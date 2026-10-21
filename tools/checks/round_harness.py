"""Builds a Luau script that plays one full round of a mini-game on a real Roblox server (Open Cloud
Luau execution) with stand-in players, using the real RoundContext and mini-game code from the
working tree. Prints errors, the end reason, results and every event the clients would have got.

    python3 tools/checks/round_harness.py HexMeltdown --players 12 > round.luau
    python3 tools/preview/luau_task.py round.luau - round.json

Luau execution runs scripts but not physics, so the stand-in players don't fall or walk: their
bot (tools/checks/bots/<Id>.luau) moves them with PivotTo and sends the actions a client would.
That's why mini-games check positions and distances on the server instead of relying on Touched.

With --client, Bot1 runs the client half like a real player in the round. --client-sits-out makes it a
spectator instead (sitting the round out: on the server with PP_SitOut, not in the round), and
--client-out-at T knocks it out T seconds into the round (ctx:Eliminate): with --ui-at, what someone
watching sees (no mode buttons for them, for one).

During the rules card: --leave-at T makes every stand-in leave T seconds in, and --spawn-fails gives
them no character, so with --bots only bots are left: the round is called off (summary: calledOff).
--reset-at T kills the last stand-in's character T seconds in (a reset); the summary's "reset" says
where it is at GO and after. --bot FILE swaps the stand-ins' script (tools/checks/bots/<Id>.luau) for
a scenario of your own, e.g. tools/checks/scenarios/*.luau.
"""

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_render import devices_luau, size_names  # noqa: E402  (the screens the engine lays the UI out on)

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "src"
BOTS = Path(__file__).resolve().parent / "bots"


def client_paths():
    paths = {}
    for path in sorted((SRC / "client").rglob("*.luau")):
        if path.name == "init.client.luau":
            continue
        rel = path.relative_to(SRC / "client").with_suffix("")
        paths["Client/" + "/".join(rel.parts)] = path
    return paths


def module_paths():
    paths = {}
    for path in sorted((SRC / "shared").rglob("*.luau")):
        rel = path.relative_to(SRC / "shared").with_suffix("")
        paths["Shared/" + "/".join(rel.parts)] = path
    for path in sorted((SRC / "server").rglob("*.luau")):
        if path.name == "init.server.luau":
            continue
        rel = path.relative_to(SRC / "server")
        parts = list(rel.with_suffix("").parts)
        if parts[-1] == "init":
            parts = parts[:-1]
        paths["Server/" + "/".join(parts)] = path
    return paths


def resolve(module: str, expr: str, is_init: bool) -> str:
    parts = module.split("/")
    if not is_init:
        pass
    # `script` of an init module is the folder itself, so its children resolve under it.
    for token in expr.split(".")[1:]:
        if token == "Parent":
            parts = parts[:-1]
        else:
            parts = parts + [token]
    return "/".join(parts)


def rewrite(module: str, text: str, is_init: bool) -> str:
    text = re.sub(r"require\((script(?:\.\w+)+)\)", lambda m: f'__require("{resolve(module, m.group(1), is_init)}")', text)
    shared = r'(?:game:GetService\("ReplicatedStorage"\)\.Shared|ReplicatedStorage\.Shared|Shared)'
    text = re.sub(r"require\(" + shared + r"((?:\.\w+)+)\)", lambda m: '__require("Shared' + m.group(1).replace(".", "/") + '")', text)
    text = text.replace('game:GetService("Players")', '__service("Players")')
    # Folder lookups such as script.Parent:FindFirstChild("Props") list bundled modules instead.
    text = re.sub(r'(script(?:\.Parent)+):FindFirstChild\("(\w+)"\)', lambda m: f'__folder("{resolve(module, m.group(1) + "." + m.group(2), is_init)}")', text)
    if module.startswith("Server/"):
        text = re.sub(r"\brequire\(", "__req(", text)  # dynamic requires of those bundled modules
    if module.startswith("Client/"):
        # Client code: client-only services get stand-ins, and folder lookups go through the bundle.
        for service in ("RunService", "StarterGui", "UserInputService"):
            text = text.replace(f'game:GetService("{service}")', f'__clientService("{service}")')
        text = re.sub(r"(script(?:\.Parent)+\.MiniGames)(?!\.)", lambda m: f'__folder("{resolve(module, m.group(1), is_init)}")', text)
        text = re.sub(r"\brequire\(", "__req(", text)
        text = text.replace("pcall(require,", "pcall(__req,")
    return re.sub(r"^export type", "type", text, flags=re.M)


def other_mode(module: str, game: str) -> bool:
    """Another mini-game's rules, brain or client half (a round only needs its own)."""
    modes = {path.stem for path in (SRC / "server" / "MiniGames").glob("*.luau")} - {"init"}
    for prefix in ("Server/MiniGames/", "Server/MiniGames/Bots/", "Client/MiniGames/", "Server/World/Props/"):
        name = module[len(prefix):] if module.startswith(prefix) else None
        if name in modes and name != game:
            return True
    return False


# The lobby run only needs a few modes for its vote (three games and Random); bundling all of them
# would go over Luau execution's 1 MB script limit as the game list grows.
LOBBY_MODES = {"FireRope", "HexMeltdown", "HoneyTrap", "BumperBallers"}


PRELUDE = (Path(__file__).resolve().parent / "gui_dump.luau").read_text() + (Path(__file__).resolve().parent / "harness_prelude.luau").read_text()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("game", help="mode id, LOBBY for the lobby with bots (uses --bots, --seconds), or SKEEBALL "
                        "for a Skee-Ball game in the lobby's arcade (tools/checks/skeeball_game.luau)")
    parser.add_argument("--players", type=int, default=12)
    parser.add_argument("--seconds", type=float, default=0, help="stop after this many seconds (0 = game length)")
    parser.add_argument("--client", action="store_true", help="also run the client half as Bot1")
    parser.add_argument("--dump-at", type=float, default=None, help="snapshot the arena this many seconds into the round")
    parser.add_argument("--map", help="write a line map (bundle line -> module) here for readable errors")
    parser.add_argument("--touch", action="store_true", help="the stand-in client is a phone (touch, no keyboard)")
    parser.add_argument("--bots", type=int, default=0, help="also add this many real bots, played by the mode's brain (MiniGames/Bots/<Id>)")
    parser.add_argument("--ui-at", help="with --client: snapshot the player's screen UI at these round times, e.g. 2,10 (see ui_render.py)")
    parser.add_argument("--sizes", help="with --ui-at: screens to lay the UI out on with the engine (ui_render.py's "
                        "names or groups; default: touch with --touch, else pc)")
    parser.add_argument("--client-sits-out", action="store_true", help="with --client: Bot1 sits this round out and watches")
    parser.add_argument("--client-out-at", type=float, default=None, help="with --client: knock Bot1 out this many seconds in")
    parser.add_argument("--leave-at", type=float, default=None, help="every stand-in leaves this many seconds into the rules card")
    parser.add_argument("--spawn-fails", action="store_true", help="the stand-ins have no character, so they can't be placed")
    parser.add_argument("--reset-at", type=float, default=None, help="the last stand-in's character dies this many seconds into the rules card")
    parser.add_argument("--bot", help="stand-in script to use instead of tools/checks/bots/<Id>.luau")
    args = parser.parse_args()

    header = "__touchMode = true\n" if args.touch else "__touchMode = false\n"
    if args.ui_at:
        header += devices_luau(size_names(args.sizes or ("touch" if args.touch else "pc")))
    out = [header + PRELUDE]
    paths = module_paths()
    if args.client:
        paths.update(client_paths())
    line_map = []  # (first line of the module body in the bundle, module name)
    line = PRELUDE.count("\n") + header.count("\n") + 1  # the __touchMode (and __devices) lines come first
    for module, path in paths.items():
        if module == "Shared/Remotes":
            continue  # replaced by the harness's recording stand-in
        lobby = args.game in ("LOBBY", "SKEEBALL")
        if not lobby and other_mode(module, args.game):
            continue  # keeps the bundle under Luau execution's 1 MB script limit
        if lobby and other_mode(module, "") and all(other_mode(module, mode) for mode in LOBBY_MODES):
            continue  # the lobby keeps LOBBY_MODES only
        is_init = path.name == "init.luau"
        body = rewrite(module, path.read_text(), is_init)
        # Blank comment-only lines (line numbers stay put for the map): Open Cloud caps a script at 1 MiB.
        body = re.sub(r"(?m)^[ \t]*--(?!\[).*$", "", body)
        out.append(f'__modules["{module}"] = function()')
        line += 1
        line_map.append((line, module))
        out.append(body)
        line += body.count("\n") + 1
        out.append("end")
        line += 1
    if args.map:
        Path(args.map).write_text(json.dumps(line_map))
    bot_file = Path(args.bot) if args.bot else BOTS / f"{args.game}.luau"
    bot = bot_file.read_text() if bot_file.exists() else "return function() end"
    out.append("local __bot = (function()\n" + bot + "\nend)()")
    client = "true" if args.client else "false"
    dump = "nil" if args.dump_at is None else str(args.dump_at)
    ui = "nil" if not args.ui_at else "{" + ", ".join(str(float(t)) for t in args.ui_at.split(",")) + "}"
    if args.game == "SKEEBALL":
        out.append((Path(__file__).resolve().parent / "skeeball_game.luau").read_text())
        out.append("return __runSkeeBall()")
    elif args.game == "LOBBY":
        out.append(f"return __runLobby({args.bots or 8}, {args.seconds or 8}, 10)")
    else:
        def number(value):
            return "nil" if value is None else str(value)

        watch = "{ sitOut = %s, outAt = %s, leaveAt = %s, spawnFails = %s, resetAt = %s }" % (
            "true" if args.client_sits_out else "false",
            number(args.client_out_at),
            number(args.leave_at),
            "true" if args.spawn_fails else "false",
            number(args.reset_at),
        )
        out.append(f'return __runRound("{args.game}", {args.players}, {args.seconds}, __bot, {client}, {dump}, {ui}, {args.bots}, {watch})')
    sys.stdout.write("\n".join(out))


if __name__ == "__main__":
    main()

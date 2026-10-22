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
watching sees (no mode buttons for them, for one). --ui-at also takes "rules" (the screen with the
rules card up) and "closed" (just after the player closed it with its ✕); the summary's "rulesCard"
says what was up each time and what the 3-2-1 showed after.

LOBBY plays the time between rounds (Config.Session's results, lobby and vote times) three times with
two stand-in people voting and --bots bots wandering: a vote everyone answers (it ends a beat after
the last vote), one somebody skips (its full time), and one where the last voter-to-be sits out. The
summary's "phases" and "votes" say when each phase started and how each vote went.

<Mode> --replay runs the real RoundManager loop with that mode as the only game, two stand-in people
and --bots bots (default 6): a vote, the round, its results' PLAY AGAIN vote passing (the same game
straight again, while someone joins), the replay, its results' vote failing, then the lobby and a
vote again. The summary's "phases", "replayVotes", "rounds", "builds" and "toasts" show it
(tools/checks/harness_prelude.luau, __runReplay).

During the rules card: --leave-at T makes every stand-in leave T seconds in, and --spawn-fails gives
them no character, so with --bots only bots are left: the round is called off (summary: calledOff).
--reset-at T kills the last stand-in's character T seconds in (a reset); the summary's "reset" says
where it is at GO and after. --drop-at T drops the last stand-in through its floor to under KillY T
seconds in (as on a device that hadn't loaded the floor); the summary's "drop" says where it is a
moment later, at GO and after (back on its spot, the same character, still in). --bot FILE swaps the
stand-ins' script (tools/checks/bots/<Id>.luau) for a scenario of your own, e.g.
tools/checks/scenarios/*.luau.

With --client, the summary's "clientHolds" lists every time the stand-in client's device held its
character (Controllers/ArrivalController): never, once it's on a floor that's there. --late-floor T
gives that device the arena T seconds late (its ground probe finds nothing until then, like a phone
still loading a big arena): it must be held where the round put it until then.

--party 1,2 (as many times as there are parties) puts those stand-ins in a party before the round,
the way players do it: through PartyService's remote, the first one invites the others and each
says JOIN. The summary's "parties" says what each stand-in's PP_Party became, "partyTeams" the team
(or role) each member was dealt and whether the party is together, and "partyToasts" what partied
people were told (a party that had to be split is told so). With --replay, any --party puts the
two people (Ann and Bo) in a party: "rounds" shows their teams in the round and in its replay.

CUP plays a whole PARTY CUP and the next cup's first round (tools/checks/cup_rounds.luau): --rounds
real rounds of the --modes in turn, with --players stand-ins and --bots real bots, then the rest of
cup 2 made up, to check the standings, the podium, the prizes, the medal and the crown.
"""

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bundling  # noqa: E402  (only the modules a run needs: Open Cloud's 1 MiB script cap)
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


def borrowed_props(game: str) -> set:
    """The other modes whose props this mode's own code asks for by name (Shark Bait's palms are
    Bumper Ballers' BumperPalm): their Props files stay in its bundle."""
    own = ""
    for path in (SRC / "server" / "MiniGames" / f"{game}.luau", SRC / "client" / "MiniGames" / f"{game}.luau",
                 SRC / "server" / "MiniGames" / "Bots" / f"{game}.luau"):
        if path.exists():
            own += path.read_text()
    names = set(re.findall(r'"(\w+)"', own))
    borrowed = set()
    for path in (SRC / "server" / "World" / "Props").glob("*.luau"):
        text = path.read_text()
        # Its prop specs, read like merge_check.sh does: `Name = {` blocks and `Name = helper(` calls
        # (not palette colours).
        specs = set(re.findall(r"^\t\t(\w+) = \{$", text, re.M))
        specs |= {name for name, helper in re.findall(r"^\t\t(\w+) = (\w+)\(", text, re.M)
                  if helper not in ("rgb", "Color3", "Vector3", "UDim2", "CFrame")}
        if path.stem != game and specs & names:
            borrowed.add(path.stem)
    return borrowed


_borrowed: dict = {}


def other_mode(module: str, game: str) -> bool:
    """Another mini-game's rules, brain or client half (a round only needs its own), or its props
    unless this mode borrows some of them."""
    modes = {path.stem for path in (SRC / "server" / "MiniGames").glob("*.luau")} - {"init"}
    for prefix in ("Server/MiniGames/", "Server/MiniGames/Bots/", "Client/MiniGames/", "Server/World/Props/"):
        name = module[len(prefix):] if module.startswith(prefix) else None
        if name in modes and name != game:
            if prefix == "Server/World/Props/" and game:
                if game not in _borrowed:
                    _borrowed[game] = borrowed_props(game)
                if name in _borrowed[game]:
                    return False
            return True
    return False


# The lobby run only needs a few modes for its vote (three games and Random); bundling all of them
# would go over Luau execution's 1 MB script limit as the game list grows.
LOBBY_MODES = {"FireRope", "HexMeltdown", "HoneyTrap", "BumperBallers"}

# CUP: the modes a cup's rounds play by default (a survival, a team, a score and a versus mode).
CUP_MODES = "FireRope,PumpAndPop,CrazyCutters,ArrowAmbush,HexMeltdown"


def cup_table(modes: list) -> str:
    """CUP: each mode's server half, bot brain and stand-in script (tools/checks/bots/<Id>.luau),
    named in full so the bundler takes them (cup_rounds.luau plays them in turn)."""
    rows = []
    for mode in modes:
        bot_path = BOTS / f"{mode}.luau"
        script = bot_path.read_text() if bot_path.exists() else "return function() end"
        brain = mode if (SRC / "server" / "MiniGames" / "Bots" / f"{mode}.luau").exists() else "Default"
        rows.append(
            f'\t{mode} = {{ Mode = function() return __require("Server/MiniGames/{mode}") end, '
            f'Brain = function() return __require("Server/MiniGames/Bots/{brain}") end, '
            f"Script = (function()\n{script}\nend)() }},"
        )
    return "__cupModes = {\n" + "\n".join(rows) + "\n}\n"


# --ui-at snapshots that aren't round times (tools/checks/harness_prelude.luau, __rulesShots).
UI_SHOTS = ("rules", "closed")


def ui_time(token: str) -> str:
    """One --ui-at entry as Luau: a round time (seconds), or one of UI_SHOTS by name."""
    token = token.strip()
    return f'"{token}"' if token in UI_SHOTS else str(float(token))


def slim(text: str) -> str:
    """Comment-only lines blanked and indentation dropped, with every line kept where it is (the line
    map and error lines stay right): Open Cloud caps a script at 1 MiB, and the biggest mode's
    bundle (Shark Bait's) is within a few dozen KB of it."""
    text = re.sub(r"(?m)^[ \t]*--(?!\[).*$", "", text)
    return re.sub(r"(?m)^[ \t]+", "", text)


PRELUDE_RAW = (Path(__file__).resolve().parent / "gui_dump.luau").read_text() + (
    Path(__file__).resolve().parent / "harness_prelude.luau"
).read_text()
PRELUDE = slim(PRELUDE_RAW)
# The collider inventory's Luau (--colliders-at): appended to the prelude when asked for.
COLLIDERS_RAW = (Path(__file__).resolve().parent / "colliders.luau").read_text()
COLLIDERS = slim(COLLIDERS_RAW)


def reachable_luau(text: str, entry: str) -> str:
    """The harness's own Luau a run can execute: its top-level code and the top-level functions it
    reaches from `entry` (__runRound, __runLobby, __runSkeeBall), so a mode's bundle doesn't carry
    what only the lobby run requires."""
    blocks, top, current = {}, [], None
    for line in text.split("\n"):
        start = re.match(r"(?:local )?function (__\w+)\(", line)
        if current is None and start:
            current = start.group(1)
            blocks[current] = [line]
        elif current is not None:
            blocks[current].append(line)
            if line == "end":
                current = None
        else:
            top.append(line)
    top_text = "\n".join(top)
    used, todo = set(), [entry] + [name for name in blocks if re.search(rf"\b{name}\b", top_text)]
    while todo:
        name = todo.pop()
        if name in used or name not in blocks:
            continue
        used.add(name)
        body = "\n".join(blocks[name][1:])
        todo.extend(other for other in blocks if other not in used and re.search(rf"\b{other}\b", body))
    return top_text + "\n" + "\n".join("\n".join(blocks[name]) for name in sorted(used))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("game", help="mode id, LOBBY for the lobby with bots (uses --bots, --seconds), or SKEEBALL "
                        "for a Skee-Ball game in the lobby's arcade (tools/checks/skeeball_game.luau)")
    parser.add_argument("--players", type=int, default=12)
    parser.add_argument("--seconds", type=float, default=0, help="stop after this many seconds (0 = game length); "
                        "LOBBY: the run lasts at least this long (the bots keep wandering)")
    parser.add_argument("--client", action="store_true", help="also run the client half as Bot1")
    parser.add_argument("--dump-at", type=float, default=None, help="snapshot the arena this many seconds into the round")
    parser.add_argument("--map", help="write a line map (bundle line -> module) here for readable errors")
    parser.add_argument("--touch", action="store_true", help="the stand-in client is a phone (touch, no keyboard)")
    parser.add_argument("--bots", type=int, default=0, help="also add this many real bots, played by the mode's brain (MiniGames/Bots/<Id>)")
    parser.add_argument("--ui-at", help="with --client: snapshot the player's screen UI at these round times, e.g. 2,10, "
                        "and/or 'rules' (the rules card up) and 'closed' (just after its ✕ closed it) (see ui_render.py)")
    parser.add_argument("--sizes", help="with --ui-at: screens to lay the UI out on with the engine (ui_render.py's "
                        "names or groups; default: touch with --touch, else pc)")
    parser.add_argument("--client-sits-out", action="store_true", help="with --client: Bot1 sits this round out and watches")
    parser.add_argument("--client-out-at", type=float, default=None, help="with --client: knock Bot1 out this many seconds in")
    parser.add_argument("--leave-at", type=float, default=None, help="every stand-in leaves this many seconds into the rules card")
    parser.add_argument("--spawn-fails", action="store_true", help="the stand-ins have no character, so they can't be placed")
    parser.add_argument("--reset-at", type=float, default=None, help="the last stand-in's character dies this many seconds into the rules card")
    parser.add_argument("--drop-at", type=float, default=None, help="the last stand-in drops through its floor this many seconds into the rules card")
    parser.add_argument("--late-floor", type=float, default=None, help="with --client: the stand-in client's device gets the arena this many seconds late")
    parser.add_argument("--bot", help="stand-in script to use instead of tools/checks/bots/<Id>.luau")
    parser.add_argument("--colliders-at", help="snapshot every part characters collide with at these round times (0 = after "
                        "Prepare), e.g. 0,5,80, for tools/checks/colliders.py; with LOBBY: the lobby's")
    parser.add_argument("--colliders-reach", type=float, default=600, help="with --colliders-at: map this far from the arena's middle")
    parser.add_argument("--no-csg", action="store_true", help="build as if CSG had failed on this server (Shapes from plain parts)")
    parser.add_argument("--modes", default=CUP_MODES, help="CUP: the modes its rounds play, in turn")
    parser.add_argument("--rounds", type=int, default=6, help="CUP: real rounds to play (a cup is 5)")
    parser.add_argument("--party", action="append", default=[], help="stand-ins in one party, e.g. 1,2 (repeat it for "
                        "more parties): formed through PartyService before the round (with --replay: Ann and Bo)")
    parser.add_argument("--replay", action="store_true", help="the real round loop with this mode as the only game: a "
                        "vote, the round, PLAY AGAIN passing, the replay, PLAY AGAIN failing, the lobby and a vote")
    args = parser.parse_args()

    header = "__touchMode = true\n" if args.touch else "__touchMode = false\n"
    header += "__noCsg = true\n" if args.no_csg else "__noCsg = false\n"
    if args.ui_at:
        header += devices_luau(size_names(args.sizes or ("touch" if args.touch else "pc")))
    prelude = PRELUDE + ("\n" + COLLIDERS if args.colliders_at is not None else "")
    out = [header + prelude]
    paths = module_paths()
    if args.client:
        paths.update(client_paths())
    lobby = args.game in ("LOBBY", "SKEEBALL")
    cup_modes = args.modes.split(",") if args.game == "CUP" else []
    available = {}
    for module, path in paths.items():
        if module == "Shared/Remotes":
            continue  # replaced by the harness's recording stand-in
        if cup_modes and other_mode(module, "") and all(other_mode(module, mode) for mode in cup_modes):
            continue  # CUP: not one of its modes'
        if not lobby and not cup_modes and other_mode(module, args.game):
            continue  # another mode's
        if lobby and other_mode(module, "") and all(other_mode(module, mode) for mode in LOBBY_MODES):
            continue  # the lobby keeps LOBBY_MODES only
        available[module] = slim(rewrite(module, path.read_text(), path.name == "init.luau"))
    # Only what this run can load (tools/checks/bundling.py): the modules the harness's own Luau asks
    # for and everything they reach. A require the bundler can't follow stops the build here.
    bot_file = Path(args.bot) if args.bot else BOTS / f"{args.game}.luau"
    bot = bot_file.read_text() if bot_file.exists() else "return function() end"
    harness = PRELUDE_RAW
    entry = "__runRound"
    if args.colliders_at is not None:
        harness += "\n" + COLLIDERS_RAW
    if args.game == "SKEEBALL":
        harness += "\n" + (Path(__file__).resolve().parent / "skeeball_game.luau").read_text()
        entry = "__runSkeeBall"
    elif args.game == "LOBBY":
        entry = "__runLobbyColliders" if args.colliders_at is not None else "__runLobby"
    elif cup_modes:
        cup_luau = (Path(__file__).resolve().parent / "cup_rounds.luau").read_text()
        harness += "\n" + cup_luau + "\n" + cup_table(cup_modes)  # (the modes it names, for the bundler)
        entry = "__runCup"
    elif args.replay:
        entry = "__runReplay"
    roots = {"Shared", "Server"} | ({"Client"} if args.client else set())
    try:
        start = bundling.seeds(reachable_luau(harness, entry) + "\n" + bot, args.game, available, roots)
        keep = bundling.closure(available, start, provided={"Shared/Remotes"})
    except bundling.BundleError as err:
        sys.exit(f"round_harness: {err}")
    line_map = []  # (first line of the module body in the bundle, module name)
    line = prelude.count("\n") + header.count("\n") + 1  # the __touchMode (and __devices) lines come first
    for module, body in available.items():
        if module not in keep:
            continue
        out.append(f'__modules["{module}"] = function()')
        line += 1
        line_map.append((line, module))
        out.append(body)
        line += body.count("\n") + 1
        out.append("end")
        line += 1
    if args.map:
        Path(args.map).write_text(json.dumps(line_map))
    out.append("local __bot = (function()\n" + bot + "\nend)()")
    client = "true" if args.client else "false"
    dump = "nil" if args.dump_at is None else str(args.dump_at)
    ui = "nil" if not args.ui_at else "{" + ", ".join(ui_time(t) for t in args.ui_at.split(",")) + "}"
    if cup_modes:
        out.append(cup_table(cup_modes))
        out.append(cup_luau)
        modes = ", ".join(json.dumps(mode) for mode in cup_modes)
        out.append(f"return __runCup({{ {modes} }}, {args.players}, {args.bots}, {args.seconds or 12}, {args.rounds})")
    elif args.game == "LOBBY" and args.colliders_at is not None:
        out.append(f"return __runLobbyColliders({args.colliders_reach})")
    elif args.game == "SKEEBALL":
        out.append((Path(__file__).resolve().parent / "skeeball_game.luau").read_text())
        out.append("return __runSkeeBall()")
    elif args.game == "LOBBY":
        out.append(f"return __runLobby({args.bots or 8}, {args.seconds or 8})")
    elif args.replay:
        out.append(f'return __runReplay("{args.game}", {args.bots or 6}, {"true" if args.party else "false"})')
    else:
        def number(value):
            return "nil" if value is None else str(value)

        parties = ", ".join("{ " + ", ".join(str(int(n)) for n in group.split(",")) + " }" for group in args.party)
        watch = "{ sitOut = %s, outAt = %s, leaveAt = %s, spawnFails = %s, resetAt = %s, dropAt = %s, lateFloor = %s, parties = %s }" % (
            "true" if args.client_sits_out else "false",
            number(args.client_out_at),
            number(args.leave_at),
            "true" if args.spawn_fails else "false",
            number(args.reset_at),
            number(args.drop_at),
            number(args.late_floor),
            "{ " + parties + " }" if args.party else "nil",
        )
        colliders = "nil"
        if args.colliders_at is not None:
            times = ", ".join(str(float(t)) for t in args.colliders_at.split(","))
            colliders = "{ times = { %s }, reach = %s }" % (times, args.colliders_reach)
        out.append(f'return __runRound("{args.game}", {args.players}, {args.seconds}, __bot, {client}, {dump}, {ui}, {args.bots}, {watch}, {colliders})')
    sys.stdout.write("\n".join(out))


if __name__ == "__main__":
    main()

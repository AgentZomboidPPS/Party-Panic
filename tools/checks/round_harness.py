"""Builds a Luau script that plays one full round of a mini-game on a real Roblox server (Open Cloud
Luau execution) with stand-in players, using the real RoundContext and mini-game code from the
working tree. Prints errors, the end reason, results and every event the clients would have got.

    python3 tools/checks/round_harness.py HexMeltdown --players 12 > round.luau
    python3 tools/preview/luau_task.py round.luau - round.json

Luau execution runs scripts but not physics, so the stand-in players don't fall or walk: their
bot (tools/checks/bots/<Id>.luau) moves them with PivotTo and sends the actions a client would.
That's why mini-games check positions and distances on the server instead of relying on Touched.
"""

import argparse
import json
import re
import sys
from pathlib import Path

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


PRELUDE = (Path(__file__).resolve().parent / "harness_prelude.luau").read_text()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("game")
    parser.add_argument("--players", type=int, default=12)
    parser.add_argument("--seconds", type=float, default=0, help="stop after this many seconds (0 = game length)")
    parser.add_argument("--client", action="store_true", help="also run the client half as Bot1")
    parser.add_argument("--dump-at", type=float, default=None, help="snapshot the arena this many seconds into the round")
    parser.add_argument("--map", help="write a line map (bundle line -> module) here for readable errors")
    parser.add_argument("--touch", action="store_true", help="the stand-in client is a phone (touch, no keyboard)")
    parser.add_argument("--ui-at", help="with --client: snapshot the player's screen UI at these round times, e.g. 2,10 (see ui_render.py)")
    args = parser.parse_args()

    out = [("__touchMode = true\n" if args.touch else "__touchMode = false\n") + PRELUDE]
    paths = module_paths()
    if args.client:
        paths.update(client_paths())
    line_map = []  # (first line of the module body in the bundle, module name)
    line = PRELUDE.count("\n") + 2  # the __touchMode line comes first
    for module, path in paths.items():
        if module == "Shared/Remotes":
            continue  # replaced by the harness's recording stand-in
        is_init = path.name == "init.luau"
        body = rewrite(module, path.read_text(), is_init)
        out.append(f'__modules["{module}"] = function()')
        line += 1
        line_map.append((line, module))
        out.append(body)
        line += body.count("\n") + 1
        out.append("end")
        line += 1
    if args.map:
        Path(args.map).write_text(json.dumps(line_map))
    bot_file = BOTS / f"{args.game}.luau"
    bot = bot_file.read_text() if bot_file.exists() else "return function() end"
    out.append("local __bot = (function()\n" + bot + "\nend)()")
    client = "true" if args.client else "false"
    dump = "nil" if args.dump_at is None else str(args.dump_at)
    ui = "nil" if not args.ui_at else "{" + ", ".join(str(float(t)) for t in args.ui_at.split(",")) + "}"
    out.append(f'return __runRound("{args.game}", {args.players}, {args.seconds}, __bot, {client}, {dump}, {ui})')
    sys.stdout.write("\n".join(out))


if __name__ == "__main__":
    main()

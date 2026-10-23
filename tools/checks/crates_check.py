"""Builds a Luau script that checks the crate season (Shared/Seasons: HOLLOW NIGHT) on a real Roblox
server (Open Cloud Luau execution), with the round harness's stand-in players and the working tree's
code: tools/checks/crates_check.luau builds the lobby's pile, altars and board, gives and opens
crates, forces a pet and the title, and buys keys through a stand-in for Roblox's purchases. The run
sets workspace PP_Harness: the boards and first-in-the-world claims stay in memory, no real
DataStore is touched and nothing is sent to other servers. (Owner: "Hollow night comes first I
want you to actually work on adding it to the game right now ... Also do all of your ideas.")

    python3 tools/checks/crates_check.py > crates.luau
    python3 tools/preview/luau_task.py crates.luau - crates.json

The result's "checks" lists every check (ok / FAIL with what it saw), "failed" the names of those that
failed, "errors" every error and warning the run logged.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bundling  # noqa: E402
import round_harness  # noqa: E402  (its module rewriting and prelude: the stand-in players, remotes)

CHECK = Path(__file__).resolve().parent / "crates_check.luau"


def main():
    header = "__touchMode = false\n__noCsg = false\n"
    paths = round_harness.module_paths()
    available = {}
    for module, path in paths.items():
        if module == "Shared/Remotes" or round_harness.other_mode(module, ""):
            continue  # the harness's Remotes stand-in; no mini-game is played
        available[module] = round_harness.slim(round_harness.rewrite(module, path.read_text(), path.name == "init.luau"))
    check = CHECK.read_text()
    harness = round_harness.PRELUDE_RAW + "\n" + check
    try:
        start = bundling.seeds(round_harness.reachable_luau(harness, "__runCrates"), "", available,
                               {"Shared", "Server", "Client"})
        keep = bundling.closure(available, start, provided={"Shared/Remotes"})
    except bundling.BundleError as err:
        sys.exit(f"crates_check: {err}")
    out = [header + round_harness.PRELUDE]
    for module, body in available.items():
        if module in keep:
            out.append(f'__modules["{module}"] = function()')
            out.append(body)
            out.append("end")
    out.append(check)
    out.append("return __runCrates()")
    sys.stdout.write("\n".join(out))


if __name__ == "__main__":
    main()

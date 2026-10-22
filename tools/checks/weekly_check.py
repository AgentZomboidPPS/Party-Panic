"""Builds a Luau script that checks the weekly leaderboard and the Hall of Fame on a real Roblox server
(Open Cloud Luau execution), with the round harness's stand-in players and the working tree's code:
tools/checks/weekly_check.luau plays rounds, drives LeaderboardService on a fake date with its
in-memory store (the run sets workspace PP_Harness: no real DataStore is touched), builds statues from
real avatars and checks the Hall's board fits. The owner asked for "Weekly leaderboard and Hall of
Fame statues of last week's top three" ("Can you work on all of that? this wont mess with what the
other workers are working on right?").

    python3 tools/checks/weekly_check.py > weekly.luau
    python3 tools/preview/luau_task.py weekly.luau - weekly.json

The result's "checks" lists every check (ok / FAIL with what it saw), "failed" the names of those that
failed, "errors" every error and warning the run logged.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bundling  # noqa: E402
import round_harness  # noqa: E402  (its module rewriting and prelude: the stand-in players, remotes)

CHECK = Path(__file__).resolve().parent / "weekly_check.luau"


def main():
    header = "__touchMode = false\n__noCsg = false\n"
    paths = round_harness.module_paths()
    paths.update(round_harness.client_paths())  # the Hall's board is drawn by a client controller
    available = {}
    for module, path in paths.items():
        if module == "Shared/Remotes" or round_harness.other_mode(module, ""):
            continue  # the harness's Remotes stand-in; no mini-game is played
        available[module] = round_harness.slim(round_harness.rewrite(module, path.read_text(), path.name == "init.luau"))
    check = CHECK.read_text()
    harness = round_harness.PRELUDE_RAW + "\n" + check
    try:
        start = bundling.seeds(round_harness.reachable_luau(harness, "__runWeekly"), "", available,
                               {"Shared", "Server", "Client"})
        keep = bundling.closure(available, start, provided={"Shared/Remotes"})
    except bundling.BundleError as err:
        sys.exit(f"weekly_check: {err}")
    out = [header + round_harness.PRELUDE]
    for module, body in available.items():
        if module in keep:
            out.append(f'__modules["{module}"] = function()')
            out.append(body)
            out.append("end")
    out.append(check)
    out.append("return __runWeekly()")
    sys.stdout.write("\n".join(out))


if __name__ == "__main__":
    main()

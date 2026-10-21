"""Prints a readable summary of a round_harness run (errors mapped to module:line), and can save
the arena snapshot (--dump-at) for tools/preview/render.py.

    python3 tools/checks/summarize.py round.json round.map.json
    python3 tools/checks/summarize.py round.json round.map.json --dump arena.json
"""
import argparse
import bisect
import json
import re

parser = argparse.ArgumentParser()
parser.add_argument("results", help="the file luau_task.py saved")
parser.add_argument("map", nargs="?", help="the --map file round_harness.py wrote")
parser.add_argument("--dump", help="write the arena snapshot here (needs --dump-at in the run)")
parser.add_argument("--log", type=int, default=60, help="how many log lines to show")
args = parser.parse_args()

d = json.load(open(args.results))
d = d[0] if isinstance(d, list) else d
d = json.loads(d) if isinstance(d, str) else d
if d is None:
    raise SystemExit("No results: the Luau task failed before returning (see the luau_task.py output).")
line_map = json.load(open(args.map)) if args.map else []
starts = [line for line, _ in line_map]


def where(n: int) -> str:
    i = bisect.bisect_right(starts, n) - 1
    if i < 0:
        return f"prelude:{n}"
    return f"{line_map[i][1]}:{n - line_map[i][0] + 1}"


def fix(text: str) -> str:
    text = re.sub(r"Line (\d+)", lambda m: "Line " + where(int(m.group(1))), text)
    return re.sub(r"TaskScript:(\d+)", lambda m: where(int(m.group(1))), text)


for key in ["bots", "brain", "prepare", "prepareSeconds", "arenaParts", "start", "endReason", "roundSeconds", "stop", "cleanup",
            "destroy", "arenaLeftovers", "sharedLeftovers", "winningTeam", "clientGuiDuringResults",
            "clientModeGuisAfterCleanup"]:
    if key in d:
        print(f"{key:28s}", fix(str(d.get(key))))
results = d.get("results")
if isinstance(results, list):
    print("results:")
    for row in results:
        print("   ", row)
else:
    print("results:", results)
seen = {}
for error in d.get("errors", []):
    key = fix(error.split("\n")[0])
    seen[key] = seen.get(key, 0) + 1
print(f"errors ({len(d.get('errors', []))}):")
for key, count in seen.items():
    print(f"    x{count} {key[:400]}")
logs = d.get("log", [])
print(f"log ({len(logs)}):")
for line in logs[: args.log]:
    print("   ", fix(line))
print("event counts:", json.dumps(d.get("eventCounts", {}))[:1200])
if args.dump:
    if not d.get("dump"):
        raise SystemExit("This run has no arena snapshot - pass --dump-at to round_harness.py")
    json.dump(d["dump"], open(args.dump, "w"))
    print("saved arena snapshot:", args.dump, "parts:", len(d["dump"]["parts"]))

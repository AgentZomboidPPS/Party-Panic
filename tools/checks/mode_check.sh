#!/usr/bin/env bash
# Checks one mini-game end to end: code checks, a 12-player round with the client half, a round
# with real bots, and its HUD on phones (the rules card, the card just after its ✕ closed it, and the
# round). Prints a short report; output files go to $OUT (default /tmp/mode_check/<Id>).
#
#   tools/checks/mode_check.sh FireRope
#   SKIP_CODE=1 tools/checks/mode_check.sh FireRope     # just the rounds
set -uo pipefail
ID="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${OUT:-/tmp/mode_check/$ID}"
mkdir -p "$OUT"
cd "$ROOT"

if [ -z "${SKIP_CODE:-}" ]; then
	echo "== code checks"
	stylua --check src tools/checks >/dev/null 2>&1 && echo "stylua ok" || echo "STYLUA: run stylua src tools/checks"
	selene src 2>&1 | tail -3 | tr '\n' ' '; echo
	rojo sourcemap -o sourcemap.json >/dev/null 2>&1
	luau-lsp analyze --definitions=@roblox=globalTypes.d.luau --sourcemap=sourcemap.json src 2>&1 | grep -v "INFO\|WARN\] client" | head -10
	lune run tests/run 2>&1 | tail -1
	rojo build -o "$OUT/build.rbxl" 2>&1 | tail -1
fi

run() { # name, harness args...
	local name="$1"
	shift
	python3 tools/checks/round_harness.py "$ID" "$@" --map "$OUT/$name.map.json" >"$OUT/$name.luau"
	python3 tools/preview/luau_task.py "$OUT/$name.luau" - "$OUT/$name.json" >"$OUT/$name.task.log" 2>&1
	grep -v "^LOG" "$OUT/$name.task.log" | grep -q "state COMPLETE" || { echo "!! $name: task failed:"; grep -v "^LOG" "$OUT/$name.task.log" | tail -3; return; }
	python3 tools/checks/summarize.py "$OUT/$name.json" "$OUT/$name.map.json" >"$OUT/$name.summary.txt" 2>&1
	echo "== $name"
	grep -E "^(bots|brain|prepare |rulesCard|start |endReason|roundSeconds|arenaLeftovers|sharedLeftovers|clientModeGuisAfterCleanup)" "$OUT/$name.summary.txt"
	sed -n '/^results:/,/^errors/p' "$OUT/$name.summary.txt" | head -8
	sed -n '/^errors/,/^log/p' "$OUT/$name.summary.txt" | head -12
}

run players12 --players 12 --client --dump-at 8
run bots --players 2 --bots 10 --client
run phone --players 6 --client --touch --seconds 20 --ui-at rules,closed,5,15
python3 tools/checks/ui_render.py "$OUT/phone.json" "$OUT/ui" 2>&1 | grep -v "^wrote" | sed 's/^ */   ui: /' | sort | uniq -c | head -20
echo "files in $OUT"

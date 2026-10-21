#!/usr/bin/env bash
# Checks a mini-game branch after `git merge --no-ff --no-commit <branch>` in the main checkout,
# before committing the merge:
#   tools/checks/merge_check.sh <ModeId>
# 1. every added/changed prop glb: the face check on the committed file, and a regeneration with the
#    merged generator code compared against it (props that really differ need re-uploading)
# 2. every prop spec in src/server/World/Props/<ModeId>.luau has an AssetId the asset tools can see
#    (its own `Name = { ... AssetId = ... }` block; an id hidden in a helper call is never granted)
# 3. stylua, selene, luau-lsp, the lune tests
# Then run tools/checks/mode_check.sh <ModeId> and, if the arena changed, tools/preview/make_preview.py.
set -uo pipefail
ID="$1"
cd "$(dirname "$0")/../.."
CHANGED=$(git diff --cached --name-only --diff-filter=AM HEAD -- assets/meshes | grep "\.glb$" || true)
echo "== changed meshes: $(echo "$CHANGED" | xargs -n1 basename 2>/dev/null | sed 's/\.glb$//' | tr '\n' ' ')"
if [ -n "$CHANGED" ]; then
	echo "-- facing of the committed glbs:"
	python3 tools/checks/mesh_orientation.py $CHANGED | tail -6
	echo "-- regenerated with the merged code vs committed:"
	python3 tools/checks/regen_compare.py --changed | tail -12
fi
echo "== asset ids seen by the tools for $ID:"
python3 - "$ID" <<'EOF'
import os, re, sys
sys.path.insert(0, "tools/checks")
from asset_status import collect
ids = collect()
path = f"src/server/World/Props/{sys.argv[1]}.luau"
text = open(path).read() if os.path.exists(path) else ""
names = []
for m in re.finditer(r"^\t\t(\w+) = \{\n", text, re.M):  # spec blocks (palettes have no Height/Fallback)
    end = re.compile(r"^\t\t\},?$", re.M).search(text, m.end())
    block = text[m.end(): end.start() if end else len(text)]
    if re.search(r"\b(Height|Fallback|AssetId) =", block):
        names.append(m.group(1))
for m in re.finditer(r"^\t\t(\w+) = (\w+)\(", text, re.M):  # specs made by a helper call
    if m.group(2) not in ("rgb", "Color3", "Vector3", "UDim2", "CFrame"):
        names.append(m.group(1))
missing = [n for n in names if f"mesh:{n}" not in ids]
print(f"{len(names)} props in {path}; without an AssetId the tools can see: {missing or 'none'}")
EOF
echo "== code checks"
stylua --check src tools/checks tests >/dev/null 2>&1 && echo "stylua ok" || echo "STYLUA FAIL (run: stylua src tools/checks tests)"
selene src 2>&1 | tail -1
rojo sourcemap -o sourcemap.json >/dev/null 2>&1
luau-lsp analyze --definitions=@roblox=globalTypes.d.luau --sourcemap=sourcemap.json src 2>&1 | grep -v "INFO\|WARN\] client" | head -5
lune run tests/run 2>&1 | tail -1

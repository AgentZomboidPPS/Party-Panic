"""Shows which uploaded meshes players' devices couldn't load (Services/ClientReports records them
in the PP_ClientReports data store; this reads it on a Roblox test server).

    python3 tools/checks/client_reports.py
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools" / "preview"))
from luau_task import run  # noqa: E402

SCRIPT = """
local store = game:GetService("DataStoreService"):GetDataStore("PP_ClientReports")
local out = {}
local pages = store:ListKeysAsync()
while true do
	for _, key in pages:GetCurrentPage() do
		local ok, value = pcall(store.GetAsync, store, key.KeyName)
		out[key.KeyName] = if ok then value else tostring(value)
	end
	if pages.IsFinished then
		break
	end
	pages:AdvanceToNextPageAsync()
end
return game:GetService("HttpService"):JSONEncode(out)
"""

task, _ = run(SCRIPT)
results = (task.get("output") or {}).get("results") or []
if not results:
    sys.exit(f"Couldn't read the reports: {json.dumps(task.get('error'))[:500]}")
reports = json.loads(results[0]) or {}
if isinstance(reports, list):  # an empty Luau table encodes as []
    reports = {}
if not reports:
    print("No reports yet (a player's device sends one ~15 s after joining, and one per round).")
for key, entry in sorted(reports.items(), key=lambda item: -(item[1] or {}).get("Time", 0) if isinstance(item[1], dict) else 0):
    if not isinstance(entry, dict):
        print(key, entry)
        continue
    failed = entry.get("Failed") or {}
    print(f"{key}: {len(failed)} of {entry.get('Checked')} meshes failed ({entry.get('Where')}, touch={entry.get('Touch')}, place v{entry.get('PlaceVersion')})")
    for content, status in list(failed.items())[:20]:
        print(f"    {content}  {status}")

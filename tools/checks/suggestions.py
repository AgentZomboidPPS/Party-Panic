"""Reads the suggestion box (owner: "Can we add a suggestion box?"): what players sent with the
Settings window's 💡 button or the mailbox in the lobby. Services/SuggestionService keeps each one in
the PP_Suggestions data store, one key per UTC hour; this reads the last few days on a Roblox test
server and prints them newest first: when, what it's about, who sent it and their words.

    python3 tools/checks/suggestions.py              # the last 7 days
    python3 tools/checks/suggestions.py --days 30    # further back
    python3 tools/checks/suggestions.py --kind Bug   # one kind: Game, Better, Bug or Other
    python3 tools/checks/suggestions.py --test       # what the check tools sent (PP_Suggestions_Test)
    python3 tools/checks/suggestions.py --json       # the suggestions as JSON

Players' own words, as typed (tidied, never shown in the game): read them, don't paste them anywhere
public.
"""

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "preview"))
from luau_task import run  # noqa: E402

KINDS = {"Game": "🎮 New game", "Better": "⭐ Improve", "Bug": "🐛 Bug", "Other": "💬 Other"}

SCRIPT = """
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("%s")
local out = {}
-- A fresh test server has little request budget (listing especially): wait for it, and try a
-- throttled request again a few seconds later.
local function call(kind, fn, ...)
	for _ = 1, 20 do
		local waited = 0
		while DataStoreService:GetRequestBudgetForRequestType(kind) < 1 and waited < 30 do
			task.wait(1)
			waited += 1
		end
		local ok, result = pcall(fn, ...)
		if ok then
			return true, result
		elseif not string.find(tostring(result), "hrottl") then
			return false, result
		end
		task.wait(5)
	end
	return false, "still throttled"
end
local LIST, GET = Enum.DataStoreRequestType.ListAsync, Enum.DataStoreRequestType.GetAsync
for _, day in { %s } do
	local okList, pages = call(LIST, store.ListKeysAsync, store, day)
	assert(okList, pages)
	while true do
		for _, key in pages:GetCurrentPage() do
			local okGet, value = call(GET, store.GetAsync, store, key.KeyName)
			out[key.KeyName] = if okGet then value else tostring(value)
		end
		if pages.IsFinished then
			break
		end
		call(LIST, pages.AdvanceToNextPageAsync, pages)
	end
end
return game:GetService("HttpService"):JSONEncode(out)
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--days", type=int, default=7, help="how many days back (default 7: today and 6 before)")
    parser.add_argument("--kind", choices=sorted(KINDS), help="only this kind")
    parser.add_argument("--test", action="store_true", help="read the check tools' store, PP_Suggestions_Test")
    parser.add_argument("--json", action="store_true", help="print the suggestions as JSON")
    args = parser.parse_args()

    store = "PP_Suggestions_Test" if args.test else "PP_Suggestions"
    now = time.time()
    days = [time.strftime("%Y-%m-%d", time.gmtime(now - 86400 * back)) for back in range(max(1, args.days))]
    script = SCRIPT % (store, ", ".join(f'"{day}"' for day in days))
    task, _ = run(script)
    if task.get("state") != "COMPLETE":
        raise SystemExit(f"the test server's task {task.get('state')}: {json.dumps(task.get('error'))[:500]}")
    result = ((task.get("output") or {}).get("results") or [None])[0]
    keys = json.loads(result) if isinstance(result, str) else result
    entries = []
    for key, value in (keys or {}).items():
        if not isinstance(value, list):
            print(f"{key}: couldn't read ({value})", file=sys.stderr)
            continue
        entries.extend(entry for entry in value if isinstance(entry, dict))
    if args.kind:
        entries = [entry for entry in entries if entry.get("K") == args.kind]
    entries.sort(key=lambda entry: entry.get("T", 0), reverse=True)
    if args.json:
        print(json.dumps(entries, ensure_ascii=False, indent=1))
        return
    if not entries:
        print(f"No suggestions in the last {args.days} day(s) ({store}).")
        return
    counts = {}
    for entry in entries:
        counts[entry.get("K")] = counts.get(entry.get("K"), 0) + 1
    print(f"{len(entries)} suggestion(s) in the last {args.days} day(s) ({store}): "
          + ", ".join(f"{KINDS.get(kind, kind)} {count}" for kind, count in sorted(counts.items(), key=lambda kv: -kv[1])))
    for entry in entries:
        when = datetime.fromtimestamp(entry.get("T", 0), timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        print(f"\n{when}  {KINDS.get(entry.get('K'), entry.get('K'))}  from {entry.get('N')} "
              f"({entry.get('U')}, version {entry.get('V')})")
        for line in str(entry.get("S", "")).splitlines():
            print(f"    {line}")


if __name__ == "__main__":
    main()

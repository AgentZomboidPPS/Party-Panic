"""Shows which mini-games players like and which they don't: the 👍 / 👎 on the results card (owner:
"lets add to the backburner a away for players to downvote a minigame and then we can harvest that
data to disable minigames in the future." Then: "Also while you make the downvote for mini games can
you also do an upvote one so we can see if players like it"). Services/RatingService keeps running
totals per game and ISO week in the PP_GameRatings data store; this reads the last 4 weeks on a Roblox
test server and prints one row per game, best-liked first:

    plays     people who played it (bots never count)
    👍 / 👎    the share of those people who tapped 👍 ("Loved it") or 👎 ("Not for me")
    net       👍 minus 👎, over every vote: +100 = everyone loved it, -100 = nobody did
    voters    different people who voted (about: each week's are counted on their own)
    again     PLAY AGAIN answers that were yes
    vote wins times it won the game vote, of the times it was on it by name

Games with fewer than 30 votes are listed after the rest: too few to judge yet. Under the table, the
5 most liked and the 5 least liked. To switch a game off: Enabled = false in
src/shared/GameDefinitions.luau.

    python3 tools/checks/game_ratings.py            # the real totals
    python3 tools/checks/game_ratings.py --weeks 8  # further back
    python3 tools/checks/game_ratings.py --test     # what the check tools wrote (PP_GameRatings_Test)
    python3 tools/checks/game_ratings.py --json     # the rows as JSON

The sums and the order are GameRatings.Summary's (src/shared/Logic/GameRatings.luau, sent along with
the script, so they're the same rules the spec checks).
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "preview"))
from luau_task import run  # noqa: E402

parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
parser.add_argument("--weeks", type=int, default=4, help="how many weeks back (default 4: this one and 3 before)")
parser.add_argument("--test", action="store_true", help="read the check tools' store, PP_GameRatings_Test")
parser.add_argument("--json", action="store_true", help="print the rows as JSON")
args = parser.parse_args()

# (Sent inside a function, where Luau takes type aliases but not exported ones.)
logic = (ROOT / "src" / "shared" / "Logic" / "GameRatings.luau").read_text().replace("export type ", "type ")
store = "PP_GameRatings_Test" if args.test else "PP_GameRatings"

SCRIPT = """
local GameRatings = (function()
%s
end)()
local store = game:GetService("DataStoreService"):GetDataStore("%s")
local weeks = GameRatings.LastWeeks(os.time(), %d)
local records = {}
local read = 0
for _, week in weeks do
	local pages = store:ListKeysAsync(week .. "/")
	while true do
		for _, key in pages:GetCurrentPage() do
			local game = string.match(key.KeyName, "^[^/]+/(.+)$")
			local ok, value = pcall(store.GetAsync, store, key.KeyName)
			if game and ok then
				records[game] = records[game] or {}
				table.insert(records[game], value)
				read += 1
			end
		end
		if pages.IsFinished then
			break
		end
		pages:AdvanceToNextPageAsync()
	end
end
return game:GetService("HttpService"):JSONEncode({ weeks = weeks, keys = read, rows = GameRatings.Summary(records) })
""" % (logic, store, args.weeks)

task, _ = run(SCRIPT)
results = (task.get("output") or {}).get("results") or []
if not results:
    sys.exit(f"Couldn't read the ratings: {json.dumps(task.get('error'))[:500]}")
data = json.loads(results[0])
rows = data.get("rows") or []
if isinstance(rows, dict):  # an empty Luau table encodes as {}
    rows = []

if args.json:
    print(json.dumps(data, indent=2, ensure_ascii=False))
    sys.exit(0)

# Game names and which games are on (GameDefinitions).
definitions = (ROOT / "src" / "shared" / "GameDefinitions.luau").read_text()
names, enabled = {}, {}
for block in re.findall(r"\n\t\{\n(.*?)\n\t\},", definitions, re.S):
    game_id = re.search(r'Id = "(\w+)"', block)
    name = re.search(r'Name = "([^"]+)"', block)
    if game_id:
        names[game_id.group(1)] = name.group(1) if name else game_id.group(1)
        enabled[game_id.group(1)] = "Enabled = false" not in block

weeks = data.get("weeks") or []
print(f"{store}: weeks {weeks[-1] if weeks else '?'} to {weeks[0] if weeks else '?'} ({data.get('keys', 0)} game-weeks)")
if not rows:
    print("No votes yet. Every results card asks for them; check back once people have played.")
    sys.exit(0)


def pct(value) -> str:
    return "-" if value is None else f"{round(value * 100)}%"


def line(row) -> str:
    name = names.get(row["Game"], row["Game"]) + ("" if enabled.get(row["Game"], True) else " (off)")
    net = round(row["Net"] * 100)
    wins = f"{row['VoteWins']}/{row['VoteOffers']}" if row["VoteOffers"] else "-"
    return (f"{name[:22]:<22} {row['Plays']:>6} {pct(row['UpRate']):>5} {pct(row['DownRate']):>5} "
            f"{net:>+5} {row['Votes']:>6} {row['Voters']:>6} {pct(row.get('ReplayRate')):>6} {wins:>9}")


header = f"{'game':<22} {'plays':>6} {'👍':>4} {'👎':>4} {'net':>5} {'votes':>6} {'voters':>6} {'again':>6} {'vote wins':>9}"
judged = [row for row in rows if row["Judged"]]
early = [row for row in rows if not row["Judged"]]
print()
print(header)
for row in judged:
    print(line(row))
if early:
    print()
    print("Too few votes to judge yet (under 30):")
    for row in early:
        print(line(row))
played = {row["Game"] for row in rows}
unplayed = [names[game] for game in names if enabled[game] and game not in played]
if unplayed:
    print()
    print(f"Not played in these weeks: {', '.join(unplayed)}")

print()
if judged:
    top = judged[:5]
    bottom = [row for row in reversed(judged) if row not in top][:5]
    print("Most liked: " + ", ".join(f"{names.get(r['Game'], r['Game'])} ({round(r['Net'] * 100):+d})" for r in top))
    if bottom:
        print("Least liked: " + ", ".join(f"{names.get(r['Game'], r['Game'])} ({round(r['Net'] * 100):+d})" for r in bottom))
    print("A game near the bottom with a low PLAY AGAIN rate and few vote wins is the one to switch off "
          "(Enabled = false in src/shared/GameDefinitions.luau).")
else:
    print("No game has 30 votes yet, so nothing to judge: check back in a week or two.")

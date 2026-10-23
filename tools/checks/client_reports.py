"""Shows which uploaded meshes and sounds players' devices couldn't load, and whether the music
really plays for them (Services/ClientReports records them in the PP_ClientReports data store;
this reads it on a Roblox test server). Mini-games' own trouble reports are there too (keys m<UserId>),
e.g. what held a Shark Bait player who got stuck, and each device's bot reports from its last few rounds
(keys b<UserId>, Controllers/BotWatchController): how the bots moved on that screen.

    python3 tools/checks/client_reports.py           # everything
    python3 tools/checks/client_reports.py --bots    # only the bot reports
    python3 tools/checks/client_reports.py --version 48   # what devices on place version 48 couldn't
                                                          # load, and a count of the devices that reported

After a publish, --version <new version> is the check that everyone sees everything: each device
reports the meshes and images it couldn't load, and each server keeps a tally of those reports for
its version of the place (Services/ClientReports, keys v<version>_<server>, saved about once a
minute). This reads the tallies and the reports of any player whose device couldn't load something.

    python3 tools/checks/client_reports.py
"""

import json
import sys
import time
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

# --version: the servers' tallies for that version, and the reports of players they name.
VERSION_SCRIPT = """
local store = game:GetService("DataStoreService"):GetDataStore("PP_ClientReports")
local out = {}
local pages = store:ListKeysAsync("v%d_")
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
local asked = 0
for _, tally in table.clone(out) do
	for _, userId in (if type(tally) == "table" and type(tally.Players) == "table" then tally.Players else {}) do
		local key = "u" .. tostring(userId)
		if out[key] == nil and asked < 40 then
			asked += 1
			local ok, value = pcall(store.GetAsync, store, key)
			out[key] = if ok then value else tostring(value)
		end
	end
end
return game:GetService("HttpService"):JSONEncode(out)
"""

if "--version" in sys.argv[1:]:
    wanted = int(sys.argv[sys.argv.index("--version") + 1])
    task, _ = run(VERSION_SCRIPT % wanted)
    results = (task.get("output") or {}).get("results") or []
    if not results:
        sys.exit(f"Couldn't read the reports: {json.dumps(task.get('error'))[:500]}")
    found = json.loads(results[0]) or {}
    if isinstance(found, list):
        found = {}
    tallies = {k: v for k, v in found.items() if k.startswith("v") and isinstance(v, dict)}
    devices = sum(t.get("Devices") or 0 for t in tallies.values())
    phones = sum(t.get("Touch") or 0 for t in tallies.values())
    checked = sum(t.get("Checked") or 0 for t in tallies.values())
    trouble = sum(t.get("Trouble") or 0 for t in tallies.values())
    failed: dict[str, str] = {}
    for t in tallies.values():
        failed.update(t.get("Failed") or {})
    print(f"Place version {wanted}: {len(tallies)} servers, {devices} players' devices reported "
          f"({phones} phones or tablets), {checked} mesh and image loads checked.")
    if not tallies:
        print("No tallies yet: a server saves its tally about a minute after its first report "
              "(a device reports ~15 s after joining, then in each new arena).")
    elif trouble == 0:
        print("Every device loaded every mesh and image.")
    else:
        print(f"{trouble} players' devices couldn't load something:")
        for content, status in list(failed.items())[:40]:
            print(f"    {content}  {status}")
        for key, entry in found.items():
            if key.startswith("u") and isinstance(entry, dict):
                print(f"  {key}: {len(entry.get('Failed') or {})} of {entry.get('Checked')} failed "
                      f"({entry.get('Where')}, touch={entry.get('Touch')}, place v{entry.get('PlaceVersion')})")
    sys.exit(1 if trouble else 0)

task, _ = run(SCRIPT)
results = (task.get("output") or {}).get("results") or []
if not results:
    sys.exit(f"Couldn't read the reports: {json.dumps(task.get('error'))[:500]}")
reports = json.loads(results[0]) or {}
if isinstance(reports, list):  # an empty Luau table encodes as []
    reports = {}
if not reports:
    print("No reports yet (a player's device sends one ~15 s after joining, and one per round).")


def print_bots(key: str, entry: dict):
    """A device's bot reports, newest first: one block per round (BotWatchController's kinds: snap =
    drawn position jumped over 5 studs in a frame, jerk = over 2 (counted only), hover = feet over 2
    studs above anything under it for 0.5 s while not rising or falling, head = standing on someone,
    seat = somebody sat (with the seat's name), me* = the player's own character, invisible = the
    player stood on a nearly invisible part, bots = bot characters seen, watched = bot-seconds watched;
    Server = the server's counts on each body that round: Retakes = taken back from a player's device,
    Drops = dropped by the server (Spleef's net), Clamps = speed clamped after a shove)."""
    for report in entry.get("Reports") or []:
        when = time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime(report.get("Time") or 0))
        counts = report.get("Counts") or {}
        shown = " ".join(f"{name}={value}" for name, value in sorted(counts.items()))
        print(f"{key}: bots in {report.get('Where')} at {when} (place v{report.get('PlaceVersion')}, "
              f"touch={report.get('Touch')}, playing={report.get('In')}, {report.get('Seconds')} s): {shown}")
        for line in report.get("Events") or []:
            print(f"    {line}")
        if report.get("Server"):
            print(f"    server: {'; '.join(report['Server'])}")
        if report.get("Anchored"):
            print(f"    anchored: {', '.join(report['Anchored'])}")


def newest(item) -> float:
    entry = item[1]
    if not isinstance(entry, dict):
        return 0
    reports = entry.get("Reports") or [{}]
    return -(entry.get("Time") or reports[0].get("Time") or 0)


only_bots = "--bots" in sys.argv[1:]
for key, entry in sorted(reports.items(), key=newest):
    if not isinstance(entry, dict):
        print(key, entry)
        continue
    if entry.get("Kind") == "BotsLog":
        print_bots(key, entry)
        continue
    if only_bots:
        continue
    if entry.get("Kind") == "Tally":
        print(f"{key}: a server's tally on place v{entry.get('PlaceVersion')}: {entry.get('Devices')} devices, "
              f"{entry.get('Trouble')} couldn't load something")
        continue
    failed = entry.get("Failed") or {}
    if entry.get("Kind") == "Mode":
        # A mini-game's own trouble report (ClientReports.Record): e.g. what held someone who got stuck.
        when = time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime(entry.get("Time") or 0))
        print(f"{key}: {entry.get('Mode')} {entry.get('What')} at {when} (place v{entry.get('PlaceVersion')})")
        print(f"    {entry.get('Text')}")
        continue
    if entry.get("Kind") == "Sound":
        music = entry.get("Music") or {}
        print(f"{key}: {len(failed)} of {entry.get('Checked')} sounds failed ({entry.get('Where')}, touch={entry.get('Touch')}, place v{entry.get('PlaceVersion')})")
        print(f"    music {music.get('Track')}: loaded={music.get('Loaded')} playing={music.get('Playing')} at {music.get('Time')} s, "
              f"volume {music.get('Volume')}, loudness {music.get('Loudness')} (silent = 0), music setting {music.get('Level')}, "
              f"Roblox volume {entry.get('Master')}")
        if entry.get("Control"):
            print(f"    a public Roblox library sound on this device: {entry.get('Control')}")
        for line in entry.get("Messages") or []:
            print(f"    console: {line}")
        if entry.get("Policy"):
            print(f"    policy: {entry.get('Policy')}")
    else:
        print(f"{key}: {len(failed)} of {entry.get('Checked')} meshes and images failed ({entry.get('Where')}, touch={entry.get('Touch')}, place v{entry.get('PlaceVersion')})")
    for content, status in list(failed.items())[:20]:
        print(f"    {content}  {status}")


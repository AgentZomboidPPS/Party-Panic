# Last Dancer (`LastDancer`, game 31): how it works and how to change it

A rhythm dance-off, built in one session from Claude's own pitch ("Let's make it"). The rules, numbers and the owner-facing
summary are in [MINIGAME_BACKLOG.md](../MINIGAME_BACKLOG.md) (31). This page is for whoever tunes or extends it.

## The pieces

| File | What it is |
| --- | --- |
| `tools/music/songs/LastDancer.py` | the song "Mirror Ball Showdown" (120 bpm, 8 intro bars + 32 round bars) **and the chart**: `CHART_BARS`, one string of 16 steps per bar, a digit for a note in lane 1-4. The lead plays every note (lane = root, third, fifth, octave of that bar's chord) |
| `tools/music/lastdancer_chart.py` | writes `src/shared/LastDancerChart.luau` from the song (`--check` fails if it is stale); refuses a chart that breaks the rules (notes on eighths, none closer than an eighth, a free last beat before every cut) |
| `src/shared/Logic/LastDancer.luau` | the rules as plain math: windows, groove, the cut schedule, the press-time clamp. Pure, unit-tested (`tests/LastDancer.spec.luau`, which also checks the generated chart) |
| `src/server/MiniGames/LastDancer.luau` | the round: the floor, judging every `Tap`, misses, the cuts (decided 0.3 s early, tiles drop on the downbeat), results |
| `src/server/MiniGames/Bots/LastDancer.luau` | bots tap the chart with skill-based accuracy (calibrated in the file's header) |
| `src/client/MiniGames/LastDancer.luau` | the highway, pads, instant feedback (same logic), groove meter, cut line, SYNC, standings, the dance, the club mood |
| `src/server/World/Props/LastDancer.luau`, `tools/meshgen/props/LastDancer.py`, `assets/meshes/LastDancer*` | the mirror ball and speaker stack (meshes made, **not uploaded**: fallbacks are used until then) |
| `tools/checks/bots/LastDancer.luau` | the round harness's scripted dancers: good, ok, sloppy, idle, masher; checks the idle one and the masher are cut first |

## Change the chart or the song

1. Edit `CHART_BARS` (or the arrangement) in `tools/music/songs/LastDancer.py`.
2. `python3 tools/music/lastdancer_chart.py` (chart), `python3 tools/music/modes.py render LastDancer` (audio) and
   `python3 tools/music/modes.py check` (length against the round: the round part must stay 32 bars = 64 s = `Duration`).
3. If the pack is already uploaded, `modes.py pack --replace ModePack7` and a new upload; if not, `modes.py pack`.
4. `lune run tests/run`.

The tempo, the phrase length (4 bars) and the round (8 phrases) are constants in `Logic/LastDancer.luau` **and** the song:
change both together (`BPM`, `PHRASES`, `FIRST_CUT`, `LAST_CUT`, `FINALISTS`) and the round's `Duration`.

## Tuning knobs (all in `Logic/LastDancer.luau`)

- `WINDOW` (65 / 115 / 170 ms): how forgiving a tap is. `PULL` and `FORM`: how fast groove moves (a stray pulls half as hard
  as a miss; four-pad mashing makes ~8 strays a hit, so it never pays). `Target`: how the cuts are spread.
- Bots: `0.62 + 0.3 * skill` of the notes, `0.11 - 0.07 * skill` s off, in `Bots/LastDancer.luau`; its header has the measured
  groove for each skill and for human profiles (a simulation with the real judging: pro ~94%, good ~82%, casual ~60%).

## Checked, and what only a real device can show

Checked here: unit tests (273), stylua, selene, luau-lsp, a 12-player round, a round with 10 real bots, rounds of 2, 3, 5, 8
players, the phone HUD at five sizes (0 problems), no z-fighting, the arena rendered in Blender, mesh orientation.
**Not checkable without a real client** (the test server has no input, audio, physics or GUI engine):

- how the audio feels against the notes on real phones (the SYNC buttons are the safety net; judge it with Bluetooth too);
- the dance poses (the R15 joint offsets are written from the rig's geometry; look at them once: arms should go up and out);
- tiles dropping with the dancers on them, the red flash, the club mood (midnight, purple haze), the lights on phones;
- tapping on glass: two fingers, a thumb resting on the screen edge, the pads' size on a small phone.

## Going live

The mode keeps itself out of the vote on live servers until its song is in the game. To switch it on: upload the song
(`python3 tools/upload_assets.py --user-id 11690979745 --what modes --dry-run`, then without `--dry-run`: it uses 1 of the
owner's 10 audio uploads a month), optionally the meshes (`--what meshes --only LastDancerMirrorBall,LastDancerSpeaker`),
publish, restart the servers. Then add "💃 LAST DANCER" to `docs/STORE_DESCRIPTION.txt` (31 mini-games) and make its portal
preview (`tools/preview/make_preview.py LastDancer`).

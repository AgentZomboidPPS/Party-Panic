# Last Dancer (`LastDancer`, game 31): how it works and how to change it

A rhythm dance-off on arcade dance mats, built in one session from Claude's own pitch ("Let's make it"; then "I want it to
show your character basically playing on a DDR mat from an arcade"). The rules, numbers and the owner-facing
summary are in [MINIGAME_BACKLOG.md](../MINIGAME_BACKLOG.md) (31). This page is for whoever tunes or extends it.

## The pieces

| File | What it is |
| --- | --- |
| `tools/music/songs/LastDancer.py` | the song "Mirror Ball Showdown" (120 bpm, 8 intro bars + 32 round bars) **and the chart**: `CHART_BARS`, one string of 16 steps per bar, a digit for a note in lane 1-4. The lead plays every note (lane = root, third, fifth, octave of that bar's chord) |
| `tools/music/lastdancer_chart.py` | writes `src/shared/LastDancerChart.luau` from the song (`--check` fails if it is stale); refuses a chart that breaks the rules (notes on eighths, none closer than an eighth, a free last beat before every cut) |
| `src/shared/Logic/LastDancer.luau` | the rules as plain math: windows, groove, the cut schedule, the press-time clamp. Pure, unit-tested (`tests/LastDancer.spec.luau`, which also checks the generated chart) |
| `src/server/MiniGames/LastDancer.luau` | the round: the floor and each dancer's dance mat (`buildMat`), judging every `Tap`, misses, the cuts (decided 0.3 s early, mats drop on the downbeat), the batched `Steps` everyone sees, results |
| `src/server/MiniGames/Bots/LastDancer.luau` | bots tap the chart with skill-based accuracy (calibrated in the file's header) |
| `src/client/MiniGames/LastDancer.luau` | the highway with its arrow pads, instant feedback (same logic), groove meter, cut line, SYNC (manual and measured), standings, the dance and the stepping onto the mat's arrows, the club mood |
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

Checked here: unit tests (275), stylua, selene, luau-lsp, a 12-player round, a round with 10 real bots, full rounds of 1, 2,
3 and 5 players, the phone HUD at five sizes (0 problems), the arena and a dancer's mat rendered in Blender (the arrows point
the right way, UP towards the stage), mesh orientation. The z-fight check still lists pairs: rail cylinders crossing at right
angles and the two white bars of one arrow (same colour), which the check sees as boxes: nothing there can flicker.
**Not checkable without a real client** (the test server has no input, audio, physics or GUI engine):

- how the audio feels against the notes on real phones (the SYNC buttons are the safety net; judge it with Bluetooth too);
- the dance poses and the stepping (the R15 joint offsets are written from the rig's geometry: arms up and out, a side step
  puts that foot out and shifts the body over the panel, UP steps forward, DOWN back; look once, and check that the camera
  doesn't sway with the steps: as far as I know Roblox's camera follows the root part, which the dance never moves, but I
  couldn't confirm it here; if it sways, set the local player's Humanoid.CameraOffset to the negative of the body shift);
- tiles dropping with the dancers on them, the red flash, the club mood (midnight, purple haze), the lights on phones;
- tapping on glass: two fingers, a thumb resting on the screen edge, the pads' size on a small phone.

## Going live

The mode keeps itself out of the vote on live servers until its song is in the game. To switch it on: upload the song
(ModePack7's audio file lives in `build/`, which isn't in git: in a fresh container run `python3 tools/music/modes.py render
LastDancer` and `python3 tools/music/modes.py pack` first, which rebuilds the same pack; then `python3 tools/upload_assets.py --user-id 11690979745 --what modes --dry-run`, then without `--dry-run`: it uses 1 of the
owner's 10 audio uploads a month), optionally the meshes (`--what meshes --only LastDancerMirrorBall,LastDancerSpeaker`),
publish, restart the servers. Then add "💃 LAST DANCER" to `docs/STORE_DESCRIPTION.txt` (31 mini-games) and make its portal
preview (`tools/preview/make_preview.py LastDancer`).

# Handoff: Party Panic (for the Claude joining the project)

Written for a second Claude that joins while the first one keeps working. Last updated: **2026-10-21 16:40 UTC
(12:40 PM Eastern)**. Live: **version 27**. Session A keeps updating this file as its lanes land.

**At a glance (12:40 PM ET):** all 11 precision games have fair hitboxes (live). Six Session A agents are still working
(payoffs + low currency, sit-out toggle, lobby obby, Skee-Ball, Sinking Sands bots, Skate Escape start float); Session A
merges, tests and publishes each as it lands. Open with the owner: friends' audio (waiting on a device report), the store
description (owner pastes it, or adds a key scope), icon/thumbnails (owner uploads). Free for Session B: games 13-25 and
per-game music (section 2).

- **Session A** is the Claude that wrote this. It keeps its current lanes until they are finished (owner: "you can finish
  all work in here. I just want to make the other claude work on other things").
- **Session B** is you. You take other work: the obvious candidates are the backlog games 13-25 and custom music per
  mini-game (see "What's free for you"). Ask the owner which.

## 1. The owner and the house rules

- The owner is **not a programmer**. Explain in plain words, say what to click, keep updates short and concrete. They
  play-test on **phones** with friends (iPhone, small screens) and on PC, and they report what feels wrong in a sentence or
  a screenshot. They want a "masterpiece": great looks, great UX, "it just has to work". They dislike workarounds that hide
  a problem (owner: "I dont want you to do a fix for if they dont load. I want you to fucking make our own meshes work").
- The game is a Roblox party game, **Party Panic**: a lobby, a vote on 4 cards (3 games + RANDOM; bots never vote),
  then a mini-game for up to 12 players, bots filling empty spots, results, back to the lobby.
- **Private only.** Universe `10772087888`, place `78868713931081`, owner user `11690979745`. The experience stays
  PRIVATE; `tools/publish_place.py` refuses to publish to a public experience. All uploads go under user `11690979745`.
- **Git:** Session A works on branch `claude/quirky-hopper-5yk8zk` (pushed after every change). Every commit message
  ends with the session's attribution lines (Session A uses its own; use yours). No pull requests unless the owner asks.
  Never put model names in commits or files.
- **Style:** Luau with tabs and StyLua; every module starts with a comment block saying what it does and quoting the
  owner's words that asked for it; game names in capitals in player-facing text; colour is never the only cue; phones
  first (big touch targets, inside the safe area, never over the right-hand menu column, the jump button or the MOVE stick).
- **Server owns everything:** scoring, positions, eliminations, timing. Clients only ask and draw. Every mode needs a
  bot brain with hazard parity (whatever hurts players on the server must hurt bots too).
- **Fair hits** (owner, today: "the precision games will feel super bad if we dont"): if it looks like a hit/catch on the
  player's screen it counts, if it looks like a dodge it doesn't; judge against what the client saw (lag leeway from
  `GetNetworkPing`), make server radii match the visible meshes, and make client cues (highlights, rings) use the server's
  exact rule. Reference: `src/server/MiniGames/RakeItIn.luau` (top comment and `Takes`).

## 2. Who works on what (until Session A says it's done)

**Session A's lanes** (please don't edit these files until Session A has merged its work; check `git log` on
`origin/claude/quirky-hopper-5yk8zk`):

| Lane | Status | Files |
| --- | --- | --- |
| Hitbox pass for all 11 precision games | **done, live in version 24** (each game's commit message says what changed) | the mini-game files are free again, except the two rows below |
| Sinking Sands diver bots (owner: "Bots are terrible at this game") (agent; worktree `.claude/worktrees/bots-SinkingSands`, branch `bots/SinkingSands`) | started (investigating why divers score 0-4) | `src/server/MiniGames/Bots/SinkingSands.luau` and the other Sinking Sands files |
| Skate Escape start float (owner: the character floats onto the bridge "on the countdown and go") | **fixed, live in version 26** (skaters are held on their boards on the start line until GO, then handed back to their device) | free again |
| Lobby obby rebuild + scenery not climbable (agent; branch `lobby/obby`) | first WIP committed: a goo-pool course with checkpoints, foliage that never collides | `src/server/World/LobbyBuilder.luau` (buildParkour, scenery placement), `src/client/Controllers/MovementController.luau` |
| Skee-Ball arcade in the lobby (agent; branch `lobby/skeeball`) | WIP: the shared ball path (roll, hop, flight, rings) is in; machine, props and UI in progress | a new arcade module + props, a one-line hook in LobbyBuilder, a new SkeeBallController |
| "Sit out next round" toggle | **done, live in version 27**: a PLAYING / SITTING OUT switch by the phase banner and in Settings (`SitOutService`, `Logic/Roster`, `PP_SitOut`); sitting-out players don't vote or play, and rounds pause if everyone sits out | free again |
| Long-term payoffs + low currency (agent; branch `feature/payoffs`) | WIP: low coin scale, Rewards Road, career milestones, celebrations | `src/shared/Config.luau` (rewards), `Cosmetics.luau`, `QuestDefinitions.luau`, `src/shared/Logic/{RewardLogic,LevelCurve,DailyLogic,QuestLogic}.luau`, `src/server/Services/{DataService,Economy,RewardService,ShopService,CosmeticService,QuestService}.luau`, `CommerceConfig`, Shop/Quest/Results controllers, level-up UI |
| Friends can't hear our music (section 6) | waiting for the friend's report from version 25 | `src/client/Controllers/AudioController.luau`, `AssetReportController.luau`, `src/server/Services/ClientReports.luau`, `src/shared/AudioAssets.luau`, `Sounds.luau` |
| Publishing the place | Session A publishes after each merge | `tools/publish_place.py` |

The agents' branches and worktrees exist only in Session A's container (they're merged into
`claude/quirky-hopper-5yk8zk` and pushed as they finish), so you won't see them on GitHub until then.

**What's free for you:**

- **Games 13-25** ([docs/MINIGAME_BACKLOG.md](MINIGAME_BACKLOG.md): the 13 briefs, in the owner's order, with planned
  categories). They are mostly new files. Shared touch points: one entry each in `src/shared/GameDefinitions.luau`
  (append above `-- NEW MINI-GAMES GO ABOVE THIS LINE`), `src/shared/GamePreviews.luau` (written by `make_preview.py`),
  `assets/previews/previews.json`. Merge conflicts there are "keep both".
- **Custom music for each mini-game** (owner, today: "put in the backlog custom music for each mini game"). The music
  pipeline is `tools/music` (see `docs/ASSETS.md`). Shipping it is blocked until other players can hear our uploaded
  audio at all (section 6), but tracks can be composed and previewed now. Coordinate the `AudioController`/`AudioAssets`
  changes with Session A.
- Anything else the owner gives you.

**Working together:**

- Work on your own branch; merge `origin/claude/quirky-hopper-5yk8zk` into it often (`git fetch origin
  claude/quirky-hopper-5yk8zk && git merge FETCH_HEAD`). Session A will merge your pushed branch when the owner asks.
- **Publishing replaces the whole live place.** Only publish a build that contains the latest
  `origin/claude/quirky-hopper-5yk8zk`, or you roll back Session A's fixes in the live game (and vice versa). Tell the owner
  the version number you published (`publish_place.py` prints it).
- Prop names share one namespace across modes: prefix yours with the mode id (e.g. `TanksShell`).

## 3. Setting up (a fresh cloud container)

- Toolchain: `rokit install` (Rojo, Selene, StyLua, Lune from `rokit.toml`), plus `luau-lsp` and Python 3 with numpy and
  Pillow. Type-checking needs `globalTypes.d.luau` in the repo root (Roblox's definitions; it's git-ignored: fetch the
  luau-lsp Roblox definitions file).
- Roblox access goes through the environment's proxy: requests to `apis.roblox.com` get the owner's Open Cloud credential
  injected ("Roblox Publish"); no key in the repo. It can publish places, upload assets, grant asset permissions, run Luau
  on test servers (Luau execution) and read data stores. It **cannot** change place settings (403 "Scope not authorized"),
  and the universe description PATCH is blocked by Roblox's firewall (section 6). Icons and thumbnails have no API: the
  owner uploads them in the Creator Hub (`assets/store/README.md`).
- Renders (portal previews, arena checks, store art) need Blender's Python module: `pip install bpy` under **Python 3.11**
  in a venv, then `export PP_BPY_PYTHON=/path/to/venv/bin/python`. Keep renders few and small (4 CPUs).

## 4. Map of the code (start with [README.md](../README.md) and [ADDING_MINIGAMES.md](ADDING_MINIGAMES.md))

- `src/server/Services/RoundManager.luau` runs the loop (Waiting, Intermission, Voting, Preparing, InRound, Results,
  Cleanup). `RoundContext.luau` is a round's API for modes (players, teams, scores, eliminations, knockback, shared state
  `MG_*`, actions, bots). At the end of a round it gives everyone who isn't already back in the lobby a fresh character
  there (it tracks the character a player got in the lobby after going out; distance alone failed for Bobsled Run).
- `src/server/MiniGames/<Id>.luau` + `src/client/MiniGames/<Id>.luau` + `Bots/<Id>.luau`: one mode. Templates in
  `tools/templates`, the Kit in `src/server/MiniGames/Kit` and `src/client/MiniGames/Kit/Api.luau`.
- `src/server/Services/BotService.luau`: bots are fake Player-likes with real characters; `RoundContext:RunBots` drives
  their brains.
- Props: `src/server/World/Props/<File>.luau` (one spec block per prop with its own `AssetId`, a primitive `Fallback`, a
  `Palette`), `src/server/World/MeshLibrary.luau`, generators in `tools/meshgen/props/<Mode>.py` with shared helpers in
  `tools/meshgen/generate_meshes.py` (which also turns every closed part outward, `face_outward`).
- Lobby: `src/server/World/LobbyBuilder.luau`, `Environment.luau`; client controllers in `src/client/Controllers`.
- Shared: `GameDefinitions.luau` (Id, Category, Duration, MinPlayers, IsTeam, IsNew, texts), `GameState.luau`, `Remotes.luau`,
  `Config.luau`, `Teams.luau`, `Logic/*` (pure, unit-tested with Lune in `tests/`).

## 5. Testing without Studio (there is no Roblox client here)

Everything below runs real Roblox servers through Open Cloud Luau execution (no physics: harness bots move rigs with
`PivotTo`; real bots' walking is simulated).

- `tools/checks/mode_check.sh <Id>`: code checks, a 12-player round with the client half, a round with 10 real bots, and
  the phone HUD drawn at phone sizes (PNGs in `/tmp/mode_check/<Id>/`). Must show 0 errors, `notHomeAfterCleanup []`.
- `tools/checks/round_harness.py` / `client_harness.py` + `tools/preview/luau_task.py`: single rounds, the whole client
  with every screen, `LOBBY` with bots. `tools/checks/ui_render.py` draws the UI snapshots. `summarize.py` reads results.
- Gotchas: Open Cloud caps a script at 1 MiB (the round harness bundles only the tested mode; `LOBBY` bundles
  `LOBBY_MODES`); "INTERNAL_ERROR Task timed out" is transient (re-run once); HTTP 429 means wait and retry.
- Meshes: `python3 tools/checks/mesh_orientation.py` (inside-out or half-flipped closed parts; must report 0),
  `tools/checks/regen_compare.py` (would regenerating change a prop?), `tools/checks/merge_check.sh <Id>` (run after
  `git merge --no-ff --no-commit <branch>`, before committing a mode/art branch).
- Assets for other players: `python3 tools/checks/asset_status.py --meshes` (moderation of every model and the mesh files
  inside), `tools/asset_permissions.py` (the game may Use every model and sound; the mesh files inside are Open Use: both
  were needed before friends could see props). `publish_place.py` runs the grants every time.
- What players' devices actually load: `python3 tools/checks/client_reports.py` (mesh and sound reports each device sends;
  sound reports include whether the music plays, and, when something fails, Roblox's console lines and the account's
  content-policy flags).
- Workflows used for big batches (Claude Code's Workflow tool): `tools/workflows/build-minigame.js` (one game: build,
  review, fix; args are one brief from the backlog plus `ownDefinition: true`), `arena-polish.js`, `hitbox-pass.js`.

Publishing: `python3 tools/publish_place.py --universe-id 10772087888 --place-id 78868713931081` (builds, publishes,
grants asset permissions; prints the version; the settings PATCH warning at the end is expected). Push the branch after.

## 6. Open problems (Session A is on these; context so you don't trip on them)

- **Friends can't hear our music.** The friend's phone (version 22) failed to load all 4 uploaded sounds (both lobby
  tracks, the round track, the effects sprite) while all 146 meshes loaded; the owner's devices play them. Checked: all 4
  are Approved and Active, owned by the game's owner; the game's Use grant succeeds (re-granted today); audio can't be made
  Open Use (the API answers InvalidRequest). Since version 23 a failing device reports Roblox's own console lines and its
  account policy flags; version 25 also loads a public Roblox library track (APM "Bossa Nova Party", 1845764031) as a
  control. Next: the friend joins version 25 in a fresh server (old servers keep their version; the owner restarts them in
  the Creator Hub) and waits ~40 s in the lobby; then `python3 tools/checks/client_reports.py` shows the reason. If the
  library track plays and ours don't, Roblox refuses our uploads for that player; if neither plays, it's their device or
  account. Asked the owner whether the friend hears music in other games and is under 13 or parental controls.
- **Store description:** the new text is ready in `docs/STORE_DESCRIPTION.txt`, but our key can't set it. Roblox only
  saves a description through the place (`PATCH cloud/v2/universes/{u}/places/{p}`), which answers 403 "Scope not
  authorized" for this key. The universe PATCH answers 200 for a description but stores nothing (the live text is still
  the old one), and its firewall rejects long multi-line texts anyway. So: the owner pastes it (Creator Hub > Configure >
  Basic Settings) and removes the trailing space in the name "Party Panic ", or adds **universe.place (write)** for this
  experience to the API key, after which every `publish_place.py` sets the name and description.
- **Icon and thumbnails:** done (`assets/store/`, sent to the owner); the owner uploads them by hand.

## 7. Recent history (what's live)

Version **24** (published 16:15 UTC today) has the 12 games below, fair hitboxes in all 11 precision games (Honey Trap is
turn-based), the carnival Pump & Pop arena, rounds 5-10 s longer, players always sent back to the lobby after Bobsled Run,
every prop facing outward (the black Hex Meltdown flag fixed), and sound reports. Known phone-HUD nits from the last test
rounds: Skate Escape's progress-bar racer numbers overlap when riders are side by side, Bumper Ballers' "X" sits over the
rider icon of a knocked-out rider, and the Sinking Sands Sand King hint wraps to two lines (being fixed with the bots). Games: Fire Rope, Hex Meltdown, Honey Trap, Bumper Ballers, Skate Escape, Sinking
Sands, Arrow Ambush, Pump & Pop, Rake It In, Crazy Cutters, Cake Factory, Bobsled Run. All hold 12 players (each has a
clean 12-player test round).

## 8. The owner's recent requests (newest last), for context

"For bumper balls you get bounced off way too quickly." (tuned) / "Music isn't working for my friend." (open) / "When I
finished bobsled I go out here" (fixed) / "hitboxes for rake game suck" (fixed) / "We need to fine tune some of the
hitboxes. the precision games will feel super bad if we dont." (in progress) / "we need cool payoffs for players that keep
playing the game." (in progress) / "the obby in the lobby is terrible. trees and stuff collides and you can just run up
it." (in progress) / "Bots are terrible at this game" (Sinking Sands; queued) / "On the skateboard one it spawns you
when the game starts not on the bridge and you kinda just float to the bridge" (countdown and GO; queued) / "make sure all
games can hold 12 people" (checked: they do) / "a toggle where you skip next round" (in progress) / "balance the shop down.
I want low currency not high." (in progress) / "add skiball to the lobby" (in progress) / "make the games a little longer
5-10 seconds" (done) / "custom music for each mini game" (backlog) / games 13-25 (backlog, after everything else).

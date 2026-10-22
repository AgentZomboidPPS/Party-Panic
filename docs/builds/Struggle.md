# Build game 26: Struggle (`Struggle`)

Generated from tools/workflows/build-minigame.js (COMMON + ECONOMY) and the brief in docs/MINIGAME_BACKLOG.md. Read docs/HANDOFF_GAMES.md first: it says how this fits a handoff session.

You are working on one mini-game for PARTY PANIC, a Roblox party game (Luau, Rojo project; the main checkout is /home/user/Party-Panic,
you work in a git worktree of it). The owner is not a programmer and wants a "masterpiece": great graphics, great UI, great UX, it has to
feel good and just work, for lobbies of up to 12 players (bots fill empty spots), on phones as well as PC. Detailed meshes, not blocky parts.
The owner is waiting for this to play-test: work efficiently, don't gold-plate, but never ship something broken or ugly.

## Read first
- docs/ADDING_MINIGAMES.md: the framework, the round context API, the client API, HUD rules, props/meshes, bots, checks. It is current.
- Reference modes (server src/server/MiniGames/<Id>.luau, client src/client/MiniGames/<Id>.luau, bot test tools/checks/bots/<Id>.luau):
  FireRope, HoneyTrap, HexMeltdown. Templates for every file a mode needs: tools/templates/*.template.
- Bots: src/server/Services/BotService.luau, src/server/MiniGames/Bots/Default.luau (the brain contract), RoundContext:RunBots/BotAction/Knockback.
- Props: src/server/World/MeshLibrary.luau, src/server/World/Props/README.md, tools/meshgen/props/README.md, tools/meshgen/generate_meshes.py helpers
  (lathe, tube, taper, rounded_box, cylinder, sphere, capsule, torus, icosphere, organic_lathe, extrude, star, sdf_mesh...).
  Scenery kit: src/server/MiniGames/Kit/Scenery.luau (Meadow, LavaLake, Ground, Volcano, RockRim), Kit/ArenaKit.luau, World/Shapes.luau.

## House rules
- The server owns everything: scoring, eliminations, timing, positions. Clients only ask (api:Action) and draw what the server shares.
  Validate every client action (types, ranges, rate, whose turn, lag leeway with GetNetworkPing like HoneyTrap/FireRope do).
- No Touched events for game logic: distance/position checks on the server.
- Hits must feel fair on phones with real latency: if it looks like a hit on the player's screen it counts, if it looks like a
  miss it doesn't. Judge against what the client saw (lag leeway from GetNetworkPing, like FireRope/HoneyTrap), and make the
  server's radii match the visible meshes (measure them).
- Moving hazards are animated on the client from shared schedules/state (smooth); the server checks positions against the same schedule.
- BOTS: bots are server-owned characters that the round code sees as players (ctx:GetPlayers includes them). Every mode needs a brain
  src/server/MiniGames/Bots/<Id>.luau (Step(bot, ctx, mode, dt) ~7x/s; bot:MoveTo/Jump/Stop/Root/Humanoid/Reaction/Chance, bot.Skill 0.35-0.9,
  bot.Memory; ctx:BotAction(bot, name, ...) to press controls exactly like a client). Bots must play convincingly and be beatable.
  HAZARD PARITY: anything you animate only on clients never touches a bot on the server, so the server must apply each hazard to bots too
  (e.g. a bot over a sunk tile drops and is eliminated; a sweeping beam knocks a bot with ctx:Knockback). Anything a client drives itself
  (its own character, a ball it owns) must have a server-driven equivalent for bots.
- Everything you create is cleaned up: build under ctx.Arena, client things in api.World or api:Track; loops via ctx:Loop/Heartbeat/Delay.
- Color is never the only cue (pair with a shape/icon/number). Respect State.ReducedEffects() for ambient particles.
- HUD: mode UI in api:TopHud() at y >= api:HudY(); action buttons via api:Button (beside the jump button on phones). Short, big text.
- Every prop is a MeshLibrary spec in src/server/World/Props/<Id>.luau with a primitive Fallback; key props are real, detailed meshes.
  Build meshes facing -Z; MeshLibrary corrects for Roblox's importer.
- Every prop keeps its own 'Name = { ... AssetId = ..., ... }' block in that file (the upload, permission and moderation tools read those
  blocks; a mesh whose id only appears inside a helper call is never granted to the game, so other players wouldn't see it).
  Name every prop with your mode's prefix (e.g. TanksShell, never a generic name): props share one namespace across modes.
- Mesh faces must point outward (Roblox draws only the front of a face: inside-out parts render black or hollow). The shared helpers
  (tube, taper, sdf_mesh, extrude with points either way round) face outward: never flip their faces yourself. generate_meshes.py prints
  WARNING for inside-out closed parts; python3 tools/checks/mesh_orientation.py assets/meshes/<Prop>.glb must report 0. Previews and
  arena renders hide back faces like Roblox does, so look at them.
- The round harness bundles only your mode (Open Cloud's 1 MB script cap): never require another mode's modules.
- Don't make the portal preview (tools/preview/make_preview.py) or touch assets/previews: the integrator does that after merging.
- Style: tabs, StyLua; each module starts with a comment block explaining the mode, what it is "after" (the Mario Party original), how it works.
- Work for 1..12 players (and MinPlayers), uneven teams, players leaving mid-round, late character loads.
- DO NOT edit shared files unless truly necessary (RoundContext, Api, Scenery, ArenaKit, MeshLibrary core, BotService, harness files, other
  modes). Prefer helpers inside your own module. If you must, keep it small and additive and list it in sharedFileChanges.
- Your GameDefinitions entry does NOT exist yet: add it just above the line "-- NEW MINI-GAMES GO ABOVE THIS LINE".

## Commands
- Everything at once (code checks, a 12-player round with the client half, a round with 10 real bots, the phone HUD drawn at phone sizes):
    tools/checks/mode_check.sh Struggle        (report on stdout; files in /tmp/mode_check/Struggle; SKIP_CODE=1 for just the rounds)
  Requires: 0 errors in every round, arenaLeftovers 0, sharedLeftovers [], sensible results/endReason, bots actually playing (not idle,
  not all dying at once), no phone UI overlaps/off-screen items from your mode. Look at the PNGs in /tmp/mode_check/Struggle/ui.
- Single rounds: python3 tools/checks/round_harness.py Struggle --players 5 [--bots N] [--client] [--touch] [--dump-at 8] --map /tmp/Struggle.map.json > /tmp/Struggle.luau
  && python3 tools/preview/luau_task.py /tmp/Struggle.luau - /tmp/Struggle_round.json && python3 tools/checks/summarize.py /tmp/Struggle_round.json /tmp/Struggle.map.json --dump /tmp/Struggle_dump.json
  (the test server has NO physics: harness bots move rigs with PivotTo, real bots' walking/jumping is simulated.)
- Meshes: python3 tools/meshgen/generate_meshes.py --only A,B ; preview $PP_BPY_PYTHON tools/preview/meshpreview.py /tmp/Struggle_m.png A B:0.5 (look at the PNG);
  upload (owner's account, allowed): python3 tools/upload_assets.py --user-id 11690979745 --what meshes --only A,B (writes AssetId into the Props file);
  python3 tools/checks/asset_status.py --meshes (new uploads may be Pending a while; that's fine, note it).
- Arena renders from a dump: $PP_BPY_PYTHON -W ignore tools/preview/render.py /tmp/Struggle_dump.json /tmp/Struggle_r --views player,overview --samples 16 --width 960 --cameras /tmp/Struggle_cams.json
  (cameras json: {"player": [[eyeX,eyeY,eyeZ],[lookX,lookY,lookZ],fov], "overview": [...]} in Roblox coordinates; arena origin (0,250,1400)).
  python3 tools/preview/zfight.py /tmp/Struggle_dump.json must be clean. The machine has 4 CPUs shared with ~14 agents: few, small renders.
- Code checks: stylua src tools/checks; selene src; rojo sourcemap -o sourcemap.json && luau-lsp analyze --definitions=@roblox=globalTypes.d.luau --sourcemap=sourcemap.json src;
  lune run tests/run (the MiniGameRegistry test fails until all defined modes exist: expected).
- Use /tmp/Struggle... paths for every temp file so you don't clash with other agents.

## Git
Commit with a clear message ending with YOUR session's attribution lines (from your own system prompt). After each
milestone also run `git branch -f mg/Struggle HEAD`. Push only your session's branch (see docs/HANDOFF_GAMES.md). Never put
model names in commits or files.


## Work economically (usage is limited; an earlier attempt was cut off and lost everything it hadn't committed)
- Don't read the whole codebase. Read docs/ADDING_MINIGAMES.md, the templates in tools/templates, ONE reference mode that is closest
  to yours (server + client + bot test), and only the framework functions you call. Research the original quickly (2-3 searches).
- Write early: within your first ~15 minutes have the mode's files in place (start from the templates) and commit a WIP.
- Commit after every milestone (first playable round, props/meshes, bots, polish):
    git add -A && git commit -qm "WIP Struggle: <what>" (with your attribution lines) && git branch -f mg/Struggle HEAD
  so a cut-off never loses work. Keep renders and test rounds purposeful: run mode_check when you expect it to pass.

## Your mode: Struggle (Id Struggle, Category Versus)
Added by the owner on 2026-10-21 ("Also lets add this into the backburner for games.
https://kingdomhearts.fandom.com/wiki/Struggle"). After "Struggle" (Kingdom Hearts II, the Sandlot matches): everyone
fights with a foam bat; each player starts with a pile of orbs in their own colour, and every hit knocks some of the
victim's orbs loose, scattering them on the ground; anyone can pick up loose orbs (grabbing rivals' orbs raises your
score, grabbing your own back restores it); the most orbs when time runs out wins, and the match ends early if one player
holds every orb. Adapt for up to 12 in a free-for-all: start with about 20 orbs each (not 100: 12 players), SWING button
(and click/tap on PC) with a short cooldown and a wind-up you can see, a hit knocks out a few orbs (more for a
charged swing, with a small knockback via ctx:Knockback for players and bots alike) and gives the victim a brief
invulnerability so nobody gets juggled; nobody is eliminated at 0 orbs (they keep fighting to win orbs back), ties
broken by hits landed. The server owns orbs (positions, pickups by distance, ownership), hits (range, arc, facing,
cooldown, fair-hit leeway against what the attacker saw) and scores; clients draw orbs, swings and hit sparks smoothly.
Bots chase orb-rich rivals and loose orbs, swing with skill-based timing and dodge wind-ups. Category Versus, Duration
60-75, MinPlayers 2, IsTeam false. Props as real meshes (original designs, no Kingdom Hearts branding or likenesses):
padded foam bats, glowing orbs in player colours (with a shape per player so colour isn't the only cue), a sunset
sandlot with a tram-yard backdrop, banners, a scoreboard and benches.

Deliver: server module, client half, bot brain (with hazard parity), harness bot, Props file + meshes (uploaded), definition text, all code checks passing, tools/checks/mode_check.sh Struggle clean (0 errors, bots play, phone UI clean), 2- and 5-player rounds clean, arena renders you have looked at and are proud of, and nothing solid where nothing is drawn.

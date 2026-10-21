export const meta = {
  name: 'build-minigame-v4',
  description: 'Build one Party Panic mini-game (one builder, WIP commits), one review, fix',
  phases: [
    { title: 'Build', detail: 'research, implement, props/meshes, mode_check, renders, WIP commits' },
    { title: 'Review', detail: 'one reviewer: correctness, server authority, bots, UX and visuals' },
    { title: 'Fix', detail: 'apply findings, re-test, commit' },
  ],
}

const G = args
// A Python with the bpy (Blender) module, for the preview renders: see tools/preview/render.py.
const BLENDER = args.blender || 'python3.11'
const SALVAGE = `/tmp/salvage/${G.id}`

const COMMON = `
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
${G.ownDefinition ? '- Your GameDefinitions entry does NOT exist yet: add it just above the line "-- NEW MINI-GAMES GO ABOVE THIS LINE".' : '- Your GameDefinitions entry exists: keep Id/Category/Duration/MinPlayers/IsTeam; you may improve Objective/Controls text.'}

## Commands
- Everything at once (code checks, a 12-player round with the client half, a round with 10 real bots, the phone HUD drawn at phone sizes):
    tools/checks/mode_check.sh ${G.id}        (report on stdout; files in /tmp/mode_check/${G.id}; SKIP_CODE=1 for just the rounds)
  Requires: 0 errors in every round, arenaLeftovers 0, sharedLeftovers [], sensible results/endReason, bots actually playing (not idle,
  not all dying at once), no phone UI overlaps/off-screen items from your mode. Look at the PNGs in /tmp/mode_check/${G.id}/ui.
- Single rounds: python3 tools/checks/round_harness.py ${G.id} --players 5 [--bots N] [--client] [--touch] [--dump-at 8] --map /tmp/${G.id}.map.json > /tmp/${G.id}.luau
  && python3 tools/preview/luau_task.py /tmp/${G.id}.luau - /tmp/${G.id}_round.json && python3 tools/checks/summarize.py /tmp/${G.id}_round.json /tmp/${G.id}.map.json --dump /tmp/${G.id}_dump.json
  (the test server has NO physics: harness bots move rigs with PivotTo, real bots' walking/jumping is simulated.)
- Meshes: python3 tools/meshgen/generate_meshes.py --only A,B ; preview ${BLENDER} tools/preview/meshpreview.py /tmp/${G.id}_m.png A B:0.5 (look at the PNG);
  upload (owner's account, allowed): python3 tools/upload_assets.py --user-id 11690979745 --what meshes --only A,B (writes AssetId into the Props file);
  python3 tools/checks/asset_status.py --meshes (new uploads may be Pending a while; that's fine, note it).
- Arena renders from a dump: ${BLENDER} -W ignore tools/preview/render.py /tmp/${G.id}_dump.json /tmp/${G.id}_r --views player,overview --samples 16 --width 960 --cameras /tmp/${G.id}_cams.json
  (cameras json: {"player": [[eyeX,eyeY,eyeZ],[lookX,lookY,lookZ],fov], "overview": [...]} in Roblox coordinates; arena origin (0,250,1400)).
  python3 tools/preview/zfight.py /tmp/${G.id}_dump.json must be clean. The machine has 4 CPUs shared with ~14 agents: few, small renders.
- Code checks: stylua src tools/checks; selene src; rojo sourcemap -o sourcemap.json && luau-lsp analyze --definitions=@roblox=globalTypes.d.luau --sourcemap=sourcemap.json src;
  lune run tests/run (the MiniGameRegistry test fails until all defined modes exist: expected).
- Use /tmp/${G.id}... paths for every temp file so you don't clash with other agents.

## Git
Commit in the worktree with a clear message ending with exactly these two lines:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0118DxSUkAz3MXNwL4Bb3UDh
then: git branch -f mg/${G.id} HEAD. Do not push, do not touch other branches. Never put model names in commits or files.
`

const DESIGN_SCHEMA = {
  type: 'object',
  properties: {
    worktree: { type: 'string', description: 'absolute path of the worktree (output of pwd)' },
    designFile: { type: 'string', description: 'path of the design doc you wrote, inside the worktree' },
    summary: { type: 'string' },
  },
  required: ['worktree', 'designFile', 'summary'],
}
const PROPS_SCHEMA = {
  type: 'object',
  properties: {
    meshes: { type: 'array', items: { type: 'string' }, description: 'name, asset id, moderation state' },
    previews: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
    openIssues: { type: 'array', items: { type: 'string' } },
  },
  required: ['meshes', 'previews', 'summary', 'openIssues'],
}
const CODE_SCHEMA = {
  type: 'object',
  properties: {
    files: { type: 'array', items: { type: 'string' } },
    sharedFileChanges: { type: 'array', items: { type: 'string' } },
    testResults: { type: 'string' },
    summary: { type: 'string' },
    openIssues: { type: 'array', items: { type: 'string' } },
  },
  required: ['files', 'sharedFileChanges', 'testResults', 'summary', 'openIssues'],
}
const BUILD_SCHEMA = {
  type: 'object',
  properties: {
    worktree: { type: 'string' },
    branch: { type: 'string' },
    commit: { type: 'string' },
    design: { type: 'string', description: 'the rules as built, controls, how 12 players and bots work' },
    summary: { type: 'string' },
    sharedFileChanges: { type: 'array', items: { type: 'string' } },
    meshes: { type: 'array', items: { type: 'string' } },
    testResults: { type: 'string', description: 'mode_check results: errors, endReason, results, bots, phone UI' },
    renders: { type: 'array', items: { type: 'string' } },
    openIssues: { type: 'array', items: { type: 'string' }, description: 'not verified/not done, esp. what only a Studio playtest can check' },
  },
  required: ['worktree', 'branch', 'commit', 'design', 'summary', 'sharedFileChanges', 'meshes', 'testResults', 'renders', 'openIssues'],
}
const REVIEW_SCHEMA = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          severity: { type: 'string', enum: ['must', 'should', 'nit'] },
          file: { type: 'string' }, problem: { type: 'string' }, evidence: { type: 'string' }, fix: { type: 'string' },
        },
        required: ['severity', 'file', 'problem', 'evidence', 'fix'],
      },
    },
  },
  required: ['findings'],
}
const FIX_SCHEMA = {
  type: 'object',
  properties: {
    commit: { type: 'string' },
    applied: { type: 'array', items: { type: 'string' } },
    skipped: { type: 'array', items: { type: 'string' }, description: 'finding + why not applied' },
    testResults: { type: 'string' },
    renders: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
    openIssues: { type: 'array', items: { type: 'string' } },
  },
  required: ['commit', 'applied', 'skipped', 'testResults', 'renders', 'summary', 'openIssues'],
}


const ECONOMY = `
## Work economically (usage is limited; an earlier attempt was cut off and lost everything it hadn't committed)
- Don't read the whole codebase. Read docs/ADDING_MINIGAMES.md, the templates in tools/templates, ONE reference mode that is closest
  to yours (server + client + bot test), and only the framework functions you call. Research the original quickly (2-3 searches).
- Write early: within your first ~15 minutes have the mode's files in place (start from the templates) and commit a WIP.
- Commit after every milestone (first playable round, props/meshes, bots, polish):
    git add -A && git commit -qm "WIP ${G.id}: <what>" (with the two attribution lines) && git branch -f mg/${G.id} HEAD
  so a cut-off never loses work. Keep renders and test rounds purposeful: run mode_check when you expect it to pass.
`

phase('Build')
const build = await agent(`${COMMON}
${ECONOMY}
## Your mode: ${G.name} (Id ${G.id})
${G.brief}

An earlier attempt left partial files in ${SALVAGE} (same paths as the repo; may not exist): reuse what's good (nothing was uploaded).
Deliver: server module, client half, bot brain (with hazard parity), harness bot, Props file + meshes (uploaded), definition text,
all code checks passing, tools/checks/mode_check.sh ${G.id} clean (0 errors, bots play, phone UI clean), 2- and 5-player rounds clean,
arena renders you have looked at and are proud of. Final commit, git branch -f mg/${G.id} HEAD, and report.`,
  { label: `build:${G.id}`, phase: 'Build', schema: BUILD_SCHEMA, isolation: 'worktree', effort: 'high' })
if (!build) return { id: G.id, error: 'build agent failed' }

phase('Review')
const review = await agent(`You are reviewing a Party Panic mini-game before it ships; the owner wants a masterpiece that just works on phones and PC.
The mode is in the git worktree ${build.worktree} (branch mg/${G.id}, commit ${build.commit}). If that directory is gone:
git -C /home/user/Party-Panic worktree add /home/user/wt-${G.id}-review mg/${G.id}. Read-only: do not edit files.
Builder's report: ${JSON.stringify({ design: build.design, summary: build.summary, testResults: build.testResults, openIssues: build.openIssues, renders: build.renders })}
Read the mode's own files (server, client, brain, Props, harness bot) and only the framework functions they call. Find, with evidence:
1. Bugs and exploits: rule logic, unvalidated client input (types, ranges, rate, turn), races (players leaving, eliminated players acting,
   late characters, round end), cleanup leaks, nil errors, behaviour at 1, 2, 5 and 12 players and uneven teams, results/tiebreaks,
   hazard parity (do hazards reach bots on the server?), bots idling or cheating, what breaks with real physics/latency.
2. Feel: rules obvious in 3 seconds, instant feedback for every action, pacing for 12, HUD layout (TopHud/HudY, buttons, phone sizes:
   PNGs in /tmp/mode_check/${G.id}/ui if present), color+shape cues, readability of the arena in the renders (Read them).
You may run the harness to confirm (use /tmp/${G.id}_rev paths). Concrete fixes only; severity must/should/nit.`,
  { label: `review:${G.id}`, phase: 'Review', schema: REVIEW_SCHEMA, effort: 'high' })
const findings = (review && review.findings) || []
log(`${G.id}: ${findings.length} findings (${findings.filter(f => f.severity === 'must').length} must)`)

phase('Fix')
const fix = await agent(`${COMMON}
${ECONOMY}
You are finishing the mode ${G.name} (Id ${G.id}) in the git worktree ${build.worktree} on branch mg/${G.id} (commit ${build.commit}).
cd there. If that directory is gone: git -C /home/user/Party-Panic worktree add /home/user/wt-${G.id} mg/${G.id} and work in that.
Reviewer findings: ${JSON.stringify(findings, null, 1)}
Verify each against the code; fix every "must" and the "should"s you agree with (and cheap nits); say why for anything you skip. Re-run
tools/checks/mode_check.sh ${G.id} (0 errors, bots play, phone UI clean); re-render if visuals changed and look. Commit (two attribution
lines), git branch -f mg/${G.id} HEAD, report.`,
  { label: `fix:${G.id}`, phase: 'Fix', schema: FIX_SCHEMA, effort: 'high' })

return { id: G.id, build, findings, fix }

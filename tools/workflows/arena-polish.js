export const meta = {
  name: 'arena-polish-v3',
  description: 'Make each existing mini-game arena look great: rebuild the look, review, fix (one worktree per arena)',
  phases: [
    { title: 'Build', detail: 'render, rethink and rebuild the arena look, WIP commits' },
    { title: 'Review', detail: 'art director + correctness review from renders and code' },
    { title: 'Fix', detail: 'apply findings, re-render, commit' },
  ],
}

// A Python with the bpy (Blender) module, for the arena renders: see tools/preview/render.py.
const BLENDER = args.blender || 'python3.11'

const ARENAS = args

const COMMON = (a) => `
PARTY PANIC is a Roblox party game (Luau, Rojo; main checkout /home/user/Party-Panic; you work in a git worktree). The owner wants every
mini-game arena to "look really cool" for up to 12 players (bots fill empty spots), on phones and PC: bright toy style, detailed meshes,
not blocky, strong composition, readable gameplay. Your arena: ${a.id}. ${a.theme}

## Rules
- Keep the gameplay exactly as it is (rules, timings, hit checks, controls, bots): this is an art pass. Only touch how it looks.
- Edit only your mode's own files: src/server/MiniGames/${a.id}.luau, src/client/MiniGames/${a.id}.luau, src/server/World/Props/${a.id}.luau
  (create it if needed; see Props/README.md) and tools/meshgen/props/${a.id}.py (see tools/meshgen/props/README.md). Do not edit shared
  files (Kit/Scenery, Kit/ArenaKit, MeshLibrary core, RoundContext, Api, other modes): copy a helper into your module if you need a variant.
- Detailed meshes for new key props (generate, preview, upload: python3 tools/upload_assets.py --user-id 11690979745 --what meshes --only A,B;
  that also grants the game permission). Every prop needs a primitive Fallback. Mind phones: meshes and few parts, no heavy per-frame work.
- Visual effects on the client from shared state (smooth); respect State.ReducedEffects() for ambient particles. No z-fighting.
- Mesh faces must point outward (Roblox draws only the front of a face; inside-out parts render black/hollow). The shared helpers
  (tube, taper, sdf_mesh, extrude) face outward now: never flip their faces. The generator prints WARNING for inside-out closed parts;
  python3 tools/checks/mesh_orientation.py assets/meshes/<Prop>.glb must report 0. Renders hide back faces like Roblox does.
- Name every new prop with your mode's prefix (e.g. SkateCanyonWall), never a generic name: props share one namespace across modes.
- This mode was built recently: read its current files and the builder's intent first; keep its gameplay, HUD and bot code as they are.
- Work economically (usage is limited): read your mode's files, the Scenery kit and the preview commands, render first, then build.
  Commit after every milestone (git add -A && git commit -qm "WIP ${a.id} art: <what>" with the two attribution lines below, then
  git branch -f art/${a.id} HEAD) so a cut-off never loses work.

## Seeing it (real Roblox server, no physics; use /tmp/${a.id}art paths)
  python3 tools/checks/round_harness.py ${a.id} --players 8 --client --dump-at 8 --map /tmp/${a.id}art.map.json > /tmp/${a.id}art.luau
  python3 tools/preview/luau_task.py /tmp/${a.id}art.luau - /tmp/${a.id}art_round.json
  python3 tools/checks/summarize.py /tmp/${a.id}art_round.json /tmp/${a.id}art.map.json --dump /tmp/${a.id}art_dump.json
  ${BLENDER} -W ignore tools/preview/render.py /tmp/${a.id}art_dump.json /tmp/${a.id}art_r --views player,overview --samples 16 --width 960 --cameras /tmp/${a.id}art_cams.json
  (cameras json: {"player": [[eyeX,eyeY,eyeZ],[lookX,lookY,lookZ],fov], "overview": [...]} in Roblox coordinates; arena origin (0,250,1400).
  The renderer draws parts, unions and props from their glb; not GUI/particles.) Look at every PNG with the Read tool.
  python3 tools/preview/zfight.py /tmp/${a.id}art_dump.json must be clean. The machine has 4 CPUs shared with other agents: few, small renders.
- Gameplay must still pass: tools/checks/mode_check.sh ${a.id} (0 errors, bots play, phone UI clean).
- Code checks: stylua src tools/checks; selene src; rojo sourcemap -o sourcemap.json && luau-lsp analyze --definitions=@roblox=globalTypes.d.luau --sourcemap=sourcemap.json src;
  lune run tests/run (the MiniGameRegistry test fails until all defined modes exist: expected).

## Git
Commit messages end with exactly these two lines:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0118DxSUkAz3MXNwL4Bb3UDh
Final: git branch -f art/${a.id} HEAD. Do not push or touch other branches. Never put model names in commits or files.
`

const BUILD = { type: 'object', properties: {
  worktree: { type: 'string' }, commit: { type: 'string' }, summary: { type: 'string' },
  renders: { type: 'array', items: { type: 'string' } }, testResults: { type: 'string' },
  openIssues: { type: 'array', items: { type: 'string' } } },
  required: ['worktree', 'commit', 'summary', 'renders', 'testResults', 'openIssues'] }
const REVIEW = { type: 'object', properties: { findings: { type: 'array', items: { type: 'object', properties: {
  severity: { type: 'string', enum: ['must', 'should', 'nit'] }, problem: { type: 'string' }, evidence: { type: 'string' }, fix: { type: 'string' } },
  required: ['severity', 'problem', 'evidence', 'fix'] } } }, required: ['findings'] }
const FIX = { type: 'object', properties: { commit: { type: 'string' }, applied: { type: 'array', items: { type: 'string' } },
  skipped: { type: 'array', items: { type: 'string' } }, renders: { type: 'array', items: { type: 'string' } }, summary: { type: 'string' } },
  required: ['commit', 'applied', 'skipped', 'renders', 'summary'] }

const results = await pipeline(ARENAS,
  a => a.build ? Promise.resolve(a.build) : a.worktree ? agent(`${COMMON(a)}
Your job: make the ${a.id} arena look really cool. An earlier builder started this art pass and was stopped part-way: continue its work
in the existing git worktree ${a.worktree} (cd there; work and commit only in that directory; its uncommitted changes are that builder's
work in progress - keep what's good). Look at the current state (git status, git log, render it), decide what's left, finish the look step
by step, rendering after each big step. Finish with mode_check clean and all checks passing. Commit, set branch art/${a.id}, report with the
final render paths (worktree = ${a.worktree}).`,
    { label: `build:${a.id}`, phase: 'Build', schema: BUILD, effort: 'high' }) : agent(`${COMMON(a)}
Your job: make the ${a.id} arena look really cool. Render it as it is now (player view and overview), look hard, decide on a strong art
direction, then rebuild the look step by step, rendering after each big step. Finish with mode_check clean and all checks passing.
Commit, set branch art/${a.id}, report with the final render paths.`,
    { label: `build:${a.id}`, phase: 'Build', schema: BUILD, isolation: 'worktree', effort: 'high' }),
  (build, a) => build && agent(`Review the art pass on the ${a.id} arena of PARTY PANIC as a demanding art director and as a careful engineer.
Worktree ${build.worktree} (branch art/${a.id}, commit ${build.commit}); if gone: git -C /home/user/Party-Panic worktree add /home/user/wt-art-${a.id} art/${a.id}. Read-only.
Builder report: ${JSON.stringify(build)}
Look at every render (Read tool); is it stunning, readable, cohesive, phone-friendly? Then read the diff (git diff against its base):
gameplay must be unchanged; no heavy per-frame work; parts and meshes cleaned up; fallbacks present; no z-fighting. Concrete fixes only.
${COMMON(a)}`, { label: `review:${a.id}`, phase: 'Review', schema: REVIEW, effort: 'high' })
    .then(r => ({ build, findings: (r && r.findings) || [] })),
  (rv, a) => rv && rv.build && agent(`${COMMON(a)}
Finish the ${a.id} art pass in the worktree ${rv.build.worktree} (branch art/${a.id}; if gone: git -C /home/user/Party-Panic worktree add /home/user/wt-art-${a.id} art/${a.id}).
Reviewer findings: ${JSON.stringify(rv.findings, null, 1)}
If the worktree already has uncommitted changes, they are an earlier attempt at these fixes that was cut off: review them and keep what's good.
Fix every must and the shoulds you agree with; re-render and look; keep mode_check and all checks passing; commit; git branch -f art/${a.id} HEAD; report.`,
    { label: `fix:${a.id}`, phase: 'Fix', schema: FIX, effort: 'high' }).then(f => ({ id: a.id, build: rv.build, findings: rv.findings, fix: f })),
)
return results

export const meta = {
  name: 'hitbox-pass',
  description: 'Tune each precision mini-game so hits and catches match what players see (one agent per game, in worktrees)',
  phases: [
    { title: 'Tune', detail: 'audit every hit/catch test against the visuals and latency, fix, verify with mode_check, commit' },
  ],
}

const GAMES = args.games

const PROMPT = (g) => `You are tuning the hit detection of one mini-game in PARTY PANIC, a Roblox party game (Luau, Rojo; the main checkout is
/home/user/Party-Panic and you work in a git worktree of it). The owner play-tests on phones with friends and said:
"hitboxes for rake game suck" and "We need to fine tune some of the hitboxes. the precision games will feel super bad if we dont."
Your game: ${g.id} (${g.name}). ${g.focus}

## The principle (what "fair" means here)
If it looks like a hit / catch / pickup / perfect on the player's own screen, it counts; if it looks like a dodge / miss on their
screen, it doesn't. Where the two disagree because of size or timing, favour the player: generous for good things (catching produce,
grabbing treasure, a perfect pump, landing a bump on a rival, a lean in time), strict for bad things (being hit by a rope/arrow/obstacle,
raking a bomb, falling through an edge you were visibly standing on). Never make the game trivial: keep the challenge, just make the
judging match what people see.

## The reference fix (Rake It In, already done on main; read it: git show of src/server/MiniGames/RakeItIn.luau is in your worktree's
history soon, or read the description here)
Before: a rake took only items whose exact centre was inside the lane at the single instant of the press, while the rake visibly sweeps
for 0.6 s and the produce is ~2 studs wide; bombs used the same rule. After: produce counts if it overlaps the lane (centre within the
lane grown by about the produce's radius) at any moment from the press to the end of the drag (samples at +0, +0.1, +0.2, +0.3 s);
a bomb counts only if its centre was clearly inside (lane shrunk by 0.5) at the press. The client's "this is in your lane" highlight
uses the exact same rule, so what's highlighted is what you get. Bots use it too.

## What to do
1. Read the mode's server module (src/server/MiniGames/${g.id}.luau), its client half (src/client/MiniGames/${g.id}.luau), its bot brain
   (src/server/MiniGames/Bots/${g.id}.luau), its props (src/server/World/Props/${g.id}.luau, Heights/PieceSize) and the RoundContext
   functions it calls. List EVERY server-side test that decides a hit, catch, pickup, elimination, score or timing window.
2. For each, compare the server's geometry and timing with what the player sees:
   - sizes: server radii/boxes vs the visible meshes (prop Heights and scales in the Props file, piece sizes from
     python3 tools/checks/mesh_orientation.py's read_glb on assets/meshes/<Prop>.glb if needed) and the R15 character (about 2 wide,
     5 tall; HumanoidRootPart at hip height);
   - timing: what the client draws when (interpolation, animations that take time, the shared schedules) vs the instant the server
     judges; the press travels ~ping/2 (GetNetworkPing is a round trip); other players' characters are drawn ~0.1-0.2 s behind;
   - moving things: is the test sampled often enough (a fast rope/arrow can skip past a player between server steps: use swept tests);
   - edges: standing on a tile/hex/bridge edge, half on a platform, the moment a hazard starts/ends.
   Note the mismatches with numbers ("server radius 1.5, visible ball radius 3.2", "judged at the press, visible swing 0.4 s later").
3. Fix them, following the principle. Keep changes inside this mode's files (server, client, brain, harness bot
   tools/checks/bots/${g.id}.luau). If the client shows a cue (highlight, ring, timing bar, "perfect" zone), make it match the server's
   rule exactly. Keep the style: tabs, StyLua, comments that say why (quote the owner's words once in the module's top comment).
4. Verify: tools/checks/mode_check.sh ${g.id} (code checks, a 12-player round with the client half, a round with 10 real bots, the
   phone HUD). Requires 0 errors, bots still playing convincingly (not all winning or all losing), sensible results, phone UI clean.
   Compare the bots' outcomes before and after where it tells you something (e.g. run the bots round on the base commit first).
   The test server has no physics: harness bots move rigs with PivotTo. Use /tmp/hit_${g.id}* paths for every temp file.
5. Commit in the worktree with a clear message ending with exactly these two lines:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0118DxSUkAz3MXNwL4Bb3UDh
   then: git branch -f hit/${g.id} HEAD. Do not push, do not touch other branches, never put model names in commits or files.
If you find nothing that needs changing for a test, say so with the numbers that show it's fair. Work efficiently: read only what you need.`

const SCHEMA = {
  type: 'object',
  properties: {
    worktree: { type: 'string' },
    branch: { type: 'string' },
    commit: { type: 'string', description: 'commit hash, or "none" if nothing changed' },
    tests: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          what: { type: 'string', description: 'the hit/catch/timing test' },
          before: { type: 'string' },
          after: { type: 'string' },
          why: { type: 'string' },
        },
        required: ['what', 'before', 'after', 'why'],
      },
    },
    sharedFileChanges: { type: 'array', items: { type: 'string' } },
    testResults: { type: 'string', description: 'mode_check results: errors, bots, results, phone UI' },
    summary: { type: 'string', description: 'plain words for a non-programmer owner: what felt unfair and what changed' },
    openIssues: { type: 'array', items: { type: 'string' }, description: 'what only a real playtest can confirm' },
  },
  required: ['worktree', 'branch', 'commit', 'tests', 'sharedFileChanges', 'testResults', 'summary', 'openIssues'],
}

phase('Tune')
const results = await pipeline(GAMES, (g) =>
  agent(PROMPT(g), { label: `hitbox:${g.id}`, phase: 'Tune', schema: SCHEMA, isolation: 'worktree', effort: 'high' })
    .then((r) => r && { id: g.id, ...r }))
return results.filter(Boolean)
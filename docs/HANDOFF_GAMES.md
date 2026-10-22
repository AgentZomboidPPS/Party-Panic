# Handoff: building new mini-games in a separate session

You are a game-building session for Party Panic. The owner asked to hand off mini-games so they get built in
parallel ("can we handoff any of the mini games?"). A coordinator session (Session B, session id
`session_01TkuGjJa1hD9yT5rM1jPfjD`, branch `claude/upbeat-galileo-gvwq66`) owns reviewing, merging, testing and
publishing. You build the games listed in your first message, in that order, and hand each one back finished.

Read first: [HANDOFF.md](HANDOFF.md) section 1 (the owner and the house rules), [ADDING_MINIGAMES.md](ADDING_MINIGAMES.md),
and for each game its brief in [builds/](builds) (`docs/builds/<Id>.md`, generated from
`tools/workflows/build-minigame.js` and [MINIGAME_BACKLOG.md](MINIGAME_BACKLOG.md)).

## Setup (a fresh container; GitHub downloads are blocked here, git and crates.io work)

Start the long builds in the background, then read while they run (about 15 minutes):

```
cargo install --locked stylua@2.6.0 --features luau
cargo install --locked selene@0.31.0
cargo install --locked rojo@7.7.1
cargo install --locked lune@0.11.0
git clone --depth 1 --branch 1.70.1 https://github.com/JohnnyMorganz/luau-lsp /home/user/luau-lsp
git -C /home/user/luau-lsp submodule update --init --depth 1
mkdir -p /home/user/luau-lsp/build && cd /home/user/luau-lsp/build \
  && cmake .. -DCMAKE_BUILD_TYPE=Release "-DCMAKE_CXX_FLAGS=-Wno-error=maybe-uninitialized -Wno-maybe-uninitialized" \
  && cmake --build . --target Luau.LanguageServer.CLI --config Release -j3 \
  && ln -sf "$PWD/luau-lsp" /usr/local/bin/luau-lsp
cp /home/user/luau-lsp/scripts/globalTypes.d.luau <repo root>/globalTypes.d.luau   # git-ignored
pip3 install --break-system-packages scipy scikit-image                         # mesh and music tools
python3.11 -m venv /root/bpy311 && /root/bpy311/bin/pip install bpy numpy Pillow
export PP_BPY_PYTHON=/root/bpy311/bin/python                                     # Blender renders
```

`/root/.cargo/bin` must be on PATH. Roblox Open Cloud works through the environment's proxy (requests to apis.roblox.com
get the owner's credential injected; no key needed). Test servers have no physics.

## Games already started

Four games, Tanks!, Spleef, Mecha-Marathon and Prime Cut, were started in the coordinator's container and stopped by a
restart. Their work was saved as git bundles in `docs/wip/`, which the game sessions restored and finished. All four
are merged, and their bundles were removed.

## Games 27-29 (2026-10-22)

The owner asked for one more Survival, Luck and Race game and picked these ("Let's add the stars. If you need to hand them
off do it."). Briefs: [MINIGAME_BACKLOG.md](MINIGAME_BACKLOG.md) 27-29 and `docs/builds/<Id>.md`. All three are merged
since (Dice Dash 51ba233, Hot Potato c153118, Minecart Mayhem 81c0144), each with its portal preview.

| Game | Category | Session |
| --- | --- | --- |
| Hot Potato (`HotPotato`) | Survival | games-1 |
| Dice Dash (`DiceDash`) | Luck | games-2 |
| Minecart Mayhem (`MinecartMayhem`) | Race | games-3 |

- **Branches:** a session can only push its own `claude/games-N` branch, so each game is built there (merge the
  coordinator's latest in first). `claude/games-2` and `claude/games-3` carry the second shop pass, which the owner holds
  back until "after everything else is finished": keep it there, never force-push or reset those branches (a copy is in
  `docs/wip/shop-pass2.bundle`), keep the game in its own files and commits, and list in the report every file the game
  changed outside its own new files. The coordinator takes only the game's changes.
- Give the definition `IsNew = true`. The coordinator keeps the vote's new-game boost within its cap when merging.
- Report as in "Reporting back" below.

## How each game gets done

1. Build it per `docs/builds/<Id>.md` (you may run two games at once with helper agents, each in its own git worktree;
   the machine has 4 CPUs, so keep Blender renders few and small).
2. An independent review by a fresh helper that didn't build it: bugs, exploits, races, players leaving, 1/2/5/12
   players, hazard parity, phone UI, feel, and **nothing solid where nothing is drawn** (the owner's latest bug report:
   "Theres invisible stuff you can jump on and hang on in several games": no invisible walls a player can jump onto, no
   hidden helper parts left collidable — Roblox Parts default to CanCollide = true — and prop collision that hugs the
   drawn shape). Then fix what it confirms.
3. `tools/checks/mode_check.sh <Id>`: 0 errors in the 12-player, bots and phone rounds, phone UI 0 problems; look at
   the PNGs. Code checks clean (stylua, selene, luau-lsp, lune).

## Rules

- Never run `tools/publish_place.py`, never change place settings, never open pull requests. Uploading your game's
  meshes under the owner's account (user 11690979745) with `tools/upload_assets.py` is allowed.
- Never write to a real player's DataStore key from a test.
- Don't edit shared core files (RoundContext, RoundManager, Kit/Api, client Controllers, MeshLibrary core, BotService,
  Shapes, other modes). If you truly must, keep it small and additive and say so in your report.
- Each game adds its GameDefinitions entry just above `-- NEW MINI-GAMES GO ABOVE THIS LINE`. Other sessions do too; the
  coordinator resolves those small merge conflicts.
- Don't make portal previews (`tools/preview/make_preview.py`): the coordinator does that after merging.
- Before each push, merge the coordinator's latest branch into yours (`git fetch origin claude/upbeat-galileo-gvwq66`,
  `git merge FETCH_HEAD`), re-run your mode's checks, then push your own session branch.

## Reporting back

When a game passes all three steps, push your branch and tell the coordinator with the claude-code-remote
`send_message` tool (session id `session_01TkuGjJa1hD9yT5rM1jPfjD`): the game, your branch and commit, the mode_check
lines, the meshes (names, asset ids, moderation state), what only a real-game playtest can confirm, and any shared-file
change. Then start the next game on your list. If you get stuck on something only the owner can decide, say so in
that message too.

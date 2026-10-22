# Handoff for a new window: the second shop pass, then the 👎 downvote

Written 2026-10-22 ~19:10 UTC by the session that shipped versions 37-39. Read `docs/HANDOFF.md` too: its top block
lists what is live. This file covers only the two jobs the owner saved for last.

## Where things stand

- **Live: version 39** (published ~18:54 UTC from `0b9ff72` on `claude/upbeat-galileo-gvwq66`). It has 30 mini-games,
  the party glow-up, the GOLD PASS (game pass 2048378768, on sale at 399 Robux) and every fix the owner asked for
  today. Start from the tip of `claude/upbeat-galileo-gvwq66` (`git fetch origin claude/upbeat-galileo-gvwq66`), not
  from an older branch.
- **The owner's standing word on publishing:** "You can push as soon as things are finished for now untill the game is
  live to the public." Publish each finished, checked update yourself while the experience is private:
  ```
  python3 tools/publish_place.py --universe-id 10772087888 --place-id 78868713931081
  ```
  Run it from a checkout of the commit you ship. The place-settings PATCH 403 at the end is expected. Then tell the
  owner to **restart servers**. Once the game goes public, ask before every publish again.
- **Rules that always hold:**
  - The experience stays PRIVATE.
  - Never write to real players' DataStore keys (UserIds 11690979745, 11710053411, 42164532, 11752977477). The harness
    stand-ins use UserIds 1001 and up.
  - Every commit ends with the two attribution lines the session gives you, and no model names go in commits or files.
  - Don't open pull requests unless the owner asks.
- **The owner** is not a programmer, plays on iPhone and PC with friends, and likes short plain updates. Quote their
  words in header comments, as the code does everywhere.

## Checks you will need

The toolchain for a fresh container is in `docs/HANDOFF.md` ("Toolchain in a fresh container").

- **Code:**
  - `stylua --check src tests tools/checks`
  - `selene src`
  - `rojo sourcemap default.project.json -o sourcemap.json && luau-lsp analyze --definitions=@roblox=globalTypes.d.luau --sourcemap=sourcemap.json src`
    (no output means clean)
  - `lune run tests/run` (329 tests pass today)
- **Real servers** (Open Cloud Luau execution on the owner's place; the proxy adds the key):
  - `tools/checks/mode_check.sh <Mode>`: 12 players, bots, and a phone round with UI renders.
  - `tools/checks/client_harness.py [--touch]` piped through `tools/preview/luau_task.py`, then
    `tools/checks/ui_render.py`: the whole client on phone and PC screens.
  - `tools/checks/round_harness.py LOBBY --bots 8 --seconds 30`.
  - The full sweep this session used runs code checks, all 30 modes, the lobby and both clients. It took ~45 min with 3
    at once, so give a background run a 2-hour timeout.
- **Open Cloud limits:**
  - At most 5 task starts a minute.
  - "INTERNAL_ERROR Task timed out" or an HTTP 400 is transient: re-run once.
  - **Scripts are capped at 1 MiB.** The biggest test bundles are now about 1.01 MB (Shark Bait's phone run, Pump & Pop
    with `--party`). New client code eats that headroom.
  - If a mode's tasks fail with "Script too large", see `tools/checks/bundling.py` and `slim` in
    `tools/checks/round_harness.py`. Every quoted "...Controller" in the harness's Luau seeds a run with that
    controller, so keep such names out of code that every run reaches.
- **Known flake:** race-bar dots (Skate Escape, Rockin' Raceway) can overlap in one phone snapshot while they ease into
  place. That is not a regression.

## Job 1: the second shop pass (25 coin items + 10 effects)

The owner held it "after everything else is finished". Everything else is finished now.

- **Where it is:** branch `hold/shop-pass2` at `885f5ef`. Get it with
  `git fetch docs/wip/shop-pass2.bundle hold/shop-pass2:hold/shop-pass2`; it's also on origin's `claude/games-3`. Its
  merge base with today's line is `39026ba`, an old tree from before Friends, Party Cups, Medals, Halloween, the party
  glow-up and the Gold Pass.
- **Do NOT merge the branch whole.** It carries reverts of an old round-music attempt (`9e377c4`, `2948ca1`, `2af3bd7`,
  `3ec088a`, `6caad40`). Merging would delete `tools/music/instruments.py`, `modes.py` and `score.py`, which the live
  music needs.
- **Cherry-pick the shop commits only, in order:**
  1. `2fb8c26`: 25 more coin items (trails, titles, emotes, victory and knockout effects), 10 new effects, and
     `tests/Catalog.spec.luau`.
  2. `bb0aacc`: the client harness opens every shop tab on phones.
  3. `ba5dbaa`: checks that play every cosmetic effect, and `tools/checks/scenarios/ShopEffects_round.luau`.
  4. `7df1526`: review fixes. With reduced effects nothing flashes, and Balloon Release, Streamer Storm and Frozen Out
     get their own effects.
  5. `f0cb9da`: economy notes and their test (about 60 coins a day; the whole shop in about 23 days).
- **The other commits there:**
  - `47900b3` (idle stand-in scenario) is optional.
  - `5a406c4` and `6d55fde` (Snowball and Tanks bots) may already be on the line as cherry-picks (`39026ba` is the
    Snowball one), so skip any that come out empty.
  - **Skip `a83c440`** (vote variety). It ends the new-game boost for five games, but today's GameDefinitions has its
    own IsNew list (14 of 30, within VoteFairness's half cap). Take its simulator and spec only if they still fit.
- **Expect conflicts in:**
  - `src/shared/Cosmetics.luau`. The Gold Pass adds its 33 items from `src/shared/GoldPass.luau` and keeps its edits in
    Cosmetics tiny; keep both sets. Make sure no Id clashes.
  - `src/client/Controllers/EffectsController.luau`. It now requires `src/client/GoldEffects.luau`; keep both.
  - `tools/checks/client_harness.py` (the controller order list), `gui_dump.luau` and `ui_render.py`.
  - The shop window (`ShopController`), if the pass touched it.
- **What the shop must do after the merge:**
  - Hats exist now (the Halloween pumpkin hat, the Gold Pass hats). Make sure the new tabs and filters still show them.
  - Gold Pass items (`GoldPass = true`) must never be for sale for coins.
  - Re-check the economy against today's income: an average round pays about 2.75 coins. The Gold Pass adds about
    1-8% (`tests/GoldPass.spec.luau`, `tests/Payoffs.spec.luau`).
- **Glyphs:** the game fonts draw ★ ✕ ✚ ☾ ◐ ✦ ☆ ☰ as blanks (`tests/Marks.spec.luau`); use ⭐ ❌ X or drawn shapes.
  Don't use 🪙 (phones lack it; use UIKit.Coin). Search the new item names and icons for these.
- **Before publishing:**
  - code checks;
  - the Catalog, Payoffs and Marks specs;
  - `client_harness.py --touch` and PC, looking at the shop renders on every phone size;
  - the effects scenario;
  - a few modes where effects fire (Fire Rope, Spleef, Bumper Ballers);
  - the lobby.
  Then publish, tell the owner, and show them a render of the new shop tab.

## Job 2: a 👎 per mini-game, and a tool to read the totals

The owner's words: "lets add to the backburner a away for players to downvote a minigame and then we can harvest that
data to disable minigames in the future." The plan in `docs/MINIGAME_BACKLOG.md` ("On the backburner") was agreed:

- **The button:**
  - A 👎 on the results card ("Not for me"). A 👍 beside it is fine.
  - One vote per person per round they played, changeable until the results card closes. Never from bots or sit-outs.
  - Mind phones: 44 pt targets, and the card's layout checks (`ui_render`).
- **Server:**
  - A remote (append to `src/shared/Remotes.luau`).
  - Check that the voter played that round (RoundContext / RoundManager know who did), and rate limit it
    (`Services/RateLimiter`).
- **Totals:**
  - Running totals per game in a DataStore of its own, keyed by game and ISO week: plays, 👎, 👍, unique voters.
  - Use UpdateAsync increments, batched per round, not one write per vote.
  - Store next to them the signals the game already has: PLAY AGAIN yes/no (`Services/ReplayService`) and how often
    each game wins the vote (`Services/VotingService`).
  - Never touch the player profile store, and never write per-player keys for real players.
- **A tool**, e.g. `tools/checks/game_ratings.py`. Model it on `tools/checks/client_reports.py`, which reads a
  DataStore through an Open Cloud task. It prints a table per game: plays, 👎 rate, 👍 rate, replay yes-rate, vote
  wins, last 4 weeks. The owner then switches a game off with `Enabled = false` in `src/shared/GameDefinitions.luau`.
- **Tests:**
  - A Lune spec for the pure counting logic: one vote per person per round, changes replace, bots are ignored.
  - A harness scenario where stand-ins vote on the results card and the totals land.
  - Read the totals back with the tool, on test-server data only.

## Smaller things still open (from today)

- **Bots' rubber-banding:**
  - The fixes are live. After the owner's next playtest with bots, read `python3 tools/checks/client_reports.py --bots`.
  - Success means snap, hover, head and seat counts at 0; Spleef bots never anchored; Drops 0; Retakes 0.
  - Other modes still move anchored bots by CFrame (Snowball flights, Stamp Out hops, Parasol, the rides, the Hex drop).
    Act only if the reports show trouble there.
- **Gold Pass:** a real purchase can only be seen from another account (the creator owns it automatically).
- **Vote cards on phones:** at the owner's request ("bottom middle ... 25% larger") the two left cards reach into the
  MOVE stick's corner during the vote. If the owner minds, nudge the row right (`VoteController`, TOUCH_* constants).

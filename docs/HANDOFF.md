# Handoff: Party Panic (for the next Claude)

Last updated: **2026-10-22 03:15 UTC** by Session B (branch **`claude/upbeat-galileo-gvwq66`**, which started from
`claude/quirky-hopper-5yk8zk` at ee14d80). Session B is still working; see "Session B in flight" below. Sections 0-9 are
Session A's handoff from 17:40 UTC, still accurate except where this block says otherwise.

## Session B in flight (2026-10-22 03:15 UTC)

- **Live version 34** (published 02:38 UTC on 2026-10-22 from `claude/upbeat-galileo-gvwq66` at `1f08776`, on the
  owner's "merge my branch claude/quirky-hopper-5yk8zk" and that window's "merge my branch ... and publish"; the owner
  must restart servers).
  - **Quick check on that exact commit:**
    - code checks;
    - the 12-player, bots and phone rounds of SinkingSands, PrimeCut, RockinRaceway, PumpAndPop, LogJam, Struggle,
      ArrowAmbush and HoneyTrap;
    - a lobby round with 8 bots;
    - the whole client on phone and PC.

    All had 0 errors and 0 render problems. The full regression of v33 (all 25 games) was clean.
  - **What it adds to v33:**
    - the invisible-collision sweep: precise mesh collision, no reachable invisible walls, and the CSG fallback from
      pieces;
    - no falling through floors on load-in (`ArrivalController`, plus a put-back before GO);
    - the lobby at 20 s, with the vote ending 1 s after the last person votes;
    - the rules card's ✕;
    - the Sand King rework (BLAST, SUNKEN CHEST, stronger PULL);
    - team identity (Prime Cut's grills, the YOU'RE ON tab, the YOU mark on the pill);
    - Rockin' Raceway's 3D hurdles;
    - Log Jam and Struggle (27 games);
    - Tanks! and Snowball Summit bot fixes;
    - the vote-variety spec;
    - all 27 portal previews;
    - Stamp Out's 👣 icon;
    - the Skee-Ball flicker and grass fix;
    - from the owner's other window's branch `claude/quirky-hopper-5yk8zk`: per-game round songs (5 packs, NOT
      uploaded yet, so every game plays Panic Mode until `AudioAssets` gets the ids) and Friends (invite chip, +1 coin
      with a friend, beat-a-friend moments).
  - **Store description:** `docs/STORE_DESCRIPTION.txt` lists 27 games. The owner pastes it in Creator Hub, because
    publish_place can't set it (403).
- Version 33 was published 00:58 UTC from `d10b635`, and version 32 at 21:55 UTC from `6e0029b`; both regressions
  were clean.
- **On the branch since version 34 (ships in version 35):**
  - Sinking Sands' role chip (💎 DIVER / 👑 SAND KING all round) and team-marked results rows (owner: "I couldnt tell
    what color I was on prime cut.");
  - Slaparazzi bots (owner: "Bots are terrible at slaparazzi");
  - the Spleef rework from games-2 (owner: "spleef doesnt require you to dig. It should be you walk over it and it
    fades out within like 1 second or so", "Bots are awful at spleef", "make the spleef arena larger"), squashed
    from `claude/games-2` 7073f05..1c0d206 without that branch's held shop commits;
  - the PLAY AGAIN replay vote (owner: "Add a vote at the end of each minigame to replay the same minigame."):
    `Services/ReplayService`, `Logic/ReplayVote`, the results card's PLAY AGAIN? / NO THANKS; more than half of the
    round's people (never bots or anyone sitting out) replays the same game straight away, at most 3 plays in a row;
  - the lobby's sky islands moved 700-1200 studs out, clear of every arena (they broke through the floor or sea of 21
    arenas; games-2 saw a Spleef bot standing on one), and `tools/checks/colliders.py` now flags terrain near arenas.
- **Still to come for version 35:**
  - games-4's phone performance audit (`claude/games-4`: the round harness's `perf` line, cached participant lookups,
    fewer per-frame writes in Trace Race, Skate Escape, Tanks!, Crazy Cutters and others);
  - the round songs: the owner's other window uploads the 5 packs and pushes their ids to
    `claude/quirky-hopper-5yk8zk`; until then every game plays Panic Mode.
  A quick check of 7d3137b (code checks; SinkingSands, Slaparazzi, Spleef and PumpAndPop rounds; the lobby; the client
  on phone and PC) is running. Publish on the owner's word.
- **Games 27-29, building** (owner: "Let's add the stars. If you need to hand them off do it."): Hot Potato (Survival,
  games-1), Dice Dash (Luck, games-2) and Minecart Mayhem (Race, games-3), each on its session's `claude/games-N` branch
  (sessions can only push their own branch; games-2's and games-3's also carry the held shop pass, so take only the
  game's changes from them). Briefs: `docs/MINIGAME_BACKLOG.md` 27-29 and `docs/builds/`. On merge: keep
  IsNew within the vote's cap (`tests/VoteFairness.spec.luau`: at most half of the games), make portal previews, add
  them to `docs/STORE_DESCRIPTION.txt` and the lineup doc.
- **Held until the owner says the bug-fix wave is done ("after everything else is finished"):** the second shop
  pass, 25 coin items and 10 effects, finished on `claude/games-3` at f0cb9da (reviewed; its client checks are in
  the same branch; a copy is in `docs/wip/shop-pass2.bundle`). `claude/games-2` also carries the earlier shop commits, so don't merge that branch whole.
- **Game sessions** (see [HANDOFF_GAMES.md](HANDOFF_GAMES.md)): all 14 backlog games are merged (27 games); games-1
  to games-3 are building games 27-29 and games-4 is on the performance audit.
- **Later (owner):** the owner's call on rebalancing thin categories (Messy Memory to Luck, Tanks! to Knockback).
- **Toolchain in a fresh container (GitHub downloads are blocked here):** `cargo install --locked stylua@2.6.0 --features
  luau`, `selene@0.31.0`, `rojo@7.7.1`, `lune@0.11.0` (crates.io works); luau-lsp from source: `git clone --depth 1
  --branch 1.70.1 https://github.com/JohnnyMorganz/luau-lsp`, `git submodule update --init --depth 1`, cmake Release with
  `-DCMAKE_CXX_FLAGS=-Wno-error=maybe-uninitialized`, target `Luau.LanguageServer.CLI`; `globalTypes.d.luau` is in that
  repo's `scripts/`. Blender: `python3.11 -m venv` + `pip install bpy` (5.0.1). Mesh/music tools: `pip install scipy
  scikit-image`.

## Session A: songs uploaded, and the five "keep players coming back" features (2026-10-22 05:00 UTC)

Branch **`claude/quirky-hopper-5yk8zk`**. Session B merges it before publishing (the owner tells it to).

- **Round songs uploaded** (owner: "take over the music.", then "Upload now"). There are 5 packs:

  | Pack | Id |
  | --- | --- |
  | ModePack1 | 133632130255608 |
  | ModePack2 | 117185721710928 |
  | ModePack3 | 96432706159875 |
  | ModePack4 | 91819577463974 |
  | ModePack5 | 111855655225102 |

  - All five are approved by Roblox and recorded in `AudioAssets` and `assets/uploaded.json` (c7dcb2d).
  - That used 5 of the owner's 10 audio uploads for this month.
  - Each of the 27 games plays its own song with the drop on GO (`tools/music`, `ModeMusic.luau`, `AudioController`).
  - Re-check a game's timing with `python3 tools/music/modes.py check` when its round length changes. Replacing a song
    costs an upload.
- **The five features.** The owner asked "If you could do 5 things to keep players addicted what would you do?", then
  "Can you work on all of that? this wont mess with what the other workers are working on right?". Each one is built
  in its own files, hung on these shared hooks:
  - `RoundEvents.Finished` (fired by RoundManager after the rewards);
  - `Boosts` (extra coin lines on a round's reward);
  - the save fields `Cups`, `Medals`, `Weekly` and `Events`, which the client snapshot carries;
  - the GameState keys `Cup`, `Event` and `HallOfFame`;
  - the lobby's chip row `UI/LobbyRibbon`. Chip priorities: 1 Event, 2 Cup, 3 Invite, 4 Weekly. On phones it sits in the
    first-join tip's spot. On PC it sits under the banner, below the coins line;
  - `MedalService.Award(player, id)`.

  The features:
  1. **Friends** (`FriendsService`, `InviteController`, `Logic/FriendLogic`):
     - 👋 INVITE chip that opens Roblox's invite prompt;
     - +1 coin for a round played with a Roblox friend;
     - "You beat Ann!" / "Bo beat you" toasts after the results;
     - "Ann is here!" when a friend joins.
  2. **Party Cups** (`CupService`, `CupController`, `World/CupCrown`, `Logic/PartyCup`):
     - every 5 rounds on a server make one cup, scored 10/8/6/5/4/3/2 then 1;
     - bots can win;
     - after the 5th round a podium pays 5/3/2 coins to people;
     - the champion wears a crown in the lobby until the next cup ends. It comes off for their rounds.
     - A PLAY AGAIN replay puts the podium off until the next real lobby.
  3. **Medals** (`MedalService`, `MedalController`, `World/MedalWall`, `Shared/Medals`, `Logic/MedalLogic`):
     - one per game (27, built from GameDefinitions) plus 9 big ones;
     - a MEDAL EARNED card at a calm lobby moment;
     - a 🥇 Medals tab in the Rewards screen;
     - a medal wall on the south-west lawn that each client lights up;
     - Roblox badges once ids go in `BADGE_IDS` (`Shared/Medals.luau`). All are 0 now.
  4. **Weekly leaderboard + Hall of Fame** (`LeaderboardService`, `HallOfFameController`, `World/HallOfFame`,
     `Logic/WeeklyLogic`):
     - points 10/7/5 + 1 for playing, reset Monday 00:00 UTC;
     - an OrderedDataStore `PP_Weekly_<week>` per week, written in the background;
     - statues of last week's top 3 between the winner podium and the shooting gallery;
     - the 📈 chip and the THIS WEEK window.
  5. **HALLOWEEN PARTY + 2× coins weekends** (`EventService`, `EventController`, `World/EventDecor`, `Shared/Events`,
     `Logic/EventLogic`):
     - runs until 2026-11-02 00:00 UTC (`Ends` in `Events.luau`);
     - candy from rounds and 3 golden pumpkins a day in the lobby;
     - a free track of 6 limited cosmetics at 10/25/45/55/70/100 candy, with the Halloween medal at 100; the
       PUMPKIN HAT at 55 is the headline (a new Hat slot: `World/Hats` builds it as an Accessory, worn in the
       lobby, off in rounds and under the cup crown; mesh `tools/meshgen/props/Hats.py`, model 82691154142514);
     - decorations and a spookier lobby look, drawn per device;
     - double coins on the Saturdays and Sundays during the event (UTC; owner: not after Halloween).
- **Shared screen rules added for them:**
  - Toasts wait while the results card or the cup podium is up (`PP_ResultsShowing`, `PP_CupPodium`;
    NotificationController).
  - The results card draws 6+ reward lines compact.
  - Pop-ups wait for calm lobby moments.
- **Checks:**
  - Each feature has its own round-harness check on a real server: `weekly_check.py`, `round_harness.py CUP`,
    `scenarios/Friends.luau`, `scenarios/Medals_check.luau` and `scenarios/Event_halloween.luau`.
  - Client harness blocks: `cupChecks`, `medalChecks` and `eventChecks`.
  - All passed. Together, with version 35's PLAY AGAIN merged in: 6 real rounds of a cup with all five services on
    (`round_harness.py CUP --players 3 --bots 5`): 0 errors, 28/28; the whole client on phones (5 sizes): 0 errors, 0
    render problems; on PC: 0 problems after the chips moved below the coins' line and step aside for level-up and
    medal cards.
- **Tests never write real data:** under the harness flag (`workspace PP_Harness`) the weekly board uses an in-memory
  store and badges are only listed.
- **Not checkable here:**
  - real friendships and invites;
  - badges;
  - DataStores at scale;
  - real avatars on statues;
  - the lobby look;
  - touching a pumpkin;
  - the crown on a moving character.
- **The owner decided** (05:40 UTC, "No yes yes no do pumpkin hat now"):
  - no Roblox badges (the `BADGE_IDS` stay 0);
  - the event's end date and candy amounts stay;
  - the cup values stay;
  - no double coins after Halloween: only on the weekends during the HALLOWEEN PARTY (24-25 Oct, 31 Oct-1 Nov UTC;
    done, 6d89d31);
  - the pumpkin hat now: done (see the HALLOWEEN line above; mesh model 82691154142514, approved).
- **Songs for games 27-29**, uploaded on the owner's "Upload now" as ModePack6 111377793680965 (approved):
  - Hot Potato: "Mambo Kaboom";
  - Minecart Mayhem: "Crystal Cave Express";
  - Dice Dash: "Lucky Roll Cha-Cha".

  All 30 games have their own song. 6 of the owner's 10 audio uploads this month are used. A new game's song goes in
  a new pack: `modes.py pack` never changes an uploaded one.

## 0. Start here (the first 10 minutes)

1. Read section 1 (the owner and the house rules), then skim section 6 (map of the code).
2. Check what's live: `git log --oneline -5` on `claude/quirky-hopper-5yk8zk`, and the "Live version" line below.
3. **Tell the owner to restart the game's servers after every publish.** Their client reports showed everyone still
   on **version 27** at 17:15 UTC, two publishes behind, so they were reporting bugs that were already fixed (the rules card
   covered by game UI was fixed in version 28). Live servers keep the version they started with. Creator Hub > Party
   Panic > the "..." menu > **Restart servers** (or "Shut down all servers"), then rejoin.
   `python3 tools/checks/client_reports.py` shows which place version each player's device is on.
4. Ask the owner which of the open items (section 2) to do first.

**Live version: 30** (published 17:45 UTC): everything in section 2.1 (Hex Meltdown floating bots and small banner,
Honey Trap tutorial). The owner still has to restart servers to get it.

## 1. The owner and the house rules

- The owner is **not a programmer**. Explain in plain words, say what to click, keep updates short and concrete. They
  play-test on **phones** (iPhone, small screens) and PC with friends, and report problems as one sentence or a
  screenshot ("This", "Bot is floating."). Read screenshots closely: zoom into them (crop + upscale with Pillow); the
  floating bots were small figures at the edge of the frame.
- They want a "masterpiece": great looks, great UX, "it just has to work". No workarounds that hide a problem (owner: "I
  dont want you to do a fix for if they dont load. I want you to fucking make our own meshes work").
- **Private only.** Universe `10772087888`, place `78868713931081`, owner user `11690979745`. The experience stays
  PRIVATE; `tools/publish_place.py` refuses to publish to a public one. All uploads go under user `11690979745`.
- **Git:** branch `claude/quirky-hopper-5yk8zk`, push after every change. Every commit message ends with your session's
  attribution lines. No pull requests unless the owner asks. Never put model names in commits or files.
- **Style:** Luau, tabs, StyLua. Every module starts with a comment block saying what it does and quoting the owner's
  words that asked for it (each later pass adds a paragraph the same way). Game names in capitals in player-facing text,
  colour never the only cue, English only (no localization table in this project). Phones first: big touch targets,
  inside the safe area, never over the right-hand menu column, the jump button or the MOVE stick.
- **Server owns everything:** scoring, positions, eliminations, timing; clients ask and draw. Every mode has a bot brain
  with hazard parity (whatever hurts players must hurt bots).
- **Fair hits** (owner: "the precision games will feel super bad if we dont"): if it looks like a hit on the player's
  screen it counts, if it looks like a dodge it doesn't. Judge against what the client saw (ping leeway), make server
  radii match the visible meshes, make client cues use the server's exact rule. Reference: `RakeItIn.luau` (`Takes`).
- The game: a lobby (plaza, obby, beach balls), a vote on 4 cards (3 games + RANDOM; bots never vote), a mini-game for
  up to 12 players with bots filling empty spots, results, back to the lobby. A PLAYING / SITTING OUT switch lets people
  skip rounds.

## 2. Open work, most urgent first

### 2.1 Done but not yet seen by the owner (commit `bed7669`; ask them to try it after the restart)

- **Hex Meltdown, "Theres invisible stuff." / "Bot is floating."** Zooming into the owner's two screenshots showed bots
  hanging high in the air near the crater wall. Cause: the server moves bots and each player's device moves that
  player, so when they touched (a player landing on a bot to stomp it, or walking into it) Roblox shoved the bot out of
  the way, sometimes hard enough to fly it over the lava; a stomp on two heads at once also added two bounces. Fix in
  `src/server/MiniGames/HexMeltdown.luau`: bots (`PP_HexBots`) and players (the lobby's `PP_Players` group, set by
  `World/BeachBalls.luau`) don't collide in this mode (stomps go by position, so they still work); a stomp bounces once
  per landing; `_limitBots` caps every bot's speed (30 flat, 60 up) as a safety net. Tested: 12-player round, 10 real bots,
  phone HUD: 0 errors. **Not testable here:** Open Cloud test servers have no physics, so the owner has to confirm in a
  real game. If bots fly in other games too, the same split (bots vs `PP_Players`) is the fix; it's only in Hex Meltdown
  so far.
- **Hex Meltdown, "This"** (screenshot of the big "● RED ●" panel covering the referee's call board): the call banner is
  now a small pill under the status line (`src/client/MiniGames/HexMeltdown.luau`).
- **Honey Trap, "Players think they have to go to the tree."** Players are frozen on their flowers (WalkSpeed 0) and play
  with HIT or a jump, but the old rules said "Take 1 or 2 from the tree". New rules card text in `GameDefinitions.luau`
  ("Stay on your flower! ..." / "No walking! On your turn, press HIT or jump ..."), the between-turn hint says "Stay on
  your flower - the fruit comes to you!", and pushing the stick shows "No walking needed - you play from your flower!"
  for 3.5 s (`src/client/MiniGames/HoneyTrap.luau`). Checked: the card fits the smallest phone; 12-player round 0 errors.
- **Rules card covered by game UI** ("a lot of mini games are having issues where the UI is on top of the tutorial"):
  fixed in version 28 (the mode's whole ScreenGui hides while `PP_RulesShowing` is true; `Kit/Api.luau`), and the card
  stays 10 s. The owner's Pump & Pop screenshot was from a version 27 server. If they still see it after a restart, find
  which ScreenGui draws over the card (the main HUD is DisplayOrder 5, a mode's is 6).
- **Friends' music:** works now. The friend's device report (version 27) says the lobby music loaded and plays, not
  silent. If the friend still hears nothing, it's their device volume or Roblox music setting. Tell the owner.

### 2.2 Stopped half-way (the owner asked for these; work saved in `docs/wip/`, unmerged and unreviewed)

Restore one with `git fetch docs/wip/<name>.bundle wip/<name>:wip/<name>` then `git checkout wip/<name>` (or diff it
against `claude/quirky-hopper-5yk8zk`). Each bundle's last commit, "WIP (stopped)", is the uncommitted state at the
moment it was stopped, never tested. Read before reusing: continue it, take parts, or redo.

| Request (owner's words) | Saved as | State when stopped |
| --- | --- | --- |
| "we need cool payoffs for players that keep playing the game" + "balance the shop down. I want low currency not high" | `payoffs.bundle` (3 commits, ~3000 lines, 30 files) | Low coin scale, a "Rewards Road", career milestones, celebration pop-ups (`Progression.luau`, `CelebrationController`, `RewardsController`, `Economy`/`RewardService`/`ShopService` changes). **Risky: it changes saved coin balances**; check the migration of existing players' coins (DataService) and every price before shipping. |
| "Can we also add skiball to the lobby?" | `skeeball.bundle` (7 commits) | An arcade corner with four Skee-Ball machines: shared ball path `Logic/SkeeBall.luau`, `SkeeBallService`, `World/Arcade.luau`, `SkeeBallController` (play screen, meter), props in `tools/meshgen/props/Arcade.py` with meshes **already uploaded** (asset ids in `World/Props/Arcade.luau`), a 9-ball game check on a real server (`tools/checks/skeeball_game.luau`). Last work: phone layout of the play screen. Needs: a review, a phone pass, the LobbyBuilder hook checked against the obby. |
| "Bots are terrible at this game" (Sinking Sands) | `sinkingsands-bots.bundle` (1 commit) | Changes to `Bots/SinkingSands.luau`, `MiniGames/SinkingSands.luau` and its client: the agent had found divers scoring 0-4 and was comparing brains in an offline simulator plus test-server runs. Also meant to shorten the Sand King hint that wraps on phones. Untested as saved. |
| "Bumper balls control scheme is really bad on mobile" | `bumper-controls.bundle` (1 commit) | New `src/shared/Logic/BumperDrive.luau` (how the stick steers the ball, unit-tested in `tests/BumperDrive.spec.luau`, response table from `tools/checks/bumper_drive.luau`) wired into the server's steering and the client's controls and camera. Not run on a test server; the tilt option must keep working. |
| "I keep clipping into some chair on fire rope what is going on?" | nothing saved (no code changed) | Diagnosis only: there is no chair in the arena. The agent rendered player-height views and was checking where Roblox's default camera (12.5 studs behind the player) ends up inside props near the back of the deck: the braziers, wheels and towers. Most likely the camera sliding into a prop, which shows its inside. Next: ask the owner for a screenshot, then make those props non-colliding for the camera (or move them back) and check from the same views (`tools/preview` renders). |

### 2.3 Other open items

- **Store description:** text ready in `docs/STORE_DESCRIPTION.txt`; our key can't save it (the place PATCH answers 403
  "Scope not authorized"; the universe PATCH answers 200 but stores nothing). The owner pastes it (Creator Hub > Configure
  > Basic Settings; also remove the trailing space in the name "Party Panic ") or adds **universe.place (write)** to the API
  key, after which `publish_place.py` sets it every time.
- **Icon and thumbnails:** made (`assets/store/`), sent to the owner; they upload them by hand.
- **Known phone-HUD nits:** Skate Escape's race-bar racer dots overlap when riders are side by side; Bumper Ballers' "X"
  sits over a knocked-out rider's icon; Sinking Sands' Sand King hint wraps to two lines; mode buttons (`Api.Button`) still
  show for spectators.
- **Backlog, after everything above** (owner: "dont start on game 13+ untill everything else is finished"): the owner's
  13 back-burner games, in the owner's order. Each has a full brief (controls, rules, bots, props) in
  [MINIGAME_BACKLOG.md](MINIGAME_BACKLOG.md), which also has the category table and the build steps
  (`tools/workflows/build-minigame.js`, `merge_check.sh`, `mode_check.sh`, `make_preview.py`, publish). None is started.

  | # | Game | Category | After |
  | --- | --- | --- | --- |
  | 13 | Tanks! | Versus | Wii Play |
  | 14 | Spleef | Survival | Minecraft |
  | 15 | Mecha-Marathon | Reaction | Mario Party 2 |
  | 16 | Prime Cut | Team | Super Mario Party Jamboree |
  | 17 | Stamp Out | Versus | Mario Party 4 / Jamboree |
  | 18 | Messy Memory | Reaction | Mario Party 3 / Superstars |
  | 19 | Parasol Plummet | Luck | Mario Party 3 / Superstars |
  | 20 | Trace Race | Reaction | Mario Party 4 / Top 100 / Superstars |
  | 21 | Eatsa Pizza | Team | Mario Party 3 / Top 100 / Superstars |
  | 22 | Snowball Summit | Knockback | Mario Party 3 / Top 100 / Superstars |
  | 23 | Rockin' Raceway | Race | Mario Party 3 / Top 100 / Superstars |
  | 24 | Slaparazzi | Knockback | Super Mario Party |
  | 25 | Log Jam | Team | Mario Party 3 |

  With these, the 25 games split Team 6, Reaction 6, Versus 4, Knockback 3, Survival 2, Luck 2, Race 2 (suggested to the
  owner: Messy Memory as Luck and Tanks! as Knockback would even it out).
- **Also on the back burner:** custom music for each mini-game (owner: "put in the backlog custom music for each mini
  game"; pipeline in `tools/music`, see `docs/ASSETS.md`; friends can hear our music now, so it's no longer blocked).
- **Not the owner's list:** `docs/MINIGAME_IDEAS.md` holds ten original ideas from the project's first day (Piñata
  Plungers, Captain Copycat, Fuse Frenzy...). The owner never picked them; only bring them up as suggestions.

## 3. What's in `docs/wip/`

Git bundles of the stopped lanes (section 2.2). They're only there so the work isn't lost; delete the folder once each
lane is merged or dropped. `git bundle list-heads docs/wip/<name>.bundle` shows the branch inside.

## 4. Setting up (a fresh cloud container)

- Toolchain: `rokit install` (Rojo, Selene, StyLua, Lune from `rokit.toml`), plus `luau-lsp` and Python 3 with numpy and
  Pillow. Type-checking needs `globalTypes.d.luau` in the repo root (Roblox's definitions; git-ignored: fetch the luau-lsp
  Roblox definitions file).
- Roblox access goes through the environment's proxy: requests to `apis.roblox.com` get the owner's Open Cloud
  credential injected ("Roblox Publish"); no key in the repo. It can publish places, upload assets, grant asset
  permissions, run Luau on test servers (Luau execution) and read data stores. It **cannot** change place settings.
- Renders (portal previews, arena checks, store art) need Blender's Python module: `pip install bpy` under **Python 3.11**
  in a venv, then `export PP_BPY_PYTHON=/path/to/venv/bin/python`. Keep renders few and small.

## 5. Testing without Studio (there is no Roblox client here)

Everything below runs real Roblox servers through Open Cloud Luau execution. **No physics** there: harness bots move
rigs with `PivotTo`, real bots' walking is simulated, so anything physical (flings, collisions, falling) can only be
confirmed by the owner in a real game.

- `tools/checks/mode_check.sh <Id>` (set `OUT=/tmp/mode_check/<name>` to keep runs apart): code checks, a 12-player
  round with the client half, a round with 10 real bots, and the phone HUD drawn at phone sizes (PNGs). Must show 0
  errors. About 5-10 minutes.
- `tools/checks/client_harness.py [--touch]` + `tools/preview/luau_task.py` + `tools/checks/ui_render.py`: the whole
  client, every screen and phase, drawn at real phone sizes; `textReport` lists any text that doesn't fit. It plays the
  game with the longest objective (Honey Trap right now), which is how its rules card was checked.
- Before committing: `stylua src tools/checks tests`, `selene src`, `luau-lsp analyze` (see `merge_check.sh` for the
  exact line), `lune run tests/run` (55 tests).
- Meshes: `python3 tools/checks/mesh_orientation.py` (inside-out or half-flipped parts; must report 0),
  `tools/checks/regen_compare.py`, `tools/checks/merge_check.sh <Id>` after `git merge --no-ff --no-commit <branch>`.
- Assets for other players: `python3 tools/checks/asset_status.py --meshes` and `tools/asset_permissions.py`
  (`publish_place.py` runs the grants every time). An "NOT APPROVED" from asset_status can be HTTP 429: re-check.
- What players' devices load: `python3 tools/checks/client_reports.py` (mesh and sound reports from each device, with
  the place version they're on).
- Gotchas: Open Cloud caps a script at 1 MiB; "INTERNAL_ERROR Task timed out" is transient (re-run once); HTTP 429
  means wait and retry.

## 6. Map of the code (start with [README.md](../README.md) and [ADDING_MINIGAMES.md](ADDING_MINIGAMES.md))

- `src/server/Services/RoundManager.luau` runs the loop (Waiting, Intermission, Voting, Preparing, InRound, Results,
  Cleanup). `RoundContext.luau` is a round's API for modes (players, teams, scores, eliminations, stun, knockback,
  shared state `MG_*`, actions, bots, `Track` for cleanup). After a round, everyone not already in the lobby gets a
  fresh character there.
- One mode = `src/server/MiniGames/<Id>.luau` + `src/client/MiniGames/<Id>.luau` + `src/server/MiniGames/Bots/<Id>.luau`,
  plus an entry in `src/shared/GameDefinitions.luau` (name, category, duration, rules card text: Objective and Controls;
  keep them about as long as the others, the card is small on phones). Kit: `src/server/MiniGames/Kit`,
  `src/client/MiniGames/Kit/Api.luau` (TopHud, HudY, Hint, Button, mode ScreenGui).
- `src/server/Services/BotService.luau`: bots are fake Player-likes with real R15 characters, moved by the server's
  physics on live servers (`RoundContext:RunBots` drives the mode's brain).
- Props: `src/server/World/Props/<File>.luau` (one spec per prop with its own `AssetId`, a primitive `Fallback`, a
  `Palette`; props don't collide unless `Collide = true`), `World/MeshLibrary.luau`, generators in
  `tools/meshgen/props/<Mode>.py` (shared helpers in `tools/meshgen/generate_meshes.py`, which turns every closed part
  outward). Invisible colliders built with `Shapes.*` are what players stand on in several arenas.
- Lobby: `World/LobbyBuilder.luau`, `LobbyObby.luau` (+ `Logic/ParkourCourse.luau`), `BeachBalls.luau`,
  `Environment.luau`. Client controllers in `src/client/Controllers` (`RoundController` has the rules card).
- Shared: `Config.luau`, `GameState.luau`, `Remotes.luau`, `Teams.luau`, `Logic/*` (pure, unit-tested with Lune).

## 7. Publishing

`python3 tools/publish_place.py --universe-id 10772087888 --place-id 78868713931081` builds, publishes, grants asset
permissions and prints the new version (the settings warning at the end is expected). Then push the branch, tell the
owner the version number, and remind them to restart servers.

## 8. History (what each version added)

21 Bobsled return fix, sound reports, store art. 22 Pump & Pop carnival art. 23 Rake It In hitboxes, rounds 5-10 s
longer, console capture in reports. 24 fair hitboxes in all 11 precision games. 25 control track in sound reports.
26 Skate Escape start (skaters held on the line until GO). 27 sit-out switch, countdown beeps only for players in the
round. 28 rules card (10 s, nothing drawn over it). 29 lobby obby (a goo-pool course, scenery you can't climb). 30 Hex Meltdown bots stop flying off and a small call
banner; Honey Trap's tutorial says you play from your flower. 31 Shark Bait (from the owner's other window), mode
buttons only for players who can use them, Skate Escape race bar readable side by side.
Games (13, all hold 12 players): Fire Rope, Hex Meltdown, Honey Trap, Bumper Ballers, Skate Escape, Sinking Sands, Arrow
Ambush, Pump & Pop, Rake It In, Crazy Cutters, Cake Factory, Bobsled Run, Shark Bait.

## 9. The owner's requests today (newest last)

"When I finished bobsled I go out here" (fixed) / icon and thumbnail downloads (sent) / "We also need a new
description" (section 2.3) / "hitboxes for rake game suck" + "fine tune some of the hitboxes" (fixed) / "cool payoffs
for players that keep playing" (2.2) / category counts (answered) / "the obby in the lobby is terrible" (fixed) / "Bots
are terrible at this game" (Sinking Sands, 2.2) / skateboard start float (fixed) / "make sure all games can hold 12
people" (they do) / "a toggle where you skip next round" (done) / "I want low currency not high" (2.2) / "add skiball to
the lobby" (2.2) / "make the games a little longer" (done) / "Music still not working" (works now, 2.1) / "custom music
for each mini game" (backlog) / rules card "looks bad", "more time to read", "happening to all of the games" (fixed in
28) / "Bumper balls control scheme is really bad on mobile" (2.2) / "clipping into some chair on fire rope" (2.2) / Hex
Meltdown "This", "Theres invisible stuff.", "Bot is floating." (2.1) / "UI is on top of the tutorial UI" (fixed in 28,
2.1) / "Make the little tutorial for Honey trap better. Players think they have to go to the tree." (2.1).

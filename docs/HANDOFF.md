# Handoff: Party Panic (for the next Claude)

Last updated: **2026-10-22 ~20:05 UTC** by Session C (branch **`claude/friendly-ramanujan-2dtfr2`**, which started
from `claude/upbeat-galileo-gvwq66` at 3bc532a). Below it, Session B's notes from 19:00 UTC and Session A's sections
0-9, still accurate except where a newer block says otherwise.

## THE GAME IS PUBLIC now (seen 2026-10-22 21:33 UTC): ask the owner before every publish

`tools/publish_place.py` refuses while it's public (pass `--allow-public` only once the owner says yes).

- **Live: version 47** (published 2026-10-23 03:25 UTC from `b8eadaa`, owner: "Can you push the update for minecart
  mayhem"): Minecart Mayhem out of the rotation (`Enabled = false` in GameDefinitions; the code stays). Version 46
  was published by someone else between 45 and 47 (Studio, or another chat that pushed nothing to GitHub); 47
  replaced it. Checked: 46 was 45 plus the empty HttpService and ServiceVisibilityService Studio adds when it saves
  (HttpEnabled false): a Studio save, nothing lost; the owner published nothing.
- **Live: version 48** (published 03:38 UTC from `65eb25e`, owner: "Lets publish that then."): `7f9b436`, the
  fun-and-staying data (owner: "What information should we collect
  to gage if players are having fun and staying?", then "lets do 1-7."): every funnel step's custom fields
  (`Funnels.FIELDS`: device from each screen's "Device" step, Party / Friends / Solo, people in the round),
  `FirstRoundWait` (seconds from joining to the first GO), `LeftDuring`'s streak field, coins to Roblox's economy
  report (`Telemetry.Coins`, kinds in `Funnels.CoinKinds`) and levels to its progression report
  (`Telemetry.Levels`), and RATE IT! beside the results card's thumbs (the card is titled "Results" now).
- **Version 45** (published 22:55 UTC, owner: "Yes do it"): the analytics funnels (owner: "Can you make me some sick ass funnels to track
  where players leave/complete stuff"). `Services/FunnelService` logs, `Shared/Logic/Funnels` names them (step names
  are pinned by `tests/Funnels.spec.luau`: Roblox keys steps by number, so only ever add steps at the end):
  - Onboarding (new players only, whose first visit is after it ships; the profile's `Funnel.Onboarding` keeps
    their last step): Joined, Played a round, Finished a round, Finished 3 / 5 / 10 / 20 rounds.
  - Session (every visit, field New/Returning): the same ladder for one visit.
  - Round (every round, field = game): In the round, GO, Saw the results, Stayed for the next round.
  - Shop: Opened the shop, Picked an item, Bought it. GoldPass: Saw the offer, Pressed GET GOLD PASS, Bought it.
    The screens send the first steps (remote `Funnel`, only `Funnels.ClientSteps`).
  - Custom event `LeftDuring` (value: minutes played, field: what they were doing: "Round: playing",
    "Lobby: vote"...).
  - Owner reads them in Creator Hub > Analytics > Funnels and Custom Events (Roblox shows new events after a
    while, often a day). The `--replay` harness run's summary.funnels lists every step it logged.

- **Live: version 44** (published 21:37 UTC from `ce8754f` + docs, owner: "Yes push to live."). Bots. Owner:
  "Bots are STILL ruberbanding and floating." / "Yes fix it.":
  - Trace Race, Minecart Mayhem, Rockin' Raceway, Bobsled Run, Dice Dash: the server no longer moves bot riders
    during the race (it seats them at the start and for a new character). Every client already stood every rider in
    place each frame; the server's moves, a network trip behind, pulled bots back ~5 studs many times a second
    (the devices' reports: 565 and 638 snaps in a Trace Race round). `tools/checks/scenarios/BotsMove.luau` checks
    the clients carry every bot (all five: every bot moved the whole race, 0 errors).
  - Floating: a bot resting still goes to sleep in Roblox's physics and isn't woken when its floor goes (Shark Bait's
    flipped rafts: four bots hung 4.5 studs up, falling, not moving). `BotService` nudges any bot falling-but-still
    for 0.8 s (PP_Wakes, now in the bot reports), and Shark Bait nudges bots over a raft the moment it flips.
  - Left as is: Stamp Out's server-flown bot hops (8 snaps, 37 jerks a round), Shark Bait's 30-40 stud moves (chomps
    and tosses, by design).
  - After the owner's next session with bots, read `python3 tools/checks/client_reports.py --bots`.

## HOLLOW NIGHT, the first crate season (2026-10-23, NOT published yet)

Owner: "Hollow night comes first I want you to actually work on adding it to the game right now. The season should
always run (so when winter hits the winter event can take place) ... 4 doesn't need to be spooky ... Also do all of
your ideas. This has to be sick. This will be players first season. I want it to look insane." Cozy autumn, not
spooky. Commits `632645b`..`23f90de` on this branch, plus whatever is newer than this note. **Not live**: ask the
owner before publishing (the game is public).

- **What it is** (`Shared/Seasons`, `Shared/Logic/CrateLogic`; the odds and key rules are in CrateLogic's header):
  Hollow Crates (1 per round a person plays to the end) opened with Lantern Keys (Party Cup podium 3/2/1, +1 for
  playing the whole cup, +1 GOLD PASS on the podium, 3 to start, 1 for the first cup a day, 1 per weekly quest, 1
  every 5th Rewards Road level, or Robux). Tiers: THE HARVESTER title 1/500, 5 pets 1/100, 5 hats 1/50, 12
  effects 1/25, coins the rest; no duplicates (a finished tier pays a coin jackpot); the Lantern Meter gives a pet at
  150 crates without one. `Seasons.Current` just stays "HollowNight": the season always runs, and a winter event
  runs beside it (`Seasons.Order` is the collection log's tabs, oldest first).
- **Server**: `Services/CrateService` (grants, `Open` at an altar, the reveal, banners, the welcome),
  `CrateBoardService` (Top Unboxers: OrderedDataStores `PP_Crates_<season>` and weekly
  `PP_CratesWeek_<season>_<week>`, first-in-the-world claims in `PP_CrateFirsts`, MessagingService topic
  `PP_CrateTitle` for THE HARVESTER's every-server announcement), `KeyShopService` (ProcessReceipt saves before it
  grants and never grants twice; gifts to friends; the starter pack once; PolicyService-restricted players see the
  shop locked). Lobby: `World/SeasonWorld` puts the crate pile where the fountain was (24 real crate meshes, from
  `tools/meshgen/season/pile_crates.py`), three altars, the board, autumn trees, lanterns, pumpkins, leaf heaps,
  crows, falling leaves.
- **Client**: `Crates/CrateMenu` (Crates / Collection / Top / Odds / Keys tabs, phone-fitted), `Crates/CrateShow`
  (the opening everyone around sees), `Crates/CrateMoments` (banners, the season's welcome),
  `Controllers/CrateController` (the ribbon chip; walks you to an altar), `SeasonWorldController` (moon, wisps,
  crows, leaf heaps, the board), `PetController`, `AuraController`, `TitleController` (THE HARVESTER's burning
  blackletter name tag).
- **On Roblox already** (uploaded under the owner, 11690979745): every mesh in `World/Props/HollowNight` (AssetIds in
  the file), the art in `Shared/SeasonArt` (leaf flipbook, ember, moon, icon sheet `126681471772772`), and the
  developer products in `Config.Monetization`: Keys1 / 5 / 15 / 40 at 25 / 99 / 249 / 549 Robux (each with a gift
  twin) and the Starter Pack (79: 5 keys + the Harvest Banner trail).
- **Not uploaded**: the season's sounds, `assets/audio/sfx/SeasonSprite.ogg` (one audio upload; the owner has to OK
  it, the month's audio uploads are nearly spent). Until `AudioAssets.SeasonSprite` has its id the crates play the
  game's existing sounds (`AudioController.PlayOr`). Upload: `tools/upload_assets.py --what audio` style, then set
  the id.
- **Meshes**: built in Blender by `tools/meshgen/season/` (`hollow_night.py`, `hollow_night_pets.py`), then
  `export.py --only <Name>` -> `write_props.py` (keeps AssetIds; stylua the file after) -> `generate_meshes.py
  --only <Name>` -> `upload_assets.py --user-id 11690979745 --what meshes --only <Name>` (uploads only when the
  AssetId is 0, so zero it to re-upload) -> `tools/checks/mesh_orientation.py`. Piece names come from material
  names; a group's `piece_prefix` (WingL / WingR / Head / Lantern...) is what PetController animates.
- **Checks**: `tools/checks/crates_check.py` (53 checks on a real server: the lobby, grants, opening, bots get
  nothing, the board, the shop with a stand-in for Roblox's purchases; never touches real DataStores),
  `client_harness.py --touch --skip SkeeBall` (section 3d is the crates; `--skip` keeps the script under Open
  Cloud's 1 MiB) then `ui_render.py` for phone/tablet renders, and `tests/CrateLogic.spec.luau` in Lune.

## Session C, later still: version 43 (nobody floats over the lobby)

- **Live: version 43** (from `20dff14`, still PRIVATE). Owner: "Friend spawned above the lobby floating. We need to
  make sure this doesnt happen again." Cause: Roblox drops a respawn on top of whatever stands on the spawn pad (a
  bot, often), a few studs up; people and bots never collide, so the character should just drop, but
  `Controllers/ArrivalController` (the hold that stops a phone falling through an arena it hasn't loaded) saw no
  ground within 3 studs of the soles and held it in mid-air for up to 15 s. Now, away from an arena (not
  `PP_InRound` + `PP_Alive`), it holds only while nothing at all is under the character for 80 studs, at most 6 s.
  Belt and braces: `LobbyService` puts any lobby player who stands still with nothing under their footprint for 4 s
  back on a spawn pad, and records it (`client_reports.py`: a "Lobby Float" report, key m<UserId>, with where). If
  one ever shows up, there's another cause to find.
- Checks: `tools/checks/scenarios/LobbyFloat.luau` (the old code held the lobby case, the new one doesn't; arena
  holds unchanged; the server watch's floating / standing / heel-on-a-ledge), `--late-floor 3` still holds a phone
  on its spot until its floor arrives, the lobby run, 349 Lune tests.
- Bot rubber-banding is still in the owner's reports from tonight (21:00 UTC, version 41): Trace Race 565 snaps on
  the owner's PC, Dice Dash and Stamp Out dozens (anchored bots moved by CFrame). Not touched yet.

## Session C, later: version 42 (the owner's playtest notes)

- **Live: version 42** (published ~20:55 UTC from `795e965`, still PRIVATE). Four of the owner's notes:
  - Results card (owner: "I don't like how clicking skips the ending screen. I clicked and I couldn't vote."): only
    its X closes it (`Modal.CloseOnBackdrop`), a click on any window stays on it (the window is Active), and the
    results end early only once everyone has answered PLAY AGAIN *and* given a 👍 or 👎 (`ReplayService.Wait` asks
    `RatingService.Rated`); otherwise they run their 6 s.
  - 👍 / 👎 in their usual yellow (owner: "why are the thumbs up and down black?"): a UIGradient on a button tints
    the button's own text, emoji included, so each thumb is a child label. Worth knowing for any emoji on a button.
  - Cake Factory (owner: "I cant even see the cakes because its blocking it."): the per-team 🎂 / ⭐ pills are gone
    (they repeated the team scores); on PC your lanes sit at the bottom beside ADD.
  - Minecart Mayhem (owner: "I cant see when to jump."): the clear window was ~0.34 s at cruise and the gap hides
    behind your own cart. A JUMP up to `Track.HOLD` (1.2 s) early is now held to the best moment (`Track.JumpFor`,
    server, client and the sim alike); the cue reads GAP AHEAD, then JUMP! for that whole time, then ✓ GOT IT.
    `tests/MinecartJump.spec.luau`; bots' falls per round unchanged in `tools/checks/MinecartMayhemSim.luau`.
- Checks: 349 Lune tests, both full client runs (same two pre-existing phone notes), Cake Factory, Minecart Mayhem
  (a press 0.9 s early clears the gap on phone and PC), the PLAY AGAIN run (results 3 s when all answered and rated,
  6 s when one took their vote back).

## Session C: the two saved jobs are done (versions 40 and 41)

Both jobs in [HANDOFF_NEXT.md](HANDOFF_NEXT.md) are live. Start new work from the tip of
`claude/friendly-ramanujan-2dtfr2`.

- **Live: version 41** (published ~20:00 UTC from `53773f9`), on top of version 40 (~19:40 UTC, from `765c332`).
  Both under the owner's standing word; the experience is still PRIVATE.
- **Version 40, the second shop pass** (owner: "Yes lets add more items after everything else is finished"): the
  shop commits of `hold/shop-pass2` cherry-picked in order (2fb8c26, bb0aacc, ba5dbaa, 7df1526, f0cb9da; the two bot
  commits and the idle scenario were already on the line, a83c440 skipped). 25 more coin items and 10 new effects
  beside the Gold Pass's 33 and the Halloween items (no Id clashes, `tests/Catalog.spec.luau` checks; Gold Pass and
  event items never have a Price). Hats show in their tab. Fixes found on the way: a merge slip that left Candy
  Corn's entry open, a tab you switch to now starts at its top (`ShopController`), and on PC a card's description and
  lock button shrink a little to fit. The economy test still says about 23 days for the whole shop (2.85 coins a
  round by Config; Gold Pass and double coins only make it quicker).
- **Version 41, 👍 / 👎 on every mini-game** (owner: "lets add to the backburner a away for players to downvote a
  minigame..." and "can you also do an upvote one so we can see if players like it"): two 44 pt buttons beside the
  results card's title (`ResultsController`; the card is 960 wide now so the title, the thumbs and PLAY AGAIN fit).
  One vote per person per round, switch or take back until the results end, never bots or anyone not in the round.
  Rules: `Shared/Logic/GameRatings` (`tests/GameRatings.spec.luau`). Server: `Services/RatingService`, remote
  `RateGame`, `Config.RateLimits.RateGame`. Totals: data store **PP_GameRatings**, key `<ISO week>/<GameId>`
  (rounds, plays, 👍, 👎, a 4096-bit map for unique voters without UserIds, PLAY AGAIN yes/no, vote offers and wins),
  one UpdateAsync per game a round touched. Test runs write to **PP_GameRatings_Test**.
  - **Read them:** `python3 tools/checks/game_ratings.py` (the last 4 weeks, best-liked first, games under 30 votes
    listed apart, then the 5 most and least liked). `--test` reads the test store, `--weeks N` goes further back.
    In a week or two, run it and show the owner. They switch a game off with `Enabled = false` in
    `src/shared/GameDefinitions.luau`.
  - **Harness:** every harness run now sets workspace `PP_Harness` on its first line (`harness_prelude.luau`). The
    PLAY AGAIN run (`round_harness.py <Mode> --replay`) starts the real RoundManager, and before that fix one run of
    it wrote test totals to the real PP_GameRatings; those three keys were removed and the real store was empty at
    publish. That run's summary has "ratings": the taps, every write and what it added.
- **Checks run:** code checks and 345 Lune tests; both client runs (phone in 3 parts and PC in 2 with
  `tools/checks/client_split.py`: the shop tab snapshots took the phone result past Open Cloud's 4 MiB) with 0
  errors, PC 0 layout problems, phones 2 (the in-round standings reach the MOVE stick's zone in "InRound menu" on
  phone-small with 8 bots; not touched by either job); the shop effects scenario; Fire Rope, Spleef, Bumper Ballers,
  Pump & Pop and Shark Bait; the lobby; the PLAY AGAIN run. Biggest round bundle now ~1.03 MB of the 1 MiB (1.05 MB) cap
  (Pump & Pop with `--party`).

## Session B in flight (2026-10-22 16:00 UTC)

- **Live version 39** (published ~18:54 UTC on 2026-10-22 from `0b9ff72`, the integration tip, under the owner's standing
  word). It adds to version 38:
  - the party glow-up (party names, colours and emblems, squad bar, avatar-card window, PARTY UP!, invite ring, SQUAD
    card, lobby rings, beams and crests, round outlines, streak) and its phone fixes;
  - the GOLD PASS (gold lane on the Level Road, 100 rewards, +10% XP, gold name tag). The game pass 2048378768 went
    **on sale at 399 Robux** right after the publish, with the listing text in GoldPass.Listing and the icon
    assets/store/gold_pass_512.png (icon image 100580787617551). The creator always owns it, so a first real purchase
    needs another account;
  - phones: the vote cards at the bottom middle, 25% bigger (they reach into the MOVE stick's corner by design,
    PP_Popup), Skee-Ball's controls rise above them, the squad bar steps aside;
  - Minecart Mayhem's phone camera, JUMP gates and on-cart cue; Messy Memory's straight-on phone camera, booth walls,
    and no jump button; Trace Race lets riders wander out of their lane (no points there); a new Minecart preview.
  - Checks: all 30 modes 0 errors (Rockin' Raceway's race-bar dots overlapped mid-ease in one phone snapshot, a known
    flake), the lobby, and the client on phone and PC with 0 problems.
  - Tools: round_harness bundles had grown past Open Cloud's 1 MiB cap; e457e74 fixed it (largest now ~1.01 MB:
    Shark Bait's phone run, Pump & Pop with a party). Watch it when more client code lands (the held shop pass).
- **Version 38** (published ~17:10 UTC on 2026-10-22 from a hotfix copy, `8579655` in the detached worktree
  /home/user/pp-hotfix: version 37's `5783546` plus cherry-picks of the fixes below; the same commits are on this branch).
  It adds to version 37:
  - Struggle's invisible bats (owner: "Friend cant see the bat."): a device copied the shared bat model before all of its
    parts had replicated and drew every bat as its tape band alone. RoundContext.ShareTemplate records PP_Parts, and
    Kit/Api.Arrived / Api.Template (and Struggle's and Cake Factory's own lookups) copy a template only once all of its
    parts are there (e65e9df);
  - Tanks! on phones: FIRE is a stick, drag to aim and let go to shoot (58921d3); no jump button in Trace Race or
    Tanks! (ba5b9f6);
  - a calmer lobby: less saturation, a softer bloom, dimmer neon floor, no Halloween saturation boost (4410578);
  - Bumper Ballers bumps 25% stronger (70db3e7); Shark Bait's water slows swimmers to 7 and keeps them there (99b2a70).
  Version 37 was published 15:56 UTC from `7405f0c`; version 36 ~13:35 UTC from `f288f2f`.
- **The owner's standing word on publishing:** "You can push as soon as things are finished for now untill the game is
  live to the public." Publish each finished, checked update without asking, while the experience is private; tell the
  owner to restart servers after each one. Once the game goes public, ask again. 30 mini-games. Version 35 (645aff5) added games 27-29 (Hot Potato, Dice Dash, Minecart
  Mayhem), the PLAY AGAIN vote, the Spleef rework and server-owned bots. Version 36 added Session A's work (round songs,
  Friends, Party Cups, Medals, the weekly leaderboard and Hall of Fame, the Halloween party with the pumpkin hat, 2x
  coins on Halloween weekends) and the sweep's core, clean-up and group C fixes (brighter buttons among them).
- **Version 37 carried** (publish per the standing word above: `python3 tools/publish_place.py --universe-id 10772087888
  --place-id 78868713931081` from the main checkout at the release commit; the settings PATCH's 403 is expected):
  - sweep A (37f3813): Crazy Cutters' magnifier bubble on phones, mode fixes;
  - sweep B (a3fe9a1): Prime Cut's floating YOU badge gone, Spleef bot jumps, Shark Bait's stuck watchdog, mode fixes;
  - in-round screen space (81b2e02): the ☰ menu in rounds, compact standings on phones, the players-left pill in the
    banner, hints that fade, a round-only toast strip;
  - no sitting (e878148): the cause of "invisible stuff I latched onto" was a lobby bench's invisible Seat carried into
    the arena by whoever sat when a round began. `src/shared/NoSitting.luau` and `Services/NoSitService` stop all sitting;
    `tests/NoSeats.spec.luau` keeps seats out of the code; Sand Kings stand at their thrones;
  - the bots pass (9de5e9d; owner: "Bots are STILL ruberbanding and floating."): bots and people never collide
    (collision groups `PP_Bots` and `PP_Players`; a mode's own group still wins), Spleef's bots fall by physics on real
    servers (the scripted drop is only a hover net), and live counters for every bot problem. **Read them after the
    owner's playtest:** `python3 tools/checks/client_reports.py --bots`. Success: snap, hover, head and seat at 0,
    Spleef bots never anchored, Drops 0, Retakes 0. Open Cloud test servers have no physics (`StepPhysics` needs the
    Plugin capability), so only a live game proves it. Other modes still move anchored bots by CFrame (Snowball
    flights, Stamp Out hops, Parasol, the rides, the Hex drop): watch the counters before touching them;
  - Struggle's bats (685d38f): a bat mesh (asset 103167926267453) held in the right hand by a grip joint, a scripted
    swing that follows the hit rule's reach (`tests/Struggle.spec.luau`);
  - parties (7ea6168; owner: "if you party with others for team games you are on the same team"): the 👥 PARTY chip
    and window in the lobby, invite cards, parties of up to 4 that last across rounds (`Logic/PartyLogic`,
    `Services/PartyService`, `Controllers/PartyController`), kept on one team in team games and on one side in the role
    games (`Logic/PartyTeams`, `ctx:PartyGroups()`, `ctx:PartySides(n)`), split as evenly as possible only when a team
    can't hold them. On a phone's full chip row (Halloween) PARTY can push 👋 INVITE off; the PARTY window has its
    own 👋 INVITE FRIENDS TO THE GAME button, so nothing is lost;
  - marks the fonts draw (dc3358f): FredokaOne and Builder Sans draw ★ ✕ ✚ ☾ ◐ ✦ ☆ ☰ as blanks (measured on a real
    server). Red teams wear ■, Stamp Out's red ink is ♥, close buttons read X; `tests/Marks.spec.luau` checks mark sets.
  - R15 poses (35ae9c7): this place's R15 bodies use AnimationConstraint joints, not Motor6D, so the riding modes'
    poses never showed. `src/client/Pose.luau` turns either kind (`tests/Pose.spec.luau`); Bobsled Run, Dice Dash,
    Minecart Mayhem, Parasol Plummet, Rockin' Raceway, Skate Escape and Struggle use it. Only a live game shows the
    Animator/PreSimulation order on devices;
  - Struggle's portal preview re-shot with the held bats (62b2e32, image 94727421623197, approved);
  - the clean-up (9e2824b): `Kit/Glove.luau` and nine MeshLibrary specs no mode used (ShoppingCart, YeetGlove, Anvil,
    MalletHead, Chest, Cone, FireWheel, HoneyTree, Basket; their meshes stay in assets/), Arrow Ambush's `Tags` and
    Prime Cut's `History` shares. The remotes `EventAction` and `MedalEarned` are used now (Halloween, medals).
  - **Checks:** the full regression of all 30 games, the lobby and the client on 9de5e9d (0 errors); on 9e2824b the
    party team modes, Fire Rope, Honey Trap, the lobby and the phone client; on 35ae9c7 the seven pose modes and the
    client on phone and PC.
- **Being built (agents, for the update after this one):**
  - epic parties (owner: "make the party system insane. I want it to look super epic."): a squad bar, an avatar-card
    window, a PARTY UP moment, crests, rings, link beams and in-round outlines, party names, colors and emblems, a streak;
  - the GOLD PASS (owner: "we do need a paid battle pass too. I like the current free one. But the paid one should also
    be insane."; price "399 is fine."): a gold lane on the Level Road, one permanent game pass that replaces the dormant
    VIP pass. The game pass exists: **id 2048378768**, "GOLD PASS", 399 Robux, created **off sale** with Roblox's
    placeholder icon. At publish: upload the agent's icon and set it for sale
    (`PATCH https://apis.roblox.com/game-passes/v1/universes/10772087888/game-passes/2048378768`, multipart form;
    the create call took `name`, `description`, `isForSale`, `price`).
- **Src clean-up left:** Skate Escape's unused Boost broadcast and Rockin' Raceway's and Minecart Mayhem's `CloseAt`
  shares (no client reads them).
- **Held until the owner says the bug-fix wave is done ("after everything else is finished"):** the second shop
  pass, 25 coin items and 10 effects, finished on `claude/games-3` at f0cb9da (a copy is in
  `docs/wip/shop-pass2.bundle`). `claude/games-2` and `claude/games-3` carry it, so take only other work from them.
- **Game sessions:** games-1 to games-4 are idle (standing by: the account is near its weekly usage limit, which resets
  2026-10-28 17:00 UTC). Follow-ups noted from games-4's audit: Rockin' Raceway's riders JSON and parts, Bobsled Run's
  and Parasol Plummet's bot roots set every Heartbeat.
- **Later (owner):** a 👎 per game on the results card and a tool to read the totals, to pick games to switch off
  (`docs/MINIGAME_BACKLOG.md`, "On the backburner"), after the current fixes.
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
- **Songs for games 27-29** (Hot Potato, Dice Dash, Minecart Mayhem): being written. They'll go up as a 6th pack
  (one more audio upload, which needs the owner's OK; 5 left this month). Until then those games play Panic Mode.

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

### 2.2 Stopped half-way (the owner asked for these; all four lanes were finished and merged since)

The lanes were saved as git bundles in `docs/wip/`; each was later merged: payoffs (5286d6a, then 2126271 for saved
coins), skeeball (a17152f), sinkingsands-bots (its brain is the base of d16dcf8; the shorter hint is 9a14aba) and
bumper-controls (finished in 8945c14). Their bundles were removed from `docs/wip/`. The table is what was saved.

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

Only `shop-pass2.bundle`, a copy of the held second shop pass (see the top). The bundles of the stopped lanes (section
2.2), of the four games started in Session B's container and of the per-game music were removed once their work was
merged; they're still in git history (`git show 4117d67:docs/wip/<name>.bundle > <name>.bundle`).
`git bundle list-heads docs/wip/<name>.bundle` shows the branch inside a bundle.

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
confirmed by the owner in a real game. (Checked 2026-10-22: `workspace:StepPhysics` and `RunService:Run` fail with
"lacking capability Plugin", only Heartbeat fires, `GetRealPhysicsFPS()` is 0, and a moving part or a
LinearVelocity never moves. There is no way to step physics in a test; the bot reports below are the live check.)

- `tools/checks/mode_check.sh <Id>` (set `OUT=/tmp/mode_check/<name>` to keep runs apart): code checks, a 12-player
  round with the client half, a round with 10 real bots, and the phone HUD drawn at phone sizes (PNGs). Must show 0
  errors. About 5-10 minutes.
- `tools/checks/client_harness.py [--touch]` + `tools/preview/luau_task.py` + `tools/checks/ui_render.py`: the whole
  client, every screen and phase, drawn at real phone sizes; `textReport` lists any text that doesn't fit. It plays the
  game with the longest objective (Spleef now; it was Honey Trap, which is how its rules card was checked).
- Before committing: `stylua src tools/checks tests`, `selene src`, `luau-lsp analyze` (see `merge_check.sh` for the
  exact line), `lune run tests/run`.
- Meshes: `python3 tools/checks/mesh_orientation.py` (inside-out or half-flipped parts; must report 0),
  `tools/checks/regen_compare.py`, `tools/checks/merge_check.sh <Id>` after `git merge --no-ff --no-commit <branch>`.
- Assets for other players: `python3 tools/checks/asset_status.py --meshes` and `tools/asset_permissions.py`
  (`publish_place.py` runs the grants every time). An "NOT APPROVED" from asset_status can be HTTP 429: re-check.
- What players' devices load: `python3 tools/checks/client_reports.py` (mesh and sound reports from each device, with
  the place version they're on). `--bots`: each device's bot reports from its last 6 rounds
  (Controllers/BotWatchController: snaps, hovers, anyone sitting, anchored time, the server's retakes, drops
  and clamps); the only way to see how bots really move, since the test servers have no physics.
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

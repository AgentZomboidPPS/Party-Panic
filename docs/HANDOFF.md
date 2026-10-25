# Handoff: Party Panic (for the next Claude)

**Version 61 is live** (everything below, published 2026-10-25). **Version 62: the camera fix.** After a Sky Stack round on
61 the owner's camera stayed up in the sky over the arena through the next vote (owner: "This happened again after the new
mini game", then "we need that fix asap and pushed"). Controllers/MiniGameController now puts the camera back on the
player's own character (Custom, field of view 70, their humanoid) when a mode's client half stops, when a new character
arrives between rounds, and every second in the lobby; it never touches it while a round is on, nor while Skee-Ball films
(`State.CameraHeld`). The six modes that save the camera they found (Arrow Ambush, Crazy Cutters, Mecha-Marathon, Prime
Cut, Sky Stack, Trace Race) never hand back a scripted one. The exact trigger wasn't reproduced (each mode's own cleanup
looks right), so this is a backstop for every mode. The client harness checks it (`cameraChecks`: "round" Scriptable 50,
"afterRound" and "lobby" Custom 70). Obby Madness (launch Friday 30 October) is planned in the owner's Claude doc, not built.

**On this branch since version 60 (published as version 61):**
- **Game Mastery, step 1** (owner: "If you could add a progression system what would it be?", then on the plan: "Let's
  build it. 1 yes 2 gold pass should help a little. 3 yes"; the answers: the bot rule, a little GOLD PASS help, start with
  step 1). Every game has its own rank, BRONZE, SILVER, GOLD, DIAMOND, LEGEND (Config.Mastery; rules in
  `Shared/Logic/MasteryLogic`, tested in `tests/MasteryLogic.spec.luau`; paid by `Services/MasteryService`, which
  RewardService asks for every person's round).
  - Points per round played to the end: 1st 5, 2nd 4, 3rd 3, top half 2, else 1; team games 4 / 1. Ranks need 1, 8, 20,
    45 and 90 points; DIAMOND also 3 wins and LEGEND 10, and a win only counts with 3+ real players and never in a private
    server. Ranks never go down.
  - Today's 3 Spotlight games (the same everywhere: a hash of the UTC day; GameState `Spotlight`) pay double and are
    1.5x as likely in the vote. GOLD PASS owners get +1 point for a top-half finish or a team win.
  - Rank rewards: SILVER 10 coins + 1 key, GOLD 25 + 2, DIAMOND 50 + 3 + a crate, LEGEND 100 + 5 and a line to the whole
    server. Titles: All-Rounder (GOLD in 5), Diamond Partier (DIAMOND in 10), Party Pro (GOLD in every game), from the
    stats MasteryGold / MasteryDiamond / MasteryLegend.
  - Old players: on their first load, every game's past rounds (Stats.ModePlays) are credited at 1 point a round, and a
    game medal counts as a win; those ranks pay nothing (`MasteryIntro`), and a toast tells them once.
  - Screens (`UI/Mastery`): a badge on each vote card (PC also "SILVER • 6 pts to GOLD"), a ×2 sticker on Spotlight
    games, a chip on the rules card, a row on the results card with a filling bar, a "GOLD RANK!" celebration card of
    its own, and a MASTERY tab on the Rewards screen (`UI/MasteryWall`: counts, the picked game's detail, the Spotlight,
    every game by type).
  - Steps 2 and 3 (not built): a GOLD cosmetic per game (start with the 10 most played), DIAMOND name-tag frames,
    per-game LEGEND titles and a glow by the name in rounds, 2 Roblox badges (the owner creates them).
  - The client harness bundle is over Open Cloud's 1 MiB cap again with Mastery in: runs skip `Event` too
    (`--skip ...,Event`), and Telemetry is a stand-in there now.
- **Mastery, second pass (DONE, on screen in PC and phone renders; not published).** Owner: "I also want to mastery
  tab to be in the season button I want to rename that button to better reflect everything in it though. Also this has
  to be incredible and make players feel like they accomplished something."
  - The menu's 🎃 **Season** button is now 🎯 **GOALS** (HudController; the onboarding tip says "check 🎯 Goals for
    quests and mastery"). The name was picked by the session that built it; it's easy to change.
  - The GOALS hub (UI/HubTabs) has a 4th tab, 🏆 MASTERY (`Controllers/MasteryController`, 980x600 like the hub;
    `State.OpenScreen("Mastery")` opens it). The Rewards screen keeps its own 🏆 Mastery tab.
  - **Rank-up card** (`showMastery` in CelebrationController): rank-tinted card, turning rim, rays, the badge forged
    (old rank shakes, white flash, new rank bursts out), "GOLD RANK!" in the rank's metal, a tagline, the 5-rank
    ladder, coin/key/crate chips, next goal, 🏆 MASTERY. DIAMOND/LEGEND get a halo and stay 3 s longer. The headline
    ends before the ✕ (drawn smaller when "DIAMOND RANK!" needs it); on phones the next goal sits under the chips.
  - **Over the head for everyone:** MasteryService holds a pop per player and, back in the lobby (Cleanup +2.5 s),
    fires `MasteryPop` (character, rank, gameId); CelebrationController's `masteryPop` shows a pill over the head.
    DIAMOND also gets a server-wide toast (LEGEND already did).
  - **Results card rank-up** (`ResultsController.masteryRow`): starts on the old rank's badge and bar, the bar fills to
    the brim, the row flashes, the new badge pops with "GOLD RANK!", confetti, a shine and the CrateTitle sound, then
    the bar starts over in the next rank's colours. Reduced effects: the new rank straight away.
  - **Results card fits phones** (`rewardsLayout`): the column measures its room (the fitted window less the title bar
    and banner) and picks 31/27/24-unit rows; only if even 24 doesn't fit does it leave out "LEVEL UP!" (the lobby's
    card celebrates it). The personal best and "Next round soon" show wherever there's room.
  - **Trophy-case wall** (`UI/MasteryWall`): tiles are the game's picture (`Mastery.Picture`: frame 1 of its preview
    sheet) under a dark fade, rank-coloured rims, `PartyKit.Shine` on GOLD+ (each tile on its own beat), a turning rim
    on LEGEND; the tile itself is the TextButton (no invisible "Pick" over it). The picked game's panel: picture in its
    rank frame with the badge on its corner, rank, rounds/wins, a **road** of the five ranks (lit + ✓ when reached,
    the next ringed, what each pays under it, a line filled to where the player is) and the next goal with the bar's
    numbers. Header: GOLD/DIAMOND/LEGEND counts and the **next title** pill (ALL-ROUNDER 3/5, filling; then Diamond
    Partier, Party Pro), and the "How" line in whatever room is left (shorter, or none).
  - **First-render fixes:** the rules card's category line ends before the mastery chip (and shrinks if the chip is
    wide); PC vote cards show the objective's **first sentence** in a taller box (the card is 228 tall; the whole
    objective was squeezed to about 11 pt), the rules card shows all of it, and a long one there may shrink to 18
    instead of being cut off (Big Bad Vacuum's was).
  - **Checks:** stylua, selene (0 warnings), luau-lsp clean; 483 Lune tests; client harness on PC and phones (phone, phone-small,
    phone-large, phone-android, tablet): 0 errors. New harness shots: "Goals Mastery", "Mastery gold", "MasteryPop"
    (both pills copied onto a screen), "Results rank up" (0.75 s after "Results", which catches the bar filling).
- **Harness bundle back under 1 MiB:** the whole client was 1,054,803 bytes (over Open Cloud's cap) even before the
  second pass. `client_harness.py` now shrinks modules with `round_harness.slim` (comments, indentation, spaces round
  operators; line numbers kept): about 1,012,800 bytes **with `Event`**, so runs no longer need to skip it (skip
  SkeeBall,Pet,SeasonWorld,PartyWorld,Aura,HallOfFame,AssetReport,Ambience). `ui_render.py` draws the games' preview
  sheets (`assets/previews`), so tiles show their pictures.
- **Sky Stack merged** (game 34 in the list, from the owner's other window, branch `claude/ecstatic-cray-9ijheg` at
  8235797; owner here: "when the other window finishes it's game let's merge it"). Its full note is the "Sky Stack"
  section below. On merge: the store text file says 34 games; `merge_check.sh SkyStack`: its 4 meshes face out, regenerate the same with this
  branch's mesh tools, no z-fights, asset ids visible. It plays the generic round song (no song of its own; audio
  uploads are used up this month). The other window offered to merge it into `claude/quirky-hopper-5yk8zk` and
  publish from there: that branch is far behind version 60, so it must not publish. `mode_check.sh SkyStack` on this
  branch: 12 players, 10 bots and the phone round, 0 errors, phone UI 0 problems, no leftovers.
- **The new-game vote boost is the 4 newest games, worked out by itself** (owner: "I like the idea of new games getting
  a boost. What if we do every 4 games. So if we add 3 and then 2 more the first one of the 3 gets its new vote
  boost."). `GameDefinitions` marks the `NEW_GAMES` (4) newest games in the rotation as `IsNew`, by their place in the
  list (new games go at the end; `Enabled = false` ones don't count); the hand-set `IsNew = true` lines are gone, and
  `tools/new-minigame` no longer writes one. Now: Big Bad Vacuum, Last Dancer, Capy Go Boom, Sky Stack (about 1.2x as
  often as the rest in `lune run tools/checks/vote_sim`). `tests/VoteFairness.spec.luau` checks the rule; with 34 games
  a fresh server offers every game by vote 60 (9 in 10), right at that spec's limit, so the next games may need it
  revisited (fewer new games, or a looser bound).
- **Funnels redone for new players** (owner: "We also need the funnel updated its currently shit. Needs to show first
  game played, what rank they got on that game, how many others were in the lobby, check if they open crate. Also
  check for which game they leave during and any more data that might be beneficial to us."). `Shared/Logic/Funnels`
  and `Services/FunnelService` (CrateService calls `FunnelService.CrateOpened`):
  - **FirstVisit** funnel, once per new player (first visit after this ships; the profile's `Funnel.FirstVisit` keeps
    which steps are out, a bit each): Joined, First round: rules card, First round: GO, First round: results, Second
    round, Finished 3 rounds, Opened a crate, Came back another day. Fields: first game, device, others on the server
    at their first join. Creator Hub > Analytics > Funnels > FirstVisit, split by a field.
  - Custom events (Creator Hub > Analytics > Custom events): **FirstGame** (game, placed: 1st/2nd/3rd/top half/bottom
    half/team won/lost, others on the server; value = place), **LeftDuringGame** (game, rules card/playing/out,
    watching/results, new or returning), **LastGame** (last game before leaving the lobby, placed, rounds this visit;
    value = seconds since its results), **VisitEnd** (new or returning, rounds this visit, crate opened / had one and
    didn't / none; value = minutes).
  - Checked: `round_harness.py HoneyTrap --replay` (two stand-in new players; `summary.funnels` lists every step and
    event in order), 485 tests (`tests/Funnels.spec.luau` pins the step names: never rename a logged step).
- **Eatsa Pizza fixed, and the meshes version 57 swelled repaired** (owner, with screenshots: "Eatsa Pizza is
  bugged.", "the areas to say eat here the circles on the ground arent on the top of the pizza they are below it").
  Cause: `tools/meshgen/unfight.py` (v57) pushed fighting faces 0.1 a round for up to 8 rounds; pushes stacked
  through layered props (the slices' cheese rose 0.3-0.7 over toppings and pepperoni; bunting 5x thicker; Shark Bait's
  floatie 1 -> 2.7 tall; Prime Cut's steaks doubled; 51 of 145 props off by >5%), and `MeshLibrary.normalize` scales
  a prop more than 5% off its spec's Height back to it, so they were drawn shrunk too (pepperoni lay on the pan past
  the slices; rings under the cheese). Now:
  - `unfight.py`: GAP 0.03, EPS 0.02 (a depth buffer tells 0.03 apart at 100 studs); `NO_SEPARATE` (the four pizza
    slices, the floatie, the dough sheet) are left exactly as built (their fights are on cut sides / one colour).
    `mesh_zfight.py` (eps 0.02) lists those apart; `zfight.py`'s eps is 0.025.
  - The 145 meshes were rebuilt from their pre-pass files (`git show 704ffcf^:assets/meshes/<Name>.glb`) with the new
    unfight: 87 came out byte for byte and went back to their old, approved asset ids; 58 changed at most 0.12 studs
    outside and were uploaded again; Prime Cut's fence was regenerated (its bigger end post was built in that same
    commit); the Sky Stack crane rebuilt. `asset_status.py --meshes`: everything approved (496 assets, 1953 mesh files).
  - Eatsa Pizza's bite-spot rings sit at `Logic.SPOT_TOP` (0.42 mesh studs), over the cheese's bumps.
  - A helper had matched Mecha Marathon's pad Height to the swollen mesh (1.535): reverted to 1.335 with the repair.
- **Clipping sweep** (owner: "Make sure everything is super nice. No clipping stuff like that."): every arena and the
  lobby snapshotted on a test server (`round_harness.py <Id> --players 2 --seconds 4 --dump-at 2`; the lobby
  `tools/preview/bundle.py`), checked with `tools/preview/zfight.py` and the new `tools/preview/resting.py` (things
  hovering over what they stand on; mesh props judged whole), every finding judged by hand. The common fault: lawns
  0.3 under the play floor with the decorations round the arena placed at floor height (Rockin' Raceway, Struggle,
  Trace Race, ...). Fixed in 25 arenas and the lobby (commit messages list them). Also: the Hollow Night pile's
  stump reaches the court (`props/HollowNight.py` ground_bark, re-uploaded 96204088535966) and its invisible step is
  at its drawn top; Capy Go Boom's mowing rings are straight bands now (stacked discs flickered). Left as they are,
  with reasons in the helpers' notes: Skate Escape's plateau against the canyon walls' stepped backs (needs the
  canyon wall mesh reshaped), Bobsled Run's track joints (Logic/BobsledCourse), Rockin' Raceway's turn mesh (curbs
  0.07 over the grass), and the undersides of the top rails where two fence panels meet at a corner in Struggle (4)
  and Prime Cut (2), only seen from below the rail. The final pass (every arena and the lobby again, on the repaired
  meshes): 0 flickering pairs elsewhere, and every "floating" left is meant to hang or is held from the side; Eatsa
  Pizza mid-round with bots eating (all four slice stages): 24 of 24 pepperoni on a slice.
- **Pop-ups on phones:** the lobby's chips step aside while the party invite card, the cup's moment or a crate unbox
  banner is up (`LobbyRibbon.CoverWhile`); during the vote the invite card sits between the top bar and the vote
  cards (212 tall on phones). The whole client (`client_harness.py --part 1/3`..`3/3`, normal and `--rich --gold
  --bots 5`, PC and all five phone sizes): 0 errors, 0 overlaps or cut-off text.
- **Still not built (steps 2 and 3):** a GOLD cosmetic per game (start with the 10 most played), DIAMOND name-tag
  frames, per-game LEGEND titles and a glow by the name in rounds, 2 Roblox badges (the owner creates them).

**Live in version 60 (2026-10-25, on the owner's "Push it"):**
- **Server merging** (owner: "Is there a way to merge severs automatically that are getting low?", then "Also push"; I
  proposed a STAY button, 3 real players and an on/off switch). `Services/MergeService` with the rules in
  `Shared/Logic/ServerMerge` (tested) and the card in `Controllers/ServerMoveController`. Every public server lists itself
  in the memory store sorted map `PP_Servers` (real players, place version) every 30 s. A server with 1 to 3 real players
  for 2 lobbies in a row finds the fullest server on its version with room for everyone plus a spare seat, and bigger
  than it, shows a 10 s "Moving you to a busier party!" card with STAY HERE, then teleports everyone who didn't press it
  (`TeleportAsync` with `ServerInstanceId`). Parties are put back together on arrival (`PartyLogic.Reunite`). Who moved
  is in the memory store `PP_Moves`; the teleport data carries only that entry's key, because teleport data passes
  through the player's device and could be made up. Someone who pressed STAY isn't asked again on that server; a server
  people just moved to doesn't move anyone for 5 minutes. A round starting during the countdown calls it off. Off with
  `Config.Merge.Enabled = false`; never in Studio, harness runs or private servers. **Not testable here** (Open Cloud
  servers can't teleport): after the push, watch for `[PartyPanic:Merge]` warnings in the live console.

**Live in version 59 (2026-10-24, on the owner's "Also push"):**
- **Last Dancer's standings showed twice on PC** (owner, with a screenshot: "Why is this duplicated?"): the mode's own
  STANDINGS (for anyone out or watching: groove %, ranked as the cut ranks) sat where the round's board (points) is. The
  mode sets the client attribute `PP_OwnStandings` while its board shows and `RoundController` hides its own meanwhile
  (cleared at every phase change, so it can't stick). The mode's board is now as tall as its rows.
- **Cross-lobby chat: closed** (owner: "close out cross lobby chat. dont need it"). Don't build it.

**Live in version 58 (2026-10-24, on the owner's "push"):**
- The last five meshes' fights (ArrowBarrel's vanes turned 30 degrees off the shaft's faces; Honeycomb, HoneyGlade,
  TanksTank's hubs and MinecartMayhemRailStart by unfight, which now moves a face 0.1 in front of the furthest face it
  fought), uploaded again. `mesh_zfight.py` over every .glb: 0 meshes with fights.
- Phones: the squad bar takes no taps (its left end reached into the MOVE stick's corner; the PARTY chip opens the window);
  the lobby chips step aside while the emote picker is open (`PP_EmotesOpen`; they sat over its X on the smallest); the
  profile card steps aside for a level-up or medal card (`PP_Celebrating`); every close button draws the X (✕ -> UI/Icons).
- Clipping pass (map agent): the lobby's five Hollow Night leaf heaps sat on the shooting booth, quest patio, shop stand,
  podium and half through the emote stage's floor (now on open lawn, `SeasonWorld.leafHeaps`); Mecha Marathon's distance
  boards and start towers stand on the grass (`LAWN`, 0.35 under the track); Big Bad Vacuum's toy-block wall and the giant
  TVs, couches and lamps rest on the floor. A scratch "resting on nothing" check (rays down from every part's lowest
  points) found them; it isn't in the repo yet and wasn't run on the other ~25 arenas.
- Phone UI checks: what's left is pop-ups over the HUD (the party invite card over the chips, the crate unbox banners
  over the PARTY chip, the cup standings over the card), all older than this round. PC: 0.

**Live in version 57 (2026-10-24, on the owner's "Push and keep working."):**
- **Capy Go Boom is back in the rotation** (owner: "Reenable it."): its three live bugs were fixed after version 53 (below).
- **PC lobby chips right under the banner** (owner: "Why is there a gap?"): `LobbyRibbon` PC.Top was 137, room for the
  banner's status line, which only shows during a round, when the chips are away; now 80.
- **PC chat in the bottom left** (owner, with a screenshot of Roblox's chat over the profile card and standings: "is there
  anything we can do about the chatbox?"): `HudController.placeChat` sets `TextChatService.ChatWindowConfiguration` to
  Left / Bottom, HeightScale 0.6 (under the squad bar on the left). Phones keep Roblox's place (the chat starts closed there).
- **Z-fighting inside our own meshes** (owner: "lets fix those right now"): `tools/preview/mesh_zfight.py` checks the .glb
  files themselves (shapes = each piece's connected runs; buried faces and bottoms on the ground don't count);
  `tools/meshgen/unfight.py` moves the smaller shape's fighting face 0.05 out along its normal until nothing fights, and
  `generate_meshes.py` runs it on every prop it builds. The changed meshes were uploaded again
  (`upload_assets.py --again`). Prime Cut's fence: the right-hand post is 0.06 bigger all round and the runs go round the
  yard one way (`PrimeCut.luau`), so at every joint and corner one post holds the other.
- **Part-level leftovers and a clipping pass** (the map agent's second round): the vote stage floor, Rockin' Raceway
  (hurdle rows, lane lines), Big Bad Vacuum (rug bands step 0.1; the woven spokes and brick piles floated 0.4 over their
  bands and now lie on them), Sinking Sands (the mosaic), Arrow Ambush (side walls), Skate Escape (gap lips between the
  curbs as `LIP_ROW`, banner posts, plateau, goal pillar, start wall; `GapLip` reads unchanged). Struggle's board/post
  pairs are the fence mesh's own (fixed by unfight). Not rendered for clipping yet: Pump & Pop, Slaparazzi, Cake Factory
  (the automatic cameras framed them badly), Mecha Marathon, Obby Odyssey, Hot Potato, Prime Cut, Capy Go Boom.
- **A player's first crate ever always holds an item** (owner: "can we make it so everyone is guaranteed an item from their
  first crate?"): `CrateLogic.Roll(..., first)`, from `CrateService` (lifetime opened 0). The owner doesn't want these odds
  shown or published anywhere ("I dont want to display the first crate odds since they will be boosted."): the odds
  screen keeps the usual odds; don't add them to the store description, the game or any public text.
- **The owner's suggestion inbox in game** (owner: "did we ever add in a way for me the dev to read the suggestion box?"):
  the game's creator sees 💌 INBOX in the suggestion box window; the server (`SuggestionService.Inbox`, creator only) lists
  the week's keys by month (listing is the scarcest data store request) and sends the newest 150.

**Live in version 56 (2026-10-24 ~19:30 UTC, on the owner's "Lets push it"):**
- **The game's own UI art instead of an AI look** (owner, with a guide to the tells of an AI-made Roblox game: "Can we fix
  these issues? ... I want you to read it and solve the issues"). The guide's GUI tells and what replaced them:
  emoji as icons ("THE BIG ONE") -> 64 icons modelled and lit in Blender, outlined in ink like stickers
  (`tools/art/ui_art.py`, `assets/images/ui/icons.png`, ids in `Shared/UiArt`); `UI/Icons.Decorate` swaps a label's or
  button's leading emoji for its picture automatically (every `UIKit.Label` / `UIKit.Button`; `KeepEmoji = true` opts
  out; team shapes ★ ♥ are deliberately not mapped, they take their team's colour). Thin see-through white outlines ->
  a thick dark ink (`Theme.Colors.Ink`; `UIKit.new` turns any faint white UIStroke into ink, now and when it's set again).
  Dark navy panels -> a brighter party purple (`Theme.Colors.Panel*`). One font -> Luckiest Guy titles
  (`Theme.Fonts.Title`), Fredoka buttons, Builder Sans words. No images/9-slice -> a button shine (`UIKit.Gloss`), faint
  confetti on every window (`UIKit.Pattern`) and a pink title band with party flags (`Modal`, `Modal.Band`; the Party
  window hides it for its own header). Coins are the coin picture (`UIKit.Coin`). Owner on the first sheet: "can we rework
  the thumbs up and down? they look bad" -> round green/red badges with a cartoon hand.
  `ui_art.py --upload` uploads only what changed (`assets/images/ui/uploaded.json`). `ui_render.py` now draws these
  (ScaleType Stretch/Fit/Crop/Tile, ImageColor3, rounded corners). The client harness is over the 1 MiB cap with all
  controllers: screen runs use `--skip SkeeBall,Pet,SeasonWorld,PartyWorld,Aura,HallOfFame,AssetReport,Ambience` (any
  controller name can be skipped now).
- **Z-fighting sweep** (the guide's map half: flickering overlaps, clipping, too many parts). `tools/preview/zfight.py`
  now checks real shapes (cylinders, wedges, unions, mesh props triangle by triangle from `assets/meshes`), skips faces
  pressed flat against something solid and same-colour pairs, and counts fights inside one mesh apart (`--all` says why
  each pair was dropped). Fixed, every offset 0.1 or more and only on decorations (no spawns, colliders or KillY): lobby
  8 -> 1 (obby arch sign, medal wall emblem, suggestion box, Hall of Fame dais), Mecha Marathon 192 -> 0 (lane lines,
  curbs, pads), Obby Odyssey 26 -> 2 (tier lips, stair strips, checkpoint strips, arches, bridge edges, banks), Hot Potato
  23 -> 0 (alternate fence panels 0.1 deeper), Prime Cut rugs. **Left:** fights inside mesh props (need meshgen fixes and
  re-uploads: the lobby's crate pile and crates ~261, Rockin' Raceway 133, Tanks 105, Mecha Marathon 76, Skate Escape 72,
  Log Jam 46, Pump & Pop 43), Prime Cut's fence (82: its mesh doubles end posts; needs a mesh without one), Skate Escape
  36 (under the road, `GapLip` is read by the mode), Crazy Cutters 14, Struggle 24, a sliver at the vote stage's foot.
  No clipping render pass and no part merges yet (none were trivial: rings, dashes, alternating colours, runtime parts).

**Live in version 55 (2026-10-24, on the owner's "You can push what you have finished.")**: everything below, from version
54 (= 53 with Capy Go Boom out of the rotation) to the suggestion box. Capy Go Boom is still off.
- **HUD layout A** (owner, picking A of three mockups: "I like a but damn have we got to clean up the mobile UI"). PC and
  phones share one profile card (level, name, XP bar with the NEXT reward beside it, then coins, keys and crates in a row;
  `HudController.buildProfileCard`). Phones: the card and the menu (now a 2 x 2 grid) sit in the top corners
  `Theme.Touch.Edge` (32) points from the screen's sides, in part of the side insets (owner: "I know about the safety space
  nonsense but you over compensate for it too much"), in a new full-screen ScreenGui (`PartyPanicEdge`,
  `context.Edge`); the notch / Dynamic Island / camera hole are in the middle of a side, so the top band is clear on every
  phone. The sit-out switch is under the banner in the lobby (beside it, it ran into the menu on an iPhone SE), the lobby's
  chips are one row under the menu grid, the round's standings are a centred strip under the banner (owner: "It has to be
  centered"; the card steps aside during a round; for the round's players the strip fills the status line's room once the
  line fades, never in a team round or a mode with nothing to say there, so mode HUDs keep their place), and everything at
  the bottom is centred (owner: "the bottom not being
  centrally located is ass"): toasts, the "you're out" panel, the spectate bar, the squad bar, and a new pair for anyone
  watching a round: 👀 WATCH and 🎮 PLAY NEXT ROUND (turns sitting out off; the banner's switch steps aside while it shows).
  The event and crate chips are gone (owner: "We dont need a separate open crate button. I thought we said the event button
  goes inside of the season button?"): the event is the Season hub's tab, the crates are on the card. PC standings: the
  score column is capped and long scores shrink, so names stop showing as "1....".
- **First-crate nudge** (owner: "we need a way to push players to open crates if they have never opened any. can we make it
  flashy but elegant?"): `Crates/CrateNudge` on the card's 📦 pill: a breathing halo whenever there's a crate and a key, plus
  a bobbing OPEN! tag, a crate shake and a sparkle burst for someone who has never opened one.
- **No more hovering at the start of a round** (owner: "Also I did spawn hovering. Ive had reports of that."): five modes
  put their spots 3 studs over the floor on top of RoundContext's own lift; and a device that has the whole arena
  (`PP_Parts`) never holds a character in mid-air (`ArrivalController`). `tools/checks/scenarios/SpawnGap.luau` measures
  every mode.
- **Suggestion box** (owner: "Can we add a suggestion box?"): the Settings window's 💡 SUGGESTION BOX button and a blue
  mailbox at the front of the quest patio open a window (`Controllers/SuggestionController`): New game / Improve / Bug /
  Other and 8-300 characters. `Services/SuggestionService` keeps them in their own data store, `PP_Suggestions` (one key
  per UTC hour; never the profile store, never shown to other players), one a minute and 6 a server session per player;
  test runs write `PP_Suggestions_Test`. **Read them with `python3 tools/checks/suggestions.py`** (`--days 30`, `--kind
  Bug`). The client harness bundle is now about 900 bytes under Open Cloud's 1 MiB cap: the next client addition needs a
  `--skip` (or a smaller bundle).
- **Eatsa Pizza bite spots** (owner: "can we make players run around while eating"): eat only on your team's glowing spots
  (one per player, about 6 bites, the next lights up about a second's run away).
- **Big Bad Vacuum can be lost** (owner: "how do you loose this? maybe after 3 hits or something?"): 3 hearts, knocked out at
  0, the Vacuum wins when no person is left standing; bigger lobbies get a tougher boss (about 2 wins in 3).
- **Last Dancer**: steps on W A S D, speakers out of the starting camera, one name per dancer.
- **Capy Go Boom fixed but still off** (`Enabled = false`): whole capybaras, visible shells, BOOM fires forward (below).
- `tools/checks/ui_render.py` now models the real cut-outs (`cut`, `corner` per screen) instead of flagging the whole side
  insets, and lets an invisible tap area sit under one.

**Live in version 53 (2026-10-24 ~15:20 UTC, from `claude/friendly-ramanujan-2dtfr2`)** on the owner's "Lets push it all.":
Big Bad Vacuum and Last Dancer with their own songs (ModePack8, 83135733999883, approved; Last Dancer joins the live vote
now that its song is in), Capy Go Boom (merged from `claude/quirky-hopper-5yk8zk`; its song is ModePack9 here), the new
results card (hero banner, podium with avatars, keys per podium step, crate and key tiles that fly into the counters when
it closes: `Crates/LootFly`), Eatsa Pizza's chomps, combos, pepperoni and HOT PEPPER, Obby Odyssey's bridge bumpers and
ball shadows. The asset gate passed (488 models, sounds and images; 1933 mesh files; all approved and granted). The game
page description in `docs/STORE_DESCRIPTION.txt` (919 characters) was given to the owner to paste: the key still can't
save it (403). Audio uploads this month: by this branch's count ModePack8 was the 10th of 10. **Open:** the owner asked
for three mockups of a tidier HUD for sitting out during a round (A tidy columns, B spectator dock, C you / the round:
`scratchpad` HTML, sent as images) and will pick one; v53's device reports had no servers yet at publish time
(`tools/checks/client_reports.py --version 53`).

Last updated: **2026-10-22 ~20:05 UTC** by Session C (branch **`claude/friendly-ramanujan-2dtfr2`**, which started
from `claude/upbeat-galileo-gvwq66` at 3bc532a). Below it, Session B's notes from 19:00 UTC and Session A's sections
0-9, still accurate except where a newer block says otherwise.

## Sky Stack (2026-10-25, built on `claude/ecstatic-cray-9ijheg`, merged into `claude/friendly-ramanujan-2dtfr2`; not published yet)

Owner: "If you could make any mini game. What would it be?" then "Build it." The pitch they approved: everyone gets a
tower in a row of up to 12; a block slides back and forth over your tower and you tap to drop it; whatever hangs over
the edge is sliced off, so every miss makes the next block smaller; a perfect drop keeps it full size and gusts the
towers either side (their next block slides faster); a block that misses completely crumbles your tower and you're out;
first to the cloud line wins, the tallest tower if time runs out. It is `SkyStack` (Race, 60 s, 1-12, bots fill).

- **Files:** `src/shared/Logic/SkyStack.luau` (every rule and number, shared by server, clients and bots; unit tests in
  `tests/SkyStack.spec.luau`), `src/server/MiniGames/SkyStack.luau` (the plaza, the towers, judging DROP),
  `src/client/MiniGames/SkyStack.luau` (draws every tower and sliding block, shows your own drop at once, camera, HUD,
  DROP), `src/server/MiniGames/Bots/SkyStack.luau` (bot brain), `src/server/World/Props/SkyStack.luau` +
  `tools/meshgen/props/SkyStack.py` (base, star, cloud, crane), `tools/checks/bots/SkyStack.luau` (harness bot), its
  `GameDefinitions` entry (`IsNew = true`: 16 of 32 games are tagged now, the most VoteFairness allows), the store
  description (32 games), a `make_preview.py` camera and `assets/previews/SkyStack.jpg`. Shared files touched: only
  `GameDefinitions.luau`, `tools/preview/make_preview.py` (its camera entry) and the store description.
- **How it works:** a block slides on a schedule from the server's clock (`Stack.Offset`): 9 studs either side of the
  top block's middle, X on odd floors and Z on even ones, faster every floor (9 to 17 studs/s; a gusted block 1.35x).
  DROP sends the time of the frame on screen (input is handled a frame after it's drawn) and the floor it aimed at; the
  server judges it at that moment (`Logic/Buzzer.PressTime`), so a drop that looked lined up lands lined up. Perfect is
  within 0.3 studs or 0.03 s of travel, whichever is wider; every third perfect in a row grows the block 0.5 studs each
  way and gusts both neighbours; less than 0.5 studs left is a miss (eliminated; floors still count). 25 floors reach
  the clouds. Finishers place by when their last DROP was pressed (not when it arrived, so ping can't hand a close
  finish to a bot); everyone else by floors, then by who got there first. The round ends 2.5 s after no person is
  still building, or at the buzzer (presses made before it still count, nothing new starts after it). The client draws
  its own drop at once and takes it back if the server answers "Refused" (a double tap, the buzzer, another floor).
- **Bots** are deliberately beatable (owner: "dont make bots overpowered"): their timing is off by about 0.06-0.08 s and
  they often wait a pass. With two harness players (one perfect, one steady) among 10 bots, over five rounds: the
  perfect player always won (about 28.5 s), the steady one came 2nd or 3rd, 0-4 bots reached the clouds at 32-37 s and
  the rest stopped between floors 10 and 24. Knobs: top of `Bots/SkyStack.luau`.
- **Meshes** (uploaded under user 11690979745 on 2026-10-25, all four Approved): SkyStackBase 80397687535139,
  SkyStackStar 124661970850866, SkyStackCloud 107029468779143, SkyStackCrane 103214181577609. The blocks themselves are
  plain parts the client makes (they are sliced to any size), shaded per floor in the lane's colour.
- **Portal preview:** `make_preview.py SkyStack` (a round snapshotted at 24 s, looking down the row from the front
  right), image 106243641794421 (decal 139891385288243), Open Use and granted; it shows once moderation passes it.
- **Checked on real servers (Open Cloud):** `tools/checks/mode_check.sh SkyStack`: 0 errors in the 12-player, bots and
  phone rounds, phone UI 0 problems, no leftovers; stylua, selene, luau-lsp clean; 259 tests pass. An independent
  review found no blockers; its three should-fix findings were fixed (finish order by press time, judging the frame on
  screen, answering refused presses and starting nothing after the buzzer), as were its small ones (a gust cue only
  when the gust actually reached you, no burst of old slices for a late spectator, one end hold at the buzzer).
- **Left as is:** like every mode, a press may claim up to half a round trip plus 0.1 s back (`Buzzer.REACH`): a
  cheating script could claim the perfect moment just after it passed. The experience is private; tighten REACH for
  this mode if that ever matters.
- **Only a real playtest can confirm:** how DROP feels on phones (tap anywhere except the bottom-left corner counts too),
  the camera (front right of your tower top, rising with it; circling the top once you're at the clouds), and
  whether the finisher's circling camera ever passes through the clouds behind the row.

## Capy Go Boom (2026-10-24, branch `claude/quirky-hopper-5yk8zk`, merged here; in the rotation again since version 57)

Owner: "Can you take Capy to boom. Make it into a mini game for party panic?" CAPY GO BOOM is the owner's other game
(repo `AgentZomboidPPS/Capy-Go-Boom`: capybaras eat snacks to grow, blast each other, a popped capy spills food). It is
now `CapyGoBoom` (Versus, 75 s, 2-12, bots fill): everyone is a 20 KG capybara on a hedged lawn; walk over snacks to eat
(small snacks 2, tasty ones 4, big ones 9, the golden apple 25 KG) and grow; BOOM fires the snack cannon, a hit spills a fifth of the
victim's weight (a quarter for the leader, never below 10 KG) as snacks anyone can eat; nobody is out; the biggest capy
at the buzzer wins. Two SNACK DROPS (a beam 2.5 s ahead, then a golden apple falls) and a last-12-seconds FEAST (lawn
snacks count double; spills never do, pops only move weight around) give comebacks. The brief is in `docs/MINIGAME_BACKLOG.md` 32.

- **Broken on live in version 53, off since 54 (`Enabled = false`), fixed after it, still off until reviewed.** Owner: "Models
  are fucked. shooting is fucked", "cant see bullets. shooting turns you weird". Three client bugs, none visible to the
  harness: (1) the capybara template was copied the first frame its model reached the device, before all its parts had
  (Struggle's bat bug; the Capy branch forked before `Api.Arrived` existed), so every capy was the body without head or legs
  all round: shared models are now copied only once `Api.Arrived` says they're whole. (2) The "Shot" cue's launch time is
  server time (about 1.8 billion seconds) and the client's `sane` check wanted under a million, so no shell was ever drawn:
  it's now checked against the screen's own server clock. (3) Every press aimed at the mouse, so a click on the BOOM button
  (below the capy on screen) fired backwards and spun the capy round: now only a click on the lawn aims, BOOM and E fire
  the way you face. Bots' tags also lost their 🤖 (owner: "Lets remove the bot tag", also newer than the branch). The
  owner's screenshot (every capy at 20 KG, "TIED!") was taken before GO: the profile card shows and the timer is yellow,
  both of which change at GO; eating works in the harness and nothing showed it failing live. Unconfirmed: whether the
  borrowed cannon meshes show the player's colour at all (they may carry colours of their own).

- **Files:** `src/server/MiniGames/CapyGoBoom.luau` (the rules), `src/client/MiniGames/CapyGoBoom.luau` (a capybara drawn on
  everyone's character, snacks, shells, HUD, BOOM button), `src/server/MiniGames/Bots/CapyGoBoom.luau` (bot brain),
  `src/shared/Logic/CapyGoBoom.luau` (numbers and hit tests both sides use), `src/server/World/Props/CapyGoBoom.luau`
  (props), `tools/checks/bots/CapyGoBoom.luau` (harness bot), the `GameDefinitions` entry, the store description (31
  games) and this note. Shared files touched: only `GameDefinitions.luau`.
- **How it works, in short:** weight is the score and drives size, hit circle, eating reach and speed
  (`Logic/CapyGoBoom.ScaleOf`). Snacks and shells are server records the client draws on the server's clock ("Snacks",
  "Spawn", "Eat", "Shot", "Pop", "ShellEnd" cues). A shell is judged against where the shooter saw each rival
  (history rewound by ping/2 + interpolation, like Struggle) and stops at the standing stones and the hedge; a jump over
  it dodges it. A click on the lawn (PC) fires where it points; BOOM and E fire the way you face (bent up to 26 degrees toward a rival, judged where the shooter saw it). The real avatar
  is hidden locally and the capy follows its root; a coloured pad on the lawn under each capy is its shadow and its colour.
- **Art borrowed from CAPY GO BOOM** (owner: "Why don't you borrow assets from the capy go boom repo?"): the capybara is that
  game's `CapyMeshTemplate` (six textured meshes: body, head, four legs; the legs stride and the head dips to chomp), the
  cannon is its starter blaster (seven meshes; housing, light and glow take the player's colour), the snacks are its twelve
  `FoodTemplates` and the sound effects are the ones it plays. They are plain meshes and images, not Models, so
  `Props/CapyGoBoom.luau` builds them with `AssetService:CreateMeshPartAsync` (a mesh that won't load falls back to rounded
  parts). The capybara and cannon assets (19, user 11690979745's) were granted to the game (Universe 10772087888, Use) on
  2026-10-24; their ids are in `assets/capy_borrowed_assets.json`, which `tools/asset_permissions.py` re-grants on every
  publish. The foods are another creator's public assets (24) and the sounds Roblox library audio: nothing to grant, but
  they are not ours, so if one ever goes private its snack falls back to a ball.
- **Checked on a real server (Open Cloud):** 12-player round with the client half, 2 people + 10 bots, phone HUD at five
  sizes: see the mode_check lines in the report. Test bots are far better eaters than people, so their 400+ KG finals are
  not a balance signal (a capy stops growing visually at about 160 KG).
- **Independent review (a fresh reviewer read it cold; no blockers) and what changed:** pooled snack models came back
  shrunk from their eaten-flight (spills and the golden apple were drawn tiny): fixed; a huge or NaN aim from a client could give
  a zero or NaN shell direction: the aim is range-checked, normalised in doubles and the final direction verified; the
  leave/respawn hooks now go on before `SpawnAll`; aim assist uses the same rewound positions as the hit test; the
  shell starts at the capy and is drawn from the cannon's muzzle, with a local muzzle flash on press; spills add up
  exactly (`Rules.Pieces`: even spills only, so pops never create weight); each loop step runs under its own `pcall`
  (a thrown error is reported once instead of silently ending eating); a refused press no longer costs a second
  reload; landed snacks update at 30 Hz, the gulp no longer resizes the whole capy; the hint shows at GO; the FEAST
  banner (redundant with the status line, and 8.8 pt on phones) is gone.
- **Bots are deliberately gentle** (owner: "dont make bots overpowered"). Measured with the test harness (a competent
  stand-in player among bots; the `GROUPS` line in the round log): the first bot brain hit about 80% of its shots and led
  every round, on par with a competent person. The tuned one fires a shot every ~6 s, misses by a wide angle with only
  a partial lead and no aim assist (the server skips assist for bots), dodges rarely and late, dithers and idles,
  doesn't gang up on the leader, and a bot well ahead of the others holds fire and slows down. Result: one competent
  person among seven bots finishes ahead in most rounds at about 1.6x their weight; with several people in the lobby
  they mostly shoot each other and the bots come out about average. The knobs are at the top of `Step` in
  `Bots/CapyGoBoom.luau` (`skill = bot.Skill * 0.65`, the reaction factor, the fire interval and probability, the aim
  error, the dither).
- **Left as they are (design calls / platform-wide):** the hit circle is smaller than a big capy's drawn long axis
  (`Rules.HitRadius` is `BODY_R * scale^0.85` on purpose); presses and eats in the last 0.1 s and shells in flight at the
  buzzer don't count (no HoldEnd); no speed or teleport validation (same as the other modes).
- **Not done / owner's calls:**
  - The shell and the standing stones are still rounded parts (the original game has no such pieces); the capy and the
    snacks are real meshes. Their look in the game itself is unconfirmed: the preview tools can't draw plain meshes.
  - **Portal preview:** made with `tools/preview/make_preview.py CapyGoBoom` (a round on a test server snapshotted at 8 s,
    24 frames of a camera swaying round the lawn, `assets/previews/CapyGoBoom.jpg`, image 138566127435964, approved) and
    recorded in `GamePreviews.luau`. The renderer can't draw plain uploaded meshes, so the capybaras, cannons and snacks
    in it are stand-in shapes (`tools/preview/make_standins.py` writes them to `assets/previews/standins/`; the renderer
    uses them when `assets/meshes/` has no `.glb`). **Never put those in `assets/meshes/`**: `tools/upload_assets.py`
    uploads everything there and would swap the real art in the game for the stand-ins. The preview also needed
    `make_preview.py` to find players that are drawn as figures (`DRAWN_PLAYERS`) rather than avatar rigs. An earlier
    upload of the sheet with a wrong frame count (decal 111480877783246 / image 95247191577986) is unused; it can be
    deleted from the owner's Creator Hub.
  - **Song:** "Boom Boom Capybara" (`tools/music/songs/CapyGoBoom.py`: a 118 bpm tropical calypso; steel pans, marimba,
    congas, brass; the finale starts as the FEAST does) was packed as ModePack7 on its own branch and uploaded on the owner's
    "Finish all of the stuff": asset 114585791757431 (counted there as 7 of the owner's 10 audio uploads this month,
    without this branch's Obby Odyssey pack and season sound sprite: with them it is the 9th). Merged into
    `claude/friendly-ramanujan-2dtfr2` as **ModePack9** (that branch's ModePack7 is Obby Odyssey's song; same upload). Roblox's review has
    approved it (checked on 2026-10-24: Audio, Approved, Active), so it plays; if it ever isn't approved the game keeps
    playing "Panic Mode" for this mode by itself (`python3 tools/checks/asset_status.py` shows the state). The song check passes (intro 16.3 s, 81 s after the drop,
    -11.0 LUFS, -1.6 dBTP).
  - `IsNew = true` (a vote boost while new). In the merge into `claude/friendly-ramanujan-2dtfr2` it is one of 15 of 33
    (Parasol Plummet and Spleef, the oldest "new" games, lost theirs: `tests/VoteFairness.spec.luau` allows at most half).
  - Only a real playtest can confirm: the feel of BOOM and the aim on phones, how the avatar-hiding and the capy look on
    different devices, the camera with a big capy, and the balance (final weights, how often pops happen).

## LAST DANCER (2026-10-24, built on `claude/last-dancer`, merged into `claude/friendly-ramanujan-2dtfr2`; live since version 53)

The owner asked Claude "If you could make any mini game to add to the game. What would it be?", got a pitch for a rhythm
dance-off and said "Let's make it". Built on `claude/last-dancer` (from `claude/quirky-hopper-5yk8zk` at a2f483b), not pushed
until the owner says; no pull request. Full description: [MINIGAME_BACKLOG.md](MINIGAME_BACKLOG.md) 31; how to change it:
[builds/LastDancer.md](builds/LastDancer.md).

- **What it is:** Survival, 64 s, 1-12 players. Each dancer stands on an arcade dance mat (owner: "I want it to show your
  character basically playing on a DDR mat from an arcade") and steps on the arrow under each falling note on the beat of
  "Mirror Ball Showdown" (the four lanes are the mat's LEFT DOWN UP RIGHT; everyone sees everyone step);
  groove (recent accuracy) decides who falls through the floor at the end of each 8 s phrase from the second to the seventh;
  two dancers duel in the last phrase. The song's lead plays the chart, so the notes are the music.
- **Checked:** 273 unit tests (`tests/LastDancer.spec.luau`: judging, groove, cuts, the generated chart), stylua, selene,
  luau-lsp, `mode_check.sh LastDancer` (12 players, 10 real bots, phone HUD at five sizes: 0 errors, 0 UI problems), full rounds
  of 1/2/3/5 players, no z-fighting, the arena rendered with Blender, mesh orientation 0.
- **Waiting on the owner (nothing was uploaded or published):**
  1. **The song:** `python3 tools/upload_assets.py --user-id 11690979745 --what modes` (ModePack8 with Big Bad Vacuum's song, built locally by
     `modes.py pack`; the .ogg is in `build/`, not in git, so in a fresh container run `modes.py render LastDancer` and `modes.py pack`
     first; it uses the 7th of the owner's 10 audio uploads this month). Until its id is in `AudioAssets` the mode
     **keeps itself out of the live vote** (a rhythm game without its song is half a game); Studio and the harness ignore that.
  2. **The meshes** (mirror ball, speaker stack; `--what meshes --only LastDancerMirrorBall,LastDancerSpeaker`): until
     uploaded and approved the arena uses plain parts.
  3. After publishing: the portal preview (`tools/preview/make_preview.py LastDancer`), and "💃 LAST DANCER" in
     `docs/STORE_DESCRIPTION.txt` (31 mini-games).
- **Only a real device can confirm:** how the audio lines up with the notes (SYNC -/+ is the safety net; try Bluetooth
  headphones), the dance poses (R15 `C0` offsets, local to each client), tiles dropping with dancers on them, the club
  mood, tapping with two fingers on a small phone. The bots' strength was set by simulation, not by play: if casual players
  are cut too early, lower `0.62 + 0.3 * skill` in `Bots/LastDancer.luau` (and its header numbers).
- **Review:** an independent reviewer read it; its confirmed findings are fixed (dancers spawned on each other's mats because
  `SpawnAll` ignores the shuffled seating; SYNC and slow packets made notes count as missed; results could contradict the
  announced winner; the cut HUD went stale when people left; resets showed as "Cut at 0s"; the loops now survive a failed
  step; same-lane notes a quarter-second apart took each other's taps). Known and left: the "play every game" medal and
  milestone count Last Dancer while it is still dark (they read the definitions at load, before it switches itself off),
  and a modified client can autoplay (the chart is on the client: inherent to a chart game).
- **Shared files touched** (small, additive): `GameDefinitions.luau` (the entry), `ModeMusic.luau` / `AudioAssets.luau`
  (ModePack8, id 0), `tools/music/packs.json`, `docs/*`.

## BIG BAD VACUUM (2026-10-24, built on `claude/big-bad-vacuum`, merged into `claude/friendly-ramanujan-2dtfr2`; live since version 53)

- The owner asked for "a mini game ... super sick and epic" and then "Make it": a co-op boss fight, the whole lobby against a giant
  robot vacuum. Everything about it is in [MINIGAME_BACKLOG.md](MINIGAME_BACKLOG.md) entry 30 (rules, how it is built, what is
  left). Branched from `claude/quirky-hopper-5yk8zk` at a2f483b; new files only, plus small edits to `GameDefinitions` (its
  entry, `IsNew`), `ResultsController` (a lost co-op fight says "The Vacuum won"), README and the store description.
- Checked here: stylua, selene, luau-lsp (clean), `lune run tests/run` (265 passed), `tools/checks/mode_check.sh BigBadVacuum`
  (12 players with the client, 10 real bots, a phone round: 0 errors, phone UI 0 problems), a solo round with 7 bots, a round
  that makes someone leave from inside the dust bag and then pops it with a brick, forced single attacks (`tools/checks/scenarios/
  BigBadVacuum_*.luau`), and Blender renders of the arena and the boss.
- **Not checked (test servers have no physics):** the suction's pull and the dust bag's anchoring on a device, the camera work
  (flyover during the 3-2-1, shake, finale) on phones, the night lighting, and difficulty against real people (tuned on bots:
  `Shared/Logic/BigBadVacuum` `HealthFor`, `Think`, `WIND_SCALE`, the core windows). No song of its own (it plays the generic round
  song), no portal preview, all props are primitive fallbacks (`AssetId = 0`); meshes, a song and a preview each need the owner's
  say-so for an upload.

## Game 31: OBBY ODYSSEY (2026-10-23, branch `claude/admiring-albattani-dds3xp`, merged into `claude/friendly-ramanujan-2dtfr2`)

The owner sent a photo of a bright blocky obby ("Can you make an Oby obstacle course similar to this photo? I want it
to be a mini game for the game.", then "Also think of a cool name for the oby mini game. you can make it a bit longer
then the average mini game too."). Built as **Obby Odyssey** (`ObbyOdyssey`, Race, 👑, Duration 150, `IsNew`):

- **The course** (`Shared/Logic/ObbyOdyssey`: layout, hazard schedule, hit tests, checkpoints, progress; tests in
  `tests/ObbyOdyssey.spec.luau`, jump table `lune run tools/checks/obby_odyssey_jumps`): six sections over one long
  pool, water then lava: SPLASH HOPS (block rows), BALL BRIDGE (five red balls swinging from a pink gantry), TOWER
  CLIMB (yellow steps up a blue tower), SPIN CYCLE (three spinning-bar discs joined by red pipes), BLINK BLOCKS (one
  block in three gone at a time, flashing first), CROWN PEAK (pyramid tiers to a spinning gold crown between
  checkered flags). Every jump keeps 3.2 studs or more of reach to spare; nothing can be walked up or skipped.
- **Rules:** nobody is out; a fall puts you on your last of 4 checkpoints. First to the summit wins. The round ends at
  5 minutes (Duration 300) or once more than half of its people (never bots, as for PLAY AGAIN) are at the crown
  (owner: "this mini game either ends in 5 minutes or when more then half of the people make it to the top.").
  Ranking: finish order, then checkpoint and distance. Runners pass through each other (`PP_ObbyRunners`).
  Balls and bars are drawn on clients from the shared schedule and judged on the server against each runner as their
  screen showed them (half their ping back; bars swept between checks), with ctx:Knockback.
- **Look:** all parts and CSG rounded blocks (the photo is blocky), no new meshes, so nothing to upload or approve.
  Scenery never collides.
- **Fun pass** (owner: "Make sure this is super sick and actually super fun."):
  - LAUNCH PADS: a set flight with a front flip that always lands (`Course.FlightAt`, tested never to pass
    through anything). The HOP LAUNCHER in the middle of the hops flies you to pad 1. A SHORTCUT of three
    tiny pillars left of the steps ends on the TOWER LAUNCHER, which rockets you onto the tower's top. A
    person's own device flies them and sends `Launch`; the server flies bots (anchored, `_fly`).
  - ROLLING BARRELS roll sideways along the pyramid's three lower tiers out of green pipes and into the
    lava. They're always on the ground, so a timed jump clears them; the pyramid's sides are clear.
  - Every round is shuffled (`Course.Setup(seed)`, seed in `MG_Course.S`): ball timing, bar speed and
    direction, blink order and barrel rhythm. The blink order always leaves a way off a vanishing block
    (tested for 25 seeds).
  - Juice: BONK!/WHACK!/POW! pops, water splashes and lava flares, confetti at checkpoints, section-name
    arches over the pads, a start gate that lifts at GO, bobbing balloons, lava embers, a "final stretch"
    call, and the crown flying off the summit onto the winner's head for the rest of the round.
- **Checks:** see the latest commit message for this branch's test-server results (code checks, `mode_check.sh
  ObbyOdyssey` with 12 players, 10 real bots and the phone HUD, and `colliders.py`).
- **Its own song** (owner: "Make the custom song for it"): "Bounce to the Crown" (`tools/music/songs/ObbyOdyssey.py`,
  150 bpm bubblegum electro-pop, 14.4 s intro, -11 LUFS), alone in ModePack7, uploaded as 89946863953014 and approved.
  That used the owner's 7th of 10 audio uploads this month.
- **Portal preview** (owner: "portal preview video"): runners lining up for the BALL BRIDGE under a swinging ball
  (`make_preview.py ObbyOdyssey --dump-at 4`, its camera in CAMERAS), image 129333029357941, approved.
- **Not done yet:** a real-device playtest (jump feel, the knockbacks, launch flights, barrels and blinking blocks on
  a phone). Not published.

## THE GAME IS PUBLIC now (seen 2026-10-22 21:33 UTC): ask the owner before every publish

`tools/publish_place.py` refuses while it's public (pass `--allow-public` only once the owner says yes).

- **Live: version 49** (published 2026-10-23 21:42 UTC from `8b649e3`, owner: "Lets push this to production"):
  HOLLOW NIGHT, the fall crate season (crates, keys and the key shop, the five pets, hats, effects, THE HARVESTER,
  the season's sounds, the welcome; no coin jackpot), Obby Odyssey, the cleaned-up phone UI, and the asset gate.
  The gate's first try refused (the Open Use calls were rate-limited and didn't retry; fixed); the second passed:
  463 of 463 models, sounds and images granted, 1898 of 1898 mesh files and images Open Use, all approved. 48 was
  this branch's own (below), so nothing of it was lost. Check players' devices with
  `client_reports.py --version 49`.
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

## HOLLOW NIGHT, the first crate season (2026-10-23, live in version 49)

Owner: "Hollow night comes first I want you to actually work on adding it to the game right now. The season should
always run (so when winter hits the winter event can take place) ... 4 doesn't need to be spooky ... Also do all of
your ideas. This has to be sick. This will be players first season. I want it to look insane." Cozy autumn, not
spooky. Commits `632645b`..`8b649e3` on this branch. **Live in version 49** (2026-10-23 21:42 UTC); ask the owner
before every publish (the game is public).

**Live in version 50** (2026-10-23 23:35 UTC, the owner: "Push it"; the owner's notes after playing version 49): 21 s of lobby before the vote and
crates open in the lobby while a round goes on; the crate window brighter with the display font and no dark
buttons; key pack pictures; bots without a tag; keys 3/2/1 for the top 3 of every round (and the cup podium);
the starter pack at 49 Robux; one 🎃 Season button in the menu column for the season's crates, the event and the
quests (owner: "What if we rolled season/event/quests into one button?": `UI/HubTabs`, their windows share a tab
strip in the title bar, same size, no pop between them; it replaced the Quests tile); the stag walks on the ground; Prime Cut's steaks no longer lose
pieces when the next one drops in (owner: "some steaks dont render properly": the client's drop moved the model
by its pivot, and a steak whose pieces came a frame apart kept its seared body sunk under the grate; now each
piece drops from where the server put it, and the round's steaks are shared up front so devices download them
before they're served).

**Live in version 51** (2026-10-24 01:45 UTC; the owner chose "Wait for the review, then push"): the picnic tables stand on their legs (Hot Potato's and Prime Cut's legs
leaned the wrong way: a V on its point; owner: "This is not good claude."; re-uploaded), and bots pass for real
players (owner: "Can we make the bots look more like real players?"): `Shared/Logic/BotLooks` dresses each one
from the catalog (one of 12 dynamic heads or Roblox's default, hair or a hat, a shirt and pants, sometimes glasses
or a backpack, the blocky, Man, Woman or Robloxian 2.0 body, a real skin tone) and names it the way players
name themselves ("itsJosh", "SleepyBean733", "FrostyFox"). `tools/checks/bot_looks.py` builds a bot in each item
on a Roblox server (catalog items can be taken down: run it now and then); classic faces aren't used, since a
bot's default dynamic head doesn't show them. If the catalog doesn't answer, a bot spawns in its skin on the
plain body rather than not at all. Still a tell the owner may want gone: Roblox's own player list (Level, Wins)
only lists real people.
Skate Escape's bridge pieces turned up in the lobby (owner: "The skate peices are in the lobby"): a device starts
a mode's client half as Preparing does, while the arena is still being built and sent, and a model that came
before its parts read its pivot as the world's middle (the lobby). Now `RoundContext.MarkBuilt` (right after
Prepare) puts the arena's part count on it and `Kit/Api.Arena` waits for all of them (through Preparing, then
5 s more, 40 s at most); Skate Escape also stamps each section's pivot; Trace Race picks its crayons up and
Minecart Mayhem its gates only after that wait. A read-only audit of every client half found the rest clean.
The round harness runs client and server in one place, so nothing ever arrives late there: this kind of bug
only shows on real devices. Cake Factory (owner: "I feel like its broken and not lining up properly"): your
own press brings your machine down and shows its layer at once, instead of after the server's answer (on a
phone the cake had moved on by then).

**Live in version 52 (2026-10-24 02:26 UTC): hit boxes** (owner: "Can we also clean up all hit boxes after we push this
latest hotfix."). Three read-only audits checked every mode's contact rules against what's drawn (22 of 31 clean);
fixed: Hot Potato tags (TAG_REACH 4.6 → 3.5, CLIENT_TAG 3, TAG_UP 4.5: no tags across a gap or over a jumper),
Struggle (the swing's height window ABOVE 2.8 / BELOW 2.0 instead of ±5; PICK 3.6 → 2.8), Parasol Plummet (the body
an upright capsule 1.1 round instead of a 2-stud circle), Snowball Summit (ball vs body as a sphere against a
capsule), Sinking Sands (treasure reach = drawn half width + half a body + 0.5; grab height 5.5), Rake It In (each
produce kind's own lane grace, the golden pumpkin's 1.7), Slaparazzi (EDGE 0.5 on the photo rings), Obby Odyssey
(Body 0.8). Left as is: Arrow Ambush / Sinking Sands' forgiving ring rule, Struggle's close circle (it's drawn).
Minecart Mayhem's TNT can be jumped (owner chose "Jumping over TNT works"): `Track.JumpsTNT` (lift ≥ 2.6 from the
front wheels meeting the crates until the back wheels pass them), judged after the ping like a gap; a miss is
`Track.Blast` from the moment it happened; the device predicts its own the same way. The colliders sweep
(every arena + the lobby) found nothing new players can reach (Arrow Ambush's boards read rough at t=0, before
their precise collision is built).

**The owner's plan for seasons and events** (2026-10-23): "Also we can have events/holidays run along side seasons.
Also seasons are actually spring summer fall and winter". So the crate seasons are the year's four: HOLLOW NIGHT is
the **fall** season (`Seasons` `Time = "FALL"`; screens say "FALL SEASON", "THE FALL SEASON HAS BEGUN"), and
**winter** is next, once Hollow Night is fully done with no bugs (owner: "We can work on the winter season after this
one is fully implemented and no bugs."). Events and holidays (`Shared/Events`) run alongside whichever season is on.
**Waiting on the owner's word:** "When we are done. Can we remake the Halloween event to match the current fall/winter
event? (I'll tell you when to redo the Halloween event)". Don't start the Halloween remake until they say so. The bar
is this season's look: the pets rebuilt from their pictures, with glowing leaf meshes and real animations.
The owner also wants **a private test experience** to publish to before production (see the playtest notes in the
latest commits): they create it in Creator Hub, add it to the API key, and send its universe and place ids.

- **What it is** (`Shared/Seasons`, `Shared/Logic/CrateLogic`; the odds and key rules are in CrateLogic's header):
  Hollow Crates (1 per round a person plays to the end) opened with Lantern Keys: every round pays its top 3
  people 3/2/1 (owner, after "won obby odyssey and got no keys got 3rd got no key on crazy cutters": "3/2/1 every
  round"; `CrateService.RoundKeys` from `RewardService`, shown on the results card's crate line, no pop-up), the
  Party Cup podium 3/2/1 too, nothing for just playing a cup ("No keys for playing a cup."); 3 to start, 1 per
  weekly quest, 1 every 5th Rewards Road level, or Robux. Tiers: THE HARVESTER title 1/500, 5 pets 1/100, 5 hats 1/50, 12
  effects 1/25, coins the rest; no duplicates (a finished tier is out of the roll, its share going to the coins;
  owner: "Remove the jackpot for coins. It feels bad to hit a "jackpot" and only get 150 coins.": no coin jackpot,
  and no server-wide news of a coin result); the Lantern Meter gives a pet at 150 crates without one.
  `Seasons.Current` just stays "HollowNight": the season always runs, and a winter event runs beside it
  (`Seasons.Order` is the collection log's tabs, oldest first).
- **Server**: `Services/CrateService` (grants, `Open` at an altar, the reveal, banners, the welcome),
  `CrateBoardService` (Top Unboxers: OrderedDataStores `PP_Crates_<season>` and weekly
  `PP_CratesWeek_<season>_<week>`, first-in-the-world claims in `PP_CrateFirsts`, MessagingService topic
  `PP_CrateTitle` for THE HARVESTER's every-server announcement), `KeyShopService` (ProcessReceipt saves before it
  grants and never grants twice; gifts to friends; the starter pack once; PolicyService-restricted players see the
  shop locked). Lobby: `World/SeasonWorld` puts the crate pile where the fountain was (24 real crate meshes, from
  `tools/meshgen/season/pile_crates.py`), three altars, the board, autumn trees, lanterns, pumpkins, leaf heaps,
  crows, falling leaves.
- **Client**: `Crates/CrateMenu` (Crates / Collection / Top / Odds / Keys tabs, phone-fitted; owner: "Most players
  are mobile... I want it to just make sense and work", then "this screen sucks, too dark, hollow night font is
  bad": the game's own bright purple window with the season's embers as accents, the season's name once on the
  title bar in the display font (no blackletter in the crate screens; THE HARVESTER's own name tag keeps it);
  buttons say what they do: OPEN AT THE PILE, GET KEYS with no keys; the Odds tab is a card per tier with each
  outcome's picture; the key shop is one row of cards, the starter pack first, each with its picture
  (`SeasonArt.KeyPacks`: one key, five on a ring, a heap, the crate brimming; `art.py` renders them, mode
  `shop`, and the products' icons on Roblox are made from the same renders); BEST VALUE is the 40 pack; an
  item's details and the gift picker are pages in the tab's place, never pop-overs; `CrateMenu.ShowItem` /
  `ShowGift` open them for the checks). Keys and crates show as currencies under the coins on PC
  (`HudController`: tap to open the window); phones show them on the lobby's crate chip (under the coins is the
  thumbstick's corner). The menu column's 🎃 Season button opens the season hub (`UI/HubTabs`: the crate window,
  the event's and the quests' with one tab strip in their title bars; the event's tab only while one is on; a
  "!" on the button and the tab when a quest or event reward is ready). Buttons are never dark (owner: "Stop making all of the buttons so dark."; Theme:
  Lavender to Purple neutral, Muted to MutedDark for one that can't be used yet).
  `Crates/CrateShow`
  (the opening everyone around sees), `Crates/CrateMoments` (banners, the season's welcome),
  `Controllers/CrateController` (the ribbon chip; walks you to an altar), `SeasonWorldController` (moon, wisps,
  crows, leaf heaps, the board), `PetController`, `AuraController`, `TitleController` (THE HARVESTER's burning
  blackletter name tag).
- **On Roblox already** (uploaded under the owner, 11690979745): every mesh in `World/Props/HollowNight` (AssetIds in
  the file), the art in `Shared/SeasonArt` (leaf flipbook, ember, moon, icon sheet `126681471772772`), and the
  developer products in `Config.Monetization`: Keys1 / 5 / 15 / 40 at 25 / 99 / 249 / 549 Robux (each with a gift
  twin) and the Starter Pack (49, was 79 until the owner said "Lets make the starter pack be 49 robux instead": 5
  keys + the Harvest Banner trail; prices are read from Roblox, so a price change is made there).
- **The season's sounds**: `assets/audio/sfx/SeasonSprite.ogg`, uploaded with the owner's OK as 71236754603032
  (`tools/upload_assets.py --user-id 11690979745 --what season`; approved at once; the owner's 8th of 10 audio
  uploads this month). A stinger per tier on the opener's reveal (coins jingle, effect shimmer, hat a step higher,
  pet owl hoots, the title's boom and bells), the lid's creak, the reel's ticks, crows and leaf heaps (those two
  quieter: background). A season whose sprite isn't uploaded plays the game's own effects instead
  (`AudioController.PlayOr`).
- **Meshes**: built in Blender by `tools/meshgen/season/` (`hollow_night.py`, `hollow_night_pets.py`), then
  `export.py --only <Name>` -> `write_props.py` (keeps AssetIds; stylua the file after) -> `generate_meshes.py
  --only <Name>` -> `upload_assets.py --user-id 11690979745 --what meshes --only <Name>` (uploads only when the
  AssetId is 0, so zero it to re-upload) -> `tools/checks/mesh_orientation.py`. Piece names come from material
  names; a group's `piece_prefix` (WingL / WingR / Head / Lantern...) is what PetController animates.
- **The five pets were rebuilt from the owner's own pictures** (they sent one each: the owl in flight with
  glowing leaf-feather wings and a lantern on a chain from its beak; a white stag with leafy, ember-cracked
  antlers; a jack-o'-lantern Gourdian of vines; a toadstool Tot with glowing gills and an acorn; a ghost in an
  iron lantern). `hollow_night_pets.py` has the kit: closed double-sided leaf meshes (`feather_mesh`: blade,
  flame, scale, maple; a glowing-rim + core version), `metablob` (smooth blended bodies), `surface` (ray-cast
  placement on them), `lathe`, `carving` (the jack-o'-lantern face on a pumpkin). Moving parts are named
  groups with an invisible `<Group>Hinge` piece where they turn.
- **Pet animations** (owner: "They all have super cool animations right?"): `client/PetPoses` (pure; tested by
  `tests/PetPoses.spec.luau`) moves them, `Controllers/PetController` builds and places them. Idle and at a run
  (the stag gallops, the owl beats faster) plus a flourish each. `SIZES` there: the owl's wingspan 4.2 studs,
  the stag 3.6. The stag walks on the ground beside its owner's right foot (`WALKERS`; owner: "Lets make the deer
  stop floating and walk on the ground near the player."); the others float over the shoulder.
- **Checks**: `tools/checks/pets_check.py` (43 checks on a real server with the uploaded meshes: every hinge
  holds standing, running and mid-flourish; the moves happen; no errors),
  `tools/checks/crates_check.py` (73 checks on a real server: the lobby, grants, opening, bots get
  nothing, the board, the shop with a stand-in for Roblox's purchases, purchases whose saves fail or whose
  buyer or gift friend leaves mid-save; never touches real DataStores),
  `client_harness.py --touch --skip SkeeBall` (section 3d is the crates; `--skip` keeps the script under Open
  Cloud's 1 MiB) then `ui_render.py` for phone/tablet renders, and `tests/CrateLogic.spec.luau` in Lune. A whole
  run's screens no longer fit Open Cloud's 5 minutes at one size: sweep with two runs, `--half 1` and `--half 2`
  (every other snapshot each; the result's `seconds` says how long a run took).

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

- **Store description and name: done.** The owner pasted `docs/STORE_DESCRIPTION.txt` and fixed the name in Creator
  Hub (after v55). Don't remind them.
  Our key still can't write them (the place PATCH answers 403 "Scope not authorized", which `publish_place.py` prints as a
  warning after publishing: harmless). If the key ever gets **universe.place (write)**, `publish_place.py` would set the
  name and `docs/STORE_DESCRIPTION.txt` on every publish (the same text, unless one of them changes it later).
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

## 3. What was in `docs/wip/`

Nothing now: every saved bundle's work is merged. The stopped lanes (section 2.2), the four games started in Session B's
container and the per-game music were removed earlier (`git show 4117d67:docs/wip/<name>.bundle > <name>.bundle`
gets one back); `shop-pass2.bundle` went on 2026-10-25, its shop pass having shipped in version 40
(`git show 2a6af6e:docs/wip/shop-pass2.bundle > shop-pass2.bundle`). `git bundle list-heads <file>` shows the
branch inside a bundle.

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
  (`publish_place.py`'s asset gate runs both every time; see 7. Publishing). Rate limits (HTTP 429) are re-asked.
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
- Bots look like anyone (owner: "Lets remove the bot tag so people dont know they are playing with a bot."): a name
  and a level on the same name tag as people's, no antenna, no 🤖, no softer name in lists, an initial for a
  portrait on the lobby's podium, a cup podium line like anyone's (the server still pays bots nothing).
- `src/server/Services/BotService.luau`: bots are fake Player-likes with real R15 characters, moved by the server's
  physics on live servers (`RoundContext:RunBots` drives the mode's brain), dressed and named by
  `Shared/Logic/BotLooks`.
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

**Everyone must see every mesh** (owner, 2026-10-23: "We also need to make sure when we push the update that everyone
can see all the meshes. We've had that problem twice now."). Before it publishes (and in a `--dry-run`, which needs
no `--allow-public`), `publish_place.py`'s asset gate checks every model, sound and image the game uses, and every
mesh file inside the models, is approved (an HTTP 429 is asked again, never taken as a verdict), grants the game the
use of all of it with every mesh file and image Open Use, and refuses to publish if anything isn't approved, Roblox
doesn't confirm a grant, or the check can't run (`--skip-asset-gate` only with the owner's OK). Images are every
`rbxassetid://` in `src/` the owner uploaded (`asset_status.collect_images`). After publishing, players' devices
report what they couldn't load (`Controllers/AssetReportController`: the world's meshes and images, the season's
art, the portal previews), each server keeps a tally per place version (`Services/ClientReports`, keys
`v<version>_<server>`), and **15-30 minutes after a publish** `python3 tools/checks/client_reports.py --version <new
version>` says how many devices reported and whether any couldn't load something (exit 1 if so).

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

# Mini-game backlog (games 13-29)

The owner asked for these, in this order, after the first twelve and "after everything else is finished" (owner: "dont
start on game 13+ untill everything else is finished"). Each brief below is what the builder works from. They are built
with the workflow in tools/workflows/build-minigame.js (one builder in a worktree, one reviewer, one fixer), four at a time,
then merged with tools/checks/merge_check.sh <Id>, tested with tools/checks/mode_check.sh <Id>, given a portal preview
(tools/preview/make_preview.py <Id>) and published. Every game is for 1-12 players (bots fill), phones first, real meshes.

All 17 are built and merged now, 30 games in all (`src/shared/GameDefinitions.luau`).

Categories (the brief leaves some open; these are the picks):

| Category | Before the backlog | Games 13-26 |
| --- | --- | --- |
| Team | Pump & Pop, Bobsled Run, Cake Factory | + Prime Cut, Eatsa Pizza, Log Jam (6) |
| Reaction | Hex Meltdown, Rake It In, Crazy Cutters | + Mecha-Marathon, Messy Memory, Trace Race (6) |
| Versus | Sinking Sands, Arrow Ambush, Shark Bait | + Tanks!, Stamp Out, Struggle (6) |
| Knockback | Bumper Ballers | + Snowball Summit, Slaparazzi (3) |
| Survival | Fire Rope | + Spleef (2) |
| Luck | Honey Trap | + Parasol Plummet (2) |
| Race | Skate Escape | + Rockin' Raceway (2) |

(Suggested to the owner: Messy Memory as Luck and Tanks! as Knockback would even the thin categories.)

Games 27-29 were added on 2026-10-22 (owner: "Let's add the stars"): one more Survival, Luck and Race game, so each of
those categories has 3, like Knockback, and no game needs to move.
With them: Team 6, Reaction 6, Versus 6, Knockback 3, Survival 3, Luck 3, Race 3.

Also asked for: **custom music for each mini-game** (owner: "put in the backlog custom music for each mini game", then
"take over the music."). Built since: 27 games have their own round song (`tools/music/songs/`, see `docs/ASSETS.md`);
the five song packs are uploaded and live since version 36 (`AudioAssets.ModeMusic`, `src/shared/ModeMusic.luau`).
Dice Dash's and Minecart Mayhem's songs are written (`tools/music/songs/`) but not in an uploaded pack yet, and Hot Potato
has none, so those three play "Panic Mode" (`python3 tools/music/modes.py list`).

**Done in version 41** (`Services/RatingService`; read the totals with `python3 tools/checks/game_ratings.py`).
The request, as it was put **on the backburner, after the current fixes** (owner, 2026-10-22: "Once all of these are resolved. lets add to the
backburner a away for players to downvote a minigame and then we can harvest that data to disable minigames in the
future."; and later that day: "Also while you make the downvote for mini games can you also do an upvote one so we can
see if players like it"): a 👍 ("Loved it") and a 👎 ("Not for me") side by side on the results card, both required,
one vote per person per round they played, changeable until the results end, never from bots. The server keeps running
totals per game (plays, 👍, 👎, unique players, by week) in a DataStore of its own, alongside the signals it already
has (PLAY AGAIN yes/no, how often each game wins the vote). A tool (e.g. `tools/checks/game_ratings.py`, reading the
totals through Open Cloud) prints each game's 👍 rate, 👎 rate and net score, best-liked first, so the owner can see
what players like and pick games to switch off with `Enabled = false` in `src/shared/GameDefinitions.luau`. The full
plan is Job 2 in [HANDOFF_NEXT.md](HANDOFF_NEXT.md).

## 13. Tanks! (`Tanks`, Versus)

After "Tanks!" (Wii Play): toy tanks battle in a walled play-room arena. Each player drives a tank (move: stick / WASD; aim: the turret points where you drag on the right of the screen or at the mouse, with an aim-assist toward the nearest enemy in front on phones; FIRE button). Shells ricochet once off walls (true reflection, server raycasts against the wall boxes), each tank has at most 2 shells in flight; a LAY MINE button drops a mine that blows after a few seconds or when a tank drives over it (blast radius, chain reactions). One hit and your tank is out (a big toy-explosion, your character pops out and spectates); last tank standing wins, or most hits if time runs out (Duration 60-90). Up to 12 tanks free-for-all in a big arena with wooden-block walls, cork-tile floor and a few low cover blocks; the server owns tank positions/headings from players' inputs (like Bobsled Run: server-authoritative, clients interpolate smoothly) so bots and players are equal; shells/mines are server-simulated and drawn smoothly on clients. Bots drive, take cover, lead their shots and use bank shots and mines with skill-based accuracy, and dodge incoming shells. Category Knockback or Versus, MinPlayers 2, IsTeam false. Props as real meshes: chunky toy tanks in team colours, shells, mines, wooden blocks, toy-room backdrop (giant toys, a rug, a window).

## 14. Spleef (`Spleef`, Survival)

After Minecraft's Spleef: everyone stands on layered floors of snow blocks (3 layers with gaps between, a pit of water or lava below); tapping/clicking a block within reach breaks it (server checks reach, line, rate), so rivals fall through; a player who falls through every layer is out; last one standing wins. Late in the round the blocks start to crumble on their own (glowing warning, then they drop) so it always ends. Handle fall detection on the SERVER from player positions over broken blocks (the test server has no physics: hazard parity for bots and harness rigs), with a short grace so standing on a block edge is fair. Up to 12 players: floor size scales with player count; keep the part count sane (one part per block, reuse, or merged meshes per row with server-tracked cells). Bots roam, dig under rivals' feet and around them, and avoid holes, with skill-based reach and timing. Category Survival, Duration 60-90, MinPlayers 2, IsTeam false. Props as real meshes: shovels, snow blocks with texture-like detail, an icy arena with a frozen backdrop; a satisfying break puff and a crunch.

## 15. Mecha-Marathon (`MechaMarathon`, Reaction)

After "Mecha-Marathon" (Mario Party 2): each player winds up a wind-up flying toy by mashing WIND (alternating two buttons/keys, or rapid taps on phones) during a 10-second wind phase; then all toys launch down their lanes and fly; the more it was wound, the farther it flies (with a little skill-based randomness in the flight wobble but never enough to flip a clear lead); distance markers every 10 m; farthest flight wins. Up to 12 lanes side by side (or fanned) on a long sunny field; the camera follows the leaders during the flight, which is the show. The server counts presses with a hard rate cap (no auto-clicker advantage beyond a human max) and owns the flight results; clients animate the toys smoothly. Bots mash at skill-based rates. Category Reaction, Duration 25-35, MinPlayers 1, IsTeam false. Props as real meshes: wind-up toy flyers with keys and propellers in player colours, launch pads, lane markers, a festive field.

## 16. Prime Cut (`PrimeCut`, Team)

After "Prime Cut" (Super Mario Party Jamboree, 2-vs-2): teams cut an irregularly shaped grilled steak as evenly as possible. Each team shares a knife that its members steer left/right during a 10-second window; when time runs out the knife comes down and the cut is judged by how close the two pieces' areas are to 50:50 (server computes the polygon split exactly). 3 rounds with different steak shapes; the team closest to an even split wins each round; most round wins (then best total) wins. Adapt for up to 12: 2 to 4 teams (Teams.luau), each at its own grill station; teammates' nudges add up (so coordination matters) and the knife position is server-owned; show the live split % only after the cut (that's the suspense), with a big reveal of each team's two pieces and percentages. Bots nudge with skill-based error. Category Team, Duration 45-60, MinPlayers 2, IsTeam true. Props as real meshes: grills, steaks with grill marks (several shapes), a big knife, a BBQ backyard arena.

## 17. Stamp Out (`StampOut`, Versus)

After "Stamp Out!" (Mario Party 4 / Jamboree): each player rides a bouncing rubber stamp around a giant paper pad, leaving a stamp of their colour wherever it lands; stamps cover rivals' colour; tap to hop forward, hold to charge a longer jump; after 30-45 s the player with the biggest share of the pad wins. Up to 12 players on a big pad: the server tracks coverage on a grid (cells), stamps a disc on each landing from server-validated positions (rate, reach), and shares the grid compactly; clients draw it with decals/parts or a texture-like grid of tiles efficiently and show a live % leaderboard. Each player's colour must be distinct for 12 (Teams/player colours) plus a pattern or symbol in the HUD so colour isn't the only cue. Bots hop toward big unclaimed or rival areas with skill. Category Versus, Duration 30-45, MinPlayers 1, IsTeam false. Props as real meshes: rubber stamps with handles, an ink pad, a desk with giant pencils and paper clips around the pad.

## 18. Messy Memory (`MessyMemory`, Reaction)

After "Messy Memory" (Mario Party 3 / Superstars): players study a shelf of toys for a few seconds, then mischief-makers burst in a puff of smoke and knock items off; each player then has 30 s to put every item back on its original spot on their own shelf (tap an item, tap a slot; on PC click). A curtain button hides your shelf from peeking rivals (and can be reopened to change answers). When time is up the correct spots are revealed one by one: most correct placements wins. Up to 12: twelve booths in a ring (each with its own shelf and the same layout, so peeking is a tactic), server-owned item positions and validation. Bots recall with skill-based errors and sometimes peek. Category Reaction or Luck (pick the best fit), Duration 45-60, MinPlayers 1, IsTeam false. Props as real meshes: shelves, ~8 distinct cute toys, curtains, smoke puffs, a toy-shop arena.

## 19. Parasol Plummet (`ParasolPlummet`, Luck)

After "Parasol Plummet" (Mario Party 3 / Superstars): players fall through a sky shaft holding umbrellas: OPEN the umbrella to float/rise slowly, CLOSE to drop fast, steer left/right; hammer-throwers on the sides toss coins and coin bags (worth more) and sometimes hammers that stun you and snap your umbrella shut; the most coins after 30-40 s wins. Up to 12 players in a wide shared sky (or lanes), with the server simulating each faller's height and position from inputs (server-authoritative like Bobsled; the test server has no physics) and spawning items; clients draw it smoothly with a side camera. Bots steer to coins and dodge hammers with skill. Category Luck or Reaction, Duration 30-40, MinPlayers 1, IsTeam false. Props as real meshes: colourful umbrellas, coins, coin bags, hammers, throwers' cloud platforms, a sunny sky backdrop.

## 20. Trace Race (`TraceRace`, Reaction)

After "Trace Race" (Mario Party 4): each player rides a giant crayon down their own long winding guideline painted on a huge clipboard (turns, curves, loops); the crayon moves forward at a steady pace and players only steer it (stick / A-D / drag), drawing their own line as they go; accuracy is how close their line stays to the guide over the whole course; most accurate wins. Make it clearly different from Crazy Cutters (which traces small cookie outlines): this is a fast steering run seen from behind the crayon, with the line scrolling at you. Up to 12 parallel paths; the server receives sampled steering/positions, validates them (speed, bounds, timing like Crazy Cutters does) and scores; clients draw everyone's trails. Bots steer with skill-based wobble. Category Reaction, Duration 30-45, MinPlayers 1, IsTeam false. Props as real meshes: giant crayons in player colours, a clipboard, paper, desk clutter.

## 21. Eatsa Pizza (`EatsaPizza`, Team)

After "Eatsa Pizza" (Mario Party 3, 2-vs-2): teams race to eat their part of a pizza the size of a swimming pool by mashing EAT (each player chews the slice they stand on; pepperoni pieces take more bites; walk to the next slice when one is gone). First team to clear its part, or the biggest share eaten at time up, wins. Up to 12: 2 to 4 teams (Teams.luau) around one giant pizza cut into team sections; the server counts bites with a human-max rate cap and owns what's left; clients show bite marks shrinking slices, crumbs and a big % per team. Bots mash at skill-based rates and move between slices. Category Team, Duration 30, MinPlayers 2, IsTeam true. Props as real meshes: the giant pizza (slices with toppings), pizza boxes, a pizzeria rooftop or kitchen arena.

## 22. Snowball Summit (`SnowballSummit`, Knockback)

After "Snowball Summit" (Mario Party 3): on a frozen mountain-top platform players roll snowballs (hold BUILD while moving to grow one in front of you), then release to launch it; bigger snowballs knock rivals farther; two snowballs that meet cancel out; players knocked off the summit fall and are out; everyone still on top when time runs out (60 s) wins (rank by survival time). Server-simulated snowballs (positions, growth, collisions) and knockback via ctx:Knockback / the server for bots (hazard parity); edge falls detected by the server. Up to 12 on a platform that scales with player count. Bots build, aim at the nearest rival near the edge, and dodge, with skill. Category Knockback, Duration 60, MinPlayers 2, IsTeam false. Props as real meshes: a snowy summit with icy edges, snowballs, pines, flags, a mountain backdrop.

## 23. Rockin' Raceway (`RockinRaceway`, Race)

After "Rockin' Raceway" (Mario Party 3 / Superstars): a hobby-horse race. Each rider has a carrot stamina meter: holding GALLOP speeds you up but drains carrots; push past the redline and your horse spins out; let off to recover; orange carrot panels give a dash, blue ones slow you. First across the finish wins (rank the rest by distance). Up to 12 riders in lanes on a fairground track (an oval or a winding course); the server owns speed/stamina/position from inputs (server-authoritative), clients animate the hobby horses bobbing. Bots manage stamina with skill (better bots ride near the redline). Category Race, Duration 40-60, MinPlayers 1, IsTeam false. Props as real meshes: hobby horses in player colours, carrot panels, a fairground track with bunting and a finish arch.

## 24. Slaparazzi (`Slaparazzi`, Knockback)

After "Slaparazzi" (Super Mario Party): a photographer snaps a photo every few seconds (with a visible countdown and a flash); players score 3/2/1 points by how close they are to the centre of the shot, and can SLAP rivals (cooldown) to knock them out of frame; 7 photos, most points wins. Up to 12 on a stage with a marked photo frame that moves between shots; slaps are server-validated (range, cooldown, facing) and use ctx:Knockback (bots too); each photo is shown to everyone as a snapshot card with who scored. Bots jostle for the centre and slap with skill. Category Versus or Knockback, Duration 45-60, MinPlayers 2, IsTeam false. Props as real meshes: a camera on a tripod with a photographer, a stage with spotlights and a red carpet, a crowd backdrop.

## 25. Log Jam (`LogJam`, Team)

After "Log Jam" (Mario Party 3, 2-vs-2): each team works a sawmill: one teammate PLACES a log by pressing the button shown on their screen, the partner CHOPS it by pressing that same button; a wrong press jams that side for a moment; the team that chops the most logs in 30 s wins. Up to 12: 2 to 4 teams (Teams.luau) with roles rotating each log so everyone both places and chops; the prompt is one of four big shape+colour buttons (▲ ■ ● ◆) shown to the placer (and to the chopper a beat later); the server owns prompts, presses and counts. Bots press with skill-based reaction and error. Category Team, Duration 30-40, MinPlayers 2, IsTeam true. Props as real meshes: sawmill stations, logs, axes, wood chips, a forest lumber-yard arena.

## 26. Struggle (`Struggle`, Versus)

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

## 27. Hot Potato (`HotPotato`, Survival)

Added by the owner on 2026-10-22, who asked for one more Survival, Luck and Race game each and picked this pitch ("Let's
add the stars"): "a few ticking bombs get handed out, and you tag someone to pass yours on. When a bomb goes off,
whoever is holding it gets launched into the sky and is out. New bombs drop until one player is left." After the
playground game and "Hot Bob-omb" (Mario Party), with an original look: the bombs are hot potatoes (lumpy baked spuds
with a metal cap and a fizzing fuse). Everyone runs around a fenced backyard-cookout arena whose size scales with the
player count. The server hands out one potato per 4 players still in (at least 1) to random players; each has a hidden
fuse (a random 8-14 s, shorter as fewer players remain) and warns in its last 3 s (it glows, sizzles and beeps faster).
The holder passes it by touching an empty-handed player (a server distance check against what the holder saw, with lag
leeway like FireRope) or with a THROW button that lobs it to the nearest empty-handed player in front within about 12
studs (aim-assist, a visible 0.4 s arc; if the fuse runs out mid-air the thrower is out). No tag-backs: a potato can't
go straight back to whoever passed it for 2 s. Holders run about 10% faster so tags are possible. When a fuse runs out:
a big cartoon blast, the holder is launched high into the sky (the same launch for players and bots, applied by the
server) and is out; after a 2 s breather new potatoes drop on random survivors. The last one standing wins; at time-out
everyone holding a potato blows up and the rest survive; the others rank by how long they lasted. Everyone must always
see who holds a potato: a big bobbing potato icon above each holder's head (a shape, not just a colour), a pulsing "YOU
HAVE THE POTATO! PASS IT!" banner and a red screen edge for the holder, and a survivors count. Bots: holders chase the
nearest catchable player and throw with skill-based timing and aim; empty-handed bots keep away from holders with
skill-based awareness (they don't flee in one clump, and the clumsiest sometimes freeze); nobody stands still. Category
Survival, Duration 60-90, MinPlayers 2, IsTeam false. Props as real meshes: the potato bomb, a round lawn ringed by a
solid picket fence (nothing solid that isn't drawn), picnic tables and hay bales to dodge around, a giant grill or
campfire centrepiece, string lights and big blast puffs.

## 28. Dice Dash (`DiceDash`, Luck)

Added by the owner on 2026-10-22 with Hot Potato, from this pitch: "a 60-second board game. Everyone rolls giant dice at
the same time and hops along a winding path. Some tiles boost you forward, one swaps you with the leader, and trapdoors
send you back to the start. First to the finish wins, and the only button is ROLL." In the spirit of a Mario Party
board, with an original look. Everyone starts on START of one shared winding board of about 40 big tiles laid across a
giant tabletop in a sunny meadow (players sharing a tile stand in a small ring so nobody hides anyone). Every few
seconds a turn starts for everyone at once: a giant die spins above each player's head and ROLL (a button, a tap or
click, or jumping into the die) stops it; anyone who hasn't rolled after 3 s rolls automatically. The server decides
every roll (a fair d6, never the client); then everyone hops forward tile by tile together (server-owned positions,
smooth hops on clients; characters can't walk off the board during the round) and the tile they land on fires: BOOST
(+3, a springboard), SLIP (-2, a banana peel), CANNON (shoots you to the next cannon ahead), SWAP (a rare golden tile:
you trade places with the leader, with a big callout), ? (a random event: everyone behind you moves +2, a gust blows the
leader back 3, or last place jumps ahead 5) and TRAPDOOR (back to START; one or two of them, none in the last quarter).
Tiles you only pass over do nothing. First to reach FINISH wins (no exact landing needed); the rest rank by finish
order, then by how far along they are. The round ends when 3 players have finished or time runs out; tune the board so
the first finisher usually arrives at about 45-55 s. Big readable callouts for every event ("SWAP! Bo <-> Ann",
"TRAPDOOR!"), a race strip at the top of the screen with every player's badge on a line from START to FINISH, and a
camera that follows you along the board. Bots press ROLL with human-like delays (skill changes nothing: it's luck).
Category Luck, Duration about 60, MinPlayers 1, IsTeam false. Props as real meshes: giant dice with rounded edges and
pips, chunky board tiles with a raised icon per type (arrow, peel, cannon, swirl, question mark, hole), START and FINISH
arches with flags, the springboard and cannon, and oversized board-game scenery around the board (cards, a spinner, a
rule book, game pieces).

## 29. Minecart Mayhem (`MinecartMayhem`, Race)

Added by the owner on 2026-10-22 with Hot Potato, from this pitch: "race mine carts through a cave. At every split you
pick left or right; some routes are shortcuts, some are dead ends, and a TNT track blows you off. You also jump gaps and
lean into curves, and the first cart out of the mine wins. It works well on phones with just left, right and jump."
After classic mine-cart levels, with an original look. Each player rides their own cart through a crystal cave; carts
roll by themselves (faster downhill, slower uphill), and the server owns every cart's position along the track splines
(like Bobsled Run and Rockin' Raceway: server-authoritative, clients interpolate smoothly), so bots and players are
equal. Controls: LEFT / RIGHT (the move stick or two big buttons on phones, A/D or the arrow keys on PC) and JUMP. At
5-6 junctions a sign shows both ways; holding LEFT or RIGHT as you reach it picks a branch (with no choice the cart
takes the long safe way). One branch is a shortcut and one is the long safe way, and some splits hide a dead end (the
cart bumps a buffer and rolls back to take the other way) or a TNT track (the crates blow your cart off the rails: a 2-3
s comeback at the junction). Which branch is which is shuffled every round, with readable hints (cracked rails, a skull
sign, light at the far end). Broken bridges and gaps need a timed JUMP (a takeoff marker; missing drops you to a 2-3 s
comeback at the last checkpoint). On curves, leaning into the bend gives a speed boost and leaning the wrong way wobbles
and slows you. Carts don't collide (overlapping carts shift sideways so nobody gets blocked); glowing crystals on the
rails give a short dash. The first cart out of the mine into daylight wins; the rest rank by finish order, then by
distance. Up to 12 riders; a good rider finishes in about 45-60 s. HUD: a progress strip with every rider's badge, the
next junction's two arrows, and big JUMP and LEAN prompts with a countdown ring. Bots pick branches with skill (good
bots read the hints, clumsy ones sometimes take the TNT) and time jumps and leans with skill-based accuracy. Category
Race, Duration 75-90 (a time-out), MinPlayers 1, IsTeam false. Props as real meshes: riveted mine carts with each
player's colour trim and badge, curved rail segments (merged into few meshes for phones), wooden trestles and supports,
TNT crates, junction signs, glowing crystals, lanterns, a cave entrance and a sunlit exit with a FINISH banner.

## 30. Big Bad Vacuum (`BigBadVacuum`, Survival tag, co-op)

Added by the owner on 2026-10-24 (asked which mini-game to make: "make it but make it feel super sick and epic"), built by hand in
one session on `claude/big-bad-vacuum`. The first game with the whole lobby on one side: everyone against a giant robot vacuum
(a boss fight) in a living room at night, a round rug inside a ring of giant toy blocks, with a floor lamp, a TV and a couch beyond
the wall. 1-12 players, bots fill, Duration 100 (a fight clock of 82 s after a 5.5 s intro, then a 5 s finale).

How it plays (all numbers and geometry: `Shared/Logic/BigBadVacuum.luau`, unit-tested in `tests/BigBadVacuum.spec.luau`):
- The boss falls from the ceiling (a growing red warning on the floor), roars, then chases someone and attacks. Every attack is a
  telegraphed danger zone that fills up, then hits: SWEEP (a brush arm swings through a 156 degree wedge), CHARGE (a lane; it runs
  into the wall), SUCTION (a cone pulls everyone to its mouth), CORD SLAM (a circle, then a shockwave ring you jump; two in a row in
  phase 3), WHIRL (it spins its arm all the way round) and DUST BOMBS (circles on people and round the arena). Warnings get quicker
  with each phase (68% and 34% health; each break shoves everyone back and the boss can't be hurt for 3 s).
- Players pick toy bricks up by walking onto piles (one brick at a time) and THROW (E) them: a brick on the armour chips (1), a brick on
  the open CORE hatch is a CRIT (10; crits within 1.3 s make a VOLLEY, up to x1.6). The core is open only after a CHARGE crashes
  into the wall (about 6 s), a SUCTION overheats it (about 3.5 s) or a WHIRL leaves it dizzy (about 3.8 s): the lobby dodges, baits
  the charge, then everyone throws. A tall beacon marks the open core.
- SUCTION also stuffs people who reach the mouth into the DUST BAG (a few at a time, spat out after 7 s; the boss heals meanwhile).
  A brick thrown at the bag (BAG, Q) pops it and rescues everyone inside.
- Damage and rescues fill the PARTY METER; full, anyone can press PANIC (F): a sky beam hits for 8% of the boss's health and
  overloads the core for 2.4 s.
- Win by emptying the boss's health (100 per player) before the clock runs out. Nobody is ever out (daze and the bag are the
  setbacks). Score: damage + 8 per rescue + a few bonuses (finisher 15, PANIC 10, everyone else 5). **Results:** a win is everyone's
  win (a shared first place, `WinningTeam = "Squad"`); a loss ranks by contribution (`WinningTeam = "Vacuum"`; the results card says
  "The Vacuum won"; the top contributor still counts first place for rewards and medals, so a win is not claimed by losing).

How it is built:
- Server (`MiniGames/BigBadVacuum.luau`): a boss state machine (Intro, Chase, Wind, Act, Recover, Stun, Break, Dying/Done) and one
  handler per attack (`ATTACKS`); every hit, trap, pickup, throw and the meter are judged on the server, against where a player is
  plus a little of where they are going (`_where`: a dodge that looks clean on a phone counts). The suction's pull is applied by each
  client to its own character and by the server to bots. Shared state: `Boss` (a 10 Hz snapshot with velocity), `Atk` (the plan:
  danger zones with times), `Piles`, `Carry`, `Trap`, `Meter`, `Arena`; events for everything else.
- Client (`client/MiniGames/BigBadVacuum.luau`): the boss rig (eye, hatch, side brushes, arm, bag, cord) animates from the snapshot,
  the zones are drawn from `Atk` with `Rules.ZoneContains`, plus camera flyover during the 3-2-1, shake and FOV punches, the
  victory chain of explosions and the defeat laugh, a boss bar with phase ticks, the meter, banners, and the phone layout (checked
  with `tools/checks/ui_render.py`: 0 problems).
- Bots (`MiniGames/Bots/BigBadVacuum.luau`): dodge by reading the same zones (reaction time and margins by skill), jump the ring,
  fetch bricks, wait for the core, rescue, press PANIC after a human-like delay. The round harness's test bot runs this very brain
  on its stand-ins (and does what a client would do for them: walk, jump, the suction's pull).
- Props are all primitive fallbacks for now (`World/Props/BigBadVacuum.luau`; every prop has an `AssetId = 0` block ready for a
  mesh; the client finds the boss's parts by name). Set `m.PrimaryPart` in a fallback: a model without one gets its bounding box
  turned by the first rotated cylinder and MeshLibrary rescales the prop to the wrong size.
- Test aids: `tools/checks/scenarios/BigBadVacuum_attack.luau` (force one attack, render it), `_bag.luau` (trap, a leave from inside
  the bag, a rescue), `_showcase.luau` (lay the client-drawn parts out for `tools/preview/render.py`).

Not done / for a real playtest (the test servers have no physics): how the suction's pull and the dust bag's anchoring feel on a
device, the camera shake and flyover on phones, the mood lighting, sound (it uses the generic round song; a boss theme needs one of
the owner's audio uploads: `tools/music/songs/BigBadVacuum.py` + `modes.py pack`), real meshes for the boss and arena, and a portal
preview (`tools/preview/make_preview.py BigBadVacuum`). Difficulty is tuned against the bots only (a strong lobby wins about
two times in three, in 60-85 s); expect to retune `HealthFor`, the `Think`/`WIND_SCALE` pace and the core windows from real play.


# Mini-game backlog (games 13-26)

The owner asked for these, in this order, after the first twelve and "after everything else is finished" (owner: "dont
start on game 13+ untill everything else is finished"). Each brief below is what the builder works from. They are built
with the workflow in tools/workflows/build-minigame.js (one builder in a worktree, one reviewer, one fixer), four at a time,
then merged with tools/checks/merge_check.sh <Id>, tested with tools/checks/mode_check.sh <Id>, given a portal preview
(tools/preview/make_preview.py <Id>) and published. Every game is for 1-12 players (bots fill), phones first, real meshes.

Planned categories once all 25 exist (the brief leaves some open; these are the picks):

| Category | Today | After the backlog |
| --- | --- | --- |
| Team | Pump & Pop, Bobsled Run, Cake Factory | + Prime Cut, Eatsa Pizza, Log Jam (6) |
| Reaction | Hex Meltdown, Rake It In, Crazy Cutters | + Mecha-Marathon, Messy Memory, Trace Race (6) |
| Versus | Sinking Sands, Arrow Ambush, Shark Bait | + Tanks!, Stamp Out, Struggle (6) |
| Knockback | Bumper Ballers | + Snowball Summit, Slaparazzi (3) |
| Survival | Fire Rope | + Spleef (2) |
| Luck | Honey Trap | + Parasol Plummet (2) |
| Race | Skate Escape | + Rockin' Raceway (2) |

(Suggested to the owner: Messy Memory as Luck and Tanks! as Knockback would even the thin categories.)

Also on the backlog: **custom music for each mini-game** (owner: "put in the backlog custom music for each mini game").
No longer blocked: other players' devices load and play our uploaded music now (their reports from version 27).

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

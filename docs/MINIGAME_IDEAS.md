# Mini-game ideas (backlog)

Ideas inspired by classic party-game **mechanics**. Rules and mechanics can't be owned; names,
characters, art, music and level layouts can. Every idea below uses an original name and theme, and
nothing should reuse Nintendo assets, characters or recognizable layouts (see the IP note in the
design outline, §1). None of these are implemented yet, though two are close to games that exist
now: Bumper Blobs to Bumper Ballers, Fuse Frenzy to Hot Potato. The "Fits our kit" column names
modes that aren't in the game (Yeet Arena, Greedy Goblins, The Wrong Button, the cart race).

| Idea | Mechanic | Category | Fits our kit |
| --- | --- | --- | --- |
| **Piñata Plungers** | Players take turns pushing one of several plungers; one is the dud that pops the piñata on you. The last player standing wins. Pure nerve. | Luck / Reaction | Tiles plus `ctx:Eliminate`; turn order in a `ctx:Loop` |
| **Bumper Blobs** | Sumo on giant bouncy balls on a small round stage. Bump others off. | Knockback | Yeet Arena's shrinking platform plus `Knockback` remote |
| **Captain Copycat** | A robot captain calls "left up!", "right down!" and players match the pose in time. Later rounds add "do the opposite!". | Reaction | The Wrong Button's call loop; poses chosen from UI buttons |
| **Fuse Frenzy** | A ticking bomb hops between players on touch. Whoever holds it when it pops is out. The fuse gets shorter each round. | Survival | Distance checks like Greedy Goblins pickups |
| **Wall Squeeze** | A wall with a cut-out shape slides toward you, so stand in the gap. Shapes get trickier. | Survival | One moving part per wall; hit check like the mallets |
| **Rocket Mash** | Tap as fast as you can to fuel your rocket; the highest rocket wins. Server caps the tap rate. | Reaction | Rate-limited remote plus a race-style ranking |
| **Coin Cloudburst** | Coins and junk rain from the sky. Grab coins, dodge pianos. | Collection | Greedy Goblins pickups plus anvil warnings |
| **Snowball Slope** | Climb a slope while giant snowballs roll down. First to the top wins. | Race | Cart race checkpoints plus boulders |
| **Tug Team** | Two teams tug a rope by tapping in rhythm. Stay in sync to pull harder. | Team | Team scores plus a moving rope part |
| **Paint Panic** | Paint tiles your team's color by walking on them. Most tiles wins. | Team / Territory | Wrong Button tiles plus team colors (design doc's "Color Clash") |

Next steps for any of these: `lune run tools/new-minigame <Id> "<Name>" <Category>` (see
[ADDING_MINIGAMES.md](ADDING_MINIGAMES.md)), graybox it, and playtest before adding art.

# 🎉 Party Panic

> Two Claudes are working on this project: read [docs/HANDOFF.md](docs/HANDOFF.md) first (who works on what, how to
> test without Studio, what's open). The next games are in [docs/MINIGAME_BACKLOG.md](docs/MINIGAME_BACKLOG.md).

A Roblox multiplayer party game: hang out in a lively lobby, vote on the next mini-game, compete in
short chaotic rounds, earn rewards, and do it all again. Built from the *Party Panic Game Design
Outline*.

> **Get together. Pick the chaos. Play. Laugh. Repeat.**

## What's in the box

| Area | Highlights |
| --- | --- |
| **Core loop** | A server-authoritative state machine (Waiting → Intermission → Voting → Preparing → In Round → Results → Cleanup) with a watchdog. Every mini-game call runs with a timeout, so a broken mode can't stall the server. |
| **Sitting out** | A big switch right by the phase banner (and in Settings): 🎮 PLAYING or 💤 SITTING OUT. Sitting out keeps you in the lobby while rounds go on and bots take your spot; you finish a round you're in, don't vote while you're out, and jump back in with one tap. If everyone sits out, rounds wait in the lobby. It resets when you leave. |
| **Voting** | Four cards: three games and Random (a hidden pick, revealed if it wins), with live counts; change your vote until time runs out; random tie-breaks; recently played modes down-weighted; category mixing. Tap a card to vote. The stage's four portals play a little looping preview of each option (Random's spins through the games like a slot machine and lands on its game if it wins), and take turns showing every game between votes. |
| **Mini-games** | Fifteen party classics rebuilt for 12 players: 🔥 Fire Rope · ⚡ Hex Meltdown · 🍯 Honey Trap · 🎈 Pump & Pop · 🛹 Skate Escape · 🏹 Arrow Ambush · 🏜️ Sinking Sands · 🔵 Bumper Ballers · 🥕 Rake It In · 🍪 Crazy Cutters · 🎂 Cake Factory · 🛷 Bobsled Run · 🦈 Shark Bait · 🚁 Mecha-Marathon · ❄️ Spleef |
| **Bots** | Friendly AI players fill empty spots so every round feels full (8 by default): they fade out when someone joins, fade back in when someone leaves, play every mode with their own brain at varied skill, and are clearly labelled 🤖 with a BOT nameplate. No rewards, no saved data. |
| **Progression** | Small, easy-to-read coins (a round pays 2-6) and XP, itemized round rewards, personal bests, a first-win-of-the-day bonus, daily and weekly quests, a daily gift with streaks, a hidden daily token. The **Rewards Road**: every level pays coins and most milestone levels unlock a cosmetic you can't buy, always shown on the HUD as the next goal; **career milestones** (rounds, wins, podiums, every game, days played) unlock titles; **prestige colors** on the name tag and level badge every 10 levels; a level-up celebration card in the lobby (with EQUIP for what it unlocked; it never blocks the stick, jump or menu) and, back in the lobby, a "Lv 10!" over your head for everyone to see; returning players get the rewards they had already earned in a "NEW REWARDS!" card. Saved coins moved to the low scale once (divided by 10, rounded up; items kept) |
| **Cosmetics** | Trails, titles, emotes (dances and effect emotes), victory and knockout effects, a coin shop with confirmation, an optional VIP pass (cosmetic only, never pay-to-win) |
| **Lobby** | A sunny theme-park plaza built around the vote stage: four portal bays that play previews of the games under a scalloped carnival crown with neon tubes, flanked by candy-striped turrets; a scalloped stone fountain with rubber ducks, arcing water jets and a turning gold trophy (players can wade in); a sunburst court and patterned promenade on a grass lawn with flower beds and tree clusters; a turning Ferris wheel and drifting hot-air balloons on the skyline; beach balls to kick around (players pass through them and the server punts them, so there's no lag-bump on phones); a winner podium of gold, silver and bronze tiers under a bulb-lit candy arch; a shop with a mannequin gallery; a wooden quest kiosk and a giant gumball gift machine; a carnival shooting gallery (striped awning, bulbs, tin ducks) for the arcade target range; a Skee-Ball arcade (four machines on a patio of giant tickets with a TODAY'S BEST board: drag to roll nine balls, the server scores every roll, no coins, just your best); an emote stage with a dance floor under a fan-crowned arch with speakers and a circus confetti cannon; an obby in a pool of goo (hops, candy pillars, beams and ledges up a lookout tower to a view deck, with checkpoints: a fall puts you back on the last one), lamp posts strung with bunting, floating confetti, and a ring of trees and hills |
| **Look** | Rounded CSG geometry instead of blocks, over a hundred detailed original mesh props (every arena has its own set), ShadowMap lighting (sharp sun shadows, light on phones), bloom, sun rays, clouds, ambient particles and bobbing decorations |
| **Audio** | An original soundtrack (two lobby tracks plus a round track that speeds up near the end) and 15 original sound effects |
| **UI** | Mobile-first scaling, rounded glossy panels, toasts, rules card with a 3-2-1 countdown, standings, results breakdown, spectate, settings (music volume, reduced effects), onboarding tips |
| **Safety** | Session-locked DataStore saves, rate-limited and validated remotes, server-side hit, pickup and checkpoint validation, and no client-reported scores or rewards |

## Quick start

1. Install the toolchain with [Rokit](https://github.com/rojo-rbx/rokit): `rokit install`
   (installs Rojo, Selene, StyLua and Lune at the versions in `rokit.toml`).
2. Build the place: `rojo build -o build/PartyPanic.rbxl`, then open it in Roblox Studio.
   Or run `rojo serve` and connect with the Rojo Studio plugin to live-sync while you edit.
3. Press **Play**. In Studio, a single player is enough to start rounds.

### Publishing (private first)

Open Cloud can't create an experience, so the first time, open the built place in Studio and use
**File > Publish to Roblox As > New experience**. New experiences start **private**. After that,
every publish is one command (it refuses to publish to a public experience unless you say so):

```sh
python3 tools/publish_place.py --universe-id <id> --place-id <id>
```

It builds the place, publishes it, and sets the name, the store description from
[docs/STORE_DESCRIPTION.txt](docs/STORE_DESCRIPTION.txt) and a server size of 12.

- The API key needs **Place Publishing** (write) and **universe.place** (write) for the experience.
- Publishing is refused with *409 "Server is busy"* while a Collaborative Editing (Team Create)
  session holds the place. Close Studio, or turn Collaborative Editing off, and try again.

Store art (thumbnails and icon) lives in [assets/store](assets/store) and is made with
`tools/art/make_art.py` (see [docs/ASSETS.md](docs/ASSETS.md)). The API key can't upload it:
[assets/store/README.md](assets/store/README.md) says where it goes in the Creator Hub.

Also check these in **Game Settings** in Studio:

- **Places**: max players **12** (matches `Config.Session.MaxPlayers`).
- **Avatar**: R15 (emote animations use the default R15 emotes).
- **Security**: enable *Studio Access to API Services* if you want saving to work while testing in
  Studio. Without it you get a temporary profile and a notice; nothing is overwritten.
- Optional: create a VIP game pass and put its id in `Config.Monetization.VipGamePassId`.

### Turn on the real meshes and music

The game runs as-is with built-in fallbacks. To use the generated meshes and the soundtrack, upload
them once (needs an Open Cloud API key, see [docs/ASSETS.md](docs/ASSETS.md)):

```sh
python3 tools/upload_assets.py --user-id <the game owner's user id>
```

## Adding mini-games

```sh
lune run tools/new-minigame HotPotato "Hot Potato" Survival
```

That one command creates a working mode and registers it. Then set
`Config.Debug.ForceGame = "HotPotato"` to test just that mode in Studio. The full guide is in
[docs/ADDING_MINIGAMES.md](docs/ADDING_MINIGAMES.md), and the idea backlog is in
[docs/MINIGAME_IDEAS.md](docs/MINIGAME_IDEAS.md).

## Project layout

```
src/
  shared/            ReplicatedStorage.Shared: config, definitions, catalogs, pure logic
    Logic/           vote tally, game picker, placements, rewards, levels, quests, daily (unit tested)
  server/            ServerScriptService.Server
    Services/        Data, Rewards, Quests, Shop, Voting, RoundManager, RoundContext, Lobby, ...
    MiniGames/       one module per mode (auto-discovered) + Kit/ (MiniGame base, ArenaKit, Glove)
    World/           Build, Shapes (CSG), MeshLibrary, LobbyBuilder, Environment (terrain/sky)
  client/            StarterPlayerScripts.Client
    Controllers/     HUD, Vote, Round, Results, Shop, Quests, Emotes, Spectate, Audio, Effects, ...
    UI/              Theme, UIKit, Modal
assets/              generated meshes (.obj/.glb) and audio (.ogg)
tools/               mesh generator, music composer, asset uploader, mini-game scaffold
tests/               Lune unit tests
docs/                guides and design notes
```

## Seeing the game without Studio

`tools/preview` runs the lobby builder on a **real Roblox server** (Open Cloud Luau execution, no
publish needed), dumps every part, the terrain and the lighting, and renders it with Blender:

```sh
python3 tools/preview/bundle.py > task.luau                  # working-tree World modules + dump script
python3 tools/preview/luau_task.py task.luau - dump.json     # run it on Roblox
python tools/preview/render.py dump.json shots/lobby --views spawn,overview   # needs `pip install bpy`
```

It catches runtime errors and warnings too (CSG failures, missing assets), and it's how the lobby
layout was checked. `bundle.py my_check.luau` runs any script with the World modules loaded.

The portals' game previews are made the same way: `python3 tools/preview/make_preview.py <GameId>`
plays a round on a test server, renders a looping flyover of the arena and uploads it (see
[docs/ADDING_MINIGAMES.md](docs/ADDING_MINIGAMES.md), step 8).

## Checks

```sh
lune run tests/run          # unit tests (vote logic, picker, rewards, quests, registry...)
selene src tests            # lint
stylua --check src tests    # formatting
```

The screens are checked on phones, a tablet and PC by running the whole client on a real Roblox
server, which lays the UI out with the engine itself at each screen size (fonts loaded, real text
measurements), then drawing every screen with Roblox's own buttons, the thumbstick and the jump
button on top and listing text that's cut off or wraps, text under 11 pt on phones, small touch
targets, overlaps and anything in the thumbstick's corner:

```sh
python3 tools/checks/client_harness.py --touch --bots 8 > client.luau   # leave out --touch for PC
python3 tools/preview/luau_task.py client.luau - client.json
python3 tools/checks/ui_render.py client.json /tmp/screens              # PNGs + the problem list
```

Add `--sit-out` to draw the screens of a player sitting out instead (next to the playing ones).

Type checking uses [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) with the Roblox API
definitions:

```sh
rojo sourcemap -o sourcemap.json
luau-lsp analyze --definitions=@roblox=globalTypes.d.luau --sourcemap=sourcemap.json src
```

## Status and honest caveats

- The whole codebase type-checks against the current Roblox API (0 errors) and passes lint, format
  and unit tests, and the place builds with Rojo. Every mini-game is checked on a real Roblox
  server (12 players, real bots, phone screens; see Checks), but those servers have no physics, so
  movement feel, knockbacks and timings are only proven by playing: expect tuning after playtests.
- Balancing values (rewards, prices, timings) are the design outline's starting points. Tune them
  in `src/shared/Config.luau` and `src/shared/Cosmetics.luau`.
- Knockback is applied by the victim's client, because each client simulates its own character.
  The server decides who gets hit, how hard and when.

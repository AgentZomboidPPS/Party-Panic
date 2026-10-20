# 🎉 Party Panic

A Roblox multiplayer party game: hang out in a lively lobby, vote on the next mini-game, compete in
short chaotic rounds, earn rewards, and do it all again. Built from the *Party Panic Game Design
Outline*.

> **Get together. Pick the chaos. Play. Laugh. Repeat.**

## What's in the box

| Area | Highlights |
| --- | --- |
| **Core loop** | A server-authoritative state machine (Waiting → Intermission → Voting → Preparing → In Round → Results → Cleanup) with a watchdog. Every mini-game call runs with a timeout, so a broken mode can't stall the server. |
| **Voting** | Three options with live counts, change your vote until time runs out, random tie-breaks, an occasional *Mystery* card, recently played modes down-weighted, category mixing. Vote by tapping a card or stepping onto a portal pad. |
| **6 launch modes** | 🔨 Don't Get Flattened · 🌋 Floor Is Lava · 🥊 Yeet Arena · 🛒 Shopping Cart Grand Prix · 💰 Greedy Goblins · 🔘 The Wrong Button |
| **Progression** | Coins, XP and levels, itemized round rewards, personal bests, daily and weekly quests, a daily gift with streaks, a hidden daily token, level and stat unlocks |
| **Cosmetics** | Trails, titles, emotes (dances and effect emotes), victory and knockout effects, a coin shop with confirmation, an optional VIP pass (cosmetic only, never pay-to-win) |
| **Lobby** | A vote stage with three portal arches and giant screens, winner podium with avatar headshots, shop, quest board, daily gift machine, arcade target range, emote stage with a confetti cannon, spiral parkour tower, bounce pads, terrain hills, a lake and floating sky islands |
| **Look** | Rounded CSG geometry instead of blocks, 15 detailed original mesh props, ShadowMap lighting (sharp sun shadows, light on phones), bloom, sun rays, clouds, ambient particles and bobbing decorations |
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

## Checks

```sh
lune run tests/run          # unit tests (vote logic, picker, rewards, quests, registry...)
selene src tests            # lint
stylua --check src tests    # formatting
```

Type checking uses [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) with the Roblox API
definitions:

```sh
rojo sourcemap -o sourcemap.json
luau-lsp analyze --definitions=@roblox=globalTypes.d.luau --sourcemap=sourcemap.json src
```

## Status and honest caveats

- The whole codebase type-checks against the current Roblox API (0 errors) and passes lint, format
  and unit tests, and the place builds with Rojo. **It has not been play-tested inside Roblox
  Studio yet.** That wasn't possible in the environment it was built in, so expect a round of
  tuning and small fixes after the first playtests (hazard timings, arena sizes, UI positions).
- Balancing values (rewards, prices, timings) are the design outline's starting points. Tune them
  in `src/shared/Config.luau` and `src/shared/Cosmetics.luau`.
- Knockback is applied by the victim's client, because each client simulates its own character.
  The server decides who gets hit, how hard and when.

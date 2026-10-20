# Adding a mini-game

Party Panic is built so a new mode is **one file plus one definition**. The round manager, voting,
rewards, quests, results screen, spectating and cleanup all work automatically.

## 1. Scaffold it

```sh
lune run tools/new-minigame HotPotato "Hot Potato" Survival
lune run tools/new-minigame CaptureTheCake "Capture the Cake" Team --team
```

Categories: `Survival`, `Race`, `Knockback`, `Reaction`, `Team`.

This creates `src/server/MiniGames/HotPotato.luau` (a small but working game) and adds an entry
to `src/shared/GameDefinitions.luau`. Fill in the entry's `Objective` and `Controls`: those lines
appear on the vote cards and the rules screen.

## 2. Test only your mode

In `src/shared/Config.luau`:

```lua
Config.Debug = {
	ForceGame = "HotPotato", -- Studio only: every vote offers just this mode
	StudioIntermissionTime = 8,
	...
}
```

Start `rojo serve`, connect the Rojo plugin, and press **Play** in Studio. With one player, Studio
ignores minimum player counts, so you can test solo. Clear `ForceGame` when you're done.

## 3. Write the rules

A mode extends `Kit/MiniGame` and usually implements just two methods:

```lua
local MyGame = MiniGame.Define("MyGame", { Results = "Score" }) -- "Survival" | "Score" | "Team"

function MyGame:Prepare()   -- build the arena under self.context.Arena, then spawn players
function MyGame:Start()     -- start loops/hazards; runs when the countdown hits GO
```

Optional overrides: `:Stop(reason)`, `:GetResults()`, `:Cleanup()`.

### The round context (`self.context`)

| Need | Use |
| --- | --- |
| Place players | `ctx:SpawnAll(points, true)` (frozen until GO), `ArenaKit.SpawnRing/SpawnGrid` |
| Who's playing | `ctx:GetPlayers()`, `ctx:GetAlivePlayers()`, `ctx:GetCharacter(player)` |
| Knock someone out | `ctx:Eliminate(player, "reason")` (also automatic below `ctx.KillY`) |
| Falling behavior | `ctx.RespawnMode = "Eliminate"` or `"Respawn"` + `ctx.Hooks.Respawn = function(player) return cframe end` |
| End early | `ctx.EndWhenOneLeft = true`, or `ctx:End("reason")` |
| Score | `ctx:AddScore(player, n)`, `ctx:SetScoreText(player, "3 laps")` |
| Teams | `ctx:SetTeam(player, "Red")`, `ctx:AddTeamScore("Red", n)` |
| HUD | `ctx:SetStatus("Survivors: 4")`, `ctx:Announce("Watch out!", "warning")`, `ctx:Sound("HazardWarning")` |
| Timing | `ctx:Loop(fn)` (fn returns seconds to wait), `ctx:Heartbeat(fn)`, `ctx:Delay(t, fn)`, `ctx:Progress()` (0 to 1) |

Everything scheduled through the context stops by itself when the round ends, and the arena and
any tools are cleaned up automatically, so a mode can't leak into the next round.

### Building blocks

- `Kit/ArenaKit`: spawn layouts, hazard warning circles and strips, signs, distance helpers.
- `World/Shapes`: rounded boxes, slabs, capsules, arches (soft geometry, not blocks).
- `World/MeshLibrary`: mesh props such as `MeshLibrary.Get("Boulder", { CFrame = ..., Parent = ctx.Arena })`.
- `Kit/Glove`: a server-validated melee tool with knockback (used by Yeet Arena and Greedy Goblins).

## Quality bar (from the design outline)

A mode should only join the live pool when it's fun in repeated tests, easy to explain in one
sentence, stable with a full server, and has a clear end condition. Use `Enabled = false` in its
definition to keep a mode out of the vote while you work on it, and `IsNew = true` to give a
finished mode a little extra exposure.

## Safety nets

- A module that errors on load, or doesn't match its definition, is disabled with a warning rather
  than breaking the server.
- Every mode call runs with a timeout. A stuck `Prepare` or `Start` ends the round safely.
- `lune run tests/run` checks that every module has a definition and the reverse.

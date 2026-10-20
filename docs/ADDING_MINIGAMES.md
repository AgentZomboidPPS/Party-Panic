# Adding a mini-game

Party Panic is built so a new mode is **a server module, a client half and a definition**. The round
manager, voting, rewards, quests, results screen, spectating and cleanup all work automatically, for
1 to 12 players.

## 1. Scaffold it

```sh
lune run tools/new-minigame HotPotato "Hot Potato" Survival
lune run tools/new-minigame CaptureTheCake "Capture the Cake" Team --team
```

Categories: `Survival`, `Race`, `Knockback`, `Reaction`, `Team`, `Luck`, `Versus`.

It creates a small but working game you can play right away:

| File | What it is |
| --- | --- |
| `src/server/MiniGames/HotPotato.luau` | the rules (server) |
| `src/client/MiniGames/HotPotato.luau` | the client half: HUD, controls, smooth visuals |
| `src/server/MiniGames/Bots/HotPotato.luau` | how bots play it |
| `src/server/World/Props/HotPotato.luau` | the mode's props (mesh specs with primitive fallbacks) |
| `tools/meshgen/props/HotPotato.py` | the props' meshes |
| `tools/checks/bots/HotPotato.luau` | a test bot for the real-server round harness |

and an entry in `src/shared/GameDefinitions.luau`. Fill in its `Objective` and `Controls`: those
lines appear on the vote cards and the rules screen.

## 2. Play it

**On a real Roblox server, with 12 bots** (no Studio needed; this is how every mode is tested):

```sh
python3 tools/checks/round_harness.py HotPotato --players 12 --client --dump-at 8 --map map.json > round.luau
python3 tools/preview/luau_task.py round.luau - round.json
python3 tools/checks/summarize.py round.json map.json --dump arena.json
```

`--client` also runs the client half as Bot1. The summary shows errors (as `module:line`), how the
round ended, the results, and whether the arena and shared state were cleaned up. The test server
has **no physics**: bots move rigs with `PivotTo`, which is one more reason modes check positions
instead of relying on `Touched`. Try 2 and 5 players too.

**In Studio:** set `Config.Debug.ForceGame = "HotPotato"` in `src/shared/Config.luau`, `rojo serve`,
press Play. With one player Studio ignores minimum player counts. Clear `ForceGame` when done.
Anything physical (jumping, rolling, steering) and anything on a phone (tilt, touch) has to be
checked this way.

## 3. Write the rules (server)

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
| Teams | `ctx:AssignTeams({ "Red", "Blue" })`, `ctx:SetTeam(player, "Red")`, `ctx:AddTeamScore("Red", n)`, `Teams.CountFor(n, perTeam)` |
| Controls from clients | `ctx:OnAction("Pump", function(player, ...) end, { Interval = 0.1 })` - validate everything |
| State for clients | `ctx:SetShared(key, v)`, `ctx:SetSharedJSON(key, t)`, `ctx:SetPlayerShared(player, key, v)` |
| Cues for clients | `ctx:Fire(player or list or nil, "Name", ...)` |
| Models for clients | `ctx:ShareTemplate("Fruit", MeshLibrary.Get("Fruit"))` (client: `api:Template("Fruit")`) |
| Server clock | `ctx:Now()` - the same clock clients see, for shared schedules |
| HUD | `ctx:SetStatus("Survivors: 4")`, `ctx:Announce("Watch out!", "warning")`, `ctx:Sound("HazardWarning")` |
| Timing | `ctx:Loop(fn)` (fn returns seconds to wait), `ctx:Heartbeat(fn)`, `ctx:Delay(t, fn)`, `ctx:Progress()` |
| Short freeze | `ctx:Stun(player, seconds)`, `ctx:Freeze(player, true)`, `ctx:SetWalkSpeed(player, n)` |

Everything scheduled through the context stops by itself when the round ends, and the arena,
shared state and templates are cleaned up automatically, so a mode can't leak into the next round.

**The house rules:** the server owns scores, eliminations, timing and positions. A client only asks
(`api:Action`) and draws. Never trust an amount a client sends; time it on the server, with a
little leeway for ping (`player:GetNetworkPing()`), like Fire Rope and Honey Trap do. Moving
hazards are animated on clients from a shared schedule (smooth), and the server checks player
positions against the same schedule.

## 4. The client half

```lua
function MyGame.Start(api)
	api:Mood({ Tint = ..., Saturation = 0.15 })           -- this player's color grading for the arena
	local hud = api:TopHud()                               -- under the round banner, every screen size
	local label = UIKit.Label({ Position = UDim2.new(0.5, 0, 0, api:HudY()), Parent = hud, ... })
	local pump = api:Button({ Text = "PUMP", Key = Enum.KeyCode.E })  -- beside the jump button on phones
	pump.Pressed:Connect(function() api:Action("PumpDown") end)
	api:OnShared("Air", function(value) ... end)
	api:RenderStep(function(dt) ... end)                   -- animate from api:Now() and shared state
end
```

Also: `api:Shared/SharedJSON/OnShared`, `api:Mine/OnMine` (per-player state), `api:OnEvent`,
`api:Hint(text, y)`, `api:Template(name)`, `api:Sound(name)`, `api:Effect(name, position)`,
`api:Tilt()` (phone tilt), `api:World` (a folder for client-made parts), `api:Track(thing)`.

**HUD rules:** everything goes in `api:TopHud()` at `y >= api:HudY()` so it never covers the
round banner, status line or team scores; action buttons come from `api:Button`. Keep text short
and big, and pair every color with a shape or icon. Check the layout on phones (below).

## 5. Props and meshes

Detailed meshes, not blocks. A mode's props live in its own files, so modes never edit the same
file:

```sh
python3 tools/meshgen/generate_meshes.py --only Pump,Balloon          # assets/meshes/*.glb
<blender python> tools/preview/meshpreview.py out.png Pump Balloon    # look at them
python3 tools/upload_assets.py --user-id <owner> --what meshes --only Pump,Balloon
python3 tools/checks/asset_status.py --meshes                         # approved for every player?
```

The upload writes each `AssetId` into `World/Props/<Mode>.luau`. Until a mesh is uploaded and
approved by moderation the game uses its `Fallback`. Build meshes facing **-Z** (their front);
MeshLibrary corrects for Roblox's importer, which turns glTF models half a turn.
`Kit/Scenery` has ready-made settings: `Meadow`, `LavaLake`, `Ground`, `Volcano`, `RockRim`.

## 6. Teach the bots to play it

Bots fill empty spots so every round feels full (`Config.Bots`: the server keeps 8 participants while
anyone is here; bots fade out when players join and back in when they leave). They are clearly
labelled, never earn rewards, and look like players to the round code, so a mode needs no special
cases for them, with two exceptions:

1. **A brain:** `src/server/MiniGames/Bots/<Mode>.luau` tells bots how to play (see `Bots/Default.luau`,
   which plays any mode that has none):

   ```lua
   local Brain = {}
   function Brain.Step(bot, ctx, mode, dt)        -- ~7 times a second per bot still in the round
       local root = bot:Root()
       if root and bot:Chance(0.1) then bot:Jump() end
       bot:MoveTo(target)                           -- walk (call again each step)
       ctx:BotAction(bot, "Pump")                   -- press a control like a client does
   end
   return Brain
   ```

   Use `bot.Skill` (0.35 to 0.9) and `bot:Reaction()` so bots differ and stay beatable; keep per-round
   notes in `bot.Memory`.
2. **Hazards must catch bots too.** Bots are moved by the server. A hazard you animate only on clients
   (sinking floors, sweeping beams) never touches a bot on the server, so check bots against it on
   the server (e.g. a bot over a sunk hex drops and is eliminated). Use `ctx:Knockback(player,
   velocity, stun)` to throw anyone; it works for players and bots.

Test with real bots: `round_harness.py <Mode> --players 2 --bots 10 ...` (the test server has no
physics, so bots' walking and jumping are simulated there).

## 7. Check it looks right

```sh
python3 tools/preview/render.py arena.json out --views player,overview --cameras cams.json   # the arena
python3 tools/preview/zfight.py arena.json                                                   # flicker
python3 tools/checks/round_harness.py MyGame --client --touch --ui-at 3,10 ... > ui.luau      # phone HUD
python3 tools/checks/ui_render.py ui.json out --sizes all                                    # draw + check
```

`render.py` needs Blender's `bpy` (Python 3.11). `ui_render.py` draws the player's screen at PC,
phone, small phone and tablet sizes with Roblox's buttons, thumbstick and jump button, and lists
overlaps and anything off-screen.

## Quality bar

A mode should only join the live pool when it's fun in repeated tests, easy to explain in one
sentence, stable with a full server, and has a clear end condition. Use `Enabled = false` in its
definition to keep a mode out of the vote while you work on it, and `IsNew = true` to give a
finished mode a little extra exposure.

## Safety nets

- A module that errors on load, or doesn't match its definition, is disabled with a warning rather
  than breaking the server.
- Every mode call runs with a timeout. A stuck `Prepare` or `Start` ends the round safely.
- `lune run tests/run` checks that every module has a definition and the reverse.

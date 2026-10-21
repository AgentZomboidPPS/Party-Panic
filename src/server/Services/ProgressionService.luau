-- Long-term payoffs (owner: "Also we need cool payoffs for players that keep playing the game."):
-- the level-up moment (the Rewards Road's coins and exclusive cosmetics, a celebration on the
-- player's screen and a "Lv 10!" that pops over their head for everyone to see) and career
-- milestone celebrations. The server grants everything first (Economy pays the road's coins,
-- CosmeticService grants the items, once each); clients only show what they're sent.
-- Second pass (review): most level-ups happen as a round's rewards are paid, when everyone's
-- results window covers the screen and the players are still in the arena, so the "Lv 10!" pop
-- waits until everyone is back in the lobby (Cleanup, after the new characters have spawned).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local CosmeticService = require(script.Parent.CosmeticService)
local Notifier = require(script.Parent.Notifier)
local Telemetry = require(script.Parent.Telemetry)

local ProgressionService = {}

local celebrateRemote = Remotes.Get("Celebrate")
local popRemote = Remotes.Get("LevelPop")

-- Phases when the pop waits: the round (and its results) is on, players are in the arena.
local HOLD_IN = { Preparing = true, InRound = true, Results = true }
local POP_AFTER_RESPAWN = 2 -- seconds into Cleanup: the round's players have their lobby characters
local heldPops: { [Player]: number } = {} -- the level to pop once back in the lobby
local flushQueued = false

export type Celebration = {
	Kind: string, -- "LevelUp" | "Milestone"
	Level: number?, -- LevelUp: the new level
	From: number?, -- LevelUp: the level before
	Coins: number, -- coins this paid (already added)
	Items: { string }, -- cosmetics this unlocked (already owned)
}

local function ids(items: { Cosmetics.Cosmetic }): { string }
	local list = {}
	for _, item in items do
		table.insert(list, item.Id)
	end
	return list
end

local function milestoneTelemetry(player: Player, items: { Cosmetics.Cosmetic })
	for _, item in items do
		if item.UnlockStat then
			Telemetry.PlayerEvent(player, "MilestoneUnlocked", 1, item.Id)
		end
	end
end

-- "Lv 10!" over the player's head for everyone around, with a sparkle.
local function pop(player: Player, level: number)
	local character = player.Character
	if not character or not player.Parent then
		return
	end
	popRemote:FireAllClients(character, level)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		Notifier.Effect("Sparkles", root.Position + Vector3.new(0, 3, 0))
	end
end

-- The pops held through a round, once everyone is back in the lobby (a character still spawning
-- gets a moment).
local function flushHeldPops()
	flushQueued = false
	for player, level in heldPops do
		heldPops[player] = nil
		task.spawn(function()
			local deadline = os.clock() + 3
			while not player.Character and player.Parent and os.clock() < deadline do
				task.wait(0.1)
			end
			pop(player, level)
		end)
	end
end

-- Economy.AddXP calls this once the level went from `before` to `after` and the road's coins for
-- those levels (`coins`) were added. Several levels at once make one celebration.
function ProgressionService.LevelUp(player: Player, before: number, after: number, coins: number)
	local unlocked = CosmeticService.CheckUnlocks(player, true)
	CosmeticService.Refresh(player) -- the name tag shows the new level and its color
	milestoneTelemetry(player, unlocked)
	local payload: Celebration =
		{ Kind = "LevelUp", Level = after, From = before, Coins = coins, Items = ids(unlocked) }
	celebrateRemote:FireClient(player, payload)
	if HOLD_IN[GameState.Get("Phase") or "Waiting"] then
		heldPops[player] = math.max(heldPops[player] or 0, after)
	else
		pop(player, after)
	end
end

-- After lifetime stats changed (RewardService, after each round): celebrates the career
-- milestones they just unlocked.
function ProgressionService.CheckMilestones(player: Player)
	local unlocked = CosmeticService.CheckUnlocks(player, true)
	if #unlocked == 0 then
		return
	end
	milestoneTelemetry(player, unlocked)
	local payload: Celebration = { Kind = "Milestone", Coins = 0, Items = ids(unlocked) }
	celebrateRemote:FireClient(player, payload)
end

-- Connected when the module loads (Economy and RewardService require it; it has no Init).
GameState.Changed("Phase", function(phase)
	if HOLD_IN[phase] or flushQueued or next(heldPops) == nil then
		return
	end
	-- Cleanup gives the round's players new characters in the lobby; Intermission or Waiting come
	-- after it (or after a round that stopped early).
	flushQueued = true
	task.delay(if phase == "Cleanup" then POP_AFTER_RESPAWN else 0, flushHeldPops)
end)
Players.PlayerRemoving:Connect(function(player)
	heldPops[player] = nil
end)

return ProgressionService

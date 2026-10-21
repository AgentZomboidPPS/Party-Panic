-- Long-term payoffs (owner: "Also we need cool payoffs for players that keep playing the game."):
-- the level-up moment (the Rewards Road's coins and exclusive cosmetics, a celebration on the
-- player's screen and a "Lv 10!" that pops over their head for everyone to see) and career
-- milestone celebrations. The server grants everything first (Economy pays the road's coins,
-- CosmeticService grants the items, once each); clients only show what they're sent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local Remotes = require(Shared.Remotes)

local CosmeticService = require(script.Parent.CosmeticService)
local Notifier = require(script.Parent.Notifier)
local Telemetry = require(script.Parent.Telemetry)

local ProgressionService = {}

local celebrateRemote = Remotes.Get("Celebrate")
local popRemote = Remotes.Get("LevelPop")

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

-- Economy.AddXP calls this once the level went from `before` to `after` and the road's coins for
-- those levels (`coins`) were added. Several levels at once make one celebration.
function ProgressionService.LevelUp(player: Player, before: number, after: number, coins: number)
	local unlocked = CosmeticService.CheckUnlocks(player, true)
	CosmeticService.Refresh(player) -- the name tag shows the new level and its color
	milestoneTelemetry(player, unlocked)
	local payload: Celebration =
		{ Kind = "LevelUp", Level = after, From = before, Coins = coins, Items = ids(unlocked) }
	celebrateRemote:FireClient(player, payload)
	local character = player.Character
	if character then
		popRemote:FireAllClients(character, after)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Notifier.Effect("Sparkles", root.Position + Vector3.new(0, 3, 0))
		end
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

return ProgressionService

-- The only place coins and XP are granted or spent. Amounts are always computed on the server;
-- clients never submit coin totals, placements or rewards (design doc §14 "Server authority").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local LevelCurve = require(Shared.Logic.LevelCurve)

local CosmeticService = require(script.Parent.CosmeticService)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local Telemetry = require(script.Parent.Telemetry)

local Economy = {}

function Economy.AddCoins(player: Player, amount: number, reason: string): boolean
	local profile = DataService.Get(player)
	if not profile or amount <= 0 or amount ~= amount then
		return false
	end
	profile.Data.Coins += math.floor(amount)
	Telemetry.PlayerEvent(player, "CoinsEarned:" .. reason, amount)
	DataService.Changed(player)
	return true
end

function Economy.SpendCoins(player: Player, amount: number, reason: string): boolean
	local profile = DataService.Get(player)
	if not profile or amount < 0 or amount ~= amount or profile.Data.Coins < amount then
		return false
	end
	profile.Data.Coins -= math.floor(amount)
	Telemetry.PlayerEvent(player, "CoinsSpent:" .. reason, amount)
	DataService.Changed(player)
	return true
end

function Economy.AddXP(player: Player, amount: number)
	local profile = DataService.Get(player)
	if not profile or amount <= 0 or amount ~= amount then
		return
	end
	local before = LevelCurve.FromTotalXP(profile.Data.XP)
	profile.Data.XP += math.floor(amount)
	local after = LevelCurve.FromTotalXP(profile.Data.XP)
	if after > before then
		local bonus = (after - before) * Config.LevelUpCoins
		profile.Data.Coins += bonus
		Notifier.Send(player, `Level up! You're now level {after}. +{bonus} coins`, "reward", 5)
		Telemetry.PlayerEvent(player, "LevelUp", after)
		CosmeticService.CheckUnlocks(player)
		CosmeticService.Refresh(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Notifier.Effect("Sparkles", root.Position + Vector3.new(0, 3, 0))
		end
	end
	DataService.Changed(player)
end

return Economy

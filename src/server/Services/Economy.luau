-- The only place coins and XP are granted or spent. Amounts are always computed on the server;
-- clients never submit coin totals, placements or rewards (design doc §14 "Server authority").
-- Coins are on the low scale (owner: "I want low currency not high"; see Config.Rewards). Each
-- level reached pays the Rewards Road's coins (Config.Road) exactly once, since XP only goes up,
-- and ProgressionService unlocks the level's cosmetics and celebrates. A GOLD PASS owner's level
-- also pays the gold lane's coins (owner: "the paid one should also be insane"; GoldPassService).
-- Every coin in and out, and every level, also goes to Roblox's economy and progression reports
-- (Telemetry.Coins, Telemetry.Levels; owner: "What information should we collect to gage if players
-- are having fun and staying?"): whether the rewards keep people going and the shop feels in reach.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local LevelCurve = require(Shared.Logic.LevelCurve)
local ProgressionLogic = require(Shared.Logic.ProgressionLogic)

local DataService = require(script.Parent.DataService)
local GoldPassService = require(script.Parent.GoldPassService)
local ProgressionService = require(script.Parent.ProgressionService)
local Telemetry = require(script.Parent.Telemetry)

local Economy = {}

function Economy.AddCoins(player: Player, amount: number, reason: string): boolean
	local profile = DataService.Get(player)
	if not profile or amount <= 0 or amount ~= amount then
		return false
	end
	profile.Data.Coins += math.floor(amount)
	Telemetry.PlayerEvent(player, "CoinsEarned", amount, reason)
	Telemetry.Coins(player, math.floor(amount), profile.Data.Coins, reason)
	DataService.Changed(player)
	return true
end

function Economy.SpendCoins(player: Player, amount: number, reason: string, item: string?): boolean
	local profile = DataService.Get(player)
	if not profile or amount < 0 or amount ~= amount or profile.Data.Coins < amount then
		return false
	end
	profile.Data.Coins -= math.floor(amount)
	Telemetry.PlayerEvent(player, "CoinsSpent", amount, reason)
	Telemetry.Coins(player, -math.floor(amount), profile.Data.Coins, reason, item)
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
		local coins = ProgressionLogic.CoinsBetween(before, after, Config.Road)
		profile.Data.Coins += coins
		local goldCoins = GoldPassService.LevelUp(player, after) -- (added already, 0 without the pass)
		Telemetry.PlayerEvent(player, "LevelUp", after)
		Telemetry.Coins(player, coins, profile.Data.Coins - goldCoins, "Road", `Level {after}`)
		Telemetry.Coins(player, goldCoins, profile.Data.Coins, "GoldPass", `Level {after}`)
		Telemetry.Levels(player, before, after)
		ProgressionService.LevelUp(player, before, after, coins, goldCoins)
	end
	DataService.Changed(player)
end

return Economy

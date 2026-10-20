-- Grants round rewards, updates lifetime stats and quests, and sends each player their breakdown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Placement = require(Shared.Logic.Placement)
local Remotes = require(Shared.Remotes)
local RewardLogic = require(Shared.Logic.RewardLogic)

local CosmeticService = require(script.Parent.CosmeticService)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.Economy)
local QuestService = require(script.Parent.QuestService)
local Telemetry = require(script.Parent.Telemetry)

local RewardService = {}

local resultsRemote = Remotes.Get("RoundResults")

export type ResultEntry = {
	Player: Player,
	Rank: number, -- higher is better
	ScoreText: string,
	BestScore: number?, -- higher is better; used for personal bests
	Survived: number?, -- seconds survived (survival games)
	Team: string?,
}

local function favoriteCategory(categoryPlays: { [string]: number }): string?
	local best, bestCount = nil, 0
	for category, count in categoryPlays do
		if count > bestCount then
			best, bestCount = category, count
		end
	end
	return best
end

-- `placed` is the output of Placement.Assign over ResultEntry values.
function RewardService.GrantRound(definition, placed: { Placement.Placed }, winningTeam: string?)
	local playerCount = #placed
	local standings = {}
	for index, item in placed do
		if index > 8 then
			break
		end
		local entry = item.Entry :: any
		table.insert(standings, {
			Name = entry.Player.DisplayName,
			UserId = entry.Player.UserId,
			Place = item.Place,
			ScoreText = entry.ScoreText,
			Team = entry.Team,
		})
	end

	for _, item in placed do
		local entry = item.Entry :: any
		local player: Player = entry.Player
		local profile = DataService.Get(player)
		if not profile or not player.Parent then
			continue
		end
		local stats = profile.Data.Stats
		local favorite = favoriteCategory(stats.CategoryPlays)

		stats.RoundsPlayed += 1
		stats.ModePlays[definition.Id] = (stats.ModePlays[definition.Id] or 0) + 1
		stats.CategoryPlays[definition.Category] = (stats.CategoryPlays[definition.Category] or 0) + 1

		local personalBest = false
		if entry.BestScore ~= nil then
			local previous = stats.Best[definition.Id]
			if previous == nil or entry.BestScore > previous then
				personalBest = previous ~= nil
				stats.Best[definition.Id] = entry.BestScore
			end
		end

		local reward = RewardLogic.ForRound({
			Place = item.Place,
			PlayerCount = playerCount,
			PersonalBest = personalBest,
		}, Config.Rewards)

		QuestService.Track(player, "RoundPlayed")
		if reward.IsTopHalf then
			stats.TopHalf += 1
			QuestService.Track(player, "TopHalf")
		end
		if reward.IsWinner then
			stats.Wins += 1
			if definition.Category == "Survival" then
				stats.SurvivalWins += 1
			end
			QuestService.Track(player, "Win")
			if favorite ~= nil and favorite ~= definition.Category then
				QuestService.Track(player, "WinOffCategory")
			end
			CosmeticService.PlayVictory(player)
		end
		if entry.Survived and definition.Category == "Survival" then
			local seconds = math.floor(entry.Survived)
			stats.TimeSurvived += seconds
			QuestService.Track(player, "SurviveSeconds", seconds)
		end

		Economy.AddCoins(player, reward.Coins, "Round")
		Economy.AddXP(player, reward.XP)
		CosmeticService.CheckUnlocks(player)

		resultsRemote:FireClient(player, {
			GameId = definition.Id,
			Place = item.Place,
			PlayerCount = playerCount,
			ScoreText = entry.ScoreText,
			Lines = reward.Lines,
			Coins = reward.Coins,
			XP = reward.XP,
			PersonalBest = personalBest,
			Standings = standings,
			WinningTeam = winningTeam,
			MyTeam = entry.Team,
		})
		Telemetry.PlayerEvent(player, "RoundPlacement:" .. definition.Id, item.Place)
		DataService.Changed(player)
	end
end

return RewardService

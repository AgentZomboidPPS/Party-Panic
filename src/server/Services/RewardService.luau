-- Grants round rewards, updates lifetime stats and quests, and sends each player their breakdown.
-- Coins are on the low scale (owner: "I want low currency not high"): 2 for playing, up to 6.
-- The first win of each day pays a bonus, and the lifetime (career) stats feed the career
-- milestones, which ProgressionService celebrates (owner: "Also we need cool payoffs for players
-- that keep playing the game."). Every round played to the end also gives the season's crate
-- (Services/CrateService), on the results card with the rest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local DailyLogic = require(Shared.Logic.DailyLogic)
local LevelCurve = require(Shared.Logic.LevelCurve)
local Placement = require(Shared.Logic.Placement)
local ProgressionLogic = require(Shared.Logic.ProgressionLogic)
local Remotes = require(Shared.Remotes)
local RewardLogic = require(Shared.Logic.RewardLogic)

local Boosts = require(script.Parent.Boosts)
local CosmeticService = require(script.Parent.CosmeticService)
local CrateService = require(script.Parent.CrateService)
local DataService = require(script.Parent.DataService)
local Economy = require(script.Parent.Economy)
local ProgressionService = require(script.Parent.ProgressionService)
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

-- One player's rewards, stats, quests and results card (`playerCount` and `standings` are the round's).
local function grantOne(
	definition,
	item: Placement.Placed,
	playerCount: number,
	standings,
	winningTeam: string?,
	today: number
)
	local entry = item.Entry :: any
	local player: Player = entry.Player
	local profile = DataService.Get(player)
	if not profile or not player.Parent then
		return -- bots (no profile, no rewards) and anyone who just left
	end
	local data = profile.Data
	local stats = data.Stats
	local favorite = favoriteCategory(stats.CategoryPlays)
	local levelBefore = LevelCurve.FromTotalXP(data.XP)

	local personalBest = false
	if entry.BestScore ~= nil then
		local previous = stats.Best[definition.Id]
		if previous == nil or entry.BestScore > previous then
			personalBest = previous ~= nil
			stats.Best[definition.Id] = entry.BestScore
		end
	end

	-- Once a day: the day is marked as soon as it's paid, so a second win today pays no bonus.
	local firstWin = item.Place == 1 and DailyLogic.ClaimFirstWin(data.Daily, today)
	local reward = RewardLogic.ForRound({
		Place = item.Place,
		PlayerCount = playerCount,
		PersonalBest = personalBest,
		FirstWin = firstWin,
	}, Config.Rewards)
	Boosts.Apply(player, reward, { Definition = definition, Place = item.Place, PlayerCount = playerCount })

	local teamWin = winningTeam ~= nil and entry.Team ~= nil and entry.Team ~= "" and entry.Team == winningTeam
	local news = ProgressionLogic.RecordRound(stats, {
		GameId = definition.Id,
		Category = definition.Category,
		Place = item.Place,
		TopHalf = reward.IsTopHalf,
		TeamWin = teamWin,
		Survived = entry.Survived,
		Today = today,
	})

	QuestService.Track(player, "RoundPlayed")
	QuestService.Track(player, "GamePlayed", 1, definition.Id)
	if reward.IsTopHalf then
		QuestService.Track(player, "TopHalf")
	end
	if news.Podium then
		QuestService.Track(player, "Podium")
	end
	if reward.IsWinner then
		QuestService.Track(player, "Win")
		if favorite ~= nil and favorite ~= definition.Category then
			QuestService.Track(player, "WinOffCategory")
		end
		CosmeticService.PlayVictory(player)
	end
	if teamWin then
		QuestService.Track(player, "TeamWin")
	end
	if entry.Survived and definition.Category == "Survival" then
		QuestService.Track(player, "SurviveSeconds", math.floor(entry.Survived))
	end
	if firstWin then
		Telemetry.PlayerEvent(player, "FirstWinOfDay", 1, definition.Id)
	end

	Economy.AddCoins(player, reward.Coins, "Round")
	Economy.AddXP(player, reward.XP)
	ProgressionService.CheckMilestones(player)
	local levelAfter = LevelCurve.FromTotalXP(data.XP)
	-- The round's crate (the crate seasons: one for every round played to the end; Services/CrateService).
	local okCrate, crate = pcall(CrateService.RoundCrate, player)
	if not okCrate then
		Telemetry.Error("Crates", `round crate: {crate}`)
		crate = nil
	end

	resultsRemote:FireClient(player, {
		GameId = definition.Id,
		Place = item.Place,
		PlayerCount = playerCount,
		ScoreText = entry.ScoreText,
		Lines = reward.Lines,
		Coins = reward.Coins,
		XP = reward.XP,
		PersonalBest = personalBest,
		FirstWin = firstWin,
		LevelUp = if levelAfter > levelBefore then levelAfter else nil, -- the level this round (and its quests) reached
		Standings = standings,
		WinningTeam = winningTeam,
		MyTeam = entry.Team,
		Crate = crate, -- { Count, Name, Season, Total, Keys } (nil: none)
	})
	Telemetry.PlayerEvent(player, "RoundPlacement", item.Place, definition.Id)
	DataService.Changed(player)
end

-- `placed` is the output of Placement.Assign over ResultEntry values.
function RewardService.GrantRound(definition, placed: { Placement.Placed }, winningTeam: string?)
	local playerCount = #placed
	local today = DailyLogic.DayNumber(os.time())
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
		-- One player's trouble never costs the others their rewards.
		local ok, err = pcall(grantOne, definition, item, playerCount, standings, winningTeam, today)
		if not ok then
			Telemetry.Error("Rewards", `{definition.Id}: {err}`)
		end
	end
end

return RewardService

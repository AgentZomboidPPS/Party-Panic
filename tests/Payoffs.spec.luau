-- The low coin scale, the payoffs for players who keep playing (the Rewards Road, prestige colors,
-- career milestones), and checks that every reward points at something the server really keeps (a
-- stat, a quest event). The move of saved coins to the low scale: ProfileMigration.spec.
local fs = require("@lune/fs")

local TestKit = require("./TestKit")
local ProgressionLogic = require("../src/shared/Logic/ProgressionLogic")
local RewardLogic = require("../src/shared/Logic/RewardLogic")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local configSource = fs.readFile("src/shared/Config.luau")
local cosmeticsSource = fs.readFile("src/shared/Cosmetics.luau")
local questsSource = fs.readFile("src/shared/QuestDefinitions.luau")

local function configReward(key: string): { Coins: number, XP: number }
	local coins, xp = string.match(configSource, "\n\t" .. key .. " = %{ Coins = (%d+), XP = (%d+) %}")
	assert(coins and xp, `Config.Rewards.{key} not found`)
	return { Coins = tonumber(coins) :: number, XP = tonumber(xp) :: number }
end

local REWARDS = {
	Participation = configReward("Participation"),
	TopHalf = configReward("TopHalf"),
	Winner = configReward("Winner"),
	PersonalBest = configReward("PersonalBest"),
	FirstWin = configReward("FirstWin"),
}
local ROAD = {
	PerLevel = tonumber(string.match(configSource, "Config%.Road = %{ PerLevel = (%d+)")) :: number,
	Every5 = tonumber(string.match(configSource, "Every5 = (%d+)")) :: number,
	Every10 = tonumber(string.match(configSource, "Every10 = (%d+)")) :: number,
}

-- Each catalog entry's text (the top-level `{ ... },` blocks in Cosmetics.luau's list).
local items = {}
for block in string.gmatch(cosmeticsSource, "\n\t{\n(.-)\n\t},") do
	local id = string.match(block, 'Id = "([%w_]+)"')
	if id then
		items[id] = block
	end
end

test("a round pays a few coins: 2 for playing, up to 6 for a win with a personal best", function()
	local last = RewardLogic.ForRound({ Place = 12, PlayerCount = 12 }, REWARDS)
	local best = RewardLogic.ForRound({ Place = 1, PlayerCount = 12, PersonalBest = true }, REWARDS)
	expectEqual(last.Coins, 2)
	expectEqual(best.Coins, 6)
	local firstWin = RewardLogic.ForRound({ Place = 1, PlayerCount = 12, FirstWin = true }, REWARDS)
	expectTrue(firstWin.Coins <= 12, "even the first win of the day stays small")
end)

test("shop prices, quests, gifts and the road are on the same small scale", function()
	local prices = 0
	for price in string.gmatch(cosmeticsSource, "Price = (%d+)") do
		prices += 1
		local value = tonumber(price) :: number
		expectTrue(value >= 5 and value <= 300, `price {value} is outside 5-300`)
	end
	expectTrue(prices >= 15, "the shop still sells things")
	for coins in string.gmatch(questsSource, "RewardCoins = (%d+)") do
		expectTrue((tonumber(coins) :: number) <= 30, `quest reward {coins} is too big`)
	end
	local gifts = string.match(configSource, "Config%.DailyRewards = %{([^}]*)%}") :: string
	for coins in string.gmatch(gifts, "%d+") do
		expectTrue((tonumber(coins) :: number) <= 15, `daily gift {coins} is too big`)
	end
	expectTrue(ROAD.PerLevel <= 5 and ROAD.Every10 <= 20, "level-up coins stay small")
	local token = tonumber(string.match(configSource, "Config%.SecretTokenCoins = (%d+)")) :: number
	expectTrue(token <= 5, "the secret token stays small")
end)

-- Since the second shop pass (owner: "Yes lets add more items after everything else is finished")
-- the best items are something to save up for over a few evenings (Catalog.spec checks the totals).
test("pacing: a few rounds for a cheap item, a few evenings for the best one", function()
	-- An average round for an average player in an 8-player round: everyone plays, half finish in
	-- the top half, one wins, about one in ten beats their best. Round coins only (no gifts,
	-- quests or road coins, which only make it quicker).
	local perRound = REWARDS.Participation.Coins
		+ 0.5 * REWARDS.TopHalf.Coins
		+ (1 / 8) * REWARDS.Winner.Coins
		+ 0.1 * REWARDS.PersonalBest.Coins
	local prices = {}
	for price in string.gmatch(cosmeticsSource, "Price = (%d+)") do
		table.insert(prices, tonumber(price) :: number)
	end
	table.sort(prices)
	local function rounds(price: number): number
		return math.ceil(price / perRound)
	end
	local cheap, mid, top = prices[1], prices[math.ceil(#prices / 2)], prices[#prices]
	expectTrue(rounds(cheap) <= 4, `the cheapest item takes {rounds(cheap)} rounds`)
	expectTrue(rounds(mid) >= 4 and rounds(mid) <= 10, `a middle item takes {rounds(mid)} rounds`)
	expectTrue(rounds(top) >= 20 and rounds(top) <= 45, `the best item takes {rounds(top)} rounds`)
end)

test("the Rewards Road pays every level once, more every 5th and 10th", function()
	expectEqual(ProgressionLogic.LevelCoins(1, ROAD), 0)
	expectEqual(ProgressionLogic.LevelCoins(2, ROAD), ROAD.PerLevel)
	expectEqual(ProgressionLogic.LevelCoins(5, ROAD), ROAD.Every5)
	expectEqual(ProgressionLogic.LevelCoins(10, ROAD), ROAD.Every10)
	expectEqual(ProgressionLogic.CoinsBetween(1, 2, ROAD), ROAD.PerLevel)
	expectEqual(ProgressionLogic.CoinsBetween(1, 10, ROAD), 7 * ROAD.PerLevel + ROAD.Every5 + ROAD.Every10)
	-- Two levels at once pay both; no level change pays nothing.
	expectEqual(ProgressionLogic.CoinsBetween(8, 10, ROAD), ROAD.PerLevel + ROAD.Every10)
	expectEqual(ProgressionLogic.CoinsBetween(7, 7, ROAD), 0)
	expectEqual(ProgressionLogic.CoinsBetween(9, 3, ROAD), 0)
	-- Climbing in steps pays the same as one jump (each level once).
	local steps = 0
	for from = 1, 29 do
		steps += ProgressionLogic.CoinsBetween(from, from + 1, ROAD)
	end
	expectEqual(steps, ProgressionLogic.CoinsBetween(1, 30, ROAD))
end)

test("the road has an exclusive reward in the first levels and at every milestone to 50", function()
	local levels = {}
	for level in string.gmatch(cosmeticsSource, "UnlockLevel = (%d+)") do
		levels[tonumber(level) :: number] = true
	end
	expectTrue(levels[2] and levels[3], "something new in the first few rounds")
	for level = 5, 50, 5 do
		expectTrue(levels[level], `level {level} has no exclusive reward`)
	end
end)

test("rewards nobody can buy have no price", function()
	local exclusive = 0
	for id, block in items do
		if string.find(block, "UnlockLevel =", 1, true) or string.find(block, "UnlockStat =", 1, true) then
			exclusive += 1
			expectTrue(not string.find(block, "Price =", 1, true), `{id} is a reward but has a Price`)
		end
	end
	expectTrue(exclusive >= 25, "the road and the career have their rewards")
end)

test("prestige colors change every 10 levels up to 50", function()
	expectEqual(ProgressionLogic.TierIndex(1), 1)
	expectEqual(ProgressionLogic.TierIndex(9), 1)
	expectEqual(ProgressionLogic.TierIndex(10), 2)
	expectEqual(ProgressionLogic.TierIndex(29), 3)
	expectEqual(ProgressionLogic.TierIndex(50), #ProgressionLogic.Tiers)
	expectEqual(ProgressionLogic.TierIndex(100), #ProgressionLogic.Tiers)
	expectEqual((ProgressionLogic.NextTier(9) :: any).Level, 10)
	expectEqual(ProgressionLogic.NextTier(60), nil)
	for index, tier in ProgressionLogic.Tiers do
		expectTrue(#tier.Colors >= 2 and #tier.Text == 3, `tier {index} has its colors`)
	end
end)

test("RecordRound keeps the career stats", function()
	local stats: { [string]: any } = { Wins = 0 }
	local news = ProgressionLogic.RecordRound(stats, {
		GameId = "SkateEscape",
		Category = "Race",
		Place = 2,
		TopHalf = true,
		Today = 100,
	})
	expectEqual(news, { Podium = true, NewGame = true, NewDay = true })
	expectEqual(stats.RoundsPlayed, 1)
	expectEqual(stats.GamesTried, 1)
	expectEqual(stats.Podiums, 1)
	expectEqual(stats.RacePodiums, 1)
	expectEqual(stats.TopHalf, 1)
	expectEqual(stats.Wins, 0)
	expectEqual(stats.DaysPlayed, 1)

	-- Same game, same day: not new. A survival win on a team counts as a win, a survival win and a team win.
	news = ProgressionLogic.RecordRound(stats, {
		GameId = "SkateEscape",
		Category = "Survival",
		Place = 1,
		TopHalf = true,
		TeamWin = true,
		Survived = 41.7,
		Today = 100,
	})
	expectEqual(news, { Podium = true, NewGame = false, NewDay = false })
	expectEqual(stats.GamesTried, 1)
	expectEqual(stats.Wins, 1)
	expectEqual(stats.SurvivalWins, 1)
	expectEqual(stats.TeamWins, 1)
	expectEqual(stats.TimeSurvived, 41)
	expectEqual(stats.DaysPlayed, 1)

	-- Another game the next day: a new game and a new day; 9th place isn't a podium.
	news = ProgressionLogic.RecordRound(stats, {
		GameId = "FireRope",
		Category = "Survival",
		Place = 9,
		TopHalf = false,
		Today = 101,
	})
	expectEqual(news, { Podium = false, NewGame = true, NewDay = true })
	expectEqual(stats.GamesTried, 2)
	expectEqual(stats.DaysPlayed, 2)
	expectEqual(stats.Podiums, 2)
	expectEqual(stats.RoundsPlayed, 3)
	expectEqual(stats.ModePlays, { SkateEscape = 2, FireRope = 1 })
	expectEqual(stats.CategoryPlays, { Race = 1, Survival = 2 })
end)

test("race podiums: SKATE ESCAPE (the Race category) and BOBSLED RUN (a team race) count", function()
	local stats: { [string]: any } = {}
	ProgressionLogic.RecordRound(
		stats,
		{ GameId = "BobsledRun", Category = "Team", Place = 1, TopHalf = true, Today = 1 }
	)
	ProgressionLogic.RecordRound(
		stats,
		{ GameId = "SkateEscape", Category = "Race", Place = 3, TopHalf = true, Today = 1 }
	)
	ProgressionLogic.RecordRound(
		stats,
		{ GameId = "BobsledRun", Category = "Team", Place = 7, TopHalf = false, Today = 1 }
	)
	ProgressionLogic.RecordRound(
		stats,
		{ GameId = "CakeFactory", Category = "Team", Place = 1, TopHalf = true, Today = 1 }
	)
	expectEqual(stats.RacePodiums, 2, "the losing sled and a non-race win don't count")
	expectEqual(stats.Podiums, 3)
	local games = fs.readFile("src/shared/GameDefinitions.luau")
	for id in ProgressionLogic.RaceGames do
		expectTrue(string.find(games, `Id = "{id}"`, 1, true) ~= nil, `{id} is a game`)
	end
end)

test("every career milestone is a stat the server keeps", function()
	local stats: { [string]: any } = {}
	local kept = {}
	for _, record in
		{
			{ GameId = "A", Category = "Race", Place = 1, TopHalf = true, TeamWin = true, Survived = 5, Today = 1 },
			{ GameId = "B", Category = "Survival", Place = 1, TopHalf = true, Survived = 5, Today = 2 },
		}
	do
		ProgressionLogic.RecordRound(stats, record)
	end
	for key in stats do
		kept[key] = true
	end
	local count = 0
	for stat in string.gmatch(cosmeticsSource, 'UnlockStat = %{ Stat = "(%w+)"') do
		count += 1
		expectTrue(kept[stat], `a cosmetic unlocks with {stat}, which no round ever adds to`)
	end
	expectTrue(count >= 10, "the career milestones are there")
end)

test("every quest event is one the server reports", function()
	local tracked = {}
	local function scan(folder: string)
		for _, name in fs.readDir(folder) do
			local path = `{folder}/{name}`
			if fs.isDir(path) then
				scan(path)
			elseif string.match(name, "%.luau$") then
				for event in string.gmatch(fs.readFile(path), 'QuestService%.Track%(player, "(%w+)"') do
					tracked[event] = true
				end
			end
		end
	end
	scan("src/server")
	for event in string.gmatch(questsSource, 'Event = "(%w+)"') do
		expectTrue(tracked[event], `a quest waits for "{event}", which the server never reports`)
	end
end)

return nil

-- Saved profiles moving to the low coin scale (owner: "Also lets balance the shop down. I want low
-- currency not high."): exactly once, nothing lost, run the way DataService runs it (Load on every
-- profile loaded from the DataStore, Stamp in every save), including a player whose last game was
-- on a server still running the old code (live version 30) before the servers were restarted.
local TestKit = require("./TestKit")
local ProfileMigration = require("../src/shared/Logic/ProfileMigration")
local ProfileTemplate = require("../src/shared/Logic/ProfileTemplate")
local TableUtil = require("../src/shared/Logic/TableUtil")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue
local copy = TableUtil.DeepCopy

local GAMES = { FireRope = true, HexMeltdown = true, HoneyTrap = true }

-- What loading does on this code (DataService.migrate): returns the profile and the report.
local function load(stored: any): (any, ProfileMigration.Report)
	local data = copy(stored) -- a DataStore read is always a fresh copy
	local report = ProfileMigration.Load(data, ProfileTemplate, TableUtil.Reconcile, GAMES)
	return data, report
end

-- What a save on this code writes (DataService.saveRecord): the stamp, then the copy stored.
local function save(data: any): any
	ProfileMigration.Stamp(data)
	return copy(data)
end

-- The template live version 30 runs with: Version 1, no low-scale mark, no career stats.
local OLD_TEMPLATE = copy(ProfileTemplate) :: any
OLD_TEMPLATE.Version = 1
OLD_TEMPLATE.EconomyVersion = nil
for _, key in { "Podiums", "TeamWins", "RacePodiums", "GamesTried", "DaysPlayed", "LastPlayDay" } do
	OLD_TEMPLATE.Stats[key] = nil
end
OLD_TEMPLATE.Daily.FirstWinDay = nil

-- A session on a server still running version 30: its load (Reconcile, Version = 1), the coins it
-- pays or spends (old scale), its save (no stamp: it doesn't know about it).
local function oldServerSession(stored: any, coinChange: number, buy: string?): any
	local data = copy(stored)
	TableUtil.Reconcile(data, OLD_TEMPLATE)
	data.Version = OLD_TEMPLATE.Version
	data.Coins += coinChange
	if buy then
		data.Owned[buy] = true
	end
	return copy(data)
end

-- A veteran's save from before the update (live version 30's shape).
local function veteran(coins: any): any
	local data = copy(OLD_TEMPLATE)
	data.Coins = coins
	data.XP = 5400
	data.Owned = { Title_Rookie = true, Emote_Wave = true, Trail_Fire = true, Title_ChaosChampion = true }
	data.Equipped.Trail = "Trail_Fire"
	data.Equipped.Title = "Title_ChaosChampion"
	data.Stats.RoundsPlayed = 61
	data.Stats.Wins = 7
	data.Stats.ModePlays = { FireRope = 30, HexMeltdown = 31, RetiredMode = 4 }
	data.Daily.Streak = 3
	return data
end

test("the template is this code's: Version and EconomyVersion match ProfileMigration", function()
	expectEqual(ProfileTemplate.Version, ProfileMigration.SchemaVersion)
	expectEqual(ProfileTemplate.EconomyVersion, ProfileMigration.EconomyVersion)
	expectEqual((ProfileTemplate :: any).CoinStamp, nil, "the stamp is never a default (it would look like a real one)")
end)

test("a veteran's coins move to the low scale once; items, levels and stats stay", function()
	local stored = veteran(1234)
	local data, report = load(stored)
	expectEqual(report, { CoinsBefore = 1234, CoinsAfter = 124 })
	expectEqual(data.Coins, 124, "1234 old coins round up to 124")
	expectEqual(data.EconomyVersion, 2)
	expectEqual(data.Version, 2)
	expectEqual(data.XP, 5400, "XP and levels are unchanged")
	expectEqual(data.Owned, stored.Owned, "every item they bought stays theirs")
	expectEqual(data.Equipped, stored.Equipped, "and stays equipped")
	expectEqual(data.Stats.RoundsPlayed, 61)
	expectEqual(data.Stats.Wins, 7)
	expectEqual(data.Stats.Podiums, 7, "every saved win was a podium")
	expectEqual(data.Stats.DaysPlayed, 0, "the other career counts start now")
	expectEqual(data.Stats.GamesTried, 2, "only games that are in the game count")
	expectEqual(data.Daily.Streak, 3)
	expectEqual(data.Daily.FirstWinDay, 0, "new fields get their defaults")

	-- Saved, then loaded again (another server, the next day): nothing changes any more.
	local again, second = load(save(data))
	expectEqual(second, {})
	expectEqual(again.Coins, 124)
	expectEqual(again.Owned, stored.Owned)
	-- A load that's never saved (the server went down) leaves the store as it was: the next load
	-- converts from the same saved balance, to the same result.
	local retry = load(stored)
	expectEqual(retry.Coins, 124)
end)

test("the conversion rounds up and never goes below zero", function()
	local cases = {
		{ 0, 0 },
		{ 1, 1 },
		{ 9, 1 },
		{ 10, 1 },
		{ 11, 2 },
		{ 155, 16 },
		{ 99999, 10000 },
		{ 2 ^ 40, math.ceil(2 ^ 40 / 10) },
		{ 1e15, 1e14 },
		{ 12.9, 2 },
		{ "250", 25 },
		{ -5, 0 },
		{ 0 / 0, 0 },
		{ math.huge, 0 },
		{ true, 0 },
	}
	for _, case in cases do
		local data = load(veteran(case[1]))
		expectEqual(data.Coins, case[2], `{tostring(case[1])} old coins`)
		expectEqual(data.EconomyVersion, 2)
	end
end)

test("missing fields: an empty or partial save still converts and gets every default", function()
	local empty, report = load({})
	expectEqual(empty.Coins, 0)
	expectEqual(report, { CoinsBefore = 0, CoinsAfter = 0 })
	expectEqual(empty.EconomyVersion, 2)
	expectEqual(empty.Version, 2)
	expectEqual(empty.Equipped, ProfileTemplate.Equipped)
	expectEqual(empty.Stats.Podiums, 0)

	local partial = load({ Coins = 77, Owned = { Trail_Rainbow = true } })
	expectEqual(partial.Coins, 8)
	expectEqual(partial.Owned, { Trail_Rainbow = true })
	expectEqual(partial.Stats.ModePlays, {})
	expectEqual(partial.Quests.Daily, { Number = 0, Active = {} })

	local fewStats = load({ Version = 1, Coins = 40, Stats = { Wins = 3 } })
	expectEqual(fewStats.Coins, 4)
	expectEqual(fewStats.Stats.Podiums, 3)
	expectEqual(fewStats.Stats.RoundsPlayed, 0)
end)

test("a new profile (on the low scale from the start) is never converted", function()
	local fresh = copy(ProfileTemplate) :: any
	fresh.Coins = 37
	fresh.Stats.Wins = 3
	fresh.Stats.Podiums = 1
	local data, report = load(save(fresh))
	expectEqual(report, {})
	expectEqual(data.Coins, 37)
	expectEqual(data.Stats.Podiums, 1, "a profile on the new scale keeps its own podium count")
	-- Not even before its first save (no stamp yet).
	local unsaved, unsavedReport = load(fresh)
	expectEqual(unsavedReport, {})
	expectEqual(unsaved.Coins, 37)
end)

test("a game on a server still running the old code: what it paid moves to the low scale too", function()
	local converted = save((load(veteran(1234))))
	expectEqual(converted.CoinStamp, 124)

	-- Played rounds there (old scale: +20 a round, +25 a level): 124 + 230 = 354.
	local afterOld = oldServerSession(converted, 230)
	expectEqual(afterOld.Version, 1, "the old code writes Version 1 back")
	expectEqual(afterOld.EconomyVersion, 2, "and keeps the mark it doesn't know about")
	local data, report = load(afterOld)
	expectEqual(data.Coins, 124 + 23)
	expectEqual(report, { OldServerChange = 230, OldServerAfter = 147 })
	expectEqual(data.Version, 2)

	-- Never twice: saved by this code, loaded again.
	local again, second = load(save(data))
	expectEqual(second, {})
	expectEqual(again.Coins, 147)
end)

test("old-server games: a purchase there stays owned, two games in a row count once each", function()
	local converted = save((load(veteran(1234)))) -- 124 coins
	-- Earned 160 and bought a 250 item at the old price: 124 + 160 - 250 = 34 (old scale -90).
	local bought = oldServerSession(converted, 160 - 250, "Trail_Rainbow")
	local data = load(bought)
	expectEqual(data.Coins, 124 - 9)
	expectTrue(data.Owned.Trail_Rainbow, "the item bought there is theirs")

	-- Two old-server games before coming back: both count, once.
	local twice = oldServerSession(oldServerSession(converted, 40), 60)
	expectEqual((load(twice)).Coins, 124 + 10)

	-- An old-server game where nothing was earned changes nothing.
	local idle, idleReport = load(oldServerSession(converted, 0))
	expectEqual(idle.Coins, 124)
	expectEqual(idleReport, {})

	-- Spent all 124 there, at old prices: that was worth 12 coins on the low scale.
	expectEqual((load(oldServerSession(converted, -124))).Coins, 112)
end)

test("an old save with no stamp is never rescaled again, whatever its Version says", function()
	local marked = { Version = 1, EconomyVersion = 2, Coins = 500 }
	local data, report = load(marked)
	expectEqual(report, {})
	expectEqual(data.Coins, 500)
end)

test("Version is never lowered, and the stamp is the saved balance", function()
	local newer = copy(ProfileTemplate) :: any
	newer.Version = 5
	newer.Coins = 12
	local data = load(newer)
	expectEqual(data.Version, 5)
	local written = save(data)
	expectEqual(written.CoinStamp, 12)
	expectEqual(written.Coins, 12)
end)

test("GamesTried counts the games played that are in the game", function()
	expectEqual(ProfileMigration.GamesTried({ FireRope = 2, HoneyTrap = 0, Gone = 9 }, GAMES), 1)
	expectEqual(ProfileMigration.GamesTried({ FireRope = 2, Gone = 9 }), 2)
	expectEqual(ProfileMigration.GamesTried(nil, GAMES), 0)
	expectEqual(ProfileMigration.GamesTried("broken", GAMES), 0)
end)

return nil

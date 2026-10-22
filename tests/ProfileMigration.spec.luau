-- Saved profiles moving to the low coin scale (owner: "Also lets balance the shop down. I want low
-- currency not high."): exactly once, nothing lost, run the way DataService runs it (Load on every
-- profile loaded from the DataStore, Stamp in every save), including a player whose last game was
-- on a server still running the old code (live version 30) before the servers were restarted.
-- The GOLD PASS (owner: "Also we do need a paid battle pass too. I like the current free one. But the
-- paid one should also be insane."), which took the old VIP pass's place: its ownership is kept in the
-- profile now (the VIP flag never was), so the field must load safely and never grant the pass.
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
OLD_TEMPLATE.GoldPass = nil -- (older code has never heard of the GOLD PASS)

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

test("the player is told about their coins even if they leave before the message shows", function()
	expectEqual((ProfileTemplate :: any).Meta.CoinNotice, nil, "never a default")
	local data, report = load(veteran(1234))
	expectEqual(report, { CoinsBefore = 1234, CoinsAfter = 124 })
	expectEqual(data.Meta.CoinNotice, { Kind = "Converted", Before = 1234, After = 124 })

	-- They left before it showed (the note was saved): it's still waiting on the next load,
	-- although nothing converts again.
	local again, second = load(save(data))
	expectEqual(second, {})
	expectEqual(again.Meta.CoinNotice, { Kind = "Converted", Before = 1234, After = 124 })

	-- Told (DataService clears it once the message was sent), saved: gone for good.
	again.Meta.CoinNotice = nil
	local told = load(save(again))
	expectEqual(told.Meta.CoinNotice, nil)

	-- A game on an old server after that: its own note.
	local hop = load(oldServerSession(save(told), 230))
	expectEqual(hop.Coins, 124 + 23)
	expectEqual(hop.Meta.CoinNotice, { Kind = "OldServer", After = 147 })

	-- Still not told about the conversion when an old-server game comes in: the conversion's note
	-- stays (it's the one that matters), with the conversion's numbers.
	local pending = load(oldServerSession(save(data), 100))
	expectEqual(pending.Coins, 124 + 10)
	expectEqual(pending.Meta.CoinNotice, { Kind = "Converted", Before = 1234, After = 124 })

	-- No coins, nothing to say.
	expectEqual((load(veteran(0))).Meta.CoinNotice, nil)
	expectEqual((load(save(copy(ProfileTemplate)))).Meta.CoinNotice, nil)
end)

local NO_PASS = { Owned = false, Since = 0, CoinsTo = 1 }

test("a save from before the GOLD PASS gets it as not owned, and nothing else changes", function()
	-- Live version 30's shape (old coin scale) and a later one on the low scale, before the pass.
	local data = load(veteran(1234))
	expectEqual(data.GoldPass, NO_PASS)
	expectEqual(data.Coins, 124, "the coins move as they always did")
	local lowScale = save(data)
	lowScale.GoldPass = nil
	local again, report = load(lowScale)
	expectEqual(report, {})
	expectEqual(again.GoldPass, NO_PASS)
	expectEqual(again.Coins, 124)
	expectEqual(again.Owned, data.Owned)
	expectEqual(again.Version, ProfileMigration.SchemaVersion, "no new Version for a new field")
	expectEqual(ProfileTemplate.GoldPass, NO_PASS, "a new player doesn't own it")
end)

test("an owner's GOLD PASS survives saves, loads and a game on a server running older code", function()
	local data = load(save(copy(ProfileTemplate)))
	data.GoldPass = { Owned = true, Since = 1761100000, CoinsTo = 30 }
	data.Owned.Hat_RoyalCrown = true
	local again = load(save(data))
	expectEqual(again.GoldPass, { Owned = true, Since = 1761100000, CoinsTo = 30 })
	-- A game on a server still running older code (before the pass): it keeps the field it doesn't
	-- know, so the pass is still theirs back here; the levels reached there pay their gold coins on
	-- the next join (CoinsTo is still 30: Services/GoldPassService catches up).
	local afterOld = oldServerSession(save(again), 0)
	expectEqual(afterOld.GoldPass, { Owned = true, Since = 1761100000, CoinsTo = 30 })
	local back = load(afterOld)
	expectEqual(back.GoldPass, { Owned = true, Since = 1761100000, CoinsTo = 30 })
	expectTrue(back.Owned.Hat_RoyalCrown, "its rewards stay theirs")
end)

test("loading never grants the GOLD PASS: anything but a real true is not owned", function()
	for _, value in { "true", 1, 0, {}, "yes", false } do
		local data = load({ EconomyVersion = 2, GoldPass = { Owned = value } })
		expectEqual(data.GoldPass.Owned, false, `Owned = {tostring(value)}`)
	end
	local real = load({ EconomyVersion = 2, GoldPass = { Owned = true, Since = 5, CoinsTo = 40 } })
	expectEqual(real.GoldPass, { Owned = true, Since = 5, CoinsTo = 40 })
	-- A field that isn't a table at all: the default.
	for _, broken in { 5, "Owned", true } do
		expectEqual((load({ EconomyVersion = 2, GoldPass = broken })).GoldPass, NO_PASS, tostring(broken))
	end
end)

test("the GOLD PASS's last paid level is a whole level, at least 1; its date is never negative", function()
	local cases = {
		{ -5, 1 },
		{ 0, 1 },
		{ 12.7, 12 },
		{ "40", 40 },
		{ 0 / 0, 1 },
		{ math.huge, 1 },
		{ "lots", 1 },
		{ 100, 100 },
	}
	for _, case in cases do
		local data = load({ EconomyVersion = 2, GoldPass = { Owned = true, CoinsTo = case[1] } })
		expectEqual(data.GoldPass.CoinsTo, case[2], `CoinsTo {tostring(case[1])}`)
	end
	for _, since in { -3, 0 / 0, "soon", math.huge } do
		local data = load({ EconomyVersion = 2, GoldPass = { Owned = true, Since = since } })
		expectEqual(data.GoldPass.Since, 0, `Since {tostring(since)}`)
	end
end)

test("the old VIP flag means nothing: a stray IsVip in a save is dropped and grants nothing", function()
	local data = load({ EconomyVersion = 2, IsVip = true })
	expectEqual(data.IsVip, nil)
	expectEqual(data.GoldPass, NO_PASS)
	-- Owning the two old VIP items (gold rewards now) doesn't make anyone an owner either.
	local items = load({ EconomyVersion = 2, Owned = { Trail_VIP = true, Title_VIP = true } })
	expectEqual(items.GoldPass.Owned, false)
	expectTrue(items.Owned.Trail_VIP and items.Owned.Title_VIP, "but they keep them")
end)

test("what newer code keeps in the GOLD PASS field stays", function()
	local data = load({ EconomyVersion = 2, GoldPass = { Owned = true, CoinsTo = 3, Seen = 7 } })
	expectEqual(data.GoldPass, { Owned = true, Since = 0, CoinsTo = 3, Seen = 7 })
end)

test("GamesTried counts the games played that are in the game", function()
	expectEqual(ProfileMigration.GamesTried({ FireRope = 2, HoneyTrap = 0, Gone = 9 }, GAMES), 1)
	expectEqual(ProfileMigration.GamesTried({ FireRope = 2, Gone = 9 }), 2)
	expectEqual(ProfileMigration.GamesTried(nil, GAMES), 0)
	expectEqual(ProfileMigration.GamesTried("broken", GAMES), 0)
end)

return nil

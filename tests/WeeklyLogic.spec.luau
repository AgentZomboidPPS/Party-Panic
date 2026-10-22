local TestKit = require("./TestKit")
local DailyLogic = require("../src/shared/Logic/DailyLogic")
local WeeklyLogic = require("../src/shared/Logic/WeeklyLogic")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

-- 2026-10-19 00:00 UTC, a Monday.
local MONDAY = 1792368000

test("WeeklyLogic.PointsFor: 1st 10, 2nd 7, 3rd 5, anyone else who played 1", function()
	expectEqual(WeeklyLogic.PointsFor(1, 12), 10)
	expectEqual(WeeklyLogic.PointsFor(2, 12), 7)
	expectEqual(WeeklyLogic.PointsFor(3, 12), 5)
	expectEqual(WeeklyLogic.PointsFor(4, 12), 1)
	expectEqual(WeeklyLogic.PointsFor(12, 12), 1)
	-- Tied places pay alike (a team that wins shares 1st).
	expectEqual(WeeklyLogic.PointsFor(1, 7), 10)
	expectEqual(WeeklyLogic.RulesText(), "1ST 10 · 2ND 7 · 3RD 5 · PLAYING 1")
end)

test("WeeklyLogic.PointsFor: a podium place only pays when someone finished below it", function()
	expectEqual(WeeklyLogic.PointsFor(1, 1), 1, "alone in a round")
	expectEqual(WeeklyLogic.PointsFor(1, 2), 10)
	expectEqual(WeeklyLogic.PointsFor(2, 2), 1, "last of two")
	expectEqual(WeeklyLogic.PointsFor(3, 3), 1, "last of three")
end)

test("WeeklyLogic weeks start on Monday 00:00 UTC, as DailyLogic numbers them", function()
	local week = DailyLogic.WeekNumber(MONDAY)
	expectEqual(WeeklyLogic.WeekStart(week), MONDAY)
	expectEqual(DailyLogic.WeekNumber(MONDAY - 1), week - 1, "Sunday 23:59:59 is the week before")
	expectEqual(WeeklyLogic.WeekEnd(week), MONDAY + 7 * 86400)
	expectEqual(DailyLogic.WeekNumber(WeeklyLogic.WeekEnd(week) - 1), week)
	expectEqual(DailyLogic.WeekNumber(WeeklyLogic.WeekEnd(week)), week + 1)
	for _, w in { 1, 100, 2900, 2961 } do
		expectEqual(DailyLogic.WeekNumber(WeeklyLogic.WeekStart(w)), w, `week {w} starts in week {w}`)
		expectEqual(DailyLogic.WeekNumber(WeeklyLogic.WeekStart(w) - 1), w - 1, `week {w} - 1 ends before it`)
	end
	expectTrue(not WeeklyLogic.Settled(week - 1, MONDAY + 599, 600), "10 minutes to settle")
	expectTrue(WeeklyLogic.Settled(week - 1, MONDAY + 600, 600))
end)

test("WeeklyLogic.ResetsIn reads like the board says it", function()
	expectEqual(WeeklyLogic.ResetsIn(2 * 86400 + 5 * 3600 + 10), "2D 5H")
	expectEqual(WeeklyLogic.ResetsIn(7 * 86400), "7D 0H")
	expectEqual(WeeklyLogic.ResetsIn(5 * 3600 + 12 * 60), "5H 12M")
	expectEqual(WeeklyLogic.ResetsIn(12 * 60), "12M")
	expectEqual(WeeklyLogic.ResetsIn(59 * 60 + 1), "1H 0M")
	expectEqual(WeeklyLogic.ResetsIn(0), "1M")
	expectEqual(WeeklyLogic.ResetsIn(-30), "1M")
end)

test("WeeklyLogic.Add: points add up within a week and start from 0 in the next one", function()
	local week = DailyLogic.WeekNumber(MONDAY)
	local weekly: WeeklyLogic.Weekly = { Week = 0, Points = 0 } -- a save from before the leaderboard
	expectEqual({ WeeklyLogic.Add(weekly, week, 10) }, { week, 10 })
	expectEqual({ WeeklyLogic.Add(weekly, week, 1) }, { week, 11 })
	expectEqual(weekly.Pending, nil, "week 0 is nothing to check")
	expectEqual({ WeeklyLogic.Add(weekly, week + 1, 7) }, { week + 1, 7 })
	expectEqual(weekly.Pending, { week }, "the week they scored in waits for its top-three check")
	-- A server whose clock is a moment behind adds to the player's own (newer) week.
	expectEqual({ WeeklyLogic.Add(weekly, week, 5) }, { week + 1, 12 })
	expectEqual(weekly.Pending, { week })
end)

test("WeeklyLogic.Roll: a new week resets the points; a week without points isn't remembered", function()
	local weekly: WeeklyLogic.Weekly = { Week = 100, Points = 0 }
	expectTrue(WeeklyLogic.Roll(weekly, 101))
	expectEqual(weekly, { Week = 101, Points = 0 })
	expectTrue(not WeeklyLogic.Roll(weekly, 101), "same week: nothing to do")
	expectTrue(not WeeklyLogic.Roll(weekly, 99), "an earlier week never rolls back")
	weekly.Points = 40
	expectTrue(WeeklyLogic.Roll(weekly, 105), "weeks away: straight to the new one")
	expectEqual(weekly, { Week = 105, Points = 0, Pending = { 101 } })
	-- At most PendingKept weeks wait (the oldest go first).
	for week = 106, 110 do
		weekly.Points = 3
		WeeklyLogic.Roll(weekly, week)
	end
	expectEqual(weekly.Pending, { 107, 108, 109 })
	expectTrue(WeeklyLogic.ClearPending(weekly, 108))
	expectTrue(not WeeklyLogic.ClearPending(weekly, 108))
	expectEqual(weekly.Pending, { 107, 109 })
	WeeklyLogic.ClearPending(weekly, 107)
	WeeklyLogic.ClearPending(weekly, 109)
	expectEqual(weekly.Pending, nil, "an empty list goes")
end)

test("WeeklyLogic.Standings: the store's board merged with this server's newer points", function()
	local stored = {
		{ UserId = 5, Points = 90 },
		{ UserId = 3, Points = 40 },
		{ UserId = 9, Points = 40 },
		{ UserId = 7, Points = 12 },
	}
	local live = {
		{ UserId = 7, Points = 50, Name = "Ann" }, -- played since the store was read
		{ UserId = 3, Points = 30, Name = "Bo" }, -- the store is never ahead; the higher number wins
		{ UserId = 11, Points = 2, Name = "Cy" }, -- new this week
		{ UserId = -4, Points = 99, Name = "🤖 Mochi" }, -- a bot is never on the board
		{ UserId = 12, Points = 0, Name = "Di" }, -- no points yet: not on the board
	}
	local standings = WeeklyLogic.Standings(stored, live, 100)
	local rows = {}
	for _, entry in standings do
		table.insert(rows, `{entry.Rank}:{entry.UserId}:{entry.Points}:{entry.Name or "?"}`)
	end
	expectEqual(rows, { "1:5:90:?", "2:7:50:Ann", "3:3:40:Bo", "4:9:40:?", "5:11:2:Cy" })
	expectEqual(WeeklyLogic.RankOf(standings, 11), 5)
	expectEqual(WeeklyLogic.RankOf(standings, 12), nil)
	expectEqual(#WeeklyLogic.Top(standings, 3), 3)
	expectEqual(WeeklyLogic.Top(standings, 3)[3].UserId, 3, "ties go to the lower UserId")
end)

test("WeeklyLogic.Standings: below a full page of the store, a player's place isn't known", function()
	local stored = { { UserId = 1, Points = 50 }, { UserId = 2, Points = 30 } } -- a page of 2: the store may hold more
	local live = { { UserId = 8, Points = 40 }, { UserId = 9, Points = 20 }, { UserId = 2, Points = 35 } }
	local standings = WeeklyLogic.Standings(stored, live, 2)
	local ids = {}
	for _, entry in standings do
		table.insert(ids, entry.UserId)
	end
	expectEqual(ids, { 1, 8, 2 }, "9 (20, under the page's 30) could be anywhere below it")
	-- With room to spare on the page, the store held everyone: every player has a place.
	expectEqual(#WeeklyLogic.Standings(stored, live, 100), 4)
end)

test("WeeklyLogic words: the YOU line, the chip, points and places", function()
	expectEqual(WeeklyLogic.YouLine(14, 35), "YOU: #14 · 35 PTS")
	expectEqual(WeeklyLogic.YouLine(nil, 35), "YOU: 35 PTS")
	expectEqual(WeeklyLogic.YouLine(3, 1), "YOU: #3 · 1 PT")
	expectEqual(WeeklyLogic.YouLine(nil, 0), "Play a round to get on the board")
	expectEqual(WeeklyLogic.ChipText(14, 35), "#14 THIS WEEK")
	expectEqual(WeeklyLogic.ChipText(nil, 35), "WEEKLY TOP 10")
	expectEqual(WeeklyLogic.ChipText(2, 0), "WEEKLY TOP 10")
	expectEqual(WeeklyLogic.Ordinal(1), "1ST")
	expectEqual(WeeklyLogic.Ordinal(2), "2ND")
	expectEqual(WeeklyLogic.Ordinal(3), "3RD")
	expectEqual(WeeklyLogic.Ordinal(11), "11TH")
	expectEqual(WeeklyLogic.Ordinal(22), "22ND")
end)

local TestKit = require("./TestKit")
local DailyLogic = require("../src/shared/Logic/DailyLogic")
local LevelCurve = require("../src/shared/Logic/LevelCurve")
local Placement = require("../src/shared/Logic/Placement")
local QuestLogic = require("../src/shared/Logic/QuestLogic")
local RewardLogic = require("../src/shared/Logic/RewardLogic")
local TableUtil = require("../src/shared/Logic/TableUtil")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

-- The low coin scale (Config.Rewards): 2 coins for playing, up to 6 for a win with a personal best.
local REWARDS = {
	Participation = { Coins = 2, XP = 25 },
	TopHalf = { Coins = 1, XP = 10 },
	Winner = { Coins = 2, XP = 20 },
	PersonalBest = { Coins = 1, XP = 5 },
	FirstWin = { Coins = 5, XP = 50 },
}

test("Placement.Assign ranks by value with shared places for ties", function()
	local placed = Placement.Assign({
		{ Key = "a", Rank = 10 },
		{ Key = "b", Rank = 30 },
		{ Key = "c", Rank = 30 },
		{ Key = "d", Rank = 5 },
	})
	local places = {}
	for _, item in placed do
		places[item.Key] = item.Place
	end
	expectEqual(places, { a = 3, b = 1, c = 1, d = 4 })
	expectEqual(placed[1].Key, "b", "stable order for ties")
end)

test("Placement.IsTopHalf and Ordinal", function()
	expectTrue(Placement.IsTopHalf(1, 1))
	expectTrue(Placement.IsTopHalf(2, 3))
	expectEqual(Placement.IsTopHalf(3, 4), false)
	expectEqual(Placement.Ordinal(1), "1st")
	expectEqual(Placement.Ordinal(2), "2nd")
	expectEqual(Placement.Ordinal(3), "3rd")
	expectEqual(Placement.Ordinal(11), "11th")
	expectEqual(Placement.Ordinal(22), "22nd")
end)

test("RewardLogic gives everyone participation and stacks bonuses", function()
	local last = RewardLogic.ForRound({ Place = 8, PlayerCount = 8 }, REWARDS)
	expectEqual(last.Coins, 2)
	expectEqual(#last.Lines, 1)
	expectEqual(last.IsWinner, false)

	local winner = RewardLogic.ForRound({ Place = 1, PlayerCount = 8, PersonalBest = true }, REWARDS)
	expectEqual(winner.Coins, 2 + 1 + 2 + 1)
	expectEqual(winner.XP, 25 + 10 + 20 + 5)
	expectEqual(#winner.Lines, 4)
	expectTrue(winner.IsWinner and winner.IsTopHalf)

	local middle = RewardLogic.ForRound({ Place = 4, PlayerCount = 8 }, REWARDS)
	expectEqual(middle.Coins, 3)
end)

test("RewardLogic pays the first win of the day as its own line, only for a win", function()
	local first = RewardLogic.ForRound({ Place = 1, PlayerCount = 8, FirstWin = true }, REWARDS)
	expectEqual(first.Coins, 2 + 1 + 2 + 5)
	expectEqual(first.XP, 25 + 10 + 20 + 50)
	expectEqual(first.Lines[#first.Lines].Label, "First win today!")

	local second = RewardLogic.ForRound({ Place = 2, PlayerCount = 8, FirstWin = true }, REWARDS)
	expectEqual(second.Coins, 3, "no bonus without a win")
	expectEqual(#second.Lines, 2)

	local without = RewardLogic.ForRound({ Place = 1, PlayerCount = 8, FirstWin = true }, {
		Participation = REWARDS.Participation,
		TopHalf = REWARDS.TopHalf,
		Winner = REWARDS.Winner,
		PersonalBest = REWARDS.PersonalBest,
	})
	expectEqual(without.Coins, 5, "a reward table without FirstWin pays no bonus")
end)

test("LevelCurve converts total XP into level progress", function()
	expectEqual({ LevelCurve.FromTotalXP(0) }, { 1, 0, 100 })
	expectEqual({ LevelCurve.FromTotalXP(99) }, { 1, 99, 100 })
	expectEqual({ LevelCurve.FromTotalXP(100) }, { 2, 0, 150 })
	expectEqual({ LevelCurve.FromTotalXP(260) }, { 3, 10, 200 })
	expectEqual(LevelCurve.TotalXPForLevel(3), 250)
	local maxLevel = LevelCurve.FromTotalXP(10 ^ 9)
	expectEqual(maxLevel, LevelCurve.MaxLevel)
end)

test("DailyLogic streaks grow on consecutive days and reset after a gap", function()
	local state = { LastClaimDay = 0, Streak = 0 }
	local table_ = { 5, 6, 7 }
	expectEqual({ DailyLogic.Claim(state, 100, table_) }, { true, 1, 5 })
	expectEqual({ DailyLogic.Claim(state, 100, table_) }, { false, 1, 0 })
	expectEqual({ DailyLogic.Claim(state, 101, table_) }, { true, 2, 6 })
	expectEqual({ DailyLogic.Claim(state, 102, table_) }, { true, 3, 7 })
	expectEqual({ DailyLogic.Claim(state, 103, table_) }, { true, 4, 7 })
	expectEqual({ DailyLogic.Claim(state, 110, table_) }, { true, 1, 5 })
end)

test("DailyLogic.ClaimFirstWin pays once a day", function()
	local state = { LastClaimDay = 0, Streak = 0 }
	expectEqual(DailyLogic.ClaimFirstWin(state, 200), true)
	expectEqual(DailyLogic.ClaimFirstWin(state, 200), false, "a second win the same day")
	expectEqual(DailyLogic.ClaimFirstWin(state, 201), true, "the next day")
	expectEqual(state.FirstWinDay, 201)
	expectEqual(DailyLogic.ClaimFirstWin(state, 199), false, "never for a day already past")
end)

test("DailyLogic week numbers start on Monday", function()
	local monday = 1704672000 -- 2024-01-08 00:00 UTC (Monday)
	local sunday = monday - 1
	expectEqual(DailyLogic.WeekNumber(monday), DailyLogic.WeekNumber(sunday) + 1)
	expectEqual(DailyLogic.WeekNumber(monday + 6 * 86400), DailyLogic.WeekNumber(monday))
end)

local QUESTS = {
	{ Id = "Play", Period = "Daily", Text = "", Event = "RoundPlayed", Target = 3, RewardCoins = 5, RewardXP = 40 },
	{
		Id = "Emotes",
		Period = "Daily",
		Text = "",
		Event = "EmoteUsed",
		Target = 3,
		Unique = true,
		RewardCoins = 3,
		RewardXP = 20,
	},
	{
		Id = "Collect",
		Period = "Daily",
		Text = "",
		Event = "ItemCollected",
		Target = 25,
		RewardCoins = 6,
		RewardXP = 40,
	},
	{ Id = "Vote", Period = "Daily", Text = "", Event = "Voted", Target = 5, RewardCoins = 3, RewardXP = 25 },
	{ Id = "WeeklyWins", Period = "Weekly", Text = "", Event = "Win", Target = 5, RewardCoins = 30, RewardXP = 250 },
}
local BY_ID = {}
for _, def in QUESTS do
	BY_ID[def.Id] = def
end

test("QuestLogic.Refresh rolls distinct quests per period and keeps them until the period changes", function()
	local state = { Number = 0, Active = {} }
	local rng = TestKit.seeded(3)
	expectTrue(QuestLogic.Refresh(state, QUESTS, "Daily", 10, 3, rng.index))
	expectEqual(#state.Active, 3)
	local ids = {}
	for _, quest in state.Active do
		expectTrue(BY_ID[quest.Id].Period == "Daily")
		expectTrue(not ids[quest.Id])
		ids[quest.Id] = true
	end
	expectEqual(QuestLogic.Refresh(state, QUESTS, "Daily", 10, 3, rng.index), false)
	expectTrue(QuestLogic.Refresh(state, QUESTS, "Daily", 11, 3, rng.index))
end)

test("QuestLogic.Refresh replaces a retired quest the same day, keeping the rest", function()
	local state = {
		Number = 10,
		Active = {
			{ Id = "Play", Progress = 2, Done = false },
			{ Id = "D_Collect25", Progress = 0, Done = false }, -- retired: no definition any more
			{ Id = "Emotes", Progress = 1, Done = false, Seen = { Wave = true } },
		},
	}
	expectTrue(QuestLogic.Refresh(state, QUESTS, "Daily", 10, 3, TestKit.seeded(5).index))
	expectEqual(#state.Active, 3)
	local ids = {}
	for _, quest in state.Active do
		expectTrue(BY_ID[quest.Id] ~= nil, "only known quests")
		expectTrue(not ids[quest.Id], "no quest twice")
		ids[quest.Id] = quest
	end
	expectEqual(ids.Play.Progress, 2, "the others keep their progress")
	expectEqual(ids.Emotes.Progress, 1)
	expectEqual(state.Number, 10)
	expectEqual(QuestLogic.Refresh(state, QUESTS, "Daily", 10, 3, TestKit.seeded(5).index), false)
end)

test("QuestLogic.ApplyEvent progresses, completes once, and handles unique keys", function()
	local state = {
		Number = 1,
		Active = {
			{ Id = "Play", Progress = 0, Done = false },
			{ Id = "Emotes", Progress = 0, Done = false, Seen = {} },
			{ Id = "Collect", Progress = 0, Done = false },
		},
	}
	expectEqual(#QuestLogic.ApplyEvent(state, BY_ID, "RoundPlayed"), 0)
	expectEqual(#QuestLogic.ApplyEvent(state, BY_ID, "RoundPlayed"), 0)
	local done = QuestLogic.ApplyEvent(state, BY_ID, "RoundPlayed")
	expectEqual(#done, 1)
	expectEqual(done[1].Id, "Play")
	expectEqual(#QuestLogic.ApplyEvent(state, BY_ID, "RoundPlayed"), 0, "completes only once")

	QuestLogic.ApplyEvent(state, BY_ID, "EmoteUsed", 1, "Wave")
	QuestLogic.ApplyEvent(state, BY_ID, "EmoteUsed", 1, "Wave")
	expectEqual(state.Active[2].Progress, 1, "repeat emote does not count")
	QuestLogic.ApplyEvent(state, BY_ID, "EmoteUsed", 1, "Cheer")
	expectEqual(#QuestLogic.ApplyEvent(state, BY_ID, "EmoteUsed", 1, "Dance"), 1)

	QuestLogic.ApplyEvent(state, BY_ID, "ItemCollected", 30)
	expectEqual(state.Active[3].Progress, 25, "progress is capped at the target")
end)

test("TableUtil.Reconcile fills missing defaults without overwriting saved values", function()
	local saved = { Coins = 40, Stats = { Wins = 2 } }
	TableUtil.Reconcile(saved, { Coins = 0, XP = 0, Stats = { Wins = 0, RoundsPlayed = 0 }, Owned = {} })
	expectEqual(saved, { Coins = 40, XP = 0, Stats = { Wins = 2, RoundsPlayed = 0 }, Owned = {} })

	local template = { List = { 1, 2 } }
	local copy = TableUtil.DeepCopy(template)
	copy.List[1] = 9
	expectEqual(template.List[1], 1, "DeepCopy must not share nested tables")
end)

return nil

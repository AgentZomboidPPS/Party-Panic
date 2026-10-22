-- 👍 / 👎 on each mini-game (owner: "lets add to the backburner a away for players to downvote a
-- minigame and then we can harvest that data to disable minigames in the future." Then: "Also while
-- you make the downvote for mini games can you also do an upvote one so we can see if players like
-- it"; Shared/Logic/GameRatings): one vote per person per round, switching and taking it back, never
-- from bots or anyone who sat the round out, the weekly totals, the unique voters, the ISO weeks and
-- the owner's table sorted best-liked first.
local TestKit = require("./TestKit")
local GameRatings = require("../src/shared/Logic/GameRatings")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local ann, bo, cy, bot, away = { Name = "Ann" }, { Name = "Bo" }, { Name = "Cy" }, { Name = "Bot" }, { Name = "Away" }

local function ballot()
	return GameRatings.NewBallot("PumpAndPop", {
		{ Key = ann, Id = 1001 },
		{ Key = bo, Id = 1002 },
		{ Key = cy, Id = 1003 },
		{ Key = bot, Id = -5, Bot = true },
		{ Key = away, Id = 1004, SatOut = true },
	})
end

test("GameRatings: the people who played can vote, bots and sit-outs can't", function()
	local round = ballot()
	expectEqual(round.Plays, 3, "three people played")
	expectEqual(GameRatings.Vote(round, ann, "Up"), true)
	expectEqual(GameRatings.Vote(round, bot, "Up"), false, "a bot")
	expectEqual(GameRatings.Vote(round, away, "Down"), false, "someone who sat out")
	expectEqual(GameRatings.Vote(round, { Name = "Stranger" }, "Down"), false, "someone not in the round")
	expectEqual(GameRatings.Vote(round, bo, "Maybe"), false, "not a choice")
	expectEqual(GameRatings.Vote(round, bo, 1), false, "not a choice")
	expectEqual(GameRatings.Tally(round), { Game = "PumpAndPop", Plays = 3, Up = 1, Down = 0, Voters = { 1001 } })
end)

test("GameRatings: one vote per person; switching replaces it, a take-back removes it", function()
	local round = ballot()
	GameRatings.Vote(round, ann, "Up")
	GameRatings.Vote(round, ann, "Up") -- the same again is still one vote
	GameRatings.Vote(round, bo, "Up")
	GameRatings.Vote(round, bo, "Down") -- 👍 switched to 👎
	GameRatings.Vote(round, cy, "Down")
	GameRatings.Vote(round, cy, "Up") -- and 👎 back to 👍
	expectEqual(
		GameRatings.Tally(round),
		{ Game = "PumpAndPop", Plays = 3, Up = 2, Down = 1, Voters = { 1001, 1002, 1003 } }
	)
	GameRatings.Vote(round, ann, "None") -- taken back
	expectEqual(GameRatings.Current(round, ann), "None")
	expectEqual(GameRatings.Tally(round), { Game = "PumpAndPop", Plays = 3, Up = 1, Down = 1, Voters = { 1002, 1003 } })
end)

test("GameRatings.Tap: the other button switches, the lit one again takes it back", function()
	expectEqual(GameRatings.Tap("None", "Up"), "Up")
	expectEqual(GameRatings.Tap("Up", "Down"), "Down")
	expectEqual(GameRatings.Tap("Down", "Up"), "Up")
	expectEqual(GameRatings.Tap("Up", "Up"), "None")
	expectEqual(GameRatings.Tap("Down", "Down"), "None")
end)

test("GameRatings.Add: a week's totals grow by each round, the PLAY AGAIN answers and the game vote", function()
	local round = ballot()
	GameRatings.Vote(round, ann, "Up")
	GameRatings.Vote(round, bo, "Down")
	local week = GameRatings.Add(nil, { Tally = GameRatings.Tally(round), ReplayYes = 2, ReplayNo = 1 })
	week = GameRatings.Add(week, { VoteOffers = 1, VoteWins = 1 })
	week = GameRatings.Add(week, { VoteOffers = 1, VoteWins = 0 })
	expectEqual(
		{ week.Rounds, week.Plays, week.Up, week.Down, week.ReplayYes, week.ReplayNo, week.VoteOffers, week.VoteWins },
		{ 1, 3, 1, 1, 2, 1, 2, 1 }
	)
	expectEqual(GameRatings.CountVoters(week.Seen), 2)
	-- Junk in the store (another version, a hand edit) counts as nothing rather than breaking it.
	local fixed = GameRatings.Add({ Up = "lots", Down = -4, Plays = 0 / 0, Seen = "zz" }, {})
	expectEqual({ fixed.Up, fixed.Down, fixed.Plays }, { 0, 0, 0 })
	expectEqual(GameRatings.CountVoters(fixed.Seen), 0)
end)

test("GameRatings: unique voters count each person once, about right up to thousands", function()
	local seen = GameRatings.Empty().Seen
	seen = GameRatings.Mark(seen, { 1001, 1002, 1003 })
	seen = GameRatings.Mark(seen, { 1001, 1002 }) -- the same people in another round
	expectEqual(GameRatings.CountVoters(seen), 3)
	for _, count in { 100, 1000, 3000 } do
		local map = GameRatings.Empty().Seen
		local ids = {}
		for index = 1, count do
			table.insert(ids, 11690000000 + index * 7919)
		end
		map = GameRatings.Mark(map, ids)
		local estimate = GameRatings.CountVoters(map)
		expectTrue(math.abs(estimate - count) <= count * 0.06, `{count} voters read as {estimate}`)
	end
end)

test("GameRatings.Week: ISO weeks (Monday to Sunday, UTC; week 1 has the year's first Thursday)", function()
	local function at(y: number, m: number, d: number, hour: number?): number
		-- days from 1970-01-01 to y-m-d (proleptic Gregorian)
		local yy = if m <= 2 then y - 1 else y
		local era = yy // 400
		local yoe = yy - era * 400
		local mp = (m + 9) % 12
		local doy = (153 * mp + 2) // 5 + d - 1
		local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
		return (era * 146097 + doe - 719468) * 86400 + (hour or 12) * 3600
	end
	expectEqual(GameRatings.Week(at(2026, 10, 22)), "2026-W43", "a Thursday")
	expectEqual(GameRatings.Week(at(2026, 10, 19, 0)), "2026-W43", "its Monday, just after midnight")
	expectEqual(GameRatings.Week(at(2026, 10, 18, 23)), "2026-W42", "the Sunday before, late")
	expectEqual(GameRatings.Week(at(2026, 1, 1)), "2026-W01", "2026 starts on a Thursday")
	expectEqual(GameRatings.Week(at(2027, 1, 1)), "2026-W53", "a Friday in 2026's week 53")
	expectEqual(GameRatings.Week(at(2024, 12, 30)), "2025-W01", "a Monday in next year's week 1")
	expectEqual(GameRatings.Week(at(2021, 1, 3)), "2020-W53")
	expectEqual(GameRatings.Week(0), "1970-W01")
	expectEqual(GameRatings.LastWeeks(at(2026, 10, 22), 4), { "2026-W43", "2026-W42", "2026-W41", "2026-W40" })
	expectEqual(GameRatings.LastWeeks(at(2026, 1, 8), 2), { "2026-W02", "2026-W01" })
end)

test("GameRatings.Summary: best-liked first by net score; too few votes go last", function()
	local function week(up: number, down: number, plays: number, extra: { [string]: number }?)
		local record = GameRatings.Empty() :: any
		record.Rounds, record.Up, record.Down, record.Plays = 1, up, down, plays
		for key, value in extra or {} do
			record[key] = value
		end
		return record
	end
	local rows = GameRatings.Summary({
		Loved = { week(30, 5, 60), week(10, 0, 20) }, -- 40 up, 5 down: net 35/45
		Fine = { week(20, 20, 80, { ReplayYes = 3, ReplayNo = 1, VoteWins = 2, VoteOffers = 5 }) }, -- net 0
		Hated = { week(5, 40, 50) }, -- net -35/45
		Mixed = { week(25, 15, 50) }, -- net 10/40
		Tiny = { week(3, 0, 5) }, -- loved, but 3 votes say nothing yet
		TinyBad = { week(0, 4, 5) },
		Same = { week(25, 15, 60), week(10, 5, 10) }, -- net 15/55, just above Mixed
		Twin = { week(15, 9, 30), week(5, 3, 10), week(0, 0, 0) }, -- net 8/32: Mixed's 0.25, fewer votes
	})
	local order = {}
	for _, row in rows do
		table.insert(order, row.Game)
	end
	expectEqual(order, { "Loved", "Same", "Mixed", "Twin", "Fine", "Hated", "Tiny", "TinyBad" })
	local loved = rows[1]
	expectEqual({ loved.Rounds, loved.Plays, loved.Up, loved.Down, loved.Votes }, { 2, 80, 40, 5, 45 })
	expectEqual(loved.Judged, true)
	expectTrue(math.abs(loved.UpRate - 0.5) < 1e-9 and math.abs(loved.DownRate - 5 / 80) < 1e-9, "rates over plays")
	expectTrue(math.abs(loved.Net - 35 / 45) < 1e-9, "net over every vote")
	expectEqual(loved.ReplayRate, nil, "no PLAY AGAIN answers")
	local fine = rows[5]
	expectEqual({ fine.Net, fine.ReplayRate, fine.VoteWins, fine.VoteOffers }, { 0, 0.75, 2, 5 })
	expectEqual(rows[7].Judged, false)
	expectEqual(GameRatings.MinVotes, 30)
end)

return nil

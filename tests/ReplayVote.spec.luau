-- The replay vote on the results card (owner: "Add a vote at the end of each minigame to replay the
-- same minigame."; Shared/Logic/ReplayVote): who it counts, when it passes, the cap on replays in a
-- row, and that a replay doesn't spoil the game vote's variety (the real picker and game pool,
-- tools/checks/vote_pool.luau, as tests/VoteFairness.spec.luau uses them).
local fs = require("@lune/fs")

local TestKit = require("./TestKit")
local GamePicker = require("../src/shared/Logic/GamePicker")
local ReplayVote = require("../src/shared/Logic/ReplayVote")
local Pool = require("../tools/checks/vote_pool")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local config = fs.readFile("src/shared/Config.luau")
local MAX = tonumber(string.match(config, "MaxReplays = (%d+)")) or 2
local MEMORY = tonumber(string.match(config, "RecentGameMemory = (%d+)")) or 2

-- Stand-ins for the people who can vote, and what they answered.
local ann, bo, cy, di, ed = { Name = "Ann" }, { Name = "Bo" }, { Name = "Cy" }, { Name = "Di" }, { Name = "Ed" }

test("ReplayVote.Tally counts the voters' answers only", function()
	local gone = { Name = "Gone" } -- answered, then left or went on a break
	local tally = ReplayVote.Tally({ ann, bo, cy, di, ed }, { [ann] = true, [bo] = true, [cy] = false, [gone] = true })
	expectEqual(tally, { Yes = 2, No = 1, Voters = 5, Need = 3 })
end)

test("ReplayVote.Passes takes more than half of the voters saying PLAY AGAIN", function()
	local function passes(voters, yes: number): boolean
		local choices = {}
		for index = 1, yes do
			choices[voters[index]] = true
		end
		return ReplayVote.Passes(ReplayVote.Tally(voters, choices), 0, MAX)
	end
	local five = { ann, bo, cy, di, ed }
	expectEqual(passes(five, 3), true, "3 of 5")
	expectEqual(passes(five, 2), false, "2 of 5")
	local four = { ann, bo, cy, di }
	expectEqual(passes(four, 2), false, "2 of 4 is only half")
	expectEqual(passes(four, 3), true, "3 of 4")
	expectEqual(passes({ ann }, 1), true, "a lone player")
	expectEqual(passes({ ann }, 0), false, "a lone player who didn't answer")
	expectEqual(passes({}, 0), false, "nobody to vote")
	-- NO THANKS counts against it like not answering does: it's yes votes out of everyone who can vote.
	local tally = ReplayVote.Tally(four, { [ann] = true, [bo] = true, [cy] = false, [di] = false })
	expectEqual(ReplayVote.Passes(tally, 0, MAX), false, "2 yes, 2 no")
end)

test("ReplayVote: at most MaxReplays replays in a row", function()
	expectTrue(MAX >= 1, "Config.Session.MaxReplays")
	local everyone = ReplayVote.Tally({ ann, bo }, { [ann] = true, [bo] = true })
	for streak = 0, MAX - 1 do
		expectEqual(ReplayVote.Offered(streak, MAX), true, `offered after {streak} replays`)
		expectEqual(ReplayVote.Passes(everyone, streak, MAX), true, `passes after {streak} replays`)
	end
	expectEqual(ReplayVote.Offered(MAX, MAX), false, "not offered once it's been replayed MaxReplays times")
	expectEqual(ReplayVote.Passes(everyone, MAX, MAX), false, "and everyone saying yes doesn't change that")
end)

test("ReplayVote.Remember: a replay doesn't push the games before it out of the vote's memory", function()
	local recent = ReplayVote.Remember({}, "HoneyTrap", 5)
	recent = ReplayVote.Remember(recent, "PumpAndPop", 5)
	expectEqual(recent, { "PumpAndPop", "HoneyTrap" })
	for _ = 1, MAX do
		recent = ReplayVote.Remember(recent, "PumpAndPop", 5) -- replayed
	end
	expectEqual(recent, { "PumpAndPop", "HoneyTrap" })
	recent = ReplayVote.Remember(recent, "Spleef", 2)
	expectEqual(recent, { "Spleef", "PumpAndPop" }, "kept to its length")
end)

test("after a replayed game the next vote skips it and still plays down the game before it", function()
	local pool = Pool.Read()
	local players = 8
	local prev, game = nil, nil
	for _, entry in pool do
		if GamePicker.IsEligible(entry, players) and not entry.IsNew then
			if not prev then
				prev = entry
			elseif not game and entry.Category ~= prev.Category then
				game = entry
			end
		end
	end
	assert(prev and game, "two games to play")
	-- prev, then game played three times in a row (two replays).
	local remembered = ReplayVote.Remember({}, prev.Id, 5)
	local naive = table.clone(remembered)
	for _ = 1, 1 + MAX do
		remembered = ReplayVote.Remember(remembered, game.Id, 5)
		table.insert(naive, 1, game.Id) -- what a plain "add every round" list would hold
	end
	local random = Pool.Generator(2024)
	local function offered(recent: { string }): ({ [string]: number }, number)
		local counts, total = {}, 0
		for _ = 1, 4000 do
			for _, id in
				GamePicker.Pick(pool, {
					PlayerCount = players,
					Count = 3,
					Recent = recent,
					RecentMemory = MEMORY,
					RandomFloat = random,
				})
			do
				counts[id] = (counts[id] or 0) + 1
				total += 1
			end
		end
		return counts, total
	end
	local counts = offered(remembered)
	expectEqual(counts[game.Id], nil, `{game.Id} was offered right after its replays`)
	local naiveCounts = offered(naive)
	-- With every round added, the game before the replays drops out of the picker's memory and is
	-- offered as often as any game; remembered once, it stays played down.
	local before, naiveBefore = counts[prev.Id] or 0, naiveCounts[prev.Id] or 0
	expectTrue(before < naiveBefore * 0.6, `{prev.Id}: offered {before} times, {naiveBefore} with a plain list`)
end)

return nil

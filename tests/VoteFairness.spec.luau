-- Pins how fair the vote is to every mini-game (owner: "4 options always. and the 4th option should
-- be random"; three games from Shared/Logic/GamePicker plus a RANDOM card, VotingService.BuildOptions).
-- Thousands of votes through the real picker and the real GameDefinitions pool
-- (tools/checks/vote_pool.luau; `lune run tools/checks/vote_sim` prints the full table), so a new
-- game, a new IsNew tag or a weight change can't quietly starve the others:
--   * every game a lobby can play is offered at least 60% as often as the average game;
--   * new games (IsNew) get a modest boost over the rest, and no more than half the games are new
--     (with most games tagged, the tag stops meaning anything);
--   * one vote's three games almost never share a category;
--   * RANDOM is always a game that isn't already on the other three cards;
--   * a fresh server has offered every game within 60 votes, 9 times in 10;
--   * a lobby never sees a game it hasn't enough players for.
local fs = require("@lune/fs")

local TestKit = require("./TestKit")
local GamePicker = require("../src/shared/Logic/GamePicker")
local Pool = require("../tools/checks/vote_pool")

local test, expectTrue, expectEqual = TestKit.test, TestKit.expectTrue, TestKit.expectEqual

local VOTES = 6000
local config = fs.readFile("src/shared/Config.luau")
local memory = tonumber(string.match(config, "RecentGameMemory = (%d+)")) or 2
local choices = tonumber(string.match(config, "VoteChoices = (%d+)")) or 3
local pool = Pool.Read()
local counts = { 1, 2, 8, 12 }
local result = Pool.Simulate(GamePicker, pool, VOTES, counts, memory, choices, 4242)

local function eligible(entry, players: number): boolean
	return GamePicker.IsEligible(entry, players)
end

test("every game a lobby can play is offered at least 60% as often as the average", function()
	for _, players in { 2, 8, 12 } do
		local r = result[players]
		for _, entry in pool do
			if eligible(entry, players) then
				local share = (r.Offered[entry.Id] or 0) / r.Average
				expectTrue(
					share >= 0.6,
					`{entry.Id} is offered {math.floor(share * 100)}% of the average at {players} players`
				)
			end
		end
	end
end)

test("the newest four games in the rotation are the new ones", function()
	local enabled = {}
	for _, entry in pool do
		if entry.Enabled then
			table.insert(enabled, entry)
		end
	end
	for index, entry in enabled do
		expectEqual(entry.IsNew, index > #enabled - 4, `{entry.Id} new`)
	end
	for _, entry in pool do
		if not entry.Enabled then
			expectTrue(not entry.IsNew, `{entry.Id} is out of the rotation but new`)
		end
	end
end)

test("new games get a modest boost, and no more than half the games are new", function()
	local new, total = 0, 0
	for _, entry in pool do
		if entry.Enabled then
			total += 1
			if entry.IsNew then
				new += 1
			end
		end
	end
	expectTrue(new <= total / 2, `{new} of {total} games are tagged IsNew`)
	local r = result[8]
	local newSum, newCount, oldSum, oldCount = 0, 0, 0, 0
	for _, entry in pool do
		if eligible(entry, 8) then
			local n = r.Offered[entry.Id] or 0
			if entry.IsNew then
				newSum += n
				newCount += 1
			else
				oldSum += n
				oldCount += 1
			end
		end
	end
	if newCount > 0 and oldCount > 0 then
		local boost = (newSum / newCount) / (oldSum / oldCount)
		expectTrue(boost >= 1.1 and boost <= 1.6, `new games are offered {boost} times as often as the rest`)
	end
end)

test("one vote's three games almost never share a category", function()
	for _, players in { 2, 8, 12 } do
		expectTrue(
			result[players].SameAll <= 0.02,
			`all three cards share a category in {result[players].SameAll * 100}% of votes`
		)
	end
end)

test("RANDOM is never one of the three shown games", function()
	for _, players in counts do
		expectTrue(result[players].Clashes == 0, `RANDOM repeated a shown game {result[players].Clashes} times`)
	end
end)

test("a fresh server offers every game within 60 votes, 9 times in 10", function()
	local _, p90 = Pool.Coverage(GamePicker, pool, 8, memory, choices, 400, 99)
	expectTrue(p90 <= 60, `9 in 10 servers needed up to {p90} votes`)
end)

test("a lobby only sees games it has enough players for", function()
	for _, players in counts do
		for _, entry in pool do
			if not eligible(entry, players) then
				expectTrue((result[players].Offered[entry.Id] or 0) == 0, `{entry.Id} was offered to {players} players`)
				expectTrue(
					(result[players].Random[entry.Id] or 0) == 0,
					`RANDOM turned into {entry.Id} for {players} players`
				)
			end
		end
	end
end)

return nil

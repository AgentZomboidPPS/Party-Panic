-- Checks the party streak (src/shared/Logic/PartyStreak; owner: "Also make the party system insane. I
-- want it to look super epic."): rounds in a row the whole party played, back to 0 when one of them
-- missed a round, kept through people joining and leaving, gone with the party, and its tiers.
local TestKit = require("./TestKit")
local PartyStreak = require("../src/shared/Logic/PartyStreak")

local test, expectEqual = TestKit.test, TestKit.expectEqual

local function people(...: string): ...any
	local list = {}
	for _, name in { ... } do
		table.insert(list, { Name = name })
	end
	return table.unpack(list)
end

local function playing(...: any): { [any]: boolean }
	local played = {}
	for _, who in { ... } do
		played[who] = true
	end
	return played
end

test("PartyStreak: one more for every round the whole party played", function()
	local ann, bo, cy = people("Ann", "Bo", "Cy")
	local streak = 0
	for round = 1, 3 do
		streak = PartyStreak.Next(streak, { ann, bo, cy }, playing(ann, bo, cy))
		expectEqual(streak, round)
	end
	-- Others playing too changes nothing.
	expectEqual(PartyStreak.Next(streak, { ann, bo }, playing(ann, bo, cy, people("Di"))), 4)
end)

test("PartyStreak: a round one of them missed ends it", function()
	local ann, bo, cy = people("Ann", "Bo", "Cy")
	expectEqual(PartyStreak.Next(6, { ann, bo, cy }, playing(ann, bo)), 0)
	expectEqual(PartyStreak.Next(6, { ann, bo, cy }, playing()), 0, "a round none of them played")
	expectEqual(PartyStreak.Next(6, { ann }, playing(ann)), 0, "one person isn't a party")
	expectEqual(PartyStreak.Next(6, {}, playing(ann)), 0)
	expectEqual(PartyStreak.Next(-3, { ann, bo }, playing(ann, bo)), 1, "a bad count starts again")
end)

test("PartyStreak: each party's own streak; a party that's over is dropped", function()
	local ann, bo, cy, di, ed = people("Ann", "Bo", "Cy", "Di", "Ed")
	local streaks = { [1] = 2, [2] = 5, [3] = 9 }
	local after = PartyStreak.Round(streaks, {
		{ Id = 1, Members = { ann, bo } },
		{ Id = 2, Members = { cy, di, ed } },
	}, playing(ann, bo, cy, di))
	-- Party 1 played whole, Ed sat this one out, party 3 is over.
	expectEqual(after, { [1] = 3, [2] = 0 })
	-- A party that's new here starts from nothing.
	expectEqual(PartyStreak.Round({}, { { Id = 4, Members = { ann, bo } } }, playing(ann, bo)), { [4] = 1 })
end)

test("PartyStreak: people joining and leaving keep the party's streak", function()
	local ann, bo, cy = people("Ann", "Bo", "Cy")
	local streaks = PartyStreak.Round({ [7] = 3 }, { { Id = 7, Members = { ann, bo } } }, playing(ann, bo))
	expectEqual(streaks[7], 4)
	-- Cy joins: the next round they all play counts on.
	streaks = PartyStreak.Round(streaks, { { Id = 7, Members = { ann, bo, cy } } }, playing(ann, bo, cy))
	expectEqual(streaks[7], 5)
	-- Ann leaves (Bo leads now): still the same party.
	streaks = PartyStreak.Round(streaks, { { Id = 7, Members = { bo, cy } } }, playing(bo, cy))
	expectEqual(streaks[7], 6)
end)

test("PartyStreak: tiers by streak", function()
	local expected = { [0] = 0, [1] = 0, [2] = 1, [4] = 1, [5] = 2, [9] = 2, [10] = 3, [50] = 3 }
	for streak, tier in expected do
		expectEqual(PartyStreak.Tier(streak), tier, `a streak of {streak}`)
	end
end)

return nil

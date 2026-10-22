local TestKit = require("./TestKit")
local VoteLogic = require("../src/shared/Logic/VoteLogic")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

test("VoteLogic.Tally counts valid votes and ignores invalid ones", function()
	local counts = VoteLogic.Tally({ a = 1, b = 2, c = 2, d = 4, e = 0, f = 1.5 :: any }, 3)
	expectEqual(counts, { 1, 2, 0 })
end)

test("VoteLogic.ResolveWinner picks the clear winner without a tie-break", function()
	local winner, tie = VoteLogic.ResolveWinner({ 1, 4, 2 }, function()
		error("should not roll")
	end)
	expectEqual(winner, 2)
	expectEqual(tie, false)
end)

test("VoteLogic.ResolveWinner breaks ties only between tied options", function()
	local seen = {}
	for roll = 1, 2 do
		local winner, tie = VoteLogic.ResolveWinner({ 3, 1, 3 }, function(count)
			expectEqual(count, 2, "tie-break pool size")
			return roll
		end)
		expectTrue(tie, "should report a tie")
		seen[winner] = true
	end
	expectEqual(seen, { [1] = true, [3] = true })
end)

test("VoteLogic.ResolveWinner with zero votes picks from all options", function()
	local winner, tie = VoteLogic.ResolveWinner({ 0, 0, 0 }, function(count)
		expectEqual(count, 3)
		return 3
	end)
	expectEqual(winner, 3)
	expectTrue(tie)
end)

test("VoteLogic.ResolveWinner clamps an out-of-range roll", function()
	local winner = VoteLogic.ResolveWinner({ 2, 2, 0 }, function()
		return 99
	end)
	expectEqual(winner, 2)
end)

test("VoteLogic.ClosesAt waits for the deadline until everyone who votes has voted", function()
	local ann, bo = { Name = "Ann" }, { Name = "Bo" }
	expectEqual(VoteLogic.ClosesAt(108, { ann, bo }, {}, 0, 1), 108, "nobody has voted")
	expectEqual(VoteLogic.ClosesAt(108, { ann, bo }, { [ann] = 2 }, 101, 1), 108, "Bo hasn't voted")
	-- A vote from someone who isn't voting any more (sat out) doesn't count for Bo.
	expectEqual(VoteLogic.ClosesAt(108, { ann, bo }, { [ann] = 2, [{}] = 1 }, 101, 1), 108, "a stranger's vote")
	expectEqual(VoteLogic.ClosesAt(108, {}, {}, 0, 1), 108, "nobody to vote: the full time")
end)

test("VoteLogic.ClosesAt ends a beat after the last vote once everyone has voted", function()
	local ann, bo = { Name = "Ann" }, { Name = "Bo" }
	expectEqual(VoteLogic.ClosesAt(108, { ann, bo }, { [ann] = 2, [bo] = 3 }, 102.5, 1), 103.5)
	-- Changing a vote moves the last vote, and the beat with it; the deadline still stands.
	expectEqual(VoteLogic.ClosesAt(108, { ann, bo }, { [ann] = 4, [bo] = 3 }, 107.6, 1), 108)
	-- Bo, the last one left to vote, sat out at 104, long after Ann voted at 101: with only Ann
	-- voting it closes at 102, already past, so at once.
	expectEqual(VoteLogic.ClosesAt(108, { ann }, { [ann] = 1 }, 101, 1), 102)
end)

test("VoteLogic.IsValidChoice rejects junk", function()
	expectTrue(VoteLogic.IsValidChoice(2, 3))
	expectEqual(VoteLogic.IsValidChoice(0, 3), false)
	expectEqual(VoteLogic.IsValidChoice(4, 3), false)
	expectEqual(VoteLogic.IsValidChoice(1.5, 3), false)
	expectEqual(VoteLogic.IsValidChoice(0 / 0, 3), false)
	expectEqual(VoteLogic.IsValidChoice("1", 3), false)
	expectEqual(VoteLogic.IsValidChoice(nil, 3), false)
end)

return nil

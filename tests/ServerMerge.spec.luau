-- Merging quiet servers (owner: "Is there a way to merge severs automatically that are getting
-- low?"; Shared/Logic/ServerMerge): when a server is quiet, where its people go, and which parties
-- travel together.
local TestKit = require("./TestKit")
local ServerMerge = require("../src/shared/Logic/ServerMerge")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

test("ServerMerge: quiet is 1 to Low real players, and the streak counts lobbies in a row", function()
	expectEqual(ServerMerge.Quiet(0, 3), false, "nobody to move")
	expectEqual(ServerMerge.Quiet(1, 3), true)
	expectEqual(ServerMerge.Quiet(3, 3), true)
	expectEqual(ServerMerge.Quiet(4, 3), false)
	local streak = ServerMerge.Streak(0, 2, 3)
	streak = ServerMerge.Streak(streak, 3, 3)
	expectEqual(streak, 2)
	expectEqual(ServerMerge.Streak(streak, 5, 3), 0, "a busy lobby starts it again")
end)

test("ServerMerge: people go to the fullest server on their version with room, never a smaller one", function()
	local me = { JobId = "m", Count = 2, Version = 59 }
	local entries = {
		{ JobId = "m", Count = 2, Version = 59 }, -- (itself)
		{ JobId = "a", Count = 6, Version = 59 },
		{ JobId = "b", Count = 9, Version = 59 },
		{ JobId = "c", Count = 10, Version = 59 }, -- 10 + 2 = 12: no seat to spare
		{ JobId = "d", Count = 11, Version = 58 }, -- an older game
		{ JobId = "e", Count = 1, Version = 59 }, -- smaller
	}
	local target = ServerMerge.PickTarget(entries, me, 2, 12)
	expectEqual(target and target.JobId, "b")
	expectEqual(ServerMerge.PickTarget({ entries[5], entries[6] }, me, 2, 12), nil, "nowhere fitting")
	-- Two quiet servers of one size: only one of them moves (to the larger id).
	local x = { JobId = "x", Count = 2, Version = 59 }
	local y = { JobId = "y", Count = 2, Version = 59 }
	expectEqual((ServerMerge.PickTarget({ x, y }, x, 2, 12) :: any).JobId, "y")
	expectEqual(ServerMerge.PickTarget({ x, y }, y, 2, 12), nil)
end)

test("ServerMerge: a party moving together is listed leader first; people on their own aren't", function()
	local parties = { [1] = { 1, 2, 3 }, [2] = { 1, 2, 3 }, [3] = { 1, 2, 3 } }
	local partyOf = function(userId: number)
		return parties[userId]
	end
	local moving = ServerMerge.Parties({ 2, 1, 4 }, partyOf) -- (3 stayed)
	expectEqual(#moving, 1)
	expectEqual(table.concat(moving[1], ","), "1,2")
	expectEqual(#ServerMerge.Parties({ 1, 4 }, partyOf), 0, "one of a party moving alone")
	-- On arrival: join the first of the party already here.
	local here = { [2] = true }
	local mate = ServerMerge.MateHere({ { 1, 2, 3 } }, 3, function(userId)
		return here[userId] == true
	end)
	expectEqual(mate, 2)
	expectTrue(ServerMerge.MateHere({ { 1, 2 } }, 1, function()
		return false
	end) == nil, "nobody here yet")
end)

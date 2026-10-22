local TestKit = require("./TestKit")
local FriendLogic = require("../src/shared/Logic/FriendLogic")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

-- Friendships as pairs of UserIds, asked either way round.
local function friendships(list: { { number } }): (number, number) -> boolean
	local set = {}
	for _, pair in list do
		set[FriendLogic.PairKey(pair[1], pair[2])] = true
	end
	return function(a: number, b: number): boolean
		return set[FriendLogic.PairKey(a, b)] == true
	end
end

local function finishers(places: { { number } }): { FriendLogic.Finisher }
	local list = {}
	for _, row in places do
		table.insert(list, { Id = row[1], Place = row[2] })
	end
	return list
end

test("FriendLogic.PairKey: the same key whichever way round", function()
	expectEqual(FriendLogic.PairKey(7, 3), "3:7")
	expectEqual(FriendLogic.PairKey(3, 7), "3:7")
	expectTrue(FriendLogic.PairKey(1, 12) ~= FriendLogic.PairKey(11, 2), "1:12 and 11:2 are different pairs")
end)

test("FriendLogic.WithFriends: both friends in the round get it, a player without one doesn't", function()
	local areFriends = friendships({ { 1, 2 }, { 3, 9 } }) -- 9 isn't in this round
	local result = FriendLogic.WithFriends(finishers({ { 1, 1 }, { 2, 4 }, { 3, 2 }, { 4, 3 } }), areFriends)
	expectEqual(result, { [1] = true, [2] = true })
end)

test("FriendLogic.WithFriends: nobody with a friend, or a round of one", function()
	expectEqual(FriendLogic.WithFriends(finishers({ { 1, 1 }, { 2, 2 } }), friendships({})), {})
	expectEqual(FriendLogic.WithFriends(finishers({ { 1, 1 } }), friendships({ { 1, 2 } })), {})
end)

test("FriendLogic.Moments: who beat which friends, best place first", function()
	-- 1 wins; 4 is second with no friend here; 3 third; 2 last. Friends: 1-2, 1-3, 2-3.
	local areFriends = friendships({ { 1, 2 }, { 1, 3 }, { 2, 3 } })
	local moments = FriendLogic.Moments(finishers({ { 2, 4 }, { 4, 2 }, { 1, 1 }, { 3, 3 } }), areFriends)
	expectEqual(moments[1], { Beat = { 3, 2 }, BeatenBy = {} })
	expectEqual(moments[3], { Beat = { 2 }, BeatenBy = { 1 } })
	expectEqual(moments[2], { Beat = {}, BeatenBy = { 1, 3 } })
	expectEqual(moments[4], nil, "no friend in the round, no moment")
end)

test("FriendLogic.Moments: a tie is no beat (teammates share a place)", function()
	local areFriends = friendships({ { 1, 2 }, { 2, 3 } })
	local moments = FriendLogic.Moments(finishers({ { 1, 1 }, { 2, 1 }, { 3, 3 } }), areFriends)
	expectEqual(moments[1], nil)
	expectEqual(moments[2], { Beat = { 3 }, BeatenBy = {} })
	expectEqual(moments[3], { Beat = {}, BeatenBy = { 2 } })
end)

test("FriendLogic.Moments: tied friends who beat you are named in the round's order", function()
	local areFriends = friendships({ { 5, 9 }, { 6, 9 } })
	local moments = FriendLogic.Moments(finishers({ { 6, 1 }, { 9, 3 }, { 5, 1 } }), areFriends)
	expectEqual(moments[9].BeatenBy, { 6, 5 })
end)

test("FriendLogic texts: beat one friend, beat several, beaten", function()
	expectEqual(FriendLogic.BeatText({ "Ann" }), "🎉 You beat Ann!")
	expectEqual(FriendLogic.BeatText({ "Ann", "Bo" }), "🎉 You beat 2 friends!")
	expectEqual(FriendLogic.BeatenText({ "Bo" }), "Bo beat you - get them next round!")
	expectEqual(FriendLogic.BeatenText({ "Ann", "Bo", "Cy" }), "3 friends beat you - get them next round!")
end)

test("FriendLogic.MomentToast: one toast each, the happy one first", function()
	local text, kind = FriendLogic.MomentToast({ "Cy" }, { "Ann" })
	expectEqual(text, "🎉 You beat Cy!")
	expectEqual(kind, "success")
	text, kind = FriendLogic.MomentToast({}, { "Ann" })
	expectEqual(text, "Ann beat you - get them next round!")
	expectEqual(kind, "info")
	text, kind = FriendLogic.MomentToast({}, {})
	expectEqual(text, nil)
	expectEqual(kind, nil)
end)

test("FriendLogic.HereText: one friend by name, more by count, with the bonus", function()
	expectEqual(FriendLogic.HereText({ "Ann" }), "⭐ Ann is here! Play together for +1 💰 a round")
	expectEqual(FriendLogic.HereText({ "Ann", "Bo" }), "⭐ 2 friends are here! Play together for +1 💰 a round")
end)

test("FriendLogic: the bonus is on the low coin scale, with its results card line", function()
	expectEqual(FriendLogic.Bonus, 1)
	expectEqual(FriendLogic.BonusLabel, "Played with a friend")
end)

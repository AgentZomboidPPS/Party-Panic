--!strict
-- Friends' moments, worked out from who played a round and where they placed (Services/
-- FriendsService; owner, asked what keeps players coming back, then: "Can you work on all of that?
-- this wont mess with what the other workers are working on right?"; the idea as given: "Friends:
-- an invite button, a coin bonus for playing with friends, beat-a-friend moments"):
--   * who played the round with a friend (+1 coin on the results card, the FriendsParty medal);
--   * who beat which friends (a better place; a tie is neither), and the one toast each player gets
--     about it: "🎉 You beat Ann!" for beating a friend, or else, when a friend beat them, "Bo beat
--     you - get them next round!" (the happy one wins: keep it positive);
--   * the toast when a friend arrives: "⭐ Ann is here! Play together for +1 💰 a round".
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.

local FriendLogic = {}

-- Coins a round for playing it with a friend, however many friends played (the low coin scale;
-- owner: "I want low currency not high"), and its line on the results card.
FriendLogic.Bonus = 1
FriendLogic.BonusLabel = "Played with a friend"
-- Coins in running text: UI/Theme's CoinIcon (the server can't require the client's Theme).
local COIN = "💰"

-- One person who finished the round: their UserId and place (1 is best; a tie shares a place).
export type Finisher = { Id: number, Place: number }
-- A finisher's friends they beat and friends who beat them (UserIds, best place first).
export type Moments = { Beat: { number }, BeatenBy: { number } }
type AreFriends = (a: number, b: number) -> boolean

-- The same key for a pair whichever way round it's asked.
function FriendLogic.PairKey(a: number, b: number): string
	return if a < b then `{a}:{b}` else `{b}:{a}`
end

-- The finishers who played the round with at least one friend (UserId -> true).
function FriendLogic.WithFriends(finishers: { Finisher }, areFriends: AreFriends): { [number]: boolean }
	local result: { [number]: boolean } = {}
	for index, a in finishers do
		for other = index + 1, #finishers do
			local b = finishers[other]
			if a.Id ~= b.Id and areFriends(a.Id, b.Id) then
				result[a.Id] = true
				result[b.Id] = true
			end
		end
	end
	return result
end

-- Every finisher who beat a friend or was beaten by one, with who (in finishing order).
function FriendLogic.Moments(finishers: { Finisher }, areFriends: AreFriends): { [number]: Moments }
	local order = table.clone(finishers)
	local position: { [Finisher]: number } = {}
	for index, finisher in finishers do
		position[finisher] = index
	end
	table.sort(order, function(a, b)
		if a.Place ~= b.Place then
			return a.Place < b.Place
		end
		return position[a] < position[b] -- ties keep the round's order, so names read the same each time
	end)
	local moments: { [number]: Moments } = {}
	local function of(id: number): Moments
		local found = moments[id]
		if not found then
			found = { Beat = {}, BeatenBy = {} }
			moments[id] = found
		end
		return found
	end
	for index, winner in order do
		for other = index + 1, #order do
			local loser = order[other]
			if winner.Place < loser.Place and winner.Id ~= loser.Id and areFriends(winner.Id, loser.Id) then
				table.insert(of(winner.Id).Beat, loser.Id)
				table.insert(of(loser.Id).BeatenBy, winner.Id)
			end
		end
	end
	return moments
end

-- "🎉 You beat Ann!", or with two or more friends "🎉 You beat 2 friends!".
function FriendLogic.BeatText(names: { string }): string
	return if #names == 1 then `🎉 You beat {names[1]}!` else `🎉 You beat {#names} friends!`
end

-- "Bo beat you - get them next round!", or "2 friends beat you - get them next round!".
function FriendLogic.BeatenText(names: { string }): string
	local who = if #names == 1 then names[1] else `{#names} friends`
	return `{who} beat you - get them next round!`
end

-- The one toast a finisher gets about their friends (its text and the toast's kind), or nil when
-- they neither beat a friend nor were beaten by one. Beating someone wins over being beaten.
function FriendLogic.MomentToast(beat: { string }, beatenBy: { string }): (string?, string?)
	if #beat > 0 then
		return FriendLogic.BeatText(beat), "success"
	elseif #beatenBy > 0 then
		return FriendLogic.BeatenText(beatenBy), "info"
	end
	return nil, nil
end

-- "⭐ Ann is here! Play together for +1 💰 a round", or "⭐ 2 friends are here! ..." for more.
function FriendLogic.HereText(names: { string }): string
	local who = if #names == 1 then `{names[1]} is here!` else `{#names} friends are here!`
	return `⭐ {who} Play together for +{FriendLogic.Bonus} {COIN} a round`
end

return FriendLogic

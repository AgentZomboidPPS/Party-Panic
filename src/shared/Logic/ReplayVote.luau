--!strict
-- The replay vote at the end of a round (owner: "Add a vote at the end of each minigame to replay
-- the same minigame."). While the results show, the people who played the round and will play the
-- next one (never bots, never anyone sitting out) say PLAY AGAIN or NO THANKS; more than half of
-- them saying yes plays the same game again straight away. At most `maxReplays` replays in a row,
-- so one keen group can't keep a server on one game. Server: Services/ReplayService and
-- RoundManager; the buttons: Controllers/ResultsController.
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.

local ReplayVote = {}

export type Tally = {
	Yes: number,
	No: number,
	Voters: number,
	Need: number, -- yes votes it takes: more than half of the voters
}

-- Counts the answers of `voters` (`choices` maps a voter to true for PLAY AGAIN, false for NO
-- THANKS). An answer from anyone who isn't a voter any more (left, or went on a break) doesn't count.
function ReplayVote.Tally(voters: { any }, choices: { [any]: boolean }): Tally
	local yes, no = 0, 0
	for _, voter in voters do
		local choice = choices[voter]
		if choice == true then
			yes += 1
		elseif choice == false then
			no += 1
		end
	end
	return { Yes = yes, No = no, Voters = #voters, Need = math.floor(#voters / 2) + 1 }
end

-- Whether the vote is offered after a round: the game hasn't already been replayed `maxReplays`
-- times in a row (`streak`: replays so far).
function ReplayVote.Offered(streak: number, maxReplays: number): boolean
	return streak < maxReplays
end

-- Whether the same game goes again: it was offered and more than half of the voters said yes.
function ReplayVote.Passes(tally: Tally, streak: number, maxReplays: number): boolean
	return ReplayVote.Offered(streak, maxReplays) and tally.Voters > 0 and tally.Yes >= tally.Need
end

-- The recent-games list (most recent first, at most `max` long) after a round of `gameId`, for the
-- game vote's picker (Logic/GamePicker, which skips the last game and plays down the ones before
-- it): a replay doesn't add the game again, so the games before it stay remembered and the next vote
-- still favours variety.
function ReplayVote.Remember(recent: { string }, gameId: string, max: number): { string }
	local list = table.clone(recent)
	if list[1] ~= gameId then
		table.insert(list, 1, gameId)
	end
	while #list > max do
		table.remove(list)
	end
	return list
end

return ReplayVote

--!strict
-- Honey Trap's 1-or-2 block as plain math, shared by the server (which judges every hit) and the
-- client (which draws the block), so both follow exactly the same rule.
--
-- On a turn the block shows `First` until T0, then flips every FLIP seconds, and stops by itself at
-- the deadline on whatever it shows then. A hit is judged against what the player's screen showed
-- (owner: "the precision games will feel super bad if we dont"): the face they say they saw counts
-- if the block really showed it in the moment before the hit arrived (their round trip, plus a
-- little), but never a face from after the deadline. A hit sent just before the last flip can reach
-- the server after the deadline on a slow phone; it still gets the face that player pressed on (the
-- server waits LATE_HIT seconds past the deadline before stopping the block itself).
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.

local HoneyBlock = {}

HoneyBlock.FLIP = 0.42 -- seconds each face shows
HoneyBlock.LATE_HIT = 0.35 -- how long past the deadline the server waits for a hit still on its way
HoneyBlock.EXTRA = 0.25 -- leeway on top of a player's round trip when checking the face they saw

export type Turn = {
	T0: number, -- when the block starts flipping (server time)
	Deadline: number, -- when it stops by itself
	First: number, -- 1 or 2: the face it starts on
	Flip: number?, -- seconds per face (FLIP if missing)
}

-- How many times the block has flipped by server time t (it stops at the deadline).
local function flips(turn: Turn, t: number): number
	local stop = math.min(t, turn.Deadline)
	if stop <= turn.T0 then
		return 0
	end
	return math.floor((stop - turn.T0) / (turn.Flip or HoneyBlock.FLIP))
end

-- The face the block shows at server time t.
function HoneyBlock.FaceAt(turn: Turn, t: number): number
	return ((turn.First - 1 + flips(turn, t)) % 2) + 1
end

-- Whether `face` shows at any moment from `from` to `to`.
function HoneyBlock.Shows(turn: Turn, face: number, from: number, to: number): boolean
	if HoneyBlock.FaceAt(turn, from) == face or HoneyBlock.FaceAt(turn, to) == face then
		return true
	end
	return flips(turn, to) - flips(turn, from) >= 2 -- it flipped to it and back in between
end

-- Which face a hit that reached the server at `now` gets. `claimed` is the face the player's screen
-- showed when they pressed (anything else is ignored); `lag` is their round trip in seconds.
function HoneyBlock.Judge(turn: Turn, claimed: any, now: number, lag: number): number
	local to = math.min(now, turn.Deadline)
	if claimed == 1 or claimed == 2 then
		local from = math.min(now - lag - HoneyBlock.EXTRA, to)
		if HoneyBlock.Shows(turn, claimed, from, to) then
			return claimed
		end
	end
	return HoneyBlock.FaceAt(turn, now - lag / 2) -- the face when the hit was sent
end

return HoneyBlock

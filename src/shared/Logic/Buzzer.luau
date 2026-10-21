--!strict
-- The buzzer at the end of a timed round, as plain math: RoundContext ends a round with it and modes
-- judge what counts with it (owner: "the precision games will feel super bad if we dont", and "it
-- just has to work").
--
-- When time runs out, something can already be on its way to be judged: a HIT pressed just before
-- the buzzer that hasn't reached the server yet, an arrow that has just come down, a rope pass whose
-- last positions are still arriving. Dropping it because the round had just ended decided winners
-- by ping. So a mode asks for a moment (RoundContext.HoldEnd), the round ends when that's over but
-- never more than MAX_HOLD past the buzzer, and in that moment only what happened before the buzzer
-- counts: a press by when the player's device says it was made (allowing for their ping, like Rake
-- It In's rakes), a pass or a landing by its own time.
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.

local Buzzer = {}

Buzzer.MAX_HOLD = 0.5 -- the longest a round's end waits past the buzzer (seconds)
Buzzer.REACH = 0.1 -- a press may say it was made this much earlier than half a round trip before it arrived

-- Whether a round whose time ran out at `timeUpAt` ends at `now`, when something in flight asked it
-- to wait until `holdUntil` (server times).
function Buzzer.Ends(now: number, timeUpAt: number, holdUntil: number): boolean
	return now >= holdUntil or now >= timeUpAt + Buzzer.MAX_HOLD
end

-- Whether something that happened at server time `at` counts: anything while time hasn't run out
-- (`timeUpAt` nil), then only what happened by the buzzer.
function Buzzer.InTime(at: number, timeUpAt: number?): boolean
	return timeUpAt == nil or at <= timeUpAt
end

-- When a press that reached the server at `now` was made: the time the player's device says
-- (`sentAt`, its clock synced to the server's), but never after it arrived and never further back
-- than half the player's round trip (`lag`) plus REACH, so a made-up time can't reach back; without
-- one (bots, which have no lag), half a round trip before it arrived.
function Buzzer.PressTime(sentAt: any, now: number, lag: number): number
	local oneWay = math.max(0, lag) / 2
	if type(sentAt) == "number" and sentAt == sentAt then
		return math.clamp(sentAt, now - oneWay - Buzzer.REACH, now)
	end
	return now - oneWay
end

return Buzzer

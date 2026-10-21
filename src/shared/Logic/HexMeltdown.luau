-- Hex Meltdown's rules as plain math, shared by the server (which drops bots off sinking hexes and
-- judges stomps) and the client (which sinks the hexes on every screen), so what a screen shows and
-- what the server decides always follow the same rule. Nothing here touches instances.
--
-- A call (the server's MG_Call) sinks every hex that isn't its color: down over Move seconds from
-- SinkAt to Depth studs below its resting place, back up over Move from RiseAt. When the round ends
-- the server stamps the call's StopAt (owner: "Bot is floating." "Theres invisible stuff."): from
-- then on nothing sinks, and hexes that were down or on their way come straight back up, on every
-- screen alike. Before, the last call kept playing on players' devices through the results, so
-- people who had survived sank into the lava, and bots (the server moves them, and its hexes never
-- sink) stood in the air over the sunk hexes.
--
-- Stomps follow the house rule on fair hits (owner: "the precision games will feel super bad if we
-- dont"): a landing is judged on the screen that saw it. A person stomping goes by their own
-- screen, which shows everyone else a little late. A bot has no screen, so its stomp goes by the
-- victim's: there the bot is drawn late and the victim is where they really are, so someone who sees
-- a bot's leap coming and steps away is missed.

local HexMeltdown = {}

HexMeltdown.STOMP_REACH = 2.2 -- flat: feet on the head or shoulders (both characters about 2 wide)
HexMeltdown.STOMP_LOW = 2.5 -- the stomper's root at least this far above the victim's (on the head: 5.3)
HexMeltdown.STOMP_HIGH = 6 -- and less than this

export type Call = {
	SinkAt: number, -- server time (workspace:GetServerTimeNow())
	RiseAt: number,
	Move: number, -- seconds a sink or a rise takes
	Depth: number, -- studs
	StopAt: number?, -- the round ended then
}

-- Where a character was a moment ago: its root, on the server (one sample per frame, oldest first).
export type Sample = {
	Time: number,
	Position: Vector3,
	Falling: boolean, -- lower than the sample before it
}

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function scheduled(call: Call, now: number): number
	if now < call.RiseAt then
		return call.Depth * ease((now - call.SinkAt) / call.Move)
	end
	return call.Depth * (1 - ease((now - call.RiseAt) / call.Move))
end

-- How far below their resting place (studs) the sinking hexes of `call` are at server time `now`.
function HexMeltdown.Sunk(call: Call, now: number): number
	local stop = call.StopAt
	if stop and now > stop then
		return scheduled(call, stop) * (1 - ease((now - stop) / call.Move))
	end
	return scheduled(call, now)
end

-- Whether a root at `top` is coming down on the head of a root at `bottom`.
function HexMeltdown.StompsOn(top: Vector3, bottom: Vector3): boolean
	local dy = top.Y - bottom.Y
	local dx, dz = top.X - bottom.X, top.Z - bottom.Z
	return dy > HexMeltdown.STOMP_LOW
		and dy < HexMeltdown.STOMP_HIGH
		and dx * dx + dz * dz < HexMeltdown.STOMP_REACH * HexMeltdown.STOMP_REACH
end

-- The newest sample of `trail` taken at or before `time`.
local function sampleAt(trail: { Sample }, time: number): Sample?
	for index = #trail, 1, -1 do
		if trail[index].Time <= time then
			return trail[index]
		end
	end
	return nil
end

-- Whether `attacker` came down on `victim`'s head as the screen that saw it showed it. Both trails end
-- at `now`. The attacker counts where it was `attackerBack` seconds ago, against any of the victim's
-- spots from the last `victimBack` seconds:
--   a person stomping: 0, and how late their screen shows the others (any spot it showed counts);
--   a bot stomping: how late the victim's screen shows the others (where the victim saw the bot),
--   and 0 (where the victim really was then).
function HexMeltdown.Stomped(
	attacker: { Sample },
	attackerBack: number,
	victim: { Sample },
	victimBack: number,
	now: number
): boolean
	local top = sampleAt(attacker, now - attackerBack)
	if not top or not top.Falling then
		return false
	end
	for index = #victim, 1, -1 do
		local sample = victim[index]
		if sample.Time < now - victimBack then
			break
		elseif HexMeltdown.StompsOn(top.Position, sample.Position) then
			return true
		end
	end
	return false
end

return HexMeltdown

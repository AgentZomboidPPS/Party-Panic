--!strict
-- The swirling quicksand of Sinking Sands, as plain math the server, the client half, the test bots
-- and the specs all share, so everyone agrees where the sand has carried a coin at any moment.
-- Leaf module: no requires, no Roblox APIs (positions are polar: radius and angle round the funnel).
--
-- The sand is described by a schedule: segments of constant flow, each starting at server time T,
-- with a tangential speed S (studs/s, positive turns the angle up) and an inward speed V (studs/s,
-- always > 0: the sand always drains). Inside one segment a thing carried by the sand moves on an
-- exact spiral: r(t) = r0 - V t and angle(t) = a0 + (S / V) ln(r0 / r(t)), so the server can judge a
-- grab and every client can draw the same coin in the same place without streaming positions.
--
-- The schedule comes from "effects" (the Sand Kings' SWIRL flips and surges and their PULLs, on top
-- of a base flow that quickens as the round goes on) sampled every STEP seconds. An effect always
-- starts on that grid and a little in the future (LEAD), so rebuilding the schedule never changes
-- the part a client may already be using.

local SandSwirl = {}

-- Funnel shape (studs). The meshes in tools/meshgen/props/SinkingSands.py use the same numbers.
SandSwirl.RIM = 34 -- radius of the funnel at ground level
SandSwirl.HOLE = 5 -- radius of the sinkhole in the middle
SandSwirl.DEPTH = 10.5 -- how far below the rim the sand meets the hole
SandSwirl.CURVE = 1.6 -- profile exponent: flat at the rim, steep near the hole
SandSwirl.RINGS = { 5.3, 9, 14, 20, 27, 33.5 } -- edges of the swirl-streak rings (the client turns each)

-- Flow and walkers.
SandSwirl.STEP = 0.25 -- schedule resolution (seconds)
SandSwirl.LEAD = 0.45 -- effects start this long after they're asked for (covers network lag)
SandSwirl.EDGE = 1.5 -- a walker's drift fades out over this distance either side of the rim
SandSwirl.LIP = 6 -- width of the extra suction ring round the hole (walkers only)
SandSwirl.LIP_PULL = 3.5 -- extra inward speed at the very edge of the hole
SandSwirl.WALK_SPIN = 0.4 -- walkers slide round with this much of the sand's spin (treasure rides all of it)
SandSwirl.TREASURE_DRAIN = 2.4 -- treasure slides down this much faster than the sand drags a walker
SandSwirl.AIR_DRAG = 0.6 -- how much of the drag still reaches someone in the air (hopping isn't a free pass)
SandSwirl.MIN_V = 0.4

-- Base flow over the round (progress 0 -> 1).
SandSwirl.SPIN = { 3.2, 5.6 }
SandSwirl.DRAIN = { 1.3, 2.2 }

-- What the Sand Kings' powers do.
SandSwirl.FLIP_TIME = 0.5 -- the spin passes through zero over this long when it reverses
SandSwirl.SURGE = 7 -- extra spin of a SWIRL at its peak
SandSwirl.SURGE_CAP = 1.5 -- overlapping SWIRLs never spin faster than this many surges
SandSwirl.PULL = 5 -- extra drain of a PULL at its peak
SandSwirl.PULL_CAP = 8 -- overlapping PULLs never drain faster than this extra

export type Segment = { T: number, S: number, V: number }

export type Effects = {
	Start: number, -- round start (server time)
	Length: number, -- round length (seconds)
	Flips: { number }, -- times the spin reverses, in order
	Surges: { number }, -- start times of SWIRL surges
	Pulls: { number }, -- start times of PULLs
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Sand surface height relative to the rim at radius `r` (0 on the flat ground round the funnel).
function SandSwirl.Height(r: number): number
	if r >= SandSwirl.RIM then
		return 0
	end
	local u = math.max(0, (r - SandSwirl.HOLE) / (SandSwirl.RIM - SandSwirl.HOLE))
	return -SandSwirl.DEPTH * (1 - u) ^ SandSwirl.CURVE
end

-- Grid time at or after `t`, plus the lead, where a newly asked-for effect begins.
function SandSwirl.EffectStart(now: number): number
	local step = SandSwirl.STEP
	return math.ceil((now + SandSwirl.LEAD) / step - 1e-9) * step
end

-- Envelope of a SWIRL surge `tau` seconds after it starts: up fast, a short hold, a long ease out.
function SandSwirl.SurgeEnvelope(tau: number): number
	if tau <= 0 then
		return 0
	elseif tau < 0.3 then
		return tau / 0.3
	elseif tau < 0.9 then
		return 1
	elseif tau < 2.7 then
		local k = (tau - 0.9) / 1.8
		return 1 - k * k * (3 - 2 * k)
	end
	return 0
end

-- Envelope of a PULL: a strong suck that holds, then lets go.
function SandSwirl.PullEnvelope(tau: number): number
	if tau <= 0 then
		return 0
	elseif tau < 0.25 then
		return tau / 0.25
	elseif tau < 1.95 then
		return 1
	elseif tau < 2.45 then
		return 1 - (tau - 1.95) / 0.5
	end
	return 0
end

-- Spin direction at `t` (+1 or -1, passing smoothly through 0 while it reverses).
function SandSwirl.Direction(effects: Effects, t: number): number
	local direction = 1
	for _, flip in effects.Flips do
		if t < flip then
			break
		end
		local k = (t - flip) / SandSwirl.FLIP_TIME
		if k >= 1 then
			direction = -direction
		else
			local smooth = k * k * (3 - 2 * k)
			return lerp(direction, -direction, smooth)
		end
	end
	return direction
end

-- The flow at `t` before quantizing: tangential speed S and inward speed V.
function SandSwirl.Sample(effects: Effects, t: number): (number, number)
	local progress = math.clamp((t - effects.Start) / math.max(1, effects.Length), 0, 1)
	local spin = lerp(SandSwirl.SPIN[1], SandSwirl.SPIN[2], progress)
	local surge = 0
	for _, start in effects.Surges do
		surge += SandSwirl.SurgeEnvelope(t - start)
	end
	spin += SandSwirl.SURGE * math.min(surge, SandSwirl.SURGE_CAP)
	local pull = 0
	for _, start in effects.Pulls do
		pull += SandSwirl.PULL * SandSwirl.PullEnvelope(t - start)
	end
	local drain = lerp(SandSwirl.DRAIN[1], SandSwirl.DRAIN[2], progress) + math.min(pull, SandSwirl.PULL_CAP)
	return SandSwirl.Direction(effects, t) * spin, math.max(SandSwirl.MIN_V, drain)
end

local function round2(value: number): number
	return math.floor(value * 100 + 0.5) / 100
end

-- The schedule from the grid step holding `from` to `horizon` seconds later. Equal neighbours are
-- merged; the last segment runs on forever.
function SandSwirl.Build(effects: Effects, from: number, horizon: number): { Segment }
	local step = SandSwirl.STEP
	local first = math.floor(from / step)
	local last = math.ceil((from + horizon) / step)
	local segments: { Segment } = {}
	for index = first, last do
		local t = index * step
		local s, v = SandSwirl.Sample(effects, t + step / 2)
		s, v = round2(s), round2(v)
		local previous = segments[#segments]
		if not previous or previous.S ~= s or previous.V ~= v then
			table.insert(segments, { T = t, S = s, V = v })
		end
	end
	return segments
end

-- The flow in force at `t` (the first segment also covers anything before it).
function SandSwirl.FlowAt(segments: { Segment }, t: number): (number, number)
	local current = segments[1]
	if not current then
		return 0, SandSwirl.DRAIN[1]
	end
	for index = 2, #segments do
		local segment = segments[index]
		if segment.T > t then
			break
		end
		current = segment
	end
	return current.S, current.V
end

-- Carries a point lying on the sand from (r, a) at t0 to t1. `factor` scales the flow (heavy
-- treasure drifts slower but on the same spiral) and `drain` scales only the inward part (treasure
-- uses TREASURE_DRAIN). Returns the new radius and angle, and the time it reached the hole if it
-- did (then r is HOLE).
function SandSwirl.Advance(
	segments: { Segment },
	r: number,
	a: number,
	t0: number,
	t1: number,
	factor: number?,
	drain: number?
): (number, number, number?)
	local hole = SandSwirl.HOLE
	if r <= hole then
		return hole, a, t0
	end
	if t1 <= t0 then
		return r, a, nil
	end
	local k = factor or 1
	local count = #segments
	if count == 0 then
		return r, a, nil
	end
	for index = 1, count do
		local segment = segments[index]
		local from = if index == 1 then -math.huge else segment.T
		local to = if index < count then segments[index + 1].T else math.huge
		local s0, s1 = math.max(t0, from), math.min(t1, to)
		if s1 > s0 then
			local v = math.max(segment.V, SandSwirl.MIN_V) * k * (drain or 1)
			local s = segment.S * k
			local r1 = r - v * (s1 - s0)
			if r1 <= hole then
				return hole, a + (s / v) * math.log(r / hole), s0 + (r - hole) / v
			end
			a += (s / v) * math.log(r / r1)
			r = r1
		end
	end
	return r, a, nil
end

-- When a point on the sand at (r, ...) at t0 reaches the hole, if the schedule never changes again.
function SandSwirl.SinkTime(segments: { Segment }, r: number, t0: number, factor: number?): number
	local _, _, hit = SandSwirl.Advance(segments, r, 0, t0, math.huge, factor)
	return hit or math.huge
end

-- How the sand moves someone standing at radius `r`: inward and tangential speed (studs/s). Near the
-- hole the sand pulls harder; it lets go across the rim. The sand slides round under a walker's feet
-- (WALK_SPIN) while it whips treasure along, so a SWIRL carries a coin away from a Diver.
function SandSwirl.WalkerFlow(segments: { Segment }, r: number, t: number): (number, number)
	local rim, edge = SandSwirl.RIM, SandSwirl.EDGE
	if r >= rim + edge then
		return 0, 0
	end
	local s, v = SandSwirl.FlowAt(segments, t)
	local fade = math.clamp((rim + edge - r) / (2 * edge), 0, 1)
	local lip = 0
	local fromHole = r - SandSwirl.HOLE
	if fromHole < SandSwirl.LIP then
		local k = 1 - math.max(0, fromHole) / SandSwirl.LIP
		lip = SandSwirl.LIP_PULL * k * k
	end
	return (v + lip) * fade, s * SandSwirl.WALK_SPIN * fade
end

-- Polar <-> flat offsets from the funnel's center (x, z).
function SandSwirl.ToXZ(r: number, a: number): (number, number)
	return r * math.cos(a), r * math.sin(a)
end

function SandSwirl.ToPolar(x: number, z: number): (number, number)
	return math.sqrt(x * x + z * z), math.atan2(z, x)
end

return SandSwirl

--!strict
-- Rockin' Raceway's track and riding rules, shared by the server (which races everyone) and the
-- clients (which draw the same oval, the same panels and the same carrot meter from it).
--
-- The track is a fairground oval: two straights joined by half circles. Every rider's progress is
-- a distance D along the oval's centre line, so all twelve lanes are exactly the same length in the
-- race (an outside lane only looks longer on the turns). Frame(D, offset) gives the place and the
-- facing at D, `offset` studs outward from the centre line (a lane). One lap from the start line, in
-- the middle of the home straight, back to the same line under the finish arch.
--
-- Riding (Ride): holding GALLOP pushes the horse toward GALLOP speed and eats carrots; letting go
-- eases it back toward TROT speed while the carrots grow back. The carrot meter's bottom quarter is
-- the red line: run the meter dry while still galloping and the horse spins out (SPIN_TIME nearly
-- stopped). The horse speeds up gradually, so long gallops that ride the meter down near the red
-- line beat short taps. An orange carrot panel ridden over gives a DASH; a blue hurdle panel slows
-- the horse unless it hops over it (HOP_TIME in the air).
--
-- Leaf module: no Roblox services, so Lune tests can load it.

local Track = {}

Track.STRAIGHT = 200 -- each straight's length (studs)
Track.RADIUS = 58 -- the centre line's radius on the turns
Track.LANE = 4.5 -- one lane's width
Track.LANES = 12
Track.HALF_WIDTH = Track.LANE * Track.LANES / 2 -- 27: the centre line to either edge
Track.TURN = math.pi * Track.RADIUS -- one turn's length along the centre line
Track.LENGTH = 2 * Track.STRAIGHT + 2 * Track.TURN -- one lap (~764 studs)

-- Riding (studs per second, carrots 0..CARROTS).
Track.TROT = 15
Track.GALLOP = 27
Track.DASH = 38 -- speed right after a carrot panel
Track.SLOW = 7 -- speed after hitting a hurdle
Track.SPIN_SPEED = 2
Track.RISE = 1.5 -- how quickly the horse picks up speed (per second)
Track.FALL = 1.1 -- how quickly it eases off
Track.CARROTS = 100
Track.EAT = 24 -- carrots a second while galloping (about 4 s from full)
Track.REFILL = 30 -- carrots a second while trotting
Track.RED = 25 -- the red line: below it the meter is red
Track.SPIN_TIME = 1.8
Track.SPIN_CARROTS = 30 -- carrots after a spin-out
Track.DASH_TIME = 1.2
Track.DASH_CARROTS = 12 -- a carrot panel also feeds the horse
Track.SLOW_TIME = 1.1
Track.HOP_TIME = 0.75 -- seconds in the air
Track.HOP_HEIGHT = 2.6
Track.HOP_REST = 0.2 -- after landing, before the next hop
Track.PANEL = 4 -- a panel's length along the track

export type Rider = {
	D: number,
	V: number,
	C: number, -- carrots
	Gallop: boolean,
	SpinUntil: number,
	DashUntil: number,
	SlowUntil: number,
}

export type Panel = { D: number, K: string } -- K: "D" carrot (dash) or "H" hurdle (slow)

-- Where lane `lane` (1..LANES, inside to outside) runs: studs outward from the centre line.
function Track.LaneOffset(lane: number): number
	return (lane - (Track.LANES + 1) / 2) * Track.LANE
end

-- Spreads `count` riders over the twelve lanes (all twelve with a full field).
function Track.LaneFor(index: number, count: number): number
	return math.clamp(math.floor((index - 0.5) * Track.LANES / math.max(count, 1)) + 1, 1, Track.LANES)
end

-- The place (x, z around the oval's middle) and facing (fx, fz) at distance d, `offset` outward.
function Track.At(d: number, offset: number): (number, number, number, number)
	local s, r, R = Track.STRAIGHT / 2, Track.RADIUS + offset, Track.RADIUS
	local t = d % Track.LENGTH
	if t < s then
		return -t, r, -1, 0
	end
	t -= s
	if t < Track.TURN then
		local a = t / R
		return -s - r * math.sin(a), r * math.cos(a), -math.cos(a), -math.sin(a)
	end
	t -= Track.TURN
	if t < Track.STRAIGHT then
		return -s + t, -r, 1, 0
	end
	t -= Track.STRAIGHT
	if t < Track.TURN then
		local a = t / R
		return s + r * math.sin(a), -r * math.cos(a), math.cos(a), math.sin(a)
	end
	t -= Track.TURN
	return s - t, r, -1, 0
end

-- True on the two straights (panels only go there).
function Track.OnStraight(d: number): boolean
	local t = d % Track.LENGTH
	local s = Track.STRAIGHT / 2
	return t < s or (t >= s + Track.TURN and t < s + Track.TURN + Track.STRAIGHT) or t >= Track.LENGTH - s
end

-- The panel rows of a round: the same in every lane, only on the straights, never right at the
-- start or the finish. A hurdle is sometimes followed closely by a carrot (hop too late and you
-- land past it). `random` is a Random.
function Track.Panels(random: any): { Panel }
	local list: { Panel } = {}
	local s = Track.STRAIGHT / 2
	local stretches = {
		{ 30, s - 12 },
		{ s + Track.TURN + 14, s + Track.TURN + Track.STRAIGHT - 14 },
		{ Track.LENGTH - s + 12, Track.LENGTH - 22 },
	}
	for _, stretch in stretches do
		local d = stretch[1] + random:NextNumber(0, 8)
		while d < stretch[2] do
			local kind = if random:NextNumber() < 0.5 then "H" else "D"
			table.insert(list, { D = math.floor(d * 10) / 10, K = kind })
			if kind == "H" and random:NextNumber() < 0.45 and d + 16 < stretch[2] then
				d += random:NextNumber(13, 16) -- a carrot just past the hurdle
				table.insert(list, { D = math.floor(d * 10) / 10, K = "D" })
			end
			d += random:NextNumber(30, 44)
		end
	end
	return list
end

-- One step of riding: speed toward the gallop or trot pace, carrots eaten or grown back, a spin-out
-- when the meter runs dry under a gallop. Returns true when this step spun the horse out.
function Track.Ride(rider: Rider, dt: number, now: number): boolean
	local spun = false
	local spinning = now < rider.SpinUntil
	local galloping = rider.Gallop and not spinning
	local target = if spinning then Track.SPIN_SPEED elseif galloping then Track.GALLOP else Track.TROT
	local rate = if spinning then 4 elseif target > rider.V then Track.RISE else Track.FALL
	rider.V += (target - rider.V) * (1 - math.exp(-rate * dt))
	if now < rider.DashUntil and not spinning then
		rider.V = math.max(
			rider.V,
			Track.DASH - (Track.DASH - Track.GALLOP) * (1 - (rider.DashUntil - now) / Track.DASH_TIME)
		)
	end
	if now < rider.SlowUntil then
		rider.V = math.min(rider.V, Track.SLOW)
	end
	if galloping then
		rider.C -= Track.EAT * dt
		if rider.C <= 0 then
			rider.C = 0
			rider.SpinUntil = now + Track.SPIN_TIME
			rider.DashUntil = 0
			spun = true
		end
	elseif not spinning then
		rider.C = math.min(Track.CARROTS, rider.C + Track.REFILL * dt)
	else
		rider.C = math.min(Track.SPIN_CARROTS, rider.C + Track.SPIN_CARROTS / Track.SPIN_TIME * dt)
	end
	rider.D += rider.V * dt
	return spun
end

-- The height of a hop `since` seconds after it started (0 on the ground).
function Track.HopHeight(since: number): number
	if since < 0 or since > Track.HOP_TIME then
		return 0
	end
	local t = since / Track.HOP_TIME
	return 4 * t * (1 - t) * Track.HOP_HEIGHT
end

function Track.Ordinal(place: number): string
	local suffix = "th"
	local tens = place % 100
	if tens < 11 or tens > 13 then
		local ones = place % 10
		suffix = if ones == 1 then "st" elseif ones == 2 then "nd" elseif ones == 3 then "rd" else "th"
	end
	return `{place}{suffix}`
end

return Track

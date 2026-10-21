-- The Bobsled Run course, shared by the server (which races the sleds along it) and clients (which
-- draw the sleds on it), so both agree on every curve, bank and jump to the stud.
--
-- The course is a string of pieces, each the same mesh every time (World/Props/BobsledRun.luau):
--   S  a straight, UNIT studs long          J  a straight with a kicker that throws sleds into the air
--   L  a banked left curve (TURN at RADIUS)  R  the same to the right
-- The run always faces down the mountain (-Z) within MAX_HEADING, so it never crosses itself, and
-- drops SLOPE studs per stud. In a curve the floor tilts up toward the outside around its inner
-- edge (up to BANK in the middle). tools/meshgen/props/BobsledRun.py builds the meshes from the
-- same numbers: change them together.
--
-- Distances (d) run along the centerline from the start line; a sled's lane is a sideways offset x.

local BobsledCourse = {}

BobsledCourse.UNIT = 16
BobsledCourse.RADIUS = 70
BobsledCourse.TURN = math.rad(50)
BobsledCourse.ARC = BobsledCourse.RADIUS * BobsledCourse.TURN
BobsledCourse.SLOPE = 0.1
BobsledCourse.BANK = math.rad(30)
BobsledCourse.FLOOR_HALF = 20 -- half the ice floor's width (the bank's pivot is the inner edge)
BobsledCourse.LANE = 9
BobsledCourse.KICK = 3 -- the kicker's lip height
BobsledCourse.AIR = 34 -- how far a sled flies past the lip
BobsledCourse.MAX_HEADING = math.rad(50)
BobsledCourse.START_UNITS = 3 -- straights before the first curve (the start gate stands on them)
BobsledCourse.FINISH_UNITS = 3 -- straights after the last curve, up to the finish line
BobsledCourse.RUNOUT_UNITS = 5 -- straights past the finish line to stop on
BobsledCourse.CURVES = 11

-- Each track mesh's pivot (its bounding box's bottom center) relative to its entry point, and its
-- size: printed by `python3 tools/meshgen/props/BobsledRun.py` (with tools/meshgen on PYTHONPATH).
BobsledCourse.Anchor = {
	S = Vector3.new(0, -15.6, -8),
	J = Vector3.new(0, -15.6, -8),
	L = Vector3.new(-6.1083, -20.1087, -40.5238),
	R = Vector3.new(6.1083, -20.1087, -40.5238),
}
BobsledCourse.PieceSize = {
	S = Vector3.new(71.6, 21.5, 16),
	J = Vector3.new(71.6, 21.5, 16),
	L = Vector3.new(83.8167, 47.8603, 81.0475),
	R = Vector3.new(83.8167, 47.8603, 81.0475),
}
BobsledCourse.PieceProp = { S = "BobsledTrack", J = "BobsledKicker", L = "BobsledCurveL", R = "BobsledCurveR" }

local UNIT = BobsledCourse.UNIT
local RADIUS = BobsledCourse.RADIUS
local TURN = BobsledCourse.TURN
local ARC = BobsledCourse.ARC
local SLOPE = BobsledCourse.SLOPE
local BANK = BobsledCourse.BANK
local FLOOR_HALF = BobsledCourse.FLOOR_HALF
local KICK = BobsledCourse.KICK
local AIR = BobsledCourse.AIR

-- The air arc after a kicker's lip: leaves at the ramp's own angle, lands back on the floor at AIR.
local LIP_RISE = 2 * KICK / UNIT
local GRAVITY = (KICK + LIP_RISE * AIR) / (AIR * AIR)

export type Segment = {
	K: string,
	D0: number,
	Len: number,
	P: Vector3, -- entry point on the centerline, relative to the course origin
	H: number, -- entry heading (0 = -Z, positive turns left)
	C: Vector3?, -- a curve's center
}

export type Curve = { Index: number, Dir: number, D0: number, D1: number }

export type Course = {
	Pieces: string,
	Segments: { Segment },
	Curves: { Curve },
	Lips: { number },
	Length: number, -- the finish line
	Total: number, -- the end of the runout
}

local function forward(h: number): Vector3
	return Vector3.new(-math.sin(h), 0, -math.cos(h))
end

local function right(h: number): Vector3
	return Vector3.new(math.cos(h), 0, -math.sin(h))
end
BobsledCourse.Forward = forward
BobsledCourse.Right = right

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- How far into its bank a curve is, 0..1, at `t` (0..1 through the curve).
function BobsledCourse.BankShape(t: number): number
	return smooth(t / 0.3) * smooth((1 - t) / 0.3)
end

-- A random course: CURVES curves with straights between them (some with a kicker).
function BobsledCourse.Generate(rng: Random): string
	local pieces = { string.rep("S", BobsledCourse.START_UNITS) }
	local heading = 0
	local jumps = 0
	for index = 1, BobsledCourse.CURVES do
		local dir
		if heading >= BobsledCourse.MAX_HEADING - 0.01 then
			dir = "R"
		elseif heading <= -BobsledCourse.MAX_HEADING + 0.01 then
			dir = "L"
		else
			dir = if rng:NextNumber() < 0.5 then "L" else "R"
		end
		heading += if dir == "L" then TURN else -TURN
		table.insert(pieces, dir)
		if index == BobsledCourse.CURVES then
			break
		end
		-- A kicker on about every third straight (it needs room to land before the next curve).
		local units = rng:NextInteger(2, 3)
		if jumps < 3 and index % 3 == 2 then
			jumps += 1
			table.insert(pieces, "J" .. string.rep("S", 3))
		else
			table.insert(pieces, string.rep("S", units))
		end
	end
	table.insert(pieces, string.rep("S", BobsledCourse.FINISH_UNITS + BobsledCourse.RUNOUT_UNITS))
	return table.concat(pieces)
end

function BobsledCourse.Build(pieces: string): Course
	local segments: { Segment } = {}
	local curves: { Curve } = {}
	local lips = {}
	local position = Vector3.zero
	local heading = 0
	local d = 0
	for index = 1, #pieces do
		local kind = string.sub(pieces, index, index)
		local segment: Segment = { K = kind, D0 = d, Len = UNIT, P = position, H = heading }
		if kind == "L" or kind == "R" then
			local dir = if kind == "L" then -1 else 1
			segment.Len = ARC
			local center = position + right(heading) * RADIUS * dir
			segment.C = center
			local exitHeading = heading - dir * TURN
			position = center - right(exitHeading) * RADIUS * dir - Vector3.new(0, SLOPE * ARC, 0)
			heading = exitHeading
			table.insert(curves, { Index = #curves + 1, Dir = dir, D0 = d, D1 = d + ARC })
		else
			position += forward(heading) * UNIT - Vector3.new(0, SLOPE * UNIT, 0)
			if kind == "J" then
				table.insert(lips, d + UNIT)
			end
		end
		table.insert(segments, segment)
		d += segment.Len
	end
	local total = d
	local length = total - BobsledCourse.RUNOUT_UNITS * UNIT
	return {
		Pieces = pieces,
		Segments = segments,
		Curves = curves,
		Lips = lips,
		Length = length,
		Total = total,
	}
end

local function segmentAt(course: Course, d: number): Segment
	local segments = course.Segments
	local lo, hi = 1, #segments
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if segments[mid].D0 <= d then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return segments[lo]
end

-- How high a sled rides above the floor's line at `d` (the kicker's ramp, then the flight), and
-- that height's slope (for the sled's pitch).
function BobsledCourse.Lift(course: Course, d: number): (number, number)
	for _, lip in course.Lips do
		local u = d - (lip - UNIT)
		if u >= 0 and u <= UNIT then
			return KICK * (u / UNIT) ^ 2, 2 * KICK * u / (UNIT * UNIT)
		end
		local a = d - lip
		if a > 0 and a < AIR then
			return KICK + LIP_RISE * a - GRAVITY * a * a, LIP_RISE - 2 * GRAVITY * a
		end
	end
	return 0, 0
end

-- Whether a sled at `d` is flying off a kicker.
function BobsledCourse.Airborne(course: Course, d: number): boolean
	for _, lip in course.Lips do
		if d > lip and d < lip + AIR then
			return true
		end
	end
	return false
end

-- The centerline at `d`: floor point, heading, bank angle (positive lifts the right side) and the
-- bank's pivot offset (the inner floor edge, as a sideways offset).
function BobsledCourse.Sample(course: Course, d: number): (Vector3, number, number, number)
	local segment = segmentAt(course, math.max(d, 0))
	local s = d - segment.D0
	if segment.K == "L" or segment.K == "R" then
		if s <= segment.Len then
			local dir = if segment.K == "L" then -1 else 1
			local h = segment.H - dir * s / RADIUS
			local point = (segment.C :: Vector3) - right(h) * RADIUS * dir - Vector3.new(0, SLOPE * s, 0)
			local bank = -dir * BANK * BobsledCourse.BankShape(s / segment.Len)
			return point, h, bank, dir * FLOOR_HALF
		end
		-- (past the course's last piece: carry on straight)
		local h = segment.H - (if segment.K == "L" then -1 else 1) * TURN
		local exitPoint = BobsledCourse.Sample(course, segment.D0 + segment.Len)
		local extra = s - segment.Len
		return exitPoint + forward(h) * extra - Vector3.new(0, SLOPE * extra, 0), h, 0, 0
	end
	return segment.P + forward(segment.H) * s - Vector3.new(0, SLOPE * s, 0), segment.H, 0, 0
end

-- Where a sled sits at distance `d`, `x` studs right of the centerline: on the floor, facing down
-- the run, tilted with the bank and pitched with the slope (and a kicker's flight). Relative to the
-- course origin.
function BobsledCourse.Frame(course: Course, d: number, x: number): CFrame
	local point, h, bank, pivot = BobsledCourse.Sample(course, d)
	local lift, rise = BobsledCourse.Lift(course, d)
	local r = right(h)
	local up = Vector3.yAxis
	local away = x - pivot
	local position = point + r * (pivot + away * math.cos(bank)) + up * (away * math.sin(bank) + lift)
	local tilted = r * math.cos(bank) + up * math.sin(bank)
	local look = (forward(h) + up * (rise - SLOPE)).Unit
	local upVector = tilted:Cross(look).Unit
	local rightVector = look:Cross(upVector)
	return CFrame.fromMatrix(position, rightVector, upVector)
end

-- The piece frame a track mesh is placed at: its entry point, turned to its entry heading.
function BobsledCourse.PieceFrame(segment: Segment): CFrame
	return CFrame.new(segment.P) * CFrame.Angles(0, segment.H, 0)
end

-- The next curve at or after `d` (its index in course.Curves), or nil.
function BobsledCourse.NextCurve(course: Course, d: number): Curve?
	for _, curve in course.Curves do
		if curve.D1 > d then
			return curve
		end
	end
	return nil
end

-- Sideways lane offsets for `count` sleds, centered on the track.
function BobsledCourse.LaneX(index: number, count: number): number
	return (index - (count + 1) / 2) * BobsledCourse.LANE
end

-- Seat offsets along a sled (forward is -Z) for a crew of `count`, front to back.
function BobsledCourse.SeatZ(index: number, count: number): number
	return (index - (math.max(count, 1) + 1) / 2) * 2.5 + 0.6
end

-- Race rules (server; clients only draw them) --------------------------------------------------

BobsledCourse.CRUISE = 40 -- studs/s a sled settles at
BobsledCourse.MAX = 62
BobsledCourse.LAUNCH = 16 -- studs/s^2 off the start
BobsledCourse.OPEN = 1.25 -- seconds before a curve that leans start to count
BobsledCourse.WARN = 3 -- seconds before a curve that its arrow shows
BobsledCourse.CLEAN = 0.6 -- the crew's (right - wrong) / riders needed for a clean curve
BobsledCourse.BOOST = 14 -- studs/s a perfectly clean curve adds
BobsledCourse.BUMP = 0.5 -- speed kept after slamming the wall
BobsledCourse.SCRAPE = 0.82 -- speed kept after a half-right curve

-- Judges a curve from the crew's leans: the result kind and the new speed.
function BobsledCourse.Judge(score: number, speed: number): (string, number)
	if score >= BobsledCourse.CLEAN then
		return "Clean", math.min(BobsledCourse.MAX, speed + BobsledCourse.BOOST * score)
	elseif score > 0 then
		return "Scrape", speed * BobsledCourse.SCRAPE
	end
	return "Bump", speed * BobsledCourse.BUMP
end

-- One step of a sled's speed: launches to cruise, eases back to it after a boost or a bump.
function BobsledCourse.Accelerate(speed: number, dt: number): number
	local cruise = BobsledCourse.CRUISE
	if speed < cruise then
		local rate = if speed < 20 then BobsledCourse.LAUNCH else 7
		return math.min(cruise, speed + rate * dt)
	end
	return math.max(cruise, speed - (speed - cruise) * 0.35 * dt - 1.2 * dt)
end

function BobsledCourse.Ordinal(n: number): string
	local suffix = "th"
	if n % 100 < 11 or n % 100 > 13 then
		suffix = ({ "st", "nd", "rd" })[n % 10] or "th"
	end
	return `{n}{suffix}`
end

return BobsledCourse

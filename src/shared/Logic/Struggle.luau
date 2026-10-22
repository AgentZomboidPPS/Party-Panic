-- Struggle's shared rules: the numbers and the hit test the server judges with and the client draws
-- with, so a swing's reach on screen is the reach that counts (owner: "the precision games will feel
-- super bad if we dont"). See src/server/MiniGames/Struggle.luau for how the mode works.
--
-- Bats in hand (owner: "Bats on struggle arent actually being held they are floating. plus they dont
-- even look like bats."): the bat is drawn in each character's right hand, and the swing is the arm's.
-- The poses at the bottom say how: held up ready, wound back over the shoulder (further for a charge),
-- and a level sweep that keeps the bat's tip on the rule's reach through the whole arc (checked on the
-- standard R15 and R6 bodies by tests/Struggle.spec.luau). They are drawing only: the hit rule above
-- them is unchanged.

local Struggle = {}

Struggle.START_ORBS = 20 -- orbs each player starts with
Struggle.FIELD_X = 40 -- half the sandlot's width inside the fence (studs, from its middle)
Struggle.FIELD_Z = 28 -- half its depth (the fence stands 2 studs further out)
Struggle.ORB_MARGIN = 3 -- loose orbs land at least this far inside the fence

-- A swing: press to wind up, release to strike. A tap strikes WINDUP after the press; held for
-- CHARGE seconds it becomes a charged swing; the server lets it go by itself after MAX_HOLD.
Struggle.WINDUP = 0.28
Struggle.CHARGE = 0.75
Struggle.MAX_HOLD = 1.6
Struggle.RECOVER = 0.45 -- after a strike, before the next press
Struggle.RECOVER_CHARGED = 0.75
Struggle.SWEEP = 0.16 -- how long the bat takes through its arc (drawing only)

-- Reach, matching the bat as drawn (review: the rule reached further than the bat). The bat is held
-- in the right hand and swung level round the swinger (the poses below), its tip sweeping 4.6 out; a
-- charged swing draws the bat CHARGED_BAT times longer and sweeps it to 5.9. Anyone with any part of
-- them inside the drawn reach is hit: their middle within RANGE + BODY, inside the arc widened by their
-- body; and anyone whose body overlaps the small CLOSE circle round the swinger, whatever the direction
-- (the bat passes right through there). The client draws exactly this: a +-ARC fan of radius RANGE and
-- the circle.
Struggle.RANGE = 4.6
Struggle.CHARGED_BAT = 1.3
Struggle.RANGE_CHARGED = 5.9
Struggle.BODY = 1.1 -- a character's half width
Struggle.ARC = math.rad(80) -- each side of where the swinger faces
Struggle.CLOSE = 1.5 -- the circle round the swinger where any direction counts
Struggle.HEIGHT = 5 -- at most this far above or below

Struggle.SAFE = 1.4 -- seconds a victim can't be hit again
Struggle.PICK = 3.6 -- pick-up reach (root to orb, flat), the same for everyone
Struggle.FLIGHT = 0.7 -- seconds an orb flies before it lands and can be picked up

-- One colour and one shape per player slot (colour is never the only cue). Glyph is what the HUD
-- draws (built from frames when it's not one of the safe glyphs); Prop is the orb's mesh.
Struggle.SLOTS = {
	{ Name = "Ball", Glyph = "●", Prop = "StruggleOrbBall", Color = Color3.fromRGB(255, 80, 80) },
	{ Name = "Cube", Glyph = "■", Prop = "StruggleOrbCube", Color = Color3.fromRGB(70, 160, 255) },
	{ Name = "Pyramid", Glyph = "▲", Prop = "StruggleOrbPyramid", Color = Color3.fromRGB(255, 215, 50) },
	{ Name = "Diamond", Glyph = "◆", Prop = "StruggleOrbDiamond", Color = Color3.fromRGB(110, 230, 100) },
	{ Name = "Star", Glyph = "★", Prop = "StruggleOrbStar", Color = Color3.fromRGB(200, 120, 255) },
	{ Name = "Ring", Glyph = "O", Prop = "StruggleOrbRing", Color = Color3.fromRGB(255, 150, 50) },
	{ Name = "Plus", Glyph = "+", Prop = "StruggleOrbPlus", Color = Color3.fromRGB(80, 230, 225) },
	{ Name = "Cross", Glyph = "X", Prop = "StruggleOrbCross", Color = Color3.fromRGB(255, 120, 200) },
	{ Name = "Cone", Glyph = "▼", Prop = "StruggleOrbCone", Color = Color3.fromRGB(245, 245, 250) },
	{ Name = "Frame", Glyph = "#", Prop = "StruggleOrbFrame", Color = Color3.fromRGB(170, 120, 70) },
	{ Name = "Pill", Glyph = "=", Prop = "StruggleOrbPill", Color = Color3.fromRGB(40, 120, 110) },
	{ Name = "Kite", Glyph = "<>", Prop = "StruggleOrbKite", Color = Color3.fromRGB(230, 40, 150) },
}

-- Whether a swing from `from`, facing `look` (flat), reaches someone standing at `at`.
function Struggle.Reaches(from: Vector3, look: Vector3, at: Vector3, charged: boolean): boolean
	local offset = at - from
	if math.abs(offset.Y) > Struggle.HEIGHT then
		return false
	end
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	local reach = (if charged then Struggle.RANGE_CHARGED else Struggle.RANGE) + Struggle.BODY
	if distance > reach then
		return false
	end
	if distance <= Struggle.CLOSE + Struggle.BODY then
		return true
	end
	local facing = Vector3.new(look.X, 0, look.Z)
	if facing.Magnitude < 1e-3 then
		return false
	end
	local cos = facing.Unit:Dot(flat / distance)
	-- The arc is widened by the victim's body at that distance.
	local widen = math.asin(math.clamp(Struggle.BODY / distance, 0, 1))
	return cos >= math.cos(math.min(Struggle.ARC + widen, math.pi))
end

-- How many orbs a hit knocks loose from someone holding `held`: 3 (6 charged), or a tenth of a big
-- pile (twice that charged), so one runaway leader can be caught (review: 182 of 240 in one hand).
function Struggle.Knocked(held: number, charged: boolean): number
	local tenth = math.floor(held * 0.1 + 0.5)
	local count = if charged then math.max(6, tenth * 2) else math.max(3, tenth)
	return math.min(held, count)
end

-- Where an orb is at server time t: flying from (fx, fz) at t0 to (x, z), landing at t0 + FLIGHT.
-- Returns the flat offset from the field's middle and its height above the sand.
function Struggle.OrbAt(orb: { number }, t: number): (number, number, number)
	local x, z, fx, fz, t0 = orb[3], orb[4], orb[5], orb[6], orb[7]
	local k = math.clamp((t - t0) / Struggle.FLIGHT, 0, 1)
	local height = 4.5 * 4 * k * (1 - k)
	return fx + (x - fx) * k, fz + (z - fz) * k, height
end

-- The bat in hand (drawing only) ------------------------------------------------------------------

-- The bat as drawn (its mesh, tools/meshgen/props/Struggle.py): BAT_LENGTH from the knob's end to the
-- tip, held in the fist BAT_GRIP from the knob's end (a fist is about a stud deep: the knob stays out).
Struggle.BAT_LENGTH = 4.4
Struggle.BAT_GRIP = 0.78

-- A pose, in degrees. Twist turns the upper body round (to the left is +). Pitch, Yaw and Roll turn
-- the right arm at the shoulder, in the torso's axes: up in front (90 is level), then round to the
-- left (+) or out to the right (-), turned about itself first by Roll. Elbow bends the forearm up.
-- Tilt turns the bat in the fist: 0 sticks it out of the fist's front, -90 lines it up with the
-- forearm. (An R6 body, with no elbow, takes half the bend at the shoulder and half in the fist.)
export type Pose = { Twist: number, Pitch: number, Yaw: number, Roll: number, Elbow: number, Tilt: number }

-- Held up in front, barrel up, forward and a little out to the right (clear of the face): ready.
Struggle.READY = { Twist = 0, Pitch = 22, Yaw = -15, Roll = -15, Elbow = 62, Tilt = -28 } :: Pose
-- A press winds up: the body turns away and the bat goes back over the right shoulder...
Struggle.WIND = { Twist = -50, Pitch = 50, Yaw = -20, Roll = 0, Elbow = 125, Tilt = -10 } :: Pose
-- ...and while a charge builds, further round and back, the bat level behind the head.
Struggle.WIND_CHARGED = { Twist = -60, Pitch = 70, Yaw = -35, Roll = 0, Elbow = 120, Tilt = 5 } :: Pose
Struggle.WIND_IN = 0.15 -- seconds a press takes to reach the wind-up

-- The strike: the bat swept level from the right (-) round the front to the left (+), {angle, Twist,
-- Pitch, Yaw, Roll, Elbow, Tilt}. At each angle the body has unwound that far (from the wind-up's
-- turn) and the arm holds the bat level with its tip at the reach: RANGE, or RANGE_CHARGED for a
-- charged swing's longer bat. It runs a little past the +-ARC arc each side, so it crosses all of it.
-- (Solved on the standard R15 body measured on a test server; tests/Struggle.spec.luau checks R6 too.)
local SWEEP_TAP = {
	{ -100, -50, -49.5, -26, -12.3, 101.4, -48.6 },
	{ -80, -40, -38.9, -11.7, -14, 96.8, -54.7 },
	{ -50, -25, -23.9, 4.3, -12.9, 91.3, -64 },
	{ -20, -10, -8.7, 16.3, -9.6, 83.9, -71.8 },
	{ 0, 0, 2.1, 22.2, -6.2, 76.4, -75.4 },
	{ 20, 10, 6.6, 27.1, -2.4, 77.3, -82.1 },
	{ 50, 25, 18.6, 35.2, 3.1, 72, -91 },
	{ 80, 40, 32.2, 44.7, 8.4, 62.8, -97.5 },
	{ 100, 50, 42.9, 52.4, 11.7, 53.8, -100.6 },
}
local SWEEP_CHARGED = {
	{ -100, -60, -20.2, -4.1, -24.5, 72.8, -48.4 },
	{ -80, -48, -12, 3.1, -22.5, 70.1, -53.2 },
	{ -50, -30, -0.9, 11, -17.9, 66.6, -60.7 },
	{ -20, -12, 10.1, 16.8, -12.3, 61.9, -67.7 },
	{ 0, 0, 18.3, 19.6, -7.6, 56.9, -72 },
	{ 20, 12, 21.6, 24.4, -5.3, 57.8, -77.1 },
	{ 50, 30, 31, 31.5, -1.2, 54.6, -85.3 },
	{ 80, 48, 42.5, 39.4, 2.9, 48, -92.4 },
	{ 100, 60, 52.3, 45.7, 5.5, 40.6, -96.4 },
}
Struggle.SWEEP_FROM = SWEEP_TAP[1][1]
Struggle.SWEEP_TO = SWEEP_TAP[#SWEEP_TAP][1]

local function smooth(k: number): number
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end

function Struggle.BlendPose(a: Pose, b: Pose, k: number): Pose
	return {
		Twist = a.Twist + (b.Twist - a.Twist) * k,
		Pitch = a.Pitch + (b.Pitch - a.Pitch) * k,
		Yaw = a.Yaw + (b.Yaw - a.Yaw) * k,
		Roll = a.Roll + (b.Roll - a.Roll) * k,
		Elbow = a.Elbow + (b.Elbow - a.Elbow) * k,
		Tilt = a.Tilt + (b.Tilt - a.Tilt) * k,
	}
end

-- The strike's pose with the bat at `angle` (degrees round the swinger, + to the left).
function Struggle.SweepPose(angle: number, charged: boolean): Pose
	local rows = if charged then SWEEP_CHARGED else SWEEP_TAP
	local index = 1
	while index < #rows - 1 and angle > rows[index + 1][1] do
		index += 1
	end
	local a, b = rows[index], rows[index + 1]
	local k = math.clamp((angle - a[1]) / (b[1] - a[1]), 0, 1)
	local function at(column: number): number
		return a[column] + (b[column] - a[column]) * k
	end
	return { Twist = at(2), Pitch = at(3), Yaw = at(4), Roll = at(5), Elbow = at(6), Tilt = at(7) }
end

-- `held` seconds into a press: from READY into the wind-up, deepening toward WIND_CHARGED as the
-- charge builds (CHARGE seconds).
function Struggle.WindPose(held: number): Pose
	local wind = Struggle.BlendPose(Struggle.WIND, Struggle.WIND_CHARGED, smooth(held / Struggle.CHARGE))
	return Struggle.BlendPose(Struggle.READY, wind, smooth(held / Struggle.WIND_IN))
end

-- `k` (0..1) through the strike's SWEEP, from the wind-up pose `from`: the bat whips round fast and
-- slows into the follow-through, past the arc on the left.
function Struggle.StrikePose(from: Pose, k: number, charged: boolean): Pose
	local u = 1 - (1 - math.clamp(k, 0, 1)) ^ 2
	local swept = Struggle.SweepPose(Struggle.SWEEP_FROM + (Struggle.SWEEP_TO - Struggle.SWEEP_FROM) * u, charged)
	return Struggle.BlendPose(from, swept, smooth(u / 0.2))
end

return Struggle

-- Slaparazzi's shared rules: where the photo frame is at any moment, how many points a spot in the
-- frame is worth, and how far a slap reaches. The server scores and judges slaps with these; the
-- client half draws the frame, picks slap targets and shows the score rings with the very same
-- numbers, so what a player sees on their screen is what the server counts (owner: "the precision
-- games will feel super bad if we dont").

local Slaparazzi = {}

-- The frame's scoring rings (studs from its middle, flat): inside RINGS[1] is worth 3 points,
-- inside RINGS[2] 2 and inside RINGS[3] 1. The SlaparazziFrame mesh draws each ring's line with its
-- outer edge on these radii (measured: tools/meshgen/props/Slaparazzi.py).
Slaparazzi.RINGS = { 3.6, 7.2, 11 }
Slaparazzi.POINTS = { 3, 2, 1 }
-- A body half over a ring's line counts as in it (the middle of a body is about this far from its
-- side; owner: "clean up all hit boxes"). The HUD's IN THE SHOT uses the same rule.
Slaparazzi.EDGE = 0.5

-- A slap reaches this far, root to root (an arm and the big glove, plus half the other's body).
Slaparazzi.REACH = 6.5
-- The client only offers targets this close, so a slap it shows as a hit never comes back a miss.
Slaparazzi.CLIENT_REACH = 6
-- A slap goes to someone in front: the cosine of the widest angle from where the slapper faces.
Slaparazzi.FACING = -0.2
-- Bodies this close count from any side.
Slaparazzi.TOUCHING = 3
Slaparazzi.COOLDOWN = 1.5 -- seconds between slaps
Slaparazzi.STUN = 0.8 -- a slapped character is ragdolled this long (and can't slap)
Slaparazzi.KNOCK = 50 -- studs/s, flat
Slaparazzi.LIFT = 24 -- studs/s, up

export type Frame = {
	X0: number,
	Z0: number,
	X1: number,
	Z1: number,
	T0: number, -- server time the frame starts gliding from (X0, Z0)
	T1: number, -- ... and arrives at (X1, Z1)
	Shot: number, -- server time of the next photo
	N: number, -- that photo's number (1..Of)
	Of: number,
	Y: number, -- the stage floor's height
	Done: boolean?, -- every photo has been taken
}

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- The frame's middle (flat X, Z) at server time t.
function Slaparazzi.FrameAt(frame: Frame, t: number): (number, number)
	if t >= frame.T1 or frame.T1 <= frame.T0 then
		return frame.X1, frame.Z1
	end
	local a = smooth((t - frame.T0) / (frame.T1 - frame.T0))
	return frame.X0 + (frame.X1 - frame.X0) * a, frame.Z0 + (frame.Z1 - frame.Z0) * a
end

-- Points for standing `distance` studs (flat) from the frame's middle: 3, 2, 1 or 0.
function Slaparazzi.PointsFor(distance: number): number
	for index, radius in Slaparazzi.RINGS do
		if distance <= radius + Slaparazzi.EDGE then
			return Slaparazzi.POINTS[index]
		end
	end
	return 0
end

-- Whether a slap from `from` (facing `look`) reaches someone standing at `at`.
function Slaparazzi.Reaches(from: Vector3, look: Vector3, at: Vector3, reach: number): boolean
	local flat = Vector3.new(at.X - from.X, 0, at.Z - from.Z)
	local distance = flat.Magnitude
	if distance > reach or math.abs(at.Y - from.Y) > 5 then
		return false
	end
	if distance <= Slaparazzi.TOUCHING then
		return true
	end
	local facing = Vector3.new(look.X, 0, look.Z)
	if facing.Magnitude < 0.01 then
		return true
	end
	return facing.Unit:Dot(flat.Unit) >= Slaparazzi.FACING
end

return Slaparazzi

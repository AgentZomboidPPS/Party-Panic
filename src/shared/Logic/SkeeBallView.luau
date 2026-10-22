--!strict
-- The Skee-Ball play screen's numbers (owner: "Can we also add skiball to the lobby?"): where the
-- camera sits behind your lane, and how a drag on the screen becomes a roll's aim and power.
-- Controllers/SkeeBallController uses them, tests/SkeeBallView.spec.luau checks every layout
-- with them (from the waiting ball a drag to the screen's bottom edge always reaches full power,
-- so every target can be hit; the ring board keeps clear of the vote cards and the top bar), and
-- tools/checks/skeeball_game.luau checks on a real server that no lobby scenery is next to a
-- camera. Leaf module: plain numbers, no requires, no Roblox APIs (Lune runs the tests).
--
-- Poses are in a machine's frame (the frame Logic/SkeeBall's ToMachine gives: x across, y up,
-- the player's side at -Z). Every pose keeps the same eye, just behind and above the player's
-- head, and only turns and widens the view; machine 1's eye is about 2.5 studs in front of the
-- vote stage's light tower, which stays behind the camera.
--   Play       the ball waits three quarters of the way down the screen, the 100 cups a quarter.
--   Vote       while the vote cards are up (along the bottom on every screen; phones' moved there,
--              owner: "Can we make the vote buttons go to the bottom middle"): the ball and the lane
--              stay above them (the ball 60% down), the board's top under the top bar or banner.
-- A drag: pull down from anywhere on the lane and let go; sideways aims (the ball goes the other
-- way, like a slingshot). Full power is a pull of POWER_REACH of the screen's height, or down to
-- the bottom edge when the drag starts lower than that leaves room for (the waiting ball sits in
-- the lower part of the screen), but never shorter than MIN_REACH.

local SkeeBallView = {}

export type Pose = { Eye: { number }, Look: { number }, Fov: number }

local EYE = { 0, 10, -14.2 }
SkeeBallView.Poses = {
	Play = { Eye = EYE, Look = { 0, 2.6, 0.9 }, Fov = 54 },
	Vote = { Eye = EYE, Look = { 0, 1.25, -1 }, Fov = 66 },
} :: { [string]: Pose }

SkeeBallView.POWER_REACH = 0.32 -- a pull this much of the screen's height is full power
SkeeBallView.MIN_REACH = 0.15 -- but full power never takes less than this
SkeeBallView.EDGE = 6 -- pixels a finger can't quite use at the bottom edge
SkeeBallView.AIM_REACH = 0.17 -- a pull this much of the screen's width sideways is full aim

local function sub(a: { number }, b: { number }): { number }
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

local function dot(a: { number }, b: { number }): number
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

local function cross(a: { number }, b: { number }): { number }
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

local function unit(a: { number }): { number }
	local length = math.sqrt(dot(a, a))
	return { a[1] / length, a[2] / length, a[3] / length }
end

-- Where a point of the machine's frame shows on a screen `aspect` wide per unit of height, for a
-- camera in `pose` (vertical field of view, like Roblox's): fractions of the screen from its top
-- and from its left edge.
function SkeeBallView.Project(pose: Pose, aspect: number, x: number, y: number, z: number): (number, number)
	local forward = unit(sub(pose.Look, pose.Eye))
	local right = unit(cross(forward, { 0, 1, 0 }))
	local up = cross(right, forward)
	local d = sub({ x, y, z }, pose.Eye)
	local depth = dot(d, forward)
	local half = math.tan(math.rad(pose.Fov) / 2)
	return 0.5 - dot(d, up) / depth / (2 * half), 0.5 + dot(d, right) / depth / (2 * half * aspect)
end

-- How far down a pull starting at `startY` goes for full power, on a screen `height` tall whose
-- bottom edge is at `bottom` (the same space as the touch positions).
function SkeeBallView.PowerReach(startY: number, height: number, bottom: number): number
	local room = bottom - startY - SkeeBallView.EDGE
	return math.clamp(room, height * SkeeBallView.MIN_REACH, height * SkeeBallView.POWER_REACH)
end

-- The roll a drag from (x0, y0) to (x1, y1) makes: aim (-1 left .. 1 right) and power (0 .. 1).
function SkeeBallView.Drag(
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	width: number,
	height: number,
	bottom: number
): (number, number)
	local power = math.clamp((y1 - y0) / SkeeBallView.PowerReach(y0, height, bottom), 0, 1)
	local aim = math.clamp(-(x1 - x0) / (width * SkeeBallView.AIM_REACH), -1, 1)
	return aim, power
end

return SkeeBallView

--!strict
-- The sky of Parasol Plummet as plain math the server, the client half, the bots and the specs all
-- share, so everyone agrees where each faller drifts and where every thrown coin flies.
-- Leaf module: no requires, no Roblox APIs (positions are x across the sky, y up, in studs, measured
-- from the middle of the play area; the server and clients add the arena's origin).
--
-- A faller holds an umbrella. OPEN it floats up slowly (RISE), SHUT it drops fast (DROP); either way
-- the stick steers left and right (faster with the umbrella open: it catches the wind). The sky is a
-- box HALF_W wide either side and Y_MIN..Y_MAX tall: fallers stop at its edges. A hammer STUN snaps
-- the umbrella shut and takes the steering away for a moment.
--
-- Thrown things (coins, coin bags, hammers) fly on a fixed arc from their release (At, X0, Y0, VX,
-- VY) under GRAVITY, so a client can draw one from a single event and the server judges catches
-- against the same arc. Catching is a shape test against what the player sees drawn: the body (a
-- circle round the torso), and the umbrella (an ellipse round the open canopy, or a capsule round the
-- furled one). The numbers match the meshes in tools/meshgen/props/ParasolPlummet.py.
--
-- Coins and bags are lobbed high over the sky and come down on a spot away from everyone, and they
-- can only be caught on the way down, inside the middle of the sky (Sim.Catchable): the throwers'
-- hands are just outside the sky, so a coin still rising past a wall would otherwise hand a free
-- catch to anyone parked there (owner's review: "parking at a side wall beats playing").

local Sim = {}

-- The sky box (a faller's root position, in studs from the play area's middle).
Sim.HALF_W = 34
Sim.Y_MIN = -15
Sim.Y_MAX = 10

-- Faller motion (studs/s and 1/s).
Sim.RISE = 5 -- umbrella open: a slow float upward
Sim.DROP = -17 -- umbrella shut: a fast drop
Sim.STEER_OPEN = 15
Sim.STEER_SHUT = 10
Sim.ACCEL_X = 7
Sim.ACCEL_OPEN = 2.6 -- how quickly an opened umbrella brakes a drop
Sim.ACCEL_SHUT = 4.5

-- Hammer hits.
Sim.STUN = 1.5 -- seconds stunned (umbrella shut, no steering)
Sim.SAFE = 1.0 -- seconds after a stun when no hammer can hit again

-- Thrown things.
Sim.GRAVITY = -7
Sim.THROWER_X = 43 -- the throwers' clouds, either side of the sky
Sim.THROWER_BASE = { 1, -13 } -- their resting heights (upper and lower cloud on each side)
Sim.THROWER_BOB = 2 -- how far their clouds bob up and down
Sim.WINDUP = 0.55 -- seconds a thrower winds up before the throw leaves its hand
Sim.LIFE = 9 -- no thrown thing lives longer than this

Sim.Kinds = {
	-- (Height: the drawn mesh's; Middle: the point on the arc, up from the mesh's base: a hammer flies
	-- and spins about the middle of its head.)
	Coin = { Value = 1, Radius = 1.4, Height = 2.8, Middle = 1.4 },
	Bag = { Value = 5, Radius = 1.8, Height = 3.6, Middle = 1.8 },
	Hammer = { Value = 0, Radius = 1.4, Height = 4.2, Middle = 3.5 },
}

-- Where coins and bags can be caught (see the top): coming down, at most CATCH_X from the middle and
-- no higher than CATCH_TOP. Lobs peak LOB_PEAK above the top of the sky.
Sim.CATCH_X = Sim.HALF_W - 8
Sim.CATCH_TOP = Sim.Y_MAX - 3
Sim.LOB_PEAK = { 11, 13 }
Sim.MAX_LEAN = 0.05 -- radians a faller's drawn body (and umbrella) may lean while steering

-- Hit shapes, relative to the faller's root. The umbrella is held up over the head in both hands,
-- its base (the handle's hook) UMBRELLA_BASE above the root; the mesh is 5.6 tall with the canopy's
-- rim 3.9 up and its top at 5.4, 3.8 across either way, furled from 1.2 to 5.2.
Sim.UMBRELLA_BASE = 2.6
-- The body: an upright capsule as wide as the faller's hips and legs (arms are up on the umbrella),
-- from its feet to its shoulders with the round ends. It was a circle 2 studs round the middle, so a
-- hammer that visibly flew past the hips still stunned (owner: "clean up all hit boxes").
Sim.BODY_Y0 = -1.9 -- the capsule's core, from here...
Sim.BODY_Y1 = 1.5 -- ...to here
Sim.BODY_R = 1.1
Sim.CANOPY_Y = 7.2 -- middle of the open canopy
Sim.CANOPY_W = 3.8 -- its half width
Sim.CANOPY_H = 0.9 -- its half height
Sim.FURL_Y0 = 3.8 -- the furled umbrella, a capsule from here...
Sim.FURL_Y1 = 7.8 -- ...to here
Sim.FURL_R = 0.55

export type Faller = { X: number, Y: number, VX: number, VY: number }
export type Throw = { At: number, X0: number, Y0: number, VX: number, VY: number }

local function approach(value: number, target: number, rate: number, dt: number): number
	return value + (target - value) * (1 - math.exp(-rate * dt))
end

-- Moves a faller on for `dt` seconds: `steer` -1..1 (right is +x), `open` the umbrella. A stunned
-- faller's umbrella is shut and it can't steer.
function Sim.Step(f: Faller, steer: number, open: boolean, stunned: boolean, dt: number)
	if stunned then
		open = false
		steer = 0
	end
	steer = math.clamp(steer, -1, 1)
	local targetX = steer * (if open then Sim.STEER_OPEN else Sim.STEER_SHUT)
	local targetY = if open then Sim.RISE else Sim.DROP
	f.VX = approach(f.VX, targetX, Sim.ACCEL_X, dt)
	f.VY = approach(f.VY, targetY, if open then Sim.ACCEL_OPEN else Sim.ACCEL_SHUT, dt)
	f.X += f.VX * dt
	f.Y += f.VY * dt
	if f.X < -Sim.HALF_W then
		f.X = -Sim.HALF_W
		f.VX = math.max(f.VX, 0)
	elseif f.X > Sim.HALF_W then
		f.X = Sim.HALF_W
		f.VX = math.min(f.VX, 0)
	end
	if f.Y < Sim.Y_MIN then
		f.Y = Sim.Y_MIN
		f.VY = math.max(f.VY, 0)
	elseif f.Y > Sim.Y_MAX then
		f.Y = Sim.Y_MAX
		f.VY = math.min(f.VY, 0)
	end
end

-- Where a thrown thing is at time `t` (before its release it's in the thrower's hand: X0, Y0).
function Sim.ItemAt(item: Throw, t: number): (number, number)
	local s = math.max(0, t - item.At)
	return item.X0 + item.VX * s, item.Y0 + item.VY * s + 0.5 * Sim.GRAVITY * s * s
end

-- Whether a thrown thing at time `t` has left the sky for good (below it, or past either side).
function Sim.Gone(item: Throw, t: number): boolean
	if t - item.At > Sim.LIFE then
		return true
	end
	local x, y = Sim.ItemAt(item, t)
	local falling = item.VY + Sim.GRAVITY * math.max(0, t - item.At) < 0
	return (falling and y < Sim.Y_MIN - 9) or math.abs(x) > Sim.HALF_W + 14
end

-- Whether a coin or bag can be caught at time `t`: falling, and inside the catching part of the sky.
function Sim.Catchable(item: Throw, t: number): boolean
	local s = t - item.At
	if s < 0 or item.VY + Sim.GRAVITY * s >= 0 then
		return false
	end
	local x, y = Sim.ItemAt(item, t)
	return math.abs(x) <= Sim.CATCH_X and y <= Sim.CATCH_TOP
end

-- A thrower's cloud at time `t` (index 1..4: 1 and 2 on the left, upper and lower; 3 and 4 right).
function Sim.ThrowerAt(index: number, t: number): (number, number, number)
	local side = if index <= 2 then -1 else 1
	local base = Sim.THROWER_BASE[(index - 1) % 2 + 1]
	local y = base + Sim.THROWER_BOB * math.sin(t * 0.55 + index * 1.7)
	return side * Sim.THROWER_X, y, side
end

-- Where a throw leaves a thrower's hand (relative to its cloud's position): its raised right hand.
-- The throwers are the same mesh turned to face the camera (not mirrored), so that hand is on the
-- left of both: outside on the left cloud, inside on the right one.
function Sim.HandOffset(side: number): (number, number)
	return if side < 0 then -1.8 else -2.1, 6.6
end

-- Whether something of `radius` at (x, y) touches a faller at (fx, fy) with its umbrella `open` or
-- shut. `grow` widens (or with a negative value narrows) every shape.
function Sim.Touches(fx: number, fy: number, open: boolean, x: number, y: number, radius: number, grow: number): boolean
	local dx, dy = x - fx, y - fy
	local body = Sim.BODY_R + radius + grow
	local by = dy - math.clamp(dy, Sim.BODY_Y0, Sim.BODY_Y1)
	if body > 0 and dx * dx + by * by <= body * body then
		return true
	end
	if open then
		local w = Sim.CANOPY_W + radius + grow
		local h = Sim.CANOPY_H + radius + grow
		local cy = dy - Sim.CANOPY_Y
		return w > 0 and h > 0 and (dx / w) ^ 2 + (cy / h) ^ 2 <= 1
	end
	local cy = math.clamp(dy, Sim.FURL_Y0, Sim.FURL_Y1)
	local r = Sim.FURL_R + radius + grow
	return dx * dx + (dy - cy) ^ 2 <= r * r
end

-- Launch speeds that carry a throw from (x0, y0) to (x, y) in `seconds`.
function Sim.Aim(x0: number, y0: number, x: number, y: number, seconds: number): (number, number)
	local vx = (x - x0) / seconds
	local vy = (y - y0 - 0.5 * Sim.GRAVITY * seconds * seconds) / seconds
	return vx, vy
end

-- Where faller `index` of `count` starts: spread across the top of the sky.
function Sim.StartAt(index: number, count: number): (number, number)
	local span = Sim.HALF_W * 2 - 8
	local x = if count <= 1 then 0 else -span / 2 + span * (index - 1) / (count - 1)
	return x, Sim.Y_MAX - 3 - (index % 2) * 3
end

-- The depth offset (studs toward the camera) of faller `index`, so fallers side by side don't
-- draw through each other. Only for looks: catching is judged in the flat sky.
function Sim.Depth(index: number): number
	return ((index - 1) % 3 - 1) * 0.8
end

return Sim

--!strict
-- Bumper Ballers: how a ball answers its stick, as plain math shared by the server (it rolls bots'
-- balls, and every ball on test servers without physics) and each player's device (it rolls their
-- own ball), so players and bots always roll alike. Leaf module: no requires, no Roblox APIs (flat
-- x and z numbers), so tests/BumperDrive.spec.luau runs it and `lune run tools/checks/bumper_drive`
-- prints how it feels next to the drive it replaced.
--
-- Owner, on a phone: "Bumper balls control scheme is really bad on mobile". The stick used to act
-- through one slow drag (push = stick * Accel - velocity * Accel / MaxSpeed): 1.2 s to full speed,
-- 12 studs of coasting after letting go and a second to turn a corner, so a dodge always came too
-- late. A ball's velocity is now two parts:
--   * Steering: what the stick asks for (stick * MaxSpeed), closed on quickly (SteerGain per second,
--     pushing with at most SteerAccel): 90% of full speed in 0.37 s, about 4 studs (half a ball) of
--     glide after letting go, a corner turned in 0.35 s. Still a heavy rolling ball (it winds up,
--     glides and swings wide in a turn), just not one on ice.
--   * Carry: what bumps gave the ball. It fades the way all motion used to (Accel / MaxSpeed per
--     second, less of it for Relief seconds), so a bump slides a rider exactly as far as before: the
--     bumps stay as gentle as the owner asked ("you get bounced off way too quickly"). For those
--     Relief seconds the ball also steers the old way, so riding out a bump takes what it always did.
-- Steering grips only while the ball sits on the island top (BumperDrive.Grips): a ball tipping
-- over the rim or in the air steers the old, weak way, so saving yourself at the edge is exactly as
-- hard as it always was (a quick stick doesn't yank a falling ball back up onto the island).

local BumperDrive = {}
BumperDrive.__index = BumperDrive

export type Tuning = {
	MaxSpeed: number, -- studs/s: top speed from steering
	SteerGain: number, -- per second: how fast steering closes on what the stick asks for
	SteerAccel: number, -- studs/s^2: the most steering pushes with
	Accel: number, -- studs/s^2 of the old drive at full stick: right after a bump, off the island, and the carry's fade
	Relief: number, -- seconds after a bump with less drag (so bumps carry) and the old steering
	ReliefDrag: number, -- drag multiplier during that time
}

BumperDrive.Tuning = table.freeze({
	MaxSpeed = 24,
	SteerGain = 6,
	SteerAccel = 110,
	Accel = 46,
	Relief = 0.3,
	ReliefDrag = 0.6,
}) :: Tuning

-- A rolling solid ball needs 7/5 of the push a sliding one would (it spins up too), so a drive push
-- is acceleration * (ball mass * RollMass + rider mass). A push through the ball's middle (a bump) is
-- the other way round: once the ball grips the ground again it keeps
-- (ball + rider) / (ball * RollMass + rider) of the speed.
BumperDrive.RollMass = 1.4

-- How far (studs) a ball's middle may be off its resting height and still grip the island top.
BumperDrive.GripHeight = 1

export type Drive = {
	Tuning: Tuning,
	CarryX: number,
	CarryZ: number,
	ReliefUntil: number,
	Bump: (self: Drive, now: number, x: number, z: number, relief: number?) -> (),
	Relieved: (self: Drive, now: number) -> boolean,
	Step: (
		self: Drive,
		now: number,
		dt: number,
		vx: number,
		vz: number,
		ux: number,
		uz: number,
		grip: boolean?
	) -> (number, number),
}

-- A drive for one ball. `tuning` may be the server's MG_Tuning (other keys are ignored, missing
-- ones take the defaults above).
function BumperDrive.new(tuning: { [string]: any }?): Drive
	local given = tuning or {}
	local full = {}
	for key, value in BumperDrive.Tuning :: any do
		full[key] = if type(given[key]) == "number" then given[key] else value
	end
	return setmetatable({
		Tuning = full :: any,
		CarryX = 0,
		CarryZ = 0,
		ReliefUntil = -math.huge,
	}, BumperDrive) :: any
end

-- Whether a ball can steer hard: its middle is over the island top (`fromCenter`, its flat distance
-- from the island's middle, inside `islandRadius`) and it rests on it (`height`, how far its middle
-- is over the top, within GripHeight of `ballRadius`). Past the rim it is tipping off; much higher
-- it is in the air, much lower it is falling.
function BumperDrive.Grips(fromCenter: number, height: number, islandRadius: number, ballRadius: number): boolean
	return fromCenter <= islandRadius and math.abs(height - ballRadius) <= BumperDrive.GripHeight
end

-- The ball took a push: (x, z) is the flat speed it now rolls on with (studs/s), `relief` the seconds
-- of bump relief (Tuning.Relief for a bump, 0 or nil for two balls eased apart).
function BumperDrive.Bump(self: Drive, now: number, x: number, z: number, relief: number?)
	self.CarryX += x
	self.CarryZ += z
	if relief and relief > 0 then
		self.ReliefUntil = math.max(self.ReliefUntil, now + relief)
	end
end

function BumperDrive.Relieved(self: Drive, now: number): boolean
	return now < self.ReliefUntil
end

-- The flat acceleration (studs/s^2) to push the ball with for the next `dt` seconds (one frame),
-- for a ball rolling at (vx, vz) whose stick says (ux, uz) (length 1 at most). `grip` false: the
-- ball is off the island top (see BumperDrive.Grips), so it steers the old, weak way.
function BumperDrive.Step(
	self: Drive,
	now: number,
	dt: number,
	vx: number,
	vz: number,
	ux: number,
	uz: number,
	grip: boolean?
): (number, number)
	local tuning = self.Tuning
	dt = math.clamp(dt, 1 / 480, 0.25)
	local relief = now < self.ReliefUntil
	local drag = tuning.Accel / tuning.MaxSpeed * (if relief then tuning.ReliefDrag else 1)
	-- The carry fades as all motion used to (frame by frame, exactly as the old drag took it).
	local carryX, carryZ = self.CarryX, self.CarryZ
	local fade = math.min(1, drag * dt)
	local ax, az = -carryX * fade / dt, -carryZ * fade / dt
	self.CarryX, self.CarryZ = carryX * (1 - fade), carryZ * (1 - fade)
	if self.CarryX * self.CarryX + self.CarryZ * self.CarryZ < 0.01 then
		self.CarryX, self.CarryZ = 0, 0
	end
	-- Steering moves the rest of the velocity.
	local steerX, steerZ = vx - carryX, vz - carryZ
	if relief or grip == false then
		-- Just bumped, or off the island: the old drive (Accel at full stick, against the same drag
		-- as the carry).
		return ax + ux * tuning.Accel - steerX * drag, az + uz * tuning.Accel - steerZ * drag
	end
	-- (One slow frame closes at most 80% of the gap, so a hitch never overshoots and wobbles.)
	local gain = math.min(tuning.SteerGain, 0.8 / dt)
	local pushX = (ux * tuning.MaxSpeed - steerX) * gain
	local pushZ = (uz * tuning.MaxSpeed - steerZ) * gain
	local size = math.sqrt(pushX * pushX + pushZ * pushZ)
	if size > tuning.SteerAccel then
		pushX, pushZ = pushX * tuning.SteerAccel / size, pushZ * tuning.SteerAccel / size
	end
	return ax + pushX, az + pushZ
end

return BumperDrive

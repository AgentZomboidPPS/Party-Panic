-- Prints how a Bumper Ballers ball answers its stick: the shared drive (src/shared/Logic/BumperDrive)
-- next to the drive it replaced (one slow drag on all motion), in the moments that decide a round.
-- A frame is 1/60 s (1/30 s in brackets): each frame's push is held until the next, as on a device
-- or the server, and the motion in between is stepped at 240 Hz like Roblox's physics.
--   lune run tools/checks/bumper_drive
local BumperDrive = require("../../src/shared/Logic/BumperDrive")

local T = BumperDrive.Tuning
local FULL_HIT = 7 + 0.85 * T.MaxSpeed -- a full-speed ball into a still one (server BUMP_BASE, BUMP_GAIN)
local BIG_HIT = FULL_HIT * 1.4 -- the same with BIG BUMPS

type Drive = {
	Bump: (self: any, now: number, x: number, z: number, relief: number?) -> (),
	Step: (self: any, now: number, dt: number, vx: number, vz: number, ux: number, uz: number) -> (number, number),
}

-- The drive before: push = stick * Accel - velocity * Accel / MaxSpeed (less drag for Relief s).
local function before(): Drive
	local reliefUntil = -math.huge
	return {
		Bump = function(_, now: number, _x: number, _z: number, relief: number?)
			if relief and relief > 0 then
				reliefUntil = math.max(reliefUntil, now + relief)
			end
		end,
		Step = function(_, now: number, _dt: number, vx: number, vz: number, ux: number, uz: number)
			local drag = T.Accel / T.MaxSpeed * (if now < reliefUntil then T.ReliefDrag else 1)
			return ux * T.Accel - vx * drag, uz * T.Accel - vz * drag
		end,
	}
end

local function after(): Drive
	return BumperDrive.new() :: any
end

-- The shared drive for a ball off the island top (tipping over the rim, or in the air).
local function offIsland(): Drive
	local drive = BumperDrive.new()
	return {
		Bump = function(_, now: number, x: number, z: number, relief: number?)
			drive:Bump(now, x, z, relief)
		end,
		Step = function(_, now: number, dt: number, vx: number, vz: number, ux: number, uz: number)
			return drive:Step(now, dt, vx, vz, ux, uz, false)
		end,
	}
end

type Sample = { T: number, X: number, Z: number, VX: number, VZ: number }

-- Rolls a ball from (0, 0) at velocity (vx, vz) for `seconds`; `stick(t)` gives the stick, `hit` an
-- optional bump along +x at t = 0.
local function roll(
	make: () -> Drive,
	fps: number,
	seconds: number,
	stick: (number) -> (number, number),
	vx: number,
	vz: number,
	hit: number?
): { Sample }
	local drive = make()
	local frame, physics = 1 / fps, 1 / 240
	local x, z, t, nextFrame, ax, az = 0, 0, 0, 0, 0, 0
	if hit then
		vx += hit
		drive:Bump(0, hit, 0, T.Relief)
	end
	local samples = {}
	while t < seconds do
		if t >= nextFrame - 1e-9 then
			local ux, uz = stick(t)
			ax, az = drive:Step(t, frame, vx, vz, ux, uz)
			nextFrame += frame
		end
		vx += ax * physics
		vz += az * physics
		x += vx * physics
		z += vz * physics
		t += physics
		table.insert(samples, { T = t, X = x, Z = z, VX = vx, VZ = vz })
	end
	return samples
end

local function first(samples: { Sample }, test: (Sample) -> boolean): Sample
	for _, sample in samples do
		if test(sample) then
			return sample
		end
	end
	return samples[#samples]
end

local function farthest(samples: { Sample }): number
	local best = 0
	for _, sample in samples do
		best = math.max(best, sample.X)
	end
	return best
end

local function constant(ux: number, uz: number): (number) -> (number, number)
	return function()
		return ux, uz
	end
end

-- Each row: a label and a function giving the number for a drive at a frame rate.
local rows: { { Label: string, Measure: (() -> Drive, number) -> number } } = {
	{
		Label = "start: seconds to 90% of top speed",
		Measure = function(make, fps)
			return first(roll(make, fps, 3, constant(1, 0), 0, 0), function(s)
				return s.VX >= 0.9 * T.MaxSpeed
			end).T
		end,
	},
	{
		Label = "let go at top speed: seconds to stop",
		Measure = function(make, fps)
			return first(roll(make, fps, 4, constant(0, 0), T.MaxSpeed, 0), function(s)
				return s.VX < 1
			end).T
		end,
	},
	{
		Label = "let go at top speed: studs rolled on",
		Measure = function(make, fps)
			return farthest(roll(make, fps, 4, constant(0, 0), T.MaxSpeed, 0))
		end,
	},
	{
		Label = "brake (stick back): seconds to stop",
		Measure = function(make, fps)
			return first(roll(make, fps, 3, constant(-1, 0), T.MaxSpeed, 0), function(s)
				return s.VX <= 0
			end).T
		end,
	},
	{
		Label = "brake (stick back): studs to stop",
		Measure = function(make, fps)
			return farthest(roll(make, fps, 3, constant(-1, 0), T.MaxSpeed, 0))
		end,
	},
	{
		Label = "turn a corner: seconds to the new way",
		Measure = function(make, fps)
			return first(roll(make, fps, 3, constant(0, 1), T.MaxSpeed, 0), function(s)
				return s.VZ > 0 and math.abs(math.atan2(s.VX, s.VZ)) < math.rad(10)
			end).T
		end,
	},
	{
		Label = "turn a corner: studs run on the old way",
		Measure = function(make, fps)
			return farthest(roll(make, fps, 3, constant(0, 1), T.MaxSpeed, 0))
		end,
	},
	{
		Label = "turn around: seconds to 90% speed back",
		Measure = function(make, fps)
			return first(roll(make, fps, 4, constant(-1, 0), T.MaxSpeed, 0), function(s)
				return s.VX <= -0.9 * T.MaxSpeed
			end).T
		end,
	},
	{
		Label = "dodge a ball's width aside: seconds",
		Measure = function(make, fps)
			return first(roll(make, fps, 3, constant(0, 1), T.MaxSpeed, 0), function(s)
				return s.Z >= 8
			end).T
		end,
	},
	{
		Label = `bumped ({FULL_HIT} studs/s), no stick: slide`,
		Measure = function(make, fps)
			return farthest(roll(make, fps, 6, constant(0, 0), 0, 0, FULL_HIT))
		end,
	},
	{
		Label = "bumped, stick back at once: slide",
		Measure = function(make, fps)
			return farthest(roll(make, fps, 6, constant(-1, 0), 0, 0, FULL_HIT))
		end,
	},
	{
		Label = "bumped, stick back after 0.3 s: slide",
		Measure = function(make, fps)
			return farthest(roll(make, fps, 6, function(t)
				return if t >= 0.3 then -1 else 0, 0
			end, 0, 0, FULL_HIT))
		end,
	},
	{
		Label = "BIG BUMP, no stick: slide",
		Measure = function(make, fps)
			return farthest(roll(make, fps, 6, constant(0, 0), 0, 0, BIG_HIT))
		end,
	},
	{
		Label = "BIG BUMP, stick back after 0.3 s: slide",
		Measure = function(make, fps)
			return farthest(roll(make, fps, 6, function(t)
				return if t >= 0.3 then -1 else 0, 0
			end, 0, 0, BIG_HIT))
		end,
	},
}

local function pad(text: string, width: number): string
	return text .. string.rep(" ", math.max(0, width - #text))
end

print(
	`top speed {T.MaxSpeed} studs/s; steering: gain {T.SteerGain}/s, at most {T.SteerAccel} studs/s^2; bumps: Accel {T.Accel}, relief {T.Relief} s`
)
print(pad("", 42) .. "     before            after")
-- Off the island the shared drive steers the old way, so a save at the rim is as hard as before.
table.insert(rows, {
	Label = "off the island, pull back: seconds to turn",
	Measure = function(make, fps)
		local drive = if make == after then offIsland else make
		return first(roll(drive, fps, 3, constant(-1, 0), T.MaxSpeed, 0), function(s)
			return s.VX <= 0
		end).T
	end,
})
for _, row in rows do
	print(
		string.format(
			"%s %6.2f (%5.2f)   %6.2f (%5.2f)",
			pad(row.Label, 42),
			row.Measure(before, 60),
			row.Measure(before, 30),
			row.Measure(after, 60),
			row.Measure(after, 30)
		)
	)
end

-- Checks how a Bumper Ballers ball answers its stick (src/shared/Logic/BumperDrive): quick to speed
-- up, stop and turn, the same at 30 and 60 frames a second, steady through a slow frame, bumps
-- sliding a rider exactly as far as the old drive did, and a ball off the island steering the old,
-- weak way. `lune run tools/checks/bumper_drive` prints the numbers next to the old ones.
local TestKit = require("./TestKit")
local BumperDrive = require("../src/shared/Logic/BumperDrive")

local test, expectTrue = TestKit.test, TestKit.expectTrue
local T = BumperDrive.Tuning
local FULL_HIT = 7 + 0.85 * T.MaxSpeed -- a full-speed ball into a still one (the server's bump rule)

type Sample = { T: number, X: number, Z: number, VX: number, VZ: number }

-- Rolls a ball for `seconds` in frames of 1/fps (each frame's push held, motion stepped at 240 Hz).
-- `grip` false: the ball is off the island top the whole time.
local function roll(
	fps: number,
	seconds: number,
	stick: (number) -> (number, number),
	vx: number,
	vz: number,
	hit: number?,
	grip: boolean?
): ({ Sample }, BumperDrive.Drive)
	local drive = BumperDrive.new()
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
			ax, az = drive:Step(t, frame, vx, vz, ux, uz, grip)
			nextFrame += frame
		end
		vx += ax * physics
		vz += az * physics
		x += vx * physics
		z += vz * physics
		t += physics
		table.insert(samples, { T = t, X = x, Z = z, VX = vx, VZ = vz })
	end
	return samples, drive
end

local function first(samples: { Sample }, check: (Sample) -> boolean): Sample?
	for _, sample in samples do
		if check(sample) then
			return sample
		end
	end
	return nil
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

-- How far the old drive slid a still rider after a bump of `dv` with no stick (closed form):
-- less drag for Relief seconds, then the full drag.
local function oldSlide(dv: number): number
	local drag = T.Accel / T.MaxSpeed
	local relief = drag * T.ReliefDrag
	local left = dv * math.exp(-relief * T.Relief)
	return (dv - left) / relief + left / drag
end

test("BumperDrive: 90% of top speed in under 0.4 s, never past it", function()
	for _, fps in { 30, 60 } do
		local samples = roll(fps, 3, constant(1, 0), 0, 0)
		local fast = first(samples, function(s)
			return s.VX >= 0.9 * T.MaxSpeed
		end)
		expectTrue(fast and fast.T <= 0.4, `{fps} fps: 90% of top speed at {fast and fast.T}`)
		for _, s in samples do
			expectTrue(math.sqrt(s.VX * s.VX + s.VZ * s.VZ) <= T.MaxSpeed + 0.01, `{fps} fps: over top speed`)
		end
	end
end)

test("BumperDrive: letting go glides about half a ball, braking stops sooner", function()
	for _, fps in { 30, 60 } do
		local coast = roll(fps, 4, constant(0, 0), T.MaxSpeed, 0)
		local stopped = first(coast, function(s)
			return s.VX < 1
		end)
		expectTrue(stopped and stopped.T <= 0.55, `{fps} fps: stopped at {stopped and stopped.T}`)
		expectTrue(farthest(coast) <= 4.5, `{fps} fps: rolled on {farthest(coast)}`)
		expectTrue(farthest(coast) >= 2.5, `{fps} fps: still glides a little ({farthest(coast)})`)
		local brake = roll(fps, 3, constant(-1, 0), T.MaxSpeed, 0)
		expectTrue(farthest(brake) <= 3, `{fps} fps: braked in {farthest(brake)}`)
	end
end)

test("BumperDrive: a corner takes about a third of a second", function()
	for _, fps in { 30, 60 } do
		local turned = first(roll(fps, 3, constant(0, 1), T.MaxSpeed, 0), function(s)
			return s.VZ > 0 and math.abs(math.atan2(s.VX, s.VZ)) < math.rad(10)
		end)
		expectTrue(turned and turned.T <= 0.4, `{fps} fps: turned at {turned and turned.T}`)
	end
end)

test("BumperDrive: a slow frame never overshoots", function()
	-- A phone hitching: one frame of 0.25 s with the stick let go at top speed.
	local drive = BumperDrive.new()
	local ax = drive:Step(0, 0.25, T.MaxSpeed, 0, 0, 0)
	local after = T.MaxSpeed + ax * 0.25
	expectTrue(after >= 0 and after < T.MaxSpeed, `rolled back at {after}`)
end)

test("BumperDrive: a bump slides a rider as far as the old drive did", function()
	for _, hit in { FULL_HIT, FULL_HIT * 1.4 } do
		for _, fps in { 30, 60 } do
			local samples, drive = roll(fps, 6, constant(0, 0), 0, 0, hit)
			local slide, expected = farthest(samples), oldSlide(hit)
			expectTrue(math.abs(slide - expected) <= 0.03 * expected, `{fps} fps, {hit}: slid {slide}, old {expected}`)
			expectTrue(drive.CarryX == 0, "the carry fades away")
		end
	end
end)

test("BumperDrive: right after a bump it steers exactly the old way", function()
	local drive = BumperDrive.new()
	drive:Bump(10, 20, -5, T.Relief)
	local drag = T.Accel / T.MaxSpeed * T.ReliefDrag
	for _, case in { { 25, -3, 0.6, 0.8 }, { -4, 12, -1, 0 }, { 0, 0, 0, 0 } } do
		local vx, vz, ux, uz = case[1], case[2], case[3], case[4]
		local ax, az = drive:Step(10.1, 1 / 60, vx, vz, ux, uz)
		expectTrue(math.abs(ax - (ux * T.Accel - vx * drag)) < 1e-9, `x {ax}`)
		expectTrue(math.abs(az - (uz * T.Accel - vz * drag)) < 1e-9, `z {az}`)
	end
	expectTrue(drive:Relieved(10.29) and not drive:Relieved(10.31), "relief lasts Tuning.Relief")
end)

test("BumperDrive: off the island it steers the old, weak way", function()
	local drive = BumperDrive.new()
	local drag = T.Accel / T.MaxSpeed
	for _, case in { { 20, 0, -1, 0 }, { -4, 12, 0, 1 }, { 0, 0, 0, 0 } } do
		local vx, vz, ux, uz = case[1], case[2], case[3], case[4]
		local ax, az = drive:Step(0, 1 / 60, vx, vz, ux, uz, false)
		expectTrue(math.abs(ax - (ux * T.Accel - vx * drag)) < 1e-9, `x {ax}`)
		expectTrue(math.abs(az - (uz * T.Accel - vz * drag)) < 1e-9, `z {az}`)
	end
	-- Rolling off at top speed and pulling back hard: no faster a turnaround than the old drive.
	local back = first(roll(60, 2, constant(-1, 0), T.MaxSpeed, 0, nil, false), function(s)
		return s.VX <= 0
	end)
	expectTrue(back and back.T >= 0.34, `turned back off the island at {back and back.T}`)
end)

test("BumperDrive.Grips: on the island top only", function()
	local R, r = 44.6, 4
	expectTrue(BumperDrive.Grips(0, r, R, r), "middle of the island")
	expectTrue(BumperDrive.Grips(R, r + 0.5, R, r), "at the rim, a little hop")
	expectTrue(not BumperDrive.Grips(R + 0.5, r, R, r), "past the rim")
	expectTrue(not BumperDrive.Grips(10, r - 2, R, r), "falling")
	expectTrue(not BumperDrive.Grips(10, r + 3, R, r), "in the air")
end)

test("BumperDrive: steering never pushes harder than SteerAccel", function()
	local drive = BumperDrive.new()
	for _, case in { { T.MaxSpeed, 0, -1, 0 }, { 0, 0, 1, 0 }, { -T.MaxSpeed, 0, 0.7, 0.7 } } do
		local ax, az = drive:Step(0, 1 / 60, case[1], case[2], case[3], case[4])
		expectTrue(math.sqrt(ax * ax + az * az) <= T.SteerAccel + 1e-9, `pushed {ax}, {az}`)
	end
end)

test("BumperDrive.new keeps the server's numbers and fills in the rest", function()
	local drive = BumperDrive.new({ MaxSpeed = 30, Touch = 8.5 })
	expectTrue(drive.Tuning.MaxSpeed == 30, "MaxSpeed from the server")
	expectTrue(drive.Tuning.SteerGain == T.SteerGain, "SteerGain filled in")
	expectTrue((drive.Tuning :: any).Touch == nil, "other keys left out")
end)

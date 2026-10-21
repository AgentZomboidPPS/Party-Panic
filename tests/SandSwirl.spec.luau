-- Checks the Sinking Sands flow math: the closed-form spiral matches a step-by-step simulation, a
-- rebuilt schedule never changes the part clients may already be using, and the funnel profile
-- meets the hole and the rim where the meshes expect it.
local TestKit = require("./TestKit")
local SandSwirl = require("../src/shared/Logic/SandSwirl")

local test, expectTrue = TestKit.test, TestKit.expectTrue

local function near(a: number, b: number, tolerance: number, message: string)
	expectTrue(math.abs(a - b) <= tolerance, `{message}: {a} vs {b}`)
end

local function effects()
	return { Start = 1000, Length = 45, Flips = {}, Surges = {}, Pulls = {} }
end

test("SandSwirl.Height is flat at the rim and DEPTH deep at the hole", function()
	near(SandSwirl.Height(SandSwirl.RIM), 0, 1e-9, "rim")
	near(SandSwirl.Height(SandSwirl.RIM + 10), 0, 1e-9, "outside")
	near(SandSwirl.Height(SandSwirl.HOLE), -SandSwirl.DEPTH, 1e-9, "hole")
	expectTrue(SandSwirl.Height(20) < SandSwirl.Height(25), "the sand rises towards the rim")
end)

test("SandSwirl.Advance follows the flow field step by step", function()
	local fx = effects()
	table.insert(fx.Flips, 1003)
	table.insert(fx.Surges, 1003)
	table.insert(fx.Pulls, 1005)
	local segments = SandSwirl.Build(fx, 1000, 12)
	local r, a = 30, 0.4
	local x, z = SandSwirl.ToXZ(r, a)
	local dt = 0.0005
	local t = 1000.1
	while t < 1007 do
		local s, v = SandSwirl.FlowAt(segments, t)
		local pr, pa = SandSwirl.ToPolar(x, z)
		-- inward plus tangential (angle-increasing) velocity
		local ux, uz = math.cos(pa), math.sin(pa)
		x += (-ux * v + -uz * s) * dt
		z += (-uz * v + ux * s) * dt
		t += dt
		if pr <= SandSwirl.HOLE then
			break
		end
	end
	local r1, a1, sunk = SandSwirl.Advance(segments, r, a, 1000.1, t)
	local ex, ez = SandSwirl.ToXZ(r1, a1)
	if sunk then
		expectTrue(math.abs(sunk - t) < 0.05, `sank at {sunk}, simulated {t}`)
	else
		near(ex, x, 0.05, "x")
		near(ez, z, 0.05, "z")
	end
end)

test("SandSwirl.Advance can be split anywhere", function()
	local fx = effects()
	table.insert(fx.Flips, 1002)
	table.insert(fx.Surges, 1002)
	local segments = SandSwirl.Build(fx, 1000, 10)
	local r1, a1 = SandSwirl.Advance(segments, 31, 1, 1000, 1006.3, 0.8)
	local rm, am = SandSwirl.Advance(segments, 31, 1, 1000, 1002.17, 0.8)
	local r2, a2 = SandSwirl.Advance(segments, rm, am, 1002.17, 1006.3, 0.8)
	near(r1, r2, 1e-9, "radius")
	near(a1, a2, 1e-9, "angle")
end)

test("a new effect never changes the schedule before it starts", function()
	local fx = effects()
	local now = 1010.37
	local before = SandSwirl.Build(fx, now, 8)
	local start = SandSwirl.EffectStart(now)
	expectTrue(start >= now + SandSwirl.LEAD - 1e-9, "effects start after the lead")
	table.insert(fx.Flips, start)
	table.insert(fx.Surges, start)
	table.insert(fx.Pulls, start)
	local after = SandSwirl.Build(fx, now, 8)
	local t = now
	while t < start - 1e-6 do
		local s0, v0 = SandSwirl.FlowAt(before, t)
		local s1, v1 = SandSwirl.FlowAt(after, t)
		expectTrue(s0 == s1 and v0 == v1, `flow changed at {t} (effect at {start})`)
		t += 0.01
	end
	local sa = SandSwirl.FlowAt(after, start + 1.2)
	local sb = SandSwirl.FlowAt(before, start + 1.2)
	expectTrue(sa < 0 and sb > 0, "the swirl reversed")
end)

test("everything left on the sand reaches the hole", function()
	local segments = SandSwirl.Build(effects(), 1000, 8)
	local sink = SandSwirl.SinkTime(segments, 30, 1000)
	expectTrue(sink > 1000 and sink < 1030, `sinks at {sink}`)
	local heavy = SandSwirl.SinkTime(segments, 30, 1000, 0.5)
	expectTrue(heavy > sink, "heavy treasure sinks slower")
end)

test("walkers feel more pull near the hole and none outside the rim", function()
	local segments = SandSwirl.Build(effects(), 1000, 8)
	local inwardNear = SandSwirl.WalkerFlow(segments, SandSwirl.HOLE + 1, 1001)
	local inwardMid = SandSwirl.WalkerFlow(segments, 20, 1001)
	local inwardOut = SandSwirl.WalkerFlow(segments, SandSwirl.RIM + 3, 1001)
	expectTrue(inwardNear > inwardMid, "the lip pulls harder")
	expectTrue(inwardOut == 0, "no drift outside the funnel")
end)

test("a SWIRL carries treasure away from a Diver standing on it", function()
	local fx = effects()
	table.insert(fx.Surges, 1002)
	local segments = SandSwirl.Build(fx, 1000, 8)
	-- A walker and a coin start on the same spot just as the surge peaks; after a second apart.
	local r, a, t0 = 20, 0.3, 1002.3
	local x, z = SandSwirl.ToXZ(r, a)
	local dt = 0.01
	local t = t0
	while t < t0 + 1 - 1e-9 do
		local pr, pa = SandSwirl.ToPolar(x, z)
		local inward, spin = SandSwirl.WalkerFlow(segments, pr, t)
		local ux, uz = math.cos(pa), math.sin(pa)
		x += (-ux * inward + -uz * spin) * dt
		z += (-uz * inward + ux * spin) * dt
		t += dt
	end
	local cr, ca = SandSwirl.Advance(segments, r, a, t0, t0 + 1)
	local cx, cz = SandSwirl.ToXZ(cr, ca)
	local apart = math.sqrt((cx - x) ^ 2 + (cz - z) ^ 2)
	expectTrue(apart > 3, `walker and coin only {apart} studs apart`)
end)

test("SandSwirl.Detour walks round the hole, never across it", function()
	-- Walking (one step at a time, as a bot re-plans) from one side of the hole to a coin on the
	-- far side keeps out of the hole, and gets there: from just outside the keep-out ring, from far
	-- up the slope, and from inside it (dragged in), where it never goes deeper.
	local keepOut = 8
	local ax, az = -9, 0.5
	for _, start in { { 12, 0 }, { 25, -3 }, { 7, 1 } } do
		local x, z = start[1], start[2]
		local closest = math.min(math.sqrt(x * x + z * z), keepOut)
		for _ = 1, 400 do
			local gx, gz = SandSwirl.Detour(x, z, ax, az, keepOut)
			local dx, dz = gx - x, gz - z
			local d = math.sqrt(dx * dx + dz * dz)
			if d < 0.3 then
				break
			end
			x, z = x + dx / d * 0.3, z + dz / d * 0.3
			closest = math.min(closest, math.sqrt(x * x + z * z))
		end
		local from = `from ({start[1]}, {start[2]})`
		expectTrue(
			closest > math.min(keepOut, math.sqrt(start[1] ^ 2 + start[2] ^ 2)) - 0.4,
			`{from}: came within {closest}`
		)
		near(math.sqrt((x - ax) ^ 2 + (z - az) ^ 2), 0, 0.5, `{from}: reached the coin`)
	end

	-- A clear way is taken straight; an aim inside the keep-out ring is met at its edge (a grab
	-- reaches the rest of the way).
	local sx, sz = SandSwirl.Detour(20, 0, 15, 5, keepOut)
	near(sx, 15, 1e-9, "straight x")
	near(sz, 5, 1e-9, "straight z")
	local ex, ez = SandSwirl.Detour(12, 0, 6, 0, keepOut)
	near(ex, keepOut, 1e-9, "edge x")
	near(ez, 0, 1e-9, "edge z")
end)

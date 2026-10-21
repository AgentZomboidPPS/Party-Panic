-- Checks the Parasol Plummet sky math: fallers stay in the sky box, an open umbrella floats up and
-- a shut one drops, a stun shuts it, throws follow their aimed arcs, every throw ends, and the catch
-- shapes match the umbrella the client draws.
local TestKit = require("./TestKit")
local Sim = require("../src/shared/Logic/ParasolPlummetSim")

local test, expectTrue = TestKit.test, TestKit.expectTrue

local function near(a: number, b: number, tolerance: number, message: string)
	expectTrue(math.abs(a - b) <= tolerance, `{message}: {a} vs {b}`)
end

local function run(f, steer: number, open: boolean, stunned: boolean, seconds: number)
	for _ = 1, math.floor(seconds * 30) do
		Sim.Step(f, steer, open, stunned, 1 / 30)
	end
end

test("ParasolPlummetSim: open floats up, shut drops, the box holds", function()
	local f = { X = 0, Y = 0, VX = 0, VY = 0 }
	run(f, 0, true, false, 1)
	expectTrue(f.Y > 0 and f.Y < Sim.RISE, `open floats up slowly ({f.Y})`)
	local high = f.Y
	run(f, 0, false, false, 1)
	expectTrue(f.Y < high - 8, `shut drops fast ({f.Y})`)
	run(f, 1, false, false, 10)
	near(f.X, Sim.HALF_W, 1e-9, "right edge")
	near(f.Y, Sim.Y_MIN, 1e-9, "bottom")
	run(f, -1, true, false, 30)
	near(f.X, -Sim.HALF_W, 1e-9, "left edge")
	near(f.Y, Sim.Y_MAX, 1e-9, "top")
end)

test("ParasolPlummetSim: a stun shuts the umbrella and takes the steering", function()
	local f = { X = 0, Y = 5, VX = 0, VY = 0 }
	run(f, 1, true, true, 0.5)
	near(f.X, 0, 1e-9, "no steering while stunned")
	expectTrue(f.VY < -5, `drops while stunned ({f.VY})`)
end)

test("ParasolPlummetSim: Aim hits its target and every throw ends", function()
	local vx, vy = Sim.Aim(-41, 10, 12, -4, 2)
	local x, y = Sim.ItemAt({ At = 5, X0 = -41, Y0 = 10, VX = vx, VY = vy }, 7)
	near(x, 12, 1e-6, "x")
	near(y, -4, 1e-6, "y")
	local item = { At = 0, X0 = -41, Y0 = 10, VX = 3, VY = 24 }
	expectTrue(not Sim.Gone(item, 0.5), "still flying")
	expectTrue(Sim.Gone(item, Sim.LIFE + 0.01), "gone after LIFE")
end)

test("ParasolPlummetSim: catch shapes follow the drawn umbrella", function()
	local r = Sim.Kinds.Coin.Radius
	expectTrue(Sim.Touches(0, 0, true, 0, Sim.CANOPY_Y, r, 0), "canopy middle")
	expectTrue(Sim.Touches(0, 0, true, Sim.CANOPY_W + r - 0.1, Sim.CANOPY_Y, r, 0), "canopy rim")
	expectTrue(not Sim.Touches(0, 0, false, Sim.CANOPY_W + r - 0.1, Sim.CANOPY_Y, r, 0), "no canopy when shut")
	expectTrue(Sim.Touches(0, 0, false, 0, Sim.FURL_Y1, r, 0), "furled umbrella")
	expectTrue(Sim.Touches(0, 0, false, Sim.BODY_R + r - 0.1, Sim.BODY_Y, r, 0), "body")
	expectTrue(not Sim.Touches(0, 0, true, 0, -6, r, 0), "below the feet")
	-- The canopy ellipse sits on the mesh: rim at base + 3.9, top at base + 5.4.
	near(Sim.CANOPY_Y, Sim.UMBRELLA_BASE + (3.9 + 5.4) / 2 - 0.05, 0.1, "canopy middle on the mesh")
	near(Sim.FURL_Y0, Sim.UMBRELLA_BASE + 1.2, 1e-9, "furl bottom on the mesh")
	near(Sim.FURL_Y1, Sim.UMBRELLA_BASE + 5.2, 1e-9, "furl top on the mesh")
end)

test("ParasolPlummetSim: coins are catchable only coming down in the middle of the sky", function()
	local vy = math.sqrt(2 * -Sim.GRAVITY * (Sim.Y_MAX + 12 - 8))
	local item = { At = 0, X0 = -45, Y0 = 8, VX = 10, VY = vy }
	expectTrue(not Sim.Catchable(item, 0.2), "rising past the wall")
	local top = vy / -Sim.GRAVITY
	expectTrue(not Sim.Catchable(item, top - 0.1), "still rising at the top")
	local t = top + 0.5
	while select(2, Sim.ItemAt(item, t)) > Sim.CATCH_TOP do
		t += 0.05
	end
	local x = Sim.ItemAt(item, t + 0.05)
	expectTrue(math.abs(x) > Sim.CATCH_X or Sim.Catchable(item, t + 0.05), "falling in the middle")
	local wall = { At = 0, X0 = Sim.HALF_W - 2, Y0 = 0, VX = 0, VY = -1 }
	expectTrue(not Sim.Catchable(wall, 0.5), "not by the wall")
end)

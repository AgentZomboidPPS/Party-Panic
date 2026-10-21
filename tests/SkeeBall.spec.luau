-- Checks the Skee-Ball ball path (Shared/Logic/SkeeBall): the same roll always scores the same,
-- power runs from the front gutter through the rings to over the top, every pocket can be reached,
-- the ball drawn by Sample moves smoothly, stays inside the machine and ends in the hole it scored.
local TestKit = require("./TestKit")
local SkeeBall = require("../src/shared/Logic/SkeeBall")

local test, expectTrue, expectEqual = TestKit.test, TestKit.expectTrue, TestKit.expectEqual

local function roll(aim: number, power: number, ball: number?)
	local aimQ, powerQ = SkeeBall.Quantize(aim, power)
	return SkeeBall.Path(aimQ, powerQ, ball or 1)
end

test("SkeeBall.Quantize rounds to thousandths and clamps", function()
	expectEqual({ SkeeBall.Quantize(0, 0) }, { 1000, 0 })
	expectEqual({ SkeeBall.Quantize(-1, 1) }, { 0, 1000 })
	expectEqual({ SkeeBall.Quantize(5, -3) }, { 2000, 0 })
	expectEqual({ SkeeBall.Quantize(0.12345, 0.6789) }, { 1123, 679 })
	expectEqual({ SkeeBall.Quantize(0 / 0, 0 / 0) }, { 1000, 0 }, "NaN counts as the middle and no power")
end)

test("SkeeBall.Luck is in [0, 1), repeatable and well spread", function()
	local buckets = { 0, 0, 0, 0 }
	for aimQ = 0, 2000, 7 do
		local luck = SkeeBall.Luck(aimQ, 500, 3, 1)
		expectTrue(luck >= 0 and luck < 1, `luck {luck} out of range`)
		expectEqual(SkeeBall.Luck(aimQ, 500, 3, 1), luck, "same inputs, same luck")
		local bucket = math.floor(luck * 4) + 1
		buckets[bucket] += 1
	end
	for index, count in buckets do
		expectTrue(count > 40, `quarter {index} only got {count} of 286`)
	end
end)

test("SkeeBall.PocketAt reads the classic layout", function()
	local rings = SkeeBall.RINGS
	local center = SkeeBall.RING_W
	expectEqual(SkeeBall.PocketAt(0, center, 0.5), "50")
	for index = 2, #rings - 1 do
		local mid = (rings[index - 1].R + rings[index].R) / 2
		expectEqual(SkeeBall.PocketAt(0, center + mid, 0.5), tostring(rings[index].Points), "above the middle")
		expectEqual(SkeeBall.PocketAt(mid, center, 0.5), tostring(rings[index].Points), "beside the middle")
	end
	expectEqual(SkeeBall.PocketAt(0, 0.2, 0.5), "10", "the bottom of the board is the 10")
	expectEqual(SkeeBall.PocketAt(1.2, 0.2, 0.5), "10", "so are its corners")
	expectEqual(SkeeBall.PocketAt(-SkeeBall.CUP_U, SkeeBall.CUP_W, 0.99), "100L")
	expectEqual(SkeeBall.PocketAt(SkeeBall.CUP_U, SkeeBall.CUP_W, 0.99), "100R")
	-- On a lip the luck decides, likelier inside the deeper the ball is.
	local edge = center + rings[1].R
	expectEqual(SkeeBall.PocketAt(0, edge, 0.2), "50")
	expectEqual(SkeeBall.PocketAt(0, edge, 0.8), "40")
end)

test("SkeeBall.Path is the same every time for the same roll", function()
	for _, inputs in { { 0, 0.55 }, { -0.8, 0.9 }, { 0.3, 0.2 }, { 1, 1 }, { -0.2, 0 } } do
		local a, b = roll(inputs[1], inputs[2], 4), roll(inputs[1], inputs[2], 4)
		expectEqual(a.Pocket, b.Pocket)
		expectEqual(a.Done, b.Done)
		expectEqual(a.LandU, b.LandU)
	end
end)

test("SkeeBall.Path: power runs from the front gutter, over the rings, to over the top", function()
	expectEqual(roll(0, 0).Pocket, "Gutter", "no power drops short")
	expectEqual(roll(0, 1).Pocket, "Over", "full power sails over the board")
	local lastW = -math.huge
	for power = 0.12, 0.94, 0.02 do
		local path = roll(0, power)
		expectTrue(path.LandW >= 0 and path.LandW <= SkeeBall.BOARD_LEN, `power {power} lands on the board`)
		expectTrue(path.LandW > lastW, `power {power} lands further up than less power`)
		lastW = path.LandW
	end
end)

test("SkeeBall.Path: every pocket can be reached, and the 50 is a small target", function()
	local seen, count, fifty = {}, 0, 0
	for aimQ = 0, 2000, 40 do
		for powerQ = 0, 1000, 20 do
			local path = SkeeBall.Path(aimQ, powerQ, 1)
			seen[path.Pocket] = true
			count += 1
			if path.Pocket == "50" then
				fifty += 1
			end
			expectEqual(path.Points, SkeeBall.Pockets[path.Pocket].Points)
		end
	end
	for pocket in SkeeBall.Pockets do
		expectTrue(seen[pocket], `nothing lands in {pocket}`)
	end
	expectTrue(fifty / count < 0.1, `the 50 takes {fifty} of {count} rolls`)
end)

test("SkeeBall.Path: seen from above the ball goes the way it was aimed", function()
	for _, aim in { -0.6, -0.2, 0.25, 0.7 } do
		local path = roll(aim, 0.5)
		local _, _, s = SkeeBall.OnBoard(path.LandU, path.LandW)
		local expected = aim * SkeeBall.AIM_SLANT * (s + SkeeBall.BALL_R * SkeeBall.BOARD_SIN)
		expectTrue(math.abs(path.LandU - expected) < 0.05, `aim {aim}: landed at u {path.LandU}, expected {expected}`)
		expectTrue((path.LandU > 0) == (aim > 0), "right is right")
	end
end)

test("SkeeBall.Sample moves smoothly, stays in the machine and ends in its hole", function()
	local R = SkeeBall.BALL_R
	for aimQ = 0, 2000, 125 do
		for powerQ = 0, 1000, 50 do
			local path = SkeeBall.Path(aimQ, powerQ, 2)
			expectTrue(path.Landed > 0.5 and path.Landed < path.Done, "lands, then drops in")
			expectTrue(path.Done < 4, `a roll takes {path.Done} s`)
			local pu, py, ps = SkeeBall.Sample(path, 0)
			expectTrue(math.abs(pu) < 1e-9 and math.abs(ps) < 1e-9, "starts at the release point")
			local dt = 1 / 120
			local t = dt
			while t <= path.Done do
				local u, y, s = SkeeBall.Sample(path, t)
				local step = math.sqrt((u - pu) ^ 2 + (y - py) ^ 2 + (s - ps) ^ 2)
				-- 18 studs/s is the fastest it ever goes; a jump would be a seam between phases.
				expectTrue(step < 0.3, `jump of {step} at t {t} ({aimQ}, {powerQ})`)
				expectTrue(math.abs(u) <= SkeeBall.BOARD_HALF - R + 1e-6, `outside the walls at t {t}`)
				expectTrue(y < SkeeBall.TOP_Y - R, `through the roof at t {t}`)
				expectTrue(s < SkeeBall.BACK_S, `through the backstop at t {t}`)
				if s < SkeeBall.HOP_S then
					expectTrue(y >= SkeeBall.FloorY(s) + R - 1e-6, `under the lane at t {t}`)
				end
				pu, py, ps = u, y, s
				t += dt
			end
			local pocket = SkeeBall.Pockets[path.Pocket]
			if pocket.W >= 0 then
				-- It drops in where the hole is (sampled just before it sinks).
				local u, y, s = SkeeBall.Sample(path, path.Phases[#path.Phases].T0 - 1e-4)
				local hu, hy, hs = SkeeBall.OnBoard(pocket.U, pocket.W)
				local miss = math.sqrt((u - hu) ^ 2 + (y - hy) ^ 2 + (s - hs) ^ 2)
				expectTrue(miss < 0.02, `{path.Pocket} ends {miss} from its hole`)
			end
		end
	end
end)

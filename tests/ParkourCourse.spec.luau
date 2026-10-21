-- Checks the lobby obby's layout with the jump arc: every jump is comfortably inside it, nothing can be
-- walked up, nothing can be skipped, the pieces stay over the goo and never stack too close.
-- `lune run tools/checks/obby_jumps` prints the jump table.
local TestKit = require("./TestKit")
local ParkourCourse = require("../src/shared/Logic/ParkourCourse")

local test, expectTrue, expectEqual = TestKit.test, TestKit.expectTrue, TestKit.expectEqual
local Pieces = ParkourCourse.Pieces

local function near(a: number, b: number, tolerance: number, message: string)
	expectTrue(math.abs(a - b) <= tolerance, `{message}: {a} vs {b}`)
end

-- Whether two pieces' tops overlap in plan by more than a sliver (separating axes; discs are 48-gons).
local function overlapping(a: ParkourCourse.Piece, b: ParkourCourse.Piece): boolean
	for _, polygon in { a.Polygon, b.Polygon } do
		for index, p in polygon do
			local q = polygon[index % #polygon + 1]
			local nx, nz = q[2] - p[2], p[1] - q[1]
			local length = math.sqrt(nx * nx + nz * nz)
			nx, nz = nx / length, nz / length
			local aMin, aMax, bMin, bMax = math.huge, -math.huge, math.huge, -math.huge
			for _, v in a.Polygon do
				local d = v[1] * nx + v[2] * nz
				aMin, aMax = math.min(aMin, d), math.max(aMax, d)
			end
			for _, v in b.Polygon do
				local d = v[1] * nx + v[2] * nz
				bMin, bMax = math.min(bMin, d), math.max(bMax, d)
			end
			if aMax < bMin + 0.3 or bMax < aMin + 0.3 then
				return false
			end
		end
	end
	return true
end

test("ParkourCourse.Reach follows the jump arc", function()
	near(ParkourCourse.Reach(0), 8.67, 0.01, "flat")
	near(ParkourCourse.Reach(ParkourCourse.JumpHeight), 4.33, 0.01, "at the top of the arc")
	expectEqual(ParkourCourse.Reach(ParkourCourse.JumpHeight + 0.1), 0, "above the arc")
	expectTrue(ParkourCourse.Reach(3.6) < ParkourCourse.Reach(0), "rising jumps reach less")
	expectTrue(ParkourCourse.Reach(-3.6) > ParkourCourse.Reach(0), "dropping jumps reach more")
end)

test("every jump has reach to spare and nothing can be walked up", function()
	for _, jump in ParkourCourse.Jumps() do
		local name = `{jump.From.Id} > {jump.To.Id}`
		if jump.Walk then
			expectTrue(jump.Gap < 0.15 and math.abs(jump.Rise) <= 0.15, `{name} is a walk onto a beam`)
		else
			expectTrue(jump.Margin >= ParkourCourse.MinMargin, `{name}: needs {jump.Need}, reaches {jump.Reach}`)
			expectTrue(
				jump.Rise >= ParkourCourse.StepUp or jump.Gap >= ParkourCourse.WalkGap,
				`{name} can be walked: gap {jump.Gap}, rise {jump.Rise}`
			)
			expectTrue(jump.Rise >= -0.01, `{name} drops`)
		end
	end
end)

test("no piece can be skipped", function()
	for i, a in Pieces do
		for j = i + 2, #Pieces do
			local b = Pieces[j]
			local rise = b.Top - a.Top
			local gap = ParkourCourse.Gap(a, b)
			-- generous to the jumper: take off at the very edge, land 0.3 past it
			expectTrue(
				gap + 0.3 > ParkourCourse.Reach(rise),
				`{a.Id} > {b.Id} skips the course: gap {gap}, rise {rise}`
			)
		end
	end
end)

test("the course stays over the goo and inside the fence", function()
	for _, piece in Pieces do
		if piece == ParkourCourse.Start then
			continue
		end
		for _, p in piece.Polygon do
			local r = math.sqrt(p[1] * p[1] + p[2] * p[2])
			expectTrue(r <= ParkourCourse.PoolRadius - 2, `{piece.Id} reaches {r} from the middle`)
		end
		expectTrue(piece.Top >= ParkourCourse.GooTop + 1.2, `{piece.Id} is too close to the goo`)
	end
	-- the start pad sits in the fence's gap, half over the goo
	local start = ParkourCourse.Start
	local half = math.deg(math.asin((start.Size :: number) / 2 / ParkourCourse.PoolRadius))
	expectTrue(half < ParkourCourse.Opening, "the start pad fits the gap in the fence")
	expectTrue(
		(start.Radius :: number) - (start.Size :: number) / 2 < ParkourCourse.PoolRadius,
		"the start reaches the goo"
	)
end)

test("pieces that overlap in plan leave head room", function()
	for i, a in Pieces do
		for j = i + 1, #Pieces do
			local b = Pieces[j]
			if overlapping(a, b) then
				expectTrue(
					math.abs(a.Top - b.Top) >= 12.5,
					`{a.Id} and {b.Id} are stacked {math.abs(a.Top - b.Top)} apart`
				)
			end
		end
	end
end)

test("checkpoints start each section, in order", function()
	expectEqual(ParkourCourse.Start.Checkpoint, 0, "the start pad")
	expectEqual(#ParkourCourse.Checkpoints, 3, "three glowing pads")
	for index, pad in ParkourCourse.Checkpoints do
		expectEqual(pad.Checkpoint, index, `checkpoint {index}`)
		expectEqual(pad.Stage, index, `checkpoint {index} stage`)
	end
	local stage = 0
	for _, piece in Pieces do
		expectTrue(piece.Stage >= stage, `{piece.Id} goes back a stage`)
		stage = piece.Stage
	end
	expectTrue(ParkourCourse.Deck.Finish == true, "the deck finishes the course")
end)

test("ParkourCourse.PieceAt and InGoo tell where feet are", function()
	local hop = Pieces[2]
	expectEqual(ParkourCourse.PieceAt(hop.X, hop.Z, hop.Top), hop, "standing on a hop")
	expectEqual(ParkourCourse.PieceAt(hop.X, hop.Z, hop.Top + 4), nil, "jumping over it")
	expectEqual(ParkourCourse.InGoo(hop.X, hop.Z, hop.Top), false, "on a hop is not in the goo")
	expectEqual(ParkourCourse.InGoo(0, 15, ParkourCourse.Floor), true, "on the pool floor")
	expectEqual(ParkourCourse.InGoo(0, 30, ParkourCourse.Floor), false, "outside the pool")
	local beam = Pieces[11]
	expectEqual(ParkourCourse.PieceAt(beam.X, beam.Z, beam.Top), beam, "on a beam")
	local x, top, z, fx, fz = ParkourCourse.Respawn(2)
	expectEqual(ParkourCourse.PieceAt(x, z, top), ParkourCourse.Checkpoints[2], "respawn on checkpoint 2")
	near(fx * fx + fz * fz, 1, 1e-6, "facing is a unit vector")
end)

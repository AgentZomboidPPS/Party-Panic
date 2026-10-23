-- Checks Obby Odyssey's course with the jump arc: every piece has a way on with reach to spare, nothing
-- can be walked up or across, no row can be skipped, and the hazards (balls, bars, blinking blocks) do
-- what the server and the clients both expect. `lune run tools/checks/obby_odyssey_jumps` prints the
-- jump table.
local TestKit = require("./TestKit")
local ObbyOdyssey = require("../src/shared/Logic/ObbyOdyssey")

local test, expectTrue, expectEqual = TestKit.test, TestKit.expectTrue, TestKit.expectEqual
local Rows = ObbyOdyssey.Rows

test("every piece has a way on, with reach to spare, and nothing is walked up or across", function()
	for index = 1, #Rows - 1 do
		for _, from in Rows[index] do
			local ways = ObbyOdyssey.WaysOn(from)
			expectTrue(#ways > 0, `{from.Id} (row {index}) has no way on`)
			for _, jump in ways do
				local name = `{from.Id} > {jump.To.Id}`
				if jump.Walk then
					expectTrue(jump.Gap < 0.15 and math.abs(jump.Rise) < 0.15, `{name} is a walk`)
				else
					expectTrue(
						jump.Rise >= ObbyOdyssey.StepUp or jump.Gap >= ObbyOdyssey.WalkGap,
						`{name} can be walked: gap {jump.Gap}, rise {jump.Rise}`
					)
					expectTrue(jump.Rise >= -0.01, `{name} drops`)
				end
			end
		end
	end
end)

test("every piece of a row after the first can be got onto from the row before", function()
	for index = 2, #Rows do
		for _, to in Rows[index] do
			local reached = false
			for _, from in Rows[index - 1] do
				for _, jump in ObbyOdyssey.WaysOn(from) do
					if jump.To == to then
						reached = true
					end
				end
			end
			expectTrue(reached, `{to.Id} can't be reached from row {index - 1}`)
		end
	end
end)

test("no row can be skipped", function()
	for i = 1, #Rows do
		for j = i + 2, #Rows do
			for _, a in Rows[i] do
				for _, b in Rows[j] do
					local rise = b.Top - a.Top
					local gap = ObbyOdyssey.Gap(a, b)
					-- generous to the jumper: take off at the very edge, land 0.3 past it
					expectTrue(
						gap + 0.3 > ObbyOdyssey.Reach(rise),
						`{a.Id} > {b.Id} skips the course: gap {gap}, rise {rise}`
					)
				end
			end
		end
	end
end)

test("pieces that overlap in plan are a tier on the one below or leave head room", function()
	local pieces = ObbyOdyssey.Pieces
	for i, a in pieces do
		for j = i + 1, #pieces do
			local b = pieces[j]
			if ObbyOdyssey.Gap(a, b) > 0 then
				continue
			end
			local dx = math.abs(a.X - b.X) - (a.W + b.W) / 2
			local dz = math.abs(a.Z - b.Z) - (a.D + b.D) / 2
			if dx > -0.3 or dz > -0.3 then
				continue -- only touching at an edge
			end
			local upper = if b.Top > a.Top then b else a
			expectTrue(
				upper.OnTop == true or math.abs(a.Top - b.Top) >= 12.5,
				`{a.Id} and {b.Id} are stacked {math.abs(a.Top - b.Top)} apart`
			)
		end
	end
end)

test("checkpoints start sections 2 to 5, in order, and the summit is the finish", function()
	expectEqual(ObbyOdyssey.Start.Checkpoint, 0, "the start pad")
	expectEqual(#ObbyOdyssey.Checkpoints, 4, "four pads")
	local stage = 0
	for _, list in Rows do
		for _, piece in list do
			expectTrue(piece.Stage >= stage, `{piece.Id} goes back a stage`)
			if piece.Checkpoint then
				expectEqual(piece.Stage, piece.Checkpoint, `{piece.Id}'s stage`)
			end
		end
		stage = list[1].Stage
	end
	expectTrue(ObbyOdyssey.Summit.Finish == true, "the summit is the finish")
	expectEqual(ObbyOdyssey.Summit.Stage, 4, "the summit is past the last pad")
	for index, pad in ObbyOdyssey.Checkpoints do
		expectEqual(pad.Section, index + 1, `pad {index} starts section {index + 1}`)
	end
end)

test("the pool is under the whole course and the long way round is out of reach", function()
	for _, piece in ObbyOdyssey.Pieces do
		expectTrue(piece.Top >= 3, `{piece.Id} is too close to the water`)
		expectTrue(math.abs(piece.X) + piece.W / 2 <= 24, `{piece.Id} sticks out of the course's width`)
	end
	expectTrue(ObbyOdyssey.Length > 400, `the route is {ObbyOdyssey.Length} studs`)
end)

test("standing on pieces: tops, pipes, tiers and blinking blocks", function()
	local start = ObbyOdyssey.Start
	local piece = ObbyOdyssey.PieceAt(start.X, start.Z, start.Top)
	expectEqual(piece and piece.Id, "Start", "on the start pad")
	expectEqual(ObbyOdyssey.PieceAt(start.X, start.Z, start.Top + 3), nil, "in the air over it")
	-- the second tier's edge is also over the first tier: the higher one counts
	local summit = ObbyOdyssey.Summit
	piece = ObbyOdyssey.PieceAt(summit.X, summit.Z, summit.Top)
	expectEqual(piece and piece.Id, "Summit", "on the summit")
	-- a pipe's sides curve down from its crest
	local pipe = ObbyOdyssey.Rows[19][1]
	expectEqual(pipe.Kind, "Pipe", "row 19 is a pipe")
	expectTrue(ObbyOdyssey.SurfaceAt(pipe, pipe.X + 1) < pipe.Top, "a pipe's side is lower than its crest")
	piece = ObbyOdyssey.PieceAt(pipe.X + 1, pipe.Z, ObbyOdyssey.SurfaceAt(pipe, pipe.X + 1))
	expectEqual(piece and piece.Id, pipe.Id, "on a pipe's side")
	-- a blinking block holds nobody while it's gone
	local block = ObbyOdyssey.Rows[24][1]
	local goneAt = nil
	for step = 0, 84 do
		local t = step * 0.05
		if not ObbyOdyssey.Solid(block, t) then
			goneAt = t
			break
		end
	end
	expectTrue(goneAt ~= nil, "a blinking block goes")
	expectEqual(ObbyOdyssey.PieceAt(block.X, block.Z, block.Top, goneAt :: number), nil, "nobody stands on it")
	expectEqual(ObbyOdyssey.PieceAt(block.X, block.Z, block.Top), block, "it's there when time isn't asked")
end)

test("in every blinking row exactly one block is gone at a time, after a warning", function()
	for row = 24, 28 do
		local list = ObbyOdyssey.Rows[row]
		expectEqual(#list, 3, `row {row} has three blocks`)
		for step = 0, 167 do
			local t = step * 0.05 + 0.01
			local gone = 0
			for _, block in list do
				if not ObbyOdyssey.Solid(block, t) then
					gone += 1
				end
			end
			expectEqual(gone, 1, `row {row} at {t}s`)
		end
	end
	-- the warning comes right before it goes, for BlinkWarn seconds
	local block = ObbyOdyssey.Rows[24][1]
	local warned = 0
	local last = true
	for step = 0, 4199 do
		local t = step * 0.001
		local solid, warning = ObbyOdyssey.BlinkState(block, t)
		if warning then
			warned += 0.001
		end
		if last and not solid then
			local _, before = ObbyOdyssey.BlinkState(block, t - 0.002)
			expectTrue(before, `it flashes just before it goes ({t}s)`)
		end
		last = solid
	end
	expectTrue(math.abs(warned - ObbyOdyssey.BlinkWarn) < 0.01, `it flashes for {warned}s`)
end)

test("the balls swing across the whole bridge and over people's heads at the ends", function()
	local bridge = ObbyOdyssey.Bridge
	for _, ball in ObbyOdyssey.Balls do
		expectTrue(math.abs(ball.Z - bridge.Z) < bridge.D / 2 - ball.Radius, `{ball.Id} hangs over the bridge`)
		-- at the bottom of the swing it hits someone standing under it, and a jump doesn't clear it
		local t = -ball.Phase * ball.Period -- angle 0: straight down
		expectTrue(ObbyOdyssey.BallHits(ball, t, ball.X, bridge.Top, ball.Z), `{ball.Id} hits at the bottom`)
		expectTrue(
			ObbyOdyssey.BallHits(ball, t, ball.X, bridge.Top + ObbyOdyssey.JumpHeight, ball.Z),
			`{ball.Id} hits a jump`
		)
		-- it reaches past both edges of the bridge, and at the top of its swing it's over everyone's heads
		local tip = ball.Length * math.sin(ball.Swing)
		expectTrue(tip - ball.Radius > bridge.W / 2 + ObbyOdyssey.Body, `{ball.Id} sweeps the bridge`)
		local top = ball.Period * (0.25 - ball.Phase)
		local _, y = ObbyOdyssey.BallAt(ball, top)
		expectTrue(y - ball.Radius > bridge.Top + ObbyOdyssey.Height, `{ball.Id} clears heads at the end`)
		-- someone a body and a ball away in front is safe
		expectTrue(
			not ObbyOdyssey.BallHits(ball, t, ball.X, bridge.Top, ball.Z + ball.Radius + ObbyOdyssey.Body + 0.1),
			`{ball.Id} misses beside it`
		)
	end
	-- the jump off the bridge's end is taken clear of the last ball
	local last = ObbyOdyssey.Balls[#ObbyOdyssey.Balls]
	local takeOff = bridge.Z + bridge.D / 2 - 1
	expectTrue(takeOff - last.Z > last.Radius + ObbyOdyssey.Body + 2, "room to take off past the last ball")
	-- there's room to stand between the balls
	for index = 2, #ObbyOdyssey.Balls do
		local a, b = ObbyOdyssey.Balls[index - 1], ObbyOdyssey.Balls[index]
		local room = (b.Z - a.Z) - a.Radius - b.Radius - 2 * ObbyOdyssey.Body
		expectTrue(room >= 2, `room between {a.Id} and {b.Id}: {room}`)
	end
end)

test("the spinning bars hit legs, not jumps, and push the way they turn", function()
	for _, spinner in ObbyOdyssey.Spinners do
		local period = math.abs(spinner.Period)
		-- someone standing halfway out is swept by the bar twice a turn
		local x, z = spinner.X + spinner.Arm / 2, spinner.Z
		local passes, clear = 0, 0
		local step = period / 400
		local wasHit = ObbyOdyssey.SpinnerHits(spinner, -step, 0, x, spinner.Top, z)
		for index = 0, 399 do
			local t0 = index * step
			local hit = ObbyOdyssey.SpinnerHits(spinner, t0, t0 + step, x, spinner.Top, z)
			if hit and not wasHit then
				passes += 1
			elseif not hit then
				clear += 1
			end
			wasHit = hit
		end
		expectEqual(passes, 2, `{spinner.Id} passes a spot twice a turn`)
		expectTrue(clear > 300, `{spinner.Id} leaves a spot clear {clear} steps of 400`)
		-- a long sweep can't skip over anyone
		expectTrue(
			(ObbyOdyssey.SpinnerHits(spinner, 0, period / 2, x, spinner.Top, z)),
			`{spinner.Id}: half a turn always passes`
		)
		-- feet over the bar: no hit
		local barTop = spinner.Top + spinner.BarY + spinner.BarRadius
		expectTrue(
			not ObbyOdyssey.SpinnerHits(spinner, 0, period, x, barTop + 0.05, z),
			`{spinner.Id}: a jump clears it`
		)
		-- a jump stays over the bar for most of its air time
		local v0 = math.sqrt(2 * ObbyOdyssey.Gravity * ObbyOdyssey.JumpHeight)
		local rise = barTop - spinner.Top
		local inside = v0 * v0 - 2 * ObbyOdyssey.Gravity * rise
		local air = 2 * math.sqrt(inside) / ObbyOdyssey.Gravity
		expectTrue(air > 0.35, `{spinner.Id}: {air}s over the bar`)
		-- off the disc: never
		expectTrue(
			not ObbyOdyssey.SpinnerHits(spinner, 0, period, spinner.X + spinner.Arm + 2, spinner.Top, z),
			`{spinner.Id}: off the disc`
		)
		-- the push is along the way the bar turns
		local t = 0
		while not ObbyOdyssey.SpinnerHits(spinner, t, t + step, x, spinner.Top, z) do
			t += step
		end
		local _, px, pz = ObbyOdyssey.SpinnerHits(spinner, t, t + step, x, spinner.Top, z)
		expectTrue(math.abs(px) < 1e-6, `{spinner.Id}: pushed along z at +x`)
		expectEqual(if pz > 0 then 1 else -1, if spinner.Period > 0 then 1 else -1, `{spinner.Id}: push direction`)
		-- SpinnerNext says when the bar comes
		local wait = ObbyOdyssey.SpinnerNext(spinner, 0, x, z)
		expectTrue(wait >= 0 and wait <= period / 2 + 1e-6, `{spinner.Id}: next pass in {wait}s`)
		expectTrue(
			(ObbyOdyssey.SpinnerHits(spinner, wait - 0.01, wait + 0.01, x, spinner.Top, z)),
			`{spinner.Id}: the bar is there when SpinnerNext says`
		)
	end
end)

test("progress grows along the route and respawns are on their pads", function()
	local last = -1
	for index = 1, #Rows do
		local x, y, z = ObbyOdyssey.RowMiddle(index)
		local progress = ObbyOdyssey.Progress(index, x, y, z)
		expectTrue(progress > last, `row {index}: {progress}`)
		last = progress
	end
	expectTrue(math.abs(last - ObbyOdyssey.Length) < 1e-6, "the summit is the whole way")
	-- along the bridge, end to end, progress keeps growing
	local bridge = ObbyOdyssey.Bridge
	local previous = -1
	for z = bridge.Z - bridge.D / 2 + 0.5, bridge.Z + bridge.D / 2 - 0.5, 2 do
		local progress = ObbyOdyssey.Progress(bridge.Row, bridge.X, bridge.Top, z)
		expectTrue(progress > previous, `on the bridge at z {z}: {progress}`)
		previous = progress
	end
	for stage = 0, 4 do
		for slot = 1, 12 do
			local x, y, z = ObbyOdyssey.Respawn(stage, slot)
			local piece = ObbyOdyssey.PieceAt(x, z, y)
			local expected = if stage == 0 then "Start" else `Checkpoint{stage}`
			expectEqual(piece and piece.Id, expected, `stage {stage} slot {slot}`)
			expectTrue(piece ~= nil and ObbyOdyssey.DistanceTo(piece, x + 1.5, z + 1.5) == 0, "inside the pad")
		end
	end
	-- Step: a pad counts once you stand on it, never goes back
	local pad = ObbyOdyssey.Checkpoints[2]
	local stage, row = ObbyOdyssey.Step(1, 8, pad.X, pad.Z, pad.Top)
	expectEqual(stage, 2, "pad 2 reached")
	expectEqual(row, pad.Row, "its row")
	stage = ObbyOdyssey.Step(3, 8, pad.X, pad.Z, pad.Top)
	expectEqual(stage, 3, "a later pad stays")
end)

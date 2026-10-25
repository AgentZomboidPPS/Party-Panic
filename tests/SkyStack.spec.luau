-- Checks Sky Stack's rules (src/shared/Logic/SkyStack.luau): the slide schedule, what a drop
-- leaves on the tower and what falls, combos, and the standings.
local TestKit = require("./TestKit")
local Stack = require("../src/shared/Logic/SkyStack")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local function near(actual: number, expected: number, message: string)
	expectTrue(math.abs(actual - expected) < 1e-6, `{message}: {actual} (expected {expected})`)
end

-- Floor 1 sets off at server time 10 along X from the -X side, at the first floor's speed.
local function firstSlide()
	return Stack.NewSlide(1, 10)
end

-- The time floor 1's block is `offset` from the middle on its first pass (offset in -AMP..AMP).
local function when(slide, offset: number): number
	return slide.Start + (offset * slide.Dir + Stack.AMP) / slide.Speed
end

test("a block waits clear of the tower, then swings from side to side", function()
	local slide = firstSlide()
	expectEqual(slide.Axis, "X")
	expectEqual(slide.Dir, 1)
	near(Stack.Offset(slide, 0), -Stack.AMP, "before it sets off")
	near(Stack.Offset(slide, 10), -Stack.AMP, "as it sets off")
	near(Stack.Offset(slide, 10 + Stack.AMP / slide.Speed), 0, "over the middle")
	near(Stack.Offset(slide, 10 + 2 * Stack.AMP / slide.Speed), Stack.AMP, "at the far side")
	near(Stack.Offset(slide, 10 + 3 * Stack.AMP / slide.Speed), 0, "back over the middle")
	near(Stack.Offset(slide, 10 + 4 * Stack.AMP / slide.Speed), -Stack.AMP, "back where it started")
	expectTrue(Stack.AMP - Stack.HALF > Stack.HALF, "it starts clear of a full block")
end)

test("floors alternate axes and sides, and speed up to a cap", function()
	expectEqual(Stack.AxisFor(1), "X")
	expectEqual(Stack.AxisFor(2), "Z")
	expectEqual(Stack.DirFor(1), 1)
	expectEqual(Stack.DirFor(2), 1)
	expectEqual(Stack.DirFor(3), -1)
	expectEqual(Stack.DirFor(4), -1)
	expectEqual(Stack.DirFor(5), 1)
	near(Stack.SpeedFor(1), Stack.SPEED, "the first floor")
	near(Stack.SpeedFor(2), Stack.SPEED + Stack.RAMP, "the second")
	near(Stack.SpeedFor(500), Stack.MAX_SPEED, "the cap")
	near(Stack.SpeedFor(1, true), Stack.SPEED * Stack.GUST, "a gusted block")
	local slide = Stack.NewSlide(3, 5)
	near(Stack.Offset(slide, 5), Stack.AMP, "floor 3 starts on the + side")
end)

test("a press in the first moment of a slide doesn't count", function()
	local slide = firstSlide()
	expectTrue(not Stack.Counts(slide, 10), "as it sets off")
	expectTrue(not Stack.Counts(slide, 10 + Stack.READY - 0.01), "just before READY")
	expectTrue(Stack.Counts(slide, 10 + Stack.READY), "at READY")
end)

test("a drop near the middle is perfect and snaps on exactly", function()
	local slide = firstSlide()
	local drop = Stack.Drop(Stack.Base(), slide, when(slide, 0.2), 0)
	expectEqual(drop.Kind, "Perfect")
	expectEqual(drop.Block, Stack.Base())
	expectEqual(drop.Falling, nil)
	expectEqual(drop.Streak, 1)
	expectTrue(not drop.Combo, "one perfect isn't a combo")
end)

test("an off drop keeps the overlap and drops the overhang", function()
	local slide = firstSlide()
	local drop = Stack.Drop(Stack.Base(), slide, when(slide, 1.5), 2)
	expectEqual(drop.Kind, "Cut")
	expectEqual(drop.Block, { X0 = -2.5, X1 = 4, Z0 = -4, Z1 = 4 })
	expectEqual(drop.Falling, { X0 = 4, X1 = 5.5, Z0 = -4, Z1 = 4 })
	expectEqual(drop.Streak, 0)
	local early = Stack.Drop(Stack.Base(), slide, when(slide, -3), 0)
	expectEqual(early.Block, { X0 = -4, X1 = 1, Z0 = -4, Z1 = 4 })
	expectEqual(early.Falling, { X0 = -7, X1 = -4, Z0 = -4, Z1 = 4 })
	-- What lands plus what falls is the block that was dropped.
	local kept, fell = early.Block :: any, early.Falling :: any
	near((kept.X1 - kept.X0) + (fell.X1 - fell.X0), Stack.FULL, "nothing made or lost")
end)

test("a Z floor cuts along Z and keeps X", function()
	local top = { X0 = -2.5, X1 = 4, Z0 = -4, Z1 = 4 }
	local slide = Stack.NewSlide(2, 0)
	local drop = Stack.Drop(top, slide, when(slide, 2), 0)
	expectEqual(drop.Kind, "Cut")
	expectEqual(drop.Block, { X0 = -2.5, X1 = 4, Z0 = -2, Z1 = 4 })
	expectEqual(drop.Falling, { X0 = -2.5, X1 = 4, Z0 = 4, Z1 = 6 })
end)

test("too little left over is a miss and the whole block falls", function()
	local slide = firstSlide()
	local miss = Stack.Drop(Stack.Base(), slide, when(slide, -7.6), 4)
	expectEqual(miss.Kind, "Miss")
	expectEqual(miss.Block, nil)
	expectEqual(miss.Falling, { X0 = -11.6, X1 = -3.6, Z0 = -4, Z1 = 4 })
	expectEqual(miss.Streak, 0)
	local thin = { X0 = 0, X1 = 1, Z0 = -4, Z1 = 4 }
	expectEqual(Stack.Drop(thin, slide, when(slide, 0.6), 0).Kind, "Miss")
	expectEqual(Stack.Drop(thin, slide, when(slide, 0.45), 0).Kind, "Cut")
end)

test("every third perfect in a row grows the block and blows a gust", function()
	local slide = firstSlide()
	local top = { X0 = -1, X1 = 3.8, Z0 = -2, Z1 = 2 }
	local second = Stack.Drop(top, slide, when(slide, 0), 1)
	expectTrue(not second.Combo, "the second perfect")
	expectEqual(second.Block, top)
	local third = Stack.Drop(top, slide, when(slide, 0), 2)
	expectTrue(third.Combo, "the third perfect")
	expectEqual(third.Streak, 3)
	expectEqual(third.Block, { X0 = -1.5, X1 = 4, Z0 = -2.5, Z1 = 2.5 }) -- never past the base
	expectTrue(Stack.Drop(top, slide, when(slide, 0), 5).Combo, "the sixth")
end)

test("bots find the next time the block is over the middle", function()
	local slide = firstSlide()
	local pass = 2 * Stack.AMP / slide.Speed
	near(Stack.NextMiddle(slide, 0), when(slide, 0), "before it sets off")
	near(Stack.NextMiddle(slide, when(slide, 0)), when(slide, 0), "right on it")
	near(Stack.NextMiddle(slide, when(slide, 0) + 0.01), when(slide, 0) + pass, "just after: the way back")
	near(Stack.Offset(slide, Stack.NextMiddle(slide, 13.7)), 0, "any time")
end)

test("a faster block gets a wider perfect window (never under PERFECT_TIME of travel)", function()
	near(Stack.PerfectFor(Stack.SPEED), Stack.PERFECT, "the first floor")
	near(Stack.PerfectFor(17), 17 * Stack.PERFECT_TIME, "a fast floor")
	local fast = Stack.NewSlide(30, 0)
	local drop = Stack.Drop(Stack.Base(), fast, when(fast, 0.45), 0)
	expectEqual(drop.Kind, "Perfect")
end)

test("standings: the top by when, then floors, then by when", function()
	local first = Stack.Rank(25, 30, true)
	local second = Stack.Rank(25, 31, true)
	local tall = Stack.Rank(24, 20)
	local tallLater = Stack.Rank(24, 40)
	local short = Stack.Rank(10, 5)
	expectTrue(first > second, "1st over 2nd")
	expectTrue(second > tall, "a finisher over the rest")
	expectTrue(tall > tallLater, "the same height reached sooner")
	expectTrue(tallLater > short, "taller over shorter")
end)

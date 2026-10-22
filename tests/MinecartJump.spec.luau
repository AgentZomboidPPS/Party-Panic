-- Minecart Mayhem's held jumps (owner: "Minecart mayham is still terrible. Iam not sure how we can
-- fix it. I cant see when to jump."; Shared/Logic/MinecartMayhemTrack): a press in the window still
-- jumps at once, an early one (up to HOLD before the best moment) waits for the best moment and
-- clears the gap, and one earlier than that, or too late, doesn't.
local TestKit = require("./TestKit")
local Track = require("../src/shared/Logic/MinecartMayhemTrack")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local GAP = Track.GAP_TO - Track.GAP_FROM

-- The press times that clear a gap reached at `at`, as a window (from, to), on a 1 ms grid.
local function window(at: number, v: number, held: boolean): (number, number)
	local from, to = math.huge, -math.huge
	for ms = -4000, 500 do
		local press = at + ms / 1000
		local takeOff = if held then Track.TakeOff(press, at, v, GAP) else press
		if Track.Clears(takeOff, at, v, GAP) then
			from, to = math.min(from, press), math.max(to, press)
		end
	end
	return from - at, to - at
end

test("Minecart: the window a press clears a gap in was a third of a second at cruising speed", function()
	local from, to = window(10, Track.CRUISE, false)
	expectTrue(to - from < 0.4, `the old window was {to - from} s`)
end)

test("Minecart: an early press is held, so the window is over a second at any usual speed", function()
	for _, v in { 16, Track.CRUISE, 32, Track.MAX_V } do
		local from, to = window(10, v, true)
		expectTrue(to - from >= Track.HOLD, `at {v} studs/s presses from {from} to {to} s clear it`)
		expectTrue(to < 0, "a press after the front wheels reach the gap never clears it")
	end
end)

test("Minecart: TakeOff jumps at once in the window, holds an early press, not a far too early one", function()
	local at, v = 10, Track.CRUISE
	local best = Track.BestJump(at, v, GAP)
	expectTrue(Track.Clears(best, at, v, GAP), "the best moment clears it")
	expectEqual(Track.TakeOff(best, at, v, GAP), best, "in the window: at once")
	expectEqual(Track.TakeOff(best - 0.5, at, v, GAP), best, "0.5 s early: held for the best moment")
	expectEqual(Track.TakeOff(best - Track.HOLD - 0.2, at, v, GAP), best - Track.HOLD - 0.2, "far too early: at once")
	expectEqual(Track.TakeOff(at - 0.01, at, v, GAP), at - 0.01, "too late: at once (and it falls)")
	expectEqual(Track.TakeOff(3, nil, v, GAP), 3, "no gap coming: at once")
end)

test("Minecart: JumpFor finds the next gap on the rider's tile or the next", function()
	local course = {
		Tiles = {
			{ Index = 1, Paths = { { Total = 100 } }, Features = {} },
			{ Index = 2, Paths = { { Total = 72 } }, Features = { { K = "Gap", B = 1, S = 38, S1 = 46 } } },
		},
	} :: any
	local rider = { Tile = 1, B = 1, S = 80, V = Track.CRUISE } :: any
	local front, gap, tile = Track.NextGap(course, rider, 90)
	expectTrue(math.abs((front :: number) - (100 - 80 + 38 - Track.HALF_BASE)) < 1e-9, `front {front}`)
	expectEqual({ gap, tile }, { 8, 2 })
	local now = 5
	local at = now + (front :: number) / Track.CRUISE
	local best = Track.BestJump(at, Track.CRUISE, 8)
	expectTrue(math.abs(Track.JumpFor(course, rider, best - 0.4, now) - best) < 1e-9, "held for the best moment")
	rider.S = 100 + 38 -- (past it: front wheels over the gap)
	rider.Tile = 1
	expectEqual(Track.NextGap(course, rider, 90), nil, "a gap already reached isn't ahead")
end)

return nil

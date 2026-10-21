-- Checks the buzzer at the end of a timed round (src/shared/Logic/Buzzer.luau): when a held end
-- comes, what counts in that moment, and when a press was made.
local TestKit = require("./TestKit")
local Buzzer = require("../src/shared/Logic/Buzzer")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local function near(actual: number, expected: number, message: string)
	expectTrue(math.abs(actual - expected) < 1e-9, `{message}: {actual} (expected {expected})`)
end

-- Time runs out at 100 (server time).
local BUZZER = 100

test("with nothing in flight the round ends at the buzzer", function()
	expectTrue(Buzzer.Ends(BUZZER, BUZZER, 0), "no hold asked for")
	expectTrue(Buzzer.Ends(BUZZER, BUZZER, BUZZER - 0.2), "a hold that's already over")
	expectTrue(Buzzer.Ends(BUZZER, BUZZER, BUZZER), "a hold until the buzzer itself")
end)

test("a hold keeps the round going until it's over", function()
	local holdUntil = BUZZER + 0.3 -- an arrow came down at 99.9 and its last look is at 100.25
	expectTrue(not Buzzer.Ends(BUZZER, BUZZER, holdUntil), "at the buzzer")
	expectTrue(not Buzzer.Ends(BUZZER + 0.29, BUZZER, holdUntil), "just before the hold is over")
	expectTrue(Buzzer.Ends(BUZZER + 0.3, BUZZER, holdUntil), "when it's over")
end)

test("never more than MAX_HOLD past the buzzer", function()
	expectEqual(Buzzer.MAX_HOLD, 0.5)
	local holdUntil = BUZZER + 3 -- asked for far too long (or asked again and again)
	expectTrue(not Buzzer.Ends(BUZZER + 0.49, BUZZER, holdUntil), "still within MAX_HOLD")
	expectTrue(Buzzer.Ends(BUZZER + 0.5, BUZZER, holdUntil), "MAX_HOLD past the buzzer")
	expectTrue(Buzzer.Ends(BUZZER + 2, BUZZER, holdUntil), "long past it")
end)

test("InTime: everything counts until time runs out, then only what happened by the buzzer", function()
	expectTrue(Buzzer.InTime(BUZZER + 5, nil), "time hasn't run out")
	expectTrue(Buzzer.InTime(BUZZER - 0.01, BUZZER), "just before")
	expectTrue(Buzzer.InTime(BUZZER, BUZZER), "at the buzzer")
	expectTrue(not Buzzer.InTime(BUZZER + 0.01, BUZZER), "just after")
end)

test("PressTime: the time the player's device says, within what their ping allows", function()
	-- A phone with a 0.4 s round trip: the press travelled about 0.2 s, so a press that arrives at
	-- 100.15 may say it was made as early as 100.15 - 0.2 - REACH.
	expectEqual(Buzzer.REACH, 0.1)
	near(Buzzer.PressTime(99.95, 100.15, 0.4), 99.95, "an honest time is kept")
	near(Buzzer.PressTime(100.1, 100.15, 0.4), 100.1, "a quick arrival keeps its time")
	near(Buzzer.PressTime(99.0, 100.15, 0.4), 100.15 - 0.2 - 0.1, "a time from long before is pulled forward")
	near(Buzzer.PressTime(100.5, 100.15, 0.4), 100.15, "never after it arrived")
end)

test("PressTime: without a time (bots, broken values), half a round trip before it arrived", function()
	near(Buzzer.PressTime(nil, 100.15, 0.4), 99.95, "no time sent")
	near(Buzzer.PressTime("99", 100.15, 0.4), 99.95, "not a number")
	near(Buzzer.PressTime(0 / 0, 100.15, 0.4), 99.95, "NaN")
	near(Buzzer.PressTime(nil, 100.15, 0), 100.15, "a bot has no lag: when it arrived")
	near(Buzzer.PressTime(nil, 100.15, -1), 100.15, "a negative ping counts as none")
end)

test("a HIT pressed just before the buzzer on a slow phone counts; one pressed after doesn't", function()
	-- Pressed at 99.9 (0.1 s before the buzzer), arrives at 100.15 (0.5 s round trip).
	local pressed = Buzzer.PressTime(99.9, 100.15, 0.5)
	expectTrue(Buzzer.InTime(pressed, BUZZER), "pressed before")
	-- Pressed at 100.05, after the buzzer: arrives at 100.3 and doesn't count.
	expectTrue(not Buzzer.InTime(Buzzer.PressTime(100.05, 100.3, 0.5), BUZZER), "pressed after")
	-- Arriving at 100.5 it can't have been made before 100.15, whatever time it says.
	expectTrue(not Buzzer.InTime(Buzzer.PressTime(99.9, 100.5, 0.5), BUZZER), "a made-up time can't reach back")
	-- A bot pressing during the hold: no lag, so when it arrived, after the buzzer.
	expectTrue(not Buzzer.InTime(Buzzer.PressTime(nil, 100.05, 0), BUZZER), "a bot during the hold")
end)

return nil

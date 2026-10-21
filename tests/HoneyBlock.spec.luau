-- Checks Honey Trap's 1-or-2 block (src/shared/Logic/HoneyBlock.luau): when each face shows, and
-- which face a hit gets, especially one that reaches the server just after the deadline.
local TestKit = require("./TestKit")
local HoneyBlock = require("../src/shared/Logic/HoneyBlock")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

-- A turn like the server's: the block goes up at 100, flips every 0.42 s and stops at 106. Its 15th
-- face (flip 14, from 105.88) is the one it stops on.
local turn = { T0 = 100, Deadline = 106, First = 1, Flip = 0.42 }
local LAST = HoneyBlock.FaceAt(turn, 106)
local BEFORE_LAST = 3 - LAST

test("the block starts on its first face and flips every 0.42 s", function()
	expectEqual(HoneyBlock.FaceAt(turn, 99), 1, "before it goes up")
	expectEqual(HoneyBlock.FaceAt(turn, 100.2), 1)
	expectEqual(HoneyBlock.FaceAt(turn, 100.5), 2)
	expectEqual(HoneyBlock.FaceAt(turn, 100.9), 1)
	expectEqual(HoneyBlock.FaceAt({ T0 = 100, Deadline = 106, First = 2 }, 100.5), 1, "FLIP when Flip is missing")
end)

test("the block stops at the deadline on the face it shows then", function()
	expectEqual(LAST, 1, "14 flips from 1")
	expectEqual(HoneyBlock.FaceAt(turn, 105.9), LAST)
	expectEqual(HoneyBlock.FaceAt(turn, 105.8), BEFORE_LAST, "the face before the last flip (105.46 to 105.88)")
	for _, t in { 106.1, 106.31, 106.75, 110 } do
		expectEqual(HoneyBlock.FaceAt(turn, t), LAST, `still stopped at {t}`)
	end
end)

test("Shows: a face counts if it's on screen at any moment of the window", function()
	expectTrue(HoneyBlock.Shows(turn, 2, 100.3, 100.5), "flips to it")
	expectTrue(not HoneyBlock.Shows(turn, 2, 100.1, 100.3), "never shows")
	-- 100.40 shows 1, 100.42-100.84 shows 2, 100.84 on shows 1 again: both ends say 1.
	expectTrue(HoneyBlock.Shows(turn, 2, 100.40, 100.86), "in the middle of the window")
	expectTrue(not HoneyBlock.Shows(turn, BEFORE_LAST, 106, 107), "nothing new after the deadline")
end)

test("a hit pressed just before the last flip that arrives after the deadline gets the face pressed on", function()
	-- Pressed at 105.80 (BEFORE_LAST showing), on a phone with a 0.4 s round trip: it reaches the
	-- server at 106.0 or a little later, after the block has stopped on LAST.
	for _, arrives in { 106.0, 106.05, 106.2, 106.3 } do
		expectEqual(HoneyBlock.Judge(turn, BEFORE_LAST, arrives, 0.4), BEFORE_LAST, `arrives at {arrives}`)
	end
	-- A quick connection: pressed at 105.80, there at 105.85 (before the deadline) or held up to 106.05.
	expectEqual(HoneyBlock.Judge(turn, BEFORE_LAST, 105.85, 0.06), BEFORE_LAST)
	expectEqual(HoneyBlock.Judge(turn, BEFORE_LAST, 106.05, 0.06), BEFORE_LAST)
	-- Pressed on the last face, arriving late: that face.
	expectEqual(HoneyBlock.Judge(turn, LAST, 106.2, 0.4), LAST)
end)

test("no face from after the deadline", function()
	-- Had the block kept flipping, BEFORE_LAST would show again from 106.30: a claim of it arriving
	-- at 106.35 from a quick connection (pressed at about 106.32) gets the face the block stopped on.
	expectEqual(HoneyBlock.Judge(turn, BEFORE_LAST, 106.35, 0.06), LAST)
	-- With no (or a broken) claim, the face showing when the hit was sent, never past the deadline.
	expectEqual(HoneyBlock.Judge(turn, nil, 106.3, 0.06), LAST)
	expectEqual(HoneyBlock.Judge(turn, "2", 106.3, 0.06), LAST)
end)

test("a claim of a face that didn't show in the moment before the hit falls back to the clock", function()
	-- At 102.9 the block shows face 1 (since 102.52; 7 flips at 102.94): a quick connection claiming
	-- face 2 (last shown until 102.52) gets face 1.
	expectEqual(HoneyBlock.Judge(turn, 2, 102.9, 0.06), 1)
	expectEqual(HoneyBlock.Judge(turn, 1, 102.9, 0.06), 1)
	-- A slow one (0.4 s round trip, plus the leeway, back to 102.25): face 2 showed then, so it counts.
	expectEqual(HoneyBlock.Judge(turn, 2, 102.9, 0.4), 2)
	expectEqual(HoneyBlock.Judge(turn, 3, 102.9, 0.06), 1, "only 1 or 2")
	expectEqual(HoneyBlock.Judge(turn, 0 / 0, 102.9, 0.06), 1, "not a number")
end)

test("bots (no ping) get the face showing when they press", function()
	for _, t in { 100.05, 100.5, 101.3, 103.33, 105.5 } do
		local face = HoneyBlock.FaceAt(turn, t)
		expectEqual(HoneyBlock.Judge(turn, face, t, 0), face, `at {t}`)
	end
end)

return nil

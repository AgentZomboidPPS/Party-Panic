local TestKit = require("./TestKit")
local SongTiming = require("../src/shared/Logic/SongTiming")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

-- A song 100 s into its pack: a 15 s intro, then 85 s that loop.
local SONG = { Start = 100, Drop = 115, End = 200 }

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

test("SongTiming.Position: the drop plays exactly at GO", function()
	expectEqual(SongTiming.Position(SONG, 0), 115)
end)

test("SongTiming.Position: before GO it's in the intro, at its start if GO is further away", function()
	expectEqual(SongTiming.Position(SONG, -13), 102) -- the rules card and the 3-2-1: 13 s
	expectEqual(SongTiming.Position(SONG, -15), 100)
	expectEqual(SongTiming.Position(SONG, -20), 100)
end)

test("SongTiming.Position: after GO it goes round the loop, never back into the intro", function()
	expectEqual(SongTiming.Position(SONG, 30), 145)
	expectTrue(near(SongTiming.Position(SONG, 85), 115), "one loop later it's back at the drop")
	expectTrue(near(SongTiming.Position(SONG, 150), 180), "150 s into a Honey Trap round")
	for since = 0, 400, 7.3 do
		local position = SongTiming.Position(SONG, since)
		expectTrue(position >= 115 and position < 200, `{since}s after GO: {position} is outside the loop`)
	end
end)

test("SongTiming.Wait: start now unless GO is further away than the intro", function()
	expectEqual(SongTiming.Wait(SONG, -13), 0)
	expectEqual(SongTiming.Wait(SONG, -15), 0)
	expectEqual(SongTiming.Wait(SONG, -18), 3)
	expectEqual(SongTiming.Wait(SONG, 5), 0)
end)

test("SongTiming.SinceGo: Preparing counts down to GO, the round counts down its length", function()
	expectEqual(SongTiming.SinceGo("Preparing", 13, 60), -13)
	expectEqual(SongTiming.SinceGo("Preparing", 0, 60), 0)
	expectEqual(SongTiming.SinceGo("InRound", 60, 60), 0)
	expectEqual(SongTiming.SinceGo("InRound", 20, 60), 40)
	expectEqual(SongTiming.SinceGo("Results", 5, 60), nil)
	expectEqual(SongTiming.SinceGo("Voting", 5, 60), nil)
end)

test("SongTiming.Drifted: small drifts are left alone, big ones are fixed", function()
	expectTrue(not SongTiming.Drifted(SONG, 140.2, 140, 0.35), "0.2 s off")
	expectTrue(SongTiming.Drifted(SONG, 141, 140, 0.35), "a second off")
	expectTrue(SongTiming.Drifted(SONG, 103, 115, 0.35), "still in the intro at GO")
end)

test("SongTiming.Drifted: just round the loop isn't far off", function()
	expectTrue(not SongTiming.Drifted(SONG, 199.9, 115.1, 0.35), "the song went round a moment early")
	expectTrue(not SongTiming.Drifted(SONG, 115.1, 199.9, 0.35), "the song went round a moment late")
	expectTrue(SongTiming.Drifted(SONG, 160, 115, 0.35), "half a loop off")
end)

local TestKit = require("./TestKit")
local Track = require("../src/shared/Logic/RockinRacewayTrack")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

-- Riding speeds a horse meets a hurdle at: slowed by a bump, coming out of a spin, trotting,
-- galloping and fresh off a carrot's dash.
local SPEEDS = { Track.SLOW, 10, Track.TROT, 20, 25, Track.GALLOP, 35, Track.DASH }

-- Runs `fn` with the hurdle bar and the hop arc they had before the hurdles were 3D.
local function withFlatHurdles<T>(fn: () -> T): T
	local clear, height = Track.CLEAR, Track.HOP_HEIGHT
	Track.CLEAR, Track.HOP_HEIGHT = 0.8, 2.6
	local ok, result = pcall(fn)
	Track.CLEAR, Track.HOP_HEIGHT = clear, height
	assert(ok, result)
	return result
end

test("RockinRacewayTrack: the 3D hurdles keep every timing window (bar and hop scaled together)", function()
	expectEqual(Track.CLEAR / Track.HOP_HEIGHT, 0.8 / 2.6)
	for _, speed in SPEEDS do
		-- A press `lead` seconds before the rider reaches the bar, from far too early to too late.
		for step = -40, 240 do
			local lead = step * 0.005
			local now = Track.Clears(0, lead, speed)
			local before = withFlatHurdles(function()
				return Track.Clears(0, lead, speed)
			end)
			expectEqual(now, before, `a hop {lead}s ahead at {speed} studs/s`)
			-- (a carrot under a horse this high in the air is missed, the same as before)
			local high = Track.HopHeight(lead) >= Track.CLEAR
			expectEqual(
				high,
				withFlatHurdles(function()
					return Track.HopHeight(lead) >= Track.CLEAR
				end)
			)
		end
	end
end)

test("RockinRacewayTrack: a hop pressed over the take-off pad clears at any speed from a trot to a dash", function()
	expectTrue(Track.TAKEOFF_NEAR < Track.TAKEOFF_FAR)
	for _, speed in SPEEDS do
		if speed < Track.TROT then
			continue -- (slower than a trot the hop must come later: the HOP button shows when)
		end
		for step = 0, 40 do
			local distance = Track.TAKEOFF_NEAR + (Track.TAKEOFF_FAR - Track.TAKEOFF_NEAR) * step / 40
			expectTrue(Track.Clears(0, distance / speed, speed), `{distance} studs before the bar at {speed} studs/s`)
		end
	end
end)

test("RockinRacewayTrack: HitAt says where the horse hits the bar exactly when it doesn't clear", function()
	for _, speed in SPEEDS do
		local nose, tail = Track.NOSE / speed, Track.TAIL / speed
		for step = -40, 240 do
			local lead = step * 0.005
			local hit = Track.HitAt(0, lead, speed)
			expectEqual(hit == nil, Track.Clears(0, lead, speed), `a hop {lead}s ahead at {speed} studs/s`)
			if hit then
				expectTrue(math.abs(hit - (lead - nose)) < 1e-9 or math.abs(hit - (lead + tail)) < 1e-9)
				-- (the hop is lower than the bar right there, so the knock is drawn where it shows)
				expectTrue(Track.HopHeight(hit) < Track.CLEAR)
			end
		end
	end
	-- No hop at all, or one pressed as the nose reaches the bar: knocked by the front.
	expectEqual(Track.HitAt(-math.huge, 2, 20), 2 - Track.NOSE / 20)
	expectEqual(Track.HitAt(2 - Track.NOSE / 20, 2, 20), 2 - Track.NOSE / 20)
	-- Far too early: down again before the wheel is over, so the wheel knocks it.
	expectEqual(Track.HitAt(0, Track.HOP_TIME, 20), Track.HOP_TIME + Track.TAIL / 20)
end)

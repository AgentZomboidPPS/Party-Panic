-- Checks Trace Race's shared rules (src/shared/Logic/TraceRace.luau) for wandering (owner: "On trace
-- race you should be able to leave your own lane. They wont score points but its funny"): a crayon
-- can go anywhere on the paper, a stud and a half inside its outer edges, and a line drawn away from
-- the rider's own guide (in another lane, even right along that lane's guide) scores 0 while the rest
-- of the line scores as before.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local TestKit = require("./TestKit")

local test, expectTrue, expectEqual = TestKit.test, TestKit.expectTrue, TestKit.expectEqual

-- The crayon colours are Color3s: Lune's stand-in for them.
local Rules = luau.load(fs.readFile("src/shared/Logic/TraceRace.luau"), {
	debugName = "TraceRace",
	environment = { Color3 = roblox.Color3 },
})()

-- A stand-in for Roblox's Random (Generate only asks it for numbers), seeded so every run is the same.
local function random(seed: number): any
	local source = TestKit.seeded(seed)
	return {
		NextNumber = function(_, low: number?, high: number?): number
			local a, b = low or 0, high or 1
			return a + (b - a) * source.float()
		end,
		NextInteger = function(_, low: number, high: number): number
			return math.min(high, low + math.floor(source.float() * (high - low + 1)))
		end,
	}
end

local function course(seed: number): any
	return Rules.Build(Rules.Generate(random(seed)))
end

-- A line through one position per whole stud, so every step is judged right where it was drawn, at
-- x = where(s). Returns the tracker, what each step scored and the live percent after each step.
local function ride(track: any, where: (number) -> number): (any, { number }, { number })
	local tracker = Rules.Tracker(track)
	local steps, live = {}, {}
	for s = 0, track.Length do
		local before = tracker.Sum
		tracker:Add(s, where(s))
		steps[s] = tracker.Sum - before
		live[s] = tracker:Live()
	end
	return tracker, steps, live
end

test("Bounds: anywhere on the paper, a stud and a half inside its outer edges", function()
	expectEqual({ Rules.Bounds(1, 1) }, { -11.5, 11.5 }, "one rider")
	expectEqual({ Rules.Bounds(2, 3) }, { -27.5, 27.5 }, "the middle one of three")
	expectEqual({ Rules.Bounds(1, 12) }, { -11.5, 187.5 }, "the left-most of twelve")
	expectEqual({ Rules.Bounds(12, 12) }, { -187.5, 11.5 }, "the right-most of twelve")
	for count = 1, 12 do
		-- The server's paper: count * LANE + 2 * MARGIN wide, its middle under the lanes' middle.
		local half = count * Rules.LANE / 2 + Rules.MARGIN
		for index = 1, count do
			local middle = (index - (count + 1) / 2) * Rules.LANE
			local lo, hi = Rules.Bounds(index, count)
			expectEqual(middle + lo, -half + Rules.EDGE, `lane {index} of {count}: the left edge`)
			expectEqual(middle + hi, half - Rules.EDGE, `lane {index} of {count}: the right edge`)
			-- The rider's own lane is all reachable, and so is every other lane's guide.
			expectTrue(lo <= -Rules.LANE / 2 and hi >= Rules.LANE / 2, `lane {index} of {count}: its own lane`)
			expectTrue(lo <= (1 - index) * Rules.LANE - Rules.AMP, `lane {index} of {count}: lane 1's guide`)
			expectTrue(hi >= (count - index) * Rules.LANE + Rules.AMP, `lane {index} of {count}: lane {count}'s guide`)
		end
	end
	-- Bots keep to their own lane, which the guide never leaves.
	expectTrue(Rules.AMP < Rules.LIMIT and Rules.LIMIT < Rules.LANE / 2, "the guide and bots stay in the lane")
	-- The crayon (2.4 studs across, tools/meshgen/props/TraceRace.py) stays on the paper at its edge.
	expectTrue(Rules.EDGE >= 1.25, "the crayon's body stays on the paper")
end)

test("Accuracy: a step a lane or more away from the rider's own guide scores 0", function()
	for seed = 1, 20 do
		local track = course(seed)
		for s = 0, track.Length, 0.5 do
			local guide = Rules.GuideAt(track, s)
			for _, gap in { 4, 8, Rules.LANE, 2 * Rules.LANE, 11 * Rules.LANE + Rules.AMP } do
				for _, side in { -1, 1 } do
					local x = guide + side * gap
					local score = Rules.Accuracy(Rules.Distance(track, s, x))
					expectEqual(score, 0, `seed {seed}: s {s}, x {x} (the guide at {guide})`)
				end
			end
		end
	end
end)

test("Tracker: a stretch ridden along the neighbour's guide scores 0, the rest full marks", function()
	for _, side in { -1, 1 } do
		local track = course(7)
		local from, to = 120, 220
		local function away(s: number): boolean
			return s >= from and s <= to
		end
		local tracker, steps = ride(track, function(s)
			return Rules.GuideAt(track, s) + (if away(s) then side * Rules.LANE else 0)
		end)
		for s = 0, track.Length do
			expectEqual(steps[s], if away(s) then 0 else 1, `side {side}: step {s}`)
		end
		local drawn = track.Length + 1
		expectEqual(tracker.Count, drawn, "every step counted")
		expectEqual(tracker.Sum, drawn - (to - from + 1), "only the steps on the rider's own guide score")
		-- The final percent: what's left of the gap between never steering and a perfect line.
		local share = math.clamp((tracker.Sum - track.Idle) / (drawn - track.Idle), 0, 1)
		expectEqual(tracker:Score(), math.floor(share * 1000 + 0.5) / 10, "the final percent")
		expectTrue(tracker:Score() < 100, "lower than a perfect line")
	end
end)

test("Tracker: the live percent drops while the crayon is away and climbs once it's back", function()
	local track = course(11)
	local from, to = 150, 230
	local _, _, live = ride(track, function(s)
		local guide = Rules.GuideAt(track, s)
		if s >= from and s <= to then
			return guide + 2 * Rules.LANE -- two lanes over
		end
		return guide
	end)
	expectEqual(live[from - 1], 100, "a perfect line so far")
	for s = from + 1, to do
		expectTrue(live[s] <= live[s - 1], `away at {s}: {live[s]} after {live[s - 1]}`)
	end
	expectTrue(live[to] < live[from - 1], `away: down to {live[to]}`)
	expectTrue(live[track.Length] > live[to], `back on the guide: up to {live[track.Length]}`)
end)

test("Tracker: a line wandering over the whole paper scores only where it's on the rider's own guide", function()
	local track = course(3)
	local lo, hi = Rules.Bounds(4, 6) -- the 4th lane of six
	-- Out to the paper's right edge, across to its left edge, then back home on the guide.
	local function where(s: number): number
		if s < 60 or s > 300 then
			return Rules.GuideAt(track, s)
		elseif s < 140 then
			return hi
		end
		return lo
	end
	local tracker, steps = ride(track, where)
	local expected = 0
	for s = 0, track.Length do
		local home = s < 60 or s > 300
		expectEqual(steps[s], if home then 1 else 0, `step {s}`)
		expected += if home then 1 else 0
	end
	expectEqual(tracker.Sum, expected, "the home stretches only")
end)

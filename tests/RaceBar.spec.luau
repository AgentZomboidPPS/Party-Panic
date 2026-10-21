local TestKit = require("./TestKit")
local RaceBar = require("../src/shared/Logic/RaceBar")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

-- Skate Escape's phone bar: 496 units long, dots 30 across (yours 36), packs step 15 off the line.
local OPTIONS = { Width = 496, Lift = 15 }

local function dot(key: string, x: number, size: number?, tier: number?, rank: number?): RaceBar.Dot
	return { Key = key, X = x, Size = size or 30, Tier = tier, Rank = rank }
end

-- Every pair of dots is clear enough that their numbers show: centres at least their combined radius
-- apart, less the allowed rim overlap.
local function expectReadable(spots: { [string]: RaceBar.Spot }, dots: { RaceBar.Dot })
	for i, a in dots do
		for j = i + 1, #dots do
			local b = dots[j]
			local sa, sb = spots[a.Key], spots[b.Key]
			local distance = math.sqrt((sa.X - sb.X) ^ 2 + (sa.Y - sb.Y) ^ 2)
			local need = (a.Size + b.Size) / 2 - 2.01
			expectTrue(distance >= need, `{a.Key} and {b.Key} overlap: {distance} < {need}`)
		end
	end
end

test("RaceBar.Layout: riders far apart stay on the line, exactly where they are", function()
	local dots = { dot("a", 40), dot("b", 200), dot("c", 480) }
	local spots = RaceBar.Layout(dots, OPTIONS)
	expectEqual(spots.a, { X = 40, Y = 0, Tier = 0, Rank = 1 })
	expectEqual(spots.b, { X = 200, Y = 0, Tier = 0, Rank = 2 })
	expectEqual(spots.c, { X = 480, Y = 0, Tier = 0, Rank = 3 })
end)

test("RaceBar.Layout: two riders level with each other show one above the other", function()
	local dots = { dot("a", 250), dot("b", 250) }
	local spots = RaceBar.Layout(dots, OPTIONS)
	expectEqual(spots.a.Tier, -1)
	expectEqual(spots.b.Tier, 1)
	expectEqual(spots.a.Y, -15)
	expectEqual(spots.b.Y, 15)
	-- Nudged apart only a little, evenly around where they both are.
	expectTrue(math.abs((spots.a.X + spots.b.X) / 2 - 250) < 0.001, "pair stays centred")
	expectTrue(spots.b.X - spots.a.X <= 15, "pair stays close")
	expectReadable(spots, dots)
end)

test("RaceBar.Layout: a pack keeps its order and every number clear", function()
	local dots = { dot("a", 300), dot("b", 296), dot("c", 305), dot("me", 301, 36), dot("d", 299) }
	local spots = RaceBar.Layout(dots, OPTIONS)
	expectReadable(spots, dots)
	local order = { "b", "d", "a", "me", "c" }
	for index = 2, #order do
		expectTrue(spots[order[index]].X > spots[order[index - 1]].X, `{order[index]} after {order[index - 1]}`)
		expectTrue(spots[order[index]].Tier == -spots[order[index - 1]].Tier, "sides alternate")
	end
end)

test("RaceBar.Layout: everyone on the start line stays on the bar, readable", function()
	local dots = {}
	for lane = 1, 12 do
		table.insert(dots, dot(tostring(lane), 0, if lane == 5 then 36 else 30))
	end
	local spots = RaceBar.Layout(dots, OPTIONS)
	expectReadable(spots, dots)
	for _, item in dots do
		expectTrue(spots[item.Key].X >= 0 and spots[item.Key].X <= 496, `{item.Key} on the bar`)
	end
	-- The same at the finish flag.
	for _, item in dots do
		item.X = 496
	end
	spots = RaceBar.Layout(dots, OPTIONS)
	expectReadable(spots, dots)
	for _, item in dots do
		expectTrue(spots[item.Key].X <= 496, `{item.Key} on the bar at the finish`)
	end
end)

test("RaceBar.Layout: riders keep their side while the pack lasts", function()
	-- b was above and a below; now b has dropped just behind a: they keep their sides.
	local spots = RaceBar.Layout({ dot("a", 250, 30, 1), dot("b", 245, 30, -1) }, OPTIONS)
	expectEqual(spots.a.Tier, 1)
	expectEqual(spots.b.Tier, -1)
	-- A third rider joins the back of the pack: the two keep theirs, it takes the other side of b.
	spots = RaceBar.Layout({ dot("a", 250, 30, 1), dot("b", 245, 30, -1), dot("c", 238) }, OPTIONS)
	expectEqual(spots.a.Tier, 1)
	expectEqual(spots.b.Tier, -1)
	expectEqual(spots.c.Tier, 1)
end)

test("RaceBar.Layout: a pack breaks up only once its riders are clearly apart", function()
	-- 32 apart: two dots of 30 clear each other on the line, but a split pair holds a bit longer.
	local held = RaceBar.Layout({ dot("a", 200, 30, -1), dot("b", 232, 30, 1) }, OPTIONS)
	expectEqual(held.a.Tier, -1)
	expectEqual(held.b.Tier, 1)
	local fresh = RaceBar.Layout({ dot("a", 200), dot("b", 232) }, OPTIONS)
	expectEqual(fresh.a.Tier, 0)
	expectEqual(fresh.b.Tier, 0)
	local apart = RaceBar.Layout({ dot("a", 200, 30, -1), dot("b", 240, 30, 1) }, OPTIONS)
	expectEqual(apart.a.Tier, 0)
	expectEqual(apart.b.Tier, 0)
end)

test("RaceBar.Layout: riders level with each other keep their order until one is clearly ahead", function()
	-- b was ahead of a; now a is a hair in front (the numbers wobble): nothing moves.
	local spots = RaceBar.Layout({ dot("a", 252, 30, 1, 1), dot("b", 250, 30, -1, 2) }, OPTIONS)
	expectEqual({ spots.a.Rank, spots.a.Tier, spots.b.Rank, spots.b.Tier }, { 1, 1, 2, -1 })
	expectTrue(spots.a.X <= spots.b.X, "a not drawn ahead of b")
	-- a pulls clearly ahead: they swap places, and sides, and no one else moves.
	spots = RaceBar.Layout(
		{ dot("c", 236, 30, -1, 1), dot("a", 258, 30, 1, 2), dot("b", 250, 30, -1, 3), dot("d", 262, 30, 1, 4) },
		OPTIONS
	)
	expectEqual({ spots.c.Rank, spots.b.Rank, spots.a.Rank, spots.d.Rank }, { 1, 2, 3, 4 })
	expectEqual({ spots.c.Tier, spots.b.Tier, spots.a.Tier, spots.d.Tier }, { -1, 1, -1, 1 })
end)

test("RaceBar.Layout: any race, frame after frame: every number clear, every dot on the bar", function()
	math.randomseed(7)
	for _ = 1, 300 do
		local dots = {}
		local spots: { [string]: RaceBar.Spot } = {}
		local count = math.random(2, 12)
		for lane = 1, count do
			-- Riders bunched up somewhere, a few of them level.
			local x = math.clamp(200 + math.random(-40, 40) * (if lane % 3 == 0 then 0 else 1), 0, 496)
			table.insert(dots, dot(tostring(lane), x, if lane == 1 then 36 else 30))
		end
		for _ = 1, 5 do -- a few frames, the riders moving, the layout remembering itself
			for _, item in dots do
				local spot = spots[item.Key]
				item.Tier = spot and spot.Tier
				item.Rank = spot and spot.Rank
				item.X = math.clamp(item.X + math.random() * 6 - 3, 0, 496)
			end
			spots = RaceBar.Layout(dots, OPTIONS)
			expectReadable(spots, dots)
			for _, item in dots do
				local spot = spots[item.Key]
				expectTrue(spot.X >= 0 and spot.X <= 496, "on the bar")
				expectTrue(math.abs(spot.X - item.X) <= 12 * 16, "near its rider")
			end
		end
	end
end)

test("RaceBar.Layout: no riders, no dots", function()
	expectEqual(RaceBar.Layout({}, OPTIONS), {})
end)

local TestKit = require("./TestKit")
local EatsaPizza = require("../src/shared/Logic/EatsaPizza")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local function near(a: number, b: number, slack: number?): boolean
	return math.abs(a - b) <= (slack or 1e-9)
end

test("Front: from the crust to the last bite, through each stage's reach, never behind the slice", function()
	expectEqual(EatsaPizza.Front(40, 40), 1)
	expectEqual(EatsaPizza.Front(0, 40), 0)
	expectEqual(EatsaPizza.Front(5, 0), 0)
	for stage = 0, 3 do
		-- (where a stage starts, the front is at that stage's reach)
		local left = 40 - stage * 10
		expectTrue(near(EatsaPizza.Front(left, 40), EatsaPizza.REACH[stage + 1]))
	end
	expectTrue(near(EatsaPizza.Front(1e-6, 1), EatsaPizza.LAST_REACH, 1e-5))
	local last = math.huge
	for left = 40, 1, -1 do
		local front = EatsaPizza.Front(left, 40)
		expectTrue(front < last or left == 40) -- it only ever moves in
		last = front
		-- It's never behind the slice drawn for that many bites (a pepperoni it passed is off the mesh).
		local stage = EatsaPizza.Stage(left, 40)
		expectTrue(front <= EatsaPizza.REACH[stage + 1] + 1e-9)
	end
end)

test("ChiliSpot: on a border between two teams' parts, half way out, each border in turn", function()
	local radius = 30
	for teams = 2, 4 do
		local per = EatsaPizza.PerTeam(teams)
		local seen = {}
		for k = 1, teams * 2 do
			local x, z = EatsaPizza.ChiliSpot(k, teams, radius, 1)
			expectTrue(near(math.sqrt(x * x + z * z), radius * EatsaPizza.CHILI_OUT, 1e-6))
			-- The slices just either side of it belong to two different teams.
			local a = math.atan2(x, z) % (2 * math.pi)
			local after = math.floor(a / EatsaPizza.SLICE_ANGLE + 0.5) % EatsaPizza.SLICES + 1
			local before = (after - 2) % EatsaPizza.SLICES + 1
			local order = {}
			for index = 1, teams do
				order[index] = `T{index}`
			end
			local one, other = EatsaPizza.Owner(order, after), EatsaPizza.Owner(order, before)
			expectTrue(one ~= nil and other ~= nil and one ~= other)
			seen[after] = (seen[after] or 0) + 1
			expectEqual(after % per, 1 % per)
		end
		-- Every border gets its turn, as often as the others.
		local borders = 0
		for _, times in seen do
			borders += 1
			expectEqual(times, 2)
		end
		expectEqual(borders, teams)
	end
end)

test("the hot pepper's numbers: a short burst, under the round, fair to grab", function()
	expectTrue(EatsaPizza.SPICY_BITES == 2)
	expectTrue(EatsaPizza.SPICY_TIME > 0 and EatsaPizza.SPICY_TIME <= 6)
	expectTrue(EatsaPizza.CHILI_FIRST + EatsaPizza.CHILI_LIFE < 30)
	expectTrue(EatsaPizza.CHILI_REACH >= 3) -- a phone player running past it gets it
end)

-- Bite spots --------------------------------------------------------------------------------------

-- A small, repeatable random source (the tests must not depend on Random).
local function lcg(seed: number): () -> number
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local function flat(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end

-- Which slice an offset from the middle is over (by angle).
local function sliceAt(x: number, z: number): number
	local a = math.atan2(x, z) % (2 * math.pi)
	return math.floor(a / EatsaPizza.SLICE_ANGLE) % EatsaPizza.SLICES + 1
end

test("SpotsFor: one spot out for each player, the same deal for every team", function()
	expectEqual(EatsaPizza.SpotsFor(0), 0)
	for players = 1, 6 do
		expectEqual(EatsaPizza.SpotsFor(players), players)
	end
end)

test("SpotBites: about SPOT_BITES a spot, a slice's rest shared out so the last spot isn't tiny", function()
	expectEqual(EatsaPizza.SpotBites(0), 0)
	expectEqual(EatsaPizza.SpotBites(-3), 0)
	expectEqual(EatsaPizza.SpotBites(3), 3) -- (a slice that small is one spot)
	for total = 1, 200 do
		local left, spots = total, 0
		while left > 0 do
			local bites = EatsaPizza.SpotBites(left)
			expectTrue(bites >= 1 and bites <= left)
			if total >= EatsaPizza.SPOT_BITES then
				-- Never a spot under half of SPOT_BITES or over one and a half.
				expectTrue(bites >= math.ceil(EatsaPizza.SPOT_BITES / 2), `{total}: a {bites}-bite spot`)
			end
			expectTrue(bites <= math.ceil(EatsaPizza.SPOT_BITES * 1.5))
			left -= bites
			spots += 1
		end
		expectEqual(left, 0)
		expectTrue(spots <= math.max(1, math.floor(total / EatsaPizza.SPOT_BITES + 0.5)) + 1)
	end
end)

test("SpotOuter and SpotStage: inside the slice's crust or tooth marks, further in as it's eaten", function()
	for _, radius in { 26, 30, 38 } do
		local last = math.huge
		for stage = 0, 3 do
			local outer = EatsaPizza.SpotOuter(stage, radius)
			expectTrue(outer < EatsaPizza.Reach(stage, radius) - EatsaPizza.SPOT_RADIUS * 0.5)
			expectTrue(outer < last)
			-- (Even the last stage has room for a spot outside the middle.)
			expectTrue(outer >= EatsaPizza.SPOT_INNER, `radius {radius} stage {stage}: {outer}`)
			last = outer
		end
	end
	-- The stage while the last claimed bite is still to eat: the one a slice with one more bite is at.
	expectEqual(EatsaPizza.SpotStage(39, 40), 0)
	expectEqual(EatsaPizza.SpotStage(0, 40), 3)
	expectEqual(EatsaPizza.SpotStage(-2, 40), 3)
	expectEqual(EatsaPizza.SpotStage(19, 40), EatsaPizza.Stage(20, 40))
end)

test("SpotPoints: on their slice, out to the edge given, never in the middle", function()
	for _, radius in { 26, 38 } do
		for index = 1, EatsaPizza.SLICES do
			for stage = 0, 3 do
				local outer = EatsaPizza.SpotOuter(stage, radius)
				local points = EatsaPizza.SpotPoints(index, outer)
				expectTrue(#points >= 1)
				for _, point in points do
					local d = flat(point.X, point.Z)
					expectTrue(d <= outer + 1e-6 and d >= EatsaPizza.SPOT_INNER - 1e-6)
					expectEqual(sliceAt(point.X, point.Z), index)
				end
			end
		end
	end
end)

test("SpotScore: never on another ring; about SPOT_RUN from the eater; apart from the team's others", function()
	expectEqual(EatsaPizza.SpotScore(0, 10, nil, { { X = 1, Z = 10, Left = 3 } }), nil)
	expectEqual(EatsaPizza.SpotScore(0, 10, nil, { { X = 6, Z = 10, Left = 3 } }), 0) -- (a rival's: no gap)
	local near = EatsaPizza.SpotScore(0, 10, nil, { { X = 6, Z = 10, Left = 3, Mine = true } }) :: number
	local far = EatsaPizza.SpotScore(0, 10, nil, { { X = 12, Z = 10, Left = 3, Mine = true } }) :: number
	expectTrue(near < far and far == 0)
	local from = { X = 0, Z = 0 }
	local best = EatsaPizza.SpotScore(0, EatsaPizza.SPOT_RUN, from, {}) :: number
	local tooNear = EatsaPizza.SpotScore(0, EatsaPizza.SPOT_RUN - 5, from, {}) :: number
	local tooFar = EatsaPizza.SpotScore(0, EatsaPizza.SPOT_RUN + 5, from, {}) :: number
	expectTrue(best > tooFar and tooFar > tooNear)
end)

test("OnSpot: the nearest spot within reach, else none", function()
	local spots = { { X = 0, Z = 10 }, { X = 0, Z = 14 } }
	expectEqual(EatsaPizza.OnSpot(0, 10.5, spots), 1)
	expectEqual(EatsaPizza.OnSpot(0, 13, spots), 2)
	expectEqual(EatsaPizza.OnSpot(EatsaPizza.SPOT_REACH - 0.05, 10, spots), 1)
	expectEqual(EatsaPizza.OnSpot(EatsaPizza.SPOT_REACH + 0.05, 10, spots), nil)
	expectEqual(EatsaPizza.OnSpot(0, 0, {}), nil)
end)

test("PlaceSpot: nothing once a team's food is all claimed; a fresh part gets a spot SPOT_RUN out", function()
	local slices = { { Index = 1, Left = 0, Max = 30, Stage = 3 }, { Index = 2, Left = 6, Max = 30, Stage = 3 } }
	-- (Every bite left is in a spot already.)
	local placed = EatsaPizza.PlaceSpot(slices, { { Slice = 2, X = 0, Z = 6, Left = 6, Mine = true } }, 30, nil)
	expectEqual(placed, nil)
	expectEqual(EatsaPizza.PlaceSpot({ { Index = 1, Left = 0, Max = 30, Stage = 3 } }, {}, 30, nil), nil)

	local fresh = {}
	for index = 1, 6 do
		table.insert(fresh, { Index = index, Left = 40, Max = 40, Stage = 0 })
	end
	local from = { X = 10, Z = 10 }
	local spot = EatsaPizza.PlaceSpot(fresh, {}, 32, from) :: EatsaPizza.Placed
	expectTrue(spot ~= nil)
	expectEqual(spot.Bites, EatsaPizza.SPOT_BITES)
	local run = flat(spot.X - from.X, spot.Z - from.Z)
	expectTrue(math.abs(run - EatsaPizza.SPOT_RUN) < 2, `ran {run}`)
	expectTrue(spot.Slice >= 1 and spot.Slice <= 6 and sliceAt(spot.X, spot.Z) == spot.Slice)
end)

-- Plays a team's part out the way the server does: `players` spots out at a time, a random one of them
-- eaten a bite at a time (two at a time now and then, like the hot pepper), each eaten one replaced
-- from where it was. Checks every spot is on food until it's eaten, no slice has more bites claimed
-- than it has left, rings never overlap, and the whole part gets eaten.
local function playOut(radius: number, maxes: { number }, players: number, seed: number): (number, number, { number })
	local rng = lcg(seed)
	local slices = {}
	for k, max in maxes do
		table.insert(slices, { Index = k, Left = max, Max = max, Stage = 0 })
	end
	local spots = {}
	local placedCount, small, runs = 0, 0, {}
	local function fill(from: { X: number, Z: number }?)
		while #spots < EatsaPizza.SpotsFor(players) do
			local placed = EatsaPizza.PlaceSpot(slices, spots, radius, from, rng)
			if not placed then
				break
			end
			expectTrue(placed.Bites >= 1)
			if placed.Bites < math.ceil(EatsaPizza.SPOT_BITES / 2) then
				small += 1
			end
			if from then
				table.insert(runs, flat(placed.X - from.X, placed.Z - from.Z))
			end
			for _, other in spots do
				expectTrue(flat(placed.X - other.X, placed.Z - other.Z) >= EatsaPizza.SPOT_RADIUS * 2 - 1e-6)
			end
			placedCount += 1
			table.insert(spots, { Slice = placed.Slice, X = placed.X, Z = placed.Z, Left = placed.Bites, Mine = true })
		end
	end
	fill(nil)
	local eaten, total, guard = 0, 0, 0
	for _, max in maxes do
		total += max
	end
	while #spots > 0 and guard < 10000 do
		guard += 1
		local k = math.floor(rng() * #spots) + 1
		local spot = spots[k]
		local slice = slices[spot.Slice]
		local bites = math.min(if rng() < 0.15 then 2 else 1, spot.Left, slice.Left)
		expectTrue(bites >= 1)
		spot.Left -= bites
		slice.Left -= bites
		eaten += bites
		slice.Stage = math.max(slice.Stage, EatsaPizza.Stage(math.max(slice.Left, 0), slice.Max))
		-- Claims never pass what the slice has left, and every spot still to eat is on its food.
		local claimed = 0
		for _, other in spots do
			if other.Slice == slice.Index then
				claimed += other.Left
				if other.Left > 0 then
					local d = flat(other.X, other.Z)
					local outer = EatsaPizza.SpotOuter(slice.Stage, radius)
					expectTrue(d <= outer + 1e-6, `a spot {d} out on a slice that reaches {outer}`)
				end
			end
		end
		expectTrue(claimed <= slice.Left)
		if spot.Left <= 0 then
			table.remove(spots, k)
			fill({ X = spot.X, Z = spot.Z })
		end
	end
	expectEqual(eaten, total)
	for _, slice in slices do
		expectEqual(slice.Left, 0)
	end
	return placedCount, small, runs
end

-- A team's slices as the server sizes them: PER_PLAYER a player spread over the part, more on the
-- slices with more pepperoni.
local function sized(slices: number, players: number): { number }
	local maxes, weights, sum = {}, {}, 0
	for k = 1, slices do
		weights[k] = 1 + (({ 1, 2, 3, 4, 2, 3 })[k] + k % 2) * EatsaPizza.PEPPERONI_WEIGHT
		sum += weights[k]
	end
	for k = 1, slices do
		maxes[k] = math.max(4, math.floor(EatsaPizza.PER_PLAYER * players * weights[k] / sum + 0.5))
	end
	return maxes
end

test("PlaceSpot: a whole part eaten spot by spot, every spot on food, for every team size", function()
	local layouts = {
		{ radius = 26.4, slices = 6, players = 1 }, -- 2 players: two teams of one
		{ radius = 28.8, slices = 6, players = 2 },
		{ radius = 31.2, slices = 4, players = 2 }, -- 6 players: three teams of two
		{ radius = 36, slices = 3, players = 3 }, -- 10 players: teams of three and two
		{ radius = 36, slices = 3, players = 2 },
		{ radius = 38, slices = 3, players = 3 }, -- 12 players: four teams of three
	}
	for seed, layout in layouts do
		local placed, small, runs =
			playOut(layout.radius, sized(layout.slices, layout.players), layout.players, seed * 7919)
		-- About PER_PLAYER / SPOT_BITES spots a player, hardly any small ones.
		local per = placed / layout.players
		local expected = EatsaPizza.PER_PLAYER / EatsaPizza.SPOT_BITES
		expectTrue(per >= expected * 0.75 and per <= expected * 1.4, `{per} spots a player`)
		expectTrue(small <= placed * 0.15, `{small} of {placed} small`)
		-- Everyone keeps running: a new spot is mostly a proper run from where the last one was.
		local long = 0
		for _, run in runs do
			if run >= EatsaPizza.SPOT_RUN * 0.5 then
				long += 1
			end
		end
		expectTrue(long >= #runs * 0.6, `{long} of {#runs} runs long`)
	end
end)

test("PlaceSpot: the same deal for teams of different sizes (spots per player)", function()
	-- A team of three and a team of two on the same pizza (the same slices, PER_PLAYER a player).
	local three = playOut(36, sized(3, 3), 3, 101) / 3
	local two = playOut(36, sized(3, 2), 2, 202) / 2
	expectTrue(math.abs(three - two) <= 2, `{three} vs {two} spots a player`)
end)

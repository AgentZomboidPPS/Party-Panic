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

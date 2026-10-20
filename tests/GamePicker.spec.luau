local TestKit = require("./TestKit")
local GamePicker = require("../src/shared/Logic/GamePicker")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local POOL = {
	{ Id = "Flattened", Category = "Survival", MinPlayers = 1 },
	{ Id = "Lava", Category = "Survival", MinPlayers = 1 },
	{ Id = "Yeet", Category = "Knockback", MinPlayers = 2 },
	{ Id = "Carts", Category = "Race", MinPlayers = 1 },
	{ Id = "Goblins", Category = "Team", MinPlayers = 2 },
	{ Id = "Button", Category = "Reaction", MinPlayers = 1 },
}

local function contains(list, value)
	return table.find(list, value) ~= nil
end

test("GamePicker.Pick returns three distinct games", function()
	for seed = 1, 200 do
		local rng = TestKit.seeded(seed)
		local picked = GamePicker.Pick(POOL, { PlayerCount = 6, Count = 3, RandomFloat = rng.float })
		expectEqual(#picked, 3)
		local seen = {}
		for _, id in picked do
			expectTrue(not seen[id], `duplicate {id} with seed {seed}`)
			seen[id] = true
		end
	end
end)

test("GamePicker.Pick respects minimum player counts", function()
	for seed = 1, 200 do
		local rng = TestKit.seeded(seed)
		local picked = GamePicker.Pick(POOL, { PlayerCount = 1, Count = 3, RandomFloat = rng.float })
		expectTrue(not contains(picked, "Yeet") and not contains(picked, "Goblins"), "two-player modes offered solo")
	end
end)

test("GamePicker.Pick can ignore player limits for solo testing", function()
	local found = false
	for seed = 1, 200 do
		local rng = TestKit.seeded(seed)
		local picked =
			GamePicker.Pick(POOL, { PlayerCount = 1, Count = 3, RandomFloat = rng.float, IgnorePlayerLimits = true })
		if contains(picked, "Yeet") then
			found = true
		end
	end
	expectTrue(found, "IgnorePlayerLimits should allow two-player modes")
end)

test("GamePicker.Pick never offers the last played game when the pool is large enough", function()
	for seed = 1, 200 do
		local rng = TestKit.seeded(seed)
		local picked =
			GamePicker.Pick(POOL, { PlayerCount = 6, Count = 3, Recent = { "Lava", "Carts" }, RandomFloat = rng.float })
		expectTrue(not contains(picked, "Lava"), `last played game offered with seed {seed}`)
	end
end)

test("GamePicker.Pick down-weights recently played games", function()
	local recentHits, freshHits = 0, 0
	for seed = 1, 500 do
		local rng = TestKit.seeded(seed)
		local picked =
			GamePicker.Pick(POOL, { PlayerCount = 6, Count = 3, Recent = { "Lava", "Carts" }, RandomFloat = rng.float })
		if contains(picked, "Carts") then
			recentHits += 1
		end
		if contains(picked, "Button") then
			freshHits += 1
		end
	end
	expectTrue(recentHits < freshHits, `recent {recentHits} should be offered less than fresh {freshHits}`)
end)

test("GamePicker.Pick tends to mix categories", function()
	local bothSurvival = 0
	for seed = 1, 500 do
		local rng = TestKit.seeded(seed)
		local picked = GamePicker.Pick(POOL, { PlayerCount = 6, Count = 3, RandomFloat = rng.float })
		if contains(picked, "Flattened") and contains(picked, "Lava") then
			bothSurvival += 1
		end
	end
	-- Without category weighting this happens ~20% of the time.
	expectTrue(bothSurvival < 75, `two survival games offered together {bothSurvival} times`)
end)

test("GamePicker.Pick returns fewer options when the pool is small", function()
	local rng = TestKit.seeded(7)
	local picked = GamePicker.Pick({ POOL[1], POOL[2] }, { PlayerCount = 4, Count = 3, RandomFloat = rng.float })
	expectEqual(#picked, 2)
end)

test("GamePicker.Pick skips disabled games", function()
	local pool = table.clone(POOL)
	pool[6] = { Id = "Button", Category = "Reaction", MinPlayers = 1, Enabled = false }
	for seed = 1, 100 do
		local rng = TestKit.seeded(seed)
		expectTrue(
			not contains(GamePicker.Pick(pool, { PlayerCount = 6, Count = 3, RandomFloat = rng.float }), "Button")
		)
	end
end)

return nil

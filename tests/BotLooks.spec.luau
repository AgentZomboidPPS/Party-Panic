-- Bots pass for real players (owner: "Can we make the bots look more like real players?"): every
-- look is a whole outfit from the lists (Shared/Logic/BotLooks), the lists have no repeats, the mix
-- has variety, and names look like players' and are never longer than Roblox allows or taken twice.
local TestKit = require("./TestKit")
local BotLooks = require("../src/shared/Logic/BotLooks")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

-- A seeded stand-in for Random:NextNumber.
local function generator(seed: number): () -> number
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local function has(list: { number }, id: number?): boolean
	return id ~= nil and table.find(list, id) ~= nil
end

test("Bots: every look is a whole outfit from the lists", function()
	local roll = generator(7)
	local heads, hats, bodies, hairless = 0, 0, 0, 0
	for _ = 1, 400 do
		local look = BotLooks.Outfit(roll)
		expectTrue(has(BotLooks.Shirts, look.Shirt) and has(BotLooks.Pants, look.Pants), "shirt and pants")
		expectTrue(look.Head == 0 or has(BotLooks.Heads, look.Head), "a dynamic head or Roblox's default one")
		expectTrue(look.Hair == nil or has(BotLooks.Hair, look.Hair), "hair")
		expectTrue(look.Hat == nil or has(BotLooks.Hats, look.Hat), "hat")
		expectTrue(look.Glasses == nil or has(BotLooks.Glasses, look.Glasses), "glasses")
		expectTrue(look.Back == nil or has(BotLooks.Backs, look.Back), "back")
		expectTrue(table.find(BotLooks.Skins, look.Skin) ~= nil, "skin")
		if look.Body then
			bodies += 1
			expectEqual(#look.Body, 5)
		end
		heads += if look.Head ~= 0 then 1 else 0
		hats += if look.Hat then 1 else 0
		hairless += if look.Hair == nil and look.Hat == nil then 1 else 0
	end
	-- Variety like a real lobby: most in a dynamic head of their own, a few hats, some other bodies,
	-- and nearly nobody bald.
	expectTrue(heads > 300 and heads < 380, `dynamic heads {heads}`)
	expectTrue(hats > 40 and hats < 140, `hats {hats}`)
	expectTrue(bodies > 120 and bodies < 240, `other bodies {bodies}`)
	expectTrue(hairless < 35, `bald {hairless}`)
end)

test("Bots: the item lists have no repeats", function()
	local seen = {}
	for _, key in { "Heads", "Hair", "Hats", "Glasses", "Backs", "Shirts", "Pants" } do
		for _, id in (BotLooks :: any)[key] do
			expectTrue(not seen[id], `{id} in {key} is listed twice`)
			seen[id] = true
		end
	end
end)

test("Bots: names look like players' and fit", function()
	local roll = generator(11)
	local taken = {}
	local plainFirst = 0
	for _ = 1, 300 do
		local name = BotLooks.FreshName(roll, taken)
		expectTrue(#name >= 3 and #name <= BotLooks.MAX_NAME, name)
		expectTrue(string.match(name, "^[%w_]+$") ~= nil, `only letters, digits and _: {name}`)
		expectTrue(not taken[name], `{name} twice`)
		taken[name] = true
		plainFirst += if table.find(BotLooks.FirstNames, name) then 1 else 0
	end
	-- Mostly not plain first names (those run out fast and players mostly style theirs).
	expectTrue(plainFirst > 10 and plainFirst < 90, `plain first names {plainFirst}`)
end)

-- The cosmetic catalogue (Shared/Cosmetics) after the second shop pass (told "On the low-coin
-- scale a regular player can buy the whole shop in about a week", the owner said: "Yes lets add
-- more items after everything else is finished"): every item is well formed, the coin items cost
-- what the economy notes say, every effect is really drawn by EffectsController, and every emote
-- plays one of Roblox's own default emote animations.
-- Cosmetics.luau needs Roblox's script tree, so this reads its source, like Payoffs.spec.
local fs = require("@lune/fs")

local TestKit = require("./TestKit")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local cosmeticsSource = fs.readFile("src/shared/Cosmetics.luau")
local effectsSource = fs.readFile("src/client/Controllers/EffectsController.luau")
local configSource = fs.readFile("src/shared/Config.luau")

local SLOTS = { Trail = true, Title = true, Emote = true, Victory = true, Elimination = true }

-- Roblox's default R15 emotes (the /e emotes in its Animate script, all made by Roblox): wave,
-- cheer, point, laugh and the three dances. Checked on a Roblox server: each is an Animation
-- (asset type 24) by Roblox (user 1). The Dance B and C variants are the same animation as A, so
-- they don't count as new emotes.
local DEFAULT_EMOTES = {
	[507770239] = "Wave",
	[507770677] = "Cheer",
	[507770453] = "Point",
	[507770818] = "Laugh",
	[507771019] = "Dance 1",
	[507776043] = "Dance 2",
	[507777268] = "Dance 3",
}

type Item = {
	Id: string,
	Slot: string?,
	Name: string?,
	Price: number?,
	Effect: string?,
	Animation: number?,
	Block: string,
}

-- Each catalogue entry (the top-level `{ ... },` blocks of Cosmetics.luau's list).
local items: { Item } = {}
for block in string.gmatch(cosmeticsSource, "\n\t{\n(.-)\n\t},") do
	local id = string.match(block, 'Id = "([%w_]+)"')
	if id then
		table.insert(items, {
			Id = id,
			Slot = string.match(block, 'Slot = "(%w+)"'),
			Name = string.match(block, 'Name = "([^"]+)"'),
			Price = tonumber(string.match(block, "Price = (%d+)")),
			Effect = string.match(block, 'Effect = "(%w+)"'),
			Animation = tonumber(string.match(block, "Animation = (%d+)")),
			Block = block,
		})
	end
end

-- The effects EffectsController draws: the keys of its EFFECTS table and later `EFFECTS.Name =`.
local effects: { [string]: boolean } = {}
local tableBody = string.match(effectsSource, "local EFFECTS: [^\n]*= {\n(.-)\n}\n") :: string
assert(tableBody, "EffectsController's EFFECTS table not found")
for name in string.gmatch("\n" .. tableBody, "\n\t(%w+) = function") do
	effects[name] = true
end
for name in string.gmatch(effectsSource, "\nEFFECTS%.(%w+) = function") do
	effects[name] = true
end

local function coinItems(): { Item }
	local list = {}
	for _, item in items do
		if item.Price then
			table.insert(list, item)
		end
	end
	return list
end

local function shopTotal(): number
	local total = 0
	for _, item in coinItems() do
		total += item.Price :: number
	end
	return total
end

test("every item has a unique id, a known slot and a name", function()
	expectTrue(#items >= 80, `only {#items} items found`)
	local seen = {}
	for _, item in items do
		expectTrue(not seen[item.Id], `{item.Id} is in the catalogue twice`)
		seen[item.Id] = true
		expectTrue(item.Slot ~= nil and SLOTS[item.Slot :: string], `{item.Id} has slot {tostring(item.Slot)}`)
		expectTrue(item.Name ~= nil and #(item.Name :: string) > 0, `{item.Id} has no name`)
		local prefix = string.match(item.Id, "^(%a+)_")
		local expected =
			{ Trail = "Trail", Title = "Title", Emote = "Emote", Victory = "Victory", Elim = "Elimination" }
		expectEqual(expected[prefix or ""], item.Slot, `{item.Id}'s prefix matches its slot`)
	end
end)

test("every coin item has a price from 8 to 120 and no other way to unlock it", function()
	for _, item in coinItems() do
		local price = item.Price :: number
		expectTrue(price >= 8 and price <= 120, `{item.Id} costs {price}`)
		for _, key in { "UnlockLevel", "UnlockStat", "Vip", "Default" } do
			expectTrue(not string.find(item.Block, key .. " =", 1, true), `{item.Id} has a Price and {key}`)
		end
	end
end)

test("the shop has cheap, middle and save-up-for items in every slot", function()
	local coin = coinItems()
	expectTrue(#coin >= 40 and #coin <= 50, `{#coin} coin items`)
	local cheap, middle, top = 0, 0, 0
	local perSlot: { [string]: number } = {}
	for _, item in coin do
		local price = item.Price :: number
		if price <= 20 then
			cheap += 1
		elseif price < 60 then
			middle += 1
		else
			top += 1
		end
		perSlot[item.Slot :: string] = (perSlot[item.Slot :: string] or 0) + 1
	end
	expectTrue(cheap >= 5, `{cheap} cheap items`)
	expectTrue(middle >= 20, `{middle} middle items`)
	expectTrue(top >= 3 and top <= 5, `{top} items to save up for`)
	for slot in SLOTS do
		expectTrue((perSlot[slot] or 0) >= 4, `{slot} sells only {perSlot[slot] or 0} items`)
	end
end)

test("a regular player buys the whole shop in about 3 to 4 weeks", function()
	local function reward(key: string): number
		return tonumber(string.match(configSource, "\n\t" .. key .. " = %{ Coins = (%d+)")) :: number
	end
	-- The economy notes in Cosmetics.luau's header: 15 rounds a day, an average round in an
	-- 8-player game, the first win of the day and the daily gift, which follows the streak table
	-- and stays at its last value once the streak runs past it (DailyLogic.Claim).
	local perRound = reward("Participation")
		+ 0.5 * reward("TopHalf")
		+ (1 / 8) * reward("Winner")
		+ 0.1 * reward("PersonalBest")
	local giftText = string.match(configSource, "Config%.DailyRewards = %{([^}]*)%}") :: string
	local gifts = {}
	for coins in string.gmatch(giftText, "%d+") do
		table.insert(gifts, tonumber(coins) :: number)
	end
	local playing = 15 * perRound + reward("FirstWin")
	local total = shopTotal()
	local saved, days = 0, 0
	while true do
		local today = playing + gifts[math.min(days + 1, #gifts)]
		if saved + today >= total then
			days += (total - saved) / today
			break
		end
		saved += today
		days += 1
	end
	expectEqual(total, 1381, "the total in the economy notes")
	expectTrue(days >= 21 and days <= 25, `the whole shop takes {days} days (the header says about 23)`)
	expectTrue(string.find(cosmeticsSource, "costs 1381", 1, true) ~= nil, "the header's sums are up to date")
	expectTrue(string.find(cosmeticsSource, "about 23 days", 1, true) ~= nil, "the header's days are up to date")
end)

test("every effect an item names is drawn by EffectsController", function()
	local count = 0
	for _, item in items do
		if item.Effect then
			count += 1
			expectTrue(effects[item.Effect :: string], `{item.Id} plays "{item.Effect}", which nothing draws`)
		end
	end
	expectTrue(count >= 30, "the effect items are there")
	for _, name in { "Confetti", "Fireworks", "Ghosts", "Finale", "Supernova", "Zap" } do
		expectTrue(effects[name], `the effect list was read (missing {name})`)
	end
end)

test("victory and knockout items all have an effect; trails and titles have colors", function()
	for _, item in items do
		if item.Slot == "Victory" or item.Slot == "Elimination" then
			expectTrue(item.Effect ~= nil, `{item.Id} has no effect`)
		elseif item.Slot == "Trail" or item.Slot == "Title" then
			expectTrue(string.find(item.Block, "Colors = {", 1, true) ~= nil, `{item.Id} has no colors`)
		elseif item.Slot == "Emote" then
			expectTrue(item.Effect ~= nil or item.Animation ~= nil, `{item.Id} does nothing`)
		end
	end
end)

test("every emote animation is one of Roblox's default emotes", function()
	for _, item in items do
		if item.Animation then
			expectEqual(item.Slot, "Emote", `{item.Id} has an animation`)
			expectTrue(
				DEFAULT_EMOTES[item.Animation :: number] ~= nil,
				`{item.Id} plays {item.Animation}, not a Roblox default emote`
			)
		end
	end
end)

test("emote names fit the phone picker's cells", function()
	for _, item in items do
		if item.Slot == "Emote" then
			expectTrue(#(item.Name :: string) <= 12, `{item.Id}'s name "{item.Name}" is long for the picker`)
		end
	end
end)

return nil

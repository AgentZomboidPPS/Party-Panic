-- The GOLD PASS's lane (owner: "Also we do need a paid battle pass too. I like the current free one.
-- But the paid one should also be insane."): every level from 2 to 100 has a gold reward, pinned here
-- level by level; the cosmetics (Shared/GoldPass, plus the two old VIP items in Shared/Cosmetics) are
-- 33, the showstoppers at 25, 50, 75 and 100, never sold or earned any other way, and every look
-- they need exists (effects, hats with uploaded meshes, built-in trail textures, icons phones show);
-- buying the pass gives every reward already reached at once (Retroactive) and each level's coins
-- only once; the XP boost, the creator rule and the shop's offer (Roblox's price and sale state).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local TestKit = require("./TestKit")
local GoldLane = require("../src/shared/Logic/GoldLane")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local function load(path: string, name: string): any
	return luau.load(fs.readFile(path), {
		debugName = name,
		environment = {
			Color3 = roblox.Color3,
			ColorSequence = roblox.ColorSequence,
			ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
			NumberSequence = roblox.NumberSequence,
			Vector3 = roblox.Vector3,
		},
	})()
end

local GoldPass = load("src/shared/GoldPass.luau", "GoldPass")
local Config = load("src/shared/Config.luau", "Config")
local cosmeticsSource = fs.readFile("src/shared/Cosmetics.luau")
local effectsSource = fs.readFile("src/client/GoldEffects.luau")
local hatsSource = fs.readFile("src/server/World/Hats.luau")
local propsSource = fs.readFile("src/server/World/Props/GoldHats.luau")

-- The catalog's own entries (Shared/Cosmetics), by id: the two old VIP items are gold rewards there.
local catalog = {}
for block in string.gmatch(cosmeticsSource, "\n\t{\n(.-)\n\t},") do
	local id = string.match(block, 'Id = "([%w_]+)"')
	if id then
		catalog[id] = block
	end
end

-- Every gold cosmetic: id -> level, and id -> its entry.
local levels: { [string]: number } = {}
local items: { [string]: any } = {}
for _, item in GoldPass.Items do
	expectTrue(levels[item.Id] == nil, `{item.Id} is in the GOLD PASS twice`)
	levels[item.Id] = item.GoldLevel
	items[item.Id] = item
end
for id, block in catalog do
	local level = tonumber(string.match(block, "GoldLevel = (%d+)"))
	if level then
		levels[id] = level
		items[id] = { Id = id, Slot = string.match(block, 'Slot = "(%w+)"'), GoldLevel = level }
	end
end

local lane = GoldLane.Build(levels, Config.GoldRoad, 100)

-- A level's reward as one word: its cosmetics, or its coins.
local function describe(reward: GoldLane.Reward): string
	if #reward.Items > 0 then
		return `{reward.Level} {table.concat(reward.Items, "+")}`
	end
	return `{reward.Level} +{reward.Coins}`
end

test("every level from 2 to 100 has exactly one kind of gold reward: cosmetics, or coins", function()
	expectEqual(lane[1], nil, "level 1 is where everyone starts: nothing to reach")
	expectEqual(lane[101], nil)
	for level = 2, 100 do
		local reward = lane[level]
		expectTrue(reward ~= nil, `level {level} has a gold reward`)
		expectTrue((reward.Coins > 0) ~= (#reward.Items > 0), `level {level}: coins or cosmetics, not both or neither`)
	end
end)

test("the gold lane, level by level", function()
	local rows = {}
	for level = 2, 100 do
		table.insert(rows, describe(lane[level]))
	end
	expectEqual(rows, {
		"2 Title_VIP",
		"3 +6",
		"4 Emote_MakeItRain",
		"5 +6",
		"6 Trail_VIP",
		"7 +6",
		"8 Elim_GoldDust",
		"9 +6",
		"10 Hat_GoldParty",
		"11 +7",
		"12 Title_HighRoller",
		"13 +7",
		"14 Victory_GoldRush",
		"15 +7",
		"16 +7",
		"17 Trail_GoldLeaf",
		"18 +7",
		"19 +7",
		"20 Emote_HeartOfGold",
		"21 +8",
		"22 Title_Jackpot",
		"23 +8",
		"24 +8",
		"25 Hat_RoyalCrown",
		"26 +8",
		"27 +8",
		"28 Elim_TreasurePop",
		"29 +8",
		"30 Trail_MoltenGold",
		"31 +9",
		"32 +9",
		"33 Victory_GoldenBeam",
		"34 +9",
		"35 Title_CrownJewel",
		"36 +9",
		"37 +9",
		"38 Emote_DiamondDrop",
		"39 +9",
		"40 Hat_GoldenHalo",
		"41 +10",
		"42 +10",
		"43 +10",
		"44 +10",
		"45 Trail_RoseGold",
		"46 +10",
		"47 +10",
		"48 Victory_Champagne",
		"49 +10",
		"50 Trail_LiquidSunlight",
		"51 +11",
		"52 +11",
		"53 +11",
		"54 +11",
		"55 Elim_DiamondShatter",
		"56 +11",
		"57 +11",
		"58 Title_GildedLegend",
		"59 +11",
		"60 Hat_GildedTopHat",
		"61 +12",
		"62 +12",
		"63 +12",
		"64 +12",
		"65 Emote_GoldenAura",
		"66 +12",
		"67 +12",
		"68 +12",
		"69 +12",
		"70 Trail_PlatinumComet",
		"71 +13",
		"72 +13",
		"73 +13",
		"74 +13",
		"75 Victory_GoldenSupernova",
		"76 +13",
		"77 +13",
		"78 +13",
		"79 +13",
		"80 Title_SolidGold",
		"81 +14",
		"82 +14",
		"83 +14",
		"84 +14",
		"85 Trail_RoyalVelvet",
		"86 +14",
		"87 +14",
		"88 Victory_GoldShockwave",
		"89 +14",
		"90 Elim_MidasTouch",
		"91 +15",
		"92 +15",
		"93 +15",
		"94 +15",
		"95 Title_GoldStandard",
		"96 +15",
		"97 +15",
		"98 +15",
		"99 +15",
		"100 Hat_SunKing+Title_GoldenOne",
	})
end)

test("its totals: 100 rewards, 33 cosmetics on 32 levels, 733 coins on 67", function()
	local cosmetics, cosmeticLevels, coinLevels, coins = 0, 0, 0, 0
	for level = 2, 100 do
		local reward = lane[level]
		if #reward.Items > 0 then
			cosmeticLevels += 1
			cosmetics += #reward.Items
		else
			coinLevels += 1
			coins += reward.Coins
		end
	end
	expectEqual({ cosmetics, cosmeticLevels, coinLevels, coins }, { 33, 32, 67, 733 })
	expectEqual(GoldLane.RewardCount(lane, 100), 100)
	expectEqual(GoldLane.RewardCount(lane, 1), 0)
	expectEqual(GoldLane.RewardCount(lane, 12), 11)
	expectEqual({ GoldLane.CoinsBetween(lane, 1, 100) }, { 733, 67 })
	-- A coin level pays more the higher it is: 6 in the first ten, 15 in the last.
	expectEqual(GoldLane.Coins(3, Config.GoldRoad), 6)
	expectEqual(GoldLane.Coins(99, Config.GoldRoad), 15)
end)

test("the cosmetics: 31 new ones and the two VIP items, in every slot, showstoppers at 25, 50, 75, 100", function()
	expectEqual(#GoldPass.Items, 31, "about 25-35 new ones")
	local slots = {}
	for _, item in items do
		slots[item.Slot] = (slots[item.Slot] or 0) + 1
	end
	expectEqual(slots, { Trail = 7, Hat = 5, Title = 8, Victory = 5, Elimination = 4, Emote = 4 })
	expectEqual(levels.Trail_VIP, 6, "VIP Starlight is a gold reward now")
	expectEqual(levels.Title_VIP, 2, "VIP Partier is the first gold reward")
	expectEqual(lane[25].Items, { "Hat_RoyalCrown" })
	expectEqual(lane[50].Items, { "Trail_LiquidSunlight" })
	expectEqual(lane[75].Items, { "Victory_GoldenSupernova" })
	expectEqual(lane[100].Items, { "Hat_SunKing", "Title_GoldenOne" })
	-- The showstopper trail is the biggest: the widest, longest and brightest, with glitter and a glow.
	local sunlight = items.Trail_LiquidSunlight.Style
	for _, item in GoldPass.Items do
		if item.Slot == "Trail" and item.Id ~= "Trail_LiquidSunlight" then
			expectTrue(item.Style.Width < sunlight.Width, `{item.Id} is narrower than LIQUID SUNLIGHT`)
			expectTrue(item.Style.Lifetime <= sunlight.Lifetime, `{item.Id}'s tail is shorter`)
		end
	end
	expectTrue(sunlight.Glitter ~= nil and sunlight.Light ~= nil, "LIQUID SUNLIGHT glitters and glows")
end)

test("no gold cosmetic can be bought or earned another way, and no id is used twice", function()
	for _, item in GoldPass.Items do
		expectTrue(catalog[item.Id] == nil, `{item.Id} isn't also in Shared/Cosmetics`)
		for _, field in { "Price", "UnlockLevel", "UnlockStat", "Default", "Event", "Vip" } do
			expectEqual(item[field], nil, `{item.Id} has no {field}`)
		end
		expectTrue(item.GoldLevel >= 2 and item.GoldLevel <= 100, `{item.Id} is on the lane`)
		expectTrue(type(item.Name) == "string" and #item.Name <= 18, `{item.Id}'s name fits a tile`)
		expectTrue(#item.Description <= 40, `{item.Id}'s description fits a tile`)
	end
	for _, id in { "Trail_VIP", "Title_VIP" } do
		for _, field in { "Price =", "UnlockLevel =", "UnlockStat =", "Default =", "Event =", "Vip =" } do
			expectTrue(not string.find(catalog[id], field, 1, true), `{id} has no {field}`)
		end
	end
	expectTrue(not string.find(cosmeticsSource, "Vip = true", 1, true), "nothing is a VIP item any more")
end)

test("every look they need exists: effects, hats with uploaded meshes, built-in trail textures", function()
	for _, item in GoldPass.Items do
		if item.Effect then
			expectTrue(
				string.find(effectsSource, `EFFECTS.{item.Effect} = function`, 1, true) ~= nil,
				`{item.Id}'s effect {item.Effect} is in GoldEffects`
			)
		end
		if item.Slot == "Victory" or item.Slot == "Elimination" then
			expectTrue(item.Effect ~= nil, `{item.Id} has an effect`)
		end
		if item.Slot == "Emote" then
			expectTrue(item.Effect ~= nil or item.Animation ~= nil, `{item.Id} does something`)
		end
		if item.Slot == "Trail" then
			expectTrue(#item.Colors >= 2, `{item.Id} is a gradient`)
			expectTrue(string.sub(item.Style.Texture, 1, 12) == "rbxasset://t", `{item.Id}'s texture ships with Roblox`)
			expectTrue(item.Style.Emission > 0.4, `{item.Id} glows more than a shop trail`)
		end
		if item.Slot == "Hat" then
			local look = string.match(hatsSource, item.Id .. " = (%b{})")
			expectTrue(look ~= nil, `World/Hats has a look for {item.Id}`)
			local prop = string.match(look :: string, 'Prop = "(%w+)"') :: string
			local spec = string.match(propsSource, prop .. " = (%b{})")
			expectTrue(spec ~= nil, `World/Props/GoldHats defines {prop}`)
			local handle = string.match(look :: string, 'Handle = "(%w+)"') :: string
			expectTrue(string.find(spec :: string, `{handle} = `, 1, true) ~= nil, `{prop} colours its handle {handle}`)
			local assetId = tonumber(string.match(spec :: string, "AssetId = (%d+)"))
			expectTrue(assetId ~= nil and assetId > 0, `{prop}'s mesh is uploaded`)
		end
	end
end)

-- Emoji newer than Roblox's emoji font show as nothing on phones (tools/checks/ui_render.py's
-- NEW_EMOJI), and the game's fonts draw these as blanks (tests/Marks.spec.luau).
local BLANK = { "★", "✕", "✚", "☾", "◐", "✦", "☆", "☰" }
local function tooNew(text: string): boolean
	for _, code in utf8.codes(text) do
		if
			(code >= 0x1FA74 and code <= 0x1FAFF)
			or (code >= 0x1F6D6 and code <= 0x1F6DF)
			or code == 0x1F6FB
			or code == 0x1F6FC
			or code == 0x1F90C
			or code == 0x1F972
			or (code >= 0x1F977 and code <= 0x1F979)
			or (code >= 0x1F9A3 and code <= 0x1F9A4)
			or (code >= 0x1F9AB and code <= 0x1F9AD)
			or (code >= 0x1F9CB and code <= 0x1F9CC)
			or code == 0x1F7F0
		then
			return true
		end
	end
	return false
end

test("icons and words phones can draw", function()
	local texts = { GoldPass.Icon, GoldPass.Name, GoldPass.Listing.Name }
	for _, item in GoldPass.Items do
		table.insert(texts, item.Icon)
		table.insert(texts, item.Name)
		table.insert(texts, item.Description)
	end
	for _, perk in GoldPass.Perks do
		table.insert(texts, perk.Icon)
		table.insert(texts, perk.Text)
	end
	for _, text in texts do
		expectTrue(not tooNew(text), `"{text}" uses an emoji phones don't show`)
		for _, blank in BLANK do
			expectTrue(not string.find(text, blank, 1, true), `"{text}" uses {blank}, a blank in the game's fonts`)
		end
	end
end)

-- What buying at each level gives at once.
local function unlock(level: number, coinsTo: number?, owned: { [string]: boolean }?): GoldLane.Unlock
	return GoldLane.Retroactive(lane, level, coinsTo or 1, owned or {})
end

test("buying the pass gives every gold reward already reached, at once: the best first", function()
	expectEqual(unlock(1), { Count = 0, Coins = 0, CoinLevels = 0, Items = {} }, "level 1: nothing yet")
	expectEqual(unlock(12), {
		Count = 11,
		Coins = 6 + 6 + 6 + 6 + 7,
		CoinLevels = 5,
		Items = { "Title_HighRoller", "Hat_GoldParty", "Elim_GoldDust", "Trail_VIP", "Emote_MakeItRain", "Title_VIP" },
	})
	local atCrown = unlock(25)
	expectEqual(atCrown.Items[1], "Hat_RoyalCrown", "the crown leads the card at 25")
	-- Coins: levels 3, 5, 7 and 9 pay 6, 11 to 19 pay 7 (six of them), 21, 23 and 24 pay 8.
	expectEqual({ atCrown.Count, atCrown.Coins, #atCrown.Items }, { 24, 4 * 6 + 6 * 7 + 3 * 8, 11 })
	local all = unlock(100)
	expectEqual({ all.Count, all.Coins, all.CoinLevels, #all.Items }, { 100, 733, 67, 33 })
	expectEqual({ all.Items[1], all.Items[2] }, { "Hat_SunKing", "Title_GoldenOne" })
	-- The counts the card shows at each showstopper.
	local counts = {}
	for _, level in { 25, 50, 75, 100 } do
		table.insert(counts, unlock(level).Count)
	end
	expectEqual(counts, { 24, 49, 74, 100 })
end)

test("a level's coins are paid once, and cosmetics already owned aren't given again", function()
	-- Paid up to 30 already (an owner): only what's past it.
	local later = unlock(33, 30, {})
	expectEqual(later.Coins, 9 + 9, "levels 31 and 32")
	expectEqual(later.CoinLevels, 2)
	-- Owning some of them (they bought it before, or got the old VIP items): only the rest.
	local owned = unlock(12, 12, { Title_VIP = true, Trail_VIP = true, Hat_GoldParty = true })
	expectEqual(owned, {
		Count = 3,
		Coins = 0,
		CoinLevels = 0,
		Items = { "Title_HighRoller", "Elim_GoldDust", "Emote_MakeItRain" },
	})
	-- Level by level (each level-up pays from the last level paid): the same coins as all at once.
	local paid, coinsTo = 0, 1
	for level = 2, 100, 3 do
		paid += (GoldLane.CoinsBetween(lane, coinsTo, level))
		coinsTo = level
	end
	paid += (GoldLane.CoinsBetween(lane, coinsTo, 100))
	expectEqual(paid, 733)
	-- Going back (a stale level) pays nothing.
	expectEqual({ GoldLane.CoinsBetween(lane, 50, 40) }, { 0, 0 })
end)

test("owners get 10% more XP from a round, rounded up, at least 1", function()
	local road = Config.GoldRoad
	expectEqual(road.XPBoost, 0.1)
	expectEqual(GoldLane.XPBonus(25, road), 3)
	expectEqual(GoldLane.XPBonus(60, road), 6)
	expectEqual(GoldLane.XPBonus(110, road), 11)
	expectEqual(GoldLane.XPBonus(1, road), 1)
	expectEqual(GoldLane.XPBonus(0, road), 0)
	expectEqual(GoldLane.XPBonus(-5, road), 0)
	expectEqual(GoldLane.XPBonus(0 / 0, road), 0)
end)

test("the experience's creator always has the pass", function()
	expectTrue(GoldLane.IsCreator("User", 11690979745, 11690979745))
	expectEqual(GoldLane.IsCreator("User", 11690979745, 42), false)
	expectEqual(GoldLane.IsCreator("Group", 123, 123), false, "a group's experience: no one is its creator")
	expectEqual(GoldLane.IsCreator("User", 0, 0), false)
end)

test("the offer: Roblox's price and sale state, COMING SOON while off sale", function()
	local fallback = Config.Monetization.GoldPassPrice
	expectEqual(fallback, 399)
	expectEqual(Config.Monetization.GoldPassId, 2048378768)
	expectEqual(
		GoldLane.Offer(0, true, nil, fallback),
		{ OnSale = false, Price = 399, Known = true },
		"no pass: nothing to buy"
	)
	expectEqual(
		GoldLane.Offer(5, true, { IsForSale = false, PriceInRobux = 399 }, fallback),
		{ OnSale = false, Price = 399, Known = true },
		"off sale on Roblox: COMING SOON"
	)
	expectEqual(
		GoldLane.Offer(5, true, { IsForSale = true, PriceInRobux = 449 }, fallback),
		{ OnSale = true, Price = 449, Known = true },
		"Roblox's price wins"
	)
	expectEqual(
		GoldLane.Offer(5, false, "HTTP 500", fallback),
		{ OnSale = true, Price = 399, Known = false },
		"Roblox couldn't be asked: the usual price, and Roblox's prompt decides"
	)
	expectEqual(GoldLane.Offer(5, true, { IsForSale = true }, fallback).OnSale, false, "no price: not for sale")
	expectEqual(GoldLane.Offer(5, true, { IsForSale = true, PriceInRobux = 0 }, fallback).OnSale, false)
end)

test("the listing says what the pass is, and what it isn't", function()
	local text = GoldPass.Listing.Description
	expectTrue(#text <= 1000, "Roblox's limit for a pass's description")
	for _, words in { "every level from 2 to 100", "33 exclusive", "+10% XP", "already reached", "Never pay-to-win" } do
		expectTrue(string.find(text, words, 1, true) ~= nil, `it says "{words}"`)
	end
end)

return nil

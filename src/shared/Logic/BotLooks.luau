--!strict
-- How bots look and what they're called, so they pass for real players (owner: "Lets remove the bot
-- tag so people dont know they are playing with a bot.", then "Can we make the bots look more like
-- real players?"). They wore bare blocky bodies in two flat colours with the default face and pet
-- names (Pip, Mochi, Pebble): nobody's avatar looks like that. Now each one is dressed from the
-- catalog the way players dress: hair (or a hat over it), one of the dynamic heads most players wear
-- now (or Roblox's default one), a shirt and pants, sometimes glasses or a backpack, on the blocky body or
-- the Man, Woman or Robloxian 2.0 one, in a real skin tone; and named like players name
-- themselves ("Ava", "jake_2013", "PixelPanda", "xXLunaXx").
--
-- Every item is a catalog item a Roblox server loaded for a bot (tools/checks/bot_looks.py checks
-- them all again): Roblox's own and the catalog's most favourited, nothing with a brand, a show's or
-- a game's name on it. Services/BotService turns a look into a HumanoidDescription.
-- Leaf module: no requires, no Roblox APIs. `roll` returns a number in [0, 1).

local BotLooks = {}

export type Look = {
	Skin: { number }, -- RGB
	Head: number, -- a dynamic head, or 0 for Roblox's default one
	Body: { number }?, -- Torso, LeftArm, RightArm, LeftLeg, RightLeg (nil: the blocky body)
	Shirt: number,
	Pants: number,
	Hair: number?,
	Hat: number?,
	Glasses: number?,
	Back: number?,
}

BotLooks.Skins = {
	{ 255, 224, 189 },
	{ 255, 204, 170 },
	{ 234, 184, 146 },
	{ 204, 142, 105 },
	{ 175, 121, 88 },
	{ 124, 92, 70 },
	{ 86, 66, 54 },
	{ 245, 205, 48 }, -- the classic yellow (plenty of players keep it)
}

-- Dynamic heads (their face is part of the head). Classic faces aren't here: a bot is built with
-- Roblox's default dynamic head, which doesn't wear a classic face's picture (tools/checks/bot_looks.py
-- found none of them showed).
BotLooks.Heads = {
	10725626210, -- Woman Face
	10725826963, -- Man Face
	10687288296, -- Dylan Default
	10638267973, -- Stevie Standard
	10723855306, -- Devon Default
	15938951781, -- Silly Fun
	71993263971199, -- Silly Smile
	135958849558676, -- Lady Business v2
	109837069545709, -- Blush
	108490595091797, -- Super Super Happy Face Cheeks
	87203214673731, -- Yum Cute Angel Face - Cheeks
	84681044362051, -- Happy Relaxed Classic :3 Cat
}

-- Bodies: Torso, LeftArm, RightArm, LeftLeg, RightLeg.
BotLooks.Bodies = {
	Woman = { 86499666, 86499716, 86499698, 86499753, 86499793 },
	Man = { 86500008, 86500054, 86500036, 86500064, 86500078 },
	Robloxian = { 27112025, 27112052, 27112039, 27112056, 27112068 },
}

BotLooks.Hair = {
	63690008, -- Pal Hair
	451221329, -- True Blue Hair
	1103003368, -- Orange Beanie with Black Hair
	376526888, -- Straight Blonde Hair
	376524487, -- Blonde Spiked Hair
	376548738, -- Brown Charmer Hair
	376527350, -- Black Ponytail
	451220849, -- Lavender Updo
	2956239660, -- Belle Of Belfast Long Red Hair
	62234425, -- Brown Hair
	62724852, -- Chestnut Bun
	13745548, -- Cinnamon Hair
	398673196, -- Blonde Action Ponytail
	7259123616, -- Black Messy Hairstyle
	6501746646, -- Popular Girl Blonde & Brown Hair
	5890690147, -- Popstar Hair
	6413290259, -- Blonde Flowy Pigtails
	5945436918, -- Light Brown Ethereal Hairstyle
	5644883846, -- Cool Boy Hair
	5891039736, -- Black Anime Hair
	11597599236, -- Lush Wavy Hair (Blonde)
	10482964428, -- Y2K Layered Wolfcut (Blonde)
	5314006793, -- Black Trendy Messy Buns
	4527498648, -- Clean Shiny Spikes
	6413288640, -- Black Flowy Pigtails
	7284206648, -- Aesthetic Split Bangs Hair in Blonde
	6100039044, -- Bow Braids & Wispy Bangs
}

BotLooks.Hats = {
	607702162, -- Roblox Baseball Cap
	417457461, -- ROBLOX 'R' Baseball Cap
	2646473721, -- Roblox Visor
	4904891637, -- Black Trendy Hat
	4904907858, -- White Trendy Hat
	5945411921, -- Cute White Winter Beanie
	6133262085, -- Black Fuzzy Headband
	6201860992, -- White Flowy Bow
	1374269, -- Kitty Ears
}

BotLooks.Glasses = {
	376526673, -- Stylish Aviators
	376527500, -- Orange Shades
	4936055418, -- Retro Sunglasses
	4143016822, -- Vintage Glasses
	11884330, -- Nerd Glasses
	4197739997, -- Reading Glasses
}

BotLooks.Backs = {
	5315452348, -- White Bunny Backpack
	5315424251, -- Black Bunny Backpack
	4487802862, -- Black Drawstring Bag
	4436710326, -- Duffel Bag
	4367422773, -- White Luxury Backpack
}

BotLooks.Shirts = {
	144076358, -- Blue and Black Motorcycle Shirt
	607785314, -- ROBLOX Jacket
	398633584, -- Denim Jacket with White Hoodie
	144076436, -- Grey Striped Shirt with Denim Jacket
	398634295, -- Pastel Starburst Top with Gray Jacket
	382538059, -- Green Jersey
	398635081, -- Blue Plaid Shirt
	382537702, -- Teal Shirt
	382538295, -- Guitar Tee with Black Jacket
	382537085, -- I <3 Pizza Shirt
	4047884939, -- My Favorite Pizza Shirt
	3670737444, -- Roblox Shirt - Simple Pattern
	6876555875, -- soft gray vintage top
	5134719820, -- black flannel
	6862266654, -- tan plaid sweater
	6959669630, -- beige vintage top
	6905879940, -- sage green sweater
	6554200369, -- Grey Suit w/ Black Vest
}

BotLooks.Pants = {
	144076760, -- Dark Green Jeans
	398634487, -- Beautiful You Jeans
	398633812, -- Black Jeans with White Shoes
	398635338, -- Ripped Skater Pants
	382537806, -- Jean Shorts
	129459077, -- Black Slacks
	382538503, -- Black Jeans with Sneakers
	382537569, -- Black Jeans
	129458426, -- Jeans
	382537950, -- Jean Shorts with White Shoes
	5197702014, -- ripped jeans
	97118097068276, -- dark pants
	15491580408, -- grey star jeans
	9154749510, -- beige khakis
}

-- How often each piece shows up.
BotLooks.DEFAULT_HEAD = 0.15 -- Roblox's default head (plenty of players keep it)
BotLooks.HAIR = 0.95
BotLooks.HAT = 0.22
BotLooks.GLASSES = 0.2
BotLooks.BACK = 0.18
BotLooks.CLASSIC_SKIN = 0.1
BotLooks.BODIES = { Woman = 0.2, Man = 0.15, Robloxian = 0.1 } -- the rest: the blocky body

local function pick<T>(list: { T }, roll: () -> number): T
	return list[math.min(#list, math.floor(roll() * #list) + 1)]
end

local function maybe<T>(chance: number, list: { T }, roll: () -> number): T?
	if roll() < chance then
		return pick(list, roll)
	end
	return nil
end

-- A whole look.
function BotLooks.Outfit(roll: () -> number): Look
	local skins = BotLooks.Skins
	local skin = if roll() < BotLooks.CLASSIC_SKIN
		then skins[#skins]
		else skins[math.min(#skins - 1, math.floor(roll() * (#skins - 1)) + 1)]
	local body = nil
	local bodyRoll = roll()
	for _, name in { "Woman", "Man", "Robloxian" } do
		local chance = BotLooks.BODIES[name]
		if bodyRoll < chance then
			body = BotLooks.Bodies[name]
			break
		end
		bodyRoll -= chance
	end
	local default = roll() < BotLooks.DEFAULT_HEAD
	return {
		Skin = skin,
		Head = if default then 0 else pick(BotLooks.Heads, roll),
		Body = body,
		Shirt = pick(BotLooks.Shirts, roll),
		Pants = pick(BotLooks.Pants, roll),
		Hair = maybe(BotLooks.HAIR, BotLooks.Hair, roll),
		Hat = maybe(BotLooks.HAT, BotLooks.Hats, roll),
		Glasses = maybe(BotLooks.GLASSES, BotLooks.Glasses, roll),
		Back = maybe(BotLooks.BACK, BotLooks.Backs, roll),
	}
end

-- Names ------------------------------------------------------------------------------------------

BotLooks.FirstNames = {
	"Ava",
	"Mia",
	"Liam",
	"Noah",
	"Emma",
	"Olivia",
	"Ethan",
	"Lucas",
	"Zoe",
	"Lily",
	"Jayden",
	"Aiden",
	"Chloe",
	"Ella",
	"Mason",
	"Logan",
	"Harper",
	"Sophie",
	"Leo",
	"Caleb",
	"Maya",
	"Nora",
	"Ruby",
	"Kai",
	"Ezra",
	"Jade",
	"Owen",
	"Isla",
	"Miles",
	"Luna",
	"Max",
	"Riley",
	"Ellie",
	"Jake",
	"Amelia",
	"Grace",
	"Dylan",
	"Josh",
	"Bella",
	"Ryan",
}
BotLooks.Words = {
	"Shadow",
	"Pixel",
	"Cookie",
	"Frosty",
	"Blaze",
	"Lucky",
	"Sunny",
	"Cosmic",
	"Turbo",
	"Sparkle",
	"Cyber",
	"Mystic",
	"Happy",
	"Crazy",
	"Super",
	"Golden",
	"Epic",
	"Bubbly",
	"Sleepy",
	"Swift",
	"Tiny",
	"Fuzzy",
	"Neon",
	"Rainbow",
	"Mega",
	"Icy",
	"Starry",
	"Wild",
	"Silly",
	"Cool",
}
BotLooks.Things = {
	"Fox",
	"Panda",
	"Wolf",
	"Gamer",
	"Cat",
	"Bunny",
	"Dragon",
	"Ninja",
	"Tiger",
	"Bear",
	"Kitty",
	"Star",
	"Storm",
	"Ghost",
	"Knight",
	"Bean",
	"Duck",
	"Frog",
	"Penguin",
	"Rider",
	"Boba",
	"Unicorn",
	"Shark",
	"Owl",
	"Puppy",
	"Taco",
	"Waffle",
	"Comet",
	"Noodle",
	"Pickle",
}

BotLooks.MAX_NAME = 20 -- a Roblox display name's longest

local function digits(roll: () -> number): string
	local kind = roll()
	if kind < 0.35 then
		return tostring(2008 + math.floor(roll() * 10)) -- a birth year
	elseif kind < 0.7 then
		return string.format("%02d", math.floor(roll() * 100))
	end
	return tostring(math.floor(roll() * 900) + 100)
end

-- One name, the way players name themselves.
function BotLooks.Name(roll: () -> number): string
	local first = pick(BotLooks.FirstNames, roll)
	local word = pick(BotLooks.Words, roll)
	local thing = pick(BotLooks.Things, roll)
	local pattern = roll()
	local name
	if pattern < 0.2 then
		name = first -- Ava
	elseif pattern < 0.35 then
		name = string.lower(first) .. (if roll() < 0.5 then "_" else "") .. digits(roll) -- jake_2013
	elseif pattern < 0.55 then
		name = word .. thing -- PixelPanda
	elseif pattern < 0.68 then
		name = word .. thing .. digits(roll) -- ShadowWolf77
	elseif pattern < 0.74 then
		name = `xX{first}Xx` -- xXLunaXx
	elseif pattern < 0.82 then
		name = (if roll() < 0.5 then "its" else "Im") .. first -- itsMaya
	elseif pattern < 0.92 then
		name = first .. "_" .. thing -- Lily_Bunny
	else
		name = string.lower(word) .. "_" .. string.lower(thing) -- sleepy_panda
	end
	return string.sub(name, 1, BotLooks.MAX_NAME)
end

-- A name nobody in `taken` has (tries a few, then adds a number).
function BotLooks.FreshName(roll: () -> number, taken: { [string]: boolean }): string
	for _ = 1, 12 do
		local name = BotLooks.Name(roll)
		if not taken[name] then
			return name
		end
	end
	local base = string.sub(BotLooks.Name(roll), 1, BotLooks.MAX_NAME - 4) -- (room for a year)
	local name = base .. digits(roll)
	while taken[name] do
		name = base .. tostring(math.floor(roll() * 900) + 100)
	end
	return string.sub(name, 1, BotLooks.MAX_NAME)
end

return BotLooks

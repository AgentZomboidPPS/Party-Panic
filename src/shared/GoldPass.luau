-- The GOLD PASS (owner: "Also we do need a paid battle pass too. I like the current free one. But
-- the paid one should also be insane."): one permanent Roblox game pass that opens a gold lane on
-- the Rewards Road, next to the free one. Every level from 2 to 100 has a gold reward: 33 exclusive
-- cosmetics nobody else can have (these 31 and the two old VIP items, VIP Partier and VIP
-- Starlight, which the pass took over), with the showstoppers at 25 (the ROYAL CROWN), 50 (LIQUID
-- SUNLIGHT), 75 (the GOLDEN SUPERNOVA) and 100 (the SUN KING CROWN and THE GOLDEN ONE), and gold
-- coins at every other level (Logic/GoldLane, Config.GoldRoad). Buying it gives every gold reward
-- already reached, at once. Owners also get the perks at the top of the screen: a GOLD badge and a
-- shimmering gold name on their name tag, a gold level badge, and 10% more XP from rounds. Nothing
-- in it changes how a mini-game plays.
--
-- This module is the catalogue: Shared/Cosmetics appends Items to its list (an item's GoldLevel is
-- its place on the lane), and the screens take the pass's colours, perks and words from here.
-- Looks: trails can carry a Style (a texture, a glow, a width, a longer tail, glitter shed behind
-- and a light: Services/CosmeticService); every gold title shimmers in its colours on the name tag;
-- the victory, knockout and emote effects are the client's GoldEffects; the hats are World/Hats
-- looks with their own meshes (World/Props/GoldHats, tools/meshgen/props/GoldHats.py).
-- Leaf module: no requires.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Textures every device has (they ship with Roblox: nothing to upload or wait for).
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local GOLD = rgb(255, 196, 40)
local GOLD_LIGHT = rgb(255, 240, 170)
local GOLD_DEEP = rgb(214, 132, 18)

local GoldPass = {}

GoldPass.Name = "GOLD PASS"
GoldPass.Icon = "👑"

-- The pass's colours: the gold UI (Light at the top of a gradient, Deep at the bottom), its dark
-- ink (text strokes on gold), the shine, and a reward still locked (LockedTop to LockedBottom: a
-- softer gold that still looks worth having).
GoldPass.Colors = {
	Light = GOLD_LIGHT,
	Gold = GOLD,
	Deep = GOLD_DEEP,
	Ink = rgb(110, 58, 6),
	Shine = rgb(255, 252, 230),
	LockedTop = rgb(250, 224, 156),
	LockedBottom = rgb(196, 140, 56),
}

-- The shimmer on an owner's name tag and the gold titles: gold with a white glint that a client
-- slides across it (Controllers/GoldPassController).
GoldPass.Shimmer = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(255, 205, 60)),
	ColorSequenceKeypoint.new(0.4, rgb(255, 214, 90)),
	ColorSequenceKeypoint.new(0.5, rgb(255, 255, 240)),
	ColorSequenceKeypoint.new(0.6, rgb(255, 214, 90)),
	ColorSequenceKeypoint.new(1, rgb(240, 160, 30)),
})

-- What owning it does besides the lane (the Rewards screen and the unlock card list these).
-- (`Short`: the words for a line of them all.)
GoldPass.Perks = {
	{ Icon = "👑", Text = "GOLD badge on your name tag", Short = "GOLD name tag badge" },
	{ Icon = "✨", Text = "Shimmering gold name", Short = "Shimmering name" },
	{ Icon = "🏅", Text = "Gold level badge", Short = "Gold level badge" },
	{ Icon = "⚡", Text = "+10% XP from every round", Short = "+10% XP" },
}

-- The game pass's listing on Roblox (pass 2048378768, Config.Monetization; the owner sets the price
-- and puts it on sale there). Its words must stay true: cosmetics, coins and +10% XP, nothing that
-- changes how a mini-game plays.
GoldPass.Listing = {
	Name = "GOLD PASS",
	Description = "Unlock the GOLD lane of the Level Road: 100 gold rewards across every level from 2 to 100! "
		.. "33 exclusive cosmetics you can't get any other way (the Royal Crown, the Sun King Crown, Liquid "
		.. "Sunlight, the Golden Supernova and more: trails, hats, titles, victory and knockout effects, "
		.. "emotes), gold coins, a shimmering gold name tag with a GOLD badge, a gold level badge and +10% XP "
		.. "from every round. Every gold reward for levels you've already reached unlocks instantly. Never "
		.. "pay-to-win: it doesn't change how any mini-game plays.",
}

GoldPass.Items = {
	-- Trails ------------------------------------------------------------------------------------
	{
		Id = "Trail_GoldLeaf",
		Slot = "Trail",
		Name = "Gold Leaf",
		Description = "Gold flakes flutter where you run.",
		Icon = "🍂",
		GoldLevel = 17,
		Colors = { GOLD_LIGHT, GOLD, GOLD_DEEP },
		Style = { Texture = SPARKLE, TextureLength = 2.5, Emission = 0.8, Width = 1.15, Lifetime = 0.6 },
	},
	{
		Id = "Trail_MoltenGold",
		Slot = "Trail",
		Name = "Molten Gold",
		Description = "A river of glowing liquid gold.",
		Icon = "🌋",
		GoldLevel = 30,
		Colors = { rgb(255, 250, 200), rgb(255, 170, 30), rgb(230, 90, 10) },
		Style = {
			Texture = FIRE,
			TextureLength = 3,
			Emission = 1,
			Width = 1.25,
			Lifetime = 0.7,
			Glitter = rgb(255, 180, 60),
		},
	},
	{
		Id = "Trail_RoseGold",
		Slot = "Trail",
		Name = "Rose Gold",
		Description = "Pink gold with a soft glow.",
		Icon = "🌹",
		GoldLevel = 45,
		Colors = { rgb(255, 228, 218), rgb(246, 164, 152), rgb(212, 118, 108) },
		Style = {
			Texture = SPARKLE,
			TextureLength = 2.5,
			Emission = 0.7,
			Width = 1.15,
			Lifetime = 0.65,
			Glitter = rgb(255, 205, 200),
		},
	},
	{
		-- The level 50 showstopper: twice the width, a long blazing tail, gold glitter and a glow.
		Id = "Trail_LiquidSunlight",
		Slot = "Trail",
		Name = "Liquid Sunlight",
		Description = "A blazing river of light.",
		Icon = "🌅",
		GoldLevel = 50,
		Colors = { rgb(255, 255, 235), rgb(255, 226, 90), rgb(255, 170, 20), rgb(255, 110, 40) },
		Style = {
			Texture = SPARKLE,
			TextureLength = 1.6,
			Emission = 1,
			Width = 1.8,
			Lifetime = 1,
			Glitter = rgb(255, 214, 90),
			Light = rgb(255, 200, 90),
		},
	},
	{
		Id = "Trail_PlatinumComet",
		Slot = "Trail",
		Name = "Platinum Comet",
		Description = "Silver-white with gold sparks.",
		Icon = "☄️",
		GoldLevel = 70,
		Colors = { rgb(255, 255, 255), rgb(214, 224, 240), rgb(255, 214, 90) },
		Style = {
			Texture = SPARKLE,
			TextureLength = 2,
			Emission = 1,
			Width = 1.3,
			Lifetime = 0.95,
			Glitter = rgb(255, 250, 230),
		},
	},
	{
		Id = "Trail_RoyalVelvet",
		Slot = "Trail",
		Name = "Royal Velvet",
		Description = "Deep purple trimmed in gold.",
		Icon = "💜",
		GoldLevel = 85,
		Colors = { GOLD, rgb(150, 70, 220), rgb(80, 30, 150), GOLD },
		Style = {
			Texture = SPARKLE,
			TextureLength = 3,
			Emission = 0.6,
			Width = 1.35,
			Lifetime = 0.8,
			Glitter = rgb(255, 214, 90),
		},
	},

	-- Hats (World/Hats) -------------------------------------------------------------------------
	{
		Id = "Hat_GoldParty",
		Slot = "Hat",
		Name = "Gold Party Hat",
		Description = "Gold cone, pink swirls, pompom!",
		Icon = "🎉",
		GoldLevel = 10,
		Colors = { GOLD, rgb(255, 92, 170) },
	},
	{
		-- The level 25 showstopper.
		Id = "Hat_RoyalCrown",
		Slot = "Hat",
		Name = "Royal Crown",
		Description = "Jewels, pearls and red velvet.",
		Icon = "👑",
		GoldLevel = 25,
		Colors = { GOLD, rgb(190, 24, 52) },
	},
	{
		Id = "Hat_GoldenHalo",
		Slot = "Hat",
		Name = "Golden Halo",
		Description = "A glowing ring of pure gold.",
		Icon = "😇",
		GoldLevel = 40,
		Colors = { GOLD_LIGHT, GOLD },
	},
	{
		Id = "Hat_GildedTopHat",
		Slot = "Hat",
		Name = "Gilded Top Hat",
		Description = "Black silk with a gold band.",
		Icon = "🎩",
		GoldLevel = 60,
		Colors = { rgb(40, 34, 48), GOLD },
	},
	{
		-- Level 100, the last showstopper (with THE GOLDEN ONE).
		Id = "Hat_SunKing",
		Slot = "Hat",
		Name = "Sun King Crown",
		Description = "Twelve rays of blazing gold.",
		Icon = "☀️",
		GoldLevel = 100,
		Colors = { rgb(255, 246, 190), GOLD, GOLD_DEEP },
	},

	-- Titles (each shimmers in its colours on the name tag) ----------------------------------------
	{
		Id = "Title_HighRoller",
		Slot = "Title",
		Name = "High Roller",
		Description = "Big wins, bigger style.",
		Icon = "🎲",
		GoldLevel = 12,
		Colors = { rgb(255, 236, 140), rgb(255, 170, 30) },
	},
	{
		Id = "Title_Jackpot",
		Slot = "Title",
		Name = "Jackpot",
		Description = "You hit the jackpot.",
		Icon = "🎰",
		GoldLevel = 22,
		Colors = { rgb(255, 240, 120), rgb(255, 120, 60) },
	},
	{
		Id = "Title_CrownJewel",
		Slot = "Title",
		Name = "Crown Jewel",
		Description = "The gem of every party.",
		Icon = "💍",
		GoldLevel = 35,
		Colors = { rgb(255, 225, 120), rgb(120, 220, 255) },
	},
	{
		Id = "Title_GildedLegend",
		Slot = "Title",
		Name = "Gilded Legend",
		Description = "Your story is written in gold.",
		Icon = "🏛️",
		GoldLevel = 58,
		Colors = { rgb(255, 240, 180), rgb(230, 150, 30) },
	},
	{
		Id = "Title_SolidGold",
		Slot = "Title",
		Name = "Solid Gold",
		Description = "24 karats, all the way through.",
		Icon = "🥇",
		GoldLevel = 80,
		Colors = { rgb(255, 230, 110), rgb(255, 190, 40), rgb(214, 132, 18) },
	},
	{
		Id = "Title_GoldStandard",
		Slot = "Title",
		Name = "Gold Standard",
		Description = "Everyone's measured against you.",
		Icon = "🏆",
		GoldLevel = 95,
		Colors = { rgb(255, 250, 220), rgb(255, 200, 60) },
	},
	{
		-- Level 100, the last showstopper (with the SUN KING CROWN): the whole rainbow in gold.
		Id = "Title_GoldenOne",
		Slot = "Title",
		Name = "The Golden One",
		Description = "Level 100. Pure gold.",
		Icon = "⚜️",
		GoldLevel = 100,
		Colors = { rgb(255, 250, 220), rgb(255, 205, 60), rgb(255, 150, 200), rgb(255, 205, 60) },
	},

	-- Victory effects (the client's GoldEffects) ---------------------------------------------------
	{
		Id = "Victory_GoldRush",
		Slot = "Victory",
		Name = "Gold Rush",
		Description = "Gold coins rain on the winner.",
		Icon = "🤑",
		GoldLevel = 14,
		Effect = "GoldRush",
	},
	{
		Id = "Victory_GoldenBeam",
		Slot = "Victory",
		Name = "Golden Beam",
		Description = "A beam of gold light from the sky.",
		Icon = "🔆",
		GoldLevel = 33,
		Effect = "GoldenBeam",
	},
	{
		Id = "Victory_Champagne",
		Slot = "Victory",
		Name = "Champagne Shower",
		Description = "Pop the bubbly: you won!",
		Icon = "🍾",
		GoldLevel = 48,
		Effect = "Champagne",
	},
	{
		-- The level 75 showstopper: a flash, a gold sphere bursting, rings, fireworks and coins.
		Id = "Victory_GoldenSupernova",
		Slot = "Victory",
		Name = "Golden Supernova",
		Description = "Explode in a burst of pure gold.",
		Icon = "🌟",
		GoldLevel = 75,
		Effect = "Supernova",
	},
	{
		Id = "Victory_GoldShockwave",
		Slot = "Victory",
		Name = "Gold Shockwave",
		Description = "Rings of gold race out.",
		Icon = "💫",
		GoldLevel = 88,
		Effect = "GoldShockwave",
	},

	-- Knockout effects ------------------------------------------------------------------------------
	{
		Id = "Elim_GoldDust",
		Slot = "Elimination",
		Name = "Gold Dust",
		Description = "Vanish in a puff of gold glitter.",
		Icon = "✨",
		GoldLevel = 8,
		Effect = "GoldDust",
	},
	{
		Id = "Elim_TreasurePop",
		Slot = "Elimination",
		Name = "Treasure Pop",
		Description = "Burst into a shower of coins.",
		Icon = "🎁",
		GoldLevel = 28,
		Effect = "TreasurePop",
	},
	{
		Id = "Elim_DiamondShatter",
		Slot = "Elimination",
		Name = "Diamond Shatter",
		Description = "Shatter into shining diamonds.",
		Icon = "💎",
		GoldLevel = 55,
		Effect = "DiamondShatter",
	},
	{
		Id = "Elim_MidasTouch",
		Slot = "Elimination",
		Name = "Midas Touch",
		Description = "Turn to a gold statue... and crumble.",
		Icon = "🗿",
		GoldLevel = 90,
		Effect = "MidasTouch",
	},

	-- Emotes: a default dance or cheer with a gold effect, or an effect of its own ----------------------
	{
		Id = "Emote_MakeItRain",
		Slot = "Emote",
		Name = "Make It Rain",
		Description = "Throw cash in the air!",
		Icon = "💸",
		GoldLevel = 4,
		Animation = 507770677, -- the Cheer
		Effect = "MakeItRain",
	},
	{
		Id = "Emote_HeartOfGold",
		Slot = "Emote",
		Name = "Heart of Gold",
		Description = "Golden hearts for everyone.",
		Icon = "💛",
		GoldLevel = 20,
		Effect = "HeartOfGold",
	},
	{
		Id = "Emote_DiamondDrop",
		Slot = "Emote",
		Name = "Diamond Drop",
		Description = "Diamonds rain from above.",
		Icon = "💠",
		GoldLevel = 38,
		Effect = "DiamondDrop",
	},
	{
		Id = "Emote_GoldenAura",
		Slot = "Emote",
		Name = "Golden Aura",
		Description = "Dance in a ring of golden light.",
		Icon = "🌞",
		GoldLevel = 65,
		Animation = 507777268, -- the Disco dance
		Looped = true,
		Effect = "GoldenAura",
	},
}

return GoldPass

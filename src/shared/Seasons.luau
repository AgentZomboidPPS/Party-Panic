--!strict
-- The crate seasons (owner: "looking to implement seasonal crates ... seasonal crates are awarded at
-- end of match ... Keys to open the crate are available to be awarded upon winning", then "Hollow
-- night comes first I want you to actually work on adding it to the game right now. The season should
-- always run (so when winter hits the winter event can take place) 2 is good 3 is good, and 4 doesn't
-- need to be spooky. We will have separate events run along it when the time is right. Also do all of
-- your ideas. This has to be sick. This will be players first season. I want it to look insane.").
--
-- A season always runs: there's no end date, `Current` names the one players are in, and limited-time
-- events (Shared/Events) run alongside it. Changing `Current` to a new season turns everyone's
-- unopened crates into the new season's (one for one), keeps their keys, and vaults the old season's
-- items (nobody can get them any more; the collection log keeps them).
--
-- Season 1 is HOLLOW NIGHT: autumn at harvest-moon dusk, cozy rather than spooky. Its 23 crate
-- items (the title, 5 pets, 5 hats, 12 effects) are listed here and become ordinary cosmetics in
-- Shared/Cosmetics (Season = "HollowNight", never sold for coins); the Harvest Banner trail is the
-- one thing the Robux starter pack sells outright. The crate rules are Logic/CrateLogic, the server
-- Services/CrateService, the lobby World/SeasonWorld, the screens Controllers/CrateController.
-- Colours are {r, g, b} (0-255) so the Lune tests can load this file.
-- Leaf module: no requires, no Roblox APIs.

local Seasons = {}

export type RGB = { number }

export type PetInfo = {
	Prop: string, -- World/Props/HollowNight's mesh
	Light: RGB, -- its glow (light pool, sparkles)
	Flourish: string, -- its idle trick (Controllers/PetController)
	Hat: string?, -- the hat that matches it (an extra flourish when worn together)
}

export type Season = {
	Id: string,
	Number: number,
	Name: string, -- "HOLLOW NIGHT"
	Crate: string, -- what one crate is called
	Key: string,
	Meter: string,
	Title: string,
	Pets: { string },
	Hats: { string },
	Effects: { string },
	Starter: string, -- the starter pack's own item
	PetInfo: { [string]: PetInfo },
	Colors: { [string]: RGB },
	Props: { [string]: string },
}

export type Item = {
	Id: string,
	Slot: string,
	Name: string,
	Description: string,
	Icon: string,
	Effect: string?,
	Colors: { RGB }?,
	Tier: string, -- "Title" | "Pet" | "Hat" | "Effect" | "Starter"
	-- A trail's extra looks (Shared/Cosmetics turns it into the item's Style): Texture "Fire" or
	-- "Sparkle", TextureLength, Emission, Width, Lifetime, Glitter and Light {r, g, b}, and Particles
	-- "Leaves" (leaves flutter off behind) or "Wisp" (spirit flames in the footprints).
	Trail: { [string]: any }?,
}

Seasons.Current = "HollowNight"

local HOLLOW_NIGHT: Season = {
	Id = "HollowNight",
	Number = 1,
	Name = "HOLLOW NIGHT",
	Crate = "Hollow Crate",
	Key = "Lantern Key",
	Meter = "Lantern Meter",
	Title = "Title_Harvester",
	Pets = { "Pet_HarvestOwl", "Pet_EmberStag", "Pet_Gourdian", "Pet_ToadstoolTot", "Pet_LanternWisp" },
	Hats = { "Hat_LeafCrown", "Hat_Scarecrow", "Hat_AntlerCirclet", "Hat_AcornHelm", "Hat_CrescentMoon" },
	Effects = {
		"Aura_LeafWhirl",
		"Aura_Fireflies",
		"Aura_LanternRing",
		"Trail_Embers",
		"Trail_FallingLeaves",
		"Trail_WispSteps",
		"Elim_CrowScatter",
		"Elim_LeafPile",
		"Elim_LanternSnuff",
		"Victory_Bonfire",
		"Victory_HarvestRain",
		"Victory_Moonrise",
	},
	Starter = "Trail_HarvestBanner",
	PetInfo = {
		Pet_HarvestOwl = { Prop = "HarvestOwl", Light = { 255, 181, 48 }, Flourish = "Owl", Hat = "Hat_Scarecrow" },
		Pet_EmberStag = { Prop = "EmberStag", Light = { 255, 150, 60 }, Flourish = "Stag", Hat = "Hat_AntlerCirclet" },
		Pet_Gourdian = { Prop = "Gourdian", Light = { 255, 138, 42 }, Flourish = "Gourdian", Hat = "Hat_LeafCrown" },
		Pet_ToadstoolTot = { Prop = "ToadstoolTot", Light = { 255, 226, 150 }, Flourish = "Tot", Hat = "Hat_AcornHelm" },
		Pet_LanternWisp = {
			Prop = "LanternWisp",
			Light = { 125, 255, 178 },
			Flourish = "Wisp",
			Hat = "Hat_CrescentMoon",
		},
	},
	Colors = {
		Main = { 255, 138, 42 }, -- ember orange
		Glow = { 255, 181, 48 }, -- lantern amber
		Gold = { 255, 208, 74 },
		Crimson = { 200, 50, 42 },
		Deep = { 28, 15, 46 }, -- dusk plum
		Panel = { 54, 26, 52 },
		Wisp = { 125, 255, 178 },
		Text = { 255, 243, 228 },
		Title = { 255, 106, 31 },
	},
	Props = {
		Crate = "HollowCrate",
		Key = "LanternKey",
		Pile = "HollowPile",
		Altar = "HollowAltar",
		Board = "HollowBoard",
	},
}

Seasons.ById = { HollowNight = HOLLOW_NIGHT } :: { [string]: Season }

-- Every season's crate items (and the starter pack's trail), as cosmetics.
Seasons.Items = {
	-- The title, 1 in 500 (owner: "look very awesome, cool font, styled effect around the season, very
	-- visible \"woah\""): its nameplate burns like a candle (Controllers/TitleController).
	{
		Id = "Title_Harvester",
		Slot = "Title",
		Name = "The Harvester",
		Description = "1 in 500. A title that burns like a candle.",
		Icon = "🌾",
		Tier = "Title",
		Colors = { { 255, 241, 194 }, { 255, 181, 48 }, { 255, 106, 31 }, { 184, 38, 26 } },
	},
	-- Pets (a new slot): they float behind you in the lobby and in every mini-game.
	{
		Id = "Pet_HarvestOwl",
		Slot = "Pet",
		Name = "Harvest Owl",
		Description = "Leaf-feather wings and a tiny lantern.",
		Icon = "🦉",
		Tier = "Pet",
		Colors = { { 160, 98, 44 }, { 255, 181, 48 } },
	},
	{
		Id = "Pet_EmberStag",
		Slot = "Pet",
		Name = "Ember Stag",
		Description = "Glowing antlers, fireflies all around.",
		Icon = "🦌",
		Tier = "Pet",
		Colors = { { 184, 112, 60 }, { 255, 181, 48 } },
	},
	{
		Id = "Pet_Gourdian",
		Slot = "Pet",
		Name = "Gourdian",
		Description = "A pumpkin-headed golem of gourds.",
		Icon = "🎃",
		Tier = "Pet",
		Colors = { { 255, 122, 26 }, { 79, 107, 36 } },
	},
	{
		Id = "Pet_ToadstoolTot",
		Slot = "Pet",
		Name = "Toadstool Tot",
		Description = "A little mushroom surfing a maple leaf.",
		Icon = "🍄",
		Tier = "Pet",
		Colors = { { 224, 72, 46 }, { 255, 233, 176 } },
	},
	{
		Id = "Pet_LanternWisp",
		Slot = "Pet",
		Name = "Lantern Wisp",
		Description = "A cheerful spirit flame in a lantern.",
		Icon = "🏮",
		Tier = "Pet",
		Colors = { { 125, 255, 178 }, { 47, 43, 58 } },
	},
	-- Hats (no pumpkin: the Pumpkin Hat is the HALLOWEEN PARTY's).
	{
		Id = "Hat_LeafCrown",
		Slot = "Hat",
		Name = "Leaf Crown",
		Description = "A wreath of red and gold leaves.",
		Icon = "🍁",
		Tier = "Hat",
		Colors = { { 200, 50, 42 }, { 255, 208, 74 } },
	},
	{
		Id = "Hat_Scarecrow",
		Slot = "Hat",
		Name = "Scarecrow Hat",
		Description = "Straw, a patch, and a crow on the brim.",
		Icon = "👒",
		Tier = "Hat",
		Colors = { { 217, 178, 90 }, { 26, 22, 34 } },
	},
	{
		Id = "Hat_AntlerCirclet",
		Slot = "Hat",
		Name = "Antler Circlet",
		Description = "Glowing antlers with leaves and fireflies.",
		Icon = "🦌",
		Tier = "Hat",
		Colors = { { 90, 52, 32 }, { 255, 181, 48 } },
	},
	{
		Id = "Hat_AcornHelm",
		Slot = "Hat",
		Name = "Acorn Helm",
		Description = "A big acorn cap, worn proudly.",
		Icon = "🌰",
		Tier = "Hat",
		Colors = { { 106, 68, 38 }, { 255, 138, 42 } },
	},
	{
		Id = "Hat_CrescentMoon",
		Slot = "Hat",
		Name = "Crescent Moon",
		Description = "A glowing moon with stars and bats.",
		Icon = "🌙",
		Tier = "Hat",
		Colors = { { 255, 207, 122 }, { 26, 22, 34 } },
	},
	-- Effects: 3 auras (a new slot: an effect always on around you in the lobby), 3 trails, 3
	-- knockouts, 3 victories. Drawn by Controllers/EffectsController (auras: Controllers/AuraController).
	{
		Id = "Aura_LeafWhirl",
		Slot = "Aura",
		Name = "Leaf Whirl",
		Description = "Autumn leaves spiral around you.",
		Icon = "🍂",
		Tier = "Effect",
		Effect = "LeafWhirl",
		Colors = { { 200, 50, 42 }, { 255, 138, 42 }, { 255, 208, 74 } },
	},
	{
		Id = "Aura_Fireflies",
		Slot = "Aura",
		Name = "Firefly Swarm",
		Description = "Fireflies drift around you and blink.",
		Icon = "✨",
		Tier = "Effect",
		Effect = "Fireflies",
		Colors = { { 255, 226, 122 }, { 190, 255, 120 } },
	},
	{
		Id = "Aura_LanternRing",
		Slot = "Aura",
		Name = "Lantern Ring",
		Description = "Three paper lanterns float around you.",
		Icon = "🏮",
		Tier = "Effect",
		Effect = "LanternRing",
		Colors = { { 255, 138, 42 }, { 255, 181, 48 } },
	},
	{
		Id = "Trail_Embers",
		Slot = "Trail",
		Name = "Ember Trail",
		Description = "An orange ribbon with drifting sparks.",
		Icon = "🔥",
		Tier = "Effect",
		Effect = "Embers",
		Colors = { { 255, 241, 194 }, { 255, 138, 42 }, { 200, 50, 42 } },
		Trail = {
			Texture = "Fire",
			TextureLength = 1.4,
			Emission = 1,
			Width = 1.2,
			Lifetime = 0.8,
			Glitter = { 255, 150, 60 },
			Light = { 255, 138, 42 },
		},
	},
	{
		Id = "Trail_FallingLeaves",
		Slot = "Trail",
		Name = "Falling Leaves",
		Description = "Leaves flutter down behind you.",
		Icon = "🍂",
		Tier = "Effect",
		Effect = "FallingLeaves",
		Colors = { { 255, 208, 74 }, { 255, 138, 42 }, { 200, 50, 42 } },
		Trail = { Particles = "Leaves", Width = 0.7, Lifetime = 0.55, Emission = 0.25 },
	},
	{
		Id = "Trail_WispSteps",
		Slot = "Trail",
		Name = "Wisp Steps",
		Description = "Spirit flames flicker in your footprints.",
		Icon = "👣",
		Tier = "Effect",
		Effect = "WispSteps",
		Colors = { { 216, 255, 240 }, { 125, 255, 178 }, { 122, 216, 255 } },
		Trail = { Particles = "Wisp", Width = 0.5, Lifetime = 0.45, Emission = 1, Light = { 125, 255, 178 } },
	},
	{
		Id = "Elim_CrowScatter",
		Slot = "Elimination",
		Name = "Crow Scatter",
		Description = "You burst into a flock of crows.",
		Icon = "🐦",
		Tier = "Effect",
		Effect = "CrowScatter",
	},
	{
		Id = "Elim_LeafPile",
		Slot = "Elimination",
		Name = "Leaf Pile",
		Description = "Plop into a leaf pile that bursts.",
		Icon = "🍁",
		Tier = "Effect",
		Effect = "LeafPile",
	},
	{
		Id = "Elim_LanternSnuff",
		Slot = "Elimination",
		Name = "Lantern Snuff",
		Description = "Out like a lantern, with a curl of smoke.",
		Icon = "💨",
		Tier = "Effect",
		Effect = "LanternSnuff",
	},
	{
		Id = "Victory_Bonfire",
		Slot = "Victory",
		Name = "Bonfire",
		Description = "A ring of bonfire flames roars up.",
		Icon = "🔥",
		Tier = "Effect",
		Effect = "Bonfire",
		Colors = { { 255, 241, 194 }, { 255, 138, 42 }, { 200, 50, 42 } },
	},
	{
		Id = "Victory_HarvestRain",
		Slot = "Victory",
		Name = "Harvest Rain",
		Description = "Leaves, acorns and apples rain down.",
		Icon = "🍎",
		Tier = "Effect",
		Effect = "HarvestRain",
		Colors = { { 200, 50, 42 }, { 255, 138, 42 }, { 255, 208, 74 } },
	},
	{
		Id = "Victory_Moonrise",
		Slot = "Victory",
		Name = "Moonrise",
		Description = "A harvest moon rises as owls fly past.",
		Icon = "🌕",
		Tier = "Effect",
		Effect = "Moonrise",
		Colors = { { 255, 207, 122 }, { 255, 138, 42 } },
	},
	-- The starter pack's own trail (sold once for Robux, never random).
	{
		Id = "Trail_HarvestBanner",
		Slot = "Trail",
		Name = "Harvest Banner",
		Description = "A banner of autumn colours. Starter pack only.",
		Icon = "🎏",
		Tier = "Starter",
		Colors = { { 200, 50, 42 }, { 255, 138, 42 }, { 255, 208, 74 }, { 255, 243, 228 } },
		Trail = { Width = 1.5, Lifetime = 0.7, Emission = 0.25 },
	},
} :: { Item }

Seasons.ItemById = {} :: { [string]: Item }
for _, item in Seasons.Items do
	Seasons.ItemById[item.Id] = item
end

function Seasons.Get(id: string): Season?
	return Seasons.ById[id]
end

function Seasons.CurrentSeason(): Season
	return Seasons.ById[Seasons.Current]
end

-- The season an item belongs to, or nil (the starter trail belongs to its season too).
function Seasons.SeasonOf(itemId: string): Season?
	for _, season in Seasons.ById do
		if season.Title == itemId or season.Starter == itemId then
			return season
		end
		for _, list in { season.Pets, season.Hats, season.Effects } do
			if table.find(list, itemId) then
				return season
			end
		end
	end
	return nil
end

-- Whether an item can still be found in crates (it's the current season's).
function Seasons.InCrates(itemId: string): boolean
	local season = Seasons.SeasonOf(itemId)
	return season ~= nil and season.Id == Seasons.Current and season.Starter ~= itemId
end

return Seasons

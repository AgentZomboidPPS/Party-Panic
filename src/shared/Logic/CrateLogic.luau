--!strict
-- What's in a season crate and how it's rolled (owner, on the crate seasons: "crate loot consists of
-- multiple tiers. rarest loot is a seasonal title. should be 1/500 crates ... next tier of loot is
-- pets, 5 total pets per season ... each pet 1/100, no dupes. next tier can be seasonal hats. 5
-- total, 1/50, no dupes. next tier can be seasonal effects ... 3 of each, 1/25. below this, crate
-- rewards should most commonly be varying amounts of coins.", then "Hollow night comes first ... Also
-- do all of your ideas.").
--
-- The odds are per tier (the design page's recommendation, so coins stay the most common result and
-- a pet feels rare): the title 1 in 500, a pet 1 in 100, a hat 1 in 50, an effect 1 in 25, coins the
-- rest (92.8%). Hitting a tier gives an item of that tier the player doesn't own yet, picked evenly,
-- so nobody ever gets a duplicate; a tier they've finished is out of the roll, its share going to the
-- coins (owner: "Remove the jackpot for coins. It feels bad to hit a 'jackpot' and only get 150
-- coins."). The Lantern Meter is the bad-luck guarantee: every crate without a pet or the title adds
-- one, and at 150 the next crate is a pet they don't own (while any are left).
--
-- A player's very first crate always holds an item (owner: "can we make it so everyone is
-- guaranteed an item from their first crate?"): the title and the pets keep their usual chances, and
-- the coins' share goes to the hats and effects, in their usual proportion (1 to 2). The odds screen
-- shows the usual odds for it (owner: "I dont want to display the first crate odds since they will
-- be boosted."): only the server rolls with `first`, and nothing in the game or about it mentions
-- the boost. (Every new player's 3 starting keys are free, so a first crate is almost never a paid
-- one.)
--
-- PersonalOdds is the odds screen Roblox requires before anyone pays for a random item: every
-- outcome and its usual chance for this player right now (no duplicates changes them as they
-- collect; the meter's guaranteed pet shows as it is), adding up to exactly 100%.
--
-- Keys (the owner: "3 keys for 1st place, 2 keys for second, and 1 key for third", then "Winner
-- should get 3 keys, 2nd gets 2 and 3rd gets 1.", and after "won obby odyssey and got no keys got
-- 3rd got no key on crazy cutters", asked how keys should work: "3/2/1 every round"): every round
-- pays 3 / 2 / 1 to the people in 1st to 3rd, and so does the Party Cup podium (bots never get
-- keys), nothing for just playing a cup; every new player gets 3 to start.
-- Crates: 1 for every round a person plays to the end. More keys (the design page's "More ways to earn
-- keys"): 1 for each weekly quest finished and 1 for every 5th level reached on the Rewards Road.
-- Leaf module: no requires, no Roblox APIs.

local CrateLogic = {}

export type Tier = "Title" | "Pet" | "Hat" | "Effect" | "Coins"

export type Season = {
	Title: string,
	Pets: { string },
	Hats: { string },
	Effects: { string },
}

export type Result = {
	Tier: Tier,
	Item: string?, -- the item won (nil for coins)
	Coins: number, -- coins won (0 when an item was won)
	Guaranteed: boolean, -- the Lantern Meter gave this pet
	Meter: number, -- the Lantern Meter after this crate
}

export type OddsRow = { Key: string, Tier: Tier, Label: string, Chance: number }

-- Per tier, rarest first: the chance of hitting it (while the player has something in it to find).
CrateLogic.Tiers = {
	{ Tier = "Title" :: Tier, Chance = 0.002 },
	{ Tier = "Pet" :: Tier, Chance = 0.01 },
	{ Tier = "Hat" :: Tier, Chance = 0.02 },
	{ Tier = "Effect" :: Tier, Chance = 0.04 },
}

-- The coin results, of the whole crate (they add up to 92.8%; more of the crate, in the same
-- proportions, once a tier is finished).
CrateLogic.Coins = {
	{ Coins = 5, Chance = 0.4 },
	{ Coins = 10, Chance = 0.28 },
	{ Coins = 20, Chance = 0.15 },
	{ Coins = 35, Chance = 0.06 },
	{ Coins = 60, Chance = 0.03 },
	{ Coins = 150, Chance = 0.008 },
}

CrateLogic.Meter = 150 -- crates without a pet or the title, then a guaranteed pet
CrateLogic.BigCoins = 60 -- a coin result this big gets a gold beam and a cheer

-- Keys and crates.
CrateLogic.PodiumKeys = { 3, 2, 1 }
CrateLogic.StarterKeys = 3
CrateLogic.CratesPerRound = 1
CrateLogic.OpenMany = 5 -- "Open 5"
CrateLogic.FriendRadius = 20 -- a friend this close when you open adds a point to the meter
CrateLogic.QuestKeys = 1 -- for each weekly quest finished
CrateLogic.LevelKeysEvery = 5 -- a key for every 5th level reached

-- Crates opened that earn a medal.
CrateLogic.Milestones = { 10, 50, 100, 250, 500 }

function CrateLogic.ItemsOf(season: Season, tier: Tier): { string }
	if tier == "Title" then
		return { season.Title }
	elseif tier == "Pet" then
		return season.Pets
	elseif tier == "Hat" then
		return season.Hats
	elseif tier == "Effect" then
		return season.Effects
	end
	return {}
end

-- Every item of the season, rarest tier first (the collection log's order).
function CrateLogic.AllItems(season: Season): { { Item: string, Tier: Tier } }
	local out = {}
	for _, tier in CrateLogic.Tiers do
		for _, item in CrateLogic.ItemsOf(season, tier.Tier) do
			table.insert(out, { Item = item, Tier = tier.Tier })
		end
	end
	return out
end

local function missing(season: Season, tier: Tier, owned: { [string]: any }): { string }
	local out = {}
	for _, item in CrateLogic.ItemsOf(season, tier) do
		if not owned[item] then
			table.insert(out, item)
		end
	end
	return out
end

CrateLogic.Missing = missing

-- How many of the season's items are owned, of how many.
function CrateLogic.Progress(season: Season, owned: { [string]: any }): (number, number)
	local have, total = 0, 0
	for _, entry in CrateLogic.AllItems(season) do
		total += 1
		if owned[entry.Item] then
			have += 1
		end
	end
	return have, total
end

-- The coins for a roll that landed in the coin band: `r` from 0 to 1 across it.
local function coinsAt(r: number): number
	local total = 0
	for _, row in CrateLogic.Coins do
		total += row.Chance
	end
	local acc = 0
	for _, row in CrateLogic.Coins do
		acc += row.Chance / total
		if r < acc then
			return row.Coins
		end
	end
	return CrateLogic.Coins[#CrateLogic.Coins].Coins
end

-- Crates opened over every season (a profile's Crates.Seasons, or CrateService's data.Seasons).
function CrateLogic.LifetimeOpened(seasons: any): number
	local total = 0
	for _, progress in if type(seasons) == "table" then seasons else {} do
		if type(progress) == "table" then
			total += progress.Opened or 0
		end
	end
	return total
end

-- The tiers' chances for this crate: the usual ones, or on a first crate ever (`first`) the coins'
-- share spread over the hats and effects still to find, so it always holds an item.
local function tierChances(season: Season, owned: { [string]: any }, first: boolean?): { [Tier]: number }
	local chances: { [Tier]: number } = {}
	local spare = 1
	local common = 0
	for _, tier in CrateLogic.Tiers do
		if #missing(season, tier.Tier, owned) > 0 then
			chances[tier.Tier] = tier.Chance
			spare -= tier.Chance
			if tier.Tier == "Hat" or tier.Tier == "Effect" then
				common += tier.Chance
			end
		end
	end
	if first and common > 0 then
		for tier, chance in chances do
			if tier == "Hat" or tier == "Effect" then
				chances[tier] = chance + spare * chance / common
			end
		end
	end
	return chances
end

-- Whether the next crate is the meter's guaranteed pet.
function CrateLogic.Guaranteed(season: Season, owned: { [string]: any }, meter: number): boolean
	return meter + 1 >= CrateLogic.Meter and #missing(season, "Pet", owned) > 0
end

-- Opens one crate. `random` returns numbers from 0 (inclusive) to 1 (exclusive); it's called twice
-- (the tier, then which item or how many coins). `meter` is the Lantern Meter before this crate;
-- `bonus` adds to it (a friend nearby).
function CrateLogic.Roll(
	season: Season,
	owned: { [string]: any },
	meter: number,
	random: () -> number,
	bonus: number?,
	first: boolean? -- the player's first crate ever (it always holds an item)
): Result
	local function finish(result: Result): Result
		local resets = result.Tier == "Title" or result.Tier == "Pet"
		local left = #missing(season, "Pet", owned) - (if result.Tier == "Pet" then 1 else 0)
		if resets or left <= 0 then
			result.Meter = 0
		else
			result.Meter = math.min(CrateLogic.Meter - 1, meter + 1 + (bonus or 0))
		end
		return result
	end

	if CrateLogic.Guaranteed(season, owned, meter) then
		local pets = missing(season, "Pet", owned)
		local pick = pets[math.clamp(math.floor(random() * #pets) + 1, 1, #pets)]
		return finish({ Tier = "Pet", Item = pick, Coins = 0, Guaranteed = true, Meter = 0 })
	end

	-- A finished tier is out of the roll: its share falls through to the coins.
	local chances = tierChances(season, owned, first)
	local r = random()
	local acc = 0
	for _, tier in CrateLogic.Tiers do
		local choices = missing(season, tier.Tier, owned)
		if #choices > 0 then
			acc += chances[tier.Tier]
			if r < acc then
				local pick = choices[math.clamp(math.floor(random() * #choices) + 1, 1, #choices)]
				return finish({ Tier = tier.Tier, Item = pick, Coins = 0, Guaranteed = false, Meter = 0 })
			end
		end
	end
	return finish({ Tier = "Coins", Item = nil, Coins = coinsAt(random()), Guaranteed = false, Meter = 0 })
end

-- The odds of every outcome for this player's next crate, adding up to exactly 1. Item rows give
-- each item still to find its own chance; a finished tier has none (its share is in the coins).
-- `first` gives a first crate's boosted odds (the tests check the roll against them; the odds screen
-- never passes it).
function CrateLogic.PersonalOdds(season: Season, owned: { [string]: any }, meter: number, first: boolean?): { OddsRow }
	local rows: { OddsRow } = {}
	if CrateLogic.Guaranteed(season, owned, meter) then
		local pets = missing(season, "Pet", owned)
		for _, pet in pets do
			table.insert(rows, { Key = pet, Tier = "Pet", Label = pet, Chance = 1 / #pets })
		end
		return rows
	end
	local chances = tierChances(season, owned, first)
	local tiers = 0
	for _, tier in CrateLogic.Tiers do
		local choices = missing(season, tier.Tier, owned)
		if #choices > 0 then
			local chance = chances[tier.Tier]
			tiers += chance
			for _, item in choices do
				table.insert(rows, { Key = item, Tier = tier.Tier, Label = item, Chance = chance / #choices })
			end
		end
	end
	if tiers >= 1 - 1e-9 then
		return rows -- (a first crate: no coins in it)
	end
	local coinTotal = 0
	for _, row in CrateLogic.Coins do
		coinTotal += row.Chance
	end
	for _, row in CrateLogic.Coins do
		table.insert(rows, {
			Key = `Coins{row.Coins}`,
			Tier = "Coins",
			Label = `{row.Coins} coins`,
			Chance = (1 - tiers) * row.Chance / coinTotal,
		})
	end
	return rows
end

-- A chance as the odds screen writes it: "0.2%", "1%", "0.33%", "37.12%" (two decimals at most,
-- trailing zeros dropped).
function CrateLogic.Percent(chance: number): string
	local text = string.format("%.2f", chance * 100)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text .. "%"
end

-- The tier totals the odds screen shows (title, pet, hat, effect, coins), adding up to exactly 1.
function CrateLogic.TierOdds(
	season: Season,
	owned: { [string]: any },
	meter: number,
	first: boolean?
): { [string]: number }
	local out: { [string]: number } = { Title = 0, Pet = 0, Hat = 0, Effect = 0, Coins = 0 }
	for _, row in CrateLogic.PersonalOdds(season, owned, meter, first) do
		out[row.Tier] += row.Chance
	end
	return out
end

-- The keys a Party Cup gives one person: by their podium place (1 to 3; 0 or nil off it). Bots get
-- none.
function CrateLogic.CupKeys(place: number?, isBot: boolean): number
	if isBot or not place then
		return 0
	end
	return CrateLogic.PodiumKeys[place] or 0
end

-- The keys a round gives one person for their place in it: 3 / 2 / 1 for 1st to 3rd (a shared place
-- pays each person in it), nothing lower. Bots get none.
function CrateLogic.RoundKeys(place: number?, isBot: boolean): number
	if isBot or not place then
		return 0
	end
	return CrateLogic.PodiumKeys[place] or 0
end

-- The keys for going from level `before` to `after`: one for every multiple of LevelKeysEvery passed.
function CrateLogic.LevelKeys(before: number, after: number): number
	local every = CrateLogic.LevelKeysEvery
	return math.max(0, math.floor(after / every) - math.floor(before / every))
end

-- The milestone a count of crates opened just reached (the count itself), or nil.
function CrateLogic.MilestoneAt(opened: number): number?
	return if table.find(CrateLogic.Milestones, opened) then opened else nil
end

-- The best milestone `opened` crates have reached (0 below the first): the nameplate's frame.
function CrateLogic.FrameFor(opened: number): number
	local best = 0
	for _, mark in CrateLogic.Milestones do
		if opened >= mark then
			best = mark
		end
	end
	return best
end

return CrateLogic

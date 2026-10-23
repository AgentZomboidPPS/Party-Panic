-- The crate seasons (owner: "seasonal crates ... crate loot consists of multiple tiers ... no dupes",
-- then "Hollow night comes first ... Also do all of your ideas."): the odds add up, a roll never gives
-- an item twice, a finished tier is out of the roll (owner: "Remove the jackpot for coins"), its share
-- going to the coins, the Lantern Meter guarantees a pet at 150, the
-- odds screen is right for every collection, keys are paid by the rules, and Hollow Night's items
-- are all real, distinct and in the right slots. Shared/Seasons and Logic/CrateLogic.
local TestKit = require("./TestKit")
local CrateLogic = require("../src/shared/Logic/CrateLogic")
local Seasons = require("../src/shared/Seasons")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local season = Seasons.CurrentSeason()

-- A seeded stand-in for Random:NextNumber.
local function generator(seed: number): () -> number
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local function close(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

test("Crates: the odds add up to exactly 100%", function()
	local total = 0
	for _, tier in CrateLogic.Tiers do
		total += tier.Chance
	end
	for _, row in CrateLogic.Coins do
		total += row.Chance
	end
	expectTrue(close(total, 1), `total {total}`)
	expectEqual(CrateLogic.Tiers[1].Chance, 1 / 500)
	expectEqual(CrateLogic.Tiers[2].Chance, 1 / 100)
	expectEqual(CrateLogic.Tiers[3].Chance, 1 / 50)
	expectEqual(CrateLogic.Tiers[4].Chance, 1 / 25)
end)

test("Crates: the personal odds add up to 100% whatever is owned", function()
	local items = CrateLogic.AllItems(season)
	local random = generator(7)
	for trial = 1, 200 do
		local owned = {}
		for _, entry in items do
			if random() < trial / 200 then
				owned[entry.Item] = true
			end
		end
		for _, meter in { 0, 60, 148, 149 } do
			local sum = 0
			for _, row in CrateLogic.PersonalOdds(season, owned, meter) do
				expectTrue(row.Chance > 0, row.Key)
				expectTrue(not owned[row.Key], `{row.Key} is owned but listed`)
				sum += row.Chance
			end
			expectTrue(close(sum, 1), `sum {sum} at meter {meter}`)
			local tiers = CrateLogic.TierOdds(season, owned, meter)
			expectTrue(close(tiers.Title + tiers.Pet + tiers.Hat + tiers.Effect + tiers.Coins, 1), "tier sum")
		end
	end
end)

test("Crates: nothing owned, a pet is 1 in 100 and each pet 1 in 500", function()
	local tiers = CrateLogic.TierOdds(season, {}, 0)
	expectTrue(close(tiers.Pet, 0.01), `pet {tiers.Pet}`)
	expectTrue(close(tiers.Coins, 0.928), `coins {tiers.Coins}`)
	for _, row in CrateLogic.PersonalOdds(season, {}, 0) do
		if row.Tier == "Pet" then
			expectTrue(close(row.Chance, 0.002), row.Key)
		end
	end
	expectEqual(CrateLogic.Percent(0.002), "0.2%")
	expectEqual(CrateLogic.Percent(0.01), "1%")
	expectEqual(CrateLogic.Percent(0.01 / 3), "0.33%")
	expectEqual(CrateLogic.Percent(0.928 * 0.4 / 0.928), "40%")
end)

test("Crates: rolls follow the odds and never give an item twice", function()
	local random = generator(42)
	local owned: { [string]: boolean } = {}
	local counts = { Title = 0, Pet = 0, Hat = 0, Effect = 0, Coins = 0 }
	local meter = 0
	local opened = 200000
	local afterAll = 0
	for _ = 1, opened do
		local done = CrateLogic.Progress(season, owned) == 23
		local result = CrateLogic.Roll(season, owned, meter, random)
		counts[result.Tier] += 1
		if result.Item then
			expectTrue(not owned[result.Item], `duplicate {result.Item}`)
			owned[result.Item] = true
			expectEqual(result.Coins, 0)
		else
			expectEqual(result.Tier, "Coins")
			expectTrue(result.Coins > 0, "coins")
		end
		if done then
			afterAll += 1
			expectEqual(result.Tier, "Coins") -- everything found: only coins, never a "jackpot"
		end
		meter = result.Meter
		expectTrue(meter >= 0 and meter < CrateLogic.Meter, `meter {meter}`)
	end
	-- Everything gets found eventually.
	local have, total = CrateLogic.Progress(season, owned)
	expectEqual(have, total)
	expectEqual(total, 23)
	expectTrue(afterAll > 0, "crates opened after the set was done")
end)

test("Crates: each tier is hit at its odds while it has something to find", function()
	-- Nothing owned and the meter low (no guarantee): every roll is a fresh draw at the tiers' odds.
	-- (Luau's own generator, seeded: the simple one above skews the shares when a crate takes two
	-- draws in a row.)
	math.randomseed(11)
	local random = function(): number
		return math.random()
	end
	local counts = { Title = 0, Pet = 0, Hat = 0, Effect = 0, Coins = 0 }
	local opened = 200000
	for _ = 1, opened do
		counts[CrateLogic.Roll(season, {}, 0, random).Tier] += 1
	end
	expectTrue(math.abs(counts.Effect / opened - 0.04) < 0.003, `effects {counts.Effect}`)
	expectTrue(math.abs(counts.Hat / opened - 0.02) < 0.002, `hats {counts.Hat}`)
	expectTrue(math.abs(counts.Pet / opened - 0.01) < 0.0015, `pets {counts.Pet}`)
	expectTrue(math.abs(counts.Title / opened - 0.002) < 0.001, `titles {counts.Title}`)
	expectTrue(math.abs(counts.Coins / opened - 0.928) < 0.004, `coins {counts.Coins}`)
end)

test("Crates: a finished tier is out of the roll, its share going to the coins", function()
	local owned = {}
	for _, pet in season.Pets do
		owned[pet] = true
	end
	-- 0.0021 is just past the title's 0.002: with every pet found, that's the hats now (their own
	-- 2%, from 0.002 to 0.022), never a pet and never a "jackpot".
	local sequence = { 0.0021, 0.5 }
	local index = 0
	local result = CrateLogic.Roll(season, owned, 10, function()
		index += 1
		return sequence[index]
	end)
	expectEqual(result.Tier, "Hat")
	expectTrue(result.Item ~= nil and table.find(season.Hats, result.Item) ~= nil, "a hat")
	expectEqual(result.Coins, 0)
	expectEqual(result.Meter, 0) -- no pets left to wait for
	-- The odds: no pets, the other tiers unchanged, the coins 1% more (in the same proportions).
	local tiers = CrateLogic.TierOdds(season, owned, 10)
	expectTrue(close(tiers.Pet, 0), `pet {tiers.Pet}`)
	expectTrue(close(tiers.Hat, 0.02), `hat {tiers.Hat}`)
	expectTrue(close(tiers.Coins, 0.938), `coins {tiers.Coins}`)
	for _, row in CrateLogic.PersonalOdds(season, owned, 10) do
		if row.Key == "Coins150" then
			expectTrue(close(row.Chance, 0.008 * 0.938 / 0.928), `150 coins {row.Chance}`)
		end
	end
	-- A roll past every item tier is coins.
	local coins = CrateLogic.Roll(season, owned, 10, function()
		return 0.95
	end)
	expectEqual(coins.Tier, "Coins")
end)

test("Crates: the Lantern Meter guarantees a pet at 150, then starts again", function()
	local random = generator(3)
	local owned = {}
	local result = CrateLogic.Roll(season, owned, 149, function()
		return 0.99 -- would be coins
	end)
	expectEqual(result.Tier, "Pet")
	expectEqual(result.Guaranteed, true)
	expectTrue(result.Item ~= nil and table.find(season.Pets, result.Item) ~= nil, "a pet")
	expectEqual(result.Meter, 0)
	-- Coins fill it by one, a friend nearby by one more, and it never passes 149.
	local coins = CrateLogic.Roll(season, owned, 10, function()
		return 0.99
	end)
	expectEqual(coins.Tier, "Coins")
	expectEqual(coins.Meter, 11)
	local friend = CrateLogic.Roll(season, owned, 10, function()
		return 0.99
	end, 1)
	expectEqual(friend.Meter, 12)
	local top = CrateLogic.Roll(season, owned, 148, function()
		return 0.99
	end, 1)
	expectEqual(top.Meter, 149)
	-- The guaranteed crate shows as a 100% pet on the odds screen.
	local tiers = CrateLogic.TierOdds(season, owned, 149)
	expectTrue(close(tiers.Pet, 1), `guaranteed {tiers.Pet}`)
	-- Over a long run, no stretch without a pet or the title lasts 150 crates while pets remain.
	local dry, longest = 0, 0
	local meter = 0
	local have: { [string]: boolean } = {}
	for _ = 1, 3000 do
		local roll = CrateLogic.Roll(season, have, meter, random)
		if roll.Item then
			have[roll.Item] = true
		end
		if roll.Tier == "Title" or (roll.Tier == "Pet" and roll.Item) then
			dry = 0
		else
			dry += 1
		end
		if #CrateLogic.Missing(season, "Pet", have) > 0 then
			longest = math.max(longest, dry)
		end
		meter = roll.Meter
	end
	expectTrue(longest < CrateLogic.Meter, `longest dry run {longest}`)
end)

test("Crates: keys from rounds, a Party Cup, levels and milestones", function()
	-- Exactly 3 / 2 / 1 on the podium (owner: "Winner should get 3 keys, 2nd gets 2 and 3rd gets 1.").
	expectEqual(CrateLogic.CupKeys(1, false), 3)
	expectEqual(CrateLogic.CupKeys(2, false), 2)
	expectEqual(CrateLogic.CupKeys(3, false), 1)
	expectEqual(CrateLogic.CupKeys(4, false), 0)
	expectEqual(CrateLogic.CupKeys(nil, false), 0)
	expectEqual(CrateLogic.CupKeys(1, true), 0) -- bots never
	-- Every round pays the same to its top 3 (owner: "3/2/1 every round"); a shared place pays each.
	expectEqual(CrateLogic.RoundKeys(1, false), 3)
	expectEqual(CrateLogic.RoundKeys(2, false), 2)
	expectEqual(CrateLogic.RoundKeys(3, false), 1)
	expectEqual(CrateLogic.RoundKeys(4, false), 0)
	expectEqual(CrateLogic.RoundKeys(nil, false), 0)
	expectEqual(CrateLogic.RoundKeys(1, true), 0) -- bots never
	expectEqual(CrateLogic.MilestoneAt(50), 50)
	expectEqual(CrateLogic.MilestoneAt(51), nil)
	expectEqual(CrateLogic.FrameFor(9), 0)
	expectEqual(CrateLogic.FrameFor(10), 10)
	expectEqual(CrateLogic.FrameFor(260), 250)
	expectEqual(CrateLogic.FrameFor(9999), 500)
	-- A key for every 5th level reached, however many levels at once.
	expectEqual(CrateLogic.LevelKeys(4, 5), 1)
	expectEqual(CrateLogic.LevelKeys(5, 6), 0)
	expectEqual(CrateLogic.LevelKeys(3, 16), 3)
	expectEqual(CrateLogic.LevelKeys(1, 1), 0)
end)

test("Seasons: Hollow Night's items are real, distinct and in their slots", function()
	expectEqual(Seasons.Current, "HollowNight")
	expectEqual(#season.Pets, 5)
	expectEqual(#season.Hats, 5)
	expectEqual(#season.Effects, 12)
	local seen = {}
	local slots = { Title = 0, Pet = 0, Hat = 0, Aura = 0, Trail = 0, Elimination = 0, Victory = 0 }
	for _, entry in CrateLogic.AllItems(season) do
		local item = Seasons.ItemById[entry.Item]
		expectTrue(item ~= nil, `{entry.Item} is listed`)
		expectTrue(not seen[entry.Item], `{entry.Item} twice`)
		seen[entry.Item] = true
		slots[item.Slot] += 1
		expectTrue(Seasons.InCrates(entry.Item), entry.Item)
		expectTrue(#item.Name <= 18, `{item.Name} fits a card`)
		expectTrue(#item.Description <= 48, `{item.Name}'s description fits`)
		local prefix = string.match(item.Id, "^(%a+)_")
		local slotOf = {
			Title = "Title",
			Pet = "Pet",
			Hat = "Hat",
			Aura = "Aura",
			Trail = "Trail",
			Elim = "Elimination",
			Victory = "Victory",
		}
		expectEqual(slotOf[prefix], item.Slot)
	end
	expectEqual(slots, { Title = 1, Pet = 5, Hat = 5, Aura = 3, Trail = 3, Elimination = 3, Victory = 3 })
	-- Every pet has its look, and its matching hat is one of the season's hats.
	for _, pet in season.Pets do
		local info = season.PetInfo[pet]
		expectTrue(info ~= nil, pet)
		if info.Hat then
			expectTrue(table.find(season.Hats, info.Hat) ~= nil, `{pet}'s hat`)
		end
	end
	-- The starter pack's trail is the season's, but never in crates.
	expectTrue(Seasons.ItemById[season.Starter] ~= nil, "starter item")
	expectEqual(Seasons.InCrates(season.Starter), false)
	-- Effects, knockouts and victories name an effect; names are letters and digits.
	for _, item in Seasons.Items do
		if item.Slot == "Victory" or item.Slot == "Elimination" or item.Slot == "Aura" then
			expectTrue(item.Effect ~= nil and string.match(item.Effect, "^%w+$") ~= nil, `{item.Id} effect`)
		end
		if item.Slot == "Trail" or item.Slot == "Title" then
			expectTrue(item.Colors ~= nil and #item.Colors >= 1, `{item.Id} colours`)
		end
	end
end)

return nil

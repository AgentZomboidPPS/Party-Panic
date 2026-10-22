-- The Hat cosmetic slot and the PUMPKIN HAT (owner: "do pumpkin hat now"): every slot a cosmetic uses
-- is one the game knows everywhere (equipping, the shop's tabs, reward cards, saved profiles), the
-- hat is a free HALLOWEEN PARTY reward on its track between 45 and 70 candy, and its prop and the
-- World/Hats look point at each other.
local fs = require("@lune/fs")

local TestKit = require("./TestKit")
local Events = require("../src/shared/Events")
local ProfileTemplate = require("../src/shared/Logic/ProfileTemplate")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local cosmeticsSource = fs.readFile("src/shared/Cosmetics.luau")
local hatsSource = fs.readFile("src/server/World/Hats.luau")
local propsSource = fs.readFile("src/server/World/Props/Hats.luau")

-- Each catalog entry's text (the top-level `{ ... },` blocks in Cosmetics.luau's list).
local items = {}
for block in string.gmatch(cosmeticsSource, "\n\t{\n(.-)\n\t},") do
	local id = string.match(block, 'Id = "([%w_]+)"')
	if id then
		items[id] = block
	end
end

local function quoted(text: string): { string }
	local out = {}
	for word in string.gmatch(text, '"(%w+)"') do
		table.insert(out, word)
	end
	return out
end

local equipSlots = quoted(string.match(cosmeticsSource, "EquipSlots = (%b{})") :: string)
local slotNames = {}
for key, label in string.gmatch(string.match(cosmeticsSource, "SlotNames = (%b{})") :: string, '(%w+) = "([^"]+)"') do
	slotNames[key] = label
end
local shopTabs = {}
for slot in string.gmatch(string.match(cosmeticsSource, "ShopTabs = (%b{})") :: string, 'Slot = "(%w+)"') do
	table.insert(shopTabs, slot)
end

test("every cosmetic's slot is one the game knows: named on cards and given a shop tab", function()
	local count = 0
	for id, block in items do
		local slot = string.match(block, 'Slot = "(%w+)"')
		expectTrue(slot ~= nil and slotNames[slot] ~= nil, `{id}'s slot {slot} has a name for reward cards`)
		expectTrue(table.find(shopTabs, slot) ~= nil, `{id}'s slot {slot} has a shop tab`)
		count += 1
	end
	expectTrue(count > 50, "the catalog was read")
	for _, slot in shopTabs do
		expectTrue(slotNames[slot] ~= nil, `the {slot} tab is a known slot`)
	end
end)

test("every slot worn is saved in a profile, the Hat slot too", function()
	expectTrue(table.find(equipSlots, "Hat") ~= nil, "a hat is equipped like a trail")
	expectEqual(slotNames.Hat, "Hat")
	expectTrue(table.find(shopTabs, "Hat") ~= nil, "the shop has a Hats tab")
	for _, slot in equipSlots do
		local default = ProfileTemplate.Equipped[slot]
		expectTrue(type(default) == "string", `a new profile has Equipped.{slot}`)
		if default ~= "" then
			local block = items[default]
			expectTrue(
				block ~= nil and string.find(block, "Default = true", 1, true) ~= nil,
				`{slot}'s default is owned`
			)
		end
	end
	expectEqual(ProfileTemplate.Equipped.Hat, "", "nobody starts with a hat on")
	for slot in ProfileTemplate.Equipped do
		expectTrue(table.find(equipSlots, slot) ~= nil, `Equipped.{slot} is a slot players equip`)
	end
end)

test("the PUMPKIN HAT is a free HALLOWEEN PARTY reward nobody can buy", function()
	local block = items.Hat_Pumpkin
	expectTrue(block ~= nil, "it's in the catalog")
	expectTrue(string.find(block, 'Slot = "Hat"', 1, true) ~= nil, "it's a hat")
	expectTrue(string.find(block, 'Name = "Pumpkin Hat"', 1, true) ~= nil)
	expectTrue(string.find(block, 'Event = "Halloween2026"', 1, true) ~= nil, "from the HALLOWEEN PARTY")
	for _, field in { "Price =", "UnlockLevel =", "UnlockStat =", "Default =", "Vip =" } do
		expectTrue(not string.find(block, field, 1, true), `it has no {field}`)
	end
end)

test("it's its own step on the track, between 45 and 70 candy; the rest of the track is as it was", function()
	local halloween = Events.Get("Halloween2026") :: Events.Event
	local steps = {}
	for _, step in halloween.Track do
		table.insert(steps, `{step.Candy} {step.Reward}`)
	end
	expectEqual(steps, {
		"10 Emote_CandyToss",
		"25 Title_PumpkinKing",
		"45 Elim_Spooked",
		"55 Hat_Pumpkin",
		"70 Victory_BatBurst",
		"100 Trail_CandyCorn",
	})
	expectEqual(halloween.Headline, "Hat_Pumpkin", "the Rewards screen shows it off")
	expectEqual(halloween.Candy, { Played = 1, TopHalf = 1, Win = 2, Pumpkin = 3, PumpkinsPerDay = 3 })
end)

test("its look and its prop point at each other, and the prop's mesh is uploaded", function()
	local look = string.match(hatsSource, "Hat_Pumpkin = (%b{})")
	expectTrue(look ~= nil, "World/Hats has a look for it")
	local prop = string.match(look :: string, 'Prop = "(%w+)"')
	local handle = string.match(look :: string, 'Handle = "(%w+)"')
	local glow = string.match(look :: string, 'Glow = "(%w+)"')
	expectEqual(prop, "PumpkinHat")
	local spec = string.match(propsSource, (prop :: string) .. " = (%b{})")
	expectTrue(spec ~= nil, "World/Props/Hats defines its prop")
	local assetId = tonumber(string.match(spec :: string, "AssetId = (%d+)"))
	expectTrue(assetId ~= nil and assetId > 0, "its mesh is uploaded")
	for _, piece in { handle, glow, "HatStem" } do
		expectTrue(string.find(spec :: string, `{piece} = rgb`, 1, true) ~= nil, `the prop colours {piece}`)
	end
	expectTrue(string.find(spec :: string, "HatGlow = Enum.Material.Neon", 1, true) ~= nil, "the glow is Neon")
	expectTrue(fs.isFile(`assets/meshes/{prop}.glb`), "its mesh file is in assets/meshes")
end)

-- The crate seasons' effects (owner: "Hollow night comes first ... This will be players first season. I
-- want it to look insane."): every effect a season item names is really drawn by EffectsController
-- (its knockouts and victories, and the short versions of its auras and trails), every pet's look
-- names a flourish PetController knows, and each particle trail is one CosmeticService builds.
-- EffectsController needs Roblox's script tree, so this reads its source, like Catalog.spec.
local fs = require("@lune/fs")

local TestKit = require("./TestKit")
local Seasons = require("../src/shared/Seasons")

local test, expectTrue = TestKit.test, TestKit.expectTrue

local effectsSource = fs.readFile("src/client/Controllers/EffectsController.luau")
local petsSource = fs.readFile("src/client/Controllers/PetController.luau")
local cosmeticSource = fs.readFile("src/server/Services/CosmeticService.luau")

local effects: { [string]: boolean } = {}
local tableBody = string.match(effectsSource, "local EFFECTS: [^\n]*= {\n(.-)\n}\n") :: string
for name in string.gmatch("\n" .. tableBody, "\n\t(%w+) = function") do
	effects[name] = true
end
for name in string.gmatch(effectsSource, "\nEFFECTS%.(%w+) = function") do
	effects[name] = true
end

test("Seasons: every effect a season item names is drawn by EffectsController", function()
	local count = 0
	for _, item in Seasons.Items do
		if item.Effect then
			count += 1
			expectTrue(effects[item.Effect], `{item.Id} plays "{item.Effect}", which nothing draws`)
		end
	end
	expectTrue(count >= 12, "the season's effect items were read")
end)

test("Seasons: every pet's flourish and particle trail is one the game knows", function()
	for _, id in Seasons.Order do
		local season = Seasons.Get(id) :: Seasons.Season
		for _, pet in season.Pets do
			local flourish = season.PetInfo[pet].Flourish
			expectTrue(
				string.find(petsSource, `kind == "{flourish}"`, 1, true) ~= nil,
				`{pet}'s flourish {flourish} is drawn by PetController`
			)
		end
	end
	for _, item in Seasons.Items do
		local particles = item.Trail and item.Trail.Particles
		if particles then
			expectTrue(
				string.find(cosmeticSource, `kind == "{particles}"`, 1, true) ~= nil,
				`{item.Id}'s {particles} trail is built by CosmeticService`
			)
		end
	end
end)

return nil

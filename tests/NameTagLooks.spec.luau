-- The crate seasons on the name tag (owner: "Hollow night comes first ... I want it to look insane."):
-- THE HARVESTER carries its own look all the way to the name tag (Shared/Seasons -> Shared/Cosmetics
-- -> Shared/NameTag), and the frames for crates opened and a season finished come in the right
-- order (Logic/PlateFrames), none below 10 crates, the season's own the best.
local fs = require("@lune/fs")

local TestKit = require("./TestKit")
local CrateLogic = require("../src/shared/Logic/CrateLogic")
local PlateFrames = require("../src/shared/Logic/PlateFrames")
local Seasons = require("../src/shared/Seasons")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

test("THE HARVESTER has its look, and the catalog and the name tag pass it on", function()
	local title = Seasons.ItemById.Title_Harvester
	expectEqual(title.Look, "Harvester")
	expectEqual(title.Slot, "Title")
	expectEqual(Seasons.CurrentSeason().Title, "Title_Harvester")
	-- No other item has a look (it's the 1-in-500 title's alone).
	for _, item in Seasons.Items do
		if item.Id ~= "Title_Harvester" then
			expectEqual(item.Look, nil, item.Id)
		end
	end
	local cosmetics = fs.readFile("src/shared/Cosmetics.luau")
	expectTrue(string.find(cosmetics, "Look = entry.Look", 1, true) ~= nil, "Cosmetics copies the look")
	local nameTag = fs.readFile("src/shared/NameTag.luau")
	expectTrue(string.find(nameTag, 'title.Look == "Harvester"', 1, true) ~= nil, "NameTag draws it")
	expectTrue(string.find(nameTag, "Enum.Font.GrenzeGotisch", 1, true) ~= nil, "in blackletter")
	-- (The fonts draw these as blanks: the moons are images or drawn discs, never characters.)
	for _, glyph in { "☾", "☽", "★", "☆", "✦", "◐" } do
		expectTrue(not string.find(nameTag, glyph, 1, true), `no {glyph} on the tag`)
	end
end)

test("Frames: none below 10 crates, then bronze to harvest moon, a finished season best", function()
	expectEqual(PlateFrames.Milestones, CrateLogic.Milestones)
	expectEqual(PlateFrames.For(0, nil), nil)
	expectEqual(PlateFrames.For(nil, nil), nil)
	expectEqual(PlateFrames.For(9, nil), nil)
	local kinds = {}
	for _, opened in { 10, 49, 50, 100, 250, 499, 500, 9999 } do
		local frame = PlateFrames.For(CrateLogic.FrameFor(opened), nil) :: PlateFrames.Frame
		table.insert(kinds, frame.Kind)
	end
	expectEqual(kinds, { "Bronze", "Bronze", "Silver", "Gold", "Ember", "Ember", "HarvestMoon", "HarvestMoon" })
	-- Rarer frames are never thinner, and only the best ones move.
	local last = 0
	for _, mark in PlateFrames.Milestones do
		local frame = PlateFrames.For(mark, nil) :: PlateFrames.Frame
		expectTrue(frame.Thickness >= last, frame.Kind)
		last = frame.Thickness
		expectTrue(#frame.Colors >= 2, `{frame.Kind} has a rim`)
		expectTrue(frame.Backing > 0 and frame.Backing < 1, `{frame.Kind}'s fill`)
		expectEqual(frame.Shimmer ~= nil, mark == 500, `{frame.Kind} moves`)
	end
	local season = Seasons.CurrentSeason()
	local complete = PlateFrames.For(0, season.Colors) :: PlateFrames.Frame
	expectEqual(complete.Kind, "Complete")
	expectEqual(complete.Ends, "Leaf")
	expectEqual(complete.Colors[1], season.Colors.Gold)
	expectEqual((PlateFrames.For(500, season.Colors) :: PlateFrames.Frame).Kind, "Complete")
end)

test("Tier colours: the same every season, the title's the season's own", function()
	local season = Seasons.CurrentSeason()
	expectEqual(Seasons.TierColor("Title", season), season.Colors.Title)
	expectEqual(Seasons.TierColor("Pet"), Seasons.TierColors.Pet)
	expectEqual(Seasons.TierColor("Coins"), Seasons.TierColors.Coins)
	expectEqual(Seasons.TierColor("Nope"), Seasons.TierColors.Coins)
	for _, tier in { "Pet", "Hat", "Effect", "Coins" } do
		expectEqual(#Seasons.TierColors[tier], 3, tier)
	end
end)

return nil

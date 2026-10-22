-- Checks the marks that stand in for colours (owner: "I couldnt tell what color I was on prime cut."):
-- every set tells its teams, inks and orbs apart without colour, and uses only glyphs the game's fonts
-- draw. A real server measured FredokaOne and Builder Sans: ★ ✕ ✚ ☾ ◐ ✦ ☆ ☰ come out blank.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local TestKit = require("./TestKit")

local test, expectTrue = TestKit.test, TestKit.expectTrue

local function load(path: string, name: string)
	return luau.load(fs.readFile(path), {
		debugName = name,
		environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, CFrame = roblox.CFrame },
	})()
end

local Teams = load("src/shared/Teams.luau", "Teams")
local StampGrid = load("src/shared/Logic/StampGrid.luau", "StampGrid")
local Struggle = load("src/shared/Logic/Struggle.luau", "Struggle")

local BLANK = { "★", "✕", "✚", "☾", "◐", "✦", "☆", "☰" }

local function checkSet(label: string, marks: { [any]: string })
	local seen = {}
	for key, mark in marks do
		expectTrue(type(mark) == "string" and mark ~= "", `{label} {key} has a mark`)
		expectTrue(seen[mark] == nil, `{label} {key} shares {mark} with {seen[mark]}`)
		seen[mark] = key
		for _, blank in BLANK do
			expectTrue(string.find(mark, blank, 1, true) == nil, `{label} {key}'s {mark} doesn't draw`)
		end
	end
end

test("Marks: colour teams each wear their own shape", function()
	checkSet("Teams.Shapes", Teams.Shapes)
end)

test("Marks: Stamp Out's inks each have their own symbol", function()
	local symbols = {}
	for _, ink in StampGrid.INKS do
		symbols[ink.Name] = ink.Symbol
	end
	checkSet("StampGrid.INKS", symbols)
end)

test("Marks: Struggle's orbs each have their own glyph", function()
	local glyphs = {}
	for _, slot in Struggle.SLOTS do
		glyphs[slot.Name] = slot.Glyph
	end
	checkSet("Struggle.SLOTS", glyphs)
end)

return nil

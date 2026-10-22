-- Checks the words that tell players their team (src/shared/Teams: Label, YouAre; owner: "I couldnt
-- tell what color I was on prime cut."): every team and role a mode can put someone on has them, with
-- its mark, so the rules card's tab and the HUD never go by colour alone.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local TestKit = require("./TestKit")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

-- Teams has its colors as Color3s: Lune's stand-in for them.
local Teams = luau.load(fs.readFile("src/shared/Teams.luau"), {
	debugName = "Teams",
	environment = { Color3 = roblox.Color3 },
})()

test("Teams.YouAre: colour teams say the team, with its shape", function()
	expectEqual(Teams.YouAre("Red"), "YOU'RE ON ★ RED")
	expectEqual(Teams.YouAre("Blue"), "YOU'RE ON ● BLUE")
	expectEqual(Teams.YouAre("Green"), "YOU'RE ON ▲ GREEN")
	expectEqual(Teams.YouAre("Yellow"), "YOU'RE ON ◆ YELLOW")
end)

test("Teams.YouAre: versus roles say what you are, with its icon", function()
	expectEqual(Teams.YouAre("Archers"), "YOU'RE AN 🏹 ARCHER")
	expectEqual(Teams.YouAre("Runners"), "YOU'RE A 🏃 RUNNER")
	expectEqual(Teams.YouAre("SandKings"), "YOU'RE A 👑 SAND KING")
	expectEqual(Teams.YouAre("Divers"), "YOU'RE A 💎 DIVER")
	expectEqual(Teams.YouAre("Sharks"), "YOU'RE A 🦈 SHARK")
	expectEqual(Teams.YouAre("Swimmers"), "YOU'RE A 🏊 SWIMMER")
end)

test("Teams.YouAre: nothing without a team", function()
	expectEqual(Teams.YouAre(""), nil)
	expectEqual(Teams.YouAre(nil), nil)
	expectEqual(Teams.YouAre("Nobody"), nil)
end)

test("Teams: every team with a colour has its words and its mark", function()
	for name in Teams.Colors do
		local callout = Teams.YouAre(name)
		expectTrue(callout ~= nil, `{name} has no callout`)
		local mark = Teams.Shapes[name] or Teams.Icons[name]
		expectTrue(mark ~= nil, `{name} has no shape or icon`)
		expectTrue(string.find(callout or "", mark :: string, 1, true) ~= nil, `{name}'s callout has no mark`)
		expectTrue(string.find(Teams.Label(name), mark :: string, 1, true) == 1, `{name}'s label starts with its mark`)
	end
	expectEqual(Teams.Label("SandKings"), "👑 SAND KINGS")
	expectEqual(Teams.Label("Red"), "★ RED")
end)

return nil

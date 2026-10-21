-- Checks Skate Escape's collapse rule (src/shared/Logic/SkateCourse.Caught): the crumbling bridge takes
-- a rider once it's past their front wheels as their own screen draws them, and when it reaches the
-- finish line it takes everyone short of the line on their own screen, so a rider who crossed there
-- in the last instant still finishes (owner: "it just has to work").
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local TestKit = require("./TestKit")

local test, expectTrue, expectEqual = TestKit.test, TestKit.expectTrue, TestKit.expectEqual

-- SkateCourse uses Roblox types (lane colors, stance frames): Lune's stand-ins for them.
local SkateCourse = luau.load(fs.readFile("src/shared/Logic/SkateCourse.luau"), {
	debugName = "SkateCourse",
	environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Enum = roblox.Enum },
})()

local LENGTH = SkateCourse.Length

test("SkateCourse.Caught: on the way, once the front is past the front wheels on the rider's screen", function()
	local grace = SkateCourse.EdgeGrace
	expectTrue(not SkateCourse.Caught(500 + grace - 0.1, 500, 0), "a front wheel still on the planks")
	expectTrue(SkateCourse.Caught(500 + grace + 0.1, 500, 0), "no wheel left on the planks")
	expectTrue(not SkateCourse.Caught(500 + grace + 0.1, 500, 3), "their screen draws them 3 studs further on")
end)

test("SkateCourse.Caught: at the finish line, everyone short of it on their own screen", function()
	local collapse = SkateCourse.NewCollapse(0)
	expectEqual(SkateCourse.CollapseAt(collapse, collapse.T1), LENGTH, "the collapse reaches the line at T1")
	expectTrue(not SkateCourse.Caught(LENGTH, LENGTH - 2, 2.5), "2 studs short here, across on their screen")
	expectTrue(SkateCourse.Caught(LENGTH, LENGTH - 2, 1.5), "still short of the line on their screen")
	expectTrue(SkateCourse.Caught(LENGTH, LENGTH - 0.01, 0), "a stopped rider short of the line falls")
	expectTrue(not SkateCourse.Caught(LENGTH, LENGTH, 0), "on the line")
end)

return nil

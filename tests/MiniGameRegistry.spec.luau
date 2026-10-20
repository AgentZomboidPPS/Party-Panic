-- Checks that every mini-game module has a definition (and vice versa) and that each module is
-- built on Kit/MiniGame with a matching Id - the same rules the in-game registry enforces.
local fs = require("@lune/fs")

local TestKit = require("./TestKit")

local test, expectTrue = TestKit.test, TestKit.expectTrue

local definitions = fs.readFile("src/shared/GameDefinitions.luau")
local defined = {}
for id in string.gmatch(definitions, '\n\t\tId = "(%w+)"') do
	defined[id] = true
end

local modules = {}
for _, file in fs.readDir("src/server/MiniGames") do
	local id = string.match(file, "^(%w+)%.luau$")
	if id and id ~= "init" then
		modules[id] = fs.readFile(`src/server/MiniGames/{file}`)
	end
end

test("every mini-game module has a GameDefinitions entry and uses MiniGame.Define", function()
	for id, source in modules do
		expectTrue(defined[id], `{id}.luau has no entry in GameDefinitions`)
		expectTrue(
			string.find(source, `MiniGame.Define("{id}"`, 1, true) ~= nil,
			`{id}.luau must call MiniGame.Define("{id}")`
		)
	end
end)

test("every GameDefinitions entry has a module", function()
	for id in defined do
		expectTrue(modules[id] ~= nil, `GameDefinitions has {id} but src/server/MiniGames/{id}.luau is missing`)
	end
end)

test("the scaffold template has every placeholder the tool fills in", function()
	local template = fs.readFile("tools/templates/MiniGame.luau.template")
	for _, key in { "Id", "Name", "Category", "Duration", "Results", "RespawnMode", "EndWhenOneLeft" } do
		local placeholder = "{{" .. key .. "}}"
		expectTrue(string.find(template, placeholder, 1, true) ~= nil, "template is missing " .. placeholder)
	end
end)

return nil

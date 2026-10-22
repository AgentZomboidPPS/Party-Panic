-- No seats (owner: "Also theres times where I will sit on invisible shit in game. NO mini game should
-- require you to sit."): nothing in the game's code makes a Seat or sits anyone down, and both
-- places a character is simulated turn its Seated state off (Shared/NoSitting).
local fs = require("@lune/fs")

local TestKit = require("./TestKit")

local test, expectTrue = TestKit.test, TestKit.expectTrue

local sources: { [string]: string } = {}
local function walk(dir: string)
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			walk(path)
		elseif string.match(name, "%.luau?$") then
			sources[path] = fs.readFile(path)
		end
	end
end
walk("src")

local FORBIDDEN = {
	{ 'Instance%.new%(%s*"Seat"%s*%)', 'makes a Seat (Instance.new("Seat"))' },
	{ 'Instance%.new%(%s*"VehicleSeat"%s*%)', "makes a VehicleSeat" },
	{ ":Sit%(", "sits someone down (Seat:Sit)" },
	{ "pcall%([%w_%.]*%.Sit%s*,", "sits someone down (pcall(seat.Sit, ...))" },
	{ "%.Sit%s*=%s*true", "sets Humanoid.Sit" },
	{ "HumanoidStateType%.Seated%s*,%s*true", "turns the Seated state back on" },
}

test("nothing in src makes a seat or sits anyone down", function()
	for path, source in sources do
		local number = 0
		for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
			number += 1
			if string.match(line, "^%s*%-%-") then
				continue -- (a comment)
			end
			for _, rule in FORBIDDEN do
				expectTrue(string.find(line, rule[1]) == nil, `{path}:{number} {rule[2]}`)
			end
		end
	end
end)

test("every character's Seated state is turned off where it's simulated", function()
	local guard = sources["src/shared/NoSitting.luau"]
	expectTrue(guard ~= nil, "src/shared/NoSitting.luau is missing")
	expectTrue(
		guard ~= nil and string.find(guard, "SetStateEnabled(Enum.HumanoidStateType.Seated, false)", 1, true) ~= nil,
		"NoSitting must turn the Seated state off"
	)
	expectTrue(
		guard ~= nil and string.find(guard, '"SeatWeld"', 1, true) ~= nil,
		"NoSitting must break the weld a seat holds a character with"
	)
	for _, path in { "src/client/Controllers/MovementController.luau", "src/server/Services/NoSitService.luau" } do
		local source = sources[path]
		expectTrue(
			source ~= nil and string.find(source, "NoSitting.Guard", 1, true) ~= nil,
			`{path} must call NoSitting.Guard`
		)
	end
	local init = sources["src/server/init.server.luau"]
	expectTrue(
		init ~= nil and string.find(init, '"NoSitService"', 1, true) ~= nil,
		"the server must start NoSitService"
	)
end)

return nil

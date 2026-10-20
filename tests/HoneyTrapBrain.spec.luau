-- Checks the take a counting bot goes for in Honey Trap (src/server/MiniGames/Bots/HoneyTrap.luau).
local TestKit = require("./TestKit")
local Brain = require("../src/server/MiniGames/Bots/HoneyTrap")

local test, expectEqual = TestKit.test, TestKit.expectEqual

test("with two players a bot plays Nim: it leaves a multiple of 3 fruit before the honeycomb", function()
	for fruit = 1, 12 do
		local expected = ({ [0] = nil, [1] = 1, [2] = 2 })[fruit % 3]
		expectEqual(Brain.BestTake(fruit, 2), expected, `{fruit} fruit`)
	end
end)

test("a bot never takes 2 when that would take the honeycomb", function()
	for players = 2, 12 do
		expectEqual(Brain.BestTake(1, players), 1, `{players} players`)
	end
end)

test("with the honeycomb at the bottom it makes no difference", function()
	for players = 2, 12 do
		expectEqual(Brain.BestTake(0, players), nil, `{players} players`)
	end
end)

test("with more players a bot looks around the circle", function()
	-- Three players, four fruit: taking 1 (Nim's answer) brings the honeycomb back around to it.
	expectEqual(Brain.BestTake(4, 3), 2)
	expectEqual(Brain.BestTake(3, 3), 2)
	-- A full round: take both fruit and the next player gets the honeycomb.
	expectEqual(Brain.BestTake(2, 12), 2)
	expectEqual(Brain.BestTake(3, 12), nil)
end)

return nil

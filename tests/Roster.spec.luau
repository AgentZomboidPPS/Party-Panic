local TestKit = require("./TestKit")
local Roster = require("../src/shared/Logic/Roster")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

-- Stand-ins for players and bots: a name and what RoundManager would say about them.
type Who = { Name: string, IsBot: boolean, Ready: boolean, SittingOut: boolean }

local function person(name: string, sittingOut: boolean?, ready: boolean?): Who
	return { Name = name, IsBot = false, Ready = ready ~= false, SittingOut = sittingOut == true }
end

local function bot(name: string, inWorld: boolean?): Who
	return { Name = name, IsBot = true, Ready = inWorld ~= false, SittingOut = false }
end

local function lineup(everyone: { Who })
	return Roster.Build(everyone, function(who: Who): Roster.Candidate
		return { IsBot = who.IsBot, Ready = who.Ready, SittingOut = who.SittingOut }
	end)
end

local function names(list: { Who }): { string }
	local result = {}
	for _, who in list do
		table.insert(result, who.Name)
	end
	return result
end

test("Roster.Build: people play first, then the bots that are in the world", function()
	local result = lineup({ bot("Mochi"), person("Ann"), bot("Pip", false), person("Bo"), bot("Bloop") })
	expectEqual(names(result.Participants), { "Ann", "Bo", "Mochi", "Bloop" })
	expectEqual(result.Here, 2)
	expectEqual(result.Playing, 2)
	expectEqual(result.SittingOut, 0)
	expectEqual(Roster.Blocker(result, 2), "")
end)

test("Roster.Build: people sitting out aren't in the round, and the bots still fill in", function()
	local result = lineup({ person("Ann"), person("Bo", true), person("Cy"), bot("Mochi"), bot("Pip") })
	expectEqual(names(result.Participants), { "Ann", "Cy", "Mochi", "Pip" })
	expectEqual(result.Here, 3)
	expectEqual(result.Playing, 2)
	expectEqual(result.SittingOut, 1)
end)

test("Roster.Build: when everyone is sitting out there's no bots-only round", function()
	local result = lineup({ person("Ann", true), bot("Mochi"), person("Bo", true), bot("Pip") })
	expectEqual(#result.Participants, 0)
	expectEqual(result.Playing, 0)
	expectEqual(result.SittingOut, 2)
	local reason, needed = Roster.Blocker(result, 2)
	expectEqual(reason, "Break")
	expectEqual(needed, 0)
	expectEqual(Roster.WaitingMessage(reason, needed), "Everyone's taking a break!")
end)

test("Roster.Blocker: people sitting out don't count towards MinPlayers", function()
	-- No bots (turned off): two people, one sitting out, and the game needs two players.
	local result = lineup({ person("Ann"), person("Bo", true) })
	local reason, needed = Roster.Blocker(result, 2)
	expectEqual(reason, "TooFew")
	expectEqual(needed, 1)
	expectEqual(Roster.WaitingMessage(reason, needed), "Waiting for 1 more player...")
	-- Bo jumps back in: the round can start.
	expectEqual(Roster.Blocker(lineup({ person("Ann"), person("Bo") }), 2), "")
end)

test("Roster.Blocker: bots count towards MinPlayers once someone plays", function()
	expectEqual(Roster.Blocker(lineup({ person("Ann"), bot("Mochi") }), 2), "")
	expectEqual(Roster.Blocker(lineup({ person("Ann", true), person("Bo"), bot("Mochi") }), 2), "")
end)

test("Roster.Blocker: an empty server waits for players, not for a break to end", function()
	local reason, needed = Roster.Blocker(lineup({ bot("Mochi"), bot("Pip") }), 2)
	expectEqual(reason, "TooFew")
	expectEqual(needed, 2)
	expectEqual(Roster.WaitingMessage(reason, needed), "Waiting for 2 more players...")
end)

test("Roster.Build: people whose profile is still loading are neither playing nor sitting out", function()
	local result = lineup({ person("Ann", false, false), person("Bo", true, false), bot("Mochi") })
	expectEqual(#result.Participants, 0)
	expectEqual(result.Here, 0)
	expectEqual(result.SittingOut, 0)
	expectEqual(Roster.Blocker(result, 1), "TooFew") -- not "Break": they just haven't arrived yet
end)

test("Roster.Blocker: one person playing is enough in Studio (MinPlayersInStudio = 1)", function()
	local result = lineup({ person("Ann") })
	expectEqual(Roster.Blocker(result, 1), "")
	expectTrue(Roster.Blocker(lineup({ person("Ann", true) }), 1) == "Break", "sitting out alone pauses rounds")
end)

return nil

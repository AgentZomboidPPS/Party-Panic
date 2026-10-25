-- The analytics funnels (owner: "Can you make me some sick ass funnels to track where players leave/
-- complete stuff"; Shared/Logic/Funnels): the rounds-finished ladder, what leaving is called, and
-- the step names pinned (Roblox keys a funnel's steps by number: renaming one mixes up its chart, so
-- new steps only ever go on the end).
local TestKit = require("./TestKit")
local Funnels = require("../src/shared/Logic/Funnels")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

test("Funnels: the step names never change (new steps go on the end)", function()
	local ladder = {
		"Joined",
		"Played a round",
		"Finished a round",
		"Finished 3 rounds",
		"Finished 5 rounds",
		"Finished 10 rounds",
		"Finished 20 rounds",
	}
	expectEqual(Funnels.Onboarding, ladder)
	expectEqual(Funnels.Session, { Name = "Session", Steps = ladder })
	expectEqual(Funnels.Round, {
		Name = "Round",
		Steps = { "In the round", "GO", "Saw the results", "Stayed for the next round" },
	})
	expectEqual(Funnels.Shop, { Name = "Shop", Steps = { "Opened the shop", "Picked an item", "Bought it" } })
	expectEqual(
		Funnels.GoldPass,
		{ Name = "GoldPass", Steps = { "Saw the offer", "Pressed GET GOLD PASS", "Bought it" } }
	)
	expectEqual(Funnels.Crates, {
		Name = "Crates",
		Steps = { "First crate", "First open", "Opened 10", "Opened 50", "Bought keys" },
	})
	expectEqual(Funnels.CrateStep(1), 2)
	expectEqual(Funnels.CrateStep(10), 3)
	expectEqual(Funnels.CrateStep(50), 4)
	expectEqual(Funnels.CrateStep(2), nil)
end)

test("Funnels: finishing a round count reaches its ladder step", function()
	local reached = {}
	for rounds = 0, 25 do
		local step = Funnels.FinishedStep(rounds)
		if step then
			table.insert(reached, `{rounds}:{step}`)
		end
	end
	expectEqual(reached, { "1:3", "3:4", "5:5", "10:6", "20:7" })
	for _, rounds in Funnels.RoundMarks do
		local step = Funnels.FinishedStep(rounds) :: number
		expectTrue(string.find(Funnels.Session.Steps[step], "Finished", 1, true) ~= nil, `step {step}`)
	end
end)

test("Funnels: what someone was doing when they left", function()
	expectEqual(Funnels.LeftWhere("Preparing", true, false), "Round: rules card")
	expectEqual(Funnels.LeftWhere("InRound", true, false), "Round: playing")
	expectEqual(Funnels.LeftWhere("Results", true, false), "Round: results")
	expectEqual(Funnels.LeftWhere("InRound", false, true), "Sitting out")
	expectEqual(Funnels.LeftWhere("InRound", false, false), "Lobby: a round on without them")
	expectEqual(Funnels.LeftWhere("Voting", false, false), "Lobby: vote")
	expectEqual(Funnels.LeftWhere("Waiting", false, false), "Lobby: waiting for players")
	expectEqual(Funnels.LeftWhere("Intermission", false, false), "Lobby")
	expectEqual(Funnels.LeftWhere(nil, false, false), "Lobby")
end)

test("Funnels: the screens can only send their own steps", function()
	local words = {}
	for word in Funnels.ClientSteps do
		table.insert(words, word)
	end
	table.sort(words)
	expectEqual(words, { "Device", "GoldSeen", "ShopOpen", "ShopPick" })
	expectEqual(Funnels.DeviceKinds, { Phone = true, Tablet = true, PC = true, Console = true })
end)

-- (owner: "What information should we collect to gage if players are having fun and staying?", then
-- "lets do 1-7.")
test("Funnels: the fields that tell fun and staying apart", function()
	expectEqual(
		{ Funnels.PeopleBucket(0), Funnels.PeopleBucket(1), Funnels.PeopleBucket(2), Funnels.PeopleBucket(5) },
		{ "1 person", "1 person", "2 people", "3-5 people" }
	)
	expectEqual(Funnels.PeopleBucket(6), "6+ people")
	expectEqual(
		{ Funnels.Social(true, true), Funnels.Social(false, true), Funnels.Social(false, false) },
		{ "Party", "Friends", "Solo" }
	)
	expectEqual(Funnels.BestSocial("Solo", "Friends"), "Friends")
	expectEqual(Funnels.BestSocial("Party", "Friends"), "Party")
	expectEqual(Funnels.BestSocial(nil, nil), "Solo")
	expectEqual(Funnels.StreakLabel(0, 0), "No rounds yet")
	expectEqual(Funnels.StreakLabel(4, 0), "Won the last round")
	expectEqual(Funnels.StreakLabel(4, 2), "Lost the last 2")
	expectEqual(Funnels.StreakLabel(9, 4), "Lost the last 3-4")
	expectEqual(Funnels.StreakLabel(9, 7), "Lost the last 5+")
	for name, fields in Funnels.FIELDS do
		expectTrue(#fields <= 3, `{name}: Roblox takes three custom fields`)
	end
	-- Roblox's economy kinds (Enum.AnalyticsEconomyTransactionType's names).
	local kinds = { Gameplay = true, TimedReward = true, IAP = true, Shop = true, Onboarding = true }
	for reason, kind in Funnels.CoinKinds do
		expectTrue(kinds[kind] == true, `{reason} goes to {kind}`)
	end
end)

test("Funnels: a new player's first visit (its step names never change; new ones go on the end)", function()
	expectEqual(Funnels.FirstVisit, {
		Name = "FirstVisit",
		Steps = {
			"Joined",
			"First round: rules card",
			"First round: GO",
			"First round: results",
			"Second round",
			"Finished 3 rounds",
			"Opened a crate",
			"Came back another day",
		},
	})
	for _, name in { "FirstVisit", "FirstGame", "LeftDuringGame", "LastGame", "VisitEnd" } do
		expectTrue(Funnels.FIELDS[name] ~= nil, `{name} names its fields`)
	end
end)

test("Funnels: where someone placed, the others on the server, rounds and crates", function()
	expectEqual(Funnels.Placed(1, 8, false, true), "1st")
	expectEqual(Funnels.Placed(2, 8, false, false), "2nd")
	expectEqual(Funnels.Placed(3, 8, false, false), "3rd")
	expectEqual(Funnels.Placed(4, 8, false, false), "Top half")
	expectEqual(Funnels.Placed(5, 8, false, false), "Bottom half")
	expectEqual(Funnels.Placed(1, 8, true, true), "Team won")
	expectEqual(Funnels.Placed(6, 8, true, false), "Team lost")
	expectEqual(Funnels.OthersBucket(0), "Nobody else")
	expectEqual(Funnels.OthersBucket(1), "1 other")
	expectEqual(Funnels.OthersBucket(3), "2-3 others")
	expectEqual(Funnels.OthersBucket(7), "4-7 others")
	expectEqual(Funnels.OthersBucket(11), "8+ others")
	expectEqual(Funnels.RoundsBucket(0), "0 rounds")
	expectEqual(Funnels.RoundsBucket(1), "1 round")
	expectEqual(Funnels.RoundsBucket(3), "2-3 rounds")
	expectEqual(Funnels.RoundsBucket(9), "4-9 rounds")
	expectEqual(Funnels.RoundsBucket(40), "10+ rounds")
	expectEqual(Funnels.CrateLabel(2, 0), "Opened a crate")
	expectEqual(Funnels.CrateLabel(0, 3), "Had one, didn't open")
	expectEqual(Funnels.CrateLabel(0, 0), "No crate")
	expectEqual(Funnels.InGameDoing("Preparing", true), "Rules card")
	expectEqual(Funnels.InGameDoing("InRound", true), "Playing")
	expectEqual(Funnels.InGameDoing("InRound", false), "Out, watching")
	expectEqual(Funnels.InGameDoing("Results", true), "Results")
end)

return nil

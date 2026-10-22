local TestKit = require("./TestKit")
local PartyCup = require("../src/shared/Logic/PartyCup")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

-- A round's results: { name, place } for people, { name, place, true } for bots. UserIds come from
-- the names so the same person keeps the same id from round to round.
local ids: { [string]: number } = {}
local nextId = 0
local function idOf(name: string, isBot: boolean): number
	if not ids[name] then
		nextId += 1
		ids[name] = if isBot then -nextId else nextId
	end
	return ids[name]
end

local function round(places: { { any } }): { PartyCup.Result }
	local results = {}
	for _, row in places do
		local name, place, isBot = row[1], row[2], row[3] == true
		table.insert(results, { UserId = idOf(name, isBot), Name = name, IsBot = isBot, Place = place })
	end
	return results
end

-- "name place points" for each standing, best first.
local function table_(cup: PartyCup.Cup): { string }
	local lines = {}
	for _, standing in PartyCup.Standings(cup) do
		table.insert(lines, `{standing.Name} {standing.Place} {standing.Points}`)
	end
	return lines
end

test("PartyCup.PointsFor: 10, 8, 6, 5, 4, 3, 2, then 1 for every place after (everyone scores)", function()
	local points = {}
	for place = 1, 12 do
		table.insert(points, PartyCup.PointsFor(place))
	end
	expectEqual(points, { 10, 8, 6, 5, 4, 3, 2, 1, 1, 1, 1, 1 })
	expectEqual(PartyCup.PointsFor(30), 1)
end)

test("PartyCup.AddRound: a round adds its places' points and counts towards the 5", function()
	local cup = PartyCup.New(1)
	expectTrue(PartyCup.AddRound(cup, round({ { "Ann", 1 }, { "Bo", 2 }, { "Mochi", 3, true } })))
	expectEqual(cup.Played, 1)
	expectEqual(PartyCup.NextRound(cup), 2)
	expectEqual(table_(cup), { "Ann 1 10", "Bo 2 8", "Mochi 3 6" })
	local ann = cup.Entries[idOf("Ann", false)]
	expectEqual({ ann.Wins, ann.Rounds, ann.Last, ann.Gain }, { 1, 1, 1, 10 })
end)

test("PartyCup.AddRound: ties share - a team game's winning team all get 1st place's points", function()
	local cup = PartyCup.New(1)
	-- Two teams of three (Placement gives a team one place: 1, 1, 1, 4, 4, 4).
	PartyCup.AddRound(
		cup,
		round({ { "Ann", 1 }, { "Bo", 1 }, { "Pip", 1, true }, { "Cy", 4 }, { "Dee", 4 }, { "Taffy", 4, true } })
	)
	expectEqual(table_(cup), { "Ann 1 10", "Bo 1 10", "Pip 1 10", "Cy 4 5", "Dee 4 5", "Taffy 4 5" })
end)

test("PartyCup.AddRound: a round with no person in it (they all left) doesn't count", function()
	local cup = PartyCup.New(1)
	expectEqual(PartyCup.AddRound(cup, round({ { "Mochi", 1, true }, { "Pip", 2, true } })), false)
	expectEqual(PartyCup.AddRound(cup, {}), false)
	expectEqual(cup.Played, 0)
	expectEqual(next(cup.Entries), nil)
end)

test("PartyCup.AddRound: someone who joins mid-cup starts at 0", function()
	local cup = PartyCup.New(1)
	PartyCup.AddRound(cup, round({ { "Ann", 1 }, { "Bo", 2 } }))
	PartyCup.AddRound(cup, round({ { "Ann", 2 }, { "Bo", 3 }, { "Newbie", 1 } }))
	expectEqual(table_(cup), { "Ann 1 18", "Bo 2 14", "Newbie 3 10" })
	expectEqual(cup.Entries[idOf("Newbie", false)].Rounds, 1)
end)

test("PartyCup.AddRound: sitting a round out keeps your points (and no latest place)", function()
	local cup = PartyCup.New(1)
	PartyCup.AddRound(cup, round({ { "Ann", 1 }, { "Bo", 2 } }))
	PartyCup.AddRound(cup, round({ { "Bo", 1 } }))
	local ann = cup.Entries[idOf("Ann", false)]
	expectEqual({ ann.Points, ann.Last, ann.Gain }, { 10, nil, 0 })
	expectEqual(table_(cup), { "Bo 1 18", "Ann 2 10" })
end)

test("PartyCup.Standings: level on points, more round wins go first, then the latest round's place", function()
	local cup = PartyCup.New(1)
	-- Ann: 10 + 2 = 12 with a win; Bo: 6 + 6 = 12, no win.
	PartyCup.AddRound(cup, round({ { "Ann", 1 }, { "Bo", 3 }, { "Cy", 2 }, { "Dee", 3 } }))
	PartyCup.AddRound(cup, round({ { "Ann", 7 }, { "Bo", 3 }, { "Cy", 4 }, { "Dee", 3 } }))
	-- Cy: 8 + 5 = 13. Dee: 6 + 6 = 12, no win, level with Bo on everything: they share 3rd.
	expectEqual(table_(cup), { "Cy 1 13", "Ann 2 12", "Bo 3 12", "Dee 3 12" })
	-- Level on points and wins: the better place in the latest round goes first.
	local other = PartyCup.New(2)
	PartyCup.AddRound(other, round({ { "Eve", 2 }, { "Fay", 4 } }))
	PartyCup.AddRound(other, round({ { "Eve", 4 }, { "Fay", 2 } }))
	expectEqual(table_(other), { "Fay 1 13", "Eve 2 13" })
end)

test("PartyCup: a cup is over after 5 counted rounds, and takes no more", function()
	local cup = PartyCup.New(1)
	for _ = 1, 5 do
		expectTrue(PartyCup.AddRound(cup, round({ { "Ann", 1 }, { "Mochi", 2, true } })))
	end
	expectTrue(PartyCup.IsOver(cup))
	expectEqual(PartyCup.NextRound(cup), 5)
	expectEqual(PartyCup.AddRound(cup, round({ { "Ann", 1 } })), false)
	expectEqual(cup.Entries[idOf("Ann", false)].Points, 50)
end)

test("PartyCup.Remove/Restore: a leaver drops off the standings and gets their points back on return", function()
	local cup = PartyCup.New(1)
	PartyCup.AddRound(cup, round({ { "Ann", 1 }, { "Bo", 2 } }))
	local left = PartyCup.Remove(cup, idOf("Ann", false))
	expectTrue(left ~= nil)
	expectEqual(table_(cup), { "Bo 1 8" })
	PartyCup.AddRound(cup, round({ { "Bo", 1 } }))
	PartyCup.Restore(cup, left :: PartyCup.Entry)
	expectEqual(table_(cup), { "Bo 1 18", "Ann 2 10" })
	-- They missed the latest round: no latest place for the tie-break, and no gain to show.
	local ann = cup.Entries[idOf("Ann", false)]
	expectEqual({ ann.Last, ann.Gain }, { nil, 0 })
	expectEqual(PartyCup.Remove(cup, 999), nil)
end)

test("PartyCup.Podium/Payouts: the top three places win 5, 3, 2 coins; bots stand on it but win nothing", function()
	local cup = PartyCup.New(1)
	PartyCup.AddRound(cup, round({ { "Mochi", 1, true }, { "Ann", 2 }, { "Bo", 3 }, { "Cy", 4 } }))
	local standings = PartyCup.Standings(cup)
	expectEqual(#PartyCup.Podium(standings), 3)
	local payouts = PartyCup.Payouts(standings)
	expectEqual(payouts, {
		{ UserId = idOf("Ann", false), Place = 2, Coins = 3 },
		{ UserId = idOf("Bo", false), Place = 3, Coins = 2 },
	})
	-- A bot champion: nobody is crowned.
	expectEqual(#PartyCup.Champions(standings), 0)
end)

test("PartyCup.Podium/Payouts: people level on everything share the place and its prize", function()
	local cup = PartyCup.New(1)
	PartyCup.AddRound(cup, round({ { "Ann", 1 }, { "Bo", 1 }, { "Cy", 3 }, { "Dee", 4 } }))
	local standings = PartyCup.Standings(cup)
	local coins = {}
	for _, payout in PartyCup.Payouts(standings) do
		table.insert(coins, payout.Coins)
	end
	expectEqual(coins, { 5, 5, 2 })
	expectEqual(#PartyCup.Champions(standings), 2)
	expectEqual(PartyCup.PrizeFor(4), 0)
end)

test("PartyCup.Rows: the attribute's rows, capped, with what the screens draw", function()
	local cup = PartyCup.New(1)
	local places = {}
	for index = 1, 14 do
		table.insert(places, { `P{index}`, index, index % 2 == 0 })
	end
	PartyCup.AddRound(cup, round(places))
	local rows = PartyCup.Rows(PartyCup.Standings(cup))
	expectEqual(#rows, PartyCup.Shown)
	expectEqual(rows[1], { UserId = idOf("P1", false), Name = "P1", Points = 10, IsBot = false, Place = 1, Gain = 10 })
	expectEqual(rows[2].IsBot, true)
	expectEqual(#PartyCup.Rows(PartyCup.Standings(cup), 3), 3)
end)

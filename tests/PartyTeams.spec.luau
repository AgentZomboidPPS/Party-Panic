-- Checks how parties are dealt into teams (src/shared/Logic/PartyTeams; owner: "The parties work in
-- the way that if you party with others for team games you are on the same team."): a party stays
-- on one team, team sizes stay within one, a party is split only when no deal keeps it whole (and
-- then as evenly as it can be), the deal stays random, and bots never group.
local TestKit = require("./TestKit")
local PartyTeams = require("../src/shared/Logic/PartyTeams")

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

-- Stand-ins: a name, whether it's a bot, and its party id (nil: on their own).
type Who = { Name: string, IsBot: boolean, Party: number? }

local function describe(who: Who): PartyTeams.Member
	return { IsBot = who.IsBot, Party = who.Party }
end

-- A lineup from a spec like { 2, 3, 0, 0, 0 } (a party of 2, one of 3, three people on their own)
-- plus `bots` bots.
local function lineup(spec: { number }, bots: number?): { Who }
	local people, party = {}, 0
	for _, size in spec do
		if size >= 2 then
			party += 1
			for member = 1, size do
				table.insert(people, { Name = `P{party}.{member}`, IsBot = false, Party = party })
			end
		else
			table.insert(people, { Name = `Solo{#people + 1}`, IsBot = false, Party = nil })
		end
	end
	for index = 1, bots or 0 do
		table.insert(people, { Name = `Bot{index}`, IsBot = true, Party = nil })
	end
	return people
end

local function picker(seed: number): PartyTeams.Pick
	local random = TestKit.seeded(seed)
	return random.index
end

-- Which team (index) each person is on.
local function teamOf(teams: { { Who } }): { [Who]: number }
	local map = {}
	for index, team in teams do
		for _, who in team do
			expectTrue(map[who] == nil, `{who.Name} is on two teams`)
			map[who] = index
		end
	end
	return map
end

local function sizes(teams: { { any } }): { number }
	local list = {}
	for _, team in teams do
		table.insert(list, #team)
	end
	table.sort(list)
	return list
end

-- The teams a party's members ended up on (sorted, each team once).
local function partyTeams(people: { Who }, map: { [Who]: number }, party: number): { number }
	local seen, list = {}, {}
	for _, who in people do
		if who.Party == party and not seen[map[who]] then
			seen[map[who]] = true
			table.insert(list, map[who])
		end
	end
	table.sort(list)
	return list
end

test("PartyTeams.Groups: each party together, everyone else and every bot on their own", function()
	local people = lineup({ 2, 0, 3 }, 2)
	people[#people].Party = 1 -- a bot with a party id (it can't have one): still on its own
	local groups = PartyTeams.Groups(people, describe)
	local shape = {}
	for _, group in groups do
		table.insert(shape, #group)
	end
	expectEqual(shape, { 2, 1, 3, 1, 1 })
	expectEqual(groups[1][1].Name, "P1.1")
	expectEqual(groups[5][1].Name, "Bot2")
	-- A party's only member in the round plays like anyone on their own.
	local alone = PartyTeams.Groups({ { Name = "Ann", IsBot = false, Party = 4 } }, describe)
	expectEqual(#alone, 1)
end)

test("PartyTeams.Deal: a party of 2 and one of 3 among 8 stay on one team each, every time", function()
	for seed = 1, 300 do
		local people = lineup({ 2, 3, 0, 0, 0 })
		local teams, split = PartyTeams.Deal(PartyTeams.Groups(people, describe), 3, picker(seed))
		local map = teamOf(teams)
		expectEqual(#teams, 3)
		expectEqual(sizes(teams), { 2, 3, 3 })
		expectEqual(#partyTeams(people, map, 1), 1, `seed {seed}: the party of 2 was split`)
		expectEqual(#partyTeams(people, map, 2), 1, `seed {seed}: the party of 3 was split`)
		expectEqual(#split, 0)
	end
end)

test("PartyTeams.Deal: sizes within one, everyone dealt once, parties whole where they fit", function()
	local random = TestKit.seeded(99)
	for round = 1, 400 do
		-- 2 to 12 in the round: parties of 2 to 4, people on their own, bots.
		local spec, total = {}, 0
		local wanted = 2 + random.index(11) - 1
		while total < wanted do
			local size = if random.float() < 0.4 then math.min(1 + random.index(4), wanted - total) else 1
			table.insert(spec, size)
			total += size
		end
		local bots = random.index(3) - 1
		local people = lineup(spec, math.min(bots, 12 - total))
		local teamCount = math.min(1 + random.index(4), #people)
		local teams, split = PartyTeams.Deal(PartyTeams.Groups(people, describe), teamCount, picker(round))
		local map = teamOf(teams)
		local counted = 0
		for _ in map do
			counted += 1
		end
		expectEqual(counted, #people, `round {round}: someone wasn't dealt`)
		local list = sizes(teams)
		expectTrue(list[#list] - list[1] <= 1, `round {round}: team sizes {table.concat(list, ",")}`)
		-- A party no bigger than the smallest team never needs splitting on its own; with nothing
		-- else split, every party is whole.
		for _, party in split do
			expectTrue(#party >= 2, "only parties are split")
		end
		local parties = 0
		for _, size in spec do
			if size >= 2 then
				parties += 1
			end
		end
		if #split == 0 then
			for party = 1, parties do
				expectEqual(#partyTeams(people, map, party), 1, `round {round}: party {party} split, not reported`)
			end
		end
	end
end)

test("PartyTeams.Deal: splits only when no deal keeps the party whole, as evenly as it can", function()
	for seed = 1, 100 do
		-- A party of 4 and teams of 3 (6 people, 2 teams): 2 + 2, never 3 + 1.
		local people = lineup({ 4, 0, 0 })
		local teams, split = PartyTeams.Deal(PartyTeams.Groups(people, describe), 2, picker(seed))
		local map = teamOf(teams)
		expectEqual(#split, 1)
		local count = { 0, 0 }
		for _, who in people do
			if who.Party == 1 then
				count[map[who]] += 1
			end
		end
		expectEqual(count, { 2, 2 })

		-- A party of 3 and teams of 2 (8 people, 4 teams: Log Jam, Prime Cut, Eatsa Pizza): 2 + 1.
		people = lineup({ 3, 0, 0, 0, 0, 0 })
		teams, split = PartyTeams.Deal(PartyTeams.Groups(people, describe), 4, picker(seed))
		map = teamOf(teams)
		expectEqual(#split, 1)
		expectEqual(#partyTeams(people, map, 1), 2)

		-- Four parties of 3 in three teams of 4: one of them can't fit (and only one), 1 + 1 + 1.
		people = lineup({ 3, 3, 3, 3 })
		teams, split = PartyTeams.Deal(PartyTeams.Groups(people, describe), 3, picker(seed))
		map = teamOf(teams)
		expectEqual(#split, 1)
		local whole = 0
		for party = 1, 4 do
			local on = partyTeams(people, map, party)
			if #on == 1 then
				whole += 1
			else
				expectEqual(#on, 3)
			end
		end
		expectEqual(whole, 3)

		-- Parties that all fit somehow are never split, however the sizes fall: 4 + 2 + 2 in teams
		-- of 4 (8 people, 2 teams), 3 + 3 + 2 in 3, 3, 2.
		people = lineup({ 4, 2, 2 })
		teams, split = PartyTeams.Deal(PartyTeams.Groups(people, describe), 2, picker(seed))
		expectEqual(#split, 0)
		people = lineup({ 3, 3, 2 })
		teams, split = PartyTeams.Deal(PartyTeams.Groups(people, describe), 3, picker(seed))
		expectEqual(#split, 0)
		map = teamOf(teams)
		for party = 1, 3 do
			expectEqual(#partyTeams(people, map, party), 1)
		end
	end
end)

test("PartyTeams.Deal: random among equal choices (the party's team, the bigger team, everyone else)", function()
	local partyOn, soloOn, bigTeam = {}, {}, {}
	for seed = 1, 400 do
		local people = lineup({ 2, 0, 0, 0, 0, 0 }, 1) -- 8 in the round: 3 teams of 3, 3, 2
		local teams = PartyTeams.Deal(PartyTeams.Groups(people, describe), 3, picker(seed))
		local map = teamOf(teams)
		local on = partyTeams(people, map, 1)[1]
		partyOn[on] = (partyOn[on] or 0) + 1
		soloOn[map[people[3]]] = (soloOn[map[people[3]]] or 0) + 1
		for index, team in teams do
			if #team == 2 then
				bigTeam[index] = (bigTeam[index] or 0) + 1 -- (the small team, here)
			end
		end
	end
	for team = 1, 3 do
		expectTrue((partyOn[team] or 0) > 60, `the party was on team {team} {partyOn[team] or 0} times of 400`)
		expectTrue((soloOn[team] or 0) > 60, `a solo was on team {team} {soloOn[team] or 0} times of 400`)
		expectTrue((bigTeam[team] or 0) > 60, `team {team} was the small one {bigTeam[team] or 0} times of 400`)
	end
	-- Different seeds, different deals.
	local seen = {}
	for seed = 1, 20 do
		local people = lineup({ 0, 0, 0, 0, 0, 0 })
		local teams = PartyTeams.Deal(PartyTeams.Groups(people, describe), 2, picker(seed))
		local names = {}
		for _, who in teams[1] do
			table.insert(names, who.Name)
		end
		table.sort(names)
		seen[table.concat(names, ",")] = true
	end
	local distinct = 0
	for _ in seen do
		distinct += 1
	end
	expectTrue(distinct >= 8, `only {distinct} different deals in 20`)
end)

test("PartyTeams: bots never group, and fill the teams like anyone on their own", function()
	for seed = 1, 100 do
		local people = lineup({ 2 }, 6) -- two partied people and six bots: 2 teams of 4
		for _, who in people do
			if who.IsBot then
				who.Party = 9 -- as if the bots had a party: ignored
			end
		end
		local teams, split = PartyTeams.Deal(PartyTeams.Groups(people, describe), 2, picker(seed))
		expectEqual(sizes(teams), { 4, 4 })
		expectEqual(#split, 0)
		local map = teamOf(teams)
		local botTeams = {}
		for _, who in people do
			if who.IsBot then
				botTeams[map[who]] = (botTeams[map[who]] or 0) + 1
			end
		end
		expectEqual(#partyTeams(people, map, 1), 1)
		-- The partied pair's team has 2 bots, the other 4.
		local pairTeam = partyTeams(people, map, 1)[1]
		expectEqual(botTeams[pairTeam], 2)
		expectEqual(botTeams[3 - pairTeam], 4)
	end
end)

test("PartyTeams.Sides: a party on one side where the counts allow, about as often as anyone", function()
	local asArchers, solosAsArchers = 0, 0
	for seed = 1, 800 do
		-- Arrow Ambush with 8: 2 archers, 6 runners. A party of 2 and one of 3.
		local people = lineup({ 2, 3, 0, 0, 0 })
		local order, split = PartyTeams.Sides(PartyTeams.Groups(people, describe), 2, picker(seed))
		expectEqual(#order, 8)
		expectEqual(#split, 0)
		local side = {}
		for index, who in order do
			side[who] = if index <= 2 then "A" else "B"
		end
		for party = 1, 2 do
			local sides = {}
			for _, who in people do
				if who.Party == party then
					sides[side[who]] = true
				end
			end
			expectTrue(not (sides.A and sides.B), `seed {seed}: party {party} on both sides`)
			if party == 2 then
				expectTrue(sides.B == true, "a party of 3 never fits 2 archer spots")
			elseif sides.A then
				asArchers += 1
			end
		end
		for _, who in people do
			if who.Party == nil and side[who] == "A" then
				solosAsArchers += 1
			end
		end
	end
	-- The party of 3 always runs, so the other five share the 2 archer spots: the pair are archers
	-- about as often as each of the three on their own (2 in 5).
	local pairRate, soloRate = asArchers / 800, solosAsArchers / (3 * 800)
	expectTrue(math.abs(pairRate - soloRate) < 0.08, `the pair were archers {pairRate}, the others {soloRate}`)
	expectTrue(pairRate > 0.3 and pairRate < 0.5, `the pair were archers {pairRate} of the time`)
end)

test("PartyTeams.Sides: a party too big for either side is split as evenly as the sides allow", function()
	for seed = 1, 50 do
		-- Three people, one of them the archer, all in one party: 1 + 2.
		local people = lineup({ 3 })
		local order, split = PartyTeams.Sides(PartyTeams.Groups(people, describe), 1, picker(seed))
		expectEqual(#order, 3)
		expectEqual(#split, 1)
		-- Sinking Sands with 8: 3 Sand Kings. A party of 4 and four people on their own: the party
		-- dives together.
		people = lineup({ 4, 0, 0, 0, 0 })
		order, split = PartyTeams.Sides(PartyTeams.Groups(people, describe), 3, picker(seed))
		expectEqual(#split, 0)
		for index = 1, 3 do
			expectTrue(order[index].Party == nil, "a party of 4 can't all be Kings")
		end
	end
end)

test("PartyTeams: nobody in the round, one team, everyone on their own", function()
	local teams, split = PartyTeams.Deal({}, 2, picker(1))
	expectEqual(sizes(teams), { 0, 0 })
	expectEqual(#split, 0)
	teams = PartyTeams.Deal(PartyTeams.Groups(lineup({ 3, 0 }), describe), 1, picker(1))
	expectEqual(sizes(teams), { 4 })
	local order = PartyTeams.Sides({}, 2, picker(1))
	expectEqual(#order, 0)
end)

return nil

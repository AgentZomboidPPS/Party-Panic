--!strict
-- Parties on one team (owner: "stuff to work on right now is parties. The parties work in the way
-- that if you party with others for team games you are on the same team."): deals a round's players
-- into teams so that each party's members who are in the round play on one team.
--
--   * Deal: colour teams (RoundContext:AssignTeams: Pump & Pop, Cake Factory, Bobsled Run, Log
--     Jam, Prime Cut, Eatsa Pizza). Team sizes stay within one of each other, as before: the
--     parties go in first, then everyone on their own fills the gaps.
--   * Sides: two sides of set sizes for the modes that pick roles themselves (Arrow Ambush's
--     archers, Shark Bait's sharks, Sinking Sands' Sand Kings): a party lands on one side whenever
--     the role counts allow it.
-- A party is split only when no way of dealing keeps it on one team (the teams are smaller than the
-- party, or the other parties took the room): as few parties as possible (the bigger ones stay
-- whole first), each over as few teams as possible, in pieces as even as possible (a party of 4 in
-- teams of 3 plays 2 + 2). The caller tells its members.
-- Everything else stays random, as the old shuffle was: which team each party joins (weighted by the
-- room each team has left, so a party's members are as likely as anyone to land on the smaller
-- side), who fills the gaps, and which team gets which name.
-- Who's in which party (Groups): each party's members in the round together, everyone else on their
-- own; a bot is always on its own (bots never join parties), and so is a party's only member here.
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.

local PartyTeams = {}

-- A random whole number from 1 to `count` (RoundContext: its Random's NextInteger(1, count)).
export type Pick = (count: number) -> number

-- What the caller knows about someone in the round.
export type Member = {
	IsBot: boolean,
	Party: number?, -- their party's id (the server's PP_Party), nil when on their own
}

-- More parties than this (never, with 12 players and parties of 2 or more) are kept whole greedily
-- instead of by trying every set of them.
local MAX_EXACT = 12

local function shuffle<T>(list: { T }, pick: Pick)
	for index = #list, 2, -1 do
		local other = pick(index)
		list[index], list[other] = list[other], list[index]
	end
end

-- The round's people and bots in groups: each party's members here together, in the order their
-- first member comes in `people`; everyone else (bots always) as a group of one.
function PartyTeams.Groups<T>(people: { T }, describe: (T) -> Member): { { T } }
	local groups: { { T } } = {}
	local byParty: { [number]: { T } } = {}
	for _, person in people do
		local info = describe(person)
		local party = if info.IsBot then nil else info.Party
		if type(party) == "number" and party > 0 then
			local group = byParty[party]
			if group then
				table.insert(group, person)
			else
				local fresh = { person }
				byParty[party] = fresh
				table.insert(groups, fresh)
			end
		else
			table.insert(groups, { person })
		end
	end
	return groups
end

-- Whether groups of these sizes (from `from` on, biggest first) all fit in teams with this much room
-- left. Teams with the same room left are interchangeable, so only one of them is tried.
local function fits(sizes: { number }, rooms: { number }, from: number): boolean
	local size = sizes[from]
	if size == nil then
		return true
	end
	local tried: { [number]: boolean } = {}
	for team, room in rooms do
		if room >= size and not tried[room] then
			tried[room] = true
			rooms[team] = room - size
			local ok = fits(sizes, rooms, from + 1)
			rooms[team] = room
			if ok then
				return true
			end
		end
	end
	return false
end

local function sizesOf<T>(parties: { { T } }, keep: { boolean }): { number }
	local sizes = {}
	for index, party in parties do
		if keep[index] then
			table.insert(sizes, #party)
		end
	end
	table.sort(sizes, function(a, b)
		return a > b
	end)
	return sizes
end

-- Which parties play whole (true) and which are split: as many whole as possible, then as many
-- people in whole parties as possible; among equally good sets, the first in the parties' (random)
-- order.
local function chooseWhole<T>(parties: { { T } }, rooms: { number }): { boolean }
	local count = #parties
	local all = table.create(count, true)
	if count == 0 or fits(sizesOf(parties, all), table.clone(rooms), 1) then
		return all
	end
	if count > MAX_EXACT then
		-- Greedy: the biggest first, each kept whole if it still fits with the ones kept before it.
		local keep = table.create(count, false)
		local order = {}
		for index in parties do
			table.insert(order, index)
		end
		table.sort(order, function(a, b)
			return #parties[a] > #parties[b]
		end)
		for _, index in order do
			keep[index] = true
			if not fits(sizesOf(parties, keep), table.clone(rooms), 1) then
				keep[index] = false
			end
		end
		return keep
	end
	local best: { boolean }? = nil
	local bestWhole, bestPeople = -1, -1
	for mask = 0, 2 ^ count - 1 do
		local keep, whole, people = {}, 0, 0
		for index, party in parties do
			keep[index] = bit32.btest(mask, 2 ^ (index - 1))
			if keep[index] then
				whole += 1
				people += #party
			end
		end
		local better = whole > bestWhole or (whole == bestWhole and people > bestPeople)
		if better and fits(sizesOf(parties, keep), table.clone(rooms), 1) then
			best, bestWhole, bestPeople = keep, whole, people
		end
	end
	return best or table.create(count, false)
end

-- The evenest way to put `size` people in teams with these rooms (one at a time into the smallest
-- piece that still has room): each team's piece, in the order of `rooms`.
local function evenPieces(size: number, rooms: { number }): { number }
	local pieces = table.create(#rooms, 0)
	for _ = 1, size do
		local best: number? = nil
		for index, room in rooms do
			if pieces[index] < room and (best == nil or pieces[index] < pieces[best]) then
				best = index
			end
		end
		if best == nil then
			break
		end
		pieces[best] += 1
	end
	return pieces
end

-- Where a party that can't play whole goes: over the fewest teams that hold it, in the evenest
-- pieces (random among equals). Returns how many of it each team takes.
local function splitPieces(size: number, rooms: { number }, pick: Pick): { number }
	local teamCount = #rooms
	local best: { number }? = nil
	local bestTeams, bestSpread, ties = math.huge, math.huge, 0
	for mask = 1, 2 ^ teamCount - 1 do
		local chosen, chosenRooms, total = {}, {}, 0
		for team = 1, teamCount do
			if bit32.btest(mask, 2 ^ (team - 1)) then
				table.insert(chosen, team)
				table.insert(chosenRooms, rooms[team])
				total += rooms[team]
			end
		end
		if total < size or #chosen > bestTeams then
			continue
		end
		local pieces = evenPieces(size, chosenRooms)
		local low, high = math.huge, 0
		for _, piece in pieces do
			low, high = math.min(low, piece), math.max(high, piece)
		end
		if low == 0 then
			continue -- a team that takes nobody: a smaller set of teams does the same
		end
		local spread = high - low
		local result = table.create(teamCount, 0)
		for index, team in chosen do
			result[team] = pieces[index]
		end
		if #chosen < bestTeams or spread < bestSpread then
			best, bestTeams, bestSpread, ties = result, #chosen, spread, 1
		elseif spread == bestSpread then
			ties += 1
			if pick(ties) == 1 then
				best = result
			end
		end
	end
	return best or evenPieces(size, rooms)
end

-- Fills teams with these capacities: the parties that can play whole (biggest first, each into a
-- team where it fits and leaves room for the rest, picked at random weighted by the room each has),
-- then the split ones, then everyone on their own at random. Returns the teams, in the order of
-- `capacities`, and the parties that were split.
local function pack<T>(groups: { { T } }, capacities: { number }, pick: Pick): ({ { T } }, { { T } })
	local parties: { { T } } = {}
	local solos: { T } = {}
	for _, group in groups do
		if #group >= 2 then
			table.insert(parties, group)
		elseif group[1] ~= nil then
			table.insert(solos, group[1])
		end
	end
	shuffle(parties, pick)
	shuffle(solos, pick)

	local rooms = table.clone(capacities)
	local teams: { { T } } = {}
	for index in capacities do
		teams[index] = {}
	end
	local whole = chooseWhole(parties, rooms)
	local keep: { { T } }, split: { { T } } = {}, {}
	for index, party in parties do
		table.insert(if whole[index] then keep else split, party)
	end
	table.sort(keep, function(a, b)
		return #a > #b
	end)
	table.sort(split, function(a, b)
		return #a > #b
	end)

	for index, party in keep do
		local rest = {}
		for later = index + 1, #keep do
			table.insert(rest, #keep[later])
		end
		local options, weight = {}, 0
		for team, room in rooms do
			if room >= #party then
				rooms[team] = room - #party
				if fits(rest, rooms, 1) then
					table.insert(options, team)
					weight += room
				end
				rooms[team] = room
			end
		end
		local chosen = options[#options]
		local roll = pick(math.max(1, weight))
		for _, team in options do
			roll -= rooms[team]
			if roll <= 0 then
				chosen = team
				break
			end
		end
		if chosen == nil then
			table.insert(split, party) -- (can't happen: the set was checked to fit)
			continue
		end
		rooms[chosen] -= #party
		for _, member in party do
			table.insert(teams[chosen], member)
		end
	end

	for _, party in split do
		local members = table.clone(party)
		shuffle(members, pick)
		local pieces = splitPieces(#members, rooms, pick)
		local next = 1
		for team, piece in pieces do
			for _ = 1, piece do
				if members[next] ~= nil then
					table.insert(teams[team], members[next])
					next += 1
				end
			end
			rooms[team] -= piece
		end
		for leftover = next, #members do
			table.insert(solos, members[leftover]) -- (can't happen: there's always room for everyone)
		end
	end

	local slots = {}
	for team, room in rooms do
		for _ = 1, room do
			table.insert(slots, team)
		end
	end
	for index, solo in solos do
		table.insert(teams[slots[index] or #capacities], solo)
	end
	for _, team in teams do
		shuffle(team, pick)
	end
	return teams, split
end

local function countOf<T>(groups: { { T } }): number
	local total = 0
	for _, group in groups do
		total += #group
	end
	return total
end

-- Deals everyone in `groups` (Groups) into `teamCount` teams whose sizes differ by at most one.
-- Returns the teams (lists, in a random order: the caller names them in turn) and the parties that
-- had to be split.
function PartyTeams.Deal<T>(groups: { { T } }, teamCount: number, pick: Pick): ({ { T } }, { { T } })
	local count = math.max(1, math.floor(teamCount))
	local total = countOf(groups)
	local capacities = {}
	for index = 1, count do
		capacities[index] = total // count + (if index <= total % count then 1 else 0)
	end
	local teams, split = pack(groups, capacities, pick)
	shuffle(teams, pick) -- which name gets which team (and so which gets the bigger one)
	return teams, split
end

-- Two sides for a role mode: everyone in `groups` in an order whose first `count` make one side
-- (the archers, sharks or Sand Kings) and the rest the other, with each party on one side where the
-- counts allow. Returns that order and the parties that had to be split.
function PartyTeams.Sides<T>(groups: { { T } }, count: number, pick: Pick): ({ T }, { { T } })
	local total = countOf(groups)
	local first = math.clamp(math.floor(count), 0, total)
	local sides, split = pack(groups, { first, total - first }, pick)
	local order = table.clone(sides[1])
	for _, member in sides[2] do
		table.insert(order, member)
	end
	return order, split
end

return PartyTeams

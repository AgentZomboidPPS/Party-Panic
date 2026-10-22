--!strict
-- Party Cups (the owner asked "If you could do 5 things to keep players addicted what would you
-- do?", got Party Cups among the five, then: "Can you work on all of that? this wont mess with what
-- the other workers are working on right?"): every 5 rounds on a server add up into a cup with a
-- podium, and the champion wears a crown in the lobby until the next cup ends. This is the cup's
-- scoring and standings, kept pure so they're unit tested (tests/PartyCup.spec.luau);
-- Services/CupService runs the cups and Controllers/CupController draws them.
--
-- A round adds points by the place its results card showed (Logic/Placement): 10, 8, 6, 5, 4, 3, 2,
-- then 1 for every place after that, so everyone who plays scores. Ties share: everyone on the same
-- place gets that place's points (a team game's whole winning team, a survival game's survivors).
-- A round only counts when a person played it (one whose people all left is bots only).
-- The standings go by points, then round wins in this cup, then the place in the cup's latest
-- round; whoever is still level shares the place. Players and bots are both in them (a lone player
-- with bots still has a cup to win), but only people win the podium's coins (5, 3, 2).
-- Leaf module: no requires, no Roblox APIs.

local PartyCup = {}

PartyCup.Rounds = 5 -- rounds in a cup
PartyCup.Points = { 10, 8, 6, 5, 4, 3, 2 } -- a round's points by place; every later place gets MinPoints
PartyCup.MinPoints = 1
PartyCup.Prizes = { 5, 3, 2 } -- coins for 1st, 2nd and 3rd (people only; the low coin scale)
PartyCup.Shown = 12 -- standings the GameState attribute carries (a full server)

export type Entry = {
	UserId: number, -- a bot's is negative
	Name: string,
	IsBot: boolean,
	Points: number,
	Wins: number, -- rounds of this cup they won
	Rounds: number, -- rounds of this cup they played
	Last: number?, -- their place in the cup's latest round (nil: they weren't in it)
	Gain: number, -- the points the cup's latest round gave them
	LastRound: number, -- the round of the cup they last played (0: none yet)
}

export type Cup = {
	Number: number, -- this server's first cup is 1
	Played: number, -- rounds counted so far
	Entries: { [number]: Entry }, -- by UserId
}

-- One player's (or bot's) place in a round, as the round's results placed them.
export type Result = { UserId: number, Name: string, IsBot: boolean, Place: number }

export type Standing = {
	UserId: number,
	Name: string,
	IsBot: boolean,
	Points: number,
	Wins: number,
	Last: number?,
	Gain: number,
	Place: number,
}

-- What the GameState attribute carries for each row.
export type Row = { UserId: number, Name: string, Points: number, IsBot: boolean, Place: number, Gain: number }

function PartyCup.New(number: number): Cup
	return { Number = number, Played = 0, Entries = {} }
end

-- A round's points for finishing in `place`.
function PartyCup.PointsFor(place: number): number
	return PartyCup.Points[place] or PartyCup.MinPoints
end

-- The coins a person on the podium wins for `place` (0 off the podium).
function PartyCup.PrizeFor(place: number): number
	return PartyCup.Prizes[place] or 0
end

function PartyCup.IsOver(cup: Cup): boolean
	return cup.Played >= PartyCup.Rounds
end

-- The round of the cup that's next (1 to Rounds; once the cup is over, its last).
function PartyCup.NextRound(cup: Cup): number
	return math.min(cup.Played + 1, PartyCup.Rounds)
end

-- Counts a finished round. False (nothing changes) when no person is in it or the cup is over.
-- Everyone in it gets their place's points; people who weren't in it keep theirs.
function PartyCup.AddRound(cup: Cup, results: { Result }): boolean
	if PartyCup.IsOver(cup) then
		return false
	end
	local anyPerson = false
	for _, result in results do
		if not result.IsBot then
			anyPerson = true
			break
		end
	end
	if not anyPerson then
		return false
	end
	for _, entry in cup.Entries do
		entry.Last = nil
		entry.Gain = 0
	end
	for _, result in results do
		local entry = cup.Entries[result.UserId]
		if not entry then
			-- Someone new (they joined since the cup began) starts at 0.
			entry = {
				UserId = result.UserId,
				Name = result.Name,
				IsBot = result.IsBot,
				Points = 0,
				Wins = 0,
				Rounds = 0,
				Last = nil,
				Gain = 0,
				LastRound = 0,
			}
			cup.Entries[result.UserId] = entry
		end
		local points = PartyCup.PointsFor(result.Place)
		entry.Name = result.Name
		entry.Points += points
		entry.Gain = points
		entry.Last = result.Place
		entry.LastRound = cup.Played + 1
		entry.Rounds += 1
		if result.Place == 1 then
			entry.Wins += 1
		end
	end
	cup.Played += 1
	return true
end

-- Takes someone out of the standings (they left the server). Returns their entry, so a person who
-- comes back during the same cup can have their points back (Restore).
function PartyCup.Remove(cup: Cup, userId: number): Entry?
	local entry = cup.Entries[userId]
	cup.Entries[userId] = nil
	return entry
end

-- Puts back the entry of someone who left during this cup and came back (their place in the latest
-- round only if they played it).
function PartyCup.Restore(cup: Cup, entry: Entry)
	if cup.Entries[entry.UserId] then
		return
	end
	if entry.LastRound ~= cup.Played then
		entry.Last = nil
		entry.Gain = 0
	end
	cup.Entries[entry.UserId] = entry
end

-- Whether `a` is ahead of `b`: points, then round wins, then the better place in the latest round.
local function ahead(a: Entry, b: Entry): boolean
	if a.Points ~= b.Points then
		return a.Points > b.Points
	end
	if a.Wins ~= b.Wins then
		return a.Wins > b.Wins
	end
	return (a.Last or math.huge) < (b.Last or math.huge)
end

-- Everyone in the cup, best first, with their place. People who are level on everything share the
-- place, and the next place skips past them (1, 1, 3), like a round's results.
function PartyCup.Standings(cup: Cup): { Standing }
	local list: { Entry } = {}
	for _, entry in cup.Entries do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		if ahead(a, b) then
			return true
		elseif ahead(b, a) then
			return false
		end
		-- Level: a steady order to list them in (the place is shared anyway).
		if a.Name ~= b.Name then
			return a.Name < b.Name
		end
		return a.UserId < b.UserId
	end)
	local standings: { Standing } = {}
	local place = 0
	for position, entry in list do
		if position == 1 or ahead(list[position - 1], entry) then
			place = position
		end
		table.insert(standings, {
			UserId = entry.UserId,
			Name = entry.Name,
			IsBot = entry.IsBot,
			Points = entry.Points,
			Wins = entry.Wins,
			Last = entry.Last,
			Gain = entry.Gain,
			Place = place,
		})
	end
	return standings
end

-- The podium: everyone placed 1st to 3rd (more than three when some share a place).
function PartyCup.Podium(standings: { Standing }): { Standing }
	local podium = {}
	for _, standing in standings do
		if standing.Place <= #PartyCup.Prizes then
			table.insert(podium, standing)
		end
	end
	return podium
end

-- The people who won (1st place). A bot can win a cup too: then nobody is crowned.
function PartyCup.Champions(standings: { Standing }): { Standing }
	local champions = {}
	for _, standing in standings do
		if standing.Place == 1 and not standing.IsBot then
			table.insert(champions, standing)
		end
	end
	return champions
end

-- What the podium pays: one line per person on it (bots win nothing).
function PartyCup.Payouts(standings: { Standing }): { { UserId: number, Place: number, Coins: number } }
	local payouts = {}
	for _, standing in standings do
		local coins = PartyCup.PrizeFor(standing.Place)
		if coins > 0 and not standing.IsBot then
			table.insert(payouts, { UserId = standing.UserId, Place = standing.Place, Coins = coins })
		end
	end
	return payouts
end

-- The first `limit` standings as the GameState attribute carries them.
function PartyCup.Rows(standings: { Standing }, limit: number?): { Row }
	local rows: { Row } = {}
	for index, standing in standings do
		if index > (limit or PartyCup.Shown) then
			break
		end
		table.insert(rows, {
			UserId = standing.UserId,
			Name = standing.Name,
			Points = standing.Points,
			IsBot = standing.IsBot,
			Place = standing.Place,
			Gain = standing.Gain,
		})
	end
	return rows
end

return PartyCup

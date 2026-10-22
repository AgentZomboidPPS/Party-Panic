--!strict
-- 👍 / 👎 on each mini-game (owner: "lets add to the backburner a away for players to downvote a
-- minigame and then we can harvest that data to disable minigames in the future." Then: "Also while
-- you make the downvote for mini games can you also do an upvote one so we can see if players like
-- it"). While a round's results show, each person who played it can tap 👍 ("Loved it") or 👎 ("Not
-- for me") on their card: one vote per person per round. Tapping the other one switches it, tapping
-- the lit one again takes it back. Bots and anyone who sat the round out don't vote.
--
-- The counts go into running totals per game and ISO week (Services/RatingService keeps them in
-- the PP_GameRatings data store), next to the signals the game already has: the PLAY AGAIN vote's
-- answers and how often the game wins the game vote. tools/checks/game_ratings.py reads the last
-- four weeks and sorts the games best-liked first (Summary): the top shows what players like, the
-- bottom what to switch off (Enabled = false in Shared/GameDefinitions).
--
-- Unique voters are counted without keeping anyone's UserId: each voter sets one bit of a 4096-bit
-- map (a hash of their UserId), and the share of bits still clear says about how many different
-- people set them (linear counting: within a few percent up to several thousand voters a week).
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.

local GameRatings = {}

export type Choice = "Up" | "Down" | "None"

-- Someone in the round as the results see them: `Key` is what their votes come from (the Player on
-- a server), `Id` their UserId.
export type Member = { Key: any, Id: number, Bot: boolean?, SatOut: boolean? }

export type Ballot = {
	Game: string,
	Ids: { [any]: number }, -- who can vote (people who played) -> UserId
	Plays: number,
	Votes: { [any]: "Up" | "Down" },
}

export type Tally = { Game: string, Plays: number, Up: number, Down: number, Voters: { number } }

-- One game's totals for one week (the data store's value), all counts.
export type Record = {
	Rounds: number,
	Plays: number, -- people who played (bots never count)
	Up: number,
	Down: number,
	Seen: string, -- the voters' bit map (hex), for the unique voters
	ReplayYes: number, -- PLAY AGAIN answers at the end of the results
	ReplayNo: number,
	VoteWins: number, -- times the game won the game vote by name
	VoteOffers: number, -- times it was on the vote by name (the Random card doesn't count)
}

-- Fewer votes than this and the net score is too noisy to act on.
GameRatings.MinVotes = 30
GameRatings.MapBits = 4096
local HEX_DIGITS = GameRatings.MapBits // 4

-- The ballot for one round of `game`: everyone in `members` who is a person and played (not a bot,
-- not sitting out) can vote.
function GameRatings.NewBallot(game: string, members: { Member }): Ballot
	local ids = {}
	local plays = 0
	for _, member in members do
		if not member.Bot and not member.SatOut and ids[member.Key] == nil then
			ids[member.Key] = member.Id
			plays += 1
		end
	end
	return { Game = game, Ids = ids, Plays = plays, Votes = {} }
end

-- What a tap makes of the vote already there: the other button switches it, the lit one again takes
-- it back.
function GameRatings.Tap(current: Choice, tapped: "Up" | "Down"): Choice
	return if current == tapped then "None" else tapped
end

-- Sets `key`'s vote ("None" takes it back). Returns whether it counts (a voter, and a choice).
function GameRatings.Vote(ballot: Ballot, key: any, choice: any): boolean
	if ballot.Ids[key] == nil or (choice ~= "Up" and choice ~= "Down" and choice ~= "None") then
		return false
	end
	if choice == "None" then
		ballot.Votes[key] = nil
	else
		ballot.Votes[key] = choice
	end
	return true
end

-- `key`'s vote now.
function GameRatings.Current(ballot: Ballot, key: any): Choice
	local vote: Choice? = ballot.Votes[key]
	return vote or "None"
end

function GameRatings.Tally(ballot: Ballot): Tally
	local up, down, voters = 0, 0, {}
	for key, choice in ballot.Votes do
		if choice == "Up" then
			up += 1
		else
			down += 1
		end
		table.insert(voters, ballot.Ids[key])
	end
	table.sort(voters)
	return { Game = ballot.Game, Plays = ballot.Plays, Up = up, Down = down, Voters = voters }
end

-- An empty week for a game.
function GameRatings.Empty(): Record
	return {
		Rounds = 0,
		Plays = 0,
		Up = 0,
		Down = 0,
		Seen = string.rep("0", HEX_DIGITS),
		ReplayYes = 0,
		ReplayNo = 0,
		VoteWins = 0,
		VoteOffers = 0,
	}
end

-- A stored value made safe to add to: anything missing or broken is 0 (or an empty map).
function GameRatings.Clean(value: any): Record
	local record = GameRatings.Empty()
	if type(value) ~= "table" then
		return record
	end
	for key, default in record :: any do
		local stored = value[key]
		if type(default) == "number" and type(stored) == "number" and stored == stored and stored >= 0 then
			(record :: any)[key] = math.floor(stored)
		end
	end
	if type(value.Seen) == "string" and #value.Seen == HEX_DIGITS and not string.find(value.Seen, "[^0-9a-f]") then
		record.Seen = value.Seen
	end
	return record
end

-- 32-bit FNV-1a of a UserId's digits: which bit of the map a voter sets.
local function bitFor(userId: number): number
	local text = tostring(userId)
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		-- times 16777619 (2^24 + 403), mod 2^32, without losing bits to doubles
		hash = (hash * 403 + bit32.lshift(hash, 24)) % 4294967296
	end
	return hash % GameRatings.MapBits
end

-- `seen` with each of `userIds`' bits set.
function GameRatings.Mark(seen: string, userIds: { number }): string
	local digits: { number } = table.create(HEX_DIGITS, 0)
	for index = 1, HEX_DIGITS do
		digits[index] = tonumber(string.sub(seen, index, index), 16) or 0
	end
	for _, userId in userIds do
		local bit = bitFor(userId)
		local index = bit // 4 + 1
		digits[index] = bit32.bor(digits[index], bit32.lshift(1, bit % 4))
	end
	local text = table.create(HEX_DIGITS, "")
	for index, digit in digits do
		text[index] = string.format("%x", digit)
	end
	return table.concat(text)
end

-- About how many different people set bits of `seen` (linear counting).
function GameRatings.CountVoters(seen: string): number
	local set = 0
	for index = 1, #seen do
		local digit = tonumber(string.sub(seen, index, index), 16) or 0
		while digit > 0 do
			set += digit % 2
			digit //= 2
		end
	end
	-- (A full map means far more voters than it can tell apart: it reads as its most, about 34000.)
	local clear = math.max(GameRatings.MapBits - set, 1)
	return math.floor(-GameRatings.MapBits * math.log(clear / GameRatings.MapBits) + 0.5)
end

-- What a week's record becomes with these additions (any of them may be left out): a round's
-- `tally`, its PLAY AGAIN answers, the game vote's `offers` and `wins`.
export type Additions = {
	Tally: Tally?,
	ReplayYes: number?,
	ReplayNo: number?,
	VoteOffers: number?,
	VoteWins: number?,
}

function GameRatings.Add(stored: any, add: Additions): Record
	local record = GameRatings.Clean(stored)
	local tally = add.Tally
	if tally then
		record.Rounds += 1
		record.Plays += tally.Plays
		record.Up += tally.Up
		record.Down += tally.Down
		if #tally.Voters > 0 then
			record.Seen = GameRatings.Mark(record.Seen, tally.Voters)
		end
	end
	record.ReplayYes += add.ReplayYes or 0
	record.ReplayNo += add.ReplayNo or 0
	record.VoteOffers += add.VoteOffers or 0
	record.VoteWins += add.VoteWins or 0
	return record
end

-- The week a moment belongs to, ISO 8601 ("2026-W43": weeks start on Monday, UTC; week 1 is the
-- one with the year's first Thursday). `time` is unix seconds.
function GameRatings.Week(time: number): string
	local day = time // 86400 -- days since 1970-01-01, a Thursday
	local weekday = (day + 3) % 7 -- 0 = Monday
	local thursday = day - weekday + 3 -- the Thursday of this week decides its year
	local year = GameRatings.YearOf(thursday)
	local week = (thursday - GameRatings.DaysTo(year)) // 7 + 1
	return string.format("%d-W%02d", year, week)
end

-- Days from 1970-01-01 to January 1st of `year`.
function GameRatings.DaysTo(year: number): number
	local y = year - 1
	return 365 * (y - 1969) + (y // 4 - 492) - (y // 100 - 19) + (y // 400 - 4)
end

-- The year day `day` (days since 1970-01-01) falls in.
function GameRatings.YearOf(day: number): number
	local year = 1970 + day // 366
	while GameRatings.DaysTo(year + 1) <= day do
		year += 1
	end
	return year
end

-- The `count` weeks up to and including the one `time` is in, newest first.
function GameRatings.LastWeeks(time: number, count: number): { string }
	local weeks = {}
	for back = 0, count - 1 do
		table.insert(weeks, GameRatings.Week(time - back * 7 * 86400))
	end
	return weeks
end

-- One game's row for the owner's table.
export type Row = {
	Game: string,
	Rounds: number,
	Plays: number,
	Up: number,
	Down: number,
	Votes: number,
	Voters: number,
	UpRate: number, -- of the people who played, the share who tapped 👍
	DownRate: number,
	Net: number, -- (👍 - 👎) / every vote, from -1 to 1
	ReplayRate: number?, -- the share of PLAY AGAIN answers that were yes (nil: none)
	VoteWins: number,
	VoteOffers: number,
	Judged: boolean, -- enough votes to act on (MinVotes)
}

-- Adds up each game's weeks (`records`: game -> its weeks' records) and sorts them best-liked first:
-- games with enough votes by net score, then the rest the same way (their scores are only a hint).
-- Ties go to more votes, then to the game's name.
function GameRatings.Summary(records: { [string]: { any } }): { Row }
	local rows = {}
	for game, weeks in records do
		local total = GameRatings.Empty()
		local seen = {}
		for _, week in weeks do
			local record = GameRatings.Clean(week)
			for key, value in record :: any do
				if type(value) == "number" then
					(total :: any)[key] += value
				end
			end
			table.insert(seen, record)
		end
		-- Unique voters over the weeks: the same person in two weeks counts twice (each week's map
		-- is its own), so this is the sum of each week's.
		local voters = 0
		for _, record in seen do
			voters += GameRatings.CountVoters(record.Seen)
		end
		local votes = total.Up + total.Down
		local answers = total.ReplayYes + total.ReplayNo
		table.insert(rows, {
			Game = game,
			Rounds = total.Rounds,
			Plays = total.Plays,
			Up = total.Up,
			Down = total.Down,
			Votes = votes,
			Voters = voters,
			UpRate = if total.Plays > 0 then total.Up / total.Plays else 0,
			DownRate = if total.Plays > 0 then total.Down / total.Plays else 0,
			Net = if votes > 0 then (total.Up - total.Down) / votes else 0,
			ReplayRate = if answers > 0 then total.ReplayYes / answers else nil,
			VoteWins = total.VoteWins,
			VoteOffers = total.VoteOffers,
			Judged = votes >= GameRatings.MinVotes,
		})
	end
	table.sort(rows, function(a: Row, b: Row)
		if a.Judged ~= b.Judged then
			return a.Judged
		elseif a.Net ~= b.Net then
			return a.Net > b.Net
		elseif a.Votes ~= b.Votes then
			return a.Votes > b.Votes
		end
		return a.Game < b.Game
	end)
	return rows
end

return GameRatings

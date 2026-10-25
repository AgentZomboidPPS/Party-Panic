--!strict
-- Game Mastery's rules (owner: "If you could add a progression system what would it be?", then, on
-- the plan: "Let's build it. 1 yes 2 gold pass should help a little. 3 yes"): every game has its own
-- rank, BRONZE, SILVER, GOLD, DIAMOND and LEGEND, climbed with mastery points from that game's rounds.
-- Services/MasteryService pays them and the screens show them; the numbers are Config.Mastery,
-- passed in. Leaf module: no requires, no Roblox APIs.
--
--   * A profile keeps one entry per game played since: P mastery points, W wins that count toward the
--     top ranks, N rounds played to the end. Ranks are worked out from P and W, and never go down.
--   * A rank needs its Points, and the top ones their Wins too (a win with enough real players in
--     the round: ProvenWin), so DIAMOND and LEGEND take beating people, not only playing a lot.
--   * The Spotlight: a few games a day (the same everywhere: from the UTC day) pay double.
--   * When Mastery came out, every game's past rounds were credited once (Load): a point a round and
--     a win for a game medal, so a long-time player starts with the ranks they'd played for.

local MasteryLogic = {}

export type Entry = { P: number, W: number, N: number }
export type Mastery = { [string]: Entry }
export type Rank = {
	Id: string,
	Name: string,
	Icon: string,
	Points: number,
	Wins: number,
	Coins: number,
	Keys: number,
	Crates: number,
}
export type PointTable = {
	First: number,
	Second: number,
	Third: number,
	TopHalf: number,
	Played: number,
	TeamWin: number,
	TeamLoss: number,
}
export type Outcome = {
	Place: number,
	PlayerCount: number,
	Team: boolean?, -- a team game: it pays by whether the player's team won
	Won: boolean?, -- the player won (first place, or on the winning team)
}
export type Progress = {
	Rank: number, -- 0 before BRONZE
	Points: number,
	Wins: number,
	Next: Rank?, -- nil at the top rank
	NeedPoints: number, -- the next rank's (0 at the top)
	NeedWins: number,
	Fraction: number, -- of the way from this rank to the next (1 at the top)
	Short: string?, -- "Points" or "Wins": what the next rank is waiting for (nil at the top)
}

-- The stats the counts across every game go in (the career titles unlock from them: Shared/Cosmetics).
MasteryLogic.CountStats =
	{ Gold = "MasteryGold", Diamond = "MasteryDiamond", Legend = "MasteryLegend" } :: { [string]: string }

local function whole(value: any): number
	local number = tonumber(value)
	if number == nil or number ~= number or number < 0 or number == math.huge then
		return 0
	end
	return math.floor(number)
end

-- The points a round played to the end pays (before the Spotlight and the GOLD PASS).
function MasteryLogic.Points(outcome: Outcome, points: PointTable): number
	if outcome.Team then
		return if outcome.Won then points.TeamWin else points.TeamLoss
	end
	if outcome.Place == 1 then
		return points.First
	elseif outcome.Place == 2 and outcome.PlayerCount >= 2 then
		return points.Second
	elseif outcome.Place == 3 and outcome.PlayerCount >= 3 then
		return points.Third
	elseif outcome.Place <= math.max(1, math.ceil(outcome.PlayerCount / 2)) then
		return points.TopHalf
	end
	return points.Played
end

-- What the round pays in all: `base` (Points), the Spotlight's extra, and the GOLD PASS's bonus for
-- a top-half finish or a team win. Returns the total, the Spotlight's part and the GOLD PASS's part.
function MasteryLogic.Earned(
	base: number,
	spotlight: boolean,
	gold: boolean,
	goodRound: boolean,
	multiplier: number,
	goldBonus: number
): (number, number, number)
	local extra = if spotlight then base * (multiplier - 1) else 0
	local bonus = if gold and goodRound then goldBonus else 0
	return base + extra + bonus, extra, bonus
end

-- Whether a win counts toward the top ranks: `people` real players in the round (the winner too),
-- at least `need` of them, and not a private server.
function MasteryLogic.ProvenWin(won: boolean, people: number, private: boolean, need: number): boolean
	return won and not private and people >= need
end

-- The rank an entry has reached: 0 before BRONZE, else the index of the highest rank whose points
-- and wins it has (ranks are climbed in order: a rank waiting on wins holds back the ones above).
function MasteryLogic.RankOf(entry: Entry?, ranks: { Rank }): number
	local points = if entry then entry.P else 0
	local wins = if entry then entry.W else 0
	local reached = 0
	for index, rank in ranks do
		if points >= rank.Points and wins >= rank.Wins then
			reached = index
		else
			break
		end
	end
	return reached
end

-- Where an entry stands on the way to its next rank.
function MasteryLogic.Progress(entry: Entry?, ranks: { Rank }): Progress
	local points = if entry then entry.P else 0
	local wins = if entry then entry.W else 0
	local rank = MasteryLogic.RankOf(entry, ranks)
	local nextRank = ranks[rank + 1]
	if not nextRank then
		return {
			Rank = rank,
			Points = points,
			Wins = wins,
			Next = nil,
			NeedPoints = 0,
			NeedWins = 0,
			Fraction = 1,
			Short = nil,
		}
	end
	local from = if rank > 0 then ranks[rank].Points else 0
	local fraction, short
	if points < nextRank.Points then
		fraction = math.clamp((points - from) / math.max(1, nextRank.Points - from), 0, 1)
		short = "Points"
	else
		fraction = math.clamp(wins / math.max(1, nextRank.Wins), 0, 1)
		short = "Wins"
	end
	return {
		Rank = rank,
		Points = points,
		Wins = wins,
		Next = nextRank,
		NeedPoints = nextRank.Points,
		NeedWins = nextRank.Wins,
		Fraction = fraction,
		Short = short,
	}
end

-- The next goal in a few words: "6 pts to GOLD", "1 win to DIAMOND", "MAX RANK".
function MasteryLogic.Goal(progress: Progress): string
	local nextRank = progress.Next
	if not nextRank then
		return "MAX RANK"
	end
	if progress.Short == "Wins" then
		local wins = math.max(1, progress.NeedWins - progress.Wins)
		return `{wins} win{if wins == 1 then "" else "s"} to {nextRank.Name}`
	end
	local points = math.max(1, progress.NeedPoints - progress.Points)
	return `{points} pt{if points == 1 then "" else "s"} to {nextRank.Name}`
end

-- What the bar on a screen says: "14/20" points, "WINS 2/3" when the points are there, "MAX" at the top.
function MasteryLogic.BarText(progress: Progress): string
	if not progress.Next then
		return "MAX"
	end
	if progress.Short == "Wins" then
		return `WINS {progress.Wins}/{progress.NeedWins}`
	end
	return `{progress.Points}/{progress.NeedPoints}`
end

-- Adds a round to a game's entry: `gained` points, a win if `provenWin`, a round played. Returns the
-- rank before and after, and the entry.
function MasteryLogic.Record(
	mastery: Mastery,
	gameId: string,
	gained: number,
	provenWin: boolean,
	ranks: { Rank }
): (number, number, Entry)
	local entry = mastery[gameId]
	if not entry then
		entry = { P = 0, W = 0, N = 0 }
		mastery[gameId] = entry
	end
	local before = MasteryLogic.RankOf(entry, ranks)
	entry.P += whole(gained)
	if provenWin then
		entry.W += 1
	end
	entry.N += 1
	return before, MasteryLogic.RankOf(entry, ranks), entry
end

-- The coins, keys and crates for climbing from rank `from` to rank `to` (each rank's, once).
function MasteryLogic.Rewards(ranks: { Rank }, from: number, to: number): (number, number, number)
	local coins, keys, crates = 0, 0, 0
	for index = from + 1, to do
		local rank = ranks[index]
		if rank then
			coins += rank.Coins
			keys += rank.Keys
			crates += rank.Crates
		end
	end
	return coins, keys, crates
end

-- The index of the rank with this id (0 if none).
function MasteryLogic.IndexOf(ranks: { Rank }, id: string): number
	for index, rank in ranks do
		if rank.Id == id then
			return index
		end
	end
	return 0
end

-- How many games (of `known`, when given) have reached rank `index` or higher.
function MasteryLogic.CountAt(mastery: Mastery?, ranks: { Rank }, index: number, known: { [string]: boolean }?): number
	local count = 0
	local entries: Mastery = mastery or {}
	for gameId, entry in entries do
		if (known == nil or known[gameId]) and MasteryLogic.RankOf(entry, ranks) >= index then
			count += 1
		end
	end
	return count
end

-- Puts the counts across every game in the stats (CountStats: the career titles unlock from them).
function MasteryLogic.SetStats(
	stats: { [string]: any },
	mastery: Mastery?,
	ranks: { Rank },
	known: { [string]: boolean }?
)
	for id, stat in MasteryLogic.CountStats do
		local index = MasteryLogic.IndexOf(ranks, id)
		stats[stat] = if index > 0 then MasteryLogic.CountAt(mastery, ranks, index, known) else 0
	end
end

-- On every load: makes the saved entries safe to use (whole numbers, nothing broken kept), credits
-- every game's past rounds the first time (a point and a round for each round in ModePlays, a win
-- for each game medal; `medalOf` gives a game's medal id), and redoes the counts in the stats.
-- Returns how many ranks the credit gave (0 when it was done before).
function MasteryLogic.Load(
	data: { [string]: any },
	ranks: { Rank },
	known: { [string]: boolean }?,
	medalOf: (string) -> string
): number
	local saved = if type(data.Mastery) == "table" then data.Mastery else {}
	local mastery: Mastery = {}
	for gameId, entry in saved do
		if type(gameId) == "string" and type(entry) == "table" then
			mastery[gameId] = { P = whole(entry.P), W = whole(entry.W), N = whole(entry.N) }
		end
	end
	data.Mastery = mastery
	local intro = data.MasteryIntro
	if type(intro) ~= "table" then
		intro = {}
		data.MasteryIntro = intro
	end
	intro.Credited = intro.Credited == true
	intro.Ranks = whole(intro.Ranks)
	intro.Told = intro.Told == true
	local credited = 0
	if not intro.Credited then
		local stats = if type(data.Stats) == "table" then data.Stats else {}
		local plays = if type(stats.ModePlays) == "table" then stats.ModePlays else {}
		local medals = if type(data.Medals) == "table" then data.Medals else {}
		for gameId, count in plays do
			local rounds = whole(count)
			if type(gameId) ~= "string" or rounds == 0 or (known ~= nil and not known[gameId]) then
				continue
			end
			local entry: Entry = mastery[gameId] or { P = 0, W = 0, N = 0 }
			mastery[gameId] = entry
			entry.P = math.max(entry.P, rounds)
			entry.N = math.max(entry.N, rounds)
			if medals[medalOf(gameId)] ~= nil then
				entry.W = math.max(entry.W, 1)
			end
			credited += MasteryLogic.RankOf(entry, ranks)
		end
		intro.Credited = true
		intro.Ranks = credited
	end
	if type(data.Stats) == "table" then
		MasteryLogic.SetStats(data.Stats, mastery, ranks, known)
	end
	return credited
end

-- FNV-1a: a number from a text that's the same on every server and every device.
local function hash(text: string): number
	local value = 2166136261
	for index = 1, #text do
		value = bit32.bxor(value, string.byte(text, index))
		-- times 16777619 (2^24 + 403), in two exact parts: the whole product needs more than 53 bits
		value = (bit32.lshift(value, 24) + value * 403) % 4294967296
	end
	return value
end

-- Today's Spotlight: `count` of the games `ids`, picked from the UTC `day` (the same everywhere).
function MasteryLogic.Spotlight(day: number, ids: { string }, count: number): { string }
	local ranked = table.clone(ids)
	table.sort(ranked)
	local scores: { [string]: number } = {}
	for _, id in ranked do
		scores[id] = hash(`{day}:{id}`)
	end
	table.sort(ranked, function(a: string, b: string): boolean
		if scores[a] ~= scores[b] then
			return scores[a] < scores[b]
		end
		return a < b
	end)
	local picked = {}
	for index = 1, math.min(count, #ranked) do
		table.insert(picked, ranked[index])
	end
	return picked
end

return MasteryLogic

--!strict
-- The weekly leaderboard's rules: points from rounds, the week a point counts for, the board's
-- order and the words players read. The owner, asked "If you could do 5 things to keep players
-- addicted what would you do?", got "Weekly leaderboard and Hall of Fame statues of last week's top
-- three" as one of them, then said: "Can you work on all of that? this wont mess with what the
-- other workers are working on right?".
--
-- Points, simple to explain and the same for every game: 1st 10, 2nd 7, 3rd 5, anyone else who
-- played 1, so winners and players who keep playing both climb. A podium place only pays when
-- someone finished below it (a round where everyone ties pays the playing point).
-- Weeks start on Monday 00:00 UTC (DailyLogic.WeekNumber's weeks). A player's points belong to one
-- week: the first round of a new week starts them from 0, and a week they scored in is remembered
-- (Pending) until the server has checked whether it ended in the top three (the HallOfFame medal).
-- Leaf module: no requires, no Roblox APIs.

local WeeklyLogic = {}

WeeklyLogic.PlacePoints = { 10, 7, 5 } -- 1st, 2nd, 3rd
WeeklyLogic.PlayPoints = 1 -- everyone else who played the round
WeeklyLogic.BoardSize = 10 -- this week's board
WeeklyLogic.Statues = 3 -- last week's top three stand in the Hall of Fame
WeeklyLogic.PendingKept = 3 -- weeks still to check for the top three, at most

local SECONDS_PER_DAY = 86400

export type Weekly = { Week: number, Points: number, Pending: { number }? }
export type Entry = { UserId: number, Points: number, Name: string? }
export type Ranked = { UserId: number, Points: number, Name: string?, Rank: number }

-- The points a round's place pays. `worstPlace` is the round's last place (Placement's numbers:
-- tied players share a place).
function WeeklyLogic.PointsFor(place: number, worstPlace: number): number
	local points = WeeklyLogic.PlacePoints[place]
	if points and place < worstPlace then
		return points
	end
	return WeeklyLogic.PlayPoints
end

-- "1ST 10 · 2ND 7 · 3RD 5 · PLAYING 1"
function WeeklyLogic.RulesText(): string
	local p = WeeklyLogic.PlacePoints
	return `1ST {p[1]} · 2ND {p[2]} · 3RD {p[3]} · PLAYING {WeeklyLogic.PlayPoints}`
end

-- The first moment of week `week` (unix seconds): a Monday, 00:00 UTC. DailyLogic counts weeks from
-- the Monday before the epoch (a Thursday), so week w starts on day 7w - 3.
function WeeklyLogic.WeekStart(week: number): number
	return (week * 7 - 3) * SECONDS_PER_DAY
end

function WeeklyLogic.WeekEnd(week: number): number
	return WeeklyLogic.WeekStart(week + 1)
end

-- Whether week `week` is over and every server has had `settle` seconds to save its last points,
-- so its top three is final.
function WeeklyLogic.Settled(week: number, now: number, settle: number): boolean
	return now >= WeeklyLogic.WeekEnd(week) + settle
end

-- The time to the board's reset, in the board's words: "2D 5H", "5H 12M", "12M".
function WeeklyLogic.ResetsIn(seconds: number): string
	local minutes = math.max(1, math.ceil(seconds / 60))
	local days = math.floor(minutes / 1440)
	local hours = math.floor((minutes % 1440) / 60)
	if days > 0 then
		return `{days}D {hours}H`
	elseif hours > 0 then
		return `{hours}H {minutes % 60}M`
	end
	return `{minutes}M`
end

-- "35 PTS", "1 PT"
function WeeklyLogic.Pts(points: number): string
	return if points == 1 then "1 PT" else `{points} PTS`
end

-- Brings a player's points to week `week`: a later week starts them from 0, and the week they
-- leave behind is kept in Pending (if they scored in it) until its top three has been checked. An
-- earlier week (a server whose clock is a little behind) changes nothing. True when it changed.
function WeeklyLogic.Roll(weekly: Weekly, week: number): boolean
	if weekly.Week >= week then
		return false
	end
	if weekly.Week > 0 and weekly.Points > 0 then
		local pending = weekly.Pending or {}
		if not table.find(pending, weekly.Week) then
			table.insert(pending, weekly.Week)
		end
		while #pending > WeeklyLogic.PendingKept do
			table.remove(pending, 1)
		end
		weekly.Pending = pending
	end
	weekly.Week = week
	weekly.Points = 0
	return true
end

-- Adds a round's points for week `week` (rolling first). Returns the week they went to (the
-- player's own, if their save is already a week ahead) and the new total.
function WeeklyLogic.Add(weekly: Weekly, week: number, points: number): (number, number)
	WeeklyLogic.Roll(weekly, week)
	weekly.Points += math.max(0, math.floor(points))
	return weekly.Week, weekly.Points
end

-- Takes `week` off the player's list of weeks to check. True when it was on it.
function WeeklyLogic.ClearPending(weekly: Weekly, week: number): boolean
	local pending = weekly.Pending
	local index = pending and table.find(pending, week)
	if not pending or not index then
		return false
	end
	table.remove(pending, index)
	if #pending == 0 then
		weekly.Pending = nil
	end
	return true
end

-- The board, best first: what the store said (`stored`, best first, maybe only its top `pageSize`)
-- merged with the newest points this server knows (`live`: players here, saves on their way). A
-- player's higher number wins (the store can be behind, never ahead). Ties go to the lower UserId,
-- so every server orders them alike. When the store's page was full, a live player below its last
-- entry may be behind people the page didn't include: they get no rank (left off the list).
function WeeklyLogic.Standings(stored: { Entry }, live: { Entry }, pageSize: number): { Ranked }
	local best: { [number]: Entry } = {}
	local function take(entry: Entry)
		if entry.UserId <= 0 or entry.Points <= 0 then
			return
		end
		local known = best[entry.UserId]
		if not known or entry.Points > known.Points then
			best[entry.UserId] =
				{ UserId = entry.UserId, Points = entry.Points, Name = entry.Name or (known and known.Name) }
		elseif known.Name == nil and entry.Name ~= nil then
			known.Name = entry.Name
		end
	end
	local onPage: { [number]: boolean } = {}
	for _, entry in stored do
		take(entry)
		onPage[entry.UserId] = true
	end
	for _, entry in live do
		take(entry)
	end
	local cutoff = if #stored >= pageSize and #stored > 0 then stored[#stored].Points else -math.huge
	local list: { Ranked } = {}
	for userId, entry in best do
		if onPage[userId] or entry.Points > cutoff then
			table.insert(list, { UserId = userId, Points = entry.Points, Name = entry.Name, Rank = 0 })
		end
	end
	table.sort(list, function(a, b)
		if a.Points ~= b.Points then
			return a.Points > b.Points
		end
		return a.UserId < b.UserId
	end)
	for index, entry in list do
		entry.Rank = index
	end
	return list
end

-- A player's place on the board (nil when they're not on it).
function WeeklyLogic.RankOf(standings: { Ranked }, userId: number): number?
	for _, entry in standings do
		if entry.UserId == userId then
			return entry.Rank
		end
	end
	return nil
end

-- The first `count` entries of a list (a copy).
function WeeklyLogic.Top<T>(list: { T }, count: number): { T }
	local top = {}
	for index = 1, math.min(count, #list) do
		table.insert(top, list[index])
	end
	return top
end

-- The player's own line under the board: "YOU: #14 · 35 PTS", "YOU: 35 PTS" (off the top of the
-- board's list), or how to get on it.
function WeeklyLogic.YouLine(rank: number?, points: number): string
	if points <= 0 then
		return "Play a round to get on the board"
	elseif rank and rank > 0 then
		return `YOU: #{rank} · {WeeklyLogic.Pts(points)}`
	end
	return `YOU: {WeeklyLogic.Pts(points)}`
end

-- The lobby chip's words: "#14 THIS WEEK", or "WEEKLY TOP 10" before the player is on the board.
function WeeklyLogic.ChipText(rank: number?, points: number): string
	if points > 0 and rank and rank > 0 then
		return `#{rank} THIS WEEK`
	end
	return `WEEKLY TOP {WeeklyLogic.BoardSize}`
end

-- "1ST", "2ND", "3RD", "4TH"...
function WeeklyLogic.Ordinal(place: number): string
	local lastTwo = place % 100
	local last = place % 10
	if lastTwo < 11 or lastTwo > 13 then
		if last == 1 then
			return `{place}ST`
		elseif last == 2 then
			return `{place}ND`
		elseif last == 3 then
			return `{place}RD`
		end
	end
	return `{place}TH`
end

return WeeklyLogic

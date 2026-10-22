-- The weekly leaderboard and the Hall of Fame. The owner, asked "If you could do 5 things to keep
-- players addicted what would you do?", got "Weekly leaderboard and Hall of Fame statues of last
-- week's top three" as one of them, then said: "Can you work on all of that? this wont mess with what
-- the other workers are working on right?".
--
-- Points: every finished round pays the people in it by place (Shared/Logic/WeeklyLogic: 1st 10, 2nd
-- 7, 3rd 5, playing 1). Bots never get any. A player's points are in their profile (Weekly = { Week,
-- Points }), for the week the round ended in: a new week (Monday 00:00 UTC) starts them from 0, on
-- their next round, when their profile loads, or when the week turns while they're here.
--
-- The board: one OrderedDataStore per week (PP_Weekly_<week>, key = UserId, value = that week's
-- points). A round only puts the new totals in a queue; a loop of its own writes them a few seconds
-- later, so the round loop never waits on a store:
--   * UpdateAsync keeping the higher number (a late write from a server the player has left can never
--     take points away), one key at a time;
--   * never the same key twice within 7 seconds (Roblox allows one write per key every 6);
--   * only while this minute's request budget has room to spare for the profile saves (DataService);
--   * a failed write is tried again after 10, 20, 40... seconds (two minutes at most); when the
--     server closes, everything still queued gets one last try.
-- The board's top 100 is read about once a minute; this week's top 10 goes to every screen in
-- GameState's HallOfFame (JSON { Week, LastWeek, Top }: see GameState), merged with the newer points
-- of the players on this server, and each player here gets their place in PP_WeeklyRank (0 when they
-- aren't on it). Names come from the players here, or Roblox (UserService) for everyone else.
--
-- The Hall of Fame (World/HallOfFame): statues of last week's top three, read from last week's store.
-- A week's top three is final ten minutes after it ends (every server has saved its last points by
-- then). Finishing a week in the top three earns the HallOfFame medal (MedalService), even for a
-- player who isn't here when the week ends: a week they scored in waits in their profile
-- (Weekly.Pending) until its final top three has been checked, here or on their next visit.
--
-- Toasts, at most one per player per round, once the results have gone (in the lobby): when they
-- get on this week's board, and when they reach the top three. The lobby's chip (Controllers/
-- HallOfFameController) shows every other change.
--
-- Test runs (workspace PP_Harness) never touch the real stores: every read, write and listing of the
-- board goes to an in-memory stand-in instead (LeaderboardService.Harness, for the checks).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage.Shared
local DailyLogic = require(Shared.Logic.DailyLogic)
local GameState = require(Shared.GameState)
local WeeklyLogic = require(Shared.Logic.WeeklyLogic)

local BotRegistry = require(script.Parent.BotRegistry)
local DataService = require(script.Parent.DataService)
local MedalService = require(script.Parent.MedalService)
local Notifier = require(script.Parent.Notifier)
local RoundEvents = require(script.Parent.RoundEvents)
local Telemetry = require(script.Parent.Telemetry)

local HallOfFame = require(script.Parent.Parent.World.HallOfFame)

local LeaderboardService = {}

local STORE_PREFIX = "PP_Weekly_" -- one OrderedDataStore per week
local PAGE = 100 -- the board is read this deep: the top 10 show, the rest give players their place
local TICK = 2 -- the service's loop
local READ_EVERY = 60 -- seconds between reads of this week's board
local LAST_WEEK_EVERY = 600 -- ... and of last week's top three (every minute until it's final)
local SETTLE = 600 -- a week's top three is final this long after it ends
local KEY_COOLDOWN = 7 -- seconds between two writes of one key (Roblox allows one every 6)
local WRITE_RESERVE = 10 -- this minute's write budget kept for the profile saves
local READ_RESERVE = 1
local WRITES_PER_PASS = 20
local FIRST_RETRY = 10 -- a failed write waits this long, then twice as long each time...
local MAX_RETRY = 120 -- ... up to this
local TOAST_WAIT = 30 -- a round's toasts wait at most this long for the lobby

type Queued = { Week: number, UserId: number, Points: number, Failures: number, RetryAt: number }
type Leader = { UserId: number, Name: string, Points: number }

local clock: () -> number = os.time -- the harness fakes the date with Harness.SetClock
local currentWeek = 0
local queue: { [string]: Queued } = {} -- "<week>:<userId>" -> the total to save
local lastWrite: { [string]: number } = {} -- each key's last write (os.clock)
local names: { [number]: string } = {}
local stored: { WeeklyLogic.Entry } = {} -- this week's board as last read
local storedWeek = 0
local readAt = -math.huge
local lastWeekTop: { WeeklyLogic.Entry } = {} -- last week's top three as last read
local lastWeekOf = 0 -- the week that read is of
local lastWeekReadAt = -math.huge
local finalTop: { [number]: { number } } = {} -- week -> its final top three (UserIds)
local standings: { WeeklyLogic.Ranked } = {}
local leaders: { Leader } = {} -- last week's top three, as the statues show them
local published = ""
local statuesShown = ""
local bestRank: { [Player]: number } = {} -- each player's best place on the board this session
local toldStatue: { [Player]: boolean } = {}
local checkedWeek: { [Player]: number } = {} -- the last week whose final top three they were checked against
local started = false

-- Phases when nobody's busy with a round or reading its results: toasts wait for these.
local LOBBY_PHASES = { Waiting = true, Intermission = true, Voting = true }

-- The stores ----------------------------------------------------------------------------------------

-- The in-memory stand-in for test runs: { [store name] = { [key] = points } }, and faults to put in
-- its way (Harness).
local memory: { [string]: { [string]: number } } = {}
local faults = { FailWrites = 0, FailReads = 0, Budget = 1000 }
local stores: { [string]: OrderedDataStore } = {}

local function harness(): boolean
	return workspace:GetAttribute("PP_Harness") == true
end

local function storeName(week: number): string
	return STORE_PREFIX .. week
end

local function budget(kind: Enum.DataStoreRequestType): number
	if harness() then
		return faults.Budget
	end
	local ok, left = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, kind)
	return if ok and type(left) == "number" then left else 0
end

local function canWrite(): boolean
	return budget(Enum.DataStoreRequestType.UpdateAsync) > WRITE_RESERVE
		and budget(Enum.DataStoreRequestType.SetIncrementSortedAsync) > WRITE_RESERVE
end

local function canRead(): boolean
	return budget(Enum.DataStoreRequestType.GetSortedAsync) > READ_RESERVE
end

local function orderedStore(week: number): OrderedDataStore
	local name = storeName(week)
	local store = stores[name]
	if not store then
		store = DataStoreService:GetOrderedDataStore(name)
		stores[name] = store
	end
	return store
end

-- Saves `points` as the player's total for `week`, unless the board already has more. Errors when
-- the store does.
local function writePoints(week: number, userId: number, points: number)
	if harness() then
		if faults.FailWrites > 0 then
			faults.FailWrites -= 1
			error("harness: the store refused the write")
		end
		local board = memory[storeName(week)] or {}
		memory[storeName(week)] = board
		local key = tostring(userId)
		board[key] = math.max(board[key] or 0, points)
		return
	end
	orderedStore(week):UpdateAsync(tostring(userId), function(old)
		if type(old) == "number" and old >= points then
			return nil -- the board has this or more already
		end
		return points
	end)
end

-- The best `count` of `week`, best first (UserId and points). Errors when the store does.
local function readTop(week: number, count: number): { WeeklyLogic.Entry }
	local list: { WeeklyLogic.Entry } = {}
	if harness() then
		if faults.FailReads > 0 then
			faults.FailReads -= 1
			error("harness: the store refused the read")
		end
		local board: { [string]: number } = memory[storeName(week)] or {}
		for key, points in board do
			table.insert(list, { UserId = tonumber(key) :: number, Points = points })
		end
		table.sort(list, function(a, b)
			if a.Points ~= b.Points then
				return a.Points > b.Points
			end
			return a.UserId < b.UserId
		end)
		return WeeklyLogic.Top(list, count)
	end
	local pages = orderedStore(week):GetSortedAsync(false, count)
	for _, item in pages:GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId and userId > 0 and type(item.value) == "number" then
			table.insert(list, { UserId = userId, Points = item.value })
		end
	end
	return list
end

-- Players and their points ------------------------------------------------------------------------

-- A person's profile (never a bot's, nor a Studio test player's negative id).
local function profileOf(player: any): DataService.Profile?
	if BotRegistry.IsBot(player) or type(player.UserId) ~= "number" or player.UserId <= 0 then
		return nil
	end
	return DataService.Get(player)
end

local function weeklyOf(profile: DataService.Profile): WeeklyLogic.Weekly
	return profile.Data.Weekly :: any
end

-- Brings a player's points to this week (a new week starts them from 0).
local function roll(player: Player, profile: DataService.Profile)
	if currentWeek > 0 and WeeklyLogic.Roll(weeklyOf(profile), currentWeek) then
		DataService.Changed(player)
	end
end

local function queueWrite(week: number, userId: number, points: number)
	local key = `{week}:{userId}`
	local queued = queue[key]
	if queued then
		queued.Points = math.max(queued.Points, points)
	else
		queue[key] = { Week = week, UserId = userId, Points = points, Failures = 0, RetryAt = 0 }
	end
end

local function queuedFor(week: number): boolean
	for _, queued in queue do
		if queued.Week == week then
			return true
		end
	end
	return false
end

-- Writes what's queued and due, oldest week first, while the budget allows. Yields.
local function flush(final: boolean?)
	local due = {}
	local now = os.clock()
	for key, queued in queue do
		if final or queued.RetryAt <= now then
			table.insert(due, key)
		end
	end
	table.sort(due, function(a, b)
		local qa, qb = queue[a], queue[b]
		if qa.Week ~= qb.Week then
			return qa.Week < qb.Week
		end
		return qa.UserId < qb.UserId
	end)
	local written = 0
	for _, key in due do
		local queued = queue[key]
		if not queued then
			continue
		end
		if written >= WRITES_PER_PASS and not final then
			break
		end
		local storeKey = `{storeName(queued.Week)}/{queued.UserId}`
		if not final and os.clock() < (lastWrite[storeKey] or -math.huge) + KEY_COOLDOWN then
			continue
		end
		if not canWrite() then
			break
		end
		local points = queued.Points
		lastWrite[storeKey] = os.clock()
		written += 1
		local ok, err = pcall(writePoints, queued.Week, queued.UserId, points)
		if ok then
			-- (A newer total that came in meanwhile stays queued for the next pass.)
			if queue[key] == queued and queued.Points == points then
				queue[key] = nil
			end
		else
			queued.Failures += 1
			local wait = math.min(MAX_RETRY, FIRST_RETRY * 2 ^ (queued.Failures - 1))
			queued.RetryAt = os.clock() + wait * (0.85 + math.random() * 0.3)
			if queued.Failures == 1 or queued.Failures % 10 == 0 then
				Telemetry.Error("Leaderboard", `write {key} (try {queued.Failures}): {err}`)
			end
		end
	end
end

-- Looks up the display names of `ids` this server doesn't know yet (a few at a time). Yields.
local function resolveNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if not names[id] and id > 0 and #missing < 50 then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			if type(info) == "table" and type(info.Id) == "number" and type(info.DisplayName) == "string" then
				names[info.Id] = info.DisplayName
			end
		end
	end
end

-- The board ----------------------------------------------------------------------------------------

-- The players here who have points this week, and totals on their way to the store.
local function liveEntries(week: number): { WeeklyLogic.Entry }
	local live: { WeeklyLogic.Entry } = {}
	for player, profile in DataService.All() do
		local weekly = weeklyOf(profile)
		if profileOf(player) and player.Parent and weekly.Week == week and weekly.Points > 0 then
			table.insert(live, { UserId = player.UserId, Points = weekly.Points, Name = player.DisplayName })
		end
	end
	for _, queued in queue do
		if queued.Week == week then
			table.insert(live, { UserId = queued.UserId, Points = queued.Points })
		end
	end
	return live
end

local function nameOf(userId: number, given: string?): string
	return given or names[userId] or "Player"
end

local function leaderKey(list: { Leader }): string
	local parts = {}
	for _, leader in list do
		table.insert(parts, `{leader.UserId}:{leader.Points}:{leader.Name}`)
	end
	return table.concat(parts, ",")
end

-- Works the board out again from what's known (no waiting) and shows it: GameState, every player's
-- place, the statues.
local function refresh()
	if currentWeek == 0 then
		return
	end
	standings = WeeklyLogic.Standings(if storedWeek == currentWeek then stored else {}, liveEntries(currentWeek), PAGE)
	local top = {}
	for _, entry in WeeklyLogic.Top(standings, WeeklyLogic.BoardSize) do
		table.insert(top, { UserId = entry.UserId, Name = nameOf(entry.UserId, entry.Name), Points = entry.Points })
	end
	local lastWeek = currentWeek - 1
	local last = WeeklyLogic.Standings(
		if lastWeekOf == lastWeek then lastWeekTop else {},
		liveEntries(lastWeek),
		WeeklyLogic.Statues
	)
	leaders = {}
	for _, entry in WeeklyLogic.Top(last, WeeklyLogic.Statues) do
		table.insert(leaders, { UserId = entry.UserId, Name = nameOf(entry.UserId, entry.Name), Points = entry.Points })
	end

	local json = HttpService:JSONEncode({ Week = currentWeek, LastWeek = leaders, Top = top })
	if json ~= published then
		published = json
		GameState.Set("HallOfFame", json)
	end
	for player in DataService.All() do
		if profileOf(player) and player.Parent then
			local rank = WeeklyLogic.RankOf(standings, player.UserId) or 0
			if player:GetAttribute("PP_WeeklyRank") ~= rank then
				player:SetAttribute("PP_WeeklyRank", rank)
			end
		end
	end
	local key = leaderKey(leaders)
	if key ~= statuesShown then
		statuesShown = key
		HallOfFame.SetStatues(leaders)
	end
end

local function idsOf(list: { WeeklyLogic.Entry }, count: number): { number }
	local ids = {}
	for index = 1, math.min(count, #list) do
		table.insert(ids, list[index].UserId)
	end
	return ids
end

-- Reads this week's board from the store, and the names on its top 10. Yields.
local function readBoard()
	if not canRead() then
		return
	end
	readAt = os.clock()
	local week = currentWeek
	local ok, result = pcall(readTop, week, PAGE)
	if not ok then
		Telemetry.Error("Leaderboard", `read week {week}: {result}`)
		return
	end
	if week == currentWeek then
		stored, storedWeek = result, week
	end
	resolveNames(idsOf(result, WeeklyLogic.BoardSize))
end

-- Reads last week's top three from the store (once it's final, it's that week's final top three).
-- Yields.
local function readLastWeek()
	if not canRead() then
		return
	end
	lastWeekReadAt = os.clock()
	local week = currentWeek - 1
	local settled = WeeklyLogic.Settled(week, clock(), SETTLE) and not queuedFor(week)
	local ok, result = pcall(readTop, week, WeeklyLogic.Statues)
	if not ok then
		Telemetry.Error("Leaderboard", `read week {week}: {result}`)
		return
	end
	if week == currentWeek - 1 then
		lastWeekTop, lastWeekOf = result, week
		if settled then
			finalTop[week] = idsOf(result, WeeklyLogic.Statues)
		end
	end
	resolveNames(idsOf(result, WeeklyLogic.Statues))
end

-- Week `week`'s final top three (UserIds), read once if this server hasn't yet; nil while it can't
-- be known (not settled, saves still queued here, or the store didn't answer). Yields.
local function finalTopOf(week: number): { number }?
	if finalTop[week] then
		return finalTop[week]
	end
	if not WeeklyLogic.Settled(week, clock(), SETTLE) or queuedFor(week) or not canRead() then
		return nil
	end
	local ok, result = pcall(readTop, week, WeeklyLogic.Statues)
	if not ok then
		return nil
	end
	finalTop[week] = idsOf(result, WeeklyLogic.Statues)
	return finalTop[week]
end

-- Gives the HallOfFame medal for every week of the player's that has ended in the top three, once
-- that's known (the weeks still to check wait in their profile). Yields.
local function checkMedals(player: Player)
	local profile = profileOf(player)
	if not profile then
		return
	end
	local weekly = weeklyOf(profile)
	local changed, earned = false, false
	local pending: { number } = table.clone(weekly.Pending or {})
	for _, week in pending do
		local top = finalTopOf(week)
		if top and DataService.Get(player) == profile then
			earned = earned or table.find(top, player.UserId) ~= nil
			changed = WeeklyLogic.ClearPending(weekly, week) or changed
		end
	end
	-- Last week's, also for a save that never remembered the week.
	local lastWeek = currentWeek - 1
	local last = finalTop[lastWeek]
	if last then
		checkedWeek[player] = lastWeek
		earned = earned or table.find(last, player.UserId) ~= nil
	end
	if earned then
		MedalService.Award(player, "HallOfFame")
	end
	if changed then
		DataService.Changed(player)
	end
end

-- Whether checkMedals has anything to do for a player now: a week of theirs whose top three is
-- final, or last week's final top three that they haven't been checked against yet.
local function medalsDue(player: Player, profile: DataService.Profile): boolean
	local pending: { number } = weeklyOf(profile).Pending or {}
	for _, week in pending do
		if WeeklyLogic.Settled(week, clock(), SETTLE) then
			return true
		end
	end
	return finalTop[currentWeek - 1] ~= nil and checkedWeek[player] ~= currentWeek - 1
end

-- Tells a player whose statue stands in the Hall of Fame, once a visit (in the lobby).
local function tellStatue(player: Player)
	if toldStatue[player] or not LOBBY_PHASES[GameState.Get("Phase") or ""] then
		return
	end
	for place, leader in leaders do
		if leader.UserId == player.UserId then
			toldStatue[player] = true
			Notifier.Send(
				player,
				`🏆 You were #{place} last week! Your statue stands in the HALL OF FAME, by the podium.`,
				"reward",
				7
			)
			return
		end
	end
end

-- The week turned (or this is the first look): everyone here starts the new week, and both boards
-- are read again.
local function setWeek(week: number)
	if week == currentWeek then
		return
	end
	currentWeek = week
	stored, storedWeek = {}, week
	readAt = -math.huge
	lastWeekReadAt = -math.huge
	for player, profile in DataService.All() do
		if profileOf(player) then
			roll(player, profile)
		end
	end
end

-- Rounds -------------------------------------------------------------------------------------------

-- A round's toasts, once the results card has gone (it covers them): one at most per player.
local function toastLater(gains: { [Player]: { Points: number, First: boolean } })
	task.spawn(function()
		local deadline = os.clock() + TOAST_WAIT
		while os.clock() < deadline and not LOBBY_PHASES[GameState.Get("Phase") or ""] do
			task.wait(0.25)
		end
		task.wait(0.5)
		for player, gain in gains do
			if not player.Parent or not profileOf(player) then
				continue
			end
			local rank = WeeklyLogic.RankOf(standings, player.UserId)
			local best = bestRank[player]
			if rank and rank <= WeeklyLogic.Statues and (best == nil or best > WeeklyLogic.Statues) then
				Notifier.Send(
					player,
					`🏆 #{rank} THIS WEEK! Hold a top-3 spot until Monday for a statue in the HALL OF FAME.`,
					"reward",
					6
				)
			elseif gain.First then
				Notifier.Send(
					player,
					`📈 +{gain.Points} weekly points! You're {if rank then `#{rank} ` else ""}on this week's board.`,
					"success",
					5
				)
			end
			if rank and (best == nil or rank < best) then
				bestRank[player] = rank
			end
		end
	end)
end

local function onRoundFinished(_definition, placed, _winningTeam)
	local week = DailyLogic.WeekNumber(clock())
	setWeek(math.max(week, currentWeek))
	local worst = 0
	for _, item in placed do
		worst = math.max(worst, item.Place)
	end
	local gains: { [Player]: { Points: number, First: boolean } } = {}
	for _, item in placed do
		local player = (item.Entry :: any).Player
		local profile = player and profileOf(player)
		if not profile or not player.Parent then
			continue
		end
		local weekly = weeklyOf(profile)
		local first = weekly.Week < week or weekly.Points == 0
		local points = WeeklyLogic.PointsFor(item.Place, worst)
		local savedWeek, total = WeeklyLogic.Add(weekly, week, points)
		names[player.UserId] = player.DisplayName
		queueWrite(savedWeek, player.UserId, total)
		DataService.Changed(player)
		gains[player] = { Points = points, First = first }
	end
	if next(gains) then
		refresh()
		toastLater(gains)
	end
end

-- A profile that just loaded: its points brought to this week, its weeks still to check checked.
local function onProfileLoaded(player: Player)
	-- (The event's own copy of the profile is a copy: work on the real one.)
	if not profileOf(player) then
		return
	end
	if currentWeek > 0 then
		local profile = profileOf(player) :: DataService.Profile
		roll(player, profile)
		names[player.UserId] = player.DisplayName
		refresh()
	end
	task.spawn(checkMedals, player)
	task.delay(9, function()
		if player.Parent then
			tellStatue(player)
		end
	end)
end

-- One pass of the loop: the week, the store's boards, the queue, the medals. Yields.
local function step()
	setWeek(math.max(DailyLogic.WeekNumber(clock()), currentWeek))
	if os.clock() >= readAt + READ_EVERY then
		readBoard()
	end
	-- Last week's top three: every minute until it's final, then now and then.
	local final = finalTop[currentWeek - 1] ~= nil
	if os.clock() >= lastWeekReadAt + (if final then LAST_WEEK_EVERY else READ_EVERY) then
		readLastWeek()
	end
	flush()
	refresh()
	for player, profile in DataService.All() do
		if profileOf(player) and player.Parent then
			if medalsDue(player, profile) then
				checkMedals(player)
			end
			tellStatue(player)
		end
	end
end

function LeaderboardService.Init()
	RoundEvents.Finished:Connect(onRoundFinished)
	DataService.ProfileLoaded:Connect(onProfileLoaded)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		bestRank[player] = nil
		toldStatue[player] = nil
		checkedWeek[player] = nil
	end)
	pcall(function()
		game:BindToClose(function()
			-- Everything still queued gets one last try (DataService saves the profiles meanwhile).
			if next(queue) then
				flush(true)
			end
		end)
	end)
end

-- The first look: this week, and the players already here.
local function begin(): boolean
	if started then
		return false
	end
	started = true
	setWeek(DailyLogic.WeekNumber(clock()))
	for player in DataService.All() do
		task.spawn(onProfileLoaded, player)
	end
	refresh()
	return true
end

function LeaderboardService.Start()
	if not begin() then
		return
	end
	while true do
		local ok, err = pcall(step)
		if not ok then
			Telemetry.Error("Leaderboard", tostring(err))
		end
		task.wait(TICK)
	end
end

-- Tools only (tools/checks/weekly_check.luau, under PP_Harness): the in-memory store, faults to put
-- in its way, a fake date, one pass of the loop, and what the service knows.
LeaderboardService.Harness = {
	Memory = function(week: number): { [string]: number }
		local name = storeName(week)
		memory[name] = memory[name] or {}
		return memory[name]
	end,
	Faults = faults,
	SetClock = function(fake: () -> number)
		clock = fake
	end,
	Begin = begin, -- what Start does before its loop (a check then calls Step itself)
	Step = step,
	ForgetReads = function()
		readAt, lastWeekReadAt = -math.huge, -math.huge
	end,
	ForgetWrites = function() -- as if every key's cooldown had passed
		table.clear(lastWrite)
	end,
	RetryNow = function() -- as if every failed write's wait was over
		for _, queued in queue do
			queued.RetryAt = 0
		end
	end,
	State = function(): { [string]: any }
		local queued = {}
		for key, entry in queue do
			queued[key] = { Points = entry.Points, Failures = entry.Failures }
		end
		local finals = {}
		for week, ids in finalTop do
			finals[tostring(week)] = ids
		end
		return {
			Week = currentWeek,
			Queue = queued,
			Standings = WeeklyLogic.Top(standings, 12),
			Leaders = leaders,
			Final = finals,
			Published = published,
		}
	end,
}

return LeaderboardService

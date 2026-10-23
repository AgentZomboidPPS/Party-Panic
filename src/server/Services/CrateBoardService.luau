-- Top Unboxers, the crate season's leaderboard (the crate seasons' design: "Every crate opened counts
-- toward the Top Unboxers board ... Season and weekly boards in the menu, the season top 10 on the
-- lobby board, and your own rank always shown", and the first player in the world to get the title
-- "is named on the Top Unboxers board for the rest of the season"; owner: "Also do all of your
-- ideas."). Services/CrateService tells it about every open and every pet or title found.
--
-- The boards count crates opened:
--   * this season (an OrderedDataStore per season, PP_Crates_<season>: key UserId, value its total);
--   * this week (PP_CratesWeek_<season>_<week>; weeks start Monday 00:00 UTC, Logic/DailyLogic);
--   * this server (since it started: only the players here, nothing stored).
-- Writes go in a queue that a loop of its own works through, like the weekly board's (Services/
-- LeaderboardService): UpdateAsync keeping the higher number, one key at a time, never the same key
-- twice in 7 seconds, only while this minute's request budget leaves room for the profile saves, a
-- failed write tried again after 10, 20, 40... seconds (two minutes at most), and everything left
-- gets one last try when the server closes. The top 100 of each is read about once a minute; the top
-- 10s go to every screen in GameState's CrateBoard (JSON: Season, Week, Top, WeekTop, Server, Firsts,
-- each row { UserId, Name, Opened }), merged with the newer totals of the players here, and each
-- player gets their places (PP_CrateRank, PP_CrateWeekRank: 0 when they aren't in the top 100).
--
-- First in the world: one DataStore key per season (PP_CrateFirsts, key = the season) holds, for
-- each pet and the title, the first person to find it ({ UserId, Name, Day }). Finding one writes it
-- if nobody's there yet (UpdateAsync, so two servers can't both be first). CrateService claims it
-- the moment the crate is rolled (Claim), so the store has answered by the time the reel ends and
-- the banner can say FIRST IN THE WORLD (FoundFirst).
--
-- The title on every server: MessagingService topic PP_CrateTitle ({ Name, UserId, Item, JobId });
-- every other server puts it on its screens as a banner ("on another server").
--
-- Test runs (workspace PP_Harness) never touch the real stores or other servers: an in-memory
-- stand-in takes every read and write (CrateBoardService.Harness), and the message only goes to
-- this server's log.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage.Shared
local DailyLogic = require(Shared.Logic.DailyLogic)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local Seasons = require(Shared.Seasons)
local WeeklyLogic = require(Shared.Logic.WeeklyLogic)

local BotRegistry = require(script.Parent.BotRegistry)
local DataService = require(script.Parent.DataService)
local Telemetry = require(script.Parent.Telemetry)

local CrateBoardService = {}

local TOPIC = "PP_CrateTitle"
local FIRSTS_STORE = "PP_CrateFirsts"
local PAGE = 100
local SHOWN = 10
local TICK = 2
local READ_EVERY = 60
local FIRSTS_EVERY = 300
local KEY_COOLDOWN = 7
local WRITE_RESERVE = 10
local READ_RESERVE = 1
local WRITES_PER_PASS = 20
local FIRST_RETRY = 10
local MAX_RETRY = 120

type Queued = { Store: string, UserId: number, Opened: number, Failures: number, RetryAt: number }
type Row = { UserId: number, Name: string, Opened: number }
type First = { UserId: number, Name: string, Day: number }

local remote = Remotes.Get("Crate")
local season = Seasons.CurrentSeason()
local queue: { [string]: Queued } = {} -- "<store>/<userId>" -> the total to save
local lastWrite: { [string]: number } = {}
local names: { [number]: string } = {}
local stored: { [string]: { WeeklyLogic.Entry } } = {} -- store name -> its top 100 as last read
local readAt = -math.huge
local firsts: { [string]: First } = {} -- item id -> the first to find it (this season)
local firstsReadAt = -math.huge
local serverOpened: { [number]: { Name: string, Opened: number } } = {} -- this server, since it started
local published = ""
local dirty = true

-- The in-memory stand-in for test runs.
local memory: { [string]: { [string]: any } } = {}
local messages: { { [string]: any } } = {}
local ordered: { [string]: OrderedDataStore } = {}

local function harness(): boolean
	return workspace:GetAttribute("PP_Harness") == true
end

local function seasonStore(): string
	return `PP_Crates_{season.Id}`
end

local function weekStore(week: number): string
	return `PP_CratesWeek_{season.Id}_{week}`
end

local function thisWeek(): number
	return DailyLogic.WeekNumber(os.time())
end

local function budget(kind: Enum.DataStoreRequestType): number
	if harness() then
		return 1000
	end
	local ok, left = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, kind)
	return if ok and type(left) == "number" then left else 0
end

local function orderedStore(name: string): OrderedDataStore
	local store = ordered[name]
	if not store then
		store = DataStoreService:GetOrderedDataStore(name)
		ordered[name] = store
	end
	return store
end

local function writeTotal(name: string, userId: number, opened: number)
	if harness() then
		local board = memory[name] or {}
		memory[name] = board
		local key = tostring(userId)
		board[key] = math.max(board[key] or 0, opened)
		return
	end
	orderedStore(name):UpdateAsync(tostring(userId), function(old)
		if type(old) == "number" and old >= opened then
			return nil
		end
		return opened
	end)
end

local function readTop(name: string): { WeeklyLogic.Entry }
	local list: { WeeklyLogic.Entry } = {}
	if harness() then
		local board: { [string]: any } = memory[name] or {}
		for key, opened in board do
			table.insert(list, { UserId = tonumber(key) :: number, Points = opened })
		end
		table.sort(list, function(a, b)
			return if a.Points ~= b.Points then a.Points > b.Points else a.UserId < b.UserId
		end)
		return WeeklyLogic.Top(list, PAGE)
	end
	local pages = orderedStore(name):GetSortedAsync(false, PAGE)
	for _, item in pages:GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId and userId > 0 and type(item.value) == "number" then
			table.insert(list, { UserId = userId, Points = item.value })
		end
	end
	return list
end

local function queueWrite(name: string, userId: number, opened: number)
	local key = `{name}/{userId}`
	local queued = queue[key]
	if queued then
		queued.Opened = math.max(queued.Opened, opened)
	else
		queue[key] = { Store = name, UserId = userId, Opened = opened, Failures = 0, RetryAt = 0 }
	end
end

-- Writes what's queued and due while the budget allows. Yields.
local function flush(final: boolean?)
	local written = 0
	for key, queued in table.clone(queue) do
		if not final and (queued.RetryAt > os.clock() or written >= WRITES_PER_PASS) then
			continue
		end
		if not final and os.clock() < (lastWrite[key] or -math.huge) + KEY_COOLDOWN then
			continue
		end
		if budget(Enum.DataStoreRequestType.UpdateAsync) <= WRITE_RESERVE then
			break
		end
		local opened = queued.Opened
		lastWrite[key] = os.clock()
		written += 1
		local ok, err = pcall(writeTotal, queued.Store, queued.UserId, opened)
		if ok then
			if queue[key] == queued and queued.Opened == opened then
				queue[key] = nil
			end
		else
			queued.Failures += 1
			local wait = math.min(MAX_RETRY, FIRST_RETRY * 2 ^ (queued.Failures - 1))
			queued.RetryAt = os.clock() + wait * (0.85 + math.random() * 0.3)
			if queued.Failures == 1 or queued.Failures % 10 == 0 then
				Telemetry.Error("CrateBoard", `write {key} (try {queued.Failures}): {err}`)
			end
		end
	end
end

local function resolveNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if not names[id] and id > 0 and #missing < 50 then
			table.insert(missing, id)
		end
	end
	if #missing == 0 or harness() then
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

-- The players here and their totals for a board (season or this week), with what's queued.
local function liveEntries(weekly: boolean): { WeeklyLogic.Entry }
	local live: { WeeklyLogic.Entry } = {}
	local week = thisWeek()
	for player, profile in DataService.All() do
		if BotRegistry.IsBot(player) or not player.Parent or player.UserId <= 0 then
			continue
		end
		local progress = (profile.Data :: any).Seasons[season.Id]
		if type(progress) == "table" then
			local opened = if weekly
				then (if progress.Week == week then progress.WeekOpened else 0)
				else progress.Opened
			if opened and opened > 0 then
				table.insert(live, { UserId = player.UserId, Points = opened, Name = player.DisplayName })
			end
		end
	end
	return live
end

local function rowsOf(standings: { WeeklyLogic.Ranked }): { Row }
	local rows = {}
	for _, entry in WeeklyLogic.Top(standings, SHOWN) do
		table.insert(
			rows,
			{ UserId = entry.UserId, Name = entry.Name or names[entry.UserId] or "Player", Opened = entry.Points }
		)
	end
	return rows
end

-- Works the boards out again from what's known (no waiting) and shows them.
local function refresh()
	dirty = false
	local week = thisWeek()
	local seasonBoard = WeeklyLogic.Standings(stored[seasonStore()] or {}, liveEntries(false), PAGE)
	local weekBoard = WeeklyLogic.Standings(stored[weekStore(week)] or {}, liveEntries(true), PAGE)
	local server: { WeeklyLogic.Entry } = {}
	for userId, entry in serverOpened do
		table.insert(server, { UserId = userId, Points = entry.Opened, Name = entry.Name })
	end
	local serverBoard = WeeklyLogic.Standings({}, server, SHOWN)
	local firstRows = {}
	for item, first in firsts do
		firstRows[item] = { UserId = first.UserId, Name = first.Name, Day = first.Day }
	end
	local json = HttpService:JSONEncode({
		Season = season.Id,
		Week = week,
		Top = rowsOf(seasonBoard),
		WeekTop = rowsOf(weekBoard),
		Server = rowsOf(serverBoard),
		Firsts = firstRows,
	})
	if json ~= published then
		published = json
		GameState.Set("CrateBoard", json)
	end
	for _, player in Players:GetPlayers() do
		if not BotRegistry.IsBot(player) then
			local rank = WeeklyLogic.RankOf(seasonBoard, player.UserId) or 0
			local weekRank = WeeklyLogic.RankOf(weekBoard, player.UserId) or 0
			if player:GetAttribute("PP_CrateRank") ~= rank then
				player:SetAttribute("PP_CrateRank", rank)
			end
			if player:GetAttribute("PP_CrateWeekRank") ~= weekRank then
				player:SetAttribute("PP_CrateWeekRank", weekRank)
			end
		end
	end
end

local function readBoards()
	if budget(Enum.DataStoreRequestType.GetSortedAsync) <= READ_RESERVE + 1 then
		return
	end
	readAt = os.clock()
	for _, name in { seasonStore(), weekStore(thisWeek()) } do
		local ok, result = pcall(readTop, name)
		if ok then
			stored[name] = result
			local ids = {}
			for index = 1, math.min(SHOWN, #result) do
				table.insert(ids, result[index].UserId)
			end
			resolveNames(ids)
		else
			Telemetry.Error("CrateBoard", `read {name}: {result}`)
		end
	end
	dirty = true
end

-- First in the world -------------------------------------------------------------------------------

local function firstsStore(): DataStore
	return DataStoreService:GetDataStore(FIRSTS_STORE)
end

local function readFirsts()
	firstsReadAt = os.clock()
	local ok, result = pcall(function()
		if harness() then
			return memory[FIRSTS_STORE] and memory[FIRSTS_STORE][season.Id]
		end
		return firstsStore():GetAsync(season.Id)
	end)
	if ok and type(result) == "table" then
		for item, first in result do
			if type(item) == "string" and type(first) == "table" and type(first.UserId) == "number" then
				firsts[item] = { UserId = first.UserId, Name = tostring(first.Name), Day = tonumber(first.Day) or 0 }
			end
		end
		dirty = true
	elseif not ok then
		Telemetry.Error("CrateBoard", `read firsts: {result}`)
	end
end

-- Writes `player` as the first to find `item` unless someone already is. Yields. True when they are.
local function claimFirst(player: Player, item: string): boolean
	local mine = { UserId = player.UserId, Name = player.DisplayName, Day = DailyLogic.DayNumber(os.time()) }
	local winner: First? = nil
	local ok, err = pcall(function()
		if harness() then
			local all = memory[FIRSTS_STORE] or {}
			memory[FIRSTS_STORE] = all
			local list = all[season.Id] or {}
			all[season.Id] = list
			list[item] = list[item] or mine
			winner = list[item]
			return
		end
		firstsStore():UpdateAsync(season.Id, function(old)
			local list = if type(old) == "table" then old else {}
			local current = list[item]
			if type(current) == "table" and type(current.UserId) == "number" then
				winner = current
				return nil
			end
			list[item] = mine
			winner = mine
			return list
		end)
	end)
	if not ok then
		Telemetry.Error("CrateBoard", `claim first {item}: {err}`)
		return false
	end
	local found = winner :: First?
	if found then
		firsts[item] = { UserId = found.UserId, Name = found.Name, Day = found.Day }
		dirty = true
		return found.UserId == player.UserId
	end
	return false
end

local claiming: { [string]: boolean } = {} -- "<item>/<userId>" claims still on their way

-- CrateService: `player` just rolled `item` (a pet or the title): claim being the first in the world
-- to find it, if this server doesn't know of anyone already. Doesn't wait.
function CrateBoardService.Claim(player: Player, seasonId: string, item: string)
	if seasonId ~= season.Id or BotRegistry.IsBot(player) or firsts[item] then
		return
	end
	local key = `{item}/{player.UserId}`
	claiming[key] = true
	task.spawn(function()
		claimFirst(player, item)
		claiming[key] = nil
	end)
end

-- At the reveal: whether `player` is the first in the world to find `item` (waits a moment for a
-- claim still on its way).
function CrateBoardService.FoundFirst(player: Player, seasonId: string, item: string): boolean
	if seasonId ~= season.Id then
		return false
	end
	local key = `{item}/{player.UserId}`
	local deadline = os.clock() + 1.5
	while claiming[key] and os.clock() < deadline do
		task.wait(0.05)
	end
	local known = firsts[item]
	return known ~= nil and known.UserId == player.UserId
end

-- Every other server ------------------------------------------------------------------------------

function CrateBoardService.TellEveryServer(name: string, userId: number, item: string)
	local message = { Name = name, UserId = userId, Item = item, JobId = game.JobId, Season = season.Id }
	if harness() then
		table.insert(messages, message)
		return
	end
	task.spawn(function()
		local ok, err = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, HttpService:JSONEncode(message))
		if not ok then
			Telemetry.Error("CrateBoard", `publish title: {err}`)
		end
	end)
end

local function onMessage(packet: any)
	local ok, message = pcall(HttpService.JSONDecode, HttpService, packet.Data)
	if not ok or type(message) ~= "table" or message.JobId == game.JobId then
		return
	end
	if type(message.Name) ~= "string" or type(message.Item) ~= "string" or not Seasons.ItemById[message.Item] then
		return
	end
	remote:FireAllClients("Banner", {
		Name = string.sub(message.Name, 1, 40),
		UserId = tonumber(message.UserId) or 0,
		Item = message.Item,
		Tier = "Title",
		Season = tostring(message.Season),
		Elsewhere = true,
	})
end

-- Opens ------------------------------------------------------------------------------------------

-- CrateService: `player` opened `count` crates, which makes `opened` this season and `weekOpened`
-- this week.
function CrateBoardService.Opened(player: Player, seasonId: string, opened: number, weekOpened: number, count: number)
	if BotRegistry.IsBot(player) or player.UserId <= 0 or seasonId ~= season.Id then
		return
	end
	queueWrite(seasonStore(), player.UserId, opened)
	queueWrite(weekStore(thisWeek()), player.UserId, weekOpened)
	local here = serverOpened[player.UserId] or { Name = player.DisplayName, Opened = 0 }
	here.Opened += count
	serverOpened[player.UserId] = here
	names[player.UserId] = player.DisplayName
	dirty = true
end

-- Test runs: the in-memory stores and the messages sent.
CrateBoardService.Harness = {
	Memory = memory,
	Messages = messages,
	Refresh = function()
		readBoards()
		readFirsts()
		flush(true)
		refresh()
	end,
}

function CrateBoardService.Init()
	if not harness() then
		task.spawn(function()
			local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, onMessage)
			if not ok then
				Telemetry.Error("CrateBoard", `subscribe: {err}`)
			end
		end)
	end
	game:BindToClose(function()
		flush(true)
	end)
	DataService.ProfileLoaded:Connect(function()
		dirty = true
	end)
end

function CrateBoardService.Start()
	readFirsts()
	readBoards()
	refresh()
	while true do
		task.wait(TICK)
		flush()
		if os.clock() - readAt >= READ_EVERY then
			readBoards()
		end
		if os.clock() - firstsReadAt >= FIRSTS_EVERY then
			readFirsts()
		end
		if dirty then
			refresh()
		end
	end
end

return CrateBoardService

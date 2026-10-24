-- Merging quiet servers (owner: "Is there a way to merge severs automatically that are getting
-- low?"): a server with only a few real players moves them, together, to a busier one, so people
-- play with people instead of a lobby of bots. The rules are Shared/Logic/ServerMerge.
--
--   * Every public server lists itself every Config.Merge.Interval seconds in a memory store sorted
--     map ("PP_Servers": its JobId, real players, place version), each entry kept a few intervals,
--     and takes itself off when it closes. Private servers are never listed and never move anyone.
--   * At the start of each lobby (Intermission) it counts its real players. Quiet (Config.Merge.Low
--     or fewer, and someone) for Config.Merge.Lobbies lobbies in a row, it looks for the fullest
--     server on its version with room for everyone and a seat to spare, bigger than it (never a
--     smaller one, so quiet servers don't swap people). Someone who pressed STAY isn't asked again
--     on this server.
--   * Found one: everyone sees a Countdown-second card, "Moving you to a busier party!", with STAY
--     (the "ServerMove" remote: server to client ("Countdown", seconds) and ("Cancel"); client to
--     server ("Stay")). Then everyone who saw the card and didn't press STAY goes in one teleport,
--     with their parties (ServerMerge.Parties), which PartyService puts back together as they
--     arrive, and a welcome toast. A round starting first, nobody left to move, or the teleport
--     failing calls it off (people stay); either way the server waits Config.Merge.Cooldown before
--     trying again, and a server people just moved to waits as long before moving anyone on.
--   * Who moved, and with whom, is written by the server to a memory store ("PP_Moves", one entry a
--     move, a few minutes); the teleport data carries only that entry's key. Teleport data passes
--     through the player's device, so the arriving server believes the entry, never the data: a
--     made-up "I'm in their party" gets nobody into a party they weren't invited to.
--   * A server isn't listed while its countdown runs (nobody moves to a server that's emptying).
--   * Off with Config.Merge.Enabled = false; never in Studio or on a test run (workspace PP_Harness).
--
-- Progress is safe through the move: DataService saves and releases the profile as a player leaves,
-- and the next server's load waits for that lock (its session lock).

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local ServerMerge = require(Shared.Logic.ServerMerge)

local Notifier = require(script.Parent.Notifier)
local PartyService = require(script.Parent.PartyService)
local RateLimiter = require(script.Parent.RateLimiter)
local Telemetry = require(script.Parent.Telemetry)

local MergeService = {}

local MAP_NAME = "PP_Servers"
local MOVES_NAME = "PP_Moves"
local LIST_SIZE = 100 -- servers read when looking for somewhere to go
local MOVE_KEEP = 300 -- seconds a move's entry is kept (the teleport takes seconds)

local remote: RemoteEvent? = nil
local streak = 0 -- quiet lobbies in a row
local nextTry = 0 -- os.clock() before which it doesn't try again (after a try)
local moving = false -- a countdown is running
local staying: { [Player]: boolean } = {}
local stayed: { [Player]: boolean } = {} -- pressed STAY once: never asked again on this server
local sent: { [Player]: boolean } = {} -- in the teleport now (a failed one tells them)

local function active(): boolean
	return Config.Merge.Enabled
		and not RunService:IsStudio()
		and workspace:GetAttribute("PP_Harness") ~= true
		and game.PrivateServerId == ""
end

local function map(): MemoryStoreSortedMap
	return MemoryStoreService:GetSortedMap(MAP_NAME)
end

-- The real players here (bots aren't Players).
local function people(): { Player }
	return Players:GetPlayers()
end

-- The people here who'd be asked to move (not those who said STAY before).
local function askable(): { Player }
	local asked = {}
	for _, player in people() do
		if not stayed[player] then
			table.insert(asked, player)
		end
	end
	return asked
end

-- Lists this server (or, `gone` or during a countdown, takes it off).
local function list(gone: boolean?)
	local count = #people()
	pcall(function()
		if gone or moving or count == 0 then
			map():RemoveAsync(game.JobId)
		else
			local entry = { Count = count, Version = game.PlaceVersion }
			map():SetAsync(game.JobId, entry, Config.Merge.Interval * 3, count)
		end
	end)
end

-- The listed servers (this one too).
local function servers(): { ServerMerge.Entry }
	local entries: { ServerMerge.Entry } = {}
	local ok, items = pcall(function()
		return map():GetRangeAsync(Enum.SortDirection.Descending, LIST_SIZE)
	end)
	if not ok or type(items) ~= "table" then
		return entries
	end
	for _, item in items do
		local value = item.value
		if type(value) == "table" and type(value.Count) == "number" and type(value.Version) == "number" then
			table.insert(entries, { JobId = item.key, Count = value.Count, Version = value.Version })
		end
	end
	return entries
end

local function tell(player: Player, ...: any)
	if remote and player.Parent then
		(remote :: RemoteEvent):FireClient(player, ...)
	end
end

local function lobby(): boolean
	local phase = GameState.Get("Phase")
	return phase == "Intermission" or phase == "Waiting" or phase == "Voting"
end

-- The countdown, then the move (everyone who saw it and didn't press STAY), or calling it off.
local function move(target: ServerMerge.Entry)
	moving = true
	staying = {}
	nextTry = os.clock() + Config.Merge.Cooldown
	task.spawn(list)
	local told = askable() -- (someone joining during the countdown never saw it, so stays)
	Telemetry.ServerEvent("MergeOffer", { Count = #told, To = target.Count })
	for _, player in told do
		tell(player, "Countdown", Config.Merge.Countdown)
	end
	local deadline = os.clock() + Config.Merge.Countdown
	while os.clock() < deadline and lobby() do
		task.wait(0.25)
	end
	local movers: { Player } = {}
	for _, player in told do
		if player.Parent and not staying[player] then
			table.insert(movers, player)
		end
	end
	moving = false
	if not lobby() or #movers == 0 then
		for _, player in told do
			tell(player, "Cancel")
		end
		return
	end
	local ids = {}
	for _, player in movers do
		table.insert(ids, player.UserId)
	end
	local byId: { [number]: Player } = {}
	for _, player in movers do
		byId[player.UserId] = player
	end
	local parties = ServerMerge.Parties(ids, function(userId)
		local player = byId[userId]
		return if player then PartyService.MembersOf(player) else nil
	end)
	local key = HttpService:GenerateGUID(false)
	local ok, err = pcall(function()
		local entry = { To = target.JobId, Movers = ids, Parties = parties }
		MemoryStoreService:GetSortedMap(MOVES_NAME):SetAsync(key, entry, MOVE_KEEP)
		local options = Instance.new("TeleportOptions")
		options.ServerInstanceId = target.JobId
		options:SetTeleportData({ Merge = key })
		for _, player in movers do
			sent[player] = true
		end
		TeleportService:TeleportAsync(game.PlaceId, movers, options)
	end)
	if ok then
		Telemetry.ServerEvent("Merged", { Count = #movers, To = target.Count })
	else
		Telemetry.Error("Merge", tostring(err))
		for _, player in movers do
			sent[player] = nil
			tell(player, "Cancel")
			Notifier.Send(player, "Couldn't move you this time - the party goes on here!", "info", 4)
		end
	end
end

-- At the start of a lobby: one more quiet lobby, or not, and the move once it's been quiet enough.
local function onLobby()
	local count = #people()
	streak = ServerMerge.Streak(streak, count, Config.Merge.Low)
	if moving or streak < Config.Merge.Lobbies or os.clock() < nextTry then
		return
	end
	local asked = #askable()
	if asked == 0 then
		return
	end
	local me: ServerMerge.Entry = { JobId = game.JobId, Count = count, Version = game.PlaceVersion }
	local target = ServerMerge.PickTarget(servers(), me, asked, Config.Session.MaxPlayers)
	if target then
		streak = 0
		task.spawn(move, target)
	end
end

-- Someone who came from a quieter server (as that server's entry says, not their teleport data):
-- welcome, and back in their party when a mate is here.
local function onArrival(player: Player)
	local ok, joinData = pcall(player.GetJoinData, player)
	local data = if ok and type(joinData) == "table" then joinData.TeleportData else nil
	local key = if type(data) == "table" then data.Merge else nil
	if type(key) ~= "string" or #key > 64 then
		return
	end
	local found, entry = pcall(function()
		return MemoryStoreService:GetSortedMap(MOVES_NAME):GetAsync(key)
	end)
	if
		not found
		or type(entry) ~= "table"
		or entry.To ~= game.JobId
		or type(entry.Movers) ~= "table"
		or not table.find(entry.Movers, player.UserId)
		or not player.Parent
	then
		return
	end
	nextTry = math.max(nextTry, os.clock() + Config.Merge.Cooldown) -- (they just moved: not again soon)
	streak = 0
	task.delay(4, function()
		if player.Parent then
			Notifier.Send(player, "🎉 You moved to a busier party - have fun!", "success", 5)
		end
	end)
	local parties = if type(entry.Parties) == "table" then entry.Parties else {}
	local mate = ServerMerge.MateHere(parties, player.UserId, function(userId)
		local other = Players:GetPlayerByUserId(userId)
		return other ~= nil and other ~= player
	end)
	if mate then
		PartyService.Reunite(player, mate)
	end
end

function MergeService.Init()
	local limit = Config.RateLimits.ServerMove
	local limiter = RateLimiter.new(limit[1], limit[2])
	local moveRemote = Remotes.Get("ServerMove")
	remote = moveRemote
	moveRemote.OnServerEvent:Connect(function(player, action)
		if action == "Stay" and moving and limiter:Check(player) then
			staying[player] = true
			stayed[player] = true
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		if active() then
			onArrival(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		staying[player] = nil
		stayed[player] = nil
		sent[player] = nil
	end)
	-- A teleport that fails after it started (the server filled up meanwhile, Roblox busy): they stay.
	TeleportService.TeleportInitFailed:Connect(function(player, result)
		if sent[player] then
			sent[player] = nil
			Telemetry.Error("Merge", `teleport failed: {result}`)
			tell(player, "Cancel")
			Notifier.Send(player, "Couldn't move you this time - the party goes on here!", "info", 4)
		end
	end)
end

function MergeService.Start()
	if not active() then
		return
	end
	game:BindToClose(function()
		list(true)
	end)
	GameState.Changed("Phase", function(phase)
		if phase == "Intermission" then
			task.spawn(onLobby)
		end
	end)
	while true do
		list()
		task.wait(Config.Merge.Interval)
	end
end

return MergeService

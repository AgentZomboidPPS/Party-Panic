-- Player profiles: load, session lock, autosave, release and client replication (design doc §14).
--
-- Session safety: every stored record carries a Lock { JobId, Time }. A server only loads a profile
-- when no other live server holds the lock (stale locks expire), and refuses to save once another
-- server has taken the lock over, so two servers can never overwrite each other's progress.
-- When DataStores are unavailable (e.g. an unpublished place in Studio) players get a temporary
-- profile that is never saved, and they are told so.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local DailyLogic = require(Shared.Logic.DailyLogic)
local LevelCurve = require(Shared.Logic.LevelCurve)
local Remotes = require(Shared.Remotes)
local TableUtil = require(Shared.Logic.TableUtil)

local Notifier = require(script.Parent.Notifier)
local Telemetry = require(script.Parent.Telemetry)

local DataService = {}

DataService.Template = {
	Version = 1,
	Coins = 0,
	XP = 0,
	Owned = {} :: { [string]: boolean },
	Equipped = {
		Trail = "",
		Title = "Title_Rookie",
		Victory = "Victory_Confetti",
		Elimination = "Elim_Poof",
	},
	Stats = {
		RoundsPlayed = 0,
		Wins = 0,
		TopHalf = 0,
		Votes = 0,
		ItemsCollected = 0,
		TimeSurvived = 0,
		SurvivalWins = 0,
		TreasureDelivered = 0,
		RaceFinishes = 0,
		Knockouts = 0,
		ModePlays = {} :: { [string]: number },
		CategoryPlays = {} :: { [string]: number },
		Best = {} :: { [string]: number },
	},
	Daily = {
		LastClaimDay = 0,
		Streak = 0,
		SecretDay = 0,
	},
	Quests = {
		Daily = { Number = 0, Active = {} },
		Weekly = { Number = 0, Active = {} },
	},
	Tutorial = { Done = false },
	Settings = {
		ReducedEffects = false,
		MusicOn = true,
	},
	Meta = {
		FirstJoin = 0,
		LastJoin = 0,
		Sessions = 0,
	},
}

export type ProfileData = typeof(DataService.Template)

export type Profile = {
	Player: Player,
	Key: string,
	Data: ProfileData,
	CanSave: boolean,
	IsVip: boolean,
	Released: boolean,
}

local profiles: { [Player]: Profile } = {}
local loadingThreads: { [Player]: boolean } = {}
local replicateQueued: { [Player]: boolean } = {}
local store: DataStore? = nil

local loadedEvent = Instance.new("BindableEvent")
DataService.ProfileLoaded = loadedEvent.Event -- (player, profile)

local changedEvent = Instance.new("BindableEvent")
DataService.ProfileChanged = changedEvent.Event -- (player, profile)

local profileRemote = Remotes.Get("ProfileData")

local function keyFor(player: Player): string
	return Config.Data.KeyPrefix .. player.UserId
end

local function newData(): ProfileData
	local data = TableUtil.DeepCopy(DataService.Template)
	data.Meta.FirstJoin = os.time()
	return data
end

local function migrate(data: any): ProfileData
	-- Future schema changes go here, keyed on data.Version.
	TableUtil.Reconcile(data, DataService.Template)
	data.Version = DataService.Template.Version
	return data
end

local function openStore()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if not ok then
		warn("[DataService] DataStores unavailable, progress will not save:", result)
		return
	end
	if RunService:IsStudio() then
		-- Probe once so an unconfigured Studio session falls back immediately instead of retrying per player.
		local probeOk, probeErr = pcall(function()
			result:GetAsync("__probe")
		end)
		if not probeOk then
			warn(
				"[DataService] DataStores not reachable from Studio (enable 'Studio Access to API Services' to test saving):",
				probeErr
			)
			return
		end
	end
	store = result
end

local function loadRecord(player: Player): (any, boolean)
	local dataStore = store
	if not dataStore then
		return nil, false
	end
	local key = keyFor(player)
	for attempt = 1, Config.Data.LoadRetries do
		local blockedByLock = false
		local ok, result = pcall(function()
			return dataStore:UpdateAsync(key, function(stored)
				stored = stored or {}
				local lock = stored.Lock
				local lockIsLive = lock
					and lock.JobId ~= game.JobId
					and os.time() - (lock.Time or 0) < Config.Data.SessionLockTimeout
				-- On the final attempt we take over the lock (the other session is most likely gone).
				if lockIsLive and attempt < Config.Data.LoadRetries then
					blockedByLock = true
					return nil
				end
				stored.Lock = { JobId = game.JobId, Time = os.time() }
				return stored
			end)
		end)
		if ok and result and not blockedByLock then
			return result.Data, true
		end
		if not ok then
			Telemetry.Error("DataLoad", `{player.UserId} attempt {attempt}: {result}`)
		end
		if not player.Parent then
			return nil, false
		end
		task.wait(if blockedByLock then 4 else attempt * 2)
	end
	return nil, false
end

local function saveRecord(profile: Profile, release: boolean): boolean
	local dataStore = store
	if not profile.CanSave or not dataStore then
		return true
	end
	local lostLock = false
	local ok, err = pcall(function()
		dataStore:UpdateAsync(profile.Key, function(stored)
			stored = stored or {}
			local lock = stored.Lock
			if lock and lock.JobId ~= game.JobId then
				-- Another server owns this profile now; never overwrite its newer data.
				lostLock = true
				return nil
			end
			stored.Data = profile.Data
			stored.Lock = if release then nil else { JobId = game.JobId, Time = os.time() }
			return stored
		end)
	end)
	if not ok then
		Telemetry.Error("DataSave", `{profile.Key}: {err}`)
		return false
	end
	if lostLock then
		Telemetry.Error("DataSave", `{profile.Key}: session lock lost, save skipped`)
		profile.CanSave = false
	end
	return true
end

function DataService.Get(player: Player): Profile?
	return profiles[player]
end

function DataService.WaitFor(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 30)
	while not profiles[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.All(): { [Player]: Profile }
	return profiles
end

-- Builds the subset of the profile the owning client needs for its UI.
function DataService.BuildSnapshot(profile: Profile)
	local data = profile.Data
	local level, intoLevel, needed = LevelCurve.FromTotalXP(data.XP)
	local today = DailyLogic.DayNumber(os.time())
	local nextStreak = DailyLogic.NextStreak(data.Daily, today)
	local scalarStats = {}
	for key, value in data.Stats do
		if type(value) == "number" then
			scalarStats[key] = value
		end
	end
	local function quests(period)
		local list = {}
		for _, quest in period.Active do
			table.insert(list, { Id = quest.Id, Progress = quest.Progress, Done = quest.Done })
		end
		return list
	end
	return {
		Coins = data.Coins,
		XP = data.XP,
		Level = level,
		LevelXP = intoLevel,
		LevelNeed = needed,
		Owned = data.Owned,
		Equipped = data.Equipped,
		Stats = scalarStats,
		Best = data.Stats.Best,
		Quests = { Daily = quests(data.Quests.Daily), Weekly = quests(data.Quests.Weekly) },
		Daily = {
			CanClaim = DailyLogic.CanClaim(data.Daily, today),
			Streak = data.Daily.Streak,
			NextStreak = nextStreak,
			NextReward = Config.DailyRewards[math.min(nextStreak, #Config.DailyRewards)],
			SecretFound = data.Daily.SecretDay >= today,
		},
		TutorialDone = data.Tutorial.Done,
		Settings = data.Settings,
		IsVip = profile.IsVip,
		CanSave = profile.CanSave,
	}
end

local function updateLeaderstats(profile: Profile)
	local player = profile.Player
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local level = LevelCurve.FromTotalXP(profile.Data.XP)
	local levelValue = leaderstats:FindFirstChild("Level") :: IntValue?
	local winsValue = leaderstats:FindFirstChild("Wins") :: IntValue?
	if levelValue then
		levelValue.Value = level
	end
	if winsValue then
		winsValue.Value = profile.Data.Stats.Wins
	end
	player:SetAttribute("PP_Level", level)
end

-- Call after changing profile data: replicates a fresh snapshot (batched per frame).
function DataService.Changed(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	changedEvent:Fire(player, profile)
	if replicateQueued[player] then
		return
	end
	replicateQueued[player] = true
	task.defer(function()
		replicateQueued[player] = nil
		local current = profiles[player]
		if current and player.Parent then
			updateLeaderstats(current)
			profileRemote:FireClient(player, DataService.BuildSnapshot(current))
		end
	end)
end

local function onPlayerAdded(player: Player)
	if profiles[player] or loadingThreads[player] then
		return
	end
	loadingThreads[player] = true

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local levelValue = Instance.new("IntValue")
	levelValue.Name = "Level"
	levelValue.Value = 1
	levelValue.Parent = leaderstats
	local winsValue = Instance.new("IntValue")
	winsValue.Name = "Wins"
	winsValue.Parent = leaderstats
	leaderstats.Parent = player

	local stored, canSave = loadRecord(player)
	loadingThreads[player] = nil

	if not player.Parent then
		-- Left while loading: release the lock we may have taken.
		if canSave then
			saveRecord({
				Player = player,
				Key = keyFor(player),
				Data = migrate(stored or newData()),
				CanSave = true,
				IsVip = false,
				Released = false,
			}, true)
		end
		return
	end

	local data = if stored then migrate(stored) else newData()
	data.Meta.LastJoin = os.time()
	data.Meta.Sessions += 1

	local profile: Profile = {
		Player = player,
		Key = keyFor(player),
		Data = data,
		CanSave = canSave,
		IsVip = false,
		Released = false,
	}
	profiles[player] = profile

	if not canSave then
		task.delay(3, function()
			if player.Parent then
				Notifier.Send(
					player,
					"Progress saving is unavailable right now. Your progress this session won't be saved.",
					"warning",
					8
				)
			end
		end)
	end

	loadedEvent:Fire(player, profile)
	DataService.Changed(player)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Released = true
	saveRecord(profile, true)
	profiles[player] = nil
	replicateQueued[player] = nil
end

function DataService.Init()
	openStore()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		local pending = 0
		for _, profile in profiles do
			if profile.Released then
				continue
			end
			pending += 1
			task.spawn(function()
				profile.Released = true
				saveRecord(profile, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

function DataService.Start()
	while true do
		task.wait(Config.Data.AutosaveInterval)
		for _, profile in profiles do
			if not profile.Released then
				task.spawn(saveRecord, profile, false)
			end
		end
	end
end

return DataService

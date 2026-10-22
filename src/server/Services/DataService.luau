-- Player profiles: load, session lock, autosave, release and client replication (design doc §14).
--
-- Session safety: every stored record carries a Lock { JobId, Time }. A server only loads a profile
-- when no other live server holds the lock (stale locks expire), and refuses to save once another
-- server has taken the lock over, so two servers can never overwrite each other's progress.
-- When DataStores are unavailable (e.g. an unpublished place in Studio) players get a temporary
-- profile that is never saved, and they are told so.
-- Saved profiles go through Logic/ProfileMigration on load (the move to the low coin scale, owner:
-- "I want low currency not high"); a player whose coins were just converted is told so, once. Every
-- save stamps the balance it writes, so coins paid by a server still running the old code (before
-- the owner restarts servers after a publish) are converted too, on the next load.
--
-- Second pass (the owner restarts every server after each publish, so shutdowns are routine):
--   * The message about converted coins waits in the profile (Meta.CoinNotice) until it was sent,
--     so a player who leaves before it shows gets it next time.
--   * A player who leaves while their profile is still loading gets our lock released and nothing
--     else: their saved data isn't touched (it is converted on their next real load).
--   * The save when a player leaves (or the server closes) is tried again a few times (1, 2, 4 s),
--     and the server's close (BindToClose) waits for every save still running, whoever started
--     it, so the last minutes of play aren't lost and no lock is left behind.
--   * An autosave that was still running when the player left never locks the record again.
--
-- Third pass (the data-safety review that followed the move to the low coin scale): two visits of
-- one player to the same server used to hold identical locks (the JobId was all a lock said), so
-- the first visit could clear the second one's lock: a load still running when the player left
-- and came back, or a leave save that took longer than the 30 s wait on rejoining. The second
-- visit then played with no lock until its first autosave, and a quick move to another server
-- could lose its progress. Now a lock also names its session (Lock.Session, numbered per server):
-- saves and lock releases only touch their own session's lock, a load never takes the lock once
-- its player has left, and a player back on the same server also waits for a load still running
-- from their last visit. Locks written before this change have no Session; for those the JobId
-- alone decides, as before. Older servers ignore the new field (another JobId is someone else's).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local DailyLogic = require(Shared.Logic.DailyLogic)
local GameDefinitions = require(Shared.GameDefinitions)
local LevelCurve = require(Shared.Logic.LevelCurve)
local ProfileMigration = require(Shared.Logic.ProfileMigration)
local ProfileTemplate = require(Shared.Logic.ProfileTemplate)
local Remotes = require(Shared.Remotes)
local TableUtil = require(Shared.Logic.TableUtil)

local Notifier = require(script.Parent.Notifier)
local Telemetry = require(script.Parent.Telemetry)

local DataService = {}

-- Every field a profile has and its default (Logic/ProfileTemplate, where the Lune tests load it).
DataService.Template = ProfileTemplate

export type ProfileData = typeof(DataService.Template)

export type Profile = {
	Player: Player,
	Key: string,
	Data: ProfileData,
	CanSave: boolean,
	IsVip: boolean,
	Released: boolean,
	Session: number, -- this visit's number on this server (its lock's Session)
	Migration: ProfileMigration.Report?, -- what loading changed (this session only, never saved)
}

local profiles: { [Player]: Profile } = {}
local loadingThreads: { [Player]: boolean } = {}
local replicateQueued: { [Player]: boolean } = {}
local store: DataStore? = nil
local inFlight = 0 -- saves and lock releases still running; BindToClose waits for every one
local closeDeadline = math.huge -- set when the server closes: no retry may wait past it
local RELEASE_RETRY_WAITS = { 1, 2, 4 } -- seconds between the tries of a release
local busy: { [string]: number } = {} -- keys with a load or release still running here (how many)
local sessionCount = 0 -- the last visit's number (each load starts a new session)

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

-- The games a profile's GamesTried counts (the Game Explorer milestone: "Play all 12 games").
local knownGames: { [string]: boolean } = {}
for _, definition in GameDefinitions.List do
	if definition.Enabled ~= false then
		knownGames[definition.Id] = true
	end
end

-- Brings a saved profile up to date (Logic/ProfileMigration.Load: the one-time move to the low coin
-- scale first, then the template's defaults for missing fields, then the worked-out stats). Saved
-- values always win over defaults, and owned items are never touched.
local function migrate(data: any): (ProfileData, ProfileMigration.Report)
	local report = ProfileMigration.Load(data, DataService.Template, TableUtil.Reconcile, knownGames)
	return data, report
end
DataService.Migrate = migrate

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

-- Whether a record's lock is this session's: taken on this server, in this session. (A lock from
-- before sessions were numbered has no Session, and this server's JobId is enough, as it was then.)
local function ownsLock(lock: any, session: number): boolean
	return lock.JobId == game.JobId and (lock.Session == nil or lock.Session == session)
end

-- Counts a load or release of `key` running here (`change` 1 when it starts, -1 when it's over).
local function markBusy(key: string, change: number)
	local count = (busy[key] or 0) + change
	busy[key] = if count > 0 then count else nil
end

local function loadRecord(player: Player, session: number): (any, boolean)
	local dataStore = store
	if not dataStore then
		return nil, false
	end
	local key = keyFor(player)
	for attempt = 1, Config.Data.LoadRetries do
		-- Gone while we waited between attempts: never lock (or take over another server's lock) for
		-- someone who has left, or a session they've since started elsewhere could lose its lock.
		if not player.Parent then
			return nil, false
		end
		local blockedByLock = false
		local ok, result = pcall(function()
			return dataStore:UpdateAsync(key, function(stored)
				-- Or gone while this request was on its way: still no lock (their next visit may hold it).
				if not player.Parent then
					return nil
				end
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
				stored.Lock = { JobId = game.JobId, Time = os.time(), Session = session }
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

-- One save of a profile (`release`: and give up our lock). True when it's done with: saved, not
-- saved on purpose (another server owns it now, or this profile never saves), false on an error.
local function saveRecord(profile: Profile, release: boolean): boolean
	local dataStore = store
	if not profile.CanSave or not dataStore then
		return true
	end
	local lostLock = false
	inFlight += 1
	local ok, err = pcall(function()
		dataStore:UpdateAsync(profile.Key, function(stored)
			stored = stored or {}
			local lock = stored.Lock
			if lock and not ownsLock(lock, profile.Session) then
				-- Another server (or the player's next visit here) owns this profile now; never
				-- overwrite its newer data.
				lostLock = true
				return nil
			end
			if not release and profile.Released then
				-- An autosave still waiting when the player left: the release save writes the data
				-- and clears the lock, and this one must not lock the record again.
				return nil
			end
			-- The balance this save writes (stamped here, where nothing can change it before it's
			-- written), so a later load can spot coins paid by a server still running the old code.
			ProfileMigration.Stamp(profile.Data)
			stored.Data = profile.Data
			stored.Lock = if release then nil else { JobId = game.JobId, Time = os.time(), Session = profile.Session }
			return stored
		end)
	end)
	inFlight -= 1
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

-- Tries `attempt` (true when done) a few times with growing waits, never waiting past the server's
-- close. Counted in `inFlight` the whole time, waits included.
local function withRetries(attempt: () -> boolean): boolean
	inFlight += 1
	local done = false
	for try = 1, #RELEASE_RETRY_WAITS + 1 do
		done = attempt()
		local wait = RELEASE_RETRY_WAITS[try]
		if done or not wait or os.clock() + wait > closeDeadline then
			break
		end
		task.wait(wait)
	end
	inFlight -= 1
	return done
end

-- The save when a player leaves or the server closes: their data, and our lock given up.
local function releaseProfile(profile: Profile)
	profile.Released = true
	markBusy(profile.Key, 1)
	if not withRetries(function()
		return saveRecord(profile, true)
	end) then
		Telemetry.Error("DataSave", `{profile.Key}: release failed after retries`)
	end
	markBusy(profile.Key, -1)
end

-- A player left while their profile was loading: give up the lock we took and touch nothing else
-- (no session happened, so there's nothing to save; their data converts on their next real load).
local function releaseLockOnly(key: string, session: number)
	local dataStore = store
	if not dataStore then
		return
	end
	withRetries(function()
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key, function(stored)
				local lock = if type(stored) == "table" then stored.Lock else nil
				if type(lock) ~= "table" or not ownsLock(lock, session) then
					return nil -- not ours (any more): leave the record as it is
				end
				stored.Lock = nil
				return stored
			end)
		end)
		if not ok then
			Telemetry.Error("DataSave", `{key}: lock release failed: {err}`)
		end
		return ok
	end)
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
			SecretDay = data.Daily.SecretDay, -- the day they last found it (the token's Day says today's)
			FirstWinReady = (data.Daily.FirstWinDay or 0) < today, -- today's first-win bonus is still to win
		},
		TutorialDone = data.Tutorial.Done,
		Settings = data.Settings,
		-- What keeps players coming back: each feature's save field, as saved (Party Cups, medals,
		-- this week's leaderboard points, events).
		Cups = data.Cups,
		Medals = data.Medals,
		Weekly = data.Weekly,
		Events = data.Events,
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

-- The profile for this session: the save brought up to date (or a new one), and the visit counted.
local function prepare(stored: any): (ProfileData, ProfileMigration.Report?)
	local data, migration
	if stored then
		data, migration = migrate(stored)
	else
		data = newData()
	end
	data.Meta.LastJoin = os.time()
	data.Meta.Sessions += 1
	return data, migration
end

local function onPlayerAdded(player: Player)
	if profiles[player] or loadingThreads[player] then
		return
	end
	loadingThreads[player] = true
	-- Back on this server while the save from their last visit is still being retried, or the load
	-- they left during is still running: wait for it, or this load would read the record from
	-- before that visit (our own server's lock doesn't stop it).
	local key = keyFor(player)
	local waitUntil = os.clock() + 30
	while busy[key] and player.Parent and os.clock() < waitUntil do
		task.wait(0.25)
	end
	if not player.Parent then
		loadingThreads[player] = nil
		return
	end

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

	-- A load counts as a save in flight until its profile is registered (or its lock released), so
	-- a server closing meanwhile waits for it and never leaves the lock behind.
	inFlight += 1
	markBusy(key, 1)
	sessionCount += 1
	local session = sessionCount
	local stored, canSave = loadRecord(player, session)
	loadingThreads[player] = nil

	if not player.Parent then
		-- Left while loading: release the lock we took, and nothing else.
		if canSave then
			releaseLockOnly(key, session)
		end
		markBusy(key, -1)
		inFlight -= 1
		return
	end

	local ok, data, migration = pcall(prepare, stored)
	if not ok then
		-- A save this code can't read: never overwrite it. The player plays on a profile that isn't
		-- saved (and is told so), and our lock goes at once.
		Telemetry.Error("DataLoad", `{key}: unreadable save, not saving this session: {data}`)
		data, migration = prepare(nil)
		if canSave then
			canSave = false
			task.spawn(releaseLockOnly, key, session)
		end
	end

	local profile: Profile = {
		Player = player,
		Key = key,
		Data = data,
		CanSave = canSave,
		IsVip = false,
		Released = false,
		Session = session,
		Migration = migration,
	}
	profiles[player] = profile
	if closeDeadline < math.huge then
		task.spawn(releaseProfile, profile) -- loaded while the server is closing: save and let go
	end
	markBusy(key, -1)
	inFlight -= 1

	if migration and migration.CoinsBefore and migration.CoinsBefore > 0 then
		Telemetry.PlayerEvent(player, "EconomyMigrated", migration.CoinsBefore)
	elseif migration and migration.OldServerChange then
		Telemetry.PlayerEvent(player, "EconomyOldServer", 1, tostring(migration.OldServerChange))
	end
	-- What happened to their coins (ProfileMigration keeps it in Meta.CoinNotice until it's been
	-- sent): said once they've had a moment to look around, then cleared, so the next save
	-- remembers they were told. A player who leaves before that gets it next time.
	local notice = data.Meta.CoinNotice
	if type(notice) == "table" then
		task.delay(6, function()
			if not player.Parent or profiles[player] ~= profile or data.Meta.CoinNotice ~= notice then
				return
			end
			if notice.Kind == "OldServer" then
				-- Their last game was on a server still running the old version (big coins).
				Notifier.Send(
					player,
					`Coins from your last game (on an older server) are on the new small scale too: you have {notice.After}.`,
					"info",
					9
				)
			else
				Notifier.Send(
					player,
					`Coins got smaller numbers, and prices too! Your {notice.Before} coins are now {notice.After}.`,
					"reward",
					9
				)
			end
			data.Meta.CoinNotice = nil
		end)
	end

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
	if not profile.Released then -- (the server's close may have started it already)
		releaseProfile(profile)
	end
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
		-- Release everyone still here, then wait for every save still running: these, the ones
		-- players leaving just started, autosaves and lock releases (Roblox allows 30 s).
		closeDeadline = os.clock() + 25
		for _, profile in profiles do
			if not profile.Released then
				task.spawn(releaseProfile, profile)
			end
		end
		while inFlight > 0 and os.clock() < closeDeadline do
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

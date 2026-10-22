-- Medals (owner, asked what keeps players coming back: "Medals: a medal for winning each game and a
-- few big ones, Roblox badges, a collect-them-all wall in the lobby", then: "Can you work on all of
-- that? this wont mess with what the other workers are working on right?"): one for winning each
-- game and a few big ones (Shared/Medals has the list), kept in the profile (Medals: medal id -> the
-- UTC day it was earned) and awarded as Roblox badges once their ids exist. The medal wall in the
-- lobby (World/MedalWall) and the medal screen (Controllers/MedalController) show them.
--
-- How they're earned:
--   * a round's winners (RoundEvents.Finished; the winning team's players all win, as the round's
--     rewards count it: Logic/MedalLogic.IsWin) get that game's medal;
--   * after every round, and when a profile loads, the career stats are checked for the medals
--     they earn (a first win, 10 and 50 wins, every game played, every game's medal). A player who
--     won before medals existed gets those when they next join, quietly: the client shows one card
--     for all of them, not one each (MedalEarned's second value says they're from before);
--   * other features give theirs with MedalService.Award(player, id):
--       "CupChampion"   CupService: won a Party Cup
--       "HallOfFame"    LeaderboardService: finished a week in the top three
--       "Halloween2026" EventService: finished the Halloween 2026 party's candy track
--       "FriendsParty"  FriendsService: played a round with a friend
--     An award for someone whose profile is still loading is given once it has loaded.
-- Real players only, and once each: bots (BotRegistry) never get medals, saves or badges.
--
-- Badges: a medal with a BadgeId (Shared/Medals) is awarded as that Roblox badge when it's earned,
-- and a player who earned the medal before the badge existed gets the badge on their next join
-- (CheckUserBadgesAsync looks up ten at a time). One badge call at a time for the whole server,
-- with a pause between them, so the badge service is never flooded. Never from a test run: under
-- the harness (workspace PP_Harness) the badges it would have awarded are listed in
-- MedalService.HarnessBadges instead.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local DailyLogic = require(Shared.Logic.DailyLogic)
local GameDefinitions = require(Shared.GameDefinitions)
local MedalLogic = require(Shared.Logic.MedalLogic)
local Medals = require(Shared.Medals)
local Remotes = require(Shared.Remotes)

local BotRegistry = require(script.Parent.BotRegistry)
local DataService = require(script.Parent.DataService)
local RoundEvents = require(script.Parent.RoundEvents)
local Telemetry = require(script.Parent.Telemetry)

local MedalService = {}

local BADGE_GAP = 0.5 -- seconds between two calls to the badge service (the whole server)
local BADGE_TRIES = 3 -- an award that fails is tried this many times in all
local CHECK_BATCH = 10 -- CheckUserBadgesAsync looks up at most this many badges at once

local earnedRemote = Remotes.Get("MedalEarned")

-- Awards for players whose profile hadn't loaded yet: given once it has (player -> medal ids).
local pending: { [Player]: { string } } = {}
-- Badge calls waiting their turn: an award ("Award"), or a look at which of a player's medals'
-- badges they're missing ("Check").
type BadgeJob = { Kind: string, Player: Player, BadgeIds: { number }, Tries: number }
local badgeJobs: { BadgeJob } = {}
local badgeWorking = false
local warned: { [string]: boolean } = {}

-- Test runs (the round harness): the badges that would have been awarded, as { UserId, BadgeId }.
MedalService.HarnessBadges = {} :: { { UserId: number, BadgeId: number } }

local function isHarness(): boolean
	return workspace:GetAttribute("PP_Harness") == true
end

-- A real player who's still here (bots look like players but are tables flagged IsBot).
local function isPerson(player: any): boolean
	return player ~= nil and not BotRegistry.IsBot(player) and player.Parent ~= nil
end

-- The profile's medals (a save from before medals has them through Reconcile; this is a safety net).
local function medalsOf(profile: DataService.Profile): { [string]: number }
	local data = profile.Data :: any
	if type(data.Medals) ~= "table" then
		data.Medals = {}
	end
	return data.Medals
end

-- The games that count for EveryGame and WonEveryGame: the ones on right now (a game whose code
-- failed to load is switched off by the mini-game registry).
local function liveGames(): { string }
	local ids = {}
	for _, medal in Medals.Games do
		local definition = GameDefinitions.Get(medal.GameId :: string)
		if definition and definition.Enabled ~= false then
			table.insert(ids, medal.GameId :: string)
		end
	end
	return ids
end

-- Badges ------------------------------------------------------------------------------------------

local function runBadgeJob(job: BadgeJob)
	local player = job.Player
	if not player.Parent then
		return
	end
	if isHarness() then
		if job.Kind == "Award" then
			for _, badgeId in job.BadgeIds do
				table.insert(MedalService.HarnessBadges, { UserId = player.UserId, BadgeId = badgeId })
			end
		end
		return
	end
	if job.Kind == "Check" then
		-- Which of these badges they don't have yet: those are awarded (each its own job).
		local ok, owned = pcall(BadgeService.CheckUserBadgesAsync, BadgeService, player.UserId, job.BadgeIds)
		if not ok then
			Telemetry.Error("Badge", `check for {player.UserId}: {owned}`)
			return
		end
		local has = {}
		for _, badgeId in owned do
			has[badgeId] = true
		end
		for _, badgeId in job.BadgeIds do
			if not has[badgeId] then
				table.insert(badgeJobs, { Kind = "Award", Player = player, BadgeIds = { badgeId }, Tries = 0 })
			end
		end
		return
	end
	local badgeId = job.BadgeIds[1]
	local ok, err = pcall(BadgeService.AwardBadgeAsync, BadgeService, player.UserId, badgeId)
	if not ok then
		job.Tries += 1
		if job.Tries < BADGE_TRIES then
			table.insert(badgeJobs, job) -- again after the others
		else
			Telemetry.Error("Badge", `award {badgeId} to {player.UserId}: {err}`)
		end
	end
end

local function queueBadges(job: BadgeJob)
	if #job.BadgeIds == 0 then
		return
	end
	table.insert(badgeJobs, job)
	if badgeWorking then
		return
	end
	badgeWorking = true
	task.spawn(function()
		while #badgeJobs > 0 do
			local okJob, err = pcall(runBadgeJob, table.remove(badgeJobs, 1) :: BadgeJob)
			if not okJob then
				Telemetry.Error("Badge", tostring(err))
			end
			if not isHarness() then
				task.wait(BADGE_GAP)
			end
		end
		badgeWorking = false
	end)
end

-- On joining: the badges of every medal they have whose badge exists, in case one was missed (a
-- failed call, or a badge the owner made after they earned the medal).
local function checkBadges(player: Player, owned: { [string]: number })
	local batch = {}
	for _, medal in Medals.List do
		if medal.BadgeId ~= 0 and owned[medal.Id] ~= nil then
			table.insert(batch, medal.BadgeId)
			if #batch == CHECK_BATCH then
				queueBadges({ Kind = "Check", Player = player, BadgeIds = batch, Tries = 0 })
				batch = {}
			end
		end
	end
	queueBadges({ Kind = "Check", Player = player, BadgeIds = batch, Tries = 0 })
end

-- Medals ------------------------------------------------------------------------------------------

-- Gives the medal (once). `earlier`: earned before medals existed (said along with it, so the
-- client shows one card for them all). True when it was new.
local function grant(player: Player, id: string, earlier: boolean): boolean
	if not isPerson(player) then
		return false
	end
	local medal = Medals.Get(id)
	if not medal then
		if not warned[id] then
			warned[id] = true
			warn(`[MedalService] there's no medal "{id}" (see Shared/Medals)`)
		end
		return false
	end
	local profile = DataService.Get(player)
	if not profile then
		-- Still loading: given when it has.
		local waiting = pending[player] or {}
		pending[player] = waiting
		if not table.find(waiting, id) then
			table.insert(waiting, id)
		end
		return false
	end
	local owned = medalsOf(profile)
	if owned[id] ~= nil then
		return false
	end
	owned[id] = DailyLogic.DayNumber(os.time())
	DataService.Changed(player)
	earnedRemote:FireClient(player, id, earlier)
	Telemetry.PlayerEvent(player, "MedalEarned", 1, id)
	if medal.BadgeId ~= 0 then
		queueBadges({ Kind = "Award", Player = player, BadgeIds = { medal.BadgeId }, Tries = 0 })
	end
	return true
end

-- The medals a player's career stats and collection have earned that they don't have yet.
local function grantEarned(player: Player, earlier: boolean)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	for _, id in MedalLogic.Earned(profile.Data.Stats, medalsOf(profile), Medals.Catalog, liveGames()) do
		grant(player, id, earlier)
	end
end

-- Gives `player` the medal `id` (a real player's, never a bot's) the first time; later calls do
-- nothing. Safe to call from anywhere on the server (it never waits). Returns true when the medal
-- was new; an award for a player whose profile is still loading is given once it has.
function MedalService.Award(player: Player, id: string): boolean
	local isNew = grant(player, id, false)
	if isNew and Medals.Get(id) and (Medals.Get(id) :: Medals.Medal).Kind == "Game" then
		grantEarned(player, false) -- it may complete WonEveryGame
	end
	return isNew
end

-- Whether the player has the medal (false while their profile loads).
function MedalService.Has(player: Player, id: string): boolean
	local profile = DataService.Get(player)
	return profile ~= nil and medalsOf(profile)[id] ~= nil
end

-- A round ended (after its rewards): its winners get the game's medal, everyone's stats are looked at.
local function onRoundFinished(definition: any, placed: any, winningTeam: string?)
	if type(definition) ~= "table" or type(placed) ~= "table" then
		return
	end
	local medal = Medals.ForGame(definition.Id)
	for _, item in placed do
		local entry = item.Entry
		local player = entry and entry.Player
		if not isPerson(player) then
			continue
		end
		if medal and MedalLogic.IsWin(item.Place, entry.Team, winningTeam) then
			grant(player, medal.Id, false)
		end
		grantEarned(player, false)
	end
end

-- A profile is ready: awards that waited for it, then what their stats had already earned, then
-- their badges. (DataService.ProfileLoaded runs it; the round harness also runs it for a stand-in it
-- adds later, as MedalService.ProfileLoaded.)
local function onProfileLoaded(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local waiting = pending[player]
	pending[player] = nil
	for _, id in waiting or {} do
		MedalService.Award(player, id)
	end
	grantEarned(player, true)
	checkBadges(player, medalsOf(profile))
end
MedalService.ProfileLoaded = onProfileLoaded

function MedalService.Init()
	DataService.ProfileLoaded:Connect(function(player: Player)
		-- (The profile it passes is a copy: the real one is looked up.)
		onProfileLoaded(player)
	end)
	RoundEvents.Finished:Connect(onRoundFinished)
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
	end)
	-- Profiles that loaded before this started listening.
	for player in DataService.All() do
		task.spawn(onProfileLoaded, player)
	end
end

return MedalService

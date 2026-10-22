-- Logs the funnels (owner: "Can you make me some sick ass funnels to track where players leave/
-- complete stuff"; Shared/Logic/Funnels names them and their steps). Creator Hub > Analytics >
-- Funnels shows each as how many players reached each step; Custom Events shows "LeftDuring" (what
-- people were doing when they left).
--
-- Where each step comes from:
--   New players and Session: joining (DataService.ProfileLoaded), GO in a round (RoundManager calls
--     RoundStarted), and each round's results (RoundEvents.Finished): the new-player ladder counts
--     rounds over their whole life (Stats.RoundsPlayed), Session over this visit. A new player is
--     one whose first load is after this shipped (no rounds, first session); their last step logged
--     is kept in their profile (Funnel.Onboarding), so a step is never logged twice, across visits
--     too. Everyone else is marked -1 and never logged there.
--   Round: in the round and GO (RoundManager: RoundJoined, RoundStarted), saw the results
--     (RoundEvents.Finished), stayed for the next round (put in the very next round this server
--     played). Each run is one round on this server ("<JobId>:<RoundId>"), its field the game.
--   Shop: opened the shop and picked an item come from the device (the "Funnel" remote, words from
--     Funnels.ClientSteps only, rate limited); bought it from ShopService (ShopBought). Each opening
--     of the shop starts a run.
--   GOLD PASS: saw the offer (the device: the Rewards screen with GET GOLD PASS on it), pressed GET
--     GOLD PASS and bought it (GoldPassService: GoldPrompted, GoldBought).
-- Never for bots or the check tools' stand-ins (Telemetry skips anything that isn't a Player); on a
-- test run (workspace PP_Harness) every step is also kept in memory for the checks (FunnelService.Log).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Funnels = require(Shared.Logic.Funnels)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local BotRegistry = require(script.Parent.BotRegistry)
local DataService = require(script.Parent.DataService)
local RateLimiter = require(script.Parent.RateLimiter)
local RoundEvents = require(script.Parent.RoundEvents)
local SitOutService = require(script.Parent.SitOutService)
local Telemetry = require(script.Parent.Telemetry)

local FunnelService = {}

type Visit = {
	Id: string, -- this visit's run of Session
	JoinedAt: number,
	Rounds: number, -- rounds finished this visit
	Played: boolean, -- played a round this visit (got to GO)
	Finished: string?, -- the Round run of the last round they saw the results of
	FinishedRound: number?, -- ...and its RoundId
	Shop: string?, -- the current run of Shop
	Gold: string?, -- the current run of GoldPass
	Runs: number,
}

local visits: { [any]: Visit } = {}
local log: { string } = {} -- (test runs: every step logged)

local function harness(): boolean
	return workspace:GetAttribute("PP_Harness") == true
end

local function person(player: any): boolean
	return player ~= nil and player.Parent ~= nil and not BotRegistry.IsBot(player)
end

local function step(
	player: any,
	funnel: { Name: string, Steps: { string } }?,
	run: string?,
	index: number,
	detail: string?
)
	local name = if funnel then funnel.Steps[index] else Funnels.Onboarding[index]
	if not name then
		return
	end
	if harness() and #log < 400 then
		table.insert(
			log,
			`{player.Name} {if funnel then funnel.Name else "Onboarding"} {index} {name}{if detail
				then ` ({detail})`
				else ""}`
		)
	end
	Telemetry.FunnelStep(player, if funnel then funnel.Name else nil, run, index, name, detail)
end

local function visitOf(player: any): Visit
	local visit = visits[player]
	if not visit then
		visit = {
			Id = `{game.JobId}:{player.UserId}:{math.floor(os.clock() * 1000)}`,
			JoinedAt = os.clock(),
			Rounds = 0,
			Played = false,
			Runs = 0,
		}
		visits[player] = visit
	end
	return visit
end

local function newRun(visit: Visit, kind: string): string
	visit.Runs += 1
	return `{visit.Id}:{kind}{visit.Runs}`
end

-- The new-player ladder: logs `index` if it's the next step for this player (each step once).
local function onboard(player: any, index: number)
	local profile = DataService.Get(player)
	local funnel = profile and profile.Data.Funnel
	if not funnel or funnel.Onboarding < 1 or index <= funnel.Onboarding then
		return
	end
	-- (Steps the ladder passed on the way, like a first round finished before its GO was seen.)
	for missed = funnel.Onboarding + 1, index do
		step(player, nil, nil, missed)
	end
	funnel.Onboarding = index
	DataService.Changed(player)
end

-- A player's profile is loaded: Session starts, and a brand-new player starts the new-player ladder.
function FunnelService.Joined(player: any, profile: any)
	if not person(player) then
		return
	end
	local data = profile and profile.Data
	local visit = visitOf(player)
	local funnel = data and data.Funnel
	local new = data ~= nil and data.Stats.RoundsPlayed == 0 and data.Meta.Sessions <= 1
	if funnel and funnel.Onboarding == 0 then
		funnel.Onboarding = if new then 1 else -1
		if new then
			step(player, nil, nil, 1)
		end
	end
	step(player, Funnels.Session, visit.Id, 1, if new then "New" else "Returning")
end

-- A round's people are in it (the rules card is up): Round's first step, and the round before
-- theirs, if it was this server's last one, is a round they stayed on for.
function FunnelService.RoundJoined(gameId: string, roundId: number, players: { any })
	local run = `{game.JobId}:{roundId}`
	for _, player in players do
		if not person(player) then
			continue
		end
		local visit = visitOf(player)
		if visit.Finished and visit.FinishedRound == roundId - 1 then
			step(player, Funnels.Round, visit.Finished, 4, gameId)
		end
		visit.Finished, visit.FinishedRound = nil, nil
		step(player, Funnels.Round, run, 1, gameId)
	end
end

-- GO: they're playing.
function FunnelService.RoundStarted(gameId: string, roundId: number, players: { any })
	local run = `{game.JobId}:{roundId}`
	for _, player in players do
		if not person(player) then
			continue
		end
		local visit = visitOf(player)
		step(player, Funnels.Round, run, 2, gameId)
		if not visit.Played then
			visit.Played = true
			step(player, Funnels.Session, visit.Id, 2)
		end
		onboard(player, 2)
	end
end

-- The round's results (its rewards are paid, so Stats.RoundsPlayed counts it).
local function roundFinished(definition: any, placed: { any })
	local roundId = GameState.Get("RoundId") or 0
	local run = `{game.JobId}:{roundId}`
	for _, item in placed do
		local player = item.Entry and item.Entry.Player
		if not person(player) then
			continue
		end
		local visit = visitOf(player)
		step(player, Funnels.Round, run, 3, definition.Id)
		visit.Finished, visit.FinishedRound = run, roundId
		visit.Rounds += 1
		local reached = Funnels.FinishedStep(visit.Rounds)
		if reached then
			step(player, Funnels.Session, visit.Id, reached)
		end
		local profile = DataService.Get(player)
		local lifetime = Funnels.FinishedStep(if profile then profile.Data.Stats.RoundsPlayed else 0)
		if lifetime then
			onboard(player, lifetime)
		end
	end
end

-- A coin purchase in the shop went through.
function FunnelService.ShopBought(player: any, itemId: string)
	if not person(player) then
		return
	end
	local visit = visitOf(player)
	local run = visit.Shop or newRun(visit, "Shop")
	visit.Shop = run
	step(player, Funnels.Shop, run, 3, itemId)
end

-- GET GOLD PASS was pressed (Roblox's prompt is up).
function FunnelService.GoldPrompted(player: any)
	if not person(player) then
		return
	end
	local visit = visitOf(player)
	local run = visit.Gold or newRun(visit, "Gold")
	visit.Gold = run
	step(player, Funnels.GoldPass, run, 2)
end

-- The GOLD PASS was bought.
function FunnelService.GoldBought(player: any)
	if not person(player) then
		return
	end
	local visit = visitOf(player)
	step(player, Funnels.GoldPass, visit.Gold or newRun(visit, "Gold"), 3)
	visit.Gold = nil
end

-- A step only the device sees (Funnels.ClientSteps).
local function fromDevice(player: Player, what: any, detail: any)
	if type(what) ~= "string" or not Funnels.ClientSteps[what] or not person(player) then
		return
	end
	local text = if type(detail) == "string" then string.sub(detail, 1, 40) else nil
	local visit = visitOf(player)
	if what == "ShopOpen" then
		visit.Shop = newRun(visit, "Shop")
		step(player, Funnels.Shop, visit.Shop, 1, text)
	elseif what == "ShopPick" then
		local run = visit.Shop or newRun(visit, "Shop")
		visit.Shop = run
		step(player, Funnels.Shop, run, 2, text)
	elseif what == "GoldSeen" then
		visit.Gold = newRun(visit, "Gold")
		step(player, Funnels.GoldPass, visit.Gold, 1)
	end
end

-- Where they were when they left, and for how long they'd played.
function FunnelService.Left(player: any)
	local visit = visits[player]
	visits[player] = nil
	if not visit or not person(player) then
		return
	end
	local where = Funnels.LeftWhere(
		GameState.Get("Phase"),
		player:GetAttribute("PP_InRound") == true and player:GetAttribute("PP_Alive") == true,
		SitOutService.IsSittingOut(player)
	)
	local minutes = math.floor((os.clock() - visit.JoinedAt) / 60 + 0.5)
	if harness() and #log < 400 then
		table.insert(log, `{player.Name} LeftDuring {where} after {minutes} min`)
	end
	Telemetry.PlayerEvent(player, "LeftDuring", minutes, where)
end

-- Test runs only: every step logged so far ("<name> <funnel> <step> <step name> (<detail>)").
function FunnelService.Log(): { string }
	return log
end

function FunnelService.Init()
	DataService.ProfileLoaded:Connect(FunnelService.Joined)
	RoundEvents.Finished:Connect(roundFinished)
	local limit = Config.RateLimits.Funnel
	local limiter = RateLimiter.new(limit[1], limit[2])
	Remotes.Get("Funnel").OnServerEvent:Connect(function(player, what, detail)
		if limiter:Check(player) then
			fromDevice(player, what, detail)
		end
	end)
	Players.PlayerRemoving:Connect(FunnelService.Left)
end

return FunnelService

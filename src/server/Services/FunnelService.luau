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
--
-- Fun and staying (owner: "What information should we collect to gage if players are having fun and
-- staying?", then "lets do 1-7."): every step carries custom fields (Funnels.FIELDS): the device
-- (each screen says which, the "Device" step of the remote, a moment after it loads: a visit's first
-- steps wait for it, up to DEVICE_WAIT), who they play with (Party, Friends or Solo: a party mate or a
-- Roblox friend in the round, Services/FriendsService), how many people the round had, and the streak
-- they left on. "FirstRoundWait" says how long a visit waited from joining to its first GO.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Funnels = require(Shared.Logic.Funnels)
local GameState = require(Shared.GameState)
local MedalLogic = require(Shared.Logic.MedalLogic)
local Remotes = require(Shared.Remotes)

local BotRegistry = require(script.Parent.BotRegistry)
local DataService = require(script.Parent.DataService)
local FriendsService = require(script.Parent.FriendsService)
local RateLimiter = require(script.Parent.RateLimiter)
local RoundEvents = require(script.Parent.RoundEvents)
local SitOutService = require(script.Parent.SitOutService)
local Telemetry = require(script.Parent.Telemetry)

local FunnelService = {}

local DEVICE_WAIT = 6 -- seconds a visit's first steps wait for its screen to say what it is

type Fields = { string? }

type Visit = {
	Id: string, -- this visit's run of Session
	JoinedAt: number,
	New: string, -- "New" or "Returning"
	Device: string?,
	JoinLogged: boolean, -- its Joined steps are out (they wait for the device)
	Onboard: boolean, -- a new player whose Joined step is still to log
	Social: string, -- the most it has played with friends this visit (Funnels.BestSocial)
	Rounds: number, -- rounds finished this visit
	Lost: number, -- rounds lost in a row, the latest last
	Played: boolean, -- played a round this visit (got to GO)
	Round: { Run: string, Id: number, Fields: Fields }?, -- the round they're in now
	Finished: { Run: string, Id: number, Fields: Fields }?, -- the last round they saw the results of
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

local function note(player: any, text: string, fields: Fields?)
	if harness() and #log < 500 then
		local shown = {}
		for index = 1, 3 do
			local value = fields and fields[index]
			if value and value ~= "" then
				table.insert(shown, value)
			end
		end
		table.insert(log, `{player.Name} {text}{if #shown > 0 then ` ({table.concat(shown, ", ")})` else ""}`)
	end
end

local function step(
	player: any,
	funnel: { Name: string, Steps: { string } }?,
	run: string?,
	index: number,
	fields: Fields?
)
	local name = if funnel then funnel.Steps[index] else Funnels.Onboarding[index]
	if not name then
		return
	end
	note(player, `{if funnel then funnel.Name else "Onboarding"} {index} {name}`, fields)
	Telemetry.FunnelStep(player, if funnel then funnel.Name else nil, run, index, name, fields)
end

local function event(player: any, name: string, value: number, fields: Fields)
	note(player, `{name} {value}`, fields)
	Telemetry.PlayerEventFields(player, name, value, fields)
end

local function visitOf(player: any): Visit
	local visit = visits[player]
	if not visit then
		visit = {
			Id = `{game.JobId}:{player.UserId}:{math.floor(os.clock() * 1000)}`,
			JoinedAt = os.clock(),
			New = "Returning",
			JoinLogged = false,
			Onboard = false,
			Social = "Solo",
			Rounds = 0,
			Lost = 0,
			Played = false,
			Runs = 0,
		}
		visits[player] = visit
	end
	return visit
end

local function device(visit: Visit): string
	return visit.Device or "Unknown"
end

local function sessionFields(visit: Visit): Fields
	return { visit.New, device(visit), visit.Social }
end

local function onboardFields(visit: Visit): Fields
	return { device(visit), visit.Social }
end

-- The visit's Joined steps, once (they wait for the device; any later step sends them first).
local function logJoined(player: any, visit: Visit)
	if visit.JoinLogged then
		return
	end
	visit.JoinLogged = true
	if visit.Onboard then
		step(player, nil, nil, 1, onboardFields(visit))
	end
	step(player, Funnels.Session, visit.Id, 1, sessionFields(visit))
end

local function newRun(visit: Visit, kind: string): string
	visit.Runs += 1
	return `{visit.Id}:{kind}{visit.Runs}`
end

-- The new-player ladder: logs `index` if it's the next step for this player (each step once).
local function onboard(player: any, visit: Visit, index: number)
	local profile = DataService.Get(player)
	local funnel = profile and profile.Data.Funnel
	if not funnel or funnel.Onboarding < 1 or index <= funnel.Onboarding then
		return
	end
	-- (Steps the ladder passed on the way, like a first round finished before its GO was seen.)
	for missed = funnel.Onboarding + 1, index do
		step(player, nil, nil, missed, onboardFields(visit))
	end
	funnel.Onboarding = index
	DataService.Changed(player)
end

-- A player's profile is loaded: Session starts, and a brand-new player starts the new-player ladder.
-- Their Joined steps go out once their screen has said what it is (or DEVICE_WAIT later).
function FunnelService.Joined(player: any, profile: any)
	if not person(player) then
		return
	end
	local data = profile and profile.Data
	local visit = visitOf(player)
	local funnel = data and data.Funnel
	local new = data ~= nil and data.Stats.RoundsPlayed == 0 and data.Meta.Sessions <= 1
	visit.New = if new then "New" else "Returning"
	if funnel and funnel.Onboarding == 0 then
		funnel.Onboarding = if new then 1 else -1
		visit.Onboard = new
	end
	if visit.Device then
		logJoined(player, visit)
	else
		task.delay(DEVICE_WAIT, function()
			if visits[player] == visit then
				logJoined(player, visit)
			end
		end)
	end
end

-- Who a round's people play with, and how many people it has: { [player] = Fields } for Round.
local function roundFields(gameId: string, players: { any }): { [any]: Fields }
	local people = {}
	for _, player in players do
		if person(player) then
			table.insert(people, player)
		end
	end
	local count = Funnels.PeopleBucket(#people)
	local fields = {}
	for _, player in people do
		local party = player:GetAttribute("PP_Party")
		local mate, friend = false, false
		for _, other in people do
			if other ~= player then
				if party ~= nil and other:GetAttribute("PP_Party") == party then
					mate = true
				end
				local ok, friends = pcall(FriendsService.AreFriends, player, other)
				if ok and friends then
					friend = true
				end
			end
		end
		fields[player] = { gameId, Funnels.Social(mate, friend), count }
	end
	return fields
end

-- A round's people are in it (the rules card is up): Round's first step, and the round before
-- theirs, if it was this server's last one, is a round they stayed on for.
function FunnelService.RoundJoined(gameId: string, roundId: number, players: { any })
	local run = `{game.JobId}:{roundId}`
	for player, fields in roundFields(gameId, players) do
		local visit = visitOf(player)
		logJoined(player, visit)
		local finished = visit.Finished
		if finished and finished.Id == roundId - 1 then
			step(player, Funnels.Round, finished.Run, 4, finished.Fields)
		end
		visit.Finished = nil
		visit.Round = { Run = run, Id = roundId, Fields = fields }
		visit.Social = Funnels.BestSocial(visit.Social, fields[2])
		step(player, Funnels.Round, run, 1, fields)
	end
end

-- The fields of the round a visit is in (or a fresh look if it wasn't seen joining it).
local function fieldsFor(visit: Visit, gameId: string, roundId: number): (string, Fields)
	local round = visit.Round
	if round and round.Id == roundId then
		return round.Run, round.Fields
	end
	local run = `{game.JobId}:{roundId}`
	local fields = { gameId, "Solo", "" }
	visit.Round = { Run = run, Id = roundId, Fields = fields }
	return run, fields
end

-- GO: they're playing. A visit's first GO says how long it waited for it.
function FunnelService.RoundStarted(gameId: string, roundId: number, players: { any })
	for _, player in players do
		if not person(player) then
			continue
		end
		local visit = visitOf(player)
		logJoined(player, visit)
		local run, fields = fieldsFor(visit, gameId, roundId)
		step(player, Funnels.Round, run, 2, fields)
		if not visit.Played then
			visit.Played = true
			step(player, Funnels.Session, visit.Id, 2, sessionFields(visit))
			event(
				player,
				"FirstRoundWait",
				math.floor(os.clock() - visit.JoinedAt + 0.5),
				{ visit.New, device(visit), fields[3] }
			)
		end
		onboard(player, visit, 2)
	end
end

-- The round's results (its rewards are paid, so Stats.RoundsPlayed counts it).
local function roundFinished(definition: any, placed: { any }, winningTeam: string?)
	local roundId = GameState.Get("RoundId") or 0
	for _, item in placed do
		local entry = item.Entry
		local player = entry and entry.Player
		if not person(player) then
			continue
		end
		local visit = visitOf(player)
		local run, fields = fieldsFor(visit, definition.Id, roundId)
		step(player, Funnels.Round, run, 3, fields)
		visit.Finished = { Run = run, Id = roundId, Fields = fields }
		visit.Rounds += 1
		visit.Lost = if MedalLogic.IsWin(item.Place, entry.Team, winningTeam) then 0 else visit.Lost + 1
		local reached = Funnels.FinishedStep(visit.Rounds)
		if reached then
			step(player, Funnels.Session, visit.Id, reached, sessionFields(visit))
		end
		local profile = DataService.Get(player)
		local lifetime = Funnels.FinishedStep(if profile then profile.Data.Stats.RoundsPlayed else 0)
		if lifetime then
			onboard(player, visit, lifetime)
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
	step(player, Funnels.Shop, run, 3, { itemId, device(visit) })
end

-- GET GOLD PASS was pressed (Roblox's prompt is up).
function FunnelService.GoldPrompted(player: any)
	if not person(player) then
		return
	end
	local visit = visitOf(player)
	local run = visit.Gold or newRun(visit, "Gold")
	visit.Gold = run
	step(player, Funnels.GoldPass, run, 2, { "", device(visit) })
end

-- The GOLD PASS was bought.
function FunnelService.GoldBought(player: any)
	if not person(player) then
		return
	end
	local visit = visitOf(player)
	step(player, Funnels.GoldPass, visit.Gold or newRun(visit, "Gold"), 3, { "", device(visit) })
	visit.Gold = nil
end

-- A step only the device sees (Funnels.ClientSteps).
local function fromDevice(player: Player, what: any, detail: any)
	if type(what) ~= "string" or not Funnels.ClientSteps[what] or not person(player) then
		return
	end
	local text = if type(detail) == "string" then string.sub(detail, 1, 40) else nil
	local visit = visitOf(player)
	if what == "Device" then
		if text and Funnels.DeviceKinds[text] and not visit.Device then
			visit.Device = text
			if DataService.Get(player) then
				logJoined(player, visit) -- (the profile is in: its Joined steps can go)
			end
		end
	elseif what == "ShopOpen" then
		visit.Shop = newRun(visit, "Shop")
		step(player, Funnels.Shop, visit.Shop, 1, { text, device(visit) })
	elseif what == "ShopPick" then
		local run = visit.Shop or newRun(visit, "Shop")
		visit.Shop = run
		step(player, Funnels.Shop, run, 2, { text, device(visit) })
	elseif what == "GoldSeen" then
		visit.Gold = newRun(visit, "Gold")
		step(player, Funnels.GoldPass, visit.Gold, 1, { "", device(visit) })
	end
end

-- Where they were when they left, on which streak, and for how long they'd played.
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
	event(player, "LeftDuring", minutes, { where, device(visit), Funnels.StreakLabel(visit.Rounds, visit.Lost) })
end

-- Test runs only: every step and event logged so far ("<name> <funnel> <step> <step name> (<fields>)").
function FunnelService.Log(): { string }
	return log
end

-- Test runs only: says a stand-in's device, as its screen would.
function FunnelService.DeviceForTests(player: any, kind: string)
	fromDevice(player, "Device", kind)
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

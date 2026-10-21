-- The one authoritative round state machine (design doc §3 "Round lifecycle states", §14).
-- Waiting -> Intermission -> Voting -> Preparing -> InRound -> Results -> Cleanup -> Intermission ...
--
-- Every mini-game call runs through a guarded runner with a timeout, so a broken or stalled mode
-- ends the round safely instead of trapping the server (§4 "Round end conditions", §19 risks).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local Placement = require(Shared.Logic.Placement)

local BotRegistry = require(script.Parent.BotRegistry)
local BotService = require(script.Parent.BotService)
local DataService = require(script.Parent.DataService)
local LobbyService = require(script.Parent.LobbyService)
local Notifier = require(script.Parent.Notifier)
local RewardService = require(script.Parent.RewardService)
local RoundContext = require(script.Parent.RoundContext)
local Telemetry = require(script.Parent.Telemetry)
local VotingService = require(script.Parent.VotingService)

local MiniGames = require(script.Parent.Parent.MiniGames)

local RoundManager = {}

local session = Config.Session
local roundId = 0
local recentGames: { string } = {}
local currentContext = nil

local function isStudio(): boolean
	return RunService:IsStudio()
end

local function minPlayers(): number
	return if isStudio() then session.MinPlayersInStudio else session.MinPlayers
end

local function ignoreModeLimits(): boolean
	return isStudio() and session.IgnoreModePlayerLimitsInStudio
end

-- Players who can take part: profile loaded and still connected.
local function readyPlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if DataService.Get(player) then
			table.insert(list, player)
		end
	end
	return list
end

-- Everyone who'd play the next round: ready players plus the bots filling in (bots never play
-- without at least one person).
local function participantsNow(): { Player }
	local list = readyPlayers()
	if #list == 0 then
		return list
	end
	for _, bot in BotRegistry.List() do
		if bot.Character then
			table.insert(list, bot)
		end
	end
	return list
end

local function setPhase(phase: string, duration: number?, message: string?)
	GameState.Set("Phase", phase)
	GameState.Set("PhaseEndsAt", if duration then workspace:GetServerTimeNow() + duration else 0)
	GameState.Set("Message", message or "")
	Telemetry.ServerEvent("Phase", { phase = phase, round = roundId })
end

-- Waits for `duration` seconds; returns false early if `abort` reports true.
local function waitFor(duration: number, abort: (() -> boolean)?): boolean
	local deadline = os.clock() + duration
	while os.clock() < deadline do
		if abort and abort() then
			return false
		end
		task.wait(0.2)
	end
	return true
end

local function tooFewPlayers(): boolean
	return #readyPlayers() == 0 or #participantsNow() < minPlayers()
end

-- Runs a mini-game step in its own thread with a timeout so it can never stall the loop.
local function guarded(label: string, timeout: number, fn: (...any) -> any, ...: any): (boolean, any)
	local args = table.pack(...)
	local finished, ok, result = false, false, nil
	local thread = task.spawn(function()
		ok, result = pcall(fn, table.unpack(args, 1, args.n))
		finished = true
	end)
	local deadline = os.clock() + timeout
	while not finished and os.clock() < deadline do
		task.wait()
	end
	if not finished then
		pcall(task.cancel, thread)
		Telemetry.Error("Stalled", `{label} exceeded {timeout}s`)
		return false, "timed out"
	end
	if not ok then
		Telemetry.Error(label, tostring(result))
	end
	return ok, result
end

local function canStart(gameId: string, playerCount: number): boolean
	local module = MiniGames.Get(gameId)
	if not module then
		return false
	end
	return module.CanStart(playerCount, ignoreModeLimits())
end

-- If the vote winner can't run with the current players, fall back to the next best valid option.
local function chooseRunnableGame(winnerId: string, playerCount: number): string?
	if canStart(winnerId, playerCount) then
		return winnerId
	end
	for _, option in VotingService.Options() do
		if canStart(option.Id, playerCount) then
			return option.Id
		end
	end
	for _, definition in GameDefinitions.List do
		if canStart(definition.Id, playerCount) then
			return definition.Id
		end
	end
	return nil
end

local function cleanupContext()
	local context = currentContext
	currentContext = nil
	if context then
		local ok, err = pcall(context.Destroy, context)
		if not ok then
			Telemetry.Error("Cleanup", tostring(err))
		end
	end
end

local function runRound(definition, participants: { Player })
	local module = MiniGames.Get(definition.Id)
	roundId += 1
	GameState.Set("RoundId", roundId)
	GameState.Set("GameId", definition.Id)

	local context = RoundContext.new(roundId, definition, participants)
	currentContext = context
	local miniGame = module.new(context)

	-- Preparing: build the arena, place players frozen, show the rules card and countdown.
	local prepTime = session.RulesTime + session.CountdownTime
	local prepDeadline = os.clock() + prepTime
	setPhase("Preparing", prepTime, definition.Name)
	local prepared = guarded("Prepare:" .. definition.Id, prepTime + 10, miniGame.Prepare, miniGame)
	if not prepared or #context:GetPlayers() == 0 then
		Notifier.All("That game couldn't start, so we're heading back to the lobby. Sorry!", "warning", 5)
		guarded("Cleanup:" .. definition.Id, 5, miniGame.Cleanup, miniGame)
		cleanupContext()
		return
	end
	waitFor(math.max(0, prepDeadline - os.clock()))

	-- InRound
	context:Begin()
	setPhase("InRound", definition.Duration, definition.Name)
	Telemetry.ServerEvent("RoundStarted", { round = roundId, game = definition.Id, players = context.StartCount })
	local started = guarded("Start:" .. definition.Id, 5, miniGame.Start, miniGame)
	if not started then
		context:End("Error")
	else
		context:RunBots(MiniGames.Brain(definition.Id), miniGame)
	end

	local roundStart = os.clock()
	local timeUp = roundStart + definition.Duration
	local hardStop = timeUp + session.RoundGraceTime
	while not context.EndReason do
		local now = os.clock()
		if now >= timeUp then
			context:End("TimeUp")
		elseif #context:GetPlayers() == 0 then
			context:End("NoPlayers")
		elseif now >= hardStop then
			context:End("Watchdog")
		end
		task.wait(0.1)
	end
	guarded("Stop:" .. definition.Id, 5, miniGame.Stop, miniGame, context.EndReason)
	Telemetry.ServerEvent("RoundEnded", {
		round = roundId,
		game = definition.Id,
		reason = context.EndReason,
		duration = math.floor(os.clock() - roundStart),
		players = #context:GetPlayers(),
	})

	-- Results: freeze scores, grant rewards, show placements.
	local champions = {}
	if context.EndReason ~= "Error" and context.EndReason ~= "NoPlayers" then
		local ok, results = guarded("GetResults:" .. definition.Id, 5, miniGame.GetResults, miniGame)
		if ok and results then
			local entries = {}
			for _, entry in results.Entries do
				if entry.Player.Parent then
					entry.Key = entry.Player
					table.insert(entries, entry)
				end
			end
			local placed = Placement.Assign(entries)
			local granted = pcall(RewardService.GrantRound, definition, placed, results.WinningTeam)
			if not granted then
				Telemetry.Error("Rewards", definition.Id)
			end
			for index = 1, math.min(3, #placed) do
				local entry = placed[index].Entry :: any
				table.insert(
					champions,
					{ Name = entry.Player.DisplayName, UserId = entry.Player.UserId, Place = placed[index].Place }
				)
			end
		end
	else
		Notifier.All("Round ended early - no rewards this time.", "warning")
	end
	LobbyService.SetChampions(champions)
	setPhase("Results", session.ResultsTime, definition.Name)
	waitFor(session.ResultsTime)

	-- Cleanup
	setPhase("Cleanup", nil, "Back to the lobby!")
	guarded("Cleanup:" .. definition.Id, 5, miniGame.Cleanup, miniGame)
	cleanupContext()
	Notifier.Sound(nil, "ReturnToLobby")
	GameState.Set("GameId", "")
	task.delay(1, BotService.Rebalance) -- bots that stayed for this round can make room now

	table.insert(recentGames, 1, definition.Id)
	while #recentGames > 5 do
		table.remove(recentGames)
	end
end

local function runCycle()
	-- Waiting for enough players
	while tooFewPlayers() do
		local needed = math.max(1, minPlayers() - #participantsNow())
		setPhase(
			"Waiting",
			nil,
			if needed == 1 then "Waiting for 1 more player..." else `Waiting for {needed} more players...`
		)
		task.wait(1)
	end

	-- Lobby social time
	local intermission = if isStudio() then Config.Debug.StudioIntermissionTime else session.IntermissionTime
	setPhase("Intermission", intermission, "Next vote soon!")
	if not waitFor(intermission, tooFewPlayers) then
		return
	end

	-- Voting
	-- Only people vote, but the options have to fit everyone who'll play, bots included.
	local options = VotingService.BuildOptions(#participantsNow(), recentGames, ignoreModeLimits())
	local forced = Config.Debug.ForceGame
	if isStudio() and forced ~= "" then
		if GameDefinitions.Get(forced) then
			options = { { Id = forced, Mystery = false } }
		else
			warn(`[RoundManager] Config.Debug.ForceGame '{forced}' is not a known mini-game id`)
		end
	end
	if #options == 0 then
		setPhase("Waiting", nil, "No games available for this many players.")
		task.wait(3)
		return
	end
	setPhase("Voting", session.VoteTime, "Vote for the next game!")
	VotingService.Begin(options)
	waitFor(session.VoteTime)
	local winner, _, wasTie = VotingService.End()
	if not winner then
		return
	end

	local participants = participantsNow()
	if #participants < minPlayers() then
		Notifier.All("Not enough players to start - back to the lobby.", "warning")
		return
	end

	local gameId = chooseRunnableGame(winner.Id, #participants)
	if not gameId then
		Notifier.All("No game can run with this many players right now.", "warning")
		return
	end
	local definition = GameDefinitions.Get(gameId)
	local winnerDefinition = GameDefinitions.Get(winner.Id)
	if not definition or not winnerDefinition then
		return
	end
	if gameId ~= winner.Id then
		Notifier.All(
			`{winnerDefinition.Name} needs more players - playing {definition.Icon} {definition.Name} instead!`,
			"warning",
			5
		)
	else
		local suffix = if winner.Mystery then " (Mystery revealed!)" elseif wasTie then " (tie broken randomly)" else ""
		Notifier.All(`{definition.Icon} {definition.Name} wins the vote!{suffix}`, "success", 4)
	end
	Telemetry.ServerEvent("GameSelected", { game = gameId, tie = wasTie, mystery = winner.Mystery })

	runRound(definition, participants)
end

function RoundManager.Start()
	while true do
		local ok, err = pcall(runCycle)
		if not ok then
			-- Last line of defense: log, clean up whatever was running and return everyone to the lobby.
			Telemetry.Error("RoundCycle", tostring(err))
			cleanupContext()
			setPhase("Intermission", 5, "Something went wrong - restarting the round.")
			task.wait(5)
		end
	end
end

function RoundManager.Init()
	Players.PlayerAdded:Connect(function(player)
		task.delay(4, function()
			local phase = GameState.Get("Phase")
			if player.Parent and (phase == "Preparing" or phase == "InRound" or phase == "Results") then
				Notifier.Send(
					player,
					"A round is in progress - the next vote begins soon! Explore the lobby meanwhile.",
					"info",
					6
				)
			end
		end)
	end)
end

return RoundManager

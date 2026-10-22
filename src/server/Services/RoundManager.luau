-- The one authoritative round state machine (design doc §3 "Round lifecycle states", §14).
-- Waiting -> Intermission -> Voting -> Preparing -> InRound -> Results -> Cleanup -> Intermission ...
--
-- Every mini-game call runs through a guarded runner with a timeout, so a broken or stalled mode
-- ends the round safely instead of trapping the server (§4 "Round end conditions", §19 risks).
--
-- Who plays comes from SitOutService.Lineup: people sitting out the next rounds (owner: "we do
-- need to add somewhere super apparent a toggle where you skip next round") stay in the lobby and
-- aren't counted; when everyone here is on a break, rounds wait in the lobby ("Everyone's taking a
-- break!") instead of running with bots only. For the same reason a round whose people all leave or
-- can't be placed during the rules card is called off before GO (RoundContext.WaitForStart).
--
-- Between two rounds the results, the lobby and the vote take 20 seconds at most (owner: "Less time
-- sitting in the lobby. total of 20 seconds instead of 40."; Config.Session's ResultsTime,
-- IntermissionTime and VoteTime), and the vote ends early once every person playing has voted
-- (VotingService.Wait).
--
-- The results cards ask PLAY AGAIN? (owner: "Add a vote at the end of each minigame to replay the
-- same minigame."; Services/ReplayService): if more than half of the round's people say yes, the
-- next round is the same game straight away, Results -> Cleanup -> Preparing with no lobby time and
-- no game vote, announced to everyone ("🔁 REPLAY! PUMP & POP again"). It still needs enough players
-- for the game (bots someone joining replaced leave first: there's no lobby time for them to fade
-- out in), and a fresh round, so team games deal their teams again. At most Config.Session.MaxReplays
-- replays in a row, and a replay doesn't add the game to the vote's recent list again
-- (Logic/ReplayVote.Remember): the next vote still skips it and plays down the game before it.
--
-- Bug sweep (owner: "Let's do a full bug and clean sweep."): someone who joins just before a round
-- (during the vote, or during the results before a replay) and loads in time plays it, but 4 s in
-- they were still told "A round is in progress ... Explore the lobby meanwhile" over the rules
-- card. That's only said to newcomers the round didn't take in now.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local Placement = require(Shared.Logic.Placement)
local ReplayVote = require(Shared.Logic.ReplayVote)
local Roster = require(Shared.Logic.Roster)

local BotRegistry = require(script.Parent.BotRegistry)
local BotService = require(script.Parent.BotService)
local LobbyService = require(script.Parent.LobbyService)
local Notifier = require(script.Parent.Notifier)
local ReplayService = require(script.Parent.ReplayService)
local RatingService = require(script.Parent.RatingService)
local RewardService = require(script.Parent.RewardService)
local RoundEvents = require(script.Parent.RoundEvents)
local RoundContext = require(script.Parent.RoundContext)
local SitOutService = require(script.Parent.SitOutService)
local Telemetry = require(script.Parent.Telemetry)
local VotingService = require(script.Parent.VotingService)

local MiniGames = require(script.Parent.Parent.MiniGames)

local RoundManager = {}

local session = Config.Session
local roundId = 0
local recentGames: { string } = {}
local currentContext = nil
local replayNext: string? = nil -- the game the last round's PLAY AGAIN vote chose to play again
local replayStreak = 0 -- replays in a row of the game being played (Config.Session.MaxReplays at most)

local function isStudio(): boolean
	return RunService:IsStudio()
end

local function minPlayers(): number
	return if isStudio() then session.MinPlayersInStudio else session.MinPlayers
end

local function ignoreModeLimits(): boolean
	return isStudio() and session.IgnoreModePlayerLimitsInStudio
end

-- Everyone who'd play the next round: people who are ready and not sitting out, plus the bots
-- filling in (bots never play without at least one person).
local function participantsNow(): { Player }
	return SitOutService.Lineup().Participants
end

-- Why the next round can't start yet ("" when it can), and how many more players it needs.
local function blocker(): (string, number)
	return Roster.Blocker(SitOutService.Lineup(), minPlayers())
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
	return (blocker()) ~= ""
end

local function everyoneOnBreak(): boolean
	return (blocker()) == "Break"
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
	-- Bots never play on their own: a round whose people all left or couldn't be placed before GO is
	-- called off too (owner: "it just has to work"; it used to go on with only bots).
	if not prepared or not context:WaitForStart(prepDeadline) then
		Notifier.All(
			if prepared
				then "Nobody's left to play that game - back to the lobby!"
				else "That game couldn't start, so we're heading back to the lobby. Sorry!",
			"warning",
			5
		)
		guarded("Cleanup:" .. definition.Id, 5, miniGame.Cleanup, miniGame)
		cleanupContext()
		return
	end

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
			context:TimeRanOut("TimeUp") -- now, or after a moment for anything in flight (RoundContext.HoldEnd)
		elseif #context:GetPlayers() == 0 then
			context:End("NoPlayers")
		elseif now >= hardStop then
			context:End("Watchdog")
		end
		if context.EndReason then
			break -- Stop right away, so nothing keeps moving on screen after scoring has closed
		end
		task.wait() -- every frame: however the round ends, Stop follows within one
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
	local carded = false -- the round's people got their results cards, where the PLAY AGAIN vote is
	if context.EndReason ~= "Error" and context.EndReason ~= "NoPlayers" then
		local ok, results = guarded("GetResults:" .. definition.Id, 5, miniGame.GetResults, miniGame)
		if ok and results then
			carded = true
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
			RoundEvents.Finished:Fire(definition, placed, results.WinningTeam) -- cups, leaderboard, medals...
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
	-- PLAY AGAIN? on the results cards. Once everyone who can has answered, the results end a moment
	-- after the last answer (but the cards get ResultsMinTime first).
	-- 👍 / 👎 on the game, beside it (Services/RatingService): written when the results end.
	ReplayService.Begin(definition.Id, if carded then context:GetPlayers() else {}, replayStreak)
	RatingService.Begin(definition.Id, if carded then context:GetPlayers() else {})
	ReplayService.Wait(session.ResultsTime, session.ResultsMinTime)
	local replayOffered = ReplayService.IsOpen()
	local again, replayTally = ReplayService.End()
	RatingService.End(if replayOffered then replayTally else nil)

	-- Cleanup, then the lobby, or the same game again (said before the phase changes, so the lobby's
	-- celebrations wait for real lobby time: CelebrationController).
	local replayLine = `🔁 REPLAY! {string.upper(definition.Name)} again`
	if again then
		replayNext = definition.Id
		GameState.Set("Replay", definition.Id)
	end
	setPhase("Cleanup", nil, if again then replayLine else "Back to the lobby!")
	if again then
		Notifier.All(replayLine, "success", 5)
	end
	guarded("Cleanup:" .. definition.Id, 5, miniGame.Cleanup, miniGame)
	cleanupContext()
	if not again then
		Notifier.Sound(nil, "ReturnToLobby") -- (a replay goes straight back into the game)
	end
	GameState.Set("GameId", "")
	task.delay(1, BotService.Rebalance) -- bots that stayed for this round can make room now

	recentGames = ReplayVote.Remember(recentGames, definition.Id, 5)
end

-- Bots that someone joining during the round has replaced fade out in the lobby between rounds; a
-- replay has no lobby time, so they go now (BotService takes one at a time).
local function trimBots()
	for _ = 1, session.MaxPlayers do
		if #BotRegistry.List() <= BotService.Desired() then
			return
		end
		BotService.Rebalance()
	end
end

-- The same game again straight away (the last round's PLAY AGAIN vote passed): no lobby time and no
-- game vote. It still needs someone to play and enough players for the game; returns false (and
-- says so) when it can't go, and the lobby and the vote follow as usual.
local function startReplay(id: string): boolean
	local definition = GameDefinitions.Get(id)
	trimBots()
	local lineup = SitOutService.Lineup()
	local reason = Roster.Blocker(lineup, minPlayers())
	if not definition or reason ~= "" or not canStart(id, #lineup.Participants) then
		GameState.Set("Replay", "")
		if definition and reason ~= "Break" then -- a break shows on the lobby banner
			Notifier.All(
				`Not enough players for {string.upper(definition.Name)} again - next, a new vote!`,
				"warning",
				5
			)
		end
		return false
	end
	replayStreak += 1
	-- The lobby's vote stage shows no winner for it: this round wasn't voted for.
	GameState.SetJSON("VoteOptions", {})
	GameState.SetJSON("VoteCounts", {})
	Telemetry.ServerEvent("GameSelected", { game = id, replay = replayStreak })
	runRound(definition, lineup.Participants)
	if not replayNext then
		-- Called off before GO (no results, so no new vote): the replay isn't announced any more.
		GameState.Set("Replay", "")
	end
	return true
end

local function runCycle()
	-- The same game again, if the last round's players voted for it (and it can go now).
	local replay = replayNext
	replayNext = nil
	if replay and startReplay(replay) then
		return
	end

	-- Waiting for enough players (or for someone to come back from a break)
	while true do
		local reason, needed = blocker()
		if reason == "" then
			break
		end
		setPhase("Waiting", nil, Roster.WaitingMessage(reason, needed))
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
	-- Nobody can vote once everyone is sitting out: back to the lobby to wait for them. Once every
	-- person playing has voted, it ends a moment after the last vote instead of running its time.
	local voted = VotingService.Wait(session.VoteTime, everyoneOnBreak)
	local winner, counts, wasTie = VotingService.End()
	RatingService.NoteVote(VotingService.Options(), winner, counts) -- how often each game is offered and wins
	if not voted or not winner then
		return
	end

	local lineup = SitOutService.Lineup()
	local reason = Roster.Blocker(lineup, minPlayers())
	if reason ~= "" then
		if reason ~= "Break" then -- a break shows on the lobby banner
			Notifier.All("Not enough players to start - back to the lobby.", "warning")
		end
		return
	end
	local participants = lineup.Participants

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
		local suffix = if winner.Mystery then " (the Random pick!)" elseif wasTie then " (tie broken randomly)" else ""
		Notifier.All(`{definition.Icon} {definition.Name} wins the vote!{suffix}`, "success", 4)
	end
	Telemetry.ServerEvent("GameSelected", { game = gameId, tie = wasTie, mystery = winner.Mystery })

	replayStreak = 0 -- a voted game: its own run of replays starts here
	runRound(definition, participants)
end

function RoundManager.Start()
	while true do
		local ok, err = pcall(runCycle)
		if not ok then
			-- Last line of defense: log, clean up whatever was running and return everyone to the lobby.
			Telemetry.Error("RoundCycle", tostring(err))
			cleanupContext()
			replayNext = nil
			GameState.Set("Replay", "")
			setPhase("Intermission", 5, "Something went wrong - restarting the round.")
			task.wait(5)
		end
	end
end

function RoundManager.Init()
	Players.PlayerAdded:Connect(function(player)
		task.delay(4, function()
			local phase = GameState.Get("Phase")
			-- (Not to someone the round took in: they joined just before it, or a replay, and play it.)
			if
				player.Parent
				and (phase == "Preparing" or phase == "InRound" or phase == "Results")
				and player:GetAttribute("PP_InRound") ~= true
			then
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

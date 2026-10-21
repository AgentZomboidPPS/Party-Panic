-- Skee-Ball in the lobby arcade (owner: "Can we also add skiball to the lobby?"; World/Arcade builds
-- the machines). The server runs every game: a player takes a free machine with its prompt and
-- rolls nine balls; each roll's aim and power are checked here, and Shared/Logic/SkeeBall decides
-- where the ball goes (the same path every device draws, so what you see is what you score). It
-- keeps the score, the player's best (in their profile: Stats.Best.SkeeBall) and the arcade's
-- TODAY'S BEST board. No coins (rewards are being rebalanced): just the joy of beating your best.
--
-- A machine is one player's at a time. Their game ends cleanly and the machine frees up when they
-- step away from it or press DONE, reset or leave, when a round pulls them in (PP_InRound), or
-- after a while without rolling.
--
-- Review pass (same request): any aim and power is a roll a finger could make, so the server
-- checks a roll's range, its ball number and its timing (not after the last ball came down, never
-- twice at once), and a ball from a game that ended scores nothing. Someone sitting out can play
-- right through the rounds; anyone else's game ends the moment a round takes them (their device
-- ends it too, before the round's camera starts). The "someone's playing this one" note only
-- shows when someone else really is, and a game that ends for idling says so.
--
-- The "SkeeBall" remote, both ways:
--   client -> server  ("Roll", ball, aim, power)   ("Again")   ("Leave")
--   server -> client  ("Start", index, best)                                   the player
--                     ("Rolled", index, ball, aimQ, powerQ, pocket, points)     everyone
--                     ("Over", index, userId, score, best, newBest, todayRank)  everyone
--                     ("End", index, reason)                                    the player
-- Each machine's attributes (everyone's screens draw them): SkeeUser (UserId, 0 when free),
-- SkeeName, SkeeScore, SkeeBalls (rolled so far), SkeeState ("Idle" | "Playing" | "Over") and
-- SkeeBest (the player's best before this game). The board's attribute Board holds today's top
-- five as JSON ({ N = name, S = score, U = userId }).

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local DailyLogic = require(Shared.Logic.DailyLogic)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local SkeeBall = require(Shared.Logic.SkeeBall)

local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local RateLimiter = require(script.Parent.RateLimiter)
local Telemetry = require(script.Parent.Telemetry)

local SkeeBallService = {}

local BEST_KEY = "SkeeBall" -- in the profile's Stats.Best (personal bests by game)
local LEAVE_DISTANCE = 9 -- a player further than this from their machine's stand has left it
local IDLE_TIME = 45 -- seconds without a roll before a machine frees up
local OVER_HOLD = 15 -- after the last ball, the machine waits this long for PLAY AGAIN
-- A roll may come this much before the last ball landed: the device rolls as soon as it saw it
-- land, and a phone's ping can bunch two messages up (rolling early wins nothing; a refused roll
-- would put back a ball the player already saw drop in).
local ROLL_SLACK = 0.6
local MIN_GAP = 0.45 -- but never closer than this to the last roll
local BOARD_SIZE = 5
local CHECK_EVERY = 0.25

type Session = {
	Player: Player,
	Machine: Model,
	Index: number,
	Stand: BasePart,
	Prompt: ProximityPrompt?,
	Ball: number, -- balls rolled so far
	Score: number,
	Best: number, -- the player's best before this game
	State: string, -- "Playing" | "Over"
	NextRollAt: number,
	LastRollAt: number,
	LastActive: number,
	OverAt: number,
	Token: number, -- bumps every game: a ball still dropping in from an earlier one scores nothing
	Connections: { RBXScriptConnection },
}

local remote = Remotes.Get("SkeeBall")
local limiter = RateLimiter.new(20, 4)
local machines: { [number]: Model } = {}
local sessions: { [Player]: Session } = {}
local byMachine: { [number]: Session } = {}
local board: BasePart? = nil
local today = { Day = -1, Entries = {} :: { { U: number, N: string, S: number, At: number } } }

local function standOf(machine: Model): BasePart?
	return machine:FindFirstChild("Stand") :: BasePart?
end

local function setIdle(machine: Model)
	machine:SetAttribute("SkeeUser", 0)
	machine:SetAttribute("SkeeName", "")
	machine:SetAttribute("SkeeScore", 0)
	machine:SetAttribute("SkeeBalls", 0)
	machine:SetAttribute("SkeeState", "Idle")
	machine:SetAttribute("SkeeBest", 0)
end

local function profileBest(player: Player): number
	local profile = DataService.Get(player)
	local best = profile and profile.Data.Stats.Best[BEST_KEY]
	return if type(best) == "number" then best else 0
end

-- Today's best board: one entry per player (their best today), the top BOARD_SIZE shown.
local function publishBoard()
	if not board then
		return
	end
	local rows = {}
	for index = 1, math.min(BOARD_SIZE, #today.Entries) do
		local entry = today.Entries[index]
		table.insert(rows, { N = entry.N, S = entry.S, U = entry.U })
	end
	board:SetAttribute("Board", HttpService:JSONEncode(rows))
	board:SetAttribute("Day", today.Day)
end

local function rollOverDay()
	local day = DailyLogic.DayNumber(os.time())
	if day ~= today.Day then
		today.Day = day
		table.clear(today.Entries)
		publishBoard()
	end
end

-- Records a finished game on today's board. Returns the player's place if this game put them on
-- it (or moved them up), else nil.
local function recordToday(player: Player, score: number): number?
	rollOverDay()
	if score <= 0 then
		return nil
	end
	local entries = today.Entries
	local mine = nil
	for _, entry in entries do
		if entry.U == player.UserId then
			mine = entry
		end
	end
	if mine and mine.S >= score then
		return nil
	end
	if mine then
		mine.S, mine.N, mine.At = score, player.DisplayName, os.clock()
	else
		mine = { U = player.UserId, N = player.DisplayName, S = score, At = os.clock() }
		table.insert(entries, mine)
	end
	-- Highest first; on a tie, whoever got there first stays ahead.
	table.sort(entries, function(a, b)
		return if a.S == b.S then a.At < b.At else a.S > b.S
	end)
	while #entries > 20 do
		table.remove(entries)
	end
	local place = table.find(entries, mine)
	publishBoard()
	return if place and place <= BOARD_SIZE then place else nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Ends a player's game and frees their machine (and tells their device, if they're still here).
function SkeeBallService.End(player: Player, reason: string)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	byMachine[session.Index] = nil
	session.Token += 1
	for _, connection in session.Connections do
		connection:Disconnect()
	end
	setIdle(session.Machine)
	if session.Prompt then
		session.Prompt.Enabled = true
	end
	if player.Parent then
		remote:FireClient(player, "End", session.Index, reason)
	end
end

local function begin(session: Session)
	local machine = session.Machine
	session.Token += 1
	session.Ball = 0
	session.Score = 0
	session.State = "Playing"
	session.NextRollAt = 0
	session.LastRollAt = 0
	session.LastActive = os.clock()
	session.Best = profileBest(session.Player)
	machine:SetAttribute("SkeeUser", session.Player.UserId)
	machine:SetAttribute("SkeeName", session.Player.DisplayName)
	machine:SetAttribute("SkeeScore", 0)
	machine:SetAttribute("SkeeBalls", 0)
	machine:SetAttribute("SkeeBest", session.Best)
	machine:SetAttribute("SkeeState", "Playing")
	remote:FireClient(session.Player, "Start", session.Index, session.Best)
end

-- Takes machine `index` for `player`. Returns whether they got it.
function SkeeBallService.Join(player: Player, index: number): boolean
	local machine = machines[index]
	if not machine or sessions[player] or byMachine[index] then
		return false
	end
	if player:GetAttribute("PP_InRound") == true and player:GetAttribute("PP_Alive") == true then
		return false -- playing a round (only someone who's out can wander back to the lobby)
	end
	local stand = standOf(machine)
	local root = rootOf(player)
	if not stand or not root or flatDistance(root.Position, stand.Position) > LEAVE_DISTANCE then
		return false
	end
	local session: Session = {
		Player = player,
		Machine = machine,
		Index = index,
		Stand = stand,
		Prompt = stand:FindFirstChildOfClass("ProximityPrompt"),
		Ball = 0,
		Score = 0,
		Best = 0,
		State = "Playing",
		NextRollAt = 0,
		LastRollAt = 0,
		LastActive = os.clock(),
		OverAt = 0,
		Token = 0,
		Connections = {},
	}
	sessions[player] = session
	byMachine[index] = session
	if session.Prompt then
		session.Prompt.Enabled = false
	end
	-- A new character (a reset), or being pulled into a round, ends the game.
	table.insert(
		session.Connections,
		player.CharacterAdded:Connect(function()
			SkeeBallService.End(player, "Reset")
		end)
	)
	table.insert(
		session.Connections,
		player:GetAttributeChangedSignal("PP_InRound"):Connect(function()
			if player:GetAttribute("PP_InRound") == true then
				SkeeBallService.End(player, "Round")
			end
		end)
	)
	begin(session)
	Telemetry.PlayerEvent(player, "SkeeBallStart", index)
	return true
end

local function finish(session: Session)
	local player = session.Player
	session.State = "Over"
	session.OverAt = os.clock()
	session.Machine:SetAttribute("SkeeState", "Over")
	local score = session.Score
	local previous = session.Best
	local newBest = score > previous and score > 0
	if newBest then
		local profile = DataService.Get(player)
		if profile then
			profile.Data.Stats.Best[BEST_KEY] = score
			DataService.Changed(player)
		end
	end
	local place = recordToday(player, score)
	remote:FireAllClients("Over", session.Index, player.UserId, score, previous, newBest, place or 0)
	-- A new best or a place on the board gets a little party over the machine for everyone.
	local over = session.Machine:GetPivot() * CFrame.new(0, SkeeBall.SIGN_Y + 1.5, SkeeBall.SIGN_Z)
	if newBest or place then
		Notifier.Effect("Confetti", over.Position)
	end
	if place == 1 then
		Notifier.Effect("Fireworks", over.Position + Vector3.new(0, 4, 0))
	end
	Telemetry.PlayerEvent(player, "SkeeBallGame", score)
end

-- A roll from the player at their machine: `ball` is which ball (1..9), aim -1..1, power 0..1.
-- Returns the path the server rolled, or nil if the roll was refused.
function SkeeBallService.Roll(player: Player, ball: any, aim: any, power: any): SkeeBall.Path?
	local session = sessions[player]
	if not session or session.State ~= "Playing" then
		return nil
	end
	if type(ball) ~= "number" or type(aim) ~= "number" or type(power) ~= "number" then
		return nil
	end
	if ball ~= session.Ball + 1 or ball > SkeeBall.BALLS then
		return nil
	end
	if aim ~= aim or power ~= power or math.abs(aim) > 1.001 or power < -0.001 or power > 1.001 then
		return nil
	end
	local now = os.clock()
	if now < session.NextRollAt - ROLL_SLACK or now - session.LastRollAt < MIN_GAP then
		return nil
	end
	local aimQ, powerQ = SkeeBall.Quantize(aim, power)
	local path = SkeeBall.Path(aimQ, powerQ, ball)
	session.Ball = ball
	session.LastRollAt = now
	session.NextRollAt = now + path.Landed
	session.LastActive = now
	session.Machine:SetAttribute("SkeeBalls", ball)
	remote:FireAllClients("Rolled", session.Index, ball, aimQ, powerQ, path.Pocket, path.Points)
	-- The points count when the ball drops in, when everyone sees it go in.
	local token = session.Token
	task.delay(path.Done, function()
		if session.Token ~= token or sessions[player] ~= session then
			return
		end
		session.Score += path.Points
		session.Machine:SetAttribute("SkeeScore", session.Score)
		if ball == SkeeBall.BALLS then
			finish(session)
		end
	end)
	return path
end

function SkeeBallService.Again(player: Player): boolean
	local session = sessions[player]
	if not session or session.State ~= "Over" then
		return false
	end
	begin(session)
	return true
end

function SkeeBallService.SessionOf(player: Player): Session?
	return sessions[player]
end

local function onRemote(player: Player, action: any, ...: any)
	if typeof(player) == "Instance" and not limiter:Check(player) then
		return
	end
	if action == "Roll" then
		SkeeBallService.Roll(player, ...)
	elseif action == "Again" then
		SkeeBallService.Again(player)
	elseif action == "Leave" then
		SkeeBallService.End(player, "Left")
	end
end

-- Walking away, a fallen character, idling, or a game left over without PLAY AGAIN ends it.
local function check()
	local now = os.clock()
	for player, session in sessions do
		local root = rootOf(player)
		if not player.Parent then
			SkeeBallService.End(player, "Gone")
		elseif not root or flatDistance(root.Position, session.Stand.Position) > LEAVE_DISTANCE then
			SkeeBallService.End(player, "Away")
		elseif session.State == "Playing" and now - session.LastActive > IDLE_TIME then
			SkeeBallService.End(player, "Idle")
			Notifier.Send(player, "No rolls for a while, so the SKEE-BALL machine is free again.", "info", 4)
		elseif session.State == "Over" and now - session.OverAt > OVER_HOLD then
			SkeeBallService.End(player, "Done")
		end
	end
end

local function addMachine(machine: Instance)
	if not machine:IsA("Model") then
		return
	end
	local index = machine:GetAttribute("SkeeIndex")
	if type(index) ~= "number" or machines[index] == machine then
		return
	end
	machines[index] = machine
	setIdle(machine)
	local stand = standOf(machine)
	local prompt = stand and stand:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(player)
			local taken = byMachine[index]
			if not SkeeBallService.Join(player, index) and taken and taken.Player ~= player then
				Notifier.Send(player, "Someone's playing this one - try the next machine!", "info", 3)
			end
		end)
	end
end

function SkeeBallService.Init()
	for _, machine in CollectionService:GetTagged("SkeeMachine") do
		addMachine(machine)
	end
	CollectionService:GetInstanceAddedSignal("SkeeMachine"):Connect(addMachine)
	board = CollectionService:GetTagged("SkeeBestBoard")[1]
	CollectionService:GetInstanceAddedSignal("SkeeBestBoard"):Connect(function(part)
		board = part :: BasePart
		publishBoard()
	end)
	rollOverDay()
	publishBoard()

	remote.OnServerEvent:Connect(onRemote)
	Players.PlayerRemoving:Connect(function(player)
		SkeeBallService.End(player, "Gone")
	end)
	-- When a round's Preparing phase starts, everyone in it is pulled away: free their machines
	-- (PP_InRound catches it too; this is the belt to its braces).
	GameState.Changed("Phase", function(phase)
		if phase ~= "Preparing" then
			return
		end
		for player in sessions do
			if player:GetAttribute("PP_InRound") == true then
				SkeeBallService.End(player, "Round")
			end
		end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= CHECK_EVERY then
			elapsed = 0
			check()
		end
	end)
end

return SkeeBallService

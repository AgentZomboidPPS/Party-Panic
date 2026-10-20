-- Per-round helper handed to every mini-game. It owns the participants, the arena instance,
-- scoring, eliminations, respawns, timers and cleanup, so each mini-game only describes its rules.
--
-- Safety rules from the design doc that live here:
--   * a leaving player is removed from scoring and never blocks round completion (§4)
--   * failed spawns retry once, then the player safely stays in the lobby (§4)
--   * delayed callbacks are bound to this round and die with it (§4 "round ID")
--   * cleanup is idempotent and restores characters (§7, §14)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local Janitor = require(Shared.Janitor)
local Remotes = require(Shared.Remotes)

local CosmeticService = require(script.Parent.CosmeticService)
local Notifier = require(script.Parent.Notifier)
local Telemetry = require(script.Parent.Telemetry)

local LOBBY_RADIUS = 600

local actionRemote = Remotes.Get("MiniGameAction")
local eventRemote = Remotes.Get("MiniGameEvent")
local rng = Random.new()

type ActionEntry = {
	Handler: (player: Player, ...any) -> (),
	Interval: number,
	AliveOnly: boolean,
	Last: { [Player]: number },
}

local RoundContext = {}
RoundContext.__index = RoundContext

export type Participant = {
	Alive: boolean,
	Score: number,
	ScoreText: string,
	Team: string?,
	EliminatedAt: number?,
	Data: { [string]: any }, -- free space for mini-game specific state
}

export type ResultEntry = {
	Player: Player,
	Rank: number,
	ScoreText: string,
	BestScore: number?,
	Survived: number?,
	Team: string?,
}

export type Results = {
	Entries: { ResultEntry },
	WinningTeam: string?,
}

function RoundContext.new(roundId: number, definition, players: { Player })
	local self = setmetatable({}, RoundContext)
	self.RoundId = roundId
	self.Definition = definition
	self.Origin = CFrame.new(Config.ArenaOrigin)
	self.Janitor = Janitor.new()
	self.Participants = {} :: { [Player]: Participant }
	self.Active = true
	self.Started = false
	self.StartTime = 0
	self.StartCount = 0
	self.EndReason = nil :: string?
	self.Destroyed = false
	self.RespawnMode = "Eliminate" -- "Eliminate" | "Respawn"
	self.EndWhenOneLeft = false
	self.KillY = Config.ArenaOrigin.Y - 40
	self.WalkSpeed = StarterPlayer.CharacterWalkSpeed
	self.TeamScores = nil :: { [string]: number }?
	self.StartServerTime = 0
	self._actions = {} :: { [string]: ActionEntry }
	self._sharedKeys = {} :: { [string]: boolean }
	self._playerKeys = {} :: { [string]: boolean }
	self._stunnedUntil = {} :: { [Player]: number }
	self.Hooks = {
		Respawn = nil :: ((player: Player) -> CFrame?)?,
		CharacterReady = nil :: ((player: Player, character: Model) -> ())?,
		Eliminated = nil :: ((player: Player, reason: string) -> ())?,
		PlayerLeft = nil :: ((player: Player) -> ())?,
	}

	local arena = Instance.new("Model")
	arena.Name = "Arena_" .. definition.Id
	arena.Parent = workspace
	self.Arena = arena

	for _, player in players do
		self.Participants[player] = {
			Alive = true,
			Score = 0,
			ScoreText = "",
			Team = nil,
			EliminatedAt = nil,
			Data = {},
		}
		player:SetAttribute("PP_InRound", true)
		player:SetAttribute("PP_Alive", true)
		player:SetAttribute("PP_Score", 0)
		player:SetAttribute("PP_ScoreText", "")
		player:SetAttribute("PP_Team", "")
		self:_watchPlayer(player)
	end

	self.Janitor:Add(Players.PlayerRemoving:Connect(function(player)
		self:_onLeave(player)
	end))
	self.Janitor:Add(actionRemote.OnServerEvent:Connect(function(player, name, ...)
		self:_onAction(player, name, ...)
	end))

	-- Fall / out-of-bounds check (server side so clients can't skip it).
	local accumulator = 0
	self.Janitor:Add(RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.15 then
			return
		end
		accumulator = 0
		if not self:IsRunning() then
			return
		end
		for player, state in self.Participants do
			if not state.Alive then
				continue
			end
			local _, _, root = self:GetCharacter(player)
			if root and root.Position.Y < self.KillY then
				if self.RespawnMode == "Eliminate" then
					self:Eliminate(player, "fell")
				else
					self:Respawn(player)
				end
			end
		end
	end))

	GameState.Set("Status", "")
	GameState.Set("TeamScores", "")
	return self
end

export type RoundContext = typeof(RoundContext.new(0, {}, {}))

-- Lifecycle ----------------------------------------------------------------------------------

function RoundContext.IsRunning(self: RoundContext): boolean
	return self.Active and self.Started and self.EndReason == nil
end

function RoundContext.Begin(self: RoundContext)
	self.Started = true
	self.StartTime = os.clock()
	self.StartServerTime = workspace:GetServerTimeNow()
	self.StartCount = #self:GetPlayers()
	self:UnfreezeAll()
	Notifier.Sound(nil, "RoundStart")
end

function RoundContext.End(self: RoundContext, reason: string)
	if self.EndReason then
		return
	end
	self.EndReason = reason
	Telemetry.ServerEvent("RoundEnding", { round = self.RoundId, reason = reason })
end

function RoundContext.Elapsed(self: RoundContext): number
	if not self.Started then
		return 0
	end
	return os.clock() - self.StartTime
end

function RoundContext.Progress(self: RoundContext): number
	return math.clamp(self:Elapsed() / self.Definition.Duration, 0, 1)
end

-- Players --------------------------------------------------------------------------------------

function RoundContext.GetPlayers(self: RoundContext): { Player }
	local list = {}
	for player in self.Participants do
		if player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

function RoundContext.GetAlivePlayers(self: RoundContext): { Player }
	local list = {}
	for player, state in self.Participants do
		if state.Alive and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

function RoundContext.AliveCount(self: RoundContext): number
	return #self:GetAlivePlayers()
end

function RoundContext.IsAlive(self: RoundContext, player: Player): boolean
	local state = self.Participants[player]
	return state ~= nil and state.Alive
end

function RoundContext.State(self: RoundContext, player: Player): Participant?
	return self.Participants[player]
end

-- Returns the character, humanoid and root part if the player has a living character.
function RoundContext.GetCharacter(self: RoundContext, player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character or not character.Parent then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil, nil, nil
	end
	return character, humanoid, root
end

-- Finds the participant that owns a touched part, if they are alive in this round.
function RoundContext.PlayerFromPart(self: RoundContext, part: BasePart): Player?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local player = Players:GetPlayerFromCharacter(model)
		if player then
			if self:IsAlive(player) then
				return player
			end
			return nil
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function waitForCharacter(player: Player, timeout: number): Model?
	local deadline = os.clock() + timeout
	while player.Parent and os.clock() < deadline do
		local character = player.Character
		if character and character.Parent then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") then
				return character
			end
		end
		task.wait(0.1)
	end
	return nil
end

-- Teleports a participant into the arena. Retries once (with a fresh character) before giving up.
function RoundContext.SpawnPlayer(self: RoundContext, player: Player, cframe: CFrame, frozen: boolean?): boolean
	for attempt = 1, 2 do
		local character = waitForCharacter(player, 3)
		if character then
			character:PivotTo(cframe + Vector3.new(0, 3, 0))
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.AssemblyLinearVelocity = Vector3.zero
			end
			if frozen then
				self:Freeze(player, true)
			end
			if self.Hooks.CharacterReady then
				self.Hooks.CharacterReady(player, character)
			end
			return true
		end
		if attempt == 1 and player.Parent then
			pcall(player.LoadCharacterAsync, player)
		end
	end
	Telemetry.Error("SpawnFailed", `{player.Name} in round {self.RoundId}`)
	self.Participants[player] = nil
	if player.Parent then
		player:SetAttribute("PP_InRound", false)
		player:SetAttribute("PP_Alive", false)
		Notifier.Send(player, "We couldn't place you in this round. You'll be in the next one!", "warning")
	end
	return false
end

-- Spawns every participant at the given points (cycled if there are more players than points).
function RoundContext.SpawnAll(self: RoundContext, points: { CFrame }, frozen: boolean?)
	local threads = {}
	for index, player in self:GetPlayers() do
		local point = points[((index - 1) % #points) + 1]
		local done = false
		table.insert(threads, function()
			return done
		end)
		task.spawn(function()
			self:SpawnPlayer(player, point, frozen)
			done = true
		end)
	end
	local deadline = os.clock() + 8
	while os.clock() < deadline do
		local allDone = true
		for _, isDone in threads do
			if not isDone() then
				allDone = false
				break
			end
		end
		if allDone then
			break
		end
		task.wait(0.1)
	end
end

function RoundContext.Freeze(self: RoundContext, player: Player, frozen: boolean)
	local _, humanoid = self:GetCharacter(player)
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = if frozen then 0 else self.WalkSpeed
	humanoid.JumpHeight = if frozen then 0 else StarterPlayer.CharacterJumpHeight
	humanoid.JumpPower = if frozen then 0 else StarterPlayer.CharacterJumpPower
end

function RoundContext.UnfreezeAll(self: RoundContext)
	for _, player in self:GetAlivePlayers() do
		self:Freeze(player, false)
	end
end

function RoundContext.SetWalkSpeed(self: RoundContext, player: Player, speed: number)
	local _, humanoid = self:GetCharacter(player)
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

function RoundContext.Respawn(self: RoundContext, player: Player)
	local hook = self.Hooks.Respawn
	local cframe = hook and hook(player)
	local character, _, root = self:GetCharacter(player)
	if cframe and character and root then
		character:PivotTo(cframe + Vector3.new(0, 3, 0))
		root.AssemblyLinearVelocity = Vector3.zero
	else
		task.spawn(pcall, player.LoadCharacterAsync, player)
	end
end

function RoundContext.Eliminate(self: RoundContext, player: Player, reason: string)
	local state = self.Participants[player]
	if not state or not state.Alive or not self:IsRunning() then
		return
	end
	state.Alive = false
	state.EliminatedAt = self:Elapsed()
	player:SetAttribute("PP_Alive", false)

	local _, _, root = self:GetCharacter(player)
	if root then
		CosmeticService.PlayElimination(player, root.Position)
	end
	Notifier.Sound({ player }, "Eliminated")
	Notifier.Send(player, "You're out! Spectate from the HUD or explore the lobby - next vote soon.", "warning", 4)
	Telemetry.ServerEvent("Eliminated", { round = self.RoundId, player = player.UserId, reason = reason })

	if self.Hooks.Eliminated then
		self.Hooks.Eliminated(player, reason)
	end

	-- Send them back to the lobby (a dead character respawns there on its own).
	task.delay(1.2, function()
		if not player.Parent or state.Alive then
			return
		end
		local _, humanoid, currentRoot = self:GetCharacter(player)
		if humanoid and currentRoot and currentRoot.Position.Magnitude > LOBBY_RADIUS then
			pcall(player.LoadCharacterAsync, player)
		end
	end)

	self:_checkAutoEnd()
end

-- Scoring --------------------------------------------------------------------------------------

function RoundContext.AddScore(self: RoundContext, player: Player, amount: number)
	local state = self.Participants[player]
	if not state or not self:IsRunning() then
		return
	end
	state.Score += amount
	player:SetAttribute("PP_Score", state.Score)
end

function RoundContext.SetScoreText(self: RoundContext, player: Player, text: string)
	local state = self.Participants[player]
	if state then
		state.ScoreText = text
		player:SetAttribute("PP_ScoreText", text)
	end
end

function RoundContext.SetTeam(self: RoundContext, player: Player, team: string)
	local state = self.Participants[player]
	if state then
		state.Team = team
		player:SetAttribute("PP_Team", team)
	end
	self.TeamScores = self.TeamScores or {}
	local scores = self.TeamScores :: { [string]: number }
	if scores[team] == nil then
		scores[team] = 0
		GameState.SetJSON("TeamScores", scores)
	end
end

function RoundContext.AddTeamScore(self: RoundContext, team: string, amount: number)
	if not self:IsRunning() then
		return
	end
	self.TeamScores = self.TeamScores or {}
	local scores = self.TeamScores :: { [string]: number }
	scores[team] = (scores[team] or 0) + amount
	GameState.SetJSON("TeamScores", scores)
end

function RoundContext.SetStatus(self: RoundContext, text: string)
	GameState.Set("Status", text)
end

function RoundContext.Announce(self: RoundContext, text: string, kind: string?, duration: number?)
	Notifier.All(text, kind, duration)
end

function RoundContext.Sound(self: RoundContext, soundName: string)
	Notifier.Sound(nil, soundName)
end

-- Mini-game controls and state for the client half of a mode --------------------------------------

-- Server time shared with every client (workspace:GetServerTimeNow()), for synced schedules.
function RoundContext.Now(_self: RoundContext): number
	return workspace:GetServerTimeNow()
end

-- Handles a MiniGameAction the client sends while the round runs (a pump, a push, a shot...).
-- Each player is limited to one call per `Interval` seconds; eliminated players are ignored unless
-- `AliveOnly` is false. Arguments come from the client: validate them in the handler.
function RoundContext.OnAction(
	self: RoundContext,
	name: string,
	handler: (player: Player, ...any) -> (),
	options: { Interval: number?, AliveOnly: boolean? }?
)
	local opts = options or {}
	self._actions[name] = {
		Handler = handler,
		Interval = opts.Interval or 0.05,
		AliveOnly = opts.AliveOnly ~= false,
		Last = {},
	}
end

-- Round-wide state for clients: GameState attribute "MG_<key>" (cleared when the round ends).
function RoundContext.SetShared(self: RoundContext, key: string, value: any)
	self._sharedKeys[key] = true
	GameState.Set("MG_" .. key, value)
end

function RoundContext.SetSharedJSON(self: RoundContext, key: string, value: any)
	self._sharedKeys[key] = true
	GameState.SetJSON("MG_" .. key, value)
end

-- Per-player state for clients: player attribute "MG_<key>" (cleared when the round ends).
function RoundContext.SetPlayerShared(self: RoundContext, player: Player, key: string, value: any)
	self._playerKeys[key] = true
	player:SetAttribute("MG_" .. key, value)
end

-- Sends a MiniGameEvent to one player, a list of players, or everyone (nil).
function RoundContext.Fire(self: RoundContext, target: any, name: string, ...: any)
	if target == nil then
		eventRemote:FireAllClients(name, ...)
	elseif type(target) == "table" then
		for _, player in target do
			if player.Parent then
				eventRemote:FireClient(player, name, ...)
			end
		end
	elseif target.Parent then
		eventRemote:FireClient(target, name, ...)
	end
end

-- Hands physics of a part to a player's client (smooth control of their own vehicle or ball).
function RoundContext.GiveOwnership(_self: RoundContext, part: BasePart, player: Player)
	if typeof(player) == "Instance" then
		pcall(part.SetNetworkOwner, part, player)
	end
end

-- Briefly stops a player from moving or jumping.
function RoundContext.Stun(self: RoundContext, player: Player, seconds: number)
	local untilTime = math.max(self._stunnedUntil[player] or 0, os.clock() + seconds)
	self._stunnedUntil[player] = untilTime
	self:Freeze(player, true)
	self:SetPlayerShared(player, "Stunned", true)
	task.delay(seconds, function()
		if (self._stunnedUntil[player] or 0) > os.clock() + 0.01 or not self.Active then
			return
		end
		self._stunnedUntil[player] = nil
		self:SetPlayerShared(player, "Stunned", false)
		if self:IsAlive(player) then
			self:Freeze(player, false)
		end
	end)
end

function RoundContext.IsStunned(self: RoundContext, player: Player): boolean
	return (self._stunnedUntil[player] or 0) > os.clock()
end

-- Splits the participants into teams with these names (shuffled; sizes differ by at most one).
function RoundContext.AssignTeams(self: RoundContext, names: { string }): { [string]: { Player } }
	local players = self:GetPlayers()
	for index = #players, 2, -1 do
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local teams = {}
	for _, name in names do
		teams[name] = {}
	end
	for index, player in players do
		local name = names[((index - 1) % #names) + 1]
		self:SetTeam(player, name)
		table.insert(teams[name], player)
	end
	return teams
end

function RoundContext._onAction(self: RoundContext, player: Player, name: any, ...: any)
	if type(name) ~= "string" or not self:IsRunning() then
		return
	end
	local action = self._actions[name]
	local state = self.Participants[player]
	if not action or not state or (action.AliveOnly and not state.Alive) then
		return
	end
	local now = os.clock()
	if now - (action.Last[player] or 0) < action.Interval then
		return
	end
	action.Last[player] = now
	local ok, err = pcall(action.Handler, player, ...)
	if not ok then
		Telemetry.Error("RoundAction", `{self.Definition.Id}.{name}: {err}`)
	end
end

-- Scheduling (everything here dies with the round) ----------------------------------------------

function RoundContext.Track<T>(self: RoundContext, item: T): T
	return self.Janitor:Add(item)
end

function RoundContext.Delay(self: RoundContext, seconds: number, callback: () -> ())
	self.Janitor:Add(task.delay(seconds, function()
		if self.Active and self.EndReason == nil then
			local ok, err = pcall(callback)
			if not ok then
				Telemetry.Error("RoundCallback", `{self.Definition.Id}: {err}`)
			end
		end
	end))
end

-- Repeats `step` while the round runs. `step` returns the seconds to wait, or nil to stop.
function RoundContext.Loop(self: RoundContext, step: () -> number?)
	self.Janitor:Add(task.spawn(function()
		while self.Active and self.EndReason == nil do
			local ok, waitTime = pcall(step)
			if not ok then
				Telemetry.Error("RoundLoop", `{self.Definition.Id}: {waitTime}`)
				return
			end
			if waitTime == nil then
				return
			end
			task.wait(waitTime)
		end
	end))
end

function RoundContext.Heartbeat(self: RoundContext, callback: (dt: number) -> ())
	local failed = false
	self.Janitor:Add(RunService.Heartbeat:Connect(function(dt)
		if failed or not self:IsRunning() then
			return
		end
		local ok, err = pcall(callback, dt)
		if not ok then
			failed = true
			Telemetry.Error("RoundHeartbeat", `{self.Definition.Id}: {err}`)
		end
	end))
end

-- Results helpers --------------------------------------------------------------------------------

-- Survivors share first place; everyone else ranks by how long they lasted.
function RoundContext.SurvivalResults(self: RoundContext): Results
	local entries = {}
	local elapsed = self:Elapsed()
	for player, state in self.Participants do
		if not player.Parent then
			continue
		end
		local survived = if state.Alive then elapsed else (state.EliminatedAt or 0)
		table.insert(entries, {
			Player = player,
			Rank = (if state.Alive then 1e6 else 0) + math.floor(survived * 10) / 10,
			ScoreText = if state.Alive then "Survived!" else string.format("Lasted %ds", math.floor(survived)),
			BestScore = math.floor(survived),
			Survived = survived,
		})
	end
	return { Entries = entries }
end

-- Highest score wins.
function RoundContext.ScoreResults(self: RoundContext, unit: string?): Results
	local entries = {}
	for player, state in self.Participants do
		if not player.Parent then
			continue
		end
		table.insert(entries, {
			Player = player,
			Rank = state.Score,
			ScoreText = if state.ScoreText ~= "" then state.ScoreText else `{state.Score} {unit or "pts"}`,
			BestScore = state.Score,
		})
	end
	return { Entries = entries }
end

-- Every member of the best team shares first place; a draw makes everyone a winner.
function RoundContext.TeamResults(self: RoundContext): Results
	local scores = self.TeamScores or {}
	local bestTeam, bestScore, tie = nil, -math.huge, false
	for team, score in scores do
		if score > bestScore then
			bestTeam, bestScore, tie = team, score, false
		elseif score == bestScore then
			tie = true
		end
	end
	local entries = {}
	for player, state in self.Participants do
		if not player.Parent or not state.Team then
			continue
		end
		local teamScore = scores[state.Team] or 0
		table.insert(entries, {
			Player = player,
			Rank = teamScore,
			ScoreText = `{state.Team} {teamScore} • you {state.Score}`,
			BestScore = state.Score,
			Team = state.Team,
		})
	end
	return { Entries = entries, WinningTeam = if tie then nil else bestTeam }
end

-- Internals ------------------------------------------------------------------------------------

function RoundContext._checkAutoEnd(self: RoundContext)
	if not self:IsRunning() then
		return
	end
	if #self:GetPlayers() == 0 then
		self:End("NoPlayers")
		return
	end
	if self.EndWhenOneLeft then
		local alive = self:AliveCount()
		if alive == 0 then
			self:End("AllEliminated")
		elseif alive == 1 and self.StartCount >= 2 then
			self:End("LastSurvivor")
		end
	end
end

function RoundContext._watchCharacter(self: RoundContext, player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid or not self.Active then
		return
	end
	self.Janitor:Add(humanoid.Died:Connect(function()
		local state = self.Participants[player]
		if not state or not state.Alive or not self:IsRunning() then
			return
		end
		if self.RespawnMode == "Eliminate" then
			self:Eliminate(player, "died")
		end
	end))
end

function RoundContext._watchPlayer(self: RoundContext, player: Player)
	if player.Character then
		task.spawn(self._watchCharacter, self, player, player.Character)
	end
	self.Janitor:Add(player.CharacterAdded:Connect(function(character)
		task.spawn(self._watchCharacter, self, player, character)
		local state = self.Participants[player]
		if not state or not state.Alive or not self.Active or self.RespawnMode ~= "Respawn" then
			return
		end
		-- Respawn-mode games put a fresh character straight back into the arena.
		task.defer(function()
			local hook = self.Hooks.Respawn
			local cframe = hook and hook(player)
			local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
			if cframe and root and character.Parent and self.Active then
				character:PivotTo(cframe + Vector3.new(0, 3, 0))
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.WalkSpeed = if self.Started then self.WalkSpeed else 0
				end
				if self.Hooks.CharacterReady then
					self.Hooks.CharacterReady(player, character)
				end
			end
		end)
	end))
end

function RoundContext._onLeave(self: RoundContext, player: Player)
	if not self.Participants[player] then
		return
	end
	self.Participants[player] = nil
	if self.Hooks.PlayerLeft then
		local ok, err = pcall(self.Hooks.PlayerLeft, player)
		if not ok then
			Telemetry.Error("PlayerLeftHook", tostring(err))
		end
	end
	self:_checkAutoEnd()
end

-- Idempotent: stops everything, removes the arena and returns participants to the lobby.
function RoundContext.Destroy(self: RoundContext)
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self.Active = false
	self.Janitor:Cleanup()

	for player in self.Participants do
		if not player.Parent then
			continue
		end
		player:SetAttribute("PP_InRound", false)
		player:SetAttribute("PP_Alive", false)
		player:SetAttribute("PP_Score", 0)
		player:SetAttribute("PP_ScoreText", "")
		player:SetAttribute("PP_Team", "")
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or root.Position.Magnitude > LOBBY_RADIUS then
			-- A fresh character restores speed, jump, tools and anything a mode changed.
			task.spawn(function()
				pcall(player.LoadCharacterAsync, player)
			end)
		end
	end

	self.Arena:Destroy()
	GameState.Set("Status", "")
	GameState.Set("TeamScores", "")
	for key in self._sharedKeys do
		GameState.Set("MG_" .. key, nil)
	end
	for player in self.Participants do
		if player.Parent then
			for key in self._playerKeys do
				player:SetAttribute("MG_" .. key, nil)
			end
		end
	end
end

return RoundContext

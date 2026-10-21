-- Per-round helper handed to every mini-game. It owns the participants, the arena instance,
-- scoring, eliminations, respawns, timers and cleanup, so each mini-game only describes its rules.
--
-- Safety rules from the design doc that live here:
--   * a leaving player is removed from scoring and never blocks round completion (§4)
--   * failed spawns retry once, then the player safely stays in the lobby (§4)
--   * delayed callbacks are bound to this round and die with it (§4 "round ID")
--   * cleanup is idempotent and restores characters (§7, §14)
--
-- Things that happen at the same moment (a bug pass; owner: "it just has to work"):
--   * Players put out in the same server step go out together: they share the moment they went out,
--     so they tie, and the checks that end the round run once, after all of them. The first of the
--     last two to fall in one check (Hex Meltdown) or to be hit by one rope pass used to end the
--     round, and the other was turned away because it had just stopped, so they won with
--     "Survived!", picked by table order.
--   * A death before GO (a reset during the rules card) doesn't count: a fresh character goes
--     straight back to its spot, in every mode, instead of waiting in the lobby to be counted out
--     ("fell") the moment the round started.
--   * Bots never play on their own (Logic/Roster): WaitForStart tells the round manager when every
--     person in a round left or couldn't be placed before GO, so it calls the round off.
--   * At the buzzer, something already on its way to be judged (a rope pass, a landed arrow, a hit
--     pressed just before) gets a moment (HoldEnd, half a second at most) instead of being dropped
--     because the round had just ended.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local Janitor = require(Shared.Janitor)
local Remotes = require(Shared.Remotes)

local BotRegistry = require(script.Parent.BotRegistry)
local CosmeticService = require(script.Parent.CosmeticService)
local Notifier = require(script.Parent.Notifier)
local Telemetry = require(script.Parent.Telemetry)

local LOBBY_RADIUS = 600
local PEOPLE_OUT_DELAY = 2 -- once every person is out, the round wraps up after this long
local MAX_HOLD = 0.5 -- the longest a round's end waits at time-up for something in flight (HoldEnd)

local actionRemote = Remotes.Get("MiniGameAction")
local eventRemote = Remotes.Get("MiniGameEvent")
local knockbackRemote = Remotes.Get("Knockback")
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
	LobbyCharacter: Model?, -- the character they got back in the lobby after going out
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
	self.HoldUntil = 0 -- server time: at time-up the end waits until then (HoldEnd)
	self.TimeUpAt = nil :: number? -- server time the round's time ran out, while its end is held (TimeRanOut)
	self.PeopleOutPending = false
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
	self._outBatch = nil :: { At: number, CheckEnd: boolean }? -- this server step's eliminations (_outMoment)
	self._spots = {} :: { [Player]: { CFrame: CFrame, Frozen: boolean } } -- where SpawnPlayer put each one
	self._placing = {} :: { [Player]: Model } -- a new character on its way back to its spot (_backToSpot)
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
	self.Janitor:Add(BotRegistry.Removed:Connect(function(bot)
		self:_onLeave(bot)
	end))
	self.Janitor:Add(actionRemote.OnServerEvent:Connect(function(player, name, ...)
		self:_onAction(player, name, ...)
	end))

	-- Fall / out-of-bounds check (server side so clients can't skip it). Everyone below KillY in one
	-- check goes out together (see Eliminate); a new character still on its way back to its spot is
	-- left alone (it starts in the lobby, far below).
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
			if not state.Alive or self._placing[player] then
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

-- Waits for GO (`deadline`, os.clock() time) while the rules card shows. Returns false straight away
-- once no person is left in the round (they all left, or none of them could be placed): bots never
-- play on their own (Logic/Roster), so the round manager calls the round off instead of starting it.
function RoundContext.WaitForStart(self: RoundContext, deadline: number): boolean
	while os.clock() < deadline do
		if not self:HasPeople() then
			return false
		end
		task.wait(0.1)
	end
	return self:HasPeople()
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

-- Asks for a moment before the round ends at time-up, for something already on its way to be judged:
-- an arrow that has just landed, a rope pass whose last positions are still coming in, a hit pressed
-- just before the buzzer. If time runs out within the next `seconds`, the round goes on until then,
-- but never more than MAX_HOLD past the buzzer; meanwhile nothing new should start (TimeIsUp), and an
-- action should count only if it was made before TimeUpAt.
function RoundContext.HoldEnd(self: RoundContext, seconds: number)
	self.HoldUntil = math.max(self.HoldUntil, self:Now() + math.max(0, seconds))
end

-- Whether the round's time has run out (its end may be held a moment: HoldEnd).
function RoundContext.TimeIsUp(self: RoundContext): boolean
	return self.TimeUpAt ~= nil or self.EndReason ~= nil
end

-- The round manager calls this, again and again, once the round's time has run out: it ends the round
-- straight away, or as soon as what HoldEnd asked for is over (MAX_HOLD at most).
function RoundContext.TimeRanOut(self: RoundContext, reason: string)
	local now = self:Now()
	self.TimeUpAt = self.TimeUpAt or now
	if now >= self.HoldUntil or now >= (self.TimeUpAt :: number) + MAX_HOLD then
		self:End(reason)
	end
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

-- Whether any person (not a bot) is in the round, out or not.
function RoundContext.HasPeople(self: RoundContext): boolean
	for _, player in self:GetPlayers() do
		if not BotRegistry.IsBot(player) then
			return true
		end
	end
	return false
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
		local player = Players:GetPlayerFromCharacter(model) or BotRegistry.FromCharacter(model)
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
			self._spots[player] = { CFrame = cframe, Frozen = frozen == true } -- for a new character before GO
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
	if player.Parent then
		player:SetAttribute("PP_InRound", false)
		player:SetAttribute("PP_Alive", false)
		Notifier.Send(player, "We couldn't place you in this round. You'll be in the next one!", "warning")
	end
	-- Out of the round as if they'd left (a spawn can fail after GO: the mode forgets them, a team
	-- stops counting on them, and the round can end without them).
	self:_onLeave(player)
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

-- Puts a participant out. Everyone put out in the same server step goes out together: they share
-- the moment they went out (so they tie in the results) and the checks that end the round run once,
-- after all of them (_outMoment). A mode can simply eliminate everyone a hazard caught in one loop.
--
-- `showAfter` (seconds) is for a mode with its own show of someone going out (Honey Trap's bees):
-- they're out at once for the rules (results, turns, a time-up or a leave all count it), while the
-- "You're out!", the poof, the trip back to the lobby and the end-of-round checks wait for the show.
function RoundContext.Eliminate(self: RoundContext, player: Player, reason: string, showAfter: number?)
	local state = self.Participants[player]
	if not state or not state.Alive or not self:IsRunning() then
		return
	end
	state.Alive = false
	state.EliminatedAt = self:_outMoment(showAfter == nil)
	if showAfter == nil then
		self:_showOut(player, state)
	end
	Telemetry.ServerEvent("Eliminated", { round = self.RoundId, player = player.UserId, reason = reason })

	if self.Hooks.Eliminated then
		self.Hooks.Eliminated(player, reason)
	end
	if showAfter then
		self:Delay(showAfter, function()
			if self.Participants[player] == state then
				self:_showOut(player, state)
			end
			self:_checkAutoEnd()
		end)
	end
end

-- What everyone sees of someone going out: the effect where they stand, the "You're out!", and
-- their trip back to the lobby a moment later.
function RoundContext._showOut(self: RoundContext, player: Player, state: Participant)
	player:SetAttribute("PP_Alive", false)
	local _, _, root = self:GetCharacter(player)
	if root then
		CosmeticService.PlayElimination(player, root.Position)
	end
	Notifier.Sound({ player }, "Eliminated")
	Notifier.Send(player, "You're out! Spectate from the HUD or explore the lobby - next vote soon.", "warning", 4)

	-- Send them back to the lobby (a dead character respawns there on its own).
	task.delay(1.2, function()
		if not player.Parent or state.Alive then
			return
		end
		local _, humanoid, currentRoot = self:GetCharacter(player)
		if humanoid and currentRoot and not self:_inLobby(player, currentRoot) then
			pcall(player.LoadCharacterAsync, player)
		end
	end)
end

-- The moment (seconds into the round) an elimination happening now counts as: the same for every
-- elimination in this server step, so they tie. With `checkEnd`, the checks that end the round run
-- once at the end of the step, after all of them (task.defer: once this step's other handlers, the
-- fall check and the modes' own, have run), so none of them is turned away because the first one
-- just ended the round.
function RoundContext._outMoment(self: RoundContext, checkEnd: boolean): number
	local batch = self._outBatch
	if not batch then
		local fresh = { At = self:Elapsed(), CheckEnd = false }
		batch = fresh
		self._outBatch = fresh
		task.defer(function()
			if self._outBatch == fresh then
				self._outBatch = nil
			end
			if fresh.CheckEnd then
				self:_checkAutoEnd()
			end
		end)
	end
	if checkEnd then
		batch.CheckEnd = true
	end
	return batch.At
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

-- Sends a MiniGameEvent to one player, a list of players, or everyone (nil). Bots are skipped:
-- they have no client (their brain reads the round's state directly).
function RoundContext.Fire(self: RoundContext, target: any, name: string, ...: any)
	if target == nil then
		eventRemote:FireAllClients(name, ...)
	elseif BotRegistry.IsBot(target) then
		return
	elseif type(target) == "table" then
		for _, player in target do
			if typeof(player) == "Instance" and player.Parent then
				eventRemote:FireClient(player, name, ...)
			end
		end
	elseif target.Parent then
		eventRemote:FireClient(target, name, ...)
	end
end

-- Throws a participant: `velocity` in studs/s, ragdolled for `stun` seconds (0 = just a shove).
-- Players are moved by their own device (smooth); bots by the server.
function RoundContext.Knockback(self: RoundContext, player: any, velocity: Vector3, stun: number)
	if typeof(player) == "Instance" then
		knockbackRemote:FireClient(player, velocity, stun)
		return
	end
	local _, humanoid, root = self:GetCharacter(player)
	if not humanoid or not root then
		return
	end
	if stun <= 0 then
		root.AssemblyLinearVelocity += velocity
		return
	end
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = velocity
	task.delay(math.clamp(stun, 0.1, 2), function()
		if humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

-- Bots ---------------------------------------------------------------------------------------------

-- Runs a mode's bot brain (MiniGames/Bots/<Id>.luau) for every bot in the round, about 7 times a
-- second: brain.Step(bot, ctx, mode, dt), and brain.Start(ctx, mode) once if it has one.
function RoundContext.RunBots(self: RoundContext, brain: any, mode: any)
	if not brain then
		return
	end
	for player in self.Participants do
		if BotRegistry.IsBot(player) then
			player.Memory = {}
		end
	end
	if brain.Start then
		local ok, err = pcall(brain.Start, self, mode)
		if not ok then
			Telemetry.Error("BotBrain", `{self.Definition.Id}.Start: {err}`)
		end
	end
	local last = os.clock()
	local failures = 0
	self:Loop(function(): number?
		local now = os.clock()
		local dt = now - last
		last = now
		for player, state in self.Participants do
			if state.Alive and BotRegistry.IsBot(player) and player.Parent then
				local ok, err = pcall(brain.Step, player, self, mode, dt)
				if not ok then
					failures += 1
					if failures <= 3 then
						Telemetry.Error("BotBrain", `{self.Definition.Id}: {err}`)
					end
				end
			end
		end
		return 0.15
	end)
end

-- A bot pressing a control: goes through the same checks as a player's MiniGameAction.
function RoundContext.BotAction(self: RoundContext, bot: any, name: string, ...: any)
	if BotRegistry.IsBot(bot) then
		self:_onAction(bot, name, ...)
	end
end

-- Hands physics of a part to a player's client (smooth control of their own vehicle or ball).
function RoundContext.GiveOwnership(_self: RoundContext, part: BasePart, player: Player)
	if typeof(player) == "Instance" then
		pcall(part.SetNetworkOwner, part, player)
	end
end

-- Shares a model the client half copies (fruit, arrows, balloons...): it waits in
-- ReplicatedStorage.MiniGameAssets, where nothing renders, until the round ends.
function RoundContext.ShareTemplate(self: RoundContext, name: string, model: Instance)
	local folder = ReplicatedStorage:FindFirstChild("MiniGameAssets")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MiniGameAssets"
		folder.Parent = ReplicatedStorage
	end
	model.Name = name
	model.Parent = folder
	self.Janitor:Add(model)
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

-- Whether any person (not a bot) is still in the round and not out.
function RoundContext._anyPersonAlive(self: RoundContext): boolean
	for _, player in self:GetAlivePlayers() do
		if not BotRegistry.IsBot(player) then
			return true
		end
	end
	return false
end

function RoundContext._checkAutoEnd(self: RoundContext)
	if not self:IsRunning() then
		return
	end
	if #self:GetPlayers() == 0 then
		self:End("NoPlayers")
		return
	end
	-- Rounds are for people: once every person in it is out (or has left), wrap up after a moment
	-- instead of leaving them watching bots play on (owner: "The round should end if all human
	-- players are eliminated"). Modes where people respawn never get here while anyone is playing.
	if not self:_anyPersonAlive() then
		if not self.PeopleOutPending then
			self.PeopleOutPending = true
			self:Delay(PEOPLE_OUT_DELAY, function()
				self.PeopleOutPending = false
				if not self:_anyPersonAlive() then
					self:End("PeopleOut")
				end
			end)
		end
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
		if not state or not state.Alive or not self.Active then
			return
		end
		if not self.Started then
			-- Before GO a death doesn't count (a reset during the rules card): a fresh character right
			-- away, which goes back on their spot (_watchPlayer). Not yet placed: SpawnPlayer retries.
			if self._spots[player] and player.Character == character then
				task.spawn(pcall, player.LoadCharacterAsync, player)
			end
			return
		end
		if self:IsRunning() and self.RespawnMode == "Eliminate" then
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
		if state and not state.Alive then
			state.LobbyCharacter = character -- new characters start in the lobby, and nothing moves theirs
		end
		if not state or not state.Alive or not self.Active then
			return
		end
		-- Before GO, in any mode, a new character goes back on its spot. So does one arriving after GO
		-- in a mode where nobody respawns: the old one can only have died before GO.
		if not self.Started or (self.RespawnMode ~= "Respawn" and self.EndReason == nil) then
			self:_backToSpot(player, character)
			return
		end
		if self.RespawnMode ~= "Respawn" then
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

-- Puts a participant's new character on the spot SpawnPlayer gave them: frozen until GO (if they
-- were spawned frozen), free to play after it. The fall check leaves them alone until it's there.
function RoundContext._backToSpot(self: RoundContext, player: Player, character: Model)
	local spot = self._spots[player]
	if not spot then
		return -- not placed yet: SpawnPlayer does it
	end
	self._placing[player] = character
	task.defer(function()
		local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		if root and character.Parent and player.Character == character and self.Active and self:IsAlive(player) then
			character:PivotTo(spot.CFrame + Vector3.new(0, 3, 0))
			root.AssemblyLinearVelocity = Vector3.zero
			if not self.Started then
				self:Freeze(player, spot.Frozen)
			else
				self:Freeze(player, false)
			end
			if self.Hooks.CharacterReady then
				self.Hooks.CharacterReady(player, character)
			end
		end
		if self._placing[player] == character then
			self._placing[player] = nil
		end
	end)
end

-- Whether a participant is already back in the lobby: their character is the one they got there
-- after going out. Distance alone can't tell: the Bobsled Run's finish hangs over the lobby's own
-- field, so riders who weren't sent home dropped into it when the track went away.
function RoundContext._inLobby(self: RoundContext, player: Player, root: BasePart): boolean
	local state = self.Participants[player]
	return state ~= nil
		and state.LobbyCharacter ~= nil
		and player.Character == state.LobbyCharacter
		and root.Position.Magnitude <= LOBBY_RADIUS
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
		if not root or not self:_inLobby(player, root) then
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

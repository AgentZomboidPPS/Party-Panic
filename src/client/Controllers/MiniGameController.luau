-- Runs the client half of the current mini-game, if it has one (src/client/MiniGames/<Id>.luau):
-- smooth visuals driven by the server's shared state, extra controls (action buttons, tilt) and
-- mode-specific HUD bits. It starts when a round enters Preparing and is torn down at Cleanup, so
-- a mode's client code can never leak into the lobby or the next round.
--
-- That includes a start-up still waiting when the round is torn down (say for shared state a
-- failed Prepare never set): its thread is cancelled with the round, so it can't wake up in a later
-- round of the same mode with a dead API.
--
-- The camera goes back to the player too (owner, after a Sky Stack round on version 61: "This
-- happened again after the new mini game", with a screenshot of the lobby far off from the sky over
-- the arena, where the round's camera had been left). A mode's cleanup gives its camera back itself;
-- settleCamera is the backstop for one that doesn't, or that hands back a scripted camera it found
-- when it started: when a mode stops, when a new character arrives between rounds, and every second
-- in the lobby, the camera follows the player's own character at the normal field of view. Skee-Ball
-- films the lobby with its own camera (State.CameraHeld), so it's left alone then.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState = require(ReplicatedStorage.Shared.GameState)

local State = require(script.Parent.Parent.State)
local Api = require(script.Parent.Parent.MiniGames.Kit.Api)

local MiniGameController = {}

local modules = script.Parent.Parent.MiniGames
local ACTIVE_PHASES = { Preparing = true, InRound = true, Results = true }

local current: { id: string, api: any, roundId: number, thread: thread? }? = nil

local player = Players.LocalPlayer
local LOBBY_FOV = 70 -- Roblox's own field of view (the lobby never changes it)
local WATCH_EVERY = 1 -- seconds between the lobby's camera checks

-- The camera back on the player's own character (above). Returns whether anything was wrong.
local function settleCamera(): boolean
	local camera = workspace.CurrentCamera
	if State.CameraHeld or not camera then
		return false
	end
	local wrong = false
	if camera.CameraType ~= Enum.CameraType.Custom then
		camera.CameraType = Enum.CameraType.Custom
		wrong = true
	end
	if camera.FieldOfView ~= LOBBY_FOV then
		camera.FieldOfView = LOBBY_FOV
		wrong = true
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local subject = camera.CameraSubject
	if humanoid and subject ~= humanoid and (subject == nil or subject ~= humanoid.SeatPart) then
		camera.CameraSubject = humanoid
		wrong = true
	end
	return wrong
end

-- Between rounds: no mode running and the phase isn't a round's (a mode with no client code runs
-- none, and spectating its round moves the camera on purpose).
local function betweenRounds(): boolean
	return current == nil and not ACTIVE_PHASES[GameState.Get("Phase") or ""]
end

local function stop()
	local running = current
	current = nil
	if running then
		-- A start-up still waiting goes with the round (not when stop runs from inside it).
		if running.thread and coroutine.status(running.thread) == "suspended" then
			pcall(task.cancel, running.thread)
		end
		local ok, err = pcall(running.api.Destroy, running.api)
		if not ok then
			warn(`[MiniGame] {running.id} cleanup failed: {err}`)
		end
		if settleCamera() then
			warn(`[MiniGame] {running.id} left the camera off the player: put back`)
		end
	end
end

local function start(id: string, roundId: number)
	local moduleScript = modules:FindFirstChild(id)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return -- this mode needs no client code
	end
	local ok, module = pcall(require, moduleScript)
	if not ok or type(module) ~= "table" or type(module.Start) ~= "function" then
		warn(`[MiniGame] {id} client module failed to load: {module}`)
		return
	end
	local api = Api.new(id)
	local entry = { id = id, api = api, roundId = roundId, thread = nil :: thread? }
	current = entry
	entry.thread = task.spawn(function()
		local started, err = pcall(module.Start, api)
		if not started then
			warn(`[MiniGame] {id} client failed to start: {err}`)
		end
	end)
end

local function refresh()
	local phase = GameState.Get("Phase")
	local id = GameState.Get("GameId") or ""
	local roundId = GameState.Get("RoundId") or 0
	local wanted = ACTIVE_PHASES[phase] == true and id ~= ""
	if current and (not wanted or current.id ~= id or current.roundId ~= roundId) then
		stop()
	end
	if wanted and not current then
		start(id, roundId)
	end
end

function MiniGameController.Start(_context)
	GameState.Changed("Phase", refresh)
	GameState.Changed("GameId", refresh)
	GameState.Changed("RoundId", refresh)
	refresh()

	-- Between rounds (no mode running), a new character and the camera checks.
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid", 10)
		if betweenRounds() then
			settleCamera()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(WATCH_EVERY)
			if betweenRounds() and settleCamera() then
				warn("[MiniGame] the lobby camera was off the player: put back")
			end
		end
	end)
end

return MiniGameController

-- Runs the client half of the current mini-game, if it has one (src/client/MiniGames/<Id>.luau):
-- smooth visuals driven by the server's shared state, extra controls (action buttons, tilt) and
-- mode-specific HUD bits. It starts when a round enters Preparing and is torn down at Cleanup, so
-- a mode's client code can never leak into the lobby or the next round.
--
-- That includes a start-up still waiting when the round is torn down (say for shared state a
-- failed Prepare never set): its thread is cancelled with the round, so it can't wake up in a later
-- round of the same mode with a dead API.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState = require(ReplicatedStorage.Shared.GameState)

local Api = require(script.Parent.Parent.MiniGames.Kit.Api)

local MiniGameController = {}

local modules = script.Parent.Parent.MiniGames
local ACTIVE_PHASES = { Preparing = true, InRound = true, Results = true }

local current: { id: string, api: any, roundId: number, thread: thread? }? = nil

local function stop()
	local running = current
	current = nil
	if running then
		-- A start-up still waiting goes with the round (not when stop runs from inside it).
		if running.thread and coroutine.status(running.thread) == "suspended" then
			task.cancel(running.thread)
		end
		local ok, err = pcall(running.api.Destroy, running.api)
		if not ok then
			warn(`[MiniGame] {running.id} cleanup failed: {err}`)
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
end

return MiniGameController

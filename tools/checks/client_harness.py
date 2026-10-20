"""Builds a Luau script that runs the whole CLIENT on a real Roblox server (Open Cloud Luau
execution), so client code can be exercised without a player: every controller starts, then the
script opens each screen, plays through every game phase, and fires every server->client remote.
Errors and warnings from all of it come back in the result.

    python3 tools/checks/client_harness.py > client.luau
    python3 tools/preview/luau_task.py client.luau - client.json

Client-only APIs are replaced by small stand-ins: Players.LocalPlayer (a fake player with a
PlayerGui folder), RenderStepped (Heartbeat), StarterGui:SetCore, and the remotes (bindable
events the harness can fire). Shared modules are the place's real ones.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "src" / "client"
SHIMMED_SERVICES = ("Players", "RunService", "StarterGui")


def module_paths():
    paths = {}
    for path in sorted(CLIENT.rglob("*.luau")):
        if path.name == "init.client.luau":
            continue
        rel = path.relative_to(CLIENT).with_suffix("")
        paths["Client/" + "/".join(rel.parts)] = path
    return paths


def resolve(module: str, expr: str) -> str:
    parts = module.split("/")
    for token in expr.split(".")[1:]:
        if token == "Parent":
            parts = parts[:-1]
        else:
            parts = parts + [token]
    return "/".join(parts)


def rewrite(module: str, text: str) -> str:
    text = re.sub(r"require\((script(?:\.\w+)+)\)", lambda m: f'__require("{resolve(module, m.group(1))}")', text)
    text = re.sub(r"require\(([^()]*?(?:\([^()]*\))?[^()]*?)\.Remotes\)", "__RemotesShim", text)
    for service in SHIMMED_SERVICES:
        text = text.replace(f'game:GetService("{service}")', f'__service("{service}")')
    return re.sub(r"^export type", "type", text, flags=re.M)


PRELUDE = r'''
local __errors = {}
game:GetService("LogService").MessageOut:Connect(function(message, kind)
	if (kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning) and #__errors < 150 then
		table.insert(__errors, kind.Name .. ": " .. message)
	end
end)
local function __note(text)
	table.insert(__errors, "NOTE: " .. text)
end

local __realPlayers = game:GetService("Players")
local __realRun = game:GetService("RunService")
local __realStarterGui = game:GetService("StarterGui")
local function __event()
	return Instance.new("BindableEvent")
end
local __playerGui = Instance.new("Folder")
__playerGui.Name = "PlayerGui"
__playerGui.Parent = game:GetService("ServerStorage")
local __characterAdded = __event()
local __player
__player = setmetatable({
	Name = "HarnessPlayer",
	DisplayName = "Harness",
	UserId = 1,
	PlayerGui = __playerGui,
	CharacterAdded = __characterAdded.Event,
	CharacterRemoving = __event().Event,
	Changed = __event().Event,
}, {
	__index = function(_, key)
		if key == "Character" then
			return nil
		elseif key == "WaitForChild" or key == "FindFirstChild" then
			return function(self, name)
				return rawget(self, name)
			end
		elseif key == "GetAttribute" then
			return function()
				return nil
			end
		elseif key == "GetAttributeChangedSignal" or key == "GetPropertyChangedSignal" then
			return function()
				return __event().Event
			end
		elseif key == "IsA" then
			return function(_, className)
				return className == "Player" or className == "Instance"
			end
		end
		error("[harness] fake LocalPlayer has no member '" .. tostring(key) .. "'", 2)
	end,
})

local function __wrap(real, overrides)
	return setmetatable(overrides, {
		__index = function(_, key)
			local value = real[key]
			if type(value) == "function" then
				return function(_, ...)
					return value(real, ...)
				end
			end
			return value
		end,
	})
end
local __shims = {
	Players = __wrap(__realPlayers, { LocalPlayer = __player }),
	RunService = __wrap(__realRun, {
		RenderStepped = __realRun.Heartbeat,
		IsClient = function()
			return true
		end,
		IsServer = function()
			return false
		end,
		BindToRenderStep = function(_, _name, _priority, callback)
			__realRun.Heartbeat:Connect(callback)
		end,
		UnbindFromRenderStep = function() end,
	}),
	StarterGui = __wrap(__realStarterGui, {
		SetCore = function() end,
		SetCoreGuiEnabled = function() end,
		GetCore = function()
			return nil
		end,
	}),
}
local function __service(name)
	return __shims[name] or game:GetService(name)
end

local __remotes, __sent = {}, {}
local __RemotesShim = {
	Get = function(name)
		if not __remotes[name] then
			local bindable = __event()
			__remotes[name] = {
				Name = name,
				OnClientEvent = bindable.Event,
				FireServer = function(_, ...)
					table.insert(__sent, name)
				end,
				__bindable = bindable,
			}
		end
		return __remotes[name]
	end,
}
local function __fire(name, ...)
	__RemotesShim.Get(name).__bindable:Fire(...)
end

local __modules, __cache = {}, {}
local function __require(name)
	if __cache[name] == nil then
		local loader = __modules[name]
		if not loader then
			error("[harness] no module " .. name)
		end
		__cache[name] = loader()
	end
	return __cache[name]
end
'''

MAIN = r'''
task.spawn(function()
	error("harness self-test: errors are captured")
end)
-- Build the lobby like LobbyService does, so tagged screens, the podium and the token exist.
do
	local world = game:GetService("ServerScriptService").Server.World
	local okLobby, lobbyErr = pcall(function()
		require(world.LobbyBuilder).Build()
	end)
	if not okLobby then
		__note("LobbyBuilder.Build failed: " .. tostring(lobbyErr))
	end
	local token = Instance.new("Part")
	token.Name = "SecretToken"
	token.Anchored = true
	token.Parent = workspace:FindFirstChild("Lobby") or workspace
end

-- Server side state the client reads (real shared modules).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
GameState.Folder()
local GameDefinitions = require(Shared.GameDefinitions)
local Services = game:GetService("ServerScriptService").Server.Services
local DataService = require(Services.DataService)
local QuestDefinitions = require(Shared.QuestDefinitions)

local step = "start"
local function phase(name, seconds, extra)
	step = "phase " .. name
	if extra then
		extra()
	end
	GameState.Set("Phase", name)
	GameState.Set("PhaseEndsAt", workspace:GetServerTimeNow() + seconds)
	task.wait(1.2)
end

-- 1. Start every controller like init.client.luau does.
local State = __require("Client/State")
local okInit, initErr = pcall(State.Init)
if not okInit then
	__note("State.Init failed: " .. tostring(initErr))
end
local order = {
	"AudioController", "NotificationController", "EffectsController", "AmbienceController",
	"MovementController", "WorldScreensController", "HudController", "VoteController",
	"RoundController", "ResultsController", "ShopController", "QuestController",
	"EmoteController", "SpectateController", "OnboardingController",
}
local context = {}
for key, guiName in { Hud = "PartyPanicHUD", Overlay = "PartyPanicOverlay" } do
	local gui = Instance.new("ScreenGui")
	gui.Name = guiName
	gui.Parent = __playerGui
	context[key] = gui
end
local startTimes = {}
for _, name in order do
	local okLoad, controller = pcall(__require, "Client/Controllers/" .. name)
	if not okLoad then
		__note(name .. " failed to load: " .. tostring(controller))
		continue
	end
	local t = os.clock()
	local done = false
	task.spawn(function()
		local okStart, err = pcall(controller.Start, context)
		if not okStart then
			__note(name .. " failed to start: " .. tostring(err))
		end
		done = true
	end)
	local waited = 0
	while not done and waited < 5 do
		task.wait(0.1)
		waited += 0.1
	end
	if not done then
		__note(name .. ".Start is STILL RUNNING after 5s (blocks every controller after it)")
	end
	startTimes[name] = math.floor((os.clock() - t) * 1000)
end

-- 2. Profile snapshot, as DataService sends it.
local data = table.clone(DataService.Template)
local profile = { Data = data, IsVip = false, CanSave = true }
local okSnap, snapshot = pcall(DataService.BuildSnapshot, profile)
if okSnap then
	local quests = {}
	for id in QuestDefinitions.ById or {} do
		table.insert(quests, { Id = id, Progress = 1, Done = false })
		if #quests >= 3 then
			break
		end
	end
	snapshot.Quests.Daily = quests
	step = "ProfileData"
	__fire("ProfileData", snapshot)
	task.wait(1)
else
	__note("BuildSnapshot failed: " .. tostring(snapshot))
end

-- 3. Screens opened by the lobby prompts and the HUD.
for _, screen in { "Shop", "Quests", "Emotes", "Settings" } do
	step = "OpenScreen " .. screen
	State.OpenScreen:Fire(screen)
	task.wait(1)
	local Modal = __require("Client/UI/Modal")
	if Modal.CloseAll then
		pcall(Modal.CloseAll)
	end
	task.wait(0.3)
end

-- 4. A whole round, phase by phase.
local ids = {}
for _, def in GameDefinitions.List do
	table.insert(ids, def.Id)
end
phase("Intermission", 20)
phase("Voting", 12, function()
	GameState.SetJSON("VoteOptions", {
		{ Id = ids[1], Mystery = false },
		{ Id = ids[2], Mystery = false },
		{ Id = ids[3], Mystery = true },
	})
	GameState.SetJSON("VoteCounts", { 1, 0, 2 })
end)
phase("Preparing", 6, function()
	GameState.Set("GameId", ids[1])
	GameState.Set("RoundId", 1)
end)
phase("InRound", 60, function()
	GameState.Set("Status", "Survivors: 3")
end)
step = "remotes"
__fire("Notify", "Harness notification", "reward", 2)
__fire("PlayEffect", "Confetti", Vector3.new(0, 5, 0))
__fire("PlayEffect", "Fireworks", Vector3.new(0, 10, 0))
__fire("PlayEffect", "Sparkles", Vector3.new(0, 5, 0), { Color3.new(1, 0, 0) })
__fire("PlaySound", "Pickup")
__fire("Knockback", Vector3.new(10, 20, 0), 0.5)
task.wait(1)
phase("Results", 8, function()
	__fire("RoundResults", {
		GameId = ids[1],
		Place = 1,
		PlayerCount = 3,
		ScoreText = "Survived",
		Lines = { { Label = "Participation", Coins = 10 }, { Label = "1st place", Coins = 30 } },
		Coins = 40,
		XP = 50,
		PersonalBest = true,
		Standings = {
			{ Name = "Harness", Place = 1, ScoreText = "Survived", UserId = 1 },
			{ Name = "Bot", Place = 2, ScoreText = "Out", UserId = 2 },
		},
	})
	GameState.SetJSON("Champions", { { Name = "Harness", UserId = 1, Place = 1 } })
end)
phase("Cleanup", 3)
phase("Waiting", 0, function()
	GameState.Set("Message", "Waiting for 1 more player")
end)
task.wait(1)

local guiCount = #__playerGui:GetDescendants()
return game:GetService("HttpService"):JSONEncode({
	errors = __errors,
	startMs = startTimes,
	sentToServer = __sent,
	guiInstances = guiCount,
	lastStep = step,
})
'''


def main():
    out = [PRELUDE]
    for module, path in module_paths().items():
        out.append(f'__modules["{module}"] = function()')
        out.append(rewrite(module, path.read_text()))
        out.append("end")
    out.append(MAIN)
    sys.stdout.write("\n".join(out))


if __name__ == "__main__":
    main()

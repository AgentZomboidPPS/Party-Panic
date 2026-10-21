"""Builds a Luau script that runs the whole CLIENT on a real Roblox server (Open Cloud Luau
execution), so client code can be exercised without a player: every controller starts, then the
script opens each screen, plays through every game phase, and fires every server->client remote.
Errors and warnings from all of it come back in the result.

    python3 tools/checks/client_harness.py [--touch] [--rich] > client.luau
    python3 tools/preview/luau_task.py client.luau - client.json
    python3 tools/checks/ui_render.py client.json /tmp/screens    # draw every screen and phase

--touch makes the stand-in client a phone (touch, no keyboard), for the phone layouts.
--rich gives the player a well-used profile (every emote, lots of coins, a long name, a claimable
daily gift) to check the layouts at their fullest; the default is a brand-new player.

Client-only APIs are replaced by small stand-ins: Players.LocalPlayer (a fake player with a
PlayerGui folder and attributes) and 11 other fake players for the standings, RenderStepped
(Heartbeat), StarterGui:SetCore, and the remotes (bindable events the harness can fire). The two
ScreenGuis are made like init.client.luau makes them. Shared modules come from the working tree
(except Remotes).
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "src" / "client"
SHIMMED_SERVICES = ("Players", "RunService", "StarterGui", "UserInputService")


def module_paths():
    paths = {}
    # The working tree's shared modules, so client code runs against the code it ships with.
    for path in sorted((ROOT / "src" / "shared").rglob("*.luau")):
        rel = path.relative_to(ROOT / "src" / "shared").with_suffix("")
        if rel.parts != ("Remotes",):  # replaced by the harness's stand-in
            paths["Shared/" + "/".join(rel.parts)] = path
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


SHARED = r'(?:game:GetService\("ReplicatedStorage"\)\.Shared|ReplicatedStorage\.Shared|Shared)'


def shared_requires(text: str) -> str:
    return re.sub(r"require\(" + SHARED + r"((?:\.\w+)+)\)", lambda m: '__require("Shared' + m.group(1).replace(".", "/") + '")', text)


def rewrite(module: str, text: str) -> str:
    text = re.sub(r"require\(([^()]*?(?:\([^()]*\))?[^()]*?)\.Remotes\)", "__RemotesShim", text)
    text = re.sub(r"require\((script(?:\.\w+)+)\)", lambda m: f'__require("{resolve(module, m.group(1))}")', text)
    text = shared_requires(text)
    if module.startswith("Client/"):  # shared modules run as the server here (it owns GameState)
        for service in SHIMMED_SERVICES:
            text = text.replace(f'game:GetService("{service}")', f'__service("{service}")')
    return re.sub(r"^export type", "type", text, flags=re.M)


PRELUDE = r'''
local __ui = {}
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
-- Fake players: the local one (with the PlayerGui) and others for the standings and spectating.
local function __makePlayer(name, displayName, userId, extra)
	local attributes, signals = {}, {}
	local fields = {
		Name = name,
		DisplayName = displayName,
		UserId = userId,
		CharacterAdded = __event().Event,
		CharacterRemoving = __event().Event,
		Changed = __event().Event,
	}
	for key, value in extra or {} do
		fields[key] = value
	end
	local function signal(attribute)
		signals[attribute] = signals[attribute] or __event()
		return signals[attribute]
	end
	return setmetatable(fields, {
		__index = function(_, key)
			if key == "Character" then
				return nil
			elseif key == "WaitForChild" or key == "FindFirstChild" then
				return function(self, childName)
					return rawget(self, childName)
				end
			elseif key == "GetAttribute" then
				return function(_, attribute)
					return attributes[attribute]
				end
			elseif key == "SetAttribute" then
				return function(_, attribute, value)
					attributes[attribute] = value
					signal(attribute):Fire()
				end
			elseif key == "GetAttributeChangedSignal" then
				return function(_, attribute)
					return signal(attribute).Event
				end
			elseif key == "GetPropertyChangedSignal" then
				return function()
					return __event().Event
				end
			elseif key == "IsA" then
				return function(_, className)
					return className == "Player" or className == "Instance"
				end
			end
			error("[harness] fake player has no member '" .. tostring(key) .. "'", 2)
		end,
	})
end
local __player = __makePlayer(
	"HarnessPlayer",
	if __richMode then "SuperLongDisplayNm20" else "Harness",
	1,
	{ PlayerGui = __playerGui, CharacterAdded = __characterAdded.Event }
)
local __players = { __player }
for index, name in { "Bubbles", "xX_Speedy_Xx", "Pancake", "NoodleArms", "Captain Waffles", "Zoomer",
	"Mochi", "LavaLarry", "SirHopsALot", "Tiny Tim", "Glitch" } do
	table.insert(__players, __makePlayer(name, name, 100 + index))
end

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
	Players = __wrap(__realPlayers, {
		LocalPlayer = __player,
		GetPlayers = function()
			return __players
		end,
	}),
	UserInputService = __wrap(game:GetService("UserInputService"), {
		TouchEnabled = __touchMode == true,
		KeyboardEnabled = __touchMode ~= true,
		MouseEnabled = __touchMode ~= true,
	}),
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
	__ui[name] = __dumpGui(__playerGui)
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
-- The ScreenGuis, made with init.client.luau's own properties (see screen_guis() in the script).
local context = {}
for key, props in __screenGuis do
	local gui = Instance.new("ScreenGui")
	for property, value in props do
		(gui :: any)[property] = value
	end
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

-- 2. Profile snapshot, as DataService sends it: a new player (default items, 3 daily and 2 weekly
-- quests with the longest texts), or with --rich a well-used profile.
local Cosmetics = require(Shared.Cosmetics)
local data = table.clone(DataService.Template)
data.Owned = {}
for _, item in Cosmetics.List do
	if item.Default or (__richMode and item.Slot == "Emote") then
		data.Owned[item.Id] = true
	end
end
if __richMode then
	data.Coins = 1234567
	data.XP = 98765
	data.Daily = { LastClaimDay = 0, Streak = 6, SecretDay = 0 }
end
local profile = { Data = data, IsVip = false, CanSave = not __richMode }
local okSnap, snapshot = pcall(DataService.BuildSnapshot, profile)
if okSnap then
	local byPeriod = { Daily = {}, Weekly = {} }
	for _, def in QuestDefinitions.List or {} do
		table.insert(byPeriod[def.Period], def)
	end
	for period, defs in byPeriod do
		table.sort(defs, function(a, b)
			return #a.Text > #b.Text
		end)
		local quests = {}
		for index = 1, math.min(#defs, if period == "Daily" then 3 else 2) do
			local def = defs[index]
			table.insert(quests, { Id = def.Id, Progress = math.min(index - 1, def.Target), Done = index == 2 })
		end
		snapshot.Quests[period] = quests
	end
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
	__ui[screen] = __dumpGui(__playerGui)
	local Modal = __require("Client/UI/Modal")
	if Modal.CloseAll then
		pcall(Modal.CloseAll)
	end
	task.wait(0.3)
end

-- 4. A whole round, phase by phase, with three toasts on screen in the lobby. The vote shows the
-- options with the longest objectives (the fullest cards).
local ids = {}
for _, def in GameDefinitions.List do
	table.insert(ids, def.Id)
end
table.sort(ids, function(a, b)
	return #GameDefinitions.Get(a).Objective > #GameDefinitions.Get(b).Objective
end)
__fire("Notify", "Daily gift ready! Open 📜 Quests to claim it.", "reward", 6)
__fire("Notify", "Bubbles joined the party", "info", 6)
__fire("Notify", "Not enough coins yet - play a round to earn more!", "warning", 6)
phase("Intermission", 20)
phase("Voting", 12, function()
	GameState.SetJSON("VoteOptions", {
		{ Id = ids[1], Mystery = false },
		{ Id = ids[2], Mystery = false },
		{ Id = ids[3], Mystery = true },
	})
	GameState.SetJSON("VoteCounts", { 1, 0, 2 })
	__player:SetAttribute("PP_Vote", 1)
end)
phase("Preparing", 6, function()
	GameState.Set("GameId", ids[1])
	GameState.Set("RoundId", 1)
end)
phase("InRound", 60, function()
	GameState.Set("Status", "Survivors: 9")
	for index, other in __players do
		other:SetAttribute("PP_InRound", true)
		other:SetAttribute("PP_Alive", index <= 9)
		other:SetAttribute("PP_Score", 13 - index)
		other:SetAttribute("PP_ScoreText", if index <= 9 then "Alive" else "Out")
	end
end)
step = "remotes"
__fire("Notify", "Harness notification", "reward", 2)
__fire("PlayEffect", "Confetti", Vector3.new(0, 5, 0))
__fire("PlayEffect", "Fireworks", Vector3.new(0, 10, 0))
__fire("PlayEffect", "Sparkles", Vector3.new(0, 5, 0), { Color3.new(1, 0, 0) })
__fire("PlaySound", "Pickup")
__fire("Knockback", Vector3.new(10, 20, 0), 0.5)
task.wait(1)
-- Knocked out, then watching the others.
step = "Eliminated"
__player:SetAttribute("PP_Alive", false)
task.wait(1.2)
__ui.Eliminated = __dumpGui(__playerGui)
step = "Spectating"
State.OpenScreen:Fire("Spectate")
task.wait(1.2)
__ui.Spectating = __dumpGui(__playerGui)
local Config = require(Shared.Config)
phase("Results", 8, function()
	local labels = {
		Participation = "Played the round",
		TopHalf = "Top half finish",
		Winner = "Winner!",
		PersonalBest = "New personal best",
	}
	local lines = {}
	for _, key in { "Participation", "TopHalf", "Winner", "PersonalBest" } do
		table.insert(lines, { Label = labels[key], Coins = Config.Rewards[key].Coins, XP = Config.Rewards[key].XP })
	end
	local standings = {}
	for index = 1, 8 do
		local other = __players[index]
		table.insert(standings, {
			Name = other.DisplayName,
			UserId = other.UserId,
			Place = index,
			ScoreText = if index == 1 then "Last one standing" else `Out at {80 - index * 7}s`,
		})
	end
	__fire("RoundResults", {
		GameId = ids[1],
		Place = 1,
		PlayerCount = 12,
		ScoreText = "Last one standing",
		Lines = lines,
		Coins = 50,
		XP = 60,
		PersonalBest = true,
		Standings = standings,
	})
	GameState.SetJSON("Champions", { { Name = __player.DisplayName, UserId = 1, Place = 1 } })
end)
phase("Cleanup", 3, function()
	for _, other in __players do
		other:SetAttribute("PP_InRound", false)
	end
end)
phase("Waiting", 0, function()
	GameState.Set("Message", "Waiting for 1 more player")
end)
task.wait(1)

local guiCount = #__playerGui:GetDescendants()
return game:GetService("HttpService"):JSONEncode({
	ui = __ui,
	errors = __errors,
	startMs = startTimes,
	sentToServer = __sent,
	guiInstances = guiCount,
	lastStep = step,
})
'''


def screen_guis() -> str:
    """init.client.luau's ScreenGuis (`local hud = UIKit.new("ScreenGui", {...})`) as a Luau table
    keyed like the controllers' context (Hud, Overlay), so the harness lays out like the game."""
    text = (CLIENT / "init.client.luau").read_text()
    entries = []
    for var, body in re.findall(r'local (\w+) = UIKit\.new\("ScreenGui", \{\n(.*?)\n\}\)', text, flags=re.S):
        props = [line.strip().rstrip(",") for line in body.splitlines()]
        props = [prop for prop in props if prop and not prop.startswith(("Parent", "--"))]
        entries.append(f"\t{var[0].upper() + var[1:]} = {{ {', '.join(props)} }},")
    if not entries:
        raise SystemExit("client_harness: no ScreenGuis found in init.client.luau")
    return "local __screenGuis = {\n" + "\n".join(entries) + "\n}\n"


def main():
    touch = "--touch" in sys.argv
    rich = "--rich" in sys.argv
    gui_dump = (Path(__file__).resolve().parent / "gui_dump.luau").read_text()
    flags = f"__touchMode = {'true' if touch else 'false'}\n__richMode = {'true' if rich else 'false'}\n"
    out = [flags + gui_dump + PRELUDE + screen_guis()]
    for module, path in module_paths().items():
        out.append(f'__modules["{module}"] = function()')
        out.append(rewrite(module, path.read_text()))
        out.append("end")
    out.append(shared_requires(MAIN))
    sys.stdout.write("\n".join(out))


if __name__ == "__main__":
    main()

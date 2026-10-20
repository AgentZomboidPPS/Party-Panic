"""Builds a Luau script that runs the whole CLIENT on a real Roblox server (Open Cloud Luau
execution), so client code can be exercised without a player: every controller starts, then the
script opens each screen, plays through every game phase, and fires every server->client remote.
Errors and warnings from all of it come back in the result.

    python3 tools/checks/client_harness.py [--touch] [--bots N] > client.luau
    python3 tools/preview/luau_task.py client.luau - client.json
    python3 tools/checks/ui_render.py client.json /tmp/screens    # draw every screen and phase

--touch makes the stand-in client a phone (touch, no keyboard), for the phone layouts.
--bots N adds N stand-in bots, shaped like BotService's (a Configuration in
ReplicatedStorage.PartyBots with a character in the world), who play the round with the player:
the standings, team outlines, spectating (you get knocked out), a bot leaving and one arriving
mid-round, the results and a bot champion on the podium. The result's "botChecks" says what the
client did with them, and the extra snapshots ("InRound teams", "Out", "Spectate", "Podium") show
it. The stand-in player is in the round either way.

Client-only APIs are replaced by small stand-ins: Players.LocalPlayer (a fake player with a
PlayerGui folder), RenderStepped (Heartbeat), StarterGui:SetCore, and the remotes (bindable
events the harness can fire). Shared modules come from the working tree (except Remotes).
"""

import argparse
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
local __attributes, __attributeSignals = {}, {}
local function __attributeSignal(name)
	__attributeSignals[name] = __attributeSignals[name] or __event()
	return __attributeSignals[name]
end
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
			return function(_, name)
				return __attributes[name]
			end
		elseif key == "SetAttribute" then -- the harness puts this player in rounds, like RoundContext
			return function(_, name, value)
				__attributes[name] = value
				__attributeSignal(name):Fire()
			end
		elseif key == "GetAttributeChangedSignal" then
			return function(_, name)
				return __attributeSignal(name).Event
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
local __thumbnailIds = {} -- every UserId the client asked for a headshot of
local __shims = {
	Players = __wrap(__realPlayers, {
		LocalPlayer = __player,
		GetPlayers = function()
			return { __player }
		end,
		GetUserThumbnailAsync = function(_, userId, ...)
			table.insert(__thumbnailIds, userId)
			return __realPlayers:GetUserThumbnailAsync(userId, ...)
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
local context = {}
-- Made like init.client.luau makes them, so pop-ups draw over the HUD in the snapshots too.
for key, settings in { Hud = { "PartyPanicHUD", 5, false }, Overlay = { "PartyPanicOverlay", 10, true } } do
	local gui = Instance.new("ScreenGui")
	gui.Name = settings[1]
	gui.DisplayOrder = settings[2]
	gui.IgnoreGuiInset = settings[3]
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
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
	__ui[screen] = __dumpGui(__playerGui)
	local Modal = __require("Client/UI/Modal")
	if Modal.CloseAll then
		pcall(Modal.CloseAll)
	end
	if screen == "Emotes" then
		State.OpenScreen:Fire(screen) -- the emote wheel isn't a modal: its button toggles it shut
	end
	task.wait(0.3)
end

-- 4. A whole round, phase by phase. The stand-in player plays it (round attributes, as RoundContext
-- sets them), with the stand-in bots if there are any (--bots N).
local ids = {}
for _, def in GameDefinitions.List do
	table.insert(ids, def.Id)
end

local Participants = __require("Client/Participants")
local botChecks = { changedFired = 0 }
Participants.Changed:Connect(function()
	botChecks.changedFired += 1
end)

local BOT_NAMES = { "Mochi", "Pip", "Bloop", "Sprocket", "Noodle", "Ziggy", "Pickle", "Bonbon", "Taffy", "Waffles", "Gizmo" }
local BOT_COLORS = {
	Color3.fromRGB(255, 92, 170),
	Color3.fromRGB(80, 205, 255),
	Color3.fromRGB(110, 230, 140),
	Color3.fromRGB(255, 150, 60),
	Color3.fromRGB(170, 120, 255),
	Color3.fromRGB(255, 212, 70),
}
local bots = {}
local botFolder = nil
-- A bot the way BotService makes one: a Configuration with its attributes, pointing at its
-- character (a real R15 rig in the world).
local function addBot()
	local index = #bots + 1
	local name = BOT_NAMES[(index - 1) % #BOT_NAMES + 1]
	local info = Instance.new("Configuration")
	info.Name = "Bot_" .. name
	info:SetAttribute("DisplayName", "🤖 " .. name)
	info:SetAttribute("UserId", -index)
	info:SetAttribute("IsBot", true)
	info:SetAttribute("Color", BOT_COLORS[(index - 1) % #BOT_COLORS + 1])
	local pointer = Instance.new("ObjectValue")
	pointer.Name = "Character"
	pointer.Parent = info
	local okRig, rig = pcall(function()
		return __realPlayers:CreateHumanoidModelFromDescription(
			Instance.new("HumanoidDescription"),
			Enum.HumanoidRigType.R15
		)
	end)
	if okRig then
		rig.Name = info.Name
		rig:PivotTo(CFrame.new(index * 5 - 30, 8, 30))
		rig.Parent = workspace
		pointer.Value = rig
	else
		__note("couldn't build a bot's rig: " .. tostring(rig))
		rig = nil
	end
	info.Parent = botFolder
	local bot = { name = name, display = "🤖 " .. name, userId = -index, info = info, rig = rig }
	table.insert(bots, bot)
	return bot
end
if __botCount > 0 then
	-- Made after the client started, like a server that's still loading when a player joins.
	botFolder = Instance.new("Folder")
	botFolder.Name = "PartyBots"
	botFolder.Parent = ReplicatedStorage
	for _ = 1, __botCount do
		addBot()
	end
end
-- The player and every bot still here.
local function everyone()
	local list = { __player }
	for _, bot in bots do
		if bot.info.Parent then
			table.insert(list, bot.info)
		end
	end
	return list
end
-- The standings rows as they read on screen.
local function boardRows()
	local hud = __playerGui:FindFirstChild("PartyPanicHUD")
	local board = hud and hud:FindFirstChild("Leaderboard")
	local rows = {}
	for _, child in if board then board:GetChildren() else {} do
		if child:IsA("TextLabel") then
			table.insert(rows, child)
		end
	end
	table.sort(rows, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local texts = {}
	for _, row in rows do
		table.insert(texts, row.Text)
	end
	return texts
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
	for _, who in everyone() do
		who:SetAttribute("PP_InRound", true)
		who:SetAttribute("PP_Alive", true)
		who:SetAttribute("PP_Score", 0)
		who:SetAttribute("PP_ScoreText", "")
		who:SetAttribute("PP_Team", "")
	end
end)
phase("InRound", 60, function()
	GameState.Set("Status", "Survivors: 3")
	__player:SetAttribute("PP_Score", 5)
	-- Scores spread around the player's, and one bot already out.
	for index, bot in bots do
		bot.info:SetAttribute("PP_Score", (#bots - index) * 3)
		bot.info:SetAttribute("PP_Alive", index ~= 2)
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

if #bots > 0 then
	step = "bots"
	local first = bots[1]
	botChecks.all = #Participants.All()
	botChecks.inRound = #Participants.InRound()
	local entry = Participants.FromUserId(first.userId)
	botChecks.fromUserId = if entry
		then `{entry.DisplayName} IsBot={entry.IsBot} Color={entry.Color and entry.Color:ToHex()}`
		else "nil"
	botChecks.characterOf = first.rig ~= nil and Participants.CharacterOf(first.userId) == first.rig
	botChecks.escape = Participants.Escape("a<b&c>")
	botChecks.board = boardRows()

	-- Team outlines go on bots too.
	for index, who in everyone() do
		who:SetAttribute("PP_Team", if index % 2 == 0 then "Red" else "Blue")
	end
	task.wait(0.8)
	__ui["InRound teams"] = __dumpGui(__playerGui)
	local outlined = 0
	for _, bot in bots do
		if bot.rig and bot.rig:FindFirstChildOfClass("Highlight") then
			outlined += 1
		end
	end
	botChecks.outlinedBots = outlined
	for _, who in everyone() do
		who:SetAttribute("PP_Team", "")
	end
	task.wait(0.5)

	-- The player is knocked out: the out panel, then spectating (bots are the only others here).
	__player:SetAttribute("PP_Alive", false)
	task.wait(0.8)
	__ui.Out = __dumpGui(__playerGui)
	local outPanel = __playerGui.PartyPanicHUD:FindFirstChild("OutPanel")
	if outPanel then
		outPanel.Visible = false -- what its 👀 Spectate button does
	end
	State.OpenScreen:Fire("Spectate")
	task.wait(0.8)
	__ui.Spectate = __dumpGui(__playerGui)
	local function watching()
		local subject = workspace.CurrentCamera.CameraSubject
		for _, bot in bots do
			if bot.rig and subject and subject:IsDescendantOf(bot.rig) then
				return bot
			end
		end
		return nil
	end
	local watched = watching()
	botChecks.spectating = if watched then watched.display else "nobody"
	if watched then
		-- The bot you're watching is knocked out: the camera moves on to the next one...
		watched.info:SetAttribute("PP_Alive", false)
		task.wait(1.2)
		local nextUp = watching()
		botChecks.spectatingAfterKnockout = if nextUp then nextUp.display else "nobody"
		-- ...who then leaves mid-round (fades out): on to the next again, and off the standings.
		if nextUp then
			nextUp.info:Destroy()
			if nextUp.rig then
				nextUp.rig:Destroy()
			end
			task.wait(1.2)
			local after = watching()
			botChecks.spectatingAfterLeave = if after then after.display else "nobody"
			botChecks.leaverOffBoard = not string.find(table.concat(boardRows(), "\n"), nextUp.name, 1, true)
		end
	end
	-- A bot fades in mid-round: here, but not in this round.
	local newcomer = addBot()
	task.wait(0.5)
	botChecks.allAfterArrival = #Participants.All()
	botChecks.inRoundAfterArrival = #Participants.InRound()
	botChecks.newcomerFound = Participants.FromUserId(newcomer.userId) ~= nil
	botChecks.boardAfter = boardRows()
end

phase("Results", 8, function()
	local standings = {
		{ Name = "Harness", Place = 1, ScoreText = "Survived", UserId = 1 },
		{ Name = "Bot", Place = 2, ScoreText = "Out", UserId = 2 },
	}
	local champions = { { Name = "Harness", UserId = 1, Place = 1 } }
	local place = 1
	if #bots > 0 then
		-- A bot won and the player came second; the third-place bot has left since (no color known).
		standings = {
			{ Name = bots[1].display, Place = 1, ScoreText = "15 pts", UserId = bots[1].userId },
			{ Name = "Harness", Place = 2, ScoreText = "12 pts", UserId = 1 },
		}
		for index = 3, math.min(#bots, 8) do
			local bot = bots[index]
			local score = `{12 - index} pts`
			table.insert(standings, { Name = bot.display, Place = index, ScoreText = score, UserId = bot.userId })
		end
		champions = {
			{ Name = bots[1].display, UserId = bots[1].userId, Place = 1 },
			{ Name = "Harness", UserId = 1, Place = 2 },
		}
		if bots[3] then
			table.insert(champions, { Name = bots[3].display, UserId = bots[3].userId, Place = 3 })
		end
		place = 2
	end
	__fire("RoundResults", {
		GameId = ids[1],
		Place = place,
		PlayerCount = 1 + math.max(#bots, 2),
		ScoreText = "Survived",
		Lines = { { Label = "Participation", Coins = 10, XP = 25 }, { Label = "1st place", Coins = 30, XP = 25 } },
		Coins = 40,
		XP = 50,
		PersonalBest = true,
		Standings = standings,
	})
	GameState.SetJSON("Champions", champions)
end)

if #bots > 0 then
	-- The podium name tags are BillboardGuis in the world; copy them onto a screen to draw them.
	step = "podium"
	task.wait(1)
	local folder = Instance.new("Folder")
	local screen = Instance.new("ScreenGui")
	screen.Name = "PodiumTags"
	screen.Parent = folder
	local podium = {}
	for _, gui in __playerGui:GetChildren() do
		local spot = gui:IsA("BillboardGui") and gui.Adornee
		local spotPlace = spot and spot:GetAttribute("Place")
		if spotPlace then
			local frame = Instance.new("Frame")
			frame.Name = "Place" .. spotPlace
			frame.BackgroundTransparency = 1
			frame.Size = gui.Size
			frame.Position = UDim2.fromOffset(80 + (spotPlace - 1) * 190, 140)
			frame.Visible = gui.Enabled
			for _, child in gui:GetChildren() do
				child:Clone().Parent = frame
			end
			for _, item in frame:GetDescendants() do
				if item:IsA("UIGradient") and not item.Enabled then
					item:Destroy()
				end
			end
			frame.Parent = screen
			local image = gui:FindFirstChildOfClass("ImageLabel")
			local robot = image and image:FindFirstChild("Robot")
			local name = gui:FindFirstChildOfClass("TextLabel")
			table.insert(podium, {
				place = spotPlace,
				shown = gui.Enabled,
				name = name and name.Text,
				robot = robot and robot.Visible,
				image = image and image.Image,
				color = image and image.BackgroundColor3:ToHex(),
			})
		end
	end
	table.sort(podium, function(a, b)
		return a.place < b.place
	end)
	__ui.Podium = __dumpGui(folder)
	botChecks.podium = podium
	botChecks.headshotsAskedFor = __thumbnailIds
end

phase("Cleanup", 3, function()
	for _, who in everyone() do
		who:SetAttribute("PP_InRound", false)
		who:SetAttribute("PP_Alive", false)
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
	botChecks = if #bots > 0 then botChecks else nil,
})
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--touch", action="store_true", help="the stand-in client is a phone (touch, no keyboard)")
    parser.add_argument("--bots", type=int, default=0, help="stand-in bots that play the round with the player")
    args = parser.parse_args()
    gui_dump = (Path(__file__).resolve().parent / "gui_dump.luau").read_text()
    out = [f"__touchMode = {'true' if args.touch else 'false'}\n__botCount = {args.bots}\n" + gui_dump + PRELUDE]
    for module, path in module_paths().items():
        out.append(f'__modules["{module}"] = function()')
        out.append(rewrite(module, path.read_text()))
        out.append("end")
    out.append(shared_requires(MAIN))
    sys.stdout.write("\n".join(out))


if __name__ == "__main__":
    main()

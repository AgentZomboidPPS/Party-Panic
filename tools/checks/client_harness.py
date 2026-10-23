"""Builds a Luau script that runs the whole CLIENT on a real Roblox server (Open Cloud Luau
execution), so client code can be exercised without a player: every controller starts, then the
script opens each screen, plays through every game phase, and fires every server->client remote.
Errors and warnings from all of it come back in the result.

    python3 tools/checks/client_harness.py [--touch] [--rich] [--bots N] [--sit-out] > client.luau
    python3 tools/preview/luau_task.py client.luau - client.json
    python3 tools/checks/ui_render.py client.json /tmp/screens    # draw every screen and phase

--touch makes the stand-in client a phone (touch, no keyboard), for the phone layouts.
--skip SkeeBall leaves the Skee-Ball section and its controller out: the whole client is within a few
KB of Open Cloud's 1 MiB script cap, so a run checking something else (the crate season's screens,
"Crates ...", "Crate ...") makes room that way.
--sizes lists the screens every snapshot is laid out on by the ENGINE (gui_dump.luau: real sizes,
text measurements and wrapping, with the fonts loaded); default: the touch sizes with --touch, else
the PC ones. The result's "textReport" lists every text that doesn't fit on one of them.
--rich gives the player a well-used profile (every emote, lots of coins, a long name, a claimable
daily gift, a high level with its prestige color, the road and career rewards it has earned) to
check the layouts at their fullest; the default is a brand-new player.
--bots N adds N stand-in bots, shaped like BotService's (a Configuration in
ReplicatedStorage.PartyBots with a character in the world), who play the round with the player:
the standings, team outlines, spectating (you get knocked out), a bot leaving and one arriving
mid-round, the results and a bot champion on the podium. The result's "botChecks" says what the
client did with them, and the extra snapshots ("InRound teams", "Podium") show it. The stand-in
players are in the round either way, and the player is always knocked out ("Out", "Spectate").
In the round, the team pill under the status line shows every kind of team ("hudChecks": what it
read and how wide it was; "InRound teams": four teams, its widest), and a mode's two action buttons
show with two toasts up ("InRound buttons": on phones the toasts sit above the buttons; "hudChecks"
says whether they did and came back down after, and whether the mode HUD's scales let go).
A quieter round (owner: "During the mini games, any way we can save UI space so they can see more of
the game at one time?"): while the player plays, the menu column waits behind the ☰ and the phone
standings show the player and the leader; "InRound menu" is the screen with both tapped open, and
"hudChecks.quiet" says what showed before, then, and 5.5 seconds later (the banner's players-left
pill, the status line, the mode HUDs' shift). Of the two toasts in "InRound buttons", the round's
callout (topic "Round") shows (on phones in the strip under the banner) and the quest waits until
the player is out ("hudChecks.toasts"); the mode's hint has faded 7 seconds after it was set.
The result's "botReports" holds the round's bot report (Controllers/BotWatchController) as the
device would send it.
The result's "portals" says what each of the vote stage's portals shows in each phase (its game,
"✓ YOUR VOTE", Random's spinning reel, the winner), as text.
After the round the player sits out (the sit-out switch by the banner): a tap with no answer from
the server (it slides back), then the server's answer, and the screens that change for someone
sitting out. The result's "sitOutChecks" says what the switches, the vote note and the round HUD
showed. --sit-out draws those screens ("Intermission sitting out", "Voting sitting out", "Waiting
everyone on a break", "Preparing sitting out", "InRound sitting out", "InRound back in", "Settings
sitting out") next to the playing ones to compare (Intermission, Voting, Preparing, InRound,
Results, Settings), and leaves the rest out. Open Cloud refuses a task's result over 4 MB
(OUTPUT_SIZE_LIMIT_EXCEEDED), so a snapshot records only what's on screen and leaves out the values
most objects share (gui_dump.luau: the result carries them as "uiDefaults" for ui_render.py): a
whole phone run is about 1 MB. --shots NAME,... keeps just those snapshots (the run still plays
everything and reports every error).

Client-only APIs are replaced by small stand-ins: Players.LocalPlayer (a fake player with a
PlayerGui folder and attributes) and, without --bots, 11 other fake players for the standings, RenderStepped
(Heartbeat), StarterGui:SetCore, SocialService's invites (the invite chip) and the remotes (bindable
events the harness can fire). The two
ScreenGuis are made like init.client.luau makes them. Shared modules come from the working tree
(except Remotes), and so does the profile snapshot (DataService and the two services it needs).
The result's "effectChecks" plays every effect a cosmetic names, all at once, and says what each made
(parts, glowing parts and the biggest, particle emitters and their longest lifetime, emoji) and how
much was left 5 s later (none: everything cleans itself up). "Shop <Tab>" and "Shop <Tab> end" show
every shop tab at the top and scrolled to the end; "Emotes end" the emote picker's last emotes.
Besides the menu's screens it opens the Rewards screen on both tabs ("Rewards", "Rewards Career")
and shows a level-up, a career milestone and a returning player's celebration ("LevelUp",
"LevelUp2", "Milestone", "Welcome"). After the round a level-up card shows while the last
first-join tip is due; the result's "tipChecks" says what was on screen while it was up and after.
Medals (MedalController): a MEDAL EARNED card ("Medal"), the medals a returning player had already
earned as one card ("Medals earlier"), the Rewards screen's MEDALS tab ("Rewards Medals"), and the
medal wall lit up for the player; the result's "medalChecks" says what showed when (a card waits
out the vote and steps aside for a level-up card).
The results card asks PLAY AGAIN? (Services/ReplayService): "Results" shows the vote open, "Results
replay" after the player tapped PLAY AGAIN, "Results replay capped" after the most replays in a row;
the result's "replayChecks" says what the strip showed each time. Beside the title, 👍 / 👎 on the game
(Services/RatingService): "Results" with neither lit, "Results replay" with 👍 lit, "Results rated
down" with 👎 lit; "ratingChecks" says what the pair showed each time (and nothing once the vote
closes).
The GOLD PASS (Controllers/GoldPassController, the Rewards screen's gold lane): the screen while the
pass is off sale on Roblox ("Rewards gold soon": COMING SOON) and on sale ("Rewards gold offer": GET
GOLD PASS with its price), the UNLOCKED N REWARDS! card a purchase shows ("Gold unlocked"), the screen
once it's owned ("Rewards gold owned": the gold lane lit, EQUIP on its rewards), a level-up with the
gold lane's coins and a gold reward ("LevelUp gold"), the Shop's gold hats ("Shop gold") and name tags
with and without the GOLD badge ("Name tags"). --gold gives the player the pass from the start (the
HUD's gold level badge, Settings' teaser, the road lit everywhere). Roblox's price and sale state are
set by the run (GoldPassController.SetOfferForTests). The result's "goldChecks" says what the gold
button, the tiles and the card read each time, and whether a tap asked the server for the prompt.
"""

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bundling  # noqa: E402  (only the modules the run needs: Open Cloud's 1 MiB script cap)
from ui_render import devices_luau, size_names  # noqa: E402  (the screens the engine lays the UI out on)

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "src" / "client"
SHIMMED_SERVICES = ("Players", "RunService", "StarterGui", "UserInputService", "SocialService")
# Server modules bundled from the working tree: the profile snapshot the client is sent.
SERVER_MODULES = ("DataService", "Notifier", "Telemetry")


def played_game() -> str:
    """The mode the run plays: the one with the longest objective (as the Luau side picks it)."""
    text = (ROOT / "src" / "shared" / "GameDefinitions.luau").read_text()
    entries = re.findall(r'Id = "(\w+)",.*?Objective = "((?:[^"\\]|\\.)*)"', text, re.S)
    return max(entries, key=lambda entry: len(entry[1].encode()))[0]


def module_paths():
    paths = {}
    # The working tree's shared modules, so client code runs against the code it ships with.
    for path in sorted((ROOT / "src" / "shared").rglob("*.luau")):
        rel = path.relative_to(ROOT / "src" / "shared").with_suffix("")
        if rel.parts != ("Remotes",):  # replaced by the harness's stand-in
            paths["Shared/" + "/".join(rel.parts)] = path
    played = played_game()
    for path in sorted(CLIENT.rglob("*.luau")):
        if path.name == "init.client.luau":
            continue
        rel = path.relative_to(CLIENT).with_suffix("")
        if rel.parts[:1] == ("MiniGames",) and len(rel.parts) == 2 and rel.parts[1] not in ("init", played):
            continue  # only the played mode's client half (Luau execution's 1 MB script limit)
        paths["Client/" + "/".join(rel.parts)] = path
    for name in SERVER_MODULES:
        paths[f"Server/Services/{name}"] = ROOT / "src" / "server" / "Services" / f"{name}.luau"
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
-- A signal that hands its handlers the very values it's fired with (a BindableEvent copies tables),
-- for stand-in InputObjects: a drag is followed by comparing them.
local function __luaSignal()
	local handlers = {}
	local signal = {}
	function signal.Connect(_, callback)
		local entry = { callback = callback }
		table.insert(handlers, entry)
		return {
			Connected = true,
			Disconnect = function()
				entry.callback = nil
			end,
		}
	end
	function signal.Fire(_, ...)
		for _, entry in table.clone(handlers) do
			if entry.callback then
				entry.callback(...)
			end
		end
	end
	return signal
end
local __inputBegan, __inputChanged, __inputEnded = __luaSignal(), __luaSignal(), __luaSignal()
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
-- With --bots the bots are the others (the only ones with characters to spectate).
local __players = { __player }
local __otherNames = { "Bubbles", "xX_Speedy_Xx", "Pancake", "NoodleArms", "Captain Waffles", "Zoomer",
	"Mochi", "LavaLarry", "SirHopsALot", "Tiny Tim", "Glitch" }
for index, name in if __botCount > 0 then {} else __otherNames do
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
local __thumbnailIds = {} -- every UserId the client asked for a headshot of
local __shims = {
	Players = __wrap(__realPlayers, {
		LocalPlayer = __player,
		GetPlayers = function()
			return __players
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
		-- Stand-in fingers and mouse (the Skee-Ball drag checks fire them).
		InputBegan = __inputBegan,
		InputChanged = __inputChanged,
		InputEnded = __inputEnded,
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
-- Roblox's SocialService (InviteController's invite chip): the stand-in player isn't a real one to
-- ask about, so the stand-in service says it can send invites, and its prompt opens nothing.
__shims.SocialService = __wrap(game:GetService("SocialService"), {
	CanSendGameInviteAsync = function()
		return true
	end,
	PromptGameInvite = function() end,
})
local function __service(name)
	return __shims[name] or game:GetService(name)
end

local __remotes, __sent, __soundReports, __skeeSent, __botReports = {}, {}, {}, {}, {}
local __RemotesShim = {
	Get = function(name)
		if not __remotes[name] then
			local bindable = __event()
			__remotes[name] = {
				Name = name,
				OnClientEvent = bindable.Event,
				FireServer = function(_, first, ...)
					table.insert(__sent, name)
					if name == "SkeeBall" then
						table.insert(__skeeSent, { first, ... })
					end
					if name == "ClientReport" and type(first) == "table" and first.Kind == "Sound" then
						table.insert(__soundReports, first)
					end
					if name == "ClientReport" and type(first) == "table" and first.Kind == "Bots" then
						table.insert(__botReports, first) -- Controllers/BotWatchController's round report
					end
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
	-- The vote stage's preview portals, when the place's lobby is older than this client.
	if #game:GetService("CollectionService"):GetTagged("PortalScreen") == 0 then
		for index = 1, 4 do
			local screen = Instance.new("Part")
			screen.Name = "PortalScreen" .. index
			screen.Anchored = true
			screen.Size = Vector3.new(14, 19.8, 0.2)
			screen.CFrame = CFrame.new((index - 2.5) * 22, 12.3, -63.5)
			screen:SetAttribute("VoteIndex", index)
			screen:SetAttribute("PortalColor", Color3.fromRGB(255, 84, 150))
			screen:AddTag("PortalScreen")
			screen.Parent = token.Parent
		end
	end
end

-- Server side state the client reads (real shared modules).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
GameState.Folder()
local GameDefinitions = require(Shared.GameDefinitions)
local DataService = __require("Server/Services/DataService") -- the working tree's snapshot
local QuestDefinitions = require(Shared.QuestDefinitions)

local step = "start"
-- The banner messages RoundManager sets with each phase (the game's name from Preparing to Results).
local MESSAGES = {
	Intermission = "Next vote soon!",
	Voting = "Vote for the next game!",
	Cleanup = "Back to the lobby!",
	Waiting = "Waiting for 1 more player...",
}
-- The vote stage's portals as they read (WorldScreensController): what each one shows, e.g.
-- "2: 🎲 | RANDOM | ? [reel]" or "1: 🔥 | FIRE ROPE | ✓ YOUR VOTE [preview]".
local __portals = {}
local function portalReport()
	local rows = {}
	for _, gui in __playerGui:GetChildren() do
		local index = string.match(gui.Name, "^Screen_PortalScreen(%d)$")
		if not index or not gui:IsA("SurfaceGui") then
			continue
		end
		local function shown(item)
			while item and item ~= gui do
				if item:IsA("GuiObject") and not item.Visible then
					return false
				end
				item = item.Parent
			end
			return true
		end
		local texts, pictures, reel = {}, 0, false
		for _, item in gui:GetDescendants() do
			if item:IsA("TextLabel") and item.Text ~= "" and item.TextTransparency < 1 and shown(item) then
				table.insert(texts, item.Text)
			elseif item:IsA("ImageLabel") and item.Image ~= "" and shown(item) then
				pictures += 1
			elseif item:IsA("Frame") and item.ClipsDescendants and item.Parent and item.Parent:IsA("Frame") then
				reel = reel or item.Visible
			end
		end
		local extras = (if reel then " [reel]" else "") .. (if pictures > 0 then ` [{pictures} preview]` else "")
		table.insert(rows, `{index}: {table.concat(texts, " | ")}{extras}`)
	end
	table.sort(rows)
	return rows
end

-- The snapshots this run returns (Open Cloud caps a task's result, and every screen at once is
-- over it): the sit-out screens only with --sit-out (true: drawn then; false: never), and then
-- just the playing screens to compare them with.
local SIT_OUT_SHOTS = {
	["Intermission sitting out"] = true,
	["Voting sitting out"] = true,
	["Waiting everyone on a break"] = true,
	["Preparing sitting out"] = true,
	["InRound sitting out"] = true,
	["InRound back in"] = true,
	["Settings sitting out"] = true,
	["Cleanup sitting out"] = false,
}
local SIT_OUT_COMPARE =
	{ Intermission = true, Voting = true, Preparing = true, InRound = true, Results = true, Settings = true }
local function snap(key, root)
	local sitOut = SIT_OUT_SHOTS[key]
	local wanted = if __sitOutMode then sitOut == true or SIT_OUT_COMPARE[key] == true else sitOut == nil
	if __onlyShots then
		wanted = __onlyShots[key] == true -- --shots: just these
	end
	if wanted then
		__ui[key] = __dumpGui(root or __playerGui, key)
	end
end

-- `label` names the snapshot when it isn't the phase's own (e.g. "Voting sitting out"); `message`
-- is the banner's line when it isn't the usual one.
local function phase(name, seconds, extra, label, message)
	local key = label or name
	step = "phase " .. key
	if extra then
		extra()
	end
	local definition = GameDefinitions.Get(GameState.Get("GameId") or "")
	GameState.Set("Message", message or MESSAGES[name] or (definition and definition.Name) or "")
	GameState.Set("Phase", name)
	GameState.Set("PhaseEndsAt", if seconds > 0 then workspace:GetServerTimeNow() + seconds else 0) -- 0: no timer, like RoundManager
	task.wait(1.2)
	snap(key)
	__portals[key] = portalReport()
end

-- 1. Start every controller like init.client.luau does.
local State = __require("Client/State")
local okInit, initErr = pcall(State.Init)
if not okInit then
	__note("State.Init failed: " .. tostring(initErr))
end
local order = {
	"AudioController", "NotificationController", "EffectsController", "PetController", "AuraController",
	"AmbienceController",
	"MovementController", "WorldScreensController", "HudController", "VoteController",
	"RoundController", "ResultsController", "ShopController", "QuestController",
	"RewardsController", "CelebrationController", "GoldPassController", "TitleController",
	"CupController", "InviteController", "PartyController", "SquadController", "PartyWorldController", "MedalController",
	"HallOfFameController", "EventController", "SeasonWorldController", "CrateController",
	"EmoteController", "SpectateController", "OnboardingController", "SkeeBallController", "AssetReportController",
	"BotWatchController",
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
-- quests with the longest texts), or with --rich a well-used profile: a high level (and its
-- prestige color), every emote, the road and career rewards it has earned, career stats partway.
local Cosmetics = require(Shared.Cosmetics)
local LevelCurve = require(Shared.Logic.LevelCurve)
local data = table.clone(DataService.Template)
data.Owned = {}
data.Stats = table.clone(DataService.Template.Stats)
if __richMode then
	data.Coins = 99999 -- the most a player plausibly saves on the low coin scale
	data.XP = 98765
	data.Daily = { LastClaimDay = 0, Streak = 6, SecretDay = 0, FirstWinDay = 0 }
	data.Stats.RoundsPlayed = 180
	data.Stats.Wins = 12
	data.Stats.Podiums = 31
	data.Stats.TeamWins = 4
	data.Stats.GamesTried = 9
	data.Stats.DaysPlayed = 8
end
local richLevel = LevelCurve.FromTotalXP(data.XP)
for _, item in Cosmetics.List do
	local earned = item.Default
		or (__richMode and item.Slot == "Emote")
		or (item.UnlockLevel ~= nil and richLevel >= item.UnlockLevel)
		or (item.UnlockStat ~= nil and (data.Stats[item.UnlockStat.Stat] or 0) >= item.UnlockStat.Value)
		or (__goldMode and item.GoldLevel ~= nil and richLevel >= item.GoldLevel)
	if earned then
		data.Owned[item.Id] = true
	end
end
data.GoldPass = { Owned = __goldMode, Since = 0, CoinsTo = if __goldMode then richLevel else 1 }
if __richMode then
	data.Equipped = table.clone(DataService.Template.Equipped)
	data.Equipped.Title = "Title_Icon"
	data.Equipped.Trail = "Trail_Starry"
	if __goldMode then
		data.Equipped.Title = "Title_GildedLegend"
		data.Equipped.Trail = "Trail_LiquidSunlight"
		data.Equipped.Hat = "Hat_GildedTopHat"
	end
end
local profile = { Data = data, CanSave = not __richMode }
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

-- 3. Screens opened by the lobby prompts and the HUD (the profile chip opens Rewards; its Career
-- tab is a second snapshot).
for _, screen in { "Shop", "Quests", "Emotes", "Settings", "Rewards", "Rewards Career" } do
	step = "OpenScreen " .. screen
	if screen == "Rewards Career" then
		State.OpenScreen:Fire("Rewards", "Career")
	else
		State.OpenScreen:Fire(screen)
	end
	task.wait(1)
	snap(screen)
	if screen == "Emotes" then
		-- The picker scrolled to its last emotes ("Emotes end": with --rich, every emote is owned).
		local list = nil
		for _, item in __playerGui:GetDescendants() do
			if item.Name == "Emotes" and item:GetAttribute("PP_Popup") then
				list = item:FindFirstChildOfClass("ScrollingFrame")
			end
		end
		if list then
			list.CanvasPosition = Vector2.new(0, 100000)
			list:SetAttribute("PP_ScrollToEnd", true)
			task.wait(0.3)
			snap("Emotes end")
			list:SetAttribute("PP_ScrollToEnd", nil)
		end
	end
	local Modal = __require("Client/UI/Modal")
	if Modal.CloseAll then
		pcall(Modal.CloseAll)
	end
	if screen == "Emotes" then
		State.OpenScreen:Fire(screen) -- the emote wheel isn't a modal: its button toggles it shut
	end
	task.wait(0.3)
end

-- 3g. The GOLD PASS (Controllers/GoldPassController, RewardsController's gold lane). Off sale on Roblox
-- ("Rewards gold soon"), on sale ("Rewards gold offer", and a tap on GET GOLD PASS asks the server for
-- Roblox's prompt), bought ("Gold unlocked": what buying it at level 26 unlocks), owned ("Rewards gold
-- owned": a level-26 owner wearing the ROYAL CROWN), a level-up with gold coins and a gold reward
-- ("LevelUp gold"), the Shop's gold hats ("Shop gold") and name tags ("Name tags"). With --gold the
-- player owns it from the start, so the off-sale and on-sale screens are left out. The profile is put
-- back as it was after.
local goldChecks = {}
do
	local Gold = __require("Client/Controllers/GoldPassController")
	local ModalUI = __require("Client/UI/Modal")
	local Celebrations = __require("Client/Controllers/CelebrationController")
	local Progression = require(Shared.Progression)
	local GoldLane = require(Shared.Logic.GoldLane)
	local NameTag = require(Shared.NameTag)
	local LevelCurve = require(Shared.Logic.LevelCurve)
	-- What the Rewards screen's gold button and the tiles in view read (the road makes a level's
	-- tiles when it scrolls near: the first eight levels that have them).
	local function read()
		local overlay = __playerGui:FindFirstChild("PartyPanicOverlay")
		local window = overlay and overlay:FindFirstChild("RewardsModal")
		local button = window and window:FindFirstChild("GoldPass", true)
		local words = {}
		if button then
			for _, item in button:GetDescendants() do
				if item:IsA("TextLabel") and item.Text ~= "" then
					table.insert(words, item.Text)
				end
			end
		end
		local tiles = {}
		local road = window and window:FindFirstChild("Road", true)
		if road then
			local columns = {}
			for _, column in road:GetChildren() do
				local level = tonumber(string.match(column.Name, "^Level(%d+)$"))
				if level and column:FindFirstChild("Status", true) then
					table.insert(columns, { level, column })
				end
			end
			table.sort(columns, function(a, b)
				return a[1] < b[1]
			end)
			for index = 1, math.min(#columns, 8) do
				local level, column = columns[index][1], columns[index][2]
				local lanes = { free = {}, gold = {} }
				for _, tile in column:GetChildren() do
					local status = tile:FindFirstChild("Status")
					if status and status:IsA("TextLabel") and tile:IsA("GuiObject") then
						local lane = if tile.Position.Y.Offset > column.Size.Y.Offset / 2 - 20 then lanes.gold else lanes.free
						local lock = if tile:FindFirstChild("Lock", true) then "🔒 " else ""
						table.insert(lane, `{lock}{tile.Name}: {status.Text}{if tile:IsA("TextButton") then " [tap]" else ""}`)
					end
				end
				table.insert(tiles, `Lv {level}  FREE {table.concat(lanes.free, ", ")}  GOLD {table.concat(lanes.gold, ", ")}`)
			end
		end
		return { button = if button then `{button.ClassName}: {table.concat(words, " | ")}` else "missing", tiles = tiles }
	end
	local function openRoad()
		pcall(ModalUI.CloseAll)
		task.wait(0.2)
		State.OpenScreen:Fire("Rewards", "Road")
		task.wait(1.2)
	end
	local before = if okSnap then table.clone(snapshot) else nil
	if okSnap and not __goldMode then
		step = "gold: off sale"
		Gold.SetOfferForTests({ OnSale = false, Price = 399, Known = true })
		openRoad()
		goldChecks.offSale = read()
		snap("Rewards gold soon")
		step = "gold: on sale"
		Gold.SetOfferForTests({ OnSale = true, Price = 399, Known = true })
		task.wait(1.2) -- (the screen redraws when the offer changes)
		goldChecks.onSale = read()
		snap("Rewards gold offer")
		local sentBefore = #__sent
		Gold.Prompt()
		goldChecks.promptAsked = __sent[sentBefore + 1] or "nothing"
	end
	-- Bought at level 26: the server's grant (Services/GoldPassService) as this device sees it.
	if okSnap then
		step = "gold: bought"
		pcall(ModalUI.CloseAll)
		local level = 26
		local bought = table.clone(snapshot)
		bought.Level = level
		bought.XP = LevelCurve.TotalXPForLevel(level) + 300
		bought.LevelXP, bought.LevelNeed = 300, LevelCurve.XPForLevel(level)
		bought.Owned = table.clone(snapshot.Owned)
		bought.Equipped = table.clone(snapshot.Equipped)
		for _, item in Cosmetics.List do
			if (item.UnlockLevel and item.UnlockLevel <= level) or (item.GoldLevel and item.GoldLevel <= level) then
				bought.Owned[item.Id] = true
			end
		end
		bought.Equipped.Hat = "Hat_RoyalCrown"
		bought.Equipped.Title = "Title_Jackpot"
		bought.GoldPass = { Owned = true }
		local unlock = GoldLane.Retroactive(Progression.GoldLane, level, 1, snapshot.Owned)
		Gold.SetOfferForTests({ OnSale = true, Price = 399, Known = true })
		openRoad()
		__fire("ProfileData", bought)
		__fire("GoldPass", "Unlocked", {
			Level = level,
			Count = unlock.Count,
			Coins = unlock.Coins,
			Items = unlock.Items,
			Source = "Purchase",
		})
		task.wait(2.6) -- the rewards pop in one by one, the count runs up
		local layer = __playerGui:FindFirstChild("PartyPanicGold")
		local card = layer and layer:FindFirstChild("Card", true)
		local headline = card and card:FindFirstChild("Headline")
		local chips = {}
		local row = card and card:FindFirstChild("Rewards")
		if row then
			for _, slot in row:GetChildren() do
				local chip = slot:IsA("Frame") and slot:FindFirstChildWhichIsA("Frame")
				if chip then
					table.insert(chips, { slot.LayoutOrder, `{chip.Name}{if chip.Visible then "" else " (hidden)"}` })
				end
			end
		end
		table.sort(chips, function(a, b)
			return a[1] < b[1]
		end)
		local chipNames = {}
		for _, chip in chips do
			table.insert(chipNames, chip[2])
		end
		goldChecks.unlocked = {
			payload = `Count {unlock.Count}, Coins {unlock.Coins}, Items {#unlock.Items}`,
			headline = if headline then headline.Text else "missing",
			chips = chipNames,
		}
		snap("Gold unlocked")
		Gold.Dismiss()
		task.wait(0.5)
		-- (Open again: a screen that redraws keeps its place, here the level-1 start.)
		openRoad()
		goldChecks.owned = read()
		snap("Rewards gold owned")
		pcall(ModalUI.CloseAll)
		task.wait(0.4)
		-- A level-up from 26 to 28 for an owner: the road's coins, the gold lane's coins (27) and
		-- its reward (28: TREASURE POP).
		step = "gold: level-up"
		__fire("Celebrate", {
			Kind = "LevelUp",
			Level = 28,
			From = 26,
			Coins = Progression.Coins(27) + Progression.Coins(28),
			GoldCoins = Progression.GoldCoins(27),
			Items = { "Elim_TreasurePop" },
		})
		task.wait(1.6)
		snap("LevelUp gold")
		Celebrations.Dismiss()
		task.wait(0.4)
		step = "gold: shop"
		State.OpenScreen:Fire("Shop", "Hat")
		task.wait(1.2)
		snap("Shop gold")
		pcall(ModalUI.CloseAll)
		task.wait(0.3)
	end
	-- Name tags (Shared/NameTag, the server's PP_Nameplate): a player's; an owner's with the GOLD
	-- badge and VIP Partier shimmering; a long-named top-tier owner wearing THE GOLDEN ONE. Then the
	-- crate seasons': THE HARVESTER (plain, and on a GOLD tag), and the frames for crates opened
	-- (bronze, gold, harvest moon) and for a finished season.
	step = "gold: name tags"
	local folder = Instance.new("Folder")
	local screen = Instance.new("ScreenGui")
	screen.Name = "NameTags"
	screen:SetAttribute("PP_Billboards", true) -- ui_render.py: check the text, not where they sit
	screen.Parent = folder
	local tags = {
		{ "Pancake", 12, false, "Title_Pro" },
		{ "Harness", 26, true, "Title_VIP" },
		{ "SuperLongDisplayNm20", 100, true, "Title_GoldenOne" },
		{ "LeafPileLeo", 31, false, "Title_Harvester", { CrateFrame = 250 } },
		{ "Harvester", 64, true, "Title_Harvester", { CrateFrame = 500 } },
		{ "Bronze", 8, false, "Title_Rookie", { CrateFrame = 10 } },
		{ "Golden", 44, false, "Title_Pro", { CrateFrame = 100 } },
		{ "CompletedIt", 52, false, "Title_Harvester", { CrateFrame = 500, SeasonComplete = "HollowNight" } },
	}
	local nameChecks = {}
	for index, tag in tags do
		local okTag, gui = pcall(NameTag.Build, tag[1], tag[2], tag[3], Cosmetics.Get(tag[4]), tag[5])
		if not okTag then
			__note("NameTag.Build failed: " .. tostring(gui))
			continue
		end
		local frame = Instance.new("Frame")
		frame.Name = `Tag{index}`
		frame.BackgroundTransparency = 1
		frame.Size = gui.Size
		frame.Position = UDim2.fromOffset(60 + ((index - 1) % 4) * 260, 120 + math.floor((index - 1) / 4) * 110)
		local parts = {}
		for _, child in gui:GetChildren() do
			child:Clone().Parent = frame
		end
		for _, item in gui:GetDescendants() do
			if item:IsA("TextLabel") then
				table.insert(parts, item.Name .. "=" .. item.Text)
			elseif item:IsA("UIGradient") and item:GetAttribute("PP_Shimmer") then
				table.insert(parts, `{item.Parent and item.Parent.Name} shimmers ({item:GetAttribute("PP_Shimmer")})`)
			elseif item:IsA("Frame") and item:GetAttribute("PP_Frame") then
				table.insert(parts, `frame {item:GetAttribute("PP_Frame")} {item.Size.X.Offset} wide`)
			elseif item.Name == "MoonLeft" or item.Name == "MoonRight" then
				table.insert(parts, item.Name)
			end
		end
		table.insert(nameChecks, `{tag[1]} ({gui.Size.Y.Offset} tall): {table.concat(parts, "; ")}`)
		frame.Parent = screen
		gui:Destroy()
	end
	goldChecks.nameTags = nameChecks
	snap("Name tags", folder)
	-- As it was (in --gold, the owner's profile again).
	if before then
		Gold.SetOfferForTests({ OnSale = false, Price = 399, Known = true })
		__fire("ProfileData", before)
		task.wait(0.5)
	end
end

-- 3a. The HALLOWEEN PARTY (Controllers/EventController): the lobby chip and the event screen ("Event":
-- 62 candy, the first reward and the PUMPKIN HAT claimed (its EQUIP), the two between them ready),
-- then one of its double coins weekends ("Event double"), the hat in the Shop's Hats tab ("Shop hats")
-- and beside the Rewards screen's road ("Rewards hat"), then the party over (nothing on: the chip
-- leaves the row, the light goes back). Then the candy a round pays pops on the chip back in the
-- lobby. The result's "eventChecks" says what the chip read each time. The party stays on after.
local eventChecks = {}
do
	local function chipText()
		local hud = __playerGui:FindFirstChild("PartyPanicHUD")
		local chip = hud and hud:FindFirstChild("Event", true)
		local badge = chip and chip:FindFirstChild("Ready")
		local row = chip and chip.Parent
		local up = row ~= nil and row:IsA("GuiObject") and row.Visible and chip.Visible
		return if chip and chip:IsA("TextButton")
			then `{chip.Text} [{if up then "on screen" else "off screen"}{if badge and badge.Visible then ", !" else ""}]`
			else "missing"
	end
	-- The lobby's look for the event (this server's Lighting stands in for a device's): its colour
	-- correction while the party is on, and Lighting exactly as it was once it's over.
	local Lighting = game:GetService("Lighting")
	local function look()
		local effect = Lighting:FindFirstChild("PP_EventLook")
		return `{if effect then "on" else "off"}, outdoor ambient {Lighting.OutdoorAmbient:ToHex()}, shift top {Lighting.ColorShift_Top:ToHex()}`
	end
	eventChecks.lookBefore = look()
	local now = workspace:GetServerTimeNow()
	local party = { Id = "Halloween2026", Name = "HALLOWEEN PARTY", EndsAt = now + 9.5 * 86400, DoubleCoins = false, DoubleEndsAt = 0 }
	local today = math.floor(now / 86400)
	if okSnap then
		snapshot.Events = {
			Halloween2026 = {
				Candy = 62,
				Claimed = { Emote_CandyToss = true, Hat_Pumpkin = true },
				Found = { Day = today, Spots = { 3 } },
			},
		}
		snapshot.Owned = snapshot.Owned or {}
		snapshot.Owned.Emote_CandyToss = true
		snapshot.Owned.Hat_Pumpkin = true
		snapshot.Equipped = snapshot.Equipped or {}
		snapshot.Equipped.Hat = ""
		__fire("ProfileData", snapshot)
	end
	GameState.SetJSON("Event", party)
	task.wait(1.2)
	eventChecks.chip = chipText()
	eventChecks.lookDuring = look()
	step = "Event screen"
	State.OpenScreen:Fire("Event")
	task.wait(1.2)
	snap("Event")
	party.DoubleCoins, party.DoubleEndsAt = true, now + 86400 + 4 * 3600 + 120
	GameState.SetJSON("Event", party)
	task.wait(1.2)
	snap("Event double")
	eventChecks.chipDouble = chipText()
	-- The Shop's Victory tab: the event's BAT BURST card says where it's from and the candy it takes.
	State.OpenScreen:Fire("Shop", "Victory")
	task.wait(1.2)
	snap("Shop event")
	-- The Hats tab: the PUMPKIN HAT, owned, with its Equip.
	State.OpenScreen:Fire("Shop", "Hat")
	task.wait(1.2)
	snap("Shop hats")
	pcall(__require("Client/UI/Modal").CloseAll)
	-- The Rewards screen: the hat beside the road, with EQUIP.
	State.OpenScreen:Fire("Rewards", "Road")
	task.wait(1.2)
	snap("Rewards hat")
	pcall(__require("Client/UI/Modal").CloseAll)
	-- The party over: nothing on (double coins never come on their own), so no chip and the lobby's
	-- light exactly as it was.
	GameState.Set("Event", "")
	task.wait(1.2)
	eventChecks.chipAfterParty = chipText()
	eventChecks.lookAfter = look()
	party.DoubleCoins, party.DoubleEndsAt = false, 0
	GameState.SetJSON("Event", party)
	-- A round pays 2 candy (the profile comes with its results): nothing on the results card, then
	-- "+2 CANDY" on the chip once back in the lobby.
	local phaseBefore = GameState.Get("Phase")
	GameState.Set("Phase", "Results")
	if okSnap then
		snapshot.Events.Halloween2026.Candy = 64
		__fire("ProfileData", snapshot)
	end
	task.wait(0.5)
	eventChecks.chipDuringResults = chipText()
	GameState.Set("Phase", "Cleanup")
	task.wait(1.6)
	eventChecks.chipBackInLobby = chipText()
	task.wait(3.2)
	eventChecks.chipAfterPop = chipText()
	GameState.Set("Phase", phaseBefore)
	task.wait(0.3)
end

-- 3h. Every shop tab, at the top and scrolled to the end, where the dearest items are ("Shop
-- Trail", "Shop Trail end", ...; the second shop pass, owner: "Yes lets add more items after
-- everything else is finished").
for _, tab in Cosmetics.ShopTabs do
	step = "Shop tab " .. tab.Slot
	State.OpenScreen:Fire("Shop", tab.Slot)
	task.wait(1)
	snap("Shop " .. tab.Slot)
	local shopModal = __playerGui:FindFirstChild("ShopModal", true)
	local grid = nil
	if shopModal then
		for _, descendant in shopModal:GetDescendants() do
			if descendant:IsA("ScrollingFrame") and descendant:FindFirstChildOfClass("UIGridLayout") then
				grid = descendant
			end
		end
	end
	if grid then
		-- Off the end: Roblox (and ui_render.py) keep it inside the canvas, so this is the bottom
		-- whatever size the snapshot is laid out at.
		grid.CanvasPosition = Vector2.new(0, 100000)
		grid:SetAttribute("PP_ScrollToEnd", true) -- gui_dump.luau: the end on every screen size
		task.wait(0.3)
		snap("Shop " .. tab.Slot .. " end")
		grid:SetAttribute("PP_ScrollToEnd", nil)
	else
		__note("Shop tab " .. tab.Slot .. ": no item grid found")
	end
	local Modal = __require("Client/UI/Modal")
	if Modal.CloseAll then
		pcall(Modal.CloseAll)
	end
	task.wait(0.3)
end

-- 3b. Skee-Ball in the lobby's arcade (SkeeBallController): the player takes machine 1, charges the
-- ROLL meter, rolls a ball (its score pops), sees the vote open ("SkeeBall voting"), finishes a
-- game (PLAY AGAIN / DONE) and leaves; then starts again and is taken into a round. A stand-in
-- machine, board and ball when the place's lobby is older than this client.
local skeeChecks = {}
--@section SkeeBall
do
	local CollectionService = game:GetService("CollectionService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local machineModel = nil
	for _, tagged in CollectionService:GetTagged("SkeeMachine") do
		if tagged:GetAttribute("SkeeIndex") == 1 then
			machineModel = tagged
		end
	end
	if not machineModel then
		local frame = CFrame.new(60, 0.4, -40) * CFrame.Angles(0, math.rad(-57), 0)
		machineModel = Instance.new("Model")
		machineModel.Name = "ArcadeSkeeMachine"
		local function piece(name, size, offset)
			local part = Instance.new("Part")
			part.Name = name
			part.Anchored = true
			part.Size = size
			part.CFrame = frame * CFrame.new(offset)
			part.Parent = machineModel
			return part
		end
		piece("Cabinet", Vector3.new(5, 3, 14), Vector3.new(0, 1.5, 0))
		piece("Screen", Vector3.new(4.3, 1.5, 0.05), Vector3.new(0, 8.3, 6.375)):AddTag("SkeeScreen")
		piece("Band50", Vector3.new(0.1, 0.8, 0.8), Vector3.new(0, 4.4, 4.2))
		piece("BulbsA", Vector3.new(0.3, 0.3, 0.3), Vector3.new(-1, 11, 6.4))
		piece("BulbsB", Vector3.new(0.3, 0.3, 0.3), Vector3.new(1, 11, 6.4))
		piece("Glow", Vector3.new(0.1, 0.1, 8), Vector3.new(1.6, 3.6, -2.6))
		local standPart = piece("Stand", Vector3.new(3, 5, 2), Vector3.new(0, 2.5, -9))
		standPart:AddTag("SkeeStand")
		Instance.new("ProximityPrompt").Parent = standPart
		machineModel:SetAttribute("SkeeIndex", 1)
		machineModel:SetAttribute("SkeeColor", Color3.fromRGB(64, 196, 255))
		machineModel:SetAttribute("SkeeFrame", frame)
		machineModel.Parent = workspace
		machineModel:AddTag("SkeeMachine")
		skeeChecks.standIn = true
	end
	for key, value in { SkeeUser = 0, SkeeName = "", SkeeScore = 0, SkeeBalls = 0, SkeeState = "Idle", SkeeBest = 0 } do
		machineModel:SetAttribute(key, value)
	end
	if not CollectionService:GetTagged("SkeeBestBoard")[1] then
		local part = Instance.new("Part")
		part.Name = "BestBoard"
		part.Anchored = true
		part.Size = Vector3.new(23, 5.6, 0.1)
		part.CFrame = CFrame.new(70, 16, -48)
		part.Parent = workspace
		part:AddTag("SkeeBestBoard")
	end
	CollectionService:GetTagged("SkeeBestBoard")[1]:SetAttribute(
		"Board",
		'[{"N":"SuperLongDisplayNm20","S":420,"U":7},{"N":"Harness","S":310,"U":1},{"N":"Pancake","S":250,"U":9}]'
	)
	if not ReplicatedStorage:FindFirstChild("ArcadeAssets") then
		local assets = Instance.new("Folder")
		assets.Name = "ArcadeAssets"
		local ball = Instance.new("Model")
		ball.Name = "SkeeBall"
		local part = Instance.new("Part")
		part.Name = "Ball"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.one * 0.72
		part.Anchored = true
		part.CanCollide = false
		part.CFrame = CFrame.new(0, 0.36, 0)
		part.Parent = ball
		ball.PrimaryPart = part
		ball.Parent = assets
		assets.Parent = ReplicatedStorage
	end
	step = "SkeeBall"
	task.wait(1.5) -- the controller picks the machine up
	local SkeeBallController = __require("Client/Controllers/SkeeBallController")
	machineModel:SetAttribute("SkeeUser", 1)
	machineModel:SetAttribute("SkeeName", __player.DisplayName)
	machineModel:SetAttribute("SkeeBest", 240)
	machineModel:SetAttribute("SkeeState", "Playing")
	__fire("SkeeBall", "Start", 1, 240)
	task.wait(1.2)
	snap("SkeeBall")
	-- The ROLL meter: one press stops the swinging aim, the next starts the power filling.
	SkeeBallController.PressRoll()
	task.wait(0.35)
	SkeeBallController.PressRoll()
	task.wait(0.45)
	snap("SkeeBall meter")
	skeeChecks.rolled = SkeeBallController.Roll(0.05, 0.5)
	__fire("SkeeBall", "Rolled", 1, 1, 1050, 500, "40", 40)
	task.wait(1.65)
	snap("SkeeBall pop")
	machineModel:SetAttribute("SkeeScore", 40)
	machineModel:SetAttribute("SkeeBalls", 1)
	task.wait(0.6)
	-- The vote opens while you play: the cards keep their places, the play screen keeps clear of
	-- them, and the tip over the score says a round is coming.
	local phaseBefore, endsBefore = GameState.Get("Phase"), GameState.Get("PhaseEndsAt")
	local voteOptions = {}
	for _, def in GameDefinitions.List do
		if #voteOptions < 3 then
			table.insert(voteOptions, { Id = def.Id, Mystery = false })
		end
	end
	table.insert(voteOptions, { Id = voteOptions[1].Id, Mystery = true })
	GameState.SetJSON("VoteOptions", voteOptions)
	GameState.SetJSON("VoteCounts", { 1, 0, 2, 1 })
	GameState.Set("Phase", "Voting")
	GameState.Set("PhaseEndsAt", workspace:GetServerTimeNow() + 12)
	task.wait(1.2)
	snap("SkeeBall voting")
	local skeeHud = __playerGui:FindFirstChild("PartyPanicHUD")
	local skeeHolder = skeeHud and skeeHud:FindFirstChild("SkeeBallControls")
	local skeeTip = skeeHolder and skeeHolder:FindFirstChild("Hint", true)
	skeeChecks.votingTip = if skeeTip and skeeTip.Visible then skeeTip.Text else "(hidden)"
	GameState.Set("Phase", phaseBefore)
	GameState.Set("PhaseEndsAt", endsBefore or 0)
	task.wait(0.3)
	skeeChecks.tipAfterVote = if skeeTip and skeeTip.Visible then skeeTip.Text else "(hidden)"
	machineModel:SetAttribute("SkeeState", "Over")
	__fire("SkeeBall", "Over", 1, 1, 310, 240, true, 2)
	task.wait(1)
	snap("SkeeBall over")
	skeeChecks.sentToServer = table.concat(__sent, ",")
	__fire("SkeeBall", "End", 1, "Left")
	task.wait(0.5)
	local controls = __playerGui:FindFirstChild("PartyPanicHUD") and __playerGui.PartyPanicHUD:FindFirstChild("SkeeBallControls")
	skeeChecks.closed = controls ~= nil and not controls.Visible
	-- A round taking you ends the game on this device at once and hands the camera back, before
	-- the server's word comes.
	machineModel:SetAttribute("SkeeState", "Playing")
	__fire("SkeeBall", "Start", 1, 310)
	task.wait(1)
	local skeeCamera = workspace.CurrentCamera
	skeeChecks.cameraPlaying = skeeCamera.CameraType.Name
	skeeChecks.reopened = controls ~= nil and controls.Visible
	-- The machines' prompts stay off this screen while you play, even when the server turns one on.
	local skeeStand = machineModel:FindFirstChild("Stand")
	local skeePrompt = skeeStand and skeeStand:FindFirstChildOfClass("ProximityPrompt")
	if skeePrompt then
		skeePrompt.Enabled = true
		task.wait(0.1)
		skeeChecks.promptWhilePlaying = skeePrompt.Enabled
	end
	__player:SetAttribute("PP_InRound", true)
	task.wait(0.3)
	skeeChecks.roundClosed = controls ~= nil and not controls.Visible
	skeeChecks.cameraAfterRound = skeeCamera.CameraType.Name
	__player:SetAttribute("PP_InRound", nil)
	for key, value in { SkeeUser = 0, SkeeName = "", SkeeScore = 0, SkeeBalls = 0, SkeeState = "Idle", SkeeBest = 0 } do
		machineModel:SetAttribute(key, value)
	end
	if skeePrompt then
		skeePrompt.Enabled = true -- the server frees the machine
		task.wait(0.1)
		skeeChecks.promptWhenFree = skeePrompt.Enabled
	end

	-- Fingers on the lane (stand-in InputObjects through the shimmed UserInputService). A drag, with
	-- another finger touching and lifting meanwhile: only the drag's own finger ends it, and the
	-- roll it makes is the one its own positions give (SkeeBallView.Drag).
	machineModel:SetAttribute("SkeeUser", 1)
	machineModel:SetAttribute("SkeeState", "Playing")
	__fire("SkeeBall", "Start", 1, 310)
	task.wait(1)
	local SkeeBallView = __require("Shared/Logic/SkeeBallView")
	local viewport = workspace.CurrentCamera.ViewportSize
	local inputKind = if __touchMode then Enum.UserInputType.Touch else Enum.UserInputType.MouseButton1
	local function finger(kind, x, y)
		return {
			UserInputType = kind,
			UserInputState = Enum.UserInputState.Begin,
			KeyCode = Enum.KeyCode.Unknown,
			Position = Vector3.new(x * viewport.X, y * viewport.Y, 0),
			Delta = Vector3.zero,
		}
	end
	local function move(input, x, y)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- A mouse drag moves with MouseMovement inputs, and ends with the button's own.
			__inputChanged:Fire(finger(Enum.UserInputType.MouseMovement, x, y), false)
		else
			input.Position = Vector3.new(x * viewport.X, y * viewport.Y, 0)
			input.UserInputState = Enum.UserInputState.Change
			__inputChanged:Fire(input, false)
		end
	end
	local sentBefore = #__skeeSent
	local drag = finger(inputKind, 0.5, 0.3)
	__inputBegan:Fire(drag, false)
	move(drag, 0.45, 0.33)
	skeeChecks.dragFollows = SkeeBallController.Status().Dragging
	if __touchMode then
		-- A second thumb brushes the screen low on the left and lifts.
		local thumb = finger(Enum.UserInputType.Touch, 0.1, 0.9)
		__inputBegan:Fire(thumb, false)
		thumb.UserInputState = Enum.UserInputState.End
		__inputEnded:Fire(thumb, false)
		skeeChecks.otherFingerIgnored = SkeeBallController.Status().Dragging and #__skeeSent == sentBefore
	end
	drag.UserInputState = Enum.UserInputState.End
	__inputEnded:Fire(drag, false)
	task.wait(0.2)
	local rollSent = __skeeSent[#__skeeSent]
	local wantAim, wantPower = SkeeBallView.Drag(
		0.5 * viewport.X,
		0.3 * viewport.Y,
		0.45 * viewport.X,
		0.33 * viewport.Y,
		viewport.X,
		viewport.Y,
		viewport.Y
	)
	skeeChecks.dragRoll = if rollSent and rollSent[1] == "Roll"
		then string.format("ball %d aim %.3f power %.3f (want %.3f %.3f)", rollSent[2], rollSent[3], rollSent[4], wantAim, wantPower)
		else "(no roll sent)"
	skeeChecks.dragRollMatches = rollSent ~= nil
		and rollSent[1] == "Roll"
		and math.abs(rollSent[3] - wantAim) < 0.002
		and math.abs(rollSent[4] - wantPower) < 0.002
	-- The server refuses that ball ("Sync": none count): the device puts it back.
	local rolledBefore = SkeeBallController.Status().Rolled
	__fire("SkeeBall", "Sync", 1, 0)
	task.wait(0.3)
	snap("SkeeBall roll again")
	local skeePop = skeeHud and skeeHud:FindFirstChild("SkeeBallPop")
	skeeChecks.syncPutBack = string.format(
		"rolled %d -> %d, pop %q",
		rolledBefore,
		SkeeBallController.Status().Rolled,
		if skeePop and skeePop.Visible then skeePop.Text else "(none)"
	)
	skeeChecks.syncOk = rolledBefore == 1 and SkeeBallController.Status().Rolled == 0
	-- Someone hops into your lane: they fade on your screen while you play, and come back when
	-- they step off (or when you stop playing).
	local intruder = Instance.new("Model")
	intruder.Name = "LaneIntruder"
	local intruderRoot = Instance.new("Part")
	intruderRoot.Name = "HumanoidRootPart"
	intruderRoot.Anchored = true
	intruderRoot.CanCollide = false
	intruderRoot.Size = Vector3.new(2, 2, 1)
	intruderRoot.CFrame = machineModel:GetAttribute("SkeeFrame") * CFrame.new(0, 5, -2)
	intruderRoot.Parent = intruder
	Instance.new("Humanoid").Parent = intruder
	intruder.Parent = workspace
	task.wait(0.5)
	local fadedInLane = intruderRoot.LocalTransparencyModifier
	intruderRoot.CFrame = machineModel:GetAttribute("SkeeFrame") * CFrame.new(14, 5, -2)
	task.wait(0.5)
	skeeChecks.laneIntruder = string.format("in the lane %.2f, stepped off %.2f", fadedInLane, intruderRoot.LocalTransparencyModifier)
	skeeChecks.laneIntruderOk = fadedInLane > 0.5 and intruderRoot.LocalTransparencyModifier == 0
	intruder:Destroy()
	-- A round runs while you roll (sitting it out): the round's standings show on the left, the
	-- controls keep clear of them.
	__player:SetAttribute("PP_SitOut", true)
	local phaseNow = GameState.Get("Phase")
	GameState.Set("Phase", "InRound")
	GameState.Set("PhaseEndsAt", workspace:GetServerTimeNow() + 60)
	task.wait(1.2)
	snap("SkeeBall in a round")
	GameState.Set("Phase", phaseNow)
	GameState.Set("PhaseEndsAt", 0)
	__player:SetAttribute("PP_SitOut", nil)
	__fire("SkeeBall", "End", 1, "Left")
	task.wait(0.3)
	for key, value in { SkeeUser = 0, SkeeName = "", SkeeScore = 0, SkeeBalls = 0, SkeeState = "Idle", SkeeBest = 0 } do
		machineModel:SetAttribute(key, value)
	end
end
--@end SkeeBall

-- 3c. The weekly leaderboard (HallOfFameController): this week's board and last week's top three
-- with long names, the player 14th with 35 points, so its chip is in the lobby's row from here on,
-- and the THIS WEEK window the chip opens ("Weekly").
do
	local week = __require("Shared/Logic/DailyLogic").WeekNumber(os.time())
	local top, last = {}, {}
	for index = 1, 10 do
		local name = if index % 2 == 1 then "SuperLongDisplayNm20" else "Captain Waffles"
		table.insert(top, { UserId = 200 + index, Name = name, Points = 1250 - index * 37 })
	end
	for index = 1, 3 do
		table.insert(last, { UserId = 300 + index, Name = "SuperLongDisplayNm20", Points = 2400 - index * 300 })
	end
	GameState.SetJSON("HallOfFame", { Week = week, LastWeek = last, Top = top })
	__player:SetAttribute("PP_WeeklyRank", 14)
	if okSnap then
		snapshot.Weekly = { Week = week, Points = 35 }
		__fire("ProfileData", snapshot)
	end
	task.wait(0.5)
	-- Phones: the row as a player who has finished the first-join tips sees it (this run's player is
	-- new, so everywhere else the tip has the row's spot): the tip put away for one snapshot.
	local hud = __playerGui:FindFirstChild("PartyPanicHUD")
	local tip = hud and hud:FindFirstChild("Onboarding", true)
	if __touchMode and tip and tip.Visible then
		tip.Visible = false
		hud:SetAttribute("PP_TipShowing", false)
		task.wait(1)
		snap("Weekly row")
		tip.Visible = true
		hud:SetAttribute("PP_TipShowing", true)
		task.wait(0.3)
	end
	step = "OpenScreen Weekly"
	State.OpenScreen:Fire("Weekly")
	task.wait(1)
	snap("Weekly")
	pcall(__require("Client/UI/Modal").CloseAll)
	task.wait(0.3)
end

-- 3d. The crate season (Controllers/CrateController, Crates/*): a player 241 crates in, with 12
-- crates and 7 keys, six of the 23 items found, on the Top Unboxers board at 48th; the window's
-- tabs ("Crates", "Crates Collection", "Crates Top", "Crates Odds", "Crates Keys", a pet's details
-- in the collection: "Crates Item", the key shop's gift picker: "Crates Gift", and the key shop for a player Roblox restricts: "Crates Keys
-- locked"), a pet banner FIRST IN THE WORLD and the
-- title's ("Crate banner"), keys given ("Crate gift"), the player's own opening over their head and
-- its prize card ("Crate prize"), Open 5's card ("Crate prize 5") and the season's welcome
-- ("Crate welcome", "Crate welcome card"). The result's "crateChecks" says what the chip read.
do
	local Seasons = require(Shared.Seasons)
	local season = Seasons.CurrentSeason()
	local DailyLogicModule = __require("Shared/Logic/DailyLogic")
	local today = DailyLogicModule.DayNumber(os.time())
	local week = DailyLogicModule.WeekNumber(os.time())
	local found = { "Pet_HarvestOwl", "Hat_LeafCrown", "Aura_LeafWhirl", "Trail_Embers", "Elim_CrowScatter", "Victory_Bonfire" }
	local foundMap = {}
	for index, id in found do
		foundMap[id] = { Crate = 20 + index * 31, Day = today - 6 + index }
	end
	local checks = {}
	if okSnap then
		snapshot.Keys = 7
		snapshot.Crates = { Season = season.Id, Count = 12 }
		snapshot.Seasons = {
			[season.Id] = { Earned = 253, Opened = 241, Coins = 3100, Meter = 77, Week = week, WeekOpened = 40, Found = foundMap },
		}
		snapshot.CrateFlags = { StarterKeys = true, Welcome = season.Id, DailyKeyDay = 0, StarterPack = false, Bought = 0 }
		for _, id in found do
			snapshot.Owned[id] = true
		end
		snapshot.Equipped.Pet = "Pet_HarvestOwl"
		__fire("ProfileData", snapshot)
	end
	local rows = {}
	for index = 1, 10 do
		table.insert(rows, {
			UserId = 400 + index,
			Name = if index % 2 == 1 then "SuperLongDisplayNm20" else "LeafPileLeo",
			Opened = 1300 - index * 97,
		})
	end
	GameState.SetJSON("CrateBoard", {
		Season = season.Id,
		Week = week,
		Top = rows,
		WeekTop = rows,
		Server = { { UserId = __player.UserId, Name = __player.DisplayName, Opened = 12 } },
		Firsts = { Pet_HarvestOwl = { UserId = 401, Name = "SuperLongDisplayNm20", Day = today - 2 } },
	})
	GameState.SetJSON("KeyShop", {
		Packs = {
			{ Key = "Keys1", Keys = 1, Price = 25, Gift = true },
			{ Key = "Keys5", Keys = 5, Price = 99, Gift = true, Badge = "POPULAR" },
			{ Key = "Keys15", Keys = 15, Price = 249, Gift = true, Badge = "BEST VALUE" },
			{ Key = "Keys40", Keys = 40, Price = 549, Gift = true },
		},
		Starter = { Key = "Starter", Keys = 5, Price = 79, Item = season.Starter },
	})
	__player:SetAttribute("PP_CrateRank", 48)
	__player:SetAttribute("PP_CrateWeekRank", 12)
	__player:SetAttribute("PP_KeysLocked", false)
	task.wait(0.6)
	local ribbonChip = nil
	local hud = __playerGui:FindFirstChild("PartyPanicHUD")
	for _, item in (if hud then hud:GetDescendants() else {}) do
		if item:IsA("TextButton") and string.find(item.Text, "🔑", 1, true) then
			ribbonChip = item.Text
		end
	end
	checks.chip = ribbonChip or "(not in the row)"
	for _, tab in { "Crates", "Collection", "Top", "Odds", "Keys" } do
		step = "OpenScreen Crates " .. tab
		State.OpenScreen:Fire("Crates", tab)
		task.wait(0.8)
		snap(if tab == "Crates" then "Crates" else "Crates " .. tab)
	end
	step = "Crates Item"
	__require("Client/Crates/CrateMenu").ShowItem("Pet_HarvestOwl")
	task.wait(0.6)
	snap("Crates Item")
	step = "Crates Gift"
	__require("Client/Crates/CrateMenu").ShowGift("Keys5")
	task.wait(0.6)
	snap("Crates Gift")
	pcall(__require("Client/UI/Modal").CloseAll) -- (closing the window puts the picker away)
	__player:SetAttribute("PP_KeysLocked", true)
	State.OpenScreen:Fire("Crates", "Keys")
	task.wait(0.4)
	snap("Crates Keys locked")
	__player:SetAttribute("PP_KeysLocked", false)
	pcall(__require("Client/UI/Modal").CloseAll)
	task.wait(0.3)
	step = "Crate banner"
	__fire("Crate", "Banner", { Name = "SuperLongDisplayNm20", UserId = 401, Item = "Pet_LanternWisp", Tier = "Pet", Season = season.Id, First = true })
	__fire("Crate", "Banner", { Name = "LeafPileLeo", UserId = 402, Item = season.Title, Tier = "Title", Season = season.Id, Elsewhere = true })
	task.wait(1)
	snap("Crate banner")
	task.wait(6.5)
	step = "Crate gift"
	__fire("Crate", "Gift", { Keys = 4, Reason = "PartyCup", Detail = "Place 1" })
	task.wait(1)
	snap("Crate gift")
	task.wait(4)
	step = "Crate prize"
	local now = workspace:GetServerTimeNow()
	__fire("Crate", "Show", {
		Id = 1, UserId = __player.UserId, Name = __player.DisplayName, Altar = 0, Season = season.Id, At = now,
		Duration = 5.2, RevealAt = 3.4, Friend = false, Meter = 0,
		Results = { { Tier = "Pet", Item = "Pet_EmberStag", Coins = 0, Jackpot = false, Guaranteed = true, Crate = 242 } },
	})
	task.wait(3.9)
	snap("Crate prize")
	task.wait(5)
	step = "Crate prize 5"
	local five = {}
	for index, tier in { "Coins", "Effect", "Coins", "Hat", "Coins" } do
		table.insert(five, {
			Tier = tier,
			Item = if tier == "Effect" then "Trail_WispSteps" elseif tier == "Hat" then "Hat_CrescentMoon" else nil,
			Coins = if tier == "Coins" then index * 10 else 0,
			Jackpot = false,
			Guaranteed = false,
			Crate = 242 + index,
		})
	end
	__fire("Crate", "Show", {
		Id = 2, UserId = __player.UserId, Name = __player.DisplayName, Altar = 0, Season = season.Id,
		At = workspace:GetServerTimeNow(), Duration = 6.6, RevealAt = 4.4, Friend = true, Meter = 12, Results = five,
	})
	task.wait(4.9)
	snap("Crate prize 5")
	task.wait(6)
	step = "Crate welcome"
	if okSnap then
		snapshot.CrateFlags.Welcome = ""
		snapshot.TutorialDone = true
		GameState.Set("Phase", "Intermission")
		__fire("ProfileData", snapshot)
	end
	task.wait(3)
	snap("Crate welcome")
	task.wait(4)
	snap("Crate welcome card")
	local welcome = __playerGui:FindFirstChild("PartyPanicCrates")
	checks.welcome = welcome ~= nil and welcome:FindFirstChild("Welcome") ~= nil
	local card = welcome and welcome:FindFirstChild("Welcome")
	if card then
		card:Destroy() -- (LATER, as far as the rest of the run is concerned)
	end
	if okSnap then
		snapshot.CrateFlags.Welcome = season.Id
		__fire("ProfileData", snapshot)
	end
	__crateChecks = checks
	task.wait(0.5)
end

-- 4. A whole round, phase by phase, with three toasts on screen in the lobby. The vote shows the
-- fullest cards: the two longest names and the longest objective (that game is the one played).
-- The stand-in players play it (round attributes, as RoundContext sets them), with the stand-in
-- bots if there are any (--bots N).
local ids = {}
for _, def in GameDefinitions.List do
	table.insert(ids, def.Id)
end
table.sort(ids, function(a, b)
	return #GameDefinitions.Get(a).Objective > #GameDefinitions.Get(b).Objective
end)
local byName = table.clone(ids)
table.sort(byName, function(a, b)
	local la, lb = utf8.len(GameDefinitions.Get(a).Name) or 0, utf8.len(GameDefinitions.Get(b).Name) or 0
	return if la == lb then a < b else la > lb
end)
local longNames = {}
for _, id in byName do
	if id ~= ids[1] and #longNames < 2 then
		table.insert(longNames, id)
	end
end
__uiScaleFor = __require("Client/UI/UIKit").ScaleFor
__fire("Notify", "Daily gift ready! Open 📜 Quests to claim it.", "reward", 6)
__fire("Notify", "Bubbles joined the party", "info", 6)
__fire("Notify", "Not enough coins yet - play a round to earn more!", "warning", 6)

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
-- The stand-in players and every bot still here.
local function everyone()
	local list = table.clone(__players)
	for _, bot in bots do
		if bot.info.Parent then
			table.insert(list, bot.info)
		end
	end
	return list
end
-- The standings rows as they read on screen (a row is a title label, or a name and a score).
local function boardRows()
	local hud = __playerGui:FindFirstChild("PartyPanicHUD")
	-- (Phones: inside its tap area, RoundController's "Standings".)
	local tapArea = hud and hud:FindFirstChild("Standings")
	local board = hud and (hud:FindFirstChild("Leaderboard") or (tapArea and tapArea:FindFirstChild("Leaderboard")))
	local rows = {}
	for _, child in if board then board:GetChildren() else {} do
		if child:IsA("TextLabel") or child:IsA("Frame") then
			table.insert(rows, child)
		end
	end
	table.sort(rows, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local texts = {}
	for _, row in rows do
		if row:IsA("TextLabel") then
			table.insert(texts, row.Text)
		else
			local parts = {}
			for _, label in row:GetChildren() do
				if label:IsA("TextLabel") then
					table.insert(parts, label.Text)
				end
			end
			table.insert(texts, table.concat(parts, "  ·  "))
		end
	end
	return texts
end

phase("Intermission", 20)
-- A level up with two road rewards, a first level up, then a career milestone (CelebrationController
-- shows them in the lobby), and someone's "Lv 12!" pop over their head.
do
	local Celebrations = __require("Client/Controllers/CelebrationController")
	for _, case in {
		{
			name = "LevelUp",
			payload = { Kind = "LevelUp", Level = 10, From = 9, Coins = 15, Items = { "Trail_Starry", "Title_Pro" } },
		},
		{ name = "LevelUp2", payload = { Kind = "LevelUp", Level = 2, From = 1, Coins = 3, Items = { "Emote_Balloons" } } },
		{ name = "Milestone", payload = { Kind = "Milestone", Coins = 0, Items = { "Title_Veteran" } } },
		{
			name = "Welcome",
			payload = {
				Kind = "Welcome",
				Coins = 0,
				Items = { "Emote_Balloons", "Trail_Bubblegum", "Elim_Ghost", "Title_Regular" },
			},
		},
	} do
		step = "celebration " .. case.name
		__fire("Celebrate", case.payload)
		task.wait(1.6) -- the rewards are revealed one by one
		snap(case.name)
		Celebrations.Dismiss()
		task.wait(0.5)
	end
	if bots[1] and bots[1].rig then
		__fire("LevelPop", bots[1].rig, 12)
	end
	__fire("LevelPop", workspace, 3) -- no head: nothing happens
end
-- Medals (MedalController): the player has a few; a medal won just before the vote waits it out,
-- shows in the lobby ("Medal"), steps aside for a level-up card and comes back; several make one
-- card; the ones a returning player had already earned make one card ("Medals earlier"); the
-- Rewards screen's MEDALS tab ("Rewards Medals"); the medal wall lit for this player (stand-in
-- slots when the place's lobby is older than this client).
local medalChecks = {}
do
	local CollectionService = game:GetService("CollectionService")
	local MedalCards = __require("Client/Controllers/MedalController")
	local Celebrations = __require("Client/Controllers/CelebrationController")
	local function card()
		local layer = __playerGui:FindFirstChild("PartyPanicMedals")
		local shown = layer and layer:FindFirstChild("MedalCard")
		local texts = {}
		for _, item in if shown then shown:GetDescendants() else {} do
			if (item:IsA("TextLabel") or item:IsA("TextButton")) and item.Text ~= "" then
				table.insert(texts, item.Text)
			end
		end
		return if shown then table.concat(texts, " | ") else "none"
	end
	if #CollectionService:GetTagged("MedalSlot") == 0 then
		medalChecks.wallStandIn = true
		for index, id in { "FirstWin", "WinSpleef" } do
			local model = Instance.new("Model")
			model.Name = "Medal_" .. id
			local disc = Instance.new("Part")
			disc.Name = "Disc"
			disc.Shape = Enum.PartType.Cylinder
			disc.Anchored = true
			disc.Size = Vector3.new(0.24, 1.44, 1.44)
			disc.CFrame = CFrame.new(-60 + index * 2, 6, 24)
			disc.Parent = model
			local ribbon = disc:Clone()
			ribbon.Name = "Ribbon"
			ribbon.Shape = Enum.PartType.Block
			ribbon.Size = Vector3.new(0.5, 0.9, 0.05)
			ribbon.Parent = model
			model:SetAttribute("MedalId", id)
			model.Parent = workspace
			model:AddTag("MedalSlot")
		end
		local plaque = Instance.new("Part")
		plaque.Name = "MedalCount"
		plaque.Anchored = true
		plaque.Size = Vector3.new(9, 0.7, 0.1)
		plaque.Parent = workspace
		plaque:AddTag("MedalCount")
	end
	local today = math.floor(os.time() / 86400)
	snapshot.Medals = { FirstWin = today - 40, TenWins = today - 3, CupChampion = today, WinSpleef = nil, WinFireRope = today - 400, WinHexMeltdown = today }
	__fire("ProfileData", snapshot)
	task.wait(0.8)
	local lit = {}
	for _, model in CollectionService:GetTagged("MedalSlot") do
		local disc = model:FindFirstChild("Disc")
		local id = model:GetAttribute("MedalId")
		if disc and (id == "FirstWin" or id == "WinSpleef") then
			table.insert(lit, `{id}: {disc.Material.Name} {disc.Color:ToHex()}`)
		end
	end
	table.sort(lit)
	medalChecks.wall = table.concat(lit, "; ")
	local plaques = {}
	for _, gui in __playerGui:GetChildren() do
		if gui.Name == "MedalCount" then
			local text = gui:FindFirstChildWhichIsA("TextLabel", true)
			table.insert(plaques, if text then text.Text else "?")
		end
	end
	medalChecks.plaque = table.concat(plaques, " / ")
	step = "medal card"
	GameState.Set("Phase", "Voting")
	GameState.Set("PhaseEndsAt", workspace:GetServerTimeNow() + 12)
	__fire("MedalEarned", "WinFireRope", false)
	task.wait(1.2)
	medalChecks.duringVote = card()
	GameState.Set("Phase", "Intermission")
	GameState.Set("PhaseEndsAt", workspace:GetServerTimeNow() + 20)
	task.wait(1.6)
	medalChecks.backInLobby = card()
	snap("Medal")
	__fire("Celebrate", { Kind = "Milestone", Coins = 0, Items = { "Title_Veteran" } })
	task.wait(0.6)
	medalChecks.levelUpCard = card()
	Celebrations.Dismiss()
	task.wait(1.4)
	medalChecks.afterLevelUpCard = card()
	MedalCards.Dismiss()
	task.wait(0.6)
	for _, id in { "WinHexMeltdown", "EveryGame", "WinSpleef" } do
		__fire("MedalEarned", id, false)
	end
	task.wait(1.2)
	medalChecks.several = card()
	MedalCards.Dismiss()
	task.wait(0.6)
	for _, id in { "FirstWin", "TenWins", "FiftyWins" } do
		__fire("MedalEarned", id, true)
	end
	task.wait(1.2)
	medalChecks.earlier = card()
	snap("Medals earlier")
	MedalCards.Dismiss()
	task.wait(0.4)
	step = "OpenScreen Rewards Medals"
	State.OpenScreen:Fire("Rewards", "Medals")
	task.wait(1)
	snap("Rewards Medals")
	pcall(__require("Client/UI/Modal").CloseAll)
	task.wait(0.3)
	medalChecks.afterAll = card()
	-- The PARTY CUP's final podium (PP_CupPodium) and the results card (PP_ResultsShowing) have the
	-- screen: a medal waits for both to clear.
	GameState.Set("PhaseEndsAt", workspace:GetServerTimeNow() + 20)
	__player:SetAttribute("PP_CupPodium", true)
	__fire("MedalEarned", "CupChampion", false)
	task.wait(1.2)
	medalChecks.duringCupPodium = card()
	__player:SetAttribute("PP_ResultsShowing", true)
	__player:SetAttribute("PP_CupPodium", nil)
	task.wait(1)
	medalChecks.duringResultsCard = card()
	__player:SetAttribute("PP_ResultsShowing", nil)
	task.wait(1.2)
	medalChecks.afterPodiumAndResults = card()
	MedalCards.Dismiss()
	task.wait(0.4)
end
phase("Voting", 12, function()
	GameState.SetJSON("VoteOptions", {
		{ Id = longNames[1], Mystery = false },
		{ Id = ids[1], Mystery = false },
		{ Id = longNames[2], Mystery = false },
		{ Id = ids[1], Mystery = true },
	})
	GameState.SetJSON("VoteCounts", { 1, 0, 2, 1 })
	__player:SetAttribute("PP_Vote", 1)
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
	-- In a team game the server puts the player on a team while the card is up: the card's tab says
	-- which ("YOU'RE ON ◆ YELLOW", the widest colour team).
	local played = GameDefinitions.Get(ids[1])
	if played and played.IsTeam then
		__player:SetAttribute("PP_Team", "Yellow")
	end
end)
task.wait(2) -- Random's reel lands on the game that won
__portals["Preparing, 3s in"] = portalReport()
phase("InRound", 60, function()
	-- Stand-in players: scores spread out and three already out. Bots: scores spread around the
	-- player's, and one bot already out.
	for index, other in __players do
		other:SetAttribute("PP_Alive", index <= 9)
		other:SetAttribute("PP_Score", if #bots > 0 then 5 else 13 - index)
		other:SetAttribute("PP_ScoreText", if index <= 9 then "Alive" else "Out")
	end
	for index, bot in bots do
		bot.info:SetAttribute("PP_Score", (#bots - index) * 3)
		bot.info:SetAttribute("PP_Alive", index ~= 2)
	end
	local survivors = 0
	for _, who in everyone() do
		survivors += if who:GetAttribute("PP_Alive") then 1 else 0
	end
	GameState.Set("Status", `Survivors: {survivors}`)
end)
step = "remotes"
__fire("Notify", "Harness notification", "reward", 2)
__fire("PlayEffect", "Confetti", Vector3.new(0, 5, 0))
__fire("PlayEffect", "Fireworks", Vector3.new(0, 10, 0))
__fire("PlayEffect", "Sparkles", Vector3.new(0, 5, 0), { Color3.new(1, 0, 0) })
__fire("PlaySound", "Pickup")
__fire("Knockback", Vector3.new(10, 20, 0), 0.5)
task.wait(1)

-- Every effect a cosmetic plays (emotes, victory, knockout), all at once, each at its own spot in
-- front of the camera: what each one made (and how big and how long) at its fullest, and that it
-- all cleaned itself up ("effectChecks"; the second shop pass's new effects among them).
step = "cosmetic effects"
local effectChecks = {}
do
	local EffectsController = __require("Client/Controllers/EffectsController")
	local camera = workspace.CurrentCamera
	local base = if camera then camera.CFrame.Position + camera.CFrame.LookVector * 40 else Vector3.new(0, 20, 0)
	local names, colorsFor = {}, {}
	for _, item in Cosmetics.List do
		if item.Effect and colorsFor[item.Effect] == nil then
			colorsFor[item.Effect] = item.Colors or false
			table.insert(names, item.Effect)
		end
	end
	table.sort(names)
	local before = workspace:FindFirstChild("LocalEffects")
	if before then
		before:ClearAllChildren() -- the remotes' effects just above
	end
	-- A grid of spots 30 studs apart, all near enough to the camera to be drawn (Play skips an
	-- effect over 400 studs away).
	local SPACING = 30
	local spots = {}
	for index, name in names do
		local column, row = (index - 1) % 5 - 2, math.floor((index - 1) / 5) - 2
		spots[name] = base + Vector3.new(column * SPACING, 0, row * SPACING)
		local ok, err = pcall(EffectsController.Play, name, spots[name], colorsFor[name] or nil)
		effectChecks[name] = {
			ok = ok,
			err = if ok then nil else tostring(err),
			parts = 0,
			glowing = 0,
			emitters = 0,
			emoji = 0,
			biggest = 0,
			longest = 0,
		}
	end
	local folder = workspace:FindFirstChild("LocalEffects")
	local function owner(position: Vector3): string?
		local best, bestDistance = nil, math.huge
		for name, spot in spots do
			local distance = Vector2.new(position.X - spot.X, position.Z - spot.Z).Magnitude
			if distance < bestDistance then
				best, bestDistance = name, distance
			end
		end
		return best
	end
	task.wait(0.7) -- the fireworks' last burst is 0.5 s in
	if folder then
		for _, item in folder:GetDescendants() do
			local part = if item:IsA("BasePart") then item else item:FindFirstAncestorWhichIsA("BasePart")
			local name = part and owner(part.Position)
			local check = name and effectChecks[name]
			if not check then
				continue
			end
			if item:IsA("BasePart") then
				check.parts += 1
				if item.Transparency < 1 then
					check.glowing += 1
					check.biggest = math.max(check.biggest, math.floor(item.Size.Magnitude))
				end
			elseif item:IsA("ParticleEmitter") then
				check.emitters += 1
				check.longest = math.max(check.longest, item.Lifetime.Max)
			elseif item:IsA("BillboardGui") then
				check.emoji += 1
			end
		end
	end
	task.wait(4.5)
	effectChecks.leftAfter5s = if folder then #folder:GetChildren() else -1
end

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
end

-- The team pill under the status line (HudController) shows every team in the round with its mark
-- and score: the versus modes' roles and two colour teams (hudChecks.teamPill: what it read and how
-- wide it was, in its own units), then all four colour teams with 3-digit scores, its widest (the
-- snapshot). The player is on one of the teams each time (PP_Team), so the pill marks theirs: "YOU"
-- by its mark and a box round its words (hudChecks: each team's words in order, the boxed one in
-- [brackets]).
step = "team scores"
local hudChecks = { teamPill = {} }
do
	local function pill()
		local hud = __playerGui:FindFirstChild("PartyPanicHUD")
		local frame = hud and hud:FindFirstChild("TeamScores", true)
		local row = frame and frame:FindFirstChild("Row")
		if not row or not frame.Visible then
			return "hidden"
		end
		local parts = {}
		for _, part in row:GetChildren() do
			local words = part:FindFirstChild("Words")
			if part:IsA("Frame") and part.Visible and words then
				table.insert(parts, part)
			end
		end
		table.sort(parts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local shown = {}
		for _, part in parts do
			local text = part.Words.Text
			table.insert(shown, if part.BackgroundTransparency < 1 then `[{text}]` else text)
		end
		return `{table.concat(shown, "  ")}  [{frame.Size.X.Offset} wide]`
	end
	for _, case in
		{
			{ { Sharks = 3, Swimmers = 120 }, "Swimmers" },
			{ { SandKings = 85, Divers = 240 }, "SandKings" },
			{ { Archers = 4, Runners = 7 }, "Archers" },
			{ { Red = 12, Blue = 9 }, "Blue" },
			{ { Red = 100, Blue = 64, Green = 109, Yellow = 7 }, "Green" },
		}
	do
		__player:SetAttribute("PP_Team", case[2])
		GameState.SetJSON("TeamScores", case[1])
		task.wait(0.3)
		table.insert(hudChecks.teamPill, pill())
	end
	task.wait(0.5)
	snap("InRound teams")
	GameState.SetJSON("TeamScores", {})
	__player:SetAttribute("PP_Team", "")
	task.wait(0.1)
	table.insert(hudChecks.teamPill, "after the round: " .. pill())
end

if #bots > 0 then
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
end

-- A quieter round: the menu column behind the ☰ (HudController), the phone standings with just the
-- player and the leader (RoundController), the players-left pill in the banner, the empty status
-- line's room given to the mode HUDs (State.TopHudShift), and the toasts that aren't about the round
-- held back while the player plays (NotificationController). Then the ☰ and the standings tapped
-- ("InRound menu"), and both back as they were 5.5 seconds later.
step = "quiet round"
local okQuiet, quietErr = pcall(function()
	local okHud, Hud = pcall(__require, "Client/Controllers/HudController")
	local okRound, Round = pcall(__require, "Client/Controllers/RoundController")
	local hud = __playerGui:FindFirstChild("PartyPanicHUD")
	local menu = hud and hud:FindFirstChild("Menu")
	local function find(name)
		for _, gui in __playerGui:GetChildren() do
			local found = gui:FindFirstChild(name, true)
			if found then
				return found
			end
		end
		return nil
	end
	local function menuState()
		local toggle = find("MenuToggle")
		local badge = toggle and toggle:FindFirstChild("Badge", true)
		return `column {if menu and menu.Visible then "shown" else "away"}, ☰ {if toggle and toggle.Visible
			then "shown" .. (if badge and badge.Visible then " with !" else "")
			else "hidden"}`
	end
	local function line()
		local row = hud and (hud:FindFirstChild("RoundStatus") or hud:FindFirstChild("PhaseBanner"))
		local status = row and row:FindFirstChild("Status")
		return if status and status:IsA("TextLabel") and status.Visible then `'{status.Text}'` else "hidden"
	end
	local function toastsUp()
		local toasts = __playerGui:FindFirstChild("PartyPanicToasts")
		local texts = {}
		for _, item in if toasts then toasts:GetDescendants() else {} do
			if item.Name == "Toast" and item:IsA("GuiObject") then
				local words = item:FindFirstChildOfClass("TextLabel")
				table.insert(texts, if words then words.Text else "?")
			end
		end
		return texts
	end
	-- The banner's players-left pill (phones: in the top bar row; PC: in the HUD).
	local banner = find("PhaseBanner")
	local count = banner and banner:FindFirstChild("Count", true)
	local countWords = count and count:FindFirstChild("Text")
	local quiet = {
		playing = menuState(),
		countPill = if count and count.Visible and countWords then countWords.Text else "hidden",
		statusLine = line(),
		topHudShift = State.TopHudShift,
		board = boardRows(),
		toastsUp = toastsUp(),
	}
	if okHud and okRound then
		Hud.ToggleMenu()
		Round.ToggleStandings()
		task.wait(0.8)
		quiet.tapped = menuState()
		quiet.boardTapped = boardRows()
		snap("InRound menu")
		task.wait(5.5)
		quiet.later = menuState()
		quiet.boardLater = boardRows()
	else
		__note("quiet round: " .. tostring(Hud) .. " / " .. tostring(Round))
	end
	hudChecks.quiet = quiet
end)
if not okQuiet then
	__note("quiet round checks failed: " .. tostring(quietErr))
end

-- A mode's two action buttons (Kit/Api: beside the jump button on phones) with two toasts up, the
-- first on two lines: on phones the toasts sit above the buttons' row (NotificationController), and
-- back down once the round's HUD is gone (hudChecks.toastsAboveButtons). That HUD's UIKit.AutoScale
-- scales let go of the camera when it's destroyed (hudChecks.autoScalesReleased).
step = "action buttons"
do
	local okApi, Api = pcall(__require, "Client/MiniGames/Kit/Api")
	if okApi then
		local api = Api.new(ids[1])
		api:Button({ Text = "HIT!", Key = Enum.KeyCode.E })
		api:Button({ Text = "PULL", Key = Enum.KeyCode.Q, Color = Color3.fromRGB(255, 92, 170), Slot = 2 })
		api:Hint("Tap HIT! when the bees come")
		local hintSetAt = os.clock()
		__fire("Notify", "🎃 GOLDEN RUSH! Every veggie counts double for the next ten seconds!", "success", 4, "Round")
		__fire("Notify", "Quest complete: Play 3 rounds", "reward", 4)
		task.wait(0.8)
		snap("InRound buttons")
		do
			local hudGui = __playerGui:FindFirstChild("PartyPanicHUD")
			local row = hudGui and hudGui:FindFirstChild("RoundStatus")
			local strip = row and row:FindFirstChild("Callout")
			local stripWords = strip and strip:FindFirstChild("Text")
			local toasts = __playerGui:FindFirstChild("PartyPanicToasts")
			local stack = {}
			for _, item in if toasts then toasts:GetDescendants() else {} do
				if item.Name == "Toast" and item:IsA("GuiObject") then
					local words = item:FindFirstChildOfClass("TextLabel")
					table.insert(stack, if words then words.Text else "?")
				end
			end
			hudChecks.toasts = {
				strip = if strip and strip.Visible and stripWords then stripWords.Text else "hidden",
				stack = stack,
				topHudShift = State.TopHudShift,
			}
		end
		local toasts = __playerGui:FindFirstChild("PartyPanicToasts")
		local area = toasts and toasts:FindFirstChild("ToastArea")
		local function lifted()
			return if area then area:GetAttribute("PP_AboveActions") == true else "no phone toast area (PC)"
		end
		hudChecks.toastsAboveButtons = { whileShown = lifted() }
		-- The hint fades once it has been up 6 seconds.
		task.wait(math.max(0, hintSetAt + 7 - os.clock()))
		local hintLabel = api.Gui:FindFirstChild("Hint", true)
		hudChecks.hintAfter7s = if hintLabel and hintLabel.Visible then "still shown" else "faded"
		local scales, released = 0, 0
		for _, item in api.Gui:GetDescendants() do
			if item:IsA("UIScale") and item:GetAttribute("AutoScale") then
				scales += 1
				item.Destroying:Connect(function()
					released += 1
				end)
			end
		end
		api:Destroy()
		task.wait(0.5)
		hudChecks.toastsAboveButtons.afterTheRound = lifted()
		hudChecks.autoScalesReleased = `{released} of {scales}`
	else
		__note("Kit/Api failed to load: " .. tostring(Api))
	end
end

-- The player is knocked out: the out panel, then spectating (only bots have characters to watch).
step = "Out"
__player:SetAttribute("PP_Alive", false)
task.wait(1.2)
snap("Out")
do
	local toasts = __playerGui:FindFirstChild("PartyPanicToasts")
	local stack = {}
	for _, item in if toasts then toasts:GetDescendants() else {} do
		if item.Name == "Toast" and item:IsA("GuiObject") then
			local words = item:FindFirstChildOfClass("TextLabel")
			table.insert(stack, if words then words.Text else "?")
		end
	end
	local menuFrame = __playerGui.PartyPanicHUD:FindFirstChild("Menu")
	hudChecks.out = {
		toasts = stack,
		menu = if menuFrame and menuFrame.Visible then "column shown" else "column away",
	}
end
local outPanel = __playerGui.PartyPanicHUD:FindFirstChild("OutPanel")
if outPanel then
	outPanel.Visible = false -- what its 👀 Spectate button does
end
step = "Spectate"
State.OpenScreen:Fire("Spectate")
task.wait(1.2)
snap("Spectate")

if #bots > 0 then
	step = "bots spectating"
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

local Config = require(Shared.Config)
phase("Results", 8, function()
	-- Every reward line. Without bots the player won, ahead of 7 stand-in players; with bots a bot
	-- won and the player came second; the third-place bot has left since (no color known).
	local place = if #bots > 0 then 2 else 1
	local labels = {
		Participation = "Played the round",
		TopHalf = "Top half finish",
		Winner = "Winner!",
		PersonalBest = "New personal best",
		FirstWin = "First win today!",
	}
	local lines, coins, xp = {}, 0, 0
	for _, key in { "Participation", "TopHalf", "Winner", "PersonalBest", "FirstWin" } do
		if Config.Rewards[key] and ((key ~= "Winner" and key ~= "FirstWin") or place == 1) then
			local reward = Config.Rewards[key]
			table.insert(lines, { Label = labels[key], Coins = reward.Coins, XP = reward.XP })
			coins += reward.Coins
			xp += reward.XP
		end
	end
	local standings = {}
	local champions = { { Name = __player.DisplayName, UserId = 1, Place = 1 } }
	if #bots > 0 then
		standings = {
			{ Name = bots[1].display, Place = 1, ScoreText = "15 pts", UserId = bots[1].userId },
			{ Name = __player.DisplayName, Place = 2, ScoreText = "12 pts", UserId = 1 },
		}
		for index = 3, math.min(#bots, 8) do
			local bot = bots[index]
			local score = `{12 - index} pts`
			table.insert(standings, { Name = bot.display, Place = index, ScoreText = score, UserId = bot.userId })
		end
		champions = {
			{ Name = bots[1].display, UserId = bots[1].userId, Place = 1 },
			{ Name = __player.DisplayName, UserId = 1, Place = 2 },
		}
		if bots[3] then
			table.insert(champions, { Name = bots[3].display, UserId = bots[3].userId, Place = 3 })
		end
	else
		-- The longest results lines the modes write, beside long names: the result always reads whole
		-- and a name gives way ("..."), like the standings board.
		local longest = {
			"🏊 45 coins • never chomped!", -- SHARK BAIT
			"Yellow 🎂 33 ⭐ 30 • 71 layers", -- CAKE FACTORY
			"Yellow 97% • 14/15 leans", -- BOBSLED RUN
			"Yellow 100% • 22 perfect", -- PUMP & POP
			"Lasted 54s • 120 jumps", -- FIRE ROPE
			"◆ YELLOW 100% • 132 bites", -- EATSA PIZZA
			"🏹 12 tags • +12 boards", -- ARROW AMBUSH
			"💎 DIVERS 1200 • you 450", -- SINKING SANDS
		}
		for index = 1, 8 do
			local other = __players[index]
			table.insert(standings, {
				Name = other.DisplayName,
				UserId = other.UserId,
				Place = index,
				ScoreText = longest[index],
			})
		end
	end
	__fire("RoundResults", {
		-- A win draws the widest headline: "You won SINKING SANDS!  •  Your team won!"
		GameId = if place == 1 then "SinkingSands" else ids[1],
		MyTeam = if place == 1 then "Divers" else nil,
		WinningTeam = if place == 1 then "Divers" else nil,
		Place = place,
		PlayerCount = #__players + #bots,
		ScoreText = if place == 1 then "Last one standing" else "12 pts",
		Lines = lines,
		Coins = coins,
		XP = xp,
		PersonalBest = true,
		FirstWin = place == 1,
		LevelUp = 7, -- the round took the player to a new level
		Standings = standings,
		-- The crate season's crate (Services/CrateService): one more line on the card.
		Crate = { Count = 1, Name = "Hollow Crate", Season = "HollowNight", Total = 13, Keys = 7 },
	})
	GameState.SetJSON("Champions", champions)
	-- PLAY AGAIN? on the card (Services/ReplayService): the people who played vote (bots don't).
	local voters = { __player.UserId }
	for index = 2, math.min(5, #__players) do
		table.insert(voters, __players[index].UserId)
	end
	GameState.SetJSON("ReplayVote", {
		Open = true,
		Game = if place == 1 then "SinkingSands" else ids[1],
		Yes = math.max(0, #voters - 3),
		No = math.min(1, #voters - 1),
		Voters = voters,
		Need = math.floor(#voters / 2) + 1,
		Capped = false,
	})
	-- 👍 / 👎 on the game (Services/RatingService): open for the card's game.
	GameState.SetJSON("Rating", { Open = true, Game = if place == 1 then "SinkingSands" else ids[1] })
end)
-- The player taps PLAY AGAIN (marked, counted), then a card after the most replays in a row (no
-- buttons: a new vote is next). replayChecks: what the strip showed each time; ratingChecks: the
-- 👍 / 👎 pair.
local replayChecks = {}
local ratingChecks = {}
do
	step = "replay vote"
	local function strip(label)
		local overlay = __playerGui:FindFirstChild("PartyPanicOverlay")
		local found = overlay and overlay:FindFirstChild("Replay", true)
		local function text(name)
			local item = found and found:FindFirstChild(name, true)
			if not item or not item:IsA("GuiObject") or not item.Visible then
				return "hidden"
			end
			local title = item:FindFirstChild("Title")
			local count = item:FindFirstChild("Count")
			if title and count then
				return `{title.Text} / {count.Text}`
			end
			return (item :: any).Text
		end
		replayChecks[label] = {
			strip = if found and found.Visible then "shown" else "hidden",
			again = text("PlayAgain"),
			no = text("NoThanks"),
			note = text("Note"),
		}
	end
	-- The 👍 / 👎 pair: shown, its buttons' size, and which one is lit (its gradient's top colour).
	local function thumbs(label)
		local overlay = __playerGui:FindFirstChild("PartyPanicOverlay")
		local row = overlay and overlay:FindFirstChild("Rating", true)
		local function button(name)
			local item = row and row:FindFirstChild(name)
			if not item or not item:IsA("TextButton") then
				return "missing"
			end
			local gradient = item:FindFirstChildOfClass("UIGradient")
			local top = gradient and gradient.Color.Keypoints[1].Value:ToHex() or "?"
			local rim = item:FindFirstChildOfClass("UIStroke")
			local icon = item:FindFirstChild("Icon")
			local text = if icon and icon:IsA("TextLabel") then icon.Text else "no icon"
			return `{text} {item.Size.X.Offset}x{item.Size.Y.Offset} top #{top}{if rim and rim.Thickness > 2 then " LIT" else ""}`
		end
		ratingChecks[label] = {
			row = if row and row:IsA("GuiObject") and row.Visible then "shown" else "hidden",
			up = button("ThumbUp"),
			down = button("ThumbDown"),
		}
	end
	thumbs("open")
	strip("open")
	__player:SetAttribute("PP_Replay", "Yes")
	__player:SetAttribute("PP_Rating", "Up")
	local vote = GameState.GetJSON("ReplayVote")
	vote.Yes += 1
	GameState.SetJSON("ReplayVote", vote)
	task.wait(0.6)
	strip("tappedYes")
	thumbs("up")
	snap("Results replay")
	__player:SetAttribute("PP_Rating", "Down")
	task.wait(0.3)
	thumbs("down")
	snap("Results rated down")
	__player:SetAttribute("PP_Rating", nil)
	GameState.SetJSON("Rating", { Open = false, Game = "" })
	task.wait(0.3)
	thumbs("closed")
	vote.Open, vote.Capped = false, true
	GameState.SetJSON("ReplayVote", vote)
	__player:SetAttribute("PP_Replay", nil)
	task.wait(0.6)
	strip("capped")
	snap("Results replay capped")
	GameState.SetJSON("ReplayVote", { Open = false, Game = "", Voters = {} })
end

if #bots > 0 then
	-- The podium name tags are BillboardGuis in the world; copy them onto a screen to draw them.
	step = "podium"
	task.wait(1)
	local folder = Instance.new("Folder")
	local screen = Instance.new("ScreenGui")
	screen.Name = "PodiumTags"
	screen:SetAttribute("PP_Billboards", true) -- ui_render.py: check the text, not where they sit
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
	snap("Podium", folder)
	botChecks.podium = podium
	botChecks.headshotsAskedFor = __thumbnailIds
end

phase("Cleanup", 3, function()
	for _, who in everyone() do
		who:SetAttribute("PP_InRound", false)
		who:SetAttribute("PP_Alive", false)
	end
end)
-- Back in the lobby the card shows while the last first-join tip is due: on phones the tip steps
-- aside while the card is up and comes back after it, its 8 s counted only while it's on screen
-- (the tips never finish behind the card). tipChecks: what was on screen, and whether the client
-- had told the server the tips were done.
local tipChecks = {}
do
	local function tipPanel()
		local hud = __playerGui:FindFirstChild("PartyPanicHUD")
		local holder = hud and hud:FindFirstChild("Onboarding", true)
		return holder and (holder:FindFirstChild("Tip") or holder)
	end
	local function look(label)
		local celebrate = __playerGui:FindFirstChild("PartyPanicCelebrate")
		local tip = tipPanel()
		local tipText = tip and tip:FindFirstChildWhichIsA("TextLabel", true)
		tipChecks[label] = {
			card = if celebrate and celebrate:FindFirstChild("Celebration") then "shown" else "none",
			tip = if tip and tip.Visible then "shown" else "hidden",
			tipText = if tipText then string.sub(tipText.Text, 1, 60) else nil,
			tutorialDone = table.find(__sent, "TutorialDone") ~= nil,
		}
	end
	-- The round levelled the player up (a new player's first win does). (Fired once the Cleanup
	-- snapshot is taken: a snapshot in the middle of the chips popping in reads as tiny text.)
	__fire("Celebrate", { Kind = "LevelUp", Level = 2, From = 1, Coins = 3, Items = { "Emote_Balloons" } })
	task.wait(0.6)
	look("cardUp")
	task.wait(10) -- the card closes itself after 9 s
	look("afterCard")
end
phase("Waiting", 0)
task.wait(1)

-- 4b. The PARTY CUP (CupController), from the server's attribute (GameState "Cup", as
-- Services/CupService writes it): after round 2 of 5 with the player 5th of eight, the standings
-- for a moment back in the lobby ("Cup moment": the top three and you), the chip in the lobby's row
-- ("Cup chip"), the standings window it opens ("Cup standings"), then a cup's final standings and
-- its podium as the results card's time runs out ("Cup podium": a bot champion with --bots, else
-- the player), closed by the vote. cupChecks: what the chip and the screens showed.
local cupChecks = {}
do
	local CupController = __require("Client/Controllers/CupController")
	-- On phones the lobby's chips and the moment give way to the first-join tip: let it finish.
	for _ = 1, 40 do
		if table.find(__sent, "TutorialDone") then
			break
		end
		task.wait(0.25)
	end
	cupChecks.tutorialDone = table.find(__sent, "TutorialDone") ~= nil
	local others = {}
	for index, other in __players do
		if index > 1 then
			table.insert(others, { other.DisplayName, other.UserId, false })
		end
	end
	for _, bot in bots do
		if bot.info.Parent then
			table.insert(others, { bot.display, bot.userId, true })
		end
	end
	local function standings(myPlace, points)
		local rows, nextOther = {}, 0
		for place = 1, 8 do
			local gain = ({ 10, 8, 6, 5, 4, 3, 2, 1 })[place]
			local who = if place == myPlace then { __player.DisplayName, __player.UserId, false } else nil
			if not who then
				nextOther += 1
				who = others[nextOther]
			end
			if who then
				table.insert(rows, { UserId = who[2], Name = who[1], Points = points[place], IsBot = who[3], Place = place, Gain = gain })
			end
		end
		return rows
	end
	local lastPodium = { Number = 2, Podium = standings(if #bots > 0 then 1 else 3, { 44, 40, 37 }) }
	-- Who wears the crown (a person: with --bots the player won last cup, and loses it to a bot now).
	local champion = if #bots > 0
		then { UserId = __player.UserId, Name = __player.DisplayName, Cup = 2 }
		else { UserId = others[1][2], Name = others[1][1], Cup = 2 }
	local function setPhase(name, seconds)
		GameState.Set("Phase", name)
		GameState.Set("PhaseEndsAt", if seconds > 0 then workspace:GetServerTimeNow() + seconds else 0)
	end
	step = "cup moment"
	setPhase("Results", 3)
	GameState.SetJSON("Cup", {
		Number = 3, Round = 3, Of = 5, Played = 2, Done = false, EndedAt = workspace:GetServerTimeNow(),
		Standings = standings(5, { 18, 16, 14, 12, 11, 9, 6, 4 }), Champion = champion, Last = lastPodium,
	})
	task.wait(1)
	setPhase("Cleanup", 0)
	task.wait(1.4) -- a beat for a level-up card to go first, then it pops in
	snap("Cup moment")
	cupChecks.moment = CupController.Status()
	setPhase("Intermission", 20)
	task.wait(4.6) -- the moment's time
	cupChecks.afterMoment = CupController.Status()
	snap("Cup chip")
	step = "cup standings"
	CupController.OpenStandings()
	task.wait(1)
	snap("Cup standings")
	cupChecks.standings = CupController.Status()
	pcall(__require("Client/UI/Modal").CloseAll)
	task.wait(0.3)
	-- The cup's last round: its final standings come with the results, the podium takes over as the
	-- results card's time runs out, the new cup arrives as it's paid, and the vote closes it.
	step = "cup podium"
	setPhase("InRound", 30)
	local myFinal = if #bots > 0 then 2 else 1
	local final = standings(myFinal, { 46, 41, 37, 30, 26, 21, 17, 12 })
	GameState.SetJSON("Cup", {
		Number = 3, Round = 5, Of = 5, Played = 5, Done = true, EndedAt = workspace:GetServerTimeNow(),
		Standings = final, Champion = champion, Last = lastPodium,
	})
	task.wait(0.5)
	cupChecks.podiumBeforeResults = CupController.Status().Podium
	setPhase("Results", 1.5)
	task.wait(1.7)
	snap("Cup podium")
	cupChecks.podium = CupController.Status()
	setPhase("Cleanup", 0)
	task.wait(0.4)
	local podiumRows = {}
	for index = 1, 3 do
		table.insert(podiumRows, final[index])
	end
	GameState.SetJSON("Cup", {
		Number = 4, Round = 1, Of = 5, Played = 0, Done = false, EndedAt = workspace:GetServerTimeNow(),
		Standings = {}, Champion = if final[1].IsBot then nil else { UserId = final[1].UserId, Name = final[1].Name, Cup = 3 },
		Last = { Number = 3, Podium = podiumRows },
	})
	task.wait(0.5)
	cupChecks.newCup = CupController.Status()
	setPhase("Voting", 12)
	task.wait(0.5)
	cupChecks.atTheVote = CupController.Status()
	setPhase("Waiting", 0)
	task.wait(0.5)
end

-- 4c. Parties (PartyController; owner: "stuff to work on right now is parties."), from the
-- server's attributes (PP_Party, PP_PartySeat, as Services/PartyService sets them) and its GameState
-- "Parties" (each party's name, colour, emblem and streak). The glow-up (owner: "Also make the party
-- system insane. I want it to look super epic."): the player is in Bubbles's TURBO PANCAKES (🔥 4),
-- with another party of two and a full one (the longest name) here, and levels in every prestige
-- colour. Snapshots: the lobby with the 👥 PARTY chip and the squad bar ("Party chip"); xX_Speedy_Xx
-- joining, the PARTY UP! banner ("Party up"); the window as a member ("Party window") and as the
-- leader with the PARTY LOOK ("Party window leader"); an invite card from Captain Waffles of
-- GALACTIC LLAMAS in the lobby ("Party invite") and during the vote ("Party invite voting": on
-- phones the card goes to the top while the vote cards are up at the bottom middle, and the squad
-- bar steps aside for them); then a
-- team round's rules card with the SQUAD card ("Party squad"), and the next round's on a screen too
-- narrow for the full card beside the rules card: the compact one, faces only ("Party squad
-- compact"; the rules card is moved over while the SQUAD card measures its room, then put back);
-- last, the window for someone on their own ("Party window alone"). The card goes under the rules card
-- and comes back with the time the server says it has left; JOIN asks the server and the card goes.
-- partyChecks: what the chip, the window, the squad bar, the banner, the card and the SQUAD card
-- showed each time, and what the leader's PARTY LOOK asked the server.
local partyChecks = {}
do
	local PartyController = __require("Client/Controllers/PartyController")
	local SquadController = __require("Client/Controllers/SquadController")
	local function setPhase(name, seconds)
		GameState.Set("Phase", name)
		GameState.Set("PhaseEndsAt", if seconds > 0 then workspace:GetServerTimeNow() + seconds else 0)
	end
	local function party(player, id, seat)
		if player then
			player:SetAttribute("PP_Party", id)
			player:SetAttribute("PP_PartySeat", seat)
		end
	end
	local byName = {}
	for _, other in __players do
		byName[other.Name] = other
	end
	local speedy, waffles = byName["xX_Speedy_Xx"], byName["Captain Waffles"]
	if not (byName.Bubbles and speedy and waffles) then
		__note("party checks need the stand-in players (run without --bots)")
	end
	-- Levels in every prestige colour (DataService's PP_Level).
	local levels = { Bubbles = 42, ["xX_Speedy_Xx"] = 55, Pancake = 12, NoodleArms = 3, ["Captain Waffles"] = 27,
		Zoomer = 31, Mochi = 8, LavaLarry = 19, SirHopsALot = 64 }
	for name, level in levels do
		if byName[name] then
			byName[name]:SetAttribute("PP_Level", level)
		end
	end
	__player:SetAttribute("PP_Level", 7)
	__player:SetAttribute("PP_Celebrating", false)
	step = "party chip"
	setPhase("Intermission", 20)
	GameState.SetJSON("Parties", {
		["7"] = { Name = "Turbo Pancakes", Color = 1, Emblem = 1, Streak = 4 },
		["8"] = { Name = "Galactic Llamas", Color = 2, Emblem = 3, Streak = 0 },
		["9"] = { Name = "Electric Raccoons", Color = 3, Emblem = 6, Streak = 12 },
	})
	party(byName.Bubbles, 7, 1)
	party(__player, 7, 2)
	party(byName.Pancake, 8, 1)
	party(byName.NoodleArms, 8, 2)
	party(waffles, 8, 3)
	for seat, name in { "Zoomer", "Mochi", "LavaLarry", "SirHopsALot" } do
		party(byName[name], 9, seat)
	end
	if byName.Glitch then
		__fire("Party", "Sent", byName.Glitch.UserId)
	end
	task.wait(1)
	pcall(__require("Client/UI/Modal").CloseAll) -- the cup's podium, if the lobby brought it back
	task.wait(0.5)
	snap("Party chip")
	partyChecks.chip = PartyController.Status()
	partyChecks.squad = SquadController.Status()

	-- xX_Speedy_Xx joins: the server marks them, then says PARTY UP! to everyone in the party.
	step = "party up"
	party(speedy, 7, 3)
	task.wait(0.1)
	__fire("Party", "PartyUp", speedy and speedy.UserId or 102, "xX_Speedy_Xx")
	task.wait(0.9)
	snap("Party up")
	partyChecks.partyUp = SquadController.Status()
	task.wait(3.6)
	partyChecks.afterPartyUp = SquadController.Status()

	step = "party window"
	PartyController.Open()
	task.wait(1.2)
	snap("Party window")
	partyChecks.window = PartyController.Status()
	-- Bubbles hands over: the player leads, with the PARTY LOOK to change.
	party(byName.Bubbles, 7, 2)
	party(__player, 7, 1)
	task.wait(1)
	snap("Party window leader")
	partyChecks.windowLeader = PartyController.Status()
	pcall(__require("Client/UI/Modal").CloseAll)
	task.wait(0.3)

	step = "party invite"
	__fire("Party", "Invited", waffles and waffles.UserId or 105, "Captain Waffles", 20)
	task.wait(1.4)
	snap("Party invite")
	partyChecks.card = PartyController.Status()
	setPhase("Voting", 12)
	task.wait(1)
	snap("Party invite voting")
	partyChecks.cardVoting = PartyController.Status()
	partyChecks.squadVoting = SquadController.Status() -- (phones: the bar steps aside for the vote cards)

	-- A team round: the player, Bubbles and xX_Speedy_Xx on Red; the rules card and the SQUAD card.
	step = "party squad"
	local gameBefore = GameState.Get("GameId")
	GameState.Set("GameId", "PumpAndPop")
	GameState.Set("RoundId", (GameState.Get("RoundId") or 0) + 1)
	for _, who in __players do
		who:SetAttribute("PP_InRound", true)
		who:SetAttribute("PP_Alive", true)
		who:SetAttribute("PP_Team", "")
	end
	setPhase("Preparing", 13)
	task.wait(0.4)
	for index, who in __players do
		local team = if who == __player or who == byName.Bubbles or who == speedy then "Red"
			else (if index % 2 == 0 then "Blue" else "Red")
		who:SetAttribute("PP_Team", team)
	end
	task.wait(1.2)
	snap("Party squad")
	partyChecks.squadCard = SquadController.Status()
	partyChecks.underRulesCard = PartyController.Status()
	-- The next round on a narrower screen: 94 pixels less room beside the rules card (the harness's
	-- screen is 800 wide) makes the SQUAD card the compact one.
	step = "party squad compact"
	local rulesFrame = context.Hud:FindFirstChild("Rules")
	local rulesAt = if rulesFrame then rulesFrame.Position else nil
	setPhase("Cleanup", 0)
	task.wait(0.6)
	GameState.Set("RoundId", (GameState.Get("RoundId") or 0) + 1)
	if rulesFrame and rulesAt then
		rulesFrame.Position = rulesAt + UDim2.fromOffset(-94, 0)
	end
	setPhase("Preparing", 13)
	task.wait(1)
	if rulesFrame and rulesAt then
		rulesFrame.Position = rulesAt
	end
	task.wait(0.3)
	snap("Party squad compact")
	partyChecks.squadCompact = SquadController.Status()
	for _, who in __players do
		who:SetAttribute("PP_InRound", false)
		who:SetAttribute("PP_Alive", false)
		who:SetAttribute("PP_Team", "")
	end
	GameState.Set("GameId", gameBefore or "")
	setPhase("Cleanup", 0)
	__fire("Party", "Invited", waffles and waffles.UserId or 105, "Captain Waffles", 12) -- back in the lobby, 12 s left
	task.wait(0.6)
	partyChecks.backInLobby = PartyController.Status()
	local sentBefore = #__sent
	PartyController.Answer(true)
	task.wait(0.3)
	partyChecks.joinAsked = __sent[sentBefore + 1]
	partyChecks.afterJoin = PartyController.Status()
	for _, other in __players do
		party(other, nil, nil)
	end
	GameState.Set("Parties", "")
	setPhase("Waiting", 0)
	task.wait(0.5)
	partyChecks.squadAfter = SquadController.Status()
	-- On your own: the window before any party ("Party window alone").
	step = "party window alone"
	PartyController.Open()
	task.wait(1.2)
	snap("Party window alone")
	partyChecks.windowAlone = PartyController.Status()
	pcall(__require("Client/UI/Modal").CloseAll)
	task.wait(0.3)
end

-- 5. Sitting out (UI/SitOutSwitch: by the banner, and in Settings). A tap flips the switches at
-- once and asks the server; with no answer they slide back. Then the server's answer (PP_SitOut,
-- as Services/SitOutService sets it) and the screens that change for someone sitting out.
local sitOutChecks = {}
local SitOutSwitch = __require("Client/UI/SitOutSwitch")
-- What each switch says, e.g. "SitOut (shown): 💤 SITTING OUT / tap to play".
local function switches()
	local rows = {}
	for _, item in __playerGui:GetDescendants() do
		if item:IsA("TextButton") and (item.Name == "SitOut" or item.Name == "SitOutSwitch") then
			local pill = item:FindFirstChild("Pill")
			local track = pill and pill:FindFirstChild("Track")
			local knob = track and track:FindFirstChild("Knob")
			local function text(parent, name)
				local label = parent and parent:FindFirstChild(name)
				return if label then label.Text else "?"
			end
			local side = if knob and knob.Position.X.Offset < 10 then "knob left" else "knob right"
			table.insert(
				rows,
				`{item.Name} ({if item.Visible then "shown" else "hidden"}): {text(knob, "Icon")} {text(pill, "Title")} / {text(pill, "Hint")}, {side}`
			)
		end
	end
	table.sort(rows)
	return rows
end
local function hudText(name)
	local hud = __playerGui:FindFirstChild("PartyPanicHUD")
	local found = hud and hud:FindFirstChild(name, true)
	if not found then
		return "missing"
	end
	local visible = found:IsA("GuiObject") and found.Visible
	return (if visible then "shown" else "hidden") .. (if found:IsA("TextLabel") then ": " .. found.Text else "")
end
-- The sit-out lines on screen (under the banner, under the vote cards).
local function statusLines()
	local lines = {}
	for _, gui in __playerGui:GetChildren() do
		for _, item in gui:GetDescendants() do
			if item:IsA("TextLabel") and (item.Text:find("Sitting out", 1, true) or item.Text:find("next round!", 1, true)) then
				local shown, node = true, item
				while node and node ~= gui do
					shown = shown and (not node:IsA("GuiObject") or node.Visible)
					node = node.Parent
				end
				if shown then
					table.insert(lines, item.Text)
				end
			end
		end
	end
	return lines
end

step = "sit out: a tap"
sitOutChecks.before = switches()
local sentBefore = #__sent
SitOutSwitch.Request(true)
task.wait(0.4)
sitOutChecks.afterTap = switches()
sitOutChecks.tapAsked = table.concat(table.move(__sent, sentBefore + 1, #__sent, 1, {}), ", ")
task.wait(2.2) -- the server never answers here: the switches slide back
sitOutChecks.noAnswer = switches()

-- The server's answer, then the lobby, the vote and the lobby when everyone is on a break.
__player:SetAttribute("PP_SitOut", true)
phase("Intermission", 20, nil, "Intermission sitting out")
sitOutChecks.lobby = switches()
phase("Voting", 12, function()
	GameState.SetJSON("VoteOptions", {
		{ Id = longNames[1], Mystery = false },
		{ Id = ids[1], Mystery = false },
		{ Id = longNames[2], Mystery = false },
		{ Id = ids[1], Mystery = true },
	})
	GameState.SetJSON("VoteCounts", { 1, 0, 2, 1 })
	__player:SetAttribute("PP_Vote", 0)
end, "Voting sitting out")
local dimmed = 0
for _, item in __playerGui.PartyPanicHUD:GetDescendants() do
	if item.Name == "Dim" and item:IsA("GuiObject") and item.Visible then
		dimmed += 1
	end
end
sitOutChecks.vote = { note = hudText("SitOutNote"), dimmedCards = dimmed }
phase("Waiting", 0, nil, "Waiting everyone on a break", "Everyone's taking a break!")

-- A round they watch from the lobby: everyone else plays it.
phase("Preparing", 6, function()
	GameState.Set("RoundId", 2)
	for _, who in everyone() do
		local playing = who ~= __player
		who:SetAttribute("PP_InRound", playing)
		who:SetAttribute("PP_Alive", playing)
		who:SetAttribute("PP_Score", 0)
	end
end, "Preparing sitting out")
sitOutChecks.preparing = { rules = hudText("Rules"), switches = switches() }
phase("InRound", 60, function()
	GameState.Set("Status", "Watch the vine: count the fruit before each honeycomb!")
end, "InRound sitting out")
sitOutChecks.inRound = { lines = statusLines(), outPanel = hudText("OutPanel"), switches = switches() }

-- Back in, mid-round: the next round is theirs.
step = "sit out: back in"
__player:SetAttribute("PP_SitOut", false)
task.wait(1.2)
snap("InRound back in")
sitOutChecks.backIn = { lines = statusLines(), switches = switches() }

-- The second switch, in Settings.
step = "sit out: settings"
__player:SetAttribute("PP_SitOut", true)
phase("Cleanup", 3, function()
	for _, who in everyone() do
		who:SetAttribute("PP_InRound", false)
		who:SetAttribute("PP_Alive", false)
	end
end, "Cleanup sitting out")
State.OpenScreen:Fire("Settings")
task.wait(1)
snap("Settings sitting out")
sitOutChecks.settings = switches()
pcall(__require("Client/UI/Modal").CloseAll)
__player:SetAttribute("PP_SitOut", false)
task.wait(0.5)

local guiCount = #__playerGui:GetDescendants()
return game:GetService("HttpService"):JSONEncode({
	ui = __ui,
	uiDefaults = __uiDefaults, -- the values gui_dump.luau left out of the snapshots
	errors = __errors,
	startMs = startTimes,
	sentToServer = __sent,
	soundReports = __soundReports,
	botReports = __botReports,
	botWatch = (function() -- what Controllers/BotWatchController did (rounds watched, reports, a problem)
		local ok, watcher = pcall(__require, "Client/Controllers/BotWatchController")
		return if ok and watcher.Status then watcher.Status() else tostring(watcher)
	end)(),
	guiInstances = guiCount,
	lastStep = step,
	botChecks = if #bots > 0 then botChecks else nil,
	skeeChecks = skeeChecks,
	eventChecks = eventChecks,
	effectChecks = effectChecks,
	hudChecks = hudChecks,
	sitOutChecks = sitOutChecks,
	tipChecks = tipChecks,
	cupChecks = cupChecks,
	partyChecks = partyChecks,
	medalChecks = medalChecks,
	replayChecks = replayChecks,
	ratingChecks = ratingChecks,
	goldChecks = goldChecks,
	crateChecks = __crateChecks,
	textReport = __textReport,
	portals = __portals,
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
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--touch", action="store_true", help="the stand-in client is a phone (touch, no keyboard)")
    parser.add_argument("--rich", action="store_true", help="a well-used profile, to check the layouts at their fullest")
    parser.add_argument("--gold", action="store_true", help="the player owns the GOLD PASS from the start")
    parser.add_argument("--bots", type=int, default=0, help="stand-in bots that play the round with the player")
    parser.add_argument("--sit-out", action="store_true", help="draw the screens of a player sitting out (and the "
                        "playing ones to compare) instead of every screen")
    parser.add_argument("--shots", help="only these snapshots, comma-separated (e.g. Intermission,LevelUp,Rewards): "
                        "a run with every screen at several sizes is over Open Cloud's result cap")
    parser.add_argument("--skip", help="leave these sections (and their controllers) out of the run, comma-separated: "
                        "SkeeBall. The whole client is close to Open Cloud's 1 MiB script cap; a run checking "
                        "something else can make room this way")
    parser.add_argument("--sizes", help="screens to lay the UI out on with the engine (ui_render.py's names or "
                        "groups; default: touch with --touch, else pc; none to skip)")
    args = parser.parse_args()
    gui_dump = (Path(__file__).resolve().parent / "gui_dump.luau").read_text()
    sizes = args.sizes or ("touch" if args.touch else "pc")
    flags = (
        f"__touchMode = {'true' if args.touch else 'false'}\n"
        f"__richMode = {'true' if args.rich else 'false'}\n"
        f"__goldMode = {'true' if args.gold else 'false'}\n"
        f"__botCount = {args.bots}\n"
        f"__sitOutMode = {'true' if args.sit_out else 'false'}\n"
        + (
            "__onlyShots = { " + ", ".join(f'["{name}"] = true' for name in args.shots.split(",")) + " }\n"
            if args.shots
            else "__onlyShots = nil\n"
        )
        + (devices_luau(size_names(sizes)) if sizes != "none" else "")
    )
    out = [flags + gui_dump + PRELUDE + screen_guis()]
    available = {}
    for module, path in module_paths().items():
        body = rewrite(module, path.read_text())
        # Comments and indentation dropped (line numbers stay put): Open Cloud caps a script at 1 MiB,
        # and the whole client with the crate season's screens is over it with them in.
        body = re.sub(r"(?m)^[ \t]*--(?!\[).*$", "", body)
        body = re.sub(r"(?m)^([^\"'`\[\n]*?\S)[ \t]+--(?!\[)[^\n]*$", r"\1", body)
        available[module] = re.sub(r"(?m)[ \t]+$", "", re.sub(r"(?m)^[ \t]+", "", body))
    main_luau = shared_requires(MAIN)
    # Sections left out (--skip): their lines blanked (the rest keep their line numbers), and their
    # controller not started, so its modules aren't bundled.
    for name in (args.skip.split(",") if args.skip else []):
        pattern = re.compile(r"--@section " + re.escape(name) + r"\n.*?--@end " + re.escape(name) + r"\n", re.S)
        if not pattern.search(main_luau):
            sys.exit(f"client_harness: no section {name} to skip")
        main_luau = pattern.sub(lambda m: "\n" * m.group(0).count("\n"), main_luau)
        main_luau = main_luau.replace(f'"{name}Controller", ', "")
    # The run's own script too, the same way (its lines stay where they are, for the error lines).
    main_luau = re.sub(r"(?m)^[ \t]*--(?!\[).*$", "", main_luau)
    main_luau = re.sub(r"(?m)^([^\"'`\[\n]*?\S)[ \t]+--(?!\[)[^\n]*$", r"\1", main_luau)
    main_luau = re.sub(r"(?m)^[ \t]+", "", main_luau)
    # Only what the run can load (tools/checks/bundling.py): the modules this script asks for and
    # everything they reach. A require the bundler can't follow stops the build here.
    try:
        start = bundling.seeds(PRELUDE + "\n" + main_luau, played_game(), available, {"Shared", "Client", "Server"})
        keep = bundling.closure(available, start)
    except bundling.BundleError as err:
        sys.exit(f"client_harness: {err}")
    for module, body in available.items():
        if module in keep:
            out.append(f'__modules["{module}"] = function()')
            out.append(body)
            out.append("end")
    out.append(main_luau)
    sys.stdout.write("\n".join(out))


if __name__ == "__main__":
    main()

-- Party Panic client entry point: builds the UI root and starts every controller.
--
-- ArrivalController keeps a character the server has just placed where it was put until this device
-- has the floor under it (owner: "Friend fell through the floor while loading into pump and pop.").
--
-- BotWatchController tells the server how the bots moved on this screen in each round (owner: "Bots
-- are STILL ruberbanding and floating."): only a real game has physics, so only a real game can show it.
--
-- Once everything has started, it tells the server which kind of device this is, for the analytics
-- (Services/FunnelService; owner: "What information should we collect to gage if players are having
-- fun and staying?"): Console, Phone, Tablet (a touch screen 600 points or more each way) or PC.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local State = require(script.State)
local UIKit = require(script.UI.UIKit)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- One ScreenGui for the whole HUD; modals use a second one so they draw on top. Both keep to the
-- safe area (clear of Roblox's top bar and phone notches); a modal's dim backdrop reaches past it.
local hud = UIKit.new("ScreenGui", {
	Name = "PartyPanicHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 5,
	Parent = playerGui,
})
local overlay = UIKit.new("ScreenGui", {
	Name = "PartyPanicOverlay",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 10,
	Parent = playerGui,
})

pcall(function()
	-- Our own HUD shows coins/level; keep chat and the player list.
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
end)

State.Init()

local Controllers = script.Controllers
local order = {
	"AudioController",
	"NotificationController",
	"EffectsController",
	"PetController", -- the crate season's pets, on every character (Shared/Seasons)
	"AuraController", -- ... and its auras, in the lobby
	"AmbienceController",
	"MovementController",
	"ArrivalController",
	"SceneryCameraController",
	"WorldScreensController",
	"HudController",
	"VoteController",
	"RoundController",
	"ResultsController",
	"ShopController",
	"QuestController",
	"RewardsController", -- after HudController: it adds to the profile chip
	"CelebrationController",
	"GoldPassController", -- the GOLD PASS's UNLOCKED card, and the gold shimmer on name tags
	"TitleController", -- THE HARVESTER's flicker and embers on name tags, and its chat tag
	-- What keeps players coming back.
	"CupController",
	"InviteController",
	"PartyController", -- the PARTY chip, its window, the invite card and the 👥 on name tags
	"SquadController", -- the squad bar, PARTY UP! and the SQUAD card (after PartyController: it opens its window)
	"PartyWorldController", -- party rings, crests and links in the lobby, mates' outlines in rounds
	"MedalController",
	"HallOfFameController",
	"EventController",
	-- The crate season (Shared/Seasons): the lobby's season, then the crates (they use the lobby's wisps).
	"SeasonWorldController",
	"CrateController",
	"EmoteController",
	"SpectateController",
	"OnboardingController",
	"MiniGameController",
	"SkeeBallController",
	"AssetReportController",
	"BotWatchController",
}

local context = { Hud = hud, Overlay = overlay }
for _, name in order do
	local module = Controllers:FindFirstChild(name)
	if not module then
		warn("[PartyPanic] missing controller", name)
		continue
	end
	local ok, controller = pcall(require, module)
	if not ok then
		warn(`[PartyPanic] {name} failed to load: {controller}`)
		continue
	end
	local started, err = pcall(controller.Start, context)
	if not started then
		warn(`[PartyPanic] {name} failed to start: {err}`)
	end
end

-- Which kind of device this is, for the analytics.
pcall(function()
	local kind = "PC"
	if GuiService:IsTenFootInterface() then
		kind = "Console"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local size = workspace.CurrentCamera.ViewportSize
		kind = if math.min(size.X, size.Y) >= 600 then "Tablet" else "Phone"
	end
	require(ReplicatedStorage.Shared.Remotes).Get("Funnel"):FireServer("Device", kind)
end)

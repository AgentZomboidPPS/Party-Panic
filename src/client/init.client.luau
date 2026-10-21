-- Party Panic client entry point: builds the UI root and starts every controller.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

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
	"AmbienceController",
	"MovementController",
	"WorldScreensController",
	"HudController",
	"VoteController",
	"RoundController",
	"ResultsController",
	"ShopController",
	"QuestController",
	"EmoteController",
	"SpectateController",
	"OnboardingController",
	"MiniGameController",
	"SkeeBallController",
	"AssetReportController",
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

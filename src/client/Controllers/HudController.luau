-- Lobby / in-round HUD (design doc §12 "Primary UI surfaces"):
-- profile chip (level, XP, coins), phase banner with timer, side menu, settings window.
-- Kept to the screen edges so chat and the middle of the screen stay clear.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local HudController = {}

local PHASE_ICONS = {
	Waiting = "⏳",
	Intermission = "🎉",
	Voting = "🗳️",
	Preparing = "📋",
	InRound = "🎮",
	Results = "🏆",
	Cleanup = "🏠",
}

local player = Players.LocalPlayer
local badges: { [string]: TextLabel } = {}

local function buildProfileChip(parent: Instance)
	local holder = UIKit.new("Frame", {
		Name = "ProfileChip",
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(310, 130),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.AutoScale(holder)

	local chip = UIKit.Panel({ Size = UDim2.fromOffset(310, 74), CornerRadius = 37, Parent = holder })
	local badge = UIKit.new("Frame", {
		Size = UDim2.fromOffset(62, 62),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = chip,
		Children = {
			UIKit.Round(),
			UIKit.Gradient(Theme.Colors.Yellow, Theme.Colors.Orange),
			UIKit.Stroke(nil, 3, 0.3),
		},
	})
	local levelLabel = UIKit.Label({
		Text = "1",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
		Children = { UIKit.TextStroke(0.2) },
	})
	UIKit.Label({
		Text = player.DisplayName,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(80, 8),
		Size = UDim2.new(1, -96, 0, 24),
		Parent = chip,
	})
	local barBack = UIKit.new("Frame", {
		Position = UDim2.fromOffset(80, 40),
		Size = UDim2.new(1, -100, 0, 18),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = chip,
		Children = { UIKit.Round() },
	})
	local barFill = UIKit.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = barBack,
		Children = { UIKit.Round(), UIKit.Gradient(Theme.Colors.Cyan, Theme.Colors.Green, 0) },
	})
	local xpText = UIKit.Label({
		Text = "",
		TextSize = 14,
		Size = UDim2.fromScale(1, 1),
		Parent = barBack,
		Children = { UIKit.TextStroke(0.3) },
	})

	local coins = UIKit.Panel(
		{ Position = UDim2.fromOffset(0, 82), Size = UDim2.fromOffset(190, 46), CornerRadius = 23, Parent = holder },
		Color3.fromRGB(255, 196, 60),
		Color3.fromRGB(230, 130, 30)
	)
	local coinLabel = UIKit.Label({
		Text = "🪙 0",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		Size = UDim2.fromScale(1, 1),
		Parent = coins,
		Children = { UIKit.TextStroke(0.15) },
	})

	local shown = 0
	local coinValue = Instance.new("NumberValue")
	coinValue.Changed:Connect(function(value)
		coinLabel.Text = "🪙 " .. UIKit.FormatNumber(value)
	end)

	State.ProfileChanged:Connect(function(profile, previous)
		levelLabel.Text = tostring(profile.Level)
		local ratio = if profile.LevelNeed > 0 then profile.LevelXP / profile.LevelNeed else 1
		UIKit.Tween(barFill, 0.4, { Size = UDim2.fromScale(ratio, 1) })
		xpText.Text = if profile.LevelNeed > 0 then `{profile.LevelXP} / {profile.LevelNeed} XP` else "MAX LEVEL"
		if profile.Coins ~= shown then
			shown = profile.Coins
			UIKit.Tween(coinValue, 0.6, { Value = profile.Coins })
			if previous and profile.Coins > previous.Coins then
				UIKit.PopIn(coins, 0.3)
			end
		end
		if previous and profile.Level > previous.Level then
			UIKit.PopIn(badge, 0.5)
		end
	end)
end

local function buildPhaseBanner(parent: Instance)
	local holder = UIKit.new("Frame", {
		Name = "PhaseBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(520, 150),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.AutoScale(holder)
	local banner = UIKit.Panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(520, 70),
		CornerRadius = 35,
		Parent = holder,
	})
	local title = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(28, 0),
		Size = UDim2.new(1, -170, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = banner,
		Children = { UIKit.TextStroke(0.3) },
	})
	local timerPill = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(124, 52),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = banner,
		Children = { UIKit.Round() },
	})
	local timer = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 34,
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Theme.Colors.Yellow,
		Parent = timerPill,
	})
	local status = UIKit.Label({
		Text = "",
		TextSize = 22,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76),
		Size = UDim2.fromOffset(620, 28),
		Parent = holder,
		Children = { UIKit.TextStroke(0.2) },
	})
	local teams = UIKit.Panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.fromOffset(360, 40),
		CornerRadius = 20,
		Visible = false,
		Parent = holder,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local teamsLabel = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		Size = UDim2.fromScale(1, 1),
		Parent = teams,
	})

	local lastWhole = -1
	RunService.Heartbeat:Connect(function()
		local phase = GameState.Get("Phase") or "Waiting"
		local gameId = GameState.Get("GameId")
		local definition = gameId ~= "" and GameDefinitions.Get(gameId)
		local message = GameState.Get("Message") or ""
		local icon = PHASE_ICONS[phase] or "🎉"
		if (phase == "InRound" or phase == "Preparing" or phase == "Results") and definition then
			title.Text = `{definition.Icon} {definition.Name}`
		else
			title.Text = `{icon} {if message ~= "" then message else phase}`
		end
		local left = GameState.TimeLeft()
		timerPill.Visible = GameState.Get("PhaseEndsAt") > 0
		timer.Text = UIKit.FormatTime(left)
		local whole = math.ceil(left)
		-- Urgency: the timer turns red and pulses in the last 10 seconds of a round or vote.
		local urgent = (phase == "InRound" or phase == "Voting") and left > 0 and left <= 10
		timer.TextColor3 = if urgent then Theme.Colors.Red else Theme.Colors.Yellow
		if urgent and whole ~= lastWhole then
			UIKit.PopIn(timerPill, 0.25)
		end
		lastWhole = whole
		status.Text = if phase == "InRound" then GameState.Get("Status") or "" else ""
	end)

	local function refreshTeams()
		local scores = GameState.GetJSON("TeamScores")
		if type(scores) ~= "table" or next(scores) == nil then
			teams.Visible = false
			return
		end
		teams.Visible = true
		teamsLabel.Text = `🔴 {scores.Red or 0}   —   {scores.Blue or 0} 🔵`
	end
	GameState.Changed("TeamScores", refreshTeams)
	refreshTeams()
end

local function menuButton(
	parent: Instance,
	name: string,
	icon: string,
	caption: string,
	order: number,
	top: Color3,
	bottom: Color3
): TextButton
	local button = UIKit.Button({
		Name = name,
		Text = icon,
		TextSize = 36,
		Size = UDim2.fromOffset(74, 74),
		CornerRadius = 24,
		LayoutOrder = order,
		Parent = parent,
	}, function()
		State.OpenScreen:Fire(name)
	end, top, bottom)
	UIKit.Label({
		Text = caption,
		TextSize = 15,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.new(1, 10, 0, 18),
		Parent = button,
		Children = { UIKit.TextStroke(0.1) },
	})
	local badge = UIKit.Label({
		Name = "Badge",
		Text = "!",
		Font = Theme.Fonts.Display,
		TextSize = 20,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Red,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(26, 26),
		Visible = false,
		Parent = button,
		Children = { UIKit.Round() },
	})
	badges[name] = badge
	return button
end

local function buildMenu(parent: Instance)
	local menu = UIKit.new("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(80, 360),
		BackgroundTransparency = 1,
		Parent = parent,
		Children = {
			UIKit.List(Enum.FillDirection.Vertical, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
		},
	})
	UIKit.AutoScale(menu)
	menuButton(menu, "Shop", "🛍️", "Shop", 1, Theme.Colors.Pink, Color3.fromRGB(200, 50, 140))
	menuButton(menu, "Quests", "📜", "Quests", 2, Theme.Colors.Yellow, Theme.Colors.Orange)
	menuButton(menu, "Emotes", "🕺", "Emotes", 3, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
	menuButton(menu, "Settings", "⚙️", "Settings", 4, Theme.Colors.PanelLight, Theme.Colors.PanelDark)

	State.ProfileChanged:Connect(function(profile)
		local claimable = profile.Daily.CanClaim
		badges.Quests.Visible = claimable
	end)
end

local function toggleRow(
	parent: Instance,
	order: number,
	label: string,
	getter: () -> boolean,
	onToggle: (boolean) -> ()
)
	local row = UIKit.new(
		"Frame",
		{ Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent }
	)
	UIKit.Label({
		Text = label,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -150, 1, 0),
		Parent = row,
	})
	local button
	button = UIKit.Button({
		Text = "",
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(130, 50),
		CornerRadius = 25,
		Parent = row,
	}, function()
		onToggle(not getter())
	end, Theme.Colors.Green, Color3.fromRGB(60, 170, 90))
	local function refresh()
		button.Text = if getter() then "ON" else "OFF"
	end
	State.ProfileChanged:Connect(refresh)
	refresh()
end

local function buildSettings(overlay: Instance)
	local modal = Modal.new(overlay, "Settings", "⚙️", Vector2.new(560, 420))
	local list = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = modal.Content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 10) },
	})
	local setSetting = Remotes.Get("SetSetting")
	toggleRow(list, 1, "🎵 Music", function()
		return State.Setting("MusicOn") ~= false
	end, function(value)
		setSetting:FireServer("MusicOn", value)
	end)
	toggleRow(list, 2, "✨ Reduced effects", function()
		return State.Setting("ReducedEffects") == true
	end, function(value)
		setSetting:FireServer("ReducedEffects", value)
	end)
	UIKit.Label({
		Text = "Reduced effects tones down particles, flashes and motion.",
		TextSize = 18,
		TextColor3 = Theme.Colors.TextDim,
		LayoutOrder = 3,
		Parent = list,
	})
	if Config.Monetization.VipGamePassId ~= 0 then
		UIKit.Button(
			{ Text = "💎 Get VIP (cosmetics only)", Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 4, Parent = list },
			function()
				Remotes.Get("PromptVip"):FireServer()
			end,
			Theme.Colors.Yellow,
			Theme.Colors.Orange
		)
	end
	local saveNote =
		UIKit.Label({ Text = "", TextSize = 16, TextColor3 = Theme.Colors.TextDim, LayoutOrder = 5, Parent = list })
	State.ProfileChanged:Connect(function(profile)
		saveNote.Text = if profile.CanSave
			then "Your progress saves automatically."
			else "⚠️ Progress isn't saving this session."
	end)
	return modal
end

function HudController.Start(context)
	buildProfileChip(context.Hud)
	buildPhaseBanner(context.Hud)
	buildMenu(context.Hud)
	local settings = buildSettings(context.Overlay)

	State.OpenScreen:Connect(function(name)
		if name == "Settings" then
			settings:Toggle()
		end
	end)

	-- Lobby prompts that open screens (shop counter, quest board).
	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
		if triggeringPlayer ~= player then
			return
		end
		local action = prompt:GetAttribute("Action")
		if action == "OpenShop" then
			State.OpenScreen:Fire("Shop")
		elseif action == "OpenQuests" then
			State.OpenScreen:Fire("Quests")
		end
	end)

	-- Keyboard shortcuts for desktop players.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
			State.OpenScreen:Fire("Emotes")
		elseif input.KeyCode == Enum.KeyCode.M then
			State.OpenScreen:Fire("Shop")
		elseif input.KeyCode == Enum.KeyCode.J then
			State.OpenScreen:Fire("Quests")
		end
	end)
end

return HudController

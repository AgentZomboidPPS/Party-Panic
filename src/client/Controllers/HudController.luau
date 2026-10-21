-- Lobby / in-round HUD (design doc §12 "Primary UI surfaces"):
-- profile chip (level, XP, coins), phase banner with timer, side menu, settings window.
-- Kept to the screen edges so chat and the middle of the screen stay clear.
-- Phones (owner: "Wtf is this mobile Ui lol"): a compact HUD. The phase banner is one short line
-- with the timer ("VOTE! 0:08") up in Roblox's top bar row, beside its buttons; a small profile
-- pill (level, name, XP) with the coins tucked under it at the top left, which makes way for the
-- standings during a round; the round's status line under the top bar; the menu down the right
-- edge, with 44 pt buttons. Nothing goes in the thumbstick's corner or near the jump button.
-- Tapping the profile chip opens the Rewards screen (owner: "Also we need cool payoffs for players
-- that keep playing the game."); RewardsController adds the next reward beside the coins and colors
-- the level badge for the player's prestige tier.

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
local Teams = require(Shared.Teams)

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
-- Phones: the banner's short words for the phases that have a timer.
local SHORT_TITLES = {
	Intermission = "NEXT VOTE",
	Voting = "VOTE!",
	Results = "RESULTS",
}

local player = Players.LocalPlayer
local badges: { [string]: TextLabel } = {}

-- Phones and tablets without a keyboard: the HUD keeps clear of the thumbstick and jump button.
local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Level, XP bar and coins follow the profile (both layouts).
local function followProfile(
	levelLabel: TextLabel,
	barFill: Frame,
	xpText: TextLabel,
	badge: GuiObject,
	coins: GuiObject,
	setCoins: (number) -> ()
)
	local shown = 0
	local coinValue = Instance.new("NumberValue")
	coinValue.Changed:Connect(setCoins)
	setCoins(0)
	State.ProfileChanged:Connect(function(profile, previous)
		levelLabel.Text = tostring(profile.Level)
		local ratio = if profile.LevelNeed > 0 then profile.LevelXP / profile.LevelNeed else 1
		UIKit.Tween(barFill, 0.4, { Size = UDim2.fromScale(ratio, 1) })
		if profile.LevelNeed <= 0 then
			xpText.Text = "MAX LEVEL"
		elseif isTouch() then
			xpText.Text = `{profile.LevelXP}/{profile.LevelNeed} XP`
		else
			xpText.Text = `{profile.LevelXP} / {profile.LevelNeed} XP`
		end
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

-- The profile chip's holder: a see-through button that opens the Rewards screen.
local function profileHolder(props: { [string]: any }): TextButton
	props.Name = "ProfileChip"
	props.Text = ""
	props.AutoButtonColor = false
	props.BackgroundTransparency = 1
	local holder = UIKit.new("TextButton", props)
	holder.Activated:Connect(function()
		State.OpenScreen:Fire("Rewards")
	end)
	return holder
end

local function buildProfileChip(parent: Instance)
	local width = 310
	local holder = profileHolder({
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(width, 130),
		Parent = parent,
	})
	UIKit.AutoScale(holder)

	local chip = UIKit.Panel({ Size = UDim2.fromOffset(width, 74), CornerRadius = 37, Parent = holder })
	local badge = UIKit.new("Frame", {
		Name = "LevelBadge",
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
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
		Children = { UIKit.TextStroke(0.2) },
	})
	local name = UIKit.Label({
		Text = player.DisplayName,
		TextSize = 20,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(80, 8),
		Size = UDim2.new(1, -96, 0, 24),
		Parent = chip,
	})
	name:SetAttribute("PP_TruncateOk", true) -- a long name ends in "..."
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
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = barBack,
		Children = { UIKit.TextStroke(0.3) },
	})

	local coins = UIKit.Panel({
		Name = "Coins",
		Position = UDim2.fromOffset(0, 82),
		Size = UDim2.fromOffset(200, 46),
		CornerRadius = 23,
		Parent = holder,
	}, Color3.fromRGB(255, 196, 60), Color3.fromRGB(230, 130, 30))
	UIKit.Coin({ Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(30, 30), Parent = coins })
	local coinLabel = UIKit.Label({
		Text = "0",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextWrapped = false,
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.new(1, -56, 1, 0),
		Parent = coins,
		Children = { UIKit.TextStroke(0.15) },
	})
	followProfile(levelLabel, barFill, xpText, badge, coins, function(value)
		coinLabel.Text = UIKit.FormatNumber(value)
	end)
end

-- Phones: a small pill (level badge, name, XP bar) with the coins tucked under it, in the top left
-- corner under Roblox's buttons. During a round the standings take its place (RoundController).
local function buildTouchProfile(parent: Instance)
	local holder = profileHolder({
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.fromOffset(196, 96),
		Parent = parent,
	})
	UIKit.AutoScale(holder)

	local chip = UIKit.Panel({ Size = UDim2.fromOffset(192, 62), CornerRadius = 31, ZIndex = 2, Parent = holder })
	local badge = UIKit.new("Frame", {
		Name = "LevelBadge",
		Size = UDim2.fromOffset(52, 52),
		Position = UDim2.fromOffset(5, 5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = chip,
		Children = {
			UIKit.Round(),
			UIKit.Gradient(Theme.Colors.Yellow, Theme.Colors.Orange),
			UIKit.Stroke(nil, 2, 0.3),
		},
	})
	local levelLabel = UIKit.Label({
		Text = "1",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
		Children = { UIKit.TextStroke(0.2) },
	})
	local name = UIKit.Label({
		Text = player.DisplayName,
		TextSize = 20,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(64, 6),
		Size = UDim2.fromOffset(118, 24),
		Parent = chip,
	})
	name:SetAttribute("PP_TruncateOk", true)
	local barBack = UIKit.new("Frame", {
		Position = UDim2.fromOffset(64, 33),
		Size = UDim2.fromOffset(118, 22),
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
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = barBack,
		Children = { UIKit.TextStroke(0.3) },
	})

	-- The coins: a gold tab under the pill, as wide as the number.
	local coins = UIKit.Panel({
		Name = "Coins",
		Position = UDim2.fromOffset(12, 52),
		Size = UDim2.fromOffset(110, 42),
		CornerRadius = 18,
		ZIndex = 1,
		Parent = holder,
	}, Color3.fromRGB(255, 196, 60), Color3.fromRGB(230, 130, 30))
	UIKit.Coin({ Position = UDim2.fromOffset(10, 14), Size = UDim2.fromOffset(24, 24), Parent = coins })
	local coinLabel = UIKit.Label({
		Text = "0",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(40, 10),
		Size = UDim2.new(1, -46, 0, 32),
		Parent = coins,
		Children = { UIKit.TextStroke(0.15) },
	})
	local function fitCoins()
		local width = UIKit.TextWidth(coinLabel.Text, 24, Theme.Fonts.Display)
		coins.Size = UDim2.fromOffset(math.max(84, math.ceil(width) + 56), 42)
	end
	followProfile(levelLabel, barFill, xpText, badge, coins, function(value)
		coinLabel.Text = UIKit.FormatNumber(value)
		fitCoins()
	end)
	task.delay(3, fitCoins) -- again once the font has surely loaded

	-- The standings use this corner during a round.
	local function refresh()
		holder.Visible = GameState.Get("Phase") ~= "InRound"
	end
	GameState.Changed("Phase", refresh)
	refresh()
end

-- The words, timer and urgency both banners show.
local function bannerTitle(touch: boolean): string
	local phase = GameState.Get("Phase") or "Waiting"
	local gameId = GameState.Get("GameId")
	local definition = gameId ~= "" and GameDefinitions.Get(gameId)
	local message = GameState.Get("Message") or ""
	local icon = PHASE_ICONS[phase] or "🎉"
	if touch and SHORT_TITLES[phase] then
		return `{icon} {SHORT_TITLES[phase]}`
	elseif (phase == "InRound" or phase == "Preparing" or phase == "Results") and definition then
		return `{definition.Icon} {definition.Name}`
	end
	return `{icon} {if message ~= "" then message else phase}`
end

local function followTimer(timerPill: Frame, timer: TextLabel)
	local lastWhole = -1
	RunService.Heartbeat:Connect(function()
		local phase = GameState.Get("Phase") or "Waiting"
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
	end)
end

local function buildPhaseBanner(parent: Instance)
	local width = 520
	local holder = UIKit.new("Frame", {
		Name = "PhaseBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(width, 150),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.AutoScale(holder)
	local banner = UIKit.Panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(width, 70),
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
	title:SetAttribute("PP_Lines", 2) -- PC: a long message ("Waiting for 1 more player...") takes two lines
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
		TextWrapped = false,
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
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = teams,
	})

	followTimer(timerPill, timer)
	RunService.Heartbeat:Connect(function()
		local phase = GameState.Get("Phase") or "Waiting"
		title.Text = bannerTitle(false)
		status.Text = if phase == "InRound" then GameState.Get("Status") or "" else ""
	end)

	local function refreshTeams()
		local scores = GameState.GetJSON("TeamScores")
		if type(scores) ~= "table" or next(scores) == nil then
			teams.Visible = false
			return
		end
		teams.Visible = true
		-- Colour teams: two read "A — B"; with three or four, every team present gets its icon and
		-- score. Versus roles (Archers / Runners, ...): each side's icon and score, in name order.
		local present = {}
		for _, team in Teams.Order do
			if scores[team] ~= nil then
				table.insert(present, `{Teams.Icons[team]} {scores[team]}`)
			end
		end
		if #present > 2 then
			teamsLabel.Text = table.concat(present, "   ")
		elseif #present > 0 then
			teamsLabel.Text = `🔴 {scores.Red or 0}   —   {scores.Blue or 0} 🔵`
		else
			local names = {}
			for name in scores do
				table.insert(names, name)
			end
			table.sort(names)
			local parts = {}
			for index, name in names do
				local icon = Teams.Icons[name] or ""
				table.insert(parts, if index == 1 then `{icon} {scores[name]}` else `{scores[name]} {icon}`)
			end
			teamsLabel.Text = table.concat(parts, "   —   ")
		end
	end
	GameState.Changed("TeamScores", refreshTeams)
	refreshTeams()
end

-- Phones: the banner sits in Roblox's top bar row (its own ScreenGui inside the device's safe area,
-- level with Roblox's 44 pt buttons), centered, one short line as wide as its words.
local TOUCH_BANNER_HEIGHT = 66
local function buildTopBarBanner(hud: Instance)
	local gui = UIKit.new("ScreenGui", {
		Name = "PartyPanicTopBar",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
	})
	-- Clear of the notch and home bar but not of the top bar (set in this order: either property
	-- alone would do it, and the last one set wins).
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = hud.Parent
	local holder = UIKit.new("Frame", {
		Name = "PhaseBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 34), -- Roblox's buttons run from 12 to 55 pt
		Size = UDim2.fromOffset(700, TOUCH_BANNER_HEIGHT),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.AutoScale(holder, 0.8) -- phone size on tablets too, like Roblox's own buttons
	local banner = UIKit.Panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(300, TOUCH_BANNER_HEIGHT),
		CornerRadius = TOUCH_BANNER_HEIGHT / 2,
		Parent = holder,
	})
	local title = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.fromOffset(200, TOUCH_BANNER_HEIGHT),
		Parent = banner,
		Children = { UIKit.TextStroke(0.3) },
	})
	local timerPill = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -7, 0.5, 0),
		Size = UDim2.fromOffset(88, 52),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = banner,
		Children = { UIKit.Round() },
	})
	local timer = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Theme.Colors.Yellow,
		Parent = timerPill,
	})
	followTimer(timerPill, timer)

	-- As wide as the words (re-measured every second too, in case the font was still loading).
	local measuredFor, measuredAt = "", 0
	RunService.Heartbeat:Connect(function()
		local text = bannerTitle(true)
		title.Text = text
		local key = text .. tostring(timerPill.Visible)
		if key == measuredFor and os.clock() - measuredAt < 1 then
			return
		end
		measuredFor, measuredAt = key, os.clock()
		local width = math.ceil(UIKit.TextWidth(text, 26, Theme.Fonts.Display)) + 4
		title.Size = UDim2.fromOffset(width, TOUCH_BANNER_HEIGHT)
		banner.Size =
			UDim2.fromOffset(20 + width + (if timerPill.Visible then 12 + 88 + 7 else 20), TOUCH_BANNER_HEIGHT)
	end)
end

-- Phones: the round's status line ("Survivors: 7") and team scores, just under the top bar in the
-- middle. Mode HUDs go under them (Api.TopHud / HudY).
local function buildTouchStatus(parent: Instance)
	local holder = UIKit.new("Frame", {
		Name = "RoundStatus",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(620, 90),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.AutoScale(holder)
	local status = UIKit.Label({
		Text = "",
		TextSize = 22,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(600, 30),
		Parent = holder,
		Children = { UIKit.TextStroke(0.2) },
	})
	local teams = UIKit.Panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(240, 42),
		CornerRadius = 21,
		Visible = false,
		Parent = holder,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local teamsLabel = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = teams,
	})
	RunService.Heartbeat:Connect(function()
		local phase = GameState.Get("Phase") or "Waiting"
		status.Text = if phase == "InRound" then GameState.Get("Status") or "" else ""
	end)
	local function refreshTeams()
		local scores = GameState.GetJSON("TeamScores")
		if type(scores) ~= "table" or next(scores) == nil then
			teams.Visible = false
			return
		end
		teams.Visible = true
		teamsLabel.Text = `🔴 {scores.Red or 0}  —  {scores.Blue or 0} 🔵`
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
	local touch = isTouch()
	local size = if touch then Theme.Touch.Target else 74
	local button = UIKit.Button({
		Name = name,
		Text = icon,
		TextSize = if touch then 34 else 36,
		Size = UDim2.fromOffset(size, size),
		CornerRadius = if touch then 22 else 24,
		LayoutOrder = order,
		Parent = parent,
	}, function()
		State.OpenScreen:Fire(name)
	end, top, bottom)
	UIKit.Label({
		Text = caption,
		TextSize = if touch then Theme.Touch.MinText else 15,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if touch then 4 else 2),
		Size = UDim2.new(1, if touch then 20 else 10, 0, if touch then 20 else 18),
		Parent = button,
		Children = { UIKit.TextStroke(0.1) },
	})
	local badge = UIKit.Label({
		Name = "Badge",
		Text = "!",
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Red,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(if touch then 30 else 26, if touch then 30 else 26),
		Visible = false,
		Parent = button,
		Children = { UIKit.Round() },
	})
	badges[name] = badge
	return button
end

local function buildMenu(parent: Instance)
	-- PC: the middle of the right edge. Touch: down from the top right corner, where it can't be
	-- hit by mistake when reaching for the jump button.
	local touch = isTouch()
	local gap = if touch then 12 else 14
	local menu = UIKit.new("Frame", {
		Name = "Menu",
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(1, 0.5),
		Position = if touch then UDim2.new(1, -8, 0, 6) else UDim2.new(1, -14, 0.5, 0),
		Size = if touch
			then UDim2.fromOffset(Theme.Touch.Target + 20, 4 * Theme.Touch.Target + 3 * gap + 6)
			else UDim2.fromOffset(80, 360),
		BackgroundTransparency = 1,
		Parent = parent,
		Children = {
			UIKit.List(
				Enum.FillDirection.Vertical,
				gap,
				Enum.HorizontalAlignment.Center,
				if touch then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Center
			),
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
	local touch = isTouch()
	local row = UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, if touch then 76 else 64),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
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
		Size = UDim2.fromOffset(130, if touch then Theme.Touch.Target else 50),
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

local MUSIC_LEVELS = {
	{ Value = 0, Label = "🔇 Off" },
	{ Value = 0.25, Label = "🔈 Low" },
	{ Value = 0.5, Label = "🔉 Medium" },
	{ Value = 1, Label = "🔊 High" },
}

local function musicRow(parent: Instance, order: number, setSetting: RemoteEvent)
	local touch = isTouch()
	local row = UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, if touch then 76 else 64),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.Label({
		Text = "🎵 Music volume",
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -190, 1, 0),
		Parent = row,
	})
	local function currentIndex(): number
		local volume = State.Setting("MusicVolume")
		if type(volume) ~= "number" then
			return 3
		end
		local best, bestDistance = 1, math.huge
		for index, level in MUSIC_LEVELS do
			local distance = math.abs(level.Value - volume)
			if distance < bestDistance then
				best, bestDistance = index, distance
			end
		end
		return best
	end
	local button
	button = UIKit.Button({
		Text = "",
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(170, if touch then Theme.Touch.Target else 50),
		CornerRadius = 25,
		Parent = row,
	}, function()
		local nextLevel = MUSIC_LEVELS[(currentIndex() % #MUSIC_LEVELS) + 1]
		setSetting:FireServer("MusicVolume", nextLevel.Value)
	end, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
	local function refresh()
		button.Text = MUSIC_LEVELS[currentIndex()].Label
	end
	State.ProfileChanged:Connect(refresh)
	refresh()
end

local function buildSettings(overlay: Instance)
	local touch = isTouch()
	local modal = Modal.new(overlay, "Settings", "⚙️", Vector2.new(560, if touch then 440 else 420))
	local list = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = modal.Content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 10) },
	})
	local setSetting = Remotes.Get("SetSetting")
	musicRow(list, 1, setSetting)
	toggleRow(list, 2, "✨ Reduced effects", function()
		return State.Setting("ReducedEffects") == true
	end, function(value)
		setSetting:FireServer("ReducedEffects", value)
	end)
	UIKit.Label({
		Text = "Reduced effects tones down particles, flashes and motion.",
		TextSize = 18,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 3,
		Parent = list,
	})
	if Config.Monetization.VipGamePassId ~= 0 then
		UIKit.Button({
			Text = "💎 Get VIP (cosmetics only)",
			Size = UDim2.new(1, 0, 0, if touch then Theme.Touch.Target else 56),
			LayoutOrder = 4,
			Parent = list,
		}, function()
			Remotes.Get("PromptVip"):FireServer()
		end, Theme.Colors.Yellow, Theme.Colors.Orange)
	end
	local saveNote = UIKit.Label({
		Text = "",
		TextSize = 18,
		TextColor3 = Theme.Colors.TextDim,
		LayoutOrder = 5,
		Parent = list,
	})
	State.ProfileChanged:Connect(function(profile)
		saveNote.Text = if profile.CanSave
			then "Your progress saves automatically."
			else "⚠️ Progress isn't saving this session."
	end)
	return modal
end

function HudController.Start(context)
	if isTouch() then
		buildTouchProfile(context.Hud)
		buildTopBarBanner(context.Hud)
		buildTouchStatus(context.Hud)
	else
		buildProfileChip(context.Hud)
		buildPhaseBanner(context.Hud)
	end
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

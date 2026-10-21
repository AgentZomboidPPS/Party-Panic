-- Rules card, countdown and in-round HUD (design doc §12): objective, controls and duration before
-- the round; then a live mini-leaderboard, team highlights and an "you're out" prompt. Bots are in
-- the standings and get team outlines like everyone else (Participants).
-- Phones (owner: "Wtf is this mobile Ui lol"): the rules card sits in the upper middle under the
-- tip, sized for a phone; the standings take the profile pill's corner (top three, or you); the
-- "you're out" pill sits low between the thumbstick's corner and the jump button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local Teams = require(Shared.Teams)

local Participants = require(script.Parent.Parent.Participants)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local RoundController = {}

local player = Players.LocalPlayer

local TEAM_COLORS = Teams.Colors

local rules: Frame -- the card (PC), or the frame it sits in (phones)
local rulesCard: Frame
local rulesFields: { [string]: TextLabel } = {}
local countdown: TextLabel
local board: Frame
local outPanel: Frame

-- Phones and tablets without a keyboard get their own layouts (fewer standings rows, smaller cards).
local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function buildRules(parent: Instance)
	local touch = isTouch()
	if touch then
		-- Phones: in a frame at the top middle (scaled like the tip toast above it), so the card
		-- starts just under the tip on every screen. Shown for a few seconds before the round and
		-- nothing on it takes taps, so it may reach into the thumbstick's corner.
		rules = UIKit.new("Frame", {
			Name = "Rules",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(620, 104 + 262),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = parent,
		})
		UIKit.AutoScale(rules)
		rulesCard = UIKit.Panel({
			Name = "Card",
			Position = UDim2.fromOffset(0, 104),
			Size = UDim2.fromOffset(620, 262),
			CornerRadius = 24,
			Parent = rules,
		})
		rulesCard:SetAttribute("PP_Popup", true)
	else
		rules = UIKit.Panel({
			Name = "Rules",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromOffset(620, 330),
			CornerRadius = 26,
			Visible = false,
			Parent = parent,
		})
		UIKit.AutoScale(rules)
		rulesCard = rules
	end
	rulesFields.Icon = UIKit.Label({
		Text = "",
		TextSize = if touch then 60 else 80,
		TextWrapped = false,
		Position = if touch then UDim2.fromOffset(14, 10) else UDim2.fromOffset(20, 16),
		Size = if touch then UDim2.fromOffset(78, 72) else UDim2.fromOffset(110, 100),
		Parent = rulesCard,
	})
	rulesFields.Name = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 36 else 44,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = if touch then UDim2.fromOffset(100, 10) else UDim2.fromOffset(140, 18),
		Size = if touch then UDim2.new(1, -116, 0, 44) else UDim2.new(1, -160, 0, 56),
		Parent = rulesCard,
		Children = { UIKit.TextStroke(0.2) },
	})
	rulesFields.Category = UIKit.Label({
		Text = "",
		TextSize = if touch then 20 else 22,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = if touch then UDim2.fromOffset(102, 54) else UDim2.fromOffset(142, 74),
		Size = if touch then UDim2.new(1, -118, 0, 26) else UDim2.new(1, -160, 0, 30),
		Parent = rulesCard,
	})
	rulesFields.Objective = UIKit.Label({
		Text = "",
		TextSize = if touch then 21 else 28,
		TextScaled = not touch, -- PC: long objectives shrink a little to fit
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = if touch then UDim2.fromOffset(20, 90) else UDim2.fromOffset(28, 128),
		Size = if touch then UDim2.new(1, -40, 0, 70) else UDim2.new(1, -56, 0, 84),
		Parent = rulesCard,
		Children = if touch then {} else { UIKit.new("UITextSizeConstraint", { MaxTextSize = 28, MinTextSize = 20 }) },
	})
	local controls = UIKit.new("Frame", {
		Position = if touch then UDim2.fromOffset(14, 168) else UDim2.fromOffset(24, 222),
		Size = if touch then UDim2.new(1, -28, 0, 78) else UDim2.new(1, -48, 0, 84),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.3,
		Parent = rulesCard,
		Children = { UIKit.Corner(14) },
	})
	rulesFields.Controls = UIKit.Label({
		Text = "",
		TextSize = if touch then 20 else 21,
		TextColor3 = Theme.Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(1, 1),
		Parent = controls,
		Children = { UIKit.Padding(if touch then 8 else 10, 16) },
	})

	countdown = UIKit.Label({
		Name = "Countdown",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 140,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(400, 200),
		Visible = false,
		Parent = parent,
		Children = { UIKit.TextStroke(0) },
	})
	countdown:SetAttribute("PP_Popup", true) -- a second or two before the round
	UIKit.AutoScale(countdown)
end

local function showRules()
	local definition = GameDefinitions.Get(GameState.Get("GameId"))
	if not definition then
		return
	end
	local info = GameDefinitions.Categories[definition.Category]
	rulesFields.Icon.Text = definition.Icon
	rulesFields.Name.Text = definition.Name
	rulesFields.Category.Text =
		`{info and info.Icon or ""} {definition.Category}  •  ⏱ {definition.Duration} seconds`
	rulesFields.Objective.Text = "🎯 " .. definition.Objective
	rulesFields.Controls.Text = "🎮 " .. definition.Controls
	local gradient = rulesCard:FindFirstChildOfClass("UIGradient")
	if gradient then
		local h, s, v = definition.Color:ToHSV()
		gradient.Color = ColorSequence.new(Color3.fromHSV(h, s * 0.8, v * 0.75), Color3.fromHSV(h, s, v * 0.35))
	end
	rules.Visible = true
	UIKit.PopIn(rulesCard, 0.45)
end

local function flashCountdown(text: string, color: Color3)
	countdown.Text = text
	countdown.TextColor3 = color
	countdown.Visible = true
	UIKit.PopIn(countdown, 0.3)
	task.delay(0.85, function()
		if countdown.Text == text then
			countdown.Visible = false
		end
	end)
end

-- PC: the standings sit under the profile card, clear of the tips panel now that bots keep the
-- board full. Phones: in the profile pill's corner (it makes way during the round), the top three
-- rows with no title, clear of the thumbstick's corner below.
local TOUCH_ROW, TOUCH_ROWS, TOUCH_PAD = 26, 3, 8
local function buildBoard(parent: Instance)
	if isTouch() then
		board = UIKit.Panel({
			Name = "Leaderboard",
			Position = UDim2.fromOffset(8, 6),
			Size = UDim2.fromOffset(230, 2 * TOUCH_PAD + TOUCH_ROWS * TOUCH_ROW + (TOUCH_ROWS - 1) * 3),
			CornerRadius = 16,
			Visible = false,
			Parent = parent,
			Children = { UIKit.List(Enum.FillDirection.Vertical, 3), UIKit.Padding(TOUCH_PAD, 12) },
		}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
		UIKit.AutoScale(board)
		return
	end
	board = UIKit.Panel({
		Name = "Leaderboard",
		Size = UDim2.fromOffset(270, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		CornerRadius = 18,
		Visible = false,
		Parent = parent,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 4), UIKit.Padding(10, 12) },
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	UIKit.AutoScale(board, 0.9)
	-- Just under the profile chip and coins (HudController: 130 tall at y 12, scaled the same way).
	local function place()
		board.Position = UDim2.fromOffset(14, 12 + 130 * UIKit.CurrentScale() + 8)
	end
	board:SetAttribute("PP_UnderProfile", true)
	place()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(place)
end

local function refreshBoard()
	for _, child in board:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local touch = isTouch()
	local entries = {}
	for _, other in Participants.InRound() do
		table.insert(entries, {
			who = other,
			alive = other:GetAttribute("PP_Alive") == true,
			score = other:GetAttribute("PP_Score") or 0,
			text = other:GetAttribute("PP_ScoreText") or "",
			team = other:GetAttribute("PP_Team") or "",
		})
	end
	table.sort(entries, function(a, b)
		if a.alive ~= b.alive then
			return a.alive
		end
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.who.UserId > b.who.UserId -- ties keep their places (players, then bots)
	end)
	if not touch then
		UIKit.Label({
			Text = "🏁 Standings",
			Font = Theme.Fonts.Display,
			TextSize = 22,
			TextWrapped = false,
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = 0,
			Parent = board,
		})
	end
	-- The top rows, and always your own (in place of the last row if you're further down).
	local rows = if touch then TOUCH_ROWS else 6
	local shown = {}
	for index = 1, math.min(rows, #entries) do
		table.insert(shown, index)
	end
	for index, entry in entries do
		if entry.who.IsLocal and index > rows then
			shown[#shown] = index
		end
	end
	for _, index in shown do
		local entry = entries[index]
		local who = entry.who
		local status = if entry.alive then "" else "💀 "
		local teamColor = TEAM_COLORS[entry.team]
		local name = Participants.ListName(who.DisplayName, who.IsBot and not teamColor) -- teams keep their color
		local detail = Participants.Escape(if entry.text ~= "" then entry.text else tostring(entry.score))
		local color = if who.IsLocal
			then Theme.Colors.Yellow
			elseif teamColor then teamColor
			elseif entry.alive then Theme.Colors.Text
			else Theme.Colors.TextDim
		if touch then
			-- Phones: the name (shortened if it must be) and the score on the right, always shown.
			local row = UIKit.new("Frame", {
				Size = UDim2.new(1, 0, 0, TOUCH_ROW),
				BackgroundTransparency = 1,
				LayoutOrder = index,
				Parent = board,
			})
			local nameLabel = UIKit.Label({
				Text = `{index}. {status}{name}`,
				RichText = true,
				TextSize = 19,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = color,
				Size = UDim2.new(1, -64, 1, 0),
				Parent = row,
			})
			nameLabel:SetAttribute("PP_TruncateOk", true)
			UIKit.Label({
				Text = detail,
				RichText = true,
				TextSize = 19,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = color,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0, 60, 1, 0),
				Parent = row,
			})
			continue
		end
		UIKit.Label({
			Text = `{index}. {status}{name}  ·  {detail}`,
			RichText = true,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = color,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = index,
			Parent = board,
		})
	end
end

local function buildOutPanel(parent: Instance)
	if isTouch() then
		-- Phones: one low pill between the thumbstick's corner and the jump button (62% across is
		-- the middle of that gap on phones and tablets alike).
		outPanel = UIKit.Panel({
			Name = "OutPanel",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.62, 0, 1, -8),
			Size = UDim2.fromOffset(400, 86),
			CornerRadius = 30,
			Visible = false,
			Parent = parent,
		}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
		UIKit.AutoScale(outPanel)
		UIKit.Label({
			Text = "💥 You're out!",
			Font = Theme.Fonts.Display,
			TextSize = 26,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(20, 0),
			Size = UDim2.new(1, -190, 1, 0),
			Parent = outPanel,
		})
		UIKit.Button({
			Text = "👀 Watch",
			TextSize = 22,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -7, 0.5, 0),
			Size = UDim2.fromOffset(160, Theme.Touch.Target),
			CornerRadius = 26,
			Parent = outPanel,
		}, function()
			outPanel.Visible = false
			State.OpenScreen:Fire("Spectate")
		end, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
		return
	end
	outPanel = UIKit.Panel({
		Name = "OutPanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(420, 120),
		CornerRadius = 22,
		Visible = false,
		Parent = parent,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	UIKit.AutoScale(outPanel)
	UIKit.Label({
		Text = "💥 You're out! Nice try.",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 36),
		Parent = outPanel,
	})
	UIKit.Button({
		Text = "👀 Spectate",
		TextSize = 22,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(220, 52),
		CornerRadius = 26,
		Parent = outPanel,
	}, function()
		outPanel.Visible = false
		State.OpenScreen:Fire("Spectate")
	end, Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230))
end

-- Team-colored outlines so teammates and rivals are readable at a glance.
local highlights: { [Participants.Participant]: Highlight } = {}
local function refreshHighlights()
	local here = {}
	for _, other in Participants.All() do
		here[other] = true
		local team = other:GetAttribute("PP_Team") or ""
		local color = TEAM_COLORS[team]
		local character = other:Character()
		local existing = highlights[other]
		if color and character and GameState.Get("Phase") == "InRound" then
			if not existing or existing.Adornee ~= character then
				if existing then
					existing:Destroy()
				end
				existing = UIKit.new("Highlight", {
					Adornee = character,
					FillTransparency = 0.8,
					OutlineTransparency = 0.1,
					DepthMode = Enum.HighlightDepthMode.Occluded,
					Parent = character,
				})
				highlights[other] = existing
			end
			existing.FillColor = color
			existing.OutlineColor = color
		elseif existing then
			existing:Destroy()
			highlights[other] = nil
		end
	end
	-- Whoever left (a bot fading out, a player quitting) takes their outline with them.
	for other, highlight in highlights do
		if not here[other] then
			highlight:Destroy()
			highlights[other] = nil
		end
	end
end

function RoundController.Start(context)
	buildRules(context.Hud)
	buildBoard(context.Hud)
	buildOutPanel(context.Hud)

	local lastSecond = -1
	GameState.Changed("Phase", function(phase)
		rules.Visible = false
		outPanel.Visible = false
		if phase == "Preparing" then
			showRules()
		elseif phase == "InRound" then
			flashCountdown("GO!", Theme.Colors.Green)
		end
		board.Visible = phase == "InRound"
		refreshHighlights()
	end)

	player:GetAttributeChangedSignal("PP_Alive"):Connect(function()
		if GameState.Get("Phase") == "InRound" and State.InRound() and not State.Alive() then
			outPanel.Visible = true
			UIKit.PopIn(outPanel, 0.35)
		end
	end)
	-- A bot fading in or out shows up in the standings right away.
	Participants.Changed:Connect(function()
		if board.Visible then
			refreshBoard()
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		local phase = GameState.Get("Phase")
		if phase == "Preparing" then
			local second = math.ceil(GameState.TimeLeft())
			if second ~= lastSecond and second <= 3 and second >= 1 then
				rules.Visible = false
				flashCountdown(tostring(second), Theme.Colors.Yellow)
			end
			lastSecond = second
		else
			lastSecond = -1
		end
		accumulator += dt
		if accumulator > 0.3 then
			accumulator = 0
			if board.Visible then
				refreshBoard()
			end
			if phase == "InRound" then
				refreshHighlights()
			end
		end
	end)
end

return RoundController

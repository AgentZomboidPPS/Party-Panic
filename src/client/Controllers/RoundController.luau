-- Rules card, countdown and in-round HUD (design doc §12): objective, controls and duration before
-- the round; then a live mini-leaderboard, team highlights and an "you're out" prompt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local Teams = require(Shared.Teams)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local RoundController = {}

local player = Players.LocalPlayer

local TEAM_COLORS = Teams.Colors

local rules: Frame
local rulesFields: { [string]: TextLabel } = {}
local countdown: TextLabel
local board: Frame
local outPanel: Frame

local function buildRules(parent: Instance)
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
	rulesFields.Icon = UIKit.Label({
		Text = "",
		TextSize = 80,
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.fromOffset(110, 100),
		Parent = rules,
	})
	rulesFields.Name = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(140, 18),
		Size = UDim2.new(1, -160, 0, 56),
		Parent = rules,
		Children = { UIKit.TextStroke(0.2) },
	})
	rulesFields.Category = UIKit.Label({
		Text = "",
		TextSize = 22,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(142, 74),
		Size = UDim2.new(1, -160, 0, 30),
		Parent = rules,
	})
	rulesFields.Objective = UIKit.Label({
		Text = "",
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(28, 128),
		Size = UDim2.new(1, -56, 0, 80),
		Parent = rules,
	})
	local controls = UIKit.new("Frame", {
		Position = UDim2.fromOffset(24, 222),
		Size = UDim2.new(1, -48, 0, 84),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.3,
		Parent = rules,
		Children = { UIKit.Corner(14) },
	})
	rulesFields.Controls = UIKit.Label({
		Text = "",
		TextSize = 21,
		TextColor3 = Theme.Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(1, 1),
		Parent = controls,
		Children = { UIKit.Padding(10, 16) },
	})

	countdown = UIKit.Label({
		Name = "Countdown",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 140,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(400, 200),
		Visible = false,
		Parent = parent,
		Children = { UIKit.TextStroke(0) },
	})
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
	local gradient = rules:FindFirstChildOfClass("UIGradient")
	if gradient then
		local h, s, v = definition.Color:ToHSV()
		gradient.Color = ColorSequence.new(Color3.fromHSV(h, s * 0.8, v * 0.75), Color3.fromHSV(h, s, v * 0.35))
	end
	rules.Visible = true
	UIKit.PopIn(rules, 0.45)
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

local function buildBoard(parent: Instance)
	board = UIKit.Panel({
		Name = "Leaderboard",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(270, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		CornerRadius = 18,
		Visible = false,
		Parent = parent,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 4), UIKit.Padding(10, 12) },
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	UIKit.AutoScale(board, 0.9)
end

local function refreshBoard()
	for _, child in board:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local entries = {}
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("PP_InRound") then
			table.insert(entries, {
				player = other,
				alive = other:GetAttribute("PP_Alive") == true,
				score = other:GetAttribute("PP_Score") or 0,
				text = other:GetAttribute("PP_ScoreText") or "",
				team = other:GetAttribute("PP_Team") or "",
			})
		end
	end
	table.sort(entries, function(a, b)
		if a.alive ~= b.alive then
			return a.alive
		end
		return a.score > b.score
	end)
	UIKit.Label({
		Text = "🏁 Standings",
		Font = Theme.Fonts.Display,
		TextSize = 22,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 0,
		Parent = board,
	})
	for index, entry in entries do
		if index > 6 then
			break
		end
		local status = if entry.alive then "" else "💀 "
		local detail = if entry.text ~= "" then entry.text else tostring(entry.score)
		local teamColor = TEAM_COLORS[entry.team]
		UIKit.Label({
			Text = `{status}{entry.player.DisplayName}  ·  {detail}`,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = if entry.player == player
				then Theme.Colors.Yellow
				elseif teamColor then teamColor
				elseif entry.alive then Theme.Colors.Text
				else Theme.Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = index,
			Parent = board,
		})
	end
end

local function buildOutPanel(parent: Instance)
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
local highlights: { [Player]: Highlight } = {}
local function refreshHighlights()
	for _, other in Players:GetPlayers() do
		local team = other:GetAttribute("PP_Team") or ""
		local color = TEAM_COLORS[team]
		local character = other.Character
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

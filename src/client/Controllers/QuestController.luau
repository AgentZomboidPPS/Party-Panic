-- Quests and daily reward window (design doc §9): progress toward goals, exact rewards, and a daily
-- gift that's a welcome bonus rather than a requirement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local QuestDefinitions = require(Shared.QuestDefinitions)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local QuestController = {}

local modal: Modal.Modal
local list: ScrollingFrame

local function questRow(order: number, def, quest)
	local row = UIKit.Panel(
		{ Size = UDim2.new(1, -8, 0, 74), LayoutOrder = order, CornerRadius = 16, Parent = list },
		Theme.Colors.Card,
		Theme.Colors.PanelDark
	)
	UIKit.Label({
		Text = (if quest.Done then "✅ " else "🎯 ") .. def.Text,
		TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -200, 0, 30),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	UIKit.Label({
		Text = `+{def.RewardCoins} 🪙  +{def.RewardXP} XP`,
		TextSize = 18,
		TextColor3 = Theme.Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 8),
		Size = UDim2.fromOffset(180, 26),
		Parent = row,
	})
	local back = UIKit.new("Frame", {
		Position = UDim2.fromOffset(14, 42),
		Size = UDim2.new(1, -28, 0, 20),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = row,
		Children = { UIKit.Round() },
	})
	local ratio = math.clamp(quest.Progress / def.Target, 0, 1)
	UIKit.new("Frame", {
		Size = UDim2.fromScale(ratio, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = back,
		Children = { UIKit.Round(), UIKit.Gradient(Theme.Colors.Green, Theme.Colors.Cyan, 0) },
	})
	UIKit.Label({
		Text = `{quest.Progress} / {def.Target}`,
		TextSize = 15,
		Size = UDim2.fromScale(1, 1),
		Parent = back,
		Children = { UIKit.TextStroke(0.2) },
	})
end

local function header(order: number, text: string)
	UIKit.Label({
		Text = text,
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = order,
		Parent = list,
	})
end

local function render()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local profile = State.Profile
	if not profile then
		return
	end

	-- Daily gift card
	local daily = profile.Daily
	local card = UIKit.Panel(
		{ Size = UDim2.new(1, -8, 0, 96), LayoutOrder = 1, CornerRadius = 18, Parent = list },
		Color3.fromRGB(150, 110, 255),
		Color3.fromRGB(90, 60, 190)
	)
	local streakText = if daily.Streak > 0 then `🔥 {daily.Streak}-day streak` else "Start a streak today!"
	UIKit.Label({
		Text = "🎁 Daily Gift",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -240, 0, 34),
		Parent = card,
	})
	UIKit.Label({
		Text = streakText,
		TextSize = 19,
		TextColor3 = Theme.Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 50),
		Size = UDim2.new(1, -240, 0, 28),
		Parent = card,
	})
	if daily.CanClaim then
		UIKit.Button({
			Text = `Claim 🪙 {daily.NextReward}`,
			TextSize = 22,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(210, 58),
			Parent = card,
		}, function()
			Remotes.Get("ClaimDaily"):FireServer()
		end, Theme.Colors.Yellow, Theme.Colors.Orange)
	else
		UIKit.Label({
			Text = "Come back tomorrow! ⏰",
			TextSize = 20,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(220, 40),
			Parent = card,
		})
	end

	local order = 10
	header(order, "📅 Daily Quests")
	for _, quest in profile.Quests.Daily do
		local def = QuestDefinitions.ById[quest.Id]
		if def then
			order += 1
			questRow(order, def, quest)
		end
	end
	order += 1
	header(order, "⭐ Weekly Quests")
	for _, quest in profile.Quests.Weekly do
		local def = QuestDefinitions.ById[quest.Id]
		if def then
			order += 1
			questRow(order, def, quest)
		end
	end
	order += 1
	UIKit.Label({
		Text = "Quests pay out automatically when you finish them.",
		TextSize = 16,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = order,
		Parent = list,
	})
end

function QuestController.Start(context)
	modal = Modal.new(context.Overlay, "Quests", "📜", Vector2.new(700, 600))
	list = UIKit.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = modal.Content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 10), UIKit.Padding(4) },
	})
	State.OpenScreen:Connect(function(name)
		if name == "Quests" then
			modal:Toggle()
		end
	end)
	modal.Opened:Connect(render)
	State.ProfileChanged:Connect(function()
		if modal.IsOpen then
			render()
		end
	end)
end

return QuestController

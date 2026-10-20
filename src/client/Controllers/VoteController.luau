-- Vote UI (design doc §6): three big cards with icon, name, category, one-line objective,
-- estimated duration and live vote counts. Tap a card or walk onto a portal pad to vote;
-- your choice is clearly marked and can be changed until the timer ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local VoteController = {}

local player = Players.LocalPlayer

type Card = {
	button: TextButton,
	icon: TextLabel,
	name: TextLabel,
	category: TextLabel,
	objective: TextLabel,
	count: TextLabel,
	check: TextLabel,
	stroke: UIStroke,
	gradient: UIGradient,
}

local cards: { Card } = {}
local holder: Frame

local function darker(color: Color3): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.min(1, s * 1.1), v * 0.62)
end

local function buildCard(index: number): Card
	local button = UIKit.Button({
		Name = "Card" .. index,
		Text = "",
		Size = UDim2.fromOffset(280, 206),
		CornerRadius = 22,
		LayoutOrder = index,
		Parent = holder,
	}, function()
		Remotes.Get("CastVote"):FireServer(index)
	end, Theme.Colors.PanelLight, Theme.Colors.Panel)
	local gradient = button:FindFirstChildOfClass("UIGradient") :: UIGradient
	local stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke

	local icon = UIKit.Label({
		Text = "",
		TextSize = 54,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.fromOffset(70, 70),
		Parent = button,
	})
	local name = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Position = UDim2.fromOffset(86, 12),
		Size = UDim2.new(1, -96, 0, 60),
		Parent = button,
		Children = { UIKit.TextStroke(0.3) },
	})
	local category = UIKit.Label({
		Text = "",
		TextSize = 17,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 80),
		Size = UDim2.new(1, -32, 0, 22),
		Parent = button,
	})
	local objective = UIKit.Label({
		Text = "",
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(16, 104),
		Size = UDim2.new(1, -32, 0, 52),
		Parent = button,
	})
	local countPill = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -24, 0, 34),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.2,
		Parent = button,
		Children = { UIKit.Round() },
	})
	local count = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 22,
		Size = UDim2.fromScale(1, 1),
		Parent = countPill,
	})
	local check = UIKit.Label({
		Text = "✓ YOUR VOTE",
		Font = Theme.Fonts.Display,
		TextSize = 18,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Green,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(150, 30),
		Visible = false,
		Parent = button,
		Children = { UIKit.Round(), UIKit.TextStroke(0.3) },
	})
	return {
		button = button,
		icon = icon,
		name = name,
		category = category,
		objective = objective,
		count = count,
		check = check,
		stroke = stroke,
		gradient = gradient,
	}
end

local function refresh()
	local phase = GameState.Get("Phase")
	local options = GameState.GetJSON("VoteOptions") or {}
	local counts = GameState.GetJSON("VoteCounts") or {}
	local myVote = player:GetAttribute("PP_Vote") or 0
	holder.Visible = phase == "Voting" and #options > 0
	if not holder.Visible then
		return
	end
	for index, card in cards do
		local option = options[index]
		card.button.Visible = option ~= nil
		if not option then
			continue
		end
		local definition = GameDefinitions.Get(option.Id)
		if definition and not option.Mystery then
			card.icon.Text = definition.Icon
			card.name.Text = definition.Name
			local info = GameDefinitions.Categories[definition.Category]
			card.category.Text = `{info and info.Icon or ""} {definition.Category}  •  ⏱ ~{definition.Duration}s`
			card.objective.Text = definition.Objective
			card.gradient.Color = ColorSequence.new(definition.Color, darker(definition.Color))
		else
			card.icon.Text = "❓"
			card.name.Text = "Mystery Game"
			card.category.Text = "Revealed only if it wins"
			card.objective.Text = "Could be anything. Feeling lucky?"
			card.gradient.Color = ColorSequence.new(Color3.fromRGB(150, 110, 255), Color3.fromRGB(70, 40, 140))
		end
		local votes = counts[index] or 0
		card.count.Text = `{votes} vote{if votes == 1 then "" else "s"}`
		local selected = myVote == index
		card.check.Visible = selected
		card.stroke.Color = if selected then Theme.Colors.Yellow else Color3.new(1, 1, 1)
		card.stroke.Thickness = if selected then 5 else 2
		card.stroke.Transparency = if selected then 0 else 0.55
	end
end

function VoteController.Start(context)
	holder = UIKit.new("Frame", {
		Name = "Vote",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(900, 240),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = context.Hud,
		Children = {
			UIKit.List(
				Enum.FillDirection.Horizontal,
				16,
				Enum.HorizontalAlignment.Center,
				Enum.VerticalAlignment.Bottom
			),
		},
	})
	UIKit.AutoScale(holder)
	for index = 1, 3 do
		table.insert(cards, buildCard(index))
	end

	GameState.Changed("Phase", function(phase)
		refresh()
		if phase == "Voting" then
			for _, card in cards do
				UIKit.PopIn(card.button, 0.4)
			end
		end
	end)
	GameState.Changed("VoteOptions", refresh)
	GameState.Changed("VoteCounts", refresh)
	player:GetAttributeChangedSignal("PP_Vote"):Connect(refresh)
	refresh()
end

return VoteController

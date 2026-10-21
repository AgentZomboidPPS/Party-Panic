-- Vote UI (design doc §6): four cards, three games and Random (a hidden pick, revealed if it wins;
-- owner: "4 options always. and the 4th option should be random"), each with icon, name, category,
-- one-line objective, estimated duration and live vote counts. Tap a card or walk onto a portal pad to vote;
-- your choice is clearly marked and can be changed until the timer ends.
-- PC: a row along the bottom. Phones and tablets: compact upright cards under the round banner,
-- beside the menu, where the right thumb reaches them and they stay clear of the thumbstick and
-- the jump button (the objective is left to the rules card there).

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
local row: Frame
local touch = false

local CARDS = 4
local CARD_W = 228 -- PC
local TOUCH_W = 150

local function darker(color: Color3): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.min(1, s * 1.1), v * 0.62)
end

-- For TextScaled labels: shrink to fit the box, but never past `size`.
local function fitted(size: number): UITextSizeConstraint
	return UIKit.new("UITextSizeConstraint", { MaxTextSize = size, MinTextSize = math.floor(size * 0.6) })
end

local function buildCard(index: number): Card
	local button = UIKit.Button({
		Name = "Card" .. index,
		Text = "",
		Size = if touch then UDim2.fromOffset(TOUCH_W, 220) else UDim2.fromOffset(CARD_W, 214),
		CornerRadius = 22,
		LayoutOrder = index,
		Parent = row,
	}, function()
		Remotes.Get("CastVote"):FireServer(index)
	end, Theme.Colors.PanelLight, Theme.Colors.Panel)
	local gradient = button:FindFirstChildOfClass("UIGradient") :: UIGradient
	local stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke

	-- PC: icon at the top left with the name beside it. Touch: icon, name and category stacked.
	local icon = UIKit.Label({
		Text = "",
		TextSize = if touch then 46 else 54,
		AnchorPoint = if touch then Vector2.new(0.5, 0) else Vector2.zero,
		Position = if touch then UDim2.new(0.5, 0, 0, 10) else UDim2.fromOffset(12, 8),
		Size = if touch then UDim2.fromOffset(60, 52) else UDim2.fromOffset(70, 70),
		Parent = button,
	})
	local name = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 23 else 26,
		TextScaled = true,
		TextXAlignment = if touch then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
		Position = if touch then UDim2.fromOffset(8, 64) else UDim2.fromOffset(86, 12),
		Size = if touch then UDim2.new(1, -16, 0, 52) else UDim2.new(1, -96, 0, 60),
		Parent = button,
		Children = { UIKit.TextStroke(0.3), fitted(if touch then 23 else 26) },
	})
	local category = UIKit.Label({
		Text = "",
		TextSize = 17,
		TextScaled = true,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = if touch then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
		Position = if touch then UDim2.fromOffset(8, 118) else UDim2.fromOffset(16, 80),
		Size = if touch then UDim2.new(1, -16, 0, 22) else UDim2.new(1, -32, 0, 22),
		Parent = button,
		Children = { fitted(17) },
	})
	local objective = UIKit.Label({
		Text = "",
		TextSize = 18,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(14, 104),
		Size = UDim2.new(1, -28, 0, 60),
		Visible = not touch,
		Parent = button,
		Children = { fitted(18) },
	})
	local countPill = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -24, 0, if touch then 38 else 34),
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
		TextSize = if touch then 17 else 18,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Green,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = if touch then UDim2.fromOffset(136, 28) else UDim2.fromOffset(150, 30),
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
			card.icon.Text = "🎲"
			card.name.Text = "Random"
			card.category.Text = if touch then "Any game!" else "Any game • revealed if it wins"
			card.objective.Text = "Could be any game. Feeling lucky?"
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
	touch = UIKit.IsTouch()
	local list = UIKit.List(
		Enum.FillDirection.Horizontal,
		if touch then 10 else 16,
		Enum.HorizontalAlignment.Center,
		if touch then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom
	)
	if touch then
		-- Anchored like the menu (top right) and scaled the same way, so the cards sit just under
		-- the round banner (80 down, with room for the "YOUR VOTE" tag on a card's top edge) and
		-- just left of the menu column (70 wide) on every screen.
		local top = 80 + 16
		holder = UIKit.new("Frame", {
			Name = "Vote",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 10),
			Size = UDim2.fromOffset(78 + CARDS * TOUCH_W + (CARDS - 1) * 10, top + 220),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = context.Hud,
		})
		UIKit.AutoScale(holder)
		row = UIKit.new("Frame", {
			Name = "Cards",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -78, 0, top),
			Size = UDim2.fromOffset(CARDS * TOUCH_W + (CARDS - 1) * 10, 220),
			BackgroundTransparency = 1,
			Parent = holder,
			Children = { list },
		})
	else
		holder = UIKit.new("Frame", {
			Name = "Vote",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -18),
			Size = UDim2.fromOffset(CARDS * CARD_W + (CARDS - 1) * 16 + 20, 248),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = context.Hud,
			Children = { list },
		})
		UIKit.AutoScale(holder)
		row = holder
	end
	for index = 1, CARDS do
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

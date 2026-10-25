-- Vote UI (design doc §6): four cards, three games and Random (a hidden pick, revealed if it wins;
-- owner: "4 options always. and the 4th option should be random"), each with icon, name, category,
-- one-line objective, estimated duration and live vote counts. Tap a card to vote (the stage's
-- portals only play a preview of each option); your choice is clearly marked and can be changed
-- until the timer ends.
-- PC: a row along the bottom. Phones and tablets (owner: "Wtf is this mobile Ui lol"): a slim row
-- of four cards: icon, name on one line, category as just its icon, and the votes (the objective and
-- length are on the rules card). A long name (Mecha-Marathon) is drawn a little smaller so it fits
-- its card. The row sits at the bottom middle, drawn a quarter bigger (owner: "Can we make the vote
-- buttons go to the bottom middle and make them 25% larger."): every card is laid out at the old
-- size and the row is scaled up whole (TOUCH_GROW), between the thumbstick's corner and the jump
-- button. Toasts stay above it (NotificationController's BOTTOM_PANELS).
-- Only people who'll play vote: while you're sitting out (UI/SitOutSwitch) the cards are dimmed and
-- a note says why (over the cards); tapping one tells you how to jump back in. The server refuses
-- those votes anyway (VotingService).
-- Game Mastery (owner: "Let's build it. 1 yes 2 gold pass should help a little. 3 yes"; UI/Mastery):
-- every game's card has the player's rank in it (phones: a badge in the top right corner, the
-- category icon's twin; PC: a line under the objective with the next goal, "SILVER • 6 pts to GOLD"),
-- and today's Spotlight games (double points) a yellow "×2" (phones: in the category icon's place;
-- PC: a sticker on the top right corner, clear of the YOUR VOTE tag).
-- The objective on a PC card was drawn at about 11 pt to fit, so it's the objective's first sentence
-- now, in a slightly taller box (the card is 14 units taller); the rules card before the round has
-- the whole of it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local MasteryLogic = require(Shared.Logic.MasteryLogic)

local NotificationController = require(script.Parent.NotificationController)
local State = require(script.Parent.Parent.State)
local Mastery = require(script.Parent.Parent.UI.Mastery)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local VoteController = {}

local player = Players.LocalPlayer

type Card = {
	button: TextButton,
	icon: TextLabel,
	name: TextLabel,
	category: TextLabel,
	categoryIcon: TextLabel,
	objective: TextLabel,
	count: TextLabel,
	check: TextLabel,
	stroke: UIStroke,
	gradient: UIGradient,
	dim: Frame,
	mastery: Frame, -- holds the rank badge
	masteryShown: string, -- the game and rank the badge is for ("" for none)
	goal: TextLabel?, -- PC: the rank and the next goal
	spotlight: TextLabel, -- "×2" on today's Spotlight games
}

local cards: { Card } = {}
local holder: Frame
local row: Frame
local sitOutNote: TextLabel
local touch = false
local lastSitOutTip = -math.huge

local CARDS = 4
local CARD_W, CARD_H = 228, 228 -- PC
local TOUCH_W, TOUCH_H, TOUCH_GAP = 150, 94, 10
local TOUCH_NAME_TEXT = 20 -- a phone card's name (a long one is drawn a little smaller to fit)
local TOUCH_TOP = 12 -- room above the row for the "YOUR VOTE" tag on a card's top edge
local TOUCH_GROW = 1.25 -- phones: the row is drawn this much bigger than it's laid out
local TOUCH_BOTTOM = 10 -- phones: the row's gap above the screen's bottom edge
local PC_TOP = 34 -- PC: the same room above the cards (the sit-out note uses it when there's no vote)

local function darker(color: Color3): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.min(1, s * 1.1), v * 0.62)
end

-- An objective's first sentence ("Race your mine cart out of the crystal cave!"): the PC card's line
-- (the rules card has the whole of it). A sentence ends at ". ", "! " or "? " before a capital or a
-- number, so "Everyone vs. a giant robot vacuum!" stays whole.
local function firstSentence(text: string): string
	local stop = string.find(text, "[%.!%?] [%u%d]")
	return if stop then string.sub(text, 1, stop) else text
end

-- For TextScaled labels: shrink to fit the box, but never past `size`.
local function fitted(size: number): UITextSizeConstraint
	return UIKit.new("UITextSizeConstraint", { MaxTextSize = size, MinTextSize = math.floor(size * 0.6) })
end

local function buildCard(index: number): Card
	local button = UIKit.Button({
		Name = "Card" .. index,
		Text = "",
		Size = if touch then UDim2.fromOffset(TOUCH_W, TOUCH_H) else UDim2.fromOffset(CARD_W, CARD_H),
		CornerRadius = if touch then 18 else 22,
		LayoutOrder = index,
		Parent = row,
	}, function()
		if State.SittingOut() then
			local now = os.clock()
			if now - lastSitOutTip > 2 then
				lastSitOutTip = now
				NotificationController.Show("You're sitting out - tap SITTING OUT up top to play and vote!", "info", 4)
			end
			return
		end
		Remotes.Get("CastVote"):FireServer(index)
	end, Theme.Colors.PanelLight, Theme.Colors.Panel)
	local gradient = button:FindFirstChildOfClass("UIGradient") :: UIGradient
	local stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke

	-- PC: icon at the top left with the name beside it. Touch: icon over the name, the category's
	-- icon in the corner.
	local icon = UIKit.Label({
		Text = "",
		TextSize = if touch then 30 else 54,
		TextWrapped = false,
		AnchorPoint = if touch then Vector2.new(0.5, 0) else Vector2.zero,
		Position = if touch then UDim2.new(0.5, 0, 0, 12) else UDim2.fromOffset(12, 8), -- under the tag
		Size = if touch then UDim2.fromOffset(56, 32) else UDim2.fromOffset(70, 70),
		Parent = button,
	})
	local name = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then TOUCH_NAME_TEXT else 26,
		TextScaled = not touch,
		TextWrapped = not touch,
		TextXAlignment = if touch then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
		AnchorPoint = if touch then Vector2.new(0.5, 0) else Vector2.zero,
		Position = if touch then UDim2.new(0.5, 0, 0, 43) else UDim2.fromOffset(86, 12),
		Size = if touch then UDim2.new(1, -10, 0, 24) else UDim2.new(1, -96, 0, 60),
		Parent = button,
		Children = if touch then { UIKit.TextStroke(0.3) } else { UIKit.TextStroke(0.3), fitted(26) },
	})
	if not touch then
		name:SetAttribute("PP_Lines", 2) -- PC: a long name may take two lines beside the icon
	end
	local categoryIcon = UIKit.Label({
		Text = "",
		TextSize = 20,
		TextWrapped = false,
		Position = UDim2.fromOffset(6, 14),
		Size = UDim2.fromOffset(26, 26),
		Visible = touch,
		Parent = button,
	})
	local category = UIKit.Label({
		Text = "",
		TextSize = 17,
		TextScaled = true,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 80),
		Size = UDim2.new(1, -32, 0, 22),
		Visible = not touch,
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
		Size = UDim2.new(1, -28, 0, 54),
		Visible = not touch,
		Parent = button,
		Children = { fitted(18) },
	})
	-- Game Mastery: the rank (and on PC the next goal), and the Spotlight's ×2.
	local mastery = UIKit.new("Frame", {
		Name = "Mastery",
		BackgroundTransparency = 1,
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.zero,
		Position = if touch then UDim2.new(1, -6, 0, 14) else UDim2.fromOffset(14, 160),
		Size = if touch then UDim2.fromOffset(26, 26) else UDim2.fromOffset(22, 22),
		Parent = button,
	})
	local goal = if touch
		then nil
		else UIKit.Label({
			Name = "MasteryGoal",
			Text = "",
			TextSize = 16,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(42, 160),
			Size = UDim2.new(1, -56, 0, 22),
			Parent = button,
			Children = { UIKit.TextStroke(0.3) },
		})
	local spotlight = UIKit.Label({
		Name = "Spotlight",
		Text = "×2",
		Font = Theme.Fonts.Display,
		TextSize = if touch then Theme.Touch.MinText else 20,
		TextWrapped = false,
		TextColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Yellow,
		AnchorPoint = if touch then Vector2.zero else Vector2.new(0.5, 0.5),
		Position = if touch then UDim2.fromOffset(4, 14) else UDim2.new(1, -16, 0, 0),
		Size = if touch then UDim2.fromOffset(34, 26) else UDim2.fromOffset(44, 30),
		Rotation = if touch then 0 else 10,
		ZIndex = 4,
		Visible = false,
		Parent = button,
		Children = { UIKit.Round(), UIKit.Stroke(Theme.Colors.Ink, 2, 0) },
	})
	local countPill = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if touch then -4 else -10),
		Size = UDim2.new(1, if touch then -16 else -24, 0, if touch then 24 else 34),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.2,
		Parent = button,
		Children = { UIKit.Round() },
	})
	local count = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then Theme.Touch.MinText else 22,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = countPill,
	})
	local check = UIKit.Label({
		Text = "✓ YOUR VOTE",
		Font = Theme.Fonts.Display,
		TextSize = 18,
		TextWrapped = false,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Green,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = if touch then UDim2.fromOffset(124, 24) else UDim2.fromOffset(150, 30),
		Visible = false,
		Parent = button,
		Children = { UIKit.Round(), UIKit.TextStroke(0.3) },
	})
	-- Sitting out: the card stays readable but dimmed.
	local dim = UIKit.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(16, 10, 34),
		BackgroundTransparency = 0.42,
		ZIndex = 5,
		Visible = false,
		Parent = button,
		Children = { UIKit.Corner(if touch then 18 else 22) },
	})
	return {
		button = button,
		icon = icon,
		name = name,
		category = category,
		categoryIcon = categoryIcon,
		objective = objective,
		count = count,
		check = check,
		stroke = stroke,
		gradient = gradient,
		dim = dim,
		mastery = mastery,
		masteryShown = "",
		goal = goal,
		spotlight = spotlight,
	}
end

-- The card's Game Mastery: the player's rank in the game, the next goal (PC) and the Spotlight's ×2
-- (nil `gameId`: the Random card, none of it).
local function showMastery(card: Card, gameId: string?)
	local lit = gameId ~= nil and Mastery.IsSpotlight(gameId)
	card.spotlight.Visible = lit
	if touch then
		card.categoryIcon.Visible = not lit
	end
	card.mastery.Visible = gameId ~= nil
	if card.goal then
		card.goal.Visible = gameId ~= nil
	end
	if not gameId then
		return
	end
	local progress = Mastery.Progress(gameId)
	if card.goal then
		card.goal.Text = `{Mastery.Name(progress.Rank)} • {MasteryLogic.Goal(progress)}`
	end
	local shown = `{gameId}:{progress.Rank}`
	if card.masteryShown ~= shown then
		card.masteryShown = shown
		card.mastery:ClearAllChildren()
		Mastery.Badge(progress.Rank, card.mastery.Size.X.Offset, { Parent = card.mastery })
	end
end

-- The note that says why the cards are dimmed, over the cards (short on phones).
local function buildSitOutNote(parent: Instance)
	local text = if touch
		then "💤 Sitting out - can't vote"
		else "💤 Sitting out - can't vote. Tap SITTING OUT up top to play!"
	local size = if touch then Theme.Touch.MinText else 20
	sitOutNote = UIKit.Label({
		Name = "SitOutNote",
		Text = text,
		TextSize = size,
		TextWrapped = false,
		BackgroundTransparency = 0.15,
		BackgroundColor3 = Theme.Colors.PanelDark,
		AnchorPoint = if touch then Vector2.new(0.5, 1) else Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, if touch then TOUCH_TOP - 4 else 2),
		Size = UDim2.fromOffset(
			math.ceil(UIKit.TextWidth(text, size, Theme.Fonts.Bold)) + 32,
			if touch then 28 else 30
		),
		Visible = false,
		Parent = parent,
		Children = { UIKit.Round(), UIKit.TextStroke(0.4) },
	})
	task.delay(3, function() -- again once the font has surely loaded
		local width = math.ceil(UIKit.TextWidth(text, size, Theme.Fonts.Bold)) + 32
		sitOutNote.Size = UDim2.fromOffset(math.max(width, sitOutNote.Size.X.Offset), sitOutNote.Size.Y.Offset)
	end)
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
	local sittingOut = State.SittingOut()
	sitOutNote.Visible = sittingOut
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
			card.categoryIcon.Text = info and info.Icon or ""
			card.objective.Text = firstSentence(definition.Objective)
			card.gradient.Color = ColorSequence.new(definition.Color, darker(definition.Color))
			showMastery(card, definition.Id)
		else
			card.icon.Text = "🎲"
			card.name.Text = "Random"
			card.category.Text = "Any game • revealed if it wins"
			card.categoryIcon.Text = "❔"
			card.objective.Text = "Could be any game. Feeling lucky?"
			card.gradient.Color = ColorSequence.new(Color3.fromRGB(150, 110, 255), Color3.fromRGB(70, 40, 140))
			showMastery(card, nil)
		end
		if touch then
			-- One line under the icon: a long name ("Mecha-Marathon") is drawn a little smaller to fit
			-- (phones draw small text up to 4% wider than it measures), never under 11 pt.
			local size = TOUCH_NAME_TEXT
			while
				size > Theme.Touch.MinText
				and UIKit.TextWidth(card.name.Text, size, Theme.Fonts.Display) * 1.06 + 2 > TOUCH_W - 10
			do
				size -= 1
			end
			card.name.TextSize = size
		end
		local votes = counts[index] or 0
		card.count.Text = `{votes} vote{if votes == 1 then "" else "s"}`
		local selected = myVote == index and not sittingOut
		card.dim.Visible = sittingOut
		card.check.Visible = selected
		card.stroke.Color = if selected then Theme.Colors.Yellow else Color3.new(1, 1, 1)
		card.stroke.Thickness = if selected then (if touch then 4 else 5) else 2
		card.stroke.Transparency = if selected then 0 else 0.55
	end
end

function VoteController.Start(context)
	touch = UIKit.IsTouch()
	local list = UIKit.List(
		Enum.FillDirection.Horizontal,
		if touch then TOUCH_GAP else 16,
		Enum.HorizontalAlignment.Center,
		if touch then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom
	)
	local noteParent: Instance
	if touch then
		-- At the bottom middle, a quarter bigger: the cards are laid out at their size in "Grow", which
		-- a UIScale draws TOUCH_GROW times as big (text and all) inside the holder.
		local width = CARDS * TOUCH_W + (CARDS - 1) * TOUCH_GAP
		local height = TOUCH_TOP + TOUCH_H + 4
		holder = UIKit.new("Frame", {
			Name = "Vote",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -TOUCH_BOTTOM),
			Size = UDim2.fromOffset(width * TOUCH_GROW, height * TOUCH_GROW),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = context.Hud,
		})
		UIKit.AutoScale(holder)
		-- Where the owner wants them: the first two cards reach into the MOVE stick's corner, so a
		-- thumb that starts there taps a card (a vote can be changed until the timer ends) instead
		-- of walking, for the few seconds of the vote. (tools/checks: allowed over the stick's zone.)
		holder:SetAttribute("PP_Popup", true)
		local grow = UIKit.new("Frame", {
			Name = "Grow",
			Size = UDim2.fromOffset(width, height),
			BackgroundTransparency = 1,
			Parent = holder,
			Children = { UIKit.new("UIScale", { Scale = TOUCH_GROW }) },
		})
		row = UIKit.new("Frame", {
			Name = "Cards",
			Position = UDim2.fromOffset(0, TOUCH_TOP),
			Size = UDim2.fromOffset(width, TOUCH_H),
			BackgroundTransparency = 1,
			Parent = grow,
			Children = { list },
		})
		noteParent = grow
	else
		holder = UIKit.new("Frame", {
			Name = "Vote",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -18),
			Size = UDim2.fromOffset(CARDS * CARD_W + (CARDS - 1) * 16 + 20, PC_TOP + CARD_H),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = context.Hud,
		})
		UIKit.AutoScale(holder)
		row = UIKit.new("Frame", {
			Name = "Cards",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = holder,
			Children = { list },
		})
		noteParent = holder
	end
	for index = 1, CARDS do
		table.insert(cards, buildCard(index))
	end
	buildSitOutNote(noteParent)

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
	GameState.Changed("Spotlight", refresh)
	State.ProfileChanged:Connect(refresh)
	player:GetAttributeChangedSignal("PP_Vote"):Connect(refresh)
	player:GetAttributeChangedSignal("PP_SitOut"):Connect(refresh)
	refresh()
end

return VoteController

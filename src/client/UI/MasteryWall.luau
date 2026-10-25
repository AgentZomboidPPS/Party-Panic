-- The Rewards screen's MASTERY tab (owner: "Let's build it. 1 yes 2 gold pass should help a little.
-- 3 yes"; Controllers/RewardsController shows it, the rules are Shared/Logic/MasteryLogic): every
-- game's rank on one wall.
--   * Along the top: how many games are GOLD, DIAMOND and LEGEND, and how points are earned.
--   * The game picked (a tap on its tile; at first, the one closest to its next rank): its rank, a
--     bar to the next, what that rank pays, and the rounds played and wins that count.
--   * Today's Spotlight games (double points), then every game by type, each a tile with its icon,
--     name, rank badge and bar; games not played yet are dimmed ("NEW").
-- Phones: tiles 124 units square or so (77 pt), text 11 pt or more; the list scrolls.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameDefinitions = require(Shared.GameDefinitions)
local MasteryLogic = require(Shared.Logic.MasteryLogic)

local Mastery = require(script.Parent.Mastery)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local MasteryWall = {}

local TILE_W, TILE_H, GAP = 124, 120, 8
local DETAIL_H = 136
local SCROLL_ROOM = 10 -- the scroll bar's side of each row
local CATEGORIES = { "Survival", "Race", "Knockback", "Reaction", "Versus", "Team", "Luck" }

local selected: string? = nil -- the game shown in the detail panel

-- The games on the wall (the ones in the rotation), in the game list's order.
local function games(): { GameDefinitions.GameDefinition }
	local list = {}
	for _, definition in GameDefinitions.List do
		if definition.Enabled ~= false then
			table.insert(list, definition)
		end
	end
	return list
end

local function darker(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.min(1, s * 1.05), v * amount)
end

-- "25 coins + 2 keys" (what a rank pays).
local function paysText(rank: MasteryLogic.Rank): string
	local parts = {}
	if rank.Coins > 0 then
		table.insert(parts, `{rank.Coins} coins`)
	end
	if rank.Keys > 0 then
		table.insert(parts, `{rank.Keys} key{if rank.Keys == 1 then "" else "s"}`)
	end
	if rank.Crates > 0 then
		table.insert(parts, `{rank.Crates} crate{if rank.Crates == 1 then "" else "s"}`)
	end
	return table.concat(parts, " + ")
end

-- The game to show first: the one closest to its next rank (a game played, below the top), else the
-- first game.
local function firstPick(list: { GameDefinitions.GameDefinition }): string
	local best, bestFraction = nil, -1
	for _, definition in list do
		local progress = Mastery.Progress(definition.Id)
		if progress.Rank > 0 and progress.Next and progress.Fraction > bestFraction then
			best, bestFraction = definition.Id, progress.Fraction
		end
	end
	return best or (list[1] and list[1].Id) or ""
end

local function detail(parent: Instance, definition: GameDefinitions.GameDefinition, order: number)
	local entry = Mastery.Entry(definition.Id)
	local progress = Mastery.Progress(definition.Id)
	local panel = UIKit.Panel({
		Name = "Detail",
		Size = UDim2.new(1, -SCROLL_ROOM, 0, DETAIL_H),
		LayoutOrder = order,
		CornerRadius = 18,
		Parent = parent,
	}, definition.Color, darker(definition.Color, 0.45))
	UIKit.Label({
		Name = "Icon",
		Text = definition.Icon,
		TextSize = 46,
		TextWrapped = false,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.fromOffset(60, 60),
		Parent = panel,
	})
	UIKit.Label({
		Name = "Game",
		Text = string.upper(definition.Name),
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(84, 8),
		Size = UDim2.new(1, -240, 0, 36),
		Parent = panel,
		Children = { UIKit.TextStroke(0.1) },
	})
	if Mastery.IsSpotlight(definition.Id) then
		UIKit.Label({
			Name = "Spotlight",
			Text = "×2 TODAY",
			Font = Theme.Fonts.Display,
			TextSize = 20,
			TextWrapped = false,
			TextColor3 = Theme.Colors.Ink,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Colors.Yellow,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 12),
			Size = UDim2.fromOffset(130, 32),
			Parent = panel,
			Children = { UIKit.Round(), UIKit.Stroke(Theme.Colors.Ink, 2, 0) },
		})
	end
	Mastery.Badge(progress.Rank, 34, { Position = UDim2.fromOffset(84, 46), Parent = panel })
	UIKit.Label({
		Name = "Rank",
		Text = Mastery.Name(progress.Rank),
		Font = Theme.Fonts.Display,
		TextSize = 22,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(126, 46),
		Size = UDim2.fromOffset(120, 34),
		Parent = panel,
		Children = { UIKit.TextStroke(0.1) },
	})
	local nextIndex = math.min(progress.Rank + 1, #Mastery.Ranks)
	Mastery.Bar(nextIndex, progress.Fraction, MasteryLogic.BarText(progress), Theme.Touch.MinText, {
		Position = UDim2.fromOffset(252, 50),
		Size = UDim2.new(1, -268, 0, 26),
		Parent = panel,
	})
	local nextRank = progress.Next
	local goal
	if not nextRank then
		goal = `The top rank! You're a LEGEND at {string.upper(definition.Name)}.`
	elseif progress.Short == "Wins" then
		goal = `Next: {MasteryLogic.Goal(progress)} (with 3+ real players)  •  pays {paysText(nextRank)}`
	else
		goal = `Next: {MasteryLogic.Goal(progress)}  •  pays {paysText(nextRank)}`
	end
	UIKit.Label({
		Name = "Goal",
		Text = goal,
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 84),
		Size = UDim2.new(1, -32, 0, 22),
		Parent = panel,
		Children = { UIKit.TextStroke(0.3) },
	})
	local rounds = if entry then entry.N else 0
	local wins = if entry then entry.W else 0
	UIKit.Label({
		Name = "Played",
		Text = if rounds == 0
			then "Not played yet: your first round makes you BRONZE!"
			else `Played {rounds} round{if rounds == 1 then "" else "s"}  •  {wins} win{if wins == 1
				then ""
				else "s"} that count`,
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 108),
		Size = UDim2.new(1, -32, 0, 22),
		Parent = panel,
	})
end

local function tile(parent: Instance, definition: GameDefinitions.GameDefinition, order: number, redraw: () -> ())
	local progress = Mastery.Progress(definition.Id)
	local played = Mastery.Entry(definition.Id) ~= nil
	local picked = selected == definition.Id
	local frame = UIKit.Panel(
		{
			Name = definition.Id,
			Size = UDim2.fromOffset(TILE_W, TILE_H),
			LayoutOrder = order,
			CornerRadius = 16,
			Parent = parent,
		},
		if played then definition.Color else Theme.Colors.PanelLight,
		if played then darker(definition.Color, 0.45) else Theme.Colors.PanelDark
	)
	local rim = frame:FindFirstChildOfClass("UIStroke")
	if rim and picked then
		rim.Color, rim.Thickness, rim.Transparency = Theme.Colors.Yellow, 4, 0
	end
	UIKit.Label({
		Name = "Icon",
		Text = definition.Icon,
		TextSize = 30,
		TextWrapped = false,
		TextTransparency = if played then 0 else 0.35,
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(40, 38),
		Parent = frame,
	})
	if Mastery.IsSpotlight(definition.Id) then
		UIKit.Label({
			Name = "Spotlight",
			Text = "×2",
			Font = Theme.Fonts.Display,
			TextSize = Theme.Touch.MinText,
			TextWrapped = false,
			TextColor3 = Theme.Colors.Ink,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Colors.Yellow,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.fromOffset(34, 24),
			Parent = frame,
			Children = { UIKit.Round() },
		})
	end
	Mastery.Badge(progress.Rank, 36, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Parent = frame,
	})
	local name = UIKit.Label({
		Name = "Game",
		Text = definition.Name,
		Font = Theme.Fonts.Display,
		TextSize = Theme.Touch.MinText,
		TextColor3 = if played then Color3.new(1, 1, 1) else Theme.Colors.TextDim,
		Position = UDim2.fromOffset(6, 46),
		Size = UDim2.new(1, -12, 0, 42),
		Parent = frame,
		Children = { UIKit.TextStroke(0.2) },
	})
	name:SetAttribute("PP_Lines", 2) -- "Parasol Plummet" takes two lines
	local nextIndex = math.min(progress.Rank + 1, #Mastery.Ranks)
	Mastery.Bar(
		nextIndex,
		if played then progress.Fraction else 0,
		if played then MasteryLogic.BarText(progress) else "NEW",
		Theme.Touch.MinText,
		{
			Position = UDim2.new(0, 6, 1, -30),
			Size = UDim2.new(1, -12, 0, 24),
			Parent = frame,
		}
	)
	-- The whole tile picks the game for the detail panel.
	local button = UIKit.new("TextButton", {
		Name = "Pick",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = frame,
	})
	button.Activated:Connect(function()
		if selected ~= definition.Id then
			selected = definition.Id
			redraw()
		end
	end)
end

-- A row of tiles under its heading ("SURVIVAL  3/5 ranked"): as many to a line as fit `width`.
local function section(
	parent: Instance,
	order: number,
	heading: string,
	list: { GameDefinitions.GameDefinition },
	width: number,
	redraw: () -> ()
)
	if #list == 0 then
		return
	end
	UIKit.Label({
		Name = "Heading",
		Text = heading,
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -SCROLL_ROOM, 0, 28),
		LayoutOrder = order,
		Parent = parent,
		Children = { UIKit.TextStroke(0.2) },
	})
	local columns = math.max(1, math.floor((width + GAP) / (TILE_W + GAP)))
	local rows = math.ceil(#list / columns)
	local grid = UIKit.new("Frame", {
		Name = "Tiles",
		Size = UDim2.fromOffset(width, rows * TILE_H + (rows - 1) * GAP),
		BackgroundTransparency = 1,
		LayoutOrder = order + 1,
		Parent = parent,
		Children = {
			UIKit.new("UIGridLayout", {
				CellSize = UDim2.fromOffset(TILE_W, TILE_H),
				CellPadding = UDim2.fromOffset(GAP, GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	for index, definition in list do
		tile(grid, definition, index, redraw)
	end
end

-- Draws the tab into `body` (scrolled to `keep`); `redraw` draws it again (a tile was picked).
function MasteryWall.Render(body: Frame, keep: Vector2?, redraw: () -> ())
	local touch = UIKit.IsTouch()
	local list = games()
	local known: { [string]: boolean } = {}
	for _, definition in list do
		known[definition.Id] = true
	end
	if not selected or not known[selected] then
		selected = firstPick(list)
	end
	local scale = UIKit.CurrentScale()
	local bodyWidth = if body.AbsoluteSize.X > 100 and scale > 0 then body.AbsoluteSize.X / scale else 940
	local rowWidth = math.floor(bodyWidth - SCROLL_ROOM)

	-- The header: the counts, and how points come.
	local headerH = 44
	local header = UIKit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, headerH),
		BackgroundTransparency = 1,
		Parent = body,
		Children = {
			UIKit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
		},
	})
	local profile = State.Profile
	local mastery = profile and profile.Mastery
	for order, id in { "Gold", "Diamond", "Legend" } do
		local index = MasteryLogic.IndexOf(Mastery.Ranks, id)
		local count = MasteryLogic.CountAt(mastery, Mastery.Ranks, index, known)
		local text = `{count} {Mastery.Name(index)}`
		local width = math.ceil(UIKit.TextWidth(text, 20, Theme.Fonts.Display) * 1.06) + 54
		local pill = UIKit.new("Frame", {
			Name = id,
			Size = UDim2.fromOffset(width, 36),
			BackgroundColor3 = Theme.Colors.PanelDark,
			LayoutOrder = order,
			Parent = header,
			Children = { UIKit.Round(), UIKit.Stroke(Mastery.Look(index).Top, 2, 0) },
		})
		Mastery.Badge(
			index,
			30,
			{ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Parent = pill }
		)
		UIKit.Label({
			Text = text,
			Font = Theme.Fonts.Display,
			TextSize = 20,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(40, 0),
			Size = UDim2.new(1, -44, 1, 0),
			Parent = pill,
			Children = { UIKit.TextStroke(0.2) },
		})
	end
	UIKit.Label({
		Name = "How",
		Text = if touch
			then "Points every round, more on the podium"
			else "Points every round, more on the podium. ×2 on Spotlight games!",
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0, math.max(100, rowWidth - 3 * 150 - 24), 1, 0),
		LayoutOrder = 10,
		Parent = header,
	})

	local scroll = UIKit.new("ScrollingFrame", {
		Name = "Mastery",
		Position = UDim2.fromOffset(0, headerH + 6),
		Size = UDim2.new(1, 0, 1, -(headerH + 6)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = if touch then 6 else 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
		Children = {
			UIKit.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left),
			UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }),
		},
	})
	local picked = GameDefinitions.Get(selected or "")
	if picked then
		detail(scroll, picked, 0)
	end
	local spotlight = {}
	for _, id in Mastery.Spotlight() do
		local definition = GameDefinitions.Get(id)
		if definition and known[id] then
			table.insert(spotlight, definition)
		end
	end
	section(scroll, 10, "×2 TODAY'S SPOTLIGHT", spotlight, rowWidth, redraw)
	for index, category in CATEGORIES do
		local inCategory = {}
		local ranked = 0
		for _, definition in list do
			if definition.Category == category then
				table.insert(inCategory, definition)
				if Mastery.Progress(definition.Id).Rank > 0 then
					ranked += 1
				end
			end
		end
		section(
			scroll,
			10 + index * 10,
			`{string.upper(category)}  •  {ranked}/{#inCategory} ranked`,
			inCategory,
			rowWidth,
			redraw
		)
	end
	if keep then
		task.defer(function()
			if scroll.Parent then
				scroll.CanvasPosition = keep
			end
		end)
	end
end

return MasteryWall

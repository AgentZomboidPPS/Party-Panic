-- The Rewards screen's MASTERY tab (owner: "Let's build it. 1 yes 2 gold pass should help a little.
-- 3 yes"; Controllers/RewardsController shows it, the rules are Shared/Logic/MasteryLogic): every
-- game's rank on one wall.
--   * Along the top: how many games are GOLD, DIAMOND and LEGEND, and how points are earned.
--   * The game picked (a tap on its tile; at first, the one closest to its next rank): its rank, a
--     bar to the next, what that rank pays, and the rounds played and wins that count.
--   * Today's Spotlight games (double points), then every game by type, each a tile with its icon,
--     name, rank badge and bar; games not played yet are dimmed ("NEW").
-- Phones: tiles 124 units square or so (77 pt), text 11 pt or more; the list scrolls.
--
-- A trophy case (owner: "this has to be incredible and make players feel like they accomplished
-- something"): each tile is the game's own picture (the first frame of its vote-stage preview) under
-- a dark fade, framed in its rank's metal; GOLD and up catch the light now and then, LEGEND's frame
-- turns. The tile itself is the button (an invisible one laid over it covered its words). The picked
-- game's panel is a road of the five ranks, what each one pays and a tick on those reached, filled
-- to where the player is; the header shows the next title across every game ("ALL-ROUNDER 3/5").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local GameDefinitions = require(Shared.GameDefinitions)
local MasteryLogic = require(Shared.Logic.MasteryLogic)

local Mastery = require(script.Parent.Mastery)
local PartyKit = require(script.Parent.PartyKit)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local MasteryWall = {}

local TILE_W, TILE_H, GAP = 124, 128, 8
local DETAIL_H = 228
local PICTURE_W, PICTURE_H = 124, 176 -- the detail panel's picture (the previews are 168 x 240)
-- The titles across every game, in the order they come (Shared/Cosmetics): the header shows the next.
local TITLES = { "Title_AllRounder", "Title_DiamondPartier", "Title_PartyPro" }
local TITLE_STAT_RANK = { MasteryGold = "Gold", MasteryDiamond = "Diamond", MasteryLegend = "Legend" }
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

-- What a rank pays, a line each ("25 coins", "+2 keys"), for its step on the road.
local function paysLines(rank: MasteryLogic.Rank): { string }
	local parts = {}
	if rank.Coins > 0 then
		table.insert(parts, `{rank.Coins} coins`)
	end
	if rank.Keys > 0 then
		table.insert(parts, `+{rank.Keys} key{if rank.Keys == 1 then "" else "s"}`)
	end
	if rank.Crates > 0 then
		table.insert(parts, `+{rank.Crates} crate{if rank.Crates == 1 then "" else "s"}`)
	end
	return parts
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

-- The road of the five ranks across the panel's right: a badge for each, lit once reached (with a
-- tick), the next one ringed, what each pays under it, and a line filled to where the player is.
local function road(panel: Instance, progress: MasteryLogic.Progress, x: number, y: number)
	local count = #Mastery.Ranks
	local holder = UIKit.new("Frame", {
		Name = "Road",
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.new(1, -(x + 12), 0, 124),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	local badge = 40
	local step = 1 / count -- each rank's column, as a share of the road
	local function centre(index: number): UDim2
		return UDim2.new((index - 0.5) * step, 0, 0, badge / 2 + 2)
	end
	UIKit.new("Frame", {
		Name = "Line",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = centre(1),
		Size = UDim2.new((count - 1) * step, 0, 0, 8),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = holder,
		Children = { UIKit.Round(), UIKit.Stroke(Theme.Colors.Ink, 2, 0) },
	})
	-- (filled to the rank reached, and on toward the next as far as the player has come)
	local reach = math.max(0, progress.Rank - 1)
		+ (if progress.Rank > 0 and progress.Next then progress.Fraction else 0)
	if reach > 0 then
		UIKit.new("Frame", {
			Name = "Reached",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = centre(1),
			Size = UDim2.new(reach * step, 0, 0, 8),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = holder,
			Children = {
				UIKit.Round(),
				UIKit.new("UIGradient", { Color = Mastery.Gradient(math.min(progress.Rank + 1, count)) }),
			},
		})
	end
	for index, rank in Mastery.Ranks do
		local reached = index <= progress.Rank
		local isNext = index == progress.Rank + 1
		local medal = Mastery.Badge(index, badge, {
			Name = rank.Id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = centre(index),
			ZIndex = 3,
			Parent = holder,
		}, not reached)
		if reached then
			UIKit.Label({
				Name = "Tick",
				Text = "✓",
				Font = Theme.Fonts.Display,
				TextSize = Theme.Touch.MinText,
				TextWrapped = false,
				TextColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0,
				BackgroundColor3 = Theme.Colors.Green,
				KeepEmoji = true,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -2, 1, -2),
				Size = UDim2.fromOffset(24, 24),
				ZIndex = 4,
				Parent = medal,
				Children = { UIKit.Round(), UIKit.Stroke(Theme.Colors.Ink, 2, 0) },
			})
		elseif isNext then
			local ring = UIKit.new("Frame", {
				Name = "Next",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = centre(index),
				Size = UDim2.fromOffset(badge + 10, badge + 10),
				BackgroundTransparency = 1,
				ZIndex = 2,
				Parent = holder,
				Children = { UIKit.Round() },
			})
			local stroke = UIKit.Stroke(Theme.Colors.Yellow, 3, 0)
			stroke.Parent = ring
			PartyKit.Loop(stroke, 0.9, { Transparency = 0.7, Thickness = 5 })
		end
		local column = UDim2.new(step, -6, 0, 22)
		UIKit.Label({
			Name = rank.Id .. "Name",
			Text = rank.Name,
			Font = Theme.Fonts.Display,
			TextSize = Theme.Touch.MinText,
			TextWrapped = false,
			TextColor3 = if reached or isNext then Mastery.Look(index).Top else Theme.Colors.TextDim,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new((index - 0.5) * step, 0, 0, badge + 6),
			Size = column,
			Parent = holder,
			Children = { UIKit.TextStroke(0.1) },
		})
		local lines = paysLines(rank)
		if #lines == 0 then
			lines = { "First round" }
		end
		local pays = UIKit.Label({
			Name = rank.Id .. "Pays",
			Text = table.concat(lines, "\n"),
			TextSize = Theme.Touch.MinText,
			TextWrapped = false,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = if reached then Theme.Colors.TextDim else Theme.Colors.Yellow,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new((index - 0.5) * step, 0, 0, badge + 28),
			Size = UDim2.new(step, -6, 0, 3 * (Theme.Touch.MinText + 1)),
			Parent = holder,
			Children = { UIKit.TextStroke(0.3) },
		})
		pays:SetAttribute("PP_Lines", #lines)
	end
end

local function detail(parent: Instance, definition: GameDefinitions.GameDefinition, order: number)
	local entry = Mastery.Entry(definition.Id)
	local progress = Mastery.Progress(definition.Id)
	local look = Mastery.Look(progress.Rank)
	local panel = UIKit.Panel({
		Name = "Detail",
		Size = UDim2.new(1, -SCROLL_ROOM, 0, DETAIL_H),
		LayoutOrder = order,
		CornerRadius = 18,
		Parent = parent,
	}, definition.Color, darker(definition.Color, 0.45))
	-- The game's picture in its rank's frame, the badge on its corner.
	local frame = UIKit.new("Frame", {
		Name = "Frame",
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(PICTURE_W, PICTURE_H),
		BackgroundColor3 = darker(definition.Color, 0.3),
		Parent = panel,
		Children = { UIKit.Corner(14) },
	})
	local rim = UIKit.Stroke(if progress.Rank > 0 then look.Top else Theme.Colors.Ink, 4, 0)
	rim.Parent = frame
	local picture = Mastery.Picture(definition.Id, { Size = UDim2.fromScale(1, 1), Parent = frame })
	if picture then
		UIKit.Corner(14).Parent = picture
	else
		UIKit.Label({
			Name = "Icon",
			Text = definition.Icon,
			TextSize = 64,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			Parent = frame,
		})
	end
	if progress.Rank >= 3 then
		PartyKit.Shine(frame, nil, { Period = 2.2, ZIndex = frame.ZIndex + 1 })
	end
	if progress.Rank >= #Mastery.Ranks then
		PartyKit.SpinBorder(frame, PartyKit.RimColors(look.Top), 4)
	end
	Mastery.Badge(progress.Rank, 58, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -10, 1, -10),
		ZIndex = frame.ZIndex + 2,
		Parent = frame,
	})

	local left = 14 + PICTURE_W + 26
	local spotlight = Mastery.IsSpotlight(definition.Id)
	UIKit.Label({
		Name = "Game",
		Text = string.upper(definition.Name),
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(left, 10),
		Size = UDim2.new(1, -(left + (if spotlight then 150 else 16)), 0, 38),
		Parent = panel,
		Children = { UIKit.TextStroke(0.1) },
	})
	if spotlight then
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
	local rounds = if entry then entry.N else 0
	local wins = if entry then entry.W else 0
	local rankText = if progress.Rank == 0 then "NOT RANKED YET" else `{Mastery.Name(progress.Rank)} RANK`
	UIKit.Label({
		Name = "Rank",
		Text = rankText,
		Font = Theme.Fonts.Display,
		TextSize = 22,
		TextWrapped = false,
		TextColor3 = if progress.Rank > 0 then look.Top else Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(left, 46),
		Size = UDim2.fromOffset(math.ceil(UIKit.TextWidth(rankText, 22, Theme.Fonts.Display) * 1.06) + 6, 26),
		Parent = panel,
		Children = { UIKit.TextStroke(0) },
	})
	local rankWidth = math.ceil(UIKit.TextWidth(rankText, 22, Theme.Fonts.Display) * 1.06) + 6
	UIKit.Label({
		Name = "Played",
		Text = if rounds == 0
			then "Your first round makes you BRONZE!"
			else `{rounds} round{if rounds == 1 then "" else "s"}  •  {wins} win{if wins == 1 then "" else "s"} that count`,
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(left + rankWidth + 12, 46),
		Size = UDim2.new(1, -(left + rankWidth + 28), 0, 26),
		Parent = panel,
	})
	road(panel, progress, left - 8, 74)
	-- The next goal, with the bar's numbers, at the bottom.
	local goal
	if not progress.Next then
		goal = `The top rank! You're a LEGEND at {string.upper(definition.Name)}.`
	elseif progress.Short == "Wins" then
		goal = `Next: {MasteryLogic.Goal(progress)} ({MasteryLogic.BarText(progress)}, with 3+ real players)`
	else
		goal = `Next: {MasteryLogic.Goal(progress)} ({MasteryLogic.BarText(progress)})`
	end
	UIKit.Label({
		Name = "Goal",
		Text = goal,
		Font = Theme.Fonts.Display,
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(left, DETAIL_H - 30),
		Size = UDim2.new(1, -(left + 16), 0, 24),
		Parent = panel,
		Children = { UIKit.TextStroke(0.2) },
	})
end

-- A game's tile, the button that picks it: its picture under a dark fade, framed in its rank's metal
-- (GOLD and up shine now and then, LEGEND's frame turns), the badge in the corner, the name and the
-- bar at the bottom. A game not played yet is dimmed with "NEW" on its bar.
local function tile(parent: Instance, definition: GameDefinitions.GameDefinition, order: number, redraw: () -> ())
	local progress = Mastery.Progress(definition.Id)
	local played = Mastery.Entry(definition.Id) ~= nil
	local picked = selected == definition.Id
	local look = Mastery.Look(progress.Rank)
	local frame = UIKit.new("TextButton", {
		Name = definition.Id,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(TILE_W, TILE_H),
		BackgroundColor3 = if played then darker(definition.Color, 0.55) else Theme.Colors.PanelDark,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = parent,
		Children = { UIKit.Corner(16) },
	})
	local picture = Mastery.Picture(definition.Id, {
		Size = UDim2.fromScale(1, 1),
		ImageColor3 = if played then Color3.new(1, 1, 1) else Color3.fromRGB(120, 112, 150),
		ImageTransparency = if played then 0 else 0.25,
		Parent = frame,
	})
	if picture then
		UIKit.Corner(16).Parent = picture
	else
		UIKit.Label({
			Name = "Icon",
			Text = definition.Icon,
			TextSize = 40,
			TextWrapped = false,
			TextTransparency = if played then 0 else 0.35,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 14),
			Size = UDim2.fromOffset(56, 50),
			Parent = frame,
		})
	end
	-- (the dark fade the name reads on)
	UIKit.new("Frame", {
		Name = "Fade",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.66),
		BackgroundColor3 = Color3.fromRGB(16, 8, 34),
		Parent = frame,
		Children = {
			UIKit.Corner(16),
			UIKit.new("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.45, 0.45),
					NumberSequenceKeypoint.new(1, 0.1),
				}),
			}),
		},
	})
	local rim = UIKit.Stroke(
		if picked then Color3.new(1, 1, 1) elseif progress.Rank > 0 then look.Top else Theme.Colors.Ink,
		if picked then 5 elseif progress.Rank > 0 then 3 else 2,
		0
	)
	rim.Parent = frame
	if progress.Rank >= #Mastery.Ranks then
		PartyKit.SpinBorder(frame, PartyKit.RimColors(look.Top), if picked then 5 else 4)
	end
	if progress.Rank >= 3 then
		-- (each tile on its own beat, so the case glints here and there rather than all at once)
		PartyKit.Shine(frame, nil, { Period = 2.4 + (order % 5) * 0.55, Strength = 0.45 })
	end
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
			Position = UDim2.fromOffset(6, 8),
			Size = UDim2.fromOffset(34, 24),
			Parent = frame,
			Children = { UIKit.Round(), UIKit.Stroke(Theme.Colors.Ink, 2, 0) },
		})
	end
	Mastery.Badge(progress.Rank, 38, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -5, 0, 5),
		Parent = frame,
	})
	local name = UIKit.Label({
		Name = "Game",
		Text = definition.Name,
		Font = Theme.Fonts.Display,
		TextSize = Theme.Touch.MinText,
		TextColor3 = if played then Color3.new(1, 1, 1) else Theme.Colors.TextDim,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 6, 1, -32),
		Size = UDim2.new(1, -12, 0, 42),
		Parent = frame,
		Children = { UIKit.TextStroke(0.1) },
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
	frame.Activated:Connect(function()
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
	-- The next title across every game (Shared/Cosmetics): its name and how far along, the pill filling
	-- up as it comes.
	local used = 0
	for _, child in header:GetChildren() do
		if child:IsA("Frame") then
			used += child.Size.X.Offset + 8
		end
	end
	local title, have = nil, 0
	for _, id in TITLES do
		local cosmetic = Cosmetics.Get(id)
		local unlock = cosmetic and cosmetic.UnlockStat
		local rankId = unlock and TITLE_STAT_RANK[unlock.Stat]
		if cosmetic and unlock and rankId then
			local count =
				MasteryLogic.CountAt(mastery, Mastery.Ranks, MasteryLogic.IndexOf(Mastery.Ranks, rankId), known)
			if count < unlock.Value then
				title, have = cosmetic, count
				break
			end
		end
	end
	local titleText = if title
		then `{title.Icon} {string.upper(title.Name)}  {have}/{(title.UnlockStat :: any).Value}`
		else "🏆 EVERY TITLE EARNED!"
	local titleWidth = math.ceil(UIKit.TextWidth(titleText, 20, Theme.Fonts.Display) * 1.06) + 52
	local titlePill = UIKit.new("Frame", {
		Name = "NextTitle",
		Size = UDim2.fromOffset(titleWidth, 36),
		BackgroundColor3 = Theme.Colors.PanelDark,
		ClipsDescendants = true,
		LayoutOrder = 5,
		Parent = header,
		Children = { UIKit.Round(), UIKit.Stroke(Theme.Colors.Yellow, 2, 0) },
	})
	local share = if title then have / math.max(1, (title.UnlockStat :: any).Value) else 1
	if share > 0 then
		UIKit.new("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(share, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.25,
			Parent = titlePill,
			Children = {
				UIKit.Round(),
				UIKit.new("UIGradient", {
					Color = ColorSequence.new(Color3.fromRGB(255, 196, 60), Color3.fromRGB(230, 110, 30)),
				}),
			},
		})
	end
	UIKit.Label({
		Name = "Text",
		Text = titleText,
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = titlePill,
		Children = { UIKit.TextStroke(0.1) },
	})
	used += titleWidth + 8
	-- How points come, in the room that's left (shorter on a narrow window, left out if there's none).
	local room = rowWidth - used
	local how = "Points every round, more on the podium. ×2 on Spotlight games!"
	if UIKit.TextWidth(how, Theme.Touch.MinText, Theme.Fonts.Bold) * 1.06 > room then
		how = "More points on the podium, ×2 on Spotlight!"
	end
	if UIKit.TextWidth(how, Theme.Touch.MinText, Theme.Fonts.Bold) * 1.06 > room then
		how = "×2 on Spotlight games!"
	end
	if UIKit.TextWidth(how, Theme.Touch.MinText, Theme.Fonts.Bold) * 1.06 <= room then
		UIKit.Label({
			Name = "How",
			Text = how,
			TextSize = Theme.Touch.MinText,
			TextWrapped = false,
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0, math.floor(room), 1, 0),
			LayoutOrder = 10,
			Parent = header,
		})
	end

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

-- The Rewards screen and the next goal on the HUD (owner: "Also we need cool payoffs for players
-- that keep playing the game."):
--   * Beside the coins, a pink tab shows the next exclusive reward ("🌌 Lv 10: Starry Night"; phones:
--     "🌌 Lv 10"), so there's always a next goal on screen; tapping the profile chip opens the screen.
--     The level badge takes the prestige tier's colors (every 10 levels; the top tier shimmers).
--   * The Rewards screen has two tabs. LEVEL ROAD: a strip of cards to swipe through, one per
--     level (every level pays coins; milestone levels unlock cosmetics nobody can buy), each ribbon
--     in the colors that level gives your name tag; it opens on your next level. CAREER: lifetime
--     milestones (rounds, wins, podiums, every game, days played) with progress bars.
--   Unlocked rewards can be equipped right there. The server owns all of it: this only shows the
--   profile it sends (Shared/Progression has the road, the milestones and the colors).
-- Phones: 44 pt buttons and 11 pt or bigger text; the road's cards fit the shortest phone window.
-- State.OpenScreen:Fire("Rewards", "Career") opens it on a tab.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local GameState = require(Shared.GameState)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local RewardsController = {}

local touch = false
local modal: Modal.Modal
local body: Frame
local tabButtons: { [string]: TextButton } = {}
local currentTab = "Road"

local CARD_W, CARD_GAP = 180, 12
local CARD_H = 282 -- phones: fits the road on the shortest phone window (800x360)
local PC_CARD_H = 330
local HEADER_H = 44

local PINK_DARK = Color3.fromRGB(200, 50, 140)
local CYAN_DARK = Color3.fromRGB(50, 120, 230)
local GREEN_DARK = Color3.fromRGB(60, 160, 90)

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Scrolls a list once its canvas has grown to fit what was just put in it (the next layout pass).
local function scrollWhenLaidOut(list: ScrollingFrame, position: Vector2)
	local layout = list:FindFirstChildOfClass("UIListLayout")
	task.spawn(function()
		for _ = 1, 30 do
			if not list.Parent or not layout or layout.AbsoluteContentSize.Magnitude > 0 then
				break
			end
			task.wait()
		end
		if list.Parent then
			list.CanvasPosition = position
		end
	end)
end

local function level(): number
	local profile = State.Profile
	return if profile then profile.Level or 1 else 1
end

local function slotName(item: Cosmetics.Cosmetic): string
	return string.upper(Cosmetics.SlotNames[item.Slot] or item.Slot)
end

-- The button (or note) for an unlocked item: equip it, take it off, or where it went.
local function ownedAction(parent: Instance, item: Cosmetics.Cosmetic, props: { [string]: any }): GuiObject
	local profile = State.Profile
	if Cosmetics.IsEquipSlot(item.Slot) then
		local equipped = profile and profile.Equipped[item.Slot] == item.Id
		props.Text = if equipped then "EQUIPPED ✓" else "EQUIP"
		props.Parent = parent
		return UIKit.Button(props, function()
			Remotes.Get("ShopEquip"):FireServer(item.Slot, if equipped then "" else item.Id)
		end, if equipped then Theme.Colors.Green else Theme.Colors.Cyan, if equipped then GREEN_DARK else CYAN_DARK)
	end
	props.Text = if item.Slot == "Emote" then "✓ IN EMOTES" else "✓ UNLOCKED"
	props.Font = Theme.Fonts.Display
	props.TextColor3 = Theme.Colors.Green
	props.TextWrapped = false
	props.Parent = parent
	return UIKit.Label(props)
end

-- HUD: the next reward beside the coins, and the badge's colors ------------------------------------

local function buildNextTab(context)
	local holder = context.Hud:FindFirstChild("ProfileChip")
	local coins = holder and holder:FindFirstChild("Coins")
	if not holder or not coins or not coins:IsA("GuiObject") then
		return
	end
	local height = if touch then 42 else 46
	local tab = UIKit.Panel({
		Name = "NextReward",
		Position = UDim2.fromOffset(0, coins.Position.Y.Offset),
		Size = UDim2.fromOffset(100, height),
		CornerRadius = if touch then 18 else 23,
		ZIndex = 1,
		Visible = false,
		Parent = holder,
	}, Theme.Colors.Pink, PINK_DARK)
	local stroke = tab:FindFirstChildOfClass("UIStroke") :: UIStroke
	-- Phones: the coins tab's top is tucked under the pill, so the text sits in its visible part.
	local label = UIKit.Label({
		Text = "",
		RichText = not touch,
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(if touch then 10 else 16, if touch then 10 else 0),
		Size = UDim2.new(1, if touch then -14 else -22, 0, if touch then 32 else height),
		Parent = tab,
		Children = { UIKit.TextStroke(0.2) },
	})
	local holderWidth = holder.Size.X.Offset

	local function refresh()
		local profile = State.Profile
		if not profile then
			tab.Visible = false
			return
		end
		local current = profile.Level or 1
		local nextLevel = Progression.NextItemLevel(current)
		local item = nextLevel and Progression.ItemsAt(nextLevel)[1]
		local plain
		if item and nextLevel then
			plain = if touch then `{item.Icon} Lv {nextLevel}` else `NEXT  {item.Icon} Lv {nextLevel}: {item.Name}`
			label.Text = if touch
				then plain
				else `<font color="#{Theme.Colors.Yellow:ToHex()}">NEXT</font>  {item.Icon} Lv {nextLevel}: {item.Name}`
		else
			plain = if touch then "👑 MAX" else "👑 Every level reward unlocked!"
			label.Text = plain
		end
		local left = coins.Position.X.Offset + coins.Size.X.Offset + (if touch then 6 else 8)
		local width = math.ceil(UIKit.TextWidth(plain, 20, Theme.Fonts.Display)) + (if touch then 22 else 34)
		if touch and left + width > holderWidth + 2 then
			-- A long coin number: just the reward's icon, or nothing if even that doesn't fit.
			plain = if item then item.Icon else "👑"
			label.Text = plain
			width = 44
		end
		tab.Size = UDim2.fromOffset(width, height)
		tab.Position = UDim2.fromOffset(left, coins.Position.Y.Offset)
		-- One level to go: a gold rim.
		local close = nextLevel ~= nil and nextLevel == current + 1
		stroke.Color = if close then Theme.Colors.Yellow else Theme.Colors.Stroke
		stroke.Thickness = if close then 3 else 2
		stroke.Transparency = if close then 0 else 0.75
		local phase = GameState.Get("Phase") or "Waiting"
		tab.Visible = phase ~= "InRound" and not (touch and left + width > holderWidth + 2)
	end
	State.ProfileChanged:Connect(function(profile, previous)
		refresh()
		if previous and profile.Level ~= previous.Level then
			UIKit.PopIn(tab, 0.5)
		end
	end)
	coins:GetPropertyChangedSignal("Size"):Connect(refresh)
	GameState.Changed("Phase", refresh)
	task.delay(3, refresh) -- again once the font has surely loaded
	refresh()
end

local function followBadge(context)
	local holder = context.Hud:FindFirstChild("ProfileChip")
	local badge = holder and holder:FindFirstChild("LevelBadge", true)
	local gradient = badge and badge:FindFirstChildOfClass("UIGradient")
	if not gradient then
		return
	end
	local rainbow = false
	State.ProfileChanged:Connect(function(profile)
		local look = Progression.Look(profile.Level or 1)
		gradient.Color = look.Gradient
		rainbow = look.Rainbow
		if not rainbow then
			gradient.Rotation = 90
		end
	end)
	-- The top tier's badge slowly turns its rainbow (not with reduced effects).
	RunService.Heartbeat:Connect(function()
		if rainbow and not State.ReducedEffects() then
			gradient.Rotation = (os.clock() * 45) % 360
		end
	end)
end

-- The Rewards screen: Level Road --------------------------------------------------------------------

local function header(parent: Instance)
	local profile = State.Profile
	local current = level()
	local look = Progression.Look(current)
	local row = UIKit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, HEADER_H),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local badge = UIKit.new("Frame", {
		Size = UDim2.fromOffset(HEADER_H, HEADER_H),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = row,
		Children = {
			UIKit.Round(),
			UIKit.new("UIGradient", { Color = look.Gradient, Rotation = 90 }),
			UIKit.Stroke(nil, 2, 0.3),
		},
	})
	UIKit.Label({
		Text = tostring(current),
		Font = Theme.Fonts.Display,
		TextSize = 22,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
		Children = { UIKit.TextStroke(0.2) },
	})
	local need = if profile then profile.LevelNeed or 0 else 0
	local into = if profile then profile.LevelXP or 0 else 0
	local bar = UIKit.new("Frame", {
		Position = UDim2.fromOffset(HEADER_H + 10, 9),
		Size = UDim2.fromOffset(250, 26),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = row,
		Children = { UIKit.Round() },
	})
	UIKit.new("Frame", {
		Size = UDim2.fromScale(if need > 0 then math.clamp(into / need, 0, 1) else 1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = bar,
		Children = { UIKit.Round(), UIKit.Gradient(Theme.Colors.Cyan, Theme.Colors.Green, 0) },
	})
	UIKit.Label({
		Text = if need > 0 then `{into} / {need} XP to Lv {current + 1}` else "MAX LEVEL",
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = bar,
		Children = { UIKit.TextStroke(0.3) },
	})
	local nextLook = Progression.NextLook(current)
	UIKit.Label({
		Text = if nextLook
			then `Next name tag color: {nextLook.Icon} {nextLook.Name} at Lv {nextLook.Level}`
			else `Top name tag color: {look.Icon} {look.Name}!`,
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 0),
		Size = UDim2.new(1, -(HEADER_H + 280), 1, 0),
		Parent = row,
	})
end

-- The first card: how the road works.
local function introCard(parent: Instance, height: number)
	local card = UIKit.Panel({
		Name = "Intro",
		Size = UDim2.fromOffset(CARD_W + 30, height),
		LayoutOrder = 0,
		CornerRadius = 18,
		Parent = parent,
	}, Color3.fromRGB(150, 110, 255), Color3.fromRGB(90, 60, 190))
	UIKit.Label({
		Text = "YOUR ROAD",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextWrapped = false,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 32),
		Parent = card,
		Children = { UIKit.TextStroke(0.2) },
	})
	local lines = {
		`💰 Every level pays coins, every 5th pays more`,
		"🎁 Big levels unlock rewards you can't buy",
		"🎨 Every 10 levels: a new name tag color",
	}
	for index, text in lines do
		UIKit.Label({
			Text = text,
			TextSize = Theme.Touch.MinText,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(14, 50 + (index - 1) * ((height - 64) / 3)),
			Size = UDim2.new(1, -24, 0, (height - 64) / 3),
			Parent = card,
		})
	end
end

local function levelCard(
	parent: Instance,
	order: number,
	cardLevel: number,
	item: Cosmetics.Cosmetic?,
	coins: number,
	height: number
)
	local profile = State.Profile
	local current = level()
	local reached = current >= cardLevel
	local isNext = cardLevel == current + 1
	local look = Progression.Look(cardLevel)
	local card = UIKit.Panel({
		Name = `Level{cardLevel}` .. (if item then "_" .. item.Id else ""),
		Size = UDim2.fromOffset(CARD_W, height),
		LayoutOrder = order,
		CornerRadius = 18,
		Parent = parent,
	}, if reached then Theme.Colors.Card else Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	if isNext then
		local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = Theme.Colors.Yellow
		stroke.Thickness = 4
		stroke.Transparency = 0
	end

	-- The ribbon wears the colors this level gives your name tag.
	local ribbon = UIKit.new("Frame", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 0, 34),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
		Children = { UIKit.Round(), UIKit.new("UIGradient", { Color = look.Gradient, Rotation = 0 }) },
	})
	UIKit.Label({
		Text = `LEVEL {cardLevel}`,
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = ribbon,
		Children = { UIKit.TextStroke(0.15) },
	})

	-- Top to bottom: ribbon, icon, name (two lines), what it is, its coins, (PC: what it does), button.
	local iconTop = if touch then 46 else 48
	local iconHeight = if touch then 56 else 64
	local nameTop = iconTop + iconHeight + 2
	if item then
		UIKit.Label({
			Text = item.Icon,
			TextSize = if touch then 46 else 52,
			TextWrapped = false,
			Position = UDim2.fromOffset(0, iconTop),
			Size = UDim2.new(1, 0, 0, iconHeight),
			Parent = card,
		})
	else
		UIKit.Coin({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, iconTop + iconHeight / 2),
			Size = UDim2.fromOffset(46, 46),
			Parent = card,
		})
	end
	local name = UIKit.Label({
		Text = if item then item.Name else `+{coins} coins`,
		Font = Theme.Fonts.Display,
		TextSize = 20,
		Position = UDim2.fromOffset(8, nameTop),
		Size = UDim2.new(1, -16, 0, 44),
		Parent = card,
		Children = { UIKit.TextStroke(0.3) },
	})
	name:SetAttribute("PP_Lines", 2) -- "Rainbow Fireworks" takes two lines on a card
	local lines = {}
	if item then
		table.insert(lines, { slotName(item), Theme.Colors.TextDim })
		if coins > 0 then
			table.insert(lines, { `+{coins} {Theme.CoinIcon}`, Theme.Colors.Yellow })
		end
	elseif cardLevel % 5 == 0 then
		table.insert(lines, { "BONUS LEVEL!", Theme.Colors.Yellow })
	end
	for index, line in lines do
		UIKit.Label({
			Text = line[1],
			TextSize = Theme.Touch.MinText,
			TextWrapped = false,
			TextColor3 = line[2],
			Position = UDim2.fromOffset(8, nameTop + 44 + (index - 1) * 22),
			Size = UDim2.new(1, -16, 0, 22),
			Parent = card,
		})
	end
	if not touch and item then
		UIKit.Label({
			Text = item.Description,
			TextSize = 16,
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(8, nameTop + 92),
			Size = UDim2.new(1, -16, 0, 62),
			Parent = card,
		})
	end

	local actionHeight = if touch then Theme.Touch.Target else 48
	local props = {
		Name = "Action",
		TextSize = if touch then 20 else 18,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -16, 0, actionHeight),
		CornerRadius = 14,
	}
	if reached and item and profile and profile.Owned[item.Id] then
		ownedAction(card, item, props)
	else
		local text
		if reached then
			text = "✓ COLLECTED"
		elseif isNext and profile and (profile.LevelNeed or 0) > 0 then
			text = `{math.max(0, profile.LevelNeed - profile.LevelXP)} XP TO GO`
		else
			text = `🔒 LEVEL {cardLevel}`
		end
		props.Text = text
		props.Font = Theme.Fonts.Display
		props.TextWrapped = false
		props.TextColor3 = if reached
			then Theme.Colors.Green
			elseif isNext then Theme.Colors.Yellow
			else Theme.Colors.TextDim
		props.Parent = card
		UIKit.Label(props)
	end
end

-- `keep`: where to scroll (a redraw keeps the place); else the next level.
local function renderRoad(keep: Vector2?)
	header(body)
	local height = if touch then CARD_H else PC_CARD_H
	local road = UIKit.new("ScrollingFrame", {
		Name = "Road",
		Position = UDim2.fromOffset(0, HEADER_H + 8),
		Size = UDim2.new(1, 0, 1, -(HEADER_H + 8)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = if touch then 6 else 8,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = body,
		Children = {
			UIKit.List(
				Enum.FillDirection.Horizontal,
				CARD_GAP,
				Enum.HorizontalAlignment.Left,
				Enum.VerticalAlignment.Top
			),
			UIKit.new("UIPadding", {
				PaddingLeft = UDim.new(0, 4),
				PaddingRight = UDim.new(0, 4),
				PaddingTop = UDim.new(0, 4),
			}),
		},
	})
	introCard(road, height)
	local current = level()
	local order, focus = 0, 0
	for _, cardLevel in Progression.RoadLevels() do
		local items = Progression.ItemsAt(cardLevel)
		local coins = Progression.Coins(cardLevel)
		if #items == 0 then
			order += 1
			levelCard(road, order, cardLevel, nil, coins, height)
		else
			for index, item in items do
				order += 1
				levelCard(road, order, cardLevel, item, if index == 1 then coins else 0, height)
			end
		end
		if focus == 0 and cardLevel > current then
			focus = order
		end
	end
	-- Open on the next level: it's the second card in view (the one before it shows where you are).
	local target = 0
	if focus > 1 then
		target = 4 + (CARD_W + 30 + CARD_GAP) + (focus - 2) * (CARD_W + CARD_GAP)
	end
	scrollWhenLaidOut(road, keep or Vector2.new(target, 0))
end

-- The Rewards screen: Career ---------------------------------------------------------------------

local function milestoneRow(parent: Instance, order: number, item: Cosmetics.Cosmetic)
	local profile = State.Profile
	local owned = profile ~= nil and profile.Owned[item.Id] == true
	local have, target = Progression.MilestoneProgress(item, profile and profile.Stats)
	local rowHeight = if touch then 100 else 88
	local right = 214
	local row = UIKit.Panel({
		Name = item.Id,
		Size = UDim2.new(1, -8, 0, rowHeight),
		LayoutOrder = order,
		CornerRadius = 16,
		Parent = parent,
	}, if owned then Theme.Colors.Card else Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	UIKit.Label({
		Text = item.Icon,
		TextSize = 42,
		TextWrapped = false,
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(0, 70, 1, 0),
		Parent = row,
	})
	UIKit.Label({
		Text = item.Name,
		Font = Theme.Fonts.Display,
		TextSize = 22,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(86, 8),
		Size = UDim2.new(1, -(86 + right), 0, 28),
		Parent = row,
		Children = { UIKit.TextStroke(0.3) },
	})
	UIKit.Label({
		Text = `{item.Description}  ({string.lower(Cosmetics.SlotNames[item.Slot] or item.Slot)})`,
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(86, 36),
		Size = UDim2.new(1, -(86 + right), 0, 24),
		Parent = row,
	})
	local bar = UIKit.new("Frame", {
		Position = UDim2.fromOffset(86, rowHeight - 34),
		Size = UDim2.new(1, -(86 + right), 0, 22),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = row,
		Children = { UIKit.Round() },
	})
	UIKit.new("Frame", {
		Size = UDim2.fromScale(if owned then 1 else math.clamp(have / math.max(1, target), 0, 1), 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = bar,
		Children = { UIKit.Round(), UIKit.Gradient(Theme.Colors.Yellow, Theme.Colors.Orange, 0) },
	})
	UIKit.Label({
		Text = if owned then "DONE!" else `{have} / {target}`,
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = bar,
		Children = { UIKit.TextStroke(0.2) },
	})
	local props = {
		Name = "Action",
		TextSize = if touch then 20 else 18,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(right - 24, if touch then Theme.Touch.Target else 50),
		CornerRadius = 14,
	}
	if owned then
		ownedAction(row, item, props)
	else
		props.Text = `🔒 {math.floor(100 * have / math.max(1, target))}%`
		props.Font = Theme.Fonts.Display
		props.TextWrapped = false
		props.TextColor3 = Theme.Colors.TextDim
		props.Parent = row
		UIKit.Label(props)
	end
end

local function renderCareer(keep: Vector2?)
	local profile = State.Profile
	local list = UIKit.new("ScrollingFrame", {
		Name = "Career",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = if touch then 6 else 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 10), UIKit.Padding(4) },
	})
	-- Closest to unlocking first; unlocked ones at the end.
	local items = table.clone(Progression.Milestones)
	local function ratio(item: Cosmetics.Cosmetic): number
		if profile and profile.Owned[item.Id] then
			return 2
		end
		local have, target = Progression.MilestoneProgress(item, profile and profile.Stats)
		return have / math.max(1, target)
	end
	local ratios = {}
	for index, item in items do
		ratios[item.Id] = { ratio(item), index }
	end
	table.sort(items, function(a, b)
		local ra, rb = ratios[a.Id], ratios[b.Id]
		local doneA, doneB = ra[1] > 1, rb[1] > 1
		if doneA ~= doneB then
			return doneB
		elseif not doneA and ra[1] ~= rb[1] then
			return ra[1] > rb[1]
		end
		return ra[2] < rb[2]
	end)
	local unlocked = 0
	for _, item in items do
		if profile and profile.Owned[item.Id] then
			unlocked += 1
		end
	end
	UIKit.Label({
		Text = `🏅 {unlocked} of {#items} milestones unlocked. Keep partying!`,
		Font = Theme.Fonts.Display,
		TextSize = 22,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -8, 0, 32),
		LayoutOrder = 0,
		Parent = list,
	})
	for order, item in items do
		milestoneRow(list, order, item)
	end
	if keep then
		scrollWhenLaidOut(list, keep)
	end
end

local function render(keep: Vector2?)
	if not modal.IsOpen then
		return
	end
	clear(body)
	for key, button in tabButtons do
		local gradient = button:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = if key == currentTab
				then ColorSequence.new(Theme.Colors.Pink, PINK_DARK)
				else ColorSequence.new(Theme.Colors.PanelLight, Theme.Colors.PanelDark)
		end
	end
	if not State.Profile then
		return
	end
	if currentTab == "Career" then
		renderCareer(keep)
	else
		renderRoad(keep)
	end
end

function RewardsController.Start(context)
	touch = UIKit.IsTouch()
	buildNextTab(context)
	followBadge(context)

	modal = Modal.new(context.Overlay, "Rewards", "🎁", Vector2.new(980, 620))
	local content = modal.Content
	local title = Modal.TitleHeight()
	body = UIKit.new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = content,
	})
	-- The tabs, in the title bar after the title.
	local tabHeight = if touch then Theme.Touch.Target else 50
	for index, tab in { { Key = "Road", Text = "⭐ Level Road" }, { Key = "Career", Text = "🏅 Career" } } do
		tabButtons[tab.Key] = UIKit.Button({
			Name = tab.Key .. "Tab",
			Text = tab.Text,
			TextSize = 22,
			Position = UDim2.fromOffset(220 + (index - 1) * 206, -(title + 6) + (title - tabHeight) / 2 + 2),
			Size = UDim2.fromOffset(194, tabHeight),
			CornerRadius = 16,
			ZIndex = 25,
			Parent = content,
		}, function()
			currentTab = tab.Key
			render()
		end, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	end

	State.OpenScreen:Connect(function(name, tab)
		if name ~= "Rewards" then
			return
		end
		if type(tab) == "string" and tabButtons[tab] then
			currentTab = tab
			if modal.IsOpen then
				render()
				return
			end
		elseif not modal.IsOpen then
			currentTab = "Road"
		end
		modal:Toggle()
	end)
	modal.Opened:Connect(function()
		render()
	end)
	State.ProfileChanged:Connect(function()
		if modal.IsOpen then
			-- Redrawn with the new profile, scrolled where it was.
			local list = body:FindFirstChildOfClass("ScrollingFrame")
			render(if list then list.CanvasPosition else nil)
		end
	end)
end

return RewardsController

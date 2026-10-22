-- The Rewards screen and the next goal on the HUD (owner: "Also we need cool payoffs for players
-- that keep playing the game."):
--   * Beside the coins, a pink tab shows the next exclusive reward ("🌌 Lv 10: Starry Night"; phones:
--     "🌌 Lv 10"), so there's always a next goal on screen; tapping the profile chip or the tab opens
--     the screen.
--     The level badge takes the prestige tier's colors (every 10 levels; the top tier shimmers).
--   * The Rewards screen has two tabs. LEVEL ROAD: a strip of cards to swipe through, one per
--     level (every level pays coins; milestone levels unlock cosmetics nobody can buy), each ribbon
--     in the colors that level gives your name tag; it opens on your next level. CAREER: lifetime
--     milestones (rounds, wins, podiums, every game, days played) with progress bars.
--   Unlocked rewards can be equipped right there. The server owns all of it: this only shows the
--   profile it sends (Shared/Progression has the road, the milestones and the colors).
-- Phones: 44 pt buttons and 11 pt or bigger text; the road's cards fit the shortest phone window.
-- State.OpenScreen:Fire("Rewards", "Career") opens it on a tab.
-- Second pass: CAREER lists the quickest milestones first (5 race podiums before 30 days), the
-- same order the celebration's "Next:" goal uses (Progression.SortedMilestones).
-- Medals (owner, asked what keeps players coming back: "Medals: a medal for winning each game and a
-- few big ones, Roblox badges, a collect-them-all wall in the lobby", then: "Can you work on all of
-- that? this wont mess with what the other workers are working on right?"): a third tab, MEDALS,
-- is the collect-them-all screen (Controllers/MedalController draws it); the medal wall's prompt and
-- the MEDAL EARNED card's SEE ALL open the screen on it (State.OpenScreen:Fire("Rewards", "Medals")).
-- The PUMPKIN HAT (owner: "do pumpkin hat now"): while a limited-time event is on, its headline
-- reward (Shared/Events' Headline) stands beside the road on a card of its own, with the candy it
-- takes (a tap opens the event screen) or EQUIP once it's yours; afterwards it stays for whoever has
-- it.
-- The GOLD PASS (owner: "Also we do need a paid battle pass too. I like the current free one. But the
-- paid one should also be insane."): every level of the road is a column with two lanes, FREE on
-- top (as before: coins, and at milestone levels a reward nobody can buy) and GOLD under it (a gold
-- reward at every level from 2 to 100: a cosmetic, or gold coins; Shared/GoldPass), each lane named
-- at the road's left. A tile is one reward: its icon, its name, what it is and its state; a tap
-- equips it (EQUIP / EQUIPPED, like the free lane's). Before the pass is theirs, the gold tiles are a
-- softer gold with a 🔒 and the header's big shining GET GOLD PASS button (with Roblox's price;
-- "N REWARDS READY" for what buying it unlocks at once) shows Roblox's purchase prompt, as does a
-- tap on a gold tile; while the pass is off sale on Roblox both say COMING SOON. An owner sees the
-- gold lane lit, their gold count in the header, a gold level badge (here and on the HUD) and gold
-- goals in the next-reward tab. Phones: the header and both lanes fit the shortest phone window;
-- tiles and buttons are 44 pt or more, text 11 pt or more.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local EventLogic = require(Shared.Logic.EventLogic)
local Events = require(Shared.Events)
local GameState = require(Shared.GameState)
local GoldPass = require(Shared.GoldPass)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local GoldPassController = require(script.Parent.GoldPassController)
local MedalController = require(script.Parent.MedalController)
local NotificationController = require(script.Parent.NotificationController)
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

-- Phones: how far right of the profile chip's left edge the next-reward tab may reach (scaled
-- units): the top-middle vote cards and tip start about 215 units in on the narrowest phone.
local TOUCH_TAB_REACH = 208
local CARD_W, CARD_GAP = 180, 12
local LANE_W = 60 -- the lanes' names at the road's left (FREE, GOLD)
-- The road makes a level's content when it scrolls this near the view (scaled units).
local FILL_BEHIND, FILL_AHEAD = 400, 1500
local GOLD = GoldPass.Colors

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

-- A note where a button would be (same place and size; labels have no corner radius).
local function statusLabel(props: { [string]: any }): TextLabel
	props.CornerRadius = nil
	return UIKit.Label(props)
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
	return statusLabel(props)
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
	-- The whole pill opens the Rewards screen. PC: it's a see-through button over the pill (the pill
	-- reaches past the profile chip's own button), with the words on it. Phones: the chip's button
	-- grows to cover the pill instead (a button of the pill's height would be too small for a thumb).
	local baseWidth = holder.Size.X.Offset
	local face: GuiObject = tab
	if not touch then
		local open = UIKit.new("TextButton", {
			Name = "Open",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = tab,
		})
		open.Activated:Connect(function()
			State.OpenScreen:Fire("Rewards")
		end)
		face = open
	end
	-- Phones: the coins tab's top is tucked under the pill, so the text sits in its visible part.
	local textSize = if touch then 18 else 20
	local label = UIKit.Label({
		Text = "",
		RichText = not touch,
		Font = Theme.Fonts.Display,
		TextSize = textSize,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(if touch then 10 else 16, if touch then 10 else 0),
		Size = UDim2.new(1, if touch then -14 else -22, 0, if touch then 32 else height),
		ZIndex = 2,
		Parent = face,
		Children = { UIKit.TextStroke(0.2) },
	})
	local function refresh()
		local profile = State.Profile
		if not profile then
			tab.Visible = false
			return
		end
		local current = profile.Level or 1
		local nextLevel, item = Progression.NextReward(current, GoldPassController.Owned())
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
		local width = math.ceil(UIKit.TextWidth(plain, textSize, Theme.Fonts.Display)) + (if touch then 22 else 34)
		if touch and left + width > TOUCH_TAB_REACH then
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
		tab.Visible = phase ~= "InRound" and not (touch and left + width > TOUCH_TAB_REACH)
		if touch then
			local reach = if tab.Visible then left + width else 0
			holder.Size = UDim2.fromOffset(math.max(baseWidth, reach), holder.Size.Y.Offset)
		end
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
	local stroke = badge:FindFirstChildOfClass("UIStroke")
	local glint: Frame? = nil
	State.ProfileChanged:Connect(function(profile)
		local look = Progression.Look(profile.Level or 1)
		if GoldPassController.Owned() then
			-- A GOLD PASS owner's badge is gold, with a shining rim and a glint now and then.
			gradient.Color = GoldPassController.Fill().Color
			gradient.Rotation = 90
			rainbow = false
			if stroke then
				stroke.Color, stroke.Thickness, stroke.Transparency = GOLD.Shine, 3, 0
			end
			if not glint then
				local band = GoldPassController.Glint(badge)
				glint = band
				for _, child in badge:GetChildren() do
					if child:IsA("TextLabel") then
						child.ZIndex = math.max(child.ZIndex, band.ZIndex + 1)
					end
				end
			end
			return
		end
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

-- The road's sizes (scaled units). Phones: the header and both lanes fit the shortest phone window
-- (800 x 360: 360 units under the title bar); PC: taller tiles, with each reward's description.
type Metrics = {
	Header: number, -- the row with the level, XP bar and the GOLD PASS button
	Ribbon: number, -- a level's ribbon ("LEVEL 12")
	LaneTop: number, -- where the free lane starts in a level's column
	Tile: number, -- each lane's height
	LaneGap: number,
	Card: number, -- a level's column, both lanes
}

local function metrics(): Metrics
	local ribbon, tile, gap = if touch then 28 else 34, if touch then 112 else 200, if touch then 6 else 8
	local laneTop = ribbon + (if touch then 4 else 6)
	return {
		Header = if touch then 76 else 64,
		Ribbon = ribbon,
		LaneTop = laneTop,
		Tile = tile,
		LaneGap = gap,
		Card = laneTop + 2 * tile + gap,
	}
end

-- Text on gold: a dark ink outline.
local function ink(transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = GOLD.Ink,
		Thickness = 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

-- The GOLD PASS at the header's right: GET GOLD PASS with its price (a tap shows Roblox's purchase
-- prompt), COMING SOON while it's off sale on Roblox, or how much of the gold lane an owner has.
local function goldAction(parent: Instance, m: Metrics)
	local owned = GoldPassController.Owned()
	local onSale = GoldPassController.OnSale()
	local reached = Progression.GoldRewardCount(level())
	local height = if touch then Theme.Touch.Target else 56
	local buy = not owned and onSale
	local props = {
		Name = "GoldPass",
		Text = "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0, m.Header / 2),
		Size = UDim2.fromOffset(if touch then 340 else 330, height),
		CornerRadius = 20,
		Parent = parent,
	}
	local holder: GuiObject
	if buy then
		holder = UIKit.Button(props, GoldPassController.Prompt, GOLD.Gold, GOLD.Deep)
	else
		props.Text = nil
		props.CornerRadius = nil
		holder = UIKit.new("Frame", props)
		holder.BackgroundColor3 = Color3.new(1, 1, 1)
		UIKit.Corner(20).Parent = holder
	end
	local fill = holder:FindFirstChildOfClass("UIGradient")
	if fill then
		fill:Destroy()
	end
	GoldPassController.Fill().Parent = holder
	local rim = holder:FindFirstChildOfClass("UIStroke") or UIKit.new("UIStroke", { Parent = holder })
	rim.Color = GOLD.Shine
	rim.Thickness = 3
	rim.Transparency = 0
	GoldPassController.Glint(holder, 20)
	if buy and not State.ReducedEffects() then
		-- Its bright rim breathes, so the eye finds it.
		TweenService
			:Create(
				rim,
				TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Thickness = 6 }
			)
			:Play()
	end
	local title = if owned
		then `{GoldPass.Icon} GOLD PASS ✓`
		elseif buy then `{GoldPass.Icon} GET GOLD PASS`
		else `{GoldPass.Icon} GOLD PASS`
	local note
	if owned then
		note = `{reached} / {Progression.GoldTotals.Rewards} GOLD REWARDS`
	elseif not onSale then
		note = "COMING SOON"
	elseif reached > 0 then
		note = `{reached} REWARD{if reached == 1 then "" else "S"} READY`
	else
		note = "A REWARD EVERY LEVEL"
	end
	-- The price (Roblox's), in a dark tag at the right of the button.
	local priceWidth = if buy then (if touch then 96 else 90) else 0
	if buy then
		local tag = UIKit.new("Frame", {
			Name = "Price",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(priceWidth - 10, if touch then 44 else 38),
			BackgroundColor3 = Color3.fromRGB(60, 30, 4),
			BackgroundTransparency = 0.15,
			ZIndex = 3,
			Parent = holder,
			Children = { UIKit.Round(), UIKit.new("UIStroke", { Color = GOLD.Light, Thickness = 1.5 }) },
		})
		UIKit.Label({
			Text = `R$ {GoldPassController.Price()}`,
			Font = Theme.Fonts.Display,
			TextSize = if touch then 20 else 19,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Parent = tag,
		})
	end
	UIKit.Label({
		Name = "Title",
		Text = title,
		Font = Theme.Fonts.Display,
		TextSize = if touch then 24 else 23,
		TextWrapped = false,
		TextXAlignment = if buy then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(12, if touch then 7 else 4),
		Size = UDim2.new(1, -(24 + priceWidth), 0, if touch then 32 else 30),
		ZIndex = 3,
		Parent = holder,
		Children = { ink() },
	})
	UIKit.Label({
		Name = "Note",
		Text = note,
		Font = Theme.Fonts.Display,
		TextSize = if touch then Theme.Touch.MinText else 17,
		TextWrapped = false,
		TextColor3 = GOLD.Shine,
		TextXAlignment = if buy then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(12, if touch then 40 else 33),
		Size = UDim2.new(1, -(24 + priceWidth), 0, if touch then 24 else 20),
		ZIndex = 3,
		Parent = holder,
		Children = { ink(0.1) },
	})
end

local function header(parent: Instance, m: Metrics)
	local profile = State.Profile
	local current = level()
	local look = Progression.Look(current)
	local gold = GoldPassController.Owned()
	local row = UIKit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, m.Header),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	-- The level badge in the level's prestige colors; gold, with a glint, for a GOLD PASS owner.
	local badgeSize = if touch then 60 else 52
	local badge = UIKit.new("Frame", {
		Name = "LevelBadge",
		Position = UDim2.fromOffset(0, (m.Header - badgeSize) / 2),
		Size = UDim2.fromOffset(badgeSize, badgeSize),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = row,
		Children = { UIKit.Round() },
	})
	if gold then
		GoldPassController.Fill().Parent = badge
		UIKit.new("UIStroke", { Color = GOLD.Shine, Thickness = 3, Transparency = 0, Parent = badge })
		GoldPassController.Glint(badge)
	else
		UIKit.new("UIGradient", { Color = look.Gradient, Rotation = 90, Parent = badge })
		UIKit.Stroke(nil, 2, 0.3).Parent = badge
	end
	UIKit.Label({
		Text = tostring(current),
		Font = Theme.Fonts.Display,
		TextSize = if touch then 26 else 24,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = badge,
		Children = { if gold then ink() else UIKit.TextStroke(0.2) },
	})
	local need = if profile then profile.LevelNeed or 0 else 0
	local into = if profile then profile.LevelXP or 0 else 0
	local barX = badgeSize + 12
	local bar = UIKit.new("Frame", {
		Position = UDim2.fromOffset(barX, if touch then 8 else 6),
		Size = UDim2.fromOffset(270, if touch then 28 else 26),
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
		Name = "NextColor",
		Text = if nextLook
			then `Next name tag color: {nextLook.Icon} {nextLook.Name} at Lv {nextLook.Level}`
			else `Top name tag color: {look.Icon} {look.Name}!`,
		TextSize = if touch then Theme.Touch.MinText else 16,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(barX + 2, if touch then 42 else 36),
		Size = UDim2.fromOffset(340, if touch then 26 else 22),
		Parent = row,
	})
	goldAction(row, m)
end

-- The lanes' names at the road's left, beside each lane: ⭐ FREE and 👑 GOLD.
local function laneLabels(parent: Instance, x: number, m: Metrics)
	local top = m.Header + 8 + m.LaneTop
	for index, lane in { { Icon = "⭐", Text = "FREE" }, { Icon = GoldPass.Icon, Text = "GOLD" } } do
		local gold = index == 2
		local panel = UIKit.new("Frame", {
			Name = `{lane.Text}Lane`,
			Position = UDim2.fromOffset(x, top + (index - 1) * (m.Tile + m.LaneGap)),
			Size = UDim2.fromOffset(LANE_W, m.Tile),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = parent,
			Children = {
				UIKit.Corner(14),
				if gold then GoldPassController.Fill() else UIKit.Gradient(Theme.Colors.Pink, PINK_DARK),
				UIKit.new("UIStroke", {
					Color = if gold then GOLD.Ink else Theme.Colors.Stroke,
					Thickness = 2,
					Transparency = if gold then 0.2 else 0.6,
				}),
			},
		})
		UIKit.Label({
			Text = lane.Icon,
			TextSize = if touch then 28 else 26,
			TextWrapped = false,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 34),
			Parent = panel,
		})
		UIKit.Label({
			Text = lane.Text,
			Font = Theme.Fonts.Display,
			TextSize = if touch then Theme.Touch.MinText else 16,
			TextWrapped = false,
			Position = UDim2.new(0, 0, 0.5, 2),
			Size = UDim2.new(1, 0, 0, 24),
			Parent = panel,
			Children = { if gold then ink() else UIKit.TextStroke(0.2) },
		})
	end
end

-- What one tile of a level shows and does.
type Tile = {
	Name: string,
	Icon: string, -- its emoji (coins: 💰)
	Caption: string, -- what it is ("TRAIL", "COINS")
	Description: string?, -- PC
	Status: string, -- the line at its bottom ("EQUIP", "✓ COLLECTED", "🔒 GOLD PASS")
	StatusColor: Color3,
	Pill: { Color3 }?, -- a filled pill for the status (an action): top and bottom colours
	OnClick: (() -> ())?,
	Gold: boolean,
	Locked: boolean, -- a gold reward the player doesn't have the pass for: the lock in the corner
	Lit: boolean, -- reached (and theirs): drawn bright
	Equipped: boolean,
}

local function drawTile(parent: Instance, x: number, y: number, w: number, h: number, tile: Tile)
	local top, bottom
	if tile.Gold then
		top, bottom = GOLD.Light, GOLD.Deep
	else
		top, bottom = if tile.Lit then Theme.Colors.Card else Theme.Colors.PanelLight, Theme.Colors.PanelDark
	end
	-- A tile that does something is a button, its whole face (44 pt and more on phones).
	local props = {
		Name = tile.Name,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		CornerRadius = 16,
		Parent = parent,
	}
	local frame: GuiObject
	if tile.OnClick then
		props.Text = ""
		frame = UIKit.Button(props, tile.OnClick, top, bottom)
	else
		frame = UIKit.Panel(props, top, bottom)
	end
	if tile.Gold then
		local fill = frame:FindFirstChildOfClass("UIGradient")
		if fill then
			fill:Destroy()
		end
		local gradient = GoldPassController.Fill()
		if tile.Locked then
			-- A locked reward is a softer gold (no glint): it lights up once it's theirs.
			gradient.Color = ColorSequence.new(GOLD.LockedTop, GOLD.LockedBottom)
		end
		gradient.Parent = frame
	end
	local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
	if tile.Equipped then
		stroke.Color, stroke.Thickness, stroke.Transparency = Theme.Colors.Green, 3, 0
	elseif tile.Gold then
		stroke.Color, stroke.Thickness, stroke.Transparency = GOLD.Ink, 2, 0.25
	end
	if tile.Gold and tile.Lit and not tile.Locked then
		GoldPassController.Glint(frame, 16)
	end

	-- Phones: the icon at the left, the name and what it is beside it, the status underneath. PC:
	-- the icon on top, then the name, what it is, its description and the status. Text outlines are
	-- the labels' own, so a tile stays light: the road has dozens.
	local inkColor = if tile.Gold then GOLD.Ink else Color3.fromRGB(30, 15, 60)
	local icon = UIKit.Label({
		Name = "Icon",
		Text = tile.Icon,
		TextSize = if touch then 38 else 46,
		TextWrapped = false,
		Position = if touch then UDim2.fromOffset(4, 8) else UDim2.fromOffset(0, 6),
		Size = if touch then UDim2.fromOffset(52, 52) else UDim2.new(1, 0, 0, 56),
		ZIndex = 2,
		Parent = frame,
	})
	if tile.Locked then
		-- A padlock on the icon's corner (clear of the words beside it on a phone).
		UIKit.Label({
			Name = "Lock",
			Text = "🔒",
			TextSize = if touch then Theme.Touch.MinText else 16,
			TextWrapped = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = if touch then UDim2.new(1, -14, 1, -10) else UDim2.new(0.5, 26, 1, -16),
			Size = UDim2.fromOffset(if touch then 24 else 28, if touch then 24 else 28),
			BackgroundColor3 = Color3.fromRGB(70, 36, 6),
			BackgroundTransparency = 0.15,
			ZIndex = 3,
			Parent = icon,
			Children = { UIKit.Round() },
		})
	end
	local textLeft = if touch then 58 else 8
	local textWidth = if touch then w - 64 else w - 16
	local align = if touch then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	local name = UIKit.Label({
		Name = "Title",
		Text = tile.Name,
		Font = Theme.Fonts.Display,
		TextSize = if touch then 18 else 20,
		TextXAlignment = align,
		TextStrokeColor3 = inkColor,
		TextStrokeTransparency = if tile.Gold then 0.1 else 0.4,
		Position = UDim2.fromOffset(textLeft, if touch then 6 else 60),
		Size = UDim2.fromOffset(textWidth, if touch then 44 else 48),
		ZIndex = 2,
		Parent = frame,
	})
	name:SetAttribute("PP_Lines", 2) -- "Rainbow Fireworks" takes two lines on a tile
	UIKit.Label({
		Name = "Caption",
		Text = tile.Caption,
		Font = Theme.Fonts.Display,
		TextSize = if touch then Theme.Touch.MinText else 15,
		TextWrapped = false,
		TextColor3 = if tile.Gold then GOLD.Ink else Theme.Colors.TextDim,
		TextXAlignment = align,
		Position = UDim2.fromOffset(textLeft, if touch then 50 else 108),
		Size = UDim2.fromOffset(textWidth, if touch then 22 else 20),
		ZIndex = 2,
		Parent = frame,
	})
	if not touch and tile.Description then
		UIKit.Label({
			Name = "Description",
			Text = tile.Description,
			TextSize = 14,
			TextColor3 = if tile.Gold then GOLD.Ink else Theme.Colors.TextDim,
			Position = UDim2.fromOffset(8, 128),
			Size = UDim2.new(1, -16, 0, 34),
			ZIndex = 2,
			Parent = frame,
		})
	end
	-- The status: a filled pill when it's an action (EQUIP), else words on a soft band.
	local status = UIKit.Label({
		Name = "Status",
		Text = tile.Status,
		Font = Theme.Fonts.Display,
		TextSize = if touch then Theme.Touch.MinText else 17,
		TextWrapped = false,
		TextColor3 = tile.StatusColor,
		TextStrokeTransparency = 0.5,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -12, 0, if touch then 28 else 30),
		BackgroundColor3 = if tile.Pill then Color3.new(1, 1, 1) else Color3.new(0, 0, 0),
		BackgroundTransparency = if tile.Pill then 0 else (if tile.Gold then 0.72 else 0.6),
		ZIndex = 2,
		Parent = frame,
		Children = { UIKit.Round() },
	})
	if tile.Pill then
		UIKit.Gradient(tile.Pill[1], tile.Pill[2]).Parent = status
	end
end

-- The status of a reward the player can't have yet: XP TO GO on the next level, else its level.
local function lockedStatus(cardLevel: number): (string, Color3)
	local profile = State.Profile
	if cardLevel == level() + 1 and profile and (profile.LevelNeed or 0) > 0 then
		return `{math.max(0, profile.LevelNeed - profile.LevelXP)} XP TO GO`, Theme.Colors.Yellow
	end
	return `🔒 LEVEL {cardLevel}`, Theme.Colors.TextDim
end

-- One reward's tile: an item (free or gold), or a level's coins (`item` nil).
local function rewardTile(cardLevel: number, item: Cosmetics.Cosmetic?, coins: number, gold: boolean): Tile
	local profile = State.Profile
	local reached = level() >= cardLevel
	local hasPass = GoldPassController.Owned()
	local theirs = reached and (not gold or hasPass)
	local tile: Tile = {
		Name = if item then item.Name else `+{coins} coins`,
		Icon = if item then item.Icon else Theme.CoinIcon,
		Caption = if item then slotName(item) elseif gold then "GOLD COINS" else "COINS",
		Description = if item
			then item.Description
			elseif gold then "Gold coins for reaching this level."
			else "Every level pays coins.",
		Status = "",
		StatusColor = Theme.Colors.TextDim,
		Gold = gold,
		Locked = gold and not hasPass,
		Lit = theirs,
		Equipped = false,
	}
	if gold and not hasPass then
		-- Locked behind the pass: a tap buys it (or says it's coming).
		if GoldPassController.OnSale() then
			tile.Status = if reached then "🔓 GET IT NOW" else "🔒 GOLD PASS"
			tile.StatusColor = if reached then GOLD.Shine else GOLD.Light
			tile.OnClick = GoldPassController.Prompt
		else
			tile.Status, tile.StatusColor = "🔒 COMING SOON", GOLD.Light
			tile.OnClick = function()
				NotificationController.Show(`{GoldPass.Icon} The GOLD PASS is coming soon!`, "info", 4)
			end
		end
	elseif not reached then
		tile.Status, tile.StatusColor = lockedStatus(cardLevel)
	elseif item and profile and profile.Owned[item.Id] then
		if Cosmetics.IsEquipSlot(item.Slot) then
			local equipped = profile.Equipped[item.Slot] == item.Id
			tile.Equipped = equipped
			tile.Status = if equipped then "EQUIPPED ✓" else "EQUIP"
			tile.StatusColor = Theme.Colors.Text
			tile.Pill = if equipped then { Theme.Colors.Green, GREEN_DARK } else { Theme.Colors.Cyan, CYAN_DARK }
			tile.OnClick = function()
				Remotes.Get("ShopEquip"):FireServer(item.Slot, if equipped then "" else item.Id)
			end
		else
			tile.Status, tile.StatusColor = "✓ IN EMOTES", Theme.Colors.Green
		end
	else
		tile.Status, tile.StatusColor = "✓ COLLECTED", Theme.Colors.Green
	end
	return tile
end

-- One level's column: its ribbon (in the colors that level gives your name tag, with the free coins
-- of a level that has a free reward), the free lane and the gold lane. A lane with two rewards
-- shows both side by side (level 10's trail and title; level 100's crown and title). The column is
-- made at once (the road's width is right), its content when it scrolls near (`build`).
local function levelColumn(parent: Instance, order: number, cardLevel: number, m: Metrics): (number, () -> ())
	local freeItems = Progression.ItemsAt(cardLevel)
	local goldItems = Progression.GoldItemsAt(cardLevel)
	local slots = math.max(1, #freeItems, #goldItems)
	local width = slots * CARD_W + (slots - 1) * CARD_GAP
	local column = UIKit.new("Frame", {
		Name = `Level{cardLevel}`,
		Size = UDim2.fromOffset(width, m.Card),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	local function build()
		if cardLevel == level() + 1 then
			-- The next level: a gold-yellow rim round both lanes.
			UIKit.new("Frame", {
				Name = "NextRim",
				Position = UDim2.fromOffset(2, m.LaneTop - 2),
				Size = UDim2.new(1, -4, 0, m.Card - m.LaneTop + 1),
				BackgroundTransparency = 1,
				Parent = column,
				Children = { UIKit.Corner(18), UIKit.new("UIStroke", { Color = Theme.Colors.Yellow, Thickness = 3 }) },
			})
		end
		local coins = Progression.Coins(cardLevel)
		local badge = #freeItems > 0 and coins > 0
		local ribbon = UIKit.Label({
			Name = "Ribbon",
			Text = `LEVEL {cardLevel}`,
			Font = Theme.Fonts.Display,
			TextSize = if touch then 20 else 21,
			TextWrapped = false,
			TextXAlignment = if badge then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.3,
			Size = UDim2.new(1, 0, 0, m.Ribbon),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0,
			Parent = column,
			Children = {
				UIKit.Round(),
				UIKit.new("UIGradient", { Color = Progression.Look(cardLevel).Gradient, Rotation = 0 }),
				UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, if badge then 12 else 0) }),
			},
		})
		if badge then
			-- The free coins this level pays besides its reward.
			UIKit.Label({
				Name = "Coins",
				Text = `+{coins} {Theme.CoinIcon}`,
				Font = Theme.Fonts.Display,
				TextSize = Theme.Touch.MinText,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextStrokeTransparency = 0.3,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 0),
				Size = UDim2.new(0, 80, 1, 0),
				Parent = ribbon,
			})
		end
		local function lane(items: { Cosmetics.Cosmetic }, y: number, gold: boolean)
			if #items == 0 then
				local laneCoins = if gold then Progression.GoldCoins(cardLevel) else coins
				drawTile(column, 0, y, width, m.Tile, rewardTile(cardLevel, nil, laneCoins, gold))
				return
			end
			local tileW = (width - (#items - 1) * CARD_GAP) / #items
			for index, item in items do
				drawTile(
					column,
					(index - 1) * (tileW + CARD_GAP),
					y,
					tileW,
					m.Tile,
					rewardTile(cardLevel, item, 0, gold)
				)
			end
		end
		lane(freeItems, m.LaneTop, false)
		lane(goldItems, m.LaneTop + m.Tile + m.LaneGap, true)
	end
	return width, build
end

-- The first column: how each lane works.
local function introColumn(parent: Instance, m: Metrics): number
	local width = 2 * CARD_W + CARD_GAP
	local column = UIKit.new("Frame", {
		Name = "Intro",
		Size = UDim2.fromOffset(width, m.Card),
		BackgroundTransparency = 1,
		LayoutOrder = 0,
		Parent = parent,
	})
	local ribbon = UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, m.Ribbon),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = column,
		Children = { UIKit.Round(), UIKit.Gradient(Theme.Colors.Pink, Theme.Colors.Purple, 0) },
	})
	UIKit.Label({
		Text = "YOUR ROAD",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 20 else 21,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = ribbon,
		Children = { UIKit.TextStroke(0.15) },
	})
	local total = Progression.GoldTotals
	local lanes = {
		{
			Title = "⭐ FREE ROAD",
			Lines = {
				"💰 Coins every level, more every 5th",
				"🎁 Big levels: rewards nobody can buy",
				"🎨 Every 10 levels: a new name tag color",
			},
		},
		{
			Title = `{GoldPass.Icon} GOLD PASS`,
			Lines = {
				"🎁 A gold reward at EVERY level",
				`✨ {total.Items} cosmetics + {total.Coins} gold coins`,
				"⚡ GOLD name tag, gold badge, +10% XP",
			},
		},
	}
	for index, info in lanes do
		local gold = index == 2
		local panel = UIKit.Panel({
			Name = if gold then "GoldIntro" else "FreeIntro",
			Position = UDim2.fromOffset(0, m.LaneTop + (index - 1) * (m.Tile + m.LaneGap)),
			Size = UDim2.new(1, 0, 0, m.Tile),
			CornerRadius = 16,
			Parent = column,
		}, Color3.fromRGB(150, 110, 255), Color3.fromRGB(90, 60, 190))
		if gold then
			panel:FindFirstChildOfClass("UIGradient"):Destroy()
			GoldPassController.Fill().Parent = panel
			local stroke = panel:FindFirstChildOfClass("UIStroke") :: UIStroke
			stroke.Color, stroke.Transparency = GOLD.Ink, 0.25
			GoldPassController.Glint(panel, 16)
		end
		local lineHeight = if touch then 24 else (m.Tile - 52) / 3
		UIKit.Label({
			Text = info.Title,
			Font = Theme.Fonts.Display,
			TextSize = if touch then 19 else 20,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, if touch then 4 else 10),
			Size = UDim2.new(1, -24, 0, 28),
			ZIndex = 2,
			Parent = panel,
			Children = { if gold then ink() else UIKit.TextStroke(0.2) },
		})
		for line, text in info.Lines do
			UIKit.Label({
				Text = text,
				TextSize = if touch then Theme.Touch.MinText else 17,
				TextWrapped = false,
				TextColor3 = if gold then GOLD.Ink else Theme.Colors.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(14, (if touch then 32 else 46) + (line - 1) * lineHeight),
				Size = UDim2.new(1, -24, 0, lineHeight),
				ZIndex = 2,
				Parent = panel,
			})
		end
	end
	return width
end

-- The limited-time event's headline reward to show beside the road: while its event is on, or for
-- whoever has it. Also whether the event is on.
local function headline(): (Cosmetics.Cosmetic?, Events.Event?, boolean)
	local state = GameState.GetJSON("Event")
	local profile = State.Profile
	for _, event in Events.List do
		local item = event.Headline and Cosmetics.Get(event.Headline)
		local on = type(state) == "table" and state.Id == event.Id
		if item and (on or (profile ~= nil and profile.Owned[item.Id] == true)) then
			return item, event, on
		end
	end
	return nil, nil, false
end

-- Its card, in the event's colours: where it's from, what it is, and the candy it takes or EQUIP.
-- As tall as the road's levels, both lanes.
local function headlineCard(parent: Instance, m: Metrics): boolean
	local item, event, on = headline()
	if not item or not event then
		return false
	end
	local profile = State.Profile
	local height = m.Card
	local card = UIKit.Panel({
		Name = "Headline",
		Position = UDim2.fromOffset(4, m.Header + 8),
		Size = UDim2.fromOffset(CARD_W, height),
		CornerRadius = 18,
		Parent = parent,
	}, Color3.fromRGB(255, 150, 50), Color3.fromRGB(150, 60, 170))
	local ribbon = UIKit.new("Frame", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 0, m.Ribbon),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
		Children = { UIKit.Round(), UIKit.Gradient(Color3.fromRGB(70, 40, 110), Color3.fromRGB(40, 20, 70), 0) },
	})
	UIKit.Label({
		Text = `{event.Icon} {event.Short}`,
		Font = Theme.Fonts.Display,
		TextSize = 18,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = ribbon,
		Children = { UIKit.TextStroke(0.15) },
	})
	local iconTop = m.Ribbon + (if touch then 12 else 16)
	local iconHeight = if touch then 48 else 64
	local nameTop = iconTop + iconHeight + 2
	UIKit.Label({
		Text = item.Icon,
		TextSize = if touch then 42 else 52,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, iconTop),
		Size = UDim2.new(1, 0, 0, iconHeight),
		Parent = card,
	})
	local name = UIKit.Label({
		Text = item.Name,
		Font = Theme.Fonts.Display,
		TextSize = 20,
		Position = UDim2.fromOffset(8, nameTop),
		Size = UDim2.new(1, -16, 0, 44),
		Parent = card,
		Children = { UIKit.TextStroke(0.25) },
	})
	name:SetAttribute("PP_Lines", 2)
	local step = EventLogic.Step(event.Track, item.Id)
	local owned = profile ~= nil and profile.Owned[item.Id] == true
	local lines = { { slotName(item), Color3.fromRGB(255, 236, 210) } }
	if on and step and not owned then
		table.insert(lines, { "FREE WITH CANDY", Theme.Colors.Yellow })
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
			Children = { UIKit.TextStroke(0.4) },
		})
	end
	if not touch then
		UIKit.Label({
			Text = item.Description,
			TextSize = 16,
			Position = UDim2.fromOffset(8, nameTop + 92),
			Size = UDim2.new(1, -16, 0, 62),
			Parent = card,
			Children = { UIKit.TextStroke(0.5) },
		})
	end
	local props = {
		Name = "Action",
		TextSize = if touch then 20 else 18,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -16, 0, if touch then Theme.Touch.Target else 48),
		CornerRadius = 14,
	}
	if owned then
		ownedAction(card, item, props)
	else
		-- The candy so far toward it, or CLAIM IT! once there's enough: both open the event screen.
		local saved = profile and profile.Events and profile.Events[event.Id]
		local candy = if type(saved) == "table" and type(saved.Candy) == "number" then saved.Candy else 0
		props.Text = if not step
			then "GET IT"
			elseif candy >= step.Candy then "CLAIM IT!"
			else `🍬 {candy}/{step.Candy}`
		props.Parent = card
		UIKit.Button(props, function()
			State.OpenScreen:Fire("Event")
		end, Theme.Colors.Yellow, Theme.Colors.Orange)
	end
	return true
end

-- `keep`: where to scroll (a redraw keeps the place); else the next level.
local function renderRoad(keep: Vector2?)
	local m = metrics()
	header(body, m)
	-- An event's headline reward stands at the road's left, where it stays in view; then the lanes'
	-- names, then the road.
	local left = if headlineCard(body, m) then CARD_W + CARD_GAP + 4 else 0
	laneLabels(body, left + 2, m)
	left += LANE_W + 10
	local road = UIKit.new("ScrollingFrame", {
		Name = "Road",
		Position = UDim2.fromOffset(left, m.Header + 4),
		Size = UDim2.new(1, -left, 1, -(m.Header + 4)),
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
				PaddingLeft = UDim.new(0, 2),
				PaddingRight = UDim.new(0, 4),
				PaddingTop = UDim.new(0, 4),
			}),
		},
	})
	-- Every level's column is made now (the road is as long as it should be); what's in it is made
	-- when it scrolls near, so a phone makes the few in view rather than dozens.
	local introWidth = introColumn(road, m)
	local x = 2 + introWidth + CARD_GAP
	local current = level()
	local target = 0
	local waiting = {}
	for order, cardLevel in Progression.RoadLevels(current) do
		if cardLevel <= current then
			target = x -- the last level reached starts the view; the next one is beside it
		end
		local width, build = levelColumn(road, order, cardLevel, m)
		table.insert(waiting, { From = x, To = x + width, Build = build })
		x += width + CARD_GAP
	end
	local function fill(at: number)
		for index = #waiting, 1, -1 do
			local column = waiting[index]
			if column.To >= at - FILL_BEHIND and column.From <= at + FILL_AHEAD then
				table.remove(waiting, index)
				column.Build()
			end
		end
	end
	-- Scroll positions are screen pixels, while the road is laid out in units the window's UIScale
	-- shrinks (0.62 on phones) or grows: pixels per unit are measured on the intro once it's laid out
	-- (until then, the screen's UI scale).
	local intro = road:FindFirstChild("Intro") :: GuiObject
	local function laidOut(): boolean
		return intro.AbsoluteSize.X > 0 and road.AbsoluteCanvasSize.X > 0
	end
	local function perUnit(): number
		return if intro.AbsoluteSize.X > 0 then intro.AbsoluteSize.X / introWidth else UIKit.CurrentScale()
	end
	road:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if laidOut() then
			fill(road.CanvasPosition.X / perUnit())
		end
	end)
	if keep then
		-- A redraw: the same place (the same window, so the same pixels).
		fill(keep.X / perUnit())
		scrollWhenLaidOut(road, keep)
		return
	end
	-- Opening: on the last level reached. The window grows in as it opens, so in pixels that place
	-- moves: it's set again while the window settles.
	fill(target)
	local function open()
		road.CanvasPosition = Vector2.new(target * perUnit(), 0)
	end
	local resized = intro:GetPropertyChangedSignal("AbsoluteSize"):Connect(open)
	local grown = road:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(open)
	task.delay(1, function()
		resized:Disconnect()
		grown:Disconnect()
	end)
	open()
end

-- The Rewards screen: Career ---------------------------------------------------------------------

local function milestoneRow(parent: Instance, order: number, item: Cosmetics.Cosmetic)
	local profile = State.Profile
	local owned = profile ~= nil and profile.Owned[item.Id] == true
	local have, target = Progression.MilestoneProgress(item, profile and profile.Stats)
	local rowHeight = if touch then 100 else 96 -- the progress bar sits under the description
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
		statusLabel(props)
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
	-- Closest to unlocking first (the quick ones before the long ones); unlocked ones at the end.
	local items = Progression.SortedMilestones(profile and profile.Owned, profile and profile.Stats)
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
	elseif currentTab == "Medals" then
		MedalController.Render(body, keep)
	else
		renderRoad(keep)
	end
end

function RewardsController.Start(context)
	touch = UIKit.IsTouch()
	buildNextTab(context)
	followBadge(context)

	-- As tall as the road's two lanes need: on phones that's about the shortest phone's window, so a
	-- bigger phone doesn't get an empty band under the lanes (Career and Medals scroll).
	modal = Modal.new(context.Overlay, "Rewards", "🎁", Vector2.new(980, if touch then 470 else 620))
	local content = modal.Content
	local title = Modal.TitleHeight()
	body = UIKit.new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = content,
	})
	-- The tabs, in the title bar after the title (the third ends 50 units short of the ✕ on phones).
	local tabHeight = if touch then Theme.Touch.Target else 50
	local tabs = {
		{ Key = "Road", Text = "⭐ Level Road" },
		{ Key = "Career", Text = "🏅 Career" },
		{ Key = "Medals", Text = "🥇 Medals" },
	}
	for index, tab in tabs do
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
	-- Built fresh on every open; nothing is kept around while the screen is closed.
	modal.Closed:Connect(function()
		clear(body)
	end)
	local function redraw()
		if modal.IsOpen then
			-- Redrawn with the new profile, scrolled where it was.
			local list = body:FindFirstChildOfClass("ScrollingFrame")
			render(if list then list.CanvasPosition else nil)
		end
	end
	State.ProfileChanged:Connect(redraw)
	GoldPassController.OfferChanged:Connect(redraw) -- the pass went on (or off) sale, or its price changed
end

return RewardsController

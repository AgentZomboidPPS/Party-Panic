-- Medals on screen (owner, asked what keeps players coming back: "Medals: a medal for winning each
-- game and a few big ones, Roblox badges, a collect-them-all wall in the lobby", then: "Can you work
-- on all of that? this wont mess with what the other workers are working on right?"):
--   * MEDAL EARNED! A card with the medal on its ribbon, its name and how many you have, with SEE
--     ALL (the medal screen) and ✕. Several medals at once make one card ("3 NEW MEDALS!"), and the
--     medals a returning player had already earned before medals existed make one card too
--     ("MEDALS UNLOCKED!"), never one each.
--   * The medal screen: the Rewards screen's MEDALS tab (RewardsController calls Render): every
--     medal in a grid with your count ("12 / 34"); the ones you have bright, with the day you earned
--     them; the others dimmed with a 🔒 and how to earn them. The medal wall's prompt in the lobby
--     opens it too.
--   * The medal wall (World/MedalWall): your own medals light up gold on it, on your screen only;
--     the others stay dark with their icons faded. Its plaque shows your count.
-- The server decides every medal (Services/MedalService); this only shows them.
--
-- A card waits for a calm moment, like the level-up cards (CelebrationController): never during the
-- vote, the rules card, the round or its results (it shows once everyone's back in the lobby), and
-- never over a level-up card: that goes first, and a medal card that's up when one comes in steps
-- aside and comes back after. It also waits for a window (the shop, the Rewards screen...) to close,
-- for a lobby game (Skee-Ball) to finish, and for the PARTY CUP's final podium (the player's
-- PP_CupPodium: the cup's champion gets CupChampion just then) and the results card
-- (PP_ResultsShowing) to clear; it steps aside if one of them comes up. While either of those two
-- is up nothing here opens a window (SEE ALL and the wall's prompt do nothing): opening one closes
-- any other, and would cut the podium short. A card closes itself after a few seconds, with its ✕,
-- when a window opens or when the vote starts; one that had barely shown comes back at the next
-- calm moment.
-- Phones: the card sits at the top middle (the spot the first-join tip, the lobby's chips and the
-- level-up card share: it sets PP_Celebrating while it's up, so the tip and the chips step aside),
-- clear of the profile chip, the menu column, the jump button and the toasts; its buttons are on its
-- right half (outside the thumbstick's corner) and 44 pt tall. PC: the middle of the screen.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local DailyLogic = require(Shared.Logic.DailyLogic)
local GameState = require(Shared.GameState)
local MedalLogic = require(Shared.Logic.MedalLogic)
local Medals = require(Shared.Medals)
local Remotes = require(Shared.Remotes)

local AudioController = require(script.Parent.AudioController)
local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local MedalController = {}

type Earned = { Id: string, Earlier: boolean }

local CALM = { Waiting = true, Intermission = true, Cleanup = true }
local SHOW_FOR = 7
local MIN_SHOW = 4 -- a card starts in the lobby only with at least this long before the vote
local BARELY = 3 -- a card closed by something else before this long comes back later
local LEVEL_UP_FIRST = 0.6 -- seconds into a calm moment before a card: a level-up card goes first
-- The card, in scaled units (phones: 0.62 points a unit, 372 x 134 pt).
local CARD_W, CARD_H = 600, 216
local DISC = 116
local TEXT_LEFT = 158
local CLOSE = Theme.Touch.Target
local BOTTOM_Y = 134
local SEE_W = 170
local PINK_DARK = Color3.fromRGB(200, 50, 140)
local GOLD_TOP, GOLD_BOTTOM = Color3.fromRGB(255, 236, 120), Color3.fromRGB(240, 150, 30)
local LOCKED_TOP, LOCKED_BOTTOM = Color3.fromRGB(120, 108, 165), Color3.fromRGB(70, 58, 115)
local CONFETTI = {
	Color3.fromRGB(255, 90, 140),
	Color3.fromRGB(90, 190, 255),
	Color3.fromRGB(255, 210, 70),
	Color3.fromRGB(150, 110, 255),
	Color3.fromRGB(110, 230, 140),
}
-- The wall: a medal you have is lit gold.
local LIT_DISC = Color3.fromRGB(240, 178, 40)
local WALL_LOCKED_DISC = Color3.fromRGB(92, 78, 140)
local WALL_LOCKED_RIBBON = Color3.fromRGB(120, 110, 150)

local player = Players.LocalPlayer
local touch = false
local gui: ScreenGui
local playerGui: Instance
local hud: Instance
local queue: { Earned } = {}
local closeCurrent: ((interrupted: boolean) -> ())? = nil
local windowOpen = false
local pumpQueued = false

-- Medals ------------------------------------------------------------------------------------------

local function owned(): { [string]: any }
	local profile = State.Profile
	return if profile and type(profile.Medals) == "table" then profile.Medals else {}
end

local function progressText(): string
	local have, total = MedalLogic.Progress(Medals.Catalog, owned())
	return `{have} / {total}`
end

-- Moments that have the screen and mustn't be cut short: the PARTY CUP's final podium
-- (PP_CupPodium) and the round's results card (PP_ResultsShowing). No card shows meanwhile, and
-- nothing here opens a window then (opening one closes any other, the podium included).
local SCREEN_TAKEN = { "PP_CupPodium", "PP_ResultsShowing" }

local function screenTaken(): boolean
	for _, attribute in SCREEN_TAKEN do
		if player:GetAttribute(attribute) == true then
			return true
		end
	end
	return false
end

-- Opens the medal screen (the Rewards screen's MEDALS tab), unless the podium or the results have
-- the screen.
local function openScreen()
	if not screenTaken() then
		State.OpenScreen:Fire("Rewards", "Medals")
	end
end

-- The level-up card (CelebrationController) is on screen, or has the spot.
local function celebrationShowing(): boolean
	local celebrate = playerGui:FindFirstChild("PartyPanicCelebrate")
	return celebrate ~= nil and celebrate:FindFirstChild("Celebration") ~= nil
end

local function setSpot(taken: boolean)
	-- The first-join tip and the lobby's chips give way while the card has their spot. A level-up
	-- card that took over keeps the flag up (it clears it itself).
	if taken or not celebrationShowing() then
		player:SetAttribute("PP_Celebrating", taken)
	end
end

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.ZIndex = props.ZIndex or 3
	return UIKit.Label(props)
end

-- The biggest text size (from `size` down to `smallest`) at which `text` fits `width` on one line.
local function fitSize(text: string, size: number, smallest: number, width: number, font: Enum.Font): number
	local fitted = size
	while fitted > smallest and UIKit.TextWidth(text, fitted, font) > width do
		fitted -= 2
	end
	return math.max(fitted, smallest)
end

-- A medal: a round disc in gold (or dimmed, locked) with its icon, as the card and the screen draw it.
local function medalDisc(parent: Instance, medal: Medals.Medal, size: number, have: boolean, props: { [string]: any })
	props.Name = props.Name or "Disc"
	props.Size = UDim2.fromOffset(size, size)
	props.BackgroundColor3 = Color3.new(1, 1, 1)
	props.Parent = parent
	props.Children = {
		UIKit.Round(),
		UIKit.Gradient(if have then GOLD_TOP else LOCKED_TOP, if have then GOLD_BOTTOM else LOCKED_BOTTOM),
		UIKit.new("UIStroke", {
			Color = if have then Color3.fromRGB(150, 85, 10) else Color3.fromRGB(40, 30, 80),
			Thickness = math.max(2, size / 28),
			Transparency = 0.1,
		}),
	}
	local disc = UIKit.new("Frame", props)
	label({
		Name = "Icon",
		Text = medal.Icon,
		TextSize = math.floor(size * 0.52),
		TextWrapped = false,
		TextTransparency = if have then 0 else 0.55,
		-- (Just the icon's own room: the "+2" sits on the disc's edge, clear of it.)
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.64, 0.64),
		ZIndex = (props.ZIndex or 3) + 1,
		Parent = disc,
	})
	return disc
end

-- The card ----------------------------------------------------------------------------------------

-- Confetti falls over the card (clipped to it).
local function confetti(layer: Frame)
	local count = if State.ReducedEffects() then 6 else 16
	for index = 1, count do
		local piece = UIKit.new("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.04 + math.random() * 0.92, -0.06 - math.random() * 0.2),
			Size = UDim2.fromOffset(math.random(8, 11), math.random(12, 16)),
			Rotation = math.random(0, 360),
			BackgroundColor3 = CONFETTI[(index % #CONFETTI) + 1],
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = layer,
		})
		local fall = 1.6 + math.random() * 1.2
		UIKit.Tween(piece, fall, {
			Position = UDim2.fromScale(piece.Position.X.Scale + (math.random() - 0.5) * 0.12, 1.02),
			Rotation = piece.Rotation + math.random(-480, 480),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(piece, fall + 0.2)
	end
end

-- What the card says about these medals: the headline and the line under it.
local function cardWords(list: { Medals.Medal }, earlier: boolean): (string, string)
	local count = #list
	if earlier then
		if count == 1 then
			return "MEDAL UNLOCKED!", `{list[1].Icon} {list[1].Name}: you'd already earned it!`
		end
		return `{count} MEDALS UNLOCKED!`, "You'd already earned these. They're yours!"
	end
	if count == 1 then
		return "MEDAL EARNED!", `{list[1].Icon} {list[1].Name}`
	end
	local icons = {}
	for index, medal in list do
		if index > 5 then
			table.insert(icons, `+{count - 5}`)
			break
		end
		table.insert(icons, medal.Icon)
	end
	return `{count} NEW MEDALS!`, table.concat(icons, "  ")
end

local function show(items: { Earned })
	local list: { Medals.Medal } = {}
	local seen = {}
	local earlier = true
	for _, item in items do
		local medal = Medals.Get(item.Id)
		if medal and not seen[item.Id] then
			seen[item.Id] = true
			table.insert(list, medal)
			earlier = earlier and item.Earlier
		end
	end
	if #list == 0 then
		return
	end
	local first = list[1]

	-- Phones: top middle, under Roblox's top bar. PC: the middle of the screen.
	local holder = UIKit.new("Frame", {
		Name = "MedalCard",
		AnchorPoint = if touch then Vector2.new(0.5, 0) else Vector2.new(0.5, 0.5),
		Position = if touch then UDim2.new(0.5, 0, 0, 4) else UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.AutoScale(holder)
	local card = UIKit.Panel({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		CornerRadius = 26,
		ClipsDescendants = true, -- the ribbon and the confetti stay on the card
		ZIndex = 1,
		Parent = holder,
	}, Color3.fromRGB(96, 62, 190), Theme.Colors.PanelDark)
	card:SetAttribute("PP_Popup", true) -- a few seconds in the lobby; nothing in the stick's corner takes taps
	local rim = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	rim.Color = Theme.Colors.Yellow
	rim.Thickness = 4
	rim.Transparency = 0

	local shownAt = os.clock()
	local closed = false
	local function close(interrupted: boolean)
		if closed then
			return
		end
		closed = true
		if closeCurrent == close then
			closeCurrent = nil
		end
		holder:Destroy()
		setSpot(false)
		if interrupted and os.clock() - shownAt < BARELY then
			-- Hardly seen: back at the front of the queue for the next calm moment.
			for index = #items, 1, -1 do
				table.insert(queue, 1, items[index])
			end
		end
		task.delay(0.4, MedalController.Pump)
	end
	closeCurrent = close
	setSpot(true)

	-- The medal on its ribbon (a V of two strips from the card's top edge), on the left.
	local discCenter = UDim2.fromOffset(24 + DISC / 2, 30 + DISC / 2)
	for _, side in { -1, 1 } do
		UIKit.new("Frame", {
			Name = "Ribbon",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(24 + DISC / 2 + side * 16, 30 + DISC / 2),
			-- (A rotated frame isn't clipped by the card: this reaches just to its top edge.)
			Size = UDim2.fromOffset(34, 84),
			Rotation = side * 16,
			BackgroundColor3 = first.Color,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = card,
			Children = { UIKit.Gradient(first.Color, first.Color:Lerp(Color3.new(0, 0, 0), 0.25), 0) },
		})
	end
	local disc = medalDisc(card, first, DISC, true, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = discCenter,
		ZIndex = 3,
	})
	if #list > 1 then
		local more = UIKit.new("Frame", {
			Name = "More",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(24 + DISC - 8, 30 + DISC - 6),
			Size = UDim2.fromOffset(52, 40),
			BackgroundColor3 = Theme.Colors.Pink,
			ZIndex = 5,
			Parent = card,
			Children = { UIKit.Round(), UIKit.Stroke(nil, 2, 0.2) },
		})
		label({
			Text = `+{#list - 1}`,
			Font = Theme.Fonts.Display,
			TextSize = 24,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 6,
			Parent = more,
			Children = { UIKit.TextStroke(0.2) },
		})
	end

	-- The words, and the ✕ in the corner.
	local headlineText, sublineText = cardWords(list, earlier)
	local wordsWidth = CARD_W - TEXT_LEFT - CLOSE - 24
	local headline = label({
		Name = "Headline",
		Text = headlineText,
		Font = Theme.Fonts.Display,
		TextSize = fitSize(headlineText, 40, 28, wordsWidth, Theme.Fonts.Display),
		TextWrapped = false,
		TextColor3 = Theme.Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(TEXT_LEFT, 12),
		Size = UDim2.fromOffset(wordsWidth, 52),
		Parent = card,
		Children = { UIKit.TextStroke(0) },
	})
	local subline = label({
		Name = "Subline",
		Text = sublineText,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(TEXT_LEFT + 2, 66),
		Size = UDim2.fromOffset(wordsWidth, 56),
		Parent = card,
		Children = { UIKit.TextStroke(0.2) },
	})
	subline:SetAttribute("PP_Lines", 2)
	UIKit.Button({
		Name = "Close",
		Text = "X",
		TextSize = 30,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(if touch then CLOSE else 56, if touch then CLOSE else 56),
		CornerRadius = "round",
		ZIndex = 5,
		Parent = card,
	}, function()
		close(false)
	end, Theme.Colors.PanelLight, Theme.Colors.PanelDark)

	-- The count (left) and SEE ALL (right half: clear of the thumbstick's corner).
	local buttonHeight = if touch then Theme.Touch.Target else 60
	label({
		Name = "Count",
		Text = `🏅 {progressText()} medals`,
		Font = Theme.Fonts.Display,
		TextSize = 22,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(TEXT_LEFT + 2, BOTTOM_Y),
		Size = UDim2.fromOffset(CARD_W - TEXT_LEFT - SEE_W - 30, buttonHeight),
		Parent = card,
		Children = { UIKit.TextStroke(0.3) },
	})
	UIKit.Button({
		Name = "SeeAll",
		Text = "🏅 SEE ALL",
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, BOTTOM_Y),
		Size = UDim2.fromOffset(SEE_W, buttonHeight),
		CornerRadius = 18,
		ZIndex = 4,
		Parent = card,
	}, function()
		close(false)
		openScreen()
	end, Theme.Colors.Pink, PINK_DARK)

	UIKit.PopIn(card, 0.4)
	UIKit.PopIn(disc, 0.6)
	UIKit.PopIn(headline, 0.45)
	confetti(card)
	AudioController.Play("Victory")
	task.delay(SHOW_FOR, function()
		close(false)
	end)
end

-- Shows the waiting medals in one card, if it's a calm moment.
function MedalController.Pump()
	local phase = GameState.Get("Phase") or "Waiting"
	if closeCurrent or windowOpen or #queue == 0 or not CALM[phase] then
		return
	end
	if phase == "Intermission" and GameState.TimeLeft() < MIN_SHOW then
		return -- the vote is about to start: after the next round instead
	end
	if not State.Profile or celebrationShowing() or player:GetAttribute("PP_Celebrating") == true then
		return -- a level-up card first (it says when it's done)
	end
	if screenTaken() or hud:GetAttribute("PP_TipsAside") == true then
		return -- the PARTY CUP's podium or the results card, or playing Skee-Ball
	end
	local items = table.clone(queue)
	table.clear(queue)
	show(items)
end

-- Pumps in a moment (a level-up card that comes in at the same time takes the spot first).
local function pumpSoon(delay: number?)
	if pumpQueued then
		return
	end
	pumpQueued = true
	task.delay(delay or LEVEL_UP_FIRST, function()
		pumpQueued = false
		MedalController.Pump()
	end)
end

-- Closes the card on screen (the client harness uses this too).
function MedalController.Dismiss()
	if closeCurrent then
		closeCurrent(false)
	end
end

-- The medal screen (the Rewards screen's MEDALS tab) --------------------------------------------------

local TILE_GAP = 10
local SCROLL_ROOM = 10 -- the scroll bar's side of each row

-- One medal's tile: its disc (bright, or dimmed with a faded icon), its name, and the day it was
-- earned (✓) or how to earn it (🔒).
local function tile(parent: Instance, medal: Medals.Medal, order: number, width: number, height: number, today: number)
	local day = owned()[medal.Id]
	local have = type(day) == "number"
	local card = UIKit.Panel(
		{
			Name = medal.Id,
			Size = UDim2.fromOffset(width, height),
			LayoutOrder = order,
			CornerRadius = 16,
			Parent = parent,
		},
		if have then Theme.Colors.Card else Theme.Colors.PanelDark,
		if have then Theme.Colors.PanelDark else Theme.Colors.Panel
	)
	if have then
		local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = Theme.Colors.Yellow
		stroke.Thickness = 2
		stroke.Transparency = 0.2
	end
	-- The medal's ribbon colour down its left edge.
	UIKit.new("Frame", {
		Name = "Band",
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(0, 6, 1, -28),
		BackgroundColor3 = if have then medal.Color else WALL_LOCKED_RIBBON,
		BorderSizePixel = 0,
		Parent = card,
		Children = { UIKit.Round() },
	})
	local discSize = height - 34
	medalDisc(card, medal, discSize, have, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		ZIndex = 2,
	})
	local left = 14 + discSize + 10
	local textWidth = width - left - 8
	label({
		Name = "Title",
		Text = medal.Short,
		Font = Theme.Fonts.Display,
		-- A long name draws a little smaller, so it stays on one line.
		TextSize = fitSize(medal.Short, 22, Theme.Touch.MinText, textWidth, Theme.Fonts.Display),
		TextWrapped = false,
		TextColor3 = if have then Theme.Colors.Text else Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(left, 8),
		Size = UDim2.fromOffset(textWidth, 30),
		Parent = card,
		Children = { UIKit.TextStroke(0.3) },
	})
	local line = label({
		Name = "How",
		Text = if have then `✓ Earned {MedalLogic.DateText(day, today)}` else `🔒 {medal.How}`,
		Font = if have then Theme.Fonts.Display else Theme.Fonts.Bold,
		TextSize = Theme.Touch.MinText,
		TextColor3 = if have then Theme.Colors.Green else Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(left, 40),
		Size = UDim2.fromOffset(textWidth, height - 46),
		Parent = card,
	})
	line:SetAttribute("PP_Lines", 2)
end

-- A heading ("⭐ BIG MEDALS  3 / 9") and its medals, three to a row.
local function section(
	list: Frame,
	order: number,
	title: string,
	medals: { Medals.Medal },
	width: number,
	today: number
)
	local have = 0
	for _, medal in medals do
		if owned()[medal.Id] ~= nil then
			have += 1
		end
	end
	label({
		Name = "Section",
		Text = `{title}  {have} / {#medals}`,
		Font = Theme.Fonts.Display,
		TextSize = 22,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(width, 30),
		LayoutOrder = order,
		Parent = list,
		Children = { UIKit.TextStroke(0.3) },
	})
	local height = if touch then 112 else 100
	local tileWidth = math.floor((width - 2 * TILE_GAP) / 3)
	for row = 1, math.ceil(#medals / 3) do
		local holder = UIKit.new("Frame", {
			Name = `Row{row}`,
			Size = UDim2.fromOffset(width, height),
			BackgroundTransparency = 1,
			LayoutOrder = order + row,
			Parent = list,
			Children = { UIKit.List(Enum.FillDirection.Horizontal, TILE_GAP, Enum.HorizontalAlignment.Left) },
		})
		for column = 1, 3 do
			local medal = medals[(row - 1) * 3 + column]
			if medal then
				tile(holder, medal, column, tileWidth, height, today)
			end
		end
	end
end

-- Draws the medal screen into `body` (the Rewards screen's MEDALS tab). `keep`: where to scroll.
function MedalController.Render(body: Frame, keep: Vector2?)
	touch = UIKit.IsTouch()
	-- The tiles are laid out for the screen's width (in the window's units; 940 on every phone).
	local scale = UIKit.CurrentScale()
	local bodyWidth = if body.AbsoluteSize.X > 100 and scale > 0 then body.AbsoluteSize.X / scale else 940
	local rowWidth = math.floor(bodyWidth - SCROLL_ROOM)
	local have, total = MedalLogic.Progress(Medals.Catalog, owned())
	local headerH = 44
	local header = UIKit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, headerH),
		BackgroundTransparency = 1,
		Parent = body,
	})
	local bar = UIKit.new("Frame", {
		Name = "Progress",
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.fromOffset(300, 32),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = header,
		Children = { UIKit.Round() },
	})
	UIKit.new("Frame", {
		Size = UDim2.fromScale(if total > 0 then math.clamp(have / total, 0, 1) else 0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = bar,
		Children = { UIKit.Round(), UIKit.Gradient(Theme.Colors.Yellow, Theme.Colors.Orange, 0) },
	})
	label({
		Text = `🏅 {have} / {total} medals`,
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = bar,
		Children = { UIKit.TextStroke(0.2) },
	})
	label({
		Text = if have >= total and total > 0
			then "You have them all! 👑"
			else "Yours shine on the MEDAL WALL by the SHOP",
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 0),
		Size = UDim2.new(1, -316, 1, 0),
		Parent = header,
	})

	local list = UIKit.new("ScrollingFrame", {
		Name = "Medals",
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
	local today = DailyLogic.DayNumber(os.time())
	section(list, 0, "⭐ BIG MEDALS", Medals.Big, rowWidth, today)
	section(list, 100, "🎮 WIN EVERY GAME", Medals.Games, rowWidth, today)
	if keep then
		task.defer(function()
			if list.Parent then
				list.CanvasPosition = keep
			end
		end)
	end
end

-- The medal wall: your medals lit up on it ------------------------------------------------------------

type Slot = { Medal: Medals.Medal, Disc: BasePart, Ribbons: { BasePart }, Icon: TextLabel }
local slots: { [Instance]: Slot } = {}
local counters: { TextLabel } = {}

local function paintSlot(slot: Slot)
	local have = owned()[slot.Medal.Id] ~= nil
	slot.Disc.Color = if have then LIT_DISC else WALL_LOCKED_DISC
	slot.Disc.Material = if have then Enum.Material.Neon else Enum.Material.SmoothPlastic
	for _, ribbon in slot.Ribbons do
		ribbon.Color = if have then slot.Medal.Color else WALL_LOCKED_RIBBON
	end
	slot.Icon.TextTransparency = if have then 0 else 0.6
end

local function paintWall()
	for _, slot in slots do
		paintSlot(slot)
	end
	for _, counter in counters do
		counter.Text = `🏅 YOUR MEDALS  {progressText()}`
	end
end

local function bindSlot(model: Instance)
	local id = model:GetAttribute("MedalId")
	local medal = if type(id) == "string" then Medals.Get(id) else nil
	if not medal or slots[model] then
		return
	end
	local disc = model:WaitForChild("Disc", 30)
	if not (disc and disc:IsA("BasePart")) then
		return
	end
	local ribbons = {}
	for _, child in model:GetChildren() do
		if child.Name == "Ribbon" and child:IsA("BasePart") then
			table.insert(ribbons, child)
		end
	end
	-- The icon on the disc's face toward the plaza (its Right face).
	local surface = UIKit.new("SurfaceGui", {
		Name = "Medal_" .. medal.Id,
		Adornee = disc,
		Face = Enum.NormalId.Right,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 50,
		LightInfluence = 0,
		Brightness = 1.2,
		MaxDistance = 140,
		ResetOnSpawn = false,
		Parent = playerGui,
	})
	local icon = UIKit.Label({
		Name = "Icon",
		Text = medal.Icon,
		TextScaled = true,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.68, 0.68),
		Parent = surface,
	})
	local slot = { Medal = medal, Disc = disc :: BasePart, Ribbons = ribbons, Icon = icon }
	slots[model] = slot
	model.Destroying:Connect(function()
		slots[model] = nil
		surface:Destroy()
	end)
	paintSlot(slot)
end

local function bindCounter(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local surface = UIKit.new("SurfaceGui", {
		Name = "MedalCount",
		Adornee = part,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0,
		Brightness = 1.3,
		MaxDistance = 90,
		ResetOnSpawn = false,
		Parent = playerGui,
	})
	local text = UIKit.Label({
		Name = "Count",
		Text = `🏅 YOUR MEDALS  {progressText()}`,
		Font = Theme.Fonts.Display,
		TextScaled = true,
		TextColor3 = Theme.Colors.Yellow,
		Size = UDim2.fromScale(1, 1),
		Parent = surface,
		Children = { UIKit.Padding(3, 12) },
	})
	table.insert(counters, text)
end

-- Runs `callback` for every instance with `tag`, now and when one is added (the lobby is built over
-- a few seconds, so the wall can arrive after this starts).
local function onTag(tag: string, callback: (Instance) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(callback, instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(callback)
end

function MedalController.Start(context)
	touch = UIKit.IsTouch()
	hud = context.Hud
	playerGui = context.Hud.Parent
	-- Their own layer, like the level-up cards': above the HUD and the toasts, under the windows
	-- (10), which close it anyway.
	gui = UIKit.new("ScreenGui", {
		Name = "PartyPanicMedals",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 9,
		Parent = playerGui,
	})

	Remotes.Get("MedalEarned").OnClientEvent:Connect(function(id, earlier)
		if type(id) ~= "string" or not Medals.Get(id) then
			return
		end
		table.insert(queue, { Id = id, Earlier = earlier == true })
		pumpSoon() -- (several in a row make one card)
	end)
	GameState.Changed("Phase", function(phase)
		if CALM[phase] then
			pumpSoon()
		elseif closeCurrent then
			closeCurrent(true) -- the vote or the round: out of the way
		end
	end)
	GameState.Changed("PhaseEndsAt", function()
		pumpSoon()
	end)
	State.ProfileChanged:Connect(function()
		paintWall()
		if #queue > 0 then
			pumpSoon()
		end
	end)
	-- A level-up card takes the spot: a medal card on screen steps aside, and the waiting ones show
	-- once it has gone.
	player:GetAttributeChangedSignal("PP_Celebrating"):Connect(function()
		if player:GetAttribute("PP_Celebrating") ~= true then
			pumpSoon(0.5)
		end
	end)
	local function watchCelebrations(celebrate: Instance)
		celebrate.ChildAdded:Connect(function(child)
			if child.Name == "Celebration" and closeCurrent then
				closeCurrent(true)
			end
		end)
		celebrate.ChildRemoved:Connect(function(child)
			if child.Name == "Celebration" then
				pumpSoon(0.5)
			end
		end)
	end
	local celebrate = playerGui:FindFirstChild("PartyPanicCelebrate")
	if celebrate then
		watchCelebrations(celebrate)
	else
		playerGui.ChildAdded:Connect(function(child)
			if child.Name == "PartyPanicCelebrate" then
				watchCelebrations(child)
			end
		end)
	end
	Modal.AnyOpenChanged:Connect(function(open)
		windowOpen = open
		if open and closeCurrent then
			closeCurrent(true)
		elseif not open then
			pumpSoon(0.4)
		end
	end)
	-- A lobby game (Skee-Ball) takes the screen: the card steps aside until it's over.
	hud:GetAttributeChangedSignal("PP_TipsAside"):Connect(function()
		if hud:GetAttribute("PP_TipsAside") == true and closeCurrent then
			closeCurrent(true)
		else
			pumpSoon(0.4)
		end
	end)
	-- So do the PARTY CUP's podium and the results card (a card waits for both to clear).
	for _, attribute in SCREEN_TAKEN do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if player:GetAttribute(attribute) == true and closeCurrent then
				closeCurrent(true)
			else
				pumpSoon(0.4)
			end
		end)
	end

	-- The medal wall's prompt opens the medal screen.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
		if triggeringPlayer == player and prompt:GetAttribute("Action") == "OpenMedals" then
			openScreen()
		end
	end)
	onTag("MedalSlot", bindSlot)
	onTag("MedalCount", bindCounter)
end

return MedalController

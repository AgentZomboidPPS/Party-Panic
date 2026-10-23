-- Cosmetic shop (design doc §10 "Shop layout"): tabs, large previews, price, ownership, a clear
-- purchase confirmation and an equip button. Every lock says exactly how to unlock the item.
-- Four cards fill each row at any window size (the window shrinks on phones and the grid scrolls);
-- phones get three wider cards a row so names fit on one line, 44 pt buttons and 11 pt or bigger
-- text, and the tabs scroll if the window is short.
-- State.OpenScreen:Fire("Shop", "Emote") opens it on a tab (the emote picker's "Get more").
-- Prices are low (owner: "Also lets balance the shop down. I want low currency not high."); what
-- coins buy comes first, then the Rewards Road and career rewards, which say how to unlock them.
-- A limited-time event's free rewards come last (owner: "Can you work on all of that? this wont
-- mess with what the other workers are working on right?"): never for sale, and the card says which
-- event it came from; during the event its button says the candy it takes and opens the event
-- screen.
--
-- The purchase confirmation's Cancel was a dark purple button on its dark panel (owner: "why are
-- the close menu buttons and the invite friend button so dark?"): it's Theme's neutral lavender
-- button now. A locked item's button and the tabs not chosen stay dark on purpose: they say so.
-- The GOLD PASS's rewards (owner: "the paid one should also be insane") come after the road's and
-- the career's: never for coins, their button is gold ("👑 GOLD Lv 25") and opens the Rewards screen
-- on the gold lane, where the pass is.
-- Since the second shop pass (owner: "Yes lets add more items after everything else is finished") a
-- tab can hold twice as many cards, so a tab you switch to starts at its top, not where the last one
-- was scrolled to.
-- The crate seasons (Shared/Seasons; owner: "Hollow night comes first ... I want it to look insane.")
-- bring two tabs, Pets and Auras, and crate items in the others: never for coins, they come last,
-- on a card in the season's dusk colours with a rim in their tier's colour (pink pets, purple
-- hats, blue effects, the title in the season's own), the season's name in its corner. One that
-- isn't theirs says where it comes from ("📦 From crates": a tap opens the crate menu's
-- collection); the starter pack's trail opens its key shop; a past season's that wasn't found in
-- time is VAULTED. Theirs equip like any other. With eight tabs the tab column scrolls on PC too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local EventLogic = require(Shared.Logic.EventLogic)
local Events = require(Shared.Events)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local SeasonArt = require(Shared.SeasonArt)
local Seasons = require(Shared.Seasons)

local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ShopController = {}

local CARD_WIDTH, CARD_HEIGHT, CARD_GAP = 176, 236, 12
local TOUCH_CARD_HEIGHT = 252
local touch = false

local modal: Modal.Modal
local grid: ScrollingFrame
local coinLabel: TextLabel
local coinIcon: Frame
local confirm: Frame
local confirmText: TextLabel
local pendingItem: Cosmetics.Cosmetic? = nil
local currentSlot = "Trail"
local tabButtons: { [string]: TextButton } = {}

local function lockReason(item: Cosmetics.Cosmetic): string?
	if item.UnlockLevel then
		return `🔒 Level {item.UnlockLevel}`
	elseif item.UnlockStat then
		local profile = State.Profile
		local have = profile and profile.Stats[item.UnlockStat.Stat] or 0
		return `🔒 {item.UnlockStat.Label} {have}/{item.UnlockStat.Value}`
	elseif item.GoldLevel then
		return `👑 GOLD Lv {item.GoldLevel}`
	end
	return nil
end

-- An event's reward: during its event, the candy it takes on the track (true: on now, a tap opens
-- the event screen); after it, that it can't be had any more.
local function eventSource(item: Cosmetics.Cosmetic): (string?, boolean)
	local event = item.Event and Events.Get(item.Event)
	if not event then
		return nil, false
	end
	local state = GameState.GetJSON("Event")
	local step = EventLogic.Step(event.Track, item.Id)
	if type(state) == "table" and state.Id == event.Id and step then
		return `🍬 {step.Candy} CANDY`, true
	end
	return "🔒 EVENT OVER", false
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The tier a crate item is in ("Title", "Pet", "Hat", "Effect"; the starter pack's trail: "Starter").
local function tierOf(item: Cosmetics.Cosmetic): string
	local entry = Seasons.ItemById[item.Id]
	return if entry then entry.Tier else "Effect"
end

-- A crate item's picture (under the season's name): its cell of the season's icon sheet once that's
-- uploaded, else its emoji.
local SEASON_LABEL = 20 -- the season's name across the top of the swatch
local function seasonIcon(parent: GuiObject, item: Cosmetics.Cosmetic)
	local cell = SeasonArt.IconCells[item.Id]
	if SeasonArt.Icons ~= "" and cell then
		local size = SeasonArt.IconSize
		UIKit.new("ImageLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, SEASON_LABEL / 2),
			Size = UDim2.fromOffset(68, 68),
			BackgroundTransparency = 1,
			Image = SeasonArt.Icons,
			ImageRectOffset = Vector2.new(cell[1] * size, cell[2] * size),
			ImageRectSize = Vector2.new(size, size),
			ScaleType = Enum.ScaleType.Fit,
			Parent = parent,
		})
		return
	end
	UIKit.Label({
		Name = "Icon",
		Text = item.Icon,
		TextSize = 46,
		Position = UDim2.fromOffset(0, SEASON_LABEL),
		Size = UDim2.new(1, 0, 1, -SEASON_LABEL),
		Parent = parent,
		Children = { UIKit.TextStroke(0.5) },
	})
end

-- A crate item's preview: the season's dusk, a rim in its tier's colour, its picture, the season's
-- name in the corner.
local function seasonPreview(card: Frame, item: Cosmetics.Cosmetic)
	local season = Seasons.Get(item.Season :: string)
	local colors = if season then season.Colors else Seasons.CurrentSeason().Colors
	local tier = tierOf(item)
	local tierColor = rgb(if tier == "Starter" then colors.Gold else Seasons.TierColor(tier, season))
	local swatch = UIKit.new("Frame", {
		Name = "Swatch",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 92),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true,
		Parent = card,
		Children = {
			UIKit.Corner(14),
			UIKit.new("UIGradient", {
				Color = ColorSequence.new(rgb(colors.Panel), rgb(colors.Deep)),
				Rotation = 90,
			}),
			UIKit.new("UIStroke", {
				Color = tierColor,
				Thickness = 3,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		},
	})
	-- A soft glow of the tier's colour behind the picture.
	UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, SEASON_LABEL / 2 + 6),
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = tierColor,
		BackgroundTransparency = 0.55,
		Parent = swatch,
		Children = {
			UIKit.Corner(42),
			UIKit.new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 90,
			}),
		},
	})
	seasonIcon(swatch, item)
	if season then
		UIKit.Label({
			Name = "Season",
			Text = season.Name,
			Font = Theme.Fonts.Display,
			TextSize = if touch then Theme.Touch.MinText else 14,
			TextWrapped = false,
			TextColor3 = rgb(colors.Glow),
			Position = UDim2.fromOffset(6, 1),
			Size = UDim2.new(1, -12, 0, SEASON_LABEL),
			Parent = swatch,
			Children = { UIKit.TextStroke(0.3) },
		})
	end
end

local function preview(card: Frame, item: Cosmetics.Cosmetic)
	if item.Season then
		seasonPreview(card, item)
		return
	end
	local swatch = UIKit.new("Frame", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 92),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
		Children = { UIKit.Corner(14) },
	})
	if item.Colors and #item.Colors > 0 then
		UIKit.new("UIGradient", { Color = Cosmetics.ColorSequence(item.Colors), Rotation = 0, Parent = swatch })
	else
		swatch.BackgroundColor3 = Theme.Colors.PanelDark
	end
	UIKit.Label({
		Text = item.Icon,
		TextSize = 52,
		Size = UDim2.fromScale(1, 1),
		Parent = swatch,
		Children = { UIKit.TextStroke(0.5) },
	})
end

local function render()
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local profile = State.Profile
	if not profile then
		return
	end
	coinLabel.Text = UIKit.FormatNumber(profile.Coins)
	local coinWidth = UIKit.TextWidth(coinLabel.Text, 28, Theme.Fonts.Display)
	coinIcon.Position = UDim2.new(1, -70 - coinWidth - 8, coinIcon.Position.Y.Scale, coinIcon.Position.Y.Offset)
	for slot, button in tabButtons do
		local gradient = button:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = if slot == currentSlot
				then ColorSequence.new(Theme.Colors.Pink, Color3.fromRGB(200, 50, 140))
				else ColorSequence.new(Theme.Colors.Lavender, Theme.Colors.Purple)
		end
	end

	local items = {}
	for _, item in Cosmetics.List do
		if item.Slot == currentSlot then
			table.insert(items, item)
		end
	end
	-- Free items, then what coins buy (cheapest first), then the rewards coins can't buy: the
	-- Rewards Road by level, career milestones, the GOLD PASS's lane by level, events, then the
	-- crate seasons' (the newest season first, rarest first).
	local tierRank = { Title = 1, Pet = 2, Hat = 3, Effect = 4, Starter = 5 }
	local function rank(item: Cosmetics.Cosmetic): (number, number)
		if item.Season then
			local season = Seasons.Get(item.Season)
			return 6, -(if season then season.Number else 0) * 10 + (tierRank[tierOf(item)] or 4)
		elseif item.Default then
			return 0, 0
		elseif item.Price then
			return 1, item.Price
		elseif item.UnlockLevel then
			return 2, item.UnlockLevel
		elseif item.UnlockStat then
			return 3, item.UnlockStat.Value
		elseif item.GoldLevel then
			return 4, item.GoldLevel
		elseif item.Event then
			local event = Events.Get(item.Event)
			local step = event and EventLogic.Step(event.Track, item.Id)
			return 5, if step then step.Candy else 0
		end
		return 4, 0
	end
	table.sort(items, function(a, b)
		local groupA, valueA = rank(a)
		local groupB, valueB = rank(b)
		if groupA ~= groupB then
			return groupA < groupB
		elseif valueA ~= valueB then
			return valueA < valueB
		end
		return a.Name < b.Name
	end)

	for order, item in items do
		local owned = profile.Owned[item.Id] == true
		local equipped = profile.Equipped[item.Slot] == item.Id
		local card = UIKit.Panel({
			Size = UDim2.fromOffset(CARD_WIDTH, if touch then TOUCH_CARD_HEIGHT else CARD_HEIGHT),
			LayoutOrder = order,
			CornerRadius = 18,
			Parent = grid,
		}, Theme.Colors.Card, Theme.Colors.PanelDark)
		preview(card, item)
		UIKit.Label({
			Text = item.Name,
			Font = Theme.Fonts.Display,
			TextSize = 20,
			TextScaled = not touch, -- PC: long names shrink a little to fit the card
			TextWrapped = false,
			Position = UDim2.fromOffset(8, if touch then 100 else 106),
			Size = UDim2.new(1, -16, 0, 26),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = card,
			Children = if touch
				then {}
				else { UIKit.new("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 15 }) },
		})
		local event = item.Event and Events.Get(item.Event)
		UIKit.Label({
			-- An event's reward says where it came from, owned or not ("🎃 HALLOWEEN 2026").
			Text = if event then `{event.Icon} {event.Label}` else item.Description,
			TextSize = if touch then Theme.Touch.MinText else 17,
			TextScaled = not touch, -- PC: a long one shrinks a little to keep to two lines
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(8, if touch then 126 else 132),
			Size = UDim2.new(1, -16, 0, if touch then 44 else 40),
			Parent = card,
			Children = if touch
				then {}
				else { UIKit.new("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 13 }) },
		})

		local actionText, top, bottom, onClick
		if Cosmetics.IsEquipSlot(item.Slot) and owned then
			if equipped then
				actionText, top, bottom = "Equipped ✓", Theme.Colors.Green, Color3.fromRGB(60, 160, 90)
				onClick = function()
					Remotes.Get("ShopEquip"):FireServer(item.Slot, "")
				end
			else
				actionText, top, bottom = "Equip", Theme.Colors.Cyan, Color3.fromRGB(50, 120, 230)
				onClick = function()
					Remotes.Get("ShopEquip"):FireServer(item.Slot, item.Id)
				end
			end
		elseif owned then
			actionText, top, bottom = "Owned ✓", Theme.Colors.Green, Color3.fromRGB(60, 160, 90)
		elseif item.Price then
			local affordable = profile.Coins >= item.Price
			actionText = `{Theme.CoinIcon} {UIKit.FormatNumber(item.Price)}`
			top = if affordable then Theme.Colors.Yellow else Theme.Colors.Muted
			bottom = if affordable then Theme.Colors.Orange else Theme.Colors.MutedDark
			onClick = function()
				pendingItem = item
				confirmText.Text = `Buy {item.Icon} {item.Name} for {Theme.CoinIcon} {UIKit.FormatNumber(
					item.Price :: number
				)}?\nYou have {Theme.CoinIcon} {UIKit.FormatNumber(profile.Coins)}.`
				confirm.Visible = true
				Remotes.Get("Funnel"):FireServer("ShopPick", item.Id) -- (the Shop funnel: Services/FunnelService)
				UIKit.PopIn(confirm, 0.25)
			end
		elseif item.Event then
			local source, on = eventSource(item)
			actionText = source or "Locked"
			top = if on then Theme.Colors.Orange else Theme.Colors.Muted
			bottom = if on then Color3.fromRGB(205, 92, 24) else Theme.Colors.MutedDark
			if on then
				onClick = function()
					State.OpenScreen:Fire("Event")
				end
			end
		elseif item.GoldLevel then
			-- A GOLD PASS reward: the gold lane (and the pass) are on the Rewards screen.
			actionText, top, bottom =
				lockReason(item) or "GOLD", Color3.fromRGB(255, 214, 90), Color3.fromRGB(214, 132, 18)
			onClick = function()
				State.OpenScreen:Fire("Rewards", "Road")
			end
		elseif item.Season then
			-- A crate season's: from its crates (the crate menu), the starter pack's from its key shop,
			-- a past season's VAULTED.
			local season = Seasons.Get(item.Season)
			local starter = season ~= nil and season.Starter == item.Id
			if season and (season.Id == Seasons.Current or starter) then
				local colors = season.Colors
				actionText = if starter then "🔑 Starter pack" else "📦 From crates"
				top, bottom = rgb(colors.Main), rgb(colors.Crimson)
				onClick = function()
					State.OpenScreen:Fire("Crates", if starter then "Keys" else "Collection")
				end
			else
				actionText, top, bottom = "🔒 VAULTED", Theme.Colors.Muted, Theme.Colors.MutedDark
			end
		else
			actionText, top, bottom = lockReason(item) or "Locked", Theme.Colors.Muted, Theme.Colors.MutedDark
		end
		UIKit.Button({
			Text = actionText,
			TextSize = if touch then 20 else 18,
			TextScaled = not touch, -- PC: a long lock ("🔒 Survival wins 0/5") shrinks a little
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -20, 0, if touch then 68 else 44),
			CornerRadius = 14,
			Parent = card,
			Children = if touch
				then {}
				else {
					UIKit.new("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 14 }),
					UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
				},
		}, onClick, top, bottom)
	end
end

function ShopController.Start(context)
	touch = UIKit.IsTouch()
	modal = Modal.new(context.Overlay, "Shop", "🛍️", Vector2.new(960, 600))
	local content = modal.Content
	local title = Modal.TitleHeight()

	-- Your coins, in the title bar left of the close button.
	coinLabel = UIKit.Label({
		Text = "0",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextWrapped = false,
		TextColor3 = Theme.Colors.Coin,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -70, 0, -(title + 6) + title / 2 + 2),
		Size = UDim2.fromOffset(190, 40),
		ZIndex = 25,
		Parent = content,
		Children = { UIKit.TextStroke(0.2) },
	})
	coinIcon = UIKit.Coin({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -110, 0, -(title + 6) + title / 2 + 2),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 25,
		Parent = content,
	})

	-- The tabs scroll (eight of them, with the crate seasons' Pets and Auras, don't fit a short window).
	local tabGap = if touch then 6 else 8
	local tabs = UIKit.new("ScrollingFrame", {
		Size = UDim2.new(0, 170, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, tabGap) },
	})
	for order, tab in Cosmetics.ShopTabs do
		tabButtons[tab.Slot] = UIKit.Button({
			Text = `{tab.Icon} {tab.Label}`,
			TextSize = 21,
			Size = UDim2.new(1, -6, 0, if touch then 66 else 48),
			LayoutOrder = order,
			Parent = tabs,
		}, function()
			if currentSlot ~= tab.Slot then
				grid.CanvasPosition = Vector2.zero -- a new tab starts at its top
			end
			currentSlot = tab.Slot
			render()
		end, Theme.Colors.Lavender, Theme.Colors.Purple)
	end
	UIKit.Label({
		Text = "Cosmetics only - no gameplay advantages.",
		TextSize = if touch then Theme.Touch.MinText else 17,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, -6, 0, if touch then 60 else 40),
		LayoutOrder = 99,
		Parent = tabs,
	})

	grid = UIKit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(186, 0),
		Size = UDim2.new(1, -186, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
		Children = {
			UIKit.new("UIGridLayout", {
				-- A quarter of the row each (less the gaps, with a little slack), so four always fit
				-- (phones: a third, so names fit on one line).
				CellSize = if touch
					then UDim2.new(1 / 3, -(CARD_GAP + 4), 0, TOUCH_CARD_HEIGHT)
					else UDim2.new(0.25, -(CARD_GAP + 4), 0, CARD_HEIGHT),
				CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			-- The right side leaves room for the scroll bar.
			UIKit.new("UIPadding", {
				PaddingLeft = UDim.new(0, 4),
				PaddingRight = UDim.new(0, 14),
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
			}),
		},
	})

	local confirmButton = if touch then Theme.Touch.Target else 56
	confirm = UIKit.Panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, if touch then 236 else 220),
		CornerRadius = 20,
		Visible = false,
		ZIndex = 30,
		Parent = content,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	confirmText = UIKit.Label({
		Text = "",
		TextSize = 24,
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.new(1, -32, 0, 100),
		ZIndex = 31,
		Parent = confirm,
	})
	UIKit.Button({
		Text = "Buy",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -8, 1, -18),
		Size = UDim2.fromOffset(170, confirmButton),
		ZIndex = 31,
		Parent = confirm,
	}, function()
		if pendingItem then
			Remotes.Get("ShopPurchase"):FireServer(pendingItem.Id)
		end
		pendingItem = nil
		confirm.Visible = false
	end, Theme.Colors.Green, Color3.fromRGB(60, 160, 90))
	UIKit.Button({
		Text = "Cancel",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 8, 1, -18),
		Size = UDim2.fromOffset(170, confirmButton),
		ZIndex = 31,
		Parent = confirm,
	}, function()
		pendingItem = nil
		confirm.Visible = false
	end, Theme.Colors.Lavender, Theme.Colors.Purple)

	State.OpenScreen:Connect(function(name, tab)
		if name ~= "Shop" then
			return
		end
		if type(tab) == "string" and tabButtons[tab] then
			if currentSlot ~= tab then
				grid.CanvasPosition = Vector2.zero
			end
			currentSlot = tab
			if modal.IsOpen then
				render()
				return
			end
		end
		modal:Toggle()
	end)
	modal.Opened:Connect(render)
	modal.Opened:Connect(function()
		Remotes.Get("Funnel"):FireServer("ShopOpen", currentSlot) -- (the Shop funnel's first step)
	end)
	modal.Closed:Connect(function()
		confirm.Visible = false
	end)
	State.ProfileChanged:Connect(function()
		if modal.IsOpen then
			render()
		end
	end)
end

return ShopController

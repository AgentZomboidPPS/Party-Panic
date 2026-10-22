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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local EventLogic = require(Shared.Logic.EventLogic)
local Events = require(Shared.Events)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

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

local function preview(card: Frame, item: Cosmetics.Cosmetic)
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
				else ColorSequence.new(Theme.Colors.PanelLight, Theme.Colors.PanelDark)
		end
	end

	local items = {}
	for _, item in Cosmetics.List do
		if item.Slot == currentSlot then
			table.insert(items, item)
		end
	end
	-- Free items, then what coins buy (cheapest first), then the rewards coins can't buy: the
	-- Rewards Road by level, career milestones, the GOLD PASS's lane by level, then events.
	local function rank(item: Cosmetics.Cosmetic): (number, number)
		if item.Default then
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
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(8, if touch then 126 else 132),
			Size = UDim2.new(1, -16, 0, if touch then 44 else 40),
			Parent = card,
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
			top = if affordable then Theme.Colors.Yellow else Theme.Colors.PanelLight
			bottom = if affordable then Theme.Colors.Orange else Theme.Colors.PanelDark
			onClick = function()
				pendingItem = item
				confirmText.Text = `Buy {item.Icon} {item.Name} for {Theme.CoinIcon} {UIKit.FormatNumber(
					item.Price :: number
				)}?\nYou have {Theme.CoinIcon} {UIKit.FormatNumber(profile.Coins)}.`
				confirm.Visible = true
				UIKit.PopIn(confirm, 0.25)
			end
		elseif item.Event then
			local source, on = eventSource(item)
			actionText = source or "Locked"
			top = if on then Theme.Colors.Orange else Theme.Colors.PanelLight
			bottom = if on then Color3.fromRGB(205, 92, 24) else Theme.Colors.PanelDark
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
		else
			actionText, top, bottom = lockReason(item) or "Locked", Theme.Colors.PanelLight, Theme.Colors.PanelDark
		end
		UIKit.Button({
			Text = actionText,
			TextSize = if touch then 20 else 18,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -20, 0, if touch then 68 else 44),
			CornerRadius = 14,
			Parent = card,
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

	local tabGap = if touch then 6 else 10
	local tabs = UIKit.new(if touch then "ScrollingFrame" else "Frame", {
		Size = UDim2.new(0, 170, 1, 0),
		BackgroundTransparency = 1,
		Parent = content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, tabGap) },
	})
	if touch then
		tabs.BorderSizePixel = 0
		tabs.ScrollBarThickness = 4
		tabs.AutomaticCanvasSize = Enum.AutomaticSize.Y
		tabs.CanvasSize = UDim2.new()
	end
	for order, tab in Cosmetics.ShopTabs do
		tabButtons[tab.Slot] = UIKit.Button({
			Text = `{tab.Icon} {tab.Label}`,
			TextSize = 21,
			Size = UDim2.new(1, if touch then -6 else 0, 0, if touch then 66 else 54),
			LayoutOrder = order,
			Parent = tabs,
		}, function()
			if currentSlot ~= tab.Slot then
				grid.CanvasPosition = Vector2.zero -- a new tab starts at its top
			end
			currentSlot = tab.Slot
			render()
		end, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	end
	UIKit.Label({
		Text = "Cosmetics only - no gameplay advantages.",
		TextSize = if touch then Theme.Touch.MinText else 17,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, if touch then -6 else 0, 0, if touch then 60 else 40),
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

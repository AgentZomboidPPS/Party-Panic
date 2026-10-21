-- Cosmetic shop (design doc §10 "Shop layout"): tabs, large previews, price, ownership, a clear
-- purchase confirmation and an equip button. Every lock says exactly how to unlock the item.
-- Four cards fill each row at any window size (the window shrinks on phones and the grid scrolls);
-- phones get three wider cards a row so names fit on one line, 44 pt buttons and 11 pt or bigger
-- text, and the tabs scroll if the window is short.
-- State.OpenScreen:Fire("Shop", "Emote") opens it on a tab (the emote picker's "Get more").
-- Prices are low (owner: "Also lets balance the shop down. I want low currency not high."); what
-- coins buy comes first, then the Rewards Road and career rewards, which say how to unlock them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
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
	elseif item.Vip then
		return "💎 VIP pass"
	end
	return nil
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
	-- Rewards Road by level, career milestones, VIP.
	local function rank(item: Cosmetics.Cosmetic): (number, number)
		if item.Default then
			return 0, 0
		elseif item.Price then
			return 1, item.Price
		elseif item.UnlockLevel then
			return 2, item.UnlockLevel
		elseif item.UnlockStat then
			return 3, item.UnlockStat.Value
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
		UIKit.Label({
			Text = item.Description,
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
	end, Theme.Colors.PanelLight, Theme.Colors.PanelDark)

	State.OpenScreen:Connect(function(name, tab)
		if name ~= "Shop" then
			return
		end
		if type(tab) == "string" and tabButtons[tab] then
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

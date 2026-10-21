-- Cosmetic shop (design doc §10 "Shop layout"): tabs, large previews, price, ownership, a clear
-- purchase confirmation and an equip button. Every lock says exactly how to unlock the item.
-- Four cards fill each row at any window size (the window shrinks on phones and the grid scrolls).
-- State.OpenScreen:Fire("Shop", "Emote") opens it on a tab (the emote picker's "Get more").

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

local modal: Modal.Modal
local grid: ScrollingFrame
local coinLabel: TextLabel
local confirm: Frame
local confirmText: TextLabel
local pendingItem: Cosmetics.Cosmetic? = nil
local currentSlot = "Trail"
local tabButtons: { [string]: TextButton } = {}

local function lockReason(item: Cosmetics.Cosmetic): string?
	if item.UnlockLevel then
		return `🔒 Reach level {item.UnlockLevel}`
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
	coinLabel.Text = "🪙 " .. UIKit.FormatNumber(profile.Coins)
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
	table.sort(items, function(a, b)
		return (a.Price or 0) < (b.Price or 0)
	end)

	for order, item in items do
		local owned = profile.Owned[item.Id] == true
		local equipped = profile.Equipped[item.Slot] == item.Id
		local card = UIKit.Panel(
			{ Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT), LayoutOrder = order, CornerRadius = 18, Parent = grid },
			Theme.Colors.Card,
			Theme.Colors.PanelDark
		)
		preview(card, item)
		UIKit.Label({
			Text = item.Name,
			Font = Theme.Fonts.Display,
			TextSize = 20,
			TextScaled = true, -- long names shrink a little to fit the card
			TextWrapped = false,
			Position = UDim2.fromOffset(8, 106),
			Size = UDim2.new(1, -16, 0, 26),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = card,
			Children = { UIKit.new("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 15 }) },
		})
		UIKit.Label({
			Text = item.Description,
			TextSize = 17,
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(8, 132),
			Size = UDim2.new(1, -16, 0, 40),
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
			actionText = `🪙 {UIKit.FormatNumber(item.Price)}`
			top = if affordable then Theme.Colors.Yellow else Theme.Colors.PanelLight
			bottom = if affordable then Theme.Colors.Orange else Theme.Colors.PanelDark
			onClick = function()
				pendingItem = item
				confirmText.Text =
					`Buy {item.Icon} {item.Name} for 🪙 {UIKit.FormatNumber(item.Price :: number)}?\nYou have 🪙 {UIKit.FormatNumber(
						profile.Coins
					)}.`
				confirm.Visible = true
				UIKit.PopIn(confirm, 0.25)
			end
		else
			actionText, top, bottom = lockReason(item) or "Locked", Theme.Colors.PanelLight, Theme.Colors.PanelDark
		end
		UIKit.Button({
			Text = actionText,
			TextSize = 18,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -20, 0, 44),
			CornerRadius = 14,
			Parent = card,
		}, onClick, top, bottom)
	end
end

function ShopController.Start(context)
	modal = Modal.new(context.Overlay, "Shop", "🛍️", Vector2.new(960, 600))
	local content = modal.Content

	coinLabel = UIKit.Label({
		Text = "🪙 0",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextColor3 = Theme.Colors.Coin,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -70, 0, -58),
		Size = UDim2.fromOffset(220, 40),
		ZIndex = 25,
		Parent = content,
		Children = { UIKit.TextStroke(0.2) },
	})

	local tabs = UIKit.new("Frame", {
		Size = UDim2.new(0, 170, 1, 0),
		BackgroundTransparency = 1,
		Parent = content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 10) },
	})
	for order, tab in Cosmetics.ShopTabs do
		tabButtons[tab.Slot] = UIKit.Button({
			Text = `{tab.Icon} {tab.Label}`,
			TextSize = 21,
			Size = UDim2.new(1, 0, 0, 54),
			LayoutOrder = order,
			Parent = tabs,
		}, function()
			currentSlot = tab.Slot
			render()
		end, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	end
	UIKit.Label({
		Text = "Cosmetics only - no gameplay advantages.",
		TextSize = 17,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 40),
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
				-- A quarter of the row each (less the gaps, with a little slack), so four always fit.
				CellSize = UDim2.new(0.25, -(CARD_GAP + 4), 0, CARD_HEIGHT),
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

	confirm = UIKit.Panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 220),
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
		Size = UDim2.fromOffset(170, 56),
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
		Size = UDim2.fromOffset(170, 56),
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

-- Toast notifications: short, icon-led messages that slide in and fade out (design doc §12).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local NotificationController = {}

local KINDS = {
	info = { Icon = "💬", Color = Theme.Colors.Cyan },
	success = { Icon = "✅", Color = Theme.Colors.Green },
	warning = { Icon = "⚠️", Color = Theme.Colors.Orange },
	reward = { Icon = "🎁", Color = Theme.Colors.Yellow },
}

local MAX_TOASTS = 4
local stack: Frame
local active: { Frame } = {}
local order = 0

function NotificationController.Show(text: string, kind: string?, duration: number?)
	local style = KINDS[kind or "info"] or KINDS.info
	order += 1

	local toast = UIKit.Panel({
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = -order,
		BackgroundTransparency = 0.05,
		CornerRadius = 14,
		Parent = stack,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	UIKit.new("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, 8, 1, 0),
		BackgroundColor3 = style.Color,
		BorderSizePixel = 0,
		Parent = toast,
		Children = { UIKit.Corner(6) },
	})
	UIKit.Label({
		Text = `{style.Icon}  {text}`,
		TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		Parent = toast,
		Children = { UIKit.Padding(10, 18) },
	})
	table.insert(active, toast)
	while #active > MAX_TOASTS do
		local oldest = table.remove(active, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	UIKit.PopIn(toast, 0.25)

	task.delay(duration or 3.5, function()
		if not toast.Parent then
			return
		end
		UIKit.Tween(toast, 0.3, { BackgroundTransparency = 1 })
		for _, descendant in toast:GetDescendants() do
			if descendant:IsA("TextLabel") then
				UIKit.Tween(descendant, 0.3, { TextTransparency = 1 })
			elseif descendant:IsA("UIStroke") then
				UIKit.Tween(descendant, 0.3, { Transparency = 1 })
			elseif descendant:IsA("Frame") then
				UIKit.Tween(descendant, 0.3, { BackgroundTransparency = 1 })
			end
		end
		task.wait(0.32)
		local index = table.find(active, toast)
		if index then
			table.remove(active, index)
		end
		toast:Destroy()
	end)
end

function NotificationController.Start(context)
	stack = UIKit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 96),
		Size = UDim2.fromOffset(380, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = context.Hud,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right) },
	})
	UIKit.AutoScale(stack, 0.95)

	Remotes.Get("Notify").OnClientEvent:Connect(function(text, kind, duration)
		if type(text) == "string" then
			NotificationController.Show(text, kind, duration)
		end
	end)
end

return NotificationController

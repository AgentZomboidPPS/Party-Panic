-- Toast notifications: short, icon-led messages that slide in and fade out (design doc §12).
-- They draw above the HUD and mode HUDs (but under pop-ups) in a spot nothing else uses: the top
-- right corner on PC (above the side menu), and on phones the bottom middle like Android toasts,
-- between the thumbstick and the jump button, lifted above the "you're out" and spectate panels.
-- Two at a time (a new one pushes the oldest out), so they never reach the menu or the vote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

-- Bottom-middle HUD panels (RoundController, SpectateController) the phone toasts stay above:
-- name -> their height plus a gap, in the same scaled units.
local BOTTOM_PANELS = { OutPanel = 120 + 24, Spectate = 76 + 24, SpectateButton = 56 + 24 }

local MAX_TOASTS = 2
local newestLast = false -- phones: the newest toast sits at the bottom of the stack
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
		LayoutOrder = if newestLast then order else -order,
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
	local touch = UIKit.IsTouch()
	-- Their own layer: above the HUD (5) and mode HUDs (6), under pop-ups (10).
	local gui = UIKit.new("ScreenGui", {
		Name = "PartyPanicToasts",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 8,
		Parent = context.Hud.Parent,
	})
	if touch then
		newestLast = true
		local holder = UIKit.new("Frame", {
			Name = "ToastArea",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -16),
			Size = UDim2.fromOffset(440, 400),
			BackgroundTransparency = 1,
			Parent = gui,
		})
		UIKit.AutoScale(holder)
		stack = UIKit.new("Frame", {
			Name = "Toasts",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = holder,
			Children = {
				UIKit.List(
					Enum.FillDirection.Vertical,
					8,
					Enum.HorizontalAlignment.Center,
					Enum.VerticalAlignment.Bottom
				),
			},
		})
		local function lift()
			local height = 0
			for name, panelHeight in BOTTOM_PANELS do
				local panel = context.Hud:FindFirstChild(name)
				if panel and panel:IsA("GuiObject") and panel.Visible then
					height = math.max(height, panelHeight)
				end
			end
			stack.Position = UDim2.new(0.5, 0, 1, -height)
		end
		local elapsed = 0
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed > 0.2 then
				elapsed = 0
				lift()
			end
		end)
		lift()
	else
		stack = UIKit.new("Frame", {
			Name = "Toasts",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 8),
			Size = UDim2.fromOffset(360, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = gui,
			Children = { UIKit.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right) },
		})
		UIKit.AutoScale(stack, 0.95)
	end

	Remotes.Get("Notify").OnClientEvent:Connect(function(text, kind, duration)
		if type(text) == "string" then
			NotificationController.Show(text, kind, duration)
		end
	end)
end

return NotificationController

-- Centered modal window with a title bar and close button. Only one modal is open at a time.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Signal = require(game:GetService("ReplicatedStorage").Shared.Signal)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local Modal = {}
Modal.__index = Modal

local openModal = nil

-- Fires with true/false whenever any modal opens or the last one closes (used to duck music).
Modal.AnyOpenChanged = Signal.new()

export type Modal = typeof(setmetatable(
	{} :: {
		Root: Frame,
		Window: Frame,
		Content: Frame,
		IsOpen: boolean,
		Opened: any,
		Closed: any,
	},
	Modal
))

function Modal.new(parent: Instance, title: string, icon: string, size: Vector2): Modal
	local root = UIKit.new("Frame", {
		Name = title .. "Modal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	})
	-- Clicking the dim backdrop closes the window.
	local backdrop = UIKit.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 20,
		Parent = root,
	})

	local window = UIKit.Panel({
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 21,
		CornerRadius = 22,
		Parent = root,
	})
	UIKit.AutoScale(window)

	local titleBar = UIKit.new("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = window,
	})
	UIKit.Label({
		Text = `{icon}  {title}`,
		Font = Theme.Fonts.Display,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(24, 10),
		Size = UDim2.new(1, -100, 0, 44),
		ZIndex = 22,
		Parent = titleBar,
		Children = { UIKit.TextStroke(0.3) },
	})

	local self = setmetatable({
		Root = root,
		Window = window,
		Content = UIKit.new("Frame", {
			Name = "Content",
			Position = UDim2.fromOffset(20, 70),
			Size = UDim2.new(1, -40, 1, -88),
			BackgroundTransparency = 1,
			ZIndex = 22,
			Parent = window,
		}),
		IsOpen = false,
		Opened = Signal.new(),
		Closed = Signal.new(),
	}, Modal)

	UIKit.Button({
		Name = "Close",
		Text = "✕",
		TextSize = 26,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.fromOffset(46, 46),
		CornerRadius = "round",
		ZIndex = 23,
		Parent = titleBar,
	}, function()
		self:Close()
	end, Theme.Colors.Red, Color3.fromRGB(190, 40, 60))

	backdrop.Activated:Connect(function()
		self:Close()
	end)
	return self
end

function Modal.Open(self: Modal)
	if openModal and openModal ~= self then
		openModal:Close()
	end
	openModal = self
	self.IsOpen = true
	Modal.AnyOpenChanged:Fire(true)
	self.Root.Visible = true
	UIKit.PopIn(self.Window, 0.3)
	self.Opened:Fire()
end

function Modal.Close(self: Modal)
	if not self.IsOpen then
		return
	end
	self.IsOpen = false
	self.Root.Visible = false
	if openModal == self then
		openModal = nil
		Modal.AnyOpenChanged:Fire(false)
	end
	GuiService.SelectedObject = nil
	self.Closed:Fire()
end

function Modal.Toggle(self: Modal)
	if self.IsOpen then
		self:Close()
	else
		self:Open()
	end
end

function Modal.CloseAll()
	if openModal then
		openModal:Close()
	end
end

-- Gamepad B closes whatever is open.
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.ButtonB then
		Modal.CloseAll()
	end
end)

return Modal

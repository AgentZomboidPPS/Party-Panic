-- Centered modal window with a title bar and close button. Only one modal is open at a time.
-- The window sits inside the screen's safe area (clear of Roblox's top bar and phone notches) and
-- shrinks to fit small screens; its content lays out to the window, so lists scroll on phones.
-- Phones: a 44 pt close button and a slightly smaller title (Modal.TitleHeight() says where the
-- content starts).

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Signal = require(game:GetService("ReplicatedStorage").Shared.Signal)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local Modal = {}
Modal.__index = Modal

local openModal = nil

-- Room left around a window that has been shrunk to fit the screen (screen pixels).
local FIT_MARGIN = 8

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

-- `parent` is a ScreenGui that keeps to the safe area (init.client.luau's overlay).
function Modal.new(parent: Instance, title: string, icon: string, size: Vector2): Modal
	local touch = UIKit.IsTouch()
	local root = UIKit.new("Frame", {
		Name = title .. "Modal",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	})
	-- The dim backdrop reaches past the safe area to cover the whole screen; tapping it closes.
	local backdrop = UIKit.new("TextButton", {
		Name = "Backdrop",
		Position = UDim2.fromOffset(-300, -300),
		Size = UDim2.new(1, 600, 1, 600),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AutoButtonColor = false,
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
	local windowScale = UIKit.AutoScale(window)
	window:SetAttribute("PP_Fit", size) -- tools/checks/ui_render.py fits it the same way
	-- Shrink (never grow) the window so it fits the safe area at the current UI scale.
	local function fit()
		local area = root.AbsoluteSize
		if area.X < 100 or area.Y < 100 then
			return -- not laid out yet
		end
		local scale = windowScale.Scale
		window.Size = UDim2.fromOffset(
			math.min(size.X, (area.X - 2 * FIT_MARGIN) / scale),
			math.min(size.Y, (area.Y - 2 * FIT_MARGIN) / scale)
		)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	windowScale:GetPropertyChangedSignal("Scale"):Connect(fit)
	fit()

	local titleHeight = Modal.TitleHeight()
	local titleBar = UIKit.new("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, titleHeight),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = window,
	})
	UIKit.Label({
		Text = `{icon}  {title}`,
		Font = Theme.Fonts.Display,
		TextSize = if touch then 30 else 34,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(24, (titleHeight - 44) / 2),
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 22,
		Parent = titleBar,
		Children = { UIKit.TextStroke(0.3) },
	})

	local self = setmetatable({
		Root = root,
		Window = window,
		Content = UIKit.new("Frame", {
			Name = "Content",
			Position = UDim2.fromOffset(20, titleHeight + 6),
			Size = UDim2.new(1, -40, 1, -(titleHeight + 24)),
			BackgroundTransparency = 1,
			ZIndex = 22,
			Parent = window,
		}),
		IsOpen = false,
		Opened = Signal.new(),
		Closed = Signal.new(),
	}, Modal)

	-- A bigger close button for thumbs.
	local closeSize = if touch then Theme.Touch.Target else 46
	UIKit.Button({
		Name = "Close",
		Text = "X",
		TextSize = if touch then 30 else 26,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0, titleHeight / 2 + 2),
		Size = UDim2.fromOffset(closeSize, closeSize),
		CornerRadius = "round",
		ZIndex = 23,
		Parent = titleBar,
	}, function()
		self:Close()
	end, Theme.Colors.Red, Color3.fromRGB(190, 40, 60))

	backdrop.Activated:Connect(function()
		self:Close()
	end)
	self.Opened:Connect(fit)
	return self
end

-- Height of the title bar (scaled units): the content starts just under it.
function Modal.TitleHeight(): number
	return if UIKit.IsTouch() then 80 else 64
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

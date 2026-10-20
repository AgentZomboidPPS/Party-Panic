-- Small declarative UI helpers so every screen shares the same rounded, glossy, animated style.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local UIKit = {}

export type Props = { [string]: any }

-- Creates an instance, applies props, parents children. `Parent` is applied last.
function UIKit.new(className: string, props: Props?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	for key, value in props or ({} :: Props) do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UIKit.Corner(radius: number?): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Corner) })
end

function UIKit.Round(): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function UIKit.Stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = color or Theme.Colors.Stroke,
		Thickness = thickness or 2,
		Transparency = transparency or 0.7,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UIKit.TextStroke(transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = Color3.fromRGB(30, 15, 60),
		Thickness = 2,
		Transparency = transparency or 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

function UIKit.Gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	return UIKit.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	})
end

function UIKit.Padding(all: number, horizontal: number?): UIPadding
	local h = UDim.new(0, horizontal or all)
	local v = UDim.new(0, all)
	return UIKit.new("UIPadding", { PaddingLeft = h, PaddingRight = h, PaddingTop = v, PaddingBottom = v })
end

function UIKit.List(
	direction: Enum.FillDirection?,
	padding: number?,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): UIListLayout
	return UIKit.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UIKit.Label(props: Props): TextLabel
	local defaults: Props = {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.Text,
		TextSize = 22,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 30),
	}
	for key, value in props do
		defaults[key] = value
	end
	local children = defaults.Children
	defaults.Children = nil
	return UIKit.new("TextLabel", defaults, children)
end

-- Glossy rounded panel with a gradient and a soft white rim.
function UIKit.Panel(props: Props, top: Color3?, bottom: Color3?): Frame
	local defaults: Props = {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}
	for key, value in props do
		defaults[key] = value
	end
	local children = defaults.Children or {}
	defaults.Children = nil
	table.insert(children, UIKit.Corner(defaults.CornerRadius))
	defaults.CornerRadius = nil
	table.insert(children, UIKit.Gradient(top or Theme.Colors.PanelLight, bottom or Theme.Colors.Panel))
	table.insert(children, UIKit.Stroke(nil, 2, 0.75))
	return UIKit.new("Frame", defaults, children)
end

local clickSound: Sound? = nil
function UIKit.SetClickSound(sound: Sound)
	clickSound = sound
end

-- Chunky button with hover and press animation. `onClick` fires on activation.
function UIKit.Button(props: Props, onClick: (() -> ())?, top: Color3?, bottom: Color3?): TextButton
	local defaults: Props = {
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Font = Theme.Fonts.Display,
		TextColor3 = Theme.Colors.Text,
		TextSize = 24,
		Size = UDim2.fromOffset(180, 56),
		BorderSizePixel = 0,
	}
	for key, value in props do
		defaults[key] = value
	end
	local children = defaults.Children or {}
	defaults.Children = nil
	local radius = defaults.CornerRadius
	defaults.CornerRadius = nil
	table.insert(children, if radius == "round" then UIKit.Round() else UIKit.Corner(radius))
	table.insert(children, UIKit.Gradient(top or Theme.Colors.Pink, bottom or Color3.fromRGB(200, 50, 140)))
	table.insert(children, UIKit.Stroke(nil, 2, 0.55))
	table.insert(children, UIKit.TextStroke(0.35))
	local scale = UIKit.new("UIScale", { Scale = 1 })
	table.insert(children, scale)
	local button = UIKit.new("TextButton", defaults, children)

	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.06 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.94 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	if onClick then
		button.Activated:Connect(function()
			if clickSound then
				SoundService:PlayLocalSound(clickSound)
			end
			onClick()
		end)
	end
	return button
end

-- Keeps a container at a comfortable size on every screen, from phones to 4K monitors.
function UIKit.AutoScale(container: GuiObject, bias: number?): UIScale
	local uiScale = UIKit.new("UIScale", { Parent = container })
	local camera = workspace.CurrentCamera
	local function update()
		local viewport = camera.ViewportSize
		local raw = math.min(viewport.X / Theme.DesignSize.X, viewport.Y / Theme.DesignSize.Y)
		uiScale.Scale = math.clamp(raw * (bias or 1), Theme.MinScale, Theme.MaxScale)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	update()
	return uiScale
end

function UIKit.Tween(
	instance: Instance,
	time: number,
	goal: Props,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goal
	)
	tween:Play()
	return tween
end

-- Pops a GuiObject in with a bouncy scale animation (adds a UIScale if missing).
function UIKit.PopIn(gui: GuiObject, time: number?)
	local scale = gui:FindFirstChild("PopScale") :: UIScale?
	if not scale then
		scale = UIKit.new("UIScale", { Name = "PopScale", Parent = gui })
	end
	local popScale = scale :: UIScale
	popScale.Scale = 0.6
	UIKit.Tween(popScale, time or 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

function UIKit.FormatTime(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

function UIKit.FormatNumber(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

return UIKit

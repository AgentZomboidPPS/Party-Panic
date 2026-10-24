-- Small declarative UI helpers so every screen shares the same rounded, glossy, animated style.

local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UiArt = require(game:GetService("ReplicatedStorage").Shared.UiArt)
local Icons = require(script.Parent.Icons)
local Theme = require(script.Parent.Theme)

local UIKit = {}

export type Props = { [string]: any }

-- Phones and tablets without a keyboard: layouts keep clear of the thumbstick (bottom left) and the
-- jump button (bottom right), and use bigger text.
function UIKit.IsTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- A faint white outline (white, partly see-through) is drawn as the game's dark ink instead, now and
-- whenever it's set again: the thin translucent white line round everything is a giveaway of a
-- generated UI (Theme's note). A strong white one (a picked chip, a highlight) stays white, and one
-- put away (fully see-through) stays away.
local function inkify(stroke: UIStroke)
	local function check()
		local color, seen = stroke.Color, stroke.Transparency
		if
			stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Border
			and seen >= 0.25
			and seen < 0.99
			and math.min(color.R, color.G, color.B) > 0.94
		then
			stroke.Color = Theme.Colors.Ink
			stroke.Transparency = 0
		end
	end
	stroke:GetPropertyChangedSignal("Color"):Connect(check)
	stroke:GetPropertyChangedSignal("Transparency"):Connect(check)
	stroke:GetPropertyChangedSignal("ApplyStrokeMode"):Connect(check)
	check()
end

-- Creates an instance, applies props, parents children. `Parent` is applied last.
function UIKit.new(className: string, props: Props?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	for key, value in props or ({} :: Props) do
		if key == "Parent" then
			parent = value
		elseif key == "Children" then
			-- Children can come in the props table too (like UIKit.Label/Button/Panel); setting it
			-- as a property would throw "Children is not a valid member".
			for _, child in value do
				child.Parent = instance
			end
		else
			(instance :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if className == "UIStroke" then
		inkify(instance)
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

-- An outline (a faint white one is drawn in ink: inkify above).
function UIKit.Stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = color or Theme.Colors.Stroke,
		Thickness = thickness or 2,
		Transparency = transparency or 0.7,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

-- The ink outline for something this colour: the colour itself, far darker.
function UIKit.InkFor(color: Color3): Color3
	return color:Lerp(Theme.Colors.Ink, 0.75)
end

-- A button's shine (Shared/UiArt's Gloss, tools/art/ui_art.py): a soft light band along its top and
-- a shade along its bottom edge, rounded like the button. Not on something laid out by a
-- UIListLayout/UIGridLayout inside it (the shine would be laid out too), nor without the art.
function UIKit.Gloss(target: GuiObject, radius: number | string | nil): ImageLabel?
	if UiArt.Gloss == "" or target:FindFirstChildWhichIsA("UIGridStyleLayout") then
		return nil
	end
	local gloss = UIKit.new("ImageLabel", {
		Name = "Gloss",
		Image = UiArt.Gloss,
		ScaleType = Enum.ScaleType.Stretch,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = target.ZIndex,
		Parent = target,
		Children = { if radius == "round" then UIKit.Round() else UIKit.Corner(radius :: number?) },
	})
	gloss:SetAttribute("PP_Skin", true)
	local function follow()
		gloss.ZIndex = target.ZIndex
		gloss.ImageTransparency = if target.BackgroundTransparency >= 0.99 then 1 else target.BackgroundTransparency
	end
	target:GetPropertyChangedSignal("ZIndex"):Connect(follow)
	target:GetPropertyChangedSignal("BackgroundTransparency"):Connect(follow)
	target.ChildAdded:Connect(function(child)
		if child:IsA("UIGridStyleLayout") then
			gloss:Destroy()
		end
	end)
	follow()
	return gloss
end

-- Confetti over a window (Shared/UiArt's Pattern), faint, rounded like it. Its ZIndex is the
-- window's own, so everything in the window draws over it.
function UIKit.Pattern(target: GuiObject, radius: number?, transparency: number?): ImageLabel?
	if UiArt.Pattern == "" then
		return nil
	end
	local pattern = UIKit.new("ImageLabel", {
		Name = "Pattern",
		Image = UiArt.Pattern,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(256, 256),
		ImageTransparency = transparency or 0.9,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = target.ZIndex,
		Parent = target,
		Children = { UIKit.Corner(radius) },
	})
	pattern:SetAttribute("PP_Skin", true)
	return pattern
end

function UIKit.TextStroke(transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = Theme.Colors.Ink,
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

-- A label. Text that starts with an emoji the game has a picture for shows the picture (UI/Icons);
-- KeepEmoji = true keeps the emoji.
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
	local keep = defaults.KeepEmoji
	defaults.KeepEmoji = nil
	local label = UIKit.new("TextLabel", defaults, children)
	if not keep then
		Icons.Decorate(label)
	end
	return label
end

-- Rounded panel with a gradient and a dark ink outline.
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
	table.insert(children, UIKit.Stroke(Theme.Colors.Ink, 3, 0))
	return UIKit.new("Frame", defaults, children)
end

local clickHandler: (() -> ())? = nil
function UIKit.SetClickHandler(handler: () -> ())
	clickHandler = handler
end

-- Chunky button with hover and press animation. `onClick` fires on activation. It wears a thick ink
-- outline in its own colour's darkest shade and a shine (UIKit.Gloss); text that starts with an
-- emoji the game has a picture for shows the picture (UI/Icons; KeepEmoji = true keeps the emoji).
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
	local keep = defaults.KeepEmoji
	defaults.KeepEmoji = nil
	local low = bottom or Color3.fromRGB(200, 50, 140)
	table.insert(children, if radius == "round" then UIKit.Round() else UIKit.Corner(radius))
	table.insert(children, UIKit.Gradient(top or Theme.Colors.Pink, low))
	table.insert(children, UIKit.Stroke(UIKit.InkFor(low), 3, 0))
	table.insert(children, UIKit.TextStroke(0.2))
	local scale = UIKit.new("UIScale", { Scale = 1 })
	table.insert(children, scale)
	local button = UIKit.new("TextButton", defaults, children)
	if button.BackgroundTransparency < 0.99 then
		UIKit.Gloss(button, radius)
	end
	if not keep then
		Icons.Decorate(button)
	end

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
			if clickHandler then
				clickHandler()
			end
			onClick()
		end)
	end
	return button
end

-- Keeps a container at a comfortable size on every screen, from phones to 4K monitors.
-- The scale for a screen this size (in points): the design size fitted to it, kept between
-- Theme.MinScale and Theme.MaxScale. Every phone gets MinScale (see Theme).
function UIKit.ScaleFor(viewport: Vector2, bias: number?): number
	local raw = math.min(viewport.X / Theme.DesignSize.X, viewport.Y / Theme.DesignSize.Y)
	return math.clamp(raw * (bias or 1), Theme.MinScale, Theme.MaxScale)
end

-- The scale UIKit.AutoScale gives the current screen (layouts that line up with scaled HUD parts).
function UIKit.CurrentScale(bias: number?): number
	return UIKit.ScaleFor(workspace.CurrentCamera.ViewportSize, bias)
end

function UIKit.AutoScale(container: GuiObject, bias: number?): UIScale
	local uiScale = UIKit.new("UIScale", { Parent = container })
	-- Lets the UI checks redo the scale per screen (tools/checks/gui_dump.luau, ui_render.py).
	uiScale:SetAttribute("AutoScale", bias or 1)
	local camera = workspace.CurrentCamera
	local function update()
		uiScale.Scale = UIKit.ScaleFor(camera.ViewportSize, bias)
	end
	-- Lives as long as the UIScale: a mode's HUD (destroyed with its round) mustn't leave a handler
	-- on the camera behind every round.
	local resized = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	uiScale.Destroying:Connect(function()
		resized:Disconnect()
	end)
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

-- A coin: the game's own coin picture (UI/Icons), a little bigger than the box so the coin itself
-- fills it; without the art, a drawn gold disc with a rim. (Not the 🪙 emoji: phones don't show it.)
function UIKit.Coin(props: Props): Frame
	local defaults: Props = {
		Name = "Coin",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(24, 24),
	}
	for key, value in props do
		defaults[key] = value
	end
	if Icons.Name("Coin") then
		defaults.BackgroundTransparency = 1
		local holder = UIKit.new("Frame", defaults)
		Icons.Image("Coin", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.3, 1.3),
			ZIndex = holder.ZIndex,
			Parent = holder,
		})
		return holder
	end
	local coin = UIKit.new("Frame", defaults, {
		UIKit.Round(),
		UIKit.Gradient(Color3.fromRGB(255, 236, 120), Color3.fromRGB(240, 160, 30)),
		UIKit.new("UIStroke", { Color = Color3.fromRGB(150, 85, 10), Thickness = 2, Transparency = 0.1 }),
	})
	UIKit.new("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = coin,
		Children = {
			UIKit.Round(),
			UIKit.new("UIStroke", { Color = Color3.fromRGB(255, 250, 200), Thickness = 1.5, Transparency = 0.3 }),
		},
	})
	return coin
end

-- How wide a line of text is, in the units of the layout it sits in (before any UIScale).
-- A font that hasn't loaded yet measures a little narrow, so callers re-measure now and then.
function UIKit.TextWidth(text: string, size: number, font: Enum.Font): number
	local ok, bounds = pcall(TextService.GetTextSize, TextService, text, size, font, Vector2.new(1e4, 1e4))
	return if ok then bounds.X else #text * size * 0.6
end

-- How many lines text wraps onto in a box this wide (with a little slack for a font still loading).
function UIKit.TextLines(text: string, size: number, font: Enum.Font, width: number): number
	local ok, bounds =
		pcall(TextService.GetTextSize, TextService, text, size, font, Vector2.new(math.max(1, width * 0.94), 1e4))
	local height = if ok then bounds.Y else size
	return math.max(1, math.floor(height / size + 0.5))
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

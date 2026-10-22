-- The party screens' look (owner: "Also make the party system insane. I want it to look super
-- epic."): faces in glowing rings of the party's colour, the leader's 👑, level badges in prestige
-- colours (Shared/Progression), emblem medallions, sweeping shines, spinning gradient borders, a
-- countdown ring, pulses and confetti, shared by the PARTY window and its invite card
-- (Controllers/PartyController), the squad bar, the PARTY UP! moment and the SQUAD card
-- (Controllers/SquadController).
--   * Glows are strokes and gradients (no image assets to upload, approve or lose), drawn the same
--     on phones and PC.
--   * Every animation is a looping tween the engine runs (no per-frame code, nothing allocated
--     while it plays); Loop stops it when its object goes, and Group pauses a screen's loops while
--     it's hidden. With reduced effects nothing loops (State.ReducedEffects).
--   * Faces are Roblox headshots (Players:GetUserThumbnailAsync), asked for once per person.
--   * A sunburst (Rays) turns slowly behind a celebration: soft beams through its middle, brightest
--     in the middle and fading out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Progression = require(ReplicatedStorage.Shared.Progression)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local PartyKit = {}

local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(30, 15, 60) -- UIKit's text stroke colour

function PartyKit.Lighter(color: Color3, amount: number): Color3
	return color:Lerp(WHITE, amount)
end

function PartyKit.Darker(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

-- Animation -------------------------------------------------------------------------------------------

-- A screen's looping tweens, paused while it's hidden (a closed window shouldn't animate).
export type Group = { Tweens: { Tween }, Playing: boolean }

function PartyKit.Group(): Group
	return { Tweens = {}, Playing = true }
end

function PartyKit.SetPlaying(group: Group, playing: boolean)
	group.Playing = playing
	for index = #group.Tweens, 1, -1 do
		local tween = group.Tweens[index]
		if tween.PlaybackState == Enum.PlaybackState.Cancelled then
			table.remove(group.Tweens, index)
		elseif playing then
			tween:Play()
		else
			tween:Pause()
		end
	end
end

-- A tween that repeats for as long as `instance` is around (back and forth unless `reverses` is
-- false), in `group` if given. Nothing loops with reduced effects.
function PartyKit.Loop(
	instance: Instance,
	time: number,
	goal: { [string]: any },
	group: Group?,
	options: { Style: Enum.EasingStyle?, Reverses: boolean?, Delay: number? }?
): Tween?
	if State.ReducedEffects() then
		return nil
	end
	local opts = options or {}
	local info = TweenInfo.new(
		time,
		opts.Style or Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		opts.Reverses ~= false,
		opts.Delay or 0
	)
	local tween = TweenService:Create(instance, info, goal)
	instance.Destroying:Connect(function()
		tween:Cancel()
	end)
	if group then
		table.insert(group.Tweens, tween)
		if group.Playing then
			tween:Play()
		end
	else
		tween:Play()
	end
	return tween
end

-- A soft band of light that sweeps across `frame` every `period` seconds (a full-size layer with
-- the frame's own corners and a see-through gradient whose bright middle slides over).
function PartyKit.Shine(
	frame: GuiObject,
	group: Group?,
	options: { Period: number?, ZIndex: number?, Strength: number? }?
): Frame
	local opts = options or {}
	local corner = frame:FindFirstChildOfClass("UICorner")
	local layer = UIKit.new("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = opts.ZIndex or frame.ZIndex,
		Parent = frame,
	})
	if corner then
		UIKit.new("UICorner", { CornerRadius = corner.CornerRadius, Parent = layer })
	end
	local strength = opts.Strength or 0.55
	local gradient = UIKit.new("UIGradient", {
		Rotation = 20,
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, 1 - strength),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = layer,
	})
	PartyKit.Loop(
		gradient,
		1.1,
		{ Offset = Vector2.new(1, 0) },
		group,
		{ Style = Enum.EasingStyle.Quad, Reverses = false, Delay = opts.Period or 2.6 }
	)
	return layer
end

-- A rim of colours that keeps turning round `frame` (its UIStroke, made if it has none).
function PartyKit.SpinBorder(frame: GuiObject, colors: ColorSequence, thickness: number, group: Group?): UIStroke
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = UIKit.new("UIStroke", { Parent = frame })
	end
	local rim = stroke :: UIStroke
	rim.Color = WHITE
	rim.Thickness = thickness
	rim.Transparency = 0
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local gradient = UIKit.new("UIGradient", { Name = "Spin", Color = colors, Rotation = 0, Parent = rim })
	PartyKit.Loop(gradient, 3, { Rotation = 360 }, group, { Style = Enum.EasingStyle.Linear, Reverses = false })
	return rim
end

-- The colours a party's rim turns through: its colour, white and gold.
function PartyKit.RimColors(color: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, PartyKit.Lighter(color, 0.15)),
		ColorSequenceKeypoint.new(0.3, WHITE),
		ColorSequenceKeypoint.new(0.55, Theme.Colors.Yellow),
		ColorSequenceKeypoint.new(0.8, color),
		ColorSequenceKeypoint.new(1, PartyKit.Lighter(color, 0.15)),
	})
end

-- Soft rings of light round a round `frame` (behind it, in its parent): `layers` strokes, each wider
-- and fainter, the outer one breathing in and out. Returns the strokes (recolour them with the party).
function PartyKit.Halo(frame: GuiObject, color: Color3, layers: number, group: Group?): { UIStroke }
	local strokes = {}
	-- The frame's middle in its parent, whatever its anchor.
	local anchor, position, frameSize = frame.AnchorPoint, frame.Position, frame.Size
	local center = UDim2.new(
		position.X.Scale + frameSize.X.Scale * (0.5 - anchor.X),
		position.X.Offset + frameSize.X.Offset * (0.5 - anchor.X),
		position.Y.Scale + frameSize.Y.Scale * (0.5 - anchor.Y),
		position.Y.Offset + frameSize.Y.Offset * (0.5 - anchor.Y)
	)
	for index = 1, layers do
		local grow = 1 + 0.16 * index
		local ring = UIKit.new("Frame", {
			Name = `Halo{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = center,
			Size = UDim2.new(
				frame.Size.X.Scale * grow,
				frame.Size.X.Offset * grow,
				frame.Size.Y.Scale * grow,
				frame.Size.Y.Offset * grow
			),
			BackgroundTransparency = 1,
			ZIndex = math.max(1, frame.ZIndex - 1),
			Parent = frame.Parent,
			Children = { UIKit.Round() },
		})
		local stroke = UIKit.new("UIStroke", {
			Color = color,
			Thickness = 3 + index,
			Transparency = 0.35 + 0.25 * index,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = ring,
		})
		table.insert(strokes, stroke)
		if index == layers then
			local wider = 1 + 0.16 * (index + 0.6)
			PartyKit.Loop(ring, 1.3, {
				Size = UDim2.new(
					frame.Size.X.Scale * wider,
					frame.Size.X.Offset * wider,
					frame.Size.Y.Scale * wider,
					frame.Size.Y.Offset * wider
				),
			}, group)
			PartyKit.Loop(stroke, 1.3, { Transparency = 0.95 }, group)
		end
	end
	return strokes
end

-- Faces -----------------------------------------------------------------------------------------------

local headshots: { [number]: string } = {}
local asking: { [number]: { (string) -> () } } = {}

-- Someone's Roblox headshot, asked for once (it can take a moment): `apply` gets its image.
function PartyKit.Headshot(userId: number, apply: (string) -> ())
	local known = headshots[userId]
	if known then
		apply(known)
		return
	end
	if userId <= 0 then
		apply("") -- a bot or a stand-in: no Roblox avatar
		return
	end
	local waiting = asking[userId]
	if waiting then
		table.insert(waiting, apply)
		return
	end
	asking[userId] = { apply }
	task.spawn(function()
		local ok, url = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size150x150
		)
		local image = if ok and type(url) == "string" then url else ""
		headshots[userId] = image
		local callbacks = asking[userId] or {}
		asking[userId] = nil
		for _, callback in callbacks do
			task.spawn(callback, image)
		end
	end)
end

export type Face = {
	Frame: Frame,
	Disc: Frame,
	Photo: ImageLabel,
	Initial: TextLabel,
	Ring: UIStroke,
	Halo: { UIStroke },
	Crown: TextLabel,
	Badge: Frame?,
	BadgeText: TextLabel?,
	BadgeTint: UIGradient?,
	UserId: number?,
}

-- A face in a ring: `size` units across. Options: Halo (soft glow rings, default on; HaloLayers of
-- them, 2 by default), Badge (a level badge at the bottom right), Group (for the halo's breathing),
-- ZIndex.
function PartyKit.Face(props: {
	Size: number,
	Parent: Instance,
	Name: string?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	ZIndex: number?,
	Halo: boolean?,
	HaloLayers: number?,
	Badge: boolean?,
	Group: Group?,
}): Face
	local size = props.Size
	local z = props.ZIndex or 2
	local holder = UIKit.new("Frame", {
		Name = props.Name or "Face",
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Position = props.Position or UDim2.new(),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = z,
		Parent = props.Parent,
	})
	local disc = UIKit.new("Frame", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.PanelDark,
		ZIndex = z + 1,
		Parent = holder,
		Children = { UIKit.Round() },
	})
	local ring = UIKit.new("UIStroke", {
		Name = "Ring",
		Color = WHITE,
		Thickness = math.max(2, math.floor(size * 0.07 + 0.5)),
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = disc,
	})
	-- Someone's first letter until their headshot comes (or if it never does).
	local initial = UIKit.Label({
		Name = "Initial",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = math.floor(size * 0.46),
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.56, 0.56),
		ZIndex = z + 2,
		Parent = disc,
		Children = { UIKit.TextStroke(0.3) },
	})
	local photo = UIKit.new("ImageLabel", {
		Name = "Photo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.9),
		BackgroundTransparency = 1,
		Image = "",
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = z + 3,
		Parent = disc,
		Children = { UIKit.Round() },
	})
	local halo = if props.Halo == false then {} else PartyKit.Halo(disc, WHITE, props.HaloLayers or 2, props.Group)
	-- The leader's crown: tipped on the ring's top left.
	local crown = UIKit.Label({
		Name = "Crown",
		Text = "👑",
		TextSize = math.floor(size * 0.42),
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.2, 0.06),
		Size = UDim2.fromOffset(math.floor(size * 0.5), math.floor(size * 0.5)),
		Rotation = -22,
		Visible = false,
		ZIndex = z + 5,
		Parent = holder,
	})
	local face: Face = {
		Frame = holder,
		Disc = disc,
		Photo = photo,
		Initial = initial,
		Ring = ring,
		Halo = halo,
		Crown = crown,
		Badge = nil,
		BadgeText = nil,
		BadgeTint = nil,
		UserId = nil,
	}
	if props.Badge then
		local badgeSize = math.max(36, math.floor(size * 0.36))
		local badge = UIKit.new("Frame", {
			Name = "Level",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.86, 0.86),
			Size = UDim2.fromOffset(badgeSize + 10, badgeSize),
			BackgroundColor3 = WHITE,
			ZIndex = z + 6,
			Parent = holder,
			Children = { UIKit.Round(), UIKit.Stroke(WHITE, 2, 0.1) },
		})
		face.BadgeTint = UIKit.new("UIGradient", { Rotation = 90, Parent = badge })
		face.BadgeText = UIKit.Label({
			Name = "Text",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = math.max(Theme.Touch.MinText, math.floor(badgeSize * 0.56)),
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			ZIndex = z + 7,
			Parent = badge,
			Children = { UIKit.TextStroke(0.1) },
		})
		face.Badge = badge
	end
	return face
end

-- Puts someone on a face: their headshot (their initial meanwhile), the party's colour on the ring
-- and its glow, the crown when they lead, and their level (prestige colours) when it has a badge.
function PartyKit.SetFace(face: Face, player: any?, color: Color3, leader: boolean, level: number?)
	local userId = if player then player.UserId else nil
	local ringTint = face.Ring:FindFirstChild("Tint") :: UIGradient?
	if not ringTint then
		ringTint = UIKit.new("UIGradient", { Name = "Tint", Rotation = 90, Parent = face.Ring })
	end
	(ringTint :: UIGradient).Color = ColorSequence.new(PartyKit.Lighter(color, 0.55), color)
	face.Ring.Color = WHITE
	for _, stroke in face.Halo do
		stroke.Color = color
	end
	face.Disc.BackgroundColor3 = PartyKit.Darker(color, 0.55)
	face.Crown.Visible = leader and player ~= nil
	face.Initial.Text = if player then string.upper(string.sub(player.DisplayName, 1, 1)) else ""
	if face.Badge and face.BadgeText and face.BadgeTint then
		local shown = type(level) == "number" and level >= 1
		face.Badge.Visible = shown
		if shown then
			local look = Progression.Look(level :: number)
			face.BadgeTint.Color = look.Gradient
			face.BadgeText.Text = tostring(level)
			local width = UIKit.TextWidth(tostring(level), face.BadgeText.TextSize, Theme.Fonts.Display)
			face.Badge.Size =
				UDim2.fromOffset(math.max(face.Badge.Size.Y.Offset, math.ceil(width) + 16), face.Badge.Size.Y.Offset)
		end
	end
	if face.UserId == userId then
		return
	end
	face.UserId = userId
	face.Photo.Image = ""
	face.Initial.Visible = true
	if userId then
		PartyKit.Headshot(userId, function(image)
			if face.UserId == userId then
				face.Photo.Image = image
				face.Initial.Visible = image == ""
			end
		end)
	end
end

-- Someone's level as the server says (DataService's PP_Level), or nil before it has.
function PartyKit.LevelOf(player: any): number?
	local level = player:GetAttribute("PP_Level")
	return if type(level) == "number" and level >= 1 then math.floor(level) else nil
end

-- Emblems -----------------------------------------------------------------------------------------------

export type Medallion = { Frame: Frame, Icon: TextLabel, Tint: UIGradient, Halo: { UIStroke } }

-- A party's emblem on a glossy disc of its colour with a white rim and a glow.
function PartyKit.Medallion(props: {
	Size: number,
	Parent: Instance,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	ZIndex: number?,
	Halo: boolean?,
	Group: Group?,
}): Medallion
	local z = props.ZIndex or 2
	local frame = UIKit.new("Frame", {
		Name = "Emblem",
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = props.Position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(props.Size, props.Size),
		BackgroundColor3 = WHITE,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = z,
		Parent = props.Parent,
		Children = { UIKit.Round(), UIKit.Stroke(WHITE, math.max(2, math.floor(props.Size * 0.05)), 0) },
	})
	local tint = UIKit.new("UIGradient", { Rotation = 90, Parent = frame })
	local icon = UIKit.Label({
		Name = "Icon",
		Text = "",
		TextSize = math.floor(props.Size * 0.56),
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
		Parent = frame,
	})
	local halo = if props.Halo == false then {} else PartyKit.Halo(frame, WHITE, 2, props.Group)
	return { Frame = frame, Icon = icon, Tint = tint, Halo = halo }
end

function PartyKit.SetMedallion(medallion: Medallion, color: Color3, emblem: string)
	medallion.Icon.Text = emblem
	medallion.Tint.Color = ColorSequence.new(PartyKit.Lighter(color, 0.35), PartyKit.Darker(color, 0.25))
	for _, stroke in medallion.Halo do
		stroke.Color = color
	end
end

-- A sunburst: `count` soft beams through the middle of a square `size` units across, brightest in
-- the middle and fading out, turning slowly (once every `period` seconds) behind whatever sits there.
function PartyKit.Rays(props: {
	Parent: Instance,
	Size: number,
	Position: UDim2,
	Color: Color3,
	Count: number?,
	ZIndex: number?,
	Group: Group?,
	Period: number?,
	Strength: number?,
}): Frame
	local count = props.Count or 8
	local holder = UIKit.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.Position,
		Size = UDim2.fromOffset(props.Size, props.Size),
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	local fade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 1 - (props.Strength or 0.55)),
		NumberSequenceKeypoint.new(1, 1),
	})
	for index = 1, count do
		local ray = UIKit.new("Frame", {
			Name = `Ray{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, math.floor(props.Size * 0.09)),
			Rotation = (index - 1) * 180 / count,
			BackgroundColor3 = props.Color,
			BorderSizePixel = 0,
			ZIndex = props.ZIndex or 1,
			Parent = holder,
		})
		UIKit.new("UIGradient", { Transparency = fade, Parent = ray })
	end
	PartyKit.Loop(
		holder,
		props.Period or 14,
		{ Rotation = 360 },
		props.Group,
		{ Style = Enum.EasingStyle.Linear, Reverses = false }
	)
	return holder
end

-- A soft neon glow round a frame, behind it in its parent: a stroke of `color` that breathes.
function PartyKit.Glow(frame: GuiObject, color: Color3, thickness: number, group: Group?): UIStroke
	local corner = frame:FindFirstChildOfClass("UICorner")
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		AnchorPoint = frame.AnchorPoint,
		Position = frame.Position,
		Size = frame.Size,
		BackgroundTransparency = 1,
		ZIndex = math.max(1, frame.ZIndex - 1),
		Parent = frame.Parent,
	})
	if corner then
		UIKit.new("UICorner", { CornerRadius = corner.CornerRadius, Parent = glow })
	end
	local stroke = UIKit.new("UIStroke", { Color = color, Thickness = thickness, Transparency = 0.55, Parent = glow })
	PartyKit.Loop(stroke, 1.2, { Thickness = thickness * 1.8, Transparency = 0.85 }, group)
	-- It follows the frame's size and place (a bar that grows with its party).
	frame:GetPropertyChangedSignal("Size"):Connect(function()
		glow.Size = frame.Size
	end)
	frame:GetPropertyChangedSignal("Position"):Connect(function()
		glow.Position = frame.Position
	end)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		glow.Visible = frame.Visible
	end)
	return stroke
end

-- The streak ------------------------------------------------------------------------------------------

-- The flame's colours by streak tier (Logic/PartyStreak.Tier): warm orange, hot red, blazing purple.
-- (Tier 0, nothing yet, is a calm purple: the first entry.)
local FLAMES = {
	{ Color3.fromRGB(150, 120, 200), Color3.fromRGB(90, 70, 150) },
	{ Color3.fromRGB(255, 190, 70), Color3.fromRGB(255, 110, 40) },
	{ Color3.fromRGB(255, 120, 60), Color3.fromRGB(225, 40, 70) },
	{ Color3.fromRGB(255, 120, 220), Color3.fromRGB(130, 60, 255) },
}

function PartyKit.FlameColors(tier: number): ColorSequence
	local pair = FLAMES[math.clamp(tier, 0, #FLAMES - 1) + 1]
	return ColorSequence.new(pair[1], pair[2])
end

-- Confetti --------------------------------------------------------------------------------------------

local CONFETTI = {
	Theme.Colors.Pink,
	Theme.Colors.Cyan,
	Theme.Colors.Yellow,
	Theme.Colors.Green,
	Color3.fromRGB(150, 110, 255),
}

-- Confetti bursting out of `origin` in `layer` (scaled units), then fluttering down and fading:
-- `colors` first (the party's), then the party colours. Fewer pieces with reduced effects.
function PartyKit.Burst(layer: Instance, origin: UDim2, colors: { Color3 }?, count: number?, reach: number?)
	local total = if State.ReducedEffects() then 8 else (count or 28)
	local far = reach or 220
	for index = 1, total do
		local palette = if colors and index % 2 == 0 then colors else CONFETTI
		local piece = UIKit.new("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = origin,
			Size = UDim2.fromOffset(math.random(9, 13), math.random(14, 20)),
			Rotation = math.random(0, 360),
			BackgroundColor3 = palette[(index % #palette) + 1],
			BorderSizePixel = 0,
			ZIndex = 30,
			Parent = layer,
			Children = if index % 3 == 0 then { UIKit.Round() } else nil,
		})
		local angle = math.rad(math.random(0, 359))
		local distance = far * (0.45 + math.random() * 0.55)
		local out = UDim2.new(
			origin.X.Scale,
			origin.X.Offset + math.cos(angle) * distance,
			origin.Y.Scale,
			origin.Y.Offset + math.sin(angle) * distance * 0.6 - 30
		)
		UIKit.Tween(piece, 0.45, { Position = out, Rotation = piece.Rotation + math.random(-200, 200) })
		local fall = 1 + math.random() * 0.8
		task.delay(0.45, function()
			if piece.Parent then
				UIKit.Tween(piece, fall, {
					Position = UDim2.new(
						out.X.Scale,
						out.X.Offset + math.random(-30, 30),
						out.Y.Scale,
						out.Y.Offset + 140
					),
					Rotation = piece.Rotation + math.random(-360, 360),
					BackgroundTransparency = 1,
				}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end)
		task.delay(0.5 + fall, function()
			piece:Destroy()
		end)
	end
end

-- The countdown ring ----------------------------------------------------------------------------------

export type TimerRing = { Frame: Frame, Right: UIGradient, Left: UIGradient, Rings: { UIStroke } }

-- A ring that runs down like a clock (TimerSet): two halves, each a ring clipped to its side whose
-- stroke shows only the part of a turned, hard-edged gradient still to go. `size` units across,
-- `thickness` thick, round whatever sits in the middle (it's see-through inside).
function PartyKit.TimerRing(props: {
	Size: number,
	Thickness: number,
	Color: Color3,
	Parent: Instance,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	ZIndex: number?,
}): TimerRing
	local size, thick = props.Size, props.Thickness
	local z = props.ZIndex or 2
	local frame = UIKit.new("Frame", {
		Name = "Timer",
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = props.Position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = props.Parent,
	})
	-- The track: the whole ring, faint.
	UIKit.new("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(thick, thick),
		Size = UDim2.fromOffset(size - 2 * thick, size - 2 * thick),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = frame,
		Children = {
			UIKit.Round(),
			UIKit.new("UIStroke", { Color = INK, Thickness = thick, Transparency = 0.45 }),
		},
	})
	local hardEdge = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.499, 0),
		NumberSequenceKeypoint.new(0.501, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	local rings = {}
	local function half(name: string, x: number): UIGradient
		local clip = UIKit.new("Frame", {
			Name = name,
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(size / 2, size),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = z + 1,
			Parent = frame,
		})
		local ring = UIKit.new("Frame", {
			Name = "Ring",
			Position = UDim2.fromOffset(thick - x, thick),
			Size = UDim2.fromOffset(size - 2 * thick, size - 2 * thick),
			BackgroundTransparency = 1,
			ZIndex = z + 1,
			Parent = clip,
			Children = { UIKit.Round() },
		})
		local stroke =
			UIKit.new("UIStroke", { Color = props.Color, Thickness = thick, Transparency = 0, Parent = ring })
		table.insert(rings, stroke)
		return UIKit.new("UIGradient", { Transparency = hardEdge, Rotation = 0, Parent = stroke })
	end
	local right = half("RightHalf", size / 2)
	local left = half("LeftHalf", 0)
	local timer = { Frame = frame, Right = right, Left = left, Rings = rings }
	PartyKit.TimerSet(timer, 1)
	return timer
end

-- How much of the ring is left (1 full, 0 gone): it runs from 12 o'clock round clockwise. A
-- gradient turned by θ (clockwise) leaves the ring from 12 o'clock to θ on the right half, and
-- from 6 o'clock to θ on the left once θ is past 180.
function PartyKit.TimerSet(timer: TimerRing, fraction: number)
	local angle = 360 * math.clamp(fraction, 0, 1)
	timer.Right.Rotation = math.min(angle, 180)
	timer.Left.Rotation = if angle <= 180 then 180 else angle
end

function PartyKit.TimerColor(timer: TimerRing, color: Color3)
	for _, stroke in timer.Rings do
		stroke.Color = color
	end
end

return PartyKit

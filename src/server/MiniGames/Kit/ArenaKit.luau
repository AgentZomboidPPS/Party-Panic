-- Shared building blocks for mini-game arenas: platforms, spawn layouts, signs and hazard warnings.
-- Warnings always pair a color with a shape/icon so color is never the only cue (design doc §12).

local Build = require(script.Parent.Parent.Parent.World.Build)

local ArenaKit = {}

ArenaKit.Colors = {
	Danger = Color3.fromRGB(255, 60, 60),
	Warning = Color3.fromRGB(255, 200, 40),
	Safe = Color3.fromRGB(110, 230, 130),
	Floor = Color3.fromRGB(245, 240, 255),
	FloorAlt = Color3.fromRGB(220, 230, 255),
	Trim = Color3.fromRGB(150, 110, 255),
}

-- World-space CFrame for an offset from the arena origin.
function ArenaKit.At(context, offset: Vector3): CFrame
	return context.Origin * CFrame.new(offset)
end

function ArenaKit.Part(context, props: { [string]: any }): Part
	props.Parent = props.Parent or context.Arena
	return Build.Part(props)
end

function ArenaKit.Decor(context, props: { [string]: any }): Part
	props.Parent = props.Parent or context.Arena
	return Build.Decor(props)
end

-- Spawn points on a circle around `center`, all facing inward.
function ArenaKit.SpawnRing(center: Vector3, radius: number, count: number): { CFrame }
	return Build.Ring(center, radius, math.max(count, 1))
end

-- Spawn points in rows (e.g. a race grid), facing `forward`.
function ArenaKit.SpawnGrid(
	origin: Vector3,
	forward: Vector3,
	columns: number,
	spacing: Vector2,
	count: number
): { CFrame }
	local right = forward:Cross(Vector3.yAxis).Unit
	local points = {}
	for index = 0, math.max(count, 1) - 1 do
		local column = index % columns
		local row = math.floor(index / columns)
		local position = origin + right * ((column - (columns - 1) / 2) * spacing.X) - forward * (row * spacing.Y)
		table.insert(points, CFrame.lookAt(position, position + forward))
	end
	return points
end

-- A flat neon disc with a "!" marker that shows where a hazard is about to land.
function ArenaKit.WarningCircle(context, position: Vector3, radius: number): Part
	local disc = Build.Decor({
		Name = "Warning",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = ArenaKit.Colors.Danger,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		Parent = context.Arena,
	})
	Build.Billboard(disc, "⚠️", {
		Size = UDim2.fromOffset(60, 60),
		StudsOffset = Vector3.new(0, 4, 0),
		MaxDistance = 200,
		AlwaysOnTop = true,
	})
	return disc
end

-- A flat warning strip (e.g. a boulder's path).
function ArenaKit.WarningStrip(context, cframe: CFrame, size: Vector3): Part
	local strip = Build.Decor({
		Name = "WarningStrip",
		Size = size,
		CFrame = cframe,
		Color = ArenaKit.Colors.Danger,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		Parent = context.Arena,
	})
	return strip
end

-- Large readable sign floating over the arena.
function ArenaKit.Sign(context, text: string, cframe: CFrame, size: Vector3): TextLabel
	local board = Build.Decor({
		Name = "Sign",
		Size = size,
		CFrame = cframe,
		Color = Color3.fromRGB(30, 22, 60),
		Parent = context.Arena,
	})
	local front = Build.SurfaceText(board, Enum.NormalId.Front, text, { PixelsPerStud = 14, MaxDistance = 400 })
	local back = Build.SurfaceText(board, Enum.NormalId.Back, text, { PixelsPerStud = 14, MaxDistance = 400 })
	-- Keep both faces in sync when the caller updates the returned label.
	front:GetPropertyChangedSignal("Text"):Connect(function()
		back.Text = front.Text
	end)
	front:GetPropertyChangedSignal("TextColor3"):Connect(function()
		back.TextColor3 = front.TextColor3
	end)
	return front
end

-- Horizontal distance between two points (ignores height).
function ArenaKit.FlatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- Shortest distance from point `p` to segment `a`-`b`, measured on the XZ plane.
function ArenaKit.FlatDistanceToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
	local ap = Vector2.new(p.X - a.X, p.Z - a.Z)
	local lengthSquared = ab:Dot(ab)
	local t = if lengthSquared > 0 then math.clamp(ap:Dot(ab) / lengthSquared, 0, 1) else 0
	return (ap - ab * t).Magnitude
end

-- True when `point` lies inside a box described by its CFrame and size.
function ArenaKit.InBox(point: Vector3, boxCFrame: CFrame, boxSize: Vector3): boolean
	local localPoint = boxCFrame:PointToObjectSpace(point)
	return math.abs(localPoint.X) <= boxSize.X / 2
		and math.abs(localPoint.Y) <= boxSize.Y / 2
		and math.abs(localPoint.Z) <= boxSize.Z / 2
end

function ArenaKit.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * math.clamp(t, 0, 1)
end

return ArenaKit

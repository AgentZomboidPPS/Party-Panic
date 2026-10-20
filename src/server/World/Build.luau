-- Helpers for building geometry from code.
--
-- Performance defaults (design doc §5 "Visual performance", §14 "Performance and stability"):
--   * everything is Anchored unless a caller says otherwise
--   * decoration has CanCollide/CanQuery/CanTouch off so physics and spatial queries skip it
--   * small decoration doesn't cast shadows
--   * repeated props come from MeshLibrary templates (one mesh, cloned) instead of stacks of parts

local Build = {}

export type PartProps = { [string]: any }

local function apply(instance: Instance, props: PartProps?)
	if not props then
		return
	end
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if parent then
		instance.Parent = parent
	end
end

-- A solid, anchored part.
function Build.Part(props: PartProps?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	apply(part, props)
	return part
end

-- Non-interactive decoration: no collisions, queries, touches or shadows.
function Build.Decor(props: PartProps?): Part
	local part = Build.Part()
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	apply(part, props)
	return part
end

function Build.Wedge(props: PartProps?): WedgePart
	local part = Instance.new("WedgePart")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	apply(part, props)
	return part
end

function Build.Folder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function Build.Model(name: string, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = name
	if parent then
		model.Parent = parent
	end
	return model
end

-- Invisible collision-only wall.
function Build.Barrier(props: PartProps?): Part
	local part = Build.Part()
	part.Transparency = 1
	part.CanQuery = false
	part.CastShadow = false
	apply(part, props)
	return part
end

function Build.Weld(a: BasePart, b: BasePart): WeldConstraint
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = a
	weld.Part1 = b
	weld.Parent = a
	return weld
end

-- Sign text on one face of a part.
function Build.SurfaceText(part: BasePart, face: Enum.NormalId, text: string, options: { [string]: any }?): TextLabel
	local opts = options or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = opts.Name or "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.PixelsPerStud or 20
	gui.LightInfluence = opts.LightInfluence or 0
	gui.Brightness = opts.Brightness or 1.2
	gui.MaxDistance = opts.MaxDistance or 250
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = opts.Font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = opts.TextColor3 or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = opts.TextStrokeTransparency or 0.6
	label.Text = text
	label.Parent = gui

	local padding = Instance.new("UIPadding")
	local pad = UDim.new(opts.Padding or 0.06, 0)
	padding.PaddingLeft = pad
	padding.PaddingRight = pad
	padding.PaddingTop = pad
	padding.PaddingBottom = pad
	padding.Parent = label
	return label
end

-- Floating label above a part.
function Build.Billboard(adornee: BasePart, text: string, options: { [string]: any }?): TextLabel
	local opts = options or {}
	local gui = Instance.new("BillboardGui")
	gui.Name = opts.Name or "Label"
	gui.Size = opts.Size or UDim2.fromOffset(240, 60)
	gui.StudsOffset = opts.StudsOffset or Vector3.new(0, 4, 0)
	gui.MaxDistance = opts.MaxDistance or 120
	gui.LightInfluence = 0
	gui.AlwaysOnTop = opts.AlwaysOnTop or false
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = opts.Font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = opts.TextColor3 or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	return label
end

function Build.Light(parent: BasePart, color: Color3, range: number, brightness: number?): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness or 1.5
	light.Shadows = false
	light.Parent = parent
	return light
end

-- Lays out `count` points evenly around a circle.
function Build.Ring(center: Vector3, radius: number, count: number, startAngle: number?): { CFrame }
	local points = {}
	for index = 0, count - 1 do
		local angle = (startAngle or 0) + index / count * math.pi * 2
		local position = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		table.insert(points, CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)))
	end
	return points
end

return Build

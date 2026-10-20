-- Soft, toy-like geometry built at runtime with in-experience CSG (BasePart:UnionAsync).
--
-- Plain parts read as "blocky". Rounding the edges of tiles, platforms and props is the single
-- biggest step toward the bright toy look in the design doc (§13 "Visual identity").
--
-- Performance: each unique shape+size is unioned ONCE into a template and then cloned. A union is
-- a single rendered mesh with a single physics body, so a rounded tile costs the same per copy as
-- a plain part. If CSG is unavailable for any reason the module falls back to plain parts, so the
-- game always works.

local GeometryService = game:GetService("GeometryService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local Build = require(script.Parent.Build)

local Shapes = {}

-- Tools only: when true, every union remembers its pieces (relative to itself) in the PP_Pieces
-- attribute, so offline preview renders can redraw it exactly. Off in the game.
Shapes.RecordPieces = false

local cache: { [string]: BasePart } = {}
local failures = 0
local MAX_FAILURES = 3
local workFolder: Folder? = nil

export type Props = { [string]: any }

local function getWorkFolder(): Folder
	if not workFolder then
		workFolder = Build.Folder("_ShapeWork", ServerStorage)
	end
	return workFolder :: Folder
end

local function piece(size: Vector3, cframe: CFrame, shape: Enum.PartType?): BasePart
	return Build.Part({
		Size = size,
		CFrame = cframe,
		Shape = shape or Enum.PartType.Block,
		Parent = getWorkFolder(),
	})
end

-- Unions `parts` into one UnionOperation, then cuts `cutters` out of it (or returns nil when CSG
-- fails). Every piece is destroyed afterwards.
local function union(parts: { BasePart }, cutters: { BasePart }?): BasePart?
	local all = table.clone(parts)
	if cutters then
		for _, cutter in cutters do
			table.insert(all, cutter)
		end
	end
	local function cleanUp()
		for _, part in all do
			part:Destroy()
		end
	end
	if failures >= MAX_FAILURES or #parts < 2 then
		cleanUp()
		return nil
	end
	local first = parts[1]
	local rest = table.move(parts, 2, #parts, 1, {})
	local ok, result = pcall(function(): BasePart
		if cutters and #cutters > 0 then
			-- Subtracting from a fresh BasePart:UnionAsync result fails on servers ("missing child
			-- data"), so cut shapes go through GeometryService for both steps.
			local options = { SplitApart = false }
			local merged = GeometryService:UnionAsync(first, rest, options)[1]
			local cut = GeometryService:SubtractAsync(merged, cutters, options)[1]
			merged:Destroy()
			return cut :: BasePart
		end
		return first:UnionAsync(rest, Enum.CollisionFidelity.Default, Enum.RenderFidelity.Automatic)
	end)
	if ok and result and Shapes.RecordPieces then
		local pieces = {}
		for _, part in all do
			local relative = result.CFrame:ToObjectSpace(part.CFrame)
			local isCutter = if table.find(parts, part) then 0 else 1
			local entry =
				{ (part :: Part).Shape.Value, part.Size.X, part.Size.Y, part.Size.Z, relative:GetComponents() }
			table.insert(entry, isCutter)
			table.insert(pieces, entry)
		end
		local size = result.Size
		result:SetAttribute("PP_Pieces", HttpService:JSONEncode({ size = { size.X, size.Y, size.Z }, pieces = pieces }))
	end
	cleanUp()
	if not ok or not result then
		failures += 1
		warn(`[Shapes] CSG failed ({failures}/{MAX_FAILURES}), using plain parts: {result}`)
		return nil
	end
	local unionPart = result :: UnionOperation
	unionPart.UsePartColor = true
	unionPart.Anchored = true
	return unionPart
end

local function key(kind: string, ...: number): string
	local parts = { kind }
	for _, value in { ... } do
		table.insert(parts, string.format("%.2f", value))
	end
	return table.concat(parts, "|")
end

local function apply(part: BasePart, props: Props?): BasePart
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if part.Material == Enum.Material.Plastic then
		part.Material = Enum.Material.SmoothPlastic
	end
	if props then
		local parent = props.Parent
		for name, value in props do
			if name ~= "Parent" then
				(part :: any)[name] = value
			end
		end
		if parent then
			part.Parent = parent
		end
	end
	return part
end

local function fromTemplate(cacheKey: string, build: () -> BasePart?, fallback: () -> BasePart, props: Props?): BasePart
	local template = cache[cacheKey]
	if not template then
		template = build() or fallback()
		cache[cacheKey] = template
	end
	return apply(template:Clone(), props)
end

-- A box with every edge and corner rounded (3 boxes + 12 cylinders + 8 spheres, unioned once).
function Shapes.RoundedBox(size: Vector3, radius: number, props: Props?): BasePart
	local r = math.min(radius, size.X / 2 - 0.05, size.Y / 2 - 0.05, size.Z / 2 - 0.05)
	return fromTemplate(key("RoundedBox", size.X, size.Y, size.Z, r), function()
		if r < 0.1 then
			return nil
		end
		local d = 2 * r
		local hx, hy, hz = size.X / 2 - r, size.Y / 2 - r, size.Z / 2 - r
		local parts = {
			piece(Vector3.new(size.X, size.Y - d, size.Z - d), CFrame.identity),
			piece(Vector3.new(size.X - d, size.Y, size.Z - d), CFrame.identity),
			piece(Vector3.new(size.X - d, size.Y - d, size.Z), CFrame.identity),
		}
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(
					parts,
					piece(Vector3.new(size.X - d, d, d), CFrame.new(0, sy * hy, sz * hz), Enum.PartType.Cylinder)
				)
			end
		end
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(
					parts,
					piece(
						Vector3.new(size.Y - d, d, d),
						CFrame.new(sx * hx, 0, sz * hz) * CFrame.Angles(0, 0, math.rad(90)),
						Enum.PartType.Cylinder
					)
				)
			end
		end
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				table.insert(
					parts,
					piece(
						Vector3.new(size.Z - d, d, d),
						CFrame.new(sx * hx, sy * hy, 0) * CFrame.Angles(0, math.rad(90), 0),
						Enum.PartType.Cylinder
					)
				)
			end
		end
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					table.insert(
						parts,
						piece(Vector3.one * d, CFrame.new(sx * hx, sy * hy, sz * hz), Enum.PartType.Ball)
					)
				end
			end
		end
		return union(parts)
	end, function()
		return Build.Part({ Size = size })
	end, props)
end

-- A slab rounded only in top view (vertical sides): cheap and ideal for big floors and tracks.
function Shapes.Slab(size: Vector3, radius: number, props: Props?): BasePart
	local r = math.min(radius, size.X / 2 - 0.05, size.Z / 2 - 0.05)
	return fromTemplate(key("Slab", size.X, size.Y, size.Z, r), function()
		if r < 0.1 then
			return nil
		end
		local d = 2 * r
		local parts = {
			piece(Vector3.new(size.X, size.Y, size.Z - d), CFrame.identity),
			piece(Vector3.new(size.X - d, size.Y, size.Z), CFrame.identity),
		}
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(
					parts,
					piece(
						Vector3.new(size.Y, d, d),
						CFrame.new(sx * (size.X / 2 - r), 0, sz * (size.Z / 2 - r)) * CFrame.Angles(0, 0, math.rad(90)),
						Enum.PartType.Cylinder
					)
				)
			end
		end
		return union(parts)
	end, function()
		return Build.Part({ Size = size })
	end, props)
end

-- A pill shape lying along X (cylinder with hemispherical ends).
function Shapes.Capsule(length: number, diameter: number, props: Props?): BasePart
	return fromTemplate(key("Capsule", length, diameter), function()
		local body = math.max(0.1, length - diameter)
		return union({
			piece(Vector3.new(body, diameter, diameter), CFrame.identity, Enum.PartType.Cylinder),
			piece(Vector3.one * diameter, CFrame.new(-body / 2, 0, 0), Enum.PartType.Ball),
			piece(Vector3.one * diameter, CFrame.new(body / 2, 0, 0), Enum.PartType.Ball),
		})
	end, function()
		return Build.Part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(length, diameter, diameter) })
	end, props)
end

-- Pieces of a "tombstone" (a rectangle with a round top) standing on y = `bottom`, facing Z.
local function tombstonePieces(width: number, top: number, depth: number, bottom: number): { BasePart }
	local radius = width / 2
	local boxTop = math.max(bottom + 0.5, top - radius)
	return {
		piece(Vector3.new(width, boxTop - bottom, depth), CFrame.new(0, (boxTop + bottom) / 2, 0)),
		piece(
			Vector3.new(depth, width, width),
			CFrame.new(0, boxTop, 0) * CFrame.Angles(0, math.rad(90), 0),
			Enum.PartType.Cylinder
		),
	}
end

-- A smooth rounded arch opening along Z: an outer tombstone with an inner one cut out. `ground`
-- is where its feet stand; it's positioned from its real bounding box, so it never sinks.
function Shapes.Arch(
	width: number,
	height: number,
	thickness: number,
	depth: number,
	ground: CFrame,
	props: Props?
): BasePart
	local part = fromTemplate(key("Arch", width, height, thickness, depth), function()
		local inner = width - 2 * thickness
		return union(
			tombstonePieces(width, height, depth, 0),
			tombstonePieces(inner, height - thickness, depth + 2, -1)
		)
	end, function()
		return Build.Part({ Size = Vector3.new(width, thickness, depth) })
	end, props)
	part.CFrame = ground * CFrame.new(0, part.Size.Y / 2, 0)
	return part
end

-- A flat "tombstone" panel (rectangle with a round top) that fits inside Shapes.Arch.
function Shapes.ArchPanel(width: number, height: number, depth: number, ground: CFrame, props: Props?): BasePart
	local part = Shapes.Custom(key("ArchPanel", width, height, depth), function(makePiece)
		local radius = width / 2
		local boxHeight = math.max(0.5, height - radius)
		return {
			makePiece(Vector3.new(width, boxHeight, depth), CFrame.new(0, boxHeight / 2, 0)),
			makePiece(
				Vector3.new(depth, width, width),
				CFrame.new(0, boxHeight, 0) * CFrame.Angles(0, math.rad(90), 0),
				Enum.PartType.Cylinder
			),
		}
	end, Vector3.new(width, height, depth), props)
	part.CFrame = ground * CFrame.new(0, part.Size.Y / 2, 0)
	return part
end

-- Any shape made from primitive pieces, unioned once and cached under `cacheKey`.
-- `build` receives the piece constructor and returns the pieces; `fallbackSize` is used if CSG fails.
function Shapes.Custom(
	cacheKey: string,
	build: (piece: (size: Vector3, cframe: CFrame, shape: Enum.PartType?) -> BasePart) -> { BasePart },
	fallbackSize: Vector3,
	props: Props?
): BasePart
	return fromTemplate("Custom|" .. cacheKey, function()
		return union(build(piece))
	end, function()
		return Build.Part({ Size = fallbackSize })
	end, props)
end

-- Builds templates ahead of time (call from a background thread) so rounds start instantly.
function Shapes.Prewarm(builders: { () -> () })
	for _, builder in builders do
		local ok, err = pcall(builder)
		if not ok then
			warn("[Shapes] prewarm failed:", err)
		end
		task.wait()
	end
end

function Shapes.IsCsgAvailable(): boolean
	return failures < MAX_FAILURES
end

return Shapes

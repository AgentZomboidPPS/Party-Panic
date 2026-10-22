-- Soft, toy-like geometry built at runtime with in-experience CSG (BasePart:UnionAsync).
--
-- Plain parts read as "blocky". Rounding the edges of tiles, platforms and props is the single
-- biggest step toward the bright toy look in the design doc (§13 "Visual identity").
--
-- Performance: each unique shape+size is unioned ONCE into a template and then cloned. A union is
-- a single rendered mesh with a single physics body, so a rounded tile costs the same per copy as
-- a plain part. If CSG is unavailable for any reason the module falls back to plain parts, so the
-- game always works.
--
-- When CSG fails (owner: "Theres invisible stuff you can jump on and hang on in several games"): a
-- shape used to fall back to one plain box the size of its bounds, that box was kept as the shape's
-- template for the rest of the server's life, and after three failures anywhere CSG was never tried
-- again. Hex Meltdown's hexes stand on invisible hex-prism colliders, so on a long-running server
-- the floor could reach about 3 studs past every drawn corner; an arch became a slab across its
-- own doorway. Now a shape built from pieces (Custom, Arch, ArchPanel) is built from those same
-- pieces as plain parts, so it's exactly its shape, and nothing built without CSG is kept: CSG
-- rests for RETRY_AFTER seconds after a failure and is then tried again. Rounded boxes, slabs and
-- capsules still fall back to one plain box or cylinder their size: that's what's drawn and what
-- collides (only the rounding is lost).

local GeometryService = game:GetService("GeometryService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local Build = require(script.Parent.Build)

local Shapes = {}

-- Tools only: when true, every union remembers its pieces (relative to itself) in the PP_Pieces
-- attribute, so offline preview renders can redraw it exactly. Off in the game.
Shapes.RecordPieces = false

local cache: { [string]: BasePart } = {}
local RETRY_AFTER = 20 -- seconds without CSG after a failure; then it's tried again
local pausedUntil = 0
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

local function destroyAll(parts: { BasePart })
	for _, part in parts do
		part:Destroy()
	end
end

-- Unions `parts` into one UnionOperation, then cuts `cutters` out of it, and destroys the pieces.
-- Returns nil when CSG fails or is resting after a failure: the cutters are destroyed then, but
-- `parts` are left as they are for the caller to build the shape from (or destroy).
--
-- A cut shape comes from GeometryService, whose result takes the CFrame of the first part rather
-- than the center of its bounds (BasePart:UnionAsync results are centered). So cut shapes pass
-- `center`, the middle of their final bounds: a speck placed there goes first, which puts the
-- result's CFrame where every caller expects it. The speck must sit inside a cutter or the solid.
local function union(parts: { BasePart }, cutters: { BasePart }?, center: CFrame?): BasePart?
	local positives = table.clone(parts)
	local cutList: { BasePart } = if cutters then cutters else {}
	if center then
		table.insert(positives, 1, piece(Vector3.one * 0.05, center))
	end
	local helpers = table.clone(cutList)
	if center then
		table.insert(helpers, positives[1])
	end
	if os.clock() < pausedUntil or #positives < 2 then
		destroyAll(helpers)
		return nil
	end
	local first = positives[1]
	local rest = table.move(positives, 2, #positives, 1, {})
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
	if not ok or not result then
		destroyAll(helpers)
		pausedUntil = os.clock() + RETRY_AFTER
		warn(`[Shapes] CSG failed, building from plain parts (CSG again in {RETRY_AFTER} s): {result}`)
		return nil
	end
	if Shapes.RecordPieces then
		local pieces = {}
		local function record(part: BasePart, isCutter: number)
			local relative = result.CFrame:ToObjectSpace(part.CFrame)
			local entry =
				{ (part :: Part).Shape.Value, part.Size.X, part.Size.Y, part.Size.Z, relative:GetComponents() }
			table.insert(entry, isCutter)
			table.insert(pieces, entry)
		end
		for _, part in positives do
			record(part, 0)
		end
		for _, part in cutList do
			record(part, 1)
		end
		local size = result.Size
		result:SetAttribute("PP_Pieces", HttpService:JSONEncode({ size = { size.X, size.Y, size.Z }, pieces = pieces }))
	end
	destroyAll(parts)
	destroyAll(helpers)
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

-- What a compound's other pieces copy from the part callers hold.
local SHARED = {
	"Name",
	"Color",
	"Material",
	"MaterialVariant",
	"Transparency",
	"Reflectance",
	"CastShadow",
	"CanCollide",
	"CanQuery",
	"CanTouch",
	"CollisionGroup",
}
local isShared = {}
for _, property in SHARED do
	isShared[property] = true
end

-- A shape CSG couldn't union, as its pieces: plain parts, so what collides is exactly the shape.
-- `pieces` are in the shape's own frame; `props.CFrame` places the middle of their bounds, which is
-- where a union's own frame would be. Callers get the biggest piece, with `props` (name, color,
-- collisions...) applied; the others sit inside it as its children and copy those, now and whenever
-- they change on the server, so code that looks a part up by name or walks a model's descendants
-- treats every piece alike. All are anchored where they belong: move the whole shape with
-- Model:PivotTo (as clients and every caller do), not by setting this one part's CFrame.
local function compound(pieces: { BasePart }, props: Props?): BasePart
	local low = Vector3.one * math.huge
	local high = -low
	local main = pieces[1]
	for _, part in pieces do
		local cframe, half = part.CFrame, part.Size / 2
		local x, y, z = cframe.XVector, cframe.YVector, cframe.ZVector
		local extent = Vector3.new(
			math.abs(x.X) * half.X + math.abs(y.X) * half.Y + math.abs(z.X) * half.Z,
			math.abs(x.Y) * half.X + math.abs(y.Y) * half.Y + math.abs(z.Y) * half.Z,
			math.abs(x.Z) * half.X + math.abs(y.Z) * half.Y + math.abs(z.Z) * half.Z
		)
		low = low:Min(cframe.Position - extent)
		high = high:Max(cframe.Position + extent)
		if part.Size.X * part.Size.Y * part.Size.Z > main.Size.X * main.Size.Y * main.Size.Z then
			main = part
		end
	end
	local given: Props = if props then props else {}
	local place = (given.CFrame or CFrame.identity) * CFrame.new(-(low + high) / 2)
	for _, part in pieces do
		part.CFrame = place * part.CFrame
	end
	for name, value in given do
		if name ~= "CFrame" and name ~= "Parent" then
			(main :: any)[name] = value
		end
	end
	local others = {}
	for _, part in pieces do
		if part ~= main then
			for _, property in SHARED do
				(part :: any)[property] = (main :: any)[property]
			end
			part.Parent = main
			table.insert(others, part)
		end
	end
	if #others > 0 then
		main.Changed:Connect(function(property: string)
			if isShared[property] then
				local value = (main :: any)[property]
				for _, part in others do
					(part :: any)[property] = value
				end
			end
		end)
	end
	main.Parent = given.Parent
	return main
end

-- A copy of the shape's cached union, or a new union (then cached). When CSG fails the shape is
-- `fallback(props)`, built fresh and never kept, so the next copy tries CSG again.
local function fromTemplate(
	cacheKey: string,
	build: () -> BasePart?,
	fallback: (props: Props?) -> BasePart,
	props: Props?
): BasePart
	local template = cache[cacheKey]
	if not template then
		template = build()
		if template then
			cache[cacheKey] = template
		end
	end
	if template then
		return apply(template:Clone(), props)
	end
	return fallback(props)
end

-- `pieces` unioned, or nil (the pieces destroyed) when CSG fails.
local function unionOrNil(pieces: { BasePart }): BasePart?
	local result = union(pieces)
	if not result then
		destroyAll(pieces)
	end
	return result
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
		return unionOrNil(parts)
	end, function(fallbackProps)
		return apply(Build.Part({ Size = size }), fallbackProps)
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
		return unionOrNil(parts)
	end, function(fallbackProps)
		return apply(Build.Part({ Size = size }), fallbackProps)
	end, props)
end

-- A pill shape lying along X (cylinder with hemispherical ends).
function Shapes.Capsule(length: number, diameter: number, props: Props?): BasePart
	return fromTemplate(key("Capsule", length, diameter), function()
		local body = math.max(0.1, length - diameter)
		return unionOrNil({
			piece(Vector3.new(body, diameter, diameter), CFrame.identity, Enum.PartType.Cylinder),
			piece(Vector3.one * diameter, CFrame.new(-body / 2, 0, 0), Enum.PartType.Ball),
			piece(Vector3.one * diameter, CFrame.new(body / 2, 0, 0), Enum.PartType.Ball),
		})
	end, function(fallbackProps)
		return apply(
			Build.Part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(length, diameter, diameter) }),
			fallbackProps
		)
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

-- The pieces of Shapes.Arch as plain parts, feet on y = 0: two legs up to where the round top
-- starts, and the top as a ring of short blocks round its middle (they cover the arch's band and
-- stay inside it to within a hundredth of its radius).
local function archPieces(width: number, height: number, thickness: number, depth: number): { BasePart }
	local radius = width / 2
	local spring = math.max(0.5, height - radius)
	local band = math.min(thickness, radius)
	local pieces = {}
	for _, side in { -1, 1 } do
		table.insert(
			pieces,
			piece(Vector3.new(band, spring, depth), CFrame.new(side * (radius - band / 2), spring / 2, 0))
		)
	end
	local segments = 12
	local step = math.pi / segments
	for index = 0, segments - 1 do
		table.insert(
			pieces,
			piece(
				Vector3.new(band, 2 * radius * math.tan(step / 2), depth),
				CFrame.new(0, spring, 0)
					* CFrame.Angles(0, 0, (index + 0.5) * step)
					* CFrame.new(radius - band / 2, 0, 0)
			)
		)
	end
	return pieces
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
	local cacheKey = key("Arch", width, height, thickness, depth)
	local template = cache[cacheKey]
	if not template then
		local inner = width - 2 * thickness
		local cutters = tombstonePieces(inner, height - thickness, depth + 2, -1)
		-- A wide, low arch's round top would bulge below its feet: cut off anything under them.
		table.insert(cutters, piece(Vector3.new(width + 2, width, depth + 2), CFrame.new(0, -width / 2, 0)))
		local pieces = tombstonePieces(width, height, depth, 0)
		template = union(pieces, cutters, CFrame.new(0, height / 2, 0))
		if template then
			cache[cacheKey] = template
		else
			destroyAll(pieces)
		end
	end
	if template then
		local part = apply(template:Clone(), props)
		part.CFrame = ground * CFrame.new(0, part.Size.Y / 2, 0)
		return part
	end
	local placed = table.clone(props or {})
	placed.CFrame = ground * CFrame.new(0, (math.max(0.5, height - width / 2) + width / 2) / 2, 0)
	return compound(archPieces(width, height, thickness, depth), placed)
end

-- A flat "tombstone" panel (rectangle with a round top) that fits inside Shapes.Arch.
function Shapes.ArchPanel(width: number, height: number, depth: number, ground: CFrame, props: Props?): BasePart
	local radius = width / 2
	local boxHeight = math.max(0.5, height - radius)
	-- Placed by its bounds (feet on the ground), worked out here so a union and its pieces land alike.
	local placed = table.clone(props or {})
	placed.CFrame = ground * CFrame.new(0, (boxHeight + radius - math.min(0, boxHeight - radius)) / 2, 0)
	return Shapes.Custom(key("ArchPanel", width, height, depth), function(makePiece)
		return {
			makePiece(Vector3.new(width, boxHeight, depth), CFrame.new(0, boxHeight / 2, 0)),
			makePiece(
				Vector3.new(depth, width, width),
				CFrame.new(0, boxHeight, 0) * CFrame.Angles(0, math.rad(90), 0),
				Enum.PartType.Cylinder
			),
		}
	end, Vector3.new(width, height, depth), placed)
end

-- Any shape made from primitive pieces, unioned once and cached under `cacheKey`. `build` receives
-- the piece constructor and returns the pieces, around the shape's middle. When CSG fails the shape
-- is those pieces as plain parts (see compound); `_fallbackSize` is no longer used.
function Shapes.Custom(
	cacheKey: string,
	build: (piece: (size: Vector3, cframe: CFrame, shape: Enum.PartType?) -> BasePart) -> { BasePart },
	_fallbackSize: Vector3,
	props: Props?
): BasePart
	local fullKey = "Custom|" .. cacheKey
	local template = cache[fullKey]
	if not template then
		local pieces = build(piece)
		template = union(pieces)
		if template then
			cache[fullKey] = template
		else
			return compound(pieces, props)
		end
	end
	return apply((template :: BasePart):Clone(), props)
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

-- False for a few seconds after CSG fails (shapes are built from plain parts meanwhile).
function Shapes.IsCsgAvailable(): boolean
	return os.clock() >= pausedUntil
end

-- Tools only: makes the next unions fail as they would on a struggling server (`seconds` of no
-- CSG), so checks can see what gets built instead.
function Shapes.PauseCsgForTests(seconds: number)
	pausedUntil = os.clock() + seconds
	table.clear(cache)
end

return Shapes

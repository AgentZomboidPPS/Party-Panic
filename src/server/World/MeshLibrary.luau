-- Prop library: one template per prop, cloned for every use.
--
-- Why: a prop built from many parts costs a draw call and a physics/query entry per part, every
-- time it appears. A mesh prop is one MeshPart per color, and identical MeshParts are GPU-instanced
-- by the renderer, so a lobby full of trees or a race full of carts stays cheap on mobile.
--
-- Resolution order for each prop (first match wins):
--   1. ServerStorage.MeshTemplates.<Name>  - a Model/MeshPart imported in Studio from assets/meshes
--   2. its uploaded Model asset id           - spec.AssetId, or MeshAssets[<Name>] for older props
--   3. A built-in fallback made from as few primitive parts as possible
--
-- Props that belong to one mini-game live in World/Props/<Game>.luau (see Props/README.md), so modes
-- built side by side never edit the same file. Each returns function(helpers) -> { [name]: Spec }.
--
-- Every template is normalized once: anchored, piece colors applied by name, collision/query/touch
-- flags set for its role, pivot moved to the bottom center so callers can drop it on the ground.
--
-- Scenery the camera can't go inside (owner: "I keep clipping into some chair on fire rope what is
-- going on?"): Roblox's default camera only stops in front of parts that collide, and props don't
-- (so nothing ever snags on them), so it slid right inside Fire Rope's braziers and rope towers and
-- showed their insides. A spec with `BlocksCamera` (true, or the names of the pieces that do) puts
-- those pieces in the CAMERA_SOLID collision group and tags them; each player's device then makes
-- them solid for itself (client Controllers/SceneryCameraController). The group collides with
-- Default only, which is the group the camera's ray uses; every other group (players' characters
-- and everything else a mode sets up) passes through. Here on the server they stay non-colliding,
-- so bots and anything else the server moves never touch them. Only for props that stay still or
-- turn in place: a moving part would push the camera around.
--
-- Collision that follows the drawing (owner: "Theres invisible stuff you can jump on and hang on in
-- several games"): an uploaded mesh comes with Roblox's Default collision, a rough handful of convex
-- hulls that fills hollows and bulges past what's drawn (a palm's trunk and fronds, a broken
-- column's top, a tree's branches, an arch's gold sun: up to 5 studs of invisible ledge to stand or
-- hang on). Scripts can't set a MeshPart's CollisionFidelity, so every piece of a template that
-- collides or stops the camera gets its collision rebuilt once as PreciseConvexDecomposition (see
-- preciseCollision).

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local PhysicsService = game:GetService("PhysicsService")
local ServerStorage = game:GetService("ServerStorage")

local Build = require(script.Parent.Build)
local MeshAssets = require(script.Parent.MeshAssets)
local Shapes = require(script.Parent.Shapes)

local MeshLibrary = {}

type Spec = {
	Height: number, -- canonical height in studs
	AssetId: number?, -- uploaded Model asset (tools/upload_assets.py fills it in)
	Collide: boolean?,
	Touch: boolean?,
	BlocksCamera: (boolean | { string })?, -- solid to the camera only (see the top): all pieces, or these
	-- Collision that follows the drawing (see preciseCollision): nil = for the pieces that collide or stop
	-- the camera, true = every piece (a client makes it solid itself), false = none (the rough hull is better)
	Precise: boolean?,
	Shadow: boolean?,
	Palette: { [string]: Color3 },
	Materials: { [string]: Enum.Material }?,
	Fallback: (model: Model) -> (),
	PostProcess: ((model: Model) -> ())?,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Fallback helpers. `y` is measured from the ground (the prop's pivot).
local function block(model: Model, name: string, size: Vector3, position: Vector3): Part
	return Build.Part({ Name = name, Size = size, CFrame = CFrame.new(position), Parent = model })
end

local function ball(model: Model, name: string, diameter: number, position: Vector3): Part
	return Build.Part({
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = CFrame.new(position),
		Parent = model,
	})
end

-- Vertical cylinder (Roblox cylinders run along X, so rotate onto Y).
local function pillar(model: Model, name: string, diameter: number, height: number, position: Vector3): Part
	return Build.Part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = model,
	})
end

-- Cylinder lying along X.
local function roller(model: Model, name: string, diameter: number, length: number, position: Vector3): Part
	return Build.Part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = CFrame.new(position),
		Parent = model,
	})
end

-- One part rendered as an ellipsoid (SpecialMesh avoids stacking spheres for squashed shapes).
local function blob(model: Model, name: string, size: Vector3, position: Vector3): Part
	local part = block(model, name, size, position)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Rounded helpers for fallbacks (one CSG union each, cached by Shapes).
local function rounded(model: Model, name: string, size: Vector3, radius: number, position: Vector3): BasePart
	return Shapes.RoundedBox(size, radius, { Name = name, CFrame = CFrame.new(position), Parent = model })
end

local function capsule(model: Model, name: string, length: number, diameter: number, cframe: CFrame): BasePart
	return Shapes.Capsule(length, diameter, { Name = name, CFrame = cframe, Parent = model })
end

-- Several overlapping spheres unioned into one soft blob (canopies, bushes, rocks).
local function cluster(model: Model, name: string, key: string, spheres: { { number } }, position: Vector3): BasePart
	local part = Shapes.Custom(key, function(piece)
		local pieces = {}
		for _, sphere in spheres do
			table.insert(
				pieces,
				piece(Vector3.one * sphere[4], CFrame.new(sphere[1], sphere[2], sphere[3]), Enum.PartType.Ball)
			)
		end
		return pieces
	end, Vector3.one * spheres[1][4], { Name = name, CFrame = CFrame.new(position), Parent = model })
	return part
end

-- The fallback builders: as few pieces as possible, rounded wherever it shows.
local SPECS: { [string]: Spec } = {
	ShoppingCart = {
		Height = 4.2,
		Palette = {
			Basket = rgb(205, 215, 225),
			Chassis = rgb(150, 155, 170),
			Frame = rgb(230, 60, 70),
			Wheels = rgb(40, 40, 50),
		},
		Materials = { Basket = Enum.Material.Metal, Chassis = Enum.Material.Metal },
		Fallback = function(m)
			rounded(m, "Basket", Vector3.new(3.8, 2.2, 4.6), 0.3, Vector3.new(0, 2.6, -0.6))
			rounded(m, "Frame", Vector3.new(3.6, 0.35, 5.2), 0.15, Vector3.new(0, 1.15, -0.3))
			capsule(m, "Frame", 4.2, 0.4, CFrame.new(0, 4, 2.6))
			for _, x in { -1.6, 1.6 } do
				for _, z in { -2.4, 1.8 } do
					roller(m, "Wheels", 0.9, 0.4, Vector3.new(x, 0.45, z))
				end
			end
		end,
	},
	YeetGlove = {
		Height = 2.4,
		Palette = { Glove = rgb(235, 50, 70), Cuff = rgb(250, 250, 250) },
		Fallback = function(m)
			cluster(
				m,
				"Glove",
				"Glove",
				{ { 0, 0, 0, 2.4 }, { -0.95, 0.2, -0.3, 1.1 }, { 0, 0.35, -0.55, 1.9 } },
				Vector3.new(0, 1.2, -0.4)
			)
			capsule(m, "Cuff", 1.2, 1.7, CFrame.new(0, 1.2, 1.1) * CFrame.Angles(0, math.rad(90), 0))
		end,
	},
	Anvil = {
		Height = 4.5,
		Collide = true,
		Palette = { Anvil = rgb(70, 72, 82) },
		Materials = { Anvil = Enum.Material.Metal },
		Fallback = function(m)
			rounded(m, "Anvil", Vector3.new(4, 1.2, 3), 0.3, Vector3.new(0, 0.6, 0))
			rounded(m, "Anvil", Vector3.new(2.2, 1.7, 1.8), 0.3, Vector3.new(0, 2, 0))
			rounded(m, "Anvil", Vector3.new(4.6, 1.3, 2.4), 0.35, Vector3.new(0.2, 3.45, 0))
			capsule(m, "Anvil", 2.6, 1.1, CFrame.new(-2.7, 3.6, 0))
		end,
	},
	Boulder = {
		Height = 8,
		Collide = true,
		Palette = { Rock = rgb(140, 120, 105) },
		Materials = { Rock = Enum.Material.Slate },
		Fallback = function(m)
			cluster(m, "Rock", "Boulder", {
				{ 0, 0, 0, 7.4 },
				{ 1.4, 0.8, 0.6, 5.2 },
				{ -1.3, 0.5, -0.9, 5 },
				{ 0.3, -1.2, 1.4, 4.6 },
			}, Vector3.new(0, 4, 0))
		end,
	},
	MalletHead = {
		Height = 4.5,
		Collide = true,
		Palette = { Head = rgb(255, 90, 80), Bands = rgb(255, 235, 200) },
		Fallback = function(m)
			capsule(m, "Head", 7.5, 4.5, CFrame.new(0, 2.25, 0))
			for _, x in { -2.2, 2.2 } do
				roller(m, "Bands", 4.7, 0.5, Vector3.new(x, 2.25, 0))
			end
		end,
	},
	Treasure = {
		Height = 2.2,
		Touch = true,
		Palette = { Gold = rgb(255, 205, 50) },
		Materials = { Gold = Enum.Material.Neon },
		Fallback = function(m)
			roller(m, "Gold", 2.2, 0.45, Vector3.new(0, 1.1, 0))
		end,
	},
	Chest = {
		Height = 4.4,
		Collide = true,
		Palette = { Body = rgb(150, 95, 55), Lid = rgb(120, 75, 45), Trim = rgb(255, 205, 60) },
		Materials = { Body = Enum.Material.WoodPlanks, Lid = Enum.Material.WoodPlanks },
		Fallback = function(m)
			rounded(m, "Body", Vector3.new(5, 2.7, 3.4), 0.35, Vector3.new(0, 1.35, 0))
			capsule(m, "Lid", 5.6, 2.8, CFrame.new(0, 2.9, 0))
			rounded(m, "Trim", Vector3.new(0.8, 1.2, 0.5), 0.2, Vector3.new(0, 2.6, -1.75))
		end,
	},
	Trophy = {
		Height = 7,
		Collide = true,
		Palette = { Cup = rgb(255, 200, 50), Base = rgb(60, 50, 80) },
		Materials = { Cup = Enum.Material.Metal },
		Fallback = function(m)
			rounded(m, "Base", Vector3.new(3, 1, 3), 0.3, Vector3.new(0, 0.5, 0))
			pillar(m, "Cup", 0.9, 2.2, Vector3.new(0, 2.1, 0))
			cluster(m, "Cup", "TrophyCup", { { 0, 0, 0, 3.2 }, { 0, 0.9, 0, 3.4 } }, Vector3.new(0, 4.4, 0))
			for _, x in { -1.9, 1.9 } do
				capsule(m, "Cup", 1.8, 0.5, CFrame.new(x, 4.8, 0) * CFrame.Angles(0, 0, math.rad(90)))
			end
			ball(m, "Cup", 1.2, Vector3.new(0, 6.4, 0))
		end,
	},
	Tree = {
		Height = 16,
		Collide = true,
		Palette = { Trunk = rgb(120, 80, 50), Leaves = rgb(80, 190, 90) },
		Materials = { Trunk = Enum.Material.Wood },
		Fallback = function(m)
			pillar(m, "Trunk", 1.6, 8, Vector3.new(0, 4, 0))
			cluster(m, "Leaves", "TreeCanopy", {
				{ 0, 0, 0, 8.5 },
				{ 2.4, -0.8, 1, 6 },
				{ -2.2, -0.6, -1.4, 6.2 },
				{ 0.4, 3.2, 0.2, 6 },
			}, Vector3.new(0, 10.2, 0))
		end,
	},
	Bush = {
		Height = 4,
		Palette = { Leaves = rgb(70, 175, 85), Flowers = rgb(255, 130, 190) },
		Fallback = function(m)
			cluster(
				m,
				"Leaves",
				"Bush",
				{ { 0, 0, 0, 4.2 }, { 1.8, -0.4, 0.4, 3.4 }, { -1.7, -0.5, -0.3, 3.3 } },
				Vector3.new(0, 2, 0)
			)
		end,
	},
	Balloon = {
		Height = 7.2,
		Palette = { Balloon = rgb(255, 90, 140), String = rgb(240, 240, 240) },
		Materials = { Balloon = Enum.Material.Glass },
		Fallback = function(m)
			pillar(m, "String", 0.08, 4, Vector3.new(0, 2, 0))
			blob(m, "Balloon", Vector3.new(2.6, 3.2, 2.6), Vector3.new(0, 5.6, 0))
			ball(m, "Balloon", 0.45, Vector3.new(0, 4, 0))
		end,
	},
	Bench = {
		Height = 3.4,
		Collide = true,
		Palette = { Bench = rgb(190, 130, 80), Legs = rgb(70, 70, 80) },
		Materials = { Bench = Enum.Material.WoodPlanks },
		Fallback = function(m)
			rounded(m, "Bench", Vector3.new(8, 0.5, 2.4), 0.2, Vector3.new(0, 1.65, 0))
			rounded(m, "Bench", Vector3.new(8, 1.4, 0.4), 0.18, Vector3.new(0, 2.7, 1.1))
			rounded(m, "Legs", Vector3.new(0.6, 1.4, 2.2), 0.25, Vector3.new(-3.2, 0.7, 0))
			rounded(m, "Legs", Vector3.new(0.6, 1.4, 2.2), 0.25, Vector3.new(3.2, 0.7, 0))
		end,
		PostProcess = function(m)
			-- An invisible Seat makes every bench sittable regardless of how it was built.
			local _, size = m:GetBoundingBox()
			local seat = Instance.new("Seat")
			seat.Name = "SeatSpot"
			seat.Anchored = true
			seat.Transparency = 1
			seat.CanQuery = false
			seat.Size = Vector3.new(size.X * 0.8, 0.4, 1.6)
			seat.CFrame = m:GetPivot() * CFrame.new(0, 1.95, -0.2)
			seat.Parent = m
		end,
	},
	LampPost = {
		Height = 12.4,
		Palette = { Pole = rgb(60, 60, 75), Lamp = rgb(255, 235, 180) },
		Materials = { Pole = Enum.Material.Metal, Lamp = Enum.Material.Neon },
		Fallback = function(m)
			pillar(m, "Pole", 1.6, 0.6, Vector3.new(0, 0.3, 0))
			pillar(m, "Pole", 0.6, 11, Vector3.new(0, 5.5, 0))
			ball(m, "Lamp", 1.8, Vector3.new(0, 11.5, 0))
		end,
	},
	GiftBox = {
		Height = 4.6,
		Collide = true,
		Palette = { Box = rgb(120, 90, 255), Ribbon = rgb(255, 220, 70) },
		Fallback = function(m)
			rounded(m, "Box", Vector3.new(4, 4, 4), 0.4, Vector3.new(0, 2, 0))
			rounded(m, "Ribbon", Vector3.new(4.12, 4.12, 0.7), 0.3, Vector3.new(0, 2, 0))
			rounded(m, "Ribbon", Vector3.new(0.7, 4.12, 4.12), 0.3, Vector3.new(0, 2, 0))
			cluster(m, "Ribbon", "GiftBow", { { -0.6, 0, 0, 1.2 }, { 0.6, 0, 0, 1.2 } }, Vector3.new(0, 4.3, 0))
		end,
	},
	Cone = {
		Height = 3,
		Collide = true,
		Palette = { Cone = rgb(255, 130, 40), Stripe = rgb(250, 250, 250) },
		Fallback = function(m)
			rounded(m, "Cone", Vector3.new(2.4, 0.3, 2.4), 0.12, Vector3.new(0, 0.15, 0))
			Shapes.Custom("TrafficCone", function(piece)
				local pieces = {}
				for index = 0, 5 do
					local diameter = 1.6 - index * 0.24
					table.insert(
						pieces,
						piece(
							Vector3.new(0.48, diameter, diameter),
							CFrame.new(0, index * 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)),
							Enum.PartType.Cylinder
						)
					)
				end
				return pieces
			end, Vector3.new(1.4, 2.7, 1.4), { Name = "Cone", CFrame = CFrame.new(0, 0.55, 0), Parent = m })
			pillar(m, "Stripe", 1.12, 0.35, Vector3.new(0, 1.55, 0))
		end,
	},
	-- Backdrop for the lava arenas; its lava runs face -Z.
	Volcano = {
		Height = 62,
		Shadow = false,
		Palette = { Rock = rgb(62, 46, 52), Lava = rgb(255, 120, 40) },
		Materials = { Rock = Enum.Material.Basalt, Lava = Enum.Material.Neon },
		Fallback = function(m)
			for index = 0, 3 do
				pillar(m, "Rock", 100 - index * 24, 16, Vector3.new(0, 8 + index * 15, 0))
			end
			pillar(m, "Lava", 22, 0.6, Vector3.new(0, 61.7, 0))
		end,
	},
	Spire = {
		Height = 20.4,
		Collide = true,
		Palette = { Rock = rgb(66, 50, 56), Glow = rgb(255, 130, 40) },
		Materials = { Rock = Enum.Material.Basalt, Glow = Enum.Material.Neon },
		Fallback = function(m)
			blob(m, "Rock", Vector3.new(7, 20.4, 7), Vector3.new(0, 10.2, 0))
			blob(m, "Rock", Vector3.new(4, 11, 4), Vector3.new(4, 5.5, 1.5))
			ball(m, "Glow", 1.6, Vector3.new(3, 0.3, -2.6))
		end,
	},
	-- Turns Fire Rope's rope; stands in the YZ plane with its axle along X.
	FireWheel = {
		Height = 22.7,
		Palette = { Rim = rgb(70, 55, 62), Spokes = rgb(255, 140, 50), Hub = rgb(255, 200, 60) },
		Materials = { Rim = Enum.Material.Metal, Spokes = Enum.Material.Neon },
		Fallback = function(m)
			roller(m, "Rim", 22.7, 1.2, Vector3.new(0, 11.35, 0))
			for spoke = 0, 3 do
				Build.Part({
					Name = "Spokes",
					Size = Vector3.new(1.4, 19, 1),
					CFrame = CFrame.new(-0.7, 11.35, 0) * CFrame.Angles(spoke * math.pi / 4, 0, 0),
					Parent = m,
				})
			end
			roller(m, "Hub", 3.4, 2.6, Vector3.new(0, 11.35, 0))
		end,
	},
	-- Honey Trap's giant tree. "Anchor" marks the tip of the front branch, where the vine hangs.
	HoneyTree = {
		Height = 57.9,
		Collide = true,
		Palette = {
			Trunk = rgb(125, 84, 56),
			Leaves = rgb(96, 186, 88),
			Hive = rgb(240, 176, 60),
			Anchor = rgb(125, 84, 56),
		},
		Fallback = function(m)
			pillar(m, "Trunk", 9, 38, Vector3.new(0, 19, 0))
			cluster(m, "Leaves", "HoneyTreeLeaves", {
				{ 0, 0, 0, 26 },
				{ -11.5, -4, -2, 19 },
				{ 11.5, -4, 2, 19 },
				{ 0, -4, 11, 18 },
				{ 0, -4.5, -10.5, 17 },
			}, Vector3.new(0, 45, 0))
			blob(m, "Hive", Vector3.new(6, 6.4, 6), Vector3.new(9.8, 29, 2.2))
			rounded(m, "Trunk", Vector3.new(3, 3, 14), 1.4, Vector3.new(0, 30.5, -8))
			ball(m, "Anchor", 0.6, Vector3.new(0, 29.6, -14.5))
		end,
	},
	Fruit = {
		Height = 2.25,
		Palette = { Fruit = rgb(235, 60, 60), Stem = rgb(90, 140, 50) },
		Fallback = function(m)
			ball(m, "Fruit", 2.2, Vector3.new(0, 1.1, 0))
			block(m, "Stem", Vector3.new(0.15, 0.5, 0.15), Vector3.new(0, 2.25, 0))
		end,
	},
	Honeycomb = {
		Height = 3.85,
		Palette = { Comb = rgb(240, 170, 40), Honey = rgb(255, 200, 60) },
		Fallback = function(m)
			Shapes.Custom("HoneycombFallback", function(piece)
				local pieces = {}
				for index = 0, 2 do
					table.insert(
						pieces,
						piece(Vector3.new(1.5, 2.6, 0.9), CFrame.Angles(0, 0, index * math.pi / 3), Enum.PartType.Block)
					)
				end
				return pieces
			end, Vector3.new(2.6, 2.6, 0.9), { Name = "Comb", CFrame = CFrame.new(0, 2.5, 0), Parent = m })
			ball(m, "Honey", 0.5, Vector3.new(0, 0.9, 0))
		end,
	},
	Bee = {
		Height = 1.23,
		Palette = { Body = rgb(255, 205, 40), Stripes = rgb(40, 30, 30), Wings = rgb(240, 250, 255) },
		Fallback = function(m)
			blob(m, "Body", Vector3.new(1.1, 1, 1.44), Vector3.new(0, 0.62, 0))
			ball(m, "Stripes", 0.72, Vector3.new(0, 0.72, -0.72))
			blob(m, "Wings", Vector3.new(0.84, 0.08, 0.52), Vector3.new(0, 1.15, 0))
		end,
	},
	Basket = {
		Height = 1.59,
		Palette = { Basket = rgb(205, 150, 85), Rim = rgb(150, 100, 55) },
		Fallback = function(m)
			pillar(m, "Basket", 3.4, 1.4, Vector3.new(0, 0.7, 0))
			pillar(m, "Rim", 3.8, 0.25, Vector3.new(0, 1.45, 0))
		end,
	},
	-- The 1-or-2 block; the client writes the numbers on it.
	DiceBlock = {
		Height = 4,
		Palette = { Block = rgb(255, 210, 60) },
		Fallback = function(m)
			rounded(m, "Block", Vector3.new(4, 4, 4), 0.7, Vector3.new(0, 2, 0))
		end,
	},
}

-- Per-mode props (World/Props/*.luau) get the same fallback helpers the specs above use.
local helpers = {
	rgb = rgb,
	block = block,
	ball = ball,
	pillar = pillar,
	roller = roller,
	blob = blob,
	rounded = rounded,
	capsule = capsule,
	cluster = cluster,
	Build = Build,
	Shapes = Shapes,
}
MeshLibrary.Helpers = helpers

local propsFolder = script.Parent:FindFirstChild("Props")
if propsFolder then
	for _, module in propsFolder:GetChildren() do
		if not module:IsA("ModuleScript") then
			continue
		end
		local ok, result = pcall(function()
			return require(module :: any)(helpers)
		end)
		if not ok or type(result) ~= "table" then
			warn(`[MeshLibrary] Props/{module.Name} failed to load: {result}`)
			continue
		end
		for name, spec in result do
			if SPECS[name] then
				warn(`[MeshLibrary] Props/{module.Name} redefines {name}; keeping the first`)
			else
				SPECS[name] = spec
			end
		end
	end
end

local templates: { [string]: Model } = {}
local sources: { [string]: string } = {}
local cameraSolid: { [string]: boolean } = {} -- templates with pieces in CAMERA_SOLID

-- Collision group and tag of the pieces that block the camera (the client uses the same name).
local CAMERA_SOLID = "PP_CameraSolid"

-- Registers CAMERA_SOLID and keeps it colliding with Default only: every other group (players'
-- characters, a mode's own groups, even ones registered since last time) passes through it. Run
-- each time such a prop is placed. False if the groups can't be set up (the pieces then stay plain
-- scenery).
local function setupCameraSolid(): boolean
	local ok = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(CAMERA_SOLID) then
			PhysicsService:RegisterCollisionGroup(CAMERA_SOLID)
		end
		for _, group in PhysicsService:GetRegisteredCollisionGroups() do
			if group.name ~= "Default" and PhysicsService:CollisionGroupsAreCollidable(CAMERA_SOLID, group.name) then
				PhysicsService:CollisionGroupSetCollidable(CAMERA_SOLID, group.name, false)
			end
		end
	end)
	return ok
end

local function blocksCamera(spec: Spec, piece: string): boolean
	local blocks = spec.BlocksCamera
	if type(blocks) == "table" then
		return table.find(blocks, piece) ~= nil
	end
	return blocks == true
end

local function wrapInModel(instance: Instance, name: string): Model
	if instance:IsA("Model") then
		return instance
	end
	local model = Instance.new("Model")
	model.Name = name
	instance.Parent = model
	return model
end

local function fromStudioTemplate(name: string): Model?
	local folder = ServerStorage:FindFirstChild("MeshTemplates")
	local found = folder and folder:FindFirstChild(name)
	if not found then
		return nil
	end
	return wrapInModel(found:Clone(), name)
end

local function fromAsset(name: string, spec: Spec): Model?
	local assetId = spec.AssetId or (MeshAssets :: any)[name]
	if type(assetId) ~= "number" or assetId <= 0 then
		return nil
	end
	local ok, container = pcall(InsertService.LoadAsset, InsertService, assetId)
	if not ok or not container then
		warn(`[MeshLibrary] Couldn't load mesh asset {assetId} for {name}: {container}. Using fallback.`)
		return nil
	end
	local content = container:FindFirstChildWhichIsA("Model") or container:FindFirstChildWhichIsA("BasePart")
	if not content then
		container:Destroy()
		return nil
	end
	local model = wrapInModel(content, name)
	model.Parent = nil
	container:Destroy()
	-- Roblox imports a glTF turned half a turn (glTF's front is +Z, Roblox's is -Z): every piece sits
	-- mirrored across the middle with its mesh turned. Turn it back, so the prop faces -Z as authored
	-- (and as the fallback does).
	model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.pi, 0))
	return model
end

-- Puts a model's pivot at `pivot`. With a PrimaryPart, Model.WorldPivot doesn't stick on servers
-- (the pivot stays at the primary part's center), so set the part's PivotOffset directly.
local function setPivot(model: Model, pivot: CFrame)
	local primary = model.PrimaryPart
	if primary then
		primary.PivotOffset = primary.CFrame:ToObjectSpace(pivot)
	else
		model.WorldPivot = pivot
	end
end

-- Rebuilds these mesh pieces' collision to follow their drawn shape: AssetService makes a MeshPart
-- from the same mesh with PreciseConvexDecomposition and ApplyMesh copies its collision over (about
-- a second each, a prop's pieces side by side, at most REBUILDS_AT_ONCE across the server). Measured
-- on a test server, a palm's, a column's, an arch's and a tree's collision then sits within half a
-- stud of the drawing. A piece whose rebuild fails twice keeps its rough Default collision, and the
-- output says so. Once per template: every copy of a prop shares it.
local PRECISE = { CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition }
local REBUILDS_AT_ONCE = 12 -- across all props (Preload asks for every prop at once)
local rebuilding = 0
local KEPT = {
	"Size",
	"CFrame",
	"Anchored",
	"CanCollide",
	"CanQuery",
	"CanTouch",
	"CollisionGroup",
	"CastShadow",
	"Color",
	"Material",
	"Transparency",
}

local function preciseCollision(name: string, pieces: { MeshPart })
	local remaining = #pieces
	for _, part in pieces do
		task.spawn(function()
			while rebuilding >= REBUILDS_AT_ONCE do
				task.wait()
			end
			rebuilding += 1
			-- (Everything normalize set stays as it was: only the collision shape changes.)
			local kept = {}
			for _, property in KEPT do
				kept[property] = (part :: any)[property]
			end
			local ok, err = false, nil
			for attempt = 1, 2 do
				ok, err = pcall(function()
					local fresh = AssetService:CreateMeshPartAsync(Content.fromUri(part.MeshId), PRECISE)
					part:ApplyMesh(fresh)
					fresh:Destroy()
				end)
				if ok or attempt == 2 then
					break
				end
				task.wait(1)
			end
			for property, value in kept do
				(part :: any)[property] = value
			end
			if not ok then
				warn(`[MeshLibrary] {name}.{part.Name} keeps its rough collision: {err}`)
			end
			rebuilding -= 1
			remaining -= 1
		end)
	end
	while remaining > 0 do
		task.wait()
	end
end

-- Moves the pivot to the bottom center of the model's bounding box.
local function pivotAtBottom(model: Model)
	local box, size = model:GetBoundingBox()
	setPivot(model, CFrame.new((box * CFrame.new(0, -size.Y / 2, 0)).Position))
end

local function normalize(name: string, model: Model, spec: Spec)
	model.Name = name
	model:SetAttribute("PP_Prop", name) -- lets tools (and clones) know which prop this is
	-- Scale imported meshes to the canonical size the game is designed around.
	local _, size = model:GetBoundingBox()
	if size.Y > 0 and math.abs(size.Y - spec.Height) / spec.Height > 0.05 then
		model:ScaleTo(model:GetScale() * spec.Height / size.Y)
	end

	-- (Colliding props already stop the camera.)
	local camera = spec.BlocksCamera ~= nil and spec.Collide ~= true and setupCameraSolid()
	local largest: BasePart? = nil
	local largestVolume = -1
	local solidMeshes: { MeshPart } = {}
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		local part = descendant :: BasePart
		part.Anchored = true
		part.CanCollide = spec.Collide == true
		part.CanQuery = spec.Collide == true or spec.Touch == true
		part.CanTouch = spec.Touch == true
		if camera and blocksCamera(spec, part.Name) then
			part.CollisionGroup = CAMERA_SOLID
			CollectionService:AddTag(part, CAMERA_SOLID)
			cameraSolid[name] = true
		end
		local solid = part.CanCollide or part.CollisionGroup == CAMERA_SOLID
		if part:IsA("MeshPart") and spec.Precise ~= false and (solid or spec.Precise) then
			table.insert(solidMeshes, part)
		end
		local volume = part.Size.X * part.Size.Y * part.Size.Z
		part.CastShadow = spec.Shadow ~= false and volume > 8
		local color = spec.Palette[part.Name]
		if color then
			part.Color = color
		end
		local material = spec.Materials and spec.Materials[part.Name]
		if material then
			part.Material = material
		end
		if volume > largestVolume then
			largest, largestVolume = part, volume
		end
	end
	preciseCollision(name, solidMeshes)

	-- Pivot at the bottom center so `PivotTo(CFrame.new(groundPoint))` sits the prop on the ground.
	model.PrimaryPart = largest
	pivotAtBottom(model)
	if spec.PostProcess then
		spec.PostProcess(model)
	end
end

local function build(name: string, spec: Spec): Model
	local model = fromStudioTemplate(name)
	local source = "Template"
	if not model then
		model = fromAsset(name, spec)
		source = "Asset"
	end
	if not model then
		local built = Instance.new("Model")
		spec.Fallback(built)
		model = built
		source = "Fallback"
	end
	normalize(name, model :: Model, spec)
	templates[name] = model :: Model
	sources[name] = source
	return model :: Model
end

local building: { [string]: boolean } = {} -- templates being made right now (it takes seconds)

local function resolve(name: string): Model
	local cached = templates[name]
	if cached then
		return cached
	end
	local spec = SPECS[name]
	assert(spec, `MeshLibrary has no prop named {name}`)
	-- Someone else (Preload, a round) is making it already: wait for theirs instead of making two.
	while building[name] do
		task.wait()
	end
	if templates[name] then
		return templates[name]
	end
	building[name] = true
	local ok, result = pcall(build, name, spec)
	building[name] = nil
	if not ok then
		error(result, 0)
	end
	return result
end

export type GetOptions = {
	Scale: number?,
	Colors: { [string]: Color3 }?,
	Parent: Instance?,
	CFrame: CFrame?,
}

-- Returns a fresh copy of a prop. Options can rescale, recolor pieces, place and parent it.
function MeshLibrary.Get(name: string, options: GetOptions?): Model
	local model = resolve(name):Clone()
	if cameraSolid[name] then
		setupCameraSolid() -- keeps groups registered since the template was made out of it
	end
	local opts = options or {}
	if opts.Scale and opts.Scale ~= 1 then
		model:ScaleTo(model:GetScale() * opts.Scale)
		pivotAtBottom(model)
	end
	if opts.Colors then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				local color = opts.Colors[descendant.Name]
				if color then
					descendant.Color = color
				end
			end
		end
	end
	if opts.CFrame then
		model:PivotTo(opts.CFrame)
	end
	if opts.Parent then
		model.Parent = opts.Parent
	end
	return model
end

-- Converts a prop into a single unanchored assembly welded to its PrimaryPart (for tools and props
-- carried by characters). Returns the root part.
function MeshLibrary.Assemble(model: Model, massless: boolean): BasePart
	local root = model.PrimaryPart :: BasePart
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = massless
			if descendant:HasTag(CAMERA_SOLID) then -- carried props never block the camera
				descendant:RemoveTag(CAMERA_SOLID)
				descendant.CollisionGroup = "Default"
			end
			if descendant ~= root then
				Build.Weld(root, descendant)
			end
		end
	end
	return root
end

function MeshLibrary.Source(name: string): string
	resolve(name)
	return sources[name]
end

function MeshLibrary.Names(): { string }
	local names = {}
	for name in SPECS do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Resolves every prop up front (in parallel, since asset loads yield) and reports the sources.
function MeshLibrary.Preload()
	local names = MeshLibrary.Names()
	local remaining = #names
	for _, name in names do
		task.spawn(function()
			local ok, err = pcall(resolve, name)
			if not ok then
				warn(`[MeshLibrary] {name}: {err}`)
			end
			remaining -= 1
		end)
	end
	local deadline = os.clock() + 15
	while remaining > 0 and os.clock() < deadline do
		task.wait()
	end
	local counts = { Template = 0, Asset = 0, Fallback = 0 }
	for _, source in sources do
		counts[source] += 1
	end
	print(
		`[MeshLibrary] {#names} props ready - {counts.Template} Studio templates, {counts.Asset} uploaded meshes, {counts.Fallback} fallbacks`
	)
end

return MeshLibrary

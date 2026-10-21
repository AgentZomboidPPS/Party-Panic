-- Builds the lobby plaza (design doc §5 "Lobby and Social Hub").
--
-- One compact, round plaza (about 150 studs across) so everything is in view from the spawn:
--
--                              N (-Z)
--        [parkour tower]   [ VOTE STAGE: 3 portal bays ]   [speakers]
--
--   W  [ SHOP / gallery ]       ( fountain + trophy )       [ WINNER PODIUM ]  E (+X)
--
--        [ quests + daily gift ]    [ emote stage ]    [ arcade range ]
--                              S (+Z)
--
-- Spawns face the vote stage, the one obvious landmark. Colored walkways run from the fountain to
-- each zone. Trees, hedges and hills close the view so the plaza feels full, not like a field.
--
-- Look: rounded CSG shapes (World/Shapes), mesh props (World/MeshLibrary) and terrain scenery
-- (World/Environment). Screens showing live or per-player data (vote cards, quest board, podium
-- names) are tagged and rendered by each client. Decorations that move (balloons, trophies) are
-- tagged too and animated on clients, which costs the server nothing.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local Build = require(script.Parent.Build)
local Environment = require(script.Parent.Environment)
local MeshLibrary = require(script.Parent.MeshLibrary)
local Shapes = require(script.Parent.Shapes)

local LobbyBuilder = {}

export type LobbyRefs = {
	Root: Model,
	VotePads: { BasePart },
	DailyPrompt: ProximityPrompt,
	ConfettiPrompt: ProximityPrompt,
	ConfettiPosition: Vector3,
	TokenSpots: { Vector3 },
	Targets: { BasePart },
	TargetBoard: TextLabel,
	BallSpots: { Vector3 },
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local PALETTE = {
	Lawn = rgb(104, 196, 88),
	Grout = rgb(238, 226, 212),
	Curb = rgb(250, 242, 228),
	Trim = rgb(255, 204, 64),
	Backdrop = rgb(80, 50, 164),
	Stage = rgb(92, 64, 168),
	StageDark = rgb(52, 36, 104),
	Bay = rgb(30, 20, 66),
	Portal = { rgb(255, 84, 150), rgb(64, 196, 255), rgb(120, 224, 96) },
	Spawn = rgb(255, 236, 140),
	Wood = rgb(196, 140, 92),
}

local PARTY_COLORS = {
	rgb(255, 84, 150),
	rgb(64, 196, 255),
	rgb(255, 204, 64),
	rgb(156, 108, 255),
	rgb(110, 226, 140),
	rgb(255, 140, 70),
}

local PLAZA_RADIUS = 75
local PAVED_RADIUS = 45.9 -- the court and promenade (LobbyCourt + LobbyPavers); lawn beyond
local SIGN_FONT = Enum.Font.LuckiestGuy
local BUNTING_LENGTH = 24 -- LobbyBunting's length at scale 1

-- Zone anchors (ground level).
local STAGE_Z = -53 -- center of the vote stage platform
local STAGE_TOP = 2.4
local PODIUM = Vector3.new(54, 0, -4)
local SHOP = Vector3.new(-54, 0, -4)
local QUESTS = Vector3.new(-42, 0, 42)
local ARCADE = Vector3.new(42, 0, 42)
local EMOTE = Vector3.new(0, 0, 54)
local PARKOUR = Vector3.new(-58, 0, -50)

LobbyBuilder.PlazaRadius = PLAZA_RADIUS
LobbyBuilder.StageFrontZ = STAGE_Z + 13 -- the vote stage's front edge (its steps are in front)

local function tag(instance: Instance, name: string)
	CollectionService:AddTag(instance, name)
end

local function prompt(parent: BasePart, actionText: string, objectText: string, action: string?): ProximityPrompt
	local proximity = Instance.new("ProximityPrompt")
	proximity.ActionText = actionText
	proximity.ObjectText = objectText
	proximity.HoldDuration = 0
	proximity.MaxActivationDistance = 12
	proximity.RequiresLineOfSight = false
	if action then
		-- Client-handled prompts (open UI) carry their action as an attribute.
		proximity:SetAttribute("Action", action)
	end
	proximity.Parent = parent
	return proximity
end

local function setupLighting()
	-- Warm, sunny haze: golden toward the horizon so the park glows, never a blue wash over the plaza.
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.26
	atmosphere.Offset = 0.2
	atmosphere.Color = rgb(255, 236, 214)
	atmosphere.Decay = rgb(186, 196, 236)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 0.5
	atmosphere.Parent = Lighting

	-- Rich, warm color, and enough bloom that neon bulbs and signs glow.
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Saturation = 0.22
	correction.Contrast = 0.1
	correction.TintColor = rgb(255, 247, 236)
	correction.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.05
	bloom.Parent = Lighting
end

-- A flat cylinder lying on the ground (Roblox cylinders run along X, so it's turned upright).
local function disc(name: string, diameter: number, height: number, position: Vector3, props: { [string]: any }): Part
	props.Name = name
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	return Build.Part(props)
end

local FLAT = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

local function flat(props: { [string]: any }): { [string]: any }
	for key, value in FLAT do
		props[key] = value
	end
	return props
end

-- CFrame at `position` whose Front face looks at `target` (level, no tilt).
local function facing(position: Vector3, target: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
end

-- A string of party lights between two points: a sagging Beam plus a few glowing bulbs.
local function lightString(parent: Instance, from: Vector3, to: Vector3, sag: number, colorIndex: number)
	local holder = Build.Decor({
		Name = "LightString",
		Size = Vector3.one * 0.2,
		Transparency = 1,
		CFrame = CFrame.new(from),
		Parent = parent,
	})
	local endPoint = Build.Decor({
		Name = "LightStringEnd",
		Size = Vector3.one * 0.2,
		Transparency = 1,
		CFrame = CFrame.new(to),
		Parent = parent,
	})
	local a0 = Instance.new("Attachment")
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.Parent = endPoint
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.18
	beam.Width1 = 0.18
	beam.CurveSize0 = -sag
	beam.CurveSize1 = sag
	beam.Segments = 20
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(rgb(60, 50, 70))
	beam.Parent = holder
	-- Bulbs along a parabola that roughly follows the beam's curve.
	local count = math.max(3, math.floor((to - from).Magnitude / 5))
	for index = 1, count - 1 do
		local t = index / count
		local point = from:Lerp(to, t) - Vector3.new(0, sag * 1.5 * t * (1 - t), 0)
		Build.Decor({
			Name = "Bulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.7,
			CFrame = CFrame.new(point),
			Color = PARTY_COLORS[((index + colorIndex) % #PARTY_COLORS) + 1],
			Material = Enum.Material.Neon,
			Parent = parent,
		})
	end
end

local function sparkleEmitter(parent: BasePart, color: Color3, rate: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(1.5, 2.5)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Rate = rate
	emitter.Parent = parent
	tag(emitter, "PP_Ambient") -- clients with "reduced effects" switch these off
	return emitter
end

-- A sign board with big cartoon lettering on one face.
local function sign(
	parent: Instance,
	text: string,
	size: Vector3,
	cframe: CFrame,
	face: Enum.NormalId,
	color: Color3,
	textColor: Color3?
): BasePart
	local board = Shapes.RoundedBox(size, math.min(size.X, size.Y, size.Z) * 0.45, {
		Name = "Sign",
		CFrame = cframe,
		Color = color,
		Parent = parent,
	})
	Build.SurfaceText(board, face, text, {
		PixelsPerStud = 16,
		Font = SIGN_FONT,
		TextColor3 = textColor or rgb(255, 236, 120),
		TextStrokeTransparency = 0.35,
		Padding = 0.08,
	})
	return board
end

local function balloonCluster(parent: Instance, position: Vector3, firstColor: number)
	for index, offset in { Vector3.new(0, 0, 0), Vector3.new(1.6, 1.2, 0.6), Vector3.new(-1.4, 0.8, -0.8) } do
		local balloon = MeshLibrary.Get("Balloon", {
			Colors = { Balloon = PARTY_COLORS[((firstColor + index) % #PARTY_COLORS) + 1] },
			Scale = 1.3,
			CFrame = CFrame.new(position + offset),
			Parent = parent,
		})
		tag(balloon, "PP_Bob")
	end
end

-- Ground ---------------------------------------------------------------------------------------

local function buildGround(root: Model)
	local ground = Build.Model("Ground", root)
	-- One thick grass disc is the whole walkable plaza; terrain is carved away under it (Environment).
	disc("Plaza", PLAZA_RADIUS * 2, 6, Vector3.new(0, -3, 0), {
		Color = PALETTE.Lawn,
		Material = Enum.Material.Grass,
		Parent = ground,
	})
	-- A cream stone curb just below the plaza edge.
	disc("Curb", PLAZA_RADIUS * 2 + 3, 6, Vector3.new(0, -3.15, 0), { Color = PALETTE.Curb, Parent = ground })
	-- The paved middle: a grout disc with the sunburst court and the promenade's curved tiles on
	-- top (meshes). Every layer's top is a full 0.1 stud above the one under it: surfaces closer
	-- than that flicker (z-fighting) as the camera moves.
	disc(
		"Grout",
		PAVED_RADIUS * 2 + 0.2,
		0.1,
		Vector3.new(0, 0.05, 0),
		flat({ Color = PALETTE.Grout, Material = Enum.Material.Concrete, Parent = ground })
	)
	MeshLibrary.Get("LobbyCourt", { CFrame = CFrame.new(0, 0.1, 0), Parent = ground })
	MeshLibrary.Get("LobbyPavers", { CFrame = CFrame.new(0, 0.1, 0), Parent = ground })

	-- Paved walkways across the lawn to every zone: a white border with the zone's color inside.
	local walkways = {
		{ target = Vector3.new(0, 0, STAGE_Z + 14), width = 16, color = rgb(255, 204, 64) }, -- vote stage
		{ target = PODIUM + Vector3.new(-10, 0, 0), width = 10, color = rgb(255, 96, 110) }, -- podium (red carpet)
		{ target = SHOP + Vector3.new(10, 0, 0), width = 10, color = rgb(255, 120, 190) }, -- shop
		{ target = EMOTE + Vector3.new(0, 0, -12), width = 10, color = rgb(80, 200, 255) }, -- emote stage
		-- (these two stop just short of their corner floors, whose tops share the walkway's height)
		{ target = QUESTS * 0.81, width = 9, color = rgb(160, 120, 255) }, -- quests
		{ target = ARCADE * 0.81, width = 9, color = rgb(100, 220, 140) }, -- arcade
	}
	for _, walk in walkways do
		local direction = Vector3.new(walk.target.X, 0, walk.target.Z).Unit
		local startRadius = PAVED_RADIUS - 3
		local endRadius = Vector3.new(walk.target.X, 0, walk.target.Z).Magnitude
		local length = endRadius - startRadius
		local middle = direction * (startRadius + length / 2)
		for layer = 1, 2 do
			local y = 0.15 + layer * 0.1
			local width = if layer == 1 then walk.width + 1.6 else walk.width
			Shapes.Slab(
				Vector3.new(width, 0.1, length + (if layer == 1 then 1.6 else 0)),
				width * 0.45,
				flat({
					Name = if layer == 1 then "WalkwayEdge" else "Walkway",
					CFrame = CFrame.lookAt(middle + Vector3.new(0, y, 0), middle + Vector3.new(0, y, 0) + direction),
					Color = if layer == 1 then rgb(255, 255, 255) else walk.color,
					Material = if layer == 1 then Enum.Material.SmoothPlastic else Enum.Material.Pavement,
					Parent = ground,
				})
			)
		end
	end

	-- Invisible boundary a little further out, among the trees.
	for index, point in Build.Ring(Vector3.new(0, 25, 0), PLAZA_RADIUS + 30, 28) do
		Build.Barrier({ Name = "Boundary" .. index, Size = Vector3.new(24, 70, 2), CFrame = point, Parent = ground })
	end
end

local function buildSpawns(root: Model)
	local spawns = Build.Model("Spawns", root)
	-- An arc on the stage side of the fountain; everyone spawns looking at the vote stage.
	for index = 1, 7 do
		local angle = math.rad(-90 + (index - 4) * 19)
		local position = Vector3.new(math.cos(angle) * 18, 0, math.sin(angle) * 18)
		local point = CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn" .. index
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Size = Vector3.new(5, 0.2, 5)
		spawn.CFrame = point + Vector3.new(0, 0.7, 0)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Parent = spawns
		disc(
			"SpawnPad",
			5.5,
			0.12,
			position + Vector3.new(0, 0.66, 0),
			flat({
				Color = PALETTE.Spawn,
				Material = Enum.Material.Neon,
				Transparency = 0.35,
				Parent = spawns,
			})
		)
	end
end

-- Central plaza: fountain landmark, seating -----------------------------------------------------

local function waterJet(parent: Instance, from: Vector3, toward: Vector3, speed: number, rate: number)
	-- An arcing stream of spray: the holder's Top face points up and in, toward `toward`.
	local flatDirection = Vector3.new(toward.X - from.X, 0, toward.Z - from.Z).Unit
	local aim = (flatDirection + Vector3.new(0, 1.6, 0)).Unit
	local holder = Build.Decor({
		Name = "Jet",
		Size = Vector3.one * 0.4,
		Transparency = 1,
		CFrame = CFrame.lookAt(from, from + aim) * CFrame.Angles(math.rad(-90), 0, 0),
		Parent = parent,
	})
	local jet = Instance.new("ParticleEmitter")
	jet.Texture = "rbxasset://textures/particles/smoke_main.dds"
	jet.Color = ColorSequence.new(rgb(220, 244, 255))
	jet.LightEmission = 0.3
	jet.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.9) })
	jet.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	jet.Lifetime = NumberRange.new(0.9, 1.1)
	jet.Speed = NumberRange.new(speed, speed * 1.08)
	jet.Acceleration = Vector3.new(0, -workspace.Gravity * 0.16, 0)
	jet.SpreadAngle = Vector2.new(4, 4)
	jet.EmissionDirection = Enum.NormalId.Top
	jet.Rate = rate
	jet.Parent = holder
	tag(jet, "PP_Ambient")
end

local function buildFountain(root: Model)
	local center = Build.Model("Fountain", root)
	local water = {
		Color = rgb(70, 196, 240),
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		Reflectance = 0.2,
	}

	-- The scalloped basin, fluted column and upper bowl are one mesh prop; the water surfaces are
	-- glass discs, and invisible colliders let players wade in (the pool is knee deep).
	local fountain = MeshLibrary.Get("LobbyFountain", { CFrame = CFrame.new(0, 0.2, 0), Parent = center })
	for _, descendant in fountain:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
		end
	end
	local waterDisc = disc("Water", 22.4, 0.2, Vector3.new(0, 2.05, 0), flat({ Parent = center }))
	local upperWater = disc("UpperWater", 9.4, 0.2, Vector3.new(0, 8.3, 0), flat({ Parent = center }))
	for key, value in water do
		(waterDisc :: any)[key] = value;
		(upperWater :: any)[key] = value
	end
	local colliders = Build.Model("Colliders", center)
	disc("PoolFloor", 22.6, 1, Vector3.new(0, 0.6, 0), { Transparency = 1, Parent = colliders })
	disc("ColumnCollider", 3.6, 8.6, Vector3.new(0, 4.5, 0), { Transparency = 1, Parent = colliders })
	for _, point in Build.Ring(Vector3.new(0, 1.6, 0), 12.1, 24) do
		Build.Part({
			Name = "RimCollider",
			Size = Vector3.new(3.4, 2.8, 1.4),
			CFrame = point,
			Transparency = 1,
			Parent = colliders,
		})
	end

	-- Rubber ducks bob in the pool; one rides the top bowl.
	local rng = Random.new(5)
	for index = 1, 6 do
		local angle = (index + rng:NextNumber(-0.25, 0.25)) / 6 * math.pi * 2
		local distance = rng:NextNumber(6.2, 9.2)
		local position = Vector3.new(math.cos(angle) * distance, 1.75, math.sin(angle) * distance)
		local duck = MeshLibrary.Get("LobbyDuck", {
			Scale = if index == 1 then 1.4 else 1,
			CFrame = CFrame.new(position) * CFrame.Angles(0, angle + math.rad(rng:NextNumber(60, 120)), 0),
			Parent = center,
		})
		tag(duck, "PP_Bob")
	end

	-- The landmark: a giant golden trophy that slowly turns (clients animate it).
	local trophy = MeshLibrary.Get("Trophy", { Scale = 1.5, CFrame = CFrame.new(0, 8.6, 0), Parent = center })
	tag(trophy, "PP_Spin")

	-- Water spray from the bowl into the basin, and arcing jets from the rim toward the column.
	local spout = Build.Decor({
		Name = "Spray",
		Size = Vector3.one,
		Transparency = 1,
		CFrame = CFrame.new(0, 8.8, 0),
		Parent = center,
	})
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spray.Color = ColorSequence.new(rgb(225, 245, 255))
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.4) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.9, 1.2)
	spray.Speed = NumberRange.new(9, 11)
	spray.Acceleration = Vector3.new(0, -26, 0)
	spray.SpreadAngle = Vector2.new(35, 35)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Rate = 26
	spray.Parent = spout
	tag(spray, "PP_Ambient")
	Build.Light(spout, rgb(255, 230, 160), 22, 1)
	sparkleEmitter(spout, rgb(255, 230, 140), 4)
	for _, point in Build.Ring(Vector3.new(0, 2.6, 0), 11.2, 8, math.pi / 8) do
		waterJet(center, point.Position, Vector3.zero, 13, 14)
	end
	-- A soft glow from under the water.
	local glow = Build.Decor({
		Name = "PoolGlow",
		Size = Vector3.one,
		Transparency = 1,
		CFrame = CFrame.new(0, 1.4, 0),
		Parent = center,
	})
	Build.Light(glow, rgb(120, 220, 255), 18, 1.2)

	-- Benches facing the fountain, between the walkways (seating from §5).
	for _, degrees in { 0, 50, 130, 180, 200, 340 } do
		local angle = math.rad(degrees)
		local position = Vector3.new(math.cos(angle) * 31, 0, math.sin(angle) * 31)
		MeshLibrary.Get("Bench", { CFrame = facing(position + Vector3.new(0, 0.2, 0), Vector3.zero), Parent = center })
	end
end

-- Vote stage -------------------------------------------------------------------------------------

local function buildVoteStage(root: Model): { BasePart }
	local stage = Build.Model("VoteStage", root)
	local backZ = STAGE_Z - 13

	-- Platform with two wide steps in front.
	Shapes.Slab(Vector3.new(90, STAGE_TOP, 26), 6, {
		Name = "StageFloor",
		CFrame = CFrame.new(0, STAGE_TOP / 2, STAGE_Z),
		Color = PALETTE.Stage,
		Parent = stage,
	})
	Shapes.Slab(Vector3.new(90.6, 0.5, 26.6), 6.2, {
		Name = "StageTrim", -- top sits under the stage top, so only the gold lip shows
		CFrame = CFrame.new(0, STAGE_TOP - 0.4, STAGE_Z),
		Color = PALETTE.Trim,
		Parent = stage,
	})
	for step = 1, 2 do
		local height = STAGE_TOP * step / 3
		Shapes.Slab(Vector3.new(70 - step * 4, height, 3.2), 1.4, {
			Name = "Step",
			CFrame = CFrame.new(0, height / 2, STAGE_Z + 13 + (3 - step) * 3),
			Color = if step == 1 then rgb(130, 100, 210) else rgb(112, 84, 190),
			Parent = stage,
		})
	end

	-- Backdrop: a big rounded wall that holds the screens, with marquee bulbs on top, a scalloped
	-- carnival crown behind them and glowing neon tubes between the portal bays.
	Shapes.RoundedBox(Vector3.new(92, 46, 3), 2, {
		Name = "Backdrop",
		CFrame = CFrame.new(0, STAGE_TOP + 23, backZ - 1),
		Color = PALETTE.Backdrop,
		Parent = stage,
	})
	for index = -5, 5 do
		Build.Part({
			Name = "Crown",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2, 9, 9),
			CFrame = CFrame.new(index * 8.4, STAGE_TOP + 47, backZ - 1.6) * CFrame.Angles(0, math.rad(90), 0),
			Color = if index % 2 == 0 then rgb(255, 92, 150) else rgb(255, 204, 64),
			Parent = stage,
		})
	end
	for index, x in { -41.5, -14, 14, 41.5 } do
		Shapes.Capsule(21, 1.1, {
			Name = "NeonTube",
			CFrame = CFrame.new(x, STAGE_TOP + 13, backZ + 0.65) * CFrame.Angles(0, 0, math.rad(90)),
			Color = PALETTE.Portal[(index - 1) % 3 + 1],
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = stage,
		})
	end
	Shapes.RoundedBox(Vector3.new(94, 1.6, 3.4), 0.7, {
		Name = "BackdropTrim",
		CFrame = CFrame.new(0, STAGE_TOP + 46, backZ - 1),
		Color = PALETTE.Trim,
		Parent = stage,
	})
	for index = 0, 22 do
		Build.Decor({
			Name = "Marquee",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.5,
			CFrame = CFrame.new(-44 + index * 4, STAGE_TOP + 47.4, backZ + 0.6),
			Color = PARTY_COLORS[(index % #PARTY_COLORS) + 1],
			Material = Enum.Material.Neon,
			Parent = stage,
		})
	end
	-- Logo sign on top.
	sign(
		stage,
		"PARTY PANIC",
		Vector3.new(46, 9, 2.4),
		CFrame.new(0, STAGE_TOP + 52, backZ - 0.6),
		Enum.NormalId.Back,
		rgb(255, 84, 150),
		rgb(255, 255, 255)
	)

	-- Announcement screen (phase, timer, winner reveal) in a rounded bezel. Clients draw on Back.
	Shapes.RoundedBox(Vector3.new(46, 10, 1.2), 0.6, {
		Name = "AnnouncementBezel",
		CFrame = CFrame.new(0, STAGE_TOP + 39, backZ + 0.8),
		Color = PALETTE.Trim,
		Parent = stage,
	})
	local announcement = Build.Part({
		Name = "AnnouncementScreen",
		Size = Vector3.new(44, 8.4, 0.4),
		CFrame = CFrame.new(0, STAGE_TOP + 39, backZ + 1.5),
		Color = rgb(18, 14, 36),
		Parent = stage,
	})
	tag(announcement, "AnnouncementScreen")

	local pads = {}
	for index = 1, 3 do
		local x = (index - 2) * 28
		local color = PALETTE.Portal[index]
		-- Dark bay behind each portal so the glowing film pops.
		Shapes.RoundedBox(Vector3.new(21, 25, 2), 1.5, {
			Name = "PortalBay",
			CFrame = CFrame.new(x, STAGE_TOP + 12.5, backZ + 0.6),
			Color = PALETTE.Bay,
			Parent = stage,
		})
		Shapes.Arch(22, 25, 3.4, 4.4, CFrame.new(x, STAGE_TOP, backZ + 3), {
			Name = "PortalArch",
			Color = color,
			Parent = stage,
		})
		Shapes.Arch(23.2, 25.6, 1, 3.6, CFrame.new(x, STAGE_TOP, backZ + 3), {
			Name = "PortalArchTrim",
			Color = rgb(255, 255, 255),
			Parent = stage,
		})
		local film = Shapes.ArchPanel(14.6, 21.4, 0.3, CFrame.new(x, STAGE_TOP, backZ + 3), {
			Name = "PortalFilm",
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.45,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = stage,
		})
		film:SetAttribute("VoteIndex", index)
		tag(film, "PortalFilm")
		sparkleEmitter(film, color, 8)
		local light = Instance.new("SpotLight")
		light.Color = color
		light.Brightness = 3
		light.Range = 26
		light.Angle = 80
		light.Face = Enum.NormalId.Back
		light.Shadows = false
		light.Parent = film

		-- Game card screen above the portal (rendered by clients on the Back face).
		Shapes.RoundedBox(Vector3.new(22, 10.6, 1.2), 0.7, {
			Name = "ScreenBezel",
			CFrame = CFrame.new(x, STAGE_TOP + 31.5, backZ + 0.8),
			Color = color,
			Parent = stage,
		})
		local screen = Build.Part({
			Name = "VoteScreen" .. index,
			Size = Vector3.new(20.4, 9, 0.4),
			CFrame = CFrame.new(x, STAGE_TOP + 31.5, backZ + 1.5),
			Color = rgb(18, 14, 36),
			Parent = stage,
		})
		screen:SetAttribute("VoteIndex", index)
		tag(screen, "VoteScreen")

		-- Step-on vote pad in front of the portal.
		local pad = Shapes.Slab(Vector3.new(17, 0.4, 11), 3, {
			Name = "VotePad" .. index,
			CFrame = CFrame.new(x, STAGE_TOP + 0.2, STAGE_Z + 2),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CanTouch = true,
			Parent = stage,
		})
		pad:SetAttribute("VoteIndex", index)
		tag(pad, "VotePad")
		Build.SurfaceText(
			pad,
			Enum.NormalId.Top,
			`VOTE {index}`,
			{ PixelsPerStud = 12, Font = SIGN_FONT, TextStrokeTransparency = 0.2 }
		)
		table.insert(pads, pad)
	end

	-- Speaker stacks and light towers on both sides.
	for _, side in { -1, 1 } do
		local x = side * 51
		for level = 0, 1 do
			local box = Shapes.RoundedBox(Vector3.new(9, 8, 8), 1, {
				Name = "Speaker",
				CFrame = facing(Vector3.new(x, 4 + level * 8.2, STAGE_Z - 4), Vector3.new(x * 0.3, 0, 30)),
				Color = rgb(40, 34, 60),
				Parent = stage,
			})
			for _, offset in { Vector3.new(0, 1.4, 0), Vector3.new(0, -2.2, 0) } do
				local size = if offset.Y > 0 then 5.4 else 2.6
				Build.Part({
					Name = "Woofer",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.6, size, size),
					CFrame = box.CFrame
						* CFrame.new(offset + Vector3.new(0, 0, -4))
						* CFrame.Angles(0, math.rad(90), 0),
					Color = rgb(20, 18, 30),
					Parent = stage,
				})
				Build.Decor({
					Name = "WooferRing",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.5, size + 0.8, size + 0.8),
					CFrame = box.CFrame
						* CFrame.new(offset + Vector3.new(0, 0, -3.95))
						* CFrame.Angles(0, math.rad(90), 0),
					Color = PALETTE.Portal[if side < 0 then 1 else 3],
					Material = Enum.Material.Neon,
					Parent = stage,
				})
			end
		end
		-- Light tower: a slim pillar with a lamp head pointed at the stage.
		Shapes.Capsule(34, 1.4, {
			Name = "LightTower",
			CFrame = CFrame.new(side * 45, 17, STAGE_Z + 12) * CFrame.Angles(0, 0, math.rad(90)),
			Color = rgb(235, 235, 245),
			Parent = stage,
		})
		local lamp = Build.Decor({
			Name = "StageLamp",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.4,
			CFrame = CFrame.lookAt(Vector3.new(side * 45, 34, STAGE_Z + 12), Vector3.new(side * 12, 4, STAGE_Z)),
			Color = rgb(255, 245, 200),
			Material = Enum.Material.Neon,
			Parent = stage,
		})
		local spot = Instance.new("SpotLight")
		spot.Color = rgb(255, 240, 210)
		spot.Brightness = 2
		spot.Range = 60
		spot.Angle = 50
		spot.Shadows = false
		spot.Parent = lamp
		balloonCluster(stage, Vector3.new(side * 40, STAGE_TOP, STAGE_Z + 10), if side < 0 then 0 else 3)
	end
	return pads
end

-- Winner podium (east) ---------------------------------------------------------------------------

local function buildPodium(root: Model)
	local podium = Build.Model("WinnerPodium", root)
	local base = PODIUM
	Shapes.Slab(Vector3.new(24, 0.8, 36), 6, {
		Name = "PodiumBase",
		CFrame = CFrame.new(base + Vector3.new(2, 0.4, 0)),
		Color = PALETTE.StageDark,
		Parent = podium,
	})
	Shapes.Slab(Vector3.new(24.6, 0.3, 36.6), 6.2, {
		Name = "PodiumBaseTrim", -- top sits under the base top, so only the gold lip shows
		CFrame = CFrame.new(base + Vector3.new(2, 0.5, 0)),
		Color = PALETTE.Trim,
		Parent = podium,
	})
	local steps = {
		{ place = 1, height = 6.5, z = 0, color = rgb(255, 205, 60) },
		{ place = 2, height = 4.6, z = -9.5, color = rgb(215, 222, 240) },
		{ place = 3, height = 3, z = 9.5, color = rgb(240, 160, 100) },
	}
	for _, step in steps do
		local block = Shapes.RoundedBox(Vector3.new(9, step.height, 9), 1, {
			Name = "Step" .. step.place,
			CFrame = CFrame.new(base + Vector3.new(0, step.height / 2 + 0.8, step.z)),
			Color = step.color,
			Parent = podium,
		})
		Build.SurfaceText(
			block,
			Enum.NormalId.Left,
			tostring(step.place),
			{ PixelsPerStud = 14, Font = SIGN_FONT, TextColor3 = rgb(70, 45, 110), TextStrokeTransparency = 1 }
		)
		local spot = Build.Decor({
			Name = "PodiumSpot" .. step.place,
			Size = Vector3.one,
			Transparency = 1,
			CFrame = CFrame.new(base + Vector3.new(0, step.height + 7.4, step.z)),
			Parent = podium,
		})
		spot:SetAttribute("Place", step.place)
		tag(spot, "PodiumSpot")
	end
	-- Champion board behind the podium; clients draw on its Left face (toward the plaza).
	Shapes.RoundedBox(Vector3.new(2.6, 18.5, 34), 1, {
		Name = "ChampionBezel",
		CFrame = CFrame.new(base + Vector3.new(9.6, 10, 0)),
		Color = PALETTE.Trim,
		Parent = podium,
	})
	local board = Build.Part({
		Name = "ChampionBoard",
		Size = Vector3.new(1, 16.5, 32),
		CFrame = CFrame.new(base + Vector3.new(8.6, 10, 0)),
		Color = PALETTE.StageDark,
		Parent = podium,
	})
	tag(board, "ChampionBoard")
	sign(
		podium,
		"CHAMPIONS",
		Vector3.new(2.4, 6, 26),
		CFrame.new(base + Vector3.new(9.6, 22.5, 0)),
		Enum.NormalId.Left,
		rgb(255, 84, 150),
		rgb(255, 255, 255)
	)
	for _, z in { -17, 17 } do
		local trophy = MeshLibrary.Get(
			"Trophy",
			{ Scale = 0.75, CFrame = CFrame.new(base + Vector3.new(-6, 0.8, z)), Parent = podium }
		)
		tag(trophy, "PP_Spin")
	end
	balloonCluster(podium, base + Vector3.new(6, 0.8, -19), 1)
	balloonCluster(podium, base + Vector3.new(6, 0.8, 19), 4)
end

-- Shop and cosmetics gallery (west) ---------------------------------------------------------------

-- A toy-like mannequin (rounded blocks in avatar proportions) to show off cosmetics.
local function mannequin(parent: Instance, ground: CFrame, color: Color3, pose: number): Model
	local model = Build.Model("Mannequin", parent)
	local parts = {
		{ "Head", Vector3.new(2.2, 2.2, 2.2), Vector3.new(0, 7.1, 0), 0.9 },
		{ "Torso", Vector3.new(3.4, 3.2, 1.8), Vector3.new(0, 4.6, 0), 0.5 },
		{ "LeftLeg", Vector3.new(1.5, 3, 1.6), Vector3.new(-0.85, 1.5, 0), 0.5 },
		{ "RightLeg", Vector3.new(1.5, 3, 1.6), Vector3.new(0.85, 1.5, 0), 0.5 },
	}
	for _, spec in parts do
		Shapes.RoundedBox(spec[2], spec[4], {
			Name = spec[1],
			CFrame = ground * CFrame.new(spec[3]),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end
	-- Arms: one up in a cheer, one down (pose flips the sides).
	for _, side in { -1, 1 } do
		local up = side == pose
		local shoulder = ground * CFrame.new(side * 2.4, 5.8, 0)
		local arm = if up
			then shoulder * CFrame.Angles(0, 0, math.rad(side * 150)) * CFrame.new(0, -1.5, 0)
			else shoulder * CFrame.Angles(0, 0, math.rad(side * 12)) * CFrame.new(0, -1.5, 0)
		Shapes.RoundedBox(Vector3.new(1.4, 3.2, 1.5), 0.5, {
			Name = "Arm",
			CFrame = arm,
			Color = color,
			Parent = model,
		})
	end
	return model
end

local function buildShop(root: Model)
	local shop = Build.Model("ShopBooth", root)
	local base = SHOP
	local pink, white = rgb(255, 120, 175), rgb(255, 255, 255)
	Shapes.Slab(Vector3.new(20, 0.5, 32), 5, {
		Name = "ShopFloor",
		CFrame = CFrame.new(base + Vector3.new(-3, 0.25, 0)),
		Color = rgb(255, 228, 240),
		Parent = shop,
	})
	Shapes.RoundedBox(Vector3.new(2.5, 17, 30), 1, {
		Name = "BackWall",
		CFrame = CFrame.new(base + Vector3.new(-12, 8.5, 0)),
		Color = pink,
		Parent = shop,
	})
	for _, z in { -14.5, 14.5 } do
		Shapes.RoundedBox(Vector3.new(11, 17, 2), 0.9, {
			Name = "SideWall",
			CFrame = CFrame.new(base + Vector3.new(-7, 8.5, z)),
			Color = white,
			Parent = shop,
		})
	end
	-- Striped awning: alternating rounded strips, tilted toward the plaza.
	for index = 0, 9 do
		Shapes.RoundedBox(Vector3.new(14, 0.9, 3.1), 0.4, {
			Name = "Awning",
			CFrame = CFrame.new(base + Vector3.new(-5, 17.4, -13.5 + index * 3)) * CFrame.Angles(0, 0, math.rad(-12)),
			Color = if index % 2 == 0 then pink else white,
			Parent = shop,
		})
		Shapes.Capsule(3.1, 1.7, {
			Name = "Scallop",
			CFrame = CFrame.new(base + Vector3.new(1.7, 15.8, -13.5 + index * 3)) * CFrame.Angles(0, math.rad(90), 0),
			Color = if index % 2 == 0 then pink else white,
			CanCollide = false,
			CastShadow = false,
			Parent = shop,
		})
	end
	sign(
		shop,
		"SHOP",
		Vector3.new(2, 6.5, 18),
		CFrame.new(base + Vector3.new(-9, 22, 0)),
		Enum.NormalId.Right,
		rgb(70, 36, 110)
	)
	local counter = Shapes.RoundedBox(Vector3.new(4.5, 3.8, 16), 0.7, {
		Name = "Counter",
		CFrame = CFrame.new(base + Vector3.new(-2, 1.9, 0)),
		Color = rgb(255, 205, 228),
		Parent = shop,
	})
	Shapes.RoundedBox(Vector3.new(5.2, 0.6, 16.8), 0.25, {
		Name = "CounterTop",
		CFrame = CFrame.new(base + Vector3.new(-2, 4, 0)),
		Color = white,
		Parent = shop,
	})
	prompt(counter, "Open Shop", "Cosmetics", "OpenShop")
	-- Goodies on the counter.
	MeshLibrary.Get("GiftBox", { Scale = 0.6, CFrame = CFrame.new(base + Vector3.new(-2, 4.3, -5)), Parent = shop })
	MeshLibrary.Get("Treasure", { Scale = 0.7, CFrame = CFrame.new(base + Vector3.new(-2, 4.3, 5)), Parent = shop })

	-- Cosmetics gallery: mannequins on turning display stands, each with a glowing effect.
	local gallery = Build.Model("Gallery", shop)
	for index, offset in { Vector3.new(10, 0, -18), Vector3.new(14, 0, 0), Vector3.new(10, 0, 18) } do
		local color = PARTY_COLORS[index * 2 - 1]
		local position = base + offset
		disc("Stand", 7, 1.4, position + Vector3.new(0, 0.7, 0), { Color = white, Parent = gallery })
		disc(
			"StandRing",
			7.6,
			0.4,
			position + Vector3.new(0, 1.3, 0),
			flat({
				Color = color,
				Material = Enum.Material.Neon,
				Parent = gallery,
			})
		)
		local figure = mannequin(
			gallery,
			facing(position + Vector3.new(0, 1.4, 0), Vector3.zero),
			color,
			if index == 2 then 1 else -1
		)
		tag(figure, "PP_Spin")
		local glow = Build.Decor({
			Name = "Aura",
			Size = Vector3.one,
			Transparency = 1,
			CFrame = CFrame.new(position + Vector3.new(0, 4, 0)),
			Parent = gallery,
		})
		sparkleEmitter(glow, color, 5)
	end
	balloonCluster(shop, base + Vector3.new(4, 0.5, -17), 2)
end

-- Quest and reward corner (south-west) -----------------------------------------------------------

local function buildQuestCorner(root: Model): ProximityPrompt
	local corner = Build.Model("QuestCorner", root)
	local base = QUESTS
	local toCenter = (Vector3.zero - base).Unit
	local side = Vector3.new(-toCenter.Z, 0, toCenter.X)
	Shapes.Slab(Vector3.new(30, 0.4, 22), 7, {
		Name = "CornerFloor",
		CFrame = facing(base + Vector3.new(0, 0.2, 0), Vector3.zero),
		Color = rgb(238, 228, 255),
		Parent = corner,
	})

	-- Quest board under a little roof; clients draw the quests on its Front face.
	local boardPosition = base - toCenter * 6 + side * 6 + Vector3.new(0, 8, 0)
	local boardCFrame = facing(boardPosition, Vector3.zero)
	Shapes.RoundedBox(Vector3.new(18, 13, 1.4), 0.7, {
		Name = "QuestBezel",
		CFrame = boardCFrame * CFrame.new(0, 0, 0.6),
		Color = PALETTE.Wood,
		Parent = corner,
	})
	local board = Build.Part({
		Name = "QuestBoard",
		Size = Vector3.new(16, 11, 0.6),
		CFrame = boardCFrame,
		Color = rgb(60, 40, 100),
		Parent = corner,
	})
	tag(board, "QuestBoard")
	prompt(board, "View Quests", "Quest Board", "OpenQuests")
	for _, x in { -8, 8 } do
		Shapes.RoundedBox(Vector3.new(1.4, 16, 1.4), 0.5, {
			Name = "Post",
			CFrame = boardCFrame * CFrame.new(x, -0.5, 0.8),
			Color = PALETTE.Wood,
			Parent = corner,
		})
	end
	Shapes.RoundedBox(Vector3.new(21, 1, 4.5), 0.45, {
		Name = "Roof",
		CFrame = boardCFrame * CFrame.new(0, 7.8, 0) * CFrame.Angles(math.rad(-14), 0, 0),
		Color = rgb(170, 110, 240),
		Parent = corner,
	})
	sign(
		corner,
		"QUESTS",
		Vector3.new(12, 3.6, 1),
		boardCFrame * CFrame.new(0, 9.6, -0.6),
		Enum.NormalId.Front,
		rgb(255, 84, 150),
		rgb(255, 255, 255)
	)

	-- Daily gift machine: a giant gumball machine full of prizes.
	local machine = base - toCenter * 2 - side * 9
	local machineBase = Shapes.RoundedBox(Vector3.new(7, 5, 7), 1, {
		Name = "MachineBase",
		CFrame = facing(machine + Vector3.new(0, 2.5, 0), Vector3.zero),
		Color = rgb(255, 84, 120),
		Parent = corner,
	})
	Build.Decor({
		Name = "Chute",
		Size = Vector3.new(3, 1.6, 0.4),
		CFrame = machineBase.CFrame * CFrame.new(0, -0.6, -3.55),
		Color = rgb(255, 214, 92),
		Parent = corner,
	})
	disc("Neck", 5.4, 1, machine + Vector3.new(0, 5.5, 0), { Color = rgb(255, 214, 92), Parent = corner })
	Build.Part({
		Name = "Globe",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 8,
		CFrame = CFrame.new(machine + Vector3.new(0, 9.6, 0)),
		Color = rgb(220, 240, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.55,
		Parent = corner,
	})
	local rng = Random.new(3)
	for index = 1, 22 do
		local direction = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 0.2), rng:NextNumber(-1, 1))
		Build.Decor({
			Name = "Gumball",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.5,
			CFrame = CFrame.new(machine + Vector3.new(0, 9.2, 0) + direction.Unit * rng:NextNumber(0.5, 2.6)),
			Color = PARTY_COLORS[(index % #PARTY_COLORS) + 1],
			Parent = corner,
		})
	end
	disc("Cap", 3.4, 1.4, machine + Vector3.new(0, 14, 0), { Color = rgb(255, 84, 120), Parent = corner })
	Build.Part({
		Name = "Knob",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.6,
		CFrame = CFrame.new(machine + Vector3.new(0, 15, 0)),
		Color = rgb(255, 214, 92),
		Parent = corner,
	})
	local gift = MeshLibrary.Get("GiftBox", {
		CFrame = facing(machine + toCenter * 6 + Vector3.new(0, 0.4, 0), Vector3.zero),
		Parent = corner,
	})
	tag(gift, "PP_Bob")
	Build.Billboard(
		machineBase,
		"🎁 Daily Gift",
		{ StudsOffset = Vector3.new(0, 15, 0), Size = UDim2.fromOffset(220, 50), MaxDistance = 90 }
	)
	sparkleEmitter(machineBase, rgb(255, 220, 120), 5)
	balloonCluster(corner, base + toCenter * 8 + side * 11, 5)
	return prompt(machineBase, "Claim Daily Reward", "Daily Gift")
end

-- Arcade corner (south-east) ---------------------------------------------------------------------

local function buildArcade(root: Model): ({ BasePart }, TextLabel)
	local arcade = Build.Model("ArcadeCorner", root)
	local base = ARCADE
	local toCenter = (Vector3.zero - base).Unit
	local wallCFrame = facing(base - toCenter * 8 + Vector3.new(0, 8.5, 0), Vector3.zero)
	Shapes.Slab(Vector3.new(32, 0.4, 24), 7, {
		Name = "CornerFloor",
		CFrame = facing(base + Vector3.new(0, 0.2, 0), Vector3.zero),
		Color = rgb(225, 250, 232),
		Parent = arcade,
	})
	Shapes.RoundedBox(Vector3.new(32, 17, 2.5), 1, {
		Name = "TargetWall",
		CFrame = wallCFrame * CFrame.new(0, 0, 0.4),
		Color = rgb(45, 65, 130),
		Parent = arcade,
	})
	Shapes.RoundedBox(Vector3.new(33, 1.2, 3), 0.5, {
		Name = "WallTrim",
		CFrame = wallCFrame * CFrame.new(0, 8.6, 0.4),
		Color = rgb(110, 226, 140),
		Parent = arcade,
	})
	local targets = {}
	for row = 0, 1 do
		for column = 0, 2 do
			local offset = Vector3.new((column - 1) * 9.5, (row - 0.5) * 7, -1.3)
			local target = Build.Part({
				Name = "Target",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.6, 5, 5),
				CFrame = wallCFrame * CFrame.new(offset) * CFrame.Angles(0, math.rad(90), 0),
				Color = rgb(230, 230, 240),
				CanTouch = false,
				Parent = arcade,
			})
			local detector = Instance.new("ClickDetector")
			detector.MaxActivationDistance = 70
			detector.Parent = target
			table.insert(targets, target)
		end
	end
	Shapes.RoundedBox(Vector3.new(15.4, 9.4, 1.4), 0.6, {
		Name = "ScoreBezel",
		CFrame = wallCFrame * CFrame.new(0, 13.6, 0.7),
		Color = PALETTE.Trim,
		Parent = arcade,
	})
	local boardPart = Build.Part({
		Name = "TargetScores",
		Size = Vector3.new(14, 8, 0.6),
		CFrame = wallCFrame * CFrame.new(0, 13.6, 0),
		Color = rgb(25, 25, 50),
		Parent = arcade,
	})
	local label = Build.SurfaceText(
		boardPart,
		Enum.NormalId.Front,
		"🎯 TARGET RANGE\nClick lit targets!",
		{ PixelsPerStud = 20, Font = Enum.Font.GothamBold }
	)
	sign(
		arcade,
		"ARCADE",
		Vector3.new(14, 4, 1),
		wallCFrame * CFrame.new(0, 19.6, 0.2),
		Enum.NormalId.Front,
		rgb(45, 65, 130)
	)
	Shapes.Slab(
		Vector3.new(26, 0.12, 1.2),
		0.55,
		flat({
			Name = "FiringLine",
			CFrame = wallCFrame * CFrame.new(0, -8, -16),
			Color = rgb(255, 210, 70),
			Material = Enum.Material.Neon,
			Parent = arcade,
		})
	)
	-- Toys: cones and a few bouncy balls nearby.
	local side = Vector3.new(-toCenter.Z, 0, toCenter.X)
	for index = -1, 1, 2 do
		MeshLibrary.Get(
			"Cone",
			{ Scale = 1.2, CFrame = CFrame.new(base + side * index * 15 + toCenter * 4), Parent = arcade }
		)
	end
	balloonCluster(arcade, base + side * 15 - toCenter * 6, 0)
	return targets, label
end

-- Emote stage (south) ----------------------------------------------------------------------------

local function buildEmoteStage(root: Model): (ProximityPrompt, Vector3)
	local stage = Build.Model("EmoteStage", root)
	local center = EMOTE
	disc(
		"StageGlow",
		29,
		1,
		center + Vector3.new(0, 0.5, 0),
		{ Color = rgb(120, 230, 255), Material = Enum.Material.Neon, Parent = stage }
	)
	disc("Stage", 28, 1.6, center + Vector3.new(0, 0.8, 0), { Color = rgb(255, 125, 205), Parent = stage })
	-- Dance floor: a grid of colored tiles inside the circle.
	for gx = -2, 2 do
		for gz = -2, 2 do
			local offset = Vector3.new(gx * 4.2, 0, gz * 4.2)
			if offset.Magnitude > 11 then
				continue
			end
			Shapes.Slab(
				Vector3.new(3.9, 0.1, 3.9),
				0.6,
				flat({
					Name = "DanceTile",
					CFrame = CFrame.new(center + offset + Vector3.new(0, 1.7, 0)),
					Color = PARTY_COLORS[((gx + gz) % #PARTY_COLORS) + 1],
					Material = if (gx + gz) % 2 == 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic,
					Transparency = if (gx + gz) % 2 == 0 then 0.25 else 0,
					Parent = stage,
				})
			)
		end
	end
	-- Truss arch over the back of the stage with the sign and disco lights.
	for _, x in { -14, 14 } do
		Shapes.RoundedBox(Vector3.new(2, 18, 2), 0.6, {
			Name = "TrussPost",
			CFrame = CFrame.new(center + Vector3.new(x, 9, 8)),
			Color = rgb(70, 50, 120),
			Parent = stage,
		})
	end
	Shapes.RoundedBox(Vector3.new(30, 2, 2), 0.6, {
		Name = "TrussBeam",
		CFrame = CFrame.new(center + Vector3.new(0, 18, 8)),
		Color = rgb(70, 50, 120),
		Parent = stage,
	})
	local stageSign = sign(
		stage,
		"EMOTE STAGE",
		Vector3.new(22, 4.4, 1),
		CFrame.new(center + Vector3.new(0, 21.4, 8)),
		Enum.NormalId.Front,
		rgb(255, 84, 150),
		rgb(255, 255, 255)
	)
	Build.SurfaceText(stageSign, Enum.NormalId.Back, "EMOTE STAGE", {
		PixelsPerStud = 16,
		Font = SIGN_FONT,
		TextColor3 = rgb(255, 255, 255),
		TextStrokeTransparency = 0.35,
	})
	for index, x in { -9, 0, 9 } do
		local lamp = Build.Decor({
			Name = "Spot",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.8,
			CFrame = CFrame.lookAt(center + Vector3.new(x, 16.6, 8), center + Vector3.new(x * 0.3, 0, -2)),
			Color = PARTY_COLORS[index * 2],
			Material = Enum.Material.Neon,
			Parent = stage,
		})
		local light = Instance.new("SpotLight")
		light.Color = PARTY_COLORS[index * 2]
		light.Brightness = 4
		light.Range = 26
		light.Angle = 45
		light.Shadows = false
		light.Parent = lamp
	end
	-- Confetti cannon beside the stage.
	local cannonBase = Shapes.RoundedBox(Vector3.new(4.5, 2.2, 4.5), 0.6, {
		Name = "CannonBase",
		CFrame = CFrame.new(center + Vector3.new(19, 1.1, -4)),
		Color = rgb(80, 80, 100),
		Parent = stage,
	})
	Shapes.Capsule(6, 2.6, {
		Name = "CannonBarrel",
		CFrame = CFrame.new(center + Vector3.new(19, 3.8, -4)) * CFrame.Angles(0, 0, math.rad(60)),
		Color = rgb(255, 90, 140),
		Parent = stage,
	})
	balloonCluster(stage, center + Vector3.new(-18, 0, -3), 2)
	return prompt(cannonBase, "Fire Confetti!", "Confetti Cannon"), center + Vector3.new(0, 10, 0)
end

-- Secret space: spiral parkour tower to a view deck (north-west) ---------------------------------

local function buildParkour(root: Model): Vector3
	local course = Build.Model("ParkourRoute", root)
	local center = PARKOUR
	local radius = 11
	local startAngle = math.atan2(-center.Z, -center.X) -- the side facing the plaza

	local function around(angle: number, height: number): Vector3
		return center + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
	end

	local startPad = Shapes.Slab(Vector3.new(7, 0.6, 7), 2.5, {
		Name = "ParkourStart",
		CFrame = CFrame.new(around(startAngle, 0.3)),
		Color = rgb(120, 230, 120),
		Material = Enum.Material.Neon,
		CanTouch = true,
		Parent = course,
	})
	tag(startPad, "ParkourStart")
	Build.Billboard(
		startPad,
		"🧗 Parkour - climb to the view deck!",
		{ StudsOffset = Vector3.new(0, 5, 0), Size = UDim2.fromOffset(280, 44), MaxDistance = 70 }
	)

	local steps = 13
	for index = 1, steps do
		local angle = startAngle + math.rad(32 * index)
		local position = around(angle, 2.3 * index)
		Shapes.RoundedBox(Vector3.new(5.5, 1.2, 5.5), 0.5, {
			Name = "Step" .. index,
			CFrame = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)),
			Color = Color3.fromHSV(index / (steps + 2), 0.55, 1),
			Parent = course,
		})
	end

	local deckHeight = 2.3 * steps + 2.6
	disc(
		"Pillar",
		9,
		deckHeight - 0.5,
		center + Vector3.new(0, (deckHeight - 0.5) / 2, 0),
		{ Color = rgb(155, 125, 235), Parent = course }
	)
	for level = 1, 3 do
		disc(
			"PillarBand",
			9.6,
			0.8,
			center + Vector3.new(0, level * deckHeight / 4, 0),
			{ Color = PALETTE.Trim, Parent = course }
		)
	end
	local deckCenter = center + Vector3.new(0, deckHeight, 0)
	disc("ViewDeck", 18, 1.2, deckCenter, { Color = rgb(255, 222, 95), Parent = course })
	local finish = disc("ParkourFinish", 6, 0.3, deckCenter + Vector3.new(0, 0.7, 0), {
		Color = rgb(255, 120, 60),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = true,
		Parent = course,
	})
	tag(finish, "ParkourFinish")
	-- Railing posts all round except where the last step arrives.
	local arrival = startAngle + math.rad(32 * steps)
	for index = 0, 15 do
		local angle = index / 16 * math.pi * 2
		local delta = math.abs(((angle - arrival + math.pi) % (math.pi * 2)) - math.pi)
		if delta < 0.5 then
			continue
		end
		local position = deckCenter + Vector3.new(math.cos(angle) * 8.5, 2, math.sin(angle) * 8.5)
		Shapes.Capsule(3.4, 0.7, {
			Name = "Rail",
			CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
			Color = rgb(255, 255, 255),
			Parent = course,
		})
	end
	Shapes.Capsule(12, 0.5, {
		Name = "FlagPole",
		CFrame = CFrame.new(deckCenter + Vector3.new(0, 6.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = rgb(240, 240, 240),
		CanCollide = false,
		Parent = course,
	})
	Build.Decor({
		Name = "Flag",
		Size = Vector3.new(0.2, 3.4, 5.6),
		CFrame = CFrame.new(deckCenter + Vector3.new(0, 10.6, 2.8)),
		Color = rgb(255, 84, 150),
		Parent = course,
	})
	return deckCenter + Vector3.new(3, 2.5, 3)
end

local function buildBouncePads(root: Model)
	for index, degrees in { 45, 135 } do
		local angle = math.rad(degrees)
		local position = Vector3.new(math.cos(angle) * 40, 0, math.sin(angle) * 40)
		disc("BounceRim", 10.4, 0.7, position + Vector3.new(0, 0.35, 0), { Color = rgb(255, 255, 255), Parent = root })
		local pad = disc("BouncePad" .. index, 9, 0.9, position + Vector3.new(0, 0.45, 0), {
			Color = rgb(120, 240, 255),
			Material = Enum.Material.Neon,
			CanTouch = true,
			Parent = root,
		})
		pad:SetAttribute("Power", 95)
		tag(pad, "BouncePad")
	end
end

-- Skyline: Ferris wheel, carnival turrets, hot-air balloons ------------------------------------------

-- Where the big landmarks stand (outside the plaza, so they never block a path). Trees keep clear.
local FERRIS = Vector3.new(64, -0.5, -99)
local TOWERS = {
	{ position = Vector3.new(-50, -0.4, -70), scale = 1.25, roof = rgb(120, 84, 230) },
	{ position = Vector3.new(50, -0.4, -70), scale = 1.25, roof = rgb(120, 84, 230) },
	{ position = Vector3.new(-27, -0.4, 82), scale = 1, roof = rgb(64, 180, 255) },
	{ position = Vector3.new(27, -0.4, 82), scale = 1, roof = rgb(64, 180, 255) },
}

local function clearOfLandmarks(position: Vector3): boolean
	local flatPosition = Vector3.new(position.X, 0, position.Z)
	if (flatPosition - Vector3.new(FERRIS.X, 0, FERRIS.Z)).Magnitude < 34 then
		return false
	end
	for _, tower in TOWERS do
		if (flatPosition - Vector3.new(tower.position.X, 0, tower.position.Z)).Magnitude < 10 then
			return false
		end
	end
	return true
end

local function buildFerrisWheel(parent: Instance)
	-- The stand faces the plaza; the wheel turns about its axle and the cabins hang level (clients
	-- animate it: AmbienceController, tag PP_Wheel).
	local ferris = Build.Model("FerrisWheel", parent)
	local standCFrame = facing(FERRIS, Vector3.zero)
	MeshLibrary.Get("LobbyFerrisStand", { CFrame = standCFrame, Parent = ferris })
	local hub = standCFrame * Vector3.new(0, 43, 0.625)
	local wheel = MeshLibrary.Get("LobbyFerrisWheel", { CFrame = standCFrame, Parent = ferris })
	local box = wheel:GetBoundingBox()
	wheel:PivotTo(wheel:GetPivot() + (hub - box.Position))
	local cabinColors = { rgb(64, 196, 255), rgb(255, 204, 64), rgb(120, 224, 96), rgb(156, 108, 255) }
	for index = 0, 11 do
		local angle = index / 12 * math.pi * 2
		local hang = hub + standCFrame:VectorToWorldSpace(Vector3.new(math.cos(angle), math.sin(angle), 0) * 32)
		local cabin = MeshLibrary.Get("LobbyFerrisCabin", {
			Scale = 0.85,
			Colors = { Body = cabinColors[index % #cabinColors + 1] },
			Parent = ferris,
		})
		local _, size = cabin:GetBoundingBox()
		cabin:PivotTo(standCFrame.Rotation + (hang - Vector3.new(0, size.Y, 0)))
		cabin:SetAttribute("Hang", Vector3.new(0, size.Y, 0)) -- from its pivot to where it hangs
	end
	ferris:SetAttribute("Hub", hub)
	ferris:SetAttribute("Axis", standCFrame.LookVector)
	tag(ferris, "PP_Wheel")
	local glow = Build.Decor({
		Name = "HubGlow",
		Size = Vector3.one,
		Transparency = 1,
		CFrame = CFrame.new(hub),
		Parent = ferris,
	})
	Build.Light(glow, rgb(255, 160, 210), 40, 1.5)
end

local function buildSkyline(root: Model)
	local skyline = Build.Model("Skyline", root)
	buildFerrisWheel(skyline)
	for _, tower in TOWERS do
		MeshLibrary.Get("LobbyTower", {
			Scale = tower.scale,
			Colors = { Roof = tower.roof },
			CFrame = facing(tower.position, Vector3.zero),
			Parent = skyline,
		})
	end
	-- Hot-air balloons drifting over the park (clients bob them slowly: tag PP_Float).
	local balloons = {
		{ Vector3.new(-78, 58, -112), rgb(255, 92, 150), rgb(255, 236, 120), 1.1 },
		{ Vector3.new(128, 70, 6), rgb(64, 196, 255), rgb(255, 255, 255), 1.2 },
		{ Vector3.new(-126, 64, 46), rgb(156, 108, 255), rgb(255, 204, 64), 1 },
		{ Vector3.new(42, 88, 132), rgb(255, 140, 70), rgb(255, 255, 255), 1.3 },
		{ Vector3.new(-12, 96, -170), rgb(120, 224, 96), rgb(255, 92, 150), 1.4 },
	}
	for _, spec in balloons do
		local balloon = MeshLibrary.Get("LobbyHotAirBalloon", {
			Scale = spec[4],
			Colors = { Envelope = spec[2], Stripes = spec[3] },
			CFrame = CFrame.new(spec[1]) * CFrame.Angles(0, math.rad(spec[1].X), 0),
			Parent = skyline,
		})
		tag(balloon, "PP_Float")
	end
end

-- Gardens: flower beds and tree clusters on the lawn between the walkways ---------------------------

local function buildGardens(root: Model)
	local gardens = Build.Model("Gardens", root)
	local rng = Random.new(9)
	local flowerSets = {
		{ FlowerA = rgb(255, 92, 150), FlowerB = rgb(255, 255, 255), FlowerC = rgb(255, 170, 60) },
		{ FlowerA = rgb(170, 120, 255), FlowerB = rgb(255, 120, 190), FlowerC = rgb(255, 236, 120) },
		{ FlowerA = rgb(255, 84, 84), FlowerB = rgb(255, 214, 92), FlowerC = rgb(120, 200, 255) },
	}
	-- { angle in degrees, radius }: the lawn wedges between the zones.
	local spots = { { 22, 58 }, { 158, 58 }, { 70, 62 }, { 110, 62 }, { -32, 56 }, { 212, 56 } }
	for index, spot in spots do
		local angle = math.rad(spot[1])
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = radial * spot[2]
		-- The bed's long axis runs along the circle, so it lines the lawn instead of blocking it.
		MeshLibrary.Get("LobbyFlowerBed", {
			Colors = flowerSets[index % #flowerSets + 1],
			Scale = 1.3,
			CFrame = CFrame.lookAt(position, position + radial),
			Parent = gardens,
		})
		-- A clump of trees and bushes behind it, for height and shade.
		local side = Vector3.new(-radial.Z, 0, radial.X)
		local behind = radial * (spot[2] + 9)
		for _, offset in { side * -4.5, side * 4.5 + radial * 2.5 } do
			MeshLibrary.Get("Tree", {
				Scale = rng:NextNumber(1.05, 1.35),
				CFrame = CFrame.new(behind + offset) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = gardens,
			})
		end
		for _, offset in { side * -9, side * 0.5 - radial * 1.5, side * 9 } do
			MeshLibrary.Get("Bush", {
				Scale = rng:NextNumber(0.9, 1.2),
				CFrame = CFrame.new(behind + offset) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = gardens,
			})
		end
	end
end

-- Scenery: hedges, lamps with bunting, trees, floating confetti ---------------------------------------

local function buildScenery(root: Model)
	local scenery = Build.Model("Scenery", root)
	local rng = Random.new(42)

	-- Lamp posts around the plaza edge, strung together with pennant bunting.
	local lampPositions = {}
	local lampCount = 16
	for index = 0, lampCount - 1 do
		local angle = (index + 0.5) / lampCount * math.pi * 2
		local position = Vector3.new(math.cos(angle) * (PLAZA_RADIUS - 3), 0, math.sin(angle) * (PLAZA_RADIUS - 3))
		-- Leave the stage back and the zone buildings free of lamps.
		if position.Z < STAGE_Z + 6 and math.abs(position.X) < 50 then
			continue
		end
		MeshLibrary.Get("LampPost", { CFrame = facing(position, Vector3.zero), Parent = scenery })
		table.insert(lampPositions, position)
	end
	for index = 1, #lampPositions - 1 do
		local a, b = lampPositions[index], lampPositions[index + 1]
		local span = (a - b).Magnitude
		if span < 40 then
			local middle = (a + b) / 2
			local scale = span / BUNTING_LENGTH
			local bunting = MeshLibrary.Get("LobbyBunting", {
				Scale = scale,
				Parent = scenery,
			})
			local _, size = bunting:GetBoundingBox()
			local direction = (b - a).Unit
			-- The bunting runs along its X axis; its ends are the top of its bounding box.
			bunting:PivotTo(CFrame.fromMatrix(middle + Vector3.new(0, 10.4 - size.Y, 0), direction, Vector3.yAxis))
		end
	end
	-- Light strings from the stage's light towers out over the plaza.
	for _, side in { -1, 1 } do
		lightString(scenery, Vector3.new(side * 45, 32, STAGE_Z + 12), Vector3.new(side * 8, 14, -6), 4, 2)
		lightString(scenery, Vector3.new(side * 45, 32, STAGE_Z + 12), Vector3.new(side * 40, 10.4, 16), 4, 4)
	end

	-- Hedges along the edge.
	for index = 0, 59 do
		local angle = index / 60 * math.pi * 2
		local position =
			Vector3.new(math.cos(angle) * (PLAZA_RADIUS + 3.5), -0.2, math.sin(angle) * (PLAZA_RADIUS + 3.5))
		if not clearOfLandmarks(position) then
			continue
		end
		MeshLibrary.Get("Bush", {
			Scale = rng:NextNumber(1.1, 1.5),
			CFrame = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = scenery,
		})
	end

	-- Two rings of trees just outside, so the horizon is green and full.
	for ring, radius in { PLAZA_RADIUS + 14, PLAZA_RADIUS + 30 } do
		local count = if ring == 1 then 30 else 36
		for index = 0, count - 1 do
			local angle = (index + ring * 0.5) / count * math.pi * 2 + rng:NextNumber(-0.04, 0.04)
			local distance = radius + rng:NextNumber(-4, 4)
			local position = Vector3.new(math.cos(angle) * distance, -0.4, math.sin(angle) * distance)
			local scale = rng:NextNumber(1.2, 1.8) + (ring - 1) * 0.3
			local yaw = rng:NextNumber(0, math.pi * 2)
			if not clearOfLandmarks(position) then
				continue
			end
			MeshLibrary.Get("Tree", {
				Scale = scale,
				CFrame = CFrame.new(position) * CFrame.Angles(0, yaw, 0),
				Parent = scenery,
			})
		end
	end

	-- Floating sparkles over the plaza.
	for _, point in Build.Ring(Vector3.new(0, 0, 0), 30, 3, 0.5) do
		local holder = Build.Decor({
			Name = "AmbientSparkles",
			Size = Vector3.one,
			Transparency = 1,
			CFrame = CFrame.new(point.Position + Vector3.new(0, 14, 0)),
			Parent = scenery,
		})
		local emitter = sparkleEmitter(holder, rgb(255, 255, 255), 3)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Speed = NumberRange.new(0.5, 1.5)
		emitter.Lifetime = NumberRange.new(4, 6)
	end

	-- Confetti drifting down over the whole plaza, in party colors.
	local sky = Build.Decor({
		Name = "ConfettiSky",
		Size = Vector3.new(110, 1, 110),
		Transparency = 1,
		CFrame = CFrame.new(0, 42, 0),
		Parent = scenery,
	})
	local confetti = Instance.new("ParticleEmitter")
	confetti.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	confetti.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PARTY_COLORS[1]),
		ColorSequenceKeypoint.new(0.25, PARTY_COLORS[2]),
		ColorSequenceKeypoint.new(0.5, PARTY_COLORS[3]),
		ColorSequenceKeypoint.new(0.75, PARTY_COLORS[4]),
		ColorSequenceKeypoint.new(1, PARTY_COLORS[5]),
	})
	confetti.LightEmission = 0.4
	confetti.Size = NumberSequence.new(0.45)
	confetti.Squash = NumberSequence.new(0.6)
	confetti.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.1),
		NumberSequenceKeypoint.new(0.85, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	confetti.Lifetime = NumberRange.new(12, 16)
	confetti.Speed = NumberRange.new(2, 3.5)
	confetti.Acceleration = Vector3.new(0, -0.6, 0)
	confetti.Rotation = NumberRange.new(0, 360)
	confetti.RotSpeed = NumberRange.new(-160, 160)
	confetti.SpreadAngle = Vector2.new(25, 25)
	confetti.EmissionDirection = Enum.NormalId.Bottom
	confetti.Rate = 7
	confetti.Parent = sky
	tag(confetti, "PP_Ambient")
end

function LobbyBuilder.Build(): LobbyRefs
	setupLighting()
	local root = Build.Model("Lobby", workspace)
	-- Ground and spawns first so early joiners always land on something.
	buildGround(root)
	buildSpawns(root)
	Environment.Build(PLAZA_RADIUS)
	buildFountain(root)
	local pads = buildVoteStage(root)
	buildPodium(root)
	buildShop(root)
	local dailyPrompt = buildQuestCorner(root)
	local targets, targetBoard = buildArcade(root)
	local confettiPrompt, confettiPosition = buildEmoteStage(root)
	local deckSpot = buildParkour(root)
	buildBouncePads(root)
	buildGardens(root)
	buildSkyline(root)
	buildScenery(root)

	return {
		Root = root,
		VotePads = pads,
		DailyPrompt = dailyPrompt,
		ConfettiPrompt = confettiPrompt,
		ConfettiPosition = confettiPosition,
		-- Hidden daily token spots: one is picked per day (§5 "Secret collectible").
		TokenSpots = {
			deckSpot, -- on the parkour view deck
			Vector3.new(0, 2.5, STAGE_Z - 18), -- behind the vote stage
			SHOP + Vector3.new(-5, 20.5, 8), -- on the shop awning
			PODIUM + Vector3.new(9.6, 21, 14), -- on top of the champion board
			EMOTE + Vector3.new(0, 20.5, 8), -- on the emote stage truss
			QUESTS + Vector3.new(-14, 2, 14), -- behind the quest corner, by the hedge
			ARCADE + Vector3.new(14, 2, 14), -- behind the arcade wall
		},
		Targets = targets,
		TargetBoard = targetBoard,
		-- Beach balls rest on the promenade, clear of the benches, bounce pads and walkways.
		BallSpots = {
			Vector3.new(math.cos(math.rad(25)) * 37, 0.2, math.sin(math.rad(25)) * 37),
			Vector3.new(math.cos(math.rad(155)) * 37, 0.2, math.sin(math.rad(155)) * 37),
			Vector3.new(math.cos(math.rad(215)) * 37, 0.2, math.sin(math.rad(215)) * 37),
			Vector3.new(math.cos(math.rad(325)) * 37, 0.2, math.sin(math.rad(325)) * 37),
		},
	}
end

return LobbyBuilder

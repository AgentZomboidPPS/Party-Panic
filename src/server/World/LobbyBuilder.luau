-- Builds the lobby plaza (design doc §5 "Lobby and Social Hub").
--
--                         N (-Z)
--                  [ vote wall + 3 portals ]
--                                              [parkour tower]
--   W  [ shop ]        ( statue + spawns )        [ podium ]  E (+X)
--      [ quests/daily ]   [ emote stage ]   [ arcade range ]
--                         S (+Z)
--
-- Look: rounded CSG shapes (World/Shapes), mesh props (World/MeshLibrary) and terrain scenery
-- (World/Environment) instead of raw blocks. Screens showing live or per-player data (vote cards,
-- quest board, podium names) are tagged and rendered by each client. Decorations that move
-- (balloons, trophies) are tagged too and animated on clients, which costs the server nothing.

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
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local PALETTE = {
	Plaza = rgb(240, 234, 255),
	PlazaRing = rgb(255, 205, 232),
	Path = rgb(205, 225, 255),
	Stage = rgb(72, 52, 128),
	StageDark = rgb(46, 34, 92),
	Trim = rgb(255, 210, 70),
	Portal = { rgb(255, 95, 150), rgb(80, 200, 255), rgb(130, 230, 110) },
	Spawn = rgb(255, 240, 160),
}

local PARTY_COLORS = { rgb(255, 90, 140), rgb(90, 190, 255), rgb(255, 210, 70), rgb(150, 110, 255), rgb(110, 230, 140) }

local LAWN_Y = -0.3 -- terrain lawn surface; the plaza disc sits just above it

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
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.15
	atmosphere.Color = rgb(205, 215, 255)
	atmosphere.Decay = rgb(140, 120, 190)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting

	local correction = Instance.new("ColorCorrectionEffect")
	correction.Saturation = 0.18
	correction.Contrast = 0.06
	correction.TintColor = rgb(255, 250, 255)
	correction.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.45
	bloom.Size = 24
	bloom.Threshold = 1.2
	bloom.Parent = Lighting
end

local function disc(name: string, diameter: number, height: number, position: Vector3, props: { [string]: any }): Part
	props.Name = name
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	return Build.Part(props)
end

-- Rainbow streamer between two parts (a Beam: no parts, no physics).
local function streamer(from: BasePart, to: BasePart, offset: Vector3, colorIndex: number)
	local a0 = Instance.new("Attachment")
	a0.Position = offset
	a0.Parent = from
	local a1 = Instance.new("Attachment")
	a1.Position = offset
	a1.Parent = to
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.5
	beam.Width1 = 0.5
	beam.CurveSize0 = -6
	beam.CurveSize1 = 6
	beam.Segments = 16
	beam.FaceCamera = true
	beam.LightEmission = 0.3
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PARTY_COLORS[colorIndex]),
		ColorSequenceKeypoint.new(0.5, PARTY_COLORS[(colorIndex % #PARTY_COLORS) + 1]),
		ColorSequenceKeypoint.new(1, PARTY_COLORS[colorIndex]),
	})
	beam.Parent = from
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

local function buildGround(root: Model)
	disc("Plaza", 230, 4, Vector3.new(0, -2, 0), { Color = PALETTE.Plaza, Parent = root })
	disc("PlazaEdge", 232, 3.8, Vector3.new(0, -2.05, 0), { Color = PALETTE.Trim, Parent = root })
	-- Decorative ring and paths: thin, no collision, no shadows.
	local flat = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	disc("PlazaRing", 92, 0.1, Vector3.new(0, 0.03, 0), {
		Color = PALETTE.PlazaRing,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = root,
	})
	disc("PlazaInner", 80, 0.1, Vector3.new(0, 0.05, 0), {
		Color = PALETTE.Plaza,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = root,
	})
	for _, direction in { Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1) } do
		local size = if direction.X ~= 0 then Vector3.new(64, 0.12, 10) else Vector3.new(10, 0.12, 64)
		local path = Shapes.Slab(size, 4.9, {
			Name = "Path",
			CFrame = CFrame.new(direction * 72 + Vector3.new(0, 0.04, 0)),
			Color = PALETTE.Path,
			Parent = root,
		})
		for key, value in flat do
			(path :: any)[key] = value
		end
	end
	-- Invisible boundary so nobody walks off the world.
	for index, point in Build.Ring(Vector3.new(0, 20, 0), 192, 24) do
		Build.Barrier({ Name = "Boundary" .. index, Size = Vector3.new(52, 60, 2), CFrame = point, Parent = root })
	end
end

local function buildSpawns(root: Model)
	local spawns = Build.Model("Spawns", root)
	for index, point in Build.Ring(Vector3.new(0, 0, 0), 26, 8, math.pi / 8) do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn" .. index
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Size = Vector3.new(6, 0.2, 6)
		spawn.CFrame = point + Vector3.new(0, 0.1, 0)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Parent = spawns
		disc("SpawnPad", 7, 0.3, point.Position + Vector3.new(0, 0.12, 0), {
			Color = PALETTE.Spawn,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Parent = spawns,
		})
	end
end

local function buildCenter(root: Model)
	local center = Build.Model("CentralPlaza", root)
	disc("PedestalStep", 22, 1, Vector3.new(0, 0.5, 0), { Color = PALETTE.StageDark, Parent = center })
	disc("Pedestal", 18, 3, Vector3.new(0, 1.5, 0), { Color = PALETTE.Stage, Parent = center })
	disc(
		"PedestalTrim",
		18.8,
		0.6,
		Vector3.new(0, 2.85, 0),
		{ Color = PALETTE.Trim, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = center }
	)
	-- Landmark: a giant trophy (one mesh prop, scaled up) that slowly turns on clients.
	local trophy = MeshLibrary.Get("Trophy", { Scale = 2.4, CFrame = CFrame.new(0, 3, 0), Parent = center })
	tag(trophy, "PP_Spin")
	local glow = Build.Decor({
		Name = "TrophyGlow",
		Size = Vector3.one,
		Transparency = 1,
		CFrame = CFrame.new(0, 12, 0),
		Parent = center,
	})
	sparkleEmitter(glow, rgb(255, 230, 140), 6)
	Build.Light(glow, rgb(255, 220, 140), 24, 1.2)

	for index, point in Build.Ring(Vector3.new(0, 0, 0), 12.5, 4, math.pi / 4) do
		local balloon = MeshLibrary.Get("Balloon", {
			Colors = { Balloon = PARTY_COLORS[index] },
			CFrame = CFrame.new(point.Position + Vector3.new(0, 3, 0)),
			Parent = center,
		})
		tag(balloon, "PP_Bob")
	end

	-- Benches facing the statue (seating from §5); Build.Ring points face the center.
	for _, point in Build.Ring(Vector3.new(0, 0, 0), 46, 6, math.pi / 6) do
		MeshLibrary.Get("Bench", { CFrame = point, Parent = center })
	end
end

local function buildVoteStage(root: Model): { BasePart }
	local stage = Build.Model("VoteStage", root)
	local wallZ = -100
	Shapes.Slab(Vector3.new(126, 0.6, 38), 8, {
		Name = "StageEdge",
		CFrame = CFrame.new(0, 0.2, -84),
		Color = PALETTE.Trim,
		Material = Enum.Material.Neon,
		Parent = stage,
	})
	Shapes.Slab(
		Vector3.new(124, 0.7, 36),
		7,
		{ Name = "StageFloor", CFrame = CFrame.new(0, 0.3, -84), Color = PALETTE.Stage, Parent = stage }
	)
	Shapes.RoundedBox(
		Vector3.new(128, 48, 4),
		1.8,
		{ Name = "VoteWall", CFrame = CFrame.new(0, 24, wallZ), Color = PALETTE.StageDark, Parent = stage }
	)
	-- Marquee bulbs along the top edge.
	for index = 0, 15 do
		Build.Decor({
			Name = "Bulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.6,
			CFrame = CFrame.new(-60 + index * 8, 47.5, wallZ + 2.2),
			Color = PARTY_COLORS[(index % #PARTY_COLORS) + 1],
			Material = Enum.Material.Neon,
			Parent = stage,
		})
	end

	-- Announcement screen (phase, timer, winner reveal) in a rounded bezel.
	Shapes.RoundedBox(
		Vector3.new(58.5, 13.5, 1.2),
		0.6,
		{ Name = "AnnouncementBezel", CFrame = CFrame.new(0, 38.5, wallZ + 2.2), Color = PALETTE.Trim, Parent = stage }
	)
	local announcement = Build.Part({
		Name = "AnnouncementScreen",
		Size = Vector3.new(56, 11, 0.4),
		CFrame = CFrame.new(0, 38.5, wallZ + 2.9),
		Color = rgb(18, 14, 36),
		Parent = stage,
	})
	tag(announcement, "AnnouncementScreen")

	local pads = {}
	for index = 1, 3 do
		local x = (index - 2) * 38
		local color = PALETTE.Portal[index]
		-- Smooth portal arch with a glowing film.
		Shapes.Arch(21, 21, 2.8, 3.2, CFrame.new(x, 0.6, -94), { Name = "PortalArch", Color = color, Parent = stage })
		local film = Shapes.ArchPanel(15.6, 18.2, 0.3, CFrame.new(x, 0.6, -94), {
			Name = "PortalFilm",
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.6,
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
		light.Range = 30
		light.Angle = 70
		light.Face = Enum.NormalId.Back
		light.Shadows = false
		light.Parent = film

		-- Game card screen above the portal (rendered by clients).
		Shapes.RoundedBox(
			Vector3.new(26, 14.5, 1.2),
			0.8,
			{ Name = "ScreenBezel", CFrame = CFrame.new(x, 27, wallZ + 2.2), Color = color, Parent = stage }
		)
		local screen = Build.Part({
			Name = "VoteScreen" .. index,
			Size = Vector3.new(24, 12.5, 0.4),
			CFrame = CFrame.new(x, 27, wallZ + 2.9),
			Color = rgb(18, 14, 36),
			Parent = stage,
		})
		screen:SetAttribute("VoteIndex", index)
		tag(screen, "VoteScreen")

		-- Step-on vote pad.
		local pad = Shapes.Slab(Vector3.new(15, 0.5, 12), 3, {
			Name = "VotePad" .. index,
			CFrame = CFrame.new(x, 0.7, -82),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			CanTouch = true,
			Parent = stage,
		})
		pad:SetAttribute("VoteIndex", index)
		tag(pad, "VotePad")
		Build.SurfaceText(pad, Enum.NormalId.Top, `VOTE {index}`, { PixelsPerStud = 12, TextStrokeTransparency = 0.2 })
		table.insert(pads, pad)
	end
	return pads
end

local function buildPodium(root: Model)
	local podium = Build.Model("WinnerPodium", root)
	local baseX = 82
	local steps = {
		{ place = 1, height = 6, z = 0, color = rgb(255, 205, 60) },
		{ place = 2, height = 4.2, z = -9, color = rgb(205, 215, 235) },
		{ place = 3, height = 2.6, z = 9, color = rgb(235, 155, 95) },
	}
	Shapes.Slab(
		Vector3.new(16, 0.6, 32),
		4,
		{ Name = "PodiumBase", CFrame = CFrame.new(baseX, 0.3, 0), Color = PALETTE.StageDark, Parent = podium }
	)
	for _, step in steps do
		local block = Shapes.RoundedBox(Vector3.new(8, step.height, 8.5), 0.9, {
			Name = "Step" .. step.place,
			CFrame = CFrame.new(baseX, step.height / 2 + 0.6, step.z),
			Color = step.color,
			Parent = podium,
		})
		Build.SurfaceText(
			block,
			Enum.NormalId.Left,
			tostring(step.place),
			{ PixelsPerStud = 14, TextColor3 = rgb(60, 40, 90), TextStrokeTransparency = 1 }
		)
		local spot = Build.Decor({
			Name = "PodiumSpot" .. step.place,
			Size = Vector3.one,
			Transparency = 1,
			CFrame = CFrame.new(baseX, step.height + 6.6, step.z),
			Parent = podium,
		})
		spot:SetAttribute("Place", step.place)
		tag(spot, "PodiumSpot")
	end
	Shapes.RoundedBox(
		Vector3.new(2.6, 17.5, 33.5),
		0.9,
		{ Name = "ChampionBezel", CFrame = CFrame.new(baseX + 8.4, 8.75, 0), Color = PALETTE.Trim, Parent = podium }
	)
	local board = Build.Part({
		Name = "ChampionBoard",
		Size = Vector3.new(1, 16, 32),
		CFrame = CFrame.new(baseX + 7.4, 8.75, 0),
		Color = PALETTE.StageDark,
		Parent = podium,
	})
	tag(board, "ChampionBoard")
	local small = MeshLibrary.Get("Trophy", { CFrame = CFrame.new(baseX - 2, 0, -18), Parent = podium })
	tag(small, "PP_Spin")
	local smaller = MeshLibrary.Get("Trophy", { Scale = 0.8, CFrame = CFrame.new(baseX - 2, 0, 18), Parent = podium })
	tag(smaller, "PP_Spin")
end

local function buildShop(root: Model)
	local shop = Build.Model("ShopBooth", root)
	local x = -82
	Shapes.RoundedBox(
		Vector3.new(2.5, 17, 29),
		1,
		{ Name = "BackWall", CFrame = CFrame.new(x - 7, 8.5, 0), Color = rgb(255, 125, 175), Parent = shop }
	)
	local sign = Shapes.RoundedBox(
		Vector3.new(1.4, 5.5, 19),
		0.6,
		{ Name = "Sign", CFrame = CFrame.new(x - 5.4, 13.5, 0), Color = rgb(60, 30, 90), Parent = shop }
	)
	Build.SurfaceText(
		sign,
		Enum.NormalId.Right,
		"🛍️ SHOP",
		{ PixelsPerStud = 16, TextColor3 = rgb(255, 230, 120) }
	)
	Shapes.RoundedBox(Vector3.new(14, 1, 31), 0.45, {
		Name = "Awning",
		CFrame = CFrame.new(x - 1, 17.4, 0) * CFrame.Angles(0, 0, math.rad(-8)),
		Color = rgb(255, 240, 248),
		Parent = shop,
	})
	-- Scalloped awning edge: alternating capsules.
	for index = 0, 9 do
		Shapes.Capsule(3.4, 1.6, {
			Name = "Scallop",
			CFrame = CFrame.new(x + 5.8, 16.3, -13.5 + index * 3) * CFrame.Angles(0, math.rad(90), 0),
			Color = if index % 2 == 0 then rgb(255, 120, 170) else rgb(255, 255, 255),
			CanCollide = false,
			CastShadow = false,
			Parent = shop,
		})
	end
	local counter = Shapes.RoundedBox(
		Vector3.new(4.5, 3.8, 17),
		0.7,
		{ Name = "Counter", CFrame = CFrame.new(x, 1.9, 0), Color = rgb(255, 205, 228), Parent = shop }
	)
	prompt(counter, "Open Shop", "Cosmetics", "OpenShop")
	-- Display pedestals with glowing trail-color previews.
	for index, color in { rgb(255, 80, 80), rgb(90, 230, 110), rgb(80, 170, 255) } do
		local z = (index - 2) * 10
		disc("Pedestal", 4, 3, Vector3.new(x + 9, 1.5, z), { Color = rgb(250, 250, 255), Parent = shop })
		local orb = Build.Decor({
			Name = "Display",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.2,
			CFrame = CFrame.new(x + 9, 4.6, z),
			Color = color,
			Material = Enum.Material.Neon,
			Parent = shop,
		})
		sparkleEmitter(orb, color, 4)
	end
end

local function buildQuestCorner(root: Model): ProximityPrompt
	local corner = Build.Model("QuestCorner", root)
	local base = Vector3.new(-66, 0, 66)
	disc("Floor", 34, 0.3, base + Vector3.new(0, 0.15, 0), { Color = rgb(255, 242, 205), Parent = corner })
	local boardCFrame = CFrame.lookAt(base + Vector3.new(-8, 7.5, 8), Vector3.new(0, 7.5, 0))
	Shapes.RoundedBox(
		Vector3.new(17.6, 12.6, 1.4),
		0.7,
		{ Name = "QuestBezel", CFrame = boardCFrame * CFrame.new(0, 0, 0.6), Color = PALETTE.Trim, Parent = corner }
	)
	local board = Build.Part({
		Name = "QuestBoard",
		Size = Vector3.new(16, 11, 0.6),
		CFrame = boardCFrame,
		Color = rgb(60, 40, 100),
		Parent = corner,
	})
	tag(board, "QuestBoard")
	prompt(board, "View Quests", "Quest Board", "OpenQuests")
	for _, side in { -7, 7 } do
		Shapes.Capsule(8, 0.9, {
			Name = "BoardLeg",
			CFrame = boardCFrame * CFrame.new(side, -4.5, 0.6) * CFrame.Angles(0, 0, math.rad(90)),
			Color = PALETTE.StageDark,
			Parent = corner,
		})
	end

	local machineBase = Shapes.RoundedBox(Vector3.new(6.5, 2, 6.5), 0.6, {
		Name = "MachineBase",
		CFrame = CFrame.new(base + Vector3.new(6, 1, -6)),
		Color = rgb(95, 75, 170),
		Parent = corner,
	})
	local gift = MeshLibrary.Get("GiftBox", { CFrame = CFrame.new(base + Vector3.new(6, 2, -6)), Parent = corner })
	tag(gift, "PP_Bob")
	Build.Billboard(
		machineBase,
		"🎁 Daily Reward",
		{ StudsOffset = Vector3.new(0, 7.5, 0), Size = UDim2.fromOffset(220, 50), MaxDistance = 80 }
	)
	sparkleEmitter(machineBase, rgb(255, 220, 120), 5)
	return prompt(machineBase, "Claim Daily Reward", "Daily Gift")
end

local function buildArcade(root: Model): ({ BasePart }, TextLabel)
	local arcade = Build.Model("ArcadeCorner", root)
	local base = Vector3.new(68, 0, 70)
	local facing = CFrame.lookAt(base + Vector3.new(10, 8, 10), Vector3.new(0, 8, 0))
	Shapes.RoundedBox(
		Vector3.new(35, 17, 2.5),
		1,
		{ Name = "TargetWall", CFrame = facing * CFrame.new(0, 0.5, 0.4), Color = rgb(45, 65, 120), Parent = arcade }
	)
	local targets = {}
	for row = 0, 1 do
		for column = 0, 2 do
			local offset = Vector3.new((column - 1) * 10, (row - 0.5) * 7, -1.3)
			local target = Build.Part({
				Name = "Target",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.6, 5, 5),
				CFrame = facing * CFrame.new(offset) * CFrame.Angles(0, math.rad(90), 0),
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
	Shapes.RoundedBox(
		Vector3.new(15.4, 10.4, 1.4),
		0.6,
		{ Name = "ScoreBezel", CFrame = facing * CFrame.new(0, 13.5, 0.5), Color = PALETTE.Trim, Parent = arcade }
	)
	local boardPart = Build.Part({
		Name = "TargetScores",
		Size = Vector3.new(14, 9, 0.6),
		CFrame = facing * CFrame.new(0, 13.5, 0),
		Color = rgb(25, 25, 50),
		Parent = arcade,
	})
	local label = Build.SurfaceText(
		boardPart,
		Enum.NormalId.Front,
		"🎯 TARGET RANGE\nClick lit targets!",
		{ PixelsPerStud = 20, Font = Enum.Font.GothamBold }
	)
	Shapes.Slab(Vector3.new(30, 0.12, 1.2), 0.55, {
		Name = "FiringLine",
		CFrame = facing * CFrame.new(0, -7.95, -22),
		Color = rgb(255, 210, 70),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		Parent = arcade,
	})
	return targets, label
end

local function buildEmoteStage(root: Model): (ProximityPrompt, Vector3)
	local stage = Build.Model("EmoteStage", root)
	local center = Vector3.new(0, 0, 84)
	disc(
		"StageGlow",
		33,
		1.2,
		center + Vector3.new(0, 0.6, 0),
		{ Color = rgb(120, 230, 255), Material = Enum.Material.Neon, Parent = stage }
	)
	disc("Stage", 32, 1.5, center + Vector3.new(0, 0.75, 0), { Color = rgb(255, 125, 205), Parent = stage })
	disc(
		"StageTop",
		24,
		0.1,
		center + Vector3.new(0, 1.52, 0),
		{ Color = rgb(255, 170, 225), CanCollide = false, CanQuery = false, CastShadow = false, Parent = stage }
	)
	local sign = Shapes.RoundedBox(Vector3.new(21, 4.5, 0.8), 0.35, {
		Name = "StageSign",
		CFrame = CFrame.new(center + Vector3.new(0, 12, 17)),
		Color = rgb(60, 30, 90),
		CanCollide = false,
		Parent = stage,
	})
	Build.SurfaceText(
		sign,
		Enum.NormalId.Back,
		"💃 EMOTE STAGE",
		{ PixelsPerStud = 16, TextColor3 = rgb(255, 230, 120) }
	)
	Build.SurfaceText(
		sign,
		Enum.NormalId.Front,
		"💃 EMOTE STAGE",
		{ PixelsPerStud = 16, TextColor3 = rgb(255, 230, 120) }
	)
	for _, x in { -10, 10 } do
		Shapes.Capsule(12, 0.9, {
			Name = "SignPost",
			CFrame = CFrame.new(center + Vector3.new(x, 6, 17)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = rgb(60, 30, 90),
			CanCollide = false,
			Parent = stage,
		})
	end
	-- Disco spotlights aimed at the stage.
	for index, angle in { -0.9, 0, 0.9 } do
		local lamp = Build.Decor({
			Name = "Spot",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.6,
			CFrame = CFrame.lookAt(center + Vector3.new(math.sin(angle) * 14, 14, 15), center),
			Color = PARTY_COLORS[index],
			Material = Enum.Material.Neon,
			Parent = stage,
		})
		local light = Instance.new("SpotLight")
		light.Color = PARTY_COLORS[index]
		light.Brightness = 4
		light.Range = 30
		light.Angle = 40
		light.Shadows = false
		light.Parent = lamp
	end

	local cannonBase = Shapes.RoundedBox(Vector3.new(4.5, 2.2, 4.5), 0.6, {
		Name = "CannonBase",
		CFrame = CFrame.new(center + Vector3.new(20, 1.1, -6)),
		Color = rgb(80, 80, 100),
		Parent = stage,
	})
	Shapes.Capsule(6, 2.6, {
		Name = "CannonBarrel",
		CFrame = CFrame.new(center + Vector3.new(20, 3.8, -6)) * CFrame.Angles(0, 0, math.rad(60)),
		Color = rgb(255, 90, 140),
		Parent = stage,
	})
	return prompt(cannonBase, "Fire Confetti!", "Confetti Cannon"), center + Vector3.new(0, 10, 0)
end

-- A spiral tower: twelve candy-colored steps around a pillar up to a railed view deck.
local function buildParkour(root: Model): Vector3
	local course = Build.Model("ParkourRoute", root)
	local center = Vector3.new(88, 0, -72)
	local radius = 16
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

	for index = 1, 12 do
		local angle = startAngle + math.rad(30 * index)
		local position = around(angle, 2.4 * index)
		Shapes.RoundedBox(Vector3.new(6, 1.2, 6), 0.5, {
			Name = "Step" .. index,
			CFrame = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)),
			Color = Color3.fromHSV(index / 14, 0.5, 1),
			Parent = course,
		})
	end

	local deckHeight = 31
	disc(
		"Pillar",
		8,
		deckHeight - 0.5,
		center + Vector3.new(0, (deckHeight - 0.5) / 2, 0),
		{ Color = rgb(155, 125, 235), Parent = course }
	)
	local deckCenter = center + Vector3.new(0, deckHeight, 0)
	Shapes.Slab(
		Vector3.new(18, 1.2, 18),
		5,
		{ Name = "ViewDeck", CFrame = CFrame.new(deckCenter), Color = rgb(255, 222, 95), Parent = course }
	)
	local finish = Shapes.Slab(Vector3.new(6, 0.3, 6), 2.9, {
		Name = "ParkourFinish",
		CFrame = CFrame.new(deckCenter + Vector3.new(0, 0.75, 0)),
		Color = rgb(255, 120, 60),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = true,
		Parent = course,
	})
	tag(finish, "ParkourFinish")
	-- Railings on three sides keep the deck a safe hangout; the plaza side stays open as the way in.
	local inward = Vector3.new(math.cos(startAngle), 0, math.sin(startAngle))
	for _, offset in { Vector3.new(9, 2, 0), Vector3.new(-9, 2, 0), Vector3.new(0, 2, 9), Vector3.new(0, 2, -9) } do
		if offset.Unit:Dot(inward) > 0.7 then
			continue
		end
		local rotation = if offset.X ~= 0 then CFrame.Angles(0, math.rad(90), 0) else CFrame.identity
		Shapes.Capsule(18, 0.8, {
			Name = "Rail",
			CFrame = CFrame.new(deckCenter + offset + Vector3.new(0, 1, 0)) * rotation,
			Color = rgb(255, 255, 255),
			Parent = course,
		})
	end
	Shapes.Capsule(10, 0.5, {
		Name = "FlagPole",
		CFrame = CFrame.new(deckCenter - inward * 7 + Vector3.new(0, 5.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = rgb(240, 240, 240),
		CanCollide = false,
		Parent = course,
	})
	Build.Decor({
		Name = "Flag",
		Size = Vector3.new(0.2, 3, 5),
		CFrame = CFrame.new(deckCenter - inward * 7 + Vector3.new(0, 9, 2.5)),
		Color = rgb(255, 90, 140),
		Parent = course,
	})
	return deckCenter + Vector3.new(4, 2.5, 4)
end

local function buildBouncePads(root: Model)
	for index, point in Build.Ring(Vector3.new(0, 0, 0), 60, 4, math.pi / 4) do
		disc(
			"BounceRim",
			10.4,
			0.7,
			point.Position + Vector3.new(0, 0.3, 0),
			{ Color = rgb(255, 255, 255), Parent = root }
		)
		local pad = disc("BouncePad" .. index, 9, 0.9, point.Position + Vector3.new(0, 0.45, 0), {
			Color = rgb(120, 240, 255),
			Material = Enum.Material.Neon,
			CanTouch = true,
			Parent = root,
		})
		pad:SetAttribute("Power", 95)
		tag(pad, "BouncePad")
	end
end

local function buildScenery(root: Model)
	local scenery = Build.Model("Scenery", root)
	local rng = Random.new(42)
	for _, point in Build.Ring(Vector3.new(0, 0, 0), 150, 18, 0.1) do
		local jitter = Vector3.new(rng:NextNumber(-8, 8), LAWN_Y, rng:NextNumber(-8, 8))
		MeshLibrary.Get("Tree", {
			Scale = rng:NextNumber(0.8, 1.3),
			CFrame = CFrame.new(point.Position + jitter) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = scenery,
		})
	end
	for _, point in Build.Ring(Vector3.new(0, 0, 0), 121, 28, 0.05) do
		MeshLibrary.Get("Bush", {
			Scale = rng:NextNumber(0.7, 1.2),
			CFrame = CFrame.new(point.Position + Vector3.new(0, LAWN_Y, 0))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = scenery,
		})
	end
	-- Lamp posts strung together with party streamers.
	local lamps = {}
	for _, point in Build.Ring(Vector3.new(0, 0, 0), 104, 8, math.pi / 8) do
		local lamp = MeshLibrary.Get("LampPost", { CFrame = CFrame.new(point.Position), Parent = scenery })
		table.insert(lamps, lamp)
	end
	for index, lamp in lamps do
		local nextLamp = lamps[(index % #lamps) + 1]
		local fromPart, toPart = lamp.PrimaryPart, nextLamp.PrimaryPart
		if fromPart and toPart then
			local topOffset = fromPart.CFrame:PointToObjectSpace(lamp:GetPivot().Position + Vector3.new(0, 10.5, 0))
			streamer(fromPart, toPart, topOffset, ((index - 1) % #PARTY_COLORS) + 1)
		end
	end
	for index, point in Build.Ring(Vector3.new(0, 0, 0), 95, 10, 0.3) do
		local balloon = MeshLibrary.Get("Balloon", {
			Colors = { Balloon = PARTY_COLORS[(index % #PARTY_COLORS) + 1] },
			Scale = 1.4,
			CFrame = CFrame.new(point.Position),
			Parent = scenery,
		})
		tag(balloon, "PP_Bob")
	end
	-- Floating ambient sparkles over the plaza.
	for _, point in Build.Ring(Vector3.new(0, 0, 0), 60, 3, 0.5) do
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
end

function LobbyBuilder.Build(): LobbyRefs
	setupLighting()
	local root = Build.Model("Lobby", workspace)
	-- Ground and spawns first so early joiners always land on something.
	buildGround(root)
	buildSpawns(root)
	Environment.Build()
	buildCenter(root)
	local pads = buildVoteStage(root)
	buildPodium(root)
	buildShop(root)
	local dailyPrompt = buildQuestCorner(root)
	local targets, targetBoard = buildArcade(root)
	local confettiPrompt, confettiPosition = buildEmoteStage(root)
	local deckSpot = buildParkour(root)
	buildBouncePads(root)
	buildScenery(root)

	return {
		Root = root,
		VotePads = pads,
		DailyPrompt = dailyPrompt,
		ConfettiPrompt = confettiPrompt,
		ConfettiPosition = confettiPosition,
		-- Hidden daily token spots: one is picked per day (§5 "Secret collectible").
		TokenSpots = {
			deckSpot,
			Vector3.new(-83, 19.4, 6), -- on the shop awning
			Vector3.new(0, 2.5, -112), -- behind the vote wall
			Vector3.new(90, 18.5, 0), -- atop the champion board
			Vector3.new(0, 5.5, 84), -- center of the emote stage
			Vector3.new(-140, 2.5, -70), -- out among the trees
			Vector3.new(130, 2.5, 95), -- far corner past the arcade
		},
		Targets = targets,
		TargetBoard = targetBoard,
	}
end

return LobbyBuilder

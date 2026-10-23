-- The lobby dressed for the crate season (owner: "Hollow night comes first I want you to actually work
-- on adding it to the game right now ... This has to be sick. This will be players first season. I
-- want it to look insane."; Shared/Seasons.Current names the season, and it always runs). Built by
-- LobbyBuilder in the fountain's place; the meshes are World/Props/HollowNight.
--
--   * The pile: a giant tree stump the fountain's size (25 studs across), roots over the plaza, piled
--     with leaves, about 24 crates, pumpkins and gourds. A giant Hollow Crate on top turns slowly
--     (PP_Spin) with three Lantern Keys circling it; each device adds the green wisps round the top.
--     Invisible steps let players climb it (its top is the giant crate's lid).
--   * Three opening altars on the far side of the pile from the spawns (18.5 studs out, at 50, 90 and
--     130 degrees), so a crowd round an opening never blocks someone spawning in. Each has a Hollow
--     Crate on it, a Lantern Key floating over it while it's free, and the OPEN prompt (Services/
--     CrateService opens it; PP_AltarBusy says who's opening). Tagged PP_CrateAltar for the devices.
--   * The Top Unboxers board on the east side, facing the pile (both faces: PP_CrateBoard screens,
--     drawn by each device from GameState CrateBoard).
--   * Autumn: the trees and bushes in reds, oranges and golds, golden grass (the plaza and the
--     terrain), lantern posts round the promenade, pumpkins by the benches and zones, leaves falling
--     instead of confetti, leaf heaps on the lawn to jump into (PP_LeafHeap: each device bursts them),
--     and crows on the rooftops (PP_Crow: each device makes them caw, and fly off at a big pull).
--   * The meshes each device needs for the openings, pets and hats (SeasonMeshes in ReplicatedStorage).
-- The harvest moon, the season look (light), the wisps and the welcome moment (the trees turning
-- from green to orange) are each device's own (Controllers/SeasonWorldController).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local SeasonArt = require(Shared.SeasonArt)
local Seasons = require(Shared.Seasons)

local Build = require(script.Parent.Build)
local Hats = require(script.Parent.Hats)
local MeshLibrary = require(script.Parent.MeshLibrary)

local SeasonWorld = {}

export type Altar = { Model: Model, Prompt: ProximityPrompt, Position: Vector3 }

SeasonWorld.AltarAngles = { 50, 90, 130 } -- degrees from +X toward +Z (the spawns are at -90)
SeasonWorld.AltarRadius = 18.5
SeasonWorld.BoardPosition = Vector3.new(26.5, 0.2, 7.5)
SeasonWorld.PileRadius = 12.6 -- the stump (its roots reach a little further)
SeasonWorld.TemplatesName = "SeasonMeshes"

local GROUND = 0.2 -- the court's top (the fountain stood here)
local TOP_CRATE_SCALE = 2
local TOP_CRATE_Y = 9.7

-- The autumn palette for leaves (the design renders').
local AUTUMN = {
	Color3.fromRGB(214, 72, 38),
	Color3.fromRGB(238, 120, 40),
	Color3.fromRGB(246, 168, 48),
	Color3.fromRGB(200, 96, 40),
	Color3.fromRGB(232, 190, 70),
}
local AUTUMN_BUSH = {
	Color3.fromRGB(190, 70, 40),
	Color3.fromRGB(222, 112, 44),
	Color3.fromRGB(170, 96, 46),
}
local LAWN = Color3.fromRGB(168, 160, 74)
local TERRAIN = {
	[Enum.Material.Grass] = Color3.fromRGB(158, 153, 69),
	[Enum.Material.LeafyGrass] = Color3.fromRGB(179, 133, 56),
}

local altars: { Altar } = {}
local built = false

local function tag(instance: Instance, name: string)
	CollectionService:AddTag(instance, name)
end

local function facing(position: Vector3, target: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
end

local function onGround(angleDegrees: number, radius: number): Vector3
	local angle = math.rad(angleDegrees)
	return Vector3.new(math.cos(angle) * radius, GROUND, math.sin(angle) * radius)
end

-- An invisible upright cylinder players stand on.
local function step(parent: Instance, name: string, radius: number, bottom: number, top: number)
	Build.Part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(top - bottom, radius * 2, radius * 2),
		CFrame = CFrame.new(0, (bottom + top) / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Transparency = 1,
		Parent = parent,
	})
end

local function ember(parent: BasePart, rate: number, spread: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Embers"
	emitter.Texture = if SeasonArt.Ember ~= ""
		then SeasonArt.Ember
		else "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 196, 92), Color3.fromRGB(255, 110, 40))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(2.5, 4)
	emitter.Speed = NumberRange.new(1.5, 3)
	emitter.SpreadAngle = Vector2.new(spread, spread)
	emitter.Acceleration = Vector3.new(0, 0.6, 0)
	emitter.Drag = 0.6
	emitter.Rate = rate
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = parent
	tag(emitter, "PP_Ambient")
	return emitter
end

-- The pile ----------------------------------------------------------------------------------------

local function buildPile(root: Model)
	local season = Seasons.CurrentSeason()
	local pile = Build.Model("CratePile", root)
	MeshLibrary.Get(season.Props.Pile, { CFrame = CFrame.new(0, GROUND, 0), Parent = pile })

	-- The giant crate on top turns (each device turns it), its keys circling it.
	local top = MeshLibrary.Get(season.Props.Crate, {
		Scale = TOP_CRATE_SCALE,
		CFrame = CFrame.new(0, TOP_CRATE_Y, 0) * CFrame.Angles(0, 0.4, 0),
		Parent = pile,
	})
	top.Name = "TopCrate"
	tag(top, "PP_Spin")
	local keys = Build.Model("Keys", pile)
	for index = 1, 3 do
		local angle = index * math.pi * 2 / 3 + 0.5
		local position = Vector3.new(math.cos(angle) * 4.8, TOP_CRATE_Y + 3.5, math.sin(angle) * 4.8)
		local key = MeshLibrary.Get(season.Props.Key, {
			Scale = 1.6,
			CFrame = CFrame.new(position) * CFrame.Angles(0, -angle + math.pi / 2, math.rad(20)),
			Parent = keys,
		})
		key.Name = "Key" .. index
	end
	keys.WorldPivot = CFrame.new(0, TOP_CRATE_Y + 3.5, 0)
	tag(keys, "PP_Spin")
	keys:SetAttribute("PP_SpinSpeed", -0.35) -- (they circle the other way, a little faster)

	-- Steps to climb it: the stump, the leaf mound, the crate rings, and the giant crate's lid.
	local colliders = Build.Model("Colliders", pile)
	step(colliders, "Stump", 12.5, 0, GROUND + 1.7)
	step(colliders, "Mound", 9.6, GROUND + 1.7, GROUND + 3.6)
	step(colliders, "RingLow", 8.2, GROUND + 3.6, GROUND + 5.9)
	step(colliders, "RingMid", 5.6, GROUND + 5.9, GROUND + 8.0)
	step(colliders, "TopCrate", 3.3, GROUND + 8.0, TOP_CRATE_Y + 6.9)

	-- Its light: a warm glow over the top, and embers rising off it.
	local glow = Build.Decor({
		Name = "PileGlow",
		Size = Vector3.one,
		Transparency = 1,
		CFrame = CFrame.new(0, TOP_CRATE_Y + 3, 0),
		Parent = pile,
	})
	Build.Light(glow, Color3.fromRGB(255, 170, 80), 30, 1.3)
	glow:SetAttribute("PP_PileGlow", true) -- (each device flares it in a pull's tier colour)
	local embers = Build.Decor({
		Name = "PileEmbers",
		Size = Vector3.new(16, 1, 16),
		Transparency = 1,
		CFrame = CFrame.new(0, GROUND + 4, 0),
		Parent = pile,
	})
	ember(embers, 6, 25)
	tag(pile, "PP_CratePile")
end

-- The altars --------------------------------------------------------------------------------------

local function buildAltars(root: Model)
	local season = Seasons.CurrentSeason()
	local folder = Build.Model("Altars", root)
	for index, degrees in SeasonWorld.AltarAngles do
		local position = onGround(degrees, SeasonWorld.AltarRadius)
		-- Facing away from the pile, toward whoever walks up.
		local frame = facing(position, position * 2)
		local model = Build.Model("Altar" .. index, folder)
		MeshLibrary.Get(season.Props.Altar, { CFrame = frame, Parent = model })
		local crate = MeshLibrary.Get(season.Props.Crate, {
			CFrame = frame * CFrame.new(0, 1.35, 0),
			Parent = model,
		})
		crate.Name = "AltarCrate"
		-- A key floats over every free altar (each device hides it while it's busy, and bobs it).
		local key = MeshLibrary.Get(season.Props.Key, {
			Scale = 1.1,
			CFrame = frame * CFrame.new(0, 5.6, 0) * CFrame.Angles(0, 0, math.rad(-20)),
			Parent = model,
		})
		key.Name = "FloatingKey"
		tag(key, "PP_Bob")
		-- Solid steps (the mesh doesn't collide) and the prompt.
		Build.Part({
			Name = "AltarStep",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.35, 5.4, 5.4),
			CFrame = CFrame.new(position + Vector3.new(0, 0.675, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Transparency = 1,
			Parent = model,
		})
		local spot = Build.Decor({
			Name = "PromptSpot",
			Size = Vector3.one,
			Transparency = 1,
			CFrame = frame * CFrame.new(0, 3, 0),
			Parent = model,
		})
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "OpenPrompt"
		prompt.ActionText = "OPEN"
		prompt.ObjectText = `{season.Crate} · uses 1 key`
		prompt.HoldDuration = 0.35
		prompt.MaxActivationDistance = 11
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = spot
		local light = Build.Light(spot, Color3.fromRGB(255, 150, 70), 14, 0.9)
		light.Name = "AltarLight"
		model:SetAttribute("PP_Altar", index)
		model:SetAttribute("PP_AltarBusy", 0)
		model.WorldPivot = frame
		tag(model, "PP_CrateAltar")
		table.insert(altars, { Model = model, Prompt = prompt, Position = position })
	end
end

-- The Top Unboxers board --------------------------------------------------------------------------

local function buildBoard(root: Model)
	local season = Seasons.CurrentSeason()
	local position = SeasonWorld.BoardPosition
	local frame = facing(position, Vector3.new(0, position.Y, 0))
	local board = Build.Model("TopUnboxers", root)
	MeshLibrary.Get(season.Props.Board, { CFrame = frame, Parent = board })
	-- The screen in the frame: 10 x 13, its middle 9 up; both faces are drawn (front: toward the pile).
	local screen = Build.Part({
		Name = "Screen",
		Size = Vector3.new(10, 13, 0.6),
		CFrame = frame * CFrame.new(0, 9.2, 0),
		Color = Color3.fromRGB(28, 15, 46),
		Material = Enum.Material.SmoothPlastic,
		Parent = board,
	})
	tag(screen, "PP_CrateBoard")
	-- Solid legs (the mesh doesn't collide).
	Build.Part({
		Name = "Base",
		Size = Vector3.new(11, 16, 1),
		CFrame = frame * CFrame.new(0, 8, 0),
		Transparency = 1,
		Parent = board,
	})
end

-- Autumn ------------------------------------------------------------------------------------------

-- Every tree and bush of the lobby turns: leaves in autumn colours (picked evenly round the plaza,
-- so neighbours differ). The trees' green is kept (PP_SpringColor) for the welcome moment.
local function autumnFoliage(root: Instance)
	local rng = Random.new(10)
	for _, model in root:GetDescendants() do
		if not model:IsA("Model") or (model.Name ~= "Tree" and model.Name ~= "Bush") then
			continue
		end
		local palette = if model.Name == "Tree" then AUTUMN else AUTUMN_BUSH
		local color = palette[rng:NextInteger(1, #palette)]
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "Leaves" then
				part:SetAttribute("PP_SpringColor", part.Color)
				part.Color = color
			end
		end
		tag(model, "PP_AutumnTree")
	end
end

local function lanterns(root: Model)
	local folder = Build.Model("Lanterns", root)
	-- Round the promenade's edge, between the zones and clear of the walkways and benches.
	for _, degrees in { 15, 35, 65, 115, 145, 165, 195, 225, 248, 292, 315, 345 } do
		local position = onGround(degrees, 43.5)
		local post = MeshLibrary.Get("LanternPost", {
			CFrame = facing(position, Vector3.new(0, position.Y, 0)),
			Parent = folder,
		})
		post.Name = "LanternPost"
		local glow = post:FindFirstChild("Glow", true) :: BasePart?
		if glow then
			Build.Light(glow, Color3.fromRGB(255, 166, 72), 16, 1.1)
		end
	end
end

local function pumpkins(root: Model)
	local folder = Build.Model("Pumpkins", root)
	local rng = Random.new(31)
	local spots = {
		{ 8, 33.5 }, -- by the benches
		{ 58, 33.5 },
		{ 122, 33.5 },
		{ 172, 33.5 },
		{ 208, 33.5 },
		{ 332, 33.5 },
		{ 70, 22 }, -- round the altars
		{ 110, 22 },
		{ 30, 21.5 },
		{ 150, 21.5 },
	}
	for _, spot in spots do
		local base = onGround(spot[1], spot[2])
		for index = 1, rng:NextInteger(2, 3) do
			local offset = Vector3.new(rng:NextNumber(-1.6, 1.6), 0, rng:NextNumber(-1.6, 1.6))
			local scale = if index == 1 then rng:NextNumber(1, 1.3) else rng:NextNumber(0.55, 0.85)
			local colors = if index == 3 then { Pumpkin = Color3.fromRGB(242, 228, 196) } else nil
			MeshLibrary.Get("HarvestPumpkin", {
				Scale = scale,
				Colors = colors,
				CFrame = CFrame.new(base + offset) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = folder,
			})
		end
	end
end

-- Leaf heaps on the lawn: jump in and they burst (each device sees it: PP_LeafHeap).
local function leafHeaps(root: Model)
	local folder = Build.Model("LeafHeaps", root)
	for index, spot in { { 40, 52 }, { 140, 51 }, { 200, 50 }, { 340, 52 }, { 98, 47 } } do
		local position = onGround(spot[1], spot[2]) - Vector3.new(0, GROUND, 0)
		local heap = MeshLibrary.Get("LeafHeap", {
			Scale = 1.15,
			CFrame = CFrame.new(position) * CFrame.Angles(0, index * 1.3, 0),
			Parent = folder,
		})
		heap.Name = "LeafHeap" .. index
		for _, part in heap:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanQuery = false
			end
		end
		heap:SetAttribute("PP_HeapRadius", 3.6)
		tag(heap, "PP_LeafHeap")
	end
end

-- Crows on the rooftops (the spots players can find the daily token on are the high ones). Each
-- device animates them; a pet or title pull sends them flying across the sky.
local CROW_SPOTS = {
	CFrame.new(-57, 20, 2.5) * CFrame.Angles(0, math.rad(80), 0), -- the shop's awning
	CFrame.new(-61, 20, 5.5) * CFrame.Angles(0, math.rad(110), 0),
	CFrame.new(61.6, 20.5, 10) * CFrame.Angles(0, math.rad(-100), 0), -- the champion board
	CFrame.new(65.6, 20.5, 9.5) * CFrame.Angles(0, math.rad(-60), 0),
	CFrame.new(17, 8, 61.6) * CFrame.Angles(0, math.rad(180), 0), -- the emote stage's speaker
	CFrame.new(-1.8, 16.6, 0), -- the board's cap (in the board's frame)
}

local function crows(root: Model)
	local folder = Build.Model("Crows", root)
	local board = CFrame.lookAt(SeasonWorld.BoardPosition, Vector3.new(0, SeasonWorld.BoardPosition.Y, 0))
	for index, spot in CROW_SPOTS do
		local frame = if index == #CROW_SPOTS then board * spot else spot
		local crow = MeshLibrary.Get("HarvestCrow", { Scale = 1.4, CFrame = frame, Parent = folder })
		crow.Name = "Crow" .. index
		crow:SetAttribute("PP_Perch", frame)
		tag(crow, "PP_Crow")
	end
	local second = MeshLibrary.Get("HarvestCrow", {
		Scale = 1.3,
		CFrame = board * CFrame.new(2.4, 16.6, 0) * CFrame.Angles(0, math.rad(40), 0),
		Parent = folder,
	})
	second.Name = "Crow" .. (#CROW_SPOTS + 1)
	second:SetAttribute("PP_Perch", second:GetPivot())
	tag(second, "PP_Crow")
end

-- The confetti over the plaza turns into falling leaves.
local function fallingLeaves(root: Instance)
	local sky = root:FindFirstChild("ConfettiSky", true)
	local emitter = sky and sky:FindFirstChildWhichIsA("ParticleEmitter")
	if not emitter then
		return
	end
	if SeasonArt.Leaves ~= "" then
		emitter.Texture = SeasonArt.Leaves
		emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
		emitter.FlipbookMode = Enum.ParticleFlipbookMode.Random
		emitter.Squash = NumberSequence.new(0)
		emitter.Size = NumberSequence.new(0.7)
	else
		emitter.Size = NumberSequence.new(0.55)
	end
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, AUTUMN[1]),
		ColorSequenceKeypoint.new(0.3, AUTUMN[2]),
		ColorSequenceKeypoint.new(0.6, AUTUMN[3]),
		ColorSequenceKeypoint.new(1, AUTUMN[5]),
	})
	emitter.LightEmission = 0.1
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Speed = NumberRange.new(1.5, 2.5)
	emitter.Acceleration = Vector3.new(0.4, -0.5, 0.2)
	emitter.Lifetime = NumberRange.new(9, 12)
	emitter.Rate = 9
	emitter.Name = "FallingLeaves"
end

local function autumnGround(root: Instance)
	local plaza = root:FindFirstChild("Plaza", true)
	if plaza and plaza:IsA("BasePart") then
		plaza:SetAttribute("PP_SpringColor", plaza.Color)
		plaza.Color = LAWN
		tag(plaza, "PP_AutumnTree")
	end
	local terrain = workspace.Terrain
	for material, color in TERRAIN do
		pcall(function()
			terrain:SetMaterialColor(material, color)
		end)
	end
end

-- The meshes the devices clone for the openings (crates, keys, prizes), the pets and the hats.
local function templates()
	local season = Seasons.CurrentSeason()
	local folder = ReplicatedStorage:FindFirstChild(SeasonWorld.TemplatesName) or Instance.new("Folder")
	folder.Name = SeasonWorld.TemplatesName
	local names = { season.Props.Crate, season.Props.Key, "PaperLantern", "HarvestCrow" }
	for _, pet in season.Pets do
		table.insert(names, season.PetInfo[pet].Prop)
	end
	for _, hat in season.Hats do
		local prop = Hats.PropOf(hat)
		if prop then
			table.insert(names, prop)
		end
	end
	for _, name in names do
		if not folder:FindFirstChild(name) then
			local ok, model = pcall(MeshLibrary.Get, name)
			if ok then
				model.Name = name
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.CanCollide = false
						part.CanQuery = false
						part.CanTouch = false
					end
				end
				model.Parent = folder
			else
				warn(`[SeasonWorld] {name}: {model}`)
			end
		end
	end
	folder.Parent = ReplicatedStorage
end

-- Builds the season's pile, altars and board in the fountain's place. False when no season has a
-- lobby (the fountain stays).
function SeasonWorld.Build(root: Model): boolean
	local season = Seasons.CurrentSeason()
	if not season.Props then
		return false
	end
	buildPile(root)
	buildAltars(root)
	buildBoard(root)
	built = true
	task.spawn(templates)
	return true
end

-- The autumn dressing, once the rest of the lobby is up (its trees and lawn).
function SeasonWorld.Dress(root: Model)
	if not built then
		return
	end
	autumnFoliage(root)
	autumnFoliage(workspace) -- (the sky islands' trees)
	autumnGround(root)
	lanterns(root)
	pumpkins(root)
	leafHeaps(root)
	crows(root)
	fallingLeaves(root)
	workspace:SetAttribute("PP_Season", Seasons.Current)
end

function SeasonWorld.Altars(): { Altar }
	return altars
end

return SeasonWorld

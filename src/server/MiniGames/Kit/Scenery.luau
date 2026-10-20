-- Shared scenery for mini-game arenas, so games in the same setting look alike and their modules
-- stay about gameplay: a lava lake (glowing surface, lights, embers, heat haze), dark ground out to
-- the horizon, volcano backdrops with smoke plumes and a rim of rock spires.
--
-- Ambient particles are tagged PP_Ambient so players with reduced effects don't get them.

local CollectionService = game:GetService("CollectionService")

local Build = require(script.Parent.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.Parent.World.MeshLibrary)

local Scenery = {}

local rng = Random.new()

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function ambient(emitter: ParticleEmitter, parent: Instance)
	emitter.Parent = parent
	CollectionService:AddTag(emitter, "PP_Ambient")
end

-- A cylinder part's CFrame standing upright at `center` (Roblox cylinders run along X; turned onto
-- Y, its +X face is the top).
local function upright(center: Vector3): CFrame
	return CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
end

-- A round lava lake whose surface is at `surface`, with a glow layer, lights, embers and haze.
function Scenery.LavaLake(context, surface: Vector3, diameter: number): BasePart
	local lava = Build.Part({
		Name = "Lava",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, diameter, diameter),
		CFrame = upright(surface - Vector3.new(0, 1, 0)),
		Color = rgb(255, 105, 30),
		Material = Enum.Material.CrackedLava,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = context.Arena,
	})
	Build.Decor({
		Name = "LavaGlow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, diameter - 2, diameter - 2),
		CFrame = upright(surface + Vector3.new(0, 0.3, 0)),
		Color = rgb(255, 140, 40),
		Material = Enum.Material.Neon,
		Transparency = 0.72,
		Parent = context.Arena,
	})
	local lights = math.clamp(math.floor(diameter / 40), 3, 8)
	for index = 0, lights - 1 do
		local angle = index / lights * math.pi * 2
		local glow = Build.Decor({
			Name = "LavaLight",
			Size = Vector3.one,
			Transparency = 1,
			CFrame = CFrame.new(
				surface + Vector3.new(math.cos(angle) * diameter * 0.2, 6, math.sin(angle) * diameter * 0.2)
			),
			Parent = context.Arena,
		})
		Build.Light(glow, rgb(255, 120, 40), 45, 2)
	end

	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(rgb(255, 170, 60))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.35, 0)
	embers.Lifetime = NumberRange.new(3, 5)
	embers.Speed = NumberRange.new(3, 7)
	embers.SpreadAngle = Vector2.new(20, 20)
	embers.EmissionDirection = Enum.NormalId.Right -- the cylinder's +X faces up
	embers.Rate = math.floor(diameter / 8)
	ambient(embers, lava)

	local haze = Instance.new("ParticleEmitter")
	haze.Texture = "rbxasset://textures/particles/smoke_main.dds"
	haze.Color = ColorSequence.new(rgb(255, 160, 110), rgb(120, 90, 90))
	haze.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.86),
		NumberSequenceKeypoint.new(1, 1),
	})
	haze.Size = NumberSequence.new(8, 16)
	haze.Lifetime = NumberRange.new(5, 8)
	haze.Speed = NumberRange.new(2, 4)
	haze.EmissionDirection = Enum.NormalId.Right
	haze.Rate = 5
	ambient(haze, lava)
	return lava
end

-- Dark volcanic ground out to the horizon, its top `drop` studs below `surface` (so a lake on it
-- shows its glowing surface and the ground is never coplanar with it).
function Scenery.Ground(context, surface: Vector3, drop: number?): BasePart
	local top = surface.Y - (drop or 0.6)
	return Build.Part({
		Name = "Ground",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 1000, 1000),
		CFrame = upright(Vector3.new(surface.X, top - 2, surface.Z)),
		Color = rgb(52, 40, 46),
		Material = Enum.Material.Basalt,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = context.Arena,
	})
end

-- A volcano standing on `base`, its lava runs facing `facing`, smoking from the crater.
function Scenery.Volcano(context, base: Vector3, facing: Vector3, scale: number): Model
	local flatFacing = Vector3.new(facing.X, base.Y, facing.Z)
	local volcano = MeshLibrary.Get("Volcano", {
		Scale = scale,
		CFrame = CFrame.lookAt(base, flatFacing),
		Parent = context.Arena,
	})
	local _, size = volcano:GetBoundingBox()
	local crater = Build.Decor({
		Name = "Crater",
		Size = Vector3.one,
		Transparency = 1,
		CFrame = CFrame.new(base + Vector3.new(0, size.Y - 2 * scale, 0)),
		Parent = volcano,
	})
	Build.Light(crater, rgb(255, 120, 40), 60, 3)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(rgb(90, 70, 75), rgb(40, 34, 38))
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.6, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Size = NumberSequence.new(10 * scale, 26 * scale)
	smoke.Lifetime = NumberRange.new(9, 13)
	smoke.Speed = NumberRange.new(3 * scale, 5 * scale)
	smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.Acceleration = Vector3.new(2, 0, 0) -- drifts with the wind
	smoke.RotSpeed = NumberRange.new(-8, 8)
	smoke.Rate = 3
	ambient(smoke, crater)
	return volcano
end

-- A ring of rock spires around `center` (on the ground at its Y), random sizes and turns.
function Scenery.RockRim(context, center: Vector3, radius: number, count: number, minScale: number, maxScale: number)
	for index = 0, count - 1 do
		local angle = (index + rng:NextNumber(-0.3, 0.3)) / count * math.pi * 2
		local distance = radius * rng:NextNumber(0.94, 1.08)
		MeshLibrary.Get("Spire", {
			Scale = rng:NextNumber(minScale, maxScale),
			CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * distance, -1, math.sin(angle) * distance))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = context.Arena,
		})
	end
end

return Scenery

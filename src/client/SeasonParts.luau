-- What the crate seasons' looks on each device share (Controllers/PetController, AuraController,
-- EffectsController): the season's meshes the server put in ReplicatedStorage (World/SeasonWorld's
-- SeasonMeshes: the pets, the paper lantern, the crow...), local copies of them that never collide
-- or block anything, and the season's particle textures (Shared/SeasonArt), with built-in stand-ins
-- while those aren't uploaded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeasonArt = require(ReplicatedStorage.Shared.SeasonArt)

local SeasonParts = {}

local FOLDER = "SeasonMeshes"
local CAMERA_SOLID = "PP_CameraSolid" -- (World/MeshLibrary's tag and collision group)
SeasonParts.Sparkle = "rbxasset://textures/particles/sparkles_main.dds"
SeasonParts.Smoke = "rbxasset://textures/particles/smoke_main.dds"
SeasonParts.Fire = "rbxasset://textures/particles/fire_main.dds"

-- The season's mesh called `name` (a Model), or nil while the server's copies haven't arrived.
function SeasonParts.Template(name: string): Model?
	local folder = ReplicatedStorage:FindFirstChild(FOLDER)
	local found = folder and folder:FindFirstChild(name)
	return if found and found:IsA("Model") then found else nil
end

-- Calls `callback()` whenever a new season mesh arrives (they come a few seconds after joining).
function SeasonParts.OnTemplates(callback: () -> ()): RBXScriptConnection
	local folder = ReplicatedStorage:FindFirstChild(FOLDER)
	if folder then
		return folder.ChildAdded:Connect(callback)
	end
	local connection: RBXScriptConnection
	local inner: RBXScriptConnection? = nil
	connection = ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == FOLDER and not inner then
			inner = child.ChildAdded:Connect(callback)
			callback()
		end
	end)
	return connection
end

-- A local copy of the season mesh `name` that's only decoration: anchored, no collisions, touches,
-- ray hits or shadows. Nil while the server's copies haven't arrived.
function SeasonParts.Copy(name: string): Model?
	local template = SeasonParts.Template(name)
	if not template then
		return nil
	end
	local model = template:Clone()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Massless = true
			-- (A crate's pieces stop the camera where the server built them; a copy that moves never does.)
			if part:HasTag(CAMERA_SOLID) then
				part:RemoveTag(CAMERA_SOLID)
				part.CollisionGroup = "Default"
			end
		end
	end
	return model
end

-- Makes `emitter` throw fallen leaves: the season's leaf flipbook (a random leaf each), or a soft
-- sparkle in the leaves' colours while that isn't uploaded.
function SeasonParts.Leaves(emitter: ParticleEmitter)
	if SeasonArt.Leaves ~= "" then
		emitter.Texture = SeasonArt.Leaves
		emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
		emitter.FlipbookMode = Enum.ParticleFlipbookMode.Random
	else
		emitter.Texture = SeasonParts.Sparkle
		emitter.Squash = NumberSequence.new(0.5) -- (a little flatter: more leaf than star)
	end
end

-- The season's ember (a soft glowing dot), or the sparkle.
function SeasonParts.EmberTexture(): string
	return if SeasonArt.Ember ~= "" then SeasonArt.Ember else SeasonParts.Sparkle
end

-- The autumn leaf colours, for particles.
SeasonParts.LeafColors = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(214, 72, 38)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(238, 120, 40)),
	ColorSequenceKeypoint.new(0.7, Color3.fromRGB(246, 168, 48)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(232, 190, 70)),
})

return SeasonParts

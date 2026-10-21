-- Keeps the camera out of the scenery (owner: "I keep clipping into some chair on fire rope what is
-- going on?"). Roblox's default camera sits behind the player and only stops in front of parts that
-- collide. Scenery props don't collide (nothing may snag on them), so the camera slid right inside
-- them: at Fire Rope, into a fire brazier's bowl behind the bridge (its rim and gold claws, seen
-- from inside, look like the back of a chair) or a rope tower at either end, showing their insides.
--
-- World/MeshLibrary puts the pieces of props marked `BlocksCamera` in the "PP_CameraSolid" collision
-- group (which collides with Default only) and tags them. Here, on this device only, they're made
-- solid: the camera's ray (Default group) now stops in front of them. Our own character is in a
-- group that passes through them (the lobby's PP_Players), and the server keeps them non-colliding,
-- so bots and everything the server moves are exactly as before. While our character is in a group
-- that would touch them (a new character the server hasn't grouped yet), they stay non-solid.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local SceneryCameraController = {}

local CAMERA_SOLID = "PP_CameraSolid" -- tag and collision group (World/MeshLibrary)

local player = Players.LocalPlayer
local solid = false

-- Whether a part in this collision group would bump into camera-solid scenery.
local function touchesScenery(group: string): boolean
	local ok, collides = pcall(function()
		return PhysicsService:CollisionGroupsAreCollidable(group, CAMERA_SOLID)
	end)
	if ok then
		return collides
	end
	return group == "Default"
end

local function apply(part: BasePart)
	if solid then
		part.CanQuery = true
		part.CanCollide = true
	else
		part.CanCollide = false
		part.CanQuery = false
	end
end

local function refresh()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local want = not (root and root:IsA("BasePart") and touchesScenery(root.CollisionGroup))
	if want == solid then
		return
	end
	solid = want
	for _, part in CollectionService:GetTagged(CAMERA_SOLID) do
		if part:IsA("BasePart") then
			apply(part)
		end
	end
end

local function watchCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root and root:IsA("BasePart") and character == player.Character then
		root:GetPropertyChangedSignal("CollisionGroup"):Connect(refresh)
	end
	refresh()
end

function SceneryCameraController.Start()
	CollectionService:GetInstanceAddedSignal(CAMERA_SOLID):Connect(function(part)
		refresh() -- (the groups may have changed since: an arena is built at the start of each round)
		if part:IsA("BasePart") then
			apply(part)
		end
	end)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	refresh()
end

return SceneryCameraController

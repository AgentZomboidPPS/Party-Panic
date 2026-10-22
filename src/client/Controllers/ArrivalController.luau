-- Holds this player's character where the server put it until this device has solid ground under
-- it (owner: "Friend fell through the floor while loading into pump and pop.").
--
-- Each round's arena is built on the server as the rules card comes up, far from the lobby, and
-- everyone is moved onto their spots straight after. Streaming is off, so every device gets the
-- whole arena, but a big one takes a phone seconds to download (Bobsled Run's track took one more
-- than 5), and the move doesn't wait for it. Each device moves its own character, so one that got
-- there before its floor dropped straight through and out of the world. Under each Pump & Pop pump
-- there are three solid layers (the pad, the hidden stage and the grass), all built before anyone
-- is moved: the friend's device had none of them yet. Being "frozen until GO" only stops walking and
-- jumping, not falling.
--
-- So whenever this character arrives somewhere (a new character, or the server moving it: onto its
-- spot, back after a fall, a respawn) and this device has nothing solid under its feet there, it's
-- held right there until it has. Rays go straight down from the root (and a little to each side),
-- against what the root itself collides with (its collision group), so it's the ground the character
-- would stand on. At most HOLD_LIMIT seconds, longer than the rules card and the countdown together.
-- Only this device waits: the round goes on for everyone, and a slow phone just stays put a moment
-- longer.
--
-- It never fights a mode that has the character in hand. It holds by putting the root back before
-- each physics step, never by anchoring it (modes anchor riders on the server until GO: Bumper
-- Ballers, Skate Escape, Parasol Plummet's fallers; a local un-anchor would undo theirs), and it
-- lets go the moment the root is anchored, the humanoid is PlatformStanding or sitting (Parasol
-- Plummet, Bobsled Run, Rockin' Raceway and Tanks! pose their riders that way; Sinking Sands' Kings
-- sit on thrones), or the server moves it again (then it starts over there). Walking, jumping and
-- falling in play are physics, not arrivals, so they're never held: a fall off an edge counts
-- wherever it did before.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local ArrivalController = {}

-- Seconds at most: longer than the rules card and the countdown together.
local HOLD_LIMIT = math.max(15, Config.Session.RulesTime + Config.Session.CountdownTime + 2)
local MOVED = 4 -- studs a root went between two physics steps: only the server (or a mode) moves one so
local REACH = 3 -- studs under the soles that still count as ground
-- Where the rays start round the root's middle: anything solid under the character's footprint.
local OFFSETS = {
	Vector3.zero,
	Vector3.new(0.8, 0, 0),
	Vector3.new(-0.8, 0, 0),
	Vector3.new(0, 0, 0.8),
	Vector3.new(0, 0, -0.8),
}

type Hold = { Root: BasePart, At: Vector3, Since: number }

local player = Players.LocalPlayer
local rays = RaycastParams.new()
rays.FilterType = Enum.RaycastFilterType.Exclude
rays.RespectCanCollide = true
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.RespectCanCollide = true

local hold: Hold? = nil
local lastRoot: BasePart? = nil
local lastAt: Vector3? = nil -- where the root was after the last physics step

-- How far below the root's middle a character's soles are.
local function legs(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		return 3
	end
	return humanoid.HipHeight + root.Size.Y / 2
end

local function probe(character: Model, humanoid: Humanoid, root: BasePart): boolean
	rays.FilterDescendantsInstances = { character }
	rays.CollisionGroup = root.CollisionGroup
	local down = Vector3.new(0, -(legs(humanoid, root) + REACH), 0)
	for _, offset in OFFSETS do
		if workspace:Raycast(root.Position + offset, down, rays) then
			return true
		end
	end
	-- Already in something solid (a spot set a little low): physics lifts it out, nothing to wait for.
	overlap.FilterDescendantsInstances = { character }
	overlap.CollisionGroup = root.CollisionGroup
	return #workspace:GetPartsInPart(root, overlap) > 0
end

-- Whether this device has something solid under the character's feet (within REACH of its soles,
-- among the parts its root collides with). A probe that fails says yes: never hold on a guess.
function ArrivalController.GroundUnder(character: Model, humanoid: Humanoid, root: BasePart): boolean
	local ok, found = pcall(probe, character, humanoid, root)
	return not ok or found == true
end

-- Whether a mode has the character in hand (anchored, PlatformStanding or sitting): never held.
local function taken(humanoid: Humanoid, root: BasePart): boolean
	return root.Anchored or humanoid.PlatformStand or humanoid.Sit
end

-- Where this device is holding its character right now, if it is (the check tools read this).
function ArrivalController.HeldAt(): Vector3?
	local held = hold
	return if held then held.At else nil
end

local function current(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character or not character.Parent then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

-- Before each physics step: has the character just arrived somewhere with nothing under it?
local function beforePhysics()
	local character, humanoid, root = current()
	if not character or not humanoid or not root then
		hold, lastRoot, lastAt = nil, nil, nil
		return
	end
	-- (Between the last step and this one only the server or a script can have moved it.)
	local arrived = root ~= lastRoot or (lastAt ~= nil and (root.Position - lastAt).Magnitude > MOVED)
	lastRoot = root
	local held = hold
	if held then
		if held.Root ~= root or taken(humanoid, root) or os.clock() - held.Since > HOLD_LIMIT then
			held = nil -- a mode has it now (or this has gone on long enough)
		elseif (root.Position - held.At).Magnitude > MOVED then
			held, arrived = nil, true -- moved again while held: start over where it is now
		end
	end
	if not held and arrived and not taken(humanoid, root) then
		held = { Root = root, At = root.Position, Since = os.clock() }
	end
	if held and ArrivalController.GroundUnder(character, humanoid, root) then
		held = nil -- solid ground under its feet: on with the game
	end
	hold = held
	if held then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = root.CFrame.Rotation + held.At
	end
end

local function afterPhysics()
	local root = lastRoot
	lastAt = if root and root.Parent then root.Position else nil
end

function ArrivalController.Start(_context)
	local before = (RunService :: any).PreSimulation or RunService.Stepped
	local after = (RunService :: any).PostSimulation or RunService.Heartbeat
	before:Connect(beforePhysics)
	after:Connect(afterPhysics)
end

return ArrivalController

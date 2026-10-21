-- Beach balls to kick around the lobby plaza (lobby polish: "give players fun things to do while
-- waiting"). Walking into a ball punts it: the server sets its velocity, so every player sees the
-- same ball. A ball that leaves the plaza, lands on the vote stage, sits in a trap (the fountain,
-- the emote stage) for a while or sits far from home for a minute rolls back to its spot, so the
-- plaza never loses its toys and the vote pads stay clear.
--
-- Players' characters don't collide with the balls (collision group PP_Players): the ball is
-- simulated on the server, so on a phone with some ping a solid ball would feel like a wall the
-- player bumps into, or climbs. Instead the server checks who is next to each ball and kicks it.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local Build = require(script.Parent.Build)
local MeshLibrary = require(script.Parent.MeshLibrary)

local BeachBalls = {}

local SIZE = 5
local KICK_SPEED = 28
local KICK_LIFT = 22
local KICK_COOLDOWN = 0.35
local KICK_REACH = SIZE / 2 + 1.8 -- from a character's root to the ball's center, flat
local MAX_RUN = 24 -- the run speed a kick counts (a client controls its own velocity)
local SCAN_EVERY = 0.1
local CHECK_EVERY = 2
local IDLE_RESET = 60 -- seconds still and away from home before a ball goes back
local TRAPPED_RESET = 10 -- seconds inside a trap zone before a ball goes back

local BALL_GROUP = "PP_BeachBall"
local PLAYER_GROUP = "PP_Players"

export type Bounds = {
	PlazaRadius: number, -- balls past this distance from the center go home
	StageFrontZ: number, -- balls behind this line (on the vote stage) go home
	Traps: { { Center: Vector3, Radius: number } }?, -- places a ball may not stay in for long
}

-- The velocity a kick from a character at `rootPosition`, moving at `runSpeed`, gives the ball.
function BeachBalls.KickVelocity(
	ballPosition: Vector3,
	rootPosition: Vector3,
	facing: Vector3,
	runSpeed: number
): Vector3
	local away = (ballPosition - rootPosition) * Vector3.new(1, 0, 1)
	if away.Magnitude < 0.1 then
		away = facing * Vector3.new(1, 0, 1)
	end
	if away.Magnitude < 0.1 then
		away = Vector3.new(0, 0, -1)
	end
	local run = math.clamp(runSpeed, 0, MAX_RUN)
	return away.Unit * (KICK_SPEED + run * 0.5) + Vector3.new(0, KICK_LIFT, 0)
end

-- Whether a ball at `position` is in one of the bounds' trap zones.
function BeachBalls.InTrap(position: Vector3, bounds: Bounds): boolean
	local traps: { { Center: Vector3, Radius: number } } = bounds.Traps or {}
	for _, trap in traps do
		if ((position - trap.Center) * Vector3.new(1, 0, 1)).Magnitude < trap.Radius then
			return true
		end
	end
	return false
end

-- Whether a ball at `position` that last moved `idleFor` seconds ago, and has been in a trap zone
-- for `trappedFor` seconds, should go back to `home`.
function BeachBalls.ShouldReset(
	position: Vector3,
	home: Vector3,
	idleFor: number,
	bounds: Bounds,
	trappedFor: number?
): boolean
	local flat = Vector3.new(position.X, 0, position.Z)
	local outside = position.Y < -10 or flat.Magnitude > bounds.PlazaRadius - 2
	local onStage = position.Z < bounds.StageFrontZ and math.abs(position.X) < 50
	local idleAway = idleFor > IDLE_RESET and (position - home).Magnitude > 20
	local trapped = (trappedFor or 0) > TRAPPED_RESET
	return outside or onStage or idleAway or trapped
end

local function setupGroups()
	if not PhysicsService:IsCollisionGroupRegistered(BALL_GROUP) then
		PhysicsService:RegisterCollisionGroup(BALL_GROUP)
	end
	if not PhysicsService:IsCollisionGroupRegistered(PLAYER_GROUP) then
		PhysicsService:RegisterCollisionGroup(PLAYER_GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(BALL_GROUP, PLAYER_GROUP, false)

	-- Players' characters join PP_Players, which collides with everything else as Default does.
	local function join(item: Instance)
		if item:IsA("BasePart") then
			item.CollisionGroup = PLAYER_GROUP
		end
	end
	local function onCharacter(character: Model)
		for _, item in character:GetDescendants() do
			join(item)
		end
		character.DescendantAdded:Connect(join)
	end
	local function onPlayer(player: Player)
		if player.Character then
			onCharacter(player.Character)
		end
		player.CharacterAdded:Connect(onCharacter)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
end

local function makeBall(parent: Instance, name: string, home: CFrame): Part
	local ball = Build.Part({
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * SIZE,
		CFrame = home,
		Transparency = 1,
		-- Light and bouncy, so a walk-in nudges it and a kick sends it flying.
		CustomPhysicalProperties = PhysicalProperties.new(0.12, 0.4, 0.6, 1, 1),
	})
	ball.Anchored = false
	ball.CollisionGroup = BALL_GROUP
	-- The look comes from the mesh prop, welded on and weightless; the ball part is the physics.
	local look = MeshLibrary.Get("LobbyBeachBall", { CFrame = home * CFrame.new(0, -SIZE / 2, 0), Parent = ball })
	for _, descendant in look:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			Build.Weld(ball, descendant)
		end
	end
	ball.Parent = parent
	ball:SetNetworkOwner(nil) -- the server simulates it, so every player sees the same ball
	return ball
end

-- The root part of a living character (a player's or a bot's) that `part` belongs to.
local function characterRoot(part: BasePart): BasePart?
	local character = part.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Puts a ball on each spot (ground level) and keeps them in play. Returns the balls.
function BeachBalls.Setup(parent: Instance, spots: { Vector3 }, bounds: Bounds): { BasePart }
	setupGroups()
	local folder = Build.Model("BeachBalls", parent)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { parent }
	overlap.RespectCanCollide = false

	local balls = {}
	for index, spot in spots do
		local home = CFrame.new(spot + Vector3.new(0, SIZE / 2, 0))
		local ball = makeBall(folder, "BeachBall" .. index, home)
		table.insert(balls, ball)

		-- Kicks: anyone standing against the ball punts it away from them.
		local lastKick = 0
		task.spawn(function()
			while ball.Parent do
				task.wait(SCAN_EVERY)
				if os.clock() - lastKick < KICK_COOLDOWN then
					continue
				end
				for _, part in workspace:GetPartBoundsInRadius(ball.Position, KICK_REACH + 1, overlap) do
					local root = characterRoot(part)
					local offset = if root then ball.Position - root.Position else Vector3.zero
					if
						not root
						or (offset * Vector3.new(1, 0, 1)).Magnitude > KICK_REACH
						or math.abs(offset.Y) > 4.5
					then
						continue
					end
					lastKick = os.clock()
					local run = (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
					local velocity = BeachBalls.KickVelocity(ball.Position, root.Position, root.CFrame.LookVector, run)
					ball.AssemblyLinearVelocity = velocity
					ball.AssemblyAngularVelocity = (velocity * Vector3.new(1, 0, 1)).Unit:Cross(Vector3.yAxis) * -6
					break
				end
			end
		end)

		-- Housekeeping: send strays home.
		task.spawn(function()
			local lastMoved, trappedSince = os.clock(), nil
			while ball.Parent do
				task.wait(CHECK_EVERY)
				local now = os.clock()
				if ball.AssemblyLinearVelocity.Magnitude > 1 then
					lastMoved = now
				end
				if BeachBalls.InTrap(ball.Position, bounds) then
					trappedSince = trappedSince or now
				else
					trappedSince = nil
				end
				local trappedFor = if trappedSince then now - trappedSince else 0
				if BeachBalls.ShouldReset(ball.Position, home.Position, now - lastMoved, bounds, trappedFor) then
					ball.AssemblyLinearVelocity = Vector3.zero
					ball.AssemblyAngularVelocity = Vector3.zero
					ball:PivotTo(home)
					lastMoved, trappedSince = now, nil
				end
			end
		end)
	end
	return balls
end

return BeachBalls

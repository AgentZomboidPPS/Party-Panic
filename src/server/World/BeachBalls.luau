-- Beach balls to kick around the lobby plaza (lobby polish: "give players fun things to do while
-- waiting"). Walking into a ball punts it: the server sets its velocity, so every player sees the
-- same ball. A ball that leaves the plaza, lands on the vote stage or sits far from home for a
-- minute rolls back to its spot, so the plaza never loses its toys and the vote pads stay clear.

local Build = require(script.Parent.Build)
local MeshLibrary = require(script.Parent.MeshLibrary)

local BeachBalls = {}

local SIZE = 5
local KICK_SPEED = 28
local KICK_LIFT = 22
local KICK_COOLDOWN = 0.35
local CHECK_EVERY = 2
local IDLE_RESET = 60 -- seconds still and away from home before a ball goes back

export type Bounds = {
	PlazaRadius: number, -- balls past this distance from the center go home
	StageFrontZ: number, -- balls behind this line (on the vote stage) go home
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
	return away.Unit * (KICK_SPEED + runSpeed * 0.5) + Vector3.new(0, KICK_LIFT, 0)
end

-- Whether a ball at `position` that last moved `idleFor` seconds ago should go back to `home`.
function BeachBalls.ShouldReset(position: Vector3, home: Vector3, idleFor: number, bounds: Bounds): boolean
	local flat = Vector3.new(position.X, 0, position.Z)
	local outside = position.Y < -10 or flat.Magnitude > bounds.PlazaRadius - 2
	local onStage = position.Z < bounds.StageFrontZ and math.abs(position.X) < 50
	local idleAway = idleFor > IDLE_RESET and (position - home).Magnitude > 20
	return outside or onStage or idleAway
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

-- Puts a ball on each spot (ground level) and keeps them in play. Returns the balls.
function BeachBalls.Setup(parent: Instance, spots: { Vector3 }, bounds: Bounds): { BasePart }
	local folder = Build.Model("BeachBalls", parent)
	local balls = {}
	for index, spot in spots do
		local home = CFrame.new(spot + Vector3.new(0, SIZE / 2, 0))
		local ball = makeBall(folder, "BeachBall" .. index, home)
		table.insert(balls, ball)

		local lastKick, lastMoved = 0, os.clock()
		ball.Touched:Connect(function(hit)
			local character = hit.Parent
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not humanoid or humanoid.Health <= 0 or not (root and root:IsA("BasePart")) then
				return
			end
			local now = os.clock()
			if now - lastKick < KICK_COOLDOWN then
				return
			end
			lastKick = now
			local run = (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
			local velocity = BeachBalls.KickVelocity(ball.Position, root.Position, root.CFrame.LookVector, run)
			ball.AssemblyLinearVelocity = velocity
			ball.AssemblyAngularVelocity = (velocity * Vector3.new(1, 0, 1)).Unit:Cross(Vector3.yAxis) * -6
		end)

		task.spawn(function()
			while ball.Parent do
				task.wait(CHECK_EVERY)
				if ball.AssemblyLinearVelocity.Magnitude > 1 then
					lastMoved = os.clock()
				end
				if BeachBalls.ShouldReset(ball.Position, home.Position, os.clock() - lastMoved, bounds) then
					ball.AssemblyLinearVelocity = Vector3.zero
					ball.AssemblyAngularVelocity = Vector3.zero
					ball:PivotTo(home)
					lastMoved = os.clock()
				end
			end
		end)
	end
	return balls
end

return BeachBalls

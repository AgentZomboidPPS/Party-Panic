-- Bumper Ballers (Knockback, 60s, 1 to 12 players). After "Bumper Balls" from the first Mario
-- Party (the owner's favourite): everyone rides on top of a big ball on a round island in the sea
-- and bumps everyone else off. Fall in the water and you're out; last one rolling wins. In the last
-- 15 seconds bumps get bigger (BIG BUMPS!) so a round never fizzles out.
--
-- How it works:
--   * Each ball is an unanchored sphere (Body) with a patterned mesh welded on (it rolls for real).
--     The rider stands on top: a BallSocket joins the rider's root to the ball's center and an
--     AlignOrientation keeps them upright, so the ball spins freely under their feet.
--   * A player's ball belongs to their device (ctx:GiveOwnership): their client pushes it with a
--     VectorForce from the move input (keyboard, thumbstick, gamepad or phone tilt), so steering is
--     smooth. Bots' balls belong to the server, which pushes them the same way with the same speed
--     and acceleration limits (MG_Tuning is shared so both sides use the same numbers).
--   * Bumps are decided here, by distance and closing speed: when two balls meet, each is pushed
--     apart by an amount that grows with the OTHER ball's speed into it, so the faster ball wins.
--     A player's push is sent to their client (MiniGameEvent "Bump"), a bot's is applied directly;
--     players and bots bump each other both ways under the same rules.
--   * Ring-outs are position checks: a ball whose center drops below the water line is out.
--   * Luau test servers have no physics, so there the server moves every ball itself with the same
--     drive model (see :_simulate), which is also how the round harness tests bots and bumps.

local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

local MiniGame = require(script.Parent.Kit.MiniGame)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local BumperBallers = MiniGame.Define("BumperBallers")

local BALL_SIZE = 8
local RADIUS = BALL_SIZE / 2
local ISLAND_RADIUS = 44 -- the flat top; a ball whose center rolls past it drops off the edge
local WATER_DROP = 5 -- water surface below the island top
local OUT_DEPTH = 1.5 -- a ball is out once its center is this far under the water surface
local BIG_BUMPS_AT = 45 -- seconds into the round
local RIDER_GROUP = "BumperRider"

-- The drive model both the clients and the server use (shared as MG_Tuning).
local TUNING = {
	Accel = 46, -- studs/s^2 at full input
	MaxSpeed = 24, -- studs/s top rolling speed (Accel / drag)
	Relief = 0.5, -- seconds after a bump with less drag, so bumps carry
	ReliefDrag = 0.3, -- drag multiplier during that time
}
local DRAG = TUNING.Accel / TUNING.MaxSpeed
local BUMP_BASE = 10 -- studs/s every bump gives
local BUMP_GAIN = 1.25 -- extra per stud/s of the other ball's speed into you
local BUMP_SELF = 0.25 -- extra per stud/s of your own speed into them (you bounce back a bit)
local BUMP_MAX = 62
local BUMP_LIFT = 7
local BIG_BUMPS = 1.4
local CLOSING_MIN = 4 -- closing speed (studs/s) that counts as a bump
local PAIR_COOLDOWN = 0.4
local HISTORY = 8 -- velocity samples kept (about 0.25 s): the bounce often happens before we see it
local GRAVITY = 110 -- simulated fall (no-physics servers only)

-- Every rider gets a color, a pattern on the ball and a shape tag, so color is never the only cue.
BumperBallers.Riders = {
	{ Name = "Red", Color = Color3.fromRGB(240, 70, 70), Shape = "●" },
	{ Name = "Blue", Color = Color3.fromRGB(60, 135, 255), Shape = "■" },
	{ Name = "Green", Color = Color3.fromRGB(70, 200, 95), Shape = "▲" },
	{ Name = "Yellow", Color = Color3.fromRGB(255, 205, 45), Shape = "★" },
	{ Name = "Purple", Color = Color3.fromRGB(160, 90, 255), Shape = "♦" },
	{ Name = "Orange", Color = Color3.fromRGB(255, 140, 40), Shape = "♥" },
	{ Name = "Pink", Color = Color3.fromRGB(255, 100, 190), Shape = "✚" },
	{ Name = "Cyan", Color = Color3.fromRGB(40, 210, 230), Shape = "◆" },
	{ Name = "Lime", Color = Color3.fromRGB(165, 230, 60), Shape = "▼" },
	{ Name = "Navy", Color = Color3.fromRGB(50, 60, 170), Shape = "☀" },
	{ Name = "Brown", Color = Color3.fromRGB(150, 95, 60), Shape = "☾" },
	{ Name = "Black", Color = Color3.fromRGB(45, 45, 55), Shape = "✿" },
}
BumperBallers.Patterns = { "BumperBallGores", "BumperBallBands", "BumperBallDots" }

local physics = RunService:IsRunning()
local rng = Random.new()

export type Entry = {
	Player: any,
	Index: number,
	Model: Model,
	Body: Part,
	Center: Attachment,
	Force: VectorForce,
	Socket: BallSocketConstraint,
	Seat: Attachment?,
	Align: AlignOrientation?,
	RiderOffset: number,
	ClientDriven: boolean,
	Input: Vector3,
	Position: Vector3,
	Velocity: Vector3,
	History: { Vector3 },
	ReliefUntil: number,
	Yaw: number,
	Spin: CFrame,
	Out: boolean,
	LastBumper: any,
	LastBumpAt: number,
	KOs: number,
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function registerRiderGroup()
	local ok = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(RIDER_GROUP) then
			PhysicsService:RegisterCollisionGroup(RIDER_GROUP)
		end
		-- Riders touch nothing: the ball does the bumping, and legs never snag on the island.
		PhysicsService:CollisionGroupSetCollidable(RIDER_GROUP, "Default", false)
		PhysicsService:CollisionGroupSetCollidable(RIDER_GROUP, RIDER_GROUP, false)
	end)
	return ok
end

local function setRiderCollision(character: Model, group: string)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

-- Arena -------------------------------------------------------------------------------------------

function BumperBallers:_buildArena()
	local ctx = self.context
	local top = self.top
	local center = self.center
	local waterY = self.waterY

	-- The island top: a real grass cylinder the balls roll on (Roblox cylinders run along X).
	Build.Part({
		Name = "IslandTop",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, ISLAND_RADIUS * 2, ISLAND_RADIUS * 2),
		CFrame = CFrame.new(center.X, top - 3, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(96, 190, 80),
		Material = Enum.Material.Grass,
		CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.6, 0.4, 1, 1),
		CanQuery = false,
		CanTouch = false,
		Parent = ctx.Arena,
	})
	-- Sand beach ring, striped warning lip, cliffs, foam and rocks (one mesh, no collisions).
	MeshLibrary.Get("BumperIsland", {
		CFrame = CFrame.new(center.X, top - self.islandHeight + self.islandAbove, center.Z),
		Parent = ctx.Arena,
	})

	-- Tropical sea: glassy turquoise over light sand near the island, deeper blue further out.
	Build.Decor({
		Name = "Sea",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 2048, 2048),
		CFrame = CFrame.new(center.X, waterY - 0.5, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(40, 175, 205),
		Material = Enum.Material.Glass,
		Transparency = 0.28,
		Reflectance = 0.08,
		Parent = ctx.Arena,
	})
	Build.Decor({
		Name = "Shallows",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 170, 170),
		CFrame = CFrame.new(center.X, waterY - 5, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(150, 225, 205),
		Material = Enum.Material.Sand,
		Parent = ctx.Arena,
	})
	Build.Decor({
		Name = "SeaBed",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 2048, 2048),
		CFrame = CFrame.new(center.X, waterY - 16, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(20, 85, 130),
		Material = Enum.Material.Sand,
		Parent = ctx.Arena,
	})

	-- Little palm islets around the arena, rocks in the surf.
	local islets = 7
	for index = 0, islets - 1 do
		local angle = (index + rng:NextNumber(-0.25, 0.25)) / islets * math.pi * 2
		local distance = rng:NextNumber(92, 150)
		local scale = rng:NextNumber(0.9, 1.5)
		local spot = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		MeshLibrary.Get("BumperIslet", {
			Scale = scale,
			CFrame = CFrame.new(spot.X, waterY - 1.2, spot.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = ctx.Arena,
		})
		local palms = rng:NextInteger(1, 2)
		for palm = 1, palms do
			local offset = Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)) * scale
			MeshLibrary.Get("BumperPalm", {
				Scale = rng:NextNumber(0.85, 1.25) * (if palm == 1 then 1 else 0.8),
				CFrame = CFrame.new(spot.X + offset.X, waterY - 1.2 + 2.7 * scale, spot.Z + offset.Z)
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = ctx.Arena,
			})
		end
	end
	for index = 0, 9 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(62, 84)
		MeshLibrary.Get("Boulder", {
			Scale = rng:NextNumber(0.5, 1.1),
			Colors = { Rock = Color3.fromRGB(125, 118, 112) },
			CFrame = CFrame.new(
				center.X + math.cos(angle) * distance,
				waterY - 2.5,
				center.Z + math.sin(angle) * distance
			) * CFrame.Angles(0, index * 1.7, 0),
			Parent = ctx.Arena,
		})
	end
	-- Hazy green islands on the horizon close off the view.
	for index = 0, 9 do
		local angle = (index + rng:NextNumber(-0.3, 0.3)) / 10 * math.pi * 2
		local distance = rng:NextNumber(560, 760)
		local size = Vector3.new(rng:NextNumber(160, 260), rng:NextNumber(60, 120), rng:NextNumber(110, 170))
		local hill = Build.Decor({
			Name = "FarIsland",
			Size = size,
			CFrame = CFrame.new(
				center.X + math.cos(angle) * distance,
				waterY - size.Y * 0.18,
				center.Z + math.sin(angle) * distance
			) * CFrame.Angles(0, -angle + math.pi / 2, 0),
			Color = Color3.fromRGB(80, 160, 95):Lerp(Color3.fromRGB(110, 170, 150), rng:NextNumber(0, 1)),
			Material = Enum.Material.Grass,
			Parent = ctx.Arena,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = hill
	end
end

-- Balls and riders ---------------------------------------------------------------------------------

function BumperBallers:_makeBall(player, index: number, spot: Vector3): Entry
	local rider = BumperBallers.Riders[(index - 1) % #BumperBallers.Riders + 1]
	local patternName = BumperBallers.Patterns[(index - 1) % #BumperBallers.Patterns + 1]
	local model = Build.Model(`Ball_{player.UserId}`, self.ballsFolder)

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.one * BALL_SIZE
	body.CFrame = CFrame.new(spot)
	body.Transparency = 1
	body.Anchored = true -- until GO
	body.CanQuery = false
	body.CanTouch = false
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	-- Dense (sinks, and riders barely tip it), grippy enough to roll, bouncy enough to boing.
	body.CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.5, 0.55, 1, 1)
	body.Parent = model
	model.PrimaryPart = body

	local visual = MeshLibrary.Get(patternName, {
		Colors = { Shell = rider.Color },
		CFrame = CFrame.new(spot - Vector3.new(0, RADIUS, 0)),
	})
	visual.Name = "Visual"
	local visualRoot = MeshLibrary.Assemble(visual, true)
	visual.Parent = model
	for _, part in visual:GetDescendants() do
		if part:IsA("BasePart") then
			part.CastShadow = true
		end
	end
	Build.Weld(body, visualRoot)

	local centerAttachment = Instance.new("Attachment")
	centerAttachment.Name = "Center"
	centerAttachment.Parent = body
	local force = Instance.new("VectorForce")
	force.Name = "Drive"
	force.Attachment0 = centerAttachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = body
	local socket = Instance.new("BallSocketConstraint")
	socket.Name = "RiderSocket"
	socket.Attachment0 = centerAttachment
	socket.Parent = body

	-- The rider's shape tag, floating over their head in their color.
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Adornee = body
	tag.Size = UDim2.fromScale(2.6, 2.6)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 12.2, 0)
	tag.MaxDistance = 140
	tag.LightInfluence = 0
	tag.Parent = body
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = rider.Shape
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = rider.Color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(1, 1, 1)
	label.Parent = tag

	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("Rider", rider.Name)
	model:SetAttribute("Shape", rider.Shape)
	model:SetAttribute("Color", rider.Color)
	model:SetAttribute("ClientDriven", false)
	model:SetAttribute("Index", index)

	local toCenter = flat(self.center - spot)
	local entry: Entry = {
		Player = player,
		Index = index,
		Model = model,
		Body = body,
		Center = centerAttachment,
		Force = force,
		Socket = socket,
		Seat = nil,
		Align = nil,
		RiderOffset = RADIUS + 3,
		ClientDriven = false,
		Input = Vector3.zero,
		Position = spot,
		Velocity = Vector3.zero,
		History = {},
		ReliefUntil = 0,
		Yaw = math.atan2(-toCenter.X, -toCenter.Z),
		Spin = CFrame.identity,
		Out = false,
		LastBumper = nil,
		LastBumpAt = 0,
		KOs = 0,
	}
	return entry
end

-- Stands the rider on top of their ball: socket at the ball's center, kept upright.
function BumperBallers:_attachRider(entry: Entry)
	local character, humanoid, root = self.context:GetCharacter(entry.Player)
	if not character or not humanoid or not root then
		return
	end
	if entry.Seat and entry.Seat.Parent == root then
		return
	end
	local offset = RADIUS + humanoid.HipHeight + root.Size.Y / 2
	entry.RiderOffset = offset
	character:PivotTo(CFrame.new(entry.Position + Vector3.new(0, offset, 0)) * CFrame.Angles(0, entry.Yaw, 0))
	root.AssemblyLinearVelocity = Vector3.zero

	local seat = Instance.new("Attachment")
	seat.Name = "BumperSeat"
	seat.Position = Vector3.new(0, -offset, 0)
	seat.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "BumperUpright"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = seat
	align.RigidityEnabled = true
	align.CFrame = CFrame.Angles(0, entry.Yaw, 0)
	align.Parent = root
	entry.Seat = seat
	entry.Align = align
	entry.Socket.Attachment1 = seat

	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	if self.groupReady then
		setRiderCollision(character, RIDER_GROUP)
	end
	if not entry.ClientDriven and physics then
		pcall(root.SetNetworkOwner, root, nil)
	end
end

function BumperBallers:_detachRider(entry: Entry)
	if entry.Seat then
		entry.Seat:Destroy()
		entry.Seat = nil
	end
	if entry.Align then
		entry.Align:Destroy()
		entry.Align = nil
	end
	local character, humanoid = self.context:GetCharacter(entry.Player)
	if character and humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		if self.groupReady then
			setRiderCollision(character, "Default")
		end
	end
end

function BumperBallers:_removeBall(entry: Entry)
	self:_detachRider(entry)
	if entry.Model.Parent then
		entry.Model:Destroy()
	end
	self.entries[entry.Player] = nil
end

-- Round ---------------------------------------------------------------------------------------------

function BumperBallers:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	ctx.WalkSpeed = 0 -- riders don't walk; the ball does the moving
	local origin = ctx.Origin.Position
	self.center = origin
	self.top = origin.Y
	self.waterY = origin.Y - WATER_DROP
	self.restY = origin.Y + RADIUS
	self.islandRadius = ISLAND_RADIUS
	ctx.KillY = self.waterY - 25
	self.islandHeight = 14 -- the island mesh's height (tools/meshgen/props/BumperBallers.py)
	self.islandAbove = 0.15 -- how far its sand rises over the grass top
	self.entries = {} :: { [any]: Entry }
	self.pairCooldown = {} :: { [string]: number }
	self.bumpScale = 1
	self.groupReady = registerRiderGroup()

	self:_buildArena()
	self.ballsFolder = Build.Folder("Balls", ctx.Arena)

	-- One ball per rider in a ring facing the middle; riders stand on them, frozen until GO.
	local players = ctx:GetPlayers()
	local count = #players
	local ringRadius = math.clamp(count * 2.1 + 4, 14, 27)
	local spots = {}
	local startAngle = rng:NextNumber(0, math.pi * 2)
	for index, player in players do
		local angle = startAngle + (index - 1) / math.max(count, 1) * math.pi * 2
		local spot =
			Vector3.new(origin.X + math.cos(angle) * ringRadius, self.restY, origin.Z + math.sin(angle) * ringRadius)
		local entry = self:_makeBall(player, index, spot)
		self.entries[player] = entry
		spots[index] = CFrame.new(spot + Vector3.new(0, entry.RiderOffset - 3, 0)) * CFrame.Angles(0, entry.Yaw, 0)
	end

	ctx.Hooks.CharacterReady = function(player)
		local entry = self.entries[player]
		if entry then
			self:_attachRider(entry)
		end
	end
	ctx.Hooks.Eliminated = function(player)
		local entry = self.entries[player]
		if not entry then
			return
		end
		entry.Out = true
		entry.Input = Vector3.zero
		-- The ball sinks for a moment, then it's gone.
		ctx:Delay(1.4, function()
			if self.entries[player] == entry then
				self:_removeBall(entry)
			end
		end)
	end
	ctx.Hooks.PlayerLeft = function(player)
		local entry = self.entries[player]
		if entry then
			self:_removeBall(entry)
		end
	end

	ctx:SpawnAll(spots, true)
	for _, entry in self.entries do
		self:_attachRider(entry) -- anyone whose character was already placed before the hook ran
	end

	ctx:SetSharedJSON("Tuning", {
		Accel = TUNING.Accel,
		MaxSpeed = TUNING.MaxSpeed,
		Relief = TUNING.Relief,
		ReliefDrag = TUNING.ReliefDrag,
	})
	ctx:SetSharedJSON("Island", {
		X = origin.X,
		Y = self.top,
		Z = origin.Z,
		R = ISLAND_RADIUS,
		Water = self.waterY,
	})
	ctx:SetStatus(`Players left: {ctx:AliveCount()}`)
end

function BumperBallers:Start()
	local ctx = self.context

	-- Release the balls: players' to their own devices, bots' to the server.
	for player, entry in self.entries do
		local _, humanoid = ctx:GetCharacter(player)
		if humanoid then
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
			humanoid.PlatformStand = true
		end
		if physics then
			entry.Body.Anchored = false
			if typeof(player) == "Instance" then
				entry.ClientDriven = true
				entry.Model:SetAttribute("ClientDriven", true)
				ctx:GiveOwnership(entry.Body, player)
			else
				pcall(entry.Body.SetNetworkOwner, entry.Body, nil)
			end
		end
	end

	-- Bots and stand-ins steer with the same stick a player has (x, z: a world direction, length <= 1).
	ctx:OnAction("Steer", function(player, x, z)
		local entry = self.entries[player]
		if not entry or entry.ClientDriven or entry.Out then
			return
		end
		if type(x) ~= "number" or type(z) ~= "number" or x ~= x or z ~= z then
			return
		end
		local input = Vector3.new(math.clamp(x, -1, 1), 0, math.clamp(z, -1, 1))
		if input.Magnitude > 1 then
			input = input.Unit
		end
		entry.Input = input
	end, { Interval = 0.03 })

	ctx:Delay(BIG_BUMPS_AT, function()
		self.bumpScale = BIG_BUMPS
		ctx:SetShared("BigBumps", true)
		ctx:Announce("💥 BIG BUMPS! 💥", "warning", 2.5)
		ctx:Sound("HazardWarning")
	end)

	local shownStatus = ""
	local sampleClock = 0
	ctx:Heartbeat(function(dt)
		dt = math.min(dt, 0.1)
		sampleClock += dt
		local record = sampleClock >= 1 / 30
		if record then
			sampleClock = 0
		end
		local live = {}
		for _, entry in self.entries do
			if entry.Out or not entry.Model.Parent then
				continue
			end
			self:_step(entry, dt)
			if record then
				table.insert(entry.History, 1, entry.Velocity)
				if #entry.History > HISTORY then
					table.remove(entry.History)
				end
			end
			if entry.Position.Y < self.waterY - OUT_DEPTH or flat(entry.Position - self.center).Magnitude > 600 then
				self:_ringOut(entry)
			else
				table.insert(live, entry)
			end
		end
		self:_bumps(live)
		local status = `Players left: {ctx:AliveCount()}`
		if self.bumpScale > 1 then
			status ..= "  •  💥 BIG BUMPS!"
		end
		if status ~= shownStatus then
			shownStatus = status
			ctx:SetStatus(status)
		end
	end)
end

-- Moves one ball for a frame: reads where a player's ball is, or drives a bot's.
function BumperBallers:_step(entry: Entry, dt: number)
	local body = entry.Body
	if entry.ClientDriven then
		entry.Position = body.Position
		entry.Velocity = body.AssemblyLinearVelocity
		return
	end
	local now = os.clock()
	local drag = if now < entry.ReliefUntil then DRAG * TUNING.ReliefDrag else DRAG
	if physics then
		local velocity = body.AssemblyLinearVelocity
		local mass = body.AssemblyMass
		local _, _, root = self.context:GetCharacter(entry.Player)
		if root and entry.Seat then
			mass += root.AssemblyMass
		end
		entry.Force.Force = (entry.Input * TUNING.Accel - flat(velocity) * drag) * mass
		entry.Position = body.Position
		entry.Velocity = velocity
		self:_face(entry, flat(velocity), dt)
		return
	end
	self:_simulate(entry, dt, drag)
end

-- Turns the rider to face where they roll (or where they steer when nearly still).
function BumperBallers:_face(entry: Entry, velocity: Vector3, dt: number)
	local heading = if velocity.Magnitude > 2 then velocity else entry.Input
	if heading.Magnitude > 0.1 then
		local target = math.atan2(-heading.X, -heading.Z)
		local delta = (target - entry.Yaw + math.pi) % (math.pi * 2) - math.pi
		entry.Yaw += delta * math.min(1, dt * 8)
	end
	if entry.Align then
		entry.Align.CFrame = CFrame.Angles(0, entry.Yaw, 0)
	end
end

-- No-physics servers: integrate the same drive model, fall off the edge, and keep balls apart.
function BumperBallers:_simulate(entry: Entry, dt: number, drag: number)
	local position, velocity = entry.Position, entry.Velocity
	local horizontal = flat(velocity)
	horizontal += (entry.Input * TUNING.Accel - horizontal * drag) * dt
	local vertical = velocity.Y
	local onIsland = flat(position - self.center).Magnitude <= ISLAND_RADIUS and position.Y >= self.restY - 0.5
	if onIsland and position.Y <= self.restY + 0.01 and vertical <= 0 then
		vertical = 0
	else
		vertical -= GRAVITY * dt
	end
	position += (horizontal + Vector3.new(0, vertical, 0)) * dt
	if onIsland and position.Y < self.restY then
		position = Vector3.new(position.X, self.restY, position.Z)
	end
	-- Separate overlapping balls (physics would).
	for _, other in self.entries do
		if other ~= entry and not other.Out then
			local gap = flat(position - other.Position)
			local distance = gap.Magnitude
			if distance > 0.01 and distance < BALL_SIZE then
				position += gap.Unit * (BALL_SIZE - distance) * 0.5
			end
		end
	end
	entry.Position = position
	entry.Velocity = horizontal + Vector3.new(0, vertical, 0)
	-- Roll the ball visibly and carry the rider.
	if horizontal.Magnitude > 0.05 then
		local axis = Vector3.yAxis:Cross(horizontal.Unit)
		entry.Spin = CFrame.fromAxisAngle(axis, horizontal.Magnitude * dt / RADIUS) * entry.Spin
	end
	entry.Model:PivotTo(CFrame.new(position) * entry.Spin)
	self:_face(entry, horizontal, dt)
	local character = entry.Player.Character
	if character and character.Parent then
		character:PivotTo(CFrame.new(position + Vector3.new(0, entry.RiderOffset, 0)) * CFrame.Angles(0, entry.Yaw, 0))
	end
end

-- Pushes a ball by `dv` studs/s: through the owner's device for players, directly for bots.
function BumperBallers:_push(entry: Entry, dv: Vector3, bumper: Entry)
	entry.ReliefUntil = os.clock() + TUNING.Relief
	entry.LastBumper = bumper.Player
	entry.LastBumpAt = os.clock()
	if entry.ClientDriven then
		self.context:Fire(entry.Player, "Bump", dv, TUNING.Relief)
	elseif physics then
		local body = entry.Body
		local mass = body.AssemblyMass
		local _, _, root = self.context:GetCharacter(entry.Player)
		if root and entry.Seat then
			mass += root.AssemblyMass
		end
		body:ApplyImpulse(dv * mass)
	else
		entry.Velocity += dv
	end
end

-- Finds balls that just met and bumps them apart: the faster ball into the other wins.
function BumperBallers:_bumps(live: { Entry })
	local now = os.clock()
	local contact = BALL_SIZE + 1.2 -- a little leeway: the server sees players a moment late
	for i = 1, #live do
		local a = live[i]
		for j = i + 1, #live do
			local b = live[j]
			local gap = b.Position - a.Position
			local distance = flat(gap).Magnitude
			if distance > contact or math.abs(gap.Y) > BALL_SIZE or distance < 0.01 then
				continue
			end
			local key = if a.Index < b.Index then `{a.Index}:{b.Index}` else `{b.Index}:{a.Index}`
			if now < (self.pairCooldown[key] or 0) then
				continue
			end
			local normal = flat(gap).Unit -- from a to b
			-- The strongest closing moment in the last few samples (the bounce may already be over).
			local speedA, speedB, closing = 0, 0, 0
			local samples = math.min(#a.History, #b.History)
			for k = 1, math.max(samples, 1) do
				local va = a.History[k] or a.Velocity
				local vb = b.History[k] or b.Velocity
				local into = flat(va):Dot(normal) - flat(vb):Dot(normal)
				if into > closing then
					closing = into
					speedA = math.max(0, flat(va):Dot(normal))
					speedB = math.max(0, -flat(vb):Dot(normal))
				end
			end
			if closing < CLOSING_MIN then
				continue
			end
			self.pairCooldown[key] = now + PAIR_COOLDOWN
			local scale = self.bumpScale
			local toB = math.min(BUMP_MAX, (BUMP_BASE + BUMP_GAIN * speedA + BUMP_SELF * speedB) * scale)
			local toA = math.min(BUMP_MAX, (BUMP_BASE * 0.7 + BUMP_GAIN * speedB + BUMP_SELF * speedA) * scale)
			local lift = Vector3.new(0, BUMP_LIFT, 0)
			self:_push(b, normal * toB + lift, a)
			self:_push(a, -normal * toA + lift, b)
			local strength = math.clamp(closing / (TUNING.MaxSpeed * 2), 0.2, 1)
			local point = a.Position + normal * RADIUS
			self.context:Fire(nil, "Boing", point, strength, a.Player.UserId, b.Player.UserId)
			self.bumpCount = (self.bumpCount or 0) + 1
		end
	end
end

function BumperBallers:_ringOut(entry: Entry)
	local ctx = self.context
	entry.Out = true
	entry.Force.Force = Vector3.zero
	ctx:Fire(nil, "Splash", Vector3.new(entry.Position.X, self.waterY, entry.Position.Z), entry.Player.UserId)
	-- Whoever bumped them in the last few seconds gets the knock-out.
	local bumper = entry.LastBumper
	if bumper and os.clock() - entry.LastBumpAt < 4 then
		local bumperEntry = self.entries[bumper]
		if bumperEntry then
			bumperEntry.KOs += 1
			ctx:SetScoreText(bumper, if bumperEntry.KOs == 1 then "1 KO" else `{bumperEntry.KOs} KOs`)
		end
	end
	self.ringOuts = (self.ringOuts or 0) + 1
	ctx:Eliminate(entry.Player, "fell")
end

function BumperBallers:Stop()
	-- Everything freezes where it is for the results.
	for _, entry in self.entries do
		entry.Input = Vector3.zero
		if entry.Model.Parent then
			entry.Force.Force = Vector3.zero
			entry.Body.Anchored = true
		end
	end
end

function BumperBallers:Cleanup()
	for _, entry in self.entries do
		self:_detachRider(entry)
	end
	self.entries = {}
end

return BumperBallers

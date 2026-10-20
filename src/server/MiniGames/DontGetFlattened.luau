-- Don't Get Flattened (Survival, 90s): dodge falling anvils, rolling boulders and sweeping mallets.
-- Every hazard is telegraphed: anvils show a red ⚠️ circle, boulders show a red strip along their
-- path, and the mallets are always visible. Hits are checked by distance on the server each frame,
-- so results are deterministic rather than depending on touch events.

local ArenaKit = require(script.Parent.Kit.ArenaKit)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local MiniGame = require(script.Parent.Kit.MiniGame)
local Shapes = require(script.Parent.Parent.World.Shapes)

local DontGetFlattened = MiniGame.Define("DontGetFlattened", { Results = "Survival" })

local SIZE = 110
local HALF = SIZE / 2
local ANVIL_RADIUS = 4.5
local BOULDER_RADIUS = 4
local MALLET_ARM = 22

type Boulder = { model: Model, from: Vector3, to: Vector3, speed: number, travelled: number }
type Mallet = { pivot: Vector3, head: Model, arm: BasePart, angle: number, direction: number }

function DontGetFlattened:Prepare()
	local ctx = self.context
	self.boulders = {} :: { Boulder }
	self.mallets = {} :: { Mallet }
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	ctx.KillY = ctx.Origin.Y - 30
	self.ground = ctx.Origin.Y

	Shapes.Slab(Vector3.new(SIZE, 4, SIZE), 10, {
		Name = "Floor",
		CFrame = ArenaKit.At(ctx, Vector3.new(0, -2, 0)),
		Color = ArenaKit.Colors.Floor,
		Parent = ctx.Arena,
	})
	-- Cheap visual rhythm: a few stripes instead of a tile grid.
	for index = -2, 2 do
		ArenaKit.Decor(ctx, {
			Name = "Stripe",
			Size = Vector3.new(SIZE, 0.1, 6),
			CFrame = ArenaKit.At(ctx, Vector3.new(0, 0.05, index * 22)),
			Color = ArenaKit.Colors.FloorAlt,
		})
	end
	local trim = Shapes.Slab(Vector3.new(SIZE + 1.2, 3.6, SIZE + 1.2), 10.6, {
		Name = "EdgeTrim",
		CFrame = ArenaKit.At(ctx, Vector3.new(0, -2.3, 0)),
		Color = ArenaKit.Colors.Trim,
		Material = Enum.Material.Neon,
		Parent = ctx.Arena,
	})
	trim.CanCollide = false
	-- A soft cloud bank under the floor so the arena reads as floating in the sky.
	Shapes.Custom(
		"CloudBank",
		function(piece)
			local pieces = {}
			for index = 0, 8 do
				local angle = index / 9 * math.pi * 2
				table.insert(
					pieces,
					piece(
						Vector3.one * 34,
						CFrame.new(math.cos(angle) * 34, 0, math.sin(angle) * 34),
						Enum.PartType.Ball
					)
				)
			end
			table.insert(pieces, piece(Vector3.one * 60, CFrame.new(0, -4, 0), Enum.PartType.Ball))
			return pieces
		end,
		Vector3.new(100, 34, 100),
		{
			Name = "Clouds",
			CFrame = ArenaKit.At(ctx, Vector3.new(0, -22, 0)),
			Color = Color3.fromRGB(255, 255, 255),
			Transparency = 0.15,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = ctx.Arena,
		}
	)

	-- Two sweeping mallets on opposite sides.
	for index, x in { -27, 27 } do
		local pivot = (ctx.Origin * CFrame.new(x, 0, 0)).Position
		ArenaKit.Part(ctx, {
			Name = "MalletPost",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(7, 3, 3),
			CFrame = CFrame.new(pivot + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(80, 70, 110),
		})
		local arm = Shapes.Capsule(MALLET_ARM, 1, {
			Name = "MalletArm",
			CFrame = CFrame.new(pivot + Vector3.new(MALLET_ARM / 2, 6.5, 0)),
			Color = Color3.fromRGB(150, 105, 70),
			Material = Enum.Material.Wood,
			CanCollide = false,
			CanQuery = false,
			Parent = ctx.Arena,
		})
		local head = MeshLibrary.Get("MalletHead", { Parent = ctx.Arena })
		local mallet: Mallet = {
			pivot = pivot,
			head = head,
			arm = arm,
			angle = (index - 1) * math.pi,
			direction = if index == 1 then 1 else -1,
		}
		table.insert(self.mallets, mallet)
		self:_placeMallet(mallet)
	end

	ctx:SpawnAll(ArenaKit.SpawnRing(ctx.Origin.Position, 12, #ctx:GetPlayers()), true)
	ctx:SetStatus(`Survivors: {ctx:AliveCount()}`)
end

function DontGetFlattened:_placeMallet(mallet: Mallet)
	local direction = Vector3.new(math.cos(mallet.angle), 0, math.sin(mallet.angle))
	local headPosition = mallet.pivot + direction * MALLET_ARM
	-- The head rolls along the floor, its axis pointing along the arm.
	mallet.head:PivotTo(CFrame.lookAt(headPosition, headPosition + direction) * CFrame.Angles(0, math.rad(90), 0))
	mallet.arm.CFrame = CFrame.lookAt(
		mallet.pivot + direction * (MALLET_ARM / 2) + Vector3.new(0, 6.5, 0),
		mallet.pivot + Vector3.new(0, 6.5, 0)
	) * CFrame.Angles(0, math.rad(90), 0)
end

function DontGetFlattened:_randomPoint(margin: number): Vector3
	local rng = Random.new()
	return (self.context.Origin * CFrame.new(
		rng:NextNumber(-HALF + margin, HALF - margin),
		0,
		rng:NextNumber(-HALF + margin, HALF - margin)
	)).Position
end

function DontGetFlattened:_dropAnvil()
	local ctx = self.context
	local target = self:_randomPoint(6)
	-- Some anvils land near a player (never directly on them) to keep everyone moving.
	local alive = ctx:GetAlivePlayers()
	if #alive > 0 and math.random() < 0.45 then
		local _, _, root = ctx:GetCharacter(alive[math.random(1, #alive)])
		if root then
			local angle = math.random() * math.pi * 2
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (3 + math.random() * 4)
			local flat = Vector3.new(root.Position.X, self.ground, root.Position.Z) + offset
			local localPoint = ctx.Origin:PointToObjectSpace(flat)
			if math.abs(localPoint.X) < HALF - 4 and math.abs(localPoint.Z) < HALF - 4 then
				target = flat
			end
		end
	end

	local warnTime = ArenaKit.Lerp(1.7, 1.05, ctx:Progress())
	local warning = ArenaKit.WarningCircle(ctx, target, ANVIL_RADIUS)
	ctx:Sound("HazardWarning")
	ctx:Delay(warnTime, function()
		warning:Destroy()
		local anvil =
			MeshLibrary.Get("Anvil", { Parent = ctx.Arena, CFrame = CFrame.new(target + Vector3.new(0, 45, 0)) })
		local fallTime = 0.3
		local started = os.clock()
		local connection
		connection = ctx:Track(game:GetService("RunService").Heartbeat:Connect(function()
			local t = math.min(1, (os.clock() - started) / fallTime)
			anvil:PivotTo(CFrame.new(target + Vector3.new(0, 45 * (1 - t * t), 0)))
			if t < 1 then
				return
			end
			connection:Disconnect()
			-- Impact: flatten anyone inside the circle who isn't high above it.
			for _, player in ctx:GetAlivePlayers() do
				local _, _, root = ctx:GetCharacter(player)
				if
					root
					and ArenaKit.FlatDistance(root.Position, target) < ANVIL_RADIUS + 0.6
					and root.Position.Y < self.ground + 7
				then
					ctx:Eliminate(player, "anvil")
				end
			end
			ctx:Delay(1.6, function()
				anvil:Destroy()
			end)
		end))
	end)
end

function DontGetFlattened:_rollBoulder()
	local ctx = self.context
	local rng = Random.new()
	local alongX = rng:NextNumber() < 0.5
	local lane = rng:NextNumber(-HALF + 8, HALF - 8)
	local sign = if rng:NextNumber() < 0.5 then 1 else -1
	local fromLocal = if alongX then Vector3.new(-HALF * sign - 6, 0, lane) else Vector3.new(lane, 0, -HALF * sign - 6)
	local toLocal = if alongX then Vector3.new(HALF * sign + 12, 0, lane) else Vector3.new(lane, 0, HALF * sign + 12)
	local from = (ctx.Origin * CFrame.new(fromLocal)).Position
	local to = (ctx.Origin * CFrame.new(toLocal)).Position

	local stripSize = if alongX
		then Vector3.new(SIZE, 0.2, BOULDER_RADIUS * 2)
		else Vector3.new(BOULDER_RADIUS * 2, 0.2, SIZE)
	local strip = ArenaKit.WarningStrip(
		ctx,
		ArenaKit.At(ctx, Vector3.new(if alongX then 0 else lane, 0.15, if alongX then lane else 0)),
		stripSize
	)
	ctx:Sound("HazardWarning")

	ctx:Delay(ArenaKit.Lerp(1.4, 0.9, ctx:Progress()), function()
		strip:Destroy()
		local model = MeshLibrary.Get("Boulder", { Parent = ctx.Arena, CFrame = CFrame.new(from) })
		table.insert(self.boulders, {
			model = model,
			from = from,
			to = to,
			speed = ArenaKit.Lerp(32, 58, ctx:Progress()),
			travelled = 0,
		})
	end)
end

function DontGetFlattened:Start()
	local ctx = self.context

	ctx:Loop(function()
		if math.random() < 0.62 then
			self:_dropAnvil()
		else
			self:_rollBoulder()
		end
		return ArenaKit.Lerp(2.3, 0.75, ctx:Progress())
	end)

	ctx:Heartbeat(function(dt)
		local alive = ctx:GetAlivePlayers()

		for _, mallet in self.mallets do
			mallet.angle += dt * mallet.direction * ArenaKit.Lerp(0.7, 1.6, ctx:Progress())
			self:_placeMallet(mallet)
			local headPosition = mallet.head:GetPivot().Position
			for _, player in alive do
				local _, _, root = ctx:GetCharacter(player)
				if
					root
					and ArenaKit.FlatDistance(root.Position, headPosition) < 3.6
					and root.Position.Y < self.ground + 6.5
				then
					ctx:Eliminate(player, "mallet")
				end
			end
		end

		for index = #self.boulders, 1, -1 do
			local boulder = self.boulders[index]
			boulder.travelled += boulder.speed * dt
			local total = (boulder.to - boulder.from).Magnitude
			local alpha = boulder.travelled / total
			if alpha >= 1 then
				boulder.model:Destroy()
				table.remove(self.boulders, index)
				continue
			end
			local position = boulder.from:Lerp(boulder.to, alpha)
			local direction = (boulder.to - boulder.from).Unit
			local roll = CFrame.fromAxisAngle(direction:Cross(Vector3.yAxis), -boulder.travelled / BOULDER_RADIUS)
			local center = position + Vector3.new(0, BOULDER_RADIUS, 0)
			-- Rotate about the boulder's center; its pivot sits at the bottom of the rock.
			boulder.model:PivotTo(CFrame.new(center) * roll * CFrame.new(0, -BOULDER_RADIUS, 0))
			for _, player in alive do
				local _, _, root = ctx:GetCharacter(player)
				if root and (root.Position - center).Magnitude < BOULDER_RADIUS + 1.6 then
					ctx:Eliminate(player, "boulder")
				end
			end
		end

		ctx:SetStatus(`Survivors: {#ctx:GetAlivePlayers()}`)
	end)
end

-- Stop/GetResults/Cleanup use the MiniGame defaults: hazards stop by themselves when the round
-- ends (loops and heartbeats check IsRunning), survival results, and the context removes the arena.

return DontGetFlattened

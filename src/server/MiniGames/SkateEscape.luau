-- Skate Escape (Race, 55s, 1-12 players). After Mario Party 2's "Skateboard Scamper": everyone
-- races on a skateboard, pushing to build speed and jumping the obstacles, first to the goal wins.
-- Here twelve lanes run down a long wooden bridge over a lava canyon. PUSH (mash it) kicks you faster,
-- JUMP ollies over crates, striped barriers and gaps in the bridge; miss one and you wipe out for a
-- moment. Boost pads throw you forward. The bridge crumbles into the lava behind the pack at a set
-- pace, so slowpokes fall and are out. Ranking: finish order, then how far you got.
--
-- How it works: the race is simulated on the server with the shared rules in
-- Shared/Logic/SkateCourse (distance, speed, ollies, wipeouts), for players and bots alike. A player's
-- PUSH and JUMP are actions; their own client runs the same rules to move its character at once, so
-- it feels instant, and follows the server's numbers (MG_Racers) when they disagree. A client can only
-- ever ask to push or jump, at a limited rate, so it can't skate faster or teleport ahead: the server's
-- distances decide the finish, the collapse and the results. A jump that arrives just after the
-- server's skater reached an obstacle still counts if it would have cleared it, allowing for ping.
-- Bots skate the same simulation and the server moves their characters; the collapse (animated on
-- clients from the shared schedule MG_Collapse) is checked against everyone's distance here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local SkateCourse = require(ReplicatedStorage.Shared.Logic.SkateCourse)

local MiniGame = require(script.Parent.Kit.MiniGame)
local Scenery = require(script.Parent.Kit.Scenery)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local Shapes = require(script.Parent.Parent.World.Shapes)

local SkateEscape = MiniGame.Define("SkateEscape")

local LANES = 12
local SEGMENT = 24 -- deck pieces are at most this long (each crumbles on its own)
local DECK_WIDTH = 100
local DECK_MESH_LENGTH = 24
local LAVA_DROP = 34
local START_BACK = 36 -- the start pad behind the line
local GOAL_DEPTH = 70

local PUSH_RATE = 12 -- pushes a second the server takes on average ...
local PUSH_BURST = 3 -- ... and how many may arrive at once
local KIND_PROP = { Crate = "SkateCrate", Barrier = "SkateBarrier", Boost = "SkateBoost" }

local rng = Random.new()

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function round(x: number, step: number): number
	return math.floor(x / step + 0.5) * step
end

local function ambient(emitter: ParticleEmitter, parent: Instance)
	emitter.Parent = parent
	CollectionService:AddTag(emitter, "PP_Ambient")
end

-- Stretches a prop along Z (its length) without changing its width or height; MeshParts take any size.
local function stretchZ(model: Model, factor: number)
	if math.abs(factor - 1) < 0.001 then
		return
	end
	local pivot = model:GetPivot()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local relative = pivot:ToObjectSpace(part.CFrame)
			part.Size = Vector3.new(part.Size.X, part.Size.Y, part.Size.Z * factor)
			part.CFrame = pivot * CFrame.new(relative.X, relative.Y, relative.Z * factor) * relative.Rotation
		end
	end
end

-- Arena ------------------------------------------------------------------------------------------

function SkateEscape:_deckPiece(index: number, d0: number, d1: number): Model
	local ctx = self.context
	local origin = self.origin
	local model = Build.Model(`Seg{index}`) -- parented once its distances are set (clients read them)
	model:SetAttribute("D0", d0)
	model:SetAttribute("D1", d1)
	local length = d1 - d0
	local middle = origin + Vector3.new(0, 0, -(d0 + d1) / 2)
	local deck = MeshLibrary.Get("SkateDeck", {
		CFrame = CFrame.new(middle - Vector3.new(0, 2, 0)),
		Parent = model,
	})
	stretchZ(deck, length / DECK_MESH_LENGTH)
	for _, side in { -1, 1 } do
		local rail = MeshLibrary.Get("SkateRail", {
			CFrame = CFrame.new(middle + Vector3.new(side * (DECK_WIDTH / 2 - 0.6), 0, 0)),
			Parent = model,
		})
		stretchZ(rail, length / DECK_MESH_LENGTH)
		-- Timber piles down into the lava.
		if length > 10 then
			Build.Decor({
				Name = "Pile",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(LAVA_DROP + 2, 2.2, 2.2),
				CFrame = CFrame.new(origin + Vector3.new(side * 44, -2.4 - (LAVA_DROP + 2) / 2, -(d0 + 1.5)))
					* CFrame.Angles(0, 0, math.rad(90)),
				Color = rgb(78, 52, 36),
				Material = Enum.Material.Wood,
				Parent = model,
			})
		end
	end
	model.PrimaryPart = deck.PrimaryPart
	model.Parent = ctx.Arena
	return model
end

function SkateEscape:_torch(parent: Instance, position: Vector3, light: boolean)
	local torch = MeshLibrary.Get("SkateTorch", { CFrame = CFrame.new(position), Parent = parent })
	local flame = Build.Decor({
		Name = "Flame",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.1, 1.1, 1.1),
		CFrame = CFrame.new(position + Vector3.new(0, 4.1, 0)),
		Color = rgb(255, 150, 50),
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		Parent = torch,
	})
	if light then
		Build.Light(flame, rgb(255, 140, 60), 26, 1.6)
	end
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(rgb(255, 200, 90), rgb(255, 90, 30))
	fire.LightEmission = 1
	fire.Size = NumberSequence.new(1.1, 0.2)
	fire.Lifetime = NumberRange.new(0.4, 0.7)
	fire.Speed = NumberRange.new(2, 4)
	fire.Rate = 14
	fire.SpreadAngle = Vector2.new(10, 10)
	fire.EmissionDirection = Enum.NormalId.Top
	ambient(fire, flame)
end

function SkateEscape:_buildArena()
	local ctx = self.context
	local origin = self.origin
	local length = SkateCourse.Length
	local arena = ctx.Arena

	-- The canyon: a lava river under the whole bridge, rock spires along both sides and volcanoes ahead.
	local lake = origin + Vector3.new(0, -LAVA_DROP, -length / 2 + 40)
	Scenery.LavaLake(ctx, lake, 2040)
	Scenery.Volcano(ctx, lake + Vector3.new(30, -2, -length / 2 - 380), origin, 3.2)
	Scenery.Volcano(ctx, lake + Vector3.new(-420, -2, -length / 2 - 200), origin, 2.1)
	Scenery.Volcano(ctx, lake + Vector3.new(400, -2, -length / 2 - 60), origin, 1.7)
	Scenery.Volcano(ctx, lake + Vector3.new(-520, -2, 260), origin, 1.5)
	Scenery.Volcano(ctx, lake + Vector3.new(560, -2, 420), origin, 1.9)
	for _, side in { -1, 1 } do
		local z = 140
		while z > -length - 160 do
			local near = rng:NextNumber() < 0.35
			local x = side * (if near then rng:NextNumber(68, 90) else rng:NextNumber(105, 190))
			MeshLibrary.Get("Spire", {
				Scale = if near then rng:NextNumber(0.9, 1.5) else rng:NextNumber(1.6, 3.4),
				CFrame = CFrame.new(Vector3.new(origin.X + x, lake.Y - 1, origin.Z + z))
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = arena,
			})
			z -= rng:NextNumber(38, 70)
		end
	end

	-- The bridge, cut into pieces that crumble one by one, with gaps where the obstacles say.
	local cuts = {}
	for _, o in self.obstacles do
		if o.Kind == "Gap" then
			table.insert(cuts, { o.D - o.Len / 2, o.D + o.Len / 2 })
		end
	end
	local pieces = {}
	local cursor = 0
	local cutIndex = 1
	while cursor < length - 0.01 do
		local cut = cuts[cutIndex]
		local stop = math.min(length, cursor + SEGMENT)
		if cut and stop > cut[1] then
			stop = cut[1]
		end
		if stop - cursor > 0.5 then
			table.insert(pieces, self:_deckPiece(#pieces + 1, cursor, stop))
		end
		cursor = stop
		if cut and cursor >= cut[1] - 0.01 then
			cursor = cut[2]
			cutIndex += 1
			-- A raised curb of yellow and black blocks on both lips, so the drop reads at speed.
			local blocks = 14
			local width = (DECK_WIDTH - 2) / blocks
			for side, lip in { cut[1] - 0.8, cut[2] + 0.8 } do
				for block = 0, blocks - 1 do
					local curb = Build.Decor({
						Name = "GapLip",
						Size = Vector3.new(width, 0.3, 1.6),
						CFrame = CFrame.new(
							origin + Vector3.new(-(DECK_WIDTH - 2) / 2 + (block + 0.5) * width, 0.17, -lip)
						),
						Color = if (block + side) % 2 == 0 then rgb(255, 200, 40) else rgb(34, 28, 34),
						Material = if (block + side) % 2 == 0 then Enum.Material.Neon else Enum.Material.Metal,
						Parent = arena,
					})
					curb:SetAttribute("At", lip)
				end
			end
			-- A warning banner across the deck well before the gap: it stands up, so it shows from far.
			local at = cut[1] - 28
			local banner = Build.Decor({
				Name = "GapLip",
				Size = Vector3.new(DECK_WIDTH - 4, 3.4, 0.5),
				CFrame = CFrame.new(origin + Vector3.new(0, 16.1, -at)),
				Color = rgb(34, 28, 34),
				Material = Enum.Material.Metal,
				Parent = arena,
			})
			banner:SetAttribute("At", at)
			Build.SurfaceText(banner, Enum.NormalId.Back, "⚠  GAP AHEAD  •  JUMP!  ⚠", {
				PixelsPerStud = 12,
				TextColor3 = rgb(255, 210, 60),
				TextStrokeTransparency = 0.4,
			})
			for _, y in { 14.15, 18.05 } do
				local trim = Build.Decor({
					Name = "GapLip",
					Size = Vector3.new(DECK_WIDTH - 4, 0.3, 0.6),
					CFrame = CFrame.new(origin + Vector3.new(0, y, -at)),
					Color = rgb(255, 200, 40),
					Material = Enum.Material.Neon,
					Parent = arena,
				})
				trim:SetAttribute("At", at)
			end
			for _, sideX in { -1, 1 } do
				local post = Build.Decor({
					Name = "GapLip",
					Size = Vector3.new(0.8, 18.2, 0.8),
					CFrame = CFrame.new(origin + Vector3.new(sideX * (DECK_WIDTH / 2 - 1.5), 9.1, -at)),
					Color = rgb(52, 44, 50),
					Material = Enum.Material.Metal,
					Parent = arena,
				})
				post:SetAttribute("At", at)
			end
		end
	end
	self.pieces = pieces
	local function pieceAt(d: number): Instance
		for _, piece in pieces do
			if d >= piece:GetAttribute("D0") and d <= piece:GetAttribute("D1") then
				return piece
			end
		end
		return arena
	end
	-- Gap lips belong to the deck piece they sit on, so they fall with it.
	for _, lip in arena:GetChildren() do
		if lip.Name == "GapLip" then
			lip.Parent = pieceAt(lip:GetAttribute("At"))
		end
	end

	-- Torches along both rails, lit every other one.
	local torchIndex = 0
	for index, piece in pieces do
		if index % 3 == 0 then
			torchIndex += 1
			local d = (piece:GetAttribute("D0") + piece:GetAttribute("D1")) / 2
			for _, side in { -1, 1 } do
				self:_torch(piece, origin + Vector3.new(side * (DECK_WIDTH / 2 - 0.6), 0, -d), torchIndex % 2 == 1)
			end
		end
	end

	-- Obstacles: the same thing at the same distance in every lane.
	for _, o in self.obstacles do
		local prop = KIND_PROP[o.Kind]
		if not prop then
			continue
		end
		local parent = pieceAt(o.D)
		for lane = 1, LANES do
			local x = SkateCourse.LaneX(lane, LANES)
			MeshLibrary.Get(prop, {
				CFrame = CFrame.new(origin + Vector3.new(x, 0, -o.D)),
				Parent = parent,
			})
		end
	end

	-- The start pad (it crumbles first), with the start gate and lane numbers.
	local start = Build.Model("Seg0")
	start:SetAttribute("D0", -START_BACK)
	start:SetAttribute("D1", 0)
	local pad = Shapes.Slab(Vector3.new(DECK_WIDTH + 24, 5, START_BACK), 2, {
		Name = "StartPad",
		CFrame = CFrame.new(origin + Vector3.new(0, -2.5, START_BACK / 2)),
		Color = rgb(96, 84, 92),
		Material = Enum.Material.Slate,
		Parent = start,
	})
	start.PrimaryPart = pad
	start.Parent = arena
	MeshLibrary.Get("SkateArch", {
		CFrame = CFrame.new(origin + Vector3.new(0, 0, 5)),
		Colors = { Dark = rgb(40, 170, 90), Pennant = rgb(80, 220, 120) },
		Parent = start,
	})
	Build.Decor({
		Name = "StartLine",
		Size = Vector3.new(DECK_WIDTH - 4, 0.08, 1),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.05, 0.5)),
		Color = rgb(250, 250, 250),
		Parent = start,
	})
	for lane = 1, LANES do
		local tile = Build.Decor({
			Name = "LaneNumber",
			Size = Vector3.new(5, 0.08, 5),
			CFrame = CFrame.new(origin + Vector3.new(SkateCourse.LaneX(lane, LANES), 0.05, 9)),
			Color = SkateCourse.LaneColors[lane],
			Parent = start,
		})
		Build.SurfaceText(tile, Enum.NormalId.Top, tostring(lane), {
			PixelsPerStud = 24,
			TextColor3 = rgb(30, 24, 40),
			TextStrokeTransparency = 1,
			Font = Enum.Font.FredokaOne,
		})
	end
	table.insert(pieces, 1, start)

	-- The goal: a stone landing that never falls, with the finish line and arch.
	Shapes.Slab(Vector3.new(DECK_WIDTH + 24, 8, GOAL_DEPTH), 2, {
		Name = "Goal",
		CFrame = CFrame.new(origin + Vector3.new(0, -4, -length - GOAL_DEPTH / 2)),
		Color = rgb(110, 98, 104),
		Material = Enum.Material.Slate,
		Parent = arena,
	})
	Build.Part({
		Name = "GoalPillar",
		Size = Vector3.new(DECK_WIDTH, LAVA_DROP, GOAL_DEPTH - 8),
		CFrame = CFrame.new(origin + Vector3.new(0, -8 - LAVA_DROP / 2, -length - GOAL_DEPTH / 2)),
		Color = rgb(70, 56, 62),
		Material = Enum.Material.Basalt,
		Parent = arena,
	})
	MeshLibrary.Get("SkateArch", {
		CFrame = CFrame.new(origin + Vector3.new(0, 0, -length - 6)),
		Parent = arena,
	})
	-- The finish line: a checkerboard of black and white tiles side by side (none overlap).
	local squares = 24
	local tile = (DECK_WIDTH - 4) / squares
	for index = 0, squares * 2 - 1 do
		local column = index % squares
		local row = index // squares
		Build.Decor({
			Name = "Checker",
			Size = Vector3.new(tile, 0.12, 2),
			CFrame = CFrame.new(
				origin + Vector3.new(-(DECK_WIDTH - 4) / 2 + (column + 0.5) * tile, 0.08, -length - 1 - row * 2)
			),
			Color = if (column + row) % 2 == 0 then rgb(28, 28, 34) else rgb(250, 250, 250),
			Parent = arena,
		})
	end
	for _, side in { -1, 1 } do
		for _, z in { 20, 45 } do
			self:_torch(arena, origin + Vector3.new(side * (DECK_WIDTH / 2 + 4), 0, -length - z), true)
		end
	end
end

-- Round ------------------------------------------------------------------------------------------

function SkateEscape:_attachBoard(player: any, character: Model)
	local racer = self.racers[tostring(player.UserId)]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not racer or not humanoid or not root then
		return
	end
	local old = character:FindFirstChild("Skateboard")
	if old then
		old:Destroy()
	end
	local board = MeshLibrary.Get("SkateBoard", {
		Colors = { Deck = SkateCourse.LaneColors[racer.Lane] },
		CFrame = root.CFrame,
	})
	board.Name = "Skateboard"
	local boardRoot = MeshLibrary.Assemble(board, true)
	local weld = Instance.new("Weld")
	weld.Name = "BoardWeld"
	weld.Part0 = root
	weld.Part1 = boardRoot
	weld.C0 = CFrame.new(0, -SkateCourse.RootHeight(humanoid, root), 0) * CFrame.Angles(0, math.rad(90), 0)
	weld.C1 = boardRoot.CFrame:ToObjectSpace(board:GetPivot())
	weld.Parent = boardRoot
	board.Parent = character
end

function SkateEscape:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - LAVA_DROP - 8
	self.origin = ctx.Origin.Position
	self.obstacles = SkateCourse.Generate(rng)
	self.racers = {} :: { [string]: any }
	self.finished = 0
	self:_buildArena()

	-- Everyone gets a lane; with fewer than twelve the middle lanes fill first.
	local players = ctx:GetPlayers()
	local order = {}
	for index = 1, #players do
		order[index] = index
	end
	for index = #order, 2, -1 do
		local other = rng:NextInteger(1, index)
		order[index], order[other] = order[other], order[index]
	end
	local first = math.floor((LANES - math.min(#players, LANES)) / 2) + 1
	local lanes = {}
	local points = {}
	for index, player in players do
		local lane = math.min(LANES, first + order[index] - 1)
		local racer = SkateCourse.NewRacer() :: any
		racer.Player = player
		racer.Lane = lane
		racer.IsBot = BotRegistry.IsBot(player)
		racer.Leeway = 0
		self.racers[tostring(player.UserId)] = racer
		lanes[tostring(player.UserId)] = lane
		local x = SkateCourse.LaneX(lane, LANES)
		points[index] = SkateCourse.StanceCFrame(self.origin, x, 0, 0, 0)
	end

	local obstacles = {}
	for _, o in self.obstacles do
		table.insert(obstacles, { K = o.Kind, D = o.D, N = o.Len })
	end
	ctx:SetSharedJSON("Race", {
		O = { self.origin.X, self.origin.Y, self.origin.Z },
		Length = SkateCourse.Length,
		Lanes = LANES,
		Obstacles = obstacles,
		Lane = lanes,
	})

	ctx.Hooks.CharacterReady = function(player, character)
		self:_attachBoard(player, character)
	end
	ctx.Hooks.PlayerLeft = function(player)
		self.racers[tostring(player.UserId)] = nil
	end
	-- Out some other way (a reset, say): stop simulating them and count them as fallen.
	ctx.Hooks.Eliminated = function(player)
		local racer = self.racers[tostring(player.UserId)]
		if racer and not racer.Done then
			racer.Out = true
			racer.OutAt = ctx:Now()
			racer.Done = true
			racer.Pending = nil
		end
	end
	ctx:SpawnAll(points, true)
	-- Bots wait on their boards in the skating stance (held still until GO).
	for _, racer in self.racers do
		if racer.IsBot then
			local _, _, root = ctx:GetCharacter(racer.Player)
			if root then
				root.Anchored = true
				self:_moveBot(racer, ctx:Now())
			end
		end
	end
	self:_share() -- the progress bar shows every lane during the countdown
	self.status = nil
	ctx:SetStatus("Get ready to PUSH!")
end

function SkateEscape:_ping(player: any): number
	if BotRegistry.IsBot(player) then
		return 0
	end
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and type(ping) == "number" then math.clamp(ping, 0, 0.3) else 0.1
end

function SkateEscape:_wipe(racer, event)
	-- As of the moment of the hit, however long the ping allowance held it.
	SkateCourse.Apply(racer, event, self.obstacles, event.At)
	racer.Pending = nil
	self.context:Fire(nil, "Wipe", tostring(racer.Player.UserId), event.Kind, event.Index)
end

function SkateEscape:Start()
	local ctx = self.context
	local now = ctx:Now()
	self.startAt = now
	self.collapse = SkateCourse.NewCollapse(now)
	ctx:SetSharedJSON("Collapse", self.collapse)
	for _, racer in self.racers do
		if racer.IsBot then
			local _, _, root = ctx:GetCharacter(racer.Player)
			if root then
				root.Anchored = false
			end
		end
	end

	-- Pushes are capped by a small bucket (PUSH_RATE a second on average, a few at once) rather than
	-- a fixed gap, so taps the network bunched together aren't dropped.
	ctx:OnAction("Push", function(player)
		local racer = self.racers[tostring(player.UserId)]
		if not racer then
			return
		end
		local clock = os.clock()
		racer.Tokens =
			math.min(PUSH_BURST, (racer.Tokens or PUSH_BURST) + (clock - (racer.TokenAt or clock)) * PUSH_RATE)
		racer.TokenAt = clock
		if racer.Tokens < 1 then
			return
		end
		racer.Tokens -= 1
		racer.Leeway = 0.06 + self:_ping(player)
		SkateCourse.Push(racer, ctx:Now())
	end, { Interval = 0.04 })

	ctx:OnAction("Jump", function(player)
		local racer = self.racers[tostring(player.UserId)]
		if not racer then
			return
		end
		local at = ctx:Now()
		racer.Leeway = 0.06 + self:_ping(player)
		local pending = racer.Pending
		if pending then
			-- The skater already reached the obstacle here; would a jump pressed up to `Leeway` ago
			-- (and not before the last landing) have cleared it?
			local start = math.max(at - racer.Leeway, racer.AirEnd or -math.huge)
			local o = self.obstacles[pending.Event.Index]
			if o and start <= at and SkateCourse.WouldClear(o, start, pending.Event.At, pending.Speed) then
				racer.Pending = nil
				racer.Air = start
				racer.AirEnd = start + SkateCourse.AirTime
				return
			end
		end
		SkateCourse.Jump(racer, at)
	end, { Interval = 0.15 })

	-- Small steps, so a server hitch doesn't cost anyone distance while the collapse runs on.
	ctx:Heartbeat(function(dt)
		local now = ctx:Now()
		local left = math.min(dt, 0.5)
		while left > 1e-4 do
			local h = math.min(left, 0.05)
			left -= h
			self:_tick(h, now - left)
		end
	end)
	ctx:Loop(function()
		self:_share()
		return 0.12
	end)
end

function SkateEscape:_moveBot(racer, now: number)
	local character, humanoid, root = self.context:GetCharacter(racer.Player)
	if not character or not humanoid or not root then
		return
	end
	local d, lift, tumble, drop = SkateCourse.Pose(racer, now)
	if racer.Out then
		local t = now - (racer.OutAt or now)
		drop = math.min(60, 0.5 * 70 * t * t)
		tumble = t * 1.5
	end
	if not humanoid.PlatformStand then
		humanoid.PlatformStand = true -- the server moves this skater; the humanoid mustn't try to stand
	end
	local x = SkateCourse.LaneX(racer.Lane, LANES)
	root.CFrame =
		SkateCourse.StanceCFrame(self.origin, x, d, SkateCourse.RootHeight(humanoid, root) + lift - drop, tumble)
	root.AssemblyLinearVelocity = Vector3.new(0, 0, -racer.V)
end

function SkateEscape:_tick(dt: number, now: number)
	local ctx = self.context
	if not ctx:IsRunning() then
		return
	end
	local length = SkateCourse.Length
	local front = SkateCourse.CollapseAt(self.collapse, now)
	local everyoneDone = true
	local crossed = {}
	for key, racer in self.racers do
		local player = racer.Player
		if not ctx:State(player) then
			self.racers[key] = nil
			continue
		end
		if racer.Out then
			if racer.IsBot and now - racer.OutAt < 1.4 then
				self:_moveBot(racer, now)
			end
			continue
		end
		if racer.Place then
			-- Finished: coast to a stop on the goal landing.
			racer.V = math.max(0, racer.V - (8 + 0.6 * racer.V) * dt)
			racer.D = math.min(racer.D + racer.V * dt, length + SkateCourse.RunOut)
			racer.Air = nil
			if racer.IsBot then
				self:_moveBot(racer, now)
			end
			continue
		end
		everyoneDone = false
		if racer.Done then
			continue -- crossed the line this step, placed below
		end
		local pending = racer.Pending
		if pending and now >= pending.Until then
			self:_wipe(racer, pending.Event)
		end
		local event = SkateCourse.Step(racer, self.obstacles, now, dt)
		if event then
			if event.Kind == "Boost" then
				SkateCourse.Apply(racer, event, self.obstacles, now)
				ctx:Fire(nil, "Boost", key)
			elseif racer.Leeway > 0 and not racer.Pending then
				racer.Pending = { Event = event, Until = now + racer.Leeway, Speed = math.max(racer.V, 1) }
			else
				self:_wipe(racer, event)
			end
		end
		if racer.D >= length then
			-- The exact moment they crossed, so two finishers in one step are ranked fairly.
			racer.Done = true
			racer.Wipe = nil
			racer.Pending = nil
			table.insert(crossed, { Key = key, Racer = racer, At = now - (racer.D - length) / math.max(racer.V, 1) })
		elseif racer.D < front then
			racer.Out = true
			racer.OutAt = now
			racer.Done = true
			racer.Pending = nil
			ctx:Fire(nil, "Out", key)
			ctx:SetScoreText(player, `Fell at {math.floor(math.max(0, racer.D) / length * 100)}%`)
			ctx:Eliminate(player, "collapse")
		end
		if racer.IsBot then
			self:_moveBot(racer, now)
		end
	end
	table.sort(crossed, function(a, b)
		return a.At < b.At
	end)
	for _, entry in crossed do
		local racer = entry.Racer
		self.finished += 1
		racer.Place = self.finished
		racer.Time = entry.At - self.startAt
		local player = racer.Player
		ctx:SetScoreText(player, `{SkateCourse.Ordinal(racer.Place)} • {string.format("%.1f", racer.Time)}s`)
		ctx:Fire(nil, "Finish", entry.Key, racer.Place)
		if racer.Place == 1 then
			ctx:Announce(`🏁 {player.DisplayName} reached the goal first!`, "success", 3)
		end
	end
	if everyoneDone and not self.ending and next(self.racers) ~= nil then
		self.ending = true
		ctx:Delay(2, function()
			ctx:End("AllFinished")
		end)
	end
end

-- Everyone's race for clients (progress bar, other skaters' kicks and wipeouts, your own corrections).
function SkateEscape:_share()
	local ctx = self.context
	local now = ctx:Now()
	local list = {}
	local home, skating = 0, 0
	for key, racer in self.racers do
		local entry: { [string]: any } = {
			L = racer.Lane,
			D = round(racer.D, 0.01),
			V = round(racer.V, 0.01),
			P = racer.Pushes,
			T = round(now, 0.001),
		}
		if racer.Air then
			entry.A = round(racer.Air, 0.001)
		end
		if racer.Pending then
			entry.PW = 1 -- a hit the server is still deciding on (ping allowance)
		end
		if racer.Wipe and now < racer.Wipe then
			entry.W = round(racer.Wipe, 0.001)
			entry.WA = round(racer.WipeAt or now, 0.001)
			entry.WK = racer.WipeKind
			entry.FD = racer.FallD and round(racer.FallD, 0.01)
		end
		if racer.Place then
			entry.F = racer.Place
			home += 1
		elseif racer.Out then
			entry.O = 1
		else
			skating += 1
			if self.startAt then
				ctx:SetScoreText(racer.Player, `{math.floor(math.clamp(racer.D / SkateCourse.Length, 0, 1) * 100)}%`)
			end
		end
		-- The live standings sort by score: progress in percent, finishers above everyone by place.
		local state = self.startAt and ctx:State(racer.Player)
		if state then
			local score = if racer.Place
				then 200 - racer.Place
				else math.floor(math.clamp(racer.D / SkateCourse.Length, 0, 1) * 100)
			if score ~= state.Score then
				ctx:AddScore(racer.Player, score - state.Score)
			end
		end
		list[key] = entry
	end
	ctx:SetSharedJSON("Racers", list)
	local status = if home > 0
		then `🏁 {home} home  •  🛹 {skating} skating`
		else `🛹 {skating} skating  •  outrun the collapse!`
	if status ~= self.status then
		self.status = status
		ctx:SetStatus(status)
	end
end

function SkateEscape:GetResults()
	local ctx = self.context
	local entries = {}
	for _, player in ctx:GetPlayers() do
		local racer = self.racers[tostring(player.UserId)]
		if not racer then
			continue
		end
		local percent = math.floor(math.clamp(racer.D / SkateCourse.Length, 0, 1) * 100)
		if racer.Place then
			table.insert(entries, {
				Player = player,
				Rank = 1e6 - racer.Place,
				ScoreText = `{SkateCourse.Ordinal(racer.Place)} • {string.format("%.1f", racer.Time or 0)}s`,
				BestScore = 100,
			})
		else
			table.insert(entries, {
				Player = player,
				Rank = math.clamp(racer.D, 0, SkateCourse.Length),
				ScoreText = if racer.Out then `Fell at {percent}%` else `{percent}% of the way`,
				BestScore = percent,
			})
		end
	end
	return { Entries = entries }
end

return SkateEscape

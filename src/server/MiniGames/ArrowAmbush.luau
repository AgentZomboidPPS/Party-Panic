-- Arrow Ambush (Versus, 35s, 2-12 players). Mechanics after "Archer-ival": one ARCHER (two with
-- six or more players) stands on a stone tower above a castle courtyard with a bow and endless
-- arrows; everyone else is a RUNNER in the courtyard below. Archers click or tap where to shoot;
-- runners dodge, and hide behind the big target boards that roll slowly back and forth on rails.
-- One arrow tags a runner. Archers win by tagging every runner; runners win if anyone is still
-- untagged when time runs out. Like the bonus panels in the original, an arrow that hits a target
-- board is blocked, but scores the archer the board's number (+1, +2 or +3; at most 5 board points
-- each, so shooting the boards never pays like tagging a runner).
--
-- The server owns everything. The boards follow a schedule shared with every client (MG_Layout:
-- each board's rail and sine motion from one start time), so clients move them smoothly and the
-- server knows exactly where each one is. A shot (ctx:OnAction "Shoot") is checked (archer, alive,
-- cooldown, inside the courtyard), then the server plans the arrow's whole flight: a shallow arc
-- from the bow to the spot, cut short by the first board it passes through. Clients get the plan
-- (event "Arrow") and draw it; the landing ring shows where it comes down from the moment it's
-- fired. When it lands the server checks every runner's distance to the spot, a little later for
-- runners with more lag, so a dodge that looked clean on your screen counts. Bots are judged by
-- the same code, so arrows and boards treat them exactly like players.
--
-- Hit judging (the hitbox pass; owner: "We need to fine tune some of the hitboxes. the
-- precision games will feel super bad if we dont."): being tagged is the bad thing, so it only
-- happens when it clearly looked like one on the runner's own screen.
--  * The red ring is drawn RING_RADIUS (3.5) wide and a runner is tagged only when their middle is
--    inside HIT_RADIUS (3): at least half a stud inside the ring, most of the body in it. (It used
--    to be drawn at 3, so a runner straddling the line, half their body outside, was tagged.)
--  * Each runner is checked twice: when their own screen showed the landing (half their ping
--    after it: their moves reach us one way) and 0.1 s later (allowing for replication). Only
--    inside both times is a tag. Before, one check a full ping later could tag a runner who was
--    clearly outside when it landed on their screen and then walked over the spot.
--  * Boards block arrows that visibly touch them: the frame is 3.78 studs either side and 8.14
--    high (TargetBoard mesh, on 0.46 rails), plus the arrowhead's 0.15. It was 3.6 and 8, so an
--    arrow could clip a board's edge on screen and still tag the runner hiding behind it.

local MiniGame = require(script.Parent.Kit.MiniGame)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local Shapes = require(script.Parent.Parent.World.Shapes)

local ArrowAmbush = MiniGame.Define("ArrowAmbush")

ArrowAmbush.ARCHERS = "Archers"
ArrowAmbush.RUNNERS = "Runners"

local X_HALF = 25 -- the runners' courtyard: x in [-X_HALF, X_HALF]
local Z_MIN = -15 -- ... and z in [Z_MIN, Z_MAX] (the tower is north, at -z)
local Z_MAX = 25
local TOWER_Z = -26
local TOWER_TOP = 16 -- the archers' deck height above the courtyard floor
local WALL = 2.4 -- low courtyard wall height (an invisible barrier rises above it)
ArrowAmbush.RAIL_TOP = 0.42 -- the boards' wheels run on rails this high above the floor

-- Seconds between an archer's shots: quicker when each archer has more runners to chase.
function ArrowAmbush.Cooldown(runnersPerArcher: number): number
	return math.clamp(1 - 0.07 * (runnersPerArcher - 1), 0.68, 0.95)
end
ArrowAmbush.HIT_RADIUS = 3 -- a runner whose middle is this close to where an arrow lands is tagged
-- The landing ring's drawn radius: a tag needs the runner's middle half a stud inside it, so a runner
-- half outside the line (R15 is about 2 wide) isn't tagged.
ArrowAmbush.RING_RADIUS = ArrowAmbush.HIT_RADIUS + 0.5
local SHOVE_RADIUS = 5.5 -- near misses get a little shove
local JUDGE_SPREAD = 0.1 -- a tag needs the runner inside at their screen's landing and this long after
-- Half a target board's width (what blocks arrows): the visible frame (3.78) plus the arrowhead.
ArrowAmbush.BOARD_HALF = 3.93
-- Boards block arrows below this height above the floor: the frame's top (0.46 rails + 7.68) plus
-- the arrowhead.
ArrowAmbush.BOARD_HEIGHT = 8.3
local SAMPLES = 48 -- flight samples when looking for a board in the way
local BOARD_CAP = 5 -- the most board points one archer can score
local SPAWN_LIFT = 3 -- an archer's root stands this high over their spot on the deck

local rng = Random.new()

export type Board = { C: number, Z: number, A: number, W: number, P: number, V: number }
export type Arrow = {
	Id: number,
	By: number,
	From: Vector3,
	To: Vector3,
	T0: number,
	T1: number, -- when it lands, or when it hits a board
	Flight: number, -- full flight time to the target (if nothing were in the way)
	Arc: number,
	Board: number, -- index of the board that stopped it, 0 if none
	Stop: Vector3, -- where it stops
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Flight time and arc height of a shot covering `distance` studs.
function ArrowAmbush.Flight(distance: number): (number, number)
	return 0.28 + distance / 105, 1.5 + distance * 0.04 -- keep in step with the client half
end

-- Where an arrow is `s` of the way through its flight (0..1).
function ArrowAmbush.PointAt(from: Vector3, to: Vector3, arc: number, s: number): Vector3
	return from:Lerp(to, s) + Vector3.new(0, 4 * arc * s * (1 - s), 0)
end

-- A board's x at server time `t` (it slides along its rail on a sine).
function ArrowAmbush.BoardX(board: Board, t0: number, t: number): number
	return board.C + board.A * math.sin(board.W * (t - t0) + board.P)
end

function ArrowAmbush:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 25
	local origin = ctx.Origin.Position
	self.origin = origin
	self.floorY = origin.Y
	self.role = {} :: { [Player]: string }
	self.tagged = {} :: { [Player]: boolean }
	self.tags = {} :: { [Player]: number }
	self.bonus = {} :: { [Player]: number }
	self.nextShot = {} :: { [Player]: number }
	self.spots = {} :: { [Player]: CFrame }
	self.arrows = {} :: { Arrow }
	self.arrowId = 0
	self.track = {} :: { [Player]: { Pos: Vector3, Vel: Vector3, T: number } }
	self.runnerCount = 0
	self.coverClaims = {} :: { [any]: number } -- runner bots: the board each is hiding behind
	self.ended = false
	self.shownRunners = 0

	self:_buildArena()

	-- Roles: one archer under six players, two from six on; everyone else runs.
	local players = ctx:GetPlayers()
	for index = #players, 2, -1 do
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	-- (A lone player in Studio is the archer, so they can try the bow; bots fill real rounds.)
	local archerCount = if #players >= 6 then 2 else 1
	local archers, runners = {}, {}
	for index, player in players do
		if index <= archerCount then
			table.insert(archers, player)
		else
			table.insert(runners, player)
		end
	end
	self.runnerCount = #runners
	self.cooldown = ArrowAmbush.Cooldown(#runners / math.max(1, #archers))

	local spawnFor = {}
	for index, player in archers do
		local x = if #archers == 1 then 0 else (index - 1.5) * 6
		local position = origin + Vector3.new(x, TOWER_TOP, TOWER_Z + 1.5)
		spawnFor[player] = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
		self.spots[player] = spawnFor[player]
		self.role[player] = "Archer"
		ctx:SetTeam(player, ArrowAmbush.ARCHERS)
		ctx:SetPlayerShared(player, "Role", "Archer")
		self.tags[player] = 0
		self.bonus[player] = 0
		ctx:SetScoreText(player, "0 tags")
	end
	local columns = math.max(1, math.min(5, #runners))
	for index, player in runners do
		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		local x = (column - (columns - 1) / 2) * 8.5 + (if row % 2 == 1 then 4 else 0)
		-- Rows at z 22 and 18: clear of the back board row's track (z 14, 2.5 deep) with 3 rows.
		local position = origin + Vector3.new(x, 0, Z_MAX - 3 - row * 4)
		spawnFor[player] = CFrame.lookAt(position, position - Vector3.new(0, 0, 1))
		self.role[player] = "Runner"
		ctx:SetTeam(player, ArrowAmbush.RUNNERS)
		ctx:SetPlayerShared(player, "Role", "Runner")
		ctx:SetScoreText(player, "Running")
	end
	local ordered = {}
	for _, player in ctx:GetPlayers() do
		table.insert(ordered, spawnFor[player] or spawnFor[runners[1]] or CFrame.new(origin))
	end
	ctx:SpawnAll(ordered, true)

	ctx:ShareTemplate("AmbushArrow", MeshLibrary.Get("AmbushArrow"))
	ctx:ShareTemplate("AmbushBow", MeshLibrary.Get("AmbushBow"))
	ctx:ShareTemplate("TargetBoard", MeshLibrary.Get("TargetBoard"))

	-- Each archer's bow point base (their spot on the deck), so the client's aim path starts where
	-- the server's flight plan does.
	local spots = {}
	for player, spot in self.spots do
		local base = spot.Position + Vector3.new(0, SPAWN_LIFT, 0)
		spots[tostring(player.UserId)] = { base.X, base.Y, base.Z }
	end
	local boards = {}
	for _, board in self.boards do
		table.insert(boards, { C = board.C, Z = board.Z, A = board.A, W = board.W, P = board.P, V = board.V })
	end
	ctx:SetSharedJSON("Layout", {
		Floor = self.floorY,
		Origin = { origin.X, origin.Y, origin.Z },
		Tower = { origin.X, origin.Y + TOWER_TOP, origin.Z + TOWER_Z },
		Bounds = { origin.X - X_HALF, origin.X + X_HALF, origin.Z + Z_MIN, origin.Z + Z_MAX },
		Boards = boards,
		Spots = spots,
		BoardsT0 = self.boardsT0,
		BoardHalf = ArrowAmbush.BOARD_HALF,
		BoardHeight = ArrowAmbush.BOARD_HEIGHT,
		Samples = SAMPLES,
		RailTop = ArrowAmbush.RAIL_TOP + 0.04, -- where the boards' wheels sit
		Hit = ArrowAmbush.HIT_RADIUS,
		Ring = ArrowAmbush.RING_RADIUS, -- the landing ring's drawn radius
		Cooldown = self.cooldown,
	})
	ctx:SetStatus(if #archers > 1 then "2 ARCHERS vs the RUNNERS!" else "1 ARCHER vs the RUNNERS!")
end

-- The meadow round the castle grounds (Scenery.Meadow's look: grass to the horizon, a ring of forest,
-- flowering bushes, soft hills), keeping trees and bushes off the castle and the festival.
local function meadow(ctx, center: Vector3, radius: number, clear: (Vector3) -> boolean)
	Build.Part({
		Name = "Grass",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, radius * 2, radius * 2),
		CFrame = CFrame.new(center - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = rgb(106, 188, 82),
		Material = Enum.Material.Grass,
		Parent = ctx.Arena,
	})
	local leafColors = { rgb(80, 190, 90), rgb(110, 200, 80), rgb(70, 165, 95), rgb(140, 205, 85) }
	for index = 0, 29 do
		local angle = (index + rng:NextNumber(-0.35, 0.35)) / 30 * math.pi * 2
		local distance = rng:NextNumber(58, 100)
		local at = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if clear(at) then
			MeshLibrary.Get("Tree", {
				Scale = rng:NextNumber(1.5, 2.7),
				Colors = { Leaves = leafColors[rng:NextInteger(1, #leafColors)] },
				CFrame = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = ctx.Arena,
			})
		end
	end
	local flowerColors = { rgb(255, 130, 190), rgb(255, 220, 90), rgb(180, 140, 255), rgb(255, 255, 255) }
	for index = 0, 23 do
		local angle = (index + rng:NextNumber(-0.4, 0.4)) / 24 * math.pi * 2
		local distance = rng:NextNumber(50, 62)
		local at = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if clear(at) then
			MeshLibrary.Get("Bush", {
				Scale = rng:NextNumber(1.1, 1.9),
				Colors = { Flowers = flowerColors[rng:NextInteger(1, #flowerColors)] },
				CFrame = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = ctx.Arena,
			})
		end
	end
	for index = 0, 11 do
		local angle = (index + rng:NextNumber(-0.3, 0.3)) / 12 * math.pi * 2
		local distance = radius * rng:NextNumber(0.7, 0.85)
		-- (Each hill gets its own height step, so no two buried bottoms ever share a plane.)
		local height = 50 + (index * 7 % 12) * 3.3 + rng:NextNumber(0, 0.5)
		local size = Vector3.new(rng:NextNumber(150, 230), height, rng:NextNumber(110, 160))
		local hill = Build.Part({
			Name = "Hill",
			Size = size,
			CFrame = CFrame.new(
				center + Vector3.new(math.cos(angle) * distance, -size.Y * 0.2, math.sin(angle) * distance)
			) * CFrame.Angles(0, -angle + math.pi / 2, 0),
			Color = rgb(96, 176, 86):Lerp(rgb(70, 140, 90), rng:NextNumber(0, 1)),
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = ctx.Arena,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = hill
	end
end

-- The look: a storybook castle archery tournament. The archers' tower (blue-roofed stair turret,
-- banners, painted shields) stands in front of a castle curtain wall with towers; the courtyard is
-- cobbled in cream, honey and blue stones inside a low crenellated wall with corner turrets and
-- bunting; banner poles line the sides, and past the far wall a row of hay targets stands before
-- striped festival tents. Everything outside the walls is scenery: the courtyard, its colliders,
-- barriers and the boards are as they were.
function ArrowAmbush:_buildArena()
	local ctx = self.context
	local origin: Vector3 = self.origin
	local ground = origin.Y - 0.5 -- the tournament field's top, round the courtyard
	local function at(x: number, z: number, y: number?): Vector3
		return Vector3.new(origin.X + x, y or ground, origin.Z + z)
	end
	local grass = origin.Y - 0.6 -- the meadow's top
	local castleZ = TOWER_Z - 16 -- the curtain wall behind the tower
	local castleX = 56 -- ... and its side walls
	meadow(ctx, origin - Vector3.new(0, 0.6, 0), 300, function(point: Vector3): boolean
		local x, z = point.X - origin.X, point.Z - origin.Z
		-- (Only the castle's own depth is kept clear: the forest rises behind its battlements.)
		return not (math.abs(x) < castleX + 8 and z < -2 and z > castleZ - 12)
			and not (math.abs(x) < 48 and z > 24 and z < 60)
	end)
	-- The tournament field: trampled sand round the courtyard, the meadow beyond.
	Shapes.Slab(Vector3.new(90, 0.4, 86), 10, {
		Name = "Field",
		CFrame = CFrame.new(at(0, 6, ground - 0.2)),
		Color = rgb(226, 204, 156),
		Material = Enum.Material.Sand,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = ctx.Arena,
	})

	-- The courtyard floor (what runners stand on): its top shows between the cobbles as grout.
	local floorSize = Vector3.new(X_HALF * 2 + 7.2, 1.6, Z_MAX - Z_MIN + 7.2)
	local floorCenter = origin + Vector3.new(0, -0.8, (Z_MIN + Z_MAX) / 2)
	Shapes.Slab(floorSize, 1, {
		Name = "Courtyard",
		CFrame = CFrame.new(floorCenter),
		Color = rgb(150, 134, 120),
		Material = Enum.Material.Slate,
		Parent = ctx.Arena,
	})
	-- Cobbles: 5 x 4 tiles fill the inside of the walls, their tops a little over the floor.
	for i = 0, 4 do
		for j = 0, 3 do
			MeshLibrary.Get("ArrowAmbushCobbles", {
				CFrame = CFrame.new(origin + Vector3.new(-21.2 + i * 10.6, -0.24, Z_MIN - 1.4 + 5.35 + j * 10.7))
					* CFrame.Angles(0, if (i + j) % 2 == 0 then 0 else math.pi, 0),
				Parent = ctx.Arena,
			})
		end
	end

	-- The low wall: an invisible collider with the barrier above it (as before), dressed in stone
	-- sections with coping and little merlons.
	local function wall(center: Vector3, size: Vector3, barrierLength: number)
		Shapes.RoundedBox(size + Vector3.new(0, 0.2, 0), 0.5, {
			Name = "Wall",
			CFrame = CFrame.new(center + Vector3.new(0, size.Y / 2 - 0.1, 0)),
			Transparency = 1,
			Parent = ctx.Arena,
		})
		Build.Barrier({
			Name = "Barrier",
			Size = if size.X > size.Z
				then Vector3.new(barrierLength, 16, size.Z)
				else Vector3.new(size.X, 16, barrierLength),
			CFrame = CFrame.new(center + Vector3.new(0, size.Y + 8, 0)),
			Parent = ctx.Arena,
		})
		local alongX = size.X > size.Z
		local length = if alongX then size.X else size.Z
		local count = math.round(length / 8.8)
		local step = length / count
		for k = 0, count - 1 do
			local offset = -length / 2 + step * (k + 0.5)
			MeshLibrary.Get("ArrowAmbushWall", {
				Scale = step / 8.8,
				CFrame = CFrame.new(center + if alongX then Vector3.new(offset, 0, 0) else Vector3.new(0, 0, offset))
					* CFrame.Angles(0, if alongX then 0 else math.pi / 2, 0),
				Parent = ctx.Arena,
			})
		end
	end
	local wx, z0, z1 = X_HALF + 2.2, Z_MIN - 2.2, Z_MAX + 2.2
	wall(origin + Vector3.new(0, 0, z1), Vector3.new(wx * 2 - 1.6, WALL, 1.6), wx * 2 + 2.6)
	wall(origin + Vector3.new(0, 0, z0), Vector3.new(wx * 2 - 1.6, WALL, 1.6), wx * 2 + 2.6)
	wall(origin + Vector3.new(-wx, 0, (z0 + z1) / 2), Vector3.new(1.6, WALL, z1 - z0 - 1.6), z1 - z0 + 2.6)
	wall(origin + Vector3.new(wx, 0, (z0 + z1) / 2), Vector3.new(1.6, WALL, z1 - z0 - 1.6), z1 - z0 + 2.6)
	-- Corner turrets round the corner posts (the posts stay as invisible colliders).
	local red, gold, blue = rgb(226, 62, 74), rgb(255, 200, 70), rgb(64, 112, 214)
	for _, cx in { -1, 1 } do
		for _, cz in { z0, z1 } do
			local post = origin + Vector3.new(cx * wx, 0, cz)
			Shapes.RoundedBox(Vector3.new(2.6, WALL + 2.8, 2.6), 0.5, {
				Name = "Post",
				CFrame = CFrame.new(post + Vector3.new(0, (WALL + 2.8) / 2 - 0.4, 0)),
				Transparency = 1,
				Parent = ctx.Arena,
			})
			MeshLibrary.Get("ArrowAmbushTurret", {
				Colors = { Flag = if cx < 0 then red else gold },
				CFrame = CFrame.new(post - Vector3.new(0, 0.15, 0))
					* CFrame.Angles(0, if cz == z0 then math.pi else 0, 0),
				Parent = ctx.Arena,
			})
		end
	end

	-- Bunting from turret to turret along the side and far walls, held up by a pole halfway.
	local hang = WALL + 3.1
	local function bunting(a: Vector3, b: Vector3)
		local scale = (b - a).Magnitude / 20
		local mid = (a + b) / 2
		MeshLibrary.Get("Bunting", {
			Scale = scale,
			CFrame = CFrame.lookAt(mid, mid + (b - a).Unit:Cross(Vector3.yAxis))
				+ Vector3.new(0, hang - 2.23 * scale, 0),
			Parent = ctx.Arena,
		})
	end
	local runs = {
		{ Vector3.new(-wx, 0, z0), Vector3.new(-wx, 0, z1) },
		{ Vector3.new(wx, 0, z0), Vector3.new(wx, 0, z1) },
		{ Vector3.new(-wx, 0, z1), Vector3.new(wx, 0, z1) },
	}
	for _, run in runs do
		local a, b = origin + run[1], origin + run[2]
		local mid = (a + b) / 2
		Build.Part({
			Name = "BuntingPole",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(hang + 0.4, 0.3, 0.3),
			CFrame = CFrame.new(mid + Vector3.new(0, (hang + 0.4) / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = gold,
			Material = Enum.Material.Metal,
			Parent = ctx.Arena,
		})
		bunting(a, mid)
		bunting(mid, b)
	end

	-- The archers' tower behind the north wall on a stone plinth, with a solid core to stand on.
	MeshLibrary.Get("ArcherTower", {
		CFrame = CFrame.new(origin + Vector3.new(0, 0, TOWER_Z)) * CFrame.Angles(0, math.pi, 0),
		Parent = ctx.Arena,
	})
	Build.Part({
		Name = "TowerPlinth",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 15.2, 15.2),
		CFrame = CFrame.new(origin + Vector3.new(0, -0.3, TOWER_Z)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = rgb(198, 186, 170),
		Material = Enum.Material.Slate,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = ctx.Arena,
	})
	Build.Part({
		Name = "TowerCore",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(TOWER_TOP, 12.4, 12.4),
		CFrame = CFrame.new(origin + Vector3.new(0, TOWER_TOP / 2, TOWER_Z)) * CFrame.Angles(0, 0, math.rad(90)),
		Transparency = 1,
		Parent = ctx.Arena,
	})
	Build.Barrier({
		Name = "TowerFence",
		Size = Vector3.new(16, 10, 1),
		CFrame = CFrame.new(origin + Vector3.new(0, TOWER_TOP + 5, TOWER_Z + 6.8)),
		Parent = ctx.Arena,
	})
	for _, x in { -6.2, 6.2 } do
		MeshLibrary.Get("ArrowBarrel", {
			CFrame = CFrame.new(at(x, TOWER_Z + 5.4)) * CFrame.Angles(0, x, 0),
			Parent = ctx.Arena,
		})
	end

	-- The castle behind the tower: curtain walls with banners between round towers, and side walls
	-- reaching forward, so the runners look up at a storybook castle.
	local castleBanners = { blue, red, blue, red, blue, red, blue }
	for k = -3, 3 do
		MeshLibrary.Get("ArrowAmbushCastleWall", {
			Colors = { Banner = castleBanners[k + 4] },
			CFrame = CFrame.new(at(k * 16, castleZ, grass - 0.05)) * CFrame.Angles(0, math.pi, 0),
			Parent = ctx.Arena,
		})
	end
	for _, side in { -1, 1 } do
		for k = 0, 1 do
			MeshLibrary.Get("ArrowAmbushCastleWall", {
				Colors = { Banner = if k == 0 then red else blue },
				CFrame = CFrame.new(at(side * castleX, castleZ + 8 + k * 16, grass - 0.05))
					* CFrame.Angles(0, side * math.pi / 2, 0),
				Parent = ctx.Arena,
			})
		end
	end
	local towers = {
		{ 8, castleZ, 1.6 },
		{ 40, castleZ, 2 },
		{ castleX, castleZ, 2.4 },
		{ castleX, castleZ + 32, 1.9 },
	}
	for _, tower in towers do
		for _, side in { -1, 1 } do
			MeshLibrary.Get("ArrowAmbushTurret", {
				Scale = tower[3],
				Colors = { Flag = if side < 0 then red else gold },
				CFrame = CFrame.new(at(side * tower[1], tower[2], grass - 0.15)) * CFrame.Angles(0, math.pi, 0),
				Parent = ctx.Arena,
			})
		end
	end

	-- Banner poles along the outside of the side walls, their banners facing in.
	for _, side in { -1, 1 } do
		for index, z in { -8, 6, 20 } do
			MeshLibrary.Get("ArrowAmbushBanner", {
				Colors = { Cloth = if (index + (if side < 0 then 0 else 1)) % 2 == 0 then red else blue },
				CFrame = CFrame.new(at(side * (wx + 4.4), z)) * CFrame.Angles(0, side * math.pi / 2, 0),
				Parent = ctx.Arena,
			})
		end
	end

	-- The festival past the far wall: hay targets facing the tower, striped tents behind them.
	for _, x in { -16, -8, 8, 16 } do
		MeshLibrary.Get("ArrowAmbushHayTarget", {
			CFrame = CFrame.new(at(x, z1 + 6)) * CFrame.Angles(0, math.rad(x * 0.6), 0),
			Parent = ctx.Arena,
		})
	end
	local tents = {
		{ -31, z1 + 12, 1, rgb(226, 62, 74), gold },
		{ -17, z1 + 17, 1, rgb(64, 120, 226), red },
		{ 0, z1 + 15, 1.25, rgb(156, 88, 214), gold },
		{ 17, z1 + 17, 1, rgb(60, 176, 110), red },
		{ 31, z1 + 12, 1, rgb(255, 150, 50), gold },
	}
	for _, tent in tents do
		MeshLibrary.Get("ArrowAmbushTent", {
			Scale = tent[3],
			Colors = { StripeA = tent[4], Flag = tent[5] },
			CFrame = CFrame.new(at(tent[1], tent[2])) * CFrame.Angles(0, math.rad(-tent[1] * 0.8), 0),
			Parent = ctx.Arena,
		})
	end
	local bales = {
		{ -wx - 5, z1 + 3, 20 },
		{ wx + 5.5, z1 + 2.5, -15 },
		{ -wx - 6, z0 + 3, 80 },
		{ wx + 6, z0 + 5, 100 },
		{ -24, z1 + 7, 5 },
		{ 24, z1 + 7, -10 },
	}
	for _, spot in bales do
		MeshLibrary.Get("HayBale", {
			CFrame = CFrame.new(at(spot[1], spot[2])) * CFrame.Angles(0, math.rad(spot[3]), 0),
			Parent = ctx.Arena,
		})
	end

	-- Target boards on rails: two rows of boards with 4 runners or fewer, three rows otherwise.
	local runners = math.max(1, #ctx:GetPlayers() - (if #ctx:GetPlayers() >= 6 then 2 else 1))
	local rows = if runners <= 4 then { -2, 11 } else { -6, 4, 14 }
	self.boards = {} :: { Board }
	local values = {}
	for index, z in rows do
		for _, side in { -1, 1 } do
			-- Each board keeps to its own half, so the two in a row never meet.
			table.insert(self.boards, {
				C = side * 12.5 + (if index % 2 == 0 then side * 0.8 else 0),
				Z = z,
				A = rng:NextNumber(6, 7.2),
				W = 2 * math.pi / rng:NextNumber(6.5, 10),
				P = rng:NextNumber(0, math.pi * 2),
				V = 0,
			})
			table.insert(values, #values % 3 + 1)
		end
	end
	for index = #values, 2, -1 do
		local other = rng:NextInteger(1, index)
		values[index], values[other] = values[other], values[index]
	end
	for index, board in self.boards do
		board.V = values[index]
		-- Its rail: two metal strips the board's wheels run on, over wooden sleepers set in the
		-- cobbles. Every layer's top and bottom are at their own heights (never coplanar).
		local length = board.A * 2 + 6.6
		for _, offset in { -0.78, 0.78 } do
			Build.Decor({
				Name = "Rail",
				Size = Vector3.new(length, ArrowAmbush.RAIL_TOP + 0.4, 0.3),
				CFrame = CFrame.new(origin + Vector3.new(board.C, (ArrowAmbush.RAIL_TOP - 0.4) / 2, board.Z + offset)),
				Color = rgb(120, 120, 135),
				Material = Enum.Material.Metal,
				Parent = ctx.Arena,
			})
		end
		local sleepers = math.floor(length / 2.2)
		for step = 0, sleepers do
			local x = origin.X + board.C - length / 2 + 0.7 + step * (length - 1.4) / sleepers
			Build.Decor({
				Name = "Sleeper",
				Size = Vector3.new(0.6, 0.5, 2.6),
				CFrame = CFrame.new(x, origin.Y - 0.05, origin.Z + board.Z),
				Color = rgb(140, 100, 70),
				Material = Enum.Material.Wood,
				Parent = ctx.Arena,
			})
		end
	end
	self.boardsT0 = workspace:GetServerTimeNow()
end

-- The first board an arrow from `from` to `to` (fired at `t0`) passes through, and when and where.
function ArrowAmbush:_firstBoard(from: Vector3, to: Vector3, t0: number, flight: number, arc: number)
	local floorY = self.floorY
	local originX, originZ = self.origin.X, self.origin.Z
	local previous = from
	for step = 1, SAMPLES do
		local s = step / SAMPLES
		local point = ArrowAmbush.PointAt(from, to, arc, s)
		for index, board in self.boards do
			local planeZ = originZ + board.Z
			local a, b = previous.Z - planeZ, point.Z - planeZ
			if a == b or (a > 0 and b > 0) or (a < 0 and b < 0) then
				continue
			end
			local f = a / (a - b)
			local hit = previous:Lerp(point, f)
			local t = t0 + flight * ((step - 1 + f) / SAMPLES)
			local boardX = originX + ArrowAmbush.BoardX(board, self.boardsT0, t)
			local height = hit.Y - floorY
			if
				math.abs(hit.X - boardX) <= ArrowAmbush.BOARD_HALF
				and height <= ArrowAmbush.BOARD_HEIGHT
				and height > -0.5
			then
				return index, t, hit
			end
		end
		previous = point
	end
	return nil, nil, nil
end

-- Bots can't turn themselves to face their shots the way a player's client does: turn them here.
local function faceShot(archer: any, ctx, target: Vector3)
	if typeof(archer) == "Instance" then
		return -- players turn themselves on their own screen
	end
	local character, _, root = ctx:GetCharacter(archer)
	if character and root then
		local at = root.Position
		character:PivotTo(CFrame.lookAt(at, Vector3.new(target.X, at.Y, target.Z)))
	end
end

-- Where an archer's arrow leaves the bow for a shot at `target`: from the archer's own spot on the
-- tower (server-owned, never the character's position, which the archer's client controls).
-- The client half draws the aim path from the same point.
function ArrowAmbush:ShotFrom(archer: Player, target: Vector3): Vector3
	local spot = self.spots[archer]
	local base = (if spot then spot.Position else self.origin) + Vector3.new(0, SPAWN_LIFT, 0)
	local flat = Vector3.new(target.X - base.X, 0, target.Z - base.Z)
	local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, 1)
	return base + Vector3.new(0, 1.2, 0) + dir * 1.6
end

-- Plans a shot (the caller has already checked it may be fired) and tells everyone.
function ArrowAmbush:_fire(archer: Player, target: Vector3)
	local ctx = self.context
	local from = self:ShotFrom(archer, target)
	local distance = (target - from).Magnitude
	local flight, arc = ArrowAmbush.Flight(distance)
	local now = ctx:Now()
	local boardIndex, blockT, blockAt = self:_firstBoard(from, target, now, flight, arc)
	self.arrowId += 1
	local arrow: Arrow = {
		Id = self.arrowId,
		By = archer.UserId,
		From = from,
		To = target,
		T0 = now,
		T1 = blockT or (now + flight),
		Flight = flight,
		Arc = arc,
		Board = boardIndex or 0,
		Stop = blockAt or target,
	}
	table.insert(self.arrows, arrow)
	while #self.arrows > 24 do
		table.remove(self.arrows, 1)
	end
	ctx:Fire(nil, "Arrow", {
		Id = arrow.Id,
		By = arrow.By,
		From = { from.X, from.Y, from.Z },
		To = { target.X, target.Y, target.Z },
		T0 = arrow.T0,
		T1 = arrow.T1,
		Flight = flight,
		Arc = arc,
		Board = arrow.Board,
	})
	faceShot(archer, ctx, target)
	ctx:Delay(math.max(0, arrow.T1 - now), function()
		self:_land(arrow)
	end)
end

function ArrowAmbush:_land(arrow: Arrow)
	local ctx = self.context
	local archer = nil
	for _, player in ctx:GetPlayers() do
		if player.UserId == arrow.By then
			archer = player
		end
	end
	if arrow.Board > 0 then
		local board = self.boards[arrow.Board]
		if archer and board then
			local points = math.min(board.V, BOARD_CAP - (self.bonus[archer] or 0))
			if points > 0 then
				self.bonus[archer] = (self.bonus[archer] or 0) + points
				ctx:AddScore(archer, points)
			end
		end
		ctx:Fire(nil, "BoardHit", arrow.Id, arrow.Board, board and board.V or 0)
		return
	end
	-- Judge each runner by where they were on their own screen when it landed: their moves reach us
	-- half a ping (a round trip) late, so look then, and again JUDGE_SPREAD later; a tag needs both.
	for _, runner in ctx:GetAlivePlayers() do
		if self.role[runner] ~= "Runner" or self.tagged[runner] then
			continue
		end
		local ok, ping = pcall(function()
			return (runner :: any):GetNetworkPing()
		end)
		local lag = if ok and type(ping) == "number" then math.clamp(ping, 0, 0.4) / 2 else 0.05
		local function second(first: number)
			ctx:Delay(JUDGE_SPREAD, function()
				self:_judge(arrow, runner, archer, first)
			end)
		end
		if lag <= 0.01 then
			second(self:_distance(arrow, runner))
		else
			ctx:Delay(lag, function()
				second(self:_distance(arrow, runner))
			end)
		end
	end
	ctx:Fire(nil, "Landed", arrow.Id)
end

-- How far (flat) a runner's middle is from where an arrow came down (math.huge if they're gone).
function ArrowAmbush:_distance(arrow: Arrow, runner: Player): number
	local _, _, root = self.context:GetCharacter(runner)
	if not root then
		return math.huge
	end
	return Vector3.new(root.Position.X - arrow.To.X, 0, root.Position.Z - arrow.To.Z).Magnitude
end

-- The second look at a runner after a landing (`first` is the distance at the first look).
function ArrowAmbush:_judge(arrow: Arrow, runner: Player, archer: Player?, first: number)
	local ctx = self.context
	if self.tagged[runner] or not ctx:IsAlive(runner) then
		return
	end
	local _, _, root = ctx:GetCharacter(runner)
	if not root then
		return
	end
	-- Inside the walls every runner is reachable (the arrow comes down from above, so a jump
	-- doesn't dodge it; runners can't get higher than a jump, see the bounds check in Start).
	local offset = Vector3.new(root.Position.X - arrow.To.X, 0, root.Position.Z - arrow.To.Z)
	local away = if offset.Magnitude > 0.1 then offset.Unit else Vector3.new(0, 0, 1)
	if first <= ArrowAmbush.HIT_RADIUS and offset.Magnitude <= ArrowAmbush.HIT_RADIUS then
		self:_tag(runner, archer, away)
	elseif math.min(first, offset.Magnitude) <= SHOVE_RADIUS then
		ctx:Knockback(runner, away * 22 + Vector3.new(0, 14, 0), 0)
	end
end

function ArrowAmbush:_tag(runner: Player, archer: Player?, away: Vector3)
	local ctx = self.context
	self.tagged[runner] = true
	local _, _, root = ctx:GetCharacter(runner)
	local at = if root then root.Position else self.origin
	ctx:Fire(nil, "Tagged", runner.UserId, at.X, at.Y, at.Z, if archer then archer.UserId else 0)
	ctx:Knockback(runner, away * 38 + Vector3.new(0, 48, 0), 1)
	ctx:SetScoreText(runner, string.format("Tagged at %ds", math.floor(ctx:Elapsed())))
	if archer then
		self.tags[archer] = (self.tags[archer] or 0) + 1
		ctx:AddScore(archer, 3)
		local tags = self.tags[archer]
		ctx:SetScoreText(archer, if tags == 1 then "1 tag" else `{tags} tags`)
		ctx:SetPlayerShared(archer, "Tags", tags)
	end
	ctx:AddTeamScore(ArrowAmbush.ARCHERS, 1)
	ctx:Delay(0.9, function()
		ctx:Eliminate(runner, "arrow")
	end)
	self:_refresh()
end

function ArrowAmbush:RunnersLeft(): number
	local count = 0
	for _, player in self.context:GetAlivePlayers() do
		if self.role[player] == "Runner" and not self.tagged[player] then
			count += 1
		end
	end
	return count
end

function ArrowAmbush:ArchersLeft(): number
	local count = 0
	for _, player in self.context:GetAlivePlayers() do
		if self.role[player] == "Archer" then
			count += 1
		end
	end
	return count
end

-- Status line, and the end of the round once one side is gone.
function ArrowAmbush:_refresh()
	local ctx = self.context
	if self.ended then
		return
	end
	local left = self:RunnersLeft()
	-- The banner's team scores: tags for the archers, runners still going for the runners.
	if ctx:IsRunning() and left ~= self.shownRunners then
		ctx:AddTeamScore(ArrowAmbush.RUNNERS, left - self.shownRunners)
		self.shownRunners = left
	end
	if self.runnerCount > 0 and left == 0 then
		self.ended = true
		local tagged = 0
		for _ in self.tagged do
			tagged += 1
		end
		if tagged == 0 then
			-- Nobody was tagged: the runners left (or never made it in).
			ctx:SetStatus("🏃 The runners left!")
			ctx:End("NoRunners")
			return
		end
		ctx:SetStatus("🏹 Every runner is tagged! ARCHERS win!")
		ctx:Delay(1.3, function()
			ctx:End("AllTagged")
		end)
		return
	end
	if self.runnerCount > 0 and self:ArchersLeft() == 0 then
		self.ended = true
		ctx:SetStatus("🏃 The archers left. RUNNERS win!")
		ctx:End("NoArchers")
		return
	end
	ctx:SetStatus(if left == 1 then "🏃 1 runner left!" else `🏃 {left} runners left`)
end

function ArrowAmbush:Start()
	local ctx = self.context
	-- Archers stay on their tower spot; they only turn and shoot.
	for player, role in self.role do
		if role == "Archer" then
			ctx:Freeze(player, true)
		end
	end
	ctx.Hooks.CharacterReady = function(player)
		if self.role[player] == "Archer" then
			ctx:Freeze(player, true)
		end
	end
	ctx.Hooks.PlayerLeft = function()
		self:_refresh()
	end
	ctx.Hooks.Eliminated = function()
		self:_refresh()
	end

	ctx:OnAction("Shoot", function(player, x, z)
		if self.role[player] ~= "Archer" or self.ended then
			return
		end
		if type(x) ~= "number" or type(z) ~= "number" or x ~= x or z ~= z then
			return
		end
		local now = ctx:Now()
		if now < (self.nextShot[player] or 0) - 0.08 then
			return -- still drawing the next arrow
		end
		local origin = self.origin
		local target = Vector3.new(
			math.clamp(x, origin.X - X_HALF - 1, origin.X + X_HALF + 1),
			self.floorY,
			math.clamp(z, origin.Z + Z_MIN - 1, origin.Z + Z_MAX + 1)
		)
		-- (From the later of now and when it was due, so the early leeway never adds up.)
		self.nextShot[player] = math.max(now, self.nextShot[player] or 0) + self.cooldown
		ctx:SetPlayerShared(player, "NextShot", self.nextShot[player])
		self:_fire(player, target)
	end, { Interval = 0.2 })

	-- Runners score for every second they stay untagged. Positions and speeds are tracked for the
	-- bots' aim, and anyone outside where their role belongs is put back.
	local lastSecond = 0
	ctx:Loop(function(): number?
		local now = ctx:Now()
		local origin = self.origin
		for _, player in ctx:GetAlivePlayers() do
			local character, _, root = ctx:GetCharacter(player)
			if not character or not root then
				continue
			end
			local position = root.Position
			local seen = self.track[player]
			if seen and now > seen.T then
				local vel = (position - seen.Pos) / (now - seen.T)
				seen.Vel = seen.Vel:Lerp(Vector3.new(vel.X, 0, vel.Z), 0.6)
				seen.Pos, seen.T = position, now
			else
				self.track[player] = { Pos = position, Vel = Vector3.zero, T = now }
			end
			if self.role[player] == "Runner" and not self.tagged[player] then
				local outside = math.abs(position.X - origin.X) > X_HALF + 4
					or position.Z - origin.Z < Z_MIN - 4
					or position.Z - origin.Z > Z_MAX + 4
					or position.Y - self.floorY > 14 -- higher than any jump: put back on the floor
				if outside then
					local back = Vector3.new(
						math.clamp(position.X, origin.X - X_HALF + 2, origin.X + X_HALF - 2),
						self.floorY + 3,
						math.clamp(position.Z, origin.Z + Z_MIN + 2, origin.Z + Z_MAX - 2)
					)
					character:PivotTo(CFrame.new(back))
				end
			elseif self.role[player] == "Archer" then
				local spot = self.spots[player]
				if spot and (position - spot.Position).Magnitude > 6 then
					character:PivotTo(spot + Vector3.new(0, 3, 0))
				end
			end
		end
		if now - lastSecond >= 1 then
			lastSecond = now
			for _, player in ctx:GetAlivePlayers() do
				if self.role[player] == "Runner" and not self.tagged[player] then
					ctx:AddScore(player, 1)
				end
			end
		end
		return 0.1
	end)
	self:_refresh()
end

-- Everyone on the winning side shares first place (equal Rank); the losing side is ordered by
-- points: archers by tags and boards, runners by how long they stayed untagged.
function ArrowAmbush:GetResults()
	local ctx = self.context
	local runnersWin = self:RunnersLeft() > 0 or self:ArchersLeft() == 0
	local winner = if runnersWin then ArrowAmbush.RUNNERS else ArrowAmbush.ARCHERS
	local entries = {}
	for _, player in ctx:GetPlayers() do
		local state = ctx:State(player)
		local role = self.role[player]
		if not state or not role then
			continue
		end
		local team = if role == "Archer" then ArrowAmbush.ARCHERS else ArrowAmbush.RUNNERS
		local text
		if role == "Archer" then
			local tags = self.tags[player] or 0
			text = `🏹 {tags} {if tags == 1 then "tag" else "tags"}`
			if (self.bonus[player] or 0) > 0 then
				text ..= ` • +{self.bonus[player]} boards`
			end
		else
			text = if not self.tagged[player] and state.Alive then "🏃 Never tagged!" else `🏃 {state.ScoreText}`
		end
		table.insert(entries, {
			Player = player,
			Rank = if team == winner then 1e6 else state.Score,
			ScoreText = text,
			BestScore = state.Score,
			Team = team,
		})
	end
	return { Entries = entries, WinningTeam = winner }
end

return ArrowAmbush

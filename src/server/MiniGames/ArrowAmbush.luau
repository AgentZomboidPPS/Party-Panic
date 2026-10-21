-- Arrow Ambush (Versus, 35s, 2-12 players). Mechanics after "Archer-ival": one ARCHER (two with
-- six or more players) stands on a stone tower above a castle courtyard with a bow and endless
-- arrows; everyone else is a RUNNER in the courtyard below. Archers click or tap where to shoot;
-- runners dodge, and hide behind the big target boards that roll slowly back and forth on rails.
-- One arrow tags a runner. Archers win by tagging every runner; runners win if anyone is still
-- untagged when time runs out. Like the bonus panels in the original, an arrow that hits a target
-- board is blocked, but scores the archer the board's number (+1, +2 or +3).
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

local MiniGame = require(script.Parent.Kit.MiniGame)
local Scenery = require(script.Parent.Kit.Scenery)
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
ArrowAmbush.HIT_RADIUS = 2.7 -- a runner this close to where an arrow lands is tagged
local SHOVE_RADIUS = 5.5 -- near misses get a little shove
ArrowAmbush.BOARD_HALF = 3.6 -- half the width of a target board (what blocks arrows)
ArrowAmbush.BOARD_HEIGHT = 8 -- boards block arrows below this height above the floor
local SAMPLES = 48 -- flight samples when looking for a board in the way

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
	return 0.32 + distance / 95, 1.5 + distance * 0.04
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
	self.ended = false
	self.shownRunners = 0

	self:_buildArena()

	-- Roles: one archer under six players, two from six on; everyone else runs.
	local players = ctx:GetPlayers()
	for index = #players, 2, -1 do
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local archerCount = if #players >= 6 then 2 else 1
	if #players < 2 then
		archerCount = 0 -- a lone player (Studio) just runs from... nobody; bots fill real rounds
	end
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
		local position = origin + Vector3.new(x, 0, Z_MAX - 5 - row * 5)
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
		BoardsT0 = self.boardsT0,
		BoardHalf = ArrowAmbush.BOARD_HALF,
		RailTop = ArrowAmbush.RAIL_TOP + 0.04, -- where the boards' wheels sit
		Hit = ArrowAmbush.HIT_RADIUS,
		Cooldown = self.cooldown,
	})
	ctx:SetStatus(if #archers > 1 then "2 ARCHERS vs the RUNNERS!" else "1 ARCHER vs the RUNNERS!")
end

function ArrowAmbush:_buildArena()
	local ctx = self.context
	local origin: Vector3 = self.origin
	Scenery.Meadow(ctx, origin - Vector3.new(0, 0.6, 0), 300)

	-- The courtyard: a flagstone floor inside a low stone wall.
	local floorSize = Vector3.new(X_HALF * 2 + 7.2, 1.6, Z_MAX - Z_MIN + 7.2)
	local floorCenter = origin + Vector3.new(0, -0.8, (Z_MIN + Z_MAX) / 2)
	Shapes.Slab(floorSize, 1, {
		Name = "Courtyard",
		CFrame = CFrame.new(floorCenter),
		Color = rgb(214, 200, 178),
		Material = Enum.Material.Cobblestone,
		Parent = ctx.Arena,
	})
	-- A checker of lighter flagstones, a hair above the floor (never coplanar).
	for gx = -4, 4 do
		for gz = 0, 6 do
			if (gx + gz) % 2 == 0 then
				Build.Decor({
					Name = "Flag",
					Size = Vector3.new(5.4, 0.3, 5.4),
					CFrame = CFrame.new(origin + Vector3.new(gx * 5.8, -0.05, Z_MIN + 2.6 + gz * 5.8)),
					Color = rgb(232, 222, 202),
					Material = Enum.Material.Slate,
					Parent = ctx.Arena,
				})
			end
		end
	end
	local wallColor = rgb(176, 164, 150)
	local capColor = rgb(226, 214, 196)
	-- A wall from post to post (its ends tucked into the posts), sunk a little into the floor.
	local function wall(center: Vector3, size: Vector3, barrierLength: number, capHeight: number)
		Shapes.RoundedBox(size + Vector3.new(0, 0.2, 0), 0.5, {
			Name = "Wall",
			CFrame = CFrame.new(center + Vector3.new(0, size.Y / 2 - 0.1, 0)),
			Color = wallColor,
			Material = Enum.Material.Slate,
			Parent = ctx.Arena,
		})
		Shapes.RoundedBox(Vector3.new(size.X + 0.5, capHeight, size.Z + 0.5), 0.2, {
			Name = "WallCap",
			CFrame = CFrame.new(center + Vector3.new(0, size.Y + 0.25, 0)),
			Color = capColor,
			Material = Enum.Material.Slate,
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
	end
	local wx, z0, z1 = X_HALF + 2.2, Z_MIN - 2.2, Z_MAX + 2.2
	-- (The side walls' caps are a little taller, so caps meeting inside a post never share a face.)
	wall(origin + Vector3.new(0, 0, z1), Vector3.new(wx * 2 - 1.6, WALL, 1.6), wx * 2 + 2.6, 0.5)
	wall(origin + Vector3.new(0, 0, z0), Vector3.new(wx * 2 - 1.6, WALL, 1.6), wx * 2 + 2.6, 0.5)
	wall(origin + Vector3.new(-wx, 0, (z0 + z1) / 2), Vector3.new(1.6, WALL, z1 - z0 - 1.6), z1 - z0 + 2.6, 0.74)
	wall(origin + Vector3.new(wx, 0, (z0 + z1) / 2), Vector3.new(1.6, WALL, z1 - z0 - 1.6), z1 - z0 + 2.6, 0.74)
	-- Corner posts with banners.
	for _, cx in { -1, 1 } do
		for _, cz in { z0, z1 } do
			local post = origin + Vector3.new(cx * wx, 0, cz)
			Shapes.RoundedBox(Vector3.new(2.6, WALL + 2.8, 2.6), 0.5, {
				Name = "Post",
				CFrame = CFrame.new(post + Vector3.new(0, (WALL + 2.8) / 2 - 0.4, 0)),
				Color = wallColor,
				Material = Enum.Material.Slate,
				Parent = ctx.Arena,
			})
			Build.Decor({
				Name = "PostCap",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 1.6,
				CFrame = CFrame.new(post + Vector3.new(0, WALL + 2.9, 0)),
				Color = rgb(255, 150, 70),
				Parent = ctx.Arena,
			})
		end
	end

	-- The archers' tower behind the north wall, with a solid core to stand on.
	MeshLibrary.Get("ArcherTower", {
		CFrame = CFrame.new(origin + Vector3.new(0, 0, TOWER_Z)) * CFrame.Angles(0, math.pi, 0),
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

	-- Whether an x is within a hair of a flagstone's edge (faces that close would flicker).
	local function nearFlagEdge(x: number): boolean
		local offset = (x - origin.X + 2.9) % 5.8 -- flagstone edges sit 0.2 either side of these lines
		return math.abs(offset - 0.2) < 0.12 or math.abs(offset - 5.6) < 0.12
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
		-- Its rail: two metal strips the board's wheels run on, over wooden sleepers. Every layer's
		-- top and bottom are at their own heights (never coplanar with the flagstones).
		local length = board.A * 2 + 6.6
		if nearFlagEdge(origin.X + board.C + length / 2) or nearFlagEdge(origin.X + board.C - length / 2) then
			length += 0.3
		end
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
			if nearFlagEdge(x - 0.3) or nearFlagEdge(x + 0.3) then
				x += 0.2
			end
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

-- Plans a shot (the caller has already checked it may be fired) and tells everyone.
function ArrowAmbush:_fire(archer: Player, target: Vector3)
	local ctx = self.context
	local spot = self.spots[archer]
	local _, _, root = ctx:GetCharacter(archer)
	local base = if root then root.Position else (spot and spot.Position or self.origin)
	local flat = Vector3.new(target.X - base.X, 0, target.Z - base.Z)
	local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, 1)
	local from = base + Vector3.new(0, 1.2, 0) + dir * 1.6
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
			self.bonus[archer] = (self.bonus[archer] or 0) + board.V
			ctx:AddScore(archer, board.V)
		end
		ctx:Fire(nil, "BoardHit", arrow.Id, arrow.Board, board and board.V or 0)
		return
	end
	-- Judge each runner when their own view of the landing has reached us (ping leeway).
	for _, runner in ctx:GetAlivePlayers() do
		if self.role[runner] ~= "Runner" or self.tagged[runner] then
			continue
		end
		local ok, ping = pcall(function()
			return (runner :: any):GetNetworkPing()
		end)
		local lag = if ok and type(ping) == "number" then math.clamp(ping, 0, 0.3) else 0.1
		if lag <= 0.03 then
			self:_judge(arrow, runner, archer)
		else
			ctx:Delay(lag, function()
				self:_judge(arrow, runner, archer)
			end)
		end
	end
	ctx:Fire(nil, "Landed", arrow.Id)
end

function ArrowAmbush:_judge(arrow: Arrow, runner: Player, archer: Player?)
	local ctx = self.context
	if self.tagged[runner] or not ctx:IsAlive(runner) then
		return
	end
	local _, _, root = ctx:GetCharacter(runner)
	if not root then
		return
	end
	local offset = Vector3.new(root.Position.X - arrow.To.X, 0, root.Position.Z - arrow.To.Z)
	local height = root.Position.Y - self.floorY
	if height > 9 then
		return -- somewhere the arrow can't reach (shouldn't happen inside the walls)
	end
	local away = if offset.Magnitude > 0.1 then offset.Unit else Vector3.new(0, 0, 1)
	if offset.Magnitude <= ArrowAmbush.HIT_RADIUS then
		self:_tag(runner, archer, away)
	elseif offset.Magnitude <= SHOVE_RADIUS then
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
		self.nextShot[player] = now + self.cooldown
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

-- The winning side shares first place; inside each side, archers by points (tags and boards),
-- runners by how long they stayed untagged.
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
			Rank = (if team == winner then 1e6 else 0) + state.Score,
			ScoreText = text,
			BestScore = state.Score,
			Team = team,
		})
	end
	return { Entries = entries, WinningTeam = winner }
end

return ArrowAmbush

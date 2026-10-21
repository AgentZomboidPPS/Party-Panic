-- Tanks! (Versus, 75s, 2-12 players, free for all). After "Tanks!" from Wii Play: toy tanks battle
-- in a walled play-room arena. Every player drives a chunky toy tank: the stick (or WASD) drives,
-- the turret points at the mouse (phones: where you drag on the right of the screen, with an
-- aim-assist toward the nearest enemy in front), FIRE shoots a shell that ricochets once off the
-- walls, and LAY MINE drops a mine that blows after a few seconds or when a tank drives over it. One
-- hit and your tank is out (a big toy explosion, your character pops out and spectates). Last tank
-- standing wins; if time runs out, the survivors share the win ranked by hits.
--
-- How it works:
--   * The arena is a grid of cork tiles with wooden-block walls and low toy-brick cover
--     (Shared/Logic/TankField: the same layout, driving and shell maths on the server and clients).
--   * The server owns every tank: each player's client sends its stick and aim ("In", ~15 a second,
--     numbered), the server drives all tanks from their latest input (bots press the same control
--     through ctx:BotAction) and shares them 15 times a second ("Tanks": position, heading, turret,
--     speed, turn rate, and for players the last input it applied and when it arrived). A player's
--     client moves its own tank the moment they steer and quietly corrects toward the server's from
--     that ack; everyone else's tanks glide on from the shared speed and heading.
--   * A shell's whole flight follows from the shot (TankField.Path: straight, one true reflection off
--     the wall it hits, gone at the next), so a "Shot" event is all clients need to draw it. The shot
--     leaves from where the server has the tank when the press arrives (which is where the shooter
--     saw it: their screen runs their own tank that far ahead) and is timed from the press itself.
--   * Hits are box checks against the hull's real footprint (the mesh's 6.4 x 7.6 studs) padded by
--     the shell's radius, swept along the shell's path every frame. A player's own screen shows their
--     tank ahead of the server's by the one-way trip, so a player is judged against where each shell
--     was that long ago: what they saw dodge is a dodge, what they saw touch them is a hit. Bots (no
--     screen) are judged as the server sees them. A tank's own shell can hit it only after its
--     ricochet (and never in its first half second, so a shot point-blank into a wall is safe).
--   * Shells that meet pop each other; a shell that touches a mine sets it off (both only once the
--     shell is out of its barrel, where clients first draw it: a shot never sets off the mine under
--     its own tank). A mine arms after 1.5 s (its layer must have driven off it first), goes off
--     when a hull touches it or after 7 s, and its blast takes every tank, shell and mine within 10
--     studs (mines chain a moment later). Everyone one blast catches is knocked out in the same
--     server step; a player is spared if their own screen (a one-way trip ahead) had them outside.
--   * Live mines and shells are shared state as well as events, so a screen that starts late still
--     draws every one that's out.
--   * For the first 3 s after GO every tank is shielded (a shell that touches it just pops, a blast
--     passes it by), so nobody is out before they've had a chance to move.
--   * Each tank can have 2 shells in flight and 2 mines down. A hit scores for the shooter or the
--     mine's layer (never for yourself); a mine that takes its own layer scores for whoever set it
--     off (their shell, their tank driving onto it, or the blast that chained it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TankField = require(ReplicatedStorage.Shared.Logic.TankField)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local Tanks = MiniGame.Define("Tanks")
Tanks.Field = TankField -- the shared rules, for the round harness's test bot

local TILE = TankField.TILE
local SPEED = TankField.SHELL_SPEED
local MAX_LAG = 0.2 -- the furthest back a player's screen is judged (one-way trip, capped)
local SEAT_Y = 4.15 -- a driver's root above the floor, standing in the hatch
local SHARE_EVERY = 1 / 15
local FLOOR_DROP = 0.6 -- the cork board's thickness on the room's floorboards
local SINK = 0.05 -- props sit this far into what they stand on (no coplanar faces to flicker)

type Tank = {
	Player: any,
	Id: number,
	Slot: number,
	Bot: boolean,
	X: number,
	Z: number,
	H: number,
	V: number,
	Rev: boolean,
	W: number,
	LastH: number,
	Aim: number,
	MX: number,
	MZ: number,
	Seq: number,
	SeqAt: number,
	Lag: number,
	Out: boolean,
	OutAt: number?,
	Shells: number,
	LastShot: number,
	Mines: number,
	LastMine: number,
	Hits: number,
}

type Shell = {
	Id: number,
	Owner: Tank,
	T0: number,
	Path: TankField.Path,
	End: number, -- when it reaches its second wall
	Prev: number, -- checked up to this server time
	Aim: number,
	Dead: boolean,
	Counted: boolean, -- its owner got the slot back
}

type Mine = {
	Id: number,
	Owner: Tank,
	X: number,
	Z: number,
	ArmAt: number,
	BlowAt: number,
	Clear: boolean, -- its layer has driven off it
	Dead: boolean,
	Detonator: Tank?, -- whose shell (or blast) set it off, when not its layer's
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function round(x: number, step: number): number
	return math.floor(x / step + 0.5) * step
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < 1e9
end

-- A player's round trip (GetNetworkPing); a press only travels one way, half of it.
local function ping(player: any): number
	if BotRegistry.IsBot(player) then
		return 0
	end
	local ok, value = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and type(value) == "number" then math.clamp(value, 0, 0.4) else 0.15
end

-- Arena ---------------------------------------------------------------------------------------------

function Tanks:_at(x: number, y: number, z: number): CFrame
	return CFrame.new(self.origin + Vector3.new(x, y, z))
end

function Tanks:_buildArena()
	local ctx = self.context
	local arena = ctx.Arena
	local field = self.field
	local width, depth = field.Width, field.Depth
	local floorY = -FLOOR_DROP

	-- The room: honey floorboards, wallpapered walls on three sides, a big window, giant toys.
	local room = Build.Model("Room", arena)
	Build.Part({
		Name = "Floorboards",
		Size = Vector3.new(width + 360, 2, depth + 300),
		CFrame = self:_at(0, floorY - 1, 30),
		Color = rgb(196, 146, 96),
		Material = Enum.Material.WoodPlanks,
		Parent = room,
	})
	local northZ = -depth / 2 - 56
	local sideX = width / 2 + 70
	local wallpaper = rgb(176, 208, 236)
	for _, spec in
		{
			{ Vector3.new(width + 2 * 70 + 7.8, 72, 4), Vector3.new(0, 36, northZ - 2) },
			-- (the side walls sit 0.1 lower than the north one: no flush faces where they meet)
			{ Vector3.new(4, 72, depth + 220), Vector3.new(-sideX - 2, 35.9, 46) },
			{ Vector3.new(4, 72, depth + 220), Vector3.new(sideX + 2, 35.9, 46) },
		}
	do
		Build.Part({
			Name = "Wallpaper",
			Size = spec[1],
			CFrame = self:_at(spec[2].X, floorY + spec[2].Y, spec[2].Z),
			Color = wallpaper,
			Material = Enum.Material.Fabric,
			Parent = room,
		})
	end
	-- Baseboards along the walls (white, a little proud of the wallpaper).
	Build.Decor({
		Name = "Baseboard",
		Size = Vector3.new(width + 2 * 70, 5, 1.2),
		CFrame = self:_at(0, floorY + 2.5, northZ + 0.7),
		Color = rgb(250, 248, 240),
		Parent = room,
	})
	-- The side ones run from just behind the north one's front to just short of the walls' ends.
	local boardZ0, boardZ1 = northZ + 0.2, 46 + (depth + 220) / 2 - 1
	for _, side in { -1, 1 } do
		Build.Decor({
			Name = "Baseboard",
			Size = Vector3.new(1.2, 5.2, boardZ1 - boardZ0), -- (not flush with the north one's faces)
			CFrame = self:_at(side * (sideX - 0.7), floorY + 2.5, (boardZ0 + boardZ1) / 2),
			Color = rgb(250, 248, 240),
			Parent = room,
		})
	end
	MeshLibrary.Get("TanksWindow", {
		CFrame = self:_at(0, floorY + 14, northZ + 2) * CFrame.Angles(0, math.pi, 0), -- the frame proud of the wall (pivot is the box center)
		Parent = room,
	})
	-- Giant toys around the arena (north and the sides: the camera looks north).
	local bearX, bearZ = -width / 2 - 34, -depth / 2 - 22
	MeshLibrary.Get("TanksBear", {
		CFrame = self:_at(bearX, floorY - SINK, bearZ) * CFrame.Angles(0, math.atan2(bearX, bearZ), 0),
		Parent = room,
	})
	MeshLibrary.Get("TanksBall", {
		CFrame = self:_at(width / 2 + 36, floorY - SINK, -depth / 2 - 18) * CFrame.Angles(0, math.rad(30), 0),
		Parent = room,
	})
	MeshLibrary.Get("TanksRug", {
		CFrame = self:_at(width / 2 + 40, floorY - SINK, depth / 2 - 30),
		Parent = room,
	})
	local crayons = {
		{ -width / 2 - 22, depth / 2 - 20, 40, rgb(235, 70, 60) },
		{ -width / 2 - 30, depth / 2 - 8, 75, rgb(60, 130, 235) },
		{ -width / 2 - 18, 6, 10, rgb(250, 200, 40) },
		{ width / 2 + 22, -10, -60, rgb(80, 190, 90) },
		{ 30, -depth / 2 - 26, 95, rgb(160, 90, 220) },
		{ -40, -depth / 2 - 30, 20, rgb(250, 130, 40) },
	}
	for _, spec in crayons do
		MeshLibrary.Get("TanksCrayon", {
			CFrame = self:_at(spec[1], floorY - SINK, spec[2]) * CFrame.Angles(0, math.rad(spec[3]), 0),
			Colors = { Wax = spec[4], Wrapper = spec[4]:Lerp(Color3.new(1, 1, 1), 0.25) },
			Parent = room,
		})
	end

	-- The cork board and its tile grooves.
	Build.Part({
		Name = "Cork",
		Size = Vector3.new(width + 2, FLOOR_DROP + 0.4, depth + 2),
		CFrame = self:_at(0, -(FLOOR_DROP + 0.4) / 2, 0),
		Color = rgb(204, 160, 108),
		Material = Enum.Material.Sand,
		Parent = arena,
	})
	local grooves = Build.Model("Grooves", arena)
	local groove = rgb(176, 128, 80)
	for col = 1, field.Cols - 1 do
		Build.Decor({
			Name = "Groove",
			Size = Vector3.new(0.16, 0.2, depth),
			CFrame = self:_at(-width / 2 + col * TILE, 0, 0),
			Color = groove,
			Material = Enum.Material.Sand,
			Parent = grooves,
		})
	end
	for row = 1, field.Rows - 1 do
		Build.Decor({
			Name = "Groove",
			Size = Vector3.new(width, 0.4, 0.16), -- (faces 0.1 apart where they cross: no flicker)
			CFrame = self:_at(0, 0, -depth / 2 + row * TILE),
			Color = groove,
			Material = Enum.Material.Sand,
			Parent = grooves,
		})
	end

	-- Walls: a ring of wooden blocks outside the tiles, tall blocks and low toy bricks inside.
	local blocks = Build.Model("Blocks", arena)
	local woods = { rgb(232, 196, 140), rgb(206, 160, 104) }
	local bricks = { rgb(225, 60, 55), rgb(55, 120, 225), rgb(250, 200, 45), rgb(70, 180, 85) }
	local function blockAt(col: number, row: number)
		local x, z = TankField.Center(field, col, row)
		MeshLibrary.Get("TanksBlock", {
			CFrame = self:_at(x, floorY - SINK, z) * CFrame.Angles(0, math.rad(90 * ((col * 7 + row * 3) % 4)), 0),
			Colors = { Wood = woods[(col + row) % 2 + 1] },
			Parent = blocks,
		})
	end
	for col = 0, field.Cols + 1 do
		blockAt(col, 0)
		blockAt(col, field.Rows + 1)
	end
	for row = 1, field.Rows do
		blockAt(0, row)
		blockAt(field.Cols + 1, row)
	end
	local brickCount = 0
	for row = 1, field.Rows do
		for col = 1, field.Cols do
			local cell = field.Grid[row][col]
			if cell == "#" then
				blockAt(col, row)
			elseif cell == "+" then
				brickCount += 1
				local x, z = TankField.Center(field, col, row)
				MeshLibrary.Get("TanksBrick", {
					CFrame = self:_at(x, -SINK, z),
					Colors = { Plastic = bricks[(brickCount - 1) % #bricks + 1] },
					Parent = blocks,
				})
			end
		end
	end
end

-- Tanks ---------------------------------------------------------------------------------------------

-- Where a tank's driver stands: in the hatch, turned with the turret.
function Tanks:_seat(tank: Tank): CFrame
	return self:_at(tank.X, SEAT_Y, tank.Z) * CFrame.Angles(0, tank.Aim, 0)
end

function Tanks:_placeBot(tank: Tank)
	local _, humanoid, root = self.context:GetCharacter(tank.Player)
	if not humanoid or not root then
		return
	end
	if not root.Anchored then
		root.Anchored = true
	end
	if not humanoid.PlatformStand then
		humanoid.PlatformStand = true
	end
	root.CFrame = self:_seat(tank)
end

function Tanks:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	self.origin = ctx.Origin.Position
	ctx.KillY = self.origin.Y - 30

	local players = ctx:GetPlayers()
	self.mapName = TankField.MapFor(#players)
	self.field = TankField.Build(self.mapName)
	self.tanks = {} :: { [any]: Tank }
	self.list = {} :: { Tank }
	self.shells = {} :: { [number]: Shell }
	self.mines = {} :: { [number]: Mine }
	self.outs = {} :: { { any } }
	self.nextId = 0
	self.startAt = math.huge

	-- Shuffled into the spawn spots (the first N spots are spread out for any N).
	local order = table.clone(players)
	local rng = Random.new()
	for index = #order, 2, -1 do
		local other = rng:NextInteger(1, index)
		order[index], order[other] = order[other], order[index]
	end
	local spawns = self.field.Spawns
	local info = {}
	for index, player in order do
		local spot = spawns[(index - 1) % #spawns + 1]
		local x, z = spot[1], spot[2]
		local heading = math.atan2(x, z) -- facing the middle
		heading = math.round(heading / (math.pi / 4)) * (math.pi / 4)
		local tank: Tank = {
			Player = player,
			Id = player.UserId,
			Slot = (index - 1) % #TankField.COLORS + 1,
			Bot = BotRegistry.IsBot(player),
			X = x,
			Z = z,
			H = heading,
			V = 0,
			Rev = false,
			W = 0,
			LastH = heading,
			Aim = heading,
			MX = 0,
			MZ = 0,
			Seq = 0,
			SeqAt = 0,
			Lag = 0,
			Out = false,
			Shells = 0,
			LastShot = -math.huge,
			Mines = 0,
			LastMine = -math.huge,
			Hits = 0,
		}
		self.tanks[player] = tank
		table.insert(self.list, tank)
		table.insert(info, { tank.Id, tank.Slot })
		ctx:SetScoreText(player, "0 hits")
	end
	ctx:SetSharedJSON("Field", {
		m = self.mapName,
		o = { self.origin.X, self.origin.Y, self.origin.Z },
		k = info,
	})
	self:_buildArena()
	ctx:ShareTemplate("TanksTank", MeshLibrary.Get("TanksTank"))
	ctx:ShareTemplate("TanksShell", MeshLibrary.Get("TanksShell"))
	ctx:ShareTemplate("TanksMine", MeshLibrary.Get("TanksMine"))

	ctx.Hooks.CharacterReady = function(player)
		local tank = self.tanks[player]
		if tank and tank.Bot and not tank.Out then
			self:_placeBot(tank)
		end
	end
	ctx.Hooks.Eliminated = function(player, reason)
		-- Out some other way (their character died, they reset): the tank goes up too.
		local tank = self.tanks[player]
		if tank and not tank.Out then
			tank.Out = true
			tank.OutAt = ctx:Now()
			ctx:Fire(nil, "Out", tank.Id, round(tank.X, 0.01), round(tank.Z, 0.01), 0, reason)
		end
	end
	ctx.Hooks.PlayerLeft = function(player)
		local tank = self.tanks[player]
		if tank and not tank.Out then
			tank.Out = true
			tank.OutAt = ctx:Now()
			ctx:Fire(nil, "Gone", tank.Id)
			self:_status()
		end
	end

	local points = {}
	for _, player in players do
		local tank = self.tanks[player]
		table.insert(points, self:_seat(tank) - Vector3.new(0, 3, 0))
	end
	ctx:SpawnAll(points, true)
	for _, tank in self.list do
		if tank.Bot then
			self:_placeBot(tank)
		end
	end
	self:_share()
	ctx:SetStatus("Get ready to roll!")
end

function Tanks:Start()
	local ctx = self.context
	self.startAt = ctx:Now()
	ctx:SetShared("GoAt", self.startAt)
	-- Players whose character never loaded aren't in the round: no tank for them.
	for _, tank in self.list do
		if not ctx:State(tank.Player) and not tank.Out then
			tank.Out = true
			ctx:Fire(nil, "Gone", tank.Id)
		end
	end
	for _, player in ctx:GetPlayers() do
		ctx:SetWalkSpeed(player, 0)
	end

	ctx:OnAction("In", function(player, seq, mx, mz, aim)
		local tank = self.tanks[player]
		if not tank or tank.Out or not finite(seq) or seq <= tank.Seq or not finite(mx) or not finite(mz) then
			return
		end
		local length = math.sqrt(mx * mx + mz * mz)
		if length > 1 then
			mx, mz = mx / length, mz / length
		end
		tank.MX, tank.MZ = mx, mz
		if finite(aim) then
			tank.Aim = TankField.Wrap(aim)
		end
		tank.Seq = seq
		tank.SeqAt = ctx:Now()
	end, { Interval = 0.02 })

	ctx:OnAction("Fire", function(player, aim, pressedAt, token)
		self:_fire(player, aim, pressedAt, token)
	end, { Interval = 0.1 })

	ctx:OnAction("Mine", function(player)
		self:_layMine(player)
	end, { Interval = 0.25 })

	ctx:Heartbeat(function(dt)
		self:_step(dt)
	end)
	ctx:Loop(function()
		self:_share()
		return SHARE_EVERY
	end)
	ctx:Loop(function()
		for _, tank in self.list do
			if not tank.Bot then
				tank.Lag = math.clamp(ping(tank.Player) / 2, 0, MAX_LAG)
			end
		end
		return 1
	end)
	self:_status()
end

-- Controls ------------------------------------------------------------------------------------------

function Tanks:_fire(player: any, aim: any, pressedAt: any, token: any)
	local ctx = self.context
	local tank = self.tanks[player]
	if not tank or tank.Out or not finite(aim) then
		return
	end
	local now = ctx:Now()
	if tank.Shells >= TankField.MAX_SHELLS or now - tank.LastShot < TankField.RELOAD - 0.05 then
		ctx:Fire(player, "Dud", if type(token) == "number" then token else 0)
		return
	end
	-- Timed from the press (it can't reach back further than its one-way trip, plus a little
	-- jitter), from where the tank is now: that's where the shooter's own screen had it.
	local oneWay = ping(player) / 2
	local at = now - oneWay
	if finite(pressedAt) then
		at = math.clamp(pressedAt, now - oneWay - 0.1, now)
	end
	at = math.max(at, self.startAt)
	aim = TankField.Wrap(aim)
	tank.Aim = aim
	tank.Shells += 1
	tank.LastShot = now
	self.nextId += 1
	local t0 = at - TankField.MUZZLE / SPEED
	local path = TankField.Path(self.field, tank.X, tank.Z, aim)
	local shell: Shell = {
		Id = self.nextId,
		Owner = tank,
		T0 = t0,
		Path = path,
		End = t0 + path.Length / SPEED,
		Prev = t0,
		Aim = aim,
		Dead = false,
		Counted = false,
	}
	self.shells[shell.Id] = shell
	self.shellsDirty = true
	ctx:Fire(nil, "Shot", shell.Id, tank.Id, t0, tank.X, tank.Z, aim, if type(token) == "number" then token else 0)
end

function Tanks:_layMine(player: any)
	local ctx = self.context
	local tank = self.tanks[player]
	if not tank or tank.Out then
		return
	end
	local now = ctx:Now()
	if tank.Mines >= TankField.MAX_MINES or now - tank.LastMine < TankField.MINE_GAP then
		return
	end
	-- Not on top of another mine.
	for _, mine in self.mines do
		if not mine.Dead and (mine.X - tank.X) ^ 2 + (mine.Z - tank.Z) ^ 2 < 9 then
			return
		end
	end
	tank.Mines += 1
	tank.LastMine = now
	self.nextId += 1
	local mine: Mine = {
		Id = self.nextId,
		Owner = tank,
		X = tank.X,
		Z = tank.Z,
		ArmAt = now + TankField.MINE_ARM,
		BlowAt = now + TankField.MINE_FUSE,
		Clear = false,
		Dead = false,
	}
	self.mines[mine.Id] = mine
	self.minesDirty = true
	ctx:Fire(nil, "Mine", mine.Id, tank.Id, round(mine.X, 0.01), round(mine.Z, 0.01), mine.ArmAt, mine.BlowAt)
end

-- The simulation ------------------------------------------------------------------------------------

function Tanks:_step(dt: number)
	local ctx = self.context
	local now = ctx:Now()
	local prev = self.stepAt or now
	self.stepAt = now
	dt = math.clamp(dt, 0, 0.25)
	local field = self.field
	local list = self.list

	-- Drive every tank from its latest input, in small steps; blocks and other hulls push back.
	local steps = math.max(1, math.ceil(dt / (1 / 30)))
	local h = dt / steps
	for _ = 1, steps do
		for _, tank in list do
			if not tank.Out then
				TankField.Drive(tank, tank.MX, tank.MZ, h)
				TankField.Collide(field, tank)
			end
		end
		for i = 1, #list do
			local a = list[i]
			if a.Out then
				continue
			end
			for j = i + 1, #list do
				local b = list[j]
				if b.Out then
					continue
				end
				local depth, nx, nz = TankField.HullOverlap(a, b)
				if depth then
					a.X += nx * depth / 2
					a.Z += nz * depth / 2
					b.X -= nx * depth / 2
					b.Z -= nz * depth / 2
					TankField.Collide(field, a)
					TankField.Collide(field, b)
				end
			end
		end
	end
	for _, tank in list do
		if not tank.Out then
			tank.W = if dt > 0 then TankField.Wrap(tank.H - tank.LastH) / dt else 0
			tank.LastH = tank.H
			if tank.Bot then
				self:_placeBot(tank)
			end
		end
	end

	self:_stepShells(prev, now)
	self:_stepMines(now)
	self:_flushOuts()
	self:_shareShots()
end

-- Live mines and shells as shared state too (the events are only cues): a screen that starts late
-- (a slow phone, someone rejoining or watching) still draws every mine and shell that's out.
function Tanks:_shareShots()
	local ctx = self.context
	if self.minesDirty then
		self.minesDirty = false
		local list = {}
		for id, mine in self.mines do
			if not mine.Dead then
				list[tostring(id)] = {
					mine.Owner.Id,
					round(mine.X, 0.01),
					round(mine.Z, 0.01),
					round(mine.ArmAt, 0.001),
					round(mine.BlowAt, 0.001),
				}
			end
		end
		ctx:SetSharedJSON("Mines", list)
	end
	if self.shellsDirty then
		self.shellsDirty = false
		local now = ctx:Now()
		local list = {}
		for id, shell in self.shells do
			if not shell.Dead and now < shell.End then
				local first = shell.Path.Segments[1]
				list[tostring(id)] = {
					shell.Owner.Id,
					shell.T0,
					first.X,
					first.Z,
					shell.Aim,
				}
			end
		end
		ctx:SetSharedJSON("Shells", list)
	end
end

-- The first point (path distance) at which a shell's flight between s0 and s1 touches a hull.
local function hullHit(path: TankField.Path, s0: number, s1: number, tank: Tank): number?
	s0 = math.max(s0, 0)
	s1 = math.min(s1, path.Length)
	if s1 <= s0 then
		return nil
	end
	for _, segment in path.Segments do
		local a = math.max(s0, segment.S)
		local b = math.min(s1, segment.S + segment.Length)
		if b > a then
			local ua, ub = a - segment.S, b - segment.S
			local u = TankField.SegmentHitsHull(
				tank,
				segment.X + segment.DX * ua,
				segment.Z + segment.DZ * ua,
				segment.X + segment.DX * ub,
				segment.Z + segment.DZ * ub,
				TankField.SHELL_RADIUS
			)
			if u then
				return a + (b - a) * u
			end
		end
	end
	return nil
end

-- Distance from a point to the segment a-b.
-- Distance from a point to the segment a-b, and where along it (0..1) it's closest.
local function segmentDistance(px: number, pz: number, ax: number, az: number, bx: number, bz: number): (number, number)
	local dx, dz = bx - ax, bz - az
	local length2 = dx * dx + dz * dz
	local t = if length2 > 1e-9 then math.clamp(((px - ax) * dx + (pz - az) * dz) / length2, 0, 1) else 0
	local cx, cz = ax + dx * t - px, az + dz * t - pz
	return math.sqrt(cx * cx + cz * cz), t
end

function Tanks:_popShell(shell: Shell, s: number, kind: string)
	if shell.Dead then
		return
	end
	shell.Dead = true
	self.shellsDirty = true
	if not shell.Counted then
		shell.Counted = true
		shell.Owner.Shells = math.max(0, shell.Owner.Shells - 1)
	end
	local x, z = TankField.At(shell.Path, s)
	self.context:Fire(nil, "Pop", shell.Id, round(x, 0.01), round(z, 0.01), kind)
end

function Tanks:_stepShells(prev: number, now: number)
	local list = self.list
	local radius = TankField.SHELL_RADIUS
	for id, shell in self.shells do
		if shell.Dead then
			self.shells[id] = nil
			continue
		end
		local path = shell.Path
		-- Tanks, each judged at its own screen's time (players: the shell as it was a one-way trip ago).
		local bestS, bestTank = math.huge, nil
		for _, tank in list do
			if tank.Out then
				continue
			end
			local s0 = (shell.Prev - tank.Lag - shell.T0) * SPEED
			local s1 = (now - tank.Lag - shell.T0) * SPEED
			if tank == shell.Owner then
				s0 = math.max(s0, path.Bounce, TankField.OWN_SAFE * SPEED)
			end
			local s = hullHit(path, s0, s1, tank)
			if s and s < bestS then
				bestS, bestTank = s, tank
			end
		end
		if bestTank then
			if now < self.startAt + TankField.SHIELD then
				self:_popShell(shell, bestS, "shield")
			else
				self:_popShell(shell, bestS, "tank")
				self:_knockOut(bestTank, shell.Owner, "shelled")
			end
			continue
		end
		-- Mines it flies into (only once it's out of the barrel, as clients draw it), popping where
		-- it meets the first one.
		local s0 = math.max((shell.Prev - shell.T0) * SPEED, TankField.SHELL_SHOWN)
		local s1 = math.min((now - shell.T0) * SPEED, path.Length)
		local hitS, hitMine = math.huge, nil
		TankField.Pieces(path, s0, s1, function(ax, az, bx, bz, sa, sb)
			for _, mine in self.mines do
				if mine.Dead then
					continue
				end
				local d, t = segmentDistance(mine.X, mine.Z, ax, az, bx, bz)
				if d <= TankField.MINE_RADIUS + radius then
					local s = sa + (sb - sa) * t
					if s < hitS then
						hitS, hitMine = s, mine
					end
				end
			end
		end)
		if hitMine then
			self:_popShell(shell, hitS, "mine")
			self:_blast(hitMine, now, shell.Owner)
		end
		if shell.Dead then
			continue
		end
		if not shell.Counted and now >= shell.End then
			-- Hit its second wall: the slot is free again (the record stays a moment longer, for
			-- players judged a little in the past).
			shell.Counted = true
			shell.Owner.Shells = math.max(0, shell.Owner.Shells - 1)
			self.shellsDirty = true
		end
		shell.Prev = now
		if now - MAX_LAG > shell.End then
			self.shells[id] = nil
		end
	end
	-- Shells that meet pop each other (closest approach over this frame).
	local live = {}
	for _, shell in self.shells do
		if not shell.Dead and now < shell.End and now > shell.T0 then
			table.insert(live, shell)
		end
	end
	local shown = TankField.SHELL_SHOWN / SPEED -- seconds from T0 until a shell leaves its barrel
	for i = 1, #live do
		local a = live[i]
		if a.Dead or now < a.T0 + shown then
			continue
		end
		for j = i + 1, #live do
			local b = live[j]
			if b.Dead or now < b.T0 + shown then
				continue
			end
			-- Over the part of this frame when both are out of their barrels: the closest approach of
			-- their relative motion.
			local from = math.max(prev, a.T0 + shown, b.T0 + shown)
			local a0x, a0z = TankField.At(a.Path, (from - a.T0) * SPEED)
			local a1x, a1z = TankField.At(a.Path, (now - a.T0) * SPEED)
			local b0x, b0z = TankField.At(b.Path, (from - b.T0) * SPEED)
			local b1x, b1z = TankField.At(b.Path, (now - b.T0) * SPEED)
			local rx0, rz0 = b0x - a0x, b0z - a0z
			local rx1, rz1 = b1x - a1x, b1z - a1z
			local d, t = segmentDistance(0, 0, rx0, rz0, rx1, rz1)
			if d <= 2 * radius + 0.3 then
				local at = from + (now - from) * t
				self:_popShell(a, (at - a.T0) * SPEED, "shell")
				self:_popShell(b, (at - b.T0) * SPEED, "shell")
				break
			end
		end
	end
end

function Tanks:_stepMines(now: number)
	for id, mine in self.mines do
		if mine.Dead then
			self.mines[id] = nil
			continue
		end
		local blow = now >= mine.BlowAt
		if not blow then
			for _, tank in self.list do
				if tank.Out then
					continue
				end
				local near = TankField.Near(tank, mine.X, mine.Z, TankField.MINE_TRIGGER)
				if tank == mine.Owner then
					if not near then
						mine.Clear = true
					elseif mine.Clear and now >= mine.ArmAt then
						blow = true
						break
					end
				elseif near and now >= mine.ArmAt then
					blow = true
					-- Whoever drove onto it set it off: if it takes its layer too, that's their hit.
					mine.Detonator = mine.Detonator or tank
					break
				end
			end
		end
		if blow then
			self:_blast(mine, now, mine.Detonator)
		end
	end
end

-- A mine goes off: every tank, shell and mine in the blast.
-- Whether a blast at (x, z) catches a tank. A player's own screen runs their tank a one-way trip
-- ahead of the server, so a player is spared when either where the server has them or where their
-- screen showed them is outside the ring (the benefit of the doubt, like shells).
function Tanks:_caught(tank: Tank, x: number, z: number, radius: number): boolean
	if not TankField.Near(tank, x, z, radius) then
		return false
	end
	if tank.Bot or tank.Lag <= 0 then
		return true
	end
	local ahead = {
		X = tank.X - math.sin(tank.H) * tank.V * tank.Lag,
		Z = tank.Z - math.cos(tank.H) * tank.V * tank.Lag,
		H = tank.H,
		V = tank.V,
		Rev = tank.Rev,
	}
	return TankField.Near(ahead, x, z, radius)
end

-- A mine goes off: every tank, shell and mine in the blast. `detonator` is whose shell (or blast)
-- set it off: when the blast takes the mine's own layer, that's who gets the hit.
function Tanks:_blast(mine: Mine, now: number, detonator: Tank?)
	if mine.Dead then
		return
	end
	local ctx = self.context
	mine.Dead = true
	mine.Owner.Mines = math.max(0, mine.Owner.Mines - 1)
	ctx:Fire(nil, "Boom", mine.Id, round(mine.X, 0.01), round(mine.Z, 0.01))
	self.minesDirty = true
	local blast = TankField.MINE_BLAST
	if now >= self.startAt + TankField.SHIELD then
		for _, tank in self.list do
			if not tank.Out and self:_caught(tank, mine.X, mine.Z, blast) then
				local by = mine.Owner
				if tank == mine.Owner and detonator and detonator ~= tank then
					by = detonator
				end
				self:_knockOut(tank, by, "mined")
			end
		end
	end
	for _, shell in self.shells do
		if not shell.Dead and now < shell.End then
			local s = math.max(now - shell.T0, 0) * SPEED
			local x, z = TankField.At(shell.Path, s)
			if (x - mine.X) ^ 2 + (z - mine.Z) ^ 2 <= (blast + TankField.SHELL_RADIUS) ^ 2 then
				self:_popShell(shell, s, "blast")
			end
		end
	end
	for _, other in self.mines do
		if not other.Dead and (other.X - mine.X) ^ 2 + (other.Z - mine.Z) ^ 2 <= blast * blast then
			other.BlowAt = math.min(other.BlowAt, now + TankField.CHAIN_DELAY)
			-- A chain goes back to whoever started it.
			other.Detonator = other.Detonator or detonator or mine.Owner
		end
	end
end

-- Marks a tank out now; the knock-outs of one step are applied together (see _flushOuts).
function Tanks:_knockOut(tank: Tank, by: Tank?, cause: string)
	if tank.Out then
		return
	end
	tank.Out = true
	tank.OutAt = self.context:Now()
	table.insert(self.outs, { tank, by, cause })
end

function Tanks:_flushOuts()
	if #self.outs == 0 then
		return
	end
	local ctx = self.context
	local batch = self.outs
	self.outs = {}
	-- Credit first (scoring stops once the round ends), then everyone this step caught goes out.
	for _, entry in batch do
		local tank, by = entry[1], entry[2]
		if by and by ~= tank and ctx:State(by.Player) then
			by.Hits += 1
			ctx:AddScore(by.Player, 1)
			ctx:SetScoreText(by.Player, if by.Hits == 1 then "1 hit" else `{by.Hits} hits`)
		end
	end
	for _, entry in batch do
		local tank, by, cause = entry[1], entry[2], entry[3]
		ctx:Fire(
			nil,
			"Out",
			tank.Id,
			round(tank.X, 0.01),
			round(tank.Z, 0.01),
			if by and by ~= tank then by.Id else 0,
			cause
		)
	end
	for _, entry in batch do
		ctx:Eliminate(entry[1].Player, entry[3])
	end
	self:_status()
	self:_share()
end

function Tanks:_status()
	local ctx = self.context
	local alive = 0
	for _, tank in self.list do
		if not tank.Out then
			alive += 1
		end
	end
	ctx:SetStatus(if alive == 1 then "1 tank left!" else `{alive} tanks left`)
end

function Tanks:_share()
	local ctx = self.context
	local list = {}
	for _, tank in self.list do
		if tank.Out then
			continue
		end
		local entry = {
			round(tank.X, 0.01),
			round(tank.Z, 0.01),
			round(tank.H, 0.001),
			round(tank.Aim, 0.001),
			round(tank.V, 0.01),
			round(tank.W, 0.001),
		}
		if not tank.Bot then
			entry[7] = tank.Seq
			entry[8] = round(tank.SeqAt, 0.0001)
		end
		list[tostring(tank.Id)] = entry
	end
	ctx:SetSharedJSON("Tanks", { t = round(self.stepAt or ctx:Now(), 0.0001), k = list })
end

-- Results -------------------------------------------------------------------------------------------

-- Survivors first (the last tank standing, or everyone still rolling at the bell, by hits), then
-- the rest by hits and how long they lasted.
function Tanks:GetResults()
	local ctx = self.context
	local entries = {}
	local elapsed = ctx:Elapsed()
	for player, state in ctx.Participants do
		if not player.Parent then
			continue
		end
		local tank = self.tanks and self.tanks[player]
		local hits = if tank then tank.Hits else 0
		local alive = state.Alive and tank ~= nil and not tank.Out
		-- (From the tank's own knock-out time: everyone one blast caught went out together.)
		local lasted = if alive
			then elapsed
			elseif tank and tank.OutAt and self.startAt < math.huge then math.max(tank.OutAt - self.startAt, 0)
			else state.EliminatedAt or 0
		local hitText = if hits == 1 then "1 hit" else `{hits} hits`
		table.insert(entries, {
			Player = player,
			Rank = (if alive then 1e6 else 0) + hits * 1000 + math.min(math.floor(lasted * 10) / 10, 999),
			ScoreText = if alive then `Still rolling! • {hitText}` else `{hitText} • lasted {math.floor(lasted)}s`,
			BestScore = hits,
			Survived = lasted,
		})
	end
	return { Entries = entries }
end

return Tanks

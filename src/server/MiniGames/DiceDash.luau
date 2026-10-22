-- Dice Dash (Luck, 60s, 1-12 players). After the board-game minigames of Mario Party (a board you
-- race along by dice rolls, with springs, slips and trapdoors): a 60-second board game on a giant
-- tabletop in a sunny meadow. Everyone rolls a giant die at the same time and hops along one
-- winding path of 40 big tiles. BOOST (+3, a springboard), SLIP (-2, a banana peel), CANNON (shoots
-- you to the next cannon ahead; the last one fires at the FINISH), SWAP (the rare golden tile: trade
-- places with the leader), ? (a random event: everyone behind you +2, a gust blows the leader back
-- 3, or last place jumps ahead 5) and TRAPDOOR (back to START). Tiles you only pass over do nothing.
-- First to FINISH wins (no exact landing); the rest rank by finish order, then by how far along.
-- The round ends when 3 racers are home (everyone, in a smaller race) or time runs out.
--
-- How it works: the server owns everything. A turn starts for everyone at once ("Turn": its number,
-- when it started, the roll deadline); a die spins over each racer and ROLL (api:Action "Roll": a
-- button, a tap or click, or the jump button) stops it. The server picks every number (a fair d6,
-- never the client) and anyone who hasn't rolled after Board.ROLL_WINDOW seconds rolls
-- automatically. Then the server plans the whole turn at once: each racer's walk, the tiles they
-- land on, and the effects in order (lone effects together, then SWAP and ? one at a time, since
-- they depend on where everyone is), as a list of timed moves per racer (Logic/DiceDashBoard).
-- Clients draw every character hopping along those moves (smooth, the same plan for everyone) and
-- show the callouts at the moment each effect happens ("Event"). Characters are frozen (no walking
-- or jumping; each client poses its own character on the board, the server poses the bots), so
-- nobody can leave the board. Landing after an effect never fires a second tile.
--
-- Bots press ROLL through ctx:BotAction with human-like delays (Bots/DiceDash.luau) and the same
-- server rules move them, so every tile treats bots exactly like players (it's all luck: skill
-- changes nothing). Tiles and pads collide with their drawn shapes; every other prop on the board
-- and around it is decoration only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.Logic.DiceDashBoard)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local Shapes = require(script.Parent.Parent.World.Shapes)

local DiceDash = MiniGame.Define("DiceDash", { Results = "Score" })

local GROUND = -34 -- the meadow under the table, below the tabletop
local TILE_BASE = 0.1 -- tiles sit this far up in the felt (their top is Board.TOP)
local STAGGER = 0.45 -- seconds at least between one SWAP / ? effect and the next
local ROLL_INTERVAL = 0.15

-- Racer colours, one per racer number (the number on the badge is the second cue).
local COLORS = {
	Color3.fromRGB(255, 80, 90),
	Color3.fromRGB(70, 150, 255),
	Color3.fromRGB(255, 200, 50),
	Color3.fromRGB(90, 210, 110),
	Color3.fromRGB(190, 110, 255),
	Color3.fromRGB(255, 140, 50),
	Color3.fromRGB(60, 215, 210),
	Color3.fromRGB(255, 120, 200),
	Color3.fromRGB(160, 200, 60),
	Color3.fromRGB(140, 120, 255),
	Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(150, 105, 75),
}

local TILE_PROPS = {
	[Board.PLAIN] = "DiceDashTile",
	[Board.BOOST] = "DiceDashTileBoost",
	[Board.SLIP] = "DiceDashTileSlip",
	[Board.CANNON] = "DiceDashTileCannon",
	[Board.SWAP] = "DiceDashTileSwap",
	[Board.EVENT] = "DiceDashTileEvent",
	[Board.TRAP] = "DiceDashTileTrap",
}

type Racer = {
	Player: any,
	Number: number,
	Pos: number,
	Moves: { Board.Move },
	Roll: number?,
	Auto: boolean?,
	Finish: number?,
	Place: number?,
	Gone: boolean,
	Shown: number,
}

local rng = Random.new()

local function color3(color: Color3): { number }
	return { math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5) }
end

function DiceDash:_at(offset: Vector3, yaw: number?): CFrame
	return CFrame.new(self.origin + offset) * CFrame.Angles(0, yaw or 0, 0)
end

-- A tile's raised icon is too low to stand on: only its plate is solid.
function DiceDash:_flatIcon(model: Instance)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name == "Icon" then
			part.CanCollide = false
			part.CanQuery = false
		end
	end
end

-- The arena -------------------------------------------------------------------------------------------

function DiceDash:_buildArena()
	local ctx = self.context
	local arena = ctx.Arena
	local origin = self.origin

	-- The meadow far below: grass, a ring of trees and flower bushes, hills on the horizon.
	Build.Part({
		Name = "Grass",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 640, 640),
		CFrame = CFrame.new(origin + Vector3.new(0, GROUND - 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(106, 188, 82),
		Material = Enum.Material.Grass,
		Parent = arena,
	})
	local leafColors = {
		Color3.fromRGB(80, 190, 90),
		Color3.fromRGB(110, 200, 80),
		Color3.fromRGB(70, 165, 95),
		Color3.fromRGB(140, 205, 85),
	}
	for index = 0, 25 do
		local angle = (index + rng:NextNumber(-0.35, 0.35)) / 26 * math.pi * 2
		local distance = rng:NextNumber(125, 190)
		MeshLibrary.Get("Tree", {
			Scale = rng:NextNumber(2.4, 3.6),
			Colors = { Leaves = leafColors[rng:NextInteger(1, #leafColors)] },
			CFrame = self:_at(
				Vector3.new(math.cos(angle) * distance * 1.2, GROUND, math.sin(angle) * distance),
				rng:NextNumber(0, math.pi * 2)
			),
			Parent = arena,
		})
	end
	local flowerColors = {
		Color3.fromRGB(255, 130, 190),
		Color3.fromRGB(255, 220, 90),
		Color3.fromRGB(180, 140, 255),
		Color3.fromRGB(255, 255, 255),
	}
	for index = 0, 15 do
		local angle = (index + rng:NextNumber(-0.4, 0.4)) / 16 * math.pi * 2
		local distance = rng:NextNumber(98, 118)
		MeshLibrary.Get("Bush", {
			Scale = rng:NextNumber(1.6, 2.4),
			Colors = { Flowers = flowerColors[rng:NextInteger(1, #flowerColors)] },
			CFrame = self:_at(
				Vector3.new(math.cos(angle) * distance * 1.15, GROUND, math.sin(angle) * distance * 0.9),
				rng:NextNumber(0, math.pi * 2)
			),
			Parent = arena,
		})
	end
	for index = 0, 9 do
		local angle = (index + rng:NextNumber(-0.3, 0.3)) / 10 * math.pi * 2
		local distance = rng:NextNumber(250, 290)
		local size = Vector3.new(rng:NextNumber(170, 240), rng:NextNumber(60, 100), rng:NextNumber(120, 170))
		local hill = Build.Part({
			Name = "Hill",
			Size = size,
			CFrame = CFrame.new(
				origin + Vector3.new(math.cos(angle) * distance, GROUND - size.Y * 0.2, math.sin(angle) * distance)
			) * CFrame.Angles(0, -angle + math.pi / 2, 0),
			Color = Color3.fromRGB(96, 176, 86):Lerp(Color3.fromRGB(70, 140, 90), rng:NextNumber(0, 1)),
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = arena,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = hill
	end

	-- The giant table: a rounded wooden top with a green felt mat, on four turned legs.
	Shapes.Slab(Vector3.new(178, 4, 118), 5, {
		Name = "Tabletop",
		CFrame = self:_at(Vector3.new(0, -2.3, 0)),
		Color = Color3.fromRGB(176, 118, 72),
		Material = Enum.Material.WoodPlanks,
		Parent = arena,
	})
	Shapes.Slab(Vector3.new(156, 0.6, 100), 6, {
		Name = "Felt",
		CFrame = self:_at(Vector3.new(0, -0.1, 0)),
		Color = Color3.fromRGB(64, 150, 96),
		Material = Enum.Material.Fabric,
		Parent = arena,
	})
	for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		MeshLibrary.Get("DiceDashTableLeg", {
			CFrame = self:_at(Vector3.new(corner.X * 78, GROUND, corner.Y * 48)),
			Parent = arena,
		})
	end

	-- The path: one tile per index, START and FINISH on their pads under their arches.
	local kinds = self.kinds
	for index = 1, Board.LAST - 1 do
		local x, z, yaw = Board.Tile(index)
		local kind = Board.KindAt(kinds, index)
		local tile = MeshLibrary.Get(TILE_PROPS[kind] or "DiceDashTile", {
			CFrame = self:_at(Vector3.new(x, TILE_BASE, z), yaw),
			Parent = arena,
		})
		tile.Name = `Tile{index}`
		self:_flatIcon(tile)
		-- (springboards and cannons stand beside their tiles, on the outside of the path)
		local side = if (z > 0) == (x > 0) then 1 else -1
		if kind == Board.BOOST then
			MeshLibrary.Get("DiceDashSpring", {
				CFrame = self:_at(Vector3.new(x, 0, z), yaw) * CFrame.new(side * (Board.TILE / 2 + 2), 0, 0),
				Parent = arena,
			})
		elseif kind == Board.CANNON then
			MeshLibrary.Get("DiceDashCannon", {
				CFrame = self:_at(Vector3.new(x, 0, z), yaw) * CFrame.new(side * (Board.TILE / 2 + 2.8), 0, 0),
				Parent = arena,
			})
		end
	end
	for _, index in { 0, Board.LAST } do
		local x, z, yaw = Board.Tile(index)
		local finish = index == Board.LAST
		self:_flatIcon(MeshLibrary.Get(if finish then "DiceDashPadFinish" else "DiceDashPadStart", {
			CFrame = self:_at(Vector3.new(x, TILE_BASE, z), yaw),
			Parent = arena,
		}))
		-- The arch stands over the pad's inner edge, facing along the path (its posts off the pad).
		local arch = MeshLibrary.Get(if finish then "DiceDashArchFinish" else "DiceDashArchStart", {
			CFrame = self:_at(Vector3.new(x, 0, z), yaw)
				* CFrame.new(0, 0, if finish then Board.PAD / 2 - 1 else -(Board.PAD / 2 - 1)),
			Parent = arena,
		})
		local banner = arch:FindFirstChild("Banner", true)
		if banner and banner:IsA("BasePart") then
			for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
				local gui = Instance.new("SurfaceGui")
				gui.Face = face
				gui.CanvasSize = Vector2.new(400, 100)
				gui.LightInfluence = 0.3
				local label = Instance.new("TextLabel")
				label.BackgroundTransparency = 1
				label.Size = UDim2.fromScale(1, 1)
				label.Font = Enum.Font.FredokaOne
				label.TextScaled = true
				label.Text = if finish then "FINISH" else "START"
				label.TextColor3 = if finish then Color3.fromRGB(255, 90, 100) else Color3.fromRGB(255, 255, 255)
				local stroke = Instance.new("UIStroke")
				stroke.Thickness = 3
				stroke.Color = Color3.fromRGB(30, 24, 40)
				stroke.Parent = label
				label.Parent = gui
				gui.Parent = banner
			end
		end
	end
	-- The FINISH cannon (where the last cannon fires you), behind the FINISH pad.
	do
		local x, z, yaw = Board.Tile(Board.LAST)
		MeshLibrary.Get("DiceDashCannon", {
			Scale = 1.3,
			CFrame = self:_at(Vector3.new(x, 0, z), yaw)
				* CFrame.new(0, 0, -Board.PAD / 2 - 3.5)
				* CFrame.Angles(0, math.pi, 0),
			Parent = arena,
		})
	end

	-- Oversized board-game clutter around the board (decoration only).
	local function prop(name: string, x: number, z: number, yaw: number, scale: number?, colors: any?)
		MeshLibrary.Get(name, {
			Scale = scale,
			Colors = colors,
			CFrame = self:_at(Vector3.new(x, 0, z), yaw),
			Parent = arena,
		})
	end
	prop("DiceDashSpinner", 72, 2, 0.3)
	prop("DiceDashRuleBook", 72, -30, -0.35)
	prop("DiceDashCards", 72, 32, 0.5)
	prop("DiceDashCards", -78, -44, 2.4, 0.8)
	prop("DiceDashDie", 62, -48, 0.6, 1.4, { Body = Color3.fromRGB(250, 248, 240), Pips = Color3.fromRGB(40, 36, 60) })
	prop(
		"DiceDashDie",
		-76,
		44,
		1.9,
		1.2,
		{ Body = Color3.fromRGB(255, 90, 100), Pips = Color3.fromRGB(255, 255, 255) }
	)
	local pawnSpots = {
		{ 40, 50, 0.2 },
		{ -10, 51, 1.2 },
		{ -40, -51, 2.2 },
		{ 18, -51, 0.4 },
		{ 82, -14, 0.9 },
		{ 82, 16, 1.6 },
	}
	for index, spot in pawnSpots do
		prop("DiceDashPawn", spot[1], spot[2], spot[3], 1, { Body = COLORS[(index * 5) % #COLORS + 1] })
	end
end

-- Round -----------------------------------------------------------------------------------------------

function DiceDash:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn" -- nothing knocks anyone out
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y + GROUND - 30
	self.origin = ctx.Origin.Position
	self.kinds = Board.Deal(function(lo, hi)
		return rng:NextInteger(lo, hi)
	end)
	self.racers = {} :: { [any]: Racer }
	self.finished = 0
	self.turn = 0
	self.phase = "Ready"
	self.racing = false
	self.nextTurn = 0
	self.turnAt = 0
	self.rollEnd = 0
	self.turnTime = Board.TurnTime(1)

	local players = table.clone(ctx:GetPlayers())
	for index = #players, 2, -1 do -- racer numbers in a random order
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local roster = {}
	for index, player in players do
		local racer: Racer = {
			Player = player,
			Number = index,
			Pos = 0,
			Moves = {},
			Gone = false,
			Shown = 0,
		}
		self.racers[player] = racer
		table.insert(roster, {
			U = player.UserId,
			N = index,
			C = color3(COLORS[(index - 1) % #COLORS + 1]),
			Name = player.DisplayName,
		})
		ctx:SetScoreText(player, "START")
	end
	self:_buildArena()
	ctx:ShareTemplate("DiceDashDie", MeshLibrary.Get("DiceDashDie"))
	ctx:SetSharedJSON("Board", {
		O = { self.origin.X, self.origin.Y, self.origin.Z },
		K = self.kinds,
		R = roster,
	})
	ctx:SetShared("Stage", "Ready")
	self:_share()

	ctx.Hooks.CharacterReady = function(player)
		if self.racing then
			ctx:Freeze(player, true)
		end
		if BotRegistry.IsBot(player) then
			self:_placeBots(ctx:Now(), player)
		end
	end
	ctx.Hooks.Respawn = function(player)
		local racer = self.racers[player]
		return if racer then self:_at(Board.Spot(racer.Pos)) else nil
	end
	ctx.Hooks.PlayerLeft = function(player)
		self:_leave(player)
	end

	local points = {}
	local count = #ctx:GetPlayers()
	local _, _, startYaw = Board.Tile(0)
	for index, player in ctx:GetPlayers() do
		local racer = self.racers[player]
		local slot = if racer then racer.Number else index
		table.insert(points, self:_at(Board.Spot(0) + Board.Ring(slot, count, true), startYaw))
	end
	ctx:SpawnAll(points, true)
	self:_placeBots(ctx:Now())
	ctx:SetStatus("🎲 Roll the dice and race to the FINISH!")
end

function DiceDash:Start()
	local ctx = self.context
	self.racing = true
	self.startAt = ctx:Now()
	local racing = 0
	for player, racer in self.racers do
		if not ctx:State(player) then
			racer.Gone = true -- left (or never got a character) before GO
		else
			racing += 1
		end
	end
	self.turnTime = Board.TurnTime(racing)
	for _, player in ctx:GetPlayers() do
		ctx:Freeze(player, true) -- (GO unfreezes everyone: here nobody walks)
	end
	ctx:SetShared("Stage", "Race")

	ctx:OnAction("Roll", function(player)
		self:_roll(player)
	end, { Interval = ROLL_INTERVAL })

	self:_beginTurn()
	local lastBots, lastScore = 0, 0
	ctx:Heartbeat(function()
		local now = ctx:Now()
		if not self.ending then
			if self.phase == "Roll" then
				if now >= self.rollEnd or self:_allRolled() then
					self:_resolve()
				end
			elseif self.phase == "Wait" and now >= self.nextTurn then
				if ctx:TimeIsUp() then
					self.phase = "Over"
				else
					self:_beginTurn()
				end
			end
		end
		if now - lastBots >= 1 / 15 then
			lastBots = now
			self:_placeBots(now)
		end
		if now - lastScore >= 0.25 then
			lastScore = now
			self:_score(now)
		end
	end)
end

function DiceDash:_active(racer: Racer): boolean
	return not racer.Gone and racer.Finish == nil and self.context:State(racer.Player) ~= nil
end

function DiceDash:_allRolled(): boolean
	local any = false
	for _, racer in self.racers do
		if self:_active(racer) then
			any = true
			if racer.Roll == nil then
				return false
			end
		end
	end
	-- (a short beat after the last press so its number shows before the hops)
	return any and self.context:Now() >= (self.lastPress or 0) + 0.35
end

function DiceDash:_beginTurn()
	local ctx = self.context
	local now = ctx:Now()
	self.turn += 1
	self.phase = "Roll"
	self.turnAt = now
	self.rollEnd = now + Board.ROLL_WINDOW
	self.lastPress = nil
	for _, racer in self.racers do
		racer.Roll = nil
		racer.Auto = nil
		racer.Moves = {}
	end
	ctx:SetSharedJSON("Turn", { N = self.turn, A = now, E = self.rollEnd })
	self:_share()
	ctx:SetStatus(`🎲 Turn {self.turn}: ROLL!`)
end

function DiceDash:_roll(player: any)
	local racer = self.racers[player]
	if self.phase ~= "Roll" or self.ending or not racer or not self:_active(racer) or racer.Roll ~= nil then
		return
	end
	racer.Roll = rng:NextInteger(1, 6) -- the server decides every roll
	self.lastPress = self.context:Now()
	self:_share()
end

-- Plans the whole turn: walks, then each landing tile's effect, as timed moves for every racer.
function DiceDash:_resolve()
	local ctx = self.context
	local now = ctx:Now()
	local kinds = self.kinds
	self.phase = "Move"
	local active = {}
	for _, racer in self.racers do
		if self:_active(racer) then
			if racer.Roll == nil then
				racer.Roll = rng:NextInteger(1, 6)
				racer.Auto = true
			end
			table.insert(active, racer)
		end
	end
	local moveAt = now + Board.SHOW
	local finishes = {}
	local lastEnd = moveAt
	local function move(racer: Racer, at: number, to: number, kind: string): number
		local entry: Board.Move = { a = at, f = racer.Pos, t = to, k = kind }
		table.insert(racer.Moves, entry)
		racer.Pos = to
		local ends = at + Board.Duration(entry)
		lastEnd = math.max(lastEnd, ends)
		if to >= Board.LAST and racer.Finish == nil then
			racer.Finish = ends
			table.insert(finishes, racer)
		end
		return ends
	end
	local function event(at: number, kind: string, text: string, users: { number }, tile: number?)
		ctx:Fire(nil, "Event", { At = at, K = kind, T = text, U = users, P = tile })
	end
	local function unfinished(): { Racer }
		local list = {}
		for _, racer in active do
			if racer.Finish == nil and not racer.Gone then
				table.insert(list, racer)
			end
		end
		return list
	end

	-- 1. Everyone hops their roll (FINISH needs no exact landing).
	local maxRoll = 0
	for _, racer in active do
		local roll = racer.Roll :: number
		maxRoll = math.max(maxRoll, roll)
		move(racer, moveAt, math.min(racer.Pos + roll, Board.LAST), "w")
	end
	local effectAt = moveAt + maxRoll * Board.HOP + 0.2

	-- 2. Lone effects (they only move the racer who landed), all at once.
	local landers = unfinished()
	table.sort(landers, function(a, b)
		return a.Pos > b.Pos
	end)
	local beatAt = effectAt
	local interactive = {}
	for _, racer in landers do
		local from = racer.Pos
		local kind = Board.KindAt(kinds, from)
		local name = racer.Player.DisplayName
		local id = racer.Player.UserId
		if kind == Board.BOOST then
			move(racer, effectAt, math.min(from + 3, Board.LAST), "b")
			event(effectAt, "BOOST", `BOOST! {name} +3`, { id }, from)
		elseif kind == Board.SLIP then
			move(racer, effectAt, math.max(from - 2, 0), "l")
			event(effectAt, "SLIP", `SLIP! {name} -2`, { id }, from)
		elseif kind == Board.CANNON then
			local target = Board.NextCannon(kinds, from)
			move(racer, effectAt, target, "c")
			local text = if target >= Board.LAST
				then `CANNON! {name} to the FINISH!`
				else `CANNON! {name} +{target - from}`
			event(effectAt, "CANNON", text, { id }, from)
		elseif kind == Board.TRAP then
			move(racer, effectAt, 0, "d")
			event(effectAt, "TRAP", `TRAPDOOR! {name} back to START`, { id }, from)
		elseif kind == Board.SWAP or kind == Board.EVENT then
			table.insert(interactive, racer)
		end
	end
	-- (an effect waits for everyone it moves to finish what they're doing; others run alongside)
	local function startFor(list: { Racer }): number
		local start = beatAt
		for _, other in list do
			start = math.max(start, Board.MovesEnd(other.Moves, 0) + 0.1)
		end
		beatAt = start + STAGGER
		return start
	end

	-- 3. SWAP and ? tiles in turn (each depends on where everyone is by then), alongside the rest.
	for _, racer in interactive do
		if racer.Finish ~= nil or racer.Gone then
			continue
		end
		local from = racer.Pos
		local kind = Board.KindAt(kinds, from)
		if kind ~= Board.SWAP and kind ~= Board.EVENT then
			continue -- (an earlier effect moved them off their tile)
		end
		local name = racer.Player.DisplayName
		local id = racer.Player.UserId
		local others = unfinished()
		if kind == Board.SWAP then
			local leader: Racer? = nil
			for _, other in others do
				if other ~= racer and other.Pos > from and (leader == nil or other.Pos > leader.Pos) then
					leader = other
				end
			end
			if leader then
				local theirs = leader.Pos
				local at = startFor({ racer, leader })
				move(racer, at, theirs, "x")
				move(leader, at, from, "x")
				event(at, "SWAP", `SWAP! {name} ↔ {leader.Player.DisplayName}`, { id, leader.Player.UserId }, from)
			else
				event(startFor({ racer }), "SWAP", `SWAP! {name} is already in front`, { id }, from)
			end
		else
			local roll = rng:NextInteger(1, 3)
			if roll == 1 then
				local behind = {}
				for _, other in others do
					if other.Pos < from then
						table.insert(behind, other)
					end
				end
				local at = startFor(behind)
				local moved = {}
				for _, other in behind do
					move(other, at, math.min(other.Pos + 2, Board.LAST), "j")
					table.insert(moved, other.Player.UserId)
				end
				local text = if #moved > 0 then `? Everyone behind {name} +2` else `? Nobody behind {name}`
				event(at, "EVENT", text, moved, from)
			elseif roll == 2 then
				local leader: Racer? = nil
				for _, other in others do
					if leader == nil or other.Pos > leader.Pos then
						leader = other
					end
				end
				if leader then
					local leaderName = leader.Player.DisplayName
					local at = startFor({ leader })
					move(leader, at, math.max(leader.Pos - 3, 0), "g")
					event(at, "GUST", `? GUST! {leaderName} blown back 3`, { leader.Player.UserId }, from)
				end
			else
				local last: Racer? = nil
				for _, other in others do
					if last == nil or other.Pos < last.Pos then
						last = other
					end
				end
				if last then
					local lastName = last.Player.DisplayName
					local at = startFor({ last })
					move(last, at, math.min(last.Pos + 5, Board.LAST), "j")
					event(at, "LAST", `? Last place {lastName} +5`, { last.Player.UserId }, from)
				end
			end
		end
	end

	-- 4. Finishers take their places in the order they arrive.
	table.sort(finishes, function(a, b)
		return (a.Finish :: number) < (b.Finish :: number)
	end)
	for _, racer in finishes do
		self.finished += 1
		racer.Place = self.finished
		local place = self.finished
		local at = racer.Finish :: number
		local player = racer.Player
		ctx:Delay(math.max(0, at - now), function()
			if racer.Gone then
				return
			end
			ctx:SetScoreText(player, `{Board.Ordinal(place)} · {string.format("%.1f", at - self.startAt)}s`)
			ctx:Fire(nil, "Finish", player.UserId, place)
			if place == 1 then
				ctx:Announce(`🏁 {player.DisplayName} wins the race!`, "success", 3)
				ctx:Sound("Victory")
			end
		end)
	end

	self.nextTurn = math.max(self.turnAt + self.turnTime, lastEnd + 0.6)
	self.phase = "Wait"
	ctx:SetSharedJSON("Turn", { N = self.turn, A = self.turnAt, E = self.rollEnd, M = moveAt })
	self:_share()
	ctx:SetStatus(`🎲 Turn {self.turn}`)
	self:_checkDone(lastEnd)
end

-- Every racer's tile, roll and this turn's moves for the clients.
function DiceDash:_share()
	local list = {}
	for player, racer in self.racers do
		if racer.Gone then
			continue
		end
		list[tostring(player.UserId)] = {
			P = racer.Pos,
			D = racer.Roll,
			Au = if racer.Auto then 1 else nil,
			M = if #racer.Moves > 0 then racer.Moves else nil,
			F = racer.Place,
		}
	end
	self.context:SetSharedJSON("Racers", { N = self.turn, R = list })
end

-- The standings: finishers by place, the rest by how far along they are (as they arrive).
function DiceDash:_score(now: number)
	local ctx = self.context
	for player, racer in self.racers do
		if racer.Gone or not ctx:State(player) then
			continue
		end
		local home = racer.Place ~= nil and racer.Finish ~= nil and now >= racer.Finish
		local tile = Board.Sample(racer.Moves, racer.Pos, now).Rest
		if tile == nil then
			continue -- (mid-hop: keep what's shown)
		end
		local score = if home then 200 - (racer.Place :: number) else tile
		if score ~= racer.Shown then
			ctx:AddScore(player, score - racer.Shown)
			racer.Shown = score
			if not home then
				ctx:SetScoreText(player, if tile <= 0 then "START" else `Tile {tile}/{Board.LAST}`)
			end
		end
	end
end

-- Done once 3 racers are home (or everyone still racing, in a smaller race).
function DiceDash:_checkDone(lastEnd: number?)
	if not self.racing or self.ending then
		return
	end
	local remaining, home = 0, 0
	for player, racer in self.racers do
		if racer.Gone or not self.context:State(player) then
			continue
		end
		remaining += 1
		if racer.Finish then
			home += 1
		end
	end
	if remaining > 0 and home < math.min(3, remaining) then
		return
	end
	self.ending = true
	local ctx = self.context
	local wait = math.max(0, (lastEnd or ctx:Now()) - ctx:Now()) + 2
	ctx:Delay(wait, function()
		ctx:SetShared("Stage", "Done")
		ctx:End("Finished")
	end)
end

function DiceDash:_leave(player: any)
	local racer = self.racers[player]
	if racer and not racer.Gone then
		racer.Gone = true
		self:_share()
		self:_checkDone(if self.phase == "Roll" then nil else self.nextTurn)
	end
end

-- Bots stand where the server has them (players' own clients pose their characters; every client
-- draws everyone from the same moves). Racers sharing a tile stand in a ring.
function DiceDash:_placeBots(now: number, only: any?)
	local ctx = self.context
	local rests: { [number]: { Racer } } = {}
	local samples: { [Racer]: Board.Sample } = {}
	for _, racer in self.racers do
		if racer.Gone then
			continue
		end
		local sample = Board.Sample(racer.Moves, racer.Pos, now)
		samples[racer] = sample
		local rest = sample.Rest
		if rest then
			local list = rests[rest] or {}
			rests[rest] = list
			table.insert(list, racer)
		end
	end
	for _, list in rests do
		table.sort(list, function(a, b)
			return a.Number < b.Number
		end)
	end
	for player, racer in self.racers do
		if racer.Gone or not BotRegistry.IsBot(player) or (only and only ~= player) then
			continue
		end
		local character, humanoid, root = ctx:GetCharacter(player)
		local sample = samples[racer]
		if not character or not humanoid or not root or not sample then
			continue
		end
		if not root.Anchored then
			root.Anchored = true
		end
		if not humanoid.PlatformStand then
			humanoid.PlatformStand = true
		end
		local offset = Vector3.zero
		local rest = sample.Rest
		if rest then
			local list = rests[rest]
			offset = Board.Ring(table.find(list, racer) or 1, #list, rest == 0 or rest == Board.LAST)
		end
		local rootY = if humanoid.RigType == Enum.HumanoidRigType.R15 then humanoid.HipHeight + root.Size.Y / 2 else 3
		local position = sample.Position + offset + Vector3.new(0, rootY, 0)
		if sample.Hidden then
			position -= Vector3.new(0, 4, 0)
		end
		root.CFrame = self:_at(position, sample.Yaw)
	end
end

-- Finish order first (a finish counts if it landed by the buzzer), then how far along.
function DiceDash:GetResults()
	local ctx = self.context
	local home = {}
	for player in ctx.Participants do
		local racer = self.racers[player]
		if player.Parent and racer and racer.Finish and ctx:InTime(racer.Finish) then
			table.insert(home, racer)
		end
	end
	table.sort(home, function(a, b)
		if a.Finish == b.Finish then
			return (a.Place or 0) < (b.Place or 0)
		end
		return (a.Finish :: number) < (b.Finish :: number)
	end)
	local places = {}
	for index, racer in home do
		places[racer] = index -- (a finisher who left gives up their place)
	end
	local entries = {}
	for player in ctx.Participants do
		if not player.Parent then
			continue
		end
		local racer = self.racers[player]
		if not racer then
			continue
		end
		local place = places[racer]
		if place then
			table.insert(entries, {
				Player = player,
				Rank = 1e6 - place,
				ScoreText = `{Board.Ordinal(place)} · {string.format(
					"%.1f",
					(racer.Finish or 0) - (self.startAt or 0)
				)}s`,
				BestScore = 100,
			})
		else
			local tile = math.min(racer.Pos, Board.LAST - 1)
			table.insert(entries, {
				Player = player,
				Rank = tile,
				ScoreText = if tile <= 0 then "at START" else `Tile {tile}/{Board.LAST}`,
				BestScore = math.floor(tile / Board.LAST * 100),
			})
		end
	end
	return { Entries = entries }
end

return DiceDash

-- Spleef (Survival, 75s, 2-12 players). After Minecraft's Spleef: everyone stands on three floors
-- of snow blocks stacked over an icy pool, with a shovel in hand. Click or tap a block within reach
-- and it breaks, so rivals drop through the hole to the floor below. Fall through all three floors
-- into the water and you're out; last one standing wins. Later in the round the floors crack on
-- their own, from the rim inward (the blocks shake and glow, then drop), so every round ends.
--
-- How it works:
--   * The server owns every block: one part each (a cell in self.cells), in a folder per floor.
--     Breaking one destroys its part, so players fall through on their own devices and bots by
--     server physics (or the test server's simulated walking).
--   * Clients only ask (api:Action("Break", cell)); the server checks the cell is still there,
--     within reach of the breaker's eyes (lag leeway from GetNetworkPing), on their floor or below
--     (dig down, never up) and in plain sight (no other block in the way), at most ~7 a second.
--   * Falls are judged on the server from positions too (the test server has no physics, and a
--     device could just hover): a character standing at a floor's height with no block within its
--     footprint for a short grace (longer by its ping for people) is dropped by the server until it
--     lands on a block of a lower floor. Below the last floor it is out at once. Everyone a single
--     step drops out is eliminated in that same step.
--   * The crumble is a shared schedule: cracking blocks get a DropAt time (attribute + "Crack" event),
--     clients shake and glow them until then, and the server drops them at that time.
-- Bots (Bots/Spleef.luau) walk around holes, close in on rivals and dig under their feet.

local ArenaKit = require(script.Parent.Kit.ArenaKit)
local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local Spleef = MiniGame.Define("Spleef")

local BLOCK = 4 -- a block's width and depth
local BLOCK_H = 3 -- its height
local FLOORS = 3
local FLOOR_GAP = 16 -- from one floor's top to the next one down
local FOOT = 1.1 -- half a character's footprint (corner to corner): any block this close to its middle holds it up
local STAND_BAND = 1 -- feet this close to a floor's top count as standing on it
local REACH = 12 -- from the eyes to the nearest point of a block
local EYE = 1.5 -- eyes above the root
local GRACE = 0.25 -- standing over a hole this long drops a character (people add their ping)
local PING_MAX = 0.3 -- the most of anyone's ping that is made up for
local WATER_BELOW = 47 -- the pool's surface under the top floor
local CRUMBLE_AT = 0.4 -- share of the round before the floors start cracking
local CRUMBLE_DONE = 0.92 -- share of the round by when the crumble has done its work
local LAST_CORE = 5 -- blocks of the last floor left standing at the very end (a crowded finale)
local FALL_MAX = 120 -- the fastest a dropped character falls (studs/s)
local CREDIT_TIME = 5 -- a fall this soon after a rival broke your block is their spleef
-- No bot moves faster than walking, jumping or falling could make it (a player landing on a bot's
-- head mustn't launch it off the floors).
local BOT_MAX_UP, BOT_MAX_FLAT = 60, 30
-- The crater rim (World/Props/Spleef.luau, SpleefCliff): each arc is authored around the crater's
-- middle with its mesh bottom CLIFF_BASE under the water; its pivot (bounding box bottom center)
-- sits at CLIFF_PIVOT from there. The cliff face rises out of the water CLIFF_INNER out.
local CLIFF_BASE = 6
local CLIFF_PIVOT = Vector3.new(0, 0, -92)
local CLIFF_INNER = 66
local CLIFF_TOP = 22 -- the rim's top above the water

-- Each floor has its own snow (number and color both shown on the HUD).
Spleef.FloorColors = {
	Color3.fromRGB(248, 251, 255), -- 1: fresh powder
	Color3.fromRGB(186, 222, 252), -- 2: packed snow
	Color3.fromRGB(120, 188, 246), -- 3: blue ice, the last floor
}
Spleef.FloorMaterials = { Enum.Material.Snow, Enum.Material.Snow, Enum.Material.Glacier }
Spleef.Block, Spleef.BlockHeight, Spleef.Floors, Spleef.FloorGap = BLOCK, BLOCK_H, FLOORS, FLOOR_GAP
Spleef.Reach, Spleef.Eye, Spleef.Foot = REACH, EYE, FOOT

export type Cell = {
	Index: number,
	Floor: number,
	I: number,
	J: number,
	Position: Vector3, -- the middle of its top face
	Part: BasePart?,
	State: string, -- "Solid" | "Cracking" | "Gone"
	DropAt: number?,
	BrokenBy: any?,
	BrokenAt: number?,
	Rim: number, -- 0 in the middle, 1 at the edge
}

local rng = Random.new()

local function key(i: number, j: number): number
	return (i + 64) * 256 + (j + 64)
end

local function pingOf(player: any): number
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	return math.clamp(if ok and type(ping) == "number" then ping else 0, 0, PING_MAX)
end

-- Arena ------------------------------------------------------------------------------------------

-- The frozen crater: an icy pool under the floors inside a rim of ice cliffs, snowy pines on the
-- rim and the snowfield around it, crystals and floes in the water, snowy peaks on the horizon.
function Spleef:_buildScenery()
	local ctx = self.context
	local center = self.center
	local waterY = self.waterY
	local pool = Vector3.new(center.X, waterY, center.Z)
	local function upright(position: Vector3): CFrame
		return CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	end
	-- The pool reaches in under the rim; the snowfield runs out to the horizon just under it.
	Build.Decor({
		Name = "Water",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, CLIFF_INNER * 2 + 24, CLIFF_INNER * 2 + 24),
		CFrame = upright(pool - Vector3.new(0, 0.5, 0)),
		Color = Color3.fromRGB(58, 136, 190),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Reflectance = 0.12,
		Parent = ctx.Arena,
	})
	Build.Decor({
		Name = "Deep",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, CLIFF_INNER * 2 + 24, CLIFF_INNER * 2 + 24),
		CFrame = upright(pool - Vector3.new(0, 10, 0)),
		Color = Color3.fromRGB(16, 48, 88),
		Parent = ctx.Arena,
	})
	Build.Decor({
		Name = "Snowfield",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 1600, 1600),
		CFrame = upright(pool - Vector3.new(0, 2.6, 0)),
		Color = Color3.fromRGB(208, 224, 242), -- a shade bluer than the top floor, so the floors stand out
		Material = Enum.Material.Snow,
		Parent = ctx.Arena,
	})
	-- The crater rim: six arcs of ice cliff (each 60 degrees, authored around the crater's middle).
	for index = 0, 5 do
		MeshLibrary.Get("SpleefCliff", {
			CFrame = CFrame.new(pool.X, waterY - CLIFF_BASE, pool.Z)
				* CFrame.Angles(0, math.rad(index * 60 + 30), 0)
				* CFrame.new(CLIFF_PIVOT),
			Parent = ctx.Arena,
		})
	end
	-- Pines along the rim's top and out on the snowfield.
	for index = 0, 15 do
		local angle = index / 16 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local onRim = index % 2 == 0
		local distance = if onRim then rng:NextNumber(CLIFF_INNER + 14, CLIFF_INNER + 22) else rng:NextNumber(150, 230)
		local y = if onRim then CLIFF_TOP else -0.6
		MeshLibrary.Get("SpleefPine", {
			Scale = rng:NextNumber(0.9, 1.5),
			CFrame = CFrame.new(pool + Vector3.new(math.cos(angle) * distance, y, math.sin(angle) * distance))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = ctx.Arena,
		})
	end
	-- Ice crystals at the foot of the cliffs, floes drifting on the pool.
	for index = 0, 8 do
		local angle = index / 9 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local distance = rng:NextNumber(CLIFF_INNER - 6, CLIFF_INNER - 2)
		MeshLibrary.Get("SpleefCrystal", {
			Scale = rng:NextNumber(1.2, 2),
			CFrame = CFrame.new(pool + Vector3.new(math.cos(angle) * distance, -1.5, math.sin(angle) * distance))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = ctx.Arena,
		})
	end
	for index = 0, 6 do
		local angle = index / 7 * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local distance = rng:NextNumber(40, CLIFF_INNER - 14)
		MeshLibrary.Get("SpleefFloe", {
			Scale = rng:NextNumber(0.9, 1.4),
			CFrame = CFrame.new(pool + Vector3.new(math.cos(angle) * distance, -0.7, math.sin(angle) * distance))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = ctx.Arena,
		})
	end
	-- Snowy peaks all round the horizon.
	for index, peak in
		{
			{ -20, 430, 1.9 },
			{ 30, 520, 2.6 },
			{ 75, 450, 1.7 },
			{ 130, 500, 2.3 },
			{ 185, 420, 1.6 },
			{ 240, 530, 2.8 },
			{ 300, 460, 2 },
		}
	do
		local angle = math.rad(peak[1])
		MeshLibrary.Get("SpleefPeak", {
			Scale = peak[3],
			CFrame = CFrame.new(pool + Vector3.new(math.cos(angle) * peak[2], -2, math.sin(angle) * peak[2]))
				* CFrame.Angles(0, index * 1.7, 0),
			Parent = ctx.Arena,
		})
	end
end

-- The three floors of blocks: a disc of cells per floor, sized for the number of players.
function Spleef:_buildFloors(radius: number)
	local ctx = self.context
	local template = MeshLibrary.Get("SpleefBlock")
	local source = template.PrimaryPart :: BasePart
	local turn = source.CFrame.Rotation
	local blocks = Build.Folder("Blocks", ctx.Arena)
	local span = math.ceil(radius)
	for floor = 1, FLOORS do
		local folder = Instance.new("Folder")
		folder.Name = "Floor" .. floor
		local top = self.tops[floor]
		self.grid[floor] = {}
		self.floorCount[floor] = 0
		for i = -span, span do
			for j = -span, span do
				local distance = math.sqrt(i * i + j * j)
				if distance > radius then
					continue
				end
				local position = Vector3.new(self.center.X + i * BLOCK, top, self.center.Z + j * BLOCK)
				local part = source:Clone()
				part.Name = "Block"
				part.Anchored = true
				part.CanCollide = true
				part.CanQuery = true
				part.CanTouch = false
				part.CastShadow = false
				part.Color = Spleef.FloorColors[floor]
				part.Material = Spleef.FloorMaterials[floor]
				part.CFrame = CFrame.new(position - Vector3.new(0, BLOCK_H / 2, 0))
					* CFrame.Angles(0, rng:NextInteger(0, 3) * math.pi / 2, 0)
					* turn
				local index = #self.cells + 1
				part:SetAttribute("Cell", index)
				part:SetAttribute("Floor", floor)
				part.Parent = folder
				local cell: Cell = {
					Index = index,
					Floor = floor,
					I = i,
					J = j,
					Position = position,
					Part = part,
					State = "Solid",
					Rim = distance / radius,
				}
				self.cells[index] = cell
				self.grid[floor][key(i, j)] = cell
				self.floorCount[floor] += 1
			end
		end
		folder.Parent = blocks
	end
	template:Destroy()
end

-- Gives a character a shovel in its right hand (carried at its side, blade forward).
local GRIP = 2.35 -- how far up the shovel the hand holds it
function Spleef:_giveShovel(character: Model)
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") or character:FindFirstChild("SpleefShovel") then
		return
	end
	local shovel = MeshLibrary.Get("SpleefShovel")
	local root = MeshLibrary.Assemble(shovel, true)
	local weld = Instance.new("Weld")
	weld.Name = "ShovelWeld"
	weld.Part0 = hand
	weld.Part1 = root
	weld.C0 = CFrame.new(0, -hand.Size.Y * 0.3, -0.05) * CFrame.Angles(math.rad(48), 0, 0)
	weld.C1 = root.CFrame:ToObjectSpace(shovel:GetPivot() * CFrame.new(0, GRIP, 0))
	weld.Parent = root
	shovel.Parent = character
	self.context:Track(shovel)
end

function Spleef:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	local origin = ctx.Origin.Position
	self.center = origin
	self.tops = {} :: { number }
	for floor = 1, FLOORS do
		self.tops[floor] = origin.Y - (floor - 1) * FLOOR_GAP
	end
	self.floorY = self.tops[FLOORS] - BLOCK_H - 1.5 -- feet below this: through the last floor
	self.waterY = origin.Y - WATER_BELOW
	ctx.KillY = self.waterY - 12
	self.cells = {} :: { Cell }
	self.grid = {} :: { [number]: { [number]: Cell } }
	self.floorCount = {} :: { number }
	self.falling = {} :: { [any]: { Character: Model, Speed: number, Out: boolean } }
	self.unsupported = {} :: { [any]: number }
	self.standing = {} :: { [any]: { Floor: number, Position: Vector3 } }
	self.spleefs = {} :: { [any]: number }
	self.crumbling = false

	local count = #ctx:GetPlayers()
	local radius = math.clamp(3.6 + 0.35 * count, 4.3, 7.8)
	self.radius = radius
	self:_buildScenery()
	self:_buildFloors(radius)
	ctx:SetSharedJSON("Layout", {
		Block = BLOCK,
		Height = BLOCK_H,
		Tops = self.tops,
		X = origin.X,
		Z = origin.Z,
		Reach = REACH,
		Eye = EYE,
		Water = self.waterY,
	})

	-- Everyone starts on the top floor, in a ring facing the middle, each on a block of its own.
	local spawns = {}
	local ring = math.max(BLOCK, radius * BLOCK * 0.55)
	for _, point in ArenaKit.SpawnRing(origin, ring, count) do
		local i = math.floor((point.Position.X - origin.X) / BLOCK + 0.5)
		local j = math.floor((point.Position.Z - origin.Z) / BLOCK + 0.5)
		local spot = Vector3.new(origin.X + i * BLOCK, origin.Y, origin.Z + j * BLOCK)
		table.insert(spawns, CFrame.lookAt(spot, Vector3.new(origin.X, spot.Y, origin.Z)))
	end
	ctx.Hooks.CharacterReady = function(_player, character)
		self:_giveShovel(character)
	end
	ctx:SpawnAll(spawns, true)
	ctx:SetStatus(`Players left: {ctx:AliveCount()}`)
end

-- Geometry the brain and the test bot use too --------------------------------------------------

-- How high a character's feet are (R6 bodies have no hip height: their legs are 2 under a 2-tall root).
function Spleef.Feet(_self, humanoid: Humanoid, root: BasePart): number
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2
	return root.Position.Y - legs
end

-- The floor whose top the feet are at (standing on it, or just over a hole in it), if any.
function Spleef:FloorAt(feet: number): number?
	for floor = 1, FLOORS do
		if math.abs(feet - self.tops[floor]) <= STAND_BAND then
			return floor
		end
	end
	return nil
end

-- The floor a character at this height is on or will land on next (nil: under the last one).
function Spleef:FloorBelow(feet: number): number?
	for floor = 1, FLOORS do
		if feet >= self.tops[floor] - STAND_BAND then
			return floor
		end
	end
	return nil
end

function Spleef:CellAt(floor: number, i: number, j: number): Cell?
	local cells = self.grid[floor]
	return cells and cells[key(i, j)]
end

-- The grid square a point is over.
function Spleef:GridOf(position: Vector3): (number, number)
	return math.floor((position.X - self.center.X) / BLOCK + 0.5),
		math.floor((position.Z - self.center.Z) / BLOCK + 0.5)
end

-- The blocks of `floor` still holding up a character whose middle is at `position` (any part of its
-- footprint over the block).
function Spleef:Supports(floor: number, position: Vector3): { Cell }
	local found = {}
	local i0, j0 = self:GridOf(position)
	local reach = BLOCK / 2 + FOOT
	for i = i0 - 1, i0 + 1 do
		for j = j0 - 1, j0 + 1 do
			local cell = self:CellAt(floor, i, j)
			if
				cell
				and cell.State ~= "Gone"
				and math.abs(position.X - cell.Position.X) <= reach
				and math.abs(position.Z - cell.Position.Z) <= reach
			then
				table.insert(found, cell)
			end
		end
	end
	return found
end

function Spleef:Supported(floor: number, position: Vector3): boolean
	return #self:Supports(floor, position) > 0
end

-- The block (not yet broken) whose solid a point is inside, if any.
function Spleef:_solidAt(point: Vector3): Cell?
	for floor = 1, FLOORS do
		local top = self.tops[floor]
		if point.Y < top - 0.05 and point.Y > top - BLOCK_H + 0.05 then
			local i, j = self:GridOf(point)
			local cell = self:CellAt(floor, i, j)
			if
				cell
				and cell.State ~= "Gone"
				and math.abs(point.X - cell.Position.X) < BLOCK / 2 - 0.05
				and math.abs(point.Z - cell.Position.Z) < BLOCK / 2 - 0.05
			then
				return cell
			end
			return nil
		end
	end
	return nil
end

-- Whether nothing but air is between the eyes and a point (the target block itself excepted).
function Spleef:_clear(from: Vector3, to: Vector3, target: Cell): boolean
	local delta = to - from
	local steps = math.ceil(delta.Magnitude / 0.5)
	for step = 1, steps - 1 do
		local point = from + delta * (step / steps)
		local cell = self:_solidAt(point)
		if cell and cell ~= target then
			return false
		end
	end
	return true
end

-- The nearest point of a block to `from`.
local function nearestOnBlock(cell: Cell, from: Vector3): Vector3
	local p = cell.Position
	return Vector3.new(
		math.clamp(from.X, p.X - BLOCK / 2, p.X + BLOCK / 2),
		math.clamp(from.Y, p.Y - BLOCK_H, p.Y),
		math.clamp(from.Z, p.Z - BLOCK / 2, p.Z + BLOCK / 2)
	)
end

-- Whether a character (root, feet) may break this block: on its floor or below, within reach of
-- its eyes (plus `leeway`), and in plain sight.
function Spleef:CanBreak(root: BasePart, feet: number, cell: Cell, leeway: number): boolean
	if cell.State == "Gone" or cell.Position.Y > feet + STAND_BAND + leeway * 0.5 then
		return false
	end
	local eye = root.Position + Vector3.new(0, EYE, 0)
	local nearest = nearestOnBlock(cell, eye)
	if (nearest - eye).Magnitude > REACH + leeway then
		return false
	end
	if self:_clear(eye, nearest, cell) then
		return true
	end
	-- Seen past an edge: any corner of the top will do.
	local p = cell.Position
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		if self:_clear(eye, p + corner * (BLOCK / 2 - 0.4), cell) then
			return true
		end
	end
	return false
end

-- Round ------------------------------------------------------------------------------------------

function Spleef:Start()
	local ctx = self.context
	ctx:OnAction("Break", function(player, index)
		if type(index) ~= "number" then
			return
		end
		local cell = self.cells[index]
		if not cell or cell.State == "Gone" or self.falling[player] then
			return
		end
		local _, humanoid, root = ctx:GetCharacter(player)
		if not humanoid or not root then
			return
		end
		local leeway = 1.5 + pingOf(player) * 8
		if not self:CanBreak(root, self:Feet(humanoid, root), cell, leeway) then
			ctx:Fire(player, "Denied", index)
			return
		end
		self:_break(cell, player)
	end, { Interval = 0.14 })

	local shownStatus = ""
	ctx:Heartbeat(function(dt)
		self:_falls(dt)
		self:_limitBots()
		local status = `Players left: {ctx:AliveCount()}`
		if self.crumbling then
			status = `❄ The ice is cracking!  •  {status}`
		end
		if status ~= shownStatus then
			shownStatus = status
			ctx:SetStatus(status)
		end
	end)

	local duration = ctx.Definition.Duration or 75
	local startAt = duration * CRUMBLE_AT
	ctx:Delay(startAt, function()
		self.crumbling = true
		ctx:Announce("The ice is cracking!", "warning", 2.5)
		ctx:Sound("HazardWarning")
		ctx:Loop(function()
			local progress =
				math.clamp((ctx:Elapsed() - startAt) / math.max(1, duration * CRUMBLE_DONE - startAt), 0, 1)
			self:_crumble(progress)
			return ArenaKit.Lerp(0.9, 0.45, progress)
		end)
	end)
end

-- Breaks a block: its part goes (so everyone on it falls), clients get the puff and the crunch.
function Spleef:_break(cell: Cell, by: any?)
	cell.State = "Gone"
	cell.BrokenBy = by
	cell.BrokenAt = os.clock()
	if cell.Part then
		cell.Part:Destroy()
		cell.Part = nil
	end
	if by then
		self.context:Fire(nil, "Broke", cell.Index, by.UserId)
	end
end

-- One wave of the crumble: on each floor, enough blocks start cracking (rim first) to keep the
-- floor shrinking on schedule; they drop when their warning runs out. The upper floors go
-- completely; the last floor shrinks to a small core in the middle, so whoever is still standing
-- at the end has to fight for it (and a round always ends: last one standing, or time up).
function Spleef:_crumble(progress: number)
	local ctx = self.context
	local warn = ArenaKit.Lerp(1.9, 1.2, progress)
	local keep = 1 - progress ^ 1.1 -- share of each floor still standing by now
	local batch = {}
	for floor = 1, FLOORS do
		local solid = {}
		for _, cell in self.grid[floor] do
			if cell.State == "Solid" then
				table.insert(solid, cell)
			end
		end
		local core = if floor == FLOORS then LAST_CORE else 0
		local want = math.max(core, math.ceil(self.floorCount[floor] * keep))
		local extra = math.clamp(#solid - want, 0, 6)
		if extra == 0 and #solid > core and rng:NextNumber() < 0.3 then
			extra = 1
		end
		-- Rim first (on the last floor almost only the rim, so its core is the middle).
		local base = if floor == FLOORS then 0.01 else 0.15
		for _ = 1, extra do
			local total = 0
			for _, cell in solid do
				total += base + cell.Rim ^ 4 * 3
			end
			local pick = rng:NextNumber() * total
			for index, cell in solid do
				pick -= base + cell.Rim ^ 4 * 3
				if pick <= 0 or index == #solid then
					table.insert(batch, cell)
					table.remove(solid, index)
					break
				end
			end
		end
	end
	if #batch == 0 then
		return
	end
	local dropAt = ctx:Now() + warn
	local indices = {}
	for _, cell in batch do
		cell.State = "Cracking"
		cell.DropAt = dropAt
		if cell.Part then
			cell.Part:SetAttribute("DropAt", dropAt)
		end
		table.insert(indices, cell.Index)
	end
	ctx:Fire(nil, "Crack", indices, dropAt)
	ctx:Delay(warn, function()
		for _, cell in batch do
			if cell.State == "Cracking" then
				self:_break(cell, nil)
			end
		end
	end)
end

-- Falls: drops anyone standing over a hole (after the grace) and knocks out anyone below the last
-- floor, all in the same step.
function Spleef:_falls(dt: number)
	local ctx = self.context
	local now = os.clock()
	local out = {}

	-- Characters the server is dropping: down they go until a block of a lower floor catches them.
	for player, fall in self.falling do
		local character = fall.Character
		local root = character.Parent and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if player.Character ~= character or not root or not humanoid then
			self.falling[player] = nil
			continue
		end
		local feet = self:Feet(humanoid, root)
		if feet < self.waterY - 10 then
			continue -- under the water: rests there until it's sent back to the lobby
		end
		fall.Speed = math.min(fall.Speed + workspace.Gravity * dt, FALL_MAX)
		local drop = fall.Speed * dt
		local landed = false
		if not fall.Out then
			for floor = 1, FLOORS do
				local top = self.tops[floor]
				if feet >= top - 0.05 and feet - drop <= top and self:Supported(floor, root.Position) then
					character:PivotTo(character:GetPivot() - Vector3.new(0, feet - top, 0))
					root.Anchored = false
					root.AssemblyLinearVelocity = Vector3.zero
					ctx:GiveOwnership(root, player)
					self.falling[player] = nil
					landed = true
					break
				end
			end
		end
		if not landed then
			character:PivotTo(character:GetPivot() - Vector3.new(0, drop, 0))
			if not fall.Out and feet - drop < self.floorY then
				fall.Out = true
				table.insert(out, player)
			end
		end
	end

	for _, player in ctx:GetAlivePlayers() do
		if self.falling[player] then
			continue
		end
		local character, humanoid, root = ctx:GetCharacter(player)
		if not character or not humanoid or not root or root.Anchored then
			continue
		end
		local feet = self:Feet(humanoid, root)
		if feet < self.floorY then
			table.insert(out, player)
			continue
		end
		local floor = self:FloorAt(feet)
		if not floor then
			self.unsupported[player] = nil
			continue
		end
		if self:Supported(floor, root.Position) then
			self.unsupported[player] = nil
			self.standing[player] = { Floor = floor, Position = root.Position }
			continue
		end
		local since = self.unsupported[player]
		if not since then
			self.unsupported[player] = now
		elseif now - since > GRACE + (if BotRegistry.IsBot(player) then 0 else pingOf(player)) then
			self.unsupported[player] = nil
			if BotRegistry.IsBot(player) then
				(player :: any):Stop()
			end
			root.Anchored = true
			self.falling[player] = {
				Character = character,
				Speed = math.max(0, -root.AssemblyLinearVelocity.Y),
				Out = false,
			}
		end
	end

	-- Everyone out in this step goes together: the round can't end (and crown one of them) halfway
	-- through the list; if that leaves nobody standing, they share the finish.
	if #out > 0 then
		local endWhenOneLeft = ctx.EndWhenOneLeft
		ctx.EndWhenOneLeft = false
		for _, player in out do
			self:_out(player)
		end
		ctx.EndWhenOneLeft = endWhenOneLeft
		ctx:_checkAutoEnd()
	end
end

-- A safety net under the bots: whatever shoves one, it goes no faster than walking or jumping would.
function Spleef:_limitBots()
	local ctx = self.context
	for _, player in ctx:GetAlivePlayers() do
		if not BotRegistry.IsBot(player) or self.falling[player] then
			continue
		end
		local _, _, root = ctx:GetCharacter(player)
		if not root or root.Anchored then
			continue
		end
		local velocity = root.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		if velocity.Y > BOT_MAX_UP or flat.Magnitude > BOT_MAX_FLAT then
			if flat.Magnitude > BOT_MAX_FLAT then
				flat = flat.Unit * BOT_MAX_FLAT
			end
			root.AssemblyLinearVelocity = Vector3.new(flat.X, math.min(velocity.Y, BOT_MAX_UP), flat.Z)
		end
	end
end

-- Knocked out through the last floor: whoever broke the block it last stood on gets the spleef.
function Spleef:_out(player: any)
	local ctx = self.context
	self.unsupported[player] = nil
	local standing = self.standing[player]
	if standing then
		local best: Cell? = nil
		local i0, j0 = self:GridOf(standing.Position)
		for i = i0 - 1, i0 + 1 do
			for j = j0 - 1, j0 + 1 do
				local cell = self:CellAt(standing.Floor, i, j)
				if
					cell
					and cell.State == "Gone"
					and cell.BrokenBy
					and cell.BrokenBy ~= player
					and os.clock() - (cell.BrokenAt or 0) < CREDIT_TIME
					and (not best or (cell.BrokenAt or 0) > (best.BrokenAt or 0))
				then
					best = cell
				end
			end
		end
		local by = best and best.BrokenBy
		if by and ctx:State(by) then
			self.spleefs[by] = (self.spleefs[by] or 0) + 1
			ctx:SetScoreText(by, `{self.spleefs[by]} spleef{if self.spleefs[by] == 1 then "" else "s"}`)
			ctx:Fire(nil, "Spleefed", player.UserId, by.UserId)
		end
	end
	ctx:Eliminate(player, "fell")
end

return Spleef

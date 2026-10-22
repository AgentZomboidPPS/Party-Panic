-- Spleef (Survival, 75s, 2-12 players). After Minecraft's Spleef: everyone stands on three floors
-- of snow blocks stacked over an icy pool, with a shovel in hand. Click or tap a block within reach
-- and it breaks, so rivals drop through the hole to the floor below. Fall through all three floors
-- into the water and you're out; last one standing wins. Later in the round the floors crack on
-- their own, from the rim inward (the blocks shake and glow, then drop), so every round ends.
--
-- Second pass, after the owner played it: "Bots are awful at spleef. also spleef doesnt require you
-- to dig. It should be you walk over it and it fades out within like 1 second or so". No more
-- shovels or digging: a block fades away about a second after anyone first steps on it (it shakes,
-- cracks and turns orange, turns see-through, then it's gone for the round), so standing still drops
-- you through and you have to keep moving onto fresh snow. Three floors over the water, fall through
-- all of them and you're out, last one standing wins. The late crumble stays, gentler, as the
-- guarantee that a round ends. Bots plan their steps across the fresh blocks and drop on purpose
-- when they're cornered.
--
-- How it works:
--   * The server owns every block: one part each (a cell in self.cells), in a folder per floor.
--     A cell is "Solid", then "Fading" (with a DropAt time on the shared clock), then "Gone".
--   * Steps are judged on the server from positions, the same way for players and bots: every
--     heartbeat, any character whose feet are at a floor's top triggers each block under its
--     footprint (FOOT, the body's width), along the whole way from where it was last step to where
--     it is now (so a fast mover or a bunched-up network update never skips a block it crossed, and
--     a block it never touched is never triggered). Someone hanging above the floors for longer than
--     a jump (AIR_MAX) counts as standing on the floor under them: nobody hovers for free. Anyone
--     beyond the floors' edge (self.edge) is falling out whatever they stand on (owner's report: a
--     bot standing out on the snowfield; the lobby's sky-island terrain is solid and pokes through
--     this arena's snowfield, the only solid thing outside the floors).
--   * A triggered block gets DropAt = now + WARN + FADE (attribute + "Fade" event). Every client
--     shakes, cracks and tints it for WARN, fades it for FADE, then hides it and turns its collision
--     off at DropAt by the shared clock; the server destroys it at that same moment. Until then it
--     holds you up, everywhere: nothing solid where nothing is drawn, nothing drawn that you fall
--     through.
--   * Falls are judged on the server too (the test server has no physics, and a device could just
--     hover): a character standing at a floor's height with no block within its footprint for a short
--     grace (longer by its ping for people) is dropped by the server until it lands on a block of a
--     lower floor. Below the last floor it is out at once. Everyone a single step drops out is
--     eliminated in that same step.
--   * The crumble (second half of the round) uses the same Fade schedule with a longer warning, rim
--     first; the upper floors go completely and the last floor shrinks to a small core.
-- Bots (Bots/Spleef.luau) plan their steps over the fresh blocks and drop down when cornered.

local ArenaKit = require(script.Parent.Kit.ArenaKit)
local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local Spleef = MiniGame.Define("Spleef")

local BLOCK = 6 -- a block's width and depth (the 4-stud mesh, scaled)
local BLOCK_H = 3 -- its height
local FLOORS = 3
local FLOOR_GAP = 16 -- from one floor's top to the next one down
local FOOT = 1 -- half a character's footprint: any block this close to its middle (on each axis) is under it
local STAND_BAND = 1 -- feet this close to a floor's top count as standing on it
local WARN = 0.7 -- a stepped-on block shakes, cracks and tints this long...
local FADE = 0.3 -- ...then fades this long, then it's gone (it holds you up until then)
local STEP_TIME = WARN + FADE
local GRACE = 0.25 -- standing over a hole this long drops a character (people add their ping)
local AIR_MAX = 1.4 -- hanging above the floors longer than this counts as standing on the one below
local PING_MAX = 0.3 -- the most of anyone's ping that is made up for
local SWEEP_MAX = 14 -- a jump between two samples longer than this isn't a walk (a put-back, a drop)
local WATER_BELOW = 47 -- the pool's surface under the top floor
local CRUMBLE_AT = 0.55 -- share of the round before the floors start crumbling on their own
local CRUMBLE_DONE = 0.92 -- share of the round by when the crumble has done its work
local CRUMBLE_WARN = { 1.7, 1.15 } -- a crumbling block's warning, early and late in the crumble
local LAST_CORE = 6 -- blocks of the last floor the crumble leaves (stepping on them still counts)
local FALL_MAX = 120 -- the fastest a dropped character falls (studs/s)
-- No bot moves faster than walking, jumping or falling could make it (a player landing on a bot's
-- head mustn't launch it off the floors).
local BOT_MAX_UP, BOT_MAX_FLAT = 60, 30
-- The crater rim (World/Props/Spleef.luau, SpleefCliff): each arc is authored around the crater's
-- middle with its mesh bottom CLIFF_BASE under the water; its pivot (bounding box bottom center)
-- sits at CLIFF_PIVOT from there. The cliff face rises out of the water CLIFF_INNER out. The whole
-- rim is scaled up by CLIFF_SCALE (the floors grew: "Also make the spleef arena larger"), so even the
-- biggest floors (78 studs out) stay well inside it.
local CLIFF_SCALE = 1.5
local CLIFF_BASE = 6 * CLIFF_SCALE
local CLIFF_PIVOT = Vector3.new(0, 0, -92 * CLIFF_SCALE)
local CLIFF_INNER = 66 * CLIFF_SCALE
local CLIFF_TOP = 33 -- the rim's top above the water

-- Each floor has its own snow (number and color both shown on the HUD).
Spleef.FloorColors = {
	Color3.fromRGB(248, 251, 255), -- 1: fresh powder
	Color3.fromRGB(150, 194, 238), -- 2: packed snow
	Color3.fromRGB(84, 148, 222), -- 3: blue ice, the last floor
}
Spleef.FloorMaterials = { Enum.Material.Snow, Enum.Material.Snow, Enum.Material.Glacier }
Spleef.Block, Spleef.BlockHeight, Spleef.Floors, Spleef.FloorGap = BLOCK, BLOCK_H, FLOORS, FLOOR_GAP
Spleef.Foot, Spleef.StepTime = FOOT, STEP_TIME

-- The floor's radius in blocks for a number of players: about 140 blocks a floor for two, 225 for
-- five, about 490 for twelve (75 studs; under 1500 blocks in all). Everyone has to keep moving and
-- every step uses up a block, so this sets how long a floor lasts.
function Spleef.RadiusFor(count: number): number
	return math.clamp(5.6 + 0.58 * count, 6.5, 12.5)
end

export type Cell = {
	Index: number,
	Floor: number,
	I: number,
	J: number,
	Position: Vector3, -- the middle of its top face
	Part: BasePart?,
	State: string, -- "Solid" | "Fading" | "Gone"
	DropAt: number?, -- (shared clock) when a fading block is gone
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
			Scale = CLIFF_SCALE,
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
		local distance = if onRim then rng:NextNumber(CLIFF_INNER + 20, CLIFF_INNER + 32) else rng:NextNumber(215, 300)
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
		local distance = rng:NextNumber(CLIFF_INNER - 8, CLIFF_INNER - 3)
		MeshLibrary.Get("SpleefCrystal", {
			Scale = rng:NextNumber(1.2, 2),
			CFrame = CFrame.new(pool + Vector3.new(math.cos(angle) * distance, -1.5, math.sin(angle) * distance))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = ctx.Arena,
		})
	end
	for index = 0, 6 do
		local angle = index / 7 * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local distance = rng:NextNumber(84, CLIFF_INNER - 8)
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
				part.CastShadow = true -- the floors shade the ones below, so each floor reads apart
				part.Color = Spleef.FloorColors[floor]
				part.Material = Spleef.FloorMaterials[floor]
				-- (Turned by quarter turns about Y only, so the scale is the same on X and Z.)
				part.Size = Vector3.new(BLOCK, BLOCK_H, BLOCK)
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
	self.fading = {} :: { Cell }
	self.falling = {} :: { [any]: { Character: Model, Speed: number, Out: boolean } }
	self.unsupported = {} :: { [any]: number }
	self.airborne = {} :: { [any]: number }
	self.track = {} :: { [any]: { Floor: number, Position: Vector3 } }
	self.crumbling = false

	local count = #ctx:GetPlayers()
	local radius = Spleef.RadiusFor(count)
	self.radius = radius
	self.edge = radius * BLOCK + BLOCK / 2 + FOOT + 2 -- further out than this is off the floors
	self:_buildScenery()
	self:_buildFloors(radius)
	ctx:SetSharedJSON("Layout", {
		Block = BLOCK,
		Height = BLOCK_H,
		Tops = self.tops,
		X = origin.X,
		Z = origin.Z,
		Fade = FADE,
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

-- The blocks of `floor` (not gone) under a character whose middle is at `position`: any part of its
-- footprint over the block. These hold it up, and these are the ones it steps on.
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

-- Seconds until a block is gone (math.huge while untouched, 0 once gone).
function Spleef:TimeLeft(cell: Cell): number
	if cell.State == "Gone" then
		return 0
	elseif cell.State == "Fading" then
		return math.max(0, (cell.DropAt or 0) - self.context:Now())
	end
	return math.huge
end

-- Round ------------------------------------------------------------------------------------------

function Spleef:Start()
	local ctx = self.context
	local shownStatus = ""
	ctx:Heartbeat(function(dt)
		self:_expire()
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

-- Starts a block fading: it's gone at dropAt (shared clock). Untouched blocks only.
function Spleef:_fade(cell: Cell, dropAt: number): boolean
	if cell.State ~= "Solid" then
		return false
	end
	cell.State = "Fading"
	cell.DropAt = dropAt
	if cell.Part then
		cell.Part:SetAttribute("DropAt", dropAt)
	end
	table.insert(self.fading, cell)
	return true
end

-- Every block whose time is up goes now: its part is destroyed, so nobody stands on it any more.
-- Clients hide it and turn its collision off at this same DropAt on their own clock.
function Spleef:_expire()
	local now = self.context:Now()
	local fading = self.fading
	for index = #fading, 1, -1 do
		local cell = fading[index]
		if cell.State ~= "Fading" then
			table.remove(fading, index)
		elseif now >= (cell.DropAt or 0) then
			table.remove(fading, index)
			cell.State = "Gone"
			if cell.Part then
				cell.Part:Destroy()
				cell.Part = nil
			end
		end
	end
end

-- The blocks a character stepped on since the last heartbeat: everything under its footprint along
-- the way from where it was then to where it is now, on this floor. Starts them fading.
function Spleef:_step(player: any, floor: number, position: Vector3, dropAt: number, fresh: { number })
	local last = self.track[player]
	local from = position
	if last and last.Floor == floor then
		local flat = Vector3.new(position.X - last.Position.X, 0, position.Z - last.Position.Z)
		if flat.Magnitude <= SWEEP_MAX then
			from = last.Position
		end
	end
	self.track[player] = { Floor = floor, Position = position }
	local delta = Vector3.new(position.X - from.X, 0, position.Z - from.Z)
	local samples = math.ceil(delta.Magnitude / 0.8)
	for sample = 0, samples do
		local point = if samples == 0 then position else from + delta * (sample / samples)
		for _, cell in self:Supports(floor, point) do
			if self:_fade(cell, dropAt) then
				table.insert(fresh, cell.Index)
			end
		end
	end
end

-- One wave of the crumble: on each floor, enough untouched blocks start fading (rim first, with a
-- longer warning than a step) to keep the floor shrinking on schedule. The upper floors go
-- completely; the last floor shrinks to a small core in the middle (which still fades when it's
-- stepped on), so a round always ends with a winner or at the buzzer.
function Spleef:_crumble(progress: number)
	local ctx = self.context
	local warn = ArenaKit.Lerp(CRUMBLE_WARN[1], CRUMBLE_WARN[2], progress)
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
		local extra = math.clamp(#solid - want, 0, 8)
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
	local dropAt = ctx:Now() + warn
	local indices = {}
	for _, cell in batch do
		if self:_fade(cell, dropAt) then
			table.insert(indices, cell.Index)
		end
	end
	if #indices > 0 then
		ctx:Fire(nil, "Fade", indices, dropAt)
	end
end

-- Steps and falls, every heartbeat: anyone at a floor's height steps on the blocks under them;
-- anyone standing over a hole (after the grace) is dropped; anyone below the last floor is out, all
-- in the same step.
function Spleef:_falls(dt: number)
	local ctx = self.context
	local now = os.clock()
	local dropAt = ctx:Now() + STEP_TIME
	local fresh = {}
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
		-- (A new character the round is still putting back on its spot isn't standing anywhere yet.)
		if self.falling[player] or ctx._placing[player] then
			self.track[player] = nil
			continue
		end
		local character, humanoid, root = ctx:GetCharacter(player)
		if not character or not humanoid or not root or root.Anchored then
			self.track[player] = nil
			continue
		end
		local isBot = BotRegistry.IsBot(player)
		local ping = if isBot then 0 else pingOf(player)
		local feet = self:Feet(humanoid, root)
		if feet < self.floorY then
			table.insert(out, player)
			continue
		end
		local position = root.Position
		local floor = self:FloorAt(feet)
		local outside = Vector2.new(position.X - self.center.X, position.Z - self.center.Z).Magnitude > self.edge
		if outside then
			-- Off the floors altogether: nothing out here holds anyone up in this mode (the lobby's
			-- sky islands are solid terrain around the arena and poke through the snowfield), so
			-- whoever gets out here is falling out, wherever they stand.
			self.track[player] = nil
			self.airborne[player] = nil
			floor = self:FloorBelow(feet) or FLOORS
		elseif floor then
			self.airborne[player] = nil
		else
			-- In the air: a jump or a fall is fine; hanging up here longer than a jump isn't (on
			-- someone's head, on the crater rim, a device that hovers): it counts as standing on the
			-- floor under them.
			self.track[player] = nil
			local since = self.airborne[player]
			if not since then
				self.airborne[player] = now
			elseif now - since > AIR_MAX + ping then
				floor = self:FloorBelow(feet)
			end
			if not floor then
				self.unsupported[player] = nil
				continue
			end
		end
		if self.airborne[player] and not outside then
			for _, cell in self:Supports(floor, position) do
				if self:_fade(cell, dropAt) then
					table.insert(fresh, cell.Index)
				end
			end
		elseif not outside then
			self:_step(player, floor, position, dropAt, fresh)
		end
		if self:Supported(floor, position) then
			self.unsupported[player] = nil
			continue
		end
		local since = self.unsupported[player]
		if not since then
			self.unsupported[player] = now
		elseif now - since > GRACE + ping then
			self.unsupported[player] = nil
			self.airborne[player] = nil
			self.track[player] = nil
			if isBot then
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

	if #fresh > 0 then
		ctx:Fire(nil, "Fade", fresh, dropAt)
	end

	-- Everyone out in this step goes together: the round can't end (and crown one of them) halfway
	-- through the list; if that leaves nobody standing, they share the finish.
	if #out > 0 then
		local endWhenOneLeft = ctx.EndWhenOneLeft
		ctx.EndWhenOneLeft = false
		for _, player in out do
			self.unsupported[player] = nil
			self.airborne[player] = nil
			self.track[player] = nil
			ctx:Eliminate(player, "fell")
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

return Spleef

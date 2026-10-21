-- Hex Meltdown (Reaction, 80s, up to 12 players). Mechanics after "Hexagon Heat":
-- hex pillars stand in a lava lake; a referee robot raises a colored flag and every hex of another
-- color sinks into the lava for a moment. Stand on the flag's color or fall in. Calls come faster
-- and faster; landing on a rival's head stuns them. Last players standing win.
--
-- The hexes move on each client from a shared schedule (MG_Call), so they glide smoothly; the
-- server never needs their position, only the players', and the round's fall check knocks out
-- anyone who sinks into the lava. Bots are the exception: the server moves them, and on the server
-- the hexes never sink, so while they're down a bot that isn't on a hex of the called color is
-- dropped into the lava here (Bots/HexMeltdown.luau is how they play).

local ArenaKit = require(script.Parent.Kit.ArenaKit)
local MiniGame = require(script.Parent.Kit.MiniGame)
local Scenery = require(script.Parent.Kit.Scenery)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local Shapes = require(script.Parent.Parent.World.Shapes)

local HexMeltdown = MiniGame.Define("HexMeltdown")

local HEX_SIZE = 7 -- circumradius (center to corner)
local HEX_HEIGHT = 30
local SPACING = 1.12 -- leaves a gap between hexes you have to hop
local GRID_RADIUS = 2 -- rings around the center: 19 hexes
local SINK_DEPTH = 26
local LAVA_DROP = 20 -- lava surface below the hex tops
local DROP_DEPTH = 3 -- a bot off the called color falls once the other hexes are this far down

-- Art (World/Props/HexMeltdown.luau). Mesh props pivot at their bounding box's bottom center:
local WALL_PIVOT = Vector3.new(-0.04, 0, -103.85) -- a CraterWall arc's pivot from the crater center
local ROBOT_PIVOT = Vector3.new(3.38, 0.04, -0.05) -- the RefereeBot's pivot from its feet
local STAND_HEIGHT = 19.3 -- RefereeStand: its top is the stage
local MARQUEE_CENTER_Y = 23.5 -- the CallMarquee's opening, above the stage
local BASALT = Color3.fromRGB(84, 60, 80)
local RIM = Color3.fromRGB(255, 244, 226)
local GOLD = Color3.fromRGB(255, 196, 60)

-- Every color comes with a shape so color is never the only cue (design doc §12).
HexMeltdown.Palette = {
	{ Name = "Red", Shape = "●", Color = Color3.fromRGB(255, 70, 70) },
	{ Name = "Blue", Shape = "■", Color = Color3.fromRGB(60, 140, 255) },
	{ Name = "Green", Shape = "▲", Color = Color3.fromRGB(70, 210, 90) },
	{ Name = "Yellow", Shape = "★", Color = Color3.fromRGB(255, 210, 50) },
	{ Name = "Purple", Shape = "♦", Color = Color3.fromRGB(165, 95, 255) },
	{ Name = "Pink", Shape = "♥", Color = Color3.fromRGB(255, 110, 200) },
}

local rng = Random.new()

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- How far the sinking hexes are below their resting place at `now` on players' screens (the client
-- half eases them down and back up with this same curve).
local function sunkBy(call, now: number): number
	local function ease(t: number): number
		t = math.clamp(t, 0, 1)
		return t * t * (3 - 2 * t)
	end
	if now < call.RiseAt then
		return call.Depth * ease((now - call.SinkAt) / call.Move)
	end
	return call.Depth * (1 - ease((now - call.RiseAt) / call.Move))
end

-- A hexagonal prism: three boxes turned 60 degrees apart, unioned once and cloned.
local function hexPrism(height: number, props: { [string]: any }, size: number?): BasePart
	local radius = size or HEX_SIZE
	local width, depth = radius, radius * math.sqrt(3)
	return Shapes.Custom(`Hex|{radius}|{height}`, function(piece)
		return {
			piece(Vector3.new(width, height, depth), CFrame.identity),
			piece(Vector3.new(width, height, depth), CFrame.Angles(0, math.rad(60), 0)),
			piece(Vector3.new(width, height, depth), CFrame.Angles(0, math.rad(120), 0)),
		}
	end, Vector3.new(radius * 2, height, depth), props)
end

-- Axial hex coordinates -> world offset (flat-top layout).
local function hexOffset(q: number, r: number): Vector3
	local x = HEX_SIZE * 1.5 * q
	local z = HEX_SIZE * math.sqrt(3) * (r + q / 2)
	return Vector3.new(x, 0, z) * SPACING
end

-- Colors for the 18 outer hexes: three of each, shuffled so neighbors rarely match.
local function colorLayout(count: number): { number }
	local best, bestScore = nil, math.huge
	for _ = 1, 40 do
		local order = {}
		for index = 1, count do
			order[index] = ((index - 1) % #HexMeltdown.Palette) + 1
		end
		for index = #order, 2, -1 do
			local other = rng:NextInteger(1, index)
			order[index], order[other] = order[other], order[index]
		end
		local score = 0
		for index = 2, #order do
			if order[index] == order[index - 1] then
				score += 1
			end
		end
		if score < bestScore then
			best, bestScore = order, score
		end
	end
	return best :: { number }
end

-- The crater around the lake: four arcs of crater wall, crust rafts drifting on the lava, lava
-- torches either side of the referee and volcanoes on the horizon behind the wall.
local function buildCrater(ctx, origin: Vector3, lake: Vector3)
	for index = 0, 3 do
		local turn = CFrame.new(lake.X, lake.Y - 3, lake.Z) * CFrame.Angles(0, math.rad(index * 90 + 45), 0)
		MeshLibrary.Get("CraterWall", { CFrame = turn * CFrame.new(WALL_PIVOT), Parent = ctx.Arena })
	end
	-- Rafts sit in the open lava between the grid and the wall, never in front of the referee.
	for _, raft in
		{ { 15, 60 }, { 62, 58 }, { 110, 62 }, { 160, 56 }, { 205, 60 }, { 330, 58 }, { 20, 76 }, { 140, 76 } }
	do
		local angle = math.rad(raft[1])
		local spot = lake + Vector3.new(math.cos(angle) * raft[2], -0.9, math.sin(angle) * raft[2])
		MeshLibrary.Get("LavaCrust", {
			Scale = rng:NextNumber(0.75, 1),
			CFrame = CFrame.new(spot) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = ctx.Arena,
		})
	end
	for _, side in { -1, 1 } do
		local torch = MeshLibrary.Get("LavaTorch", {
			CFrame = CFrame.new(Vector3.new(origin.X + side * 21, lake.Y - 2, origin.Z - 47)),
			Parent = ctx.Arena,
		})
		local flame = torch:FindFirstChild("Flame", true)
		if flame and flame:IsA("BasePart") then
			Build.Light(flame, rgb(255, 150, 60), 26, 1.6)
		end
	end
	Scenery.Volcano(ctx, lake + Vector3.new(-20, -2, -300), origin, 2.3)
	Scenery.Volcano(ctx, lake + Vector3.new(260, -2, -220), origin, 1.4)
	Scenery.Volcano(ctx, lake + Vector3.new(-290, -2, -160), origin, 1.1)
end

-- The referee's stage north of the grid: the robot holding up the call flag, the call board in a
-- light-bulb marquee behind it. Returns the flag (the server colors it) and the board's text.
local function buildReferee(ctx, origin: Vector3): (BasePart, TextLabel)
	local stageTop = origin + Vector3.new(0, -4, -52)
	-- The old rock pillar stays as an invisible collider, so anyone who leaps that far still lands
	-- the same way; the stage mesh around it is the look.
	Shapes.Slab(Vector3.new(14, 26, 14), 4, {
		Name = "RefereeRock",
		CFrame = CFrame.new(stageTop - Vector3.new(0, 13, 0)),
		Transparency = 1,
		Parent = ctx.Arena,
	})
	local facing = CFrame.lookAt(stageTop, Vector3.new(origin.X, stageTop.Y, origin.Z))
	MeshLibrary.Get("RefereeStand", { CFrame = facing * CFrame.new(0, -STAND_HEIGHT, 0), Parent = ctx.Arena })
	local robot = MeshLibrary.Get("RefereeBot", {
		CFrame = facing * CFrame.new(0, 0, -3) * CFrame.new(ROBOT_PIVOT),
		Parent = ctx.Arena,
	})
	local flag = robot:FindFirstChild("Flag", true) :: BasePart
	flag:SetAttribute("Flag", true)
	MeshLibrary.Get("CallMarquee", { CFrame = facing * CFrame.new(0, 0, 5), Parent = ctx.Arena })
	local board = Build.Decor({
		Name = "CallBoard",
		Size = Vector3.new(26.6, 9.4, 0.6),
		CFrame = facing * CFrame.new(0, MARQUEE_CENTER_Y, 5),
		Color = rgb(28, 20, 56),
		Parent = ctx.Arena,
	})
	local label = Build.SurfaceText(board, Enum.NormalId.Front, "GET READY!", {
		PixelsPerStud = 14,
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = Color3.new(1, 1, 1),
		MaxDistance = 400,
	})
	return flag, label
end

function HexMeltdown:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	ctx.KillY = ctx.Origin.Y - 14
	self.hexes = {} :: { { Position: Vector3, ColorIndex: number } }
	self.lastStomp = {} :: { [string]: number }
	self.call = nil :: { [string]: any }? -- the current call (also shared with clients as MG_Call)
	self.falling = {} :: { [any]: { Character: Model, Speed: number } } -- bots dropping into the lava
	local origin = ctx.Origin.Position

	-- A lava lake in a volcanic crater, the referee's stage north of the grid.
	local lake = origin - Vector3.new(0, LAVA_DROP, 0)
	Scenery.LavaLake(ctx, lake, 200)
	Scenery.Ground(ctx, lake)
	buildCrater(ctx, origin, lake)
	self.flag, self.boardLabel = buildReferee(ctx, origin)

	-- The hex grid: a white start hex in the middle, colored hexes around it.
	local coords = {}
	for q = -GRID_RADIUS, GRID_RADIUS do
		for r = -GRID_RADIUS, GRID_RADIUS do
			if math.abs(q + r) <= GRID_RADIUS and not (q == 0 and r == 0) then
				table.insert(coords, { q, r })
			end
		end
	end
	local colors = colorLayout(#coords)
	local function addHex(index: number, q: number, r: number, colorIndex: number)
		local top = origin + hexOffset(q, r)
		local entry = HexMeltdown.Palette[colorIndex]
		local color = if entry then entry.Color else rgb(255, 250, 240)
		local model = Build.Model("Hex" .. index, ctx.Arena)
		-- The pillar, rim and cap you stand on are invisible colliders (the same shapes as ever);
		-- the carved column mesh inside them is what you see.
		hexPrism(HEX_HEIGHT, {
			Name = "Pillar",
			CFrame = CFrame.new(top - Vector3.new(0, HEX_HEIGHT / 2 + 0.5, 0)),
			Transparency = 1,
			Parent = model,
		})
		hexPrism(0.7, {
			Name = "Rim",
			CFrame = CFrame.new(top - Vector3.new(0, 1.15, 0)),
			Transparency = 1,
			Parent = model,
		}, HEX_SIZE + 0.45)
		local cap = hexPrism(1, {
			Name = "Cap",
			CFrame = CFrame.new(top - Vector3.new(0, 0.5, 0)),
			Color = color,
			Transparency = 1,
			Parent = model,
		})
		if entry then
			Build.SurfaceText(cap, Enum.NormalId.Top, entry.Shape, {
				PixelsPerStud = 10,
				TextColor3 = Color3.new(1, 1, 1),
				TextStrokeTransparency = 0.5,
				Font = Enum.Font.GothamBold,
			})
		end
		MeshLibrary.Get("HexColumn", {
			Colors = {
				Top = color,
				Rock = if entry then color:Lerp(BASALT, 0.72) else BASALT,
				Rim = if entry then RIM else GOLD,
			},
			CFrame = CFrame.new(top - Vector3.new(0, HEX_HEIGHT + 1, 0)),
			Parent = model,
		})
		model:SetAttribute("ColorIndex", colorIndex)
		model:SetAttribute("Index", index)
		model.PrimaryPart = cap
		table.insert(self.hexes, { Position = top, ColorIndex = colorIndex })
	end
	addHex(0, 0, 0, 0)
	for index, coord in coords do
		addHex(index, coord[1], coord[2], colors[index])
	end

	-- One player per hex to start (the grid has room for 19).
	local spawns = {}
	for _, hex in self.hexes do
		table.insert(spawns, CFrame.lookAt(hex.Position, Vector3.new(origin.X, hex.Position.Y, origin.Z - 60)))
	end
	for index = #spawns, 2, -1 do
		local other = rng:NextInteger(1, index)
		spawns[index], spawns[other] = spawns[other], spawns[index]
	end
	ctx:SpawnAll(spawns, true)
	ctx:SetStatus(`Players left: {ctx:AliveCount()}`)
end

-- Picks the next color, never the same twice in a row.
function HexMeltdown:_nextColor(): number
	local choice = rng:NextInteger(1, #HexMeltdown.Palette)
	if choice == self.lastColor then
		choice = (choice % #HexMeltdown.Palette) + 1
	end
	self.lastColor = choice
	return choice
end

function HexMeltdown:Start()
	local ctx = self.context
	local callId = 0

	ctx:Loop(function()
		local progress = ctx:Progress()
		local warn = ArenaKit.Lerp(4.2, 1.7, progress)
		local down = ArenaKit.Lerp(2.4, 1.6, progress)
		local pause = ArenaKit.Lerp(1.6, 0.9, progress)
		local colorIndex = self:_nextColor()
		local entry = HexMeltdown.Palette[colorIndex]
		callId += 1
		local now = ctx:Now()
		self.call = {
			Id = callId,
			Color = colorIndex,
			Name = entry.Name,
			Shape = entry.Shape,
			RGB = { math.floor(entry.Color.R * 255), math.floor(entry.Color.G * 255), math.floor(entry.Color.B * 255) },
			WarnAt = now,
			SinkAt = now + warn,
			RiseAt = now + warn + 0.7 + down,
			Move = 0.7,
			Depth = SINK_DEPTH,
		}
		ctx:SetSharedJSON("Call", self.call)
		self.flag.Color = entry.Color
		self.boardLabel.Text = `{entry.Shape} {string.upper(entry.Name)} {entry.Shape}`
		self.boardLabel.TextColor3 = entry.Color
		self.callText = `{entry.Shape} {string.upper(entry.Name)}!`
		ctx:Sound("HazardWarning")
		return warn + 0.7 + down + 0.7 + pause
	end)

	-- Stomps: land on a rival's head to stun them for a moment.
	local previousY: { [Player]: number } = {}
	local shownStatus = ""
	ctx:Heartbeat(function()
		local alive = ctx:GetAlivePlayers()
		local roots = {}
		for _, player in alive do
			local _, _, root = ctx:GetCharacter(player)
			if root then
				roots[player] = root.Position
			end
		end
		for attacker, top in roots do
			local falling = previousY[attacker] ~= nil and top.Y < previousY[attacker] - 0.05
			previousY[attacker] = top.Y
			if not falling then
				continue
			end
			for victim, bottom in roots do
				if victim == attacker or ctx:IsStunned(victim) then
					continue
				end
				local dy = top.Y - bottom.Y
				if dy > 2.5 and dy < 6 and ArenaKit.FlatDistance(top, bottom) < 2.2 then
					local key = attacker.Name .. ">" .. victim.Name
					if os.clock() - (self.lastStomp[key] or 0) > 1.5 then
						self.lastStomp[key] = os.clock()
						ctx:Stun(victim, 1.2)
						ctx:Knockback(attacker, Vector3.new(0, 45, 0), 0) -- the stomper bounces off
						ctx:Sound("Boing")
					end
				end
			end
		end
		local status = `{self.callText or "Get ready!"}  •  Players left: {#alive}`
		if status ~= shownStatus then
			shownStatus = status
			ctx:SetStatus(status)
		end
	end)

	ctx:Heartbeat(function(dt)
		self:_dropBots(dt)
	end)
end

-- Players fall when the hexes sink on their screens. The server moves bots, and on the server the
-- hexes never sink, so while they're down a bot standing anywhere but on a hex of the called color
-- falls into the lava here, and the round's fall check knocks it out the same way.
function HexMeltdown:_dropBots(dt: number)
	local ctx = self.context
	local call = self.call
	if call and sunkBy(call, ctx:Now()) > DROP_DEPTH then
		local floorY = ctx.Origin.Position.Y
		for _, player in ctx:GetAlivePlayers() do
			if not BotRegistry.IsBot(player) or self.falling[player] then
				continue
			end
			local character, humanoid, root = ctx:GetCharacter(player)
			if not character or not humanoid or not root then
				continue
			end
			-- In the air (a hop) it may still land on a safe hex; standing, its hex must be safe.
			local feet = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
			local safe = feet > floorY + 1
			for _, hex in self.hexes do
				if hex.ColorIndex == call.Color and ArenaKit.FlatDistance(hex.Position, root.Position) < HEX_SIZE then
					safe = true
					break
				end
			end
			if not safe then
				(player :: any):Stop()
				root.Anchored = true
				self.falling[player] = { Character = character, Speed = 0 }
			end
		end
	end
	local lavaY = ctx.Origin.Position.Y - LAVA_DROP
	for player, fall in self.falling do
		local character = fall.Character
		if player.Character ~= character or not character.Parent then
			self.falling[player] = nil -- out, and back in the lobby
		elseif character:GetPivot().Y > lavaY - 4 then
			fall.Speed += workspace.Gravity * dt
			character:PivotTo(character:GetPivot() - Vector3.new(0, fall.Speed * dt, 0))
		end
	end
end

return HexMeltdown

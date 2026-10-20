-- Hex Meltdown (Reaction, 80s, up to 12 players). Mechanics after "Hexagon Heat":
-- hex pillars stand in a lava lake; a referee robot raises a colored flag and every hex of another
-- color sinks into the lava for a moment. Stand on the flag's color or fall in. Calls come faster
-- and faster; landing on a rival's head stuns them. Last players standing win.
--
-- The hexes move on each client from a shared schedule (MG_Call), so they glide smoothly; the
-- server never needs their position, only the players', and the round's fall check knocks out
-- anyone who sinks into the lava.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ArenaKit = require(script.Parent.Kit.ArenaKit)
local MiniGame = require(script.Parent.Kit.MiniGame)
local Scenery = require(script.Parent.Kit.Scenery)
local Build = require(script.Parent.Parent.World.Build)
local Shapes = require(script.Parent.Parent.World.Shapes)

local HexMeltdown = MiniGame.Define("HexMeltdown")

local HEX_SIZE = 7 -- circumradius (center to corner)
local HEX_HEIGHT = 30
local SPACING = 1.12 -- leaves a gap between hexes you have to hop
local GRID_RADIUS = 2 -- rings around the center: 19 hexes
local SINK_DEPTH = 26
local LAVA_DROP = 20 -- lava surface below the hex tops

-- Every color comes with a shape so color is never the only cue (design doc §12).
HexMeltdown.Palette = {
	{ Name = "Red", Shape = "●", Color = Color3.fromRGB(255, 70, 70) },
	{ Name = "Blue", Shape = "■", Color = Color3.fromRGB(60, 140, 255) },
	{ Name = "Green", Shape = "▲", Color = Color3.fromRGB(70, 210, 90) },
	{ Name = "Yellow", Shape = "★", Color = Color3.fromRGB(255, 210, 50) },
	{ Name = "Purple", Shape = "♦", Color = Color3.fromRGB(165, 95, 255) },
	{ Name = "Pink", Shape = "♥", Color = Color3.fromRGB(255, 110, 200) },
}

local knockbackRemote = Remotes.Get("Knockback")
local rng = Random.new()

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
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

function HexMeltdown:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	ctx.KillY = ctx.Origin.Y - 14
	self.hexes = {} :: { { Position: Vector3, ColorIndex: number } }
	self.lastStomp = {} :: { [string]: number }
	local origin = ctx.Origin.Position

	-- A lava lake in a volcanic crater; volcanoes behind the referee close off the view.
	local lake = origin - Vector3.new(0, LAVA_DROP, 0)
	Scenery.LavaLake(ctx, lake, 200)
	Scenery.Ground(ctx, lake)
	Scenery.RockRim(ctx, lake, 96, 16, 0.9, 1.7)
	Scenery.Volcano(ctx, lake + Vector3.new(-20, -2, -300), origin, 2.3)
	Scenery.Volcano(ctx, lake + Vector3.new(260, -2, -220), origin, 1.4)
	Scenery.Volcano(ctx, lake + Vector3.new(-290, -2, -160), origin, 1.1)

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
		local color = if entry then entry.Color else rgb(250, 250, 255)
		local model = Build.Model("Hex" .. index, ctx.Arena)
		hexPrism(HEX_HEIGHT, {
			Name = "Pillar",
			CFrame = CFrame.new(top - Vector3.new(0, HEX_HEIGHT / 2 + 0.5, 0)),
			Color = color:Lerp(rgb(60, 40, 50), 0.55),
			Material = Enum.Material.Slate,
			Parent = model,
		})
		hexPrism(0.7, {
			Name = "Rim",
			CFrame = CFrame.new(top - Vector3.new(0, 1.15, 0)),
			Color = rgb(255, 245, 235),
			Parent = model,
		}, HEX_SIZE + 0.45)
		local cap = hexPrism(1, {
			Name = "Cap",
			CFrame = CFrame.new(top - Vector3.new(0, 0.5, 0)),
			Color = color,
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
		model:SetAttribute("ColorIndex", colorIndex)
		model:SetAttribute("Index", index)
		model.PrimaryPart = cap
		table.insert(self.hexes, { Position = top, ColorIndex = colorIndex })
	end
	addHex(0, 0, 0, 0)
	for index, coord in coords do
		addHex(index, coord[1], coord[2], colors[index])
	end

	-- The referee robot with its flag, on a rock pillar north of the grid.
	local refereeBase = origin + Vector3.new(0, -4, -52)
	Shapes.Slab(Vector3.new(14, 26, 14), 4, {
		Name = "RefereeRock",
		CFrame = CFrame.new(refereeBase - Vector3.new(0, 13, 0)),
		Color = rgb(80, 60, 66),
		Material = Enum.Material.Slate,
		Parent = ctx.Arena,
	})
	local facing = CFrame.lookAt(refereeBase, Vector3.new(origin.X, refereeBase.Y, origin.Z))
	local robot = Build.Model("Referee", ctx.Arena)
	Shapes.RoundedBox(Vector3.new(6, 7, 4), 1.2, {
		Name = "Body",
		CFrame = facing * CFrame.new(0, 3.5, 0),
		Color = rgb(245, 245, 255),
		Parent = robot,
	})
	Shapes.RoundedBox(Vector3.new(5, 4, 4), 1.4, {
		Name = "Head",
		CFrame = facing * CFrame.new(0, 9.3, 0),
		Color = rgb(245, 245, 255),
		Parent = robot,
	})
	Build.Part({
		Name = "Visor",
		Size = Vector3.new(4, 1.4, 0.4),
		CFrame = facing * CFrame.new(0, 9.6, -2),
		Color = rgb(40, 220, 255),
		Material = Enum.Material.Neon,
		Parent = robot,
	})
	Shapes.Capsule(12, 0.5, {
		Name = "FlagPole",
		CFrame = facing * CFrame.new(4.2, 10, -1) * CFrame.Angles(0, 0, math.rad(90)),
		Color = rgb(230, 230, 240),
		Parent = robot,
	})
	self.flag = Build.Part({
		Name = "Flag",
		Size = Vector3.new(0.3, 4.5, 7),
		CFrame = facing * CFrame.new(4.2, 13.6, -4.5) * CFrame.Angles(0, math.rad(90), 0),
		Color = rgb(255, 255, 255),
		Parent = robot,
	})
	self.flag:SetAttribute("Flag", true)
	local board = Build.Decor({
		Name = "CallBoard",
		Size = Vector3.new(24, 9, 0.6),
		CFrame = facing * CFrame.new(0, 22, 0),
		Color = rgb(30, 22, 60),
		Parent = robot,
	})
	self.boardLabel = Build.SurfaceText(board, Enum.NormalId.Front, "GET READY!", {
		PixelsPerStud = 14,
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = Color3.new(1, 1, 1),
		MaxDistance = 400,
	})

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
		ctx:SetSharedJSON("Call", {
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
		})
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
						if typeof(attacker) == "Instance" then
							knockbackRemote:FireClient(attacker, Vector3.new(0, 45, 0), 0)
						end
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
end

return HexMeltdown

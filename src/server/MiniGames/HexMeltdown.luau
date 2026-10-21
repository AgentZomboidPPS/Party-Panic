-- Hex Meltdown (Reaction, 90s, up to 12 players). Mechanics after "Hexagon Heat":
-- hex pillars stand in a lava lake; a referee robot raises a colored flag and every hex of another
-- color sinks into the lava for a moment. Stand on the flag's color or fall in. Calls come faster
-- and faster; landing on a rival's head stuns them. Last players standing win.
--
-- The hexes move on each client from a shared schedule (MG_Call), so they glide smoothly; the
-- server never needs their position, only the players', and the round's fall check knocks out
-- anyone who sinks into the lava. Bots are the exception: the server moves them, and on the server
-- the hexes never sink, so while they're down a bot that isn't on a hex of the called color is
-- dropped into the lava here (Bots/HexMeltdown.luau is how they play).
--
-- Art pass ("make every arena look really cool"): a toy volcano crater. Carved basalt hex columns
-- with candy-colored tiles, a crater wall with lava falls and rock spires, cracked crust rafts on
-- the lava, and a game-show referee robot on a striped stage under a light-bulb call board, between
-- two lava torches. The meshes are in World/Props/HexMeltdown.luau; the colliders are unchanged.
--
-- Hitbox pass (owner: "We need to fine tune some of the hitboxes. the precision games will feel super
-- bad if we dont."): what you see on your screen is what counts.
--   Players fall by their own device's physics on the hexes it sinks, so the colliders match the
--   visible column: the cap is the 6.95 tile (collider 7), and the rim collider now fills the
--   visible cream rim (7.45 out, 0.65 to 1.7 below the top; it used to stop 0.15 below the rim's top).
--   A bot is on a hex while any of its footprint (about 2 wide) is over the hex's top, rim
--   included: a true hexagon test, not a 7 stud circle that counted half the gap along an edge and
--   dropped a bot standing on a rim corner. It is judged on the picture everyone else sees (the
--   hexes as they sink now, the bot as drawn about 0.15s late), and a dropped bot rides its hex
--   down instead of hanging in the air while the hex sinks out from under it.
--   A stomp counts if you land on a rival where your screen showed them: up to your ping plus
--   0.15s back (they are drawn that late, and at walking speed that is more than the 2.2 reach).
--
-- Floating bots (owner: "Theres invisible stuff." "Bot is floating."): bots were being launched
-- into the sky. The server moves bots and each player's own device moves them, so when the two
-- touched (a player landing on a bot, or walking into one) Roblox shoved the bot out of the way,
-- sometimes hard enough to send it flying over the lava; a stomp on two rivals at once also added
-- two bounces. Now bots and players pass through each other here (stomps never needed touching:
-- they go by where everyone is), a stomp bounces you once however many heads it lands on, and no
-- bot can move faster than it could by walking, jumping or bouncing.
--
-- Round's end, bots' stomps and the referee's stage (owner: "Bot is floating." "Theres invisible
-- stuff."; fair hits: "the precision games will feel super bad if we dont"):
--   * Time can run out in the middle of a call. The call used to play on on everyone's device
--     through the results while the server had stopped: people who had made it sank into the lava,
--     and bots on the doomed hexes stood in the air over them (the server's hexes never sink, and
--     it no longer dropped bots). Now the round's end calls it off for everyone (Stop: the call's
--     StopAt, Shared/Logic/HexMeltdown): nothing more sinks and whatever was going down comes back
--     up. A bot that was already dropping keeps falling into the lava and is out, not "Survived!".
--   * A bot has no screen, so its stomp is judged on the victim's, where the bot is drawn late and
--     the victim is where they really are: stepping away from a leap you saw coming is a dodge (it
--     used to count any of the victim's spots from the last 0.15s, which is for a person's screen).
--     A stomper bounces once per landing even when a person's bounce takes their ping to arrive:
--     until it does, the server still sees them coming down, and a second head gave a second bounce.
--   * The referee's stage was held up by the old rock pillar, an invisible block that stuck out up
--     to 4 studs past the drawn plinth under the stage's lip. Now only the drawn stage is solid, and
--     it is out of bounds: it never sinks, so whoever lands on it (a bounce off a head can carry
--     that far) is out, as if they had fallen in.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Rules = require(ReplicatedStorage.Shared.Logic.HexMeltdown)

local ArenaKit = require(script.Parent.Kit.ArenaKit)
local MiniGame = require(script.Parent.Kit.MiniGame)
local Scenery = require(script.Parent.Kit.Scenery)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Telemetry = require(script.Parent.Parent.Services.Telemetry)
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
local RIM_SIZE = HEX_SIZE + 0.45 -- the cream rim, the widest part of a hex's top (the mesh: 7.45)
local FOOT = 1 -- half a character's width: any of its footprint over a hex top holds it up
-- Other players' characters (bots too) are drawn about this far behind the server on your screen.
local SEEN_LAG = 0.15
local STOMP_PING_MAX = 0.2 -- the most of a person's ping that is made up for
local BOUNCE = 45 -- added to a stomper's upward speed, once per landing
-- One landing: a person's bounce reaches them up to twice their ping later (the server sees them
-- coming down until then), and a bot's landing is judged up to SEEN_LAG plus the victim's ping late.
local BOUNCE_LOCK = 0.5
-- Bots and players don't touch in this mode (they still stomp each other: that goes by position).
-- People use the lobby's PP_Players group (World/BeachBalls.luau puts every player's character in it).
local BOT_GROUP, PEOPLE_GROUP = "PP_HexBots", "PP_Players"
-- No bot ever moves faster than this (walking is 16, a jump or a bounce about 50 up).
local BOT_MAX_UP, BOT_MAX_FLAT = 60, 30

-- Art (World/Props/HexMeltdown.luau). Mesh props pivot at their bounding box's bottom center:
local WALL_PIVOT = Vector3.new(-0.11, 0, -103.91) -- a CraterWall arc's pivot from the crater center
local WALL_SCALE = 0.85 -- the crater's inner foot about 73 studs out, framing the grid
local ROBOT_PIVOT = Vector3.new(7.13, 0.04, -0.05) -- the RefereeBot's pivot from its feet
local STAND_HEIGHT = 19.3 -- RefereeStand: its top is the stage
-- The stand's axis sits this far back from where the old rock pillar stood, so the stage's grid-side
-- edge is where the rock's was and only the far side overhangs.
local STAND_BACK = 5.4
local MARQUEE_CENTER_Y = 27 -- the CallMarquee's opening, above the stage
local STAND_SCALE, ROBOT_SCALE, MARQUEE_SCALE = 1.15, 1.35, 1.25
-- The stage disc on top of the RefereeStand mesh (radius 11, 1.4 deep there), as the stand is drawn.
local STAGE_RADIUS, STAGE_DEPTH = 11 * STAND_SCALE, 1.4 * STAND_SCALE
local BASALT = Color3.fromRGB(84, 60, 80)
local RIM = Color3.fromRGB(255, 244, 226)
local GOLD = Color3.fromRGB(255, 196, 60)
local WALL_ROCK = Color3.fromRGB(66, 50, 62)

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

-- Whether a character whose root is at `point` stands on the hex whose top center is at
-- `hexPosition`: any of its footprint over the top, rim included (flat-top: corners on +-X; the
-- hexagon grown by FOOT). Across the 1.45 stud gap between two hexes both count, as a character
-- straddling it is held up by either rim.
local REACH = RIM_SIZE * math.sqrt(3) / 2 + FOOT
function HexMeltdown.StandsOn(hexPosition: Vector3, point: Vector3): boolean
	local x = math.abs(point.X - hexPosition.X)
	local z = math.abs(point.Z - hexPosition.Z)
	return z <= REACH and x * math.sqrt(3) / 2 + z / 2 <= REACH
end

-- How far behind the server a person's screen shows everyone else: the time others are drawn late
-- plus their ping (what they do on it reaches the server that late). A bot has no screen: 0.
local function screenLag(player): number
	if BotRegistry.IsBot(player) then
		return 0
	end
	local ok, ping = pcall(function()
		return (player :: any):GetNetworkPing()
	end)
	return SEEN_LAG + math.clamp(if ok and type(ping) == "number" then ping else 0, 0, STOMP_PING_MAX)
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
		MeshLibrary.Get("CraterWall", {
			Scale = WALL_SCALE,
			CFrame = turn * CFrame.new(WALL_PIVOT * WALL_SCALE),
			Parent = ctx.Arena,
		})
	end
	-- Rock spires along the crest break up the skyline (none behind the referee's board).
	for index = 0, 10 do
		local degrees = (index / 11 * 360 + rng:NextNumber(-8, 8)) % 360
		if degrees > 240 and degrees < 300 then
			continue
		end
		local angle = math.rad(degrees)
		local distance = rng:NextNumber(87, 95)
		local spire = MeshLibrary.Get("Spire", {
			Scale = rng:NextNumber(1.1, 1.6),
			Colors = { Rock = WALL_ROCK },
			CFrame = CFrame.new(lake + Vector3.new(math.cos(angle) * distance, 6, math.sin(angle) * distance))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
		})
		-- Scenery only (out of reach): no colliders, and the same smooth toy rock as the wall.
		for _, part in spire:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				if part.Name == "Rock" then
					part.Material = Enum.Material.SmoothPlastic
				end
			end
		end
		spire.Parent = ctx.Arena
	end
	-- Rafts sit in the open lava between the grid and the wall, never in front of the referee.
	-- Each raft is stretched by its own amounts along X and Z, so no two share an outline.
	for _, raft in { { 20, 48 }, { 75, 50 }, { 125, 47 }, { 170, 49 }, { 215, 48 }, { 330, 50 } } do
		local angle = math.rad(raft[1])
		local spot = lake + Vector3.new(math.cos(angle) * raft[2], -0.8, math.sin(angle) * raft[2])
		local crust = MeshLibrary.Get("LavaCrust", { Scale = rng:NextNumber(1.25, 1.5) })
		local pivot = crust:GetPivot()
		local stretch = Vector3.new(rng:NextNumber(0.8, 1.2), 1, rng:NextNumber(0.75, 1.25))
		for _, part in crust:GetDescendants() do
			if part:IsA("BasePart") then
				local offset = pivot:ToObjectSpace(part.CFrame)
				part.Size *= stretch
				part.CFrame = pivot * CFrame.new(offset.Position * stretch) * offset.Rotation
			end
		end
		crust:PivotTo(CFrame.new(spot) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
		crust.Parent = ctx.Arena
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
	-- The volcanoes stand off to the sides, so the call board and the flag have open sky behind them.
	Scenery.Volcano(ctx, lake + Vector3.new(135, -2, -300), origin, 2.3)
	Scenery.Volcano(ctx, lake + Vector3.new(-200, -2, -260), origin, 1.4)
	Scenery.Volcano(ctx, lake + Vector3.new(-290, -2, -160), origin, 1.1)
end

-- The referee's stage north of the grid: the robot holding up the call flag, the call board in a
-- light-bulb marquee behind it. Returns the flag (the server colors it), the board's text and the
-- middle of the stage's top.
local function buildReferee(ctx, origin: Vector3): (BasePart, TextLabel, Vector3)
	local stageTop = origin + Vector3.new(0, -4, -52)
	local facing = CFrame.lookAt(stageTop, Vector3.new(origin.X, stageTop.Y, origin.Z))
	local stand = facing * CFrame.new(0, 0, STAND_BACK) -- the stand's axis, at the stage's top
	MeshLibrary.Get("RefereeStand", {
		Scale = STAND_SCALE,
		CFrame = stand * CFrame.new(0, -STAND_HEIGHT * STAND_SCALE, 0),
		Parent = ctx.Arena,
	})
	-- What anyone who leaps that far lands on: the stage disc as drawn (it was the old rock pillar,
	-- an invisible block reaching past the drawn plinth under the stage's lip). It's out of bounds
	-- all the same (_checkStage).
	Build.Part({
		Name = "RefereeStage",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(STAGE_DEPTH, STAGE_RADIUS * 2, STAGE_RADIUS * 2),
		CFrame = CFrame.new(stand.Position - Vector3.new(0, STAGE_DEPTH / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Transparency = 1,
		Parent = ctx.Arena,
	})
	local robot = MeshLibrary.Get("RefereeBot", {
		Scale = ROBOT_SCALE,
		CFrame = facing * CFrame.new(0, 0, -3.2) * CFrame.new(ROBOT_PIVOT * ROBOT_SCALE),
		Parent = ctx.Arena,
	})
	local flag = robot:FindFirstChild("Flag", true) :: BasePart
	flag:SetAttribute("Flag", true)
	MeshLibrary.Get("CallMarquee", {
		Scale = MARQUEE_SCALE,
		CFrame = facing * CFrame.new(0, 0, 3.5),
		Parent = ctx.Arena,
	})
	-- The board fills the marquee's opening, its edges hidden inside the frame.
	local board = Build.Decor({
		Name = "CallBoard",
		Size = Vector3.new(26.6 * MARQUEE_SCALE, 9.4 * MARQUEE_SCALE, 0.6),
		CFrame = facing * CFrame.new(0, MARQUEE_CENTER_Y * MARQUEE_SCALE, 3.5),
		Color = rgb(28, 20, 56),
		Parent = ctx.Arena,
	})
	local label = Build.SurfaceText(board, Enum.NormalId.Front, "GET READY!", {
		PixelsPerStud = 14,
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = Color3.new(1, 1, 1),
		MaxDistance = 400,
	})
	return flag, label, stand.Position
end

-- Puts every character in the round in the bots' or the people's collision group (parts that load
-- later too), so bots and players pass through each other. Returns false if the groups can't be set
-- up, and then everyone collides as before.
local function separateBotsFromPeople(ctx): boolean
	local ok = pcall(function()
		for _, group in { BOT_GROUP, PEOPLE_GROUP } do
			if not PhysicsService:IsCollisionGroupRegistered(group) then
				PhysicsService:RegisterCollisionGroup(group)
			end
		end
		PhysicsService:CollisionGroupSetCollidable(BOT_GROUP, PEOPLE_GROUP, false)
	end)
	if not ok then
		return false
	end
	for _, player in ctx:GetPlayers() do
		local character = ctx:GetCharacter(player)
		if not character then
			continue
		end
		local group = if BotRegistry.IsBot(player) then BOT_GROUP else PEOPLE_GROUP
		for _, item in character:GetDescendants() do
			if item:IsA("BasePart") then
				item.CollisionGroup = group
			end
		end
		ctx:Track(character.DescendantAdded:Connect(function(item)
			if item:IsA("BasePart") then
				item.CollisionGroup = group
			end
		end))
	end
	return true
end

function HexMeltdown:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	ctx.KillY = ctx.Origin.Y - 14
	self.hexes = {} :: { { Position: Vector3, ColorIndex: number } }
	self.lastStomp = {} :: { [string]: number }
	self.call = nil :: { [string]: any }? -- the current call (also shared with clients as MG_Call)
	-- Bots dropping into the lava (_dropBots): riding their hex down from Top, dropped At seconds in.
	self.falling = {} :: { [any]: { Character: Model, Speed: number, Ride: any, Top: number, At: number } }
	local origin = ctx.Origin.Position

	-- A lava lake in a volcanic crater, the referee's stage north of the grid.
	local lake = origin - Vector3.new(0, LAVA_DROP, 0)
	Scenery.LavaLake(ctx, lake, 200)
	Scenery.Ground(ctx, lake)
	buildCrater(ctx, origin, lake)
	self.flag, self.boardLabel, self.stage = buildReferee(ctx, origin)

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
		local model = Build.Model("Hex" .. index) -- parented once complete (the client reads its pivot)
		-- The pillar, rim and cap you stand on are invisible colliders (the same shapes as ever);
		-- the carved column mesh inside them is what you see.
		hexPrism(HEX_HEIGHT, {
			Name = "Pillar",
			CFrame = CFrame.new(top - Vector3.new(0, HEX_HEIGHT / 2 + 0.5, 0)),
			Transparency = 1,
			Parent = model,
		})
		hexPrism(1.05, {
			Name = "Rim",
			CFrame = CFrame.new(top - Vector3.new(0, 1.175, 0)), -- the mesh's rim: 0.65 to 1.7 below the top
			Transparency = 1,
			Parent = model,
		}, RIM_SIZE)
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
		model.Parent = ctx.Arena
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
	separateBotsFromPeople(ctx)
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

	-- Stomps: land on a rival's head to stun them for a moment, judged on the screen that saw it
	-- (Shared/Logic/HexMeltdown: Stomped), so everyone's spots from the last moments are kept.
	local trails: { [any]: { Rules.Sample } } = {}
	local bounceUntil: { [any]: number } = {}
	local shownStatus = ""
	ctx:Heartbeat(function()
		local clock = os.clock()
		local alive = ctx:GetAlivePlayers()
		local roots = {}
		for _, player in alive do
			local _, _, root = ctx:GetCharacter(player)
			if root and not self.falling[player] then
				roots[player] = root.Position
			end
		end
		for player in trails do
			if not roots[player] then
				trails[player] = nil
			end
		end
		local lags = {}
		for player, position in roots do
			local trail = trails[player] or {}
			trails[player] = trail
			local last = trail[#trail]
			table.insert(trail, {
				Time = clock,
				Position = position,
				Falling = last ~= nil and position.Y < last.Position.Y - 0.05,
			})
			while trail[1].Time < clock - SEEN_LAG - STOMP_PING_MAX - 0.05 do
				table.remove(trail, 1)
			end
			lags[player] = screenLag(player)
		end
		for attacker, attackerTrail in trails do
			for victim, victimTrail in trails do
				if victim == attacker or ctx:IsStunned(victim) then
					continue
				end
				-- A person goes by their own screen; a bot, which has none, by the victim's.
				local attackerBack = if BotRegistry.IsBot(attacker) then lags[victim] else 0
				local key = attacker.Name .. ">" .. victim.Name
				if
					clock - (self.lastStomp[key] or 0) > 1.5
					and Rules.Stomped(attackerTrail, attackerBack, victimTrail, lags[attacker], clock)
				then
					self.lastStomp[key] = clock
					ctx:Stun(victim, 1.2)
					-- The stomper bounces off once per landing, however many heads it lands on.
					if clock >= (bounceUntil[attacker] or 0) then
						bounceUntil[attacker] = clock + BOUNCE_LOCK
						ctx:Knockback(attacker, Vector3.new(0, BOUNCE, 0), 0)
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

	ctx:Heartbeat(function()
		self:_dropBots()
		self:_limitBots()
		self:_checkStage() -- last: it can end the round
	end)
	-- Bots dropping into the lava keep falling after the round ends (it can end mid-drop), so none
	-- is ever left hanging in the air through the results.
	local moving: RBXScriptConnection
	moving = ctx:Track(RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(self._moveFalling, self, dt)
		if not ok then
			moving:Disconnect()
			Telemetry.Error("RoundHeartbeat", `{HexMeltdown.Id} falling bots: {err}`)
		end
	end))
end

-- Time's up, or the round ended another way: the call is off for everyone. Nothing more sinks, and
-- hexes that were going down, or down, come straight back up (Shared/Logic/HexMeltdown), so the
-- players left stand on solid hexes through the results, on their screens and on the server alike.
function HexMeltdown:Stop()
	local call = self.call
	if call and not call.StopAt then
		call.StopAt = self.context:Now()
		self.context:SetSharedJSON("Call", call)
	end
end

-- Survivors share first place, except a bot that was already dropping into the lava when the round
-- ended: it is out (it just hadn't reached the lava yet), ranked by when it was dropped.
function HexMeltdown:GetResults()
	local ctx = self.context
	local results = ctx:SurvivalResults()
	for _, entry in results.Entries do
		local fall = self.falling and self.falling[entry.Player]
		if fall and fall.Character == entry.Player.Character and ctx:IsAlive(entry.Player) then
			entry.Rank = math.floor(fall.At * 10) / 10
			entry.ScoreText = string.format("Lasted %ds", math.floor(fall.At))
			entry.BestScore = math.floor(fall.At)
			entry.Survived = fall.At
		end
	end
	return results
end

-- The referee's stage is scenery, not a hex: it never sinks, so anyone who lands on it is out, as if
-- they had fallen in (bots never go there).
function HexMeltdown:_checkStage()
	local ctx = self.context
	local floorY = ctx.Origin.Position.Y
	for _, player in ctx:GetAlivePlayers() do
		local _, humanoid, root = ctx:GetCharacter(player)
		if not humanoid or not root or self.falling[player] then
			continue
		end
		local feet = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
		if feet < floorY - 2 and ArenaKit.FlatDistance(root.Position, self.stage) < STAGE_RADIUS + FOOT then
			ctx:Eliminate(player, "stage")
		end
	end
end

-- A safety net under the bots: whatever shoves one (a pile-up, a bounce on a bounce), it can't fly
-- off over the lava or hang in the sky; it goes no faster than walking, jumping or bouncing would.
function HexMeltdown:_limitBots()
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

-- Players fall when the hexes sink on their screens. The server moves bots, and on the server the
-- hexes never sink, so while they're down a bot standing anywhere but on a hex of the called color
-- is dropped into the lava here (_moveFalling), and the round's fall check knocks it out the same
-- way. It is judged on what the others see: the hexes as they are now, the bot as it was SEEN_LAG
-- ago (where it's drawn).
function HexMeltdown:_dropBots()
	local ctx = self.context
	local call = self.call
	local seen = ctx:Now() + SEEN_LAG -- the hexes' time when the others see the bot as it is now
	local sunk = if call then Rules.Sunk(call, seen) else 0
	if not call or sunk <= DROP_DEPTH then
		return
	end
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
			if hex.ColorIndex == call.Color and HexMeltdown.StandsOn(hex.Position, root.Position) then
				safe = true
				break
			end
		end
		if not safe then
			(player :: any):Stop()
			-- Standing on a hex as it started down, it rides the hex down (or falls faster);
			-- landing from a hop on a hex that is already down, it just keeps falling.
			local riding = seen < call.RiseAt and sunk < DROP_DEPTH * 2
			root.Anchored = true
			self.falling[player] = {
				Character = character,
				Speed = math.max(0, -root.AssemblyLinearVelocity.Y),
				Ride = if riding then call else nil,
				Top = character:GetPivot().Y,
				At = ctx:Elapsed(),
			}
		end
	end
end

-- Moves the dropped bots: down with their hex as everyone sees it sink, or faster, until they're
-- under the lava. Runs on after the round ends, so a drop is always seen through.
function HexMeltdown:_moveFalling(dt: number)
	local ctx = self.context
	local seen = ctx:Now() + SEEN_LAG
	local lavaY = ctx.Origin.Position.Y - LAVA_DROP
	for player, fall in self.falling do
		local character = fall.Character
		if player.Character ~= character or not character.Parent then
			self.falling[player] = nil -- out, and back in the lobby
			continue
		end
		local pivot = character:GetPivot()
		if pivot.Y > lavaY - 4 then
			fall.Speed += workspace.Gravity * dt
			local y = pivot.Y - fall.Speed * dt
			local ride = fall.Ride
			if ride and ride == self.call and seen < ride.RiseAt then
				-- (Once the round has ended its hex comes back up, and the bot falls on past it.)
				y = math.min(y, fall.Top - Rules.Sunk(ride, seen))
			end
			character:PivotTo(pivot - Vector3.new(0, pivot.Y - y, 0))
		end
	end
end

return HexMeltdown

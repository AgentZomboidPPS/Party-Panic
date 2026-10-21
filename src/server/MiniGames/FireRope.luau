-- Fire Rope (Survival, 75s, up to 12 players). Mechanics after "Hot Rope Jump": everyone stands on
-- a long stone bridge over lava while two fire wheels swing a burning rope around it. Jump as it
-- sweeps under your feet; it keeps speeding up, with the odd change of pace. Touch it and you're
-- out. Last one jumping wins; ties go to whoever cleared more jumps.
--
-- The rope's angle follows a schedule shared with every client (MG_Rope): a list of segments that
-- each start at a bottom pass and are announced one full turn ahead, so clients draw it perfectly
-- in sync. At every pass the server checks each player's recent height, with a little leeway for
-- network lag, so a jump that looked right on your screen counts. Bots are judged the same way
-- (Bots/FireRope.luau times their jumps from the same schedule).

local MiniGame = require(script.Parent.Kit.MiniGame)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local Notifier = require(script.Parent.Parent.Services.Notifier)
local Scenery = require(script.Parent.Kit.Scenery)
local Shapes = require(script.Parent.Parent.World.Shapes)

local FireRope = MiniGame.Define("FireRope")

local LENGTH = 72 -- bridge length (x)
local DEPTH = 8 -- bridge depth (z)
local RADIUS = 9.5 -- rope swing radius
local ROPE_LOW = 0.9 -- rope height above the floor at the bottom of its swing
local CLEAR = 1.4 -- how far a player's root must rise above standing height to clear the rope
local FIRST_PERIOD = 3.0
local FASTEST_PERIOD = 1.05 -- a Roblox jump is ~0.5s in the air; this leaves time to land and go again
local LAVA_DROP = 24

local rng = Random.new()

type Segment = { T0: number, A0: number, W: number }
type Sample = { T: number, H: number }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

function FireRope:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	ctx.KillY = ctx.Origin.Y - 12
	self.history = {} :: { [Player]: { Sample } }
	self.standing = {} :: { [Player]: number }
	self.jumps = {} :: { [Player]: number }
	self.segments = {} :: { Segment }
	self.passes = 0
	local origin = ctx.Origin.Position
	self.floorY = origin.Y
	self.axis = origin + Vector3.new(0, RADIUS + ROPE_LOW, 0)

	-- A lava lake in a volcanic crater, with volcanoes ahead of the players.
	local lake = origin - Vector3.new(0, LAVA_DROP, 0)
	Scenery.LavaLake(ctx, lake, 210)
	Scenery.Ground(ctx, lake)
	Scenery.RockRim(ctx, lake, 110, 18, 0.9, 1.8)
	Scenery.Volcano(ctx, lake + Vector3.new(30, -2, -320), origin, 2.4)
	Scenery.Volcano(ctx, lake + Vector3.new(-280, -2, -250), origin, 1.5)
	Scenery.Volcano(ctx, lake + Vector3.new(300, -2, -190), origin, 1.15)

	-- The bridge: a stone slab with gold edges on stone arches rising out of the lava.
	Shapes.Slab(Vector3.new(LENGTH, 3, DEPTH), 1.2, {
		Name = "Bridge",
		CFrame = CFrame.new(origin - Vector3.new(0, 1.5, 0)),
		Color = rgb(190, 170, 160),
		Material = Enum.Material.Slate,
		Parent = ctx.Arena,
	})
	for _, side in { -1, 1 } do
		Shapes.RoundedBox(Vector3.new(LENGTH + 0.6, 0.8, 0.9), 0.35, {
			Name = "Edge",
			CFrame = CFrame.new(origin + Vector3.new(0, -2.4, side * (DEPTH / 2 + 0.1))),
			Color = rgb(255, 200, 60),
			Parent = ctx.Arena,
		})
	end
	for index = 0, 7 do
		local x = -LENGTH / 2 + 2 + index * (LENGTH - 4) / 7
		Build.Decor({
			Name = "Seam",
			Size = Vector3.new(0.25, 0.05, DEPTH - 1),
			CFrame = CFrame.new(origin + Vector3.new(x, 0.03, 0)),
			Color = rgb(150, 130, 125),
			Parent = ctx.Arena,
		})
	end
	local archWidth = LENGTH / 3
	for index = -1, 1 do
		Shapes.Arch(
			archWidth,
			LAVA_DROP - 1.9,
			3,
			DEPTH - 1,
			CFrame.new(lake + Vector3.new(index * archWidth, -1, 0)),
			{
				Name = "Arch",
				Color = rgb(128, 108, 108),
				Material = Enum.Material.Slate,
				Parent = ctx.Arena,
			}
		)
	end

	-- A fire wheel at each end turns the rope (the client spins the wheels in time with it), held
	-- by a stone tower with a burning brazier on top.
	for _, side in { -1, 1 } do
		local wheelX = side * (LENGTH / 2 + 7)
		local wheel = MeshLibrary.Get("FireWheel", { Parent = ctx.Arena })
		wheel.Name = if side < 0 then "WheelL" else "WheelR"
		local box = wheel:GetBoundingBox()
		local center = self.axis + Vector3.new(wheelX, 0, 0)
		wheel:PivotTo(wheel:GetPivot() + (center - box.Position))

		local towerX = wheelX + side * 4.7 -- the axle's end just meets the tower
		local towerHeight = LAVA_DROP + RADIUS + ROPE_LOW + 5
		Shapes.RoundedBox(Vector3.new(6, towerHeight, 6), 1.2, {
			Name = "Tower",
			CFrame = CFrame.new(lake + Vector3.new(towerX, towerHeight / 2 - 1, 0)),
			Color = rgb(96, 76, 84),
			Material = Enum.Material.Slate,
			Parent = ctx.Arena,
		})
		for _, height in { 8, towerHeight - 3.5 } do
			Shapes.RoundedBox(Vector3.new(6.8, 1, 6.8), 0.4, {
				Name = "TowerBand",
				CFrame = CFrame.new(lake + Vector3.new(towerX, height, 0)),
				Color = rgb(255, 200, 60),
				Parent = ctx.Arena,
			})
		end
		local brazier = Shapes.RoundedBox(Vector3.new(4, 1.6, 4), 0.6, {
			Name = "Brazier",
			CFrame = CFrame.new(lake + Vector3.new(towerX, towerHeight - 0.2, 0)),
			Color = rgb(70, 55, 62),
			Material = Enum.Material.Metal,
			Parent = ctx.Arena,
		})
		local coals = Build.Decor({
			Name = "Coals",
			Size = Vector3.new(3, 0.3, 3),
			CFrame = brazier.CFrame + Vector3.new(0, 0.85, 0),
			Color = rgb(255, 150, 50),
			Material = Enum.Material.Neon,
			Parent = ctx.Arena,
		})
		local fire = Instance.new("Fire")
		fire.Size = 7
		fire.Heat = 10
		fire.Color = rgb(255, 140, 40)
		fire.SecondaryColor = rgb(255, 60, 30)
		fire.Parent = coals
		Build.Light(coals, rgb(255, 150, 60), 30, 2)
	end

	-- Everyone lines up across the bridge, facing the side the rope comes down on.
	local players = ctx:GetPlayers()
	local spacing = math.min(5.5, (LENGTH - 6) / math.max(1, #players))
	local spawns = {}
	for index = 1, #players do
		local x = (index - (#players + 1) / 2) * spacing
		local position = origin + Vector3.new(x, 0, 0)
		table.insert(spawns, CFrame.lookAt(position, position + Vector3.new(0, 0, -1)))
	end
	ctx:SpawnAll(spawns, true)
	for _, player in ctx:GetPlayers() do
		self.jumps[player] = 0
		ctx:SetScoreText(player, "0 jumps")
	end
	self:_publish(0)
	ctx:SetStatus("Get ready to jump!")
end

-- Rope speed for the next full turn (seconds per turn), with surprise changes of pace.
function FireRope:_nextPeriod(): number
	local period = math.max(FASTEST_PERIOD, FIRST_PERIOD * 0.955 ^ self.passes)
	if self.passes > 4 and rng:NextNumber() < 0.2 then
		period *= if rng:NextNumber() < 0.5 then 1.35 else 0.85
	end
	return math.max(FASTEST_PERIOD * 0.9, period)
end

function FireRope:_publish(heat: number)
	local segments = {}
	for index = math.max(1, #self.segments - 2), #self.segments do
		table.insert(segments, self.segments[index])
	end
	self.context:SetSharedJSON("Rope", {
		Axis = { self.axis.X, self.axis.Y, self.axis.Z },
		Radius = RADIUS,
		Length = LENGTH + 12,
		FloorY = self.floorY,
		Segments = segments,
		Heat = heat,
	})
end

function FireRope:_floorHeight(position: Vector3): number?
	local origin = self.context.Origin.Position
	if math.abs(position.X - origin.X) > LENGTH / 2 + 2 or math.abs(position.Z - origin.Z) > DEPTH / 2 + 4 then
		return nil -- not over the bridge
	end
	return position.Y - self.floorY
end

function FireRope:_judge(passTime: number)
	local ctx = self.context
	for _, player in ctx:GetAlivePlayers() do
		local samples = self.history[player]
		if not samples then
			continue
		end
		local ok, ping = pcall(function()
			return (player :: any):GetNetworkPing()
		end)
		local lag = if ok and type(ping) == "number" then math.clamp(ping, 0, 0.35) else 0.1
		local highest = -math.huge
		local seen = false
		for _, sample in samples do
			if sample.T >= passTime - 0.16 and sample.T <= passTime + 0.18 + lag then
				seen = true
				highest = math.max(highest, sample.H)
			end
		end
		if not seen then
			continue -- off the bridge (falling): the fall check deals with it
		end
		local need = (self.standing[player] or 3) + CLEAR
		if highest >= need then
			self.jumps[player] = (self.jumps[player] or 0) + 1
			ctx:AddScore(player, 1)
			ctx:SetScoreText(player, if self.jumps[player] == 1 then "1 jump" else `{self.jumps[player]} jumps`)
			ctx:SetPlayerShared(player, "Jumps", self.jumps[player])
		else
			local _, _, root = ctx:GetCharacter(player)
			if root then
				Notifier.Effect("Fireworks", root.Position, { rgb(255, 120, 40), rgb(255, 210, 60) })
				ctx:Knockback(player, Vector3.new(0, 55, 45), 1.2) -- thrown off the bridge, bots too
			end
			ctx:Eliminate(player, "rope")
		end
	end
end

function FireRope:Start()
	local ctx = self.context
	-- Standing height of each player's root above the floor, for judging jumps.
	for _, player in ctx:GetAlivePlayers() do
		local _, _, root = ctx:GetCharacter(player)
		local height = root and (root.Position.Y - self.floorY)
		self.standing[player] = if height and height > 1.5 and height < 5 then height else 3
		self.history[player] = {}
	end

	local t0 = ctx:Now() + 0.4
	local firstW = 2 * math.pi / FIRST_PERIOD
	self.segments = {
		{ T0 = t0, A0 = math.pi, W = firstW }, -- starts at the top
		{ T0 = t0 + math.pi / firstW, A0 = 0, W = 2 * math.pi / self:_nextPeriod() },
	}
	self:_publish(0)
	ctx:SetStatus("Jump the fire rope!")

	-- Height history for every player, in server time.
	ctx:Heartbeat(function()
		local now = ctx:Now()
		for _, player in ctx:GetAlivePlayers() do
			local _, _, root = ctx:GetCharacter(player)
			local samples = self.history[player]
			if not root or not samples then
				continue
			end
			local height = self:_floorHeight(root.Position)
			if height then
				table.insert(samples, { T = now, H = height })
			end
			while samples[1] and now - samples[1].T > 2 do
				table.remove(samples, 1)
			end
		end
	end)

	-- Each bottom pass: judge it a moment later (to let lagging positions arrive) and plan the
	-- turn after next, so clients always know the rope's path one full turn ahead.
	ctx:Loop(function(): number?
		local upcoming = self.segments[#self.segments]
		local now = ctx:Now()
		if now < upcoming.T0 then
			return math.min(0.05, upcoming.T0 - now)
		end
		local passTime = upcoming.T0
		self.passes += 1
		ctx:Delay(0.4, function()
			self:_judge(passTime)
		end)
		table.insert(self.segments, {
			T0 = upcoming.T0 + 2 * math.pi / upcoming.W,
			A0 = 0,
			W = 2 * math.pi / self:_nextPeriod(),
		})
		while #self.segments > 4 do
			table.remove(self.segments, 1)
		end
		local period = 2 * math.pi / upcoming.W
		local heat = math.clamp((FIRST_PERIOD - period) / (FIRST_PERIOD - FASTEST_PERIOD), 0, 1)
		self:_publish(heat)
		ctx:SetStatus(`Jumps: {self.passes}  •  Players left: {ctx:AliveCount()}`)
		return 0.02
	end)
end

-- Survivors first, then whoever lasted longest; jumps break ties.
function FireRope:GetResults()
	local results = self.context:SurvivalResults()
	for _, entry in results.Entries do
		local jumps = self.jumps[entry.Player] or 0
		entry.Rank += jumps * 0.001
		entry.ScoreText = `{entry.ScoreText} • {jumps} {if jumps == 1 then "jump" else "jumps"}`
	end
	return results
end

return FireRope

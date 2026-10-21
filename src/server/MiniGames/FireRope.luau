-- Fire Rope (Survival, 75s, up to 12 players). Mechanics after "Hot Rope Jump": everyone stands on
-- a long stone bridge over lava while two fire wheels swing a burning rope around it. Jump as it
-- sweeps under your feet; it keeps speeding up, with the odd change of pace. Touch it and you're
-- out. Last one jumping wins; ties go to whoever cleared more jumps.
--
-- The rope's angle follows a schedule shared with every client (MG_Rope): a list of segments that
-- each start at a bottom pass and are announced one full turn ahead, so clients draw it perfectly
-- in sync. At every pass the server checks that each player is in the air as the rope goes under
-- them (a short moment either side of the pass, shifted by half their ping so a jump that looked
-- right on their screen counts). Being in the air at some other moment doesn't count, so holding
-- jump isn't a way through (owner: "its super easy right now not to get hit"). Bots are judged the same way
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
local CLEAR = 1.6 -- how far a player's root must rise above standing height to clear the rope
local CLEAR_WINDOW = 0.07 -- a jumper must be that high from this long before the pass to this long after
local FIRST_PERIOD = 3.0
local FASTEST_PERIOD = 1.05 -- a Roblox jump is ~0.5s in the air; this leaves time to land and go again
local LAVA_DROP = 24
local TEMPLE_DISTANCE = 175 -- how far ahead of the bridge the Dragon Temple stands
local TEMPLE_SCALE = 1.35
local TEMPLE_SINK = 10 -- (unscaled) how deep the temple's bottom tier sits in the lava: keeps the dragon head below the HUD

local rng = Random.new()

type Segment = { T0: number, A0: number, W: number }
type Sample = { T: number, H: number }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- An invisible marker the client lights a fire on (size in the "Flame" attribute), with a glow.
local function flameSpot(ctx, position: Vector3, size: number)
	local spot = Build.Decor({
		Name = "FlameSpot",
		Size = Vector3.one,
		Transparency = 1,
		CFrame = CFrame.new(position),
		Parent = ctx.Arena,
	})
	spot:SetAttribute("Flame", size)
	Build.Light(spot, rgb(255, 150, 60), size * 3.4, 2)
end

-- An invisible marker the client puffs steam from, where lava falls into the lake.
local function steamSpot(ctx, position: Vector3, size: number)
	local spot = Build.Decor({
		Name = "SteamSpot",
		Size = Vector3.one,
		Transparency = 1,
		CFrame = CFrame.new(position),
		Parent = ctx.Arena,
	})
	spot:SetAttribute("Steam", size)
end

-- Rock spires around the lake (like Scenery.RockRim), leaving the view to the temple (-Z) open.
local function rockRim(ctx, center: Vector3, radius: number, count: number)
	for index = 0, count - 1 do
		local angle = (index + rng:NextNumber(-0.3, 0.3)) / count * math.pi * 2
		local fromTemple = math.abs((angle + math.pi / 2 + math.pi) % (2 * math.pi) - math.pi)
		if fromTemple < math.rad(40) then
			continue
		end
		local distance = radius * rng:NextNumber(0.94, 1.08)
		MeshLibrary.Get("Spire", {
			Scale = rng:NextNumber(1.1, 2.1),
			CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * distance, -1, math.sin(angle) * distance))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = ctx.Arena,
		})
	end
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

	-- The Dragon Temple's fire festival (owner: "I saw the lava rope one and that one kinda sucks"):
	-- the bridge spans a lava lake in front of a stepped temple whose dragon head pours lava down its
	-- stairs, framed by basalt cliffs with lava falls, fire braziers and volcanoes on the horizon.
	local lake = origin - Vector3.new(0, LAVA_DROP, 0)
	local base = lake - Vector3.new(0, 1, 0) -- props standing in the lava are based here
	local function facingBridge(position: Vector3): CFrame
		return CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z))
	end
	Scenery.LavaLake(ctx, lake, 300)
	Scenery.Ground(ctx, lake)
	rockRim(ctx, lake, 150, 22)
	-- The temple rises out of the lava (its bottom tier mostly under it), which keeps the dragon head
	-- low enough on screen to stay clear of the round banner.
	local temple = facingBridge(base + Vector3.new(0, -TEMPLE_SINK * TEMPLE_SCALE, -TEMPLE_DISTANCE))
	MeshLibrary.Get("DragonTemple", { Scale = TEMPLE_SCALE, CFrame = temple, Parent = ctx.Arena })
	-- Steam where its lava cascade meets the lake.
	steamSpot(ctx, (temple * CFrame.new(0, TEMPLE_SINK * TEMPLE_SCALE + 2, -36.5 * TEMPLE_SCALE)).Position, 3)
	for _, spot in
		{ Vector3.new(-102, 0, -112), Vector3.new(102, 0, -112), Vector3.new(-104, 0, 112), Vector3.new(104, 0, 112) }
	do
		local scale = if spot.Z < 0 then 1.25 else 1.05
		local cframe = facingBridge(base + spot)
		MeshLibrary.Get("LavaFall", { Scale = scale, CFrame = cframe, Parent = ctx.Arena })
		steamSpot(ctx, (cframe * CFrame.new(0, 2, -13 * scale)).Position, 2)
	end
	Scenery.Volcano(ctx, lake + Vector3.new(-175, -2, -345), origin, 2.4)
	Scenery.Volcano(ctx, lake + Vector3.new(235, -2, -300), origin, 1.7)
	Scenery.Volcano(ctx, lake + Vector3.new(40, -2, 360), origin, 1.9)

	-- The bridge: a sandstone walkway with terracotta borders on carved arches over the lava.
	Shapes.Slab(Vector3.new(LENGTH, 3, DEPTH), 1.2, {
		Name = "Bridge",
		CFrame = CFrame.new(origin - Vector3.new(0, 1.5, 0)),
		Color = rgb(244, 218, 178),
		Material = Enum.Material.Sandstone,
		Parent = ctx.Arena,
	})
	for _, side in { -1, 1 } do
		Build.Decor({
			Name = "Border",
			Size = Vector3.new(LENGTH - 2.4, 0.12, 0.9),
			CFrame = CFrame.new(origin + Vector3.new(0, 0.04, side * (DEPTH / 2 - 0.85))),
			Color = rgb(222, 100, 66),
			Parent = ctx.Arena,
		})
	end
	MeshLibrary.Get("TempleBridge", { CFrame = CFrame.new(base), Parent = ctx.Arena })

	-- A sun wheel at each end turns the rope (the client spins the wheels in time with it), its axle
	-- in a stone tower with a fire bowl on top.
	for _, side in { -1, 1 } do
		local wheelX = side * (LENGTH / 2 + 7)
		local wheel = MeshLibrary.Get("SunWheel", { Parent = ctx.Arena })
		wheel.Name = if side < 0 then "WheelL" else "WheelR"
		local box = wheel:GetBoundingBox()
		local center = self.axis + Vector3.new(wheelX, 0, 0)
		wheel:PivotTo(wheel:GetPivot() + (center - box.Position))

		local tower = base + Vector3.new(wheelX + side * 4.7, 0, 0)
		MeshLibrary.Get("RopeTower", {
			CFrame = CFrame.lookAt(tower, tower - Vector3.new(side, 0, 0)), -- medallion towards the wheel
			Parent = ctx.Arena,
		})
		flameSpot(ctx, tower + Vector3.new(0, 43, 0), 7)
	end

	-- Fire braziers rising out of the lava either side of the bridge, clear of the rope. The pair in
	-- front (where the rope comes down) stands wider, further out and lower, so their fires sit below
	-- the deck on screen and never behind the descending rope.
	for _, spot in
		{ Vector3.new(-30, -6, -28), Vector3.new(30, -6, -28), Vector3.new(-22, 0, 17), Vector3.new(22, 0, 17) }
	do
		local position = base + spot
		MeshLibrary.Get("FireBrazier", { CFrame = CFrame.new(position), Parent = ctx.Arena })
		flameSpot(ctx, position + Vector3.new(0, 27.6, 0), 6)
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
		-- What their screen showed at the pass reaches the server about half a round trip later.
		local at = passTime + 0.03 + (if ok and type(ping) == "number" then math.clamp(ping, 0, 0.5) / 2 else 0.05)
		local lowest = math.huge
		local nearest, nearestGap = nil, 0.15
		for _, sample in samples do
			local gap = math.abs(sample.T - at)
			if gap <= CLEAR_WINDOW then
				lowest = math.min(lowest, sample.H)
			elseif gap < nearestGap then
				nearest, nearestGap = sample.H, gap
			end
		end
		if lowest == math.huge then
			if not nearest then
				continue -- off the bridge (falling): the fall check deals with it
			end
			lowest = nearest
		end
		local need = (self.standing[player] or 3) + CLEAR
		if lowest >= need then
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

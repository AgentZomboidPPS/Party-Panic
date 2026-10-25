-- Sky Stack (Race, 60s, 1-12 players): everyone builds a tower to the clouds, one block at a time.
-- Owner: "If you could make any mini game. What would it be?" ... "Build it." (the pitch: "Every
-- player gets their own tower in a row of up to 12, with the sky behind them. A block slides back
-- and forth above your tower, and you tap to drop it. Any part hanging over the edge gets sliced
-- off, so each miss makes your next block smaller. A perfect drop keeps the block full size and
-- sends a gust to the towers on either side, which makes their next block swing faster. If your
-- block shrinks to nothing, your tower crumbles and you're out. The first player to reach the cloud
-- line wins. If time runs out, the tallest tower wins.")
--
-- How it works: each player has a lane with a stone base, a golden star floating at the cloud line
-- (Stack.GOAL floors up) and a spot on the plaza in front where they stand. The rules are in
-- Shared/Logic/SkyStack: the next block slides across the top one on a schedule from the server's
-- clock (its slide), and DROP (api:Action "Drop" with the time the player's device pressed it;
-- ctx:BotAction for bots) is judged here, at when it was pressed (Logic/Buzzer.PressTime: if it
-- looked lined up on the player's screen, it lands lined up). A perfect drop snaps on; three in a
-- row grow the block back a little and gust the towers either side (their next block slides
-- faster); an off drop slices the overhang off; one that leaves too little is a miss: the block
-- falls, the tower is done and its builder is out (their floors still count in the standings).
--
-- Every tower is shared on its own ("T<userId>": its floors, every block, the slide, the last drop
-- and what fell, the streak, a gust on its way, its place), so clients draw every tower and its
-- sliding block from the same schedule, and a client that starts late still gets the whole tower.
-- Reaching the cloud line finishes the race for that tower (places go by when the last floor's DROP
-- was pressed, so a person's ping can't hand a close finish to a bot). The round ends when
-- nobody (no person) is still building, or at the buzzer: then the tallest towers win, sooner
-- breaking ties. Nothing here can touch anyone (the blocks are drawn by clients and decide nothing),
-- so there's no hazard to apply to bots on the server; bots press DROP through the same judge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Buzzer = require(ReplicatedStorage.Shared.Logic.Buzzer)
local Stack = require(ReplicatedStorage.Shared.Logic.SkyStack)

local MiniGame = require(script.Parent.Kit.MiniGame)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)

local SkyStack = MiniGame.Define("SkyStack", { Results = "Score", ScoreUnit = "floors" })

local LANE = 26 -- lane width (studs): a block swinging out never reaches the next tower
local BASE_TOP = 3 -- the base's top over the plaza (SkyStackBase's Height): floor 1 sits on it
local STAND = 10 -- where players stand, in front of their tower (+Z)
local FIRST_DELAY = 0.6 -- from GO to the first block setting off
local CELEBRATE = 2.5 -- from the last builder finishing (or crumbling) to the end of the round
local HOLD = 0.3 -- near the buzzer the end waits this long for presses still on their way

-- Lane colors (each tower's blocks, base trim and spot; the lane number is the second cue).
local COLORS = {
	Color3.fromRGB(255, 80, 90),
	Color3.fromRGB(70, 150, 255),
	Color3.fromRGB(255, 205, 50),
	Color3.fromRGB(90, 210, 100),
	Color3.fromRGB(190, 110, 255),
	Color3.fromRGB(255, 145, 50),
	Color3.fromRGB(70, 220, 215),
	Color3.fromRGB(255, 120, 200),
	Color3.fromRGB(160, 110, 70),
	Color3.fromRGB(40, 150, 140),
	Color3.fromRGB(225, 50, 150),
	Color3.fromRGB(170, 215, 40),
}

local rng = Random.new()

type Tower = {
	Lane: number,
	X: number,
	Color: Color3,
	Blocks: { Stack.Block },
	Top: Stack.Block,
	Streak: number,
	Slide: Stack.Slide?,
	GustNext: boolean,
	GustFrom: number?,
	Drops: number,
	Last: { [string]: any }?, -- the last drop: kind, offset, what fell
	ReachedAt: number, -- seconds into the round the top floor went on
	Place: number?, -- reached the cloud line, in this place (by FinishedAt)
	FinishedAt: number?, -- seconds into the round the last floor's DROP was pressed
	FinishedIn: number?, -- the same, to a tenth (shown)
	Out: boolean,
	Gone: boolean,
	Spot: CFrame,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function color3(color: Color3): { number }
	return { math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5) }
end

local function box(block: Stack.Block): { number }
	return { block.X0, block.X1, block.Z0, block.Z1 }
end

-- Scenery is only to look at: nothing solid where nothing is drawn (a tree's collision hull is
-- bigger than its leaves), and nobody can walk to it anyway.
local function decor(model: Instance): Instance
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	return model
end

-- The plaza: a long paved strip under the row of towers (what everyone stands on), grass out to the
-- hills, cranes at both ends of the row, clouds along the cloud line behind the towers, trees and
-- balloons further out.
local function buildPlaza(ctx, origin: Vector3, laneCount: number)
	local arena = ctx.Arena
	local ground = origin.Y
	local lanes = math.max(laneCount, 4)
	local half = lanes * LANE / 2 + 8
	local goalY = ground + BASE_TOP + Stack.GOAL * Stack.BLOCK
	local plaza = Build.Folder("Plaza", arena)

	Build.Part({
		Name = "Grass",
		Size = Vector3.new(1400, 4, 1000),
		CFrame = CFrame.new(origin.X, ground - 0.4 - 2, origin.Z - 200),
		Color = rgb(108, 190, 84),
		Material = Enum.Material.Grass,
		CastShadow = false,
		Parent = plaza,
	})
	-- The paved strip players stand on (solid and drawn), with a curb all round.
	Build.Part({
		Name = "Paving",
		Size = Vector3.new(half * 2, 1, 44),
		CFrame = CFrame.new(origin.X, ground - 0.5, origin.Z + 2),
		Color = rgb(236, 226, 206),
		Material = Enum.Material.Pavement,
		CastShadow = false,
		Parent = plaza,
	})
	for _, side in { -1, 1 } do
		Build.Decor({
			Name = "Curb",
			Size = Vector3.new(half * 2 + 1.2, 0.5, 0.6),
			CFrame = CFrame.new(origin.X, ground + 0.05, origin.Z + 2 + side * 22.3),
			Color = rgb(200, 186, 160),
			Material = Enum.Material.Concrete,
			Parent = plaza,
		})
		Build.Decor({
			Name = "Curb",
			Size = Vector3.new(0.6, 0.5, 45.2),
			CFrame = CFrame.new(origin.X + side * (half + 0.3), ground + 0.05, origin.Z + 2),
			Color = rgb(200, 186, 160),
			Material = Enum.Material.Concrete,
			Parent = plaza,
		})
	end

	-- Cranes at both ends, their jibs reaching over the row.
	for _, side in { -1, 1 } do
		MeshLibrary.Get("SkyStackCrane", {
			CFrame = CFrame.new(origin.X + side * (half + 14), ground - 0.4, origin.Z - 14)
				* CFrame.Angles(0, math.rad(side * 110), 0), -- the jib (its -Z) toward the row
			Parent = plaza,
		})
	end

	-- Clouds along the cloud line, behind the towers and off to the sides (the cameras look at the
	-- towers from the front, so none sits between a player and their tower).
	local clouds = Build.Folder("Clouds", plaza)
	local x = origin.X - half - 60
	while x < origin.X + half + 60 do
		decor(MeshLibrary.Get("SkyStackCloud", {
			Scale = rng:NextNumber(1.4, 2.4),
			CFrame = CFrame.new(x, goalY - 2 + rng:NextNumber(-1.5, 2), origin.Z - rng:NextNumber(16, 30))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = clouds,
		}))
		x += rng:NextNumber(14, 22)
	end
	for _ = 1, 16 do
		decor(MeshLibrary.Get("SkyStackCloud", {
			Scale = rng:NextNumber(2.5, 4.5),
			CFrame = CFrame.new(
				origin.X + rng:NextNumber(-half - 150, half + 150),
				goalY + rng:NextNumber(14, 60),
				origin.Z - rng:NextNumber(80, 260)
			) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = clouds,
		}))
	end

	-- Trees and bushes behind the row and at its ends.
	local leafColors = { rgb(80, 190, 90), rgb(110, 200, 80), rgb(70, 165, 95), rgb(140, 205, 85) }
	local flowerColors = { rgb(255, 130, 190), rgb(255, 220, 90), rgb(180, 140, 255), rgb(255, 255, 255) }
	local treeX = origin.X - half - 40
	while treeX < origin.X + half + 40 do
		decor(MeshLibrary.Get("Tree", {
			Scale = rng:NextNumber(1.6, 2.6),
			Colors = { Leaves = leafColors[rng:NextInteger(1, #leafColors)] },
			CFrame = CFrame.new(treeX, ground - 0.4, origin.Z - rng:NextNumber(40, 70))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = plaza,
		}))
		treeX += rng:NextNumber(18, 28)
	end
	for _, side in { -1, 1 } do
		for row = 0, 2 do
			decor(MeshLibrary.Get("Bush", {
				Scale = rng:NextNumber(1.1, 1.7),
				Colors = { Flowers = flowerColors[rng:NextInteger(1, #flowerColors)] },
				CFrame = CFrame.new(origin.X + side * (half + 5), ground - 0.4, origin.Z + 14 - row * 12)
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = plaza,
			}))
		end
	end
	-- Hot air balloons drifting over the far field.
	local balloons = {
		{ -120, 30, 120, rgb(255, 90, 90) },
		{ 90, 46, 170, rgb(70, 160, 255) },
		{ -40, 64, 240, rgb(255, 200, 60) },
		{ 160, 80, 300, rgb(130, 220, 120) },
	}
	for _, spec in balloons do
		decor(MeshLibrary.Get("MechaMarathonSkyBalloon", {
			Scale = rng:NextNumber(1.1, 1.5),
			Colors = { StripesA = spec[4] },
			CFrame = CFrame.new(origin.X + spec[1], goalY + spec[2], origin.Z - spec[3])
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = plaza,
		}))
	end
	-- Soft hills on the horizon behind the row (squashed spheres half sunk into the grass).
	for hill = 0, 8 do
		local angle = math.rad(-160 + hill * 18 + rng:NextNumber(-4, 4))
		local distance = rng:NextNumber(420, 480)
		local size = Vector3.new(rng:NextNumber(180, 260), rng:NextNumber(60, 110), rng:NextNumber(120, 170))
		local center = Vector3.new(
			origin.X + math.cos(angle) * distance,
			ground - size.Y * 0.2,
			origin.Z - 120 + math.sin(angle) * distance
		)
		local part = Build.Decor({
			Name = "Hill",
			Size = size,
			CFrame = CFrame.lookAt(center, Vector3.new(origin.X, center.Y, origin.Z - 120)),
			Color = rgb(96, 176, 86):Lerp(rgb(70, 140, 90), rng:NextNumber(0, 1)),
			Material = Enum.Material.Grass,
			Parent = plaza,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
end

function SkyStack:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn" -- nothing knocks anyone off the plaza; a fall just puts you back
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 30
	local origin = ctx.Origin.Position
	self.towers = {} :: { [any]: Tower }
	self.order = {} :: { any } -- players in lane order
	self.announced = false
	self.startAt = math.huge
	self.ending = false
	self.phase = "Ready"

	local players = ctx:GetPlayers()
	for index = #players, 2, -1 do -- lanes in a random order
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local count = #players
	buildPlaza(ctx, origin, count)

	local goalY = origin.Y + BASE_TOP + Stack.GOAL * Stack.BLOCK
	local towers = Build.Folder("Towers", ctx.Arena)
	local lanes = {}
	for index, player in players do
		local x = origin.X + (index - (count + 1) / 2) * LANE
		local color = COLORS[(index - 1) % #COLORS + 1]
		local base = MeshLibrary.Get("SkyStackBase", {
			Colors = { Trim = color },
			CFrame = CFrame.new(x, origin.Y, origin.Z),
			Parent = towers,
		})
		base.Name = "Base_" .. player.UserId
		local star = MeshLibrary.Get("SkyStackStar", {
			Colors = { Ribbon = color },
			-- Its smiling face (-Z) turned toward the players' cameras (they look from the front right).
			CFrame = CFrame.new(x, goalY + 1.2, origin.Z) * CFrame.Angles(0, math.rad(-135), 0),
			Parent = towers,
		})
		star.Name = "Star_" .. player.UserId
		star:SetAttribute("User", player.UserId)
		-- Where the player stands: a disc in the lane's color on the paving, the lane number in
		-- front of it.
		local spotAt = Vector3.new(x, origin.Y, origin.Z + STAND)
		Build.Decor({
			Name = "Spot",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, 5, 5),
			CFrame = CFrame.new(spotAt + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Parent = towers,
		})
		local tile = Build.Decor({
			Name = "LaneTile",
			Size = Vector3.new(4, 0.14, 4),
			CFrame = CFrame.new(spotAt + Vector3.new(0, 0.07, 5)),
			Color = rgb(250, 250, 245),
			Parent = towers,
		})
		Build.SurfaceText(tile, Enum.NormalId.Top, tostring(index), {
			TextColor3 = rgb(40, 50, 80), -- dark ink on the white tile, ringed in the lane's color
			TextStrokeColor3 = color,
			TextStrokeTransparency = 0,
			PixelsPerStud = 16,
			LightInfluence = 1,
			Brightness = 1,
		}).Font =
			Enum.Font.FredokaOne

		local spot = CFrame.lookAt(spotAt + Vector3.new(0, 3, 0), Vector3.new(x, origin.Y + 3, origin.Z))
		self.towers[player] = {
			Lane = index,
			X = x,
			Color = color,
			Blocks = {},
			Top = Stack.Base(),
			Streak = 0,
			Slide = nil,
			GustNext = false,
			GustFrom = nil,
			Drops = 0,
			Last = nil,
			ReachedAt = 0,
			Place = nil,
			FinishedAt = nil,
			FinishedIn = nil,
			Out = false,
			Gone = false,
			Spot = spot,
		}
		table.insert(self.order, player)
		table.insert(lanes, {
			User = player.UserId,
			Lane = index,
			X = x,
			Color = color3(color),
			Name = player.DisplayName,
		})
	end
	ctx:SetSharedJSON("Layout", {
		Lanes = lanes,
		Origin = { origin.X, origin.Y, origin.Z },
		BaseTop = origin.Y + BASE_TOP,
		Goal = Stack.GOAL,
	})
	ctx:SetShared("Stage", "Ready")
	for player in self.towers do
		self:_share(player)
	end

	-- SpawnAll hands out points in ctx:GetPlayers() order, not the shuffled lane order.
	local ordered = {}
	for _, player in ctx:GetPlayers() do
		local tower = self.towers[player]
		table.insert(ordered, if tower then tower.Spot else CFrame.new(origin + Vector3.new(0, 3, STAND)))
	end
	ctx:SpawnAll(ordered, true)
	ctx.Hooks.Respawn = function(player)
		local tower = self.towers[player]
		return if tower then tower.Spot else nil
	end
	for player in self.towers do
		ctx:SetScoreText(player, "0 floors")
	end
	ctx:SetStatus("Stack your tower to the clouds!")
	ctx.Hooks.PlayerLeft = function(player)
		local tower = self.towers[player]
		if tower and not tower.Gone then
			tower.Gone = true
			tower.Slide = nil
			self:_share(player)
			self:_checkDone()
		end
	end
end

-- Shares one tower (everything a client needs to draw it from scratch).
function SkyStack:_share(player)
	local tower = self.towers[player]
	if not tower then
		return
	end
	local blocks = table.create(#tower.Blocks)
	for index, block in tower.Blocks do
		blocks[index] = box(block)
	end
	local slide = tower.Slide
	self.context:SetSharedJSON(`T{player.UserId}`, {
		L = #tower.Blocks,
		B = blocks,
		S = if slide
			then { L = slide.Level, A = slide.Axis, D = slide.Dir, T = slide.Start, V = slide.Speed, G = slide.Gust }
			else nil,
		N = tower.Drops,
		K = tower.Last,
		Q = tower.Streak,
		W = tower.GustFrom,
		P = tower.Place,
		In = tower.FinishedIn,
		X = tower.Out,
		Gone = tower.Gone,
	})
end

-- Whether a tower is still being built.
local function building(tower: Tower): boolean
	return not tower.Out and not tower.Gone and tower.Place == nil
end

function SkyStack:Start()
	local ctx = self.context
	local now = ctx:Now()
	self.startAt = now
	self.phase = "Stack"
	for player, tower in self.towers do
		if not ctx:State(player) then
			tower.Gone = true -- left (or never got a character) before GO
		else
			tower.Slide = Stack.NewSlide(1, now + FIRST_DELAY)
		end
		self:_share(player)
	end
	ctx:SetShared("Stage", "Stack")
	-- Everyone stays at their spot (jumping still works, for joy).
	for _, player in ctx:GetPlayers() do
		ctx:SetWalkSpeed(player, 0)
	end
	ctx.Hooks.CharacterReady = function(player)
		ctx:SetWalkSpeed(player, 0)
	end
	ctx:OnAction("Drop", function(player, sentAt, level)
		self:_drop(player, sentAt, level)
	end, { Interval = 0.1 })

	local duration = ctx.Definition.Duration
	local lastStatus = ""
	local held = false
	ctx:Loop(function(): number?
		-- Presses made just before the buzzer may still be on their way: the end waits a moment.
		if not held and ctx:Elapsed() >= duration - 0.1 then
			held = true
			ctx:HoldEnd(0.1 + HOLD)
		end
		local status = self:_status()
		if status ~= lastStatus then
			lastStatus = status
			ctx:SetStatus(status)
		end
		return 0.1
	end)
end

-- The status line: the tallest tower still in the race, or who reached the clouds first.
function SkyStack:_status(): string
	local first, leader, best = nil, nil, -1
	for player, tower in self.towers do
		if tower.Gone then
			continue
		end
		if tower.Place == 1 then
			first = player
		end
		local floors = #tower.Blocks
		if floors > best or (floors == best and leader and tower.ReachedAt < self.towers[leader].ReachedAt) then
			leader, best = player, floors
		end
	end
	if first then
		return `🏆 {first.DisplayName} reached the clouds!`
	end
	if leader and best > 0 then
		return `Tallest: {leader.DisplayName} · {best}/{Stack.GOAL}`
	end
	return "Stack your tower to the clouds!"
end

-- How long a player's round trip is (Buzzer allows half of it for a press on its way); bots press
-- on the server, with no lag.
local function lagOf(player): number
	if BotRegistry.IsBot(player) then
		return 0
	end
	local ok, ping = pcall(function()
		return (player :: any):GetNetworkPing()
	end)
	return if ok and type(ping) == "number" then math.clamp(ping, 0, 0.6) else 0.2
end

-- DROP: judged at when it was pressed, against the slide that was on screen then (`level` is the
-- floor the player's device was dropping: a press meant for another block doesn't count). A press
-- that doesn't count is answered ("Refused"), so the player's device takes back the drop it showed.
function SkyStack:_drop(player, sentAt: any, level: any)
	local ctx = self.context
	local tower = self.towers[player]
	if not tower or not building(tower) or self.phase ~= "Stack" then
		ctx:Fire(player, "Refused")
		return
	end
	local slide = tower.Slide
	if not slide or (type(level) == "number" and level ~= slide.Level) then
		ctx:Fire(player, "Refused")
		return
	end
	local now = ctx:Now()
	local at = Buzzer.PressTime(sentAt, now, lagOf(player))
	if not ctx:InTime(at) or not Stack.Counts(slide, at) then
		ctx:Fire(player, "Refused") -- after the buzzer, or a double tap meant for the last block
		return
	end
	local drop = Stack.Drop(tower.Top, slide, at, tower.Streak)
	tower.Drops += 1
	tower.Streak = drop.Streak
	tower.Last = {
		K = drop.Kind,
		O = drop.Offset,
		F = if drop.Falling then box(drop.Falling) else nil,
		A = slide.Axis,
		C = drop.Combo,
	}
	local elapsed = math.max(at - self.startAt, 0)
	if drop.Kind == "Miss" or not drop.Block then
		tower.Out = true
		tower.Slide = nil
		ctx:SetScoreText(player, `Crumbled at {#tower.Blocks}`)
		self:_share(player)
		ctx:Eliminate(player, "crumbled", 1.6) -- out now; the "You're out!" once the block has fallen
		self:_checkDone()
		return
	end
	local block = drop.Block :: Stack.Block
	table.insert(tower.Blocks, block)
	tower.Top = block
	tower.ReachedAt = elapsed
	local floors = #tower.Blocks
	ctx:AddScore(player, 1)
	if drop.Combo then
		self:_gust(player)
	end
	if floors >= Stack.GOAL then
		tower.FinishedAt = elapsed
		tower.FinishedIn = math.floor(elapsed * 10) / 10
		tower.Slide = nil
		self:_placeFinishers(player)
		self:_checkDone()
		return
	end
	ctx:SetScoreText(player, `{floors} floors`)
	-- Once time is up nothing new starts: a press made before the buzzer still lands, but no block
	-- follows it.
	tower.Slide = if ctx:TimeIsUp() then nil else Stack.NewSlide(floors + 1, at + Stack.SPAWN, tower.GustNext)
	tower.GustNext = false
	tower.GustFrom = nil
	self:_share(player)
end

-- Places at the clouds go by when the last floor's DROP was pressed, not by when it reached the
-- server (a person's press travels for half their ping; a bot's doesn't), so a finish that arrives
-- second but was pressed first moves ahead, and anyone it passes is shared again.
function SkyStack:_placeFinishers(newcomer)
	local ctx = self.context
	local finishers = {}
	for player, tower in self.towers do
		if tower.FinishedAt then
			table.insert(finishers, player)
		end
	end
	table.sort(finishers, function(a, b)
		return (self.towers[a].FinishedAt :: number) < (self.towers[b].FinishedAt :: number)
	end)
	for place, player in finishers do
		local tower = self.towers[player]
		if tower.Place ~= place or player == newcomer then
			tower.Place = place
			ctx:SetScoreText(player, string.format("%s • %.1fs", self:_ordinal(place), tower.FinishedIn or 0))
			self:_share(player)
		end
	end
	if not self.announced and self.towers[newcomer].Place == 1 then
		self.announced = true
		ctx:Announce(`🏆 {newcomer.DisplayName} reached the clouds!`, "success", 3)
	end
end

function SkyStack:_ordinal(place: number): string
	local suffix = "th"
	if place % 100 < 11 or place % 100 > 13 then
		suffix = ({ "st", "nd", "rd" })[place % 10] or "th"
	end
	return `{place}{suffix}`
end

-- A combo: the towers either side get a gust, so their next block slides faster (one gust at a
-- time: a tower that already has one coming doesn't get a second). The cue names who blew it and
-- whom it reached.
function SkyStack:_gust(player)
	local tower = self.towers[player]
	local hit = {}
	for _, step in { -1, 1 } do
		local neighbor = self.order[tower.Lane + step]
		local other = neighbor and self.towers[neighbor]
		if other and building(other) and not other.GustNext then
			other.GustNext = true
			other.GustFrom = player.UserId
			table.insert(hit, neighbor.UserId)
			self:_share(neighbor)
		end
	end
	self.context:Fire(nil, "Gust", player.UserId, hit)
end

-- Once no person is still building (all at the clouds, crumbled or gone), the round wraps up.
function SkyStack:_checkDone()
	if self.ending then
		return
	end
	for player, tower in self.towers do
		if building(tower) and not BotRegistry.IsBot(player) then
			return
		end
	end
	self.ending = true
	local ctx = self.context
	ctx:Delay(CELEBRATE, function()
		self.phase = "Done"
		ctx:End("AllDone")
	end)
end

function SkyStack:Stop()
	self.phase = "Done"
	for player, tower in self.towers do
		if tower.Slide then
			tower.Slide = nil
			self:_share(player)
		end
	end
	self.context:SetShared("Stage", "Done")
end

-- At the clouds first (by place), then the tallest towers, sooner breaking ties.
function SkyStack:GetResults()
	local ctx = self.context
	local entries = {}
	for player in ctx.Participants do
		if not player.Parent then
			continue
		end
		local tower = self.towers[player]
		local floors = if tower then #tower.Blocks else 0
		local text
		if tower and tower.Place then
			text = string.format("%s • %.1fs", self:_ordinal(tower.Place), tower.FinishedIn or 0)
		elseif tower and tower.Out then
			text = `Crumbled at {floors}`
		else
			text = `{floors}/{Stack.GOAL} floors`
		end
		table.insert(entries, {
			Player = player,
			Rank = if tower and tower.FinishedAt
				then Stack.Rank(floors, tower.FinishedAt, true)
				else Stack.Rank(floors, if tower then tower.ReachedAt else 0),
			ScoreText = text,
			BestScore = floors,
		})
	end
	return { Entries = entries }
end

return SkyStack

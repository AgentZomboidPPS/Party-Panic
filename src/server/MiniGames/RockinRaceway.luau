-- Rockin' Raceway (Race, up to 60s, 1-12 players). After "Rockin' Raceway" (Mario Party 3): a
-- hobby-horse race once round a fairground oval. Hold GALLOP to speed up, but galloping eats your
-- horse's carrots: run the carrot meter dry past the red line and your horse spins out. Let go to
-- trot and the carrots grow back. Orange carrot panels on the track give a DASH (ride over them);
-- blue hurdle panels slow you down unless you HOP them. First across the finish wins; the rest are
-- ranked by how far they got.
--
-- How it works: every rider has a lane (spread over the twelve lanes, in a random order; the lane
-- number is painted at the start and shown on the race bar, the horse's colour is the second cue).
-- The server races everyone (Shared/Logic/RockinRacewayTrack: Ride) from their inputs only: GALLOP
-- held or not (api:Action "Gallop", true/false) and HOP (api:Action "Hop" with the time the player
-- pressed it on their own screen). It shares every rider's distance, speed, carrots, hop and
-- spin-out ("Riders", 10 times a second) and clients draw the hobby horses bobbing round the oval
-- from that (each player's own client also seats its own character on its horse, so everyone sees
-- them where they ride; bots are seated by the server here).
--
-- Fair panels (owner: "the precision games will feel super bad if we dont"): the panel rows are the
-- same in every lane. When a rider's distance passes a panel, the server notes the moment and waits
-- out that rider's ping before judging it, so a HOP pressed while the horse was still short of the
-- hurdle on the player's screen counts even if it arrives a little later. A hurdle is cleared when
-- the hop holds the whole horse (nose to wheel) above its bar while it passes (Track.Clears, the
-- same rule the client lights HOP by); a carrot is taken unless the horse is that high over it.
--
-- Review pass: the race freezes the moment it closes (no riding, no input, bots stop too); riders
-- home in the same step take places in the order they crossed; the results renumber the finishers
-- still here.
--
-- Bots press GALLOP and HOP through ctx:BotAction (Bots/RockinRaceway.luau) and are judged by the
-- same rules, so hurdles slow bots and dry meters spin them out exactly like players. Nothing is
-- solid on the track but the ground: every prop and painted line is decoration only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Track = require(ReplicatedStorage.Shared.Logic.RockinRacewayTrack)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local RockinRaceway = MiniGame.Define("RockinRaceway", { Results = "Score" })

local FINISH_CLOCK = 10 -- seconds the finish stays open after the first rider is home
local MAX_LEEWAY = 0.4
local ROOT_Y = 3 -- a standing character's root above the ground

-- Horse colours, one per lane (the lane number is the second cue).
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
	Color3.fromRGB(250, 250, 250),
	Color3.fromRGB(225, 50, 150),
	Color3.fromRGB(170, 215, 40),
}

local rng = Random.new()

type Rider = Track.Rider & {
	Player: any,
	Lane: number,
	Offset: number,
	HopAt: number,
	Next: number, -- the next panel row to pass
	Pending: { { Panel: Track.Panel, At: number, V: number, JudgeAt: number } },
	Finish: number?, -- the moment it crossed the line
	Place: number?,
	Shown: number, -- score already in the standings
	Spins: number,
	Dashes: number,
	Bumps: number,
	Gone: boolean,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function color3(color: Color3): { number }
	return { math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5) }
end

local function round(value: number, step: number): number
	return math.floor(value / step + 0.5) * step
end

-- How long after a panel passes the server waits for a hop still on its way (part of the ping).
local function leewayFor(player: any): number
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	local lag = if ok and type(ping) == "number" then ping else 0.1
	return math.clamp(lag + 0.06, 0.06, MAX_LEEWAY)
end

-- Scenery only to look at: nothing solid where nothing is drawn.
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

-- World place of track distance d, `offset` outward, `lift` above the ground, facing the race.
function RockinRaceway:_frame(d: number, offset: number, lift: number?): CFrame
	local x, z, fx, fz = Track.At(d, offset)
	local origin = self.origin
	local position = Vector3.new(origin.X + x, origin.Y + (lift or 0), origin.Z + z)
	return CFrame.lookAt(position, position + Vector3.new(fx, 0, fz))
end

-- A flat painted strip lying on the ground, rotated by `yaw`, its top `top` above the ground and
-- its bottom sunk a little (so it never shares a plane with the track under it).
function RockinRaceway:_strip(
	parent: Instance,
	name: string,
	x: number,
	z: number,
	size: Vector2,
	top: number,
	color: Color3,
	yaw: number?
)
	local origin = self.origin
	-- (each kind sinks to its own depth, so buried bottoms never share a plane either)
	local sink = if name == "Curb" then 0.2 elseif name == "Check" then 0.27 else 0.06
	local height = top + sink
	return Build.Decor({
		Name = name,
		Size = Vector3.new(size.X, height, size.Y),
		CFrame = CFrame.new(origin.X + x, origin.Y + top - height / 2, origin.Z + z) * CFrame.Angles(0, yaw or 0, 0),
		Color = color,
		Parent = parent,
	})
end

-- The fairground: grass, the oval (straights from parts, turns from the turn mesh), lane lines,
-- curbs, the checkered line under the finish arch, the outer fence with bunting, grandstands along
-- the home straight, a carousel and tents in the infield, a Ferris wheel past the back straight,
-- trees round it all and balloons.
function RockinRaceway:_buildArena()
	local ctx = self.context
	local origin = self.origin
	local ground = origin.Y
	local arena = ctx.Arena
	local field = Build.Folder("Fairground", arena)
	local s = Track.STRAIGHT / 2
	local R = Track.RADIUS
	local half = Track.HALF_WIDTH
	local dirt = rgb(214, 160, 104)
	local white = rgb(250, 248, 240)

	-- The ground everyone could stand on: one grass slab under it all, its top just under the track.
	Build.Part({
		Name = "Grass",
		Size = Vector3.new(900, 4, 760),
		CFrame = CFrame.new(origin.X, ground - 0.3 - 2, origin.Z),
		Color = rgb(108, 190, 84),
		Material = Enum.Material.Grass,
		CastShadow = false,
		Parent = field,
	})

	-- Straights: dirt, lane lines, curbs.
	for _, side in { 1, -1 } do
		local z = side * R
		Build.Decor({
			Name = "Straight",
			Size = Vector3.new(Track.STRAIGHT, 0.4, half * 2),
			CFrame = CFrame.new(origin.X, ground - 0.2, origin.Z + z),
			Color = dirt,
			Material = Enum.Material.SmoothPlastic,
			Parent = field,
		})
		for line = 0, Track.LANES do
			local offset = -half + line * Track.LANE
			local edge = line == 0 or line == Track.LANES
			local width = if edge then 0.5 else 0.3
			if side > 0 then
				-- (the home straight's lines stop at the checkered band under the arch)
				local length = s - 1.6 - 0.15
				for _, part in { -1, 1 } do
					self:_strip(
						field,
						"LaneLine",
						part * (1.6 + length / 2),
						R + offset,
						Vector2.new(length, width),
						0.1,
						white
					)
				end
			else
				self:_strip(field, "LaneLine", 0, -(R + offset), Vector2.new(Track.STRAIGHT - 0.3, width), 0.1, white)
			end
		end
		-- Red and white curbs just outside both edges.
		for _, edge in { -1, 1 } do
			local zc = side * (R + edge * (half + 0.9))
			local count = math.floor(Track.STRAIGHT / 5)
			for k = 0, count - 1 do
				local x = -s + (k + 0.5) * 5
				self:_strip(
					field,
					"Curb",
					x,
					zc,
					Vector2.new(4.9, 1.8),
					0.18,
					if k % 2 == 0 then rgb(235, 60, 60) else white
				)
			end
		end
	end
	-- Turns: the half-ring mesh (dirt, lane lines, curbs), its pivot in the middle of its outer half.
	for _, side in { 1, -1 } do
		local center = Vector3.new(origin.X + side * s, ground - 0.4, origin.Z)
		local outward = Vector3.new(side, 0, 0)
		local pivot = center + outward * ((R + half + 1.8) / 2)
		MeshLibrary.Get("RockinRacewayTurn", {
			CFrame = CFrame.fromMatrix(pivot, outward, Vector3.yAxis), -- its +X points outward
			Parent = field,
		})
	end

	-- The start / finish line: a checkered band across the home straight at d = 0.
	local squares = Build.Folder("FinishLine", field)
	local rows = 36
	local cell = (half * 2 - 0.2) / rows -- (inset a little from the track's edges)
	for row = 0, rows - 1 do
		for column = 0, 1 do
			local z = R - half + 0.1 + (row + 0.5) * cell
			local dark = (row + column) % 2 == 0
			self:_strip(
				squares,
				"Check",
				(column - 0.5) * cell,
				z,
				Vector2.new(cell, cell),
				0.22,
				if dark then rgb(35, 35, 45) else white
			)
		end
	end
	-- The finish arch over it (its span runs across the track: the mesh's X along world Z).
	local archAt = Vector3.new(origin.X, ground, origin.Z + R)
	local arch = MeshLibrary.Get("RockinRacewayArch", {
		CFrame = CFrame.lookAt(archAt, archAt + Vector3.new(1, 0, 0)), -- front (-Z) toward riders coming home
		Parent = field,
	})
	local banner = Build.Decor({
		Name = "ArchBanner",
		Size = Vector3.new(0.3, 4.4, 38),
		CFrame = CFrame.new(archAt + Vector3.new(0, 16.6, 0)),
		Color = rgb(255, 250, 235),
		Parent = arch,
	})
	local function bannerText(face: Enum.NormalId, text: string)
		Build.SurfaceText(banner, face, text, {
			TextColor3 = rgb(225, 50, 70),
			TextStrokeColor3 = rgb(255, 255, 255),
			TextStrokeTransparency = 0.2,
			PixelsPerStud = 14,
			MaxDistance = 600,
		}).Font =
			Enum.Font.FredokaOne
	end
	bannerText(Enum.NormalId.Right, "🏁 FINISH 🏁") -- +X: seen by riders coming home
	bannerText(Enum.NormalId.Left, "🥕 GALLOP! 🥕") -- -X: seen from the start

	-- Lane numbers painted just behind the start line, ringed in the lane's horse colour.
	for lane = 1, Track.LANES do
		local offset = Track.LaneOffset(lane)
		local tile = self:_strip(field, "LaneTile", 6, R + offset, Vector2.new(3.4, 3.4), 0.14, white)
		Build.SurfaceText(tile, Enum.NormalId.Top, tostring(lane), {
			TextColor3 = rgb(40, 50, 80),
			TextStrokeColor3 = COLORS[lane],
			TextStrokeTransparency = 0,
			PixelsPerStud = 16,
			LightInfluence = 1,
			Brightness = 1,
		}).Font =
			Enum.Font.FredokaOne
		-- (the tile's top faces up; turn the text to read from behind the start, facing the race)
		tile.CFrame *= CFrame.Angles(0, math.pi / 2, 0)
	end

	-- Panels: every row in all twelve lanes.
	local panels = Build.Folder("Panels", arena)
	for _, panel in self.panels do
		for lane = 1, Track.LANES do
			MeshLibrary.Get(if panel.K == "H" then "RockinRacewayHurdle" else "RockinRacewayCarrot", {
				CFrame = self:_frame(panel.D, Track.LaneOffset(lane), -0.05),
				Parent = panels,
			})
		end
	end

	-- The outer fence, all the way round, with bunting along the straights.
	local fence = Build.Folder("Fence", field)
	local fenceOffset = half + 4
	local FENCE = 10 -- the fence mesh's length
	local gap = 6 -- left open either side of the arch (its feet stand there)
	local count = math.floor((Track.LENGTH - gap * 2) / FENCE + 0.5)
	local step = (Track.LENGTH - gap * 2) / count
	for k = 0, count - 1 do
		local a = self:_frame(gap + k * step, fenceOffset).Position
		local b = self:_frame(gap + (k + 1) * step, fenceOffset).Position
		MeshLibrary.Get("RockinRacewayFence", {
			CFrame = CFrame.fromMatrix((a + b) / 2, (b - a).Unit, Vector3.yAxis), -- its rails (X) along the track
			Scale = (b - a).Magnitude / FENCE,
			Parent = fence,
		})
	end
	for _, side in { 1, -1 } do
		for k = 0, 8 do
			local x = -s + 12 + k * 22
			if math.abs(x) < 14 then
				continue -- the arch stands there
			end
			local at = Vector3.new(origin.X + x, ground, origin.Z + side * (R + fenceOffset + 2.5))
			MeshLibrary.Get("RockinRacewayBunting", {
				CFrame = CFrame.new(at) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0),
				Parent = fence,
			})
		end
	end

	-- Grandstands full of fans along the home straight, facing the track.
	for _, x in { -62, 62 } do
		local at = Vector3.new(origin.X + x, ground, origin.Z + R + half + 20)
		MeshLibrary.Get("RockinRacewayStand", {
			CFrame = CFrame.lookAt(at, at - Vector3.zAxis),
			Parent = field,
		})
	end

	-- The infield: a carousel in the middle, striped tents, balloons.
	local infield = Build.Folder("Infield", field)
	MeshLibrary.Get("RockinRacewayCarousel", {
		CFrame = CFrame.new(origin.X, ground, origin.Z),
		Parent = infield,
	}).Name =
		"Carousel"
	local tentColors = { rgb(235, 60, 70), rgb(70, 140, 235), rgb(250, 190, 40), rgb(120, 200, 90) }
	for index, spot in { { -62, -6 }, { 60, 8 }, { -34, 14 }, { 36, -14 }, { -88, 10 }, { 88, -10 } } do
		MeshLibrary.Get("RockinRacewayTent", {
			Colors = { Stripes = tentColors[(index - 1) % #tentColors + 1] },
			CFrame = CFrame.new(origin.X + spot[1], ground, origin.Z + spot[2])
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = infield,
		})
	end
	local balloonColors =
		{ rgb(255, 90, 140), rgb(255, 205, 50), rgb(80, 170, 255), rgb(120, 220, 110), rgb(190, 120, 255) }
	for _, spot in { { -20, -6 }, { 18, 6 }, { -76, -2 }, { 76, 2 } } do
		for k = 1, 3 do
			local angle = k * 2.1 + rng:NextNumber(-0.3, 0.3)
			decor(MeshLibrary.Get("Balloon", {
				Scale = rng:NextNumber(0.6, 0.8),
				Colors = { Balloon = balloonColors[rng:NextInteger(1, #balloonColors)] },
				CFrame = CFrame.new(origin.X + spot[1], ground, origin.Z + spot[2])
					* CFrame.Angles(0, angle, 0)
					* CFrame.Angles(math.rad(10), 0, 0),
				Parent = infield,
			}))
		end
	end

	-- A Ferris wheel past the back straight, and trees all round beyond the fence.
	MeshLibrary.Get("RockinRacewayWheel", {
		CFrame = CFrame.new(origin.X + 20, ground, origin.Z - R - half - 48),
		Parent = field,
	})
	local leafColors = { rgb(80, 190, 90), rgb(110, 200, 80), rgb(70, 165, 95), rgb(140, 205, 85) }
	for k = 0, 33 do
		local angle = k / 34 * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
		local reach = rng:NextNumber(1.0, 1.15)
		local x = math.cos(angle) * (s + R + half + 40) * reach
		local z = math.sin(angle) * (R + half + 56) * reach
		if z > R + half + 6 and math.abs(x) < 95 then
			continue -- the grandstands are there
		end
		if z < -(R + half) and math.abs(x - 20) < 46 then
			continue -- the Ferris wheel
		end
		decor(MeshLibrary.Get("Tree", {
			Scale = rng:NextNumber(1.7, 2.6),
			Colors = { Leaves = leafColors[rng:NextInteger(1, #leafColors)] },
			CFrame = CFrame.new(origin.X + x, ground - 0.3, origin.Z + z)
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = field,
		}))
	end
end

function RockinRaceway:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn" -- nothing knocks anyone out
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 40
	self.origin = ctx.Origin.Position
	self.panels = Track.Panels(rng)
	self.riders = {} :: { [any]: Rider }
	self.finished = 0
	self.racing = false
	self.closeAt = nil :: number?

	local players = table.clone(ctx:GetPlayers())
	for index = #players, 2, -1 do -- lanes in a random order
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local lanes = {}
	for index, player in players do
		local lane = Track.LaneFor(index, #players)
		local rider: Rider = {
			Player = player,
			Lane = lane,
			Offset = Track.LaneOffset(lane),
			D = 0,
			V = 0,
			C = Track.CARROTS,
			Gallop = false,
			Build = 0,
			Rest = 10,
			SpinUntil = 0,
			DashUntil = 0,
			SlowUntil = 0,
			HopAt = -math.huge,
			Next = 1,
			Pending = {},
			Shown = 0,
			Spins = 0,
			Dashes = 0,
			Bumps = 0,
			Gone = false,
		}
		self.riders[player] = rider
		table.insert(lanes, {
			U = player.UserId,
			L = lane,
			C = color3(COLORS[lane]),
			N = player.DisplayName,
		})
		ctx:SetScoreText(player, "0%")
	end
	self:_buildArena()
	ctx:ShareTemplate("RockinRacewayHorse", MeshLibrary.Get("RockinRacewayHorse"))
	ctx:SetSharedJSON("Layout", {
		O = { self.origin.X, self.origin.Y, self.origin.Z },
		Riders = lanes,
		Panels = self.panels,
	})
	ctx:SetShared("Stage", "Ready")
	self:_share()

	ctx.Hooks.CharacterReady = function(player)
		if BotRegistry.IsBot(player) then
			self:_placeBot(player, ctx:Now())
		end
		if self.racing then
			ctx:SetWalkSpeed(player, 0)
		end
	end
	ctx.Hooks.Respawn = function(player)
		local rider = self.riders[player]
		return if rider then self:_frame(rider.D, rider.Offset) else nil
	end
	ctx.Hooks.PlayerLeft = function(player)
		self:_leave(player)
	end
	-- SpawnAll hands out points in ctx:GetPlayers() order, not the shuffled lane order.
	local points = {}
	for _, player in ctx:GetPlayers() do
		local rider = self.riders[player]
		table.insert(points, self:_frame(0, if rider then rider.Offset else 0))
	end
	ctx:SpawnAll(points, true)
	for _, player in players do
		if BotRegistry.IsBot(player) then
			self:_placeBot(player, ctx:Now())
		end
	end
	ctx:SetStatus("Hold GALLOP, but watch your carrots!")
end

-- Bots ride where the server has them (players' own clients seat themselves on their horses).
function RockinRaceway:_placeBot(player: any, now: number)
	local rider = self.riders[player]
	local character, humanoid, root = self.context:GetCharacter(player)
	if not rider or not character or not humanoid or not root then
		return
	end
	if not root.Anchored then
		root.Anchored = true
	end
	if not humanoid.PlatformStand then
		humanoid.PlatformStand = true
	end
	local lift = ROOT_Y + Track.HopHeight(now - rider.HopAt)
	local frame = self:_frame(rider.D, rider.Offset, lift)
	if now < rider.SpinUntil then
		frame *= CFrame.Angles(0, (rider.SpinUntil - now) / Track.SPIN_TIME * math.pi * 4, 0)
	end
	root.CFrame = frame
end

function RockinRaceway:_leave(player: any)
	local rider = self.riders[player]
	if rider and not rider.Gone then
		rider.Gone = true
		self:_share()
		self:_checkDone()
	end
end

function RockinRaceway:Start()
	local ctx = self.context
	self.startAt = ctx:Now()
	self.racing = true
	for player, rider in self.riders do
		if not ctx:State(player) then
			rider.Gone = true -- left (or never got a character) before GO
		end
	end
	for _, player in ctx:GetPlayers() do
		ctx:SetWalkSpeed(player, 0)
	end
	ctx:SetShared("Stage", "Race")
	ctx:SetStatus("🥕 Hold GALLOP · HOP the blue hurdles!")

	ctx:OnAction("Gallop", function(player, on)
		local rider = self.riders[player]
		if self.ending then
			return -- the race is over
		end
		if rider and not rider.Gone and not rider.Finish and type(on) == "boolean" then
			rider.Gallop = on
		end
	end, { Interval = 0 })
	ctx:OnAction("Hop", function(player, pressedAt)
		self:_hop(player, pressedAt)
	end, { Interval = 0.1 })

	local lastShare = 0
	local lastScore = 0
	local lastBots = 0
	ctx:Heartbeat(function(dt)
		if self.ending then
			return -- the race is over: everyone stays where they were when it closed
		end
		local now = ctx:Now()
		dt = math.min(dt, 0.1)
		local home = {}
		for player, rider in self.riders do
			if rider.Gone then
				continue
			end
			if not rider.Finish and self:_ride(player, rider, dt, now) then
				table.insert(home, player)
			end
			self:_judge(rider, now)
		end
		-- Riders home in the same step take their places in the order they crossed the line.
		table.sort(home, function(a, b)
			return (self.riders[a].Finish :: number) < (self.riders[b].Finish :: number)
		end)
		for _, player in home do
			self:_home(player, self.riders[player], now)
		end
		if #home > 0 then
			self:_score()
			self:_checkDone()
		end
		if now - lastBots >= 1 / 20 then
			lastBots = now
			for player, rider in self.riders do
				if not rider.Gone and BotRegistry.IsBot(player) then
					self:_placeBot(player, now)
				end
			end
		end
		if now - lastShare >= 0.1 then
			lastShare = now
			self:_share()
		end
		if now - lastScore >= 0.5 then
			lastScore = now
			self:_score()
		end
		if self.closeAt and now >= self.closeAt and not self.ending then
			self:_end("Time")
		end
	end)
end

-- A HOP pressed at `pressedAt` on the player's screen (never later than now, never earlier than
-- the player's ping allows).
function RockinRaceway:_hop(player: any, pressedAt: any)
	local rider = self.riders[player]
	if not rider or rider.Gone or rider.Finish or not self.racing or self.ending then
		return
	end
	local now = self.context:Now()
	local at = if type(pressedAt) == "number" and pressedAt == pressedAt then pressedAt else now
	at = math.clamp(at, now - leewayFor(player), now)
	if at < self.startAt then
		return
	end
	if at < rider.HopAt + Track.HOP_TIME + Track.HOP_REST - 0.05 then
		return -- still in the air (or just landed)
	end
	if at < rider.SpinUntil then
		return
	end
	rider.HopAt = at
end

-- One step of a rider's race; true when it crossed the line in this step.
function RockinRaceway:_ride(player: any, rider: Rider, dt: number, now: number): boolean
	local ctx = self.context
	local before = rider.D
	if Track.Ride(rider, dt, now) then
		rider.Spins += 1
		ctx:Fire(nil, "Spin", player.UserId)
	end
	-- Panels passed this step wait to be judged until the rider's hop has had time to arrive.
	local panel = self.panels[rider.Next]
	while panel and panel.D <= rider.D do
		local fraction = if rider.D > before then (panel.D - before) / (rider.D - before) else 1
		local at = now - dt * (1 - math.clamp(fraction, 0, 1))
		table.insert(rider.Pending, {
			Panel = panel,
			At = at,
			V = rider.V,
			JudgeAt = at + leewayFor(player) + Track.TAIL / math.max(rider.V, 1),
		})
		rider.Next += 1
		panel = self.panels[rider.Next]
	end
	if rider.D >= Track.LENGTH then
		local over = (rider.D - Track.LENGTH) / math.max(rider.V, 1)
		rider.D = Track.LENGTH
		rider.Finish = now - math.min(over, dt)
		rider.Gallop = false
		return true
	end
	return false
end

-- A rider over the line: its place, the cheer, the finish clock for everyone else.
function RockinRaceway:_home(player: any, rider: Rider, now: number)
	local ctx = self.context
	self.finished += 1
	rider.Place = self.finished
	local time = (rider.Finish :: number) - self.startAt
	ctx:SetScoreText(player, `{Track.Ordinal(self.finished)} · {string.format("%.1f", time)}s`)
	ctx:Fire(nil, "Finish", player.UserId, self.finished, time)
	if self.finished == 1 then
		ctx:Announce(`🏁 {player.DisplayName} wins the race!`, "success", 3)
		ctx:Sound("Victory")
		self.closeAt = now + FINISH_CLOCK
		ctx:SetShared("CloseAt", self.closeAt)
	end
end

function RockinRaceway:_judge(rider: Rider, now: number)
	local pending = rider.Pending
	while pending[1] and pending[1].JudgeAt <= now do
		local item = table.remove(pending, 1) :: any
		local high = Track.HopHeight(item.At - rider.HopAt) >= Track.CLEAR
		local result
		if item.Panel.K == "H" then
			if Track.Clears(rider.HopAt, item.At, item.V) then
				result = "clear"
			else
				result = "bump"
				rider.Bumps += 1
				rider.SlowUntil = math.max(rider.SlowUntil, now + Track.SLOW_TIME)
				rider.DashUntil = 0
			end
		elseif high then
			result = "miss"
		else
			result = "dash"
			rider.Dashes += 1
			if now >= rider.SpinUntil and not rider.Finish then
				rider.DashUntil = now + Track.DASH_TIME
				rider.SlowUntil = 0
			end
			rider.C = math.min(Track.CARROTS, rider.C + Track.DASH_CARROTS)
		end
		self.context:Fire(nil, "Panel", rider.Player.UserId, item.Panel.D, result)
	end
end

-- Everyone's race for the clients (10 times a second).
function RockinRaceway:_share()
	local ctx = self.context
	local now = ctx:Now()
	local list = {}
	for player, rider in self.riders do
		if rider.Gone then
			continue
		end
		list[tostring(player.UserId)] = {
			D = round(rider.D, 0.01),
			V = round(rider.V, 0.01),
			C = round(rider.C, 0.1),
			G = if rider.Gallop then 1 else nil,
			B = round(rider.Build, 0.001),
			Rs = round(math.min(rider.Rest, 5), 0.001),
			H = if now - rider.HopAt < 2 then round(rider.HopAt, 0.001) else nil,
			S = if rider.SpinUntil > now then round(rider.SpinUntil, 0.001) else nil,
			Da = if rider.DashUntil > now then round(rider.DashUntil, 0.001) else nil,
			Sl = if rider.SlowUntil > now then round(rider.SlowUntil, 0.001) else nil,
			F = if rider.Finish then round(rider.Finish - (self.startAt or 0), 0.01) else nil,
			E = if rider.Finish then round(rider.Finish, 0.001) else nil, -- (the moment, for the coast past the line)
			P = rider.Place,
		}
	end
	ctx:SetSharedJSON("Riders", { T = now, R = list })
end

-- The standings: finishers by place, the rest by how far round they are.
function RockinRaceway:_score()
	local ctx = self.context
	local leader, best = nil, -1
	for player, rider in self.riders do
		if rider.Gone or not ctx:State(player) then
			continue
		end
		local percent = math.floor(math.clamp(rider.D / Track.LENGTH, 0, 1) * 100)
		local score = if rider.Place then 200 - rider.Place else percent
		if score ~= rider.Shown then
			ctx:AddScore(player, score - rider.Shown)
			rider.Shown = score
			if not rider.Place then
				ctx:SetScoreText(player, `{percent}%`)
			end
		end
		if score > best then
			leader, best = player, score
		end
	end
	if self.closeAt then
		local left = math.max(0, math.ceil(self.closeAt - ctx:Now()))
		ctx:SetStatus(`🏁 Finish closes in {left}s!`)
	elseif leader and self.racing and ctx:Now() - self.startAt > 6 then
		ctx:SetStatus(`🥕 {leader.DisplayName} leads!`)
	end
end

function RockinRaceway:_checkDone()
	if not self.racing or self.ending then
		return
	end
	for player, rider in self.riders do
		if not rider.Gone and not rider.Finish and self.context:State(player) then
			return
		end
	end
	self:_end("Finished")
end

function RockinRaceway:_end(reason: string)
	if self.ending then
		return
	end
	self.ending = true
	local ctx = self.context
	for _, rider in self.riders do
		rider.Gallop = false
		if not rider.Finish then
			rider.V = 0
		end
	end
	self:_share()
	ctx:SetShared("Stage", "Done")
	ctx:Delay(if reason == "Finished" then 2.5 else 0.5, function()
		ctx:End(reason)
	end)
end

-- Finish order first, then how far round the oval each rider got.
function RockinRaceway:GetResults()
	local ctx = self.context
	local entries = {}
	local home = {}
	for player in ctx.Participants do
		local rider = self.riders[player]
		if player.Parent and rider and rider.Finish then
			table.insert(home, rider)
		end
	end
	table.sort(home, function(a, b)
		return (a.Finish :: number) < (b.Finish :: number)
	end)
	local places = {}
	for index, rider in home do
		places[rider] = index -- (a finisher who left gives up their place)
	end
	for player in ctx.Participants do
		if not player.Parent then
			continue
		end
		local rider = self.riders[player]
		if not rider then
			continue
		end
		local percent = math.floor(math.clamp(rider.D / Track.LENGTH, 0, 1) * 100)
		local place = places[rider]
		if place then
			table.insert(entries, {
				Player = player,
				Rank = 1e6 - place,
				ScoreText = `{Track.Ordinal(place)} · {string.format(
					"%.1f",
					(rider.Finish or 0) - (self.startAt or 0)
				)}s`,
				BestScore = 100,
			})
		else
			table.insert(entries, {
				Player = player,
				Rank = math.clamp(rider.D, 0, Track.LENGTH),
				ScoreText = `{percent}% of the lap`,
				BestScore = percent,
			})
		end
	end
	return { Entries = entries }
end

return RockinRaceway

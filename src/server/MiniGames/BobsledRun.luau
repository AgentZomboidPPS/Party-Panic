-- Bobsled Run (Team/Race, 50s, 2-12 players). After "Bobsled Run" (Mario Party 1, 2 vs. 2): each team
-- rides its own bobsled down an icy course and the first team to the finish line wins. Here the crew
-- steers by leaning together: every curve, each rider presses LEAN LEFT or LEAN RIGHT in time, and
-- the sled takes the curve clean (a speed boost, like the original's boost pads), scrapes it (a
-- little slower) or slams into the wall (a lot slower).
--
-- The players split into 2-4 sleds (Teams.CountFor, 1-4 riders each) racing side by side in their own
-- lanes down one wide ice channel with banked curves, kickers that throw the sleds into the air and a
-- finish arch. A curve counts the crew's leans from OPEN seconds before it until the sled enters
-- it (plus the riders' ping): score = (right - wrong) / riders, so a short crew's leans count for
-- more and uneven teams are fair. Score >= CLEAN takes it clean, above 0 scrapes, else it's a bump.
-- Ends when every sled is home (or time runs out: finish order first, then distance).
--
-- How it works: the course is a string of fixed track pieces (Shared/Logic/BobsledCourse) that the
-- server and clients both turn into the same path, so the curve "schedule" is just the course: a
-- client shows the next curve's arrow early from its sled's distance. The server races each sled
-- (distance and speed) and judges every curve; it shares the sleds ("Sleds", 10 times a second) and
-- each curve's result ("Curve" events). Clients animate the sleds smoothly along the path from that
-- and seat every rider's character in their sled (their own moves for real; bots' are moved by the
-- server too, so spectating and the round code see everyone where they ride).
--
-- Bots press LEAN through ctx:BotAction with skill-based reaction times (Bots/BobsledRun.luau): the
-- same judging as everyone, so the wall catches a bot crew exactly like a player crew.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local BobsledCourse = require(ReplicatedStorage.Shared.Logic.BobsledCourse)
local Teams = require(ReplicatedStorage.Shared.Teams)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local BobsledRun = MiniGame.Define("BobsledRun", { Results = "Team" })

BobsledRun.Shapes = { Red = "★", Blue = "●", Green = "▲", Yellow = "◆" }

local SEAT_Y = 1.9 -- a seated rider's root above the sled's pivot (runner bottoms)
local PRE_UNITS = 3 -- straights behind the start line (the start house)

local rng = Random.new()

type Rider = { Player: any, Team: string, Lean: number, LeanAt: number, Good: number, Seen: number }
type Sled = {
	Team: string,
	X: number,
	Riders: { any },
	D: number,
	V: number,
	Next: number, -- the next curve to judge
	OpenAt: number?,
	EnterAt: number?,
	JudgeAt: number?,
	Place: number?,
	Time: number?,
	Gone: boolean?,
	Clean: number,
	Bumps: number,
	Shown: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function round(x: number, step: number): number
	return math.floor(x / step + 0.5) * step
end

local function ping(player: any): number
	if BotRegistry.IsBot(player) then
		return 0
	end
	local ok, value = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and type(value) == "number" then math.clamp(value, 0, 0.25) else 0.1
end

-- Arena -------------------------------------------------------------------------------------------

function BobsledRun:_at(d: number, x: number): CFrame
	return self.originCF * BobsledCourse.Frame(self.course, d, x)
end

-- The world frame of a piece of track: its entry point, turned to its heading (upright).
function BobsledRun:_upright(d: number): CFrame
	local point, h = BobsledCourse.Sample(self.course, d)
	return self.originCF * CFrame.new(point) * CFrame.Angles(0, h, 0)
end

function BobsledRun:_buildArena()
	local ctx = self.context
	local arena = ctx.Arena
	local course = self.course
	local originCF = self.originCF

	-- The run: one mesh per piece (plus straights behind the start for the start house).
	for index = PRE_UNITS, 1, -1 do
		local segment = {
			K = "S",
			D0 = -index * BobsledCourse.UNIT,
			Len = BobsledCourse.UNIT,
			P = Vector3.new(0, BobsledCourse.SLOPE * BobsledCourse.UNIT * index, BobsledCourse.UNIT * index),
			H = 0,
		}
		MeshLibrary.Get("BobsledTrack", {
			CFrame = originCF * BobsledCourse.PieceFrame(segment :: any) * CFrame.new(BobsledCourse.Anchor.S),
			Parent = arena,
		})
	end
	for _, segment in course.Segments do
		MeshLibrary.Get(BobsledCourse.PieceProp[segment.K], {
			CFrame = originCF * BobsledCourse.PieceFrame(segment) * CFrame.new(BobsledCourse.Anchor[segment.K]),
			Parent = arena,
		})
	end
	-- The start house's back wall: a snow drift closing the channel behind the start.
	local back = self:_upright(-PRE_UNITS * BobsledCourse.UNIT + 2)
	Build.Part({
		Name = "Drift",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(64, 64, 64),
		CFrame = back * CFrame.new(0, -14, 26),
		Color = rgb(244, 248, 255),
		Material = Enum.Material.Snow,
		CanCollide = false,
		Parent = arena,
	})

	-- The snowy mountainside: strips of snow following the run's height down the hill.
	local samples = {}
	local d = -PRE_UNITS * BobsledCourse.UNIT
	while d <= course.Total do
		local point = BobsledCourse.Sample(course, d)
		table.insert(samples, point)
		d += 6
	end
	self.samples = samples
	local zTop = samples[1].Z + 120
	local zBottom = samples[#samples].Z - 220
	local nodes = {}
	local z = zTop
	while z >= zBottom - 40 do
		local low = math.huge
		local nearest, nearestGap = samples[1], math.huge
		for _, point in samples do
			local gap = math.abs(point.Z - z)
			if gap <= 22 then
				low = math.min(low, point.Y)
			end
			if gap < nearestGap then
				nearest, nearestGap = point, gap
			end
		end
		if low == math.huge then
			low = nearest.Y + (z - nearest.Z) * BobsledCourse.SLOPE * 0.8
		end
		table.insert(nodes, Vector3.new(0, low - 1.5, z))
		z -= 40
	end
	self.groundNodes = nodes
	for index = 1, #nodes - 1 do
		local a, b = nodes[index], nodes[index + 1]
		local run = Vector3.new(0, b.Y - a.Y, b.Z - a.Z)
		local middle = (a + b) / 2
		local look = CFrame.lookAt(middle, middle + run)
		Build.Part({
			Name = "Snowfield",
			Size = Vector3.new(1600 + (index % 2) * 6, 6, run.Magnitude), -- (neighbors' side faces apart)
			CFrame = originCF * look * CFrame.new(0, -3, 0),
			Color = rgb(238, 244, 252),
			Material = Enum.Material.Snow,
			CastShadow = false,
			Parent = arena,
		})
	end

	-- Pines on the slopes (never on the run), thicker further out, and peaks all around.
	local function clear(x: number, zz: number, gap: number): boolean
		for index = 1, #samples, 2 do
			local point = samples[index]
			local dx, dz = point.X - x, point.Z - zz
			if dx * dx + dz * dz < gap * gap then
				return false
			end
		end
		return true
	end
	local planted = 0
	local tries = 0
	while planted < 150 and tries < 900 do
		tries += 1
		local zz = rng:NextNumber(zBottom + 60, zTop - 30)
		local spread = if rng:NextNumber() < 0.6 then rng:NextNumber(50, 160) else rng:NextNumber(160, 420)
		local x = (if rng:NextNumber() < 0.5 then -1 else 1) * spread
		if clear(x, zz, 52) then
			planted += 1
			MeshLibrary.Get("BobsledPine", {
				Scale = rng:NextNumber(0.8, 1.7),
				CFrame = originCF
					* CFrame.new(x, self:_groundAt(zz) - 0.3, zz)
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = arena,
			})
		end
	end
	local middleZ = (zTop + zBottom) / 2
	for _, spot in
		{
			{ -560, middleZ + 300, 3.4 },
			{ -620, middleZ - 150, 4.2 },
			{ 600, middleZ + 200, 3.8 },
			{ 640, middleZ - 300, 3.0 },
			{ -300, zBottom - 420, 4.6 },
			{ 220, zBottom - 520, 5.2 },
			{ -760, zBottom - 160, 3.2 },
			{ 820, zBottom - 120, 3.6 },
		}
	do
		MeshLibrary.Get("BobsledPeak", {
			Scale = spot[3],
			CFrame = originCF
				* CFrame.new(spot[1], self:_groundAt(spot[2]) - 30, spot[2])
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = arena,
		})
	end

	-- The start house and line, flags along the lips, the finish line and arch.
	MeshLibrary.Get("BobsledGate", {
		CFrame = self:_upright(-6) * CFrame.new(0, -8, 0),
		Parent = arena,
	})
	local floorWidth = BobsledCourse.FLOOR_HALF * 2 - 4
	Build.Decor({
		Name = "StartLine",
		Size = Vector3.new(floorWidth, 0.1, 1),
		CFrame = self:_at(0, 0) * CFrame.new(0, 0.06, 0),
		Color = rgb(230, 56, 66),
		Material = Enum.Material.SmoothPlastic,
		Parent = arena,
	})
	local squares = 18
	local tile = floorWidth / squares
	for index = 0, squares * 2 - 1 do
		local column = index % squares
		local row = index // squares
		Build.Decor({
			Name = "Checker",
			Size = Vector3.new(tile, 0.1, 1.6),
			CFrame = self:_at(course.Length + row * 1.6 + 0.8, -floorWidth / 2 + (column + 0.5) * tile)
				* CFrame.new(0, 0.06, 0),
			Color = if (column + row) % 2 == 0 then rgb(28, 28, 34) else rgb(250, 250, 250),
			Material = Enum.Material.SmoothPlastic,
			Parent = arena,
		})
	end
	MeshLibrary.Get("BobsledArch", {
		CFrame = self:_upright(course.Length) * CFrame.new(0, -8, 0),
		Parent = arena,
	})

	-- Flags on the lips of the straights, in the sleds' colors.
	local colors = {}
	for _, team in self.order do
		table.insert(colors, Teams.Colors[team])
	end
	local flagIndex = 0
	for _, segment in course.Segments do
		if segment.K ~= "S" or segment.D0 < 20 or segment.D0 > course.Length - 10 then
			continue
		end
		flagIndex += 1
		if flagIndex % 2 == 0 then
			continue
		end
		for _, side in { -1, 1 } do
			local x = side * (BobsledCourse.FLOOR_HALF + 1.7)
			local frame = self:_upright(segment.D0 + 8)
			MeshLibrary.Get("BobsledFlag", {
				Colors = { Cloth = colors[(flagIndex + (if side > 0 then 1 else 0)) % #colors + 1] },
				CFrame = frame * CFrame.new(x, 5.9, 0) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
				Parent = arena,
			})
		end
	end

	-- Snow drifting down over the course (ambient: off with reduced effects).
	local sky = Build.Decor({
		Name = "SnowSky",
		Size = Vector3.new(400, 1, 400),
		CFrame = originCF * CFrame.new(0, 90, -course.Length / 2),
		Transparency = 1,
		Parent = arena,
	})
	local flakes = Instance.new("ParticleEmitter")
	flakes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	flakes.Color = ColorSequence.new(Color3.new(1, 1, 1))
	flakes.LightEmission = 0.3
	flakes.Size = NumberSequence.new(0.35)
	flakes.Lifetime = NumberRange.new(10, 14)
	flakes.Speed = NumberRange.new(6, 9)
	flakes.EmissionDirection = Enum.NormalId.Bottom
	flakes.SpreadAngle = Vector2.new(20, 20)
	flakes.Rate = 140
	flakes.Parent = sky
	CollectionService:AddTag(flakes, "PP_Ambient")
end

-- The snowfield's height under `z` (course coordinates).
function BobsledRun:_groundAt(z: number): number
	local nodes = self.groundNodes
	for index = 1, #nodes - 1 do
		local a, b = nodes[index], nodes[index + 1]
		if z <= a.Z and z >= b.Z then
			local t = (a.Z - z) / (a.Z - b.Z)
			return a.Y + (b.Y - a.Y) * t
		end
	end
	return if z > nodes[1].Z then nodes[1].Y else nodes[#nodes].Y
end

-- Round ------------------------------------------------------------------------------------------

function BobsledRun:_seat(player: any): CFrame?
	local rider = self.riders[player]
	local sled = rider and self.sleds[rider.Team]
	if not sled then
		return nil
	end
	local index = table.find(sled.Riders, player) or 1
	return self:_at(sled.D, sled.X) * CFrame.new(0, SEAT_Y, BobsledCourse.SeatZ(index, #sled.Riders))
end

-- Bots ride where the server has their sled (players' own clients seat them).
function BobsledRun:_placeBot(player: any)
	local character, humanoid, root = self.context:GetCharacter(player)
	local seat = self:_seat(player)
	if not character or not humanoid or not root or not seat then
		return
	end
	if not root.Anchored then
		root.Anchored = true
	end
	if not humanoid.PlatformStand then
		humanoid.PlatformStand = true
	end
	root.CFrame = seat
end

function BobsledRun:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	self.origin = ctx.Origin.Position
	self.originCF = CFrame.new(self.origin)
	self.course = BobsledCourse.Build(BobsledCourse.Generate(rng))
	ctx.KillY = self.origin.Y - BobsledCourse.SLOPE * self.course.Total * 1.6 - 120

	local players = ctx:GetPlayers()
	local names = {}
	-- (A solo test gets one sled instead of an empty rival.)
	for index = 1, math.min(Teams.CountFor(#players, 3), math.max(#players, 1)) do
		table.insert(names, Teams.Order[index])
	end
	self.order = names
	local teams = ctx:AssignTeams(names)
	self.sleds = {} :: { [string]: Sled }
	self.riders = {} :: { [any]: Rider }
	self.finished = 0
	local shared = {}
	for index, team in names do
		local sled: Sled = {
			Team = team,
			X = BobsledCourse.LaneX(index, #names),
			Riders = teams[team] or {},
			D = 0,
			V = 0,
			Next = 1,
			Clean = 0,
			Bumps = 0,
			Shown = 0,
		}
		self.sleds[team] = sled
		local ids = {}
		for _, player in sled.Riders do
			self.riders[player] = { Player = player, Team = team, Lean = 0, LeanAt = -math.huge, Good = 0, Seen = 0 }
			table.insert(ids, player.UserId)
		end
		table.insert(shared, { T = team, X = sled.X, R = ids })
	end
	ctx:SetSharedJSON("Course", {
		O = { self.origin.X, self.origin.Y, self.origin.Z },
		P = self.course.Pieces,
		Sleds = shared,
	})
	self:_buildArena()
	ctx:ShareTemplate("BobsledSled", MeshLibrary.Get("BobsledSled"))

	ctx.Hooks.CharacterReady = function(player)
		if BotRegistry.IsBot(player) then
			self:_placeBot(player)
		end
	end
	ctx.Hooks.Respawn = function(player)
		return self:_seat(player)
	end
	ctx.Hooks.PlayerLeft = function(player)
		self:_leave(player)
	end
	local points = {}
	for _, player in players do
		table.insert(points, (self:_seat(player) or self:_at(0, 0)) - Vector3.new(0, 3, 0))
	end
	ctx:SpawnAll(points, true)
	for _, player in players do
		if BotRegistry.IsBot(player) then
			self:_placeBot(player)
		end
	end
	self:_share()
	ctx:SetStatus("Lean into the curves together!")
end

function BobsledRun:_leave(player: any)
	local rider = self.riders[player]
	self.riders[player] = nil
	local sled = rider and self.sleds[rider.Team]
	if not sled then
		return
	end
	local index = table.find(sled.Riders, player)
	if index then
		table.remove(sled.Riders, index)
	end
	if #sled.Riders == 0 then
		sled.Gone = true
	end
	-- Everyone's seats shift to fit the smaller crew.
	local shared = {}
	for _, team in self.order do
		local other = self.sleds[team]
		local ids = {}
		for _, member in other.Riders do
			table.insert(ids, member.UserId)
		end
		table.insert(shared, { T = team, X = other.X, R = ids, G = if other.Gone then 1 else nil })
	end
	self.context:SetSharedJSON("Course", {
		O = { self.origin.X, self.origin.Y, self.origin.Z },
		P = self.course.Pieces,
		Sleds = shared,
	})
end

function BobsledRun:Start()
	local ctx = self.context
	self.startAt = ctx:Now()
	for _, player in ctx:GetPlayers() do
		if not self.riders[player] then
			continue
		end
		ctx:SetWalkSpeed(player, 0)
	end

	ctx:OnAction("Lean", function(player, dir)
		local rider = self.riders[player]
		if not rider or (dir ~= -1 and dir ~= 1) then
			return
		end
		rider.Lean = dir
		rider.LeanAt = ctx:Now()
		ctx:Fire(nil, "Lean", player.UserId, dir)
	end, { Interval = 0.08 })

	-- Small steps, so a server hitch doesn't skip a curve's judging.
	ctx:Heartbeat(function(dt)
		local now = ctx:Now()
		local left = math.min(dt, 0.5)
		while left > 1e-4 do
			local h = math.min(left, 0.05)
			left -= h
			self:_tick(h, now - left)
		end
		for player, rider in self.riders do
			if BotRegistry.IsBot(player) and self.sleds[rider.Team] then
				self:_placeBot(player)
			end
		end
	end)
	ctx:Loop(function()
		self:_share()
		return 0.1
	end)
end

-- The crew's leans for a curve: right ones, wrong ones, and the riders counted.
function BobsledRun:_crewScore(sled: Sled, curve: BobsledCourse.Curve): (number, number, number)
	local right, wrong, count = 0, 0, 0
	local from = (sled.OpenAt or 0) - 0.05
	local to = sled.JudgeAt or math.huge
	for _, player in sled.Riders do
		local rider = self.riders[player]
		if not rider then
			continue
		end
		count += 1
		rider.Seen += 1
		if rider.LeanAt >= from and rider.LeanAt <= to then
			if rider.Lean == curve.Dir then
				right += 1
				rider.Good += 1
			else
				wrong += 1
			end
		end
	end
	return right, wrong, count
end

function BobsledRun:_judge(sled: Sled, curve: BobsledCourse.Curve)
	local ctx = self.context
	local right, wrong, count = self:_crewScore(sled, curve)
	local score = if count > 0 then (right - wrong) / count else 0
	local kind, speed = BobsledCourse.Judge(score, sled.V)
	sled.V = speed
	if kind == "Clean" then
		sled.Clean += 1
	elseif kind == "Bump" then
		sled.Bumps += 1
	end
	ctx:Fire(nil, "Curve", sled.Team, curve.Index, kind, right, count)
	sled.Next += 1
	sled.OpenAt, sled.EnterAt, sled.JudgeAt = nil, nil, nil
end

function BobsledRun:_tick(dt: number, now: number)
	local ctx = self.context
	if not ctx:IsRunning() then
		return
	end
	local course = self.course
	local everyoneHome = true
	local crossed = {}
	for _, team in self.order do
		local sled = self.sleds[team]
		if sled.Gone then
			continue
		end
		if sled.Place then
			-- Home: brake to a stop on the runout.
			sled.V = math.max(0, sled.V - (10 + 0.5 * sled.V) * dt)
			sled.D = math.min(sled.D + sled.V * dt, course.Total - 10)
			continue
		end
		everyoneHome = false
		sled.V = BobsledCourse.Accelerate(sled.V, dt)
		sled.D += sled.V * dt
		local curve = course.Curves[sled.Next]
		if curve then
			if not sled.OpenAt and (curve.D0 - sled.D) <= BobsledCourse.OPEN * math.max(sled.V, 1) then
				sled.OpenAt = now
			end
			if sled.D >= curve.D0 and not sled.EnterAt then
				-- In the curve: wait out the crew's ping before judging, so a press made in time on a
				-- laggy phone still counts.
				local leeway = 0.06
				for _, player in sled.Riders do
					leeway = math.max(leeway, 0.06 + ping(player))
				end
				sled.EnterAt = now
				sled.JudgeAt = now + leeway
				sled.OpenAt = sled.OpenAt or now
			end
			if sled.JudgeAt and now >= sled.JudgeAt then
				self:_judge(sled, curve)
			end
		end
		if sled.D >= course.Length then
			table.insert(crossed, {
				Sled = sled,
				At = now - (sled.D - course.Length) / math.max(sled.V, 1),
			})
		end
	end
	table.sort(crossed, function(a, b)
		return a.At < b.At
	end)
	for _, entry in crossed do
		local sled = entry.Sled
		self.finished += 1
		sled.Place = self.finished
		sled.Time = entry.At - (self.startAt or entry.At)
		ctx:Fire(nil, "Finish", sled.Team, sled.Place)
		if sled.Place == 1 then
			ctx:Announce(`{BobsledRun.Shapes[sled.Team] or ""} {string.upper(sled.Team)} WINS THE RUN!`, "success", 3)
			ctx:Sound("Victory")
		end
	end
	if everyoneHome and not self.ending then
		self.ending = true
		ctx:Delay(2.5, function()
			ctx:End("AllFinished")
		end)
	end
end

-- Progress in whole percent (the team scores the HUD shows); 100 once home.
function BobsledRun:_percent(sled: Sled): number
	if sled.Place then
		return 100
	end
	return math.clamp(math.floor(sled.D / self.course.Length * 100), 0, 99)
end

function BobsledRun:_share()
	local ctx = self.context
	local now = ctx:Now()
	local list = {}
	local best, bestD = nil, -1
	local home = 0
	for _, team in self.order do
		local sled = self.sleds[team]
		local leans, at = {}, {}
		for _, player in sled.Riders do
			local rider = self.riders[player]
			if rider and rider.Lean ~= 0 then
				leans[tostring(player.UserId)] = rider.Lean
				at[tostring(player.UserId)] = round(rider.LeanAt, 0.001)
			end
		end
		list[team] = {
			D = round(sled.D, 0.01),
			V = round(sled.V, 0.01),
			T = round(now, 0.001),
			N = sled.Next,
			F = sled.Place,
			Tm = sled.Time and round(sled.Time, 0.01),
			G = if sled.Gone then 1 else nil,
			L = leans,
			LA = at,
		}
		if self.startAt then
			local percent = self:_percent(sled)
			if percent ~= sled.Shown and not sled.Gone then
				ctx:AddTeamScore(team, percent - sled.Shown)
				sled.Shown = percent
			end
		end
		if sled.Place then
			home += 1
		end
		local score = if sled.Place then 1e6 - sled.Place else sled.D
		if not sled.Gone and score > bestD then
			best, bestD = team, score
		end
	end
	ctx:SetSharedJSON("Sleds", list)
	if self.startAt then
		local status = if best
			then `{BobsledRun.Shapes[best] or ""} {string.upper(best)} {if home > 0 then "WON" else "LEADS"}`
			else ""
		if home > 0 and home < #self.order then
			status ..= `  •  🏁 {home} home`
		end
		if status ~= self.status then
			self.status = status
			ctx:SetStatus(status)
		end
	end
end

-- Exact order: home sleds by place, the rest by distance (players who left don't count).
function BobsledRun:_rank(team: string): number
	local sled = self.sleds[team]
	if not sled or sled.Gone then
		return -1
	end
	return if sled.Place then 1e6 - sled.Place else sled.D
end

function BobsledRun:GetResults()
	local results = self.context:TeamResults()
	local best, bestRank, tie = nil, -math.huge, false
	for _, team in self.order do
		local rank = self:_rank(team)
		if rank > bestRank then
			best, bestRank, tie = team, rank, false
		elseif rank == bestRank then
			tie = true
		end
	end
	for _, entry in results.Entries do
		local sled = entry.Team and self.sleds[entry.Team]
		if not sled then
			continue
		end
		entry.Rank = self:_rank(entry.Team)
		local rider = self.riders[entry.Player]
		local leans = if rider then ` • {rider.Good}/{rider.Seen} leans` else ""
		entry.ScoreText = if sled.Place
			then `{entry.Team} {BobsledCourse.Ordinal(sled.Place)} • {string.format("%.1f", sled.Time or 0)}s{leans}`
			else `{entry.Team} {self:_percent(sled)}% of the run{leans}`
		entry.BestScore = if rider then rider.Good else 0
	end
	results.WinningTeam = if tie then nil else best
	return results
end

return BobsledRun

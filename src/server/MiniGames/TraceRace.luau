-- Trace Race (Reaction, 40s, 1-12 players). After "Trace Race" (Mario Party 4): each player rides a
-- giant crayon down their own long, winding guideline; the crayon rolls forward by itself at a
-- steady pace and players only steer it left and right, drawing their own line as they go. The
-- line that stays closest to the guide over the whole course wins.
--
-- Here the guidelines are pencil dashes on a huge sheet of notebook paper clipped to a clipboard on
-- a desk (crayon box, pencil, eraser, sharpener and paper clips round it). Every player gets a lane
-- with the very same course: a straight start, then smooth curves, sharp zigzag turns and waves
-- that tighten towards the finish. Seen from behind your crayon, the guide scrolls at you; steer
-- with the MOVE stick, A / D or the arrow keys.
--
-- How it works: the course is a list of pieces (Shared/Logic/TraceRace: Generate/Build) the server
-- picks and shares ("Layout"); both sides turn it into the same guide. The ride's clock is shared
-- too ("Race": T0, T1), and a crayon's distance down its lane is just (time - T0) * SPEED, so the
-- only thing a player controls is the sideways offset. A player's client moves their crayon and
-- sends its offsets with the time it drew them, in small batches ("Trace"); the server checks each
-- one (in order, inside the ride, on the paper, and no further sideways from the last one than the
-- crayon can steer, with leeway for frame timing), scores the accepted ones with the shared Tracker
-- and relays them to every client ten times a second ("Trails"), which draws everyone's lines.
-- Scoring follows the line as everyone sees it drawn: a straight stroke between two positions,
-- full marks wherever it touches the guide. Positions are judged at the time they were drawn, so
-- ping never costs points; clients resend anything the server hasn't relayed back yet.
--
-- Bots steer through the very same action (TraceRace:BotSamples): they anticipate the turns by a
-- skill-based amount, wobble and now and then slip, so careful players beat most of them. Nothing in
-- this mode can hurt anyone (no hazards), and the server seats bots on their crayons itself (players'
-- own clients seat them), so spectators and the round code see everyone riding.
--
-- Wandering (owner: "On trace race you should be able to leave your own lane. They wont score points
-- but its funny"): a player's crayon may leave its lane and ride anywhere on the paper, over the
-- other lanes, up to a stud and a half from the paper's outer edges (Rules.Bounds). The server takes
-- those positions like any others (in order, inside the ride, no faster sideways than the crayon
-- steers), refuses anything off the paper, and scores every step against the rider's own guide, so a
-- line drawn in someone else's lane scores 0. Its crayon, rider and line follow it there on every
-- screen. Bots keep to their own lanes.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.TraceRace)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local Shapes = require(script.Parent.Parent.World.Shapes)

local TraceRace = MiniGame.Define("TraceRace", { Results = "Score" })

local PAPER_Y = 1.9 -- the paper's top above the arena origin
local TIP = 6.37 -- the crayon prop's pivot is this far behind its tip (tools/meshgen/props/TraceRace.py)
local SEAT = CFrame.new(0, 5.44 + 3, 10.2) -- a rider's root from the crayon's tip (feet on its back end)
local LATE = 0.3 -- positions may still arrive this long (plus ping, up to 0.25 s) after the ride
local FINAL_AT = 0.7 -- the scores are final this long after the ride ends
local END_AT = 3.2 -- the round ends this long after the ride (everyone sees their line)
local RUN_IN = 34 -- paper before the start line
local RUN_OUT = 34 -- paper after the finish line
-- How far the markings stand above the paper. Rules and lane lines are centred on the paper's top
-- (their bottoms as far down inside the sheet); the guide and the start/finish float in thin bands
-- above them. Nothing that overlaps on the paper shares a height (no flicker); the clients' crayon
-- lines float higher still (0.5 and up).
local LAYER = { Rule = 0.1, Lane = 0.2 }
local GUIDE_Y = 0.2 -- the guide's middle (0.15 to 0.25)
local FINISH_Y = 0.35 -- the start line's and the finish squares' middle (0.3 to 0.4)
local BAND = 0.1

local rng = Random.new()

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

type Track = Rules.Tracker & {
	LastT: number,
	LastX: number,
}

type Lane = {
	Index: number,
	Color: number,
	Frame: CFrame, -- the start line's middle on the paper, facing down the lane (-Z)
	Lo: number, -- the crayon's x can go from Lo to Hi: anywhere on the paper (Rules.Bounds)
	Hi: number,
	Crayon: Model?,
}

function TraceRace:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 40
	local origin = ctx.Origin.Position
	self.course = Rules.Build(Rules.Generate(rng))
	self.lanes = {} :: { [any]: Lane }
	self.tracks = {} :: { [any]: Track }
	self.pending = {} :: { [any]: { number } }
	self.botPlans = {} :: { [any]: any }
	self.final = {} :: { [any]: number }
	self.race = nil :: any

	local players = ctx:GetPlayers()
	local count = math.max(#players, 1)
	local length = self.course.Length
	self.zStart = origin.Z + length / 2
	self.paperY = origin.Y + PAPER_Y
	-- Colours in a shuffled order, so the same colours aren't always first.
	local colors = {}
	for index = 1, #Rules.Colors do
		table.insert(colors, index)
	end
	for index = #colors, 2, -1 do
		local other = rng:NextInteger(1, index)
		colors[index], colors[other] = colors[other], colors[index]
	end
	local shared = {}
	for index, player in players do
		local x = origin.X + (index - (count + 1) / 2) * Rules.LANE
		local lo, hi = Rules.Bounds(index, count)
		local lane: Lane = {
			Index = index,
			Color = colors[(index - 1) % #colors + 1],
			Frame = CFrame.new(x, self.paperY, self.zStart),
			Lo = lo,
			Hi = hi,
		}
		self.lanes[player] = lane
		table.insert(shared, { U = player.UserId, I = index, C = lane.Color })
		ctx:SetScoreText(player, "0%")
	end
	self:_buildArena(origin, count, players)
	ctx:SetSharedJSON("Layout", {
		Pieces = self.course.Pieces,
		Lanes = shared,
		Count = count,
		X = origin.X,
		Y = self.paperY,
		Z = self.zStart,
	})

	ctx.Hooks.CharacterReady = function(player)
		if BotRegistry.IsBot(player) then
			self:_placeBot(player)
		end
	end
	ctx.Hooks.Respawn = function(player)
		return self:_seat(player)
	end
	ctx.Hooks.PlayerLeft = function(player)
		self.tracks[player] = nil
		self.pending[player] = nil
		local lane = self.lanes[player]
		if lane and lane.Crayon then
			lane.Crayon:Destroy()
			lane.Crayon = nil
		end
		ctx:Fire(nil, "Left", player.UserId)
	end

	local spawns = {}
	for _, player in players do
		table.insert(spawns, (self:_seat(player) or CFrame.new(origin)) - Vector3.new(0, 3, 0))
	end
	ctx:SpawnAll(spawns, true)
	for _, player in players do
		if BotRegistry.IsBot(player) then
			self:_placeBot(player)
		end
	end
	ctx:SetStatus("Steer your crayon along the dotted line!")
end

-- Where a lane's crayon tip is at distance s, x studs right of the middle.
function TraceRace:_tip(lane: Lane, s: number, x: number): CFrame
	return lane.Frame * CFrame.new(x, 0, -s)
end

-- Where the crayon is now (from the ride's clock and the last position the server took).
function TraceRace:_where(player: any): (number, number)
	local race = self.race
	local s = 0
	if race then
		s = math.clamp((self.context:Now() - race.T0) * Rules.SPEED, 0, self.course.Length)
	end
	local track = self.tracks[player]
	return s, if track then track.LastX else 0
end

function TraceRace:_seat(player: any): CFrame?
	local lane = self.lanes[player]
	if not lane then
		return nil
	end
	local s, x = self:_where(player)
	return self:_tip(lane, s, x) * SEAT
end

-- Bots ride where the server has their crayon (players' own clients seat them).
function TraceRace:_placeBot(player: any)
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

-- Arena ---------------------------------------------------------------------------------------------

-- A huge clipboard on a wooden desk: notebook paper with a lane per player, each with the same
-- dotted guideline, a start box with the rider's name and a chequered finish.
function TraceRace:_buildArena(origin: Vector3, count: number, players: { any })
	local ctx = self.context
	local arena = ctx.Arena
	local length = self.course.Length
	local width = count * Rules.LANE
	local zStart, zFinish = self.zStart, self.zStart - length
	local paperY = self.paperY
	local paperW, paperL = width + 2 * Rules.MARGIN, length + RUN_IN + RUN_OUT -- (crayons ride all of it)
	local paperMid = (zStart + RUN_IN + zFinish - RUN_OUT) / 2
	local boardW = paperW + 22
	local boardFar = zFinish - RUN_OUT - 30 -- room for the clip
	local boardNear = zStart + RUN_IN + 12
	local boardMid = (boardFar + boardNear) / 2

	-- The desk (solid and visible: nothing invisible anywhere).
	Build.Part({
		Name = "Desk",
		Size = Vector3.new(1400, 6, 1400),
		CFrame = CFrame.new(origin.X, origin.Y - 3, paperMid),
		Color = rgb(196, 140, 92),
		Material = Enum.Material.WoodPlanks,
		Parent = arena,
	})
	Shapes.Slab(Vector3.new(boardW, 1.5, boardNear - boardFar), 6, {
		Name = "Clipboard",
		CFrame = CFrame.new(origin.X, origin.Y + 0.65, boardMid),
		Color = rgb(150, 100, 62),
		Material = Enum.Material.Wood,
		Parent = arena,
	})
	Build.Part({
		Name = "Paper",
		Size = Vector3.new(paperW, 1.2, paperL),
		CFrame = CFrame.new(origin.X, paperY - 0.6, paperMid),
		Color = rgb(252, 251, 246),
		Material = Enum.Material.SmoothPlastic,
		Parent = arena,
	})
	-- Notebook rules across the sheet, a red margin and pale lines between the lanes.
	for z = zStart + RUN_IN - 8, zFinish - RUN_OUT + 4, -15 do
		Build.Decor({
			Name = "Rule",
			Size = Vector3.new(paperW - 1, LAYER.Rule * 2, 0.25),
			CFrame = CFrame.new(origin.X, paperY, z),
			Color = rgb(170, 205, 240),
			Parent = arena,
		})
	end
	for side = -1, 1, 2 do
		Build.Decor({
			Name = "Margin",
			Size = Vector3.new(0.3, LAYER.Lane * 2, paperL - 1),
			CFrame = CFrame.new(origin.X + side * (width / 2 + Rules.MARGIN / 2), paperY, paperMid),
			Color = rgb(240, 120, 130),
			Parent = arena,
		})
	end
	for index = 1, count - 1 do
		Build.Decor({
			Name = "LaneLine",
			Size = Vector3.new(0.2, LAYER.Lane * 2, paperL - 1),
			CFrame = CFrame.new(origin.X + (index - count / 2) * Rules.LANE, paperY, paperMid),
			Color = rgb(200, 205, 220),
			Parent = arena,
		})
	end

	-- Each lane: the guide (pencil dashes), a start box with the rider's name, the crayon.
	for _, player in players do
		local lane = self.lanes[player]
		local info = Rules.Colors[lane.Color]
		self:_drawGuide(lane)
		local box = Build.Decor({
			Name = "StartBox",
			Size = Vector3.new(Rules.LANE - 3, LAYER.Lane * 2, 9),
			CFrame = lane.Frame * CFrame.new(0, 0, 13),
			Color = info.Color,
			Transparency = 0.55,
			Parent = arena,
		})
		Build.SurfaceText(box, Enum.NormalId.Top, `{lane.Index}  {player.DisplayName}`, {
			TextColor3 = rgb(40, 40, 50),
		})
		local crayon = MeshLibrary.Get("TraceRaceCrayon", {
			Colors = { Wax = info.Color, Wrapper = info.Color:Lerp(Color3.new(1, 1, 1), 0.3) },
			Parent = arena,
		})
		crayon:SetAttribute("TraceRaceUser", player.UserId)
		local toPivot = self:_tipToPivot(crayon)
		crayon:SetAttribute("TipToPivot", toPivot)
		crayon:PivotTo(self:_tip(lane, 0, 0) * CFrame.new(toPivot))
		CollectionService:AddTag(crayon, "TraceRaceCrayon")
		lane.Crayon = crayon
	end

	-- Start line, START and the chequered finish across every lane.
	Build.Decor({
		Name = "StartLine",
		Size = Vector3.new(width, BAND, 0.5),
		CFrame = CFrame.new(origin.X, paperY + FINISH_Y, zStart + 0.5),
		Color = rgb(60, 60, 70),
		Parent = arena,
	})
	local squares = math.max(2, math.floor(width / 3))
	local square = width / squares
	for row = 0, 1 do
		for column = 0, squares - 1 do
			Build.Decor({
				Name = "Finish",
				Size = Vector3.new(square, BAND, square),
				CFrame = CFrame.new(
					origin.X - width / 2 + (column + 0.5) * square,
					paperY + FINISH_Y,
					zFinish - (row + 0.5) * square
				),
				Color = if (row + column) % 2 == 0 then rgb(35, 35, 45) else rgb(255, 255, 255),
				Parent = arena,
			})
		end
	end
	local finishText = Build.Decor({
		Name = "FinishText",
		Size = Vector3.new(math.min(width, 60), LAYER.Lane * 2, 12),
		CFrame = CFrame.new(origin.X, paperY, zFinish - 2 * square - 9),
		Transparency = 1,
		Parent = arena,
	})
	Build.SurfaceText(finishText, Enum.NormalId.Top, "FINISH", {
		TextColor3 = rgb(230, 60, 70),
	})

	-- The clip holding the paper at the far end.
	local clipScale = math.max(1.6, boardW * 0.42 / 22)
	MeshLibrary.Get("TraceRaceClip", {
		Scale = clipScale,
		CFrame = CFrame.new(origin.X, origin.Y + 1.4, zFinish - RUN_OUT + 2) * CFrame.Angles(0, math.pi, 0),
		Parent = arena,
	})

	-- Desk clutter round the clipboard (well clear of it; none of it collides).
	local half = boardW / 2
	local function put(name: string, scale: number, x: number, z: number, yaw: number, colors: any?)
		MeshLibrary.Get(name, {
			Scale = scale,
			Colors = colors,
			CFrame = CFrame.new(origin.X + x, origin.Y, z) * CFrame.Angles(0, math.rad(yaw), 0),
			Parent = arena,
		})
	end
	put("TraceRaceCrayonBox", 3, -(half + 38), zStart - 40, 18)
	put("TraceRacePencil", 4, half + 34, paperMid + 30, 8)
	put("TraceRaceEraser", 3, -(half + 32), zFinish + 60, -25)
	put("TraceRaceSharpener", 3, half + 30, zFinish + 20, 30)
	put("TraceRacePaperClip", 3.5, -(half + 26), paperMid + 10, 70)
	put("TraceRacePaperClip", 3.5, half + 22, zStart + 20, -40)
	local loose = { 2, 5, 8, 11 }
	for index, colorIndex in loose do
		local color = Rules.Colors[colorIndex].Color
		local side = if index % 2 == 0 then 1 else -1
		put(
			"TraceRaceCrayon",
			4,
			side * (half + 22 + index * 5),
			zStart - 110 - index * 75,
			side * 12 + index * 9,
			{ Wax = color, Wrapper = color:Lerp(Color3.new(1, 1, 1), 0.3) }
		)
	end
	-- A loose sheet of drawing paper under some of it, and a few on the far side.
	for _, spot in { { -1, 0.35, 12 }, { 1, 0.75, -9 } } do
		Build.Part({
			Name = "LooseSheet",
			Size = Vector3.new(90, 0.6, 120),
			CFrame = CFrame.new(origin.X + spot[1] * (half + 70), origin.Y + 0.2, zStart - length * spot[2])
				* CFrame.Angles(0, math.rad(spot[3]), 0),
			Color = rgb(250, 248, 240),
			Parent = arena,
		})
	end
end

-- Where a crayon's pivot is from its tip (the lowest point, at the front): measured, so the mesh and
-- its primitive stand-in both draw from the tip.
function TraceRace:_tipToPivot(crayon: Model): Vector3
	crayon:PivotTo(CFrame.new())
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in crayon:GetDescendants() do
		if part:IsA("BasePart") then
			for _, corner in { -1, 1 } do
				for _, cy in { -1, 1 } do
					for _, cz in { -1, 1 } do
						local point = part.CFrame * (part.Size / 2 * Vector3.new(corner, cy, cz))
						low = low:Min(point)
						high = high:Max(point)
					end
				end
			end
		end
	end
	local offset = Vector3.new(0, 0, TIP)
	if low.X < math.huge then
		-- The tip's lowest point is a third of a stud behind the box's front (the rounded tip).
		local tip = Vector3.new((low.X + high.X) / 2, low.Y, low.Z + 0.32)
		offset = -tip
	end
	return offset
end

-- The guideline: short pencil dashes along the course (straight between guide points).
function TraceRace:_drawGuide(lane: Lane)
	local course = self.course
	local arena = self.context.Arena
	local dash, gap = 2.4, 1.1
	local s = 0
	while s < course.Length do
		local s1 = math.min(s + dash, course.Length)
		local a = self:_tip(lane, s, Rules.GuideAt(course, s)).Position
		local b = self:_tip(lane, s1, Rules.GuideAt(course, s1)).Position
		local span = (b - a).Magnitude
		Build.Decor({
			Name = "Guide",
			Size = Vector3.new(Rules.GUIDE_WIDTH, BAND, span + Rules.GUIDE_WIDTH * 0.3),
			CFrame = CFrame.lookAt((a + b) / 2, b) + Vector3.new(0, GUIDE_Y, 0),
			Color = rgb(85, 85, 100),
			Parent = arena,
		})
		s += dash + gap
	end
end

-- Ride ----------------------------------------------------------------------------------------------

function TraceRace:Start()
	local ctx = self.context
	local now = ctx:Now()
	local t0 = now + 0.2
	self.race = { T0 = t0, T1 = t0 + self.course.Length / Rules.SPEED }
	-- (Only who's still in the round: someone whose character never spawned is back in the lobby.)
	for _, player in ctx:GetPlayers() do
		if not self.lanes[player] then
			continue
		end
		local track = Rules.Tracker(self.course) :: Track
		-- The first position may be drawn the moment the ride starts.
		track.LastT = t0 - Rules.SAMPLE_GAP
		track.LastX = 0
		self.tracks[player] = track
		self.pending[player] = {}
	end
	ctx:SetSharedJSON("Race", { T0 = t0, T1 = self.race.T1 })
	-- No jumping on a crayon (owner: "Remove the jump button for trace race. it was confusing"): a
	-- character that can't jump has no jump button on phones. (The round's Begin gave everyone their
	-- jump back at GO; the next character, back in the lobby, has it again.)
	for player in self.lanes do
		local _, humanoid = ctx:GetCharacter(player)
		if humanoid then
			humanoid.JumpHeight = 0
			humanoid.JumpPower = 0
		end
	end

	ctx:OnAction("Trace", function(player, data)
		self:_onTrace(player, data)
	end, { Interval = 0.04 }) -- every position is checked on its own, so batches can come quickly

	local lastScores = 0
	local lastCrayons = -math.huge
	local finalized = false
	ctx:Loop(function(): number?
		local time = ctx:Now()
		local race = self.race
		-- Relay what the server took since the last relay, everyone's at once.
		local relay = {}
		local any = false
		for player, list in self.pending do
			if #list > 0 then
				relay[tostring(player.UserId)] = list
				self.pending[player] = {}
				any = true
			end
		end
		if any then
			ctx:Fire(nil, "Trails", relay)
		end
		-- Riders and crayons where the server has them. Every client moves every crayon smoothly
		-- itself, so the server's copy only needs a nudge now and then (moving 12 models 10 times a
		-- second replicated to every phone for nothing).
		local moveCrayons = time - lastCrayons >= 1
		if moveCrayons then
			lastCrayons = time
		end
		for player, lane in self.lanes do
			if not player.Parent then
				continue
			end
			local s, x = self:_where(player)
			if lane.Crayon and moveCrayons then
				lane.Crayon:PivotTo(
					self:_tip(lane, s, x) * CFrame.new(lane.Crayon:GetAttribute("TipToPivot") or Vector3.new(0, 0, TIP))
				)
			end
			if BotRegistry.IsBot(player) then
				self:_placeBot(player)
			end
		end
		if time - lastScores >= 0.5 and not finalized then
			lastScores = time
			self:_liveScores()
		end
		if not finalized and time >= race.T1 + FINAL_AT then
			finalized = true
			self:_finish()
		end
		if time >= race.T1 + END_AT then
			ctx:End("Finished")
			return nil
		end
		return 0.1
	end)
end

-- The board sorts by the numeric score: keep it equal to the shown percent (in tenths).
function TraceRace:_setScore(player: any, percent: number)
	local ctx = self.context
	local state = ctx:State(player)
	if state then
		local target = math.floor(percent * 10 + 0.5)
		if state.Score ~= target then
			ctx:AddScore(player, target - state.Score)
		end
	end
end

function TraceRace:_liveScores()
	local ctx = self.context
	local best, bestScore = nil, -1
	for player, track in self.tracks do
		if not player.Parent then
			continue
		end
		local live = track:Live()
		ctx:SetScoreText(player, if live then `{live}%` else "--")
		self:_setScore(player, live or 0)
		if live and live > bestScore then
			best, bestScore = player, live
		end
	end
	if best then
		ctx:SetStatus(`Most accurate: {best.DisplayName} {bestScore}%`)
	end
end

-- The ride is over: everyone's score is final (steps never drawn count as 0).
function TraceRace:_finish()
	local ctx = self.context
	local results = {}
	for player, track in self.tracks do
		if not player.Parent then
			continue
		end
		local score = track:Score()
		self.final[player] = score
		results[tostring(player.UserId)] = score
		ctx:SetScoreText(player, `{math.floor(score + 0.5)}%`)
		self:_setScore(player, score)
	end
	ctx:Fire(nil, "Final", results)
	local best, bestScore = nil, -1
	for player, score in self.final do
		if score > bestScore then
			best, bestScore = player, score
		end
	end
	if best then
		ctx:SetStatus(`{best.DisplayName} traced it best: {math.floor(bestScore + 0.5)}%!`)
	end
end

-- A batch of crayon positions from a player's device (or a bot): flat { t, x, t, x, ... }.
function TraceRace:_onTrace(player: any, data: any)
	local ctx = self.context
	local race = self.race
	local track = self.tracks[player]
	if not race or not track then
		return
	end
	if type(data) ~= "table" or #data % 2 ~= 0 or #data == 0 or #data > Rules.MAX_CHUNK * 2 then
		return
	end
	local now = ctx:Now()
	local lag = 0
	if not BotRegistry.IsBot(player) then
		local ok, ping = pcall(function()
			return player:GetNetworkPing()
		end)
		lag = if ok and type(ping) == "number" then math.clamp(ping, 0, 0.5) else 0.2
	end
	if now < race.T0 - 0.2 or now > race.T1 + math.min(lag, 0.25) + LATE then
		return
	end
	local list = self.pending[player]
	-- Anywhere on the paper, over the other lanes too (only the rider's own guide scores).
	local lane = self.lanes[player]
	if not lane then
		return
	end
	local lo, hi = lane.Lo - 0.05, lane.Hi + 0.05
	for at = 1, #data, 2 do
		local t, x = data[at], data[at + 1]
		if type(t) ~= "number" or type(x) ~= "number" or t ~= t or x ~= x then
			return -- junk or NaN
		end
		-- In order, inside the ride (never ahead of the server's clock), on the paper, and no further
		-- sideways from the last position than the crayon can steer.
		if
			t < track.LastT + Rules.SAMPLE_GAP * 0.5
			or t < race.T0 - 0.001
			or t < now - lag - 1.5 -- (drawn this long ago, even a resent one would have arrived)
			or t > math.min(now + 0.1, race.T1 + 0.1)
		then
			continue
		end
		if x < lo or x > hi then
			continue
		end
		-- (Clients cap the crayon at STEER; the 15% over that covers frame timing.)
		local reach = Rules.STEER * 1.15 * (t - track.LastT) + 0.1
		if math.abs(x - track.LastX) > reach then
			continue
		end
		track.LastT, track.LastX = t, x
		track:Add((t - race.T0) * Rules.SPEED, x)
		if list then
			table.insert(list, math.floor(t * 1000 + 0.5) / 1000)
			table.insert(list, math.floor(x * 100 + 0.5) / 100)
		end
	end
end

-- Bots ------------------------------------------------------------------------------------------------

-- The next crayon positions for a bot (or a test player) of this skill (0..1), up to `now`, in the
-- same flat { t, x, ... } form a client sends. A bot follows the guide a moment late (clumsy riders
-- turn late and cut every bend), wobbles round it and now and then slips off the line and back;
-- skilled riders are quicker and steadier (about 95%), clumsy ones wander (60s-70s). Bots never
-- leave their own lane (Rules.LIMIT), though players can.
function TraceRace:BotSamples(player: any, skill: number, random: Random, now: number): { number }?
	local race = self.race
	if not race or now < race.T0 then
		return nil
	end
	if not self.tracks[player] then
		return nil
	end
	local plan = self.botPlans[player]
	if not plan then
		local slips = {}
		local t = race.T0
		while t < race.T1 do
			t += random:NextNumber(2, 5) / (0.3 + (1 - skill) * 1.3)
			table.insert(
				slips,
				{ At = t, Size = random:NextNumber(1.5, 3.3) * (if random:NextNumber() < 0.5 then -1 else 1) }
			)
		end
		plan = {
			Last = race.T0 - 0.07,
			X = 0,
			Lag = Rules.SPEED * (0.06 + 0.3 * (1 - skill)), -- studs behind the guide
			Amp = 1.3 + 1.6 * (1 - skill) ^ 1.2,
			W1 = random:NextNumber(1.2, 2.2),
			W2 = random:NextNumber(3.5, 5.5),
			P1 = random:NextNumber(0, 6.28),
			P2 = random:NextNumber(0, 6.28),
			Slips = slips,
		}
		self.botPlans[player] = plan
	end
	local out = {}
	local t = plan.Last
	local dt = 0.07
	local step = Rules.STEER * (0.75 + 0.2 * skill) * dt
	while t + dt <= now and t + dt <= race.T1 and #out < Rules.MAX_CHUNK * 2 do
		t += dt
		local s = (t - race.T0) * Rules.SPEED
		local w = math.sin(t * plan.W1 + plan.P1) * 0.65 + math.sin(t * plan.W2 + plan.P2) * 0.35
		for _, slip in plan.Slips do
			local f = (t - slip.At) / 0.6
			if f > 0 and f < 1 then
				w += slip.Size * math.sin(f * math.pi)
			end
		end
		local target = Rules.GuideAt(self.course, s - plan.Lag) + w * plan.Amp
		plan.X = math.clamp(plan.X + math.clamp(target - plan.X, -step, step), -Rules.LIMIT, Rules.LIMIT)
		table.insert(out, t)
		table.insert(out, plan.X)
	end
	plan.Last = t
	return if #out > 0 then out else nil
end

-- Most accurate wins (to a tenth of a percent).
function TraceRace:GetResults()
	local ctx = self.context
	local entries = {}
	for _, player in ctx:GetPlayers() do
		if not player.Parent then
			continue
		end
		local score = self.final[player]
		if not score then
			local track = self.tracks[player]
			score = if track then track:Score() else 0
		end
		table.insert(entries, {
			Player = player,
			Rank = score,
			ScoreText = `{math.floor(score + 0.5)}% on the line`,
			BestScore = math.floor(score + 0.5),
		})
	end
	return { Entries = entries }
end

return TraceRace

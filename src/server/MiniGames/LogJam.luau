-- Log Jam (Team, 30s, 2-12 players). After "Log Jam" (Mario Party 3, 2 vs. 2): each team works a
-- sawmill. One teammate PLACES a log by pressing the shape shown on their screen, then the partner
-- CHOPS it by pressing that same shape; a wrong press jams the mill for a moment. The team that
-- chops the most logs in 30 seconds wins.
--
-- The players split into 2-4 teams (Teams.CountFor, about two a team). Every team has a station on
-- a wooden deck: the log rack on the players' left, the chopping stump in the middle and a big axe
-- on a hinge post on their right. The roles rotate every log (A places and B chops, then B places
-- and C chops...), so everyone both places and chops; a team of one does both. The prompt is one of
-- four shapes (▲ ■ ● ◆, each with its own colour too): the placer sees it at once, the chopper when
-- the log lands on the stump (BEAT later). A wrong shape, or a press before your prompt was showing,
-- jams the mill for JAM seconds (the same log waits).
--
-- The server owns everything: the shapes, whose turn it is, every press and the counts. A client
-- sends "Press" with the shape, the log number and the phase it pressed in (and when it pressed, by
-- its synced clock, for presses made just before the buzzer: Logic/Buzzer); a stale press (an old
-- log, the wrong phase) is dropped without a penalty, so lag never jams anyone. Each mill's state is
-- shared as "Mill_<Team>" (JSON) and the clients animate the log flying over, the axe and the split
-- halves from it. Bots press through ctx:BotAction exactly like a client (Bots/LogJam.luau); there is
-- no hazard here, the jam is the same server rule for everyone.
--
-- Ties: the team that reached its count first wins (the time of its last chop).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Buzzer = require(ReplicatedStorage.Shared.Logic.Buzzer)
local Teams = require(ReplicatedStorage.Shared.Teams)

local MiniGame = require(script.Parent.Kit.MiniGame)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local LogJam = MiniGame.Define("LogJam", { Results = "Team" })

LogJam.SYMBOLS = { "▲", "■", "●", "◆" }
LogJam.BEAT = 0.4 -- the placed log's flight to the stump; the chopper's prompt shows when it lands
LogJam.NEXT = 0.55 -- after a chop, until the next log's prompt
LogJam.JAM = 1.1 -- a wrong press stops the mill this long
LogJam.FIRST = 0.3 -- after GO, until the first prompt

-- Station geometry (studs, in the station's own frame: right = the players' right, up, toward = towards
-- the players). The meshes are made for these numbers (tools/meshgen/props/LogJam.py).
LogJam.HINGE = Vector3.new(4.6, 5.2, 0) -- the axe's hinge
LogJam.LOG_REST = Vector3.new(-3.5, 2.45, 0) -- the waiting log's middle, lying on the rack
LogJam.LOG_UP = Vector3.new(0, 3.56, 0) -- the log's middle standing on the stump
LogJam.AXE_REST = -70 -- the axe's resting angle (degrees; + is the head going down)
LogJam.AXE_BITE = 17.3 -- the axe stuck in the stump after a chop
local PEG = Vector3.new(-2.75, 1.6, 0) -- the rack's stop peg
local STUMP_TOP = 2.39 -- the stump's "Top" piece centre
local STAND = 6.8 -- the players' line, in front of the stump
local SPACING = 3.2 -- between neighbours in that line
local STATION_GAP = 26
local DECK = 0.6 -- the decks' top above the ground

type Station = {
	Team: string,
	CFrame: CFrame, -- on the deck, LookVector towards the players
	Members: { Player },
	Turn: number,
	Seq: number,
	Phase: string, -- "Wait" | "Place" | "Chop" | "Split" | "Gone"
	Symbol: number,
	ShowAt: number, -- when the current prompt shows (server time)
	JamUntil: number,
	JamBy: number, -- the UserId whose press jammed it
	Placer: Player?,
	Chopper: Player?,
	Logs: number,
	LastChopAt: number,
}

type Stats = { Placed: number, Chopped: number, Jams: number }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function upright(position: Vector3): CFrame
	return CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
end

-- A point in a station's frame (see the constants above).
function LogJam.Point(frame: CFrame, offset: Vector3): Vector3
	return frame.Position - frame.RightVector * offset.X + Vector3.yAxis * offset.Y + frame.LookVector * offset.Z
end

-- The axe's hinge frame: X along the players' right, Y up (its Z then points at the players), so the
-- chop pose is the axe mesh as built and Angles(0, 0, a) turns its head down by `a`.
function LogJam.HingeFrame(frame: CFrame): CFrame
	return CFrame.fromMatrix(LogJam.Point(frame, LogJam.HINGE), -frame.RightVector, Vector3.yAxis)
end

-- Moves a model so that its piece `name` is centred on `point`.
local function centre(model: Model, name: string, point: Vector3)
	local piece = model:FindFirstChild(name, true) :: BasePart?
	if piece then
		model:PivotTo(model:GetPivot() + (point - piece.Position))
	end
end

-- Slack for a press's timing, from the player's ping (bots have none).
local function lagOf(player: Player): number
	local ok, ping = pcall(function()
		return (player :: any):GetNetworkPing()
	end)
	return if ok and type(ping) == "number" then math.clamp(ping, 0, 0.5) else 0.1
end

-- The forest lumber yard round the decks (looks only: nothing here collides).
local function buildYard(ctx, origin: Vector3, frames: { CFrame })
	local arena = ctx.Arena
	local rng = Random.new(25)
	Build.Part({
		Name = "Grass",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 640, 640),
		CFrame = upright(origin - Vector3.new(0, 2, 0)),
		Color = rgb(104, 168, 76),
		Material = Enum.Material.Grass,
		Parent = arena,
	})
	-- The yard: packed dirt under the mills, sprinkled with sawdust.
	Build.Decor({
		Name = "Yard",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 150, 150),
		CFrame = upright(origin + Vector3.new(0, -0.1, -8)),
		Color = rgb(170, 126, 84),
		Material = Enum.Material.Ground,
		Parent = arena,
	})
	local function facing(at: Vector3, target: Vector3): CFrame
		return CFrame.lookAt(at, Vector3.new(target.X, at.Y, target.Z))
	end
	local front = origin + Vector3.new(0, 0, 60)
	-- The sawmill shed behind the stations, with lumber stacks either side.
	local millAt = origin + Vector3.new(0, 0, -38)
	MeshLibrary.Get("LogJamMill", { Scale = 1.25, CFrame = facing(millAt, front), Parent = arena })
	for _, spot in { { -40, -30, 15 }, { 40, -30, -15 }, { -58, -6, 70 }, { 58, -4, -70 }, { -30, 34, 160 } } do
		local at = origin + Vector3.new(spot[1], 0, spot[2])
		MeshLibrary.Get("LogJamLumber", {
			Scale = 1.3,
			CFrame = facing(at, front) * CFrame.Angles(0, math.rad(spot[3]), 0),
			Parent = arena,
		})
	end
	-- Sawdust and chips scattered on the yard.
	for _ = 1, 10 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(30, 60)
		MeshLibrary.Get("LogJamChips", {
			Scale = rng:NextNumber(1, 1.8),
			CFrame = CFrame.new(origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance - 8))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = arena,
		})
	end
	-- Pine forest all round, thicker behind the mill.
	local needles = { rgb(52, 124, 78), rgb(66, 140, 84), rgb(44, 110, 74), rgb(78, 150, 90) }
	for index = 0, 47 do
		local angle = (index + rng:NextNumber(-0.4, 0.4)) / 48 * math.pi * 2
		local distance = rng:NextNumber(82, 130)
		local at = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance - 10)
		MeshLibrary.Get("LogJamPine", {
			Scale = rng:NextNumber(1.2, 2.1),
			Colors = { Needles = needles[rng:NextInteger(1, #needles)] },
			CFrame = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = arena,
		})
	end
	for index = 0, 13 do
		local x = -95 + index * 14.5 + rng:NextNumber(-3, 3)
		local at = origin + Vector3.new(x, 0, -66 - rng:NextNumber(0, 12))
		MeshLibrary.Get("LogJamPine", {
			Scale = rng:NextNumber(1.3, 1.9),
			Colors = { Needles = needles[rng:NextInteger(1, #needles)] },
			CFrame = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = arena,
		})
	end
	-- Stumps of felled trees about the yard, between the stations and the trees.
	for _, frame in frames do
		local side = LogJam.Point(frame, Vector3.new(0, -DECK, -9))
		MeshLibrary.Get("LogJamChips", {
			Scale = 1.3,
			CFrame = CFrame.new(side) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = arena,
		})
	end
	for _, spot in { { -52, 18 }, { 50, 22 }, { -70, -40 }, { 72, -36 } } do
		MeshLibrary.Get("LogJamStump", {
			Scale = rng:NextNumber(0.9, 1.3),
			CFrame = CFrame.new(origin + Vector3.new(spot[1], 0, spot[2]))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = arena,
		})
	end
end

-- One team's mill: deck, rack, stump, axe and its post, the log and its two halves.
local function buildStation(ctx, team: string, frame: CFrame)
	local arena = ctx.Arena
	local color = Teams.Colors[team]
	local function at(offset: Vector3): Vector3
		return LogJam.Point(frame, offset)
	end
	local ground = frame - Vector3.new(0, DECK, 0)
	-- The deck: real planks to stand on (solid, and drawn), its edge trimmed in the team's colour.
	local deckCenter = LogJam.Point(ground, Vector3.new(-0.5, (DECK - 0.4) / 2, 2.5))
	Build.Part({
		Name = "Deck_" .. team,
		Size = Vector3.new(19, DECK + 0.4, 16),
		CFrame = CFrame.lookAt(deckCenter, deckCenter + frame.LookVector),
		Color = rgb(196, 150, 100),
		Material = Enum.Material.WoodPlanks,
		Parent = arena,
	})
	local trimCenter = deckCenter - Vector3.new(0, 0.12, 0)
	Build.Decor({
		Name = "DeckTrim_" .. team,
		Size = Vector3.new(19.8, DECK + 0.4 - 0.12, 16.8),
		CFrame = CFrame.lookAt(trimCenter, trimCenter + frame.LookVector),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Parent = arena,
	})

	local stump = MeshLibrary.Get("LogJamStump", { CFrame = frame, Parent = arena })
	centre(stump, "Top", at(Vector3.new(0, STUMP_TOP, 0)))
	stump.Name = "Stump_" .. team

	local rack = MeshLibrary.Get("LogJamRack", { CFrame = frame, Parent = arena })
	centre(rack, "Peg", at(PEG))
	rack.Name = "Rack_" .. team

	local hinge = LogJam.HingeFrame(frame)
	local post = MeshLibrary.Get("LogJamAxeFrame", { CFrame = frame, Parent = arena })
	centre(post, "Bolt", hinge.Position)
	post.Name = "Post_" .. team

	-- The axe, raised: placed level on its hinge, then turned up about it.
	local axe = MeshLibrary.Get("LogJamAxe", { CFrame = hinge, Parent = arena })
	centre(axe, "Collar", hinge.Position)
	local relative = hinge:ToObjectSpace(axe:GetPivot())
	axe:PivotTo(hinge * CFrame.Angles(0, 0, math.rad(LogJam.AXE_REST)) * relative)
	axe.Name = "Axe_" .. team

	-- The log waiting on the rack (lying along the players' line of sight).
	local rest = at(LogJam.LOG_REST)
	local log = MeshLibrary.Get("LogJamLog", {
		CFrame = CFrame.fromMatrix(rest, frame.RightVector, frame.LookVector),
		Parent = arena,
	})
	centre(log, "Wood", rest)
	log.Name = "Log_" .. team

	-- The two halves a chop leaves, hidden until the client splits a log.
	local up = at(LogJam.LOG_UP)
	for index, side in { 1, -1 } do
		local right = -frame.RightVector * side
		local half = MeshLibrary.Get("LogJamHalf", {
			CFrame = CFrame.fromMatrix(up, -right, Vector3.yAxis),
			Parent = arena,
		})
		centre(half, "Wood", up + frame.LookVector * side * 0.4)
		half.Name = `Half_{team}_{index}`
		for _, part in half:GetDescendants() do
			if part:IsA("BasePart") then
				part.Transparency = 1
				part.CastShadow = false
			end
		end
	end

	-- Sawdust round the stump, and the team's name over the mill (never colour alone).
	MeshLibrary.Get("LogJamChips", {
		CFrame = CFrame.new(at(Vector3.new(-0.8, 0, 2.1))) * CFrame.Angles(0, math.rad(30), 0),
		Parent = arena,
	})
	local top = stump:FindFirstChild("Top", true) :: BasePart?
	if top then
		Build.Billboard(top, `{string.upper(team)} MILL`, {
			Name = "TeamLabel",
			Size = UDim2.fromOffset(200, 50),
			StudsOffset = Vector3.new(0, 7.6, 0),
			MaxDistance = 300,
			TextColor3 = color,
		})
	end
end

function LogJam:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 30
	local origin = ctx.Origin.Position
	self.stations = {} :: { [string]: Station }
	self.order = {} :: { string }
	self.teamOf = {} :: { [Player]: string }
	self.stats = {} :: { [Player]: Stats }
	self.spots = {} :: { [Player]: CFrame }
	self.rng = Random.new()

	local players = ctx:GetPlayers()
	local names = {}
	-- (A solo test gets a single mill instead of an empty rival.)
	for index = 1, math.min(Teams.CountFor(#players, 2), math.max(#players, 1)) do
		table.insert(names, Teams.Order[index])
	end
	local teams = ctx:AssignTeams(names)

	-- The mills stand in a gentle arc facing a point in front of them, so everyone sees their
	-- neighbours' logs fly.
	local focus = origin + Vector3.new(0, 0, 80)
	local frames = {}
	local layout = {}
	for index, team in names do
		local x = (index - (#names + 1) / 2) * STATION_GAP
		local base = origin + Vector3.new(x, DECK, -x * x / 160)
		local frame = CFrame.lookAt(base, Vector3.new(focus.X, base.Y, focus.Z))
		frames[index] = frame
		buildStation(ctx, team, frame)
		local members = teams[team] or {}
		local station: Station = {
			Team = team,
			CFrame = frame,
			Members = members,
			Turn = 0,
			Seq = 0,
			Phase = "Wait",
			Symbol = 0,
			ShowAt = 0,
			JamUntil = 0,
			JamBy = 0,
			Placer = nil,
			Chopper = nil,
			Logs = 0,
			LastChopAt = math.huge,
		}
		self.stations[team] = station
		table.insert(self.order, team)
		for slot, player in members do
			self.teamOf[player] = team
			self.stats[player] = { Placed = 0, Chopped = 0, Jams = 0 }
			local stand = LogJam.Point(frame, Vector3.new((slot - (#members + 1) / 2) * SPACING, 0, STAND))
			self.spots[player] = CFrame.lookAt(stand, stand - frame.LookVector)
		end
		local p, look = frame.Position, frame.LookVector
		table.insert(layout, { Team = team, Pos = { p.X, p.Y, p.Z }, Look = { look.X, look.Z } })
		self:_roles(station)
		self:_publish(station)
	end
	buildYard(ctx, origin, frames)

	ctx:SetSharedJSON("Layout", {
		Stations = layout,
		Beat = LogJam.BEAT,
		Next = LogJam.NEXT,
		Jam = LogJam.JAM,
		Hinge = { LogJam.HINGE.X, LogJam.HINGE.Y, LogJam.HINGE.Z },
		LogRest = { LogJam.LOG_REST.X, LogJam.LOG_REST.Y, LogJam.LOG_REST.Z },
		LogUp = { LogJam.LOG_UP.X, LogJam.LOG_UP.Y, LogJam.LOG_UP.Z },
		AxeRest = LogJam.AXE_REST,
		AxeBite = LogJam.AXE_BITE,
	})

	local points = {}
	for _, player in players do
		table.insert(points, self.spots[player] or CFrame.new(focus))
	end
	ctx:SpawnAll(points, true)
	ctx.Hooks.Respawn = function(player)
		return self.spots[player]
	end
	for _, player in players do
		ctx:SetScoreText(player, "0 logs")
	end
	ctx:SetStatus("Press the shape on your screen!")
	ctx.Hooks.PlayerLeft = function(player)
		self:_leave(player)
	end
end

-- Who places and who chops the station's current log: the turn walks round the team.
function LogJam:_roles(station: Station)
	local members = station.Members
	local count = #members
	if count == 0 then
		station.Placer, station.Chopper = nil, nil
		return
	end
	local turn = math.max(station.Turn, 1)
	station.Placer = members[(turn - 1) % count + 1]
	station.Chopper = members[turn % count + 1]
end

function LogJam:_publish(station: Station)
	self.context:SetSharedJSON("Mill_" .. station.Team, {
		Seq = station.Seq,
		Phase = station.Phase,
		Symbol = station.Symbol,
		ShowAt = station.ShowAt,
		JamUntil = station.JamUntil,
		JamBy = station.JamBy,
		Placer = if station.Placer then station.Placer.UserId else 0,
		Chopper = if station.Chopper then station.Chopper.UserId else 0,
		Logs = station.Logs,
	})
end

-- The next log: a new shape (never the same twice running) and the next pair of teammates.
function LogJam:_nextLog(station: Station, showAt: number)
	if station.Phase == "Gone" or self.context:TimeIsUp() then
		return
	end
	station.Seq += 1
	station.Turn += 1
	local symbol = self.rng:NextInteger(1, #LogJam.SYMBOLS - 1)
	if symbol >= station.Symbol and station.Symbol > 0 then
		symbol += 1
	end
	station.Symbol = symbol
	station.Phase = "Place"
	station.ShowAt = showAt
	self:_roles(station)
	self:_publish(station)
end

function LogJam:_bump(player: Player, field: string)
	local stats = self.stats[player]
	if not stats then
		return
	end
	(stats :: any)[field] += 1
	self.context:SetScoreText(player, `{stats.Placed + stats.Chopped} logs`)
end

-- A press of one of the four shapes. `seq` and `phase` say which prompt the player answered: a press
-- meant for an earlier log or phase is dropped (it crossed a change on the way), never a penalty.
function LogJam:_press(player: Player, symbol: any, seq: any, phase: any, sentAt: any)
	local ctx = self.context
	local team = self.teamOf[player]
	local station = team and self.stations[team]
	if
		not station
		or type(symbol) ~= "number"
		or symbol ~= symbol
		or symbol % 1 ~= 0
		or symbol < 1
		or symbol > #LogJam.SYMBOLS
		or seq ~= station.Seq
		or phase ~= station.Phase
	then
		return
	end
	local role = if phase == "Place" then station.Placer elseif phase == "Chop" then station.Chopper else nil
	if role ~= player then
		return
	end
	local now = ctx:Now()
	if now < station.JamUntil then
		return -- jammed: the buttons are greyed out on screen too
	end
	local lag = lagOf(player)
	local pressedAt = Buzzer.PressTime(sentAt, now, lag)
	if not ctx:InTime(pressedAt) then
		return
	end
	-- A press made before the prompt could have shown is a guess: it jams like a wrong one.
	local early = pressedAt < station.ShowAt - 0.05
	if early or symbol ~= station.Symbol then
		station.JamUntil = now + LogJam.JAM
		station.JamBy = player.UserId
		local stats = self.stats[player]
		if stats then
			stats.Jams += 1
		end
		self:_publish(station)
		ctx:Fire(nil, "Jam", station.Team, player.UserId, symbol)
		return
	end
	if phase == "Place" then
		station.Phase = "Chop"
		station.ShowAt = now + LogJam.BEAT
		self:_bump(player, "Placed")
		ctx:AddScore(player, 1)
		self:_publish(station)
		return
	end
	station.Phase = "Split"
	station.Logs += 1
	station.LastChopAt = pressedAt
	self:_bump(player, "Chopped")
	ctx:AddScore(player, 1)
	ctx:AddTeamScore(station.Team, 1)
	self:_publish(station)
	local seqNow = station.Seq
	ctx:Delay(LogJam.NEXT, function()
		if station.Seq == seqNow and station.Phase == "Split" then
			self:_nextLog(station, ctx:Now())
		end
	end)
end

-- A player who leaves: the turn goes on with whoever is left; a team with nobody left stops.
function LogJam:_leave(player: Player)
	local team = self.teamOf[player]
	local station = team and self.stations[team]
	self.teamOf[player] = nil
	if not station then
		return
	end
	local index = table.find(station.Members, player)
	if index then
		table.remove(station.Members, index)
	end
	if #station.Members == 0 then
		station.Phase = "Gone"
		station.Placer, station.Chopper = nil, nil
		self:_publish(station)
		return
	end
	if station.Placer == player or station.Chopper == player then
		self:_roles(station)
		-- The new player on this prompt sees it from now.
		station.ShowAt = math.max(station.ShowAt, self.context:Now())
		self:_publish(station)
	end
end

function LogJam:Start()
	local ctx = self.context
	self.started = true
	for _, player in ctx:GetPlayers() do
		ctx:SetWalkSpeed(player, 0)
	end
	ctx.Hooks.CharacterReady = function(player)
		ctx:SetWalkSpeed(player, 0)
	end
	ctx:OnAction("Press", function(player, symbol, seq, phase, sentAt)
		self:_press(player, symbol, seq, phase, sentAt)
	end, { Interval = 0.1 })

	-- Anyone who left (or never spawned) before the hook was set.
	local gone = {}
	for player in self.teamOf do
		if not ctx:State(player) then
			table.insert(gone, player)
		end
	end
	for _, player in gone do
		self:_leave(player)
	end

	local first = ctx:Now() + LogJam.FIRST
	for _, team in self.order do
		self:_nextLog(self.stations[team], first)
	end

	-- The status line shows who's ahead; while any prompt is up near the buzzer, the end waits a
	-- moment for a press already on its way.
	local lastStatus = 0
	ctx:Loop(function(): number?
		local now = ctx:Now()
		local live = false
		for _, team in self.order do
			local phase = self.stations[team].Phase
			live = live or phase == "Place" or phase == "Chop"
		end
		if live then
			ctx:HoldEnd(0.3)
		end
		if now - lastStatus > 1 then
			lastStatus = now
			local leader = self:_leader()
			if leader then
				ctx:SetStatus(`{string.upper(leader)} leads: {self.stations[leader].Logs} logs`)
			end
		end
		return 0.1
	end)
end

-- The team with the most logs (still with players); a tie goes to whoever got there first. Nil if
-- nobody chopped anything, or on a dead heat.
function LogJam:_leader(): string?
	local best: Station? = nil
	local tie = false
	for _, team in self.order do
		local station = self.stations[team]
		if #station.Members == 0 or station.Logs == 0 then
			continue
		end
		if
			not best
			or station.Logs > best.Logs
			or (station.Logs == best.Logs and station.LastChopAt < best.LastChopAt)
		then
			best, tie = station, false
		elseif station.Logs == best.Logs and station.LastChopAt == best.LastChopAt then
			tie = true
		end
	end
	return if best and not tie then best.Team else nil
end

function LogJam:Stop(reason: string?)
	if not self.started then
		return
	end
	local ctx = self.context
	for _, team in self.order do
		local station = self.stations[team]
		if station.Phase ~= "Gone" then
			station.Phase = "Done"
			self:_publish(station)
		end
	end
	if reason == "TimeUp" then
		local leader = self:_leader()
		if leader then
			ctx:Announce(`{string.upper(leader)} MILL WINS!`, "success", 2.5)
			ctx:SetShared("Winner", leader)
		end
	end
end

-- Team results: most logs first (ties by who got there first); each line shows the team's logs and
-- the player's own share.
function LogJam:GetResults()
	local results = self.context:TeamResults()
	-- Equal counts rank by who got there first (a small bonus for each team that got there later).
	local later = {}
	for _, team in self.order do
		local station = self.stations[team]
		local count = 0
		for _, other in self.order do
			local rival = self.stations[other]
			if rival.Logs == station.Logs and rival.LastChopAt > station.LastChopAt then
				count += 1
			end
		end
		later[team] = count
	end
	for _, entry in results.Entries do
		local station = entry.Team and self.stations[entry.Team]
		local stats = self.stats[entry.Player]
		if station then
			entry.Rank = station.Logs + later[station.Team] * 0.1
			entry.ScoreText =
				`{entry.Team} {station.Logs} logs • you {if stats then stats.Placed + stats.Chopped else 0}`
		end
	end
	results.WinningTeam = self:_leader()
	return results
end

return LogJam

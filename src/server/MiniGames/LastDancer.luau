-- Last Dancer (Survival, 64s, 1-12 players). A rhythm dance-off (owner: "Let's make it", after the pitch
-- "Last Dancer Standing"; then "I want it to show your character basically playing on a DDR mat from an
-- arcade"): everyone stands on their own arcade dance mat (a 3 x 3 grid of panels with an arrow on each of
-- the four edge-centre ones, a safety rail round it) on a disco floor and steps on the arrow under
-- each falling note on the beat of the round's own song (Mirror Ball Showdown, 120 bpm). Hits keep a
-- dancer's groove up (a moving average of their recent form: Logic/LastDancer); at the end of each
-- 8-second phrase from the second to the seventh, the dancers with the lowest groove fall through the
-- floor, enough to leave two for the last phrase, the final duel; at the buzzer the highest groove wins.
--
-- The chart is the song's own lead line (LastDancerChart.luau, written from tools/music/songs/
-- LastDancer.py): the same notes for everybody, as seconds after GO and a lane 1-4. GO is the moment
-- the round's phase timer counts down to while the rules card shows (the song's drop lands there: the
-- audio is timed from the same clock), shared as "Go".
--
-- The server owns everything: a client only sends "Tap" with a lane and when it pressed (its synced
-- clock, less its sync setting). The server judges that against the chart with the shared logic
-- (Logic/LastDancer: the nearest waiting note in the lane within the Ok window, else a stray), judges
-- notes nobody hit as misses a little after their window (and the player's lag), and runs the cuts. The
-- cut is decided a third of a second before it happens, in the free last beat of the phrase the chart
-- leaves empty: the doomed tiles flash red, then drop on the downbeat. Nothing is sent per tap: each
-- client judges its own taps too, with the same logic, for instant PERFECT / GREAT text, and draws
-- everyone's groove from the shared "Board" (a few times a second).
--
-- Bots tap through ctx:BotAction exactly like a client (Bots/LastDancer.luau); there is no hazard here
-- but the cut, which is the same server rule for everyone. Eliminated dancers drop with their tile and
-- spectate the floor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Chart = require(ReplicatedStorage.Shared.LastDancerChart)
local GameDefinitions = require(ReplicatedStorage.Shared.GameDefinitions)
local GameState = require(ReplicatedStorage.Shared.GameState)
local Logic = require(ReplicatedStorage.Shared.Logic.LastDancer)
local SongTiming = require(ReplicatedStorage.Shared.Logic.SongTiming)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local LastDancer = MiniGame.Define("LastDancer", { Results = "Survival" })

-- A rhythm game is half a game without its own song, and the song waits for the owner's go-ahead to be
-- uploaded (ModePack8, tools/music/modes.py). Until its id is in AudioAssets the mode stays out of the
-- vote on live servers (no code to flip afterwards: the next publish after the upload has it in the vote);
-- Studio testing and the round harness ignore this, and play with the tick that keeps the beat.
if Sounds.ModeSongs.LastDancer == nil and not RunService:IsStudio() then
	local definition = GameDefinitions.Get("LastDancer")
	if definition then
		definition.Enabled = false
	end
end

LastDancer.Chart = Chart
LastDancer.WARN = 0.3 -- the cut is decided and shown this long before the tiles drop
LastDancer.DROP = 1.0 -- a tile's fall
LastDancer.MARGIN = 0.05 -- extra wait before a note is a miss, on top of the dancer's one-way lag

-- The floor (studs). A ring of dance mats round a stage, a pit under it all.
local CELL = 2.9 -- the pitch of a mat's 3 x 3 panels
local PANEL = 2.7 -- a panel's side
local MAT = CELL * 3 + 0.6 -- the mat's side
local MAT_THICK = 0.6
local STAGE_THICK = 1
local RAIL = 2.6 -- the safety rail's height (the rail is decoration: nothing collides, the camera passes)
local MAT_GAP = 1.6 -- between the mats' inner corners
local MIN_RING = 14
local PIT_DEPTH = 70
local SPEAKER_OUT = 30 -- the speaker stacks, this far past the ring of mats (clear of the camera)
local ORB_HEIGHT = 30
local MAX_STEPS = 48 -- steps sent to the clients in one batch, and per dancer in one:
local MAX_STEPS_EACH = 3
local STEP_CODES = { Perfect = 1, Great = 2, Ok = 3, Stray = 4, Late = 4 }

local HUES = {
	Color3.fromRGB(255, 80, 130),
	Color3.fromRGB(255, 150, 50),
	Color3.fromRGB(255, 215, 60),
	Color3.fromRGB(130, 230, 90),
	Color3.fromRGB(50, 220, 190),
	Color3.fromRGB(60, 190, 255),
	Color3.fromRGB(110, 120, 255),
	Color3.fromRGB(190, 110, 255),
	Color3.fromRGB(255, 110, 230),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 120, 90),
	Color3.fromRGB(150, 255, 160),
}

type Slot = {
	Player: Player,
	Index: number, -- the mat's place in the ring
	Tile: Model, -- the dancer's mat
	Spot: CFrame,
	State: Logic.Dancer,
	Order: number, -- a draw for settling dead heats
	Out: number?, -- seconds after GO the dancer went out
	Cut: boolean, -- ... by a cut (not by a reset or a fall)
	Sync: number, -- the dancer's sync setting (seconds the sound reaches them late; they tell the server)
	OutGroove: number,
	Doomed: boolean,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function upright(position: Vector3): CFrame
	return CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
end

-- Slack for a press's timing, from the player's ping (bots have none).
local function lagOf(player: Player): number
	if BotRegistry.IsBot(player) then
		return 0
	end
	local ok, ping = pcall(function()
		return (player :: any):GetNetworkPing()
	end)
	return if ok and type(ping) == "number" then math.clamp(ping, 0, 0.5) else 0.1
end

-- The arena: a ring of dance mats round a mirror-ball stage, speaker stacks, a pit with a glow under it.
local function buildFloor(ctx, origin: Vector3, count: number): (number, { CFrame })
	local arena = ctx.Arena
	-- The ring is wide enough that the mats' inner corners (square mats converge on the inside) clear
	-- each other by MAT_GAP.
	local ring = math.max(MIN_RING, (MAT + MAT_GAP) / (2 * math.sin(math.pi / count)) + MAT / 2)
	-- The dark ground far below: what the dancers who are cut fall towards.
	Build.Decor({
		Name = "Pit",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, ring * 5, ring * 5),
		CFrame = upright(origin - Vector3.new(0, PIT_DEPTH, 0)),
		Color = rgb(40, 18, 80),
		Material = Enum.Material.Neon,
		Transparency = 0.1,
		Parent = arena,
	})
	-- The stage the ring stands round: a dark glossy disc with neon rings, clear of the mats.
	local stage = ring - MAT / 2 - 1
	Build.Part({
		Name = "Stage",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(STAGE_THICK, stage * 2, stage * 2),
		CFrame = upright(origin - Vector3.new(0, STAGE_THICK / 2 + 0.4, 0)),
		Color = rgb(28, 20, 58),
		Material = Enum.Material.Glass,
		Parent = arena,
	})
	for step, share in { 0.34, 0.62, 0.9 } do
		Build.Decor({
			Name = "StageRing" .. step,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, stage * 2 * share, stage * 2 * share),
			CFrame = upright(origin - Vector3.new(0, 0.04 + 0.15 * (step - 1), 0)), -- (the smaller on top: no flicker)
			Color = HUES[(step * 3) % #HUES + 1],
			Material = Enum.Material.Neon,
			Transparency = 0.55,
			Parent = arena,
		})
	end
	-- The mirror ball, hanging over the stage from a rod (its centre ORB_HEIGHT up).
	local ball = MeshLibrary.Get("LastDancerMirrorBall", {
		CFrame = CFrame.new(origin + Vector3.new(0, ORB_HEIGHT - 4.5, 0)),
		Parent = arena,
	})
	local glass = ball:FindFirstChild("Ball", true)
	if glass and glass:IsA("BasePart") then
		Build.Light(glass, rgb(255, 230, 255), 60, 2)
	end
	Build.Decor({
		Name = "MirrorBallRod",
		Size = Vector3.new(0.4, 40, 0.4),
		Position = origin + Vector3.new(0, ORB_HEIGHT + 6.2 + 20, 0),
		Color = rgb(200, 200, 215),
		Parent = arena,
	})
	-- Speaker stacks and spotlights round the edge, the cones facing the stage. Each stack stands on a
	-- pillar rising out of the pit, its spotlight on top (they floated over the pit before). SPEAKER_OUT
	-- past the mats: Roblox's camera sits about 12 studs behind a dancer, and there a stack filled the
	-- whole view (owner's screenshot on spawning in).
	for index = 0, 5 do
		local angle = (index + 0.5) / 6 * math.pi * 2
		local out = ring + SPEAKER_OUT
		local at = origin + Vector3.new(math.cos(angle) * out, 0, math.sin(angle) * out)
		MeshLibrary.Get("LastDancerSpeaker", {
			CFrame = CFrame.lookAt(at, Vector3.new(origin.X, at.Y, origin.Z)),
			Parent = arena,
		})
		Build.Decor({
			Name = "SpeakerPillar",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(PIT_DEPTH, 4.2, 4.2),
			CFrame = upright(at - Vector3.new(0, PIT_DEPTH / 2 + 0.05, 0)),
			Color = rgb(24, 20, 40),
			Material = Enum.Material.Metal,
			Parent = arena,
		})
		local spot = Build.Decor({
			Name = "Spot",
			Size = Vector3.new(1.6, 1.6, 1.6),
			Position = at + Vector3.new(0, 13.9, 0),
			Color = HUES[(index * 2) % #HUES + 1],
			Material = Enum.Material.Neon,
			Parent = arena,
		})
		Build.Light(spot, spot.Color, 50, 2)
	end
	-- One mat a dancer, facing the middle.
	local points = Build.Ring(origin, ring, count)
	return ring, points
end

-- One dancer's mat: `frame` is the middle of its top, -Z towards the stage (the way the dancer faces, so the
-- UP arrow is the panel nearest the stage). A dark metal base to stand on (the only solid part), a 3 x 3 grid
-- of panels with an arrow on the four edge-centre ones (each lane's own colour, and lit by the client on the
-- beat and when stepped on), a strip and a centre disc in the dancer's colour, and a safety rail round the
-- front and sides like an arcade machine's. Returns the model.
local function buildMat(ctx, frame: CFrame, color: Color3, userId: number): Model
	local model = Instance.new("Model")
	model.Name = "Tile_" .. userId
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	Build.Part({
		Name = "Base",
		Size = Vector3.new(MAT, MAT_THICK, MAT),
		CFrame = at(0, -MAT_THICK / 2, 0),
		Color = rgb(34, 30, 52),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	Build.Decor({
		Name = "Strip",
		Size = Vector3.new(MAT, 0.12, 0.3),
		CFrame = at(0, 0.03, -(MAT / 2 - 0.25)),
		Color = color,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	local center = Build.Decor({
		Name = "Center",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 1.7, 1.7),
		CFrame = at(0, 0.04, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	Build.Light(center, color, 15, 1.4) -- each dancer is lit in their own colour
	for lane, arrow in Logic.ARROWS do
		local lit = rgb(arrow.Color[1], arrow.Color[2], arrow.Color[3])
		local x, z = arrow.Dx * CELL, arrow.Dz * CELL
		Build.Decor({
			Name = "Panel" .. lane,
			Size = Vector3.new(PANEL, 0.1, PANEL),
			CFrame = at(x, 0.05, z),
			Color = lit:Lerp(Color3.new(0, 0, 0), 0.45),
			Material = Enum.Material.Neon,
			Parent = model,
		})
		-- The arrow: two bars meeting at the tip (a chevron), drawn pointing UP and turned to this panel's way.
		local turn = at(x, 0.15, z) * CFrame.Angles(0, -math.rad(arrow.Rotation), 0)
		for piece, side in { HeadR = 1, HeadL = -1 } do
			-- (the left bar a hair higher, so the two never share a surface where they meet)
			local offset = CFrame.new(side * 0.53, if side < 0 then 0.01 else 0, -0.02)
			Build.Decor({
				Name = `Arrow{lane}{piece}`,
				Size = Vector3.new(0.55, 0.1, 1.5),
				CFrame = turn * offset * CFrame.Angles(0, side * math.rad(45), 0),
				Color = Color3.new(1, 1, 1),
				Material = Enum.Material.Neon,
				Parent = model,
			})
		end
	end
	-- The safety rail: a bar across the front and one down each side, held up by posts at the front (the side
	-- bars a little thinner and the posts a little thicker than the front bar where they meet).
	local half = MAT / 2 + 0.3
	local function rail(piece: string, size: Vector3, cframe: CFrame)
		Build.Decor({
			Name = "Rail" .. piece,
			Shape = Enum.PartType.Cylinder,
			Size = size,
			CFrame = cframe,
			Color = rgb(205, 210, 225),
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
	rail("Front", Vector3.new(half * 2, 0.3, 0.3), at(0, RAIL, -half))
	rail(
		"Left",
		Vector3.new(half + 0.6, 0.26, 0.26),
		at(-half, RAIL, -half / 2 + 0.3) * CFrame.Angles(0, math.rad(90), 0)
	)
	rail(
		"Right",
		Vector3.new(half + 0.6, 0.26, 0.26),
		at(half, RAIL, -half / 2 + 0.3) * CFrame.Angles(0, math.rad(90), 0)
	)
	rail("PostL", Vector3.new(RAIL, 0.36, 0.36), at(-half, RAIL / 2, -half) * CFrame.Angles(0, 0, math.rad(90)))
	rail("PostR", Vector3.new(RAIL, 0.36, 0.36), at(half, RAIL / 2, -half) * CFrame.Angles(0, 0, math.rad(90)))
	-- (No name over the mat: the dancer's own name tag says who it is, and two names stacked over every
	-- dancer were a jumble.)
	model.Parent = ctx.Arena
	return model
end

function LastDancer:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	ctx.WalkSpeed = 0 -- nobody walks off their mat
	ctx.KillY = ctx.Origin.Y - PIT_DEPTH + 25
	local origin = ctx.Origin.Position
	self.rng = Random.new()
	self.slots = {} :: { [Player]: Slot }
	self.order = {} :: { Player }
	self.cutsDone = {} :: { [number]: boolean }
	self.warned = {} :: { [number]: boolean }
	self.drops = {} :: { { Model: Model, Pivot: CFrame, Start: number } }
	self.steps = {} :: { { number } } -- this batch's steps: {userId, lane, outcome code}
	self.stepsBy = {} :: { [Player]: number }
	self.boardKey = ""
	self.final = false
	self.startCount = #ctx:GetPlayers()
	-- GO: the moment the phase timer counts down to while the rules card shows. The round's song is timed
	-- from it, and so is the chart.
	local phaseEnd = GameState.Get("PhaseEndsAt")
	self.go = if type(phaseEnd) == "number" and phaseEnd > 0 then phaseEnd else ctx:Now() + 13
	ctx:SetShared("Go", self.go)

	local players = ctx:GetPlayers()
	-- A different seating every round.
	for index = #players, 2, -1 do
		local other = self.rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local ring, points = buildFloor(ctx, origin, math.max(#players, 2))
	local layout = {}
	for index, player in players do
		local point = points[index]
		local color = HUES[(index - 1) % #HUES + 1]
		local position = point.Position
		local mat =
			buildMat(ctx, CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z)), color, player.UserId)
		self.slots[player] = {
			Player = player,
			Index = index,
			Tile = mat,
			Spot = CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z)),
			State = Logic.new(),
			Order = self.rng:NextNumber(),
			Out = nil,
			Cut = false,
			Sync = 0,
			OutGroove = 0,
			Doomed = false,
		}
		table.insert(self.order, player)
		table.insert(layout, { Id = player.UserId, Index = index, Hue = { color.R, color.G, color.B } })
	end
	ctx:SetSharedJSON("Floor", {
		Center = { origin.X, origin.Y, origin.Z },
		Ring = ring,
		Cell = CELL,
		Tiles = layout,
	})

	-- Each dancer on their own mat. (Not ctx:SpawnAll: it deals its points out in the round's own player order,
	-- not in this seating's, which put dancers on each other's mats and dropped the wrong ones.)
	local pending = 0
	for _, player in self.order do
		pending += 1
		task.spawn(function()
			local slot = self.slots[player]
			if slot then
				ctx:SpawnPlayer(player, slot.Spot, true)
			end
			pending -= 1
		end)
	end
	local deadline = os.clock() + 8
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
	ctx.Hooks.CharacterReady = function(player)
		self:_still(player)
	end
	ctx.Hooks.PlayerLeft = function(player)
		self:_leave(player)
	end
	-- (Out by a reset or a fall, not a cut: the result still says when, with the groove they had.)
	ctx.Hooks.Eliminated = function(player)
		local slot = self.slots[player]
		if slot and slot.Out == nil then
			slot.Out = ctx:Elapsed()
			slot.OutGroove = slot.State.Groove
		end
	end
	for _, player in players do
		ctx:SetScoreText(player, "")
	end
	ctx:SetStatus("Tap the notes on the beat!")
end

-- Nobody walks or jumps: dancers stay on their mats.
function LastDancer:_still(player: Player)
	local ctx = self.context
	local _, humanoid = ctx:GetCharacter(player)
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	end
end

function LastDancer:_alive(): { Player }
	local list = {}
	for _, player in self.order do
		local slot = self.slots[player]
		if slot and self.context:IsAlive(player) then
			table.insert(list, player)
		end
	end
	return list
end

-- The groove as the clients show it: a whole number 0-100.
local function percent(groove: number): number
	return math.clamp(math.floor(groove * 100 + 0.5), 0, 100)
end

function LastDancer:_board()
	local rows = {}
	local key = {}
	for _, player in self.order do
		local slot = self.slots[player]
		if slot then
			local alive = if self.context:IsAlive(player) then 1 else 0
			local row = { slot.Player.UserId, percent(slot.State.Groove), slot.State.Score, alive, slot.State.Combo }
			table.insert(rows, row)
			table.insert(key, table.concat(row, ","))
		end
	end
	local joined = table.concat(key, ";")
	if joined ~= self.boardKey then
		self.boardKey = joined
		self.context:SetSharedJSON("Board", rows)
	end
end

-- The cut shown on the HUD: when it comes and how many fall (nil Phase: none left).
function LastDancer:_publishCut(rel: number)
	local ctx = self.context
	local phase = Logic.PhraseAt(rel)
	local nextPhase = phase
	while nextPhase <= Logic.LAST_CUT and self.cutsDone[nextPhase] do
		nextPhase += 1
	end
	if nextPhase < Logic.FIRST_CUT then
		nextPhase = Logic.FIRST_CUT
	end
	local at = Logic.CutTime(nextPhase)
	if not at then
		ctx:SetSharedJSON("Cut", { Final = true })
		return
	end
	ctx:SetSharedJSON("Cut", {
		Phase = nextPhase,
		At = self.go + at,
		Count = Logic.CutCount(#self:_alive(), nextPhase, self.startCount),
		Final = false,
	})
end

-- Decides who falls at the end of `phase`: the lowest groove. They flash red now and drop in WARN seconds.
function LastDancer:_warn(phase: number)
	local ctx = self.context
	self.warned[phase] = true
	local alive = self:_alive()
	local count = Logic.CutCount(#alive, phase, self.startCount)
	if count <= 0 then
		return
	end
	local entries = {}
	for _, player in alive do
		local slot = self.slots[player]
		table.insert(entries, {
			Key = player,
			Groove = slot.State.Groove,
			Score = slot.State.Score,
			Order = slot.Order,
		})
	end
	local ids = {}
	local doomed = {}
	for _, player in Logic.PickCuts(entries, count) do
		local slot = self.slots[player]
		slot.Doomed = true
		slot.Tile:SetAttribute("Doomed", true)
		table.insert(doomed, player)
		table.insert(ids, player.UserId)
	end
	self.doomed = doomed
	ctx:Fire(nil, "CutWarn", ids, self.go + (Logic.CutTime(phase) :: number))
	ctx:Sound("HazardWarning")
end

-- The tiles of the dancers decided in _warn drop, and the dancers with them are out.
function LastDancer:_cut(phase: number, rel: number)
	local ctx = self.context
	self.cutsDone[phase] = true
	-- (Someone may have left since the warning: only as many fall as the schedule still needs, the worst
	-- first, and the rest of the doomed are spared.)
	local limit = Logic.CutCount(#self:_alive(), phase, self.startCount)
	local ids, spared = {}, {}
	for _, player in self.doomed or {} do
		local slot = self.slots[player]
		if not slot or not ctx:IsAlive(player) then
			-- (gone, or reset, since the warning: their mat stops flashing on every device)
			if slot then
				slot.Doomed = false
				slot.Tile:SetAttribute("Doomed", nil)
			end
			table.insert(spared, player.UserId)
			continue
		end
		if #ids >= limit then
			slot.Doomed = false
			slot.Tile:SetAttribute("Doomed", nil)
			table.insert(spared, player.UserId)
			continue
		end
		slot.Out = rel
		slot.Cut = true
		slot.OutGroove = slot.State.Groove
		table.insert(ids, player.UserId)
		self:_drop(slot.Tile)
		ctx:Eliminate(player, "cut", LastDancer.DROP + 0.4)
	end
	self.doomed = nil
	ctx:Fire(nil, "Cut", ids, phase, spared)
	local left = self:_alive()
	ctx:SetStatus(`Dancers left: {#left}`)
	if phase == Logic.LAST_CUT and #left >= 2 then
		self.final = true
		ctx:Announce("FINAL DUEL!", "warning", 3)
	end
	self:_publishCut(rel)
	self:_board()
end

-- A mat falls into the pit (a model can't be tweened: its pivot is moved every frame, see Start).
function LastDancer:_drop(mat: Model)
	if mat.Parent then
		table.insert(self.drops, { Model = mat, Pivot = mat:GetPivot(), Start = os.clock() })
	end
end

-- A dancer who leaves is simply gone (the tile drops, and a round down to one dancer ends).
function LastDancer:_leave(player: Player)
	local slot = self.slots[player]
	if not slot then
		return
	end
	self:_drop(slot.Tile)
	local at = table.find(self.order, player)
	if at then
		table.remove(self.order, at)
	end
	self.slots[player] = nil
	if self.started then
		-- (the HUD's "N fall" depends on who is left)
		self:_publishCut(self.context:Now() - self.go)
		self:_board()
	end
	if self.doomed then
		local doomed = table.find(self.doomed, player)
		if doomed then
			table.remove(self.doomed, doomed)
		end
	end
end

-- A tap in `lane` made at `sentAt` (the device's synced clock, less its sync setting).
function LastDancer:_tap(player: Player, lane: any, sentAt: any)
	local ctx = self.context
	local slot = self.slots[player]
	if not slot or not ctx:IsAlive(player) then
		return
	end
	local now = ctx:Now()
	local pressedAt = Logic.PressTime(sentAt, now, lagOf(player))
	if not ctx:InTime(pressedAt) then
		return
	end
	local rel = pressedAt - self.go
	if Logic.InWarmup(Chart, rel) then
		return -- the warm-up: tapping the pads to see how they feel costs nothing
	end
	local outcome = Logic.Tap(Chart, slot.State, lane, rel)
	if outcome.Points > 0 then
		ctx:AddScore(player, outcome.Points)
	end
	-- Everybody sees this dancer step on that arrow (a stray too: the foot went there), a few times a batch
	-- at most so a masher can't flood the clients.
	if
		type(lane) == "number"
		and lane % 1 == 0
		and lane >= 1
		and lane <= Logic.LANES
		and #self.steps < MAX_STEPS
		and (self.stepsBy[player] or 0) < MAX_STEPS_EACH
	then
		self.stepsBy[player] = (self.stepsBy[player] or 0) + 1
		table.insert(self.steps, { player.UserId, lane, STEP_CODES[outcome.Kind] })
	end
end

-- Sends the steps made since the last batch to every client (about 20 times a second).
function LastDancer:_flushSteps()
	if #self.steps == 0 then
		return
	end
	self.context:Fire(nil, "Steps", self.steps)
	self.steps = {}
	table.clear(self.stepsBy)
end

-- Notes nobody hit are misses once their window is over, and the dancer's lag and sync setting (a tap
-- for the note is made that much later when the sound reaches them late), so a tap still on its way
-- isn't missed.
function LastDancer:_expire(now: number)
	for _, player in self.order do
		local slot = self.slots[player]
		if slot and self.context:IsAlive(player) then
			local rel = now - self.go - slot.Sync - lagOf(player) / 2 - LastDancer.MARGIN
			Logic.Expire(Chart, slot.State, rel)
		end
	end
end

function LastDancer:Start()
	local ctx = self.context
	self.started = true
	-- A round that began more than SongTiming.DRIFT after GO (a slow Prepare): every device's song jumps
	-- to the real start (AudioController), so the chart moves there too and the notes stay on the music.
	local definition = GameDefinitions.Get("LastDancer")
	local phaseEnd = GameState.Get("PhaseEndsAt")
	if definition and type(phaseEnd) == "number" and phaseEnd > 0 then
		local began = phaseEnd - definition.Duration
		if began - self.go > SongTiming.DRIFT then
			self.go = began
			ctx:SetShared("Go", self.go)
		end
	end
	for _, player in ctx:GetPlayers() do
		self:_still(player)
	end
	ctx:OnAction("Tap", function(player, lane, sentAt)
		self:_tap(player, lane, sentAt)
	end, { Interval = 0.035 })

	-- Anyone who left (or never spawned) before the hook was set.
	local gone = {}
	for _, player in self.order do
		if not ctx:State(player) then
			table.insert(gone, player)
		end
	end
	for _, player in gone do
		self:_leave(player)
	end
	self.startCount = #self:_alive()
	self:_publishCut(0)
	self:_board()

	-- Each dancer's sync setting (0 to SYNC_MAX seconds): their taps are made that much after the clock says.
	ctx:OnAction("Sync", function(player, value)
		local slot = self.slots[player]
		if slot and type(value) == "number" and value == value then
			slot.Sync = math.clamp(value, 0, Logic.SYNC_MAX)
		end
	end, { Interval = 0.1 })

	-- Each of these keeps going if one step of it fails (a loop that errors once would stop for good).
	local failures = 0
	local function safely(label: string, step: () -> ())
		local ok, err = pcall(step)
		if not ok then
			failures += 1
			if failures <= 5 then
				warn(`[LastDancer] {label} failed: {err}`)
			end
		end
	end
	ctx:Heartbeat(function()
		safely("falling mats", function()
			self:_animateDrops()
		end)
	end)
	ctx:Loop(function(): number?
		safely("steps", function()
			self:_flushSteps()
		end)
		return 0.05
	end)
	ctx:Loop(function(): number?
		safely("round", function()
			self:_tick()
		end)
		return 0.05
	end)
end

-- The mats that are falling (every frame: a model's pivot is moved by hand).
function LastDancer:_animateDrops()
	local now = os.clock()
	for index = #self.drops, 1, -1 do
		local drop = self.drops[index]
		local t = (now - drop.Start) / LastDancer.DROP
		if drop.Model.Parent then
			drop.Model:PivotTo(drop.Pivot * CFrame.new(0, -PIT_DEPTH * math.min(t, 1) ^ 2, 0))
		end
		if t >= 1 or not drop.Model.Parent then
			table.remove(self.drops, index)
		end
	end
end

-- Misses, the cuts (decided WARN before they happen, carried out on the downbeat) and the board.
function LastDancer:_tick()
	local now = self.context:Now()
	local rel = now - self.go
	self:_expire(now)
	for phase = Logic.FIRST_CUT, Logic.LAST_CUT do
		local at = Logic.CutTime(phase) :: number
		if not self.warned[phase] and rel >= at - LastDancer.WARN then
			self:_warn(phase)
		end
		if not self.cutsDone[phase] and rel >= at then
			if not self.warned[phase] then
				self:_warn(phase)
			end
			self:_cut(phase, rel)
		end
	end
	self:_board()
end

-- At the buzzer the highest groove wins. (Everyone else was cut earlier.)
function LastDancer:Stop(reason: string?)
	if not self.started then
		return
	end
	local ctx = self.context
	self:_board()
	local winner = self:_winner()
	if winner and (reason == "TimeUp" or reason == "LastSurvivor") then
		ctx:Announce(`{winner.DisplayName} IS THE LAST DANCER!`, "success", 3)
		ctx:SetShared("Winner", winner.UserId)
	end
end

-- The dancer ahead of every other dancer still on the floor (nil if nobody is).
function LastDancer:_winner(): Player?
	local best: Player? = nil
	local bestEntry
	for _, player in self:_alive() do
		local slot = self.slots[player]
		local entry = { Key = player, Groove = slot.State.Groove, Score = slot.State.Score, Order = slot.Order }
		if not best or Logic.Ahead(entry, bestEntry) then
			best, bestEntry = player, entry
		end
	end
	return best
end

-- Results: the dancers left at the end rank by groove then points; everyone cut ranks by how long they
-- lasted (a later cut is better), then by the groove they went out with.
function LastDancer:GetResults()
	local ctx = self.context
	local results = ctx:SurvivalResults()
	local elapsed = ctx:Elapsed()
	local standing = {} -- the dancers left, to be ordered by who finishes ahead
	for _, entry in results.Entries do
		local slot = self.slots[entry.Player]
		if not slot then
			continue
		end
		local state = slot.State
		local alive = ctx:IsAlive(entry.Player)
		local groove = if alive then state.Groove else slot.OutGroove
		if alive then
			entry.Survived = elapsed
			entry.ScoreText = `Last dancer! {percent(groove)}% groove • {state.Score} pts`
			table.insert(standing, { Key = entry, Groove = groove, Score = state.Score, Order = slot.Order })
		else
			local out = slot.Out or 0
			entry.Rank = out + percent(groove) / 1000
			entry.Survived = out
			entry.ScoreText =
				`{if slot.Cut then "Cut" else "Out"} at {math.floor(out)}s • {percent(groove)}% groove • {state.Score} pts`
		end
		entry.BestScore = state.Score
	end
	-- Those left at the buzzer place in the order that picked the winner (groove, then points, then the
	-- draw), one place each: the announced winner is always first.
	table.sort(standing, function(a, b)
		return Logic.Ahead(a, b)
	end)
	for index, item in standing do
		item.Key.Rank = 1e6 + (#standing - index + 1) * 1000
	end
	return results
end

return LastDancer

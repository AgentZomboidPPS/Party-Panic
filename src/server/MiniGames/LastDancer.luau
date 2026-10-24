-- Last Dancer (Survival, 64s, 1-12 players). A rhythm dance-off (owner: "Let's make it", after the pitch
-- "Last Dancer Standing"): everyone stands on a glowing tile of a disco floor and taps the pad under
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
local TweenService = game:GetService("TweenService")

local Chart = require(ReplicatedStorage.Shared.LastDancerChart)
local GameState = require(ReplicatedStorage.Shared.GameState)
local Logic = require(ReplicatedStorage.Shared.Logic.LastDancer)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)

local LastDancer = MiniGame.Define("LastDancer", { Results = "Survival" })

LastDancer.Chart = Chart
LastDancer.WARN = 0.3 -- the cut is decided and shown this long before the tiles drop
LastDancer.DROP = 1.0 -- a tile's fall
LastDancer.MARGIN = 0.05 -- extra wait before a note is a miss, on top of the dancer's one-way lag

-- The floor (studs). A ring of tiles round a stage, a pit under it all.
local TILE = 7
local TILE_THICK = 1
local TILE_GAP = 1.6
local MIN_RING = 14
local PIT_DEPTH = 70
local ORB_HEIGHT = 30

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
	Index: number, -- the tile's place in the ring
	Tile: BasePart,
	Pad: BasePart,
	Spot: CFrame,
	State: Logic.Dancer,
	Order: number, -- a draw for settling dead heats
	Out: number?, -- seconds after GO the dancer was cut
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

-- The arena: a ring of lit tiles round a mirror-ball stage, speaker stacks, a pit with a glow under it.
local function buildFloor(ctx, origin: Vector3, count: number): (number, { CFrame })
	local arena = ctx.Arena
	local ring = math.max(MIN_RING, count * (TILE + TILE_GAP) / (math.pi * 2))
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
	-- The stage the ring stands round: a dark glossy disc with a neon rim.
	Build.Part({
		Name = "Stage",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(TILE_THICK, ring * 2 - TILE - 2, ring * 2 - TILE - 2),
		CFrame = upright(origin - Vector3.new(0, TILE_THICK / 2 + 0.4, 0)),
		Color = rgb(28, 20, 58),
		Material = Enum.Material.Glass,
		Parent = arena,
	})
	for step, radius in { 0.32, 0.55, 0.78 } do
		Build.Decor({
			Name = "StageRing" .. step,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, ring * 2 * radius, ring * 2 * radius),
			CFrame = upright(origin - Vector3.new(0, 0.3, 0)),
			Color = HUES[(step * 3) % #HUES + 1],
			Material = Enum.Material.Neon,
			Transparency = 0.55,
			Parent = arena,
		})
	end
	-- The mirror ball, hanging over the stage.
	local ball = Build.Part({
		Name = "MirrorBall",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 9,
		Position = origin + Vector3.new(0, ORB_HEIGHT, 0),
		Color = rgb(235, 240, 255),
		Material = Enum.Material.Metal,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = arena,
	})
	Build.Light(ball, rgb(255, 230, 255), 60, 2)
	Build.Decor({
		Name = "MirrorBallRod",
		Size = Vector3.new(0.4, 40, 0.4),
		Position = origin + Vector3.new(0, ORB_HEIGHT + 24, 0),
		Color = rgb(200, 200, 215),
		Parent = arena,
	})
	-- Speaker stacks and spotlights round the edge.
	for index = 0, 5 do
		local angle = (index + 0.5) / 6 * math.pi * 2
		local at = origin + Vector3.new(math.cos(angle) * (ring + 12), 0, math.sin(angle) * (ring + 12))
		local facing = CFrame.lookAt(at, Vector3.new(origin.X, at.Y, origin.Z))
		for level = 0, 2 do
			Build.Part({
				Name = "Speaker",
				Size = Vector3.new(5 - level * 0.6, 4.4, 4.4),
				CFrame = facing * CFrame.new(0, 2.2 + level * 4.4, 0),
				Color = rgb(24, 22, 36),
				Material = Enum.Material.Slate,
				Parent = arena,
			})
			Build.Decor({
				Name = "Cone",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.3, 3, 3),
				CFrame = facing * CFrame.new(0, 2.2 + level * 4.4, -2.25) * CFrame.Angles(0, math.rad(90), 0),
				Color = rgb(70, 70, 90),
				Parent = arena,
			})
		end
		local spot = Build.Decor({
			Name = "Spot",
			Size = Vector3.new(1.6, 1.6, 1.6),
			Position = at + Vector3.new(0, 16, 0),
			Color = HUES[(index * 2) % #HUES + 1],
			Material = Enum.Material.Neon,
			Parent = arena,
		})
		Build.Light(spot, spot.Color, 50, 2)
	end
	-- The tiles: one a dancer, facing the middle, a slab with a neon pad on top.
	local points = Build.Ring(origin, ring, count)
	return ring, points
end

function LastDancer:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	ctx.WalkSpeed = 0 -- nobody walks off their tile
	ctx.KillY = ctx.Origin.Y - PIT_DEPTH + 25
	local origin = ctx.Origin.Position
	self.rng = Random.new()
	self.slots = {} :: { [Player]: Slot }
	self.order = {} :: { Player }
	self.cutsDone = {} :: { [number]: boolean }
	self.warned = {} :: { [number]: boolean }
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
		local slab = Build.Part({
			Name = "Tile_" .. player.UserId,
			Size = Vector3.new(TILE, TILE_THICK, TILE),
			CFrame = CFrame.lookAt(
				position - Vector3.new(0, TILE_THICK / 2, 0),
				origin - Vector3.new(0, TILE_THICK / 2, 0)
			),
			Color = rgb(30, 24, 60),
			Material = Enum.Material.SmoothPlastic,
			Parent = ctx.Arena,
		})
		local pad = Build.Decor({
			Name = "Pad",
			Size = Vector3.new(TILE - 1, 0.25, TILE - 1),
			CFrame = slab.CFrame * CFrame.new(0, TILE_THICK / 2 + 0.05, 0),
			Color = color,
			Material = Enum.Material.Neon,
			Parent = slab,
		})
		Build.Billboard(slab, player.DisplayName, {
			Name = "DancerName",
			Size = UDim2.fromOffset(200, 44),
			StudsOffset = Vector3.new(0, 9, 0),
			MaxDistance = 200,
			TextColor3 = color,
		})
		self.slots[player] = {
			Player = player,
			Index = index,
			Tile = slab,
			Pad = pad,
			Spot = CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z)),
			State = Logic.new(),
			Order = self.rng:NextNumber(),
			Out = nil,
			OutGroove = 0,
			Doomed = false,
		}
		table.insert(self.order, player)
		table.insert(layout, { Id = player.UserId, Index = index, Hue = { color.R, color.G, color.B } })
	end
	ctx:SetSharedJSON("Floor", {
		Center = { origin.X, origin.Y, origin.Z },
		Ring = ring,
		Tiles = layout,
	})

	local spots = {}
	for _, player in self.order do
		table.insert(spots, self.slots[player].Spot)
	end
	ctx:SpawnAll(spots, true)
	ctx.Hooks.CharacterReady = function(player)
		self:_still(player)
	end
	ctx.Hooks.PlayerLeft = function(player)
		self:_leave(player)
	end
	for _, player in players do
		ctx:SetScoreText(player, "")
	end
	ctx:SetStatus("Tap the notes on the beat!")
end

-- Nobody walks or jumps: dancers stay on their tiles.
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
	local ids = {}
	for _, player in self.doomed or {} do
		local slot = self.slots[player]
		if slot and ctx:IsAlive(player) then
			slot.Out = rel
			slot.OutGroove = slot.State.Groove
			table.insert(ids, player.UserId)
			local tween = TweenService:Create(
				slot.Tile,
				TweenInfo.new(LastDancer.DROP, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					CFrame = slot.Tile.CFrame * CFrame.new(0, -PIT_DEPTH, 0),
				}
			)
			tween:Play()
			ctx:Eliminate(player, "cut", LastDancer.DROP + 0.4)
		end
	end
	self.doomed = nil
	ctx:Fire(nil, "Cut", ids, phase)
	local left = self:_alive()
	ctx:SetStatus(`Dancers left: {#left}`)
	if phase == Logic.LAST_CUT and #left >= 2 then
		self.final = true
		ctx:Announce("FINAL DUEL!", "warning", 3)
	end
	self:_publishCut(rel)
	self:_board()
end

-- A dancer who leaves is simply gone (the tile drops, and a round down to one dancer ends).
function LastDancer:_leave(player: Player)
	local slot = self.slots[player]
	if not slot then
		return
	end
	if slot.Tile.Parent then
		TweenService
			:Create(slot.Tile, TweenInfo.new(LastDancer.DROP, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = slot.Tile.CFrame * CFrame.new(0, -PIT_DEPTH, 0),
			})
			:Play()
	end
	local at = table.find(self.order, player)
	if at then
		table.remove(self.order, at)
	end
	self.slots[player] = nil
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
end

-- Notes nobody hit are misses once their window is over (and the dancer's lag, so a tap still on its
-- way isn't missed).
function LastDancer:_expire(now: number)
	for _, player in self.order do
		local slot = self.slots[player]
		if slot and self.context:IsAlive(player) then
			local rel = now - self.go - lagOf(player) / 2 - LastDancer.MARGIN
			Logic.Expire(Chart, slot.State, rel)
		end
	end
end

function LastDancer:Start()
	local ctx = self.context
	self.started = true
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

	ctx:Loop(function(): number?
		local now = ctx:Now()
		local rel = now - self.go
		self:_expire(now)
		-- The cuts: decided WARN before they happen, and carried out on the downbeat.
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
		return 0.05
	end)
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
	for _, entry in results.Entries do
		local slot = self.slots[entry.Player]
		if not slot then
			continue
		end
		local state = slot.State
		local alive = ctx:IsAlive(entry.Player)
		local groove = if alive then state.Groove else slot.OutGroove
		if alive then
			entry.Rank = 1e6 + percent(groove) * 1000 + math.min(state.Score, 999999) / 1000
			entry.Survived = elapsed
			entry.ScoreText = `Last dancer! {percent(groove)}% groove • {state.Score} pts`
		else
			local out = slot.Out or 0
			entry.Rank = out + percent(groove) / 1000
			entry.Survived = out
			entry.ScoreText = `Cut at {math.floor(out)}s • {percent(groove)}% groove • {state.Score} pts`
		end
		entry.BestScore = state.Score
	end
	-- The one winner (ties settled by points, then the draw): nobody else shares first place.
	local winner = self:_winner()
	if winner then
		for _, entry in results.Entries do
			if entry.Player == winner then
				entry.Rank += 0.5
			end
		end
	end
	return results
end

return LastDancer

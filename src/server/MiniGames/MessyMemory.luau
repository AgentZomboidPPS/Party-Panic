-- Messy Memory (Reaction, 52s, 1-12 players). After "Messy Memory" (Mario Party 3, again in Mario
-- Party Superstars): everyone studies a shelf of toys for a few seconds, then mischief-makers burst
-- in with a puff of smoke and knock every toy off; you then have 30 seconds to put each toy back on
-- its own spot. When time is up the right spots are revealed one by one: most toys right wins.
--
-- The arena is a toy shop: twelve booths in a ring (always all twelve; empty ones stay shut), each
-- with the same cubby shelf (4 x 3 slots), a counter in front where knocked-off toys land, and a
-- curtain across its front. Eight toys (a teddy, a duck, a rocket, a robot, a ball, a top, a block
-- and a boat) sit in 8 of the 12 slots, the same layout in every booth, so a rival's shelf is worth
-- a PEEK. Your own CURTAIN hides your shelf from peekers; while it's shut your answers are locked,
-- and you can open it again to change them. When everyone still in the round has shut theirs, the
-- reveal starts early.
--
-- How it works: the server owns every toy's position (Logic/MessyMemory has the geometry and the
-- move rule). A booth's state is shared as "B<UserId>" ({ O = open, S = the owner's last move
-- number, P = each toy's position }); P is left out while the curtain is shut, so a shut booth's
-- toys never reach anyone's device. Clients send "Move" (move number, toy, target), "Curtain"
-- (open?) and "Peek" (whose booth: only to tell that player someone is peeking); every one is
-- checked (phase, types, ranges, an open curtain, the owner's own booth only, with ping leeway at
-- the end of the placing time). The round's phase is shared as "Phase" ({ N = name, T0, T1, ... });
-- clients animate the curtains, the smoke, the toys flying off and the reveal from it.
--
-- Bots (Bots/MessyMemory) recall each toy's spot with skill-based mistakes (usually a neighbouring
-- slot), place them at a human pace through ctx:BotAction, sometimes peek at an open rival booth and
-- copy what they see there (right or wrong), then shut their curtain. There are no hazards: the
-- mischief is a change of the shared positions that the server makes for bots and players alike.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.MessyMemory)

local MiniGame = require(script.Parent.Kit.MiniGame)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local MessyMemory = MiniGame.Define("MessyMemory", { Results = "Score" })

local WALL_RADIUS = 46
local FLOOR_RADIUS = 47
local LATE = 0.15 -- moves may still arrive this long (plus ping, up to 0.25 s) after placing ends

local rng = Random.new()

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local SPIN = CFrame.Angles(0, math.pi, 0) -- meshes face -Z; booth things face the player (+Z)

type Booth = {
	Index: number,
	Frame: CFrame,
	Positions: { number },
	Homes: { number }, -- each toy's counter spot after the mischief
	Open: boolean,
	Seq: number,
	LockedAt: number?,
	Left: boolean,
	Score: number,
}

local function upright(center: Vector3): CFrame
	return CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
end

function MessyMemory:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 30
	local center = ctx.Origin.Position
	self.center = center
	self.booths = {} :: { [Player]: Booth }
	self.phase = "Ready"
	self.phaseInfo = { N = "Ready" }

	-- The layout everyone studies: 8 of the 12 slots, one toy each.
	local slots = {}
	for slot = 1, Rules.SLOTS do
		table.insert(slots, slot)
	end
	for index = #slots, 2, -1 do
		local other = rng:NextInteger(1, index)
		slots[index], slots[other] = slots[other], slots[index]
	end
	self.answer = {} :: { number }
	for toy = 1, #Rules.TOYS do
		self.answer[toy] = slots[toy]
	end

	-- Booths: players spread round the ring (2 players face each other across it).
	local players = ctx:GetPlayers()
	local count = #players
	local owners = {}
	local spawns = {}
	local layout = {}
	for index, player in players do
		local ring = math.floor((index - 1) * Rules.BOOTHS / math.max(count, 1)) + 1
		owners[ring] = player
		local frame = Rules.BoothFrame(center, ring)
		self.booths[player] = {
			Index = ring,
			Frame = frame,
			Positions = table.clone(self.answer),
			Homes = {},
			Open = false,
			Seq = 0,
			LockedAt = nil,
			Left = false,
			Score = 0,
		}
		table.insert(spawns, self:_standFrame(frame))
		table.insert(layout, { User = player.UserId, I = ring })
		ctx:SetScoreText(player, "0/8")
	end
	self:_buildArena(center, owners)
	ctx:SpawnAll(spawns, true)

	for _, name in Rules.TOYS do
		ctx:ShareTemplate(name, MeshLibrary.Get(name))
	end
	ctx:ShareTemplate("MessyMemoryCurtain", MeshLibrary.Get("MessyMemoryCurtain"))
	ctx:ShareTemplate("MessyMemorySmoke", MeshLibrary.Get("MessyMemorySmoke"))
	ctx:SetSharedJSON("Layout", { Booths = layout, Center = { center.X, center.Y, center.Z } })
	for player in self.booths do
		self:_shareBooth(player)
	end
	self:_setPhase({ N = "Ready" })
	ctx:SetStatus("Watch the shelf when the curtain opens!")
end

-- Where a player stands in front of their booth, facing the shelf.
function MessyMemory:_standFrame(frame: CFrame): CFrame
	local stand = frame * Vector3.new(0, 0, Rules.STAND_Z)
	local look = frame * Vector3.new(0, 0, Rules.SHELF_Z)
	return CFrame.lookAt(stand + Vector3.new(0, 3, 0), Vector3.new(look.X, stand.Y + 3, look.Z))
end

-- A toy shop: a round wooden floor with a star rug, a ring of twelve booths, striped walls behind
-- them, and a toy chest overflowing with giant toys in the middle.
function MessyMemory:_buildArena(center: Vector3, owners: { [number]: Player })
	local ctx = self.context
	local arena = ctx.Arena
	-- The floor (drawn and solid: the only thing anyone stands on).
	Build.Part({
		Name = "ShopFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, FLOOR_RADIUS * 2, FLOOR_RADIUS * 2),
		CFrame = upright(center - Vector3.new(0, 1, 0)),
		Color = rgb(222, 170, 118),
		Material = Enum.Material.WoodPlanks,
		Parent = arena,
	})
	-- A round rug in the middle and a ring path in front of the booths.
	Build.Decor({
		Name = "Rug",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.06, 30, 30),
		CFrame = upright(center + Vector3.new(0, 0.29, 0)),
		Color = rgb(120, 200, 235),
		Material = Enum.Material.Fabric,
		Parent = arena,
	})
	Build.Decor({
		Name = "RugRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.06, 33, 33),
		CFrame = upright(center + Vector3.new(0, 0.13, 0)),
		Color = rgb(255, 255, 255),
		Material = Enum.Material.Fabric,
		Parent = arena,
	})
	for index = 0, 15 do
		local angle = index / 16 * math.pi * 2
		local at = center + Vector3.new(math.cos(angle) * 12.5, 0.44, math.sin(angle) * 12.5)
		Build.Decor({
			Name = "RugStar",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.04, 1.6, 1.6),
			CFrame = upright(at),
			Color = if index % 2 == 0 then rgb(255, 220, 90) else rgb(255, 140, 190),
			Material = Enum.Material.Fabric,
			Parent = arena,
		})
	end

	-- Booths.
	local stripe = { rgb(255, 120, 170), rgb(110, 200, 255), rgb(255, 200, 70), rgb(140, 220, 130) }
	for ring = 1, Rules.BOOTHS do
		local frame = Rules.BoothFrame(center, ring)
		local accent = stripe[(ring - 1) % #stripe + 1]
		MeshLibrary.Get("MessyMemoryBooth", {
			CFrame = frame * CFrame.new(0, 0, -3.5) * SPIN,
			Colors = { Awning = accent, Post = accent },
			Parent = arena,
		})
		MeshLibrary.Get("MessyMemoryShelf", {
			CFrame = frame * CFrame.new(0, 0, Rules.SHELF_Z) * SPIN,
			Parent = arena,
		})
		-- The name board on the awning.
		local owner = owners[ring]
		local board = Build.Decor({
			Name = "BoothSign",
			Size = Vector3.new(7, 1.4, 0.12),
			CFrame = frame * CFrame.new(0, 13.5, 0.87),
			Color = rgb(255, 250, 240),
			Material = Enum.Material.SmoothPlastic,
			Parent = arena,
		})
		Build.SurfaceText(board, Enum.NormalId.Back, if owner then owner.DisplayName else "CLOSED", {
			TextColor3 = if owner then rgb(90, 50, 120) else rgb(170, 150, 160),
			TextStrokeTransparency = 1,
			PixelsPerStud = 24,
			MaxDistance = 160,
		})
	end

	-- The shop's walls: pastel stripes with a cream trim, all round behind the booths.
	local panels = 32
	local width = WALL_RADIUS * 2 * math.pi / panels + 0.2
	for index = 0, panels - 1 do
		local angle = (index + 0.5) / panels * math.pi * 2
		local outward = Vector3.new(math.sin(angle), 0, math.cos(angle))
		-- Neighbouring panels overlap a little, so every other one sits a hair further out (no
		-- two faces in one plane: no flicker).
		local nudge = (index % 2) * 0.15
		local base = center + outward * (WALL_RADIUS + nudge)
		local frame = CFrame.lookAt(base, base - outward)
		Build.Decor({
			Name = "Wallpaper",
			Size = Vector3.new(width, 29.6, 1),
			CFrame = frame * CFrame.new(0, 15.2 + nudge, 0),
			Color = if index % 2 == 0 then rgb(255, 214, 228) else rgb(255, 240, 246),
			Material = Enum.Material.SmoothPlastic,
			Parent = arena,
		})
		Build.Decor({
			Name = "WallTrim",
			Size = Vector3.new(width + 0.3, 1.6, 1.6),
			CFrame = frame * CFrame.new(0, 30.4 + nudge, 0),
			Color = rgb(150, 110, 200),
			Material = Enum.Material.SmoothPlastic,
			Parent = arena,
		})
		Build.Decor({
			Name = "Skirting",
			Size = Vector3.new(width + 0.3, 1.6, 1.4),
			CFrame = frame * CFrame.new(0, 0.9 + nudge, -0.05),
			Color = rgb(150, 110, 200),
			Material = Enum.Material.SmoothPlastic,
			Parent = arena,
		})
	end

	-- The middle: an open toy chest with giant toys round it, balloons and gift boxes.
	MeshLibrary.Get("MessyMemoryToyBox", {
		CFrame = CFrame.new(center) * CFrame.Angles(0, math.rad(20), 0),
		Parent = arena,
	})
	local giants = {
		{ "MessyMemoryTeddy", 4.2, 0 },
		{ "MessyMemoryRocket", 4.4, 72 },
		{ "MessyMemoryBall", 3.4, 144 },
		{ "MessyMemoryDuck", 3.6, 216 },
		{ "MessyMemoryRobot", 3.8, 288 },
	}
	for _, giant in giants do
		local angle = math.rad(giant[3] + 36)
		local at = center + Vector3.new(math.cos(angle) * 9, 0.42, math.sin(angle) * 9)
		MeshLibrary.Get(giant[1], {
			Scale = giant[2],
			CFrame = CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z)) * SPIN,
			Parent = arena,
		})
	end
	local boxColors = { rgb(255, 120, 170), rgb(120, 200, 255), rgb(255, 210, 80), rgb(160, 120, 230) }
	for index = 0, 4 do
		local angle = math.rad(index * 72)
		local at = center + Vector3.new(math.cos(angle) * 15.5, 0.27, math.sin(angle) * 15.5)
		MeshLibrary.Get("GiftBox", {
			Scale = rng:NextNumber(0.35, 0.5),
			Colors = { Box = boxColors[index % #boxColors + 1] },
			CFrame = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			Parent = arena,
		})
	end
	local balloonColors = { rgb(255, 90, 120), rgb(255, 210, 70), rgb(90, 180, 255), rgb(140, 220, 120) }
	for index = 0, 5 do
		local angle = math.rad(index * 60 + 15)
		local at = center + Vector3.new(math.cos(angle) * 6, 9 + (index % 2) * 2.5, math.sin(angle) * 6)
		MeshLibrary.Get("Balloon", {
			Scale = 1.2,
			Colors = { Balloon = balloonColors[index % #balloonColors + 1] },
			CFrame = CFrame.new(at),
			Parent = arena,
		})
	end
end

function MessyMemory:_setPhase(info: { [string]: any })
	self.phase = info.N
	self.phaseInfo = info
	self.context:SetSharedJSON("Phase", info)
end

function MessyMemory:_shareBooth(player: Player)
	local booth = self.booths[player]
	if not booth then
		return
	end
	local visible = booth.Open or self.phase == "Reveal" or self.phase == "Done"
	self.context:SetSharedJSON("B" .. player.UserId, {
		O = booth.Open,
		S = booth.Seq,
		P = if visible then booth.Positions else nil,
		L = if booth.Left then true else nil,
	})
end

function MessyMemory:Start()
	local ctx = self.context
	for _, player in ctx:GetPlayers() do
		ctx:SetWalkSpeed(player, 0)
	end
	ctx.Hooks.CharacterReady = function(player)
		ctx:SetWalkSpeed(player, 0)
	end
	ctx.Hooks.Respawn = function(player)
		local booth = self.booths[player]
		return if booth then self:_standFrame(booth.Frame) else nil
	end
	ctx.Hooks.PlayerLeft = function(player)
		local booth = self.booths[player]
		if booth then
			booth.Left = true
			booth.Open = false
			self:_shareBooth(player)
		end
		self:_checkAllLocked()
	end

	ctx:OnAction("Move", function(player, seq, toy, target)
		self:_onMove(player, seq, toy, target)
	end, { Interval = 0.06 })
	ctx:OnAction("Curtain", function(player, open)
		self:_onCurtain(player, open)
	end, { Interval = 0.25 })
	ctx:OnAction("Peek", function(player, userId)
		self:_onPeek(player, userId)
	end, { Interval = 0.6 })

	-- 1. The curtains open: study the shelf.
	local now = ctx:Now()
	for player, booth in self.booths do
		booth.Open = true
		self:_shareBooth(player)
	end
	self:_setPhase({ N = "Study", T0 = now, T1 = now + Rules.STUDY })
	ctx:SetStatus("Remember where every toy goes!")

	-- 2. Mischief! Every toy is knocked onto the counter, in a jumble.
	ctx:Delay(Rules.STUDY, function()
		local t0 = ctx:Now()
		-- (The phase first, so clients see the toys fly off as the mischief, not as moves.)
		self:_setPhase({ N = "Mess", T0 = t0, T1 = t0 + Rules.MESS })
		for player, booth in self.booths do
			local spots = {}
			for spot = 1, #Rules.TOYS do
				table.insert(spots, spot)
			end
			for index = #spots, 2, -1 do
				local other = rng:NextInteger(1, index)
				spots[index], spots[other] = spots[other], spots[index]
			end
			for toy = 1, #Rules.TOYS do
				booth.Homes[toy] = spots[toy]
				booth.Positions[toy] = Rules.TrayPos(spots[toy])
			end
			self:_shareBooth(player)
		end
		ctx:SetStatus("Mischief! The toys got knocked off!")
		ctx:Sound("HazardWarning")
	end)

	-- 3. Put them back.
	ctx:Delay(Rules.STUDY + Rules.MESS, function()
		local t0 = ctx:Now()
		self.placeStart = t0
		self:_setPhase({ N = "Place", T0 = t0, T1 = t0 + Rules.PLACE })
		ctx:SetStatus("Put every toy back on its spot!")
		ctx:Delay(Rules.PLACE, function()
			self:_startReveal()
		end)
	end)
end

function MessyMemory:_placing(player: Player): boolean
	if self.phase ~= "Place" then
		return false
	end
	local info = self.phaseInfo
	local ok, ping = pcall(function()
		return (player :: any):GetNetworkPing()
	end)
	local lag = if ok and type(ping) == "number" then math.clamp(ping, 0, 0.25) else 0.15
	return self.context:Now() <= info.T1 + lag + LATE
end

local function wholeNumber(value: any, low: number, high: number): number?
	if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < low or value > high then
		return nil
	end
	return value
end

function MessyMemory:_onMove(player: Player, seq: any, toy: any, target: any)
	local booth = self.booths[player]
	if not booth or booth.Left or not booth.Open then
		return
	end
	-- The reveal starts the moment placing ends: a move that was already on its way (ping) still
	-- lands for a moment (lateOk), before any toy is scored.
	if not self:_placing(player) and not (self.phase == "Reveal" and self.lateOk) then
		return
	end
	local n = wholeNumber(seq, 1, 1e6)
	local t = wholeNumber(toy, 1, #Rules.TOYS)
	local to = wholeNumber(target, 1, Rules.SLOTS + #Rules.TOYS)
	if not n or not t or not to then
		return
	end
	if n <= booth.Seq then
		return -- an old move arriving late (the device already moved on)
	end
	booth.Seq = n
	Rules.Move(booth.Positions, booth.Homes, t, to)
	self:_shareBooth(player)
end

function MessyMemory:_onCurtain(player: Player, open: any)
	local booth = self.booths[player]
	if type(open) ~= "boolean" or not booth or booth.Left or self.phase ~= "Place" then
		return
	end
	if booth.Open == open then
		return
	end
	booth.Open = open
	booth.LockedAt = if open then nil else self.context:Now()
	self:_shareBooth(player)
	self:_checkAllLocked()
end

function MessyMemory:_onPeek(player: Player, userId: any)
	if self.phase ~= "Place" or type(userId) ~= "number" or userId == player.UserId then
		return
	end
	for other, booth in self.booths do
		if other.UserId == userId and booth.Open and not booth.Left then
			self.context:Fire(other, "Peeked", player.UserId)
			return
		end
	end
end

-- Everyone still here has shut their curtain: no need to wait out the clock.
function MessyMemory:_checkAllLocked()
	if self.phase ~= "Place" or self.earlyReveal then
		return
	end
	for player, booth in self.booths do
		if player.Parent and not booth.Left and booth.Open then
			return
		end
	end
	self.earlyReveal = true
	self.context:SetStatus("Everyone's locked in!")
	self.context:Delay(Rules.ALL_LOCKED_GRACE, function()
		self:_startReveal()
	end)
end

-- The right spots, one toy at a time (top-left slot first); each right toy scores as it's shown.
function MessyMemory:_startReveal()
	local ctx = self.context
	if self.phase ~= "Place" then
		return
	end
	local order = {}
	for toy = 1, #Rules.TOYS do
		table.insert(order, toy)
	end
	table.sort(order, function(a, b)
		return self.answer[a] < self.answer[b]
	end)
	local t0 = ctx:Now() + 0.8
	self:_setPhase({
		N = "Reveal",
		T0 = t0,
		Step = Rules.REVEAL_STEP,
		Order = order,
		Answer = self.answer,
	})
	-- Moves already on their way when the clock ran out still land (ping leeway), for a moment.
	self.lateOk = true
	ctx:Delay(0.4, function()
		self.lateOk = false
		for player in self.booths do
			self:_shareBooth(player) -- every shelf on show, with its final answers
		end
	end)
	for player in self.booths do
		self:_shareBooth(player)
	end
	ctx:SetStatus("Let's see who remembered...")
	for step, toy in order do
		ctx:Delay(t0 - ctx:Now() + (step - 1) * Rules.REVEAL_STEP, function()
			for player, booth in self.booths do
				if booth.Positions[toy] == self.answer[toy] then
					booth.Score += 1
					ctx:AddScore(player, 1)
				end
				ctx:SetScoreText(player, `{booth.Score}/{#Rules.TOYS}`)
			end
		end)
	end
	local finish = 0.8 + #order * Rules.REVEAL_STEP + Rules.REVEAL_HOLD
	ctx:Delay(finish, function()
		self.phase = "Done"
		ctx:End("Revealed")
	end)
end

-- Bots: what a bot sees when it peeks at a rival (nil if that booth is shut).
function MessyMemory:OpenBooths(except: Player): { { Player: Player, Positions: { number } } }
	local list = {}
	for player, booth in self.booths do
		if player ~= except and booth.Open and not booth.Left and player.Parent then
			table.insert(list, { Player = player, Positions = booth.Positions })
		end
	end
	return list
end

-- Most toys right wins; between equal scores, whoever shut their curtain sooner.
function MessyMemory:GetResults()
	local ctx = self.context
	local entries = {}
	for _, player in ctx:GetPlayers() do
		local booth = self.booths[player]
		if not player.Parent or not booth then
			continue
		end
		local correct = Rules.Correct(booth.Positions, self.answer)
		local bonus = 0
		if booth.LockedAt and self.placeStart then
			bonus = math.clamp(1 - (booth.LockedAt - self.placeStart) / Rules.PLACE, 0, 1) * 0.9
		end
		table.insert(entries, {
			Player = player,
			Rank = correct + bonus,
			ScoreText = `{correct}/{#Rules.TOYS} right`,
			BestScore = correct,
		})
	end
	return { Entries = entries }
end

return MessyMemory

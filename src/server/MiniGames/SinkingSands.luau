-- Sinking Sands (Versus, 45s, 1 to 12 players). After Mario Party's "Quicksand Cache": a desert
-- mesa whose middle is a giant quicksand funnel draining into a sinkhole. Coins, gems, coin bags and
-- the odd GOLDEN IDOL rain onto the sand and ride the swirl down into the hole.
--
--   DIVERS (most players) run on the sand and grab treasure (+1 coin, +3 gem, +5 bag, +10 idol). The
--   sand drags them round and in; whoever slips into the sinkhole is spat back out at the rim a
--   moment later (and the Sand Kings score +5).
--   SAND KINGS (about one in four, on thrones round the rim) steer the swirl: SWIRL flips the spin
--   and whips it faster, PULL drains the funnel hard for two seconds. Every treasure that sinks goes
--   to the Kings. With nobody to be a King (a solo round) the sand plays King by itself.
-- The team with the bigger haul wins.
--
-- How it works: the sand is a shared schedule of constant-flow segments (Logic/SandSwirl), and a
-- treasure is just (radius, angle, time) on it, so every client draws each treasure on the same
-- spiral the server judges grabs on, without streaming positions. Players' devices drag their own
-- characters with the sand (smooth); the server drags bots the same way (hazard parity) and checks
-- everyone against the sinkhole by position.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SandSwirl = require(ReplicatedStorage.Shared.Logic.SandSwirl)
local Teams = require(ReplicatedStorage.Shared.Teams)

local MiniGame = require(script.Parent.Kit.MiniGame)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)

local SinkingSands = MiniGame.Define("SinkingSands", { Results = "Team" })
SinkingSands.Swirl = SandSwirl -- the flow math, for the test bot

local KINGS, DIVERS = "SandKings", "Divers"

-- Treasure kinds: value, how often (weight), how fast the sand carries it (heavier = slower), grab
-- reach (studs, measured from the player's middle) and the prop the client draws.
SinkingSands.Kinds = {
	{ Name = "Coin", Value = 1, Weight = 58, Factor = 1.5, Reach = 3.4, Prop = "SandCoin" },
	{ Name = "Gem", Value = 3, Weight = 27, Factor = 1.4, Reach = 3.4, Prop = "SandGem" },
	{ Name = "Bag", Value = 5, Weight = 15, Factor = 1.2, Reach = 3.7, Prop = "CoinBag" },
	{ Name = "Idol", Value = 10, Weight = 0, Factor = 0.95, Reach = 3.9, Prop = "GoldenIdol" },
}
local IDOL = 4

local PLAZA = 78 -- radius of the mesa top (the meshes use the same numbers)
local MESA = 40 -- mesa top above the desert floor
local THRONE_R = SandSwirl.RIM + 9
local DIVER_R = SandSwirl.RIM + 3.5
local HOLD_DEPTH = 22 -- the dark pocket down the sinkhole where gulped divers wait
local GULP_TIME = 1.8
local GULP_BONUS = 5
local FALL_TIME = 1.1 -- treasure falls from the sky this long before it lands
local MAX_ITEMS = 24
local SWIRL_COOLDOWN, PULL_COOLDOWN = 3, 5 -- with three Kings; fewer Kings recharge faster
local FLIP_GAP = 1.4 -- the spin never reverses twice within this long
local HIP = 3 -- a character's root above the ground

local rng = Random.new()

type Item = {
	Id: number,
	Kind: number,
	R: number,
	A: number,
	T: number,
}

local function round(value: number, places: number): number
	local k = 10 ^ places
	return math.floor(value * k + 0.5) / k
end

local function isBot(player: any): boolean
	return BotRegistry.IsBot(player)
end

function SinkingSands:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 26
	local center = ctx.Origin.Position
	self.center = center
	ctx.Arena:SetAttribute("Center", center)
	self.items = {} :: { [number]: Item }
	self.nextId = 0
	self.kings = {} :: { any }
	self.thrones = {} :: { [any]: { CFrame: CFrame, Seat: Seat, Angle: number } }
	self.gulped = {} :: { [any]: number }
	self.lastFlip = -math.huge
	self.dirty = true
	self.lastPublish = 0
	self.idols = 0

	-- Teams: about one Sand King per four players (none when playing alone).
	local players = ctx:GetPlayers()
	for index = #players, 2, -1 do
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local kingCount = if #players >= 2 then math.clamp(math.floor(#players / 4 + 0.5), 1, 3) else 0
	for index, player in players do
		if index <= kingCount then
			table.insert(self.kings, player)
			ctx:SetTeam(player, KINGS)
			ctx:SetPlayerShared(player, "Role", "King")
		else
			ctx:SetTeam(player, DIVERS)
			ctx:SetPlayerShared(player, "Role", "Diver")
		end
	end

	self:_buildArena(kingCount)

	ctx.Hooks.Respawn = function(player)
		if self.thrones[player] then
			return self.thrones[player].CFrame * CFrame.new(0, 2.6, 0.5)
		end
		return self:_rimSpot(rng:NextNumber(0, math.pi * 2))
	end
	ctx.Hooks.CharacterReady = function(player, character)
		if self.thrones[player] then
			-- A King who reset comes back on the throne, still frozen.
			ctx:Freeze(player, true)
			task.defer(function()
				self:_seatKing(player, character)
			end)
		end
	end
	ctx.Hooks.PlayerLeft = function(player)
		self.gulped[player] = nil
		local index = table.find(self.kings, player)
		if index then
			table.remove(self.kings, index)
			if #self.kings == 0 then
				ctx:Announce("The Sand Kings left: the sand plays on by itself!", "info", 3)
			end
		elseif #self.kings > 0 and ctx:IsRunning() and #ctx:GetPlayers() - #self.kings <= 0 then
			ctx:Announce("The Divers left!", "info", 2)
			ctx:End("TeamGone")
		end
	end

	-- Thrones for the Kings, Divers spread round the rim between them.
	local spawns = {}
	local divers = #players - kingCount
	for index, player in players do
		if index <= kingCount then
			spawns[index] = self.thrones[player].CFrame * CFrame.new(0, 2.6, 0.5)
		else
			local k = index - kingCount
			spawns[index] = self:_rimSpot(self.kingOffset + (k - 0.5) / math.max(1, divers) * math.pi * 2)
		end
	end
	-- SpawnAll cycles through points in GetPlayers() order, so spawn one by one instead.
	local done = 0
	for index, player in players do
		task.spawn(function()
			ctx:SpawnPlayer(player, spawns[index], true)
			done += 1
		end)
	end
	local deadline = os.clock() + 8
	while done < #players and os.clock() < deadline do
		task.wait(0.1)
	end
	self:_pruneKings()

	ctx:SetStatus("Divers: grab the treasure! Sand Kings: sink it!")
	self:_publish(ctx:Now())
end

-- Kings whose character never spawned (they left the round) play no part: the sand takes over.
function SinkingSands:_pruneKings()
	for index = #self.kings, 1, -1 do
		if not self.context:State(self.kings[index]) then
			table.remove(self.kings, index)
		end
	end
end

-- A spot on the mesa just outside the funnel, facing the hole.
function SinkingSands:_rimSpot(angle: number): CFrame
	local center = self.center
	local position = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * DIVER_R
	return CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
end

function SinkingSands:_buildArena(kingCount: number)
	local ctx = self.context
	local center = self.center
	local arena = ctx.Arena
	local sandColor = Color3.fromRGB(238, 198, 128)

	-- The desert floor out to the horizon and soft dunes far away.
	local floorY = center.Y - MESA
	Build.Decor({
		Name = "Desert",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 1400, 1400),
		CFrame = CFrame.new(center.X, floorY - 1, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(226, 178, 112),
		Material = Enum.Material.Sand,
		Parent = arena,
	})
	for index = 1, 14 do
		local angle = index / 14 * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local distance = rng:NextNumber(260, 420)
		local width = rng:NextNumber(150, 300)
		local dune = Build.Decor({
			Name = "Dune",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(width, width * rng:NextNumber(0.1, 0.16), width * rng:NextNumber(0.45, 0.7)),
			CFrame = CFrame.new(
				center.X + math.cos(angle) * distance,
				floorY - 4,
				center.Z + math.sin(angle) * distance
			) * CFrame.Angles(0, -angle + math.pi / 2, 0),
			Color = Color3.fromRGB(232, 176, 104):Lerp(Color3.fromRGB(246, 206, 140), rng:NextNumber()),
			Material = Enum.Material.Sand,
			Parent = arena,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = dune
	end

	-- The mesa and its funnel (one mesh), and the swirl streaks the clients turn.
	local pit =
		MeshLibrary.Get("SandPit", { CFrame = CFrame.new(center - Vector3.new(0, MESA + 0.3, 0)), Parent = arena })
	local swirl = MeshLibrary.Get("SandSwirl", { CFrame = CFrame.new(center - Vector3.new(0, 20, 0)), Parent = arena })
	swirl.Name = "SandSwirl"
	local showFloor = MeshLibrary.Source("SandPit") == "Fallback"
	pit.Name = "SandPit"

	-- Walkable collision on the same profile as the mesh: tilted slabs in rings round the funnel and
	-- a flat ring for the mesa top. The sinkhole itself has no floor.
	local floor = Build.Folder("Floor", arena)
	local sectors = 28
	local edges = { SandSwirl.HOLE, 6.5, 8.5, 11, 14, 17.5, 21.5, 26, 30, SandSwirl.RIM }
	local function slab(cframe: CFrame, size: Vector3)
		Build.Part({
			Name = "Sand",
			Size = size,
			CFrame = cframe,
			Color = sandColor,
			Material = Enum.Material.Sand,
			Transparency = if showFloor then 0 else 1,
			CastShadow = false,
			CanTouch = false,
			Parent = floor,
		})
	end
	for sector = 0, sectors - 1 do
		local angle = (sector + 0.5) / sectors * math.pi * 2
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local look = CFrame.lookAt(Vector3.zero, outward)
		for band = 1, #edges - 1 do
			local r0, r1 = edges[band], edges[band + 1]
			local h0, h1 = SandSwirl.Height(r0), SandSwirl.Height(r1)
			local run = r1 - r0
			local rise = h1 - h0
			local length = math.sqrt(run * run + rise * rise) + 0.3
			local width = 2 * r1 * math.sin(math.pi / sectors) + 0.4
			local mid = center + outward * (r0 + r1) / 2 + Vector3.new(0, (h0 + h1) / 2, 0)
			local tilt = math.atan2(rise, run)
			local cframe = CFrame.new(mid) * look.Rotation * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, -0.5, 0)
			slab(cframe, Vector3.new(width, 1, length))
		end
		-- The mesa top, from the rim to the cliffs.
		local width = 2 * PLAZA * math.sin(math.pi / sectors) + 0.6
		local mid = center + outward * (SandSwirl.RIM + PLAZA) / 2
		-- (alternate sectors sit a hair lower, so where neighbours overlap they never z-fight)
		slab(
			CFrame.new(mid - Vector3.new(0, 0.5 + (sector % 2) * 0.06, 0)) * look.Rotation,
			Vector3.new(width, 1, PLAZA - SandSwirl.RIM + 0.4)
		)
		-- An invisible wall at the cliff edge so nobody walks off the mesa.
		Build.Barrier({
			Name = "Edge",
			Size = Vector3.new(width, 12, 1),
			CFrame = CFrame.new(center + outward * (PLAZA - 1.5) + Vector3.new(0, 6, 0)) * look.Rotation,
			Parent = floor,
		})
	end
	-- Where gulped divers wait for a moment, deep in the dark throat.
	Build.Barrier({
		Name = "Pocket",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, SandSwirl.HOLE * 2 + 2, SandSwirl.HOLE * 2 + 2),
		CFrame = CFrame.new(center - Vector3.new(0, HOLD_DEPTH + 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = floor,
	})

	-- Sand pouring into the sinkhole and dust blowing off the mesa (ambient: reduced-effects aware).
	local hole = Build.Decor({
		Name = "HoleDust",
		Size = Vector3.new(SandSwirl.HOLE * 1.6, 1, SandSwirl.HOLE * 1.6),
		CFrame = CFrame.new(center - Vector3.new(0, SandSwirl.DEPTH + 1, 0)),
		Transparency = 1,
		Parent = arena,
	})
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(240, 204, 140), Color3.fromRGB(200, 150, 96))
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 6) })
	spray.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.5, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	spray.Lifetime = NumberRange.new(1.4, 2.4)
	spray.Rate = 9
	spray.Speed = NumberRange.new(2, 4)
	spray.SpreadAngle = Vector2.new(30, 30)
	spray.Acceleration = Vector3.new(0, -2, 0)
	spray.RotSpeed = NumberRange.new(-60, 60)
	spray.LightEmission = 0.1
	self:_ambient(spray, hole)
	for index = 1, 3 do
		local angle = index / 3 * math.pi * 2
		local source = Build.Decor({
			Name = "Wind",
			Size = Vector3.new(40, 1, 40),
			CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * 55, 1, math.sin(angle) * 55)),
			Transparency = 1,
			Parent = arena,
		})
		local dust = Instance.new("ParticleEmitter")
		dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
		dust.Color = ColorSequence.new(Color3.fromRGB(246, 214, 160))
		dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
		dust.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.82),
			NumberSequenceKeypoint.new(1, 1),
		})
		dust.Lifetime = NumberRange.new(3, 5)
		dust.Rate = 3
		dust.Speed = NumberRange.new(4, 7)
		dust.EmissionDirection = Enum.NormalId.Top
		dust.SpreadAngle = Vector2.new(70, 10)
		dust.Acceleration = Vector3.new(5, 0, 2)
		self:_ambient(dust, source)
	end

	-- Treasure models the clients copy.
	for _, kind in SinkingSands.Kinds do
		ctx:ShareTemplate(kind.Prop, MeshLibrary.Get(kind.Prop))
	end

	-- Thrones round the rim (evenly, starting at a random angle).
	self.kingOffset = rng:NextNumber(0, math.pi * 2)
	local kingColor = Teams.Colors.SandKings or Color3.fromRGB(230, 170, 70)
	for index, king in self.kings do
		local angle = self.kingOffset + (index - 1) / math.max(1, kingCount) * math.pi * 2
		local position = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * THRONE_R
		local cframe = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
		MeshLibrary.Get("SandThrone", {
			CFrame = cframe,
			Colors = { Cushion = kingColor:Lerp(Color3.fromRGB(190, 40, 40), 0.5) },
			Parent = arena,
		})
		local seat = Instance.new("Seat")
		seat.Name = "ThroneSeat"
		seat.Size = Vector3.new(3, 0.6, 2.6)
		seat.CFrame = cframe * CFrame.new(0, 3.2, 0.5)
		seat.Anchored = true
		seat.Transparency = 1
		seat.CanTouch = false
		seat.Parent = arena
		self.thrones[king] = { CFrame = cframe, Seat = seat, Angle = angle }
	end

	-- Desert dressing on the mesa top (clear of thrones and spawns) and below the cliffs.
	local placed = {}
	local function clear(position: Vector3, gap: number): boolean
		for _, other in placed do
			if (other - position).Magnitude < gap then
				return false
			end
		end
		for _, throne in self.thrones do
			if (throne.CFrame.Position - position).Magnitude < 12 then
				return false
			end
		end
		return true
	end
	local function scatter(prop: string, count: number, r0: number, r1: number, y: number, scale: { number })
		local tries = 0
		while count > 0 and tries < 80 do
			tries += 1
			local angle = rng:NextNumber(0, math.pi * 2)
			local radius = rng:NextNumber(r0, r1)
			local position = center + Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
			if clear(position, 11) then
				table.insert(placed, position)
				MeshLibrary.Get(prop, {
					CFrame = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
					Scale = rng:NextNumber(scale[1], scale[2]),
					Parent = arena,
				})
				count -= 1
			end
		end
	end
	scatter("SandRuin", 6, SandSwirl.RIM + 18, PLAZA - 8, 0, { 0.9, 1.3 })
	scatter("Cactus", 9, SandSwirl.RIM + 14, PLAZA - 6, 0, { 0.7, 1.1 })
	scatter("Cactus", 10, PLAZA + 25, 190, -MESA, { 1.2, 2 })
	scatter("SandRuin", 5, PLAZA + 30, 170, -MESA, { 1.6, 2.6 })
end

function SinkingSands:_ambient(emitter: ParticleEmitter, parent: Instance)
	emitter.Parent = parent
	CollectionService:AddTag(emitter, "PP_Ambient")
end

-- Sits a King on their throne with a crown on, and keeps them there.
function SinkingSands:_seatKing(player: any, character: Model)
	local ctx = self.context
	local throne = self.thrones[player]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head") :: BasePart?
	if not throne or not humanoid then
		return
	end
	if head and not character:FindFirstChild("SandCrown") then
		local crown = MeshLibrary.Get("SandCrown")
		local root = MeshLibrary.Assemble(crown, true)
		crown:PivotTo(head.CFrame * CFrame.new(0, head.Size.Y / 2 - 0.15, 0))
		Build.Weld(head, root)
		crown.Parent = character
		ctx:Track(crown)
	end
	if throne.Seat.Parent then
		pcall(throne.Seat.Sit, throne.Seat, humanoid)
	end
end

-- Kings stay on their thrones: one who hopped off is sat back down, one who got away is respawned.
function SinkingSands:_keepKingsSeated()
	local ctx = self.context
	for _, king in self.kings do
		local throne = self.thrones[king]
		local character, humanoid, root = ctx:GetCharacter(king)
		if not throne or not character or not humanoid or not root or not ctx:IsAlive(king) then
			continue
		end
		local seat = throne.Seat.Position
		if Vector2.new(root.Position.X - seat.X, root.Position.Z - seat.Z).Magnitude > 6 then
			ctx:Respawn(king)
			ctx:Freeze(king, true)
		elseif humanoid.SeatPart ~= throne.Seat then
			ctx:Freeze(king, true)
			self:_seatKing(king, character)
		end
	end
end

-- Treasure ----------------------------------------------------------------------------------------

-- Where a treasure is at server time `t`: radius, angle and the time it reached the hole (if it did).
function SinkingSands:ItemPolar(item: Item, t: number): (number, number, number?)
	if t <= item.T then
		return item.R, item.A, nil
	end
	return SandSwirl.Advance(
		self.segments,
		item.R,
		item.A,
		item.T,
		t,
		SinkingSands.Kinds[item.Kind].Factor,
		SandSwirl.TREASURE_DRAIN
	)
end

-- The treasure's spot on the sand at `t` (world space).
function SinkingSands:ItemPosition(item: Item, t: number): Vector3
	local r, a = self:ItemPolar(item, t)
	local x, z = SandSwirl.ToXZ(r, a)
	return self.center + Vector3.new(x, SandSwirl.Height(r), z)
end

function SinkingSands:_spawnItem(kind: number, radius: number?)
	local ctx = self.context
	self.nextId += 1
	local now = ctx:Now()
	local item = {
		Id = self.nextId,
		Kind = kind,
		R = round(radius or rng:NextNumber(13, SandSwirl.RIM - 3), 3),
		A = round(rng:NextNumber(-math.pi, math.pi), 4),
		T = round(now + FALL_TIME, 3),
	}
	self.items[item.Id] = item
	self.dirty = true
end

local function pickKind(): number
	local total = 0
	for _, kind in SinkingSands.Kinds do
		total += kind.Weight
	end
	local roll = rng:NextNumber(0, total)
	for index, kind in SinkingSands.Kinds do
		roll -= kind.Weight
		if roll <= 0 and kind.Weight > 0 then
			return index
		end
	end
	return 1
end

-- Rebases every treasure onto `now` (same spot, fresh start time) and shares the sand: the flow
-- schedule plus the treasure, in one value so clients never pair a treasure with the wrong flow.
function SinkingSands:_publish(now: number)
	if self.segments then
		for _, item in self.items do
			if item.T < now then
				local r, a, sunk = self:ItemPolar(item, now)
				if not sunk then
					item.R, item.A, item.T = round(r, 3), round(a, 4), round(now, 3)
				end
			end
		end
	end
	self.segments = SandSwirl.Build(self.effects or self:_effects(), now - 1.5, 8)
	local flow = {}
	for _, segment in self.segments do
		table.insert(flow, { segment.T, segment.S, segment.V })
	end
	local items = {}
	for _, item in self.items do
		table.insert(items, { item.Id, item.Kind, item.R, item.A, item.T })
	end
	self.context:SetSharedJSON("Sand", { F = flow, I = items })
	self.dirty = false
	self.lastPublish = now
end

function SinkingSands:_effects()
	local ctx = self.context
	self.effects = {
		Start = if ctx.StartServerTime > 0 then ctx.StartServerTime else ctx:Now() + 10,
		Length = ctx.Definition.Duration or 45,
		Flips = {},
		Surges = {},
		Pulls = {},
	}
	return self.effects
end

-- Powers -----------------------------------------------------------------------------------------

function SinkingSands:_swirl(byUserId: number?)
	local ctx = self.context
	local start = SandSwirl.EffectStart(ctx:Now())
	local effects = self.effects or self:_effects()
	local flipped = start - self.lastFlip >= FLIP_GAP
	if flipped then
		self.lastFlip = start
		table.insert(effects.Flips, start)
	end
	table.insert(effects.Surges, start)
	self.dirty = true
	ctx:Fire(nil, "Power", "SWIRL", start, byUserId or 0, flipped)
end

function SinkingSands:_pull(byUserId: number?)
	local ctx = self.context
	local start = SandSwirl.EffectStart(ctx:Now())
	local effects = self.effects or self:_effects()
	table.insert(effects.Pulls, start)
	self.dirty = true
	ctx:Fire(nil, "Power", "PULL", start, byUserId or 0, false)
end

-- Cooldowns for this many Kings: a lone King has to keep the sand busy by themself.
function SinkingSands:Cooldowns(): (number, number)
	local share = math.clamp(#self.kings, 1, 3) / 3
	return SWIRL_COOLDOWN * (0.55 + 0.45 * share), PULL_COOLDOWN * (0.6 + 0.4 * share)
end

function SinkingSands:IsKing(player: any): boolean
	return table.find(self.kings, player) ~= nil
end

-- Scoring ----------------------------------------------------------------------------------------

function SinkingSands:_scoreKings(amount: number)
	local ctx = self.context
	ctx:AddTeamScore(KINGS, amount)
	-- Each King's own score is their share of the haul (the team total is what wins).
	local share = math.max(1, math.round(amount / math.max(1, #self.kings)))
	for _, king in self.kings do
		ctx:AddScore(king, share)
	end
end

function SinkingSands:_gulp(player: any)
	local ctx = self.context
	if self.gulped[player] then
		return
	end
	self.gulped[player] = os.clock()
	local character = ctx:GetCharacter(player)
	if character then
		character:PivotTo(CFrame.new(self.center - Vector3.new(0, HOLD_DEPTH - HIP, 0)))
	end
	ctx:Freeze(player, true)
	self:_scoreKings(GULP_BONUS)
	ctx:Fire(nil, "Gulp", player.UserId)
	ctx:Delay(GULP_TIME, function()
		self.gulped[player] = nil
		if ctx:IsAlive(player) then
			ctx:Respawn(player)
			ctx:Freeze(player, false)
		end
	end)
end

function SinkingSands:IsGulped(player: any): boolean
	return self.gulped[player] ~= nil
end

-- At the buzzer, anyone still down the hole comes back up for the podium.
function SinkingSands:Stop()
	local ctx = self.context
	for player in self.gulped do
		self.gulped[player] = nil
		ctx:Respawn(player)
		ctx:Freeze(player, false)
	end
end

-- Team results with readable names; Kings' personal bests aren't counted (they share one haul).
function SinkingSands:GetResults()
	local results = self.context:TeamResults()
	for _, entry in results.Entries do
		local state = self.context:State(entry.Player)
		local mine = if state then state.Score else 0
		if entry.Team == KINGS then
			entry.ScoreText = `Sand Kings {entry.Rank}`
			entry.BestScore = nil
		else
			entry.ScoreText = `Divers {entry.Rank} • you {mine}`
		end
	end
	return results
end

function SinkingSands:Start()
	local ctx = self.context
	self:_pruneKings()
	self:_effects()
	ctx:AddTeamScore(DIVERS, 0)
	ctx:AddTeamScore(KINGS, 0)
	self:_publish(ctx:Now())
	for _, king in self.kings do
		ctx:Freeze(king, true)
		local character = ctx:GetCharacter(king)
		if character then
			self:_seatKing(king, character)
		end
	end

	-- The Kings' powers (cooldowns are the server's; the client only shows them).
	local ready: { [any]: { Swirl: number, Pull: number } } = {}
	local function readyFor(player)
		ready[player] = ready[player] or { Swirl = 0, Pull = 0 }
		return ready[player]
	end
	ctx:OnAction("Swirl", function(player)
		if not self:IsKing(player) then
			return
		end
		local cool = readyFor(player)
		local now = ctx:Now()
		if now < cool.Swirl - 0.1 then
			return
		end
		local length = self:Cooldowns()
		cool.Swirl = now + length
		ctx:SetPlayerShared(player, "SwirlLength", length)
		ctx:SetPlayerShared(player, "SwirlAt", cool.Swirl)
		self:_swirl(player.UserId)
	end, { Interval = 0.25 })
	ctx:OnAction("Pull", function(player)
		if not self:IsKing(player) then
			return
		end
		local cool = readyFor(player)
		local now = ctx:Now()
		if now < cool.Pull - 0.1 then
			return
		end
		local _, length = self:Cooldowns()
		cool.Pull = now + length
		ctx:SetPlayerShared(player, "PullLength", length)
		ctx:SetPlayerShared(player, "PullAt", cool.Pull)
		self:_pull(player.UserId)
	end, { Interval = 0.25 })

	-- With no Kings left the sand plays by itself.
	local nextAuto = os.clock() + 4
	local nextAutoPull = os.clock() + 9
	ctx:Loop(function()
		self:_keepKingsSeated()
		if #self.kings == 0 then
			local now = os.clock()
			if now >= nextAuto then
				nextAuto = now + rng:NextNumber(4.5, 7.5)
				self:_swirl(nil)
			end
			if now >= nextAutoPull then
				nextAutoPull = now + rng:NextNumber(7, 10)
				self:_pull(nil)
			end
		end
		return 0.5
	end)

	-- Treasure rains in, quicker with more divers; a GOLDEN IDOL halfway (and late in big games).
	ctx:Loop(function()
		local divers = #ctx:GetPlayers() - #self.kings
		local count = 0
		for _ in self.items do
			count += 1
		end
		local progress = ctx:Progress()
		local idolsDue = if progress >= 0.8 and divers >= 6 then 2 elseif progress >= 0.42 then 1 else 0
		if self.idols < idolsDue then
			self.idols += 1
			self:_spawnItem(IDOL, SandSwirl.RIM - 4)
			ctx:Announce("THE GOLDEN IDOL! +10", "reward", 2.5)
		elseif count < MAX_ITEMS then
			self:_spawnItem(pickKind())
		end
		return math.clamp(2 / (0.5 + 0.28 * math.max(1, divers)), 0.45, 2) * rng:NextNumber(0.8, 1.2)
	end)

	-- Grabs, sinks and the sinkhole, ten times a second; the sand shared at least once a second.
	local accumulator = 0
	local physics = RunService:IsRunning()
	ctx:Heartbeat(function(dt)
		local now = ctx:Now()
		self:_dragBots(dt, now, physics)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			self:_judge(now)
		end
		if self.dirty and now - self.lastPublish > 0.1 or now - self.lastPublish > 1 then
			self:_publish(now)
		end
	end)
end

-- Bots are moved by the server, so the sand drags them here exactly as each player's device drags
-- its own character (same flow, same numbers).
function SinkingSands:_dragBots(dt: number, now: number, physics: boolean)
	local ctx = self.context
	local center = self.center
	for _, player in ctx:GetAlivePlayers() do
		if not isBot(player) or self.gulped[player] or self:IsKing(player) then
			continue
		end
		local _, humanoid, root = ctx:GetCharacter(player)
		if not root or not humanoid then
			continue
		end
		local position = root.Position
		local offset = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
		local r = offset.Magnitude
		local airborne = if physics
			then humanoid.FloorMaterial == Enum.Material.Air
			else (player :: any).JumpStart ~= nil
		if r < 0.01 then
			continue
		end
		local inward, spin = SandSwirl.WalkerFlow(self.segments, r, now)
		local k = if airborne then SandSwirl.AIR_DRAG else 1
		local u = offset / r
		local move = (-u * inward + Vector3.new(-u.Z, 0, u.X) * spin) * dt * k
		if physics then
			if move.Magnitude > 0 then
				root.CFrame += move
			end
		elseif airborne then
			-- Mid-hop on the test servers: the bot service owns the height, the sand still drags.
			root.CFrame += Vector3.new(move.X, 0, move.Z)
		else
			-- No physics on the test servers: keep the bot on the sand's surface too.
			local after = offset + move
			local y = center.Y + SandSwirl.Height(after.Magnitude) + HIP
			if r > SandSwirl.RIM + 1 and move.Magnitude == 0 and math.abs(position.Y - y) < 0.05 then
				continue
			end
			root.CFrame += Vector3.new(move.X, y - position.Y, move.Z)
		end
	end
end

function SinkingSands:_judge(now: number)
	local ctx = self.context
	local center = self.center
	-- Divers who are on the sand (and where).
	local divers = {}
	for _, player in ctx:GetAlivePlayers() do
		if self:IsKing(player) or self.gulped[player] then
			continue
		end
		local _, _, root = ctx:GetCharacter(player)
		if not root then
			continue
		end
		local position = root.Position
		local r = Vector2.new(position.X - center.X, position.Z - center.Z).Magnitude
		-- In the hole: over it and low, or anywhere in the throat below the lip.
		local belowLip = position.Y < center.Y - SandSwirl.DEPTH - 1 and r < SandSwirl.HOLE + 1.5
		if belowLip or r < SandSwirl.HOLE - 0.4 and position.Y < center.Y - SandSwirl.DEPTH + 4 then
			self:_gulp(player)
		elseif r < SandSwirl.RIM + 4 then
			local ping = math.clamp(player:GetNetworkPing(), 0, 0.3)
			table.insert(divers, { Player = player, Position = position, Ping = ping })
		end
	end

	for id, item in self.items do
		local _, _, sunk = self:ItemPolar(item, now)
		if sunk and sunk <= now then
			self.items[id] = nil
			self.dirty = true
			local kind = SinkingSands.Kinds[item.Kind]
			self:_scoreKings(kind.Value)
			ctx:Fire(nil, "Sink", id, kind.Value)
			continue
		end
		if now < item.T then
			continue
		end
		local kind = SinkingSands.Kinds[item.Kind]
		local here = self:ItemPosition(item, now)
		local best, bestDistance = nil, math.huge
		for _, diver in divers do
			-- Lag leeway: also check where the treasure was when this player's view was taken.
			local before = self:ItemPosition(item, now - diver.Ping)
			local d = math.min(
				Vector2.new(diver.Position.X - here.X, diver.Position.Z - here.Z).Magnitude,
				Vector2.new(diver.Position.X - before.X, diver.Position.Z - before.Z).Magnitude
			)
			local dy = diver.Position.Y - here.Y
			if d < kind.Reach and dy > -2 and dy < 7.5 and d < bestDistance then
				best, bestDistance = diver.Player, d
			end
		end
		if best then
			self.items[id] = nil
			self.dirty = true
			ctx:AddScore(best, kind.Value)
			ctx:AddTeamScore(DIVERS, kind.Value)
			ctx:Fire(nil, "Grab", id, best.UserId, kind.Value)
		end
	end
end

return SinkingSands

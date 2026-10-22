-- Sinking Sands (Versus, 45s, 1 to 12 players). After Mario Party's "Quicksand Cache": a desert
-- mesa whose middle is a giant quicksand funnel draining into a sinkhole. Coins, gems, coin bags,
-- the odd GOLDEN IDOL and a SUNKEN CHEST near the bottom rain onto the sand and ride the swirl down
-- into the hole.
--
--   DIVERS (most players) run on the sand and grab treasure (+1 coin, +3 gem, +5 bag, +8 chest,
--   +10 idol). The sand drags them round and in; whoever slips into the sinkhole is spat back out
--   at the rim a moment later (and the Sand Kings score +5).
--   SAND KINGS (about one in three, on thrones round the rim) steer the swirl: SWIRL flips the spin
--   and whips it faster, PULL drains the funnel hard for three seconds, and a tap on the sand SAND
--   BLASTs it: a ring, then an eruption that throws any Diver still in it and knocks a gem out of
--   their haul. Every treasure that sinks goes to the Kings. With nobody to be a King (a solo
--   round) the sand plays King by itself.
-- The team with the bigger haul wins.
--
-- How it works: the sand is a shared schedule of constant-flow segments (Logic/SandSwirl), and a
-- treasure is just (radius, angle, time) on it, so every client draws each treasure on the same
-- spiral the server judges grabs on, without streaming positions. Players' devices drag their own
-- characters with the sand (smooth); the server drags bots the same way (hazard parity) and checks
-- everyone against the sinkhole by position.
--
-- Fair judging (hitbox pass, after "We need to fine tune some of the hitboxes. the precision games
-- will feel super bad if we dont."): what looks like a grab on a Diver's own screen counts. Treasure
-- can whip past at up to ~50 studs/s in a SWIRL + PULL, so a grab is a swept test over the Diver's
-- path since the last check against the treasure's path as their device drew it (up to their ping
-- plus the client's easing earlier), and treasure that touched a Diver before it slid into the hole
-- is theirs, not the Kings'. The hole only takes a Diver whose whole body is over it (or who fell
-- in): a Diver visibly standing on the lip is still on the sand.
--
-- Bot pass (owner, after a round the Kings won 145 to 52 with the diver bots on 3, 2, 0, 4 and 0:
-- "Bots are terrible at this game. can we make them a little better."): the sand drags bots and
-- then they steer like a player's stick, every frame (_dragBots), so a real server's physics can't
-- stop their walk; how they play is in Bots/SinkingSands.
--
-- Stronger Kings (owner, told the Divers now won almost every round: "lets make it stronger and add
-- another king"): one more King per round (SandSwirl.KingCount: 3 of 8 players, 4 of 12, never all
-- Kings) and a stronger, longer PULL (SandSwirl.PULL, PULL_HOLD).
--
-- Owner, after playing it: "sand king needs to have more interaction, is boring" and "sand one more
-- valuable stuff near the bottom. also increase pull". Kings get the SAND BLAST, aimed where they
-- tap (judged the Arrow Ambush way: the ring is where their screen showed it, and a Diver is hit
-- only if they were in it on their own screen when it erupted, allowing for their ping); Divers
-- get the SUNKEN CHEST (+8), one at a time near the bottom, so heavy that only a whole PULL sinks
-- it; and the PULL drains a little harder (SandSwirl.PULL).

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
	-- The SUNKEN CHEST lands near the bottom and is so heavy it barely slides: only a whole PULL
	-- sinks it. (Reach: its 2.8 x 1.9 lid plus half a body, as drawn.)
	{ Name = "Chest", Value = 8, Weight = 0, Factor = 0.03, Reach = 2.9, Prop = "SandChest" },
}
local IDOL, CHEST = 4, 5
local COIN, GEM = 1, 2
SinkingSands.CHEST = CHEST -- (for the bots)

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
local HALF_WIDTH = 1 -- half a character's width: the hole takes a Diver whose middle is this far inside it
-- The SUNKEN CHEST (owner: "sand one more valuable stuff near the bottom"): one at a time, landing
-- CHEST_R from the middle (the hole's edge is at 5, the wet sand that sucks hardest reaches 11), the
-- first CHEST_FIRST seconds in, the next one CHEST_GAP after the last is grabbed or sunk.
local CHEST_R = { 7, 8.5 }
local CHEST_FIRST = 8
local CHEST_GAP = { 8, 12 }
-- SAND BLAST (owner: "sand king needs to have more interaction, is boring"): a King taps the sand,
-- a ring shows where for BLAST_DELAY, then the sand erupts: a Diver whose middle is within BLAST_HIT
-- is thrown away from its middle (BLAST_PUSH out, BLAST_LIFT up) and tumbles for BLAST_STUN while
-- the sand keeps dragging them, and a gem (or a coin) from their haul pops out onto the sand. The
-- ring is drawn BLAST_RING wide, half a stud more, so a hit is clearly inside it (as Arrow Ambush's
-- rings). A King's BLAST comes back sooner the more Divers each King has to watch: each Diver faces
-- one about every BLAST_EVERY seconds (BLAST_COOLDOWN bounds a King's own wait).
local BLAST_DELAY = 0.75
local BLAST_HIT = 4
SinkingSands.BLAST_DELAY = BLAST_DELAY -- (for the bots: when a blast erupts, and the ring to get out of)
SinkingSands.BLAST_RING = BLAST_HIT + 0.5
local BLAST_PUSH, BLAST_LIFT = 20, 24
local BLAST_STUN = 0.7
local BLAST_SLIDE = 0.3 -- (test servers: about how long the throw carries someone in a real game)
local BLAST_EVERY = 10
local BLAST_COOLDOWN = { 5, 8 }
local JUDGE_SPREAD = 0.1 -- a Diver is looked at twice, this far apart: only in it both times is a hit
-- Grabs. The client draws each treasure easing after its true spot (1/18 s behind), and a Diver's
-- position reaches the server up to a ping late, so a grab compares the Diver's path with the
-- treasure's path from 0 to (ping + EASE) seconds earlier. SWEEP_STEPS slices the time since the
-- last check; MAX_SPEED (studs/s: the fastest any treasure goes, the lightest in a full SWIRL and
-- PULL, plus a little) only skips pairs that can't possibly meet.
local EASE = 0.06
local SWEEP_STEPS = 4
local MAX_SPEED = (function()
	local factor = 0
	for _, kind in SinkingSands.Kinds do
		factor = math.max(factor, kind.Factor)
	end
	local inward = (SandSwirl.DRAIN[2] + SandSwirl.PULL_CAP) * factor * SandSwirl.TREASURE_DRAIN
	local around = (SandSwirl.SPIN[2] + SandSwirl.SURGE * SandSwirl.SURGE_CAP) * factor
	return math.sqrt(inward * inward + around * around) + 3
end)()

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

-- Flat distance from the origin to the segment between two flat offsets (x, z).
local function segmentReach(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local length = dx * dx + dz * dz
	local t = if length > 1e-9 then math.clamp(-(ax * dx + az * dz) / length, 0, 1) else 0
	local x, z = ax + dx * t, az + dz * t
	return math.sqrt(x * x + z * z)
end

-- A Diver's middle vs a treasure lying on the sand: high enough to reach it, not hovering over it.
local function inHeight(dy: number): boolean
	return dy > -2 and dy < 7.5
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
	self.lastJudge = nil :: number?
	self.spots = {} :: { [any]: { Position: Vector3, Time: number } } -- each Diver at the last check
	self.idols = 0
	self.chestAt = nil :: number? -- when the next SUNKEN CHEST lands (server time; set at GO)
	-- SAND BLASTs on their way (the bots dodge what they see coming) and, where physics isn't running
	-- (test servers), the shove a blast gave a bot (physics carries it in a real game).
	self.blasts = {} :: { [number]: { Id: number, X: number, Z: number, T: number, By: number } }
	self.nextBlast = 0
	self.shoves = {} :: { [any]: { Velocity: Vector3, Until: number } }

	-- Teams (SandSwirl.KingCount): 3 Sand Kings of 8 players, 4 of 12, none when playing alone.
	local players = ctx:GetPlayers()
	for index = #players, 2, -1 do
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local kingCount = SandSwirl.KingCount(#players)
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
	self:_buildBackdrop(floorY)

	-- The mesa and its funnel (one mesh), and the swirl streaks the clients turn.
	local pit =
		MeshLibrary.Get("SandPit", { CFrame = CFrame.new(center - Vector3.new(0, MESA + 0.3, 0)), Parent = arena })
	local swirl = MeshLibrary.Get("SandSwirl", { CFrame = CFrame.new(center - Vector3.new(0, 20, 0)), Parent = arena })
	swirl.Name = "SandSwirl"
	local showFloor = MeshLibrary.Source("SandPit") == "Fallback"
	pit.Name = "SandPit"
	-- The temple courtyard's paving round the funnel (its stones stand a hair proud of the sand).
	MeshLibrary.Get("SandMosaic", { CFrame = CFrame.new(center - Vector3.new(0, 0.24, 0)), Parent = arena })

	-- Walkable collision on the same profile as the mesh: tilted slabs in rings round the funnel and
	-- a flat ring for the mesa top. The sinkhole itself has no floor.
	local floor = Build.Folder("Floor", arena)
	local sectors = 28
	local edges = { SandSwirl.HOLE, 6.5, 8.5, 11, 14, 17.5, 21.5, 26, 30, SandSwirl.RIM }
	-- The suction ring round the hole (HOLE to HOLE + LIP) is darker, wetter sand: "the danger starts
	-- here" in one look, getting darker towards the hole.
	local wetColor = Color3.fromRGB(170, 94, 58) -- the SandPit mesh's Lip colour
	local bandColors = { wetColor, sandColor:Lerp(wetColor, 0.62), sandColor:Lerp(wetColor, 0.3) }
	local function slab(cframe: CFrame, size: Vector3, color: Color3?)
		Build.Part({
			Name = "Sand",
			Size = size,
			CFrame = cframe,
			Color = color or sandColor,
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
			slab(cframe, Vector3.new(width, 1, length), bandColors[band])
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

	self:_buildCourtyard()
end

-- The temple courtyard on the mesa top: a ring of painted columns with royal banners and four
-- gateways framing the funnel, palms flanking each gateway and heaps of treasure that sparkle. The
-- gateways stand north, south, east and west, each framing a landmark beyond the cliffs.
local COLONNADE_R = 66
local BANNER_RED, BANNER_BLUE = Color3.fromRGB(214, 38, 62), Color3.fromRGB(40, 86, 210)

function SinkingSands:_buildCourtyard()
	local center = self.center
	local arena = self.context.Arena
	local function facing(angle: number, radius: number, y: number?): CFrame
		local position = center + Vector3.new(math.cos(angle) * radius, y or 0, math.sin(angle) * radius)
		return CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
	end
	for slot = 0, 15 do
		local angle = slot / 16 * math.pi * 2
		if slot % 4 == 0 then
			MeshLibrary.Get("SandArch", { CFrame = facing(angle, COLONNADE_R), Parent = arena })
			for side = -1, 1, 2 do
				MeshLibrary.Get("SandPalm", {
					CFrame = facing(angle + side * 0.2, 71.5) * CFrame.Angles(0, side * 2.2, 0),
					Scale = 0.9 + (slot % 3) * 0.08,
					Parent = arena,
				})
			end
		elseif slot == 3 or slot == 6 or slot == 9 or slot == 13 then
			MeshLibrary.Get("SandColumnBroken", {
				CFrame = facing(angle, COLONNADE_R) * CFrame.Angles(0, slot * 1.7, 0),
				Parent = arena,
			})
		else
			MeshLibrary.Get("SandColumn", {
				CFrame = facing(angle, COLONNADE_R),
				Colors = { Cloth = if slot % 2 == 0 then BANNER_RED else BANNER_BLUE },
				Parent = arena,
			})
		end
		if slot % 4 == 2 then
			-- Treasure heaps sit up on a stone altar step beside their column, so they read as
			-- scenery and not as treasure to grab (the real treasure lies loose on the sand).
			local at = facing(angle + 0.14, 64)
			Build.Part({
				Name = "HoardAltar",
				Size = Vector3.new(10.5, 1.4, 10.5),
				CFrame = at * CFrame.new(0, 0.7, 0),
				Color = Color3.fromRGB(232, 204, 152),
				Material = Enum.Material.Sandstone,
				CanTouch = false,
				Parent = arena,
			})
			local hoard = MeshLibrary.Get("SandHoard", {
				CFrame = at * CFrame.new(0, 1.4, 0) * CFrame.Angles(0, math.pi + slot * 0.3, 0),
				Parent = arena,
			})
			self:_sparkle(hoard)
		end
	end
end

-- Gold glints rising off a heap of treasure (ambient: reduced-effects aware).
function SinkingSands:_sparkle(model: Model)
	local box, size = model:GetBoundingBox()
	local source = Build.Decor({
		Name = "Glints",
		Size = Vector3.new(size.X * 0.7, 1, size.Z * 0.7),
		CFrame = box,
		Transparency = 1,
		Parent = model,
	})
	local glints = Instance.new("ParticleEmitter")
	glints.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glints.Color = ColorSequence.new(Color3.fromRGB(255, 236, 140))
	glints.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	glints.Lifetime = NumberRange.new(0.7, 1.2)
	glints.Rate = 2 -- the brightest twinkles stay on the real treasure
	glints.Speed = NumberRange.new(0.5, 1.5)
	glints.SpreadAngle = Vector2.new(60, 60)
	glints.LightEmission = 1
	self:_ambient(glints, source)
end

-- Beyond the cliffs: a golden step-temple, a colossal sphinx, far pyramids, an oasis with palms,
-- rolling dunes in layers that pale with distance, and ruins and cacti on the desert floor.
local TEMPLE_ANGLE = -math.pi / 2 -- the temple stands on the -Z side
local SPHINX_ANGLE = 0
local OASIS_ANGLE = math.pi

function SinkingSands:_buildBackdrop(floorY: number)
	local center = self.center
	local arena = self.context.Arena
	local function at(angle: number, distance: number): Vector3
		return Vector3.new(center.X + math.cos(angle) * distance, floorY, center.Z + math.sin(angle) * distance)
	end
	local function facingCenter(position: Vector3): CFrame
		return CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
	end

	-- The temple's pivot (its footprint's middle) sits 12.8 studs (unscaled) in front of its core.
	local templeScale = 1.8
	MeshLibrary.Get("SandTemple", {
		CFrame = facingCenter(at(TEMPLE_ANGLE, 262 - 12.8 * templeScale)),
		Scale = templeScale,
		Parent = arena,
	})
	MeshLibrary.Get("SandSphinx", {
		CFrame = facingCenter(at(SPHINX_ANGLE, 248)),
		Scale = 2.3,
		Parent = arena,
	})
	for _, pyramid in
		{
			{ math.pi / 2, 470, 2.0 },
			{ math.rad(205), 430, 1.6 },
			{ math.rad(228), 520, 1.3 },
			{ math.rad(320), 480, 1.5 },
		}
	do
		MeshLibrary.Get("SandPyramid", {
			CFrame = CFrame.new(at(pyramid[1], pyramid[2])) * CFrame.Angles(0, pyramid[1] * 0.7, 0),
			Scale = pyramid[3],
			Parent = arena,
		})
	end

	-- The oasis with its palms.
	local oasis = at(OASIS_ANGLE, 140)
	MeshLibrary.Get("SandOasis", { CFrame = facingCenter(oasis), Scale = 1.1, Parent = arena })
	for index = 1, 6 do
		local angle = OASIS_ANGLE + index * 1.05
		local position = oasis + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (26 + index % 2 * 4)
		MeshLibrary.Get("SandPalm", {
			CFrame = CFrame.new(position) * CFrame.Angles(0, index * 1.3, 0),
			Scale = 1.3 + (index % 3) * 0.15,
			Parent = arena,
		})
	end

	-- Dunes in rings: the near ones warm, the far ones paler (as if seen through the heat haze).
	local near, far = Color3.fromRGB(234, 172, 98), Color3.fromRGB(248, 218, 172)
	for index = 1, 18 do
		local ring = index % 3
		local angle = index / 18 * math.pi * 2 + ring * 0.21
		local distance = 200 + ring * 110 + rng:NextNumber(0, 40)
		if
			distance < 400
			and (
				math.cos(angle - TEMPLE_ANGLE) > 0.88
				or math.cos(angle - SPHINX_ANGLE) > 0.88
				or math.cos(angle - math.pi / 2) > 0.94
			)
		then
			continue -- keep the temple, the sphinx and the big pyramid in view
		end
		local scale = 1 + ring * 0.3 + rng:NextNumber(0, 0.25)
		local dune = MeshLibrary.Get("SandDune", {
			-- (its skirt sits 3 studs below its foot: sunk that far, the dune rises out of the floor)
			CFrame = CFrame.new(at(angle, distance) - Vector3.new(0, 3 * scale, 0))
				* CFrame.Angles(0, -angle + math.pi / 2 + rng:NextNumber(-0.4, 0.4), 0),
			Scale = scale,
			Colors = { Dune = near:Lerp(far, ring / 2) },
			Parent = arena,
		})
		dune.Name = "Dune"
	end

	-- Ruins, fallen columns and cacti on the desert floor round the mesa.
	local placed = {}
	local function scatter(prop: string, count: number, r0: number, r1: number, scale: { number })
		local tries = 0
		while count > 0 and tries < 80 do
			tries += 1
			local angle = rng:NextNumber(0, math.pi * 2)
			local position = at(angle, rng:NextNumber(r0, r1))
			local ok = (position - at(OASIS_ANGLE, 140)).Magnitude > 45
				and math.abs(math.cos(angle - TEMPLE_ANGLE)) < 0.9
				and math.abs(math.cos(angle - SPHINX_ANGLE)) < 0.94
			for _, other in placed do
				if (other - position).Magnitude < 16 then
					ok = false
				end
			end
			if ok then
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
	scatter("SandColumnBroken", 4, 100, 170, { 1.2, 1.6 })
	scatter("SandRuin", 4, 100, 180, { 1.6, 2.4 })
	scatter("Cactus", 7, 100, 200, { 1.3, 2 })
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

-- A new treasure falling onto the sand: at `radius` and `angle` (random where not given), landing
-- `fall` seconds from now (FALL_TIME from the sky; a dropped one only pops up a little).
function SinkingSands:_spawnItem(kind: number, radius: number?, angle: number?, fall: number?)
	local ctx = self.context
	self.nextId += 1
	local now = ctx:Now()
	local item = {
		Id = self.nextId,
		Kind = kind,
		R = round(radius or rng:NextNumber(11, SandSwirl.RIM - 4), 3),
		A = round(angle or rng:NextNumber(-math.pi, math.pi), 4),
		T = round(now + (fall or FALL_TIME), 3),
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

-- Cooldowns for this many Kings: a lone King has to keep the sand busy by themself. A BLAST is
-- back sooner the more Divers each King has to watch (BLAST_EVERY).
function SinkingSands:Cooldowns(): (number, number, number)
	local kings = #self.kings
	local share = math.clamp(kings, 1, 3) / 3
	local divers = math.max(1, #self.context:GetPlayers() - kings)
	return SWIRL_COOLDOWN * (0.55 + 0.45 * share),
		PULL_COOLDOWN * (0.6 + 0.4 * share),
		math.clamp(BLAST_EVERY * math.max(1, kings) / divers, BLAST_COOLDOWN[1], BLAST_COOLDOWN[2])
end

-- SAND BLAST ---------------------------------------------------------------------------------------

-- A blast where a King tapped (kept on the sand; 0 for the sand playing King by itself), erupting
-- BLAST_DELAY from now. Everyone sees the ring at once ("Blast"), so a Diver who's quick can get out.
function SinkingSands:_blast(byUserId: number, x: number, z: number)
	local ctx = self.context
	local center = self.center
	local dx, dz = x - center.X, z - center.Z
	local r = math.sqrt(dx * dx + dz * dz)
	if r > SandSwirl.RIM then
		dx, dz = dx / r * SandSwirl.RIM, dz / r * SandSwirl.RIM
	end
	self.nextBlast += 1
	local blast = {
		Id = self.nextBlast,
		X = round(center.X + dx, 2),
		Z = round(center.Z + dz, 2),
		T = round(ctx:Now() + BLAST_DELAY, 3),
		By = byUserId,
	}
	self.blasts[blast.Id] = blast
	ctx:Fire(nil, "Blast", blast.Id, blast.X, blast.Z, blast.T, blast.By, SinkingSands.BLAST_RING)
	ctx:Delay(BLAST_DELAY, function()
		self:_erupt(blast)
	end)
end

-- The sand playing King by itself: a blast under one of the Divers on the sand.
function SinkingSands:_autoBlast()
	local ctx = self.context
	local spots = {}
	for _, player in ctx:GetAlivePlayers() do
		local _, _, root = ctx:GetCharacter(player)
		if root and not self.gulped[player] and not self:IsKing(player) then
			local position = root.Position
			if Vector2.new(position.X - self.center.X, position.Z - self.center.Z).Magnitude < SandSwirl.RIM then
				table.insert(spots, position)
			end
		end
	end
	if #spots > 0 then
		local spot = spots[rng:NextInteger(1, #spots)]
		self:_blast(0, spot.X, spot.Z)
	end
end

-- How far (flat) a Diver's middle is from a blast (math.huge once they're gone or down the hole).
function SinkingSands:_blastDistance(blast, diver: any): number
	local _, _, root = self.context:GetCharacter(diver)
	if not root or self.gulped[diver] then
		return math.huge
	end
	return Vector2.new(root.Position.X - blast.X, root.Position.Z - blast.Z).Magnitude
end

-- The sand erupts. Each Diver is judged by where they were on their own screen when it did: their
-- moves reach the server half a ping (a round trip) late, so look then, and again JUDGE_SPREAD
-- later; only inside BLAST_HIT both times is a hit (a dodge that looked clean on their screen
-- counts). Something that erupts after the buzzer is too late (RoundContext.InTime / HoldEnd).
function SinkingSands:_erupt(blast)
	local ctx = self.context
	self.blasts[blast.Id] = nil
	ctx:Fire(nil, "Erupt", blast.Id)
	if not ctx:InTime(blast.T) then
		return
	end
	for _, diver in ctx:GetAlivePlayers() do
		if self:IsKing(diver) or self.gulped[diver] then
			continue
		end
		local ok, ping = pcall(function()
			return (diver :: any):GetNetworkPing()
		end)
		local lag = if ok and type(ping) == "number" then math.clamp(ping, 0, 0.4) / 2 else 0.05
		ctx:HoldEnd(lag + JUDGE_SPREAD + 0.05)
		local function second(first: number)
			ctx:Delay(JUDGE_SPREAD, function()
				self:_blastJudge(blast, diver, first)
			end)
		end
		if lag <= 0.01 then
			second(self:_blastDistance(blast, diver))
		else
			ctx:Delay(lag, function()
				second(self:_blastDistance(blast, diver))
			end)
		end
	end
end

-- The second look at a Diver after an eruption (`first` is the distance at the first look). A hit
-- throws them away from the blast to tumble a moment (the sand drags them meanwhile, the same for
-- bots and people), and knocks a gem out of their haul (a coin if they have less): it pops out of
-- the eruption, behind them as they fly, for anyone to grab back before it sinks for the Kings.
function SinkingSands:_blastJudge(blast, diver: any, first: number)
	local ctx = self.context
	if not ctx:IsAlive(diver) or self:IsKing(diver) or self.gulped[diver] then
		return
	end
	local second = self:_blastDistance(blast, diver)
	if first > BLAST_HIT or second > BLAST_HIT then
		return
	end
	local _, _, root = ctx:GetCharacter(diver)
	if not root then
		return
	end
	local center = self.center
	local offset = Vector3.new(root.Position.X - blast.X, 0, root.Position.Z - blast.Z)
	local outward = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
	local away = if offset.Magnitude > 0.2
		then offset.Unit
		elseif outward.Magnitude > 0.2 then outward.Unit
		else Vector3.new(1, 0, 0)
	ctx:Knockback(diver, away * BLAST_PUSH + Vector3.new(0, BLAST_LIFT, 0), BLAST_STUN)
	if not RunService:IsRunning() then
		-- (no physics on the test servers: the mode carries a bot's throw itself, see _dragBots, and
		-- stops its walk while it would be tumbling)
		ctx:Stun(diver, BLAST_STUN)
		self.shoves[diver] = { Velocity = away * BLAST_PUSH, Until = ctx:Now() + BLAST_SLIDE }
	end
	local state = ctx:State(diver)
	local haul = if state then state.Score else 0
	local drop = if haul >= 3 then 3 elseif haul >= 1 then 1 else 0
	if drop > 0 then
		ctx:AddScore(diver, -drop)
		ctx:AddTeamScore(DIVERS, -drop)
		local r, a = SandSwirl.ToPolar(blast.X - center.X, blast.Z - center.Z)
		self:_spawnItem(if drop == 3 then GEM else COIN, math.clamp(r, SandSwirl.HOLE + 1, SandSwirl.RIM - 1), a, 0.35)
	end
	ctx:Fire(nil, "BlastHit", blast.Id, diver.UserId, drop)
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
-- Bots let go of the stick _dragBots pushed for them.
function SinkingSands:Stop()
	local ctx = self.context
	for player in self.gulped do
		self.gulped[player] = nil
		ctx:Respawn(player)
		ctx:Freeze(player, false)
	end
	for _, player in ctx:GetPlayers() do
		local _, humanoid = ctx:GetCharacter(player)
		if humanoid and isBot(player) then
			humanoid:Move(Vector3.zero)
		end
	end
	table.clear(self.blasts)
	table.clear(self.shoves)
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
	local ready: { [any]: { Swirl: number, Pull: number, Blast: number } } = {}
	local function readyFor(player)
		ready[player] = ready[player] or { Swirl = 0, Pull = 0, Blast = 0 }
		return ready[player]
	end
	-- SAND BLAST: where the King tapped on their screen (x, z on the sand).
	ctx:OnAction("Blast", function(player, x, z)
		if not self:IsKing(player) or ctx:TimeIsUp() then
			return -- (once time is up no blast could erupt in time)
		end
		if type(x) ~= "number" or type(z) ~= "number" or x ~= x or z ~= z then
			return
		end
		local cool = readyFor(player)
		local now = ctx:Now()
		if now < cool.Blast - 0.1 then
			return
		end
		local _, _, length = self:Cooldowns()
		cool.Blast = now + length
		ctx:SetPlayerShared(player, "BlastLength", length)
		ctx:SetPlayerShared(player, "BlastAt", cool.Blast)
		self:_blast(player.UserId, x, z)
	end, { Interval = 0.2 })
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
	local nextAutoBlast = os.clock() + 6
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
			if now >= nextAutoBlast and not ctx:TimeIsUp() then
				nextAutoBlast = now + rng:NextNumber(7, 10)
				self:_autoBlast()
			end
		end
		return 0.5
	end)

	-- The SUNKEN CHEST: one at a time, landing near the bottom.
	self.chestAt = ctx:Now() + CHEST_FIRST
	ctx:Loop(function()
		local now = ctx:Now()
		for _, item in self.items do
			if item.Kind == CHEST then
				return 0.25
			end
		end
		if not self.chestAt then
			self.chestAt = now + rng:NextNumber(CHEST_GAP[1], CHEST_GAP[2])
		elseif now >= self.chestAt then
			self.chestAt = nil
			self:_spawnItem(CHEST, rng:NextNumber(CHEST_R[1], CHEST_R[2]))
		end
		return 0.25
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
-- its own character (same flow, same numbers, same cap on a long frame).
--
-- And then they steer, as a player's device does every frame: in a real game the diver bots
-- scored 0-4 and slid into the hole again and again, while on the test servers (where bots walk
-- without physics) the same brain scored 20 on average. A bot walks with Humanoid:MoveTo, renewed
-- only about 7 times a second, and moving its root from a script in between evidently ends that
-- walk, so the sand won (a simulated round where it does looks just like the owner's: bots on 0-6
-- who fall in five or six times each). Humanoid:Move is the stick a player's device pushes every
-- frame: pushed towards where the brain wants to go after every drag, the walk goes on whatever
-- the sand does.
function SinkingSands:_dragBots(dt: number, now: number, physics: boolean)
	local ctx = self.context
	local center = self.center
	dt = math.min(dt, 0.1)
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
		local move = Vector3.zero
		if r > 0.01 then
			local inward, spin = SandSwirl.WalkerFlow(self.segments, r, now)
			local k = if airborne then SandSwirl.AIR_DRAG else 1
			local u = offset / r
			move = (-u * inward + Vector3.new(-u.Z, 0, u.X) * spin) * dt * k
		end
		local shove = self.shoves[player]
		if shove and now >= shove.Until then
			self.shoves[player] = nil
		elseif shove and not physics then
			move += shove.Velocity * dt -- (a SAND BLAST's shove; physics carries it in a real game)
		end
		if physics then
			if move.Magnitude > 0 then
				root.CFrame += move
			end
			local goal: Vector3? = (player :: any).Goal
			local toward = if goal
				then Vector3.new(goal.X - position.X - move.X, 0, goal.Z - position.Z - move.Z)
				else Vector3.zero
			humanoid:Move(if toward.Magnitude > 0.5 then toward.Unit else Vector3.zero)
		elseif r < 0.01 then
			continue
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

-- How close a Diver came to a treasure since the last check, as their own device showed it: their
-- path since then (sliced into SWEEP_STEPS) against the treasure's path `lag` seconds earlier for
-- lags 0, half and all of (ping + EASE), with every neighbouring pair of samples swept, so a fast
-- pass between two checks still counts. `at(t)` is the treasure on the sand at `t` (nil while it is
-- still falling or once it has gone down the hole).
function SinkingSands:_closest(diver: any, at: (number) -> Vector3?, now: number, span: number): number
	local best = math.huge
	local rows = {}
	for j = 0, SWEEP_STEPS do
		local u = j / SWEEP_STEPS
		local s = now - span * (1 - u)
		local p = diver.From:Lerp(diver.Position, u)
		local row = {}
		for k = 0, 2 do
			local spot = at(s - diver.Lag * k / 2)
			if spot then
				row[k] = { p.X - spot.X, p.Z - spot.Z, inHeight(p.Y - spot.Y) }
			end
		end
		rows[j] = row
	end
	local function sweep(a, b)
		if a and b and (a[3] or b[3]) then
			best = math.min(best, segmentReach(a[1], a[2], b[1], b[2]))
		elseif a and a[3] then
			best = math.min(best, math.sqrt(a[1] * a[1] + a[2] * a[2]))
		end
	end
	for j = 0, SWEEP_STEPS do
		for k = 0, 2 do
			local here = rows[j][k]
			sweep(here, rows[j][k + 1])
			sweep(here, if j < SWEEP_STEPS then rows[j + 1][k] else nil)
		end
	end
	return best
end

function SinkingSands:_judge(now: number)
	local ctx = self.context
	local center = self.center
	local last = self.lastJudge
	self.lastJudge = now
	local span = if last then math.clamp(now - last, 0, 0.25) else 0
	-- Divers who are on the sand (and where, now and at the last check).
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
		-- In the hole: fallen below the lip, or low with the whole body over the hole. Someone whose
		-- feet are still on the lip (middle within HALF_WIDTH of the edge) is standing on the sand,
		-- whatever the sand is doing to them.
		local belowLip = position.Y < center.Y - SandSwirl.DEPTH - 1 and r < SandSwirl.HOLE + 1.5
		if belowLip or r < SandSwirl.HOLE - HALF_WIDTH and position.Y < center.Y - SandSwirl.DEPTH + 4 then
			self.spots[player] = nil
			self:_gulp(player)
		elseif r < SandSwirl.RIM + 4 then
			-- Where they were at the last check (not across a respawn or a teleport).
			local previous = self.spots[player]
			local from = position
			if previous and previous.Time == last and (previous.Position - position).Magnitude < span * 40 + 2 then
				from = previous.Position
			end
			self.spots[player] = { Position = position, Time = now }
			local ping = math.clamp(player:GetNetworkPing(), 0, 0.3)
			table.insert(divers, { Player = player, Position = position, From = from, Lag = ping + EASE })
		else
			self.spots[player] = nil
		end
	end

	for id, item in self.items do
		local _, _, sunk = self:ItemPolar(item, now)
		local kind = SinkingSands.Kinds[item.Kind]
		if now >= item.T or sunk then
			-- The treasure's spots on the sand, shared by every Diver's test this check.
			local cache = {}
			local function at(t: number): Vector3?
				if t < item.T or sunk and t > sunk then
					return nil
				end
				local key = math.floor(t * 80 + 0.5)
				local spot = cache[key]
				if not spot then
					spot = self:ItemPosition(item, key / 80)
					cache[key] = spot
				end
				return spot
			end
			local here = self:ItemPosition(item, if sunk then math.min(now, sunk) else now)
			local best, bestDistance = nil, math.huge
			for _, diver in divers do
				local far = kind.Reach + (diver.From - diver.Position).Magnitude + MAX_SPEED * (span + diver.Lag)
				if Vector2.new(diver.Position.X - here.X, diver.Position.Z - here.Z).Magnitude > far then
					continue
				end
				local d = self:_closest(diver, at, now, span)
				if d < kind.Reach and d < bestDistance then
					best, bestDistance = diver.Player, d
				end
			end
			if best then
				-- Touched on the Diver's screen before it went down: theirs, even if it sank since.
				self.items[id] = nil
				self.dirty = true
				ctx:AddScore(best, kind.Value)
				ctx:AddTeamScore(DIVERS, kind.Value)
				ctx:Fire(nil, "Grab", id, best.UserId, kind.Value)
				continue
			end
		end
		if sunk and sunk <= now then
			self.items[id] = nil
			self.dirty = true
			self:_scoreKings(kind.Value)
			ctx:Fire(nil, "Sink", id, kind.Value)
		end
	end
end

return SinkingSands

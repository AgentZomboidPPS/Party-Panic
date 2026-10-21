-- Shark Bait (Versus, 60s, 2 to 12 players). Owner: "Can you work on shark bait?" and "dont forget
-- about using meshes and making this mini game stunning. I want players to be like damn. That was
-- the best mini game I have ever played." Seven round log rafts float in a tropical cove: a big one
-- in the middle and six around it, a short hop apart. One SHARK (two from seven players) swims in
-- the water round and between them; everyone else is a SWIMMER up on the rafts.
--
--   SWIMMERS hop raft to raft grabbing coins (+1): on the decks, hanging over the gaps (grab them
--   mid-hop) and floating in the water, where pearls (+3) and the odd TREASURE CHEST (+6) bob too.
--   The swimmers win together the moment their haul reaches the goal on the HUD. Anyone in the
--   water is slow, and fair game for the shark. In the last quarter comes the COIN RUSH: coins twice
--   as fast, more of them in the water.
--   SHARKS can't climb onto a raft. CHOMP (E, or the button) snaps the jaws: a swimmer in the water
--   in reach is swallowed (the swimmers' haul loses 2 coins) and spat back out onto a raft 4 s
--   later, and a raft in reach WOBBLES for 1.2 s, then FLIPS: everyone still on it is thrown into the
--   water and its coins spill round it. It bobs back up 3 s later and can't be chomped again for a
--   moment. Sharks win if the goal isn't reached by the buzzer. At least two rafts always stay up,
--   so there's always somewhere to jump. Nobody is ever out: everyone plays the whole minute.
--
-- How it works. The server owns everything; clients draw. Every raft is one invisible upright
-- cylinder from the hidden sea floor (3.5 studs under the water, where anyone in the water stands,
-- head and shoulders out) up to the deck, so nobody passes under a raft; a flip just turns its
-- collider off for the dunk. The clients draw the rafts (bobbing, rocking, flipping) from MG_Rafts,
-- the coins from MG_Coins and each shark at its character (the server hides the shark's body), and
-- the shark is a character walking on the sea floor, fast and unable to jump. Everything is judged
-- by position on the server, never Touched, so bots and the no-physics test servers play by the
-- same rules: bots are thrown and lifted by the server (hazard parity), players by their device.
-- Bots and the sharks' hidden bodies pass through every character (BODY_GROUP).
--
-- Fair judging (owner: "the precision games will feel super bad if we dont"):
--  * A bite only takes a swimmer who is in the water and inside the jaws' reach when their own
--    screen showed it: looked at half their ping after the chomp and again JUDGE_SPREAD later; a
--    swimmer who climbed out (or swam clear) on their screen is spared. The reach is the lunge the
--    clients draw: from just ahead of the shark's middle to its snout thrust forward (JAW_NEAR to
--    JAW_FAR along its facing), BITE_RADIUS round that.
--  * A flip throws only who was on the raft on their own screen when it went (the same two looks);
--    a swimmer who hopped off in time keeps going. The collider itself goes for everyone at once,
--    which is right on every screen: whoever stands on it falls.
--  * A grab is a swept test along the swimmer's path since the last check (coins don't move), so a
--    coin brushed mid-hop counts. The client half pops a coin it judges grabbed by the same rule.

local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

local MiniGame = require(script.Parent.Kit.MiniGame)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)

local SharkBait = MiniGame.Define("SharkBait")

SharkBait.SHARKS = "Sharks"
SharkBait.SWIMMERS = "Swimmers"

-- Heights, relative to the arena origin (the deck tops).
SharkBait.DECK = 0
SharkBait.WATER = -1 -- the water surface, a stud under the decks
SharkBait.SEA_FLOOR = SharkBait.WATER - 3.5 -- the hidden floor everyone in the water stands on
SharkBait.SEA_BED = SharkBait.WATER - 14 -- the sand you see through the water
-- A root below this is in the water (standing in it the root is 0.5 under the surface; up on a deck
-- it's 3 over the deck; a jump out of the water passes it on the way up).
SharkBait.WET = SharkBait.WATER + 0.9
SharkBait.HIP = 3 -- a character's root above what it stands on
SharkBait.SHARK_Y = SharkBait.WATER - 2.6 -- the shark mesh's base (its y = 2.6 is the waterline)

SharkBait.LAGOON = 44 -- the float line: everyone stays inside it
SharkBait.RING = 18.5 -- the outer rafts' distance from the middle
SharkBait.CENTER_RADIUS = 7.5
SharkBait.RING_RADIUS = 6.5
SharkBait.RAFT_MESH_RADIUS = 7 -- SharkBaitRaft's deck at scale 1 (its deck top is the mesh's top)
SharkBait.RAFT_MESH_HEIGHT = 2

SharkBait.SHARK_SPEED = 22
SharkBait.SWIM_SPEED = 10
SharkBait.WOBBLE = 1.2 -- warning before a chomped raft flips
SharkBait.DUNK = 3 -- how long a flipped raft stays under
SharkBait.SAFE = 2.5 -- a raft that just came up can't be chomped for this long
SharkBait.BITE_COOLDOWN = 0.8
SharkBait.RAM_COOLDOWN = 1.8 -- the jaws are ready again just after the raft goes over
SharkBait.MIN_READY = 2 -- a chomp never leaves fewer rafts than this to stand on
-- The jaws' reach along the shark's facing (its middle to its snout thrust forward in the lunge),
-- and how far round that line a swimmer's middle may be.
SharkBait.JAW_NEAR = 1
SharkBait.JAW_FAR = 7.5
SharkBait.BITE_RADIUS = 2.3
SharkBait.RAM_REACH = 0.6 -- a raft's edge this far past the jaws' line still counts as hit
local JUDGE_SPREAD = 0.1
local BITE_SLACK = 0.6 -- the second look allows the swimmer's own follow-through
local OVERHANG = 0.6 -- a middle this far past a raft's edge still stands on it (feet on the rim)
local TOSS_OUT, TOSS_UP = 20, 34 -- thrown about 2 to 9 studs out past the edge
local GULP_TIME = 4 -- a swallowed swimmer is spat back out onto a raft after this long
SharkBait.CHOMP_COST = 2 -- coins a chomp takes off the swimmers' haul
local POCKET = -32.5 -- the shark's belly: a hidden ledge under the sea bed, where swallowed swimmers wait
-- Each swallowed swimmer waits on their own spot there, a 4 x 3 grid 5 studs apart: two players
-- put in one place would shove each other apart, hard.
local BELLY_SPOTS = 12
local CLIMB_TIME = 0.8 -- no-physics test servers: how long a swimmer takes to climb out at a raft
-- Bots and the sharks' hidden bodies pass through every character (players keep the lobby's
-- PP_Players group and bump each other as everywhere else). On a live server each device moves its
-- own player and the server moves the bots, so a player walking into a bot on a crowded raft could
-- shove it hard enough to fling it into the sky (Hex Meltdown's "Bot is floating."); and a shark is
-- drawn as a mesh far longer than the body it swims with, which mustn't stop anyone.
local BODY_GROUP, PEOPLE_GROUP = "PP_SharkBodies", "PP_Players"
local WATER_LIFE = 9 -- coins in the water sink after this long
local CHEST_LIFE = 12
local POP_IN = 0.35 -- a new coin rises into view this long before it can be grabbed
local RUSH_AT = 0.75 -- the COIN RUSH (coins twice as fast, more of them in the water) for the last quarter
local SPILL_TIME = 0.55 -- spilled coins fly this long before they land in the water
-- A grab: the coin's middle within the kind's reach of the swimmer's middle (flat), and the coin
-- between GRAB_BELOW under and GRAB_ABOVE over it.
SharkBait.GRAB_BELOW = 3.2
SharkBait.GRAB_ABOVE = 2.6

SharkBait.Kinds = {
	{ Name = "Coin", Value = 1, Reach = 2.8, Prop = "SharkBaitCoin" },
	{ Name = "Pearl", Value = 3, Reach = 3, Prop = "SharkBaitPearl" },
	{ Name = "Chest", Value = 6, Reach = 3.6, Prop = "SharkBaitChest" },
}
local COIN, PEARL, CHEST = 1, 2, 3
-- Coin heights over the deck (rafts and gaps) or the water.
SharkBait.DECK_COIN = 1.4
SharkBait.GAP_COIN = 7.5 -- where a running hop across a gap passes (the root rises 7.2 in a jump)
SharkBait.WATER_COIN = 0.4

SharkBait.READY, SharkBait.WOBBLING, SharkBait.FLIPPED = 0, 1, 2

-- Seamless water textures (tools/art/water_textures.py, uploaded with --upload): light caustics on
-- the sea floor and ripple lines on the surface, two layers of each drifting different ways (the
-- client half scrolls them).
SharkBait.Textures = {
	Caustics = "rbxassetid://123272338089068",
	Ripples = "rbxassetid://123824947073819",
}

local physics = RunService:IsRunning()
local rng = Random.new()
local decor = Random.new(9177) -- the cove's dressing is laid out the same every round

export type Raft = {
	Index: number,
	Center: Vector3, -- the middle of the deck's top
	Radius: number,
	Yaw: number,
	State: number,
	Since: number, -- server time the state began
	SafeUntil: number,
	Collider: BasePart,
	Neighbours: { number },
}

export type Coin = {
	Id: number,
	Kind: number,
	Position: Vector3,
	Raft: number, -- deck coins ride their raft (0 for gap and water coins)
	Born: number, -- grabbable from
	Expires: number, -- 0 = until grabbed
	From: Vector3?, -- spilled coins fly from here...
	SpillAt: number?, -- ...starting then
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function round(value: number, places: number): number
	local k = 10 ^ places
	return math.floor(value * k + 0.5) / k
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- The way a CFrame faces, flattened (straight ahead along -Z if it faces straight up or down).
local function flatLook(cframe: CFrame): Vector3
	local look = flat(cframe.LookVector)
	return if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
end

-- Flat distance from `point` to the segment `a`-`b`.
local function segmentDistance(point: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
	local ap = Vector2.new(point.X - a.X, point.Z - a.Z)
	local length = ab:Dot(ab)
	local t = if length > 1e-9 then math.clamp(ap:Dot(ab) / length, 0, 1) else 0
	return (ap - ab * t).Magnitude
end

-- A cylinder part's CFrame standing upright at `center` (cylinders run along X).
local function upright(center: Vector3): CFrame
	return CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
end

local function isBot(player: any): boolean
	return BotRegistry.IsBot(player)
end

-- Sets up BODY_GROUP's collisions; false if it can't (then everyone collides as usual).
local function setUpBodies(): boolean
	local ok = pcall(function()
		for _, group in { BODY_GROUP, PEOPLE_GROUP } do
			if not PhysicsService:IsCollisionGroupRegistered(group) then
				PhysicsService:RegisterCollisionGroup(group)
			end
		end
		PhysicsService:CollisionGroupSetCollidable(BODY_GROUP, PEOPLE_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(BODY_GROUP, BODY_GROUP, false)
	end)
	return ok
end

local function pingOf(player: any): number
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and type(ping) == "number" then math.clamp(ping, 0, 0.4) else 0.05
end

-- The jaws: how far `point` is from a chomp made at `from` facing `look` (flat).
function SharkBait.JawDistance(point: Vector3, from: Vector3, look: Vector3): number
	return segmentDistance(point, from + look * SharkBait.JAW_NEAR, from + look * SharkBait.JAW_FAR)
end

-- Whether a swimmer's middle moving from `a` to `b` passed within `reach` of a coin at `coin`.
function SharkBait.Swept(a: Vector3, b: Vector3, coin: Vector3, reach: number): boolean
	for step = 0, 5 do
		local p = a:Lerp(b, step / 5)
		local dy = coin.Y - p.Y
		if dy >= -SharkBait.GRAB_BELOW and dy <= SharkBait.GRAB_ABOVE and flatDistance(p, coin) <= reach then
			return true
		end
	end
	-- The closest flat approach between the samples, at the height it happened.
	local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
	local length = ab:Dot(ab)
	if length > 1e-6 then
		local t = math.clamp(Vector2.new(coin.X - a.X, coin.Z - a.Z):Dot(ab) / length, 0, 1)
		local p = a:Lerp(b, t)
		local dy = coin.Y - p.Y
		if dy >= -SharkBait.GRAB_BELOW and dy <= SharkBait.GRAB_ABOVE and flatDistance(p, coin) <= reach then
			return true
		end
	end
	return false
end

function SharkBait:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn" -- only a chomp puts a swimmer out; a reset comes back on a raft
	ctx.EndWhenOneLeft = false
	local origin = ctx.Origin.Position
	self.origin = origin
	self.deckY = origin.Y + SharkBait.DECK
	self.waterY = origin.Y + SharkBait.WATER
	self.floorY = origin.Y + SharkBait.SEA_FLOOR
	ctx.KillY = origin.Y - 50 -- under the shark's belly (POCKET)
	ctx.Arena:SetAttribute("Center", origin)
	self.role = {} :: { [any]: string }
	self.sharks = {} :: { any }
	self.gulped = {} :: { [any]: number } -- swallowed swimmers: when they're spat out
	self.bellySpot = {} :: { [any]: number } -- and where each waits in the belly
	self.chomped = {} :: { [any]: number } -- how often each swimmer was swallowed
	self.wet = {} :: { [any]: boolean }
	self.spots = {} :: { [any]: Vector3 } -- each swimmer's middle at the last grab check
	self.splashAt = {} :: { [any]: number }
	self.wetSince = {} :: { [any]: number }
	self.coins = {} :: { [number]: Coin }
	self.coinId = 0
	self.coinsDirty = true
	self.raftsDirty = true
	self.lastPublish = 0
	self.nextChomp = {} :: { [any]: number }
	self.chomps = {} :: { [any]: number }
	self.dunks = {} :: { [any]: number }
	self.haul = 0
	self.goal = 1
	self.swimmerCount = 0
	self.chests = 0
	self.rush = false
	self.ended = false
	self.won = nil :: string?
	self.bodies = setUpBodies()

	self:_buildRafts()
	self:_buildArena()

	-- Roles: one shark under seven players, two from seven on; everyone else swims. (A lone player
	-- in Studio is the shark, so they can try the jaws; bots fill real rounds.)
	local players = ctx:GetPlayers()
	for index = #players, 2, -1 do
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local sharkCount = if #players >= 7 then 2 else 1
	local sharkAngle = rng:NextNumber(0, math.pi * 2)
	local spawns = {}
	local swimmerIndex = 0
	for index, player in players do
		if index <= sharkCount then
			table.insert(self.sharks, player)
			self.role[player] = "Shark"
			self.chomps[player] = 0
			self.dunks[player] = 0
			ctx:SetTeam(player, SharkBait.SHARKS)
			ctx:SetPlayerShared(player, "Role", "Shark")
			ctx:SetScoreText(player, "0 chomps")
			spawns[index] = self:_sharkSpot(sharkAngle + (index - 1) / sharkCount * math.pi * 2)
		else
			swimmerIndex += 1
			self.role[player] = "Swimmer"
			ctx:SetTeam(player, SharkBait.SWIMMERS)
			ctx:SetPlayerShared(player, "Role", "Swimmer")
			ctx:SetScoreText(player, "0 coins")
			spawns[index] = self:_swimmerSpot(swimmerIndex)
		end
	end

	-- Bring a shark's own character back as the shark, and a swimmer's on a raft that's up.
	ctx.Hooks.Respawn = function(player)
		if self.role[player] == "Shark" then
			return self:_sharkSpot(rng:NextNumber(0, math.pi * 2))
		end
		return self:_raftSpot()
	end
	ctx.Hooks.CharacterReady = function(player, character)
		self.spots[player] = nil
		if self.bodies and (isBot(player) or self.role[player] == "Shark") then
			self:_passThrough(character)
		end
		if self.role[player] == "Swimmer" then
			self.wet[player] = false -- a fresh character starts dry, up on a raft
			ctx:SetPlayerShared(player, "InWater", false)
		elseif self.role[player] == "Shark" then
			self:_dressShark(character)
			if ctx:IsRunning() then
				self:_sharkSpeed(player)
			end
		end
	end
	ctx.Hooks.PlayerLeft = function(player)
		local index = table.find(self.sharks, player)
		if index then
			table.remove(self.sharks, index)
		end
		self:_refresh()
	end
	ctx.Hooks.Eliminated = function()
		self:_refresh()
	end

	-- Everyone placed at once (frozen until GO); SpawnAll would pair points with its own order.
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
	for index = #self.sharks, 1, -1 do
		if not ctx:State(self.sharks[index]) then
			table.remove(self.sharks, index) -- never made it in
		end
	end

	for _, kind in SharkBait.Kinds do
		ctx:ShareTemplate(kind.Prop, MeshLibrary.Get(kind.Prop))
	end
	ctx:ShareTemplate("SharkBaitShark", MeshLibrary.Get("SharkBaitShark"))
	ctx:ShareTemplate("SharkBaitRaft", MeshLibrary.Get("SharkBaitRaft"))
	ctx:ShareTemplate("SharkBaitFloatie", MeshLibrary.Get("SharkBaitFloatie"))
	ctx:ShareTemplate("SharkBaitGull", MeshLibrary.Get("SharkBaitGull"))

	local rafts = {}
	for _, raft in self.rafts do
		table.insert(rafts, {
			X = round(raft.Center.X, 3),
			Z = round(raft.Center.Z, 3),
			R = raft.Radius,
			Yaw = round(raft.Yaw, 3),
		})
	end
	ctx:SetSharedJSON("Layout", {
		Origin = { origin.X, origin.Y, origin.Z },
		Deck = self.deckY,
		Water = self.waterY,
		Floor = self.floorY,
		SharkY = origin.Y + SharkBait.SHARK_Y,
		Wet = origin.Y + SharkBait.WET,
		Lagoon = SharkBait.LAGOON,
		Rafts = rafts,
		RaftMesh = { SharkBait.RAFT_MESH_RADIUS, SharkBait.RAFT_MESH_HEIGHT },
		Wobble = SharkBait.WOBBLE,
		Dunk = SharkBait.DUNK,
		Jaw = { SharkBait.JAW_NEAR, SharkBait.JAW_FAR, SharkBait.BITE_RADIUS },
		Grab = { SharkBait.GRAB_BELOW, SharkBait.GRAB_ABOVE },
		Reach = { SharkBait.Kinds[1].Reach, SharkBait.Kinds[2].Reach, SharkBait.Kinds[3].Reach },
		BiteCooldown = SharkBait.BITE_COOLDOWN,
		RamCooldown = SharkBait.RAM_COOLDOWN,
	})
	local ids = {}
	for _, shark in self.sharks do
		table.insert(ids, shark.UserId)
	end
	ctx:SetSharedJSON("Sharks", ids)
	self:_publishRafts()
	self:_publishCoins()
	ctx:SetStatus(if #self.sharks > 1 then "🦈 2 SHARKS are circling!" else "🦈 A SHARK is circling!")
end

-- The rafts -----------------------------------------------------------------------------------------

function SharkBait:_buildRafts()
	local ctx = self.context
	local origin: Vector3 = self.origin
	local height = SharkBait.DECK - SharkBait.SEA_FLOOR
	self.rafts = {} :: { Raft }
	local function add(offset: Vector3, radius: number)
		local center = Vector3.new(origin.X + offset.X, self.deckY, origin.Z + offset.Z)
		-- Its collider: from the hidden sea floor up to the deck, so nobody slips under it.
		local collider = Build.Part({
			Name = "RaftCollider",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, radius * 2, radius * 2),
			CFrame = upright(center - Vector3.new(0, height / 2, 0)),
			Transparency = 1,
			CastShadow = false,
			CanTouch = false,
			Parent = ctx.Arena,
		})
		table.insert(self.rafts, {
			Index = #self.rafts + 1,
			Center = center,
			Radius = radius,
			Yaw = decor:NextNumber(0, math.pi * 2),
			State = SharkBait.READY,
			Since = 0,
			SafeUntil = 0,
			Collider = collider,
			Neighbours = {},
		})
	end
	add(Vector3.zero, SharkBait.CENTER_RADIUS)
	for index = 0, 5 do
		local angle = index / 6 * math.pi * 2 + math.pi / 6
		add(Vector3.new(math.cos(angle), 0, math.sin(angle)) * SharkBait.RING, SharkBait.RING_RADIUS)
	end
	-- Neighbours: rafts a hop apart (the middle one and both ring rafts beside each ring raft).
	for _, raft in self.rafts do
		for _, other in self.rafts do
			if other ~= raft and flatDistance(raft.Center, other.Center) - raft.Radius - other.Radius < 7 then
				table.insert(raft.Neighbours, other.Index)
			end
		end
	end
end

-- Which raft (if any) has `position` over its deck (within `margin` past its edge).
function SharkBait:RaftUnder(position: Vector3, margin: number?): Raft?
	for _, raft in self.rafts do
		if flatDistance(position, raft.Center) <= raft.Radius + (margin or 0) then
			return raft
		end
	end
	return nil
end

function SharkBait:IsReady(raft: Raft): boolean
	return raft.State == SharkBait.READY
end

function SharkBait:ReadyCount(): number
	local count = 0
	for _, raft in self.rafts do
		if raft.State == SharkBait.READY then
			count += 1
		end
	end
	return count
end

-- A swimmer's spawn: spread over the rafts, a couple of studs from each deck's middle.
function SharkBait:_swimmerSpot(index: number): CFrame
	local raft = self.rafts[(index - 1) % #self.rafts + 1]
	local slot = (index - 1) // #self.rafts
	local angle = raft.Index * 1.3 + slot * 2.1
	local distance = if slot == 0 and raft.Index > 1 then 0 else 3
	local position = raft.Center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
	local look = Vector3.new(self.origin.X, position.Y, self.origin.Z)
	if flatDistance(position, look) < 0.5 then
		look = position + Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(position, look)
end

-- A spot on a raft that's up (for a swimmer coming back after a reset).
function SharkBait:_raftSpot(): CFrame
	local choices = {}
	for _, raft in self.rafts do
		if raft.State == SharkBait.READY then
			table.insert(choices, raft)
		end
	end
	local raft = if #choices > 0 then choices[rng:NextInteger(1, #choices)] else self.rafts[1]
	local angle = rng:NextNumber(0, math.pi * 2)
	return CFrame.new(raft.Center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * raft.Radius * 0.4)
end

-- A shark's spot in open water, on the sea floor, facing round the lagoon.
function SharkBait:_sharkSpot(angle: number): CFrame
	local origin: Vector3 = self.origin
	local distance = SharkBait.RING + SharkBait.RING_RADIUS + 8
	local position =
		Vector3.new(origin.X + math.cos(angle) * distance, self.floorY, origin.Z + math.sin(angle) * distance)
	return CFrame.lookAt(position, position + Vector3.new(-math.sin(angle), 0, math.cos(angle)))
end

-- The cove ----------------------------------------------------------------------------------------

-- The look: a sunny tropical cove. Turquoise water over a pale sand lagoon full of coral, kelp and
-- starfish (seen through the water), a ring of floats and warning buoys round the lagoon, sand bars
-- with palms and a lifeguard tower, a half-sunk pirate wreck, a lighthouse on its rock, limestone
-- sea stacks and jungle islands on the horizon.
function SharkBait:_buildArena()
	local ctx = self.context
	local arena = ctx.Arena
	local origin: Vector3 = self.origin
	local waterY: number = self.waterY
	local function at(x: number, z: number, y: number): Vector3
		return Vector3.new(origin.X + x, y, origin.Z + z)
	end
	local function around(angle: number, distance: number, y: number): Vector3
		return at(math.cos(angle) * distance, math.sin(angle) * distance, y)
	end
	local function facing(position: Vector3): CFrame
		return CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z))
	end

	-- The sea: clear turquoise water over a pale sand lagoon that drops to deep blue past the reef.
	Build.Decor({
		Name = "Sea",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 2048, 2048),
		CFrame = upright(Vector3.new(origin.X, waterY - 0.5, origin.Z)),
		Color = rgb(36, 182, 214),
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		Reflectance = 0.06,
		Parent = arena,
	})
	local bedY = origin.Y + SharkBait.SEA_BED
	Build.Decor({
		Name = "LagoonSand",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 150, 150),
		CFrame = upright(Vector3.new(origin.X, bedY - 1, origin.Z)),
		Color = rgb(232, 216, 168),
		Material = Enum.Material.Sand,
		Parent = arena,
	})
	Build.Decor({
		Name = "ReefSlope",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 196, 196),
		CFrame = upright(Vector3.new(origin.X, bedY - 4.6, origin.Z)),
		Color = rgb(40, 150, 170),
		Material = Enum.Material.Sand,
		Parent = arena,
	})
	Build.Decor({
		Name = "DeepSea",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 2048, 2048),
		CFrame = upright(Vector3.new(origin.X, bedY - 12, origin.Z)),
		Color = rgb(18, 84, 150),
		Material = Enum.Material.Sand,
		Parent = arena,
	})
	-- Moving water: ripple lines drifting over the surface, light dancing on the lagoon floor.
	local function textured(name: string, size: number, y: number, image: string, layers: { { number } })
		local plane = Build.Decor({
			Name = name,
			Size = Vector3.new(size, 0.05, size),
			CFrame = CFrame.new(origin.X, y, origin.Z),
			Transparency = 1,
			Parent = arena,
		})
		for index, layer in layers do
			local texture = Instance.new("Texture")
			texture.Name = `{name}{index}`
			texture.Texture = image
			texture.Face = Enum.NormalId.Top
			texture.StudsPerTileU = layer[1]
			texture.StudsPerTileV = layer[1]
			texture.Transparency = layer[2]
			texture.Color3 = Color3.fromRGB(layer[3], layer[4], layer[5])
			texture.Parent = plane
		end
	end
	textured("Ripples", 260, waterY + 0.06, SharkBait.Textures.Ripples, {
		{ 34, 0.5, 255, 255, 255 },
		{ 53, 0.68, 220, 248, 255 },
	})
	textured("Caustics", 150, bedY + 0.06, SharkBait.Textures.Caustics, {
		{ 17, 0.3, 235, 255, 250 },
		{ 26, 0.5, 210, 245, 255 },
	})

	-- The shark's belly: a hidden ledge under the sea bed, where swallowed swimmers wait (out of sight
	-- under the deep sea floor) until they're spat out.
	Build.Part({
		Name = "Belly",
		Size = Vector3.new(24, 1, 20),
		CFrame = CFrame.new(origin + Vector3.new(0, POCKET - 0.5, 0)),
		Transparency = 1,
		CastShadow = false,
		CanTouch = false,
		Parent = arena,
	})
	-- The hidden floor anyone in the water stands on, and the float line everyone stays inside.
	Build.Part({
		Name = "SeaFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, (SharkBait.LAGOON + 8) * 2, (SharkBait.LAGOON + 8) * 2),
		CFrame = upright(Vector3.new(origin.X, self.floorY - 1, origin.Z)),
		Transparency = 1,
		CastShadow = false,
		CanTouch = false,
		Parent = arena,
	})
	local walls = Build.Folder("Walls", arena)
	local segments = 40
	for index = 0, segments - 1 do
		local angle = (index + 0.5) / segments * math.pi * 2
		local width = 2 * (SharkBait.LAGOON + 1) * math.sin(math.pi / segments) + 0.6
		local height = self.deckY + 16 - self.floorY
		local position = around(angle, SharkBait.LAGOON + 1, self.floorY + height / 2)
		Build.Barrier({
			Name = "Edge",
			Size = Vector3.new(width, height, 1),
			CFrame = facing(position),
			Parent = walls,
		})
	end
	MeshLibrary.Get("SharkBaitFloatLine", {
		CFrame = CFrame.new(origin.X, waterY - 0.55, origin.Z),
		Parent = arena,
	})
	local floats = Build.Folder("Floats", arena) -- the clients bob everything in here
	for index = 0, 5 do
		local spot = around((index + 0.25) / 6 * math.pi * 2, SharkBait.LAGOON + 5, waterY - 1.2)
		MeshLibrary.Get("SharkBaitBuoy", {
			CFrame = CFrame.new(spot) * CFrame.Angles(0, decor:NextNumber(0, math.pi * 2), 0),
			Parent = floats,
		})
	end

	-- Under the water: coral heads, kelp and starfish on the lagoon sand (never right under a raft's
	-- middle, where the deck would hide them).
	local reef = Build.Folder("Reef", arena)
	local taken: { { Spot: Vector3, Radius: number } } = {}
	local function free(spot: Vector3, radius: number): boolean
		for _, other in taken do
			if flatDistance(other.Spot, spot) < other.Radius + radius then
				return false
			end
		end
		return true
	end
	for _, raft in self.rafts do
		table.insert(taken, { Spot = raft.Center, Radius = raft.Radius * 0.55 })
	end
	local function scatter(prop: string, count: number, r0: number, r1: number, size: number, scale: { number })
		local placed = 0
		for _ = 1, count * 12 do
			if placed >= count then
				break
			end
			local spot = around(decor:NextNumber(0, math.pi * 2), decor:NextNumber(r0, r1), bedY)
			if free(spot, size) then
				table.insert(taken, { Spot = spot, Radius = size })
				placed += 1
				MeshLibrary.Get(prop, {
					Scale = decor:NextNumber(scale[1], scale[2]),
					CFrame = CFrame.new(spot) * CFrame.Angles(0, decor:NextNumber(0, math.pi * 2), 0),
					Parent = reef,
				})
			end
		end
	end
	scatter("SharkBaitCoral", 14, 8, 66, 5, { 0.8, 1.4 })
	scatter("SharkBaitKelp", 12, 14, 70, 3, { 0.7, 1.1 })
	scatter("SharkBaitStarfish", 16, 4, 60, 1.6, { 0.9, 1.4 })

	-- Sand bars with palms round the lagoon: one with the lifeguard tower, one with parasols, and a
	-- pool float that drifted off (nobody's swimming out to get it).
	local bars = {
		{ Angle = math.rad(-35), Distance = 78, Yaw = 0.4, Scale = 1.1 },
		{ Angle = math.rad(70), Distance = 84, Yaw = 2.1, Scale = 0.9 },
		{ Angle = math.rad(200), Distance = 92, Yaw = -0.8, Scale = 1 },
	}
	for index, bar in bars do
		local spot = around(bar.Angle, bar.Distance, waterY - 2)
		local base = CFrame.new(spot) * CFrame.Angles(0, bar.Yaw, 0)
		MeshLibrary.Get("SharkBaitSandBar", { Scale = bar.Scale, CFrame = base, Parent = arena })
		-- A spot on its sand (x, z from its middle, unscaled): the mound's base is 2 studs under the
		-- water and it rises about 3, so things stand a little under its crest.
		local function onBar(x: number, z: number): Vector3
			local p = (base * CFrame.new(x * bar.Scale, 0, z * bar.Scale)).Position
			return Vector3.new(p.X, waterY - 2 + 3 * bar.Scale * 0.78, p.Z)
		end
		for k, offset in { { -9, 3 }, { 8, -2 }, { 13, 4 } } do
			MeshLibrary.Get("BumperPalm", {
				Scale = 0.85 + ((index + k) % 3) * 0.12,
				CFrame = CFrame.new(onBar(offset[1], offset[2])) * CFrame.Angles(0, k * 2.3 + index, 0),
				Parent = arena,
			})
		end
		if index == 1 then
			MeshLibrary.Get("SharkBaitHut", { CFrame = facing(onBar(-1, -2)), Parent = arena })
		elseif index == 2 then
			for k, offset in { { -3, -4 }, { 4, -3 } } do
				MeshLibrary.Get("BumperParasol", {
					Colors = { CanopyA = if k == 1 then rgb(255, 92, 126) else rgb(70, 190, 255) },
					CFrame = CFrame.new(onBar(offset[1], offset[2])) * CFrame.Angles(0, k * 1.7, 0),
					Parent = arena,
				})
			end
		end
	end
	local flamingo = around(math.rad(120), 62, waterY - 0.6 * 1.5)
	MeshLibrary.Get("BumperFlamingo", {
		Scale = 1.5,
		CFrame = CFrame.new(flamingo) * CFrame.Angles(0, 0.7, 0),
		Parent = floats,
	})

	-- The wreck, the lighthouse and the sea stacks.
	local wreck = around(math.rad(150), 100, waterY - 8)
	MeshLibrary.Get("SharkBaitShipwreck", {
		CFrame = CFrame.lookAt(wreck, Vector3.new(origin.X, wreck.Y, origin.Z)) * CFrame.Angles(0, math.rad(70), 0),
		Parent = arena,
	})
	local lighthouse = around(math.rad(-80), 135, waterY - 4)
	MeshLibrary.Get("SharkBaitLighthouse", { CFrame = facing(lighthouse), Parent = arena })
	local stacks = {
		{ math.rad(25), 170, 1.1 },
		{ math.rad(-130), 185, 1.3 },
		{ math.rad(105), 205, 1.0 },
		{ math.rad(-15), 240, 1.5 },
		{ math.rad(235), 225, 1.2 },
		{ math.rad(165), 250, 1.4 },
	}
	for _, stack in stacks do
		MeshLibrary.Get("SharkBaitSeaStack", {
			Scale = stack[3],
			CFrame = CFrame.new(around(stack[1], stack[2], waterY - 4 * stack[3])) * CFrame.Angles(0, stack[1] * 3, 0),
			Parent = arena,
		})
	end
	-- Jungle islands on the horizon close off the view, with gaps of open sea between them.
	local far = 6
	for index = 0, far - 1 do
		local angle = (index + 0.3 + decor:NextNumber(-0.15, 0.15)) / far * math.pi * 2
		local scale = decor:NextNumber(1, 1.4)
		MeshLibrary.Get(if index % 2 == 0 then "BumperFarIslandA" else "BumperFarIslandB", {
			Scale = scale,
			CFrame = CFrame.new(around(angle, decor:NextNumber(480, 620), waterY - 6 * scale))
				* CFrame.Angles(0, -angle + math.pi / 2 + decor:NextNumber(-0.4, 0.4), 0),
			Parent = arena,
		})
	end
end

-- Sharks --------------------------------------------------------------------------------------------

-- The shark's own body is hidden (every client draws the shark mesh where it swims); it keeps its
-- nameplate. It walks the sea floor, fast, and can't jump onto a raft.
function SharkBait:_dressShark(character: Model)
	character:SetAttribute("PP_Shark", true)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CastShadow = false
		elseif descendant:IsA("Decal") then
			descendant.Transparency = 1 -- the face
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") then
			descendant.Enabled = false
		end
	end
end

-- A bot's or a shark's character into BODY_GROUP, parts it gets later too (deferred: after the
-- lobby's own handler, which puts a player's new parts in PP_Players).
function SharkBait:_passThrough(character: Model)
	local function join(item: Instance)
		if item:IsA("BasePart") then
			item.CollisionGroup = BODY_GROUP
		end
	end
	for _, item in character:GetDescendants() do
		join(item)
	end
	self.context:Track(character.DescendantAdded:Connect(function(item)
		task.defer(join, item)
	end))
end

function SharkBait:_sharkSpeed(player: any)
	local _, humanoid = self.context:GetCharacter(player)
	if humanoid then
		humanoid.WalkSpeed = SharkBait.SHARK_SPEED
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	end
end

function SharkBait:IsShark(player: any): boolean
	return self.role[player] == "Shark"
end

function SharkBait:IsGulped(player: any): boolean
	return self.gulped[player] ~= nil
end

function SharkBait:InWater(position: Vector3): boolean
	return position.Y < self.origin.Y + SharkBait.WET
end

-- When a shark can chomp next (server time).
function SharkBait:ChompReadyAt(player: any): number
	return self.nextChomp[player] or 0
end

-- Bots can't turn themselves to face a chomp the way a player's device does: turn them here.
function SharkBait:Aim(bot: any, target: Vector3)
	if not isBot(bot) then
		return
	end
	local character, _, root = self.context:GetCharacter(bot)
	if character and root then
		local at = root.Position
		if flatDistance(at, target) > 0.2 then
			character:PivotTo(CFrame.lookAt(at, Vector3.new(target.X, at.Y, target.Z)))
		end
	end
end

-- The raft (if any) a chomp from `from` facing `look` reaches: the nearest one up and not resting.
function SharkBait:RaftInReach(from: Vector3, look: Vector3, now: number): Raft?
	local best, bestDistance = nil, math.huge
	for _, raft in self.rafts do
		if raft.State ~= SharkBait.READY or now < raft.SafeUntil then
			continue
		end
		if SharkBait.JawDistance(raft.Center, from, look) <= raft.Radius + SharkBait.RAM_REACH then
			local distance = flatDistance(from, raft.Center)
			if distance < bestDistance then
				best, bestDistance = raft, distance
			end
		end
	end
	return best
end

function SharkBait:_chomp(shark: any)
	local ctx = self.context
	local _, _, root = ctx:GetCharacter(shark)
	if not root then
		return
	end
	local now = ctx:Now()
	local from = root.Position
	local look = flatLook(root.CFrame)

	-- A swimmer in the water in reach: a bite (each judged by what their own screen showed).
	local victims = {}
	for _, swimmer in ctx:GetAlivePlayers() do
		if self.role[swimmer] ~= "Swimmer" or self.gulped[swimmer] then
			continue
		end
		local _, _, swimmerRoot = ctx:GetCharacter(swimmer)
		if
			swimmerRoot
			and self:InWater(swimmerRoot.Position)
			and SharkBait.JawDistance(swimmerRoot.Position, from, look) <= SharkBait.BITE_RADIUS + BITE_SLACK
		then
			table.insert(victims, swimmer)
		end
	end
	local raft = nil
	if #victims == 0 then
		raft = self:RaftInReach(from, look, now)
		if raft and self:ReadyCount() <= SharkBait.MIN_READY then
			raft = nil -- keep somewhere to stand
		end
	end
	local cooldown = if raft then SharkBait.RAM_COOLDOWN else SharkBait.BITE_COOLDOWN
	self.nextChomp[shark] = math.max(now, self.nextChomp[shark] or 0) + cooldown
	ctx:SetPlayerShared(shark, "ChompAt", self.nextChomp[shark])
	ctx:SetPlayerShared(shark, "ChompLength", cooldown)
	ctx:Fire(
		nil,
		"Chomp",
		shark.UserId,
		round(from.X, 2),
		round(from.Z, 2),
		round(look.X, 3),
		round(look.Z, 3),
		if raft then raft.Index else 0
	)
	if raft then
		self:_wobble(raft, shark)
		return
	end
	for _, swimmer in victims do
		local lag = pingOf(swimmer) / 2
		ctx:Delay(lag, function()
			local first = self:_jawReach(swimmer, from, look)
			ctx:Delay(JUDGE_SPREAD, function()
				local second = self:_jawReach(swimmer, from, look)
				if first <= SharkBait.BITE_RADIUS and second <= SharkBait.BITE_RADIUS + BITE_SLACK then
					self:_gulp(swimmer, shark)
				end
			end)
		end)
	end
end

-- How far a swimmer's middle is from a chomp's jaws (math.huge unless they're in the water).
function SharkBait:_jawReach(swimmer: any, from: Vector3, look: Vector3): number
	local _, _, root = self.context:GetCharacter(swimmer)
	if not root or self.gulped[swimmer] or not self:InWater(root.Position) then
		return math.huge
	end
	return SharkBait.JawDistance(root.Position, from, look)
end

-- Swallowed: the swimmer waits in the shark's belly (a hidden ledge under the sea bed; their own
-- screen follows the shark), the swimmers' haul loses CHOMP_COST coins, and a moment later the
-- shark spits them back out onto a raft.
function SharkBait:_gulp(swimmer: any, shark: any)
	local ctx = self.context
	if self.gulped[swimmer] or self.ended or not ctx:IsAlive(swimmer) then
		return
	end
	local character, _, root = ctx:GetCharacter(swimmer)
	if not character or not root then
		return
	end
	local at = root.Position
	self.gulped[swimmer] = ctx:Now() + GULP_TIME
	self.wet[swimmer] = false
	self.spots[swimmer] = nil
	ctx:SetPlayerShared(swimmer, "InWater", false)
	local lost = math.min(SharkBait.CHOMP_COST, self.haul)
	if lost > 0 then
		self.haul -= lost
		ctx:SetShared("Haul", self.haul)
		ctx:AddTeamScore(SharkBait.SWIMMERS, -lost)
	end
	self.chomped[swimmer] = (self.chomped[swimmer] or 0) + 1
	self:_swimmerText(swimmer)
	ctx:AddTeamScore(SharkBait.SHARKS, 1)
	if shark and self.chomps[shark] then
		self.chomps[shark] += 1
		ctx:AddScore(shark, 5)
		self:_sharkText(shark)
	end
	ctx:Fire(nil, "Eaten", swimmer.UserId, if shark then shark.UserId else 0, round(at.X, 2), round(at.Z, 2), lost)
	local taken = {}
	for _, index in self.bellySpot do
		taken[index] = true
	end
	local spot = 1
	while taken[spot] and spot < BELLY_SPOTS do
		spot += 1
	end
	self.bellySpot[swimmer] = spot
	local column, row = (spot - 1) % 4, (spot - 1) // 4
	character:PivotTo(CFrame.new(self.origin + Vector3.new(-7.5 + 5 * column, POCKET + SharkBait.HIP, -5 + 5 * row)))
	ctx:Freeze(swimmer, true)
	ctx:Delay(GULP_TIME, function()
		self:_spitOut(swimmer)
	end)
	self:_status()
end

-- Back out of the belly, onto a raft that's up.
function SharkBait:_spitOut(swimmer: any)
	local ctx = self.context
	if not self.gulped[swimmer] then
		return
	end
	self.gulped[swimmer] = nil
	self.bellySpot[swimmer] = nil
	self.spots[swimmer] = nil
	local character = ctx:GetCharacter(swimmer)
	if not character or not ctx:IsAlive(swimmer) then
		return
	end
	local spot = self:_raftSpot()
	character:PivotTo(spot + Vector3.new(0, SharkBait.HIP, 0))
	ctx:Freeze(swimmer, false)
	ctx:Fire(nil, "SpatOut", swimmer.UserId, round(spot.X, 2), round(spot.Z, 2))
end

-- The standings' line (short: it has to fit the phone leaderboard; the results say more).
function SharkBait:_swimmerText(swimmer: any)
	local state = self.context:State(swimmer)
	local coins = if state then state.Score else 0
	self.context:SetScoreText(swimmer, if coins == 1 then "1 coin" else `{coins} coins`)
end

function SharkBait:_sharkText(shark: any)
	local chomps = self.chomps[shark] or 0
	self.context:SetScoreText(shark, if chomps == 1 then "1 chomp" else `{chomps} chomps`)
end

-- Rafts: wobble, flip, come back up ----------------------------------------------------------------

function SharkBait:_wobble(raft: Raft, shark: any)
	local ctx = self.context
	raft.State = SharkBait.WOBBLING
	raft.Since = ctx:Now()
	self.raftsDirty = true
	self:_publishRafts()
	ctx:Delay(SharkBait.WOBBLE, function()
		self:_flip(raft, shark)
	end)
end

-- Whether `position` (a swimmer's middle) is up on `raft` (or just over it), not in the water.
function SharkBait:_onRaft(raft: Raft, position: Vector3): boolean
	return flatDistance(position, raft.Center) <= raft.Radius + OVERHANG
		and position.Y > self.waterY - 0.5
		and position.Y < self.deckY + 14
end

function SharkBait:_flip(raft: Raft, shark: any)
	local ctx = self.context
	local now = ctx:Now()
	raft.State = SharkBait.FLIPPED
	raft.Since = now
	raft.Collider.CanCollide = false
	self.raftsDirty = true
	self:_publishRafts()
	ctx:Sound("Splash")

	-- Its coins spill into the water round it.
	for _, coin in self.coins do
		if coin.Raft == raft.Index then
			local offset = flat(coin.Position - raft.Center)
			local dir = if offset.Magnitude > 0.2 then offset.Unit else self:_randomDir()
			coin.From = coin.Position
			coin.SpillAt = now
			coin.Raft = 0
			coin.Position = self:_waterSpotNear(raft, dir)
			coin.Born = now + SPILL_TIME
			coin.Expires = now + SPILL_TIME + WATER_LIFE
			self.coinsDirty = true
		end
	end

	-- Everyone on it goes in: each judged by what their own screen showed (see the top).
	for _, swimmer in ctx:GetAlivePlayers() do
		if self.role[swimmer] ~= "Swimmer" or self.gulped[swimmer] then
			continue
		end
		local lag = pingOf(swimmer) / 2
		ctx:Delay(lag, function()
			local _, _, root = ctx:GetCharacter(swimmer)
			if not root or not self:_onRaft(raft, root.Position) then
				return
			end
			ctx:Delay(JUDGE_SPREAD, function()
				local _, _, later = ctx:GetCharacter(swimmer)
				if later and self:_onRaft(raft, later.Position) and not self.gulped[swimmer] then
					self:_toss(swimmer, raft, shark)
				end
			end)
		end)
	end
	ctx:Delay(SharkBait.DUNK, function()
		self:_surface(raft)
	end)
end

function SharkBait:_randomDir(): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

-- A spot in the water just off `raft`'s edge in direction `dir`, clear of the other rafts.
function SharkBait:_waterSpotNear(raft: Raft, dir: Vector3): Vector3
	for attempt = 0, 7 do
		local turn = (if attempt % 2 == 0 then 1 else -1) * math.ceil(attempt / 2) * 0.45
		local d = CFrame.Angles(0, turn, 0):VectorToWorldSpace(dir)
		local spot = raft.Center + d * (raft.Radius + rng:NextNumber(2.4, 6))
		spot = Vector3.new(spot.X, self.waterY + SharkBait.WATER_COIN, spot.Z)
		local clear = flatDistance(spot, self.origin) < SharkBait.LAGOON - 3
		for _, other in self.rafts do
			if other ~= raft and flatDistance(spot, other.Center) < other.Radius + 1.6 then
				clear = false
			end
		end
		if clear then
			return spot
		end
	end
	local spot = raft.Center + dir * (raft.Radius + 2.5)
	return Vector3.new(spot.X, self.waterY + SharkBait.WATER_COIN, spot.Z)
end

-- Throws a swimmer off a flipping raft into the water.
function SharkBait:_toss(swimmer: any, raft: Raft, shark: any)
	local ctx = self.context
	local character, _, root = ctx:GetCharacter(swimmer)
	if not character or not root then
		return
	end
	local offset = flat(root.Position - raft.Center)
	local dir = if offset.Magnitude > 0.3 then offset.Unit else self:_randomDir()
	if physics then
		ctx:Knockback(swimmer, dir * TOSS_OUT + Vector3.new(0, TOSS_UP, 0), 0.4)
	else
		-- No physics on the test servers: put them in the water just off the edge.
		local spot = self:_waterSpotNear(raft, dir)
		character:PivotTo(
			CFrame.lookAt(
				Vector3.new(spot.X, self.floorY + SharkBait.HIP, spot.Z),
				Vector3.new(raft.Center.X, self.floorY + SharkBait.HIP, raft.Center.Z)
			)
		)
	end
	ctx:Fire(nil, "Tossed", swimmer.UserId, raft.Index)
	if shark and self.dunks[shark] then
		self.dunks[shark] += 1
		ctx:AddScore(shark, 1)
		self:_sharkText(shark)
	end
end

function SharkBait:_surface(raft: Raft)
	local ctx = self.context
	local now = ctx:Now()
	raft.State = SharkBait.READY
	raft.Since = now
	raft.SafeUntil = now + SharkBait.SAFE
	-- Whoever is in the water where it comes up: swimmers are scooped up onto the deck, sharks are
	-- pushed out past its edge (a shark never gets onto a raft).
	for _, player in ctx:GetAlivePlayers() do
		local character, _, root = ctx:GetCharacter(player)
		if not character or not root or self.gulped[player] then
			continue
		end
		local position = root.Position
		local offset = flat(position - raft.Center)
		if offset.Magnitude > raft.Radius + 0.4 or position.Y > self.deckY + 0.5 then
			continue
		end
		local dir = if offset.Magnitude > 0.2 then offset.Unit else self:_randomDir()
		if self.role[player] == "Shark" then
			local out = raft.Center + dir * (raft.Radius + 2.6)
			local spot = Vector3.new(out.X, self.floorY + SharkBait.HIP, out.Z)
			character:PivotTo(CFrame.lookAt(spot, spot + dir))
		else
			local spot = raft.Center + dir * math.min(offset.Magnitude, raft.Radius - 1.2)
			character:PivotTo(CFrame.new(spot.X, self.deckY + SharkBait.HIP, spot.Z) * root.CFrame.Rotation)
		end
	end
	raft.Collider.CanCollide = true
	self.raftsDirty = true
	self:_publishRafts()
end

-- Coins ----------------------------------------------------------------------------------------------

function SharkBait:_addCoin(kind: number, position: Vector3, raftIndex: number, life: number)
	local now = self.context:Now()
	self.coinId += 1
	self.coins[self.coinId] = {
		Id = self.coinId,
		Kind = kind,
		Position = position,
		Raft = raftIndex,
		Born = now + POP_IN,
		Expires = if life > 0 then now + POP_IN + life else 0,
	}
	self.coinsDirty = true
end

function SharkBait:CoinCount(): number
	local count = 0
	for _ in self.coins do
		count += 1
	end
	return count
end

local function clearOfCoins(coins: { [number]: Coin }, spot: Vector3, spacing: number): boolean
	for _, coin in coins do
		if flatDistance(coin.Position, spot) < spacing and math.abs(coin.Position.Y - spot.Y) < 3 then
			return false
		end
	end
	return true
end

-- A spot in the water close to the rafts (a quick dip from a deck): in a gap between two
-- neighbours, or in the ring of water round the middle raft.
function SharkBait:_nearSpot(): Vector3?
	if rng:NextNumber() < 0.3 then
		local middle = self.rafts[1]
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = (SharkBait.CENTER_RADIUS + SharkBait.RING - SharkBait.RING_RADIUS) / 2
		return Vector3.new(
			middle.Center.X + math.cos(angle) * radius,
			self.waterY + SharkBait.WATER_COIN,
			middle.Center.Z + math.sin(angle) * radius
		)
	end
	local raft = self.rafts[rng:NextInteger(1, #self.rafts)]
	local index = raft.Neighbours[rng:NextInteger(1, math.max(1, #raft.Neighbours))]
	local other = if index then self.rafts[index] else nil
	if not other then
		return nil
	end
	local dir = flat(other.Center - raft.Center).Unit
	local gap = flatDistance(raft.Center, other.Center) - raft.Radius - other.Radius
	local spot = raft.Center + dir * (raft.Radius + gap / 2)
	return Vector3.new(spot.X, self.waterY + SharkBait.WATER_COIN, spot.Z)
end

-- One new coin. A third or so on the decks (safe and small), a quarter hanging over the gaps (grab
-- them mid-hop) and the rest in the water, where the shark is: half close to the rafts, half out
-- in the open, where pearls are likelier. The COIN RUSH puts more of them in the water.
function SharkBait:_spawnCoin()
	local deckShare = if self.rush then 0.22 else 0.35
	local waterShare = if self.rush then 0.55 else 0.4
	for _ = 1, 8 do
		local roll = rng:NextNumber()
		if roll < deckShare then
			local raft = self.rafts[rng:NextInteger(1, #self.rafts)]
			if raft.State ~= SharkBait.READY then
				continue
			end
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = math.sqrt(rng:NextNumber()) * (raft.Radius - 1.6)
			local spot = raft.Center
				+ Vector3.new(math.cos(angle) * distance, SharkBait.DECK_COIN, math.sin(angle) * distance)
			if clearOfCoins(self.coins, spot, 2.4) then
				self:_addCoin(COIN, spot, raft.Index, 0)
				return
			end
		elseif roll < 1 - waterShare then
			local raft = self.rafts[rng:NextInteger(1, #self.rafts)]
			local index = raft.Neighbours[rng:NextInteger(1, math.max(1, #raft.Neighbours))]
			local other = if index then self.rafts[index] else nil
			if not other then
				continue
			end
			local dir = flat(other.Center - raft.Center).Unit
			local gap = flatDistance(raft.Center, other.Center) - raft.Radius - other.Radius
			local spot = raft.Center + dir * (raft.Radius + gap / 2) + Vector3.new(0, SharkBait.GAP_COIN, 0)
			if clearOfCoins(self.coins, spot, 2.4) then
				self:_addCoin(COIN, spot, 0, 0)
				return
			end
		else
			local near = rng:NextNumber() < 0.5
			local spot = if near then self:_nearSpot() else nil
			if not near then
				local angle = rng:NextNumber(0, math.pi * 2)
				local distance = rng:NextNumber(SharkBait.RING + SharkBait.RING_RADIUS + 3, SharkBait.LAGOON - 5)
				spot = Vector3.new(
					self.origin.X + math.cos(angle) * distance,
					self.waterY + SharkBait.WATER_COIN,
					self.origin.Z + math.sin(angle) * distance
				)
			end
			if spot and clearOfCoins(self.coins, spot, 3) then
				self:_addCoin(
					if rng:NextNumber() < (if near then 0.2 else 0.5) then PEARL else COIN,
					spot,
					0,
					WATER_LIFE
				)
				return
			end
		end
	end
end

function SharkBait:_spawnChest()
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = rng:NextNumber(SharkBait.RING + SharkBait.RING_RADIUS + 5, SharkBait.LAGOON - 6)
	local spot = Vector3.new(
		self.origin.X + math.cos(angle) * distance,
		self.waterY + SharkBait.WATER_COIN,
		self.origin.Z + math.sin(angle) * distance
	)
	self:_addCoin(CHEST, spot, 0, CHEST_LIFE)
	self.context:Announce("🧰 TREASURE CHEST in the water! +6", "reward", 3)
	self.context:Fire(nil, "Chest", round(spot.X, 2), round(spot.Z, 2))
end

function SharkBait:_grab(swimmer: any, id: number, coin: Coin)
	local ctx = self.context
	local kind = SharkBait.Kinds[coin.Kind]
	self.coins[id] = nil
	self.coinsDirty = true
	ctx:AddScore(swimmer, kind.Value)
	ctx:AddTeamScore(SharkBait.SWIMMERS, kind.Value)
	self.haul += kind.Value
	ctx:SetShared("Haul", self.haul)
	self:_swimmerText(swimmer)
	ctx:Fire(nil, "Grab", id, swimmer.UserId, kind.Value)
	if self.haul >= self.goal and not self.ended then
		self.ended = true
		self.won = SharkBait.SWIMMERS
		ctx:SetStatus("🏊 The swimmers hit the goal! SWIMMERS WIN!")
		ctx:Fire(nil, "Win", SharkBait.SWIMMERS)
		ctx:Delay(1.4, function()
			ctx:End("Goal")
		end)
	else
		self:_status()
	end
end

-- Shared state ----------------------------------------------------------------------------------------

function SharkBait:_publishRafts()
	local list = {}
	for _, raft in self.rafts do
		table.insert(list, { raft.State, round(raft.Since, 3), round(raft.SafeUntil, 3) })
	end
	self.context:SetSharedJSON("Rafts", list)
	self.raftsDirty = false
end

function SharkBait:_publishCoins()
	local list = {}
	for _, coin in self.coins do
		local p = coin.Position
		local entry = {
			coin.Id,
			coin.Kind,
			round(p.X, 2),
			round(p.Y, 2),
			round(p.Z, 2),
			round(coin.Born, 3),
			round(coin.Expires, 3),
		}
		if coin.From and coin.SpillAt then
			table.insert(entry, round(coin.From.X, 2))
			table.insert(entry, round(coin.From.Y, 2))
			table.insert(entry, round(coin.From.Z, 2))
			table.insert(entry, round(coin.SpillAt, 3))
		end
		table.insert(list, entry)
	end
	self.context:SetSharedJSON("Coins", list)
	self.coinsDirty = false
	self.lastPublish = self.context:Now()
end

function SharkBait:SwimmersLeft(): number
	local count = 0
	for _, player in self.context:GetAlivePlayers() do
		if self.role[player] == "Swimmer" then
			count += 1
		end
	end
	return count
end

function SharkBait:SharksLeft(): number
	local count = 0
	for _, shark in self.sharks do
		if self.context:IsAlive(shark) then
			count += 1
		end
	end
	return count
end

function SharkBait:_status()
	if self.ended then
		return
	end
	local need = math.max(0, self.goal - self.haul)
	self.context:SetStatus(if need == 1 then "🏊 1 coin to go!" else `🏊 {need} coins to go!`)
end

-- The end of the round once one side is gone.
function SharkBait:_refresh()
	local ctx = self.context
	if self.ended or not ctx:IsRunning() then
		return
	end
	if self.swimmerCount > 0 and self:SwimmersLeft() == 0 then
		self.ended = true
		ctx:SetStatus("🏊 The swimmers left!")
		ctx:End("NoSwimmers")
		return
	end
	if self.swimmerCount > 0 and self:SharksLeft() == 0 then
		self.ended = true
		self.won = SharkBait.SWIMMERS
		ctx:SetStatus("🦈 The shark left. SWIMMERS WIN!")
		ctx:End("NoSharks")
		return
	end
	self:_status()
end

-- The round -------------------------------------------------------------------------------------------

function SharkBait:Start()
	local ctx = self.context
	for _, player in ctx:GetPlayers() do
		if self.role[player] == "Swimmer" then
			self.swimmerCount += 1
		end
	end
	-- The goal: enough that the swimmers have to take risks, more for more swimmers and sharks.
	self.goal = math.max(12, math.floor(8 + 6.5 * self.swimmerCount) - (if #self.sharks > 1 then 4 else 0))
	ctx:SetShared("Goal", self.goal)
	ctx:SetShared("Haul", 0)
	ctx:AddTeamScore(SharkBait.SHARKS, 0)
	ctx:AddTeamScore(SharkBait.SWIMMERS, 0)
	for _, shark in self.sharks do
		self:_sharkSpeed(shark)
		self.nextChomp[shark] = ctx:Now() + 0.5
		ctx:SetPlayerShared(shark, "ChompAt", self.nextChomp[shark])
		ctx:SetPlayerShared(shark, "ChompLength", 0.5)
	end

	ctx:OnAction("Chomp", function(player)
		if self.role[player] ~= "Shark" or self.ended then
			return
		end
		if ctx:Now() < (self.nextChomp[player] or 0) - 0.08 then
			return -- the jaws are still resetting
		end
		self:_chomp(player)
	end, { Interval = 0.15 })

	-- Coins: a steady drizzle (quicker with more swimmers), and a treasure chest or two.
	for _ = 1, math.min(6, 2 + self.swimmerCount) do
		self:_spawnCoin()
	end
	ctx:Loop(function(): number?
		local progress = ctx:Progress()
		if progress >= RUSH_AT and not self.rush then
			self.rush = true
			ctx:SetShared("Rush", true)
			ctx:Announce("🌊 COIN RUSH! Coins everywhere!", "reward", 3)
			ctx:Sound("VoteOpen")
		end
		local chestsDue = if progress >= 0.72 and self.swimmerCount >= 5 then 2 elseif progress >= 0.38 then 1 else 0
		local most = 8 + 2 * self.swimmerCount + (if self.rush then 6 else 0)
		if self.chests < chestsDue then
			self.chests += 1
			self:_spawnChest()
		elseif self:CoinCount() < most then
			self:_spawnCoin()
		end
		local every = math.clamp(2.6 / (0.6 + 0.28 * math.max(1, self.swimmerCount)), 0.4, 1.8)
		return every * (if self.rush then 0.5 else 1) * rng:NextNumber(0.8, 1.2)
	end)

	-- Ten times a second: who's in the water, grabs, sinking coins, everyone where they belong.
	ctx:Loop(function(): number?
		self:_tick(ctx:Now())
		return 0.1
	end)
	self:_refresh()
end

function SharkBait:_tick(now: number)
	local ctx = self.context
	if self.ended then
		return -- someone has won: everything holds still for the cheer
	end
	local origin: Vector3 = self.origin
	for _, player in ctx:GetAlivePlayers() do
		local character, humanoid, root = ctx:GetCharacter(player)
		if not character or not humanoid or not root or self.gulped[player] then
			continue
		end
		local position = root.Position
		local away = flatDistance(position, origin)
		if self.role[player] == "Shark" then
			-- Sharks stay in the water, inside the float line, fast and unable to jump.
			local raft = self:RaftUnder(position)
			local up = position.Y > self.waterY + 1.6
			if up or away > SharkBait.LAGOON + 2 or (raft and raft.State ~= SharkBait.FLIPPED) then
				local dir = flat(position - origin)
				dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(1, 0, 0)
				local back = origin
					+ dir * math.clamp(away, SharkBait.RING + SharkBait.RING_RADIUS + 3, SharkBait.LAGOON - 3)
				if raft and away <= SharkBait.LAGOON then
					local out = flat(position - raft.Center)
					out = if out.Magnitude > 0.1 then out.Unit else dir
					back = raft.Center + out * (raft.Radius + 2.6)
				end
				local spot = Vector3.new(back.X, self.floorY + SharkBait.HIP, back.Z)
				character:PivotTo(CFrame.lookAt(spot, spot + flatLook(root.CFrame)))
			end
			if humanoid.WalkSpeed ~= SharkBait.SHARK_SPEED or humanoid.JumpHeight > 0 or humanoid.JumpPower > 0 then
				self:_sharkSpeed(player)
			end
			continue
		end

		-- Swimmers.
		if away > SharkBait.LAGOON + 2 then
			character:PivotTo(self:_raftSpot() + Vector3.new(0, SharkBait.HIP, 0))
			self.spots[player] = nil
			continue
		end
		local wet = self:InWater(position)
		if wet ~= (self.wet[player] == true) then
			self.wet[player] = wet
			self.wetSince[player] = if wet then now else nil
			ctx:SetPlayerShared(player, "InWater", wet)
			if not ctx:IsStunned(player) then
				humanoid.WalkSpeed = if wet then SharkBait.SWIM_SPEED else ctx.WalkSpeed
			end
			-- (One splash per dip: bobbing up and down at a raft's side doesn't make a fountain.)
			if wet and now - (self.splashAt[player] or -math.huge) > 1.5 then
				self.splashAt[player] = now
				ctx:Fire(nil, "Splash", player.UserId, round(position.X, 2), round(position.Z, 2))
			end
		end
		if wet and not physics and now - (self.wetSince[player] or now) >= CLIMB_TIME then
			-- No physics on the test servers: a swimmer that reaches a raft's side climbs up it (on a
			-- real server their jump does that).
			local raft = self:RaftUnder(position, -0.6)
			if raft and raft.State == SharkBait.READY then
				character:PivotTo(CFrame.new(position.X, self.deckY + SharkBait.HIP, position.Z) * root.CFrame.Rotation)
				position = Vector3.new(position.X, self.deckY + SharkBait.HIP, position.Z)
			end
		end

		-- Grabs along their path since the last check.
		local previous = self.spots[player]
		if not previous or (previous - position).Magnitude > 24 then
			previous = position
		end
		self.spots[player] = position
		for id, coin in self.coins do
			if
				now >= coin.Born
				and SharkBait.Swept(previous, position, coin.Position, SharkBait.Kinds[coin.Kind].Reach)
			then
				self:_grab(player, id, coin)
				if self.ended then
					return
				end
			end
		end
	end

	-- Coins in the water sink when their time is up.
	for id, coin in self.coins do
		if coin.Expires > 0 and now >= coin.Expires then
			self.coins[id] = nil
			self.coinsDirty = true
			ctx:Fire(nil, "Sink", id)
		end
	end
	if self.coinsDirty and now - self.lastPublish >= 0.1 then
		self:_publishCoins()
	end
end

-- At the buzzer: nothing moves any more, and anyone still in a shark's belly is spat out for the cheer.
function SharkBait:Stop()
	self.ended = true
	for swimmer in self.gulped do
		self:_spitOut(swimmer)
	end
end

-- Everyone on the winning side shares first place; the losing side is ordered by points: sharks by
-- chomps (5) and dunks (1), swimmers by coins.
function SharkBait:GetResults()
	local ctx = self.context
	local winner = self.won
	if not winner then
		-- Time's up without the goal: the sharks held them off (or there were no swimmers).
		winner = if self.swimmerCount > 0 and #self.sharks == 0 then SharkBait.SWIMMERS else SharkBait.SHARKS
	end
	local entries = {}
	for _, player in ctx:GetPlayers() do
		local state = ctx:State(player)
		local role = self.role[player]
		if not state or not role then
			continue
		end
		local team = if role == "Shark" then SharkBait.SHARKS else SharkBait.SWIMMERS
		local text
		if role == "Shark" then
			local chomps, dunks = self.chomps[player] or 0, self.dunks[player] or 0
			text = `🦈 {chomps} {if chomps == 1 then "chomp" else "chomps"}`
			if dunks > 0 then
				text ..= ` • {dunks} dunked`
			end
		else
			local times = self.chomped[player] or 0
			text = `🏊 {state.Score} {if state.Score == 1 then "coin" else "coins"} • `
				.. if times == 0 then "never chomped!" elseif times == 1 then "chomped once" else `chomped {times}x`
		end
		table.insert(entries, {
			Player = player,
			Rank = if team == winner then 1e6 else state.Score,
			ScoreText = text,
			BestScore = state.Score,
			Team = team,
		})
	end
	return { Entries = entries, WinningTeam = winner }
end

return SharkBait

-- Big Bad Vacuum (co-op boss fight, 1-12 players, everyone on the same side). The owner asked for a game
-- that "feels super sick and epic": the whole lobby against one giant robot vacuum in a toy-strewn living
-- room at night. It drops in from the ceiling, chases people, sweeps, charges, sucks everyone toward its
-- mouth, whips its power cord and lobs dust bombs, and gets angrier in three phases.
--
-- How it plays (Shared/Logic/BigBadVacuum has every number and the geometry):
--   * Toy bricks wait in piles round the rug. Walk onto a pile to pick one up (one at a time), THROW it
--     (E) and it lobs at the boss. A brick on the armour only chips it; a brick on the open CORE hatch on
--     top is a CRIT, and crits thrown close together make a VOLLEY that hits harder.
--   * The core is open only after the boss CRASHES into the wall at the end of a CHARGE, OVERHEATS after a
--     SUCTION or gets DIZZY after a WHIRL. So the lobby dodges, baits the charge, and then everyone throws.
--   * A SUCTION pulls people toward the boss's mouth and anyone who reaches it is stuffed in its DUST BAG
--     (the bag holds a few, spits them out after a while, and heals the boss meanwhile). A brick thrown at
--     the bag (BAG) pops it and frees them: a rescue.
--   * Damage and rescues fill the PARTY METER; when it is full anyone can fire the PANIC BLAST.
--   * Phases at 68% and 34%: the boss breaks from its attack, roars (nobody can hurt it for a moment),
--     and learns cord slams (a shockwave ring to jump), then whirls and dust bombs.
--   * Win by emptying its health before the fight clock runs out. Everyone shares first place on a win;
--     otherwise the places go by contribution (damage + rescues).
--
-- The server owns everything (the boss's position, every attack and hit, bricks, the bag, the meter);
-- clients only ask (THROW, PANIC) and draw. The boss is drawn on clients from a shared snapshot
-- (position, heading and velocity, 10 times a second) and attack plans (the danger zones with their
-- times: the same zones the server judges and the bots read). Hits are judged on where the player is
-- plus a little of where they are going (their screen is a trip ahead of the server), so a dodge that
-- looks clean on a phone counts. The suction's pull is applied by each client to its own character
-- (smooth) and by the server to bots (hazard parity); the trap itself is judged on the server.
--
-- Nothing solid where nothing is drawn: the rug layers and the wall blocks are the only collision.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.BigBadVacuum)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Telemetry = require(script.Parent.Parent.Services.Telemetry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local BigBadVacuum = MiniGame.Define("BigBadVacuum", { Results = "Score" })

local FLOOR_Y = 0.2 -- the rug's top above the arena origin
local LAND_AT = 3.6 -- seconds after GO the boss hits the floor
local LAND_PUSH = 30 -- everyone this close to the middle is shoved out when it lands
local SHARE_EVERY = 0.1
local TURN_RATE = 2.4 -- rad/s while chasing
local AIM_RATE = 6 -- rad/s while lining up an attack
local PING_MAX = 0.3
local LEAD_MAX = 0.15 -- the most of a player's velocity that is judged ahead
local LEAD_SPEED = 80 -- ... and the fastest a player is taken to be moving for it (studs/s)

local rng = Random.new()

local function r2(v: number): number
	return math.floor(v * 100 + 0.5) / 100
end

local function pingOf(player: any): number
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and type(ping) == "number" and ping == ping then math.clamp(ping, 0, PING_MAX) else 0.1
end

type Stat = { Damage: number, Rescues: number, Bonus: number, Throws: number, Crits: number, Dazed: number }
type Trap = { Since: number, Until: number, Slot: number }
type Flight = { Id: number, Thrower: any, Kind: string, T0: number, T1: number }

local ATTACKS: { [string]: any } = {}

-- Setting up -----------------------------------------------------------------------------------------------

function BigBadVacuum:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn" -- nobody is ever out: the dust bag and daze are the setbacks
	ctx.KillY = ctx.Origin.Y - 40
	local players = ctx:GetPlayers()
	self.count = math.max(#players, 1)
	self.radius = Rules.RadiusFor(self.count)
	self.center = ctx.Origin.Position + Vector3.new(0, FLOOR_Y, 0)

	self.stats = {} :: { [any]: Stat }
	self.carry = {} :: { [any]: number } -- who holds a brick (since when)
	self.dazed = {} :: { [any]: number } -- until when
	self.bumped = {} :: { [any]: number } -- when each was last shoved out of the boss
	self.safe = {} :: { [any]: number } -- can't be hit again until
	self.traps = {} :: { [any]: Trap }
	self.freeSlots = {} :: { number }
	self.flights = {} :: { Flight }
	self.rings = {} :: { any }
	self.volley = {} :: { number }
	self.piles = {} :: { any }
	self.bombs = {} :: { any }
	self.nextId = 0
	self.attackId = 0
	self.meter = 0
	self.meterReady = false
	self.panicPending = false
	self.outcome = nil :: string?
	self.sinceShare = 0
	self.errors = 0
	self.atkDirty = false
	self.lastCarry = ""
	self.lastTraps = ""
	self.lastPiles = ""

	self.boss = {
		X = self.center.X,
		Z = self.center.Z,
		Face = math.pi / 2,
		Vx = 0,
		Vz = 0,
		Spin = 0,
		State = "Intro",
		Until = 0,
		Hp = Rules.HealthFor(self.count),
		Max = Rules.HealthFor(self.count),
		Phase = 1,
		CoreUntil = 0,
		Shield = true,
		Target = nil,
		Last = nil,
		SinceStun = 0,
		Plan = nil,
		Healed = 0,
		PendingStun = 0,
		PendingReason = "",
	}

	self:_buildArena()

	-- Everyone starts on a ring near the wall, facing the middle (where the boss will land).
	local spawns = {}
	local count = math.max(#players, 1)
	local ring = self.radius * 0.8
	for index = 1, count do
		local angle = (index - 0.5) / count * math.pi * 2
		local at = self.center + Vector3.new(math.cos(angle) * ring, 3, math.sin(angle) * ring)
		table.insert(spawns, CFrame.lookAt(at, Vector3.new(self.center.X, at.Y, self.center.Z)))
	end
	ctx:SpawnAll(spawns, true)

	ctx.Hooks.Respawn = function(_player)
		local angle = rng:NextNumber(0, math.pi * 2)
		local at = self.center
			+ Vector3.new(math.cos(angle) * self.radius * 0.7, 3, math.sin(angle) * self.radius * 0.7)
		return CFrame.lookAt(at, Vector3.new(self.center.X, at.Y, self.center.Z))
	end
	ctx.Hooks.PlayerLeft = function(player)
		self:_letGo(player)
	end

	for _, name in
		{
			"BigBadVacuumBody",
			"BigBadVacuumBrush",
			"BigBadVacuumBag",
			"BigBadVacuumCordLink",
			"BigBadVacuumPlug",
			"BigBadVacuumBrick",
			"BigBadVacuumDebris",
		}
	do
		ctx:ShareTemplate(name, MeshLibrary.Get(name))
	end
	ctx:SetSharedJSON(
		"Arena",
		{ R = self.radius, X = self.center.X, Y = self.center.Y, Z = self.center.Z, N = self.count }
	)
	self:_publishAll()
end

-- The living room at night: a round rug under a ring of giant toy blocks, bricks to throw, a lamp, a TV
-- and a couch beyond the wall.
function BigBadVacuum:_buildArena()
	local ctx = self.context
	local arena = ctx.Arena
	local center = self.center
	local radius = self.radius
	local origin = ctx.Origin.Position

	local function rgb(r: number, g: number, b: number): Color3
		return Color3.fromRGB(r, g, b)
	end
	local function disc(
		name: string,
		diameter: number,
		thickness: number,
		y: number,
		color: Color3,
		material,
		solid: boolean
	)
		return Build.Part({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(thickness, diameter, diameter),
			CFrame = CFrame.new(center.X, y - thickness / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = material,
			CanCollide = solid,
			CanQuery = solid,
			CanTouch = false,
			CastShadow = false,
			Parent = arena,
		})
	end

	-- The room's dark wooden floor out to the horizon, and the rug on it: bands of colour, each layer a
	-- hair above the one under it (solid and drawn, so a character stands on whichever is under it).
	disc("Floor", 1200, 4, origin.Y - 0.9, rgb(58, 40, 36), Enum.Material.Wood, false)
	disc("RugShadow", radius * 2 + 22, 0.4, origin.Y - 0.5, rgb(30, 22, 24), Enum.Material.SmoothPlastic, false)
	local bands = {
		{ radius + 5, rgb(34, 40, 92), Enum.Material.Fabric },
		{ radius + 2.2, rgb(240, 226, 196), Enum.Material.Fabric },
		{ radius * 0.93, rgb(52, 110, 130), Enum.Material.Fabric },
		{ radius * 0.86, rgb(236, 218, 184), Enum.Material.Fabric },
		{ radius * 0.62, rgb(190, 78, 70), Enum.Material.Fabric },
		{ radius * 0.55, rgb(240, 226, 196), Enum.Material.Fabric },
		{ radius * 0.32, rgb(48, 56, 120), Enum.Material.Fabric },
		{ radius * 0.25, rgb(240, 186, 70), Enum.Material.Fabric },
		{ radius * 0.12, rgb(190, 78, 70), Enum.Material.Fabric },
	}
	for index, band in bands do
		disc(`Rug{index}`, band[1] * 2, 1, center.Y + (index - 1) * 0.07 - 0.5, band[2], band[3], true)
	end
	-- Spokes on the cream band, like a woven pattern.
	local top = center.Y + #bands * 0.07 - 0.5
	for index = 0, 15 do
		local angle = index / 16 * math.pi * 2
		local at = center + Vector3.new(math.cos(angle) * radius * 0.74, 0, math.sin(angle) * radius * 0.74)
		Build.Decor({
			Name = "Spoke",
			Size = Vector3.new(radius * 0.14, 0.12, 2.2),
			CFrame = CFrame.lookAt(Vector3.new(at.X, top + 0.07, at.Z), Vector3.new(center.X, top + 0.07, center.Z))
				* CFrame.Angles(0, math.rad(90), 0),
			Color = if index % 2 == 0 then rgb(52, 110, 130) else rgb(190, 78, 70),
			Material = Enum.Material.Fabric,
			Parent = arena,
		})
	end

	-- The wall: giant toy blocks, some stacked two high, their inner faces on the arena's edge.
	local ringRadius = radius + 7.5
	local blocks = math.ceil(2 * math.pi * ringRadius / 14.2)
	self.blocks = blocks
	local palette = {
		rgb(232, 76, 84),
		rgb(70, 140, 235),
		rgb(250, 200, 60),
		rgb(86, 200, 120),
		rgb(250, 140, 60),
		rgb(160, 110, 230),
	}
	for index = 0, blocks - 1 do
		local angle = index / blocks * math.pi * 2
		local color = palette[index % #palette + 1]
		local at = center + Vector3.new(math.cos(angle) * ringRadius, -0.3, math.sin(angle) * ringRadius)
		local facing = CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z))
		local stacked = index % 3 == 1
		MeshLibrary.Get("BigBadVacuumBlock", {
			CFrame = facing,
			Colors = {
				Body = color,
				Face = color:Lerp(Color3.new(1, 1, 1), 0.28),
				Emblem = color:Lerp(Color3.new(1, 1, 1), 0.7),
			},
			Parent = arena,
		})
		if stacked then
			MeshLibrary.Get("BigBadVacuumBlock", {
				CFrame = facing * CFrame.new(0, 15.7, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-6, 6)), 0),
				Colors = {
					Body = palette[(index + 2) % #palette + 1],
					Face = palette[(index + 2) % #palette + 1]:Lerp(Color3.new(1, 1, 1), 0.28),
					Emblem = palette[(index + 2) % #palette + 1]:Lerp(Color3.new(1, 1, 1), 0.7),
				},
				Parent = arena,
			})
		end
	end

	-- The brick piles, evenly round the rug.
	local piles = Rules.PilesFor(self.count)
	local turn = rng:NextNumber(0, math.pi * 2)
	for index = 0, piles - 1 do
		local angle = turn + index / piles * math.pi * 2
		local at = center + Vector3.new(math.cos(angle) * radius * 0.6, 0, math.sin(angle) * radius * 0.6)
		table.insert(self.piles, { Id = index + 1, X = at.X, Z = at.Z, ReadyAt = 0 })
		MeshLibrary.Get("BigBadVacuumPile", {
			CFrame = CFrame.new(at.X, top, at.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = arena,
		})
		local glow = Build.Decor({
			Name = "PileGlow",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, Rules.PICKUP * 2, Rules.PICKUP * 2),
			CFrame = CFrame.new(at.X, top + 0.12, at.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = rgb(255, 214, 90),
			Material = Enum.Material.Neon,
			Transparency = 0.6,
			Parent = arena,
		})
		Build.Light(glow, rgb(255, 214, 120), 18, 1.2)
	end

	-- The room beyond the wall: a floor lamp, a TV and a couch at three sides, so the arena has a
	-- backdrop in every direction.
	local function backdrop(name: string, angle: number, distance: number, turnBy: number?)
		local at = center + Vector3.new(math.cos(angle) * distance, -0.3, math.sin(angle) * distance)
		MeshLibrary.Get(name, {
			CFrame = CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z)) * CFrame.Angles(0, turnBy or 0, 0),
			Parent = arena,
		})
	end
	backdrop("BigBadVacuumTV", math.pi * 1.5, radius + 60)
	backdrop("BigBadVacuumCouch", 0.05, radius + 58)
	backdrop("BigBadVacuumLamp", math.pi * 0.85, radius + 46)
	backdrop("BigBadVacuumLamp", math.pi * 0.2, radius + 50)
	backdrop("BigBadVacuumCouch", math.pi * 1.0, radius + 60, math.rad(8))
	backdrop("BigBadVacuumTV", math.pi * 0.5, radius + 62)
end

-- Sharing ------------------------------------------------------------------------------------------------

function BigBadVacuum:_zonesJson(plan: any): { any }
	local list = {}
	for _, zone in plan.Zones do
		table.insert(list, {
			K = zone.K,
			X = r2(zone.X),
			Z = r2(zone.Z),
			A = if zone.A then r2(zone.A) else nil,
			Arc = if zone.Arc then r2(zone.Arc) else nil,
			R = r2(zone.R),
			L = if zone.L then r2(zone.L) else nil,
			W = if zone.W then r2(zone.W) else nil,
			T0 = r2(zone.T0),
			T1 = r2(zone.T1),
			T2 = r2(zone.T2),
		})
	end
	return list
end

function BigBadVacuum:_publishAtk()
	local plan = self.boss.Plan
	self.atkDirty = false
	if not plan then
		self.context:SetSharedJSON("Atk", { I = self.attackId, K = "" })
		return
	end
	self.context:SetSharedJSON("Atk", {
		I = plan.Id,
		K = plan.Kind,
		T0 = r2(plan.T0),
		T1 = r2(plan.T1),
		T2 = r2(plan.T2),
		Z = self:_zonesJson(plan),
		F = if plan.Face then r2(plan.Face) else nil,
		Ex = if plan.Ex then r2(plan.Ex) else nil,
		Ez = if plan.Ez then r2(plan.Ez) else nil,
		B = if plan.Base then r2(plan.Base) else nil,
	})
end

function BigBadVacuum:_publishBoss()
	local boss = self.boss
	local ctx = self.context
	ctx:SetSharedJSON("Boss", {
		T = r2(ctx:Now()),
		X = r2(boss.X),
		Z = r2(boss.Z),
		F = r2(boss.Face),
		VX = r2(boss.Vx),
		VZ = r2(boss.Vz),
		W = r2(boss.Spin),
		S = boss.State,
		P = boss.Phase,
		H = math.ceil(boss.Hp),
		M = boss.Max,
		C = r2(boss.CoreUntil),
		Q = boss.Shield,
		U = r2(boss.Until),
		K = if boss.Plan then boss.Plan.Kind else "",
		G = self.t0 or 0,
		E = self.fightEnds or 0,
	})
end

function BigBadVacuum:_publishMeter()
	self.context:SetSharedJSON("Meter", { V = math.floor(self.meter), R = self.meterReady })
end

-- Carry, trap and pile lists only go out when they change.
function BigBadVacuum:_publishLists()
	local ctx = self.context
	local carry = {}
	for player in self.carry do
		table.insert(carry, player.UserId)
	end
	table.sort(carry)
	local carryKey = table.concat(carry, ",")
	if carryKey ~= self.lastCarry then
		self.lastCarry = carryKey
		ctx:SetSharedJSON("Carry", carry)
	end
	local traps = {}
	for player, trap in self.traps do
		table.insert(traps, { U = player.UserId, S = trap.Slot, E = r2(trap.Until) })
	end
	table.sort(traps, function(a, b)
		return a.S < b.S
	end)
	local trapKey = ""
	for _, entry in traps do
		trapKey ..= `{entry.U}:{entry.S}:{entry.E};`
	end
	if trapKey ~= self.lastTraps then
		self.lastTraps = trapKey
		ctx:SetSharedJSON("Trap", traps)
	end
	local piles = {}
	local pileKey = ""
	for _, pile in self.piles do
		table.insert(piles, { I = pile.Id, X = r2(pile.X), Z = r2(pile.Z), R = r2(pile.ReadyAt) })
		pileKey ..= `{pile.Id}:{r2(pile.ReadyAt)};`
	end
	if pileKey ~= self.lastPiles then
		self.lastPiles = pileKey
		ctx:SetSharedJSON("Piles", piles)
	end
end

function BigBadVacuum:_publishAll()
	self:_publishBoss()
	self:_publishAtk()
	self:_publishMeter()
	self:_publishLists()
end

-- People ----------------------------------------------------------------------------------------------------

function BigBadVacuum:_stat(player: any): Stat
	local stat = self.stats[player]
	if not stat then
		stat = { Damage = 0, Rescues = 0, Bonus = 0, Throws = 0, Crits = 0, Dazed = 0 }
		self.stats[player] = stat
	end
	return stat
end

function BigBadVacuum:_scoreText(player: any)
	local stat = self:_stat(player)
	local text = `{stat.Damage} dmg`
	if stat.Rescues > 0 then
		text ..= ` · {stat.Rescues} saved`
	end
	self.context:SetScoreText(player, text)
end

-- Where `player` is judged: their root, a little ahead along their velocity for people (their screen is a
-- trip ahead of the server, so a dodge that looks clean there must count).
function BigBadVacuum:_where(player: any, root: BasePart): (number, number)
	local position = root.Position
	if BotRegistry.IsBot(player) then
		return position.X, position.Z
	end
	local velocity = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	if velocity.Magnitude > LEAD_SPEED then
		velocity = velocity.Unit * LEAD_SPEED -- (a device reporting a wild velocity isn't judged far away)
	end
	local lead = math.min(pingOf(player) / 2 + 0.04, LEAD_MAX)
	return position.X + velocity.X * lead, position.Z + velocity.Z * lead
end

-- Everyone who can be hit or targeted: alive, in the arena, not in the bag.
function BigBadVacuum:_targets(): { { Player: any, Root: BasePart } }
	local list = {}
	local ctx = self.context
	for _, player in ctx:GetAlivePlayers() do
		if self.traps[player] then
			continue
		end
		local _, _, root = ctx:GetCharacter(player)
		if root then
			table.insert(list, { Player = player, Root = root })
		end
	end
	return list
end

function BigBadVacuum:IsDazed(player: any, now: number): boolean
	return (self.dazed[player] or 0) > now
end

function BigBadVacuum:IsTrapped(player: any): boolean
	return self.traps[player] ~= nil
end

function BigBadVacuum:HasBrick(player: any): boolean
	return self.carry[player] ~= nil
end

function BigBadVacuum:TrappedCount(): number
	local n = 0
	for _ in self.traps do
		n += 1
	end
	return n
end

function BigBadVacuum:CoreOpen(now: number): boolean
	return now < self.boss.CoreUntil and not self.boss.Shield
end

-- The nearest pile that has a brick for `position`.
function BigBadVacuum:NearestPile(x: number, z: number, now: number): any
	local best, bestDistance = nil, math.huge
	for _, pile in self.piles do
		local distance = Rules.Distance(x, z, pile.X, pile.Z)
		-- (a pile that is cooling down is back in a moment: still worth walking to)
		if distance < bestDistance and pile.ReadyAt - now < 1.5 then
			best, bestDistance = pile, distance
		end
	end
	return best
end

-- Every warning that is up right now (telegraphs the server will judge): bots read these to dodge.
function BigBadVacuum:Zones(now: number): { any }
	local plan = self.boss.Plan
	local list = {}
	if plan and (self.boss.State == "Wind" or self.boss.State == "Act") then
		for _, zone in plan.Zones do
			if now >= zone.T0 - 0.05 and now <= zone.T2 + 0.1 then
				table.insert(list, zone)
			end
		end
	end
	return list
end

-- A live shockwave ring, if any (bots jump over it).
function BigBadVacuum:RingAt(now: number): any
	for _, ring in self.rings do
		if now - ring.T0 < (Rules.RING_MAX + Rules.RING_THICK) / Rules.RING_SPEED then
			return ring
		end
	end
	return nil
end

-- Takes a brick away from `player` (daze, the bag, leaving).
function BigBadVacuum:_dropBrick(player: any)
	if self.carry[player] then
		self.carry[player] = nil
	end
end

-- `player` is hit by an attack: dazed, thrown away from (fromX, fromZ), brick dropped, then safe a while.
function BigBadVacuum:_hit(player: any, kind: string, fromX: number, fromZ: number, force: number): boolean
	local ctx = self.context
	local now = ctx:Now()
	if self.boss.Shield or self.traps[player] or (self.safe[player] or 0) > now or not ctx:IsAlive(player) then
		return false
	end
	local _, _, root = ctx:GetCharacter(player)
	if not root then
		return false
	end
	self.dazed[player] = now + Rules.DAZE
	self.safe[player] = now + Rules.DAZE + Rules.SAFE
	self:_stat(player).Dazed += 1
	self:_dropBrick(player)
	local away = Vector3.new(root.Position.X - fromX, 0, root.Position.Z - fromZ)
	away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit
	ctx:Knockback(player, away * force + Vector3.new(0, 34, 0), Rules.DAZE)
	ctx:Fire(nil, "Dazed", player.UserId, r2(root.Position.X), r2(root.Position.Y), r2(root.Position.Z), kind)
	return true
end

-- Puts `player` in the dust bag (if there is room).
function BigBadVacuum:_trap(player: any, now: number)
	local ctx = self.context
	if self.traps[player] or self.boss.Shield or (self.safe[player] or 0) > now then
		return
	end
	if self:TrappedCount() >= Rules.BagCapacity(self.count) then
		return
	end
	local slot = table.remove(self.freeSlots, 1)
	if not slot then
		slot = self:TrappedCount() + 1
	end
	self:_dropBrick(player)
	self.traps[player] = { Since = now, Until = now + Rules.TRAP_TIME, Slot = slot }
	ctx:Freeze(player, true)
	local _, _, root = ctx:GetCharacter(player)
	if root then
		root.Anchored = true
		root.AssemblyLinearVelocity = Vector3.zero
		ctx:Fire(nil, "Trapped", player.UserId, r2(root.Position.X), r2(root.Position.Y), r2(root.Position.Z))
	end
	self:_followBag(player, self.traps[player], now)
end

function BigBadVacuum:_bagCenter(): Vector3
	local boss = self.boss
	return Vector3.new(
		boss.X - math.cos(boss.Face) * Rules.BAG_BACK,
		self.center.Y + Rules.BAG_HEIGHT,
		boss.Z - math.sin(boss.Face) * Rules.BAG_BACK
	)
end

function BigBadVacuum:_coreAt(): Vector3
	return Vector3.new(self.boss.X, self.center.Y + Rules.CORE_HEIGHT, self.boss.Z)
end

-- Holds a trapped player at their slot inside the bag.
function BigBadVacuum:_followBag(player: any, trap: Trap, now: number)
	local ctx = self.context
	local character, _, root = ctx:GetCharacter(player)
	if not character or not root then
		return
	end
	local capacity = Rules.BagCapacity(self.count)
	local angle = trap.Slot / capacity * math.pi * 2 + now * 0.8
	local at = self:_bagCenter()
		+ Vector3.new(math.cos(angle) * 2.6, -2.2 + math.sin(now * 3 + trap.Slot) * 0.4, math.sin(angle) * 2.6)
	root.Anchored = true
	character:PivotTo(CFrame.lookAt(at, self:_bagCenter()))
end

-- Lets `player` out of the bag: they land behind the boss, shoved clear and safe for a moment.
function BigBadVacuum:_release(player: any, now: number, spit: boolean)
	local ctx = self.context
	local trap = self.traps[player]
	if not trap then
		return
	end
	self.traps[player] = nil
	table.insert(self.freeSlots, trap.Slot)
	local character, _, root = ctx:GetCharacter(player)
	if root and character then
		local boss = self.boss
		-- Out of the back, clear of the body; with the boss backed against the wall, out towards the middle.
		local reach = Rules.BODY_RADIUS + 5
		local angle = boss.Face + math.pi + rng:NextNumber(-0.7, 0.7)
		local function landing(a: number): (number, number)
			return boss.X + math.cos(a) * reach, boss.Z + math.sin(a) * reach
		end
		local x, z = landing(angle)
		if Rules.Distance(x, z, self.center.X, self.center.Z) > self.radius - 3 then
			angle = math.atan2(self.center.Z - boss.Z, self.center.X - boss.X) + rng:NextNumber(-0.7, 0.7)
			x, z = landing(angle)
		end
		local at = Vector3.new(x, self.center.Y + 3.5, z)
		root.Anchored = false
		character:PivotTo(CFrame.new(at))
		root.AssemblyLinearVelocity = Vector3.zero
		ctx:Knockback(player, Vector3.new(math.cos(angle) * 22, 14, math.sin(angle) * 22), 0.5)
	end
	ctx:Freeze(player, false)
	self.safe[player] = now + 2.5
	ctx:Fire(nil, "Freed", player.UserId, spit)
end

function BigBadVacuum:_releaseAll(now: number)
	for player in table.clone(self.traps) do
		self:_release(player, now, true)
	end
end

-- Someone left: whatever they held or were stuck in goes with them.
function BigBadVacuum:_letGo(player: any)
	self:_dropBrick(player)
	self.dazed[player] = nil
	self.safe[player] = nil
	self.bumped[player] = nil
	local trap = self.traps[player]
	if trap then
		self.traps[player] = nil
		table.insert(self.freeSlots, trap.Slot)
	end
end

-- Bricks -------------------------------------------------------------------------------------------------------

function BigBadVacuum:_tryThrow(player: any, hint: any)
	local ctx = self.context
	local boss = self.boss
	local now = ctx:Now()
	local function refuse()
		ctx:Fire(player, "Refused", "Throw")
	end
	if not ctx:IsRunning() or ctx:TimeIsUp() or not ctx:IsAlive(player) then
		return
	end
	if not self.carry[player] or self.traps[player] or self:IsDazed(player, now) then
		refuse()
		return
	end
	if boss.State == "Intro" or boss.State == "Dying" or boss.State == "Done" then
		refuse()
		return
	end
	local _, _, root = ctx:GetCharacter(player)
	if not root then
		return
	end
	local kind = "Core"
	if hint == "Bag" and self:TrappedCount() > 0 then
		kind = "Bag"
	end
	local aim = if kind == "Bag" then self:_bagCenter() else self:_coreAt()
	local from = root.Position + Vector3.new(0, 2, 0)
	local distance = (Vector3.new(aim.X, from.Y, aim.Z) - from).Magnitude
	if Rules.Distance(root.Position.X, root.Position.Z, boss.X, boss.Z) > Rules.THROW_RANGE then
		refuse()
		return
	end
	self.carry[player] = nil
	self.nextId += 1
	local flight: Flight =
		{ Id = self.nextId, Thrower = player, Kind = kind, T0 = now, T1 = now + Rules.Flight(distance) }
	table.insert(self.flights, flight)
	self:_stat(player).Throws += 1
	ctx:Fire(
		nil,
		"Throw",
		flight.Id,
		player.UserId,
		kind,
		r2(flight.T0),
		r2(flight.T1),
		r2(from.X),
		r2(from.Y),
		r2(from.Z)
	)
	self:_publishLists()
end

-- A brick lands: damage, or a rescue.
function BigBadVacuum:_landBrick(flight: Flight, now: number)
	local ctx = self.context
	local boss = self.boss
	local thrower = flight.Thrower
	if flight.Kind == "Bag" then
		local count = self:TrappedCount()
		if count > 0 then
			local at = self:_bagCenter()
			self:_releaseAll(now)
			if ctx:IsAlive(thrower) then
				local stat = self:_stat(thrower)
				stat.Rescues += count
				ctx:AddScore(thrower, count * Rules.RESCUE_POINTS)
				self:_scoreText(thrower)
			end
			self:_addMeter(count * Rules.METER_PER_RESCUE)
			ctx:Fire(nil, "Pop", count, if thrower then thrower.UserId else 0, r2(at.X), r2(at.Y), r2(at.Z))
			return
		end
	end
	local at = self:_coreAt()
	if boss.Shield or boss.State == "Dying" or boss.State == "Done" then
		ctx:Fire(nil, "Clink", r2(at.X), r2(at.Y), r2(at.Z), true)
		return
	end
	-- (a brick thrown while the core was open counts as a crit even if the hatch shut while it flew: the
	-- HUD said THROW when it left the hand)
	local open = now < boss.CoreUntil + 0.12 or flight.T0 < boss.CoreUntil
	if not open then
		self:_damage(thrower, Rules.CHIP, false, 0, now)
		ctx:Fire(nil, "Clink", r2(at.X), r2(at.Y), r2(at.Z), false)
		return
	end
	-- Crits thrown close together make a volley.
	local fresh = {}
	for _, t in self.volley do
		if now - t <= Rules.VOLLEY_WINDOW then
			table.insert(fresh, t)
		end
	end
	table.insert(fresh, now)
	self.volley = fresh
	local count = #fresh
	local damage = math.floor(Rules.CRIT * Rules.Volley(count) + 0.5)
	self:_stat(thrower).Crits += 1
	self:_damage(thrower, damage, true, count, now)
end

-- Damage to the boss (and the meter, the score, the phase, the end).
function BigBadVacuum:_damage(
	player: any,
	amount: number,
	crit: boolean,
	volley: number,
	now: number,
	noMeter: boolean?
)
	local ctx = self.context
	local boss = self.boss
	if boss.Shield or boss.Hp <= 0 then
		return 0
	end
	local dealt = math.min(math.floor(amount + 0.5), math.ceil(boss.Hp))
	if dealt <= 0 then
		return 0
	end
	boss.Hp -= dealt
	if player and ctx:IsAlive(player) then
		self:_stat(player).Damage += dealt
		ctx:AddScore(player, dealt)
		self:_scoreText(player)
	end
	if not noMeter then
		self:_addMeter(dealt * Rules.METER_PER_DAMAGE)
	end
	local at = self:_coreAt()
	ctx:Fire(nil, "Hit", r2(at.X), r2(at.Y), r2(at.Z), dealt, crit, volley, if player then player.UserId else 0)
	if boss.Hp <= 0 then
		boss.Hp = 0
		self:_win(player, now)
	else
		local phase = Rules.PhaseFor(boss.Hp / boss.Max)
		if phase > boss.Phase then
			self:_startBreak(phase, now)
		end
	end
	self:_publishBoss()
	return dealt
end

function BigBadVacuum:_addMeter(amount: number)
	if self.meterReady then
		return
	end
	self.meter = math.min(100, self.meter + amount)
	if self.meter >= 100 then
		self.meterReady = true
		self.context:Fire(nil, "MeterFull")
	end
	self:_publishMeter()
end

function BigBadVacuum:_stepFlights(now: number)
	-- Take the landed ones out first: landing can end the fight, which clears the list.
	local due = {}
	for index = #self.flights, 1, -1 do
		if now >= self.flights[index].T1 then
			table.insert(due, 1, table.remove(self.flights, index))
		end
	end
	for _, flight in due do
		self:_landBrick(flight, now)
	end
end

-- Pickups, the suction's pull on bots, bumping out of the boss, staying in the arena.
function BigBadVacuum:_stepPeople(now: number, dt: number)
	local ctx = self.context
	local boss = self.boss
	local plan = boss.Plan
	local sucking = plan ~= nil and plan.Kind == "Suction" and boss.State == "Act"
	local mouthX, mouthZ = Rules.MouthAt(boss.X, boss.Z, plan and plan.Face or boss.Face)
	local playing = boss.State ~= "Dying" and boss.State ~= "Done"
	for _, entry in self:_targets() do
		local player, root = entry.Player, entry.Root
		local position = root.Position
		local x, z = position.X, position.Z
		-- A brick from a pile.
		if playing and not self.carry[player] and not self:IsDazed(player, now) then
			for _, pile in self.piles do
				if now >= pile.ReadyAt and Rules.Distance(x, z, pile.X, pile.Z) <= Rules.PICKUP then
					pile.ReadyAt = now + Rules.PILE_WAIT
					self.carry[player] = now
					ctx:Fire(nil, "Pickup", player.UserId, pile.Id)
					break
				end
			end
		end
		-- The suction pulls bots (each person's own device pulls them), and the mouth takes whoever gets there.
		if sucking and playing then
			local fx, fz = self:_where(player, root)
			local pulled =
				Rules.InCone(boss.X, boss.Z, plan.Face, Rules.Attacks.Suction.Arc, Rules.Attacks.Suction.Reach, fx, fz)
			if pulled then
				if BotRegistry.IsBot(player) and not root.Anchored then
					local dx, dz = mouthX - x, mouthZ - z
					local away = math.sqrt(dx * dx + dz * dz)
					if away > 0.5 then
						local speed = Rules.PullSpeed(Rules.Distance(x, z, boss.X, boss.Z)) * dt
						local character = root.Parent
						if character and character:IsA("Model") then
							character:PivotTo(
								character:GetPivot() + Vector3.new(dx / away * speed, 0, dz / away * speed)
							)
						end
					end
				end
				if Rules.Distance(x, z, mouthX, mouthZ) <= Rules.Attacks.Suction.Mouth then
					self:_trap(player, now)
				end
			end
		end
		-- Nobody stands inside the boss: a shove out of its body.
		if playing and not self.traps[player] and boss.State ~= "Intro" then
			local away = Rules.Distance(x, z, boss.X, boss.Z)
			if away < Rules.BODY_RADIUS + 0.4 then
				local dx, dz = x - boss.X, z - boss.Z
				local magnitude = math.sqrt(dx * dx + dz * dz)
				local ux, uz =
					if magnitude > 0.05 then dx / magnitude else 1, if magnitude > 0.05 then dz / magnitude else 0
				if BotRegistry.IsBot(player) then
					local character = root.Parent
					if character and character:IsA("Model") then
						local push = Rules.BODY_RADIUS + 1.2 - away
						character:PivotTo(character:GetPivot() + Vector3.new(ux * push, 0, uz * push))
					end
				elseif now - (self.bumped[player] or 0) > 0.3 then
					self.bumped[player] = now
					ctx:Knockback(player, Vector3.new(ux * 40, 8, uz * 40), 0)
				end
			end
		end
		-- The safety net: anyone found outside the wall (or under the rug) goes back in.
		local fromMiddle = Rules.Distance(x, z, self.center.X, self.center.Z)
		-- (the blocks' inside face is at radius + 0.5: only someone pushed into or through the wall is caught,
		-- not someone standing against it)
		if (fromMiddle > self.radius + 2 or position.Y < self.center.Y - 5) and not root.Anchored then
			local ux = (x - self.center.X) / math.max(fromMiddle, 0.1)
			local uz = (z - self.center.Z) / math.max(fromMiddle, 0.1)
			local inside = math.min(fromMiddle, self.radius - 4)
			local character = root.Parent
			if character and character:IsA("Model") then
				character:PivotTo(
					CFrame.new(self.center.X + ux * inside, self.center.Y + 3.5, self.center.Z + uz * inside)
						* (character:GetPivot() - character:GetPivot().Position)
				)
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
end

-- The bag: followers, the spit-out timer and the boss healing while it holds people.
function BigBadVacuum:_stepTraps(now: number, dt: number)
	local boss = self.boss
	local count = 0
	for player, trap in table.clone(self.traps) do
		count += 1
		if now >= trap.Until then
			self:_release(player, now, true)
		else
			self:_followBag(player, trap, now)
		end
	end
	if count > 0 and not boss.Shield and boss.Hp > 0 and boss.State ~= "Dying" then
		local room = boss.Max * Rules.HEAL_CAP - boss.Healed
		local heal = math.min(boss.Max * Rules.HEAL_PER_SECOND * count * dt, room)
		if heal > 0 then
			boss.Healed += heal
			boss.Hp = math.min(boss.Max, boss.Hp + heal)
		end
	end
end

function BigBadVacuum:_stepRings(now: number)
	local boss = self.boss
	for index = #self.rings, 1, -1 do
		local ring = self.rings[index]
		local e1 = now - ring.T0
		if e1 > (Rules.RING_MAX + Rules.RING_THICK) / Rules.RING_SPEED + 0.2 then
			table.remove(self.rings, index)
			continue
		end
		if not boss.Shield then
			for _, entry in self:_targets() do
				local player = entry.Player
				if not ring.Hit[player] then
					local x, z = self:_where(player, entry.Root)
					local feet = entry.Root.Position.Y - self.center.Y - Rules.STAND
					if Rules.RingHits(ring.X, ring.Z, ring.Last, e1, x, z, feet) then
						ring.Hit[player] = true
						self:_hit(player, "Ring", ring.X, ring.Z, 42)
					end
				end
			end
		end
		ring.Last = e1
	end
end

-- The boss ------------------------------------------------------------------------------------------------

function BigBadVacuum:_pickTarget(): any
	local targets = self:_targets()
	if #targets == 0 then
		return nil
	end
	return targets[rng:NextInteger(1, #targets)]
end

-- The nearest person (to the boss), with their root.
function BigBadVacuum:_nearestTarget(): any
	local boss = self.boss
	local best, bestDistance = nil, math.huge
	for _, entry in self:_targets() do
		local distance = Rules.Distance(entry.Root.Position.X, entry.Root.Position.Z, boss.X, boss.Z)
		if distance < bestDistance then
			best, bestDistance = entry, distance
		end
	end
	return best
end

function BigBadVacuum:_enterChase(now: number)
	local boss = self.boss
	boss.State = "Chase"
	boss.Plan = nil
	boss.Until = now + Rules.Think(boss.Phase) + rng:NextNumber(0, 0.6)
	boss.Target = nil
	boss.CoreUntil = 0
	self:_publishAtk()
	self:_publishBoss()
end

function BigBadVacuum:_clampBoss()
	local boss = self.boss
	local limit = self.radius - Rules.BODY_RADIUS - 0.6
	local dx, dz = boss.X - self.center.X, boss.Z - self.center.Z
	local away = math.sqrt(dx * dx + dz * dz)
	if away > limit then
		boss.X = self.center.X + dx / away * limit
		boss.Z = self.center.Z + dz / away * limit
	end
end

-- Turns the boss toward `angle` at `rate` rad/s.
function BigBadVacuum:_turnTo(angle: number, rate: number, dt: number)
	local boss = self.boss
	local turn = Rules.Turn(boss.Face, angle)
	local step = math.clamp(turn, -rate * dt, rate * dt)
	boss.Face += step
	if boss.Face > math.pi then
		boss.Face -= math.pi * 2
	elseif boss.Face < -math.pi then
		boss.Face += math.pi * 2
	end
	boss.Spin = step / math.max(dt, 1e-3)
end

-- Between attacks the boss lumbers after someone.
function BigBadVacuum:_chase(dt: number)
	local boss = self.boss
	local target = boss.Target
	if target then
		local _, _, root = self.context:GetCharacter(target)
		if not root or self.traps[target] then
			target = nil
		end
	end
	if not target then
		local pick = self:_nearestTarget()
		if pick and rng:NextNumber() < 0.5 then
			pick = self:_pickTarget() or pick
		end
		target = if pick then pick.Player else nil
		boss.Target = target
	end
	boss.Vx, boss.Vz, boss.Spin = 0, 0, 0
	if not target then
		return
	end
	local _, _, root = self.context:GetCharacter(target)
	if not root then
		return
	end
	local dx, dz = root.Position.X - boss.X, root.Position.Z - boss.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	self:_turnTo(math.atan2(dz, dx), TURN_RATE, dt)
	if distance > Rules.BODY_RADIUS + 9 then
		local speed = Rules.ChaseSpeed(boss.Phase)
		boss.Vx, boss.Vz = math.cos(boss.Face) * speed, math.sin(boss.Face) * speed
		boss.X += boss.Vx * dt
		boss.Z += boss.Vz * dt
		self:_clampBoss()
	end
end

-- (`forced` is for tests: the round harness's showcase scenarios start a particular attack.)
function BigBadVacuum:_beginAttack(now: number, forced: string?)
	local boss = self.boss
	local kind = forced or Rules.NextAttack(boss.Phase, boss.Last, boss.SinceStun, rng:NextNumber())
	boss.Last = kind
	self.attackId += 1
	local wind = Rules.WindFor(kind, boss.Phase)
	local plan = { Kind = kind, Id = self.attackId, T0 = now, T1 = now + wind, T2 = now + wind, Zones = {}, Prev = 0 }
	boss.Plan = plan
	boss.State = "Wind"
	boss.Vx, boss.Vz, boss.Spin = 0, 0, 0
	boss.Until = plan.T1
	ATTACKS[kind].Wind(self, plan, now)
	self:_publishAtk()
	self:_publishBoss()
	self.context:Fire(nil, "Wind", kind, plan.Id, r2(plan.T1))
end

-- An attack is over: a breather, then (for the attacks that open it) the core.
function BigBadVacuum:_finishAttack(now: number)
	local boss = self.boss
	local plan = boss.Plan
	if not plan then
		return
	end
	local def = Rules.Attacks[plan.Kind]
	local stun = if Rules.Stuns[plan.Kind] then Rules.StunFor(plan.Kind, boss.Phase) else 0
	if stun > 0 then
		boss.SinceStun = 0
	else
		boss.SinceStun += 1
	end
	boss.PendingStun = stun
	boss.PendingReason = plan.Kind
	boss.State = "Recover"
	boss.Until = now + (def.Recover or 0.3)
	boss.Vx, boss.Vz, boss.Spin = 0, 0, 0
	boss.Plan = nil
	self:_publishAtk()
	self:_publishBoss()
end

-- The core opens: bricks are crits for `seconds`.
function BigBadVacuum:_openCore(now: number, seconds: number, reason: string)
	local boss = self.boss
	boss.State = "Stun"
	boss.Until = now + seconds
	boss.CoreUntil = now + seconds
	boss.Plan = nil
	boss.Vx, boss.Vz, boss.Spin = 0, 0, 0
	self.bombs = {}
	self.context:Fire(nil, "Core", r2(boss.CoreUntil), reason)
	self:_publishAtk()
	self:_publishBoss()
end

function BigBadVacuum:_stepBoss(now: number, dt: number)
	local boss = self.boss
	local state = boss.State
	if state == "Dying" or state == "Done" then
		return
	end
	if state ~= "Intro" and now >= self.fightEnds then
		self:_lose(now)
		return
	end
	if state == "Intro" or state == "Break" then
		if now >= boss.Until then
			boss.Shield = false
			self:_enterChase(now)
		end
	elseif state == "Chase" then
		self:_chase(dt)
		if now >= boss.Until then
			self:_beginAttack(now)
		end
	elseif state == "Wind" then
		local plan = boss.Plan
		ATTACKS[plan.Kind].WindTick(self, plan, now, dt)
		if now >= plan.T1 then
			boss.State = "Act"
			ATTACKS[plan.Kind].Begin(self, plan, now)
			self:_publishAtk()
			self:_publishBoss()
		end
	elseif state == "Act" then
		local plan = boss.Plan
		if plan and ATTACKS[plan.Kind].ActTick(self, plan, now, dt) then
			self:_finishAttack(now)
		end
	elseif state == "Recover" then
		if now >= boss.Until then
			if boss.PendingStun > 0 then
				local seconds = boss.PendingStun
				boss.PendingStun = 0
				self:_openCore(now, seconds, boss.PendingReason)
			else
				self:_enterChase(now)
			end
		end
	elseif state == "Stun" then
		if now >= boss.Until then
			self:_enterChase(now)
		end
	end
end

-- The boss lands from the ceiling: everyone near the middle is shoved clear (no damage).
function BigBadVacuum:_landBoss()
	local ctx = self.context
	ctx:Fire(nil, "Land", r2(self.boss.X), r2(self.boss.Z), r2(ctx:Now()))
	for _, entry in self:_targets() do
		local position = entry.Root.Position
		local away = Rules.Distance(position.X, position.Z, self.boss.X, self.boss.Z)
		if away < LAND_PUSH then
			local dx, dz = position.X - self.boss.X, position.Z - self.boss.Z
			local m = math.max(math.sqrt(dx * dx + dz * dz), 0.1)
			ctx:Knockback(entry.Player, Vector3.new(dx / m * 55, 20, dz / m * 55), 0.5)
		end
	end
end

-- Health crossed a phase line: the boss breaks off, roars and can't be hurt for a moment.
function BigBadVacuum:_startBreak(phase: number, now: number)
	local ctx = self.context
	local boss = self.boss
	boss.Phase = phase
	boss.State = "Break"
	boss.Until = now + Rules.BREAK
	boss.Shield = true
	boss.CoreUntil = 0
	boss.Plan = nil
	boss.PendingStun = 0
	boss.Healed = 0
	boss.SinceStun = 0
	boss.Vx, boss.Vz, boss.Spin = 0, 0, 0
	self.bombs = {}
	self:_releaseAll(now)
	ctx:Fire(nil, "Phase", phase, r2(now), r2(boss.Until))
	-- A shockwave shoves everyone back (no damage).
	for _, entry in self:_targets() do
		local position = entry.Root.Position
		local dx, dz = position.X - boss.X, position.Z - boss.Z
		local m = math.max(math.sqrt(dx * dx + dz * dz), 0.1)
		ctx:Knockback(entry.Player, Vector3.new(dx / m * 48, 22, dz / m * 48), 0.6)
	end
	self:_publishAtk()
end

-- The boss is beaten: it falls apart, everyone is frozen to watch, then the results.
function BigBadVacuum:_win(killer: any, now: number)
	local ctx = self.context
	local boss = self.boss
	if self.outcome then
		return
	end
	self.outcome = "Victory"
	boss.State = "Dying"
	boss.Shield = true
	boss.CoreUntil = 0
	boss.Plan = nil
	boss.Vx, boss.Vz, boss.Spin = 0, 0, 0
	self:_releaseAll(now)
	self.flights = {}
	if killer and ctx:IsAlive(killer) then
		self:_stat(killer).Bonus += Rules.FINISHER_POINTS
		ctx:AddScore(killer, Rules.FINISHER_POINTS)
		self:_scoreText(killer)
	end
	self:_freezeEveryone(true)
	ctx:Fire(nil, "Victory", r2(now), if killer then killer.UserId else 0)
	self:_publishAll()
	ctx:Delay(Rules.VICTORY_SHOW, function()
		ctx:End("Victory")
	end)
end

-- The clock ran out: the boss wins.
function BigBadVacuum:_lose(now: number)
	local ctx = self.context
	local boss = self.boss
	if self.outcome then
		return
	end
	self.outcome = "Defeat"
	boss.State = "Done"
	boss.Shield = true
	boss.CoreUntil = 0
	boss.Plan = nil
	boss.Vx, boss.Vz, boss.Spin = 0, 0, 0
	self.flights = {}
	self:_releaseAll(now) -- (as a win does: nobody hangs in the bag through the results)
	self:_freezeEveryone(true)
	ctx:Fire(nil, "Defeat", r2(now))
	self:_publishAll()
	ctx:Delay(Rules.DEFEAT_SHOW, function()
		ctx:End("Defeat")
	end)
end

function BigBadVacuum:_freezeEveryone(frozen: boolean)
	local ctx = self.context
	for _, player in ctx:GetAlivePlayers() do
		if not self.traps[player] then
			ctx:Freeze(player, frozen)
		end
	end
end

-- The PANIC BLAST --------------------------------------------------------------------------------------------

function BigBadVacuum:_tryPanic(player: any)
	local ctx = self.context
	local boss = self.boss
	local now = ctx:Now()
	if not self.meterReady or self.panicPending or not ctx:IsRunning() or self.traps[player] then
		return
	end
	if boss.Shield or boss.State == "Dying" or boss.State == "Done" or boss.State == "Intro" then
		return
	end
	self.panicPending = true
	self.meter = 0
	self.meterReady = false
	self:_publishMeter()
	ctx:Fire(nil, "Panic", player.UserId, r2(now), r2(now + 1.4))
	local stat = self:_stat(player)
	stat.Bonus += Rules.PANIC_POINTS
	ctx:AddScore(player, Rules.PANIC_POINTS)
	for _, other in ctx:GetAlivePlayers() do
		if other ~= player then
			self:_stat(other).Bonus += Rules.PANIC_SHARE
			ctx:AddScore(other, Rules.PANIC_SHARE)
		end
	end
	local function blast()
		local at = ctx:Now()
		if boss.State == "Dying" or boss.State == "Done" or not ctx:IsRunning() then
			self.panicPending = false
			return
		end
		if boss.Shield then
			-- (a phase break began while it charged: it goes off as soon as the shield drops, the meter
			-- already spent isn't wasted)
			ctx:Delay(0.2, blast)
			return
		end
		self.panicPending = false
		-- The blast opens the core as well (an overload), whatever the boss was doing.
		self:_openCore(at, Rules.BLAST_OPEN, "Blast")
		local dealt = self:_damage(player, math.floor(boss.Max * Rules.BLAST + 0.5), false, 0, at, true)
		ctx:Fire(nil, "Blast", dealt)
	end
	ctx:Delay(1.4, blast)
end

-- Starting ------------------------------------------------------------------------------------------------------

function BigBadVacuum:Start()
	local ctx = self.context
	local now = ctx:Now()
	local boss = self.boss
	self.t0 = now
	boss.State = "Intro"
	boss.Until = now + Rules.INTRO
	self.fightEnds = now + Rules.INTRO + Rules.FIGHT
	ctx:SetStatus("Team up against the Big Bad Vacuum!")

	ctx:OnAction("Throw", function(player, hint)
		self:_tryThrow(player, hint)
	end, { Interval = Rules.THROW_WAIT * 0.8 })
	ctx:OnAction("Panic", function(player)
		self:_tryPanic(player)
	end, { Interval = 0.3 })

	ctx:Delay(LAND_AT, function()
		self:_landBoss()
	end)
	ctx:Delay(Rules.INTRO - 1.4, function()
		ctx:Fire(nil, "Roar")
	end)

	self:_publishAll()
	ctx:Heartbeat(function(dt)
		self:_step(dt)
	end)
end

function BigBadVacuum:_safely(label: string, fn: (...any) -> (), ...: any)
	local ok, err = pcall(fn, self, ...)
	if not ok then
		self.errors += 1
		if self.errors <= 5 then
			Telemetry.Error("BigBadVacuum:" .. label, tostring(err))
		end
	end
end

function BigBadVacuum:_step(dt: number)
	local ctx = self.context
	local now = ctx:Now()
	self:_safely("boss", self._stepBoss, now, dt)
	self:_safely("rings", self._stepRings, now)
	self:_safely("flights", self._stepFlights, now)
	self:_safely("people", self._stepPeople, now, dt)
	self:_safely("traps", self._stepTraps, now, dt)
	self.sinceShare += dt
	if self.sinceShare >= SHARE_EVERY then
		self.sinceShare = 0
		self:_safely("share", function()
			self:_publishBoss()
			if self.atkDirty then
				self:_publishAtk()
			end
			self:_publishLists()
		end)
	end
	-- The status line: the clock and the phase.
	local remaining = math.max(0, math.ceil(self.fightEnds - now))
	local text = if self.boss.State == "Intro"
		then "Here it comes..."
		else `PHASE {self.boss.Phase} · {remaining}s left`
	if text ~= self.lastStatus and not self.outcome then
		self.lastStatus = text
		ctx:SetStatus(text)
	end
end

-- The attacks -----------------------------------------------------------------------------------------------------
-- Each: Wind(plan, now) sets it up, WindTick keeps the boss lined up (or tracking), Begin starts the hit,
-- ActTick judges it each step and returns true once it's over.

-- The boss lines up on `angle`.
local function aimAt(self, angle: number, dt: number)
	self:_turnTo(angle, AIM_RATE, dt)
end

local function bearingToNearest(self): number
	local boss = self.boss
	local target = self:_nearestTarget()
	if target then
		return math.atan2(target.Root.Position.Z - boss.Z, target.Root.Position.X - boss.X)
	end
	return boss.Face
end

ATTACKS.Sweep = {
	Wind = function(self, plan, now)
		local def = Rules.Attacks.Sweep
		plan.Face = bearingToNearest(self)
		plan.T2 = plan.T1 + def.Act
		table.insert(plan.Zones, {
			K = "Sector",
			X = self.boss.X,
			Z = self.boss.Z,
			A = plan.Face,
			Arc = def.Arc,
			R = def.Reach,
			T0 = now,
			T1 = plan.T1,
			T2 = plan.T2,
		})
	end,
	WindTick = function(self, plan, _now, dt)
		aimAt(self, plan.Face, dt)
	end,
	Begin = function(self, plan, _now)
		self.boss.Face = plan.Face
		plan.Prev = 0
		self.context:Fire(nil, "Swing", plan.Id, r2(plan.T1), r2(plan.T2), r2(plan.Face))
	end,
	ActTick = function(self, plan, now, _dt)
		local boss = self.boss
		local def = Rules.Attacks.Sweep
		local f1 = math.clamp((now - plan.T1) / def.Act, 0, 1)
		for _, entry in self:_targets() do
			local x, z = self:_where(entry.Player, entry.Root)
			if Rules.SweepHits(boss.X, boss.Z, plan.Face, plan.Prev, f1, x, z) then
				self:_hit(entry.Player, "Sweep", boss.X, boss.Z, 52)
			end
		end
		plan.Prev = f1
		return f1 >= 1
	end,
}

ATTACKS.Whirl = {
	Wind = function(self, plan, now)
		local def = Rules.Attacks.Whirl
		plan.Face = self.boss.Face
		plan.Base = self.boss.Face
		plan.T2 = plan.T1 + def.Act
		table.insert(plan.Zones, {
			K = "Whirl",
			X = self.boss.X,
			Z = self.boss.Z,
			R = def.Reach,
			T0 = now,
			T1 = plan.T1,
			T2 = plan.T2,
		})
	end,
	WindTick = function(self, plan, _now, _dt)
		plan.Zones[1].X, plan.Zones[1].Z = self.boss.X, self.boss.Z
	end,
	Begin = function(self, plan, _now)
		plan.Prev = 0
		self.context:Fire(nil, "Spin", plan.Id, r2(plan.T1), r2(plan.T2), r2(plan.Base))
	end,
	ActTick = function(self, plan, now, dt)
		local boss = self.boss
		local def = Rules.Attacks.Whirl
		local f1 = math.clamp((now - plan.T1) / def.Act, 0, 1)
		-- It drifts after the nearest person while it spins.
		local target = self:_nearestTarget()
		boss.Vx, boss.Vz = 0, 0
		if target then
			local dx, dz = target.Root.Position.X - boss.X, target.Root.Position.Z - boss.Z
			local m = math.max(math.sqrt(dx * dx + dz * dz), 0.1)
			if m > Rules.BODY_RADIUS + 6 then
				boss.Vx, boss.Vz = dx / m * 6, dz / m * 6
				boss.X += boss.Vx * dt
				boss.Z += boss.Vz * dt
				self:_clampBoss()
			end
		end
		boss.Spin = 0 -- (clients turn the body along the plan: Rules.WhirlAngle)
		plan.Zones[1].X, plan.Zones[1].Z = boss.X, boss.Z
		for _, entry in self:_targets() do
			local x, z = self:_where(entry.Player, entry.Root)
			if Rules.WhirlHits(boss.X, boss.Z, plan.Base, plan.Prev, f1, x, z) then
				self:_hit(entry.Player, "Whirl", boss.X, boss.Z, 52)
			end
		end
		plan.Prev = f1
		if f1 >= 1 then
			-- It stops facing where the arm ended up.
			boss.Face = Rules.Turn(0, Rules.WhirlAngle(plan.Base, 1))
			return true
		end
		return false
	end,
}

ATTACKS.Charge = {
	Wind = function(self, plan, now)
		local boss = self.boss
		local def = Rules.Attacks.Charge
		local pick = self:_pickTarget()
		local angle = boss.Face
		if pick then
			angle = math.atan2(pick.Root.Position.Z - boss.Z, pick.Root.Position.X - boss.X)
		end
		local dx, dz = Rules.Dir(angle)
		local ex, ez = Rules.ChargeEnd(self.center.X, self.center.Z, boss.X, boss.Z, dx, dz, self.radius)
		local distance = Rules.Distance(boss.X, boss.Z, ex, ez)
		plan.Face = angle
		plan.Ex, plan.Ez = ex, ez
		plan.Sx, plan.Sz = boss.X, boss.Z
		plan.Distance = distance
		plan.T2 = plan.T1 + distance / def.Speed
		table.insert(plan.Zones, {
			K = "Lane",
			X = boss.X,
			Z = boss.Z,
			A = angle,
			L = distance + Rules.BODY_RADIUS,
			W = def.HalfWidth,
			R = def.HalfWidth,
			T0 = now,
			T1 = plan.T1,
			T2 = plan.T2,
		})
	end,
	WindTick = function(self, plan, _now, dt)
		aimAt(self, plan.Face, dt)
	end,
	Begin = function(self, plan, _now)
		self.boss.Face = plan.Face
		self.context:Fire(nil, "Dash", plan.Id, r2(plan.T1), r2(plan.T2), r2(plan.Face))
	end,
	ActTick = function(self, plan, now, _dt)
		local boss = self.boss
		local def = Rules.Attacks.Charge
		local travelled = math.min(def.Speed * (now - plan.T1), plan.Distance)
		local dx, dz = Rules.Dir(plan.Face)
		boss.X = plan.Sx + dx * travelled
		boss.Z = plan.Sz + dz * travelled
		local done = travelled >= plan.Distance
		boss.Vx, boss.Vz = if done then 0 else dx * def.Speed, if done then 0 else dz * def.Speed
		for _, entry in self:_targets() do
			local x, z = self:_where(entry.Player, entry.Root)
			if Rules.Distance(x, z, boss.X, boss.Z) <= Rules.BODY_RADIUS + 1.2 then
				-- (flung to the side the body is passing, not along its path)
				self:_hit(entry.Player, "Charge", boss.X - dz * 6, boss.Z + dx * 6, 70)
			end
		end
		if done then
			self.context:Fire(nil, "Crash", r2(boss.X), r2(boss.Z), r2(plan.Face))
		end
		return done
	end,
}

ATTACKS.Suction = {
	Wind = function(self, plan, now)
		local def = Rules.Attacks.Suction
		plan.Face = bearingToNearest(self)
		plan.T2 = plan.T1 + def.Act
		table.insert(plan.Zones, {
			K = "Cone",
			X = self.boss.X,
			Z = self.boss.Z,
			A = plan.Face,
			Arc = def.Arc,
			R = def.Reach,
			T0 = now,
			T1 = plan.T1,
			T2 = plan.T2,
		})
	end,
	WindTick = function(self, plan, _now, dt)
		aimAt(self, plan.Face, dt)
	end,
	Begin = function(self, plan, _now)
		self.boss.Face = plan.Face
		self.context:Fire(nil, "Inhale", plan.Id, r2(plan.T1), r2(plan.T2), r2(plan.Face))
	end,
	ActTick = function(self, plan, now, _dt)
		return now >= plan.T2
	end,
}

-- The cord slam: a circle on someone, then a shockwave ring (two slams in a row in phase 3).
ATTACKS.Cord = {
	Wind = function(self, plan, now)
		local def = Rules.Attacks.Cord
		plan.Slams = if self.boss.Phase >= 3 then 2 else 1
		plan.T2 = plan.T1 + def.Act
		local pick = self:_pickTarget()
		local x = if pick then pick.Root.Position.X else self.boss.X
		local z = if pick then pick.Root.Position.Z else self.boss.Z
		plan.Aim = pick and pick.Player or nil
		plan.Face = if pick then math.atan2(z - self.boss.Z, x - self.boss.X) else self.boss.Face
		table.insert(plan.Zones, {
			K = "Disc",
			X = x,
			Z = z,
			R = def.Radius,
			T0 = now,
			T1 = plan.T1,
			T2 = plan.T2,
		})
	end,
	WindTick = function(self, plan, now, dt)
		local def = Rules.Attacks.Cord
		aimAt(self, plan.Face, dt)
		-- The circle follows its target until the last moment, then holds still.
		local aim = plan.Aim
		if aim and now < plan.T1 - def.Lock then
			local _, _, root = self.context:GetCharacter(aim)
			if root and not self.traps[aim] then
				local zone = plan.Zones[1]
				zone.X, zone.Z = root.Position.X, root.Position.Z
				plan.Face = math.atan2(zone.Z - self.boss.Z, zone.X - self.boss.X)
				self.atkDirty = true
			end
		end
	end,
	Begin = function(self, plan, now)
		local def = Rules.Attacks.Cord
		local zone = plan.Zones[1]
		self.nextId += 1
		local ring = { Id = self.nextId, X = zone.X, Z = zone.Z, T0 = now, Last = 0, Hit = {} }
		table.insert(self.rings, ring)
		self.context:Fire(nil, "Slam", ring.Id, r2(zone.X), r2(zone.Z), r2(now))
		for _, entry in self:_targets() do
			local x, z = self:_where(entry.Player, entry.Root)
			if Rules.Distance(x, z, zone.X, zone.Z) <= def.Radius then
				ring.Hit[entry.Player] = true -- (the slam itself is the hit; the ring doesn't hit them again)
				self:_hit(entry.Player, "Slam", zone.X, zone.Z, 55)
			end
		end
	end,
	ActTick = function(self, plan, now, _dt)
		if now < plan.T2 then
			return false
		end
		if plan.Slams > 1 then
			-- The second slam: a quicker warning on someone else.
			local def = Rules.Attacks.Cord
			plan.Slams -= 1
			local boss = self.boss
			boss.State = "Wind"
			plan.T0 = now
			plan.T1 = now + math.max(0.75 * Rules.WIND_SCALE[boss.Phase], 0.55)
			plan.T2 = plan.T1 + def.Act
			local pick = self:_pickTarget()
			local x = if pick then pick.Root.Position.X else boss.X
			local z = if pick then pick.Root.Position.Z else boss.Z
			plan.Aim = pick and pick.Player or nil
			plan.Face = math.atan2(z - boss.Z, x - boss.X)
			plan.Zones = {
				{ K = "Disc", X = x, Z = z, R = def.Radius, T0 = now, T1 = plan.T1, T2 = plan.T2 },
			}
			boss.Until = plan.T1
			self:_publishAtk()
			self.context:Fire(nil, "Wind", "Cord", plan.Id, r2(plan.T1))
			return false
		end
		return true
	end,
}

-- Dust bombs: circles pop up on people and around the arena, then burst.
ATTACKS.Bombs = {
	Wind = function(_self, plan, _now)
		local def = Rules.Attacks.Bombs
		plan.T2 = plan.T1 + def.Act
	end,
	WindTick = function(self, plan, _now, dt)
		self:_turnTo(plan.Face or self.boss.Face, AIM_RATE, dt)
	end,
	Begin = function(self, plan, now)
		local def = Rules.Attacks.Bombs
		local boss = self.boss
		local count = 4 + math.floor(self.count / 3)
		local targets = self:_targets()
		for index = 1, count do
			local x, z
			if index <= math.ceil(count / 2) and #targets > 0 then
				local pick = table.remove(targets, rng:NextInteger(1, #targets))
				local velocity = pick.Root.AssemblyLinearVelocity
				x = pick.Root.Position.X + velocity.X * 0.5
				z = pick.Root.Position.Z + velocity.Z * 0.5
			else
				local angle = rng:NextNumber(0, math.pi * 2)
				local away = self.radius * 0.85 * math.sqrt(rng:NextNumber())
				x = self.center.X + math.cos(angle) * away
				z = self.center.Z + math.sin(angle) * away
			end
			local fromMiddle = Rules.Distance(x, z, self.center.X, self.center.Z)
			if fromMiddle > self.radius - 4 then
				x = self.center.X + (x - self.center.X) / fromMiddle * (self.radius - 4)
				z = self.center.Z + (z - self.center.Z) / fromMiddle * (self.radius - 4)
			end
			local t0 = now + (index - 1) * def.Stagger
			local bomb = { X = x, Z = z, T0 = t0, T1 = t0 + 1.4, Done = false }
			table.insert(self.bombs, bomb)
			table.insert(
				plan.Zones,
				{ K = "Disc", X = x, Z = z, R = def.Radius, T0 = t0, T1 = bomb.T1, T2 = bomb.T1 + 0.3 }
			)
		end
		plan.T2 = now + (count - 1) * def.Stagger + 1.4 + 0.35
		self.context:Fire(nil, "Mortar", plan.Id, r2(now), r2(boss.X), r2(boss.Z))
	end,
	ActTick = function(self, plan, now, _dt)
		for _, bomb in self.bombs do
			if not bomb.Done and now >= bomb.T1 then
				bomb.Done = true
				self.context:Fire(nil, "Boom", r2(bomb.X), r2(bomb.Z), "Bomb")
				for _, entry in self:_targets() do
					local x, z = self:_where(entry.Player, entry.Root)
					if Rules.Distance(x, z, bomb.X, bomb.Z) <= Rules.Attacks.Bombs.Radius then
						self:_hit(entry.Player, "Bomb", bomb.X, bomb.Z, 50)
					end
				end
			end
		end
		if now >= plan.T2 then
			self.bombs = {}
			return true
		end
		return false
	end,
}

-- Finishing ---------------------------------------------------------------------------------------------------------

function BigBadVacuum:Stop(reason: string?)
	-- The round's own clock should never run out before the fight does; if it does, the boss wins.
	if not self.outcome then
		self.outcome = if reason == "Victory" then "Victory" else "Defeat"
	end
end

function BigBadVacuum:GetResults()
	local ctx = self.context
	local victory = self.outcome == "Victory"
	local entries = {}
	local best, bestScore = nil, -1
	for player, state in ctx.Participants do
		if not player.Parent then
			continue
		end
		local stat = self:_stat(player)
		local score = Rules.Score(stat.Damage, stat.Rescues, stat.Bonus)
		if score > bestScore then
			best, bestScore = player, score
		end
		table.insert(entries, { Player = player, Score = score, Stat = stat, State = state })
	end
	local results = {}
	for _, item in entries do
		local stat = item.Stat
		local text = `{stat.Damage} dmg`
		if stat.Rescues > 0 then
			text ..= ` · {stat.Rescues} saved`
		end
		if item.Player == best and bestScore > 0 then
			text = "★ MVP · " .. text
		end
		table.insert(results, {
			Player = item.Player,
			-- Beating the boss is everyone's win (a shared first place); a loss ranks by contribution.
			Rank = if victory then 1e6 else item.Score,
			ScoreText = text,
			BestScore = item.Score,
			Team = "Squad",
		})
	end
	return { Entries = results, WinningTeam = if victory then "Squad" else "Vacuum" }
end

return BigBadVacuum

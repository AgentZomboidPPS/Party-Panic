-- Hot Potato (Survival, 2-12 players). The owner picked this pitch ("Let's add the stars"): "a few
-- ticking bombs get handed out, and you tag someone to pass yours on. When a bomb goes off, whoever
-- is holding it gets launched into the sky and is out. New bombs drop until one player is left."
-- After the playground game and "Hot Bob-omb" (Mario Party), with its own look: the bombs are hot
-- potatoes (lumpy baked spuds with a metal cap and a fizzing fuse) in a fenced backyard cookout.
--
-- How it plays: one potato per 4 players still in (at least 1) drops on random players. Each has a
-- hidden fuse (8-14 s, shorter as fewer remain) and warns in its last 3 s. Its holder runs 10%
-- faster and passes it by touching an empty-handed player, or with THROW, a 0.4 s lob to the nearest
-- empty-handed player in front within 12 studs. No tag-backs for 2 s. When a fuse runs out the holder
-- (or, mid-air, the thrower) is launched into the sky and is out; 2 s later fresh potatoes top the
-- count back up. Last one standing wins; at time-out everyone still holding one blows up and the rest
-- survive; the others rank by how long they lasted.
--
-- The server owns who holds which potato, the flights and every fuse (shared as MG_Potatoes, sent
-- only when something changes; a fuse's end is only shared once its warning starts). Tags and throws
-- are judged against what the passer saw (owner: "the precision games will feel super bad if we
-- dont"): the server keeps a short history of everyone's position, and each of the passer's positions
-- as the press arrived is matched with the target's position the passer's round trip (capped at
-- 0.3 s) plus the drawing delay before it, never "any sample against any sample". A refused press is
-- answered with "Refused" so the client drops its prediction. Actions are only taken from GO on.
--
-- Bots play by the same rules: they tag and throw through ctx:BotAction, and an explosion launches
-- anyone with ctx:Knockback, players and bots alike. Characters don't bump into each other (one
-- mode-only collision group that doesn't collide with itself, for everyone, re-applied on respawn):
-- passes go by position, and nobody can shove a server-moved bot around.
--
-- Nothing solid where nothing is drawn (owner: "Theres invisible stuff you can jump on and hang on
-- in several games"): only the drawn lawn, fence panels, grill, tables and hay bales collide, with
-- collision that follows their meshes; the fence (10.5 studs) is well over a jump (7.2), nothing to
-- climb stands within 8 studs of it, and a safety net puts anyone found outside the lawn back in.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.HotPotato)

local MiniGame = require(script.Parent.Kit.MiniGame)
local Scenery = require(script.Parent.Kit.Scenery)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local HotPotato = MiniGame.Define("HotPotato", { Results = "Survival" })

local FIRST_DROP = 2 -- seconds after GO
local BREATHER = 2 -- after a blast, before fresh potatoes drop
local LAWN_Y = 0.2 -- the lawn's top above the origin
local FENCE_HEIGHT = 10.5 -- HotPotatoFence's height (a jump reaches 7.2)
local PANEL_WIDTH = 8 -- each fence panel covers this much of the ring (the mesh is a bit wider)
-- Solid props stand this far above the lawn: an invisible sliver, but a probe rising from the lawn under
-- them then meets their underside instead of starting inside them (tools/checks/colliders.py).
local SET_ON = 0.08
local LAUNCH_UP = 150 -- studs/s: a blast throws the holder about 55 studs up
local SHOW_AFTER = 1.8 -- the "You're out!" waits for the launch
local PING_MAX = 0.3 -- the most of a round trip that is made up for
local SEEN_LAG = 0.15 -- other characters are drawn about this far behind the server on a screen
local HISTORY_STEP = 1 / 20
local HISTORY_KEEP = 1.5
local CAST_GROUP = "PP_PotatoCast"

local rng = Random.new()

type Sample = { T: number, P: Vector3 }
type Flight = { From: any?, To: any, T0: number, T1: number, A: Vector3 }
type Potato = {
	Id: number,
	Holder: any?,
	From: any?,
	NoBackUntil: number,
	LockUntil: number,
	FuseEnd: number,
	Warned: boolean,
	Flight: Flight?,
}

local function pingOf(player: any): number
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and type(ping) == "number" and ping == ping then math.clamp(ping, 0, PING_MAX) else 0.15
end

-- Puts every character in the round in one group that doesn't collide with itself (parts that load
-- later too), the same for people and bots; each part gets its old group back when the round ends.
local function castWithoutContact(ctx): ((any, Model) -> ())?
	local ok = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(CAST_GROUP) then
			PhysicsService:RegisterCollisionGroup(CAST_GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(CAST_GROUP, CAST_GROUP, false)
	end)
	if not ok then
		return nil
	end
	local before: { [BasePart]: string } = {}
	ctx:Track(function()
		for part, group in before do
			if part.Parent and part.CollisionGroup == CAST_GROUP then
				part.CollisionGroup = group
			end
		end
	end)
	local function join(item: Instance)
		if item:IsA("BasePart") then
			if before[item] == nil then
				before[item] = item.CollisionGroup
			end
			item.CollisionGroup = CAST_GROUP
		end
	end
	local function put(_player: any, character: Model)
		for _, item in character:GetDescendants() do
			join(item)
		end
		ctx:Track(character.DescendantAdded:Connect(join))
	end
	for _, player in ctx:GetPlayers() do
		local character = ctx:GetCharacter(player)
		if character then
			put(player, character)
		end
	end
	return put
end

function HotPotato:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	ctx.KillY = ctx.Origin.Y - 30
	local origin = ctx.Origin.Position
	local players = ctx:GetPlayers()
	self.center = origin + Vector3.new(0, LAWN_Y, 0)
	self.radius = Rules.RadiusFor(#players)
	self.history = {} :: { [any]: { Sample } }
	self.potatoes = {} :: { Potato }
	self.nextId = 0
	self.passes = {} :: { [any]: number }
	self.blown = {} :: { [any]: boolean } -- holders blown up at the buzzer
	self.exploding = {} :: { [any]: boolean }
	self.lastSeen = {} :: { [any]: Vector3 }
	self.started = #players
	self.topUpPending = false

	self:_buildArena()

	-- Everyone starts on a ring near the fence, facing the grill.
	local spawns = {}
	local count = math.max(#players, 1)
	local ring = self.radius - 4.5
	for index = 1, count do
		local angle = (index - 0.5) / count * math.pi * 2
		local at = self.center + Vector3.new(math.cos(angle) * ring, 3, math.sin(angle) * ring)
		table.insert(spawns, CFrame.lookAt(at, Vector3.new(self.center.X, at.Y, self.center.Z)))
	end
	ctx:SpawnAll(spawns, true)
	for _, player in players do
		self.passes[player] = 0
	end

	local put = castWithoutContact(ctx)
	ctx.Hooks.CharacterReady = function(player, character)
		if put then
			put(player, character)
		end
	end
	ctx.Hooks.PlayerLeft = function(player)
		self:_letGo(player)
		self.history[player] = nil
		self:_publishLeft()
	end
	ctx.Hooks.Eliminated = function(player)
		if not self.exploding[player] then
			self:_letGo(player) -- out some other way (a reset): the potato moves on
		end
		self:_publishLeft()
	end

	ctx:ShareTemplate("HotPotatoSpud", MeshLibrary.Get("HotPotatoSpud"))
	ctx:ShareTemplate("HotPotatoPuff", MeshLibrary.Get("HotPotatoPuff"))
	ctx:SetSharedJSON("Lawn", { R = self.radius, Y = self.center.Y })
	self:_publish()
	self:_publishLeft()
end

function HotPotato:_buildArena()
	local ctx = self.context
	local arena = ctx.Arena
	local center = self.center
	local radius = self.radius
	local origin = ctx.Origin.Position

	Scenery.Meadow(ctx, origin, 300)
	-- The mowed lawn (drawn and solid), a little above the meadow so they never flicker, on a ring of
	-- gravel path under the fence.
	Build.Part({
		Name = "Lawn",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, radius * 2 + 3, radius * 2 + 3),
		CFrame = CFrame.new(center - Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(122, 200, 92),
		Material = Enum.Material.Grass,
		Parent = arena,
	})
	Build.Part({
		Name = "Path",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, radius * 2 + 9, radius * 2 + 9),
		CFrame = CFrame.new(origin + Vector3.new(0, -0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(196, 170, 130),
		Material = Enum.Material.Pebble,
		Parent = arena,
	})

	-- The fence: panels round the lawn, each facing the middle, with string lights along the top.
	local panels = math.ceil(2 * math.pi * radius / PANEL_WIDTH)
	local fenceAt = radius + 0.7 -- the panels' inside faces on the lawn's edge
	for index = 0, panels - 1 do
		local angle = index / panels * math.pi * 2
		local at = center + Vector3.new(math.cos(angle) * fenceAt, SET_ON, math.sin(angle) * fenceAt)
		local facing = CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z))
		MeshLibrary.Get("HotPotatoFence", { CFrame = facing, Parent = arena })
		MeshLibrary.Get("HotPotatoLights", {
			CFrame = facing * CFrame.new(0, FENCE_HEIGHT - 2, -1),
			Parent = arena,
		})
	end

	-- The giant grill in the middle, and things to dodge round: picnic tables and hay bales on a ring
	-- well inside the fence (nothing to climb near it).
	MeshLibrary.Get("HotPotatoGrill", { CFrame = CFrame.new(center + Vector3.new(0, SET_ON, 0)), Parent = arena })
	local count = if radius < 26 then 4 else 6
	local ring = math.min(radius * 0.55, radius - 9)
	local turn = rng:NextNumber(0, math.pi * 2)
	for index = 0, count - 1 do
		local angle = turn + index / count * math.pi * 2
		local at = center + Vector3.new(math.cos(angle) * ring, SET_ON, math.sin(angle) * ring)
		local facing = CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z))
		MeshLibrary.Get(if index % 2 == 0 then "HotPotatoTable" else "HotPotatoHay", {
			CFrame = facing * CFrame.Angles(0, math.pi / 2, 0),
			Parent = arena,
		})
	end
end

-- Potatoes ----------------------------------------------------------------------------------------

function HotPotato:_publish()
	local list = {}
	for _, potato in self.potatoes do
		local entry: { [string]: any } = {
			I = potato.Id,
			H = if potato.Holder then potato.Holder.UserId else 0,
			F = if potato.From then potato.From.UserId else 0,
			N = potato.NoBackUntil,
			L = potato.LockUntil,
		}
		if potato.Warned then
			entry.W = potato.FuseEnd - Rules.WARN
		end
		local flight = potato.Flight
		if flight then
			entry.Fl = {
				A = if flight.From then flight.From.UserId else 0,
				B = flight.To.UserId,
				T0 = flight.T0,
				T1 = flight.T1,
				P = { flight.A.X, flight.A.Y, flight.A.Z },
			}
		end
		table.insert(list, entry)
	end
	self.context:SetSharedJSON("Potatoes", list)
	local count = #list
	if count ~= self.shownCount then
		self.shownCount = count
		self.context:SetStatus(
			if count == 0
				then "Pass the potato before it blows!"
				else `▼ {count} HOT POTATO{if count == 1 then "" else "ES"} IN PLAY`
		)
	end
end

function HotPotato:_publishLeft()
	local ctx = self.context
	ctx:SetShared("Left", ctx:AliveCount())
end

function HotPotato:HolderOf(player: any): Potato?
	for _, potato in self.potatoes do
		if potato.Holder == player then
			return potato
		end
	end
	return nil
end

-- Whether `player` is tied up with a potato: holding one, or one is flying to or from them.
function HotPotato:Busy(player: any): boolean
	for _, potato in self.potatoes do
		local flight = potato.Flight
		if potato.Holder == player or (flight and (flight.To == player or flight.From == player)) then
			return true
		end
	end
	return false
end

-- Whether `potato` may go to `target` now.
function HotPotato:CanTake(potato: Potato, target: any, now: number): boolean
	local ctx = self.context
	if not ctx:IsAlive(target) or self:Busy(target) then
		return false
	end
	if target == potato.From and now < potato.NoBackUntil then
		return false
	end
	local _, _, root = ctx:GetCharacter(target)
	return root ~= nil
end

function HotPotato:_participant(userId: any): any
	if type(userId) ~= "number" or userId ~= userId then
		return nil
	end
	for _, player in self.context:GetAlivePlayers() do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

function HotPotato:_speed(player: any)
	local ctx = self.context
	if not ctx:IsAlive(player) then
		return
	end
	ctx:SetWalkSpeed(player, ctx.WalkSpeed * (if self:HolderOf(player) then Rules.SPEED else 1))
end

function HotPotato:_give(potato: Potato, to: any, from: any?, how: string)
	local now = self.context:Now()
	potato.Holder = to
	potato.Flight = nil
	potato.From = from
	potato.NoBackUntil = if from then now + Rules.NO_BACK else 0
	potato.LockUntil = now + Rules.LOCK
	if from then
		self.passes[from] = (self.passes[from] or 0) + 1
		self:_speed(from)
	end
	self:_speed(to)
	self:_publish()
	self.context:Fire(nil, "Pass", if from then from.UserId else 0, to.UserId, how, potato.Id)
end

-- The nearest player who could take `potato` to `at` (nil if nobody can).
function HotPotato:_nearestTaker(potato: Potato, at: Vector3, except: any?): any
	local ctx = self.context
	local now = ctx:Now()
	local best, bestDistance = nil, math.huge
	for _, player in ctx:GetAlivePlayers() do
		if player == except or not self:CanTake(potato, player, now) then
			continue
		end
		local _, _, root = ctx:GetCharacter(player)
		if root then
			local distance = (root.Position - at).Magnitude
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

-- Tops the potatoes back up to one per 4 players still in, on random empty-handed survivors.
function HotPotato:_topUp()
	local ctx = self.context
	if not ctx:IsRunning() or ctx:TimeIsUp() then
		return
	end
	local alive = ctx:GetAlivePlayers()
	local want = Rules.PotatoesFor(#alive)
	local free = {}
	for _, player in alive do
		local _, _, root = ctx:GetCharacter(player)
		if root and not self:Busy(player) then
			table.insert(free, player)
		end
	end
	local now = ctx:Now()
	local dropped = {}
	while #self.potatoes < want and #free > 0 do
		local player = table.remove(free, rng:NextInteger(1, #free))
		self.nextId += 1
		local potato: Potato = {
			Id = self.nextId,
			Holder = player,
			From = nil,
			NoBackUntil = 0,
			LockUntil = now + Rules.LOCK,
			FuseEnd = now + Rules.FuseFor(rng:NextNumber(), #alive, self.started),
			Warned = false,
			Flight = nil,
		}
		table.insert(self.potatoes, potato)
		self:_speed(player)
		table.insert(dropped, player.UserId)
	end
	if #dropped > 0 then
		self:_publish()
		ctx:Fire(nil, "Drop", dropped)
	end
end

function HotPotato:_scheduleTopUp(seconds: number)
	if self.topUpPending then
		return
	end
	self.topUpPending = true
	self.context:Delay(seconds, function()
		self.topUpPending = false
		self:_topUp()
	end)
end

function HotPotato:_remove(potato: Potato)
	local index = table.find(self.potatoes, potato)
	if index then
		table.remove(self.potatoes, index)
	end
end

-- Where a potato is right now (over its holder's head, or along its flight).
function HotPotato:_where(potato: Potato): Vector3
	local ctx = self.context
	local flight = potato.Flight
	if flight then
		local _, _, toRoot = ctx:GetCharacter(flight.To)
		local b = if toRoot then toRoot.Position + Vector3.new(0, 3, 0) else flight.A
		return Rules.Arc(flight.A, b, (ctx:Now() - flight.T0) / (flight.T1 - flight.T0))
	end
	local holder = potato.Holder
	local root: BasePart? = nil
	if holder then
		local _, _, holderRoot = ctx:GetCharacter(holder)
		root = holderRoot
	end
	return if root then root.Position + Vector3.new(0, 3, 0) else self.center + Vector3.new(0, 3, 0)
end

-- A fuse ran out: its holder (or, mid-air, its thrower) is launched into the sky and is out.
function HotPotato:_explode(potato: Potato)
	local ctx = self.context
	local at = self:_where(potato)
	local victim = if potato.Flight then potato.Flight.From else potato.Holder
	self:_remove(potato)
	self:_publish()
	ctx:Fire(nil, "Boom", if victim then victim.UserId else 0, at.X, at.Y, at.Z)
	if victim and ctx:IsAlive(victim) then
		self.exploding[victim] = true
		local flat = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * 12
		ctx:Knockback(victim, flat + Vector3.new(0, LAUNCH_UP, 0), 2)
		ctx:Eliminate(victim, "Potato", SHOW_AFTER)
	end
	self:_scheduleTopUp(BREATHER)
end

-- `player` is gone (left, or out another way): whatever potato they had goes on to the nearest
-- player who can take it, with a few seconds left on its fuse, so it never vanishes or stalls.
function HotPotato:_letGo(player: any)
	local ctx = self.context
	local now = ctx:Now()
	for _, potato in table.clone(self.potatoes) do
		local flight = potato.Flight
		if flight and flight.From == player then
			flight.From = nil -- it still lands; if its fuse runs out first it just pops
		end
		if potato.Holder == player then
			local _, _, root = ctx:GetCharacter(player)
			local at = if root then root.Position else self.lastSeen[player] or self.center
			potato.Holder = nil
			potato.FuseEnd = math.max(potato.FuseEnd, now + Rules.WARN + 1.5)
			potato.Warned = false
			local to = self:_nearestTaker(potato, at, player)
			if to then
				self:_give(potato, to, nil, "Drop")
			else
				self:_remove(potato)
				self:_publish()
				self:_scheduleTopUp(BREATHER)
			end
		end
	end
end

-- Fair passes ---------------------------------------------------------------------------------------

-- Where `player` was at server time t (from the history; the newest sample if t is later).
function HotPotato:PositionAt(player: any, t: number): Vector3?
	local history: { Sample }? = self.history[player]
	if not history or #history == 0 then
		local _, _, root = self.context:GetCharacter(player)
		return root and root.Position
	end
	local newest = history[#history]
	if t >= newest.T then
		return newest.P
	end
	for index = #history - 1, 1, -1 do
		local a = history[index]
		if a.T <= t then
			local b = history[index + 1]
			local alpha = (t - a.T) / math.max(b.T - a.T, 1e-3)
			return a.P:Lerp(b.P, alpha)
		end
	end
	return history[1].P
end

-- Whether a pass `player` sent, heard at server time `heard`, reached `target`: the passer's own
-- positions as the press arrived are where they were on their screen, and each is matched with where
-- the target was drawn on that screen then: the passer's round trip plus the drawing delay earlier.
-- Bots see the server's world as it is, so theirs are judged on current positions.
function HotPotato:_reached(player: any, target: any, heard: number, reach: number): boolean
	local ctx = self.context
	local bot = BotRegistry.IsBot(player)
	local seenLag = pingOf(player) + SEEN_LAG
	local froms: { Sample } = {}
	if not bot then
		local history = self.history[player]
		if history then
			for index = #history, 1, -1 do
				local sample = history[index]
				if sample.T < heard - 0.1 then
					break
				end
				table.insert(froms, sample)
			end
		end
	end
	local _, _, root = ctx:GetCharacter(player)
	if root then
		table.insert(froms, { T = heard, P = root.Position })
	end
	local _, _, targetRoot = ctx:GetCharacter(target)
	for _, from in froms do
		if bot then
			if targetRoot and Rules.Reaches(from.P, targetRoot.Position, reach) then
				return true
			end
			continue
		end
		for _, shift in { -0.05, 0, 0.05 } do
			local at = self:PositionAt(target, from.T - seenLag + shift)
			if at and Rules.Reaches(from.P, at, reach) then
				return true
			end
		end
	end
	return false
end

-- A pass the server can't take: the passer's client drops its prediction.
function HotPotato:_refuse(player: any, potato: Potato?)
	self.context:Fire(player, "Refused", if potato then potato.Id else 0)
end

function HotPotato:_tryPass(player: any, targetId: any, throw: boolean)
	local ctx = self.context
	local potato = self:HolderOf(player)
	if not ctx:IsRunning() or ctx:TimeIsUp() or not potato then
		self:_refuse(player, potato)
		return
	end
	local now = ctx:Now()
	local target = self:_participant(targetId)
	if now < potato.LockUntil - 0.1 or target == nil or target == player or not self:CanTake(potato, target, now) then
		self:_refuse(player, potato)
		return
	end
	if not self:_reached(player, target, now, if throw then Rules.THROW_REACH else Rules.TAG_REACH) then
		self:_refuse(player, potato)
		return
	end
	if not throw then
		self:_give(potato, target, player, "Tag")
		return
	end
	local _, _, root = ctx:GetCharacter(player)
	potato.Holder = nil
	potato.From = player
	potato.Flight = {
		From = player,
		To = target,
		T0 = now,
		T1 = now + Rules.FLIGHT,
		A = (if root then root.Position else self.center) + Vector3.new(0, 3, 0),
	}
	self:_speed(player)
	self:_publish()
end

function HotPotato:Start()
	local ctx = self.context
	ctx:OnAction("Tag", function(player, targetId)
		self:_tryPass(player, targetId, false)
	end, { Interval = 0.1 })
	ctx:OnAction("Throw", function(player, targetId)
		self:_tryPass(player, targetId, true)
	end, { Interval = 0.25 })

	ctx:Delay(FIRST_DROP, function()
		self:_topUp()
	end)

	local sinceSample = math.huge
	local sinceNet = 0
	ctx:Heartbeat(function(dt)
		local now = ctx:Now()
		-- Everyone's recent positions (for fair passes).
		sinceSample += dt
		if sinceSample >= HISTORY_STEP then
			sinceSample = 0
			for _, player in ctx:GetAlivePlayers() do
				local _, _, root = ctx:GetCharacter(player)
				if not root then
					continue
				end
				local history = self.history[player]
				if not history then
					history = {}
					self.history[player] = history
				end
				table.insert(history, { T = now, P = root.Position })
				self.lastSeen[player] = root.Position
				while #history > 2 and history[1].T < now - HISTORY_KEEP do
					table.remove(history, 1)
				end
			end
		end
		-- Fuses, warnings and landings.
		local changed = false
		for _, potato in table.clone(self.potatoes) do
			if now >= potato.FuseEnd then
				self:_explode(potato)
				continue
			end
			if not potato.Warned and now >= potato.FuseEnd - Rules.WARN then
				potato.Warned = true
				changed = true
			end
			local flight = potato.Flight
			if flight and now >= flight.T1 then
				local to = flight.To
				if not ctx:IsAlive(to) then
					local _, _, root = ctx:GetCharacter(to)
					local at = if root then root.Position else self.lastSeen[to] or self.center
					to = self:_nearestTaker(potato, at, nil)
						or (if flight.From and ctx:IsAlive(flight.From) then flight.From else nil)
				end
				if to then
					self:_give(potato, to, flight.From, "Throw")
				else
					self:_remove(potato)
					changed = true
					self:_scheduleTopUp(BREATHER)
				end
			end
		end
		if changed then
			self:_publish()
		end
		-- The safety net: anyone found outside the fence (or under the lawn) goes back in.
		sinceNet += dt
		if sinceNet >= 0.2 then
			sinceNet = 0
			self:_keepInside()
		end
	end)
end

function HotPotato:_keepInside()
	local ctx = self.context
	local center = self.center
	local limit = self.radius - 1
	for _, player in ctx:GetAlivePlayers() do
		local _, _, root = ctx:GetCharacter(player)
		if not root or root.Anchored then
			continue
		end
		local offset = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
		local below = root.Position.Y < center.Y - 4
		if offset.Magnitude <= limit and not below then
			continue
		end
		local direction = if offset.Magnitude > 0.1 then offset.Unit else Vector3.new(1, 0, 0)
		local inside = center + direction * math.min(offset.Magnitude, self.radius - 3.5)
		local y = math.max(root.Position.Y, center.Y + 3)
		local look = root.CFrame.LookVector
		local at = Vector3.new(inside.X, y, inside.Z)
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.lookAt(at, at + Vector3.new(look.X, 0, look.Z + 1e-3))
	end
end

-- Time-out: everyone still holding a potato (or with one in the air) blows up; the rest survive.
function HotPotato:Stop(reason: string?)
	if reason ~= "TimeUp" then
		return
	end
	local ctx = self.context
	for _, potato in self.potatoes do
		local victim = if potato.Flight then potato.Flight.From else potato.Holder
		local at = self:_where(potato)
		ctx:Fire(nil, "Boom", if victim then victim.UserId else 0, at.X, at.Y, at.Z)
		if victim and ctx:IsAlive(victim) then
			self.blown[victim] = true
			ctx:Knockback(victim, Vector3.new(0, LAUNCH_UP, 0), 2)
		end
	end
	self.potatoes = {}
	self:_publish()
end

function HotPotato:GetResults()
	local ctx = self.context
	local results = ctx:SurvivalResults()
	for _, entry in results.Entries do
		local passes = self.passes[entry.Player] or 0
		if self.blown[entry.Player] then
			local lasted = entry.Survived or ctx:Elapsed()
			entry.Rank = math.floor(lasted * 10) / 10
			entry.ScoreText = "Blown up at the buzzer"
		end
		entry.ScoreText ..= ` · {passes} pass{if passes == 1 then "" else "es"}`
	end
	return results
end

return HotPotato

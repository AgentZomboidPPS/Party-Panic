-- Parasol Plummet (Luck, 35s, 1-12 players). After "Parasol Plummet" (Mario Party 3): everyone drifts
-- down a sunny sky holding an umbrella while throwers on clouds at both sides toss coins, fat coin bags
-- and the odd hammer across. OPEN the umbrella to float up slowly, hold DIVE to shut it and drop fast,
-- steer left and right to catch what flies by. A hammer stuns you and snaps your umbrella shut. The
-- most coins when the clock runs out wins.
--
-- One wide shared sky (Shared/Logic/ParasolPlummetSim: the box, the motion, the arcs, the catch
-- shapes), seen from the side. The server simulates every faller from their inputs (the client half
-- only sends "Input": steer -1..1 and umbrella open or shut, like Bobsled Run's server races the
-- sleds) and shares them ("Fallers", 10 times a second). The throwers' clouds bob on a shared clock;
-- the server picks each throw (thrower, kind, arc) and fires "Throw" a wind-up before it leaves the
-- hand, so every client draws the same arc from one event, and judges catches against that arc.
-- Coins and bags are lobbed high over the sky and land on the spot (of a few picked at random)
-- farthest from every faller, so the coins come to whoever goes for them; hammers fly at a faller
-- (often the leader).
--
-- Review pass (owner's review: "parking at a side wall beats playing"): the throwers' hands are just
-- outside the sky, so every throw used to pass the side walls first, in reach of anyone parked there;
-- an idle player at a wall averaged 2nd of 12. Now a coin can only be caught on its way down, inside
-- the middle of the sky (Sim.Catchable; clients draw it faded until then), and lands away from
-- everyone: a parked player gets next to nothing. Also from that review: inputs are re-sent while
-- held (a dropped release left DIVE stuck), the fallers are shared before anyone spawns (players fell
-- while SpawnAll waited), catches are judged in one short window (a laggy player used to get a longer
-- one), and the second after a stun, when no hammer can hit, is shared so clients blink the faller.
--
-- Fair catches (owner: "the precision games will feel super bad if we dont"): a player's faller on
-- the server is where their screen had it about a one-way trip ago (their inputs travel that long),
-- so the server tests it against where the coin was on their screen then: the arc a one-way trip
-- (plus a frame) back, give or take WINDOW. Coins also count against the umbrella they shut a moment
-- ago and a little outside the drawn shapes (generous); a hammer counts a little inside them, so a
-- dodge on screen is a dodge.
--
-- Nothing in the sky is solid (owner: "Theres invisible stuff you can jump on and hang on in several
-- games"): fallers fly where the server puts them, so every faller's character is put in a collision
-- group that touches nothing (not the clouds, not each other), and every prop here is non-colliding.
-- There is no ground: the sky goes on below and nobody can reach it.
--
-- Bots (Bots/ParasolPlummet.luau) press the same Input through ctx:BotAction and fly in the same
-- simulation, so every hammer that can stun a player stuns a bot exactly the same way (hazard
-- parity); the server moves bots' characters to their fallers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")

local GameDefinitions = require(ReplicatedStorage.Shared.GameDefinitions)
local Sim = require(ReplicatedStorage.Shared.Logic.ParasolPlummetSim)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local ParasolPlummet = MiniGame.Define("ParasolPlummet", { Results = "Score", ScoreUnit = "coins" })

local SKY_Y = 60 -- the middle of the sky above the arena origin
local FALLER_GROUP = "ParasolFaller"
local SHARE_EVERY = 0.1
local RUSH = 7 -- the last seconds are a COIN RUSH: more throws, more bags
local STEP = 1 / 30
local WINDOW = 0.05 -- seconds either side of what a player's screen showed that a catch is judged over

local rng = Random.new()

type Faller = {
	Player: any,
	Index: number,
	X: number,
	Y: number,
	VX: number,
	VY: number,
	Steer: number,
	Open: boolean,
	ShutAt: number, -- when the umbrella was last shut (a coin may still hit it on a laggy screen)
	StunUntil: number,
	SafeUntil: number,
	Coins: number,
	Bags: number,
	Bonks: number,
}
type Item = {
	Id: number,
	Kind: string,
	Thrower: number,
	At: number,
	X0: number,
	Y0: number,
	VX: number,
	VY: number,
}

local function round(x: number, step: number): number
	return math.floor(x / step + 0.5) * step
end

-- A player's one-way trip (half of GetNetworkPing's round trip); bots have none.
local function oneWay(player: any): number
	if BotRegistry.IsBot(player) then
		return 0
	end
	local ok, value = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and type(value) == "number" then math.clamp(value, 0, 0.5) / 2 else 0.08
end

local function coinText(n: number): string
	return if n == 1 then "1 coin" else `{n} coins`
end

-- Arena -------------------------------------------------------------------------------------------

function ParasolPlummet:_world(x: number, y: number, depth: number): Vector3
	return self.center + Vector3.new(x, y, depth)
end

-- A faller's frame: at its spot in the sky, facing the camera (+Z).
function ParasolPlummet:_frame(f: Faller): CFrame
	local position = self:_world(f.X, f.Y, Sim.Depth(f.Index))
	return CFrame.lookAt(position, position + Vector3.zAxis)
end

function ParasolPlummet:_buildArena()
	local arena = self.context.Arena
	local center = self.center

	-- The four throwers on their clouds (each a model the client half bobs on the shared clock).
	for index = 1, 4 do
		local x, y, side = Sim.ThrowerAt(index, 0)
		local holder = Instance.new("Model")
		holder.Name = `Thrower{index}`
		local base = CFrame.new(self:_world(x, y, 0))
		MeshLibrary.Get("ParasolPlummetCloud", { Scale = 1.2, CFrame = base * CFrame.new(0, -2.6, 0), Parent = holder })
		-- Turned mostly to the camera, a little toward the middle of the sky.
		MeshLibrary.Get("ParasolPlummetThrower", {
			Scale = 1.2,
			CFrame = base * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, math.pi + side * math.rad(35), 0),
			Parent = holder,
		})
		holder:PivotTo(base)
		holder.Parent = arena
	end

	-- A low sun and far cloud banks behind the sky, a sea of clouds far below, and hot-air balloons.
	MeshLibrary.Get("ParasolPlummetSun", {
		Scale = 1,
		CFrame = CFrame.new(center + Vector3.new(-170, 95, -520)) * CFrame.Angles(0, 0, math.rad(12)),
		Parent = arena,
	})
	local banks = {
		{ -260, 40, -330, 6 },
		{ -60, -35, -260, 5 },
		{ 190, 25, -360, 7 },
		{ 380, -20, -420, 6 },
		{ -420, -10, -460, 8 },
		{ 60, 80, -480, 5 },
		{ -150, 70, -400, 4.5 },
		{ 300, 85, -520, 6 },
	}
	for _, bank in banks do
		MeshLibrary.Get("ParasolPlummetCloud", {
			Scale = bank[4],
			CFrame = CFrame.new(center + Vector3.new(bank[1], bank[2], bank[3]))
				* CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
			Parent = arena,
		})
	end
	for column = -4, 4 do
		for row = 0, 2 do
			MeshLibrary.Get("ParasolPlummetCloud", {
				Scale = rng:NextNumber(6, 9),
				CFrame = CFrame.new(
					center
						+ Vector3.new(
							column * 120 + rng:NextNumber(-30, 30),
							-150 - row * 14 + rng:NextNumber(-6, 6),
							-120 - row * 170 + rng:NextNumber(-30, 30)
						)
				) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = arena,
			})
		end
	end
	for _, spot in { { -70, 40, -160, 1.4 }, { 95, 52, -300, 1.9 }, { -230, -15, -360, 2.2 } } do
		MeshLibrary.Get("ParasolPlummetBalloon", {
			Scale = spot[4],
			CFrame = CFrame.new(center + Vector3.new(spot[1], spot[2], spot[3])),
			Parent = arena,
		})
	end

	-- Sunny haze motes drifting up past the camera (ambient: off with reduced effects).
	local motes = Build.Decor({
		Name = "Motes",
		Size = Vector3.new(140, 1, 30),
		CFrame = CFrame.new(center + Vector3.new(0, -40, 10)),
		Transparency = 1,
		Parent = arena,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 250, 230))
	emitter.LightEmission = 0.4
	emitter.Transparency = NumberSequence.new(0.35)
	emitter.Size = NumberSequence.new(0.3)
	emitter.Lifetime = NumberRange.new(4, 6)
	emitter.Speed = NumberRange.new(16, 22)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Rate = 40
	emitter.Parent = motes
	CollectionService:AddTag(emitter, "PP_Ambient")

	-- Belt and braces: nothing in this arena is solid, queryable or touchable.
	for _, part in arena:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
end

-- Fallers touch nothing ---------------------------------------------------------------------------

local function setupGroup(): boolean
	local ok = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(FALLER_GROUP) then
			PhysicsService:RegisterCollisionGroup(FALLER_GROUP)
		end
		for _, group in PhysicsService:GetRegisteredCollisionGroups() do
			PhysicsService:CollisionGroupSetCollidable(FALLER_GROUP, group.name, false)
		end
	end)
	return ok
end

function ParasolPlummet:_ghost(character: Model)
	if not self.groupReady or self.ghosted[character] then
		return
	end
	local saved = {}
	self.ghosted[character] = saved
	local function apply(part: Instance)
		if part:IsA("BasePart") then
			if saved[part] == nil then
				saved[part] = part.CollisionGroup
			end
			part.CollisionGroup = FALLER_GROUP
		end
	end
	for _, part in character:GetDescendants() do
		apply(part)
	end
	self.context:Track(character.DescendantAdded:Connect(apply))
end

function ParasolPlummet:_unghostAll()
	for character, saved in self.ghosted do
		for part, group in saved do
			if part.Parent then
				part.CollisionGroup = group
			end
		end
		self.ghosted[character] = nil
	end
end

-- Round ------------------------------------------------------------------------------------------

-- Bots fly where the server has their faller (players' own clients move theirs).
function ParasolPlummet:_placeBot(player: any)
	local f = self.fallers[player]
	local character, humanoid, root = self.context:GetCharacter(player)
	if not f or not character or not humanoid or not root then
		return
	end
	if not root.Anchored then
		root.Anchored = true
	end
	if not humanoid.PlatformStand then
		humanoid.PlatformStand = true
	end
	root.CFrame = self:_frame(f)
end

function ParasolPlummet:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	local origin = ctx.Origin.Position
	self.center = origin + Vector3.new(0, SKY_Y, 0)
	ctx.KillY = origin.Y - 120 -- far below anything a faller can reach (Sim.Y_MIN)
	local definition = GameDefinitions.Get("ParasolPlummet")
	self.duration = if definition then definition.Duration else 35
	self.fallers = {} :: { [any]: Faller }
	self.items = {} :: { [number]: Item }
	self.nextId = 0
	self.ghosted = {} :: { [Model]: { [BasePart]: string } }
	self.groupReady = setupGroup()
	self.held = {} :: { [BasePart]: boolean }

	local players = ctx:GetPlayers()
	local list = {}
	for index, player in players do
		local x, y = Sim.StartAt(index, #players)
		self.fallers[player] = {
			Player = player,
			Index = index,
			X = x,
			Y = y,
			VX = 0,
			VY = 0,
			Steer = 0,
			Open = true,
			ShutAt = -math.huge,
			StunUntil = 0,
			SafeUntil = 0,
			Coins = 0,
			Bags = 0,
			Bonks = 0,
		}
		ctx:SetScoreText(player, coinText(0))
		table.insert(list, { U = player.UserId, I = index })
	end
	ctx:SetSharedJSON("Sky", {
		O = { self.center.X, self.center.Y, self.center.Z },
		P = list,
	})
	self:_buildArena()
	for _, name in
		{
			"ParasolPlummetUmbrella",
			"ParasolPlummetUmbrellaShut",
			"ParasolPlummetCoin",
			"ParasolPlummetBag",
			"ParasolPlummetHammer",
			"ParasolPlummetCloud",
		}
	do
		ctx:ShareTemplate(name, MeshLibrary.Get(name))
	end

	ctx.Hooks.CharacterReady = function(player, character)
		self:_ghost(character)
		if BotRegistry.IsBot(player) then
			self:_placeBot(player)
		elseif not self.startAt then
			-- Held where they spawned until GO: SpawnAll can take seconds, and with nothing solid in
			-- the sky an unanchored character would fall away before its client half takes it.
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.Anchored = true
				self.held[root] = true
			end
		end
	end
	ctx.Hooks.Respawn = function(player)
		local f = self.fallers[player]
		return if f then self:_frame(f) - Vector3.new(0, 3, 0) else nil
	end
	ctx.Hooks.PlayerLeft = function(player)
		self.fallers[player] = nil
	end
	local points = {}
	for _, player in players do
		table.insert(points, self:_frame(self.fallers[player]) - Vector3.new(0, 3, 0))
	end
	self:_share() -- (clients place their characters from this as soon as they spawn)
	ctx:SpawnAll(points, true)
	for _, player in players do
		local character = ctx:GetCharacter(player)
		if character then
			self:_ghost(character)
		end
		if BotRegistry.IsBot(player) then
			self:_placeBot(player)
		end
	end
	self:_share()
	ctx:SetStatus("Catch the coins!")
end

function ParasolPlummet:Start()
	local ctx = self.context
	self.startAt = ctx:Now()
	self.endAt = self.startAt + self.duration
	ctx:SetShared("Go", self.startAt) -- (clients start predicting their own faller from here)
	for root in self.held do
		if root.Parent then
			root.Anchored = false
		end
	end
	table.clear(self.held)
	-- Fallers whose character never loaded aren't in the round.
	for player in table.clone(self.fallers) do
		if not ctx:State(player) then
			self.fallers[player] = nil
		end
	end

	ctx:OnAction("Input", function(player, steer, open)
		local f = self.fallers[player]
		if not f or type(steer) ~= "number" or steer ~= steer or type(open) ~= "boolean" then
			return
		end
		f.Steer = math.clamp(steer, -1, 1)
		if f.Open and not open then
			f.ShutAt = ctx:Now()
		end
		f.Open = open
	end, { Interval = 0.015 })

	-- Small fixed steps, the same the clients predict with.
	self.carry = 0
	ctx:Heartbeat(function(dt)
		local now = ctx:Now()
		self.carry = math.min(self.carry + dt, 0.5)
		while self.carry >= STEP do
			self.carry -= STEP
			self:_tick(now - self.carry)
		end
		for player in self.fallers do
			if BotRegistry.IsBot(player) then
				self:_placeBot(player)
			end
		end
	end)
	ctx:Loop(function()
		return self:_throw()
	end)
	ctx:Loop(function()
		self:_share()
		return SHARE_EVERY
	end)
	ctx:Delay(math.max(0, self.duration - RUSH), function()
		ctx:Announce("💰 COIN RUSH! 💰", "warning", 2.5)
		ctx:Sound("HazardWarning")
	end)
end

function ParasolPlummet:_tick(now: number)
	for _, f in self.fallers do
		Sim.Step(f, f.Steer, f.Open, now < f.StunUntil, STEP)
	end
	-- Once per step: everyone in a fresh random order (nobody always wins a coin two of them reach
	-- together) with how far back their screen is.
	local order = self.order or {}
	self.order = order
	table.clear(order)
	for player, f in self.fallers do
		local back = 0
		if not BotRegistry.IsBot(player) then
			back = oneWay(player) + 1 / 30
		end
		table.insert(order, { F = f, Back = back })
	end
	for index = #order, 2, -1 do
		local other = rng:NextInteger(1, index)
		order[index], order[other] = order[other], order[index]
	end
	for id, item in self.items do
		if now < item.At then
			continue
		end
		if Sim.Gone(item, now) then
			self.items[id] = nil
			continue
		end
		if item.Kind == "Hammer" then
			self:_hammer(item, now, order)
		else
			self:_coin(item, now, order)
		end
	end
end

type Seat = { F: Faller, Back: number }

-- Coins and bags: caught where the player's screen had them (a one-way trip back, give or take
-- WINDOW), only while they're catchable there (falling, in the middle of the sky).
function ParasolPlummet:_coin(item: Item, now: number, order: { Seat })
	local kind = Sim.Kinds[item.Kind]
	for _, seat in order do
		local f = seat.F
		local seen = now - seat.Back
		local open = f.Open or now - f.ShutAt <= seat.Back + 0.1
		for _, t in { seen - WINDOW, seen, seen + WINDOW } do
			t = math.clamp(t, item.At, now)
			if not Sim.Catchable(item, t) then
				continue
			end
			local x, y = Sim.ItemAt(item, t)
			if Sim.Touches(f.X, f.Y, open, x, y, kind.Radius, 0.35) then
				self.items[item.Id] = nil
				f.Coins += kind.Value
				if item.Kind == "Bag" then
					f.Bags += 1
				end
				self.context:AddScore(f.Player, kind.Value)
				self.context:SetScoreText(f.Player, coinText(f.Coins))
				self.context:Fire(nil, "Take", item.Id, f.Player.UserId, kind.Value)
				return
			end
		end
	end
end

-- Hammers: only where the player's screen had it, a little inside the drawn shapes.
function ParasolPlummet:_hammer(item: Item, now: number, order: { Seat })
	local kind = Sim.Kinds.Hammer
	for _, seat in order do
		local f = seat.F
		if now < f.SafeUntil then
			continue
		end
		local x, y = Sim.ItemAt(item, math.max(item.At, now - seat.Back))
		if Sim.Touches(f.X, f.Y, f.Open, x, y, kind.Radius, -0.3) then
			self.items[item.Id] = nil
			f.StunUntil = now + Sim.STUN
			f.SafeUntil = f.StunUntil + Sim.SAFE
			f.Bonks += 1
			self.context:Fire(nil, "Bonk", item.Id, f.Player.UserId, round(f.StunUntil, 0.001))
			return
		end
	end
end

-- Picks the next throw, announces it a wind-up ahead, and returns the seconds to the one after.
function ParasolPlummet:_throw(): number?
	local ctx = self.context
	local now = ctx:Now()
	local left = self.endAt - now
	if left < Sim.WINDUP + 0.6 then
		return nil
	end
	local count = 0
	local targets = {}
	for _, f in self.fallers do
		count += 1
		table.insert(targets, f)
	end
	local rush = left <= RUSH
	local progress = math.clamp((now - self.startAt) / self.duration, 0, 1)
	local rate = (1.3 + 0.17 * math.max(count, 1)) * (if rush then 1.6 else 1)

	-- Which thrower (never the same one twice running) and what it throws.
	local thrower = rng:NextInteger(1, 4)
	if thrower == self.lastThrower then
		thrower = thrower % 4 + 1
	end
	self.lastThrower = thrower
	local roll = rng:NextNumber()
	local hammerChance = if rush then 0.1 else 0.08 + 0.1 * progress
	local bagChance = if rush then 0.22 else 0.08
	local kind = if roll < hammerChance and #targets > 0
		then "Hammer"
		elseif roll < hammerChance + bagChance then "Bag"
		else "Coin"

	local at = now + Sim.WINDUP
	local cx, cy, side = Sim.ThrowerAt(thrower, at)
	local hx, hy = Sim.HandOffset(side)
	local x0, y0 = cx + hx, cy + hy
	local g = -Sim.GRAVITY
	local vx, vy
	if kind == "Hammer" then
		-- At a faller (where they are now: they have the wind-up and the flight to dodge it), often
		-- the one with the most coins.
		local f = targets[rng:NextInteger(1, #targets)]
		if rng:NextNumber() < 0.35 then
			for _, other in targets do
				if other.Coins > f.Coins then
					f = other
				end
			end
		end
		local tx = math.clamp(f.X + rng:NextNumber(-2.5, 2.5), -Sim.HALF_W, Sim.HALF_W)
		local ty = math.clamp(f.Y + rng:NextNumber(-1, 3), Sim.Y_MIN, Sim.Y_MAX + 4)
		vx, vy = Sim.Aim(x0, y0, tx, ty, math.clamp(math.abs(tx - x0) / 26, 1.0, 1.8))
		vy = math.clamp(vy, -6, math.sqrt(2 * g * math.max(0, Sim.Y_MAX + 5 - y0)))
	else
		-- A high lob over the sky, coming down on the spot (of a few picked at random) farthest from
		-- every faller: catchable only on the way down in the middle of the sky (Sim.Catchable), it
		-- goes to whoever flies to it, never to someone parked by a wall.
		local peak = rng:NextNumber(Sim.Y_MAX + Sim.LOB_PEAK[1], Sim.Y_MAX + Sim.LOB_PEAK[2])
		vy = math.sqrt(2 * g * math.max(0, peak - y0))
		local tx, ty, far = 0, 0, -1
		for _ = 1, 6 do
			local x = rng:NextNumber(-Sim.CATCH_X + 1, Sim.CATCH_X - 1)
			local y = rng:NextNumber(Sim.Y_MIN + 1, Sim.CATCH_TOP - 1)
			local gap = math.huge
			for _, f in targets do
				gap = math.min(gap, math.abs(f.X - x) + 0.5 * math.abs(f.Y - y))
			end
			if gap > far then
				tx, ty, far = x, y, gap
			end
		end
		local seconds = (vy + math.sqrt(vy * vy + 2 * g * math.max(0, y0 - ty))) / g
		vx = (tx - x0) / seconds
	end
	self.nextId += 1
	local item: Item = {
		Id = self.nextId,
		Kind = kind,
		Thrower = thrower,
		At = round(at, 0.001),
		X0 = round(x0, 0.01),
		Y0 = round(y0, 0.01),
		VX = round(vx, 0.01),
		VY = round(vy, 0.01),
	}
	self.items[item.Id] = item
	ctx:Fire(nil, "Throw", item.Id, kind, thrower, item.At, item.X0, item.Y0, item.VX, item.VY)
	return rng:NextNumber(0.7, 1.3) / rate
end

function ParasolPlummet:_share()
	local ctx = self.context
	local list = {}
	local best, bestCoins, tie = nil, -1, false
	local now = ctx:Now()
	for player, f in self.fallers do
		list[tostring(player.UserId)] = {
			x = round(f.X, 0.01),
			y = round(f.Y, 0.01),
			vx = round(f.VX, 0.01),
			vy = round(f.VY, 0.01),
			o = if f.Open then 1 else 0,
			st = if now < f.StunUntil then round(f.StunUntil, 0.001) else nil,
			sf = if now < f.SafeUntil then round(f.SafeUntil, 0.001) else nil,
			c = f.Coins,
		}
		if f.Coins > bestCoins then
			best, bestCoins, tie = f, f.Coins, false
		elseif f.Coins == bestCoins then
			tie = true
		end
	end
	ctx:SetSharedJSON("Fallers", { T = round(now, 0.001), F = list })
	if self.startAt then
		local status = if best
				and bestCoins > 0
				and not tie
			then `👑 {best.Player.DisplayName} leads with {coinText(bestCoins)}`
			elseif bestCoins > 0 then `👑 Tied at {coinText(bestCoins)}!`
			else "Catch the coins!"
		if status ~= self.status then
			self.status = status
			ctx:SetStatus(status)
		end
	end
end

function ParasolPlummet:Stop(_reason: string?)
	self.over = true
	self.context:SetShared("Over", true)
	self:_share()
end

function ParasolPlummet:GetResults()
	local results = self.context:ScoreResults("coins")
	for _, entry in results.Entries do
		local f = self.fallers[entry.Player]
		if f then
			entry.Rank = f.Coins
			entry.BestScore = f.Coins
			entry.ScoreText = if f.Bags > 0 then `{coinText(f.Coins)} • 💰x{f.Bags}` else coinText(f.Coins)
		end
	end
	return results
end

function ParasolPlummet:Cleanup()
	for root in self.held or {} do
		if root.Parent then
			root.Anchored = false
		end
	end
	self:_unghostAll()
end

return ParasolPlummet

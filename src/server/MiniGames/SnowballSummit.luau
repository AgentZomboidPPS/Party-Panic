-- Snowball Summit (Knockback, 60s, 2-12 players). After "Snowball Summit" from Mario Party 3:
-- everyone stands on a frozen mountain top above the clouds. Hold ROLL while you walk and a snowball
-- grows in front of you; let go and it rolls off the way you face. A snowball that hits someone
-- knocks them back (bigger balls, much farther), two snowballs that meet burst, and anyone knocked
-- off the summit falls into the clouds and is out. Everyone still on top when time runs out wins;
-- the rest rank by how long they lasted (knock-offs break ties).
--
-- How it works (the server owns all of it):
--   * The summit is a disc of radius self.radius (bigger with more players). Its snowfield is one
--     real part (what everyone stands on, exactly as drawn); the Peak mesh around it (ice band, lip,
--     icicles, the mountain below) never collides.
--   * Held snowballs (self.held): "Build" starts one in front of the player; every stud the player's
--     root moves grows it (GROW), up to MAX_R, and slows them down. Clients draw it in front of the
--     holder's character from the shared radius (MG_Held), so it's smooth.
--   * "Throw" launches it. A thrown ball follows a fixed schedule (start, direction, speed, a little
--     slowing, then a fall once its middle passes the rim) shared in MG_Balls, which every client
--     animates from the same clock. The server checks hits along the same schedule.
--   * Fair hits: each person is judged against the ball where their own screen showed it, half
--     their ping earlier (FireRope's lag leeway); bots, which the server moves, with no delay. A hit
--     needs the ball's drawn sphere (radius = its size, the mesh is radius 1 scaled to it) to overlap
--     the character's body (BODY across, from the feet up 5 studs): jump over a small ball and it
--     misses. Thrown balls that meet each other (or a held ball) burst together.
--   * Knockback: ctx:Knockback for people (their device flies them). Bots are flown by the server on
--     the same arc (anchored, self.flights), so they fall off exactly like a person would, also on
--     the test server, which has no physics.
--     A flown bot slides SLIDE_TIME on landing, about as far as a person tumbles. People knocked
--     can't start a ball until they're back up (knockedUntil).
--   * Falls: anyone whose root is past the rim and dropping, or well past it (OUT_FAR: a root can
--     rest about a stud past the drawn edge) for OUT_TIME, is out; ctx.KillY catches the rest. A
--     knock-off within CREDIT_TIME of a hit counts for the thrower. Everyone out in one step goes
--     out together, and the last-one-standing end (_checkEnd, the mode's own) waits for anyone
--     still teetering past the rim.
-- Bots (Bots/SnowballSummit.luau) roll balls round the summit, throw at rivals near the edge, and
-- sidestep or hop over balls coming at them.
--
-- Sweep pass (owner: "Let's do a full bug and clean sweep."; "Bots are still rubber banding on
-- spleef"): a flown bot's root goes straight back to the server when it's let go (landing, a lost
-- flight, cleanup). Unanchored and left as it was, the engine could hand it to the nearest player's
-- device for a moment, and the bot snapped when the server took it back.

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local SnowballSummit = MiniGame.Define("SnowballSummit", { Results = "Survival" })

local MIN_R, MAX_R = 0.8, 3.2 -- snowball radius while it grows
local GROW = 0.042 -- radius per stud rolled (smallest to biggest: about 57 studs)
local BLIZZARD_GROW = 1.6 -- growth multiplier in the last BLIZZARD_AT of the round
local BLIZZARD_AT = 0.72 -- share of the round before the blizzard
local BODY = 1.0 -- half a character's width
local BODY_H = 5 -- a character's height from the feet
local HOLD_GAP = 0.5 -- between a character's front and its held ball
local THROW_SPEED = 56 -- studs/s for the smallest ball
local THROW_SLOW = 4.5 -- studs/s less per stud of radius
local DECEL = 5 -- studs/s^2 a rolling ball slows by
local BALL_LIFE = 6 -- seconds before a ball that somehow stayed on top melts
local FALL_SHOW = 1.6 -- seconds a ball that rolled off stays shared (clients show it falling)
local COOLDOWN = 0.45 -- after a throw, before the next ball can be started
local SLACK = 0.03 -- seconds of leeway either way on a person's delay (ping jitter), in their favour
local PING_MAX = 0.4
local CREDIT_TIME = 5
local OUT_DROP = 2.5 -- past the rim (OUT_NEAR) and this far below standing height: out
local OUT_NEAR = 0.6 -- root this far past the rim and dropping: falling
local OUT_FAR = 1.2 -- root this far past the rim (a root can rest ~1 stud out on the drawn edge)...
local OUT_TIME = 0.9 -- ...this long, falling or not: out
local KNOCKED = 0.35 -- after a knock lands (stun), before a person can start a ball again
local SLIDE_TIME = 0.6 -- a flown bot's slide after landing (people tumble on their own device)
local SLIDE_SHARE = 0.45 -- of its knock's ground speed it slides off with
local G = 196.2

SnowballSummit.MIN_R = MIN_R
SnowballSummit.MAX_R = MAX_R
SnowballSummit.BODY = BODY

type Ball = {
	Id: number,
	Owner: any,
	P0: Vector3, -- its middle at launch
	Dir: Vector3,
	Speed: number,
	T0: number,
	R: number,
	Edge: number, -- when its middle passes the rim (math.huge if never)
	StopT: number, -- when it would stop rolling
}

type Held = { R: number, Last: Vector3 }

type Flight = { Start: number, P0: Vector3, V: Vector3, Phase: string, Character: Model, Since: number }

-- Platform radius for a number of players: room to roll a ball round everyone.
function SnowballSummit.RadiusFor(count: number): number
	return math.clamp(19 + 1.75 * count, 24, 40)
end

-- How far a thrown ball has rolled `dt` seconds after launch (it slows, never backs up).
local function rolled(ball: Ball, dt: number): number
	local t = math.clamp(dt, 0, ball.StopT)
	return ball.Speed * t - 0.5 * DECEL * t * t
end

-- A thrown ball's middle at server time t: rolling on the snow, then dropping past the rim.
function SnowballSummit:BallAt(ball: Ball, t: number): Vector3
	local flat = ball.P0 + ball.Dir * rolled(ball, t - ball.T0)
	local y = self.topY + ball.R
	if t > ball.Edge then
		local fall = t - ball.Edge
		y -= 0.5 * G * fall * fall
	end
	return Vector3.new(flat.X, y, flat.Z)
end

local function standingHeight(humanoid: Humanoid?, root: BasePart): number
	if humanoid then
		local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2
		if legs > 1.5 and legs < 6 then
			return legs
		end
	end
	return 3
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Lets a flown bot go: unanchored and given straight back to the server (an unanchored root left as
-- it is can be handed to the nearest player's device until the server takes it back, and the bot
-- snaps).
local function release(bot: any, root: BasePart)
	root.Anchored = false
	if BotRegistry.IsBot(bot) then
		pcall(root.SetNetworkOwner, root, nil)
	end
end

function SnowballSummit:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	-- The last-one-standing end is this mode's own (_checkEnd): everyone a step puts out goes out
	-- together, and the round waits for anyone still mid-fall off the rim.
	ctx.EndWhenOneLeft = false
	local origin = ctx.Origin.Position
	self.center = origin
	self.topY = origin.Y
	ctx.KillY = origin.Y - 40
	self.radius = SnowballSummit.RadiusFor(#ctx:GetPlayers())
	self.held = {} :: { [any]: Held }
	self.balls = {} :: { [number]: Ball }
	self.nextId = 0
	self.cooldown = {} :: { [any]: number }
	self.flights = {} :: { [any]: Flight }
	self.knocks = {} :: { [any]: { Start: number, P0: Vector3, V: Vector3 } } -- people's knocks (the test bot replays them)
	self.lastHit = {} :: { [any]: { By: any, T: number } }
	self.outSince = {} :: { [any]: number } -- past the rim (OUT_NEAR) since
	self.farSince = {} :: { [any]: number } -- past OUT_FAR since
	self.knockedUntil = {} :: { [any]: number }
	self.kos = {} :: { [any]: number }
	self.blizzard = false

	self:_buildScenery()

	local players = ctx:GetPlayers()
	local spawns = {}
	local ring = self.radius * 0.55
	for index = 1, #players do
		local angle = (index - 1) / #players * math.pi * 2
		local position = origin + Vector3.new(math.cos(angle) * ring, 0, math.sin(angle) * ring)
		table.insert(spawns, CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z)))
	end
	ctx:SpawnAll(spawns, true)
	for _, player in players do
		self.kos[player] = 0
	end
	ctx:SetSharedJSON("Summit", { X = origin.X, Y = origin.Y, Z = origin.Z, R = self.radius, D = DECEL, G = G })
	ctx:SetSharedJSON("Balls", {})
	ctx:SetSharedJSON("Held", {})
	ctx:ShareTemplate("Snowball", MeshLibrary.Get("SnowballSummitSnowball"))
	ctx:SetStatus("Roll snowballs, knock rivals off!")

	ctx.Hooks.Eliminated = function(player)
		self:_dropHeld(player, true)
	end
end

-- The summit, the cloud sea and the mountains around.
function SnowballSummit:_buildScenery()
	local ctx = self.context
	local origin = self.center
	local radius = self.radius
	local scale = radius / 32
	local rng = Random.new()

	-- The snowfield everyone stands on: one real cylinder, its top exactly the platform's top.
	local thick = 3 * scale
	Build.Part({
		Name = "SnowballSummitSnowfield",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thick, radius * 2, radius * 2),
		CFrame = CFrame.new(origin - Vector3.new(0, thick / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(246, 250, 255),
		Material = Enum.Material.Snow,
		Parent = ctx.Arena,
	})
	-- The ice band, lip and mountain (its top 0.05 above the snowfield, never colliding).
	MeshLibrary.Get("SnowballSummitPeak", {
		Scale = scale,
		CFrame = CFrame.new(origin + Vector3.new(0, 0.05 - 46 * scale, 0)),
		Parent = ctx.Arena,
	})

	-- The sea of clouds far below, with soft puffs drifting over it.
	local cloudY = origin.Y - 70
	Build.Decor({
		Name = "SnowballSummitClouds",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 1800, 1800),
		CFrame = CFrame.new(origin.X, cloudY - 1, origin.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(222, 234, 250),
		Material = Enum.Material.SmoothPlastic,
		Parent = ctx.Arena,
	})
	-- Billowing clouds drifting on it.
	for _ = 1, 30 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(radius + 12, 320)
		MeshLibrary.Get("SnowballSummitCloud", {
			Scale = rng:NextNumber(1, 2.2),
			CFrame = CFrame.new(
				origin.X + math.cos(angle) * distance,
				cloudY - rng:NextNumber(1.5, 3),
				origin.Z + math.sin(angle) * distance
			) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = ctx.Arena,
		})
	end

	-- Rock spires round the summit, each with a pine or two and a flag on its snowy top.
	local spires = 6
	for index = 0, spires - 1 do
		local angle = (index + rng:NextNumber(-0.2, 0.2)) / spires * math.pi * 2 + 0.3
		local distance = radius + rng:NextNumber(26, 44)
		local spireScale = rng:NextNumber(0.85, 1.1)
		local topDrop = rng:NextNumber(6, 20)
		local base = Vector3.new(
			origin.X + math.cos(angle) * distance,
			origin.Y - topDrop - 60 * spireScale,
			origin.Z + math.sin(angle) * distance
		)
		MeshLibrary.Get("SnowballSummitSpire", {
			Scale = spireScale,
			CFrame = CFrame.new(base) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = ctx.Arena,
		})
		local top = base + Vector3.new(0, 60 * spireScale, 0)
		local facing = CFrame.lookAt(top, Vector3.new(origin.X, top.Y, origin.Z))
		MeshLibrary.Get("SnowballSummitPine", {
			Scale = rng:NextNumber(0.8, 1.05),
			CFrame = facing
				* CFrame.new(rng:NextNumber(-1.5, 1.5), -0.3, 1.5)
				* CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			Parent = ctx.Arena,
		})
		if index % 2 == 0 then
			MeshLibrary.Get("SnowballSummitPine", {
				Scale = rng:NextNumber(0.55, 0.7),
				CFrame = facing * CFrame.new(3.2, -0.4, -1) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
				Parent = ctx.Arena,
			})
		end
		MeshLibrary.Get("SnowballSummitFlag", {
			CFrame = facing * CFrame.new(-3, -0.2, -2.6) * CFrame.Angles(0, math.rad(rng:NextNumber(-40, 40)), 0),
			Parent = ctx.Arena,
		})
	end

	-- Big mountains on the horizon, rising out of the clouds.
	for index = 0, 6 do
		local angle = index / 7 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local distance = rng:NextNumber(330, 470)
		local mountainScale = rng:NextNumber(1.2, 1.9)
		MeshLibrary.Get("SnowballSummitMountain", {
			Scale = mountainScale,
			CFrame = CFrame.new(
				origin.X + math.cos(angle) * distance,
				cloudY - 30,
				origin.Z + math.sin(angle) * distance
			) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = ctx.Arena,
		})
	end
end

-- Where a held ball's middle is: in front of its holder, resting on the snow.
function SnowballSummit:_heldCenter(root: BasePart, r: number): Vector3
	local look = flat(root.CFrame.LookVector)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local spot = root.Position + look * (BODY + HOLD_GAP + r)
	return Vector3.new(spot.X, self.topY + r, spot.Z)
end

-- How long ago, in server time, a participant's own screen showed what the server sees now.
local function seenDelay(player: any): number
	if BotRegistry.IsBot(player) then
		return 0
	end
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	return 0.03 + (if ok and type(ping) == "number" then math.clamp(ping, 0, PING_MAX) / 2 else 0.05)
end

function SnowballSummit:_publishBalls()
	local list = {}
	for _, ball in self.balls do
		table.insert(list, {
			I = ball.Id,
			U = ball.Owner.UserId,
			X = math.round(ball.P0.X * 100) / 100,
			Z = math.round(ball.P0.Z * 100) / 100,
			DX = math.round(ball.Dir.X * 10000) / 10000,
			DZ = math.round(ball.Dir.Z * 10000) / 10000,
			S = ball.Speed,
			T = ball.T0,
			R = math.round(ball.R * 100) / 100,
			E = if ball.Edge == math.huge then -1 else ball.Edge,
		})
	end
	self.context:SetSharedJSON("Balls", list)
end

function SnowballSummit:_publishHeld(force: boolean?)
	local map = {}
	local keys = {}
	for player, held in self.held do
		local key = tostring(player.UserId)
		map[key] = math.round(held.R * 20) / 20
		table.insert(keys, key)
	end
	table.sort(keys)
	local signature = ""
	for _, key in keys do
		signature ..= `{key}={map[key]};`
	end
	if force or signature ~= self.heldSignature then
		self.heldSignature = signature
		self.context:SetSharedJSON("Held", map)
	end
end

function SnowballSummit:_setSpeed(player: any)
	local ctx = self.context
	if ctx:IsStunned(player) or self.flights[player] or not ctx:IsAlive(player) then
		return
	end
	local held = self.held[player]
	local base = ctx.WalkSpeed
	ctx:SetWalkSpeed(player, if held then base * (1 - 0.28 * (held.R - MIN_R) / (MAX_R - MIN_R)) else base)
end

-- Removes a player's held ball (bursting it where it was, if `burst`).
function SnowballSummit:_dropHeld(player: any, burst: boolean)
	local held = self.held[player]
	if not held then
		return
	end
	self.held[player] = nil
	if burst then
		local _, _, root = self.context:GetCharacter(player)
		if root then
			local spot = self:_heldCenter(root, held.R)
			self.context:Fire(nil, "Smash", spot.X, spot.Y, spot.Z, held.R)
		end
	end
	self:_publishHeld(true)
	self:_setSpeed(player)
end

function SnowballSummit:_build(player: any)
	local ctx = self.context
	if self.held[player] or self.flights[player] or ctx:IsStunned(player) then
		return
	end
	if (self.cooldown[player] or 0) > ctx:Now() or (self.knockedUntil[player] or 0) > ctx:Now() then
		return
	end
	local _, humanoid, root = ctx:GetCharacter(player)
	if not root or math.abs(root.Position.Y - self.topY) > 8 or (humanoid and humanoid.PlatformStand) then
		return
	end
	self.held[player] = { R = MIN_R, Last = flat(root.Position) }
	self:_publishHeld(true)
	self:_setSpeed(player)
end

function SnowballSummit:_throw(player: any, dx: any, dz: any)
	local ctx = self.context
	local held = self.held[player]
	if not held then
		return
	end
	local _, _, root = ctx:GetCharacter(player)
	self.held[player] = nil
	self:_publishHeld(true)
	self:_setSpeed(player)
	if not root then
		return
	end
	local now = ctx:Now()
	self.cooldown[player] = now + COOLDOWN
	local look = flat(root.CFrame.LookVector)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local dir = look
	-- The device's own facing (what the player saw when they let go) if it's a sane direction near
	-- the server's view of it; bots aim exactly.
	if type(dx) == "number" and type(dz) == "number" and dx == dx and dz == dz then
		local wanted = Vector3.new(dx, 0, dz)
		if wanted.Magnitude > 0.5 and wanted.Magnitude < 1.5 then
			wanted = wanted.Unit
			if BotRegistry.IsBot(player) or wanted:Dot(look) > math.cos(math.rad(70)) then
				dir = wanted
			end
		end
	end
	-- It sets off from in front of the thrower along the throw (the held ball swings round to it).
	local spot = root.Position + dir * (BODY + HOLD_GAP + held.R)
	local start = Vector3.new(spot.X, self.topY + held.R, spot.Z)
	local speed = THROW_SPEED - THROW_SLOW * held.R
	self.nextId += 1
	local ball: Ball = {
		Id = self.nextId,
		Owner = player,
		P0 = start,
		Dir = dir,
		Speed = speed,
		T0 = now,
		R = held.R,
		Edge = math.huge,
		StopT = speed / DECEL,
	}
	-- When its middle passes the rim: |P0 + Dir*d - C| = radius, the forward root.
	local rel = flat(start - self.center)
	local b = rel:Dot(dir)
	local c = rel:Dot(rel) - self.radius * self.radius
	local disc = b * b - c
	if disc >= 0 then
		local d = -b + math.sqrt(disc)
		local maxD = rolled(ball, ball.StopT)
		if d <= 0 then
			ball.Edge = now
		elseif d < maxD then
			-- Solve speed*t - DECEL/2 t^2 = d for the first t.
			local s = speed * speed - 2 * DECEL * d
			ball.Edge = now + (speed - math.sqrt(math.max(0, s))) / DECEL
		end
	end
	self.balls[ball.Id] = ball
	self:_publishBalls()
	ctx:Fire(nil, "Throw", player.UserId, ball.R)
end

-- Throws someone: people fly on their own device, bots on the server along the same arc.
function SnowballSummit:_knock(victim: any, ball: Ball, at: Vector3)
	local ctx = self.context
	local _, _, root = ctx:GetCharacter(victim)
	if not root then
		return
	end
	local away = flat(root.Position - at)
	away = if away.Magnitude > 0.05 then away.Unit else ball.Dir
	local dir = (ball.Dir * 0.6 + away * 0.4)
	dir = if dir.Magnitude > 0.05 then dir.Unit else ball.Dir
	local r = ball.R
	-- Steeper with size at the small end, so a stream of tiny balls never beats rolling a big one
	-- (smallest ~10 studs of flight, biggest ~50).
	local velocity = dir * (10 + 28 * r) + Vector3.new(0, 22 + 9 * r, 0)
	local stun = 0.35 + 0.1 * r
	self.knockedUntil[victim] = ctx:Now() + 2 * velocity.Y / G + stun + KNOCKED
	self:_dropHeld(victim, true)
	self.lastHit[victim] = { By = ball.Owner, T = ctx:Now() }
	if BotRegistry.IsBot(victim) then
		local character = victim.Character
		if character then
			root.Anchored = true
			self.flights[victim] = {
				Start = ctx:Now(),
				P0 = root.Position,
				V = velocity,
				Phase = "air",
				Character = character,
				Since = 0,
			}
		end
	else
		self.knocks[victim] = { Start = ctx:Now(), P0 = root.Position, V = velocity }
		ctx:Knockback(victim, velocity, stun)
	end
end

-- Moves the bots the server is flying: up and out on the knock's arc, then a short slide on landing
-- (or a fall, past the rim). Runs every frame.
function SnowballSummit:_fly(now: number)
	for bot, flight in self.flights do
		local character = flight.Character
		local root = character and character.Parent and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or bot.Character ~= character or now - flight.Start > 4 then
			if root then
				release(bot, root)
			end
			self.flights[bot] = nil
			continue
		end
		local position = self:FlightAt(flight, now)
		if not position then
			-- Landed on the summit: let the bot walk again.
			release(bot, root)
			self.flights[bot] = nil
			self:_setSpeed(bot)
			continue
		end
		character:PivotTo(CFrame.lookAt(position, position - flat(flight.V) + Vector3.new(0, 0.001, 0)))
	end
end

-- Where a flown character's root is at time t on a knock (start position P0, velocity V), or nil
-- once it has landed back on the summit and slid to a stop. Past the rim it keeps falling.
function SnowballSummit:FlightAt(flight: { Start: number, P0: Vector3, V: Vector3 }, t: number): Vector3?
	local dt = t - flight.Start
	local p0, v = flight.P0, flight.V
	local vy = v.Y
	local hv = flat(v)
	local airTime = 2 * vy / G
	local function inside(p: Vector3): boolean
		return flat(p - self.center).Magnitude <= self.radius + 0.6
	end
	if dt <= airTime then
		return p0 + hv * dt + Vector3.new(0, vy * dt - 0.5 * G * dt * dt, 0)
	end
	local landing = p0 + hv * airTime
	if not inside(landing) then
		local fall = dt - airTime
		return landing + hv * fall + Vector3.new(0, -vy * fall - 0.5 * G * fall * fall, 0)
	end
	-- A slide on the snow, slowing to a stop over SLIDE_TIME (a person's tumble is about this long).
	local slide = SLIDE_TIME
	local s = math.min(dt - airTime, slide)
	local slideSpeed = hv * SLIDE_SHARE
	local spot = landing + slideSpeed * (s - 0.5 * s * s / slide)
	if not inside(spot) then
		local fall = dt - airTime - s
		if fall > 0 or s >= slide then
			return spot + slideSpeed * 0.2 * fall + Vector3.new(0, -0.5 * G * fall * fall, 0)
		end
		return spot
	end
	if dt - airTime >= slide then
		return nil
	end
	return spot
end

function SnowballSummit:Start()
	local ctx = self.context
	self.standing = {}
	for _, player in ctx:GetAlivePlayers() do
		local _, humanoid, root = ctx:GetCharacter(player)
		self.standing[player] = if root then standingHeight(humanoid, root) else 3
	end

	ctx:OnAction("Build", function(player)
		self:_build(player)
	end, { Interval = 0.1 })
	ctx:OnAction("Throw", function(player, dx, dz)
		self:_throw(player, dx, dz)
	end, { Interval = 0.1 })

	local lastHeldPublish = 0
	ctx:Heartbeat(function(dt)
		local now = ctx:Now()
		self:_fly(now)
		self:_grow(dt)
		if now - lastHeldPublish > 0.12 then
			lastHeldPublish = now
			self:_publishHeld()
		end
		self:_collide(now)
		self:_falls(now)
	end)

	ctx:Loop(function()
		if not self.blizzard and ctx:Progress() >= BLIZZARD_AT then
			self.blizzard = true
			ctx:SetShared("Blizzard", true)
			ctx:Announce("Blizzard! Snowballs grow faster!", "warning", 3)
			ctx:Sound("HazardWarning")
		end
		ctx:SetStatus(`On the summit: {ctx:AliveCount()}`)
		return 0.5
	end)
end

-- Held balls grow with every stud their holder rolls them.
function SnowballSummit:_grow(dt: number)
	local ctx = self.context
	local factor = if self.blizzard then BLIZZARD_GROW else 1
	for player, held in self.held do
		local _, humanoid, root = ctx:GetCharacter(player)
		if not root or not ctx:IsAlive(player) then
			self.held[player] = nil
			continue
		end
		local here = flat(root.Position)
		-- Only walking grows it: never faster than the holder can walk (a little slack for lag).
		local speed = if humanoid then humanoid.WalkSpeed else ctx.WalkSpeed
		local moved = math.min((here - held.Last).Magnitude, speed * math.max(dt, 1 / 60) * 1.3)
		held.Last = here
		if held.R < MAX_R and moved > 0.01 then
			local before = held.R
			held.R = math.min(MAX_R, held.R + moved * GROW * factor)
			if math.floor(before * 4) ~= math.floor(held.R * 4) then
				self:_setSpeed(player)
			end
		end
	end
end

-- Hits, bursts and balls leaving the summit.
function SnowballSummit:_collide(now: number)
	local ctx = self.context
	local changed = false
	local alive = ctx:GetAlivePlayers()

	-- Balls that rolled off (shown falling for a moment) or melted.
	for id, ball in self.balls do
		if now > ball.Edge + FALL_SHOW or now - ball.T0 > BALL_LIFE then
			self.balls[id] = nil
			changed = true
			if now - ball.T0 > BALL_LIFE and ball.Edge == math.huge then
				local spot = self:BallAt(ball, now)
				ctx:Fire(nil, "Smash", spot.X, spot.Y, spot.Z, ball.R)
			end
		end
	end

	local function live(ball: Ball, t: number): boolean
		return t >= ball.T0 and t <= ball.Edge + 0.3
	end

	-- Thrown balls meeting each other (in server time: both are on the shared schedule).
	local list = {}
	for _, ball in self.balls do
		if live(ball, now) then
			table.insert(list, ball)
		end
	end
	local gone = {}
	for i = 1, #list do
		local a = list[i]
		if gone[a.Id] then
			continue
		end
		local pa = self:BallAt(a, now)
		for j = i + 1, #list do
			local b = list[j]
			if gone[b.Id] then
				continue
			end
			local pb = self:BallAt(b, now)
			if (pa - pb).Magnitude < a.R + b.R then
				gone[a.Id], gone[b.Id] = true, true
				local mid = (pa * b.R + pb * a.R) / (a.R + b.R)
				ctx:Fire(nil, "Smash", mid.X, mid.Y, mid.Z, math.max(a.R, b.R))
				break
			end
		end
	end

	-- Each participant against the balls, as their own screen showed them.
	for _, player in alive do
		local _, _, root = ctx:GetCharacter(player)
		if not root or self.flights[player] then
			continue
		end
		local delay = seenDelay(player)
		local slack = if BotRegistry.IsBot(player) then 0 else SLACK
		local position = root.Position
		local feet = position.Y - (self.standing[player] or 3)
		local held = self.held[player]
		local heldAt = if held then self:_heldCenter(root, held.R) else nil
		for _, ball in self.balls do
			if gone[ball.Id] or ball.Owner == player then
				continue
			end
			-- A hit only if the ball overlaps them at every delay in the leeway.
			local hits, burst = 0, 0
			local seen: Vector3? = nil
			for _, d in { delay - slack, delay, delay + slack } do
				local t = now - math.max(0, d)
				if not live(ball, t) then
					continue
				end
				local at = self:BallAt(ball, t)
				seen = seen or at
				-- The ball (a sphere) against the body (an upright capsule BODY round, feet to head): a
				-- jump whose feet clear the ball's curved top, off its middle, is a dodge. (It was a
				-- cylinder, so feet that visibly cleared the ball still counted; owner: "clean up all
				-- hit boxes".)
				local cy = math.clamp(at.Y, feet + BODY, feet + BODY_H - BODY)
				local offset = Vector3.new(at.X - position.X, at.Y - cy, at.Z - position.Z)
				if offset.Magnitude < ball.R + BODY then
					hits += 1
				end
				if heldAt and (at - heldAt).Magnitude < ball.R + (held :: Held).R then
					burst += 1
				end
			end
			if burst >= 1 and seen then
				-- Blocked with their own snowball: both burst (generous, it's a save).
				gone[ball.Id] = true
				ctx:Fire(nil, "Smash", seen.X, seen.Y, seen.Z, ball.R)
				self:_dropHeld(player, true)
				heldAt = nil
			elseif hits >= 3 and seen then
				gone[ball.Id] = true
				ctx:Fire(nil, "Hit", player.UserId, seen.X, seen.Y, seen.Z, ball.R)
				self:_knock(player, ball, seen)
				break
			end
		end
	end

	for id in gone do
		if self.balls[id] then
			self.balls[id] = nil
			changed = true
		end
	end
	if changed then
		self:_publishBalls()
	end
end

-- Knocked (or walked) off the summit: out.
function SnowballSummit:_falls(now: number)
	local ctx = self.context
	local out = {}
	for _, player in ctx:GetAlivePlayers() do
		local _, _, root = ctx:GetCharacter(player)
		if not root then
			continue
		end
		local position = root.Position
		local reach = flat(position - self.center).Magnitude
		if reach <= self.radius + OUT_NEAR then
			self.outSince[player] = nil
			self.farSince[player] = nil
			continue
		end
		self.outSince[player] = self.outSince[player] or now
		if reach > self.radius + OUT_FAR then
			self.farSince[player] = self.farSince[player] or now
		else
			self.farSince[player] = nil
		end
		local dropped = position.Y < self.topY + (self.standing[player] or 3) - OUT_DROP
		local stranded = self.farSince[player] ~= nil and now - self.farSince[player] > OUT_TIME
		if dropped or stranded then
			table.insert(out, player)
		end
	end
	if #out > 0 then
		-- Everyone this step puts out goes out together (credit first), then the end rule runs once.
		for _, player in out do
			self:_dropHeld(player, false)
			self.outSince[player] = nil
			self.farSince[player] = nil
			local hit = self.lastHit[player]
			if hit and now - hit.T <= CREDIT_TIME and hit.By ~= player and ctx:State(hit.By) then
				self.kos[hit.By] = (self.kos[hit.By] or 0) + 1
				ctx:AddScore(hit.By, 1)
				local count = self.kos[hit.By]
				ctx:SetScoreText(hit.By, if count == 1 then "1 knock-off" else `{count} knock-offs`)
				ctx:Fire(nil, "KnockOff", player.UserId, hit.By.UserId)
			else
				ctx:Fire(nil, "KnockOff", player.UserId, 0)
			end
		end
		for _, player in out do
			ctx:Eliminate(player, "fell")
		end
	end
	self:_checkEnd()
end

-- Last one standing: once at most one is left (of a round that started with two or more) and nobody
-- still in is mid-fall off the rim, the round ends.
function SnowballSummit:_checkEnd()
	local ctx = self.context
	if not ctx:IsRunning() or (ctx.StartCount or 0) < 2 then
		return
	end
	local alive = ctx:GetAlivePlayers()
	if #alive > 1 then
		return
	end
	for _, player in alive do
		if self.outSince[player] then
			return -- teetering or falling: wait and see
		end
	end
	ctx:End(if #alive == 0 then "AllEliminated" else "LastSurvivor")
end

-- Survivors first, then whoever lasted longest; knock-offs break ties.
function SnowballSummit:GetResults()
	local results = self.context:SurvivalResults()
	for _, entry in results.Entries do
		local kos = self.kos[entry.Player] or 0
		entry.Rank += kos * 0.001
		if kos > 0 then
			entry.ScoreText = `{entry.ScoreText} • {kos} KO{if kos == 1 then "" else "s"}`
		end
	end
	return results
end

function SnowballSummit:Cleanup()
	for bot, flight in self.flights do
		local root = flight.Character and flight.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			release(bot, root)
		end
		self.flights[bot] = nil
	end
end

return SnowballSummit

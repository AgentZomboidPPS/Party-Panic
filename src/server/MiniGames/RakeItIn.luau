-- Rake It In (Reaction, 45s, 1-12 players). After "Rakin' 'em In" (Mario Party 2): a round table of
-- mushrooms turns slowly and everyone rakes them into their own basket; a regular one is worth 1, a
-- gold one 3 and a poison one takes 3 away. Here the table is a big round field turning around a red
-- harvest silo that keeps popping produce onto it. Everyone stands at the rim with a lane in front of
-- them: press RAKE and the rake sweeps your lane, pulling in everything in it. 🥕🍅🥦 are worth 1, a
-- golden 🎃 3, and a 💣 takes 3 away (and jams your rake for a moment). Time it so your lane is full
-- and bomb-free. The last stretch is a GOLDEN RUSH: the field turns faster and pumpkins rain down.
--
-- How it works: the field's turn is a shared schedule (MG_Spin: angle, speed and a smooth ramp to a
-- new speed), so every client spins its copy of the field and the produce on it in step with the
-- server. The produce is shared as MG_Field: each item's spot on the field (radius and angle on the
-- turning field), when it lands and, for bombs, when the fuse runs out; items that left recently are
-- listed with who raked them, so clients can fly them to the right basket. A rake is judged on the
-- server against the same schedule, at the moment the player pressed (with leeway for their ping).
-- Bots rake through ctx:BotAction exactly like players, so nothing here is client-only.

local MiniGame = require(script.Parent.Kit.MiniGame)
local Scenery = require(script.Parent.Kit.Scenery)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local RakeItIn = MiniGame.Define("RakeItIn", { Results = "Score" })

-- The field (studs from its middle). Produce lands between R_SPAWN_IN and R_SPAWN_OUT; a lane reaches
-- from R_IN to R_OUT and is HALF wide on each side of its middle line.
local BASE_Y = 0.9 -- the field mesh's base above the ground
local SOIL_Y = 2.2 -- where produce sits, above the ground
local R_IN = 9.4
local R_OUT = 20.6
local R_SPAWN_IN = 10.6
local R_SPAWN_OUT = 18.6
local HALF = 2.6 -- half a lane's width (the rake head is 4.3 wide; a little generous)
local STAND = 23.4 -- where players stand, from the middle
local SILO_Y = 1.85 -- the silo stands on the pedestal (its footing sunk in a little), scaled 0.95
local VENT_Y = SILO_Y + 19.5 * 0.95 -- its vent cap, where produce pops out

local FLIGHT = 0.9 -- seconds from the silo to the field
local COOLDOWN = 0.8 -- between rakes
local JAM = 1.6 -- a bomb jams your rake this long
local GONE_FOR = 2.5 -- how long a raked item stays listed (so clients can fly it to the basket)
local RUSH = 0.7 -- the share of the round after which the GOLDEN RUSH starts

-- Produce kinds: index = the number shared with clients.
RakeItIn.Kinds = {
	{ Name = "VeggieCarrot", Value = 1 },
	{ Name = "VeggieTomato", Value = 1 },
	{ Name = "VeggieBroccoli", Value = 1 },
	{ Name = "GoldenPumpkin", Value = 3 },
	{ Name = "VeggieBomb", Value = -3 },
}
local PUMPKIN, BOMB = 4, 5

-- Station colors (each lane, stand and basket label; the score number is the second cue).
local COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(255, 205, 60),
	Color3.fromRGB(120, 220, 110),
	Color3.fromRGB(200, 120, 255),
	Color3.fromRGB(255, 150, 60),
	Color3.fromRGB(90, 225, 220),
	Color3.fromRGB(255, 130, 200),
	Color3.fromRGB(170, 230, 70),
	Color3.fromRGB(140, 150, 255),
	Color3.fromRGB(255, 240, 150),
	Color3.fromRGB(240, 240, 250),
}

local rng = Random.new()

export type Spin = { T: number, A: number, W0: number, W1: number, Ramp: number }
export type Item = { Id: number, Kind: number, R: number, Th: number, Land: number, Fuse: number? }
export type Station = { Player: Player, Index: number, Angle: number, Stand: Vector3, Basket: Vector3 }

-- The field's angle at server time `t` along one segment of the schedule: it turns at W0, easing to
-- W1 over Ramp seconds (clients use the same formula).
function RakeItIn.SegmentAngle(seg: Spin, t: number): number
	local dt = t - seg.T
	if dt <= 0 then
		return seg.A + seg.W0 * dt
	elseif dt < seg.Ramp then
		return seg.A + seg.W0 * dt + (seg.W1 - seg.W0) * dt * dt / (2 * seg.Ramp)
	end
	return seg.A + (seg.W0 + seg.W1) / 2 * seg.Ramp + seg.W1 * (dt - seg.Ramp)
end

function RakeItIn.SegmentSpeed(seg: Spin, t: number): number
	local dt = t - seg.T
	if dt <= 0 then
		return seg.W0
	end
	return seg.W0 + (seg.W1 - seg.W0) * math.min(dt / seg.Ramp, 1)
end

-- The field's angle at server time t.
function RakeItIn:AngleAt(t: number): number
	local seg = if self.prevSpin and t < self.spin.T then self.prevSpin else self.spin
	return RakeItIn.SegmentAngle(seg, t)
end

-- Where an item is (flat, relative to the field's middle) at time t.
function RakeItIn:ItemOffset(item: Item, t: number): Vector3
	local angle = item.Th + self:AngleAt(t)
	return Vector3.new(math.cos(angle) * item.R, 0, math.sin(angle) * item.R)
end

-- Whether an item is in a station's lane at time t (landed and inside the lane's box).
function RakeItIn:InLane(station: Station, item: Item, t: number): boolean
	if t < item.Land or (item.Fuse and t >= item.Fuse) then
		return false
	end
	local d = item.Th + self:AngleAt(t) - station.Angle
	local along = item.R * math.cos(d)
	local across = item.R * math.sin(d)
	return math.abs(across) <= HALF and along >= R_IN and along <= R_OUT
end

-- What raking a station's lane at time t would take: the items, their total value, and whether a
-- bomb is among them.
function RakeItIn:LaneHaul(station: Station, t: number): ({ Item }, number, boolean)
	local taken, value, bomb = {}, 0, false
	for _, item in self.items do
		if self:InLane(station, item, t) then
			table.insert(taken, item)
			value += RakeItIn.Kinds[item.Kind].Value
			bomb = bomb or item.Kind == BOMB
		end
	end
	return taken, value, bomb
end

-- When this player's rake can be used again (server time).
function RakeItIn:ReadyAt(player: Player): number
	return self.readyAt[player] or 0
end

function RakeItIn:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 30
	local origin = ctx.Origin.Position
	self.center = origin
	self.items = {} :: { [number]: Item }
	self.gone = {} :: { { number } }
	self.nextId = 0
	self.stations = {} :: { [Player]: Station }
	self.readyAt = {} :: { [Player]: number }
	self.scores = {} :: { [Player]: number }
	self.labels = {} :: { [Player]: TextLabel }
	self.dirty = true
	self.rush = false
	local now = ctx:Now()
	self.spin = { T = now, A = rng:NextNumber(0, math.pi * 2), W0 = 0.38, W1 = 0.38, Ramp = 1 } :: Spin
	self.prevSpin = nil :: Spin?

	Scenery.Meadow(ctx, origin, 300)
	local brown = Color3.fromRGB(92, 62, 40)
	-- A trodden dirt yard around the field, under the stands.
	Build.Part({
		Name = "Yard",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 62, 62),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(176, 146, 100),
		Material = Enum.Material.Ground,
		Parent = ctx.Arena,
	})
	-- The pedestal the field turns on (the field mesh covers its top), and the field itself; clients
	-- spin their own copy of the field.
	Build.Part({
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.9, 39.2, 39.2),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.95, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = brown,
		Material = Enum.Material.WoodPlanks,
		Parent = ctx.Arena,
	})
	MeshLibrary.Get("TurningField", {
		CFrame = CFrame.new(origin + Vector3.new(0, BASE_Y, 0)),
		Parent = ctx.Arena,
	})
	MeshLibrary.Get("HarvestSilo", {
		Scale = 0.95,
		CFrame = CFrame.new(origin + Vector3.new(0, SILO_Y, 0)),
		Parent = ctx.Arena,
	})

	-- Stations around the rim, evenly spaced; the first faces the silo's door.
	local players = ctx:GetPlayers()
	for index = #players, 2, -1 do
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local count = #players
	local spawnAt = {}
	local layout = {}
	for index, player in players do
		local angle = -math.pi / 2 + (index - 1) / math.max(count, 1) * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local side = Vector3.new(-out.Z, 0, out.X) -- to the player's right when facing the middle
		local stand = origin + out * STAND
		local basket = origin + out * (STAND + 0.6) - side * 3.6
		local color = COLORS[(index - 1) % #COLORS + 1]
		local station: Station = { Player = player, Index = index, Angle = angle, Stand = stand, Basket = basket }
		self.stations[player] = station
		self.scores[player] = 0

		Build.Part({
			Name = "Stand",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 4.6, 4.6),
			CFrame = CFrame.new(stand + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Parent = ctx.Arena,
		})
		local basketModel = MeshLibrary.Get("BushelBasket", {
			CFrame = CFrame.lookAt(basket + Vector3.new(0, 0.2, 0), origin + Vector3.new(0, 0.2, 0)),
			Parent = ctx.Arena,
		})
		if basketModel.PrimaryPart then
			local label = Build.Billboard(basketModel.PrimaryPart, "0", {
				Name = "Score",
				Size = UDim2.fromOffset(110, 56),
				StudsOffset = Vector3.new(0, 3.6, 0),
				MaxDistance = 140,
				TextColor3 = color,
			})
			self.labels[player] = label
		end
		-- The lane on the field in front of the stand: a tinted strip with white edges.
		local mid = origin + out * ((R_IN + R_OUT) / 2) + Vector3.new(0, SOIL_Y + 0.28, 0)
		local laneFrame = CFrame.lookAt(mid, mid + out)
		Build.Decor({
			Name = "Lane_" .. player.UserId,
			Size = Vector3.new(HALF * 2, 0.06, R_OUT - R_IN),
			CFrame = laneFrame,
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.72,
			CastShadow = false,
			Parent = ctx.Arena,
		})
		for _, edge in { -1, 1 } do
			Build.Decor({
				Name = "LaneEdge",
				Size = Vector3.new(0.22, 0.08, R_OUT - R_IN),
				CFrame = laneFrame * CFrame.new(edge * HALF, 0.02, 0),
				Color = Color3.new(1, 1, 1),
				Material = Enum.Material.SmoothPlastic,
				Transparency = 0.25,
				CastShadow = false,
				Parent = ctx.Arena,
			})
		end
		spawnAt[player] = CFrame.lookAt(stand + Vector3.new(0, 0.6, 0), origin + Vector3.new(0, 0.6, 0))
		table.insert(layout, {
			User = player.UserId,
			Angle = angle,
			Stand = { stand.X, stand.Y, stand.Z },
			Basket = { basket.X, basket.Y, basket.Z },
			Color = { math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255) },
		})
		ctx:SetScoreText(player, "0 pts")
		ctx:SetPlayerShared(player, "Score", 0)
	end
	local ordered = {}
	for _, player in ctx:GetPlayers() do
		table.insert(ordered, spawnAt[player])
	end
	ctx:SpawnAll(ordered, true)
	ctx.Hooks.Respawn = function(player)
		local station = self.stations[player]
		return if station
			then CFrame.lookAt(station.Stand + Vector3.new(0, 3, 0), origin + Vector3.new(0, 3, 0))
			else CFrame.new(origin + Vector3.new(0, 3, STAND))
	end

	for _, kind in RakeItIn.Kinds do
		ctx:ShareTemplate(kind.Name, MeshLibrary.Get(kind.Name))
	end
	ctx:ShareTemplate("GardenRake", MeshLibrary.Get("GardenRake"))

	local values = {}
	for _, kind in RakeItIn.Kinds do
		table.insert(values, kind.Value)
	end
	ctx:SetSharedJSON("Layout", {
		Center = { origin.X, origin.Y, origin.Z },
		BaseY = BASE_Y,
		SoilY = SOIL_Y,
		VentY = VENT_Y,
		RIn = R_IN,
		ROut = R_OUT,
		Half = HALF,
		Flight = FLIGHT,
		Cooldown = COOLDOWN,
		Jam = JAM,
		Values = values,
		Stations = layout,
	})
	self:_publishSpin()
	self:_publish()
	ctx:SetStatus("Rake veggies into your basket - skip the bombs!")
end

function RakeItIn:_publishSpin()
	local function pack(seg: Spin?)
		return if seg then { seg.T, seg.A, seg.W0, seg.W1, seg.Ramp } else nil
	end
	self.context:SetSharedJSON("Spin", { Cur = pack(self.spin), Prev = pack(self.prevSpin) })
end

function RakeItIn:_publish()
	local list = {}
	for _, item in self.items do
		table.insert(list, {
			item.Id,
			item.Kind,
			math.floor(item.R * 100 + 0.5) / 100,
			math.floor(item.Th * 10000 + 0.5) / 10000,
			item.Land,
			item.Fuse or 0,
		})
	end
	self.context:SetSharedJSON("Field", { Items = list, Gone = self.gone })
	self.dirty = false
end

-- Turns the field toward a new speed, starting a moment from now so every client has the change
-- before it begins.
function RakeItIn:_changeSpin(speed: number)
	local start = self.context:Now() + 0.4
	local current = self.spin
	self.prevSpin = current
	self.spin = {
		T = start,
		A = RakeItIn.SegmentAngle(current, start),
		W0 = RakeItIn.SegmentSpeed(current, start),
		W1 = speed,
		Ramp = 1.4,
	}
	self:_publishSpin()
end

function RakeItIn:_pickKind(): number
	local roll = rng:NextNumber()
	local pumpkin = if self.rush then 0.16 else 0.07
	local bomb = if self.rush then 0.16 else 0.19
	if roll < pumpkin then
		return PUMPKIN
	elseif roll < pumpkin + bomb then
		return BOMB
	end
	return rng:NextInteger(1, 3)
end

-- Pops one item out of the silo onto a free spot of the field.
function RakeItIn:_spawn()
	local ctx = self.context
	local now = ctx:Now()
	local land = now + FLIGHT
	local r, th
	for _ = 1, 10 do
		r = rng:NextNumber(R_SPAWN_IN, R_SPAWN_OUT)
		th = rng:NextNumber(0, math.pi * 2)
		local spot = Vector3.new(math.cos(th) * r, 0, math.sin(th) * r)
		local clear = true
		for _, other in self.items do
			local there = Vector3.new(math.cos(other.Th) * other.R, 0, math.sin(other.Th) * other.R)
			if (there - spot).Magnitude < 2.8 then
				clear = false
				break
			end
		end
		if clear then
			break
		end
	end
	self.nextId += 1
	local kind = self:_pickKind()
	local item: Item = {
		Id = self.nextId,
		Kind = kind,
		R = r,
		Th = th,
		Land = land,
		Fuse = if kind == BOMB then land + rng:NextNumber(8, 12) else nil,
	}
	self.items[item.Id] = item
	self.dirty = true
end

function RakeItIn:_remove(item: Item, by: number)
	self.items[item.Id] = nil
	table.insert(self.gone, { item.Id, by, self.context:Now() })
	self.dirty = true
end

function RakeItIn:_setScore(player: Player, score: number)
	local ctx = self.context
	local old = self.scores[player] or 0
	self.scores[player] = score
	ctx:AddScore(player, score - old)
	ctx:SetScoreText(player, `{score} pts`)
	ctx:SetPlayerShared(player, "Score", score)
	local label = self.labels[player]
	if label then
		label.Text = tostring(score)
	end
end

-- A rake: everything in the player's lane at time t goes to their basket.
function RakeItIn:_rake(player: Player, t: number)
	local ctx = self.context
	local station = self.stations[player]
	if not station then
		return
	end
	local now = ctx:Now()
	local taken, value, bomb = self:LaneHaul(station, t)
	for _, item in taken do
		self:_remove(item, player.UserId)
	end
	local score = math.max(0, (self.scores[player] or 0) + value)
	self:_setScore(player, score)
	self.readyAt[player] = now + (if bomb then JAM else COOLDOWN)
	local ids = {}
	for _, item in taken do
		table.insert(ids, item.Id)
	end
	ctx:Fire(nil, "Rake", player.UserId, t, value, bomb, ids)
	if bomb then
		ctx:SetPlayerShared(player, "Jammed", now + JAM)
	end
end

function RakeItIn:Start()
	local ctx = self.context
	-- Everyone stays at their stand (jumping still works).
	for _, player in ctx:GetAlivePlayers() do
		ctx:SetWalkSpeed(player, 0)
	end
	ctx.Hooks.CharacterReady = function(player)
		ctx:SetWalkSpeed(player, 0)
	end

	ctx:OnAction("Rake", function(player, claimed)
		local station = self.stations[player]
		if not station then
			return
		end
		local now = ctx:Now()
		if now < self:ReadyAt(player) - 0.05 then
			return
		end
		local _, _, root = ctx:GetCharacter(player)
		if not root then
			return
		end
		local flat = Vector3.new(root.Position.X - station.Stand.X, 0, root.Position.Z - station.Stand.Z)
		if flat.Magnitude > 9 then
			return -- not at their stand
		end
		-- Judge the rake when the player pressed it, allowing for their ping.
		local ok, ping = pcall(function()
			return (player :: any):GetNetworkPing()
		end)
		local lag = if ok and type(ping) == "number" then math.clamp(ping, 0, 0.35) else 0.15
		local t = now - lag / 2
		if type(claimed) == "number" and claimed == claimed then
			t = math.clamp(claimed, now - lag - 0.12, now)
		end
		self:_rake(player, t)
	end, { Interval = 0.3 })

	-- The silo keeps the field stocked (more players, more produce).
	ctx:Loop(function(): number?
		local players = #ctx:GetPlayers()
		local target = math.clamp(12 + math.floor(players * 1.4), 13, 28)
		local count = 0
		for _ in self.items do
			count += 1
		end
		if count < target then
			self:_spawn()
		end
		local gap = if self.rush then 0.22 else 0.34
		return gap * rng:NextNumber(0.7, 1.3) * (if count < target * 0.6 then 0.6 else 1)
	end)

	-- Bombs nobody raked go off by themselves; the list of recently raked items is trimmed; the
	-- field is shared when it changed.
	ctx:Loop(function(): number?
		local now = ctx:Now()
		for _, item in self.items do
			if item.Fuse and now >= item.Fuse then
				self:_remove(item, 0)
			end
		end
		local keep = {}
		for _, entry in self.gone do
			if now - entry[3] < GONE_FOR then
				table.insert(keep, entry)
			end
		end
		if #keep ~= #self.gone then
			self.gone = keep
			self.dirty = true
		end
		if self.dirty then
			self:_publish()
		end
		return 0.1
	end)

	-- The field changes speed (and now and then direction) every few seconds; the last stretch is
	-- the GOLDEN RUSH.
	ctx:Delay(rng:NextNumber(4, 6), function()
		ctx:Loop(function(): number?
			if not self.rush and ctx:Progress() >= RUSH then
				self.rush = true
				ctx:Announce("🎃 GOLDEN RUSH! 🎃", "warning", 2.5)
				ctx:Sound("HazardWarning")
				ctx:SetShared("Rush", true)
			end
			local current = RakeItIn.SegmentSpeed(self.spin, ctx:Now())
			local direction = if current >= 0 then 1 else -1
			if rng:NextNumber() < 0.3 then
				direction = -direction
			end
			local speed = if self.rush then rng:NextNumber(0.45, 0.62) else rng:NextNumber(0.28, 0.5)
			self:_changeSpin(direction * speed)
			return rng:NextNumber(5, 8)
		end)
	end)
end

return RakeItIn

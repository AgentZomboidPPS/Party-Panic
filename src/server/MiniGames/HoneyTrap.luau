-- Honey Trap (Luck, 150s, 2-12 players). Mechanics after "Honeycomb Havoc": everyone stands in an
-- arc before a giant tree with a vine of fruit and honeycombs hanging from it. On your turn a block
-- over your head flips between 1 and 2: hit it (button or jump) to take that many from the bottom
-- of the vine. Fruit goes in your basket; a honeycomb brings out the bees and you're out. Taking 2
-- stops at a honeycomb, so the fruit behind it stays for the next player. Last one standing wins;
-- fruit breaks ties when time runs out.
--
-- The vine (MG_Vine) and the turn (MG_Turn) are shared state, and the block's flips follow the
-- turn's clock, so every client shows the same face at the same moment. The server judges a hit
-- against that clock with leeway for lag, so the face you saw is the face you get.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MiniGame = require(script.Parent.Kit.MiniGame)
local Scenery = require(script.Parent.Kit.Scenery)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local HoneyTrap = MiniGame.Define("HoneyTrap")

local ARC_RADIUS = 19 -- how far the players stand from the vine
local BOTTOM = 6.5 -- height of the lowest item on the vine
local SPACING = 2.6 -- between items on the vine
local TURN_TIME = 6 -- seconds to hit before the block stops by itself
local FLIP = 0.42 -- seconds each face shows
local PAUSE_FRUIT = 1.4 -- after a turn that took only fruit
local PAUSE_HONEY = 3.2 -- after a honeycomb (the bees need a moment)

-- Fruit kinds on the vine (the vine string uses their index; "H" is a honeycomb).
HoneyTrap.Fruits = {
	{ Name = "Apple", Color = Color3.fromRGB(235, 60, 60) },
	{ Name = "Orange", Color = Color3.fromRGB(255, 150, 40) },
	{ Name = "Lemon", Color = Color3.fromRGB(255, 225, 70) },
	{ Name = "Lime", Color = Color3.fromRGB(120, 210, 70) },
	{ Name = "Plum", Color = Color3.fromRGB(150, 80, 200) },
}

local knockbackRemote = Remotes.Get("Knockback")
local rng = Random.new()

type Turn = {
	Id: number,
	Player: Player,
	T0: number,
	Deadline: number,
	First: number,
	Done: boolean,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- A stretch of vine: runs of fruit, each ended by a honeycomb (now and then two in a row).
local function growVine(count: number, players: number): string
	local items = {}
	local longest = if players > 6 then 4 else 5
	while #items < count do
		local run = if rng:NextNumber() < 0.12 then 0 else rng:NextInteger(1, longest)
		for _ = 1, run do
			table.insert(items, tostring(rng:NextInteger(1, #HoneyTrap.Fruits)))
		end
		table.insert(items, "H")
	end
	return table.concat(items)
end

-- The block's face at server time `t` (it flips every FLIP seconds from T0).
function HoneyTrap.FaceAt(turn: { T0: number, First: number }, t: number): number
	if t <= turn.T0 then
		return turn.First
	end
	local flips = math.floor((t - turn.T0) / FLIP)
	return ((turn.First - 1 + flips) % 2) + 1
end

function HoneyTrap:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	ctx.KillY = ctx.Origin.Y - 30
	local origin = ctx.Origin.Position
	self.vine = growVine(60, #ctx:GetPlayers())
	self.next = 1 -- index of the lowest item still on the vine
	self.fruit = {} :: { [Player]: number }
	self.pads = {} :: { [Player]: number }
	self.order = {} :: { Player }
	self.turnId = 0
	self.current = nil :: Turn?

	-- A sunny meadow with a forest around it.
	Scenery.Meadow(ctx, origin, 300)
	Build.Part({
		Name = "Clearing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 64, 64),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.1, 2)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = rgb(196, 170, 120),
		Material = Enum.Material.Ground,
		CanCollide = false,
		Parent = ctx.Arena,
	})

	-- The tree, turned to face the players, with its branch tip right above the vine spot.
	local tree = MeshLibrary.Get("HoneyTree", {
		CFrame = CFrame.new(origin) * CFrame.Angles(0, math.pi, 0),
		Parent = ctx.Arena,
	})
	local anchor = tree:FindFirstChild("Anchor", true) :: BasePart?
	if anchor then
		tree:PivotTo(tree:GetPivot() + Vector3.new(origin.X - anchor.Position.X, 0, origin.Z - anchor.Position.Z))
		anchor.Transparency = 1
	end
	local anchorPosition = if anchor then anchor.Position else origin + Vector3.new(0, 29.6, 0)

	-- Pads in an arc facing the vine, each with a basket for its fruit.
	local players = ctx:GetPlayers()
	for index = #players, 2, -1 do
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local count = #players
	local span = math.rad(math.clamp((count - 1) * 15, 30, 160))
	local spawns = {}
	local layoutPads = {}
	for index, player in players do
		local angle = if count == 1 then 0 else -span / 2 + span * (index - 1) / (count - 1)
		local flat = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local position = origin + flat * ARC_RADIUS
		local facing = CFrame.lookAt(position, origin)
		Build.Part({
			Name = "Pad" .. index,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 4.6, 4.6),
			CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = rgb(255, 245, 225),
			Parent = ctx.Arena,
		})
		Build.Decor({
			Name = "PadRim",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 5.4, 5.4),
			CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = rgb(255, 200, 60),
			Parent = ctx.Arena,
		})
		local basketSpot = position - flat * 3.3
		MeshLibrary.Get("Basket", {
			CFrame = CFrame.new(basketSpot + Vector3.new(0, 0.2, 0)),
			Parent = ctx.Arena,
		})
		self.pads[player] = index
		table.insert(self.order, player)
		table.insert(spawns, facing + Vector3.new(0, 0.6, 0))
		table.insert(layoutPads, {
			User = player.UserId,
			Pos = { position.X, position.Y + 0.6, position.Z },
			Basket = { basketSpot.X, basketSpot.Y + 0.2, basketSpot.Z },
		})
		self.fruit[player] = 0
	end
	local spawnAt = {}
	for index, player in players do
		spawnAt[player] = spawns[index]
	end
	local ordered = {}
	for _, player in ctx:GetPlayers() do
		table.insert(ordered, spawnAt[player])
	end
	ctx:SpawnAll(ordered, true)

	-- Models the client draws the vine, the block and the bees with.
	ctx:ShareTemplate("Fruit", MeshLibrary.Get("Fruit"))
	ctx:ShareTemplate("Honeycomb", MeshLibrary.Get("Honeycomb"))
	ctx:ShareTemplate("Bee", MeshLibrary.Get("Bee"))
	ctx:ShareTemplate("DiceBlock", MeshLibrary.Get("DiceBlock"))

	local fruitColors = {}
	for _, kind in HoneyTrap.Fruits do
		table.insert(fruitColors, { kind.Color.R * 255, kind.Color.G * 255, kind.Color.B * 255 })
	end
	ctx:SetSharedJSON("Layout", {
		Anchor = { anchorPosition.X, anchorPosition.Y, anchorPosition.Z },
		Bottom = origin.Y + BOTTOM,
		Spacing = SPACING,
		Pads = layoutPads,
		Fruits = fruitColors,
	})
	self:_publishVine(nil, 0, false)
	for _, player in players do
		ctx:SetScoreText(player, "0 fruit")
	end
	ctx:SetStatus("Watch the vine: count the fruit before each honeycomb!")
end

-- The part of the vine clients draw, plus what the last turn took (so they can animate it).
function HoneyTrap:_publishVine(taker: Player?, taken: number, honey: boolean)
	self.context:SetSharedJSON("Vine", {
		Start = self.next,
		Items = string.sub(self.vine, self.next, self.next + 13),
		Taker = if taker then taker.UserId else nil,
		Taken = taken,
		Honey = honey,
	})
end

-- The next alive player after `after` in pad order (or the first alive one).
function HoneyTrap:_nextPlayer(after: Player?): Player?
	local ctx = self.context
	local count = #self.order
	local start = if after then self.pads[after] or 0 else 0
	for step = 1, count do
		local player = self.order[((start + step - 1) % count) + 1]
		if player.Parent and ctx:IsAlive(player) then
			return player
		end
	end
	return nil
end

function HoneyTrap:_startTurn(after: Player?)
	local ctx = self.context
	local player = self:_nextPlayer(after)
	if not player or not ctx:IsRunning() then
		return
	end
	self.turnId += 1
	local now = ctx:Now()
	local turn: Turn = {
		Id = self.turnId,
		Player = player,
		T0 = now + 0.6,
		Deadline = now + 0.6 + TURN_TIME,
		First = rng:NextInteger(1, 2),
		Done = false,
	}
	self.current = turn
	local upNext = self:_nextPlayer(player)
	ctx:SetSharedJSON("Turn", {
		Id = turn.Id,
		User = player.UserId,
		Name = player.DisplayName,
		T0 = turn.T0,
		Deadline = turn.Deadline,
		First = turn.First,
		Flip = FLIP,
		Next = if upNext and upNext ~= player then upNext.UserId else nil,
	})
	ctx:SetStatus(`{player.DisplayName}'s turn  •  Players left: {ctx:AliveCount()}`)
end

-- Which face a hit gets: the one the player says they saw if it really showed during the last
-- moment (allowing for their ping), otherwise the face showing when the hit was sent.
function HoneyTrap:_judgeFace(player: Player, turn: Turn, claimed: any, now: number): number
	local ok, ping = pcall(function()
		return (player :: any):GetNetworkPing()
	end)
	local lag = if ok and type(ping) == "number" then math.clamp(ping, 0, 0.4) else 0.15
	if claimed == 1 or claimed == 2 then
		local from = now - lag - 0.25
		for step = 0, 4 do
			if HoneyTrap.FaceAt(turn, from + (now - from) * step / 4) == claimed then
				return claimed
			end
		end
	end
	return HoneyTrap.FaceAt(turn, now - lag / 2)
end

function HoneyTrap:_resolve(turn: Turn, face: number)
	local ctx = self.context
	if turn.Done then
		return
	end
	turn.Done = true
	local player = turn.Player
	local taken, honey, fruit = 0, false, 0
	for _ = 1, face do
		local item = string.sub(self.vine, self.next, self.next)
		self.next += 1
		taken += 1
		if item == "H" then
			honey = true
			break -- the bees come out: anything behind the honeycomb stays on the vine
		end
		fruit += 1
	end
	if #self.vine - self.next < 24 then
		self.vine ..= growVine(40, ctx:AliveCount())
	end

	ctx:SetSharedJSON("Turn", {
		Id = turn.Id,
		User = player.UserId,
		Name = player.DisplayName,
		T0 = turn.T0,
		Deadline = turn.Deadline,
		First = turn.First,
		Flip = FLIP,
		Result = face,
	})
	self:_publishVine(player, taken, honey)
	if fruit > 0 then
		self.fruit[player] = (self.fruit[player] or 0) + fruit
		ctx:AddScore(player, fruit)
		ctx:SetScoreText(player, `{self.fruit[player]} fruit`)
		ctx:SetPlayerShared(player, "Fruit", self.fruit[player])
	end

	if honey then
		ctx:SetStatus(`🐝 The bees are after {player.DisplayName}!`)
		-- The comb lands in their basket, then the swarm chases them off.
		ctx:Delay(1.1, function()
			local _, _, root = ctx:GetCharacter(player)
			if root and typeof(player) == "Instance" then
				local away = Vector3.new(root.Position.X - ctx.Origin.X, 0, root.Position.Z - ctx.Origin.Z)
				away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
				knockbackRemote:FireClient(player, away * 45 + Vector3.new(0, 50, 0), 1.2)
			end
			ctx:Delay(1.0, function()
				ctx:Eliminate(player, "bees")
			end)
		end)
	end
	ctx:Delay(if honey then PAUSE_HONEY else PAUSE_FRUIT, function()
		self:_startTurn(player)
	end)
end

function HoneyTrap:Start()
	local ctx = self.context
	-- Everyone stays on their pad; jumping still works (it hits the block on your turn).
	for _, player in ctx:GetAlivePlayers() do
		ctx:SetWalkSpeed(player, 0)
	end
	ctx.Hooks.CharacterReady = function(player)
		ctx:SetWalkSpeed(player, 0)
	end

	ctx:OnAction("Hit", function(player, claimed)
		local turn = self.current
		if not turn or turn.Done or turn.Player ~= player then
			return
		end
		local now = ctx:Now()
		if now < turn.T0 - 0.1 then
			return -- the block isn't up yet
		end
		self:_resolve(turn, self:_judgeFace(player, turn, claimed, now))
	end, { Interval = 0.25 })

	ctx:Delay(1, function()
		self:_startTurn(nil)
	end)

	-- The block stops by itself when time runs out, and a turn passes on if its player is gone.
	ctx:Loop(function(): number?
		local turn = self.current
		if turn and not turn.Done then
			if not turn.Player.Parent or not ctx:IsAlive(turn.Player) then
				turn.Done = true
				self:_startTurn(turn.Player)
			elseif ctx:Now() >= turn.Deadline then
				self:_resolve(turn, HoneyTrap.FaceAt(turn, turn.Deadline))
			end
		end
		return 0.1
	end)
end

-- Survivors first, then whoever lasted longest; fruit breaks ties.
function HoneyTrap:GetResults()
	local results = self.context:SurvivalResults()
	for _, entry in results.Entries do
		local fruit = self.fruit[entry.Player] or 0
		entry.Rank += fruit * 0.001
		entry.ScoreText = `{entry.ScoreText} • {fruit} fruit`
	end
	return results
end

return HoneyTrap

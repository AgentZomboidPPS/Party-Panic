-- Greedy Goblins (Team, 110s): grab treasure in the middle of the field and deliver it to your
-- team's chest. Carry up to 3 (carrying slows you down). Bonk an enemy carrier to make them drop
-- their loot, which anyone can then grab.
--
-- Fairness (design doc §8 design note): bases are mirrored, players respawn at their own base,
-- and you can't be bonked inside your own base, so spawn camping doesn't work.
-- Pickups are checked by distance on the server with a per-player cap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.Parent.Services.DataService)
local QuestService = require(script.Parent.Parent.Services.QuestService)
local ArenaKit = require(script.Parent.Kit.ArenaKit)
local Build = require(script.Parent.Parent.World.Build)
local Glove = require(script.Parent.Kit.Glove)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local MiniGame = require(script.Parent.Kit.MiniGame)
local Shapes = require(script.Parent.Parent.World.Shapes)

local _ = ReplicatedStorage

local GreedyGoblins = MiniGame.Define("GreedyGoblins", { Results = "Team" })

local FIELD = Vector2.new(150, 90)
local BASE_X = 64
local BASE_SIZE = Vector3.new(20, 12, 34)
local MAX_CARRY = 3
local PICKUP_RANGE = 4.5
local BASE_SPEED = 18

local TEAMS = {
	{ Name = "Red", Color = Color3.fromRGB(255, 80, 90), Side = -1, Icon = "🔴" },
	{ Name = "Blue", Color = Color3.fromRGB(80, 160, 255), Side = 1, Icon = "🔵" },
}

type Treasure = { model: Model, position: Vector3, value: number }

function GreedyGoblins:Prepare()
	local ctx = self.context
	self.treasures = {} :: { Treasure }
	self.carrying = {} :: { [Player]: number }
	self.teamOf = {} :: { [Player]: typeof(TEAMS[1]) }
	self.carryLabels = {} :: { [Player]: TextLabel }
	self.lastPickup = {} :: { [Player]: number }
	ctx.RespawnMode = "Respawn"
	ctx.WalkSpeed = BASE_SPEED
	ctx.KillY = ctx.Origin.Y - 20

	Shapes.Slab(Vector3.new(FIELD.X + 8, 6, FIELD.Y + 8), 12, {
		Name = "FieldBase",
		CFrame = ArenaKit.At(ctx, Vector3.new(0, -3.2, 0)),
		Color = Color3.fromRGB(150, 110, 80),
		Material = Enum.Material.Ground,
		Parent = ctx.Arena,
	})
	Shapes.Slab(Vector3.new(FIELD.X, 4, FIELD.Y), 10, {
		Name = "Field",
		CFrame = ArenaKit.At(ctx, Vector3.new(0, -2, 0)),
		Color = Color3.fromRGB(150, 215, 120),
		Material = Enum.Material.Grass,
		Parent = ctx.Arena,
	})
	ArenaKit.Decor(ctx, {
		Name = "MidLine",
		Size = Vector3.new(1, 0.1, FIELD.Y),
		CFrame = ArenaKit.At(ctx, Vector3.new(0, 0.05, 0)),
		Color = Color3.fromRGB(255, 255, 255),
	})
	-- Log fences keep everyone on the field (two stacked logs per side).
	for _, wall in
		{
			{ FIELD.X, Vector3.new(0, 0, FIELD.Y / 2 - 1), 0 },
			{ FIELD.X, Vector3.new(0, 0, -FIELD.Y / 2 + 1), 0 },
			{ FIELD.Y, Vector3.new(FIELD.X / 2 - 1, 0, 0), 90 },
			{ FIELD.Y, Vector3.new(-FIELD.X / 2 + 1, 0, 0), 90 },
		}
	do
		for _, height in { 1, 2.8 } do
			Shapes.Capsule(wall[1], 1.9, {
				Name = "Fence",
				CFrame = ArenaKit.At(ctx, wall[2] + Vector3.new(0, height, 0)) * CFrame.Angles(0, math.rad(wall[3]), 0),
				Color = Color3.fromRGB(150, 100, 60),
				Material = Enum.Material.Wood,
				Parent = ctx.Arena,
			})
		end
	end

	self.bases = {}
	for _, team in TEAMS do
		local baseCFrame = ArenaKit.At(ctx, Vector3.new(team.Side * BASE_X, 0, 0))
		ArenaKit.Decor(ctx, {
			Name = team.Name .. "Base",
			Size = Vector3.new(BASE_SIZE.X, 0.15, BASE_SIZE.Z),
			CFrame = baseCFrame + Vector3.new(0, 0.08, 0),
			Color = team.Color,
			Material = Enum.Material.Neon,
			Transparency = 0.35,
		})
		local chest = MeshLibrary.Get("Chest", {
			Scale = 1.4,
			CFrame = baseCFrame * CFrame.new(team.Side * 6, 0, 0) * CFrame.Angles(0, math.rad(-90 * team.Side), 0),
			Parent = ctx.Arena,
		})
		-- Team flags flank each base.
		for _, z in { -14, 14 } do
			local poleBase = baseCFrame * CFrame.new(team.Side * 7, 0, z)
			Shapes.Capsule(12, 0.6, {
				Name = "FlagPole",
				CFrame = poleBase * CFrame.new(0, 6, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(240, 240, 240),
				Parent = ctx.Arena,
			})
			ArenaKit.Decor(ctx, {
				Name = "Flag",
				Size = Vector3.new(0.3, 3.4, 5.5),
				CFrame = poleBase * CFrame.new(0, 10, -team.Side * 2.8) * CFrame.Angles(0, math.rad(90), 0),
				Color = team.Color,
			})
		end
		local banner = ArenaKit.Decor(ctx, {
			Name = "Banner",
			Size = Vector3.new(1, 1, 1),
			Transparency = 1,
			CFrame = chest:GetPivot() + Vector3.new(0, 9, 0),
		})
		Build.Billboard(
			banner,
			`{team.Icon} {string.upper(team.Name)} CHEST`,
			{ TextColor3 = team.Color, MaxDistance = 300, Size = UDim2.fromOffset(240, 50) }
		)
		self.bases[team.Name] = { cframe = baseCFrame + Vector3.new(0, 4, 0), size = BASE_SIZE }
	end

	-- Balanced teams: shuffle, then alternate.
	local players = ctx:GetPlayers()
	local rng = Random.new()
	for index = #players, 2, -1 do
		local swap = rng:NextInteger(1, index)
		players[index], players[swap] = players[swap], players[index]
	end
	for index, player in players do
		local team = TEAMS[((index - 1) % 2) + 1]
		self.teamOf[player] = team
		self.carrying[player] = 0
		ctx:SetTeam(player, team.Name)
	end
	if #players == 1 then
		ctx:SetTeam(players[1], TEAMS[1].Name) -- solo practice still shows both totals
		ctx:AddTeamScore(TEAMS[2].Name, 0)
	end

	ctx.Hooks.Respawn = function(player)
		return self:_spawnFor(player, 0)
	end
	ctx.Hooks.CharacterReady = function(player, character)
		self.carrying[player] = 0
		self:_attachCarryLabel(player, character)
		if ctx.Started then
			self:_giveGlove(player)
		end
	end

	-- Spawn each team inside its own base.
	local teamCounts = {}
	for _, player in players do
		local team = self.teamOf[player]
		teamCounts[team.Name] = (teamCounts[team.Name] or 0) + 1
		task.spawn(ctx.SpawnPlayer, ctx, player, self:_spawnFor(player, teamCounts[team.Name]), true)
	end
	task.wait(1)

	for _ = 1, 14 do
		self:_spawnTreasure(nil)
	end
	ctx:SetStatus("Deliver treasure to your chest!")
end

function GreedyGoblins:_spawnFor(player: Player, slot: number): CFrame
	local team = self.teamOf[player] or TEAMS[1]
	local z = ((slot % 6) - 2.5) * 5
	local position = (self.context.Origin * CFrame.new(team.Side * (BASE_X - 3), 0, z)).Position
	return CFrame.lookAt(position, self.context.Origin.Position)
end

function GreedyGoblins:_attachCarryLabel(player: Player, character: Model)
	local head = character:WaitForChild("Head", 5) :: BasePart?
	if not head then
		return
	end
	local label = Build.Billboard(
		head,
		"",
		{ Name = "PP_Carry", StudsOffset = Vector3.new(0, 4.5, 0), Size = UDim2.fromOffset(120, 40), MaxDistance = 150 }
	)
	self.carryLabels[player] = label
end

function GreedyGoblins:_setCarrying(player: Player, amount: number)
	self.carrying[player] = amount
	local label = self.carryLabels[player]
	if label and label.Parent then
		label.Text = if amount > 0 then `💰 x{amount}` else ""
	end
	-- Heavier pockets, slower goblin.
	self.context:SetWalkSpeed(player, BASE_SPEED - amount * 1.5)
end

function GreedyGoblins:_spawnTreasure(position: Vector3?)
	local ctx = self.context
	local spot = position
	if not spot then
		local rng = Random.new()
		spot = (ctx.Origin * CFrame.new(rng:NextNumber(-42, 42), 0, rng:NextNumber(-FIELD.Y / 2 + 6, FIELD.Y / 2 - 6))).Position
	end
	local model = MeshLibrary.Get(
		"Treasure",
		{ CFrame = CFrame.new(spot :: Vector3) * CFrame.Angles(0, math.random() * math.pi, 0), Parent = ctx.Arena }
	)
	table.insert(self.treasures, { model = model, position = spot :: Vector3, value = 1 })
end

function GreedyGoblins:_inOwnBase(player: Player, position: Vector3): boolean
	local team = self.teamOf[player]
	local base = team and self.bases[team.Name]
	return base ~= nil and ArenaKit.InBox(position, base.cframe, base.size)
end

function GreedyGoblins:_dropLoot(victim: Player)
	local amount = self.carrying[victim] or 0
	if amount <= 0 then
		return
	end
	local _, _, root = self.context:GetCharacter(victim)
	self:_setCarrying(victim, 0)
	if not root then
		return
	end
	local ground = self.context.Origin.Y
	for index = 1, amount do
		local angle = (index / amount) * math.pi * 2 + math.random()
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 6
		self:_spawnTreasure(Vector3.new(root.Position.X, ground, root.Position.Z) + offset)
	end
	self.context:Announce(`💥 {victim.DisplayName} dropped their loot!`, "info", 2)
end

function GreedyGoblins:_giveGlove(player: Player)
	local ctx = self.context
	local team = self.teamOf[player]
	Glove.Give(ctx, player, {
		Name = "Bonk Glove",
		Color = team and team.Color or Color3.new(1, 1, 1),
		Cooldown = 0.9,
		Range = 8,
		Power = function()
			return 42
		end,
		Lift = 20,
		Stun = 0.55,
		CanHit = function(attacker, victim)
			if self.teamOf[attacker] == self.teamOf[victim] then
				return false
			end
			local _, _, root = ctx:GetCharacter(victim)
			return root ~= nil and not self:_inOwnBase(victim, root.Position)
		end,
		OnHit = function(_, victim)
			self:_dropLoot(victim)
		end,
	})
end

function GreedyGoblins:Start()
	local ctx = self.context
	for _, player in ctx:GetAlivePlayers() do
		self:_giveGlove(player)
	end

	local maxTreasure = math.min(30, 12 + #ctx:GetPlayers() * 2)
	ctx:Loop(function()
		if #self.treasures < maxTreasure then
			self:_spawnTreasure(nil)
		end
		return 1.1
	end)

	ctx:Heartbeat(function()
		local now = os.clock()
		for _, player in ctx:GetAlivePlayers() do
			local _, _, root = ctx:GetCharacter(player)
			if not root then
				continue
			end
			local carrying = self.carrying[player] or 0

			-- Pickups (rate limited per player).
			if carrying < MAX_CARRY and now - (self.lastPickup[player] or 0) > 0.15 then
				for index = #self.treasures, 1, -1 do
					local treasure = self.treasures[index]
					if (treasure.position - root.Position).Magnitude < PICKUP_RANGE + 2.5 then
						treasure.model:Destroy()
						table.remove(self.treasures, index)
						self.lastPickup[player] = now
						carrying += treasure.value
						self:_setCarrying(player, carrying)
						ctx:Sound("Pickup")
						local profile = DataService.Get(player)
						if profile then
							profile.Data.Stats.ItemsCollected += 1
						end
						QuestService.Track(player, "ItemCollected", 1)
						break
					end
				end
			end

			-- Deliveries.
			if carrying > 0 and self:_inOwnBase(player, root.Position) then
				local team = self.teamOf[player]
				ctx:AddTeamScore(team.Name, carrying)
				ctx:AddScore(player, carrying)
				local profile = DataService.Get(player)
				if profile then
					profile.Data.Stats.TreasureDelivered += carrying
				end
				QuestService.Track(player, "TeamObjective", 1)
				self:_setCarrying(player, 0)
				ctx:Sound("Victory")
			end
		end

		local scores = ctx.TeamScores or {}
		ctx:SetStatus(`{TEAMS[1].Icon} Red {scores.Red or 0}   vs   {scores.Blue or 0} Blue {TEAMS[2].Icon}`)
	end)

	ctx.Hooks.PlayerLeft = function(player)
		self.carrying[player] = nil
		self.teamOf[player] = nil
	end
end

function GreedyGoblins:Stop()
	Glove.RemoveAll(self.context)
end

function GreedyGoblins:Cleanup()
	Glove.RemoveAll(self.context)
end

return GreedyGoblins

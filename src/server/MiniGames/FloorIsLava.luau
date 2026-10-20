-- Floor Is Lava (Survival, ~85s): tiles warn, then sink into lava. The safe area keeps shrinking.
-- Readability: a tile about to sink turns yellow, then orange with a "!" before it drops,
-- so players always get time to read the next safe zone (design doc §8 design note).

local ArenaKit = require(script.Parent.Kit.ArenaKit)
local Build = require(script.Parent.Parent.World.Build)
local MiniGame = require(script.Parent.Kit.MiniGame)
local Shapes = require(script.Parent.Parent.World.Shapes)

local FloorIsLava = MiniGame.Define("FloorIsLava", { Results = "Survival" })

local GRID = 8
local TILE = 11
local SPACING = 12
local MIN_TILES = 4

type Tile = { part: BasePart, color: Color3, state: string }

function FloorIsLava:Prepare()
	local ctx = self.context
	self.tiles = {} :: { Tile }
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	ctx.KillY = ctx.Origin.Y - 7

	ArenaKit.Decor(ctx, {
		Name = "Lava",
		Size = Vector3.new(GRID * SPACING + 40, 1, GRID * SPACING + 40),
		CFrame = ArenaKit.At(ctx, Vector3.new(0, -12, 0)),
		Color = Color3.fromRGB(255, 100, 20),
		Material = Enum.Material.Neon,
	})
	local glow = ArenaKit.Decor(ctx, {
		Name = "LavaGlow",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		CFrame = ArenaKit.At(ctx, Vector3.new(0, -8, 0)),
	})
	Build.Light(glow, Color3.fromRGB(255, 120, 40), 60, 2)
	-- Rising embers sell the heat without extra parts.
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/fire_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 80, 20))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	embers.Transparency = NumberSequence.new(0.2, 1)
	embers.Lifetime = NumberRange.new(2, 3.5)
	embers.Speed = NumberRange.new(4, 9)
	embers.SpreadAngle = Vector2.new(10, 10)
	embers.Rate = 25
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Shape = Enum.ParticleEmitterShape.Box
	embers.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	local emberSource = ArenaKit.Decor(ctx, {
		Name = "EmberSource",
		Size = Vector3.new(GRID * SPACING, 1, GRID * SPACING),
		Transparency = 1,
		CFrame = ArenaKit.At(ctx, Vector3.new(0, -11, 0)),
	})
	embers.Parent = emberSource
	-- Rocky rim around the lava pool.
	for _, side in { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } } do
		local alongX = side[1] == 0
		local reach = GRID * SPACING / 2 + 14
		Shapes.Capsule(GRID * SPACING + 34, 8, {
			Name = "Rim",
			CFrame = ArenaKit.At(ctx, Vector3.new(side[1] * reach, -10, side[2] * reach))
				* (if alongX then CFrame.identity else CFrame.Angles(0, math.rad(90), 0)),
			Color = Color3.fromRGB(90, 60, 70),
			Material = Enum.Material.Basalt,
			CanCollide = false,
			Parent = ctx.Arena,
		})
	end

	local offset = (GRID - 1) * SPACING / 2
	for row = 0, GRID - 1 do
		for column = 0, GRID - 1 do
			local color = if (row + column) % 2 == 0
				then Color3.fromRGB(255, 245, 230)
				else Color3.fromRGB(230, 220, 255)
			local part = Shapes.RoundedBox(Vector3.new(TILE, 2, TILE), 0.9, {
				Name = "Tile",
				CFrame = ArenaKit.At(ctx, Vector3.new(column * SPACING - offset, -1, row * SPACING - offset)),
				Color = color,
				Parent = ctx.Arena,
			})
			table.insert(self.tiles, { part = part, color = color, state = "solid" })
		end
	end

	ctx:SpawnAll(ArenaKit.SpawnRing(ctx.Origin.Position, 16, #ctx:GetPlayers()), true)
	ctx:SetStatus(`Survivors: {ctx:AliveCount()}`)
end

function FloorIsLava:_solidTiles(): { Tile }
	local list = {}
	for _, tile in self.tiles do
		if tile.state == "solid" then
			table.insert(list, tile)
		end
	end
	return list
end

function FloorIsLava:_sink(tile: Tile)
	local ctx = self.context
	tile.state = "warning"
	tile.part.Color = ArenaKit.Colors.Warning
	tile.part.Material = Enum.Material.Neon
	local mark = Build.SurfaceText(tile.part, Enum.NormalId.Top, "!", {
		PixelsPerStud = 10,
		TextColor3 = Color3.fromRGB(120, 30, 0),
		TextStrokeTransparency = 1,
	})
	mark.Visible = false

	local warnTime = ArenaKit.Lerp(2.3, 1.3, ctx:Progress())
	ctx:Delay(warnTime * 0.5, function()
		tile.part.Color = Color3.fromRGB(255, 120, 30)
		mark.Visible = true
	end)
	ctx:Delay(warnTime, function()
		tile.state = "gone"
		tile.part.CanCollide = false
		tile.part.Transparency = 0.7
		tile.part.CFrame = tile.part.CFrame - Vector3.new(0, 3, 0)
		ctx:Delay(0.6, function()
			tile.part.Transparency = 1
		end)
	end)
end

function FloorIsLava:Start()
	local ctx = self.context
	local rng = Random.new()
	ctx:Loop(function()
		local solid = self:_solidTiles()
		local keep = math.max(MIN_TILES, ctx:AliveCount())
		local count = math.min(math.floor(ArenaKit.Lerp(3, 8, ctx:Progress())), #solid - keep)
		for _ = 1, count do
			local index = rng:NextInteger(1, #solid)
			self:_sink(table.remove(solid, index) :: Tile)
		end
		return ArenaKit.Lerp(3.8, 2.3, ctx:Progress())
	end)

	ctx:Heartbeat(function()
		ctx:SetStatus(`Survivors: {ctx:AliveCount()}  •  Tiles left: {#self:_solidTiles()}`)
	end)

	ctx.Hooks.Eliminated = function(player)
		local _, _, root = ctx:GetCharacter(player)
		if root then
			ctx:Sound("Splash")
		end
	end
end

return FloorIsLava

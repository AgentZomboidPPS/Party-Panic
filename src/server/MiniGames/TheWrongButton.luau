-- The Wrong Button (Reaction, 70s): a call is announced ("Stand on ★ RED"); when the timer runs
-- out every other tile vanishes. Later calls flip to "AVOID ..." to catch autopilots.
-- Accessibility (design doc §8 design note): every tile shows a symbol and a color name, so color
-- vision is never the only cue.

local ArenaKit = require(script.Parent.Kit.ArenaKit)
local MiniGame = require(script.Parent.Kit.MiniGame)
local Shapes = require(script.Parent.Parent.World.Shapes)

local TheWrongButton = MiniGame.Define("TheWrongButton")

local GRID = 6
local TILE = 11.5
local SPACING = 12.6

local KINDS = {
	{ Name = "RED", Symbol = "★", Color = Color3.fromRGB(255, 80, 80) },
	{ Name = "BLUE", Symbol = "●", Color = Color3.fromRGB(70, 150, 255) },
	{ Name = "GREEN", Symbol = "▲", Color = Color3.fromRGB(80, 220, 110) },
	{ Name = "YELLOW", Symbol = "■", Color = Color3.fromRGB(255, 215, 60) },
	{ Name = "PURPLE", Symbol = "♥", Color = Color3.fromRGB(180, 100, 255) },
	{ Name = "ORANGE", Symbol = "◆", Color = Color3.fromRGB(255, 150, 50) },
}

type Tile = { part: BasePart, gui: SurfaceGui, symbol: TextLabel, name: TextLabel, kind: number, home: CFrame }

function TheWrongButton:Prepare()
	local ctx = self.context
	self.tiles = {} :: { Tile }
	self.calls = 0
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	ctx.KillY = ctx.Origin.Y - 14

	local offset = (GRID - 1) * SPACING / 2
	for row = 0, GRID - 1 do
		for column = 0, GRID - 1 do
			local home = ArenaKit.At(ctx, Vector3.new(column * SPACING - offset, -1.25, row * SPACING - offset))
			local part = Shapes.RoundedBox(
				Vector3.new(TILE, 2.5, TILE),
				1.1,
				{ Name = "Tile", CFrame = home, Parent = ctx.Arena }
			)
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Top
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 12
			gui.LightInfluence = 0.2
			gui.MaxDistance = 300
			gui.Parent = part
			local symbol = Instance.new("TextLabel")
			symbol.BackgroundTransparency = 1
			symbol.Size = UDim2.fromScale(1, 0.72)
			symbol.Font = Enum.Font.GothamBlack
			symbol.TextScaled = true
			symbol.TextColor3 = Color3.new(1, 1, 1)
			symbol.TextStrokeTransparency = 0.6
			symbol.Parent = gui
			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.Position = UDim2.fromScale(0, 0.7)
			name.Size = UDim2.fromScale(1, 0.24)
			name.Font = Enum.Font.FredokaOne
			name.TextScaled = true
			name.TextColor3 = Color3.new(1, 1, 1)
			name.TextStrokeTransparency = 0.5
			name.Parent = gui
			table.insert(self.tiles, { part = part, gui = gui, symbol = symbol, name = name, kind = 1, home = home })
		end
	end

	-- Big call board on two sides of the arena.
	self.boards = {
		ArenaKit.Sign(ctx, "GET READY", ArenaKit.At(ctx, Vector3.new(0, 22, -offset - 18)), Vector3.new(48, 12, 1)),
		ArenaKit.Sign(
			ctx,
			"GET READY",
			ArenaKit.At(ctx, Vector3.new(-offset - 18, 22, 0)) * CFrame.Angles(0, math.rad(90), 0),
			Vector3.new(48, 12, 1)
		),
	}
	ArenaKit.Decor(ctx, {
		Name = "PitGlow",
		Size = Vector3.new(GRID * SPACING + 20, 1, GRID * SPACING + 20),
		CFrame = ArenaKit.At(ctx, Vector3.new(0, -26, 0)),
		Color = Color3.fromRGB(60, 30, 120),
		Material = Enum.Material.Neon,
	})

	self:_shuffle()
	ctx:SpawnAll(ArenaKit.SpawnRing(ctx.Origin.Position, 14, #ctx:GetPlayers()), true)
	ctx:SetStatus("Watch the call board!")
end

-- Every kind appears equally often, scattered across the grid.
function TheWrongButton:_shuffle()
	local kinds = {}
	for index = 1, #self.tiles do
		table.insert(kinds, ((index - 1) % #KINDS) + 1)
	end
	local rng = Random.new()
	for index = #kinds, 2, -1 do
		local swap = rng:NextInteger(1, index)
		kinds[index], kinds[swap] = kinds[swap], kinds[index]
	end
	for index, tile in self.tiles do
		local kind = KINDS[kinds[index]]
		tile.kind = kinds[index]
		tile.part.Color = kind.Color
		tile.part.Transparency = 0
		tile.part.CanCollide = true
		tile.part.CFrame = tile.home
		tile.symbol.Text = kind.Symbol
		tile.name.Text = kind.Name
		tile.gui.Enabled = true
	end
end

function TheWrongButton:_setBoards(text: string, color: Color3)
	for _, board in self.boards do
		board.Text = text
		board.TextColor3 = color
	end
end

function TheWrongButton:Start()
	local ctx = self.context
	local rng = Random.new()

	ctx:Loop(function()
		self.calls += 1
		local target = rng:NextInteger(1, #KINDS)
		local kind = KINDS[target]
		local avoid = self.calls > 3 and rng:NextNumber() < 0.35
		local text = if avoid then `AVOID {kind.Symbol} {kind.Name}!` else `STAND ON {kind.Symbol} {kind.Name}`
		local window = ArenaKit.Lerp(5, 2.2, ctx:Progress())

		self:_setBoards(text, kind.Color)
		ctx:SetStatus(`{text}  •  Survivors: {ctx:AliveCount()}`)
		ctx:Announce(text, "warning", window)
		ctx:Sound("HazardWarning")

		task.wait(window)
		if not ctx:IsRunning() then
			return nil
		end

		-- Drop every unsafe tile.
		for _, tile in self.tiles do
			local safe = if avoid then tile.kind ~= target else tile.kind == target
			if not safe then
				tile.part.CanCollide = false
				tile.part.Transparency = 0.85
				tile.part.CFrame = tile.home - Vector3.new(0, 2, 0)
				tile.gui.Enabled = false
			end
		end
		self:_setBoards("👀", Color3.new(1, 1, 1))
		task.wait(2.6)
		if not ctx:IsRunning() then
			return nil
		end
		for _, player in ctx:GetAlivePlayers() do
			ctx:AddScore(player, 1)
		end
		self:_shuffle()
		self:_setBoards("NEXT CALL...", Color3.new(1, 1, 1))
		return 1.2
	end)
end

return TheWrongButton

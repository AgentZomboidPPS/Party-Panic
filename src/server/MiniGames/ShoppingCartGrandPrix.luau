-- Shopping Cart Grand Prix (Race, 90s): push a wobbly shopping cart through a course with a slalom,
-- boost pads, a ramp jump, a slippery spill zone and a risky plank shortcut.
--
-- Forgiving by design (design doc §8): falling off returns you to your last checkpoint, and
-- checkpoints are validated in order on the server, so nobody can skip to the finish.
-- The cart is a welded, massless mesh prop, so it never changes how the character moves;
-- the "unstable cart" feel comes from wobble shoves in spill zones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = require(script.Parent.Parent.Services.DataService)
local ArenaKit = require(script.Parent.Kit.ArenaKit)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local MiniGame = require(script.Parent.Kit.MiniGame)
local Shapes = require(script.Parent.Parent.World.Shapes)

local ShoppingCartGrandPrix = MiniGame.Define("ShoppingCartGrandPrix")

local BASE_SPEED = 28
local BOOST_SPEED = 46
local BOOST_TIME = 1.4

local knockbackRemote = Remotes.Get("Knockback")

type Zone = { cframe: CFrame, size: Vector3 }
type Checkpoint = Zone & { spawn: CFrame, label: string }
type Racer = { next: number, finishedAt: number?, boostUntil: number, lastSlip: number }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

function ShoppingCartGrandPrix:Prepare()
	local ctx = self.context
	self.checkpoints = {} :: { Checkpoint }
	self.boosts = {} :: { Zone }
	self.spills = {} :: { Zone }
	self.racers = {} :: { [Player]: Racer }
	self.finishOrder = 0
	ctx.RespawnMode = "Respawn"
	ctx.WalkSpeed = BASE_SPEED
	ctx.KillY = ctx.Origin.Y - 25

	local function at(x: number, y: number, z: number): CFrame
		return ctx.Origin * CFrame.new(x, y, z)
	end
	local function floor(name: string, size: Vector3, cframe: CFrame, color: Color3?): BasePart
		-- Rounded corners everywhere a track piece can be seen from above.
		return Shapes.Slab(size, math.min(4, size.X / 4, size.Z / 4), {
			Name = name,
			CFrame = cframe,
			Color = color or rgb(90, 95, 120),
			Parent = ctx.Arena,
		})
	end
	-- Classic red/white kart curb made of capsules.
	local function curb(from: Vector3, to: Vector3)
		local length = (to - from).Magnitude
		local count = math.max(1, math.floor(length / 6))
		for index = 0, count - 1 do
			local a = from:Lerp(to, index / count)
			local b = from:Lerp(to, (index + 1) / count)
			Shapes.Capsule(length / count + 0.6, 1.2, {
				Name = "Curb",
				CFrame = (ctx.Origin * CFrame.lookAt(a:Lerp(b, 0.5), b)) * CFrame.Angles(0, math.rad(90), 0),
				Color = if index % 2 == 0 then rgb(255, 70, 70) else rgb(255, 255, 255),
				Parent = ctx.Arena,
			})
		end
	end
	local function checkpoint(label: string, cframe: CFrame, size: Vector3, spawn: CFrame, color: Color3)
		table.insert(self.checkpoints, { cframe = cframe, size = size, spawn = spawn, label = label })
		-- Smooth arch gate with a banner across the top.
		local archHeight = 17
		local ground = cframe * CFrame.new(0, -size.Y / 2, 0)
		Shapes.Arch(
			size.X + 4,
			archHeight,
			2.2,
			2.2,
			ground,
			{ Name = "Gate", Color = color, CanCollide = false, Parent = ctx.Arena }
		)
		local banner = ArenaKit.Decor(ctx, {
			Name = "GateBanner",
			Size = Vector3.new(size.X * 0.6, 3, 0.6),
			CFrame = ground * CFrame.new(0, archHeight - 4.5, 0),
			Color = rgb(30, 22, 60),
		})
		Build.SurfaceText(banner, Enum.NormalId.Front, label, { PixelsPerStud = 10 })
		Build.SurfaceText(banner, Enum.NormalId.Back, label, { PixelsPerStud = 10 })
	end

	-- Segment A: start grid and slalom straight (+Z is forward).
	floor("Start", Vector3.new(44, 2, 34), at(0, -1, 14), rgb(70, 75, 100))
	floor("StraightA", Vector3.new(36, 2, 122), at(0, -1, 92))
	for _, side in { -1, 1 } do
		curb(Vector3.new(side * 18.2, 0.4, 32), Vector3.new(side * 18.2, 0.4, 152))
	end
	for index = 0, 5 do
		local x = if index % 2 == 0 then -7 else 7
		MeshLibrary.Get("Cone", { CFrame = at(x, 0, 48 + index * 15), Parent = ctx.Arena })
		MeshLibrary.Get("Cone", { CFrame = at(x + (if x < 0 then -4 else 4), 0, 48 + index * 15), Parent = ctx.Arena })
	end
	for _, z in { 62, 118 } do
		local pad = ArenaKit.Decor(ctx, {
			Name = "BoostPad",
			Size = Vector3.new(10, 0.15, 7),
			CFrame = at(0, 0.08, z),
			Color = rgb(60, 180, 255),
			Material = Enum.Material.Neon,
		})
		Build.SurfaceText(pad, Enum.NormalId.Top, "»»", { PixelsPerStud = 8, TextColor3 = rgb(255, 255, 255) })
		table.insert(self.boosts, { cframe = at(0, 2, z), size = Vector3.new(10, 5, 7) })
	end
	checkpoint("CHECKPOINT 1", at(0, 3, 150), Vector3.new(36, 8, 4), at(0, 0, 146), rgb(255, 200, 60))

	-- Ramp jump: up a wedge, across a gap, down the far side.
	-- A WedgePart is tallest at its back (+Z), so the default orientation climbs along +Z.
	Build.Wedge({
		Name = "RampUp",
		Size = Vector3.new(30, 10, 40),
		CFrame = at(0, 5, 173),
		Color = rgb(255, 150, 90),
		Parent = ctx.Arena,
	})
	floor("Upper", Vector3.new(30, 2, 34), at(0, 9, 210))
	floor("Landing", Vector3.new(34, 2, 30), at(0, 7, 248), rgb(110, 100, 150))
	checkpoint("CHECKPOINT 2", at(0, 11, 258), Vector3.new(34, 8, 4), at(0, 8, 254), rgb(120, 230, 120))
	Build.Wedge({
		Name = "RampDown",
		Size = Vector3.new(34, 8, 30),
		CFrame = at(0, 4, 278) * CFrame.Angles(0, math.pi, 0),
		Color = rgb(255, 150, 90),
		Parent = ctx.Arena,
	})
	-- Corner pad, then the course turns toward +X.
	floor("Corner", Vector3.new(44, 2, 44), at(0, -1, 314))

	-- Segment B: spill zone, then the pit with a plank shortcut or a wide detour.
	floor("StraightB1", Vector3.new(84, 2, 40), at(64, -1, 314))
	local spill = ArenaKit.Part(ctx, {
		Name = "Spill",
		Size = Vector3.new(34, 2.05, 40),
		CFrame = at(70, -1, 314),
		Color = rgb(255, 240, 150),
		Material = Enum.Material.Ice,
		CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.02, 0, 100, 1),
	})
	Build.SurfaceText(
		spill,
		Enum.NormalId.Top,
		"⚠️ SPILL",
		{ PixelsPerStud = 6, TextColor3 = rgb(140, 100, 0), TextStrokeTransparency = 1 }
	)
	table.insert(self.spills, { cframe = at(70, 3, 314), size = Vector3.new(34, 8, 40) })

	-- Pit area (x 106..140): a narrow plank straight across, or a safe detour around the far side.
	local plank = floor("Plank", Vector3.new(34, 1, 3), at(123, -0.5, 314), rgb(180, 130, 80))
	plank.Material = Enum.Material.WoodPlanks
	local sign = ArenaKit.Decor(
		ctx,
		{ Name = "ShortcutSign", Size = Vector3.new(0.5, 3, 10), CFrame = at(105, 4, 306), Color = rgb(30, 22, 60) }
	)
	Build.SurfaceText(sign, Enum.NormalId.Left, "SHORTCUT →", { PixelsPerStud = 10, TextColor3 = rgb(255, 210, 70) })
	floor("DetourIn", Vector3.new(6, 2, 26), at(103, -1, 347))
	floor("Detour", Vector3.new(46, 2, 12), at(123, -1, 354))
	floor("DetourOut", Vector3.new(6, 2, 26), at(143, -1, 347))
	floor("StraightB2", Vector3.new(46, 2, 40), at(163, -1, 314))
	checkpoint(
		"CHECKPOINT 3",
		at(150, 3, 314) * CFrame.Angles(0, math.rad(90), 0),
		Vector3.new(40, 8, 4),
		at(154, 0, 314) * CFrame.Angles(0, math.rad(-90), 0),
		rgb(80, 200, 255)
	)

	-- Finish straight.
	floor("FinishStraight", Vector3.new(50, 2, 40), at(211, -1, 314))
	for index = 0, 7 do
		ArenaKit.Decor(ctx, {
			Name = "Checker",
			Size = Vector3.new(4, 0.12, 5),
			CFrame = at(208, 0.07, 296.5 + index * 5),
			Color = if index % 2 == 0 then rgb(20, 20, 20) else rgb(250, 250, 250),
		})
	end
	checkpoint(
		"🏁 FINISH",
		at(208, 3, 314) * CFrame.Angles(0, math.rad(90), 0),
		Vector3.new(40, 8, 4),
		at(220, 0, 314) * CFrame.Angles(0, math.rad(-90), 0),
		rgb(255, 90, 170)
	)

	local players = ctx:GetPlayers()
	for _, player in players do
		self.racers[player] = { next = 1, finishedAt = nil, boostUntil = 0, lastSlip = 0 }
		ctx:SetScoreText(player, `Checkpoint 0/{#self.checkpoints - 1}`)
	end

	ctx.Hooks.CharacterReady = function(_player, character)
		self:_attachCart(character)
	end
	ctx.Hooks.Respawn = function(player)
		local racer = self.racers[player]
		if not racer or racer.next <= 1 then
			return at(0, 0, 6)
		end
		return self.checkpoints[racer.next - 1].spawn
	end

	local grid = ArenaKit.SpawnGrid(
		(ctx.Origin * CFrame.new(0, 0, 22)).Position,
		ctx.Origin.LookVector * -1,
		4,
		Vector2.new(9, 7),
		#players
	)
	ctx:SpawnAll(grid, true)
	ctx:SetStatus("Reach the 🏁 finish!")
end

function ShoppingCartGrandPrix:_attachCart(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or character:FindFirstChild("Cart") then
		return
	end
	local cart = MeshLibrary.Get("ShoppingCart")
	cart.Name = "Cart"
	local cartRoot = MeshLibrary.Assemble(cart, true)
	cart:PivotTo(root.CFrame * CFrame.new(0, -3, -3.8))
	Build.Weld(root, cartRoot)
	cart.Parent = character
end

function ShoppingCartGrandPrix:_progressText(racer: Racer): string
	local total = #self.checkpoints
	if racer.finishedAt then
		return string.format("Finished %.1fs", racer.finishedAt)
	end
	return `Checkpoint {racer.next - 1}/{total - 1}`
end

function ShoppingCartGrandPrix:Start()
	local ctx = self.context
	local total = #self.checkpoints

	ctx:Heartbeat(function()
		local now = os.clock()
		local remaining = 0
		for player, racer in self.racers do
			if racer.finishedAt or not player.Parent then
				continue
			end
			remaining += 1
			local _, humanoid, root = ctx:GetCharacter(player)
			if not root or not humanoid then
				continue
			end
			local position = root.Position

			-- Checkpoints must be crossed in order.
			local target = self.checkpoints[racer.next]
			if target and ArenaKit.InBox(position, target.cframe, target.size + Vector3.new(0, 6, 2)) then
				racer.next += 1
				if racer.next > total then
					self.finishOrder += 1
					racer.finishedAt = ctx:Elapsed()
					ctx:AddScore(player, 1)
					ctx:Announce(`🏁 {player.DisplayName} finished #{self.finishOrder}!`, "success", 3)
					ctx:Sound("Victory")
					local profile = DataService.Get(player)
					if profile then
						profile.Data.Stats.RaceFinishes += 1
					end
				else
					ctx:Sound("Pickup")
				end
				ctx:SetScoreText(player, self:_progressText(racer))
			end

			for _, boost in self.boosts do
				if ArenaKit.InBox(position, boost.cframe, boost.size) then
					racer.boostUntil = now + BOOST_TIME
				end
			end
			humanoid.WalkSpeed = if now < racer.boostUntil then BOOST_SPEED else BASE_SPEED

			-- Spill zones shove carts sideways now and then: wobbly, never deadly.
			for _, spill in self.spills do
				if now - racer.lastSlip > 0.9 and ArenaKit.InBox(position, spill.cframe, spill.size) then
					racer.lastSlip = now
					local side = root.CFrame.RightVector * (if math.random() < 0.5 then -1 else 1)
					knockbackRemote:FireClient(player, side * 26 + Vector3.new(0, 6, 0), 0)
				end
			end
		end
		if remaining == 0 then
			ctx:End("AllFinished")
		end
		ctx:SetStatus(`Finished: {self.finishOrder}/{#ctx:GetPlayers()}`)
	end)
end

-- Finishers rank by time; everyone else by checkpoints reached, then distance to the next one.
function ShoppingCartGrandPrix:GetResults()
	local ctx = self.context
	local entries = {}
	for player, racer in self.racers do
		if not player.Parent then
			continue
		end
		local rank
		if racer.finishedAt then
			rank = 1e6 - racer.finishedAt
		else
			local distance = 999
			local _, _, root = ctx:GetCharacter(player)
			local target = self.checkpoints[racer.next]
			if root and target then
				distance = (root.Position - target.cframe.Position).Magnitude
			end
			rank = racer.next * 1000 - math.min(distance, 999)
		end
		table.insert(entries, {
			Player = player,
			Rank = rank,
			ScoreText = self:_progressText(racer),
			BestScore = if racer.finishedAt then math.floor(1000 - racer.finishedAt * 10) else nil,
		})
	end
	return { Entries = entries }
end

return ShoppingCartGrandPrix

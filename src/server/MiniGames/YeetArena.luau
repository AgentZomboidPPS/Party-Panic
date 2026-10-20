-- Yeet Arena (Knockback, 90s): swing a Yeet Glove to knock rivals off a floating platform that
-- shrinks in telegraphed steps. Last players standing place highest; knockouts break ties.
-- Hits and cooldowns are validated on the server by Kit/Glove; there is no paid combat power.

local ArenaKit = require(script.Parent.Kit.ArenaKit)
local Glove = require(script.Parent.Kit.Glove)
local MiniGame = require(script.Parent.Kit.MiniGame)
local Shapes = require(script.Parent.Parent.World.Shapes)

local YeetArena = MiniGame.Define("YeetArena")

local START_DIAMETER = 84
local SHRINK_STEPS = { { at = 25, diameter = 64 }, { at = 50, diameter = 46 }, { at = 70, diameter = 32 } }
local KO_CREDIT_WINDOW = 5

function YeetArena:Prepare()
	local ctx = self.context
	self.lastHit = {} :: { [Player]: { attacker: Player, time: number } }
	self.knockouts = {} :: { [Player]: number }
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	ctx.KillY = ctx.Origin.Y - 25

	local center = ctx.Origin.Position
	self.platform = ArenaKit.Part(ctx, {
		Name = "Platform",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, START_DIAMETER, START_DIAMETER),
		CFrame = CFrame.new(center - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 230, 245),
	})
	self.edge = ArenaKit.Decor(ctx, {
		Name = "EdgeRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.6, START_DIAMETER + 2, START_DIAMETER + 2),
		CFrame = CFrame.new(center - Vector3.new(0, 2.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 90, 170),
		Material = Enum.Material.Neon,
	})
	-- Puffy cloud underside so the ring floats.
	Shapes.Custom(
		"YeetClouds",
		function(piece)
			local pieces = {}
			for index = 0, 7 do
				local angle = index / 8 * math.pi * 2
				table.insert(
					pieces,
					piece(
						Vector3.one * 26,
						CFrame.new(math.cos(angle) * 26, 0, math.sin(angle) * 26),
						Enum.PartType.Ball
					)
				)
			end
			table.insert(pieces, piece(Vector3.one * 40, CFrame.new(0, -6, 0), Enum.PartType.Ball))
			return pieces
		end,
		Vector3.new(70, 26, 70),
		{
			Name = "Clouds",
			CFrame = CFrame.new(center - Vector3.new(0, 17, 0)),
			Color = Color3.fromRGB(255, 240, 250),
			Transparency = 0.1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = ctx.Arena,
		}
	)
	-- Corner spotlights on floating orbs.
	for index = 0, 3 do
		local angle = index / 4 * math.pi * 2 + math.pi / 4
		local orbPosition = center + Vector3.new(math.cos(angle) * 58, 26, math.sin(angle) * 58)
		local orb = ArenaKit.Decor(ctx, {
			Name = "LightOrb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 3,
			CFrame = CFrame.lookAt(orbPosition, center),
			Color = Color3.fromRGB(255, 120, 200),
			Material = Enum.Material.Neon,
		})
		local light = Instance.new("SpotLight")
		light.Color = Color3.fromRGB(255, 180, 230)
		light.Brightness = 2
		light.Range = 80
		light.Angle = 45
		light.Shadows = false
		light.Parent = orb
	end
	ArenaKit.Decor(ctx, {
		Name = "CenterMark",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 10, 10),
		CFrame = CFrame.new(center + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 90, 170),
	})

	ctx:SpawnAll(ArenaKit.SpawnRing(center, START_DIAMETER / 2 - 10, #ctx:GetPlayers()), true)
	for _, player in ctx:GetPlayers() do
		self.knockouts[player] = 0
		ctx:SetScoreText(player, "0 KOs")
	end
	ctx:SetStatus(`Players left: {ctx:AliveCount()}`)
end

function YeetArena:_resize(diameter: number)
	local center = self.context.Origin.Position
	self.platform.Size = Vector3.new(4, diameter, diameter)
	self.platform.CFrame = CFrame.new(center - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	self.edge.Size = Vector3.new(3.6, diameter + 2, diameter + 2)
	self.edge.CFrame = CFrame.new(center - Vector3.new(0, 2.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	self.edge.Color = Color3.fromRGB(255, 90, 170)
end

function YeetArena:Start()
	local ctx = self.context
	local duration = ctx.Definition.Duration

	for _, player in ctx:GetAlivePlayers() do
		Glove.Give(ctx, player, {
			Name = "Yeet Glove",
			Color = Color3.fromRGB(235, 50, 70),
			Cooldown = 1.0,
			Range = 9,
			Power = function()
				-- Knockback grows as the round goes on so it always ends with a bang.
				return ArenaKit.Lerp(68, 105, ctx:Elapsed() / duration)
			end,
			Lift = 32,
			Stun = 0.8,
			OnHit = function(attacker, victim)
				self.lastHit[victim] = { attacker = attacker, time = os.clock() }
			end,
		})
	end

	ctx.Hooks.Eliminated = function(victim)
		local hit = self.lastHit[victim]
		if hit and os.clock() - hit.time <= KO_CREDIT_WINDOW and hit.attacker.Parent then
			local attacker = hit.attacker
			self.knockouts[attacker] = (self.knockouts[attacker] or 0) + 1
			ctx:AddScore(attacker, 1)
			ctx:SetScoreText(attacker, `{self.knockouts[attacker]} KOs`)
			ctx:Announce(`💥 {attacker.DisplayName} yeeted {victim.DisplayName}!`, "info", 3)
		end
	end

	for _, step in SHRINK_STEPS do
		-- Three seconds of flashing edge before each shrink.
		ctx:Delay(step.at - 3, function()
			self.edge.Color = Color3.fromRGB(255, 40, 40)
			ctx:Announce("⚠️ The platform is shrinking!", "warning", 3)
			ctx:Sound("HazardWarning")
		end)
		ctx:Delay(step.at, function()
			self:_resize(step.diameter)
		end)
	end

	ctx:Heartbeat(function()
		ctx:SetStatus(`Players left: {ctx:AliveCount()}`)
	end)
end

function YeetArena:Stop()
	Glove.RemoveAll(self.context)
end

-- Survivors first; within the same survival time, more knockouts rank higher.
function YeetArena:GetResults()
	local ctx = self.context
	local results = ctx:SurvivalResults()
	for _, entry in results.Entries do
		local knockouts = self.knockouts[entry.Player] or 0
		entry.Rank += knockouts * 0.001
		entry.ScoreText = `{entry.ScoreText} • {knockouts} KOs`
	end
	return results
end

function YeetArena:Cleanup()
	Glove.RemoveAll(self.context)
end

return YeetArena

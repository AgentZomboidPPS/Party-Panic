-- Client half of Fire Rope: draws the burning rope and spins the two sun wheels from the shared
-- schedule (MG_Rope), shows a shadow on the floor where the rope will sweep (for timing), and
-- counts your jumps.
--
-- The look (art pass; owner: "I saw the lava rope one and that one kinda sucks"): a golden-hour sky
-- over the Dragon Temple, fires in the braziers and tower bowls, steam where lava falls meet the
-- lake, and a rope that reads from anywhere: a white-hot core threaded through fireballs inside a
-- glow, licked by flames, going from gold to angry red as it speeds up. Particles stay off with
-- reduced effects.

local Lighting = game:GetService("Lighting")

local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local State = require(script.Parent.Parent.State)

local FireRope = {}

local COLD = Color3.fromRGB(255, 205, 60)
local WARM = Color3.fromRGB(255, 120, 30)
local HOT = Color3.fromRGB(255, 40, 30)
local WHITE_HOT = Color3.fromRGB(255, 250, 215)
local CLOCK_TIME = 16.9 -- golden hour: low warm sun, still bright enough on phones

local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local function heatColor(heat: number): Color3
	if heat < 0.5 then
		return COLD:Lerp(WARM, heat * 2)
	end
	return WARM:Lerp(HOT, (heat - 0.5) * 2)
end

-- The rope's angle at `now` (0 = bottom of the swing, increasing towards the players' backs).
local function angleAt(rope, now: number): number
	local segments = rope.Segments
	local current = segments and segments[1]
	if not current then
		return math.pi -- not swinging yet: resting at the top
	end
	for _, segment in segments do
		if segment.T0 <= now then
			current = segment
		end
	end
	if now < current.T0 then
		return current.A0
	end
	return current.A0 + current.W * (now - current.T0)
end

local function visualPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- Fires on the arena's FlameSpot markers and steam on its SteamSpot markers.
local function decorate(spot: Instance)
	if not spot:IsA("BasePart") then
		return
	end
	local flame = spot:GetAttribute("Flame")
	if spot.Name == "FlameSpot" and type(flame) == "number" then
		local fire = Instance.new("Fire")
		fire.Size = flame
		fire.Heat = flame * 1.4
		fire.Color = Color3.fromRGB(255, 150, 40)
		fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
		fire.Parent = spot
	end
	local steam = spot:GetAttribute("Steam")
	if spot.Name == "SteamSpot" and type(steam) == "number" then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = SMOKE_TEXTURE
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 190, 150), Color3.fromRGB(150, 120, 120))
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Size = NumberSequence.new(4 * steam, 12 * steam)
		emitter.Lifetime = NumberRange.new(3, 5)
		emitter.Speed = NumberRange.new(4, 8)
		emitter.SpreadAngle = Vector2.new(25, 25)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.RotSpeed = NumberRange.new(-20, 20)
		emitter.Rate = 2 * steam
		emitter.Parent = spot
	end
end

function FireRope.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 228, 206),
		Saturation = 0.18,
		Contrast = 0.1,
		Haze = Color3.fromRGB(255, 160, 100),
		HazeDecay = Color3.fromRGB(170, 70, 60),
		Density = 0.32,
	})
	-- Golden hour for the round, put back afterwards.
	local clockTime = Lighting.ClockTime
	Lighting.ClockTime = CLOCK_TIME
	api:Track(function()
		Lighting.ClockTime = clockTime
	end)

	local rope = api:SharedJSON("Rope")
	while not rope do
		task.wait(0.1)
		rope = api:SharedJSON("Rope")
	end
	api:OnShared("Rope", function()
		rope = api:SharedJSON("Rope") or rope
	end)
	local arena = api:Arena()
	local axis = Vector3.new(rope.Axis[1], rope.Axis[2], rope.Axis[3])
	local radius = rope.Radius
	local effects = not State.ReducedEffects()

	-- The rope: a white-hot core threaded through fireballs inside a soft glow, all in one model
	-- turned around the axis every frame.
	local model = Instance.new("Model")
	model.Name = "FireRopeVisual"
	local pivot = visualPart({ Name = "Axis", Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(axis) })
	pivot.Parent = model
	model.PrimaryPart = pivot
	local low = CFrame.new(axis + Vector3.new(0, -radius, 0))
	local core = visualPart({
		Name = "Core",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(rope.Length, 0.8, 0.8),
		Color = WHITE_HOT,
		CFrame = low,
	})
	core.Parent = model
	local halo = visualPart({
		Name = "Halo",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(rope.Length - 1, 1.8, 1.8), -- top at 1.8 at the pass: a cleared jump looks cleared
		Color = WARM, -- one step hotter than the fireballs: an orange-red outline against the cream deck
		Transparency = 0.65,
		CFrame = low,
	})
	halo.Parent = model
	local balls = {}
	local count = math.floor(rope.Length / 2.1)
	for index = 0, count do
		local x = -rope.Length / 2 + index * rope.Length / count
		local ball = visualPart({
			Name = "Fireball",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * (if index % 2 == 0 then 1.9 else 1.5), -- alternating, like a braid of flame
			Color = COLD,
			CFrame = CFrame.new(axis + Vector3.new(x, -radius, 0)),
		})
		ball.Parent = model
		table.insert(balls, ball)
		if effects and index % 3 == 0 then
			-- Streaks behind the rope as it swings.
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, 0.6, 0)
			a0.Parent = ball
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -0.6, 0)
			a1.Parent = ball
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Lifetime = 0.18
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.Color = ColorSequence.new(WARM, HOT)
			trail.Transparency = NumberSequence.new(0.2, 1)
			trail.Parent = ball
		end
	end
	-- Flames licking off the whole length of the rope (one emitter over the core's volume, locked to it).
	local flames: ParticleEmitter? = nil
	if effects then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = FIRE_TEXTURE
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.LightEmission = 1
		emitter.Color = ColorSequence.new(COLD, WARM)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.1),
			NumberSequenceKeypoint.new(0.4, 1.5),
			NumberSequenceKeypoint.new(1, 0.2),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.6, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Lifetime = NumberRange.new(0.18, 0.32)
		emitter.Speed = NumberRange.new(0.5, 2)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, 4, 0) -- turns with the rope (locked), so kept small
		emitter.RotSpeed = NumberRange.new(-180, 180)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.Rate = 160
		emitter.LockedToPart = true -- the flames ride with the rope instead of smearing behind it
		emitter.Parent = core
		flames = emitter
	end
	local light = Instance.new("PointLight")
	light.Color = WARM
	light.Range = 20
	light.Brightness = 2.2
	light.Parent = balls[math.floor(#balls / 2)]
	model.Parent = api.World

	-- The rope's shadow on the bridge: where it will sweep, darker as it comes down. Above the
	-- bridge's borders, so it shows the whole way across.
	local shadow = visualPart({
		Name = "RopeShadow",
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(50, 16, 12),
		Size = Vector3.new(rope.Length - 14, 0.05, 1.4),
	})
	shadow.Parent = api.World

	-- The sun wheels at both ends, and fires and steam on the arena's markers.
	local wheels = {}
	if arena then
		for _, name in { "WheelL", "WheelR" } do
			local wheel = arena:WaitForChild(name, 5) :: Model?
			if wheel then
				table.insert(wheels, { Model = wheel, Base = wheel:GetPivot() })
			end
		end
		if effects then
			for _, descendant in arena:GetDescendants() do
				decorate(descendant)
			end
			api:Track(arena.DescendantAdded:Connect(decorate))
		end
	end

	-- Jump counter.
	local counter = UIKit.Label({
		Name = "Jumps",
		Text = "🔥 0",
		Font = Theme.Fonts.Display,
		TextSize = 54,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY()),
		Size = UDim2.fromOffset(300, 64),
		Parent = api:TopHud(),
		Children = { UIKit.TextStroke(0.1) },
	})
	api:OnMine("Jumps", function(value)
		counter.Text = `🔥 {value or 0}`
		UIKit.PopIn(counter, 0.2)
	end)

	local lastHeat = -1
	local around = CFrame.new(axis)
	api:RenderStep(function()
		local theta = angleAt(rope, api:Now())
		local turn = CFrame.Angles(-theta, 0, 0)
		model:PivotTo(around * turn)
		-- The wheels turn about the same line (their axles are on it), whatever their pivots are.
		local spin = around * turn * around:Inverse()
		for _, wheel in wheels do
			wheel.Model:PivotTo(spin * wheel.Base)
		end
		-- Rope position in the swing plane: z ahead (negative) when coming down at the players.
		local z = radius * math.sin(theta)
		local y = -radius * math.cos(theta)
		local below = math.clamp(-y / radius, 0, 1) -- 1 at the bottom, 0 at axis height
		shadow.CFrame = CFrame.new(rope.Axis[1], rope.FloorY + 0.17, rope.Axis[3] + z)
		shadow.Transparency = 1 - below * 0.65
		if rope.Heat ~= lastHeat then
			lastHeat = rope.Heat
			local color = heatColor(rope.Heat)
			for _, ball in balls do
				ball.Color = color
			end
			halo.Color = heatColor(math.min(1, rope.Heat + 0.5))
			core.Color = WHITE_HOT:Lerp(color, 0.25)
			light.Color = color
			if flames then
				flames.Color = ColorSequence.new(WHITE_HOT:Lerp(color, 0.4), color)
				flames.Rate = 160 + 120 * rope.Heat -- angrier as it speeds up
			end
		end
	end)
end

return FireRope

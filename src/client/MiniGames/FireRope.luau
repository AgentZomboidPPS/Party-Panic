-- Client half of Fire Rope: draws the burning rope and spins the two fire wheels from the shared
-- schedule (MG_Rope), shows a shadow on the floor where the rope will sweep (for timing), and
-- counts your jumps.

local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local State = require(script.Parent.Parent.State)

local FireRope = {}

local COLD = Color3.fromRGB(255, 225, 90)
local WARM = Color3.fromRGB(255, 140, 40)
local HOT = Color3.fromRGB(255, 55, 40)

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

function FireRope.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 232, 214),
		Saturation = 0.12,
		Contrast = 0.08,
		Haze = Color3.fromRGB(255, 170, 120),
		HazeDecay = Color3.fromRGB(150, 70, 50),
		Density = 0.3,
	})
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

	-- The rope: a line of fireballs in one model, turned around the axis every frame.
	local model = Instance.new("Model")
	model.Name = "FireRopeVisual"
	local pivot = Instance.new("Part")
	pivot.Name = "Axis"
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.CanQuery = false
	pivot.CanTouch = false
	pivot.Transparency = 1
	pivot.Size = Vector3.one
	pivot.CFrame = CFrame.new(axis)
	pivot.Parent = model
	model.PrimaryPart = pivot
	local balls = {}
	local count = math.floor(rope.Length / 2.1)
	local effects = not State.ReducedEffects()
	for index = 0, count do
		local x = -rope.Length / 2 + index * rope.Length / count
		local ball = Instance.new("Part")
		ball.Name = "Fireball"
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * 1.8
		ball.Material = Enum.Material.Neon
		ball.Color = COLD
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.CanTouch = false
		ball.CastShadow = false
		ball.CFrame = CFrame.new(axis + Vector3.new(x, -radius, 0))
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
	local light = Instance.new("PointLight")
	light.Color = WARM
	light.Range = 18
	light.Brightness = 2
	light.Parent = balls[math.floor(#balls / 2)]
	model.Parent = api.World

	-- The rope's shadow on the bridge: where it will sweep, darker as it comes down.
	local shadow = Instance.new("Part")
	shadow.Name = "RopeShadow"
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	shadow.CastShadow = false
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Color = Color3.fromRGB(40, 20, 20)
	shadow.Size = Vector3.new(rope.Length - 14, 0.05, 1.4)
	shadow.Parent = api.World

	-- The fire wheels at both ends.
	local wheels = {}
	if arena then
		for _, name in { "WheelL", "WheelR" } do
			local wheel = arena:WaitForChild(name, 5) :: Model?
			if wheel then
				table.insert(wheels, { Model = wheel, Base = wheel:GetPivot() })
			end
		end
	end

	-- Jump counter.
	local counter = UIKit.Label({
		Name = "Jumps",
		Text = "🔥 0",
		Font = Theme.Fonts.Display,
		TextSize = 54,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.fromOffset(300, 64),
		Parent = api.Gui,
		Children = { UIKit.TextStroke(0.1) },
	})
	UIKit.AutoScale(counter)
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
		shadow.CFrame = CFrame.new(rope.Axis[1], rope.FloorY + 0.04, rope.Axis[3] + z)
		shadow.Transparency = 1 - below * 0.65
		if rope.Heat ~= lastHeat then
			lastHeat = rope.Heat
			local color = heatColor(rope.Heat)
			for _, ball in balls do
				ball.Color = color
			end
			light.Color = color
		end
	end)
end

return FireRope

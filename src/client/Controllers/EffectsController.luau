-- Renders celebratory and feedback effects locally. The server only says what and where, so each
-- player's "reduced effects" setting is respected (design doc §12 accessibility).
-- The Rewards Road and career rewards add balloons, ghosts, music notes, crowns, trophies and a
-- grand finale (owner: "Also we need cool payoffs for players that keep playing the game.").
-- The second shop pass adds thumbs up, snow, flowers, rainbows, streamers, a spotlight, a
-- supernova, paint splats, rubber ducks and a zap (owner: "Yes lets add more items after everything
-- else is finished"). Each one is over in about two seconds and stays small, so a knockout effect
-- never hides the game around it; with reduced effects there are fewer pieces and no flashes.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.Parent.State)

local EffectsController = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local PARTY = {
	Color3.fromRGB(255, 90, 140),
	Color3.fromRGB(90, 190, 255),
	Color3.fromRGB(255, 210, 70),
	Color3.fromRGB(150, 110, 255),
	Color3.fromRGB(110, 230, 140),
}

local folder: Folder

local function anchor(position: Vector3, lifetime: number): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = CFrame.new(position)
	part.Parent = folder
	Debris:AddItem(part, lifetime)
	return part
end

local function burst(parent: Part, props: { [string]: any }, count: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = parent
	emitter:Emit(count)
end

-- Emoji that float up and fade (hearts, stars, bubbles). Several emoji take turns.
local function emojiBurst(position: Vector3, emoji: string | { string }, count: number)
	local holder = anchor(position, 2.5)
	local choices = if type(emoji) == "table" then emoji else { emoji }
	for index = 1, count do
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(46, 46)
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.MaxDistance = 120
		gui.StudsOffset = Vector3.new(math.random() * 4 - 2, math.random() * 1.5, math.random() * 4 - 2)
		gui.Adornee = holder
		gui.Parent = holder
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Text = choices[(index - 1) % #choices + 1]
		label.Parent = gui
		local rise = Vector3.new(0, 4 + math.random() * 3, 0)
		TweenService:Create(
			gui,
			TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ StudsOffset = gui.StudsOffset + rise }
		):Play()
		TweenService
			:Create(label, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
			:Play()
	end
end

-- A glowing see-through shape (the spotlight's beam, the supernova's ring) that fades out.
local function glow(cframe: CFrame, size: Vector3, color: Color3, shape: Enum.PartType, lifetime: number): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = shape
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.55
	part.Size = size
	part.CFrame = cframe
	part.Parent = folder
	Debris:AddItem(part, lifetime + 0.1)
	TweenService:Create(part, TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Transparency = 1,
	}):Play()
	return part
end

local function flash(holder: Part, color: Color3, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 4
	light.Parent = holder
	TweenService:Create(light, TweenInfo.new(0.35), { Brightness = 0 }):Play()
end

local EFFECTS: { [string]: (position: Vector3, colors: { Color3 }?, scale: number) -> () } = {
	Confetti = function(position, colors, scale)
		local holder = anchor(position, 4)
		for _, color in colors or PARTY do
			burst(holder, {
				Texture = SPARKLE,
				Color = ColorSequence.new(color),
				LightEmission = 0.4,
				Size = NumberSequence.new(0.7, 0.4),
				Lifetime = NumberRange.new(1.8, 2.8),
				Speed = NumberRange.new(14, 26),
				SpreadAngle = Vector2.new(55, 55),
				Acceleration = Vector3.new(0, -30, 0),
				Drag = 1.5,
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-300, 300),
				EmissionDirection = Enum.NormalId.Top,
			}, math.floor(10 * scale))
		end
	end,
	Fireworks = function(position, colors, scale)
		local palette = colors or PARTY
		for index = 1, 3 do
			task.delay((index - 1) * 0.25, function()
				local offset = Vector3.new(math.random(-8, 8), math.random(6, 14), math.random(-8, 8))
				local holder = anchor(position + offset, 3)
				local color = palette[math.random(1, #palette)]
				burst(holder, {
					Texture = SPARKLE,
					Color = ColorSequence.new(color),
					LightEmission = 1,
					Size = NumberSequence.new(1.1, 0),
					Lifetime = NumberRange.new(1, 1.6),
					Speed = NumberRange.new(18, 26),
					SpreadAngle = Vector2.new(180, 180),
					Acceleration = Vector3.new(0, -12, 0),
					Drag = 2,
				}, math.floor(40 * scale))
				local light = Instance.new("PointLight")
				light.Color = color
				light.Range = 30
				light.Brightness = 4
				light.Parent = holder
				TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
			end)
		end
	end,
	Sparkles = function(position, colors, scale)
		local holder = anchor(position, 3)
		burst(holder, {
			Texture = SPARKLE,
			Color = ColorSequence.new((colors and colors[1]) or Color3.fromRGB(255, 225, 120)),
			LightEmission = 1,
			Size = NumberSequence.new(0.9, 0),
			Lifetime = NumberRange.new(0.8, 1.6),
			Speed = NumberRange.new(4, 10),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 1,
		}, math.floor(30 * scale))
	end,
	Poof = function(position, _colors, scale)
		local holder = anchor(position, 3)
		burst(holder, {
			Texture = SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) }),
			Transparency = NumberSequence.new(0.2, 1),
			Lifetime = NumberRange.new(0.8, 1.2),
			Speed = NumberRange.new(6, 10),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 4,
		}, math.floor(18 * scale))
	end,
	Hearts = function(position, _colors, scale)
		emojiBurst(position, "💖", math.max(2, math.floor(7 * scale)))
	end,
	Stars = function(position, _colors, scale)
		emojiBurst(position, "⭐", math.max(2, math.floor(6 * scale)))
	end,
	Bubbles = function(position, _colors, scale)
		emojiBurst(position, "🔵", math.max(2, math.floor(7 * scale))) -- 🫧 is blank on phones
	end,
	Balloons = function(position, _colors, scale)
		emojiBurst(position, "🎈", math.max(3, math.floor(9 * scale)))
	end,
	Ghosts = function(position, _colors, scale)
		emojiBurst(position, "👻", math.max(2, math.floor(5 * scale)))
	end,
	Notes = function(position, _colors, scale)
		emojiBurst(position, { "🎵", "🎶" }, math.max(2, math.floor(8 * scale)))
	end,
	Crowns = function(position, _colors, scale)
		emojiBurst(position, "👑", math.max(2, math.floor(7 * scale)))
	end,
	Trophies = function(position, _colors, scale)
		emojiBurst(position, { "🏆", "🥇" }, math.max(2, math.floor(7 * scale)))
	end,
	Thumbs = function(position, _colors, scale)
		emojiBurst(position, "👍", math.max(2, math.floor(6 * scale)))
	end,
	Snow = function(position, _colors, scale)
		emojiBurst(position, "❄️", math.max(2, math.floor(7 * scale)))
		local holder = anchor(position + Vector3.new(0, 3, 0), 3)
		burst(holder, {
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.fromRGB(235, 250, 255)),
			LightEmission = 0.3,
			Size = NumberSequence.new(0.35, 0.2),
			Lifetime = NumberRange.new(1.2, 1.8),
			Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -6, 0),
			Drag = 1,
		}, math.floor(20 * scale))
	end,
	Flowers = function(position, _colors, scale)
		emojiBurst(position, { "🌸", "🌼" }, math.max(2, math.floor(8 * scale)))
	end,
	Rainbows = function(position, _colors, scale)
		emojiBurst(position, "🌈", math.max(2, math.floor(5 * scale)))
	end,
	Ducks = function(position, _colors, scale)
		emojiBurst(position, "🦆", math.max(2, math.floor(5 * scale)))
	end,
	-- Long ribbons of color that shoot up and flutter down.
	Streamers = function(position, colors, scale)
		local holder = anchor(position, 4)
		for _, color in colors or PARTY do
			burst(holder, {
				Texture = SPARKLE,
				Color = ColorSequence.new(color),
				LightEmission = 0.3,
				Orientation = Enum.ParticleOrientation.VelocityParallel,
				Squash = NumberSequence.new(-1.5),
				Size = NumberSequence.new(0.6, 0.35),
				Lifetime = NumberRange.new(1.4, 2.2),
				Speed = NumberRange.new(20, 30),
				SpreadAngle = Vector2.new(30, 30),
				Acceleration = Vector3.new(0, -26, 0),
				Drag = 1.2,
				EmissionDirection = Enum.NormalId.Top,
			}, math.floor(8 * scale))
		end
	end,
	-- A quick splash of paint drops that falls back to the ground.
	Splat = function(position, colors, scale)
		local holder = anchor(position, 2)
		local palette = colors
			or { Color3.fromRGB(255, 80, 120), Color3.fromRGB(80, 200, 255), Color3.fromRGB(255, 220, 60) }
		for _, color in palette do
			burst(holder, {
				Texture = SPARKLE,
				Color = ColorSequence.new(color),
				Size = NumberSequence.new(0.9, 0.3),
				Lifetime = NumberRange.new(0.4, 0.7),
				Speed = NumberRange.new(12, 18),
				SpreadAngle = Vector2.new(70, 70),
				Acceleration = Vector3.new(0, -45, 0),
				EmissionDirection = Enum.NormalId.Top,
			}, math.floor(10 * scale))
		end
	end,
	-- A short electric crackle: fast blue-white sparks, two bolts and a blink of light.
	Zap = function(position, _colors, scale)
		local holder = anchor(position, 2)
		burst(holder, {
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.fromRGB(190, 240, 255), Color3.fromRGB(255, 250, 150)),
			LightEmission = 1,
			Size = NumberSequence.new(0.8, 0),
			Lifetime = NumberRange.new(0.2, 0.4),
			Speed = NumberRange.new(20, 30),
			SpreadAngle = Vector2.new(180, 180),
		}, math.floor(24 * scale))
		emojiBurst(position, "⚡", 2)
		if scale >= 1 then
			flash(holder, Color3.fromRGB(150, 220, 255), 18)
		end
	end,
	-- A see-through beam of light from above, with gold sparkles at the bottom.
	Spotlight = function(position, colors, scale)
		local color = (colors and colors[1]) or Color3.fromRGB(255, 245, 200)
		local height = 36
		glow(
			CFrame.new(position + Vector3.new(0, height / 2 - 3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(height, 7, 7),
			color,
			Enum.PartType.Cylinder,
			2
		)
		local holder = anchor(position, 3)
		burst(holder, {
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.fromRGB(255, 225, 120)),
			LightEmission = 1,
			Size = NumberSequence.new(0.8, 0),
			Lifetime = NumberRange.new(1, 1.6),
			Speed = NumberRange.new(2, 6),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, 4, 0),
		}, math.floor(30 * scale))
	end,
}
-- A flat ring of light that spreads out and fades, then stars and purple fireworks.
EFFECTS.Supernova = function(position, colors, scale)
	local palette = colors
		or { Color3.fromRGB(200, 140, 255), Color3.fromRGB(120, 200, 255), Color3.fromRGB(255, 255, 255) }
	if scale >= 1 then
		local ring = glow(
			CFrame.new(position - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(0.3, 3, 3),
			palette[1],
			Enum.PartType.Cylinder,
			0.9
		)
		TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.3, 28, 28),
		}):Play()
	end
	EFFECTS.Stars(position, nil, scale)
	EFFECTS.Fireworks(position, palette, scale)
end
-- Everything at once: the Grand Finale victory effect.
EFFECTS.Finale = function(position, colors, scale)
	EFFECTS.Confetti(position, colors, scale)
	EFFECTS.Sparkles(position, { Color3.fromRGB(255, 225, 120) }, scale)
	EFFECTS.Fireworks(position, colors, scale)
end

function EffectsController.Play(name: string, position: Vector3, colors: { Color3 }?)
	local effect = EFFECTS[name]
	if not effect then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - position).Magnitude > 400 then
		return -- too far away to see; skip the work
	end
	local scale = if State.ReducedEffects() then 0.35 else 1
	effect(position, colors, scale)
end

function EffectsController.Start(_context)
	folder = Instance.new("Folder")
	folder.Name = "LocalEffects"
	folder.Parent = workspace
	Remotes.Get("PlayEffect").OnClientEvent:Connect(function(name, position, colors)
		if type(name) == "string" and typeof(position) == "Vector3" then
			EffectsController.Play(name, position, if type(colors) == "table" then colors else nil)
		end
	end)
end

return EffectsController

-- Renders celebratory and feedback effects locally. The server only says what and where, so each
-- player's "reduced effects" setting is respected (design doc §12 accessibility).
-- The Rewards Road and career rewards add balloons, ghosts, music notes, crowns, trophies and a
-- grand finale (owner: "Also we need cool payoffs for players that keep playing the game.").
-- The HALLOWEEN PARTY's free rewards add candy, bats and a spooky knockout (owner: "Can you work
-- on all of that?").

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
	-- The HALLOWEEN PARTY's rewards (Shared/Events): a candy toss, and a knockout in purple smoke.
	Candy = function(position, _colors, scale)
		emojiBurst(position, { "🍬", "🍭" }, math.max(3, math.floor(9 * scale)))
	end,
	Spooky = function(position, _colors, scale)
		local holder = anchor(position, 3)
		burst(holder, {
			Texture = SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(150, 90, 220)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) }),
			Transparency = NumberSequence.new(0.25, 1),
			Lifetime = NumberRange.new(0.9, 1.4),
			Speed = NumberRange.new(5, 9),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 4,
		}, math.floor(18 * scale))
		emojiBurst(position, { "👻", "🦇" }, math.max(2, math.floor(6 * scale)))
	end,
}
-- Everything at once: the Grand Finale victory effect.
EFFECTS.Finale = function(position, colors, scale)
	EFFECTS.Confetti(position, colors, scale)
	EFFECTS.Sparkles(position, { Color3.fromRGB(255, 225, 120) }, scale)
	EFFECTS.Fireworks(position, colors, scale)
end
-- A swarm of bats takes off in purple and orange fireworks (the HALLOWEEN PARTY's victory reward).
EFFECTS.Bats = function(position, colors, scale)
	emojiBurst(position, "🦇", math.max(3, math.floor(9 * scale)))
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

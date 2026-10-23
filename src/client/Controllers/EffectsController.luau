-- Renders celebratory and feedback effects locally. The server only says what and where, so each
-- player's "reduced effects" setting is respected (design doc §12 accessibility).
-- The Rewards Road and career rewards add balloons, ghosts, music notes, crowns, trophies and a
-- grand finale (owner: "Also we need cool payoffs for players that keep playing the game.").
-- The HALLOWEEN PARTY's free rewards add candy, bats and a spooky knockout (owner: "Can you work
-- on all of that?").
-- The GOLD PASS's effects (owner: "the paid one should also be insane") live in their own module,
-- GoldEffects, and play by name like these.
-- The second shop pass adds thumbs up, snow, flowers, rainbows, streamers, a spotlight, a
-- supernova, paint splats, rubber ducks, a zap, and the victory and knockout cousins of three
-- emotes (a balloon flight, a streamer storm, a blizzard) that look different from them (owner: "Yes lets add more items after everything
-- else is finished"). Each one is over in about two seconds and stays small, so a knockout effect
-- never hides the game around it; with reduced effects there are fewer pieces and no flashes.
-- HOLLOW NIGHT, the first crate season (owner: "Hollow night comes first ... This will be players
-- first season. I want it to look insane."; Shared/Seasons): three knockouts (you burst into a flock
-- of crows; a leaf pile drops on you and bursts; you go out like a blown lantern, leaving a curl of
-- smoke) and three victories (a ring of bonfire flames roars up round the winner; leaves, acorns and
-- apples rain down; a giant harvest moon rises behind the winner as owls fly across it), drawn with
-- the season's own crow, owl and lantern meshes when they've arrived (Client/SeasonParts). The
-- season's auras and trails have short versions here too, for showing them off.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GoldEffects = require(script.Parent.Parent.GoldEffects)
local SeasonParts = require(script.Parent.Parent.SeasonParts)
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
local function glow(
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	shape: Enum.PartType,
	lifetime: number,
	transparency: number?
): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = shape
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency or 0.55
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
				if scale >= 1 then -- reduced effects: no flashes
					local light = Instance.new("PointLight")
					light.Color = color
					light.Range = 30
					light.Brightness = 4
					light.Parent = holder
					TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
				end
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
	-- Victory: a big bunch of balloons and gifts with a cloud of confetti in the item's colors
	-- drifting up after them (the emote's Balloons is a small bunch on its own).
	BalloonFlight = function(position, colors, scale)
		emojiBurst(position, { "🎈", "🎈", "🎁" }, math.max(3, math.floor(14 * scale)))
		local holder = anchor(position, 3)
		for _, color in colors or PARTY do
			burst(holder, {
				Texture = SPARKLE,
				Color = ColorSequence.new(color),
				LightEmission = 0.3,
				Size = NumberSequence.new(0.6, 0.3),
				Lifetime = NumberRange.new(1.4, 2.2),
				Speed = NumberRange.new(3, 7),
				SpreadAngle = Vector2.new(60, 60),
				Acceleration = Vector3.new(0, 5, 0),
				Drag = 1,
				EmissionDirection = Enum.NormalId.Top,
			}, math.floor(8 * scale))
		end
	end,
	-- Knockout: a quick icy swirl of snowflakes and snowmen (the Snow emote is a gentle shower).
	Blizzard = function(position, colors, scale)
		emojiBurst(position, { "❄️", "⛄" }, math.max(2, math.floor(5 * scale)))
		local holder = anchor(position, 2)
		burst(holder, {
			Texture = SPARKLE,
			Color = Cosmetics.ColorSequence(colors or { Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 210, 255) }),
			LightEmission = 0.4,
			Size = NumberSequence.new(0.5, 0.1),
			Lifetime = NumberRange.new(0.6, 1),
			Speed = NumberRange.new(10, 16),
			SpreadAngle = Vector2.new(180, 30),
			RotSpeed = NumberRange.new(-400, 400),
			Drag = 3,
		}, math.floor(30 * scale))
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
		-- Reduced effects: a narrower, fainter beam (no bright flash of light).
		local width = if scale >= 1 then 7 else 4
		glow(
			CFrame.new(position + Vector3.new(0, height / 2 - 3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(height, width, width),
			color,
			Enum.PartType.Cylinder,
			2,
			if scale >= 1 then 0.55 else 0.82
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
-- Victory: three volleys of streamers in the item's colors, from either side and the middle (the
-- Encore! emote's Streamers is one burst).
EFFECTS.StreamerStorm = function(position, colors, scale)
	local offsets = { Vector3.new(-3, 0, 0), Vector3.new(3, 0, 0), Vector3.zero }
	for index, offset in offsets do
		task.delay((index - 1) * 0.3, function()
			EFFECTS.Streamers(position + offset, colors, scale)
		end)
	end
end
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
-- A swarm of bats takes off in purple and orange fireworks (the HALLOWEEN PARTY's victory reward).
EFFECTS.Bats = function(position, colors, scale)
	emojiBurst(position, "🦇", math.max(3, math.floor(9 * scale)))
	EFFECTS.Fireworks(position, colors, scale)
end

-- HOLLOW NIGHT (the first crate season) -----------------------------------------------------------

local AUTUMN = {
	Color3.fromRGB(214, 72, 38),
	Color3.fromRGB(238, 120, 40),
	Color3.fromRGB(246, 168, 48),
	Color3.fromRGB(232, 190, 70),
}
local EMBER = { Color3.fromRGB(255, 241, 194), Color3.fromRGB(255, 138, 42), Color3.fromRGB(200, 50, 42) }
local DUSK = Color3.fromRGB(176, 124, 255)

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

-- The ground under `position` (characters and effects don't count), or `drop` studs down.
local function groundBelow(position: Vector3, drop: number): Vector3
	local exclude: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local pets = workspace:FindFirstChild("LocalPets")
	if pets then
		table.insert(exclude, pets)
	end
	groundParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(position, Vector3.new(0, -(drop + 6), 0), groundParams)
	return if hit then hit.Position else position - Vector3.new(0, drop, 0)
end

-- Leaves bursting from `holder`: one emitter per autumn colour.
local function leafBurst(holder: Part, count: number, props: { [string]: any })
	for _, color in AUTUMN do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		emitter.Color = ColorSequence.new(color)
		emitter.LightEmission = 0.1
		emitter.Size = NumberSequence.new(0.55, 0.4)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.8, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-260, 260)
		for key, value in props do
			(emitter :: any)[key] = value
		end
		SeasonParts.Leaves(emitter)
		emitter.Parent = holder
		emitter:Emit(math.max(1, math.floor(count / #AUTUMN)))
	end
end

-- Emoji that fall from `height` studs over `position` to the ground (apples, acorns, leaves).
local function emojiRain(position: Vector3, emoji: { string }, count: number, height: number)
	local holder = anchor(position, 3)
	for index = 1, count do
		task.delay(math.random() * 0.8, function()
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(40, 40)
			gui.LightInfluence = 0
			gui.MaxDistance = 120
			local start = Vector3.new(math.random() * 8 - 4, height, math.random() * 8 - 4)
			gui.StudsOffset = start
			gui.Adornee = holder
			gui.Parent = holder
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.TextScaled = true
			label.Text = emoji[(index - 1) % #emoji + 1]
			label.Rotation = math.random(-40, 40)
			label.Parent = gui
			TweenService:Create(gui, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				StudsOffset = Vector3.new(start.X, -2.5, start.Z),
			}):Play()
			TweenService:Create(
				label,
				TweenInfo.new(1.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
				{ TextTransparency = 1 }
			):Play()
		end)
	end
end

type Flyer = { Parts: { BasePart }, Offsets: { CFrame }, Wings: { { Part: BasePart, Hinge: Vector3, Side: number } } }

-- A local copy of a season mesh (scaled) that flies: its parts and where each sits, and its wings
-- (WingL... / WingR..., turning at their inner edge). Nil before the meshes have arrived.
local function flyer(name: string, scale: number, tint: Color3?): Flyer?
	local model = SeasonParts.Copy(name)
	if not model then
		return nil
	end
	model:ScaleTo(model:GetScale() * scale)
	local pivot = model:GetPivot()
	local result: Flyer = { Parts = {}, Offsets = {}, Wings = {} }
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local offset = pivot:ToObjectSpace(part.CFrame)
			table.insert(result.Parts, part)
			table.insert(result.Offsets, offset)
			local side = if string.sub(part.Name, 1, 5) == "WingL"
				then 1
				elseif string.sub(part.Name, 1, 5) == "WingR" then -1
				else 0
			if side ~= 0 then
				local inner = offset.Position.X - side * part.Size.X / 2
				table.insert(
					result.Wings,
					{ Part = part, Hinge = Vector3.new(inner, offset.Position.Y, offset.Position.Z), Side = side }
				)
			end
			-- (A pet's flat light disc was drawn for it sitting on the ground: not in the air.)
			if part.Name == "Glow" and part.Size.Y < 0.15 then
				part.Transparency = 1
			end
			-- A silhouette against the moon: dark, but the glowing eyes stay lit.
			if tint and part.Material ~= Enum.Material.Neon then
				part.Color = tint
				part.Material = Enum.Material.SmoothPlastic
			end
		end
	end
	model.Parent = folder
	Debris:AddItem(model, 8)
	return result
end

-- Flies `flyers` for `duration` seconds: `path(index, t)` says where each is and where it's going
-- (t from 0 to 1); their wings flap; they fade out over the last third.
local function fly(flyers: { Flyer }, duration: number, path: (index: number, t: number) -> (Vector3, Vector3))
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) / duration
		if t >= 1 then
			connection:Disconnect()
			for _, each in flyers do
				for _, part in each.Parts do
					part:Destroy()
				end
			end
			return
		end
		local parts, frames = {}, {}
		for index, each in flyers do
			local at, heading = path(index, t)
			local base = CFrame.lookAt(at, at + heading)
			local flap = math.rad(55) * math.sin((os.clock() - started) * 26 + index)
			local wingOf: { [BasePart]: CFrame } = {}
			for _, wing in each.Wings do
				local hinge = CFrame.new(wing.Hinge)
				wingOf[wing.Part] = hinge * CFrame.Angles(0, 0, wing.Side * flap) * hinge:Inverse()
			end
			local fade = math.clamp((t - 0.66) / 0.34, 0, 1)
			for partIndex, part in each.Parts do
				local turn = wingOf[part]
				table.insert(parts, part)
				table.insert(
					frames,
					if turn then base * turn * each.Offsets[partIndex] else base * each.Offsets[partIndex]
				)
				part.LocalTransparencyModifier = fade
			end
		end
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

-- Knockout: you burst into a flock of crows (in a puff of dusk-purple smoke and feathers).
EFFECTS.CrowScatter = function(position, _colors, scale)
	local holder = anchor(position, 3)
	burst(holder, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(110, 76, 160), Color3.fromRGB(40, 30, 56)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) }),
		Transparency = NumberSequence.new(0.35, 1),
		Lifetime = NumberRange.new(0.7, 1.1),
		Speed = NumberRange.new(4, 8),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
	}, math.floor(14 * scale))
	burst(holder, {
		Texture = SPARKLE,
		Color = ColorSequence.new(Color3.fromRGB(34, 28, 46)),
		Size = NumberSequence.new(0.4, 0.25),
		Squash = NumberSequence.new(-1),
		Lifetime = NumberRange.new(1, 1.6),
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -7, 0),
		Drag = 2.5,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300),
	}, math.floor(18 * scale))
	if scale >= 1 then
		flash(holder, DUSK, 14)
	end
	local count = math.max(3, math.floor(9 * scale))
	local crows, directions, speeds = {}, {}, {}
	for _ = 1, count do
		local crow = flyer("HarvestCrow", 1.6)
		if not crow then
			emojiBurst(position, "🐦", count) -- (the crow's mesh hasn't arrived)
			return
		end
		table.insert(crows, crow)
		local angle = math.random() * math.pi * 2
		table.insert(directions, Vector3.new(math.cos(angle), 0.55 + math.random() * 0.7, math.sin(angle)).Unit)
		table.insert(speeds, 13 + math.random() * 9)
	end
	fly(crows, 1.8, function(index, t)
		local direction = directions[index]
		local travelled = speeds[index] * 1.8 * (t + 0.25 * t * t)
		local at = position + direction * travelled + Vector3.new(0, 3 * t * t, 0)
		return at, Vector3.new(direction.X, direction.Y * 0.4, direction.Z)
	end)
end

-- Knockout: a pile of leaves drops on the spot and bursts everywhere.
EFFECTS.LeafPile = function(position, _colors, scale)
	local ground = groundBelow(position, 3)
	local pile = Instance.new("Part")
	pile.Name = "LeafPileDrop"
	pile.Shape = Enum.PartType.Ball
	pile.Material = Enum.Material.Grass
	pile.Color = AUTUMN[2]
	pile.Anchored = true
	pile.CanCollide = false
	pile.CanQuery = false
	pile.CanTouch = false
	pile.CastShadow = false
	pile.Size = Vector3.new(5, 2.4, 5)
	pile.CFrame = CFrame.new(ground + Vector3.new(0, 9, 0))
	pile.Parent = folder
	Debris:AddItem(pile, 2)
	local drop = TweenService:Create(pile, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.new(ground + Vector3.new(0, 0.6, 0)),
	})
	drop:Play()
	drop.Completed:Once(function()
		local holder = anchor(ground + Vector3.new(0, 1, 0), 3)
		leafBurst(holder, math.floor(56 * scale), {
			Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(10, 18),
			SpreadAngle = Vector2.new(70, 70),
			Acceleration = Vector3.new(0, -14, 0),
			Drag = 2.5,
			EmissionDirection = Enum.NormalId.Top,
		})
		TweenService:Create(pile, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = Vector3.new(0.2, 0.2, 0.2),
			Transparency = 1,
		}):Play()
	end)
end

-- Knockout: you go out like a blown lantern: it glows, flickers, goes dark, and a curl of smoke
-- drifts up off it.
EFFECTS.LanternSnuff = function(position, colors, scale)
	local glowColor = (colors and colors[1]) or Color3.fromRGB(255, 181, 48)
	local at = position + Vector3.new(0, 0.5, 0)
	local model = SeasonParts.Copy("PaperLantern")
	local paper: BasePart
	if model then
		model:ScaleTo(model:GetScale() * 2.2)
		model:PivotTo(CFrame.new(at - Vector3.new(0, 1.2, 0)))
		model.Parent = folder
		Debris:AddItem(model, 3.4)
		local found = model:FindFirstChild("Paper", true)
		paper = if found and found:IsA("BasePart")
			then found
			else model:FindFirstChildWhichIsA("BasePart", true) :: BasePart
	else
		paper = glow(CFrame.new(at), Vector3.one * 1.8, glowColor, Enum.PartType.Ball, 3, 0.05)
	end
	paper.Color = glowColor
	local light = Instance.new("PointLight")
	light.Color = glowColor
	light.Range = 12
	light.Brightness = if scale >= 1 then 2.5 else 1
	light.Parent = paper
	-- The flicker, then out.
	task.spawn(function()
		for _ = 1, 6 do
			task.wait(0.06 + math.random() * 0.06)
			light.Brightness = (if scale >= 1 then 2.5 else 1) * (0.3 + math.random() * 0.7)
		end
		light.Brightness = 0
		paper.Material = Enum.Material.SmoothPlastic
		paper.Color = Color3.fromRGB(70, 46, 40)
		-- A curl of smoke: a puff source that circles as it rises, leaving the smoke where it was.
		local holder = anchor(at + Vector3.new(0, 1.2, 0), 3)
		local source = Instance.new("Attachment")
		source.Parent = holder
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = SMOKE
		smoke.Color = ColorSequence.new(Color3.fromRGB(196, 186, 200), Color3.fromRGB(110, 100, 120))
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.6) })
		smoke.Transparency = NumberSequence.new(0.35, 1)
		smoke.Lifetime = NumberRange.new(0.9, 1.3)
		smoke.Speed = NumberRange.new(0.2, 0.5)
		smoke.Rate = 40 * scale + 6
		smoke.Parent = source
		local started = os.clock()
		while os.clock() - started < 1.3 do
			local t = os.clock() - started
			source.Position = Vector3.new(math.cos(t * 7) * 0.5 * (1 + t), t * 3, math.sin(t * 7) * 0.5 * (1 + t))
			task.wait()
		end
		smoke.Enabled = false
		for _, part in (if model then model:GetDescendants() else { paper }) do
			if part:IsA("BasePart") then
				TweenService:Create(part, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			end
		end
	end)
end

-- Victory: a ring of bonfire flames roars up round the winner, with stones and rising embers.
EFFECTS.Bonfire = function(position, _colors, scale)
	local ground = groundBelow(position, 6)
	local count = if scale >= 1 then 8 else 5
	for index = 1, count do
		local angle = index / count * math.pi * 2
		local spot = ground + Vector3.new(math.cos(angle) * 3.6, 0.4, math.sin(angle) * 3.6)
		local holder = anchor(spot, 3.4)
		local fire = Instance.new("ParticleEmitter")
		fire.Texture = SeasonParts.Fire
		fire.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, EMBER[1]),
			ColorSequenceKeypoint.new(0.4, EMBER[2]),
			ColorSequenceKeypoint.new(1, EMBER[3]),
		})
		fire.LightEmission = 1
		fire.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.2),
			NumberSequenceKeypoint.new(0.4, 2.2),
			NumberSequenceKeypoint.new(1, 0.2),
		})
		fire.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.2, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		fire.Lifetime = NumberRange.new(0.45, 0.75)
		fire.Speed = NumberRange.new(6, 10)
		fire.SpreadAngle = Vector2.new(10, 10)
		fire.Acceleration = Vector3.new(0, 5, 0)
		fire.Rotation = NumberRange.new(0, 360)
		fire.RotSpeed = NumberRange.new(-60, 60)
		fire.EmissionDirection = Enum.NormalId.Top
		fire.Rate = 22 * scale + 6
		fire.Parent = holder
		task.delay(2.2, function()
			fire.Enabled = false
		end)
		-- A stone between each pair of flames.
		local stoneAngle = angle + math.pi / count
		glow(
			CFrame.new(ground + Vector3.new(math.cos(stoneAngle) * 3.6, 0.3, math.sin(stoneAngle) * 3.6)),
			Vector3.new(0.9, 0.6, 0.8),
			Color3.fromRGB(90, 84, 102),
			Enum.PartType.Ball,
			3,
			0
		).Material =
			Enum.Material.Slate
	end
	local center = anchor(ground + Vector3.new(0, 1, 0), 4)
	burst(center, {
		Texture = SeasonParts.EmberTexture(),
		Color = ColorSequence.new(EMBER[1], EMBER[2]),
		LightEmission = 1,
		Size = NumberSequence.new(0.3, 0),
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(50, 50),
		Acceleration = Vector3.new(0, 3, 0),
		Drag = 1,
		EmissionDirection = Enum.NormalId.Top,
	}, math.floor(50 * scale))
	if scale >= 1 then
		local light = Instance.new("PointLight")
		light.Color = EMBER[2]
		light.Range = 22
		light.Brightness = 3
		light.Parent = center
		TweenService
			:Create(light, TweenInfo.new(2.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = 0 })
			:Play()
	end
end

-- Victory: leaves, acorns and apples rain down on the winner.
EFFECTS.HarvestRain = function(position, _colors, scale)
	local sky = Instance.new("Part")
	sky.Anchored = true
	sky.CanCollide = false
	sky.CanQuery = false
	sky.CanTouch = false
	sky.Transparency = 1
	sky.Size = Vector3.new(12, 1, 12)
	sky.CFrame = CFrame.new(position + Vector3.new(0, 9, 0))
	sky.Parent = folder
	Debris:AddItem(sky, 4.5)
	for _, color in AUTUMN do
		local leaves = Instance.new("ParticleEmitter")
		leaves.Color = ColorSequence.new(color)
		leaves.LightEmission = 0.1
		leaves.Size = NumberSequence.new(0.6, 0.45)
		leaves.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.85, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		leaves.Lifetime = NumberRange.new(1.8, 2.4)
		leaves.Speed = NumberRange.new(1, 3)
		leaves.EmissionDirection = Enum.NormalId.Bottom
		leaves.Acceleration = Vector3.new(0.5, -5, 0.3)
		leaves.Rotation = NumberRange.new(0, 360)
		leaves.RotSpeed = NumberRange.new(-200, 200)
		leaves.Rate = 9 * scale + 2
		SeasonParts.Leaves(leaves)
		leaves.Parent = sky
		task.delay(1.8, function()
			leaves.Enabled = false
		end)
	end
	emojiRain(position, { "🍎", "🌰", "🍂", "🍁" }, math.max(4, math.floor(14 * scale)), 9)
end

-- Victory: a giant harvest moon rises behind the winner, glowing, while owls fly across it.
EFFECTS.Moonrise = function(position, _colors, scale)
	local camera = workspace.CurrentCamera
	local away = if camera then position - camera.CFrame.Position else Vector3.new(0, 0, -1)
	away = Vector3.new(away.X, 0, away.Z)
	away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, -1)
	local across = Vector3.new(-away.Z, 0, away.X)
	local size = if scale >= 1 then 13 else 9
	local center = position + away * 16
	local parts: { BasePart } = {}
	local offsets: { Vector3 } = {}
	local function piece(radius: number, color: Color3, offset: Vector3, transparency: number)
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Transparency = transparency
		part.Size = Vector3.one * radius * 2
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = folder
		Debris:AddItem(part, 4)
		table.insert(parts, part)
		table.insert(offsets, offset)
		return part
	end
	local moon = piece(size / 2, Color3.fromRGB(255, 207, 122), Vector3.zero, 0.04)
	piece(size * 0.66, Color3.fromRGB(255, 160, 80), Vector3.zero, 0.82) -- its halo
	local rng = Random.new()
	for _ = 1, 6 do
		local spot = Vector3.new(rng:NextNumber(-0.55, 0.55), rng:NextNumber(-0.55, 0.55), 0)
		local offset = across * spot.X * size / 2 + Vector3.new(0, spot.Y * size / 2, 0) - away * size * 0.4
		piece(size * rng:NextNumber(0.06, 0.12), Color3.fromRGB(240, 160, 78), offset, 0.1)
	end
	if scale >= 1 then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 110)
		light.Range = 40
		light.Brightness = 2
		light.Parent = moon
	end
	local rise = 1.6
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t > 3.6 or not moon.Parent then
			connection:Disconnect()
			return
		end
		local up = 1 - (1 - math.clamp(t / rise, 0, 1)) ^ 3
		local at = center + Vector3.new(0, -size + up * (size + 6), 0)
		local fade = math.clamp((t - 3) / 0.6, 0, 1)
		local frames = {}
		for index, part in parts do
			table.insert(frames, CFrame.new(at + offsets[index]))
			part.LocalTransparencyModifier = fade
		end
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	-- The owls, dark against the moon, eyes glowing.
	task.delay(0.9, function()
		local owls = {}
		for _ = 1, if scale >= 1 then 3 else 1 do
			local owl = flyer("HarvestOwl", 0.55, Color3.fromRGB(26, 20, 38))
			if not owl then
				return
			end
			table.insert(owls, owl)
		end
		local heights = { 7.5, 10, 5.5 }
		fly(owls, 2.6, function(index, t)
			local from = center - across * (size + 6) - away * 3 + Vector3.new(0, heights[index], 0)
			local at = from + across * (size * 2 + 12) * (t + (index - 1) * 0.08)
			at += Vector3.new(0, math.sin(t * math.pi * 2 + index) * 0.8, 0)
			return at, across
		end)
	end)
end

-- The season's auras and trails, as quick bursts (for showing them off).
EFFECTS.LeafWhirl = function(position, _colors, scale)
	local holder = anchor(position, 2.5)
	local source = Instance.new("Attachment")
	source.Parent = holder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(AUTUMN[2], AUTUMN[3])
	emitter.Size = NumberSequence.new(0.45, 0.3)
	emitter.Lifetime = NumberRange.new(0.8, 1.1)
	emitter.Speed = NumberRange.new(0.2, 0.5)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.Rate = 30 * scale + 6
	SeasonParts.Leaves(emitter)
	emitter.Parent = source
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < 1.4 do
			local t = os.clock() - started
			source.Position = Vector3.new(math.cos(t * 8) * 2.2, -2 + t * 3, math.sin(t * 8) * 2.2)
			task.wait()
		end
		emitter.Enabled = false
	end)
end
EFFECTS.Fireflies = function(position, colors, scale)
	local holder = anchor(position, 5)
	burst(holder, {
		Texture = SeasonParts.EmberTexture(),
		Color = ColorSequence.new((colors and colors[1]) or Color3.fromRGB(255, 226, 122)),
		LightEmission = 1,
		Size = NumberSequence.new(0.25),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0),
			NumberSequenceKeypoint.new(0.35, 0.85),
			NumberSequenceKeypoint.new(0.55, 0),
			NumberSequenceKeypoint.new(0.8, 0.8),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(2.5, 4),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 1,
	}, math.floor(24 * scale) + 4)
end
EFFECTS.LanternRing = function(position, colors, scale)
	local lanterns = {}
	for _ = 1, 3 do
		local lantern = flyer("PaperLantern", 1.2)
		if not lantern then
			EFFECTS.Fireflies(position, colors, scale) -- (the lantern's mesh hasn't arrived)
			return
		end
		table.insert(lanterns, lantern)
	end
	fly(lanterns, 2, function(index, t)
		local angle = t * math.pi * 2 + index * math.pi * 2 / 3
		return position + Vector3.new(
			math.cos(angle) * 2.6,
			-1 + math.sin(t * math.pi * 3) * 0.3,
			math.sin(angle) * 2.6
		),
			Vector3.new(-math.sin(angle), 0, math.cos(angle))
	end)
end
EFFECTS.Embers = function(position, _colors, scale)
	local holder = anchor(position, 3)
	burst(holder, {
		Texture = SeasonParts.EmberTexture(),
		Color = ColorSequence.new(EMBER[1], EMBER[2]),
		LightEmission = 1,
		Size = NumberSequence.new(0.35, 0),
		Lifetime = NumberRange.new(1, 1.8),
		Speed = NumberRange.new(3, 7),
		SpreadAngle = Vector2.new(60, 60),
		Acceleration = Vector3.new(0, 3, 0),
		Drag = 1,
		EmissionDirection = Enum.NormalId.Top,
	}, math.floor(36 * scale) + 4)
end
EFFECTS.FallingLeaves = function(position, _colors, scale)
	local holder = anchor(position + Vector3.new(0, 3, 0), 3)
	leafBurst(holder, math.floor(28 * scale) + 4, {
		Lifetime = NumberRange.new(1.6, 2.2),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 30),
		Acceleration = Vector3.new(0.4, -3, 0.2),
		Drag = 0.5,
	})
end
EFFECTS.WispSteps = function(position, colors, scale)
	local wisp = (colors and colors[2]) or Color3.fromRGB(125, 255, 178)
	local ground = groundBelow(position, 3)
	for index = 1, 5 do
		task.delay((index - 1) * 0.12, function()
			local holder = anchor(ground + Vector3.new((index - 3) * 1.2, 0.3, (index % 2) * 0.8 - 0.4), 2)
			burst(holder, {
				Texture = SeasonParts.Fire,
				Color = ColorSequence.new(Color3.fromRGB(216, 255, 240), wisp),
				LightEmission = 1,
				Size = NumberSequence.new(0.7, 0),
				Lifetime = NumberRange.new(0.5, 0.8),
				Speed = NumberRange.new(1, 2),
				SpreadAngle = Vector2.new(10, 10),
				Acceleration = Vector3.new(0, 3, 0),
				EmissionDirection = Enum.NormalId.Top,
			}, math.floor(8 * scale) + 2)
		end)
	end
end

function EffectsController.Play(name: string, position: Vector3, colors: { Color3 }?)
	local effect = EFFECTS[name] or GoldEffects.Get(name)
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

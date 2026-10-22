-- The GOLD PASS's effects (owner: "Also we do need a paid battle pass too. I like the current free
-- one. But the paid one should also be insane."): the gold lane's victory, knockout and emote effects
-- (Shared/GoldPass), drawn on each device like the rest (Controllers/EffectsController plays them by
-- name: the server only says which and where, so each player's reduced effects setting holds).
--
--   Victory: GOLD RUSH (gold coins rain down), GOLDEN BEAM (a pillar of gold light from the sky),
--     CHAMPAGNE SHOWER (a pop, bubbles, gold confetti and clinking glasses), GOLDEN SUPERNOVA (the
--     level 75 showstopper: a white-gold flash, a burst of gold rays, a shockwave, three gold
--     fireworks and coins raining down) and GOLD SHOCKWAVE (three rings of gold sparks racing out).
--   Knockout: GOLD DUST (a puff of gold glitter), TREASURE POP (coins burst out in arcs), DIAMOND
--     SHATTER (glassy shards fly apart) and MIDAS TOUCH (a gold statue of you that crumbles to dust).
--   Emotes: MAKE IT RAIN (cash and coins fly), HEART OF GOLD (gold hearts), DIAMOND DROP (diamonds
--     fall around you) and GOLDEN AURA (rings of light rise round you as sparks spiral up).
--
-- Coins, shards and the statue are small parts made on this device only (anchored, no collisions,
-- touches or ray hits) and gone within seconds; flashes and rings are Neon. With reduced effects
-- (scale 0.35) there are far fewer pieces and no flashes. Built for phones: a few dozen parts at most.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local GoldEffects = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local GOLD = Color3.fromRGB(255, 196, 40)
local GOLD_LIGHT = Color3.fromRGB(255, 236, 150)
local GOLD_DEEP = Color3.fromRGB(214, 132, 18)
local WHITE_GOLD = Color3.fromRGB(255, 250, 225)
local DIAMOND = Color3.fromRGB(190, 240, 255)

type Effect = (position: Vector3, colors: { Color3 }?, scale: number) -> ()

local function folder(): Instance
	return workspace:FindFirstChild("LocalEffects") or workspace
end

-- A part for an effect: anchored, never in anyone's way, gone after `lifetime` seconds.
local function piece(props: { [string]: any }, lifetime: number): BasePart
	local class = props.ClassName or "Part"
	props.ClassName = nil
	local part = Instance.new(class) :: BasePart
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = folder()
	Debris:AddItem(part, lifetime)
	return part
end

local function anchor(position: Vector3, lifetime: number): BasePart
	return piece({ Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(position) }, lifetime)
end

local function tween(
	instance: Instance,
	time: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
)
	TweenService
		:Create(
			instance,
			TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
			goal
		)
		:Play()
end

local function burst(parent: Instance, props: { [string]: any }, count: number)
	if count < 1 then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Texture = SPARKLE
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = parent
	emitter:Emit(count)
end

-- Gold sparkles bursting out of `position`.
local function sparkles(position: Vector3, color: Color3, count: number, speed: number?)
	local holder = anchor(position, 3)
	burst(holder, {
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Size = NumberSequence.new(0.9, 0),
		Lifetime = NumberRange.new(0.8, 1.6),
		Speed = NumberRange.new((speed or 10) * 0.5, speed or 10),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 1.5,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-200, 200),
	}, count)
end

local function light(position: Vector3, color: Color3, brightness: number, range: number, time: number)
	local holder = anchor(position, time + 0.2)
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Brightness = brightness
	glow.Range = range
	glow.Shadows = false
	glow.Parent = holder
	tween(glow, time, { Brightness = 0 })
end

-- Emoji that rise (or fall, with `drop`) and fade, around `position`.
local function emoji(position: Vector3, choices: { string }, count: number, drop: boolean?)
	local holder = anchor(position, 3)
	for index = 1, count do
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(46, 46)
		gui.LightInfluence = 0
		gui.MaxDistance = 120
		local start = Vector3.new(
			math.random() * 6 - 3,
			if drop then 6 + math.random() * 3 else math.random() * 1.5,
			math.random() * 6 - 3
		)
		gui.StudsOffset = start
		gui.Adornee = holder
		gui.Parent = holder
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Text = choices[(index - 1) % #choices + 1]
		label.Parent = gui
		local move = if drop
			then Vector3.new(0, -(7 + math.random() * 2), 0)
			else Vector3.new(0, 4 + math.random() * 3, 0)
		tween(
			gui,
			2,
			{ StudsOffset = start + move },
			Enum.EasingStyle.Quad,
			if drop then Enum.EasingDirection.In else Enum.EasingDirection.Out
		)
		tween(label, 2, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
end

-- A spinning gold coin that travels from `from` to `to` in `time` seconds, then fades.
local function coin(from: Vector3, to: Vector3, time: number, delay: number?)
	task.delay(delay or 0, function()
		local spin = CFrame.Angles(0, math.random() * math.pi * 2, math.rad(90))
		local part = piece({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.16, 1.1, 1.1),
			Color = GOLD,
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.35,
			CFrame = CFrame.new(from) * spin,
		}, time + 0.6)
		tween(
			part,
			time,
			{ CFrame = CFrame.new(to) * spin * CFrame.Angles(math.rad(720), 0, 0) },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		task.delay(time, function()
			tween(part, 0.5, { Transparency = 1 })
		end)
	end)
end

-- Coins falling from above onto a circle round `position` (its ground `drop` studs below).
local function coinRain(position: Vector3, count: number, radius: number, drop: number)
	for _ = 1, count do
		local offset = Vector3.new((math.random() - 0.5) * 2 * radius, 0, (math.random() - 0.5) * 2 * radius)
		local from = position + offset + Vector3.new(0, 8 + math.random() * 5, 0)
		coin(from, position + offset - Vector3.new(0, drop, 0), 1 + math.random() * 0.5, math.random() * 0.9)
	end
end

-- A ring of `count` gold sparks racing out flat from `center` to `radius` studs.
local function sparkRing(center: Vector3, count: number, radius: number, time: number, color: Color3, delay: number?)
	task.delay(delay or 0, function()
		for index = 1, count do
			local angle = 2 * math.pi * index / count
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local spark = piece({
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.7,
				Color = color,
				Material = Enum.Material.Neon,
				CFrame = CFrame.new(center + direction * 0.8),
			}, time + 0.2)
			tween(
				spark,
				time,
				{ CFrame = CFrame.new(center + direction * radius), Size = Vector3.one * 0.25, Transparency = 1 }
			)
		end
	end)
end

-- A flat glowing disc that grows and fades (a shockwave on the ground, or a halo).
local function disc(center: Vector3, from: number, to: number, time: number, color: Color3, delay: number?)
	task.delay(delay or 0, function()
		local part = piece({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.15, from, from),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.25,
			CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		}, time + 0.2)
		tween(part, time, { Size = Vector3.new(0.15, to, to), Transparency = 1 })
	end)
end

local EFFECTS: { [string]: Effect } = {}

-- Victory ----------------------------------------------------------------------------------------

EFFECTS.GoldRush = function(position, _colors, scale)
	sparkles(position + Vector3.new(0, 4, 0), GOLD_LIGHT, math.floor(30 * scale), 12)
	coinRain(position, math.max(5, math.floor(24 * scale)), 5, 6)
	light(position, GOLD, 3, 22, 1.6)
end

EFFECTS.GoldenBeam = function(position, _colors, scale)
	local ground = position - Vector3.new(0, 6, 0)
	local beam = piece({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(60, 1, 1),
		Color = GOLD_LIGHT,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CFrame = CFrame.new(ground + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	}, 3)
	tween(beam, 0.35, { Size = Vector3.new(60, 6, 6) }, Enum.EasingStyle.Back)
	task.delay(1.4, function()
		tween(beam, 1.2, { Size = Vector3.new(60, 0.5, 0.5), Transparency = 1 })
	end)
	-- Sparkles drifting down inside it, and a glow on the ground.
	local top = anchor(ground + Vector3.new(0, 16, 0), 4)
	burst(top, {
		Color = ColorSequence.new(WHITE_GOLD),
		LightEmission = 1,
		Size = NumberSequence.new(0.8, 0.2),
		Lifetime = NumberRange.new(1.5, 2.2),
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(20, 20),
		Acceleration = Vector3.new(0, -9, 0),
		EmissionDirection = Enum.NormalId.Bottom,
	}, math.floor(50 * scale))
	disc(ground + Vector3.new(0, 0.1, 0), 3, 14, 1.4, GOLD)
	light(position, GOLD_LIGHT, 4, 30, 2.4)
end

EFFECTS.Champagne = function(position, _colors, scale)
	sparkles(position + Vector3.new(0, 1, 0), WHITE_GOLD, math.floor(24 * scale), 16)
	-- Bubbles rising.
	local foam = anchor(position, 4)
	burst(foam, {
		Color = ColorSequence.new(Color3.fromRGB(255, 246, 210)),
		LightEmission = 0.6,
		Transparency = NumberSequence.new(0.2, 1),
		Size = NumberSequence.new(0.5, 0.8),
		Lifetime = NumberRange.new(1.4, 2.4),
		Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, 6, 0),
		Drag = 1,
		EmissionDirection = Enum.NormalId.Top,
	}, math.floor(40 * scale))
	-- Gold confetti.
	for _, color in { GOLD, GOLD_LIGHT, WHITE_GOLD } do
		burst(foam, {
			Color = ColorSequence.new(color),
			LightEmission = 0.4,
			Size = NumberSequence.new(0.6, 0.35),
			Lifetime = NumberRange.new(1.8, 2.6),
			Speed = NumberRange.new(14, 24),
			SpreadAngle = Vector2.new(50, 50),
			Acceleration = Vector3.new(0, -28, 0),
			Drag = 1.5,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-300, 300),
			EmissionDirection = Enum.NormalId.Top,
		}, math.floor(12 * scale))
	end
	emoji(position, { "🍾", "🥂" }, math.max(2, math.floor(6 * scale)))
end

EFFECTS.Supernova = function(position, _colors, scale)
	local reduced = scale < 1
	if not reduced then
		-- The flash: a white-gold sphere bursting out and fading.
		local flash = piece({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2,
			Color = WHITE_GOLD,
			Material = Enum.Material.Neon,
			Transparency = 0.1,
			CFrame = CFrame.new(position),
		}, 1.2)
		tween(flash, 0.9, { Size = Vector3.one * 24, Transparency = 1 })
		-- Gold rays shooting out.
		for index = 1, 10 do
			local direction = CFrame.Angles(0, 2 * math.pi * index / 10, math.rad(math.random(-35, 35)))
			local ray = piece({
				Size = Vector3.new(0.4, 0.4, 2),
				Color = GOLD_LIGHT,
				Material = Enum.Material.Neon,
				CFrame = CFrame.new(position) * direction * CFrame.new(0, 0, -2),
			}, 1)
			tween(ray, 0.8, {
				Size = Vector3.new(0.15, 0.15, 14),
				CFrame = CFrame.new(position) * direction * CFrame.new(0, 0, -10),
				Transparency = 1,
			})
		end
		light(position, WHITE_GOLD, 8, 40, 1.8)
	end
	disc(position - Vector3.new(0, 5.8, 0), 2, 30, 1.1, GOLD, 0.1)
	sparkRing(position - Vector3.new(0, 5, 0), math.max(8, math.floor(20 * scale)), 16, 0.9, GOLD_LIGHT, 0.15)
	for index = 1, 3 do
		task.delay(0.25 + (index - 1) * 0.3, function()
			local offset = Vector3.new(math.random(-7, 7), math.random(7, 13), math.random(-7, 7))
			local holder = anchor(position + offset, 3)
			burst(holder, {
				Color = ColorSequence.new(if index == 2 then WHITE_GOLD else GOLD),
				LightEmission = 1,
				Size = NumberSequence.new(1.1, 0),
				Lifetime = NumberRange.new(1, 1.6),
				Speed = NumberRange.new(18, 28),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, -12, 0),
				Drag = 2,
			}, math.floor(45 * scale))
		end)
	end
	coinRain(position, math.max(4, math.floor(16 * scale)), 6, 6)
end

EFFECTS.GoldShockwave = function(position, _colors, scale)
	local ground = position - Vector3.new(0, 5.6, 0)
	for wave = 1, 3 do
		local delay = (wave - 1) * 0.28
		sparkRing(
			ground,
			math.max(8, math.floor(22 * scale)),
			12 + wave * 4,
			0.9,
			if wave == 2 then WHITE_GOLD else GOLD,
			delay
		)
		disc(ground + Vector3.new(0, 0.05 * wave, 0), 2, 14 + wave * 6, 0.9, GOLD_DEEP, delay)
	end
	sparkles(position, GOLD_LIGHT, math.floor(24 * scale), 10)
	light(position, GOLD, 4, 26, 1.6)
end

-- Knockout -----------------------------------------------------------------------------------------

EFFECTS.GoldDust = function(position, _colors, scale)
	sparkles(position, GOLD_LIGHT, math.floor(40 * scale), 9)
	local holder = anchor(position, 3)
	burst(holder, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(255, 214, 110)),
		LightEmission = 0.3,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) }),
		Transparency = NumberSequence.new(0.3, 1),
		Lifetime = NumberRange.new(0.8, 1.3),
		Speed = NumberRange.new(5, 9),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
	}, math.floor(14 * scale))
	light(position, GOLD, 2, 14, 0.8)
end

EFFECTS.TreasurePop = function(position, _colors, scale)
	for _ = 1, math.max(5, math.floor(16 * scale)) do
		local angle = math.random() * 2 * math.pi
		local reach = 3 + math.random() * 5
		local landing = position + Vector3.new(math.cos(angle) * reach, -2.5, math.sin(angle) * reach)
		-- Up first, then down to the landing spot.
		local peak = position:Lerp(landing, 0.5) + Vector3.new(0, 4 + math.random() * 3, 0)
		coin(position, peak, 0.35)
		coin(peak, landing, 0.55, 0.35)
	end
	sparkles(position, GOLD_LIGHT, math.floor(26 * scale), 12)
	emoji(position, { "💰" }, math.max(1, math.floor(3 * scale)))
end

EFFECTS.DiamondShatter = function(position, _colors, scale)
	for _ = 1, math.max(5, math.floor(16 * scale)) do
		local direction = Vector3.new(math.random() - 0.5, math.random() * 0.9, math.random() - 0.5).Unit
		local size = 0.3 + math.random() * 0.45
		local spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		local shard = piece({
			ClassName = "WedgePart",
			Size = Vector3.new(size * 0.5, size, size * 1.4),
			Color = if math.random() < 0.5 then DIAMOND else WHITE_GOLD,
			Material = Enum.Material.Neon,
			Transparency = 0.1,
			CFrame = CFrame.new(position) * spin,
		}, 1.6)
		local landing = position + direction * (5 + math.random() * 4) - Vector3.new(0, 2, 0)
		tween(shard, 1.1, {
			CFrame = CFrame.new(landing) * spin * CFrame.Angles(math.random() * 8, math.random() * 8, 0),
			Transparency = 1,
		})
	end
	sparkles(position, DIAMOND, math.floor(30 * scale), 14)
	light(position, DIAMOND, 3, 18, 0.9)
end

EFFECTS.MidasTouch = function(position, _colors, scale)
	-- A little gold statue where you were...
	local base = position - Vector3.new(0, 2.6, 0)
	local parts: { BasePart } = {}
	local shape = {
		{ Vector3.new(2, 2, 1), Vector3.new(0, 2.6, 0), Enum.PartType.Block }, -- body
		{ Vector3.one * 1.3, Vector3.new(0, 4.3, 0), Enum.PartType.Ball }, -- head
		{ Vector3.new(0.9, 1.9, 0.9), Vector3.new(-1.5, 2.9, 0), Enum.PartType.Block }, -- arms, raised a little
		{ Vector3.new(0.9, 1.9, 0.9), Vector3.new(1.5, 2.9, 0), Enum.PartType.Block },
		{ Vector3.new(0.95, 1.7, 0.95), Vector3.new(-0.5, 0.85, 0), Enum.PartType.Block }, -- legs
		{ Vector3.new(0.95, 1.7, 0.95), Vector3.new(0.5, 0.85, 0), Enum.PartType.Block },
	}
	for _, bit in shape do
		table.insert(
			parts,
			piece({
				Shape = bit[3],
				Size = bit[1],
				Color = GOLD,
				Material = Enum.Material.SmoothPlastic,
				Reflectance = 0.45,
				CFrame = CFrame.new(base + bit[2]),
			}, 2.6)
		)
	end
	sparkles(base + Vector3.new(0, 2.5, 0), WHITE_GOLD, math.floor(20 * scale), 4)
	light(base + Vector3.new(0, 3, 0), GOLD_LIGHT, 2.5, 14, 1.4)
	-- ...that crumbles into gold dust.
	task.delay(1.1, function()
		for _, part in parts do
			local center = part.Position
			part.Transparency = 1
			for _ = 1, if scale < 1 then 1 else 3 do
				local nugget = piece({
					Size = Vector3.one * (0.3 + math.random() * 0.3),
					Color = if math.random() < 0.5 then GOLD else GOLD_DEEP,
					Material = Enum.Material.SmoothPlastic,
					Reflectance = 0.3,
					CFrame = CFrame.new(
						center + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
					) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
				}, 1.4)
				tween(nugget, 0.9, {
					CFrame = CFrame.new(
						Vector3.new(center.X + (math.random() - 0.5) * 3, base.Y, center.Z + (math.random() - 0.5) * 3)
					),
					Transparency = 1,
				}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end
		EFFECTS.GoldDust(base + Vector3.new(0, 2, 0), nil, scale)
	end)
end

-- Emotes -------------------------------------------------------------------------------------------

EFFECTS.MakeItRain = function(position, _colors, scale)
	emoji(position + Vector3.new(0, 1, 0), { "💸", "💵", "💰" }, math.max(3, math.floor(12 * scale)))
	for _ = 1, math.max(2, math.floor(8 * scale)) do
		local angle = math.random() * 2 * math.pi
		local landing = position + Vector3.new(math.cos(angle) * 4, -4.5, math.sin(angle) * 4)
		local peak = position + Vector3.new(math.cos(angle) * 2, 5 + math.random() * 2, math.sin(angle) * 2)
		coin(position + Vector3.new(0, 1, 0), peak, 0.4)
		coin(peak, landing, 0.6, 0.4)
	end
end

EFFECTS.HeartOfGold = function(position, _colors, scale)
	emoji(position, { "💛", "💛", "✨" }, math.max(3, math.floor(9 * scale)))
	sparkles(position, GOLD_LIGHT, math.floor(18 * scale), 6)
end

EFFECTS.DiamondDrop = function(position, _colors, scale)
	emoji(position, { "💎", "💠" }, math.max(3, math.floor(10 * scale)), true)
	sparkles(position + Vector3.new(0, 4, 0), DIAMOND, math.floor(20 * scale), 5)
end

EFFECTS.GoldenAura = function(position, _colors, scale)
	local feet = position - Vector3.new(0, 4.6, 0)
	for ring = 1, 3 do
		task.delay((ring - 1) * 0.45, function()
			local halo = piece({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.12, 7, 7),
				Color = if ring == 2 then WHITE_GOLD else GOLD,
				Material = Enum.Material.Neon,
				Transparency = 0.45,
				CFrame = CFrame.new(feet) * CFrame.Angles(0, 0, math.rad(90)),
			}, 1.6)
			tween(halo, 1.3, {
				CFrame = CFrame.new(feet + Vector3.new(0, 6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Size = Vector3.new(0.12, 3, 3),
				Transparency = 1,
			}, Enum.EasingStyle.Sine)
		end)
	end
	-- Sparks spiralling up round the dancer.
	local holder = anchor(feet, 4)
	burst(holder, {
		Color = ColorSequence.new(GOLD_LIGHT),
		LightEmission = 1,
		Size = NumberSequence.new(0.6, 0),
		Lifetime = NumberRange.new(1.5, 2.4),
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, 4, 0),
		RotSpeed = NumberRange.new(-180, 180),
		EmissionDirection = Enum.NormalId.Top,
	}, math.floor(40 * scale))
	light(position, GOLD, 2, 16, 2.6)
end

-- The effect called `name`, if it's one of these.
function GoldEffects.Get(name: string): Effect?
	return EFFECTS[name]
end

GoldEffects.Names = {} :: { string }
for name in EFFECTS do
	table.insert(GoldEffects.Names, name)
end
table.sort(GoldEffects.Names)

return GoldEffects

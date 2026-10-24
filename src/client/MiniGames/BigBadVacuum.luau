-- Client half of Big Bad Vacuum (server: src/server/MiniGames/BigBadVacuum.luau, rules: Shared/Logic/BigBadVacuum).
-- The owner asked for this game to "feel super sick and epic", so almost all of the show is here. The server
-- owns the fight; this draws it from what it shares, and sends THROW (E), BAG (Q) and PANIC (F):
--
--   * The BOSS is a shared snapshot (position, heading, velocity, state) that this dead-reckons and smooths,
--     and a rig made from the props' parts (found by name): its eye follows people (and swirls when it is dizzy),
--     the stripe round it glows with its phase, the hatch on top slides open onto the core (with a beacon, so
--     the whole lobby can see where to throw), the side brushes spin, the vents glow. Its brush arm swings,
--     its dust bag fills, its cord whips and slams a plug. It drops from the ceiling to start (a growing
--     warning on the floor), and falls apart in a chain of explosions when it is beaten.
--   * The DANGER ZONES the server judges are drawn the moment they are known: wedges and discs on the floor that
--     fill up until the hit (the same Rules.ZoneContains the server and the bots use), plus a red "MOVE!" edge
--     on your own screen when you stand in one, and a JUMP! cue for the shockwave ring.
--   * Bricks float over the head of whoever holds one; thrown bricks arc (this player's is drawn the instant
--     they press, then adopts the server's timing); hits make floating numbers, VOLLEY! callouts and sparks.
--   * The CAMERA gets a flyover during the 3-2-1 (everyone is frozen then), shakes and punches on impacts, and
--     takes over for the finale. Big banners call out every attack, phase, rescue and the PANIC BLAST.
--
-- The suction's pull is applied here to this player's own character (smooth, like a conveyor), by the same
-- Rules the server uses to judge who ends up in the bag. Everything made here goes in api.World or through
-- api:Track, so it all goes with the round.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Rules = require(ReplicatedStorage.Shared.Logic.BigBadVacuum)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local BigBadVacuum = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SOUND_BOOM = "rbxasset://sounds/impact_water.mp3"
local SOUND_WHOOSH = "rbxasset://sounds/swoosh.wav"
local SOUND_PING = "rbxasset://sounds/electronicpingshort.wav"
local SOUND_CLICK = "rbxasset://sounds/clickfast.wav"
local SOUND_HIT = "rbxasset://sounds/swordlunge.wav"

local DANGER = Color3.fromRGB(255, 62, 72)
local WIND = Color3.fromRGB(120, 200, 255)
local HOT = Color3.fromRGB(255, 150, 50)
local GOLD = Color3.fromRGB(255, 214, 70)
local CYAN = Color3.fromRGB(80, 255, 230)
local WHITE = Color3.new(1, 1, 1)
local PHASE_COLORS = { Color3.fromRGB(60, 220, 255), Color3.fromRGB(255, 170, 50), Color3.fromRGB(255, 60, 110) }
local EYE_DARK = Color3.fromRGB(34, 32, 44)
local LAND_AT = 3.6 -- seconds after GO the boss hits the floor (the server's LAND_AT)

local function clamp01(v: number): number
	return math.clamp(v, 0, 1)
end

local function smooth(v: number): number
	local t = clamp01(v)
	return t * t * (3 - 2 * t)
end

local function rootOf(model: Model?): BasePart?
	return if model then model:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function dir(angle: number): Vector3
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

-- A floor-level translucent glowing part.
local function newPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.Neon
	local parent = nil
	for key, value in props do
		if key == "Parent" then
			parent = value
		else
			(part :: any)[key] = value
		end
	end
	part.Parent = parent
	return part
end

local function newWedge(parent: Instance, color: Color3): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Anchored = true
	wedge.CanCollide = false
	wedge.CanQuery = false
	wedge.CanTouch = false
	wedge.CastShadow = false
	wedge.Material = Enum.Material.Neon
	wedge.Color = color
	wedge.Size = Vector3.new(0.12, 0.1, 0.1)
	wedge.Parent = parent
	return wedge
end

-- Lays two thin wedges over the triangle a-b-c (the usual way to draw a flat triangle in 3D).
local function setTriangle(w1: WedgePart, w2: WedgePart, a: Vector3, b: Vector3, c: Vector3)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-4 or bc.Magnitude < 1e-4 then
		w1.Size = Vector3.new(0.12, 0.05, 0.05)
		w2.Size = Vector3.new(0.12, 0.05, 0.05)
		return
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	w1.Size = Vector3.new(0.12, math.max(height, 0.05), math.max(math.abs(ab:Dot(back)), 0.05))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	w2.Size = Vector3.new(0.12, math.max(height, 0.05), math.max(math.abs(ac:Dot(back)), 0.05))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
end

function BigBadVacuum.Start(api)
	local localPlayer = Players.LocalPlayer
	local me = localPlayer.UserId
	local camera = workspace.CurrentCamera
	local touch = api:IsTouch()
	local world = api.World

	-- A night in the living room.
	api:Mood({
		Tint = Color3.fromRGB(178, 186, 238),
		Saturation = 0.1,
		Contrast = 0.1,
		Brightness = -0.08,
		Haze = Color3.fromRGB(58, 52, 104),
		HazeDecay = Color3.fromRGB(30, 26, 64),
		Density = 0.3,
	})

	-- The shared state ------------------------------------------------------------------------------------------
	local arena = api:SharedJSON("Arena") or {}
	local radius: number = arena.R or 58
	local floorY: number = arena.Y or 0
	local centerX: number = arena.X or 0
	local centerZ: number = arena.Z or 0
	api:OnShared("Arena", function()
		local fresh = api:SharedJSON("Arena")
		if type(fresh) == "table" then
			radius, floorY, centerX, centerZ =
				fresh.R or radius, fresh.Y or floorY, fresh.X or centerX, fresh.Z or centerZ
		end
	end)
	local boss: any = api:SharedJSON("Boss")
	local atk: any = api:SharedJSON("Atk") or { K = "" }
	local pileList: { any } = api:SharedJSON("Piles") or {}
	local carryList: { number } = api:SharedJSON("Carry") or {}
	local trapList: { any } = api:SharedJSON("Trap") or {}
	local meter: any = api:SharedJSON("Meter") or { V = 0, R = false }
	local lastAtk: any = nil -- the attack that has just ended (the arm and cord finish their moves)

	local function now(): number
		return api:Now()
	end

	local carrying: { [number]: boolean } = {}
	local function readCarry()
		local value = api:SharedJSON("Carry")
		carryList = if type(value) == "table" then value else {}
		carrying = {}
		for _, id in carryList do
			carrying[id] = true
		end
	end
	local trapped: { [number]: any } = {}
	local function readTraps()
		local value = api:SharedJSON("Trap")
		trapList = if type(value) == "table" then value else {}
		trapped = {}
		for _, entry in trapList do
			trapped[entry.U] = entry
		end
	end
	readCarry()
	readTraps()
	api:OnShared("Boss", function()
		local value = api:SharedJSON("Boss")
		if type(value) == "table" then
			boss = value
		end
	end)
	api:OnShared("Atk", function()
		local value = api:SharedJSON("Atk")
		if type(value) ~= "table" then
			return
		end
		if (atk.K or "") ~= "" and (value.K or "") == "" then
			lastAtk = atk
		end
		atk = value
	end)
	api:OnShared("Piles", function()
		local value = api:SharedJSON("Piles")
		pileList = if type(value) == "table" then value else {}
	end)
	api:OnShared("Carry", readCarry)
	api:OnShared("Trap", readTraps)
	api:OnShared("Meter", function()
		local value = api:SharedJSON("Meter")
		if type(value) == "table" then
			meter = value
		end
	end)

	local function myRoot(): BasePart?
		return rootOf(api:CharacterOf(me))
	end
	local function inRound(): boolean
		return State.Phase() == "InRound" and api:CanAct()
	end

	-- Little tools ---------------------------------------------------------------------------------------------------
	local function anchorAt(position: Vector3, lifetime: number): Part
		local part = newPart({
			Transparency = 1,
			Size = Vector3.one,
			CFrame = CFrame.new(position),
			Parent = world,
		})
		Debris:AddItem(part, lifetime)
		return part
	end

	local function emit(parent: Instance, props: { [string]: any }, count: number)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		for key, value in props do
			(emitter :: any)[key] = value
		end
		emitter.Parent = parent
		emitter:Emit(math.max(1, math.floor(count * (if State.ReducedEffects() then 0.35 else 1))))
	end

	-- (The round harness's stand-in client is not a real Player and has no sound files to load.)
	local hasSound = typeof(localPlayer) == "Instance"
	local function playAt(id: string, position: Vector3, volume: number, speed: number)
		if not hasSound then
			return
		end
		local holder = anchorAt(position, 4)
		local sound = Instance.new("Sound")
		sound.SoundId = id
		sound.Volume = volume
		sound.PlaybackSpeed = speed
		sound.RollOffMinDistance = 40
		sound.RollOffMaxDistance = 320
		sound.Parent = holder
		sound:Play()
	end

	-- Dust and sparks at a point.
	local function dust(position: Vector3, size: number, count: number, color: Color3?)
		local holder = anchorAt(position, 3)
		emit(holder, {
			Texture = SMOKE,
			Color = ColorSequence.new(color or Color3.fromRGB(214, 200, 190)),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, size * 0.4),
				NumberSequenceKeypoint.new(1, size),
			}),
			Transparency = NumberSequence.new(0.25, 1),
			Lifetime = NumberRange.new(0.9, 1.7),
			Speed = NumberRange.new(8, 22),
			SpreadAngle = Vector2.new(180, 60),
			Drag = 3,
			EmissionDirection = Enum.NormalId.Top,
		}, count)
	end
	local function sparks(position: Vector3, count: number, color: Color3?, speed: number?)
		local holder = anchorAt(position, 2.5)
		emit(holder, {
			Texture = SPARKLE,
			Color = ColorSequence.new(color or GOLD),
			LightEmission = 1,
			Size = NumberSequence.new(1.4, 0),
			Lifetime = NumberRange.new(0.5, 1.2),
			Speed = NumberRange.new((speed or 24) * 0.5, speed or 24),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -40, 0),
			Drag = 1,
		}, count)
	end

	-- A glowing ball that swells and fades (explosions, flashes), with a light.
	local function fireball(position: Vector3, size: number, color: Color3, time: number)
		local ball = newPart({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size * 0.2,
			CFrame = CFrame.new(position),
			Color = color,
			Transparency = 0.1,
			Parent = world,
		})
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = size * 2.4
		light.Brightness = 4
		light.Shadows = false
		light.Parent = ball
		UIKit.Tween(ball, time, { Size = Vector3.one * size, Transparency = 1 }, Enum.EasingStyle.Quad)
		UIKit.Tween(light, time, { Brightness = 0 })
		Debris:AddItem(ball, time + 0.1)
	end

	-- A floating number or word that rises and fades.
	local function floatText(position: Vector3, text: string, color: Color3, size: number, rise: number?)
		local holder = anchorAt(position, 2.2)
		local gui = UIKit.new("BillboardGui", {
			Size = UDim2.fromOffset(size * 4, size * 1.3),
			StudsOffset = Vector3.new(0, 0, 0),
			AlwaysOnTop = true,
			LightInfluence = 0,
			MaxDistance = 260,
			Adornee = holder,
			Parent = holder,
		})
		local label = UIKit.Label({
			Text = text,
			Font = Theme.Fonts.Display,
			TextScaled = true,
			TextColor3 = color,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0) },
		})
		UIKit.PopIn(label, 0.25)
		UIKit.Tween(gui, 1.6, { StudsOffset = Vector3.new(0, rise or 7, 0) }, Enum.EasingStyle.Quad)
		task.delay(0.9, function()
			if label.Parent then
				UIKit.Tween(label, 0.7, { TextTransparency = 1 })
				local stroke = label:FindFirstChildOfClass("UIStroke")
				if stroke then
					UIKit.Tween(stroke, 0.7, { Transparency = 1 })
				end
			end
		end)
	end

	-- Camera shake and FOV punch (applied after Roblox's own camera moves, below).
	local shakeAmount = 0
	local punch = 0
	local function shake(amount: number, at: Vector3?)
		if State.ReducedEffects() then
			amount *= 0.3
		end
		if at then
			local root = myRoot()
			if root then
				local away = (root.Position - at).Magnitude
				amount *= math.clamp(1.15 - away / 170, 0.15, 1)
			end
		end
		shakeAmount = math.max(shakeAmount, amount)
	end
	local function punchFov(amount: number)
		if not State.ReducedEffects() then
			punch = math.max(punch, amount)
		end
	end

	-- Templates -------------------------------------------------------------------------------------------------------
	local bodyModel: Model? = nil
	local bagModel: Model? = nil
	local armModel: Model? = nil
	local plugModel: Model? = nil
	local linkTemplate: Instance? = nil
	local brickTemplate: Instance? = nil
	local debrisTemplate: Instance? = nil
	task.spawn(function()
		bodyModel = api:Template("BigBadVacuumBody", 12) :: Model?
		armModel = api:Template("BigBadVacuumBrush", 12) :: Model?
		bagModel = api:Template("BigBadVacuumBag", 12) :: Model?
		plugModel = api:Template("BigBadVacuumPlug", 12) :: Model?
		linkTemplate = api:Template("BigBadVacuumCordLink", 12)
		brickTemplate = api:Template("BigBadVacuumBrick", 12)
		debrisTemplate = api:Template("BigBadVacuumDebris", 12)
	end)

	local function prepare(model: Instance, castShadow: boolean)
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = castShadow and part.Size.Magnitude > 4
			end
		end
	end

	-- The boss's rig ------------------------------------------------------------------------------------------------------
	type Entry = { Part: BasePart, Rel: CFrame }
	local rig: { [string]: { Entry } } = {}
	local sideL: { Entry } = {}
	local sideR: { Entry } = {}
	local armParts: { [string]: { Entry } } = {}
	local eyeLight: PointLight? = nil
	local coreLight: PointLight? = nil
	local sirenLight: PointLight? = nil
	local beam: Part? = nil
	local beamRing: Part? = nil
	local beamGui: BillboardGui? = nil
	local bossBuilt = false

	-- The rig's parts of one name (none: an empty list).
	local function group(name: string): { Entry }
		return rig[name] or {}
	end
	local function armGroup(name: string): { Entry }
		return armParts[name] or {}
	end

	local function indexParts(model: Model, into: { [string]: { Entry } }): { Entry }
		local pivot = model:GetPivot()
		local all = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				local entry = { Part = part, Rel = pivot:ToObjectSpace(part.CFrame) }
				table.insert(all, entry)
				into[part.Name] = into[part.Name] or {}
				table.insert(into[part.Name], entry)
			end
		end
		return all
	end

	local function buildBoss()
		if bossBuilt or not bodyModel then
			return
		end
		bossBuilt = true
		local body = bodyModel :: Model
		prepare(body, true)
		indexParts(body, rig)
		body.Parent = world
		for _, entry in group("SideBrushL") do
			table.insert(sideL, entry)
		end
		for _, entry in group("SideBrushR") do
			table.insert(sideR, entry)
		end
		for _, entry in group("BristlesL") do -- (the mesh's; the Fallback's are all "Bristles")
			table.insert(sideL, entry)
		end
		for _, entry in group("BristlesR") do
			table.insert(sideR, entry)
		end
		for _, entry in group("Bristles") do
			if math.abs(entry.Rel.Position.X) > 8 then
				table.insert(if entry.Rel.Position.X < 0 then sideL else sideR, entry)
			end
		end
		local eye = rig.Eye and rig.Eye[1].Part
		if eye then
			eyeLight =
				UIKit.new("PointLight", { Color = DANGER, Range = 34, Brightness = 0, Shadows = false, Parent = eye })
		end
		local orb = rig.Orb and rig.Orb[1].Part
		if orb then
			coreLight =
				UIKit.new("PointLight", { Color = CYAN, Range = 46, Brightness = 0, Shadows = false, Parent = orb })
		end
		local siren = rig.Siren and rig.Siren[1].Part
		if siren then
			sirenLight =
				UIKit.new("PointLight", { Color = DANGER, Range = 40, Brightness = 2, Shadows = false, Parent = siren })
		end
		-- The core's beacon: a tall beam and a ring, there so everyone sees where to throw.
		beam = newPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(80, 3.4, 3.4),
			Color = CYAN,
			Transparency = 1,
			Parent = world,
		})
		beamRing = newPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 12, 12),
			Color = CYAN,
			Transparency = 1,
			Parent = world,
		})
		local gui = UIKit.new("BillboardGui", {
			Size = UDim2.fromOffset(220, 70),
			StudsOffset = Vector3.new(0, 7, 0),
			AlwaysOnTop = true,
			LightInfluence = 0,
			MaxDistance = 400,
			Enabled = false,
			Adornee = beamRing,
			Parent = beamRing,
		})
		UIKit.Label({
			Text = "▼ HIT THE CORE! ▼",
			Font = Theme.Fonts.Display,
			TextScaled = true,
			TextColor3 = CYAN,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0) },
		})
		beamGui = gui
	end

	-- The arm's rig, the first time it's drawn (its template can arrive after the body's).
	local armReady = false
	local function readyArm(model: Model)
		if not armReady then
			armReady = true
			prepare(model, true)
			model.Parent = nil
			indexParts(model, armParts)
		end
	end

	-- Where the boss is drawn, smoothed from the shared snapshots.
	local shown = { X = 0, Z = 0, F = math.pi / 2, Ready = false, Height = 0 }
	local function bagCenter(): Vector3
		return Vector3.new(
			shown.X - math.cos(shown.F) * Rules.BAG_BACK,
			floorY + Rules.BAG_HEIGHT,
			shown.Z - math.sin(shown.F) * Rules.BAG_BACK
		)
	end
	local function coreAt(): Vector3
		return Vector3.new(shown.X, floorY + Rules.CORE_HEIGHT + shown.Height, shown.Z)
	end

	local function goTime(): number
		return if boss and boss.G and boss.G > 0 then boss.G else now()
	end

	local function updatePose(t: number, dt: number)
		if not boss then
			return
		end
		local age = math.clamp(t - boss.T, 0, 0.35)
		local tx, tz, tf = boss.X + boss.VX * age, boss.Z + boss.VZ * age, boss.F + boss.W * age
		local exact = false
		local zone = atk.Z and atk.Z[1]
		if boss.S == "Act" then
			if atk.K == "Charge" and zone and atk.Ex then
				-- The charge is a straight run on a known line: draw it exactly.
				local dx, dz = Rules.Dir(atk.F or 0)
				local distance = Rules.Distance(zone.X, zone.Z, atk.Ex, atk.Ez)
				local travelled = math.min(Rules.Attacks.Charge.Speed * math.max(t - atk.T1, 0), distance)
				tx, tz, tf = zone.X + dx * travelled, zone.Z + dz * travelled, atk.F or tf
				exact = true
			elseif atk.K == "Whirl" and atk.B then
				local f = clamp01((t - atk.T1) / math.max(atk.T2 - atk.T1, 0.05))
				tf = Rules.WhirlAngle(atk.B, f)
				exact = true
			end
		end
		if not shown.Ready then
			shown.X, shown.Z, shown.F, shown.Ready = tx, tz, tf, true
		else
			local k = 1 - math.exp(-(if exact then 40 else 14) * dt)
			shown.X += (tx - shown.X) * k
			shown.Z += (tz - shown.Z) * k
			shown.F += Rules.Turn(shown.F, tf) * k
		end
	end

	-- The intro: the boss hangs high over the middle until it falls at LAND_AT.
	local function introHeight(t: number): number
		local since = t - goTime()
		if boss and boss.S == "Intro" and since < LAND_AT then
			local p = clamp01(since / LAND_AT)
			return 150 * (1 - p * p)
		end
		if since >= LAND_AT and since < LAND_AT + 1.3 then
			local bounce = since - LAND_AT
			return 2.6 * math.exp(-5.5 * bounce) * math.abs(math.cos(10 * bounce))
		end
		return 0
	end

	local eyeColor = EYE_DARK
	local irisColor = EYE_DARK
	local stripeColor = PHASE_COLORS[1]
	local flapOpen = 0
	local sideSpin = 0
	local lastLanded = false
	local function stateColors(t: number): (Color3, Color3, Color3)
		local state = boss and boss.S or "Intro"
		local phase = boss and boss.P or 1
		local blink = 0.5 + 0.5 * math.sin(t * 22)
		local eye, iris = Color3.fromRGB(255, 70, 60), Color3.fromRGB(255, 190, 80)
		local stripe = PHASE_COLORS[math.clamp(phase, 1, 3)]
		if state == "Intro" then
			if lastLanded then
				eye = Color3.fromRGB(255, 70, 60)
			else
				eye, iris = EYE_DARK, EYE_DARK
			end
		elseif state == "Wind" then
			eye = Color3.fromRGB(255, 70, 60):Lerp(Color3.fromRGB(255, 240, 120), blink)
			iris = Color3.fromRGB(255, 120, 60)
		elseif state == "Act" then
			eye, iris = Color3.fromRGB(255, 244, 230), Color3.fromRGB(255, 90, 60)
		elseif state == "Stun" then
			eye, iris = Color3.fromRGB(150, 100, 255), Color3.fromRGB(90, 200, 255)
			stripe = Color3.fromRGB(110, 90, 200)
		elseif state == "Break" then
			eye = WHITE:Lerp(Color3.fromRGB(255, 120, 120), blink)
			iris = WHITE
			stripe = WHITE
		elseif state == "Dying" then
			local flicker = math.random() < 0.35
			eye = if flicker then WHITE else EYE_DARK
			iris = if flicker then Color3.fromRGB(255, 120, 60) else EYE_DARK
			stripe = if flicker then WHITE else EYE_DARK
		elseif state == "Done" then
			eye, iris = Color3.fromRGB(255, 40, 40), Color3.fromRGB(255, 200, 60)
		end
		return eye, iris, stripe
	end

	local function drawBoss(t: number, dt: number)
		if not bossBuilt or not boss or not shown.Ready then
			return
		end
		local model = bodyModel :: Model
		local state = boss.S
		shown.Height = introHeight(t)
		local coreOpen = state ~= "Break" and state ~= "Dying" and t < (boss.C or 0)
		if (shown.Height < 1 and boss.S ~= "Intro") or (state == "Intro" and t - goTime() >= LAND_AT) then
			lastLanded = true
		end

		-- The body: heading, hover, shake (a stun rattles it, dying shudders it hard).
		local position = Vector3.new(shown.X, floorY + shown.Height, shown.Z)
		if state == "Chase" or state == "Wind" or state == "Recover" then
			position += Vector3.new(0, 0.28 + 0.28 * math.sin(t * 3.2), 0) -- (it hovers and idles)
		end
		local rattle = 0
		if state == "Stun" then
			rattle = 0.18
		elseif state == "Dying" then
			rattle = 0.7 + 0.5 * clamp01((t - (boss.Q and goTime() or t)) / 3)
		elseif state == "Break" then
			rattle = 0.3
		elseif state == "Done" then
			position += Vector3.new(0, 0.9 * math.abs(math.sin(t * 5.5)), 0) -- (it laughs)
		end
		if rattle > 0 and not State.ReducedEffects() then
			position += Vector3.new(
				(math.random() - 0.5) * rattle * 2,
				(math.random() - 0.5) * rattle,
				(math.random() - 0.5) * rattle * 2
			)
		end
		local look = dir(shown.F)
		local base = CFrame.lookAt(position, position + look)
		model:PivotTo(base)

		-- The eye: follows the nearest person, swirls when it is dizzy.
		local target = myRoot()
		local ox, oy = 0, 0
		if state == "Stun" then
			ox, oy = math.cos(t * 9) * 1.1, math.sin(t * 9) * 1.0
		elseif target and state ~= "Intro" and state ~= "Dying" then
			local rel = base:PointToObjectSpace(target.Position)
			local flat = Vector2.new(rel.X, -rel.Z)
			if flat.Magnitude > 0.1 then
				local unit = flat.Unit
				ox = unit.X * 1.1
				oy = math.clamp((target.Position.Y - position.Y) * 0.04, -0.4, 0.6)
			end
		end
		local k = 1 - math.exp(-12 * dt)
		local eyeTarget, irisTarget, stripeTarget = stateColors(t)
		eyeColor = eyeColor:Lerp(eyeTarget, k)
		irisColor = irisColor:Lerp(irisTarget, k)
		stripeColor = stripeColor:Lerp(stripeTarget, k)
		for _, entry in group("Eye") do
			entry.Part.Color = eyeColor
		end
		for _, entry in group("Iris") do
			entry.Part.Color = irisColor
			entry.Part.CFrame = base * CFrame.new(ox * 0.55, oy * 0.5, 0) * entry.Rel
		end
		for _, entry in group("Pupil") do
			entry.Part.CFrame = base * CFrame.new(ox, oy, 0) * entry.Rel
		end
		for _, entry in group("Stripe") do
			entry.Part.Color = stripeColor
		end
		-- Angry brows slam down when it attacks.
		local brow = if state == "Wind" or state == "Act" then -0.35 elseif state == "Stun" then 0.3 else 0
		for _, name in { "BrowL", "BrowR" } do
			for _, entry in group(name) do
				entry.Part.CFrame = base * CFrame.new(0, brow, 0) * entry.Rel
			end
		end

		-- The hatch: slides open onto the core.
		flapOpen += ((if coreOpen then 1 else 0) - flapOpen) * (1 - math.exp(-14 * dt))
		for _, entry in group("FlapL") do
			entry.Part.CFrame = base * CFrame.new(-4.2 * flapOpen, 0, 0) * entry.Rel
		end
		for _, entry in group("FlapR") do
			entry.Part.CFrame = base * CFrame.new(4.2 * flapOpen, 0, 0) * entry.Rel
		end
		local pulse = 0.5 + 0.5 * math.sin(t * 10)
		for _, entry in group("Orb") do
			entry.Part.Color = if coreOpen then CYAN:Lerp(WHITE, pulse * 0.6) else Color3.fromRGB(24, 60, 66)
			entry.Part.Size = Vector3.one * (4.2 + (if coreOpen then 0.9 * pulse else 0))
		end
		if coreLight then
			coreLight.Brightness = if coreOpen then 2.5 + 3 * pulse else 0
		end
		if eyeLight then
			eyeLight.Color = eyeColor
			eyeLight.Brightness = if state == "Intro" and not lastLanded
				then 0
				else 1.6 + (if state == "Act" then 2 else 0)
		end
		if sirenLight then
			sirenLight.Brightness = if state == "Wind" or state == "Act"
				then 2 + 5 * (0.5 + 0.5 * math.sin(t * 18))
				else 1.2
		end
		for _, entry in group("Siren") do
			entry.Part.Color = if state == "Wind" and math.sin(t * 18) > 0 then WHITE else DANGER
		end
		-- Vents glow hotter in later phases and when it overheats.
		local heat = if state == "Stun" then 1 else 0.35 + 0.2 * (boss.P or 1)
		for _, entry in group("VentGlow") do
			entry.Part.Color = Color3.fromRGB(255, 70, 30)
				:Lerp(Color3.fromRGB(255, 220, 90), clamp01(heat * (0.6 + 0.4 * pulse)))
		end

		-- The side brushes spin; faster the faster it moves.
		local speed = math.sqrt(boss.VX * boss.VX + boss.VZ * boss.VZ)
		sideSpin += dt * (6 + speed * 0.5 + (if state == "Act" then 10 else 0))
		local function spin(list: { Entry }, sign: number)
			for _, entry in list do
				local c = entry.Rel.Position
				local about = CFrame.new(c.X, 0, c.Z) * CFrame.Angles(0, sideSpin * sign, 0) * CFrame.new(-c.X, 0, -c.Z)
				entry.Part.CFrame = base * about * entry.Rel
			end
		end
		spin(sideL, 1)
		spin(sideR, -1)

		-- The beacon over the core.
		if beam and beamRing and beamGui then
			local core = coreAt()
			beam.CFrame = CFrame.new(core.X, core.Y + 42, core.Z) * CFrame.Angles(0, 0, math.rad(90))
			beamRing.CFrame = CFrame.new(core.X, core.Y + 0.2 + 2 * pulse, core.Z) * CFrame.Angles(0, 0, math.rad(90))
			beam.Transparency = if coreOpen then 0.55 + 0.25 * pulse else 1
			beamRing.Transparency = if coreOpen then 0.4 + 0.3 * pulse else 1
			beamRing.Size = Vector3.new(0.4, 10 + 6 * pulse, 10 + 6 * pulse)
			beamGui.Enabled = coreOpen
		end
	end

	-- Vent smoke and sparks while it is hot, a steam leak when stunned.
	local nextSmoke = 0
	local function ambientBoss(t: number)
		if not boss or not shown.Ready or t < nextSmoke or State.ReducedEffects() then
			return
		end
		local state = boss.S
		if state == "Stun" then
			nextSmoke = t + 0.22
			local at = Vector3.new(shown.X, floorY + 13 + shown.Height, shown.Z) + dir(shown.F + math.pi) * 5
			dust(at, 7, 3, Color3.fromRGB(180, 180, 200))
			sparks(at, 4, HOT, 16)
		elseif state == "Dying" then
			nextSmoke = t + 0.1
			local angle = math.random() * math.pi * 2
			local at = Vector3.new(shown.X, floorY + 6 + math.random() * 9, shown.Z)
				+ dir(angle) * (4 + math.random() * 8)
			sparks(at, 8, if math.random() < 0.5 then HOT else WHITE, 30)
			dust(at, 8, 2, Color3.fromRGB(60, 56, 64))
		elseif state == "Act" and atk.K == "Charge" then
			nextSmoke = t + 0.05
			dust(Vector3.new(shown.X, floorY + 1, shown.Z) - dir(shown.F) * 10, 9, 3)
		elseif math.abs(boss.VX) + math.abs(boss.VZ) > 3 and state ~= "Intro" then
			nextSmoke = t + 0.22
			dust(Vector3.new(shown.X, floorY + 0.8, shown.Z) - dir(shown.F) * 11, 4, 2, Color3.fromRGB(190, 176, 168))
		elseif (boss.P or 1) >= 3 and state ~= "Intro" then
			nextSmoke = t + 0.4
			dust(
				Vector3.new(shown.X, floorY + 12, shown.Z) + dir(shown.F + math.pi) * 6,
				4,
				1,
				Color3.fromRGB(70, 66, 74)
			)
		end
	end

	-- The brush arm ------------------------------------------------------------------------------------------------------
	local armSpin = 0
	local function drawArm(t: number, dt: number)
		local model = armModel
		if not model or not boss or not shown.Ready then
			return
		end
		readyArm(model)
		local plan = atk
		local ending = false
		if (plan.K or "") == "" then
			plan = lastAtk
			ending = true
		end
		if not plan or (plan.K ~= "Sweep" and plan.K ~= "Whirl") then
			model.Parent = nil
			return
		end
		local extension, angle
		local span = math.max(plan.T2 - plan.T1, 0.05)
		if plan.K == "Sweep" then
			local f = clamp01((t - plan.T1) / span)
			angle = Rules.SweepAngle(plan.F or 0, f)
			if t < plan.T1 then
				extension = smooth((t - plan.T0) / 0.5)
				angle += math.sin(t * 14) * 0.03 -- (it quivers, winding up)
			else
				extension = 1
			end
		else
			angle = Rules.WhirlAngle(plan.B or 0, clamp01((t - plan.T1) / span))
			extension = if t < plan.T1 then smooth((t - plan.T0) / 0.9) else 1
		end
		if t > plan.T2 then
			extension *= 1 - smooth((t - plan.T2) / 0.45)
		end
		if extension < 0.04 or (ending and t > plan.T2 + 0.5) then
			model.Parent = nil
			return
		end
		model.Parent = world
		armSpin += dt * 22
		local origin = Vector3.new(shown.X, floorY + 0.2 + shown.Height, shown.Z)
		local armCF = CFrame.lookAt(origin, origin + dir(angle))
		local function place(name: string, fn: (entry: Entry) -> CFrame)
			for _, entry in armGroup(name) do
				entry.Part.CFrame = fn(entry)
			end
		end
		place("Hub", function(entry)
			return armCF * entry.Rel
		end)
		place("Boom", function(entry)
			entry.Part.Size = Vector3.new(3, 1.8, math.max(21 * extension, 0.2))
			return armCF * CFrame.new(0, entry.Rel.Position.Y, -(6 + 10.5 * extension))
		end)
		place("BoomTop", function(entry)
			entry.Part.Size = Vector3.new(1.6, 0.5, math.max(19 * extension, 0.2))
			return armCF * CFrame.new(0, entry.Rel.Position.Y, -(6 + 10.5 * extension))
		end)
		local shift = CFrame.new(0, 0, 21 - 21 * extension)
		local function tip(entry: Entry)
			local c = entry.Rel.Position
			local about = CFrame.new(c.X, 0, c.Z) * CFrame.Angles(0, armSpin, 0) * CFrame.new(-c.X, 0, -c.Z)
			return armCF * shift * about * entry.Rel
		end
		place("Head", tip)
		place("Bristles", tip)
	end

	-- The dust bag --------------------------------------------------------------------------------------------------------
	local bagGui: BillboardGui? = nil
	local bagReady = false -- (set up once: its parent goes back to nil every frame until the boss lands)
	local bagGone = false -- blown up with the boss at the finale
	local bagLabel: TextLabel? = nil
	local bagScale = 1
	local function drawBag(t: number, dt: number)
		local model = bagModel
		if not model or not boss or not shown.Ready or bagGone then
			return
		end
		if not bagReady then
			bagReady = true
			prepare(model, false)
			model.Parent = world
			bagGui = UIKit.new("BillboardGui", {
				Size = UDim2.fromOffset(300, 70),
				StudsOffset = Vector3.new(0, 11, 0),
				AlwaysOnTop = true,
				LightInfluence = 0,
				MaxDistance = 400,
				Enabled = false,
				Adornee = model.PrimaryPart,
				Parent = model.PrimaryPart,
			})
			bagLabel = UIKit.Label({
				Text = "",
				Font = Theme.Fonts.Display,
				TextScaled = true,
				TextColor3 = CYAN,
				Size = UDim2.fromScale(1, 1),
				Parent = bagGui,
				Children = { UIKit.TextStroke(0) },
			})
		end
		local count = #trapList
		local fill = clamp01(count / math.max(Rules.BagCapacity(arena.N or 8), 1))
		local target = 1 + 0.06 * count
		bagScale += (target - bagScale) * (1 - math.exp(-8 * dt))
		local center = bagCenter()
		local sway = Vector3.new(math.sin(t * 2.3) * 0.5, math.sin(t * 3.1) * 0.35, math.cos(t * 2.1) * 0.5)
		local alive = boss.S ~= "Dying" or t - goTime() < 0
		model.Parent = if boss.S == "Intro" and not lastLanded then nil else world
		model:PivotTo(
			CFrame.new(center.X, center.Y - 7.3 * bagScale + shown.Height, center.Z) * CFrame.Angles(0, shown.F, 0)
				+ sway
		)
		model:ScaleTo(bagScale)
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "Bag" then
				part.Color = Color3.fromRGB(236, 236, 250):Lerp(Color3.fromRGB(196, 168, 128), fill)
				part.Transparency = 0.62 - 0.12 * fill
			end
		end
		if bagGui and bagLabel then
			bagGui.Enabled = count > 0 and alive
			if count > 0 then
				bagLabel.Text = `IN THE BAG {count}/{Rules.BagCapacity(arena.N or 8)} — THROW A BRICK!`
				bagLabel.TextColor3 = WHITE:Lerp(CYAN, 0.5 + 0.5 * math.sin(t * 9))
			end
		end
	end

	-- The cord and plug ----------------------------------------------------------------------------------------------------
	local LINKS = 16
	local cordFolder = Instance.new("Folder")
	cordFolder.Name = "Cord"
	local cordLinks: { Instance } = {}
	local slamMoment = 0
	local function ensureCord()
		if #cordLinks > 0 or not linkTemplate or not plugModel then
			return
		end
		for index = 1, LINKS do
			local link = linkTemplate:Clone()
			prepare(link, false)
			link.Parent = cordFolder
			cordLinks[index] = link
		end
		prepare(plugModel :: Model, true);
		(plugModel :: Model).Parent = cordFolder
		cordFolder.Parent = nil
	end
	local function drawCord(t: number, dt: number)
		ensureCord()
		if #cordLinks == 0 or not boss or not shown.Ready then
			return
		end
		local plan = atk
		if (plan.K or "") == "" then
			plan = lastAtk
		end
		local zone = plan and plan.K == "Cord" and plan.Z and plan.Z[1] or nil
		if not zone or t > plan.T2 + 0.9 then
			cordFolder.Parent = nil
			return
		end
		cordFolder.Parent = world
		local target = Vector3.new(zone.X, floorY, zone.Z)
		local slammed = t >= plan.T1
		local hover = 30
		local height
		if not slammed then
			local rise = smooth((t - plan.T0) / 0.5)
			height = 4 + (hover - 4) * rise
		else
			local fall = clamp01((t - plan.T1) / 0.09)
			height = hover * (1 - fall * fall) + 1.5
			if t > plan.T2 + 0.35 then
				height += (t - plan.T2 - 0.35) * 60 -- it whips back up
			end
		end
		local plugPos = Vector3.new(target.X, floorY + height, target.Z)
		local socket = Vector3.new(shown.X, floorY + 11 + shown.Height, shown.Z) + dir(shown.F + math.pi) * 9
		local joint = plugPos + Vector3.new(0, 5.2, 0)
		local arch = 18 + 10 * (if slammed then 0 else 1)
		local control = (socket + joint) / 2 + Vector3.new(0, arch, 0)
		local previous = socket
		for index = 1, LINKS do
			local u = index / LINKS
			local point = socket * (1 - u) ^ 2 + control * 2 * u * (1 - u) + joint * u ^ 2
			local link = cordLinks[index] :: Model
			local forward = point - previous
			if forward.Magnitude > 0.01 then
				link:PivotTo(
					CFrame.lookAt(previous:Lerp(point, 0.5) - Vector3.new(0, 1.1, 0), point - Vector3.new(0, 1.1, 0))
						* CFrame.Angles(0, math.rad(90), 0)
				)
			end
			previous = point
		end
		local plug = plugModel :: Model
		plug:PivotTo(CFrame.new(plugPos) * CFrame.Angles(math.rad(180), 0, 0) * CFrame.new(0, -6.5, 0))
		if slammed and slamMoment == 0 then
			slamMoment = t
		end
		if not slammed then
			slamMoment = 0
		end
		local _ = dt
	end

	-- Suction streaks ---------------------------------------------------------------------------------------------------------
	local STREAKS = 26
	local streaks: { { Part: Part, U: number, Angle: number, Reach: number, Life: number } } = {}
	local windSound: Sound? = nil
	local nextStreak = 0
	local function drawSuction(t: number, dt: number)
		local active = (atk.K or "") == "Suction" and t >= atk.T0 and t <= atk.T2 and shown.Ready
		if windSound then
			windSound.Volume = if active and t >= atk.T1 then 0.5 else 0
		end
		if not active then
			for _, streak in streaks do
				streak.Part.Transparency = 1
			end
			return
		end
		local zone = atk.Z and atk.Z[1]
		if not zone then
			return
		end
		if not windSound and hasSound then
			local holder = anchorAt(Vector3.new(shown.X, floorY + 4, shown.Z), 8)
			local sound = Instance.new("Sound")
			sound.SoundId = SOUND_WHOOSH
			sound.Looped = true
			sound.PlaybackSpeed = 0.55
			sound.Volume = 0
			sound.RollOffMinDistance = 40
			sound.RollOffMaxDistance = 300
			sound.Parent = holder
			sound:Play()
			windSound = sound
			Debris:AddItem(holder, 12)
		end
		local face = atk.F or zone.A or 0
		local mx, mz = Rules.MouthAt(zone.X, zone.Z, face)
		local mouth = Vector3.new(mx, floorY + 3.5, mz)
		local arc = zone.Arc or Rules.Attacks.Suction.Arc
		local reach = zone.R or Rules.Attacks.Suction.Reach
		local strong = t >= atk.T1
		if t >= nextStreak and #streaks < STREAKS then
			nextStreak = t + (if strong then 0.02 else 0.06)
			local part = newPart({ Size = Vector3.new(0.5, 0.4, 5), Color = WIND, Transparency = 1, Parent = world })
			table.insert(streaks, {
				Part = part,
				U = 1,
				Angle = face + (math.random() - 0.5) * arc,
				Reach = reach * (0.4 + 0.6 * math.random()),
				Life = 0.45 + math.random() * 0.2,
			})
		end
		for _, streak in streaks do
			streak.U -= dt / streak.Life
			if streak.U <= 0 then
				streak.U = 1
				streak.Angle = face + (math.random() - 0.5) * arc
				streak.Reach = reach * (0.4 + 0.6 * math.random())
			end
			local d = dir(streak.Angle)
			local head = mouth + d * (streak.Reach * streak.U)
			local tail = head + d * 5
			streak.Part.CFrame = CFrame.lookAt((head + tail) / 2, head)
			streak.Part.Transparency = 1 - (if strong then 0.55 else 0.3) * math.sin(streak.U * math.pi)
		end
	end

	-- Danger zones -------------------------------------------------------------------------------------------------------------
	type Marker = { Zone: any, Kind: string, Color: Color3, Update: (t: number) -> boolean, Destroy: () -> () }
	local markers: { Marker } = {}
	local markerId = -1
	local FAN = 10

	local function zoneColor(zone: any, kind: string): Color3
		if kind == "Suction" then
			return WIND
		elseif zone.K == "Whirl" or kind == "Bombs" then
			return HOT
		end
		return DANGER
	end

	local function makeMarker(zone: any, kind: string): Marker
		local color = zoneColor(zone, kind)
		local y = floorY + 0.55
		local parts: { Instance } = {}
		local function add(part: Instance)
			table.insert(parts, part)
			return part
		end
		local marker: any = { Zone = zone, Kind = zone.K, Color = color }
		local function paint(transparencyBase: number, transparencyFill: number, fillColor: Color3)
			marker.Paint = { transparencyBase, transparencyFill, fillColor }
		end
		paint(0.85, 0.5, color)

		if zone.K == "Disc" or zone.K == "Whirl" then
			local baseDisc = add(newPart({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.12, 1, 1),
				Color = color,
				Parent = world,
			})) :: Part
			local fillDisc = add(newPart({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.12, 1, 1),
				Color = color,
				Parent = world,
			})) :: Part
			local rim = add(
				newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 1, 1), Color = WHITE, Parent = world })
			) :: Part
			function marker.Update(t: number): boolean
				local zone = marker.Zone -- (the latest: the cord's circle follows its target)
				local span = math.max(zone.T1 - zone.T0, 0.05)
				local p = clamp01((t - zone.T0) / span)
				local hot = t >= zone.T1
				local fade = if t > zone.T2 then clamp01(1 - (t - zone.T2) / 0.25) else 1
				local x, z = zone.X, zone.Z
				if zone.K == "Whirl" and boss then
					x, z = shown.X, shown.Z
				end
				local r = zone.R
				local cf = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90))
				baseDisc.Size = Vector3.new(0.12, r * 2, r * 2)
				baseDisc.CFrame = cf
				fillDisc.Size = Vector3.new(
					0.12,
					math.max(r * 2 * (if hot then 1 else p), 0.2),
					math.max(r * 2 * (if hot then 1 else p), 0.2)
				)
				fillDisc.CFrame = cf * CFrame.new(0.02, 0, 0)
				rim.Size = Vector3.new(0.1, r * 2 + 0.8, r * 2 + 0.8)
				rim.CFrame = cf * CFrame.new(-0.02, 0, 0)
				local pulse = 0.5 + 0.5 * math.sin(t * (if hot then 40 else 12))
				baseDisc.Transparency = 1 - (1 - 0.82) * fade
				fillDisc.Transparency = 1 - (if hot then 0.9 else 0.45 + 0.1 * pulse) * fade
				fillDisc.Color = if hot then WHITE:Lerp(color, 0.35) else color
				rim.Transparency = 1 - (0.55 + 0.25 * pulse) * fade
				rim.Color = color:Lerp(WHITE, 0.4)
				return t < zone.T2 + 0.3
			end
		elseif zone.K == "Sector" or zone.K == "Cone" then
			local baseTris, fillTris = {}, {}
			for _ = 1, FAN do
				table.insert(baseTris, { newWedge(world, color), newWedge(world, color) })
				table.insert(fillTris, { newWedge(world, color), newWedge(world, color) })
			end
			for _, pair in baseTris do
				add(pair[1])
				add(pair[2])
			end
			for _, pair in fillTris do
				add(pair[1])
				add(pair[2])
			end
			function marker.Update(t: number): boolean
				local zone = marker.Zone
				local span = math.max(zone.T1 - zone.T0, 0.05)
				local p = clamp01((t - zone.T0) / span)
				local hot = t >= zone.T1
				local fade = if t > zone.T2 then clamp01(1 - (t - zone.T2) / 0.25) else 1
				local arc = zone.Arc or math.rad(120)
				local a0 = (zone.A or 0) - arc / 2
				local origin = Vector3.new(zone.X, y, zone.Z)
				if kind == "Suction" and boss and shown.Ready then
					origin = Vector3.new(shown.X, y, shown.Z)
				end
				local fillR = zone.R * (if hot then 1 else (0.15 + 0.85 * p))
				local pulse = 0.5 + 0.5 * math.sin(t * (if hot then 40 else 12))
				for index = 1, FAN do
					local pa = a0 + arc * (index - 1) / FAN
					local pb = a0 + arc * index / FAN
					local pair = baseTris[index]
					setTriangle(pair[1], pair[2], origin, origin + dir(pa) * zone.R, origin + dir(pb) * zone.R)
					local fpair = fillTris[index]
					setTriangle(
						fpair[1],
						fpair[2],
						origin + Vector3.new(0, 0.05, 0),
						origin + dir(pa) * fillR + Vector3.new(0, 0.05, 0),
						origin + dir(pb) * fillR + Vector3.new(0, 0.05, 0)
					)
					local baseT = 1 - (1 - 0.84) * fade
					local fillT = 1 - (if hot then 0.88 else 0.42 + 0.12 * pulse) * fade
					pair[1].Transparency, pair[2].Transparency = baseT, baseT
					fpair[1].Transparency, fpair[2].Transparency = fillT, fillT
					local fc = if hot and kind ~= "Suction" then WHITE:Lerp(color, 0.35) else color
					fpair[1].Color, fpair[2].Color = fc, fc
				end
				return t < zone.T2 + 0.3
			end
		elseif zone.K == "Lane" then
			local baseBar = add(newPart({ Color = color, Parent = world })) :: Part
			local fillBar = add(newPart({ Color = color, Parent = world })) :: Part
			local chevrons = {}
			for _ = 1, 6 do
				table.insert(chevrons, add(newPart({ Color = WHITE, Parent = world })))
			end
			function marker.Update(t: number): boolean
				local zone = marker.Zone
				local span = math.max(zone.T1 - zone.T0, 0.05)
				local p = clamp01((t - zone.T0) / span)
				local hot = t >= zone.T1
				local fade = if t > zone.T2 then clamp01(1 - (t - zone.T2) / 0.25) else 1
				local angle = zone.A or 0
				local back = Rules.BODY_RADIUS
				local length = (zone.L or 60) + back
				local forward = dir(angle)
				local start = Vector3.new(zone.X, y, zone.Z) - forward * back
				local width = (zone.W or 14) * 2
				baseBar.Size = Vector3.new(width, 0.12, length)
				baseBar.CFrame = CFrame.lookAt(start + forward * (length / 2), start + forward * length)
				local fillLength = math.max(length * (if hot then 1 else p), 0.2)
				fillBar.Size = Vector3.new(width, 0.12, fillLength)
				fillBar.CFrame = CFrame.lookAt(
					start + forward * (fillLength / 2) + Vector3.new(0, 0.04, 0),
					start + forward * fillLength + Vector3.new(0, 0.04, 0)
				)
				local pulse = 0.5 + 0.5 * math.sin(t * (if hot then 40 else 12))
				baseBar.Transparency = 1 - (1 - 0.84) * fade
				fillBar.Transparency = 1 - (if hot then 0.88 else 0.42 + 0.12 * pulse) * fade
				fillBar.Color = if hot then WHITE:Lerp(color, 0.35) else color
				-- Chevrons pointing down the lane, running toward the wall.
				for index, chevron in chevrons do
					local u = ((index - 1) / #chevrons + t * 0.9) % 1
					local at = start + forward * (length * u)
					chevron.Size = Vector3.new(width * 0.5, 0.1, 1.6)
					chevron.CFrame = CFrame.lookAt(at + Vector3.new(0, 0.08, 0), at + forward + Vector3.new(0, 0.08, 0))
					chevron.Transparency = 1 - (0.5 * math.sin(u * math.pi)) * fade * (if hot then 0.3 else 1)
				end
				return t < zone.T2 + 0.3
			end
		end
		function marker.Destroy()
			for _, part in parts do
				part:Destroy()
			end
		end
		return marker :: Marker
	end

	-- Keeps the markers in step with the attack plan, on every publish: a new attack clears the old one's;
	-- within one, each zone is matched by its place, kind and start (a moved zone, the cord's circle
	-- following its target, keeps its marker and moves it; a zone added later, the dust bombs' circles or
	-- a second cord slam, gets one). A plan with no attack clears them all.
	local function syncMarkers()
		local plan = api:SharedJSON("Atk") -- (read here, whichever Atk handler runs first)
		if type(plan) ~= "table" or (plan.K or "") == "" or plan.I ~= markerId then
			for _, marker in markers do
				marker.Destroy()
			end
			markers = {}
			markerId = if type(plan) == "table" and (plan.K or "") ~= "" then plan.I else -1
		end
		if type(plan) ~= "table" or type(plan.Z) ~= "table" or (plan.K or "") == "" then
			return
		end
		local byKey: { [string]: Marker } = {}
		for _, marker in markers do
			byKey[(marker :: any).Key] = marker
		end
		for index, zone in plan.Z do
			local key = `{index}:{zone.K}:{zone.T0}`
			local marker = byKey[key]
			if marker then
				marker.Zone = zone
			else
				local made = makeMarker(zone, plan.K);
				(made :: any).Key = key
				table.insert(markers, made)
			end
		end
	end
	api:OnShared("Atk", syncMarkers)
	syncMarkers()

	-- The cord slam's shockwave rings -------------------------------------------------------------------------------------------
	type Ring = { X: number, Z: number, T0: number, Parts: { Part }, Flash: Part?, Visual: boolean }
	local rings: { Ring } = {}
	local RING_SEGMENTS = 30
	local function spawnRing(x: number, z: number, t0: number, visual: boolean?)
		local parts = {}
		for _ = 1, RING_SEGMENTS do
			table.insert(parts, newPart({ Color = HOT, Transparency = 1, Parent = world }))
		end
		local flash = newPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, 1, 1),
			Color = WHITE,
			Transparency = 1,
			Parent = world,
		})
		table.insert(rings, { X = x, Z = z, T0 = t0, Parts = parts, Flash = flash, Visual = visual == true })
	end
	local function updateRings(t: number)
		for index = #rings, 1, -1 do
			local ring = rings[index]
			local elapsed = t - ring.T0
			local speed = if ring.Visual then 46 else Rules.RING_SPEED
			local limit = if ring.Visual then 70 else Rules.RING_MAX + Rules.RING_THICK
			local r = math.max(elapsed, 0) * speed
			if r > limit + 2 then
				for _, part in ring.Parts do
					part:Destroy()
				end
				if ring.Flash then
					ring.Flash:Destroy()
				end
				table.remove(rings, index)
				continue
			end
			local thick = if ring.Visual then 2.4 else Rules.RING_THICK
			local fade = clamp01(r / limit)
			local arc = math.max(r, 1) * math.pi * 2 / RING_SEGMENTS
			for step, part in ring.Parts do
				local angle = step / RING_SEGMENTS * math.pi * 2
				local d = dir(angle)
				local at = Vector3.new(ring.X, floorY + 0.9, ring.Z) + d * math.max(r - thick / 2, 0.1)
				part.Size = Vector3.new(arc * 1.06 + 0.4, 1.8, thick)
				part.CFrame = CFrame.lookAt(at, at + d)
				part.Transparency = if r <= 0.1 then 1 else 0.12 + 0.75 * fade * fade
			end
			if ring.Flash then
				local flashSize = math.max(2, 22 * (1 - clamp01(elapsed / 0.3)))
				ring.Flash.Size = Vector3.new(0.2, flashSize, flashSize)
				ring.Flash.CFrame = CFrame.new(ring.X, floorY + 0.7, ring.Z) * CFrame.Angles(0, 0, math.rad(90))
				ring.Flash.Transparency = if elapsed < 0.3 then 0.15 + 0.85 * clamp01(elapsed / 0.3) else 1
			end
		end
	end

	-- Bricks: carried, thrown, piled ------------------------------------------------------------------------------------------------
	local carried: { [number]: Model } = {}
	type Flight = {
		Id: number,
		Kind: string,
		T0: number,
		T1: number,
		From: Vector3,
		Model: Model,
		Mine: boolean,
		Predicted: boolean,
	}
	local flights: { Flight } = {}
	local nextBrick = 0

	local function newBrick(color: Color3?): Model?
		if not brickTemplate then
			return nil
		end
		local brick = brickTemplate:Clone() :: Model
		prepare(brick, false)
		if color then
			for _, part in brick:GetDescendants() do
				if part:IsA("BasePart") then
					part.Color = if part.Name == "Stud" then color:Lerp(WHITE, 0.25) else color
				end
			end
		end
		brick.Parent = world
		return brick
	end

	-- A glowing streak behind a brick in flight.
	local function addTrail(brick: Model)
		local primary = brick.PrimaryPart or brick:FindFirstChildWhichIsA("BasePart")
		if not primary or State.ReducedEffects() then
			return
		end
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.8, 0)
		a0.Parent = primary
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.8, 0)
		a1.Parent = primary
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.35
		trail.LightEmission = 0.8
		trail.Color = ColorSequence.new(GOLD, WHITE)
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Parent = primary
	end

	local BRICK_COLORS = {
		Color3.fromRGB(232, 76, 84),
		Color3.fromRGB(70, 140, 235),
		Color3.fromRGB(250, 200, 60),
		Color3.fromRGB(86, 200, 120),
		Color3.fromRGB(250, 140, 60),
		Color3.fromRGB(160, 110, 230),
	}

	local function drawCarried(t: number)
		local seen = {}
		for _, id in carryList do
			seen[id] = true
			local character = api:CharacterOf(id)
			local root = rootOf(character)
			if root then
				local brick = carried[id]
				if not brick then
					brick = newBrick(BRICK_COLORS[id % #BRICK_COLORS + 1])
					if brick then
						carried[id] = brick
					end
				end
				if brick then
					local hover = 4.1 + 0.25 * math.sin(t * 5 + id)
					brick:PivotTo(
						CFrame.new(root.Position + Vector3.new(0, hover, 0))
							* CFrame.Angles(0, t * 2 + id, math.sin(t * 4 + id) * 0.12)
					)
				end
			end
		end
		for id, brick in carried do
			if not seen[id] then
				brick:Destroy()
				carried[id] = nil
			end
		end
	end

	local function flightTarget(kind: string): Vector3
		if kind == "Bag" then
			return bagCenter()
		end
		return coreAt()
	end

	local function startFlight(
		id: number,
		kind: string,
		t0: number,
		t1: number,
		from: Vector3,
		mine: boolean,
		predicted: boolean
	)
		local brick = newBrick(BRICK_COLORS[nextBrick % #BRICK_COLORS + 1])
		nextBrick += 1
		if not brick then
			return
		end
		addTrail(brick)
		table.insert(
			flights,
			{ Id = id, Kind = kind, T0 = t0, T1 = t1, From = from, Model = brick, Mine = mine, Predicted = predicted }
		)
	end

	local function updateFlights(t: number)
		for index = #flights, 1, -1 do
			local flight = flights[index]
			local alpha = (t - flight.T0) / math.max(flight.T1 - flight.T0, 0.05)
			if alpha >= 1.02 or (flight.Predicted and t - flight.T0 > 1.3) then
				flight.Model:Destroy()
				table.remove(flights, index)
				continue
			end
			local target = flightTarget(flight.Kind)
			local ax, ay, az =
				Rules.Arc(flight.From.X, flight.From.Y, flight.From.Z, target.X, target.Y, target.Z, alpha)
			flight.Model:PivotTo(CFrame.new(ax, ay, az) * CFrame.Angles(t * 9 + flight.Id, t * 7, t * 5))
		end
	end

	-- The piles: they glow while they have a brick, and say where they are.
	local pileGlows: { [number]: Part } = {}
	local pileGuides: { [number]: { Gui: BillboardGui, Label: TextLabel } } = {}
	task.spawn(function()
		local model = api:Arena(6)
		if not model then
			return
		end
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") and item.Name == "PileGlow" then
				for _, pile in pileList do
					if
						(Vector3.new(item.Position.X, 0, item.Position.Z) - Vector3.new(pile.X, 0, pile.Z)).Magnitude
						< 2
					then
						pileGlows[pile.I] = item
					end
				end
			end
		end
	end)
	local function drawPiles(t: number)
		local holding = carrying[me] == true
		for _, pile in pileList do
			local ready = t >= pile.R
			local glow = pileGlows[pile.I]
			if glow then
				glow.Transparency = if ready then 0.6 + 0.12 * math.sin(t * 4 + pile.I) else 0.92
			end
			local guide = pileGuides[pile.I]
			if not guide then
				local holder = anchorAt(Vector3.new(pile.X, floorY + 11, pile.Z), 600)
				local gui = UIKit.new("BillboardGui", {
					Size = UDim2.fromOffset(170, 52),
					AlwaysOnTop = false,
					LightInfluence = 0,
					MaxDistance = 120,
					Adornee = holder,
					Parent = holder,
				})
				local label = UIKit.Label({
					Text = "BRICKS ▼",
					Font = Theme.Fonts.Display,
					TextScaled = true,
					TextColor3 = GOLD,
					Size = UDim2.fromScale(1, 1),
					Parent = gui,
					Children = { UIKit.TextStroke(0) },
				})
				guide = { Gui = gui, Label = label }
				pileGuides[pile.I] = guide
			end
			local adornee = guide.Gui.Adornee :: Part
			adornee.CFrame = CFrame.new(pile.X, floorY + 11 + 0.8 * math.sin(t * 3 + pile.I), pile.Z)
			guide.Gui.Enabled = not holding and ready and inRound()
		end
	end

	-- Events ------------------------------------------------------------------------------------------------------------------------
	local bannerLabel: TextLabel
	local subLabel: TextLabel
	local flashFrame: Frame
	local callout: (text: string, color: Color3?, sub: string?, hold: number?, priority: number?) -> ()

	local function num(value: any): number?
		return if type(value) == "number" and value == value then value else nil
	end

	local function onEvent(name: string, handler: (...any) -> ())
		api:OnEvent(name, function(...)
			local ok, err = pcall(handler, ...)
			if not ok then
				warn(`[BigBadVacuum] event {name}: {err}`)
			end
		end)
	end

	local myDazedUntil = 0
	local WIND_TEXT = {
		Sweep = { "SWEEP!", "Get out of the red!" },
		Whirl = { "WHIRLWIND!", "Run to the edge!" },
		Charge = { "CHARGE!", "Dodge it - let it hit the wall!" },
		Suction = { "SUCTION!", "Run out of the wind!" },
		Cord = { "CORD SLAM!", "Jump the shockwave!" },
		Bombs = { "DUST BOMBS!", "Watch the circles!" },
	}
	onEvent("Wind", function(kind, _id, _t1)
		local text = WIND_TEXT[kind]
		if text then
			callout(text[1], if kind == "Suction" then WIND else DANGER, text[2], 1.2, 2)
		end
		api:Sound("HazardWarning")
		if shown.Ready then
			playAt(SOUND_PING, Vector3.new(shown.X, floorY + 8, shown.Z), 0.6, 0.5)
		end
	end)
	onEvent("Swing", function()
		if shown.Ready then
			playAt(SOUND_WHOOSH, Vector3.new(shown.X, floorY + 4, shown.Z), 0.9, 0.7)
		end
		shake(0.6)
	end)
	onEvent("Dash", function()
		if shown.Ready then
			playAt(SOUND_WHOOSH, Vector3.new(shown.X, floorY + 4, shown.Z), 1, 0.45)
		end
		shake(0.5)
	end)
	onEvent("Spin", function()
		if shown.Ready then
			playAt(SOUND_WHOOSH, Vector3.new(shown.X, floorY + 4, shown.Z), 0.9, 0.9)
		end
	end)
	onEvent("Inhale", function()
		shake(0.35)
	end)
	onEvent("Mortar", function(_id, _t, x, z)
		if num(x) and num(z) then
			playAt(SOUND_CLICK, Vector3.new(x, floorY + 14, z), 0.8, 0.45)
		end
	end)
	onEvent("Land", function(x, z, t)
		local _ = t
		if num(x) and num(z) then
			local at = Vector3.new(x, floorY + 1, z)
			dust(at, 18, 26)
			fireball(at + Vector3.new(0, 4, 0), 30, Color3.fromRGB(255, 220, 160), 0.5)
			spawnRing(x, z, now(), true)
			playAt(SOUND_BOOM, at, 1.6, 0.35)
			shake(2.4, at)
			punchFov(9)
		end
	end)
	onEvent("Roar", function()
		local at = if shown.Ready
			then Vector3.new(shown.X, floorY + 10, shown.Z)
			else Vector3.new(centerX, floorY + 10, centerZ)
		playAt(SOUND_BOOM, at, 1.4, 0.3)
		playAt(SOUND_WHOOSH, at, 1.2, 0.3)
		shake(1.6)
		punchFov(7)
		callout("BIG BAD VACUUM", DANGER, "Beat it together before time runs out!", 2.4, 5)
	end)
	onEvent("Crash", function(x, z, face)
		if not (num(x) and num(z) and num(face)) then
			return
		end
		local at = Vector3.new(x, floorY + 6, z) + dir(face) * Rules.BODY_RADIUS
		dust(at, 20, 30)
		sparks(at, 40, GOLD, 40)
		fireball(at, 22, Color3.fromRGB(255, 200, 120), 0.4)
		playAt(SOUND_BOOM, at, 1.5, 0.4)
		shake(2.2, at)
		punchFov(8)
		-- Shards fly off the wall.
		if debrisTemplate and not State.ReducedEffects() then
			for _ = 1, 10 do
				local chunk = debrisTemplate:Clone() :: Model
				prepare(chunk, false)
				chunk.Parent = world
				local velocity = Vector3.new(
					(math.random() - 0.5) * 50,
					28 + math.random() * 30,
					(math.random() - 0.5) * 50
				) - dir(face) * (10 + math.random() * 18)
				local position = at
				local spinAxis = Vector3.new(math.random(), math.random(), math.random()).Unit
				task.spawn(function()
					local born = os.clock()
					while chunk.Parent and os.clock() - born < 1.6 do
						local step = 1 / 60
						velocity += Vector3.new(0, -90 * step, 0)
						position += velocity * step
						chunk:PivotTo(
							CFrame.new(position)
								* CFrame.fromAxisAngle(spinAxis, (os.clock() - born) * 9)
								* CFrame.new(0, 0, 0)
						)
						task.wait()
					end
					chunk:Destroy()
				end)
			end
		end
	end)
	onEvent("Slam", function(_id, x, z, t)
		if not (num(x) and num(z)) then
			return
		end
		local at = Vector3.new(x, floorY + 1, z)
		spawnRing(x, z, num(t) or now())
		dust(at, 14, 22)
		sparks(at, 24, HOT, 34)
		fireball(at + Vector3.new(0, 2, 0), 16, Color3.fromRGB(255, 190, 110), 0.35)
		playAt(SOUND_BOOM, at, 1.3, 0.5)
		shake(1.5, at)
		local root = myRoot()
		if root and inRound() then
			local away = Rules.Distance(root.Position.X, root.Position.Z, x, z)
			local arrives = math.max(away - Rules.RING_THICK, 0) / Rules.RING_SPEED
			if arrives < 1.2 then
				callout("JUMP!", HOT, nil, math.max(arrives, 0.35) + 0.3, 6)
			end
		end
	end)
	onEvent("Boom", function(x, z, kind)
		if not (num(x) and num(z)) then
			return
		end
		local at = Vector3.new(x, floorY + 2, z)
		dust(at, 12, 20, Color3.fromRGB(120, 108, 100))
		sparks(at, 22, HOT, 30)
		fireball(at + Vector3.new(0, 3, 0), 15, Color3.fromRGB(255, 170, 90), 0.4)
		playAt(SOUND_BOOM, at, 1.1, if kind == "Bomb" then 0.6 else 0.5)
		shake(0.9, at)
	end)
	onEvent("Core", function(until_, reason)
		local text = ({
			Charge = { "IT CRASHED! CORE OPEN!", "Everyone THROW!" },
			Suction = { "OVERHEATED! CORE OPEN!", "Everyone THROW!" },
			Whirl = { "DIZZY! CORE OPEN!", "Everyone THROW!" },
			Blast = { "OVERLOADED! CORE OPEN!", "Everyone THROW!" },
		})[reason] or { "CORE OPEN!", "THROW!" }
		callout(text[1], CYAN, text[2], 1.5, 4)
		api:Sound("Pickup")
		local _ = until_
	end)
	onEvent("Hit", function(x, y, z, dealt, crit, volley, userId)
		if not (num(x) and num(y) and num(z) and num(dealt)) then
			return
		end
		local at = Vector3.new(x, y, z)
		if crit then
			local color = if volley and volley >= 3 then GOLD else Color3.fromRGB(255, 240, 130)
			floatText(
				at + Vector3.new((math.random() - 0.5) * 6, 3, (math.random() - 0.5) * 6),
				`-{dealt}`,
				color,
				26 + math.min(volley or 1, 5) * 4,
				9
			)
			sparks(at, 22, color, 30)
			playAt(SOUND_HIT, at, 0.9, 0.8 + math.min(volley or 1, 6) * 0.08)
			shake(0.35 + 0.1 * math.min(volley or 1, 5), at)
			if volley and volley >= 3 and userId == me then
				callout(`VOLLEY x{volley}!`, GOLD, nil, 0.9, 3)
			end
		else
			floatText(at + Vector3.new(0, 2, 0), `-{dealt}`, Color3.fromRGB(220, 220, 230), 20, 6)
			sparks(at, 6, WHITE, 18)
		end
	end)
	onEvent("Clink", function(x, y, z, shielded)
		if not (num(x) and num(y) and num(z)) then
			return
		end
		local at = Vector3.new(x, y, z)
		sparks(at, 8, if shielded then CYAN else WHITE, 22)
		playAt(SOUND_CLICK, at, 0.7, 1.4)
		if not shielded then
			floatText(at + Vector3.new(0, 3, 0), "CLINK", Color3.fromRGB(200, 200, 215), 18, 5)
		end
	end)
	onEvent("Pop", function(count, userId, x, y, z)
		if not (num(x) and num(y) and num(z) and num(count)) then
			return
		end
		local at = Vector3.new(x, y, z)
		sparks(at, 40, Color3.fromRGB(255, 255, 255), 36)
		dust(at, 12, 16, Color3.fromRGB(240, 240, 255))
		fireball(at, 16, Color3.fromRGB(230, 240, 255), 0.4)
		playAt(SOUND_PING, at, 0.9, 1.3)
		shake(0.8, at)
		callout(`RESCUED x{count}!`, CYAN, nil, 1.3, 3)
		if userId == me then
			api:Sound("Victory")
		end
	end)
	onEvent("Trapped", function(userId, x, y, z)
		if num(x) and num(y) and num(z) then
			local at = Vector3.new(x, y, z)
			dust(at, 8, 10, Color3.fromRGB(240, 240, 255))
			playAt(SOUND_WHOOSH, at, 0.9, 1.6)
		end
		if userId == me then
			callout("SUCKED UP!", WIND, "Friends can free you with a brick!", 2, 5)
		end
	end)
	onEvent("Freed", function(userId)
		if userId == me then
			api:Sound("Boing")
		end
	end)
	onEvent("Dazed", function(userId, x, y, z)
		if num(x) and num(y) and num(z) then
			local at = Vector3.new(x, y + 2, z)
			emit(anchorAt(at, 2), {
				Texture = SPARKLE,
				Color = ColorSequence.new(GOLD),
				LightEmission = 1,
				Size = NumberSequence.new(1.2, 0.2),
				Lifetime = NumberRange.new(0.6, 1.1),
				Speed = NumberRange.new(10, 20),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, -20, 0),
			}, 12)
			playAt(SOUND_HIT, at, 0.8, 0.6)
		end
		if userId == me then
			myDazedUntil = now() + Rules.DAZE
			shake(1.0)
			punchFov(4)
			UIKit.Tween(flashFrame, 0.05, { BackgroundTransparency = 0.55, BackgroundColor3 = DANGER })
			task.delay(0.08, function()
				if flashFrame.Parent then
					UIKit.Tween(flashFrame, 0.5, { BackgroundTransparency = 1 })
				end
			end)
		end
	end)
	onEvent("Pickup", function(userId)
		if userId == me then
			api:Sound("Pickup")
		end
	end)
	onEvent("Refused", function(_what)
		for index = #flights, 1, -1 do
			if flights[index].Predicted then
				flights[index].Model:Destroy()
				table.remove(flights, index)
			end
		end
		readCarry() -- (the brick we drew leaving is still in hand, as far as the server is concerned)
	end)
	onEvent("Throw", function(id, userId, kind, t0, t1, fx, fy, fz)
		if not (num(id) and num(userId) and num(t0) and num(t1) and num(fx) and num(fy) and num(fz)) then
			return
		end
		local kindName = if kind == "Bag" then "Bag" else "Core"
		if userId == me then
			for index = #flights, 1, -1 do
				if flights[index].Predicted then
					flights[index].Model:Destroy()
					table.remove(flights, index)
				end
			end
		end
		startFlight(id, kindName, t0, t1, Vector3.new(fx, fy, fz), userId == me, false)
		playAt(SOUND_WHOOSH, Vector3.new(fx, fy, fz), 0.5, 1.4)
	end)
	onEvent("Phase", function(phase, t, until_)
		if not num(phase) then
			return
		end
		local title = ({ "", "PHASE 2", "PHASE 3" })[math.clamp(phase, 1, 3)]
		local sub = ({ "", "It learned the CORD SLAM!", "FINAL PHASE: whirlwinds and dust bombs!" })[math.clamp(
			phase,
			1,
			3
		)]
		callout(title, PHASE_COLORS[math.clamp(phase, 1, 3)], sub, 2.4, 5)
		local at = if shown.Ready
			then Vector3.new(shown.X, floorY + 10, shown.Z)
			else Vector3.new(centerX, floorY + 10, centerZ)
		fireball(at, 40, PHASE_COLORS[math.clamp(phase, 1, 3)], 0.7)
		spawnRing(shown.X, shown.Z, now(), true)
		dust(at, 20, 20)
		playAt(SOUND_BOOM, at, 1.5, 0.3)
		playAt(SOUND_WHOOSH, at, 1.2, 0.35)
		shake(2.2)
		punchFov(8)
		local _ = t
		local _u = until_
	end)
	onEvent("MeterFull", function()
		callout("PANIC METER FULL!", Color3.fromRGB(255, 90, 200), "Press PANIC!", 1.6, 4)
		api:Sound("Victory")
	end)
	onEvent("Panic", function(userId, t0, t1)
		local at = Vector3.new(shown.X, floorY + 10, shown.Z)
		local name = "Someone"
		for _, person in api:Participants() do
			if person.UserId == userId then
				name = person.DisplayName
			end
		end
		callout("PANIC BLAST!", Color3.fromRGB(255, 90, 200), `{name} hit the button!`, 1.6, 7)
		playAt(SOUND_WHOOSH, at, 1.3, 0.3)
		shake(0.8)
		punchFov(-6)
		-- A beam charges from the sky onto the core.
		local sky = newPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(300, 1, 1),
			Color = Color3.fromRGB(255, 120, 220),
			Transparency = 0.2,
			Parent = world,
		})
		local startAt = num(t0) or now()
		local endAt = num(t1) or startAt + 1.4
		task.spawn(function()
			while sky.Parent and now() < endAt + 0.7 do
				local t = now()
				local core = coreAt()
				local p = clamp01((t - startAt) / math.max(endAt - startAt, 0.1))
				local width = if t < endAt then 0.5 + 5 * p * p else math.max(0.1, 14 * (1 - (t - endAt) / 0.7))
				sky.Size = Vector3.new(300, width, width)
				sky.CFrame = CFrame.new(core.X, core.Y + 150, core.Z) * CFrame.Angles(0, 0, math.rad(90))
				sky.Transparency = if t < endAt then 0.5 - 0.3 * p else 0.15 + 0.85 * clamp01((t - endAt) / 0.7)
				task.wait()
			end
			sky:Destroy()
		end)
	end)
	onEvent("Blast", function(dealt)
		local at = coreAt()
		fireball(at, 46, Color3.fromRGB(255, 160, 240), 0.8)
		fireball(at, 26, WHITE, 0.4)
		sparks(at, 70, Color3.fromRGB(255, 160, 240), 50)
		spawnRing(shown.X, shown.Z, now(), true)
		dust(at, 22, 24)
		playAt(SOUND_BOOM, at, 1.8, 0.28)
		shake(2.6)
		punchFov(10)
		UIKit.Tween(flashFrame, 0.04, { BackgroundTransparency = 0.25, BackgroundColor3 = WHITE })
		task.delay(0.06, function()
			if flashFrame.Parent then
				UIKit.Tween(flashFrame, 0.6, { BackgroundTransparency = 1 })
			end
		end)
		if num(dealt) then
			floatText(at + Vector3.new(0, 6, 0), `-{dealt}`, Color3.fromRGB(255, 150, 240), 44, 14)
		end
	end)

	-- Finales ---------------------------------------------------------------------------------------------------------------------
	local finale: { Kind: string, T0: number }? = nil
	local finaleBlown = false
	local mvpName = ""
	local function mvp(): (string, number)
		local best, bestScore = "", -1
		for _, person in api:Participants() do
			local score = person:GetAttribute("PP_Score") or 0
			if score > bestScore then
				best, bestScore = person.DisplayName, score
			end
		end
		return best, bestScore
	end
	onEvent("Victory", function(t0, killerId)
		finale = { Kind = "Victory", T0 = num(t0) or now() }
		local _ = killerId
		callout("", WHITE, nil, 0, 0)
		shake(1.4)
		punchFov(6)
		api:Sound("HazardWarning")
	end)
	onEvent("Defeat", function(t0)
		finale = { Kind = "Defeat", T0 = num(t0) or now() }
		callout("TIME'S UP!", DANGER, "The vacuum is winning...", 2.5, 9)
		api:Sound("Eliminated")
		shake(1.2)
	end)

	local nextBoom = 0
	local function drawFinale(t: number)
		local f = finale
		if not f or not shown.Ready then
			return
		end
		local since = t - f.T0
		local at = Vector3.new(shown.X, floorY + 8, shown.Z)
		if f.Kind == "Victory" then
			if since < 3.2 then
				-- A chain of little explosions, faster and faster.
				if t >= nextBoom then
					nextBoom = t + math.max(0.12, 0.55 - since * 0.15)
					local angle = math.random() * math.pi * 2
					local spot = at + dir(angle) * (math.random() * 10) + Vector3.new(0, (math.random() - 0.2) * 9, 0)
					fireball(
						spot,
						7 + math.random() * 6,
						if math.random() < 0.5 then HOT else Color3.fromRGB(255, 240, 160),
						0.35
					)
					sparks(spot, 12, HOT, 34)
					playAt(SOUND_BOOM, spot, 0.8, 0.6 + math.random() * 0.4)
					shake(0.7 + since * 0.3, spot)
				end
			elseif not finaleBlown then
				finaleBlown = true
				-- The big one.
				fireball(at, 70, Color3.fromRGB(255, 230, 170), 1.0)
				fireball(at, 40, WHITE, 0.5)
				spawnRing(shown.X, shown.Z, t, true)
				dust(at, 30, 40)
				sparks(at, 120, HOT, 70)
				playAt(SOUND_BOOM, at, 2, 0.25)
				playAt(SOUND_BOOM, at, 2, 0.5)
				shake(4)
				punchFov(14)
				api:Effect("Finale", at + Vector3.new(0, 8, 0))
				task.delay(0.5, function()
					api:Effect("Fireworks", at + Vector3.new(0, 14, 0))
				end)
				task.delay(1.0, function()
					api:Effect("Confetti", at + Vector3.new(0, 20, 0))
				end)
				UIKit.Tween(flashFrame, 0.05, { BackgroundTransparency = 0, BackgroundColor3 = WHITE })
				task.delay(0.12, function()
					if flashFrame.Parent then
						UIKit.Tween(flashFrame, 1.0, { BackgroundTransparency = 1 })
					end
				end)
				local name, score = mvp()
				mvpName = name
				callout(
					"VICTORY!",
					GOLD,
					if name ~= "" then `MVP: {name} · {score} pts` else "You beat the Big Bad Vacuum!",
					3.2,
					10
				)
				api:Sound("Victory")
				if bodyModel then
					bodyModel.Parent = nil
				end
				if armModel then
					armModel.Parent = nil
				end
				if bagModel then
					bagGone = true
					bagModel.Parent = nil
				end
			end
		else
			-- The boss laughs: a bounce and a low rumble.
			if t >= nextBoom then
				nextBoom = t + 0.55
				playAt(SOUND_BOOM, at, 0.9, 0.3)
				shake(0.5)
			end
		end
	end

	-- HUD -----------------------------------------------------------------------------------------------------------------------------
	local hud = api:TopHud()
	local barWidth = 560
	local panel = UIKit.new("Frame", {
		Name = "BossPanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY()),
		Size = UDim2.fromOffset(barWidth, 140),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud,
	})
	UIKit.Label({
		Text = "BIG BAD VACUUM",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = WHITE,
		Position = UDim2.fromOffset(2, 0),
		Size = UDim2.fromOffset(barWidth * 0.55, 32),
		Parent = panel,
		Children = { UIKit.TextStroke(0.1) },
	})
	local phaseLabel = UIKit.Label({
		Text = "PHASE 1",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = PHASE_COLORS[1],
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -2, 0, 1),
		Size = UDim2.fromOffset(barWidth * 0.4, 32),
		Parent = panel,
		Children = { UIKit.TextStroke(0.1) },
	})
	local track = UIKit.new("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.fromOffset(barWidth, 34),
		BackgroundColor3 = Color3.fromRGB(24, 18, 40),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = panel,
		Children = { UIKit.Corner(17), UIKit.Stroke(WHITE, 3, 0.35) },
	})
	local ghost = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 226, 190),
		BorderSizePixel = 0,
		Parent = track,
	})
	local fill = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 64, 84),
		BorderSizePixel = 0,
		Parent = track,
		Children = { UIKit.Gradient(Color3.fromRGB(255, 120, 90), Color3.fromRGB(220, 30, 70), 90) },
	})
	for _, at in Rules.PHASE_AT do
		UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(at, 0),
			Size = UDim2.new(0, 3, 1, 0),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = track,
		})
	end
	local hpLabel = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = track,
		Children = { UIKit.TextStroke(0) },
	})
	local meterTrack = UIKit.new("Frame", {
		Position = UDim2.new(0.5, -180, 0, 74),
		Size = UDim2.fromOffset(360, 30),
		BackgroundColor3 = Color3.fromRGB(24, 18, 40),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = panel,
		Children = { UIKit.Corner(15), UIKit.Stroke(WHITE, 2, 0.45) },
	})
	local meterFill = UIKit.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 90, 200),
		BorderSizePixel = 0,
		Parent = meterTrack,
		Children = { UIKit.Gradient(Color3.fromRGB(255, 170, 240), Color3.fromRGB(190, 60, 255), 0) },
	})
	local meterLabel = UIKit.Label({
		Text = "PARTY METER",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = meterTrack,
		Children = { UIKit.TextStroke(0) },
	})
	local coreLabel = UIKit.Label({
		Text = "CORE OPEN! THROW!",
		TextWrapped = false,
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextColor3 = CYAN,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 106),
		Size = UDim2.fromOffset(320, 36),
		Visible = false,
		Parent = panel,
		Children = { UIKit.TextStroke(0) },
	})
	local coreScale = UIKit.new("UIScale", { Parent = coreLabel })

	-- Big banner words in the middle of the screen, and a full-screen flash.
	local gui = api.Gui
	bannerLabel = UIKit.Label({
		Name = "Banner",
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = if touch then UDim2.fromScale(0.64, 0.37) else UDim2.fromScale(0.5, 0.3),
		Size = if touch then UDim2.fromScale(0.4, 0.12) else UDim2.fromScale(0.7, 0.11),
		Visible = false,
		ZIndex = 20,
		Parent = gui,
		Children = { UIKit.TextStroke(0), UIKit.new("UITextSizeConstraint", { MaxTextSize = 78, MinTextSize = 18 }) },
	})
	local bannerScale = UIKit.new("UIScale", { Parent = bannerLabel })
	subLabel = UIKit.Label({
		Name = "BannerSub",
		Text = "",
		Font = Theme.Fonts.Bold,
		TextScaled = true,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = if touch then UDim2.fromScale(0.64, 0.47) else UDim2.fromScale(0.5, 0.385),
		Size = if touch then UDim2.fromScale(0.4, 0.07) else UDim2.fromScale(0.6, 0.05),
		Visible = false,
		ZIndex = 20,
		Parent = gui,
		Children = { UIKit.TextStroke(0), UIKit.new("UITextSizeConstraint", { MaxTextSize = 34, MinTextSize = 14 }) },
	})
	flashFrame = UIKit.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 30,
		Parent = gui,
	})

	local calloutUntil = 0
	local calloutPriority = 0
	callout = function(text: string, color: Color3?, sub: string?, hold: number?, priority: number?)
		local t = now()
		local rank = priority or 1
		if text == "" then
			calloutUntil = 0
			bannerLabel.Visible = false
			subLabel.Visible = false
			return
		end
		if t < calloutUntil and rank < calloutPriority then
			return
		end
		calloutPriority = rank
		calloutUntil = t + (hold or 1.2)
		bannerLabel.Text = text
		bannerLabel.TextColor3 = color or WHITE
		bannerLabel.Visible = true
		bannerScale.Scale = 1.5
		UIKit.Tween(bannerScale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
		subLabel.Text = sub or ""
		subLabel.Visible = sub ~= nil and sub ~= ""
	end

	-- Danger edge (while standing in a warning) and the "SUCKED UP" dust.
	local edgeGui = api:Track(UIKit.new("ScreenGui", {
		Name = "BigBadVacuumEdge",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = -1,
		Enabled = false,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	}))
	local edges: { Frame } = {}
	for _, side in { "Bottom", "Left", "Right", "Top" } do
		local vertical = side == "Left" or side == "Right"
		local edge = UIKit.new("Frame", {
			BackgroundColor3 = DANGER,
			BorderSizePixel = 0,
			Active = false,
			AnchorPoint = Vector2.new(if side == "Right" then 1 else 0, if side == "Bottom" then 1 else 0),
			Position = UDim2.fromScale(if side == "Right" then 1 else 0, if side == "Bottom" then 1 else 0),
			Size = if vertical then UDim2.new(0, 70, 1, 0) else UDim2.new(1, 0, 0, 70),
			Parent = edgeGui,
		})
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new(0, 1)
		gradient.Rotation = ({ Bottom = -90, Left = 0, Right = 180, Top = 90 })[side]
		gradient.Parent = edge
		table.insert(edges, edge)
	end
	local moveLabel = UIKit.Label({
		Text = "MOVE!",
		Font = Theme.Fonts.Display,
		TextSize = 40,
		TextColor3 = DANGER,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY() + 150),
		Size = UDim2.fromOffset(240, 46),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0) },
	})
	local trappedLabel = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 32,
		TextColor3 = WIND,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY() + 150),
		Size = UDim2.fromOffset(560, 80),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0) },
	})

	-- Buttons ---------------------------------------------------------------------------------------------------------------------------
	local throwButton = api:Button({ Text = "THROW", Key = Enum.KeyCode.E, Color = Theme.Colors.Orange, Slot = 1 })
	local bagButton = api:Button({ Text = "BAG", Key = Enum.KeyCode.Q, Color = Theme.Colors.Cyan, Slot = 2 })
	local panicButton = api:Button({ Text = "PANIC", Key = Enum.KeyCode.F, Color = Theme.Colors.Pink, Slot = 3 })
	bagButton:SetVisible(false)
	panicButton:SetVisible(false)

	local lastThrow = 0
	local function canThrow(): boolean
		local t = now()
		return inRound()
			and carrying[me] == true
			and trapped[me] == nil
			and t >= myDazedUntil
			and boss ~= nil
			and boss.S ~= "Intro"
			and boss.S ~= "Dying"
			and boss.S ~= "Done"
			and t - lastThrow > Rules.THROW_WAIT * 0.9
	end
	local function throwBrick(kind: string)
		if not canThrow() then
			return
		end
		local root = myRoot()
		if not root then
			return
		end
		local t = now()
		lastThrow = t
		-- Draw it at once; the server's own "Throw" replaces it with its timing (or a refusal removes it).
		local from = root.Position + Vector3.new(0, 2, 0)
		local target = flightTarget(kind)
		local distance = (Vector3.new(target.X, from.Y, target.Z) - from).Magnitude
		startFlight(-1, kind, t, t + Rules.Flight(distance), from, true, true)
		carrying[me] = nil -- (it's in the air; the server confirms)
		api:Action("Throw", kind)
		api:Sound("Boing")
	end
	throwButton.Pressed:Connect(function()
		throwBrick("Core")
	end)
	bagButton.Pressed:Connect(function()
		throwBrick("Bag")
	end)
	panicButton.Pressed:Connect(function()
		if meter.R then
			api:Action("Panic")
		end
	end)

	-- The first seconds: how to play.
	local hintUntil = 0
	local shownHint = ""

	-- Every frame ---------------------------------------------------------------------------------------------------------------------------
	local shownHp = 1
	local ghostHp = 1
	local lastHpChange = 0
	local lastHp = 1
	local lastPhase = 1

	local function updateHud(t: number, dt: number)
		if not boss then
			panel.Visible = false
			return
		end
		local revealed = lastLanded and boss.S ~= "Intro" or (boss.S == "Intro" and t - goTime() > LAND_AT + 0.4)
		panel.Visible = revealed
		local fraction = clamp01(boss.H / math.max(boss.M, 1))
		if fraction < lastHp - 1e-4 then
			lastHpChange = t
		end
		lastHp = fraction
		shownHp += (fraction - shownHp) * (1 - math.exp(-14 * dt))
		if t - lastHpChange > 0.45 then
			ghostHp += (fraction - ghostHp) * (1 - math.exp(-5 * dt))
		end
		ghostHp = math.max(ghostHp, fraction)
		fill.Size = UDim2.fromScale(shownHp, 1)
		ghost.Size = UDim2.fromScale(ghostHp, 1)
		hpLabel.Text = `{boss.H} / {boss.M}`
		local phase = boss.P or 1
		if phase ~= lastPhase then
			lastPhase = phase
		end
		phaseLabel.Text = `PHASE {phase}`
		phaseLabel.TextColor3 = PHASE_COLORS[math.clamp(phase, 1, 3)]
		local coreOpen = boss.S ~= "Break" and boss.S ~= "Dying" and t < (boss.C or 0)
		coreLabel.Visible = coreOpen
		if coreOpen then
			coreScale.Scale = 1 + 0.07 * math.sin(t * 12)
			coreLabel.Text = if carrying[me] then "CORE OPEN! THROW!" else "CORE OPEN! GET BRICKS!"
		end
		local stroke = track:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if coreOpen then CYAN else WHITE
			stroke.Transparency = if coreOpen then 0.1 else 0.35
		end
		-- The meter.
		local meterValue = (meter.V or 0) / 100
		meterFill.Size = UDim2.fromScale(meterValue, 1)
		if meter.R then
			local pulse = 0.5 + 0.5 * math.sin(t * 10)
			meterLabel.Text = if touch then "PANIC READY! TAP PANIC" else "PANIC READY! PRESS F"
			meterFill.BackgroundColor3 = Color3.fromRGB(255, 90, 200):Lerp(WHITE, pulse * 0.6)
		else
			meterLabel.Text = "PARTY METER"
			meterFill.BackgroundColor3 = Color3.fromRGB(255, 90, 200)
		end
		-- Buttons.
		local canAct = inRound()
		local holding = carrying[me] == true
		local stuck = trapped[me] ~= nil
		local free = canAct
			and not stuck
			and t >= myDazedUntil
			and boss.S ~= "Intro"
			and boss.S ~= "Dying"
			and boss.S ~= "Done"
		throwButton:SetEnabled(holding and free)
		throwButton:SetText(
			if holding then "THROW" elseif stuck then "STUCK!" elseif t < myDazedUntil then "DAZED" else "EMPTY"
		)
		bagButton:SetVisible(#trapList > 0 and holding and not stuck)
		bagButton:SetFill(0)
		panicButton:SetVisible(meter.R == true and canAct and not stuck and boss.S ~= "Break")
		if meter.R then
			panicButton:SetFill(0.5 + 0.5 * math.sin(t * 8), Color3.fromRGB(255, 200, 250))
		end
		-- The banner fades when its time is up.
		if bannerLabel.Visible and t > calloutUntil then
			bannerLabel.Visible = false
			subLabel.Visible = false
			calloutPriority = 0
		end
		-- How to play, for the first seconds of the fight.
		if hintUntil == 0 and State.Phase() == "InRound" then
			hintUntil = t + 16
		end
		local hint = ""
		if
			hintUntil > 0
			and t < hintUntil
			and canAct
			and finale == nil
			and not moveLabel.Visible
			and not trappedLabel.Visible
			and not bannerLabel.Visible
		then
			if not holding and boss.S ~= "Break" then
				hint = "Grab a brick from a BRICKS ▼ pile!"
			elseif coreOpen then
				hint = ""
			elseif holding then
				hint = "Keep your brick - THROW when the core opens!"
			end
		end
		if hint ~= shownHint then
			shownHint = hint
			api:Hint(hint, api:HudY() + 150)
		end
	end

	local function updatePlayerState(t: number, dt: number)
		local root = myRoot()
		local active = inRound() and root ~= nil and boss ~= nil
		-- The suction pulls this player's own character toward the mouth.
		if
			active
			and root
			and (atk.K or "") == "Suction"
			and t >= atk.T1
			and t <= atk.T2
			and trapped[me] == nil
			and not root.Anchored
		then
			local zone = atk.Z and atk.Z[1]
			if zone then
				local x, z = root.Position.X, root.Position.Z
				if Rules.InCone(zone.X, zone.Z, atk.F or zone.A or 0, zone.Arc or 1.7, zone.R or 48, x, z) then
					local mx, mz = Rules.MouthAt(zone.X, zone.Z, atk.F or zone.A or 0)
					local dx, dz = mx - x, mz - z
					local m = math.max(math.sqrt(dx * dx + dz * dz), 0.1)
					local speed = Rules.PullSpeed(Rules.Distance(x, z, zone.X, zone.Z)) * dt
					root.CFrame = root.CFrame + Vector3.new(dx / m * speed, 0, dz / m * speed)
					shake(0.12)
				end
			end
		end
		-- Standing in a warning: a red edge and MOVE!.
		local danger = false
		if active and root and trapped[me] == nil then
			local x, z = root.Position.X, root.Position.Z
			for _, zone in atk.Z or {} do
				if t >= zone.T0 and t <= zone.T2 + 0.1 and Rules.ZoneContains(zone, x, z) then
					danger = true
					break
				end
			end
		end
		local pulse = 0.5 + 0.5 * math.sin(t * 14)
		edgeGui.Enabled = danger or trapped[me] ~= nil
		for _, edge in edges do
			edge.BackgroundColor3 = if trapped[me] then WIND else DANGER
			edge.BackgroundTransparency = 0.5 + 0.25 * pulse
		end
		moveLabel.Visible = danger
		if danger then
			moveLabel.TextTransparency = 0.1 * pulse
		end
		local stuck = trapped[me]
		trappedLabel.Visible = stuck ~= nil
		if stuck then
			trappedLabel.Text = `YOU'RE IN THE DUST BAG!\nFriends can free you with a brick · out in {math.max(
				0,
				math.ceil(stuck.E - t)
			)}s`
		end
	end

	-- Camera ----------------------------------------------------------------------------------------------------------------------------------
	local camMode = "Normal"
	local baseFov = camera.FieldOfView
	local function restoreCamera()
		if camMode ~= "Normal" then
			camMode = "Normal"
			local _, humanoid = api:Character()
			camera.CameraType = Enum.CameraType.Custom
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end
	api:Track(function()
		restoreCamera()
		camera.FieldOfView = baseFov
		pcall(function()
			RunService:UnbindFromRenderStep("BigBadVacuumCamera")
		end)
	end)

	local function flyoverPose(t: number): CFrame?
		local ends = GameState.Get("PhaseEndsAt")
		if type(ends) ~= "number" or State.Phase() ~= "Preparing" or not api:CanAct() then
			return nil
		end
		local left = ends - t
		local length = 4.2
		if left > length or left < -0.1 then
			return nil
		end
		local root = myRoot()
		if not root then
			return nil
		end
		-- A swoop from high over the middle, round the arena, down to just behind this player's character
		-- (about where the normal camera starts), the eye going round the middle as it comes in.
		local p = smooth(1 - left / length)
		local centerPos = Vector3.new(centerX, floorY, centerZ)
		local out = Vector3.new(root.Position.X - centerX, 0, root.Position.Z - centerZ)
		local outDir = if out.Magnitude > 0.5 then out.Unit else Vector3.new(0, 0, 1)
		local endAngle = math.atan2(outDir.Z, outDir.X)
		local endEye = root.Position + outDir * 13 + Vector3.new(0, 6.5, 0)
		local endRadius = Vector3.new(endEye.X - centerX, 0, endEye.Z - centerZ).Magnitude
		local startAngle = endAngle + 1.5
		local angle = startAngle + (endAngle - startAngle) * p
		local radius = 96 + (endRadius - 96) * p
		local height = 82 + (endEye.Y - floorY - 82) * p
		local eye = Vector3.new(centerX + math.cos(angle) * radius, floorY + height, centerZ + math.sin(angle) * radius)
		local focus = (centerPos + Vector3.new(0, 9, 0)):Lerp(root.Position + Vector3.new(0, 2, 0), p * p)
		return CFrame.lookAt(eye, focus)
	end

	local function finalePose(t: number): CFrame?
		local f = finale
		if not f then
			return nil
		end
		local since = t - f.T0
		local focus = Vector3.new(shown.X, floorY + 9, shown.Z)
		if f.Kind == "Victory" then
			local angle = 0.8 + since * 0.45
			local distance = 58 + since * 3
			local eye = focus + dir(angle) * distance + Vector3.new(0, 30 - since * 1.5, 0)
			return CFrame.lookAt(eye, focus)
		end
		-- Defeat: a slow push in on the eye.
		local front = dir(shown.F) * (62 - math.min(since, 4) * 6)
		local eye = focus + front + Vector3.new(14, 12, 6) * (1 - math.min(since, 4) / 6)
		return CFrame.lookAt(eye, focus)
	end

	RunService:BindToRenderStep("BigBadVacuumCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local t = now()
		-- Scripted shots: the flyover (everyone is frozen for the 3-2-1) and the finale.
		local pose = finalePose(t) or flyoverPose(t)
		if pose then
			if camMode == "Normal" then
				camMode = "Scripted"
				camera.CameraType = Enum.CameraType.Scriptable
			end
			camera.CFrame = pose
		elseif camMode ~= "Normal" then
			restoreCamera()
		end
		if State.Phase() == "Results" or State.Phase() == "Cleanup" then
			restoreCamera()
		end
		-- Shake and punch on top.
		if shakeAmount > 0.01 then
			local a = shakeAmount
			camera.CFrame = camera.CFrame
				* CFrame.new((math.random() - 0.5) * a * 0.9, (math.random() - 0.5) * a * 0.9, 0)
				* CFrame.Angles(
					math.rad((math.random() - 0.5) * a * 1.4),
					math.rad((math.random() - 0.5) * a * 1.4),
					math.rad((math.random() - 0.5) * a * 0.9)
				)
			shakeAmount *= math.exp(-5.5 * dt)
		end
		punch *= math.exp(-6 * dt)
		camera.FieldOfView = baseFov + punch
	end)

	-- The frame loop ------------------------------------------------------------------------------------------------------------------------------
	local systems: { { Name: string, Fn: (t: number, dt: number) -> (), Errors: number } } = {}
	local function system(name: string, fn: (t: number, dt: number) -> ())
		table.insert(systems, { Name = name, Fn = fn, Errors = 0 })
	end
	local warning: Part? = nil
	system("build", function()
		buildBoss()
	end)
	system("pose", updatePose)
	system("boss", drawBoss)
	system("ambient", function(t)
		ambientBoss(t)
	end)
	system("arm", drawArm)
	system("bag", drawBag)
	system("cord", drawCord)
	system("suction", drawSuction)
	system("markers", function(t)
		for index = #markers, 1, -1 do
			local marker = markers[index]
			local alive = marker.Update(t)
			if not alive then
				marker.Destroy()
				table.remove(markers, index)
			end
		end
	end)
	system("rings", function(t)
		updateRings(t)
	end)
	system("bricks", function(t)
		drawCarried(t)
		updateFlights(t)
		drawPiles(t)
	end)
	system("landing", function(t)
		-- The warning on the floor while the boss falls: a growing red disc under it.
		local since = t - goTime()
		local falling = boss ~= nil and boss.S == "Intro" and since < LAND_AT
		if falling and not warning then
			warning = newPart({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.14, 1, 1),
				Color = DANGER,
				Transparency = 0.5,
				Parent = world,
			})
		end
		local disc = warning
		if disc then
			if falling then
				local p = clamp01(since / LAND_AT)
				local size = 14 + 34 * p
				disc.Size = Vector3.new(0.14, size, size)
				disc.CFrame = CFrame.new(centerX, floorY + 0.6, centerZ) * CFrame.Angles(0, 0, math.rad(90))
				disc.Transparency = 0.7 - 0.35 * p + 0.15 * math.sin(t * 20)
			else
				disc:Destroy()
				warning = nil
			end
		end
		if boss and boss.S == "Intro" and since > 0.2 and since < 0.6 and bannerLabel.Text == "" then
			callout("INCOMING!", DANGER, "Clear the middle!", 2.6, 5)
		end
	end)
	system("finale", function(t)
		drawFinale(t)
	end)
	system("hud", updateHud)
	system("player", updatePlayerState)
	api:RenderStep(function(dt)
		local t = now()
		for _, entry in systems do
			if entry.Errors < 3 then
				local ok, err = pcall(entry.Fn, t, dt)
				if not ok then
					entry.Errors += 1
					warn(`[BigBadVacuum] {entry.Name}: {err}`)
				end
			end
		end
	end)

	local _ = mvpName
end

return BigBadVacuum

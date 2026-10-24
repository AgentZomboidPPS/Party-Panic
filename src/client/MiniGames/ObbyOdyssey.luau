-- Client half of Obby Odyssey: the moving parts of the course and the race HUD.
--
-- The swinging balls, the spinning bars and the blinking blocks all follow the shared schedule (MG_Course:
-- the arena's origin and the schedule's epoch, with Shared/Logic/ObbyOdyssey's numbers), so they're in
-- the same place on every screen and where the server judges them. A blinking block also stops holding
-- this player up the moment it's gone on their own screen (it turns see-through and non-solid here); it
-- flashes for its last BlinkWarn seconds first, and a faint ghost shows where it comes back.
--
-- HUD (phones first, everything under the round banner and clear of the thumbstick's corner): a race
-- strip with every runner's numbered dot from the start to the 👑 (riders side by side step above and
-- below the line: Logic/RaceBar, the checkpoints as ticks) and one line under it, your place and your
-- checkpoints. The server's toasts say each checkpoint (and the section after it), a splash back to one,
-- and the crown; here they get their sound and sparkle. Pads you've reached turn gold.
--
-- Fun pass (owner: "Make sure this is super sick and actually super fun."): the round's shuffle
-- (Course.Setup with MG_Course's seed); this player's launch-pad flights (stepping on a pad flies the
-- character on the pad's arc with a front flip, the same flight the server gives the bots, and tells the
-- server); the springs bouncing whenever anyone takes off; the barrels rolling across the pyramid; BONK!
-- WHACK! POW! over whoever a hazard hits, a splash of water or a flare of lava where someone falls in;
-- confetti at each checkpoint; the start gate lifting at GO; bobbing balloons; and the crown flying off the
-- summit onto the winner's head, to wear for the rest of the round.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Course = require(ReplicatedStorage.Shared.Logic.ObbyOdyssey)
local RaceBar = require(ReplicatedStorage.Shared.Logic.RaceBar)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ObbyOdyssey = {}

local CLOCK_TIME = 13.5 -- a bright midday for the round, put back afterwards
local GOLD = Color3.fromRGB(255, 204, 64)
local WORN_SCALE = 0.28 -- the crown on the winner's head
local HIT_WORDS = {
	Ball = { "BONK!", Color3.fromRGB(255, 90, 90) },
	Bar = { "WHACK!", Color3.fromRGB(255, 170, 60) },
	Barrel = { "POW!", Color3.fromRGB(255, 220, 80) },
}
-- A ball's shadow on the bridge: faint and dark while it's over heads, red once its middle is low
-- enough to hit someone (it hangs 5 over the bridge at the bottom of its swing, 13 at the ends).
local SHADOW_HIGH, SHADOW_LOW = 11, 6.5 -- studs over the bridge: starts turning red, fully red
local SHADOW_DARK, SHADOW_DANGER = Color3.fromRGB(20, 10, 30), Color3.fromRGB(230, 30, 60)
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local function ease(a: number): number
	local u = math.clamp(a, 0, 1)
	return u * u * (3 - 2 * u)
end

type Mover = { Parts: { BasePart }, Offsets: { CFrame } }

-- A model's parts and where each sits from `base` (its pose as the server built it).
local function moverFor(model: Instance, base: CFrame): Mover
	local mover = { Parts = {}, Offsets = {} }
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(mover.Parts, item)
			table.insert(mover.Offsets, base:ToObjectSpace(item.CFrame))
		end
	end
	return mover
end

function ObbyOdyssey.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 252, 244),
		Saturation = 0.2,
		Contrast = 0.06,
	})
	local clockTime = Lighting.ClockTime
	Lighting.ClockTime = CLOCK_TIME
	api:Track(function()
		Lighting.ClockTime = clockTime
	end)

	local myKey = tostring(Players.LocalPlayer.UserId)
	local touch = api:IsTouch()

	local origin: Vector3? = nil
	local epoch = api:Now()
	local appliedSeed: number? = nil
	local riders: { [string]: { L: number, C: Color3, N: string } } = {}
	local function readCourse()
		local value = api:SharedJSON("Course")
		if type(value) ~= "table" or type(value.O) ~= "table" then
			return
		end
		origin = Vector3.new(value.O[1], value.O[2], value.O[3])
		epoch = tonumber(value.E) or epoch
		local seed = tonumber(value.S)
		if seed and seed ~= appliedSeed then
			appliedSeed = seed
			Course.Setup(seed) -- (this round's shuffle, as on the server)
		end
		for _, entry in value.Riders or {} do
			local c = entry.C or { 255, 255, 255 }
			riders[tostring(entry.U)] = { L = entry.L or 1, C = Color3.fromRGB(c[1], c[2], c[3]), N = entry.N or "" }
		end
	end
	readCourse()
	api:OnShared("Course", readCourse)

	local snapshot: { T: number, R: { [string]: any } } = { T = 0, R = {} }
	local function readRunners()
		local value = api:SharedJSON("Runners")
		if type(value) == "table" and type(value.R) == "table" then
			snapshot = value
		end
	end
	readRunners()
	api:OnShared("Runners", readRunners)

	-- The moving parts, found as the arena arrives ------------------------------------------------------

	local arena = api:Arena(20)
	local balls: { { Spec: Course.Ball, Mover: Mover, Shadow: BasePart } } = {}
	local bars: { { Spec: Course.Spinner, Mover: Mover } } = {}
	local blinks: { { Piece: Course.Piece, Parts: { BasePart }, Shown: string? } } = {}
	local glows: { { Part: BasePart, Checkpoint: number, Lit: boolean } } = {}
	local crown: Mover? = nil
	local crownModel: Model? = nil
	local springs: { [string]: { Mover: Mover, Base: CFrame, At: number } } = {}
	local gate: { Mover: Mover, Base: CFrame, Lift: number? }? = nil
	local balloons: { { Mover: Mover, Base: CFrame, Phase: number } } = {}
	local found: { [Instance]: boolean } = {}
	local piecesById: { [string]: Course.Piece } = {}
	for _, piece in Course.Pieces do
		piecesById[piece.Id] = piece
	end
	local ballsById: { [string]: Course.Ball } = {}
	for _, ball in Course.Balls do
		ballsById[ball.Id] = ball
	end

	local function scan()
		local o = origin
		if not arena or not o then
			return
		end
		local folder = arena:FindFirstChild("Balls")
		for _, model in if folder then folder:GetChildren() else {} do
			local spec = ballsById[model.Name]
			if spec and not found[model] and #model:GetChildren() >= 4 then
				found[model] = true
				local hinge = CFrame.new(o + Vector3.new(spec.X, spec.PivotY, spec.Z))
				-- Its shadow on the bridge, darker and redder as it swings low enough to hit (owner:
				-- "the swinging balls on the OBBY obstacle is too hard for players on mobile"): where
				-- it'll be is easy to read from any angle, even looking straight down at the runner.
				local shadow = Instance.new("Part")
				shadow.Name = "BallShadow"
				shadow.Shape = Enum.PartType.Cylinder
				shadow.Anchored = true
				shadow.CanCollide = false
				shadow.CanQuery = false
				shadow.CanTouch = false
				shadow.CastShadow = false
				shadow.Material = Enum.Material.SmoothPlastic
				shadow.Size = Vector3.new(0.05, spec.Radius * 2, spec.Radius * 2)
				shadow.Transparency = 1
				shadow.Parent = arena
				api:Track(shadow)
				table.insert(balls, { Spec = spec, Mover = moverFor(model, hinge), Shadow = shadow })
			end
		end
		folder = arena:FindFirstChild("Bars")
		for _, model in if folder then folder:GetChildren() else {} do
			local index = model:GetAttribute("Spinner")
			local spec = if type(index) == "number" then Course.Spinners[index] else nil
			if spec and not found[model] and #model:GetChildren() >= 9 then
				found[model] = true
				local center = CFrame.new(o + Vector3.new(spec.X, spec.Top + spec.BarY, spec.Z))
				table.insert(bars, { Spec = spec, Mover = moverFor(model, center) })
			end
		end
		folder = arena:FindFirstChild("Blinks")
		for _, part in if folder then folder:GetChildren() else {} do
			local piece = piecesById[part.Name]
			if piece and part:IsA("BasePart") and not found[part] then
				found[part] = true
				local parts = { part }
				for _, item in part:GetDescendants() do
					if item:IsA("BasePart") then
						table.insert(parts, item)
					end
				end
				table.insert(blinks, { Piece = piece, Parts = parts, Shown = nil })
			end
		end
		folder = arena:FindFirstChild("Pads")
		for _, part in if folder then folder:GetChildren() else {} do
			local checkpoint = part:GetAttribute("Checkpoint")
			if part:IsA("BasePart") and part.Name == "Glow" and type(checkpoint) == "number" and not found[part] then
				found[part] = true
				table.insert(glows, { Part = part, Checkpoint = checkpoint, Lit = false })
			end
		end
		local model = arena:FindFirstChild("Crown")
		if model and not crown and not crownModel and #model:GetChildren() >= 30 then
			local summit = Course.Summit
			crown = moverFor(model, CFrame.new(o + Vector3.new(summit.X, summit.Top + 8.5, summit.Z)))
			crownModel = model :: Model
		end
		folder = arena:FindFirstChild("Springs")
		for _, spring in if folder then folder:GetChildren() else {} do
			local padId = spring:GetAttribute("Pad")
			local plate = spring:FindFirstChild("Plate") :: BasePart?
			if type(padId) == "string" and plate and not found[spring] then
				found[spring] = true
				springs[padId] = { Mover = moverFor(spring, plate.CFrame), Base = plate.CFrame, At = -math.huge }
			end
		end
		local gateModel = arena:FindFirstChild("Gate")
		if gateModel and not gate and #gateModel:GetChildren() >= 10 then
			local first = gateModel:GetChildren()[1] :: BasePart
			local base = CFrame.new(first.Position)
			gate = { Mover = moverFor(gateModel, base), Base = base }
		end
		folder = arena:FindFirstChild("Balloons")
		for index, bunch in if folder then folder:GetChildren() else {} do
			local first = bunch:FindFirstChild("Balloon") :: BasePart?
			if first and not found[bunch] and #bunch:GetChildren() >= 4 then
				found[bunch] = true
				local base = CFrame.new(first.Position)
				table.insert(balloons, { Mover = moverFor(bunch, base), Base = base, Phase = index * 1.7 })
			end
		end
	end
	local scanned = 0

	-- HUD ------------------------------------------------------------------------------------------------

	local hud = api:TopHud()
	local hudY = api:HudY()
	local barWidth = 560
	local trackLength = barWidth - 70
	local DOT = if touch then 30 else 18
	local MY_DOT = if touch then 36 else 26
	local LIFT = if touch then 15 else 9
	local barHeight = if touch then 60 else 36
	local bar = UIKit.Panel({
		Name = "RaceBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY + 4),
		Size = UDim2.fromOffset(barWidth, barHeight),
		CornerRadius = 15,
		Parent = hud,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local lane = UIKit.new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, -6, 0.5, 0),
		Size = UDim2.new(1, -70, 0, 8),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = bar,
		Children = { UIKit.Round() },
	})
	-- The checkpoints along the strip: small ticks with their number.
	for index, pad in Course.Checkpoints do
		local x, y, z = Course.RowMiddle(pad.Row)
		local at = Course.Progress(pad.Row, x, y, z) / Course.Length
		UIKit.new("Frame", {
			Name = `Tick{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(at, 0.5),
			Size = UDim2.fromOffset(4, if touch then 22 else 16),
			BackgroundColor3 = Theme.Colors.TextDim,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Parent = lane,
		})
	end
	UIKit.Label({
		Name = "Goal",
		Text = "👑",
		TextSize = if touch then 26 else 22,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 6, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		Parent = lane,
	})
	local markers: { [string]: Frame } = {}
	local myGlow: Frame? = nil
	local function marker(key: string): Frame
		local existing = markers[key]
		if existing then
			return existing
		end
		local info = riders[key]
		local isMine = key == myKey
		local size = if isMine then MY_DOT else DOT
		local dot = UIKit.new("Frame", {
			Name = "Runner" .. key,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = if info then info.C else Theme.Colors.Text,
			ZIndex = if isMine then 5 else 3,
			Parent = lane,
			Children = {
				UIKit.Round(),
				if isMine
					then UIKit.Stroke(Theme.Colors.Text, if touch then 4 else 3, 0)
					else UIKit.Stroke(Theme.Colors.PanelDark, 2, 0.3),
			},
		})
		if isMine then
			myGlow = UIKit.new("Frame", {
				Name = "MyGlow",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(size + 10, size + 10),
				BackgroundColor3 = Theme.Colors.Text,
				BackgroundTransparency = 0.55,
				ZIndex = 2,
				Parent = lane,
				Children = { UIKit.Round() },
			})
		end
		UIKit.Label({
			Text = tostring(if info then info.L else "?"),
			TextSize = if touch then (if isMine then 26 else 24) else (if isMine then 16 else 12),
			Font = Theme.Fonts.Bold,
			TextColor3 = Color3.fromRGB(30, 24, 40),
			Size = UDim2.fromScale(1, 1),
			ZIndex = dot.ZIndex,
			Parent = dot,
		})
		markers[key] = dot
		return dot
	end

	local placeY = hudY + barHeight + 8
	local placeLabel = UIKit.Label({
		Name = "Place",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, placeY),
		Size = UDim2.fromOffset(320, 32),
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})
	-- Cues from the server ------------------------------------------------------------------------------

	local reduced = State.ReducedEffects()

	-- A word that pops over a spot and floats up (BONK!, WHEEE!).
	local function popWord(position: Vector3, text: string, color: Color3)
		local o = origin
		if not o then
			return
		end
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - position).Magnitude > 160 then
			return
		end
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.CFrame = CFrame.new(position)
		holder.Parent = api.World
		local board = Instance.new("BillboardGui")
		board.Size = UDim2.fromScale(7, 2.4)
		board.StudsOffset = Vector3.new(0, 1, 0)
		board.AlwaysOnTop = true
		board.LightInfluence = 0
		board.MaxDistance = 160
		board.Parent = holder
		local label = UIKit.Label({
			Text = text,
			Font = Theme.Fonts.Display,
			TextScaled = true,
			TextColor3 = color,
			Size = UDim2.fromScale(1, 1),
			Rotation = math.random(-12, 12),
			Parent = board,
			Children = { UIKit.TextStroke(0) },
		})
		TweenService:Create(board, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			StudsOffset = Vector3.new(0, 4, 0),
		}):Play()
		TweenService
			:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.45), {
				TextTransparency = 1,
			})
			:Play()
		task.delay(1, function()
			holder:Destroy()
		end)
	end

	-- A burst where someone falls in: a splash of water, or a flare of lava and smoke.
	local function burst(position: Vector3, lava: boolean)
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - position).Magnitude > 260 then
			return
		end
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.CFrame = CFrame.new(position)
		holder.Parent = api.World
		local drops = Instance.new("ParticleEmitter")
		drops.Texture = if lava then SPARK else SMOKE
		drops.Color = if lava
			then ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 70, 20))
			else ColorSequence.new(Color3.fromRGB(235, 250, 255), Color3.fromRGB(120, 200, 255))
		drops.LightEmission = if lava then 1 else 0.2
		drops.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0.4) })
		drops.Transparency = NumberSequence.new(0.1, 1)
		drops.Lifetime = NumberRange.new(0.7, 1.1)
		drops.Speed = NumberRange.new(16, 30)
		drops.SpreadAngle = Vector2.new(22, 22)
		drops.EmissionDirection = Enum.NormalId.Top
		drops.Acceleration = Vector3.new(0, -70, 0)
		drops.Drag = 1
		drops.Enabled = false
		drops.Parent = holder
		drops:Emit(if reduced then 8 else 26)
		if lava then
			local smoke = Instance.new("ParticleEmitter")
			smoke.Texture = SMOKE
			smoke.Color = ColorSequence.new(Color3.fromRGB(90, 80, 80))
			smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) })
			smoke.Transparency = NumberSequence.new(0.35, 1)
			smoke.Lifetime = NumberRange.new(1, 1.6)
			smoke.Speed = NumberRange.new(4, 9)
			smoke.SpreadAngle = Vector2.new(30, 30)
			smoke.EmissionDirection = Enum.NormalId.Top
			smoke.Enabled = false
			smoke.Parent = holder
			smoke:Emit(if reduced then 3 else 10)
		end
		task.delay(2.5, function()
			holder:Destroy()
		end)
	end

	local function near(position: Vector3, range: number): boolean
		local camera = workspace.CurrentCamera
		return camera ~= nil and (camera.CFrame.Position - position).Magnitude < range
	end

	-- Cues from the server ------------------------------------------------------------------------------

	local myStage = 0
	local crownWinner: number? = nil
	local crownTakenAt = 0
	local worn: Model? = nil
	local wornScale = 1
	api:OnEvent("Checkpoint", function(stage: number)
		if type(stage) ~= "number" then
			return
		end
		myStage = math.max(myStage, stage)
		api:Sound("Pickup")
		local _, _, root = api:Character()
		if root then
			api:Effect("Confetti", root.Position + Vector3.new(0, 2, 0))
		end
	end)
	api:OnEvent("Splash", function(userId: number, x: number, z: number, lava: boolean)
		local o = origin
		if not o or type(x) ~= "number" or type(z) ~= "number" then
			return
		end
		local position = o + Vector3.new(x, 0.3, z)
		burst(position, lava == true)
		if tostring(userId) == myKey or near(position, 70) then
			api:Sound("Splash")
		end
	end)
	api:OnEvent("Bonk", function(userId: number, x: number, y: number, z: number, kind: string)
		local o = origin
		if not o or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
			return
		end
		local position = o + Vector3.new(x, y + 2, z)
		api:Effect("Stars", position)
		local word = HIT_WORDS[kind] or HIT_WORDS.Ball
		popWord(position + Vector3.new(0, 2, 0), word[1], word[2])
		if tostring(userId) == myKey then
			api:Sound("Hit")
			api:Sound("Boing")
		elseif near(position, 60) then
			api:Sound("Boing")
		end
	end)
	api:OnEvent("Launched", function(userId: number, padId: string)
		local spring = if type(padId) == "string" then springs[padId] else nil
		if spring then
			spring.At = os.clock()
		end
		local character = api:CharacterOf(userId)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and tostring(userId) ~= myKey then
			popWord(root.Position + Vector3.new(0, 3, 0), "WHEEE!", Color3.fromRGB(110, 230, 255))
			if near(root.Position, 70) then
				api:Sound("Boing")
			end
		end
	end)
	api:OnEvent("Finish", function(userId: number, place: number, time: number)
		if type(place) ~= "number" or type(time) ~= "number" or type(userId) ~= "number" then
			return
		end
		local o = origin
		local character = api:CharacterOf(userId)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			api:Effect(if place == 1 then "Finale" else "Confetti", root.Position)
		elseif o then
			local summit = Course.Summit
			api:Effect("Confetti", o + Vector3.new(summit.X, summit.Top + 3, summit.Z))
		end
		if place == 1 and not crownWinner then
			crownWinner = userId -- the crown flies off the summit onto their head
			crownTakenAt = os.clock()
		end
		if tostring(userId) == myKey then
			myStage = #Course.Checkpoints
			api:Sound("Victory")
		end
	end)

	-- This player's launch-pad flight: on the pad's arc with a front flip, then let go on the landing.
	local flight: { Pad: Course.Piece, From: Vector3, To: Vector3, Start: number, Character: Model }? = nil
	local function fly(humanoid: Humanoid, root: BasePart, o: Vector3)
		local current = flight
		if not current then
			return
		end
		if current.Character ~= humanoid.Parent or humanoid.Health <= 0 then
			flight = nil
			return
		end
		local launch = current.Pad.Launch :: Course.Launch
		local u = math.clamp((os.clock() - current.Start) / launch.Time, 0, 1)
		local from, to = current.From, current.To
		local x, y, z = Course.FlightAt(launch, from.X, from.Y, from.Z, to.X, to.Y, to.Z, u)
		local lift = if humanoid.RigType == Enum.HumanoidRigType.R15 then humanoid.HipHeight + root.Size.Y / 2 else 3
		local position = o + Vector3.new(x, y + lift, z)
		local heading = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
		local facing = if heading.Magnitude > 0.1 then heading.Unit else Vector3.zAxis
		humanoid.PlatformStand = true
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		if u < 1 then
			root.CFrame = CFrame.lookAt(position, position + facing) * CFrame.Angles(-math.pi * 2 * ease(u), 0, 0)
			return
		end
		root.CFrame = CFrame.lookAt(position, position + facing)
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		flight = nil
	end

	-- Every frame -----------------------------------------------------------------------------------------

	local shown: { [string]: number } = {}
	local dotTiers: { [string]: number } = {}
	local dotRanks: { [string]: number } = {}
	local dotShifts: { [string]: { X: number, Y: number } } = {}
	local lastPlace = ""
	local moveParts: { BasePart } = {}
	local moveFrames: { CFrame } = {}
	local barrelTemplate: Model? = nil
	local barrelPool: { Model } = {}
	local barrelsShown: { [string]: Model } = {}
	task.spawn(function()
		local template = api:Template("ObbyOdysseyBarrel", 30)
		if template and template:IsA("Model") then
			barrelTemplate = template
		end
	end)

	api:RenderStep(function(dt)
		local o = origin
		if not o then
			return
		end
		scanned -= dt
		if scanned <= 0 then
			scanned = 0.5
			scan()
		end
		local t = api:Now() - epoch

		-- The balls swing, the bars turn and the crown spins: moved all at once.
		table.clear(moveParts)
		table.clear(moveFrames)
		local function place(mover: Mover, frame: CFrame)
			for index, part in mover.Parts do
				table.insert(moveParts, part)
				table.insert(moveFrames, frame * mover.Offsets[index])
			end
		end
		local bridgeTop = Course.Bridge.Top
		for _, entry in balls do
			local spec = entry.Spec
			local hinge = CFrame.new(o + Vector3.new(spec.X, spec.PivotY, spec.Z))
			place(entry.Mover, hinge * CFrame.Angles(0, 0, Course.BallAngle(spec, t)))
			local bx, by = Course.BallAt(spec, t)
			-- (0 swinging high over heads, 1 low enough to hit a runner)
			local low = math.clamp((bridgeTop + SHADOW_HIGH - by) / (SHADOW_HIGH - SHADOW_LOW), 0, 1)
			local shadow = entry.Shadow
			shadow.Color = SHADOW_DARK:Lerp(SHADOW_DANGER, low)
			shadow.Transparency = 0.82 - 0.4 * low
			local width = spec.Radius * (1.5 + 0.6 * low)
			shadow.Size = Vector3.new(0.05, width, width)
			table.insert(moveParts, shadow)
			table.insert(
				moveFrames,
				CFrame.new(o + Vector3.new(bx, bridgeTop + 0.06, spec.Z)) * CFrame.Angles(0, 0, math.rad(90))
			)
		end
		for _, entry in bars do
			local spec = entry.Spec
			local center = CFrame.new(o + Vector3.new(spec.X, spec.Top + spec.BarY, spec.Z))
			place(entry.Mover, center * CFrame.Angles(0, -Course.SpinnerAngle(spec, t), 0))
		end
		local summit = Course.Summit
		local crownAt = o + Vector3.new(summit.X, summit.Top + 8.5 + math.sin(t * 1.6) * 0.6, summit.Z)
		local crownMover = crown
		if crownMover then
			place(crownMover, CFrame.new(crownAt) * CFrame.Angles(0, t * 0.9, 0))
		end
		local now = os.clock()
		for _, spring in springs do
			local since = now - spring.At
			local squash = if since < 0.5 then -0.8 * math.sin(since / 0.5 * math.pi) * math.exp(-since * 3) else 0
			place(spring.Mover, spring.Base * CFrame.new(squash, 0, 0)) -- (the plate is a cylinder on its side: X is up)
		end
		local gateNow = gate
		if gateNow then
			local stage = api:Shared("Stage")
			local lift = if stage == "Race" or stage == "Done" then 1 else 0
			gateNow.Lift = (gateNow.Lift or 0) + (lift - (gateNow.Lift or 0)) * math.min(1, dt * 4)
			local up = (gateNow.Lift or 0) * 14
			place(gateNow.Mover, gateNow.Base * CFrame.new(0, up, 0) * CFrame.Angles(0, 0, (gateNow.Lift or 0) * 0.25))
		end
		for _, bunch in balloons do
			local bob = math.sin(t * 1.1 + bunch.Phase) * 1.2
			place(
				bunch.Mover,
				bunch.Base * CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, math.sin(t * 0.7 + bunch.Phase) * 0.08)
			)
		end
		if #moveParts > 0 then
			workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end

		-- The blinking blocks: solid, flashing, or a faint ghost you fall through.
		for _, entry in blinks do
			local solid, warning = Course.BlinkState(entry.Piece, t)
			local look = if not solid then "gone" elseif warning then (if t * 8 % 2 < 1 then "on" else "dim") else "on"
			if look ~= entry.Shown then
				entry.Shown = look
				for _, part in entry.Parts do
					part.Transparency = if look == "gone" then 0.86 elseif look == "dim" then 0.55 else 0
					part.CanCollide = look ~= "gone"
				end
			end
		end

		-- The barrels rolling across the pyramid (copies of the server's barrel, as many as are rolling).
		local template = barrelTemplate
		if template then
			local live = {}
			for _, barrel in Course.BarrelsAt(t) do
				local key = `{barrel.Track}:{barrel.Index}`
				live[key] = true
				local model = barrelsShown[key]
				if not model then
					model = table.remove(barrelPool) or template:Clone()
					barrelsShown[key] = model
				end
				local track = Course.BarrelTracks[barrel.Track]
				local roll = track.Way * barrel.Age * Course.BarrelSpeed / Course.BarrelRadius
				local frame = CFrame.new(o + Vector3.new(barrel.X, barrel.Y, barrel.Z))
					* CFrame.Angles(0, math.rad(90), 0)
					* CFrame.Angles(roll, 0, 0)
				local shown = model :: Model
				shown:PivotTo(frame)
				if shown.Parent ~= api.World then
					shown.Parent = api.World
				end
			end
			for key, model in barrelsShown do
				if not live[key] then
					barrelsShown[key] = nil
					model.Parent = nil
					table.insert(barrelPool, model)
				end
			end
		end

		-- The crown: off the summit and onto the winner's head, worn for the rest of the round.
		local winner = crownWinner
		local original = crownModel
		if winner and original then
			if not worn then
				local copy = original:Clone()
				for _, item in original:GetDescendants() do
					if item:IsA("BasePart") then
						item.LocalTransparencyModifier = 1
						item.Transparency = 1
					elseif item:IsA("Light") or item:IsA("ParticleEmitter") then
						(item :: any).Enabled = false
					end
				end
				crown = nil -- (the summit's crown stays put, hidden)
				copy.Parent = api.World
				worn = copy
			end
			local model = worn :: Model
			local character = api:CharacterOf(winner)
			local head = character and character:FindFirstChild("Head") :: BasePart?
			local a = ease((now - crownTakenAt) / 0.9)
			local scale = 1 + (WORN_SCALE - 1) * a
			if math.abs(scale - wornScale) > 0.005 then
				wornScale = scale
				model:ScaleTo(scale)
			end
			local target = if head then head.Position + Vector3.new(0, 1.3, 0) else crownAt
			local hop = 6 * math.sin(math.min(a, 1) * math.pi)
			local position = crownAt:Lerp(target, a) + Vector3.new(0, hop, 0)
			model:PivotTo(CFrame.new(position) * CFrame.Angles(0, t * (if a < 1 then 8 else 1.5), 0))
		end

		-- My own flight off a launch pad, or the take-off.
		local _, myHumanoid, myRoot = api:Character()
		if myHumanoid and myRoot then
			if flight then
				fly(myHumanoid, myRoot, o)
			elseif myHumanoid.Health > 0 and not myHumanoid.PlatformStand and api:CanAct() then
				local p = myRoot.Position - o
				local feet = (
					if myHumanoid.RigType == Enum.HumanoidRigType.R15
						then myRoot.Position.Y - myHumanoid.HipHeight - myRoot.Size.Y / 2
						else myRoot.Position.Y - 3
				) - o.Y
				local pad = Course.PieceAt(p.X, p.Z, feet, t)
				local mine = snapshot.R[myKey]
				if pad and pad.Launch and not (mine and mine.F) then
					local info = riders[myKey]
					local x1, y1, z1 = Course.LaunchLanding(pad, if info then info.L else 1)
					flight = {
						Pad = pad,
						From = Vector3.new(p.X, pad.Top, p.Z),
						To = Vector3.new(x1, y1, z1),
						Start = now,
						Character = myHumanoid.Parent :: Model,
					}
					api:Action("Launch", pad.Id)
					api:Sound("Boing")
					popWord(myRoot.Position + Vector3.new(0, 3, 0), "WHEEE!", Color3.fromRGB(110, 230, 255))
					local spring = springs[pad.Id]
					if spring then
						spring.At = now
					end
				end
			end
		end

		-- Pads I've reached glow gold.
		for _, glow in glows do
			local lit = myStage >= glow.Checkpoint
			if lit ~= glow.Lit then
				glow.Lit = lit
				glow.Part.Color = if lit then GOLD else Color3.fromRGB(90, 230, 120)
			end
		end

		-- The race strip and my place.
		local dots: { RaceBar.Dot } = {}
		local order = {}
		for key in riders do
			local data = snapshot.R[key]
			local dot = markers[key]
			if not data then
				if dot then
					dot.Visible = false
				end
				continue
			end
			local target = math.clamp((tonumber(data.P) or 0) / Course.Length, 0, 1)
			if data.F then
				target = 1
			end
			local current = shown[key] or target
			current += (target - current) * (1 - math.exp(-dt * 6))
			shown[key] = current
			dot = marker(key)
			dot.Visible = true
			local isMine = key == myKey
			table.insert(dots, {
				Key = key,
				X = current * trackLength,
				Size = if isMine then MY_DOT else DOT,
				Tier = dotTiers[key],
				Rank = dotRanks[key],
			})
			table.insert(
				order,
				{ Key = key, Score = if data.F then 1e6 - data.F else (tonumber(data.S) or 0) * 1e4 + (data.P or 0) }
			)
		end
		local spots = RaceBar.Layout(dots, { Width = trackLength, Lift = LIFT })
		local ease = 1 - math.exp(-dt * 30)
		for _, item in dots do
			local spot = spots[item.Key]
			dotTiers[item.Key] = spot.Tier
			dotRanks[item.Key] = spot.Rank
			local shift = dotShifts[item.Key]
			if shift then
				shift.X += (spot.X - item.X - shift.X) * ease
				shift.Y += (spot.Y - shift.Y) * ease
			else
				shift = { X = spot.X - item.X, Y = spot.Y }
				dotShifts[item.Key] = shift
			end
			local at = UDim2.new(0, item.X + shift.X, 0.5, shift.Y)
			markers[item.Key].Position = at
			if item.Key == myKey and myGlow then
				myGlow.Position = at
				myGlow.Visible = true
			end
		end
		table.sort(order, function(a, b)
			return a.Score > b.Score
		end)
		local placeText = ""
		for index, item in order do
			if item.Key == myKey then
				local data = snapshot.R[myKey]
				placeText = if data and data.F
					then `👑 {Course.Ordinal(data.F)} · {string.format("%.1f", data.T or 0)}s`
					else `{Course.Ordinal(index)} of {#order}`
			end
		end
		local mine = snapshot.R[myKey]
		if mine and type(mine.S) == "number" then
			myStage = math.max(myStage, mine.S)
		end
		if not (mine and mine.F) and placeText ~= "" then
			placeText ..= `  ·  🚩{myStage}/{#Course.Checkpoints}`
		end
		if placeText ~= lastPlace then
			lastPlace = placeText
			placeLabel.Text = placeText
		end
	end)
end

return ObbyOdyssey

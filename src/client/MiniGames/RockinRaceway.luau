-- Client half of Rockin' Raceway: every rider on a hobby horse bobbing round the fairground oval,
-- your own character seated and galloping on yours, the chase camera, the GALLOP and HOP buttons,
-- the carrot meter with its red line, and the race bar.
--
-- The oval and the panel rows come from MG_Layout (Shared/Logic/RockinRacewayTrack draws the same
-- track the server races on). Every rider's horse follows MG_Riders (distance and speed with the
-- server's time, extrapolated and eased so it never jumps). Your own horse is also ridden here with
-- the same rules (Track.Ride) from the server's last snapshot and the GALLOP you're holding right
-- now, so your carrot meter and speed answer your thumb at once; the server's next snapshot pulls
-- it back where the server has it. A HOP shows at once and is sent with the moment you pressed it,
-- which is what the server judges hurdles by.
--
-- Every rider's character (players and bots, via api:CharacterOf) is set onto its horse here each
-- frame and posed galloping (legs swinging with the pace, hands on the stick); your own is moved
-- for real, so the server and everyone else see you where you ride.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local RaceBar = require(ReplicatedStorage.Shared.Logic.RaceBar)
local Track = require(ReplicatedStorage.Shared.Logic.RockinRacewayTrack)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local RockinRaceway = {}

local ROOT_Y = 3 -- a standing character's root above the ground
local COAST = 14 -- how far a finished rider rolls on past the line
local rad = math.rad

local JOINTS = {
	UpperTorso = "Waist",
	Head = "Neck",
	LeftUpperArm = "LeftShoulder",
	RightUpperArm = "RightShoulder",
	LeftLowerArm = "LeftElbow",
	RightLowerArm = "RightElbow",
	LeftUpperLeg = "LeftHip",
	RightUpperLeg = "RightHip",
	LeftLowerLeg = "LeftKnee",
	RightLowerLeg = "RightKnee",
	LeftFoot = "LeftAnkle",
	RightFoot = "RightAnkle",
}

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

-- A rider's pose: running with the hobby horse between the legs, both hands on the stick in front.
-- `phase` turns with the strides, `stride` 0..1 is how big they are, `air` tucks the legs in a hop,
-- `dizzy` throws the arms out in a spin-out, `cheer` waves after the finish.
local function ridePose(phase: number, stride: number, air: number, dizzy: boolean, cheer: boolean, t: number)
	local swing = math.sin(phase) * 38 * stride
	local knee = 30 * stride + 20
	local tuck = air * 50
	local armUp = if cheer then 150 + math.sin(t * 9) * 12 else 0
	return {
		Waist = angles(-10 * stride - 4, 0, 0),
		Neck = angles(6, 0, 0),
		LeftShoulder = if dizzy
			then angles(0, 0, -80 + math.sin(t * 14) * 20)
			elseif cheer then angles(0, 0, -armUp)
			else angles(52, 0, 10),
		RightShoulder = if dizzy
			then angles(0, 0, 80 - math.sin(t * 14) * 20)
			elseif cheer then angles(0, 0, armUp)
			else angles(52, 0, -10),
		LeftElbow = angles(if dizzy or cheer then 10 else 34, 0, 0),
		RightElbow = angles(if dizzy or cheer then 10 else 34, 0, 0),
		LeftHip = angles(swing + tuck, 0, -6),
		RightHip = angles(-swing + tuck, 0, 6),
		LeftKnee = angles(-knee * (0.5 + 0.5 * math.max(0, math.cos(phase))) - tuck, 0, 0),
		RightKnee = angles(-knee * (0.5 + 0.5 * math.max(0, -math.cos(phase))) - tuck, 0, 0),
		LeftAnkle = angles(10, 0, 0),
		RightAnkle = angles(10, 0, 0),
	}
end

type Shown = {
	D: number,
	V: number,
	Phase: number,
	Yaw: number,
	Model: Model?,
	Frame: CFrame?,
	Color: Color3,
	Lane: number,
	Name: string,
}

function RockinRaceway.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 248, 235),
		Saturation = 0.18,
		Contrast = 0.06,
		Brightness = 0.02,
		Haze = Color3.fromRGB(210, 230, 255),
		HazeDecay = Color3.fromRGB(170, 200, 240),
		Density = 0.22,
	})

	local myId = Players.LocalPlayer.UserId
	local myKey = tostring(myId)
	local camera = workspace.CurrentCamera
	local touch = api:IsTouch()
	local reduced = State.ReducedEffects()

	local originCF: CFrame? = nil
	local riders: { [string]: { L: number, C: Color3, N: string } } = {}
	local snapshot: { T: number, R: { [string]: any } } = { T = 0, R = {} }
	local shown: { [string]: Shown } = {}
	local stage = api:Shared("Stage") or "Ready"
	api:OnShared("Stage", function(value)
		stage = value or stage
	end)

	local function readLayout()
		local value = api:SharedJSON("Layout")
		if type(value) ~= "table" or type(value.O) ~= "table" then
			return
		end
		originCF = CFrame.new(value.O[1], value.O[2], value.O[3])
		for _, entry in value.Riders or {} do
			local c = entry.C or { 255, 255, 255 }
			riders[tostring(entry.U)] = { L = entry.L or 1, C = Color3.fromRGB(c[1], c[2], c[3]), N = entry.N or "" }
		end
	end
	readLayout()
	api:OnShared("Layout", readLayout)

	-- My own ride, predicted from the last snapshot with the GALLOP I'm holding now.
	local mine: Track.Rider? = nil
	local myHopAt = -math.huge
	local holding = false
	local function readRiders()
		local value = api:SharedJSON("Riders")
		if type(value) ~= "table" or type(value.R) ~= "table" then
			return
		end
		snapshot = { T = tonumber(value.T) or api:Now(), R = value.R }
		local entry = value.R[myKey]
		if entry then
			local now = api:Now()
			local rider: Track.Rider = {
				D = entry.D or 0,
				V = entry.V or 0,
				C = entry.C or Track.CARROTS,
				Gallop = entry.G == 1,
				SpinUntil = entry.S or 0,
				DashUntil = entry.Da or 0,
				SlowUntil = entry.Sl or 0,
			}
			-- Ride it on from the snapshot's moment to now with what I'm holding.
			local behind = math.clamp(now - snapshot.T, 0, 0.5)
			rider.Gallop = holding and not entry.F
			local steps = math.ceil(behind / (1 / 30))
			for _ = 1, steps do
				Track.Ride(rider, behind / steps, now - behind)
			end
			mine = rider
			if entry.H and entry.H > myHopAt + 0.05 then
				myHopAt = entry.H
			end
		else
			mine = nil
		end
	end
	readRiders()
	api:OnShared("Riders", readRiders)

	-- Horses -----------------------------------------------------------------------------------------

	local template = nil :: Instance?
	task.spawn(function()
		template = api:Template("RockinRacewayHorse", 30)
	end)
	local function horseFor(key: string, info): Model?
		local entry = shown[key]
		if entry and entry.Model then
			return entry.Model
		end
		if not template then
			return nil
		end
		local model = (template :: Instance):Clone() :: Model
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				if part.Name == "Body" then
					part.Color = info.C
				end
			end
		end
		model.Name = "Horse_" .. key
		model.Parent = api.World
		if entry then
			entry.Model = model
		end
		return model
	end

	-- Posing riders -----------------------------------------------------------------------------------

	local rigs: { [Model]: { [string]: { Motor: Motor6D, Current: CFrame } } } = {}
	local posed: { [Model]: string } = {}
	local function rigOf(character: Model)
		local rig = rigs[character]
		if rig then
			return rig
		end
		rig = {}
		for partName, motorName in JOINTS do
			local part = character:FindFirstChild(partName)
			local motor = part and part:FindFirstChild(motorName)
			if motor and motor:IsA("Motor6D") then
				rig[motorName] = { Motor = motor, Current = CFrame.identity }
			end
		end
		rigs[character] = rig
		return rig
	end
	local function unpose(character: Model)
		local rig = rigs[character]
		if rig then
			for _, joint in rig do
				joint.Motor.Transform = CFrame.identity
			end
		end
		rigs[character] = nil
		posed[character] = nil
	end
	local poseConnection = (RunService :: any).PreSimulation or RunService.Stepped
	api:Track(poseConnection:Connect(function(dt)
		local now = api:Now()
		local step = if type(dt) == "number" then dt else 1 / 60
		local alpha = 1 - math.exp(-step * 18)
		for character, key in posed do
			if not character.Parent then
				posed[character] = nil
				rigs[character] = nil
				continue
			end
			local entry = shown[key]
			local data = snapshot.R[key]
			if not entry or not data then
				continue
			end
			local spinning = data.S ~= nil and now < data.S
			local hopAt = if key == myKey then myHopAt else (data.H or -math.huge)
			local air = math.clamp(Track.HopHeight(now - hopAt) / Track.HOP_HEIGHT, 0, 1)
			local stride = math.clamp(entry.V / Track.GALLOP, 0, 1)
			local target = ridePose(entry.Phase, stride, air, spinning, data.F ~= nil, now)
			for name, joint in rigOf(character) do
				joint.Current = joint.Current:Lerp(target[name] or CFrame.identity, alpha)
				joint.Motor.Transform = joint.Current
			end
		end
	end))

	-- HUD ----------------------------------------------------------------------------------------------

	local hud = api:TopHud()
	local hudY = api:HudY()
	local barWidth = 560
	local trackLength = barWidth - 64
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
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -64, 0, 8),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = bar,
		Children = { UIKit.Round() },
	})
	UIKit.Label({
		Name = "Goal",
		Text = "🏁",
		TextSize = if touch then 24 else 22,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 4, 0.5, 0),
		Size = if touch then UDim2.fromOffset(28, 28) else UDim2.fromOffset(26, 26),
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
			Name = "Rider" .. key,
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

	-- The carrot meter: a bar of carrots, the left quarter red (the red line).
	-- (on phones the meter and what's under it sit right of the middle, clear of the thumbstick zone)
	local shiftX = if touch then 100 else 0
	local meterWidth = 340
	local meterHeight = if touch then 44 else 34
	local meterY = hudY + barHeight + 10
	local meter = UIKit.Panel({
		Name = "Carrots",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, shiftX, 0, meterY),
		Size = UDim2.fromOffset(meterWidth, meterHeight),
		CornerRadius = 12,
		Parent = hud,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local icon = if touch then 40 else 32
	local well = UIKit.new("Frame", {
		Name = "Well",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, icon + 8, 0.5, 0),
		Size = UDim2.new(1, -(icon + 16), 1, -12),
		BackgroundColor3 = Theme.Colors.PanelDark,
		ClipsDescendants = true,
		Parent = meter,
		Children = { UIKit.new("UICorner", { CornerRadius = UDim.new(0, 8) }) },
	})
	UIKit.new("Frame", {
		Name = "RedZone",
		Size = UDim2.fromScale(Track.RED / Track.CARROTS, 1),
		BackgroundColor3 = Color3.fromRGB(150, 30, 45),
		Parent = well,
		Children = { UIKit.new("UICorner", { CornerRadius = UDim.new(0, 8) }) },
	})
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Orange,
		ZIndex = 2,
		Parent = well,
		Children = { UIKit.new("UICorner", { CornerRadius = UDim.new(0, 8) }) },
	})
	UIKit.new("Frame", {
		Name = "RedLine",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(Track.RED / Track.CARROTS, 0),
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = Theme.Colors.Text,
		ZIndex = 3,
		Parent = well,
	})
	local meterText = UIKit.Label({
		Name = "MeterText",
		Text = "CARROTS",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 26 else 20,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = well,
		Children = { UIKit.TextStroke(0.1) },
	})
	UIKit.Label({
		Name = "CarrotIcon",
		Text = "🥕",
		TextSize = if touch then 30 else 24,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(icon, icon),
		Parent = meter,
	})

	local placeLabel = UIKit.Label({
		Name = "Place",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 30 else 30,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, shiftX, 0, meterY + meterHeight + 6),
		Size = UDim2.fromOffset(300, 36),
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})
	local callout = UIKit.Label({
		Name = "Callout",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 34 else 40,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, shiftX, 0, meterY + meterHeight + 44),
		Size = UDim2.fromOffset(if touch then 360 else 520, 46),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})
	local calloutUntil = 0
	local function say(text: string, color: Color3, seconds: number)
		callout.Text = text
		callout.TextColor3 = color
		callout.Visible = true
		calloutUntil = os.clock() + seconds
	end

	-- Controls ---------------------------------------------------------------------------------------

	local gallop = api:Button({ Text = "GALLOP", Key = Enum.KeyCode.W, Color = Theme.Colors.Orange, Slot = 1 })
	-- (GALLOP is the longest label: it shrinks to fit instead of wrapping onto two lines)
	local gallopHolder = api.Gui:FindFirstChild("Action_GALLOP")
	local gallopLabel = gallopHolder and gallopHolder:FindFirstChildWhichIsA("TextLabel", true)
	if gallopLabel then
		gallopLabel.TextWrapped = false
		gallopLabel.Size = UDim2.fromScale(0.96, 0.5) -- (a little wider than the usual 0.86)
	end
	local hop = api:Button({ Text = "HOP", Key = Enum.KeyCode.Space, Color = Theme.Colors.Cyan, Slot = 2 })
	local function racing(): boolean
		local entry = snapshot.R[myKey]
		return stage == "Race" and entry ~= nil and entry.F == nil and api:CanAct()
	end
	local function setHolding(value: boolean)
		if value and not racing() then
			value = false
		end
		if value ~= holding then
			holding = value
			if mine then
				mine.Gallop = value
			end
			api:Action("Gallop", value)
		end
	end
	gallop.Pressed:Connect(function()
		setHolding(true)
	end)
	gallop.Released:Connect(function()
		setHolding(false)
	end)
	-- (the arrow up key and a held mouse button gallop too on PC)
	api:Track(UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Up then
			setHolding(true)
		end
	end))
	api:Track(UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Up and not gallop:IsDown() then
			setHolding(false)
		end
	end))
	local function doHop()
		local now = api:Now()
		if not racing() then
			return
		end
		if now < myHopAt + Track.HOP_TIME + Track.HOP_REST then
			return
		end
		local entry = snapshot.R[myKey]
		if entry and entry.S and now < entry.S then
			return
		end
		myHopAt = now
		api:Action("Hop", now)
		api:Sound("Boing")
	end
	hop.Pressed:Connect(doHop)
	api:Track(UserInputService.JumpRequest:Connect(doHop)) -- (Roblox's own jump button hops too)
	api:Track(function()
		if holding then
			holding = false
		end
	end)

	local shake = 0

	-- The carousel in the infield turns slowly (only drawn here; it decides nothing).
	local carousel: Model? = nil
	local carouselPivot: CFrame? = nil
	task.spawn(function()
		local arena = api:Arena(15)
		local found = arena and arena:FindFirstChild("Carousel", true)
		if found and found:IsA("Model") then
			carousel = found
			carouselPivot = found:GetPivot()
		end
	end)

	-- Events -------------------------------------------------------------------------------------------

	api:OnEvent("Panel", function(userId, _d, result)
		if userId ~= myId then
			return
		end
		if result == "dash" then
			say("🥕 DASH!", Theme.Colors.Orange, 1)
			api:Sound("Pickup")
			local entry = shown[myKey]
			if entry and entry.Frame then
				api:Effect("Sparkles", entry.Frame.Position + Vector3.new(0, 3, 0))
			end
		elseif result == "bump" then
			say("💥 BUMP! HOP the hurdles!", Theme.Colors.Cyan, 1.3)
			api:Sound("Hit")
			shake = math.max(shake, 0.25)
		elseif result == "clear" then
			say("✔ CLEAR!", Theme.Colors.Green, 0.8)
		elseif result == "miss" then
			say("Missed the carrot!", Theme.Colors.TextDim, 1)
		end
	end)
	api:OnEvent("Spin", function(userId)
		local entry = shown[tostring(userId)]
		if entry and entry.Frame then
			api:Effect("Stars", entry.Frame.Position + Vector3.new(0, 6, 0))
		end
		if userId == myId then
			say("💫 SPUN OUT! Let go sooner!", Theme.Colors.Red, 1.8)
			api:Sound("HazardWarning")
			shake = 0.4
		end
	end)
	api:OnEvent("Finish", function(userId, place)
		local entry = shown[tostring(userId)]
		if entry and entry.Frame and not reduced then
			api:Effect("Confetti", entry.Frame.Position + Vector3.new(0, 5, 0))
		end
		if userId == myId and type(place) == "number" then
			say(`🏁 {Track.Ordinal(place)} place!`, Theme.Colors.Yellow, 4)
			api:Sound(if place == 1 then "Victory" else "Pickup")
		end
	end)

	local hintShown = false
	local hintUntil = 0

	-- Camera ---------------------------------------------------------------------------------------------

	local cameraPosition: Vector3? = nil
	local cameraTaken = false
	local function releaseCamera()
		if cameraTaken then
			cameraTaken = false
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
			local _, humanoid = api:Character()
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end
	api:Track(function()
		releaseCamera()
		for character in table.clone(posed) do
			unpose(character)
		end
		local _, humanoid, root = api:Character()
		if humanoid then
			humanoid.PlatformStand = false
		end
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)

	-- Every frame ----------------------------------------------------------------------------------------

	local dotTiers: { [string]: number } = {}
	local dotRanks: { [string]: number } = {}
	local dotShifts: { [string]: { X: number, Y: number } } = {}
	local lastPlace = ""

	api:RenderStep(function(dt)
		local origin = originCF
		if not origin then
			return
		end
		dt = math.min(dt, 0.1)
		local now = api:Now()

		-- My own ride, carried on from the last snapshot.
		if mine then
			mine.Gallop = holding and racing()
			if stage == "Race" and not (snapshot.R[myKey] and snapshot.R[myKey].F) then
				Track.Ride(mine, dt, now)
			end
		end

		local dots: { RaceBar.Dot } = {}
		local order = {}
		for key, info in riders do
			local data = snapshot.R[key]
			local entry = shown[key]
			if not data then
				-- Left the round: hide the horse and the dot.
				if entry and entry.Model then
					entry.Model:Destroy()
					entry.Model = nil
				end
				local dot = markers[key]
				if dot then
					dot.Visible = false
				end
				continue
			end
			if not entry then
				entry = {
					D = data.D or 0,
					V = data.V or 0,
					Phase = math.random() * math.pi * 2,
					Yaw = 0,
					Model = nil,
					Frame = nil,
					Color = info.C,
					Lane = info.L,
					Name = info.N,
				}
				shown[key] = entry
			end
			local shownEntry = entry :: Shown
			-- Where to draw it: my own prediction, or the snapshot carried on to now.
			local target
			if data.E then
				local since = math.max(0, now - data.E)
				target = Track.LENGTH + COAST * (1 - math.exp(-since / 1.2))
				shownEntry.V = Track.TROT * math.exp(-since / 1.2)
			elseif key == myKey and mine then
				target = mine.D
				shownEntry.V = mine.V
			else
				target = (data.D or 0) + (data.V or 0) * math.clamp(now - snapshot.T, 0, 0.5)
				shownEntry.V += ((data.V or 0) - shownEntry.V) * (1 - math.exp(-dt * 8))
			end
			if stage == "Ready" then
				target = 0
			end
			local gap = target - shownEntry.D
			if math.abs(gap) > 25 then
				shownEntry.D = target
			else
				shownEntry.D += shownEntry.V * dt
				shownEntry.D += (target - shownEntry.D) * (1 - math.exp(-dt * 6))
			end
			shownEntry.Phase += dt * (2 + shownEntry.V * 0.42)

			-- The horse and its rider.
			local offset = Track.LaneOffset(info.L)
			local x, z, fx, fz = Track.At(shownEntry.D, offset)
			local hopAt = if key == myKey then myHopAt else (data.H or -math.huge)
			local lift = Track.HopHeight(now - hopAt)
			local bounce = if lift > 0
				then 0
				else math.abs(math.sin(shownEntry.Phase)) * 0.35 * math.clamp(shownEntry.V / 12, 0, 1)
			local spinning = data.S ~= nil and now < data.S
			local yaw = if spinning then (data.S - now) / Track.SPIN_TIME * math.pi * 4 else 0
			local position = origin.Position + Vector3.new(x, 0, z)
			local frame = CFrame.lookAt(position, position + Vector3.new(fx, 0, fz)) * CFrame.Angles(0, yaw, 0)
			shownEntry.Frame = frame
			local pitch = if lift > 0
				then -0.25 * (1 - 2 * math.clamp((now - hopAt) / Track.HOP_TIME, 0, 1))
				else math.sin(shownEntry.Phase * 1) * 0.07
			local horse = horseFor(key, info)
			if horse then
				horse:PivotTo(frame * CFrame.new(0, lift + bounce, 0) * CFrame.Angles(pitch, 0, 0))
			end
			local character = api:CharacterOf(tonumber(key))
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if character and root then
				if not posed[character] then
					posed[character] = key
				end
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				local rootY = if humanoid then humanoid.HipHeight + root.Size.Y / 2 else ROOT_Y
				if key == myKey then
					if humanoid and not humanoid.PlatformStand then
						humanoid.PlatformStand = true
					end
					root.AssemblyLinearVelocity = frame.LookVector * shownEntry.V
					root.AssemblyAngularVelocity = Vector3.zero
				end
				root.CFrame = frame * CFrame.new(0, rootY + lift + bounce * 0.8, 0)
			end

			local dot = marker(key)
			dot.Visible = true
			table.insert(dots, {
				Key = key,
				X = math.clamp(shownEntry.D / Track.LENGTH, 0, 1) * trackLength,
				Size = if key == myKey then MY_DOT else DOT,
				Tier = dotTiers[key],
				Rank = dotRanks[key],
			})
			table.insert(order, { Key = key, Score = if data.P then 1e6 - data.P else shownEntry.D })
		end

		-- The race bar (riders side by side step above and below the line: Logic/RaceBar).
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
		local place = ""
		for index, item in order do
			if item.Key == myKey then
				local data = snapshot.R[myKey]
				place = if data and data.P
					then `🏁 {Track.Ordinal(data.P)} · {string.format("%.1f", data.F or 0)}s`
					else `{Track.Ordinal(index)} of {#order}`
			end
		end
		if place ~= lastPlace then
			lastPlace = place
			placeLabel.Text = place
		end

		-- The carrot meter.
		local myData = snapshot.R[myKey]
		meter.Visible = myData ~= nil
		if mine and myData then
			local fraction = math.clamp(mine.C / Track.CARROTS, 0, 1)
			fill.Size = UDim2.fromScale(fraction, 1)
			local spinning = now < mine.SpinUntil
			local red = mine.C < Track.RED
			local text, color
			if myData.F then
				text, color = "🏁 HOME!", Theme.Colors.Green
			elseif spinning then
				text, color = "💫 DIZZY…", Theme.Colors.Red
			elseif red and holding then
				text, color = "EASE OFF!", Theme.Colors.Red
			elseif holding then
				text, color = "GALLOP!", Theme.Colors.Orange
			elseif mine.C >= Track.CARROTS - 0.5 then
				text, color = "FULL", Theme.Colors.Green
			else
				text, color = "MUNCHING…", Theme.Colors.Yellow
			end
			if red and holding and not spinning then
				local pulse = 0.5 + 0.5 * math.sin(now * 18)
				fill.BackgroundColor3 = Theme.Colors.Red:Lerp(Theme.Colors.Text, pulse * 0.4)
			elseif red then
				fill.BackgroundColor3 = Theme.Colors.Red
			else
				fill.BackgroundColor3 = Theme.Colors.Orange
			end
			if meterText.Text ~= text then
				meterText.Text = text
			end
			meterText.TextColor3 = if color == Theme.Colors.Orange then Theme.Colors.Text else color
			gallop:SetFill(if holding then 1 - fraction else 0, Theme.Colors.Text)
		end
		gallop:SetEnabled(racing())
		hop:SetEnabled(racing())

		if callout.Visible and os.clock() > calloutUntil then
			callout.Visible = false
		end
		if stage == "Race" and not hintShown then
			hintShown = true
			hintUntil = os.clock() + 5
			api:Hint(
				if touch
					then "Hold GALLOP · let go in the red! HOP the blue hurdles"
					else "Hold W to GALLOP · let go in the red! SPACE hops the blue hurdles"
			)
		end
		if hintUntil > 0 and os.clock() > hintUntil then
			hintUntil = -1
			api:Hint("")
		end

		if carousel and carouselPivot and carousel.Parent then
			carousel:PivotTo(carouselPivot * CFrame.Angles(0, now * 0.35, 0))
		end

		-- Chase camera behind my horse.
		local me = shown[myKey]
		if me and me.Frame and myData and api:Alive() then
			local x, z, fx, fz = Track.At(me.D, Track.LaneOffset(me.Lane))
			local position = origin.Position + Vector3.new(x, 0, z)
			local flat = CFrame.lookAt(position, position + Vector3.new(fx, 0, fz))
			local desired = (flat * CFrame.new(0, 8.5, 17)).Position
			cameraPosition = if cameraPosition then cameraPosition:Lerp(desired, 1 - math.exp(-dt * 6)) else desired
			if not cameraTaken then
				cameraTaken = true
				camera.CameraType = Enum.CameraType.Scriptable
			end
			shake = math.max(0, shake - dt)
			local jolt = if shake > 0
				then Vector3.new(math.sin(now * 61), math.sin(now * 73), 0) * shake
				else Vector3.zero
			camera.CFrame = CFrame.lookAt((cameraPosition :: Vector3) + jolt, (flat * CFrame.new(0, 3, -14)).Position)
			camera.FieldOfView = 64 + 14 * math.clamp((me.V - Track.TROT) / (Track.DASH - Track.TROT), 0, 1)
		else
			releaseCamera()
		end
	end)
end

return RockinRaceway

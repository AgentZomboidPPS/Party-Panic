-- Client half of Bobsled Run: everyone's sled sliding down the run, every rider seated and leaning
-- in it, the chase camera, the LEAN buttons and the race HUD.
--
-- The course comes from MG_Course (the pieces string; Shared/Logic/BobsledCourse turns it into the
-- same path the server races on). Each sled glides along it from MG_Sleds (distance and speed with
-- the server's time, extrapolated and eased so it never jumps), tilted with the banks and thrown by
-- the kickers; a "Curve" event slams it into the wall or sends it off with a boost. Every rider's
-- character (players and bots, via api:CharacterOf) is set into its seat here each frame and posed
-- sitting and leaning; your own character is moved for real, so the server sees you in your sled.
-- The next curve's arrow shows WARN seconds early and says LEAN when its window opens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BobsledCourse = require(ReplicatedStorage.Shared.Logic.BobsledCourse)
local Teams = require(ReplicatedStorage.Shared.Teams)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local BobsledRun = {}

local SHAPES = { Red = "★", Blue = "●", Green = "▲", Yellow = "◆" }
local SEAT_Y = 1.9
local LEAN_HOLD = 1.3 -- seconds a lean shows on a rider
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

-- A rider's pose: sitting with legs forward, holding the sides; `lean` -1..1 throws the upper body
-- that way; `cheer` lifts the arms.
local function seatedPose(lean: number, cheer: boolean, t: number): { [string]: CFrame }
	local arms = if cheer then 150 + math.sin(t * 9) * 12 else 0
	return {
		Waist = angles(-6, 0, -lean * 26),
		Neck = angles(4, 0, lean * 10),
		LeftShoulder = if cheer then angles(0, 0, -arms) else angles(30, 0, -14 + lean * 20),
		RightShoulder = if cheer then angles(0, 0, arms) else angles(30, 0, 14 + lean * 20),
		LeftElbow = angles(if cheer then 10 else 45, 0, 0),
		RightElbow = angles(if cheer then 10 else 45, 0, 0),
		LeftHip = angles(86, 0, -5),
		RightHip = angles(86, 0, 5),
		LeftKnee = angles(-28, 0, 0),
		RightKnee = angles(-28, 0, 0),
		LeftAnkle = angles(12, 0, 0),
		RightAnkle = angles(12, 0, 0),
	}
end

function BobsledRun.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(236, 246, 255),
		Saturation = 0.1,
		Contrast = 0.06,
		Brightness = 0.02,
		Haze = Color3.fromRGB(205, 225, 245),
		HazeDecay = Color3.fromRGB(150, 180, 220),
		Density = 0.28,
	})

	local localPlayer = Players.LocalPlayer
	local myId = localPlayer.UserId
	local camera = workspace.CurrentCamera
	local reduced = State.ReducedEffects()
	local touch = api:IsTouch()

	local course: BobsledCourse.Course? = nil
	local originCF = CFrame.identity
	local sledInfo: { any } = {} -- { T, X, R = { userIds }, G }
	local myTeam: string? = nil
	local snapshot: { [string]: any } = {}

	local function readCourse()
		local value = api:SharedJSON("Course")
		if type(value) ~= "table" or type(value.O) ~= "table" or type(value.P) ~= "string" then
			return
		end
		if not course then
			course = BobsledCourse.Build(value.P)
			originCF = CFrame.new(value.O[1], value.O[2], value.O[3])
		end
		sledInfo = value.Sleds or {}
		myTeam = nil
		for _, info in sledInfo do
			for _, id in info.R or {} do
				if id == myId then
					myTeam = info.T
				end
			end
		end
	end
	readCourse()
	api:OnShared("Course", readCourse)
	local function readSleds()
		local value = api:SharedJSON("Sleds")
		if type(value) == "table" then
			snapshot = value
		end
	end
	readSleds()
	api:OnShared("Sleds", readSleds)

	-- Sleds ------------------------------------------------------------------------------------------

	type Visual = {
		Model: Model?,
		D: number,
		V: number,
		BumpAt: number,
		BumpDir: number,
		BoostAt: number,
		Spray: ParticleEmitter?,
		Sparks: ParticleEmitter?,
		Frame: CFrame?,
	}
	local visuals: { [string]: Visual } = {}

	local function makeSled(team: string): Model?
		local template = api:Template("BobsledSled", 5)
		if not template or not template:IsA("Model") then
			return nil
		end
		local model = template :: Model
		local color = Teams.Colors[team] or Theme.Colors.Pink
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				if part.Name == "Body" then
					part.Color = color
				end
			end
		end
		model.Parent = api.World
		local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if root then
			-- Whose sled: the team's shape and name float above it (color is never the only cue).
			local board = Instance.new("BillboardGui")
			board.Name = "Tag"
			board.Size = UDim2.fromOffset(150, 40)
			board.StudsOffsetWorldSpace = Vector3.new(0, 7.5, 0)
			board.MaxDistance = 260
			board.LightInfluence = 0
			board.Adornee = root
			board.Parent = model
			UIKit.Label({
				Text = `{SHAPES[team] or ""} {string.upper(team)}`,
				Font = Theme.Fonts.Display,
				TextSize = 26,
				TextColor3 = color,
				Size = UDim2.fromScale(1, 1),
				Parent = board,
				Children = { UIKit.TextStroke(0) },
			})
			local spray = Instance.new("ParticleEmitter")
			spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
			spray.Color = ColorSequence.new(Color3.fromRGB(250, 252, 255))
			spray.Transparency = NumberSequence.new(0.35, 1)
			spray.Size = NumberSequence.new(1.2, 3.2)
			spray.Lifetime = NumberRange.new(0.5, 0.9)
			spray.Speed = NumberRange.new(4, 8)
			spray.SpreadAngle = Vector2.new(25, 10)
			spray.EmissionDirection = Enum.NormalId.Back
			spray.Rate = 0
			spray.Parent = root
			local sparks = Instance.new("ParticleEmitter")
			sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparks.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255), Color3.fromRGB(255, 255, 255))
			sparks.LightEmission = 0.8
			sparks.Size = NumberSequence.new(0.6, 0)
			sparks.Lifetime = NumberRange.new(0.4, 0.7)
			sparks.Speed = NumberRange.new(14, 24)
			sparks.SpreadAngle = Vector2.new(70, 70)
			sparks.Rate = 0
			sparks.Parent = root
			local visual = visuals[team]
			if visual then
				visual.Spray = spray
				visual.Sparks = sparks
			end
		end
		return model
	end

	local function visualOf(team: string): Visual
		local visual = visuals[team]
		if not visual then
			visual = { D = 0, V = 0, BumpAt = -math.huge, BumpDir = 1, BoostAt = -math.huge }
			visuals[team] = visual
			visual.Model = makeSled(team)
		end
		return visual :: Visual
	end

	-- Leans seen (from "Lean" events and the snapshot; my own at once when I press).
	local leans: { [number]: { Dir: number, At: number } } = {}
	local function noteLean(userId: number, dir: number, at: number)
		local seen = leans[userId]
		if not seen or at > seen.At + 0.01 then
			leans[userId] = { Dir = dir, At = at }
		end
	end
	api:OnEvent("Lean", function(userId, dir)
		if type(userId) == "number" and (dir == -1 or dir == 1) and userId ~= myId then
			noteLean(userId, dir, api:Now())
		end
	end)

	-- HUD -------------------------------------------------------------------------------------------

	local hud = api:TopHud()
	local hudY = api:HudY()
	local barWidth = 560
	local bar = UIKit.Panel({
		Name = "RunBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY + 4),
		Size = UDim2.fromOffset(barWidth, if touch then 42 else 32),
		CornerRadius = 16,
		Parent = hud,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local track = UIKit.new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, -14, 0.5, 0),
		Size = UDim2.new(1, -76, 0, 8),
		BackgroundColor3 = Color3.fromRGB(200, 230, 250),
		Parent = bar,
		Children = { UIKit.Round() },
	})
	UIKit.Label({
		Name = "Goal",
		Text = "🏁",
		TextSize = if touch then 26 else 22,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 6, 0.5, 0),
		Size = if touch then UDim2.fromOffset(30, 30) else UDim2.fromOffset(26, 26),
		Parent = track,
	})
	local ticksMade = false
	local function makeTicks()
		if ticksMade or not course then
			return
		end
		ticksMade = true
		for _, curve in course.Curves do
			UIKit.new("Frame", {
				Name = "Curve",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(math.clamp(curve.D0 / course.Length, 0, 1), 0.5),
				Size = UDim2.fromOffset(3, 14),
				BackgroundColor3 = Theme.Colors.PanelDark,
				BackgroundTransparency = 0.3,
				Parent = track,
			})
		end
	end
	local markers: { [string]: Frame } = {}
	local function marker(team: string): Frame
		local existing = markers[team]
		if existing then
			return existing
		end
		local mine = team == myTeam
		local size = if touch then (if mine then 38 else 32) else (if mine then 28 else 22)
		local dot = UIKit.new("Frame", {
			Name = "Sled" .. team,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Teams.Colors[team] or Theme.Colors.Text,
			ZIndex = if mine then 4 else 3,
			Parent = track,
			Children = {
				UIKit.Round(),
				UIKit.Stroke(if mine then Theme.Colors.Text else Theme.Colors.PanelDark, if mine then 3 else 2),
			},
		})
		UIKit.Label({
			Text = SHAPES[team] or "?",
			TextSize = if touch then (if mine then 26 else 22) else (if mine then 18 else 14),
			Font = Theme.Fonts.Bold,
			TextColor3 = Color3.fromRGB(30, 24, 40),
			Size = UDim2.fromScale(1, 1),
			ZIndex = dot.ZIndex,
			Parent = dot,
		})
		markers[team] = dot
		return dot
	end

	-- The next curve: a big arrow, what to do, and a bar that fills up to the curve.
	local cue = UIKit.Panel({
		Name = "CurveCue",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY + (if touch then 54 else 44)),
		Size = UDim2.fromOffset(if touch then 300 else 330, 74),
		CornerRadius = 18,
		Visible = false,
		Parent = hud,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local arrow = UIKit.Label({
		Name = "Arrow",
		Text = "◀",
		Font = Theme.Fonts.Bold,
		TextSize = 52,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, -3),
		Size = UDim2.fromOffset(62, 62),
		Parent = cue,
		Children = { UIKit.TextStroke(0.2) },
	})
	local cueText = UIKit.Label({
		Name = "Say",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 70, 0, 8),
		Size = UDim2.new(1, -140, 0, 36),
		Parent = cue,
		Children = { UIKit.TextStroke(0.2) },
	})
	local arrow2 = UIKit.Label({
		Name = "Arrow2",
		Text = "◀",
		Font = Theme.Fonts.Bold,
		TextSize = 52,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, -3),
		Size = UDim2.fromOffset(62, 62),
		Parent = cue,
		Children = { UIKit.TextStroke(0.2) },
	})
	local timing = UIKit.new("Frame", {
		Name = "Timing",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -150, 0, 12),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = cue,
		Children = { UIKit.Round() },
	})
	local timingFill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Cyan,
		Parent = timing,
		Children = { UIKit.Round() },
	})

	-- My crew's leans, one pip each: ◀, ▶ or a dot.
	local crewRow = UIKit.new("Frame", {
		Name = "Crew",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY + (if touch then 132 else 122)),
		Size = UDim2.fromOffset(240, 34),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud,
		Children = {
			UIKit.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	local pips: { [number]: TextLabel } = {}

	local callout = UIKit.Label({
		Name = "Callout",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 40,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY + (if touch then 172 else 164)),
		Size = UDim2.fromOffset(420, 48),
		TextWrapped = false,
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})
	local calloutUntil = 0
	local function say(text: string, color: Color3, seconds: number)
		callout.Text = text
		callout.TextColor3 = color
		if touch then
			local width = UIKit.TextWidth(text, 40, Theme.Fonts.Display) + 24
			callout.Size = UDim2.fromOffset(math.ceil(width), 48)
		end
		callout.Visible = true
		calloutUntil = os.clock() + seconds
		UIKit.PopIn(callout, 0.25)
	end

	local placeLabel = UIKit.Label({
		Name = "Place",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, barWidth / 2, 0, hudY + (if touch then 52 else 42)),
		Size = UDim2.fromOffset(110, 36),
		Visible = not touch, -- phones: the run bar's markers already show the order
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})

	-- Controls --------------------------------------------------------------------------------------

	local left = api:Button({ Text = "◀ LEAN", Key = Enum.KeyCode.A, Color = Theme.Colors.Cyan, Slot = 2 })
	local right = api:Button({ Text = "LEAN ▶", Key = Enum.KeyCode.D, Color = Theme.Colors.Orange, Slot = 1 })
	local lastPress = -math.huge
	local earlyCurve = 0

	local function windowState(): (BobsledCourse.Curve?, number?)
		local entry = myTeam and snapshot[myTeam]
		local visual = myTeam and visuals[myTeam]
		if not course or not entry or not visual or entry.F then
			return nil, nil
		end
		local curve = course.Curves[entry.N or 1]
		if not curve then
			return nil, nil
		end
		return curve, (curve.D0 - visual.D) / math.max(visual.V, 8)
	end

	local function lean(dir: number)
		if not myTeam or not api:Alive() then
			return
		end
		local now = api:Now()
		if now - lastPress < 0.09 then
			return
		end
		lastPress = now
		api:Action("Lean", dir)
		noteLean(myId, dir, now)
		api:Sound("Click")
		local curve, seconds = windowState()
		if curve and seconds and seconds > BobsledCourse.OPEN + 0.05 and seconds < BobsledCourse.WARN + 0.5 then
			earlyCurve = curve.Index
			say("TOO EARLY! Wait for LEAN", Theme.Colors.Yellow, 1.1)
		end
	end
	left.Pressed:Connect(function()
		lean(-1)
	end)
	right.Pressed:Connect(function()
		lean(1)
	end)
	api:Track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Left then
			lean(-1)
		elseif input.KeyCode == Enum.KeyCode.Right then
			lean(1)
		end
	end))

	-- Curve results ---------------------------------------------------------------------------------

	local shake = 0
	local fovPunch = 0
	api:OnEvent("Curve", function(team, index, kind, rightCount, crew)
		if type(team) ~= "string" or not course then
			return
		end
		local visual = visualOf(team)
		local curve = course.Curves[index]
		local now = api:Now()
		if kind == "Bump" then
			visual.BumpAt = now
			visual.BumpDir = if curve then -curve.Dir else 1 -- thrown to the curve's outside
			if visual.Sparks then
				visual.Sparks:Emit(28)
			end
		elseif kind == "Clean" then
			visual.BoostAt = now
		end
		if team ~= myTeam then
			return
		end
		local counted = if type(rightCount) == "number"
				and type(crew) == "number"
				and crew > 1
			then `  {rightCount}/{crew}`
			else ""
		if kind == "Clean" then
			say(`✔ CLEAN! SPEED UP{counted}`, Theme.Colors.Green, 1.2)
			api:Sound("Pickup")
			fovPunch = 9
		elseif kind == "Scrape" then
			say(`~ SCRAPE{counted}`, Theme.Colors.Yellow, 1.1)
			api:Sound("Click")
			shake = 0.25
		else
			say(`✖ BUMP! LEAN TOGETHER{counted}`, Theme.Colors.Red, 1.3)
			api:Sound("Hit")
			shake = 0.7
		end
	end)
	api:OnEvent("Finish", function(team, place)
		if team == myTeam and type(place) == "number" then
			say(
				`🏁 {BobsledCourse.Ordinal(place)} PLACE!`,
				if place == 1 then Theme.Colors.Yellow else Theme.Colors.Text,
				3
			)
			local visual = visuals[team]
			if visual and visual.Frame then
				api:Effect("Confetti", visual.Frame.Position + Vector3.new(0, 4, 0))
			end
		end
	end)

	-- Posing riders ---------------------------------------------------------------------------------

	local rigs: { [Model]: { [string]: { Motor: Motor6D, Current: CFrame } } } = {}
	local leanShown: { [number]: number } = {}
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
	local function leanOf(userId: number, now: number): number
		local seen = leans[userId]
		if seen and now - seen.At < LEAN_HOLD then
			return seen.Dir
		end
		return 0
	end

	local seated: { [Model]: boolean } = {}
	local poseConnection = (RunService :: any).PreSimulation or RunService.Stepped
	api:Track(poseConnection:Connect(function(dt)
		if not course then
			return
		end
		local now = api:Now()
		local step = if type(dt) == "number" then dt else 1 / 60
		local alpha = 1 - math.exp(-step * 16)
		for character in seated do
			if not character.Parent then
				seated[character] = nil
				rigs[character] = nil
				continue
			end
			local userId = character:GetAttribute("BobsledRider")
			local team = character:GetAttribute("BobsledTeam")
			local entry = team and snapshot[team]
			local target = seatedPose(leanShown[userId] or 0, entry ~= nil and entry.F ~= nil, now)
			for name, joint in rigOf(character) do
				joint.Current = joint.Current:Lerp(target[name] or CFrame.identity, alpha)
				joint.Motor.Transform = joint.Current
			end
		end
	end))
	local function unseat(character: Model)
		local rig = rigs[character]
		if rig then
			for _, joint in rig do
				joint.Motor.Transform = CFrame.identity
			end
		end
		rigs[character] = nil
		seated[character] = nil
	end

	-- Camera ------------------------------------------------------------------------------------------

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
		for character in seated do
			unseat(character)
		end
		local _, humanoid, root = api:Character()
		if humanoid then
			humanoid.PlatformStand = false
		end
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)

	-- Every frame ---------------------------------------------------------------------------------------

	local hintUntil = 0
	local lastPlace = ""
	local cueMode = ""
	local leanEnabled = nil :: boolean?
	local spraySet: { [string]: number } = {}

	api:RenderStep(function(dt)
		local run = course
		if not run then
			return
		end
		makeTicks()
		dt = math.min(dt, 0.1)
		local now = api:Now()

		-- Sleds and riders.
		local order = {}
		for _, info in sledInfo do
			local team = info.T
			local visual = visualOf(team)
			local entry = snapshot[team]
			local model = visual.Model
			if info.G or (entry and entry.G) then
				if model then
					model:PivotTo(CFrame.new(0, -500, 0))
				end
				local dot = markers[team]
				if dot then
					dot.Visible = false
				end
				continue
			end
			if entry then
				local target = (entry.D or 0) + (entry.V or 0) * math.clamp(now - (entry.T or now), 0, 0.5)
				target = math.min(target, run.Total - 10)
				visual.V += ((entry.V or 0) - visual.V) * (1 - math.exp(-dt * 8))
				visual.D += visual.V * dt
				local gap = target - visual.D
				if math.abs(gap) > 25 then
					visual.D = target
				else
					visual.D += gap * (1 - math.exp(-dt * 5))
				end
			end
			local wobble, yaw = 0, 0
			local since = now - visual.BumpAt
			if since >= 0 and since < 1.1 then
				local fade = 1 - since / 1.1
				wobble = visual.BumpDir * 2.2 * math.sin(math.min(since * 9, math.pi)) * fade
				yaw = math.sin(since * 26) * rad(9) * fade
			end
			local frame = originCF * BobsledCourse.Frame(run, visual.D, info.X + wobble) * CFrame.Angles(0, yaw, 0)
			visual.Frame = frame
			if model then
				model:PivotTo(frame)
			end
			-- Snow spray at speed (it's the sled's own trail: not ambient, but reduced effects dims it).
			local spray = visual.Spray
			if spray then
				local airborne = BobsledCourse.Airborne(run, visual.D)
				local rate = if airborne then 0 else math.clamp((visual.V - 10) * 0.9, 0, 30)
				if reduced then
					rate *= 0.3
				end
				rate = math.floor(rate)
				if spraySet[team] ~= rate then
					spraySet[team] = rate
					spray.Rate = rate
				end
			end

			local riders = info.R or {}
			for index, userId in riders do
				local seat = frame * CFrame.new(0, SEAT_Y, BobsledCourse.SeatZ(index, #riders))
				local target = leanOf(userId, now)
				local shown = leanShown[userId] or 0
				shown += (target - shown) * (1 - math.exp(-dt * 10))
				leanShown[userId] = shown
				seat *= CFrame.new(shown * 0.3, 0, 0) * CFrame.Angles(0, 0, -shown * rad(10))
				local character = api:CharacterOf(userId)
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not character or not root then
					continue
				end
				if not seated[character] then
					seated[character] = true
					character:SetAttribute("BobsledRider", userId)
					character:SetAttribute("BobsledTeam", team)
				end
				if userId == myId then
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid and not humanoid.PlatformStand then
						humanoid.PlatformStand = true
					end
					root.AssemblyLinearVelocity = frame.LookVector * visual.V
					root.AssemblyAngularVelocity = Vector3.zero
				end
				root.CFrame = seat
			end

			local entryD = visual.D
			local dot = marker(team)
			dot.Visible = true
			dot.Position = UDim2.fromScale(math.clamp(entryD / run.Length, 0, 1), 0.5)
			table.insert(order, {
				Team = team,
				Score = if entry and entry.F then 1e6 - entry.F else entryD,
			})
		end
		-- Leans from the snapshot (catches any event that arrived before the riders were known).
		for _, entry in snapshot do
			if type(entry) == "table" and type(entry.L) == "table" and type(entry.LA) == "table" then
				for key, dir in entry.L do
					local userId = tonumber(key)
					local at = entry.LA[key]
					if userId and userId ~= myId and type(at) == "number" and (dir == -1 or dir == 1) then
						noteLean(userId, dir, at)
					end
				end
			end
		end

		-- Chase camera behind my sled.
		local mine = myTeam and visuals[myTeam]
		if mine and mine.Frame and api:Alive() then
			local frame = mine.Frame :: CFrame
			local flat = CFrame.lookAt(frame.Position, frame.Position + frame.LookVector)
			local desired = (flat * CFrame.new(0, 7.5, 19)).Position
			cameraPosition = if cameraPosition then cameraPosition:Lerp(desired, 1 - math.exp(-dt * 7)) else desired
			if not cameraTaken then
				cameraTaken = true
				camera.CameraType = Enum.CameraType.Scriptable
			end
			shake = math.max(0, shake - dt)
			fovPunch = math.max(0, fovPunch - dt * 12)
			local jolt = if shake > 0
				then Vector3.new(math.sin(now * 71), math.sin(now * 83), 0) * shake * 0.9
				else Vector3.zero
			local up = Vector3.yAxis:Lerp(frame.UpVector, 0.35).Unit
			local position = cameraPosition :: Vector3
			camera.CFrame = CFrame.lookAt(position + jolt, (flat * CFrame.new(0, 2.5, -16)).Position, up)
			camera.FieldOfView = 66 + 16 * math.clamp((mine.V - 20) / 40, 0, 1) + fovPunch
		else
			releaseCamera()
		end

		-- The next curve's cue.
		local curve, seconds = windowState()
		local mode = ""
		if curve and seconds and seconds <= BobsledCourse.WARN and api:Alive() then
			mode = if seconds <= BobsledCourse.OPEN then "Lean" else "Ready"
			if curve.D0 <= (mine and mine.D or 0) then
				mode = "Lean" -- in the curve, waiting for the judging
			end
		end
		if mode ~= cueMode then
			cueMode = mode
			cue.Visible = mode ~= ""
			if curve and mode ~= "" then
				local glyph = if curve.Dir < 0 then "◀" else "▶"
				arrow.Text = glyph
				arrow2.Text = glyph
				local word = if curve.Dir < 0 then "LEFT" else "RIGHT"
				if mode == "Lean" then
					cueText.Text = `LEAN {word}!`
					timingFill.BackgroundColor3 = Theme.Colors.Green
					api:Sound("Countdown")
					UIKit.PopIn(cue, 0.2)
				else
					cueText.Text = `{word} CURVE`
					timingFill.BackgroundColor3 = Theme.Colors.Cyan
				end
			end
		end
		if cue.Visible and seconds then
			local fill = math.clamp(1 - seconds / BobsledCourse.WARN, 0, 1)
			timingFill.Size = UDim2.fromScale(fill, 1)
			local hot = cueMode == "Lean"
			local pulse = if hot then 0.5 + 0.5 * math.sin(os.clock() * 14) else 0
			local color = if hot
				then Color3.fromRGB(255, 255, 255):Lerp(Theme.Colors.Yellow, pulse)
				else Theme.Colors.TextDim
			arrow.TextColor3 = color
			arrow2.TextColor3 = color
			cueText.TextColor3 = if hot then Theme.Colors.Yellow else Theme.Colors.Text
			if hot and earlyCurve == (curve and curve.Index) and leanOf(myId, now) == 0 then
				cueText.Text = if curve and curve.Dir < 0 then "AGAIN: LEFT!" else "AGAIN: RIGHT!"
			end
		end

		-- My crew's leans.
		local myInfo = nil
		for _, info in sledInfo do
			if info.T == myTeam then
				myInfo = info
			end
		end
		local crewText = ""
		if myInfo and #(myInfo.R or {}) > 1 then
			for index, userId in myInfo.R do
				local dir = leanOf(userId, now)
				local pip = pips[index]
				if not pip then
					pip = UIKit.Label({
						Name = "Pip" .. index,
						Text = "•",
						Font = Theme.Fonts.Bold,
						TextSize = 24,
						LayoutOrder = index,
						Size = UDim2.fromOffset(40, 34),
						BackgroundTransparency = 0.25,
						BackgroundColor3 = Theme.Colors.PanelDark,
						Parent = crewRow,
						Children = { UIKit.Corner(10) },
					})
					pips[index] = pip
				end
				local glyph = if dir < 0 then "◀" elseif dir > 0 then "▶" else "•"
				crewText ..= glyph
				pip.Text = glyph
				pip.TextColor3 = if userId == myId then Theme.Colors.Yellow else Theme.Colors.Text
				pip.Visible = true
			end
			for index = #myInfo.R + 1, #pips do
				pips[index].Visible = false
			end
		end
		local showCrew = crewText ~= "" and cue.Visible
		if crewRow.Visible ~= showCrew then
			crewRow.Visible = showCrew
		end

		if callout.Visible and os.clock() > calloutUntil then
			callout.Visible = false
		end
		if hintUntil == 0 and myTeam then
			hintUntil = os.clock() + 7
			api:Hint(
				if touch
					then "Lean with your crew on each ◀ ▶"
					else "Lean with your crew: ◀ A / D ▶ when the arrow says",
				hudY + (if touch then 216 else 214)
			)
		elseif hintUntil > 0 and os.clock() > hintUntil then
			hintUntil = -1
			api:Hint("")
		end

		table.sort(order, function(a, b)
			return a.Score > b.Score
		end)
		local place = ""
		for index, item in order do
			if item.Team == myTeam then
				place = `{BobsledCourse.Ordinal(index)} of {#order}`
			end
		end
		if place ~= lastPlace then
			lastPlace = place
			placeLabel.Text = place
		end
		local entry = myTeam and snapshot[myTeam]
		local canLean = myTeam ~= nil and entry ~= nil and not entry.F and api:Alive()
		if canLean ~= leanEnabled then
			leanEnabled = canLean
			left:SetEnabled(canLean)
			right:SetEnabled(canLean)
		end
	end)
end

return BobsledRun

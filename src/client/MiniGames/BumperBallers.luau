-- Client half of Bumper Ballers: rolls this player's own ball and draws the round.
--
-- The server gives each player's ball to their device (ball model attribute ClientDriven). This
-- client then pushes it every frame with the same drive the server rolls bots' balls with
-- (Logic/BumperDrive, with the server's numbers from MG_Tuning). Input is Roblox's own move vector
-- (WASD, arrows, the MOVE stick, gamepad: PlayerModule's controls), relative to the camera, or
-- phone TILT if the player turns it on.
-- The server decides bumps and sends "Bump" (a velocity kick for this ball); everyone gets "Boing"
-- (a squash, a ring and a sound where two balls met) and "Splash" (someone fell in). This player's
-- own bumps squash and boing the moment the balls touch on screen, without waiting for the server,
-- by the server's own rule (MG_Tuning Touch and ClosingMin): the server also judges bumps as this
-- screen showed them, so a boing here is a bump there.
--
-- Also: a strip of every rider's shape and color (faded, with a red X tag hanging under the icon,
-- when they're out), an EDGE! warning near the rim, a YOU marker over this player's ball, gentle
-- foam rings on the sea, and the buoys and pool floats bobbing on the swell.
--
-- Controls pass (owner, playing on a phone: "Bumper balls control scheme is really bad on
-- mobile"). What was wrong there:
--   * Roblox's touch camera is a "follow" camera: it swings round behind whatever the player moves
--     towards. The stick is read relative to the camera, so holding it right rolled the ball right,
--     the camera swung right, "right" turned with it, and the ball rolled round in a circle; every
--     push bent a little as the camera chased it. (PC's camera doesn't swing, which is why only
--     phones felt it.) Phones now get a steady camera: high behind the ball, looking the way the
--     rider faced at the start (towards the middle) for the whole round, following the ball but
--     never turning, so pushing the stick rolls the ball exactly where the thumb points on screen,
--     and most of the island stays in view. After a fall it watches the splash, then hands back to
--     Roblox's camera for spectating.
--   * Tilt steered by default on any phone that can tilt, so the ball drifted whenever the stick
--     was let go, with three big buttons beside jump. Tilt is now a small TILT switch, off until the
--     player turns it on (it stays on for their next rounds); CALIBRATE and FLIP show only while
--     it's on.
--   * The ball took 1.2 s to reach full speed, coasted 12 studs after letting go and took a second
--     to turn, so dodges came too late on a small screen. It answers quickly now (Logic/BumperDrive)
--     while bumps still slide riders exactly as far as before.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local BumperDrive = require(ReplicatedStorage.Shared.Logic.BumperDrive)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local BumperBallers = {}

local EDGE_WARNING = 8 -- studs from the rim
-- The steady camera (touch screens): this far from the ball, looking down this steeply. The ball
-- sits mid-screen, about 50 points across on a small phone, with about 28 studs of island in view
-- behind it, 70 ahead and more than that to each side.
local CAMERA_DISTANCE = 50
local CAMERA_PITCH = math.rad(58)
local CAMERA_FOV = 70
local CAMERA_FOLLOW = 14 -- per second: how tightly it keeps up with the ball (a touch of smoothing)
local OUT_CAMERA = 1.2 -- seconds the camera stays on the splash before Roblox's camera takes over

-- Tilt steering, once the player has turned it on: kept for their next rounds (this session).
local tiltChosen = false

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Roblox's own move input (keyboard, thumbstick, gamepad), camera-relative like walking.
local function moveControls(): any
	local ok, controls = pcall(function()
		local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
		local module = playerScripts and playerScripts:FindFirstChild("PlayerModule")
		if not module then
			return nil
		end
		return (require(module) :: any):GetControls()
	end)
	return if ok then controls else nil
end

-- The screen's "up" and "right" on the ground: where pushing the stick up or right should roll.
local function cameraAxes(): (Vector3, Vector3)
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.new(0, 0, -1), Vector3.new(1, 0, 0)
	end
	local look = flat(camera.CFrame.LookVector)
	if look.Magnitude < 0.05 then
		look = flat(camera.CFrame.UpVector)
	end
	local forward = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	return forward, Vector3.new(-forward.Z, 0, forward.X)
end

function BumperBallers.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(250, 252, 255),
		Saturation = 0.18,
		Contrast = 0.06,
		Brightness = 0.02,
		Haze = Color3.fromRGB(190, 230, 255),
		HazeDecay = Color3.fromRGB(120, 190, 230),
		Density = 0.26,
	})
	local arena = api:Arena()
	if not arena then
		return
	end
	local ballsFolder = arena:WaitForChild("Balls", 10)
	if not ballsFolder then
		return
	end
	-- Where the island is (the on-island rule and the phone camera need it) and the drive's numbers:
	-- the server shares both before it builds the balls, but wait a moment in case they're still on
	-- their way, and take them whenever they come.
	local island = api:SharedJSON("Island")
	local waited = 0
	while not island and waited < 10 and ballsFolder.Parent do
		task.wait(0.1)
		waited += 0.1
		island = api:SharedJSON("Island")
	end
	if not ballsFolder.Parent then
		return -- the round was called off meanwhile
	end
	api:OnShared("Island", function()
		island = api:SharedJSON("Island") or island
	end)
	local player = api.Player or Players.LocalPlayer
	local myId = player and player.UserId
	local tuning = api:SharedJSON("Tuning") or {}
	local drive = BumperDrive.new(tuning)
	local maxSpeed = drive.Tuning.MaxSpeed
	local touchDistance = tuning.Touch or 8.5
	local closingMin = tuning.ClosingMin or 4
	local hud = api:TopHud()
	local touch = api:IsTouch()

	-- Riders strip ----------------------------------------------------------------------------
	-- (Phones draw the HUD at 75%: bigger icons there keep the shapes readable. Twelve riders still
	-- fit in the strip.)
	local iconSize = if touch then 40 else 34
	-- Lines under the strip start this far below it: a knocked-out rider's X tag hangs under their
	-- icon (see addIcon).
	local underStrip = api:HudY() + 62
	local strip = UIKit.new("Frame", {
		Name = "Riders",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY()),
		Size = UDim2.fromOffset(600, iconSize + 6),
		BackgroundTransparency = 1,
		Parent = hud,
		Children = {
			UIKit.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	type Icon = { Frame: Frame, Shape: TextLabel, Ring: UIStroke, Badge: Frame, Out: boolean }
	local icons: { [number]: Icon } = {}
	local function participantAlive(userId: number): boolean
		for _, participant in api:Participants() do
			if participant.UserId == userId then
				return participant:GetAttribute("PP_Alive") ~= false
			end
		end
		return false
	end
	local function addIcon(model: Instance)
		local userId = model:GetAttribute("Owner")
		if type(userId) ~= "number" or icons[userId] then
			return
		end
		local color = model:GetAttribute("Color") or Color3.new(1, 1, 1)
		local mine = userId == myId
		local ring = UIKit.Stroke(Color3.new(1, 1, 1), if mine then 3 else 2, 0)
		local frame = UIKit.new("Frame", {
			Name = "Rider" .. tostring(userId),
			Size = UDim2.fromOffset(if mine then iconSize + 6 else iconSize, if mine then iconSize + 6 else iconSize),
			BackgroundColor3 = color,
			LayoutOrder = if mine then -1 else model:GetAttribute("Index") or 0,
			Parent = strip,
			Children = { UIKit.Round(), ring },
		})
		local shape = UIKit.Label({
			Name = "Shape",
			Text = model:GetAttribute("Shape") or "●",
			Font = Enum.Font.GothamBlack,
			TextScaled = true,
			Size = UDim2.fromScale(0.7, 0.7),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			TextColor3 = Color3.new(1, 1, 1),
			Parent = frame,
			Children = { UIKit.TextStroke(0.3) },
		})
		-- Knocked out (owner's phone: the "X" sat right over the rider's shape, so you couldn't tell
		-- who was out): the icon fades, its shape moves up a little and stays in full view, and a red
		-- X tag hangs from the bottom of the icon.
		local badge = UIKit.new("Frame", {
			Name = "Out",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(0.55, 0.55),
			BackgroundColor3 = Theme.Colors.Red,
			Visible = false,
			ZIndex = 3,
			Parent = frame,
			Children = { UIKit.Round(), UIKit.Stroke(Color3.new(1, 1, 1), 2, 0) },
		})
		UIKit.Label({
			Text = "X", -- (its box overhangs the badge: the letter itself sits inside, big enough to read)
			Font = Enum.Font.GothamBlack,
			TextScaled = true,
			Size = UDim2.fromScale(1.15, 1.15),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			TextColor3 = Color3.new(1, 1, 1),
			ZIndex = 4,
			Parent = badge,
		})
		icons[userId] = { Frame = frame, Shape = shape, Ring = ring, Badge = badge, Out = false }
	end
	local function showOut(icon: Icon, out: boolean)
		icon.Badge.Visible = out
		icon.Frame.BackgroundTransparency = if out then 0.6 else 0
		icon.Ring.Transparency = if out then 0.5 else 0
		icon.Shape.Position = UDim2.fromScale(0.5, if out then 0.4 else 0.5)
	end

	local bigBadge = UIKit.Label({
		Name = "BigBumps",
		Text = "💥 BIG BUMPS!",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, underStrip),
		Size = UDim2.fromOffset(320, 36),
		TextColor3 = Theme.Colors.Orange,
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})
	local function refreshBig()
		local on = api:Shared("BigBumps") == true
		if on and not bigBadge.Visible then
			bigBadge.Visible = true
			UIKit.PopIn(bigBadge, 0.3)
		end
		bigBadge.Visible = on
	end
	api:OnShared("BigBumps", refreshBig)
	refreshBig()

	local edgeLabel = UIKit.Label({
		Name = "Edge",
		Text = "⚠ EDGE! ⚠",
		Font = Theme.Fonts.Display,
		TextSize = 40,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, underStrip + 66), -- under the hint line, which shows at the start
		Size = UDim2.fromOffset(320, 46),
		TextColor3 = Theme.Colors.Red,
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0) },
	})

	-- Balls --------------------------------------------------------------------------------------
	type Ball = { Model: Model, Body: BasePart?, Pieces: { { Part: BasePart, Size: Vector3 } }, Pulse: number }
	local balls: { [number]: Ball } = {}
	local addBall
	function addBall(model: Instance)
		if not model:IsA("Model") then
			return
		end
		local userId = model:GetAttribute("Owner")
		if type(userId) ~= "number" then
			local connection
			connection = model:GetAttributeChangedSignal("Owner"):Connect(function()
				connection:Disconnect()
				addBall(model)
			end)
			api:Track(connection)
			return
		end
		if balls[userId] then
			return
		end
		local body = model:WaitForChild("Body", 5) :: BasePart?
		local visual = model:WaitForChild("Visual", 5)
		local pieces = {}
		if visual then
			for _, part in visual:GetDescendants() do
				if part:IsA("BasePart") then
					table.insert(pieces, { Part = part, Size = part.Size })
				end
			end
		end
		balls[userId] = { Model = model :: Model, Body = body, Pieces = pieces, Pulse = 0 }
		addIcon(model)
	end
	for _, child in ballsFolder:GetChildren() do
		task.spawn(addBall, child)
	end
	api:Track(ballsFolder.ChildAdded:Connect(addBall))
	-- A ball taken away before GO (its rider couldn't be placed in the round, or left): they're not
	-- in this round, so their icon goes too, instead of showing them knocked out all round.
	api:Track(ballsFolder.ChildRemoved:Connect(function(model)
		local userId = model:GetAttribute("Owner")
		if State.Phase() ~= "Preparing" or type(userId) ~= "number" then
			return
		end
		local icon = icons[userId]
		if icon then
			icon.Frame:Destroy()
			icons[userId] = nil
		end
		balls[userId] = nil
	end))

	-- "Boing": both balls squash and spring back, a ring flashes where they met.
	local function pulse(userId: number, strength: number)
		local ball = balls[userId]
		if ball then
			ball.Pulse = math.max(ball.Pulse, 0.12 + strength * 0.16)
		end
	end
	local function ring(position: Vector3, color: Color3, size: number)
		local part = Instance.new("Part")
		part.Name = "BoingRing"
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Transparency = 0.25
		part.Size = Vector3.new(0.2, 2, 2)
		part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
		part.Parent = api.World
		local tween = TweenService:Create(
			part,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.2, size, size), Transparency = 1 }
		)
		tween:Play()
		task.delay(0.5, function()
			part:Destroy()
		end)
	end
	-- Instant feedback for this player's own bumps (see RenderStep); the server's Boing for the
	-- same bump arrives a round trip later and is skipped.
	local localBoingAt: { [number]: number } = {}
	local function boing(position: Vector3, strength: number, a: number, b: number)
		pulse(a, strength)
		pulse(b, strength)
		ring(position, Color3.fromRGB(255, 245, 200), 8 + strength * 10)
		api:Effect("Stars", position)
		local camera = workspace.CurrentCamera
		local near = camera and (camera.CFrame.Position - position).Magnitude < 70
		if a == myId or b == myId or near then
			api:Sound("Boing")
		end
	end
	api:OnEvent("Boing", function(position: Vector3, strength: number, a: number, b: number)
		if typeof(position) ~= "Vector3" or type(strength) ~= "number" then
			return
		end
		local other = if a == myId then b elseif b == myId then a else nil
		if other and os.clock() - (localBoingAt[other] or -10) < 0.6 then
			return
		end
		boing(position, strength, a, b)
	end)
	api:OnEvent("Splash", function(position: Vector3, userId: number)
		if typeof(position) ~= "Vector3" then
			return
		end
		ring(position + Vector3.new(0, 0.2, 0), Color3.fromRGB(235, 250, 255), 16)
		api:Effect("Bubbles", position)
		api:Sound("Splash")
		local icon = icons[userId]
		if icon then
			icon.Out = true
		end
	end)

	-- Driving this player's own ball --------------------------------------------------------------
	local controls = moveControls()
	local wasDriving = false
	local yaw: number? = nil
	local driving = false

	api:OnEvent("Bump", function(dv: Vector3, relief: number)
		local ball = balls[myId]
		local body = ball and ball.Body
		if typeof(dv) ~= "Vector3" or not body or not driving then
			return
		end
		local _, _, root = api:Character()
		local rider = if root then root.AssemblyMass else 0
		local mass = body.AssemblyMass + rider
		body:ApplyImpulse(dv * mass)
		-- The drive lets what the ball rolls on with once it grips again (the rest spins it up) fade
		-- the way bumps always did, instead of steering it away.
		local keep = mass / (body.AssemblyMass * BumperDrive.RollMass + rider)
		local seconds = math.clamp(type(relief) == "number" and relief or 0.5, 0, 1)
		drive:Bump(os.clock(), dv.X * keep, dv.Z * keep, seconds)
		if dv.Magnitude > 9 then
			pulse(myId, math.clamp(dv.Magnitude / 40, 0.2, 1))
		end
	end)

	-- Tilt, for phones that can tilt: a TILT switch low on the screen, between the MOVE stick's
	-- corner and the jump button, shown only while the player can steer (api:CanAct: not once
	-- they're out, nor once the round is over). Off until they turn it on; turning it on takes the
	-- way they hold the phone then as level. While it's on, CALIBRATE (that's level now) and FLIP
	-- (left and right swap) appear to its right: the switch itself never moves, so a second tap on
	-- the same spot turns it off again. The row sits above where phone toasts pop up (the same spot,
	-- 62% across the bottom), so BIG BUMPS and the like never cover it.
	local tilt = if touch then api:Tilt() else nil
	local tiltOn = tilt ~= nil and tiltChosen
	local hintY = underStrip
	local hintUntil: number? = nil -- the hint stays up until 5 s after GO
	local function hintText(): string
		if not touch then
			return "Move to roll. Bump them off!"
		end
		return if tiltOn then "Tilt to roll. Bump them off!" else "Push the stick to roll. Bump them off!"
	end
	api:Hint(hintText(), hintY)
	local tiltUi: { Row: Frame, Switch: TextButton, Calibrate: TextButton, Flip: TextButton }? = nil
	local function tiltShown(): boolean
		return api:CanAct() and balls[myId] ~= nil
	end
	local function refreshTilt()
		local ui = tiltUi
		if not ui then
			return
		end
		ui.Row.Visible = tiltShown()
		ui.Switch.Text = if tiltOn then "TILT: ON" else "TILT: OFF"
		local gradient = ui.Switch:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = if tiltOn
				then ColorSequence.new(Theme.Colors.Pink, Color3.fromRGB(200, 50, 140))
				else ColorSequence.new(Theme.Colors.PanelLight, Theme.Colors.Panel)
		end
		ui.Calibrate.Visible = tiltOn
		ui.Flip.Visible = tiltOn
	end
	if tilt then
		local device = tilt
		-- The pills sit on the row's top line, left-aligned. Under them is room for two phone toasts
		-- (NotificationController: 39 units for one line, 58 for two, 8 apart), one of each.
		local toastRoom = 39 + 58 + 8 + 8
		local row = UIKit.new("Frame", {
			Name = "TiltControls",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.62, 0, 1, -8),
			Size = UDim2.fromOffset(446, Theme.Touch.Target + toastRoom),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = api.Gui,
			Children = {
				UIKit.new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Left,
					VerticalAlignment = Enum.VerticalAlignment.Top,
					Padding = UDim.new(0, 8),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
		})
		UIKit.AutoScale(row)
		local function pill(
			name: string,
			text: string,
			width: number,
			order: number,
			top: Color3,
			bottom: Color3,
			onClick: () -> ()
		): TextButton
			return UIKit.Button({
				Name = name,
				Text = text,
				TextSize = 24,
				TextWrapped = false,
				Size = UDim2.fromOffset(width, Theme.Touch.Target),
				CornerRadius = "round",
				LayoutOrder = order,
				Parent = row,
			}, onClick, top, bottom)
		end
		local switch = pill("TiltSwitch", "TILT: OFF", 160, 1, Theme.Colors.PanelLight, Theme.Colors.Panel, function()
			if not api:CanAct() then
				return
			end
			tiltOn = not tiltOn
			tiltChosen = tiltOn
			if tiltOn then
				device:Calibrate()
			end
			api:Sound("Click")
			refreshTilt()
			-- The start hint (up before GO and for 5 s after) says how to steer now. Once it's gone,
			-- the switch's own ON / OFF is the answer: no hint comes back over BIG BUMPS.
			if hintUntil == nil or hintUntil > os.clock() then
				api:Hint(hintText(), hintY)
			end
		end)
		local calibrate: TextButton
		calibrate = pill("Calibrate", "CALIBRATE", 170, 2, Theme.Colors.Cyan, Color3.fromRGB(40, 130, 220), function()
			device:Calibrate()
			api:Sound("Click")
			calibrate.Text = "✓ SET!"
			task.delay(1, function()
				calibrate.Text = "CALIBRATE"
			end)
		end)
		local flip = pill("Flip", "FLIP", 100, 3, Theme.Colors.Yellow, Theme.Colors.Orange, function()
			device:Flip()
			api:Sound("Click")
		end)
		tiltUi = { Row = row, Switch = switch, Calibrate = calibrate, Flip = flip }
		refreshTilt()
		api:OnCanAct(function()
			refreshTilt()
		end)
	end

	-- Steady camera (touch screens) ----------------------------------------------------------------
	-- Hangs behind and above the ball on one heading for the whole round (the way the rider faced at
	-- the start: towards the middle) and follows it without ever turning, so up on the stick is up
	-- the screen everywhere on the island. PC keeps Roblox's camera (it doesn't swing round).
	local steady = UserInputService.TouchEnabled
	local heading: Vector3? = nil -- the camera's flat forward, fixed once this player's ball is known
	local focus: Vector3? = nil
	local cameraTaken = false
	local savedFov = 70
	local function releaseCamera()
		if not cameraTaken then
			return
		end
		cameraTaken = false
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = savedFov
		-- Back to following this player (unless they already chose someone to watch).
		local character, humanoid = api:Character()
		local subject = camera.CameraSubject
		if
			humanoid
			and (not subject or not subject.Parent or (character ~= nil and subject:IsDescendantOf(character)))
		then
			camera.CameraSubject = humanoid
		end
	end
	api:Track(releaseCamera)
	local function steadyCamera(body: BasePart, place: any, dt: number)
		local camera = workspace.CurrentCamera
		if not heading then
			local toMiddle = flat(Vector3.new(place.X, 0, place.Z) - body.Position)
			heading = if toMiddle.Magnitude > 1 then toMiddle.Unit else Vector3.new(0, 0, -1)
		end
		if not cameraTaken then
			cameraTaken = true
			savedFov = camera.FieldOfView
		end
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable -- (again if a respawn put Roblox's back)
		end
		camera.FieldOfView = CAMERA_FOV
		-- Follow the ball across the island at its resting height: not up and down with every bump,
		-- and not down into the sea when it goes in.
		local position = body.Position
		local target = Vector3.new(position.X, place.Y + body.Size.Y / 2, position.Z)
		local at = if focus then focus:Lerp(target, 1 - math.exp(-dt * CAMERA_FOLLOW)) else target
		focus = at
		local back = (heading :: Vector3) * (math.cos(CAMERA_PITCH) * CAMERA_DISTANCE)
		local up = Vector3.new(0, math.sin(CAMERA_PITCH) * CAMERA_DISTANCE, 0)
		camera.CFrame = CFrame.lookAt(at - back + up, at)
		camera.Focus = CFrame.new(at)
	end

	-- A YOU marker over this player's ball, so they find themselves in a crowd.
	local marker: BillboardGui? = nil
	local function ensureMarker(body: BasePart)
		if marker and marker.Parent then
			return
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "YouMarker"
		gui.Adornee = body
		gui.Size = UDim2.fromOffset(70, 34)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 15, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Parent = api.World
		UIKit.Label({
			Text = "YOU ▼",
			Font = Theme.Fonts.Display,
			TextSize = 26,
			Size = UDim2.fromScale(1, 1),
			TextColor3 = Theme.Colors.Yellow,
			Parent = gui,
			Children = { UIKit.TextStroke(0) },
		})
		marker = gui
	end

	-- Where the player steers, as a flat world direction (length 1 at most): the stick (or keys) as
	-- the screen shows it, or tilt when it's on and the stick is let go.
	local function input(): Vector3
		local forward, right = cameraAxes()
		local move = Vector3.zero
		if controls then
			local ok, value = pcall(controls.GetMoveVector, controls)
			if ok and typeof(value) == "Vector3" then
				move = right * value.X - forward * value.Z
			end
		end
		if tilt and tiltOn and move.Magnitude < 0.15 then
			local value = tilt:Get()
			move = right * value.X + forward * value.Y
		end
		if move.Magnitude > 1 then
			move = move.Unit
		end
		return move
	end

	-- Foam rings that breathe around the island (ambient: off with reduced effects).
	local foam: { Part } = {}
	if island and not State.ReducedEffects() then
		for index = 1, 3 do
			local part = Instance.new("Part")
			part.Name = "Foam"
			part.Shape = Enum.PartType.Cylinder
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = Enum.Material.SmoothPlastic
			part.Color = Color3.fromRGB(240, 252, 255)
			part.Transparency = 0.6
			part.Size = Vector3.new(0.12, 2, 2)
			part.Parent = api.World
			part:SetAttribute("Phase", index / 3)
			table.insert(foam, part)
		end
	end

	-- Buoys and pool floats bob on the swell (ambient: off with reduced effects).
	local bobbers: { { Model: Model, Base: CFrame, Phase: number } } = {}
	local floatsFolder = arena:FindFirstChild("Floats")
	if floatsFolder and not State.ReducedEffects() then
		for _, model in floatsFolder:GetChildren() do
			if model:IsA("Model") then
				local base = model:GetPivot()
				local phase = (base.X * 0.07 + base.Z * 0.05) % (math.pi * 2)
				table.insert(bobbers, { Model = model, Base = base, Phase = phase })
			end
		end
	end

	local outAt: number? = nil
	local nextStrip = 0
	local nextBob = 0
	api:RenderStep(function(dt: number)
		local now = os.clock()
		-- Squash-and-stretch pulses (uniform, so they look right however the ball has rolled).
		for _, ball in balls do
			if ball.Pulse > 0.001 then
				ball.Pulse = math.max(0, ball.Pulse - dt * 0.9)
				local scale = 1 + math.sin(ball.Pulse * 40) * ball.Pulse
				for _, piece in ball.Pieces do
					if piece.Part.Parent then
						piece.Part.Size = piece.Size * scale
					end
				end
			end
		end
		if not hintUntil and State.Phase() == "InRound" then
			hintUntil = now + 5
			if tilt then
				tilt:Calibrate() -- calibrate on GO, however they hold the phone by then
			end
		elseif hintUntil and now > hintUntil and hintUntil > 0 then
			hintUntil = 0
			api:Hint("", hintY)
		end
		local alive = api:Alive()
		outAt = if alive then nil else outAt or now
		-- Riders strip (a few times a second is plenty).
		if now >= nextStrip then
			nextStrip = now + 0.25
			for userId, icon in icons do
				showOut(icon, icon.Out or not participantAlive(userId))
			end
			if tiltUi and tiltUi.Row.Visible ~= tiltShown() then
				refreshTilt() -- (this player's ball turned up)
			end
		end
		for _, part in foam do
			local phase = ((now * 0.18) + part:GetAttribute("Phase")) % 1
			local size = island.R * 2 + 6 + phase * 26
			part.Size = Vector3.new(0.12, size, size)
			part.Transparency = 0.55 + phase * 0.45
			part.CFrame = CFrame.new(island.X, island.Water + 0.2 + math.sin(now * 1.3 + phase * 6) * 0.06, island.Z)
				* CFrame.Angles(0, 0, math.rad(90))
		end

		-- A 0.22-stud bob reads fine at 30 Hz; skip the other frames to save phones the PivotTo calls.
		if now >= nextBob then
			nextBob = now + 1 / 30
			for _, bob in bobbers do
				local t = now * 1.4 + bob.Phase
				bob.Model:PivotTo(
					bob.Base
						* CFrame.new(0, math.sin(t) * 0.22, 0)
						* CFrame.Angles(math.sin(t * 0.8) * 0.05, 0, math.cos(t * 0.9) * 0.05)
				)
			end
		end

		local ball = balls[myId]
		local body = ball and ball.Body
		-- The steady camera rides with this player's ball while they're in (and on the splash for a
		-- moment after they go in), once it knows where the island is (it looks towards the middle).
		if steady and island and body and body.Parent and (alive or now - (outAt or now) < OUT_CAMERA) then
			steadyCamera(body, island, dt)
		else
			releaseCamera()
		end
		if not ball or not body or not body.Parent then
			edgeLabel.Visible = false
			return
		end
		ensureMarker(body)
		local onIsland = true -- (unknown only if the island never arrived: then it steers quickly everywhere)
		if island then
			local fromCenter = flat(body.Position - Vector3.new(island.X, 0, island.Z)).Magnitude
			local near = alive and fromCenter > island.R - EDGE_WARNING and body.Position.Y > island.Water
			edgeLabel.Visible = near and (now * 4) % 1 < 0.7
			onIsland = BumperDrive.Grips(fromCenter, body.Position.Y - island.Y, island.R, body.Size.Y / 2)
		end
		driving = ball.Model:GetAttribute("ClientDriven") == true and alive
		local force = body:FindFirstChild("Drive") :: VectorForce?
		if not driving then
			if wasDriving and force then
				force.Force = Vector3.zero -- out (or reset): stop pushing the ball
			end
			wasDriving = false
			return
		end
		wasDriving = true
		local character, humanoid, root = api:Character()
		if humanoid and not humanoid.PlatformStand then
			humanoid.PlatformStand = true
		end
		local move = input()
		local velocity = body.AssemblyLinearVelocity
		local ax, az = drive:Step(now, dt, velocity.X, velocity.Z, move.X, move.Z, onIsland)
		-- On the island the ball rolls, so it spins up as it speeds up: 7/5 of its mass, plus the
		-- rider (as the server does). Off it, in the air, it doesn't.
		local rider = if root then root.AssemblyMass else 0
		local mass = body.AssemblyMass * (if onIsland then BumperDrive.RollMass else 1) + rider
		if force then
			force.Force = Vector3.new(ax, 0, az) * mass
		end
		-- Face where we roll.
		local align = root and root:FindFirstChild("BumperUpright") :: AlignOrientation?
		if align and character then
			local facing = if flat(velocity).Magnitude > 2 then flat(velocity) else move
			if facing.Magnitude > 0.1 then
				local target = math.atan2(-facing.X, -facing.Z)
				local current = yaw or target
				local delta = (target - current + math.pi) % (math.pi * 2) - math.pi
				yaw = current + delta * math.min(1, dt * 8)
				align.CFrame = CFrame.Angles(0, yaw :: number, 0)
			end
		end
		-- Our ball touching another on screen: squash and boing now (the server's push follows).
		local size = body.Size.X
		for otherId, other in balls do
			local otherBody = other.Body
			if otherId == myId or not otherBody or not otherBody.Parent then
				continue
			end
			local gap = otherBody.Position - body.Position
			local apart = flat(gap)
			if
				gap.Magnitude > touchDistance
				or apart.Magnitude < 0.01
				or now - (localBoingAt[otherId] or -10) < 0.6
			then
				continue
			end
			local normal = apart.Unit
			local closing = flat(velocity):Dot(normal) - flat(otherBody.AssemblyLinearVelocity):Dot(normal)
			if closing >= closingMin then
				localBoingAt[otherId] = now
				local strength = math.clamp(closing / (maxSpeed * 2), 0.2, 1)
				boing(body.Position + normal * size / 2, strength, myId, otherId)
			end
		end
	end)

	api:Track(function()
		if RunService:IsClient() then
			local _, humanoid = api:Character()
			if humanoid then
				humanoid.PlatformStand = false
			end
		end
	end)
end

return BumperBallers

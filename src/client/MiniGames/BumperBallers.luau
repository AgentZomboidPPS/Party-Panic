-- Client half of Bumper Ballers: rolls this player's own ball and draws the round.
--
-- The server gives each player's ball to their device (ball model attribute ClientDriven). This
-- client then pushes it every frame with the same drive model the server uses for bots (MG_Tuning):
-- force = mass * (input * Accel - flat velocity * drag). Input is Roblox's own move vector (WASD,
-- arrows, thumbstick, gamepad: PlayerModule's controls), or phone TILT when the stick is idle.
-- On phones with an accelerometer there are CALIBRATE, FLIP and TILT/STICK buttons beside jump;
-- tilt switches itself off for good once someone has steered with the thumbstick for a second.
-- The server decides bumps and sends "Bump" (a velocity kick for this ball); everyone gets "Boing"
-- (a squash, a ring and a sound where two balls met) and "Splash" (someone fell in). This player's
-- own bumps squash and boing the moment the balls touch on screen, without waiting for the server.
--
-- Also: a strip of every rider's shape and color (dimmed with a cross when they're out), an EDGE!
-- warning near the rim, a YOU marker over this player's ball and gentle foam rings on the sea.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local BumperBallers = {}

local EDGE_WARNING = 8 -- studs from the rim

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
	local player = api.Player or Players.LocalPlayer
	local myId = player and player.UserId
	local tuning = api:SharedJSON("Tuning") or { Accel = 46, MaxSpeed = 24, Relief = 0.5, ReliefDrag = 0.3 }
	local island = api:SharedJSON("Island")
	local drag = tuning.Accel / tuning.MaxSpeed
	local hud = api:TopHud()
	local touch = api:IsTouch()

	-- Riders strip ----------------------------------------------------------------------------
	local strip = UIKit.new("Frame", {
		Name = "Riders",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY()),
		Size = UDim2.fromOffset(600, 40),
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
	local icons: { [number]: { Frame: Frame, Cross: TextLabel, Out: boolean } } = {}
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
		local frame = UIKit.new("Frame", {
			Name = "Rider" .. tostring(userId),
			Size = UDim2.fromOffset(if mine then 40 else 34, if mine then 40 else 34),
			BackgroundColor3 = color,
			LayoutOrder = if mine then -1 else model:GetAttribute("Index") or 0,
			Parent = strip,
			Children = {
				UIKit.Round(),
				UIKit.Stroke(Color3.new(1, 1, 1), if mine then 3 else 2, 0),
			},
		})
		UIKit.Label({
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
		local cross = UIKit.Label({
			Text = "X",
			Font = Enum.Font.GothamBlack,
			TextScaled = true,
			Size = UDim2.fromScale(1.1, 1.1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			TextColor3 = Theme.Colors.Red,
			Visible = false,
			ZIndex = 3,
			Parent = frame,
			Children = { UIKit.TextStroke(0) },
		})
		icons[userId] = { Frame = frame, Cross = cross, Out = false }
	end

	local bigBadge = UIKit.Label({
		Name = "BigBumps",
		Text = "💥 BIG BUMPS!",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY() + 46),
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
		Position = UDim2.new(0.5, 0, 0, api:HudY() + 84),
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
	local tilt = if touch then api:Tilt() else nil
	local tiltOn = tilt ~= nil
	local stickTime = 0 -- seconds steered with the thumbstick: after 1 s, tilt turns itself off
	local wasDriving = false
	local reliefUntil = 0
	local yaw: number? = nil
	local driving = false

	api:OnEvent("Bump", function(dv: Vector3, relief: number)
		local ball = balls[myId]
		local body = ball and ball.Body
		if typeof(dv) ~= "Vector3" or not body or not driving then
			return
		end
		reliefUntil = os.clock() + math.clamp(type(relief) == "number" and relief or 0.5, 0, 1)
		local _, _, root = api:Character()
		local mass = body.AssemblyMass + (if root then root.AssemblyMass else 0)
		body:ApplyImpulse(dv * mass)
		if dv.Magnitude > 9 then
			pulse(myId, math.clamp(dv.Magnitude / 40, 0.2, 1))
		end
	end)

	-- Tilt controls (phones with an accelerometer): CALIBRATE, FLIP and a TILT/STICK switch, all
	-- beside the jump button where the right thumb already is.
	local hintY = api:HudY() + 46
	local tiltUi: { Calibrate: any, Flip: any, Switch: any }? = nil
	local function refreshTiltUi()
		if not tiltUi then
			return
		end
		local alive = api:Alive()
		tiltUi.Switch:SetVisible(alive)
		tiltUi.Switch:SetText(if tiltOn then "TILT" else "STICK")
		tiltUi.Calibrate:SetVisible(alive and tiltOn)
		tiltUi.Flip:SetVisible(alive and tiltOn)
	end
	if tilt then
		local calibrate = api:Button({ Text = "CALIBRATE", Key = Enum.KeyCode.C, Color = Theme.Colors.Cyan })
		calibrate.Pressed:Connect(function()
			tilt:Calibrate()
			api:Sound("Click")
			calibrate:SetText("✓ SET!")
			task.delay(1, function()
				calibrate:SetText("CALIBRATE")
			end)
		end)
		local flip = api:Button({ Text = "FLIP", Key = Enum.KeyCode.F, Color = Theme.Colors.Yellow, Slot = 2 })
		flip.Pressed:Connect(function()
			tilt:Flip()
			api:Sound("Click")
		end)
		local switch = api:Button({ Text = "TILT", Key = Enum.KeyCode.T, Color = Theme.Colors.Pink, Slot = 3 })
		switch.Pressed:Connect(function()
			tiltOn = not tiltOn
			stickTime = if tiltOn then -math.huge else stickTime -- chose tilt themselves: keep it
			refreshTiltUi()
			api:Sound("Click")
		end)
		tiltUi = { Calibrate = calibrate, Flip = flip, Switch = switch }
		api:Hint("Tilt to roll! Bump them off!", hintY)
	else
		api:Hint(if touch then "Stick to roll. Bump them off!" else "Move to roll. Bump them off!", hintY)
	end
	local hintUntil: number? = nil -- the hint stays up until 5 s after GO

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

	local function input(dt: number): Vector3
		local forward, right = cameraAxes()
		local move = Vector3.zero
		if controls then
			local ok, value = pcall(controls.GetMoveVector, controls)
			if ok and typeof(value) == "Vector3" then
				move = right * value.X - forward * value.Z
			end
		end
		if tilt and tiltOn and move.Magnitude >= 0.15 then
			stickTime += dt
			if stickTime > 1 then
				tiltOn = false -- they steer with the stick: tilt would drift whenever they let go
				refreshTiltUi()
			end
		end
		if move.Magnitude < 0.15 and tilt and tiltOn then
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

	local wasAlive = nil
	local nextStrip = 0
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
		if alive ~= wasAlive then
			wasAlive = alive
			refreshTiltUi()
		end
		-- Riders strip (a few times a second is plenty).
		if now >= nextStrip then
			nextStrip = now + 0.25
			for userId, icon in icons do
				local out = icon.Out or not participantAlive(userId)
				icon.Cross.Visible = out
				icon.Frame.BackgroundTransparency = if out then 0.65 else 0
			end
		end
		for _, part in foam do
			local phase = ((now * 0.18) + part:GetAttribute("Phase")) % 1
			local size = island.R * 2 + 6 + phase * 26
			part.Size = Vector3.new(0.12, size, size)
			part.Transparency = 0.55 + phase * 0.45
			part.CFrame = CFrame.new(island.X, island.Water + 0.05 + math.sin(now * 1.3 + phase * 6) * 0.06, island.Z)
				* CFrame.Angles(0, 0, math.rad(90))
		end

		local ball = balls[myId]
		local body = ball and ball.Body
		if not body or not body.Parent then
			edgeLabel.Visible = false
			return
		end
		ensureMarker(body)
		if island then
			local fromCenter = flat(body.Position - Vector3.new(island.X, 0, island.Z)).Magnitude
			local near = api:Alive() and fromCenter > island.R - EDGE_WARNING and body.Position.Y > island.Water
			edgeLabel.Visible = near and (now * 4) % 1 < 0.7
		end
		driving = ball.Model:GetAttribute("ClientDriven") == true and api:Alive()
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
		local move = input(dt)
		local velocity = body.AssemblyLinearVelocity
		local k = if now < reliefUntil then drag * tuning.ReliefDrag else drag
		-- A rolling ball spins up as it speeds up: 7/5 of its mass, plus the rider (as the server does).
		local mass = body.AssemblyMass * 1.4 + (if root then root.AssemblyMass else 0)
		if force then
			force.Force = (move * tuning.Accel - flat(velocity) * k) * mass
		end
		-- Face where we roll.
		local align = root and root:FindFirstChild("BumperUpright") :: AlignOrientation?
		if align and character then
			local heading = if flat(velocity).Magnitude > 2 then flat(velocity) else move
			if heading.Magnitude > 0.1 then
				local target = math.atan2(-heading.X, -heading.Z)
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
			local gap = flat(otherBody.Position - body.Position)
			local distance = gap.Magnitude
			if distance > size + 0.4 or distance < 0.01 or now - (localBoingAt[otherId] or -10) < 0.6 then
				continue
			end
			local normal = gap.Unit
			local closing = flat(velocity):Dot(normal) - flat(otherBody.AssemblyLinearVelocity):Dot(normal)
			if closing > 4 then
				localBoingAt[otherId] = now
				local strength = math.clamp(closing / (tuning.MaxSpeed * 2), 0.2, 1)
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

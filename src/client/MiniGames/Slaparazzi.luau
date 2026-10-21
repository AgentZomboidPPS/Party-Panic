-- Client half of Slaparazzi: glides the photo frame (and the spotlights' light on it) from the
-- server's schedule (MG_Frame, Logic/Slaparazzi), counts down to each photo, flashes the camera, pops
-- up each photo as a snapshot card (a little picture of the frame with a dot for everyone in it and
-- who scored), and runs the SLAP button.
--
-- Slaps (fair hits, owner: "the precision games will feel super bad if we dont"): the button picks
-- the nearest rival in reach that this screen shows (in front first, Logic/Slaparazzi CLIENT_REACH,
-- a little inside the server's reach), turns you to face them and sends who it was; the server
-- judges against where they were on this screen. A hand marker floats over whoever a slap would hit
-- right now, so on a phone you know before pressing. The glove swings at once on your screen.
--
-- Phones first: the photo counter and the "in the shot" pill sit under the banner, the snapshot card
-- under them and only while it's up, the SLAP button beside the jump button. Points always come as a
-- number with the ring (+3 / +2 / +1), never color alone.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.Slaparazzi)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local Slaparazzi = {}

local GOLD = Color3.fromRGB(255, 205, 60)
local SILVER = Color3.fromRGB(215, 225, 240)
local BRONZE = Color3.fromRGB(225, 140, 80)
local RING_COLORS = { GOLD, SILVER, BRONZE }
local CARD_TIME = 2.8

local function ringColor(points: number): Color3
	if points >= 3 then
		return GOLD
	elseif points == 2 then
		return SILVER
	elseif points == 1 then
		return BRONZE
	end
	return Color3.fromRGB(150, 150, 165)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Slaparazzi.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 240, 248),
		Saturation = 0.15,
		Contrast = 0.08,
	})
	local localPlayer = Players.LocalPlayer
	local hud = api:TopHud()
	local y = api:HudY()

	-- The photo counter and countdown.
	local counter = UIKit.Panel({
		Name = "PhotoCounter",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(250, 50),
		CornerRadius = 18,
		Parent = hud,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local counterText = UIKit.Label({
		Text = "📸 PHOTO 1/7",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		Size = UDim2.fromScale(1, 1),
		Parent = counter,
		Children = { UIKit.TextStroke(0.15) },
	})
	-- Where you stand right now: +3 / +2 / +1 or OUT OF SHOT.
	local zone = UIKit.Panel({
		Name = "Zone",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y + 56),
		Size = UDim2.fromOffset(230, 40),
		CornerRadius = 14,
		Parent = hud,
	}, Theme.Colors.Panel, Theme.Colors.PanelDark)
	local zoneText = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		Size = UDim2.fromScale(1, 1),
		Parent = zone,
		Children = { UIKit.TextStroke(0.2) },
	})

	-- The snapshot card (shown for a moment after each photo).
	local card = UIKit.Panel({
		Name = "Snapshot",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y + 104),
		Size = UDim2.fromOffset(400, 150),
		CornerRadius = 12,
		Visible = false,
		Parent = hud,
	}, Color3.fromRGB(255, 255, 255), Color3.fromRGB(232, 228, 240))
	local picture = UIKit.new("Frame", {
		Name = "Picture",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(130, 130),
		BackgroundColor3 = Color3.fromRGB(70, 44, 52),
		ClipsDescendants = true,
		Parent = card,
		Children = { UIKit.Corner(6) },
	})
	local scale = 130 / (Rules.RINGS[3] * 2 + 3)
	for index = #Rules.RINGS, 1, -1 do
		local d = Rules.RINGS[index] * 2 * scale
		UIKit.new("Frame", {
			Name = "Ring" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(d, d),
			BackgroundTransparency = 1,
			Parent = picture,
			Children = { UIKit.Round(), UIKit.Stroke(RING_COLORS[index], 2, 0) },
		})
	end
	local dots = UIKit.new("Frame", {
		Name = "Dots",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = picture,
	})
	local cardTitle = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextColor3 = Color3.fromRGB(60, 40, 90),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(152, 8),
		Size = UDim2.fromOffset(240, 30),
		Parent = card,
	})
	local lines = {}
	for index = 1, 3 do
		lines[index] = UIKit.Label({
			Text = "",
			Font = Theme.Fonts.Bold,
			TextSize = 20,
			TextColor3 = Color3.fromRGB(50, 40, 70),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Position = UDim2.fromOffset(152, 12 + index * 26),
			Size = UDim2.fromOffset(240, 26),
			Parent = card,
		})
	end
	local mineLine = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(152, 114),
		Size = UDim2.fromOffset(240, 30),
		Parent = card,
		Children = { UIKit.TextStroke(0.3) },
	})

	-- The camera flash over the whole screen (its own gui so it also covers the safe-area edges).
	local flashGui = api:Track(UIKit.new("ScreenGui", {
		Name = "SlaparazziFlash",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 7,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	}))
	local flash = UIKit.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = flashGui,
	})

	-- The arena pieces this half moves.
	local arena = api:Arena()
	local frameModel: Model? = nil
	local beams: { BasePart } = {}
	local cameraModel: Model? = nil
	local paparazzi: { Model } = {}
	local function watch(child: Instance)
		if child.Name == "SlaparazziFrame" and child:IsA("Model") then
			frameModel = child
		elseif child.Name == "SpotBeam" and child:IsA("BasePart") then
			table.insert(beams, child)
		elseif child.Name == "MainCamera" and child:IsA("Model") then
			cameraModel = child
		elseif child.Name == "Paparazzo" and child:IsA("Model") then
			table.insert(paparazzi, child)
		end
	end
	if arena then
		for _, child in arena:GetChildren() do
			watch(child)
		end
		api:Track(arena.ChildAdded:Connect(watch))
	end

	-- A camera's flash bulb: bright for a moment (a light and the bulb glowing).
	local function pop(model: Model?, strong: boolean)
		local bulb = model and model:FindFirstChild("Bulb", true)
		if not bulb or not bulb:IsA("BasePart") then
			return
		end
		local light = bulb:FindFirstChild("FlashLight") :: PointLight?
		if not light then
			local made = Instance.new("PointLight")
			made.Name = "FlashLight"
			made.Color = Color3.fromRGB(255, 250, 230)
			made.Shadows = false
			made.Parent = bulb
			light = made
		end
		local lamp = light :: PointLight
		lamp.Range = if strong then 40 else 18
		lamp.Brightness = if strong then 8 else 4
		lamp.Enabled = true
		UIKit.Tween(lamp, 0.4, { Brightness = 0 })
		local size = bulb.Size
		bulb.Size = size * 1.6
		task.delay(0.12, function()
			bulb.Size = size
		end)
	end

	-- The countdown floating over the frame.
	local overFrame = Instance.new("Part")
	overFrame.Name = "CountdownAnchor"
	overFrame.Anchored = true
	overFrame.CanCollide = false
	overFrame.CanQuery = false
	overFrame.CanTouch = false
	overFrame.Transparency = 1
	overFrame.Size = Vector3.new(0.2, 0.2, 0.2)
	overFrame.Parent = api.World
	local countdown = UIKit.new("BillboardGui", {
		Name = "Countdown",
		Size = UDim2.fromOffset(110, 110),
		StudsOffset = Vector3.new(0, 9, 0),
		LightInfluence = 0,
		MaxDistance = 300,
		Enabled = false,
		Parent = overFrame,
	})
	local countdownText = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		TextColor3 = GOLD,
		Parent = countdown,
		Children = { UIKit.TextStroke(0) },
	})

	-- The hand over whoever a slap would hit now.
	local marker = UIKit.new("BillboardGui", {
		Name = "SlapTarget",
		Size = UDim2.fromOffset(56, 56),
		StudsOffset = Vector3.new(0, 4.2, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		Parent = api.World,
	})
	UIKit.Label({
		Text = "👋",
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		Parent = marker,
	})

	local frame: Rules.Frame? = api:SharedJSON("Frame")
	api:OnShared("Frame", function()
		frame = api:SharedJSON("Frame")
	end)

	-- Who a slap from here would hit right now: the nearest in reach, in front first.
	local function pickTarget(): (any, Model?)
		local _, _, root = api:Character()
		if not root then
			return nil, nil
		end
		local look = flat(root.CFrame.LookVector)
		local best, bestModel, bestScore = nil, nil, math.huge
		for _, participant in api:Participants() do
			if participant.UserId == localPlayer.UserId then
				continue
			end
			local model = participant:Character()
			local other = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not other then
				continue
			end
			local offset = flat(other.Position - root.Position)
			local distance = offset.Magnitude
			if distance > Rules.CLIENT_REACH or math.abs(other.Position.Y - root.Position.Y) > 4.5 then
				continue
			end
			local facing = if distance > 0.05 and look.Magnitude > 0.05 then look.Unit:Dot(offset.Unit) else 1
			local score = distance + (if facing >= 0.3 then 0 else 4)
			if score < bestScore then
				best, bestModel, bestScore = participant, model, score
			end
		end
		return best, bestModel
	end

	-- The glove swinging from a slapper toward where they slapped (palm first, across their front).
	local gloveTemplate = api:Template("SlaparazziGlove", 5)
	local function swing(fromModel: Model?, toModel: Model?)
		local fromRoot = fromModel and fromModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not fromRoot or not gloveTemplate then
			return
		end
		local glove = gloveTemplate:Clone() :: Model
		for _, part in glove:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
		glove.Parent = api.World
		local toRoot = toModel and toModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		local start = os.clock()
		local connection: RBXScriptConnection? = nil
		connection = api:Track(RunService.RenderStepped:Connect(function()
			local t = (os.clock() - start) / 0.28
			if t >= 1 or not fromRoot.Parent then
				glove:Destroy()
				if connection then
					connection:Disconnect()
				end
				return
			end
			local look = flat(fromRoot.CFrame.LookVector)
			if look.Magnitude < 0.05 then
				look = Vector3.new(0, 0, -1)
			end
			local aim = if toRoot and toRoot.Parent then flat(toRoot.Position - fromRoot.Position) else look.Unit * 4
			if aim.Magnitude < 0.5 then
				aim = look.Unit * 2
			end
			local side = Vector3.new(-aim.Unit.Z, 0, aim.Unit.X)
			local sweep = math.sin(math.min(t * 1.4, 1) * math.pi / 2)
			local reachOut = math.max(math.min(aim.Magnitude - 0.8, 3.6), 1) * sweep
			local position = fromRoot.Position
				+ Vector3.new(0, 0.6, 0)
				+ side * (1.8 - 3.2 * sweep)
				+ aim.Unit * (0.8 + reachOut)
			glove:PivotTo(
				CFrame.lookAt(position, position - side)
					* CFrame.new(0, -1.4, 0)
					* CFrame.Angles(0, 0, math.rad(-60 + 40 * sweep))
			)
		end))
	end

	-- A slap landing: stars and a SLAP! over the one hit.
	local function impact(toModel: Model?)
		local toRoot = toModel and toModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not toRoot then
			return
		end
		api:Effect("Stars", toRoot.Position + Vector3.new(0, 1.5, 0))
		local pow = UIKit.new("BillboardGui", {
			Name = "Pow",
			Size = UDim2.fromOffset(150, 60),
			StudsOffset = Vector3.new(0, 3.5, 0),
			AlwaysOnTop = true,
			LightInfluence = 0,
			MaxDistance = 140,
			Adornee = toRoot,
			Parent = api.World,
		})
		local label = UIKit.Label({
			Text = "SLAP!",
			Font = Theme.Fonts.Display,
			TextScaled = true,
			TextColor3 = Theme.Colors.Yellow,
			Size = UDim2.fromScale(1, 1),
			Parent = pow,
			Children = { UIKit.TextStroke(0) },
		})
		UIKit.PopIn(label, 0.25)
		task.delay(0.7, function()
			pow:Destroy()
		end)
	end

	-- The SLAP button and its cooldown.
	local slap = api:Button({ Text = "SLAP", Key = Enum.KeyCode.E, Color = Theme.Colors.Pink })
	local readyAt = 0
	local function refreshReady()
		local ready = api:Mine("Ready")
		if type(ready) == "number" then
			readyAt = math.max(readyAt, ready)
		end
	end
	api:OnMine("Ready", refreshReady)
	slap.Pressed:Connect(function()
		local now = api:Now()
		if now < readyAt - 0.05 then
			return
		end
		local _, humanoid, root = api:Character()
		if not root or not humanoid or humanoid.PlatformStand then
			return
		end
		local target, model = pickTarget()
		local targetRoot = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			local at = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
			if flat(at - root.Position).Magnitude > 0.1 then
				root.CFrame = CFrame.lookAt(root.Position, at)
			end
		end
		readyAt = now + Rules.COOLDOWN
		api:Action("Slap", if target then target.UserId else 0)
		swing(api:Character(), model)
		api:Sound("Boing")
	end)

	api:OnEvent("Slap", function(slapperId, targetId, hit)
		if type(slapperId) ~= "number" then
			return
		end
		local targetModel = if type(targetId) == "number" and targetId ~= 0 then api:CharacterOf(targetId) else nil
		local mine = slapperId == localPlayer.UserId
		if not mine then
			swing(api:CharacterOf(slapperId), targetModel)
		end
		if hit == true then
			task.delay(if mine then 0 else 0.12, impact, targetModel)
		end
		if hit == true then
			api:Sound("Hit")
			if targetId == localPlayer.UserId then
				local camera = workspace.CurrentCamera
				local strength = if State.ReducedEffects() then 0.1 else 0.35
				for step = 1, 6 do
					task.delay(step * 0.03, function()
						camera.CFrame *= CFrame.Angles(
							math.rad(math.random(-10, 10) * strength * 0.2),
							math.rad(math.random(-10, 10) * strength * 0.2),
							0
						)
					end)
				end
			end
		end
	end)

	-- The flash.
	api:OnEvent("Flash", function(number)
		pop(cameraModel, true)
		api:Sound("Click")
		flash.Visible = true
		flash.BackgroundTransparency = if State.ReducedEffects() then 0.55 else 0.05
		UIKit.Tween(flash, 0.5, { BackgroundTransparency = 1 })
		task.delay(0.55, function()
			flash.Visible = false
		end)
		if type(number) == "number" then
			counterText.Text = `📸 SNAP! {number}/{if frame then frame.Of else 7}`
		end
	end)

	-- The snapshot card.
	local cardShownAt = -math.huge
	local function showPhoto()
		local photo = api:SharedJSON("Photo")
		if not photo or type(photo.Shots) ~= "table" then
			return
		end
		for _, child in dots:GetChildren() do
			child:Destroy()
		end
		local names = {}
		for _, participant in api:Participants() do
			names[participant.UserId] = participant.DisplayName
		end
		local mine = 0
		local inShot = 0
		for _, shot in photo.Shots do
			local isMe = shot.U == localPlayer.UserId
			if isMe then
				mine = shot.P
			end
			if shot.P > 0 then
				inShot += 1
			end
			local size = if isMe then 16 else 11
			UIKit.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, shot.X * scale, 0.5, shot.Z * scale),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = if isMe then Theme.Colors.Pink else ringColor(shot.P),
				ZIndex = if isMe then 5 else 4,
				Parent = dots,
				Children = { UIKit.Round(), UIKit.Stroke(Color3.new(1, 1, 1), if isMe then 3 else 1.5, 0) },
			})
		end
		cardTitle.Text = `📸 PHOTO {photo.N}/{if frame then frame.Of else 7}`
		local shown = 0
		for _, shot in photo.Shots do
			if shot.P <= 0 or shown >= 3 then
				continue
			end
			shown += 1
			local name = names[shot.U] or "?"
			lines[shown].Text = `+{shot.P}  {name}`
			lines[shown].TextColor3 = if shot.U == localPlayer.UserId
				then Color3.fromRGB(220, 40, 130)
				else Color3.fromRGB(50, 40, 70)
		end
		for index = shown + 1, 3 do
			lines[index].Text = if index == 1 and shown == 0 then "Nobody in the shot!" else ""
			lines[index].TextColor3 = Color3.fromRGB(50, 40, 70)
		end
		if inShot > 3 and shown == 3 then
			lines[3].Text ..= `  +{inShot - 3} more`
		end
		if api:CanAct() then
			mineLine.Text = if mine > 0 then `YOU +{mine}!` else "YOU: missed it!"
			mineLine.TextColor3 = if mine > 0 then ringColor(mine) else Theme.Colors.Red
		else
			mineLine.Text = ""
		end
		card.Visible = true
		cardShownAt = os.clock()
		UIKit.PopIn(card, 0.3)
	end
	api:OnShared("Photo", showPhoto)

	-- Every frame: glide the frame and the spotlights, count down, mark the slap target, the zone.
	local lastBeat = -1
	local nextAmbient = os.clock() + 2
	api:RenderStep(function()
		local now = api:Now()
		local current = frame
		if not current then
			return
		end
		local x, z = Rules.FrameAt(current, now)
		local center = Vector3.new(x, current.Y, z)
		if frameModel then
			frameModel:PivotTo(CFrame.new(x, current.Y + 0.03, z))
		end
		for _, beam in beams do
			beam.CFrame = CFrame.lookAt(beam.Position, center)
		end
		overFrame.CFrame = CFrame.new(center)

		-- The counter and the countdown.
		local left = current.Shot - now
		if current.Done then
			counterText.Text = "📸 THAT'S A WRAP!"
			countdown.Enabled = false
		elseif left > 1e5 then
			counterText.Text = `📸 PHOTO 1/{current.Of}`
			countdown.Enabled = false
		elseif left > -0.6 then
			local beat = math.ceil(left)
			if left > 0 then
				counterText.Text = `📸 PHOTO {current.N}/{current.Of} · {beat}`
			end
			countdown.Enabled = left > 0 and left <= 3
			countdownText.Text = tostring(beat)
			if beat ~= lastBeat and left > 0 and left <= 3 then
				lastBeat = beat
				api:Sound("Countdown")
				UIKit.PopIn(countdownText, 0.25)
			end
		end

		-- Where you stand now.
		local _, _, root = api:Character()
		if root and api:CanAct() then
			local distance = flat(root.Position - center).Magnitude
			local points = if math.abs(root.Position.Y - current.Y) < 8 then Rules.PointsFor(distance) else 0
			zone.Visible = not current.Done
			zoneText.Text = if points > 0 then `IN THE SHOT +{points}` else "OUT OF THE SHOT"
			zoneText.TextColor3 = if points > 0 then ringColor(points) else Theme.Colors.TextDim
		else
			zone.Visible = false
		end

		-- The slap button's cooldown and target marker.
		local cooling = math.clamp((readyAt - now) / Rules.COOLDOWN, 0, 1)
		slap:SetFill(cooling)
		slap:SetEnabled(cooling <= 0.03)
		local _, model = pickTarget()
		local head = model and model:FindFirstChild("Head") :: BasePart?
		marker.Adornee = head
		marker.Enabled = head ~= nil and cooling <= 0.03 and api:CanAct()

		if card.Visible and os.clock() - cardShownAt > CARD_TIME then
			card.Visible = false
		end

		-- The other paparazzi snap now and then (ambient; off with reduced effects).
		if os.clock() >= nextAmbient then
			nextAmbient = os.clock() + math.random() * 1.6 + 0.6
			if not State.ReducedEffects() and #paparazzi > 0 then
				pop(paparazzi[math.random(1, #paparazzi)], false)
			end
		end
	end)
end

return Slaparazzi

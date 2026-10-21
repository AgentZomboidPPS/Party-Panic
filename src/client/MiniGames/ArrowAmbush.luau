-- Client half of Arrow Ambush: rolls the target boards along their rails from the shared
-- schedule (MG_Layout), flies every arrow the server planned (event "Arrow") with a landing ring
-- that shows where it comes down, sticks arrows in the ground or in a board, and puts a bow in
-- every archer's hands (bots too, through api:Participants()).
--
-- ARCHERS get a fixed view over the courtyard from behind the tower, a reticle where the mouse
-- points (or where the finger is), the arrow's path as a line of beads that stops at any board
-- in the way, and a reload bar. Click, or tap and release, to shoot. Their move controls are
-- put away (they can't walk), so the whole screen is free to tap. RUNNERS play normally and
-- watch for the rings.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GameState = require(ReplicatedStorage.Shared.GameState)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ArrowAmbush = {}

local ARCHER_COLOR = Color3.fromRGB(255, 120, 60)
local RUNNER_COLOR = Color3.fromRGB(80, 200, 255)
local RING_COLOR = Color3.fromRGB(255, 70, 60)
local READY_COLOR = Color3.fromRGB(255, 240, 120)
local BADGE_COLORS = { Color3.fromRGB(120, 220, 120), Color3.fromRGB(80, 190, 255), Color3.fromRGB(255, 200, 60) }
local BEADS = 16

local function pointAt(from: Vector3, to: Vector3, arc: number, s: number): Vector3
	return from:Lerp(to, s) + Vector3.new(0, 4 * arc * s * (1 - s), 0)
end

local function flight(distance: number): (number, number)
	return 0.32 + distance / 95, 1.5 + distance * 0.04
end

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- A flat disc lying on the ground (cylinders run along X; stand them on Y).
local function flatDisc(diameter: number, color: Color3, transparency: number, parent: Instance): Part
	return part({
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.06, diameter, diameter),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = transparency,
		Parent = parent,
	})
end

local function quiet(model: Instance)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
end

local function modelHeight(model: Model): number
	local _, size = model:GetBoundingBox()
	return size.Y
end

function ArrowAmbush.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 246, 232),
		Saturation = 0.12,
		Contrast = 0.06,
	})
	local layout = api:SharedJSON("Layout")
	local waited = 0
	while not layout and waited < 10 do
		task.wait(0.1)
		waited += 0.1
		layout = api:SharedJSON("Layout")
	end
	if not layout then
		return
	end
	local floorY: number = layout.Floor
	local origin = v3(layout.Origin)
	local tower = v3(layout.Tower)
	local bounds = layout.Bounds
	local hitRadius: number = layout.Hit
	local cooldown: number = layout.Cooldown
	local boardHalf: number = layout.BoardHalf
	local boardsT0: number = layout.BoardsT0
	local me = Players.LocalPlayer

	local role = api:Mine("Role")
	for _ = 1, 30 do
		if role then
			break
		end
		task.wait(0.1)
		role = api:Mine("Role")
	end
	local isArcher = role == "Archer"
	local effects = not State.ReducedEffects()

	-- Boards ------------------------------------------------------------------------------------
	local boards = {}
	for index, data in layout.Boards do
		local model = api:Template("TargetBoard") :: Model?
		if not model then
			continue
		end
		quiet(model)
		for _, descendant in model:GetDescendants() do
			if
				descendant:IsA("BasePart")
				and descendant.Name ~= "Face"
				and descendant.Name ~= "Rings"
				and descendant.Name ~= "Bull"
			then
				descendant.CanCollide = true -- runners bump into the boards they hide behind
			end
		end
		local anchor = part({
			Name = "BadgeAnchor",
			Size = Vector3.one * 0.2,
			Transparency = 1,
			CFrame = model:GetPivot() + Vector3.new(0, 9.3, 0),
			Parent = model,
		})
		local badge = Instance.new("BillboardGui")
		badge.Name = "Badge"
		badge.Size = UDim2.fromScale(3.2, 1.8)
		badge.LightInfluence = 0
		badge.MaxDistance = 220
		badge.Adornee = anchor
		badge.Parent = anchor
		local value = math.clamp(data.V or 1, 1, 3)
		UIKit.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = BADGE_COLORS[value],
			Parent = badge,
			Children = { UIKit.Round(), UIKit.Stroke(Color3.new(1, 1, 1), 3, 0) },
		})
		UIKit.Label({
			Text = `🎯+{value}`,
			Font = Theme.Fonts.Display,
			TextScaled = true,
			Size = UDim2.fromScale(0.9, 0.8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 2,
			Parent = badge,
			Children = { UIKit.TextStroke(0.1) },
		})
		model.Name = "Board" .. index
		model.Parent = api.World
		table.insert(boards, { Data = data, Model = model, Wobble = 0, WobbleAt = -1 })
	end

	local function boardX(data, t: number): number
		return origin.X + data.C + data.A * math.sin(data.W * (t - boardsT0) + data.P)
	end
	local function boardFrame(board, t: number): CFrame
		local frame = CFrame.new(boardX(board.Data, t), floorY, origin.Z + board.Data.Z)
		local since = t - board.WobbleAt
		if since >= 0 and since < 0.8 then
			frame *= CFrame.Angles(math.sin(since * 30) * 0.12 * (1 - since / 0.8), 0, 0)
		end
		return frame
	end

	-- The first board a path crosses (same check as the server's), as a fraction of the path.
	local function firstBlock(from: Vector3, to: Vector3, arc: number, t0: number, total: number): number?
		local previous = from
		for step = 1, 32 do
			local s = step / 32
			local point = pointAt(from, to, arc, s)
			for _, board in boards do
				local planeZ = origin.Z + board.Data.Z
				local a, b = previous.Z - planeZ, point.Z - planeZ
				if a == b or (a > 0 and b > 0) or (a < 0 and b < 0) then
					continue
				end
				local f = a / (a - b)
				local hit = previous:Lerp(point, f)
				local frac = (step - 1 + f) / 32
				local x = boardX(board.Data, t0 + total * frac)
				local height = hit.Y - floorY
				if math.abs(hit.X - x) <= boardHalf and height <= 8 and height > -0.5 then
					return frac
				end
			end
			previous = point
		end
		return nil
	end

	-- Bows in every archer's hands -------------------------------------------------------------
	local bows = {} -- userId -> { Model, Nocked, ShotAt }
	local lastShot = {} -- userId -> client time of their last shot
	local function refreshBows()
		local here = {}
		for _, who in api:Participants() do
			if who:GetAttribute("PP_Team") ~= "Archers" then
				continue
			end
			here[who.UserId] = true
			if not bows[who.UserId] then
				local bow = api:Template("AmbushBow") :: Model?
				local nocked = api:Template("AmbushArrow") :: Model?
				if bow then
					quiet(bow)
					bow.Parent = api.World
				end
				if nocked then
					quiet(nocked)
					nocked.Parent = api.World
				end
				bows[who.UserId] = { Model = bow, Nocked = nocked, Who = who }
			end
		end
		for userId, entry in bows do
			if not here[userId] then
				if entry.Model then
					entry.Model:Destroy()
				end
				if entry.Nocked then
					entry.Nocked:Destroy()
				end
				bows[userId] = nil
			end
		end
	end
	refreshBows()
	task.delay(1.5, refreshBows)
	task.delay(4, refreshBows)

	local arrowTemplate = api:Template("AmbushArrow") :: Model?
	local arrowHeight = if arrowTemplate then modelHeight(arrowTemplate) else 0.63
	-- The arrow model's pivot sits under its middle; its head is 2.2 studs in front of that.
	local function arrowFrame(tip: Vector3, direction: Vector3): CFrame
		local look = if direction.Magnitude > 1e-3 then direction.Unit else Vector3.new(0, -1, 0)
		local up = if math.abs(look.Y) > 0.98 then Vector3.new(0, 0, 1) else Vector3.yAxis
		return CFrame.lookAt(tip, tip + look, up) * CFrame.new(0, -arrowHeight / 2, 2.2)
	end

	-- Arrows -----------------------------------------------------------------------------------
	local arrows = {} -- id -> flight
	local function addRing(position: Vector3)
		local ring = Instance.new("Model")
		ring.Name = "LandingRing"
		local outer = flatDisc(hitRadius * 2, RING_COLOR, 0.35, ring)
		outer.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local inner = flatDisc(hitRadius * 2 - 0.5, Color3.fromRGB(255, 255, 255), 0.55, ring)
		inner.Material = Enum.Material.SmoothPlastic
		inner.CFrame = outer.CFrame + Vector3.new(0, 0.01, 0)
		local fill = flatDisc(0.4, RING_COLOR, 0.15, ring)
		fill.CFrame = outer.CFrame + Vector3.new(0, 0.02, 0)
		-- A cross through the ring, so the warning is a shape and not only a color.
		local bars = {}
		for k = 0, 1 do
			local bar = part({
				Name = "Cross",
				Size = Vector3.new(hitRadius * 2.3, 0.07, 0.32),
				Color = RING_COLOR,
				Material = Enum.Material.Neon,
				Transparency = 0.2,
				Parent = ring,
			})
			bar.CFrame = CFrame.new(position + Vector3.new(0, 0.14, 0)) * CFrame.Angles(0, math.rad(45 + 90 * k), 0)
			table.insert(bars, bar)
		end
		ring.Parent = api.World
		return { Model = ring, Fill = fill, Bars = bars, Position = position }
	end

	api:OnEvent("Arrow", function(data)
		if type(data) ~= "table" or not arrowTemplate then
			return
		end
		local model = arrowTemplate:Clone()
		quiet(model)
		if effects then
			local primary = model.PrimaryPart
			if primary then
				local a0 = Instance.new("Attachment")
				a0.Position = Vector3.new(0, 0.12, 0)
				a0.Parent = primary
				local a1 = Instance.new("Attachment")
				a1.Position = Vector3.new(0, -0.12, 0)
				a1.Parent = primary
				local trail = Instance.new("Trail")
				trail.Attachment0 = a0
				trail.Attachment1 = a1
				trail.Lifetime = 0.16
				trail.LightEmission = 0.6
				trail.FaceCamera = true
				trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
				trail.Transparency = NumberSequence.new(0.4, 1)
				trail.Parent = primary
			end
		end
		local from, to = v3(data.From), v3(data.To)
		model:PivotTo(arrowFrame(from, to - from))
		model.Parent = api.World
		local entry = {
			Data = data,
			Model = model,
			From = from,
			To = to,
			Ring = if data.Board == 0 then addRing(to) else nil,
			Done = false,
			Board = if data.Board > 0 then boards[data.Board] else nil,
		}
		arrows[data.Id] = entry
		lastShot[data.By] = os.clock()
		if data.By == me.UserId then
			api:Sound("Click")
		end
	end)

	local function finish(entry, tip: Vector3, direction: Vector3)
		entry.Done = true
		entry.DoneAt = os.clock()
		entry.Stuck = arrowFrame(tip, direction)
		if entry.Ring then
			entry.Ring.Model:Destroy()
			entry.Ring = nil
		end
		if entry.Board then
			entry.Offset = boardFrame(entry.Board, api:Now()):ToObjectSpace(entry.Stuck)
		end
	end

	api:OnEvent("BoardHit", function(id, index, value)
		local board = boards[index]
		if board then
			board.WobbleAt = api:Now()
		end
		local entry = arrows[id]
		local by = entry and entry.Data.By
		if board and type(value) == "number" then
			local anchor = board.Model:FindFirstChild("BadgeAnchor") :: BasePart?
			if anchor then
				api:Effect(
					"Sparkles",
					anchor.Position - Vector3.new(0, 4, 0),
					{ BADGE_COLORS[math.clamp(value, 1, 3)] }
				)
			end
		end
		if by == me.UserId then
			api:Sound("Pickup")
		end
	end)

	api:OnEvent("Landed", function(id)
		local entry = arrows[id]
		if entry and effects then
			api:Effect("Poof", entry.To)
		end
	end)

	-- HUD --------------------------------------------------------------------------------------
	local hud = api:TopHud()
	local y = api:HudY()
	local chip = UIKit.Panel(
		{
			Name = "Role",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y),
			Size = UDim2.fromOffset(380, 48),
			Parent = hud,
		},
		if isArcher then ARCHER_COLOR else RUNNER_COLOR,
		if isArcher then Color3.fromRGB(200, 70, 40) else Color3.fromRGB(40, 120, 220)
	)
	UIKit.Label({
		Text = if isArcher
			then (if api:IsTouch() then "🏹 ARCHER • TAP TO SHOOT" else "🏹 ARCHER • CLICK TO SHOOT")
			else "🏃 RUNNER • DODGE & HIDE",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -20, 1, -12),
		Parent = chip,
		Children = { UIKit.TextStroke(0.2) },
	})

	local reload, reloadFill, reloadText
	if isArcher then
		reload = UIKit.new("Frame", {
			Name = "Reload",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y + 56),
			Size = UDim2.fromOffset(260, 30),
			BackgroundColor3 = Color3.fromRGB(30, 22, 50),
			BackgroundTransparency = 0.25,
			Parent = hud,
			Children = { UIKit.Round(), UIKit.Stroke(Color3.new(1, 1, 1), 2, 0.4) },
		})
		reloadFill = UIKit.new("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = READY_COLOR,
			Parent = reload,
			Children = { UIKit.Round() },
		})
		reloadText = UIKit.Label({
			Text = "READY!",
			Font = Theme.Fonts.Display,
			TextSize = 22,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = reload,
			Children = { UIKit.TextStroke(0.2) },
		})
	end

	-- The role intro: big for a few seconds, then it gets out of the way.
	local intro = UIKit.Label({
		Name = "Intro",
		Text = if isArcher then "🏹 YOU'RE AN ARCHER!" else "🏃 YOU'RE A RUNNER!",
		Font = Theme.Fonts.Display,
		TextSize = 52,
		TextColor3 = if isArcher then ARCHER_COLOR else RUNNER_COLOR,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y + 96),
		Size = UDim2.fromOffset(600, 60),
		Parent = hud,
		Children = { UIKit.TextStroke(0) },
	})
	local introSub = UIKit.Label({
		Name = "IntroSub",
		Text = if isArcher then "Tag every runner!" else "Survive the arrows!",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y + 156),
		Size = UDim2.fromOffset(600, 40),
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})
	UIKit.PopIn(intro, 0.45)
	-- The client half starts with the countdown: keep the intro up until a moment after GO.
	local function afterGo(seconds: number, callback: () -> ())
		task.spawn(function()
			for _ = 1, 200 do
				if GameState.Get("Phase") ~= "Preparing" then
					break
				end
				task.wait(0.1)
			end
			task.wait(seconds)
			callback()
		end)
	end
	afterGo(2.5, function()
		if intro.Parent and intro.Text ~= "🎯 TAGGED!" then
			UIKit.Tween(intro, 0.4, { TextTransparency = 1 })
			UIKit.Tween(introSub, 0.4, { TextTransparency = 1 })
			local s1 = intro:FindFirstChildOfClass("UIStroke")
			local s2 = introSub:FindFirstChildOfClass("UIStroke")
			if s1 then
				UIKit.Tween(s1, 0.4, { Transparency = 1 })
			end
			if s2 then
				UIKit.Tween(s2, 0.4, { Transparency = 1 })
			end
		end
	end)

	api:OnEvent("Tagged", function(userId, x, yy, z, _by)
		if type(x) ~= "number" then
			return
		end
		local at = Vector3.new(x, yy, z)
		api:Effect("Stars", at)
		api:Sound("Hit")
		if userId == me.UserId then
			intro.Text = "🎯 TAGGED!"
			intro.TextColor3 = RING_COLOR
			intro.TextTransparency = 0
			introSub.Text = ""
			UIKit.PopIn(intro, 0.3)
		end
	end)

	-- Archer controls ----------------------------------------------------------------------------
	local aim: Vector3? = nil
	local aimingTouch: InputObject? = nil
	local reticle, beads, reticleRing
	if isArcher then
		local camera = workspace.CurrentCamera
		local savedType, savedFov = camera.CameraType, camera.FieldOfView
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 55
		local eye = tower + Vector3.new(0, 16, -18)
		local focus = Vector3.new(origin.X, floorY, origin.Z + 5)
		camera.CFrame = CFrame.lookAt(eye, focus)
		api:Track(function()
			camera.CameraType = savedType
			camera.FieldOfView = savedFov
			local _, humanoid = api:Character()
			if humanoid then
				humanoid.AutoRotate = true
			end
		end)

		-- Put the move controls away: archers stand still, and the whole screen is for aiming.
		local controls = nil
		pcall(function()
			local scripts = me:FindFirstChild("PlayerScripts")
			local module = scripts and scripts:FindFirstChild("PlayerModule")
			if module then
				controls = (require(module :: any) :: any):GetControls()
				controls:Disable()
			end
		end)
		api:Track(function()
			if controls then
				pcall(function()
					controls:Enable()
				end)
			end
		end)

		reticle = Instance.new("Model")
		reticle.Name = "Reticle"
		reticleRing = flatDisc(hitRadius * 2, READY_COLOR, 0.3, reticle)
		local hole = flatDisc(hitRadius * 2 - 0.6, Color3.new(1, 1, 1), 0.85, reticle)
		hole.Material = Enum.Material.SmoothPlastic
		hole.Name = "Hole"
		for k = 0, 3 do
			local tick = part({
				Name = "Tick",
				Size = Vector3.new(1.2, 0.08, 0.3),
				Color = READY_COLOR,
				Material = Enum.Material.Neon,
				Parent = reticle,
			})
			tick:SetAttribute("Angle", k * 90)
		end
		reticle.Parent = api.World
		beads = {}
		for index = 1, BEADS do
			table.insert(
				beads,
				part({
					Name = "Bead",
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * 0.35,
					Color = READY_COLOR,
					Material = Enum.Material.Neon,
					Transparency = 1,
					Parent = api.World,
				})
			)
			beads[index]:SetAttribute("Index", index)
		end

		local function groundPoint(screen: Vector2): Vector3?
			local ray = camera:ScreenPointToRay(screen.X, screen.Y)
			if ray.Direction.Y >= -1e-3 then
				return nil
			end
			local t = (floorY - ray.Origin.Y) / ray.Direction.Y
			local hit = ray.Origin + ray.Direction * t
			return Vector3.new(
				math.clamp(hit.X, bounds[1] - 1, bounds[2] + 1),
				floorY,
				math.clamp(hit.Z, bounds[3] - 1, bounds[4] + 1)
			)
		end
		local function shoot(at: Vector3?)
			if not at or not api:Alive() then
				return
			end
			local ready = api:Mine("NextShot") or 0
			if api:Now() < ready - 0.05 then
				return
			end
			api:Action("Shoot", at.X, at.Z)
		end

		api:Track(UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				aim = groundPoint(Vector2.new(input.Position.X, input.Position.Y))
				shoot(aim)
			elseif input.UserInputType == Enum.UserInputType.Touch and not aimingTouch then
				aimingTouch = input
				aim = groundPoint(Vector2.new(input.Position.X, input.Position.Y))
			end
		end))
		api:Track(UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement or input == aimingTouch then
				aim = groundPoint(Vector2.new(input.Position.X, input.Position.Y))
			end
		end))
		api:Track(UserInputService.InputEnded:Connect(function(input)
			if input == aimingTouch then
				aim = groundPoint(Vector2.new(input.Position.X, input.Position.Y))
				aimingTouch = nil
				shoot(aim)
			end
		end))
		api:Hint(if api:IsTouch() then "Tap where to shoot!" else "Click where to shoot!", y + 200)
		afterGo(5, function()
			api:Hint("")
		end)
	else
		api:Hint("Watch for the red rings! Hide behind the boards!", y + 200)
		afterGo(5, function()
			api:Hint("")
		end)
	end

	-- Every frame --------------------------------------------------------------------------------
	api:RenderStep(function()
		local now = api:Now()
		local clock = os.clock()
		for _, board in boards do
			board.Model:PivotTo(boardFrame(board, now))
		end

		for id, entry in arrows do
			local data = entry.Data
			if not entry.Done then
				local s = math.clamp((now - data.T0) / data.Flight, 0, 1)
				local stopS = math.clamp((data.T1 - data.T0) / data.Flight, 0, 1)
				local reached = s >= stopS or now >= data.T1
				s = math.min(s, stopS)
				local tip = pointAt(entry.From, entry.To, data.Arc, s)
				local direction = (entry.To - entry.From) + Vector3.new(0, 4 * data.Arc * (1 - 2 * s), 0)
				entry.Model:PivotTo(arrowFrame(tip, direction))
				if entry.Ring then
					local progress = math.clamp((now - data.T0) / math.max(0.05, data.T1 - data.T0), 0, 1)
					local size = 0.4 + (hitRadius * 2 - 0.5) * progress
					entry.Ring.Fill.Size = Vector3.new(0.06, size, size)
					for k, bar in entry.Ring.Bars do
						bar.CFrame = CFrame.new(entry.Ring.Position + Vector3.new(0, 0.14, 0))
							* CFrame.Angles(0, math.rad(45 + 90 * k) + progress * 1.5, 0)
					end
				end
				if reached then
					finish(entry, tip, direction)
				end
			else
				if entry.Board and entry.Offset then
					entry.Model:PivotTo(boardFrame(entry.Board, now) * entry.Offset)
				end
				local age = clock - entry.DoneAt
				if age > 1.6 then
					entry.Model:Destroy()
					arrows[id] = nil
				end
			end
		end

		-- Bows: held in front of each archer, kicking back when they shoot.
		for userId, entry in bows do
			local character = entry.Who:Character()
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root or not entry.Model then
				continue
			end
			local since = clock - (lastShot[userId] or -10)
			local kick = if since < 0.25 then (1 - since / 0.25) * 0.35 else 0
			local hold = root.CFrame * CFrame.new(0.35, 0.5, -1.4 + kick) * CFrame.Angles(0, 0, math.rad(-12))
			entry.Model:PivotTo(hold * CFrame.new(0, -2.42, 0.39))
			if entry.Nocked then
				local ready = since > cooldown * 0.7
				entry.Nocked:PivotTo(hold * CFrame.new(0, 0, -0.9) * CFrame.new(0, -arrowHeight / 2, 2.2))
				for _, piece in entry.Nocked:GetDescendants() do
					if piece:IsA("BasePart") then
						piece.LocalTransparencyModifier = if ready then 0 else 1
					end
				end
			end
		end

		-- The local archer: face the aim, draw the reticle, the path and the reload bar.
		if isArcher and reticle and reticleRing and beads then
			local nextShot = api:Mine("NextShot") or 0
			local ready = now >= nextShot - 0.05
			local fraction = if ready then 1 else math.clamp(1 - (nextShot - now) / cooldown, 0, 1)
			if reloadFill and reloadText then
				reloadFill.Size = UDim2.fromScale(fraction, 1)
				reloadFill.BackgroundColor3 = if ready then READY_COLOR else Color3.fromRGB(150, 140, 170)
				reloadText.Text = if ready then "READY!" else "RELOADING..."
			end
			local _, humanoid, root = api:Character()
			local showAim = aim ~= nil and (not api:IsTouch() or aimingTouch ~= nil)
			for _, piece in reticle:GetDescendants() do
				if piece:IsA("BasePart") then
					piece.LocalTransparencyModifier = if showAim then 0 else 1
				end
			end
			if aim and root then
				local flat = Vector3.new(aim.X, root.Position.Y, aim.Z)
				if (flat - root.Position).Magnitude > 1 then
					if humanoid then
						humanoid.AutoRotate = false
					end
					root.CFrame = CFrame.lookAt(root.Position, flat)
				end
			end
			if aim and showAim then
				local spin = clock * (if ready then 1.2 else 4)
				local color = if ready then READY_COLOR else Color3.fromRGB(170, 160, 190)
				reticleRing.Color = color
				reticleRing.CFrame = CFrame.new(aim + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
				local hole = reticle:FindFirstChild("Hole") :: BasePart?
				if hole then
					hole.CFrame = reticleRing.CFrame + Vector3.new(0, 0.01, 0)
				end
				for _, tick in reticle:GetChildren() do
					if tick.Name == "Tick" and tick:IsA("BasePart") then
						local angle = math.rad(tick:GetAttribute("Angle") :: number) + spin
						local out = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (hitRadius + 0.6)
						tick.Color = color
						tick.CFrame = CFrame.lookAt(aim + out + Vector3.new(0, 0.14, 0), aim + Vector3.new(0, 0.14, 0))
							* CFrame.Angles(0, math.rad(90), 0)
					end
				end
				-- The path: beads from the bow to the spot, stopping at the first board in the way.
				local base = if root then root.Position else tower
				local dir = Vector3.new(aim.X - base.X, 0, aim.Z - base.Z)
				dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(0, 0, 1)
				local from = base + Vector3.new(0, 1.2, 0) + dir * 1.6
				local total, arc = flight((aim - from).Magnitude)
				local block = firstBlock(from, aim, arc, now, total)
				for index, bead in beads do
					local s = index / (BEADS + 1)
					bead.CFrame = CFrame.new(pointAt(from, aim, arc, s))
					local hidden = block ~= nil and s > block
					bead.Transparency = if hidden then 1 else (if ready then 0.25 else 0.6)
					bead.Color = if block and index == math.floor(block * (BEADS + 1)) then RING_COLOR else color
				end
			else
				for _, bead in beads do
					bead.Transparency = 1
				end
			end
		end
	end)
end

return ArrowAmbush

-- Client half of Arrow Ambush: rolls the target boards along their rails from the shared
-- schedule (MG_Layout), flies every arrow the server planned (event "Arrow") with a landing ring
-- that shows where it comes down, sticks arrows in the ground or in a board, and puts a bow in
-- every archer's hands (bots too, through api:Participants()).
--
-- ARCHERS get a fixed view high over the tower, a reticle where the mouse points (or where the
-- finger is), the arrow's path as a line of beads that stops at any board in the way, and a
-- reload bar at the bottom of the screen. Click, or tap and release, to shoot: the shot is felt at
-- once (sound, kick, reload) without waiting for the server, and a tap a moment early is queued.
-- Their move controls are put away (they can't walk), so the whole screen is free to tap.
-- RUNNERS play normally, watch for the rings and hear arrows coming down near them. Anyone not in
-- the round just watches.

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
	return 0.28 + distance / 105, 1.5 + distance * 0.04 -- the server's ArrowAmbush.Flight
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
	local railTop: number = layout.RailTop or 0
	local boardHeight: number = layout.BoardHeight or 8
	local samples: number = layout.Samples or 48
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
	local watching = role ~= "Archer" and role ~= "Runner" -- not in this round (lobby, or joined late)
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
		badge.Size = UDim2.new(3.2, 40, 1.8, 22) -- studs plus a pixel floor, readable from the tower
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
		local frame = CFrame.new(boardX(board.Data, t), floorY + railTop, origin.Z + board.Data.Z)
		local since = t - board.WobbleAt
		if since >= 0 and since < 0.8 then
			frame *= CFrame.Angles(math.sin(since * 30) * 0.12 * (1 - since / 0.8), 0, 0)
		end
		return frame
	end

	-- The first board a path crosses (same check as the server's), as a fraction of the path.
	local function firstBlock(from: Vector3, to: Vector3, arc: number, t0: number, total: number): number?
		local previous = from
		for step = 1, samples do
			local s = step / samples
			local point = pointAt(from, to, arc, s)
			for _, board in boards do
				local planeZ = origin.Z + board.Data.Z
				local a, b = previous.Z - planeZ, point.Z - planeZ
				if a == b or (a > 0 and b > 0) or (a < 0 and b < 0) then
					continue
				end
				local f = a / (a - b)
				local hit = previous:Lerp(point, f)
				local frac = (step - 1 + f) / samples
				local x = boardX(board.Data, t0 + total * frac)
				local height = hit.Y - floorY
				if math.abs(hit.X - x) <= boardHalf and height <= boardHeight and height > -0.5 then
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
	local bowsCheckedAt = os.clock()
	local halfPing = 0 -- how long a shot takes to reach the server (checked every 2 s)
	local function hideModel(model: Instance?, hidden: boolean)
		if not model then
			return
		end
		for _, piece in model:GetDescendants() do
			if piece:IsA("BasePart") then
				piece.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end

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
	-- Ground markings are drawn on a SurfaceGui over one invisible part (a single flat layer,
	-- so nothing flickers against the flagstones, rails or boards).
	local function marking(size: number, parent: Instance): (Part, Frame)
		local holder = part({
			Name = "Marking",
			Size = Vector3.new(size, 0.05, size),
			Transparency = 1,
			Parent = parent,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = holder
		local canvas = UIKit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
		return holder, canvas
	end
	local function circle(parent: Instance, scale: number, color: Color3, transparency: number, stroke: number?): Frame
		local frame = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(scale, scale),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			Parent = parent,
			Children = { UIKit.Round() },
		})
		if stroke then
			UIKit.new("UIStroke", { Color = color, Thickness = stroke, Parent = frame })
		end
		return frame
	end

	local RING_SIZE = hitRadius * 2 + 1.4
	local function addRing(position: Vector3, id: number)
		local holder, canvas = marking(RING_SIZE, api.World)
		holder.Name = "LandingRing"
		-- Each ring a hair higher than the last few, so overlapping rings never flicker.
		holder.CFrame = CFrame.new(position + Vector3.new(0, 0.3 + (id % 6) * 0.012, 0))
		local inside = hitRadius * 2 / RING_SIZE
		circle(canvas, inside, RING_COLOR, 0.7, 7)
		local fill = circle(canvas, 0.1, RING_COLOR, 0.25)
		-- A cross through the ring, so the warning is a shape and not only a color.
		local cross = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = canvas,
		})
		for k = 0, 1 do
			UIKit.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.98, 0.07),
				Rotation = 45 + 90 * k,
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 0.1,
				Parent = cross,
				Children = { UIKit.Round(), UIKit.Stroke(RING_COLOR, 3, 0) },
			})
		end
		return { Model = holder, Fill = fill, Cross = cross, Inside = inside }
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
			Ring = if data.Board == 0 then addRing(to, tonumber(data.Id) or 0) else nil,
			Done = false,
			Board = if data.Board > 0 then boards[data.Board] else nil,
		}
		arrows[data.Id] = entry
		if data.By == me.UserId then
			-- Our own shot already kicked and clicked when we fired; only catch up if it didn't.
			if os.clock() - (lastShot[data.By] or -10) > 0.5 then
				lastShot[data.By] = os.clock()
				api:Sound("Click")
			end
		else
			lastShot[data.By] = os.clock()
			-- Runners hear an arrow that will come down near them.
			local _, _, root = api:Character()
			if not isArcher and not watching and root and data.Board == 0 then
				local near = Vector3.new(root.Position.X - to.X, 0, root.Position.Z - to.Z).Magnitude
				if near <= 10 then
					api:Sound("HazardWarning")
				end
			end
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
	-- Archers have no move stick or jump button, so their role chip and reload bar sit at the bottom
	-- of the screen, leaving the top (the far end of the courtyard) clear to aim at.
	local bottom = nil
	if isArcher then
		bottom = UIKit.new("Frame", {
			Name = "ArcherBar",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -16),
			Size = UDim2.fromOffset(380, 86),
			BackgroundTransparency = 1,
			Parent = api.Gui,
		})
		UIKit.AutoScale(bottom)
	end
	local chipColor = if isArcher then ARCHER_COLOR elseif watching then Color3.fromRGB(150, 140, 175) else RUNNER_COLOR
	local chip = UIKit.Panel(
		{
			Name = "Role",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = if bottom then UDim2.new(0.5, 0, 0, 0) else UDim2.new(0.5, 0, 0, y),
			Size = if watching then UDim2.fromOffset(220, 44) else UDim2.fromOffset(380, 48),
			Parent = bottom or hud,
		},
		chipColor,
		if isArcher
			then Color3.fromRGB(200, 70, 40)
			elseif watching then Color3.fromRGB(90, 80, 120)
			else Color3.fromRGB(40, 120, 220)
	)
	UIKit.Label({
		Text = if isArcher
			then (if api:IsTouch() then "🏹 ARCHER • TAP TO SHOOT" else "🏹 ARCHER • CLICK TO SHOOT")
			elseif watching then "👀 WATCHING"
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
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.fromOffset(260, 30),
			BackgroundColor3 = Color3.fromRGB(30, 22, 50),
			BackgroundTransparency = 0.25,
			Parent = bottom,
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

	-- The role intro: big for a few seconds, then it gets out of the way. (Low enough to clear the
	-- standings list on small phones.)
	local introY = y + 96
	local intro = UIKit.Label({
		Name = "Intro",
		Text = if isArcher then "🏹 YOU'RE AN ARCHER!" else "🏃 YOU'RE A RUNNER!",
		Font = Theme.Fonts.Display,
		TextSize = 52,
		TextColor3 = if isArcher then ARCHER_COLOR else RUNNER_COLOR,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, introY),
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
		Position = UDim2.new(0.5, 0, 0, introY + 60),
		Size = UDim2.fromOffset(600, 40),
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})
	if watching then
		intro.Visible = false -- spectators get no role intro
		introSub.Visible = false
	else
		UIKit.PopIn(intro, 0.45)
	end
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
			intro.Visible = true
			local stroke = intro:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 0 -- (the intro fade may have hidden it)
			end
			introSub.Text = ""
			api:Hint("") -- the "You're out" panel takes over
			UIKit.PopIn(intro, 0.3)
			task.delay(2.5, function()
				if intro.Parent then
					UIKit.Tween(intro, 0.5, { TextTransparency = 1 })
					if stroke then
						UIKit.Tween(stroke, 0.5, { Transparency = 1 })
					end
				end
			end)
		end
	end)

	-- Archer controls ----------------------------------------------------------------------------
	local aim: Vector3? = nil
	local aimingTouch: InputObject? = nil
	local reticle: Part?, beads, reticleRing: Frame?, reticleSpin: Frame?
	local predictedNext = 0 -- when our next arrow is ready, as we predicted it on firing
	local queuedUntil = 0 -- a tap a moment early is fired as soon as the bow is ready
	local flashAt = -10 -- when the reload bar last flashed "not ready"
	local cameraBase: CFrame? = nil
	local spotData = layout.Spots and layout.Spots[tostring(me.UserId)]
	local bowBase = if type(spotData) == "table" then v3(spotData) else nil
	local function readyAt(): number
		return math.max(api:Mine("NextShot") or 0, predictedNext)
	end
	if isArcher then
		local camera = workspace.CurrentCamera
		local savedType, savedFov = camera.CameraType, camera.FieldOfView
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 56
		-- High over the front of the tower (above the parapet), looking well out over the courtyard,
		-- so the far end sits under the round banner and the near wall at the bottom of the screen.
		local eye = tower + Vector3.new(0, 28, 4)
		local focus = Vector3.new(origin.X, floorY, origin.Z + 11)
		cameraBase = CFrame.lookAt(eye, focus)
		camera.CFrame = cameraBase :: CFrame
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

		local reticlePart, reticleCanvas = marking(RING_SIZE + 1, api.World)
		reticlePart.Name = "Reticle"
		reticle = reticlePart
		reticleRing = circle(reticleCanvas, hitRadius * 2 / (RING_SIZE + 1), READY_COLOR, 0.8, 6)
		reticleSpin = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = reticleCanvas,
		})
		for k = 0, 3 do
			local angle = math.rad(k * 90)
			UIKit.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.44, 0.5 + math.sin(angle) * 0.44),
				Size = UDim2.fromScale(0.16, 0.05),
				Rotation = k * 90,
				BackgroundColor3 = Color3.new(1, 1, 1),
				Parent = reticleSpin,
				Children = { UIKit.Round() },
			})
		end
		reticlePart.Parent = nil
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
		local function release(at: Vector3)
			api:Action("Shoot", at.X, at.Z)
			-- Felt at once, without waiting for the server: the click, the bow's kick, the reload.
			lastShot[me.UserId] = os.clock()
			predictedNext = api:Now() + cooldown
			api:Sound("Click")
		end
		local function shoot(at: Vector3?)
			if not at or not api:Alive() then
				return
			end
			local wait = readyAt() - api:Now()
			if wait <= 0.05 then
				release(at)
			elseif wait < 0.35 then
				-- Just early: fire the moment the bow is ready.
				local queuedAt = at
				queuedUntil = api:Now() + wait
				task.delay(wait, function()
					queuedUntil = 0
					if api:Alive() and readyAt() - api:Now() <= 0.06 then
						release(queuedAt)
					end
				end)
			else
				flashAt = os.clock() -- too early: the reload bar flashes
				api:Sound("Countdown")
			end
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
		-- (No hint line for archers: the chip at the bottom already says TAP / CLICK TO SHOOT.)
	elseif not watching then
		api:Hint("Watch for the red rings! Hide behind the boards!", introY + 104)
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
					local size = entry.Ring.Inside * (0.1 + 0.9 * progress)
					entry.Ring.Fill.Size = UDim2.fromScale(size, size)
					entry.Ring.Cross.Rotation = progress * 90
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

		-- Bows: held in front of each archer, kicking back when they shoot. (Every 2 s the list is
		-- checked again, so an archer who leaves takes their bow with them.)
		if clock - bowsCheckedAt > 2 then
			bowsCheckedAt = clock
			refreshBows()
			local ok, ping = pcall(function()
				return me:GetNetworkPing()
			end)
			halfPing = if ok and type(ping) == "number" then math.clamp(ping / 2, 0, 0.3) else 0
		end
		for userId, entry in bows do
			local character = entry.Who:Character()
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root or not entry.Model then
				if not entry.Hidden then
					entry.Hidden = true -- their character is gone: don't leave the bow in mid-air
					hideModel(entry.Model, true)
					hideModel(entry.Nocked, true)
				end
				continue
			end
			if entry.Hidden then
				entry.Hidden = false
				hideModel(entry.Model, false)
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
			local nextShot = readyAt()
			local ready = now >= nextShot - 0.05
			local fraction = if ready then 1 else math.clamp(1 - (nextShot - now) / cooldown, 0, 1)
			if reloadFill and reloadText and reload then
				local flash = clock - flashAt < 0.3
				reloadFill.Size = UDim2.fromScale(fraction, 1)
				reloadFill.BackgroundColor3 = if ready
					then READY_COLOR
					elseif flash then RING_COLOR
					else Color3.fromRGB(150, 140, 170)
				reloadText.Text = if ready
					then "READY!"
					elseif now < queuedUntil then "NEXT ARROW..."
					else "RELOADING..."
				reload.Rotation = if flash then math.sin((clock - flashAt) * 60) * 3 else 0
			end
			-- A little recoil on the camera when we shoot.
			local since = clock - (lastShot[me.UserId] or -10)
			if cameraBase then
				local kick = if since < 0.18 then math.sin(since / 0.18 * math.pi) * 0.006 else 0
				workspace.CurrentCamera.CFrame = (cameraBase :: CFrame) * CFrame.Angles(kick, 0, 0)
			end
			local _, humanoid, root = api:Character()
			local showAim = aim ~= nil and (not api:IsTouch() or aimingTouch ~= nil)
			reticle.Parent = if showAim then api.World else nil
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
				reticleRing.BackgroundColor3 = color
				local stroke = reticleRing:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = color
				end
				reticle.CFrame = CFrame.new(aim + Vector3.new(0, 0.3, 0))
				if reticleSpin then
					reticleSpin.Rotation = math.deg(spin)
					for _, tick in reticleSpin:GetChildren() do
						if tick:IsA("Frame") then
							tick.BackgroundColor3 = color
						end
					end
				end
				-- The path: beads from the bow to the spot, stopping at the first board in the way.
				-- (From our spot on the tower, exactly as the server plans it.)
				local base = bowBase or (if root then root.Position else tower)
				local dir = Vector3.new(aim.X - base.X, 0, aim.Z - base.Z)
				dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(0, 0, 1)
				local from = base + Vector3.new(0, 1.2, 0) + dir * 1.6
				local total, arc = flight((aim - from).Magnitude)
				-- The server plans the shot when it gets it, about half a ping from now.
				local block = firstBlock(from, aim, arc, now + halfPing, total)
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

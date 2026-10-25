-- Client half of Sky Stack: every tower in the row and the block sliding over each one, the slices
-- tumbling off, the golden stars at the cloud line, a camera that rises with your tower, the HUD
-- (floors, your perfect streak, your place) and the DROP controls.
--
-- The server owns the towers: each one comes in "T<userId>" (every block, the slide, the last drop
-- and what fell; Shared/Logic/SkyStack has the rules), and every sliding block here moves on the
-- same schedule from the server's clock (Stack.Offset at api:Now()), so the block a player sees is
-- where the server judges it. DROP sends the moment it was pressed (api:Action "Drop", api:Now()),
-- and this side shows its own drop straight away with the same rules (Stack.Drop) instead of
-- waiting a round trip: the slice falls, the next block appears. When the server's tower comes back
-- it's the one drawn (it agrees, unless the press was clamped or never counted); a prediction the
-- server never answers is dropped after a moment.
--
-- Controls: tap DROP (phones), click or press E (PC). On phones a tap on the open screen counts too,
-- except the bottom-left corner where the thumbstick lives.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Stack = require(ReplicatedStorage.Shared.Logic.SkyStack)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SkyStack = {}

local GOLD = Color3.fromRGB(255, 212, 70)
local GRAVITY = 70 -- studs/s² for falling slices
local PREDICT_TIMEOUT = 3 -- a drop the server hasn't answered by then is forgotten (it answers refusals)
local OUT_CAMERA = 2 -- seconds after crumbling before the camera goes back to normal

type Box = Stack.Block

type Falling = {
	Part: BasePart,
	Velocity: Vector3,
	Spin: Vector3,
	Angles: Vector3,
	Born: number,
}

type View = {
	User: number,
	Lane: number,
	Name: string,
	Color: Color3,
	X: number,
	Parts: { BasePart }, -- one per floor
	Boxes: { Box },
	Moving: BasePart,
	MovingLevel: number,
	Slide: Stack.Slide?,
	Top: Box,
	Streak: number,
	Drops: number, -- drops seen (their slices have fallen)
	GustFrom: number?,
	Place: number?,
	FinishedIn: number?,
	Out: boolean,
	Gone: boolean,
	Star: Model?,
	StarParts: { BasePart },
	StarOffsets: { CFrame },
	StarBase: CFrame?,
	StarPopped: boolean,
	Tag: BillboardGui?,
	TagLabel: TextLabel?,
	Anchor: BasePart,
}

local function vec(list: any): Vector3
	return Vector3.new(list[1], list[2], list[3])
end

local function toBox(list: any): Box?
	if type(list) ~= "table" or type(list[1]) ~= "number" then
		return nil
	end
	return { X0 = list[1], X1 = list[2], Z0 = list[3], Z1 = list[4] }
end

local function sameBox(a: Box, b: Box): boolean
	return math.abs(a.X0 - b.X0) < 0.02
		and math.abs(a.X1 - b.X1) < 0.02
		and math.abs(a.Z0 - b.Z0) < 0.02
		and math.abs(a.Z1 - b.Z1) < 0.02
end

local function toSlide(data: any): Stack.Slide?
	if type(data) ~= "table" or type(data.T) ~= "number" or type(data.V) ~= "number" then
		return nil
	end
	return {
		Level = tonumber(data.L) or 1,
		Axis = if data.A == "Z" then "Z" else "X",
		Dir = if data.D == -1 then -1 else 1,
		Start = data.T,
		Speed = data.V,
		Gust = data.G == true,
	}
end

-- One of the shared sound effects at a pitch and volume of our own (falls back to the plain effect
-- without the uploaded effects sprite).
local function playSound(api, name: string, speed: number, volume: number)
	local sprite = Sounds.Sprite
	local region = sprite and sprite.Regions[name]
	if not sprite or not region then
		api:Sound(name)
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = sprite.Id
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(region.Start, region.Start + region.Length)
	sound.PlaybackSpeed = speed
	sound.Volume = volume
	sound.Parent = SoundService
	api:Track(sound)
	sound:Play()
	task.delay(region.Length / speed + 0.3, function()
		sound:Destroy()
	end)
end

local function ordinal(place: number): string
	local suffix = "th"
	if place % 100 < 11 or place % 100 > 13 then
		suffix = ({ "st", "nd", "rd" })[place % 10] or "th"
	end
	return `{place}{suffix}`
end

-- A floor's color: the lane's, its hue drifting a little floor by floor and every other floor a
-- shade lighter, so the layers read apart.
local function floorColor(color: Color3, level: number): Color3
	local h, s, v = color:ToHSV()
	h = (h + level * 0.011) % 1
	if level % 2 == 0 then
		s *= 0.82
		v = math.min(1, v * 1.08)
	end
	return Color3.fromHSV(h, s, v)
end

function SkyStack.Start(api)
	api:Mood({ Tint = Color3.fromRGB(246, 250, 255), Saturation = 0.16, Contrast = 0.05 })
	local layout = api:SharedJSON("Layout")
	local waited = 0
	while not layout and waited < 10 do
		waited += task.wait(0.1)
		layout = api:SharedJSON("Layout")
	end
	local arena = api:Arena(10)
	if not layout or not arena then
		return
	end
	local towerFolder = arena:WaitForChild("Towers", 10)
	local me = api.Player
	local origin = vec(layout.Origin)
	local baseTop = tonumber(layout.BaseTop) or origin.Y + 3
	local goal = tonumber(layout.Goal) or Stack.GOAL
	local effects = not State.ReducedEffects()
	local touch = api:IsTouch()

	local function floorY(level: number): number
		return baseTop + (level - 0.5) * Stack.BLOCK
	end
	local function boxFrame(view: View, box: Box, level: number): CFrame
		return CFrame.new(view.X + (box.X0 + box.X1) / 2, floorY(level), origin.Z + (box.Z0 + box.Z1) / 2)
	end
	local function boxSize(box: Box): Vector3
		return Vector3.new(math.max(box.X1 - box.X0, 0.05), Stack.BLOCK, math.max(box.Z1 - box.Z0, 0.05))
	end
	local function newBlock(view: View, box: Box, level: number, name: string): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = view.User == me.UserId
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Color = floorColor(view.Color, level)
		part.Size = boxSize(box)
		part.CFrame = boxFrame(view, box, level)
		part.Parent = api.World
		return part
	end

	-- The towers --------------------------------------------------------------------------------------
	local views = {} :: { View }
	local byUser = {} :: { [number]: View }
	local mine: View? = nil
	for _, lane in layout.Lanes do
		local color = Color3.fromRGB(lane.Color[1], lane.Color[2], lane.Color[3])
		local anchor = Instance.new("Part")
		anchor.Name = "TagAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		anchor.CFrame = CFrame.new(lane.X, baseTop + 3, origin.Z)
		anchor.Parent = api.World
		local view: View = {
			User = lane.User,
			Lane = lane.Lane,
			Name = tostring(lane.Name),
			Color = color,
			X = lane.X,
			Parts = {},
			Boxes = {},
			Moving = nil :: any,
			MovingLevel = 0,
			Slide = nil,
			Top = Stack.Base(),
			Streak = 0,
			Drops = 0,
			GustFrom = nil,
			Place = nil,
			FinishedIn = nil,
			Out = false,
			Gone = false,
			Star = nil,
			StarParts = {},
			StarOffsets = {},
			StarBase = nil,
			StarPopped = false,
			Tag = nil,
			TagLabel = nil,
			Anchor = anchor,
		}
		local moving = newBlock(view, Stack.Base(), 1, "Moving")
		moving.CastShadow = false
		moving.Transparency = 1
		view.Moving = moving
		-- The star at the cloud line (the server's model, spun here; it may arrive a moment later).
		local function takeStar(star: Model)
			local pivot = star:GetPivot()
			for _, part in star:GetDescendants() do
				if part:IsA("BasePart") then
					table.insert(view.StarParts, part)
					table.insert(view.StarOffsets, pivot:ToObjectSpace(part.CFrame))
				end
			end
			view.Star = star
			view.StarBase = pivot
		end
		local starName = "Star_" .. tostring(lane.User)
		local star = towerFolder and towerFolder:FindFirstChild(starName) :: Model?
		if star then
			takeStar(star)
		elseif towerFolder then
			task.spawn(function()
				local late = towerFolder:WaitForChild(starName, 8) :: Model?
				if late and late.Parent and not view.StarBase then
					takeStar(late)
				end
			end)
		end
		table.insert(views, view)
		byUser[view.User] = view
		if view.User == me.UserId then
			mine = view
		end
	end
	if #views == 0 then
		return
	end

	-- Name tags over the towers: the lane number and name (yours says YOU, in gold).
	for _, view in views do
		local gui = Instance.new("BillboardGui")
		gui.Name = "TowerTag"
		gui.Adornee = view.Anchor
		gui.Size = UDim2.fromOffset(170, 32)
		gui.MaxDistance = 160
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.Parent = api.World
		local isMine = view == mine
		view.TagLabel = UIKit.Label({
			Text = if isMine then `{view.Lane} · YOU` else `{view.Lane} · {view.Name}`,
			Font = Theme.Fonts.Display,
			TextSize = if isMine then 24 else 18,
			TextColor3 = if isMine then GOLD else Color3.new(1, 1, 1),
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0.1) },
		})
		view.Tag = gui
	end

	-- Falling slices --------------------------------------------------------------------------------
	local falling = {} :: { Falling }
	local function drop(view: View, box: Box, level: number, offset: number, axis: string)
		local part = newBlock(view, box, level, "Slice")
		part.CastShadow = false
		local away = if offset >= 0 then 1 else -1
		local push = if axis == "X" then Vector3.new(away * 5, 0, 0) else Vector3.new(0, 0, away * 5)
		local tumble = if axis == "X" then Vector3.new(0, 0, -away * 3) else Vector3.new(away * 3, 0, 0)
		table.insert(falling, {
			Part = part,
			Velocity = push + Vector3.new(0, 4, 0),
			Spin = tumble + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5),
			Angles = Vector3.zero,
			Born = os.clock(),
		})
	end

	-- HUD ---------------------------------------------------------------------------------------------
	local hud = api:TopHud()
	local y = api:HudY()
	local panelHeight = if touch then 102 else 80
	local panel = UIKit.new("Frame", {
		Name = "StackPanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(if touch then 350 else 300, panelHeight),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.2,
		Visible = mine ~= nil,
		Parent = hud,
		Children = { UIKit.Corner(16), UIKit.Stroke(Color3.new(1, 1, 1), 2, 0.2) },
	})
	local bigText = UIKit.Label({
		Name = "Floors",
		Text = `🧱 0 / {goal}`,
		Font = Theme.Fonts.Display,
		TextSize = if touch then 38 else 34,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, if touch then 44 else 38),
		Parent = panel,
		Children = { UIKit.TextStroke(0.2) },
	})
	local track = UIKit.new("Frame", {
		Name = "Height",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -28, 0, if touch then 32 else 20),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		Parent = panel,
		Children = { UIKit.Round() },
	})
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = if mine then mine.Color else Theme.Colors.Yellow,
		Parent = track,
		Children = { UIKit.Round() },
	})
	local barText = UIKit.Label({
		Name = "Detail",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 27 else 16,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = track,
		Children = { UIKit.TextStroke(0.15) },
	})
	local panelBottom = y + panelHeight
	local shout = UIKit.Label({
		Name = "Shout",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 50 else 56,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, panelBottom + (if touch then 48 else 70)),
		Size = UDim2.fromOffset(560, 64),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0) },
	})
	local shoutUntil = 0
	local function yell(text: string, color: Color3?, seconds: number?)
		shout.Text = text
		shout.TextColor3 = color or Color3.new(1, 1, 1)
		shout.Size =
			UDim2.fromOffset(math.min(600, UIKit.TextWidth(text, shout.TextSize, Theme.Fonts.Display) + 24), 64)
		shout.Visible = true
		shoutUntil = os.clock() + (seconds or 1)
		UIKit.PopIn(shout, 0.25)
	end

	-- Shared state ----------------------------------------------------------------------------------
	-- My own drops, shown before the server's answer: the tower as it'll be, the next slide, the
	-- streak, how many drops it makes, what the last one was, and when it was made.
	local predicted: {
		Boxes: { Box },
		Slide: Stack.Slide?,
		Top: Box,
		Streak: number,
		Drops: number,
		Kind: string,
		At: number,
	}? =
		nil

	-- Puts a tower's blocks in place: one part per floor, rebuilt only where the floor changed.
	local function setBoxes(view: View, boxes: { Box })
		for level, box in boxes do
			local part = view.Parts[level]
			local old = view.Boxes[level]
			if not part then
				view.Parts[level] = newBlock(view, box, level, "Floor")
			elseif not old or not sameBox(old, box) then
				part.Size = boxSize(box)
				part.CFrame = boxFrame(view, box, level)
			end
			view.Boxes[level] = box
		end
		for level = #view.Parts, #boxes + 1, -1 do
			view.Parts[level]:Destroy()
			view.Parts[level] = nil
			view.Boxes[level] = nil
		end
		view.Top = boxes[#boxes] or Stack.Base()
		view.Anchor.CFrame = CFrame.new(view.X, baseTop + #boxes * Stack.BLOCK + 3.2, origin.Z)
	end

	local function refreshTag(view: View)
		local label = view.TagLabel
		if not label then
			return
		end
		local name = if view == mine then "YOU" else view.Name
		if view.Place then
			label.Text = `🏆 {ordinal(view.Place)} · {name}`
		elseif view.Out then
			label.Text = `💥 {name}`
		else
			label.Text = `{view.Lane} · {name}`
		end
		if view.Gone and view.Tag then
			view.Tag.Enabled = false
		end
	end

	local function popStar(view: View)
		if view.StarPopped or not view.StarBase then
			return
		end
		view.StarPopped = true
		local at = (view.StarBase :: CFrame).Position
		for _, part in view.StarParts do
			part.Transparency = 1
		end
		api:Effect("Confetti", at, { view.Color, GOLD, Color3.new(1, 1, 1) })
		if effects then
			api:Effect("Stars", at)
		end
	end

	-- `quiet`: the first look at a tower (drops made before this side started show no slices).
	local function readTower(view: View, quiet: boolean?)
		local data = api:SharedJSON(`T{view.User}`)
		if type(data) ~= "table" then
			return
		end
		local boxes = {}
		if type(data.B) == "table" then
			for _, list in data.B do
				local box = toBox(list)
				if box then
					table.insert(boxes, box)
				end
			end
		end
		local drops = tonumber(data.N) or 0
		local last = data.K
		if quiet then
			view.Drops = drops
		end
		-- My drop that this side showed differently (the server clamped the press): its slice falls now.
		if view == mine and predicted and drops == (predicted :: any).Drops and type(last) == "table" then
			if last.K ~= (predicted :: any).Kind then
				view.Drops = drops - 1
			end
		end
		-- A drop this side hasn't shown yet: its slice falls now.
		if drops > view.Drops then
			if type(last) == "table" then
				local cut = toBox(last.F)
				if cut then
					local level = if last.K == "Miss" then #boxes + 1 else #boxes
					drop(view, cut, level, tonumber(last.O) or 0, if last.A == "Z" then "Z" else "X")
				end
				if view ~= mine and effects and last.C == true then
					api:Effect("Sparkles", Vector3.new(view.X, floorY(#boxes) + 1, origin.Z), { view.Color, GOLD })
				end
			end
		end
		local wasOut, wasPlace = view.Out, view.Place
		view.Slide = toSlide(data.S)
		view.Streak = tonumber(data.Q) or 0
		view.GustFrom = tonumber(data.W)
		view.Place = tonumber(data.P)
		view.FinishedIn = tonumber(data.In)
		view.Out = data.X == true
		view.Gone = data.Gone == true
		if view == mine and predicted then
			local p = predicted :: any
			-- The server has caught up with (or gone past) what this side showed: draw its tower.
			if drops >= p.Drops then
				predicted = nil
			end
		end
		if view ~= mine or not predicted then
			view.Drops = drops
			setBoxes(view, boxes)
		end
		if view.Place and not wasPlace then
			popStar(view)
			if view == mine then
				yell(`🏆 {ordinal(view.Place :: number)}!`, GOLD, 3)
				api:Sound("Victory")
			end
		end
		if view.Out and not wasOut and view == mine then
			yell("💥 CRUMBLED!", Theme.Colors.Red, 2.5)
		end
		refreshTag(view)
	end
	for _, view in views do
		readTower(view, true)
		api:OnShared(`T{view.User}`, function()
			readTower(view)
		end)
	end

	-- A gust from a neighbor's combo: a puff of wind at your tower and a warning (only if it reached
	-- you: a tower with a gust already on its way doesn't get a second).
	api:OnEvent("Gust", function(from, hit)
		local source = byUser[tonumber(from) or 0]
		if not source then
			return
		end
		if effects then
			api:Effect("Sparkles", Vector3.new(source.X, floorY(#source.Boxes) + 1.5, origin.Z), { source.Color, GOLD })
		end
		local reached = type(hit) == "table" and mine ~= nil and table.find(hit, mine.User) ~= nil
		if mine and reached and not mine.Out and not mine.Place then
			yell(`💨 GUST from {source.Name}!`, Color3.fromRGB(170, 220, 255), 1.6)
			playSound(api, "Boing", 0.6, 0.6)
			if effects then
				api:Effect("Poof", Vector3.new(mine.X, floorY(#mine.Boxes + 1), origin.Z), { Color3.new(1, 1, 1) })
			end
		end
	end)

	-- Controls ----------------------------------------------------------------------------------------
	local dropButton = api:Button({ Text = "DROP", Key = Enum.KeyCode.E, Color = if mine then mine.Color else nil })
	dropButton:SetEnabled(false) -- it wakes up when the first block sets off

	local function myState(): (Box, Stack.Slide?, number, number)
		local view = mine :: View
		if predicted then
			local p = predicted :: any
			return p.Top, p.Slide, p.Streak, p.Drops
		end
		return view.Top, view.Slide, view.Streak, view.Drops
	end

	-- The server's clock as of the frame on screen: a tap answers what the player saw, and input is
	-- handled before the next frame is drawn, so api:Now() at the tap would be a frame late (on a
	-- fast block at 30 fps, a drop that looked perfect would be judged a slice off).
	local drawnAt: number? = nil
	local function press()
		local view = mine
		if not view or view.Out or view.Place or not api:CanAct() then
			return
		end
		local top, slide, streak, drops = myState()
		local clock = api:Now()
		local now = if drawnAt and math.abs(clock - drawnAt) < 0.1 then drawnAt :: number else clock
		local endsAt = GameState.Get("PhaseEndsAt") or 0
		if GameState.Get("Phase") ~= "InRound" or (endsAt > 0 and now > endsAt) then
			return -- time's up: nothing new counts
		end
		if not slide or not Stack.Counts(slide, now) then
			return -- nothing to drop yet, or a double tap
		end
		api:Action("Drop", now, slide.Level)
		local result = Stack.Drop(top, slide, now, streak)
		local boxes = table.clone(if predicted then (predicted :: any).Boxes else view.Boxes)
		local nextSlide: Stack.Slide? = nil
		local level = #boxes
		if result.Block then
			table.insert(boxes, result.Block :: Box)
			level = #boxes
			if level < goal then
				nextSlide = Stack.NewSlide(level + 1, now + Stack.SPAWN, view.GustFrom ~= nil)
			end
		end
		predicted = {
			Boxes = boxes,
			Slide = nextSlide,
			Top = result.Block or top,
			Streak = result.Streak,
			Drops = drops + 1,
			Kind = result.Kind,
			At = os.clock(),
		}
		view.Drops = drops + 1 -- its slice falls now, not when the server's answer comes
		setBoxes(view, boxes)
		if result.Falling then
			drop(
				view,
				result.Falling :: Box,
				if result.Kind == "Miss" then level + 1 else level,
				result.Offset,
				slide.Axis
			)
		end
		if result.Kind == "Perfect" then
			-- A rising note for every perfect drop in a row.
			playSound(api, "Pickup", 0.9 + math.min(result.Streak, 10) * 0.08, 0.6)
			if result.Combo then
				yell("✨ COMBO! 💨 GUST!", GOLD, 1.4)
				playSound(api, "Boing", 1.2, 0.6)
				if effects then
					api:Effect("Sparkles", Vector3.new(view.X, floorY(level) + 1, origin.Z), { view.Color, GOLD })
				end
			else
				yell(if result.Streak >= 2 then `PERFECT x{result.Streak}` else "PERFECT!", GOLD, 0.8)
			end
		elseif result.Kind == "Cut" then
			playSound(api, "Hit", 1.1, 0.45)
		else
			playSound(api, "Hit", 0.6, 0.8)
		end
	end
	dropButton.Pressed:Connect(press)
	-- The server didn't count my last press (a double tap, the buzzer): back to its tower at once.
	api:OnEvent("Refused", function()
		if predicted and mine then
			predicted = nil
			readTower(mine)
		end
	end)
	-- Mouse clicks and taps on the open screen (not on buttons; not the thumbstick's corner).
	api:Track(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			press()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			local viewport = workspace.CurrentCamera.ViewportSize
			local at = input.Position
			if at.X > viewport.X * 0.35 or at.Y < viewport.Y * 0.5 then
				press()
			end
		end
	end))

	-- Camera (only for the players building a tower) -----------------------------------------------
	local camera = workspace.CurrentCamera
	local filming = State.InRound() and mine ~= nil
	local savedType, savedFov = camera.CameraType, camera.FieldOfView
	local released = false
	local function release()
		if filming and not released then
			released = true
			camera.CameraType = if savedType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedType
			camera.FieldOfView = savedFov
		end
	end
	if filming then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 50
		api:Track(release)
	end
	local camEye: Vector3? = nil
	local camLook: Vector3? = nil
	local outAt: number? = nil

	-- Every frame -------------------------------------------------------------------------------------
	local parts = {} :: { BasePart }
	local frames = {} :: { CFrame }
	local hinted = false
	local hintUntil = math.huge
	local wasActive = false
	api:RenderStep(function(dt)
		local now = api:Now()
		drawnAt = now
		local clock = os.clock()
		local stage = api:Shared("Stage")
		if shout.Visible and clock > shoutUntil then
			shout.Visible = false
		end
		if clock > hintUntil then
			hintUntil = math.huge
			api:Hint("")
		end
		if predicted and clock - (predicted :: any).At > PREDICT_TIMEOUT then
			predicted = nil -- the server never counted it: back to its tower
			if mine then
				readTower(mine)
			end
		end

		table.clear(parts)
		table.clear(frames)
		-- The sliding blocks.
		for _, view in views do
			local slide = view.Slide
			local top = view.Top
			if view == mine and predicted then
				slide = (predicted :: any).Slide
				top = (predicted :: any).Top
			end
			local active = slide ~= nil and stage ~= "Done" and not view.Out and not view.Place and not view.Gone
			if active then
				local s = slide :: Stack.Slide
				local box = Stack.Moving(top, s, Stack.Offset(s, now))
				local size = boxSize(box)
				if view.Moving.Size ~= size then
					view.Moving.Size = size
				end
				if view.Moving.Transparency ~= 0 then
					view.Moving.Transparency = 0
				end
				if view.MovingLevel ~= s.Level then
					view.MovingLevel = s.Level
					view.Moving.Color = floorColor(view.Color, s.Level)
				end
				table.insert(parts, view.Moving)
				table.insert(frames, boxFrame(view, box, s.Level))
			elseif view.Moving.Transparency < 1 then
				view.Moving.Transparency = 1
			end
			-- The star at the cloud line bobs and sways (its face stays toward the cameras).
			if view.StarBase and not view.StarPopped then
				local spin = CFrame.new(0, math.sin(clock * 2 + view.Lane) * 0.3, 0)
					* CFrame.Angles(
						0,
						math.sin(clock * 1.3 + view.Lane) * 0.35,
						math.sin(clock * 1.7 + view.Lane) * 0.12
					)
				local base = (view.StarBase :: CFrame) * spin
				for index, part in view.StarParts do
					table.insert(parts, part)
					table.insert(frames, base * view.StarOffsets[index])
				end
			end
		end
		-- Slices tumbling off.
		for index = #falling, 1, -1 do
			local piece = falling[index]
			local age = clock - piece.Born
			if age > 2.2 or not piece.Part.Parent then
				piece.Part:Destroy()
				table.remove(falling, index)
				continue
			end
			piece.Velocity += Vector3.new(0, -GRAVITY * dt, 0)
			piece.Angles += piece.Spin * dt
			local position = piece.Part.Position + piece.Velocity * dt
			if position.Y < origin.Y + 0.4 then
				position = Vector3.new(position.X, origin.Y + 0.4, position.Z)
				piece.Velocity = Vector3.zero
				piece.Spin = Vector3.zero
				piece.Part.Transparency = math.clamp((age - 1.2) / 1, 0, 1)
			end
			table.insert(parts, piece.Part)
			table.insert(frames, CFrame.new(position) * CFrame.Angles(piece.Angles.X, piece.Angles.Y, piece.Angles.Z))
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end

		-- The panel and the DROP button.
		local view = mine
		if view then
			local _, slide, streak = myState()
			local floors = if predicted then #(predicted :: any).Boxes else #view.Boxes
			local active = slide ~= nil and stage ~= "Done" and not view.Out and not view.Place
			if active ~= wasActive then
				wasActive = active
				dropButton:SetEnabled(active)
				if active and not hinted then
					hinted = true
					api:Hint(
						if touch then "Tap when the block lines up!" else "Click or press E when it lines up!",
						panelBottom + 8
					)
					hintUntil = clock + 5
				end
			end
			bigText.Text = `🧱 {floors} / {goal}`
			bar.Size = UDim2.fromScale(math.clamp(floors / goal, 0, 1), 1)
			if view.Place then
				barText.Text = string.format("🏆 %s · %.1fs", ordinal(view.Place), view.FinishedIn or 0)
			elseif view.Out then
				barText.Text = `💥 crumbled at {floors}`
			elseif view.GustFrom and not (slide and slide.Gust) then
				barText.Text = "💨 next block: FASTER"
			elseif slide and slide.Gust then
				barText.Text = "💨 GUST! It's faster!"
			elseif streak > 0 and streak % Stack.COMBO == 0 then
				barText.Text = `✨ COMBO! perfect x{streak}`
			elseif streak > 0 then
				barText.Text = `{string.rep("⭐", streak % Stack.COMBO)} perfect x{streak}`
			else
				-- Where you stand: towers taller than yours (or at the clouds) go ahead.
				local ahead = 0
				for _, other in views do
					if other ~= view and not other.Gone and (other.Place or #other.Boxes > floors) then
						ahead += 1
					end
				end
				barText.Text = `{ordinal(ahead + 1)} place`
			end
			if view.Out and not outAt then
				outAt = clock
			end
		end

		-- Camera: just off your tower's top corner, rising with it; at the clouds it circles the top.
		if filming and mine and not released then
			if outAt and clock - outAt > OUT_CAMERA then
				release()
				return
			end
			if camera.CameraType ~= Enum.CameraType.Scriptable then
				camera.CameraType = Enum.CameraType.Scriptable
			end
			local floors = if predicted then #(predicted :: any).Boxes else #mine.Boxes
			local topY = baseTop + floors * Stack.BLOCK
			local center = Vector3.new(mine.X, topY, origin.Z)
			local eye, look
			if mine.Place then
				local angle = clock * 0.35
				eye = center + Vector3.new(math.cos(angle) * 22, 9, math.sin(angle) * 22)
				look = center + Vector3.new(0, 1.5, 0)
			else
				local back = if touch then 15 else 16.5
				eye = center + Vector3.new(back, 10.5, back)
				look = center + Vector3.new(0, 1.2, 0)
			end
			local alpha = math.clamp(dt * 4, 0, 1)
			camEye = if camEye then camEye:Lerp(eye, alpha) else eye
			camLook = if camLook then camLook:Lerp(look, alpha) else look
			camera.CFrame = CFrame.lookAt(camEye :: Vector3, camLook :: Vector3)
		end
	end)
end

return SkyStack

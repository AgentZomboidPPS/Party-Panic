-- Client half of Messy Memory: every booth's curtains, toys and smoke, this player's fixed camera on
-- their own shelf, tapping toys back into place, peeking at rivals, and the reveal.
--
-- YOUR SHELF fills the screen (a fixed camera in front of your booth). Tap (or click) a toy to pick
-- it up (it floats and glows), then tap the spot it goes in: an empty cubby, a cubby with another
-- toy (they swap), or an empty spot on the counter (it goes back down). Your moves show at once
-- (they follow the same rule as the server, Logic/MessyMemory.Move); the server's positions are
-- adopted as soon as they include your latest move (the "S" move number), so a slow reply never
-- undoes a newer move. CLOSE (E) shuts your curtain: rivals can't see your shelf, and your answers
-- are locked until you OPEN it again. PEEK (Q) swings the camera to a rival's open booth for a few
-- seconds (press again for the next one, tap the screen to come back); the rival is told.
--
-- Everyone's booths are drawn from the server's shared state ("B<UserId>"; a shut booth sends no
-- positions, so its toys simply aren't drawn) and the round's "Phase": curtains open at GO, smoke
-- puffs burst and the toys tumble onto the counters at the mischief, and at the reveal each right
-- spot lights up in turn on every shelf (a ✓ or ✗ over each toy on yours, and a see-through copy of
-- a toy where it should have gone).
--
-- Phones (owner, from an iPhone: "Weird angle on mobile for this mini game."): they had the PC camera
-- moved right with a 60-degree view, so on a 2.17:1 screen the awning cut across the top shelf, a
-- curtain and posts filled one side, the next booth the other, and the shelf sat small and skewed in
-- between. Now a phone looks straight into the booth from Rules.PHONE_EYE (low enough that the awning
-- clears the shelf), with the pitch and the field of view worked out from the screen: the shelf's
-- crown just under the HUD's lines, the framing's foot just above the bottom edge. While you memorise
-- (the counter still empty) that's the shelf alone, centred and bigger; from the mischief on (and
-- when you peek) it's the shelf and the counter's toys, and if the right-hand toys would sit under
-- PEEK / CLOSE the eye slides right (under a stud on 2.17:1 phones, up to MAX_SHIFT on 16:9 and 4:3
-- screens) before the framing shrinks. Even so a wide screen holds more than one booth, so phones get
-- a wall between every two booths: the sides show your own booth's nook, never the next booths'
-- shelves (that's what PEEK is for). There the shout takes the hint's line, and the name boards (right
-- behind the HUD) are off. PC is as it was.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.MessyMemory)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local MessyMemory = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local SPIN = CFrame.Angles(0, math.pi, 0) -- toys face -Z; turned to face the player
local GOOD = rgb(80, 220, 110)
local BAD = rgb(240, 70, 70)
local CURTAIN_W = 6.6 -- one half's width, shut
local CURTAIN_OPEN = 0.2 -- an open half's width, as a share of shut
local CURTAIN_Y = 0.1
local CURTAIN_Z = 0.2
local PEEK_TIME = 3.5
local CURTAIN_COOLDOWN = 0.35 -- CLOSE/OPEN presses at least this far apart
local MOVE_TIME = 0.28
local PICK_RADIUS = 0.11 -- of the screen's height: a tap this close to a toy or spot picks it

-- Phones (see the header).
local HUD_BAND = 108 -- HUD units from the top of the phase panel to the bottom of the line under it
local TOUCH_HUD = 0.75 -- the TopHud's own scale on phones (Api's TOUCH_HUD_SCALE), before it's laid out
local DIVIDER_IN, DIVIDER_OUT = 19, 29 -- the walls between booths, from and to these radii
local DIVIDER_HEIGHT = 18

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
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
			descendant.CastShadow = false
		end
	end
end

local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

type Toy = {
	Model: Model?,
	Pos: number?, -- the position it's drawn heading to
	From: CFrame,
	To: CFrame,
	T0: number,
	Dur: number,
	Hop: number,
	Spin: number,
	Now: CFrame,
	Drawn: CFrame?, -- where the model was last put
	Shown: boolean,
}

type Booth = {
	User: number?,
	Index: number,
	Frame: CFrame,
	Curtains: { { Model: Model, Parts: { { Part: BasePart, Size: Vector3, Offset: CFrame } } } },
	Open: number, -- 0 shut .. 1 open
	Drawn: number?, -- the Open the curtains were last drawn at
	Toys: { Toy },
	State: any,
	Marks: { Instance },
}

function MessyMemory.Start(api)
	api:Mood({ Tint = rgb(255, 246, 240), Saturation = 0.12, Contrast = 0.04 })
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
	local me = api.Player
	local center = Vector3.new(layout.Center[1], layout.Center[2], layout.Center[3])
	local effects = not State.ReducedEffects()
	local playing = api:Alive() -- (someone who rejoins mid-round watches instead)

	local templates = {}
	local function template(name: string): Model?
		if templates[name] == nil then
			templates[name] = (api:Template(name, 5) :: Model?) or false
		end
		local found = templates[name]
		if not found then
			return nil
		end
		local copy = found:Clone()
		quiet(copy)
		return copy
	end

	local names = {}
	for _, participant in api:Participants() do
		names[participant.UserId] = participant.DisplayName
	end

	-- Booths ---------------------------------------------------------------------------------------
	local booths: { Booth } = {}
	local byUser: { [number]: Booth } = {}
	for index = 1, Rules.BOOTHS do
		local booth: Booth = {
			User = nil,
			Index = index,
			Frame = Rules.BoothFrame(center, index),
			Curtains = {},
			Open = 0,
			Drawn = nil,
			Toys = {},
			State = nil,
			Marks = {},
		}
		booths[index] = booth
		for _ = 1, 2 do
			local model = template("MessyMemoryCurtain")
			if model then
				local pivot = model:GetPivot()
				local pieces = {}
				for _, descendant in model:GetDescendants() do
					if descendant:IsA("BasePart") then
						table.insert(pieces, {
							Part = descendant,
							Size = descendant.Size,
							Offset = pivot:ToObjectSpace(descendant.CFrame),
						})
					end
				end
				model.Parent = api.World
				table.insert(booth.Curtains, { Model = model, Parts = pieces })
			end
		end
	end
	for _, entry in layout.Booths do
		local booth = booths[entry.I]
		if booth then
			booth.User = entry.User
			byUser[entry.User] = booth
		end
	end
	local mine: Booth? = if playing then byUser[me.UserId] else nil

	local function toyFrame(booth: Booth, pos: number, toy: number): CFrame
		local point = Rules.LocalPoint(pos)
		local turn = if Rules.IsSlot(pos) then 0 else math.rad(((toy * 37) % 30) - 15)
		return booth.Frame * CFrame.new(point) * SPIN * CFrame.Angles(0, turn, 0)
	end

	for _, booth in booths do
		if not booth.User then
			continue
		end
		for toy, name in Rules.TOYS do
			local model = template(name)
			local start = toyFrame(booth, Rules.TrayPos(toy), toy)
			booth.Toys[toy] = {
				Model = model,
				Pos = nil,
				From = start,
				To = start,
				T0 = 0,
				Dur = 0,
				Hop = 0,
				Spin = 0,
				Now = start,
				Shown = false,
			}
		end
	end

	-- Shared state ---------------------------------------------------------------------------------
	local phase: any = api:SharedJSON("Phase") or { N = "Ready" }
	local myPositions: { number }? = nil -- this player's toys, with their own moves applied at once
	local homes: { number } = {}
	local mySeq = 0
	local myOpen = false
	local curtainSentAt = -10
	local curtainRecheck = false -- re-read the server's state once the curtain's grace is over
	local selected: number? = nil

	local function positionsFor(booth: Booth): { number }?
		if booth == mine then
			return myPositions
		end
		return booth.State and booth.State.P
	end

	local function setTarget(booth: Booth, toy: number, pos: number?)
		local item = booth.Toys[toy]
		if not item or item.Pos == pos then
			return
		end
		local now = os.clock()
		if pos == nil then
			item.Pos = nil
			return
		end
		local target = toyFrame(booth, pos, toy)
		if not item.Shown or item.Pos == nil then
			-- Appears where it is (a curtain opening, the first state): no flight.
			item.From, item.To, item.Now = target, target, target
			item.Dur = 0
		else
			item.From = item.Now
			item.To = target
			item.T0 = now
			-- Knocked off the shelf by the mischief: a big tumbling flight.
			local mess = phase.N ~= "Place" and not Rules.IsSlot(pos) and item.Pos ~= nil and Rules.IsSlot(item.Pos)
			item.Dur = if mess then 0.85 else MOVE_TIME
			item.Hop = if mess then 3.2 else 0.9
			item.Spin = if mess then (if toy % 2 == 0 then 1 else -1) * math.pi * 2 else 0
			if mess then
				item.T0 = now + (toy - 1) * 0.07
			end
		end
		item.Pos = pos
	end

	local function refreshBooth(booth: Booth)
		local positions = positionsFor(booth)
		for toy = 1, #Rules.TOYS do
			setTarget(booth, toy, positions and positions[toy])
		end
	end

	local function onBooth(booth: Booth, raw: any)
		local data = api:Decode(raw)
		booth.State = data
		if booth == mine and data then
			-- (At the reveal the server's shelf is the one that's scored: always take it.)
			if data.P and ((data.S or 0) >= mySeq or phase.N == "Reveal") then
				myPositions = table.clone(data.P)
				for toy, pos in data.P do
					if not Rules.IsSlot(pos) then
						homes[toy] = pos - Rules.SLOTS
					end
				end
				if selected and myPositions and not myPositions[selected] then
					selected = nil
				end
			end
			if os.clock() - curtainSentAt > 0.8 then
				myOpen = data.O == true
			end
		end
		refreshBooth(booth)
	end
	for user, booth in byUser do
		api:OnShared("B" .. user, function(value)
			onBooth(booth, value)
		end)
		local current = api:Shared("B" .. user)
		if current then
			onBooth(booth, current)
		end
	end

	-- HUD ------------------------------------------------------------------------------------------
	local touch = api:IsTouch()
	local hud = api:TopHud()
	local hudY = api:HudY()
	local panel = UIKit.Panel({
		Name = "MemoryPanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY),
		Size = UDim2.fromOffset(380, 56),
		Visible = false,
		Parent = hud,
	}, rgb(255, 130, 185), rgb(170, 80, 160))
	local panelText = UIKit.Label({
		Name = "PhaseText",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 2),
		Parent = panel,
		Children = { UIKit.TextStroke(0.3) },
	})
	local barBack = UIKit.new("Frame", {
		Name = "TimeBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -28, 0, 7),
		BackgroundColor3 = rgb(80, 30, 80),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = panel,
		Children = { UIKit.Round() },
	})
	local bar = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Yellow,
		BorderSizePixel = 0,
		Parent = barBack,
		Children = { UIKit.Round() },
	})
	local shoutLabel = UIKit.Label({
		Name = "Shout",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 40,
		AnchorPoint = Vector2.new(0.5, 0),
		-- (Phones: in the hint's line, which makes way, so it never covers the top shelf.)
		Position = UDim2.new(0.5, 0, 0, hudY + (if touch then 62 else 130)),
		Size = UDim2.fromOffset(520, 52),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})
	local shoutUntil = 0
	local function shout(text: string, color: Color3?, seconds: number?)
		shoutLabel.Text = text
		shoutLabel.TextColor3 = color or Color3.new(1, 1, 1)
		shoutLabel.Size = UDim2.fromOffset(math.min(520, UIKit.TextWidth(text, 40, Theme.Fonts.Display) + 24), 52)
		shoutLabel.Visible = true
		shoutUntil = os.clock() + (seconds or 1.6)
		UIKit.PopIn(shoutLabel, 0.2)
	end
	local hintText = ""
	local function hint(text: string)
		if text ~= hintText then
			hintText = text
			api:Hint(text, hudY + 62)
		end
	end

	-- Buttons ---------------------------------------------------------------------------------------
	local curtainButton = api:Button({ Text = "CLOSE", Key = Enum.KeyCode.E, Color = Theme.Colors.Pink })
	local peekButton = api:Button({ Text = "PEEK 👀", Key = Enum.KeyCode.Q, Color = Theme.Colors.Cyan, Slot = 2 })
	curtainButton:SetVisible(false)
	peekButton:SetVisible(false)
	if not touch then
		-- PC: in the bottom-right corner instead of the bottom middle, where the counter's toys are.
		for slot, name in { "Action_CLOSE", "Action_PEEK 👀" } do
			local holder = api.Gui:FindFirstChild(name) :: Frame?
			if holder then
				holder.Position = UDim2.new(1, -24 - (slot - 1) * 150, 1, -24)
			end
		end
	end

	local peekUser: number? = nil
	local peekUntil = 0

	local function setCurtain(open: boolean)
		if not mine or phase.N ~= "Place" or os.clock() - curtainSentAt < CURTAIN_COOLDOWN then
			return
		end
		myOpen = open
		curtainSentAt = os.clock()
		curtainRecheck = true
		selected = nil
		api:Action("Curtain", open)
		api:Sound(if open then "Click" else "Boing")
	end
	curtainButton.Pressed:Connect(function()
		setCurtain(not myOpen)
	end)

	-- The next rival booth (round the ring from the one being looked at) whose curtain is open.
	local function nextRival(): Booth?
		if not mine then
			return nil
		end
		local from = if peekUser and byUser[peekUser] then byUser[peekUser].Index else mine.Index
		for step = 1, Rules.BOOTHS do
			local booth = booths[(from + step - 1) % Rules.BOOTHS + 1]
			if booth ~= mine and booth.User and booth.State and booth.State.O and booth.State.P then
				return booth
			end
		end
		return nil
	end
	peekButton.Pressed:Connect(function()
		if not mine or phase.N ~= "Place" then
			return
		end
		local rival = nextRival()
		if not rival or not rival.User then
			shout("Every curtain is shut!", Theme.Colors.Yellow)
			return
		end
		peekUser = rival.User
		peekUntil = os.clock() + PEEK_TIME
		selected = nil
		api:Action("Peek", rival.User)
		api:Sound("Click")
	end)
	api:OnEvent("Peeked", function(userId)
		if type(userId) == "number" then
			shout(`👀 {names[userId] or "Someone"} is peeking!`, Theme.Colors.Cyan)
		end
	end)

	-- Picking ---------------------------------------------------------------------------------------
	local camera = workspace.CurrentCamera
	local markers: { Part } = {}
	if mine then
		-- Little glowing rings on the spots a picked-up toy can go (shown while one is held).
		for pos = 1, Rules.SLOTS + #Rules.TOYS do
			local point = mine.Frame * (Rules.LocalPoint(pos) + Vector3.new(0, 0.03, 0))
			local ring = part({
				Name = "SpotRing",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.05, 1.5, 1.5),
				CFrame = CFrame.new(point) * CFrame.Angles(0, 0, math.rad(90)),
				Color = rgb(255, 240, 120),
				Material = Enum.Material.Neon,
				Transparency = 1,
				Parent = api.World,
			})
			markers[pos] = ring
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = rgb(255, 240, 120)
	highlight.FillTransparency = 0.6
	highlight.OutlineColor = rgb(255, 255, 255)
	highlight.Enabled = false
	highlight.Parent = api.World
	api:Track(highlight)

	local function canPlace(): boolean
		return mine ~= nil and phase.N == "Place" and myOpen and myPositions ~= nil and api:CanAct()
	end

	local function tap(screen: Vector2)
		if peekUser then
			peekUser = nil -- any tap brings you back
			return
		end
		if not canPlace() or not mine then
			if mine and phase.N == "Place" and not myOpen then
				shout("Locked! Tap OPEN to change", Theme.Colors.Yellow, 1.2)
			end
			return
		end
		local positions = myPositions :: { number }
		local radius = PICK_RADIUS * camera.ViewportSize.Y
		local best, bestDistance, bestKind = nil, radius, nil
		local function consider(kind: string, value: number, world: Vector3)
			local point, visible = camera:WorldToScreenPoint(world)
			if not visible then
				return
			end
			local distance = (Vector2.new(point.X, point.Y) - screen).Magnitude
			if distance < bestDistance then
				best, bestDistance, bestKind = value, distance, kind
			end
		end
		local taken = {}
		for toy, pos in positions do
			taken[pos] = toy
			consider("Toy", toy, mine.Frame * (Rules.LocalPoint(pos) + Vector3.new(0, 0.8, 0)))
		end
		for pos = 1, Rules.SLOTS + #Rules.TOYS do
			if not taken[pos] then
				consider("Spot", pos, mine.Frame * (Rules.LocalPoint(pos) + Vector3.new(0, 0.8, 0)))
			end
		end
		if not best then
			if selected then
				selected = nil
				api:Sound("Click")
			end
			return
		end
		local function move(toy: number, target: number)
			if Rules.Move(positions, homes, toy, target) then
				mySeq += 1
				api:Action("Move", mySeq, toy, target)
				api:Sound("Pickup")
				refreshBooth(mine)
			end
			selected = nil
		end
		if bestKind == "Toy" then
			local toy = best :: number
			if selected == toy then
				selected = nil
				api:Sound("Click")
			elseif selected and Rules.IsSlot(positions[toy]) then
				move(selected, positions[toy]) -- into that toy's cubby: they swap
			else
				selected = toy
				api:Sound("Click")
			end
		elseif selected then
			move(selected, best :: number)
		end
	end

	if mine then
		api:Track(UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				tap(Vector2.new(input.Position.X, input.Position.Y))
			end
		end))
	end

	-- Camera ----------------------------------------------------------------------------------------
	local savedFov = camera.FieldOfView
	-- PC: one framing, the top shelf under the HUD and the counter's toys above the bottom edge.
	local function viewOf(booth: Booth): CFrame
		return CFrame.lookAt(booth.Frame * Rules.EYE, booth.Frame * Rules.LOOK)
	end

	-- Phones: the framing for this screen (Rules.PhoneFraming, see the header), worked out again only
	-- when the screen, the HUD or the buttons move. "Shelf" is the shelf alone, centred (nothing on the
	-- counter yet); "Booth" is the shelf and the counter's toys (from the mischief on, and peeking),
	-- clear of PEEK / CLOSE.
	local framed = { Key = "", Eye = Rules.EYE, Pitch = 0, Fov = 60 }
	local function phoneFraming(kind: string): (Vector3, number, number)
		local size = camera.ViewportSize
		local inset = GuiService:GetGuiInset().Y
		-- The bottom of the HUD: the panel, then the hint's (and the shout's) line under it.
		local unit = panel.AbsoluteSize.Y / 56
		local top = 2
			+ if unit > 0
				then inset + panel.AbsolutePosition.Y + HUD_BAND * unit
				else inset + (hudY + HUD_BAND) * UIKit.CurrentScale() * TOUCH_HUD
		local buttons = {}
		if kind == "Booth" then
			for _, name in { "Action_CLOSE", "Action_PEEK 👀" } do
				local holder = api.Gui:FindFirstChild(name) :: GuiObject?
				if holder and holder.AbsoluteSize.X > 0 then
					local middle = holder.AbsolutePosition + holder.AbsoluteSize / 2
					table.insert(buttons, Vector3.new(middle.X, middle.Y + inset, holder.AbsoluteSize.X / 2))
				end
			end
		end
		local key = `{kind} {math.round(size.X)} {math.round(size.Y)} {math.round(top)}`
		for _, button in buttons do
			key ..= ` {math.round(button.X)} {math.round(button.Y)} {math.round(button.Z)}`
		end
		if key ~= framed.Key then
			local eye, pitch, fov = Rules.PhoneFraming(kind, size, top, buttons)
			if eye and pitch and fov then
				framed = { Key = key, Eye = eye, Pitch = pitch, Fov = fov }
			else
				-- (A screen it can't be fitted to: the PC framing.)
				local down = math.atan2(Rules.EYE.Y - Rules.LOOK.Y, Rules.EYE.Z - Rules.LOOK.Z)
				framed = { Key = key, Eye = Rules.EYE, Pitch = down, Fov = 60 }
			end
		end
		return framed.Eye, framed.Pitch, framed.Fov
	end

	-- Where the camera goes for a booth (and its field of view).
	local function goal(booth: Booth): (CFrame, number)
		if not touch then
			return viewOf(booth), 60
		end
		local name = phase.N
		local shelfOnly = booth == mine and (name == nil or name == "Ready" or name == "Study")
		local eye, pitch, fov = phoneFraming(if shelfOnly then "Shelf" else "Booth")
		local at = booth.Frame * eye
		local ahead = booth.Frame:VectorToWorldSpace(Vector3.new(0, -math.sin(pitch), -math.cos(pitch)))
		return CFrame.lookAt(at, at + ahead), fov
	end

	if mine then
		camera.CameraType = Enum.CameraType.Scriptable
		local view, fov = goal(mine)
		camera.FieldOfView = fov
		camera.CFrame = view
		api:Track(function()
			-- Back to Roblox's own camera, following this player's character.
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = savedFov
			local character = me.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end)
		-- No walking: you stand at your booth and the screen is for tapping toys.
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

		if touch then
			-- A wall between every two booths, on this device only: the sides of a wide screen show
			-- your own booth's nook (or the one you're peeking into), never the next booths' shelves.
			local length = DIVIDER_OUT - DIVIDER_IN
			for index = 1, Rules.BOOTHS do
				local base = Rules.BoothFrame(center, index + 0.5) -- (half a booth round: after booth `index`)
					* CFrame.new(0, 0, Rules.RING - (DIVIDER_IN + DIVIDER_OUT) / 2)
				part({
					Name = "Divider",
					Size = Vector3.new(0.4, DIVIDER_HEIGHT, length),
					CFrame = base * CFrame.new(0, DIVIDER_HEIGHT / 2, 0),
					Color = if index % 2 == 0 then rgb(255, 214, 228) else rgb(255, 240, 246),
					Parent = api.World,
				})
				part({
					Name = "DividerTrim",
					Size = Vector3.new(0.9, 0.8, length + 0.3),
					CFrame = base * CFrame.new(0, DIVIDER_HEIGHT + 0.2, 0),
					Color = rgb(150, 110, 200),
					Parent = api.World,
				})
				part({
					Name = "DividerSkirting",
					Size = Vector3.new(0.7, 1.4, length + 0.1),
					CFrame = base * CFrame.new(0, 0.7, 0),
					Color = rgb(150, 110, 200),
					Parent = api.World,
				})
			end
			-- The name boards on the awnings sit right behind the HUD here, half covered: off.
			local arena = api:Arena(2)
			if arena then
				local function hideSign(item: Instance)
					if item:IsA("BasePart") and item.Name == "BoothSign" then
						item.LocalTransparencyModifier = 1
					elseif item:IsA("SurfaceGui") and item.Parent and item.Parent.Name == "BoothSign" then
						item.Enabled = false
					end
				end
				for _, item in arena:GetDescendants() do
					hideSign(item)
				end
				api:Track(arena.DescendantAdded:Connect(hideSign))
			end
		end
	end

	-- Phases ----------------------------------------------------------------------------------------
	local smokes = {}
	local revealShown = 0
	local function clearMarks()
		for _, booth in booths do
			for _, mark in booth.Marks do
				mark:Destroy()
			end
			booth.Marks = {}
		end
	end

	local function burstSmoke()
		for _, booth in booths do
			if not booth.User then
				continue
			end
			for k = 1, if effects then 3 else 1 do
				local model = template("MessyMemorySmoke")
				if model then
					local at = booth.Frame * Vector3.new((k - 2) * 3.4, 4.5 + (k % 2) * 3, -4.2)
					model:PivotTo(CFrame.new(at) * CFrame.Angles(0, k * 1.7, 0))
					model.Parent = api.World
					table.insert(
						smokes,
						{ Model = model, T0 = os.clock() + k * 0.08, At = at, Scale = model:GetScale() }
					)
				end
			end
			if effects and booth == mine then
				api:Effect("Poof", booth.Frame * Vector3.new(0, 6, -4))
			end
		end
	end

	local function onPhase(raw: any)
		local data = api:Decode(raw)
		if type(data) ~= "table" then
			return
		end
		local old: string? = phase.N
		local new: string? = data.N
		phase = data
		if old == new then
			new = nil -- (the same phase again: nothing new to announce)
		end
		if new == "Study" then
			shout("Remember every toy's spot!", Theme.Colors.Yellow, 2.2)
			api:Sound("RoundStart")
		elseif new == "Mess" then
			burstSmoke()
			shout("💨 MISCHIEF!", Theme.Colors.Pink, 1.6)
			api:Sound("Hit")
		elseif new == "Place" then
			if mine then
				shout("Put them back!", Theme.Colors.Green, 1.4)
			end
		elseif new == "Reveal" then
			peekUser = nil
			selected = nil
			revealShown = 0
			clearMarks()
		end
		for _, booth in booths do
			refreshBooth(booth)
		end
	end
	api:OnShared("Phase", onPhase)
	onPhase(api:Shared("Phase"))

	-- One step of the reveal: toy `toy`'s right slot lights up on every shelf.
	local myRight = 0
	local function revealStep(toy: number, slot: number)
		local point = Rules.LocalPoint(slot)
		for _, booth in booths do
			local positions = positionsFor(booth)
			if not booth.User or not positions then
				continue
			end
			local right = positions[toy] == slot
			local ring = part({
				Name = "RevealRing",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.06, 2.1, 2.1),
				CFrame = booth.Frame * CFrame.new(point + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = if right then GOOD else BAD,
				Material = Enum.Material.Neon,
				Transparency = 0.15,
				Parent = api.World,
			})
			table.insert(booth.Marks, ring)
			if booth == mine then
				if right then
					myRight += 1
				end
				local anchor = part({
					Name = "RevealMark",
					Size = Vector3.new(0.2, 0.2, 0.2),
					CFrame = booth.Frame * CFrame.new(point + Vector3.new(0, 2.15, 0.5)),
					Transparency = 1,
					Parent = api.World,
				})
				local gui = Instance.new("BillboardGui")
				gui.Size = UDim2.fromScale(1.3, 1.3)
				gui.LightInfluence = 0
				gui.Parent = anchor
				UIKit.Label({
					Text = if right then "✓" else "✗",
					Font = Theme.Fonts.Display,
					TextScaled = true,
					TextColor3 = if right then GOOD else BAD,
					Size = UDim2.fromScale(1, 1),
					Parent = gui,
					Children = { UIKit.TextStroke(0) },
				})
				table.insert(booth.Marks, anchor)
				if not right then
					-- Where it should have gone: a see-through copy of the toy.
					local ghost = template(Rules.TOYS[toy])
					if ghost then
						for _, descendant in ghost:GetDescendants() do
							if descendant:IsA("BasePart") then
								descendant.Transparency = 0.6
							end
						end
						ghost:PivotTo(toyFrame(booth, slot, toy))
						ghost.Parent = api.World
						table.insert(booth.Marks, ghost)
					end
				end
				api:Sound(if right then "Pickup" else "Click")
			end
		end
	end

	-- A booth's two curtain halves, stretched shut or bunched open (booth.Open, 0..1).
	local function placeCurtains(booth: Booth)
		local width = 1 - (1 - CURTAIN_OPEN) * ease(booth.Open)
		for side, curtain in booth.Curtains do
			local sign = if side == 1 then -1 else 1
			local pivot = booth.Frame * CFrame.new(sign * (CURTAIN_W - CURTAIN_W * width / 2), CURTAIN_Y, CURTAIN_Z)
			for _, piece in curtain.Parts do
				local offset = piece.Offset
				piece.Part.Size = Vector3.new(piece.Size.X * width, piece.Size.Y, piece.Size.Z)
				piece.Part.CFrame = pivot * CFrame.new(offset.X * width, offset.Y, offset.Z) * offset.Rotation
			end
		end
	end

	-- Every frame -------------------------------------------------------------------------------------
	api:RenderStep(function(dt)
		local clock = os.clock()
		if curtainRecheck and mine and clock - curtainSentAt > 0.8 then
			-- The server may have turned the press down: take what it says now.
			curtainRecheck = false
			local current = api:Shared("B" .. me.UserId)
			if current then
				onBooth(mine, current)
			end
		end
		local now = api:Now()
		local name = phase.N

		-- HUD.
		local placing = name == "Place"
		panel.Visible = playing and name ~= "Ready" and name ~= nil
		if name == "Study" then
			local left = math.max(0, (phase.T1 or now) - now)
			panelText.Text = `👀 MEMORIZE!  {math.ceil(left)}`
			bar.Size = UDim2.fromScale(math.clamp(left / Rules.STUDY, 0, 1), 1)
			bar.BackgroundColor3 = Theme.Colors.Yellow
		elseif name == "Mess" then
			panelText.Text = "💨 MISCHIEF!"
			bar.Size = UDim2.fromScale(0, 1)
		elseif placing then
			local left = math.max(0, (phase.T1 or now) - now)
			panelText.Text = `🧸 PUT THEM BACK  {math.ceil(left)}`
			bar.Size = UDim2.fromScale(math.clamp(left / Rules.PLACE, 0, 1), 1)
			bar.BackgroundColor3 = if left < 8 then Theme.Colors.Red else Theme.Colors.Green
		elseif name == "Reveal" then
			panelText.Text = `✓ {myRight} / {#Rules.TOYS}`
			bar.Size = UDim2.fromScale(math.clamp(revealShown / #Rules.TOYS, 0, 1), 1)
			bar.BackgroundColor3 = GOOD
		end
		if shoutLabel.Visible and clock > shoutUntil then
			shoutLabel.Visible = false
		end

		-- Buttons and hints.
		local canAct = mine ~= nil and placing
		curtainButton:SetVisible(canAct)
		peekButton:SetVisible(canAct)
		curtainButton:SetText(if myOpen then "CLOSE" else "OPEN")
		peekButton:SetText(if peekUser then "NEXT 👀" else "PEEK 👀")
		if peekUser and (clock > peekUntil or not placing) then
			peekUser = nil
		end
		if peekUser and byUser[peekUser] and not (byUser[peekUser].State and byUser[peekUser].State.O) then
			peekUser = nil -- they shut their curtain
		end
		local line = ""
		if mine and peekUser then
			line = `Peeking at {names[peekUser] or "a rival"}... tap to go back`
		elseif mine and placing and not myOpen then
			line = "Locked in! OPEN to change your answers"
		elseif mine and placing and selected then
			line = `Now tap where the {Rules.TOY_NAMES[selected]} goes`
		elseif mine and placing then
			line = "Tap a toy, then tap its spot"
		end
		hint(if touch and shoutLabel.Visible then "" else line) -- (phones: the shout is in its line)

		-- Reveal steps.
		if name == "Reveal" and phase.Order and phase.Answer then
			while revealShown < #phase.Order and now >= phase.T0 + revealShown * phase.Step do
				revealShown += 1
				local toy = phase.Order[revealShown]
				revealStep(toy, phase.Answer[toy])
			end
		end

		-- Curtains.
		for _, booth in booths do
			local open = false
			if booth.User then
				if booth == mine and placing then
					open = myOpen
				else
					open = (booth.State and booth.State.O) or name == "Reveal"
				end
				if booth.State and booth.State.L and name ~= "Reveal" then
					open = false
				end
			end
			local target = if open then 1 else 0
			if booth.Open ~= target then
				booth.Open = if target > booth.Open
					then math.min(target, booth.Open + dt * 2.4)
					else math.max(target, booth.Open - dt * 2.4)
			end
			if booth.Drawn ~= booth.Open then
				booth.Drawn = booth.Open
				placeCurtains(booth)
			end

			-- Toys.
			for toy, item in booth.Toys do
				local model = item.Model
				if not model then
					continue
				end
				local show = item.Pos ~= nil
				if show ~= item.Shown then
					item.Shown = show
					model.Parent = if show then api.World else nil
				end
				if not show then
					continue
				end
				local frame = item.To
				if item.Dur > 0 then
					local f = (clock - item.T0) / item.Dur
					if f >= 1 then
						item.Dur = 0
					elseif f > 0 then
						local e = ease(f)
						frame = item.From:Lerp(item.To, e)
							* CFrame.new(0, math.sin(f * math.pi) * item.Hop, 0)
							* CFrame.Angles(item.Spin * e * 0.3, item.Spin * e, 0)
					else
						frame = item.From
					end
				end
				if booth == mine and selected == toy then
					frame = frame * CFrame.new(0, 0.45 + math.sin(clock * 6) * 0.12, 0)
				end
				if item.Drawn ~= frame then
					item.Drawn = frame
					item.Now = frame
					model:PivotTo(frame)
				end
			end
		end

		-- The held toy glows, and the spots it can go show.
		local held = if mine and selected and placing then mine.Toys[selected] else nil
		if held and held.Model then
			highlight.Adornee = held.Model
			highlight.Enabled = true
		else
			highlight.Enabled = false
		end
		if mine then
			local taken = {}
			if myPositions then
				for _, pos in myPositions :: { number } do
					taken[pos] = true
				end
			end
			for pos, ring in markers do
				local wanted = held ~= nil and not taken[pos]
				ring.Transparency = if wanted then 0.35 + math.sin(clock * 5) * 0.15 else 1
			end
		end

		-- Smoke puffs: swell and fade.
		for index = #smokes, 1, -1 do
			local smoke = smokes[index]
			local f = (clock - smoke.T0) / 1.5
			if f >= 1 then
				smoke.Model:Destroy()
				table.remove(smokes, index)
			elseif f > 0 then
				smoke.Model:ScaleTo(smoke.Scale * (0.5 + 1.1 * ease(math.min(f * 2, 1))))
				smoke.Model:PivotTo(CFrame.new(smoke.At + Vector3.new(0, f * 2, 0)) * CFrame.Angles(0, f, 0))
				for _, descendant in smoke.Model:GetDescendants() do
					if descendant:IsA("BasePart") then
						descendant.Transparency = math.clamp((f - 0.45) / 0.55, 0, 1)
					end
				end
			end
		end

		-- Camera: your booth, or the rival you're peeking at (eased, and on phones eased between the
		-- shelf alone and the shelf with the counter).
		if mine then
			if camera.CameraType ~= Enum.CameraType.Scriptable then
				camera.CameraType = Enum.CameraType.Scriptable
			end
			local booth = if peekUser and byUser[peekUser] then byUser[peekUser] else mine
			local view, fov = goal(booth)
			local blend = math.clamp(dt * 5, 0, 1)
			camera.CFrame = camera.CFrame:Lerp(view, blend)
			if camera.FieldOfView ~= fov then
				camera.FieldOfView += (fov - camera.FieldOfView) * blend
			end
		end
	end)
end

return MessyMemory

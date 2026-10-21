-- Client half of Stamp Out: draws the inked paper, flies this player's STAMP hops and shows the
-- standings. The server (MiniGames/StampOut.luau) decides every stamp; this only draws them.
--
--   * The pad: the server shares it as one string ("Grid", a character per cell) twice a second and
--     sends a "Stamp" event (ink, x, z, radius) for every landing. Each event is redrawn at once with
--     the same Logic/StampGrid.Disc() the server used, so the ink appears the moment it lands; the
--     string keeps everyone in step (cells an event touched in the last moment are left alone, so
--     an older string never flickers them back). Cells are flat tiles made when first inked, a hair
--     above the paper, never collidable. Each stamp also leaves its owner's symbol in the middle of
--     the blot (removed when someone stamps over it), so the pad reads without colour too.
--   * STAMP (E, or the button beside jump on phones): hold to charge (the button fills and a ring
--     shows where you'll land), let go to hop forward. This device flies its own character (the
--     same arc as StampGrid.Hop, the server flies bots' hops the same way) and tells the server
--     "Charge"/"Hop" so it can time the hold and size the stamp.
--   * HUD: a bar split by everyone's share of the pad (colour + symbol), and chips for the top three
--     and you (rank, symbol, %).

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StampGrid = require(ReplicatedStorage.Shared.Logic.StampGrid)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local StampOut = {}

local CELL = StampGrid.CELL
local INKS = StampGrid.INKS
local MAX_MARKS = 100
local EVENT_HOLD = 0.8 -- seconds a cell an event drew ignores the shared string

local function brightness(color: Color3): number
	return color.R * 0.3 + color.G * 0.59 + color.B * 0.11
end

local function ordinal(n: number): string
	if n == 1 then
		return "1st"
	elseif n == 2 then
		return "2nd"
	elseif n == 3 then
		return "3rd"
	end
	return `{n}th`
end

local function decor(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Parent" then
			(part :: any)[key] = value
		end
	end
	part.Parent = props.Parent
	return part
end

function StampOut.Start(api)
	api:Mood({ Tint = Color3.fromRGB(255, 247, 234), Saturation = 0.12, Contrast = 0.04 })

	-- The pad's place and size (the server shares it in Prepare; wait a moment if it's not here yet).
	local pad = api:SharedJSON("Pad")
	local deadline = os.clock() + 5
	while not pad and os.clock() < deadline do
		task.wait(0.1)
		pad = api:SharedJSON("Pad")
	end
	if pad and type(pad.N) == "number" then
		StampGrid.Configure(pad.N)
	end
	local N = StampGrid.N
	local inks = api:SharedJSON("Inks") or {}
	local myInk = inks[tostring(api.Player.UserId)]
	local paperY = if pad then pad.Y else 0
	local paperX = if pad then pad.X else 0
	local paperZ = if pad then pad.Z else 0
	api:OnShared("Pad", function()
		local value = api:SharedJSON("Pad")
		if value then
			pad = value
			paperX, paperY, paperZ = value.X, value.Y, value.Z
		end
	end)
	api:OnShared("Inks", function()
		inks = api:SharedJSON("Inks") or {}
		myInk = inks[tostring(api.Player.UserId)]
	end)

	-- The pad's ink ---------------------------------------------------------------------------------
	local folder = Instance.new("Folder")
	folder.Name = "StampOutInk"
	folder.Parent = api.World
	local owners = table.create(N * N, 0)
	local counts = {} -- ink -> cells
	local tiles = {} -- cell -> Part
	local heldUntil = {} -- cell -> os.clock() until which the shared string leaves it alone
	local marks = {} -- cell -> { Part, Ink }
	local markOrder = {}
	local dirty = true

	local function tint(cell: number, color: Color3): Color3
		-- A little mottling so the ink looks printed rather than painted.
		local wobble = ((cell * 7919) % 101) / 101
		return color:Lerp(Color3.new(1, 1, 1), wobble * 0.09)
	end

	local function removeMark(cell: number)
		local mark = marks[cell]
		if mark then
			marks[cell] = nil
			mark.Part:Destroy()
		end
	end

	local function setCell(cell: number, ink: number)
		local previous = owners[cell]
		if previous == ink then
			return
		end
		owners[cell] = ink
		if previous > 0 then
			counts[previous] = (counts[previous] or 1) - 1
		end
		if ink > 0 then
			counts[ink] = (counts[ink] or 0) + 1
		end
		dirty = true
		local tile = tiles[cell]
		if ink == 0 then
			if tile then
				tile.Transparency = 1
			end
		else
			if not tile then
				local x, z = StampGrid.Center(cell)
				tile = decor({
					Name = "Ink",
					Size = Vector3.new(CELL - 0.02, 0.04, CELL - 0.02), -- a hair under a cell
					-- (a checkerboard of two heights 0.13 apart: neighbours' sides never share a plane)
					CFrame = CFrame.new(
						paperX + x,
						paperY + (if (cell + (cell - 1) // N) % 2 == 0 then 0.22 else 0.35),
						paperZ + z
					),
					Parent = folder,
				})
				tiles[cell] = tile
			end
			local t = tile :: Part
			t.Transparency = 0
			t.Color = tint(cell, INKS[ink].Color)
		end
		local mark = marks[cell]
		if mark and mark.Ink ~= ink then
			removeMark(cell)
		end
	end

	local function addMark(ink: number, x: number, z: number, radius: number)
		local ix, iz = StampGrid.CellAt(x, z)
		if not ix or not iz then
			return
		end
		local cell = StampGrid.Index(ix, iz)
		removeMark(cell)
		local size = radius * 1.25
		local part = decor({
			Name = "Mark",
			Size = Vector3.new(size, 0.05, size),
			CFrame = CFrame.new(paperX + x, paperY + 0.45, paperZ + z),
			Transparency = 1,
			Parent = folder,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		gui.LightInfluence = 1
		gui.MaxDistance = 220
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Theme.Fonts.Display
		label.TextScaled = true
		label.Text = INKS[ink].Symbol
		label.TextColor3 = INKS[ink].Color:Lerp(Color3.new(0, 0, 0), 0.45)
		label.TextTransparency = 0.1
		label.Parent = gui
		marks[cell] = { Part = part, Ink = ink }
		table.insert(markOrder, cell)
		while #markOrder > MAX_MARKS do
			local oldest = table.remove(markOrder, 1)
			local stale = marks[oldest]
			if stale and stale.Part ~= part then
				removeMark(oldest)
			end
		end
	end

	-- A ring of ink that bursts out where a stamp lands.
	local function splash(ink: number, x: number, z: number, radius: number)
		local ring = decor({
			Name = "Splash",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, radius * 1.2, radius * 1.2),
			CFrame = CFrame.new(paperX + x, paperY + 0.55, paperZ + z) * CFrame.Angles(0, 0, math.pi / 2),
			Color = INKS[ink].Color,
			Material = Enum.Material.Neon,
			Transparency = 0.35,
			Parent = folder,
		})
		local tween = TweenService:Create(
			ring,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.12, radius * 2.5, radius * 2.5), Transparency = 1 }
		)
		tween:Play()
		task.delay(0.4, function()
			ring:Destroy()
		end)
	end

	api:OnEvent("Stamp", function(ink, x, z, radius)
		if type(ink) ~= "number" or not INKS[ink] or type(x) ~= "number" or type(z) ~= "number" then
			return
		end
		if type(radius) ~= "number" then
			return
		end
		local now = os.clock()
		for _, cell in StampGrid.Disc(x, z, radius) do
			setCell(cell, ink)
			heldUntil[cell] = now + EVENT_HOLD
		end
		addMark(ink, x, z, radius)
		splash(ink, x, z, radius)
		if ink == myInk then
			api:Sound("Hit")
		end
	end)

	local function applyGrid()
		local text = api:Shared("Grid")
		if type(text) ~= "string" then
			return
		end
		local now = os.clock()
		local decoded = StampGrid.Decode(text)
		for cell, ink in decoded do
			if owners[cell] ~= ink and (heldUntil[cell] or 0) < now then
				setCell(cell, ink)
			end
		end
	end
	api:OnShared("Grid", applyGrid)
	applyGrid()

	-- HUD -------------------------------------------------------------------------------------------
	local hud = api:TopHud()
	local y0 = api:HudY()
	local bar = UIKit.new("Frame", {
		Name = "StampOutShare",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y0),
		Size = UDim2.fromOffset(500, 34),
		BackgroundColor3 = Color3.fromRGB(252, 249, 238),
		ClipsDescendants = true,
		Parent = hud,
		Children = {
			UIKit.Corner(10),
			UIKit.Stroke(Color3.fromRGB(40, 30, 70), 3, 0),
			UIKit.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	local segments = {}
	local chips = UIKit.new("Frame", {
		Name = "StampOutChips",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y0 + 42),
		Size = UDim2.fromOffset(600, 40),
		BackgroundTransparency = 1,
		Parent = hud,
		Children = {
			UIKit.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 8),
			}),
		},
	})
	local chipFrames = {}
	local function chip(index: number): (Frame, TextLabel)
		local existing = chipFrames[index]
		if existing then
			return existing.Frame, existing.Label
		end
		local frame = UIKit.new("Frame", {
			Name = "Chip" .. index,
			Size = UDim2.fromOffset(136, 38),
			LayoutOrder = index,
			Parent = chips,
			Children = { UIKit.Corner(12) },
		})
		local stroke = UIKit.Stroke(Color3.new(1, 1, 1), 2, 0.2)
		stroke.Parent = frame
		local label = UIKit.Label({
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = 24,
			Size = UDim2.fromScale(1, 1),
			Parent = frame,
			Children = { UIKit.TextStroke(0.3) },
		})
		chipFrames[index] = { Frame = frame, Label = label, Stroke = stroke }
		return frame, label
	end

	local function refreshHud()
		local total = N * N
		local order = {}
		for ink, cells in counts do
			if cells > 0 then
				table.insert(order, ink)
			end
		end
		table.sort(order, function(a, b)
			if counts[a] ~= counts[b] then
				return counts[a] > counts[b]
			end
			return a < b
		end)
		-- The share bar, biggest first.
		for ink, segment in segments do
			if (counts[ink] or 0) <= 0 then
				segment.Visible = false
			end
		end
		for rank, ink in order do
			local segment = segments[ink]
			if not segment then
				local color = INKS[ink].Color
				segment = UIKit.new("Frame", {
					Name = "Ink" .. ink,
					BackgroundColor3 = color,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(0, 1),
					Parent = bar,
				})
				UIKit.Label({
					Name = "Symbol",
					Text = INKS[ink].Symbol,
					Font = Theme.Fonts.Display,
					TextSize = 28,
					TextColor3 = if brightness(color) > 0.62 then Color3.fromRGB(40, 30, 50) else Color3.new(1, 1, 1),
					Size = UDim2.fromScale(1, 1),
					Parent = segment,
				})
				segments[ink] = segment
			end
			segment.Visible = true
			segment.LayoutOrder = rank
			segment.Size = UDim2.fromScale(counts[ink] / total, 1)
			local symbol = segment:FindFirstChild("Symbol") :: TextLabel?
			if symbol then
				symbol.Visible = counts[ink] / total > 0.06
			end
		end
		-- Chips: the top three, then you if you're not among them.
		local shown = {}
		for rank = 1, math.min(3, #order) do
			table.insert(shown, { Rank = rank, Ink = order[rank] })
		end
		if myInk then
			local myRank = table.find(order, myInk)
			if not myRank or myRank > 3 then
				table.insert(shown, { Rank = myRank or (#order + 1), Ink = myInk })
			end
		end
		for index = 1, 4 do
			local entry = shown[index]
			local existing = chipFrames[index]
			if not entry then
				if existing then
					existing.Frame.Visible = false
				end
				continue
			end
			local frame, label = chip(index)
			local ink = INKS[entry.Ink]
			local mine = entry.Ink == myInk
			frame.Visible = true
			frame.BackgroundColor3 = ink.Color
			label.TextColor3 = if brightness(ink.Color) > 0.62 then Color3.fromRGB(40, 30, 50) else Color3.new(1, 1, 1)
			local percent = StampGrid.Percent(counts[entry.Ink] or 0)
			label.Text = if mine then `YOU {ink.Symbol} {percent}%` else `{ordinal(entry.Rank)} {ink.Symbol} {percent}%`
			local holder = chipFrames[index]
			holder.Stroke.Thickness = if mine then 4 else 2
			holder.Stroke.Color = if mine then Color3.fromRGB(255, 236, 120) else Color3.new(1, 1, 1)
		end
	end
	refreshHud()

	-- The tip shows once this player can move (after the rules card and the 3-2-1), for a few seconds.
	local hinted = false
	local function hint()
		hinted = true
		api:Hint("Every landing stamps! Hold STAMP for a big hop", y0 + 90)
		task.delay(7, function()
			if hud.Parent then
				api:Hint("")
			end
		end)
	end

	-- STAMP: charge and hop -------------------------------------------------------------------------
	local button = api:Button({ Text = "STAMP", Key = Enum.KeyCode.E, Color = Theme.Colors.Pink })
	local chargeStart: number? = nil
	local queued: { Charge: number, Until: number }? = nil
	local flight: { Dir: Vector3, Along: number, Up: number, Until: number, Start: number }? = nil
	local aim = decor({
		Name = "StampOutAim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 4, 4),
		Color = if myInk then INKS[myInk].Color else Color3.new(1, 1, 1),
		Material = Enum.Material.Neon,
		Transparency = 1,
		Parent = folder,
	})

	local function grounded(humanoid: Humanoid): boolean
		return humanoid.FloorMaterial ~= Enum.Material.Air
	end

	local function hopDirection(humanoid: Humanoid, root: BasePart): Vector3
		local move = humanoid.MoveDirection
		local flat = Vector3.new(move.X, 0, move.Z)
		if flat.Magnitude < 0.2 then
			local look = root.CFrame.LookVector
			flat = Vector3.new(look.X, 0, look.Z)
		end
		return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	end

	local function charged(): number
		return if chargeStart then math.clamp((os.clock() - chargeStart) / StampGrid.CHARGE_TIME, 0, 1) else 0
	end

	local function hop(charge: number)
		local _, humanoid, root = api:Character()
		if not humanoid or not root or humanoid.WalkSpeed <= 0 then
			return
		end
		local _, up, along, airtime = StampGrid.Hop(charge, workspace.Gravity)
		local dir = hopDirection(humanoid, root)
		api:Action("Hop", charge, dir.X, dir.Z)
		root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
		-- Freefall (not Jumping: a jump would replace the launch speed with the character's JumpPower).
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		root.AssemblyLinearVelocity = dir * along + Vector3.new(0, up, 0)
		flight = { Dir = dir, Along = along, Up = up, Until = os.clock() + airtime + 0.15, Start = os.clock() }
		api:Sound("Boing")
	end

	button.Pressed:Connect(function()
		chargeStart = os.clock()
		api:Action("Charge")
	end)
	button.Released:Connect(function()
		local charge = charged()
		chargeStart = nil
		button:SetFill(0)
		local _, humanoid = api:Character()
		if humanoid and grounded(humanoid) and not flight then
			hop(charge)
		else
			queued = { Charge = charge, Until = os.clock() + 0.3 }
		end
	end)

	api:RenderStep(function()
		local _, humanoid, root = api:Character()
		local now = os.clock()
		-- Keep the hop's ground speed (the character's own air control would slow it down).
		if flight then
			if humanoid and root and now < flight.Until and (now - flight.Start < 0.12 or not grounded(humanoid)) then
				local t = now - flight.Start
				-- The first frames set the climb too (the floor's grip can eat a little of it).
				local vertical = if t < 0.06 then flight.Up - workspace.Gravity * t else root.AssemblyLinearVelocity.Y
				root.AssemblyLinearVelocity = flight.Dir * flight.Along + Vector3.new(0, vertical, 0)
			else
				flight = nil
			end
		end
		if queued then
			if now > queued.Until then
				queued = nil
			elseif humanoid and grounded(humanoid) and not flight then
				local charge = queued.Charge
				queued = nil
				hop(charge)
			end
		end
		-- While charging: fill the button and ring the spot you'll land on.
		if chargeStart and humanoid and root then
			local charge = charged()
			button:SetFill(charge)
			local distance, _, _, _, radius = StampGrid.Hop(charge, workspace.Gravity)
			local dir = hopDirection(humanoid, root)
			local spot = root.Position + dir * distance
			aim.Size = Vector3.new(0.1, radius * 2, radius * 2)
			aim.CFrame = CFrame.new(spot.X, paperY + 0.65, spot.Z) * CFrame.Angles(0, 0, math.pi / 2)
			aim.Transparency = 0.55
		else
			aim.Transparency = 1
		end
		if dirty then
			dirty = false
			refreshHud()
		end
		if not hinted and humanoid and humanoid.WalkSpeed > 0 and api:CanAct() then
			hint()
		end
	end)
end

return StampOut

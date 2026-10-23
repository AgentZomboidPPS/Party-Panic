-- Client half of Obby Odyssey: the moving parts of the course and the race HUD.
--
-- The swinging balls, the spinning bars and the blinking blocks all follow the shared schedule (MG_Course:
-- the arena's origin and the schedule's epoch, with Shared/Logic/ObbyOdyssey's numbers), so they're in
-- the same place on every screen and where the server judges them. A blinking block also stops holding
-- this player up the moment it's gone on their own screen (it turns see-through and non-solid here); it
-- flashes for its last BlinkWarn seconds first, and a faint ghost shows where it comes back.
--
-- HUD (phones first, everything under the round banner and clear of the thumbstick's corner): a race
-- strip with every runner's numbered dot from the start to the 👑 (riders side by side step above and
-- below the line: Logic/RaceBar, the checkpoints as ticks) and one line under it, your place and your
-- checkpoints. The server's toasts say each checkpoint (and the section after it), a splash back to one,
-- and the crown; here they get their sound and sparkle. Pads you've reached turn gold.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Course = require(ReplicatedStorage.Shared.Logic.ObbyOdyssey)
local RaceBar = require(ReplicatedStorage.Shared.Logic.RaceBar)

local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ObbyOdyssey = {}

local CLOCK_TIME = 13.5 -- a bright midday for the round, put back afterwards
local GOLD = Color3.fromRGB(255, 204, 64)

type Mover = { Parts: { BasePart }, Offsets: { CFrame } }

-- A model's parts and where each sits from `base` (its pose as the server built it).
local function moverFor(model: Instance, base: CFrame): Mover
	local mover = { Parts = {}, Offsets = {} }
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(mover.Parts, item)
			table.insert(mover.Offsets, base:ToObjectSpace(item.CFrame))
		end
	end
	return mover
end

function ObbyOdyssey.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 252, 244),
		Saturation = 0.2,
		Contrast = 0.06,
	})
	local clockTime = Lighting.ClockTime
	Lighting.ClockTime = CLOCK_TIME
	api:Track(function()
		Lighting.ClockTime = clockTime
	end)

	local myKey = tostring(Players.LocalPlayer.UserId)
	local touch = api:IsTouch()

	local origin: Vector3? = nil
	local epoch = api:Now()
	local riders: { [string]: { L: number, C: Color3, N: string } } = {}
	local function readCourse()
		local value = api:SharedJSON("Course")
		if type(value) ~= "table" or type(value.O) ~= "table" then
			return
		end
		origin = Vector3.new(value.O[1], value.O[2], value.O[3])
		epoch = tonumber(value.E) or epoch
		for _, entry in value.Riders or {} do
			local c = entry.C or { 255, 255, 255 }
			riders[tostring(entry.U)] = { L = entry.L or 1, C = Color3.fromRGB(c[1], c[2], c[3]), N = entry.N or "" }
		end
	end
	readCourse()
	api:OnShared("Course", readCourse)

	local snapshot: { T: number, R: { [string]: any } } = { T = 0, R = {} }
	local function readRunners()
		local value = api:SharedJSON("Runners")
		if type(value) == "table" and type(value.R) == "table" then
			snapshot = value
		end
	end
	readRunners()
	api:OnShared("Runners", readRunners)

	-- The moving parts, found as the arena arrives ------------------------------------------------------

	local arena = api:Arena(20)
	local balls: { { Spec: Course.Ball, Mover: Mover } } = {}
	local bars: { { Spec: Course.Spinner, Mover: Mover } } = {}
	local blinks: { { Piece: Course.Piece, Parts: { BasePart }, Shown: string? } } = {}
	local glows: { { Part: BasePart, Checkpoint: number, Lit: boolean } } = {}
	local crown: Mover? = nil
	local found: { [Instance]: boolean } = {}
	local piecesById: { [string]: Course.Piece } = {}
	for _, piece in Course.Pieces do
		piecesById[piece.Id] = piece
	end
	local ballsById: { [string]: Course.Ball } = {}
	for _, ball in Course.Balls do
		ballsById[ball.Id] = ball
	end

	local function scan()
		local o = origin
		if not arena or not o then
			return
		end
		local folder = arena:FindFirstChild("Balls")
		for _, model in if folder then folder:GetChildren() else {} do
			local spec = ballsById[model.Name]
			if spec and not found[model] and #model:GetChildren() >= 4 then
				found[model] = true
				local hinge = CFrame.new(o + Vector3.new(spec.X, spec.PivotY, spec.Z))
				table.insert(balls, { Spec = spec, Mover = moverFor(model, hinge) })
			end
		end
		folder = arena:FindFirstChild("Bars")
		for _, model in if folder then folder:GetChildren() else {} do
			local index = model:GetAttribute("Spinner")
			local spec = if type(index) == "number" then Course.Spinners[index] else nil
			if spec and not found[model] and #model:GetChildren() >= 9 then
				found[model] = true
				local center = CFrame.new(o + Vector3.new(spec.X, spec.Top + spec.BarY, spec.Z))
				table.insert(bars, { Spec = spec, Mover = moverFor(model, center) })
			end
		end
		folder = arena:FindFirstChild("Blinks")
		for _, part in if folder then folder:GetChildren() else {} do
			local piece = piecesById[part.Name]
			if piece and part:IsA("BasePart") and not found[part] then
				found[part] = true
				local parts = { part }
				for _, item in part:GetDescendants() do
					if item:IsA("BasePart") then
						table.insert(parts, item)
					end
				end
				table.insert(blinks, { Piece = piece, Parts = parts, Shown = nil })
			end
		end
		folder = arena:FindFirstChild("Pads")
		for _, part in if folder then folder:GetChildren() else {} do
			local checkpoint = part:GetAttribute("Checkpoint")
			if part:IsA("BasePart") and part.Name == "Glow" and type(checkpoint) == "number" and not found[part] then
				found[part] = true
				table.insert(glows, { Part = part, Checkpoint = checkpoint, Lit = false })
			end
		end
		local model = arena:FindFirstChild("Crown")
		if model and not crown and #model:GetChildren() >= 30 then
			local summit = Course.Summit
			crown = moverFor(model, CFrame.new(o + Vector3.new(summit.X, summit.Top + 8.5, summit.Z)))
		end
	end
	local scanned = 0

	-- HUD ------------------------------------------------------------------------------------------------

	local hud = api:TopHud()
	local hudY = api:HudY()
	local barWidth = 560
	local trackLength = barWidth - 70
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
		Position = UDim2.new(0.5, -6, 0.5, 0),
		Size = UDim2.new(1, -70, 0, 8),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = bar,
		Children = { UIKit.Round() },
	})
	-- The checkpoints along the strip: small ticks with their number.
	for index, pad in Course.Checkpoints do
		local x, y, z = Course.RowMiddle(pad.Row)
		local at = Course.Progress(pad.Row, x, y, z) / Course.Length
		UIKit.new("Frame", {
			Name = `Tick{index}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(at, 0.5),
			Size = UDim2.fromOffset(4, if touch then 22 else 16),
			BackgroundColor3 = Theme.Colors.TextDim,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Parent = lane,
		})
	end
	UIKit.Label({
		Name = "Goal",
		Text = "👑",
		TextSize = if touch then 26 else 22,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 6, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
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
			Name = "Runner" .. key,
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

	local placeY = hudY + barHeight + 8
	local placeLabel = UIKit.Label({
		Name = "Place",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, placeY),
		Size = UDim2.fromOffset(320, 32),
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})
	-- Cues from the server ------------------------------------------------------------------------------

	local myStage = 0
	api:OnEvent("Checkpoint", function(stage: number)
		if type(stage) ~= "number" then
			return
		end
		myStage = math.max(myStage, stage)
		api:Sound("Pickup")
		local _, _, root = api:Character()
		if root then
			api:Effect("Sparkles", root.Position, { Theme.Colors.Green, GOLD })
		end
	end)
	api:OnEvent("Splash", function(userId: number, x: number, z: number, lava: boolean)
		local o = origin
		if not o or type(x) ~= "number" or type(z) ~= "number" then
			return
		end
		local position = o + Vector3.new(x, 0.5, z)
		api:Effect(if lava then "Poof" else "Bubbles", position)
		if tostring(userId) == myKey then
			api:Sound("Splash")
		end
	end)
	api:OnEvent("Bonk", function(userId: number, x: number, y: number, z: number)
		local o = origin
		if not o or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
			return
		end
		api:Effect("Stars", o + Vector3.new(x, y + 2, z))
		if tostring(userId) == myKey then
			api:Sound("Boing")
		end
	end)
	api:OnEvent("Finish", function(userId: number, place: number, time: number)
		if type(place) ~= "number" or type(time) ~= "number" then
			return
		end
		local o = origin
		local character = api:CharacterOf(userId)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			api:Effect(if place == 1 then "Finale" else "Confetti", root.Position)
		elseif o then
			local summit = Course.Summit
			api:Effect("Confetti", o + Vector3.new(summit.X, summit.Top + 3, summit.Z))
		end
		if tostring(userId) == myKey then
			myStage = #Course.Checkpoints
			api:Sound("Victory")
		end
	end)

	-- Every frame -----------------------------------------------------------------------------------------

	local shown: { [string]: number } = {}
	local dotTiers: { [string]: number } = {}
	local dotRanks: { [string]: number } = {}
	local dotShifts: { [string]: { X: number, Y: number } } = {}
	local lastPlace = ""
	local moveParts: { BasePart } = {}
	local moveFrames: { CFrame } = {}

	api:RenderStep(function(dt)
		local o = origin
		if not o then
			return
		end
		scanned -= dt
		if scanned <= 0 then
			scanned = 0.5
			scan()
		end
		local t = api:Now() - epoch

		-- The balls swing, the bars turn and the crown spins: moved all at once.
		table.clear(moveParts)
		table.clear(moveFrames)
		local function place(mover: Mover, frame: CFrame)
			for index, part in mover.Parts do
				table.insert(moveParts, part)
				table.insert(moveFrames, frame * mover.Offsets[index])
			end
		end
		for _, entry in balls do
			local spec = entry.Spec
			local hinge = CFrame.new(o + Vector3.new(spec.X, spec.PivotY, spec.Z))
			place(entry.Mover, hinge * CFrame.Angles(0, 0, Course.BallAngle(spec, t)))
		end
		for _, entry in bars do
			local spec = entry.Spec
			local center = CFrame.new(o + Vector3.new(spec.X, spec.Top + spec.BarY, spec.Z))
			place(entry.Mover, center * CFrame.Angles(0, -Course.SpinnerAngle(spec, t), 0))
		end
		local crownMover = crown
		if crownMover then
			local summit = Course.Summit
			local center = o + Vector3.new(summit.X, summit.Top + 8.5 + math.sin(t * 1.6) * 0.6, summit.Z)
			place(crownMover, CFrame.new(center) * CFrame.Angles(0, t * 0.9, 0))
		end
		if #moveParts > 0 then
			workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end

		-- The blinking blocks: solid, flashing, or a faint ghost you fall through.
		for _, entry in blinks do
			local solid, warning = Course.BlinkState(entry.Piece, t)
			local look = if not solid then "gone" elseif warning then (if t * 8 % 2 < 1 then "on" else "dim") else "on"
			if look ~= entry.Shown then
				entry.Shown = look
				for _, part in entry.Parts do
					part.Transparency = if look == "gone" then 0.86 elseif look == "dim" then 0.55 else 0
					part.CanCollide = look ~= "gone"
				end
			end
		end

		-- Pads I've reached glow gold.
		for _, glow in glows do
			local lit = myStage >= glow.Checkpoint
			if lit ~= glow.Lit then
				glow.Lit = lit
				glow.Part.Color = if lit then GOLD else Color3.fromRGB(90, 230, 120)
			end
		end

		-- The race strip and my place.
		local dots: { RaceBar.Dot } = {}
		local order = {}
		for key in riders do
			local data = snapshot.R[key]
			local dot = markers[key]
			if not data then
				if dot then
					dot.Visible = false
				end
				continue
			end
			local target = math.clamp((tonumber(data.P) or 0) / Course.Length, 0, 1)
			if data.F then
				target = 1
			end
			local current = shown[key] or target
			current += (target - current) * (1 - math.exp(-dt * 6))
			shown[key] = current
			dot = marker(key)
			dot.Visible = true
			local isMine = key == myKey
			table.insert(dots, {
				Key = key,
				X = current * trackLength,
				Size = if isMine then MY_DOT else DOT,
				Tier = dotTiers[key],
				Rank = dotRanks[key],
			})
			table.insert(
				order,
				{ Key = key, Score = if data.F then 1e6 - data.F else (tonumber(data.S) or 0) * 1e4 + (data.P or 0) }
			)
		end
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
		local placeText = ""
		for index, item in order do
			if item.Key == myKey then
				local data = snapshot.R[myKey]
				placeText = if data and data.F
					then `👑 {Course.Ordinal(data.F)} · {string.format("%.1f", data.T or 0)}s`
					else `{Course.Ordinal(index)} of {#order}`
			end
		end
		local mine = snapshot.R[myKey]
		if mine and type(mine.S) == "number" then
			myStage = math.max(myStage, mine.S)
		end
		if not (mine and mine.F) and placeText ~= "" then
			placeText ..= `  ·  ✓{myStage}/{#Course.Checkpoints}`
		end
		if placeText ~= lastPlace then
			lastPlace = placeText
			placeLabel.Text = placeText
		end
	end)
end

return ObbyOdyssey

-- Client half of Crazy Cutters: everyone's cutting board, the dotted outline, each cutter and the
-- line it has cut, the cookie that pops out onto the plate, and this player's controls and HUD.
--
-- YOUR BOARD fills the screen (a fixed camera over it). The pastry wheel follows your finger or
-- the mouse while it's held down (WASD / arrow keys / a gamepad stick steer it too) and cuts
-- wherever it goes, so the cut is one continuous line from the start flag. Your cut and your score
-- are drawn at once from your own moves (Shared/Logic/CrazyCutters scores them exactly like the
-- server); the positions go to the server in small batches, and the server's score is the one
-- that counts. When you finish a shape early, the camera pulls back so you can watch the others.
-- EVERYONE ELSE's cutter replays the positions the server relays ("Cut"), a moment behind, so it
-- glides smoothly; bots' cuts arrive the same way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Rules = require(ReplicatedStorage.Shared.Logic.CrazyCutters)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local CrazyCutters = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local DOT_COLOR = rgb(120, 70, 45)
local DOT_DONE = rgb(255, 245, 225)
local START_COLOR = rgb(70, 200, 110)
local GOOD = rgb(70, 190, 100)
local BAD = rgb(235, 70, 60)
local PANEL = rgb(60, 36, 24)
local REPLAY_DELAY = 0.3 -- others' cutters replay this far behind, so they glide
local SEND_EVERY = 0.12
local KEY_SPEED = 5.5 -- studs/s with keys or a stick
local FOLLOW_SPEED = Rules.MAX_SPEED * 0.85 -- the cutter chases a finger this fast
local SHAPE_ICONS = {
	Star = "⭐",
	Heart = "❤️",
	Fish = "🐟",
	Ghost = "👻",
	Moon = "🌙",
	Mushroom = "🍄",
	Flower = "🌸",
}

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

type Board = {
	User: number,
	Frame: CFrame, -- the board's bottom middle; the dough's top is DoughTop above it
	Top: CFrame,
	Mine: boolean,
	Dots: { Part },
	DotAt: { Vector2 },
	Trail: { Part },
	TrailUsed: number,
	TrailFrom: Vector2,
	Samples: { { number } }, -- relayed { t, u, v } waiting to be replayed (others' boards)
	Pos: Vector2, -- the cutter's position now
	Heading: number,
	Cutter: Model?,
	TipOffset: CFrame,
	Label: TextLabel?,
	Scores: { number },
	Plate: number, -- cookies on the plate
	Done: boolean,
}

function CrazyCutters.Start(api)
	api:Mood({ Tint = rgb(255, 246, 232), Saturation = 0.14, Contrast = 0.05 })
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
	local doughTop: number = layout.DoughTop
	local effects = not State.ReducedEffects()
	local touch = api:IsTouch()

	-- Templates (the cutter, and a cookie per shape of this game).
	local templates = {}
	local function template(name: string): Model?
		if templates[name] == nil then
			templates[name] = (api:Template(name, 5) :: Model?) or false
		end
		local found = templates[name]
		return if found then found:Clone() else nil
	end

	local names = {}
	for _, participant in api:Participants() do
		names[participant.UserId] = participant.DisplayName
	end

	-- Boards ------------------------------------------------------------------------------------
	local boards: { [number]: Board } = {}
	local mine: Board? = nil
	for _, data in layout.Boards do
		local position = Vector3.new(data.P[1], data.P[2], data.P[3])
		local outward = Vector3.new(math.sin(data.Yaw), 0, math.cos(data.Yaw))
		local frame = CFrame.lookAt(position, position - outward)
		local board: Board = {
			User = data.User,
			Frame = frame,
			Top = frame * CFrame.new(0, doughTop, 0),
			Mine = data.User == me.UserId,
			Dots = {},
			DotAt = {},
			Trail = {},
			TrailUsed = 0,
			TrailFrom = Vector2.zero,
			Samples = {},
			Pos = Vector2.zero,
			Heading = 0,
			Cutter = nil,
			TipOffset = CFrame.identity,
			Label = nil,
			Scores = {},
			Plate = 0,
			Done = false,
		}
		boards[data.User] = board
		if board.Mine then
			mine = board
		end
		local cutter = template("PastryCutter")
		if cutter then
			quiet(cutter)
			local tip = cutter:FindFirstChild("Tip", true) :: BasePart?
			if tip then
				board.TipOffset = cutter:GetPivot():ToObjectSpace(CFrame.new(tip.Position))
			end
			cutter.Parent = api.World
			board.Cutter = cutter
		end
		-- Name and scores over the board's far edge.
		local anchor = part({
			Name = "BoardLabel",
			Size = Vector3.one * 0.2,
			Transparency = 1,
			CFrame = frame * CFrame.new(0, 4.5, -9.5),
			Parent = api.World,
		})
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(260, 64)
		billboard.MaxDistance = 140
		billboard.LightInfluence = 0
		billboard.Adornee = anchor
		billboard.Parent = anchor
		board.Label = UIKit.Label({
			Text = names[data.User] or "",
			Font = Theme.Fonts.Display,
			TextSize = 26,
			TextScaled = true,
			Size = UDim2.fromScale(1, 1),
			TextColor3 = if board.Mine then Theme.Colors.Yellow else Color3.new(1, 1, 1),
			Parent = billboard,
			Children = { UIKit.TextStroke(0.2) },
		})
	end

	local function at(board: Board, u: number, v: number, lift: number): Vector3
		return board.Top * Vector3.new(u, lift, -v)
	end

	local function placeCutter(board: Board)
		local cutter = board.Cutter
		if cutter then
			local spot = board.Top * CFrame.new(board.Pos.X, 0, -board.Pos.Y) * CFrame.Angles(0, board.Heading, 0)
			cutter:PivotTo(spot * board.TipOffset:Inverse())
		end
	end

	local function refreshLabel(board: Board)
		local label = board.Label
		if not label then
			return
		end
		local parts = { names[board.User] or "" }
		for _, score in board.Scores do
			local _, symbol = Rules.Grade(score)
			table.insert(parts, `{symbol}{score}`)
		end
		label.Text = table.concat(parts, "  ")
	end

	-- The current shape ---------------------------------------------------------------------------
	local round = nil
	local shape: Rules.Shape? = nil
	local tracker: Rules.Tracker? = nil
	local startMarkers = {}

	local function clearTrail(board: Board)
		for index = 1, board.TrailUsed do
			board.Trail[index].Parent = nil
		end
		board.TrailUsed = 0
	end

	local function setupShape(id: string)
		shape = Rules.Get(id)
		local current = shape :: Rules.Shape
		if not shape then
			return
		end
		tracker = Rules.Tracker(current)
		for _, marker in startMarkers do
			marker:Destroy()
		end
		table.clear(startMarkers)
		local su, sv, du, dv = Rules.PointAt(current, 0)
		for _, board in boards do
			for _, dot in board.Dots do
				dot:Destroy()
			end
			table.clear(board.Dots)
			table.clear(board.DotAt)
			table.clear(board.Samples)
			clearTrail(board)
			board.Done = false
			board.Pos = Vector2.new(su, sv)
			board.TrailFrom = board.Pos
			board.Heading = math.atan2(-du, -dv) -- the wheel rolls along the outline
			placeCutter(board)
			-- Dotted outline: closer dots on your own board.
			local spacing = if board.Mine then 0.55 else 1.1
			local size = if board.Mine then 0.3 else 0.36
			local count = math.max(8, math.floor(current.Length / spacing))
			for index = 1, count - 1 do
				local u, v = Rules.PointAt(current, current.Length * index / count)
				local dot = part({
					Name = "Dot",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.06, size, size),
					Color = DOT_COLOR,
					CFrame = CFrame.new(at(board, u, v, 0.04)) * board.Top.Rotation * CFrame.Angles(0, 0, math.rad(90)),
					Parent = api.World,
				})
				table.insert(board.Dots, dot)
				table.insert(board.DotAt, Vector2.new(u, v))
			end
			-- The start: a green disc with an arrow pointing the way round.
			local disc = part({
				Name = "Start",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.07, 0.9, 0.9),
				Color = START_COLOR,
				CFrame = CFrame.new(at(board, su, sv, 0.045)) * board.Top.Rotation * CFrame.Angles(0, 0, math.rad(90)),
				Parent = api.World,
			})
			table.insert(startMarkers, disc)
			-- The arrowhead: two wedges lying flat, mirrored about the way to go. (A wedge's triangle
			-- is in its YZ plane with its sharp corner at -Z, -Y; X is its thickness.)
			local up = board.Top.UpVector
			local forward = (at(board, su + du, sv + dv, 0) - at(board, su, sv, 0)).Unit
			local zAxis = -forward
			local head = CFrame.fromMatrix(at(board, su + du * 1.15, sv + dv * 1.15, 0.065), up, zAxis:Cross(up), zAxis)
			for _, turn in { 0, math.pi } do
				local wedge = Instance.new("WedgePart")
				wedge.Name = "StartArrow"
				wedge.Anchored = true
				wedge.CanCollide = false
				wedge.CanQuery = false
				wedge.CanTouch = false
				wedge.CastShadow = false
				wedge.Color = START_COLOR
				wedge.Material = Enum.Material.SmoothPlastic
				wedge.Size = Vector3.new(0.07, 0.38, 0.75)
				wedge.CFrame = head * CFrame.Angles(0, 0, turn) * CFrame.new(0, 0.19, 0)
				wedge.Parent = api.World
				table.insert(startMarkers, wedge)
			end
		end
	end

	-- A stretch of cut line on a board, colored by how close it is to the outline.
	local function cutTo(board: Board, position: Vector2, force: boolean)
		local from = board.TrailFrom
		local step = if board.Mine then 0.3 else 0.6
		local length = (position - from).Magnitude
		if length < step and not force then
			return
		end
		if length < 0.02 then
			return
		end
		local distance = if shape then Rules.Distance(shape, position.X, position.Y) else 0
		local index = board.TrailUsed + 1
		local segment = board.Trail[index]
		if not segment then
			segment = part({ Name = "Cut" })
			board.Trail[index] = segment
		end
		board.TrailUsed = index
		local a, b = at(board, from.X, from.Y, 0.06), at(board, position.X, position.Y, 0.06)
		segment.Size = Vector3.new(if board.Mine then 0.2 else 0.28, 0.05, length + 0.12)
		segment.CFrame = CFrame.lookAt((a + b) / 2, b, board.Top.UpVector)
		segment.Color = GOOD:Lerp(BAD, math.clamp((distance - Rules.FULL) / (Rules.ZERO - Rules.FULL), 0, 1))
		segment.Parent = api.World
		board.TrailFrom = position
		-- Dots the cutter has passed turn pale (cut).
		local r2 = Rules.COVER * Rules.COVER
		for dotIndex, dotAt in board.DotAt do
			local dot = board.Dots[dotIndex]
			if dot.Color ~= DOT_DONE and (dotAt - position).Magnitude ^ 2 <= r2 then
				dot.Color = DOT_DONE
				dot.Transparency = 0.35
			end
		end
	end

	local function moveCutter(board: Board, position: Vector2)
		local delta = position - board.Pos
		if delta.Magnitude > 0.05 then
			local target = math.atan2(-delta.X, -delta.Y)
			local diff = (target - board.Heading + math.pi) % (2 * math.pi) - math.pi
			board.Heading += diff * 0.35
		end
		board.Pos = position
		cutTo(board, position, false)
		placeCutter(board)
	end

	-- HUD ------------------------------------------------------------------------------------------
	local hud = api:TopHud()
	local hudY = api:HudY()
	local panel = UIKit.new("Frame", {
		Name = "CutPanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY),
		Size = UDim2.fromOffset(470, 66),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.2,
		Parent = hud,
		Children = { UIKit.Corner(14), UIKit.Stroke(rgb(255, 214, 150), 2, 0.3) },
	})
	local shapeLabel = UIKit.Label({
		Name = "Shape",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.fromOffset(230, 44),
		Parent = panel,
		Children = { UIKit.TextStroke(0.3) },
	})
	local timeLabel = UIKit.Label({
		Name = "Time",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		Position = UDim2.fromOffset(244, 4),
		Size = UDim2.fromOffset(90, 44),
		Parent = panel,
		Children = { UIKit.TextStroke(0.3) },
	})
	local scoreLabel = UIKit.Label({
		Name = "Score",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(334, 4),
		Size = UDim2.fromOffset(122, 44),
		TextColor3 = Theme.Colors.Yellow,
		Parent = panel,
		Children = { UIKit.TextStroke(0.3) },
	})
	local barBack = UIKit.new("Frame", {
		Name = "TimeBar",
		Position = UDim2.fromOffset(14, 50),
		Size = UDim2.new(1, -28, 0, 8),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Parent = panel,
		Children = { UIKit.Round() },
	})
	local bar = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Yellow,
		Parent = barBack,
		Children = { UIKit.Round() },
	})
	-- Big messages: the countdown, "CUT!", your grade.
	local big = UIKit.Label({
		Name = "Big",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 64,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY + 76),
		Size = UDim2.fromOffset(560, 76),
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})
	local function shout(text: string, color: Color3?)
		big.Text = text
		big.TextColor3 = color or Color3.new(1, 1, 1)
		if text ~= "" then
			UIKit.PopIn(big, 0.25)
		end
	end

	-- Camera -------------------------------------------------------------------------------------
	local camera = workspace.CurrentCamera
	local savedType, savedFov = camera.CameraType, camera.FieldOfView
	local watching = false -- pulled back to watch the others
	if mine then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 40
		api:Track(function()
			camera.CameraType = savedType
			camera.FieldOfView = savedFov
		end)
		-- The move controls go away: you stand at your board, and the screen is for cutting.
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
	end
	local function cameraTarget(board: Board): CFrame
		-- Looking down at the dough from just behind the near edge; the board sits a little low on
		-- the screen, under the HUD. Pulled back and lower when watching the others.
		local distance = if watching then 40 else 24.5
		local pitch = math.rad(if watching then 52 else 70)
		local look = board.Top * Vector3.new(0, 0, if watching then -6 else -1.2)
		local eye = board.Top * Vector3.new(0, math.sin(pitch) * distance, math.cos(pitch) * distance)
		return CFrame.lookAt(eye, look)
	end
	if mine then
		camera.CFrame = cameraTarget(mine)
	end

	-- Your cutter: input ------------------------------------------------------------------------
	local pointer: Vector2? = nil -- where the finger / mouse is, in board coordinates
	local pointerDown = false
	local activeTouch: InputObject? = nil
	local pending = {}
	local lastSend = 0
	local lastSample = 0
	local lastSamplePos = Vector2.zero
	local moved = false

	local function boardPoint(screen: Vector3): Vector2?
		if not mine then
			return nil
		end
		local ray = camera:ScreenPointToRay(screen.X, screen.Y)
		local up = mine.Top.UpVector
		local denom = ray.Direction:Dot(up)
		if math.abs(denom) < 1e-4 then
			return nil
		end
		local t = (mine.Top.Position - ray.Origin):Dot(up) / denom
		if t <= 0 then
			return nil
		end
		local hit = mine.Top:PointToObjectSpace(ray.Origin + ray.Direction * t)
		return Vector2.new(math.clamp(hit.X, -Rules.LIMIT, Rules.LIMIT), math.clamp(-hit.Z, -Rules.LIMIT, Rules.LIMIT))
	end

	if mine then
		api:Track(UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				pointerDown = true
				pointer = boardPoint(input.Position)
			elseif input.UserInputType == Enum.UserInputType.Touch and not activeTouch then
				activeTouch = input
				pointerDown = true
				pointer = boardPoint(input.Position)
			end
		end))
		api:Track(UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement or input == activeTouch then
				pointer = boardPoint(input.Position)
			end
		end))
		api:Track(UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input == activeTouch then
				pointerDown = false
				activeTouch = nil
			end
		end))
	end

	local function keyDirection(): Vector2
		local x, y = 0, 0
		if not touch then
			if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
				x += 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
				x -= 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
				y += 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
				y -= 1
			end
		end
		local direction = Vector2.new(x, y)
		if UserInputService.GamepadEnabled then
			local ok, states = pcall(UserInputService.GetGamepadState, UserInputService, Enum.UserInputType.Gamepad1)
			if ok and states then
				for _, state in states do
					if state.KeyCode == Enum.KeyCode.Thumbstick1 then
						local stick = Vector2.new(state.Position.X, state.Position.Y)
						if stick.Magnitude > 0.2 then
							direction += stick
						end
					end
				end
			end
		end
		if direction.Magnitude > 1 then
			direction = direction.Unit
		end
		return direction
	end

	local function flush(now: number, force: boolean?)
		if
			#pending > 0
			and round
			and (force or now - lastSend >= SEND_EVERY or #pending >= Rules.MAX_CHUNK * 3 - 3)
		then
			api:Action("Cut", round.Index, pending)
			pending = {}
			lastSend = now
		end
	end

	-- Shapes, scores and relays -----------------------------------------------------------------
	local hinted = false
	local function onRound()
		local data = api:SharedJSON("Round")
		if not data then
			return
		end
		local fresh = not round or round.Index ~= data.Index
		round = data
		if fresh then
			setupShape(data.Shape)
			pending = {}
			moved = false
			watching = false
			lastSample = 0
			if mine then
				lastSamplePos = mine.Pos
			end
			local icon = SHAPE_ICONS[data.Shape] or "🍪"
			shapeLabel.Text = `{icon} {string.upper(data.Shape)} {data.Index}/{data.Count}`
			scoreLabel.Text = ""
			shout("")
			if mine and not hinted then
				hinted = true
				api:Hint(
					if touch then "Drag your finger along the dots!" else "Hold the mouse and trace the dots! (or WASD)",
					hudY + 158
				)
			end
		end
		if data.Phase == "Score" then
			pointerDown = false
			if mine and tracker and not mine.Done then
				watching = true
			end
		end
	end
	api:OnShared("Round", onRound)
	onRound()

	api:OnEvent("Cut", function(userId: number, index: number, flat: { number })
		local board = boards[userId]
		if not board or board.Mine or not round or index ~= round.Index or type(flat) ~= "table" then
			return
		end
		for at = 1, #flat - 2, 3 do
			table.insert(board.Samples, { flat[at], flat[at + 1], flat[at + 2] })
		end
	end)

	-- A cookie pops out of the dough, spins, and lands on the board's plate.
	local pops = {}
	local function popCookie(board: Board)
		if not round then
			return
		end
		local cookie = template(round.Shape .. "Cookie")
		if not cookie then
			return
		end
		quiet(cookie)
		cookie.Parent = api.World
		local plateTop = board.Frame * CFrame.new(9.6, 0, 9.5) * CFrame.new(0, 2.46 * 0.8 - 0.1 + board.Plate * 0.5, 0)
		board.Plate += 1
		table.insert(pops, {
			Model = cookie,
			From = board.Top * CFrame.new(0, -0.6, 0),
			To = plateTop * CFrame.Angles(0, board.Plate * 0.7, 0),
			T0 = os.clock(),
			Scale = cookie:GetScale(),
			Board = board,
		})
		cookie:PivotTo(board.Top * CFrame.new(0, -0.6, 0))
		if effects then
			api:Effect("Sparkles", at(board, 0, 0, 1))
		end
	end

	api:OnEvent("Done", function(userId: number, index: number, score: number)
		local board = boards[userId]
		if not board or not round or index ~= round.Index or board.Done then
			return
		end
		board.Done = true
		if board.Mine then
			local grade = Rules.Grade(score)
			shout(`{grade} {score}%`, Theme.Colors.Yellow)
			api:Sound("Pickup")
			watching = true
			api:Hint("")
			task.delay(1.6, function()
				if round and round.Index == index and round.Phase == "Cut" then
					shout("Watch the others!")
				end
			end)
		end
	end)

	api:OnEvent("Scores", function(index: number, results: { [string]: number })
		if type(results) ~= "table" then
			return
		end
		for key, score in results do
			local board = boards[tonumber(key) or 0]
			if board and type(score) == "number" then
				board.Scores[index] = score
				refreshLabel(board)
				popCookie(board)
				if board.Mine then
					local grade, symbol = Rules.Grade(score)
					shout(`{symbol} {grade} {score}%`, if score >= 80 then Theme.Colors.Yellow else Color3.new(1, 1, 1))
					api:Sound(if score >= 80 then "Victory" else "Click")
				end
			end
		end
	end)

	-- Every frame --------------------------------------------------------------------------------
	local lastCount = -1
	api:RenderStep(function(dt)
		local now = api:Now()
		local clock = os.clock()
		dt = math.min(dt, 0.1)

		-- HUD: countdown, time left, your live score.
		if round then
			local cutting = round.Phase == "Cut" and now >= round.T0 and now < round.T1
			if round.Phase == "Cut" and now < round.T0 then
				local count = math.ceil(round.T0 - now)
				if count ~= lastCount then
					lastCount = count
					if count <= 3 then
						shout(tostring(count))
						api:Sound("Countdown")
					else
						shout(`{SHAPE_ICONS[round.Shape] or ""} {string.upper(round.Shape)}!`)
					end
				end
				timeLabel.Text = `⏱ {math.floor(round.T1 - round.T0 + 0.5)}`
				bar.Size = UDim2.fromScale(1, 1)
			elseif cutting then
				if lastCount ~= 0 then
					lastCount = 0
					shout("CUT!", Theme.Colors.Green)
					api:Sound("RoundStart")
					task.delay(0.8, function()
						if big.Text == "CUT!" then
							shout("")
						end
					end)
				end
				local left = round.T1 - now
				timeLabel.Text = `⏱ {math.ceil(left)}`
				local fraction = left / math.max(1, round.T1 - round.T0)
				bar.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
				bar.BackgroundColor3 = if left <= 3 then Theme.Colors.Red else Theme.Colors.Yellow
			else
				lastCount = -1
				bar.Size = UDim2.fromScale(0, 1)
				timeLabel.Text = "⏱ 0"
			end

			-- Your cutter.
			if mine and tracker and shape and cutting and not mine.Done and not tracker.Done then
				local position = mine.Pos
				local target = position
				if pointerDown and pointer then
					local delta = pointer - position
					local reach = FOLLOW_SPEED * dt
					target = if delta.Magnitude > reach then position + delta.Unit * reach else pointer
				else
					local direction = keyDirection()
					if direction.Magnitude > 0 then
						local slow = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 0.45 or 1
						target = position + direction * KEY_SPEED * slow * dt
					end
				end
				target = Vector2.new(
					math.clamp(target.X, -Rules.LIMIT, Rules.LIMIT),
					math.clamp(target.Y, -Rules.LIMIT, Rules.LIMIT)
				)
				if (target - position).Magnitude > 1e-3 then
					moveCutter(mine, target)
					if not moved then
						moved = true
						api:Hint("")
					end
				end
				if now - lastSample >= Rules.SAMPLE_GAP + 0.005 and (mine.Pos - lastSamplePos).Magnitude >= 0.05 then
					lastSample = now
					lastSamplePos = mine.Pos
					table.insert(pending, math.floor(now * 1000 + 0.5) / 1000)
					table.insert(pending, mine.Pos.X)
					table.insert(pending, mine.Pos.Y)
					tracker:Add(mine.Pos.X, mine.Pos.Y)
					scoreLabel.Text = `✂ {tracker:Score()}%`
					if tracker.Done then
						cutTo(mine, mine.Pos, true)
						flush(now, true)
					end
				end
			end
			flush(now)
		end

		-- Everyone else's cutters replay what the server relayed, a moment behind.
		local replayAt = now - REPLAY_DELAY
		for _, board in boards do
			if board.Mine then
				continue
			end
			local samples = board.Samples
			while #samples > 0 and samples[1][1] <= replayAt do
				local sample = table.remove(samples, 1) :: { number }
				moveCutter(board, Vector2.new(sample[2], sample[3]))
			end
			local nextSample = samples[1]
			if nextSample then
				-- Glide toward the next position.
				local span = nextSample[1] - replayAt
				local f = math.clamp(dt / math.max(dt, span), 0, 1)
				local position = board.Pos:Lerp(Vector2.new(nextSample[2], nextSample[3]), f)
				moveCutter(board, position)
			end
		end

		-- Cookies flying to their plates.
		for index = #pops, 1, -1 do
			local pop = pops[index]
			local t = clock - pop.T0
			local model = pop.Model
			if not model.Parent then
				table.remove(pops, index)
				continue
			end
			if t < 0.6 then
				-- Up out of the dough with a spin.
				local f = ease(t / 0.6)
				model:PivotTo(pop.From * CFrame.new(0, f * 4.2, 0) * CFrame.Angles(0, f * math.pi * 2, 0))
			elseif t < 1.5 then
				local f = ease((t - 0.6) / 0.9)
				local lifted = pop.From * CFrame.new(0, 4.2, 0)
				local position = lifted.Position:Lerp(pop.To.Position, f) + Vector3.new(0, math.sin(f * math.pi) * 3, 0)
				local rotation = lifted.Rotation:Lerp(pop.To.Rotation, f)
				model:ScaleTo(pop.Scale * (1 - 0.55 * f))
				model:PivotTo(CFrame.new(position) * rotation)
			else
				model:ScaleTo(pop.Scale * 0.45)
				model:PivotTo(pop.To)
				table.remove(pops, index)
			end
		end

		-- Camera: over your board (eased, so pulling back to watch is smooth).
		if mine then
			local target = cameraTarget(mine)
			camera.CFrame = camera.CFrame:Lerp(target, math.clamp(dt * 4, 0, 1))
		end
	end)
end

return CrazyCutters

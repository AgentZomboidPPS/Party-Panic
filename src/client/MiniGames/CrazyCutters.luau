-- Client half of Crazy Cutters: everyone's cutting board, the dotted outline, each cutter and the
-- line it has cut, the cookie that pops out onto the plate, and this player's controls and HUD.
--
-- YOUR BOARD fills the screen (a fixed camera over it). On a phone the pastry wheel moves with
-- your finger wherever you put it on the screen (it copies the finger's moves, so the finger never
-- hides the line and lifting it never makes the wheel jump); with a mouse you grab the wheel and
-- drag it (WASD / arrow keys / a gamepad stick steer it too). It cuts wherever it goes, so the cut
-- is one continuous line from the green start. Your cut and your score
-- are drawn at once from your own moves (Shared/Logic/CrazyCutters scores them exactly like the
-- server); the positions go to the server in small batches, and the server's score is the one
-- that counts. When you finish a shape early, the camera pulls back so you can watch the others.
-- EVERYONE ELSE's cutter replays the positions the server relays ("Cut"), a moment behind (as far
-- behind as their positions arrive late), so it glides smoothly; bots' cuts arrive the same way.
--
-- What you see is what the server judges: your dots and cut line are drawn at the sizes the scoring
-- uses (Rules.DOT_SIZE, CUT_WIDTH), a dot on your board turns pale exactly when the server's tracker
-- counts its stretch as cut (so "Missed a spot!" always leaves a brown dot to find), and positions
-- the server hasn't confirmed yet go again with the next batch (a lost or dropped batch would
-- otherwise leave the server judging a straight shortcut where you traced a curve).
--
-- Bug pass (owner: "it just has to work"): every batch now really carries all the positions the
-- server hasn't confirmed (a dropped batch used to wait for a resend and be overtaken by the next
-- one, so the server lost that stretch for good); a finger held on the screen from one cookie to
-- the next keeps steering; the cookie's name fits on one line ("🍄 MUSHROOM 3/3" spilled over the
-- time bar), and the bar is yellow, not the last cookie's red, during the next 3-2-1; your own
-- board's name tag no longer sits behind the round banner on phones; and someone who rejoins
-- mid-round watches instead of getting their old board under a camera they can't leave, with their
-- character stuck in the lobby and a cut that can't count.
--
-- The magnifier (owner: "For the drawing mini games it's hard to draw since your finger is in the way
-- and you can't see behind it.", then, of the ideas offered: "Let's do the magnifier bubble but only
-- for mobile."): on a touch screen, while your finger cuts, a round bubble floats by it with the board
-- round your wheel 2.25 times bigger, flat from above: the dough, your dots just as your board shows
-- them, the start, your cut and the wheel, with a ring on the point it cuts. It magnifies the wheel,
-- not the finger (the wheel copies the finger's moves, so it's often elsewhere), floats above the
-- finger and towards the middle of the screen (beside or below it when the finger is near the top),
-- clear of the cookie panel, the hints, the menu column and the jump button, and fades in and out with
-- the finger. It's plain 2D drawn from the board's own dots, stretches and wheel position each frame
-- (no 3D copy), so it costs little on a phone. PCs see nothing new. The move stick and jump button,
-- put away for the cutting, are now put away for the phone checks too (PP_NoTouchControls), and a
-- test seam lets the checks' stand-in client cut with a finger (see testFinger).

local ContextActionService = game:GetService("ContextActionService")
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
-- Heights over the dough, each layer clear of the next (no flicker): dots, the start disc, the cut
-- line (four alternating levels), the start arrow on top.
local DOT_TOP = 0.1
local START_TOP = 0.19
local CUT_LIFT = 0.275
local CUT_STEP = 0.09
local ARROW_LIFT = 0.68
local REPLAY_DELAY = 0.3 -- others' cutters replay at least this far behind, so they glide
local REPLAY_MAX = 0.8 -- ...and at most this far
local SEND_EVERY = 0.12
local RESEND_EVERY = 0.25 -- positions the server hasn't confirmed go again at least this often
local RESEND_FOR = 1.5 -- a finished cut the server hasn't confirmed this long carries on (it's missing a bit)
local LATE_SEND = 0.5 -- positions still go this long after the cut ends (the server takes them a moment)
local GRAB = 1.5 -- a mouse click this close to the wheel grabs it
local HINT_GAP = 68 -- hints sit just under the panel (clear of the start, at the outline's top)
local SHOUT_GAP = 106 -- big messages under the hints (a phone hint is one 36-tall line)
local KEY_SPEED = 5.5 -- studs/s with keys or a stick
local FOLLOW_SPEED = Rules.MAX_SPEED * 0.85 -- the cutter chases a finger this fast
-- The magnifier (phones): the board round the wheel this many times bigger than the screen shows it,
-- in a bubble this big (points) that floats this far from the finger (to its edge), above it and this
-- far over towards the middle of the screen, never coming within FINGERTIP of the finger's spot.
local LENS_ZOOM = 2.25
local LENS_SIZE = 132
local LENS_GAP = 40
local LENS_SIDE = 30
local FINGERTIP = 30
local LENS_FADE = 10 -- dots and the start fade out over this much before the bubble's rim (points)
local DOUGH_COLOR = rgb(250, 228, 190) -- the dough sheet's (World/Props/CrazyCutters)
local WHEEL_COLOR = rgb(215, 220, 230) -- the pastry wheel's steel
local WHEEL_SIZE = Vector2.new(0.25, 1.7) -- your wheel seen from above (studs): a blade up the board
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
	DotSize: number,
	DotPoints: { { number } }, -- your board: the outline points each dot stands for
	StartDisc: Part?,
	Trail: { Part },
	TrailUsed: number,
	TrailFrom: Vector2,
	TrailLen: number,
	Samples: { { number } }, -- relayed { t, u, v } waiting to be replayed (others' boards)
	Pos: Vector2, -- the cutter's position now
	Heading: number,
	Cutter: Model?,
	Marker: Part?,
	TipOffset: CFrame,
	Label: TextLabel?,
	Scores: { number },
	Plate: number, -- cookies on the plate
	Done: boolean,
	Popped: boolean, -- this shape's cookie has popped out
	Lag: number, -- how late this board's positions arrive (seconds), for the replay
	Left: boolean,
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
	-- Your board is only yours while you're in this round: someone who drops out and rejoins (same
	-- UserId, but the server no longer counts them) watches instead of tracing a cut that can't count
	-- under a camera they can't leave.
	local playing = api:Alive()

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
			Mine = playing and data.User == me.UserId,
			Dots = {},
			DotAt = {},
			DotSize = Rules.DOT_SIZE,
			DotPoints = {},
			StartDisc = nil,
			Trail = {},
			TrailUsed = 0,
			TrailFrom = Vector2.zero,
			TrailLen = 0,
			Samples = {},
			Pos = Vector2.zero,
			Heading = 0,
			Cutter = nil,
			Marker = nil,
			TipOffset = CFrame.identity,
			Label = nil,
			Scores = {},
			Plate = 0,
			Done = false,
			Popped = false,
			Lag = REPLAY_DELAY,
			Left = false,
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
		if board.Mine then
			-- A bright bead where the wheel touches the dough: exactly where you're cutting.
			board.Marker = part({
				Name = "CutPoint",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.42,
				Color = Theme.Colors.Yellow,
				Material = Enum.Material.Neon,
				Parent = api.World,
			})
		end
		-- Name and scores over the board's far edge. Not over your own: the camera over your board
		-- puts that spot right behind the round banner and the status line (on a 667x375 phone the
		-- 260x64 tag covered y 14-78, the banner and status line y 15-76), and behind your panel
		-- and hints when it pulls back; your panel shows your score, and each cookie's grade is called.
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
		billboard.Enabled = not board.Mine
		billboard.Adornee = anchor
		billboard.Parent = anchor
		board.Label = UIKit.Label({
			Text = names[data.User] or "",
			Font = Theme.Fonts.Display,
			TextSize = 26,
			TextScaled = true,
			Size = UDim2.fromScale(1, 1),
			TextColor3 = Color3.new(1, 1, 1),
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
			-- Your own cutter keeps its handle leaning away from you, so it never hides the line
			-- under the wheel; the others' swivel to follow their cut.
			local yaw = if board.Mine then math.pi else board.Heading
			local spot = board.Top * CFrame.new(board.Pos.X, 0, -board.Pos.Y) * CFrame.Angles(0, yaw, 0)
			cutter:PivotTo(spot * board.TipOffset:Inverse())
		end
		local marker = board.Marker
		if marker then
			marker.CFrame = CFrame.new(at(board, board.Pos.X, board.Pos.Y, 0.25))
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
	-- Your cut as your board draws it (each stretch's ends and colour) and the start's spot, for the
	-- magnifier.
	local myCuts: { { A: Vector2, B: Vector2, Color: Color3 } } = {}
	local shapeStart = Vector2.zero

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
		shapeStart = Vector2.new(su, sv)
		for _, board in boards do
			for _, dot in board.Dots do
				dot:Destroy()
			end
			table.clear(board.Dots)
			table.clear(board.DotAt)
			table.clear(board.DotPoints)
			table.clear(board.Samples)
			clearTrail(board)
			board.Done = false
			board.Popped = false
			board.Pos = Vector2.new(su, sv)
			board.TrailFrom = board.Pos
			board.TrailLen = 0
			board.Heading = math.atan2(-du, -dv) -- the wheel rolls along the outline
			placeCutter(board)
			-- Dotted outline: closer dots on your own board.
			local spacing = if board.Mine then 0.55 else 1.1
			local size = if board.Mine then Rules.DOT_SIZE else 0.36
			board.DotSize = size
			local count = math.max(8, math.floor(current.Length / spacing))
			for index = 1, count - 1 do
				local u, v = Rules.PointAt(current, current.Length * index / count)
				if (u - su) ^ 2 + (v - sv) ^ 2 < 0.6 ^ 2 then
					continue -- under the start disc
				end
				local dot = part({
					Name = "Dot",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(DOT_TOP, size, size),
					Color = DOT_COLOR,
					CFrame = CFrame.new(at(board, u, v, DOT_TOP / 2))
						* board.Top.Rotation
						* CFrame.Angles(0, 0, math.rad(90)),
					Parent = api.World,
				})
				table.insert(board.Dots, dot)
				table.insert(board.DotAt, Vector2.new(u, v))
			end
			if board.Mine and #board.DotAt > 0 then
				-- Each outline point the tracker scores belongs to its nearest dot.
				for _ in board.DotAt do
					table.insert(board.DotPoints, {})
				end
				for point = 1, current.N do
					local spot = Vector2.new(current.U[point], current.V[point])
					local best, nearest = math.huge, 1
					for dotIndex, dotAt in board.DotAt do
						local d = (dotAt - spot).Magnitude
						if d < best then
							best, nearest = d, dotIndex
						end
					end
					table.insert(board.DotPoints[nearest], point)
				end
			end
			-- The start: a green disc with an arrow pointing the way round.
			local disc = part({
				Name = "Start",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(START_TOP, 0.9, 0.9),
				Color = START_COLOR,
				CFrame = CFrame.new(at(board, su, sv, START_TOP / 2))
					* board.Top.Rotation
					* CFrame.Angles(0, 0, math.rad(90)),
				Transparency = if board.Left then 0.6 else 0,
				Parent = api.World,
			})
			board.StartDisc = disc
			table.insert(startMarkers, disc)
			-- The arrowhead: two wedges lying flat, mirrored about the way to go. (A wedge's triangle
			-- is in its YZ plane with its sharp corner at -Z, -Y; X is its thickness.)
			local up = board.Top.UpVector
			local forward = (at(board, su + du, sv + dv, 0) - at(board, su, sv, 0)).Unit
			local zAxis = -forward
			local head =
				CFrame.fromMatrix(at(board, su + du * 1.15, sv + dv * 1.15, ARROW_LIFT), up, zAxis:Cross(up), zAxis)
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
				wedge.Size = Vector3.new(0.1, 0.38, 0.75)
				wedge.CFrame = head * CFrame.Angles(0, 0, turn) * CFrame.new(0, 0.19, 0)
				wedge.Parent = api.World
				table.insert(startMarkers, wedge)
			end
		end
	end

	-- A stretch of cut line on a board, colored by how close it is to the outline.
	local function cutTo(board: Board, position: Vector2, force: boolean)
		local from = board.TrailFrom
		-- (Others' boards are seen from a distance: longer stretches, ~40% fewer parts for phones.)
		local step = if board.Mine then 0.3 else 1.0
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
		-- Neighbouring stretches overlap a little at the joints, so they alternate between two
		-- heights (and the second half of a lap, which meets the first at the start, uses two more).
		local half = if shape and board.TrailLen > shape.Length * 0.55 then 2 else 0
		local lift = CUT_LIFT + CUT_STEP * ((index % 2) + half)
		board.TrailLen += length
		local a, b = at(board, from.X, from.Y, lift), at(board, position.X, position.Y, lift)
		segment.Size = Vector3.new(if board.Mine then Rules.CUT_WIDTH else 0.28, 0.07, length + 0.12)
		segment.CFrame = CFrame.lookAt((a + b) / 2, b, board.Top.UpVector)
		segment.Color = GOOD:Lerp(BAD, math.clamp((distance - Rules.FULL) / (Rules.ZERO - Rules.FULL), 0, 1))
		segment.Parent = api.World
		board.TrailFrom = position
		if board.Mine then
			myCuts[index] = { A = from, B = position, Color = segment.Color }
			return -- your own dots follow your tracker (paleDots)
		end
		-- Dots the cutter has passed turn pale (cut).
		local r2 = Rules.COVER * Rules.COVER
		for dotIndex, dotAt in board.DotAt do
			local dot = board.Dots[dotIndex]
			if dot.Color ~= DOT_DONE and (dotAt - position).Magnitude ^ 2 <= r2 then
				dot.Color = DOT_DONE
				dot.Transparency = 0.35
				dot.Size = Vector3.new(DOT_TOP, board.DotSize, board.DotSize)
			end
		end
	end

	-- Your dots turn pale exactly when the tracker (the server's rule) counts all of theirs as cut.
	local function paleDots(board: Board, track: Rules.Tracker)
		for dotIndex, points in board.DotPoints do
			local dot = board.Dots[dotIndex]
			if dot.Color == DOT_DONE then
				continue
			end
			local cut = true
			for _, point in points do
				if not track.Covered[point] then
					cut = false
					break
				end
			end
			if cut then
				dot.Color = DOT_DONE
				dot.Transparency = 0.35
				dot.Size = Vector3.new(DOT_TOP, board.DotSize, board.DotSize)
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
	-- The longest name, "🍄 MUSHROOM 3/3", is 236 wide at this size: it needs the room on one line
	-- (in 230 it wrapped onto a second line over the time bar). The time, at most "⏱ 14", is 59 wide.
	local shapeLabel = UIKit.Label({
		Name = "Shape",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.fromOffset(250, 44),
		Parent = panel,
		Children = { UIKit.TextStroke(0.3) },
	})
	local timeLabel = UIKit.Label({
		Name = "Time",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		Position = UDim2.fromOffset(264, 4),
		Size = UDim2.fromOffset(70, 44),
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
		Position = UDim2.new(0.5, 0, 0, hudY + SHOUT_GAP),
		Size = UDim2.fromOffset(560, 76),
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})
	local function shout(text: string, color: Color3?)
		big.Text = text
		big.TextColor3 = color or Color3.new(1, 1, 1)
		-- Only as wide as the words, so it stays clear of the corners (phones' thumb zones).
		big.Size = UDim2.fromOffset(math.min(560, UIKit.TextWidth(text, 64, Theme.Fonts.Display) + 24), 76)
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
			camera.CameraType = if savedType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedType
			camera.FieldOfView = savedFov
		end)
		-- The move controls go away: you stand at your board, and the screen is for cutting. (The UI
		-- checks then draw no move stick or jump button either: tools/checks/ui_render.py.)
		api.Gui:SetAttribute("PP_NoTouchControls", if touch then true else nil)
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
		local distance = if watching then 40 else 26.5
		local pitch = math.rad(if watching then 52 else 70)
		local look = board.Top * Vector3.new(0, 0, if watching then -6 else -2.7)
		local eye = board.Top * Vector3.new(0, math.sin(pitch) * distance, math.cos(pitch) * distance)
		return CFrame.lookAt(eye, look)
	end
	if mine then
		camera.CFrame = cameraTarget(mine)
	end

	-- Your cutter: input ------------------------------------------------------------------------
	local pointer: Vector2? = nil -- where the wheel is steered to, in board coordinates
	local pointerDown = false
	local activeTouch: InputObject? = nil
	local dragFrom: Vector2? = nil -- touch: the finger's board point when the wheel was last at wheelFrom
	local wheelFrom = Vector2.zero
	local fingerAt: Vector2? = nil
	local fingerScreen: Vector2? = nil -- touch: the finger's spot on the screen (the magnifier floats by it)
	local testTouch: any = { Position = Vector3.zero } -- the checks' stand-in finger (the test seam below)
	local recent = {} -- your last positions, flat { t, u, v, ... } (the server skips ones it has)
	local sentUpTo = 0 -- the newest position's time sent so far
	local confirmed = 0 -- the newest position's time the server took (it relays every one it takes)
	local lastSend = 0
	local lastSample = 0
	local lastSamplePos = Vector2.zero
	local moved = false
	local hintState: string? = nil -- "Back" (go back to the start) or "Missed" (dots still to cut)
	local flashUntil = 0 -- the start disc pulses until then (a click that missed the wheel)
	local doneAt = 0 -- when this client saw the cut finish (resends until the server confirms it)

	local function boardPoint(screen: Vector3, free: boolean?): Vector2?
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
		if free then
			return Vector2.new(hit.X, -hit.Z)
		end
		return Vector2.new(math.clamp(hit.X, -Rules.LIMIT, Rules.LIMIT), math.clamp(-hit.Z, -Rules.LIMIT, Rules.LIMIT))
	end

	-- Touch: the wheel copies the finger's moves from where it is (from where it was when the
	-- finger went down), so the finger can be anywhere and lifting it never makes the wheel jump.
	-- The finger's spot is read again here, as the camera may have moved under a still finger
	-- (pulled back to watch, and in again for the next cookie).
	local function regrip()
		local held = activeTouch
		if mine and held then
			local point = if held == testTouch
				then me:GetAttribute("PP_TestFinger")
				else boardPoint(held.Position, true)
			fingerAt = if typeof(point) == "Vector2" then point else fingerAt
		end
		if mine and fingerAt then
			dragFrom = fingerAt
			wheelFrom = mine.Pos
			pointer = mine.Pos
		end
	end

	if mine then
		api:Track(UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				local point = boardPoint(input.Position)
				if point and (point - mine.Pos).Magnitude <= GRAB then
					pointerDown = true
					pointer = point
					if flashUntil > 0 then
						-- Clear the "grab it" hint (a "what's left" hint comes back with the next move).
						flashUntil = 0
						hintState = nil
						api:Hint("")
					end
				elseif round and round.Phase == "Cut" and not mine.Done then
					-- Missed the wheel: show where it is.
					flashUntil = os.clock() + 1
					api:Hint(
						if mine.TrailLen < 0.1 then "Start on the green dot!" else "Grab your cutter to carry on!",
						hudY + HINT_GAP
					)
				end
			elseif input.UserInputType == Enum.UserInputType.Touch and not activeTouch then
				local point = boardPoint(input.Position, true)
				if point then
					activeTouch = input
					pointerDown = true
					fingerAt = point
					fingerScreen = Vector2.new(input.Position.X, input.Position.Y)
					regrip()
				end
			end
		end))
		api:Track(UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				pointer = boardPoint(input.Position)
			elseif input == activeTouch then
				fingerScreen = Vector2.new(input.Position.X, input.Position.Y)
				local point = boardPoint(input.Position, true)
				if point and dragFrom then
					fingerAt = point
					pointer = wheelFrom + (point - dragFrom)
				end
			end
		end))
		api:Track(UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input == activeTouch then
				pointerDown = false
				activeTouch = nil
				dragFrom = nil
				fingerAt = nil
				fingerScreen = nil
			end
		end))
		-- Shift slows the wheel; keep it from also toggling Roblox's Shift Lock.
		local bound = pcall(function()
			ContextActionService:BindActionAtPriority("CutterSlow", function()
				return Enum.ContextActionResult.Sink
			end, false, 3000, Enum.KeyCode.LeftShift)
		end)
		if bound then
			api:Track(function()
				ContextActionService:UnbindAction("CutterSlow")
			end)
		end
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

	-- Sends the new positions (no sooner than the server takes a batch), together with every earlier
	-- one the server hasn't confirmed yet (it skips the ones it already has). When two batches
	-- arrive in one server frame the action limit drops the second; if its positions waited until
	-- they looked overdue, the next batch would get there first, and once the server has taken a
	-- newer position it can never take older ones: it would score a straight shortcut where you
	-- traced a curve (and a cut finished on your screen could stay unfinished on the server).
	local function flush(now: number, force: boolean?)
		if not round or #recent == 0 or now - lastSend < 0.04 or now > round.T1 + LATE_SEND then
			return
		end
		local fresh = 0
		local batch = {}
		for at = 1, #recent - 2, 3 do
			local t = recent[at]
			if t <= confirmed then
				continue -- the server has it
			end
			if t > sentUpTo then
				fresh += 1
			end
			table.insert(batch, t)
			table.insert(batch, recent[at + 1])
			table.insert(batch, recent[at + 2])
		end
		local due = if fresh > 0
			then force or now - lastSend >= SEND_EVERY or fresh >= Rules.MAX_CHUNK // 2
			else now - lastSend >= RESEND_EVERY
		if #batch > 0 and due then
			api:Action("Cut", round.Index, batch)
			sentUpTo = math.max(sentUpTo, batch[#batch - 2])
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
			recent = {}
			sentUpTo = 0
			confirmed = 0
			doneAt = 0
			hintState = nil
			moved = false
			watching = false
			lastSample = 0
			if mine then
				lastSamplePos = mine.Pos
			end
			local icon = SHAPE_ICONS[data.Shape] or "🍪"
			shapeLabel.Text = `{icon} {string.upper(data.Shape)} {data.Index}/{data.Count}`
			scoreLabel.Text = if mine then "✂ 0%" else ""
			shout("")
			api:Hint("")
			if mine and not hinted then
				hinted = true
				api:Hint(
					if touch then "Drag anywhere to trace the dots!" else "Grab the green dot and trace the dots!",
					hudY + HINT_GAP
				)
			end
		end
		if data.Phase == "Score" then
			-- A mouse lets go of the wheel (the next cookie starts with a fresh grab of the green
			-- dot); a finger still on the screen keeps steering, from wherever the wheel is then.
			if not activeTouch then
				pointerDown = false
			end
			if mine and tracker and not mine.Done then
				watching = true
			end
		end
	end
	api:OnShared("Round", onRound)
	onRound()

	local function onCut(userId: number, index: number, flat: { number })
		local board = boards[userId]
		if not board or not round or index ~= round.Index or type(flat) ~= "table" then
			return
		end
		if board.Mine then
			-- The server took these: they don't need sending again.
			local last = flat[#flat - 2]
			if type(last) == "number" then
				confirmed = math.max(confirmed, last + 1e-4)
			end
			return
		end
		for at = 1, #flat - 2, 3 do
			table.insert(board.Samples, { flat[at], flat[at + 1], flat[at + 2] })
		end
		-- How late this batch's oldest position arrived: replay at least that far behind (the
		-- delay creeps back down when the connection gets better).
		local late = if type(flat[1]) == "number" then api:Now() - flat[1] else 0
		board.Lag = math.clamp(math.max(board.Lag - 0.01, late + 0.1), REPLAY_DELAY, REPLAY_MAX)
	end
	-- Everyone's positions since the last relay, in one message (CrazyCutters:_flushRelay).
	api:OnEvent("Cuts", function(index: number, relay: { [string]: { number } })
		if type(relay) ~= "table" then
			return
		end
		for key, flat in relay do
			local userId = tonumber(key)
			if userId then
				onCut(userId, index, flat)
			end
		end
	end)

	-- A player left: their board stays, faded, so it doesn't look like someone stuck.
	api:OnEvent("Left", function(userId: number)
		local board = boards[userId]
		if not board or board.Left then
			return
		end
		board.Left = true
		table.clear(board.Samples)
		local cutter = board.Cutter
		if cutter then
			for _, descendant in cutter:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Transparency = 1 - (1 - descendant.Transparency) * 0.4
				end
			end
		end
		for _, dot in board.Dots do
			dot.Transparency = 0.6
		end
		if board.StartDisc then
			board.StartDisc.Transparency = 0.6
		end
		if board.Label then
			board.Label.Text = `{names[board.User] or ""} left`
			board.Label.TextTransparency = 0.4
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
		local plateTop = board.Frame * CFrame.new(11, 0, 10.5) * CFrame.new(0, 2.46 * 0.8 - 0.1 + board.Plate * 0.5, 0)
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
		board.Popped = true
		if not board.Mine then
			-- Their cutter replays a moment behind: pop the cookie as it closes the lap on screen.
			api:Track(task.delay(board.Lag, function()
				if round and round.Index == index then
					popCookie(board)
				end
			end))
		else
			popCookie(board)
			local grade, symbol = Rules.Grade(score)
			shout(`{symbol} {score}%`, Theme.Colors.Yellow)
			api:Sound("Pickup")
			watching = true
			api:Hint(`{grade} Now watch the others!`, hudY + HINT_GAP)
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
				if not board.Left then
					refreshLabel(board)
				end
				if not board.Popped and score >= 50 then
					board.Popped = true
					popCookie(board)
				end
				if board.Mine then
					local grade, symbol = Rules.Grade(score)
					shout(`{symbol} {score}%`, if score >= 80 then Theme.Colors.Yellow else Color3.new(1, 1, 1))
					api:Hint(grade, hudY + HINT_GAP)
					api:Sound(if score >= 80 then "Victory" else "Click")
				end
			end
		end
	end)

	-- The magnifier (phones) ----------------------------------------------------------------------
	-- While a finger cuts on your board, a round bubble floats by it with the board round the wheel
	-- LENS_ZOOM times bigger, flat from above: the dough, your dots as your board shows them (pale once
	-- cut, big after "Missed a spot!"), the green start, your cut in its colours and the wheel, with a
	-- yellow ring on the very point it cuts. It shows where the wheel is, not where the finger is (the
	-- wheel copies the finger's moves, so it's often somewhere else). It's drawn from the same dots,
	-- stretches and wheel position as the board, so the two always agree; stretches are cut off at its
	-- rim, and dots and the start fade out just inside it.
	local lens: Frame? = nil
	local lensEdge: Frame? = nil
	local lensWheel: Frame? = nil
	local lensStart: Frame? = nil
	local lensTail: Frame? = nil
	local lensDots: { Frame } = {}
	local lensCuts: { Frame } = {}
	local lensFades: { { Item: Instance, Key: string, Base: number } } = {} -- what fades in and out with it
	local lensShown = 0 -- how far it has faded in (0..1)
	local lensSpot: Vector2? = nil -- where it floats (its middle, in this mode's screen's points)
	local lensPlace = "Above" -- which side of the finger: "Above", "Aside", "Across" or "Below"
	local lensSide = 1 -- towards the middle of the screen from the finger: 1 right, -1 left
	local function fades(item: Instance, key: string, base: number): any
		table.insert(lensFades, { Item = item, Key = key, Base = base })
		return item
	end
	local function lensPiece(props: { [string]: any }): Frame
		props.AnchorPoint = Vector2.new(0.5, 0.5)
		props.Parent = lens
		return UIKit.new("Frame", props)
	end
	if touch and mine then
		local ring = fades(UIKit.Stroke(Color3.new(1, 1, 1), 4, 0), "Transparency", 0)
		lens = fades(
			UIKit.new("Frame", {
				Name = "Magnifier",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(LENS_SIZE, LENS_SIZE),
				BackgroundColor3 = DOUGH_COLOR,
				Visible = false,
				ZIndex = 21,
				Parent = api.Gui,
				Children = { UIKit.Round(), ring },
			}),
			"BackgroundTransparency",
			0
		)
		-- A dark line round the white ring, so it stands out on the light dough of the board under it.
		lensEdge = UIKit.new("Frame", {
			Name = "MagnifierEdge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(LENS_SIZE + 8, LENS_SIZE + 8),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 20,
			Parent = api.Gui,
			Children = { UIKit.Round(), fades(UIKit.Stroke(PANEL, 2, 0.2), "Transparency", 0.2) },
		})
		-- The wheel, a see-through steel blade (the line under it shows), and the cutting point: a ring
		-- in the board's bead yellow, open in the middle, between four little ticks.
		lensWheel = fades(
			lensPiece({
				Name = "Wheel",
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundColor3 = WHEEL_COLOR,
				ZIndex = 4,
				Children = { UIKit.Round(), fades(UIKit.Stroke(PANEL, 1, 0.5), "Transparency", 0.5) },
			}),
			"BackgroundTransparency",
			0.7
		)
		for _, tick in { Vector2.new(-11, 0), Vector2.new(11, 0), Vector2.new(0, -11), Vector2.new(0, 11) } do
			fades(
				lensPiece({
					Name = "Tick",
					Position = UDim2.new(0.5, tick.X, 0.5, tick.Y),
					Size = if tick.X ~= 0 then UDim2.fromOffset(6, 2) else UDim2.fromOffset(2, 6),
					BackgroundColor3 = PANEL,
					ZIndex = 5,
				}),
				"BackgroundTransparency",
				0
			)
		end
		lensPiece({
			Name = "CutPoint",
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
			ZIndex = 6,
			Children = { UIKit.Round(), fades(UIKit.Stroke(Theme.Colors.Yellow, 2.5, 0), "Transparency", 0) },
		})
	end

	-- Screen points a stud of your board spans by the wheel (across the board).
	local function screenPerStud(point: Vector2): number
		local board = mine :: Board
		local a = camera:WorldToViewportPoint(at(board, point.X, point.Y, 0))
		local b = camera:WorldToViewportPoint(at(board, point.X + 1, point.Y, 0))
		local per = Vector2.new(b.X - a.X, b.Y - a.Y).Magnitude
		-- (A camera that can't measure it, like the checks' stand-in client's: a small phone's.)
		return if per > 4 and per < 400 then per else 19
	end

	-- Where the bubble floats (its middle, in this mode's screen's points) for a finger at `finger`:
	-- above it and a little towards the middle of the screen (the thumb comes from below); beside it,
	-- either side, when that's too near the top; below it as a last resort. Always on the screen (the
	-- safe area), under the cookie panel and any hint under it, left of the menu column and the jump
	-- button, and never within FINGERTIP of the finger. It keeps its side until one before it in that
	-- order fits with room to spare, so it doesn't hop about.
	local function placeLens(finger: Vector2): Vector2
		local gui = api.Gui
		local origin = gui.AbsolutePosition
		local size = gui.AbsoluteSize
		local radius = LENS_SIZE / 2
		-- (A screen not laid out yet: the smallest phone's numbers.)
		local measured = size.X > 200 and size.Y > 150
		local width = if measured then size.X else 667
		local height = if measured then size.Y else 319
		local top = if measured then panel.AbsolutePosition.Y + panel.AbsoluteSize.Y - origin.Y else 60
		local right = if measured then width else width - 70
		if measured then
			local hint = hud:FindFirstChild("Hint")
			if hint and hint:IsA("TextLabel") and hint.Visible and hint.Text ~= "" then
				top = math.max(top, hint.AbsolutePosition.Y + hint.AbsoluteSize.Y - origin.Y)
			end
			local playerGui = gui.Parent
			local main = playerGui and playerGui:FindFirstChild("PartyPanicHUD")
			local menu = main and main:FindFirstChild("Menu")
			if menu and menu:IsA("GuiObject") and menu.Visible and menu.AbsoluteSize.X > 0 then
				right = math.min(right, menu.AbsolutePosition.X - origin.X)
			end
			local controls = playerGui and playerGui:FindFirstChild("TouchGui")
			local frame = controls and controls:FindFirstChild("TouchControlFrame")
			local jump = frame and frame:FindFirstChild("JumpButton")
			if
				controls
				and controls:IsA("ScreenGui")
				and controls.Enabled
				and jump
				and jump:IsA("GuiObject")
				and jump.Visible
				and jump.AbsoluteSize.X > 0
			then
				right = math.min(right, jump.AbsolutePosition.X - origin.X)
			end
		end
		local margin = 6
		local function fit(spot: Vector2): Vector2
			local lowX, lowY = radius + margin, top + radius + margin
			return Vector2.new(
				math.clamp(spot.X, lowX, math.max(lowX, right - radius - margin)),
				math.clamp(spot.Y, lowY, math.max(lowY, height - radius - margin))
			)
		end
		-- (It changes sides only once the finger is well past the middle.)
		if finger.X > width / 2 + 40 then
			lensSide = -1
		elseif finger.X < width / 2 - 40 then
			lensSide = 1
		end
		local lift = LENS_GAP + radius
		local spots = {
			Above = Vector2.new(finger.X + lensSide * LENS_SIDE, finger.Y - lift),
			Aside = Vector2.new(finger.X + lensSide * lift, finger.Y - LENS_SIDE),
			Across = Vector2.new(finger.X - lensSide * lift, finger.Y - LENS_SIDE),
			Below = Vector2.new(finger.X + lensSide * LENS_SIDE, finger.Y + lift),
		}
		local order = { "Above", "Aside", "Across", "Below" }
		local clear = radius + FINGERTIP
		local current = false
		local far, farGap = nil, -1
		for _, place in order do
			local spot = fit(spots[place])
			local gap = (spot - finger).Magnitude
			current = current or place == lensPlace
			if gap >= clear + (if current then 0 else 12) then
				lensPlace = place
				return spot
			end
			if gap > farGap then
				far, farGap = spot, gap
			end
		end
		return far :: Vector2 -- (nowhere clear on a tiny screen: as far from the finger as it gets)
	end

	-- Where a stretch of board (points a to b, studs; the wheel at `wheel`) lies in the bubble, cut
	-- off at `clip` points from its middle: its middle, length and angle, or nil if none of it is inside.
	local function lensStretch(
		a: Vector2,
		b: Vector2,
		wheel: Vector2,
		zoom: number,
		clip: number
	): (Vector2?, number, number)
		local p = Vector2.new((a.X - wheel.X) * zoom, (wheel.Y - a.Y) * zoom)
		local q = Vector2.new((b.X - wheel.X) * zoom, (wheel.Y - b.Y) * zoom)
		local length = (q - p).Magnitude
		if length < 0.5 then
			return nil, 0, 0
		end
		local unit = (q - p) / length
		-- (Each end reaches a little past its point, as the board's stretches do.)
		local over = 0.06 * zoom
		p -= unit * over
		length += 2 * over
		-- Where the line crosses the rim: p + unit * t, t from first to last.
		local along = p:Dot(unit)
		local room = along * along - (p:Dot(p) - clip * clip)
		if room <= 0 then
			return nil, 0, 0
		end
		local first = math.max(0, -along - math.sqrt(room))
		local last = math.min(length, -along + math.sqrt(room))
		if last - first < 0.5 then
			return nil, 0, 0
		end
		return p + unit * ((first + last) / 2), last - first, math.deg(math.atan2(unit.Y, unit.X))
	end

	local function lensCutPiece(): Frame
		return lensPiece({ Name = "Cut", ZIndex = 3, Children = { UIKit.Round() } })
	end

	-- Draws the bubble for this frame (`wanted`: a finger is cutting on your board).
	local function updateLens(dt: number, wanted: boolean)
		local frame, edge, board = lens, lensEdge, mine
		if not frame or not edge or not board or (not wanted and lensShown <= 0) then
			return
		end
		local step = if effects then dt / (if wanted then 0.12 else 0.18) else 1
		lensShown = math.clamp(lensShown + (if wanted then step else -step), 0, 1)
		if lensShown <= 0 then
			frame.Visible = false
			edge.Visible = false
			lensSpot = nil
			return
		end
		local finger = fingerScreen
		if finger then
			local spot = placeLens(finger - api.Gui.AbsolutePosition)
			lensSpot = if lensSpot then lensSpot:Lerp(spot, math.clamp(dt * 25, 0, 1)) else spot
		end
		local spot = lensSpot
		if not spot then
			return
		end
		frame.Position = UDim2.fromOffset(spot.X, spot.Y)
		edge.Position = frame.Position
		frame.Visible = true
		edge.Visible = true
		local alpha = lensShown
		for _, fade in lensFades do
			(fade.Item :: any)[fade.Key] = 1 - (1 - fade.Base) * alpha
		end

		local radius = LENS_SIZE / 2
		local wheel = board.Pos
		local zoom = LENS_ZOOM * screenPerStud(wheel)
		local function inLens(point: Vector2): Vector2
			return Vector2.new(radius + (point.X - wheel.X) * zoom, radius + (wheel.Y - point.Y) * zoom)
		end
		-- How much of something round of `size` at `where` is inside the rim's fade (0 gone, 1 all there).
		local function shown(where: Vector2, size: number): number
			local inside = radius - ((where - Vector2.new(radius, radius)).Magnitude + size / 2)
			return math.clamp(inside / LENS_FADE, 0, 1)
		end

		-- The dots.
		for index, dot in board.Dots do
			local where = inLens(board.DotAt[index])
			local size = dot.Size.Y * zoom
			local seen = shown(where, size)
			local view = lensDots[index]
			if seen <= 0 then
				if view and view.Visible then
					view.Visible = false
				end
				continue
			end
			if not view then
				view = lensPiece({ Name = "Dot", ZIndex = 1, Children = { UIKit.Round() } })
				lensDots[index] = view
			end
			local piece = view :: Frame
			piece.Position = UDim2.fromOffset(where.X, where.Y)
			piece.Size = UDim2.fromOffset(size, size)
			piece.BackgroundColor3 = dot.Color
			piece.BackgroundTransparency = 1 - (1 - dot.Transparency) * seen * alpha
			piece.Visible = true
		end
		for index = #board.Dots + 1, #lensDots do
			lensDots[index].Visible = false
		end

		-- The green start.
		local disc = board.StartDisc
		local where = inLens(shapeStart)
		local size = if disc then disc.Size.Y * zoom else 0
		local seen = if disc and disc.Parent then shown(where, size) else 0
		if seen > 0 and not lensStart then
			lensStart =
				lensPiece({ Name = "Start", BackgroundColor3 = START_COLOR, ZIndex = 2, Children = { UIKit.Round() } })
		end
		local start = lensStart
		if start then
			start.Visible = seen > 0
			if seen > 0 then
				start.Position = UDim2.fromOffset(where.X, where.Y)
				start.Size = UDim2.fromOffset(size, size)
				start.BackgroundTransparency = 1 - (1 - (disc :: Part).Transparency) * seen * alpha
			end
		end

		-- Your cut, and the stretch the wheel is cutting now (on the board it's under the wheel).
		local width = Rules.CUT_WIDTH * zoom
		local clip = radius - width / 2 - 1
		local used = board.TrailUsed
		for index = 1, math.max(used, #lensCuts) do
			local cut = if index <= used then myCuts[index] else nil
			local middle, length, angle = nil :: Vector2?, 0, 0
			if cut then
				middle, length, angle = lensStretch(cut.A, cut.B, wheel, zoom, clip)
			end
			local view = lensCuts[index]
			if not middle then
				if view and view.Visible then
					view.Visible = false
				end
				continue
			end
			if not view then
				view = lensCutPiece()
				lensCuts[index] = view
			end
			local piece = view :: Frame
			piece.Position = UDim2.fromOffset(radius + middle.X, radius + middle.Y)
			piece.Size = UDim2.fromOffset(length, width)
			piece.Rotation = angle
			piece.BackgroundColor3 = (cut :: any).Color
			piece.BackgroundTransparency = 1 - alpha
			piece.Visible = true
		end
		local middle, length, angle = lensStretch(board.TrailFrom, wheel, wheel, zoom, clip)
		if middle and not lensTail then
			lensTail = lensCutPiece()
		end
		local tail = lensTail
		if tail then
			tail.Visible = middle ~= nil
			if middle then
				local distance = if shape then Rules.Distance(shape, wheel.X, wheel.Y) else 0
				tail.Position = UDim2.fromOffset(radius + middle.X, radius + middle.Y)
				tail.Size = UDim2.fromOffset(length, width)
				tail.Rotation = angle
				tail.BackgroundColor3 =
					GOOD:Lerp(BAD, math.clamp((distance - Rules.FULL) / (Rules.ZERO - Rules.FULL), 0, 1))
				tail.BackgroundTransparency = 1 - alpha
			end
		end

		-- The wheel.
		local blade = lensWheel :: Frame
		blade.Size = UDim2.fromOffset(WHEEL_SIZE.X * zoom, WHEEL_SIZE.Y * zoom)
	end

	-- Test seam (a harness run only: workspace PP_Harness). The checks' stand-in client has no fingers,
	-- so its bot (tools/checks/bots/CrazyCutters.luau) puts one down with this player's attributes:
	-- PP_TestFinger, the board point under the finger, and PP_TestFingerAt, its spot on this mode's
	-- screen. It goes through the same steps as a real touch (down, moves, up), so the checks cut with
	-- it, and their phone pictures show the magnifier as a finger cutting sees it.
	local harness = touch and mine ~= nil and workspace:GetAttribute("PP_Harness") == true
	local function testFinger()
		local point = me:GetAttribute("PP_TestFinger")
		local spot = me:GetAttribute("PP_TestFingerAt")
		if typeof(point) == "Vector2" and typeof(spot) == "Vector2" then
			if activeTouch == nil then
				activeTouch = testTouch
				pointerDown = true
				fingerAt = point
				fingerScreen = spot
				regrip()
			elseif activeTouch == testTouch then
				fingerScreen = spot
				if dragFrom then
					fingerAt = point
					pointer = wheelFrom + (point - dragFrom)
				end
			end
		elseif activeTouch == testTouch then
			pointerDown = false
			activeTouch = nil
			dragFrom = nil
			fingerAt = nil
			fingerScreen = nil
		end
	end

	-- Every frame --------------------------------------------------------------------------------
	local lastCount = -1
	api:RenderStep(function(dt)
		local now = api:Now()
		local clock = os.clock()
		dt = math.min(dt, 0.1)
		if harness then
			testFinger()
		end
		local lensWanted = false -- a finger is cutting on your board: the magnifier shows

		-- HUD: countdown, time left, your live score.
		if round then
			local cutting = round.Phase == "Cut" and now >= round.T0 and now < round.T1
			lensWanted = cutting
				and fingerScreen ~= nil
				and mine ~= nil
				and not mine.Done
				and tracker ~= nil
				and not tracker.Done
			if round.Phase == "Cut" and now < round.T0 then
				local count = math.ceil(round.T0 - now)
				if count ~= lastCount then
					lastCount = count
					if count <= 3 then
						shout(tostring(count))
						api:Sound("Countdown")
					end
				end
				timeLabel.Text = `⏱ {math.floor(round.T1 - round.T0 + 0.5)}`
				bar.Size = UDim2.fromScale(1, 1)
				bar.BackgroundColor3 = Theme.Colors.Yellow -- a full bar, not the last cookie's red end
			elseif cutting then
				if lastCount ~= 0 then
					lastCount = 0
					shout("✂ CUT!", Theme.Colors.Green)
					api:Sound("RoundStart")
					task.delay(0.8, function()
						if big.Text == "✂ CUT!" then
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
			if mine and (not cutting or mine.Done) then
				regrip() -- a finger held down before CUT! starts from where the wheel is
			end
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
					local t = math.floor(now * 1000 + 0.5) / 1000
					table.insert(recent, t)
					table.insert(recent, mine.Pos.X)
					table.insert(recent, mine.Pos.Y)
					if #recent > Rules.MAX_CHUNK * 3 then
						table.move(recent, 4, #recent, 1)
						for _ = 1, 3 do
							table.remove(recent)
						end
					end
					tracker:Add(mine.Pos.X, mine.Pos.Y)
					paleDots(mine, tracker)
					scoreLabel.Text = `✂ {tracker:Score()}%`
					if tracker.Done then
						cutTo(mine, mine.Pos, true)
						flush(now, true)
						doneAt = now
					else
						-- Tell the player what's left: back to the start, or dots they skipped.
						local coverage = tracker:Coverage()
						local su, sv = shape.U[1], shape.V[1]
						local near = (mine.Pos.X - su) ^ 2 + (mine.Pos.Y - sv) ^ 2 <= (Rules.DONE_RADIUS * 1.5) ^ 2
						local state = hintState
						if coverage >= 1 then
							state = "Back"
						elseif near and coverage >= 0.5 then
							state = "Missed"
						end
						if state ~= hintState then
							hintState = state
							if state == "Back" then
								api:Hint("Back to the green dot to finish!", hudY + HINT_GAP)
							else
								api:Hint("Missed a spot! Cut the brown dots", hudY + HINT_GAP)
								-- The dots still to cut grow, so they're easy to find.
								for _, dot in mine.Dots do
									if dot.Color ~= DOT_DONE then
										local size = mine.DotSize * 2
										dot.Size = Vector3.new(DOT_TOP, size, size)
									end
								end
							end
						end
					end
				end
			end
			-- The moment the cut ends, the last positions go at once (the server only takes them
			-- for a moment after the end).
			flush(now, round.Phase ~= "Cut" or now >= round.T1)
			-- The cut is finished here but the server hasn't said so yet: flush keeps sending what
			-- it hasn't confirmed. If it still hasn't after a while, it is missing a bit of the cut
			-- (a position it turned down): let the player carry on cutting.
			if mine and tracker and tracker.Done and not mine.Done and doneAt > 0 and now - doneAt > RESEND_FOR then
				if round.Phase == "Cut" and now < round.T1 then
					tracker.Done = false
					doneAt = 0
					hintState = nil
				end
			end

			-- The start disc pulses when it's where to go next.
			local disc = if mine then mine.StartDisc else nil
			if mine and disc then
				local pulse = (hintState == "Back" and not mine.Done) or os.clock() < flashUntil
				local size = if pulse then 0.9 + 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 10)) else 0.9
				if math.abs(disc.Size.Y - size) > 1e-3 then
					disc.Size = Vector3.new(START_TOP, size, size)
				end
			end
		end

		-- Everyone else's cutters replay what the server relayed, a moment behind.
		for _, board in boards do
			if board.Mine then
				continue
			end
			local replayAt = now - board.Lag
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

		-- Camera: over your board (eased, so pulling back to watch is smooth). (A respawn puts the
		-- camera back to following the character: take it back.)
		if mine then
			if camera.CameraType ~= Enum.CameraType.Scriptable then
				camera.CameraType = Enum.CameraType.Scriptable
			end
			local target = cameraTarget(mine)
			camera.CFrame = camera.CFrame:Lerp(target, math.clamp(dt * 4, 0, 1))
		end
		updateLens(dt, lensWanted) -- (last: the wheel has moved and the camera is set for this frame)
	end)
end

return CrazyCutters

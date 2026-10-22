-- Client half of Prime Cut: every team's giant knife over its steak, this player's ◀ ▶ controls, the
-- camera over their grill, the ten-second clock, and the big reveal of each team's two pieces.
--
-- The server owns the knives ("Knives": each team's knife, and the last nudge number it took from each
-- player) and the round ("Cut": which steak, its turn, the phase, the window, and after the chop the
-- results). This player's nudges go out in small numbered batches with the time they were pressed;
-- their own knife is drawn at the server's spot plus their nudges still on the way, so it moves the
-- moment they press, and every other knife eases to the server's spot. A line on the steak shows
-- exactly where the blade will come down (seen from above at an angle, the blade itself would be a
-- little off). Nobody sees a percentage before the chop: then each team's steak shows up in the HUD
-- in its two pieces (the real steak drawn from above, clipped at the cut) with their shares.
--
-- Which team you're on (owner: "I couldnt tell what color I was on prime cut."): the camera looks
-- down at your grill, so the hood in your colour and its "★ RED" sign were off the top of the screen
-- (under the HUD on phones), and every grill looked the same from there: a steel rim and a black
-- grate over orange coals. Now the title starts with your team in its colour ("★ RED  •  STEAK 1/3
-- •  7.3"), and before GO it's the whole title ("YOU'RE ON ★ RED", after the rules card's tab says
-- the same); your card in the reveal says YOU; and the server paints your grill's rim and side
-- tables and the rug under it in your colour (MiniGames/PrimeCut).
--
-- Sweep pass (owner, of the top HUD and the team badge that floated over your grill on the steak's
-- left: "The top circled is fine. we dont need both."): the badge is gone. The HUD's title, the
-- team pills' YOU mark and the before-GO "YOU'RE ON ..." title still say which team you're on, and
-- so do your grill's colours.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local PrimeCutLogic = require(ReplicatedStorage.Shared.Logic.PrimeCut)
local Teams = require(ReplicatedStorage.Shared.Teams)

local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local PrimeCut = {}

local HOVER = 0.6 -- the edge floats this far over the steak's top while steering
local LIFT = 2.6 -- the knife rises this much before it comes down
local CHOP_RISE, CHOP_FALL = 0.16, 0.1
local REPEAT_DELAY = 0.3 -- a held button starts repeating after this long...
local REPEAT_RATE, REPEAT_FAST = 12, 20 -- ...this many nudges a second, speeding up to this
local SEND_GAP = 0.05 -- at most this often a batch goes out
local CARD_GAP = 0.32 -- the reveal shows one team's pieces after another
local FRAME_PAD = 0.8 -- studs of grill shown round a steak in a reveal picture

type Station = {
	Team: string,
	Frame: CFrame,
	Members: { number },
	Gone: boolean,
	Knife: Model?,
	X: number, -- drawn knife position
	Target: number,
	Height: number, -- drawn edge height over the grate
	Steak: Model?,
	Dropping: number?, -- when the steak started dropping in
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) * (1 - t)
end

function PrimeCut.Start(api)
	local me = api.Player
	local myId = me.UserId
	local touch = api:IsTouch()
	local hud = api:TopHud()
	local hudY = api:HudY()

	-- Layout: the grills (each team's frame: the steak's middle on the grate, the team at +Z).
	local layout = api:SharedJSON("Layout")
	local waited = 0
	while not layout and waited < 10 do
		waited += task.wait(0.1)
		layout = api:SharedJSON("Layout")
	end
	if not layout then
		return
	end
	local stations: { [string]: Station } = {}
	local order = {}
	for _, entry in layout.Stations do
		local p = entry.P
		stations[entry.T] = {
			Team = entry.T,
			Frame = CFrame.new(p[1], p[2], p[3]),
			Members = entry.M or {},
			Gone = entry.G == 1,
			X = 0,
			Target = 0,
			Height = PrimeCutLogic.HEIGHT + HOVER,
		}
		table.insert(order, entry.T)
	end
	local function myTeam(): string?
		local team = me:GetAttribute("PP_Team")
		if type(team) == "string" and stations[team] then
			return team
		end
		for _, station in stations do
			if table.find(station.Members, myId) then
				return station.Team
			end
		end
		return nil
	end
	local mine = myTeam()
	local myStation = if mine then stations[mine] else nil
	local myColor = if mine then Teams.Colors[mine] else Theme.Colors.Yellow
	api:OnShared("Layout", function()
		local fresh = api:SharedJSON("Layout")
		if not fresh then
			return
		end
		for _, entry in fresh.Stations do
			local station = stations[entry.T]
			if station then
				station.Members = entry.M or {}
				station.Gone = entry.G == 1
			end
		end
	end)

	api:Mood({ Tint = Color3.fromRGB(255, 244, 228), Saturation = 0.12, Contrast = 0.04 })

	-- Round state ------------------------------------------------------------------------------
	local cut = api:SharedJSON("Cut") or {}
	local knives = api:SharedJSON("Knives") or {}
	local outline: PrimeCutLogic.Outline = {}
	local outlineKey = ""
	local function refreshOutline()
		local key = `{cut.S}:{cut.A}`
		if cut.S and key ~= outlineKey and PrimeCutLogic.Steak(cut.S) then
			outlineKey = key
			outline = PrimeCutLogic.Place(PrimeCutLogic.Outline(cut.S), cut.A or 0)
		end
	end
	refreshOutline()

	-- My nudges: numbered batches, and the ones the server hasn't taken yet (for my knife).
	local seq = 0
	local inFlight = {} -- { { Seq, Delta } }
	local pendingDir, pendingCount, pendingAt = 0, 0, 0
	local lastSend = -math.huge

	local function serverKnife(team: string): number?
		local entry = knives.S and knives.S[team]
		return entry and entry.X
	end
	local function taken(): number
		local entry = mine and knives.S and knives.S[mine]
		local value = entry and entry.K and entry.K[tostring(myId)]
		return if type(value) == "number" then value else 0
	end
	local function steering(now: number): boolean
		return cut.Ph == "Steer"
			and type(cut.C) == "number"
			and now < cut.C
			and type(cut.O) == "number"
			and now >= cut.O
	end
	-- Where my knife is: the server's spot plus my nudges it hasn't taken yet.
	local function predicted(): number?
		local x = if mine then serverKnife(mine) else nil
		if not x then
			return nil
		end
		local ack = taken()
		local extra = 0
		for _, batch in inFlight do
			if batch.Seq > ack then
				extra += batch.Delta
			end
		end
		extra += pendingDir * pendingCount
		return math.clamp(x + extra * PrimeCutLogic.STEP, cut.Lo or -math.huge, cut.Hi or math.huge)
	end
	local function flush(now: number)
		if pendingCount <= 0 then
			return
		end
		seq += 1
		table.insert(inFlight, { Seq = seq, Delta = pendingDir * pendingCount })
		api:Action("Nudge", pendingDir, pendingCount, seq, pendingAt)
		pendingDir, pendingCount = 0, 0
		lastSend = now
	end
	local function nudge(dir: number, now: number)
		if not myStation or not steering(now) then
			return
		end
		-- Not past the rails (on screen it stops at the steak's side too).
		local x = predicted()
		if
			x and ((dir > 0 and x >= (cut.Hi or math.huge) - 1e-6) or (dir < 0 and x <= (cut.Lo or -math.huge) + 1e-6))
		then
			return
		end
		if pendingDir ~= dir then
			flush(now)
		end
		pendingDir = dir
		pendingCount += 1
		pendingAt = now
		if pendingCount >= PrimeCutLogic.MAX_BATCH then
			flush(now)
		end
	end

	-- Knives and steaks in the world -------------------------------------------------------------
	local template = api:Template("PrimeCutKnife")
	local edgeOffset = Vector3.new(0, 0, -3.7) -- the edge's middle relative to the knife's pivot
	if template then
		local blade = template:FindFirstChild("Blade", true) :: BasePart?
		if blade then
			local relative = (template :: Model):GetPivot():ToObjectSpace(blade.CFrame)
			edgeOffset = Vector3.new(relative.X, relative.Y - blade.Size.Y / 2, relative.Z)
		end
	end
	for _, team in order do
		local station = stations[team]
		if template then
			local knife = template:Clone() :: Model
			knife.Name = `Knife_{team}`
			knife.Parent = api.World
			station.Knife = knife
		end
		station.X = serverKnife(team) or cut.X0 or 0
		station.Target = station.X
	end
	if template then
		template:Destroy()
	end
	local function placeKnife(station: Station)
		local knife = station.Knife
		if knife then
			knife:PivotTo(
				station.Frame * CFrame.new(station.X - edgeOffset.X, station.Height - edgeOffset.Y, -edgeOffset.Z)
			)
		end
	end

	-- The cut line on my steak: short glowing pieces hugging its top, under the blade.
	local GUIDE_PIECES = 12
	local guide = {}
	if myStation then
		for index = 1, GUIDE_PIECES do
			guide[index] = UIKit.new("Part", {
				Name = "CutLine",
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 246, 200),
				Size = Vector3.new(0.14, 0.05, 1),
				Transparency = 1,
				Parent = api.World,
			})
		end
	end
	local guideKey = ""
	local function placeGuide(x: number, visible: boolean, color: Color3?)
		if not myStation then
			return
		end
		-- (Twelve pieces re-laid every frame cost phones for nothing while the knife sits still.)
		local key = if visible
			then `{math.floor(x * 200 + 0.5)}:{outlineKey}:{if color then color:ToHex() else ""}`
			else "hidden"
		if key == guideKey then
			return
		end
		guideKey = key
		local near, far = PrimeCutLogic.Chord(outline, x)
		if not visible or not near or not far or far - near < 0.05 then
			for _, piece in guide do
				piece.Transparency = 1
			end
			return
		end
		local length = (far - near) / GUIDE_PIECES
		for index, piece in guide do
			local z0 = near + (index - 1) * length
			local z1 = z0 + length
			local zm = (z0 + z1) / 2
			-- (sampled a little inside the ends, where the rim curves down)
			local y0 = PrimeCutLogic.TopAt(outline, Vector2.new(x, math.min(z0 + 0.06, zm)))
			local y1 = PrimeCutLogic.TopAt(outline, Vector2.new(x, math.max(z1 - 0.06, zm)))
			local a = Vector3.new(x, y0 + 0.1, z0)
			local b = Vector3.new(x, y1 + 0.1, z1)
			local middle = (a + b) / 2
			piece.Size = Vector3.new(0.16, 0.05, (b - a).Magnitude + 0.04)
			piece.CFrame = myStation.Frame * CFrame.lookAt(middle, b)
			piece.Transparency = 0
			if color then
				piece.Color = color
			end
		end
	end

	local arena = api:Arena(5)
	local function findSteaks(now: number)
		if not arena then
			return
		end
		for _, team in order do
			local station = stations[team]
			local model = arena:FindFirstChild(`Steak_{team}`) :: Model?
			if model and model ~= station.Steak then
				local first = station.Steak == nil
				station.Steak = model
				if not first then
					station.Dropping = now
					model:SetAttribute("PP_Land", model:GetPivot().Position.Y)
				end
			end
		end
	end

	-- Camera: over my steak, looking down at it from behind the knife's handle.
	-- (Only while I'm really at my grill: someone whose character never spawned is back in the lobby,
	-- and someone the server took off the team gets their camera and controls back.)
	local camera = workspace.CurrentCamera
	local shake = 0
	local claimed = false
	local savedType, savedFov = nil, nil
	local controls = nil
	local function atMyGrill(): boolean
		return myStation ~= nil and api:Alive() and table.find((myStation :: Station).Members, myId) ~= nil
	end
	local function claim(want: boolean)
		if want == claimed or not camera then
			return
		end
		claimed = want
		if want then
			savedType, savedFov = camera.CameraType, camera.FieldOfView
			camera.CameraType = Enum.CameraType.Scriptable
			camera.FieldOfView = 42
		else
			camera.CameraType = savedType or Enum.CameraType.Custom
			camera.FieldOfView = savedFov or 70
		end
		-- You stand at your grill: the move controls go away, the screen is for the knife. (The UI
		-- checks then draw no move stick or jump button either, like Skee-Ball's play screen:
		-- tools/checks/ui_render.py.)
		api.Gui:SetAttribute("PP_NoTouchControls", if want and touch then true else nil)
		pcall(function()
			if not controls then
				local scripts = me:FindFirstChild("PlayerScripts")
				local module = scripts and scripts:FindFirstChild("PlayerModule")
				if module then
					controls = (require(module :: any) :: any):GetControls()
				end
			end
			if controls then
				if want then
					controls:Disable()
				else
					controls:Enable()
				end
			end
		end)
	end
	api:Track(function()
		claim(false)
	end)
	local function cameraTarget(): CFrame
		local frame = (myStation :: Station).Frame
		local pitch = math.rad(if touch then 70 else 72)
		local distance = if touch then 25 else 27
		-- Aimed a little past the steak's middle, so it sits low on the screen, under the HUD.
		local look = frame * Vector3.new(0, 0.6, if touch then -3.6 else -2.4)
		local eye = look + Vector3.new(0, math.sin(pitch) * distance, math.cos(pitch) * distance)
		return CFrame.lookAt(eye, look)
	end
	if atMyGrill() and camera then
		claim(true)
		camera.CFrame = cameraTarget()
	end

	-- HUD ------------------------------------------------------------------------------------------
	-- The title: my team in its colour, then the steak and the clock ("★ RED  •  STEAK 1/3  •  7.3");
	-- before GO just my team, bigger ("YOU'RE ON ★ RED").
	local title = UIKit.Label({
		Name = "Steak",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextWrapped = false,
		RichText = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY),
		Size = UDim2.fromOffset(600, 40),
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})
	local myTag = if mine then `<font color="#{myColor:ToHex()}">{Teams.Label(mine)}</font>` else nil
	local titleLead = if myTag then `{myTag}  •  ` else ""
	local barBack = UIKit.new("Frame", {
		Name = "Clock",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY + 40),
		Size = UDim2.fromOffset(300, 14),
		BackgroundColor3 = Color3.fromRGB(30, 22, 50),
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = hud,
		Children = { UIKit.Round(), UIKit.Stroke(Color3.new(1, 1, 1), 2, 0.3) },
	})
	local bar = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = myColor,
		Parent = barBack,
		Children = { UIKit.Round() },
	})
	-- My crew's pushes: one chip each, with the way they're pushing.
	local chips = UIKit.new("Frame", {
		Name = "Crew",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY + 60),
		Size = UDim2.fromOffset(470, 34),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud,
		Children = {
			UIKit.List(
				Enum.FillDirection.Horizontal,
				if touch then 5 else 8,
				Enum.HorizontalAlignment.Center,
				Enum.VerticalAlignment.Center
			),
		},
	})
	local chipLabels: { [number]: TextLabel } = {}
	local function chipFor(userId: number): TextLabel
		local label = chipLabels[userId]
		if label then
			return label
		end
		label = UIKit.Label({
			Name = `Chip{userId}`,
			Text = "",
			Font = Theme.Fonts.Bold,
			TextSize = 24,
			Size = UDim2.fromOffset(if touch then 100 else 150, 32),
			BackgroundColor3 = Color3.fromRGB(30, 22, 50),
			BackgroundTransparency = 0.35,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = chips,
			Children = { UIKit.Corner(10), UIKit.TextStroke(0.3) },
		})
		chipLabels[userId] = label :: TextLabel
		return label :: TextLabel
	end
	local function nameOf(userId: number): string
		if userId == myId then
			return "YOU"
		end
		for _, participant in api:Participants() do
			if participant.UserId == userId then
				local name = participant.DisplayName
				return if #name > 10 then string.sub(name, 1, 9) .. "…" else name
			end
		end
		return "?"
	end
	local function refreshChips(now: number, show: boolean)
		chips.Visible = show and myStation ~= nil and #(myStation :: Station).Members > 1
		if not chips.Visible or not myStation then
			return
		end
		local entry = knives.S and knives.S[mine]
		local pushing = entry and entry.P or {}
		local fresh = type(knives.T) == "number" and now - knives.T < 0.45
		for userId, label in chipLabels do
			if not table.find(myStation.Members, userId) then
				label:Destroy()
				chipLabels[userId] = nil
			end
		end
		for index, userId in myStation.Members do
			local label = chipFor(userId)
			label.LayoutOrder = index
			local dir = if userId == myId
				then (if pendingDir ~= 0 or (#inFlight > 0 and now - lastSend < 0.3) then pendingDir else 0)
				else (if fresh then pushing[tostring(userId)] or 0 else 0)
			if userId == myId and dir == 0 and #inFlight > 0 and now - lastSend < 0.3 then
				dir = if inFlight[#inFlight].Delta > 0 then 1 else -1
			end
			local name = nameOf(userId)
			label.Text = if dir < 0 then `◀ {name}` elseif dir > 0 then `{name} ▶` else name
			label.TextColor3 = if dir ~= 0 then Color3.new(1, 1, 1) else Theme.Colors.TextDim
			label.BackgroundColor3 = if dir ~= 0
				then myColor:Lerp(Color3.new(0, 0, 0), 0.25)
				else Color3.fromRGB(30, 22, 50)
		end
	end
	if myStation and not touch then
		-- (One line: two covered the top of the steak.)
		api:Hint("Hold ◀ ▶ (A / D) to slide your knife: cut it 50 : 50!", hudY + 96)
	end
	local hintShown = myStation ~= nil and not touch

	-- The reveal: a card per team with its steak in two pieces and their shares.
	local cardsFrame = UIKit.new("Frame", {
		Name = "Reveal",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY + 42),
		Size = UDim2.fromOffset(612, 210),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud,
	})
	-- (Shown for a few seconds between steaks, while the move stick is off: it may cover its corner.)
	cardsFrame:SetAttribute("PP_Popup", true)
	type Card = {
		Frame: Frame,
		Team: string,
		Left: Frame,
		Right: Frame,
		Picture: Frame,
		Shares: TextLabel,
		Miss: TextLabel,
		Crown: TextLabel,
		Cut: number,
		Width: number,
		ShownAt: number,
		Opened: boolean,
	}
	local cards: { Card } = {}
	local revealOf = -1

	local function clearCards()
		for _, card in cards do
			card.Frame:Destroy()
		end
		table.clear(cards)
		cardsFrame.Visible = false
		revealOf = -1
	end

	-- One half of a team's steak drawn from above, clipped at the cut (x studs right of its middle).
	local function steakPicture(
		parent: Frame,
		team: string,
		width: number,
		height: number,
		scale: number, -- pixels per stud
		cutX: number,
		left: boolean
	)
		local cutPx = width / 2 + cutX * scale
		local clip = UIKit.new("Frame", {
			Name = if left then "Left" else "Right",
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(if left then 0 else cutPx, 0),
			Size = UDim2.fromOffset(if left then math.max(cutPx, 0) else math.max(width - cutPx, 0), height),
			Parent = parent,
		})
		local view = UIKit.new("ViewportFrame", {
			Name = "View",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(if left then 0 else -cutPx, 0),
			Size = UDim2.fromOffset(width, height),
			Ambient = Color3.fromRGB(170, 160, 150),
			LightColor = Color3.fromRGB(255, 246, 232),
			LightDirection = Vector3.new(-0.35, -1, -0.5),
			Parent = clip,
		})
		local source = arena and arena:FindFirstChild(`Steak_{team}`)
		if source then
			local copy = source:Clone() :: Model
			copy:PivotTo(CFrame.Angles(0, cut.A or 0, 0))
			copy.Parent = view
		end
		-- Straight down from high up with a narrow lens: nearly flat, so the clip edge is the cut.
		local fov = 10
		local worldH = height / scale
		local distance = (worldH / 2) / math.tan(math.rad(fov / 2)) + PrimeCutLogic.HEIGHT
		local lens = UIKit.new("Camera", {
			FieldOfView = fov,
			CFrame = CFrame.lookAt(
				Vector3.new(0, distance, 0),
				Vector3.new(0, PrimeCutLogic.HEIGHT, 0),
				Vector3.new(0, 0, -1)
			),
			Parent = view,
		})
		view.CurrentCamera = lens
		return clip
	end

	local function buildCards(results: any)
		clearCards()
		revealOf = cut.N or 0
		local shown = {}
		for _, team in order do
			if results[team] and not stations[team].Gone then
				table.insert(shown, team)
			end
		end
		local count = #shown
		if count == 0 then
			return
		end
		-- (On phones 3-4 teams go on two rows, so the cards and their text stay big.)
		local gap = 8
		local perRow = if touch and count >= 3 then 2 else count
		local rows = math.ceil(count / perRow)
		local width = math.min(if touch then 230 else 190, math.floor((612 - (perRow - 1) * gap) / perRow))
		local pictureW = width - 12
		local pictureH = math.floor(pictureW * (if rows > 1 then 0.56 else 0.66))
		local height = 34 + pictureH + 64
		cardsFrame.Size = UDim2.fromOffset(612, rows * (height + gap))
		-- The whole steak in every picture: framed from its outline as it lies on the grill.
		local reachX, reachZ = 1, 1
		for _, point in outline do
			reachX = math.max(reachX, math.abs(point.X))
			reachZ = math.max(reachZ, math.abs(point.Y))
		end
		local scale = math.min(pictureW / (2 * (reachX + FRAME_PAD)), pictureH / (2 * (reachZ + FRAME_PAD)))
		for index, team in shown do
			local result = results[team]
			local color = Teams.Colors[team] or Color3.new(1, 1, 1)
			local row = math.ceil(index / perRow)
			local inRow = math.min(perRow, count - (row - 1) * perRow)
			local column = index - (row - 1) * perRow
			local total = inRow * width + (inRow - 1) * gap
			local frame = UIKit.new("Frame", {
				Name = `Card_{team}`,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(
					306 - total / 2 + (column - 1) * (width + gap) + width / 2,
					(row - 1) * (height + gap)
				),
				Size = UDim2.fromOffset(width, height),
				BackgroundColor3 = Color3.fromRGB(32, 24, 54),
				BackgroundTransparency = 0.15,
				Visible = false,
				Parent = cardsFrame,
				Children = {
					UIKit.Corner(14),
					UIKit.Stroke(if team == mine then Color3.new(1, 1, 1) else color, if team == mine then 4 else 3, 0),
				},
			})
			UIKit.Label({
				Name = "Team",
				Text = if team == mine then `{Teams.Label(team)} (YOU)` else Teams.Label(team),
				Font = Theme.Fonts.Display,
				TextSize = 20,
				TextColor3 = color,
				TextWrapped = false,
				TextScaled = true,
				Position = UDim2.fromOffset(8, 3),
				Size = UDim2.new(1, -16, 0, 28),
				Parent = frame,
				Children = { UIKit.TextStroke(0.1) },
			})
			local picture = UIKit.new("Frame", {
				Name = "Picture",
				Position = UDim2.fromOffset(6, 34),
				Size = UDim2.fromOffset(pictureW, pictureH),
				BackgroundColor3 = Color3.fromRGB(58, 52, 60),
				BackgroundTransparency = 0.2,
				ClipsDescendants = true,
				Parent = frame,
				Children = { UIKit.Corner(10) },
			})
			local cutX = result.X or 0
			local left = steakPicture(picture, team, pictureW, pictureH, scale, cutX, true)
			local right = steakPicture(picture, team, pictureW, pictureH, scale, cutX, false)
			local leftShare, rightShare = PrimeCutLogic.Format(result.P or 50)
			local shares = UIKit.Label({
				Name = "Shares",
				Text = `{leftShare}% | {rightShare}%`,
				Font = Theme.Fonts.Display,
				TextSize = 22,
				TextScaled = true,
				TextWrapped = false,
				Position = UDim2.fromOffset(6, 36 + pictureH),
				Size = UDim2.new(1, -12, 0, 30),
				Visible = false,
				Parent = frame,
				Children = { UIKit.TextStroke(0.1) },
			})
			local off = result.O or 0
			local miss = UIKit.Label({
				Name = "Miss",
				Text = if off <= 0 then "PERFECT 50 : 50!" else `OFF BY {string.format("%.1f", off)}%`,
				Font = Theme.Fonts.Bold,
				TextSize = 18,
				TextScaled = true,
				TextWrapped = false,
				TextColor3 = if off <= 0 then Theme.Colors.Yellow else Theme.Colors.TextDim,
				Position = UDim2.fromOffset(6, 66 + pictureH),
				Size = UDim2.new(1, -12, 0, 28),
				Visible = false,
				Parent = frame,
				Children = { UIKit.TextStroke(0.2) },
			})
			local crown = UIKit.Label({
				Name = "Crown",
				Text = "👑 BEST CUT",
				Font = Theme.Fonts.Display,
				TextSize = 18,
				TextScaled = true,
				TextWrapped = false,
				TextColor3 = Color3.fromRGB(40, 26, 10),
				BackgroundColor3 = Theme.Colors.Yellow,
				BackgroundTransparency = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 34 + pictureH / 2),
				Size = UDim2.fromOffset(math.min(130, width - 16), 28),
				ZIndex = 3,
				Visible = false,
				Parent = frame,
				Children = { UIKit.Corner(10), UIKit.Stroke(Color3.new(1, 1, 1), 2, 0) },
			})
			table.insert(cards, {
				Frame = frame,
				Team = team,
				Left = left,
				Right = right,
				Picture = picture,
				Shares = shares,
				Miss = miss,
				Crown = crown,
				Cut = revealOf,
				Width = pictureW,
				ShownAt = math.huge,
				Opened = false,
			})
		end
		cardsFrame.Visible = true
	end

	-- Buttons and keys -------------------------------------------------------------------------
	local held = { [-1] = false, [1] = false }
	local heldSince = { [-1] = 0, [1] = 0 }
	local nextRepeat = { [-1] = math.huge, [1] = math.huge }
	local repeats = { [-1] = 0, [1] = 0 }
	local function press(dir: number)
		if held[dir] then
			return
		end
		local now = api:Now()
		held[dir] = true
		heldSince[dir] = now
		nextRepeat[dir] = now + REPEAT_DELAY
		repeats[dir] = 0
		if not held[-dir] then
			nudge(dir, now)
			api:Sound("Click")
		end
		if hintShown then
			hintShown = false
			task.delay(1.5, function()
				api:Hint("")
			end)
		end
	end
	local function release(dir: number)
		local was = held[dir]
		held[dir] = false
		nextRepeat[dir] = math.huge
		if was and held[-dir] then
			-- (the other button takes over from now, not from when it was pressed)
			local now = api:Now()
			heldSince[-dir] = now
			nextRepeat[-dir] = now + REPEAT_DELAY
		end
	end
	local leftButton, rightButton = nil, nil
	if myStation then
		leftButton = api:Button({ Text = "◀", Key = Enum.KeyCode.A, Color = myColor, Slot = 2 })
		rightButton = api:Button({ Text = "▶", Key = Enum.KeyCode.D, Color = myColor, Slot = 1 })
		leftButton.Pressed:Connect(function()
			press(-1)
		end)
		leftButton.Released:Connect(function()
			release(-1)
		end)
		rightButton.Pressed:Connect(function()
			press(1)
		end)
		rightButton.Released:Connect(function()
			release(1)
		end)
		-- Arrow keys and a gamepad's d-pad / bumpers work too.
		local keys = {
			[Enum.KeyCode.Left] = -1,
			[Enum.KeyCode.Right] = 1,
			[Enum.KeyCode.DPadLeft] = -1,
			[Enum.KeyCode.DPadRight] = 1,
			[Enum.KeyCode.ButtonL1] = -1,
			[Enum.KeyCode.ButtonR1] = 1,
		}
		api:Track(UserInputService.InputBegan:Connect(function(input, processed)
			local dir = keys[input.KeyCode]
			if dir and not processed and api:CanAct() then
				press(dir)
			end
		end))
		api:Track(UserInputService.InputEnded:Connect(function(input)
			local dir = keys[input.KeyCode]
			if dir then
				release(dir)
			end
		end))
	end
	local buttonsLive, buttonsShown = nil, nil
	local function setButtons(live: boolean)
		if not leftButton or not rightButton then
			return
		end
		-- (Out of the way of the reveal between steaks.)
		local phase = cut.Ph
		local shown = phase ~= "Chop" and phase ~= "Reveal" and phase ~= "Done"
		if shown ~= buttonsShown then
			buttonsShown = shown
			leftButton:SetVisible(shown)
			rightButton:SetVisible(shown)
		end
		if buttonsLive == live then
			return
		end
		buttonsLive = live
		leftButton:SetEnabled(live)
		rightButton:SetEnabled(live)
		if not live then
			release(-1)
			release(1)
		end
	end
	setButtons(false)

	-- Shared state ------------------------------------------------------------------------------
	local lastPhase = cut.Ph
	local chopAt: number? = nil
	local impactDone = false
	local lastTick = -1
	local function onCut()
		local fresh = api:SharedJSON("Cut")
		if not fresh then
			return
		end
		local previous = cut
		cut = fresh
		refreshOutline()
		if cut.N ~= previous.N then
			-- A new steak: my nudges for the old one don't count any more.
			table.clear(inFlight)
			pendingDir, pendingCount = 0, 0
			clearCards()
		end
		if cut.Ph ~= lastPhase then
			lastPhase = cut.Ph
			if cut.Ph == "Chop" or (cut.Ph == "Reveal" and not chopAt) then
				chopAt = if type(cut.C) == "number" then cut.C else api:Now()
				impactDone = false
			elseif cut.Ph == "Steer" or cut.Ph == "Ready" then
				chopAt = nil
			end
		end
	end
	api:OnShared("Cut", onCut)
	api:OnShared("Knives", function()
		knives = api:SharedJSON("Knives") or knives
		local ack = taken()
		for index = #inFlight, 1, -1 do
			if inFlight[index].Seq <= ack then
				table.remove(inFlight, index)
			end
		end
	end)
	findSteaks(api:Now())

	-- Every frame --------------------------------------------------------------------------------
	api:RenderStep(function(dt)
		local now = api:Now()
		local live = steering(now)
		setButtons(live and api:CanAct() and atMyGrill())

		-- Held buttons repeat, quicker the longer they're held; batches go out every SEND_GAP.
		for _, dir in { -1, 1 } do
			if held[dir] and not held[-dir] and live then
				local rate = if now - heldSince[dir] > 0.9 then REPEAT_FAST else REPEAT_RATE
				local guard = 0
				while now >= nextRepeat[dir] and guard < 4 do
					guard += 1
					nextRepeat[dir] += 1 / rate
					repeats[dir] += 1
					nudge(dir, math.min(nextRepeat[dir], now))
				end
				if now >= nextRepeat[dir] then
					nextRepeat[dir] = now + 1 / rate
				end
			end
		end
		if pendingCount > 0 and (now - lastSend >= SEND_GAP or not live) then
			flush(now)
		end

		findSteaks(now)

		-- Knives: mine at the server's spot plus my nudges in flight, the others eased to theirs;
		-- the chop lifts them and brings them down at the window's close.
		local phase = cut.Ph
		for _, team in order do
			local station = stations[team]
			local target = if team == mine then predicted() else serverKnife(team)
			if knives.C ~= cut.N then
				target = cut.X0 -- (a new steak: back to the start)
			end
			station.Target = target or station.Target
			local follow = if team == mine then 30 else 12
			station.X = lerp(station.X, station.Target, math.clamp(dt * follow, 0, 1))
			local hover = PrimeCutLogic.HEIGHT + HOVER
			local height = hover
			if phase == "Ready" then
				height = hover + LIFT * 0.6
			elseif chopAt and (phase == "Chop" or phase == "Reveal" or phase == "Done") then
				local t = now - chopAt
				if t < CHOP_RISE then
					height = hover + LIFT * ease(t / CHOP_RISE)
				elseif t < CHOP_RISE + CHOP_FALL then
					local f = (t - CHOP_RISE) / CHOP_FALL
					height = lerp(hover + LIFT, 0.05, f * f)
				else
					height = 0.05
				end
			end
			station.Height = lerp(
				station.Height,
				height,
				if phase == "Chop" or phase == "Reveal" then 1 else math.clamp(dt * 8, 0, 1)
			)
			placeKnife(station)

			-- A new steak drops onto the grill.
			local steak = station.Steak
			if steak and station.Dropping then
				local land = steak:GetAttribute("PP_Land")
				local t = (now - station.Dropping) / 0.35
				if type(land) == "number" and steak.Parent then
					local pivot = steak:GetPivot()
					local y = if t >= 1
						then land
						else land + 5 * (1 - ease(t)) + math.sin(math.min(t, 1) * math.pi) * 0.3
					steak:PivotTo(pivot - Vector3.new(0, pivot.Position.Y - y, 0))
				end
				if t >= 1 then
					station.Dropping = nil
					if team == mine then
						api:Sound("Boing")
					end
				end
			end
		end

		-- The impact: a shake, a puff of smoke over my steak.
		if chopAt and not impactDone and now >= chopAt + CHOP_RISE + CHOP_FALL then
			impactDone = true
			shake = 0.5
			if myStation then
				api:Effect("Poof", (myStation.Frame * CFrame.new(myStation.X, PrimeCutLogic.HEIGHT, 0)).Position)
			end
		end

		-- My cut line follows my knife while steering; after the chop it's the cut.
		if myStation then
			local showLine = phase == "Steer"
				or phase == "Wait"
				or phase == "Chop"
				or phase == "Reveal"
				or phase == "Done"
			local color = if phase == "Reveal" or phase == "Done"
				then Color3.fromRGB(70, 30, 20)
				else Color3.fromRGB(255, 246, 200)
			placeGuide(myStation.X, showLine and not myStation.Dropping, color)
		end

		-- Clock, title and crew.
		local steakText = `{titleLead}STEAK {cut.N or 1}/{cut.Of or PrimeCutLogic.CUTS}`
		title.TextSize = if myTag and phase == "Wait" then 32 else 30
		if live and type(cut.C) == "number" then
			local left = math.max(0, cut.C - now)
			title.Text = `{steakText}  •  {string.format("%.1f", left)}`
			barBack.Visible = true
			bar.Size = UDim2.fromScale(math.clamp(left / PrimeCutLogic.STEER, 0, 1), 1)
			bar.BackgroundColor3 = if left <= 3 then Theme.Colors.Red else myColor
			local whole = math.ceil(left)
			if whole <= 3 and whole ~= lastTick and whole > 0 then
				lastTick = whole
				api:Sound("Countdown")
			end
		else
			barBack.Visible = false
			lastTick = -1
			if phase == "Chop" then
				title.Text = `{steakText}  •  CHOP!`
			elseif phase == "Reveal" or phase == "Done" then
				title.Text = `{steakText}  •  THE VERDICT`
			elseif phase == "Ready" then
				title.Text = `{steakText}  •  NEXT STEAK!`
			elseif myTag then
				title.Text = `YOU'RE ON {myTag}`
			else
				title.Text = `{steakText}  •  GET READY`
			end
		end
		refreshChips(now, live or phase == "Wait" or phase == "Ready")
		if hintShown and (phase == "Chop" or phase == "Reveal" or phase == "Done") then
			hintShown = false
			api:Hint("")
		end

		-- The reveal: cards appear one after another, then the best cut is crowned.
		if (phase == "Reveal" or phase == "Done") and cut.R and revealOf ~= (cut.N or 0) then
			buildCards(cut.R)
			local start = math.max(now, (chopAt or now) + CHOP_RISE + CHOP_FALL + 0.25)
			for index, card in cards do
				card.ShownAt = start + (index - 1) * CARD_GAP
			end
		end
		for _, card in cards do
			if not card.Frame.Visible and now >= card.ShownAt then
				card.Frame.Visible = true
				UIKit.PopIn(card.Frame, 0.3)
				api:Sound("Pickup")
			end
			if card.Frame.Visible then
				-- The two pieces slide apart, then their shares show.
				local t = math.clamp((now - card.ShownAt - 0.15) / 0.35, 0, 1)
				local gap = math.floor(7 * ease(t))
				local leftSize = card.Left.Size
				card.Left.Position = UDim2.fromOffset(-gap, 0)
				card.Right.Position = UDim2.fromOffset(leftSize.X.Offset + gap, 0)
				if t >= 1 and not card.Opened then
					card.Opened = true
					card.Shares.Visible = true
					card.Miss.Visible = true
					UIKit.PopIn(card.Shares, 0.25)
				end
			end
			local crowned = type(cut.Wt) == "number" and now >= cut.Wt and cut.W and table.find(cut.W, card.Team) ~= nil
			if crowned and not card.Crown.Visible then
				card.Crown.Visible = true
				UIKit.PopIn(card.Crown, 0.35)
				if card.Team == mine and myStation then
					api:Effect(
						"Confetti",
						(myStation.Frame * CFrame.new(0, 4, 0)).Position,
						{ myColor, Theme.Colors.Yellow }
					)
				end
			end
		end

		-- Camera (a respawn puts it back to following the character: take it back).
		local here = atMyGrill()
		claim(here)
		if here and camera then
			if camera.CameraType ~= Enum.CameraType.Scriptable then
				camera.CameraType = Enum.CameraType.Scriptable
			end
			local target = cameraTarget()
			if shake > 0 then
				shake = math.max(0, shake - dt * 2.2)
				local amount = shake * shake * 0.9
				target *= CFrame.new(math.sin(now * 61) * amount, math.cos(now * 47) * amount, 0)
			end
			camera.CFrame = camera.CFrame:Lerp(target, math.clamp(dt * 6, 0, 1))
		end
	end)
end

return PrimeCut

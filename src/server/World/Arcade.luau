-- The lobby's arcade corner (owner: "Can we also add skiball to the lobby?"): four Skee-Ball
-- machines side by side on a patio of giant arcade tickets, in the plaza's north-east corner
-- between the vote stage and the winner podium, with a TODAY'S BEST board over them on
-- candy-striped posts and a path of tickets from the promenade. LobbyBuilder calls Arcade.Build
-- once the plaza's scenery is in; the game itself is Services/SkeeBallService (the server decides
-- every score) and Controllers/SkeeBallController (each player's camera, controls and balls).
--
-- The row faces the fountain, its fronts on a line FRONT_RADIUS out from the middle; the machines
-- reach a little past the plaza's edge into the lawn. Whatever of the plaza's scenery stood there
-- (a flower bed and its trees, a lamp post and its bunting, hedges, two trees of the outer ring) is
-- cleared, so nothing pokes into a machine.
--
-- Parts the game uses (tags and attributes):
--   SkeeMachine    each machine's model; SkeeIndex 1..4 (left to right as you face them),
--                  SkeeColor, and SkeeFrame (the frame the ball path's numbers are in).
--                  SkeeBallService adds its state (who's playing, score, balls).
--   SkeeScreen     a machine's score screen (clients draw on its Front face)
--   SkeeStand      where its player stands; holds the "Play SKEE-BALL" prompt
--   SkeeBestBoard  the TODAY'S BEST board (clients draw on its Front face)
--
-- Review pass (same request): the mesh's own pieces don't collide. Beach balls that roll into the
-- arcade go home after a while (BallTrap, in LobbyBuilder.BallTraps), so none sits in front of a
-- machine.
--
-- Invisible stuff (owner: "invisible stuff you can jump on and hang on in several games"): each
-- machine used to be one invisible box as tall as its marquee, a wall over the lane and the rails
-- where nothing is drawn, and a roof you could stand on 12 studs up (a jump from the vote stage's
-- speakers reaches it). Now its colliders follow the cabinet's own shape (fitColliders: the base,
-- the front, the rails along the lane and the chute on the right one, the lane and its hop, the
-- trough, the ring board, the target box's walls, the cage's roof, the back with its screen and
-- the marquee), so whatever you can stand on or bump into is something you can see; the cage's
-- roof keeps everyone out of the rings. The TODAY'S BEST board is solid the same way (its posts
-- and panel), and both stop the camera, which no longer slides inside them.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkeeBall = require(ReplicatedStorage.Shared.Logic.SkeeBall)

local Build = require(script.Parent.Build)
local MeshLibrary = require(script.Parent.MeshLibrary)

local Arcade = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Where the arcade stands (see the layout comment in LobbyBuilder: the north-east lawn).
local ANGLE = math.rad(-33) -- the row looks back at the fountain from this direction
local FRONT_RADIUS = 70 -- from the plaza's middle to the machines' fronts
local PITCH = 6 -- machine to machine
local FLOOR_TOP = 0.4 -- the tickets' top: the machines stand on it
local BOARD_Z = 13.6 -- the TODAY'S BEST board's face, over the machines' marquees
-- Each prop's pivot (the bottom center of its box) from its own origin (tools/meshgen/props/Arcade.py
-- prints them): the floor's box is centered 5.5 toward the plaza and reaches 0.6 down; the board's
-- is 0.6 behind its face; the machine's is centered.
local FLOOR_PIVOT = CFrame.new(0, -0.6, -5.5)
local BOARD_PIVOT = CFrame.new(0, 0, 0.6)
-- The cabinet's shape, besides Shared/Logic/SkeeBall's numbers (tools/meshgen/props/Arcade.py builds
-- the mesh from both): what its colliders follow.
local RAIL_RISE = 0.9 -- the rails along the lane stand this far over its floor
local CAP = 0.14 -- the gold cap on the rails and on the target box's walls
local FRONT_TOP = 2.7 -- the front panel's top and its bumper
local WALL_TOP = 6 -- the target box's walls (the cage stands on them)
local WALL_SLOPE = 1.1 -- their front edges slope up from the rails over this much
local BACK_TOP = 9.15 -- the back panel behind the backstop, up to the screen
local CHUTE_HALF = 0.48 -- the chute's rails either side of its middle
local ARCH_RISE = 1 -- the marquee's arch over its shoulders (half an ellipse as wide as the cabinet)
local ARCH_HALF = 2 -- solid this far either side of its middle (its ends are lower)
-- The TODAY'S BEST board's posts and panel (its own space: the face at z = 0, posts 0.6 behind).
local POST_X, POST_RADIUS, POST_HEIGHT = 12.6, 0.65, 19.8
local FOOT_RADIUS, FOOT_HEIGHT = 0.9, 0.7
local PANEL_SIZE, PANEL_Y, PANEL_Z = Vector3.new(24.5, 6.9, 1.26), 16, 0.37

Arcade.Count = 4
Arcade.Colors = { rgb(255, 84, 150), rgb(64, 196, 255), rgb(156, 108, 255), rgb(255, 150, 60) }

-- The arcade's frame: on the ground under the middle of the machines' front line, looking back at
-- the plaza (-Z toward the fountain, +X to the left of a player facing the machines).
function Arcade.Frame(): CFrame
	local outward = Vector3.new(math.cos(ANGLE), 0, math.sin(ANGLE))
	local front = outward * FRONT_RADIUS
	return CFrame.lookAt(front, front - outward)
end

-- Machine `index` (1..Count, left to right for a player facing them): its pivot, with the prop's
-- own axes (its player stands on its -Z side).
function Arcade.MachineFrame(index: number): CFrame
	return Arcade.Frame() * CFrame.new((2.5 - index) * PITCH, FLOOR_TOP, -SkeeBall.FRONT_Z)
end

-- Where beach balls may not stay (BeachBalls sends them home): round the patio, in front of the
-- machines included.
function Arcade.BallTrap(): { Center: Vector3, Radius: number }
	return { Center = Arcade.Frame():PointToWorldSpace(Vector3.new(0, 0, 5.9)), Radius = 16 }
end

-- The arcade's footprint in its own frame: the patio, and the ticket path to the promenade.
local FOOTPRINT = {
	{ X = 13.5, Z0 = -4.8, Z1 = 16.6 },
	{ X = 4, Z0 = -27.5, Z1 = -4.5 },
}

-- Whether a prop whose bounding box is `box` / `size` (world) would poke into the arcade.
local function inFootprint(frame: CFrame, box: CFrame, size: Vector3, slack: number): boolean
	local position = frame:PointToObjectSpace(box.Position)
	local reach = math.max(size.X, size.Z) / 2 * slack
	for _, area in FOOTPRINT do
		if math.abs(position.X) < area.X + reach and position.Z > area.Z0 - reach and position.Z < area.Z1 + reach then
			return true
		end
	end
	return false
end

-- Clears the plaza's scenery out of the arcade's way: trees, bushes, flower beds and lamp posts
-- that would poke into it, and any bunting hung from a lamp post that goes.
local function clearSite(root: Instance, frame: CFrame)
	local removed: { Vector3 } = {}
	local scenery = { Tree = 0.7, Bush = 0.8, LobbyFlowerBed = 0.9, LampPost = 1 }
	for _, model in root:GetDescendants() do
		if not model:IsA("Model") then
			continue
		end
		local slack = scenery[model.Name]
		if not slack then
			continue
		end
		local box, size = model:GetBoundingBox()
		if inFootprint(frame, box, size, slack) then
			if model.Name == "LampPost" then
				table.insert(removed, model:GetPivot().Position)
			end
			model:Destroy()
		end
	end
	for _, model in root:GetDescendants() do
		if not model:IsA("Model") or model.Name ~= "LobbyBunting" then
			continue
		end
		local box, size = model:GetBoundingBox()
		local pivot = model:GetPivot()
		local reach = size.X / 2
		local ends = { pivot * CFrame.new(-reach, 0, 0), pivot * CFrame.new(reach, 0, 0) }
		local hung = false
		for _, lamp in removed do
			for _, point in ends do
				if (Vector3.new(point.X, 0, point.Z) - Vector3.new(lamp.X, 0, lamp.Z)).Magnitude < 2 then
					hung = true
				end
			end
		end
		if hung or inFootprint(frame, box, size, 0.5) then
			model:Destroy()
		end
	end
end

-- The numbers on the ring board (10 to 50 either side of each ring's hole, 100 by the cups), on a
-- see-through part lying on the board.
local function ringLabels(machine: Model, frame: CFrame)
	local half, length = SkeeBall.BOARD_HALF, SkeeBall.BOARD_LEN
	local _, y, s = SkeeBall.BoardPoint(0, length / 2)
	local x, _, z = SkeeBall.ToMachine(0, y, s)
	local normal = Vector3.new(0, SkeeBall.BOARD_COS, -SkeeBall.BOARD_SIN)
	local up = Vector3.new(0, SkeeBall.BOARD_SIN, SkeeBall.BOARD_COS)
	local part = Build.Decor({
		Name = "RingNumbers",
		Size = Vector3.new(half * 2, length, 0.02),
		CFrame = frame * CFrame.fromMatrix(Vector3.new(x, y, z) + normal * 0.075, Vector3.xAxis, up),
		Transparency = 1,
		Parent = machine,
	})
	local pixels = 60
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Numbers"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixels
	gui.LightInfluence = 0.3
	gui.MaxDistance = 90
	gui.Parent = part
	local function label(text: string, u: number, w: number, size: number)
		local textLabel = Instance.new("TextLabel")
		textLabel.BackgroundTransparency = 1
		textLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		textLabel.Position = UDim2.fromOffset((u + half) * pixels, (length - w) * pixels)
		textLabel.Size = UDim2.fromOffset(size * 2.2 * pixels, size * pixels)
		textLabel.Font = Enum.Font.LuckiestGuy
		textLabel.TextScaled = true
		textLabel.Text = text
		textLabel.TextColor3 = Color3.new(1, 1, 1)
		textLabel.TextStrokeTransparency = 0.2
		textLabel.TextStrokeColor3 = rgb(30, 20, 60)
		textLabel.Parent = gui
	end
	local inner = 0
	for index, ring in SkeeBall.RINGS do
		local pocket = SkeeBall.Pockets[tostring(ring.Points)]
		if index == 1 then
			label("50", 0, pocket.W + 0.21, 0.2)
		else
			-- Either side of the hole, a little way round the ring's channel.
			local radius = (inner + ring.R) / 2
			for _, side in { -1, 1 } do
				local angle = math.rad(-90 + side * 38)
				label(tostring(ring.Points), math.cos(angle) * radius, SkeeBall.RING_W + math.sin(angle) * radius, 0.19)
			end
		end
		inner = ring.R
	end
	for _, side in { -1, 1 } do
		label("100", side * SkeeBall.CUP_U, SkeeBall.CUP_W - SkeeBall.CUP_R - 0.2, 0.2)
	end
end

-- The SKEE-BALL lettering on a machine's marquee (bright on the sign's dark face).
local function marqueeText(machine: Model, frame: CFrame, color: Color3)
	local part = Build.Decor({
		Name = "MarqueeText",
		Size = Vector3.new(SkeeBall.SIGN_W, SkeeBall.SIGN_H, 0.02),
		CFrame = frame * CFrame.new(0, SkeeBall.SIGN_Y, SkeeBall.SIGN_Z - 0.08),
		Transparency = 1,
		Parent = machine,
	})
	local text = Build.SurfaceText(part, Enum.NormalId.Front, "SKEE-BALL", {
		PixelsPerStud = 48,
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 1,
		Padding = 0.08,
		Brightness = 1.6,
		MaxDistance = 300,
	})
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(255, 236, 120)),
		ColorSequenceKeypoint.new(0.5, color:Lerp(Color3.new(1, 1, 1), 0.35)),
		ColorSequenceKeypoint.new(1, rgb(255, 236, 120)),
	})
	gradient.Parent = text
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgb(30, 14, 60)
	stroke.Thickness = 3
	stroke.Parent = text
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 230, 190)
	light.Range = 9
	light.Brightness = 0.9
	light.Shadows = false
	light.Parent = part
end

-- An invisible solid piece, x0..x1 by y0..y1 by z0..z1 in `frame`; a wedge rises toward +z (its
-- tall face at z1).
local function solid(parent: Instance, frame: CFrame, name: string, wedge: boolean, bounds: { number })
	local x0, x1, y0, y1, z0, z1 = table.unpack(bounds)
	local props = {
		Name = name,
		Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		CFrame = frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		Transparency = 1,
		CastShadow = false,
		CanTouch = false,
		Parent = parent,
	}
	if wedge then
		Build.Wedge(props)
	else
		Build.Part(props)
	end
end

-- What bodies bump into at a machine: its cabinet's own shape (the mesh doesn't collide), in the
-- machine's frame (x across, y up from its base, its player's side at -z).
local function fitColliders(machine: Model, frame: CFrame)
	local holder = Build.Model("Colliders", machine)
	local function box(name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number)
		solid(holder, frame, name, false, { x0, x1, y0, y1, z0, z1 })
	end
	-- A top that slopes up from (z0, y0) to (z1, y1): a block under a wedge, upright at both ends.
	local function ramp(name: string, x0: number, x1: number, z0: number, y0: number, z1: number, y1: number)
		solid(holder, frame, name, false, { x0, x1, 0, y0, z0, z1 })
		solid(holder, frame, name .. "Slope", true, { x0, x1, y0, y1, z0, z1 })
	end
	local function z(s: number): number
		return SkeeBall.RELEASE_Z + s
	end
	local half, front, back = SkeeBall.HALF_WIDTH, SkeeBall.FRONT_Z, -SkeeBall.FRONT_Z
	local side = half - 0.1 -- the cabinet's side faces (the base sticks out a little further)
	local lane, inner = SkeeBall.LANE_HALF, SkeeBall.BOARD_HALF + 0.02 -- the lane's and the target box's insides
	local lip, boardZ = z(SkeeBall.LIP_S), z(SkeeBall.BOARD_S)
	local boardTopZ = boardZ + SkeeBall.BOARD_LEN * SkeeBall.BOARD_COS
	local boardTopY = SkeeBall.BOARD_Y + SkeeBall.BOARD_LEN * SkeeBall.BOARD_SIN
	local backstop = z(SkeeBall.BACK_S)
	-- The rails' gold cap climbs with the lane.
	local function railTop(at: number): number
		return SkeeBall.LANE_Y + RAIL_RISE + CAP + (at - SkeeBall.RELEASE_Z) * SkeeBall.LANE_RISE
	end

	box("Base", -half, half, 0, 0.32, front, back)
	box("Front", -side, side, 0, FRONT_TOP, front + 0.2, z(SkeeBall.LANE_START))
	for _, sign in { 1, -1 } do
		local tag = if sign > 0 then "L" else "R"
		-- The rail along the lane, and the target box's wall with its sloped front edge.
		local x0, x1 = math.min(sign * lane, sign * (side + 0.08)), math.max(sign * lane, sign * (side + 0.08))
		ramp(`Rail{tag}`, x0, x1, front + 0.05, railTop(front + 0.05), lip, railTop(lip))
		local w0, w1 = math.min(sign * inner, sign * (side + 0.08)), math.max(sign * inner, sign * (side + 0.08))
		ramp(`WallFront{tag}`, w0, w1, lip, railTop(lip), lip + WALL_SLOPE, WALL_TOP + CAP)
		box(`Wall{tag}`, w0, w1, 0, WALL_TOP + CAP, lip + WALL_SLOPE, back - 0.05)
	end
	-- The chute on the right-hand rail: halfway between the tops of its two rails and the cap
	-- between them, where the balls wait.
	local lastZ = SkeeBall.CHUTE_Z + (SkeeBall.BALLS - 1) * SkeeBall.CHUTE_STEP + 0.55
	local function chuteTop(at: number): number
		return SkeeBall.CHUTE_Y + (at - SkeeBall.CHUTE_Z) * SkeeBall.CHUTE_RISE - 0.15
	end
	ramp("Chute", SkeeBall.CHUTE_X - CHUTE_HALF, -lane, front + 0.05, chuteTop(front + 0.05), lastZ, chuteTop(lastZ))
	-- The lane and its hop, the trough behind the hop and the ring board.
	local laneStart = z(SkeeBall.LANE_START)
	ramp(
		"Lane",
		-lane,
		lane,
		laneStart,
		SkeeBall.FloorY(SkeeBall.LANE_START),
		z(SkeeBall.HOP_S),
		SkeeBall.FloorY(SkeeBall.HOP_S)
	)
	ramp("Hop", -lane, lane, z(SkeeBall.HOP_S), SkeeBall.FloorY(SkeeBall.HOP_S), lip, SkeeBall.LIP_Y)
	box("Trough", -inner, inner, 0, SkeeBall.TROUGH_Y, lip, boardZ)
	ramp("Board", -inner, inner, boardZ, SkeeBall.BOARD_Y, boardTopZ, boardTopY)
	-- The cage's roof over the rings (nobody fits under it), the back with the score screen's bezel,
	-- and the marquee up to its shoulders with the middle of its arch.
	box(
		"CageRoof",
		-inner - 0.43,
		inner + 0.43,
		SkeeBall.TOP_Y - 0.1,
		SkeeBall.TOP_Y + 0.12,
		lip + 1.16,
		backstop + 0.1
	)
	box("Back", -side, side, 0, BACK_TOP, backstop, back - 0.1)
	local screenTop = SkeeBall.SCREEN_Y + SkeeBall.SCREEN_H / 2 + 0.22
	local bezel = SkeeBall.SCREEN_W / 2 + 0.25
	box(
		"Bezel",
		-bezel,
		bezel,
		SkeeBall.SCREEN_Y - SkeeBall.SCREEN_H / 2 - 0.22,
		screenTop,
		SkeeBall.SCREEN_Z + 0.05,
		back - 0.1
	)
	local shoulder = SkeeBall.SIGN_Y + SkeeBall.SIGN_H / 2 - 0.15
	local arch = half - 0.05
	box("Marquee", -arch, arch, screenTop, shoulder, SkeeBall.SIGN_Z - 0.06, back - 0.1)
	local archTop = shoulder + ARCH_RISE * math.sqrt(1 - (ARCH_HALF / arch) ^ 2)
	box("Arch", -ARCH_HALF, ARCH_HALF, shoulder, archTop, SkeeBall.SIGN_Z - 0.06, back - 0.1)
end

local function buildMachine(parent: Instance, index: number): Model
	local frame = Arcade.MachineFrame(index)
	local color = Arcade.Colors[index]
	local machine = MeshLibrary.Get("ArcadeSkeeMachine", {
		Colors = { Cabinet = color },
		CFrame = frame,
		Parent = parent,
	})
	machine:SetAttribute("SkeeIndex", index)
	machine:SetAttribute("SkeeColor", color)
	machine:SetAttribute("SkeeFrame", frame) -- the frame Shared/Logic/SkeeBall's numbers are in
	fitColliders(machine, frame)

	-- The score screen in the bezel above the cage (clients draw on it).
	local screen = Build.Decor({
		Name = "Screen",
		Size = Vector3.new(SkeeBall.SCREEN_W, SkeeBall.SCREEN_H, 0.05),
		CFrame = frame * CFrame.new(0, SkeeBall.SCREEN_Y, SkeeBall.SCREEN_Z + 0.015),
		Color = rgb(14, 10, 30),
		Parent = machine,
	})
	screen:SetAttribute("SkeeIndex", index)
	CollectionService:AddTag(screen, "SkeeScreen")
	marqueeText(machine, frame, color)
	ringLabels(machine, frame)

	-- Where its player stands, with the prompt to play.
	local stand = Build.Decor({
		Name = "Stand",
		Size = Vector3.new(3, 5, 2),
		CFrame = frame * CFrame.new(0, 2.5, SkeeBall.STAND_Z),
		Transparency = 1,
		Parent = machine,
	})
	stand:SetAttribute("SkeeIndex", index)
	CollectionService:AddTag(stand, "SkeeStand")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlayPrompt"
	prompt.ActionText = "Play SKEE-BALL"
	prompt.ObjectText = "Arcade"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand

	CollectionService:AddTag(machine, "SkeeMachine")
	return machine
end

-- The TODAY'S BEST board's screen (clients draw on its Front face, toward the plaza).
local function buildBoard(parent: Instance, frame: CFrame)
	local model = MeshLibrary.Get("ArcadeBestBoard", {
		CFrame = frame * CFrame.new(0, FLOOR_TOP, BOARD_Z) * BOARD_PIVOT,
		Parent = parent,
	})
	-- What bodies bump into (the mesh doesn't collide): its two posts on their feet, and the panel.
	local colliders = Build.Model("Colliders", model)
	local face = frame * CFrame.new(0, FLOOR_TOP, BOARD_Z)
	for _, x in { -POST_X, POST_X } do
		for _, piece in
			{
				{ Name = "Post", Radius = POST_RADIUS, Height = POST_HEIGHT },
				{ Name = "Foot", Radius = FOOT_RADIUS, Height = FOOT_HEIGHT },
			}
		do
			Build.Part({
				Name = piece.Name,
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(piece.Height, piece.Radius * 2, piece.Radius * 2),
				CFrame = face
					* CFrame.new(x, piece.Height / 2, BOARD_PIVOT.Position.Z)
					* CFrame.Angles(0, 0, math.rad(90)),
				Transparency = 1,
				CastShadow = false,
				CanTouch = false,
				Parent = colliders,
			})
		end
	end
	solid(colliders, face, "Panel", false, {
		-PANEL_SIZE.X / 2,
		PANEL_SIZE.X / 2,
		PANEL_Y - PANEL_SIZE.Y / 2,
		PANEL_Y + PANEL_SIZE.Y / 2,
		PANEL_Z - PANEL_SIZE.Z / 2,
		PANEL_Z + PANEL_SIZE.Z / 2,
	})
	local screen = Build.Decor({
		Name = "BestBoard",
		Size = Vector3.new(23, 5.6, 0.1),
		CFrame = frame * CFrame.new(0, FLOOR_TOP + 16, BOARD_Z - 0.02),
		Color = rgb(40, 28, 90),
		Parent = parent,
	})
	CollectionService:AddTag(screen, "SkeeBestBoard")
	return screen
end

-- Builds the arcade into the lobby's model (after its scenery, which it clears out of the way).
function Arcade.Build(root: Model): Model
	local frame = Arcade.Frame()
	clearSite(root, frame)
	local arcade = Build.Model("Arcade", root)
	MeshLibrary.Get("ArcadeTicketFloor", { CFrame = frame * FLOOR_PIVOT, Parent = arcade })
	-- What feet land on: flat invisible floors at the grout's height (0.3) under the patio's
	-- tickets and the path's (the floor mesh doesn't collide).
	local colliders = Build.Model("Colliders", arcade)
	for _, floor in
		{
			{ Name = "PatioFloor", Size = Vector3.new(24.8, 1, 19.3), At = Vector3.new(0, -0.2, 5.75) },
			{ Name = "PathFloor", Size = Vector3.new(7.2, 1, 23.1), At = Vector3.new(0, -0.2, -15.45) },
		}
	do
		Build.Part({
			Name = floor.Name,
			Size = floor.Size,
			CFrame = frame * CFrame.new(floor.At),
			Transparency = 1,
			CastShadow = false,
			Parent = colliders,
		})
	end
	for index = 1, Arcade.Count do
		buildMachine(arcade, index)
	end
	buildBoard(arcade, frame)

	-- The ball the clients roll: a template they copy (in ReplicatedStorage, where nothing renders).
	local assets = ReplicatedStorage:FindFirstChild("ArcadeAssets") or Instance.new("Folder")
	assets.Name = "ArcadeAssets"
	assets.Parent = ReplicatedStorage
	local ball = MeshLibrary.Get("ArcadeSkeeBall")
	ball.Name = "SkeeBall"
	for _, part in ball:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
	end
	ball.Parent = assets
	return arcade
end

return Arcade

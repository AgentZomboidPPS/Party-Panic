-- The Hall of Fame by the winner podium: last week's top three as gold, silver and bronze statues of
-- their own avatars on marble plinths, and this week's top-10 board behind them under a HALL OF FAME
-- sign. The owner, asked "If you could do 5 things to keep players addicted what would you do?", got
-- "Weekly leaderboard and Hall of Fame statues of last week's top three" as one of them, then said:
-- "Can you work on all of that? this wont mess with what the other workers are working on right?".
--
-- Where: the lawn between the winner podium and the shooting gallery (east-south-east), facing the
-- fountain, with the garden's flower bed in front of it and the hedge behind. The balloons of the
-- podium and of the gallery stand either side of its front. Whatever of the plaza's scenery stood
-- in its spot (two trees, two bushes, the bunting across it) is cleared, like the Skee-Ball arcade
-- clears its own; the flower bed, the lamps and the hedge stay.
--
-- What it's made of (frame space: the middle plinth's foot at the origin, -Z toward the fountain,
-- +X toward the podium; 2nd place stands on the podium's side, as on the podium):
--   * a low dais, three plinths (1st in the middle and highest) with a metal cap and a name plate;
--   * a statue on each (Players:CreateHumanoidModelFromUserId, recoloured gold, silver or bronze,
--     posed, anchored and walked through: CanCollide, CanQuery and CanTouch off), or a see-through
--     stand-in reading "YOUR STATUE HERE?" while that place is empty (no last week yet). A statue
--     whose avatar can't be loaded is a metal stand-in of the same pose: the place never looks
--     empty when someone earned it;
--   * a name tag over each (name and points, readable from the plaza);
--   * the board (tag WeeklyBoard): each client draws this week's top 10, its own line and the time
--     to the reset on its Front face (Controllers/HallOfFameController).
-- Everything you can bump into is something you can see: the dais, plinths, posts and board are
-- solid, the statues, stand-ins and tags are not.
--
-- LobbyBuilder calls HallOfFame.Build once the plaza's scenery is in; Services/LeaderboardService
-- calls HallOfFame.SetStatues with last week's top three whenever it learns them.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Build = require(script.Parent.Build)
local Shapes = require(script.Parent.Shapes)

local HallOfFame = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Where it stands (see the top): the middle plinth this far out from the plaza's middle, at this
-- angle (radians, from +X toward +Z), looking back at the fountain.
local ANGLE = math.rad(21)
local RADIUS = 67.5
local SPACING = 4.6 -- plinth to plinth
local DAIS = Vector3.new(14.6, 0.4, 6.4) -- the floor under the plinths (its middle 0.4 behind them)
local BOARD_Z = 6.6 -- the board's face, behind the plinths
local BOARD_SIZE = Vector2.new(14.4, 11.2) -- the screen inside its gold bezel
local BOARD_Y = 19 -- the screen's middle (its bottom clears the statues' raised arms and tags)
local POST_X = 8.7 -- the board's two posts, either side of the bezel
local PLATE = Vector2.new(3.2, 1.45) -- the name plates, all at one height
local PLATE_Y = 1.3

local SIGN_FONT = Enum.Font.LuckiestGuy
local MARBLE = rgb(244, 238, 228)
local DARK = rgb(52, 36, 104)

type Look = { Color: Color3, Material: Enum.Material, Reflectance: number }

-- Each place: where its plinth stands (frame X), how tall and wide it is, the statue's metal, height
-- (feet to the top of the head: every avatar is scaled to it, so a tiny one still shows and a giant
-- one fits under the board) and pose, and its medal.
type PlaceSpec = {
	Place: number,
	X: number,
	Height: number,
	Width: number,
	Metal: Look,
	Tall: number,
	Pose: string,
	Medal: string,
	Word: string,
}

local PLACES: { PlaceSpec } = {
	{
		Place = 1,
		X = 0,
		Height = 3.4,
		Width = 4,
		Metal = { Color = rgb(255, 196, 46), Material = Enum.Material.Metal, Reflectance = 0.12 },
		Tall = 6.9,
		Pose = "Victory",
		Medal = "🥇",
		Word = "1ST",
	},
	{
		Place = 2,
		X = SPACING,
		Height = 2.8,
		Width = 3.8,
		Metal = { Color = rgb(206, 214, 228), Material = Enum.Material.Metal, Reflectance = 0.12 },
		Tall = 6.4,
		Pose = "Point",
		Medal = "🥈",
		Word = "2ND",
	},
	{
		Place = 3,
		X = -SPACING,
		Height = 2.2,
		Width = 3.8,
		Metal = { Color = rgb(214, 130, 62), Material = Enum.Material.Metal, Reflectance = 0.1 },
		Tall = 6.4,
		Pose = "Wave",
		Medal = "🥉",
		Word = "3RD",
	},
}

-- The joints a pose turns, as turns about the body's front-to-back axis in degrees: positive raises
-- the right arm, negative the left; elbows bend the same way. Every raised arm reaches outward (2nd
-- place points up on the podium's side, 3rd waves on the gallery's). R15 joint names, and an R6
-- body's own (no elbows: its arm goes higher instead).
local POSES: { [string]: { [string]: number } } = {
	Victory = { RightShoulder = 148, LeftShoulder = -148 },
	Point = { RightShoulder = 165, LeftShoulder = -12 },
	Wave = { LeftShoulder = -95, LeftElbow = -68, RightShoulder = 8 },
}
local R6_POSES: { [string]: { [string]: number } } = {
	Victory = { ["Right Shoulder"] = 148, ["Left Shoulder"] = -148 },
	Point = { ["Right Shoulder"] = 165, ["Left Shoulder"] = -12 },
	Wave = { ["Left Shoulder"] = -140, ["Right Shoulder"] = 8 },
}

export type Leader = { UserId: number, Name: string, Points: number }

type Spot = {
	Spec: PlaceSpec,
	Top: CFrame, -- the plinth's top middle, facing the fountain
	Plate: TextLabel,
	PlatePoints: TextLabel,
	Tag: BillboardGui,
	TagName: TextLabel,
	TagPoints: TextLabel,
	Holder: Model, -- what stands on the plinth: the statue or the stand-in
	UserId: number, -- whose statue it is (0: empty)
	Token: number, -- bumped whenever the place changes hands, so a slow avatar load can't land late
}

local spots: { [number]: Spot } = {}
local hall: Model? = nil

-- The Hall's frame: on the ground under the middle plinth, looking at the fountain.
function HallOfFame.Frame(): CFrame
	local outward = Vector3.new(math.cos(ANGLE), 0, math.sin(ANGLE))
	local position = outward * RADIUS
	return CFrame.lookAt(position, Vector3.zero)
end

-- The Hall's footprint in its own frame (X across, Z outward), for clearing the scenery: the dais
-- and plinths, and the board's posts behind them (whose backs reach into the hedge's leaves, which
-- stays: it's walked through).
local FOOTPRINT = {
	{ X0 = -7.9, X1 = 7.9, Z0 = -3.4, Z1 = 4.4 },
	{ X0 = -POST_X - 1, X1 = POST_X + 1, Z0 = 4.4, Z1 = BOARD_Z + 0.4 },
}

local function inFootprint(frame: CFrame, box: CFrame, size: Vector3, slack: number): boolean
	local position = frame:PointToObjectSpace(box.Position)
	local reach = math.max(size.X, size.Z) / 2 * slack
	for _, area in FOOTPRINT do
		if
			position.X > area.X0 - reach
			and position.X < area.X1 + reach
			and position.Z > area.Z0 - reach
			and position.Z < area.Z1 + reach
		then
			return true
		end
	end
	return false
end

-- Clears the plaza's scenery out of the Hall's way: trees and bushes that would poke into it, and
-- bunting strung across it. (The flower bed in front and the lamps either side stay.)
local function clearSite(root: Instance, frame: CFrame)
	local scenery = { Tree = 0.7, Bush = 0.8 }
	for _, model in root:GetDescendants() do
		if not model:IsA("Model") or not model.Parent then
			continue
		end
		local slack = scenery[model.Name]
		if model.Name == "LobbyBunting" then
			slack = 0.15 -- strung lamp to lamp: only its middle has to be clear
		end
		if not slack then
			continue
		end
		local box, size = model:GetBoundingBox()
		if inFootprint(frame, box, size, slack) then
			model:Destroy()
		end
	end
end

local function surfaceGui(part: BasePart, face: Enum.NormalId, pixelsPerStud: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.MaxDistance = 160
	gui.Parent = part
	return gui
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.5
	for key, value in props do
		(text :: any)[key] = value
	end
	text.Parent = parent
	return text
end

-- A toy-like figure of rounded blocks in avatar proportions, `tall` studs to the top of its head,
-- posed like the statue it stands in for: the stand-in on an empty plinth (see-through) or for an
-- avatar that wouldn't load (metal). Its feet are on its pivot.
local FIGURE_TALL = 7.1 -- the figure below at scale 1
local function figure(name: string, pose: string, look: Look, transparency: number, tall: number): Model
	local model = Build.Model(name)
	local turns = POSES[pose] or {}
	local scale = tall / FIGURE_TALL
	local function piece(pieceName: string, size: Vector3, cframe: CFrame, rounding: number)
		Shapes.RoundedBox(size * scale, rounding * scale, {
			Name = pieceName,
			CFrame = CFrame.new(cframe.Position * scale) * cframe.Rotation,
			Color = look.Color,
			Material = look.Material,
			Reflectance = look.Reflectance,
			Transparency = transparency,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = transparency < 0.5,
			Parent = model,
		})
	end
	piece("Head", Vector3.new(1.9, 1.9, 1.9), CFrame.new(0, 6.15, 0), 0.8)
	piece("Torso", Vector3.new(3, 2.9, 1.5), CFrame.new(0, 3.95, 0), 0.45)
	piece("LeftLeg", Vector3.new(1.3, 2.5, 1.4), CFrame.new(-0.75, 1.25, 0), 0.45)
	piece("RightLeg", Vector3.new(1.3, 2.5, 1.4), CFrame.new(0.75, 1.25, 0), 0.45)
	-- Arms hang from the shoulders and turn like the pose's (upper and lower arm as one piece, or
	-- two when the elbow bends).
	for _, side in { "Right", "Left" } do
		local sign = if side == "Right" then 1 else -1
		local shoulder = CFrame.new(sign * 1.95, 5.15, 0)
			* CFrame.Angles(0, 0, math.rad(turns[side .. "Shoulder"] or 0))
		local elbow = turns[side .. "Elbow"]
		if elbow then
			piece(side .. "UpperArm", Vector3.new(1.1, 1.5, 1.1), shoulder * CFrame.new(0, -0.7, 0), 0.4)
			local bent = shoulder * CFrame.new(0, -1.4, 0) * CFrame.Angles(0, 0, math.rad(elbow))
			piece(side .. "LowerArm", Vector3.new(1.05, 1.55, 1.05), bent * CFrame.new(0, -0.7, 0), 0.4)
		else
			piece(side .. "Arm", Vector3.new(1.1, 2.9, 1.1), shoulder * CFrame.new(0, -1.35, 0), 0.4)
		end
	end
	model.WorldPivot = CFrame.identity
	return model
end

-- A rig's joints as links between its parts: Motor6Ds and welds (C0 and C1 in their parts), and the
-- AnimationConstraints and RigidConstraints newer avatars come with (their two attachments). Not the
-- BallSocketConstraints beside the AnimationConstraints: they're for ragdolls, and say nothing of
-- the pose.
type Link = { Name: string, Part0: BasePart, Part1: BasePart, C0: CFrame, C1: CFrame }
local function links(model: Model): { Link }
	local list: { Link } = {}
	for _, item in model:GetDescendants() do
		if item:IsA("JointInstance") then
			if item.Part0 and item.Part1 then
				table.insert(
					list,
					{ Name = item.Name, Part0 = item.Part0, Part1 = item.Part1, C0 = item.C0, C1 = item.C1 }
				)
			end
		elseif item:IsA("AnimationConstraint") or item:IsA("RigidConstraint") then
			local a0, a1 = item.Attachment0, item.Attachment1
			local part0 = a0 and a0.Parent
			local part1 = a1 and a1.Parent
			if a0 and a1 and part0 and part1 and part0:IsA("BasePart") and part1:IsA("BasePart") then
				table.insert(list, { Name = item.Name, Part0 = part0, Part1 = part1, C0 = a0.CFrame, C1 = a1.CFrame })
			end
		end
	end
	return list
end

-- Where every part goes for the pose: worked out from the joints, outward from the root (the rig
-- as built, with the pose's joints turned). A turn is about the parent part's front-to-back axis
-- whatever the joint's own axes are, so arms go up sideways on any body. Only works it out: the
-- statue's joints are gone before the parts move (joints between anchored parts would snap them
-- back).
local function posed(model: Model, turns: { [string]: number }): { [BasePart]: CFrame }
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return {}
	end
	local joints = links(model)
	local placed: { [BasePart]: CFrame } = { [root] = root.CFrame }
	local progress = true
	while progress do
		progress = false
		for _, joint in joints do
			local part0, part1 = joint.Part0, joint.Part1
			local degrees = turns[joint.Name]
			local turn = CFrame.identity
			if degrees then
				local axes = joint.C0.Rotation
				turn = axes:Inverse() * CFrame.Angles(0, 0, math.rad(degrees)) * axes
			end
			if placed[part0] and not placed[part1] then
				placed[part1] = placed[part0] * joint.C0 * turn * joint.C1:Inverse()
				progress = true
			elseif placed[part1] and not placed[part0] then
				placed[part0] = placed[part1] * joint.C1 * turn:Inverse() * joint.C0:Inverse()
				progress = true
			end
		end
	end
	return placed
end

-- Turns a character model into a statue: one metal all over (no clothes, textures or effects),
-- anchored, nothing to bump into, and no Humanoid or joints left in it (nothing runs or moves, no
-- name over its head, and nothing turns its collisions back on).
local function cast(model: Model, look: Look)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.Massless = true
			item.Color = look.Color
			item.Material = look.Material
			item.Reflectance = look.Reflectance
			item.CastShadow = true
			if item:IsA("MeshPart") then
				item.TextureID = ""
			end
		elseif item:IsA("SpecialMesh") then
			item.TextureId = ""
		elseif item:IsA("Decal") then
			-- The face, carved in: a darker shade of the metal.
			item.Color3 = look.Color:Lerp(Color3.new(0, 0, 0), 0.55)
		elseif
			item:IsA("SurfaceAppearance")
			or item:IsA("Clothing")
			or item:IsA("ShirtGraphic")
			or item:IsA("BodyColors")
			or item:IsA("LuaSourceContainer")
			or item:IsA("Sound")
			or item:IsA("ParticleEmitter")
			or item:IsA("Fire")
			or item:IsA("Smoke")
			or item:IsA("Sparkles")
			or item:IsA("Light")
			or item:IsA("JointInstance")
			or item:IsA("WeldConstraint")
			or item:IsA("Constraint")
			or item:IsA("AnimationConstraint")
			or item:IsA("Humanoid")
		then
			item:Destroy()
		end
	end
end

-- The statue of `userId` for place `spec`, standing with its feet on its pivot (nil when the
-- avatar can't be loaded: test servers, an outage, a deleted account).
local function statueOf(userId: number, spec: PlaceSpec): Model?
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	local built = pcall(function()
		model.Name = "Statue"
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") then
				item.Anchored = true -- before anything moves, so joints never pull at it
			end
		end
		-- Every statue of a place is as tall (standing straight, hats and hair included).
		local height = model:GetExtentsSize().Y
		model:ScaleTo(math.clamp(if height > 0 then spec.Tall / height else 1, 0.6, 1.8))
		local turns = if model:FindFirstChild("UpperTorso") then POSES[spec.Pose] else R6_POSES[spec.Pose]
		local placed = posed(model, turns or {})
		cast(model, spec.Metal)
		for part, cframe in placed do
			part.CFrame = cframe
		end
		-- Feet on the pivot: the model's lowest point under its root, facing the way the rig does.
		-- (A rig's pivot is its root part's, moved by the part's PivotOffset.)
		local root = model.PrimaryPart
		local box, size = model:GetBoundingBox()
		local base = if root then root.CFrame else box
		local feet = CFrame.new(base.Position.X, box.Position.Y - size.Y / 2, base.Position.Z) * base.Rotation
		if root then
			root.PivotOffset = root.CFrame:ToObjectSpace(feet)
		else
			model.WorldPivot = feet
		end
	end)
	if not built then
		model:Destroy()
		return nil
	end
	return model
end

local function setTag(spot: Spot, leader: Leader?)
	local spec = spot.Spec
	if leader then
		spot.Plate.Text = `{spec.Medal} {leader.Name}`
		spot.PlatePoints.Text = `{spec.Word} · {leader.Points} PTS`
		spot.TagName.Text = `{spec.Medal} {leader.Name}`
		spot.TagPoints.Text = `{spec.Word} LAST WEEK · {leader.Points} PTS`
	else
		spot.Plate.Text = "YOUR STATUE HERE?"
		spot.PlatePoints.Text = `{spec.Word} · TOP 3 THIS WEEK`
		spot.TagName.Text = "YOUR STATUE HERE?"
		spot.TagPoints.Text = `{spec.Medal} {spec.Word}: finish the week in the TOP 3`
	end
end

-- Puts `model` (feet on its pivot) on the spot's plinth, facing the fountain: anchored, and walked
-- through (nothing to stand on, hang on or bump into but the plinth).
local function stand(spot: Spot, model: Model)
	model:PivotTo(spot.Top)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	model.Parent = spot.Holder
end

local function clearHolder(spot: Spot)
	for _, child in spot.Holder:GetChildren() do
		child:Destroy()
	end
end

local function showStandIn(spot: Spot)
	clearHolder(spot)
	local spec = spot.Spec
	local ghost = figure(
		"StandIn",
		spec.Pose,
		{ Color = spec.Metal.Color, Material = Enum.Material.Glass, Reflectance = 0 },
		0.55,
		spec.Tall
	)
	stand(spot, ghost)
end

local function buildPlinth(parent: Model, frame: CFrame, spec: PlaceSpec): Spot
	local base = frame * CFrame.new(spec.X, 0, 0)
	local width, height = spec.Width, spec.Height
	-- The marble block, its metal cap and a foot.
	Shapes.RoundedBox(Vector3.new(width, height - 0.45, width), 0.35, {
		Name = "Plinth" .. spec.Place,
		CFrame = base * CFrame.new(0, (height - 0.45) / 2 + 0.25, 0),
		Color = MARBLE,
		Material = Enum.Material.Marble,
		Parent = parent,
	})
	Shapes.RoundedBox(Vector3.new(width + 0.5, 0.5, width + 0.5), 0.2, {
		Name = "Foot",
		CFrame = base * CFrame.new(0, 0.5, 0),
		Color = MARBLE,
		Material = Enum.Material.Marble,
		Parent = parent,
	})
	Shapes.RoundedBox(Vector3.new(width + 0.4, 0.5, width + 0.4), 0.2, {
		Name = "Cap",
		CFrame = base * CFrame.new(0, height - 0.2, 0),
		Color = spec.Metal.Color,
		Material = spec.Metal.Material,
		Reflectance = spec.Metal.Reflectance,
		Parent = parent,
	})
	-- The name plate on the front (toward the fountain).
	local plate = Build.Decor({
		Name = "Plate" .. spec.Place,
		Size = Vector3.new(PLATE.X, PLATE.Y, 0.1),
		CFrame = base * CFrame.new(0, PLATE_Y + PLATE.Y / 2, -width / 2 - 0.06),
		Color = DARK,
		Parent = parent,
	})
	local plateGui = surfaceGui(plate, Enum.NormalId.Front, 60)
	local plateName = label(plateGui, {
		Name = "Name",
		Position = UDim2.fromScale(0.05, 0.06),
		Size = UDim2.fromScale(0.9, 0.52),
		TextColor3 = rgb(255, 255, 255),
	})
	local platePoints = label(plateGui, {
		Name = "Points",
		Position = UDim2.fromScale(0.08, 0.6),
		Size = UDim2.fromScale(0.84, 0.32),
		TextColor3 = spec.Metal.Color,
		Font = SIGN_FONT,
		TextStrokeTransparency = 0.7,
	})
	-- A warm light on it, and the name tag over the statue's head (a fixed size on screen, so it
	-- reads from across the plaza on a phone).
	local top = base * CFrame.new(0, height + 0.05, 0)
	local tagSpot = Build.Decor({
		Name = "TagSpot" .. spec.Place,
		Size = Vector3.one * 0.2,
		Transparency = 1,
		CFrame = top * CFrame.new(0, spec.Tall + 1, -1.5), -- a little in front, clear of a raised arm
		Parent = parent,
	})
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(220, 52)
	tag.MaxDistance = 110
	tag.LightInfluence = 0
	tag.Adornee = tagSpot
	tag.Parent = tagSpot
	local tagName = label(tag, {
		Name = "Name",
		Size = UDim2.new(1, 0, 0, 30),
		TextStrokeTransparency = 0.2,
	})
	local tagPoints = label(tag, {
		Name = "Points",
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = spec.Metal.Color,
		TextStrokeTransparency = 0.2,
	})
	local glow = Build.Decor({
		Name = "Glow" .. spec.Place,
		Size = Vector3.one * 0.2,
		Transparency = 1,
		CFrame = top * CFrame.new(0, 3, -3),
		Parent = parent,
	})
	Build.Light(glow, rgb(255, 232, 180), 12, 1.1)

	local holder = Build.Model("Statue" .. spec.Place, parent)
	local spot: Spot = {
		Spec = spec,
		Top = top,
		Plate = plateName,
		PlatePoints = platePoints,
		Tag = tag,
		TagName = tagName,
		TagPoints = tagPoints,
		Holder = holder,
		UserId = 0,
		Token = 0,
	}
	setTag(spot, nil)
	showStandIn(spot)
	return spot
end

local function buildBoard(parent: Model, frame: CFrame)
	local face = frame * CFrame.new(0, BOARD_Y, BOARD_Z)
	-- Two white posts with gold tops hold the gold bezel, the screen and the sign.
	for _, x in { -POST_X, POST_X } do
		local height = BOARD_Y + BOARD_SIZE.Y / 2 + 1.6
		Shapes.RoundedBox(Vector3.new(1.3, height, 1.3), 0.6, {
			Name = "Post",
			CFrame = frame * CFrame.new(x, height / 2, BOARD_Z + 0.5),
			Color = rgb(255, 255, 255),
			Parent = parent,
		})
		Build.Part({
			Name = "PostTop",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.9,
			CFrame = frame * CFrame.new(x, height + 0.5, BOARD_Z + 0.5),
			Color = rgb(255, 204, 64),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = parent,
		})
	end
	Shapes.RoundedBox(Vector3.new(BOARD_SIZE.X + 1.6, BOARD_SIZE.Y + 1.4, 1), 0.5, {
		Name = "BoardBezel",
		CFrame = face * CFrame.new(0, 0, 0.6), -- its face 0.1 behind the screen's (no flicker)
		Color = rgb(255, 204, 64),
		Parent = parent,
	})
	local board = Build.Part({
		Name = "WeeklyBoard",
		Size = Vector3.new(BOARD_SIZE.X, BOARD_SIZE.Y, 0.4),
		CFrame = face * CFrame.new(0, 0, 0.2),
		Color = rgb(30, 22, 64),
		Parent = parent,
	})
	CollectionService:AddTag(board, "WeeklyBoard")
	-- The sign on top, like the podium's CHAMPIONS.
	local sign = Shapes.RoundedBox(Vector3.new(14, 3.6, 1), 0.45, {
		Name = "Sign",
		CFrame = face * CFrame.new(0, BOARD_SIZE.Y / 2 + 0.7 + 1.8, 0.5), -- standing on the bezel
		Color = rgb(255, 84, 150),
		Parent = parent,
	})
	local gui = surfaceGui(sign, Enum.NormalId.Front, 16)
	gui.MaxDistance = 250
	label(gui, {
		Name = "Text",
		Text = "HALL OF FAME",
		Font = SIGN_FONT,
		Size = UDim2.fromScale(0.92, 0.84),
		Position = UDim2.fromScale(0.04, 0.08),
		TextStrokeTransparency = 0.35,
	})
end

-- Builds the Hall into the lobby's model (LobbyBuilder, after the scenery).
function HallOfFame.Build(root: Model)
	local frame = HallOfFame.Frame()
	clearSite(root, frame)
	local model = Build.Model("HallOfFame", root)
	hall = model
	-- A gold-rimmed marble floor half a stud up (a step anyone walks onto).
	Shapes.Slab(DAIS, 1.2, {
		Name = "Dais",
		CFrame = frame * CFrame.new(0, DAIS.Y / 2, 0.4),
		Color = rgb(255, 204, 64),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	Shapes.Slab(Vector3.new(DAIS.X - 1, 0.1, DAIS.Z - 1), 0.8, {
		Name = "DaisTop",
		CFrame = frame * CFrame.new(0, DAIS.Y + 0.05, 0.4),
		Color = MARBLE,
		Material = Enum.Material.Marble,
		Parent = model,
	})
	table.clear(spots)
	for _, spec in PLACES do
		spots[spec.Place] = buildPlinth(model, frame, spec)
	end
	buildBoard(model, frame)
end

-- Last week's top three (best first; fewer, or none, before anyone has a last week): builds each
-- new leader's statue (in the background: avatars take a moment to load) and updates the tags.
-- Safe to call again with the same list; a place whose leader didn't change keeps its statue.
function HallOfFame.SetStatues(leaders: { Leader })
	for place, spot in spots do
		local leader = leaders[place]
		setTag(spot, leader)
		local userId = if leader then leader.UserId else 0
		if spot.UserId == userId then
			continue
		end
		spot.UserId = userId
		spot.Token += 1
		if not leader then
			showStandIn(spot)
			continue
		end
		local token = spot.Token
		task.spawn(function()
			local statue = statueOf(userId, spot.Spec)
			if spot.Token ~= token or not spot.Holder.Parent then
				if statue then
					statue:Destroy()
				end
				return
			end
			clearHolder(spot)
			if not statue then
				-- The avatar wouldn't load: a metal figure in the same pose holds the place.
				statue = figure("Statue", spot.Spec.Pose, spot.Spec.Metal, 0, spot.Spec.Tall)
				statue:SetAttribute("StandIn", true)
			end
			local built = statue :: Model
			built:SetAttribute("UserId", userId)
			stand(spot, built)
		end)
	end
end

-- Tools only (tools/checks/weekly_check.luau): what stands on each plinth now.
function HallOfFame.StateForTests(): { [string]: any }
	local state = {}
	for place, spot in spots do
		local model = spot.Holder:FindFirstChildWhichIsA("Model")
		table.insert(state, {
			place = place,
			userId = spot.UserId,
			model = if model then model.Name else "none",
			standIn = if model then model:GetAttribute("StandIn") == true or model.Name == "StandIn" else nil,
			plate = spot.Plate.Text .. " / " .. spot.PlatePoints.Text,
			tag = spot.TagName.Text .. " / " .. spot.TagPoints.Text,
		})
	end
	return { built = hall ~= nil and hall.Parent ~= nil, spots = state }
end

return HallOfFame

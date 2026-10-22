-- The medal wall (owner, asked what keeps players coming back: "Medals: a medal for winning each
-- game and a few big ones, Roblox badges, a collect-them-all wall in the lobby", then: "Can you work
-- on all of that? this wont mess with what the other workers are working on right?"): a gold-framed
-- board on a stone plinth with every medal in the game hanging on it from its ribbon, the big ones
-- in the top row and one for each game under them, a pink MEDALS sign on top with a giant gold
-- medal, trophies turning on its corners and bulbs round its frame.
--
-- Where: the south-west lawn between the SHOP and the quest corner, looking back at the fountain
-- (LobbyBuilder's header map: the west zone). The flower bed in front of it stays; the trees, bushes
-- and lamp posts of the plaza's scenery that stood where it is are cleared (like the arcade's), and
-- it keeps clear of the shop, the quest corner's patio and gift machine, the obby (north-west) and
-- the beach balls' spots on the promenade.
--
-- Each player's own medals light up on their screen only: every medal is a "MedalSlot" model
-- (MedalId attribute) with a Disc (the clients draw the medal's icon on its Right face, which looks
-- at the plaza) and its Ribbon strips, built here in the locked look; Controllers/MedalController
-- turns the ones a player has gold. The "MedalCount" board on the plinth's front shows each player
-- their count and holds the prompt that opens the medal screen (its Action is "OpenMedals").
-- The layout comes from Logic/MedalLogic.WallLayout, so more games make more rows.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MedalLogic = require(ReplicatedStorage.Shared.Logic.MedalLogic)
local Medals = require(ReplicatedStorage.Shared.Medals)

local Build = require(script.Parent.Build)
local MeshLibrary = require(script.Parent.MeshLibrary)
local Shapes = require(script.Parent.Shapes)

local MedalWall = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Where the wall stands: this far round the plaza (from +X toward +Z) and its board's face this far
-- out from the middle (the south-west lawn, near the plaza's edge: the shop's side wall and the gift
-- machine are about 4 studs from its ends, the flower bed 8 in front, the hedges 7 behind).
local ANGLE = math.rad(159)
local FRONT_RADIUS = 69.5

local PLINTH_H = 1.2 -- the stone plinth (its band reaches 0.1 higher)
local PLINTH_FRONT, PLINTH_BACK = -2.2, 1.6 -- the plinth's faces (the board's face is at z = 0)
local RIM = 0.6 -- the gold board shows this much round the medal panel
local PANEL_DEPTH = 0.5
local BOARD_FRONT, BOARD_BACK = 0.3, 1.1

-- The colours: a locked medal (the clients light up the ones each player has).
MedalWall.LockedDisc = rgb(92, 78, 140)
MedalWall.LockedRibbon = rgb(120, 110, 150)
local GOLD = rgb(255, 204, 64)
local PANEL = rgb(52, 36, 104)
local STONE = rgb(250, 242, 228)
local PINK = rgb(255, 84, 150)
local PARTY_COLORS = {
	rgb(255, 84, 150),
	rgb(64, 196, 255),
	rgb(255, 204, 64),
	rgb(156, 108, 255),
	rgb(110, 226, 140),
	rgb(255, 140, 70),
}

-- The wall's frame: on the ground under the middle of the board's face, looking at the fountain
-- (-Z toward the plaza, +X to the left of a player facing the wall).
function MedalWall.Frame(): CFrame
	local outward = Vector3.new(math.cos(ANGLE), 0, math.sin(ANGLE))
	local front = outward * FRONT_RADIUS
	return CFrame.lookAt(front, front - outward)
end

-- The board's size for today's list of medals.
local function layout(): MedalLogic.WallLayout
	return MedalLogic.WallLayout(#Medals.Big, #Medals.Games)
end

-- The wall's footprint in its own frame (half its length, and its depth from the plinth's front to
-- its back: the plinth's gold band), for clearing the scenery out of its way.
local function footprint(): (number, number, number)
	local half = layout().Width / 2 + RIM + 0.6
	return half, PLINTH_FRONT - 0.1, PLINTH_BACK + 0.1
end

-- Where a prop's box (shrunk by `slack` about its middle: a tree's canopy is rounder than its box)
-- reaches in the wall's frame: its least and most x, then z.
local function reachOf(frame: CFrame, box: CFrame, size: Vector3, slack: number): (number, number, number, number)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, sx in { -0.5, 0.5 } do
		for _, sz in { -0.5, 0.5 } do
			local corner =
				frame:PointToObjectSpace(box:PointToWorldSpace(Vector3.new(sx * size.X, 0, sz * size.Z) * slack))
			minX, maxX = math.min(minX, corner.X), math.max(maxX, corner.X)
			minZ, maxZ = math.min(minZ, corner.Z), math.max(maxZ, corner.Z)
		end
	end
	return minX, maxX, minZ, maxZ
end

-- Clears the plaza's scenery out of the wall's way: trees and bushes that would reach into it (the
-- wall is taller than most of them, so a tree just behind would grow through its sign), a lamp post
-- by its end, and the bunting that would run through it or hung from that lamp post (as the arcade
-- does). The flower bed in front of it stays.
local function clearSite(root: Instance, frame: CFrame)
	local half, front, back = footprint()
	-- How much of each prop's box counts, and how far from the wall it may come.
	local rules = {
		Tree = { Slack = 0.7, Gap = 1 },
		Bush = { Slack = 0.8, Gap = 0.5 },
		LampPost = { Slack = 1, Gap = 3 },
		LobbyBunting = { Slack = 1, Gap = 1 },
	}
	local removed: { Vector3 } = {}
	for _, model in root:GetDescendants() do
		local rule = model:IsA("Model") and rules[model.Name]
		if not rule then
			continue
		end
		local box, size = (model :: Model):GetBoundingBox()
		local minX, maxX, minZ, maxZ = reachOf(frame, box, size, rule.Slack)
		if
			maxX > -half - rule.Gap
			and minX < half + rule.Gap
			and maxZ > front - rule.Gap
			and minZ < back + rule.Gap
		then
			if model.Name == "LampPost" then
				table.insert(removed, (model :: Model):GetPivot().Position)
			end
			model:Destroy()
		end
	end
	for _, model in root:GetDescendants() do
		if not model:IsA("Model") or model.Name ~= "LobbyBunting" then
			continue
		end
		local box, size = model:GetBoundingBox()
		for _, lamp in removed do
			local flat = Vector3.new(box.Position.X - lamp.X, 0, box.Position.Z - lamp.Z)
			if flat.Magnitude < size.X / 2 + 1.5 then
				model:Destroy()
				break
			end
		end
	end
end

-- One medal: its disc (the icon goes on the face toward the plaza) and its ribbon, a V of two
-- strips in the medal's colour from the top of the disc. `center` is the disc's middle.
local function medalSlot(parent: Instance, medal: Medals.Medal, center: CFrame, disc: number, ribbon: number): Model
	local model = Build.Model("Medal_" .. medal.Id)
	Build.Decor({
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.24, disc, disc),
		-- The cylinder runs along its X axis: turned so its Right face looks at the plaza (-Z).
		CFrame = center * CFrame.Angles(0, math.rad(90), 0),
		Color = MedalWall.LockedDisc,
		Parent = model,
	})
	local length = ribbon + disc * 0.2 -- (it starts a little down behind the disc)
	local width = disc * 0.34
	for _, side in { -1, 1 } do
		local lean = math.rad(16) * side
		local foot = center * CFrame.new(side * disc * 0.1, disc * 0.3, 0.07)
		Build.Decor({
			Name = "Ribbon",
			Size = Vector3.new(width, length, 0.05),
			CFrame = foot * CFrame.Angles(0, 0, -lean) * CFrame.new(0, length / 2, 0),
			Color = MedalWall.LockedRibbon,
			Parent = model,
		})
	end
	model:SetAttribute("MedalId", medal.Id)
	model.Parent = parent
	CollectionService:AddTag(model, "MedalSlot")
	return model
end

-- A neon bulb on the frame.
local function bulb(parent: Instance, cframe: CFrame, index: number)
	Build.Decor({
		Name = "Bulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.42,
		CFrame = cframe,
		Color = PARTY_COLORS[(index % #PARTY_COLORS) + 1],
		Material = Enum.Material.Neon,
		Parent = parent,
	})
end

-- Builds into the lobby's model (called by LobbyBuilder after the scenery, like the arcade).
function MedalWall.Build(root: Model)
	local frame = MedalWall.Frame()
	clearSite(root, frame)
	local wall = Build.Model("MedalWall", root)
	local grid = layout()
	local boardW, boardH = grid.Width + 2 * RIM, grid.Height + 2 * RIM
	local boardBottom = PLINTH_H + 0.1
	local boardY = boardBottom + boardH / 2
	local panelBottom = boardBottom + RIM
	local boardTop = boardBottom + boardH

	-- The plinth, with a gold band round its top.
	local plinthW = boardW + 1
	local plinthDepth = PLINTH_BACK - PLINTH_FRONT
	Shapes.RoundedBox(Vector3.new(plinthW, PLINTH_H, plinthDepth), 0.45, {
		Name = "Plinth",
		CFrame = frame * CFrame.new(0, PLINTH_H / 2, (PLINTH_FRONT + PLINTH_BACK) / 2),
		Color = STONE,
		Parent = wall,
	})
	Shapes.RoundedBox(Vector3.new(plinthW + 0.2, 0.3, plinthDepth + 0.2), 0.14, {
		Name = "PlinthBand",
		CFrame = frame * CFrame.new(0, PLINTH_H - 0.05, (PLINTH_FRONT + PLINTH_BACK) / 2),
		Color = GOLD,
		Material = Enum.Material.Metal,
		Parent = wall,
	})

	-- The gold board, the medal panel on it, and the line between the big medals and the games.
	Shapes.RoundedBox(Vector3.new(boardW, boardH, BOARD_BACK - BOARD_FRONT), 0.5, {
		Name = "Board",
		CFrame = frame * CFrame.new(0, boardY, (BOARD_FRONT + BOARD_BACK) / 2),
		Color = GOLD,
		Material = Enum.Material.Metal,
		Parent = wall,
	})
	Shapes.RoundedBox(Vector3.new(grid.Width, grid.Height, PANEL_DEPTH), 0.35, {
		Name = "Panel",
		CFrame = frame * CFrame.new(0, panelBottom + grid.Height / 2, PANEL_DEPTH / 2),
		Color = PANEL,
		Parent = wall,
	})
	Shapes.RoundedBox(Vector3.new(grid.Width - 1.4, 0.16, 0.2), 0.07, {
		Name = "Divider",
		CFrame = frame * CFrame.new(0, panelBottom + grid.DividerY, -0.04),
		Color = GOLD,
		Material = Enum.Material.Metal,
		CanCollide = false,
		CastShadow = false,
		Parent = wall,
	})

	-- The medals, big ones first (in the list's order, like the medal screen).
	local medals = Build.Model("Medals", wall)
	local list = table.clone(Medals.Big)
	for _, medal in Medals.Games do
		table.insert(list, medal)
	end
	for index, medal in list do
		local slot = grid.Slots[index]
		if slot then
			local center = frame * CFrame.new(slot.X, panelBottom + slot.Y, -0.16)
			medalSlot(medals, medal, center, grid.Disc, grid.Ribbon)
		end
	end

	-- Bulbs along the frame's top and sides.
	local bulbs = Build.Model("Bulbs", wall)
	local count = 0
	local across = math.max(2, math.floor(boardW / 1.6))
	for step = 0, across do
		count += 1
		local x = -boardW / 2 + RIM / 2 + (boardW - RIM) * step / across
		bulb(bulbs, frame * CFrame.new(x, boardTop - RIM / 2, BOARD_FRONT - 0.05), count)
	end
	local up = math.max(2, math.floor((boardH - RIM) / 1.6))
	for _, side in { -1, 1 } do
		for step = 1, up - 1 do
			count += 1
			local y = boardTop - RIM / 2 - (boardH - RIM) * step / up
			bulb(bulbs, frame * CFrame.new(side * (boardW / 2 - RIM / 2), y, BOARD_FRONT - 0.05), count)
		end
	end

	-- The MEDALS sign on the board's top, and a giant gold medal pinned over it with its ribbon.
	local signH = 3
	local signY = boardTop + signH / 2 - 0.3
	local sign = Shapes.RoundedBox(Vector3.new(11.5, signH, 0.9), 0.4, {
		Name = "Sign",
		CFrame = frame * CFrame.new(0, signY, 0.7),
		Color = PINK,
		Parent = wall,
	})
	Build.SurfaceText(sign, Enum.NormalId.Front, "MEDALS", {
		PixelsPerStud = 16,
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = rgb(255, 236, 120),
		TextStrokeTransparency = 0.35,
		Padding = 0.08,
	})
	local emblemY = signY + signH / 2 + 1.1
	for _, side in { -1, 1 } do
		Build.Decor({
			Name = "EmblemRibbon",
			Size = Vector3.new(1.1, 3.4, 0.12),
			CFrame = frame * CFrame.new(side * 0.55, emblemY + 0.4, 0.4) * CFrame.Angles(0, 0, math.rad(-18) * side),
			Color = if side < 0 then rgb(64, 196, 255) else PINK,
			Parent = wall,
		})
	end
	Build.Decor({
		Name = "Emblem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 3.2, 3.2),
		CFrame = frame * CFrame.new(0, emblemY, 0.05) * CFrame.Angles(0, math.rad(90), 0),
		Color = GOLD,
		Material = Enum.Material.Metal,
		CastShadow = true,
		Parent = wall,
	})
	Build.Decor({
		Name = "EmblemFace",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 2.3, 2.3),
		CFrame = frame * CFrame.new(0, emblemY, -0.22) * CFrame.Angles(0, math.rad(90), 0),
		Color = rgb(255, 232, 130),
		Material = Enum.Material.Neon,
		Parent = wall,
	})

	-- Trophies turning on the board's top corners.
	for _, side in { -1, 1 } do
		local trophy = MeshLibrary.Get("Trophy", {
			Scale = 0.5,
			CFrame = frame * CFrame.new(side * (boardW / 2 - 1.3), boardTop, 0.7),
			Parent = wall,
		})
		CollectionService:AddTag(trophy, "PP_Spin")
	end

	-- The count board on the plinth's front (each player's count, drawn by their client) with the
	-- prompt that opens the medal screen.
	local counter = Build.Part({
		Name = "MedalCount",
		Size = Vector3.new(9, 0.7, 0.1),
		CFrame = frame * CFrame.new(0, 0.55, PLINTH_FRONT - 0.07),
		Color = PANEL,
		CanCollide = false,
		Parent = wall,
	})
	CollectionService:AddTag(counter, "MedalCount")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "See Medals"
	prompt.ObjectText = "Medal Wall"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", "OpenMedals") -- opened on the client (MedalController)
	prompt.Parent = counter
end

return MedalWall

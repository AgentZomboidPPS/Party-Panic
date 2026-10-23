-- Obby Odyssey (Race, up to 12 players). The owner sent a photo of a bright blocky obby ("Can you make an
-- Oby obstacle course similar to this photo? I want it to be a mini game for the game.") and asked for a
-- cool name and a longer round ("Also think of a cool name for the oby mini game. you can make it a bit
-- longer then the average mini game too."). Everyone races the same long obby over a pool: hop the
-- colourful blocks over the water, time the swinging red balls on the bridge, climb the yellow steps up
-- the blue tower, jump the spinning bars over the lava, cross the blinking blocks and climb the pyramid to
-- the gold crown. Fall in and you're back on your last checkpoint (nobody is knocked out). First to the
-- crown wins; once someone has it, the rest have FINISH_CLOCK seconds. The rest rank by finish order,
-- then by how far along they got.
--
-- How it works: the layout, the hazards' schedule and the rules are in Shared/Logic/ObbyOdyssey, so the
-- server, the clients, the bots and the tests all use the same numbers. Everyone runs and jumps with
-- their own character (bots with the server's physics) on solid course pieces; the scenery never
-- collides, so the only things to stand on are the course's own tops, and anything off them is a fall.
-- The balls and bars are drawn on every client from the shared schedule (MG_Course's epoch) and judged
-- here against each runner as their own screen showed them (fair hits, owner: "the precision games will
-- feel super bad if we dont"): a person's position reaches the server half their ping late, so they're
-- judged against the hazards as they were then; a bar's hit is swept between checks so a fast one can't
-- slip past anyone. A hit throws the runner (ctx:Knockback: their own device for people, the server for
-- bots). The blinking blocks go solid and see-through on the same schedule on every device, and here for
-- the bots. Runners pass through each other (one collision group), so twelve on a bridge never block or
-- shove anyone off.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Course = require(ReplicatedStorage.Shared.Logic.ObbyOdyssey)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Notifier = require(script.Parent.Parent.Services.Notifier)
local Build = require(script.Parent.Parent.World.Build)
local Shapes = require(script.Parent.Parent.World.Shapes)

local ObbyOdyssey = MiniGame.Define("ObbyOdyssey")

local FINISH_CLOCK = 25 -- seconds the others get once someone has the crown
local MAX_PING = 0.5 -- round trips above this are judged as this
local HIT_COOLDOWN = 1.4 -- after a hit, no new one for this long (they're flying)
local BALL_PUSH, BALL_LIFT, BALL_STUN = 62, 34, 0.9
local BAR_PUSH, BAR_LIFT, BAR_STUN = 44, 36, 0.7
local SHARE_EVERY = 0.25
-- Runners pass through each other; people also pass through anything still in the lobby's group.
local RUNNER_GROUP, PEOPLE_GROUP = "PP_ObbyRunners", "PP_Players"

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Runners' colours, each with a number on the HUD so colour is never the only cue.
local COLORS = {
	rgb(255, 80, 90),
	rgb(70, 150, 255),
	rgb(255, 205, 50),
	rgb(90, 210, 100),
	rgb(190, 110, 255),
	rgb(255, 145, 50),
	rgb(70, 220, 215),
	rgb(255, 120, 200),
	rgb(160, 110, 70),
	rgb(250, 250, 250),
	rgb(225, 50, 150),
	rgb(170, 215, 40),
}

-- The course's colours, after the photo: primary-coloured blocks, a blue tower with yellow steps, red
-- pipes and balls, a pink gantry, a stepped pyramid and a gold crown.
local PALETTE = {
	Red = rgb(235, 60, 60),
	Yellow = rgb(255, 205, 40),
	Green = rgb(80, 200, 80),
	Blue = rgb(50, 140, 255),
	Orange = rgb(255, 140, 40),
	Purple = rgb(165, 95, 255),
	White = rgb(250, 248, 240),
	Pad = rgb(245, 245, 235),
	Bridge = rgb(255, 236, 200),
	Step = rgb(255, 205, 40),
	Tower = rgb(55, 120, 235),
	Disc = rgb(250, 248, 240),
	Pipe = rgb(225, 45, 50),
	Blink = rgb(170, 110, 255),
	Tier = rgb(80, 200, 80),
	Summit = rgb(255, 214, 70),
}
local TOWER_LIGHT = rgb(110, 175, 255)
local PINK = rgb(255, 84, 170)
local GOLD = rgb(255, 204, 64)
local CHECK_GREEN = rgb(90, 230, 120)
local TIER_COLORS = { rgb(80, 200, 80), rgb(50, 140, 255), rgb(235, 60, 60), rgb(255, 214, 70) }
local BLINK_COLORS = { rgb(170, 110, 255), rgb(255, 110, 200), rgb(70, 215, 230) }
local SIGN_FONT = Enum.Font.LuckiestGuy
local DEEP = -6 -- the low pieces' feet, under the water

type Runner = {
	Slot: number,
	Stage: number,
	Row: number,
	Progress: number,
	Finish: number?, -- server time
	Place: number?,
	HitUntil: number, -- os.clock(): no new hit before this
	SeenT: number?, -- the course time of the last hazard check, as their screen showed it
	Falls: number,
	FellAt: Vector3?, -- the last fall: x, the row it fell from, z
	Hits: number,
	Shown: number, -- the score last given
	Gone: boolean,
}

-- How far behind the server a runner's position arrives: half a person's round trip; a bot is the server's.
local function oneWay(player): number
	if BotRegistry.IsBot(player) then
		return 0
	end
	local ok, ping = pcall(function()
		return (player :: any):GetNetworkPing()
	end)
	return math.clamp(if ok and type(ping) == "number" then ping else 0, 0, MAX_PING) / 2
end

-- Where a character's feet are: R15 from its hip height, R6 three studs under the root.
local function feetOf(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
	end
	return root.Position.Y - 3
end

-- A cylinder part's CFrame standing upright at `center` (Roblox cylinders run along X).
local function upright(center: Vector3): CFrame
	return CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
end

function ObbyOdyssey:_at(x: number, y: number, z: number): CFrame
	return CFrame.new(self.origin + Vector3.new(x, y, z))
end

function ObbyOdyssey:_decor(props: { [string]: any }): Part
	props.Parent = props.Parent or self.context.Arena
	return Build.Decor(props)
end

-- Puts every runner's character in one collision group that doesn't collide with itself (parts that
-- load later too), so runners pass through each other. Returns false if the group can't be set up.
local function setUpGroups(): boolean
	return pcall(function()
		for _, group in { RUNNER_GROUP, PEOPLE_GROUP } do
			if not PhysicsService:IsCollisionGroupRegistered(group) then
				PhysicsService:RegisterCollisionGroup(group)
			end
		end
		PhysicsService:CollisionGroupSetCollidable(RUNNER_GROUP, RUNNER_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(RUNNER_GROUP, PEOPLE_GROUP, false)
	end)
end

function ObbyOdyssey:_joinGroup(character: Model)
	if not self.groupReady or self.grouped[character] then
		return
	end
	self.grouped[character] = true
	for _, item in character:GetDescendants() do
		if item:IsA("BasePart") then
			item.CollisionGroup = RUNNER_GROUP
		end
	end
	self.context:Track(character.DescendantAdded:Connect(function(item)
		if item:IsA("BasePart") then
			item.CollisionGroup = RUNNER_GROUP
		end
	end))
end

-- Building -------------------------------------------------------------------------------------------

-- A course piece: what's drawn is what's solid (rounded blocks and slabs, cylinders), and supports
-- under the floating ones are decoration.
function ObbyOdyssey:_buildPiece(piece: Course.Piece, folders: { [string]: Instance })
	local arena = self.context.Arena
	local color = PALETTE[piece.Color] or PALETTE.White
	local x, z, top = piece.X, piece.Z, piece.Top
	if piece.Kind == "Disc" then
		local disc = Build.Part({
			Name = piece.Id,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2, piece.W, piece.W),
			CFrame = upright(self.origin + Vector3.new(x, top - 1, z)),
			Color = color,
			Parent = arena,
		})
		disc:SetAttribute("Piece", piece.Id)
		-- a red skirt under the white top, a hub in the middle and a post down into the lava
		self:_decor({
			Name = "Skirt",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, piece.W - 0.02, piece.W - 0.02),
			CFrame = upright(self.origin + Vector3.new(x, top - 2.6, z)),
			Color = PALETTE.Red,
		})
		local spinner = Course.Spinners[piece.Spinner :: number]
		Build.Part({
			Name = "Hub",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(spinner.HubTop, spinner.Hub * 2, spinner.Hub * 2),
			CFrame = upright(self.origin + Vector3.new(x, top + spinner.HubTop / 2, z)),
			Color = PALETTE.Yellow,
			Parent = arena,
		})
		self:_decor({
			Name = "HubCap",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * (spinner.Hub * 1.6),
			CFrame = self:_at(x, top + spinner.HubTop, z),
			Color = GOLD,
			Material = Enum.Material.SmoothPlastic,
		})
		self:_decor({
			Name = "Post",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(top + 4, 4, 4),
			CFrame = upright(self.origin + Vector3.new(x, (top - 3.3) / 2 - 2, z)),
			Color = rgb(70, 60, 80),
		})
		-- The bar: drawn here at angle 0, turned on every client from the schedule.
		local bar = Build.Model(`Bar{piece.Spinner}`)
		bar:SetAttribute("Spinner", piece.Spinner)
		local barY = top + spinner.BarY
		self:_decor({
			Name = "Bar",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(spinner.Arm * 2, spinner.BarRadius * 2, spinner.BarRadius * 2),
			CFrame = self:_at(x, barY, z),
			Color = PALETTE.Red,
			Parent = bar,
		})
		for _, side in { -1, 1 } do
			self:_decor({
				Name = "Tip",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * (spinner.BarRadius * 2.4),
				CFrame = self:_at(x + side * spinner.Arm, barY, z),
				Color = PALETTE.White,
				Parent = bar,
			})
			for band = 1, 3 do
				self:_decor({
					Name = "Band",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.5, spinner.BarRadius * 2 + 0.06, spinner.BarRadius * 2 + 0.06),
					CFrame = self:_at(x + side * (spinner.Hub + band * (spinner.Arm - spinner.Hub) / 3.6), barY, z),
					Color = PALETTE.White,
					Parent = bar,
				})
			end
		end
		bar.WorldPivot = self:_at(x, barY, z)
		bar.Parent = folders.Bars
		return
	end
	if piece.Kind == "Pipe" then
		local radius = piece.W / 2
		Build.Part({
			Name = piece.Id,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(piece.D, piece.W, piece.W),
			CFrame = self:_at(x, top - radius, z) * CFrame.Angles(0, math.rad(90), 0),
			Color = color,
			Parent = arena,
		})
		for band = 1, 3 do
			self:_decor({
				Name = "Band",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.6, piece.W + 0.04, piece.W + 0.04),
				CFrame = self:_at(x, top - radius, z + (band - 2) * piece.D / 3.2) * CFrame.Angles(0, math.rad(90), 0),
				Color = PALETTE.White,
			})
		end
		return
	end
	if piece.Id == "Checkpoint3" then
		return -- the tower's top (built with the tower)
	end
	if piece.Section == 6 then
		-- A pyramid tier: a block on the one below, with a blue band up the middle of its front.
		local tier = piece.Row - 28
		local bottom = if tier == 1 then DEEP else top - 3.7
		Build.Part({
			Name = piece.Id,
			Size = Vector3.new(piece.W, top - bottom, piece.D),
			CFrame = self:_at(x, (top + bottom) / 2, z),
			Color = TIER_COLORS[tier],
			Parent = arena,
		})
		self:_decor({
			Name = "Stairs",
			Size = Vector3.new(10, top - math.max(bottom, 0), 0.2),
			CFrame = self:_at(x, (top + math.max(bottom, 0)) / 2, z - piece.D / 2 - 0.08),
			Color = rgb(60, 110, 230),
		})
		self:_decor({
			Name = "Lip",
			Size = Vector3.new(piece.W + 0.1, 0.5, piece.D + 0.1),
			CFrame = self:_at(x, top - 0.3, z),
			Color = rgb(255, 255, 255),
		})
		return
	end
	local floating = top > 10
	if piece.Blink then
		local block = Shapes.RoundedBox(Vector3.new(piece.W, 2.4, piece.D), 0.6, {
			Name = piece.Id,
			CFrame = self:_at(x, top - 1.2, z),
			Color = BLINK_COLORS[(piece.Blink :: number) + 1],
			Material = Enum.Material.SmoothPlastic,
			Parent = folders.Blinks,
		})
		block:SetAttribute("Piece", piece.Id)
		block:SetAttribute("Group", piece.Blink)
		self.blinks[piece.Id] = { Part = block, Piece = piece }
		return
	end
	local part
	if piece.Checkpoint then
		local bottom = if floating then top - 3 else DEEP
		part = Shapes.Slab(Vector3.new(piece.W, top - bottom, piece.D), 2, {
			Name = piece.Id,
			CFrame = self:_at(x, (top + bottom) / 2, z),
			Color = color,
			Parent = folders.Pads,
		})
		part:SetAttribute("Checkpoint", piece.Checkpoint)
		if piece.Checkpoint > 0 then
			self:_checkpointFlag(piece)
		end
	elseif piece.Kind == "Box" and piece.Section == 1 then
		part = Shapes.RoundedBox(Vector3.new(piece.W, top - DEEP, piece.D), 0.7, {
			Name = piece.Id,
			CFrame = self:_at(x, (top + DEEP) / 2, z),
			Color = color,
			Parent = arena,
		})
	elseif piece.Id == "Bridge" then
		part = Shapes.Slab(Vector3.new(piece.W, 2, piece.D), 1, {
			Name = piece.Id,
			CFrame = self:_at(x, top - 1, z),
			Color = color,
			Parent = arena,
		})
		-- pink edges and legs into the water
		for _, side in { -1, 1 } do
			self:_decor({
				Name = "Edge",
				Size = Vector3.new(0.6, 2.2, piece.D - 2),
				CFrame = self:_at(x + side * (piece.W / 2 - 0.2), top - 1.15, z),
				Color = PINK,
			})
		end
		for leg = 0, 4 do
			self:_decor({
				Name = "Leg",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(top + 6, 2, 2),
				CFrame = upright(self.origin + Vector3.new(x, (top - 2 + DEEP) / 2, z - piece.D / 2 + 4 + leg * 12)),
				Color = rgb(240, 230, 210),
			})
		end
	else
		-- a floating step: a rounded block on a thin stem
		part = Shapes.RoundedBox(Vector3.new(piece.W, 2.4, piece.D), 0.6, {
			Name = piece.Id,
			CFrame = self:_at(x, top - 1.2, z),
			Color = color,
			Parent = arena,
		})
		self:_decor({
			Name = "Stem",
			Size = Vector3.new(1.2, top - 2.4 - DEEP, 1.2),
			CFrame = self:_at(x, (top - 2.4 + DEEP) / 2, z),
			Color = rgb(235, 170, 30),
		})
	end
	part:SetAttribute("Piece", piece.Id)
end

-- A pad's flag: a pole at its left front corner with a green flag and the pad's number.
function ObbyOdyssey:_checkpointFlag(piece: Course.Piece)
	local x = piece.X - piece.W / 2 + 1.4
	local z = piece.Z - piece.D / 2 + 1.4
	self:_decor({
		Name = "FlagPole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(9, 0.4, 0.4),
		CFrame = upright(self.origin + Vector3.new(x, piece.Top + 4.5, z)),
		Color = rgb(255, 255, 255),
	})
	local flag = self:_decor({
		Name = "Flag",
		Size = Vector3.new(4, 2.6, 0.2),
		CFrame = self:_at(x + 2.2, piece.Top + 7.6, z),
		Color = CHECK_GREEN,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		Build.SurfaceText(flag, face, `✓{piece.Checkpoint}`, {
			PixelsPerStud = 20,
			Font = SIGN_FONT,
			TextColor3 = rgb(255, 255, 255),
			TextStrokeTransparency = 0.4,
		})
	end
	-- a glowing strip round the pad's top edge
	local y = piece.Top + 0.03
	for _, edge in
		{
			{ piece.W - 1, 0.5, piece.X, piece.Z - piece.D / 2 + 0.45 },
			{ piece.W - 1, 0.5, piece.X, piece.Z + piece.D / 2 - 0.45 },
		}
	do
		local glow = self:_decor({
			Name = "Glow",
			Size = Vector3.new(edge[1], 0.06, edge[2]),
			CFrame = self:_at(edge[3], y, edge[4]),
			Color = CHECK_GREEN,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			Parent = self.folders.Pads,
		})
		glow:SetAttribute("Checkpoint", piece.Checkpoint) -- (each client turns it gold once it's theirs)
	end
end

-- The blue tower: a block from the water to the third pad on its top, lighter bands and a stair pattern
-- up its front, a gold trim round the top.
function ObbyOdyssey:_buildTower()
	local pad = Course.Checkpoints[3]
	local x, z, top = pad.X, pad.Z, pad.Top
	local tower = Build.Part({
		Name = "Checkpoint3",
		Size = Vector3.new(pad.W, top - DEEP, pad.D),
		CFrame = self:_at(x, (top + DEEP) / 2, z),
		Color = PALETTE.Tower,
		Parent = self.folders.Pads,
	})
	tower:SetAttribute("Piece", pad.Id)
	tower:SetAttribute("Checkpoint", 3)
	for y = 4, top - 4, 6 do
		for _, face in { -1, 1 } do
			self:_decor({
				Name = "Band",
				Size = Vector3.new(pad.W + 0.1, 1.6, 0.2),
				CFrame = self:_at(x, y, z + face * (pad.D / 2 + 0.06)),
				Color = TOWER_LIGHT,
			})
		end
		for _, face in { -1, 1 } do
			self:_decor({
				Name = "Band",
				Size = Vector3.new(0.2, 1.6, pad.D + 0.1),
				CFrame = self:_at(x + face * (pad.W / 2 + 0.06), y, z),
				Color = TOWER_LIGHT,
			})
		end
	end
	-- windows: dark squares on the front, two to a floor
	for y = 7, top - 6, 6 do
		for _, offset in { -8, 8 } do
			self:_decor({
				Name = "Window",
				Size = Vector3.new(3, 3, 0.2),
				CFrame = self:_at(x + offset, y, z - pad.D / 2 - 0.08),
				Color = rgb(30, 60, 140),
			})
		end
	end
	self:_decor({
		Name = "Trim",
		Size = Vector3.new(pad.W + 0.3, 0.8, pad.D + 0.3),
		CFrame = self:_at(x, top - 0.5, z),
		Color = GOLD,
	})
	self:_checkpointFlag(pad)
	-- Battlements round the back and sides (out of reach of the course: decoration).
	for index = 0, 7 do
		self:_decor({
			Name = "Merlon",
			Size = Vector3.new(2.4, 2, 2.4),
			CFrame = self:_at(x - pad.W / 2 + 1.2 + index * (pad.W - 2.4) / 7, top + 1, z + pad.D / 2 - 1.2),
			Color = PALETTE.Tower,
		})
	end
end

-- The pink gantry over the bridge and its balls (each a model hinged on the gantry, swung on clients).
function ObbyOdyssey:_buildGantry()
	local bridge = Course.Bridge
	local first, last = Course.Balls[1], Course.Balls[#Course.Balls]
	local pivotY = first.PivotY
	local from, to = first.Z - 6, last.Z + 6
	self:_decor({
		Name = "Gantry",
		Size = Vector3.new(1.8, 1.8, to - from + 1.8),
		CFrame = self:_at(bridge.X, pivotY + 0.9, (from + to) / 2),
		Color = PINK,
	})
	for _, z in { from, to } do
		for _, side in { -1, 1 } do
			self:_decor({
				Name = "Post",
				Size = Vector3.new(1.6, pivotY + 2 - DEEP, 1.6),
				CFrame = self:_at(bridge.X + side * 9, (pivotY + 2 + DEEP) / 2, z),
				Color = PINK,
			})
		end
		self:_decor({
			Name = "Crossbar",
			Size = Vector3.new(19.6, 1.6, 1.6),
			CFrame = self:_at(bridge.X, pivotY + 1.4, z),
			Color = PINK,
		})
	end
	for _, ball in Course.Balls do
		local model = Build.Model(ball.Id)
		local hinge = self:_at(ball.X, ball.PivotY, ball.Z)
		self:_decor({
			Name = "Rod",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(ball.Length - ball.Radius + 0.4, 0.5, 0.5),
			CFrame = hinge * CFrame.new(0, -(ball.Length - ball.Radius) / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = rgb(70, 70, 80),
			Material = Enum.Material.Metal,
			Parent = model,
		})
		self:_decor({
			Name = "Ball",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * ball.Radius * 2,
			CFrame = hinge * CFrame.new(0, -ball.Length, 0),
			Color = PALETTE.Red,
			Parent = model,
		})
		self:_decor({
			Name = "Shine",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * ball.Radius * 0.7,
			CFrame = hinge * CFrame.new(-ball.Radius * 0.45, -ball.Length + ball.Radius * 0.5, -ball.Radius * 0.45),
			Color = rgb(255, 170, 170),
			Parent = model,
		})
		self:_decor({
			Name = "Hinge",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.4,
			CFrame = hinge,
			Color = GOLD,
			Parent = model,
		})
		model.WorldPivot = hinge
		model:SetAttribute("Ball", ball.Id)
		model.Parent = self.folders.Balls
	end
end

-- The summit's prize: a gold crown turning over the middle (clients turn it), between two checkered flags.
function ObbyOdyssey:_buildCrown()
	local summit = Course.Summit
	local crown = Build.Model("Crown")
	local center = self:_at(summit.X, summit.Top + 8.5, summit.Z)
	local radius, height = 4.2, 2.6
	for index = 0, 11 do
		local angle = index / 12 * math.pi * 2
		self:_decor({
			Name = "Band",
			Size = Vector3.new(2.3, height, 0.7),
			CFrame = center * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius),
			Color = GOLD,
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.15,
			Parent = crown,
		})
	end
	for index = 0, 5 do
		local angle = index / 6 * math.pi * 2
		local spike = center * CFrame.Angles(0, angle, 0) * CFrame.new(0, height / 2 + 1.2, -radius)
		self:_decor({
			Name = "Spike",
			Size = Vector3.new(2, 2, 0.6),
			CFrame = spike * CFrame.Angles(0, 0, math.rad(45)),
			Color = GOLD,
			Reflectance = 0.15,
			Parent = crown,
		})
		self:_decor({
			Name = "Pearl",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1,
			CFrame = spike * CFrame.new(0, 1.5, 0),
			Color = rgb(255, 255, 245),
			Parent = crown,
		})
		self:_decor({
			Name = "Jewel",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1,
			CFrame = center * CFrame.Angles(0, angle + math.pi / 6, 0) * CFrame.new(0, 0, -radius - 0.35),
			Color = if index % 2 == 0 then rgb(235, 40, 60) else rgb(60, 120, 255),
			Material = Enum.Material.Neon,
			Parent = crown,
		})
	end
	local glow = self:_decor({
		Name = "Glow",
		Size = Vector3.one,
		Transparency = 1,
		CFrame = center,
		Parent = crown,
	})
	Build.Light(glow, rgb(255, 220, 120), 24, 2)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(rgb(255, 230, 140))
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Lifetime = NumberRange.new(1, 1.8)
	sparkle.Speed = NumberRange.new(2, 4)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Rate = 6
	sparkle.Parent = glow
	crown.WorldPivot = center
	crown.Parent = self.context.Arena

	-- The checkered flags at the summit's back corners.
	for _, side in { -1, 1 } do
		local x = summit.X + side * (summit.W / 2 - 0.8)
		local z = summit.Z + summit.D / 2 - 0.8
		self:_decor({
			Name = "FlagPole",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(16, 0.6, 0.6),
			CFrame = upright(self.origin + Vector3.new(x, summit.Top + 8, z)),
			Color = rgb(250, 250, 250),
		})
		self:_decor({
			Name = "PoleTop",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.2,
			CFrame = self:_at(x, summit.Top + 16.2, z),
			Color = GOLD,
		})
		for row = 0, 2 do
			for column = 0, 3 do
				self:_decor({
					Name = "Check",
					Size = Vector3.new(1.5, 1.5, 0.2),
					CFrame = self:_at(x + side * (1.05 + column * 1.5), summit.Top + 15 - row * 1.5, z),
					Color = if (row + column) % 2 == 0 then rgb(25, 25, 30) else rgb(250, 250, 250),
				})
			end
		end
	end
end

-- The start: an arch over the start line with the game's name, bunting along the pad.
function ObbyOdyssey:_buildStart()
	local start = Course.Start
	local front = start.Z + start.D / 2 - 1
	local arch = Shapes.Arch(30, 15, 2, 2, self:_at(start.X, start.Top, front), {
		Name = "StartArch",
		Color = rgb(255, 84, 150),
		Parent = self.context.Arena,
	})
	arch.CanCollide = false
	arch.CanQuery = false
	arch.CanTouch = false
	local sign = self:_decor({
		Name = "Sign",
		Size = Vector3.new(26, 4.4, 1),
		CFrame = self:_at(start.X, start.Top + 17.2, front),
		Color = rgb(60, 40, 140),
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		Build.SurfaceText(sign, face, "OBBY ODYSSEY", {
			PixelsPerStud = 14,
			Font = SIGN_FONT,
			TextColor3 = GOLD,
			TextStrokeTransparency = 0.3,
		})
	end
	local bulbs = { rgb(255, 84, 150), rgb(64, 196, 255), rgb(255, 204, 64), rgb(110, 226, 140) }
	for index = 0, 9 do
		self:_decor({
			Name = "Bulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.9,
			CFrame = self:_at(start.X - 12.6 + index * 2.8, start.Top + 15.2, front - 0.7),
			Color = bulbs[index % #bulbs + 1],
			Material = Enum.Material.Neon,
		})
	end
end

-- The pool (water to the tower, lava after it), grassy banks with blocky trees, and hills far off.
-- None of it collides: a runner off the course always falls into the pool.
function ObbyOdyssey:_buildScenery()
	local split = Course.LavaFrom
	local back, ahead = -90, 470
	self:_decor({
		Name = "Water",
		Size = Vector3.new(220, 1, split - back),
		CFrame = self:_at(0, -0.5, (back + split) / 2),
		Color = rgb(40, 170, 245),
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		Reflectance = 0.06,
	})
	self:_decor({
		Name = "PoolFloor",
		Size = Vector3.new(220, 1, split - back),
		CFrame = self:_at(0, -10, (back + split) / 2),
		Color = rgb(30, 110, 190),
		Material = Enum.Material.Sand,
	})
	self:_decor({
		Name = "Lava",
		Size = Vector3.new(220, 1, ahead - split),
		CFrame = self:_at(0, -0.7, (split + ahead) / 2),
		Color = rgb(255, 105, 30),
		Material = Enum.Material.CrackedLava,
	})
	self:_decor({
		Name = "LavaGlow",
		Size = Vector3.new(218, 0.3, ahead - split - 2),
		CFrame = self:_at(0, -0.05, (split + ahead) / 2),
		Color = rgb(255, 150, 40),
		Material = Enum.Material.Neon,
		Transparency = 0.7,
	})
	for index = 0, 4 do
		local glow = self:_decor({
			Name = "LavaLight",
			Size = Vector3.one,
			Transparency = 1,
			CFrame = self:_at(0, 6, split + 30 + index * 60),
		})
		Build.Light(glow, rgb(255, 120, 40), 60, 1.2)
	end
	-- Grass banks on both sides and behind the start, with blocky trees.
	local grass = rgb(106, 188, 82)
	for _, side in { -1, 1 } do
		self:_decor({
			Name = "Bank",
			Size = Vector3.new(160, 8, ahead - back + 160),
			CFrame = self:_at(side * 190, -3, (back + ahead) / 2),
			Color = grass,
			Material = Enum.Material.Grass,
		})
	end
	for _, z in { back - 60, ahead + 60 } do
		self:_decor({
			Name = "Bank",
			Size = Vector3.new(540, 8, 120),
			CFrame = self:_at(0, -3, z),
			Color = grass,
			Material = Enum.Material.Grass,
		})
	end
	local rng = Random.new(7)
	local leaves = { rgb(80, 190, 90), rgb(110, 205, 80), rgb(60, 160, 90), rgb(140, 210, 85) }
	local function tree(x: number, z: number, scale: number)
		local trunkHeight = 6 * scale
		self:_decor({
			Name = "Trunk",
			Size = Vector3.new(2 * scale, trunkHeight, 2 * scale),
			CFrame = self:_at(x, 1 + trunkHeight / 2, z),
			Color = rgb(130, 85, 50),
		})
		local y = 1 + trunkHeight
		local color = leaves[rng:NextInteger(1, #leaves)]
		self:_decor({
			Name = "Leaves",
			Size = Vector3.new(7, 4, 7) * scale,
			CFrame = self:_at(x, y + 1.5 * scale, z),
			Color = color,
		})
		self:_decor({
			Name = "Leaves",
			Size = Vector3.new(4.5, 3, 4.5) * scale,
			CFrame = self:_at(x, y + 4.8 * scale, z),
			Color = color:Lerp(rgb(255, 255, 255), 0.12),
		})
	end
	for _, side in { -1, 1 } do
		for index = 0, 13 do
			tree(
				side * rng:NextNumber(118, 150),
				back + 20 + index * 38 + rng:NextNumber(-8, 8),
				rng:NextNumber(1.1, 1.8)
			)
			if index % 2 == 0 then
				tree(side * rng:NextNumber(165, 210), back + 40 + index * 38, rng:NextNumber(1.5, 2.3))
			end
		end
	end
	for index = 0, 8 do
		tree(-120 + index * 30 + rng:NextNumber(-6, 6), back - 30 - rng:NextNumber(0, 30), rng:NextNumber(1.2, 2))
		tree(-120 + index * 30 + rng:NextNumber(-6, 6), ahead + 25 + rng:NextNumber(0, 40), rng:NextNumber(1.6, 2.6))
	end
	-- Blocky hills on the horizon.
	for index = 0, 11 do
		local side = if index % 2 == 0 then -1 else 1
		local size = Vector3.new(rng:NextNumber(60, 90), rng:NextNumber(30, 60), rng:NextNumber(60, 100))
		self:_decor({
			Name = "Hill",
			Size = size,
			CFrame = self:_at(side * rng:NextNumber(250, 300), size.Y / 2 - 6, back + index * 60),
			Color = grass:Lerp(rgb(70, 140, 90), rng:NextNumber(0, 0.6)),
			Material = Enum.Material.Grass,
		})
	end
end

-- Prepare ---------------------------------------------------------------------------------------------

function ObbyOdyssey:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn" -- nobody is knocked out: a fall goes back to the last checkpoint
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 4 -- a few studs into the pool
	self.origin = ctx.Origin.Position
	self.runners = {} :: { [any]: Runner }
	self.blinks = {} :: { [string]: { Part: BasePart, Piece: Course.Piece } }
	self.grouped = {} :: { [Model]: boolean }
	self.finished = 0
	self.closeAt = nil :: number?
	self.ending = false
	self.racing = false
	-- The hazards run from now, so they're moving while the rules card shows; hits count from GO.
	self.epoch = ctx:Now()

	local arena = ctx.Arena
	self.folders = {
		Pads = Build.Folder("Pads", arena),
		Balls = Build.Folder("Balls", arena),
		Bars = Build.Folder("Bars", arena),
		Blinks = Build.Folder("Blinks", arena),
	}
	self:_buildScenery()
	self:_buildStart()
	self:_buildTower()
	for _, piece in Course.Pieces do
		self:_buildPiece(piece, self.folders)
	end
	self:_buildGantry()
	self:_buildCrown()

	local roster = {}
	for index, player in ctx:GetPlayers() do
		local slot = (index - 1) % 12 + 1
		self.runners[player] = {
			Slot = slot,
			Stage = 0,
			Row = 1,
			Progress = 0,
			Finish = nil,
			Place = nil,
			HitUntil = 0,
			SeenT = nil,
			Falls = 0,
			Hits = 0,
			Shown = 0,
			Gone = false,
		}
		local color = COLORS[slot]
		table.insert(roster, {
			U = player.UserId,
			L = slot,
			C = { math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5) },
			N = player.DisplayName,
		})
		ctx:SetScoreText(player, "0%")
	end
	ctx:SetSharedJSON("Course", {
		O = { self.origin.X, self.origin.Y, self.origin.Z },
		E = self.epoch,
		Riders = roster,
	})
	ctx:SetShared("Stage", "Ready")

	ctx.Hooks.Respawn = function(player)
		return self:_respawnAt(player)
	end
	ctx.Hooks.CharacterReady = function(_player, character)
		self:_joinGroup(character)
	end
	ctx.Hooks.PlayerLeft = function(player)
		local runner = self.runners[player]
		if runner then
			runner.Gone = true
		end
		self:_checkDone()
	end

	local points = {}
	for slot = 1, 12 do
		local x, y, z = Course.Respawn(0, slot)
		local position = self.origin + Vector3.new(x, y, z)
		table.insert(points, CFrame.lookAt(position, position + Vector3.zAxis))
	end
	-- (each runner on their own slot's spot)
	self.groupReady = setUpGroups()
	local spawnPoints = {}
	for index, player in ctx:GetPlayers() do
		local runner = self.runners[player]
		spawnPoints[index] = points[if runner then runner.Slot else index]
	end
	ctx:SpawnAll(spawnPoints, true)
	for player in self.runners do
		local character = ctx:GetCharacter(player)
		if character then
			self:_joinGroup(character)
		end
	end
	self:_share()
	ctx:SetStatus("Race to the 👑 crown!")
end

-- Where a runner goes back to after a fall (or a new character): their last checkpoint, or the summit once
-- they've finished. A fall after GO also splashes where they went in.
function ObbyOdyssey:_respawnAt(player): CFrame?
	local ctx = self.context
	local runner = self.runners[player]
	if not runner then
		return nil
	end
	local started = ctx.Started and not self.ending
	if started then
		local _, _, root = ctx:GetCharacter(player)
		local p = if root then root.Position - self.origin else nil
		-- (a fall into the pool, not a new character waiting in the lobby after a reset)
		if p and p.Y < 0 and p.Y > -80 and math.abs(p.X) < 120 and p.Z > -100 and p.Z < 480 then
			runner.Falls += 1
			runner.FellAt = Vector3.new(p.X, runner.Row, p.Z) -- (where, and from which row: for the checks)
			ctx:Fire(nil, "Splash", player.UserId, p.X, p.Z, p.Z >= Course.LavaFrom)
		end
	end
	local x, y, z
	if runner.Finish then
		local summit = Course.Summit
		x, y, z = summit.X + (runner.Slot % 4 - 1.5) * 2.4, summit.Top, summit.Z - 3 + math.floor(runner.Slot / 4) * 2
		runner.Row = summit.Row
	else
		x, y, z = Course.Respawn(runner.Stage, runner.Slot)
		local pad = if runner.Stage <= 0 then Course.Start else Course.Checkpoints[runner.Stage]
		runner.Row = pad.Row
	end
	runner.SeenT = nil
	runner.HitUntil = os.clock() + 0.5
	if started then
		ctx:Fire(player, "Respawned", runner.Stage)
		if not runner.Finish then
			Notifier.Send(
				player,
				if runner.Stage > 0 then `Splash! Back to checkpoint {runner.Stage}` else "Splash! Back to the start",
				"info",
				2
			)
		end
	end
	local position = self.origin + Vector3.new(x, y, z)
	return CFrame.lookAt(position, position + Vector3.zAxis)
end

-- Start ------------------------------------------------------------------------------------------------

function ObbyOdyssey:Start()
	local ctx = self.context
	self.racing = true
	self.startAt = ctx:Now()
	ctx:SetShared("Stage", "Race")
	ctx:Heartbeat(function()
		self:_step()
	end)
	local shared = 0
	ctx:Heartbeat(function(dt)
		shared += dt
		if shared >= SHARE_EVERY then
			shared = 0
			self:_score()
			self:_share()
		end
	end)
end

-- One look at every runner: hazards (as their screen showed them), checkpoints and the finish; and the
-- blinking blocks for the bots.
function ObbyOdyssey:_step()
	local ctx = self.context
	if self.ending then
		return
	end
	local now = ctx:Now()
	local t = now - self.epoch
	for _, blink in self.blinks do
		local solid = Course.Solid(blink.Piece, t)
		if blink.Part.CanCollide ~= solid then
			blink.Part.CanCollide = solid
		end
	end
	local clock = os.clock()
	for player, runner in self.runners do
		if runner.Gone or not ctx:IsAlive(player) then
			continue
		end
		local _, humanoid, root = ctx:GetCharacter(player)
		if not humanoid or not root then
			continue
		end
		local p = root.Position - self.origin
		local feet = feetOf(humanoid, root) - self.origin.Y
		local seen = t - oneWay(player)
		local last = runner.SeenT or seen
		last = math.clamp(last, seen - 0.1, seen)
		runner.SeenT = seen
		if not runner.Finish and clock >= runner.HitUntil and not humanoid.PlatformStand then
			self:_hazards(player, runner, p, feet, last, seen)
		end
		local stage, row, piece = Course.Step(runner.Stage, runner.Row, p.X, p.Z, feet, seen)
		if stage > runner.Stage and not runner.Finish then
			runner.Stage = stage
			ctx:Fire(player, "Checkpoint", stage)
			local section = Course.Sections[stage + 1]
			Notifier.Send(player, `CHECKPOINT {stage}! Next: {section.Icon} {section.Name}`, "success", 2.5)
		end
		runner.Row = row
		runner.Progress = Course.Progress(runner.Row, p.X, feet, p.Z)
		if piece and piece.Finish and not runner.Finish then
			self:_finish(player, runner, now)
		end
	end
	if self.closeAt and now >= self.closeAt then
		self:_end("CrownClosed")
	end
end

function ObbyOdyssey:_hazards(player, runner: Runner, p: Vector3, feet: number, last: number, seen: number)
	for _, ball in Course.Balls do
		if math.abs(p.Z - ball.Z) > ball.Radius + Course.Body + 0.5 then
			continue
		end
		if Course.BallHits(ball, seen, p.X, feet, p.Z) then
			local heading = Course.BallHeading(ball, seen)
			self:_hit(player, runner, Vector3.new(heading * BALL_PUSH, BALL_LIFT, 0), BALL_STUN, p)
			return
		end
	end
	for _, spinner in Course.Spinners do
		local hit, px, pz = Course.SpinnerHits(spinner, last, seen, p.X, feet, p.Z)
		if hit then
			self:_hit(player, runner, Vector3.new(px * BAR_PUSH, BAR_LIFT, pz * BAR_PUSH), BAR_STUN, p)
			return
		end
	end
end

function ObbyOdyssey:_hit(player, runner: Runner, velocity: Vector3, stun: number, p: Vector3)
	local ctx = self.context
	runner.HitUntil = os.clock() + HIT_COOLDOWN
	runner.Hits += 1
	ctx:Knockback(player, velocity, stun)
	ctx:Fire(nil, "Bonk", player.UserId, p.X, p.Y, p.Z)
end

-- A runner reached the crown: their place, the cheer, the finish clock for everyone else.
function ObbyOdyssey:_finish(player, runner: Runner, now: number)
	local ctx = self.context
	-- (their place among the finishers still here: one who left gives up theirs, as in the results)
	local place = 1
	for _, other in self.runners do
		if other ~= runner and other.Place and not other.Gone then
			place += 1
		end
	end
	self.finished += 1
	runner.Finish = now
	runner.Place = place
	runner.Stage = #Course.Checkpoints
	local time = now - (self.startAt or now)
	ctx:SetScoreText(player, `{Course.Ordinal(place)} · {string.format("%.1f", time)}s`)
	ctx:Fire(nil, "Finish", player.UserId, place, time)
	Notifier.Send(
		player,
		if place == 1 then "👑 YOU GOT THE CROWN!" else `👑 You made it, {Course.Ordinal(place)}!`,
		"success",
		3
	)
	if self.finished == 1 then
		ctx:Announce(`👑 {player.DisplayName} reached the crown!`, "success", 3)
		ctx:Sound("Victory")
		self.closeAt = now + FINISH_CLOCK
		ctx:SetShared("CloseAt", self.closeAt)
	end
	self:_checkDone()
end

-- The standings: finishers by place, the rest by how far along the course they are.
function ObbyOdyssey:_score()
	local ctx = self.context
	local leader, best = nil, -1
	for player, runner in self.runners do
		if runner.Gone or not ctx:State(player) then
			continue
		end
		local percent = math.floor(math.clamp(runner.Progress / Course.Length, 0, 1) * 100)
		local score = if runner.Place then 1000 - runner.Place else percent
		if score ~= runner.Shown then
			ctx:AddScore(player, score - runner.Shown)
			runner.Shown = score
			if not runner.Place then
				ctx:SetScoreText(player, `{percent}%`)
			end
		end
		if score > best then
			leader, best = player, score
		end
	end
	if self.closeAt then
		local left = math.max(0, math.ceil(self.closeAt - ctx:Now()))
		ctx:SetStatus(`👑 The crown closes in {left}s!`)
	elseif leader and self.racing and ctx:Now() - (self.startAt or 0) > 6 then
		ctx:SetStatus(`🏃 {leader.DisplayName} leads!`)
	end
end

-- Every runner for the clients' race strip.
function ObbyOdyssey:_share()
	local list = {}
	for player, runner in self.runners do
		if runner.Gone then
			continue
		end
		list[tostring(player.UserId)] = {
			P = math.floor(runner.Progress * 10) / 10,
			S = runner.Stage,
			F = runner.Place,
			T = if runner.Finish then math.floor((runner.Finish - (self.startAt or 0)) * 10) / 10 else nil,
		}
	end
	self.context:SetSharedJSON("Runners", { T = self.context:Now(), R = list })
end

function ObbyOdyssey:_checkDone()
	if not self.racing or self.ending then
		return
	end
	for player, runner in self.runners do
		if not runner.Gone and not runner.Finish and self.context:State(player) then
			return
		end
	end
	self:_end("Finished")
end

function ObbyOdyssey:_end(reason: string)
	if self.ending then
		return
	end
	self.ending = true
	local ctx = self.context
	self:_score()
	self:_share()
	ctx:SetShared("Stage", "Done")
	ctx:Delay(if reason == "Finished" then 2.5 else 0.3, function()
		ctx:End(reason)
	end)
end

-- Time's up (or the round ended another way): the standings as they are.
function ObbyOdyssey:Stop(_reason)
	if self.runners and not self.ending then
		self.ending = true
		self:_score()
		self:_share()
		self.context:SetShared("Stage", "Done")
	end
end

-- Finish order first, then how far along the course each runner got.
function ObbyOdyssey:GetResults()
	local ctx = self.context
	local entries = {}
	local home = {}
	for player in ctx.Participants do
		local runner = self.runners[player]
		if player.Parent and runner and runner.Finish then
			table.insert(home, runner)
		end
	end
	table.sort(home, function(a, b)
		return (a.Finish :: number) < (b.Finish :: number)
	end)
	local places = {}
	for index, runner in home do
		places[runner] = index -- (a finisher who left gives up their place)
	end
	for player in ctx.Participants do
		local runner = self.runners[player]
		if not player.Parent or not runner then
			continue
		end
		local place = places[runner]
		if place then
			table.insert(entries, {
				Player = player,
				Rank = 1e6 - place,
				ScoreText = `👑 {Course.Ordinal(place)} · {string.format(
					"%.1f",
					(runner.Finish :: number) - (self.startAt or 0)
				)}s`,
				BestScore = 100,
			})
		else
			local progress = math.clamp(runner.Progress, 0, Course.Length)
			local percent = math.floor(progress / Course.Length * 100)
			table.insert(entries, {
				Player = player,
				Rank = runner.Stage * 10000 + progress,
				ScoreText = if runner.Stage > 0
					then `✓{runner.Stage} · {percent}% of the way`
					else `{percent}% of the way`,
				BestScore = percent,
			})
		end
	end
	return { Entries = entries }
end

return ObbyOdyssey

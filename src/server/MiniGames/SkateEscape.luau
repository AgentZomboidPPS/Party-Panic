-- Skate Escape (Race, 55s, 1-12 players). After Mario Party 2's "Skateboard Scamper": everyone
-- races on a skateboard, pushing to build speed and jumping the obstacles, first to the goal wins.
-- Here twelve lanes run down a long wooden bridge over a lava canyon. PUSH (mash it) kicks you faster,
-- JUMP ollies over crates, striped barriers and gaps in the bridge; miss one and you wipe out for a
-- moment. Boost pads throw you forward. The bridge crumbles into the lava behind the pack at a set
-- pace, so slowpokes fall and are out. Ranking: finish order, then how far you got.
--
-- How it works: the race is simulated on the server with the shared rules in
-- Shared/Logic/SkateCourse (distance, speed, ollies, wipeouts), for players and bots alike. A player's
-- PUSH and JUMP are actions; their own client runs the same rules to move its character at once, so
-- it feels instant, and follows the server's numbers (MG_Racers) when they disagree. A client can only
-- ever ask to push or jump, at a limited rate, so it can't skate faster or teleport ahead: the server's
-- distances decide the finish, the collapse and the results. A jump that arrives just after the
-- server's skater reached an obstacle still counts if it would have cleared it, allowing for ping.
-- Bots skate the same simulation and the server moves their characters; the collapse (animated on
-- clients from the shared schedule MG_Collapse) is checked against everyone's distance here.
--
-- Judged by what the skater sees (hitbox pass, owner: "the precision games will feel super bad if we
-- dont"): crates and barriers by the board's wheels over the whole obstacle, gaps and the collapse
-- only once no wheel is left on the planks, boost pads wherever a wheel touches (Shared/Logic/
-- SkateCourse). A jump counts from the spot the player pressed it on their own screen, and the
-- collapse allows for how far ahead their screen draws them, so ping never decides a wipeout or a fall.
--
-- The start (owner: "it spawns you when the game starts not on the bridge and you kinda just float to
-- the bridge", on the countdown and at GO): every skater is put exactly where their own screen draws
-- them (their lane, the start line, on the board at their avatar's riding height) and held there by
-- the server until GO: anchored, so neither gravity, nor a late position report from a phone still
-- loading the arena, nor the order things arrive in can move them on anyone's screen. At GO each is
-- let go from that same spot: a player's character goes back to their own device, a bot's stays the
-- server's (anchoring drops the owner a part was given, and Roblox would hand the bot to the nearest
-- player's device, which then fights the server over where it is).
--
-- Audit pass (owner: "it just has to work"): the live standings scored riders in whole percents, so
-- riders up to 14 studs apart tied, and the standings list a tie by account, not by who's ahead (a
-- phone showed "2. you 44%" beside the race HUD's "1st of 6"). They score in studs now, ranked like
-- the results. The collapse reaching the finish line allows for each rider's lead on their own
-- screen, like it does the rest of the race (Shared/Logic/SkateCourse.Caught).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local SkateCourse = require(ReplicatedStorage.Shared.Logic.SkateCourse)

local MiniGame = require(script.Parent.Kit.MiniGame)
local Scenery = require(script.Parent.Kit.Scenery)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local Shapes = require(script.Parent.Parent.World.Shapes)

local SkateEscape = MiniGame.Define("SkateEscape")

local LANES = 12
local SEGMENT = 24 -- deck pieces are at most this long (each crumbles on its own)
local DECK_WIDTH = 100
local DECK_MESH_LENGTH = 24
local LAVA_DROP = 34 -- where a fallen skater is out (KillY)
local START_BACK = 36 -- the start pad behind the line
local GOAL_DEPTH = 70

-- The look (art pass, owner: "make it a dramatic, memorable run"): the bridge crosses a deep canyon
-- of layered red rock with lava falls, a glowing lava river far below. Stone viaduct piers carry
-- rope towers whose swag ropes stream past the racers; a striped start gate, and a giant checkered
-- stone arch with a golden trophy at the goal, in front of a smoking volcano at the canyon's end.
-- The bridge is the highest thing around: the canyon's rims and the plateau sit a few studs under the
-- deck, so from a skater's camera there's open air past the rails and the drop reads.
local LAVA_DEPTH = 46 -- the lava river's surface below the deck (a fallen skater reaches it before respawning)
local WALL_FOOT = -(LAVA_DEPTH + 2) -- canyon walls stand with their foot 2 studs under the lava
local PIER_FOOT = -66 -- the piers are taller: their foot stays under the lava as they tip over in the collapse
local RIM_TOP = -10 -- the plateau round the canyon (a canyon wall's top rolls down to it at the back)
local WALL_X = 92 -- the canyon walls' foot, either side of the middle
local WALL_PIVOT = 28.99 -- a canyon wall's pivot sits this far behind its foot (unscaled)
local CABLE_PIVOT = 2.54 -- a swag rope's pivot sits this far outside the rail
local CABLE_SPAN = 96 -- a swag rope's authored length
local RAIL_X = DECK_WIDTH / 2 - 0.6
-- The canyon's end walls stand inside the start and goal cliffs (so no cliff shows its flat back),
-- and the volcano rises from the plain right behind the finish arch.
local CANYON_BACK = -48 -- the canyon runs from the start cliff ...
local CANYON_END = 1428 -- ... to the goal cliff (SkateCourse.Length is 1400)

local PUSH_RATE = 12 -- pushes a second the server takes on average ...
local PUSH_BURST = 3 -- ... and how many may arrive at once
local KIND_PROP = { Crate = "SkateCrate", Barrier = "SkateBarrier", Boost = "SkateBoost" }

local rng = Random.new()

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function round(x: number, step: number): number
	return math.floor(x / step + 0.5) * step
end

local function ambient(emitter: ParticleEmitter, parent: Instance)
	emitter.Parent = parent
	CollectionService:AddTag(emitter, "PP_Ambient")
end

-- Stretches a prop along its own X and Z without changing its height; MeshParts take any size. (Its
-- parts must be lined up with the prop, as the meshes and fallbacks here are.)
local function stretch(model: Model, factorX: number, factorZ: number)
	if math.abs(factorX - 1) < 0.001 and math.abs(factorZ - 1) < 0.001 then
		return
	end
	local pivot = model:GetPivot()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local relative = pivot:ToObjectSpace(part.CFrame)
			local scale = relative.Rotation:VectorToObjectSpace(Vector3.new(factorX, 1, factorZ))
			part.Size = part.Size * Vector3.new(math.abs(scale.X), math.abs(scale.Y), math.abs(scale.Z))
			part.CFrame = pivot * CFrame.new(relative.X * factorX, relative.Y, relative.Z * factorZ) * relative.Rotation
		end
	end
end

-- Stretches a prop along Z (its length).
local function stretchZ(model: Model, factor: number)
	stretch(model, 1, factor)
end

-- Arena ------------------------------------------------------------------------------------------

function SkateEscape:_deckPiece(index: number, d0: number, d1: number): Model
	local ctx = self.context
	local origin = self.origin
	local model = Build.Model(`Seg{index}`) -- parented once its distances are set (clients read them)
	model:SetAttribute("D0", d0)
	model:SetAttribute("D1", d1)
	local length = d1 - d0
	local middle = origin + Vector3.new(0, 0, -(d0 + d1) / 2)
	local deck = MeshLibrary.Get("SkateDeck", {
		CFrame = CFrame.new(middle - Vector3.new(0, 2, 0)),
		Parent = model,
	})
	stretchZ(deck, length / DECK_MESH_LENGTH)
	for _, side in { -1, 1 } do
		local rail = MeshLibrary.Get("SkateRail", {
			CFrame = CFrame.new(middle + Vector3.new(side * (DECK_WIDTH / 2 - 0.6), 0, 0)),
			Parent = model,
		})
		stretchZ(rail, length / DECK_MESH_LENGTH)
	end
	model.PrimaryPart = deck.PrimaryPart
	-- (Devices move the piece from here as the bridge collapses: a model can reach them before its
	-- parts, and then its own pivot reads as the world's middle, which is the lobby.)
	model:SetAttribute("Pivot", model:GetPivot())
	model.Parent = ctx.Arena
	return model
end

function SkateEscape:_torch(parent: Instance, position: Vector3, light: boolean)
	local torch = MeshLibrary.Get("SkateTorch", { CFrame = CFrame.new(position), Parent = parent })
	local flame = Build.Decor({
		Name = "Flame",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.1, 1.1, 1.1),
		CFrame = CFrame.new(position + Vector3.new(0, 4.1, 0)),
		Color = rgb(255, 150, 50),
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		Parent = torch,
	})
	if light then
		Build.Light(flame, rgb(255, 140, 60), 26, 1.6)
	end
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(rgb(255, 200, 90), rgb(255, 90, 30))
	fire.LightEmission = 1
	fire.Size = NumberSequence.new(1.1, 0.2)
	fire.Lifetime = NumberRange.new(0.4, 0.7)
	fire.Speed = NumberRange.new(2, 4)
	fire.Rate = 14
	fire.SpreadAngle = Vector2.new(10, 10)
	fire.EmissionDirection = Enum.NormalId.Top
	ambient(fire, flame)
end

-- The canyon the bridge crosses: a lava river far below between walls of layered rock with lava
-- falls, closed at both ends, a red-rock plateau out to the horizon and volcanoes beyond.
function SkateEscape:_canyon()
	local ctx = self.context
	local origin = self.origin
	local arena = ctx.Arena
	local span = CANYON_END - CANYON_BACK
	local middleZ = origin.Z - (CANYON_BACK + CANYON_END) / 2

	-- The river: cracked lava under a see-through glowing sheet, with heat haze.
	local surface = Vector3.new(origin.X, origin.Y - LAVA_DEPTH, middleZ)
	local lava = Build.Part({
		Name = "Lava",
		Size = Vector3.new(2 * WALL_X + 130, 2, span + 40),
		CFrame = CFrame.new(surface - Vector3.new(0, 1, 0)),
		Color = rgb(255, 110, 34),
		Material = Enum.Material.CrackedLava,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = arena,
	})
	Build.Decor({
		Name = "LavaGlow",
		Size = Vector3.new(2 * WALL_X + 126, 0.4, span + 36),
		CFrame = CFrame.new(surface + Vector3.new(0, 0.3, 0)),
		Color = rgb(255, 110, 30),
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		Parent = arena,
	})
	-- (The sparks drifting up past the rails follow each player's camera: see the client.)
	local haze = Instance.new("ParticleEmitter")
	haze.Texture = "rbxasset://textures/particles/smoke_main.dds"
	haze.Color = ColorSequence.new(rgb(255, 150, 100), rgb(140, 90, 90))
	haze.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.84),
		NumberSequenceKeypoint.new(1, 1),
	})
	haze.Size = NumberSequence.new(14, 30)
	haze.Lifetime = NumberRange.new(6, 9)
	haze.Speed = NumberRange.new(3, 6)
	haze.EmissionDirection = Enum.NormalId.Top
	haze.Rate = 8
	ambient(haze, lava)

	-- The walls: 200-stud stretches along both sides, overlapping a little, each a little different in
	-- size and set-back (so no two ledges share a height), facing the bridge. The first and last tuck
	-- their ends into the end walls.
	local first, last = CANYON_BACK - 12 - 30 + 100, CANYON_END + 12 + 30 - 100
	local count = math.ceil((last - first) / 190)
	for _, side in { -1, 1 } do
		for index = 0, count do
			local d = first + (last - first) * index / count + rng:NextNumber(-4, 4)
			local scale = rng:NextNumber(0.97, 1.03)
			local foot = WALL_X + rng:NextNumber(-5, 5)
			local position = Vector3.new(
				origin.X + side * (foot + WALL_PIVOT * scale),
				origin.Y + WALL_FOOT - rng:NextNumber(0, 1),
				origin.Z - d
			)
			MeshLibrary.Get("SkateCanyonWall", {
				Scale = scale,
				CFrame = CFrame.lookAt(position, position - Vector3.new(side, 0, 0)),
				Parent = arena,
			})
		end
	end
	-- Both ends closed by a wall facing down the canyon.
	for _, ending in { { D = CANYON_BACK - 12, Turn = 0 }, { D = CANYON_END + 12, Turn = math.pi } } do
		local back = if ending.Turn == 0 then 1 else -1 -- which way (in Z) the wall's pivot sits from its foot
		local position = origin + Vector3.new(0, WALL_FOOT - 0.5, -ending.D + back * WALL_PIVOT * 1.04)
		MeshLibrary.Get("SkateCanyonWall", {
			Scale = 1.04,
			CFrame = CFrame.new(position) * CFrame.Angles(0, ending.Turn, 0),
			Parent = arena,
		})
	end

	-- The plateau around the canyon's rim, out to the horizon (four slabs round the canyon, thick so
	-- no gap shows under their edges).
	local top = origin.Y + RIM_TOP
	local thick = 24
	local rimY = top - thick / 2
	local outer = 1000
	for _, side in { -1, 1 } do
		for _, half in { -1, 1 } do
			local inner = WALL_X + 48
			Build.Part({
				Name = "Plateau",
				Size = Vector3.new(outer - inner, thick, (span + 1400) / 2),
				CFrame = CFrame.new(origin.X + side * (inner + outer) / 2, rimY, middleZ + half * (span + 1400) / 4),
				Color = rgb(150, 72, 64),
				Material = Enum.Material.Sandstone,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Parent = arena,
			})
		end
	end
	for _, ending in
		{ { From = CANYON_BACK - 70, To = CANYON_BACK - 690 }, { From = CANYON_END + 70, To = CANYON_END + 690 } }
	do
		Build.Part({
			Name = "Plateau",
			Size = Vector3.new(2 * (WALL_X + 48) + 2, thick, math.abs(ending.To - ending.From)),
			CFrame = CFrame.new(origin.X, rimY - 0.4, origin.Z - (ending.From + ending.To) / 2),
			Color = rgb(150, 72, 64),
			Material = Enum.Material.Sandstone,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = arena,
		})
	end

	-- Rock spires: some standing in the lava by the walls' feet, more along the rim against the sky.
	for _, side in { -1, 1 } do
		local d = 20 + rng:NextNumber(0, 60)
		while d < CANYON_END - 60 do
			MeshLibrary.Get("Spire", {
				Scale = rng:NextNumber(1.6, 2.6),
				CFrame = CFrame.new(origin.X + side * rng:NextNumber(66, 82), origin.Y - LAVA_DEPTH - 1, origin.Z - d)
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = arena,
			})
			d += rng:NextNumber(150, 260)
		end
		d = CANYON_BACK - 200 + rng:NextNumber(0, 60)
		while d < CANYON_END + 200 do
			MeshLibrary.Get("Spire", {
				Scale = rng:NextNumber(1.8, 3.6),
				CFrame = CFrame.new(origin.X + side * rng:NextNumber(170, 260), top - 1, origin.Z - d)
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = arena,
			})
			d += rng:NextNumber(90, 160)
		end
	end

	-- Layered buttes out on the plateau for a rugged horizon (one cheap mesa each).
	for _, side in { -1, 1 } do
		local d = rng:NextNumber(-400, -200)
		while d < CANYON_END + 400 do
			MeshLibrary.Get("SkateButte", {
				Scale = rng:NextNumber(0.7, 1.15),
				CFrame = CFrame.new(
					origin.X + side * rng:NextNumber(330, 520),
					top - rng:NextNumber(3, 6),
					origin.Z - d
				) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0),
				Parent = arena,
			})
			d += rng:NextNumber(560, 760)
		end
	end

	-- The big volcano at the canyon's end (the goal arch stands in front of it), two more on the plain.
	local plain = Vector3.new(origin.X, top, origin.Z)
	Scenery.Volcano(ctx, plain + Vector3.new(0, -2, -(CANYON_END + 300)), origin, 4.2)
	Scenery.Volcano(ctx, plain + Vector3.new(-560, -2, -(CANYON_END - 260)), origin, 2.6)
	Scenery.Volcano(ctx, plain + Vector3.new(620, -2, -(CANYON_END - 620)), origin, 2.2)
	Scenery.Volcano(ctx, plain + Vector3.new(-640, -2, -200), origin, 1.8)
end

function SkateEscape:_buildArena()
	local ctx = self.context
	local origin = self.origin
	local length = SkateCourse.Length
	local arena = ctx.Arena

	self:_canyon()

	-- The bridge, cut into pieces that crumble one by one, with gaps where the obstacles say.
	local cuts = {}
	for _, o in self.obstacles do
		if o.Kind == "Gap" then
			table.insert(cuts, { o.D - o.Len / 2, o.D + o.Len / 2 })
		end
	end
	local pieces = {}
	local cursor = 0
	local cutIndex = 1
	while cursor < length - 0.01 do
		local cut = cuts[cutIndex]
		local stop = math.min(length, cursor + SEGMENT)
		if cut and stop > cut[1] then
			stop = cut[1]
		end
		if stop - cursor > 0.5 then
			table.insert(pieces, self:_deckPiece(#pieces + 1, cursor, stop))
		end
		cursor = stop
		if cut and cursor >= cut[1] - 0.01 then
			cursor = cut[2]
			cutIndex += 1
			-- A raised curb of yellow and black blocks on both lips, so the drop reads at speed.
			local blocks = 14
			local width = (DECK_WIDTH - 2) / blocks
			for side, lip in { cut[1] - 0.8, cut[2] + 0.8 } do
				for block = 0, blocks - 1 do
					local curb = Build.Decor({
						Name = "GapLip",
						Size = Vector3.new(width, 0.3, 1.6),
						CFrame = CFrame.new(
							origin + Vector3.new(-(DECK_WIDTH - 2) / 2 + (block + 0.5) * width, 0.17, -lip)
						),
						Color = if (block + side) % 2 == 0 then rgb(255, 200, 40) else rgb(34, 28, 34),
						Material = if (block + side) % 2 == 0 then Enum.Material.Neon else Enum.Material.Metal,
						Parent = arena,
					})
					curb:SetAttribute("At", lip)
				end
			end
			-- A warning banner across the deck well before the gap: it stands up, so it shows from far.
			local at = cut[1] - 28
			local banner = Build.Decor({
				Name = "GapLip",
				Size = Vector3.new(DECK_WIDTH - 4, 3.4, 0.5),
				CFrame = CFrame.new(origin + Vector3.new(0, 16.1, -at)),
				Color = rgb(34, 28, 34),
				Material = Enum.Material.Metal,
				Parent = arena,
			})
			banner:SetAttribute("At", at)
			Build.SurfaceText(banner, Enum.NormalId.Back, "⚠  GAP AHEAD  •  JUMP!  ⚠", {
				PixelsPerStud = 12,
				TextColor3 = rgb(255, 210, 60),
				TextStrokeTransparency = 0.4,
			})
			for _, y in { 14.15, 18.05 } do
				local trim = Build.Decor({
					Name = "GapLip",
					Size = Vector3.new(DECK_WIDTH - 4, 0.3, 0.6),
					CFrame = CFrame.new(origin + Vector3.new(0, y, -at)),
					Color = rgb(255, 200, 40),
					Material = Enum.Material.Neon,
					Parent = arena,
				})
				trim:SetAttribute("At", at)
			end
			for _, sideX in { -1, 1 } do
				local post = Build.Decor({
					Name = "GapLip",
					Size = Vector3.new(0.8, 18.2, 0.8),
					CFrame = CFrame.new(origin + Vector3.new(sideX * (DECK_WIDTH / 2 - 1.5), 9.1, -at)),
					Color = rgb(52, 44, 50),
					Material = Enum.Material.Metal,
					Parent = arena,
				})
				post:SetAttribute("At", at)
			end
		end
	end
	self.pieces = pieces
	local function pieceAt(d: number): Instance
		for _, piece in pieces do
			if d >= piece:GetAttribute("D0") and d <= piece:GetAttribute("D1") then
				return piece
			end
		end
		return arena
	end
	-- Gap lips belong to the deck piece they sit on, so they fall with it.
	for _, lip in arena:GetChildren() do
		if lip.Name == "GapLip" then
			lip.Parent = pieceAt(lip:GetAttribute("At"))
		end
	end

	-- Stone piers under the bridge about every 96 studs, their rope towers joined by swag ropes. Each
	-- belongs to its deck piece, so it falls with it.
	local pylons = {}
	local carries: { [Instance]: boolean } = {}
	local last = -math.huge
	for _, piece in pieces do
		local d0, d1 = piece:GetAttribute("D0"), piece:GetAttribute("D1")
		local middle = (d0 + d1) / 2
		if d1 - d0 > 20 and middle > 30 and middle - last >= 90 and middle < length - 30 then
			last = middle
			carries[piece] = true
			MeshLibrary.Get(
				"SkatePylon",
				{ CFrame = CFrame.new(origin + Vector3.new(0, PIER_FOOT, -middle)), Parent = piece }
			)
			table.insert(pylons, { D = middle, Piece = piece })
			if #pylons % 2 == 1 then
				-- An orange underglow on the beams and rail edges, as if from the lava below.
				local glow = Build.Decor({
					Name = "Underglow",
					Size = Vector3.one,
					Transparency = 1,
					CFrame = CFrame.new(origin + Vector3.new(0, -6, -middle)),
					Parent = piece,
				})
				Build.Light(glow, rgb(255, 110, 40), 56, 1.8)
			end
		end
	end
	for index = 1, #pylons - 1 do
		local a, b = pylons[index], pylons[index + 1]
		local gap = b.D - a.D
		if gap <= 130 then
			for _, side in { -1, 1 } do
				local cable = MeshLibrary.Get("SkateCable", {
					CFrame = CFrame.new(origin + Vector3.new(side * (RAIL_X + CABLE_PIVOT), 3.3, -(a.D + b.D) / 2))
						* CFrame.Angles(0, if side < 0 then math.pi else 0, 0),
					Parent = a.Piece,
				})
				stretchZ(cable, gap / CABLE_SPAN)
			end
		end
	end

	-- Torches along both rails between the piers, lit every other one.
	local torchIndex = 0
	for index, piece in pieces do
		if index % 3 == 0 and not carries[piece] then
			torchIndex += 1
			local d = (piece:GetAttribute("D0") + piece:GetAttribute("D1")) / 2
			for _, side in { -1, 1 } do
				self:_torch(piece, origin + Vector3.new(side * (DECK_WIDTH / 2 - 0.6), 0, -d), torchIndex % 2 == 1)
			end
		end
	end

	-- Obstacles: the same thing at the same distance in every lane.
	for _, o in self.obstacles do
		local prop = KIND_PROP[o.Kind]
		if not prop then
			continue
		end
		local parent = pieceAt(o.D)
		for lane = 1, LANES do
			local x = SkateCourse.LaneX(lane, LANES)
			MeshLibrary.Get(prop, {
				CFrame = CFrame.new(origin + Vector3.new(x, 0, -o.D)),
				Parent = parent,
			})
		end
	end

	-- The start pad (it crumbles first): the bridge's planks on a stone plinth with red and white curbs
	-- and a dark basalt lip, the start gate and lane numbers.
	local start = Build.Model("Seg0")
	start:SetAttribute("D0", -START_BACK)
	start:SetAttribute("D1", 0)
	local plinthTop = -2.2 -- just under the planks' beams
	local plinthLength = START_BACK + 3
	local pad = Shapes.Slab(Vector3.new(DECK_WIDTH + 24, 6, plinthLength), 2, {
		Name = "StartPad",
		CFrame = CFrame.new(origin + Vector3.new(0, plinthTop - 3, plinthLength / 2)),
		Color = rgb(168, 140, 122),
		Material = Enum.Material.Slate,
		Parent = start,
	})
	local planks = MeshLibrary.Get("SkateDeck", {
		CFrame = CFrame.new(origin + Vector3.new(0, -2, START_BACK / 2)),
		Parent = start,
	})
	stretchZ(planks, START_BACK / DECK_MESH_LENGTH)
	Build.Decor({
		Name = "PadLip",
		Size = Vector3.new(DECK_WIDTH + 22, 1.6, 0.6),
		CFrame = CFrame.new(origin + Vector3.new(0, plinthTop - 1.6, plinthLength + 0.25)),
		Color = rgb(60, 42, 50),
		Material = Enum.Material.Basalt,
		Parent = start,
	})
	-- Curbs: along the back edge, and down both sides behind the gate's towers.
	local backBlocks = 14
	local backWidth = (DECK_WIDTH + 22) / backBlocks
	for block = 0, backBlocks - 1 do
		Build.Decor({
			Name = "PadCurb",
			Size = Vector3.new(backWidth, 0.8, 1.6),
			CFrame = CFrame.new(
				origin
					+ Vector3.new(
						-(DECK_WIDTH + 22) / 2 + (block + 0.5) * backWidth,
						plinthTop + 0.4,
						plinthLength - 1.4
					)
			),
			Color = if block % 2 == 0 then rgb(236, 66, 54) else rgb(250, 246, 236),
			Parent = start,
		})
	end
	for _, side in { -1, 1 } do
		local from, to = 11, plinthLength - 2.2
		local blocks = 6
		local depth = (to - from) / blocks
		for block = 0, blocks - 1 do
			Build.Decor({
				Name = "PadCurb",
				Size = Vector3.new(1.6, 0.8, depth),
				CFrame = CFrame.new(
					origin + Vector3.new(side * (DECK_WIDTH / 2 + 10.4), plinthTop + 0.4, from + (block + 0.5) * depth)
				),
				Color = if block % 2 == 0 then rgb(250, 246, 236) else rgb(236, 66, 54),
				Parent = start,
			})
		end
	end
	start.PrimaryPart = pad
	start:SetAttribute("Pivot", start:GetPivot()) -- (as each piece's: _deckPiece)
	start.Parent = arena
	-- The gate faces the racers' cameras behind the line (standing on the plinth); its banner says
	-- what the race is.
	MeshLibrary.Get("SkateStartGate", {
		CFrame = CFrame.new(origin + Vector3.new(0, plinthTop, 5)) * CFrame.Angles(0, math.pi, 0),
		Parent = start,
	})
	local sign = Build.Decor({
		Name = "GateSign",
		Size = Vector3.new(96, 7, 0.2),
		CFrame = CFrame.new(origin + Vector3.new(0, 21.7 + plinthTop, 5.6)),
		Transparency = 1,
		Parent = start,
	})
	Build.SurfaceText(sign, Enum.NormalId.Back, "🛹  SKATE ESCAPE  🌋", {
		PixelsPerStud = 10,
		TextColor3 = rgb(255, 255, 255),
		TextStrokeTransparency = 0.3,
		Font = Enum.Font.FredokaOne,
	})
	-- Behind the pad, the cliff the bridge sets out from (it stays when the pad falls).
	-- (Wider than a side stretch, so its ends tuck into the canyon's side walls.)
	stretch(
		MeshLibrary.Get("SkateCanyonWall", {
			CFrame = CFrame.new(origin + Vector3.new(0, WALL_FOOT - 1.5, START_BACK - 10 + WALL_PIVOT)),
			Parent = arena,
		}),
		1.4,
		1
	)
	Build.Decor({
		Name = "StartLine",
		Size = Vector3.new(DECK_WIDTH - 4, 0.08, 1),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.05, 0.5)),
		Color = rgb(250, 250, 250),
		Parent = start,
	})
	for lane = 1, LANES do
		local tile = Build.Decor({
			Name = "LaneNumber",
			Size = Vector3.new(5, 0.08, 5),
			CFrame = CFrame.new(origin + Vector3.new(SkateCourse.LaneX(lane, LANES), 0.05, 9)),
			Color = SkateCourse.LaneColors[lane],
			Parent = start,
		})
		Build.SurfaceText(tile, Enum.NormalId.Top, tostring(lane), {
			PixelsPerStud = 24,
			TextColor3 = rgb(30, 24, 40),
			TextStrokeTransparency = 1,
			Font = Enum.Font.FredokaOne,
		})
	end
	table.insert(pieces, 1, start)

	-- The goal: a stone landing that never falls, with the finish line and arch.
	Shapes.Slab(Vector3.new(DECK_WIDTH + 24, 8, GOAL_DEPTH), 2, {
		Name = "Goal",
		CFrame = CFrame.new(origin + Vector3.new(0, -4, -length - GOAL_DEPTH / 2)),
		Color = rgb(168, 140, 122),
		Material = Enum.Material.Slate,
		Parent = arena,
	})
	-- It stands on a rock pillar: a cliff face towards the racers, plain basalt behind it.
	Build.Part({
		Name = "GoalPillar",
		Size = Vector3.new(DECK_WIDTH, LAVA_DEPTH, GOAL_DEPTH - 8),
		CFrame = CFrame.new(origin + Vector3.new(0, -8 - LAVA_DEPTH / 2, -length - GOAL_DEPTH / 2)),
		Color = rgb(72, 50, 58),
		Material = Enum.Material.Basalt,
		Parent = arena,
	})
	stretch(
		MeshLibrary.Get("SkateCanyonWall", {
			CFrame = CFrame.new(origin + Vector3.new(0, WALL_FOOT - 1.5, -length - 2 - WALL_PIVOT))
				* CFrame.Angles(0, math.pi, 0),
			Parent = arena,
		}),
		1.4,
		1
	)
	-- The finish arch, facing the racers (its pivot sits 2.27 studs in front of the arch).
	MeshLibrary.Get("SkateFinishArch", {
		CFrame = CFrame.new(origin + Vector3.new(0, 0, -length - 8 + 2.27)) * CFrame.Angles(0, math.pi, 0),
		Parent = arena,
	})
	-- The finish line: a checkerboard of black and white tiles side by side (none overlap).
	local squares = 24
	local tile = (DECK_WIDTH - 4) / squares
	for index = 0, squares * 2 - 1 do
		local column = index % squares
		local row = index // squares
		Build.Decor({
			Name = "Checker",
			Size = Vector3.new(tile, 0.12, 2),
			CFrame = CFrame.new(
				origin + Vector3.new(-(DECK_WIDTH - 4) / 2 + (column + 0.5) * tile, 0.08, -length - 1 - row * 2)
			),
			Color = if (column + row) % 2 == 0 then rgb(28, 28, 34) else rgb(250, 250, 250),
			Parent = arena,
		})
	end
	for _, side in { -1, 1 } do
		for _, z in { 20, 45 } do
			self:_torch(arena, origin + Vector3.new(side * (DECK_WIDTH / 2 + 4), 0, -length - z), true)
		end
	end
end

-- Round ------------------------------------------------------------------------------------------

function SkateEscape:_attachBoard(player: any, character: Model)
	local racer = self.racers[tostring(player.UserId)]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not racer or not humanoid or not root then
		return
	end
	local old = character:FindFirstChild("Skateboard")
	if old then
		old:Destroy()
	end
	local board = MeshLibrary.Get("SkateBoard", {
		Colors = { Deck = SkateCourse.LaneColors[racer.Lane] },
		CFrame = root.CFrame,
	})
	board.Name = "Skateboard"
	local boardRoot = MeshLibrary.Assemble(board, true)
	local weld = Instance.new("Weld")
	weld.Name = "BoardWeld"
	weld.Part0 = root
	weld.Part1 = boardRoot
	weld.C0 = CFrame.new(0, -SkateCourse.RootHeight(humanoid, root), 0) * CFrame.Angles(0, math.rad(90), 0)
	weld.C1 = boardRoot.CFrame:ToObjectSpace(board:GetPivot())
	weld.Parent = boardRoot
	board.Parent = character
end

-- Where a skater's root goes at distance `d`, standing on their board: the same spot their own
-- screen holds them at (client: StanceCFrame with RootHeight), so placing them here never moves them.
function SkateEscape:_spot(racer, humanoid: Humanoid, root: BasePart, d: number): CFrame
	local x = SkateCourse.LaneX(racer.Lane, LANES)
	return SkateCourse.StanceCFrame(self.origin, x, d, SkateCourse.RootHeight(humanoid, root), 0)
end

-- Puts a skater on their board at their lane's start (or where they are on the course, if they only
-- got a character after GO). Before GO they're held there: anchored, so the server decides where
-- everyone sees them until the race starts, and nothing (gravity, a late position report from their
-- device, a slow phone) can move them in the meantime. PlatformStand: the humanoid mustn't try to
-- stand up on its own either, here or on their device.
function SkateEscape:_seat(player: any, character: Model)
	local racer = self.racers[tostring(player.UserId)]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not racer or not humanoid or not root then
		return
	end
	character:PivotTo(self:_spot(racer, humanoid, root, if self.startAt then racer.D else 0))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	humanoid.PlatformStand = true
	if not self.startAt then
		root.Anchored = true
	end
	racer.Character = character
	self:_attachBoard(player, character)
end

-- GO: lets a skater's character go from the spot it was held at. A player's goes back to their own
-- device (which skates it from there: nothing moves until they push); a bot's stays the server's,
-- which moves it: anchoring dropped the owner it was given, and Roblox would otherwise give it to the
-- nearest player's device.
function SkateEscape:_release(racer)
	local ctx = self.context
	local _, _, root = ctx:GetCharacter(racer.Player)
	if not root then
		return
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = false
	if racer.IsBot then
		pcall(root.SetNetworkOwner, root, nil)
	else
		ctx:GiveOwnership(root, racer.Player)
	end
end

function SkateEscape:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - LAVA_DROP - 8
	self.origin = ctx.Origin.Position
	self.obstacles = SkateCourse.Generate(rng)
	self.racers = {} :: { [string]: any }
	self.finished = 0
	self:_buildArena()

	-- Everyone gets a lane; with fewer than twelve the middle lanes fill first.
	local players = ctx:GetPlayers()
	local order = {}
	for index = 1, #players do
		order[index] = index
	end
	for index = #order, 2, -1 do
		local other = rng:NextInteger(1, index)
		order[index], order[other] = order[other], order[index]
	end
	local first = math.floor((LANES - math.min(#players, LANES)) / 2) + 1
	local lanes = {}
	local points = {}
	for index, player in players do
		local lane = math.min(LANES, first + order[index] - 1)
		local racer = SkateCourse.NewRacer() :: any
		racer.Player = player
		racer.Lane = lane
		racer.IsBot = BotRegistry.IsBot(player)
		racer.Leeway = 0
		self.racers[tostring(player.UserId)] = racer
		lanes[tostring(player.UserId)] = lane
		-- Straight onto their board (SpawnPlayer lifts the point 3 studs); a character that loads
		-- meanwhile is put right by CharacterReady.
		local _, humanoid, root = ctx:GetCharacter(player)
		points[index] = if humanoid and root
			then self:_spot(racer, humanoid, root, 0) - Vector3.new(0, 3, 0)
			else SkateCourse.StanceCFrame(self.origin, SkateCourse.LaneX(lane, LANES), 0, 0, 0)
	end

	local obstacles = {}
	for _, o in self.obstacles do
		table.insert(obstacles, { K = o.Kind, D = o.D, N = o.Len })
	end
	ctx:SetSharedJSON("Race", {
		O = { self.origin.X, self.origin.Y, self.origin.Z },
		Length = SkateCourse.Length,
		Lanes = LANES,
		Obstacles = obstacles,
		Lane = lanes,
	})

	ctx.Hooks.CharacterReady = function(player, character)
		self:_seat(player, character)
	end
	ctx.Hooks.PlayerLeft = function(player)
		self.racers[tostring(player.UserId)] = nil
	end
	-- Out some other way (a reset, say): stop simulating them and count them as fallen.
	ctx.Hooks.Eliminated = function(player)
		local racer = self.racers[tostring(player.UserId)]
		if racer and not racer.Done then
			racer.Out = true
			racer.OutAt = ctx:Now()
			racer.Done = true
			racer.Pending = nil
		end
	end
	ctx:SpawnAll(points, true) -- everyone waits on their board, held still until GO (CharacterReady)
	self:_share() -- the progress bar shows every lane during the countdown
	self.status = nil
	ctx:SetStatus("Get ready to PUSH!")
end

function SkateEscape:_ping(player: any): number
	if BotRegistry.IsBot(player) then
		return 0
	end
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and type(ping) == "number" then math.clamp(ping, 0, 0.3) else 0.1
end

-- How far ahead of the server's skater (in seconds of skating) a player's own client draws them: their
-- pushes reach the server one trip later. The same estimate the client steers its skater by.
function SkateEscape:_lag(player: any): number
	if BotRegistry.IsBot(player) then
		return 0
	end
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	return math.clamp(if ok and type(ping) == "number" then ping * 0.5 else 0.05, 0, 0.3)
end

function SkateEscape:_wipe(racer, event)
	-- As of the moment of the hit, however long the ping allowance held it.
	SkateCourse.Apply(racer, event, self.obstacles, event.At)
	racer.Pending = nil
	self.context:Fire(nil, "Wipe", tostring(racer.Player.UserId), event.Kind, event.Index)
end

function SkateEscape:Start()
	local ctx = self.context
	local now = ctx:Now()
	-- Everyone is let go from their start spot before the race's schedule goes out, so a client
	-- that can push (it knows the collapse) already holds its own skater.
	for _, racer in self.racers do
		if not ctx:State(racer.Player) then
			continue -- never placed (their character didn't load): not in this round
		end
		local character = ctx:GetCharacter(racer.Player)
		if character and character ~= racer.Character then
			self:_seat(racer.Player, character) -- reset during the countdown: back on the start line
		end
		self:_release(racer)
	end
	self.startAt = now
	self.collapse = SkateCourse.NewCollapse(now)
	ctx:SetSharedJSON("Collapse", self.collapse)

	-- Pushes are capped by a small bucket (PUSH_RATE a second on average, a few at once) rather than
	-- a fixed gap, so taps the network bunched together aren't dropped.
	ctx:OnAction("Push", function(player)
		local racer = self.racers[tostring(player.UserId)]
		if not racer then
			return
		end
		local clock = os.clock()
		racer.Tokens =
			math.min(PUSH_BURST, (racer.Tokens or PUSH_BURST) + (clock - (racer.TokenAt or clock)) * PUSH_RATE)
		racer.TokenAt = clock
		if racer.Tokens < 1 then
			return
		end
		racer.Tokens -= 1
		racer.Leeway = 0.06 + self:_ping(player)
		racer.Lag = self:_lag(player)
		SkateCourse.Push(racer, ctx:Now())
	end, { Interval = 0.04 })

	-- `claimed` is where the player's own client had them (distance) when they pressed JUMP. The ollie
	-- counts from the moment the server's skater is (or was) at that spot, so it clears exactly what it
	-- cleared on their screen: ping, and the small drift between the two simulations, can't turn a
	-- clean jump into a wipeout. It may move the take-off by at most the ping allowance either way.
	ctx:OnAction("Jump", function(player, claimed)
		local racer = self.racers[tostring(player.UserId)]
		if not racer then
			return
		end
		local at = ctx:Now()
		racer.Leeway = 0.06 + self:_ping(player)
		racer.Lag = self:_lag(player)
		local start: number? = nil
		if type(claimed) == "number" and claimed == claimed and racer.V >= 1 then
			start = at + math.clamp((claimed - racer.D) / racer.V, -racer.Leeway, racer.Leeway)
		end
		local pending = racer.Pending
		if pending then
			-- The skater already reached the obstacle here; would this jump (without a spot: one
			-- pressed up to `Leeway` ago), not before the last landing, have cleared it?
			local from = math.max(start or (at - racer.Leeway), racer.AirEnd or -math.huge)
			local o = self.obstacles[pending.Event.Index]
			if o and from <= at and SkateCourse.WouldClear(o, from, pending.Event.At, pending.Speed) then
				racer.Pending = nil
				racer.Air = from
				racer.AirEnd = from + SkateCourse.AirTime
				return
			end
		end
		if racer.Air and racer.Air > at then
			return -- one is already waiting for the skater to reach its spot
		end
		SkateCourse.Jump(racer, at, if start then math.max(start, racer.AirEnd or -math.huge) else nil)
	end, { Interval = 0.15 })

	-- Small steps, so a server hitch doesn't cost anyone distance while the collapse runs on.
	ctx:Heartbeat(function(dt)
		local now = ctx:Now()
		local left = math.min(dt, 0.5)
		while left > 1e-4 do
			local h = math.min(left, 0.05)
			left -= h
			self:_tick(h, now - left)
		end
	end)
	ctx:Loop(function()
		self:_share()
		return 0.12
	end)
end

function SkateEscape:_moveBot(racer, now: number)
	local character, humanoid, root = self.context:GetCharacter(racer.Player)
	if not character or not humanoid or not root then
		return
	end
	if racer.Character and character ~= racer.Character then
		-- A new character: a fallen bot is sent back to the lobby 1.2 s after it went in, while its
		-- fall is still drawn here, and this used to drag that lobby character back over the canyon.
		return
	end
	local d, lift, tumble, drop = SkateCourse.Pose(racer, now)
	if racer.Out then
		local t = now - (racer.OutAt or now)
		drop = math.min(60, 0.5 * 70 * t * t)
		tumble = t * 1.5
	end
	if not humanoid.PlatformStand then
		humanoid.PlatformStand = true -- the server moves this skater; the humanoid mustn't try to stand
	end
	local x = SkateCourse.LaneX(racer.Lane, LANES)
	root.CFrame =
		SkateCourse.StanceCFrame(self.origin, x, d, SkateCourse.RootHeight(humanoid, root) + lift - drop, tumble)
	root.AssemblyLinearVelocity = Vector3.new(0, 0, -racer.V)
end

function SkateEscape:_tick(dt: number, now: number)
	local ctx = self.context
	if not ctx:IsRunning() then
		return
	end
	local length = SkateCourse.Length
	local front = SkateCourse.CollapseAt(self.collapse, now)
	local everyoneDone = true
	local crossed = {}
	for key, racer in self.racers do
		local player = racer.Player
		if not ctx:State(player) then
			self.racers[key] = nil
			continue
		end
		if racer.Out then
			if racer.IsBot and now - racer.OutAt < 1.4 then
				self:_moveBot(racer, now)
			end
			continue
		end
		if racer.Place then
			-- Finished: coast to a stop on the goal landing.
			racer.V = math.max(0, racer.V - (8 + 0.6 * racer.V) * dt)
			racer.D = math.min(racer.D + racer.V * dt, length + SkateCourse.RunOut)
			racer.Air = nil
			if racer.IsBot then
				self:_moveBot(racer, now)
			end
			continue
		end
		everyoneDone = false
		if racer.Done then
			continue -- crossed the line this step, placed below
		end
		local pending = racer.Pending
		if pending and now >= pending.Until then
			self:_wipe(racer, pending.Event)
		end
		local event = SkateCourse.Step(racer, self.obstacles, now, dt)
		if event then
			if event.Kind == "Boost" then
				SkateCourse.Apply(racer, event, self.obstacles, now)
				ctx:Fire(nil, "Boost", key)
			elseif racer.Leeway > 0 and not racer.Pending and not event.Landed then
				-- (Coming down inside a gap is the last jump's doing: no later press can change it.)
				racer.Pending = { Event = event, Until = now + racer.Leeway, Speed = math.max(racer.V, 1) }
			else
				self:_wipe(racer, event)
			end
		end
		if racer.D >= length then
			-- The exact moment they crossed, so two finishers in one step are ranked fairly.
			racer.Done = true
			racer.Wipe = nil
			racer.Pending = nil
			table.insert(crossed, { Key = key, Racer = racer, At = now - (racer.D - length) / math.max(racer.V, 1) })
		elseif SkateCourse.Caught(front, racer.D, racer.V * (racer.Lag or 0), length) then
			-- Only once the front is past their front wheels as their own screen draws them (it shows
			-- them `Lag` seconds of skating ahead of these numbers), as the client checks it.
			racer.Out = true
			racer.OutAt = now
			racer.Done = true
			racer.Pending = nil
			ctx:Fire(nil, "Out", key)
			ctx:SetScoreText(player, `Fell at {math.floor(math.max(0, racer.D) / length * 100)}%`)
			ctx:Eliminate(player, "collapse")
		end
		if racer.IsBot then
			self:_moveBot(racer, now)
		end
	end
	table.sort(crossed, function(a, b)
		return a.At < b.At
	end)
	for _, entry in crossed do
		local racer = entry.Racer
		self.finished += 1
		racer.Place = self.finished
		racer.Time = entry.At - self.startAt
		local player = racer.Player
		ctx:SetScoreText(player, `{SkateCourse.Ordinal(racer.Place)} • {string.format("%.1f", racer.Time)}s`)
		ctx:Fire(nil, "Finish", entry.Key, racer.Place)
		if racer.Place == 1 then
			ctx:Announce(`🏁 {player.DisplayName} reached the goal first!`, "success", 3)
		end
	end
	if everyoneDone and not self.ending and next(self.racers) ~= nil then
		self.ending = true
		ctx:Delay(2, function()
			ctx:End("AllFinished")
		end)
	end
end

-- Everyone's race for clients (progress bar, other skaters' kicks and wipeouts, your own corrections).
function SkateEscape:_share()
	local ctx = self.context
	local now = ctx:Now()
	local list = {}
	local home, skating = 0, 0
	for key, racer in self.racers do
		local entry: { [string]: any } = {
			L = racer.Lane,
			D = round(racer.D, 0.01),
			V = round(racer.V, 0.01),
			P = racer.Pushes,
			T = round(now, 0.001),
		}
		if racer.Air then
			entry.A = round(racer.Air, 0.001)
		end
		if racer.Pending then
			entry.PW = 1 -- a hit the server is still deciding on (ping allowance)
		end
		if racer.Wipe and now < racer.Wipe then
			entry.W = round(racer.Wipe, 0.001)
			entry.WA = round(racer.WipeAt or now, 0.001)
			entry.WK = racer.WipeKind
			entry.FD = racer.FallD and round(racer.FallD, 0.01)
		end
		if racer.Place then
			entry.F = racer.Place
			home += 1
		elseif racer.Out then
			entry.O = 1
		else
			skating += 1
			if self.startAt then
				ctx:SetScoreText(racer.Player, `{math.floor(math.clamp(racer.D / SkateCourse.Length, 0, 1) * 100)}%`)
			end
		end
		-- The live standings sort by score: how far along in steps of 4 studs (they show the
		-- percent; finer steps changed every skater's score attribute ~8 times a second for every
		-- phone), finishers above everyone by place, the same order as the results.
		local state = self.startAt and ctx:State(racer.Player)
		if state then
			local score = if racer.Place
				then 1e4 - racer.Place
				else math.floor(math.clamp(racer.D, 0, SkateCourse.Length) / 4) * 4
			if score ~= state.Score then
				ctx:AddScore(racer.Player, score - state.Score)
			end
		end
		list[key] = entry
	end
	ctx:SetSharedJSON("Racers", list)
	local status = if home > 0
		then `🏁 {home} home  •  🛹 {skating} skating`
		else `🛹 {skating} skating  •  outrun the collapse!`
	if status ~= self.status then
		self.status = status
		ctx:SetStatus(status)
	end
end

function SkateEscape:GetResults()
	local ctx = self.context
	local entries = {}
	for _, player in ctx:GetPlayers() do
		local racer = self.racers[tostring(player.UserId)]
		if not racer then
			continue
		end
		local percent = math.floor(math.clamp(racer.D / SkateCourse.Length, 0, 1) * 100)
		if racer.Place then
			table.insert(entries, {
				Player = player,
				Rank = 1e6 - racer.Place,
				ScoreText = `{SkateCourse.Ordinal(racer.Place)} • {string.format("%.1f", racer.Time or 0)}s`,
				BestScore = 100,
			})
		else
			table.insert(entries, {
				Player = player,
				Rank = math.clamp(racer.D, 0, SkateCourse.Length),
				ScoreText = if racer.Out then `Fell at {percent}%` else `{percent}% of the way`,
				BestScore = percent,
			})
		end
	end
	return { Entries = entries }
end

return SkateEscape

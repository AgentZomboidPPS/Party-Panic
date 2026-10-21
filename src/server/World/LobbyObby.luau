-- Builds the lobby obby (owner: "the obby in the lobby is terrible. trees and stuff collides and you can
-- just run up it") from the layout in Shared/Logic/ParkourCourse: a round pool of purple goo with a
-- candy lookout tower in the middle, four coloured sections round it and a view deck on top.
--
--   * Every platform is a real jump from the last (the layout module and tests/ParkourCourse.spec.luau
--     check each one against the jump arc), with nothing to walk up: no ramps, no steps.
--   * A glowing pad starts each section; LobbyService puts anyone who falls into the goo back on the
--     last one they reached. The goo is see-through to physics (players sink a stud into it, onto the
--     pool floor), so a fall always ends in it.
--   * An invisible wall round the pool's rim (from the floor to well out of jumping reach) leaves one way
--     in, the start pad, so nobody can jump into a later section from outside. The low fence and its
--     bulbs show where it is.
--   * Supports (stems, posts, brackets, stripes) are decoration: they never collide, so the only things
--     to stand on are the course's own tops.
-- Tags for clients: ParkourStart (the start pad: starts the run timer), ParkourFinish (the deck's
-- finish disc: stops it). MovementController times runs.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ParkourCourse = require(ReplicatedStorage.Shared.Logic.ParkourCourse)

local Build = require(script.Parent.Build)
local Shapes = require(script.Parent.Shapes)

local LobbyObby = {}

export type Refs = {
	Model: Model,
	Frame: CFrame,
	DeckSpot: Vector3, -- a daily-token spot on the view deck
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = rgb(255, 252, 246)
local CREAM = rgb(250, 242, 228)
local GOLD = rgb(255, 204, 64)
local GOO = rgb(150, 96, 250)
local GOO_FLOOR = rgb(78, 44, 150)
local BULBS = { rgb(255, 84, 150), rgb(64, 196, 255), rgb(255, 204, 64), rgb(110, 226, 140), rgb(156, 108, 255) }

local SIGN_FONT = Enum.Font.LuckiestGuy
local RIM_RADIUS = ParkourCourse.PoolRadius + 0.8 -- the rim's middle (it's 1.6 thick)

-- How far the pool and its rim reach from the tower (the entrance sticks out toward the plaza).
LobbyObby.Radius = ParkourCourse.PoolRadius + 1.6

-- The sections' colours, and lighter tints for stripes and trims.
local function sectionColor(section: number): Color3
	local c = ParkourCourse.Sections[section].Color
	return rgb(c[1], c[2], c[3])
end

local function tag(instance: Instance, name: string)
	CollectionService:AddTag(instance, name)
end

-- A part made decoration: no collisions, queries or touches (stems, posts, stripes, brackets).
local function decor(part: BasePart): BasePart
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

local function sparkles(parent: BasePart, color: Color3, rate: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(1.2, 2)
	emitter.Speed = NumberRange.new(1.5, 3.5)
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Rate = rate
	emitter.Parent = parent
	tag(emitter, "PP_Ambient") -- clients with "reduced effects" switch these off
end

function LobbyObby.Build(parent: Instance, frame: CFrame): Refs
	local model = Build.Model("ParkourRoute", parent)
	local floor, gooTop = ParkourCourse.Floor, ParkourCourse.GooTop

	-- Course space (see ParkourCourse) to world.
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local function polar(angle: number, radius: number, y: number): CFrame
		local a = math.rad(angle)
		return at(radius * math.sin(a), y, radius * math.cos(a))
	end
	-- An upright cylinder from `bottom` to `top` (Roblox cylinders lie along X).
	local function column(
		name: string,
		diameter: number,
		bottom: number,
		top: number,
		place: CFrame,
		props: { [string]: any }
	)
		props.Name = name
		props.Shape = Enum.PartType.Cylinder
		props.Size = Vector3.new(top - bottom, diameter, diameter)
		props.CFrame = CFrame.new((place * CFrame.new(0, (top + bottom) / 2, 0)).Position)
			* CFrame.Angles(0, 0, math.rad(90))
		props.Parent = props.Parent or model
		return Build.Part(props)
	end
	local function ground(x: number, z: number): CFrame
		return at(x, 0, z)
	end

	-- The pool: a solid floor a stud under the goo, the goo itself (no collisions), the rim, the fence.
	local pool = Build.Model("GooPool", model)
	local radius = ParkourCourse.PoolRadius
	column("PoolFloor", radius * 2 + 0.4, -0.6, floor, ground(0, 0), { Color = GOO_FLOOR, Parent = pool })
	local goo = column("Goo", radius * 2, floor - 0.1, gooTop, ground(0, 0), {
		Color = GOO,
		Reflectance = 0.12,
		CastShadow = false,
		Parent = pool,
	})
	decor(goo)
	local glow = Build.Decor({
		Name = "GooGlow",
		Size = Vector3.one,
		Transparency = 1,
		CFrame = at(0, gooTop + 2, 0),
		Parent = pool,
	})
	Build.Light(glow, rgb(190, 140, 255), 30, 0.8)
	-- Bubbles drifting up off the goo.
	for index = 0, 5 do
		local spot = polar(index * 60 + 30, if index % 2 == 0 then 19.5 else 9, gooTop + 0.2)
		local holder = Build.Decor({
			Name = "Bubbles",
			Size = Vector3.new(6, 0.2, 6),
			Transparency = 1,
			CFrame = spot,
			Parent = pool,
		})
		local bubbles = Instance.new("ParticleEmitter")
		bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		bubbles.Color = ColorSequence.new(rgb(220, 190, 255))
		bubbles.LightEmission = 0.6
		bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.7) })
		bubbles.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		bubbles.Lifetime = NumberRange.new(1, 1.6)
		bubbles.Speed = NumberRange.new(1, 2.5)
		bubbles.SpreadAngle = Vector2.new(10, 10)
		bubbles.EmissionDirection = Enum.NormalId.Top
		bubbles.Rate = 3
		bubbles.Parent = holder
		tag(bubbles, "PP_Ambient")
	end
	-- A few big glossy bubbles sitting in the goo.
	local rng = Random.new(17)
	for index = 1, 9 do
		local angle = index * 40 + rng:NextNumber(-8, 8)
		local distance = if index % 3 == 0 then rng:NextNumber(7, 9) else rng:NextNumber(20.5, 21.5)
		local size = rng:NextNumber(1, 2.2)
		Build.Decor({
			Name = "Bubble",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size,
			CFrame = polar(angle, distance, gooTop - size * 0.15),
			Color = rgb(196, 160, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.25,
			Reflectance = 0.2,
			Parent = pool,
		})
	end

	-- The rim: a ring of rounded tubes round the goo, left open under the start pad.
	local start = ParkourCourse.Start
	local rimSegments = 32
	for index = 0, rimSegments - 1 do
		local angle = (index + 0.5) / rimSegments * 360
		local delta = (angle + 180) % 360 - 180
		if math.abs(delta) < 8 then
			continue -- under the start pad
		end
		local chord = 2 * RIM_RADIUS * math.sin(math.pi / rimSegments)
		Shapes.Capsule(chord + 1.6, 1.6, {
			Name = "Rim",
			CFrame = polar(angle, RIM_RADIUS, gooTop - 0.3) * CFrame.Angles(0, math.rad(angle), 0),
			Color = CREAM,
			Parent = pool,
		})
	end
	-- The fence: an invisible wall on the rim from the floor to out of reach, open at the start ...
	local fence = Build.Model("Fence", pool)
	local wallSegments = 24
	local wallHeight = ParkourCourse.FenceTop - floor
	for index = 0, wallSegments - 1 do
		local angle = (index + 0.5) / wallSegments * 360
		local delta = (angle + 180) % 360 - 180
		if math.abs(delta) < ParkourCourse.Opening then
			continue
		end
		local chord = 2 * RIM_RADIUS * math.sin(math.pi / wallSegments)
		Build.Barrier({
			Name = "Wall",
			Size = Vector3.new(chord + 0.6, wallHeight, 1.6),
			CFrame = polar(angle, RIM_RADIUS, floor + wallHeight / 2) * CFrame.Angles(0, math.rad(angle), 0),
			Parent = fence,
		})
	end
	-- ... and what players see of it: white posts with party bulbs, a rope between them.
	local posts = {}
	for index = 0, 11 do
		local angle = index * 30 + 15
		local post = Shapes.Capsule(3.4, 0.8, {
			Name = "FencePost",
			CFrame = polar(angle, RIM_RADIUS, gooTop + 1.9) * CFrame.Angles(0, 0, math.rad(90)),
			Color = WHITE,
			Parent = fence,
		})
		decor(post)
		local bulb = Build.Decor({
			Name = "FenceBulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.1,
			CFrame = polar(angle, RIM_RADIUS, gooTop + 3.8),
			Color = BULBS[index % #BULBS + 1],
			Material = Enum.Material.Neon,
			Parent = fence,
		})
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(0, -0.5, 0)
		attachment.Parent = bulb
		table.insert(posts, attachment)
	end
	for index, attachment in posts do
		if index == #posts then
			continue -- the entrance: no rope across it
		end
		local rope = Instance.new("Beam")
		rope.Attachment0 = attachment
		rope.Attachment1 = posts[index % #posts + 1]
		rope.Width0 = 0.25
		rope.Width1 = 0.25
		rope.CurveSize0 = -1.2
		rope.CurveSize1 = 1.2
		rope.Segments = 12
		rope.FaceCamera = true
		rope.Color = ColorSequence.new(rgb(255, 120, 175))
		rope.Parent = attachment.Parent
	end

	-- The way in: two steps up from the plaza to the start pad, under an arch with the sign.
	local entry = Build.Model("Entrance", model)
	local startOuter = (start.Radius :: number) + (start.Size :: number) / 2
	for step = 1, 2 do
		local depth = 3.2
		local z = startOuter + depth * (2 - step) + depth / 2 - 0.6
		local top = start.Top * step / 3
		Shapes.Slab(Vector3.new(7.5, top + 0.6, depth + 0.6), 1.2, {
			Name = "Step",
			CFrame = at(0, (top - 0.6) / 2, z),
			Color = if step == 1 then CREAM else WHITE,
			Parent = entry,
		})
	end
	local archFoot = startOuter + 3.4
	Shapes.Arch(11, 12.5, 1.4, 1.6, at(0, 0, archFoot), {
		Name = "Arch",
		Color = sectionColor(1),
		Parent = entry,
	})
	Shapes.Arch(11.8, 12.9, 0.5, 1.2, at(0, 0, archFoot), {
		Name = "ArchTrim",
		Color = WHITE,
		Parent = entry,
	})
	local board = Shapes.RoundedBox(Vector3.new(11, 3.8, 1.2), 0.5, {
		Name = "Sign",
		CFrame = at(0, 14.2, archFoot),
		Color = rgb(255, 84, 150),
		Parent = entry,
	})
	for _, face in { Enum.NormalId.Back, Enum.NormalId.Front } do
		Build.SurfaceText(board, face, "OBBY", {
			PixelsPerStud = 16,
			Font = SIGN_FONT,
			TextColor3 = rgb(255, 255, 255),
			TextStrokeTransparency = 0.35,
			Padding = 0.1,
		})
	end
	for _, side in { -1, 1 } do
		local bulb = Build.Decor({
			Name = "SignBulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.3,
			CFrame = at(side * 6.4, 14.2, archFoot),
			Color = GOLD,
			Material = Enum.Material.Neon,
			Parent = entry,
		})
		sparkles(bulb, GOLD, 2)
	end

	-- The tower: a white column with pink stripes, the gold view deck on top.
	local tower = Build.Model("Tower", model)
	local deck = ParkourCourse.Deck
	local towerRadius = ParkourCourse.TowerRadius
	local deckTop = deck.Top
	column("Column", towerRadius * 2, floor - 0.2, deckTop - 1.2, ground(0, 0), { Color = WHITE, Parent = tower })
	local stripe = 0
	for y = floor + 3, deckTop - 4, 4.6 do
		stripe += 1
		decor(column("Stripe", towerRadius * 2 + 0.3, y, y + 1.6, ground(0, 0), {
			Color = sectionColor(4),
			CastShadow = false,
			Parent = tower,
		}))
	end
	column("Deck", towerRadius * 2 + 0.4, deckTop - 1.2, deckTop, ground(0, 0), { Color = GOLD, Parent = tower })
	decor(column("DeckTrim", towerRadius * 2 + 1, deckTop - 1.5, deckTop - 0.9, ground(0, 0), {
		Color = WHITE,
		Parent = tower,
	}))
	-- Railing posts round the deck, open where the last ledge comes up.
	local arrival = ParkourCourse.Pieces[#ParkourCourse.Pieces - 1].Angle :: number
	for index = 0, 11 do
		local angle = index * 30
		local delta = (angle - arrival + 180) % 360 - 180
		if math.abs(delta) < 26 then
			continue
		end
		Shapes.Capsule(3, 0.6, {
			Name = "Rail",
			CFrame = polar(angle, towerRadius - 0.5, deckTop + 1.2) * CFrame.Angles(0, 0, math.rad(90)),
			Color = WHITE,
			Parent = tower,
		})
	end
	local finish = column("ParkourFinish", 4.6, deckTop - 0.05, deckTop + 0.25, ground(0, 0), {
		Color = rgb(255, 120, 60),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = true,
		CastShadow = false,
		Parent = tower,
	})
	tag(finish, "ParkourFinish")
	sparkles(finish, GOLD, 4)
	local flagSpot = polar(180, towerRadius - 1.2, deckTop)
	local pole = Shapes.Capsule(11, 0.5, {
		Name = "FlagPole",
		CFrame = flagSpot * CFrame.new(0, 5.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = WHITE,
		Parent = tower,
	})
	decor(pole)
	Build.Decor({
		Name = "Flag",
		Size = Vector3.new(0.2, 3.2, 5),
		CFrame = flagSpot * CFrame.new(0, 9.2, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.new(0, 0, -2.5),
		Color = sectionColor(4),
		Parent = tower,
	})
	local lamp = Build.Decor({
		Name = "DeckLight",
		Size = Vector3.one,
		Transparency = 1,
		CFrame = at(0, deckTop + 6, 0),
		Parent = tower,
	})
	Build.Light(lamp, rgb(255, 230, 170), 24, 1)

	-- The course's pieces.
	local pieces = Build.Model("Pieces", model)
	local function stem(x: number, z: number, top: number, diameter: number, color: Color3)
		decor(column("Stem", diameter, floor - 0.2, top, ground(x, z), {
			Color = color,
			CastShadow = false,
			Parent = pieces,
		}))
	end
	local function checkpointFlag(piece: ParkourCourse.Piece, number: number)
		-- A pennant on a pole at the pad's outer edge, with the checkpoint's number on both sides.
		local out = math.sqrt(piece.X * piece.X + piece.Z * piece.Z)
		local ux, uz = piece.X / out, piece.Z / out
		local reach = if piece.Kind == "Disc" then (piece.Size :: number) / 2 else (piece.Length :: number) / 2
		local base = ground(piece.X + ux * (reach - 0.4), piece.Z + uz * (reach - 0.4))
		local facing = CFrame.lookAt(base.Position, base.Position + (frame:VectorToWorldSpace(Vector3.new(ux, 0, uz))))
		decor(Shapes.Capsule(5.4, 0.35, {
			Name = "FlagPole",
			CFrame = facing * CFrame.new(0, piece.Top + 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = WHITE,
			Parent = pieces,
		}))
		local flag = Build.Decor({
			Name = "CheckpointFlag",
			Size = Vector3.new(2.8, 2, 0.2),
			CFrame = facing * CFrame.new(1.5, piece.Top + 4.2, 0),
			Color = sectionColor(piece.Section),
			Parent = pieces,
		})
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			Build.SurfaceText(flag, face, tostring(number), {
				PixelsPerStud = 24,
				Font = SIGN_FONT,
				TextColor3 = rgb(255, 255, 255),
				TextStrokeTransparency = 0.3,
				Padding = 0.04,
			})
		end
	end

	for _, piece in ParkourCourse.Pieces do
		if piece.Finish then
			continue -- the deck is the tower's top
		end
		local color = sectionColor(piece.Section)
		local top = piece.Top
		if piece == start then
			-- The start pad: a glowing green disc on a cream pedestal from the ground.
			column("StartBase", 8.8, -0.2, top - 0.25, ground(piece.X, piece.Z), { Color = CREAM, Parent = pieces })
			local pad = column("ParkourStart", start.Size :: number, top - 0.5, top, ground(piece.X, piece.Z), {
				Color = color,
				Material = Enum.Material.Neon,
				CanTouch = true,
				Parent = pieces,
			})
			tag(pad, "ParkourStart")
			Build.Billboard(pad, "🧗 OBBY - climb to the top!", {
				StudsOffset = Vector3.new(0, 6, 0),
				Size = UDim2.fromOffset(260, 44),
				MaxDistance = 70,
			})
			continue
		end
		local isCheckpoint = piece.Checkpoint ~= nil
		if piece.Kind == "Disc" then
			local size = piece.Size :: number
			local place = ground(piece.X, piece.Z)
			if isCheckpoint then
				-- A glowing pad in the colour of the section it starts, on a white rim.
				column("Checkpoint" .. piece.Checkpoint, size, top - 0.6, top, place, {
					Color = color,
					Material = Enum.Material.Neon,
					Parent = pieces,
				})
				decor(
					column("CheckpointRim", size + 0.6, top - 1.4, top - 0.4, place, { Color = WHITE, Parent = pieces })
				)
				checkpointFlag(piece, piece.Checkpoint :: number)
				local shine = Build.Decor({
					Name = "Glow",
					Size = Vector3.one,
					Transparency = 1,
					CFrame = place * CFrame.new(0, top + 1, 0),
					Parent = pieces,
				})
				sparkles(shine, color, 3)
			else
				column(piece.Id, size, top - 1.1, top, place, { Color = color, Parent = pieces })
				decor(column("Trim", size + 0.5, top - 1.3, top - 0.25, place, { Color = WHITE, Parent = pieces }))
			end
			-- What holds it up: pillars are columns from the floor; hops sit on thin stems.
			if piece.Section == 2 or (isCheckpoint and piece.Section == 3) then
				local pillarSize = if isCheckpoint then size - 1 else size - 0.4
				local pillarColor = sectionColor(2)
				column("Pillar", pillarSize, floor - 0.2, top - (if isCheckpoint then 1.3 else 1.1), place, {
					Color = pillarColor,
					Parent = pieces,
				})
				for y = floor + 2.2, top - 3, 3.4 do
					decor(column("PillarStripe", pillarSize + 0.3, y, y + 1.1, place, {
						Color = WHITE,
						CastShadow = false,
						Parent = pieces,
					}))
				end
			else
				stem(
					piece.X,
					piece.Z,
					top - 1,
					if size > 5 then 1.6 else 0.9,
					if piece.Section == 1 or (isCheckpoint and piece.Section == 2) then rgb(70, 170, 95) else WHITE
				)
			end
		elseif piece.Kind == "Beam" then
			local length, width = piece.Length :: number, piece.Width :: number
			local place = at(piece.X, top - 0.45, piece.Z) * CFrame.Angles(0, -(piece.Yaw :: number), 0)
			Shapes.Slab(
				Vector3.new(width, 0.9, length),
				0.4,
				{ Name = piece.Id, CFrame = place, Color = color, Parent = pieces }
			)
			-- White posts under the ends that aren't held by a pad.
			for _, sign in { -1, 1 } do
				local endPoint = place * CFrame.new(0, 0, sign * (length / 2 - 0.6))
				local spot = frame:PointToObjectSpace(endPoint.Position)
				local held = false
				for _, other in ParkourCourse.Pieces do
					if other ~= piece and other.Checkpoint and ParkourCourse.Over(other, spot.X, spot.Z, 0.8) then
						held = true
					end
				end
				if not held then
					stem(spot.X, spot.Z, top - 0.9, 0.7, WHITE)
				end
			end
		else -- a ledge on the tower, with a gold bracket under it
			local depth, width = piece.Depth :: number, piece.Width :: number
			local inward = 0.3 -- reaches a little into the column so it reads as fixed to it
			local place = at(piece.X, top, piece.Z) * CFrame.Angles(0, -(piece.Yaw :: number), 0)
			if isCheckpoint then
				Shapes.Slab(Vector3.new(width, 0.4, depth + inward), 0.6, {
					Name = "Checkpoint" .. piece.Checkpoint,
					CFrame = place * CFrame.new(0, -0.2, inward / 2),
					Color = color,
					Material = Enum.Material.Neon,
					Parent = pieces,
				})
				Shapes.Slab(Vector3.new(width + 0.4, 0.9, depth + inward + 0.2), 0.7, {
					Name = "CheckpointBase",
					CFrame = place * CFrame.new(0, -0.85, inward / 2),
					Color = WHITE,
					Parent = pieces,
				})
				checkpointFlag(piece, piece.Checkpoint :: number)
				local shine = Build.Decor({
					Name = "Glow",
					Size = Vector3.one,
					Transparency = 1,
					CFrame = place * CFrame.new(0, 1, 0),
					Parent = pieces,
				})
				sparkles(shine, color, 3)
			else
				Shapes.Slab(Vector3.new(width, 1, depth + inward), 0.6, {
					Name = piece.Id,
					CFrame = place * CFrame.new(0, -0.5, inward / 2),
					Color = color,
					Parent = pieces,
				})
			end
			-- The bracket: a gold wedge under the ledge, its tall side against the tower.
			Build.Wedge({
				Name = "Bracket",
				Size = Vector3.new(0.8, 2.6, depth - 0.6),
				CFrame = place * CFrame.new(0, -2.3, 0.3) * CFrame.Angles(0, 0, math.rad(180)),
				Color = GOLD,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Parent = pieces,
			})
		end
	end

	local deckSpot = at(2.2, deckTop + 2.5, -2.2).Position
	return { Model = model, Frame = frame, DeckSpot = deckSpot }
end

-- Whether a point in the world is clear of the obby (its pool, rim and entrance) by `margin` studs.
function LobbyObby.Clear(frame: CFrame, position: Vector3, margin: number): boolean
	local p = frame:PointToObjectSpace(position)
	local flat = Vector2.new(p.X, p.Z)
	local start = ParkourCourse.Start
	local entrance = Vector2.new(0, (start.Radius :: number) + (start.Size :: number) / 2 + 2.5)
	return flat.Magnitude > LobbyObby.Radius + margin and (flat - entrance).Magnitude > 6.5 + margin
end

return LobbyObby

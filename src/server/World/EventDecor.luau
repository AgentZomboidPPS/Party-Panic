-- Decorations for the limited-time event on now, around the plaza (owner, asked what keeps players
-- coming back, then: "Can you work on all of that? this wont mess with what the other workers are
-- working on right?"; the idea they were offered: "a Halloween event: candy, free limited rewards
-- like a pumpkin hat, a banner with a countdown, lobby decorations and lighting").
--
-- The HALLOWEEN PARTY: glowing jack-o'-lanterns by the lamp posts on the south lawn, on top of the
-- vote stage's speakers and at its front corners; pumpkin piles by the flower beds either side of
-- the emote stage; bats circling over the fountain, the emote stage and the stage's two towers;
-- two ghosts bobbing on the south lawn; cobwebs on those lamp posts and on the emote stage's arch;
-- a little mist on the edge of the lawn. Small pieces, spread out, and none of them collides, takes
-- a touch or blocks a ray: nothing sits on a walkway, in front of the portals or on the vote stage's
-- floor in front of them, by the podium and the Hall of Fame (east), the shop and the medal wall
-- (west), the obby or either arcade. Made from parts and an existing mesh (Rake It In's golden
-- pumpkin, painted orange), so nothing new had to be uploaded.
-- The lobby's light for the event is each device's own (Controllers/EventController, Shared/Events'
-- Look): Lighting is the whole world's, arenas included, so the server never changes it.
--
-- The pumpkin hunt: golden pumpkins hidden around the lobby (HuntSpots). Services/EventService puts
-- out today's few (PlaceHunt), hands out the candy when one is touched, and moves them at midnight
-- UTC; each device hides the ones its player has found (tag PP_EventPumpkin).
--
-- Servers run for days, so all of it comes and goes at run time: EventService calls Show(set) when
-- an event starts and Show(nil) when it ends. LobbyBuilder calls Build(root) after the scenery.

local CollectionService = game:GetService("CollectionService")

local Build = require(script.Parent.Build)
local MeshLibrary = require(script.Parent.MeshLibrary)

local EventDecor = {}

local lobby: Model? = nil
local wanted: string? = nil -- the set EventService asked for (shown once the lobby exists)
local decor: Model? = nil
local shown: string? = nil

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local PUMPKIN = rgb(255, 132, 26)
local STEM = rgb(88, 128, 50)
local FACE = rgb(255, 196, 60) -- a lantern's carved face, glowing
local CANDLE = rgb(255, 150, 50)
local BAT = rgb(46, 32, 62)
local GHOST = rgb(246, 246, 255)
local WEB = rgb(238, 238, 248)
local MIST = rgb(196, 182, 236)
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- Where the golden pumpkins of the hunt can hide, on the ground (EventService puts a few out each
-- day). Off the walkways, away from the zones above, and not where the daily secret token goes.
local HUNT_SPOTS: { [string]: { Vector3 } } = {
	Halloween = {
		Vector3.new(6, 0, 68.5), -- behind the emote stage's arch
		Vector3.new(22.8, 0, 62.6), -- behind the flower bed east of the emote stage
		Vector3.new(-22.8, 0, 62.6), -- behind the flower bed west of the emote stage
		Vector3.new(-21.4, 0, 25.5), -- behind the bench south-west of the fountain
		Vector3.new(21.4, 0, 25.5), -- behind the bench south-east of the fountain
		Vector3.new(-28, 0, -72), -- behind the vote stage, west
		Vector3.new(28, 0, -72), -- behind the vote stage, east
		Vector3.new(-47, 0, 57), -- behind the quest board
	},
}

-- Pieces --------------------------------------------------------------------------------------------

-- Decoration flags: never collides, never takes a touch or a ray, no shadow.
local function decorProps(props: { [string]: any }): { [string]: any }
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	props.CastShadow = false
	return props
end

-- A flat triangle a-b-c, `thickness` thick, from wedges (split at the foot of its height on the
-- longest side into two right triangles; a right triangle is one wedge). `props` go on each.
local function triangle(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number,
	props: { [string]: any }
)
	local ab, bc, ca = (b - a).Magnitude, (c - b).Magnitude, (a - c).Magnitude
	if bc > ab and bc >= ca then
		a, b, c = b, c, a
	elseif ca > ab and ca >= bc then
		a, b, c = c, a, b
	end
	local side = b - a
	if side.Magnitude < 1e-3 or side:Cross(c - a).Magnitude < 1e-6 then
		return
	end
	local along = side.Unit
	local foot = a + along * (c - a):Dot(along)
	-- A wedge's right angle is at its bottom-back edge: legs up its Y and forward along -Z.
	local function half(tip: Vector3, corner: Vector3, other: Vector3)
		local up, forward = tip - corner, other - corner
		if up.Magnitude < 1e-3 or forward.Magnitude < 1e-3 then
			return
		end
		local yAxis, zAxis = up.Unit, -forward.Unit
		local wedge = Build.Wedge(table.clone(props))
		wedge.Size = Vector3.new(thickness, up.Magnitude, forward.Magnitude)
		wedge.CFrame = CFrame.fromMatrix((tip + other) / 2, yAxis:Cross(zAxis), yAxis, zAxis)
		wedge.Parent = parent
	end
	half(c, foot, a)
	half(c, foot, b)
end

-- A thin straight strand from `a` to `b` (cobwebs).
local function strand(parent: Instance, a: Vector3, b: Vector3, width: number)
	local length = (b - a).Magnitude
	if length < 1e-3 then
		return
	end
	-- (A strand straight up or down needs another "up" to look along.)
	local up = if math.abs((b - a).Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	Build.Decor({
		Name = "Strand",
		Size = Vector3.new(width, width, length),
		CFrame = CFrame.lookAt((a + b) / 2, b, up),
		Color = WEB,
		Transparency = 0.15,
		Parent = parent,
	})
end

-- Where the ground (or whatever the lobby has there: a stage floor, a speaker's top) is under `at`.
local function groundAt(at: Vector3): Vector3
	local root = lobby
	if not root then
		return at
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { root, workspace.Terrain }
	local origin = Vector3.new(at.X, at.Y + 60, at.Z)
	local hit = workspace:Raycast(origin, Vector3.new(0, -120, 0), params)
	return if hit then hit.Position else at
end

-- The carved, glowing face on a pumpkin standing at `ground` (its front looks along LookVector),
-- `scale` times the golden pumpkin's size. Each point is put on the pumpkin's skin (it's close to
-- an egg 3.6 wide, 2.3 tall, centred 1.15 up), a little proud of it so the ribs never poke through.
local function carve(parent: Instance, ground: CFrame, scale: number)
	local function onSkin(x: number, y: number): Vector3
		local inside = 1 - (x / 1.8) ^ 2 - ((y - 1.15) / 1.15) ^ 2
		local depth = 1.83 * math.sqrt(math.max(0.05, inside)) + 0.1
		return ground:PointToWorldSpace(Vector3.new(x, y, -depth) * scale)
	end
	local props = decorProps({ Name = "Face", Color = FACE, Material = Enum.Material.Neon })
	local thickness = 0.06 * scale
	for _, side in { -1, 1 } do
		-- An eye: a triangle pointing up.
		triangle(parent, onSkin(side * 0.26, 1.4), onSkin(side * 0.92, 1.4), onSkin(side * 0.6, 1.84), thickness, props)
	end
	triangle(parent, onSkin(-0.15, 1.13), onSkin(0.15, 1.13), onSkin(0, 1.33), thickness, props) -- nose
	-- A wide grin: two triangles meeting under the nose.
	triangle(parent, onSkin(-0.98, 0.94), onSkin(0, 0.48), onSkin(0, 0.8), thickness, props)
	triangle(parent, onSkin(0.98, 0.94), onSkin(0, 0.48), onSkin(0, 0.8), thickness, props)
end

-- A pumpkin standing at `ground` (its front looks along LookVector), `scale` times Rake It In's
-- golden pumpkin (2.9 tall), painted orange. `lit`: a jack-o'-lantern, with a face and a candle.
local function pumpkin(parent: Instance, ground: CFrame, scale: number, lit: boolean): Model
	-- (The prop keeps its name: tools/preview renders it from its mesh.)
	local model = MeshLibrary.Get("GoldenPumpkin", {
		Scale = scale,
		Colors = { PumpkinBody = PUMPKIN, PumpkinStem = STEM },
		CFrame = ground,
		Parent = parent,
	})
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Material = Enum.Material.SmoothPlastic -- not the golden foil
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	if lit then
		carve(model, ground, scale)
		local candle = Build.Decor({
			Name = "Candle",
			Size = Vector3.one * 0.2,
			Transparency = 1,
			CFrame = ground * CFrame.new(0, 1.15 * scale, 0),
			Parent = model,
		})
		Build.Light(candle, CANDLE, 8 + 6 * scale, 1.4)
	end
	return model
end

-- A little bat, wings up, about 4 wide at scale 1, flying along `cframe.LookVector`.
local function bat(parent: Instance, cframe: CFrame, scale: number)
	local model = Build.Model("Bat", parent)
	Build.Decor({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.95 * scale,
		CFrame = cframe,
		Color = BAT,
		Parent = model,
	})
	Build.Decor({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.62 * scale,
		CFrame = cframe * CFrame.new(0, 0.2 * scale, -0.55 * scale),
		Color = BAT,
		Parent = model,
	})
	local props = decorProps({ Name = "Wing", Color = BAT })
	for _, side in { -1, 1 } do
		local function at(x: number, y: number, z: number): Vector3
			return cframe:PointToWorldSpace(Vector3.new(side * x, y, z) * scale)
		end
		-- A swept wing: the leading edge out to a raised tip, the trailing edge back to the body.
		triangle(model, at(0.3, 0.05, -0.3), at(2.05, 0.75, -0.1), at(0.3, 0, 0.45), 0.08 * scale, props)
		triangle(model, at(0.3, 0, 0.45), at(2.05, 0.75, -0.1), at(1.15, 0.3, 0.55), 0.08 * scale, props)
	end
end

-- Bats circling `center` at `radius` (each device turns the ring: AmbienceController, tag PP_Spin;
-- the ring's pivot is its centre, set on the model itself so it's right on every device at once).
local function batRing(parent: Instance, center: Vector3, radius: number, count: number, scale: number)
	local ring = Build.Model("BatRing", parent)
	for index = 1, count do
		local angle = (index - 1) / count * math.pi * 2 + 0.4
		local position = center
			+ Vector3.new(math.cos(angle) * radius, math.sin(index * 2.1) * 1.2, math.sin(angle) * radius)
		-- PP_Spin turns the ring about +Y, so each bat flies along (sin, 0, -cos) of its angle, and
		-- banks a little into the turn.
		local heading = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		bat(ring, CFrame.lookAt(position, position + heading) * CFrame.Angles(0, 0, -0.25), scale)
	end
	ring.WorldPivot = CFrame.new(center)
	CollectionService:AddTag(ring, "PP_Spin")
	return ring
end

-- A small round ghost floating at `cframe` (facing its LookVector), bobbing on each device (tag
-- PP_Bob), with a pale glow.
local function ghost(parent: Instance, cframe: CFrame)
	local model = Build.Model("Ghost", parent)
	local function piece(name: string, shape: Enum.PartType, size: Vector3, at: CFrame, color: Color3?)
		return Build.Decor({
			Name = name,
			Shape = shape,
			Size = size,
			CFrame = cframe * at,
			Color = color or GHOST,
			Transparency = if color then 0 else 0.08,
			Parent = model,
		})
	end
	local head = piece("Head", Enum.PartType.Ball, Vector3.one * 2.4, CFrame.new())
	-- The sheet: a short upright cylinder under the head, its hem a row of little balls.
	piece(
		"Sheet",
		Enum.PartType.Cylinder,
		Vector3.new(1.9, 2.36, 2.36),
		CFrame.new(0, -0.95, 0) * CFrame.Angles(0, 0, math.rad(90))
	)
	for index = 0, 5 do
		local angle = index / 6 * math.pi * 2
		piece(
			"Hem",
			Enum.PartType.Ball,
			Vector3.one * 0.9,
			CFrame.new(math.cos(angle) * 0.82, -1.9, math.sin(angle) * 0.82)
		)
	end
	local dark = rgb(40, 32, 60)
	piece("Eye", Enum.PartType.Ball, Vector3.one * 0.42, CFrame.new(-0.42, 0.18, -1.02), dark)
	piece("Eye", Enum.PartType.Ball, Vector3.one * 0.42, CFrame.new(0.42, 0.18, -1.02), dark)
	piece("Mouth", Enum.PartType.Ball, Vector3.new(0.38, 0.5, 0.38), CFrame.new(0, -0.38, -1.04), dark)
	Build.Light(head, rgb(205, 180, 255), 10, 0.9)
	model.WorldPivot = cframe
	CollectionService:AddTag(model, "PP_Bob")
end

-- A corner cobweb: strands from `corner` fanning between the directions `first` and `second`, and
-- two rings of threads across them.
local function cobweb(parent: Instance, corner: Vector3, first: Vector3, second: Vector3, radius: number)
	local model = Build.Model("Cobweb", parent)
	local spokes = 4
	local ends = {}
	for index = 0, spokes - 1 do
		local t = index / (spokes - 1)
		local direction = (first.Unit * (1 - t) + second.Unit * t).Unit
		local reach = radius * (if index % 2 == 0 then 1 else 0.88)
		strand(model, corner, corner + direction * reach, 0.05)
		table.insert(ends, direction)
	end
	for _, share in { 0.45, 0.8 } do
		for index = 1, spokes - 1 do
			-- A thread sags a little toward the corner between two spokes.
			local a = corner + ends[index] * radius * share
			local b = corner + ends[index + 1] * radius * share
			local middle = corner + (ends[index] + ends[index + 1]).Unit * radius * share * 0.9
			strand(model, a, middle, 0.04)
			strand(model, middle, b, 0.04)
		end
	end
end

-- Low mist drifting over the grass around `at` (switched off with "reduced effects": PP_Ambient).
local function mist(parent: Instance, at: Vector3)
	local holder = Build.Decor({
		Name = "Mist",
		Size = Vector3.new(16, 1, 16),
		Transparency = 1,
		CFrame = CFrame.new(at + Vector3.new(0, 0.8, 0)),
		Parent = parent,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE
	emitter.Color = ColorSequence.new(MIST)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 10) })
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.84),
		NumberSequenceKeypoint.new(0.75, 0.88),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(8, 11)
	emitter.Rate = 1.4
	emitter.Speed = NumberRange.new(0.3, 0.9)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 0.04, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-8, 8)
	emitter.LightEmission = 0.1
	emitter.Parent = holder
	CollectionService:AddTag(emitter, "PP_Ambient")
end

-- The HALLOWEEN PARTY ---------------------------------------------------------------------------------

-- The lamp posts on the south lawn (between the quest corner and the arcade range, round behind the
-- emote stage), from the west round to the east. The ones by the shop and the podium stay plain.
local function southLamps(root: Model): { Vector3 }
	local list = {}
	for _, item in root:GetDescendants() do
		if item:IsA("Model") and item:GetAttribute("PP_Prop") == "LampPost" then
			local position = item:GetPivot().Position
			if position.Z > 30 then
				table.insert(list, position)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.X < b.X
	end)
	return list
end

-- A CFrame on the ground at (x, z) that looks at `target` (level).
local function standing(x: number, z: number, target: Vector3, y: number?): CFrame
	local ground = groundAt(Vector3.new(x, y or 0, z))
	return CFrame.lookAt(ground, Vector3.new(target.X, ground.Y, target.Z))
end

local function halloween(root: Model, into: Model)
	local center = Vector3.zero
	-- Jack-o'-lanterns at the foot of the south lamp posts (with a little one beside), each lamp
	-- with a cobweb between its pole and the bunting to the next one.
	local lamps = southLamps(root)
	for index, lamp in lamps do
		local inward = Vector3.new(-lamp.X, 0, -lamp.Z).Unit
		local across = Vector3.new(-inward.Z, 0, inward.X)
		local spot = lamp + inward * 2.1 + across * 1.1
		pumpkin(into, standing(spot.X, spot.Z, center), 0.8, true)
		local small = lamp + inward * 1.6 - across * 1.5
		pumpkin(into, standing(small.X, small.Z, center) * CFrame.Angles(0, 0.7 * index, 0), 0.5, false)
		local neighbour = lamps[index + 1] or lamps[index - 1]
		if neighbour and (neighbour - lamp).Magnitude < 40 then
			local toward = Vector3.new(neighbour.X - lamp.X, 0, neighbour.Z - lamp.Z).Unit
			local corner = Vector3.new(lamp.X, 10.1, lamp.Z) + toward * 0.35
			cobweb(into, corner, Vector3.new(0, -1, 0), toward - Vector3.new(0, 0.3, 0), 3.2)
		end
	end
	-- The vote stage: a big jack-o'-lantern on each speaker stack, and one at each front corner of
	-- the stage floor (by the light towers, outside the portals).
	for _, side in { -1, 1 } do
		pumpkin(into, standing(side * 51, -57, Vector3.new(0, 0, 12), 40), 1.25, true)
		pumpkin(into, standing(side * 43.6, -42.4, center, 10), 0.9, true)
	end
	-- Pumpkin piles at the outer ends of the flower beds beside the emote stage.
	for _, side in { -1, 1 } do
		local x, z = side * 28.3, 55.7
		pumpkin(into, standing(x, z, center), 1, true)
		pumpkin(into, standing(x + side * 1.9, z + 1.4, center) * CFrame.Angles(0, 1.1, 0), 0.62, false)
		pumpkin(into, standing(x - side * 1.4, z + 2, center) * CFrame.Angles(0, -0.6, 0), 0.5, false)
	end
	-- Bats: over the fountain's trophy, over the emote stage's crown, round the stage's towers.
	batRing(into, Vector3.new(0, 27, 0), 9, 3, 1)
	batRing(into, Vector3.new(0, 35, 56), 9, 3, 1)
	batRing(into, Vector3.new(-50, 50, -70), 7, 2, 1.1)
	batRing(into, Vector3.new(50, 50, -70), 7, 2, 1.1)
	-- Two ghosts on the south lawn, either side of the emote stage, looking at the fountain.
	for _, side in { -1, 1 } do
		local position = Vector3.new(side * 33, 4.6, 65)
		ghost(into, CFrame.lookAt(position, Vector3.new(0, 4.6, 0)))
	end
	-- Cobwebs in the emote stage arch's top corners, on its front.
	for _, side in { -1, 1 } do
		cobweb(into, Vector3.new(side * 12.7, 16, 60.6), Vector3.new(0, -1, 0), Vector3.new(-side, 0, 0), 3.4)
	end
	-- Mist on the south lawn's edge.
	for _, degrees in { 50, 70, 90, 110, 130 } do
		local angle = math.rad(degrees)
		mist(into, Vector3.new(math.cos(angle) * 68, 0, math.sin(angle) * 68))
	end
end

local SETS: { [string]: (root: Model, into: Model) -> () } = {
	Halloween = halloween,
}

-- The hunt's golden pumpkin at `ground`: it sparkles, a 🍬 floats over it, and a touch anywhere in
-- its hitbox (a ball round it, easy to walk into) is what EventService listens for.
local function huntPumpkin(parent: Instance, ground: CFrame, spot: number): Model
	local model = MeshLibrary.Get("GoldenPumpkin", { Scale = 0.6, CFrame = ground, Parent = parent })
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	local hitbox = Build.Decor({
		Name = "Hitbox",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 5,
		Transparency = 1,
		CFrame = ground * CFrame.new(0, 1.2, 0),
		CanTouch = true,
		Parent = model,
	})
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = SPARKLE
	sparkles.Color = ColorSequence.new(rgb(255, 226, 120))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Lifetime = NumberRange.new(1, 1.6)
	sparkles.Speed = NumberRange.new(1, 2.5)
	sparkles.SpreadAngle = Vector2.new(60, 60)
	sparkles.Rate = 5
	sparkles.Parent = hitbox
	Build.Light(hitbox, rgb(255, 214, 110), 9, 1.1)
	Build.Billboard(hitbox, "🍬", {
		Name = "Candy",
		Size = UDim2.fromScale(2.2, 2.2),
		StudsOffset = Vector3.new(0, 2.4, 0),
		MaxDistance = 50,
	})
	model.Name = "GoldenPumpkin" -- (renders find its mesh by the prop's name)
	model:SetAttribute("Spot", spot)
	CollectionService:AddTag(model, "PP_EventPumpkin")
	return model
end

-- API ------------------------------------------------------------------------------------------------

local function clear()
	if decor then
		decor:Destroy()
	end
	decor = nil
	shown = nil
end

local function show(set: string?): boolean
	if set == shown and (set == nil or decor ~= nil) then
		return true
	end
	clear()
	local root = lobby
	local build = set and SETS[set]
	if not set or not build or not root then
		return set == nil
	end
	local model = Build.Model("EventDecor", root)
	decor = model
	shown = set
	-- A set that fails part-way keeps what it built: decorations never stop the event.
	local ok, err = pcall(build, root, model)
	if not ok then
		warn(`[EventDecor] {set}: {err}`)
	end
	return true
end

-- Builds into the lobby's model (called by LobbyBuilder after the scenery, like the arcade): the
-- decorations EventService asked for, if it already has.
function EventDecor.Build(root: Model)
	lobby = root
	if wanted then
		show(wanted)
	end
end

-- Shows the decorations of `set` (an event's Decor: "Halloween"), or none (nil): EventService calls
-- it when an event starts or ends. Before the lobby is built it waits for Build.
function EventDecor.Show(set: string?)
	wanted = set
	show(set)
end

-- The set up now (nil when none).
function EventDecor.Showing(): string?
	return shown
end

-- Where the hunt's pumpkins can hide for this set (the order is the spot numbers).
function EventDecor.HuntSpots(set: string?): { Vector3 }
	return if set then HUNT_SPOTS[set] or {} else {}
end

-- Puts the hunt's pumpkins at these spots (HuntSpots indices), replacing the ones out before, and
-- returns them (each has a "Hitbox" part and a Spot attribute). None when the set isn't up.
function EventDecor.PlaceHunt(set: string, spots: { number }): { Model }
	local model = decor
	if not model or shown ~= set then
		return {}
	end
	local old = model:FindFirstChild("Hunt")
	if old then
		old:Destroy()
	end
	local folder = Build.Folder("Hunt", model)
	local placed = {}
	for _, spot in spots do
		local where = HUNT_SPOTS[set] and HUNT_SPOTS[set][spot]
		if where then
			local ground = groundAt(where)
			local facing = CFrame.lookAt(ground, Vector3.new(0, ground.Y, 0))
			table.insert(placed, huntPumpkin(folder, facing, spot))
		end
	end
	return placed
end

return EventDecor

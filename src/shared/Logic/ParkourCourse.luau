--!strict
-- The lobby obby (owner: "the obby in the lobby is terrible. trees and stuff collides and you can just
-- run up it"): its layout and its rules as plain numbers, shared by the lobby builder (which builds it),
-- the lobby service (checkpoints and the goo) and the tests (which check every jump against the jump
-- arc, and that nothing can be skipped). Leaf module: no requires, no Roblox APIs.
--
-- The course stands in a round pool of goo with a lookout tower in the middle, in four sections:
--   1 HOP      easy hops round the left of the pool (flat, wide gaps)
--   2 CLIMB    candy pillars round the back and the right, each a proper jump higher
--   3 BALANCE  across the front of the tower: a beam, two hops, a jump onto a narrow beam, a jump off
--   4 TOWER    ledges round the tower, each a jump higher, up to the view deck on top
-- Every rise is a jump (3.6 studs, more than any avatar steps up) and every flat gap is too wide to
-- walk across, so nothing can be run up. A glowing pad starts each section; falling into the goo puts
-- you back on the last one you reached. The pool's edge is fenced (an invisible wall up to well over a
-- jump) except at the start, so no section can be reached from outside.
--
-- Course space (studs): the origin is the tower's foot on the ground; +Z points to the plaza and +X to
-- the right as seen from the plaza (the lobby builder places it with a CFrame looking away from the
-- plaza). Heights are above the plaza's ground. Angles go round the tower: 0 toward the plaza, 90 to the
-- right, 180 at the back.

local ParkourCourse = {}

-- Character movement (default.project.json) and the margins the layout keeps.
ParkourCourse.WalkSpeed = 16
ParkourCourse.JumpHeight = 7.2
ParkourCourse.Gravity = 196.2
ParkourCourse.StepUp = 3.2 -- a rise under this can be walked up (tall avatars step up about 3)
ParkourCourse.WalkGap = 4 -- a flat gap under this can be walked over without jumping
ParkourCourse.Slack = 1 -- a jump's take-off before the edge plus its landing past the edge
ParkourCourse.MinMargin = 2.5 -- every jump keeps this much reach to spare (phones)

-- The pool, the fence and the tower.
ParkourCourse.PoolRadius = 23 -- the goo's edge (the fence stands just outside it)
ParkourCourse.Floor = 2.2 -- the pool's floor, a stud under the goo (players sink into it)
ParkourCourse.GooTop = 3.2
ParkourCourse.FenceTop = 20.2 -- the invisible wall round the pool: out of reach from the ground
ParkourCourse.TowerRadius = 5.5
ParkourCourse.Opening = 12 -- half the fence's gap at the start, in degrees

ParkourCourse.Sections = {
	{ Name = "HOP", Color = { 110, 226, 140 } },
	{ Name = "CLIMB", Color = { 64, 196, 255 } },
	{ Name = "BALANCE", Color = { 255, 140, 70 } },
	{ Name = "TOWER", Color = { 255, 84, 150 } },
}

export type Piece = {
	Id: string,
	Kind: string, -- "Disc" | "Beam" | "Ledge"
	Section: number, -- its colour (1-4); the start pad and checkpoints wear the section they begin
	Stage: number, -- the checkpoint a player normally has while on it
	Checkpoint: number?, -- 0 for the start pad, 1-3 for the glowing pads
	Finish: boolean?,
	Walk: boolean?, -- reached by walking off the piece before it (a beam fixed to a pad)
	Top: number,
	-- Disc: centre and diameter. Beam: its two ends and width. Ledge: a pad on the tower's side at
	-- Angle, its inner edge against the tower, Width across and Depth out from the tower.
	Angle: number?,
	Radius: number?,
	Size: number?,
	From: { number }?,
	To: { number }?,
	Width: number?,
	Depth: number?,
	-- Filled in below: centre, footprint and (for beams and ledges) facing.
	X: number,
	Z: number,
	Length: number?,
	Yaw: number?, -- radians: the beam's or ledge's length runs along (sin Yaw, -cos Yaw) in X, Z
	Polygon: { { number } },
}

local DECK_TOP = 37.4 -- 4 above the last ledge, so it's out of reach from the one before

local function disc(
	id: string,
	section: number,
	stage: number,
	angle: number,
	radius: number,
	top: number,
	size: number
)
	return {
		Id = id,
		Kind = "Disc",
		Section = section,
		Stage = stage,
		Angle = angle,
		Radius = radius,
		Top = top,
		Size = size,
	}
end

local function beam(id: string, stage: number, from: { number }, to: { number }, top: number, width: number)
	return { Id = id, Kind = "Beam", Section = 3, Stage = stage, From = from, To = to, Top = top, Width = width }
end

local function ledge(
	id: string,
	section: number,
	stage: number,
	angle: number,
	top: number,
	width: number,
	depth: number
)
	return {
		Id = id,
		Kind = "Ledge",
		Section = section,
		Stage = stage,
		Angle = angle,
		Top = top,
		Width = width,
		Depth = depth,
	}
end

-- The route, in order. Every piece is a jump from the one before it unless it says Walk.
local route: { any } = {
	-- The start pad straddles the fence's gap, toward the plaza.
	disc("Start", 1, 0, 0, 24.8, 3.8, 8),
	-- 1 HOP: round the left of the pool, 4.3 studs apart.
	disc("Hop1", 1, 0, -25, 17, 4.6, 6),
	disc("Hop2", 1, 0, -60.2, 17, 4.6, 6),
	disc("Hop3", 1, 0, -95.5, 17, 4.6, 6),
	disc("Hop4", 1, 0, -130.7, 17, 4.6, 6),
	disc("Checkpoint1", 2, 1, -168.7, 17, 4.6, 7.5),
	-- 2 CLIMB: pillars round the back and the right, 3.6 higher and 2.6 apart.
	disc("Pillar1", 2, 1, 160.3, 17, 8.2, 5.5),
	disc("Pillar2", 2, 1, 132.8, 17, 11.8, 5.5),
	disc("Pillar3", 2, 1, 105.3, 17, 15.4, 5.5),
	disc("Checkpoint2", 3, 2, 74.2, 17, 19, 7.5),
	-- 3 BALANCE: a beam off the pad, a hop, a jump up, a jump onto a narrow beam and off it.
	beam("Beam1", 2, { 66.2, 13.6 }, { 38.2, 12 }, 19, 1.8),
	disc("Hop5", 3, 2, 5.8, 12, 19, 4.4),
	disc("Hop6", 3, 2, -28, 12, 22.6, 4.4),
	beam("Beam2", 2, { -62.4, 12 }, { -103.1, 11 }, 22.6, 1.8),
	ledge("Checkpoint3", 4, 3, -151, 22.6, 6, 5),
	-- 4 TOWER: ledges round the tower, 3.6 higher each, then the view deck on top.
	ledge("Ledge1", 4, 3, 137.2, 26.2, 4.6, 4.2),
	ledge("Ledge2", 4, 3, 70.5, 29.8, 4.6, 4.2),
	ledge("Ledge3", 4, 3, 3.8, 33.4, 4.6, 4.2),
	disc("Deck", 4, 4, 0, 0, DECK_TOP, ParkourCourse.TowerRadius * 2),
}
route[1].Checkpoint = 0
route[6].Checkpoint = 1
route[10].Checkpoint = 2
route[11].Walk = true
route[15].Checkpoint = 3
route[#route].Finish = true

local function polar(angle: number, radius: number): (number, number)
	local a = math.rad(angle)
	return radius * math.sin(a), radius * math.cos(a)
end

-- A box's corners: `along` is the unit direction its length runs in.
local function boxPolygon(x: number, z: number, width: number, length: number, yaw: number): { { number } }
	local ax, az = math.sin(yaw), -math.cos(yaw)
	local cx, cz = -az, ax
	local corners = {}
	for _, corner in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local a, l = corner[1] * width / 2, corner[2] * length / 2
		table.insert(corners, { x + cx * a + ax * l, z + cz * a + az * l })
	end
	return corners
end

for _, piece in route do
	if piece.Kind == "Disc" then
		piece.X, piece.Z = polar(piece.Angle, piece.Radius)
		local corners = {}
		for index = 0, 47 do
			local a = index / 48 * math.pi * 2
			table.insert(corners, { piece.X + math.cos(a) * piece.Size / 2, piece.Z + math.sin(a) * piece.Size / 2 })
		end
		piece.Polygon = corners
	elseif piece.Kind == "Beam" then
		local x1, z1 = polar(piece.From[1], piece.From[2])
		local x2, z2 = polar(piece.To[1], piece.To[2])
		piece.X, piece.Z = (x1 + x2) / 2, (z1 + z2) / 2
		piece.Length = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
		piece.Yaw = math.atan2(x2 - x1, -(z2 - z1))
		piece.Polygon = boxPolygon(piece.X, piece.Z, piece.Width, piece.Length, piece.Yaw)
	else -- a ledge: its length runs out from the tower
		piece.X, piece.Z = polar(piece.Angle, ParkourCourse.TowerRadius + piece.Depth / 2)
		piece.Length = piece.Depth
		piece.Yaw = math.pi - math.rad(piece.Angle)
		piece.Polygon = boxPolygon(piece.X, piece.Z, piece.Width, piece.Depth, piece.Yaw)
	end
end

ParkourCourse.Pieces = route :: { Piece }
ParkourCourse.Start = route[1] :: Piece
ParkourCourse.Deck = route[#route] :: Piece
ParkourCourse.Checkpoints = { route[6], route[10], route[15] } :: { Piece } -- the glowing pads, 1-3

-- How far a jump carries a character's centre (studs, flat) before it comes back down to `rise`
-- above where it took off; 0 when the jump can't get that high.
function ParkourCourse.Reach(rise: number): number
	local v0 = math.sqrt(2 * ParkourCourse.Gravity * ParkourCourse.JumpHeight)
	local inside = v0 * v0 - 2 * ParkourCourse.Gravity * rise
	if inside < 0 then
		return 0
	end
	return ParkourCourse.WalkSpeed * (v0 + math.sqrt(inside)) / ParkourCourse.Gravity
end

local function pointInPolygon(x: number, z: number, polygon: { { number } }): boolean
	local sign = 0
	for index, a in polygon do
		local b = polygon[index % #polygon + 1]
		local cross = (b[1] - a[1]) * (z - a[2]) - (b[2] - a[2]) * (x - a[1])
		if math.abs(cross) > 1e-9 then
			local s = if cross > 0 then 1 else -1
			if sign == 0 then
				sign = s
			elseif s ~= sign then
				return false
			end
		end
	end
	return true
end

local function segmentDistance(x: number, z: number, a: { number }, b: { number }): number
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local t = math.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / (dx * dx + dz * dz), 0, 1)
	local px, pz = a[1] + dx * t - x, a[2] + dz * t - z
	return math.sqrt(px * px + pz * pz)
end

-- The flat gap between two pieces' tops, edge to edge (0 if they touch or overlap).
function ParkourCourse.Gap(a: Piece, b: Piece): number
	if a.Kind == "Disc" and b.Kind == "Disc" then
		local d = math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
		return math.max(0, d - (a.Size :: number) / 2 - (b.Size :: number) / 2)
	end
	for _, p in a.Polygon do
		if pointInPolygon(p[1], p[2], b.Polygon) then
			return 0
		end
	end
	for _, p in b.Polygon do
		if pointInPolygon(p[1], p[2], a.Polygon) then
			return 0
		end
	end
	local best = math.huge
	for _, pair in { { a.Polygon, b.Polygon }, { b.Polygon, a.Polygon } } do
		local points, edges = pair[1], pair[2]
		for _, p in points do
			for index, e in edges do
				best = math.min(best, segmentDistance(p[1], p[2], e, edges[index % #edges + 1]))
			end
		end
	end
	return best
end

-- Whether a point (course space) is over a piece's top, with `margin` studs to spare round it.
function ParkourCourse.Over(piece: Piece, x: number, z: number, margin: number?): boolean
	local extra = margin or 0
	if piece.Kind == "Disc" then
		return (x - piece.X) ^ 2 + (z - piece.Z) ^ 2 <= ((piece.Size :: number) / 2 + extra) ^ 2
	end
	local yaw = piece.Yaw :: number
	local ax, az = math.sin(yaw), -math.cos(yaw)
	local dx, dz = x - piece.X, z - piece.Z
	local along = dx * ax + dz * az
	local across = dx * -az + dz * ax
	return math.abs(along) <= (piece.Length :: number) / 2 + extra
		and math.abs(across) <= (piece.Width :: number) / 2 + extra
end

-- The piece whose top a character's feet (course space) are on, if any.
function ParkourCourse.PieceAt(x: number, z: number, feet: number): Piece?
	for _, piece in ParkourCourse.Pieces do
		if math.abs(feet - piece.Top) < 1.2 and ParkourCourse.Over(piece, x, z, 0.6) then
			return piece
		end
	end
	return nil
end

-- Whether a character's feet (course space) are down in the goo.
function ParkourCourse.InGoo(x: number, z: number, feet: number): boolean
	return feet < ParkourCourse.GooTop - 0.2 and x * x + z * z < ParkourCourse.PoolRadius ^ 2
end

-- One look at a player in the obby: their feet are at (x, feet, z) in course space and they've reached
-- checkpoint `reached` (0: none yet). Returns the checkpoint they have now, whether to put them back on
-- it (they're in the goo, or they fell onto an earlier section), and whether they just reached it.
-- The start pad begins a new run and the view deck ends one, so after either a fall goes to the start.
function ParkourCourse.Step(reached: number, x: number, z: number, feet: number): (number, boolean, boolean)
	if ParkourCourse.InGoo(x, z, feet) then
		return reached, true, false
	end
	local piece = ParkourCourse.PieceAt(x, z, feet)
	if not piece then
		return reached, false, false
	end
	if piece == ParkourCourse.Start or piece.Finish then
		return 0, false, false
	end
	local checkpoint = piece.Checkpoint
	if checkpoint and checkpoint > reached then
		return checkpoint, false, true
	end
	return reached, piece.Stage < reached, false
end

-- Where a player on checkpoint `index` is put back: the pad's centre, and the direction (course
-- space, flat) to face, toward the next piece.
function ParkourCourse.Respawn(index: number): (number, number, number, number, number)
	local pad = ParkourCourse.Checkpoints[index] or ParkourCourse.Start -- 0: the start pad
	local position = table.find(ParkourCourse.Pieces, pad) :: number
	local nextPiece = ParkourCourse.Pieces[position + 1] or pad
	local dx, dz = nextPiece.X - pad.X, nextPiece.Z - pad.Z
	local length = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
	return pad.X, pad.Top, pad.Z, dx / length, dz / length
end

export type Jump = {
	From: Piece,
	To: Piece,
	Gap: number,
	Rise: number,
	Need: number, -- flat distance the centre has to carry: the gap plus Slack
	Reach: number,
	Margin: number,
	Walk: boolean, -- a planned walk (a beam fixed to a pad), not a jump
}

-- Every step of the route with what it needs and what a jump gives.
function ParkourCourse.Jumps(): { Jump }
	local jumps = {}
	for index = 2, #ParkourCourse.Pieces do
		local a, b = ParkourCourse.Pieces[index - 1], ParkourCourse.Pieces[index]
		local gap = ParkourCourse.Gap(a, b)
		local rise = b.Top - a.Top
		local reach = ParkourCourse.Reach(rise)
		local need = gap + ParkourCourse.Slack
		table.insert(jumps, {
			From = a,
			To = b,
			Gap = gap,
			Rise = rise,
			Need = need,
			Reach = reach,
			Margin = reach - need,
			Walk = b.Walk == true,
		})
	end
	return jumps
end

return ParkourCourse

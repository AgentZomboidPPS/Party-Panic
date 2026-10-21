-- Tanks! shared rules (server and clients run the same code): the play-room's layout, how a tank
-- drives and where a shell flies.
--
--   * The layout is a grid of 8-stud cork tiles inside a wall of wooden blocks: '#' is a tall
--     wooden block (8 high), '+' a low toy brick (4 high) a tank can hide behind, '.' open floor and
--     1-9/A-C the spawn spots in the order they're used (any first N are spread out). Small rooms
--     for up to 6 tanks, big ones for 7-12.
--   * A tank drives like the Wii original: it turns toward the stick and goes, or backs up when the
--     stick points behind it (so a quick reverse never needs a U-turn). Blocks and other tanks stop
--     it (2D box-vs-box push-out, the hull's real footprint).
--   * A shell flies straight at SHELL_SPEED, ricochets once off a wall (a true reflection off the
--     face it hit: the boxes are padded by the shell's radius, so it bounces where its surface
--     touches) and is gone at the second wall. Its whole flight follows from the shot (where, which
--     way, when), so clients draw it from one event and the server checks it against the same path.
--
-- Coordinates are flat (x, z) studs from the arena's center; heading h faces (-sin h, -cos h), the
-- look direction of CFrame.Angles(0, h, 0). Plain numbers only (no Vector3): the server and clients
-- must trace the same paths, and Vector3 math is single precision.

local TankField = {}

TankField.TILE = 8
-- The hull's footprint, tracks outside to outside (assets/meshes/TanksTank.glb: 6.4 x 7.6).
TankField.HALF_WIDTH = 3.2
TankField.HALF_LENGTH = 3.8
TankField.SPEED = 13 -- studs/s
TankField.TURN = math.rad(220) -- hull turn rate, rad/s
TankField.ACCEL = 9 -- 1/s: how fast the speed reaches the stick's
TankField.SHELL_SPEED = 28 -- about twice a tank's speed: a shell you see coming can be dodged
TankField.SHELL_RADIUS = 0.45 -- assets/meshes/TanksShell.glb is 0.9 thick
TankField.SHELL_Y = 3.1 -- a shell's center above the floor (the barrel's height)
TankField.MUZZLE = 5.4 -- from the tank's center to the barrel's tip
TankField.MAX_SHELLS = 2 -- in flight per tank
TankField.RELOAD = 0.3 -- seconds between shots
TankField.MAX_MINES = 2
TankField.MINE_GAP = 1 -- seconds between mines
TankField.MINE_ARM = 1.5 -- a fresh mine can't go off by itself being driven over until then
TankField.MINE_FUSE = 7 -- it blows by itself this long after it's laid
TankField.MINE_TRIGGER = 1.0 -- an armed mine goes off when a hull comes this close to its center
TankField.MINE_RADIUS = 1.3 -- the mine you see (a shell that touches it sets it off)
TankField.MINE_BLAST = 10 -- everything this close to the blast is caught in it
TankField.CHAIN_DELAY = 0.15 -- a mine caught in a blast goes off this much later
TankField.SHIELD = 3 -- seconds after GO when every tank is shielded (a shell or blast just pops)
TankField.OWN_SAFE = 0.5 -- a tank's own shell can't hit it in its first half second (point-blank walls)
TankField.WALL_HEIGHT = 8
TankField.COVER_HEIGHT = 4

-- The twelve tank colours (each tank also carries its driver's name: colour is never the only cue).
TankField.COLORS = {
	Color3.fromRGB(232, 64, 58),
	Color3.fromRGB(52, 120, 235),
	Color3.fromRGB(70, 190, 80),
	Color3.fromRGB(250, 205, 50),
	Color3.fromRGB(250, 140, 40),
	Color3.fromRGB(150, 90, 220),
	Color3.fromRGB(250, 120, 190),
	Color3.fromRGB(40, 200, 200),
	Color3.fromRGB(240, 240, 235),
	Color3.fromRGB(70, 72, 82),
	Color3.fromRGB(170, 230, 60),
	Color3.fromRGB(160, 105, 60),
}

local TILE = TankField.TILE
local HUGE = math.huge
local PI = math.pi
local TAU = 2 * math.pi

-- Up to 6 tanks: 15 x 11 tiles (120 x 88 studs).
local SMALL = {
	"...............",
	".1..+..5..+..3.",
	"...............",
	"...##.....##...",
	"...#...+...#...",
	".+....#.#....+.",
	"...#...+...#...",
	"...##.....##...",
	"...............",
	".4..+..6..+..2.",
	"...............",
}

-- 7 to 12 tanks: 21 x 15 tiles (168 x 120 studs).
local LARGE = {
	".....................",
	".1...+....5....+...3.",
	"........+...+........",
	"...##.....+.....##...",
	".+.#..9...+...B..#.+.",
	"...#.....+.+.....#...",
	"........#...#........",
	".7....+.#.+.#.+....8.",
	"........#...#........",
	"...#.....+.+.....#...",
	".+.#..C...+...A..#.+.",
	"...##.....+.....##...",
	"........+...+........",
	".4...+....6....+...2.",
	".....................",
}

local SPAWN_ORDER = "123456789ABC"

export type Box = {
	X0: number,
	Z0: number,
	X1: number,
	Z1: number,
	CX: number,
	CZ: number,
	HW: number,
	HL: number,
	Kind: string, -- "Wall" (the room's edge), "Block" ('#') or "Cover" ('+')
	Tiles: number,
}

export type Field = {
	Name: string,
	Cols: number,
	Rows: number,
	Width: number,
	Depth: number,
	Grid: { { string } }, -- Grid[row][col]: "#", "+" or "."
	Boxes: { Box },
	Spawns: { { number } }, -- { x, z } in the order they're handed out
}

export type Segment = { X: number, Z: number, DX: number, DZ: number, Length: number, S: number }
export type Path = { Segments: { Segment }, Length: number, Bounce: number }

export type Tank = {
	X: number,
	Z: number,
	H: number,
	V: number,
	Rev: boolean,
}

function TankField.Wrap(angle: number): number
	return (angle + PI) % TAU - PI
end

local wrap = TankField.Wrap

local function box(x0: number, z0: number, x1: number, z1: number, kind: string, tiles: number): Box
	return {
		X0 = x0,
		Z0 = z0,
		X1 = x1,
		Z1 = z1,
		CX = (x0 + x1) / 2,
		CZ = (z0 + z1) / 2,
		HW = (x1 - x0) / 2,
		HL = (z1 - z0) / 2,
		Kind = kind,
		Tiles = tiles,
	}
end

-- "S" (up to 6 tanks) or "L".
function TankField.MapFor(count: number): string
	return if count <= 6 then "S" else "L"
end

function TankField.Build(name: string): Field
	local rows = if name == "L" then LARGE else SMALL
	local rowCount, colCount = #rows, #rows[1]
	local width, depth = colCount * TILE, rowCount * TILE
	local grid = {}
	local spawns = {}
	local boxes = {}
	for r = 1, rowCount do
		local line = rows[r]
		grid[r] = {}
		local runKind, runStart = nil, 0
		for c = 1, colCount + 1 do
			local char = if c <= colCount then string.sub(line, c, c) else "."
			local kind = if char == "#" then "Block" elseif char == "+" then "Cover" else nil
			if c <= colCount then
				grid[r][c] = if kind == "Block" then "#" elseif kind == "Cover" then "+" else "."
				local order = string.find(SPAWN_ORDER, char, 1, true)
				if order then
					spawns[order] = { -width / 2 + (c - 0.5) * TILE, -depth / 2 + (r - 0.5) * TILE }
				end
			end
			-- Runs of the same kind along a row become one box (fewer boxes to trace against).
			if kind ~= runKind then
				if runKind then
					local x0 = -width / 2 + (runStart - 1) * TILE
					local x1 = -width / 2 + (c - 1) * TILE
					local z0 = -depth / 2 + (r - 1) * TILE
					table.insert(boxes, box(x0, z0, x1, z0 + TILE, runKind, c - runStart))
				end
				runKind, runStart = kind, c
			end
		end
	end
	-- The room's edge: a tile-thick wall all round, outside the play area.
	local w, d = width / 2, depth / 2
	table.insert(boxes, box(-w - TILE, -d - TILE, w + TILE, -d, "Wall", 0))
	table.insert(boxes, box(-w - TILE, d, w + TILE, d + TILE, "Wall", 0))
	table.insert(boxes, box(-w - TILE, -d, -w, d, "Wall", 0))
	table.insert(boxes, box(w, -d, w + TILE, d, "Wall", 0))
	local ordered = {}
	for index = 1, #SPAWN_ORDER do
		if spawns[index] then
			table.insert(ordered, spawns[index])
		end
	end
	return {
		Name = name,
		Cols = colCount,
		Rows = rowCount,
		Width = width,
		Depth = depth,
		Grid = grid,
		Boxes = boxes,
		Spawns = ordered,
	}
end

-- Grid helpers (tiles are 1-based: col 1 is the west edge, row 1 the north).
function TankField.Tile(field: Field, x: number, z: number): (number, number)
	return math.floor((x + field.Width / 2) / TILE) + 1, math.floor((z + field.Depth / 2) / TILE) + 1
end

function TankField.Center(field: Field, col: number, row: number): (number, number)
	return -field.Width / 2 + (col - 0.5) * TILE, -field.Depth / 2 + (row - 0.5) * TILE
end

function TankField.Open(field: Field, col: number, row: number): boolean
	local line = field.Grid[row]
	return line ~= nil and line[col] == "."
end

-- Tracing ------------------------------------------------------------------------------------------

-- The first box a ray from (x, z) along the unit (dx, dz) meets within `maxDist`, with every box
-- padded by `pad`: the distance and the face's outward normal, or nil. A ray that starts inside a
-- padded box ignores that box (it's leaving it).
function TankField.Cast(
	field: Field,
	x: number,
	z: number,
	dx: number,
	dz: number,
	maxDist: number,
	pad: number
): (number?, number, number, Box?)
	local best, bestNX, bestNZ, bestBox = maxDist, 0, 0, nil
	for _, b in field.Boxes do
		local x0, z0, x1, z1 = b.X0 - pad, b.Z0 - pad, b.X1 + pad, b.Z1 + pad
		local tmin, tmax = -HUGE, HUGE
		local nx, nz = 0, 0
		if dx ~= 0 then
			local t1, t2 = (x0 - x) / dx, (x1 - x) / dx
			local n = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				n = 1
			end
			if t1 > tmin then
				tmin, nx, nz = t1, n, 0
			end
			tmax = math.min(tmax, t2)
		elseif x <= x0 or x >= x1 then
			continue
		end
		if dz ~= 0 then
			local t1, t2 = (z0 - z) / dz, (z1 - z) / dz
			local n = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				n = 1
			end
			if t1 > tmin then
				tmin, nx, nz = t1, 0, n
			end
			tmax = math.min(tmax, t2)
		elseif z <= z0 or z >= z1 then
			continue
		end
		if tmax >= tmin and tmin >= 0 and tmin < best then
			best, bestNX, bestNZ, bestBox = tmin, nx, nz, b
		end
	end
	if bestBox then
		return best, bestNX, bestNZ, bestBox
	end
	return nil, 0, 0, nil
end

-- Whether a shell could fly straight from (x0, z0) to (x1, z1).
function TankField.Clear(field: Field, x0: number, z0: number, x1: number, z1: number, pad: number?): boolean
	local dx, dz = x1 - x0, z1 - z0
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-6 then
		return true
	end
	local hit = TankField.Cast(field, x0, z0, dx / length, dz / length, length, pad or TankField.SHELL_RADIUS)
	return hit == nil
end

-- A shell's flight from (x, z) along heading `aim`: straight to the first wall, a reflection off
-- that face, straight on to the second wall.
function TankField.Path(field: Field, x: number, z: number, aim: number): Path
	local dx, dz = -math.sin(aim), -math.cos(aim)
	local segments = {}
	local s = 0
	local px, pz = x, z
	for bounce = 0, 1 do
		local dist, nx, nz = TankField.Cast(field, px, pz, dx, dz, 1000, TankField.SHELL_RADIUS)
		local length = dist or 1000
		table.insert(segments, { X = px, Z = pz, DX = dx, DZ = dz, Length = length, S = s })
		s += length
		if bounce == 0 then
			px += dx * length
			pz += dz * length
			local dot = dx * nx + dz * nz
			dx -= 2 * dot * nx
			dz -= 2 * dot * nz
		end
	end
	return { Segments = segments, Length = s, Bounce = segments[1].Length }
end

-- Where a shell is `s` studs along its path, and which way it's flying.
function TankField.At(path: Path, s: number): (number, number, number, number)
	local segments = path.Segments
	local segment = segments[1]
	if s > segment.Length and segments[2] then
		segment = segments[2]
	end
	local along = math.clamp(s - segment.S, 0, segment.Length)
	return segment.X + segment.DX * along, segment.Z + segment.DZ * along, segment.DX, segment.DZ
end

-- Calls fn(xa, za, xb, zb, sa, sb) for each straight piece of the path between s0 and s1.
function TankField.Pieces(
	path: Path,
	s0: number,
	s1: number,
	fn: (number, number, number, number, number, number) -> ()
)
	s0 = math.max(s0, 0)
	s1 = math.min(s1, path.Length)
	if s1 <= s0 then
		return
	end
	for _, segment in path.Segments do
		local a = math.max(s0, segment.S)
		local b = math.min(s1, segment.S + segment.Length)
		if b > a then
			local ua, ub = a - segment.S, b - segment.S
			fn(
				segment.X + segment.DX * ua,
				segment.Z + segment.DZ * ua,
				segment.X + segment.DX * ub,
				segment.Z + segment.DZ * ub,
				a,
				b
			)
		end
	end
end

-- Hulls --------------------------------------------------------------------------------------------

-- The point (px, pz) in a hull's own frame: across (right +) and along (front +).
function TankField.Local(tank: Tank, px: number, pz: number): (number, number)
	local ox, oz = px - tank.X, pz - tank.Z
	local c, s = math.cos(tank.H), math.sin(tank.H)
	-- right = (cos h, -sin h), front = (-sin h, -cos h)
	return ox * c - oz * s, -ox * s - oz * c
end

-- How far the point is from the hull's footprint (0 inside).
function TankField.HullDistance(tank: Tank, px: number, pz: number): number
	local lx, lz = TankField.Local(tank, px, pz)
	local ex = math.max(math.abs(lx) - TankField.HALF_WIDTH, 0)
	local ez = math.max(math.abs(lz) - TankField.HALF_LENGTH, 0)
	return math.sqrt(ex * ex + ez * ez)
end

-- Where along the segment (0..1) it first enters the hull padded by `pad`, or nil.
function TankField.SegmentHitsHull(tank: Tank, xa: number, za: number, xb: number, zb: number, pad: number): number?
	local ax, az = TankField.Local(tank, xa, za)
	local bx, bz = TankField.Local(tank, xb, zb)
	local hw, hl = TankField.HALF_WIDTH + pad, TankField.HALF_LENGTH + pad
	local dx, dz = bx - ax, bz - az
	local tmin, tmax = 0, 1
	if math.abs(dx) < 1e-9 then
		if math.abs(ax) > hw then
			return nil
		end
	else
		local t1, t2 = (-hw - ax) / dx, (hw - ax) / dx
		if t1 > t2 then
			t1, t2 = t2, t1
		end
		tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
	end
	if math.abs(dz) < 1e-9 then
		if math.abs(az) > hl then
			return nil
		end
	else
		local t1, t2 = (-hl - az) / dz, (hl - az) / dz
		if t1 > t2 then
			t1, t2 = t2, t1
		end
		tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
	end
	if tmin <= tmax then
		return tmin
	end
	return nil
end

-- Separating axes for two boxes (center, heading, half width, half length): how deep box A is in
-- box B and the unit direction that pushes A out, or nil when they don't touch.
local function overlap(
	ax: number,
	az: number,
	ah: number,
	aw: number,
	al: number,
	bx: number,
	bz: number,
	bh: number,
	bw: number,
	bl: number
): (number?, number, number)
	local arx, arz = math.cos(ah), -math.sin(ah)
	local afx, afz = -math.sin(ah), -math.cos(ah)
	local brx, brz = math.cos(bh), -math.sin(bh)
	local bfx, bfz = -math.sin(bh), -math.cos(bh)
	local ox, oz = ax - bx, az - bz
	local best, bestX, bestZ = HUGE, 0, 0
	local axes = { arx, arz, afx, afz, brx, brz, bfx, bfz }
	for index = 1, 7, 2 do
		local nx, nz = axes[index], axes[index + 1]
		local ra = aw * math.abs(arx * nx + arz * nz) + al * math.abs(afx * nx + afz * nz)
		local rb = bw * math.abs(brx * nx + brz * nz) + bl * math.abs(bfx * nx + bfz * nz)
		local along = ox * nx + oz * nz
		local depth = ra + rb - math.abs(along)
		if depth <= 0 then
			return nil, 0, 0
		end
		if depth < best then
			local sign = if along >= 0 then 1 else -1
			best, bestX, bestZ = depth, nx * sign, nz * sign
		end
	end
	return best, bestX, bestZ
end

-- Pushes a hull out of every block it overlaps.
function TankField.Collide(field: Field, tank: Tank)
	local reach = TankField.HALF_LENGTH + TankField.HALF_WIDTH
	for _ = 1, 3 do
		local moved = false
		for _, b in field.Boxes do
			if math.abs(tank.X - b.CX) > b.HW + reach or math.abs(tank.Z - b.CZ) > b.HL + reach then
				continue
			end
			local depth, nx, nz =
				overlap(tank.X, tank.Z, tank.H, TankField.HALF_WIDTH, TankField.HALF_LENGTH, b.CX, b.CZ, 0, b.HW, b.HL)
			if depth then
				tank.X += nx * (depth + 1e-4)
				tank.Z += nz * (depth + 1e-4)
				moved = true
			end
		end
		if not moved then
			return
		end
	end
end

-- How deep hull A is in hull B and the direction that pushes A out (nil when apart).
function TankField.HullOverlap(a: Tank, b: Tank): (number?, number, number)
	local reach = 2 * (TankField.HALF_LENGTH + TankField.HALF_WIDTH)
	if math.abs(a.X - b.X) > reach or math.abs(a.Z - b.Z) > reach then
		return nil, 0, 0
	end
	local w, l = TankField.HALF_WIDTH, TankField.HALF_LENGTH
	return overlap(a.X, a.Z, a.H, w, l, b.X, b.Z, b.H, w, l)
end

-- Driving ------------------------------------------------------------------------------------------

-- One step of driving from the stick (mx, mz: a world direction, length 0..1). Turns toward it (or
-- toward its opposite when it points behind: then it backs up) and rolls once roughly lined up.
function TankField.Drive(tank: Tank, mx: number, mz: number, dt: number)
	local magnitude = math.sqrt(mx * mx + mz * mz)
	local target = 0
	if magnitude > 0.25 then
		magnitude = math.min(magnitude, 1)
		local want = math.atan2(-mx, -mz)
		local diff = math.abs(wrap(want - tank.H))
		if diff > math.rad(115) then
			tank.Rev = true
		elseif diff < math.rad(65) then
			tank.Rev = false
		end
		local goal = if tank.Rev then wrap(want + PI) else want
		local turn = wrap(goal - tank.H)
		local step = TankField.TURN * dt
		tank.H = wrap(tank.H + math.clamp(turn, -step, step))
		local left = math.abs(wrap(goal - tank.H))
		-- Full speed once within ~25 degrees, turning on the spot past 60.
		target = TankField.SPEED * magnitude * math.clamp((math.cos(left) - 0.5) / 0.4, 0, 1)
		if tank.Rev then
			target = -target
		end
	end
	tank.V += (target - tank.V) * math.min(1, TankField.ACCEL * dt)
	if math.abs(tank.V) < 1e-3 then
		tank.V = 0
	end
	tank.X += -math.sin(tank.H) * tank.V * dt
	tank.Z += -math.cos(tank.H) * tank.V * dt
end

-- Mines --------------------------------------------------------------------------------------------

-- Whether a hull is within `radius` of a point (the blast or the trigger).
function TankField.Near(tank: Tank, px: number, pz: number, radius: number): boolean
	return TankField.HullDistance(tank, px, pz) <= radius
end

return TankField

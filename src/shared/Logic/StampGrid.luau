-- Stamp Out shared rules (the server and every client run the same code): the paper pad's grid,
-- which cells a stamp covers, the twelve inks and how far a hop goes.
--
--   * The pad is PAD x PAD studs of paper split into N x N square cells (CELL studs each). A cell
--     belongs to the last ink stamped on it. Cells are numbered 1..N*N, row by row (z, then x),
--     from the pad's -X/-Z corner. The whole pad travels as one string, one character per cell
--     ("0" empty, then "1".."<" for inks 1..12), so a late client catches up from one value.
--   * A stamp covers every cell whose center is within its radius of where it landed (flat
--     distance, pad-local studs). The server decides the landing; clients redraw from the same
--     (x, z, radius) with Disc(), so both always agree cell for cell.
--   * Each round participant gets an ink: a colour AND a symbol, so colour is never the only cue
--     (owner's house rule). The 12 colours are picked to stay apart from each other and from the
--     cream paper; the symbols are plain text glyphs every Roblox font has.
--   * A hop (the STAMP button) goes HOP_MIN..HOP_MAX studs forward depending on how long it was
--     charged, in a fixed arc; a longer hop lands a bigger stamp. A plain jump stamps too (small).
--
-- Coordinates are flat pad-local studs (x, z) from the pad's center. Plain numbers only, so the
-- server and clients compute the same cells.

local StampGrid = {}

StampGrid.PAD = 120 -- studs, the paper's side
StampGrid.CELL = 2.5 -- studs
StampGrid.N = 48 -- cells per side (PAD / CELL)
StampGrid.PAPER_TOP = 1.2 -- the paper's top above the desk top (arena origin's Y)

StampGrid.JUMP_RADIUS = 4.5 -- a plain jump's stamp
StampGrid.HOP_RADIUS_MIN = 5 -- a tapped hop
StampGrid.HOP_RADIUS_MAX = 7.5 -- a fully charged hop
StampGrid.FINAL_BOOST = 1.3 -- stamps are this much bigger in the last stretch
StampGrid.FINAL_PROGRESS = 0.75 -- ...from this share of the round on

StampGrid.CHARGE_TIME = 0.8 -- seconds of holding for a full charge
StampGrid.HOP_MIN = 10 -- studs a tapped hop travels
StampGrid.HOP_MAX = 30 -- studs a fully charged hop travels
StampGrid.HOP_UP_MIN = 42 -- launch speed up, studs/s (tap)
StampGrid.HOP_UP_MAX = 62 -- (full charge)

-- name, colour, symbol
StampGrid.INKS = {
	{ Name = "Red", Color = Color3.fromRGB(226, 40, 52), Symbol = "★" },
	{ Name = "Blue", Color = Color3.fromRGB(36, 104, 236), Symbol = "●" },
	{ Name = "Green", Color = Color3.fromRGB(34, 170, 64), Symbol = "▲" },
	{ Name = "Yellow", Color = Color3.fromRGB(250, 200, 20), Symbol = "■" },
	{ Name = "Purple", Color = Color3.fromRGB(132, 62, 206), Symbol = "♥" },
	{ Name = "Orange", Color = Color3.fromRGB(250, 122, 24), Symbol = "♦" },
	{ Name = "Cyan", Color = Color3.fromRGB(24, 196, 222), Symbol = "♣" },
	{ Name = "Pink", Color = Color3.fromRGB(246, 96, 186), Symbol = "♠" },
	{ Name = "Lime", Color = Color3.fromRGB(150, 222, 30), Symbol = "✚" },
	{ Name = "Brown", Color = Color3.fromRGB(128, 76, 38), Symbol = "☀" },
	{ Name = "Teal", Color = Color3.fromRGB(0, 120, 112), Symbol = "☾" },
	{ Name = "Black", Color = Color3.fromRGB(42, 40, 52), Symbol = "✿" },
}

local ZERO = string.byte("0")

-- The cell (ix, iz, 1-based) under a pad-local point, or nil off the paper.
function StampGrid.CellAt(x: number, z: number): (number?, number?)
	local half = StampGrid.PAD / 2
	if x < -half or x >= half or z < -half or z >= half then
		return nil, nil
	end
	local ix = math.floor((x + half) / StampGrid.CELL) + 1
	local iz = math.floor((z + half) / StampGrid.CELL) + 1
	return math.clamp(ix, 1, StampGrid.N), math.clamp(iz, 1, StampGrid.N)
end

function StampGrid.Index(ix: number, iz: number): number
	return (iz - 1) * StampGrid.N + ix
end

-- A cell's center, pad-local.
function StampGrid.Center(index: number): (number, number)
	local ix = (index - 1) % StampGrid.N + 1
	local iz = (index - ix) // StampGrid.N + 1
	local half = StampGrid.PAD / 2
	return -half + (ix - 0.5) * StampGrid.CELL, -half + (iz - 0.5) * StampGrid.CELL
end

-- Whether a pad-local point is on the paper.
function StampGrid.OnPad(x: number, z: number, margin: number?): boolean
	local half = StampGrid.PAD / 2 - (margin or 0)
	return math.abs(x) <= half and math.abs(z) <= half
end

-- Every cell a stamp of `radius` landing at (x, z) covers (pad-local studs).
function StampGrid.Disc(x: number, z: number, radius: number): { number }
	local cells = {}
	local half = StampGrid.PAD / 2
	local size = StampGrid.CELL
	local n = StampGrid.N
	local fromX = math.max(1, math.floor((x - radius + half) / size) + 1)
	local toX = math.min(n, math.floor((x + radius + half) / size) + 1)
	local fromZ = math.max(1, math.floor((z - radius + half) / size) + 1)
	local toZ = math.min(n, math.floor((z + radius + half) / size) + 1)
	local r2 = radius * radius
	for iz = fromZ, toZ do
		local cz = -half + (iz - 0.5) * size
		for ix = fromX, toX do
			local cx = -half + (ix - 0.5) * size
			local dx, dz = cx - x, cz - z
			if dx * dx + dz * dz <= r2 then
				table.insert(cells, (iz - 1) * n + ix)
			end
		end
	end
	return cells
end

-- The pad as a string (one character per cell) and back.
function StampGrid.Encode(owners: { number }): string
	local chars = table.create(#owners)
	for index, owner in owners do
		chars[index] = string.char(ZERO + owner)
	end
	return table.concat(chars)
end

function StampGrid.Decode(text: string): { number }
	local count = StampGrid.N * StampGrid.N
	local owners = table.create(count, 0)
	if type(text) == "string" and #text == count then
		for index = 1, count do
			local owner = string.byte(text, index) - ZERO
			owners[index] = if owner >= 0 and owner <= #StampGrid.INKS then owner else 0
		end
	end
	return owners
end

-- How a hop charged `charge` (0..1) flies: distance (studs), launch speed up and along the ground
-- (studs/s), time in the air (s) under `gravity`, and the stamp it lands.
function StampGrid.Hop(charge: number, gravity: number): (number, number, number, number, number)
	local c = math.clamp(charge, 0, 1)
	local distance = StampGrid.HOP_MIN + (StampGrid.HOP_MAX - StampGrid.HOP_MIN) * c
	local up = StampGrid.HOP_UP_MIN + (StampGrid.HOP_UP_MAX - StampGrid.HOP_UP_MIN) * c
	local airtime = 2 * up / math.max(gravity, 1)
	local along = distance / airtime
	local radius = StampGrid.HOP_RADIUS_MIN + (StampGrid.HOP_RADIUS_MAX - StampGrid.HOP_RADIUS_MIN) * c
	return distance, up, along, airtime, radius
end

-- "37%" of the pad for a cell count.
function StampGrid.Percent(cells: number): number
	return math.floor(cells / (StampGrid.N * StampGrid.N) * 100 + 0.5)
end

return StampGrid

--!strict
-- The Dice Dash board and its moves, shared by the server (rules, bots' characters) and the client
-- half (smooth hops for everyone): where each tile sits on the tabletop, which tile kinds a round
-- deals, and where a racer is at any moment of a turn given the moves the server planned for it.
--
-- The board is one winding path across a giant tabletop: START (index 0) on its own pad, four
-- rows of 9 tiles that snake back and forth (a tile at each U-turn), and FINISH (index LAST) on
-- its own pad. Positions are relative to the arena origin, the tabletop's surface at y = 0.
--
-- A move is { a = start time, f = from tile, t = to tile, k = kind }:
--   "w" walk: hops tile by tile (HOP seconds each)     "l" slip: slides back along the path
--   "b" boost: a springboard arc     "c" cannon: a high arc     "x" swap: an arc to the other's tile
--   "g" gust: blown back in a low arc     "j" event jump: an arc forward     "d" trapdoor: drops
--   through the tile, then falls onto START from above
-- Moves in a turn never overlap; once the last one ends the racer rests on its tile.
-- Leaf module: no Roblox services, so the rules can be checked under Lune too.

local Board = {}

Board.COLUMNS = 9 -- tiles in a row
Board.ROWS = 4
Board.SPACING = 11 -- studs between neighbouring tile centres
Board.TILE = 9 -- a tile's width
Board.PAD = 15 -- START and FINISH pads' width
Board.TOP = 1.2 -- a tile's (and pad's) walkable top above the tabletop
Board.LAST = 1 + Board.COLUMNS * Board.ROWS + (Board.ROWS - 1) -- FINISH's index (40)

Board.HOP = 0.3 -- seconds per tile walked
Board.ROLL_WINDOW = 3 -- seconds to press ROLL before the die stops by itself
Board.SHOW = 0.45 -- seconds the rolled numbers show before everyone hops
Board.TIMES = { b = 0.85, l = 0.75, c = 1.3, x = 0.95, g = 0.9, j = 0.85, d = 1.25 }
Board.HEIGHTS = { b = 9, c = 22, x = 8, g = 5, j = 7 }

-- Tile kinds (one character each in the shared kinds string).
Board.START = "A"
Board.FINISH = "Z"
Board.PLAIN = "."
Board.BOOST = "B"
Board.SLIP = "L"
Board.CANNON = "C"
Board.SWAP = "S"
Board.EVENT = "Q"
Board.TRAP = "T"

export type Move = { a: number, f: number, t: number, k: string }

-- Where tile `index` sits: its centre (x, z) on the tabletop and which way the path runs there.
local cache: { [number]: { X: number, Z: number, Yaw: number } } = {}

local function raw(index: number): (number, number)
	local columns, spacing = Board.COLUMNS, Board.SPACING
	local half = (columns - 1) / 2 * spacing
	local rowZ = function(row: number): number
		return (1.5 - row) * 2 * spacing -- rows 22 studs apart: 33, 11, -11, -33
	end
	local wobble = function(row: number, column: number): number
		return 2.2 * math.sin(column * 1.1 + row * 2.3)
	end
	if index <= 0 then
		return -half - 15, rowZ(0) + wobble(0, 0) * 0.4
	end
	if index >= Board.LAST then
		local row = Board.ROWS - 1
		local x = if row % 2 == 0 then half + 15 else -half - 15
		return x, rowZ(row) + wobble(row, 0) * 0.4
	end
	local step = index - 1
	local row = 0
	while true do
		if step < columns then
			local column = if row % 2 == 0 then step else columns - 1 - step
			return -half + column * spacing, rowZ(row) + wobble(row, column)
		end
		step -= columns
		if step == 0 then -- the U-turn tile between this row and the next
			local x = if row % 2 == 0 then half + 4 else -half - 4
			return x, (rowZ(row) + rowZ(row + 1)) / 2
		end
		step -= 1
		row += 1
	end
end

function Board.Tile(index: number): (number, number, number)
	index = math.clamp(index, 0, Board.LAST)
	local entry = cache[index]
	if not entry then
		local x, z = raw(index)
		local ax, az = raw(math.max(index - 1, 0))
		local bx, bz = raw(math.min(index + 1, Board.LAST))
		if index == 0 then
			ax, az = x, z
		elseif index == Board.LAST then
			bx, bz = x, z
		end
		local dx, dz = bx - ax, bz - az
		entry = { X = x, Z = z, Yaw = math.atan2(-dx, -dz) } -- (yaw so the tile's -Z points forward)
		cache[index] = entry
	end
	return entry.X, entry.Z, entry.Yaw
end

-- The walkable top's centre of a tile, relative to the arena origin (a Vector3 is fine in Lune too).
function Board.Spot(index: number): Vector3
	local x, z = Board.Tile(index)
	return Vector3.new(x, Board.TOP, z)
end

-- Where racer `slot` of `count` sharing a tile stands, off its centre (so nobody hides anyone).
function Board.Ring(slot: number, count: number, wide: boolean?): Vector3
	if count <= 1 then
		return Vector3.zero
	end
	local radius = math.min(if wide then 5.2 else 3.3, 0.9 + 0.3 * count)
	local angle = (slot - 1) / count * math.pi * 2 + 0.4
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

function Board.Duration(move: Move): number
	if move.k == "w" then
		return math.abs(move.t - move.f) * Board.HOP
	end
	return Board.TIMES[move.k] or 0.8
end

local function smooth(u: number): number
	return u * u * (3 - 2 * u)
end

-- A point along the path at fractional tile `d` (between tile centres in straight lines).
local function along(d: number): Vector3
	local i = math.floor(d)
	local frac = d - i
	local a = Board.Spot(i)
	if frac <= 0 then
		return a
	end
	return a:Lerp(Board.Spot(i + 1), frac)
end

export type Sample = {
	Position: Vector3, -- relative to the arena origin, at the feet (ring offset not added)
	Yaw: number, -- which way the racer faces
	Air: number, -- 0..1, how high in a hop/arc (for the pose)
	Rest: number?, -- the tile the racer rests on (nil while moving)
	Kind: string?, -- the move in progress
	Progress: number, -- 0..1 through the move in progress
	Hidden: boolean?, -- under the board (a trapdoor drop)
}

-- Where a racer is at `now`: the first unfinished move decides; past all of them it rests on `final`.
function Board.Sample(moves: { Move }?, final: number, now: number): Sample
	if moves then
		for _, move in moves do
			local duration = Board.Duration(move)
			if now >= move.a + duration then
				continue
			end
			if now < move.a then
				local _, _, yaw = Board.Tile(move.f)
				return { Position = Board.Spot(move.f), Yaw = yaw, Air = 0, Rest = move.f, Progress = 0 }
			end
			local u = math.clamp((now - move.a) / math.max(duration, 1e-3), 0, 1)
			local from, to = Board.Spot(move.f), Board.Spot(move.t)
			local kind = move.k
			if kind == "w" then
				local steps = (now - move.a) / Board.HOP
				local i = math.floor(steps)
				local frac = steps - i
				local dir = if move.t >= move.f then 1 else -1
				local a, b = Board.Spot(move.f + i * dir), Board.Spot(move.f + (i + 1) * dir)
				local flat = a:Lerp(b, smooth(frac))
				local hop = math.sin(math.pi * frac)
				local delta = (b - a) * dir
				return {
					Position = flat + Vector3.new(0, 2.4 * hop, 0),
					Yaw = math.atan2(-delta.X, -delta.Z),
					Air = hop,
					Kind = kind,
					Progress = u,
				}
			elseif kind == "l" then
				local d = move.f + (move.t - move.f) * (1 - (1 - u) * (1 - u))
				local _, _, yaw = Board.Tile(move.f)
				return {
					Position = along(d),
					Yaw = yaw + u * math.pi * 4,
					Air = 0,
					Kind = kind,
					Progress = u,
				}
			elseif kind == "d" then
				local _, _, yaw = Board.Tile(move.t)
				if u < 0.4 then
					local s = u / 0.4
					return {
						Position = from - Vector3.new(0, 7 * s * s, 0),
						Yaw = yaw,
						Air = 1,
						Kind = kind,
						Progress = u,
						Hidden = s > 0.7,
					}
				end
				local s = (u - 0.4) / 0.6
				return {
					Position = to + Vector3.new(0, 16 * (1 - s * s), 0),
					Yaw = yaw,
					Air = 1 - s,
					Kind = kind,
					Progress = u,
				}
			end
			local height = Board.HEIGHTS[kind] or 6
			local arc = 4 * u * (1 - u)
			local delta = to - from
			local yaw = if kind == "g"
				then math.atan2(delta.X, delta.Z) -- (blown back facing forward)
				else math.atan2(-delta.X, -delta.Z)
			if delta.Magnitude < 0.1 then
				local _, _, tileYaw = Board.Tile(move.t)
				yaw = tileYaw
			end
			return {
				Position = from:Lerp(to, smooth(u)) + Vector3.new(0, height * arc, 0),
				Yaw = yaw,
				Air = math.min(1, arc * 1.5),
				Kind = kind,
				Progress = u,
			}
		end
	end
	local _, _, yaw = Board.Tile(final)
	return { Position = Board.Spot(final), Yaw = yaw, Air = 0, Rest = final, Progress = 1 }
end

-- When the last of a racer's moves ends (or `fallback` if it has none).
function Board.MovesEnd(moves: { Move }?, fallback: number): number
	local last = fallback
	if moves then
		for _, move in moves do
			last = math.max(last, move.a + Board.Duration(move))
		end
	end
	return last
end

-- Deals a round's tiles (a string, one character per index). `random(lo, hi)` is an integer RNG.
-- Trapdoors stay out of the first five tiles and the last quarter; the last cannon fires at the
-- FINISH cannon; no two special tiles of the same kind sit side by side.
function Board.Deal(random: (number, number) -> number): string
	local last = Board.LAST
	local kinds = table.create(last + 1, Board.PLAIN)
	kinds[1] = Board.START
	kinds[last + 1] = Board.FINISH
	local function free(index: number, kind: string): boolean
		if index < 1 or index > last - 1 or kinds[index + 1] ~= Board.PLAIN then
			return false
		end
		return kinds[index] ~= kind and kinds[index + 2] ~= kind
	end
	local function put(kind: string, lo: number, hi: number, count: number)
		for _ = 1, count do
			local options = {}
			for index = lo, hi do
				if free(index, kind) then
					table.insert(options, index)
				end
			end
			if #options == 0 then
				return
			end
			kinds[options[random(1, #options)] + 1] = kind
		end
	end
	local quarter = math.floor(last / 4)
	put(Board.CANNON, 5, 9, 1)
	put(Board.CANNON, 13, 17, 1)
	put(Board.CANNON, 22, 26, 1)
	put(Board.CANNON, last - 8, last - 5, 1)
	put(Board.TRAP, 6, 2 * quarter - 1, 1)
	put(Board.TRAP, 2 * quarter, 3 * quarter - 1, 1)
	put(Board.SWAP, 10, last - 8, 1)
	put(Board.BOOST, 2, last - 3, 5)
	put(Board.SLIP, 4, last - 2, 4)
	put(Board.EVENT, 3, last - 2, 4)
	return table.concat(kinds)
end

-- The next cannon ahead of `index` (or FINISH: the last cannon fires at the big one under the arch).
function Board.NextCannon(kinds: string, index: number): number
	for other = index + 1, Board.LAST - 1 do
		if string.sub(kinds, other + 1, other + 1) == Board.CANNON then
			return other
		end
	end
	return Board.LAST
end

function Board.KindAt(kinds: string, index: number): string
	return string.sub(kinds, index + 1, index + 1)
end

-- The minimum seconds between turns for a race of `racers` (bigger races give a little longer,
-- since more racers mean more effects to watch and a faster first finisher: tuned so the first
-- one home usually arrives about 45-55 s in).
function Board.TurnTime(racers: number): number
	return math.min(7.6, 4.6 + 0.4 * (math.max(racers, 1) - 1))
end

function Board.Ordinal(n: number): string
	local suffix = "th"
	if n % 100 < 11 or n % 100 > 13 then
		local last = n % 10
		suffix = if last == 1 then "st" elseif last == 2 then "nd" elseif last == 3 then "rd" else "th"
	end
	return `{n}{suffix}`
end

return Board

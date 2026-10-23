--!strict
-- Obby Odyssey's course (owner: "Can you make an Oby obstacle course similar to this photo? I want it to be
-- a mini game for the game." with a photo of a bright blocky obby: colourful blocks over a pool, red balls
-- swinging from a pink gantry, a blue tower with yellow steps, red pipes over lava, and a gold crown on a
-- stepped pyramid between checkered flags; then "Also think of a cool name for the oby mini game. you can
-- make it a bit longer then the average mini game too."). Its layout, its moving hazards and its rules as
-- plain numbers, shared by the server (which builds it, judges hits and checkpoints), the client (which
-- animates the hazards from the same schedule), the bots and the tests (which check every jump against
-- the jump arc, and that nothing can be skipped). Leaf module: no requires, no Roblox APIs.
--
-- Six sections, one after the other, all over one long pool (water at the front, lava further on):
--   1 SPLASH HOPS   rows of colourful blocks over the water, a flat jump apart
--   2 BALL BRIDGE   a long bridge under a pink gantry; red balls swing across it
--   3 TOWER CLIMB   yellow steps zig-zag up the front of a blue tower, each a jump higher
--   4 SPIN CYCLE    over the lava: round platforms with a red bar spinning at shin height (jump it),
--                   joined by red pipes
--   5 BLINK BLOCKS  rows of blocks that flash and vanish in turn; one block in three is gone at a time
--   6 CROWN PEAK    a stepped pyramid, a jump up per tier, to the crown on the summit: the finish
-- Every rise is a jump (3.7 studs, more than any avatar steps up) and every flat gap is too wide to walk
-- across. A checkpoint pad starts sections 2 to 5; a fall puts you back on the last one you reached.
--
-- Course space (studs): +Z runs from the start to the crown, +X is to the right as you run, and heights
-- are above the pool's surface (0). The server places it at the arena's origin, unturned.
--
-- Times are seconds since the round's GO (the schedule's epoch, shared with clients), so the balls, bars and
-- blinking blocks are in the same place on every screen and on the server.

local ObbyOdyssey = {}

-- Character movement (default.project.json) and the margins the layout keeps (as the lobby obby's).
ObbyOdyssey.WalkSpeed = 16
ObbyOdyssey.JumpHeight = 7.2
ObbyOdyssey.Gravity = 196.2
ObbyOdyssey.StepUp = 3.2 -- a rise under this can be walked up (tall avatars step up about 3)
ObbyOdyssey.WalkGap = 4 -- a flat gap under this can be walked over without jumping
ObbyOdyssey.Slack = 1 -- a jump's take-off before the edge plus its landing past the edge
ObbyOdyssey.MinMargin = 2.5 -- every jump keeps this much reach to spare (phones)
ObbyOdyssey.Body = 1 -- half a character's width: hazards hit within this of the body's middle
ObbyOdyssey.Height = 5.2 -- a character from its feet to the top of its head

ObbyOdyssey.LavaFrom = 160 -- z where the water turns to lava

local RISE = 3.7 -- the climb's and the pyramid's step up
local LOW = 4 -- the water sections' tops above the water
local HIGH = 33.6 -- the tower top and everything after it, until the pyramid

ObbyOdyssey.Sections = {
	{ Name = "SPLASH HOPS", Icon = "💦", Color = { 64, 196, 255 } },
	{ Name = "BALL BRIDGE", Icon = "🔴", Color = { 255, 84, 150 } },
	{ Name = "TOWER CLIMB", Icon = "🗼", Color = { 255, 204, 64 } },
	{ Name = "SPIN CYCLE", Icon = "🌀", Color = { 255, 120, 60 } },
	{ Name = "BLINK BLOCKS", Icon = "✨", Color = { 156, 108, 255 } },
	{ Name = "CROWN PEAK", Icon = "👑", Color = { 255, 214, 70 } },
}

export type Piece = {
	Id: string,
	Kind: string, -- "Box" | "Disc" | "Pipe" (a pipe lies along Z; its crest is its Top)
	Row: number, -- the route: from a piece in row k you jump (or walk) onto one in row k + 1
	Section: number,
	Stage: number, -- the checkpoint a runner has while on it
	Checkpoint: number?, -- 0 for the start, 1-4 for the pads
	Finish: boolean?, -- the summit
	Walk: boolean?, -- joined to the row before it: walked onto, not jumped
	OnTop: boolean?, -- sits on the piece before it (the pyramid's tiers)
	X: number,
	Z: number,
	Top: number,
	W: number, -- across (x): a box's width, a disc's or a pipe's diameter
	D: number, -- along (z): a box's depth, a disc's diameter, a pipe's length
	Color: string, -- a name from the server's palette
	Blink: number?, -- a blinking block's group (0-2): which third of the cycle it's gone in
	Spinner: number?, -- a spinner's disc: its index in ObbyOdyssey.Spinners
}

export type Ball = {
	Id: string,
	X: number, -- the pivot, on the gantry over the bridge's middle
	Z: number,
	PivotY: number,
	Length: number, -- from the pivot to the ball's middle
	Radius: number,
	Swing: number, -- radians either side of hanging straight down
	Period: number, -- seconds for a full swing there and back
	Phase: number, -- 0..1 of a period
}

export type Spinner = {
	Id: string,
	X: number,
	Z: number,
	Top: number, -- the disc's top
	Arm: number, -- from the middle to the bar's tip (the disc's radius)
	Hub: number, -- the hub's radius in the middle (solid; the bar starts from it)
	HubTop: number, -- the hub's top above the disc
	BarY: number, -- the bar's middle above the disc
	BarRadius: number,
	Period: number, -- seconds per turn; negative turns the other way
	Phase: number, -- 0..1 of a turn
}

local pieces: { Piece } = {}
local rows: { { Piece } } = {}

local function add(row: number, piece: { [string]: any }): Piece
	piece.Row = row
	piece.Kind = piece.Kind or "Box"
	local list = rows[row]
	if not list then
		list = {}
		rows[row] = list
	end
	table.insert(list, piece :: Piece)
	table.insert(pieces, piece :: Piece)
	return piece :: Piece
end

local BLOCK_COLORS = { "Red", "Yellow", "Green", "Blue", "Orange", "Purple" }

-- 1 SPLASH HOPS: the start pad, then five rows of blocks, 7 square and 4.5 apart, three and four to a
-- row in turn (every block reaches two in the next row).
add(1, {
	Id = "Start",
	Section = 1,
	Stage = 0,
	Checkpoint = 0,
	X = 0,
	Z = -8,
	W = 40,
	D = 16,
	Top = LOW,
	Color = "White",
})
for index = 1, 5 do
	local z = 8 + (index - 1) * 11.5
	local xs: { number } = if index % 2 == 1 then { -12, 0, 12 } else { -18, -6, 6, 18 }
	for column, x in ipairs(xs) do
		add(1 + index, {
			Id = `Hop{index}_{column}`,
			Section = 1,
			Stage = 0,
			X = x,
			Z = z,
			W = 7,
			D = 7,
			Top = LOW,
			Color = BLOCK_COLORS[(index + column) % #BLOCK_COLORS + 1],
		})
	end
end

-- 2 BALL BRIDGE: a pad, the bridge (walked onto), a hop to the next pad.
add(7, {
	Id = "Checkpoint1",
	Section = 2,
	Stage = 1,
	Checkpoint = 1,
	X = 0,
	Z = 67,
	W = 36,
	D = 10,
	Top = LOW,
	Color = "Pad",
})
add(
	8,
	{ Id = "Bridge", Section = 2, Stage = 1, Walk = true, X = 0, Z = 100, W = 10, D = 56, Top = LOW, Color = "Bridge" }
)
add(9, {
	Id = "Checkpoint2",
	Section = 3,
	Stage = 2,
	Checkpoint = 2,
	X = 0,
	Z = 137.5,
	W = 28,
	D = 10,
	Top = LOW,
	Color = "Pad",
})

-- 3 TOWER CLIMB: seven steps, 6 square, 2.5 apart and RISE higher each: three to the right, then four
-- back to the left in front of the tower, then up onto the tower's top.
local steps = { { 0, 148 }, { 8.5, 148 }, { 17, 148 }, { 17, 156.5 }, { 8.5, 156.5 }, { 0, 156.5 }, { -8.5, 156.5 } }
for index, step in steps do
	add(9 + index, {
		Id = `Step{index}`,
		Section = 3,
		Stage = 2,
		X = step[1],
		Z = step[2],
		W = 6,
		D = 6,
		Top = LOW + RISE * index,
		Color = "Step",
	})
end
add(17, {
	Id = "Checkpoint3",
	Section = 4,
	Stage = 3,
	Checkpoint = 3,
	X = 0,
	Z = 172,
	W = 32,
	D = 20,
	Top = HIGH,
	Color = "Tower",
})

-- 4 SPIN CYCLE: three spinning-bar discs joined by pipes, a hop off the tower and one onto the pad.
local SPINNERS: { { any } } = { -- disc radius, middle z, seconds per turn
	{ 9, 195.5, 3.6 },
	{ 10, 228.5, -3.1 },
	{ 9, 261.5, 2.7 },
}
ObbyOdyssey.Spinners = {} :: { Spinner }
for index, spec in SPINNERS do
	local radius, z = spec[1], spec[2]
	add(16 + index * 2, {
		Id = `Spinner{index}`,
		Kind = "Disc",
		Section = 4,
		Stage = 3,
		Walk = index > 1,
		X = 0,
		Z = z,
		W = radius * 2,
		D = radius * 2,
		Top = HIGH,
		Color = "Disc",
		Spinner = index,
	})
	table.insert(ObbyOdyssey.Spinners, {
		Id = `Spinner{index}`,
		X = 0,
		Z = z,
		Top = HIGH,
		Arm = radius,
		Hub = 1.8,
		HubTop = 2.6,
		BarY = 1.4,
		BarRadius = 0.65,
		Period = spec[3],
		Phase = (index - 1) * 0.37,
	})
	if index < #SPINNERS then
		local from = z + radius
		local to = SPINNERS[index + 1][2] - SPINNERS[index + 1][1]
		add(17 + index * 2, {
			Id = `Pipe{index}`,
			Kind = "Pipe",
			Section = 4,
			Stage = 3,
			Walk = true,
			X = 0,
			Z = (from + to) / 2,
			W = 4,
			D = to - from,
			Top = HIGH,
			Color = "Pipe",
		})
	end
end
add(23, {
	Id = "Checkpoint4",
	Section = 5,
	Stage = 4,
	Checkpoint = 4,
	X = 0,
	Z = 280,
	W = 24,
	D = 10,
	Top = HIGH,
	Color = "Pad",
})

-- 5 BLINK BLOCKS: five rows of three, 7 square and 4.5 apart. In each row one block is gone at a time,
-- and the gone one moves along the row (and from row to row), so there's always a way on.
for index = 1, 5 do
	for column, x in { -10, 0, 10 } do
		add(23 + index, {
			Id = `Blink{index}_{column}`,
			Section = 5,
			Stage = 4,
			X = x,
			Z = 293 + (index - 1) * 11.5,
			W = 7,
			D = 7,
			Top = HIGH,
			Color = "Blink",
			Blink = (index + column) % 3,
		})
	end
end

-- 6 CROWN PEAK: the pyramid's four tiers (each sits on the one below and is 5 in from its edge), the
-- summit on top.
for tier = 1, 4 do
	local half = 22 - (tier - 1) * 5
	add(28 + tier, {
		Id = if tier == 4 then "Summit" else `Tier{tier}`,
		Section = 6,
		Stage = 4,
		OnTop = tier > 1,
		Finish = tier == 4,
		X = 0,
		Z = 367,
		W = half * 2,
		D = half * 2,
		Top = HIGH + RISE * tier,
		Color = if tier == 4 then "Summit" else "Tier",
	})
end

ObbyOdyssey.Pieces = pieces
ObbyOdyssey.Rows = rows
ObbyOdyssey.Start = rows[1][1]
ObbyOdyssey.Summit = rows[#rows][1]
ObbyOdyssey.Checkpoints = {} :: { Piece } -- the pads, 1-4
for _, piece in pieces do
	if piece.Checkpoint and piece.Checkpoint > 0 then
		ObbyOdyssey.Checkpoints[piece.Checkpoint] = piece
	end
end
ObbyOdyssey.Bridge = rows[8][1]

-- The swinging balls over the bridge: five of them, 10 apart, out of step with each other, the last well
-- before the bridge's end (the jump to the next pad is taken clear of it).
ObbyOdyssey.Balls = {} :: { Ball }
for index, phase in { 0, 0.3, 0.62, 0.12, 0.45 } do
	table.insert(ObbyOdyssey.Balls, {
		Id = `Ball{index}`,
		X = 0,
		Z = 78.5 + (index - 1) * 10,
		PivotY = LOW + 19,
		Length = 14,
		Radius = 3,
		Swing = math.rad(66),
		Period = 3.4 - (index - 1) * 0.12,
		Phase = phase,
	})
end

-- Blinking blocks: each cycle a block is solid, flashes for Warn seconds, then is gone for Gone seconds.
ObbyOdyssey.BlinkPeriod = 4.2
ObbyOdyssey.BlinkGone = 1.4 -- a third of the period: the three groups take turns being gone
ObbyOdyssey.BlinkWarn = 0.8

-- Geometry -------------------------------------------------------------------------------------------

-- How far a jump carries a character's middle (studs, flat) before it comes back down to `rise` above
-- where it took off; 0 when the jump can't get that high.
function ObbyOdyssey.Reach(rise: number): number
	local v0 = math.sqrt(2 * ObbyOdyssey.Gravity * ObbyOdyssey.JumpHeight)
	local inside = v0 * v0 - 2 * ObbyOdyssey.Gravity * rise
	if inside < 0 then
		return 0
	end
	return ObbyOdyssey.WalkSpeed * (v0 + math.sqrt(inside)) / ObbyOdyssey.Gravity
end

-- How far a point is from a piece's footprint, flat (0 on or over it).
function ObbyOdyssey.DistanceTo(piece: Piece, x: number, z: number): number
	if piece.Kind == "Disc" then
		return math.max(0, math.sqrt((x - piece.X) ^ 2 + (z - piece.Z) ^ 2) - piece.W / 2)
	end
	local dx = math.max(0, math.abs(x - piece.X) - piece.W / 2)
	local dz = math.max(0, math.abs(z - piece.Z) - piece.D / 2)
	return math.sqrt(dx * dx + dz * dz)
end

-- The flat gap between two pieces' footprints, edge to edge (0 if they touch or overlap).
function ObbyOdyssey.Gap(a: Piece, b: Piece): number
	if a.Kind == "Disc" and b.Kind == "Disc" then
		local d = math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
		return math.max(0, d - a.W / 2 - b.W / 2)
	elseif a.Kind == "Disc" or b.Kind == "Disc" then
		local disc, box = if a.Kind == "Disc" then a else b, if a.Kind == "Disc" then b else a
		return math.max(0, ObbyOdyssey.DistanceTo(box, disc.X, disc.Z) - disc.W / 2)
	end
	local dx = math.max(0, math.abs(a.X - b.X) - (a.W + b.W) / 2)
	local dz = math.max(0, math.abs(a.Z - b.Z) - (a.D + b.D) / 2)
	return math.sqrt(dx * dx + dz * dz)
end

-- The top of a piece under a point that's over it: a pipe's top curves down from its crest.
function ObbyOdyssey.SurfaceAt(piece: Piece, x: number): number
	if piece.Kind == "Pipe" then
		local r = piece.W / 2
		local off = math.min(math.abs(x - piece.X), r)
		return piece.Top - (r - math.sqrt(r * r - off * off))
	end
	return piece.Top
end

-- Blinking -------------------------------------------------------------------------------------------

-- A blinking block at time `t`: solid or not, flashing (about to go), and seconds until it changes.
-- Anything else is always solid.
function ObbyOdyssey.BlinkState(piece: Piece, t: number): (boolean, boolean, number)
	local group = piece.Blink
	if group == nil then
		return true, false, math.huge
	end
	local period, gone = ObbyOdyssey.BlinkPeriod, ObbyOdyssey.BlinkGone
	local c = (t - group * gone) % period
	if c >= period - gone then
		return false, false, period - c
	end
	return true, c >= period - gone - ObbyOdyssey.BlinkWarn, period - gone - c
end

function ObbyOdyssey.Solid(piece: Piece, t: number): boolean
	return (ObbyOdyssey.BlinkState(piece, t))
end

-- Where everyone stands --------------------------------------------------------------------------------

-- The piece whose top a character's feet (course space) are on at time `t`, if any. A blinking block
-- that's gone holds nobody.
function ObbyOdyssey.PieceAt(x: number, z: number, feet: number, t: number?): Piece?
	local best: Piece? = nil
	for _, piece in pieces do
		if ObbyOdyssey.DistanceTo(piece, x, z) > 0.6 then
			continue
		end
		if math.abs(feet - ObbyOdyssey.SurfaceAt(piece, x)) > 1.2 then
			continue
		end
		if t and not ObbyOdyssey.Solid(piece, t) then
			continue
		end
		if not best or piece.Top > best.Top then
			best = piece -- (a tier's edge is also over the tier below it)
		end
	end
	return best
end

-- One look at a runner: their feet are at (x, feet, z) and they have checkpoint `stage` and last stood on
-- `row`. Returns their checkpoint now, their row, and the piece they're on (nil in the air). A piece
-- further on than their checkpoint counts it as reached: only a knock could carry anyone that far, and
-- never past a whole section (the tests check nothing can be skipped).
function ObbyOdyssey.Step(
	stage: number,
	row: number,
	x: number,
	z: number,
	feet: number,
	t: number?
): (number, number, Piece?)
	local piece = ObbyOdyssey.PieceAt(x, z, feet, t)
	if not piece then
		return stage, row, nil
	end
	return math.max(stage, piece.Stage), piece.Row, piece
end

-- Where a runner on checkpoint `stage` is put back: a spot on the pad (`slot` spreads people out, 1-12),
-- and the way to face.
function ObbyOdyssey.Respawn(stage: number, slot: number?): (number, number, number)
	local pad = if stage <= 0 then ObbyOdyssey.Start else ObbyOdyssey.Checkpoints[stage]
	local index = ((slot or 1) - 1) % 12
	local across = (index % 6 - 2.5) / 5 * math.max(0, pad.W - 6)
	local along = if index < 6 then 0.2 else -0.2
	if stage <= 0 then
		along = if index < 6 then 0.25 else -0.15 -- the start pad is deep: two rows
	end
	return pad.X + across, pad.Top, pad.Z + along * pad.D
end

-- The route's middle line, for progress: one point per row (the middle of its pieces), with the distance
-- along the route to each.
local path: { { number } } = {}
local arc: { number } = {}
for index, list in rows do
	local x, z = 0, 0
	for _, piece in list do
		x += piece.X
		z += piece.Z
	end
	path[index] = { x / #list, list[1].Top, z / #list }
	if index == 1 then
		arc[index] = 0
	else
		local a, b = path[index - 1], path[index]
		arc[index] = arc[index - 1] + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
	end
end
ObbyOdyssey.Length = arc[#arc]

-- How far along the route (studs) a runner at (x, y, z) is, having last stood on `row`: on the way from
-- the row before's middle to this row's, or on from this row's middle toward the next's (a long piece,
-- like the bridge, counts the whole way along it).
local function along(from: { number }, to: { number }, x: number, y: number, z: number): (number, number)
	local sx, sy, sz = to[1] - from[1], to[2] - from[2], to[3] - from[3]
	local length2 = sx * sx + sy * sy + sz * sz
	return ((x - from[1]) * sx + (y - from[2]) * sy + (z - from[3]) * sz) / length2, math.sqrt(length2)
end

function ObbyOdyssey.Progress(row: number, x: number, y: number, z: number): number
	local index = math.clamp(row, 1, #path)
	local a = path[index]
	local b = path[index + 1]
	if not b then
		return arc[index]
	end
	local share, length = along(a, b, x, y, z)
	local before = path[index - 1]
	if share >= 0 or not before then
		return arc[index] + math.clamp(share, 0, 0.98) * length
	end
	local back, backLength = along(before, a, x, y, z)
	return arc[index - 1] + math.clamp(back, 0.02, 1) * backLength
end

-- The middle of a row (course space), for bots and the HUD.
function ObbyOdyssey.RowMiddle(row: number): (number, number, number)
	local p = path[math.clamp(row, 1, #path)]
	return p[1], p[2], p[3]
end

-- Swinging balls -------------------------------------------------------------------------------------

function ObbyOdyssey.BallAngle(ball: Ball, t: number): number
	return ball.Swing * math.sin(2 * math.pi * (t / ball.Period + ball.Phase))
end

-- The ball's middle at time `t` (course space).
function ObbyOdyssey.BallAt(ball: Ball, t: number): (number, number, number)
	local angle = ObbyOdyssey.BallAngle(ball, t)
	return ball.X + ball.Length * math.sin(angle), ball.PivotY - ball.Length * math.cos(angle), ball.Z
end

-- Which way (+1 or -1 in x) the ball is swinging at time `t`.
function ObbyOdyssey.BallHeading(ball: Ball, t: number): number
	return if math.cos(2 * math.pi * (t / ball.Period + ball.Phase)) >= 0 then 1 else -1
end

-- Whether the ball, at time `t`, overlaps a character standing at (x, z) with its feet at `feet`: the
-- body is a column Body wide from the feet to the top of the head, rounded at both ends.
function ObbyOdyssey.BallHits(ball: Ball, t: number, x: number, feet: number, z: number): boolean
	local bx, by, bz = ObbyOdyssey.BallAt(ball, t)
	local body = ObbyOdyssey.Body
	local low, high = feet + body, feet + ObbyOdyssey.Height - body
	local cy = math.clamp(by, low, high)
	local d2 = (bx - x) ^ 2 + (by - cy) ^ 2 + (bz - z) ^ 2
	return d2 < (ball.Radius + body) ^ 2
end

-- Spinning bars ----------------------------------------------------------------------------------------

-- The bar's angle (radians, measured from +X toward +Z) at time `t`. The bar runs right through the
-- middle, so it lies along this angle and the opposite one.
function ObbyOdyssey.SpinnerAngle(spinner: Spinner, t: number): number
	return 2 * math.pi * (t / spinner.Period + spinner.Phase)
end

-- Whether the bar swept through a character at (x, z) with its feet at `feet` between times `t0` and
-- `t1` (they stood there meanwhile). On a hit, also the way the bar pushes them (x, z; flat, unit).
function ObbyOdyssey.SpinnerHits(
	spinner: Spinner,
	t0: number,
	t1: number,
	x: number,
	feet: number,
	z: number
): (boolean, number, number)
	local dx, dz = x - spinner.X, z - spinner.Z
	local r = math.sqrt(dx * dx + dz * dz)
	local body = ObbyOdyssey.Body
	if r > spinner.Arm + body or r < 0.01 then
		return false, 0, 0
	end
	-- Feet over the bar (a jump), or a head under it (never, on the disc): no hit.
	if feet > spinner.Top + spinner.BarY + spinner.BarRadius then
		return false, 0, 0
	end
	if feet + ObbyOdyssey.Height < spinner.Top + spinner.BarY - spinner.BarRadius then
		return false, 0, 0
	end
	local alpha = math.atan2(dz, dx)
	local width = math.atan2(spinner.BarRadius + body, r)
	local a0 = ObbyOdyssey.SpinnerAngle(spinner, t0) - alpha
	local a1 = ObbyOdyssey.SpinnerAngle(spinner, t1) - alpha
	local low, high = math.min(a0, a1) - width, math.max(a0, a1) + width
	if math.ceil(low / math.pi) > math.floor(high / math.pi) then
		return false, 0, 0
	end
	local turn = if spinner.Period > 0 then 1 else -1
	return true, -math.sin(alpha) * turn, math.cos(alpha) * turn
end

-- Seconds until the bar next passes a point at (x, z), from time `t` (math.huge off the disc).
function ObbyOdyssey.SpinnerNext(spinner: Spinner, t: number, x: number, z: number): number
	local dx, dz = x - spinner.X, z - spinner.Z
	if dx * dx + dz * dz > (spinner.Arm + ObbyOdyssey.Body) ^ 2 then
		return math.huge
	end
	local alpha = math.atan2(dz, dx)
	local angle = ObbyOdyssey.SpinnerAngle(spinner, t)
	local omega = 2 * math.pi / spinner.Period
	-- The bar lies along `angle` and `angle + pi`: the next time either reaches alpha.
	local ahead = if omega > 0 then (alpha - angle) % math.pi else (angle - alpha) % math.pi
	return ahead / math.abs(omega)
end

-- "1st", "2nd", "3rd", "4th"...
function ObbyOdyssey.Ordinal(place: number): string
	local suffix = "th"
	local tens = place % 100
	if tens < 11 or tens > 13 then
		local ones = place % 10
		suffix = if ones == 1 then "st" elseif ones == 2 then "nd" elseif ones == 3 then "rd" else "th"
	end
	return `{place}{suffix}`
end

-- Jumps (for the tests and the jump table) -------------------------------------------------------------

export type Jump = {
	From: Piece,
	To: Piece,
	Gap: number,
	Rise: number,
	Need: number, -- flat distance the middle has to carry: the gap plus Slack
	Reach: number,
	Margin: number,
	Walk: boolean,
}

-- Every way on from a piece: the pieces in the next row it can get onto (a walk, or a jump with reach to
-- spare), with what each needs.
function ObbyOdyssey.WaysOn(from: Piece): { Jump }
	local list = {}
	local next: { Piece } = rows[from.Row + 1] or {}
	for _, to in next do
		local gap = ObbyOdyssey.Gap(from, to)
		local rise = to.Top - from.Top
		local reach = ObbyOdyssey.Reach(rise)
		local need = gap + ObbyOdyssey.Slack
		local jump = {
			From = from,
			To = to,
			Gap = gap,
			Rise = rise,
			Need = need,
			Reach = reach,
			Margin = reach - need,
			Walk = to.Walk == true or (from.Walk == true and gap < 0.15 and math.abs(rise) < 0.15),
		}
		if jump.Walk or jump.Margin >= ObbyOdyssey.MinMargin then
			table.insert(list, jump)
		end
	end
	return list
end

return ObbyOdyssey

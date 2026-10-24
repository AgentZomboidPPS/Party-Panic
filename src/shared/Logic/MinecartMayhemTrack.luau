--!strict
-- Minecart Mayhem's course and riding rules, shared by the server (which rides every cart), the
-- clients (which draw the same rails and carts, and predict their own cart) and the props (whose
-- rail meshes are swept along the very same shapes by tools/meshgen/props/MinecartMayhem.py).
--
-- The course is a string of tiles, always facing down the mine (-Z), each the same mesh every round:
--   Start     the station deck: twelve stub tracks, the carts glide onto the main line as they roll
--   Bend      an S-bend that swings the line BEND_WIDE studs sideways (D = 1 to the right first)
--   Junction  a switch at SPLIT: the LONG way bows out to side L (and over a hump), the other way
--             (side -L) runs nearly straight and dips. The other way is a SHORTcut, a DEAD end (a
--             buffer stop, the cart rolls back to the switch and takes the long way) or a TNT track
--             (the crates blow the cart off: a comeback at the switch). Both rejoin at MERGE.
--   Gap       a broken bridge: the rails stop from GAP_FROM to GAP_TO, JUMP over it or fall
--   Hill      a steep dive and a short climb
--   Finish    the way out into daylight, the finish line at FINISH_AT
-- The server picks the order, the junctions' sides and what their other way is, every round.
--
-- Every path is sampled once per forward stud: course-local positions (the start at 0, 0, 0) and
-- the distance S along the rails. A cart is where it is on a path: its tile, its branch B (1: the
-- main or long way, 2: the other way) and S. Carts roll by themselves, faster downhill and slower
-- uphill. On a bend, leaning into it (LEFT on a left-hand curve) pushes the cart faster, leaning the
-- wrong way wobbles and slows it. A glowing crystal on the rails gives a DASH unless the cart is in
-- the air over it.
--
-- Fair jumps: a gap is judged over the whole cart, wheel to wheel. The front wheels reach the gap at
-- `at`; the back wheels leave it (GAP + WHEELBASE) / v later (a cart in the air keeps its speed, so
-- that's exact). The cart clears it only if its wheels are at least MIN_CLEAR up at both moments (a
-- jump is one hump, so it is up all the time between). The server judges a player's JUMP by when it
-- was pressed on their screen, and the client lights JUMP by the same rule.
--
-- Held jumps (owner: "Minecart mayham is still terrible. Iam not sure how we can fix it. I cant see
-- when to jump."): a press that clears the gap had to come in a window about a third of a second
-- long at cruising speed (less when slow), ending as the front wheels reach the gap, so a cue had to
-- be guessed, not followed. Now a JUMP pressed early, up to HOLD seconds before the best moment, is
-- held and the cart takes off at the best moment (TakeOff): from the JUMP! cue to the gap, any press
-- clears it. A press earlier than that jumps at once (and lands before the gap), as before.
--
-- Fair switches: the way a cart takes is the side of the latest LEFT or RIGHT tapped after the cart
-- came within CHOOSE studs of the switch (or pressed earlier and still held there), up to GRACE
-- seconds after its middle reached the switch on the player's screen (Choose). No press: the long,
-- safe way.
--
-- Leaf module: no Roblox services, so Lune tests and the offline sim can load it.

local Track = {}

Track.LEN = { Start = 64, Bend = 110, Junction = 150, Gap = 72, Hill = 90, Finish = 90 }
Track.SPLIT = 16 -- a junction's switch (forward studs into the tile)
Track.MERGE = 134 -- where its two ways meet again
Track.LONG_WIDE = 40 -- how far the long way bows out
Track.LONG_RISE = 6 -- and how high its hump climbs
Track.SHORT_WIDE = 9 -- the other way's gentle swing
Track.SHORT_DIP = 3
Track.BUFFER_T = 0.42 -- a dead end's buffer stop, as a share of the way from SPLIT to MERGE
Track.TNT_T = 0.34 -- a TNT track's crates
Track.SHORT_CRYSTAL_T = 0.55 -- the shortcut's crystal
Track.BEND_WIDE = 36
Track.GAP_FROM = 38
Track.GAP_TO = 46
Track.FINISH_AT = 40
Track.START_LANE = 5.5 -- the station's stub tracks, side by side
Track.START_MERGE = 28 -- the carts are on the main line by here (the station deck ends at 30)
Track.CHOOSE = 50 -- presses count from this far before a switch (its sign is 30 before it)
Track.BEND_RUN = 0.7 -- a bend swings over this share of its tile, then runs straight to the next
Track.GRACE = 0.12

-- The cart (studs). The wheels are WHEELBASE apart; S is the cart's middle.
Track.WHEELBASE = 2.8
Track.HALF_BASE = 1.4
Track.GAUGE = 3 -- rail centre to rail centre
Track.RAIL_TOP = 0.75 -- the rails' top above the path line (ties 0.25..0.45, rails 0.45..0.75)

-- Riding (studs per second).
Track.CRUISE = 24
Track.SLOPE = 45 -- extra target speed per unit of downhill grade
Track.MIN_V = 6
Track.MAX_V = 44
Track.RISE = 1.3
Track.FALL = 1.8
Track.LEAN_BOOST = 9
Track.LEAN_SLOW = 9
Track.DASH = 38
Track.DASH_TIME = 1.3
Track.BACK_SPEED = 16 -- rolling back from a buffer stop
Track.AFTER_BACK = 8 -- speed when it takes the long way after rolling back
Track.RESTART_V = 16 -- after a comeback
Track.COMEBACK = 2.5 -- seconds off the rails after a fall or a blast

-- Jumping.
Track.JUMP_TIME = 0.85
Track.JUMP_HEIGHT = 4.5
Track.JUMP_REST = 0.15
Track.MIN_CLEAR = 0.6
Track.HOLD = 1.2 -- an early JUMP up to this long before a gap's best moment waits for it (TakeOff)
-- The take-off marker (yellow chevrons on the ties): the cart's FRONT wheels over it, from
-- TAKEOFF_FAR to TAKEOFF_NEAR studs before the gap, clears at any speed from 20 to 32.
Track.TAKEOFF_NEAR = 1.2
Track.TAKEOFF_FAR = 5.2
Track.CHECKPOINT = 6 -- after a fall the cart comes back this far into the gap tile

-- Each rail tile mesh's pivot (its bounding box's bottom centre) relative to its entry, and its
-- size: printed by `PYTHONPATH=tools/meshgen python3 tools/meshgen/props/MinecartMayhem.py`.
Track.Anchor = {
	MinecartMayhemRailStart = { 0.0000, -92.0249, -28.6000, 65.5000, 93.3249, 70.8000 },
	MinecartMayhemRailBendL = { -17.9835, -92.0346, -55.0835, 54.1577, 92.7846, 110.2330 },
	MinecartMayhemRailBendR = { 17.9835, -92.0346, -55.0835, 54.1577, 92.7846, 110.2330 },
	MinecartMayhemRailJunctionL = { -15.6974, -92.0349, -75.0000, 67.5113, 98.7849, 150.0000 },
	MinecartMayhemRailJunctionR = { 15.6974, -92.0349, -75.0000, 67.5113, 98.7849, 150.0000 },
	MinecartMayhemRailGap = { 0.0000, -92.0247, -36.1000, 18.5322, 92.7747, 72.2000 },
	MinecartMayhemRailHill = { 0.0000, -92.0254, -45.0000, 18.3919, 92.7754, 90.0000 },
	MinecartMayhemRailFinish = { 0.0000, -92.0247, -45.0000, 19.0040, 96.7747, 90.0000 },
}
-- The tile each rail mesh is swept along.
Track.RailTile = {
	MinecartMayhemRailStart = { K = "Start" },
	MinecartMayhemRailBendL = { K = "Bend", D = -1 },
	MinecartMayhemRailBendR = { K = "Bend", D = 1 },
	MinecartMayhemRailJunctionL = { K = "Junction", L = -1, O = "Short" },
	MinecartMayhemRailJunctionR = { K = "Junction", L = 1, O = "Short" },
	MinecartMayhemRailGap = { K = "Gap" },
	MinecartMayhemRailHill = { K = "Hill" },
	MinecartMayhemRailFinish = { K = "Finish" },
}

export type Tile = {
	K: string,
	D: number?, -- a bend's first side
	L: number?, -- a junction's long side (-1 left, 1 right)
	O: string?, -- a junction's other way: "Short", "Dead" or "TNT"
}

export type Path = {
	X: { number },
	Y: { number },
	Z: { number },
	S: { number },
	Total: number,
}

export type Feature = { K: string, B: number, S: number, S1: number?, Dir: number? }

export type BuiltTile = Tile & {
	Index: number,
	Len: number,
	Entry: { number },
	Paths: { Path },
	Start: number, -- course progress at its entry
	Nominal: number, -- course progress across it (the main or long way's length)
	Features: { Feature },
	SplitS: number?,
}

export type Course = {
	Tiles: { BuiltTile },
	Goal: number, -- course progress at the finish line
	FinishS: number,
}

export type Pick = { Dir: number, At: number, Until: number? }

export type Rider = {
	Tile: number,
	B: number,
	S: number,
	V: number,
	Lean: number,
	JumpAt: number,
	DashUntil: number,
	DownUntil: number,
	Back: boolean,
	Finish: number?,
	ReTile: number?, -- where a comeback puts it
	ReS: number?,
}

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- A tile's shape: the sideways (x, + is right) and height (y) offset from its entry, `f` forward
-- studs in, on branch `branch`. tools/meshgen/props/MinecartMayhem.py sweeps the same shapes.
function Track.Shape(tile: Tile, branch: number, f: number): (number, number)
	local kind = tile.K
	local len = Track.LEN[kind]
	local t = math.clamp(f / len, 0, 1)
	if kind == "Start" then
		return 0, -5 * smooth((f - 40) / 24) -- (level over the station deck, then down into the mine)
	elseif kind == "Bend" then
		local u = math.min(t / Track.BEND_RUN, 1)
		return (tile.D or 1) * Track.BEND_WIDE * (1 - math.cos(math.pi * u)) / 2, -4 * smooth(t)
	elseif kind == "Junction" then
		local u = math.clamp((f - Track.SPLIT) / (Track.MERGE - Track.SPLIT), 0, 1)
		local bow = (1 - math.cos(2 * math.pi * u)) / 2
		local side = tile.L or 1
		if branch == 1 then
			return side * Track.LONG_WIDE * bow, Track.LONG_RISE * bow
		end
		return -side * Track.SHORT_WIDE * bow, -Track.SHORT_DIP * bow
	elseif kind == "Hill" then
		return 0, -10 * t - 8 * math.sin(math.pi * t)
	elseif kind == "Finish" then
		return 0, 4 * smooth(t)
	end
	return 0, 0
end

-- Samples one path of a tile, from its entry (course-local ex, ey, ez).
local function sample(tile: Tile, branch: number, ex: number, ey: number, ez: number): Path
	local len = Track.LEN[tile.K]
	local path: Path = { X = {}, Y = {}, Z = {}, S = {}, Total = 0 }
	local s = 0
	for f = 0, len do
		local x, y = Track.Shape(tile, branch, f)
		x += ex
		y += ey
		local z = ez - f
		if f > 0 then
			local i = f -- (the previous sample)
			local dx, dy = x - path.X[i], y - path.Y[i]
			s += math.sqrt(dx * dx + dy * dy + 1)
		end
		table.insert(path.X, x)
		table.insert(path.Y, y)
		table.insert(path.Z, z)
		table.insert(path.S, s)
	end
	path.Total = s
	return path
end

-- S on a path at forward stud f (whole studs).
local function sAt(path: Path, f: number): number
	return path.S[math.clamp(math.floor(f + 0.5), 0, #path.S - 1) + 1]
end

-- Builds the whole course from the server's tile list.
function Track.Build(tiles: { Tile }): Course
	local built: { BuiltTile } = {}
	local ex, ey, ez = 0, 0, 0
	local progress = 0
	local finishS = 0
	local goal = 0
	for index, source in tiles do
		local tile = table.clone(source) :: any
		tile.Index = index
		tile.Len = Track.LEN[tile.K]
		tile.Entry = { ex, ey, ez }
		tile.Paths = { sample(tile, 1, ex, ey, ez) }
		tile.Features = {}
		local main = tile.Paths[1]
		local features = tile.Features
		if tile.K == "Junction" then
			local other = sample(tile, 2, ex, ey, ez)
			tile.Paths[2] = other
			tile.SplitS = sAt(main, Track.SPLIT)
			table.insert(features, { K = "Switch", B = 1, S = tile.SplitS })
			local span = Track.MERGE - Track.SPLIT
			if tile.O == "Dead" then
				table.insert(features, { K = "Buffer", B = 2, S = sAt(other, Track.SPLIT + span * Track.BUFFER_T) })
			elseif tile.O == "TNT" then
				table.insert(features, { K = "TNT", B = 2, S = sAt(other, Track.SPLIT + span * Track.TNT_T) })
			else
				table.insert(
					features,
					{ K = "Crystal", B = 2, S = sAt(other, Track.SPLIT + span * Track.SHORT_CRYSTAL_T) }
				)
			end
		elseif tile.K == "Bend" then
			local dir = tile.D or 1
			local len = tile.Len
			table.insert(
				features,
				{ K = "Lean", B = 1, S = sAt(main, len * 0.02), S1 = sAt(main, len * 0.3), Dir = dir }
			)
			table.insert(
				features,
				{ K = "Lean", B = 1, S = sAt(main, len * 0.4), S1 = sAt(main, len * 0.68), Dir = -dir }
			)
			table.insert(features, { K = "Crystal", B = 1, S = sAt(main, len * 0.35) })
		elseif tile.K == "Gap" then
			table.insert(features, { K = "Gap", B = 1, S = sAt(main, Track.GAP_FROM), S1 = sAt(main, Track.GAP_TO) })
			table.insert(features, { K = "Crystal", B = 1, S = sAt(main, Track.GAP_TO + 12) })
		elseif tile.K == "Hill" then
			table.insert(features, { K = "Crystal", B = 1, S = sAt(main, tile.Len * 0.45) })
		elseif tile.K == "Finish" then
			finishS = sAt(main, Track.FINISH_AT)
			goal = progress + finishS
		end
		tile.Start = progress
		tile.Nominal = main.Total
		progress += main.Total
		local x, y = Track.Shape(tile, 1, tile.Len)
		ex, ey, ez = ex + x, ey + y, ez - tile.Len
		table.insert(built, tile)
	end
	return { Tiles = built, Goal = goal, FinishS = finishS }
end

-- A cart's sideways offset from the main line on the station deck: its start lane (1..12, left to
-- right), gliding onto the main line by START_MERGE.
function Track.StartOffset(lane: number, s: number): number
	local share = 1 - smooth(s / Track.START_MERGE)
	return (lane - 6.5) * Track.START_LANE * share
end

-- The sample segment index (1-based, i to i + 1) holding distance s on a path.
local function segment(path: Path, s: number): number
	local list = path.S
	local lo, hi = 1, #list - 1
	if s <= 0 then
		return 1
	elseif s >= list[#list] then
		return hi
	end
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if list[mid] <= s then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return lo
end

-- The course-local point at distance s on a path and its (unit) heading. Headings blend between
-- neighbouring segments, so a cart turns smoothly through the samples.
function Track.At(path: Path, s: number): (number, number, number, number, number, number)
	local i = segment(path, s)
	local s0, s1 = path.S[i], path.S[i + 1]
	local a = math.clamp((s - s0) / math.max(s1 - s0, 1e-6), 0, 1)
	local x = path.X[i] + (path.X[i + 1] - path.X[i]) * a
	local y = path.Y[i] + (path.Y[i + 1] - path.Y[i]) * a
	local z = path.Z[i] + (path.Z[i + 1] - path.Z[i]) * a
	local function dir(k: number): (number, number, number)
		k = math.clamp(k, 1, #path.S - 1)
		local dx, dy, dz = path.X[k + 1] - path.X[k], path.Y[k + 1] - path.Y[k], path.Z[k + 1] - path.Z[k]
		local m = math.sqrt(dx * dx + dy * dy + dz * dz)
		return dx / m, dy / m, dz / m
	end
	local ax, ay, az = dir(i)
	local other = if a < 0.5 then i - 1 else i + 1
	local bx, by, bz = dir(other)
	local w = if a < 0.5 then 0.5 - a else a - 0.5
	local hx, hy, hz = ax + (bx - ax) * w, ay + (by - ay) * w, az + (bz - az) * w
	local m = math.sqrt(hx * hx + hy * hy + hz * hz)
	return x, y, z, hx / m, hy / m, hz / m
end

-- Uphill (+) or downhill (-) at s.
function Track.Grade(path: Path, s: number): number
	local i = segment(path, s)
	local ds = path.S[i + 1] - path.S[i]
	return (path.Y[i + 1] - path.Y[i]) / math.max(ds, 1e-6)
end

-- The lean a bend asks for at s (-1 left, 1 right, 0 none).
function Track.LeanAt(tile: BuiltTile, branch: number, s: number): number
	for _, feature in tile.Features do
		if feature.K == "Lean" and feature.B == branch and s >= feature.S and s <= (feature.S1 :: number) then
			return feature.Dir :: number
		end
	end
	return 0
end

-- How far along the course a cart is (for places, the progress strip and results).
-- A cart off the rails (DownUntil) counts where it will come back (ReTile, ReS on the main way),
-- not where it fell.
function Track.Progress(course: Course, rider: Rider): number
	local tileIndex, branch, s = rider.Tile, rider.B, rider.S
	if rider.DownUntil and rider.DownUntil > 0 and rider.ReTile and rider.ReS then
		tileIndex, branch, s = rider.ReTile, 1, rider.ReS
	end
	local tile = course.Tiles[tileIndex]
	local path = tile.Paths[branch] or tile.Paths[1]
	return tile.Start + tile.Nominal * math.clamp(s / path.Total, 0, 1)
end

-- The next switch ahead of a cart within `reach` studs: its tile index and the studs to it.
function Track.NextSwitch(course: Course, rider: Rider, reach: number): (number?, number)
	local tile = course.Tiles[rider.Tile]
	if tile.SplitS and rider.S < tile.SplitS and rider.B == 1 then
		return tile.Index, tile.SplitS - rider.S
	end
	local nextTile = course.Tiles[rider.Tile + 1]
	if nextTile and nextTile.SplitS then
		local path = tile.Paths[rider.B] or tile.Paths[1]
		local away = path.Total - rider.S + nextTile.SplitS
		if away <= reach then
			return nextTile.Index, away
		end
	end
	return nil, math.huge
end

-- The height of a jump `since` seconds after it started (0 on the rails).
function Track.JumpHeight(since: number): number
	if since <= 0 or since >= Track.JUMP_TIME then
		return 0
	end
	local t = since / Track.JUMP_TIME
	return 4 * t * (1 - t) * Track.JUMP_HEIGHT
end

function Track.Airborne(jumpAt: number, at: number): boolean
	return Track.JumpHeight(at - jumpAt) >= Track.MIN_CLEAR
end

-- A TNT track's crates can be jumped (owner, asked about a cart that flew clean over them and still
-- blew up: "Jumping over TNT works"): high enough (TNT_CLEAR: its underside over the crates' tops,
-- 2.87 on a 0.45 base) from the front wheels meeting the crates until the back wheels are past them
-- (TNT_SPAN along the track).
Track.TNT_CLEAR = 2.6
Track.TNT_SPAN = 3.7
function Track.JumpsTNT(jumpAt: number, at: number, v: number): boolean
	local across = (Track.TNT_SPAN + Track.WHEELBASE) / math.max(v, 1)
	return Track.JumpHeight(at - jumpAt) >= Track.TNT_CLEAR
		and Track.JumpHeight(at + across - jumpAt) >= Track.TNT_CLEAR
end

-- A cart blown up by the TNT on `tileIndex` at `at`, its front wheels at the crates (`s` along that
-- way): it stops there, down until its comeback at the junction.
function Track.Blast(course: Course, rider: Rider, tileIndex: number, at: number, s: number)
	rider.Tile = tileIndex
	rider.B = 2
	rider.S = s
	rider.V = 0
	rider.DownUntil = at + Track.COMEBACK
	rider.ReTile = tileIndex
	rider.ReS = course.Tiles[tileIndex].SplitS
	rider.DashUntil = 0
end

-- Does a jump made at `jumpAt` carry the whole cart over a gap of `gap` studs whose start its front
-- wheels reach at `at`, at speed `v`?
function Track.Clears(jumpAt: number, at: number, v: number, gap: number): boolean
	local across = (gap + Track.WHEELBASE) / math.max(v, 1)
	return Track.Airborne(jumpAt, at) and Track.Airborne(jumpAt, at + across)
end

-- The best moment to jump a gap of `gap` studs whose start the front wheels reach at `at`, at speed
-- `v`: the middle of the jump over the middle of the gap.
function Track.BestJump(at: number, v: number, gap: number): number
	return at - (Track.JUMP_TIME / 2 - (gap + Track.WHEELBASE) / (2 * math.max(v, 1)))
end

-- When a JUMP pressed at `pressAt` takes off, for a gap whose start the front wheels reach at `at`
-- (nil: no gap coming) at speed `v`: at once, unless it's early for the gap (it wouldn't clear it,
-- and the best moment is at most HOLD away): then at the best moment.
function Track.TakeOff(pressAt: number, at: number?, v: number, gap: number): number
	if at == nil or Track.Clears(pressAt, at, v, gap) then
		return pressAt
	end
	local best = Track.BestJump(at, v, gap)
	if pressAt < best and best - pressAt <= Track.HOLD then
		return best
	end
	return pressAt
end

-- The next gap a rider's front wheels haven't reached yet, on its tile or the next: how far away
-- (studs along the rails), its length and its tile. Nil when there's none within `reach` studs.
function Track.NextGap(course: Course, rider: Rider, reach: number): (number?, number, number)
	local tile = course.Tiles[rider.Tile]
	if not tile then
		return nil, 0, 0
	end
	local path = tile.Paths[rider.B] or tile.Paths[1]
	local tiles: { BuiltTile? } = { tile, course.Tiles[rider.Tile + 1] }
	local extras = { 0, path.Total }
	for index = 1, 2 do
		local t, extra = tiles[index], extras[index]
		if t then
			for _, feature in t.Features do
				if feature.K == "Gap" then
					local front = feature.S - Track.HALF_BASE + extra - rider.S
					if front > 0 and front <= reach then
						return front, (feature.S1 :: number) - feature.S, t.Index
					end
				end
			end
		end
	end
	return nil, 0, 0
end

-- When a JUMP pressed at `pressAt` takes off, for a rider whose place is as at `now` (TakeOff with
-- its next gap).
function Track.JumpFor(course: Course, rider: Rider, pressAt: number, now: number): number
	local front, gap = Track.NextGap(course, rider, 90)
	if not front then
		return pressAt
	end
	local v = math.max(rider.V, 1)
	return Track.TakeOff(pressAt, now + front / v, v, gap)
end

-- The way a cart takes at a switch: the side of the latest press made after `zoneAt` (a tap is
-- enough), or of one pressed earlier and still held at the switch, and no later than GRACE after
-- `crossAt`. 0 when there's none.
function Track.Choose(picks: { Pick }, zoneAt: number, crossAt: number): number
	local best: Pick? = nil
	for _, pick in picks do
		if pick.At > crossAt + Track.GRACE then
			continue
		end
		if pick.At < zoneAt and pick.Until ~= nil and pick.Until < crossAt then
			continue -- pressed before the cart came near, and let go before the switch
		end
		if best == nil or pick.At > best.At then
			best = pick
		end
	end
	return if best then best.Dir else 0
end

-- The branch a choice gives at a junction: the long way unless the cart picked the other side.
function Track.BranchFor(tile: BuiltTile, dir: number): number
	return if dir ~= 0 and dir == -(tile.L or 1) then 2 else 1
end

export type Event = { K: string, At: number, Tile: number, B: number, S: number, V: number, Gap: number? }

-- One step of riding. Returns what the cart passed in this step (each with the exact moment): a
-- "Switch", a "Gap" (its front wheels at the gap), a "Crystal", "TNT" (its front wheels at the
-- crates), a "Buffer" (handled here: it doesn't depend on any input), "Back" (rolled back onto the
-- long way), "Return" (a comeback), "Finish". Switches, gaps, crystals and TNT are judged by the
-- caller, with ping leeway (TNT: Track.JumpsTNT, else Track.Blast from the moment it happened).
function Track.Ride(course: Course, rider: Rider, dt: number, now: number): { Event }
	local events: { Event } = {}
	if rider.Finish then
		return events
	end
	if rider.DownUntil > 0 then
		if now < rider.DownUntil then
			return events
		end
		rider.DownUntil = 0
		rider.Tile = rider.ReTile or rider.Tile
		rider.B = 1
		rider.S = rider.ReS or 0
		rider.V = Track.RESTART_V
		rider.Back = false
		rider.JumpAt = -math.huge
		rider.DashUntil = 0
		table.insert(events, { K = "Return", At = now, Tile = rider.Tile, B = 1, S = rider.S, V = rider.V })
	end
	local tile = course.Tiles[rider.Tile]
	local path = tile.Paths[rider.B]
	if rider.Back then
		rider.S -= Track.BACK_SPEED * dt
		local split = tile.SplitS or 0
		if rider.S <= split then
			rider.S = split
			rider.Back = false
			rider.B = 1
			rider.V = Track.AFTER_BACK
			table.insert(events, { K = "Back", At = now, Tile = tile.Index, B = 1, S = split, V = rider.V })
		end
		return events
	end
	local airborne = Track.Airborne(rider.JumpAt, now)
	if not airborne then
		local target = Track.CRUISE - Track.SLOPE * Track.Grade(path, rider.S)
		local lean = Track.LeanAt(tile, rider.B, rider.S)
		if lean ~= 0 and rider.Lean == lean then
			target += Track.LEAN_BOOST
		elseif lean ~= 0 and rider.Lean == -lean then
			target -= Track.LEAN_SLOW
		end
		local rate = if target > rider.V then Track.RISE else Track.FALL
		rider.V += (target - rider.V) * (1 - math.exp(-rate * dt))
		if now < rider.DashUntil then
			local fade = 1 - (rider.DashUntil - now) / Track.DASH_TIME
			rider.V = math.max(rider.V, Track.DASH - (Track.DASH - Track.CRUISE) * fade * 0.6)
		end
		rider.V = math.clamp(rider.V, Track.MIN_V, Track.MAX_V)
	end
	local before = rider.S
	rider.S += rider.V * dt
	local function crossing(s: number): number?
		-- the moment the cart's middle passed s in this step (nil if it didn't)
		if before < s and rider.S >= s then
			local fraction = (s - before) / math.max(rider.S - before, 1e-6)
			return now - dt * (1 - fraction)
		end
		return nil
	end
	for _, feature in tile.Features do
		if feature.B ~= rider.B and not (feature.K == "Switch") then
			continue
		end
		local kind = feature.K
		local mark = if kind == "Gap"
				or kind == "Buffer"
				or kind == "TNT"
			then feature.S - Track.HALF_BASE -- (the front wheels reach it)
			else feature.S
		local at = crossing(mark)
		if not at then
			continue
		end
		local event: Event = { K = kind, At = at, Tile = tile.Index, B = rider.B, S = mark, V = rider.V }
		if kind == "Gap" then
			event.Gap = (feature.S1 :: number) - feature.S
		elseif kind == "Buffer" then
			rider.S = mark
			rider.Back = true
			rider.V = 0
			rider.DashUntil = 0
		end
		table.insert(events, event)
		if kind == "Buffer" then
			return events
		end
	end
	if rider.Tile == #course.Tiles then
		local at = crossing(course.FinishS)
		if at then
			rider.Finish = at
			table.insert(events, { K = "Finish", At = at, Tile = tile.Index, B = 1, S = course.FinishS, V = rider.V })
			return events
		end
	end
	if rider.S >= path.Total and rider.Tile < #course.Tiles then
		rider.S -= path.Total
		rider.Tile += 1
		rider.B = 1
	end
	return events
end

-- A fall into a gap: off the rails for COMEBACK, then back at the gap tile's checkpoint.
function Track.Fall(course: Course, rider: Rider, tileIndex: number, at: number)
	local tile = course.Tiles[tileIndex]
	rider.DownUntil = at + Track.COMEBACK
	rider.ReTile = tileIndex
	rider.ReS = tile.Paths[1].S[Track.CHECKPOINT + 1]
	rider.DashUntil = 0
	rider.V = 0
end

function Track.Ordinal(place: number): string
	local suffix = "th"
	local tens = place % 100
	if tens < 11 or tens > 13 then
		local ones = place % 10
		suffix = if ones == 1 then "st" elseif ones == 2 then "nd" elseif ones == 3 then "rd" else "th"
	end
	return `{place}{suffix}`
end

-- A round's course: the station, five junctions with three gaps, two bends and a hill between them
-- (in a shuffled order), and the way out. `random` is a Random (or anything with NextInteger).
function Track.Generate(random: any): { Tile }
	local others = { "Short", "Short", "Dead", "TNT" }
	table.insert(others, ({ "Short", "Dead", "TNT" })[random:NextInteger(1, 3)])
	for i = #others, 2, -1 do
		local j = random:NextInteger(1, i)
		others[i], others[j] = others[j], others[i]
	end
	local fillers = { "Gap", "Gap", "Gap", "Bend", "Bend", "Hill" }
	for i = #fillers, 2, -1 do
		local j = random:NextInteger(1, i)
		fillers[i], fillers[j] = fillers[j], fillers[i]
	end
	local tiles: { Tile } = { { K = "Start" } }
	local bendDir = if random:NextInteger(0, 1) == 0 then -1 else 1
	local function filler(kind: string)
		if kind == "Bend" then
			table.insert(tiles, { K = "Bend", D = bendDir })
			bendDir = -bendDir -- (the second bend swings back)
		else
			table.insert(tiles, { K = kind })
		end
	end
	-- (a filler before every junction, so each switch has its approach; the sixth before the exit)
	for k = 1, 5 do
		filler(fillers[k])
		table.insert(tiles, { K = "Junction", L = if random:NextInteger(0, 1) == 0 then -1 else 1, O = others[k] })
	end
	filler(fillers[6])
	table.insert(tiles, { K = "Finish" })
	return tiles
end

return Track

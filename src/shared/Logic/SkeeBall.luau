--!strict
-- Skee-Ball in the lobby arcade (owner: "Can we also add skiball to the lobby?"): the path a ball
-- takes and where it scores, as plain math the server (which decides the score), every device
-- (which draws the same ball rolling) and the specs share. Leaf module: no requires, no Roblox
-- APIs. tools/meshgen/props/Arcade.py reads these numbers to build the machine, so the lane, the
-- hop and the rings you see are the ones the ball follows.
--
-- Lane space (studs): u across the lane (+ = the player's right), y up from the machine's base, s
-- along the lane from the release point toward the rings. The machine prop faces -Z (its player
-- stands on that side), so in the prop's own space x = -u and z = RELEASE_Z + s (ToMachine).
--
-- A roll is two numbers the player picks, aim (-1 left .. 1 right) and power (0 .. 1), kept to
-- thousandths (Quantize) so the server and every device start from the same numbers. The ball:
--   1. rolls up the lane, slowing at a steady rate, on the slant the aim gives it;
--   2. rides the hop at the end of the lane, which throws it up at a fixed angle;
--   3. flies (toy gravity) onto the tilted ring board; too soft and it drops short into the front
--      gutter, too hard and it sails over the board into the back gutter (both score nothing);
--   4. drops into the ring it came down in: 50 in the middle, then 40, 30 and 20 round it, 10
--      anywhere else on the board, or 100 in the two little cups in the top corners. It bounces a
--      little where it lands, and on a ring's lip it can fall either way: both come from a hash of
--      the roll (Luck), so the same roll always scores the same, and seen from above the ball always
--      goes straight the way it was aimed.
-- Only + - * / and sqrt (and integer math) decide the score: those give the same answer on every
-- device, while sin and cos can differ in the last digit between platforms.

local SkeeBall = {}

SkeeBall.BALLS = 9 -- balls per game
SkeeBall.BALL_R = 0.36

-- The machine (tools/meshgen/props/Arcade.py builds it from these).
SkeeBall.LANE_HALF = 1.6 -- half the lane's inside width
SkeeBall.RELEASE_Z = -5.3 -- prop z of the release point (s = 0)
SkeeBall.LANE_START = -0.8 -- s where the lane floor starts, at the machine's front
SkeeBall.LANE_Y = 2.4 -- lane floor height at s = 0
SkeeBall.LANE_RISE = 0.07 -- the lane climbs this much per stud
SkeeBall.HOP_S = 7.2 -- the hop's ramp starts here
SkeeBall.LIP_S = 7.75 -- and ends in its lip here
SkeeBall.LIP_Y = 3.2 -- lip height
SkeeBall.TROUGH_Y = 2.7 -- floor of the front gutter, between the hop and the board
SkeeBall.BOARD_S = 8.45 -- the ring board's bottom edge
SkeeBall.BOARD_Y = 3.15 -- its height there
SkeeBall.BOARD_TAN = 0.75 -- the board climbs 0.75 per stud of s (about 37 degrees)
SkeeBall.BOARD_COS = 0.8 -- cos and sin of that slope, exactly
SkeeBall.BOARD_SIN = 0.6
SkeeBall.BOARD_LEN = 3.9 -- along the slope
SkeeBall.BOARD_HALF = 1.85 -- half the board's width (the target box is a little wider than the lane)
SkeeBall.BACK_S = 12.6 -- the backstop's face, behind the back gutter
SkeeBall.BACK_TROUGH_Y = 4.7 -- floor of the back gutter, between the board's top edge and the backstop
SkeeBall.TOP_Y = 7.4 -- the cage's roof over the target box

-- The rings, round RING_W up the board from its bottom edge: each one's edge (the ball's center has
-- to be inside it). The 10 ring is everything else on the board; its edge here is just drawn.
SkeeBall.RING_W = 1.85
SkeeBall.RINGS = {
	{ Points = 50, R = 0.4 },
	{ Points = 40, R = 0.68 },
	{ Points = 30, R = 0.97 },
	{ Points = 20, R = 1.27 },
	{ Points = 10, R = 1.6 },
}
SkeeBall.LIP = 0.07 -- within this of an edge, the ball can drop either side
SkeeBall.CUP_U = 1.36 -- the 100 cups, top left and top right
SkeeBall.CUP_W = 3.4
SkeeBall.CUP_R = 0.3

-- How the ball moves.
SkeeBall.V_MIN = 5.6 -- release speed at no power (studs/s): it still gets over the hop, just
SkeeBall.V_MAX = 18.2
SkeeBall.DECEL = 2 -- slowing on the lane (studs/s^2)
SkeeBall.AIM_SLANT = 0.13 -- sideways studs per stud of s at full aim: just past a 100 cup
SkeeBall.HOP_KEEP = 0.9 -- speed kept over the hop
SkeeBall.HOP_COS = 0.6427876097 -- the hop throws the ball up at 50 degrees
SkeeBall.HOP_SIN = 0.7660444431
SkeeBall.GRAVITY = 30 -- toy gravity: a slow, readable arc
SkeeBall.BACK_KEEP = 0.15 -- speed kept bouncing off the backstop
SkeeBall.JITTER_U = 0.06 -- the little bounce where it lands
SkeeBall.JITTER_W = 0.1
SkeeBall.SETTLE_SPEED = 4.5 -- rolling round a ring to its hole (studs/s)
SkeeBall.SETTLE_MIN = 0.3
SkeeBall.DROP_TIME = 0.2
SkeeBall.GUTTER_TIME = 0.4

export type Pocket = { Id: string, Points: number, U: number, W: number, Ring: number? }

-- Every place a ball can end up, with its hole (u, w on the board). The rings' holes sit at the
-- bottom of each ring's channel, one above the other up the middle, like the real machine.
SkeeBall.Pockets = {} :: { [string]: Pocket }
do
	local inner = 0
	for index, ring in SkeeBall.RINGS do
		local id = tostring(ring.Points)
		local w = if index == 1 then SkeeBall.RING_W else SkeeBall.RING_W - (inner + ring.R) / 2
		SkeeBall.Pockets[id] = { Id = id, Points = ring.Points, U = 0, W = w, Ring = index }
		inner = ring.R
	end
	SkeeBall.Pockets["100L"] = { Id = "100L", Points = 100, U = -SkeeBall.CUP_U, W = SkeeBall.CUP_W }
	SkeeBall.Pockets["100R"] = { Id = "100R", Points = 100, U = SkeeBall.CUP_U, W = SkeeBall.CUP_W }
	SkeeBall.Pockets.Gutter = { Id = "Gutter", Points = 0, U = 0, W = -1 } -- too soft: short of the board
	SkeeBall.Pockets.Over = { Id = "Over", Points = 0, U = 0, W = -1 } -- too hard: over the board
end

export type Phase = {
	Kind: string, -- "Lane" | "Ramp" | "Air" | "Settle" | "Drop"
	T0: number,
	T1: number,
	[string]: any,
}

export type Path = {
	AimQ: number,
	PowerQ: number,
	Ball: number,
	Speed: number, -- release speed
	Phases: { Phase },
	Landed: number, -- seconds after the release when it comes down (the next ball may roll)
	Done: number, -- seconds after the release when it drops in (the score counts)
	Pocket: string,
	Points: number,
	LandU: number, -- where it came down on the board (u, w), before its little bounce
	LandW: number,
}

local UMAX = SkeeBall.LANE_HALF - SkeeBall.BALL_R
local BOX_UMAX = SkeeBall.BOARD_HALF - SkeeBall.BALL_R
local BOARD_TOP_S = SkeeBall.BOARD_S + SkeeBall.BOARD_LEN * SkeeBall.BOARD_COS

local function clamp(x: number, lo: number, hi: number): number
	return if x < lo then lo elseif x > hi then hi else x
end

-- Folds a position that ran past a wall back inside (springy walls at +-limit).
local function fold(u: number, limit: number): number
	local period = 4 * limit
	local x = (u + limit) - math.floor((u + limit) / period) * period
	if x > 2 * limit then
		x = period - x
	end
	return x - limit
end

-- The lane floor's height at s; past HOP_S the hop's ramp curves up to the lip.
function SkeeBall.FloorY(s: number): number
	if s <= SkeeBall.HOP_S then
		return SkeeBall.LANE_Y + s * SkeeBall.LANE_RISE
	end
	local length = SkeeBall.LIP_S - SkeeBall.HOP_S
	local x = clamp(s - SkeeBall.HOP_S, 0, length)
	local y0 = SkeeBall.LANE_Y + SkeeBall.HOP_S * SkeeBall.LANE_RISE
	-- A parabola leaving the lane at its slope and meeting the lip's height.
	local curve = (SkeeBall.LIP_Y - y0 - SkeeBall.LANE_RISE * length) / (length * length)
	return y0 + SkeeBall.LANE_RISE * x + curve * x * x
end

-- The ring board's surface: lane space (u, y, s) of the point w up it.
function SkeeBall.BoardPoint(u: number, w: number): (number, number, number)
	return u, SkeeBall.BOARD_Y + w * SkeeBall.BOARD_SIN, SkeeBall.BOARD_S + w * SkeeBall.BOARD_COS
end

-- Where the ball's center is when it sits on the board at (u, w).
function SkeeBall.OnBoard(u: number, w: number): (number, number, number)
	local s = SkeeBall.BOARD_S + w * SkeeBall.BOARD_COS - SkeeBall.BALL_R * SkeeBall.BOARD_SIN
	local y = SkeeBall.BOARD_Y + w * SkeeBall.BOARD_SIN + SkeeBall.BALL_R * SkeeBall.BOARD_COS
	return u, y, s
end

-- Lane space to the machine prop's own space (its pivot is the bottom center of its box).
function SkeeBall.ToMachine(u: number, y: number, s: number): (number, number, number)
	return -u, y, SkeeBall.RELEASE_Z + s
end

-- The two inputs, rounded to thousandths: aim -1..1 -> 0..2000, power 0..1 -> 0..1000.
function SkeeBall.Quantize(aim: number, power: number): (number, number)
	local a = if aim == aim then clamp(aim, -1, 1) else 0 -- NaN counts as the middle
	local p = if power == power then clamp(power, 0, 1) else 0
	return math.floor((a + 1) * 1000 + 0.5), math.floor(p * 1000 + 0.5)
end

-- A well-mixed number in [0, 1) from the roll (integer math only, so every device agrees). Every
-- multiplier is under 2^21, so each product stays exact in a double.
function SkeeBall.Luck(aimQ: number, powerQ: number, ball: number, salt: number): number
	local x = (aimQ + 2003 * (powerQ + 1009 * (ball + 13 * salt))) % 4294967296
	x = (x * 1664525 + 1013904223) % 4294967296
	x = bit32.bxor(x, bit32.rshift(x, 13))
	x = (x * 1103515 + 12345) % 4294967296
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = (x * 1664525 + 1013904223) % 4294967296
	x = bit32.bxor(x, bit32.rshift(x, 15))
	return x / 4294967296
end

-- Inside an edge of radius r at distance d? On the lip, `luck` (0..1) decides, likelier the deeper in.
local function inside(d: number, r: number, luck: number): boolean
	if d <= r - SkeeBall.LIP then
		return true
	elseif d >= r + SkeeBall.LIP then
		return false
	end
	return luck < (r + SkeeBall.LIP - d) / (2 * SkeeBall.LIP)
end

-- Which pocket a ball that came down at (u, w) on the board drops into.
function SkeeBall.PocketAt(u: number, w: number, luck: number): string
	for _, side in { -1, 1 } do
		local du, dw = u - side * SkeeBall.CUP_U, w - SkeeBall.CUP_W
		if inside(math.sqrt(du * du + dw * dw), SkeeBall.CUP_R, luck) then
			return if side < 0 then "100L" else "100R"
		end
	end
	local dw = w - SkeeBall.RING_W
	local d = math.sqrt(u * u + dw * dw)
	for index = 1, #SkeeBall.RINGS - 1 do
		local ring = SkeeBall.RINGS[index]
		if inside(d, ring.R, luck) then
			return tostring(ring.Points)
		end
	end
	return "10"
end

-- Solves a + b t - c t^2 = 0 (c > 0) for its later root, the time the ball comes down to it.
local function landing(a: number, b: number, c: number): number
	local disc = b * b + 4 * a * c
	return (b + math.sqrt(math.max(disc, 0))) / (2 * c)
end

-- The whole path of one roll. aimQ and powerQ come from Quantize; ball is 1..BALLS.
function SkeeBall.Path(aimQ: number, powerQ: number, ball: number): Path
	local aim = aimQ / 1000 - 1
	local power = powerQ / 1000
	local R = SkeeBall.BALL_R
	local G = SkeeBall.GRAVITY
	local phases: { Phase } = {}

	-- 1. Up the lane: the distance along its slanted path is d(t) = v0 t - DECEL t^2 / 2.
	local v0 = SkeeBall.V_MIN + power * (SkeeBall.V_MAX - SkeeBall.V_MIN)
	local slant = aim * SkeeBall.AIM_SLANT
	local stretch = math.sqrt(1 + slant * slant) -- path length per stud of s
	local vHop = math.sqrt(math.max(v0 * v0 - 2 * SkeeBall.DECEL * SkeeBall.HOP_S * stretch, 0.25))
	local tHop = (v0 - vHop) / SkeeBall.DECEL
	table.insert(phases, { Kind = "Lane", T0 = 0, T1 = tHop, V0 = v0, Stretch = stretch, Slant = slant })

	-- 2. Over the hop's ramp, at the speed it got there with.
	local tLip = tHop + (SkeeBall.LIP_S - SkeeBall.HOP_S) * stretch / vHop
	table.insert(phases, { Kind = "Ramp", T0 = tHop, T1 = tLip, Slant = slant })

	-- 3. Off the lip. Seen from above it keeps going the way it was aimed (the hop only tips it up).
	local forward = vHop / stretch * SkeeBall.HOP_KEEP
	local s0, y0 = SkeeBall.LIP_S, SkeeBall.LIP_Y + R
	local u0 = fold(slant * s0, UMAX)
	local vs, vy = forward * SkeeBall.HOP_COS, forward * SkeeBall.HOP_SIN
	local vu = slant * vs

	-- Where its center meets the board's surface (lifted by its radius): y0 + vy t - G t^2 / 2 =
	-- plane0 + TAN (s0 + vs t - BOARD_S).
	local plane0 = SkeeBall.BOARD_Y + R / SkeeBall.BOARD_COS
	local tBoard =
		landing(y0 - plane0 - SkeeBall.BOARD_TAN * (s0 - SkeeBall.BOARD_S), vy - SkeeBall.BOARD_TAN * vs, G / 2)
	local centerS = s0 + vs * tBoard
	local landW = (centerS + R * SkeeBall.BOARD_SIN - SkeeBall.BOARD_S) / SkeeBall.BOARD_COS
	local landU = fold(u0 + vu * tBoard, BOX_UMAX)

	local pocket: string
	local tLand: number
	local function flight(t0: number, t1: number, s: number, y: number, u: number, vS: number, vY: number, vU: number)
		table.insert(phases, { Kind = "Air", T0 = t0, T1 = t1, S = s, Y = y, U = u, VS = vS, VY = vY, VU = vU })
	end
	if landW < 0 then
		-- Too soft: it comes down in the front gutter, short of the board.
		pocket = "Gutter"
		local t = landing(y0 - SkeeBall.TROUGH_Y - R, vy, G / 2)
		t = math.min(t, (SkeeBall.BOARD_S - R - s0) / vs)
		flight(tLip, tLip + t, s0, y0, u0, vs, vy, vu)
		tLand = tLip + t
		local s, y = s0 + vs * t, y0 + vy * t - G / 2 * t * t
		local u = fold(u0 + vu * t, UMAX)
		table.insert(phases, {
			Kind = "Settle",
			T0 = tLand,
			T1 = tLand + SkeeBall.GUTTER_TIME,
			From = { u, y, s },
			To = { u * 0.4, SkeeBall.TROUGH_Y + R - 0.15, (s + SkeeBall.BOARD_S) / 2 },
		})
		landU, landW = u, -1
	elseif landW > SkeeBall.BOARD_LEN then
		-- Too hard: it sails over the board, hits the backstop and drops into the back gutter.
		pocket = "Over"
		local backS = SkeeBall.BACK_S - R
		local floorY = SkeeBall.BACK_TROUGH_Y + R
		local tWall = (backS - s0) / vs
		local yWall = y0 + vy * tWall - G / 2 * tWall * tWall
		if yWall <= floorY then
			local t = landing(y0 - floorY, vy, G / 2)
			flight(tLip, tLip + t, s0, y0, u0, vs, vy, vu)
			tLand = tLip + t
		else
			flight(tLip, tLip + tWall, s0, y0, u0, vs, vy, vu)
			local vyWall = vy - G * tWall
			local uWall = fold(u0 + vu * tWall, BOX_UMAX)
			local t = landing(yWall - floorY, vyWall, G / 2)
			-- Bouncing back a little, but never back over the board's top edge.
			local vsBack = -math.min(vs * SkeeBall.BACK_KEEP, (backS - BOARD_TOP_S - R) / math.max(t, 0.05))
			flight(tLip + tWall, tLip + tWall + t, backS, yWall, uWall, vsBack, vyWall, vu * SkeeBall.BACK_KEEP)
			tLand = tLip + tWall + t
		end
		local last = phases[#phases]
		local tau = last.T1 - last.T0
		local u = fold(last.U + last.VU * tau, BOX_UMAX)
		local s = last.S + last.VS * tau
		table.insert(phases, {
			Kind = "Settle",
			T0 = tLand,
			T1 = tLand + SkeeBall.GUTTER_TIME,
			From = { u, floorY, s },
			To = { u * 0.4, floorY - 0.15, s },
		})
		landU, landW = u, SkeeBall.BOARD_LEN + 1
	else
		-- On the board: a little bounce, then into its ring.
		flight(tLip, tLip + tBoard, s0, y0, u0, vs, vy, vu)
		tLand = tLip + tBoard
		local u1 =
			clamp(landU + (SkeeBall.Luck(aimQ, powerQ, ball, 1) * 2 - 1) * SkeeBall.JITTER_U, -BOX_UMAX, BOX_UMAX)
		local w1 =
			clamp(landW + (SkeeBall.Luck(aimQ, powerQ, ball, 2) * 2 - 1) * SkeeBall.JITTER_W, 0, SkeeBall.BOARD_LEN)
		pocket = SkeeBall.PocketAt(u1, w1, SkeeBall.Luck(aimQ, powerQ, ball, 3))
		local target = SkeeBall.Pockets[pocket]
		local ring = target.Ring
		local radius = 0
		local length: number
		if ring and ring > 1 then
			-- Round its ring's channel, from where it bounced to the hole at the bottom.
			radius = (SkeeBall.RINGS[ring].R + SkeeBall.RINGS[ring - 1].R) / 2
			local dw = w1 - SkeeBall.RING_W
			local d = math.sqrt(u1 * u1 + dw * dw)
			local around = (1 + dw / math.max(d, 1e-6)) * 0.5 * math.pi * radius
			length = around + math.abs(d - radius)
		else
			local du, dw = u1 - target.U, w1 - target.W
			length = math.sqrt(du * du + dw * dw)
		end
		table.insert(phases, {
			Kind = "Settle",
			T0 = tLand,
			T1 = tLand + 0.12 + math.max(SkeeBall.SETTLE_MIN, length / SkeeBall.SETTLE_SPEED),
			Land = { landU, landW },
			Bounce = { u1, w1 },
			Hole = { target.U, target.W },
			Radius = radius,
		})
	end

	local last = phases[#phases]
	local done = last.T1 + SkeeBall.DROP_TIME
	table.insert(phases, { Kind = "Drop", T0 = last.T1, T1 = done })
	return {
		AimQ = aimQ,
		PowerQ = powerQ,
		Ball = ball,
		Speed = v0,
		Phases = phases,
		Landed = tLand,
		Done = done,
		Pocket = pocket,
		Points = SkeeBall.Pockets[pocket].Points,
		LandU = landU,
		LandW = landW,
	}
end

-- Drawing ------------------------------------------------------------------------------------------
-- Everything below only draws the ball, so it may use any math: the score never depends on it.

local function smooth(x: number): number
	return x * x * (3 - 2 * x)
end

-- The phase running at time t (after the release) and how far into it.
local function phaseAt(path: Path, t: number): (Phase, number)
	local phases = path.Phases
	for _, phase in phases do
		if t < phase.T1 then
			return phase, math.max(0, t - phase.T0)
		end
	end
	local last = phases[#phases]
	return last, last.T1 - last.T0
end

-- Where the ball's center is t seconds after the release: lane space (u, y, s).
function SkeeBall.Sample(path: Path, t: number): (number, number, number)
	local phase, tau = phaseAt(path, t)
	local R = SkeeBall.BALL_R
	local kind = phase.Kind
	local span = phase.T1 - phase.T0
	local x = if span > 0 then clamp(tau / span, 0, 1) else 1
	if kind == "Lane" then
		local d = phase.V0 * tau - SkeeBall.DECEL / 2 * tau * tau
		local s = d / phase.Stretch
		return fold(phase.Slant * s, UMAX), SkeeBall.FloorY(s) + R, s
	elseif kind == "Ramp" then
		local s = SkeeBall.HOP_S + (SkeeBall.LIP_S - SkeeBall.HOP_S) * x
		return fold(phase.Slant * s, UMAX), SkeeBall.FloorY(s) + R, s
	elseif kind == "Air" then
		local s = phase.S + phase.VS * tau
		local y = phase.Y + phase.VY * tau - SkeeBall.GRAVITY / 2 * tau * tau
		return fold(phase.U + phase.VU * tau, BOX_UMAX), y, s
	elseif kind == "Settle" then
		if phase.From then
			-- Rolling along a gutter toward its drain.
			local from, to = phase.From, phase.To
			local e = smooth(x)
			return from[1] + (to[1] - from[1]) * e, from[2] + (to[2] - from[2]) * e, from[3] + (to[3] - from[3]) * e
		end
		local land, bounce, hole = phase.Land, phase.Bounce, phase.Hole
		local bounceTime = 0.12 / span -- the first 0.12 s: a little hop to where it settles
		local u, w, lift
		if x < bounceTime then
			local k = x / bounceTime
			u = land[1] + (bounce[1] - land[1]) * k
			w = land[2] + (bounce[2] - land[2]) * k
			lift = 0.22 * 4 * k * (1 - k)
		else
			local k = smooth((x - bounceTime) / (1 - bounceTime))
			lift = 0
			if phase.Radius > 0 then
				-- Into its ring's channel first, then round it down to the hole at the bottom.
				local du, dw = bounce[1], bounce[2] - SkeeBall.RING_W
				local a0 = math.atan2(dw, du)
				local delta = (-math.pi / 2 - a0 + math.pi) % (2 * math.pi) - math.pi
				local d0 = math.sqrt(du * du + dw * dw)
				local radius = d0 + (phase.Radius - d0) * smooth(math.min(1, k / 0.3))
				local a = a0 + delta * smooth(clamp((k - 0.15) / 0.85, 0, 1))
				u = clamp(math.cos(a) * radius, -BOX_UMAX, BOX_UMAX)
				w = SkeeBall.RING_W + math.sin(a) * radius
			else
				u = bounce[1] + (hole[1] - bounce[1]) * k
				w = bounce[2] + (hole[2] - bounce[2]) * k
			end
		end
		local bu, by, bs = SkeeBall.OnBoard(u, w)
		return bu, by + lift, bs
	end
	-- Drop: it sinks into its hole.
	local phases = path.Phases
	local u, y, s = SkeeBall.Sample(path, phases[#phases - 1].T1 - 1e-4)
	return u, y - 0.9 * x * x, s
end

return SkeeBall

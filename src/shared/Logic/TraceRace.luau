-- Trace Race rules shared by the server and clients: the guideline course and the accuracy score.
--
-- After "Trace Race" (Mario Party 4): everyone rides a giant crayon down their own long guideline
-- and only steers; the crayon moves forward on its own at a steady pace. A lane's position is
-- (s, x): s studs down the lane (it grows with time, SPEED studs a second, the same for everyone)
-- and x studs right of the lane's middle (what the player steers). The guide is one x for every s,
-- the same course in every lane, built from a list of pieces the server picks (Generate) and shares,
-- so both sides draw and judge the very same line.
--
-- Scoring: the lane is cut into one-stud steps. Each step scores 0..1 by how far the player's
-- drawn line is from the guide there (the real distance between the two lines, so a diagonal stroke
-- isn't judged by its sideways gap), and the score is the average over the whole course: a step
-- your crayon never drew scores 0. Full marks while the drawn line touches the guide (FULL comes
-- from the two lines' widths, as drawn), nothing from ZERO studs off. The line between two sent
-- positions is straight on every screen, and it's scored straight too.
--
-- The guide spends a good part of the course near the lane's middle, so a crayon that never steers
-- would still touch it often. Scores are measured against that: every step also knows what a crayon
-- left in the middle would score there (Course.I), and a player's percent is how much of the gap
-- between "never steered" and "perfect" they made up. Never steering scores 0; a perfect line 100.

local TraceRace = {}

TraceRace.LANE = 16 -- lane width in studs
TraceRace.SPEED = 15 -- studs a second down the lane
TraceRace.STEER = 13 -- the crayon's top sideways speed (studs a second)
TraceRace.LIMIT = 7 -- how far from the lane's middle the crayon can go
TraceRace.AMP = 5 -- how far from the lane's middle the guide goes
TraceRace.LENGTH = 450 -- the course is about this long (30 s)
TraceRace.GUIDE_WIDTH = 0.7 -- the pencil guideline, as drawn
TraceRace.LINE_WIDTH = 1.3 -- the crayon's line, as drawn
-- The two lines touch while their middles are less than half of both widths apart.
TraceRace.FULL = (TraceRace.GUIDE_WIDTH + TraceRace.LINE_WIDTH) / 2
TraceRace.ZERO = 3
TraceRace.SAMPLE_GAP = 0.06 -- clients sample the crayon this often (seconds)
TraceRace.MAX_CHUNK = 40 -- positions in one batch

export type Piece = { K: string, L: number, X: number?, A: number?, N: number? }

export type Course = {
	Pieces: { Piece },
	Length: number, -- in whole studs
	G: { number }, -- guide x at s = 0, 1, 2, ... (index s + 1)
	I: { number }, -- what a crayon left in the middle scores at each step (index s + 1)
	Idle: number, -- I added up
}

local function ease(t: number): number
	return (1 - math.cos(math.pi * t)) / 2
end

-- A random course: a straight start, then curves, zigzag turns and waves that get tighter towards
-- the end, then a straight finish. Steepness stays within what the crayon can steer.
function TraceRace.Generate(rng: Random): { Piece }
	local pieces: { Piece } = { { K = "S", L = 24 } }
	local total = 24
	local x = 0
	local amp = TraceRace.AMP
	local last = "S"
	while total < TraceRace.LENGTH - 26 do
		local progress = total / TraceRace.LENGTH
		local steep = 0.32 + 0.4 * progress -- the steepest slope a piece may have (dx/ds)
		local roll = rng:NextNumber()
		local piece: Piece
		if roll < 0.32 and last ~= "C" then
			-- A smooth curve over to another spot.
			local target
			repeat
				target = rng:NextNumber(-amp, amp)
			until math.abs(target - x) >= 3
			local length = math.pi * math.abs(target - x) / (2 * steep) * rng:NextNumber(1.05, 1.35)
			piece = { K = "C", L = math.ceil(length), X = math.floor(target * 10 + 0.5) / 10 }
			x = piece.X :: number
		elseif roll < 0.6 and progress > 0.12 then
			-- Sharp turns: straight diagonals with corners.
			local legs = rng:NextInteger(2, if progress > 0.5 then 4 else 3)
			local slope = steep * rng:NextNumber(0.8, 1)
			local side = if x > 0 then -1 elseif x < 0 then 1 elseif rng:NextNumber() < 0.5 then -1 else 1
			for _ = 1, legs do
				local target = side * rng:NextNumber(amp * 0.5, amp)
				target = math.floor(target * 10 + 0.5) / 10
				table.insert(pieces, { K = "Z", L = math.ceil(math.abs(target - x) / slope), X = target })
				total += pieces[#pieces].L
				x = target
				side = -side
			end
			last = "Z"
			continue
		elseif roll < 0.85 then
			-- Waves round where the crayon is: amplitude from the room left in the lane.
			local room = amp - math.abs(x)
			if room < 1.6 then
				local length = math.pi * math.abs(x) / (2 * steep) * 1.1
				piece = { K = "C", L = math.ceil(length), X = 0 }
				x = 0
			else
				local a = math.floor(rng:NextNumber(1.5, math.min(room, 4)) * 10 + 0.5) / 10
				local n = rng:NextInteger(2, 3)
				local length = 2 * math.pi * a * n / steep * rng:NextNumber(1, 1.2)
				piece = { K = "W", L = math.ceil(length), A = a * (if rng:NextNumber() < 0.5 then -1 else 1), N = n }
			end
		else
			piece = { K = "S", L = rng:NextInteger(6, 12) }
		end
		table.insert(pieces, piece)
		total += piece.L
		last = piece.K
	end
	-- Back to the middle and a straight run to the finish line.
	if math.abs(x) > 0.05 then
		table.insert(pieces, { K = "C", L = math.ceil(math.pi * math.abs(x) / (2 * 0.4) * 1.2), X = 0 })
	end
	table.insert(pieces, { K = "S", L = 20 })
	return pieces
end

-- Turns a piece list into the guide (x at every whole stud).
function TraceRace.Build(pieces: { Piece }): Course
	local g = { 0 }
	local x = 0
	for _, piece in pieces do
		local length = math.max(1, math.floor(piece.L))
		local from = x
		for step = 1, length do
			local t = step / length
			local value
			if piece.K == "C" then
				value = from + ((piece.X or 0) - from) * ease(t)
			elseif piece.K == "Z" then
				value = from + ((piece.X or 0) - from) * t
			elseif piece.K == "W" then
				value = from + (piece.A or 0) * math.sin(2 * math.pi * (piece.N or 1) * t)
			else
				value = from
			end
			table.insert(g, math.clamp(value, -TraceRace.AMP, TraceRace.AMP))
		end
		x = g[#g]
	end
	local course = { Pieces = pieces, Length = #g - 1, G = g, I = {}, Idle = 0 }
	for k = 0, course.Length do
		local idle = TraceRace.Accuracy(TraceRace.Distance(course :: any, k, 0))
		course.I[k + 1] = idle
		course.Idle += idle
	end
	return course :: any
end

-- The guide's x at distance s (between whole studs it's a straight line, as drawn).
function TraceRace.GuideAt(course: Course, s: number): number
	local g = course.G
	if s <= 0 then
		return g[1]
	end
	if s >= course.Length then
		return g[#g]
	end
	local k = math.floor(s)
	local f = s - k
	return g[k + 1] + (g[k + 2] - g[k + 1]) * f
end

-- How far the point (s, x) is from the guide line (the nearest bit of it, within a few studs).
function TraceRace.Distance(course: Course, s: number, x: number): number
	local g = course.G
	local best = math.huge
	local first = math.max(0, math.floor(s) - 6)
	local last = math.min(course.Length - 1, math.floor(s) + 6)
	for k = first, last do
		-- Segment from (k, g[k+1]) to (k+1, g[k+2]); point (s, x).
		local ax, bx = g[k + 1], g[k + 2]
		local dx = bx - ax
		local t = math.clamp(((s - k) + (x - ax) * dx) / (1 + dx * dx), 0, 1)
		local ps, px = k + t, ax + dx * t
		local d = (s - ps) ^ 2 + (x - px) ^ 2
		if d < best then
			best = d
		end
	end
	return math.sqrt(best)
end

-- 0..1 for a step drawn `distance` studs from the guide.
function TraceRace.Accuracy(distance: number): number
	if distance <= TraceRace.FULL then
		return 1
	end
	return math.clamp(1 - (distance - TraceRace.FULL) / (TraceRace.ZERO - TraceRace.FULL), 0, 1)
end

-- A player's line so far. Starts at the start (s = 0, x = 0, where every crayon starts).
export type Tracker = {
	Course: Course,
	S: number,
	X: number,
	Next: number, -- the next whole step to score
	Sum: number,
	Count: number,
	IdleSum: number, -- what never steering would have scored on the steps counted so far
	Add: (self: Tracker, s: number, x: number) -> (),
	Score: (self: Tracker) -> number,
	Live: (self: Tracker) -> number?,
}

local Tracker = {}
Tracker.__index = Tracker

function TraceRace.Tracker(course: Course): Tracker
	local self = setmetatable({
		Course = course,
		S = 0,
		X = 0,
		Next = 0,
		Sum = 0,
		Count = 0,
		IdleSum = 0,
	}, Tracker)
	return (self :: any) :: Tracker
end

-- The line goes on, straight, from where it was to (s, x): every whole step on the way scores.
function Tracker.Add(self: Tracker, s: number, x: number)
	local course = self.Course
	s = math.min(s, course.Length)
	if s < self.S then
		return
	end
	local s0, x0 = self.S, self.X
	while self.Next <= s do
		local step = self.Next
		local f = if s > s0 then (step - s0) / (s - s0) else 1
		local at = x0 + (x - x0) * math.clamp(f, 0, 1)
		self.Sum += TraceRace.Accuracy(TraceRace.Distance(course, step, at))
		self.IdleSum += course.I[step + 1] or 0
		self.Count += 1
		self.Next += 1
	end
	self.S, self.X = s, x
end

-- Accuracy over some steps against what never steering scores on them, 0..1.
local function beyondIdle(sum: number, idle: number, steps: number): number
	local room = steps - idle
	if room <= 1e-6 then
		return if sum >= steps - 1e-6 then 1 else 0
	end
	return math.clamp((sum - idle) / room, 0, 1)
end

-- The final score in percent (one decimal): steps never drawn count as 0.
function Tracker.Score(self: Tracker): number
	local course = self.Course
	local share = beyondIdle(self.Sum, course.Idle, course.Length + 1)
	return math.floor(share * 1000 + 0.5) / 10
end

-- The score so far (over the steps drawn), in whole percent: what the HUD shows during the ride
-- (nil before anything is drawn).
function Tracker.Live(self: Tracker): number?
	if self.Count == 0 then
		return nil
	end
	return math.floor(beyondIdle(self.Sum, self.IdleSum, self.Count) * 100 + 0.5)
end

-- Twelve crayon colours with names (colour is never the only cue: the name and the lane number go
-- with it everywhere).
TraceRace.Colors = {
	{ Name = "RED", Color = Color3.fromRGB(235, 55, 60) },
	{ Name = "BLUE", Color = Color3.fromRGB(45, 120, 235) },
	{ Name = "GREEN", Color = Color3.fromRGB(50, 185, 80) },
	{ Name = "ORANGE", Color = Color3.fromRGB(255, 145, 30) },
	{ Name = "PURPLE", Color = Color3.fromRGB(150, 80, 220) },
	{ Name = "PINK", Color = Color3.fromRGB(255, 105, 180) },
	{ Name = "TEAL", Color = Color3.fromRGB(20, 185, 180) },
	{ Name = "YELLOW", Color = Color3.fromRGB(250, 205, 30) },
	{ Name = "BROWN", Color = Color3.fromRGB(150, 90, 50) },
	{ Name = "SKY", Color = Color3.fromRGB(110, 200, 255) },
	{ Name = "LIME", Color = Color3.fromRGB(160, 220, 40) },
	{ Name = "BLACK", Color = Color3.fromRGB(55, 55, 65) },
}

return TraceRace

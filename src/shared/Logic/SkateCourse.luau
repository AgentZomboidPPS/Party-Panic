-- Skate Escape's rules as plain math, shared by the server (which owns the race) and the client
-- (which predicts its own skater so pushing and jumping feel instant, and draws everyone else).
--
-- A racer is a small table: D (studs along the course), V (studs/s), Air (server time the ollie
-- started, or nil), Wipe (server time a wipeout ends, or nil), Pushes (a counter clients animate
-- kicks from). The course is a straight bridge along the lanes; obstacles sit at the same distance
-- in every lane, so every lane is equally hard. Nothing here touches instances.

local SkateCourse = {}

SkateCourse.LaneWidth = 8
SkateCourse.Length = 1400 -- the finish line
SkateCourse.RunOut = 40 -- the goal platform past the line where finishers coast to a stop
SkateCourse.BoardHeight = 0.55 -- the board's deck above the track
SkateCourse.Crouch = 0.3 -- how much the skating stance lowers the hips

-- Pushing: each push adds Gain * (1 - V / Max); friction and drag slow you down. Mashing about seven
-- times a second holds ~50 studs/s, three times a second ~39.
SkateCourse.Gain = 14
SkateCourse.Max = 60
SkateCourse.Friction = 3
SkateCourse.Drag = 0.3
SkateCourse.Boost = 15 -- speed a boost pad adds
SkateCourse.BoostMax = 66

SkateCourse.AirTime = 0.75 -- an ollie: this long in the air ...
SkateCourse.AirHeight = 5.2 -- ... peaking this high (studs above the track)
SkateCourse.WipeTime = 1.3 -- lying on the deck after hitting a crate or barrier
SkateCourse.FallTime = 1.9 -- falling into a gap, then popping back up on the far side

-- What each obstacle is: Len is its depth along the course, Clear the height the board needs to be
-- at when it passes the obstacle's middle.
SkateCourse.Kinds = {
	Crate = { Len = 3.4, Height = 2.6, Clear = 2.35 },
	Barrier = { Len = 1.4, Height = 3.6, Clear = 3.25 },
	Gap = { Len = 14 },
	Boost = { Len = 7 },
}

export type Obstacle = { Kind: string, D: number, Len: number }
export type Racer = {
	D: number,
	V: number,
	Air: number?,
	AirEnd: number?,
	Wipe: number?,
	WipeAt: number?,
	WipeKind: string?,
	FallD: number?,
	Pushes: number,
	Next: number,
	Done: boolean?,
}
export type Collapse = { T0: number, D0: number, V0: number, A: number, T1: number }

function SkateCourse.NewRacer(): Racer
	return { D = 0, V = 0, Pushes = 0, Next = 1 }
end

-- A fair, varied course: crates first so everyone learns to jump, then crates, barriers, gaps and
-- boost pads with enough room between them to land and push again.
function SkateCourse.Generate(rng: Random, length: number?): { Obstacle }
	local finish = length or SkateCourse.Length
	local list = {}
	local d = 95
	local last = ""
	local index = 0
	while d < finish - 70 do
		index += 1
		local kind
		if index <= 2 then
			kind = "Crate"
		elseif index == 3 then
			kind = "Barrier"
		elseif index == 4 then
			kind = "Gap"
		else
			local roll = rng:NextNumber()
			kind = if roll < 0.32
				then "Crate"
				elseif roll < 0.58 then "Barrier"
				elseif roll < 0.82 then "Gap"
				else "Boost"
			if kind == last and kind ~= "Crate" then
				kind = "Crate"
			end
		end
		local len = SkateCourse.Kinds[kind].Len
		if kind == "Gap" then
			len = 12 + rng:NextInteger(0, 3) * 1.5
		end
		table.insert(list, { Kind = kind, D = d, Len = len })
		last = kind
		-- A boost pad is followed closely by something to jump; everything else needs room to land.
		d += if kind == "Boost" then rng:NextInteger(38, 46) else rng:NextInteger(58, 88)
	end
	return list
end

-- The collapse front: everything behind it has fallen into the lava. It starts behind the start
-- line, speeds up steadily and reaches the finish line at T1.
function SkateCourse.NewCollapse(start: number, length: number?): Collapse
	local finish = length or SkateCourse.Length
	local t0 = start + 3
	local t1 = start + 42
	local d0 = -30
	local v0 = 27
	local span = t1 - t0
	local a = 2 * (finish - d0 - v0 * span) / (span * span)
	return { T0 = t0, D0 = d0, V0 = v0, A = a, T1 = t1 }
end

function SkateCourse.CollapseAt(collapse: Collapse, now: number, length: number?): number
	local t = now - collapse.T0
	if t <= 0 then
		return collapse.D0
	end
	return math.min(collapse.D0 + collapse.V0 * t + 0.5 * collapse.A * t * t, length or SkateCourse.Length)
end

-- When the collapse reaches distance `d` (for warnings and the client's crumble animation).
function SkateCourse.CollapseTime(collapse: Collapse, d: number): number
	local a, v0 = collapse.A, collapse.V0
	local need = d - collapse.D0
	if need <= 0 then
		return collapse.T0
	end
	if a <= 1e-6 then
		return collapse.T0 + need / v0
	end
	return collapse.T0 + (-v0 + math.sqrt(v0 * v0 + 2 * a * need)) / a
end

-- How high the board is above the track at `now` (0 when grounded).
function SkateCourse.Height(racer: Racer, now: number): number
	local air = racer.Air
	if not air then
		return 0
	end
	local x = (now - air) / SkateCourse.AirTime
	if x <= 0 or x >= 1 then
		return 0
	end
	return 4 * SkateCourse.AirHeight * x * (1 - x)
end

function SkateCourse.IsWiped(racer: Racer, now: number): boolean
	return racer.Wipe ~= nil and now < racer.Wipe
end

-- A push: returns true if it counted (not while airborne, wiped out or done).
function SkateCourse.Push(racer: Racer, now: number): boolean
	if racer.Done or SkateCourse.IsWiped(racer, now) or SkateCourse.Height(racer, now) > 0 then
		return false
	end
	racer.V = math.min(SkateCourse.BoostMax, racer.V + SkateCourse.Gain * math.max(0, 1 - racer.V / SkateCourse.Max))
	racer.Pushes += 1
	return true
end

-- An ollie, starting at `at` (defaults to now). Returns true if it counted.
function SkateCourse.Jump(racer: Racer, now: number, at: number?): boolean
	if racer.Done or SkateCourse.IsWiped(racer, now) or SkateCourse.Height(racer, now) > 0 then
		return false
	end
	racer.Air = at or now
	racer.AirEnd = (at or now) + SkateCourse.AirTime
	return true
end

-- Would an ollie that started at `start` have carried the board over obstacle `o`, which the
-- racer reached at `crossAt` going `speed`?
function SkateCourse.WouldClear(o: Obstacle, start: number, crossAt: number, speed: number): boolean
	if o.Kind == "Gap" then
		local over = o.Len / math.max(speed, 5)
		return start <= crossAt + 0.02 and start + SkateCourse.AirTime >= crossAt + over
	end
	local x = (crossAt - start) / SkateCourse.AirTime
	if x <= 0 or x >= 1 then
		return false
	end
	return 4 * SkateCourse.AirHeight * x * (1 - x) >= SkateCourse.Kinds[o.Kind].Clear
end

export type Event = { Kind: string, Index: number, At: number }

-- Advances a racer by `dt` seconds ending at `now`. Returns an event when the racer meets
-- something: "Hit" (didn't clear a crate or barrier), "Fall" (on the ground over a gap) or "Boost".
-- The caller decides what happens (SkateCourse.Apply), so the server can allow for ping first.
function SkateCourse.Step(racer: Racer, obstacles: { Obstacle }, now: number, dt: number): Event?
	if racer.Done then
		return nil
	end
	if racer.Wipe then
		if now < racer.Wipe then
			racer.V = 0
			return nil
		end
		racer.Wipe = nil
		racer.WipeKind = nil
		racer.FallD = nil
	end
	if racer.Air and now >= racer.Air + SkateCourse.AirTime then
		racer.Air = nil
	end
	local v = racer.V
	v = math.max(0, v - (SkateCourse.Friction + SkateCourse.Drag * v) * dt)
	racer.V = v
	local from = racer.D
	local to = from + v * dt
	racer.D = to
	if v <= 0 then
		return nil
	end
	for index = racer.Next, #obstacles do
		local o = obstacles[index]
		local front, back = o.D - o.Len / 2, o.D + o.Len / 2
		if front > to then
			break
		end
		if o.Kind == "Gap" then
			if to >= front and from < back then
				local crossAt = now - math.max(0, to - math.max(front, from)) / v
				if SkateCourse.Height(racer, crossAt) <= 0 then
					racer.Next = index + 1
					return { Kind = "Fall", Index = index, At = crossAt }
				end
			end
			if to >= back then
				racer.Next = index + 1
			end
		elseif from < o.D and to >= o.D then
			racer.Next = index + 1
			local crossAt = now - (to - o.D) / v
			if o.Kind == "Boost" then
				if SkateCourse.Height(racer, crossAt) <= 0 then
					return { Kind = "Boost", Index = index, At = crossAt }
				end
			elseif SkateCourse.Height(racer, crossAt) < SkateCourse.Kinds[o.Kind].Clear then
				return { Kind = "Hit", Index = index, At = crossAt }
			end
		elseif to >= o.D then
			racer.Next = index + 1
		end
	end
	return nil
end

-- Applies an event from Step: a wipeout puts the racer past the obstacle, stopped for a moment.
function SkateCourse.Apply(racer: Racer, event: Event, obstacles: { Obstacle }, now: number)
	local o = obstacles[event.Index]
	if not o then
		return
	end
	if event.Kind == "Boost" then
		racer.V = math.min(SkateCourse.BoostMax, racer.V + SkateCourse.Boost)
		return
	end
	racer.V = 0
	racer.Air = nil
	racer.WipeAt = now
	racer.WipeKind = event.Kind
	racer.Next = math.max(racer.Next, event.Index + 1)
	if event.Kind == "Fall" then
		racer.Wipe = now + SkateCourse.FallTime
		racer.FallD = math.clamp(racer.D, o.D - o.Len / 2 + 1.5, o.D + o.Len / 2 - 1.5)
		racer.D = o.D + o.Len / 2 + 2
	else
		racer.Wipe = now + SkateCourse.WipeTime
		racer.D = math.max(racer.D, o.D + o.Len / 2 + 1)
	end
end

-- Where to draw a racer: distance, height above the track, a forward tumble (radians) and a drop
-- (studs below the track, falling through a gap).
function SkateCourse.Pose(racer: Racer, now: number): (number, number, number, number)
	if racer.Wipe and now < racer.Wipe and racer.WipeAt then
		local t = now - racer.WipeAt
		if racer.WipeKind == "Fall" then
			local sink = SkateCourse.FallTime * 0.6
			if t < sink then
				return racer.FallD or racer.D, 0, t * 2.2, math.min(16, 0.5 * 60 * t * t)
			end
			local pop = math.clamp((t - sink) / 0.35, 0, 1)
			return racer.D, (1 - pop) * 3, 0, 0
		end
		-- Flipped head over heels across the obstacle, then a dizzy moment back on the board.
		local spin = math.clamp(t / 0.6, 0, 1)
		local hop = math.sin(spin * math.pi) * 3.2
		return racer.D, hop, spin * math.pi * 2, 0
	end
	return racer.D, SkateCourse.Height(racer, now), 0, 0
end

-- Lane `lane` (1-based) of `lanes`: sideways offset of its middle from the course's center line.
function SkateCourse.LaneX(lane: number, lanes: number): number
	return (lane - (lanes + 1) / 2) * SkateCourse.LaneWidth
end

-- Where a skater's root goes: a sideways stance (facing +X) riding toward -Z, `lift` above the track
-- (include the root's own height), flipped forward by `tumble` radians in a wipeout.
function SkateCourse.StanceCFrame(origin: Vector3, laneX: number, d: number, lift: number, tumble: number): CFrame
	local position = origin + Vector3.new(laneX, lift, -d)
	local facing = CFrame.lookAt(Vector3.zero, Vector3.xAxis)
	if tumble ~= 0 then
		return CFrame.new(position) * CFrame.fromAxisAngle(Vector3.xAxis, -tumble) * facing
	end
	return CFrame.new(position) * facing
end

-- Lane colors, always shown with the lane number so color is never the only cue.
SkateCourse.LaneColors = {
	Color3.fromRGB(255, 92, 92),
	Color3.fromRGB(255, 150, 60),
	Color3.fromRGB(255, 212, 70),
	Color3.fromRGB(160, 225, 80),
	Color3.fromRGB(80, 210, 120),
	Color3.fromRGB(60, 200, 190),
	Color3.fromRGB(80, 205, 255),
	Color3.fromRGB(80, 130, 255),
	Color3.fromRGB(150, 110, 255),
	Color3.fromRGB(210, 100, 255),
	Color3.fromRGB(255, 100, 200),
	Color3.fromRGB(240, 240, 250),
}

function SkateCourse.Ordinal(n: number): string
	local suffix = "th"
	if n % 100 < 11 or n % 100 > 13 then
		suffix = ({ "st", "nd", "rd" })[n % 10] or "th"
	end
	return `{n}{suffix}`
end

return SkateCourse

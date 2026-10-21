-- Skate Escape's rules as plain math, shared by the server (which owns the race) and the client
-- (which predicts its own skater so pushing and jumping feel instant, and draws everyone else).
--
-- A racer is a small table: D (studs along the course), V (studs/s), Air (server time the ollie
-- started, or nil), Wipe (server time a wipeout ends, or nil), Pushes (a counter clients animate
-- kicks from). The course is a straight bridge along the lanes; obstacles sit at the same distance
-- in every lane, so every lane is equally hard. Nothing here touches instances.
--
-- Hits are judged by what the skater sees (owner: "We need to fine tune some of the hitboxes. the
-- precision games will feel super bad if we dont."): a crate or barrier is hit only if the board's
-- wheels visibly sink into it while they're over it, wherever along it that happens (not just at its
-- middle); a gap or the crumbling edge only takes you once no wheel is left on the planks; a boost
-- pad counts whenever a wheel rolls on any part of it. A jump counts from where the skater was on
-- their own screen when they pressed it (see the server's Jump), so ping doesn't move it.
--
-- Audit pass (owner: "it just has to work"): the moment the collapse reaches the finish line it
-- used to take everyone the server still had short of the line, ignoring the lead it allows for
-- the rest of the race, so a rider whose screen showed them crossing in the last instant (up to
-- half their ping) fell through the goal instead of finishing. Caught now allows the lead there too.

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

-- The board as drawn (SkateBoard mesh, 3.7 long): its wheels sit this far ahead of and behind its
-- middle, which is the racer's distance D.
SkateCourse.WheelBase = 1.22
-- How far the wheels must visibly sink into a crate or barrier to count as hitting it. Less than this
-- is a graze that looks cleared at speed (a frame or two of wheel inside a corner).
SkateCourse.Sink = 1
-- An edge (a gap's lips, or the crumbling bridge) only takes you while no wheel is on the planks:
-- the board's middle must be this far past it (a wheel's distance from the middle).
SkateCourse.EdgeGrace = 1.2

-- What each obstacle is: Len is its depth along the course (where a wipeout puts you), Top and Half
-- the visible part the wheels must clear (the mesh's top and half its depth: the crate's box, the
-- barrier's bar; the barrier's little lamp sits between the wheels).
SkateCourse.Kinds = {
	Crate = { Len = 3.4, Height = 2.6, Top = 2.6, Half = 1.78 },
	Barrier = { Len = 1.4, Height = 3.6, Top = 3.2, Half = 0.16 },
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
-- line a few seconds after GO, gently at first (a slow pusher who misses a couple of obstacles still
-- has a chance), then speeds up steadily and reaches the finish line at T1.
function SkateCourse.NewCollapse(start: number, length: number?): Collapse
	local finish = length or SkateCourse.Length
	local t0 = start + 5
	local t1 = start + 42
	local d0 = -30
	local v0 = 18
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

-- How high the board is at `now` in an ollie that started at `air` (0 when grounded).
local function heightAt(air: number?, now: number): number
	if not air then
		return 0
	end
	local x = (now - air) / SkateCourse.AirTime
	if x <= 0 or x >= 1 then
		return 0
	end
	return 4 * SkateCourse.AirHeight * x * (1 - x)
end

-- How high the board is above the track at `now` (0 when grounded).
function SkateCourse.Height(racer: Racer, now: number): number
	return heightAt(racer.Air, now)
end

-- Whether an ollie that started at `air` (nil: none) carries the wheels over crate or barrier `o`,
-- whose middle the board's middle passes at `crossAt` going `speed`. The wheels are over it from
-- `reach` before that to `reach` after; the ollie's arc is highest in between, so the wheels are
-- lowest at one of those two moments (or on the deck, if it took off or landed in between).
function SkateCourse.Clears(o: Obstacle, air: number?, crossAt: number, speed: number): boolean
	local kind = SkateCourse.Kinds[o.Kind]
	local reach = (kind.Half + SkateCourse.WheelBase) / math.max(speed, 1)
	local need = kind.Top - SkateCourse.Sink
	return heightAt(air, crossAt - reach) >= need and heightAt(air, crossAt + reach) >= need
end

-- The stretch of course where the board is checked against a gap (on the deck there: falls in) or a
-- boost pad (on the deck there: boosted). A gap: from when the back wheels leave the near lip to when
-- the front wheels reach the far one. A pad: whenever any wheel is on it.
function SkateCourse.Span(o: Obstacle): (number, number)
	if o.Kind == "Gap" then
		return o.D - o.Len / 2 + SkateCourse.EdgeGrace, o.D + o.Len / 2 - SkateCourse.EdgeGrace
	end
	return o.D - o.Len / 2 - SkateCourse.WheelBase, o.D + o.Len / 2 + SkateCourse.WheelBase
end

-- The first obstacle a racer at `d` hasn't dealt with yet (what Step expects in racer.Next).
function SkateCourse.NextIndex(obstacles: { Obstacle }, d: number): number
	for index, o in obstacles do
		local edge = o.D
		if o.Kind == "Gap" or o.Kind == "Boost" then
			local _, back = SkateCourse.Span(o)
			edge = back
		end
		if edge > d then
			return index
		end
	end
	return #obstacles + 1
end

-- Whether the collapse front has taken a racer at `d`: once it's past their front wheels. `lead`
-- allows for how far ahead of the server's numbers their own screen draws them. Once the front
-- reaches the finish line, everyone short of it has fallen: short of it on their own screen, so a
-- rider who crossed there just before the last plank went still finishes (here, within the lead),
-- and a rider who has stopped (no lead) falls.
function SkateCourse.Caught(front: number, d: number, lead: number?, length: number?): boolean
	if front >= (length or SkateCourse.Length) then
		return d + (lead or 0) < front
	end
	return front > d + (lead or 0) + SkateCourse.EdgeGrace
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
-- (For a gap, `crossAt` is when the board reached the stretch it must fly over: see Span.)
function SkateCourse.WouldClear(o: Obstacle, start: number, crossAt: number, speed: number): boolean
	if o.Kind == "Gap" then
		local from, to = SkateCourse.Span(o)
		local over = math.max(0, to - from) / math.max(speed, 5)
		return start <= crossAt + 0.02 and start + SkateCourse.AirTime >= crossAt + over
	end
	return SkateCourse.Clears(o, start, crossAt, speed)
end

-- The first moment from `from` to `to` that a racer whose ollie started at `air` is on the deck, or
-- nil if they're in the air all that time.
local function groundedIn(air: number?, from: number, to: number): number?
	if not air or from <= air or from >= air + SkateCourse.AirTime then
		return from
	end
	local landing = air + SkateCourse.AirTime
	return if landing <= to then landing else nil
end

-- Speed and distance after rolling `dt` seconds from speed `v`, slowed by friction and drag: the
-- exact solution of dv/dt = -(Friction + Drag * v), so a phone drawing 30 frames a second and the
-- server stepping 60 times agree on where a skater is.
local function roll(v: number, dt: number): (number, number)
	local f, k = SkateCourse.Friction, SkateCourse.Drag
	local rest = f / k
	local base = math.max(0, v) + rest
	local t = math.min(dt, math.log(base / rest) / k) -- (it comes to a stop at the second one)
	local decay = math.exp(-k * t)
	local distance = math.max(0, base * (1 - decay) / k - rest * t)
	return if t < dt then 0 else math.max(0, base * decay - rest), distance
end

export type Event = { Kind: string, Index: number, At: number, D: number?, Landed: boolean? }

-- Advances a racer by `dt` seconds ending at `now`. Returns an event when the racer meets
-- something: "Hit" (didn't clear a crate or barrier), "Fall" (on the deck over a gap, see Span;
-- Landed when they came down in it rather than rolled in) or "Boost". The caller decides what happens
-- (SkateCourse.Apply), so the server can allow for ping first.
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
	local speed, moved = roll(racer.V, dt)
	racer.V = speed
	local from = racer.D
	local to = from + moved
	racer.D = to
	if moved <= 0 then
		return nil
	end
	local v = moved / dt -- the average speed over the step, to tell when along it things happened
	for index = racer.Next, #obstacles do
		local o = obstacles[index]
		if o.Kind == "Gap" or o.Kind == "Boost" then
			local front, back = SkateCourse.Span(o)
			if front > to then
				break
			end
			if from < back then
				local enter = now - (to - math.max(front, from)) / v
				local leave = now - (to - math.min(back, to)) / v
				local at = groundedIn(racer.Air, enter, leave)
				if at then
					racer.Next = index + 1
					return {
						Kind = if o.Kind == "Gap" then "Fall" else "Boost",
						Index = index,
						At = at,
						D = to - (now - at) * v,
						Landed = at > enter,
					}
				end
			end
			if to >= back then
				racer.Next = index + 1
			end
		else
			if o.D > to then
				break
			end
			racer.Next = index + 1
			if from < o.D then
				local crossAt = now - (to - o.D) / v
				if not SkateCourse.Clears(o, racer.Air, crossAt, v) then
					return { Kind = "Hit", Index = index, At = crossAt }
				end
			end
		end
	end
	return nil
end

-- Applies an event from Step: a wipeout puts the racer just past the obstacle, stopped for a moment.
-- `now` should be the moment of the hit (event.At), so a wipeout applied late (the server waits out
-- the ping allowance first) ends when it would have and gives no extra distance.
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
		-- Drawn dropping where they left the deck (or came down short of the far lip).
		racer.FallD = math.clamp(event.D or -math.huge, o.D - o.Len / 2 + 1.5, o.D + o.Len / 2 - 1.5)
		racer.D = o.D + o.Len / 2 + 2
	else
		racer.Wipe = now + SkateCourse.WipeTime
		racer.D = o.D + o.Len / 2 + 1
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

-- How high a character's root sits above the track while skating (feet on the board, knees bent).
function SkateCourse.RootHeight(humanoid: Humanoid, root: BasePart): number
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
	return legs + root.Size.Y / 2 + SkateCourse.BoardHeight - SkateCourse.Crouch
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

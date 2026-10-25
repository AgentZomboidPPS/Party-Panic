--!strict
-- Sky Stack's numbers and rules, shared by the server (which judges every drop and owns the
-- towers), the clients (which slide the blocks along the same schedule and show their own drop
-- before the server's answer arrives) and the bots (which time their taps on it), so all of them
-- agree on where a block was when DROP was pressed and what it leaves on the tower.
-- Owner: "Build it." (the pitch: "Every player gets their own tower in a row of up to 12, with the
-- sky behind them. A block slides back and forth above your tower, and you tap to drop it. Any part
-- hanging over the edge gets sliced off, so each miss makes your next block smaller. A perfect drop
-- keeps the block full size and sends a gust to the towers on either side ... If your block shrinks
-- to nothing, your tower crumbles and you're out. The first player to reach the cloud line wins.")
--
-- A tower stands on a square base FULL studs across. Every floor is a block BLOCK studs tall. Blocks
-- are boxes in the tower's own frame: { X0, X1, Z0, Z1 }, studs from the base's middle. The next block
-- has the size of the top one and slides across it along X on odd floors and Z on even ones, between
-- AMP studs either side of the top's middle (a triangle wave at the floor's speed, from a start time
-- on the server's clock). DROP stops it where it is (by when the player pressed: Logic/Buzzer):
--   * within PERFECT studs of the middle, or PERFECT_TIME seconds of travel on a fast block, it snaps
--     on exactly ("Perfect"; Stack.PerfectFor); every COMBO-th perfect in a row
--     grows the block back by GROW each way (never past the base) and blows a gust at the neighbours,
--     whose next block slides GUST times faster;
--   * otherwise what hangs over the top block is sliced off and falls ("Cut");
--   * and if less than MIN_WIDTH would be left, the whole block falls and the tower is done ("Miss").
-- Presses in the first READY seconds of a slide don't count (a double tap meant for the last block).
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.

local Stack = {}

Stack.FULL = 8 -- the base and a full block, studs across
Stack.HALF = Stack.FULL / 2
Stack.BLOCK = 1.6 -- one floor's height (studs)
Stack.GOAL = 25 -- floors to the cloud line
Stack.AMP = 9 -- a sliding block swings this far either side of the top's middle (it starts clear of it)
Stack.SPEED = 9 -- the first floor's slide speed (studs/s)
Stack.RAMP = 0.3 -- each floor slides this much faster...
Stack.MAX_SPEED = 17 -- ...up to this
Stack.GUST = 1.35 -- a gusted block slides this many times faster
Stack.PERFECT = 0.3 -- this close to the middle snaps on: a perfect drop (studs)...
Stack.PERFECT_TIME = 0.03 -- ...or this many seconds' travel from it, on faster blocks
Stack.MIN_WIDTH = 0.5 -- less than this left over is a miss (studs)
Stack.COMBO = 3 -- every this many perfect drops in a row grow the block and blow a gust
Stack.GROW = 0.5 -- a combo grows the block this much each way, on both axes (studs)
Stack.SPAWN = 0.4 -- from a drop to the next block setting off (it waits, clear of the tower)
Stack.READY = 0.25 -- presses this soon after a block sets off are ignored (a double tap)

export type Block = { X0: number, X1: number, Z0: number, Z1: number }

export type Slide = {
	Level: number, -- the floor this block becomes
	Axis: string, -- "X" or "Z"
	Dir: number, -- 1: sets off from the -axis side; -1: from the +axis side
	Start: number, -- server time it sets off
	Speed: number, -- studs/s
	Gust: boolean,
}

export type Drop = {
	Kind: string, -- "Perfect", "Cut" or "Miss"
	Offset: number, -- where the block was, along its axis, from the top's middle
	Block: Block?, -- what lands on the tower (nil for a miss)
	Falling: Block?, -- what falls off (the overhang, or the whole block on a miss)
	Streak: number, -- perfect drops in a row, this one included
	Combo: boolean, -- this perfect completed a combo (the block grew and a gust blows)
}

function Stack.Base(): Block
	return { X0 = -Stack.HALF, X1 = Stack.HALF, Z0 = -Stack.HALF, Z1 = Stack.HALF }
end

function Stack.Copy(block: Block): Block
	return { X0 = block.X0, X1 = block.X1, Z0 = block.Z0, Z1 = block.Z1 }
end

function Stack.AxisFor(level: number): string
	return if level % 2 == 1 then "X" else "Z"
end

function Stack.DirFor(level: number): number
	return if ((level - 1) // 2) % 2 == 0 then 1 else -1
end

function Stack.SpeedFor(level: number, gust: boolean?): number
	local speed = math.min(Stack.SPEED + Stack.RAMP * math.max(level - 1, 0), Stack.MAX_SPEED)
	return if gust then speed * Stack.GUST else speed
end

-- The slide for floor `level`, setting off at `start` (server time).
function Stack.NewSlide(level: number, start: number, gust: boolean?): Slide
	return {
		Level = level,
		Axis = Stack.AxisFor(level),
		Dir = Stack.DirFor(level),
		Start = start,
		Speed = Stack.SpeedFor(level, gust),
		Gust = gust == true,
	}
end

-- How close to the middle a block sliding at `speed` must be dropped to be perfect (studs): never
-- tighter than PERFECT_TIME seconds, so a fast block isn't a frame-perfect test.
function Stack.PerfectFor(speed: number): number
	return math.max(Stack.PERFECT, speed * Stack.PERFECT_TIME)
end

-- Where a sliding block is at time `t`, along its axis, from the top's middle: -AMP * Dir until it
-- sets off, then back and forth between -AMP and AMP.
function Stack.Offset(slide: Slide, t: number): number
	local amp = Stack.AMP
	local travelled = math.max(t - slide.Start, 0) * slide.Speed
	local along = travelled % (4 * amp)
	local x = if along <= 2 * amp then -amp + along else 3 * amp - along
	return x * slide.Dir
end

-- Whether a press at time `t` counts for this slide (not in its first READY seconds).
function Stack.Counts(slide: Slide, t: number): boolean
	return t >= slide.Start + Stack.READY
end

-- The first time at or after `after` that the block crosses the top's middle (bots aim for it).
function Stack.NextMiddle(slide: Slide, after: number): number
	local amp = Stack.AMP
	local travelled = (after - slide.Start) * slide.Speed
	local k = math.max(0, math.ceil((travelled - amp) / (2 * amp)))
	return slide.Start + (amp + 2 * amp * k) / slide.Speed
end

local function lowHigh(block: Block, axis: string): (number, number)
	if axis == "X" then
		return block.X0, block.X1
	end
	return block.Z0, block.Z1
end

local function withAxis(block: Block, axis: string, low: number, high: number): Block
	local copy = Stack.Copy(block)
	if axis == "X" then
		copy.X0, copy.X1 = low, high
	else
		copy.Z0, copy.Z1 = low, high
	end
	return copy
end

-- Rounds to a hundredth of a stud, so the server, the JSON it shares and every client agree.
local function snap(value: number): number
	return math.floor(value * 100 + 0.5) / 100
end

local function snapped(block: Block): Block
	return { X0 = snap(block.X0), X1 = snap(block.X1), Z0 = snap(block.Z0), Z1 = snap(block.Z1) }
end

-- The sliding block shifted to `offset` (what the player sees at that moment).
function Stack.Moving(top: Block, slide: Slide, offset: number): Block
	local low, high = lowHigh(top, slide.Axis)
	return withAxis(top, slide.Axis, low + offset, high + offset)
end

-- DROP pressed at time `t`: what lands on the tower `top` and what falls, after `streak` perfect
-- drops in a row.
function Stack.Drop(top: Block, slide: Slide, t: number, streak: number): Drop
	local offset = snap(Stack.Offset(slide, t))
	local axis = slide.Axis
	local low, high = lowHigh(top, axis)
	if math.abs(offset) <= Stack.PerfectFor(slide.Speed) then
		local count = streak + 1
		local combo = count % Stack.COMBO == 0
		local block = Stack.Copy(top)
		if combo then
			local grow = Stack.GROW
			block = {
				X0 = math.max(block.X0 - grow, -Stack.HALF),
				X1 = math.min(block.X1 + grow, Stack.HALF),
				Z0 = math.max(block.Z0 - grow, -Stack.HALF),
				Z1 = math.min(block.Z1 + grow, Stack.HALF),
			}
		end
		return {
			Kind = "Perfect",
			Offset = offset,
			Block = snapped(block),
			Falling = nil,
			Streak = count,
			Combo = combo,
		}
	end
	local moving = Stack.Moving(top, slide, offset)
	if (high - low) - math.abs(offset) < Stack.MIN_WIDTH then
		return { Kind = "Miss", Offset = offset, Block = nil, Falling = snapped(moving), Streak = 0, Combo = false }
	end
	local kept, falling
	if offset > 0 then
		kept = withAxis(top, axis, low + offset, high)
		falling = withAxis(top, axis, high, high + offset)
	else
		kept = withAxis(top, axis, low, high + offset)
		falling = withAxis(top, axis, low + offset, low)
	end
	return {
		Kind = "Cut",
		Offset = offset,
		Block = snapped(kept),
		Falling = snapped(falling),
		Streak = 0,
		Combo = false,
	}
end

-- How a tower places in the standings: towers at the top by when they got there (the press that
-- put the last floor on, seconds into the round: earlier first, whoever's drop reached the server
-- first), then the rest by floors, then by when they reached them (earlier first). Higher is better.
function Stack.Rank(floors: number, at: number, finished: boolean?): number
	if finished then
		return 1e6 - math.clamp(at, 0, 999)
	end
	return floors * 1000 - math.clamp(at, 0, 999)
end

return Stack

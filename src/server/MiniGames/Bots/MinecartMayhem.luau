-- How bots ride in Minecart Mayhem (contract in Bots/Default.luau). They press LEFT, RIGHT and JUMP
-- through ctx:BotAction, so the server rides and judges them exactly like players: a bot that
-- takes a TNT track is blown off, a bot that misses a gap falls, a bot down a dead end rolls back.
--
-- Switches: a bot reads the signs as it comes within reach of a switch. Good bots (bot.Skill up to
-- 0.9) read them right nearly every time and take the shortcuts; clumsy ones misread now and then
-- (taking the TNT or the dead end), or press too late and roll down the long way.
-- Jumps: a bot aims to be in the air from the gap's edge until its back wheels are over the far
-- side (Track.Clears), off by more the clumsier it is, and now and then jumps far too early or not
-- at all. The press is timed with ctx:Delay, so it doesn't depend on how often the brain runs.
-- Since players' early presses are held for the best moment (Track.HOLD), a bot's "far too early"
-- is earlier than that: it hops at once and comes down before the gap, so bots miss about as often.
-- Bends: a bot leans into each half of a bend, better bots more often and sooner; clumsy ones now
-- and then lean the wrong way and wobble.
--
-- The brain takes the track rules from the mode (mode.Track), so the offline sim can run it as is.

local Brain = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function setLean(bot, ctx, memory, dir: number)
	if memory.Lean ~= dir then
		memory.Lean = dir
		ctx:BotAction(bot, "Lean", dir, ctx:Now())
	end
end

function Brain.Step(bot, ctx, mode, _dt)
	local rider = mode.riders and mode.riders[bot]
	if not rider or rider.Gone or rider.Finish or not mode.racing or mode.ending then
		return
	end
	local Track = mode.Track
	local course = mode.course
	local memory = bot.Memory
	local skill = bot.Skill
	local rng = bot.Rng
	if memory.Ways == nil then
		memory.Ways = {}
		memory.Jumps = {}
		memory.Leans = {}
		memory.Lean = 0
	end
	if rider.DownUntil > 0 or rider.Back then
		memory.Jumps = {} -- (back at a checkpoint: that gap gets a fresh try)
		setLean(bot, ctx, memory, 0)
		return
	end
	local tile = course.Tiles[rider.Tile]
	local want = 0

	-- Switches: read the sign once it's in reach, then press (or not) on the way to the switch.
	local index, away = Track.NextSwitch(course, rider, Track.CHOOSE)
	if index and not memory.Ways[index] then
		local junction = course.Tiles[index]
		local long = junction.L or 1
		local reads = rng:NextNumber() < lerp(0.45, 0.97, skill)
		local side
		if junction.O == "Short" then
			side = if reads then -long elseif rng:NextNumber() < 0.5 then long else 0
		else
			side = if reads then (if rng:NextNumber() < 0.5 then long else 0) else -long
		end
		memory.Ways[index] = {
			Side = side,
			At = rng:NextNumber(6, lerp(25, 55, skill)) - bot:Reaction() * 10,
			Late = rng:NextNumber() < (1 - skill) * 0.3,
		}
	end
	for key, way in memory.Ways do
		local junction = course.Tiles[key]
		local before = rider.Tile < key or (rider.Tile == key and rider.B == 1 and rider.S < (junction.SplitS or 0))
		if way.Side == 0 or way.Done then
			continue
		end
		if before then
			if not way.Late and key == index and away <= way.At then
				want = way.Side
			end
		elseif rider.Tile == key and rider.S < (junction.SplitS or 0) + 12 then
			want = way.Side -- (held on past the switch; a late bot only presses now)
		else
			way.Done = true
		end
	end

	-- Bends: lean into each half (or not, or the wrong way), from a little before it starts.
	if want == 0 then
		for k, feature in tile.Features do
			if feature.K ~= "Lean" or feature.B ~= rider.B then
				continue
			end
			local key = `{rider.Tile}:{k}`
			local plan = memory.Leans[key]
			if plan == nil then
				local roll = rng:NextNumber()
				local dir = if roll < lerp(0.3, 0.92, skill)
					then feature.Dir
					elseif roll < lerp(0.3, 0.92, skill) + (1 - skill) * 0.35 then -feature.Dir
					else 0
				plan = { Dir = dir, Lead = lerp(-6, 4, skill) + rng:NextNumber(-2, 2) }
				memory.Leans[key] = plan
			end
			if rider.S >= feature.S - plan.Lead and rider.S <= feature.S1 - 1 then
				want = plan.Dir
			end
		end
	end
	setLean(bot, ctx, memory, want)

	-- Gaps: time the jump to be up over the whole gap.
	local function gapAhead(t, extra: number)
		for _, feature in t.Features do
			if feature.K == "Gap" then
				local front = feature.S - Track.HALF_BASE - (rider.S - extra)
				if front > 0 then
					return feature, front
				end
			end
		end
		return nil, 0
	end
	local feature, front = gapAhead(tile, 0)
	local gapTile = rider.Tile
	if not feature then
		local nextTile = course.Tiles[rider.Tile + 1]
		local path = tile.Paths[rider.B] or tile.Paths[1]
		if nextTile then
			feature, front = gapAhead(nextTile, path.Total)
			gapTile = rider.Tile + 1
		end
	end
	if feature and rider.V > 1 then
		local key = gapTile
		local plan = memory.Jumps[key]
		if plan == nil then
			local gap = (feature.S1 :: number) - feature.S
			local roll = rng:NextNumber()
			local lead -- seconds before the front wheels reach the gap
			if roll < lerp(0.6, 0.97, skill) then
				-- (the middle of the jump over the middle of the gap, off by a little)
				local v = math.max(rider.V, 10)
				lead = Track.JUMP_TIME / 2 - (gap + Track.WHEELBASE) / (2 * v)
				lead += rng:NextNumber(-1, 1) * (1 - skill) * 0.22
			elseif roll < 0.8 + skill * 0.15 then
				-- far too early (before a press would be held): down before the gap
				local v = math.max(rider.V, 10)
				lead = Track.JUMP_TIME / 2 - (gap + Track.WHEELBASE) / (2 * v) + Track.HOLD + rng:NextNumber(0.3, 0.6)
			else
				lead = -1 -- doesn't jump
			end
			plan = { Lead = lead, Set = false }
			memory.Jumps[key] = plan
		end
		local seconds = front / rider.V
		if not plan.Set and plan.Lead > 0 and seconds <= plan.Lead + 0.3 then
			plan.Set = true
			ctx:Delay(math.max(0, seconds - plan.Lead), function()
				if not mode.ending then
					ctx:BotAction(bot, "Jump", ctx:Now())
				end
			end)
		end
	end
end

return Brain

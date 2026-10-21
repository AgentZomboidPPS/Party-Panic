-- How bots play Sinking Sands (the contract is in Bots/Default.luau).
--
-- Divers chase the best treasure they can reach and keep out of the sinkhole; Sand Kings SWIRL and
-- PULL to sink the treasure before the Divers get it. Reaction time and Skill keep them beatable.
-- The sand's drag on bots is applied by the mode itself (SinkingSands:_dragBots).
--
-- Owner, after a round the Sand Kings won 145 to 52 with the five diver bots on 3, 2, 0, 4 and 0
-- (the owner had 43): "Bots are terrible at this game. can we make them a little better." Most of
-- that was the bots' legs, not their heads: in a real game the sand moved them every frame and
-- their walk kept stopping, so they slid into the hole (the fix is in SinkingSands:_dragBots). On
-- top of that this pass makes them play the way a decent player does, some better than others:
--
-- DIVERS notice each treasure a moment after its landing marker appears: sooner when they're
-- skilled, later when it's far off or behind them. A Diver works out the earliest moment it can
-- meet the treasure on its spiral (the same flow every screen draws it on) and runs there: to the
-- landing spot, or across the treasure's path as the sand carries it in, steering straight at it
-- once it's close. It goes for what's worth most per second of running and leaves a treasure to a
-- Diver who stands clearly nearer to it, so they don't all chase one coin (judged by where the
-- others stand, the way a player sees it, bots and people alike). A SWIRL or a PULL changes the
-- flow: a Diver takes it in a reaction time after the King presses it and only then re-aims, so a
-- SWIRL can still whip treasure away from it. Divers keep out of the hole the way a player does:
-- they walk round it, not across it, grab treasure sliding past the edge from the edge (a grab
-- reaches), back out of the funnel while a PULL drains it (sloppy ones sometimes miss the alarm)
-- and run outward when the sand has them near the lip, the good ones hopping as they go (the sand
-- drags less in the air). Now and then a sloppy one follows a coin in. With nothing to chase, a
-- Diver waits on its own ring of the middle of the slope (good ones nearer the hole, where all
-- the treasure slides past), a few steps from the next Diver. Skill shows in all of it: in
-- simulated 12-player rounds good bots (Skill 0.7-0.9) haul about 23 and average ones
-- (0.35-0.55) about 13. (Before this pass it was the other way round: Skill only made a bot more
-- timid, so the sloppiest bots, diving deepest, hauled the most.)
-- SAND KINGS watch the sand: PULL when there's treasure to sink or a Diver strays deep (on top of
-- another King's PULL once that one has bitten: two drain harder than one), SWIRL when Divers are
-- closing in on treasure (once they're on it, it's too late). They do better than a King who
-- just presses both buttons whenever they're ready.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SandSwirl = require(ReplicatedStorage.Shared.Logic.SandSwirl)

local Brain = {}

local WALK = 16 -- a Diver's run (studs/s)
local LOOK = 2.6 -- how far ahead a Diver looks for where it can meet a treasure (seconds)
local STEP = 0.1 -- between the moments it checks
local SLACK = 1.5 -- a meeting is planned this close to the treasure (a grab reaches 3.4 or more)
local CLOSE = 7 -- nearer than this, a Diver steers straight at the treasure
local PULL_LENGTH = 2.45 -- a PULL drains this long from its start (SandSwirl.PullEnvelope)
local ROOM = 6 -- a waiting Diver keeps this far from the next one
local FAR = WALK * LOOK + 30 -- treasure further off than this can't be met within LOOK
-- How a Diver's Skill shows (each pair goes from Skill 0 to Skill 1):
local NOTICE = { 1.3, 0.2 } -- seconds before it notices a new landing marker...
local NOTICE_FAR = 60 -- ...and one more for every this many studs away
local BEHIND = 0.5 -- ...and this much more when it's behind the bot
local RING = { 20, 14 } -- radius it waits at for treasure (all of it slides past, nearer the hole)
local SAFE = { 6, 3 } -- meeting treasure this close to the hole's edge is a risk it rarely takes
local DANGER = { 2.5, 2 } -- this close to the hole's edge, it turns and runs out
local THROWN = 1.6 -- a SWIRL or PULL throws it for this many reaction times before it re-aims
local CARELESS = 0.3 -- chance (at Skill 0) that it chases its pick with its eyes only on the treasure...
local CUT = -2 -- ...noticing the hole only this far from its edge (inside it: following a coin in)
-- And a Sand King's:
local KING_LOOK = 0.4 -- it looks over the sand every this many reaction times (and a moment)
local KING_PULL = { 0.5, 1 } -- chance it PULLs (when ready) with treasure to sink or a Diver deep...
local PULL_WORTH = 2 -- ...this many coins' worth on the sand, at least
local PULL_GAP = 0.8 -- it lets another King's PULL bite this long before PULLing on top of it
local KING_SWIRL = { 0.5, 1 } -- chance it SWIRLs (when ready) with Divers closing in on treasure

local function flat(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function bySkill(range: { number }, skill: number): number
	return range[1] + (range[2] - range[1]) * skill
end

-- Sand Kings ------------------------------------------------------------------------------------

local function kingStep(bot, ctx, mode)
	local memory = bot.Memory
	local skill = bot.Skill
	local clock = os.clock()
	if clock < (memory.Think or 0) then
		return
	end
	memory.Think = clock + bot:Reaction() * KING_LOOK + bot.Rng:NextNumber(0.1, 0.3)
	local now = ctx:Now()
	local center = mode.center

	local divers = {}
	local deep = 0
	for _, player in ctx:GetAlivePlayers() do
		if mode:IsKing(player) or mode:IsGulped(player) then
			continue
		end
		local _, _, root = ctx:GetCharacter(player)
		if root then
			table.insert(divers, root.Position)
			if flat(root.Position, center) < 11 then
				deep += 1
			end
		end
	end
	-- What's on the sand (or about to land): treasure a Diver is closing in on, which a SWIRL can
	-- whip away (one they're touching is already lost), and treasure nobody is near, which a PULL
	-- sinks before anyone gets there.
	local chased, loose = 0, 0
	for _, item in mode.items do
		if item.T - now > 0.6 then
			continue
		end
		local spot = mode:ItemPosition(item, math.max(now, item.T))
		local nearest = math.huge
		for _, position in divers do
			nearest = math.min(nearest, flat(position, spot))
		end
		local value = mode.Kinds[item.Kind].Value
		if nearest >= 13 then
			loose += value
		elseif nearest >= 4 then
			chased += value
		end
	end
	local effects = mode.effects
	local lastPull = if effects and #effects.Pulls > 0 then effects.Pulls[#effects.Pulls] else -math.huge
	local fresh = now < lastPull + PULL_GAP -- (a PULL that's only just biting: let it work first)

	local swirlCool, pullCool = mode:Cooldowns()
	if clock >= (memory.PullReady or 0) and not fresh then
		local want = if loose + chased >= PULL_WORTH or deep > 0 then bySkill(KING_PULL, skill) else 0.04
		if bot:Chance(want) then
			memory.PullReady = clock + pullCool + 0.1
			ctx:BotAction(bot, "Pull")
			return
		end
	end
	if clock >= (memory.SwirlReady or 0) then
		local want = if chased >= 3
			then bySkill(KING_SWIRL, skill)
			elseif chased > 0 then bySkill(KING_SWIRL, skill) * 0.6
			else 0.05
		if bot:Chance(want) then
			memory.SwirlReady = clock + swirlCool + 0.1
			ctx:BotAction(bot, "Swirl")
		end
	end
end

-- Divers -----------------------------------------------------------------------------------------

-- The earliest moment (within LOOK) a Diver at `from`, setting off at `start` at `speed`, can be
-- within SLACK of a treasure riding the sand: that moment, the treasure's spot then and its radius.
-- Nil when the treasure sinks first or runs away. (The treasure is carried along step by step on
-- the flow every screen draws it on.)
local function meet(mode, item, from: Vector3, start: number, now: number, speed: number): (number?, Vector3?, number?)
	local kind = mode.Kinds[item.Kind]
	local t = math.max(start, item.T)
	local r, a, sunk = mode:ItemPolar(item, t)
	local horizon = now + LOOK
	while not sunk do
		local x, z = SandSwirl.ToXZ(r, a)
		local spot = mode.center + Vector3.new(x, SandSwirl.Height(r), z)
		if flat(spot, from) - SLACK <= speed * (t - start) then
			return t, spot, r
		end
		if t + STEP > horizon then
			break
		end
		r, a, sunk = SandSwirl.Advance(mode.segments, r, a, t, t + STEP, kind.Factor, SandSwirl.TREASURE_DRAIN)
		t += STEP
	end
	return nil, nil, nil
end

-- Where the other Divers on the sand stand (bots and people alike: what anyone can see).
local function rivals(ctx, mode, bot): { Vector3 }
	local list = {}
	for _, player in ctx:GetAlivePlayers() do
		if player == bot or mode:IsKing(player) or mode:IsGulped(player) then
			continue
		end
		local _, _, root = ctx:GetCharacter(player)
		if root then
			table.insert(list, root.Position)
		end
	end
	return list
end

-- What a treasure is worth to this Diver: value per second of running, less when meeting it means
-- going deep or another Diver stands clearly nearer. Also when and where they'd meet.
local function appraise(bot, mode, item, position: Vector3, now: number, start: number, others, floor: number)
	local memory = bot.Memory
	local skill = bot.Skill
	local t, spot, r = meet(mode, item, position, start, now, WALK * (0.9 + 0.08 * skill))
	if not t or not spot or not r then
		return nil, nil, nil
	end
	if r < floor then
		return nil, nil, nil -- on the lip, or too deep while a PULL drains the funnel
	end
	local worth = mode.Kinds[item.Kind].Value / (t - now + 0.7)
	if r < memory.Safe then
		worth *= if memory.Greedy then 0.7 else 0.25
	end
	for _, other in others do
		if now + math.max(0, flat(other, spot) - SLACK) / WALK < t - 0.25 then
			worth *= 0.6 - 0.35 * skill -- they'll likely get there first
		end
	end
	return worth, t, spot
end

-- Chooses what to chase (or nothing): the best treasure this Diver has noticed.
local function pick(bot, ctx, mode, position: Vector3, now: number, clock: number, floor: number)
	local memory = bot.Memory
	local others = rivals(ctx, mode, bot)
	local best, bestWorth, bestT, bestSpot = nil, 0, nil, nil
	local nearest, nearestDistance, nearestT, nearestSpot = nil, math.huge, nil, nil
	local hope, hopeDistance = nil, math.huge
	for id, item in mode.items do
		local noticed = memory.Seen[id]
		if not noticed or clock < noticed then
			continue
		end
		local here = mode:ItemPosition(item, math.max(now, item.T))
		local distance = flat(here, position)
		if distance > FAR then
			continue
		end
		local mine = id == memory.Target
		local worth, t, spot = appraise(bot, mode, item, position, now, if mine then now else now + 0.1, others, floor)
		if not worth or not spot then
			if distance < hopeDistance and flat(here, mode.center) > math.max(floor, memory.Safe) + 1 then
				hope, hopeDistance = id, distance
			end
			continue
		end
		if mine then
			worth *= 1.3 -- no flip-flopping between two equally good coins
		end
		if worth > bestWorth then
			best, bestWorth, bestT, bestSpot = id, worth, t, spot
		end
		local away = flat(spot, position)
		if away < nearestDistance then
			nearest, nearestDistance, nearestT, nearestSpot = id, away, t, spot
		end
	end
	-- Sloppy bots sometimes just run for whatever is nearest, the way people do.
	if nearest and nearest ~= best and bot:Chance(0.2 * (1 - bot.Skill)) then
		best, bestT, bestSpot = nearest, nearestT, nearestSpot
	end
	memory.Target, memory.Eta, memory.Aim, memory.Chase = best, bestT, bestSpot, false
	if not best and hope then
		-- Nothing it can be sure of reaching: like a player, it runs for the nearest treasure anyway
		-- (the sand may bring it round), as long as that isn't taking it into the hole.
		local item = mode.items[hope]
		memory.Target, memory.Chase = hope, true
		memory.Aim = mode:ItemPosition(item, math.max(now, item.T))
	end
	memory.AimAt = clock + 0.12 + 0.4 * (1 - bot.Skill)
end

-- Where to head for `aim` without going into the hole: round it, never across (SandSwirl.Detour).
local function steer(center: Vector3, position: Vector3, aim: Vector3, keepOut: number): Vector3
	local x, z =
		SandSwirl.Detour(position.X - center.X, position.Z - center.Z, aim.X - center.X, aim.Z - center.Z, keepOut)
	return center + Vector3.new(x, SandSwirl.Height(math.sqrt(x * x + z * z)), z)
end

-- Where to wait with nothing to chase: on this bot's own ring of the slope, where it is (further out
-- while it's backing away from the hole), edging round the ring away from a Diver standing close.
local function waitSpot(bot, ctx, mode, position: Vector3, outward: Vector3, danger: number): Vector3
	local spot = mode.center + outward * math.max(bot.Memory.Ring, danger + 1.5)
	local nearest, gap = nil, ROOM
	for _, other in rivals(ctx, mode, bot) do
		local distance = flat(other, position)
		if distance < gap then
			nearest, gap = other, distance
		end
	end
	if nearest then
		local side = Vector3.new(-outward.Z, 0, outward.X)
		spot += (if (position - nearest):Dot(side) >= 0 then side else -side) * (ROOM - gap)
	end
	return spot
end

local function diverStep(bot, ctx, mode)
	local root = bot:Root()
	if not root then
		return
	end
	local memory = bot.Memory
	local skill = bot.Skill
	local clock = os.clock()
	local now = ctx:Now()
	local center = mode.center
	local position = root.Position
	local offset = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	local r = offset.Magnitude
	local outward = if r > 0.01 then offset / r else Vector3.new(1, 0, 0)
	if not memory.Seen then
		memory.Seen = {}
		memory.Greedy = bot:Chance(0.4 * (1 - skill))
		local greed = if memory.Greedy then 1.5 else 0
		memory.Safe = SandSwirl.HOLE + bySkill(SAFE, skill) - greed
		memory.Danger = SandSwirl.HOLE + bySkill(DANGER, skill) - greed * 0.5
		memory.Ring = bySkill(RING, skill) + bot.Rng:NextNumber(-1.5, 1.5)
	end

	-- Treasure is noticed a moment after its marker appears (later when it's far off or behind the
	-- bot, as for a player looking the other way); the Kings' powers a reaction time after they're
	-- pressed (until then the bot keeps running where it was going).
	local facing = root.CFrame.LookVector
	for id, item in mode.items do
		if not memory.Seen[id] then
			local x, z = SandSwirl.ToXZ(item.R, item.A)
			local toward = Vector3.new(center.X + x - position.X, 0, center.Z + z - position.Z)
			local distance = toward.Magnitude
			local behind = distance > 4 and toward:Dot(facing) < -0.3 * distance
			memory.Seen[id] = clock
				+ (bySkill(NOTICE, skill) + distance / NOTICE_FAR + (if behind then BEHIND else 0))
					* bot.Rng:NextNumber(0.8, 1.3)
		end
	end
	local effects = mode.effects
	if effects then
		local surges, pulls = #effects.Surges, #effects.Pulls
		if surges ~= (memory.Surges or 0) or pulls ~= (memory.Pulls or 0) then
			-- (the spin flipping or the sand rushing throws a player for a little longer than a plain
			-- reaction: SWIRL! flashes up, the treasure whips off; a second power while they're
			-- still taking in the first doesn't throw them for longer)
			local reaction = bot:Reaction()
			if clock >= (memory.Hold or 0) then
				memory.Hold = clock + reaction * THROWN
			end
			-- (a sloppy bot sometimes misses the PULL alarm altogether)
			if pulls ~= (memory.Pulls or 0) and not bot:Chance(0.35 * (1 - skill)) then
				memory.PullSeen = clock + reaction * 0.8
				memory.PullEnd = (effects.Pulls[pulls] or now) + PULL_LENGTH
			end
			memory.Surges, memory.Pulls = surges, pulls
		end
	end
	local pulling = memory.PullSeen ~= nil and clock >= memory.PullSeen and now <= memory.PullEnd
	local holding = clock < (memory.Hold or 0)

	-- Near the hole (or deep in the funnel during a PULL): run out, hopping if this bot knows the
	-- trick. Sloppy bots notice a moment late.
	local item = memory.Target and mode.items[memory.Target]
	local danger = memory.Danger
	if pulling then
		danger = math.max(danger, memory.Safe + 1 + skill)
	end
	-- (a careless moment: eyes on the treasure, not on the edge)
	if r < (if memory.Careless and item then SandSwirl.HOLE + CUT else danger) then
		memory.Alarm = memory.Alarm or clock + (1 - skill) * bot.Rng:NextNumber(0.05, 0.45)
		if clock >= memory.Alarm then
			memory.Target, memory.Eta, memory.Aim = nil, nil, nil
			bot:MoveTo(center + outward * (r + 10))
			local inward = SandSwirl.WalkerFlow(mode.segments, r, now)
			if inward > 3 and bot:Chance(0.2 + 0.6 * skill) then
				bot:Jump()
			end
			return
		end
	else
		memory.Alarm = nil
	end

	-- Choose again every so often, as soon as the treasure is gone, and once a power has been seen.
	if not holding and (clock >= (memory.PickAt or 0) or not item or memory.Hold) then
		memory.PickAt = clock + (0.3 + 0.4 * (1 - skill)) * bot.Rng:NextNumber(0.8, 1.25)
		memory.Hold = nil
		memory.Careless = bot:Chance(CARELESS * (1 - skill))
		pick(bot, ctx, mode, position, now, clock, if pulling then danger + 1 else SandSwirl.HOLE + 1.5)
		item = memory.Target and mode.items[memory.Target]
	end

	if item then
		if not holding then
			local distance = flat(mode:ItemPosition(item, now), position)
			if now >= item.T and distance < CLOSE then
				-- Close: steer straight at it, where it will be a moment from now.
				local lead = math.min(0.3, distance / WALK) * (0.4 + 0.6 * skill)
				memory.Aim = mode:ItemPosition(item, now + lead)
			elseif clock >= (memory.AimAt or 0) then
				-- Further off: look again every so often (sooner for skilled bots).
				memory.AimAt = clock + 0.12 + 0.4 * (1 - skill)
				if memory.Chase then
					memory.Aim = mode:ItemPosition(item, math.max(now, item.T) + 0.3 * skill)
				else
					local t, spot = meet(mode, item, position, now, now, WALK * (0.9 + 0.08 * skill))
					if t then
						memory.Eta, memory.Aim = t, spot
					else
						memory.Target, memory.PickAt = nil, 0 -- it got away: choose again
					end
				end
			end
		end
		if memory.Aim then
			-- (a careless moment: straight there, even across the lip)
			local keepOut = if memory.Careless then SandSwirl.HOLE + CUT else danger + 0.5
			bot:MoveTo(steer(center, position, memory.Aim, keepOut))
		end
	else
		bot:MoveTo(steer(center, position, waitSpot(bot, ctx, mode, position, outward, danger), danger + 0.5))
		if bot:Chance(0.006) then
			bot:Jump()
		end
	end
end

function Brain.Step(bot, ctx, mode, _dt)
	if mode:IsKing(bot) then
		kingStep(bot, ctx, mode)
	elseif mode:IsGulped(bot) then
		bot:Stop()
	else
		diverStep(bot, ctx, mode)
	end
end

return Brain

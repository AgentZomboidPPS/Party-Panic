-- How bots play Sinking Sands (contract in Bots/Default.luau).
--
-- Divers chase the best treasure they can reach: worth more, closer, and not too near the sinkhole
-- (careful bots keep further from it; sloppy ones get greedy and sometimes slip in). They aim where
-- the treasure will be when they get there and lean outward against the pull. When the sand drags
-- them towards the hole they turn and run out, and good bots hop (the sand can't drag you in the air).
-- Sand Kings watch the Divers: SWIRL when one is about to grab something, PULL when Divers stray
-- deep into the funnel or a rich prize nears the hole. Reaction time and Skill keep them beatable.
-- The sand's drag on bots is applied by the mode itself (SinkingSands:_dragBots).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SandSwirl = require(ReplicatedStorage.Shared.Logic.SandSwirl)

local Brain = {}

local WALK = 16

local function flat(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function kingStep(bot, ctx, mode)
	local memory = bot.Memory
	local clock = os.clock()
	if clock < (memory.Think or 0) then
		return
	end
	memory.Think = clock + bot:Reaction() + bot.Rng:NextNumber(0.2, 0.6)
	local now = ctx:Now()
	local center = mode.center

	-- Who is about to grab something, and who has strayed deep into the funnel.
	local close, deep, richNearHole = 0, 0, false
	for _, item in mode.items do
		if now < item.T then
			continue
		end
		local r = mode:ItemPolar(item, now)
		if item.Kind >= 3 and r < 13 then
			richNearHole = true
		end
	end
	for _, player in ctx:GetAlivePlayers() do
		if mode:IsKing(player) or mode:IsGulped(player) then
			continue
		end
		local _, _, root = ctx:GetCharacter(player)
		if not root then
			continue
		end
		local r = flat(root.Position, center)
		if r < 15 then
			deep += 1
		end
		for _, item in mode.items do
			if now >= item.T and flat(mode:ItemPosition(item, now), root.Position) < 5 then
				close += 1
				break
			end
		end
	end

	if clock >= (memory.SwirlReady or 0) then
		local want = if close > 0 then 0.3 + bot.Skill * 0.5 else 0.06
		if bot:Chance(want) then
			memory.SwirlReady = clock + 3.1
			ctx:BotAction(bot, "Swirl")
			return
		end
	end
	if clock >= (memory.PullReady or 0) then
		local want = if deep > 0 or richNearHole then 0.2 + bot.Skill * 0.45 else 0.04
		if bot:Chance(want) then
			memory.PullReady = clock + 5.1
			ctx:BotAction(bot, "Pull")
		end
	end
end

local function diverStep(bot, ctx, mode)
	local root = bot:Root()
	if not root then
		return
	end
	local memory = bot.Memory
	local clock = os.clock()
	local now = ctx:Now()
	local center = mode.center
	local position = root.Position
	local offset = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	local r = offset.Magnitude
	local outward = if r > 0.01 then offset / r else Vector3.new(1, 0, 0)

	-- Too close to the hole: run out (and hop, if this bot knows the trick).
	local panic = SandSwirl.HOLE + 2 + bot.Skill * 2.5
	if r < panic then
		memory.Target = nil
		bot:MoveTo(center + outward * (r + 10))
		if bot:Chance(0.15 + bot.Skill * 0.35) then
			bot:Jump()
		end
		return
	end

	-- Pick a treasure every so often (quicker bots re-think sooner).
	local safe = SandSwirl.HOLE + 3 + bot.Skill * 3.5
	local greedy = memory.Greedy
	if greedy == nil then
		greedy = bot:Chance(0.45 * (1 - bot.Skill))
		memory.Greedy = greedy
	end
	if clock >= (memory.Rethink or 0) or not (memory.Target and mode.items[memory.Target]) then
		memory.Rethink = clock + bot:Reaction() + 0.5
		local best, bestScore = nil, -math.huge
		for id, item in mode.items do
			if item.T - now > 0.6 then
				continue
			end
			local spot = mode:ItemPosition(item, math.max(now, item.T))
			local distance = flat(spot, position)
			local later = mode:ItemPosition(item, math.max(now, item.T) + distance / WALK)
			local itemR = flat(later, center)
			local value = mode.Kinds[item.Kind].Value
			local score = value / (distance + 6)
			if itemR < safe and not greedy then
				score -= 1
			end
			-- Some bots fixate on the coin nearest them, the way people do.
			if bot.Rng:NextNumber() < 0.15 then
				score += 0.05
			end
			if score > bestScore then
				best, bestScore = id, score
			end
		end
		memory.Target = best
	end

	local item = memory.Target and mode.items[memory.Target]
	if item then
		local distance = flat(mode:ItemPosition(item, now), position)
		local lead = math.min(1.5, distance / WALK) * (0.4 + bot.Skill * 0.6)
		local aim = mode:ItemPosition(item, now + lead)
		-- Lean outward against the pull, more for better bots.
		bot:MoveTo(aim + outward * (0.6 + bot.Skill * 1.4))
	else
		-- Nothing worth chasing: wait on the gentle outer slope.
		memory.Home = memory.Home or (center + outward * bot.Rng:NextNumber(22, 30))
		bot:MoveTo(memory.Home)
	end
	if bot:Chance(0.012) then
		bot:Jump()
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

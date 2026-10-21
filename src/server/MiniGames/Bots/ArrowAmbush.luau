-- How bots play Arrow Ambush (owner: "we need bots in the mini games"; the contract is in
-- Bots/Default.luau). Bots are judged by the same server code as players: an arrow lands, the
-- server measures everyone's distance to it, and a board in the way stops it for everyone.
--
-- ARCHER bots wait out their cooldown plus their reaction time, then pick a runner: one they
-- can see (no board in the way, checked with the mode's own flight plan), nearer ones first,
-- sticking with a target for a few shots. They aim where the runner is heading (skilled bots lead
-- more accurately) with an error that shrinks with skill, so good runners can beat them.
--
-- RUNNER bots watch the arrows in the air. An arrow they notice (sooner and more often with
-- skill) coming down near them makes them dash away from the landing ring. Otherwise they hide
-- behind a target board (on its far side from the tower, following it as it rolls), spreading
-- out over the boards, or wander the courtyard; now and then they hop.

local ArrowAmbushBrain = {}

local DANGER = 1.9 -- extra studs around an arrow's hit radius a bot treats as dangerous
local DASH = 7.5 -- how far a dodge goes
local HIDE_BEHIND = 2.8 -- how far behind a board's face a hiding bot stands

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function clampToCourtyard(mode, point: Vector3): Vector3
	local origin = mode.origin
	return Vector3.new(
		math.clamp(point.X, origin.X - 23, origin.X + 23),
		mode.floorY + 3,
		math.clamp(point.Z, origin.Z - 13, origin.Z + 23)
	)
end

-- Archers -----------------------------------------------------------------------------------------

local function pickTarget(bot, ctx, mode, from: Vector3, now: number)
	local memory = bot.Memory
	local best, bestScore, bestAim = nil, -math.huge, nil
	for _, runner in ctx:GetAlivePlayers() do
		if mode.role[runner] ~= "Runner" or mode.tagged[runner] then
			continue
		end
		local seen = mode.track[runner]
		if not seen then
			continue
		end
		local distance = (flat(seen.Pos) - flat(from)).Magnitude
		local flight = mode.Flight(distance + 16)
		-- Lead: skilled bots aim most of the way to where the runner will be.
		local lead = math.clamp(bot.Skill * 1.1, 0.3, 0.95)
		local aim = flat(seen.Pos) + seen.Vel * flight * lead
		aim = Vector3.new(aim.X, mode.floorY, aim.Z)
		local _, arc = mode.Flight((aim - from).Magnitude)
		local blocked = mode:_firstBoard(from, aim, now, flight, arc)
		local score = -distance * 0.05 + bot.Rng:NextNumber(0, 1.2)
		if blocked then
			score -= 2.5 * bot.Skill + 0.5
		end
		if runner == memory.Target then
			score += 1.2
		end
		if score > bestScore then
			best, bestScore, bestAim = runner, score, aim
		end
	end
	return best, bestAim
end

local function archerStep(bot, ctx, mode)
	local root = bot:Root()
	if not root then
		return
	end
	local memory = bot.Memory
	local now = ctx:Now()
	if now < (mode.nextShot[bot] or 0) or now < (memory.WaitUntil or 0) then
		return
	end
	local from = root.Position + Vector3.new(0, 1.2, 0)
	local target, aim = pickTarget(bot, ctx, mode, from, now)
	if not target or not aim then
		return
	end
	if memory.Target ~= target then
		memory.Target = target
		memory.WaitUntil = now + bot:Reaction() * 0.6 -- a moment to line up a new target
		return
	end
	local miss = (1 - bot.Skill) * 4.2 + 0.5
	local angle = bot.Rng:NextNumber(0, math.pi * 2)
	local spread = miss * math.sqrt(bot.Rng:NextNumber())
	local x = aim.X + math.cos(angle) * spread
	local z = aim.Z + math.sin(angle) * spread
	ctx:BotAction(bot, "Shoot", x, z)
	memory.WaitUntil = now + mode.COOLDOWN + bot:Reaction() * 0.7 + bot.Rng:NextNumber(0, 0.5) * (1 - bot.Skill)
	if bot:Chance(0.25) then
		memory.Target = nil -- switch it up now and then
	end
end

-- Runners -----------------------------------------------------------------------------------------

-- The most urgent arrow this bot has noticed that will come down near `position`.
local function threat(bot, mode, position: Vector3, now: number)
	local memory = bot.Memory
	memory.Noticed = memory.Noticed or {}
	local worst, soonest = nil, math.huge
	for _, arrow in mode.arrows do
		if arrow.Board ~= 0 or arrow.T1 < now - 0.05 then
			continue
		end
		local notice = memory.Noticed[arrow.Id]
		if notice == nil then
			-- Whether (and when) this bot notices the arrow, decided once per arrow.
			notice = if bot:Chance(0.45 + bot.Skill * 0.5) then arrow.T0 + bot:Reaction() else false
			memory.Noticed[arrow.Id] = notice
		end
		if notice == false or now < notice then
			continue
		end
		local distance = (flat(position) - flat(arrow.To)).Magnitude
		if distance <= mode.HIT_RADIUS + DANGER and arrow.T1 < soonest then
			worst, soonest = arrow, arrow.T1
		end
	end
	return worst
end

local function coverSpot(mode, index: number, now: number, side: number): Vector3
	local board = mode.boards[index]
	local x = mode.origin.X + mode.BoardX(board, mode.boardsT0, now + 0.4)
	return Vector3.new(x + side, mode.floorY + 3, mode.origin.Z + board.Z + HIDE_BEHIND)
end

local function pickCover(bot, ctx, mode, position: Vector3, now: number): number?
	local claims = {}
	for _, other in ctx:GetAlivePlayers() do
		local memory = (other :: any).Memory
		if other ~= bot and type(memory) == "table" and memory.Board then
			claims[memory.Board] = (claims[memory.Board] or 0) + 1
		end
	end
	local best, bestScore = nil, math.huge
	for index in mode.boards do
		local spot = coverSpot(mode, index, now, 0)
		local score = (flat(spot) - flat(position)).Magnitude + (claims[index] or 0) * 9 + bot.Rng:NextNumber(0, 6)
		if score < bestScore then
			best, bestScore = index, score
		end
	end
	return best
end

local function runnerStep(bot, ctx, mode)
	local root = bot:Root()
	if not root then
		return
	end
	local memory = bot.Memory
	local now = ctx:Now()
	local position = root.Position

	-- Dodging comes first.
	if memory.Dodge and now < memory.DodgeUntil then
		bot:MoveTo(memory.Dodge)
		return
	end
	memory.Dodge = nil
	local arrow = threat(bot, mode, position, now)
	if arrow then
		local away = flat(position) - flat(arrow.To)
		away = if away.Magnitude > 0.2 then away.Unit else Vector3.new(bot.Rng:NextNumber(-1, 1), 0, 1).Unit
		local turn = math.rad(bot.Rng:NextNumber(-40, 40))
		away = CFrame.Angles(0, turn, 0):VectorToWorldSpace(away)
		local spot = clampToCourtyard(mode, position + away * DASH)
		if (flat(spot) - flat(arrow.To)).Magnitude < mode.HIT_RADIUS + 1 then
			spot = clampToCourtyard(mode, position - away * DASH) -- cornered: cut back the other way
		end
		memory.Dodge = spot
		memory.DodgeUntil = arrow.T1 + 0.25
		memory.Board = nil
		bot:MoveTo(spot)
		if bot:Chance(0.2) then
			bot:Jump()
		end
		return
	end

	-- Otherwise hide behind a board or roam.
	if not memory.PlanUntil or now >= memory.PlanUntil then
		memory.PlanUntil = now + bot.Rng:NextNumber(1.8, 4.5)
		memory.Side = bot.Rng:NextNumber(-1.6, 1.6)
		if #mode.boards > 0 and bot:Chance(0.35 + bot.Skill * 0.55) then
			memory.Board = pickCover(bot, ctx, mode, position, now)
			memory.Roam = nil
		else
			memory.Board = nil
			memory.Roam = clampToCourtyard(
				mode,
				mode.origin + Vector3.new(bot.Rng:NextNumber(-22, 22), 0, bot.Rng:NextNumber(-10, 22))
			)
		end
	end
	if memory.Board and mode.boards[memory.Board] then
		bot:MoveTo(clampToCourtyard(mode, coverSpot(mode, memory.Board, now, memory.Side or 0)))
	elseif memory.Roam then
		bot:MoveTo(memory.Roam)
	end
	if bot:Chance(0.012) then
		bot:Jump()
	end
end

function ArrowAmbushBrain.Step(bot, ctx, mode, _dt)
	local role = mode.role and mode.role[bot]
	if role == "Archer" then
		archerStep(bot, ctx, mode)
	elseif role == "Runner" and not mode.tagged[bot] then
		runnerStep(bot, ctx, mode)
	end
end

return ArrowAmbushBrain

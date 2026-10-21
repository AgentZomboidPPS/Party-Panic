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
--
-- Bug pass (owner: "it just has to work"): the boards are only on players' screens (each client
-- rolls its own copy, and players bump into it), so nothing on the server stopped a bot, and bots
-- walked straight through boards about every three seconds. Runner bots now go round a board in
-- their way, by its nearer end, the way a player has to.

local ArrowAmbushBrain = {}

local DANGER = 1.9 -- extra studs around an arrow's hit radius a bot treats as dangerous
local DASH = 7.5 -- how far a dodge goes
local HIDE_BEHIND = 2.8 -- how far behind a board's face a hiding bot stands
-- A board in the way: a body's middle stays BOARD_REACH from a board's middle along its line (the
-- frame is 3.78 either side, a body about 1) unless it's BOARD_DEPTH in front of or behind the line
-- (the cart under the frame is 1.25 either side); round an end, a bot aims ROUND past the corner.
local BOARD_REACH = 4.8
local BOARD_DEPTH = 1.6
local ROUND = 0.8
local WALK = 16 -- how fast bots walk (studs a second), to know where a board will be when they get there

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The first board a straight walk from `from` to `goal` would run into, and when.
local function boardInWay(mode, from: Vector3, goal: Vector3, now: number): (number?, number?)
	local origin = mode.origin
	local offset = flat(goal) - flat(from)
	local length = offset.Magnitude
	local steps = math.max(1, math.ceil(length))
	for step = 0, steps do
		local s = step / steps
		local point = from + offset * s
		local t = now + length * s / WALK
		for index, board in mode.boards do
			if math.abs(point.Z - (origin.Z + board.Z)) < BOARD_DEPTH then
				local x = origin.X + mode.BoardX(board, mode.boardsT0, t)
				if math.abs(point.X - x) < BOARD_REACH then
					return index, t
				end
			end
		end
	end
	return nil, nil
end

-- Where to walk to get to `goal` (never on a board's line, see offBoards): straight there, or round
-- the board in the way: along it to the end that makes the shorter way, then across its line there.
-- (That first leg is checked the same way, in case another board is in its way.)
local function steer(mode, from: Vector3, goal: Vector3, now: number, depth: number?): Vector3
	local index, t = boardInWay(mode, from, goal, now)
	if not index or not t then
		return goal
	end
	local origin = mode.origin
	local board = mode.boards[index]
	local z = origin.Z + board.Z
	local x = origin.X + mode.BoardX(board, mode.boardsT0, t)
	-- Clear of its end now and in a moment (the time to cross its line), as it rolls.
	local clear = math.abs(from.X - (origin.X + mode.BoardX(board, mode.boardsT0, now))) >= BOARD_REACH
		and math.abs(from.X - (origin.X + mode.BoardX(board, mode.boardsT0, now + 0.3))) >= BOARD_REACH
	local waypoint
	if math.abs(from.Z - z) < BOARD_DEPTH or clear then
		-- On its line, or clear of its end: across to the goal's side right here.
		local goalSide = if goal.Z >= z then 1 else -1
		waypoint = Vector3.new(from.X, goal.Y, z + goalSide * (BOARD_DEPTH + ROUND))
	else
		local side = if from.Z >= z then 1 else -1 -- the bot's side of the board's line
		local left, right = x - BOARD_REACH - ROUND, x + BOARD_REACH + ROUND
		local function way(endX: number): number
			local wall = if math.abs(endX - origin.X) > 23 then 100 else 0 -- no way round past the wall
			return math.abs(from.X - endX) + math.abs(goal.X - endX) + wall
		end
		local endX = if way(left) <= way(right) then left else right
		waypoint = Vector3.new(endX, goal.Y, z + side * (BOARD_DEPTH + ROUND))
	end
	if (depth or 0) < 2 then
		return steer(mode, from, waypoint, now, (depth or 0) + 1)
	end
	return waypoint
end

-- A spot moved off any board's line (to the nearer side), so a bot never waits where a board rolls.
local function offBoards(mode, point: Vector3): Vector3
	for _, board in mode.boards do
		local z = mode.origin.Z + board.Z
		local off = point.Z - z
		if math.abs(off) < BOARD_DEPTH + ROUND then
			return Vector3.new(point.X, point.Y, z + (if off >= 0 then 1 else -1) * (BOARD_DEPTH + ROUND))
		end
	end
	return point
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

local function pickTarget(bot, ctx, mode, now: number)
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
		local from = mode:ShotFrom(bot, seen.Pos)
		local distance = (flat(seen.Pos) - flat(from)).Magnitude
		local flight = mode.Flight(distance + 16)
		-- Lead: skilled bots aim most of the way to where the runner will be.
		local lead = math.clamp(bot.Skill * 1.1, 0.3, 0.95)
		local aim = flat(seen.Pos) + seen.Vel * flight * lead
		aim = Vector3.new(aim.X, mode.floorY, aim.Z)
		from = mode:ShotFrom(bot, aim) -- the same bow point the server will plan the shot from
		local full, arc = mode.Flight((aim - from).Magnitude)
		local blocked = mode:_firstBoard(from, aim, now, full, arc)
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
	local target, aim = pickTarget(bot, ctx, mode, now)
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
	memory.WaitUntil = now + mode.cooldown + bot:Reaction() * 0.7 + bot.Rng:NextNumber(0, 0.5) * (1 - bot.Skill)
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

-- Hiding spots are spread out: the mode keeps which board each bot is behind (never read off
-- other participants, which may be real Players).
local function pickCover(bot, ctx, mode, position: Vector3, now: number): number?
	local claims = {}
	for other, index in mode.coverClaims do
		if other ~= bot and ctx:IsAlive(other) and not mode.tagged[other] then
			claims[index] = (claims[index] or 0) + 1
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
		bot:MoveTo(steer(mode, position, memory.Dodge, now))
		return
	end
	memory.Dodge = nil
	local arrow = threat(bot, mode, position, now)
	if arrow then
		local away = flat(position) - flat(arrow.To)
		away = if away.Magnitude > 0.2 then away.Unit else Vector3.new(bot.Rng:NextNumber(-1, 1), 0, 1).Unit
		local turn = math.rad(bot.Rng:NextNumber(-40, 40))
		away = CFrame.Angles(0, turn, 0):VectorToWorldSpace(away)
		local spot = offBoards(mode, clampToCourtyard(mode, position + away * DASH))
		if (flat(spot) - flat(arrow.To)).Magnitude < mode.HIT_RADIUS + 1 then
			spot = offBoards(mode, clampToCourtyard(mode, position - away * DASH)) -- cornered: cut back the other way
		end
		memory.Dodge = spot
		memory.DodgeUntil = arrow.T1 + 0.25
		memory.Board = nil
		mode.coverClaims[bot] = nil
		bot:MoveTo(steer(mode, position, spot, now))
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
			mode.coverClaims[bot] = memory.Board
		else
			memory.Board = nil
			mode.coverClaims[bot] = nil
			memory.Roam = offBoards(
				mode,
				clampToCourtyard(
					mode,
					mode.origin + Vector3.new(bot.Rng:NextNumber(-22, 22), 0, bot.Rng:NextNumber(-10, 22))
				)
			)
		end
	end
	if memory.Board and mode.boards[memory.Board] then
		local spot = clampToCourtyard(mode, coverSpot(mode, memory.Board, now, memory.Side or 0))
		bot:MoveTo(steer(mode, position, spot, now))
	elseif memory.Roam then
		bot:MoveTo(steer(mode, position, memory.Roam, now))
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

-- How bots run Obby Odyssey (Shared/Logic/ObbyOdyssey has the course). From the piece it's on, a bot picks
-- a piece in the next row (the one most nearly ahead, spread out a little so they don't all take the same
-- block), walks to the edge facing it and jumps across, or just walks on where the pieces join. The step
-- is every 0.15 s, which is over 2 studs of walking, so a bot walks right up to its take-off spot (the
-- humanoid stops there) and jumps from it: never off the edge by accident, and every take-off is well
-- inside the jump arc. The hazards are read off the same schedule everyone sees:
--   * on the bridge it waits between the balls until walking under the next one would miss it;
--   * on a spinner it jumps as the bar comes round, and walks round the hub;
--   * on the blinking blocks it picks a block that will still be there when it lands, and waits on a
--     solid one when there's none.
-- Skill makes the difference: clumsier bots react later, misjudge the balls and the bars now and then,
-- and sometimes take off too early and splash. Nobody is out in this mode, so a bot that falls just goes
-- back to its checkpoint and tries again. Once at the crown it hops about on the summit.
--
-- Fun pass (owner: "Make sure this is super sick and actually super fun."): bots take the tower's
-- SHORTCUT of tiny pillars now and then (the better ones more often), half of them go for the hop row's
-- launch pad, they keep still while the server flies them off a pad, and they jump the barrels rolling
-- across the pyramid as they come, like the bars.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Course = require(ReplicatedStorage.Shared.Logic.ObbyOdyssey)

local ObbyOdyssey = {}

local TAKE_OFF_IN = 0.6 -- the take-off spot is this far in from the edge
local JUMP_WITHIN = 1.3 -- jump once this close to the take-off spot (it stops there)
local LAND_IN = 2 -- aim this far into the piece it jumps onto
local BALL_CLEAR = Course.Body + 1.3 -- waits this far from a ball's path
local ARRIVED = 1.2 -- this close to a spot it walked to counts as there
-- A blinking block is worth jumping for if it's there from just before the landing until a little after.
local SAFE_FROM, SAFE_TO = 0.25, 1.2

local function flat(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- The point of a piece's top nearest (x, z), `inset` studs inside its edge (course space, flat).
local function nearestOn(piece: Course.Piece, x: number, z: number, inset: number): (number, number)
	if piece.Kind == "Disc" then
		local dx, dz = x - piece.X, z - piece.Z
		local length = math.sqrt(dx * dx + dz * dz)
		local reach = math.max(0, piece.W / 2 - inset)
		if length <= reach or length < 1e-3 then
			return x, z
		end
		return piece.X + dx / length * reach, piece.Z + dz / length * reach
	end
	local halfW = if piece.Kind == "Pipe" then 0.3 else piece.W / 2 - inset -- (on a pipe, keep to its crest)
	local halfD = piece.D / 2 - inset
	return math.clamp(x, piece.X - math.max(halfW, 0), piece.X + math.max(halfW, 0)),
		math.clamp(z, piece.Z - math.max(halfD, 0), piece.Z + math.max(halfD, 0))
end

-- Whether a blinking piece stays solid all through [from, to] (anything else always is).
local function solidThrough(piece: Course.Piece, from: number, to: number): boolean
	if not piece.Blink then
		return true
	end
	local t = from
	while t <= to do
		if not Course.Solid(piece, t) then
			return false
		end
		t += 0.1
	end
	return Course.Solid(piece, to)
end

-- Picks the piece to go for next from `here`.
local function pick(bot, here: Course.Piece, p: Vector3, t: number): Course.Piece?
	local ways = Course.WaysOn(here)
	if #ways == 0 then
		return nil
	end
	local memory = bot.Memory
	local best, bestScore = nil, math.huge
	for _, way in ways do
		local to = way.To
		local score = math.abs(to.X - p.X) * 0.25 + bot.Rng:NextNumber(0, 2.5)
		if memory.Lane then
			score += math.abs(to.X - memory.Lane) * 0.12
		end
		if to.Blink and not solidThrough(to, t + SAFE_FROM, t + SAFE_TO) then
			score += 100
		end
		if to.Shortcut then
			score += if memory.Brave then -8 else 60
		end
		if to.Launch and to.Section == 1 then
			score += if memory.Launchy then -6 else 2
		end
		if score < bestScore then
			best, bestScore = to, score
		end
	end
	return best
end

-- Whether walking on from z along the bridge past `ball`, starting now, stays clear of it, even if the
-- ball comes `margin` seconds early or late.
local function ballClear(ball: Course.Ball, t: number, x: number, feet: number, z: number, margin: number): boolean
	local far = ball.Z + ball.Radius + Course.Body + 0.4
	local tau = 0
	while true do
		local along = z + tau * Course.WalkSpeed
		if along > far then
			return true
		end
		for _, shift in { -margin, 0, margin } do
			if Course.BallHits(ball, t + 0.05 + tau + shift, x, feet, along) then
				return false
			end
		end
		tau += 0.04
	end
end

-- On the bridge: from one gap between the balls to the next, going on only when the next ball will miss.
-- Returns the course-space point to walk to now, or nil to wait where it is.
local function bridgeStep(bot, p: Vector3, feet: number, t: number): (Vector3?, boolean)
	local memory = bot.Memory
	local skill = bot.Skill
	for _, ball in Course.Balls do
		local far = ball.Z + ball.Radius + Course.Body + 0.3
		if p.Z > far then
			continue -- past this one
		end
		local line = ball.Z - ball.Radius - BALL_CLEAR
		-- Up to the waiting line (a walk stops up to half a stud short of where it's going, so anywhere
		-- within ARRIVED of the line counts as there).
		if p.Z < line - ARRIVED then
			return Vector3.new(p.X, feet, line), false
		end
		if p.Z < ball.Z - ball.Radius - Course.Body then
			-- Waiting at the line: go when it's clear (clumsy bots misjudge it now and then).
			if memory.Ball ~= ball.Id then
				memory.Ball = ball.Id
				memory.Rush = bot:Chance(0.22 * (1 - skill) ^ 1.3)
				memory.Look = t + bot:Reaction() * 0.6
			end
			local go = memory.Rush or (t >= memory.Look and ballClear(ball, t, p.X, feet, p.Z, 0.12 + 0.18 * skill))
			if not go then
				return nil, true
			end
		end
		-- Crossing: on to the next line (never past the bridge's end).
		local bridge = Course.Bridge
		return Vector3.new(p.X, feet, math.min(far + 1.6, bridge.Z + bridge.D / 2 - 1.5)), false
	end
	return nil, false
end

function ObbyOdyssey.Step(bot, ctx, mode, _dt)
	local root, humanoid = bot:Root(), bot:Humanoid()
	local runner = mode.runners and mode.runners[bot]
	if not root or not humanoid or not runner or humanoid.PlatformStand or not mode.origin then
		return
	end
	if root.Anchored or runner.Flight then
		return -- flying off a launch pad: the server has it
	end
	local memory = bot.Memory
	local origin = mode.origin
	local p = root.Position - origin
	local feet = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2 - origin.Y
	local t = ctx:Now() - mode.epoch
	local skill = bot.Skill
	memory.Lane = memory.Lane or bot.Rng:NextNumber(-12, 12)
	if memory.Brave == nil then
		memory.Brave = bot:Chance(0.1 + 0.55 * bot.Skill ^ 2) -- the shortcut's tiny pillars
		memory.Launchy = bot:Chance(0.5)
	end
	memory.Side = memory.Side or (if bot:Chance(0.5) then -1 else 1)

	local function walkTo(x: number, y: number, z: number)
		bot:MoveTo(origin + Vector3.new(x, y + 3, z))
	end

	-- At the crown: hop about on the summit.
	if runner.Finish then
		local summit = Course.Summit
		if not memory.Party or t > memory.Party.Until then
			memory.Party = {
				X = summit.X + bot.Rng:NextNumber(-4.5, 4.5),
				Z = summit.Z + bot.Rng:NextNumber(-4.5, 1),
				Until = t + bot.Rng:NextNumber(1.5, 3.5),
			}
		end
		walkTo(memory.Party.X, summit.Top, memory.Party.Z)
		if bot:Chance(0.05) then
			bot:Jump()
		end
		return
	end

	local here = Course.PieceAt(p.X, p.Z, feet, t)
	if not here then
		return -- in the air: keep going where it was going
	end
	if memory.Here ~= here then
		memory.Here = here
		memory.Target = nil
		memory.Waiting = false
		memory.LinedUp = nil
	end
	if memory.Hop and t < memory.Hop then
		return -- just jumped: let it land
	end

	-- Unstuck: no headway for a while (not waiting on purpose): hop and think again.
	local clock = os.clock()
	if not memory.Moved or flat(root.Position, memory.Moved) > 1.5 or memory.Waiting then
		memory.Moved = root.Position
		memory.MovedAt = clock
	elseif clock - (memory.MovedAt or clock) > 3.5 then
		memory.MovedAt = clock
		memory.Target = nil
		bot:Jump()
		return
	end

	-- The spinning bars: jump as the bar comes (it passes twice a turn).
	for _, spinner in Course.Spinners do
		local wait = Course.SpinnerNext(spinner, t, p.X, p.Z)
		if wait < math.huge and feet < spinner.Top + 0.6 then
			memory.BarError = memory.BarError or bot.Rng:NextNumber(-1, 1) * 0.16 * (1 - skill) ^ 1.2
			local low, high = 0.06 + memory.BarError, 0.26 + memory.BarError -- (feet clear it 0.04-0.5 s up)
			if wait >= low and wait <= high then
				memory.BarError = nil
				memory.Hop = t + 0.35
				bot:Jump()
				return
			end
		end
	end

	-- The barrels on the pyramid: jump as one comes (on a tier, before it reaches the bot).
	if here.Section == 6 and not here.Finish then
		memory.BarrelError = memory.BarrelError or bot.Rng:NextNumber(-1, 1) * 0.14 * (1 - skill) ^ 1.2
		local wait = Course.BarrelNext(t, p.X, here.Top, p.Z, 0.4)
		if wait >= 0.05 + memory.BarrelError and wait <= 0.27 + memory.BarrelError then
			memory.BarrelError = nil
			memory.Hop = t + 0.35
			bot:Jump()
			return
		end
	end

	-- Where to next: a piece in the next row (blinking blocks re-picked while waiting for a good one).
	local target = memory.Target
	if
		not target or (target.Row > here.Row and target.Blink and not solidThrough(target, t + SAFE_FROM, t + SAFE_TO))
	then
		target = pick(bot, here, p, t)
		memory.Target = target
	end
	if not target then
		bot:Stop()
		return
	end

	-- Waiting for a blinking block: stay on a solid one while none ahead is safe. If the one under it is
	-- about to go too, hop sideways onto a neighbour in its row that stays (a short hop), and look again.
	if target.Row > here.Row and target.Blink and not solidThrough(target, t + SAFE_FROM, t + SAFE_TO) then
		local _, _, left = Course.BlinkState(here, t)
		if not here.Blink or left > 0.8 then
			memory.Waiting = true
			bot:Stop()
			return
		end
		-- (the course always leaves one of these: Course.Setup)
		for _, other in Course.BlinkEscapes(here) do
			if other.Row == here.Row and solidThrough(other, t + 0.2, t + 1.2) then
				target = other
				memory.Target = other
				break
			end
		end
	end
	memory.Waiting = false

	-- Where it lands, and where it takes off.
	local gx, gz = nearestOn(target, p.X, p.Z, LAND_IN)
	local walk = false
	for _, way in Course.WaysOn(here) do
		if way.To == target then
			walk = way.Walk
		end
	end

	-- On the bridge, the balls come first.
	if here.Id == "Bridge" then
		local point, waiting = bridgeStep(bot, p, feet, t)
		memory.Waiting = waiting
		if waiting then
			bot:Stop()
			return
		elseif point then
			walkTo(point.X, here.Top, point.Z)
			return
		end
	end

	-- On a spinner, go round the hub rather than through it.
	if here.Spinner then
		local spinner = Course.Spinners[here.Spinner]
		local ahead = gz - p.Z
		if ahead > 0 and p.Z < spinner.Z + spinner.Hub and math.abs(p.X - spinner.X) < spinner.Hub + 1.8 then
			walkTo(spinner.X + memory.Side * (spinner.Hub + 3), here.Top, spinner.Z)
			return
		end
	end

	if walk then
		-- Walking on where two pieces join: first line up on this side of the join, then straight across
		-- (cutting the corner from a wide pad onto the narrow bridge walks off its side).
		if memory.LinedUp ~= target then
			local lx, lz = nearestOn(here, gx, gz, 1)
			if math.sqrt((p.X - lx) ^ 2 + (p.Z - lz) ^ 2) > ARRIVED then
				walkTo(lx, here.Top, lz)
				return
			end
			memory.LinedUp = target
		end
		walkTo(gx, target.Top, gz)
		return
	end
	local tx, tz
	if target.OnTop then
		-- up a pyramid tier: take off at its riser
		local cx, cz = nearestOn(target, p.X, p.Z, 0)
		local dx, dz = p.X - cx, p.Z - cz
		local length = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
		tx, tz = cx + dx / length * 0.9, cz + dz / length * 0.9
	else
		tx, tz = nearestOn(here, gx, gz, TAKE_OFF_IN)
	end
	local away = flat(Vector3.new(p.X, 0, p.Z), Vector3.new(tx, 0, tz))
	-- A clumsy bot sometimes goes too soon and splashes short.
	if memory.Early == nil then
		memory.Early = bot:Chance(0.1 * (1 - skill) ^ 1.5)
	end
	local within = if memory.Early then 4.2 else JUMP_WITHIN
	if away <= within then
		memory.Early = nil
		memory.Hop = t + 0.3 + bot.Rng:NextNumber(0, 0.1)
		walkTo(gx, target.Top, gz)
		bot:Jump()
		return
	end
	walkTo(tx, here.Top, tz)
end

return ObbyOdyssey

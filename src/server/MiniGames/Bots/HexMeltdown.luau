-- How bots play Hex Meltdown. When the referee calls a color, a bot takes a moment to read the flag
-- (bot:Reaction()), then heads for the nearest hex of that color that isn't crowded and a free spot
-- on it, crossing each gap in the middle of an edge with a hop. Unskilled bots sometimes stay on the
-- last color or mix the call up with a look-alike one, and may or may not notice in time. Between
-- calls, steadier bots wait near the middle of the grid, and now and then a bot jumps on a rival's
-- head to stun them. If a bot isn't on the called color when the hexes sink, the mode drops it into
-- the lava, like a player.

local BotRegistry = require(script.Parent.Parent.Parent.Services.BotRegistry)

local HexMeltdown = {}

local ON_HEX = 7 -- this close (flat) to a hex's center is on it (its corners are 7 out)
local NEIGHBOR = 15 -- hexes whose centers are this close are side by side (13.6 apart)
local EDGE = 6.06 -- from a hex's center to the middle of an edge
local SPOT = 3.4 -- bots stand within this of a hex's center
local HOP_AT = 2.7 -- leaving a hex: hop once this far out toward the next one (a hop covers ~8)
local MIDDLE = 16 -- the white hex and the ring around it, where every color is close

type Hex = { Position: Vector3, ColorIndex: number }

local function flat(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function hexAt(mode, position: Vector3): Hex?
	local best, bestDistance = nil, ON_HEX
	for _, hex in mode.hexes do
		local distance = flat(hex.Position, position)
		if distance < bestDistance then
			best, bestDistance = hex, distance
		end
	end
	return best
end

-- The other palette color that looks most like this one (red and pink, blue and purple...).
local function lookalike(mode, color: number): number
	local mine = mode.Palette[color].Color
	local best, bestDistance = color, math.huge
	for index, entry in mode.Palette do
		local other = entry.Color
		local distance = (other.R - mine.R) ^ 2 + (other.G - mine.G) ^ 2 + (other.B - mine.B) ^ 2
		if index ~= color and distance < bestDistance then
			best, bestDistance = index, distance
		end
	end
	return best
end

-- Where everyone else stands, or is heading (a bot goes by the spot it picked).
local function others(bot, ctx, mode): { Vector3 }
	local points = {}
	for _, player in ctx:GetAlivePlayers() do
		if player == bot or mode.falling[player] then
			continue
		end
		local _, _, root = ctx:GetCharacter(player)
		local point = if BotRegistry.IsBot(player) then player.Memory.Spot else nil
		point = point or (root and root.Position)
		if point then
			table.insert(points, point)
		end
	end
	return points
end

local function room(point: Vector3, points: { Vector3 }): number
	local nearest = math.huge
	for _, other in points do
		nearest = math.min(nearest, flat(point, other))
	end
	return nearest
end

-- A free spot on a hex, not far from where the bot is (where it stands, if there's room).
local function spotOn(bot, hex: Hex, points: { Vector3 }, from: Vector3): Vector3
	local center = hex.Position + Vector3.new(0, 3, 0)
	local candidates = { center }
	local turn = bot.Rng:NextNumber(0, math.pi * 2)
	for index = 1, 6 do
		local angle = turn + index * math.pi / 3
		table.insert(candidates, center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * SPOT)
	end
	if flat(from, center) < SPOT then
		table.insert(candidates, Vector3.new(from.X, center.Y, from.Z))
	end
	local best, bestScore = center, -math.huge
	for _, point in candidates do
		local score = math.min(room(point, points), 6) - flat(point, from) * 0.1
		if score > bestScore then
			best, bestScore = point, score
		end
	end
	return best
end

-- Picks a hex of `color` to stand on: close, and not crowded while there's time to be choosy.
local function head(bot, ctx, mode, color: number, deadline: number)
	local root = bot:Root()
	if not root then
		return
	end
	local points = others(bot, ctx, mode)
	local best, bestCost = nil, math.huge
	for _, hex in mode.hexes do
		if hex.ColorIndex ~= color then
			continue
		end
		local travel = math.max(0, flat(root.Position, hex.Position) - SPOT) / ctx.WalkSpeed
		local crowd = 0
		for _, point in points do
			if flat(point, hex.Position) < ON_HEX then
				crowd += 1
			end
		end
		local slack = math.clamp((deadline - ctx:Now() - travel) / 1.2, 0, 1)
		local cost = travel + crowd * 0.45 * slack + bot.Rng:NextNumber(0, 0.6) * (1 - bot.Skill)
		if cost < bestCost then
			best, bestCost = hex, cost
		end
	end
	if best then
		bot.Memory.Spot = spotOn(bot, best, points, root.Position)
	end
end

-- A hop, if the last one has landed (a jump is about 0.6s in the air).
local function hop(bot, ctx)
	local memory = bot.Memory
	if os.clock() - (memory.HoppedAt or 0) > 0.8 and not ctx:IsStunned(bot) then
		memory.HoppedAt = os.clock()
		bot:Jump()
	end
end

-- Walks to the spot a hex at a time: lines up with the middle of the edge to the next hex (so it
-- never clips a corner, where the gaps meet), then hops across.
local function walk(bot, ctx, mode, root: BasePart, spot: Vector3)
	local here, goal = hexAt(mode, root.Position), hexAt(mode, spot)
	if not here or not goal or here == goal then
		bot:MoveTo(spot)
		return
	end
	local nextHex, nearest = goal, math.huge
	for _, hex in mode.hexes do
		local distance = flat(hex.Position, goal.Position)
		if hex ~= here and flat(hex.Position, here.Position) < NEIGHBOR and distance < nearest then
			nextHex, nearest = hex, distance
		end
	end
	local waypoint = if nextHex == goal then spot else nextHex.Position + Vector3.new(0, 3, 0)
	local out = ((nextHex.Position - here.Position) * Vector3.new(1, 0, 1)).Unit
	local right = Vector3.new(-out.Z, 0, out.X)
	local offset, target = root.Position - here.Position, waypoint - here.Position
	local along, side = offset:Dot(out), offset:Dot(right)
	local targetAlong, targetSide = target:Dot(out), target:Dot(right)
	-- Where a straight walk would cross the gap, measured from the middle of the edge (7 long).
	local middle = flat(here.Position, nextHex.Position) / 2
	local cross = side
	if targetAlong - along > 0.1 then
		cross = side + (targetSide - side) * (middle - along) / (targetAlong - along)
	end
	if math.abs(cross) > 2.2 and along < EDGE - 0.5 then
		bot:MoveTo(here.Position + out * (EDGE - 1.5) + Vector3.new(0, 3, 0))
		return
	end
	bot:MoveTo(waypoint)
	if along > HOP_AT then
		hop(bot, ctx)
	end
end

-- Someone standing on the same hex, close enough to jump on.
local function victim(bot, ctx, mode, root: BasePart): any
	local here = hexAt(mode, root.Position)
	local best, bestDistance = nil, 6
	for _, player in ctx:GetAlivePlayers() do
		if player == bot or mode.falling[player] or ctx:IsStunned(player) then
			continue
		end
		local _, _, other = ctx:GetCharacter(player)
		local distance = other and flat(other.Position, root.Position) or math.huge
		if
			other
			and distance < bestDistance
			and hexAt(mode, other.Position) == here
			and math.abs(other.Position.Y - root.Position.Y) < 1
		then
			best, bestDistance = player, distance
		end
	end
	return best
end

function HexMeltdown.Step(bot, ctx, mode, _dt)
	local root, humanoid = bot:Root(), bot:Humanoid()
	if not root or not humanoid or mode.falling[bot] then
		return
	end
	local memory = bot.Memory
	local call = mode.call
	local now = ctx:Now()
	local skill = bot.Skill
	memory.Aggression = memory.Aggression or bot.Rng:NextNumber() ^ 2
	memory.NextStomp = memory.NextStomp or now + bot.Rng:NextNumber(4, 14) / math.max(memory.Aggression, 0.1)

	-- A new call: read the flag, then pick where to go.
	if call and call.Id ~= memory.Call then
		memory.Call = call.Id
		memory.LastColor, memory.CallColor = memory.CallColor, call.Color
		memory.ReactAt = call.WarnAt + bot:Reaction()
		memory.Going = nil
		memory.NoticeAt = nil
		memory.Stomp = nil
	end
	if call and not memory.Going and now >= memory.ReactAt then
		local slip = 0.3 * (1 - skill) ^ 1.5 * (0.7 + 0.6 * ctx:Progress())
		if bot:Chance(slip) then
			-- Stays on the last color, or mixes the call up with a look-alike one.
			local last = memory.LastColor
			memory.Going = if last and bot:Chance(0.5) then last else lookalike(mode, call.Color)
			memory.NoticeAt = now + (0.5 + (1 - skill)) * bot.Rng:NextNumber(0.8, 1.3)
			memory.Notices = bot:Chance(0.45 + 0.5 * skill)
		else
			memory.Going = call.Color
		end
		head(bot, ctx, mode, memory.Going, call.SinkAt)
	end
	if call and memory.NoticeAt and now >= memory.NoticeAt then
		memory.NoticeAt = nil
		if memory.Notices and memory.Going ~= call.Color then
			memory.Going = call.Color
			head(bot, ctx, mode, call.Color, call.SinkAt)
		end
	end

	-- Between calls (every hex up), steadier bots move in towards the middle.
	local between = call ~= nil and now > call.RiseAt + call.Move
	if call and between and memory.Middle ~= call.Id then
		memory.Middle = call.Id
		local center = ctx.Origin.Position
		if flat(root.Position, center) > MIDDLE and bot:Chance(skill * 0.6) then
			local best, bestDistance = nil, math.huge
			for _, hex in mode.hexes do
				local distance = flat(hex.Position, root.Position)
				if flat(hex.Position, center) < MIDDLE and distance < bestDistance then
					best, bestDistance = hex, distance
				end
			end
			if best then
				memory.Spot = spotOn(bot, best, others(bot, ctx, mode), root.Position)
			end
		end
	end

	-- Jumping on someone: run at them and hop when close, then find a free spot again.
	local stomp = memory.Stomp
	if stomp then
		local _, _, target = ctx:GetCharacter(stomp.Victim)
		local here = hexAt(mode, root.Position)
		if
			target
			and os.clock() < stomp.Until
			and ctx:IsAlive(stomp.Victim)
			and (stomp.Jumped or hexAt(mode, target.Position) == here)
		then
			bot:MoveTo(target.Position)
			if not stomp.Jumped and flat(root.Position, target.Position) < 3.5 then
				stomp.Jumped = true
				stomp.Until = os.clock() + 0.9
				hop(bot, ctx)
			end
			return
		end
		memory.Stomp = nil
		if here then
			memory.Spot = spotOn(bot, here, others(bot, ctx, mode), root.Position)
		end
	end

	local spot = memory.Spot
	if spot and flat(root.Position, spot) > 0.8 then
		memory.Arrived = false
		walk(bot, ctx, mode, root, spot)
		return
	end
	if not memory.Arrived then
		memory.Arrived = true
		bot:Stop()
	end

	-- Waiting somewhere safe: now and then a hop on the spot, or a jump on a rival's head.
	local here = hexAt(mode, root.Position)
	if not call or not here or not (between or here.ColorIndex == call.Color) then
		return
	end
	if now >= memory.NextStomp then
		memory.NextStomp = now + bot.Rng:NextNumber(10, 22) / math.max(memory.Aggression, 0.1)
		local target = victim(bot, ctx, mode, root)
		if target then
			memory.Stomp = { Victim = target, Until = os.clock() + 1.6 }
		end
	elseif bot:Chance(0.004) then
		hop(bot, ctx)
	end
end

return HexMeltdown

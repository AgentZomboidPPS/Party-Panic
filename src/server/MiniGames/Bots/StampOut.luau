-- How bots play Stamp Out (contract in Bots/Default.luau).
--
-- A bot picks a spot on the paper worth stamping: it samples a few spots (more for skilled bots)
-- and scores each by the cells a stamp there would win (a rival's ink a little more than blank
-- paper, its own ink nothing), minus how far away it is. Far spots it reaches with a charged hop
-- (STAMP held, like a player: "Charge", then "Hop" a moment later, so the server times the hold the
-- same way); near ones it walks to and jumps, and every landing stamps (the server's landing watch
-- in StampOut.luau, same as for players). Weaker bots look at fewer spots, wait longer between
-- moves and sometimes just bounce where they are, so they're beatable. They never hop off the paper.
local StampGrid = require(game:GetService("ReplicatedStorage").Shared.Logic.StampGrid)

local Brain = {}

local EDGE = StampGrid.PAD / 2 - 6 -- bots keep their spots this far inside the paper

-- What a stamp at pad-local (x, z) would win for `ink`.
local function worth(mode, ink: number, x: number, z: number): number
	local owners = mode.Owners
	local value = 0
	for _, cell in StampGrid.Disc(x, z, StampGrid.HOP_RADIUS_MAX) do
		local owner = owners[cell]
		if owner == 0 then
			value += 1
		elseif owner ~= ink then
			value += 1.25
		end
	end
	return value
end

local function pickSpot(bot, mode, ink: number, x: number, z: number): Vector2
	local samples = math.floor(3 + bot.Skill * 10)
	local best, bestScore = Vector2.new(x, z), -math.huge
	for _ = 1, samples do
		local sx = bot.Rng:NextNumber(-EDGE, EDGE)
		local sz = bot.Rng:NextNumber(-EDGE, EDGE)
		local distance = math.sqrt((sx - x) ^ 2 + (sz - z) ^ 2)
		local score = worth(mode, ink, sx, sz) - distance * (0.35 - bot.Skill * 0.2)
		if score > bestScore then
			best, bestScore = Vector2.new(sx, sz), score
		end
	end
	return best
end

function Brain.Step(bot, ctx, mode, _dt)
	local root = bot:Root()
	if not root or not mode.Paper or not mode.InkOf then
		return
	end
	local memory = bot.Memory
	local now = os.clock()
	local ink = mode.InkOf[bot]
	if not ink or mode.Flying[bot] then
		return
	end
	local paper = mode.Paper
	local x, z = root.Position.X - paper.X, root.Position.Z - paper.Z

	-- Finishing a held STAMP: let go and hop.
	if memory.HopAt then
		if now >= memory.HopAt then
			memory.HopAt = nil
			ctx:BotAction(bot, "Hop", memory.Charge, memory.Direction.X, memory.Direction.Y)
			memory.NextMove = now + 0.75 + bot:Reaction() * 0.6
		end
		return
	end
	if memory.NextMove and now < memory.NextMove then
		if memory.Goal then
			bot:MoveTo(memory.Goal)
		end
		return
	end

	-- Off the paper (knocked or fell back on the desk): walk back on and hop up.
	if not StampGrid.OnPad(x, z, 1) then
		local back = paper + Vector3.new(x * 0.6, 0, z * 0.6)
		memory.Goal = back
		bot:MoveTo(back)
		if bot:Chance(0.3) then
			bot:Jump()
		end
		memory.NextMove = now + 0.3
		return
	end

	-- A new spot now and then (or when the old one is inked already).
	local spot = memory.Spot
	if not spot or (memory.SpotUntil or 0) < now or worth(mode, ink, spot.X, spot.Y) < 4 then
		spot = pickSpot(bot, mode, ink, x, z)
		memory.Spot = spot
		memory.SpotUntil = now + 2 + bot.Rng:NextNumber(0, 2)
	end
	local offset = Vector2.new(spot.X - x, spot.Y - z)
	local distance = offset.Magnitude

	if distance > StampGrid.HOP_MIN + 2 and bot:Chance(0.35 + bot.Skill * 0.5) then
		-- Hop toward it: charge just enough (skilled bots judge it better).
		local wanted = math.min(distance, StampGrid.HOP_MAX)
		local charge = (wanted - StampGrid.HOP_MIN) / (StampGrid.HOP_MAX - StampGrid.HOP_MIN)
		charge = math.clamp(charge + bot.Rng:NextNumber(-0.25, 0.25) * (1 - bot.Skill), 0, 1)
		local direction = offset.Unit
		-- Never off the paper.
		local reach = StampGrid.HOP_MIN + (StampGrid.HOP_MAX - StampGrid.HOP_MIN) * charge
		local lands = Vector2.new(x, z) + direction * reach
		if not StampGrid.OnPad(lands.X, lands.Y, 4) then
			charge = 0
			lands = Vector2.new(x, z) + direction * StampGrid.HOP_MIN
			if not StampGrid.OnPad(lands.X, lands.Y, 4) then
				memory.Spot = nil
				return
			end
		end
		bot:Stop()
		memory.Goal = nil
		memory.Charge = charge
		memory.Direction = direction
		memory.HopAt = now + charge * StampGrid.CHARGE_TIME + 0.05
		ctx:BotAction(bot, "Charge")
		return
	end

	-- Close (or not in a hopping mood): walk there and bounce.
	local goal = paper + Vector3.new(spot.X, 0, spot.Y)
	memory.Goal = goal
	bot:MoveTo(goal)
	if bot:Chance(0.55 + bot.Skill * 0.35) then
		bot:Jump()
	end
	memory.NextMove = now + 0.35 + bot:Reaction() * 0.5
end

return Brain

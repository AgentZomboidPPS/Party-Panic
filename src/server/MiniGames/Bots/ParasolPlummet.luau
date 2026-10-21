-- How bots play Parasol Plummet (contract in Bots/Default.luau). A bot notices each throw a moment
-- after it leaves the thrower's hand (its own reaction time, quicker with skill), then chases the
-- best coin it can still reach: it reads the shared arc (Sim.ItemAt) a few beats ahead, steers under
-- it and shuts its umbrella to drop onto a low one or opens it to float up into a high one. Bags are
-- worth chasing further. When a hammer it has seen is about to meet it, a bot tries to get out of
-- the way (sideways, and down if it comes from above); skilled bots dodge most, clumsy ones get
-- bonked now and then, and every bot drifts a little off its line, so good players can beat them.
--
-- Hazard parity: bots press the same "Input" a client sends (ctx:BotAction) and fly in the same
-- server simulation, so a hammer stuns a bot exactly the way it stuns a player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sim = require(ReplicatedStorage.Shared.Logic.ParasolPlummetSim)

local Brain = {}

local LOOK = { 0.25, 0.5, 0.8, 1.1, 1.5, 2, 2.6 }

local function send(bot, ctx, memory, steer: number, open: boolean)
	steer = math.clamp(math.floor(steer * 4 + 0.5) / 4, -1, 1)
	if memory.Steer ~= steer or memory.Open ~= open then
		memory.Steer, memory.Open = steer, open
		ctx:BotAction(bot, "Input", steer, open)
	end
end

function Brain.Step(bot, ctx, mode, _dt)
	local f = mode.fallers and mode.fallers[bot]
	if not f or not mode.startAt or mode.over then
		return
	end
	local memory = bot.Memory
	local now = ctx:Now()
	local skill = bot.Skill
	memory.Notice = memory.Notice or {}
	memory.Wobble = memory.Wobble or 0
	if now >= (memory.WobbleAt or 0) then
		memory.WobbleAt = now + bot.Rng:NextNumber(0.6, 1.6)
		memory.Wobble = bot.Rng:NextNumber(-1, 1) * (1 - skill) * 4
	end

	-- What this bot has noticed so far.
	local danger, dangerX, dangerY = false, 0, 0
	local best, bestScore, bestX, bestY = nil, 0, 0, 0
	for id, item in mode.items do
		local notice = memory.Notice[id]
		if not notice then
			notice = item.At + bot:Reaction() * 0.8
			memory.Notice[id] = notice
		end
		if now < notice then
			continue
		end
		local kind = Sim.Kinds[item.Kind]
		if item.Kind == "Hammer" then
			for _, ahead in { 0.15, 0.35, 0.6, 0.9, 1.25 } do
				local t = now + ahead
				local hx, hy = Sim.ItemAt(item, t)
				local px = f.X + f.VX * ahead
				local py = f.Y + f.VY * ahead
				if Sim.Touches(px, py, f.Open, hx, hy, kind.Radius, 1.2) then
					danger, dangerX, dangerY = true, hx, hy
					break
				end
			end
			continue
		end
		for _, ahead in LOOK do
			local t = now + ahead
			if Sim.Gone(item, t) then
				break
			end
			local ix, iy = Sim.ItemAt(item, t)
			if math.abs(ix) > Sim.HALF_W + 2 then
				continue
			end
			local reachX = Sim.STEER_OPEN * ahead * (0.55 + 0.35 * skill) + 2
			local dy = iy - f.Y
			if math.abs(ix - f.X) <= reachX and dy <= Sim.RISE * ahead + 6.5 and dy >= -14 * ahead - 2 then
				local value = kind.Value * (if item.Kind == "Bag" then 1.5 else 1)
				local score = value / (ahead + 0.5) - math.abs(ix - f.X) * 0.01
				if score > bestScore then
					best, bestScore, bestX, bestY = item, score, ix, iy
				end
				break
			end
		end
	end
	for id in memory.Notice do
		if not mode.items[id] then
			memory.Notice[id] = nil
		end
	end

	-- Dodge first (if this bot reacts in time), then chase, else drift about the middle.
	if danger and (memory.Dodging or bot:Chance(0.25 + 0.6 * skill)) then
		memory.Dodging = true
		local away = if f.X >= dangerX then 1 else -1
		if math.abs(f.X) > Sim.HALF_W - 3 then
			away = -math.sign(f.X) -- pinned to the edge: go the other way
		end
		-- Sideways first; drop under one coming in high, float over one coming in low.
		send(bot, ctx, memory, away, dangerY < f.Y + 1 or f.Y < Sim.Y_MIN + 3)
		return
	end
	memory.Dodging = false
	if best then
		-- Meet it with the umbrella or the body: anything from the feet to the canopy catches, so
		-- only drop when it's below that and float up when it's above.
		local steer = math.clamp((bestX + memory.Wobble - f.X) / 3, -1, 1)
		local open = if memory.Open == nil then true else memory.Open
		-- (Level with it, an open umbrella's slow float keeps it in reach longest.)
		if bestY < f.Y - 1.5 then
			open = false
		elseif bestY > f.Y + 4 or f.Y < Sim.Y_MAX - 2 then
			open = true
		end
		send(bot, ctx, memory, steer, open)
		return
	end
	local home = memory.Home
	if not home or bot:Chance(0.05) then
		home = bot.Rng:NextNumber(-Sim.HALF_W * 0.7, Sim.HALF_W * 0.7)
		memory.Home = home
		memory.HomeY = bot.Rng:NextNumber(Sim.Y_MIN + 6, Sim.Y_MAX - 3)
	end
	-- Hover around the middle of the sky (high enough to see what comes, low enough to drop on it).
	local open = if memory.Open == nil then true else memory.Open
	if f.Y > memory.HomeY + 3 then
		open = false
	elseif f.Y < memory.HomeY - 3 then
		open = true
	end
	send(bot, ctx, memory, math.clamp((home - f.X) / 6, -1, 1), open)
end

return Brain

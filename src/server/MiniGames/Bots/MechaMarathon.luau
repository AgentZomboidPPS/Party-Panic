-- How bots play Mecha-Marathon (the contract is in Bots/Default.luau): a bot mashes WIND from a
-- moment after GO until the winding ends, through ctx:BotAction, so the server counts its presses
-- exactly like a player's (same counter, same rate cap).
--
-- Each bot mashes at its own pace: 4 + 5 * Skill presses a second (about 6 to 9.5, give or take a
-- tenth), a little ragged from one moment to the next, tiring a bit towards the end, and the less
-- skilled ones fumble now and then (a short pause). That spreads the bots' flights over the field
-- and keeps them beatable: a player who mashes steadily beats most of them, and drumming two
-- fingers (up to the cap of 12 a second) beats every one. Nothing in this mode can hurt anyone, so
-- there's no hazard to dodge. Bots hop for joy when their toy wins.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flight = require(ReplicatedStorage.Shared.Logic.MechaMarathonFlight)

local MechaMarathonBrain = {}

function MechaMarathonBrain.Step(bot, ctx, mode, dt)
	local memory = bot.Memory
	local now = ctx:Now()
	if mode.phase == "Wind" and now <= mode.windEnd then
		if not memory.Rate then
			memory.Rate = (4 + 5 * bot.Skill) * bot.Rng:NextNumber(0.92, 1.08)
			memory.Begin = mode.windStart + bot:Reaction()
			memory.Owed = 0
		end
		if now < memory.Begin or now < (memory.PauseUntil or 0) then
			return
		end
		local progress = math.clamp((now - mode.windStart) / Flight.WIND_TIME, 0, 1)
		local tired = 1 - progress * (0.16 - 0.12 * bot.Skill)
		memory.Owed += memory.Rate * tired * math.min(dt, 0.4) * bot.Rng:NextNumber(0.8, 1.2)
		while memory.Owed >= 1 do
			memory.Owed -= 1
			ctx:BotAction(bot, "Wind")
		end
		if bot:Chance((1 - bot.Skill) * 0.03) then
			memory.PauseUntil = now + bot.Rng:NextNumber(0.15, 0.4) -- a fumble
		end
	elseif mode.phase == "Done" and not memory.Cheered then
		memory.Cheered = true
		local best = mode:_best()
		if best == bot then
			bot:Jump()
		end
	end
end

return MechaMarathonBrain

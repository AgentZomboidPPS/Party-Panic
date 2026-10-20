-- Bot for Honey Trap: on its turn a bot waits a moment, then hits the block with whatever face is
-- showing (the way a player who doesn't count would). Some bots let the timer run out.
return function(env)
	local ctx = env.ctx
	local lastTurn = nil
	local hitAt = 0
	local turns, honeys, timeouts = 0, 0, 0
	local lastStart = nil
	return function()
		local turn = env.SharedJSON("Turn")
		local vine = env.SharedJSON("Vine")
		if vine and vine.Start ~= lastStart then
			if lastStart and vine.Honey then
				honeys += 1
				env.note(`turn {turns}: honeycomb for {vine.Taker} (took {vine.Taken})`)
			end
			lastStart = vine.Start
		end
		if not turn then
			return
		end
		if turn.Id ~= lastTurn then
			lastTurn = turn.Id
			turns += 1
			-- One turn in eight, the bot "goes AFK" and the block stops by itself.
			hitAt = if env.rng:NextNumber() < 0.125 then math.huge else turn.T0 + env.rng:NextNumber(0.3, 2.5)
			if hitAt == math.huge then
				timeouts += 1
			end
		end
		if turn.Result == nil and ctx:Now() >= hitAt then
			hitAt = math.huge
			for _, player in env.players do
				if player.UserId == turn.User then
					local flips = math.floor(math.max(0, ctx:Now() - turn.T0) / turn.Flip)
					local face = ((turn.First - 1 + flips) % 2) + 1
					env.Action(player, "Hit", face)
				end
			end
		end
	end
end

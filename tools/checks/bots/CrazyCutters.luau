-- Test bot for Crazy Cutters: every stand-in player traces the outline with the mode's bot paths
-- (skills spread from clumsy to steady), sending batches of positions like a client does. One
-- player sends junk now and then (a teleport, a position off the board, a stale batch, NaN) that the
-- server must ignore, and one player leaves halfway through the second shape.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local skills = {}
	for index, player in env.players do
		skills[player] = 0.35 + 0.55 * ((index - 1) % 6) / 5
	end
	local lastSend = 0
	local sent, junk = 0, 0
	local left = false
	local reported = {}
	return function(elapsed)
		local round = mode.round
		if not round then
			return
		end
		if round.Phase == "Score" and not reported[round.Index] and mode.scores then
			reported[round.Index] = true
			local line = {}
			for _, player in env.players do
				local scores = mode.scores[player]
				if scores and scores[round.Index] then
					table.insert(line, `{player.Name}={scores[round.Index]}`)
				end
			end
			-- (The scores are final 0.35 s after the cut ends; this may print before some are in.)
			env.note(`shape {round.Index} {round.Shape}: sent {sent} batches, {junk} junk; {table.concat(line, " ")}`)
		end
		if round.Phase ~= "Cut" or elapsed - lastSend < 0.15 then
			return
		end
		lastSend = elapsed
		local now = ctx:Now()
		for index, player in env.players do
			if not player.Parent then
				continue
			end
			if index ~= 2 or env.rng:NextNumber() >= 0.15 then
				local samples = mode:BotSamples(player, skills[player], env.rng, now)
				if samples then
					env.Action(player, "Cut", round.Index, samples)
					sent += 1
				end
			else -- junk instead of this batch (the server drops it; the cut carries on after)
				junk += 1
				local kind = env.rng:NextInteger(1, 4)
				if kind == 1 then
					env.Action(player, "Cut", round.Index, { now, 6.9, -6.9 }) -- a teleport
				elseif kind == 2 then
					env.Action(player, "Cut", round.Index, { now, 40, 0 }) -- off the board
				elseif kind == 3 then
					env.Action(player, "Cut", round.Index - 1, { now, 0, 0 }) -- the last shape
				else
					env.Action(player, "Cut", round.Index, { now, 0 / 0, 0 }) -- NaN
				end
			end
		end
		if not left and round.Index == 2 and #env.players >= 4 and now > round.T0 + 3 then
			left = true
			env.note(`{env.players[4].Name} leaves mid-cut`)
			env.Leave(env.players[4])
		end
	end
end

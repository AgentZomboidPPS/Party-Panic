-- Test bot for Trace Race: every stand-in player steers with the mode's bot paths (skills spread from
-- clumsy to steady), sending batches of positions like a client does, and rides its crayon (moved
-- with env.Move, the test server has no physics). One player sends junk now and then (a teleport
-- sideways, a position off the paper, a time from the future, NaN) that the server must ignore, and
-- one player leaves halfway through the ride.
--
-- Player 3 sends like the real client: every batch carries the positions the server hasn't taken
-- yet, and a quarter of its batches are lost on the way. It keeps its own live score (the one its
-- screen shows) and notes it next to the server's final one: they must match.
return function(env)
	local Rules = __require("Shared/Logic/TraceRace") -- the harness bundle's module loader
	local ctx = env.ctx
	local mode = env.game
	local skills = {}
	for index, player in env.players do
		skills[player] = 0.35 + 0.55 * ((index - 1) % 6) / 5
	end
	local lastSend = 0
	local sent, junk, lost = 0, 0, 0
	local left = false
	local resender = env.players[3]
	local waiting = {} -- the resender's positions the server hasn't taken, flat
	local live = nil -- the resender's own tracker (what its screen shows)
	local reported = false
	return function(elapsed)
		local race = mode.race
		if not race then
			return
		end
		local now = ctx:Now()
		-- Ride along (the stand-ins' rigs follow their crayons).
		for index, player in env.players do
			if player.Parent and not (env.client and index == 1) then
				local seat = mode:_seat(player)
				if seat then
					env.Move(player, seat.Position, seat.Position + seat.LookVector)
				end
			end
		end
		if not reported and now > race.T1 + 1.2 and next(mode.final) then
			reported = true
			local line = {}
			for _, player in env.players do
				local score = mode.final[player]
				if score then
					table.insert(line, `{player.Name}={score}`)
				end
			end
			env.note(`ride over: sent {sent} batches, {junk} junk; {table.concat(line, " ")}`)
			if resender and live and mode.final[resender] then
				local final = mode.final[resender]
				env.note(
					`{resender.Name} resends, {lost} batches lost: live {live:Score()} server {final}`
						.. (if live:Score() == final then " (match)" else " MISMATCH")
				)
			end
		end
		if elapsed - lastSend < 0.15 or now > race.T1 + 0.4 then
			return
		end
		lastSend = elapsed
		for index, player in env.players do
			if not player.Parent or (env.client and index == 1) then
				continue
			end
			if player == resender then
				live = live or Rules.Tracker(mode.course)
				local samples = mode:BotSamples(player, skills[player], env.rng, now) or {}
				for at = 1, #samples - 1, 2 do
					live:Add((samples[at] - race.T0) * Rules.SPEED, samples[at + 1])
					table.move(samples, at, at + 1, #waiting + 1, waiting)
				end
				-- Like the client: drop what the server has taken, send the rest (or lose it).
				local track = mode.tracks[player]
				local batch = {}
				for at = 1, #waiting - 1, 2 do
					if not track or waiting[at] > track.LastT + 1e-4 then
						table.move(waiting, at, at + 1, #batch + 1, batch)
					end
				end
				waiting = table.move(batch, 1, math.min(#batch, Rules.MAX_CHUNK * 2), 1, {})
				if #waiting > 0 then
					if env.rng:NextNumber() < 0.25 and now < race.T1 then
						lost += 1
					else
						env.Action(player, "Trace", waiting)
						sent += 1
					end
				end
			elseif index ~= 2 or env.rng:NextNumber() >= 0.15 then
				local samples = mode:BotSamples(player, skills[player], env.rng, now)
				if samples then
					env.Action(player, "Trace", samples)
					sent += 1
				end
			else -- junk instead of this batch (the server drops it; the ride carries on after)
				junk += 1
				local kind = env.rng:NextInteger(1, 4)
				local track = mode.tracks[player]
				local x = if track then track.LastX else 0
				if kind == 1 then
					env.Action(player, "Trace", { now, if x > 0 then -6.5 else 6.5 }) -- a sideways teleport
				elseif kind == 2 then
					env.Action(player, "Trace", { now, 40 }) -- off the paper
				elseif kind == 3 then
					env.Action(player, "Trace", { now + 5, x }) -- from the future
				else
					env.Action(player, "Trace", { now, 0 / 0 }) -- NaN
				end
			end
		end
		if not left and #env.players >= 4 and now > race.T0 + 12 then
			left = true
			env.note(`{env.players[4].Name} leaves mid-ride`)
			env.Leave(env.players[4])
		end
	end
end

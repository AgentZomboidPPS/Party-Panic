-- Test bot for Crazy Cutters: every stand-in player traces the outline with the mode's bot paths
-- (skills spread from clumsy to steady), sending batches of positions like a client does. One
-- player sends junk now and then (a teleport, a position off the board, a stale batch, NaN) that the
-- server must ignore, and one player leaves halfway through the second shape.
--
-- Player 3 sends like the real client: every batch carries the positions the server hasn't taken
-- yet, and a quarter of its batches are lost on the way. It keeps its own live score (the one its
-- screen shows) and notes it next to the server's: they must match.
return function(env)
	local Rules = __require("Shared/Logic/CrazyCutters") -- the harness bundle's module loader
	local ctx = env.ctx
	local mode = env.game
	local skills = {}
	for index, player in env.players do
		skills[player] = 0.35 + 0.55 * ((index - 1) % 6) / 5
	end
	local lastSend = 0
	local sent, junk, lost = 0, 0, 0
	local left = false
	local reported = {}
	local resender = env.players[3]
	local waiting = {} -- the resender's positions the server hasn't taken, flat
	local live = nil -- the resender's own tracker (what its screen shows)
	local liveIndex = 0
	local compared = {}
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
			-- (The scores are final 0.6 s after the cut ends; this may print before some are in.)
			env.note(`shape {round.Index} {round.Shape}: sent {sent} batches, {junk} junk; {table.concat(line, " ")}`)
		end
		if resender and live and liveIndex == round.Index and not compared[round.Index] then
			local scores = mode.scores and mode.scores[resender]
			if scores and scores[round.Index] then
				compared[round.Index] = true
				env.note(
					`{resender.Name} resends, {lost} batches lost: live {live:Score()} server {scores[round.Index]}`
						.. (if live:Score() == scores[round.Index] then " (match)" else " MISMATCH")
				)
			end
		end
		if elapsed - lastSend < 0.15 then
			return
		end
		lastSend = elapsed
		local now = ctx:Now()
		-- The resender's unconfirmed positions still go for a moment after the cut ends.
		if resender and resender.Parent and #waiting > 0 and round.Phase ~= "Cut" and now < round.T1 + 0.4 then
			local track = mode.tracks[resender]
			local batch = {}
			for at = 1, #waiting - 2, 3 do
				if not track or waiting[at] > track.LastT + 1e-4 then
					table.insert(batch, waiting[at])
					table.insert(batch, waiting[at + 1])
					table.insert(batch, waiting[at + 2])
				end
			end
			waiting = batch
			if #batch > 0 then
				env.Action(resender, "Cut", round.Index, batch)
			end
		end
		if round.Phase ~= "Cut" then
			return
		end
		for index, player in env.players do
			if not player.Parent then
				continue
			end
			if player == resender then
				if liveIndex ~= round.Index then
					liveIndex = round.Index
					live = Rules.Tracker(Rules.Get(round.Shape) :: Rules.Shape)
					waiting = {}
				end
				local samples = mode:BotSamples(player, skills[player], env.rng, now) or {}
				for at = 1, #samples - 2, 3 do
					if not live.Done then
						live:Add(samples[at + 1], samples[at + 2])
						table.move(samples, at, at + 2, #waiting + 1, waiting)
					end
				end
				-- Like the client: drop what the server has taken, send the rest (or lose it).
				local track = mode.tracks[player]
				local batch = {}
				for at = 1, #waiting - 2, 3 do
					if not track or waiting[at] > track.LastT + 1e-4 then
						table.move(waiting, at, at + 2, #batch + 1, batch)
					end
				end
				waiting = table.move(batch, math.max(1, #batch - Rules.MAX_CHUNK * 3 + 1), #batch, 1, {})
				if #waiting > 0 then
					if env.rng:NextNumber() < 0.25 then
						lost += 1
					else
						env.Action(player, "Cut", round.Index, waiting)
						sent += 1
					end
				end
			elseif index ~= 2 or env.rng:NextNumber() >= 0.15 then
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

-- Bot for Rake It In (tools/checks/round_harness.py): each stand-in player rakes every second or two
-- at a random moment (like someone mashing without looking), sending the time they "pressed" like
-- the client does. Every few seconds one player sends junk (a string, a huge time) to check the
-- server's validation. Notes the scores now and then.
return function(env)
	local ctx = env.ctx
	local nextRake = {}
	local rakes, junk = 0, 0
	local reportAt = 8
	return function(elapsed)
		local now = ctx:Now()
		for index, player in env.players do
			if not env.Alive(player) then
				continue
			end
			if not nextRake[player] then
				nextRake[player] = now + env.rng:NextNumber(0.5, 2)
			elseif now >= nextRake[player] then
				nextRake[player] = now + env.rng:NextNumber(0.9, 2.2)
				if index == 1 and env.rng:NextNumber() < 0.15 then
					junk += 1
					env.Action(player, "Rake", if env.rng:NextNumber() < 0.5 then "soon" else now + 1e6)
				else
					rakes += 1
					env.Action(player, "Rake", now - env.rng:NextNumber(0, 0.1))
				end
			end
		end
		if elapsed >= reportAt then
			reportAt += 12
			local field = env.SharedJSON("Field")
			local scores = {}
			for _, player in env.players do
				table.insert(scores, tostring(env.Mine(player, "Score") or 0))
			end
			local onField = if field then #field.Items else 0
			local list = table.concat(scores, ",")
			env.note(`t={math.floor(elapsed)}s rakes {rakes} (junk {junk}), on field {onField}, scores {list}`)
		end
	end
end

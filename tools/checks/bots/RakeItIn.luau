-- Bot for Rake It In (tools/checks/round_harness.py): each stand-in player rakes every second or two
-- at a random moment (like someone mashing without looking), sending the time they "pressed" like
-- the client does. Every few seconds one player sends junk (a string, a huge time) to check the
-- server's validation. Notes the scores now and then.
--
-- In rounds of stand-ins only, it also stages two neighbours raking the same veggie at once every
-- few seconds: the one who pressed 0.1 s later is handled first (as with a faster connection), and
-- both must get it (RakeItIn.luau, "Two rakes after the same veggie"). The notes count them; a race
-- where either got less than their lane held is a warning, so it shows among the errors. With 5 or
-- more stand-ins, the last one leaves 25 s in and then tries to rake: that must change nothing.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local nextRake = {}
	local lastSent = {} -- os.clock() of each stand-in's last action (the server allows one per 0.3 s)
	local rakes, junk = 0, 0
	local reportAt = 8
	local stageAt = 3
	local staged = nil -- the race in flight: who pressed when and what each should get
	local contested, bothGot = 0, 0
	local leaver, leftScore = nil, nil

	local function send(player, ...)
		lastSent[player] = os.clock()
		env.Action(player, "Rake", ...)
	end

	local function neighbours(a, b): boolean
		local count = 0
		for _ in mode.stations do
			count += 1
		end
		local gap = math.abs(mode.stations[a].Index - mode.stations[b].Index)
		return gap == 1 or (count > 2 and gap == count - 1)
	end

	-- Two neighbours with their rakes ready and a veggie both rakes would take (the earlier press 0.1 s
	-- before the later one), with no bomb in either haul, so the scores say exactly what each got.
	local function findRace(now: number)
		if #ctx:GetPlayers() ~= #env.players then
			return nil -- real bots rake too: they could take from these lanes in between
		end
		for _, a in env.players do
			for _, b in env.players do
				if a == b or not env.Alive(a) or not env.Alive(b) or not neighbours(a, b) then
					continue
				end
				local idle = os.clock() - 0.5
				if (lastSent[a] or 0) > idle or (lastSent[b] or 0) > idle then
					continue
				end
				if mode:ReadyAt(a) > now - 0.3 or mode:ReadyAt(b) > now - 0.3 then
					continue
				end
				local early, late = now - 0.1, now
				local takenA, valueA, bombA = mode:LaneHaul(mode.stations[a], early)
				local takenB, valueB, bombB = mode:LaneHaul(mode.stations[b], late)
				if bombA or bombB then
					continue
				end
				for _, item in takenA do
					if table.find(takenB, item) then
						return {
							Early = a,
							Late = b,
							Item = item,
							WantA = valueA,
							WantB = valueB,
							ScoreA = env.Mine(a, "Score") or 0,
							ScoreB = env.Mine(b, "Score") or 0,
							EarlyAt = early,
							LateAt = late,
						}
					end
				end
			end
		end
		return nil
	end

	return function(elapsed)
		local now = ctx:Now()
		if staged then
			-- Both presses have been handled by now (actions run at the end of the frame they're sent in).
			local race = staged
			staged = nil
			local gotA = (env.Mine(race.Early, "Score") or 0) - race.ScoreA
			local gotB = (env.Mine(race.Late, "Score") or 0) - race.ScoreB
			contested += 1
			if gotA == race.WantA and gotB == race.WantB then
				bothGot += 1
			else
				warn(
					`[RakeItIn check] contested veggie #{race.Item.Id}: the later press (handled first) got `
						.. `{gotB} of {race.WantB}, the earlier press got {gotA} of {race.WantA}`
				)
			end
			nextRake[race.Early] = now + env.rng:NextNumber(0.9, 2.2)
			nextRake[race.Late] = now + env.rng:NextNumber(0.9, 2.2)
		elseif elapsed >= stageAt then
			local race = findRace(now)
			if race then
				stageAt = elapsed + 4
				staged = race
				send(race.Late, race.LateAt) -- handled first
				send(race.Early, race.EarlyAt)
				return -- no other rakes this step, so nothing else takes from these two lanes
			end
		end
		-- Someone leaves mid-round, then (a stale client) presses RAKE: nothing may change.
		if not leaver and elapsed >= 25 and #env.players >= 5 then
			leaver = table.remove(env.players)
			env.Leave(leaver)
			leftScore = env.Mine(leaver, "Score") or 0
			send(leaver, now)
		elseif leaver and leftScore then
			local score = env.Mine(leaver, "Score") or 0
			local inRound = table.find(ctx:GetPlayers(), leaver) ~= nil
			if score ~= leftScore or inRound then
				warn(`[RakeItIn check] {leaver.Name} left but is still in the round or still scoring`)
			end
			env.note(`{leaver.Name} left at {leftScore} pts: out of the round, a rake after leaving did nothing`)
			leftScore = nil
		end
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
					send(player, if env.rng:NextNumber() < 0.5 then "soon" else now + 1e6)
				else
					rakes += 1
					send(player, now - env.rng:NextNumber(0, 0.1))
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
			env.note(
				`t={math.floor(elapsed)}s rakes {rakes} (junk {junk}), on field {onField}, scores {list}, `
					.. `contested {bothGot}/{contested} both got it`
			)
		end
	end
end

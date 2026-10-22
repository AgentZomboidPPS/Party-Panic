-- Test bot for Trace Race: every stand-in player steers with the mode's bot paths (skills spread from
-- clumsy to steady), sending batches of positions like a client does, and rides its crayon (moved
-- with env.Move, the test server has no physics). One player sends junk now and then (a teleport
-- sideways, a position off the paper, a time from the future, NaN) that the server must ignore, and
-- one player leaves halfway through the ride.
--
-- Player 3 sends like the real client: every batch carries the positions the server hasn't taken
-- yet, and a quarter of its batches are lost on the way. It keeps its own live score (the one its
-- screen shows) and notes it next to the server's final one: they must match.
--
-- Wandering (owner: "On trace race you should be able to leave your own lane. They wont score points
-- but its funny"). Lanes follow the round's order of players, not the stand-ins', so each of these
-- looks at its own lane:
-- - Player 5 leaves its lane for a stretch and rides right along its neighbour's guide, then comes
--   home. The server must take those positions and score them 0. Its note gives what the stretch
--   scored, where its crayon was on the screens meanwhile, and how many of its strokes the stand-in
--   client drew in the neighbour's lane at a height the neighbour's line also uses (0, or they'd
--   flicker where they cross).
-- - Of players 6 and up, the one whose lane is nearest an outer edge of the paper steers out to that
--   edge and pushes past it, as a hacked client would: the server must take nothing off the paper.
-- - On a run with the client half (--client), its keys are held down here, through the harness's
--   UserInputService stand-in: its crayon goes over into the next lane, comes home, then out to the
--   nearest edge of the paper and pushes against it. Its note gives how far the server took it, what
--   the steering arrow said, how far the camera and its rider went, and what the time away scored.
--   With --ui-at 5,15 the phone shots catch it in the next lane and at the edge.
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

	-- Wandering -----------------------------------------------------------------------------------------
	local laneCount = 0
	for _ in mode.lanes do
		laneCount += 1
	end
	local function r1(value: number): number
		return math.floor(value * 10 + 0.5) / 10
	end
	-- Which way a player's nearest outer edge of the paper is (-1 left, 1 right), how far from its
	-- lane's middle, and its x there.
	local function nearestEdge(player: any): (number, number, number)
		local lane = mode.lanes[player]
		if -lane.Lo < lane.Hi then
			return -1, -lane.Lo, lane.Lo
		end
		return 1, lane.Hi, lane.Hi
	end
	local client = if env.client and mode.lanes[env.players[1]] then env.players[1] else nil
	local wanderer = if env.players[5] and mode.lanes[env.players[5]] then env.players[5] else nil
	local edger, edgeSide, edgeDistance, edgeX = nil, 1, math.huge, 0
	for index = 6, #env.players do
		local player = env.players[index]
		if mode.lanes[player] then
			local side, distance, x = nearestEdge(player)
			if distance < edgeDistance then
				edger, edgeSide, edgeDistance, edgeX = player, side, distance, x
			end
		end
	end
	-- (The edge player heads out 8 s in, pushes for 2.5 s once there, then comes home.)
	local edgeUntil = 8 + edgeDistance / (Rules.STEER * 0.9) + 0.3 + 2.5
	local edgeSent = 0 -- its positions past the edge
	local edgeNoted = false

	-- Positions a stand-in steers itself (toward a target, no faster sideways than a crayon steers),
	-- one every 0.07 s like a bot's.
	local steering = {} -- [player] = { T, X }
	local function steerTo(player: any, now: number, target: (number) -> number): { number }
		local race = mode.race
		local state = steering[player]
		if not state then
			state = { T = race.T0 - 0.07, X = 0 }
			steering[player] = state
		end
		local out = {}
		local step = Rules.STEER * 0.9 * 0.07
		while state.T + 0.07 <= now and state.T + 0.07 <= race.T1 and #out < Rules.MAX_CHUNK * 2 do
			state.T += 0.07
			state.X += math.clamp(target(state.T) - state.X, -step, step)
			table.insert(out, state.T)
			table.insert(out, state.X)
		end
		return out
	end
	local function guideAt(t: number): number -- the guide a little ahead (a crayon steers a moment late)
		return Rules.GuideAt(mode.course, (t - mode.race.T0) * Rules.SPEED + 1.5)
	end
	-- Where each watched rider has been as the server took it: its x range, and what the steps it drew
	-- well away from its own guide scored (each stretch between two ticks that were both away).
	local watched = {} -- [player] = { Lo, Hi, AwaySteps, AwayGain, Was }
	local function watch(player: any)
		local track = mode.tracks[player]
		if not track then
			return
		end
		local seen = watched[player]
		if not seen then
			seen = { Lo = math.huge, Hi = -math.huge, AwaySteps = 0, AwayGain = 0, Was = nil }
			watched[player] = seen
		end
		seen.Lo = math.min(seen.Lo, track.LastX)
		seen.Hi = math.max(seen.Hi, track.LastX)
		local away = Rules.Distance(mode.course, track.S, track.LastX) > Rules.ZERO + 2
		if away and seen.Was then
			seen.AwaySteps += track.Count - seen.Was.Count
			seen.AwayGain += track.Sum - seen.Was.Sum
		end
		seen.Was = if away then { Count = track.Count, Sum = track.Sum } else nil
	end
	local function scored(seen: any): string
		local flag = if seen.AwayGain ~= 0 then " NOT 0" else ""
		return `{seen.AwaySteps} steps away scored {r1(seen.AwayGain)}{flag}`
	end
	-- What the server took of a watched rider: its x range, flagged if any of it is off the paper.
	local function took(seen: any, lane: any): string
		local past = seen.Lo < lane.Lo - 0.05 or seen.Hi > lane.Hi + 0.05
		return `the server took x {r1(seen.Lo)} to {r1(seen.Hi)}{if past then " PAST THE EDGE" else ""}`
	end
	-- A crayon's tip in its lane's x, as the screens put it (the client moves every crayon itself).
	local function crayonX(player: any): number?
		local lane = mode.lanes[player]
		local crayon = lane and lane.Crayon
		if not crayon or not crayon.Parent then
			return nil
		end
		local toPivot = crayon:GetAttribute("TipToPivot")
		local tip = crayon:GetPivot() * CFrame.new(if typeof(toPivot) == "Vector3" then -toPivot else Vector3.zero)
		return lane.Frame:PointToObjectSpace(tip.Position).X
	end
	-- The lane next to a player's: on its right (on its left if it's the last lane).
	local function nextSide(player: any): number
		return if mode.lanes[player].Index == laneCount then -1 else 1
	end
	local wanderSide = if wanderer then nextSide(wanderer) else 1
	local wanderCrayon = math.huge -- the nearest its crayon came back towards home while fully over there
	local wanderNoted = false

	-- The stand-in client's keys: held here (the harness's UserInputService stand-in; the client half
	-- steers with A / D).
	local held = {}
	local keys = if client then __clientShims and __clientShims.UserInputService else nil
	if keys then
		rawset(keys, "IsKeyDown", function(_, key)
			return held[key] == true
		end)
	end
	local clientPlan = {} -- seconds into the ride, and the key held from then
	local clientEdgeUntil = 0
	local clientEdge = 0
	if client then
		local function key(side: number): EnumItem
			return if side > 0 then Enum.KeyCode.D else Enum.KeyCode.A
		end
		local side = nextSide(client)
		local edgeWay, distance, x = nearestEdge(client)
		local travel = distance / Rules.STEER + 0.3
		clientEdge = x
		clientEdgeUntil = math.max(10 + travel + 2, 15.6) -- (still at the edge for the 15 s phone shot)
		clientPlan = {
			{ 2, if laneCount > 1 then key(side) else nil }, -- over into the next lane
			{ 3.6, nil }, -- (ride straight on there)
			{ 8, if laneCount > 1 then key(-side) else nil }, -- home
			{ 9.6, nil },
			{ 10, key(edgeWay) }, -- out to the paper's nearest edge, and push against it
			{ clientEdgeUntil, key(-edgeWay) }, -- home
			{ clientEdgeUntil + travel, nil },
		}
	end
	local arrows = {} -- what the client's steering arrow said while it was away
	local cameraFar, riderFar = 0, 0 -- how far the client's camera and rider went from its lane's middle
	local clientNoted = false

	return function(elapsed)
		local race = mode.race
		if not race then
			return
		end
		local now = ctx:Now()
		local into = now - race.T0
		-- Ride along (the stand-ins' rigs follow their crayons).
		for index, player in env.players do
			if player.Parent and not (env.client and index == 1) then
				local seat = mode:_seat(player)
				if seat then
					env.Move(player, seat.Position, seat.Position + seat.LookVector)
				end
			end
		end
		for _, player in { client, wanderer, edger } do
			if player and player.Parent then
				watch(player)
			end
		end

		-- The stand-in client: its keys, and what its screen shows while it's away.
		if keys and client then
			table.clear(held)
			local key = nil
			for _, step in clientPlan do
				if into >= step[1] then
					key = step[2]
				end
			end
			if key and now <= race.T1 then
				held[key] = true
			end
			local lane = mode.lanes[client]
			local track = mode.tracks[client]
			if track and math.abs(track.LastX) > Rules.LANE / 2 + 3 then
				local gui = client.PlayerGui:FindFirstChild("MiniGame_TraceRace")
				local arrow = gui and gui:FindFirstChild("Steer", true)
				if arrow and arrow:IsA("TextLabel") and arrow.Visible and not table.find(arrows, arrow.Text) then
					table.insert(arrows, arrow.Text)
				end
				local camera = workspace.CurrentCamera
				if camera then
					local x = lane.Frame:PointToObjectSpace(camera.CFrame.Position).X
					if math.abs(x) > math.abs(cameraFar) then
						cameraFar = x
					end
				end
				local root = client.Character and client.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local x = lane.Frame:PointToObjectSpace(root.Position).X
					if math.abs(x) > math.abs(riderFar) then
						riderFar = x
					end
				end
			end
			if not clientNoted and into > clientEdgeUntil + 0.3 and watched[client] then
				clientNoted = true
				local seen = watched[client]
				local over = lane.Index + nextSide(client)
				env.note(
					`{client.Name} (lane {lane.Index}, its client, keys held here) went over into lane {over} and back, `
						.. `then to the paper's edge at x {clientEdge}: {took(seen, lane)}; {scored(seen)}; `
						.. `its arrow said {table.concat(arrows, " / ")}; `
						.. `its camera got to x {r1(cameraFar)}, its rider {r1(riderFar)}`
				)
			end
		end

		-- The wanderer: home, along its neighbour's guide, home again.
		if wanderer and wanderer.Parent then
			local lane = mode.lanes[wanderer]
			-- (Over there from about 5.5 s in: on the screens its crayon glides along the neighbour's
			-- guide, 16 +- 5 from home, and never stops at its own lane's old edge, 7.)
			if into >= 6 and into < 11.5 then
				local x = crayonX(wanderer)
				if x then
					wanderCrayon = math.min(wanderCrayon, x * wanderSide)
				end
			end
			if not wanderNoted and into > 13 and watched[wanderer] then
				wanderNoted = true
				local seen = watched[wanderer]
				-- The stand-in client's screen: the wanderer's strokes in the neighbour's lane, and the
				-- neighbour's own, with the heights each uses.
				local strokes, shared = 0, 0
				local folder = workspace:FindFirstChild("MiniGameClient")
				local lines = folder and folder:FindFirstChild("TraceRaceLines")
				local neighbour = nil
				for player, other in mode.lanes do
					if other.Index == lane.Index + wanderSide then
						neighbour = player
					end
				end
				if lines and neighbour then
					local mine = Rules.Colors[lane.Color].Color:ToHex()
					local theirs = Rules.Colors[mode.lanes[neighbour].Color].Color:ToHex()
					local theirHeights = {}
					for _, part in lines:GetChildren() do
						if part:IsA("BasePart") and part.Color:ToHex() == theirs then
							theirHeights[math.floor(part.Position.Y * 1000 + 0.5)] = true
						end
					end
					for _, part in lines:GetChildren() do
						if part:IsA("BasePart") and part.Color:ToHex() == mine then
							local x = lane.Frame:PointToObjectSpace(part.Position).X
							if x * wanderSide > Rules.LANE / 2 then
								strokes += 1
								if theirHeights[math.floor(part.Position.Y * 1000 + 0.5)] then
									shared += 1
								end
							end
						end
					end
				end
				local over = lane.Index + wanderSide
				local note = `{wanderer.Name} (lane {lane.Index}) rode lane {over}'s guide ({took(seen, lane)}): `
					.. `{scored(seen)}; over there its crayon stayed {r1(wanderCrayon)} or more from home`
				if env.client then
					note ..= `; the client drew {strokes} of its strokes in lane {over}, {shared} at a height lane {over}'s line uses`
				end
				env.note(note)
			end
		end

		-- The edge player: what the server took of its push past the paper's edge.
		if edger and not edgeNoted and into > edgeUntil + 0.5 and watched[edger] then
			edgeNoted = true
			local seen = watched[edger]
			local lane = mode.lanes[edger]
			local way = if edgeSide > 0 then "right" else "left"
			env.note(
				`{edger.Name} (lane {lane.Index}) pushed past the paper's {way} edge (x {edgeX}): `
					.. `{edgeSent} positions sent past it, {took(seen, lane)}`
			)
		end

		if not reported and now > race.T1 + 1.2 and next(mode.final) then
			reported = true
			table.clear(held)
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
			if player == wanderer then
				local samples = steerTo(player, now, function(t)
					local away = t - race.T0 >= 4 and t - race.T0 < 12
					return guideAt(t) + (if away then wanderSide * Rules.LANE else 0)
				end)
				if #samples > 0 then
					env.Action(player, "Trace", samples)
					sent += 1
				end
			elseif player == edger then
				local lane = mode.lanes[player]
				local samples = steerTo(player, now, function(t)
					local out = t - race.T0 >= 8 and t - race.T0 < edgeUntil
					return if out then edgeX + edgeSide * 3 else guideAt(t)
				end)
				for at = 2, #samples, 2 do
					if samples[at] > lane.Hi + 0.05 or samples[at] < lane.Lo - 0.05 then
						edgeSent += 1
					end
				end
				if #samples > 0 then
					env.Action(player, "Trace", samples)
					sent += 1
				end
			elseif player == resender then
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
					env.Action(player, "Trace", { now, mode.lanes[player].Hi + 10 }) -- off the paper
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

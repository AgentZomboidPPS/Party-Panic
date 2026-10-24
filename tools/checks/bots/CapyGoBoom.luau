-- Test bot for Capy Go Boom (tools/checks/round_harness.py): every stand-in player walks (env.Move, the
-- test server has no physics) toward a snack nearby or else its nearest rival, faces it, and fires BOOM
-- through the same action a client sends ("Boom" with the press time and, half the time, the direction
-- the mouse would give; the other half leaves it to the server: the way the capy faces, bent toward a
-- rival close to that line). The very first press has no direction at all and must still fire. With 3
-- or more players one leaves mid-round (their weight spills).
-- First thing, it lists anything in the arena that is solid but not drawn.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local nextShot = {}
	local reported = {}
	local left = false
	local shots, first = 0, false
	local start = {}
	return function(elapsed)
		local now = ctx:Now()
		if not reported.solid then
			reported.solid = true
			-- Nothing may be solid where nothing is drawn (owner: "invisible stuff you can jump on").
			local solid, hidden = {}, {}
			for _, part in ctx.Arena:GetDescendants() do
				if part:IsA("BasePart") and part.CanCollide then
					solid[part.Name] = (solid[part.Name] or 0) + 1
					if part.Transparency > 0.5 then
						table.insert(hidden, part:GetFullName())
					end
				end
			end
			local names = {}
			for name, count in solid do
				table.insert(names, `{name}x{count}`)
			end
			table.sort(names)
			env.note(
				`collidable: {table.concat(names, " ")}; invisible+collidable: {if #hidden > 0
					then table.concat(hidden, ", ")
					else "none"}`
			)
		end
		if not mode.mass or not mode.center then
			return
		end
		if not first and env.players[1] then
			first = true -- a press with no direction: still a shot (the way the capy faces)
			env.Action(env.players[1], "Boom", now)
		end
		local center = mode.center
		local Rules = mode.Rules
		for _, player in env.players do
			if not env.Alive(player) or mode.mass[player] == nil then
				continue
			end
			local pos = env.Root(player)
			if not pos then
				continue
			end
			start[player] = start[player] or mode.mass[player]
			-- A competent person: goes for the most worthwhile snack nearby (big ones count more, near ones
			-- count more) while shooting at rivals on the way; with nothing to eat it closes on a rival.
			local goal, goalScore, rival, rivalDistance = nil, -math.huge, nil, math.huge
			for _, snack in mode.snacks do
				if not Rules.Landed(snack, now + 0.3) then
					continue
				end
				local spot = center + Vector3.new(snack[3], 0, snack[4])
				local d = Vector3.new(spot.X - pos.X, 0, spot.Z - pos.Z).Magnitude
				local score = Rules.SNACKS[snack[2]].Mass * 1.6 - d
				if d < 40 and score > goalScore then
					goal, goalScore = Vector3.new(spot.X, pos.Y, spot.Z), score
				end
			end
			for _, other in env.players do
				if other ~= player and env.Alive(other) and mode.mass[other] ~= nil then
					local otherPos = env.Root(other)
					if otherPos then
						local d = (otherPos - pos).Magnitude
						if d < rivalDistance then
							rival, rivalDistance = otherPos, d
						end
					end
				end
			end
			-- (the real bots are in the round too: a person shoots at them as well)
			for other, _ in mode.mass do
				if other ~= player and not table.find(env.players, other) then
					local _, _, otherRoot = ctx:GetCharacter(other)
					if otherRoot then
						local d = (otherRoot.Position - pos).Magnitude
						if d < rivalDistance then
							rival, rivalDistance = otherRoot.Position, d
						end
					end
				end
			end
			local target = goal or rival
			if target then
				local flatTarget = Vector3.new(target.X, pos.Y, target.Z)
				local offset = flatTarget - pos
				local step = math.min(offset.Magnitude - (if goal then 0 else 14), 16 * 0.05)
				local nextPos = if offset.Magnitude > 1e-3 and step > 0 then pos + offset.Unit * step else pos
				local lookAt = if rival and rivalDistance < 45
					then Vector3.new(rival.X, nextPos.Y, rival.Z)
					else flatTarget
				if (lookAt - nextPos).Magnitude < 0.1 then
					lookAt = nextPos + Vector3.new(0, 0, -1)
				end
				env.Move(player, nextPos, lookAt)
			end
			-- Fire at a rival in range, as often as the reload allows, with an ordinary person's aim.
			if rival and rivalDistance < 45 and now >= (nextShot[player] or 0) then
				nextShot[player] = now + env.rng:NextNumber(0.95, 1.5)
				shots += 1
				if env.rng:NextNumber() < 0.5 then
					local aim = Vector3.new(rival.X - pos.X, 0, rival.Z - pos.Z)
					if aim.Magnitude > 0.1 then
						local turned = CFrame.Angles(0, env.rng:NextNumber(-0.12, 0.12), 0):VectorToWorldSpace(aim.Unit)
						env.Action(player, "Boom", now, turned.X, turned.Z)
					end
				else
					env.Action(player, "Boom", now)
				end
			end
		end
		if not left and elapsed > 25 and #env.players >= 3 then
			left = true
			local leaver = env.players[#env.players]
			env.note(`{leaver.Name} leaves weighing {mode.mass[leaver] or 0} {Rules.UNIT}`)
			env.Leave(leaver)
		end
		local bucket = math.floor(elapsed / 15)
		if bucket >= 1 and not reported[`t{bucket}`] then
			reported[`t{bucket}`] = true
			local lying, total, top, low, pops = 0, 0, 0, math.huge, 0
			for _ in mode.snacks do
				lying += 1
			end
			for player, mass in mode.mass do
				total += mass
				top, low = math.max(top, mass), math.min(low, mass)
				pops += mode.pops[player] or 0
			end
			env.note(
				`{math.floor(elapsed)}s: weight {total} {Rules.UNIT} (top {top}, lowest {low}), pops {pops}, snacks lying {lying}`
			)
		end
		-- Near the end: how the stand-in players (the competent-human reference) did against the real bots.
		if elapsed > 70 and not reported.groups then
			reported.groups = true
			local groups = {
				Players = { n = 0, mass = 0, shots = 0, pops = 0 },
				Bots = { n = 0, mass = 0, shots = 0, pops = 0 },
			}
			local best, bestMass = nil, -1
			for player, mass in mode.mass do
				local group = if string.sub(player.Name, 1, 4) == "Bot_" then groups.Bots else groups.Players
				group.n += 1
				group.mass += mass
				group.shots += mode.shots[player] or 0
				group.pops += mode.pops[player] or 0
				if mass > bestMass then
					best, bestMass = player, mass
				end
			end
			local function line(label, g)
				if g.n == 0 then
					return `{label}: none`
				end
				return `{label} {g.n}: avg {math.floor(g.mass / g.n)} {Rules.UNIT}, {math.floor(g.shots / g.n)} shots, hit {math.floor(
					100 * g.pops / math.max(g.shots, 1)
				)}%`
			end
			env.note(
				`GROUPS {line("stand-ins", groups.Players)} | {line("bots", groups.Bots)} | leader {best and best.Name or "?"}`
			)
		end
		if elapsed > 40 and not reported.stats then
			reported.stats = true
			local lying, total, pops, gained = 0, 0, 0, 0
			for _ in mode.snacks do
				lying += 1
			end
			for player, mass in mode.mass do
				total += mass
				pops += mode.pops[player] or 0
				gained += mass - (start[player] or mass)
			end
			env.note(
				`presses {shots}, shells in flight {#mode.shells}, pops {pops}, weight {total} {Rules.UNIT} (gained {gained}), snacks lying {lying}`
			)
		end
	end
end

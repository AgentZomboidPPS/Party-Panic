-- Test bot for Struggle (tools/checks/round_harness.py): every stand-in player walks (env.Move, the
-- test server has no physics) toward loose orbs nearby or else its nearest rival, faces it, and
-- swings through the same actions a client sends ("Charge" with the press time, "Swing" with the
-- release time; some held long enough to charge). The very first is a release with no press before
-- it (as when the press came during the 3-2-1 and was refused): it must still swing. With 3 or more players one leaves mid-round (their orbs spill).
-- First thing, it lists anything in the arena that is solid but not drawn.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local holdUntil, nextSwing = {}, {}
	local presses, early = 0, false
	local reported = {}
	local left = false
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
		if not early and env.players[1] then
			early = true -- a release whose press never arrived: still a swing (a tap)
			env.Action(env.players[1], "Swing", now)
		end
		if not mode.held or not mode.center then
			return
		end
		local center = mode.center
		local Rules = mode.Rules
		for _, player in env.players do
			if not env.Alive(player) or mode.held[player] == nil then
				continue
			end
			local root = env.Root(player)
			if not root then
				continue
			end
			local pos = root
			-- Goal: an orb within 12 studs, else the nearest rival.
			local goal, rival, rivalDistance = nil, nil, math.huge
			for _, orb in mode.orbs do
				local spot = center + Vector3.new(orb[3], 0, orb[4])
				local d = Vector3.new(spot.X - pos.X, 0, spot.Z - pos.Z).Magnitude
				if d < 12 and (not goal or d < (goal - pos).Magnitude) then
					goal = Vector3.new(spot.X, pos.Y, spot.Z)
				end
			end
			for _, other in env.players do
				if other ~= player and env.Alive(other) and mode.held[other] ~= nil then
					local otherRoot = env.Root(other)
					if otherRoot then
						local d = (otherRoot - pos).Magnitude
						if d < rivalDistance then
							rival, rivalDistance = otherRoot, d
						end
					end
				end
			end
			local target = goal or rival
			if target then
				local flatTarget = Vector3.new(target.X, pos.Y, target.Z)
				local offset = flatTarget - pos
				local step = math.min(offset.Magnitude - (if goal then 0 else 3.5), 16 * 0.05)
				local nextPos = if offset.Magnitude > 1e-3 and step > 0 then pos + offset.Unit * step else pos
				local lookAt = if rival then Vector3.new(rival.X, nextPos.Y, rival.Z) else flatTarget
				if (lookAt - nextPos).Magnitude < 0.1 then
					lookAt = nextPos + Vector3.new(0, 0, -1)
				end

				env.Move(player, nextPos, lookAt)
			end
			-- Swing at a rival in reach.
			if holdUntil[player] then
				if now >= holdUntil[player] then
					holdUntil[player] = nil
					env.Action(player, "Swing", now)
				end
			elseif rival and rivalDistance < Rules.RANGE + 1 and now >= (nextSwing[player] or 0) then
				env.Action(player, "Charge", now)
				presses += 1
				local charged = env.rng:NextNumber() < 0.3
				holdUntil[player] = now + (if charged then Rules.CHARGE + 0.1 else 0.1)
				nextSwing[player] = now + env.rng:NextNumber(0.9, 1.6)
			end
		end
		if not left and elapsed > 25 and #env.players >= 3 then
			left = true
			local leaver = env.players[#env.players]
			env.note(`{leaver.Name} leaves holding {mode.held[leaver] or 0} orbs`)
			env.Leave(leaver)
		end
		if elapsed > 40 and not reported.stats then
			reported.stats = true
			local loose, total, hits = 0, 0, 0
			for _ in mode.orbs do
				loose += 1
			end
			for player, held in mode.held do
				total += held
				hits += mode.hits[player] or 0
			end
			env.note(`presses {presses}, hits {hits}, held {total}, loose {loose}`)
		end
	end
end

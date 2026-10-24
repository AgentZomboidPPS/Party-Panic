-- Test bot for Eatsa Pizza (tools/checks/round_harness.py): every stand-in player runs (env.Move, a
-- step at a time at walking speed) to a bite spot of its team, mashes "Eat" like a client while it
-- stands on one (a little slower the further down the list it is), and when its spot pops runs to
-- the next (the nearest one no other stand-in is heading for). The stand-in client (Bot1) is left to
-- the client half. It notes the teams' shares and spots every few seconds, checks every spot is on
-- its own team's slice with food on it, one stand-in leaves mid-round (with 3 or more), and at the
-- start it lists any collidable part in the arena that isn't a visible part (there should be none).
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local Logic = mode.Logic -- (this file is bundled as is: it reaches the shared rules through the mode)
	local SPEED = 16 -- studs a second: a character's walk
	local targets = {}
	local bites, pops, badSpots = 0, 0, 0
	local reported = {}
	local function find(id)
		for _, spot in mode.spots or {} do
			if spot.Id == id then
				return spot
			end
		end
		return nil
	end
	return function(elapsed, dt)
		if not reported.collision and elapsed > 0.5 then
			reported.collision = true
			local suspicious = {}
			local solid = 0
			for _, item in ctx.Arena:GetDescendants() do
				if item:IsA("BasePart") and item.CanCollide then
					solid += 1
					if item.Transparency > 0.5 or item:IsA("MeshPart") or item:IsA("UnionOperation") then
						table.insert(suspicious, `{item:GetFullName()} ({item.ClassName}, t={item.Transparency})`)
					end
				end
			end
			env.note(`collidable parts: {solid}; invisible or mesh: {#suspicious} {table.concat(suspicious, "; ")}`)
		end
		if mode.phase == "Eat" then
			-- Every spot is on its team's slice, inside what's left of it.
			for _, spot in mode.spots do
				local slice = mode.slices[spot.Slice]
				local d = math.sqrt(spot.X * spot.X + spot.Z * spot.Z)
				if
					slice.Team ~= spot.Team
					or slice.Left < spot.Left
					or d > Logic.SpotOuter(slice.Stage, mode.radius) + 0.5 -- (as Server's _fixSpots allows)
				then
					badSpots += 1
				end
			end
			local heading = {}
			for index, player in env.players do
				if (env.client and index == 1) or not env.Alive(player) then
					continue
				end
				local member = mode.members[player]
				local position = env.Root(player)
				if not member or not position then
					continue
				end
				local target = targets[player] and find(targets[player])
				if not target then
					if targets[player] then
						pops += 1
					end
					local best, bestCost = nil, math.huge
					for _, spot in mode.spots do
						if spot.Team == member.Team then
							local goal = mode.center + Vector3.new(spot.X, 3, spot.Z)
							local cost = (goal - position).Magnitude + (if heading[spot.Id] then 20 else 0)
							if cost < bestCost then
								best, bestCost = spot, cost
							end
						end
					end
					target = best
					targets[player] = if best then best.Id else nil
				end
				if not target then
					continue
				end
				heading[target.Id] = true
				local goal = mode.center + Vector3.new(target.X, 3, target.Z)
				local flat = Vector3.new(goal.X - position.X, 0, goal.Z - position.Z)
				if flat.Magnitude > 0.5 then
					local step = flat.Unit * math.min(flat.Magnitude, SPEED * (dt or 0.05))
					env.Move(player, Vector3.new(position.X + step.X, goal.Y, position.Z + step.Z), mode.center)
				end
				if mode:_spotUnder(player) and env.rng:NextNumber() < 0.42 - index * 0.015 then
					env.Action(player, "Eat")
					bites += 1
				end
			end
		end
		local second = math.floor(elapsed / 5)
		if not reported[second] and second > 0 then
			reported[second] = true
			local parts = {}
			for _, team in mode.order do
				local count = 0
				for _, spot in mode.spots or {} do
					if spot.Team == team then
						count += 1
					end
				end
				table.insert(parts, `{team} {math.floor(mode:_teamShare(team) * 100)}% ({count} spots)`)
			end
			env.note(
				`{elapsed // 1}s: {table.concat(parts, ", ")}; {bites} bites sent, {pops} spots eaten, {badSpots} bad spot checks; phase {mode.phase}`
			)
		end
		if elapsed > 10 and #env.players >= 3 and not env.left then
			local leaver = env.players[#env.players]
			env.left = leaver
			env.note(`{leaver.Name} leaves (team {tostring(leaver:GetAttribute("PP_Team"))})`)
			env.Leave(leaver)
		end
	end
end

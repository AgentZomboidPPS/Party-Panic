-- Test bot for Eatsa Pizza (tools/checks/round_harness.py): every stand-in player walks (env.Move)
-- to a slice of its team with food left and mashes "Eat" like a client, a little slower the further
-- down the list it is; the stand-in client (Bot1) is left to the client half. It notes the teams'
-- shares every few seconds, one stand-in leaves mid-round (with 3 or more), and at the start it lists
-- any collidable part in the arena that isn't a visible part (there should be none).
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local Logic = mode.Logic -- (this file is bundled as is: it reaches the shared rules through the mode)
	local targets, stages = {}, {}
	local bites = 0
	local reported = {}
	return function(elapsed)
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
			for index, player in env.players do
				if (env.client and index == 1) or not env.Alive(player) then
					continue
				end
				local member = mode.members[player]
				local state = member and mode.teams[member.Team]
				if not state then
					continue
				end
				local target = targets[player]
				if not target or mode.slices[target].Left <= 0 then
					target = nil
					for k = 0, #state.Slices - 1 do
						local slice = state.Slices[(index + k) % #state.Slices + 1]
						if mode.slices[slice].Left > 0 then
							target = slice
							break
						end
					end
					targets[player] = target
				end
				-- (Steps in as the slice is bitten back towards its tip.)
				local stage = target and mode.slices[target].Stage
				if target and stages[player] ~= `{target}:{stage}` then
					stages[player] = `{target}:{stage}`
					do
						local slice = mode.slices[target]
						local spot = mode.center
							+ Logic.StandSpot(target, slice.Stage, mode.radius, (index % 3) - 1)
							+ Vector3.new(0, 3, 0)
						env.Move(player, spot, mode.center + Vector3.new(0, 3, 0))
					end
				end
				if target and env.rng:NextNumber() < 0.42 - index * 0.015 then
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
				table.insert(parts, `{team} {math.floor(mode:_teamShare(team) * 100)}%`)
			end
			env.note(`{elapsed // 1}s: {table.concat(parts, ", ")}; {bites} bites sent; phase {mode.phase}`)
		end
		if elapsed > 10 and #env.players >= 3 and not env.left then
			local leaver = env.players[#env.players]
			env.left = leaver
			env.note(`{leaver.Name} leaves (team {tostring(leaver:GetAttribute("PP_Team"))})`)
			env.Leave(leaver)
		end
	end
end

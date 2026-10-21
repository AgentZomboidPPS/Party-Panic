-- Test bot for Arrow Ambush (tools/checks/round_harness.py). Stand-in archers shoot at runners
-- (with a little error) as fast as the cooldown allows, plus one wild shot at a board now and
-- then; stand-in runners stroll the courtyard and half of them sidestep arrows coming down near
-- them. No physics in Luau execution, so runners move with env.Move.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local goals = {}
	local nextShot = {}
	local shots, sidesteps = 0, 0
	local reported = false

	return function(elapsed)
		local layout = env.SharedJSON("Layout")
		if not layout then
			return
		end
		local now = ctx:Now()
		local bounds = layout.Bounds
		for index, player in env.players do
			if not env.Alive(player) then
				continue
			end
			local role = env.Mine(player, "Role")
			local position = env.Root(player)
			if not position then
				continue
			end
			if role == "Archer" then
				if now >= (nextShot[player] or 0) then
					nextShot[player] = now + layout.Cooldown + 0.05
					local targets = {}
					for _, other in env.players do
						if env.Alive(other) and env.Mine(other, "Role") == "Runner" and env.Root(other) then
							table.insert(targets, env.Root(other))
						end
					end
					local x, z
					if #targets > 0 and env.rng:NextNumber() < 0.85 then
						local spot = targets[env.rng:NextInteger(1, #targets)]
						x = spot.X + env.rng:NextNumber(-2.5, 2.5)
						z = spot.Z + env.rng:NextNumber(-2.5, 2.5)
					else
						x = env.rng:NextNumber(bounds[1], bounds[2])
						z = env.rng:NextNumber(bounds[3], bounds[4])
					end
					env.Action(player, "Shoot", x, z)
					shots += 1
				end
			elseif role == "Runner" then
				local goal = goals[player]
				if not goal or (Vector3.new(goal.X - position.X, 0, goal.Z - position.Z)).Magnitude < 0.6 then
					goal = Vector3.new(
						env.rng:NextNumber(bounds[1] + 2, bounds[2] - 2),
						layout.Floor + 3,
						env.rng:NextNumber(bounds[3] + 2, bounds[4] - 2)
					)
					goals[player] = goal
				end
				if index % 2 == 0 and mode then
					for _, arrow in mode.arrows do
						if arrow.Board == 0 and arrow.T1 > now and arrow.T1 - now < 0.5 then
							local away = Vector3.new(position.X - arrow.To.X, 0, position.Z - arrow.To.Z)
							if away.Magnitude < layout.Hit + 1 then
								local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)
								goal = Vector3.new(
									math.clamp(position.X + dir.X * 6, bounds[1] + 1, bounds[2] - 1),
									layout.Floor + 3,
									math.clamp(position.Z + dir.Z * 6, bounds[3] + 1, bounds[4] - 1)
								)
								goals[player] = goal
								sidesteps += 1
								break
							end
						end
					end
				end
				local step = Vector3.new(goal.X - position.X, 0, goal.Z - position.Z)
				local move = if step.Magnitude > 0.8 then step.Unit * 0.8 else step
				local nextPosition = Vector3.new(position.X + move.X, layout.Floor + 3, position.Z + move.Z)
				env.Move(
					player,
					nextPosition,
					nextPosition + (if move.Magnitude > 0.01 then move else Vector3.new(0, 0, -1))
				)
			end
		end
		if elapsed > 12 and not reported then
			reported = true
			env.note(
				`{shots} shots, {sidesteps} sidesteps, runners left {tostring(mode and mode:RunnersLeft())}, arrows {mode and #mode.arrows or 0}`
			)
		end
	end
end

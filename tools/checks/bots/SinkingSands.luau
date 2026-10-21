-- Test bot for Sinking Sands (tools/checks/round_harness.py). Stand-in Divers walk to treasure on
-- the sand, dragged by the sand exactly as a player's device drags its own character, and one in a
-- while one wanders into the sinkhole; stand-in Sand Kings press SWIRL and PULL. Luau execution has
-- no physics, so bots move rigs with env.Move (on the sand's surface).
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local SandSwirl = mode.Swirl
	local center = mode.center
	local step = 0.05
	local plans = {}
	local presses = { Swirl = 0, Pull = 0 }
	local reported = false

	return function(elapsed)
		local now = ctx:Now()
		for index, player in env.players do
			if not env.Alive(player) then
				continue
			end
			if mode:IsKing(player) then
				if env.rng:NextNumber() < 0.03 then
					env.Action(player, "Swirl")
					presses.Swirl += 1
				elseif env.rng:NextNumber() < 0.02 then
					env.Action(player, "Pull")
					presses.Pull += 1
				end
				continue
			end
			if mode:IsGulped(player) then
				plans[player] = nil
				continue
			end
			local position = env.Root(player)
			if not position then
				continue
			end
			local offset = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
			local r = offset.Magnitude
			-- Pick a goal: the nearest treasure, or (now and then) the sinkhole itself.
			local plan = plans[player]
			if not plan or os.clock() > plan.Until then
				local goal = nil
				if index % 3 == 0 and env.rng:NextNumber() < 0.08 then
					goal = "Hole"
				else
					local best, bestDistance = nil, math.huge
					for id, item in mode.items do
						if now >= item.T then
							local d = (mode:ItemPosition(item, now) - position).Magnitude
							if d < bestDistance then
								best, bestDistance = id, d
							end
						end
					end
					goal = best
				end
				plan = { Goal = goal, Until = os.clock() + 1.5 }
				plans[player] = plan
			end
			local target = nil
			if plan.Goal == "Hole" then
				target = center
			elseif plan.Goal and mode.items[plan.Goal] then
				target = mode:ItemPosition(mode.items[plan.Goal], now + 0.3)
			end
			local move = Vector3.zero
			if target then
				local flat = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
				if flat.Magnitude > 0.3 then
					move = flat.Unit * math.min(flat.Magnitude, 16 * step)
				end
			end
			-- The sand's drag (what the client half does for a real player).
			if r > 0.05 and r < SandSwirl.RIM + SandSwirl.EDGE then
				local inward, spin = SandSwirl.WalkerFlow(mode.segments, r, now)
				local u = offset / r
				move += (-u * inward + Vector3.new(-u.Z, 0, u.X) * spin) * step
			end
			local after = offset + move
			local y = center.Y + SandSwirl.Height(after.Magnitude) + 3
			if after.Magnitude < SandSwirl.HOLE then
				y = center.Y - SandSwirl.DEPTH -- falls into the sinkhole
			end
			env.Move(player, Vector3.new(center.X + after.X, y, center.Z + after.Z), center)
		end
		if elapsed > 30 and not reported then
			reported = true
			local divers, kings = 0, 0
			for _, player in env.players do
				if mode:IsKing(player) then
					kings += 1
				else
					divers += 1
				end
			end
			local scores = ctx.TeamScores or {}
			local items = 0
			for _ in mode.items do
				items += 1
			end
			env.note(
				`kings {kings} divers {divers}; presses swirl {presses.Swirl} pull {presses.Pull}; team scores Divers {scores.Divers or 0} SandKings {scores.SandKings or 0}; items on sand {items}; segments {#mode.segments}`
			)
		end
	end
end

-- Scenario for round_harness.py --bot: the dust bag, step by step, on a real server. The boss is made to
-- SUCK; three stand-ins are put at its mouth and must end up in the bag; one of them then leaves while
-- inside it (the bag must let go of the slot, and the round carries on); a fourth then throws a brick at
-- the bag (BAG) and the rest must be freed, with the rescue scored. Each stage is a note ("bag: ...").
--
--   python3 tools/checks/round_harness.py BigBadVacuum --players 5 --seconds 24 \
--       --bot tools/checks/scenarios/BigBadVacuum_bag.luau > /tmp/bag.luau
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local Rules = __require("Shared/Logic/BigBadVacuum")
	local stage = 0
	local mark = 0
	local function note(text)
		env.note("bag: " .. text)
	end
	return function(elapsed)
		local boss = mode.boss
		if not boss then
			return
		end
		local y = mode.center.Y + 3
		if stage == 0 and boss.State == "Chase" and elapsed > 6.5 then
			stage = 1
			boss.Until = math.huge
			mode:_beginAttack(ctx:Now(), "Suction")
			note("suction started")
		elseif stage == 1 and boss.State == "Act" then
			local mx, mz = Rules.MouthAt(boss.X, boss.Z, boss.Plan.Face)
			for index = 1, 3 do
				env.Move(env.players[index], Vector3.new(mx + (index - 2) * 2, y, mz), Vector3.new(boss.X, y, boss.Z))
			end
			stage, mark = 2, elapsed
		elseif stage == 2 and elapsed > mark + 0.8 then
			local held = {}
			for index = 1, 3 do
				table.insert(held, `{env.players[index].Name}={tostring(mode:IsTrapped(env.players[index]))}`)
			end
			note(`trapped now {mode:TrappedCount()} ({table.concat(held, ", ")})`)
			env.Leave(env.players[2])
			stage = 3
		elseif stage == 3 and elapsed > mark + 1.4 then
			note(
				`after Bot2 left from inside: {mode:TrappedCount()} in the bag, round running: {tostring(
					ctx:IsRunning()
				)}`
			)
			local thrower = env.players[4]
			mode.carry[thrower] = ctx:Now()
			env.Action(thrower, "Throw", "Bag")
			note(`Bot4 throws at the bag, flights up: {#mode.flights}`)
			stage = 4
		elseif stage == 4 and elapsed > mark + 3.4 then
			local thrower = env.players[4]
			local stat = mode.stats[thrower]
			note(
				`after the throw: {mode:TrappedCount()} in the bag; Bot4 rescues {if stat then stat.Rescues else "?"}; `
					.. `score {ctx.Participants[thrower] and ctx.Participants[thrower].Score or "?"}, meter {math.floor(
						mode.meter
					)}`
			)
			stage = 5
		end
	end
end

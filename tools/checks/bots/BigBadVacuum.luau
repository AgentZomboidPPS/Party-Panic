-- Test bot for Big Bad Vacuum (tools/checks/round_harness.py): the stand-in players are driven by the real
-- bot brain (src/server/MiniGames/Bots/BigBadVacuum), with each stand-in given a skill, so the fight is
-- played the way a lobby of bots would play it. The stand-ins are "people" to the server, so this script
-- also does what a client does for them: it walks them (16 studs/s; Luau execution has no physics),
-- jumps (a simulated arc), applies the suction's pull to anyone in the cone, and sends THROW / PANIC.
-- The notes report the fight so a round can be checked from its summary: who threw, how the boss' health
-- went, what hit people, and how it ended.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local Rules = __require("Shared/Logic/BigBadVacuum") -- the harness bundle's module loader
	local Brain = __require("Server/MiniGames/Bots/BigBadVacuum")
	local SPEED = 16
	local JUMP_TIME, JUMP_HEIGHT = 0.75, 7
	local STEP = 0.05
	local THINK = 0.15
	local SKILL_MIN, SKILL_SPAN = 0.35, 0.55 -- (a weaker lobby: smaller numbers)

	-- The brain talks to ctx:BotAction; for a stand-in that is the same as a client's remote.
	local shim = setmetatable({}, { __index = ctx })
	function shim.BotAction(_, bot, name, ...)
		env.Action(bot, name, ...)
	end

	local people = {}
	for index, player in env.players do
		-- (the client half's own player keeps playing with the same brain: it has no human at the controls)
		player.Skill = SKILL_MIN + SKILL_SPAN * ((index * 37) % 11) / 10
		player.Memory = {}
		player.Rng = Random.new(500 + index)
		player.Goal = nil
		player.JumpStart = nil
		player.Pos = nil
		function player.Root(self)
			local position = env.Root(self)
			if not position then
				return nil
			end
			return { Position = position }
		end
		function player.MoveTo(self, position)
			self.Goal = position
		end
		function player.Stop(self)
			self.Goal = nil
		end
		function player.Jump(self)
			if not self.JumpStart then
				self.JumpStart = os.clock()
			end
		end
		function player.Reaction(self)
			return (0.85 - self.Skill * 0.6) * self.Rng:NextNumber(0.75, 1.35)
		end
		function player.Chance(self, probability)
			return self.Rng:NextNumber() < probability
		end
		people[player] = { Since = 0 }
	end

	local reported = {}
	local function report(label)
		if reported[label] then
			return
		end
		reported[label] = true
		local boss = mode.boss
		local throws, crits, rescues, dazed, damage = 0, 0, 0, 0, 0
		for _, stat in mode.stats do
			throws += stat.Throws
			crits += stat.Crits
			rescues += stat.Rescues
			dazed += stat.Dazed
			damage += stat.Damage
		end
		env.note(
			`{label}: boss {math.ceil(boss.Hp)}/{boss.Max} phase {boss.Phase} {boss.State}; `
				.. `throws {throws} crits {crits} damage {damage} rescues {rescues} dazed {dazed}; `
				.. `meter {math.floor(mode.meter)}, trapped now {mode:TrappedCount()}`
		)
	end

	-- With four or more stand-ins, one stuck in the bag leaves, and later one holding a brick does: the round
	-- must carry on (the bag lets the first go, the brick goes with the second).
	local leaveTest = if #env.players >= 4 then { Bag = false, Brick = false } else nil
	local lastOutcome = nil
	local lastPhase = 1
	local lastState = nil
	local seenAttacks = {}
	local clock = 0
	return function(elapsed)
		if not mode.boss or not mode.center then
			return
		end
		local now = ctx:Now()
		local boss = mode.boss
		clock += STEP
		if boss.Phase ~= lastPhase then
			lastPhase = boss.Phase
			env.note(`phase {boss.Phase} at {string.format("%.1f", elapsed)}s (boss {math.ceil(boss.Hp)}/{boss.Max})`)
		end
		if boss.Plan and not seenAttacks[boss.Plan.Id] then
			seenAttacks[boss.Plan.Id] = boss.Plan.Kind
		end
		if boss.State ~= lastState then
			lastState = boss.State
		end
		if mode.outcome and mode.outcome ~= lastOutcome then
			lastOutcome = mode.outcome
			report(`outcome {mode.outcome} at {string.format("%.1f", elapsed)}s`)
			local kinds = {}
			for _, kind in seenAttacks do
				kinds[kind] = (kinds[kind] or 0) + 1
			end
			local parts = {}
			for kind, n in kinds do
				table.insert(parts, `{kind} x{n}`)
			end
			table.sort(parts)
			env.note("attacks: " .. table.concat(parts, ", "))
		end
		for _, mark in { 25, 50, 75 } do
			if elapsed >= mark then
				report(`at {mark}s`)
			end
		end

		if leaveTest and elapsed > 8 then
			for _, player in env.players do
				if player ~= env.players[1] and env.Alive(player) then
					if not leaveTest.Bag and mode:IsTrapped(player) then
						leaveTest.Bag = true
						env.note(`{player.Name} leaves from inside the bag ({mode:TrappedCount()} in it)`)
						env.Leave(player)
						break
					elseif leaveTest.Bag and not leaveTest.Brick and mode:HasBrick(player) and elapsed > 20 then
						leaveTest.Brick = true
						env.note(`{player.Name} leaves holding a brick`)
						env.Leave(player)
						break
					end
				end
			end
		end

		local plan = boss.Plan
		local sucking = plan ~= nil and plan.Kind == "Suction" and boss.State == "Act"
		for _, player in env.players do
			if not env.Alive(player) then
				continue
			end
			local position = env.Root(player)
			if not position then
				continue
			end
			local entry = people[player]
			entry.Since += STEP
			local floorY = mode.center.Y + Rules.STAND
			-- The brain, about as often as a real bot's.
			if entry.Since >= THINK then
				entry.Since = 0
				local ok, err = pcall(Brain.Step, player, shim, mode, THINK)
				if not ok then
					env.note("brain error: " .. tostring(err))
				end
			end
			if mode:IsTrapped(player) then
				continue -- anchored in the bag: the server holds it
			end
			local x, z = position.X, position.Z
			local dx, dz = 0, 0
			local dazed = mode:IsDazed(player, now)
			if player.Goal and not dazed then
				local gx, gz = player.Goal.X - x, player.Goal.Z - z
				local m = math.sqrt(gx * gx + gz * gz)
				if m > 0.3 then
					local speed = math.min(m, SPEED * STEP)
					dx, dz = gx / m * speed, gz / m * speed
				end
			end
			-- What the client does with the suction: it pulls our character toward the mouth.
			if
				sucking
				and Rules.InCone(
					boss.X,
					boss.Z,
					plan.Face,
					Rules.Attacks.Suction.Arc,
					Rules.Attacks.Suction.Reach,
					x,
					z
				)
			then
				local mx, mz = Rules.MouthAt(boss.X, boss.Z, plan.Face)
				local px, pz = mx - x, mz - z
				local m = math.max(math.sqrt(px * px + pz * pz), 0.1)
				local pull = Rules.PullSpeed(Rules.Distance(x, z, boss.X, boss.Z)) * STEP
				dx += px / m * pull
				dz += pz / m * pull
			end
			-- A simulated jump.
			local y = floorY
			if player.JumpStart then
				local t = (os.clock() - player.JumpStart) / JUMP_TIME
				if t >= 1 then
					player.JumpStart = nil
				else
					y = floorY + 4 * JUMP_HEIGHT * t * (1 - t)
				end
			end
			local nx, nz = x + dx, z + dz
			-- (nobody walks out of the arena)
			local fromMiddle = Rules.Distance(nx, nz, mode.center.X, mode.center.Z)
			if fromMiddle > mode.radius - 2 then
				nx = mode.center.X + (nx - mode.center.X) / fromMiddle * (mode.radius - 2)
				nz = mode.center.Z + (nz - mode.center.Z) / fromMiddle * (mode.radius - 2)
			end
			if math.abs(nx - x) > 1e-4 or math.abs(nz - z) > 1e-4 or math.abs(y - position.Y) > 1e-3 then
				env.Move(player, Vector3.new(nx, y, nz), Vector3.new(boss.X, y, boss.Z))
			end
		end
	end
end

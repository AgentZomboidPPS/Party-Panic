-- Test bot for Stamp Out (tools/checks/round_harness.py): the stand-in players bounce around the
-- paper like real players do. No physics in Luau execution, so this does what a player's device
-- would: a jump is an arc moved with env.Move, and a STAMP hop sends "Charge", then "Hop" with its
-- charge and direction, and flies the same arc the client flies (Logic/StampGrid.Hop). The server's
-- landing watch stamps them; the note reports stamps and coverage.
return function(env)
	local StampGrid = __require("Shared/Logic/StampGrid") -- the harness bundle's module loader
	local ctx = env.ctx
	local state = {} -- player -> { Kind, T0, Air, From, Dir, Along, Up, Next, Charge, HopAt }
	local reported = 0

	local function legs(player): number
		local _, humanoid, root = ctx:GetCharacter(player)
		if not humanoid or not root then
			return 3
		end
		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			return 3
		end
		return humanoid.HipHeight + root.Size.Y / 2
	end

	return function(elapsed)
		local paper = env.game.Paper
		if not paper then
			return
		end
		local now = os.clock()
		local gravity = workspace.Gravity
		for _, player in env.players do
			local position = env.Root(player)
			if not position or not env.Alive(player) then
				state[player] = nil
				continue
			end
			local s = state[player]
			if not s then
				s = { Next = now + env.rng:NextNumber(0, 0.6) }
				state[player] = s
			end
			local standY = paper.Y + legs(player)
			if s.Kind then
				-- In the air: follow the arc, then stand on the paper.
				local t = math.min(now - s.T0, s.Air)
				local flat = s.From + s.Dir * (s.Along * t)
				local y = standY + math.max(0, s.Up * t - gravity * t * t / 2)
				env.Move(player, Vector3.new(flat.X, y, flat.Z), Vector3.new(flat.X, y, flat.Z) + s.Dir)
				if now - s.T0 >= s.Air then
					s.Kind = nil
					s.Next = now + env.rng:NextNumber(0.15, 0.6)
				end
			elseif s.HopAt then
				if now >= s.HopAt then
					s.HopAt = nil
					local _, up, along, air = StampGrid.Hop(s.Charge, gravity)
					env.Action(player, "Hop", s.Charge, s.Dir.X, s.Dir.Z)
					s.Kind, s.T0, s.Air, s.Up, s.Along = "Hop", now, air, up, along
					s.From = Vector3.new(position.X, standY, position.Z)
				end
			elseif now >= s.Next then
				-- Head somewhere on the paper: toward a random spot, away from the edges.
				local x, z = position.X - paper.X, position.Z - paper.Z
				local half = StampGrid.PAD / 2 - 12
				local target = Vector3.new(env.rng:NextNumber(-half, half), 0, env.rng:NextNumber(-half, half))
				local dir = Vector3.new(target.X - x, 0, target.Z - z)
				dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(0, 0, -1)
				if env.rng:NextNumber() < 0.45 then
					local charge = env.rng:NextNumber(0, 1)
					local reach = StampGrid.HOP_MIN + (StampGrid.HOP_MAX - StampGrid.HOP_MIN) * charge
					if not StampGrid.OnPad(x + dir.X * reach, z + dir.Z * reach, 3) then
						charge = 0
					end
					s.Charge, s.Dir = charge, dir
					s.HopAt = now + charge * StampGrid.CHARGE_TIME + 0.05
					env.Action(player, "Charge")
				else
					-- A plain jump while walking: 0.55 s up and down, drifting 6 studs.
					local up = 26
					s.Kind, s.T0, s.Air, s.Up, s.Dir = "Jump", now, 2 * up / gravity, up, dir
					s.Along = 6 / s.Air
					if not StampGrid.OnPad(x + dir.X * 6, z + dir.Z * 6, 3) then
						s.Along = 0
					end
					s.From = Vector3.new(position.X, standY, position.Z)
				end
			end
		end
		if elapsed > reported + 10 then
			reported = elapsed
			local parts = {}
			for ink, cells in env.game.Counts or {} do
				table.insert(parts, `{StampGrid.INKS[ink].Name}:{StampGrid.Percent(cells)}%`)
			end
			env.note(
				`t={math.floor(elapsed)} stamps={env.game.Stamps or 0} hops={env.game.Hops or 0} {table.concat(
					parts,
					" "
				)}`
			)
		end
	end
end

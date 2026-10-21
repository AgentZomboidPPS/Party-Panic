-- Test bot for Shark Bait (tools/checks/round_harness.py). Luau execution has no physics, so the
-- stand-ins move with env.Move and keep their own heights: swimmers walk the decks at deck height,
-- arc over the gaps when they hop (through the gap coins) and wade at water height when they're in;
-- the server throws them off flipped rafts and lifts them onto a raft they wade into, as it does for
-- bots. Stand-in swimmers go for coins, now and then jump in for one in the water, and half of them
-- hop off a raft that wobbles. Stand-in sharks chase swimmers in the water and chomp them, or swim
-- up to a raft with swimmers on it and chomp it.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local layout = nil
	local plans = {}
	local chomps, hops, dives = 0, 0, 0
	local reported = false

	local function flatDistance(a: Vector3, b: Vector3): number
		return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
	end

	local function raftUnder(position: Vector3, margin: number)
		for _, raft in mode.rafts do
			if flatDistance(position, raft.Center) <= raft.Radius + margin then
				return raft
			end
		end
		return nil
	end

	local function step(position: Vector3, target: Vector3, speed: number, y: number): Vector3
		local d = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
		local move = if d.Magnitude > speed then d.Unit * speed else d
		return Vector3.new(position.X + move.X, y, position.Z + move.Z)
	end

	return function(elapsed)
		layout = layout or env.SharedJSON("Layout")
		if not layout or not mode or not mode.rafts then
			return
		end
		local now = ctx:Now()
		local deck = layout.Deck + 3
		local wet = layout.Floor + 3
		for index, player in env.players do
			if not env.Alive(player) or mode:IsGulped(player) then
				continue
			end
			local position = env.Root(player)
			if not position then
				continue
			end
			local plan = plans[player] or {}
			plans[player] = plan
			if mode:IsShark(player) then
				-- Prey in the water first, else a raft with someone on it.
				local target, raftTarget = nil, nil
				local best = math.huge
				for _, other in env.players do
					local spot = env.Root(other)
					if
						spot
						and env.Alive(other)
						and not mode:IsShark(other)
						and not mode:IsGulped(other)
						and mode:InWater(spot)
					then
						local distance = flatDistance(position, spot)
						if distance < best then
							target, best = spot, distance
						end
					end
				end
				if not target then
					best = math.huge
					for _, raft in mode.rafts do
						if raft.State == mode.READY and now >= raft.SafeUntil then
							local distance = flatDistance(position, raft.Center)
							if distance < best then
								raftTarget, best = raft, distance
							end
						end
					end
				end
				local goal = target
				if raftTarget then
					local side = Vector3.new(position.X - raftTarget.Center.X, 0, position.Z - raftTarget.Center.Z)
					side = if side.Magnitude > 0.1 then side.Unit else Vector3.new(1, 0, 0)
					goal = raftTarget.Center + side * (raftTarget.Radius + 2)
				end
				if goal then
					local nextPosition = step(position, goal, 1.1, wet)
					local look = if target then target elseif raftTarget then raftTarget.Center else goal
					env.Move(player, nextPosition, look)
					local ready = now >= mode:ChompReadyAt(player)
					local close = if target
						then flatDistance(nextPosition, target) < 4
						else raftTarget and flatDistance(nextPosition, raftTarget.Center) < raftTarget.Radius + 3
					if ready and close then
						env.Action(player, "Chomp")
						chomps += 1
					end
				end
				continue
			end

			-- Swimmers.
			if mode:InWater(position) then
				local coin = if plan.CoinId then mode.coins[plan.CoinId] else nil
				if coin and coin.Raft == 0 and coin.Position.Y < layout.Water + 1.5 then
					env.Move(player, step(position, coin.Position, 0.5, wet))
				else
					plan.CoinId = nil
					local best, bestDistance = nil, math.huge
					for _, raft in mode.rafts do
						local distance = flatDistance(position, raft.Center) - raft.Radius
						if raft.State == mode.READY and distance < bestDistance then
							best, bestDistance = raft, distance
						end
					end
					if best then
						env.Move(player, step(position, best.Center, 0.5, wet))
					end
				end
				continue
			end
			local here = raftUnder(position, 0)
			if plan.HopTo then
				-- Mid-hop: arc over the gap at jump height, land on the far deck.
				local over = raftUnder(position, -0.8)
				local y = if over and over ~= plan.HopFrom then deck else deck + 5
				local nextPosition = step(position, plan.HopTo, 0.8, y)
				env.Move(player, nextPosition)
				if flatDistance(nextPosition, plan.HopTo) < 0.5 then
					plan.HopTo = nil
				end
				continue
			end
			if not here then
				env.Move(player, Vector3.new(position.X, wet, position.Z)) -- stepped off: in the water
				continue
			end
			if here.State == mode.WOBBLING and index % 2 == 0 then
				for _, other in here.Neighbours do
					local raft = mode.rafts[other]
					if raft.State == mode.READY then
						plan.HopFrom, plan.HopTo = here, raft.Center
						hops += 1
						break
					end
				end
				continue
			end
			local coin = if plan.CoinId then mode.coins[plan.CoinId] else nil
			if not coin then
				plan.CoinId = nil
				local best = math.huge
				for id, other in mode.coins do
					local distance = flatDistance(position, other.Position)
					local onHere = other.Raft == here.Index
					local water = other.Raft == 0 and other.Position.Y < layout.Water + 1.5
					local cost = distance + (if onHere then 0 elseif water then 10 else 5)
					if water and env.rng:NextNumber() > 0.15 then
						continue
					end
					if cost < best and distance < 24 then
						plan.CoinId, best = id, cost
					end
				end
				coin = if plan.CoinId then mode.coins[plan.CoinId] else nil
			end
			if coin then
				local target = coin.Position
				if coin.Raft == here.Index then
					env.Move(player, step(position, target, 0.8, deck))
				elseif coin.Raft == 0 and target.Y < layout.Water + 1.5 then
					-- Jump in off the edge nearest the coin.
					dives += 1
					local dir = Vector3.new(target.X - here.Center.X, 0, target.Z - here.Center.Z)
					dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(1, 0, 0)
					local spot = here.Center + dir * (here.Radius + 1.2)
					env.Move(player, Vector3.new(spot.X, wet, spot.Z))
				else
					-- On another raft or over a gap: hop toward the raft beyond it.
					local landing = raftUnder(target, 3)
					if landing and landing ~= here and landing.State == mode.READY then
						plan.HopFrom, plan.HopTo = here, landing.Center:Lerp(target, 0.6)
						hops += 1
					else
						plan.CoinId = nil
					end
				end
			end
		end
		if elapsed > 20 and not reported then
			reported = true
			local flipped = 0
			for _, raft in mode.rafts do
				if raft.State ~= mode.READY then
					flipped += 1
				end
			end
			-- Collision groups: bots and sharks pass through everyone (the mode's BODY_GROUP).
			local groups = {}
			for _, player in ctx:GetPlayers() do
				local _, _, root = ctx:GetCharacter(player)
				if root then
					local role = if mode:IsShark(player) then "shark" else "swimmer"
					local key = `{role}:{root.CollisionGroup}`
					groups[key] = (groups[key] or 0) + 1
				end
			end
			local counts = {}
			for key, count in groups do
				table.insert(counts, `{key} {count}`)
			end
			table.sort(counts)
			local groupText = table.concat(counts, ", ")
			env.note(
				`{chomps} chomps, {hops} hops, {dives} dives, haul {mode.haul}/{mode.goal}, swimmers left {mode:SwimmersLeft()}, rafts down {flipped}, coins {mode:CoinCount()}, groups {groupText}`
			)
		end
	end
end

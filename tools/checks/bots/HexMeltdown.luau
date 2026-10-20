-- Bot for Hex Meltdown: on each call most bots hop to a hex of the called color; the rest stay
-- put. Luau execution has no physics, so a bot left on a sinking hex is moved into the lava.
return function(env)
	local ctx = env.ctx
	local hexes = env.game.hexes
	local plans = {}
	local lastCall = nil
	local calls, falls = 0, 0

	local function hexUnder(position)
		local best, bestDistance = nil, math.huge
		for _, hex in hexes do
			local d = Vector2.new(hex.Position.X - position.X, hex.Position.Z - position.Z).Magnitude
			if d < bestDistance then
				best, bestDistance = hex, d
			end
		end
		return best, bestDistance
	end

	local checkedClient = false
	return function()
		local call = env.SharedJSON("Call")
		-- With the client half running, a sunk hex really is lower than where the server built it.
		if env.client and not checkedClient and call and ctx:Now() > call.SinkAt + 1 and ctx:Now() < call.RiseAt then
			for _, model in ctx.Arena:GetChildren() do
				if model:IsA("Model") and model:GetAttribute("ColorIndex") and model:GetAttribute("ColorIndex") ~= call.Color then
					local cap = model:FindFirstChild("Cap")
					env.note(`client check: hex {model.Name} cap at {math.floor(cap.Position.Y - ctx.Origin.Y)} (0 = resting)`)
					checkedClient = true
					break
				end
			end
		end
		if not call then
			return
		end
		if call.Id ~= lastCall then
			lastCall = call.Id
			calls += 1
			for _, player in env.players do
				if env.Alive(player) and env.rng:NextNumber() < 0.8 then
					local options = {}
					for _, hex in hexes do
						if hex.ColorIndex == call.Color then
							table.insert(options, hex)
						end
					end
					plans[player] = options[env.rng:NextInteger(1, #options)]
				else
					plans[player] = nil
				end
			end
			env.note(`call {call.Id}: {call.Name} ({#hexes} hexes)`)
		end
		local now = ctx:Now()
		for _, player in env.players do
			if not env.Alive(player) then
				continue
			end
			local target = plans[player]
			if target and now > call.WarnAt + 0.4 and now < call.SinkAt then
				env.Move(player, target.Position + Vector3.new(env.rng:NextNumber(-2, 2), 3, env.rng:NextNumber(-2, 2)))
				plans[player] = nil
			end
			if now > call.SinkAt + 0.4 and now < call.RiseAt then
				local position = env.Root(player)
				if position and position.Y > ctx.KillY then
					local hex, distance = hexUnder(position)
					if hex and distance < 7 and hex.ColorIndex ~= call.Color then
						falls += 1
						env.Move(player, position - Vector3.new(0, 30, 0))
						env.note(`{player.Name} fell (stood on color {hex.ColorIndex}, call {call.Color}), calls so far {calls}, falls {falls}`)
					end
				end
			end
		end
	end
end

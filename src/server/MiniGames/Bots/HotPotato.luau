-- How bots play Hot Potato (contract in Bots/Default.luau). A bot holding a potato chases the nearest
-- player it may pass to (leading them a little when skilled), tags them when close and THROWs when
-- they're in range, sooner once the potato starts to glow; a clumsy bot hesitates before throwing and
-- picks its target less well. Empty-handed bots keep away from holders they've noticed (skill sets how
-- far they look and how fast they react), each veering off at its own angle so they don't flee in one
-- clump, sliding along the fence instead of into it; the clumsiest sometimes freeze for a moment.
-- Nobody stands still: with no holder near, a bot strolls round the lawn. Passes go through
-- ctx:BotAction, so the server judges them exactly like a player's.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.HotPotato)

local Brain = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Keeps a goal on the lawn: inside the fence and off the grill in the middle.
local function onLawn(mode, goal: Vector3): Vector3
	local center = mode.center
	local offset = flat(goal - center)
	local distance = offset.Magnitude
	local direction = if distance > 0.1 then offset.Unit else Vector3.new(1, 0, 0)
	distance = math.clamp(distance, 7, mode.radius - 3)
	return center + direction * distance
end

function Brain.Step(bot, ctx, mode, _dt)
	local root = bot:Root()
	if not root or not mode.center then
		return
	end
	local memory = bot.Memory
	local rng = bot.Rng
	local skill = bot.Skill
	local now = ctx:Now()
	if not memory.Veer then
		memory.Veer = rng:NextNumber(-1, 1) * 0.9 -- this bot's own way of running off
		memory.Look = 9 + 14 * skill -- how far it notices holders
		memory.LastPos = root.Position
		memory.LastMove = now
	end
	local position = root.Position

	-- Unstick: walking but not getting anywhere (against a table or bale) for a moment: sidestep.
	if (position - memory.LastPos).Magnitude > 1.5 then
		memory.LastPos = position
		memory.LastMove = now
	elseif now - memory.LastMove > 1 then
		memory.LastMove = now
		local side = flat(root.CFrame.RightVector) * (if rng:NextNumber() < 0.5 then -1 else 1)
		memory.Sidestep = onLawn(mode, position + side * 6)
		memory.SidestepUntil = now + 0.7
		if bot:Chance(0.5) then
			bot:Jump()
		end
	end
	if memory.SidestepUntil and now < memory.SidestepUntil then
		bot:MoveTo(memory.Sidestep)
		return
	end

	local potato = mode:HolderOf(bot)
	if potato then
		-- Chase someone to pass it to (re-picked every so often; skilled bots pick the nearest).
		if
			not memory.Target
			or now >= (memory.Repick or 0)
			or not potato.Holder
			or not mode:CanTake(potato, memory.Target, now)
		then
			memory.Repick = now + bot:Reaction() + 0.6
			local best, bestDistance, second = nil, math.huge, nil
			for _, player in ctx:GetAlivePlayers() do
				if player ~= bot and mode:CanTake(potato, player, now) then
					local _, _, other = ctx:GetCharacter(player)
					if other then
						local distance = flat(other.Position - position).Magnitude
						if distance < bestDistance then
							best, second, bestDistance = player, best, distance
						end
					end
				end
			end
			memory.Target = if second and rng:NextNumber() > skill + 0.2 then second else best
			memory.ThrowAt = nil
		end
		local target = memory.Target
		local targetRoot: BasePart? = nil
		if target then
			targetRoot = select(3, ctx:GetCharacter(target))
		end
		if not targetRoot then
			bot:MoveTo(onLawn(mode, position + flat(root.CFrame.LookVector) * 8))
			return
		end
		local lead = targetRoot.AssemblyLinearVelocity * (0.35 * skill)
		bot:MoveTo(targetRoot.Position + flat(lead))
		local distance = flat(targetRoot.Position - position).Magnitude
		if now < potato.LockUntil then
			return
		end
		if distance <= Rules.TAG_REACH - 0.6 then
			ctx:BotAction(bot, "Tag", target.UserId)
			return
		end
		local hot = now >= potato.FuseEnd - Rules.WARN
		local inRange = distance <= Rules.CLIENT_THROW
			and Rules.InFront(position, root.CFrame.LookVector, targetRoot.Position)
		if not inRange then
			memory.ThrowAt = nil
		elseif not memory.ThrowAt then
			-- Throws when the target stays out of reach a moment (at once when it's about to blow).
			local wait = if hot then bot:Reaction() else bot:Reaction() + rng:NextNumber(0.4, 2.2) * (1.4 - skill)
			memory.ThrowAt = now + wait
		elseif now >= memory.ThrowAt then
			memory.ThrowAt = nil
			ctx:BotAction(bot, "Throw", target.UserId)
		end
		return
	end
	memory.Target = nil

	-- Empty-handed: keep away from the holders this bot has noticed.
	if memory.FrozenUntil and now < memory.FrozenUntil then
		bot:Stop()
		return
	end
	local away = Vector3.zero
	local threat = false
	for _, other in mode.potatoes do
		local holder = other.Holder or (other.Flight and other.Flight.From)
		if holder == nil or holder == bot then
			continue
		end
		local _, _, holderRoot = ctx:GetCharacter(holder)
		if not holderRoot then
			continue
		end
		local offset = flat(position - holderRoot.Position)
		local distance = offset.Magnitude
		if distance < memory.Look then
			threat = true
			away += (if distance > 0.1 then offset.Unit else flat(root.CFrame.LookVector)) * (memory.Look - distance)
		end
	end
	if threat then
		if not memory.NoticedAt then
			memory.NoticedAt = now + bot:Reaction()
			if skill < 0.5 and bot:Chance(0.25) then
				memory.FrozenUntil = now + rng:NextNumber(0.3, 0.9) -- caught like a deer in headlights
			end
		end
		if now < memory.NoticedAt then
			bot:MoveTo(memory.Goal or onLawn(mode, position + flat(root.CFrame.LookVector) * 6))
			return
		end
		local direction = away.Unit
		-- Veer off at this bot's own angle, and slide along the fence rather than into it.
		local veer = CFrame.Angles(0, memory.Veer, 0):VectorToWorldSpace(direction)
		local fromCenter = flat(position - mode.center)
		if fromCenter.Magnitude > mode.radius - 7 then
			local outward = fromCenter.Unit
			veer -= outward * math.max(veer:Dot(outward), 0) * 1.6
			if veer.Magnitude < 0.2 then
				veer = Vector3.new(-outward.Z, 0, outward.X) * (if memory.Veer >= 0 then 1 else -1)
			end
		end
		memory.Goal = onLawn(mode, position + veer.Unit * 10)
		bot:MoveTo(memory.Goal)
		return
	end
	memory.NoticedAt = nil
	if not memory.Goal or now >= (memory.Wander or 0) or flat(memory.Goal - position).Magnitude < 2 then
		memory.Wander = now + rng:NextNumber(1.5, 3.5)
		local angle = rng:NextNumber(0, math.pi * 2)
		memory.Goal = onLawn(
			mode,
			mode.center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(8, mode.radius)
		)
	end
	bot:MoveTo(memory.Goal)
	if bot:Chance(0.01) then
		bot:Jump()
	end
end

return Brain

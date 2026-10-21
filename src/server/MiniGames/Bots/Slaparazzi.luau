-- How bots play Slaparazzi (contract in Bots/Default.luau): they push into the photo frame, aiming
-- for the gold middle (good bots get closer and go for the frame's next spot sooner), and SLAP
-- rivals in reach, mostly the ones nearer the middle than they are and mostly just before the flash.
-- They slap through ctx:BotAction like a player's client (the same range, facing and cooldown
-- checks), turning to face their target first; a slapped bot is thrown by ctx:Knockback like a
-- player and lies still until it gets up.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.Slaparazzi)

local Brain = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Brain.Step(bot, ctx, mode, _dt)
	local root = bot:Root()
	local frame = mode.frame
	if not root or not frame then
		return
	end
	local memory = bot.Memory
	local now = ctx:Now()
	if (mode.stunnedUntil[bot] or 0) > now then
		bot:Stop()
		return
	end

	-- Where to stand: the frame's middle (its next spot once a bot notices it gliding), give or take
	-- a little by skill; a new wobble every few seconds so bots don't stack on one point.
	if not memory.WobbleAt or now >= memory.WobbleAt then
		memory.WobbleAt = now + bot.Rng:NextNumber(1.5, 3.5)
		local spread = 0.6 + (1 - bot.Skill) * 3.2
		local angle = bot.Rng:NextNumber(0, math.pi * 2)
		memory.Wobble = Vector3.new(math.cos(angle), 0, math.sin(angle)) * bot.Rng:NextNumber(0, spread)
	end
	if memory.FrameShot ~= frame.Shot then
		memory.FrameShot = frame.Shot
		memory.NoticeAt = frame.T0 + bot:Reaction() * 1.5
	end
	local goalX, goalZ
	if now >= (memory.NoticeAt or 0) then
		goalX, goalZ = frame.X1, frame.Z1
	else
		goalX, goalZ = Rules.FrameAt(frame, now)
	end
	local goal = Vector3.new(goalX, root.Position.Y, goalZ) + memory.Wobble
	local toGoal = flat(goal - root.Position)
	if toGoal.Magnitude > 0.8 then
		bot:MoveTo(goal)
	else
		bot:Stop()
	end

	-- Slap someone in reach: prefer rivals nearer the middle; more eager just before the flash.
	if now < (mode.readyAt[bot] or 0) or frame.Done then
		return
	end
	local fx, fz = Rules.FrameAt(frame, now)
	local middle = Vector3.new(fx, 0, fz)
	local mine = flat(root.Position - middle).Magnitude
	local best, bestScore = nil, -math.huge
	for _, other in ctx:GetAlivePlayers() do
		if other == bot or (mode.stunnedUntil[other] or 0) > now then
			continue
		end
		local _, _, otherRoot = ctx:GetCharacter(other)
		if not otherRoot then
			continue
		end
		local distance = flat(otherRoot.Position - root.Position).Magnitude
		if distance > Rules.CLIENT_REACH - 0.5 or math.abs(otherRoot.Position.Y - root.Position.Y) > 4 then
			continue
		end
		local theirs = flat(otherRoot.Position - middle).Magnitude
		local score = (mine - theirs) - distance * 0.3
		if score > bestScore then
			best, bestScore = other, score
		end
	end
	if not best then
		return
	end
	local untilShot = frame.Shot - now
	local eager = 0.08 + bot.Skill * 0.22
	if untilShot < 2 then
		eager *= 2
	end
	if bestScore < 0 then
		eager *= 0.4 -- a rival further out than me: not worth much
	end
	if not bot:Chance(eager) then
		return
	end
	local _, _, targetRoot = ctx:GetCharacter(best)
	if targetRoot then
		local look = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
		if flat(look - root.Position).Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(root.Position, look)
		end
	end
	ctx:BotAction(bot, "Slap", best.UserId)
end

return Brain

-- How bots play Slaparazzi (contract in Bots/Default.luau): they push into the photo frame, aiming
-- for the gold middle (good bots get closer and go for the frame's next spot sooner), and SLAP
-- rivals in reach now and then, more often the ones nearer the middle than they are and just before
-- the flash, after a reaction and with a breather between slaps, so they stay beatable.
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

	-- Slap someone in reach, like a person would: not the moment they arrive (a reaction first), not
	-- every time (more often for better bots and just before the flash), not always the leader, and
	-- with a little breather after each slap. Never anyone still down from a slap.
	if now < (mode.readyAt[bot] or 0) or now < (memory.RestUntil or 0) or frame.Done then
		return
	end
	local fx, fz = Rules.FrameAt(frame, now)
	local middle = Vector3.new(fx, 0, fz)
	local mine = flat(root.Position - middle).Magnitude
	local options, total = {}, 0
	for _, other in ctx:GetAlivePlayers() do
		if other == bot or (mode.stunnedUntil[other] or 0) + 0.45 > now then
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
		-- Worth more when they're nearer the middle than me; anyone in reach is worth a little.
		local weight = math.clamp(1 + (mine - flat(otherRoot.Position - middle).Magnitude) * 0.4, 0.3, 3)
		table.insert(options, { Player = other, Root = otherRoot, Weight = weight })
		total += weight
	end
	if #options == 0 then
		memory.SeenAt = nil
		return
	end
	if not memory.SeenAt then
		memory.SeenAt = now + bot:Reaction() * 2.5 -- someone came into reach: take it in first
	end
	if now < memory.SeenAt then
		return
	end
	local eager = 0.03 + bot.Skill * 0.07
	if frame.Shot - now < 2 then
		eager *= 1.6
	end
	if not bot:Chance(eager) then
		return
	end
	local roll = bot.Rng:NextNumber(0, total)
	local pick = options[#options]
	for _, option in options do
		roll -= option.Weight
		if roll <= 0 then
			pick = option
			break
		end
	end
	local look = Vector3.new(pick.Root.Position.X, root.Position.Y, pick.Root.Position.Z)
	if flat(look - root.Position).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, look)
	end
	ctx:BotAction(bot, "Slap", pick.Player.UserId)
	memory.RestUntil = now + bot.Rng:NextNumber(0.6, 2.2) * (1.3 - bot.Skill)
	memory.SeenAt = nil
end

return Brain

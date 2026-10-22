-- Test bot for Slaparazzi (tools/checks/round_harness.py): walks the stand-in players toward the
-- photo frame at walking speed (some aim well, some badly, a few wander off) and slaps whoever is in
-- reach now and then, through the same action a client sends. Luau execution has no physics, so
-- players move with env.Move and the notes report photos, points and slaps landed so a round can be
-- checked from its summary.
--
-- Bots pass (owner: "Bots are terrible at slaparazzi"): a slap's throw is played out here, for
-- stand-ins and real bots alike, since a test server has no physics to do it: the flat speed the
-- mode gives (Rules.KNOCK) in the air for the LIFT's flight, then a tumble that loses SLIDE studs/s
-- every second, about 24 studs in all (a guess at Roblox's physics; only a real game shows the real
-- one), stopped by anything solid such as the backdrop wall. Without it a slap only stopped someone
-- for a moment, so test rounds made slapping look pointless. Nobody walks while thrown or down.
-- One stand-in plays like a sensible person, to check that bots stay beatable: it heads for the
-- NEXT spot a moment after each flash, stands in the gold middle and, in the last 2 seconds, slaps
-- a rival in reach who's in the gold or silver ring. The notes give each photo's numbers (bots'
-- points, how many were in the middle ring, overlapping bodies, bot slaps and when) and a summary
-- line at the end.
return function(env)
	local ctx = env.ctx
	local mode = env.game
	local Rules = __require("Shared/Logic/Slaparazzi") -- the harness bundle's module loader
	local SLIDE = 110 -- studs/s lost per second on the floor after landing (an estimate)
	local SENSIBLE_REACTION = 0.4 -- seconds after a flash before the sensible stand-in heads off
	local SLAP_WINDOW = 2 -- it slaps only this close to the flash...
	local SLAP_REACTION = 0.3 -- ...a moment after someone worth it comes into reach
	local aims = {}
	for index, player in env.players do
		aims[player] = if index % 5 == 0 then 9 else env.rng:NextNumber(0, 3)
	end
	local person = env.players[if env.client then 2 else 1]
	local lastPhoto = 0
	local sent = 0

	-- Throws (see the top).
	local throws = {}
	local solid = RaycastParams.new()
	solid.FilterType = Enum.RaycastFilterType.Exclude
	solid.RespectCanCollide = true
	local realKnockback = ctx.Knockback
	ctx.Knockback = function(self, player, velocity, stun)
		realKnockback(self, player, velocity, stun)
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		if stun > 0 and flat.Magnitude > 0.1 then
			throws[player] = {
				Dir = flat.Unit,
				Speed = flat.Magnitude,
				Air = 2 * math.max(velocity.Y, 0) / workspace.Gravity,
				T = 0,
			}
		end
	end
	ctx:Heartbeat(function(dt)
		local characters = {}
		for _, player in ctx:GetPlayers() do
			if player.Character then
				table.insert(characters, player.Character)
			end
		end
		solid.FilterDescendantsInstances = characters
		for player, throw in throws do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			throw.T += dt
			local speed = if throw.T <= throw.Air then throw.Speed else throw.Speed - SLIDE * (throw.T - throw.Air)
			if not root or speed <= 0 then
				throws[player] = nil
				continue
			end
			local step = throw.Dir * speed * dt
			if workspace:Raycast(root.Position, throw.Dir * (step.Magnitude + 1), solid) then
				throws[player] = nil -- against a wall
				continue
			end
			character:PivotTo(root.CFrame + step)
		end
	end)
	local function down(player, now): boolean
		return throws[player] ~= nil or (mode.stunnedUntil[player] or 0) > now
	end

	-- The numbers.
	local stats = {
		Photos = 0,
		BotPoints = 0,
		BotShots = 0,
		BotMiddle = 0,
		BotIn = 0,
		Overlaps = 0,
		Slaps = 0,
		Hits = 0,
		Late = 0,
		AtMiddle = 0,
		Arrivals = {},
		Missed = 0,
	}
	local byId = {}
	local bots = {}
	for _, player in ctx:GetPlayers() do
		byId[player.UserId] = player
		if player.IsBot then
			table.insert(bots, player)
		end
	end
	local function ringOf(player, now): number
		local frame = mode.frame
		local root = env.Root(player)
		if not frame or not root then
			return 0
		end
		local fx, fz = Rules.FrameAt(frame, now)
		return Rules.PointsFor(Vector2.new(root.X - fx, root.Z - fz).Magnitude)
	end
	local realBotAction = ctx.BotAction
	ctx.BotAction = function(self, bot, name, ...)
		if name ~= "Slap" then
			return realBotAction(self, bot, name, ...)
		end
		local now = ctx:Now()
		local targetId = ...
		local target = byId[targetId]
		local left = mode.frame.Shot - now
		local ring = if target then ringOf(target, now) else 0
		local ready, landed = mode.readyAt[bot], mode.slaps[bot] or 0
		realBotAction(self, bot, name, ...)
		if mode.readyAt[bot] ~= ready then
			stats.Slaps += 1
			stats.Late += if left <= 2.5 then 1 else 0
			stats.AtMiddle += if ring == 3 then 1 else 0
			stats.Hits += if (mode.slaps[bot] or 0) > landed then 1 else 0
		end
		return nil
	end
	local photoSeen = 0
	local lastFlash = nil
	local arrived = {}

	local sensible = { SeenShot = nil, NoticeAt = 0, Offset = Vector3.zero, SlapAt = nil }
	local function playSensibly(player, root: Vector3, now: number, frame)
		if frame.Shot ~= sensible.SeenShot then
			sensible.SeenShot = frame.Shot
			sensible.NoticeAt = now + SENSIBLE_REACTION
			local angle = env.rng:NextNumber(0, math.pi * 2)
			sensible.Offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * env.rng:NextNumber(0, 1.2)
		end
		if down(player, now) or now < (mode.stunnedUntil[player] or 0) + 0.6 then
			sensible.SlapAt = nil
			return -- thrown, getting up, then a moment to take it in
		end
		if now >= sensible.NoticeAt and not frame.Done then
			local goal = Vector3.new(frame.X1, root.Y, frame.Z1) + sensible.Offset
			local step = Vector3.new(goal.X - root.X, 0, goal.Z - root.Z)
			if step.Magnitude > 0.3 then
				env.Move(player, root + step.Unit * math.min(step.Magnitude, 16 * 0.05), goal)
				root = env.Root(player) or root
			end
		end
		if frame.Done or frame.Shot - now > SLAP_WINDOW or now < (mode.readyAt[player] or 0) then
			sensible.SlapAt = nil
			return
		end
		local best, bestScore = nil, -math.huge
		for _, other in ctx:GetAlivePlayers() do
			local there = other ~= player and env.Root(other)
			if not there or (mode.stunnedUntil[other] or 0) + 0.4 > now then
				continue
			end
			local distance = Vector3.new(there.X - root.X, 0, there.Z - root.Z).Magnitude
			local worth = ringOf(other, now)
			if distance <= Rules.CLIENT_REACH and worth >= 2 and worth * 10 - distance > bestScore then
				best, bestScore = other, worth * 10 - distance
			end
		end
		if not best then
			sensible.SlapAt = nil
			return
		end
		sensible.SlapAt = sensible.SlapAt or now + SLAP_REACTION
		if now >= sensible.SlapAt then
			sensible.SlapAt = nil
			env.Move(player, root, env.Root(best))
			env.Action(player, "Slap", best.UserId)
			sent += 1
		end
	end

	local function summary()
		table.sort(stats.Arrivals)
		local median = stats.Arrivals[math.max(1, math.ceil(#stats.Arrivals / 2))]
		local shots = math.max(stats.BotShots, 1)
		local slaps = math.max(stats.Slaps, 1)
		if #bots > 0 then
			env.note(
				string.format(
					"bots: %.2f pts a photo, middle ring at the flash %d%%, in the shot %d%%; reach the next middle %s"
						.. " after the flash (missed %d); overlapping pairs %.1f a photo",
					stats.BotPoints / shots,
					math.round(stats.BotMiddle / shots * 100),
					math.round(stats.BotIn / shots * 100),
					if median then string.format("%.1f s", median) else "-",
					stats.Missed,
					stats.Overlaps / math.max(stats.Photos, 1)
				)
			)
			env.note(
				string.format(
					"bot slaps: %d (%.1f a bot), %d%% land, %d%% in the last 2.5 s, %d%% at a middle-ring rival",
					stats.Slaps,
					stats.Slaps / #bots,
					math.round(stats.Hits / slaps * 100),
					math.round(stats.Late / slaps * 100),
					math.round(stats.AtMiddle / slaps * 100)
				)
			)
		end
		if person then
			local ranked = {}
			for _, player in ctx:GetPlayers() do
				table.insert(ranked, mode.points[player] or 0)
			end
			table.sort(ranked, function(a, b)
				return a > b
			end)
			local mine = mode.points[person] or 0
			env.note(
				`sensible stand-in {person.Name}: {mine} pts, place {table.find(ranked, mine)} of {#ranked} (best {ranked[1]})`
			)
		end
	end

	return function()
		local frame = env.SharedJSON("Frame")
		if not frame or not mode.frame then
			return
		end
		local now = ctx:Now()
		local fx, fz = Rules.FrameAt(frame, now)
		for index, player in env.players do
			if not env.Alive(player) or (index == 1 and env.client) then
				continue
			end
			local root = env.Root(player)
			if not root then
				continue
			end
			if player == person then
				playSensibly(player, root, now, mode.frame)
				continue
			end
			if down(player, now) then
				continue
			end
			local angle = index * 2.4
			local goal = Vector3.new(fx + math.cos(angle) * aims[player], root.Y, fz + math.sin(angle) * aims[player])
			local step = goal - root
			local flatStep = Vector3.new(step.X, 0, step.Z)
			if flatStep.Magnitude > 0.3 then
				local move = flatStep.Unit * math.min(flatStep.Magnitude, 16 * 0.05)
				env.Move(player, root + move, goal)
			end
			if env.rng:NextNumber() < 0.04 then
				for _, other in env.players do
					local there = other ~= player and env.Alive(other) and env.Root(other)
					if there and Vector3.new(there.X - root.X, 0, there.Z - root.Z).Magnitude < 5 then
						env.Move(player, root, there)
						env.Action(player, "Slap", other.UserId)
						sent += 1
						break
					end
				end
			end
		end

		-- At each flash: how crowded the frame was, and when each bot first stood in the middle ring
		-- of the spot just photographed (since the flash before, when the NEXT disc showed it).
		local live = mode.frame
		if (mode.photo or 0) ~= photoSeen then
			photoSeen = mode.photo
			local shotX, shotZ = Rules.FrameAt(live, now)
			local roots = {}
			for _, player in ctx:GetAlivePlayers() do
				local root = env.Root(player)
				if root and Vector2.new(root.X - shotX, root.Z - shotZ).Magnitude <= Rules.RINGS[3] then
					table.insert(roots, root)
				end
			end
			for i = 1, #roots do
				for j = i + 1, #roots do
					if Vector2.new(roots[i].X - roots[j].X, roots[i].Z - roots[j].Z).Magnitude < 1.5 then
						stats.Overlaps += 1
					end
				end
			end
			if lastFlash then
				for _, bot in bots do
					if arrived[bot] then
						table.insert(stats.Arrivals, arrived[bot])
					else
						stats.Missed += 1
					end
				end
			end
			lastFlash = now
			arrived = {}
		elseif lastFlash and not live.Done then
			for _, bot in bots do
				local root = env.Root(bot)
				if
					root
					and not arrived[bot]
					and Vector2.new(root.X - live.X1, root.Z - live.Z1).Magnitude <= Rules.RINGS[1]
				then
					arrived[bot] = now - lastFlash
				end
			end
		end

		local photo = env.SharedJSON("Photo")
		if photo and photo.N ~= lastPhoto then
			lastPhoto = photo.N
			stats.Photos += 1
			local scored, landed = 0, 0
			local points = {}
			for _, shot in photo.Shots do
				points[shot.U] = shot.P
				if shot.P > 0 then
					scored += 1
				end
			end
			local botPoints, middle = 0, 0
			for _, bot in bots do
				local got = points[bot.UserId] or 0
				botPoints += got
				middle += if got == 3 then 1 else 0
				stats.BotIn += if got > 0 then 1 else 0
			end
			stats.BotPoints += botPoints
			stats.BotShots += #bots
			stats.BotMiddle += middle
			for _, count in mode.slaps do
				landed += count
			end
			env.note(
				`photo {photo.N}: {scored} scored of {#photo.Shots} near the frame; slaps sent {sent}, landed {landed}`
					.. (if #bots > 0 then `; bots {botPoints} pts, {middle} of {#bots} in the middle` else "")
					.. (if person then `; sensible stand-in +{points[person.UserId] or 0}` else "")
			)
			if photo.N == (frame.Of or 7) then
				summary()
			end
		end
	end
end

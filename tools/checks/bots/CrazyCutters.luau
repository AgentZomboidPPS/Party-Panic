-- Test bot for Crazy Cutters: every stand-in player traces the outline with the mode's bot paths
-- (skills spread from clumsy to steady), sending batches of positions like a client does. One
-- player sends junk now and then (a teleport, a position off the board, a stale batch, NaN) that the
-- server must ignore, and one player leaves halfway through the second shape.
--
-- Player 3 sends like the real client: every batch carries the positions the server hasn't taken
-- yet, and a quarter of its batches are lost on the way. It keeps its own live score (the one its
-- screen shows) and notes it next to the server's: they must match.
--
-- On a phone run (--client --touch) the stand-in client cuts with a finger: player 1's own client
-- half moves its wheel and sends its positions, as on a phone, while this bot holds the finger down
-- along its path through the client's test seam (PP_TestFinger, the board point under the finger,
-- and PP_TestFingerAt, its spot on the screen: client MiniGames/CrazyCutters). So the phone checks
-- show the magnifier as a finger cutting sees it, and the client's touch steering and sending are
-- checked too: the bot notes that client's score next to the server's.
return function(env)
	local Rules = __require("Shared/Logic/CrazyCutters") -- the harness bundle's module loader
	local ctx = env.ctx
	local mode = env.game
	local skills = {}
	for index, player in env.players do
		skills[player] = 0.35 + 0.55 * ((index - 1) % 6) / 5
	end
	local lastSend = 0
	local sent, junk, lost = 0, 0, 0
	local left = false
	local reported = {}
	local resender = env.players[3]
	local waiting = {} -- the resender's positions the server hasn't taken, flat
	local live = nil -- the resender's own tracker (what its screen shows)
	local liveIndex = 0
	local compared = {}
	local finger = if env.client and __touchMode == true then env.players[1] else nil
	local fingerDown = false
	local lastSpot: Vector2? = nil -- where the finger was put last (the client has drawn that by now)
	-- What the finger's client showed of its magnifier, measured on the stand-in's screen as the client
	-- measures it: how often it was up, how near the finger its middle came (it keeps 96 away), and how
	-- far its top stayed under the cookie panel and its right edge left of the menu column (6 at least).
	local function freshLens()
		return { Seen = 0, Nearest = math.huge, Below = math.huge, Left = math.huge, Screen = Vector2.zero }
	end
	local lens = freshLens()
	-- Where the finger touches the screen for a board point (about where a small phone draws it).
	local function screenSpot(u: number, v: number): Vector2
		return Vector2.new(math.clamp(333 + u * 19, 40, 590), math.clamp(190 - v * 19, 150, 320))
	end
	local function lift()
		if fingerDown and finger then
			fingerDown = false
			lastSpot = nil
			finger:SetAttribute("PP_TestFinger", nil)
			finger:SetAttribute("PP_TestFingerAt", nil)
		end
	end
	return function(elapsed)
		local round = mode.round
		if not round then
			return
		end
		if round.Phase == "Score" and not reported[round.Index] and mode.scores then
			reported[round.Index] = true
			local line = {}
			for _, player in env.players do
				local scores = mode.scores[player]
				if scores and scores[round.Index] then
					table.insert(line, `{player.Name}={scores[round.Index]}`)
				end
			end
			-- (The scores are final 0.6 s after the cut ends; this may print before some are in.)
			env.note(`shape {round.Index} {round.Shape}: sent {sent} batches, {junk} junk; {table.concat(line, " ")}`)
		end
		-- The finger's client: the score its panel shows for this cookie, next to the server's.
		local fingerScores = finger and mode.scores and mode.scores[finger]
		if fingerScores and fingerScores[round.Index] and not compared["finger" .. round.Index] then
			compared["finger" .. round.Index] = true
			local gui = env.localPlayer and env.localPlayer.PlayerGui:FindFirstChild("MiniGame_CrazyCutters")
			local label = gui and gui:FindFirstChild("Score", true)
			env.note(
				`{finger.Name} cuts with a finger: its panel says {if label then label.Text else "?"}, the server {fingerScores[round.Index]}%`
			)
			env.note(
				string.format(
					"its magnifier: up at %d checks on a %dx%d screen, middle >= %.0f from the finger, top >= %.0f under the panel, right edge >= %.0f left of the menu",
					lens.Seen,
					lens.Screen.X,
					lens.Screen.Y,
					lens.Nearest,
					lens.Below,
					lens.Left
				)
			)
			lens = freshLens()
		end
		if resender and live and liveIndex == round.Index and not compared[round.Index] then
			local scores = mode.scores and mode.scores[resender]
			if scores and scores[round.Index] then
				compared[round.Index] = true
				env.note(
					`{resender.Name} resends, {lost} batches lost: live {live:Score()} server {scores[round.Index]}`
						.. (if live:Score() == scores[round.Index] then " (match)" else " MISMATCH")
				)
			end
		end
		if elapsed - lastSend < 0.15 then
			return
		end
		lastSend = elapsed
		local now = ctx:Now()
		-- The resender's unconfirmed positions still go for a moment after the cut ends.
		if resender and resender.Parent and #waiting > 0 and round.Phase ~= "Cut" and now < round.T1 + 0.4 then
			local track = mode.tracks[resender]
			local batch = {}
			for at = 1, #waiting - 2, 3 do
				if not track or waiting[at] > track.LastT + 1e-4 then
					table.insert(batch, waiting[at])
					table.insert(batch, waiting[at + 1])
					table.insert(batch, waiting[at + 2])
				end
			end
			waiting = batch
			if #batch > 0 then
				env.Action(resender, "Cut", round.Index, batch)
			end
		end
		if round.Phase ~= "Cut" then
			lift()
			return
		end
		for index, player in env.players do
			if not player.Parent then
				continue
			end
			if player == finger then
				-- The finger follows this player's path (its client's wheel copies its moves); it
				-- lifts once the server has the whole cut.
				local playerGui = env.localPlayer and env.localPlayer.PlayerGui
				local gui = playerGui and playerGui:FindFirstChild("MiniGame_CrazyCutters")
				local bubble = gui and gui:FindFirstChild("Magnifier")
				if gui and bubble and bubble.Visible and lastSpot then
					local origin = gui.AbsolutePosition
					local middle = Vector2.new(bubble.Position.X.Offset, bubble.Position.Y.Offset)
					local half = bubble.Size.X.Offset / 2
					lens.Seen += 1
					lens.Screen = gui.AbsoluteSize
					lens.Nearest = math.min(lens.Nearest, (middle - lastSpot).Magnitude)
					local panel = gui:FindFirstChild("CutPanel", true)
					if panel then
						local bottom = panel.AbsolutePosition.Y + panel.AbsoluteSize.Y - origin.Y
						lens.Below = math.min(lens.Below, middle.Y - half - bottom)
					end
					local main = playerGui:FindFirstChild("PartyPanicHUD")
					local menu = main and main:FindFirstChild("Menu")
					if menu then
						lens.Left = math.min(lens.Left, menu.AbsolutePosition.X - origin.X - (middle.X + half))
					end
				end
				local samples = mode:BotSamples(player, skills[player], env.rng, now)
				if samples then
					local u, v = samples[#samples - 1], samples[#samples]
					fingerDown = true
					lastSpot = screenSpot(u, v)
					player:SetAttribute("PP_TestFinger", Vector2.new(u, v))
					player:SetAttribute("PP_TestFingerAt", lastSpot)
				elseif mode.tracks[player] and mode.tracks[player].Done then
					lift()
				end
			elseif player == resender then
				if liveIndex ~= round.Index then
					liveIndex = round.Index
					live = Rules.Tracker(Rules.Get(round.Shape) :: Rules.Shape)
					waiting = {}
				end
				local samples = mode:BotSamples(player, skills[player], env.rng, now) or {}
				for at = 1, #samples - 2, 3 do
					if not live.Done then
						live:Add(samples[at + 1], samples[at + 2])
						table.move(samples, at, at + 2, #waiting + 1, waiting)
					end
				end
				-- Like the client: drop what the server has taken, send the rest (or lose it).
				local track = mode.tracks[player]
				local batch = {}
				for at = 1, #waiting - 2, 3 do
					if not track or waiting[at] > track.LastT + 1e-4 then
						table.move(waiting, at, at + 2, #batch + 1, batch)
					end
				end
				waiting = table.move(batch, math.max(1, #batch - Rules.MAX_CHUNK * 3 + 1), #batch, 1, {})
				if #waiting > 0 then
					if env.rng:NextNumber() < 0.25 then
						lost += 1
					else
						env.Action(player, "Cut", round.Index, waiting)
						sent += 1
					end
				end
			elseif index ~= 2 or env.rng:NextNumber() >= 0.15 then
				local samples = mode:BotSamples(player, skills[player], env.rng, now)
				if samples then
					env.Action(player, "Cut", round.Index, samples)
					sent += 1
				end
			else -- junk instead of this batch (the server drops it; the cut carries on after)
				junk += 1
				local kind = env.rng:NextInteger(1, 4)
				if kind == 1 then
					env.Action(player, "Cut", round.Index, { now, 6.9, -6.9 }) -- a teleport
				elseif kind == 2 then
					env.Action(player, "Cut", round.Index, { now, 40, 0 }) -- off the board
				elseif kind == 3 then
					env.Action(player, "Cut", round.Index - 1, { now, 0, 0 }) -- the last shape
				else
					env.Action(player, "Cut", round.Index, { now, 0 / 0, 0 }) -- NaN
				end
			end
		end
		if not left and round.Index == 2 and #env.players >= 4 and now > round.T0 + 3 then
			left = true
			env.note(`{env.players[4].Name} leaves mid-cut`)
			env.Leave(env.players[4])
		end
	end
end

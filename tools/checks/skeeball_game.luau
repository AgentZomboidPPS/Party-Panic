-- A Skee-Ball game on a real Roblox server, through Services/SkeeBallService with stand-in players
-- (tools/checks/round_harness.py SKEEBALL bundles it with the working tree's server code):
--   python3 tools/checks/round_harness.py SKEEBALL > skee.luau
--   python3 tools/preview/luau_task.py skee.luau - skee.json
-- Builds the lobby (the arcade with it), then Bot1 plays a full 9-ball game on machine 2 (some
-- rolls good, one too soft, one too hard), each ball rolled the moment the last was taken: a roll
-- that comes in too soon waits its turn, one far too soon is refused and answered with the balls
-- that count ("Sync"), like every other refusal (someone else on a taken machine, a wrong ball
-- number, out-of-range inputs). Then PLAY AGAIN, and that walking away, a round pulling the player
-- in and leaving free the machine, while someone sitting out keeps playing through the next
-- round's start; a quick last ball that drops in before the slow one rolled before it (the game
-- ends with both balls' points); TODAY'S BEST clearing when the day changes. Also: each machine is
-- one solid box (nobody hops into a lane), beach balls don't stay in the arcade, and every play
-- camera pose is clear of the lobby's scenery. Prints the scores.

function __runSkeeBall()
	local GameState = __require("Shared/GameState")
	GameState.Folder()
	GameState.Set("Phase", "Intermission")
	local SkeeBall = __require("Shared/Logic/SkeeBall")
	local summary: { [string]: any } = { checks = {} }
	local function check(name: string, ok: boolean, detail: any?)
		table.insert(
			summary.checks,
			`{if ok then "PASS" else "FAIL"} {name}{if detail ~= nil then ": " .. tostring(detail) else ""}`
		)
	end

	local okLobby, lobbyErr = pcall(__require("Server/World/LobbyBuilder").Build)
	summary.lobby = if okLobby then "ok" else tostring(lobbyErr)
	-- A profile to save the best in (the harness has no DataStores).
	local DataService = __require("Server/Services/DataService")
	local profiles = {}
	DataService.Get = function(player)
		return profiles[player]
	end
	DataService.Changed = function() end
	-- Stand-in players aren't real ones Roblox's analytics would take.
	__require("Server/Services/Telemetry").PlayerEvent = function() end
	local Service = __require("Server/Services/SkeeBallService")
	Service.Init()

	for index = 1, 3 do
		table.insert(__fakePlayers, __newPlayer(index))
	end
	local p1, p2, p3 = __fakePlayers[1], __fakePlayers[2], __fakePlayers[3]
	profiles[p1] = { Data = { Stats = { Best = { SkeeBall = 120 } } } }

	local CollectionService = game:GetService("CollectionService")
	local machines = {}
	for _, model in CollectionService:GetTagged("SkeeMachine") do
		machines[model:GetAttribute("SkeeIndex")] = model
	end
	check("four machines", #machines == 4, #machines)
	local board = CollectionService:GetTagged("SkeeBestBoard")[1]
	check("a TODAY'S BEST board", board ~= nil)
	-- What bodies bump into: one solid box per machine round the whole cabinet (the mesh doesn't
	-- collide), with its player's spot in front of it free.
	for index, model in machines do
		local blocker = model:FindFirstChild("Blocker")
		local solidPieces = 0
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.CanCollide and part ~= blocker then
				solidPieces += 1
			end
		end
		local box, size = model:GetBoundingBox()
		local stand = model:FindFirstChild("Stand")
		local standFree = blocker ~= nil
			and stand ~= nil
			and math.abs(blocker.CFrame:PointToObjectSpace(stand.Position).Z) > blocker.Size.Z / 2 + 0.5
		check(
			`machine {index} is one solid box`,
			blocker ~= nil and blocker.CanCollide and solidPieces == 0 and standFree,
			blocker and `{blocker.Size} vs the model's {size} at {box.Position}, other solid pieces {solidPieces}`
		)
	end
	local traps = __require("Server/World/LobbyBuilder").BallTraps
	local arcadeTrap = traps[#traps]
	check(
		"beach balls don't stay in the arcade",
		arcadeTrap ~= nil and (arcadeTrap.Center - machines[2]:GetPivot().Position).Magnitude < 14,
		arcadeTrap and `{arcadeTrap.Center} r {arcadeTrap.Radius}`
	)
	local machine = machines[2]
	local function standOf(index)
		return machines[index]:FindFirstChild("Stand").Position
	end
	local function goTo(player, position)
		player.Character:PivotTo(CFrame.new(position + Vector3.new(0, 0.6, 0)))
	end

	-- Someone far away can't take a machine; at its stand they can, once.
	goTo(p1, standOf(2) + Vector3.new(30, 0, 0))
	check("too far away to join", not Service.Join(p1, 2))
	goTo(p1, standOf(2))
	check("Bot1 takes machine 2", Service.Join(p1, 2))
	goTo(p2, standOf(2))
	check("Bot2 can't take a machine in use", not Service.Join(p2, 2))
	check(
		"machine 2 shows Bot1",
		machine:GetAttribute("SkeeUser") == p1.UserId and machine:GetAttribute("SkeeState") == "Playing"
	)
	check("its prompt is off", machine.Stand.PlayPrompt.Enabled == false)

	-- Refusals (each tells the device how many balls count: none yet).
	check("wrong ball number refused", Service.Roll(p1, 2, 0, 0.5) == nil)
	check("aim out of range refused", Service.Roll(p1, 1, 3, 0.5) == nil)
	check("power out of range refused", Service.Roll(p1, 1, 0, -2) == nil)
	check("a string refused", Service.Roll(p1, 1, "0", 0.5) == nil)
	local refusals = 0
	for _, event in __events do
		if event.remote == "SkeeBall" and event.args[1] == "Sync" and event.to == "Bot1" and event.args[3] == 0 then
			refusals += 1
		end
	end
	check("each refusal answered with the balls that count", refusals == 4, refusals)

	-- Nine balls: aim, power.
	local inputs = {
		{ 0, 0.54 },
		{ 0.12, 0.6 },
		{ -0.86, 0.87 },
		{ 0.86, 0.87 },
		{ 0, 0.02 },
		{ 0, 1 },
		{ 0.05, 0.5 },
		{ -0.3, 0.3 },
		{ 0, 0.56 },
	}
	-- The SkeeBall remote's events (the harness records them): kind, then the rest.
	local function skeeEvents(kind: string): { any }
		local list = {}
		for _, event in __events do
			if event.remote == "SkeeBall" and event.args[1] == kind then
				table.insert(list, event)
			end
		end
		return list
	end
	local function rolledAt(index: number, ball: number): number?
		local found = nil
		for _, event in skeeEvents("Rolled") do
			if event.args[2] == index and event.args[3] == ball then
				found = event.t
			end
		end
		return found
	end

	-- Each ball is rolled the moment the last one was taken, like a device whose messages a phone's
	-- ping bunched up: a roll that comes in too soon waits its turn on the server, one far too soon
	-- is refused and the device hears how many balls count ("Sync").
	summary.rolls = {}
	local expected = 0
	local started = os.clock()
	local calledAt = {}
	for ball, input in inputs do
		local path = nil
		local waited, tries = 0, 0
		while not path and waited < 8 do
			tries += 1
			calledAt[ball] = os.clock()
			path = Service.Roll(p1, ball, input[1], input[2])
			if not path then
				task.wait(0.05)
				waited += 0.05
			end
		end
		if not path then
			check(`ball {ball} rolled`, false)
			break
		end
		expected += path.Points
		table.insert(summary.rolls, {
			ball = ball,
			aim = input[1],
			power = input[2],
			pocket = path.Pocket,
			points = path.Points,
			landed = math.floor(path.Landed * 100) / 100,
			done = math.floor(path.Done * 100) / 100,
			tries = tries,
		})
	end
	local waitedForOver = 0
	while machine:GetAttribute("SkeeState") ~= "Over" and waitedForOver < 8 do
		task.wait(0.1)
		waitedForOver += 0.1
	end
	summary.gameSeconds = math.floor((os.clock() - started) * 10) / 10
	local secondAt = rolledAt(2, 2)
	check(
		"a roll that comes in too soon waits its turn",
		summary.rolls[2] and summary.rolls[2].tries == 1 and secondAt ~= nil and secondAt - calledAt[2] >= 0.4,
		`ball 2 rolled {if secondAt then math.floor((secondAt - calledAt[2]) * 100) / 100 else "never"} s after it came in`
	)
	local afterGutter = nil
	for _, event in skeeEvents("Sync") do
		if event.to == "Bot1" and event.args[2] == 2 and event.args[3] == 5 then
			afterGutter = event
		end
	end
	check(
		"a roll far too soon (right after the slow gutter ball) is refused, and the device hears what counts",
		summary.rolls[6] ~= nil and summary.rolls[6].tries > 1 and afterGutter ~= nil,
		if afterGutter then `{afterGutter.to}: {table.concat(afterGutter.args, ", ")}` else "no Sync with 5 balls"
	)
	summary.expected = expected
	summary.score = machine:GetAttribute("SkeeScore")
	check("score adds up", summary.score == expected, `{summary.score} vs {expected}`)
	check("game over after nine", machine:GetAttribute("SkeeState") == "Over", machine:GetAttribute("SkeeState"))
	local over = skeeEvents("Over")[1]
	check("the final score sent is the whole score", over ~= nil and over.args[4] == expected, over and over.args[4])
	check("a tenth ball is refused", Service.Roll(p1, 10, 0, 0.5) == nil)
	local saved = profiles[p1].Data.Stats.Best.SkeeBall
	check("best saved if beaten", saved == math.max(120, expected), saved)
	summary.board = board:GetAttribute("Board")
	check("on today's board", string.find(summary.board or "", "Bot1", 1, true) ~= nil, summary.board)

	-- PLAY AGAIN, a ball, then walk away.
	check("play again", Service.Again(p1))
	check("fresh game", machine:GetAttribute("SkeeScore") == 0 and machine:GetAttribute("SkeeBalls") == 0)
	check("a ball in the new game", Service.Roll(p1, 1, 0, 0.55) ~= nil)
	goTo(p1, standOf(2) + Vector3.new(0, 0, 15))
	task.wait(0.8)
	check(
		"walking away frees the machine",
		Service.SessionOf(p1) == nil and machine:GetAttribute("SkeeState") == "Idle"
	)
	check("its prompt is back", machine.Stand.PlayPrompt.Enabled == true)
	task.wait(2)
	check("the ball dropping in after leaving scores nothing", machine:GetAttribute("SkeeScore") == 0)

	-- A round pulls the player in.
	goTo(p2, standOf(3))
	check("Bot2 takes machine 3", Service.Join(p2, 3))
	p2:SetAttribute("PP_InRound", true)
	p2:SetAttribute("PP_Alive", true)
	task.wait(0.2)
	check("a round frees the machine", Service.SessionOf(p2) == nil and machines[3]:GetAttribute("SkeeState") == "Idle")
	check("someone in a round can't play", not Service.Join(p2, 3))
	p2:SetAttribute("PP_InRound", false)

	-- Out of the round (back in the lobby), and then the Preparing phase of the next.
	goTo(p3, standOf(4))
	check("Bot3 takes machine 4", Service.Join(p3, 4))
	p3:SetAttribute("PP_InRound", true)
	p3:SetAttribute("PP_Alive", false)
	task.wait(0.2)
	check("a round (PP_InRound) frees machine 4", Service.SessionOf(p3) == nil)
	p3:SetAttribute("PP_InRound", false)
	check("Bot3 back in the lobby can play", Service.Join(p3, 4))
	-- Sitting out: the next round starts without them, and they keep rolling.
	p3:SetAttribute("PP_SitOut", true)
	GameState.Set("Phase", "Preparing")
	task.wait(0.2)
	check("sitting out, the next round leaves the game alone", Service.SessionOf(p3) ~= nil)
	check("and its rolls still count", Service.Roll(p3, 1, 0, 0.55) ~= nil)
	GameState.Set("Phase", "Intermission")
	-- Leaving the game.
	Service.End(p3, "Gone")
	check("leaving frees machine 4", machines[4]:GetAttribute("SkeeState") == "Idle")

	-- The last ball can drop in before the one rolled just before it (a quick one into the 100 cup
	-- after a slow one round the 10 ring): the game ends once both are in, with both balls' points.
	goTo(p2, standOf(3))
	check("Bot2 takes machine 3 again", Service.Join(p2, 3))
	local quickAim, quickPower = SkeeBall.Quantize(-1, 0.835)
	local slowAim, slowPower = SkeeBall.Quantize(-1, 0.96)
	local quick = SkeeBall.Path(quickAim, quickPower, SkeeBall.BALLS)
	local slow = SkeeBall.Path(slowAim, slowPower, SkeeBall.BALLS - 1)
	local raceExpected = 0
	for ball = 1, SkeeBall.BALLS do
		local power = if ball == SkeeBall.BALLS then 0.835 else 0.96
		local path = nil
		local waited = 0
		while not path and waited < 6 do
			path = Service.Roll(p2, ball, -1, power)
			if not path then
				task.wait(0.05)
				waited += 0.05
			end
		end
		raceExpected += if path then path.Points else 0
	end
	local machine3 = machines[3]
	local waitedRace = 0
	while machine3:GetAttribute("SkeeState") ~= "Over" and waitedRace < 8 do
		task.wait(0.1)
		waitedRace += 0.1
	end
	local raceOver = nil
	for _, event in skeeEvents("Over") do
		if event.args[2] == 3 then
			raceOver = event
		end
	end
	check(
		"a quick last ball waits for the slow one before it: the game ends with every ball's points",
		raceOver ~= nil and raceOver.args[4] == raceExpected and machine3:GetAttribute("SkeeScore") == raceExpected,
		`sent {raceOver and raceOver.args[4]}, machine shows {machine3:GetAttribute("SkeeScore")}, balls add up to {raceExpected} (the last ball's in {quick.Done} s, the one before {slow.Done} s)`
	)
	task.wait(0.5)
	check("nothing scores after the game's over", machine3:GetAttribute("SkeeScore") == raceExpected)
	Service.End(p2, "Gone")

	-- The day changes (UTC, like the daily gift): TODAY'S BEST starts afresh without waiting for the
	-- next game to end.
	local boardBefore = board:GetAttribute("Board")
	Service.Today.Day -= 1
	task.wait(0.5)
	check(
		"a new day clears TODAY'S BEST",
		boardBefore ~= "[]" and board:GetAttribute("Board") == "[]" and board:GetAttribute("Day") == Service.Today.Day,
		`{boardBefore} -> {board:GetAttribute("Board")}`
	)

	-- Every play camera (Shared/Logic/SkeeBallView's poses, at each machine) is clear of the lobby's
	-- scenery: nothing it can see within 1.5 studs of the lens (what's behind or beside it doesn't
	-- show), nothing between it and the rings.
	local SkeeBallView = __require("Shared/Logic/SkeeBallView")
	local lobbyRoot = workspace:FindFirstChild("Lobby")
	local arcadeModel = lobbyRoot and lobbyRoot:FindFirstChild("Arcade")
	local scenery = {}
	for _, part in if lobbyRoot then lobbyRoot:GetDescendants() else {} do
		if
			part:IsA("BasePart")
			and part.Transparency < 0.95
			and not (arcadeModel and part:IsDescendantOf(arcadeModel))
		then
			table.insert(scenery, part)
		end
	end
	local function boxDistance(part: BasePart, point: Vector3): number
		local p = part.CFrame:PointToObjectSpace(point)
		local half = part.Size / 2
		local dx = math.max(math.abs(p.X) - half.X, 0)
		local dy = math.max(math.abs(p.Y) - half.Y, 0)
		local dz = math.max(math.abs(p.Z) - half.Z, 0)
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end
	local function crosses(part: BasePart, a: Vector3, b: Vector3): boolean
		local p0 = part.CFrame:PointToObjectSpace(a)
		local d = part.CFrame:PointToObjectSpace(b) - p0
		local half = part.Size / 2
		local t0, t1 = 0, 1
		for _, axis in { "X", "Y", "Z" } do
			local origin, step, size = (p0 :: any)[axis], (d :: any)[axis], (half :: any)[axis]
			if math.abs(step) < 1e-9 then
				if math.abs(origin) > size then
					return false
				end
			else
				local near, far = (-size - origin) / step, (size - origin) / step
				if near > far then
					near, far = far, near
				end
				t0, t1 = math.max(t0, near), math.min(t1, far)
				if t0 > t1 then
					return false
				end
			end
		end
		return true
	end
	-- The nearest point of a part's box to the lens that the camera can see (in its view: the
	-- frustum, 2.2 wide per unit of height like the widest phone), sampling the box finely; nil if
	-- none of it within `reach` shows.
	local function seenWithin(part: BasePart, eye: Vector3, look: Vector3, fov: number, reach: number): number?
		local forward = (look - eye).Unit
		local right = forward:Cross(Vector3.yAxis).Unit
		local up = right:Cross(forward)
		local tanV = math.tan(math.rad(fov) / 2)
		local tanH = tanV * 2.2
		local half = part.Size / 2
		local steps = 14
		local best = nil
		for i = 0, steps do
			for j = 0, steps do
				for k = 0, steps do
					local local3 = Vector3.new(
						(i / steps * 2 - 1) * half.X,
						(j / steps * 2 - 1) * half.Y,
						(k / steps * 2 - 1) * half.Z
					)
					local d = part.CFrame:PointToWorldSpace(local3) - eye
					local distance = d.Magnitude
					if distance < reach and (best == nil or distance < best) then
						local z = d:Dot(forward)
						if z > 0.1 and math.abs(d:Dot(right)) <= z * tanH and math.abs(d:Dot(up)) <= z * tanV then
							best = distance
						end
					end
				end
			end
		end
		return best
	end
	-- The check itself: the first PC vote pose (pulled back to (0, 12, -17)) put machine 1's lens
	-- beside the vote stage's light tower, and this finds it.
	do
		local frame = machines[1]:GetAttribute("SkeeFrame")
		local eye = frame:PointToWorldSpace(Vector3.new(0, 12, -17))
		local look = frame:PointToWorldSpace(Vector3.new(0, 2, -2))
		local found = nil
		for _, part in scenery do
			if boxDistance(part, eye) < 1.5 and seenWithin(part, eye, look, 58, 1.5) then
				found = part:GetFullName()
			end
		end
		check(
			"the camera check finds the old PC vote pose's light tower",
			found ~= nil and string.find(found, "LightTower", 1, true) ~= nil,
			found
		)
	end
	summary.cameras = {}
	for index, model in machines do
		local frame = model:GetAttribute("SkeeFrame")
		local rings = frame:PointToWorldSpace(Vector3.new(0, 4.5, 4))
		local worst, worstName, nearest, nearestName, blocked = math.huge, "", math.huge, "", {}
		for name, pose in SkeeBallView.Poses do
			local eye = frame:PointToWorldSpace(Vector3.new(pose.Eye[1], pose.Eye[2], pose.Eye[3]))
			local look = frame:PointToWorldSpace(Vector3.new(pose.Look[1], pose.Look[2], pose.Look[3]))
			for _, part in scenery do
				local distance = boxDistance(part, eye)
				if distance < nearest then
					nearest, nearestName = distance, part:GetFullName()
				end
				local seen = if distance < 3 then seenWithin(part, eye, look, pose.Fov, 3) else nil
				if seen and seen < worst then
					worst, worstName = seen, `{part:GetFullName()} ({name})`
				end
				if crosses(part, eye, rings) then
					table.insert(blocked, `{name}: {part:GetFullName()}`)
				end
			end
		end
		local seenText = if worst < math.huge
			then `{worstName} at {math.floor(worst * 100) / 100}`
			else "nothing within 3 studs"
		summary.cameras[index] =
			`in view: {seenText}; nearest of all (behind or beside the lens too): {nearestName} at {math.floor(
				nearest * 100
			) / 100}`
		check(
			`machine {index}'s camera is clear of the scenery`,
			worst >= 1.5 and #blocked == 0,
			`in view: {seenText}{if #blocked > 0 then "; in the way: " .. table.concat(blocked, ", ") else ""}`
		)
	end

	-- Every pocket's path ends where it should, for a sweep of rolls (the same math the client draws).
	local counts = {}
	for aimQ = 0, 2000, 50 do
		for powerQ = 0, 1000, 25 do
			local path = SkeeBall.Path(aimQ, powerQ, 5)
			counts[path.Pocket] = (counts[path.Pocket] or 0) + 1
		end
	end
	summary.pocketsOnServer = counts

	summary.errors = __errors
	summary.eventCounts = __eventCounts
	local events = {}
	for _, event in __events do
		if event.remote == "SkeeBall" and #events < 40 then
			table.insert(events, event)
		end
	end
	summary.events = events
	return game:GetService("HttpService"):JSONEncode(summary)
end

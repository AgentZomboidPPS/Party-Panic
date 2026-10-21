-- A Skee-Ball game on a real Roblox server, through Services/SkeeBallService with stand-in players
-- (tools/checks/round_harness.py SKEEBALL bundles it with the working tree's server code):
--   python3 tools/checks/round_harness.py SKEEBALL > skee.luau
--   python3 tools/preview/luau_task.py skee.luau - skee.json
-- Builds the lobby (the arcade with it), then Bot1 plays a full 9-ball game on machine 2 (some
-- rolls good, one too soft, one too hard), checks the refusals (someone else on a taken machine,
-- a roll before the last ball landed, a wrong ball number, out-of-range inputs), PLAY AGAIN, and
-- that walking away, a round pulling the player in and leaving free the machine, while someone
-- sitting out keeps playing through the next round's start. Also: each machine is one solid box
-- (nobody hops into a lane) and beach balls don't stay in the arcade. Prints the scores.

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

	-- Refusals.
	check("wrong ball number refused", Service.Roll(p1, 2, 0, 0.5) == nil)
	check("aim out of range refused", Service.Roll(p1, 1, 3, 0.5) == nil)
	check("power out of range refused", Service.Roll(p1, 1, 0, -2) == nil)
	check("a string refused", Service.Roll(p1, 1, "0", 0.5) == nil)

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
	summary.rolls = {}
	local expected = 0
	local started = os.clock()
	for ball, input in inputs do
		local path = nil
		local waited = 0
		while not path and waited < 8 do
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
			waited = math.floor(waited * 100) / 100,
		})
		if ball == 1 then
			check("a roll before the last ball landed is refused", Service.Roll(p1, 2, 0, 0.5) == nil)
		end
	end
	summary.gameSeconds = math.floor((os.clock() - started) * 10) / 10
	task.wait(3)
	summary.expected = expected
	summary.score = machine:GetAttribute("SkeeScore")
	check("score adds up", summary.score == expected, `{summary.score} vs {expected}`)
	check("game over after nine", machine:GetAttribute("SkeeState") == "Over", machine:GetAttribute("SkeeState"))
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

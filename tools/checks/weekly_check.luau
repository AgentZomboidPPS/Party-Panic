-- The weekly leaderboard and the Hall of Fame on a real Roblox server (owner, asked what keeps players
-- coming back: "Weekly leaderboard and Hall of Fame statues of last week's top three"; then: "Can you
-- work on all of that? this wont mess with what the other workers are working on right?").
-- tools/checks/weekly_check.py bundles this with the round harness's prelude (stand-in players with
-- profiles, the recording remotes) and the working tree's modules. Nothing touches a real store: the
-- run sets workspace PP_Harness, so LeaderboardService keeps every board in memory.
--
-- It plays rounds the way RoundManager announces them (RoundEvents.Finished with Placement's
-- places, stand-in people and bots), drives LeaderboardService's loop one pass at a time on a fake
-- date, and checks: the points in the profiles, what reaches the board (writes batched, no bot, a
-- key's cooldown, a refused write tried again later, a short budget waited out), the board's order
-- and everyone's place, the week turning over (points from 0, last week's top three as statues, the
-- HallOfFame medal once the week is final, also for weeks a player left behind), the statues (built
-- from avatars, anchored, walked through, posed; an account that can't load gets a metal stand-in),
-- the toasts, and that every line of the Hall's board fits with the longest names.
function __runWeekly()
	local summary = { checks = {}, failed = {} }
	local function check(name: string, ok: boolean, detail: any?)
		local line = (if ok then "ok   " else "FAIL ") .. name
		if detail ~= nil then
			line ..= ": " .. (if type(detail) == "table" then HttpService:JSONEncode(detail) else tostring(detail))
		end
		table.insert(summary.checks, line)
		if not ok then
			table.insert(summary.failed, name)
		end
	end

	workspace:SetAttribute("PP_Harness", true) -- before anything can reach a store
	local GameState = __require("Shared/GameState")
	GameState.Folder()
	GameState.Set("Phase", "InRound")
	local DailyLogic = __require("Shared/Logic/DailyLogic")
	local WeeklyLogic = __require("Shared/Logic/WeeklyLogic")
	local Placement = __require("Shared/Logic/Placement")
	local DataService = __require("Server/Services/DataService")
	local MedalService = __require("Server/Services/MedalService")
	local Notifier = __require("Server/Services/Notifier")
	local RoundEvents = __require("Server/Services/RoundEvents")
	local HallOfFame = __require("Server/World/HallOfFame")
	local Leaderboard = __require("Server/Services/LeaderboardService")
	local H = Leaderboard.Harness

	-- What the players were given (stand-ins aren't real Players: Notifier would send them nothing).
	local medals, toasts = {}, {}
	MedalService.Award = function(player, id)
		table.insert(medals, `{player.Name}:{id}`)
	end
	Notifier.Send = function(player, text)
		table.insert(toasts, `{player.Name}: {text}`)
	end
	-- An account whose avatar Roblox won't give (an outage, a deleted account): Roblox hands out a
	-- default avatar for unknown ids, so the load is made to fail here (the Hall's Players is the
	-- harness's stand-in).
	local NO_AVATAR = 99999999999
	rawset(__playersShim, "CreateHumanoidModelFromUserId", function(_, userId)
		if userId == NO_AVATAR then
			error("harness: this avatar can't be loaded")
		end
		return RealPlayers:CreateHumanoidModelFromUserId(userId)
	end)

	-- The Hall on its own (the rest of the lobby isn't needed here).
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	lobby.Parent = workspace
	HallOfFame.Build(lobby)
	check("hall built", HallOfFame.StateForTests().built)

	-- Six people with profiles (the prelude's seeds), and four bots.
	for index = 1, 6 do
		table.insert(__fakePlayers, __newPlayer(index))
	end
	__seedProfiles()
	local people = table.clone(__fakePlayers)
	local bots = {}
	for index = 1, 4 do
		table.insert(bots, {
			IsBot = true,
			UserId = -index,
			Name = `Bot_{index}`,
			DisplayName = `🤖 Bot {index}`,
			Parent = true,
		})
	end

	-- The date: a Wednesday afternoon of this week (W).
	local W = DailyLogic.WeekNumber(os.time())
	local now = WeeklyLogic.WeekStart(W) + 2 * 86400 + 15 * 3600
	H.SetClock(function()
		return now
	end)

	-- Boards from earlier: last week's top (an account that doesn't exist, so its avatar can't load;
	-- the owner; Bot2, third), two and three weeks ago (Bot4 not in the top three, Bot3 in it), and
	-- this week's so far (two players on other servers).
	local function seed(week: number, entries: { [number]: number })
		local board = H.Memory(week)
		for id, points in entries do
			board[tostring(id)] = points
		end
	end
	seed(W - 1, { [99999999999] = 260, [11690979745] = 230, [1002] = 120, [156] = 100 })
	seed(W - 2, { [501] = 90, [502] = 80, [503] = 70, [1004] = 10 })
	seed(W - 3, { [1003] = 50, [601] = 40, [602] = 30 })
	seed(W, { [501] = 40, [777] = 12 })
	-- Their saves: Bot2 scored last week, Bot3 three weeks ago, Bot4 two weeks ago; Bot5's is from
	-- before the leaderboard (week 0).
	local function setWeekly(index: number, weekly)
		DataService.Get(people[index]).Data.Weekly = weekly
	end
	setWeekly(2, { Week = W - 1, Points = 120 })
	setWeekly(3, { Week = W - 3, Points = 50 })
	setWeekly(4, { Week = W - 2, Points = 10 })
	setWeekly(5, { Week = 0, Points = 0 })

	local function weekly(index: number)
		return DataService.Get(people[index]).Data.Weekly
	end
	local function hall()
		return GameState.GetJSON("HallOfFame")
	end
	local function topIds()
		local ids = {}
		for _, row in (hall() or {}).Top or {} do
			table.insert(ids, row.UserId)
		end
		return ids
	end
	local function waitForStatues(seconds: number)
		local deadline = os.clock() + seconds
		repeat
			task.wait(0.5)
			local busy = false
			for _, spot in HallOfFame.StateForTests().spots do
				if spot.userId ~= 0 and spot.model ~= "Statue" then
					busy = true
				end
			end
		until not busy or os.clock() > deadline
	end

	-- 1. Start: everyone's points brought to this week, last week's statues, the medals.
	Leaderboard.Init()
	H.Begin()
	GameState.Set("Phase", "Intermission")
	H.Step()
	task.wait(0.5)
	check(
		"profiles brought to this week",
		weekly(2).Week == W and weekly(2).Points == 0 and weekly(5).Week == W,
		{ weekly(2), weekly(5) }
	)
	local state = H.State()
	check("final top three of last week", state.Final[tostring(W - 1)] ~= nil, state.Final)
	check(
		"HallOfFame medal for last week (Bot2) and for a week left behind (Bot3), not Bot4",
		table.find(medals, "Bot2:HallOfFame") ~= nil
			and table.find(medals, "Bot3:HallOfFame") ~= nil
			and table.find(medals, "Bot4:HallOfFame") == nil,
		medals
	)
	check(
		"weeks checked leave the saves",
		weekly(2).Pending == nil and weekly(3).Pending == nil and weekly(4).Pending == nil,
		{ weekly(2).Pending, weekly(3).Pending, weekly(4).Pending }
	)
	local data = hall()
	local lastIds = {}
	for _, row in (data and data.LastWeek) or {} do
		table.insert(lastIds, `{row.UserId}:{row.Name}:{row.Points}`)
	end
	check(
		"last week's top three in GameState",
		data ~= nil
			and #data.LastWeek == 3
			and data.LastWeek[1].UserId == 99999999999
			and data.LastWeek[3].UserId == 1002,
		lastIds
	)
	check("this week's board from the store", topIds()[1] == 501 and topIds()[2] == 777, topIds())
	waitForStatues(25)
	local statues = HallOfFame.StateForTests()
	summary.statuesAtStart = statues.spots
	local spots = {}
	for _, spot in statues.spots do
		spots[spot.place] = spot
	end
	check(
		"statues: a metal stand-in for an avatar that can't load, the owner's own",
		spots[1] and spots[1].standIn == true and spots[2] and spots[2].model == "Statue" and spots[2].standIn == false,
		statues.spots
	)
	check(
		"statue toast for Bot2 (in the lobby)",
		#toasts > 0 and string.find(table.concat(toasts, "\n"), "Bot2: 🏆 You were #3 last week", 1, true) ~= nil,
		toasts
	)

	-- The statues as built: anchored, nothing to bump into, posed (hands up), feet on the plinths.
	local hallModel = lobby:FindFirstChild("HallOfFame")
	local statueReport = {}
	local allSafe = true
	for place = 1, 3 do
		local holder = hallModel and hallModel:FindFirstChild("Statue" .. place)
		local model = holder and holder:FindFirstChildWhichIsA("Model")
		if not model then
			allSafe = false
			continue
		end
		local box, size = model:GetBoundingBox()
		local unsafe, humanoids, joints = 0, 0, 0
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") and (not item.Anchored or item.CanCollide or item.CanQuery or item.CanTouch) then
				unsafe += 1
			elseif item:IsA("Humanoid") then
				humanoids += 1
			elseif item:IsA("JointInstance") then
				joints += 1
			end
		end
		allSafe = allSafe and unsafe == 0 and humanoids == 0 and joints == 0
		local head = model:FindFirstChild("Head") :: BasePart?
		local right = (model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")) :: BasePart?
		local left = (model:FindFirstChild("LeftHand") or model:FindFirstChild("Left Arm")) :: BasePart?
		local plinth = hallModel:FindFirstChild("Cap", true)
		statueReport[place] = {
			name = model.Name,
			bottom = math.floor((box.Position.Y - size.Y / 2) * 100) / 100,
			height = math.floor(size.Y * 100) / 100,
			head = head and math.floor(head.Position.Y * 100) / 100,
			rightHand = right and math.floor(right.Position.Y * 100) / 100,
			leftHand = left and math.floor(left.Position.Y * 100) / 100,
			unsafe = unsafe,
			humanoids = humanoids,
			joints = joints,
			plinthCap = plinth and plinth.Name,
		}
	end
	summary.statues = statueReport
	check("statues anchored, walked through, no Humanoid or joints left", allSafe, statueReport)
	local owner = statueReport[2] -- the owner's avatar (R15) stands on place 2 here
	check(
		"the owner's statue (2nd: points up) has its right hand over its head",
		owner ~= nil and owner.head ~= nil and owner.rightHand ~= nil and owner.rightHand > owner.head,
		owner
	)
	local blocky = statueReport[3] -- an R6 avatar: 3rd waves with its left arm
	check(
		"an R6 statue (3rd: waves) has its left arm raised",
		blocky ~= nil and blocky.leftHand ~= nil and blocky.rightHand ~= nil and blocky.leftHand > blocky.rightHand + 1,
		blocky
	)

	-- 2. Rounds: points by place (1st 10, 2nd 7, 3rd 5, playing 1), people only. (In the lobby phase,
	-- so each round's toasts go at once; step 7 checks them during the results.)
	local definition = { Id = "HarnessGame", Name = "Harness Game", Category = "Versus" }
	local function playRound(order: { any }, ranks: { number }?)
		local entries = {}
		for position, who in order do
			local player = if type(who) == "number" then people[who] else bots[tonumber(string.sub(who, 2)) :: number]
			table.insert(entries, {
				Key = player,
				Player = player,
				Rank = if ranks then ranks[position] else 100 - position,
				ScoreText = "",
			})
		end
		RoundEvents.Finished:Fire(definition, Placement.Assign(entries), nil)
	end
	local before = {}
	for index = 1, 6 do
		before[index] = weekly(index).Points
	end
	playRound({ 1, "b1", 2, 3, "b2", 4, 5, 6, "b3", "b4" }) -- Bot1 1st, Bot2 3rd
	playRound({ "b1", 6, 5, 1, "b2", 2, 3, 4, "b3", "b4" }) -- Bot6 2nd, Bot5 3rd
	playRound({ 1, 2, "b1", 3, 4, 5, 6 }, { 9, 9, 5, 4, 3, 2, 1 }) -- Bot1 and Bot2 share 1st
	playRound({ 1, 2, 3, 4, 5, 6, "b1" }, { 1, 1, 1, 1, 1, 1, 1 }) -- everyone ties: the playing point
	local gained = {}
	for index = 1, 6 do
		gained[index] = weekly(index).Points - before[index]
	end
	check("points by place", table.concat(gained, ",") == "22,17,4,4,8,10", gained)
	local queued = H.State().Queue
	local queuedKeys = {}
	for key in queued do
		table.insert(queuedKeys, key)
	end
	table.sort(queuedKeys)
	check(
		"a save queued per person, none for bots",
		#queuedKeys == 6 and not string.find(table.concat(queuedKeys, ","), ":-", 1, true),
		queuedKeys
	)

	-- 3. The loop writes them (a few seconds after the round, never in it).
	H.Step()
	local board = H.Memory(W)
	local written = {}
	local matches = true
	for index = 1, 6 do
		local value = board[tostring(1000 + index)]
		written[index] = value
		matches = matches and value == weekly(index).Points
	end
	check("the board's store has every total", matches, written)
	local noBots = true
	for key in board do
		noBots = noBots and (tonumber(key) or 0) > 0
	end
	check("no bot on the store's board", noBots)
	local order = topIds()
	check(
		"board order (merged with the store's players, ties to the lower UserId)",
		table.concat(order, ",") == "501,1001,1002,777,1006,1005,1003,1004",
		order
	)
	local ranks = {}
	local ranksOk = true
	for index = 1, 6 do
		ranks[index] = people[index]:GetAttribute("PP_WeeklyRank")
		ranksOk = ranksOk and ranks[index] == table.find(order, 1000 + index)
	end
	check("everyone's place (PP_WeeklyRank)", ranksOk, ranks)

	-- 4. A key written moments ago waits out its cooldown (one write per key every 6 s).
	playRound({ 6, 1, 2, 3, 4, 5 })
	H.Step()
	local waiting = H.State().Queue
	check(
		"a key written moments ago waits its turn",
		next(waiting) ~= nil and board["1006"] < weekly(6).Points,
		waiting
	)
	H.ForgetWrites()
	H.Step()
	check("... and goes after it", next(H.State().Queue) == nil and board["1006"] == weekly(6).Points, board["1006"])

	-- 5. A refused write is tried again later, not straight away.
	H.ForgetWrites()
	H.Faults.FailWrites = 1
	playRound({ 3, 1, 2, 4, 5, 6 })
	H.Step()
	local afterFail = H.State().Queue
	local failures = 0
	for _, entry in afterFail do
		failures += entry.Failures
	end
	H.ForgetWrites()
	H.Step()
	local stillWaiting = 0
	for _, entry in H.State().Queue do
		stillWaiting += entry.Failures
	end
	check("a refused write waits (backoff)", failures == 1 and stillWaiting == 1, afterFail)
	H.RetryNow()
	H.ForgetWrites()
	H.Step()
	check("... then goes", next(H.State().Queue) == nil and board["1001"] == weekly(1).Points, board["1001"])

	-- 6. Short of budget: nothing is written until there's room again.
	H.ForgetWrites()
	H.Faults.Budget = 5
	playRound({ 4, 1, 2, 3, 5, 6 })
	H.Step()
	local held = next(H.State().Queue) ~= nil and board["1004"] < weekly(4).Points
	H.Faults.Budget = 1000
	H.ForgetWrites()
	H.Step()
	check("a short budget holds the writes back", held and board["1004"] == weekly(4).Points, board["1004"])

	-- 7. The round's toasts wait for the lobby: one at most per person. Bot7 has just joined: its
	-- first points this week get one.
	local newcomer = __newPlayer(7)
	table.insert(__fakePlayers, newcomer)
	people[7] = newcomer
	DataService.All()[newcomer] = {
		Player = newcomer,
		Key = "Harness_7",
		Data = DataService.Migrate({ EconomyVersion = 2 }),
		CanSave = false,
		Released = false,
	}
	task.wait(1) -- (the earlier rounds' toasts have gone)
	GameState.Set("Phase", "Results")
	table.clear(toasts)
	playRound({ 5, 1, 2, 3, 4, 6 })
	local entries = {}
	for position, player in { people[6], newcomer, bots[1] } do
		table.insert(entries, { Key = player, Player = player, Rank = 10 - position, ScoreText = "" })
	end
	RoundEvents.Finished:Fire(definition, Placement.Assign(entries), nil) -- Bot7 2nd: 7 points
	task.wait(1)
	local duringResults = #toasts
	GameState.Set("Phase", "Intermission")
	task.wait(1.5)
	local perPerson = {}
	local once = true
	for _, line in toasts do
		local who = string.match(line, "^(%w+):")
		perPerson[who] = (perPerson[who] or 0) + 1
		once = once and perPerson[who] == 1
	end
	check(
		"no toast during the results, then one at most each (Bot7's first points)",
		duringResults == 0 and once and perPerson.Bot7 == 1,
		toasts
	)
	summary.roundToasts = table.clone(toasts)

	-- 8. The week turns (Monday 00:02): points from 0, the week remembered, last week's statues.
	H.ForgetWrites()
	H.Step()
	local lastTotals = {}
	for index = 1, 7 do
		lastTotals[index] = weekly(index).Points
	end
	now = WeeklyLogic.WeekStart(W + 1) + 120
	local medalsBefore = #medals
	H.ForgetReads()
	H.Step()
	data = hall()
	check(
		"the new week on every screen",
		data ~= nil and data.Week == W + 1 and #data.Top == 0,
		data and { Week = data.Week, Top = #data.Top }
	)
	check(
		"points start from 0, last week waits to be checked",
		weekly(1).Week == W + 1 and weekly(1).Points == 0 and weekly(1).Pending ~= nil and weekly(1).Pending[1] == W,
		weekly(1)
	)
	local newLast = {}
	for _, row in (data and data.LastWeek) or {} do
		table.insert(newLast, row.UserId)
	end
	local expectedLast = {}
	local everyone = {}
	for index = 1, 7 do
		table.insert(everyone, { UserId = 1000 + index, Points = lastTotals[index] })
	end
	table.insert(everyone, { UserId = 501, Points = 40 })
	table.insert(everyone, { UserId = 777, Points = 12 })
	for _, entry in WeeklyLogic.Top(WeeklyLogic.Standings(everyone, {}, 100), 3) do
		table.insert(expectedLast, entry.UserId)
	end
	check("last week's top three are the statues now", table.concat(newLast, ",") == table.concat(expectedLast, ","), {
		got = newLast,
		want = expectedLast,
	})
	check("no medal before the week is final", #medals == medalsBefore, medals)
	-- A round just after midnight counts for the new week.
	playRound({ 2, 1, 3, 4, 5, 6 })
	check("a round on Monday counts for the new week", weekly(2).Week == W + 1 and weekly(2).Points == 10, weekly(2))
	H.ForgetWrites()
	H.Step()
	check("... and is saved to the new week's board", H.Memory(W + 1)["1002"] == 10, H.Memory(W + 1))

	-- 9. Ten minutes later the week is final: the medal for its top three.
	now = WeeklyLogic.WeekStart(W + 1) + 700
	H.ForgetReads()
	H.Step()
	task.wait(0.5)
	local wanted = {}
	for _, id in expectedLast do
		if id > 1000 and id <= 1007 then
			table.insert(wanted, `Bot{id - 1000}:HallOfFame`)
		end
	end
	local gotAll = true
	for _, medal in wanted do
		gotAll = gotAll and table.find(medals, medal) ~= nil
	end
	check(
		"HallOfFame medal for last week's top three, once final",
		gotAll and #wanted > 0,
		{ wanted = wanted, medals = medals }
	)
	waitForStatues(25)
	summary.statuesAfter = HallOfFame.StateForTests().spots

	-- 10. The Hall's board: every line fits with the longest names and numbers.
	local okBoard, problems = pcall(function()
		__localPlayer = people[1]
		rawset(__playersShim, "LocalPlayer", __localPlayer)
		local Controller = __require("Client/Controllers/HallOfFameController")
		local TextService = game:GetService("TextService")
		for _, font in { Enum.Font.FredokaOne, Enum.Font.BuilderSans } do
			local params = Instance.new("GetTextBoundsParams")
			params.Text = "Ag 0 📈▶·"
			params.Font = Font.fromEnum(font)
			params.Size = 20
			params.Width = 1e5
			pcall(TextService.GetTextBoundsAsync, TextService, params)
		end
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(14.4, 11.2, 0.4)
		part.CFrame = CFrame.new(0, 300, 0)
		part.Parent = workspace
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.Parent = part
		local draw = Controller.BuildBoard(gui)
		local top = {}
		for index = 1, 10 do
			table.insert(top, { UserId = 5000 + index, Name = "SuperLongDisplayNm20", Points = 99999 - index })
		end
		top[3].UserId = people[1].UserId -- the player's own row has its marker
		draw({ Week = W + 1, LastWeek = {}, Top = top }, 99996, 3)
		task.wait(0.3)
		local lines, bad = {}, {}
		for _, label in gui:GetDescendants() do
			if label:IsA("TextLabel") and label.Text ~= "" then
				local fits = label.TextFits and label.TextBounds.X <= label.AbsoluteSize.X + 0.5
				table.insert(lines, label.Text)
				if not fits then
					table.insert(
						bad,
						string.format(
							"%s %q needs %dx%d, has %dx%d",
							label.Name,
							label.Text,
							label.TextBounds.X,
							label.TextBounds.Y,
							label.AbsoluteSize.X,
							label.AbsoluteSize.Y
						)
					)
				end
			end
		end
		draw({ Week = W + 1, LastWeek = {}, Top = {} }, 0, nil)
		task.wait(0.2)
		local empty = {}
		for _, label in gui:GetDescendants() do
			if label:IsA("TextLabel") and label.Text ~= "" then
				table.insert(empty, label.Text)
			end
		end
		return { bad = bad, lines = #lines, empty = empty }
	end)
	check("the board's lines all fit", okBoard and #problems.bad == 0, problems)

	summary.medals = medals
	summary.errors = __errors
	summary.log = __log
	return HttpService:JSONEncode(summary)
end

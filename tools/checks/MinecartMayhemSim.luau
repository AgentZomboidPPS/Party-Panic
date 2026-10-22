-- Offline sim of Minecart Mayhem riders (lune run tools/checks/MinecartMayhemSim [rounds]): the
-- real track rules (Shared/Logic/MinecartMayhemTrack) and the real bot brain (Bots/MinecartMayhem)
-- on the server's judging (ping leeway, Choose, Clears, crystals), for a perfect rider, bots of
-- three skills and an idle rider. Prints each strategy's average finish time, how many finished, and
-- its falls, blasts, dead ends and shortcuts per round.
local process = require("@lune/process")

local Track = require("../../src/shared/Logic/MinecartMayhemTrack")
local Brain = require("../../src/server/MiniGames/Bots/MinecartMayhem")

local function newRng(seed: number)
	local state = seed
	local rng = {}
	function rng.NextNumber(_self, a: number?, b: number?): number
		state = (state * 1103515245 + 12345) % 2147483648
		local u = state / 2147483648
		if a and b then
			return a + (b - a) * u
		end
		return u
	end
	function rng.NextInteger(self, a: number, b: number): number
		return math.min(b, a + math.floor(self:NextNumber() * (b - a + 1)))
	end
	return rng
end

local ROUNDS = tonumber(process.args[1]) or 40
local LEEWAY = 0.1
local DT = 1 / 60
local STRATEGIES = { "perfect", "bot 0.9", "bot 0.65", "bot 0.35", "idle" }

local totals = {}
for _, name in STRATEGIES do
	totals[name] = { Time = 0, Home = 0, Falls = 0, Blasts = 0, Bumps = 0, Shorts = 0, Progress = 0, Wins = 0 }
end

for round = 1, ROUNDS do
	local rng = newRng(round * 7919)
	local tiles = Track.Generate(rng)
	local course = Track.Build(tiles)
	local now = 0
	local delays = {}
	local mode = { Track = Track, course = course, riders = {}, racing = true, ending = false }
	local list = {}
	local ctx = {}
	function ctx.Now()
		return now
	end
	function ctx.Delay(_self, t: number, fn)
		table.insert(delays, { At = now + t, Fn = fn })
	end
	local function newRider(name: string)
		local rider = {
			Name = name,
			Tile = 1,
			B = 1,
			S = 0,
			V = 0,
			Lean = 0,
			JumpAt = -math.huge,
			DashUntil = 0,
			DownUntil = 0,
			Back = false,
			Picks = {},
			ZoneAt = {},
			Pending = {},
			Falls = 0,
			Blasts = 0,
			Bumps = 0,
			Shorts = 0,
			Gone = false,
		}
		return rider
	end
	local function lean(rider, dir)
		if dir == rider.Lean then
			return
		end
		local last = rider.Picks[#rider.Picks]
		if last and last.Until == nil then
			last.Until = now
		end
		rider.Lean = dir
		if dir ~= 0 then
			table.insert(rider.Picks, { Dir = dir, At = now })
		end
	end
	local function jump(rider)
		if rider.Back or rider.DownUntil > 0 or now < rider.JumpAt + Track.JUMP_TIME + Track.JUMP_REST then
			return
		end
		rider.JumpAt = now
	end
	function ctx.BotAction(_self, bot, name, a)
		local rider = mode.riders[bot]
		if name == "Lean" then
			lean(rider, a)
		elseif name == "Jump" then
			jump(rider)
		end
	end
	local bots = {}
	for index, name in STRATEGIES do
		local rider = newRider(name)
		local bot = { Skill = 0, Memory = {}, Rng = newRng(round * 31 + index), Name = name }
		function bot.Reaction(self)
			return (0.85 - self.Skill * 0.6) * self.Rng:NextNumber(0.75, 1.35)
		end
		if string.sub(name, 1, 3) == "bot" then
			bot.Skill = tonumber(string.sub(name, 5)) :: number
			table.insert(bots, bot)
		end
		mode.riders[bot] = rider
		rider.Bot = bot
		table.insert(list, rider)
	end
	local nextBrain = 0
	while now < 90 do
		now += DT
		for k = #delays, 1, -1 do
			if delays[k].At <= now then
				local item = table.remove(delays, k)
				item.Fn()
			end
		end
		if now >= nextBrain then
			nextBrain = now + 1 / 7
			for _, bot in bots do
				Brain.Step(bot, ctx, mode, 1 / 7)
			end
		end
		for _, rider in list do
			if rider.Finish then
				continue
			end
			-- The perfect rider: shortcuts only, every lean, every jump in the middle.
			if rider.Name == "perfect" then
				local index, away = Track.NextSwitch(course, rider, Track.CHOOSE)
				local want = 0
				if index and away < 30 then
					local junction = course.Tiles[index]
					if junction.O == "Short" then
						want = -(junction.L or 1)
					end
				end
				local tile = course.Tiles[rider.Tile]
				if want == 0 then
					want = Track.LeanAt(tile, rider.B, rider.S + 2)
				end
				lean(rider, want)
				for _, feature in tile.Features do
					if feature.K == "Gap" then
						local front = feature.S - Track.HALF_BASE - rider.S
						local lead = Track.JUMP_TIME / 2 - ((feature.S1 - feature.S) + Track.WHEELBASE) / (2 * rider.V)
						if front > 0 and front / rider.V <= lead then
							jump(rider)
						end
					end
				end
			end
			local events = Track.Ride(course, rider, DT, now)
			local index, away = Track.NextSwitch(course, rider, Track.CHOOSE)
			if index and rider.ZoneAt[index] == nil then
				rider.ZoneAt[index] = now - math.max(0, Track.CHOOSE - away) / math.max(rider.V, 1)
			end
			for _, event in events do
				if event.K == "Switch" then
					table.insert(
						rider.Pending,
						{ K = "Switch", At = event.At, Tile = event.Tile, JudgeAt = event.At + Track.GRACE + LEEWAY }
					)
				elseif event.K == "Gap" or event.K == "Crystal" then
					table.insert(
						rider.Pending,
						{
							K = event.K,
							At = event.At,
							Tile = event.Tile,
							V = event.V,
							Gap = event.Gap,
							JudgeAt = event.At + LEEWAY,
						}
					)
				elseif event.K == "Buffer" then
					rider.Bumps += 1
					rider.Pending = {}
				elseif event.K == "TNT" then
					rider.Blasts += 1
					rider.Pending = {}
				end
			end
			while rider.Pending[1] and rider.Pending[1].JudgeAt <= now do
				local item = table.remove(rider.Pending, 1)
				if rider.DownUntil > 0 then
					continue
				end
				local tile = course.Tiles[item.Tile]
				if item.K == "Switch" and rider.Tile == item.Tile and rider.B == 1 then
					rider.B =
						Track.BranchFor(tile, Track.Choose(rider.Picks, rider.ZoneAt[item.Tile] or item.At, item.At))
					if rider.B == 2 and tile.O == "Short" then
						rider.Shorts += 1
					end
				elseif item.K == "Gap" and rider.Tile == item.Tile then
					if not Track.Clears(rider.JumpAt, item.At, item.V, item.Gap) then
						rider.Falls += 1
						Track.Fall(course, rider, item.Tile, now)
						rider.Pending = {}
					end
				elseif item.K == "Crystal" and not Track.Airborne(rider.JumpAt, item.At) then
					rider.DashUntil = now + Track.DASH_TIME
				end
			end
		end
	end
	local best, winner = math.huge, nil
	for _, rider in list do
		local total = totals[rider.Name]
		if rider.Finish then
			total.Home += 1
			total.Time += rider.Finish
			if rider.Finish < best then
				best, winner = rider.Finish, rider.Name
			end
		end
		total.Falls += rider.Falls
		total.Blasts += rider.Blasts
		total.Bumps += rider.Bumps
		total.Shorts += rider.Shorts
		total.Progress += Track.Progress(course, rider) / course.Goal
	end
	if winner then
		totals[winner].Wins += 1
	end
end

for _, name in STRATEGIES do
	local t = totals[name]
	print(
		string.format(
			"%-9s home %d/%d avg %.1fs wins %d | per round: falls %.2f blasts %.2f dead ends %.2f shortcuts %.2f | progress %.0f%%",
			name,
			t.Home,
			ROUNDS,
			if t.Home > 0 then t.Time / t.Home else 0,
			t.Wins,
			t.Falls / ROUNDS,
			t.Blasts / ROUNDS,
			t.Bumps / ROUNDS,
			t.Shorts / ROUNDS,
			t.Progress / ROUNDS * 100
		)
	)
end

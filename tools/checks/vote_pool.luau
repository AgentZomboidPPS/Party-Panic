-- Shared by tools/checks/vote_sim.luau and tests/VoteFairness.spec.luau: reads the mini-game pool
-- from GameDefinitions.luau (it needs Roblox's script tree, so this parses its source) and plays
-- many votes through GamePicker the way VotingService.BuildOptions does.
local fs = require("@lune/fs")

local Pool = {}

function Pool.Read(path: string?): { any }
	local source = fs.readFile(path or "src/shared/GameDefinitions.luau")
	local pool = {}
	for id, body in string.gmatch(source, '\n\t\tId = "(%w+)",(.-)\n\t}') do
		table.insert(pool, {
			Id = id,
			Category = string.match(body, 'Category = "(%w+)"'),
			MinPlayers = tonumber(string.match(body, "MinPlayers = (%d+)")) or 1,
			Weight = tonumber(string.match(body, "\n\t\tWeight = ([%d%.]+)")),
			Enabled = not string.find(body, "\n\t\tEnabled = false", 1, true),
		})
	end
	-- New games: the newest NEW_GAMES in the rotation, by their place in the list (as GameDefinitions
	-- works it out).
	local left = tonumber(string.match(source, "\nlocal NEW_GAMES = (%d+)")) or 0
	for index = #pool, 1, -1 do
		local entry = pool[index]
		entry.IsNew = entry.Enabled and left > 0
		if entry.Enabled then
			left -= 1
		end
	end
	return pool
end

-- How many votes a fresh server takes until every game it can play has been offered: the median
-- and the 90th percentile over `servers` fresh starts.
function Pool.Coverage(
	GamePicker,
	pool,
	players: number,
	memory: number,
	choices: number,
	servers: number,
	seed: number
)
	local random = Pool.Generator(seed)
	local needed = {}
	local eligible = 0
	for _, entry in pool do
		if GamePicker.IsEligible(entry, players) then
			eligible += 1
		end
	end
	for _ = 1, servers do
		local seen, count, recent, vote = {}, 0, {}, 0
		while count < eligible and vote < 1000 do
			vote += 1
			local shown = GamePicker.Pick(pool, {
				PlayerCount = players,
				Count = choices,
				Recent = recent,
				RecentMemory = memory,
				RandomFloat = random,
			})
			for _, id in shown do
				if not seen[id] then
					seen[id] = true
					count += 1
				end
			end
			table.insert(recent, 1, shown[math.floor(random() * #shown) + 1])
		end
		table.insert(needed, vote)
	end
	table.sort(needed)
	return needed[math.ceil(#needed / 2)], needed[math.ceil(#needed * 0.9)]
end

-- A small seeded generator (Lune has no Random), returning [0, 1).
function Pool.Generator(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function()
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

function Pool.Simulate(
	GamePicker,
	pool,
	votes: number,
	counts: { number },
	memory: number,
	choices: number,
	seed: number
)
	local random = Pool.Generator(seed)
	local out = {}
	for _, players in counts do
		local offered, played, randomOf, firstSeen = {}, {}, {}, {}
		local sameAll, sameTwo, clashes = 0, 0, 0
		local recent = {}
		local seenCount = 0
		local eligibleCount = 0
		for _, entry in pool do
			if GamePicker.IsEligible(entry, players) then
				eligibleCount += 1
			end
		end
		for vote = 1, votes do
			local function pick(from, count)
				return GamePicker.Pick(from, {
					PlayerCount = players,
					Count = count,
					Recent = recent,
					RecentMemory = memory,
					RandomFloat = random,
				})
			end
			local shown = pick(pool, choices)
			local rest = {}
			for _, entry in pool do
				if not table.find(shown, entry.Id) then
					table.insert(rest, entry)
				end
			end
			local mystery = pick(rest, 1)[1] or shown[1]
			if table.find(shown, mystery) and #rest > 0 then
				clashes += 1
			end
			randomOf[mystery] = (randomOf[mystery] or 0) + 1
			local categories = {}
			for _, id in shown do
				offered[id] = (offered[id] or 0) + 1
				if not firstSeen[id] then
					firstSeen[id] = vote
					seenCount += 1
				end
				for _, entry in pool do
					if entry.Id == id then
						categories[entry.Category] = (categories[entry.Category] or 0) + 1
					end
				end
			end
			local most = 0
			for _, n in categories do
				most = math.max(most, n)
			end
			if most >= 3 then
				sameAll += 1
			elseif most == 2 then
				sameTwo += 1
			end
			local card = math.floor(random() * (#shown + 1)) + 1
			local winner = if card > #shown then mystery else shown[card]
			played[winner] = (played[winner] or 0) + 1
			table.insert(recent, 1, winner)
			if #recent > 8 then
				table.remove(recent)
			end
		end
		local everyoneBy = 0
		for _, entry in pool do
			if GamePicker.IsEligible(entry, players) then
				everyoneBy = math.max(everyoneBy, firstSeen[entry.Id] or math.huge)
			end
		end
		local total = 0
		for _, n in offered do
			total += n
		end
		out[players] = {
			Votes = votes,
			Offered = offered,
			Played = played,
			Random = randomOf,
			SameAll = sameAll / votes,
			Clashes = clashes,
			SameTwo = sameTwo / votes,
			EveryoneBy = everyoneBy,
			Eligible = eligibleCount,
			Average = total / eligibleCount,
		}
	end
	return out
end

function Pool.Print(result, pool)
	local players = {}
	for count in result do
		table.insert(players, count)
	end
	table.sort(players)
	local header = string.format("%-15s %-9s %-4s", "game", "category", "new")
	for _, count in players do
		header ..= string.format(" | %2dp off%% play%%", count)
	end
	print(header)
	for _, entry in pool do
		local line = string.format("%-15s %-9s %-4s", entry.Id, entry.Category, if entry.IsNew then "new" else "")
		for _, count in players do
			local r = result[count]
			local offered = (r.Offered[entry.Id] or 0)
			line ..= string.format(
				" | %5.1f%% %4.0f%% %4.1f%%",
				100 * offered / r.Votes,
				if r.Average > 0 then 100 * offered / r.Average else 0,
				100 * (r.Played[entry.Id] or 0) / r.Votes
			)
		end
		print(line)
	end
	for _, count in players do
		local r = result[count]
		local lowest, highest = math.huge, 0
		for _, entry in pool do
			if (r.Offered[entry.Id] or 0) > 0 or true then
				local n = r.Offered[entry.Id] or 0
				local eligible = entry.MinPlayers <= count and entry.Enabled
				if eligible then
					lowest = math.min(lowest, n / r.Average)
					highest = math.max(highest, n / r.Average)
				end
			end
		end
		local rLow, rHigh, rTotal, rCount = math.huge, 0, 0, 0
		for _, entry in pool do
			if entry.MinPlayers <= count and entry.Enabled then
				local n = r.Random[entry.Id] or 0
				rTotal += n
				rCount += 1
				rLow, rHigh = math.min(rLow, n), math.max(rHigh, n)
			end
		end
		local rAverage = rTotal / math.max(rCount, 1)
		print(
			string.format(
				"%2d players: RANDOM turns into each game %.0f%%..%.0f%% of the average",
				count,
				100 * rLow / rAverage,
				100 * rHigh / rAverage
			)
		)
		print(
			string.format(
				"%2d players: %d eligible; offered vs average %.0f%%..%.0f%%; all 3 same category %.1f%%, two the same %.1f%%; every game offered by vote %d",
				count,
				r.Eligible,
				100 * lowest,
				100 * highest,
				100 * r.SameAll,
				100 * r.SameTwo,
				r.EveryoneBy
			)
		)
	end
end

return Pool

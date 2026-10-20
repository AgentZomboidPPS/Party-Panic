--!strict
-- Chooses the mini-games offered in a vote (design doc §6 "Game selection rules").
-- * three distinct games
-- * respects each game's player-count requirement
-- * avoids the last played game and down-weights recent ones
-- * nudges toward a mix of categories
-- * gives new games a modest discovery weight
-- Leaf module: no requires, no Roblox APIs.

local GamePicker = {}

export type PoolEntry = {
	Id: string,
	Category: string,
	MinPlayers: number,
	MaxPlayers: number?,
	Weight: number?,
	IsNew: boolean?,
	Enabled: boolean?,
}

export type PickOptions = {
	PlayerCount: number,
	Count: number,
	Recent: { string }?, -- most recent first
	RecentMemory: number?,
	RandomFloat: () -> number, -- returns [0, 1)
	IgnorePlayerLimits: boolean?,
}

local RECENT_WEIGHT = 0.2
local SAME_CATEGORY_WEIGHT = 0.35
local DISCOVERY_WEIGHT = 1.25

function GamePicker.IsEligible(entry: PoolEntry, playerCount: number, ignoreLimits: boolean?): boolean
	if entry.Enabled == false then
		return false
	end
	if ignoreLimits then
		return true
	end
	if playerCount < entry.MinPlayers then
		return false
	end
	if entry.MaxPlayers and playerCount > entry.MaxPlayers then
		return false
	end
	return true
end

function GamePicker.Pick(pool: { PoolEntry }, options: PickOptions): { string }
	local recent = options.Recent or {}
	local memory = options.RecentMemory or 2

	local eligible: { PoolEntry } = {}
	for _, entry in pool do
		if GamePicker.IsEligible(entry, options.PlayerCount, options.IgnorePlayerLimits) then
			table.insert(eligible, entry)
		end
	end

	-- Drop the most recently played game outright when there is enough variety left.
	local lastPlayed = recent[1]
	if lastPlayed and #eligible - 1 >= options.Count then
		for index, entry in eligible do
			if entry.Id == lastPlayed then
				table.remove(eligible, index)
				break
			end
		end
	end

	local weights: { number } = {}
	for index, entry in eligible do
		local weight = entry.Weight or 1
		for position = 1, math.min(memory, #recent) do
			if recent[position] == entry.Id then
				weight *= RECENT_WEIGHT
				break
			end
		end
		if entry.IsNew then
			weight *= DISCOVERY_WEIGHT
		end
		weights[index] = math.max(weight, 0.0001)
	end

	local picked: { string } = {}
	local count = math.min(options.Count, #eligible)
	for _ = 1, count do
		local total = 0
		for _, weight in weights do
			total += weight
		end
		local roll = options.RandomFloat() * total
		local chosen = #eligible
		for index, weight in weights do
			roll -= weight
			if roll < 0 then
				chosen = index
				break
			end
		end

		local entry = eligible[chosen]
		table.insert(picked, entry.Id)
		table.remove(eligible, chosen)
		table.remove(weights, chosen)

		-- Encourage a category mix in the remaining picks.
		for index, other in eligible do
			if other.Category == entry.Category then
				weights[index] *= SAME_CATEGORY_WEIGHT
			end
		end
	end

	return picked
end

return GamePicker

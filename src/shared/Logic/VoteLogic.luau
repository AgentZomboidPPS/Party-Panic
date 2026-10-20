--!strict
-- Pure vote tallying and tie resolution (design doc §4 "Voting and tie resolution").
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.

local VoteLogic = {}

export type PickIndex = (count: number) -> number

-- Counts votes per option. `votes` maps a voter key to the option index they chose.
-- Invalid indices are ignored so a stale or malformed vote can never break a tally.
function VoteLogic.Tally(votes: { [any]: number }, optionCount: number): { number }
	local counts = table.create(optionCount, 0)
	for _, index in votes do
		if type(index) == "number" and index == math.floor(index) and index >= 1 and index <= optionCount then
			counts[index] += 1
		end
	end
	return counts
end

-- Returns the winning option index and whether a random tie-break was needed.
-- Ties pick randomly between the tied options; all-zero picks randomly from every option.
function VoteLogic.ResolveWinner(counts: { number }, pickIndex: PickIndex): (number, boolean)
	assert(#counts > 0, "ResolveWinner needs at least one option")
	local best = -1
	local candidates: { number } = {}
	for index, count in counts do
		if count > best then
			best = count
			candidates = { index }
		elseif count == best then
			table.insert(candidates, index)
		end
	end
	if #candidates == 1 then
		return candidates[1], false
	end
	local choice = pickIndex(#candidates)
	choice = math.clamp(math.floor(choice), 1, #candidates)
	return candidates[choice], true
end

-- Validates a client supplied vote index.
function VoteLogic.IsValidChoice(index: any, optionCount: number): boolean
	return type(index) == "number"
		and index == index -- rejects NaN
		and index == math.floor(index)
		and index >= 1
		and index <= optionCount
end

return VoteLogic

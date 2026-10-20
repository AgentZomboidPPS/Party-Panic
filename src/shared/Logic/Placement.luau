--!strict
-- Turns per-player rank values into placements (1st, 2nd, ...).
-- Higher rank value = better. Equal rank values share a place ("1, 1, 3" competition ranking).
-- Leaf module: no requires, no Roblox APIs.

local Placement = {}

export type Entry = {
	Key: any,
	Rank: number,
	[string]: any,
}

export type Placed = {
	Key: any,
	Rank: number,
	Place: number,
	Entry: Entry,
}

function Placement.Assign(entries: { Entry }): { Placed }
	local order: { { entry: Entry, index: number } } = {}
	for index, entry in entries do
		table.insert(order, { entry = entry, index = index })
	end
	table.sort(order, function(a, b)
		if a.entry.Rank ~= b.entry.Rank then
			return a.entry.Rank > b.entry.Rank
		end
		return a.index < b.index
	end)

	local placed: { Placed } = {}
	local place = 0
	for position, item in order do
		if position == 1 or item.entry.Rank ~= order[position - 1].entry.Rank then
			place = position
		end
		table.insert(placed, {
			Key = item.entry.Key,
			Rank = item.entry.Rank,
			Place = place,
			Entry = item.entry,
		})
	end
	return placed
end

-- A place counts as "top half" when it is within the better half of the field.
-- Solo rounds count as top half so a lone tester still sees the full reward flow.
function Placement.IsTopHalf(place: number, playerCount: number): boolean
	return place <= math.max(1, math.ceil(playerCount / 2))
end

function Placement.Ordinal(place: number): string
	local lastTwo = place % 100
	if lastTwo >= 11 and lastTwo <= 13 then
		return `{place}th`
	end
	local last = place % 10
	if last == 1 then
		return `{place}st`
	elseif last == 2 then
		return `{place}nd`
	elseif last == 3 then
		return `{place}rd`
	end
	return `{place}th`
end

return Placement

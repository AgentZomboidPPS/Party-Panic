--!strict
-- Where the riders' dots go on a race progress bar (Skate Escape's HUD), so every rider stays readable on
-- a small phone. Part of the phone HUD work (owner: "Wtf is this mobile Ui lol"): the racer dots piled on
-- top of each other whenever riders were side by side, so you couldn't tell who was where (on a phone the
-- bar is about 230 points long and a dot about 14).
--
-- A dot sits on the bar's line at the rider's real progress while nobody is near it. Dots that would
-- overlap form a pack: they step off the line, alternately above and below it (two riders level with
-- each other show one above the other), and are pushed apart along the bar only as far as it takes for
-- every dot's number to stay clear, keeping their order and staying as close as possible to where the
-- riders really are. The layout remembers itself (`Tier` and `Rank`, passed back in from the last one) so
-- dots stay calm: riders level with each other keep their order until one is clearly ahead (their
-- numbers wobble a little with every server update), a rider keeps its side while the pack lasts (only
-- two riders passing each other swap sides), and a pack only breaks up once its riders are clearly apart.
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.

local RaceBar = {}

export type Dot = {
	Key: string,
	X: number, -- the rider's real place along the bar, 0..Width
	Size: number, -- the dot's diameter
	Tier: number?, -- where it was last time: -1 above the line, 0 on it, 1 below
	Rank: number?, -- its place in the order last time (1 = furthest back)
}

export type Options = {
	Width: number, -- the bar's length (dots stay within 0..Width)
	Lift: number, -- how far a dot in a pack steps off the line
	Slack: number?, -- how much two dots' rims may overlap (their numbers still clear); default 2
}

export type Spot = { X: number, Y: number, Tier: number, Rank: number }

local SPLIT_HOLD = 6 -- a pack holds together until its riders are this much further apart
local PASS = 5 -- a rider has to be this far ahead to take the place in front on the bar

-- How close two dots' centres may come (their rims may overlap by `slack`, their numbers stay clear).
local function reach(a: Dot, b: Dot, slack: number): number
	return (a.Size + b.Size) / 2 - slack
end

-- The least distance along the bar between neighbours order[index - 1] and order[index]: enough for
-- the two to clear each other when one is above the line and the other below, and for the dots two
-- apart (on the same side) to clear each other with the next gap along.
local function gapBefore(order: { Dot }, index: number, lift: number, slack: number): number
	local near = reach(order[index - 1], order[index], slack)
	local gap = math.sqrt(math.max(0, near * near - (2 * lift) ^ 2))
	if order[index + 1] then
		gap = math.max(gap, reach(order[index - 1], order[index + 1], slack) / 2)
	end
	if order[index - 2] then
		gap = math.max(gap, reach(order[index - 2], order[index], slack) / 2)
	end
	return gap
end

-- Lays the dots out; returns where each one goes by Key. Y is off the line (negative is above it).
function RaceBar.Layout(dots: { Dot }, options: Options): { [string]: Spot }
	local width = options.Width
	local lift = options.Lift
	local slack = options.Slack or 2
	local order = table.clone(dots)
	table.sort(order, function(a, b)
		if a.X ~= b.X then
			return a.X < b.X
		end
		return a.Key < b.Key
	end)
	local count = #order
	-- Neighbours only trade places once one is clearly ahead; until then, last time's order stands.
	for _ = 1, count do
		local swapped = false
		for index = 1, count - 1 do
			local a, b = order[index], order[index + 1]
			if a.Rank and b.Rank and a.Rank > b.Rank and b.X - a.X < PASS then
				order[index], order[index + 1] = b, a
				swapped = true
			end
		end
		if not swapped then
			break
		end
	end
	local spots: { [string]: Spot } = {}
	if count == 0 then
		return spots
	end

	-- Along the bar: the closest positions to the real ones that keep neighbours `gap` apart (in
	-- order) and stay on the bar. With offsets[i] = the gaps up to dot i, that's x[i] - offsets[i]
	-- never going down: pool-adjacent-violators on the shifted targets, then clamp to the bar.
	local offsets = { 0 }
	for index = 2, count do
		offsets[index] = offsets[index - 1] + gapBefore(order, index, lift, slack)
	end
	local squeeze = if offsets[count] > width then width / offsets[count] else 1 -- (more dots than bar)
	local blocks: { { Sum: number, Count: number } } = {}
	for index = 1, count do
		table.insert(blocks, { Sum = order[index].X - offsets[index] * squeeze, Count = 1 })
		while #blocks > 1 do
			local last, before = blocks[#blocks], blocks[#blocks - 1]
			if before.Sum / before.Count <= last.Sum / last.Count then
				break
			end
			before.Sum += last.Sum
			before.Count += last.Count
			table.remove(blocks)
		end
	end
	local xs = {}
	local high = math.max(0, width - offsets[count] * squeeze)
	for _, block in blocks do
		local base = math.clamp(block.Sum / block.Count, 0, high)
		for _ = 1, block.Count do
			local index = #xs + 1
			xs[index] = base + offsets[index] * squeeze
		end
	end

	-- Packs: runs of dots that would overlap on the line. A pack that was split stays split a little
	-- longer, so riders hovering at the edge don't flicker on and off the line.
	local packs: { { number } } = { { 1 } }
	for index = 2, count do
		local a, b = order[index - 1], order[index]
		local wasSplit = (a.Tier or 0) ~= 0 and (b.Tier or 0) ~= 0 and a.Tier ~= b.Tier
		local apart = (a.Size + b.Size) / 2 + (if wasSplit then SPLIT_HOLD else 0)
		if xs[index] - xs[index - 1] < apart then
			table.insert(packs[#packs], index)
		else
			table.insert(packs, { index })
		end
	end

	for _, pack in packs do
		-- Above, below, above... or below, above, below...: whichever keeps more riders where they were.
		local first = -1
		if #pack > 1 then
			local keepUp, keepDown = 0, 0
			for position, index in pack do
				local tier = order[index].Tier or 0
				local up = if position % 2 == 1 then -1 else 1
				if tier == up then
					keepUp += 1
				elseif tier == -up then
					keepDown += 1
				end
			end
			first = if keepDown > keepUp then 1 else -1
		end
		for position, index in pack do
			local tier = if #pack == 1 then 0 elseif position % 2 == 1 then first else -first
			spots[order[index].Key] = { X = xs[index], Y = tier * lift, Tier = tier, Rank = index }
		end
	end
	return spots
end

return RaceBar

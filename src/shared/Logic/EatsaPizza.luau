--!strict
-- Eatsa Pizza's shared rules: the pizza's geometry (twelve slices round a middle), how much of a
-- slice is left at each stage of being eaten, and which slice a spot on the pizza is on. The server
-- judges bites with Locate; the client uses the same function to tell a player whether they're on a
-- slice they can eat, so what the HUD says is what the server does.
--
-- Angles: slice i (1..SLICES) points from the middle along (sin a, cos a) in world X, Z, with
-- a = (i - 0.5) * SLICE_ANGLE. A slice's meshes (tools/meshgen/props/EatsaPizza.py) are drawn at
-- radius MESH_RADIUS with the tip at the origin; stage k of a slice reaches REACH[k + 1] of the
-- pizza's radius (the bites in its front go up to BITE of the radius deeper).

local EatsaPizza = {}

EatsaPizza.SLICES = 12
EatsaPizza.SLICE_ANGLE = 2 * math.pi / 12
EatsaPizza.MESH_RADIUS = 20 -- the slice meshes' radius as drawn
EatsaPizza.MESH_CHEESE = 0.31 -- the cheese's top in the meshes (pepperoni sit on it)
EatsaPizza.REACH = { 1.0, 0.8, 0.6, 0.38 } -- how far stage 0..3 reaches (share of the radius)
EatsaPizza.STAGES = { "EatsaPizzaSlice", "EatsaPizzaSlice1", "EatsaPizzaSlice2", "EatsaPizzaSlice3" }

EatsaPizza.PER_PLAYER = 110 -- bites a team has to eat for each of its players
EatsaPizza.PEPPERONI_WEIGHT = 0.14 -- each pepperoni makes its slice this share bigger
EatsaPizza.RATE = 8 -- bites a second, at most (a quick human's mashing: an auto-clicker gains little)
EatsaPizza.BURST = 4
EatsaPizza.EDGE_LEEWAY = 2.2 -- studs past a slice's bitten front that still count
EatsaPizza.SIDE_LEEWAY = 1.4 -- studs past a slice's sides that still count...
EatsaPizza.SIDE_ANGLE = 0.12 -- ...but never more than this far round (radians), so near the middle
-- a step off a slice is a step off it
EatsaPizza.MIDDLE = 2.5 -- the very middle, where every slice's tip meets, is nobody's slice

-- THE HOT PEPPER (owner: "can we make the eatsa pizza game more interactable? In mario party it feels
-- and plays a ton better."): now and then a chili lands on the pizza where two teams' parts meet, half
-- way out, and whoever gets to it first is SPICY for a few seconds: every press eats two bites. One
-- is out at a time; one nobody grabs goes after a while.
EatsaPizza.CHILI_FIRST = 6 -- seconds after GO the first one lands
EatsaPizza.CHILI_EVERY = 7 -- seconds from one being grabbed (or going) to the next landing
EatsaPizza.CHILI_LIFE = 8 -- seconds one waits to be grabbed
EatsaPizza.CHILI_REACH = 3.5 -- studs (flat) from its middle that grab it
EatsaPizza.CHILI_OUT = 0.55 -- how far out it lands (share of the radius)
EatsaPizza.SPICY_TIME = 5 -- seconds of...
EatsaPizza.SPICY_BITES = 2 -- ...this many bites a press

-- A slice's bitten front for the pepperoni: they go one at a time as the bites reach them, not all
-- at once when the slice's next stage does. Its last bite is this far out (share of the radius).
EatsaPizza.LAST_REACH = 0.18

-- The pizza's radius for a round of `count` players.
function EatsaPizza.Radius(count: number): number
	return math.clamp(24 + 1.2 * count, 26, 38)
end

-- How many slices each team gets, and which team owns slice `index` (nil: nobody's).
function EatsaPizza.PerTeam(teamCount: number): number
	return if teamCount <= 1 then 6 else math.floor(EatsaPizza.SLICES / teamCount)
end

function EatsaPizza.Owner(order: { string }, index: number): string?
	local per = EatsaPizza.PerTeam(#order)
	return order[math.ceil(index / per)]
end

function EatsaPizza.Angle(index: number): number
	return (index - 0.5) * EatsaPizza.SLICE_ANGLE
end

function EatsaPizza.Direction(index: number): Vector3
	local a = EatsaPizza.Angle(index)
	return Vector3.new(math.sin(a), 0, math.cos(a))
end

-- The stage (0..3) of a slice with `left` of `max` bites still to eat.
function EatsaPizza.Stage(left: number, max: number): number
	if max <= 0 then
		return 3
	end
	local eaten = 1 - left / max
	return math.clamp(math.floor(eaten * 4), 0, 3)
end

-- How far the bites have come on a slice with `left` of `max` to go (share of the radius): smoothly
-- from the crust (1) through each stage's reach as the slice gets to it, to LAST_REACH; 0 once gone.
function EatsaPizza.Front(left: number, max: number): number
	if max <= 0 or left <= 0 then
		return 0
	end
	local eaten = math.clamp(1 - left / max, 0, 1) * 4
	local stage = math.min(math.floor(eaten), 3)
	local from = EatsaPizza.REACH[stage + 1]
	local to = EatsaPizza.REACH[stage + 2] or EatsaPizza.LAST_REACH
	return from + (to - from) * (eaten - stage)
end

-- Where the k-th chili of a round lands (offset from the middle, studs: x, z): on the line between
-- two teams' parts, going round the borders in turn so each pair of neighbours races for one.
-- `first` is the border the round starts at (0 is between the last team's part and the first's).
function EatsaPizza.ChiliSpot(k: number, teamCount: number, radius: number, first: number?): (number, number)
	local borders = math.max(teamCount, 1)
	local border = ((first or 0) + k - 1) % borders
	local a = border * EatsaPizza.PerTeam(teamCount) * EatsaPizza.SLICE_ANGLE
	local r = radius * EatsaPizza.CHILI_OUT
	return math.sin(a) * r, math.cos(a) * r
end

-- How far (studs) a slice at this stage reaches from the middle.
function EatsaPizza.Reach(stage: number, radius: number): number
	return (EatsaPizza.REACH[stage + 1] or 0.38) * radius
end

-- A good place to stand on a slice: towards the middle of what's left of it.
function EatsaPizza.StandSpot(index: number, stage: number, radius: number, sideways: number?): Vector3
	local a = EatsaPizza.Angle(index) + (sideways or 0) * EatsaPizza.SLICE_ANGLE * 0.22
	local r = EatsaPizza.Reach(stage, radius) * 0.6
	return Vector3.new(math.sin(a) * r, 0, math.cos(a) * r)
end

-- Which slice a spot (offset from the pizza's middle, studs) is on. `stageOf(index)` returns the
-- stage of a slice that may be eaten, or nil to skip it. Returns the slice the spot is most inside
-- (within the leeways), or nil.
function EatsaPizza.Locate(offset: Vector3, radius: number, stageOf: (index: number) -> number?): number?
	local distance = math.sqrt(offset.X * offset.X + offset.Z * offset.Z)
	local angle = math.atan2(offset.X, offset.Z)
	local best, bestOut = nil, math.huge
	local half = EatsaPizza.SLICE_ANGLE / 2
	for index = 1, EatsaPizza.SLICES do
		local stage = stageOf(index)
		if stage == nil then
			continue
		end
		local delta = (angle - EatsaPizza.Angle(index) + math.pi) % (2 * math.pi) - math.pi
		local excess = math.max(0, math.abs(delta) - half)
		local side = distance * math.sin(math.min(excess, math.pi / 2))
		local over = math.max(0, distance - EatsaPizza.Reach(stage, radius))
		-- (The leeway past the sides is in studs out on the slice, and a small angle near the middle:
		-- standing where the tips meet must not reach every slice at once.)
		local sideOk = excess <= math.min(EatsaPizza.SIDE_LEEWAY / math.max(distance, 1), EatsaPizza.SIDE_ANGLE)
		if distance >= EatsaPizza.MIDDLE and sideOk and over <= EatsaPizza.EDGE_LEEWAY then
			local out = side + over
			if out < bestOut then
				best, bestOut = index, out
			end
		end
	end
	return best
end

return EatsaPizza

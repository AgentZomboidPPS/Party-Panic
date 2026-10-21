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

EatsaPizza.PER_PLAYER = 130 -- bites a team has to eat for each of its players
EatsaPizza.PEPPERONI_WEIGHT = 0.14 -- each pepperoni makes its slice this share bigger
EatsaPizza.RATE = 10 -- bites a second, at most (a quick human's mashing)
EatsaPizza.BURST = 4
EatsaPizza.EDGE_LEEWAY = 2.2 -- studs past a slice's bitten front that still count
EatsaPizza.SIDE_LEEWAY = 1.4 -- studs past a slice's sides that still count

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
		local side = if math.abs(delta) > half
			then distance * math.sin(math.min(math.abs(delta) - half, math.pi / 2))
			else 0
		local over = math.max(0, distance - EatsaPizza.Reach(stage, radius))
		if side <= EatsaPizza.SIDE_LEEWAY and over <= EatsaPizza.EDGE_LEEWAY then
			local out = side + over
			if out < bestOut then
				best, bestOut = index, out
			end
		end
	end
	return best
end

return EatsaPizza

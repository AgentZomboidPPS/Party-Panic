--!strict
-- Eatsa Pizza's shared rules: the pizza's geometry (twelve slices round a middle), how much of a
-- slice is left at each stage of being eaten, and the BITE SPOTS: where a team's next one may go,
-- how many bites it holds, and which one a player stands on. The server places spots with PlaceSpot
-- and judges bites with OnSpot; the client uses OnSpot too to tell a player whether they're on a
-- spot they can eat, so what the HUD says is what the server does.
--
-- Angles: slice i (1..SLICES) points from the middle along (sin a, cos a) in world X, Z, with
-- a = (i - 0.5) * SLICE_ANGLE. A slice's meshes (tools/meshgen/props/EatsaPizza.py) are drawn at
-- radius MESH_RADIUS with the tip at the origin; stage k of a slice reaches REACH[k + 1] of the
-- pizza's radius (the bites in its front go up to BITE_DEPTH mesh studs deeper).

local EatsaPizza = {}

EatsaPizza.SLICES = 12
EatsaPizza.SLICE_ANGLE = 2 * math.pi / 12
EatsaPizza.MESH_RADIUS = 20 -- the slice meshes' radius as drawn
EatsaPizza.MESH_CHEESE = 0.31 -- the cheese's top in the meshes (pepperoni sit on it)
EatsaPizza.REACH = { 1.0, 0.8, 0.6, 0.38 } -- how far stage 0..3 reaches (share of the radius)
EatsaPizza.STAGES = { "EatsaPizzaSlice", "EatsaPizzaSlice1", "EatsaPizzaSlice2", "EatsaPizzaSlice3" }
EatsaPizza.BITE_DEPTH = 1.7 -- mesh studs: the crust's width, and how deep a stage's tooth marks go

-- (With running between spots, a player eats about one spot's bites a second and a half: 60 bites
-- is about 20 s of play for a quick player, 25 s for a slow one.)
EatsaPizza.PER_PLAYER = 60 -- bites a team has to eat for each of its players
EatsaPizza.PEPPERONI_WEIGHT = 0.14 -- each pepperoni makes its slice this share bigger
EatsaPizza.RATE = 8 -- bites a second, at most (a quick human's mashing: an auto-clicker gains little)
EatsaPizza.BURST = 4
EatsaPizza.MIDDLE = 2.5 -- the very middle, where every slice's tip meets, is nobody's slice

-- BITE SPOTS (owner: "eatza pizza is better. can we make players run around while eating instead of
-- just sitting on the slice?"): nobody chews wherever they stand any more. Glowing spots light up on
-- each team's slices, one for each of its players; standing on one and mashing EAT eats it (about
-- SPOT_BITES bites, each one a bite of the slice it's on, so slices still shrink stage by stage and
-- their pepperoni still fly), and when it's eaten it pops and a new one lights up somewhere else on
-- the team's part, about SPOT_RUN studs from whoever ate it and away from the team's other spots, so
-- everybody keeps running. Every team gets the same deal per player: one spot each, the same bites
-- in each, the same run to the next.
--
-- A spot only ever goes where there's food for all of it: it claims its bites from its slice (no
-- slice ever has more bites claimed than it has left), and it sits inside what the slice will still
-- be when its last claimed bite is eaten (the slice shrinks from the crust, so a spot out near the
-- crust is only for a slice with plenty left). A slice's last few bites go to one spot, not to a
-- spot of two bites at the end (SpotBites).
EatsaPizza.SPOT_BITES = 6 -- bites in a spot: about a second of quick mashing
EatsaPizza.SPOT_RADIUS = 2.6 -- the ring drawn on the cheese (studs)
EatsaPizza.SPOT_REACH = 3.3 -- standing this close (flat studs) to a spot's middle is standing on it: its
-- ring and a bit (a character's half width), so feet on the ring count
EatsaPizza.SPOT_RUN = 13 -- a new spot goes about this far from whoever ate the last one (studs: under a
-- second's run)
EatsaPizza.SPOT_GAP = 9 -- a team's spots keep this far apart while there's room
EatsaPizza.SPOT_INNER = 4.5 -- never nearer the middle than this: the tips are narrow and everyone's
EatsaPizza.SPOT_ROW = 2.5 -- studs between the places tried along a slice

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

-- Bite spots --------------------------------------------------------------------------------------

-- A team's slice as PlaceSpot sees it, and a spot in play (X, Z: offset from the pizza's middle,
-- studs; Left: bites still to eat at it; Mine: one of the team being placed for).
export type SliceInfo = { Index: number, Left: number, Max: number, Stage: number }
export type SpotInfo = { Slice: number?, X: number, Z: number, Left: number, Mine: boolean? }
export type Placed = { Slice: number, X: number, Z: number, Bites: number }

-- How many spots a team with `players` players has out at a time: one each.
function EatsaPizza.SpotsFor(players: number): number
	return math.max(math.floor(players), 0)
end

-- The bites a new spot takes from a slice with `unclaimed` bites no other spot has claimed: about
-- SPOT_BITES, the slice's rest shared out evenly so its last spot isn't a tiny one.
function EatsaPizza.SpotBites(unclaimed: number): number
	if unclaimed <= 0 then
		return 0
	end
	local chunks = math.max(1, math.floor(unclaimed / EatsaPizza.SPOT_BITES + 0.5))
	return math.ceil(unclaimed / chunks)
end

-- The stage a slice is at while the last of its claimed bites is still to eat, when `rest` of its
-- `max` bites are left unclaimed (a spot sitting on it must be inside that stage).
function EatsaPizza.SpotStage(rest: number, max: number): number
	return EatsaPizza.Stage(math.max(rest, 0) + 1, max)
end

-- The farthest from the middle (studs) a spot's middle may sit on a slice drawn at `stage`: its whole
-- ring on the cheese, inside the crust or the stage's tooth marks.
function EatsaPizza.SpotOuter(stage: number, radius: number): number
	local scale = radius / EatsaPizza.MESH_RADIUS
	return EatsaPizza.Reach(stage, radius) - EatsaPizza.BITE_DEPTH * scale - EatsaPizza.SPOT_RADIUS * 0.8
end

-- The places tried for a spot on slice `index`, out to `outer` studs from the middle: rows across the
-- slice every SPOT_ROW studs, a few across each (the ring may lean a little over the slice's sides).
function EatsaPizza.SpotPoints(index: number, outer: number): { { X: number, Z: number } }
	local inner = EatsaPizza.SPOT_INNER
	local a = EatsaPizza.Angle(index)
	local sinA, cosA = math.sin(a), math.cos(a)
	local points = {}
	local far = math.max(outer, EatsaPizza.MIDDLE)
	local rows = if far <= inner then 1 else math.floor((far - inner) / EatsaPizza.SPOT_ROW) + 1
	for row = 0, rows - 1 do
		local d = if far <= inner then far else far - row * EatsaPizza.SPOT_ROW
		local room = d * math.sin(EatsaPizza.SLICE_ANGLE / 2) - EatsaPizza.SPOT_RADIUS * 0.5
		local lanes: { number } = if room > 2.4
			then { 0, -0.5, 0.5, -1, 1 }
			elseif room > 0.8 then { 0, -1, 1 }
			else { 0 }
		for _, lane in lanes do
			local side = lane * math.max(room, 0)
			local along = math.sqrt(math.max(d * d - side * side, 0))
			table.insert(points, { X = sinA * along + cosA * side, Z = cosA * along - sinA * side })
		end
	end
	return points
end

-- How good (x, z) is for a team's new spot (higher is better; nil: not allowed): never on another
-- spot's ring, about SPOT_RUN from `from` (whoever ate the last one: nearer is worse than farther),
-- and SPOT_GAP from the team's other spots.
function EatsaPizza.SpotScore(x: number, z: number, from: { X: number, Z: number }?, spots: { SpotInfo }): number?
	local score = 0
	for _, other in spots do
		local dx, dz = x - other.X, z - other.Z
		local gap = math.sqrt(dx * dx + dz * dz)
		if gap < EatsaPizza.SPOT_RADIUS * 2 then
			return nil
		end
		if other.Mine and gap < EatsaPizza.SPOT_GAP then
			score -= (EatsaPizza.SPOT_GAP - gap) * 3
		end
	end
	if from then
		local dx, dz = x - from.X, z - from.Z
		local d = math.sqrt(dx * dx + dz * dz)
		score -= if d < EatsaPizza.SPOT_RUN then (EatsaPizza.SPOT_RUN - d) * 2 else (d - EatsaPizza.SPOT_RUN) * 0.6
	end
	return score
end

-- Where a team's next spot goes: on one of its `slices` with bites nobody has claimed, at the best
-- place by SpotScore (`jitter()`, 0..1, mixes it up a little; `spots` is every spot in play, the
-- team's marked Mine). A spot takes SpotBites of its slice's unclaimed bites, or fewer when that many
-- would shrink the slice out from under a spot already on it (a smaller spot scores lower), so every
-- spot is on food until it's eaten. nil when the team has no bites left to claim (or no room).
function EatsaPizza.PlaceSpot(
	slices: { SliceInfo },
	spots: { SpotInfo },
	radius: number,
	from: { X: number, Z: number }?,
	jitter: (() -> number)?
): Placed?
	local best: Placed? = nil
	local bestScore = -math.huge
	for _, slice in slices do
		local claimed = 0
		local farthest = 0
		for _, spot in spots do
			if spot.Mine and spot.Slice == slice.Index then
				claimed += spot.Left
				farthest = math.max(farthest, math.sqrt(spot.X * spot.X + spot.Z * spot.Z))
			end
		end
		local unclaimed = slice.Left - claimed
		if unclaimed <= 0 then
			continue
		end
		local full = EatsaPizza.SpotBites(unclaimed)
		local bites, outer = full, 0
		while bites >= 1 do
			local stage = math.max(slice.Stage, EatsaPizza.SpotStage(unclaimed - bites, slice.Max))
			outer = EatsaPizza.SpotOuter(stage, radius)
			if farthest <= outer + 1e-6 then
				break
			end
			bites -= 1
		end
		if bites < 1 then
			continue -- (a spot further out has to be eaten first)
		end
		for _, point in EatsaPizza.SpotPoints(slice.Index, outer) do
			local score = EatsaPizza.SpotScore(point.X, point.Z, from, spots)
			if score then
				-- (A little more on fuller slices, so the pizza goes down evenly.)
				score += unclaimed * 0.02 - (full - bites) * 1.5 + (if jitter then jitter() * 2 else 0)
				if score > bestScore then
					best, bestScore = { Slice = slice.Index, X = point.X, Z = point.Z, Bites = bites }, score
				end
			end
		end
	end
	return best
end

-- Which of `spots` (offset from the pizza's middle, studs) someone standing at offset (x, z) is on:
-- the nearest within SPOT_REACH, or nil.
function EatsaPizza.OnSpot(x: number, z: number, spots: { { X: number, Z: number } }): number?
	local best, bestDistance = nil, EatsaPizza.SPOT_REACH
	for index, spot in spots do
		local dx, dz = x - spot.X, z - spot.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d <= bestDistance then
			best, bestDistance = index, d
		end
	end
	return best
end

return EatsaPizza

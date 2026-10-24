-- Capy Go Boom's shared rules: the numbers, the size curve, the snacks and the shell's hit test that the
-- server judges with and the client draws with, so a shell that looks like it touched a capy on screen is
-- the shell the rule counts (owner: "the precision games will feel super bad if we dont"). See
-- src/server/MiniGames/CapyGoBoom.luau for how the mode works.
--
-- Brought over from the owner's other game, CAPY GO BOOM (eat snacks to grow, blast rivals, a popped capy
-- spills food): the same loop, boiled down to a 75 second party round.

local Rules = {}

Rules.UNIT = "KG"
Rules.START_MASS = 20 -- every capy starts here
Rules.MIN_MASS = 10 -- a capy is never popped below this (nobody is out; you keep playing)

-- Size ---------------------------------------------------------------------------------------------
-- A capy's drawn size follows its weight (the hit circle and the eating reach follow the drawn size),
-- and a bigger capy is a little slower, a smaller one a little quicker.
Rules.MAX_SCALE = 2.2
Rules.MIN_SCALE = 0.7

function Rules.ScaleOf(mass: number): number
	return math.clamp((math.max(mass, 1) / Rules.START_MASS) ^ 0.42, Rules.MIN_SCALE, Rules.MAX_SCALE)
end

function Rules.SpeedFactor(scale: number): number
	return math.clamp(1.25 - 0.25 * scale, 0.7, 1.1)
end

Rules.BODY_R = 2.2 -- hit circle radius at scale 1 (the drawn capy is 4.5 wide, 5.8 long)
Rules.HIT_HEIGHT = 3.4 -- a shell flies at the shooter's height: a jump over it (this far up) dodges it

-- (a big capy is a bigger target, but not a whole drawn size bigger: it would be hit by shells that
-- look like they miss, and a capy that has grown shouldn't just be shot at)
-- How far above or below a capy's height a shell still hits it. It grows with size but is capped, so even
-- the biggest capy (whose jump is the same as everyone's, about 7 studs) can hop over a shell.
function Rules.HitTolerance(scale: number): number
	return Rules.HIT_HEIGHT * math.min(scale, 1.6)
end

function Rules.HitRadius(scale: number): number
	return Rules.BODY_R * scale ^ 0.85
end

-- Eating: a landed snack is eaten by the nearest capy whose middle is within reach (flat).
function Rules.EatReach(scale: number): number
	return 2.4 + 1.6 * scale
end

-- The arena ----------------------------------------------------------------------------------------
function Rules.ArenaRadius(count: number): number
	return math.clamp(32 + 2.4 * count, 40, 60)
end

function Rules.TargetSnacks(count: number): number
	return 22 + 7 * count
end

-- New snacks sprouting per second while the lawn is below its target (double in the FEAST): the food
-- is mostly what the pops spill, so this only keeps the lawn from running dry.
function Rules.RefillRate(count: number): number
	return 0.15 * count
end

Rules.MAX_SNACKS = 150
Rules.ROCK_R = 3.6 -- a standing stone's radius (shells stop at it; the stone is a drawn pillar this wide)
Rules.WALL_THICK = 3

-- Snacks -------------------------------------------------------------------------------------------
-- The snacks are the ones in the owner's CAPY GO BOOM (its FoodTemplates): each kind has a few foods
-- that look different but weigh the same. Kind 4 only comes in a SNACK DROP. Weight is how often a kind
-- shows up when the lawn is restocked.
Rules.SNACKS = {
	{
		Name = "Small Snack",
		Mass = 2,
		Weight = 60,
		Color = Color3.fromRGB(255, 120, 120),
		Props = { "CapyBoomStrawberry", "CapyBoomBanana", "CapyBoomCarrot", "CapyBoomBlueberries", "CapyBoomAvocado" },
	},
	{
		Name = "Tasty Snack",
		Mass = 4,
		Weight = 28,
		Color = Color3.fromRGB(255, 190, 90),
		Props = { "CapyBoomPizza", "CapyBoomBurger", "CapyBoomIceCream", "CapyBoomPancakes", "CapyBoomOrange" },
	},
	{
		Name = "Big Snack",
		Mass = 9,
		Weight = 10,
		Color = Color3.fromRGB(120, 205, 90),
		Props = { "CapyBoomWatermelon" },
	},
	{
		Name = "Golden Apple",
		Mass = 25,
		Weight = 0,
		Color = Color3.fromRGB(255, 205, 60),
		Props = { "CapyBoomGoldenApple" },
	},
}
Rules.SMALL, Rules.TASTY, Rules.BIG, Rules.GOLD = 1, 2, 3, 4

-- Which food a snack is drawn as: the same on every screen, from its id.
function Rules.PropOf(kind: number, id: number): string
	local list = Rules.SNACKS[kind].Props
	return list[id % #list + 1]
end

-- How a snack comes into the world (the 8th number of its record): it sprouts where it lies, it flies
-- in an arc (a spill), or it drops from the sky (a SNACK DROP).
Rules.SPROUT, Rules.ARC, Rules.SKY = 0, 1, 2
Rules.FLIGHT = { [0] = 0.4, [1] = 0.7, [2] = 1.5 }
Rules.SKY_HEIGHT = 34
Rules.ARC_HEIGHT = 4.5

-- The snacks that make up exactly `amount` of weight (a spill), at most `maxPieces` (8): big snacks (9) in
-- pairs for the big spills, then tasty (4) and small (2) ones, so an even amount adds up exactly and a pop
-- only ever moves weight around. An odd amount (a leaver's) takes one big snack first; weight past the
-- piece limit, or a last odd 1, is lost.
function Rules.Pieces(amount: number, maxPieces: number?): { number }
	local list = {}
	local limit = maxPieces or 8
	local left = amount
	if left % 2 == 1 then
		if left >= 9 then
			table.insert(list, Rules.BIG)
			left -= 9
		else
			left -= 1
		end
	end
	while left >= 22 and #list + 2 <= limit do
		table.insert(list, Rules.BIG)
		table.insert(list, Rules.BIG)
		left -= 18
	end
	while left > 0 and #list < limit do
		if left >= 4 then
			table.insert(list, Rules.TASTY)
			left -= 4
		else
			table.insert(list, Rules.SMALL)
			left -= 2
		end
	end
	return list
end

-- Where a snack is at server time t: { id, kind, x, z, fromX, fromZ, t0, style }. Returns the flat
-- offset from the arena's middle and its height above the ground.
function Rules.SnackAt(snack: { number }, t: number): (number, number, number)
	local x, z, fx, fz, t0, style = snack[3], snack[4], snack[5], snack[6], snack[7], snack[8]
	local k = math.clamp((t - t0) / Rules.FLIGHT[style], 0, 1)
	if style == Rules.SKY then
		return x, z, Rules.SKY_HEIGHT * (1 - k * k)
	end
	return fx + (x - fx) * k, fz + (z - fz) * k, if style == Rules.ARC then Rules.ARC_HEIGHT * 4 * k * (1 - k) else 0
end

function Rules.Landed(snack: { number }, t: number): boolean
	return t >= snack[7] + Rules.FLIGHT[snack[8]]
end

-- The cannon -----------------------------------------------------------------------------------------
Rules.SHELL_SPEED = 80 -- studs a second
Rules.SHELL_RANGE = 64
Rules.SHELL_R = 0.8
Rules.RELOAD = 0.9 -- seconds between BOOMs
Rules.ASSIST_FREE = math.rad(26) -- touch: the way you face, bent toward a rival within this
Rules.ASSIST_AIMED = math.rad(6) -- PC: where the mouse points, bent a little
Rules.MAX_SHELLS = 40

-- How far in front of the capy's middle the cannon's muzzle is drawn (the original's starter blaster sits
-- 3.8 studs ahead of the pivot at scale 1). The server's shell starts at the capy itself, so whoever is in
-- front of the cannon is hit; clients draw it from the muzzle.
function Rules.Muzzle(scale: number): number
	return 3.6 * scale
end

-- A pop ----------------------------------------------------------------------------------------------
Rules.SAFE = 1.5 -- seconds after a pop that a capy can't be popped again (it blinks)
Rules.STUN = 0.45 -- the stagger
Rules.KNOCK = 34
Rules.KNOCK_UP = 16
Rules.OWN_SPILL = 1.6 -- seconds before a popped capy can eat its own spill

-- How much a pop knocks off: a fifth of the weight (a quarter for the leader, so the front can be
-- caught), 4 at least, 40 at most, and never below MIN_MASS.
-- (always an even number, so the snacks it becomes add up to it exactly: Pieces)
function Rules.SpillOf(mass: number, leader: boolean): number
	local amount = math.clamp(math.floor(mass * (if leader then 0.26 else 0.2) + 0.5), 4, 40)
	amount = math.max(0, math.min(amount, mass - Rules.MIN_MASS))
	return amount - amount % 2
end

-- Rounds ---------------------------------------------------------------------------------------------
Rules.DROPS = { 0.24, 0.55 } -- SNACK DROPS, as a fraction of the round
Rules.DROP_WARN = 2.5 -- seconds of warning (a beam of light where it will land)
Rules.DROP_SNACKS = 12
Rules.DROP_SPREAD = 8
Rules.FEAST = 12 -- the last seconds: everything eaten counts double

-- The shell's path from `origin` along `dir` (flat, unit): where it is after `age` seconds.
function Rules.ShellAt(origin: Vector3, dir: Vector3, age: number): Vector3
	return origin + dir * (Rules.SHELL_SPEED * age)
end

-- Where the segment a->b (flat) first gets inside the circle (c, r), as how far along it, 0..1: 0 if
-- it starts inside, nil if it never gets there.
function Rules.SegmentEnter(ax: number, az: number, bx: number, bz: number, cx: number, cz: number, r: number): number?
	local dx, dz = bx - ax, bz - az
	local fx, fz = ax - cx, az - cz
	local c = fx * fx + fz * fz - r * r
	if c <= 0 then
		return 0
	end
	local a = dx * dx + dz * dz
	if a < 1e-9 then
		return nil
	end
	local b = 2 * (fx * dx + fz * dz)
	local disc = b * b - 4 * a * c
	if disc < 0 then
		return nil
	end
	local t = (-b - math.sqrt(disc)) / (2 * a)
	if t >= 0 and t <= 1 then
		return t
	end
	return nil
end

-- Where the segment a->b (flat, starting inside the circle (c, r)) gets out of it, 0..1, or nil if it
-- stays inside.
function Rules.SegmentLeaves(ax: number, az: number, bx: number, bz: number, cx: number, cz: number, r: number): number?
	local dx, dz = bx - ax, bz - az
	local fx, fz = ax - cx, az - cz
	local a = dx * dx + dz * dz
	if a < 1e-9 then
		return nil
	end
	local b = 2 * (fx * dx + fz * dz)
	local c = fx * fx + fz * fz - r * r
	local disc = b * b - 4 * a * c
	if disc < 0 then
		return nil
	end
	local t = (-b + math.sqrt(disc)) / (2 * a)
	if t >= 0 and t <= 1 then
		return t
	end
	return nil
end

-- One colour per player slot (the scarf, the cannon's rim, the shell, the tag). Colour is never the
-- only cue: every tag carries the player's name.
Rules.COLORS = {
	Color3.fromRGB(235, 70, 70),
	Color3.fromRGB(70, 140, 245),
	Color3.fromRGB(250, 205, 50),
	Color3.fromRGB(90, 205, 95),
	Color3.fromRGB(170, 110, 240),
	Color3.fromRGB(250, 140, 50),
	Color3.fromRGB(50, 200, 200),
	Color3.fromRGB(250, 120, 190),
	Color3.fromRGB(245, 245, 250),
	Color3.fromRGB(70, 80, 180),
	Color3.fromRGB(190, 235, 60),
	Color3.fromRGB(215, 40, 150),
}

return Rules

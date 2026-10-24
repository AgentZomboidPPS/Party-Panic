--!strict
-- Big Bad Vacuum's shared rules: the arena and boss sizes, the attacks (their timings and the shapes
-- they threaten), the damage and scoring numbers, and the geometry that judges them. The server uses
-- these to judge every hit, the bots use them to read the boss, and the client draws the very same
-- danger zones, so what a player sees on screen is what the server counts (the same promise the
-- precision games make: "if it looks like a hit it is one, and if it looks like a miss it isn't").
--
-- The fight in one paragraph: a giant robot vacuum rolls out of its charging dock. Everyone is on the
-- same side. Players grab toy bricks from the piles and lob them at the boss; bricks only really hurt
-- (a CRIT) while its weak spot, the CORE hatch on top, is open, which it is after the boss crashes into
-- a wall (CHARGE), overheats (SUCTION) or gets dizzy (WHIRL). A SUCTION also pulls people into its dust
-- bag, and a brick thrown at the bag pops it and frees them. Damage and rescues fill the PANIC METER;
-- when it is full anyone can fire a PANIC BLAST. Three phases, each nastier than the last.
--
-- How you lose (the owner played it live and asked: "how do you loose this? maybe after 3 hits or
-- something?"; until then nobody was ever out and only the clock could beat the lobby). Everyone starts
-- the fight with HEARTS (3) hearts, bots too. Every attack that lands on you (the hit that dazes you)
-- costs one, once per attack: one swing, one charge, one shockwave or one dust bomb is one heart however
-- long it overlaps you (FirstStrike), and the daze and the grace after it still stop a hit from chaining.
-- The dust bag is not a hit: being sucked up already costs you up to TRAP_TIME seconds of the fight and
-- heals the boss, the lobby can pop you out, and it catches a few people at once, so a heart for it too
-- would turn every SUCTION into a pile of knockouts at the end of a fight. At no hearts you are KNOCKED
-- OUT (Hurt): out of the round like any Survival mode's out, spectating, your damage and rescues still in
-- the results. Once nobody is left standing the Vacuum wins at once (WipedOut), with the same show and
-- results as a fight lost on the clock. "Nobody" means no person: a round is for people (RoundContext ends
-- a round whose people are all out a moment later), so bots never carry on a fight on their own.
--
-- Leaf module: no requires, no Roblox APIs (positions are plain x / z numbers), so it can be unit tested
-- under Lune.

local BigBadVacuum = {}

export type Zone = {
	K: string, -- "Sector" | "Cone" | "Lane" | "Disc" | "Whirl"
	X: number,
	Z: number,
	A: number?, -- facing / direction (radians, atan2(z, x))
	Arc: number?, -- full angle of a sector or cone (radians)
	R: number, -- reach / radius
	L: number?, -- a lane's length
	W: number?, -- a lane's half width
	T0: number, -- server time the telegraph starts
	T1: number, -- server time it stops being a warning and starts hurting
	T2: number, -- server time it is over
	Id: number?,
}

-- Sizes -----------------------------------------------------------------------------------------------

BigBadVacuum.BODY_RADIUS = 13 -- the boss's round body (studs)
BigBadVacuum.CORE_HEIGHT = 14.8 -- the weak spot's height above the floor, on top of the dome
BigBadVacuum.BAG_HEIGHT = 17 -- the dust bag's centre above the floor
BigBadVacuum.BAG_BACK = 12 -- ... and how far behind the boss's centre
BigBadVacuum.BAG_RADIUS = 7
BigBadVacuum.STAND = 3 -- a standing character's root above the floor
BigBadVacuum.PHASE_AT = { 0.68, 0.34 } -- health fractions where phases 2 and 3 begin

-- The wall blocks' inside edge for `count` players (the floor under them is a rug a little wider).
function BigBadVacuum.RadiusFor(count: number): number
	return math.clamp(46 + 1.5 * count, 52, 66)
end

-- The boss's health for `count` players: about the damage that many players do in a fight they win
-- with a little time to spare. A small squad gets less each: with fewer people the boss's attacks come
-- round to each of them more often, so each throws less (on test servers with bots, at 100 a player a
-- duo never won and four won half the time, at the buzzer; eight or more won in 65-80 s; at 125 for two
-- a duo won one in three, at 300 four won three in three). 100 for two, 291 for four, 542 for six, 800 for
-- eight.
--
-- Past eight each player gets more, because a big lobby spreads the boss's attacks thinner still (with the
-- hearts, 2026-10-24: at 100 a player, twelve won 6 rounds of 6 at 57-77 s, eight 7 of 8 at 70-84 s, and
-- knockouts came almost only in phase 3; the aim is about two wins in three for a strong full lobby). 954 for
-- nine, 1488 for twelve.
function BigBadVacuum.HealthFor(count: number): number
	local players = math.clamp(count, 1, 12)
	local short = math.max(0, 8 - players) / 6 -- how far short of eight the squad is (1 for a duo)
	local each = math.max(45, 100 - 50 * short ^ 1.5) + 6 * math.max(0, players - 8)
	return math.floor(players * each + 0.5)
end

function BigBadVacuum.PilesFor(count: number): number
	return math.clamp(math.ceil(count / 2) + 2, 4, 8)
end

-- How many people the dust bag holds.
function BigBadVacuum.BagCapacity(count: number): number
	return math.clamp(math.ceil(count / 3) + 1, 2, 5)
end

function BigBadVacuum.PhaseFor(fraction: number): number
	if fraction <= BigBadVacuum.PHASE_AT[2] then
		return 3
	elseif fraction <= BigBadVacuum.PHASE_AT[1] then
		return 2
	end
	return 1
end

-- Timings (seconds) ---------------------------------------------------------------------------------------

BigBadVacuum.INTRO = 5.5 -- the boss rolls out of its dock; nobody can be hurt yet
BigBadVacuum.FIGHT = 82 -- the fight's clock, from the end of the intro
BigBadVacuum.BREAK = 3 -- a phase change: the boss roars and nobody can hurt it
BigBadVacuum.VICTORY_SHOW = 5.2 -- the boss falls apart, then the results
BigBadVacuum.DEFEAT_SHOW = 4.4
BigBadVacuum.TRAP_TIME = 7 -- the dust bag spits someone out after this long
BigBadVacuum.DAZE = 1.3 -- hit by an attack: a heart gone, stunned (and drops their brick) this long
BigBadVacuum.SAFE = 2 -- ... then can't be hit again for this long
BigBadVacuum.PILE_WAIT = 0.9 -- a pile hands out a brick this often
BigBadVacuum.THROW_WAIT = 0.45 -- the quickest a player throws again
BigBadVacuum.PICKUP = 4.6 -- how close to a pile (flat) picks a brick up
BigBadVacuum.THROW_RANGE = 80 -- farthest a brick can be thrown from the boss's centre
BigBadVacuum.VOLLEY_WINDOW = 1.3 -- crits this close together make a volley

-- Damage and scoring ----------------------------------------------------------------------------------------

BigBadVacuum.CRIT = 10 -- a brick on the open core
BigBadVacuum.CHIP = 1 -- a brick on the armour
BigBadVacuum.BLAST = 0.08 -- the PANIC BLAST: this share of the boss's health
BigBadVacuum.METER_PER_DAMAGE = 0.4 -- (a blast's own damage doesn't fill it)
BigBadVacuum.METER_PER_RESCUE = 10
BigBadVacuum.RESCUE_POINTS = 8
BigBadVacuum.FINISHER_POINTS = 15
BigBadVacuum.BLAST_OPEN = 2.4 -- the blast overloads the core for this long
BigBadVacuum.PANIC_POINTS = 10 -- whoever presses PANIC
BigBadVacuum.PANIC_SHARE = 5 -- everyone else
BigBadVacuum.HEAL_PER_SECOND = 0.004 -- each second someone is in the bag, the boss heals this share...
BigBadVacuum.HEAL_CAP = 0.08 -- ... but never more than this share of its health in a phase

-- Crits thrown close together (a volley) hit harder: x1, then up to x1.6 for four or more.
function BigBadVacuum.Volley(count: number): number
	return 1 + 0.2 * math.clamp(count - 1, 0, 3)
end

-- A player's score for the round: damage, rescues and one-off bonuses.
function BigBadVacuum.Score(damage: number, rescues: number, bonus: number): number
	return math.floor(damage + 0.5) + rescues * BigBadVacuum.RESCUE_POINTS + bonus
end

-- Hearts and knockouts (see the top of this file) -----------------------------------------------------------

BigBadVacuum.HEARTS = 3 -- everyone starts the fight with this many (owner: "maybe after 3 hits or something?")
BigBadVacuum.KO_SHOW = 1.6 -- a knocked-out player's flight plays out before they leave the arena
BigBadVacuum.CAREFUL_AT = 1 -- bots play it safer with this many hearts left (or fewer)

-- What an attack that lands leaves someone with: one heart fewer (never below none), and whether that was
-- their last one (knocked out).
function BigBadVacuum.Hurt(hearts: number): (number, boolean)
	local left = math.max(0, math.floor(hearts + 0.5) - 1)
	return left, left == 0
end

-- Whether attack instance `instance` (one swing, one charge, one slam and its shockwave, one dust bomb) may
-- still cost the owner of `record` a heart: only the first time it reaches them. Remembers it.
function BigBadVacuum.FirstStrike(record: { [string]: boolean }, instance: string): boolean
	if record[instance] then
		return false
	end
	record[instance] = true
	return true
end

-- Whether knockouts have lost the fight: nobody left standing, or no person among them (bots never fight
-- on alone: a round is for people).
function BigBadVacuum.WipedOut(standing: number, peopleStanding: number): boolean
	return standing <= 0 or peopleStanding <= 0
end

-- Attacks -----------------------------------------------------------------------------------------------
-- Wind: the telegraph (a warning you can read and dodge); Act: the hit; Recover: the boss is a sitting
-- duck for a moment (no weak spot though: only a Stun opens the core).

BigBadVacuum.Attacks = {
	Sweep = { Wind = 1.15, Act = 0.5, Recover = 0.6, Reach = 29, Arc = math.rad(156), Pad = 0.14 },
	Whirl = { Wind = 1.3, Act = 2.6, Recover = 0.3, Reach = 28, Turns = 2.2, Pad = 0.12, Dizzy = 3.8 },
	Charge = { Wind = 1.5, Recover = 0.2, Speed = 64, HalfWidth = 14.5, Stun = { 6.4, 5.6, 5 } },
	Suction = {
		Wind = 1.1,
		Act = 3.2,
		Recover = 0.2,
		Reach = 50,
		Arc = math.rad(104),
		Mouth = 8,
		Stun = { 3.8, 3.4, 3 },
	},
	Cord = { Wind = 1.0, Act = 0.25, Recover = 0.8, Radius = 8.5, Lock = 0.4 },
	Bombs = { Wind = 0.9, Act = 1.7, Recover = 0.9, Radius = 9, Stagger = 0.2 },
} :: { [string]: { [string]: any } }

-- The shockwave a cord slam sends out: a ring you jump over.
BigBadVacuum.RING_SPEED = 26
BigBadVacuum.RING_MAX = 27
BigBadVacuum.RING_THICK = 3.8
BigBadVacuum.RING_CLEAR = 2.4 -- feet this far above the floor are over it (a standing root is STAND up)

-- Which attacks open the core when they end.
BigBadVacuum.Stuns = { Charge = true, Suction = true, Whirl = true } :: { [string]: boolean }

-- Seconds the boss chases before its next attack, by phase.
function BigBadVacuum.Think(phase: number): number
	return ({ 2.4, 1.7, 1.15 })[phase] or 2
end

-- How long an attack's warning lasts in `phase`: it gets quicker, so later phases ask for quicker feet.
BigBadVacuum.WIND_SCALE = { 1, 0.88, 0.76 }
function BigBadVacuum.WindFor(kind: string, phase: number): number
	local attack = BigBadVacuum.Attacks[kind]
	if not attack then
		return 1
	end
	return math.max(attack.Wind * BigBadVacuum.WIND_SCALE[math.clamp(phase, 1, 3)], 0.7)
end

-- How fast it chases (studs/s; a player walks 16).
function BigBadVacuum.ChaseSpeed(phase: number): number
	return ({ 7, 8.5, 10 })[phase] or 7
end

-- Seconds the core stays open after `kind` ends in `phase`.
function BigBadVacuum.StunFor(kind: string, phase: number): number
	local attack = BigBadVacuum.Attacks[kind]
	if not attack then
		return 0
	end
	if kind == "Whirl" then
		return attack.Dizzy
	end
	local stun = attack.Stun
	return if stun then stun[math.clamp(phase, 1, #stun)] else 0
end

-- Which attacks each phase uses, with weights (an array so the order is the same everywhere).
local MENU: { { { string | number } } } = {
	{ { "Sweep", 35 }, { "Charge", 40 }, { "Suction", 25 } },
	{ { "Sweep", 20 }, { "Charge", 28 }, { "Suction", 20 }, { "Cord", 32 } },
	{ { "Sweep", 12 }, { "Whirl", 14 }, { "Charge", 20 }, { "Suction", 14 }, { "Cord", 20 }, { "Bombs", 20 } },
}

-- The next attack from a 0..1 roll: never the same twice in a row, and after two attacks that left no
-- opening a Charge (so the players always get their chance at the core).
function BigBadVacuum.NextAttack(phase: number, last: string?, sinceStun: number, roll: number): string
	if sinceStun >= 2 and last ~= "Charge" then
		return "Charge"
	end
	local menu = MENU[math.clamp(phase, 1, #MENU)]
	local total = 0
	for _, entry in menu do
		if entry[1] ~= last then
			total += entry[2] :: number
		end
	end
	local pick = math.clamp(roll, 0, 0.9999) * total
	for _, entry in menu do
		if entry[1] ~= last then
			pick -= entry[2] :: number
			if pick < 0 then
				return entry[1] :: string
			end
		end
	end
	return menu[1][1] :: string
end

-- Geometry (flat, on the floor; angles are atan2(z, x); positions are plain numbers) -------------------------

local TAU = math.pi * 2

-- The unit vector (x, z) at `angle`.
function BigBadVacuum.Dir(angle: number): (number, number)
	return math.cos(angle), math.sin(angle)
end

function BigBadVacuum.AngleOf(x: number, z: number): number
	return math.atan2(z, x)
end

-- `angle` wrapped into [0, 2*pi).
local function wrap(angle: number): number
	return angle - math.floor(angle / TAU) * TAU
end
BigBadVacuum.Wrap = wrap

-- The signed turn from angle a to angle b, in (-pi, pi].
function BigBadVacuum.Turn(a: number, b: number): number
	local d = wrap(b - a)
	return if d > math.pi then d - TAU else d
end

local function distance(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = ax - bx, az - bz
	return math.sqrt(dx * dx + dz * dz)
end
BigBadVacuum.Distance = distance

-- Whether a bearing lies on the arc swept from angle a0 turning `span` radians (counter-clockwise),
-- padded by `pad` on both ends.
local function onArc(bearing: number, a0: number, span: number, pad: number): boolean
	return wrap(bearing - (a0 - pad)) <= span + 2 * pad
end
BigBadVacuum.OnArc = onArc

-- Whether (px, pz) is inside the cone with its apex at (x, z), facing `angle`, full angle `arc`.
function BigBadVacuum.InCone(
	x: number,
	z: number,
	angle: number,
	arc: number,
	reach: number,
	px: number,
	pz: number
): boolean
	local dx, dz = px - x, pz - z
	local away = math.sqrt(dx * dx + dz * dz)
	if away > reach then
		return false
	end
	if away < 0.05 then
		return true
	end
	return math.abs(BigBadVacuum.Turn(angle, math.atan2(dz, dx))) <= arc / 2
end

-- The Sweep's arm: it swings from one side of the boss's facing to the other as `f` goes 0 -> 1.
function BigBadVacuum.SweepAngle(facing: number, f: number): number
	local attack = BigBadVacuum.Attacks.Sweep
	return facing - attack.Arc / 2 + attack.Arc * f
end

-- Whether the Sweep's arm, between progress f0 and f1, passed over (px, pz) (between the body's edge
-- and the arm's reach, around the boss's centre at x, z).
function BigBadVacuum.SweepHits(
	x: number,
	z: number,
	facing: number,
	f0: number,
	f1: number,
	px: number,
	pz: number
): boolean
	local attack = BigBadVacuum.Attacks.Sweep
	local away = distance(px, pz, x, z)
	if away < BigBadVacuum.BODY_RADIUS - 1 or away > attack.Reach then
		return false
	end
	local a0 = BigBadVacuum.SweepAngle(facing, f0)
	local span = attack.Arc * math.max(f1 - f0, 0)
	return onArc(math.atan2(pz - z, px - x), a0, span, attack.Pad)
end

-- The Whirl's arm turns all the way round, `Turns` times over its Act, from `base`.
function BigBadVacuum.WhirlAngle(base: number, f: number): number
	return base + BigBadVacuum.Attacks.Whirl.Turns * TAU * f
end

function BigBadVacuum.WhirlHits(
	x: number,
	z: number,
	base: number,
	f0: number,
	f1: number,
	px: number,
	pz: number
): boolean
	local attack = BigBadVacuum.Attacks.Whirl
	local away = distance(px, pz, x, z)
	if away < BigBadVacuum.BODY_RADIUS - 1 or away > attack.Reach then
		return false
	end
	local a0 = BigBadVacuum.WhirlAngle(base, f0)
	local span = attack.Turns * TAU * math.max(f1 - f0, 0)
	if span >= TAU then
		return true
	end
	return onArc(math.atan2(pz - z, px - x), a0, span, attack.Pad)
end

-- Where the boss's centre stops when it charges from (sx, sz) along the unit vector (dx, dz): at the
-- wall, whose inside edge is `radius` from the arena's centre (cx, cz).
function BigBadVacuum.ChargeEnd(
	cx: number,
	cz: number,
	sx: number,
	sz: number,
	dx: number,
	dz: number,
	radius: number
): (number, number)
	local limit = radius - BigBadVacuum.BODY_RADIUS - 0.6
	local px, pz = sx - cx, sz - cz
	local along = px * dx + pz * dz
	local discriminant = along * along - (px * px + pz * pz) + limit * limit
	local s = if discriminant > 0 then math.max(-along + math.sqrt(discriminant), 0) else 0
	return sx + dx * s, sz + dz * s
end

-- How hard the Suction pulls someone `away` studs from the boss's centre (studs/s): hard near the
-- mouth, where a walking player (16) can't get away.
function BigBadVacuum.PullSpeed(away: number): number
	local reach = BigBadVacuum.Attacks.Suction.Reach
	return 10 + 26 * math.clamp(1 - away / reach, 0, 1)
end

-- Where the Suction's mouth is: just in front of the body.
function BigBadVacuum.MouthAt(x: number, z: number, facing: number): (number, number)
	local d = BigBadVacuum.BODY_RADIUS + 1.5
	return x + math.cos(facing) * d, z + math.sin(facing) * d
end

-- A cord slam's shockwave ring `elapsed` seconds after the slam: its radius.
function BigBadVacuum.RingRadius(elapsed: number): number
	return math.max(elapsed, 0) * BigBadVacuum.RING_SPEED
end

-- Whether the ring, between `e0` and `e1` seconds after the slam at (cx, cz), passed over a grounded
-- (px, pz) (`feet` is how far above the floor they are).
function BigBadVacuum.RingHits(
	cx: number,
	cz: number,
	e0: number,
	e1: number,
	px: number,
	pz: number,
	feet: number
): boolean
	if feet > BigBadVacuum.RING_CLEAR then
		return false
	end
	local away = distance(px, pz, cx, cz)
	local outer = BigBadVacuum.RingRadius(e1)
	local inner = BigBadVacuum.RingRadius(e0) - BigBadVacuum.RING_THICK
	return outer <= BigBadVacuum.RING_MAX + BigBadVacuum.RING_THICK and away <= outer and away >= inner
end

-- Whether (px, pz) is inside `zone`, the region it warns about.
function BigBadVacuum.ZoneContains(zone: Zone, px: number, pz: number): boolean
	local kind = zone.K
	if kind == "Disc" then
		return distance(px, pz, zone.X, zone.Z) <= zone.R
	elseif kind == "Sector" or kind == "Cone" then
		return BigBadVacuum.InCone(zone.X, zone.Z, zone.A or 0, zone.Arc or math.pi, zone.R, px, pz)
	elseif kind == "Whirl" then
		local away = distance(px, pz, zone.X, zone.Z)
		return away >= BigBadVacuum.BODY_RADIUS - 1 and away <= zone.R
	elseif kind == "Lane" then
		local angle = zone.A or 0
		local dx, dz = px - zone.X, pz - zone.Z
		local ux, uz = math.cos(angle), math.sin(angle)
		local along = dx * ux + dz * uz
		local across = math.abs(-dx * uz + dz * ux)
		return along >= -BigBadVacuum.BODY_RADIUS and along <= (zone.L or 0) and across <= (zone.W or 0)
	end
	return false
end

-- Throwing -----------------------------------------------------------------------------------------------

-- How long a brick thrown from `away` studs away is in the air.
function BigBadVacuum.Flight(away: number): number
	return 0.5 + math.clamp(away, 0, BigBadVacuum.THROW_RANGE) / 110
end

-- Where a lobbed brick is `alpha` (0..1) of the way from (ax, ay, az) to (bx, by, bz): a high arc,
-- higher for longer throws.
function BigBadVacuum.Arc(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	alpha: number
): (number, number, number)
	local t = math.clamp(alpha, 0, 1)
	local dx, dy, dz = bx - ax, by - ay, bz - az
	local height = 5 + math.sqrt(dx * dx + dy * dy + dz * dz) * 0.2
	return ax + dx * t, ay + dy * t + 4 * height * t * (1 - t), az + dz * t
end

return BigBadVacuum

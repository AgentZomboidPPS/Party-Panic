-- Hot Potato's shared rules: how big the backyard is, how close a tag and a throw reach, how long
-- a fuse burns and the arc a thrown potato flies along. The server judges tags and throws with these
-- numbers and the client half picks targets and draws the potatoes with the very same ones, so a pass
-- that looks like it reached on a player's screen is one the server counts (owner: "the precision
-- games will feel super bad if we dont").

local HotPotato = {}

-- A tag reaches this far, root to root, flat: two bodies touching, and a little more (they're about 2
-- apart shoulder to shoulder; it was 4.6, and people were tagged across a 2-3 stud gap: owner, "clean
-- up all hit boxes"). The server judges where the tagger's screen had the target, so the half stud
-- over CLIENT_TAG covers what's still on its way.
HotPotato.TAG_REACH = 3.5
-- The client only tags people this close, so a tag it shows never comes back refused.
HotPotato.CLIENT_TAG = 3
-- ...and at most this far apart in height: two 5-tall bodies overlapping (someone jumping clear over
-- the holder isn't tagged; throws reach up to REACH_UP).
HotPotato.TAG_UP = 4.5
-- THROW lobs the potato to the nearest empty-handed player in front within this range (aim-assist)...
HotPotato.CLIENT_THROW = 12
-- ... and the server takes throws up to this far (people keep moving while the press travels).
HotPotato.THROW_REACH = 13.5
-- "In front": the cosine of the widest angle from where the thrower faces.
HotPotato.FACING = 0.1
HotPotato.FLIGHT = 0.4 -- seconds a thrown potato is in the air
HotPotato.NO_BACK = 2 -- a potato can't go straight back to whoever passed it for this long
HotPotato.LOCK = 0.5 -- a fresh holder can't pass it on for this long (no instant ping-pong)
HotPotato.WARN = 3 -- the last seconds of a fuse: the potato glows, sizzles and beeps faster
HotPotato.SPEED = 1.1 -- holders run this much faster than everyone else, so tags are possible
HotPotato.PLAYERS_PER_POTATO = 4 -- one potato per this many players still in (at least 1)

-- The lawn's radius (studs, to the fence's inside) for `count` players.
function HotPotato.RadiusFor(count: number): number
	return math.clamp(18 + 1.4 * count, 21, 34)
end

-- How many potatoes are in play while `alive` players are still in.
function HotPotato.PotatoesFor(alive: number): number
	if alive < 2 then
		return 0
	end
	return math.max(1, math.floor(alive / HotPotato.PLAYERS_PER_POTATO))
end

-- A fresh fuse (seconds) from a 0..1 roll: 8-14 s, shorter as fewer players remain.
function HotPotato.FuseFor(roll: number, alive: number, started: number): number
	local share = math.clamp(alive / math.max(started, 1), 0, 1)
	return (8 + 6 * math.clamp(roll, 0, 1)) * (0.7 + 0.3 * share)
end

-- Where a thrown potato is `alpha` (0..1) of the way from `a` to `b`: a lob whose height grows with
-- the distance.
function HotPotato.Arc(a: Vector3, b: Vector3, alpha: number): Vector3
	local t = math.clamp(alpha, 0, 1)
	local height = 3 + (b - a).Magnitude * 0.25
	return a:Lerp(b, t) + Vector3.new(0, 4 * height * t * (1 - t), 0)
end

-- Whether `to` is in front of someone at `from` looking along `look` (flat).
function HotPotato.InFront(from: Vector3, look: Vector3, to: Vector3): boolean
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local facing = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.5 then
		return true
	end
	if facing.Magnitude < 1e-3 then
		return false
	end
	return flat.Unit:Dot(facing.Unit) >= HotPotato.FACING
end

-- How far apart in height two roots may be for a pass: someone up on the grill (out of a jump's reach
-- from the lawn, but not from a picnic table; its foil potatoes top out 10 studs up) can still be
-- tagged from beside it or thrown to.
HotPotato.REACH_UP = 11

-- Whether b is within `reach` of a (flat) and at most `up` apart in height (REACH_UP: a throw's).
function HotPotato.Reaches(a: Vector3, b: Vector3, reach: number, up: number?): boolean
	local dx, dz = a.X - b.X, a.Z - b.Z
	return dx * dx + dz * dz <= reach * reach and math.abs(a.Y - b.Y) <= (up or HotPotato.REACH_UP)
end

return HotPotato

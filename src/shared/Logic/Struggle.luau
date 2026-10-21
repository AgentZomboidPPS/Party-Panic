-- Struggle's shared rules: the numbers and the hit test the server judges with and the client draws
-- with, so a swing's reach on screen is the reach that counts (owner: "the precision games will feel
-- super bad if we dont"). See src/server/MiniGames/Struggle.luau for how the mode works.

local Struggle = {}

Struggle.START_ORBS = 20 -- orbs each player starts with
Struggle.FIELD_X = 40 -- half the sandlot's width inside the fence (studs, from its middle)
Struggle.FIELD_Z = 28 -- half its depth (the fence stands 2 studs further out)
Struggle.ORB_MARGIN = 3 -- loose orbs land at least this far inside the fence

-- A swing: press to wind up, release to strike. A tap strikes WINDUP after the press; held for
-- CHARGE seconds it becomes a charged swing; the server lets it go by itself after MAX_HOLD.
Struggle.WINDUP = 0.28
Struggle.CHARGE = 0.75
Struggle.MAX_HOLD = 1.6
Struggle.RECOVER = 0.45 -- after a strike, before the next press
Struggle.RECOVER_CHARGED = 0.75
Struggle.SWEEP = 0.16 -- how long the bat takes through its arc (drawing only)

-- Reach: from the swinger's middle to the victim's middle, flat, plus the victim's body.
Struggle.RANGE = 6.4
Struggle.RANGE_CHARGED = 7.6
Struggle.BODY = 1.1 -- a character's half width
Struggle.ARC = math.rad(80) -- each side of where the swinger faces
Struggle.CLOSE = 2.6 -- this close, any direction counts (the bat passes right through)
Struggle.HEIGHT = 5 -- at most this far above or below

Struggle.KNOCK = 3 -- orbs a hit knocks loose
Struggle.KNOCK_CHARGED = 6
Struggle.SAFE = 1.4 -- seconds a victim can't be hit again
Struggle.PICK = 3.2 -- pick-up reach (root to orb, flat)
Struggle.FLIGHT = 0.7 -- seconds an orb flies before it lands and can be picked up

-- One colour and one shape per player slot (colour is never the only cue). Glyph is what the HUD
-- draws (built from frames when it's not one of the safe glyphs); Prop is the orb's mesh.
Struggle.SLOTS = {
	{ Name = "Ball", Glyph = "●", Prop = "StruggleOrbBall", Color = Color3.fromRGB(255, 80, 80) },
	{ Name = "Cube", Glyph = "■", Prop = "StruggleOrbCube", Color = Color3.fromRGB(70, 160, 255) },
	{ Name = "Pyramid", Glyph = "▲", Prop = "StruggleOrbPyramid", Color = Color3.fromRGB(255, 215, 50) },
	{ Name = "Diamond", Glyph = "◆", Prop = "StruggleOrbDiamond", Color = Color3.fromRGB(110, 230, 100) },
	{ Name = "Star", Glyph = "★", Prop = "StruggleOrbStar", Color = Color3.fromRGB(200, 120, 255) },
	{ Name = "Ring", Glyph = "O", Prop = "StruggleOrbRing", Color = Color3.fromRGB(255, 150, 50) },
	{ Name = "Plus", Glyph = "+", Prop = "StruggleOrbPlus", Color = Color3.fromRGB(80, 230, 225) },
	{ Name = "Cross", Glyph = "X", Prop = "StruggleOrbCross", Color = Color3.fromRGB(255, 120, 200) },
	{ Name = "Cone", Glyph = "▼", Prop = "StruggleOrbCone", Color = Color3.fromRGB(245, 245, 250) },
	{ Name = "Frame", Glyph = "#", Prop = "StruggleOrbFrame", Color = Color3.fromRGB(170, 120, 70) },
	{ Name = "Pill", Glyph = "=", Prop = "StruggleOrbPill", Color = Color3.fromRGB(40, 120, 110) },
	{ Name = "Kite", Glyph = "<>", Prop = "StruggleOrbKite", Color = Color3.fromRGB(230, 40, 150) },
}

-- Whether a swing from `from`, facing `look` (flat), reaches someone standing at `at`.
function Struggle.Reaches(from: Vector3, look: Vector3, at: Vector3, charged: boolean): boolean
	local offset = at - from
	if math.abs(offset.Y) > Struggle.HEIGHT then
		return false
	end
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	local reach = (if charged then Struggle.RANGE_CHARGED else Struggle.RANGE) + Struggle.BODY
	if distance > reach then
		return false
	end
	if distance <= Struggle.CLOSE then
		return true
	end
	local facing = Vector3.new(look.X, 0, look.Z)
	if facing.Magnitude < 1e-3 then
		return false
	end
	local cos = facing.Unit:Dot(flat / distance)
	-- The arc is widened by the victim's body at that distance.
	local widen = math.asin(math.clamp(Struggle.BODY / distance, 0, 1))
	return cos >= math.cos(math.min(Struggle.ARC + widen, math.pi))
end

-- Where an orb is at server time t: flying from (fx, fz) at t0 to (x, z), landing at t0 + FLIGHT.
-- Returns the flat offset from the field's middle and its height above the sand.
function Struggle.OrbAt(orb: { number }, t: number): (number, number, number)
	local x, z, fx, fz, t0 = orb[3], orb[4], orb[5], orb[6], orb[7]
	local k = math.clamp((t - t0) / Struggle.FLIGHT, 0, 1)
	local height = 4.5 * 4 * k * (1 - k)
	return fx + (x - fx) * k, fz + (z - fz) * k, height
end

return Struggle

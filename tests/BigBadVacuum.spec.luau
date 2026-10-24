-- Pins Big Bad Vacuum's shared rules (Shared/Logic/BigBadVacuum): sizes scale sanely, every phase's
-- attack menu is fair (never the same twice, a Charge so the core opens), and the geometry the server
-- judges hits with, the bots read and the client draws agrees with itself.
local TestKit = require("./TestKit")
local Rules = require("../src/shared/Logic/BigBadVacuum")

local test, expectTrue, expectEqual = TestKit.test, TestKit.expectTrue, TestKit.expectEqual

local function near(a: number, b: number, tolerance: number): boolean
	return math.abs(a - b) <= tolerance
end

test("arena, health, piles and bag scale with the number of players and stay in range", function()
	expectEqual(Rules.RadiusFor(1), 52)
	expectEqual(Rules.RadiusFor(8), 58)
	expectEqual(Rules.RadiusFor(12), 64)
	expectEqual(Rules.RadiusFor(40), 66)
	expectTrue(Rules.HealthFor(12) > Rules.HealthFor(8) and Rules.HealthFor(8) > Rules.HealthFor(2), "health grows")
	expectEqual(Rules.HealthFor(99), Rules.HealthFor(12))
	expectEqual(Rules.PilesFor(1), 4)
	expectEqual(Rules.PilesFor(8), 6)
	expectEqual(Rules.PilesFor(12), 8)
	expectEqual(Rules.PilesFor(99), 8)
	expectEqual(Rules.BagCapacity(1), 2)
	expectEqual(Rules.BagCapacity(8), 4)
	expectEqual(Rules.BagCapacity(12), 5)
	expectEqual(Rules.BagCapacity(99), 5)
end)

test("phases change at their health fractions", function()
	expectEqual(Rules.PhaseFor(1), 1)
	expectEqual(Rules.PhaseFor(0.69), 1)
	expectEqual(Rules.PhaseFor(0.68), 2)
	expectEqual(Rules.PhaseFor(0.35), 2)
	expectEqual(Rules.PhaseFor(0.34), 3)
	expectEqual(Rules.PhaseFor(0), 3)
end)

test("the next attack is never the same twice, and phase 1 only uses its own attacks", function()
	local seen = {}
	for phase = 1, 3 do
		for last in { Sweep = true, Charge = true, Suction = true, Cord = true, Bombs = true, Whirl = true } do
			for step = 0, 99 do
				local pick = Rules.NextAttack(phase, last, 0, step / 100)
				expectTrue(pick ~= last, `phase {phase} repeated {last}`)
				seen[phase] = seen[phase] or {}
				seen[phase][pick] = true
			end
		end
	end
	expectTrue(seen[1].Cord == nil and seen[1].Bombs == nil and seen[1].Whirl == nil, "phase 1 stays simple")
	expectTrue(seen[2].Cord == true and seen[2].Bombs == nil, "phase 2 adds the cord")
	expectTrue(seen[3].Bombs == true and seen[3].Whirl == true and seen[3].Cord == true, "phase 3 has everything")
end)

test("two attacks without an opening make the next one a Charge", function()
	expectEqual(Rules.NextAttack(1, "Sweep", 2, 0.5), "Charge")
	expectEqual(Rules.NextAttack(3, "Bombs", 3, 0.9), "Charge")
	expectTrue(Rules.NextAttack(1, "Charge", 5, 0.5) ~= "Charge", "never twice in a row, pity or not")
	local opens = 0
	for phase = 1, 3 do
		for step = 0, 99 do
			if Rules.Stuns[Rules.NextAttack(phase, nil, 0, step / 100)] then
				opens += 1
			end
		end
	end
	expectTrue(opens > 60, "most attack rolls open the core (or are one of the first two)")
end)

test("the core stays open longer after a crash than after an overheat, and shrinks with the phase", function()
	expectEqual(Rules.StunFor("Sweep", 1), 0)
	expectEqual(Rules.StunFor("Nonsense", 1), 0)
	expectTrue(Rules.StunFor("Charge", 1) > Rules.StunFor("Suction", 1), "a crash is the long opening")
	expectTrue(Rules.StunFor("Charge", 1) > Rules.StunFor("Charge", 3), "later phases give less time")
	expectTrue(Rules.StunFor("Whirl", 3) > 0, "dizzy")
	expectEqual(Rules.StunFor("Charge", 9), Rules.StunFor("Charge", 3))
end)

test("warnings get quicker in later phases but never too quick to read", function()
	for kind in { Sweep = true, Whirl = true, Charge = true, Suction = true, Cord = true, Bombs = true } do
		expectTrue(Rules.WindFor(kind, 1) >= Rules.WindFor(kind, 2), `{kind}: phase 2 is no slower`)
		expectTrue(Rules.WindFor(kind, 2) >= Rules.WindFor(kind, 3), `{kind}: phase 3 is no slower`)
		expectTrue(Rules.WindFor(kind, 3) >= 0.7, `{kind}: still readable`)
	end
	expectEqual(Rules.WindFor("Nonsense", 2), 1)
	expectTrue(Rules.Think(1) > Rules.Think(2) and Rules.Think(2) > Rules.Think(3), "it thinks less and less")
end)

test("angles wrap and turn the short way", function()
	expectTrue(near(Rules.Wrap(-0.5), math.pi * 2 - 0.5, 1e-9), "wrap")
	expectTrue(near(Rules.Turn(0.1, -0.1), -0.2, 1e-9), "turn left")
	expectTrue(near(Rules.Turn(math.pi - 0.1, -math.pi + 0.1), 0.2, 1e-9), "across the seam")
	expectTrue(near(Rules.AngleOf(0, 1), math.pi / 2, 1e-9), "atan2(z, x)")
	local dx, dz = Rules.Dir(math.pi / 2)
	expectTrue(near(dx, 0, 1e-9) and near(dz, 1, 1e-9), "dir")
end)

test("a cone holds what is in front of it within reach and nothing else", function()
	local arc = math.rad(100)
	expectTrue(Rules.InCone(0, 0, 0, arc, 40, 20, 0), "dead ahead")
	expectTrue(Rules.InCone(0, 0, 0, arc, 40, 20, 20), "45 degrees off is inside 100")
	expectTrue(not Rules.InCone(0, 0, 0, arc, 40, 10, 30), "72 degrees off is outside")
	expectTrue(not Rules.InCone(0, 0, 0, arc, 40, -20, 0), "behind")
	expectTrue(not Rules.InCone(0, 0, 0, arc, 40, 50, 0), "too far")
end)

test("the Sweep's arm hits a player in its band as it passes, not before and not outside", function()
	local facing = 0
	-- Straight ahead, between the body and the reach. The arm starts at -75 degrees and ends at +75: it
	-- is over "straight ahead" half way through.
	expectTrue(not Rules.SweepHits(0, 0, facing, 0, 0.3, 20, 0), "not yet")
	expectTrue(Rules.SweepHits(0, 0, facing, 0.4, 0.6, 20, 0), "passing")
	expectTrue(not Rules.SweepHits(0, 0, facing, 0.7, 1, 20, 0), "already past")
	expectTrue(not Rules.SweepHits(0, 0, facing, 0, 1, 5, 0), "inside the body")
	expectTrue(not Rules.SweepHits(0, 0, facing, 0, 1, 35, 0), "beyond the reach")
	expectTrue(not Rules.SweepHits(0, 0, facing, 0, 1, -20, 0), "behind the boss")
	-- A whole swing covers everything in the sector, whichever way the boss faces.
	local facingAway = math.pi / 3
	local dx, dz = Rules.Dir(facingAway)
	expectTrue(Rules.SweepHits(0, 0, facingAway, 0, 1, dx * 22, dz * 22), "a whole swing")
end)

test("the Whirl covers every bearing over a full turn and a slice of them in a moment", function()
	expectTrue(Rules.WhirlHits(0, 0, 0, 0, 1, 0, 22), "the whole spin")
	expectTrue(not Rules.WhirlHits(0, 0, 0, 0, 0.02, 0, 22), "a moment at the start")
	expectTrue(not Rules.WhirlHits(0, 0, 0, 0, 1, 0, 30), "outside the reach")
	expectTrue(not Rules.WhirlHits(0, 0, 0, 0, 1, 0, 4), "under the body")
end)

test("a charge stops at the wall, wherever it starts", function()
	local cx, cz = 100, -40
	local radius = 60
	local limit = radius - Rules.BODY_RADIUS - 0.6
	for angle = 0, 7 do
		local dx, dz = Rules.Dir(angle)
		local x, z = Rules.ChargeEnd(cx, cz, cx, cz, dx, dz, radius)
		expectTrue(near(Rules.Distance(x, z, cx, cz), limit, 1e-6), "from the middle it goes to the limit")
	end
	-- From off-centre, along the diameter, it goes to the far side.
	local x = Rules.ChargeEnd(cx, cz, cx - 20, cz, 1, 0, radius)
	expectTrue(near(x, cx + limit, 1e-6), "to the far limit")
	-- Already at the wall and charging into it: it doesn't move.
	local stillX = Rules.ChargeEnd(cx, cz, cx + limit, cz, 1, 0, radius)
	expectTrue(near(stillX, cx + limit, 1e-6), "nowhere to go")
end)

test("the suction pulls harder the closer you are", function()
	expectTrue(Rules.PullSpeed(5) > Rules.PullSpeed(30), "stronger near the mouth")
	expectTrue(Rules.PullSpeed(5) > 16, "a walking player can't outrun it at the mouth")
	expectTrue(Rules.PullSpeed(48) < 14, "at the edge it is a tug a walking player (16) beats")
	expectTrue(Rules.PullSpeed(500) >= 8, "never nothing")
	local mx, mz = Rules.MouthAt(10, 20, 0)
	expectTrue(near(mx, 10 + Rules.BODY_RADIUS + 1.5, 1e-9) and near(mz, 20, 1e-9), "the mouth is in front")
end)

test("the shockwave ring hits grounded players as its band passes and skips jumpers", function()
	-- The band reaches 15 studs after 15 / 26 seconds.
	local arrive = 15 / Rules.RING_SPEED
	expectTrue(not Rules.RingHits(0, 0, 0, arrive - 0.1, 15, 0, 0), "not there yet")
	expectTrue(Rules.RingHits(0, 0, arrive - 0.05, arrive + 0.05, 15, 0, 0), "passing over")
	expectTrue(not Rules.RingHits(0, 0, arrive - 0.05, arrive + 0.05, 15, 0, 3.5), "a jumper is over it")
	expectTrue(not Rules.RingHits(0, 0, arrive + 0.5, arrive + 0.6, 15, 0, 0), "long gone")
	expectTrue(not Rules.RingHits(0, 0, 3, 3.1, 80, 0, 0), "the ring stops growing")
	expectTrue(near(Rules.RingRadius(1), Rules.RING_SPEED, 1e-9), "radius")
	expectEqual(Rules.RingRadius(-1), 0)
end)

test("every kind of zone says what is inside it", function()
	local sector = { K = "Sector", X = 0, Z = 0, A = 0, Arc = math.rad(150), R = 28, T0 = 0, T1 = 1, T2 = 2 }
	expectTrue(Rules.ZoneContains(sector, 20, 5), "sector")
	expectTrue(not Rules.ZoneContains(sector, -20, 5), "behind a sector")
	local disc = { K = "Disc", X = 50, Z = 50, R = 8, T0 = 0, T1 = 1, T2 = 2 }
	expectTrue(Rules.ZoneContains(disc, 54, 54), "disc")
	expectTrue(not Rules.ZoneContains(disc, 60, 60), "outside a disc")
	local lane = { K = "Lane", X = 0, Z = 0, A = math.pi / 2, L = 80, W = 14.5, T0 = 0, T1 = 1, T2 = 2 }
	expectTrue(Rules.ZoneContains(lane, 10, 40), "lane")
	expectTrue(not Rules.ZoneContains(lane, 20, 40), "beside a lane")
	expectTrue(not Rules.ZoneContains(lane, 0, 90), "past a lane's end")
	expectTrue(not Rules.ZoneContains(lane, 0, -30), "behind a lane")
	local whirl = { K = "Whirl", X = 0, Z = 0, R = 28, T0 = 0, T1 = 1, T2 = 2 }
	expectTrue(Rules.ZoneContains(whirl, 20, 0), "whirl band")
	expectTrue(not Rules.ZoneContains(whirl, 40, 0), "outside the whirl")
	expectTrue(not Rules.ZoneContains({ K = "Nope", X = 0, Z = 0, R = 1, T0 = 0, T1 = 0, T2 = 0 }, 0, 0), "unknown")
end)

test("a thrown brick takes longer from farther away and lands where it was thrown", function()
	expectTrue(Rules.Flight(60) > Rules.Flight(10), "farther is slower")
	expectTrue(Rules.Flight(0) >= 0.5, "never instant")
	expectEqual(Rules.Flight(1e6), Rules.Flight(Rules.THROW_RANGE))
	local x0, y0, z0 = Rules.Arc(0, 3, 0, 30, 12, 40, 0)
	expectTrue(near(x0, 0, 1e-9) and near(y0, 3, 1e-9) and near(z0, 0, 1e-9), "starts at the thrower")
	local x1, y1, z1 = Rules.Arc(0, 3, 0, 30, 12, 40, 1)
	expectTrue(near(x1, 30, 1e-9) and near(y1, 12, 1e-9) and near(z1, 40, 1e-9), "ends on the target")
	local _, ym = Rules.Arc(0, 3, 0, 30, 12, 40, 0.5)
	expectTrue(ym > 7.5 + 5, "lobbed")
end)

test("volleys hit harder up to x1.6, and scores add up", function()
	expectEqual(Rules.Volley(1), 1)
	expectTrue(near(Rules.Volley(3), 1.4, 1e-9), "three crits")
	expectTrue(near(Rules.Volley(4), 1.6, 1e-9), "four crits")
	expectTrue(near(Rules.Volley(50), 1.6, 1e-9), "capped")
	expectEqual(Rules.Volley(0), 1)
	expectEqual(Rules.Score(95.4, 2, 15), 95 + 16 + 15)
	expectEqual(Rules.Score(0, 0, 0), 0)
end)

test("a lobby that plays well can win: the health is within reach of the damage on offer", function()
	-- About 16 s of open core in a fight, a brick per player every ~1.6 s, a crit being CRIT and a volley
	-- (crits close together) hitting about half as hard again.
	-- A small squad gets a smaller share of it (each of them is attacked more often, so throws less:
	-- measured with bots on test servers).
	local previous = 0
	for players = 1, 12 do
		local potential = players * (16 / 1.6) * Rules.CRIT * 1.5
		local health = Rules.HealthFor(players)
		expectTrue(health < potential, `{players} players: health {health}`)
		expectTrue(health > potential * (if players >= 4 then 0.4 else 0.25), `{players} players: not a pushover`)
		expectTrue(health > previous, "more players, more health")
		previous = health
	end
end)

return nil

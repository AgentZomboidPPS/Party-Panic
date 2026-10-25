-- Bumper Ballers (Knockback, 60s, 1 to 12 players). After "Bumper Balls" from the first Mario
-- Party (the owner's favourite): everyone rides on top of a big ball on a round island in the sea
-- and bumps everyone else off. Fall in the water and you're out; last one rolling wins. In the last
-- 15 seconds bumps get bigger (BIG BUMPS!) so a round never fizzles out.
--
-- How it works:
--   * Each ball is an unanchored sphere (Body) with a patterned mesh welded on (it rolls for real).
--     The rider stands on top: a BallSocket joins the rider's root to the ball's center and an
--     AlignOrientation keeps them upright, so the ball spins freely under their feet.
--   * A player's ball belongs to their device (ctx:GiveOwnership): their client pushes it with a
--     VectorForce from the move input (keyboard, thumbstick, gamepad, or phone tilt if they turn it
--     on), so steering is smooth. Bots' balls belong to the server, which pushes them the same way:
--     both sides run Logic/BumperDrive with the numbers the server shares (MG_Tuning).
--   * Bumps are decided here, by distance and closing speed: when two balls meet, each is pushed
--     apart by an amount that grows with the OTHER ball's speed into it, so the faster ball wins.
--     Balls don't collide with each other physically (collision group BumperBall), because each
--     device sees the other balls a round trip late: the server is the only judge of a bump.
--     A player's push is sent to their client (MiniGameEvent "Bump") and checked a moment later
--     (if it didn't happen, the server takes the ball back and pushes it itself); a bot's is applied
--     directly. Players and bots bump each other both ways under the same rules.
--     A bump counts when the balls touch (shells within 0.5 studs, the same rule the client boings
--     at) on the screen of a player riding one of them: there the other ball is drawn a round trip
--     plus about 0.1 s late, so the server looks that far back in its track, and a round trip ahead
--     (when the push gets back to them). It used to judge the server's own view with up to 3 studs
--     of leeway, so a rider crossing in front of you that you visibly hit could slip by, and a fast
--     side-swipe 3 studs clear could knock you flying. Two bots are judged as the server sees them.
--     Owner: "We need to fine tune some of the hitboxes. the precision games will feel super bad if
--     we dont."
--   * Ring-outs are position checks: a ball whose center drops below the water line is out. The ball
--     rolls off where the sand lip visibly ends (44.6 studs out, an invisible collider), not at the
--     grass's edge (44), so a ball visibly still on the sand doesn't drop. When the last two go in
--     within 0.3 s of each other (too close to call: each screen draws the other ball late), it's a
--     draw.
--   * Luau test servers have no physics, so there the server moves every ball itself with the same
--     drive model (see :_simulate), which is also how the round harness tests bots and bumps.
--
-- Controls pass (owner, playing on a phone: "Bumper balls control scheme is really bad on
-- mobile"): the drive is now Logic/BumperDrive. Steering answers the stick quickly (90% of full
-- speed in 0.37 s instead of 1.2, half a ball of glide after letting go instead of 12 studs, a
-- corner in a third of a second instead of one), while what a bump gives a ball fades exactly as it
-- always did, so bumps slide riders as far as before; a ball tipping over the rim or in the air
-- steers the old, weak way, so the edge is as unforgiving as ever. Bots roll with the same drive
-- (their brains are unchanged). A player's ball the server has taken back (see :_takeBack) now
-- slows as if its stick were let go, instead of coasting on frictionless for a second. The phone
-- side of the fix (a steady camera, tilt off by default) is in the client half.
--
-- Bug sweep (owner: "Let's do a full bug and clean sweep."): four riders' shapes (Yellow ★, Pink ✚,
-- Navy ☾, Black ◐) aren't in any of the game's fonts, so their tags over the ball and their icons in
-- the rider strip showed the same empty box: four riders with no shape to tell them apart by. They
-- are ♪, +, ◀ and ◉ now, all drawn by the fonts and still all different.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BumperDrive = require(ReplicatedStorage.Shared.Logic.BumperDrive)
local MiniGame = require(script.Parent.Kit.MiniGame)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local BumperBallers = MiniGame.Define("BumperBallers")

local BALL_SIZE = 8
local RADIUS = BALL_SIZE / 2
-- Where a ball rolls off: its center past the sand lip's visible edge (the sand around the 44-stud
-- grass top stays level out to 44.2-45.1 studs, 44.7 on average: assets/meshes/BumperIsland.glb).
local ISLAND_RADIUS = 44.6
local GRASS_RADIUS = 44 -- the green top drawn inside the sand ring
local WATER_DROP = 5 -- water surface below the island top
local OUT_DEPTH = 1.5 -- a ball is out once its center is this far under the water surface
local BIG_BUMPS_AT = 45 -- seconds into the round
local RIDER_GROUP = "BumperRider"

-- How a ball answers its stick (MaxSpeed 24 studs/s, steering, how bumps carry): Logic/BumperDrive,
-- shared with the clients as MG_Tuning.
local TUNING = BumperDrive.Tuning
-- A full-speed hit on a rider standing still slides them about 17 studs (about 5 if they steer
-- against it), 24 with BIG BUMPS, on an island 44 studs from middle to edge: a ring-out takes a hit
-- near the edge or a few in a row. (Owner, after playing: "you get bounced off way too quickly" -
-- it used to be 33 and 46 studs.)
-- Then (owner: "Bumper ball increase bounce by 25%") every bump got a quarter stronger: the push, its
-- cap and the little hop alike.
local BOUNCE = 1.25
local BUMP_BASE = 7 * BOUNCE -- studs/s a full-speed bump gives on top (less for a gentle touch)
local BUMP_GAIN = 0.85 * BOUNCE -- extra per stud/s of the other ball's speed into you
local BUMP_SELF = 0.2 * BOUNCE -- extra per stud/s of your own speed into them (you bounce back a bit)
local BUMP_MAX = 42 * BOUNCE
local BUMP_LIFT = 5 * BOUNCE
local BIG_BUMPS = 1.4
local CLOSING_MIN = 4 -- closing speed (studs/s) that counts as a bump
local TOUCH = BALL_SIZE + 0.5 -- centers this close: the balls touch (the client boings at the same)
local MAX_LEAD = 0.2 -- seconds at most a player's screen is looked ahead (their round trip)
local VIEW_LAG = 0.1 -- seconds a device draws other balls behind, on top of the network round trip
local TRACK_SECONDS = 0.8 -- how much of each ball's path is kept, for judging what a screen showed
local DRAW_WINDOW = 0.3 -- the last two going in this close together is a draw
local PAIR_COOLDOWN = 0.4
local HISTORY = 8 -- velocity samples kept (about 0.25 s): the bounce often happens before we see it
local GRAVITY = 110 -- simulated fall (no-physics servers only)
local MAX_LEGIT_SPEED = 110 -- studs/s: nothing in the game rolls a ball this fast
local SEPARATE_SPEED = 6 -- studs/s that pushes two slowly overlapping balls apart (no bump)
local BALL_GROUP = "BumperBall"
local FLOOR_GROUP = "BumperFloor" -- the hidden floor under the sea: everything lands on it
local FLOOR_DEPTH = 9 -- how far under the water surface it is
local ROLL_MASS = BumperDrive.RollMass -- a rolling ball needs 7/5 of the push to speed up (it spins up too)

-- The look (art pass, owner: "make it look really cool"): a sunny tropical party. Turquoise
-- shallows around the island, a ring of floats and buoys marking the edge, pool floats drifting in
-- the lagoon, a party islet with a tiki beach bar, palm islets and big jungle islands on the horizon.
local LAGOON_DEPTH = 15.2 -- the lagoon mesh's base under the water (its shelf is 4.5 under)
local PARTY_ANGLE = math.rad(-90) -- where the party islet sits around the island
local PARTY_SCALE = 2.4
local ISLET_PROFILE = { { 0, 3.25 }, { 2.4, 3.2 }, { 5, 2.9 }, { 7.6, 2.1 }, { 9.5, 0.9 }, { 10.5, 0 } }
-- A palm's trunk foot is off the model's pivot (its crown is the model's middle), by this much (x, z)
-- per unit of its scale, and flares out this far round: on an islet's slope that's what must stand on
-- the sand. Placed by its pivot, a palm on the party islet's edge stood up to 3 studs over the sand,
-- one of them over the water ("No clipping stuff like that.").
local PALM_FOOT = Vector2.new(-2.65, -1.05)
local PALM_FLARE = 1.15
local PALM_SINK = 0.55 -- (the islets' sand wobbles in and out round the slope: 0.3 left gaps there)
local PARASOL_COLORS = {
	Color3.fromRGB(255, 92, 126),
	Color3.fromRGB(70, 190, 255),
	Color3.fromRGB(255, 196, 50),
}
local FROSTING_COLORS = {
	Color3.fromRGB(255, 136, 204),
	Color3.fromRGB(120, 232, 196),
	Color3.fromRGB(255, 220, 90),
	Color3.fromRGB(150, 160, 255),
}
local FLOAT_KINDS = {
	{ Prop = "BumperFlamingo", Scale = 1.5, Sink = 0.6 },
	{ Prop = "BumperDonutFloat", Scale = 1.4, Sink = 0.55 },
	{ Prop = "BumperLifebuoy", Scale = 1.25, Sink = 0.3 },
	{ Prop = "BumperDonutFloat", Scale = 1.4, Sink = 0.55 },
}

-- Every rider gets a color, a pattern on the ball and a shape tag, so color is never the only cue.
-- All 12 shapes differ (and are ones the fonts have: ★ ✚ ☾ ◐ are drawn as an empty box), and riders
-- with similar colors (Red/Orange/Pink, Blue/Navy/Cyan, Green/Lime) never share a pattern.
BumperBallers.Riders = {
	{ Name = "Red", Color = Color3.fromRGB(240, 70, 70), Shape = "●", Pattern = "BumperBallGores" },
	{ Name = "Blue", Color = Color3.fromRGB(60, 135, 255), Shape = "■", Pattern = "BumperBallGores" },
	{ Name = "Green", Color = Color3.fromRGB(70, 200, 95), Shape = "▲", Pattern = "BumperBallGores" },
	{ Name = "Yellow", Color = Color3.fromRGB(255, 205, 45), Shape = "♪", Pattern = "BumperBallDots" },
	{ Name = "Purple", Color = Color3.fromRGB(160, 90, 255), Shape = "◆", Pattern = "BumperBallDots" },
	{ Name = "Orange", Color = Color3.fromRGB(255, 140, 40), Shape = "♥", Pattern = "BumperBallBands" },
	{ Name = "Pink", Color = Color3.fromRGB(255, 100, 190), Shape = "+", Pattern = "BumperBallDots" },
	{ Name = "Cyan", Color = Color3.fromRGB(40, 210, 230), Shape = "♣", Pattern = "BumperBallDots" },
	{ Name = "Lime", Color = Color3.fromRGB(165, 230, 60), Shape = "♠", Pattern = "BumperBallBands" },
	{ Name = "Navy", Color = Color3.fromRGB(50, 60, 170), Shape = "◀", Pattern = "BumperBallBands" },
	{ Name = "Brown", Color = Color3.fromRGB(150, 95, 60), Shape = "▼", Pattern = "BumperBallDots" },
	{ Name = "Black", Color = Color3.fromRGB(45, 45, 55), Shape = "◉", Pattern = "BumperBallGores" },
}
BumperBallers.Patterns = { "BumperBallGores", "BumperBallBands", "BumperBallDots" }

local physics = RunService:IsRunning()
local rng = Random.new()
local decor = Random.new(2610) -- the arena's dressing is laid out the same every round

export type Entry = {
	Player: any,
	Index: number,
	Model: Model,
	Body: Part,
	Center: Attachment,
	Force: VectorForce,
	Socket: BallSocketConstraint,
	Seat: Attachment?,
	Align: AlignOrientation?,
	Rider: Model?, -- the character seated on this ball (see :_attachRider)
	RiderGroups: { [BasePart]: string }?, -- its parts' collision groups from before it rode
	RiderOffset: number,
	ClientDriven: boolean,
	Input: Vector3,
	Drive: BumperDrive.Drive, -- rolls a bot's ball, or a player's the server has taken back (else their device does)
	Position: Vector3,
	Velocity: Vector3,
	History: { Vector3 },
	Track: { { T: number, P: Vector3, V: Vector3 } },
	ReliefUntil: number,
	Yaw: number,
	Spin: CFrame,
	Out: boolean,
	LastBumper: any,
	LastBumpAt: number,
	BeyondSince: number?,
	PolicedUntil: number?,
	ServerDriving: boolean?, -- a player's ball the server has taken back is pushed by the server
	FastSince: number?,
	HighSince: number?,
	HangSince: number?,
	PendingBump: { Dv: Vector3, Before: Vector3, At: number, Peak: number }?,
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The gap between two balls' centers where they come closest from `from` to `to` seconds after
-- now, moving apart at `relative` (a straight path: over a fraction of a second, steering bends it
-- by a third of a stud at most).
local function closestGap(gap: Vector3, relative: Vector3, from: number, to: number): Vector3
	local speed2 = relative:Dot(relative)
	local t = if speed2 > 1e-6 then math.clamp(-gap:Dot(relative) / speed2, from, to) else 0
	return gap + relative * t
end

-- Where a ball was at os.clock() time `t` (from its track, newest first), and how fast it went.
local function trackAt(entry, t: number): (Vector3, Vector3)
	local newer = nil
	for _, sample in entry.Track do
		if sample.T <= t then
			if not newer then
				return sample.P, sample.V
			end
			local f = (t - sample.T) / math.max(newer.T - sample.T, 1e-4)
			return sample.P:Lerp(newer.P, f), sample.V:Lerp(newer.V, f)
		end
		newer = sample
	end
	if newer then
		return newer.P, newer.V
	end
	return entry.Position, entry.Velocity
end

local function registerRiderGroup()
	local ok = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(RIDER_GROUP) then
			PhysicsService:RegisterCollisionGroup(RIDER_GROUP)
		end
		if not PhysicsService:IsCollisionGroupRegistered(BALL_GROUP) then
			PhysicsService:RegisterCollisionGroup(BALL_GROUP)
		end
		-- Riders touch nothing: the ball does the bumping, and legs never snag on the island.
		PhysicsService:CollisionGroupSetCollidable(RIDER_GROUP, "Default", false)
		PhysicsService:CollisionGroupSetCollidable(RIDER_GROUP, RIDER_GROUP, false)
		-- Balls roll on the island but pass through each other: the server decides every bump.
		PhysicsService:CollisionGroupSetCollidable(BALL_GROUP, "Default", true)
		PhysicsService:CollisionGroupSetCollidable(BALL_GROUP, BALL_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(BALL_GROUP, RIDER_GROUP, false)
		-- Nothing can fall out of the world: riders (who otherwise touch nothing) land on it too.
		if not PhysicsService:IsCollisionGroupRegistered(FLOOR_GROUP) then
			PhysicsService:RegisterCollisionGroup(FLOOR_GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(FLOOR_GROUP, RIDER_GROUP, true)
		PhysicsService:CollisionGroupSetCollidable(FLOOR_GROUP, BALL_GROUP, true)
		PhysicsService:CollisionGroupSetCollidable(FLOOR_GROUP, "Default", true)
	end)
	return ok
end

-- The height of the islet mesh's sand (unscaled) this far from its middle.
local function isletHeight(distance: number): number
	for index = 2, #ISLET_PROFILE do
		local a, b = ISLET_PROFILE[index - 1], ISLET_PROFILE[index]
		if distance <= b[1] then
			return a[2] + (b[2] - a[2]) * (distance - a[1]) / (b[1] - a[1])
		end
	end
	return 0
end

-- A palm (of `scale`, turned `yaw`) at (x, z) studs from an islet's middle, in its frame, on the sand
-- under its trunk's foot: judged at the downhill edge of the flare, sunk PALM_SINK.
local function palmOn(islet: CFrame, isletScale: number, x: number, z: number, scale: number, yaw: number): CFrame
	local c, s = math.cos(yaw), math.sin(yaw)
	local fx, fz = PALM_FOOT.X * scale, PALM_FOOT.Y * scale
	local foot = Vector2.new(x + fx * c + fz * s, z - fx * s + fz * c)
	local ground = isletHeight((foot.Magnitude + PALM_FLARE * scale) / isletScale) * isletScale
	return islet * CFrame.new(x, ground - PALM_SINK, z) * CFrame.Angles(0, yaw, 0)
end

-- The turn that puts a palm's trunk foot on the islet's side of (x, z), its crown leaning out to sea.
local function leanOut(x: number, z: number): number
	return math.atan2(z, -x) - math.atan2(-PALM_FOOT.Y, PALM_FOOT.X)
end

-- Arena -------------------------------------------------------------------------------------------

function BumperBallers:_buildArena()
	local ctx = self.context
	local top = self.top
	local center = self.center
	local waterY = self.waterY

	-- The island top: a real grass cylinder the balls roll on (Roblox cylinders run along X), and
	-- an invisible one as high that carries them out to where the sand lip visibly ends, so a ball
	-- rolls off where it's seen to.
	for _, part in
		{
			{ Name = "IslandTop", Radius = GRASS_RADIUS, Transparency = 0 },
			{ Name = "IslandEdge", Radius = ISLAND_RADIUS, Transparency = 1 },
		}
	do
		Build.Part({
			Name = part.Name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(5.5, part.Radius * 2, part.Radius * 2),
			CFrame = CFrame.new(center.X, top - 2.75, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(96, 190, 80),
			Material = Enum.Material.Grass,
			Transparency = part.Transparency,
			CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.6, 0.4, 1, 1),
			CanQuery = false,
			CanTouch = false,
			Parent = ctx.Arena,
		})
	end
	-- Sand beach ring, striped warning lip, cliffs, foam and rocks (one mesh, no collisions).
	MeshLibrary.Get("BumperIsland", {
		CFrame = CFrame.new(center.X, top - self.islandHeight + self.islandAbove, center.Z),
		Parent = ctx.Arena,
	})

	-- Tropical sea: glassy turquoise water over a sea floor that goes from a pale sand shelf by the
	-- island to a turquoise reef slope and deep blue, so the drop off the island reads at a glance.
	Build.Decor({
		Name = "Sea",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 2048, 2048),
		CFrame = CFrame.new(center.X, waterY - 0.5, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(40, 175, 205),
		Material = Enum.Material.Glass,
		Transparency = 0.28,
		Reflectance = 0.08,
		Parent = ctx.Arena,
	})
	MeshLibrary.Get("BumperLagoon", {
		CFrame = CFrame.new(center.X, waterY - LAGOON_DEPTH, center.Z),
		Parent = ctx.Arena,
	})
	-- A hidden floor under the water, so whoever goes in (or comes off their ball) lands on it and
	-- is counted out, instead of falling out of the world (owner: "I fell out of the world").
	local floor = Build.Part({
		Name = "SafetyFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 2048, 2048),
		CFrame = CFrame.new(center.X, waterY - FLOOR_DEPTH - 1, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Transparency = 1,
		CanQuery = false,
		CanTouch = false,
		Parent = ctx.Arena,
	})
	if self.groupReady then
		floor.CollisionGroup = FLOOR_GROUP
	end
	-- The deep sea floor out to the horizon (a little under the lagoon mesh's rim).
	Build.Decor({
		Name = "SeaBed",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 2048, 2048),
		CFrame = CFrame.new(center.X, waterY - LAGOON_DEPTH - 1.8, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(22, 106, 168),
		Material = Enum.Material.Sand,
		Parent = ctx.Arena,
	})

	-- The arena's edge from afar: a ring of red and white floats, channel buoys just outside it.
	MeshLibrary.Get("BumperFloatLine", {
		CFrame = CFrame.new(center.X, waterY - 0.43, center.Z),
		Parent = ctx.Arena,
	})
	local floats = Build.Folder("Floats", ctx.Arena) -- buoys and pool floats bob on the client
	local taken: { { Spot: Vector3, Radius: number } } = {}
	local function free(spot: Vector3, radius: number): boolean
		for _, other in taken do
			if (other.Spot - spot).Magnitude < other.Radius + radius then
				return false
			end
		end
		return true
	end
	local function around(angle: number, distance: number): Vector3
		return center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	end
	for index = 0, 7 do
		local spot = around((index + 0.5) / 8 * math.pi * 2, 80)
		MeshLibrary.Get("BumperBuoy", {
			CFrame = CFrame.new(spot.X, waterY - 1.4, spot.Z),
			Parent = floats,
		})
		table.insert(taken, { Spot = spot, Radius = 4 })
	end

	-- The party islet: a beach bar under a thatched roof facing the island, tiki torches and
	-- totems, parasols on the beach and palms behind.
	local partySpot = around(PARTY_ANGLE, 112)
	local partyBase = waterY - 4
	local party =
		CFrame.lookAt(Vector3.new(partySpot.X, partyBase, partySpot.Z), Vector3.new(center.X, partyBase, center.Z))
	MeshLibrary.Get("BumperIslet", {
		Scale = PARTY_SCALE,
		-- Scaled up, the islet's rocks would read as grey slabs: tint them as sandy dune stones.
		Colors = { Rock = Color3.fromRGB(214, 196, 150) },
		CFrame = party,
		Parent = ctx.Arena,
	})
	table.insert(taken, { Spot = partySpot, Radius = 27 })
	local function onParty(x: number, z: number): CFrame
		-- A spot on the party islet's sand (x right, -z toward the island), a little sunk in.
		return party * CFrame.new(x, isletHeight(Vector2.new(x, z).Magnitude / PARTY_SCALE) * PARTY_SCALE - 0.3, z)
	end
	MeshLibrary.Get("BumperTikiBar", {
		Scale = 1.25,
		CFrame = party * CFrame.new(0, 7, 2),
		Parent = ctx.Arena,
	})
	for _, spot in { Vector2.new(-10.5, -7), Vector2.new(10.5, -7), Vector2.new(-12.5, 4), Vector2.new(12.5, 4) } do
		MeshLibrary.Get("BumperTikiTorch", { CFrame = onParty(spot.X, spot.Y), Parent = ctx.Arena })
	end
	for _, x in { -6.5, 6.5 } do
		MeshLibrary.Get("BumperTikiTotem", { Scale = 1.15, CFrame = onParty(x, -12.5), Parent = ctx.Arena })
	end
	-- (Z: sunk that much more: the sand dips under the first, which stood 0.6 over it.)
	for index, spot in { Vector3.new(-16, -8, 0.8), Vector3.new(15.5, -10, 0) } do
		MeshLibrary.Get("BumperParasol", {
			Colors = if index == 2 then { CanopyA = Color3.fromRGB(70, 190, 255) } else nil,
			CFrame = onParty(spot.X, spot.Y) * CFrame.new(0, -spot.Z, 0) * CFrame.Angles(0, index * 2.1, 0),
			Parent = ctx.Arena,
		})
	end
	-- Palms lean out to sea (their feet on the high sand inside their spots), on the sand under their feet.
	for index, spot in { Vector2.new(-15, 10), Vector2.new(13, 13), Vector2.new(1, 19), Vector2.new(19, -1) } do
		local scale = 1.15 + index * 0.08
		MeshLibrary.Get("BumperPalm", {
			Scale = scale,
			CFrame = palmOn(party, PARTY_SCALE, spot.X, spot.Y, scale, leanOut(spot.X, spot.Y)),
			Parent = ctx.Arena,
		})
	end

	-- Little palm islets around the arena, some with a parasol or a tiki totem.
	local islets = 7
	for index = 1, islets - 1 do
		local angle = PARTY_ANGLE + (index + decor:NextNumber(-0.2, 0.2)) / islets * math.pi * 2
		local distance = decor:NextNumber(96, 150)
		local scale = decor:NextNumber(0.9, 1.5)
		local spot = around(angle, distance)
		local islet = CFrame.new(spot.X, waterY - 1.2, spot.Z) * CFrame.Angles(0, decor:NextNumber(0, math.pi * 2), 0)
		MeshLibrary.Get("BumperIslet", { Scale = scale, CFrame = islet, Parent = ctx.Arena })
		table.insert(taken, { Spot = spot, Radius = 11 * scale })
		-- (`foot`: judged that many studs downhill, where a wide base's edge is: a totem's stood 0.2
		-- over the sand there)
		local function onIslet(x: number, z: number, foot: number?): CFrame
			local ground = isletHeight(Vector2.new(x, z).Magnitude + (foot or 0) / scale) * scale
			return islet * CFrame.new(x * scale, ground - 0.3, z * scale)
		end
		local palms = decor:NextInteger(1, 2)
		for palm = 1, palms do
			-- (the decor draws in the order they always had: the layout stays the same)
			local palmScale = decor:NextNumber(0.85, 1.25) * (if palm == 1 then 1 else 0.8)
			local x, z = decor:NextNumber(-3, 3), decor:NextNumber(-3, 3)
			local yaw = decor:NextNumber(0, math.pi * 2)
			MeshLibrary.Get("BumperPalm", {
				Scale = palmScale,
				CFrame = palmOn(islet, scale, x * scale, z * scale, palmScale, yaw),
				Parent = ctx.Arena,
			})
		end
		if index % 2 == 1 then
			MeshLibrary.Get("BumperParasol", {
				Colors = { CanopyA = PARASOL_COLORS[(index // 2) % #PARASOL_COLORS + 1] },
				CFrame = onIslet(5, 1) * CFrame.Angles(0, decor:NextNumber(0, math.pi * 2), 0),
				Parent = ctx.Arena,
			})
		elseif index == 2 or index == 6 then
			local totemSpot = onIslet(-4, 2, 1.4).Position
			MeshLibrary.Get("BumperTikiTotem", {
				CFrame = CFrame.lookAt(totemSpot, Vector3.new(center.X, totemSpot.Y, center.Z)),
				Parent = ctx.Arena,
			})
		end
	end

	-- Pool floats drifting in the lagoon between the buoys and the islets.
	local placed = 0
	for _ = 1, 80 do
		if placed >= 14 then
			break
		end
		local spot = around(decor:NextNumber(0, math.pi * 2), decor:NextNumber(76, 128))
		if not free(spot, 5) then
			continue
		end
		local kind = FLOAT_KINDS[placed % #FLOAT_KINDS + 1]
		MeshLibrary.Get(kind.Prop, {
			Scale = kind.Scale,
			Colors = if kind.Prop == "BumperDonutFloat"
				then { Frosting = FROSTING_COLORS[placed % #FROSTING_COLORS + 1] }
				else nil,
			CFrame = CFrame.new(spot.X, waterY - kind.Sink * kind.Scale, spot.Z)
				* CFrame.Angles(0, decor:NextNumber(0, math.pi * 2), 0),
			Parent = floats,
		})
		table.insert(taken, { Spot = spot, Radius = 4 })
		placed += 1
	end

	-- Rocks in the surf at the foot of the cliff.
	for index = 0, 9 do
		local angle = decor:NextNumber(0, math.pi * 2)
		local distance = decor:NextNumber(62, 84)
		MeshLibrary.Get("Boulder", {
			Scale = decor:NextNumber(0.5, 1.1),
			Colors = { Rock = Color3.fromRGB(125, 118, 112) },
			CFrame = CFrame.new(
				center.X + math.cos(angle) * distance,
				waterY - 2.5,
				center.Z + math.sin(angle) * distance
			) * CFrame.Angles(0, index * 1.7, 0),
			Parent = ctx.Arena,
		})
	end

	-- Big jungle islands on the horizon close off the view, with gaps of open sea between them.
	local far = 7
	for index = 0, far - 1 do
		local angle = PARTY_ANGLE + (index + 0.5 + decor:NextNumber(-0.18, 0.18)) / far * math.pi * 2
		local distance = decor:NextNumber(500, 680)
		local scale = decor:NextNumber(1.0, 1.5)
		local spot = around(angle, distance)
		MeshLibrary.Get(if index % 2 == 0 then "BumperFarIslandA" else "BumperFarIslandB", {
			Scale = scale,
			CFrame = CFrame.new(spot.X, waterY - 6 * scale, spot.Z)
				* CFrame.Angles(0, -angle + math.pi / 2 + decor:NextNumber(-0.4, 0.4), 0),
			Parent = ctx.Arena,
		})
	end
end

-- Balls and riders ---------------------------------------------------------------------------------

function BumperBallers:_makeBall(player, index: number, spot: Vector3): Entry
	local rider = BumperBallers.Riders[(index - 1) % #BumperBallers.Riders + 1]
	local patternName = rider.Pattern
	local model = Build.Model(`Ball_{player.UserId}`)

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.one * BALL_SIZE
	body.CFrame = CFrame.new(spot)
	body.Transparency = 1
	body.Anchored = true -- until GO
	body.CanQuery = false
	body.CanTouch = false
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	-- Dense (sinks, and riders barely tip it), grippy enough to roll, bouncy enough to boing.
	body.CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.5, 0.55, 1, 1)
	if self.groupReady then
		body.CollisionGroup = BALL_GROUP
	end
	body.Parent = model
	model.PrimaryPart = body

	local visual = MeshLibrary.Get(patternName, {
		Colors = { Shell = rider.Color },
		CFrame = CFrame.new(spot - Vector3.new(0, RADIUS, 0)),
	})
	visual.Name = "Visual"
	local visualRoot = MeshLibrary.Assemble(visual, true)
	visual.Parent = model
	for _, part in visual:GetDescendants() do
		if part:IsA("BasePart") then
			part.CastShadow = true
		end
	end
	Build.Weld(body, visualRoot)

	local centerAttachment = Instance.new("Attachment")
	centerAttachment.Name = "Center"
	centerAttachment.Parent = body
	local force = Instance.new("VectorForce")
	force.Name = "Drive"
	force.Attachment0 = centerAttachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = body
	local socket = Instance.new("BallSocketConstraint")
	socket.Name = "RiderSocket"
	socket.Attachment0 = centerAttachment
	socket.Parent = body

	-- The rider's shape tag, floating over their head in their color.
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Adornee = body
	tag.Size = UDim2.fromScale(2.6, 2.6)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 12.2, 0)
	tag.MaxDistance = 140
	tag.LightInfluence = 0
	tag.Parent = body
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = rider.Shape
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = rider.Color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(1, 1, 1)
	label.Parent = tag

	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("Rider", rider.Name)
	model:SetAttribute("Shape", rider.Shape)
	model:SetAttribute("Color", rider.Color)
	model:SetAttribute("ClientDriven", false)
	model:SetAttribute("Index", index)
	model.Parent = self.ballsFolder -- last, so clients see it complete

	local toCenter = flat(self.center - spot)
	local entry: Entry = {
		Player = player,
		Index = index,
		Model = model,
		Body = body,
		Center = centerAttachment,
		Force = force,
		Socket = socket,
		Seat = nil,
		Align = nil,
		RiderOffset = RADIUS + 3,
		ClientDriven = false,
		Input = Vector3.zero,
		Drive = BumperDrive.new(),
		Position = spot,
		Velocity = Vector3.zero,
		History = {},
		Track = {},
		ReliefUntil = 0,
		Yaw = math.atan2(-toCenter.X, -toCenter.Z),
		Spin = CFrame.identity,
		Out = false,
		LastBumper = nil,
		LastBumpAt = 0,
	}
	return entry
end

-- Stands the rider on top of their ball: socket at the ball's center, kept upright.
function BumperBallers:_attachRider(entry: Entry)
	local character, humanoid, root = self.context:GetCharacter(entry.Player)
	if not character or not humanoid or not root then
		return
	end
	if entry.Seat and entry.Seat.Parent == root then
		return
	end
	-- R6 rigs have no HipHeight: their 2-stud legs hang under a 2-stud root.
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2
	local offset = RADIUS + legs
	entry.RiderOffset = offset
	character:PivotTo(CFrame.new(entry.Position + Vector3.new(0, offset, 0)) * CFrame.Angles(0, entry.Yaw, 0))
	root.AssemblyLinearVelocity = Vector3.zero

	local seat = Instance.new("Attachment")
	seat.Name = "BumperSeat"
	seat.Position = Vector3.new(0, -offset, 0)
	seat.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "BumperUpright"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = seat
	align.RigidityEnabled = true
	align.CFrame = CFrame.Angles(0, entry.Yaw, 0)
	align.Parent = root
	entry.Seat = seat
	entry.Align = align
	entry.Socket.Attachment1 = seat

	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	if physics and entry.Body.Anchored then
		root.Anchored = true -- held on top of the ball until GO, when both are let go together
	end
	-- Remember who rides it, and each part's collision group (players' are the lobby's PP_Players,
	-- which keeps beach balls from being walls), to put back when they get off (:_detachRider).
	local saved = if entry.Rider == character and entry.RiderGroups then entry.RiderGroups else {}
	entry.Rider = character
	entry.RiderGroups = saved
	if self.groupReady then
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				if saved[part] == nil then
					saved[part] = part.CollisionGroup
				end
				part.CollisionGroup = RIDER_GROUP
			end
		end
	end
	if physics and typeof(entry.Player) ~= "Instance" then
		pcall(root.SetNetworkOwner, root, nil) -- a bot's rider is the server's, like its ball
	end
end

-- Gets the rider off: only ever the character that rode this ball. (A knocked-out rider is sent
-- back to the lobby with a new character 1.2 s after going out, before their ball is removed; that
-- one used to be looked up here and left in the Default collision group, so the plaza's beach
-- balls were solid walls for them, and its PlatformStand, AutoRotate and anchoring were changed.)
function BumperBallers:_detachRider(entry: Entry)
	if entry.Seat then
		entry.Seat:Destroy()
		entry.Seat = nil
	end
	if entry.Align then
		entry.Align:Destroy()
		entry.Align = nil
	end
	local character, saved = entry.Rider, entry.RiderGroups
	entry.Rider, entry.RiderGroups = nil, nil
	if not character or not character.Parent then
		return -- gone already (a new character replaced it)
	end
	for part, group in saved or {} do
		if part.Parent then
			part.CollisionGroup = group
		end
	end
	if entry.Player.Character ~= character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
	end
	if root then
		root.Anchored = false
	end
end

function BumperBallers:_removeBall(entry: Entry)
	self:_detachRider(entry)
	if entry.Model.Parent then
		entry.Model:Destroy()
	end
	self.entries[entry.Player] = nil
end

-- Round ---------------------------------------------------------------------------------------------

function BumperBallers:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Eliminate"
	ctx.EndWhenOneLeft = true
	ctx.WalkSpeed = 0 -- riders don't walk; the ball does the moving
	local origin = ctx.Origin.Position
	self.center = origin
	self.top = origin.Y
	self.waterY = origin.Y - WATER_DROP
	self.restY = origin.Y + RADIUS
	self.islandRadius = ISLAND_RADIUS
	ctx.KillY = self.waterY - 25
	self.islandHeight = 14 -- the island mesh's height (tools/meshgen/props/BumperBallers.py)
	self.islandAbove = 0.15 -- how far its sand rises over the grass top
	self.entries = {} :: { [any]: Entry }
	self.pairCooldown = {} :: { [string]: number }
	self.pairBumpAt = {} :: { [string]: number }
	self.held = nil :: { Entries: { Entry }, At: number }? -- went in moments ago (see :_ringOuts)
	self.koCount = {} :: { [any]: number } -- kept after a ball is gone, for the results
	self.bumpScale = 1
	self.groupReady = registerRiderGroup()

	-- What the clients need first (their half starts once the Balls folder exists): the drive's
	-- numbers and where the island is, for the on-island rule and the phone camera. These used to
	-- be set after SpawnAll, which can wait seconds for a character that's still loading; a client
	-- that started before then never saw them, and its player steered hard past the rim, unlike bots.
	ctx:SetSharedJSON("Tuning", {
		MaxSpeed = TUNING.MaxSpeed,
		SteerGain = TUNING.SteerGain,
		SteerAccel = TUNING.SteerAccel,
		Accel = TUNING.Accel,
		Relief = TUNING.Relief,
		ReliefDrag = TUNING.ReliefDrag,
		Touch = TOUCH, -- the client boings at the same distance and closing speed the server bumps at
		ClosingMin = CLOSING_MIN,
	})
	ctx:SetSharedJSON("Island", {
		X = origin.X,
		Y = self.top,
		Z = origin.Z,
		R = ISLAND_RADIUS,
		Water = self.waterY,
	})

	self:_buildArena()
	self.ballsFolder = Build.Folder("Balls", ctx.Arena)

	-- One ball per rider in a ring facing the middle; riders stand on them, frozen until GO.
	local players = ctx:GetPlayers()
	local count = #players
	-- At most 22 from the middle: more than a full-speed bump's slide from the edge, so nobody goes
	-- over to the first charge after GO.
	local ringRadius = math.clamp(count * 1.6 + 4, 12, 22)
	local spots = {}
	local startAngle = rng:NextNumber(0, math.pi * 2)
	for index, player in players do
		local angle = startAngle + (index - 1) / math.max(count, 1) * math.pi * 2
		local spot =
			Vector3.new(origin.X + math.cos(angle) * ringRadius, self.restY, origin.Z + math.sin(angle) * ringRadius)
		local entry = self:_makeBall(player, index, spot)
		self.entries[player] = entry
		spots[index] = CFrame.new(spot + Vector3.new(0, entry.RiderOffset - 3, 0)) * CFrame.Angles(0, entry.Yaw, 0)
	end

	ctx.Hooks.CharacterReady = function(player)
		local entry = self.entries[player]
		if entry then
			self:_attachRider(entry)
		end
	end
	ctx.Hooks.Eliminated = function(player)
		local entry = self.entries[player]
		if not entry then
			return
		end
		entry.Out = true
		entry.Input = Vector3.zero
		entry.Force.Force = Vector3.zero
		if physics and entry.Body.Parent and not entry.Body.Anchored then
			-- Died or reset on top of the ball: anchoring takes it back from their device (whose
			-- last push would otherwise keep rolling it into others), and it sinks from here.
			entry.Body.Anchored = true
		end
		-- The ball sinks for a moment, then it's gone.
		ctx:Delay(1.4, function()
			if self.entries[player] == entry then
				self:_removeBall(entry)
			end
		end)
	end
	ctx.Hooks.PlayerLeft = function(player)
		local entry = self.entries[player]
		if entry then
			self:_removeBall(entry)
		end
	end

	ctx:SpawnAll(spots, true)
	for player, entry in self.entries do
		if ctx:State(player) == nil then
			self:_removeBall(entry) -- spawning failed: they're not in the round, so no empty ball
		else
			self:_attachRider(entry) -- anyone whose character was already placed before the hook ran
		end
	end

	ctx:SetStatus(`Players left: {ctx:AliveCount()}`)
end

function BumperBallers:Start()
	local ctx = self.context

	-- Release the balls: players' to their own devices, bots' to the server.
	local riderless = {}
	for player, entry in self.entries do
		-- Re-seat anyone who reset during the countdown (their new character is in the lobby).
		self:_attachRider(entry)
		local _, humanoid = ctx:GetCharacter(player)
		if not humanoid then
			table.insert(riderless, entry)
		else
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
			humanoid.PlatformStand = true
		end
		if physics then
			entry.Body.Anchored = false
			if typeof(player) == "Instance" then
				entry.ClientDriven = true
				entry.Model:SetAttribute("ClientDriven", true)
				ctx:GiveOwnership(entry.Body, player)
			else
				pcall(entry.Body.SetNetworkOwner, entry.Body, nil)
			end
			local _, _, root = ctx:GetCharacter(player)
			if root then
				root.Anchored = false -- held still on top of the ball during the countdown
			end
		end
	end

	-- A character still loading gets a moment to arrive, then a ball nobody rides is out.
	if #riderless > 0 then
		ctx:Delay(2.5, function()
			for _, entry in riderless do
				if self.entries[entry.Player] ~= entry or entry.Out then
					continue
				end
				self:_attachRider(entry)
				if not ctx:GetCharacter(entry.Player) then
					ctx:Eliminate(entry.Player, "no character")
				end
			end
		end)
	end

	-- Bots and stand-ins steer with the same stick a player has (x, z: a world direction, length <= 1).
	ctx:OnAction("Steer", function(player, x, z)
		local entry = self.entries[player]
		if not entry or entry.ClientDriven or entry.Out then
			return
		end
		if type(x) ~= "number" or type(z) ~= "number" or x ~= x or z ~= z then
			return
		end
		local input = Vector3.new(math.clamp(x, -1, 1), 0, math.clamp(z, -1, 1))
		if input.Magnitude > 1 then
			input = input.Unit
		end
		entry.Input = input
	end, { Interval = 0.03 })

	ctx:Delay(BIG_BUMPS_AT, function()
		self.bumpScale = BIG_BUMPS
		ctx:SetShared("BigBumps", true)
		ctx:Announce("💥 BIG BUMPS! 💥", "warning", 2.5)
		ctx:Sound("HazardWarning")
	end)

	local shownStatus = ""
	local sampleClock = 0
	ctx:Heartbeat(function(dt)
		dt = math.min(dt, 0.1)
		sampleClock += dt
		local record = sampleClock >= 1 / 30
		if record then
			sampleClock = 0
		end
		local live = {}
		local fallen = {}
		local now = os.clock()
		for _, entry in self.entries do
			if not entry.Model.Parent then
				continue
			elseif entry.Out then
				-- Knocked out: the ball sinks slowly where it splashed down.
				if entry.Body.Anchored then
					entry.Model:PivotTo(entry.Model:GetPivot() - Vector3.new(0, 3.5 * dt, 0))
				end
				continue
			end
			self:_step(entry, dt)
			if entry.ClientDriven then
				self:_checkBump(entry)
				self:_police(entry, dt)
			end
			local track = entry.Track
			table.insert(track, 1, { T = now, P = entry.Position, V = entry.Velocity })
			while #track > 2 and track[#track].T < now - TRACK_SECONDS do
				table.remove(track)
			end
			if record then
				table.insert(entry.History, 1, entry.Velocity)
				if #entry.History > HISTORY then
					table.remove(entry.History)
				end
			end
			-- Out: under the water, or hanging past the rim for longer than a real fall takes.
			local beyond = flat(entry.Position - self.center).Magnitude > ISLAND_RADIUS + 6
			if not beyond then
				entry.BeyondSince = nil
			elseif not entry.BeyondSince then
				entry.BeyondSince = os.clock()
			end
			local _, _, riderRoot = ctx:GetCharacter(entry.Player)
			if
				entry.Position.Y < self.waterY - OUT_DEPTH
				or (entry.BeyondSince and os.clock() - entry.BeyondSince > 0.8)
				or (riderRoot and riderRoot.Position.Y < self.waterY - OUT_DEPTH) -- came off the ball
			then
				table.insert(fallen, entry)
			else
				table.insert(live, entry)
			end
		end
		if #fallen > 0 then
			self:_ringOuts(fallen)
		end
		self:_bumps(live, dt)
		local status = `Players left: {ctx:AliveCount()}`
		if self.bumpScale > 1 then
			status ..= "  •  💥 BIG BUMPS!"
		end
		if status ~= shownStatus then
			shownStatus = status
			ctx:SetStatus(status)
		end
	end)
end

-- Moves one ball for a frame: reads where a player's ball is, or drives a bot's.
function BumperBallers:_step(entry: Entry, dt: number)
	local body = entry.Body
	if entry.ClientDriven then
		entry.Position = body.Position
		entry.Velocity = body.AssemblyLinearVelocity
		if physics and os.clock() < (entry.PolicedUntil or 0) then
			-- Taken back for a moment (see :_takeBack): it rolls as if its stick were let go, so it
			-- slows like any ball instead of coasting on with nothing holding it back.
			self:_drive(entry, dt, Vector3.zero)
			entry.ServerDriving = true
		elseif entry.ServerDriving then
			entry.ServerDriving = false
			entry.Force.Force = Vector3.zero -- their device drives it again
		end
		return
	end
	if physics then
		self:_drive(entry, dt, entry.Input)
		self:_face(entry, flat(entry.Velocity), dt)
		return
	end
	self:_simulate(entry, dt)
end

-- Whether a ball sitting here grips the island top (steers hard; see Logic/BumperDrive).
function BumperBallers:_grips(position: Vector3): boolean
	return BumperDrive.Grips(flat(position - self.center).Magnitude, position.Y - self.top, ISLAND_RADIUS, RADIUS)
end

-- Pushes a ball the server rolls (with physics) the way `input` steers, with the drive every
-- device rolls its own ball with.
function BumperBallers:_drive(entry: Entry, dt: number, input: Vector3)
	local body = entry.Body
	local velocity = body.AssemblyLinearVelocity
	local grip = self:_grips(body.Position)
	local ax, az = entry.Drive:Step(os.clock(), dt, velocity.X, velocity.Z, input.X, input.Z, grip)
	-- On the island it rolls (it spins up too); off it, in the air, it doesn't.
	entry.Force.Force = Vector3.new(ax, 0, az) * self:_mass(entry, grip)
	entry.Position = body.Position
	entry.Velocity = velocity
end

-- Turns the rider to face where they roll (or where they steer when nearly still).
function BumperBallers:_face(entry: Entry, velocity: Vector3, dt: number)
	local heading = if velocity.Magnitude > 2 then velocity else entry.Input
	if heading.Magnitude > 0.1 then
		local target = math.atan2(-heading.X, -heading.Z)
		local delta = (target - entry.Yaw + math.pi) % (math.pi * 2) - math.pi
		entry.Yaw += delta * math.min(1, dt * 8)
	end
	if entry.Align then
		entry.Align.CFrame = CFrame.Angles(0, entry.Yaw, 0)
	end
end

-- No-physics servers: integrate the same drive model, fall off the edge, and keep balls apart.
function BumperBallers:_simulate(entry: Entry, dt: number)
	local position, velocity = entry.Position, entry.Velocity
	local horizontal = flat(velocity)
	local input = entry.Input
	local grip = self:_grips(position)
	local ax, az = entry.Drive:Step(os.clock(), dt, horizontal.X, horizontal.Z, input.X, input.Z, grip)
	horizontal += Vector3.new(ax, 0, az) * dt
	local vertical = velocity.Y
	local onIsland = flat(position - self.center).Magnitude <= ISLAND_RADIUS and position.Y >= self.restY - 0.5
	if onIsland and position.Y <= self.restY + 0.01 and vertical <= 0 then
		vertical = 0
	else
		vertical -= GRAVITY * dt
	end
	position += (horizontal + Vector3.new(0, vertical, 0)) * dt
	if onIsland and position.Y < self.restY then
		position = Vector3.new(position.X, self.restY, position.Z)
	end
	-- Separate overlapping balls (physics would).
	for _, other in self.entries do
		if other ~= entry and not other.Out then
			local gap = flat(position - other.Position)
			local distance = gap.Magnitude
			if distance > 0.01 and distance < BALL_SIZE then
				position += gap.Unit * (BALL_SIZE - distance) * 0.5
			end
		end
	end
	entry.Position = position
	entry.Velocity = horizontal + Vector3.new(0, vertical, 0)
	-- Roll the ball visibly and carry the rider.
	if horizontal.Magnitude > 0.05 then
		local axis = Vector3.yAxis:Cross(horizontal.Unit)
		entry.Spin = CFrame.fromAxisAngle(axis, horizontal.Magnitude * dt / RADIUS) * entry.Spin
	end
	entry.Model:PivotTo(CFrame.new(position) * entry.Spin)
	self:_face(entry, horizontal, dt)
	local character = entry.Player.Character
	if character and character.Parent then
		character:PivotTo(CFrame.new(position + Vector3.new(0, entry.RiderOffset, 0)) * CFrame.Angles(0, entry.Yaw, 0))
	end
end

-- How much a push or drive force has to move: the ball plus its rider (joined by a socket).
-- A rolling ball also has to spin up, so driving it takes 7/5 of the force (`rolling`).
function BumperBallers:_mass(entry: Entry, rolling: boolean?): number
	local mass = entry.Body.AssemblyMass * (if rolling then ROLL_MASS else 1)
	local _, _, root = self.context:GetCharacter(entry.Player)
	if root and entry.Seat then
		mass += root.AssemblyMass
	end
	return mass
end

function BumperBallers:_ping(entry: Entry): number
	if typeof(entry.Player) ~= "Instance" then
		return 0
	end
	local player = entry.Player :: Player
	local ok, ping = pcall(player.GetNetworkPing, player)
	return if ok and type(ping) == "number" then math.clamp(ping, 0, 0.6) else 0.15
end

-- Pushes a ball by `dv` studs/s: through the owner's device for players (checked afterwards, see
-- :_checkBump), directly for bots. No `bumper` means a gentle nudge apart, not a bump.
function BumperBallers:_push(entry: Entry, dv: Vector3, bumper: Entry?)
	local now = os.clock()
	if bumper then
		entry.ReliefUntil = now + TUNING.Relief
		entry.LastBumper = bumper.Player
		entry.LastBumpAt = now
	end
	local relief = if bumper then TUNING.Relief else 0
	if entry.ClientDriven and now >= (entry.PolicedUntil or 0) then
		self.context:Fire(entry.Player, "Bump", dv, relief)
		if bumper then
			local pending = entry.PendingBump
			if pending then
				pending.Dv += dv
			else
				entry.PendingBump = { Dv = dv, Before = entry.Velocity, At = now, Peak = 0 }
			end
		end
	else
		self:_kick(entry, dv, relief)
	end
end

-- Pushes a ball the server rolls itself (a bot's, or a player's it has taken back) by `dv`, with
-- `relief` seconds of bump relief.
function BumperBallers:_kick(entry: Entry, dv: Vector3, relief: number)
	local now = os.clock()
	if physics then
		entry.Body:ApplyImpulse(dv * self:_mass(entry))
		-- What the ball rolls on with once it grips the ground again (the rest spins it up): its drive
		-- lets that fade the way bumps always did instead of steering it away.
		local keep = self:_mass(entry) / self:_mass(entry, true)
		entry.Drive:Bump(now, dv.X * keep, dv.Z * keep, relief)
	else
		entry.Velocity += dv
		entry.Drive:Bump(now, dv.X, dv.Z, relief)
	end
end

-- A player's device rolls their ball, so make sure a bump really happened there: if their ball
-- never picked up the push (a cheat, an app in the background, lost packets), the server takes
-- the ball back for a second and pushes it itself.
function BumperBallers:_checkBump(entry: Entry)
	local pending = entry.PendingBump
	if not pending then
		return
	end
	local push = flat(pending.Dv)
	if push.Magnitude < 1 then
		entry.PendingBump = nil
		return
	end
	local gained = flat(entry.Velocity - pending.Before):Dot(push.Unit)
	pending.Peak = math.max(pending.Peak, gained)
	if pending.Peak >= 0.4 * push.Magnitude then
		entry.PendingBump = nil
		return
	end
	if os.clock() - pending.At < 0.35 + self:_ping(entry) then
		return
	end
	entry.PendingBump = nil
	if self:_takeBack(entry, 1) then
		self:_kick(entry, pending.Dv, TUNING.Relief)
		self.forcedBumps = (self.forcedBumps or 0) + 1
	end
end

-- The server moves a player's ball itself for `seconds`, then hands it back to their device.
function BumperBallers:_takeBack(entry: Entry, seconds: number): boolean
	local body = entry.Body
	if entry.Out or not body.Parent or body.Anchored then
		return false
	end
	if os.clock() >= (entry.PolicedUntil or 0) then
		entry.Drive = BumperDrive.new() -- the server rolls it from here (see :_step): nothing carried over
	end
	entry.PolicedUntil = math.max(entry.PolicedUntil or 0, os.clock() + seconds)
	entry.PendingBump = nil
	pcall(body.SetNetworkOwner, body, nil)
	self.context:Delay(seconds, function()
		if os.clock() < (entry.PolicedUntil or 0) - 0.05 then
			return -- taken back again since: that call hands it back
		end
		if not entry.Out and body.Parent and not body.Anchored then
			self.context:GiveOwnership(body, entry.Player)
		end
	end)
	return true
end

-- How late a player's screen draws the other balls: a network round trip, plus the time the engine
-- holds replicated parts back to move them smoothly. Nil for a ball no screen of its own drives.
function BumperBallers:_viewDelay(entry: Entry): number?
	if not entry.ClientDriven then
		return nil
	end
	return self:_ping(entry) + VIEW_LAG
end

-- The strongest closing speed of `a` into `b` along `normal`: now (`va`, `vb`) or in the last few
-- samples (the server sees a player's ball a bit late). Also each ball's own speed into the other.
local function closingAlong(a: Entry, b: Entry, normal: Vector3, va: Vector3, vb: Vector3): (number, number, number)
	local speedA, speedB, closing = 0, 0, 0
	local function try(ua: Vector3, ub: Vector3)
		local into = flat(ua):Dot(normal) - flat(ub):Dot(normal)
		if into > closing then
			closing = into
			speedA = math.max(0, flat(ua):Dot(normal))
			speedB = math.max(0, -flat(ub):Dot(normal))
		end
	end
	try(va, vb)
	for k = 1, math.min(#a.History, #b.History) do
		try(a.History[k], b.History[k])
	end
	return closing, speedA, speedB
end

-- Finds balls that just met and bumps them apart: the faster ball into the other wins.
-- They've met when their shells touch (TOUCH) on the screen of a player riding one of them (the
-- other ball where that screen drew it, a round trip and VIEW_LAG back; on either screen when both
-- are players), or for two bots, as the server sees them.
function BumperBallers:_bumps(live: { Entry }, dt: number)
	local now = os.clock()
	local sweep = math.max(dt, 1 / 30) -- also look back over the last step: nothing slips through
	self.separateCooldown = self.separateCooldown or {}
	for i = 1, #live do
		local a = live[i]
		for j = i + 1, #live do
			local b = live[j]
			local gap = b.Position - a.Position
			if gap.Magnitude > TOUCH + 30 then
				continue -- too far apart even for a screen a long round trip behind
			end
			local key = if a.Index < b.Index then `{a.Index}:{b.Index}` else `{b.Index}:{a.Index}`
			if now < (self.pairCooldown[key] or 0) then
				continue
			end
			-- Each view: the gap from a to b, how fast it closes, and the window to look over.
			local normal, closing, speedA, speedB, screen = nil, 0, 0, 0, false
			local function try(at: Vector3, va: Vector3, vb: Vector3, from: number, to: number, isScreen: boolean)
				local touch = closestGap(at, vb - va, from, to)
				if touch.Magnitude > TOUCH then
					return
				end
				local direction = if flat(touch).Magnitude > 0.01 then flat(touch) else flat(at)
				if direction.Magnitude < 0.01 then
					return
				end
				local n = direction.Unit
				local c, sa, sb = closingAlong(a, b, n, va, vb)
				if not normal or (closing < CLOSING_MIN and c > closing) then
					normal, closing, speedA, speedB, screen = n, c, sa, sb, isScreen
				end
			end
			local delayA, delayB = self:_viewDelay(a), self:_viewDelay(b)
			if not delayA and not delayB then
				-- Two bots: everyone sees them alike (a moment late), so the server's view is the one.
				try(gap, a.Velocity, b.Velocity, -sweep, 0, false)
			else
				-- What each player's screen shows: their own ball where it is, the other where it was
				-- drawn, looking a round trip ahead (when the push gets back to them), and only once
				-- their last bump has played out there.
				local lastBump = self.pairBumpAt[key] or -math.huge
				if delayA and now - delayA > lastBump + 0.05 then
					local position, velocity = trackAt(b, now - delayA)
					try(position - a.Position, a.Velocity, velocity, -sweep, math.min(self:_ping(a), MAX_LEAD), true)
				end
				if (not normal or closing < CLOSING_MIN) and delayB and now - delayB > lastBump + 0.05 then
					local position, velocity = trackAt(a, now - delayB)
					try(b.Position - position, velocity, b.Velocity, -sweep, math.min(self:_ping(b), MAX_LEAD), true)
				end
			end
			if not normal then
				continue
			end
			if closing < CLOSING_MIN then
				-- Balls pass through each other physically, so two slow ones overlapping get eased apart.
				local apart = flat(gap)
				if
					gap.Magnitude < BALL_SIZE - 0.3
					and apart.Magnitude > 0.01
					and now >= (self.separateCooldown[key] or 0)
				then
					self.separateCooldown[key] = now + 0.2
					self:_push(b, apart.Unit * SEPARATE_SPEED)
					self:_push(a, -apart.Unit * SEPARATE_SPEED)
				end
				continue
			end
			self.pairCooldown[key] = now + PAIR_COOLDOWN
			self.pairBumpAt[key] = now
			local scale = self.bumpScale
			local base = BUMP_BASE * math.clamp(closing / 12, 0.3, 1) -- a gentle touch is a gentle bump
			local toB = math.min(BUMP_MAX, (base + BUMP_GAIN * speedA + BUMP_SELF * speedB) * scale)
			local toA = math.min(BUMP_MAX, (base * 0.7 + BUMP_GAIN * speedB + BUMP_SELF * speedA) * scale)
			local lift = Vector3.new(0, BUMP_LIFT, 0)
			self:_push(b, normal * toB + lift, a)
			self:_push(a, -normal * toA + lift, b)
			local strength = math.clamp(closing / (TUNING.MaxSpeed * 2), 0.2, 1)
			local point = a.Position + normal * RADIUS
			self.context:Fire(nil, "Boing", point, strength, a.Player.UserId, b.Player.UserId)
			self.bumpCount = (self.bumpCount or 0) + 1
			if screen then
				self.screenBumps = (self.screenBumps or 0) + 1
			end
		end
	end
end

-- A player's device moves their ball, so keep it honest. Taken back by the server for a moment:
-- a ball far faster than rolling can make it (a bump's extra speed is allowed while it lasts),
-- one held up in the air, or one hanging past the rim where nothing could hold it.
function BumperBallers:_police(entry: Entry, _dt: number)
	local now = os.clock()
	if now < (entry.PolicedUntil or 0) then
		entry.FastSince, entry.HighSince, entry.HangSince = nil, nil, nil
		return
	end
	local velocity = entry.Velocity
	local horizontal = flat(velocity)
	local speed = horizontal.Magnitude
	local bumped = now < entry.ReliefUntil + 1 + self:_ping(entry)
	local fast = speed > TUNING.MaxSpeed * 1.6 and not bumped
	entry.FastSince = if fast then entry.FastSince or now else nil
	local high = entry.Position.Y > self.restY + 6
	entry.HighSince = if high then entry.HighSince or now else nil
	local hanging = flat(entry.Position - self.center).Magnitude > ISLAND_RADIUS + 1.5
		and entry.Position.Y > self.restY - 1
	entry.HangSince = if hanging then entry.HangSince or now else nil

	if speed > MAX_LEGIT_SPEED or (entry.FastSince and now - entry.FastSince > 0.25) then
		if self:_takeBack(entry, 1) then
			local slowed = if speed > 0.01 then horizontal.Unit * TUNING.MaxSpeed else Vector3.zero
			entry.Body.AssemblyLinearVelocity = slowed + Vector3.new(0, math.min(velocity.Y, 0), 0)
			self.policed = (self.policed or 0) + 1
		end
	elseif (entry.HighSince and now - entry.HighSince > 1) or (entry.HangSince and now - entry.HangSince > 0.6) then
		if self:_takeBack(entry, 1) then
			-- Gravity takes it from here.
			entry.Body.AssemblyLinearVelocity = horizontal * 0.5 + Vector3.new(0, math.min(velocity.Y, 0), 0)
			self.policed = (self.policed or 0) + 1
		end
	end
end

-- Stops a ball that fell in: it splashes and sinks (see Start).
function BumperBallers:_splash(entry: Entry)
	entry.Out = true
	entry.Input = Vector3.zero
	entry.PendingBump = nil
	entry.Force.Force = Vector3.zero
	if physics and entry.Body.Parent then
		entry.Body.Anchored = true -- the server takes it from here (it sinks; see Start)
		entry.Model:PivotTo(
			CFrame.new(entry.Position.X, math.max(entry.Position.Y, self.waterY - OUT_DEPTH), entry.Position.Z)
		)
	end
	self.context:Fire(nil, "Splash", Vector3.new(entry.Position.X, self.waterY, entry.Position.Z), entry.Player.UserId)
end

-- Everyone who fell in this frame. If that's all the riders left (often: both go over after a
-- bump), nobody beat anybody, so they share the win; otherwise the first one in goes out first.
-- When all but one are in, the result waits DRAW_WINDOW: each screen draws the other ball a moment
-- late, so if the last one follows within it, it's a draw too (it used to take the same frame).
function BumperBallers:_ringOuts(fallen: { Entry })
	local ctx = self.context
	local riding = 0
	for _, entry in fallen do
		if ctx:IsAlive(entry.Player) then
			riding += 1
		end
	end
	local held = self.held
	local holding = 0
	if held then
		for _, entry in held.Entries do
			if ctx:IsAlive(entry.Player) then
				holding += 1
			end
		end
	end
	if riding >= 1 and riding + holding >= 2 and riding + holding >= ctx:AliveCount() then
		for _, entry in fallen do
			self:_splash(entry)
		end
		self.held = nil
		self.draws = (self.draws or 0) + 1
		ctx:End("Draw")
		return
	end
	table.sort(fallen, function(a, b)
		return a.Position.Y < b.Position.Y
	end)
	if riding >= 1 and ctx:AliveCount() - holding - riding == 1 then
		-- One rider left on the island: hold the result a moment in case they follow.
		local hold = held or { Entries = {}, At = ctx:Elapsed() }
		self.held = hold
		for _, entry in fallen do
			if ctx:IsAlive(entry.Player) then
				self:_splash(entry)
				table.insert(hold.Entries, entry)
			else
				self:_ringOut(entry)
			end
		end
		ctx:Delay(DRAW_WINDOW, function()
			if self.held ~= hold or not ctx:IsRunning() then
				return -- a draw, or the round's over (GetResults counts them as fallen)
			end
			self.held = nil
			for _, entry in hold.Entries do
				self:_ringOut(entry, true)
			end
		end)
		return
	end
	for _, entry in fallen do
		self:_ringOut(entry)
	end
end

function BumperBallers:_ringOut(entry: Entry, splashed: boolean?)
	local ctx = self.context
	if not splashed then
		self:_splash(entry)
	end
	if ctx:State(entry.Player) == nil then
		self:_removeBall(entry) -- not in the round any more: nothing to eliminate, no KO
		return
	end
	-- Whoever bumped them in the last few seconds gets the knock-out.
	local bumper = entry.LastBumper
	if bumper and bumper ~= entry.Player and os.clock() - entry.LastBumpAt < 4 then
		local kos = (self.koCount[bumper] or 0) + 1
		self.koCount[bumper] = kos
		if ctx:State(bumper) then
			ctx:SetScoreText(bumper, if kos == 1 then "1 KO" else `{kos} KOs`)
		end
	end
	self.ringOuts = (self.ringOuts or 0) + 1
	ctx:Eliminate(entry.Player, "fell")
end

-- Survival results (last one rolling wins), with each rider's knock-outs shown, and breaking
-- ties between riders who fell at the same moment.
function BumperBallers:GetResults()
	local results = self.context:SurvivalResults()
	-- Riders who went in just before the round ended, still waiting on a draw: they fell.
	local held = self.held
	if held then
		for _, result in results.Entries do
			for _, entry in held.Entries do
				if entry.Player == result.Player then
					result.Rank = math.floor(held.At * 10) / 10
					result.ScoreText = string.format("Lasted %ds", math.floor(held.At))
					result.BestScore = math.floor(held.At)
					result.Survived = held.At
				end
			end
		end
	end
	for _, result in results.Entries do
		local kos = if self.koCount then self.koCount[result.Player] or 0 else 0
		if kos > 0 then
			result.ScoreText ..= if kos == 1 then " • 1 KO" else ` • {kos} KOs`
			if result.Rank < 1e6 then
				result.Rank += math.min(kos, 9) * 0.01
			end
		end
	end
	return results
end

function BumperBallers:Stop()
	-- Everything freezes where it is for the results.
	for _, entry in self.entries do
		entry.Input = Vector3.zero
		if entry.Model.Parent then
			entry.Force.Force = Vector3.zero
			entry.Body.Anchored = true
		end
	end
end

function BumperBallers:Cleanup()
	for _, entry in self.entries do
		self:_detachRider(entry)
	end
	self.entries = {}
end

return BumperBallers

-- Struggle (Versus, 70s, 2-12 players, free for all). Owner: "Also lets add this into the backburner
-- for games. https://kingdomhearts.fandom.com/wiki/Struggle". After the Struggle matches of Kingdom
-- Hearts II (the Sandlot): everyone fights with a foam bat; each player starts with a pile of orbs in
-- their own colour, every hit knocks some of the victim's orbs loose, scattering them on the ground,
-- and anyone can pick loose orbs up. Most orbs when time runs out wins (ties: hits landed); the match
-- ends early if one player holds every orb.
--
-- Here: a sunset sandlot inside a plank fence, a tram yard behind it. Everyone starts with 20 orbs
-- of their own colour AND shape (● ■ ▲ ◆ ★ ... one per player, so colour is never the only cue).
-- SWING (button, E, or a click on PC): a tap winds up for a moment you can see (the bat goes back
-- over the shoulder) and strikes; holding it charges (the bat glows, you walk slower) and a charged
-- swing reaches further (the bat is drawn longer), knocks out 6 orbs instead of 3 (a tenth of a big
-- pile, doubled when charged, so a runaway leader can be caught) and throws the victim harder. A
-- victim is safe for a moment after a hit (no juggling, and no grabbing their orbs straight back)
-- and nobody is ever out: at 0 orbs you keep fighting.
--
-- How it works (the server owns everything; Shared/Logic/Struggle has the numbers and the hit test):
--   * A press sends "Charge" with when it was pressed on the player's screen, a release "Swing"
--     with when it was released (both kept within the player's ping, like Rake It In). A release
--     with no live charge (the press came during the 3-2-1, or a moment before the bat was ready) is
--     a plain tap from the release, so an early press never eats a later legit swing. The server
--     lets a charge go by itself after MAX_HOLD.
--   * The strike is judged when the attacker's screen showed it: their own position as the server
--     has it one-way after the strike, the victims where the attacker saw them (positions recorded
--     20 times a second, rewound by the attacker's one-way trip plus Roblox's interpolation, capped).
--     The reach is the drawn bat's (the client draws the rule itself as a fan on the sand). Everyone
--     in the arc is hit (a crowd can all get it). "Wind" / "Strike" / "Hit" events are cues for clients;
--     the bats are drawn on clients from them.
--   * Loose orbs are the server's ([id, slot, x, z, fromX, fromZ, droppedAt]): a hit throws them on
--     an arc from the victim back toward the swinger and out to the sides (the victim flies the
--     other way); they can be picked up once landed, by whoever is nearest within reach. "Drop" /
--     "Take" events carry each moment; the full list ("Orbs") is shared every few seconds while it
--     changes, so a client that starts late sees them all. Held counts and hits are shared as "Held".
--   * Bots swing through ctx:BotAction exactly like players, ctx:Knockback throws bots and players
--     alike, and bots pick orbs up by the same distance check: no hazard is client-only.
--   * Nobody's character collides with anyone else's (one mode-only group, respawns included): a
--     player shoving a server-moved bot could fling it; the bat decides every contact anyway.
--   * The fence is about 10 studs tall (a jump reaches 7.2), a knock adds no lift to someone already
--     in the air, and anyone who still ends up outside the fence is put back inside.
--   * A press the server turns down (cooldown, knocked down) gets a "Refused" back, so the player's
--     screen stops drawing that swing.
--   * Nothing solid where nothing is drawn (owner: "Theres invisible stuff you can jump on and hang
--     on in several games"): only the sand, the ground and the fence collide; the fence is plank
--     boards, rails and posts whose collision is their own drawn shape. Everything behind it (tram,
--     scoreboard, benches, banners) is scenery nobody can reach.
--
-- Bats in hand (owner: "Bats on struggle arent actually being held they are floating. plus they dont
-- even look like bats."): the bat is a real bat (knob, taped handle, flare, thick barrel; Props
-- StruggleBat), and clients draw it in every character's right hand and swing the arm with it, from
-- the same Wind / Strike cues (client half and Shared/Logic/Struggle's poses, whose tip follows the
-- reach below). Nothing here changed: the server's swings and hits are judged exactly as before.
--
-- Sweep pass (owner: "Let's do a full bug and clean sweep."): the leave hook is set before anyone is
-- placed. Set after ctx:SpawnAll, it missed anyone the round couldn't place (SpawnAll waits out a
-- failed spawn, and a failure counts as leaving) or who left meanwhile: they kept their 20 orbs on
-- the scoreboard, those orbs never reached the sand, and as a second holder they made "holds every
-- orb" impossible for the rest of the match.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Rules = require(ReplicatedStorage.Shared.Logic.Struggle)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local Struggle = MiniGame.Define("Struggle")
Struggle.Rules = Rules -- for the bot brain and the round harness's test bot

local FENCE_X = Rules.FIELD_X + 2
local FENCE_Z = Rules.FIELD_Z + 2
local PANEL = 12 -- a fence panel's width (studs; the sides are whole numbers of panels)
local SIGN = { Y = 10.6, W = 15.5, H = 6.2, Z = 0.62 } -- the scoreboard's lit face (its mesh, studs)
local BOARD_SCALE = 1.3 -- the scoreboard is drawn this much bigger, so its face clears the fence
local CHARGE_SPEED = 10 -- walk speed while charging
local MAX_LAG = 0.4 -- the longest round trip we allow for
local REWIND_CAP = 0.3 -- the furthest back a victim is judged
local INTERP = 0.1 -- Roblox draws other characters about this far behind
local HISTORY = 16 -- position samples kept (every 0.05 s)
local GROUP = "PP_Struggle" -- every participant's character (see setUpGroup)
local ORB_SNAPSHOT = 3 -- seconds between full lists of loose orbs (Drop / Take events carry the moments)
local FALL_SAFE = 3.8 -- a root this far above the sand is in the air (standing is about 3)
local BOT_MAX_FLAT, BOT_MAX_UP = 80, 45 -- a bot never goes faster than its hardest knock

local rng = Random.new()

export type Swing = {
	Start: number, -- server time the press was made
	StrikeAt: number?, -- set once released
	Charged: boolean,
	Cancelled: boolean,
}

-- Everyone in the round passes through everyone else (one mode-only group that doesn't collide with
-- itself; it still collides with the sand and the fence). Bodies shoving bodies only flung people
-- around (a server-moved bot shoved by a player could fly), and the bat decides every contact anyway.
-- Characters made later (a respawn) are put in it too (Struggle:_groupCharacters, every 0.1 s); the
-- lobby's own groups come back with the fresh characters everyone gets after the round.
local function setUpGroup(): boolean
	return pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(GROUP) then
			PhysicsService:RegisterCollisionGroup(GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	end)
end

local function round2(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- A player's round trip (seconds), capped; bots have none.
local function pingOf(player: any): number
	if BotRegistry.IsBot(player) then
		return 0
	end
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and finite(ping) then math.clamp(ping, 0, MAX_LAG) else 0.15
end

function Struggle:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 30
	local origin = ctx.Origin.Position
	self.center = origin
	self.slots = {} :: { [any]: number }
	self.held = {} :: { [any]: number }
	self.hits = {} :: { [any]: number }
	self.swings = {} :: { [any]: Swing }
	self.readyAt = {} :: { [any]: number }
	self.safeUntil = {} :: { [any]: number }
	self.stunUntil = {} :: { [any]: number }
	self.history = {} :: { [any]: { { any } } }
	self.orbs = {} :: { [number]: { number } }
	self.nextOrb = 0
	self.orbsDirty = true
	self.heldDirty = true
	self.lastOrbShare = -math.huge
	self.sign = nil :: TextLabel?
	self.grouped = {} :: { [any]: Model }
	self.groupReady = false

	self:_buildArena()

	-- Slots: a colour and a shape each, in a shuffled order.
	local players = ctx:GetPlayers()
	for index = #players, 2, -1 do
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local roster = {}
	for index, player in players do
		local slot = (index - 1) % #Rules.SLOTS + 1
		self.slots[player] = slot
		self.held[player] = Rules.START_ORBS
		self.hits[player] = 0
		ctx:AddScore(player, Rules.START_ORBS)
		ctx:SetScoreText(player, `{Rules.START_ORBS} orbs`)
		table.insert(roster, { player.UserId, slot })
	end
	self.roster = roster
	ctx:SetSharedJSON("Roster", roster)
	ctx:SetSharedJSON("Field", { Center = { origin.X, origin.Y, origin.Z } })

	-- Everyone on an oval facing the middle.
	local points = {}
	local count = #ctx:GetPlayers()
	for index = 1, count do
		local angle = (index - 1) / math.max(count, 1) * math.pi * 2
		local radius = if count <= 2 then 9 else 16
		local spot = origin + Vector3.new(math.cos(angle) * radius * 1.3, 0.5, math.sin(angle) * radius)
		table.insert(points, CFrame.lookAt(spot, Vector3.new(origin.X, spot.Y, origin.Z)))
	end
	-- (Before anyone is placed: someone who can't be, or leaves meanwhile, spills their orbs too.)
	ctx.Hooks.PlayerLeft = function(player)
		self:_onLeave(player)
	end
	ctx:SpawnAll(points, true)
	ctx.Hooks.Respawn = function(_player)
		local spot = origin
			+ Vector3.new(
				rng:NextNumber(-Rules.FIELD_X + 6, Rules.FIELD_X - 6),
				0.5,
				rng:NextNumber(-Rules.FIELD_Z + 6, Rules.FIELD_Z - 6)
			)
		return CFrame.lookAt(spot, Vector3.new(origin.X, spot.Y, origin.Z))
	end
	ctx.Hooks.CharacterReady = function(player)
		local swing = self.swings[player]
		if ctx:IsRunning() then
			ctx:SetWalkSpeed(player, if swing and not swing.StrikeAt then CHARGE_SPEED else ctx.WalkSpeed)
		end
	end

	for _, slot in Rules.SLOTS do
		ctx:ShareTemplate(slot.Prop, MeshLibrary.Get(slot.Prop))
	end
	ctx:ShareTemplate("StruggleBat", MeshLibrary.Get("StruggleBat"))
	ctx:ShareTemplate("StruggleReach", MeshLibrary.Get("StruggleReach"))

	self:_shareHeld()
	self:_shareOrbs()
	ctx:SetStatus("Knock their orbs loose - grab them!")
end

-- The sandlot: sand inside a plank fence, a tram yard to the south, the scoreboard to the north,
-- benches and banners along the sides, trees far off.
function Struggle:_buildArena()
	local ctx = self.context
	local origin = self.center
	local arena = ctx.Arena
	local chalk = Color3.fromRGB(250, 246, 235)
	-- Dry grass out to the horizon, a little below the sand's top.
	Build.Part({
		Name = "Ground",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 700, 700),
		CFrame = CFrame.new(origin - Vector3.new(0, 2.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(150, 150, 84),
		Material = Enum.Material.Grass,
		Parent = arena,
	})
	Build.Part({
		Name = "Sand",
		Size = Vector3.new(FENCE_X * 2, 2, FENCE_Z * 2),
		CFrame = CFrame.new(origin - Vector3.new(0, 1, 0)),
		Color = Color3.fromRGB(226, 190, 140),
		Material = Enum.Material.Sand,
		Parent = arena,
	})
	-- Chalk lines on the sand: a halfway line and a centre circle.
	-- (The halfway line stops at the circle, so the two never overlap and flicker.)
	local halfLength = FENCE_Z - 1.5 - 9.8
	for _, side in { -1, 1 } do
		Build.Decor({
			Name = "Chalk",
			Size = Vector3.new(0.4, 0.04, halfLength),
			CFrame = CFrame.new(origin + Vector3.new(0, 0.07, side * (9.8 + halfLength / 2))),
			Color = chalk,
			Transparency = 0.2,
			Parent = arena,
		})
	end
	for index = 0, 35 do
		local angle = index / 36 * math.pi * 2
		Build.Decor({
			Name = "Chalk",
			Size = Vector3.new(0.4, 0.04, 1.4),
			CFrame = CFrame.new(origin + Vector3.new(math.cos(angle) * 9, 0.085, math.sin(angle) * 9))
				* CFrame.Angles(0, -angle, 0),
			Color = chalk,
			Transparency = 0.2,
			Parent = arena,
		})
	end

	-- The fence: each panel carries the post at its left end, so every corner gets exactly one.
	local sides = {
		{ From = Vector3.new(-FENCE_X, 0, -FENCE_Z), Dir = Vector3.new(1, 0, 0), Length = FENCE_X * 2 },
		{ From = Vector3.new(FENCE_X, 0, -FENCE_Z), Dir = Vector3.new(0, 0, 1), Length = FENCE_Z * 2 },
		{ From = Vector3.new(FENCE_X, 0, FENCE_Z), Dir = Vector3.new(-1, 0, 0), Length = FENCE_X * 2 },
		{ From = Vector3.new(-FENCE_X, 0, FENCE_Z), Dir = Vector3.new(0, 0, -1), Length = FENCE_Z * 2 },
	}
	for _, side in sides do
		local panels = math.floor(side.Length / PANEL + 0.5)
		local inward = Vector3.new(-side.Dir.Z, 0, side.Dir.X)
		for index = 0, panels - 1 do
			local mid = origin + side.From + side.Dir * ((index + 0.5) * PANEL)
			MeshLibrary.Get("StruggleFence", {
				CFrame = CFrame.lookAt(mid, mid + inward),
				Parent = arena,
			})
		end
	end

	-- North: the scoreboard behind the fence, looking over it, flanked by banners.
	local boardAt = origin + Vector3.new(0, 0, -FENCE_Z - 8)
	local board = MeshLibrary.Get("StruggleScoreboard", {
		Scale = BOARD_SCALE,
		CFrame = CFrame.lookAt(boardAt, Vector3.new(origin.X, boardAt.Y, origin.Z)),
		Parent = arena,
	})
	self:_scoreboardSign(board)
	for _, x in { -22, 22 } do
		local spot = origin + Vector3.new(x, 0, -FENCE_Z - 4)
		MeshLibrary.Get("StruggleBanner", {
			CFrame = CFrame.lookAt(spot, Vector3.new(spot.X, spot.Y, origin.Z)),
			Parent = arena,
		})
	end

	-- South: the tram yard up on a brick embankment, so its trams show over the fence.
	local deck = 8
	Build.Part({
		Name = "Embankment",
		Size = Vector3.new(320, deck + 0.3, 26),
		CFrame = CFrame.new(origin + Vector3.new(0, (deck - 0.3) / 2, FENCE_Z + 20)),
		Color = Color3.fromRGB(150, 92, 72),
		Material = Enum.Material.Brick,
		Parent = arena,
	})
	for _, z in { FENCE_Z + 15, FENCE_Z + 25 } do
		for x = -140, 140, 40 do
			MeshLibrary.Get("StruggleTrack", {
				CFrame = CFrame.new(origin + Vector3.new(x, deck, z)) * CFrame.Angles(0, math.rad(90), 0),
				Parent = arena,
			})
		end
	end
	MeshLibrary.Get("StruggleTram", {
		CFrame = CFrame.new(origin + Vector3.new(-14, deck + 0.25, FENCE_Z + 15)) * CFrame.Angles(0, math.rad(90), 0),
		Parent = arena,
	})
	MeshLibrary.Get("StruggleTram", {
		Colors = { Body = Color3.fromRGB(80, 150, 120) },
		CFrame = CFrame.new(origin + Vector3.new(32, deck + 0.25, FENCE_Z + 25)) * CFrame.Angles(0, math.rad(-90), 0),
		Parent = arena,
	})

	-- East and west: benches for the crowd, banners on poles.
	for _, x in { -1, 1 } do
		for _, z in { -14, 0, 14 } do
			local spot = origin + Vector3.new(x * (FENCE_X + 4.5), 0, z)
			MeshLibrary.Get("StruggleBench", {
				CFrame = CFrame.lookAt(spot, Vector3.new(origin.X, spot.Y, spot.Z)),
				Parent = arena,
			})
		end
		for _, z in { -23, 23 } do
			local spot = origin + Vector3.new(x * (FENCE_X + 3), 0, z)
			MeshLibrary.Get("StruggleBanner", {
				Colors = { Cloth = if x < 0 then Color3.fromRGB(70, 130, 220) else Color3.fromRGB(230, 70, 70) },
				CFrame = CFrame.lookAt(spot, Vector3.new(origin.X, spot.Y, spot.Z)),
				Parent = arena,
			})
		end
	end

	-- Far off: trees against the sunset.
	for index = 0, 21 do
		local angle = (index + rng:NextNumber(-0.3, 0.3)) / 22 * math.pi * 2
		local distance = rng:NextNumber(85, 125)
		if math.sin(angle) * distance > FENCE_Z + 2 and math.sin(angle) * distance < FENCE_Z + 40 then
			continue -- not in the embankment
		end
		MeshLibrary.Get("Tree", {
			Scale = rng:NextNumber(1.6, 2.6),
			Colors = { Leaves = Color3.fromRGB(110, 140, 70):Lerp(Color3.fromRGB(160, 120, 60), rng:NextNumber()) },
			CFrame = CFrame.new(origin + Vector3.new(math.cos(angle) * distance, -0.3, math.sin(angle) * distance))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = arena,
		})
	end
end

-- The scoreboard's lit face: the top three, kept up to date.
function Struggle:_scoreboardSign(board: Model)
	local holder = Build.Decor({
		Name = "ScoreSign",
		Size = Vector3.new(SIGN.W, SIGN.H, 0.05) * BOARD_SCALE,
		CFrame = board:GetPivot() * CFrame.new(0, SIGN.Y * BOARD_SCALE, -SIGN.Z * BOARD_SCALE),
		Transparency = 1,
		Parent = board,
	})
	local label = Build.SurfaceText(holder, Enum.NormalId.Front, "STRUGGLE", {
		Name = "Board",
		PixelsPerStud = 24,
		TextColor3 = Color3.fromRGB(255, 236, 170),
		MaxDistance = 300,
	})
	label.TextXAlignment = Enum.TextXAlignment.Left
	self.sign = label
end

function Struggle:_refreshSign()
	local sign = self.sign
	if not sign then
		return
	end
	local list = {}
	for player, held in self.held do
		table.insert(list, { Player = player, Held = held, Hits = self.hits[player] or 0 })
	end
	table.sort(list, function(a, b)
		if a.Held ~= b.Held then
			return a.Held > b.Held
		end
		return a.Hits > b.Hits
	end)
	local lines = {}
	for index = 1, math.min(3, #list) do
		local entry = list[index]
		local slot = Rules.SLOTS[self.slots[entry.Player] or 1]
		local name = string.sub(entry.Player.DisplayName, 1, 12)
		table.insert(lines, `{index}. {slot.Glyph} {name}  {entry.Held}`)
	end
	sign.Text = table.concat(lines, "\n")
end

-- Shared state --------------------------------------------------------------------------------------

function Struggle:_shareHeld()
	local map = {}
	for player, held in self.held do
		map[tostring(player.UserId)] = { held, self.hits[player] or 0 }
	end
	self.context:SetSharedJSON("Held", map)
	self.heldDirty = false
	self:_refreshSign()
end

-- The full list of loose orbs, for a screen that starts late (and to correct any that missed an
-- event): every few seconds while it changes. The moments themselves go as Drop / Take events.
function Struggle:_shareOrbs()
	local list = {}
	for _, orb in self.orbs do
		table.insert(list, orb)
	end
	self.context:SetSharedJSON("Orbs", list)
	self.orbsDirty = false
	self.lastOrbShare = os.clock()
end

function Struggle:_setHeld(player: any, held: number)
	local ctx = self.context
	local old = self.held[player]
	if old == nil then
		return
	end
	self.held[player] = held
	ctx:AddScore(player, held - old)
	ctx:SetScoreText(player, if held == 1 then "1 orb" else `{held} orbs`)
	self.heldDirty = true
end

-- Orbs -------------------------------------------------------------------------------------------

-- Throws `count` orbs of `slot` from `from` to spots around it (inside the fence). After a hit they
-- spray `toward` the swinger and out to the sides, never the way the victim is thrown (review: the
-- victim flew along with their own orbs and caught them again); a leaver's spill goes all round.
function Struggle:_drop(slot: number, count: number, from: Vector3, toward: Vector3?)
	if count <= 0 then
		return
	end
	local ctx = self.context
	local now = ctx:Now()
	local origin = self.center
	local mx, mz = Rules.FIELD_X - Rules.ORB_MARGIN, Rules.FIELD_Z - Rules.ORB_MARGIN
	local fx = math.clamp(from.X - origin.X, -Rules.FIELD_X, Rules.FIELD_X)
	local fz = math.clamp(from.Z - origin.Z, -Rules.FIELD_Z, Rules.FIELD_Z)
	local aimed = toward ~= nil and toward.Magnitude > 1e-3
	local base = if aimed
		then math.atan2((toward :: Vector3).Z, (toward :: Vector3).X)
		else rng:NextNumber(0, math.pi * 2)
	local half = if aimed then 1.75 else math.pi -- each side of `toward` (about 100 degrees)
	local new = {}
	for index = 1, count do
		local angle = base - half + 2 * half * (index - 0.5) / count + rng:NextNumber(-0.2, 0.2)
		local distance = rng:NextNumber(4, 9)
		local x = math.clamp(fx + math.cos(angle) * distance, -mx, mx)
		local z = math.clamp(fz + math.sin(angle) * distance, -mz, mz)
		self.nextOrb += 1
		local orb = { self.nextOrb, slot, round2(x), round2(z), round2(fx), round2(fz), round2(now) }
		self.orbs[orb[1]] = orb
		table.insert(new, orb)
	end
	self.orbsDirty = true
	ctx:Fire(nil, "Drop", new)
end

-- Hands every landed orb to the nearest participant in reach.
function Struggle:_pickUps()
	local ctx = self.context
	if ctx:TimeIsUp() then
		return
	end
	local now = ctx:Now()
	local origin = self.center
	local roots = {}
	for _, player in ctx:GetAlivePlayers() do
		if self.held[player] == nil then
			continue
		end
		-- Nobody picks up while knocked down or in their safe moment after a hit (their own orbs
		-- are flying away from them then).
		if (self.safeUntil[player] or 0) > now then
			continue
		end
		local _, humanoid, root = ctx:GetCharacter(player)
		if root and humanoid and humanoid.Health > 0 then
			table.insert(roots, { Player = player, Position = root.Position - origin })
		end
	end
	local taken: { [any]: { number } } = {}
	for id, orb in self.orbs do
		if now < orb[7] + Rules.FLIGHT then
			continue
		end
		local best, bestDistance = nil, math.huge
		for _, entry in roots do
			local p = entry.Position
			local dx, dz = p.X - orb[3], p.Z - orb[4]
			local distance = math.sqrt(dx * dx + dz * dz)
			if distance <= Rules.PICK and distance < bestDistance and math.abs(p.Y) < 8 then
				best, bestDistance = entry.Player, distance
			end
		end
		if best then
			self.orbs[id] = nil
			taken[best] = taken[best] or {}
			table.insert(taken[best], id)
		end
	end
	for player, ids in taken do
		self:_setHeld(player, (self.held[player] or 0) + #ids)
		self.orbsDirty = true
		ctx:Fire(nil, "Take", player.UserId, ids)
	end
	if next(taken) then
		self:_checkAllOrbs()
	end
end

-- The match ends early once one player holds every orb in play.
function Struggle:_checkAllOrbs()
	if next(self.orbs) then
		return
	end
	local holders = 0
	local winner = nil
	for player, held in self.held do
		if held > 0 then
			holders += 1
			winner = player
		end
	end
	if holders == 1 and winner and #self.context:GetPlayers() >= 2 then
		self.context:Announce(`{winner.DisplayName} holds every orb!`, "success", 2.5)
		self.context:End("AllOrbs")
	end
end

-- Swings -----------------------------------------------------------------------------------------

-- When a press/release was made: what the client says (it sends api:Now()), kept within its ping.
function Struggle:_pressTime(player: any, claimed: any): number
	local now = self.context:Now()
	local lag = pingOf(player)
	if finite(claimed) then
		return math.clamp(claimed, now - lag / 2 - 0.1, now)
	end
	return now - lag / 2
end

function Struggle:_canStart(player: any, t: number): boolean
	local ctx = self.context
	if ctx:TimeIsUp() or self.held[player] == nil then
		return false
	end
	if (self.stunUntil[player] or 0) > ctx:Now() then
		return false
	end
	return t >= (self.readyAt[player] or 0) - 0.05
end

-- Tells a player's screen its press didn't start a swing, so it stops drawing one (and when it
-- may try again).
function Struggle:_refuse(player: any)
	if not BotRegistry.IsBot(player) then
		local ready = math.max(self.readyAt[player] or 0, self.stunUntil[player] or 0)
		self.context:Fire(player, "Refused", round2(ready))
	end
end

function Struggle:_charge(player: any, claimed: any)
	local ctx = self.context
	if self.swings[player] then
		return
	end
	local _, _, root = ctx:GetCharacter(player)
	if not root then
		self:_refuse(player)
		return
	end
	local t = self:_pressTime(player, claimed)
	if not self:_canStart(player, t) then
		self:_refuse(player)
		return
	end
	local swing: Swing = { Start = t, Charged = false, Cancelled = false }
	self.swings[player] = swing
	ctx:SetWalkSpeed(player, CHARGE_SPEED)
	ctx:Fire(nil, "Wind", player.UserId, round2(t))
	-- Held too long: it goes by itself.
	ctx:Delay(math.max(0, t + Rules.MAX_HOLD - ctx:Now()), function()
		if self.swings[player] == swing and not swing.StrikeAt and not swing.Cancelled then
			self:_release(player, swing, t + Rules.MAX_HOLD)
		end
	end)
end

function Struggle:_swing(player: any, claimed: any)
	local current = self.swings[player]
	if current and current.StrikeAt then
		return
	end
	local t = self:_pressTime(player, claimed)
	local swing: Swing
	if current then
		swing = current
	else
		-- No live charge: a tap from the release (see the top).
		local _, _, root = self.context:GetCharacter(player)
		if not root or not self:_canStart(player, t) then
			self:_refuse(player)
			return
		end
		swing = { Start = t, Charged = false, Cancelled = false }
		self.swings[player] = swing
	end
	self:_release(player, swing, math.max(t, swing.Start))
end

function Struggle:_release(player: any, swing: Swing, t: number)
	local ctx = self.context
	swing.Charged = t - swing.Start >= Rules.CHARGE - 0.03
	local strikeAt = math.max(t, swing.Start + Rules.WINDUP)
	swing.StrikeAt = strikeAt
	local ready = strikeAt + (if swing.Charged then Rules.RECOVER_CHARGED else Rules.RECOVER)
	self.readyAt[player] = ready
	if not BotRegistry.IsBot(player) then
		ctx:SetPlayerShared(player, "ReadyAt", round2(ready))
	end
	ctx:SetWalkSpeed(player, ctx.WalkSpeed)
	ctx:Fire(nil, "Strike", player.UserId, round2(swing.Start), round2(strikeAt), swing.Charged)
	-- Judged once the server has the attacker where their screen had them at the strike.
	local judgeAt = strikeAt + pingOf(player) / 2
	local wait = math.max(0, judgeAt - ctx:Now())
	ctx:HoldEnd(wait + 0.05)
	ctx:Delay(wait, function()
		if self.swings[player] == swing then
			self.swings[player] = nil
		end
		if not swing.Cancelled then
			self:_judge(player, swing)
		end
	end)
end

-- Where a participant was at server time t (the nearest recorded sample).
function Struggle:_positionAt(player: any, t: number): Vector3?
	local samples = self.history[player]
	if not samples then
		return nil
	end
	local best, bestGap = nil, math.huge
	for _, sample in samples do
		local gap = math.abs(sample[1] - t)
		if gap < bestGap then
			best, bestGap = sample[2], gap
		end
	end
	return best
end

function Struggle:_judge(attacker: any, swing: Swing)
	local ctx = self.context
	local strikeAt = swing.StrikeAt :: number
	if not ctx:InTime(strikeAt) or not ctx:IsAlive(attacker) or self.held[attacker] == nil then
		return
	end
	local _, _, root = ctx:GetCharacter(attacker)
	if not root then
		return
	end
	local from = root.Position
	local look = root.CFrame.LookVector
	local rewind = math.min(pingOf(attacker) / 2 + (if BotRegistry.IsBot(attacker) then 0 else INTERP), REWIND_CAP)
	local victims = {}
	for _, victim in ctx:GetAlivePlayers() do
		if victim == attacker or self.held[victim] == nil then
			continue
		end
		if (self.safeUntil[victim] or 0) > strikeAt then
			continue
		end
		local _, _, victimRoot = ctx:GetCharacter(victim)
		if not victimRoot then
			continue
		end
		-- Where the attacker saw them, only (someone who walked in after the bat passed isn't hit).
		local seen = if rewind > 0 then self:_positionAt(victim, strikeAt - rewind) else nil
		if Rules.Reaches(from, look, seen or victimRoot.Position, swing.Charged) then
			table.insert(victims, { Player = victim, Position = victimRoot.Position })
		end
	end
	for _, entry in victims do
		self:_hit(attacker, entry.Player, entry.Position, from, look, swing.Charged)
	end
end

function Struggle:_hit(attacker: any, victim: any, at: Vector3, from: Vector3, look: Vector3, charged: boolean)
	local ctx = self.context
	local now = ctx:Now()
	local count = Rules.Knocked(self.held[victim] or 0, charged)
	local away = Vector3.new(at.X - from.X, 0, at.Z - from.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(look.X, 0, look.Z)
	end
	away = if away.Magnitude > 1e-3 then away.Unit else Vector3.xAxis
	self.safeUntil[victim] = now + Rules.SAFE
	local stun = if charged then 0.8 else 0.4
	self.stunUntil[victim] = now + stun
	-- A charge (or a strike still to come) is knocked out of their hands.
	local theirs = self.swings[victim]
	if theirs and (not theirs.StrikeAt or theirs.StrikeAt > now) then
		theirs.Cancelled = true
		self.swings[victim] = nil
		ctx:SetWalkSpeed(victim, ctx.WalkSpeed)
	end
	self.hits[attacker] = (self.hits[attacker] or 0) + 1
	self.heldDirty = true
	if count > 0 then
		self:_setHeld(victim, (self.held[victim] or 0) - count)
		self:_drop(self.slots[victim] or 1, count, at, -away)
	end
	local speed = if charged then 62 else 36
	-- Someone already in the air gets no extra lift (a jump plus a knock cleared the fence).
	local _, _, victimRoot = ctx:GetCharacter(victim)
	local airborne = victimRoot ~= nil
		and (victimRoot.Position.Y - self.center.Y > FALL_SAFE or math.abs(victimRoot.AssemblyLinearVelocity.Y) > 2)
	local lift = if airborne then 0 elseif charged then 30 else 20
	ctx:Knockback(victim, away * speed + Vector3.new(0, lift, 0), stun)
	ctx:Fire(
		nil,
		"Hit",
		attacker.UserId,
		victim.UserId,
		count,
		charged,
		round2(now + Rules.SAFE),
		{ round2(at.X), round2(at.Y), round2(at.Z) },
		round2(now + stun)
	)
end

-- Players leaving: their orbs spill where they stood ------------------------------------------------

function Struggle:_onLeave(player: any)
	local held = self.held[player]
	if held == nil then
		return
	end
	local samples = self.history[player]
	local last = samples and samples[#samples]
	local at = if last then last[2] else self.center
	self.held[player] = nil
	self.hits[player] = nil
	self.swings[player] = nil
	self.history[player] = nil
	if held > 0 then
		self:_drop(self.slots[player] or 1, held, at, nil)
	end
	local roster = {}
	for _, entry in self.roster do
		if entry[1] ~= player.UserId then
			table.insert(roster, entry)
		end
	end
	self.roster = roster
	self.context:SetSharedJSON("Roster", roster)
	self.heldDirty = true
end

-- Puts every character in the round in the mode's group (GROUP; respawns too).
function Struggle:_groupCharacters()
	local ctx = self.context
	if not self.groupReady then
		return
	end
	for _, player in ctx:GetPlayers() do
		local character = ctx:GetCharacter(player)
		if not character or self.grouped[player] == character then
			continue
		end
		self.grouped[player] = character
		for _, item in character:GetDescendants() do
			if item:IsA("BasePart") then
				item.CollisionGroup = GROUP
			end
		end
		ctx:Track(character.DescendantAdded:Connect(function(item)
			if item:IsA("BasePart") then
				item.CollisionGroup = GROUP
			end
		end))
	end
end

-- A safety net: anyone who got outside the fence (a knock over it, a glitch) is put back inside,
-- where they were nearest, players and bots alike.
function Struggle:_keepInside()
	local ctx = self.context
	local origin = self.center
	for _, player in ctx:GetAlivePlayers() do
		local character, _, root = ctx:GetCharacter(player)
		if not character or not root or root.Anchored then
			continue
		end
		local offset = root.Position - origin
		if math.abs(offset.X) <= FENCE_X + 1 and math.abs(offset.Z) <= FENCE_Z + 1 then
			continue
		end
		local x = math.clamp(offset.X, -Rules.FIELD_X + 2, Rules.FIELD_X - 2)
		local z = math.clamp(offset.Z, -Rules.FIELD_Z + 2, Rules.FIELD_Z - 2)
		local spot = origin + Vector3.new(x, 3.5, z)
		character:PivotTo(CFrame.lookAt(spot, Vector3.new(origin.X, spot.Y, origin.Z)))
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- A safety net under the bots: nothing flings one faster than its hardest knock.
function Struggle:_limitBots()
	local ctx = self.context
	for _, player in ctx:GetAlivePlayers() do
		if not BotRegistry.IsBot(player) then
			continue
		end
		local _, _, root = ctx:GetCharacter(player)
		if not root or root.Anchored then
			continue
		end
		local velocity = root.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		if velocity.Y > BOT_MAX_UP or flat.Magnitude > BOT_MAX_FLAT then
			if flat.Magnitude > BOT_MAX_FLAT then
				flat = flat.Unit * BOT_MAX_FLAT
			end
			root.AssemblyLinearVelocity = Vector3.new(flat.X, math.min(velocity.Y, BOT_MAX_UP), flat.Z)
		end
	end
end

function Struggle:Start()
	local ctx = self.context
	self.groupReady = setUpGroup()
	self:_groupCharacters()

	ctx:OnAction("Charge", function(player, claimed)
		self:_charge(player, claimed)
	end, { Interval = 0.1 })
	ctx:OnAction("Swing", function(player, claimed)
		self:_swing(player, claimed)
	end, { Interval = 0.1 })

	-- Positions 20 times a second, for judging what an attacker saw.
	local since = 0
	ctx:Heartbeat(function(dt)
		since += dt
		if since < 0.05 then
			return
		end
		since = 0
		local now = ctx:Now()
		for _, player in ctx:GetAlivePlayers() do
			local _, _, root = ctx:GetCharacter(player)
			if not root or self.held[player] == nil then
				continue
			end
			local samples = self.history[player]
			if not samples then
				samples = {}
				self.history[player] = samples
			end
			table.insert(samples, { now, root.Position })
			if #samples > HISTORY then
				table.remove(samples, 1)
			end
		end
	end)

	ctx:Loop(function(): number?
		self:_groupCharacters()
		self:_keepInside()
		self:_pickUps()
		self:_limitBots()
		if self.heldDirty then
			self:_shareHeld()
		end
		if self.orbsDirty and os.clock() - self.lastOrbShare >= ORB_SNAPSHOT then
			self:_shareOrbs()
		end
		return 0.1
	end)

	-- The status line says what's lying around (the HUD shows the leader).
	ctx:Loop(function(): number?
		local loose = 0
		for _ in self.orbs do
			loose += 1
		end
		ctx:SetStatus(
			if loose == 0
				then "Knock their orbs loose!"
				elseif loose == 1 then "1 orb on the ground - grab it!"
				else `{loose} orbs on the ground - grab them!`
		)
		return 0.5
	end)
end

function Struggle:GetResults()
	local ctx = self.context
	local entries = {}
	for player in ctx.Participants do
		if not player.Parent then
			continue
		end
		local held = self.held[player] or 0
		local hits = self.hits[player] or 0
		local orbText = if held == 1 then "1 orb" else `{held} orbs`
		local hitText = if hits == 1 then "1 hit" else `{hits} hits`
		table.insert(entries, {
			Player = player,
			Rank = held * 1000 + math.min(hits, 999),
			ScoreText = `{orbText} • {hitText}`,
			BestScore = held,
		})
	end
	return { Entries = entries }
end

return Struggle

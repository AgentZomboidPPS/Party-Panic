-- Capy Go Boom (Versus, 75s, 2-12 players, free for all). Owner: "Can you take Capy to boom. Make it into a
-- mini game for party panic?" Brought over from the owner's own game CAPY GO BOOM, where capybaras eat
-- snacks to grow huge and blast each other with snack cannons, and a popped capy spills food. Here it is a
-- 75 second round: everyone starts as a 20 KG capy on a hedged lawn full of snacks. Walk over snacks to
-- eat them and grow; BOOM fires your snack cannon, and a shell that hits pops its target, who spills a
-- fifth of their weight as snacks for anyone to eat (a quarter for the leader, so the front can be
-- caught). Nobody is ever out. The biggest capy at the buzzer wins (ties: most pops).
--
-- Two moments shake it up, like the airdrops and the Mega Snack in the original: two SNACK DROPS (a beam
-- of light 2.5 seconds ahead, then a golden apple and a dozen snacks fall there) and, for the last 12
-- seconds, a FEAST where every snack on the lawn counts double (a spill never does: pops only move weight
-- around) and more snacks fall.
--
-- How it works (the server owns everything; Shared/Logic/CapyGoBoom has the numbers and the hit tests):
--   * Weight (mass) is the score. Size, eating reach, hit circle and speed all follow it (Rules.ScaleOf):
--     the client draws a capybara on everyone's character, growing smoothly.
--   * Snacks are the server's records ([id, kind, x, z, fromX, fromZ, t0, style]: spilled in an arc,
--     dropped from the sky, or sprouted where they lie). The nearest capy within reach eats a landed
--     snack, checked ten times a second for players and bots alike. A popped capy can't eat its own
--     spill for a moment. "Spawn" / "Eat" events carry each moment; the full list ("Snacks") is shared
--     every few seconds while it changes, so a client that starts late sees them all.
--   * BOOM ("Boom" with when it was pressed on the player's screen and, on PC, where the mouse
--     pointed): the server takes the shooter's position and the direction (the way they face or the
--     mouse, bent toward a rival within a small cone: aim assist on phones), and flies the shell on its
--     own clock. Clients draw it from the "Shot" cue on the same clock. A shell is judged against where
--     the shooter SAW each rival (positions recorded 20 times a second, rewound by the shooter's one-way
--     trip plus Roblox's interpolation, capped), and is stopped by the standing stones and the hedge.
--     A jump high enough clears a shell (it flies at the shooter's height).
--   * A pop knocks the victim back, staggers them (they can't fire for a moment), makes them blink and
--     safe for 1.5 s (no juggling), and throws the spill toward the shooter.
--   * Bots fire through ctx:BotAction exactly like players, are thrown by ctx:Knockback and eat by the
--     same distance check: no hazard is client-only.
--   * Nobody's character collides with anyone else's (one mode-only group): a pop decides every
--     contact, and a body shoving a server-moved bot could fling it.
--   * Nothing solid where nothing is drawn (owner: "Theres invisible stuff you can jump on and hang on
--     in several games"): only the lawn, the hedge (11 studs tall, a jump reaches 7.2) and the standing
--     stones collide, each its own drawn shape. Anyone who still ends up outside is put back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Rules = require(ReplicatedStorage.Shared.Logic.CapyGoBoom)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Telemetry = require(script.Parent.Parent.Services.Telemetry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local CapyGoBoom = MiniGame.Define("CapyGoBoom", { Results = "Score" })
CapyGoBoom.Rules = Rules -- for the bot brain and the round harness's test bot

local WALL_H = 11
local MAX_LAG = 0.4 -- the longest round trip we allow for
local REWIND_CAP = 0.3 -- the furthest back a victim is judged
local INTERP = 0.1 -- Roblox draws other characters about this far behind
local HISTORY = 16 -- position samples kept (every 0.05 s)
local GROUP = "PP_CapyGoBoom" -- every participant's character (see setUpGroup)
local SNACK_SNAPSHOT = 3 -- seconds between full lists of snacks (Spawn / Eat events carry the moments)
local MASS_SHARE = 0.25 -- seconds between the weights being shared
local BOT_MAX_FLAT, BOT_MAX_UP = 80, 45 -- a bot never goes faster than its hardest knock

local rng = Random.new()

local function round2(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- How far a character's root is above the ground standing (an avatar with its own proportions differs from
-- the default 3).
local function standHeight(humanoid: Humanoid?, root: BasePart): number
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 and humanoid.HipHeight > 0.5 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 3
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function upright(center: Vector3): CFrame
	return CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
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

-- Everyone in the round passes through everyone else (one mode-only group that doesn't collide with
-- itself; it still collides with the lawn, the hedge and the stones). Characters made later (a
-- respawn) are put in it too (CapyGoBoom:_groupCharacters, every 0.1 s); the lobby's own groups come
-- back with the fresh characters everyone gets after the round.
local function setUpGroup(): boolean
	return pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(GROUP) then
			PhysicsService:RegisterCollisionGroup(GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	end)
end

function CapyGoBoom:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 30
	local origin = ctx.Origin.Position
	local count = #ctx:GetPlayers()
	self.center = origin
	self.radius = Rules.ArenaRadius(count)
	self.mass = {} :: { [any]: number }
	self.pops = {} :: { [any]: number }
	self.shots = {} :: { [any]: number } -- BOOMs fired (the checks compare bots' accuracy with players')
	self.slots = {} :: { [any]: number }
	self.readyAt = {} :: { [any]: number }
	self.safeUntil = {} :: { [any]: number }
	self.stunUntil = {} :: { [any]: number }
	self.speedOf = {} :: { [any]: number }
	self.history = {} :: { [any]: { { any } } }
	self.snacks = {} :: { [number]: { number } }
	self.reserved = {} :: { [number]: { Player: any, Until: number } }
	self.nextSnack = 0
	self.snacksDirty = true
	self.lastSnackShare = -math.huge
	self.shells = {} :: { { [string]: any } }
	self.nextShell = 0
	self.rocks = {} :: { { X: number, Z: number } }
	self.feast = false
	self.dropWarned = {} :: { [number]: boolean }
	self.dropSpot = nil :: Vector3?
	self.failed = {} :: { [string]: boolean }
	self.refillTokens = 0
	self.lastRefill = os.clock()
	self.massDirty = true
	self.lastMassShare = -math.huge
	self.grouped = {} :: { [any]: Model }
	self.groupReady = false

	-- Slots: a colour each, in a shuffled order.
	local players = ctx:GetPlayers()
	for index = #players, 2, -1 do
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local roster = {}
	for index, player in players do
		local slot = (index - 1) % #Rules.COLORS + 1
		self.slots[player] = slot
		self.mass[player] = Rules.START_MASS
		self.pops[player] = 0
		self.shots[player] = 0
		ctx:AddScore(player, Rules.START_MASS)
		ctx:SetScoreText(player, `{Rules.START_MASS} {Rules.UNIT}`)
		table.insert(roster, { player.UserId, slot })
	end
	self.roster = roster
	ctx:SetSharedJSON("Roster", roster)
	ctx:SetSharedJSON("Field", { Center = { origin.X, origin.Y, origin.Z }, Radius = self.radius })

	-- Everyone on a ring facing the middle.
	local ringRadius = self.radius * 0.62
	local points = Build.Ring(origin + Vector3.new(0, 0.5, 0), ringRadius, math.max(count, 1))
	self:_buildArena(points)
	-- (the hooks first: placing everyone can take seconds, and someone who leaves or can't be placed in that
	-- time must not stay behind as a frozen entry)
	ctx.Hooks.Respawn = function(_player)
		local x, z = self:_spot(0.8)
		local spot = origin + Vector3.new(x, 0.5, z)
		return CFrame.lookAt(spot, Vector3.new(origin.X, spot.Y, origin.Z))
	end
	ctx.Hooks.CharacterReady = function(player)
		if ctx:IsRunning() then
			self.speedOf[player] = nil
			self:_applySpeed(player)
		end
	end
	ctx.Hooks.PlayerLeft = function(player)
		self:_onLeave(player)
	end
	ctx:SpawnAll(points, true)

	for _, kind in Rules.SNACKS do
		for _, prop in kind.Props do
			ctx:ShareTemplate(prop, MeshLibrary.Get(prop))
		end
	end
	ctx:ShareTemplate("CapyBoomCapy", MeshLibrary.Get("CapyBoomCapy"))
	ctx:ShareTemplate("CapyBoomShell", MeshLibrary.Get("CapyBoomShell"))

	-- The lawn starts with snacks lying about.
	local target = Rules.TargetSnacks(count)
	for _ = 1, target do
		local x, z = self:_spot(0.93)
		self:_addSnack(self:_pickKind(), x, z, x, z, Rules.SPROUT, nil, true)
	end
	self:_shareSnacks()
	self:_shareMass()
	ctx:SetStatus("Eat snacks to grow - BOOM rivals!")
end

-- The arena -----------------------------------------------------------------------------------------

-- A lawn inside a hedge, a hot spring in the middle, standing stones to hide behind, a sign and a ring
-- of trees and hills outside.
function CapyGoBoom:_buildArena(spawns: { CFrame })
	local ctx = self.context
	local origin = self.center
	local arena = ctx.Arena
	local R = self.radius
	local full = R + Rules.WALL_THICK

	-- Grass out to the horizon, a little below the lawn.
	Build.Part({
		Name = "Horizon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 900, 900),
		CFrame = upright(origin - Vector3.new(0, 2.4, 0)),
		Color = Color3.fromRGB(120, 190, 92),
		Material = Enum.Material.Grass,
		Parent = arena,
	})
	Build.Part({
		Name = "Lawn",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, full * 2, full * 2),
		CFrame = upright(origin - Vector3.new(0, 1, 0)),
		Color = Color3.fromRGB(104, 192, 84),
		Material = Enum.Material.Grass,
		Parent = arena,
	})
	-- Mowing stripes: rings a hair above the lawn, each a little higher than the one outside it, so
	-- none of them are coplanar.
	for index = 1, 3 do
		local radius = full * (1 - 0.22 * index)
		Build.Decor({
			Name = "Mow",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.06, radius * 2, radius * 2),
			CFrame = upright(origin + Vector3.new(0, 0.04 * index, 0)),
			Color = if index % 2 == 1 then Color3.fromRGB(120, 206, 98) else Color3.fromRGB(104, 192, 84),
			Material = Enum.Material.Grass,
			Parent = arena,
		})
	end

	-- The hot spring: water and a ring of low stones, steaming.
	local spring = Build.Decor({
		Name = "Spring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 15, 15),
		CFrame = upright(origin + Vector3.new(0, 0.18, 0)),
		Color = Color3.fromRGB(90, 200, 230),
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		Parent = arena,
	})
	for index = 0, 13 do
		local angle = index / 14 * math.pi * 2
		Build.Decor({
			Name = "SpringStone",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.2, 1.5, 2.2),
			CFrame = CFrame.new(origin + Vector3.new(math.cos(angle) * 8, 0.2, math.sin(angle) * 8)),
			Color = Color3.fromRGB(150, 146, 152),
			Material = Enum.Material.Slate,
			Parent = arena,
		})
	end
	local steam = Instance.new("ParticleEmitter")
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Color = ColorSequence.new(Color3.fromRGB(235, 245, 250))
	steam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	steam.Size = NumberSequence.new(3, 7)
	steam.Lifetime = NumberRange.new(2.5, 4)
	steam.Speed = NumberRange.new(2, 4)
	steam.SpreadAngle = Vector2.new(15, 15)
	steam.EmissionDirection = Enum.NormalId.Right -- the cylinder's +X faces up
	steam.Rate = 6
	steam.Parent = spring
	game:GetService("CollectionService"):AddTag(steam, "PP_Ambient")

	-- The hedge: boxes round the lawn (collision is the drawn box), with leafy bumps and flowers.
	local segments = math.ceil(math.pi * 2 * (R + Rules.WALL_THICK / 2) / 8)
	local wallRadius = R + Rules.WALL_THICK / 2
	local flowerColors = {
		Color3.fromRGB(255, 130, 190),
		Color3.fromRGB(255, 220, 90),
		Color3.fromRGB(180, 140, 255),
		Color3.fromRGB(255, 255, 255),
	}
	for index = 0, segments - 1 do
		local angle = index / segments * math.pi * 2
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local length = math.pi * 2 * wallRadius / segments + 0.8
		Build.Part({
			Name = "Hedge",
			Size = Vector3.new(Rules.WALL_THICK, WALL_H, length),
			CFrame = CFrame.new(origin + radial * wallRadius + Vector3.new(0, WALL_H / 2, 0))
				* CFrame.Angles(0, -angle, 0),
			Color = Color3.fromRGB(58, 146, 70),
			Material = Enum.Material.Grass,
			Parent = arena,
		})
		Build.Decor({
			Name = "HedgeTop",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(5.4, 3.6, length + 0.6),
			CFrame = CFrame.new(origin + radial * wallRadius + Vector3.new(0, WALL_H, 0)) * CFrame.Angles(0, -angle, 0),
			Color = Color3.fromRGB(78, 170, 82),
			Material = Enum.Material.Grass,
			Parent = arena,
		})
		if index % 2 == 0 then
			for _ = 1, 2 do
				Build.Decor({
					Name = "Flower",
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * 1.1,
					CFrame = CFrame.new(
						origin
							+ radial * (R - 0.15)
							+ Vector3.new(0, rng:NextNumber(2.5, WALL_H - 0.5), 0)
							+ Vector3.new(-radial.Z, 0, radial.X) * rng:NextNumber(-3, 3)
					),
					Color = flowerColors[rng:NextInteger(1, #flowerColors)],
					Parent = arena,
				})
			end
		end
	end

	-- A sign behind the hedge on the north side.
	local signAt = origin + Vector3.new(0, 0, -(full + 16))
	for _, x in { -17, 17 } do
		Build.Decor({
			Name = "SignPost",
			Size = Vector3.new(1.6, 18, 1.6),
			CFrame = CFrame.new(signAt + Vector3.new(x, 9, 0.8)),
			Color = Color3.fromRGB(120, 82, 50),
			Material = Enum.Material.Wood,
			Parent = arena,
		})
	end
	local board = Build.Decor({
		Name = "SignBoard",
		Size = Vector3.new(46, 12, 1.4),
		CFrame = CFrame.lookAt(signAt + Vector3.new(0, 16, 0), Vector3.new(origin.X, origin.Y + 16, origin.Z)),
		Color = Color3.fromRGB(176, 122, 72),
		Material = Enum.Material.Wood,
		Parent = arena,
	})
	local text = Build.SurfaceText(board, Enum.NormalId.Front, "CAPY GO BOOM!", {
		Name = "Title",
		PixelsPerStud = 24,
		TextColor3 = Color3.fromRGB(255, 244, 214),
		MaxDistance = 300,
	})
	text.TextScaled = true

	-- Standing stones to hide behind (shells stop at them), away from the spawn ring and the spring.
	local wanted = 4 + math.floor(#self.context:GetPlayers() / 2)
	local tries = 0
	while #self.rocks < wanted and tries < 200 do
		tries += 1
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(0.28, 0.84) * R
		local x, z = math.cos(angle) * distance, math.sin(angle) * distance
		local ok = math.sqrt(x * x + z * z) > 14
		if ok then
			for _, rock in self.rocks do
				if (rock.X - x) ^ 2 + (rock.Z - z) ^ 2 < 18 ^ 2 then
					ok = false
					break
				end
			end
		end
		if ok then
			for _, spawn in spawns do
				local p = spawn.Position - origin
				if (p.X - x) ^ 2 + (p.Z - z) ^ 2 < 10 ^ 2 then
					ok = false
					break
				end
			end
		end
		if ok then
			table.insert(self.rocks, { X = x, Z = z })
			MeshLibrary.Get("CapyBoomRock", {
				CFrame = CFrame.new(origin + Vector3.new(x, 0, z))
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = arena,
			})
		end
	end

	-- Outside: bushes by the hedge, a ring of trees, soft hills on the horizon.
	local leafColors = {
		Color3.fromRGB(80, 190, 90),
		Color3.fromRGB(110, 200, 80),
		Color3.fromRGB(70, 165, 95),
		Color3.fromRGB(140, 205, 85),
	}
	for index = 0, 15 do
		local angle = (index + rng:NextNumber(-0.35, 0.35)) / 16 * math.pi * 2
		local distance = full + rng:NextNumber(3, 8)
		MeshLibrary.Get("Bush", {
			Scale = rng:NextNumber(1.2, 2),
			Colors = { Flowers = flowerColors[rng:NextInteger(1, #flowerColors)] },
			CFrame = CFrame.new(origin + Vector3.new(math.cos(angle) * distance, -0.3, math.sin(angle) * distance))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = arena,
		})
	end
	for index = 0, 27 do
		local angle = (index + rng:NextNumber(-0.35, 0.35)) / 28 * math.pi * 2
		local distance = full + rng:NextNumber(14, 50)
		if math.abs(math.cos(angle) * distance) < 30 and math.sin(angle) < 0 then
			continue -- not behind the sign
		end
		MeshLibrary.Get("Tree", {
			Scale = rng:NextNumber(1.5, 2.7),
			Colors = { Leaves = leafColors[rng:NextInteger(1, #leafColors)] },
			CFrame = CFrame.new(origin + Vector3.new(math.cos(angle) * distance, -0.3, math.sin(angle) * distance))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = arena,
		})
	end
	for index = 0, 9 do
		local angle = (index + rng:NextNumber(-0.3, 0.3)) / 10 * math.pi * 2
		local distance = rng:NextNumber(190, 260)
		local size = Vector3.new(rng:NextNumber(150, 230), rng:NextNumber(50, 90), rng:NextNumber(110, 160))
		local hill = Build.Decor({
			Name = "Hill",
			Size = size,
			CFrame = CFrame.new(
				origin + Vector3.new(math.cos(angle) * distance, -size.Y * 0.2, math.sin(angle) * distance)
			) * CFrame.Angles(0, -angle + math.pi / 2, 0),
			Color = Color3.fromRGB(96, 176, 86):Lerp(Color3.fromRGB(70, 140, 90), rng:NextNumber(0, 1)),
			Material = Enum.Material.Grass,
			Parent = arena,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = hill
	end
end

-- A random spot inside the hedge as an offset from the middle (a fraction of the radius), clear of the
-- stones.
function CapyGoBoom:_spot(fraction: number): (number, number)
	local limit = (self.radius - 2) * fraction
	local x, z = 0, 0
	for _ = 1, 12 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = limit * math.sqrt(rng:NextNumber())
		x, z = math.cos(angle) * distance, math.sin(angle) * distance
		if self:_clearOfRocks(x, z, Rules.ROCK_R + 2) then
			break
		end
	end
	return x, z
end

function CapyGoBoom:_clearOfRocks(x: number, z: number, margin: number): boolean
	for _, rock in self.rocks do
		if (rock.X - x) ^ 2 + (rock.Z - z) ^ 2 < margin * margin then
			return false
		end
	end
	return true
end

-- Shared state -----------------------------------------------------------------------------------

function CapyGoBoom:_shareMass()
	local map = {}
	for player, mass in self.mass do
		map[tostring(player.UserId)] = { mass, self.pops[player] or 0 }
	end
	self.context:SetSharedJSON("Mass", map)
	self.massDirty = false
	self.lastMassShare = os.clock()
end

-- The full list of snacks, for a screen that starts late (and to correct any that missed an event):
-- every few seconds while it changes. The moments themselves go as Spawn / Eat events.
function CapyGoBoom:_shareSnacks()
	local list = {}
	for _, snack in self.snacks do
		table.insert(list, snack)
	end
	self.context:SetSharedJSON("Snacks", list)
	self.snacksDirty = false
	self.lastSnackShare = os.clock()
end

-- The player in front, or nil if the top is tied.
function CapyGoBoom:_leader(): any
	local best, bestMass, tie = nil, -1, false
	for player, mass in self.mass do
		if mass > bestMass then
			best, bestMass, tie = player, mass, false
		elseif mass == bestMass then
			tie = true
		end
	end
	return if tie then nil else best
end

function CapyGoBoom:_applySpeed(player: any)
	local mass = self.mass[player]
	if mass == nil then
		return
	end
	local factor = Rules.SpeedFactor(Rules.ScaleOf(mass))
	if self.speedOf[player] and math.abs(self.speedOf[player] - factor) < 0.01 then
		return
	end
	self.speedOf[player] = factor
	self.context:SetWalkSpeed(player, self.context.WalkSpeed * factor)
end

function CapyGoBoom:_setMass(player: any, mass: number)
	local old = self.mass[player]
	if old == nil then
		return
	end
	self.mass[player] = mass
	self.context:AddScore(player, mass - old)
	self.context:SetScoreText(player, `{mass} {Rules.UNIT}`)
	self.massDirty = true
	self:_applySpeed(player)
end

-- Snacks ---------------------------------------------------------------------------------------------

function CapyGoBoom:_pickKind(): number
	local total = 0
	for _, kind in Rules.SNACKS do
		total += kind.Weight
	end
	local roll = rng:NextNumber(0, total)
	for index, kind in Rules.SNACKS do
		roll -= kind.Weight
		if roll <= 0 and kind.Weight > 0 then
			return index
		end
	end
	return Rules.SMALL
end

-- Adds a snack at an offset from the middle, `style` says how it arrives (`settled`: it has been lying
-- there since before the round). Returns its record.
function CapyGoBoom:_addSnack(
	kind: number,
	x: number,
	z: number,
	fx: number,
	fz: number,
	style: number,
	reserve: any,
	settled: boolean?
)
	local ctx = self.context
	-- Not inside a stone or the hedge.
	local limit = self.radius - 2
	local distance = math.sqrt(x * x + z * z)
	if distance > limit then
		x, z = x / distance * limit, z / distance * limit
	end
	for _, rock in self.rocks do
		local dx, dz = x - rock.X, z - rock.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < Rules.ROCK_R + 1.4 then
			local nx, nz = if d > 1e-3 then dx / d else 1, if d > 1e-3 then dz / d else 0
			x, z = rock.X + nx * (Rules.ROCK_R + 1.6), rock.Z + nz * (Rules.ROCK_R + 1.6)
		end
	end
	self.nextSnack += 1
	local now = ctx:Now()
	local record = {
		self.nextSnack,
		kind,
		round2(x),
		round2(z),
		round2(fx),
		round2(fz),
		round2(if settled then now - 2 else now),
		style,
	}
	self.snacks[record[1]] = record
	if reserve then
		self.reserved[record[1]] = { Player = reserve, Until = now + Rules.OWN_SPILL }
	end
	self.snacksDirty = true
	return record
end

-- Throws snacks worth `amount` from `at` (a world position) to spots around it, toward `toward` and
-- out to the sides (never the way a popped capy is thrown), or all round if there is no direction.
function CapyGoBoom:_spill(amount: number, at: Vector3, toward: Vector3?, reserve: any, maxPieces: number?)
	if amount <= 0 then
		return
	end
	local origin = self.center
	local limit = self.radius - 2
	local fx, fz = at.X - origin.X, at.Z - origin.Z
	local fd = math.sqrt(fx * fx + fz * fz)
	if fd > limit then
		fx, fz = fx / fd * limit, fz / fd * limit
	end
	local aimed = toward ~= nil and toward.Magnitude > 1e-3
	local base = if aimed
		then math.atan2((toward :: Vector3).Z, (toward :: Vector3).X)
		else rng:NextNumber(0, math.pi * 2)
	local half = if aimed then 1.75 else math.pi -- each side of `toward` (about 100 degrees)
	local pieces = Rules.Pieces(amount, maxPieces)
	local made = {}
	for index, kind in pieces do
		local angle = base - half + 2 * half * (index - 0.5) / #pieces + rng:NextNumber(-0.2, 0.2)
		local distance = rng:NextNumber(4, 9)
		table.insert(
			made,
			self:_addSnack(
				kind,
				fx + math.cos(angle) * distance,
				fz + math.sin(angle) * distance,
				fx,
				fz,
				Rules.ARC,
				reserve
			)
		)
	end
	self.context:Fire(nil, "Spawn", made)
end

-- Hands every landed snack to the nearest capy in reach.
function CapyGoBoom:_pickUps()
	local ctx = self.context
	if ctx:TimeIsUp() then
		return
	end
	local now = ctx:Now()
	local origin = self.center
	local eaters = {}
	for _, player in ctx:GetAlivePlayers() do
		if self.mass[player] == nil then
			continue
		end
		local _, humanoid, root = ctx:GetCharacter(player)
		if root and humanoid and humanoid.Health > 0 then
			table.insert(eaters, {
				Player = player,
				X = root.Position.X - origin.X,
				Z = root.Position.Z - origin.Z,
				Y = root.Position.Y - origin.Y,
				Reach = Rules.EatReach(Rules.ScaleOf(self.mass[player])),
			})
		end
	end
	local taken: { [any]: { { number } } } = {}
	for id, snack in self.snacks do
		if not Rules.Landed(snack, now) then
			continue
		end
		local reserved = self.reserved[id]
		local best, bestDistance = nil, math.huge
		for _, eater in eaters do
			-- (a popped capy can't eat its own spill for a moment)
			if reserved and reserved.Player == eater.Player and reserved.Until > now then
				continue
			end
			local dx, dz = eater.X - snack[3], eater.Z - snack[4]
			local distance = math.sqrt(dx * dx + dz * dz)
			if distance <= eater.Reach and distance < bestDistance and math.abs(eater.Y) < 8 then
				best, bestDistance = eater.Player, distance
			end
		end
		if best then
			self.snacks[id] = nil
			self.reserved[id] = nil
			taken[best] = taken[best] or {}
			table.insert(taken[best], snack)
		end
	end
	for player, list in taken do
		local gain, gold, ids = 0, false, {}
		for _, snack in list do
			table.insert(ids, snack[1])
			-- (a FEAST doubles what grows or falls on the lawn, never a spill: pops don't make weight)
			gain += Rules.SNACKS[snack[2]].Mass * (if self.feast and snack[8] ~= Rules.ARC then 2 else 1)
			if snack[2] == Rules.GOLD then
				gold = true
			end
		end
		self:_setMass(player, (self.mass[player] or 0) + gain)
		self.snacksDirty = true
		ctx:Fire(nil, "Eat", player.UserId, ids, gain, gold)
	end
end

-- A spot for a new snack, not right under anyone.
function CapyGoBoom:_freeSpot(): (number, number)
	local ctx = self.context
	local origin = self.center
	local roots = {}
	for _, player in ctx:GetAlivePlayers() do
		local _, _, root = ctx:GetCharacter(player)
		if root then
			table.insert(roots, root.Position)
		end
	end
	local x, z = 0, 0
	for _ = 1, 8 do
		x, z = self:_spot(0.93)
		local clear = true
		for _, position in roots do
			if (position.X - origin.X - x) ^ 2 + (position.Z - origin.Z - z) ^ 2 < 7 * 7 then
				clear = false
				break
			end
		end
		if clear then
			break
		end
	end
	return x, z
end

-- Keeps the lawn stocked: new snacks sprout where nobody stands, at a steady rate (Rules.RefillRate)
-- while it is below its target.
function CapyGoBoom:_refill()
	local ctx = self.context
	local clock = os.clock()
	local elapsed = math.min(clock - self.lastRefill, 1)
	self.lastRefill = clock
	if ctx:TimeIsUp() then
		return
	end
	local count = #ctx:GetPlayers()
	self.refillTokens =
		math.min(self.refillTokens + Rules.RefillRate(count) * elapsed * (if self.feast then 2 else 1), 3)
	if self.refillTokens < 1 then
		return
	end
	local target = math.floor(Rules.TargetSnacks(count) * (if self.feast then 1.15 else 1))
	local have = 0
	for _ in self.snacks do
		have += 1
	end
	local missing = math.min(math.floor(self.refillTokens), target - have, Rules.MAX_SNACKS - have)
	if missing <= 0 then
		return
	end
	self.refillTokens -= missing
	local made = {}
	for _ = 1, missing do
		local x, z = self:_freeSpot()
		table.insert(made, self:_addSnack(self:_pickKind(), x, z, x, z, Rules.SPROUT, nil))
	end
	ctx:Fire(nil, "Spawn", made)
end

-- Moments --------------------------------------------------------------------------------------------

-- A beam of light where a SNACK DROP will land, then a golden apple and a dozen snacks fall there.
function CapyGoBoom:_snackDrop()
	local ctx = self.context
	local x, z = self:_spot(0.6)
	self.dropSpot = self.center + Vector3.new(x, 0, z)
	ctx:Fire(nil, "DropWarn", round2(x), round2(z), round2(ctx:Now() + Rules.DROP_WARN))
	ctx:Announce("SNACK DROP! A golden apple is coming down!", "info", 2.5)
	ctx:Sound("HazardWarning")
	ctx:Delay(Rules.DROP_WARN - Rules.FLIGHT[Rules.SKY], function()
		local made = { self:_addSnack(Rules.GOLD, x, z, x, z, Rules.SKY, nil) }
		for index = 1, Rules.DROP_SNACKS do
			local angle = index / Rules.DROP_SNACKS * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
			local distance = rng:NextNumber(2.5, Rules.DROP_SPREAD)
			local kind = if index % 4 == 0 then Rules.BIG elseif index % 2 == 0 then Rules.TASTY else Rules.SMALL
			table.insert(
				made,
				self:_addSnack(
					kind,
					x + math.cos(angle) * distance,
					z + math.sin(angle) * distance,
					x,
					z,
					Rules.SKY,
					nil
				)
			)
		end
		ctx:Fire(nil, "Spawn", made)
		-- (the spot is a goal for bots until it lands, then it is just another heap)
		ctx:Delay(Rules.FLIGHT[Rules.SKY] + 2, function()
			self.dropSpot = nil
		end)
	end)
end

function CapyGoBoom:_events()
	local ctx = self.context
	if ctx:TimeIsUp() then
		return
	end
	local elapsed = ctx:Elapsed()
	local duration = ctx.Definition.Duration
	for index, fraction in Rules.DROPS do
		if not self.dropWarned[index] and elapsed >= fraction * duration - Rules.DROP_WARN then
			self.dropWarned[index] = true
			self:_snackDrop()
		end
	end
	if not self.feast and elapsed >= duration - Rules.FEAST then
		self.feast = true
		ctx:SetShared("Feast", true)
		ctx:SetStatus("FEAST! Lawn snacks count DOUBLE!")
		ctx:Announce("FEAST! Lawn snacks count DOUBLE!", "warning", 3)
		ctx:Sound("HazardWarning")
		local made = {}
		for _ = 1, 12 do
			local x, z = self:_spot(0.9)
			table.insert(made, self:_addSnack(self:_pickKind(), x, z, x, z, Rules.SKY, nil))
		end
		ctx:Fire(nil, "Spawn", made)
	end
end

-- BOOM -------------------------------------------------------------------------------------------------

-- When a press was made: what the client says (it sends api:Now()), kept within its ping.
function CapyGoBoom:_pressTime(player: any, claimed: any): number
	local now = self.context:Now()
	local lag = pingOf(player)
	if finite(claimed) then
		return math.clamp(claimed, now - lag / 2 - 0.1, now)
	end
	return now - lag / 2
end

-- Tells a player's screen its press didn't fire, so it stops drawing a shot (and when it may try again).
function CapyGoBoom:_refuse(player: any)
	if not BotRegistry.IsBot(player) then
		local ready = math.max(self.readyAt[player] or 0, self.stunUntil[player] or 0)
		self.context:Fire(player, "Refused", round2(ready))
	end
end

-- Bends a shot toward the rival nearest to where it points, if one is within the cone. Rivals are where the
-- shooter saw them (rewound, like the hit test): aiming at where a moving rival is now would snap the shot to a
-- spot it has already left.
function CapyGoBoom:_assist(shooter: any, from: Vector3, dir: Vector3, aimed: boolean, rewind: number): Vector3
	local ctx = self.context
	local now = ctx:Now()
	local arc = if aimed then Rules.ASSIST_AIMED else Rules.ASSIST_FREE
	local best: Vector3? = nil
	local bestAngle = math.huge
	for _, other in ctx:GetAlivePlayers() do
		if other == shooter or self.mass[other] == nil or (self.safeUntil[other] or 0) > now + 0.25 then
			continue
		end
		local _, _, root = ctx:GetCharacter(other)
		if not root then
			continue
		end
		local seen = if rewind > 0 then self:_positionAt(other, now - rewind) else nil
		local offset = flat((seen or root.Position) - from)
		local distance = offset.Magnitude
		if distance < 0.5 or distance > Rules.SHELL_RANGE - 4 then
			continue
		end
		local widen = math.asin(math.clamp(Rules.HitRadius(Rules.ScaleOf(self.mass[other])) / distance, 0, 1))
		local angle = math.acos(math.clamp(dir:Dot(offset.Unit), -1, 1))
		if angle <= arc + widen and angle < bestAngle then
			best, bestAngle = offset.Unit, angle
		end
	end
	return best or dir
end

function CapyGoBoom:_boom(player: any, claimed: any, ax: any, az: any)
	local ctx = self.context
	if ctx:TimeIsUp() or self.mass[player] == nil then
		return
	end
	local now = ctx:Now()
	local t = self:_pressTime(player, claimed)
	if
		(self.stunUntil[player] or 0) > now
		or t < (self.readyAt[player] or 0) - 0.03
		or #self.shells >= Rules.MAX_SHELLS
	then
		self:_refuse(player)
		return
	end
	local _, _, root = ctx:GetCharacter(player)
	if not root then
		self:_refuse(player)
		return
	end
	-- Where it points: the mouse on PC (a direction the client sent), else the way the capy faces.
	-- (normalised in doubles, and only from sane numbers: a huge value would square to infinity as a Vector3)
	local aim: Vector3? = nil
	if finite(ax) and finite(az) and math.abs(ax) < 1e4 and math.abs(az) < 1e4 then
		local length = math.sqrt(ax * ax + az * az)
		if length > 0.1 then
			aim = Vector3.new(ax / length, 0, az / length)
		end
	end
	local look = flat(root.CFrame.LookVector)
	local dir = aim or (if look.Magnitude > 0.01 then look.Unit else -Vector3.zAxis)
	local position = root.Position
	local rewind = math.min(pingOf(player) / 2 + (if BotRegistry.IsBot(player) then 0 else INTERP), REWIND_CAP)
	-- (aim assist is for people's thumbs: a bot's misses are its own, so it gets none)
	if not BotRegistry.IsBot(player) then
		dir = self:_assist(player, position, dir, aim ~= nil, rewind)
	end
	if not (finite(dir.X) and finite(dir.Z)) or math.abs(dir.Magnitude - 1) > 0.01 then
		dir = if look.Magnitude > 0.01 then look.Unit else -Vector3.zAxis
	end

	local scale = Rules.ScaleOf(self.mass[player])
	-- (counted from when the press was made, like the client counts it, so a steady tapper isn't turned
	-- down for the trip the press took)
	local ready = t + Rules.RELOAD
	self.readyAt[player] = ready
	if not BotRegistry.IsBot(player) then
		ctx:SetPlayerShared(player, "ReadyAt", round2(ready))
	end
	self.nextShell += 1
	self.shots[player] = (self.shots[player] or 0) + 1
	-- (from the capy itself: whoever stands in front of the cannon is hit; clients draw it from the muzzle)
	local origin = Vector3.new(position.X, position.Y - 0.9, position.Z)
	local shell = {
		Id = self.nextShell,
		Owner = player,
		Origin = origin,
		Dir = dir,
		Y = origin.Y,
		T0 = now,
		Age = 0,
		-- What the shooter saw of each rival: one way back plus Roblox's interpolation, capped.
		Rewind = rewind,
	}
	table.insert(self.shells, shell)
	ctx:Fire(
		nil,
		"Shot",
		shell.Id,
		player.UserId,
		round2(origin.X),
		round2(origin.Y),
		round2(origin.Z),
		round2(dir.X),
		round2(dir.Z),
		round2(now),
		round2(scale)
	)
end

-- Where a participant was at server time t (interpolated between the recorded samples).
function CapyGoBoom:_positionAt(player: any, t: number): Vector3?
	local samples = self.history[player]
	if not samples or #samples == 0 then
		return nil
	end
	if t <= samples[1][1] then
		return samples[1][2]
	end
	for index = #samples, 2, -1 do
		local before, after = samples[index - 1], samples[index]
		if t >= before[1] then
			local gap = after[1] - before[1]
			if gap < 1e-6 then
				return after[2]
			end
			return before[2]:Lerp(after[2], math.clamp((t - before[1]) / gap, 0, 1))
		end
	end
	return samples[#samples][2]
end

-- Flies every shell on the server's clock and judges it against what the shooter saw.
function CapyGoBoom:_stepShells()
	local ctx = self.context
	if #self.shells == 0 then
		return
	end
	if ctx:TimeIsUp() then
		table.clear(self.shells)
		return
	end
	local now = ctx:Now()
	local origin = self.center
	local maxAge = Rules.SHELL_RANGE / Rules.SHELL_SPEED
	local wallRadius = self.radius - 0.4
	for index = #self.shells, 1, -1 do
		local shell = self.shells[index]
		local ended = false
		if self.mass[shell.Owner] == nil then
			ended = true
			ctx:Fire(nil, "ShellEnd", shell.Id, round2(shell.Origin.X), round2(shell.Y), round2(shell.Origin.Z), 2)
		else
			local age = math.min(now - shell.T0, maxAge)
			if age > shell.Age then
				local a = shell.Origin + shell.Dir * (Rules.SHELL_SPEED * shell.Age)
				local b = shell.Origin + shell.Dir * (Rules.SHELL_SPEED * age)
				shell.Age = age
				local hitT, kind, victim = 2, "", nil
				-- The hedge.
				if flat(a - origin).Magnitude >= wallRadius then
					hitT, kind = 0, "wall"
				else
					local leaves = Rules.SegmentLeaves(a.X, a.Z, b.X, b.Z, origin.X, origin.Z, wallRadius)
					if leaves and leaves < hitT then
						hitT, kind = leaves, "wall"
					end
				end
				-- The standing stones.
				for _, rock in self.rocks do
					local t = Rules.SegmentEnter(
						a.X,
						a.Z,
						b.X,
						b.Z,
						origin.X + rock.X,
						origin.Z + rock.Z,
						Rules.ROCK_R + Rules.SHELL_R
					)
					if t and t < hitT then
						hitT, kind = t, "rock"
					end
				end
				-- Capys, where the shooter saw them.
				for _, other in ctx:GetAlivePlayers() do
					local mass = self.mass[other]
					if other == shell.Owner or mass == nil or (self.safeUntil[other] or 0) > now then
						continue
					end
					local _, _, root = ctx:GetCharacter(other)
					if not root then
						continue
					end
					local seen = if shell.Rewind > 0 then self:_positionAt(other, now - shell.Rewind) else nil
					local at = seen or root.Position
					local scale = Rules.ScaleOf(mass)
					if math.abs(shell.Y - at.Y) > Rules.HitTolerance(scale) then
						continue -- jumped over it
					end
					local t = Rules.SegmentEnter(a.X, a.Z, b.X, b.Z, at.X, at.Z, Rules.HitRadius(scale) + Rules.SHELL_R)
					if t and t < hitT then
						hitT, kind, victim = t, "pop", other
					end
				end
				if kind ~= "" then
					ended = true
					local at = a:Lerp(b, hitT)
					if kind == "pop" and victim then
						self:_pop(shell, victim, at)
					else
						ctx:Fire(nil, "ShellEnd", shell.Id, round2(at.X), round2(shell.Y), round2(at.Z), 1)
					end
				elseif age >= maxAge then
					ended = true
					ctx:Fire(nil, "ShellEnd", shell.Id, round2(b.X), round2(shell.Y), round2(b.Z), 2)
				end
			end
		end
		if ended then
			table.remove(self.shells, index)
		end
	end
end

-- A shell hit `victim`: it spills part of its weight, is thrown, staggers and is safe for a moment.
function CapyGoBoom:_pop(shell: { [string]: any }, victim: any, at: Vector3)
	local ctx = self.context
	local now = ctx:Now()
	local attacker = shell.Owner
	local mass = self.mass[victim]
	if mass == nil then
		return
	end
	local _, victimHumanoid, root = ctx:GetCharacter(victim)
	local position = if root then root.Position else at
	local spill = Rules.SpillOf(mass, self:_leader() == victim)
	self.safeUntil[victim] = now + Rules.SAFE
	self.stunUntil[victim] = now + Rules.STUN
	if self.pops[attacker] ~= nil then
		self.pops[attacker] += 1
		self.massDirty = true
	end
	if spill > 0 then
		self:_setMass(victim, mass - spill)
		-- The spill sprays back toward the shooter and out to the sides, never the way the victim flies.
		self:_spill(spill, position, -shell.Dir, victim)
	end
	-- Someone already in the air gets no extra lift.
	local airborne = root ~= nil
		and (
			root.Position.Y - self.center.Y > standHeight(victimHumanoid, root) + 0.8
			or math.abs(root.AssemblyLinearVelocity.Y) > 2
		)
	local lift = if airborne then 0 else Rules.KNOCK_UP
	ctx:Knockback(victim, shell.Dir * Rules.KNOCK + Vector3.new(0, lift, 0), Rules.STUN)
	ctx:Fire(
		nil,
		"Pop",
		shell.Id,
		attacker.UserId,
		victim.UserId,
		spill,
		{ round2(position.X), round2(position.Y), round2(position.Z) },
		round2(now + Rules.SAFE),
		round2(now + Rules.STUN)
	)
end

-- Players leaving: their weight spills where they stood -------------------------------------------------

function CapyGoBoom:_onLeave(player: any)
	local mass = self.mass[player]
	if mass == nil then
		return
	end
	local samples = self.history[player]
	local last = samples and samples[#samples]
	local at = if last then last[2] else self.center
	self.mass[player] = nil
	self.pops[player] = nil
	self.history[player] = nil
	for index = #self.shells, 1, -1 do
		local shell = self.shells[index]
		if shell.Owner == player then
			table.remove(self.shells, index)
			self.context:Fire(
				nil,
				"ShellEnd",
				shell.Id,
				round2(shell.Origin.X),
				round2(shell.Y),
				round2(shell.Origin.Z),
				2
			)
		end
	end
	self:_spill(mass, at, nil, nil, 14)
	local roster = {}
	for _, entry in self.roster do
		if entry[1] ~= player.UserId then
			table.insert(roster, entry)
		end
	end
	self.roster = roster
	self.context:SetSharedJSON("Roster", roster)
	self.massDirty = true
end

-- Safety nets ---------------------------------------------------------------------------------------------

-- Puts every character in the round in the mode's group (GROUP; respawns too).
function CapyGoBoom:_groupCharacters()
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

-- Anyone who got outside the hedge (a knock over it, a glitch) is put back inside, players and bots alike.
function CapyGoBoom:_keepInside()
	local ctx = self.context
	local origin = self.center
	local limit = self.radius + Rules.WALL_THICK + 1
	for _, player in ctx:GetAlivePlayers() do
		local character, _, root = ctx:GetCharacter(player)
		if not character or not root or root.Anchored then
			continue
		end
		local offset = flat(root.Position - origin)
		if offset.Magnitude <= limit then
			continue
		end
		local inside = offset.Unit * (self.radius - 4)
		local spot = origin + inside + Vector3.new(0, 3.5, 0)
		character:PivotTo(CFrame.lookAt(spot, Vector3.new(origin.X, spot.Y, origin.Z)))
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- Nothing flings a bot faster than its hardest knock.
function CapyGoBoom:_limitBots()
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
		local sideways = Vector3.new(velocity.X, 0, velocity.Z)
		if velocity.Y > BOT_MAX_UP or sideways.Magnitude > BOT_MAX_FLAT then
			if sideways.Magnitude > BOT_MAX_FLAT then
				sideways = sideways.Unit * BOT_MAX_FLAT
			end
			root.AssemblyLinearVelocity = Vector3.new(sideways.X, math.min(velocity.Y, BOT_MAX_UP), sideways.Z)
		end
	end
end

-- Runs one step of the round's loops. ctx:Loop and ctx:Heartbeat stop for good at the first error, which
-- would quietly end eating (or the shells); here an error is reported once and the other steps carry on.
function CapyGoBoom:_safely(label: string, step: (any) -> ())
	local ok, err = pcall(step, self)
	if not ok and not self.failed[label] then
		self.failed[label] = true
		Telemetry.Error("CapyGoBoom", `{label}: {err}`)
	end
end

function CapyGoBoom:Start()
	local ctx = self.context
	self.groupReady = setUpGroup()
	self:_groupCharacters()
	for _, player in ctx:GetPlayers() do
		self:_applySpeed(player)
	end

	ctx:OnAction("Boom", function(player, claimed, ax, az)
		self:_boom(player, claimed, ax, az)
	end, { Interval = 0.1 })

	-- Positions 20 times a second, for judging what a shooter saw.
	local since = 0
	ctx:Heartbeat(function(dt)
		since += dt
		if since >= 0.05 then
			since = 0
			local now = ctx:Now()
			for _, player in ctx:GetAlivePlayers() do
				local _, _, root = ctx:GetCharacter(player)
				if not root or self.mass[player] == nil then
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
		end
		self:_safely("shells", self._stepShells)
	end)

	ctx:Loop(function(): number?
		self:_safely("group", self._groupCharacters)
		self:_safely("inside", self._keepInside)
		self:_safely("pickUps", self._pickUps)
		self:_safely("limitBots", self._limitBots)
		self:_safely("events", self._events)
		self:_safely("refill", self._refill)
		if self.massDirty and os.clock() - self.lastMassShare >= MASS_SHARE then
			self:_safely("shareMass", self._shareMass)
		end
		if self.snacksDirty and os.clock() - self.lastSnackShare >= SNACK_SNAPSHOT then
			self:_safely("shareSnacks", self._shareSnacks)
		end
		return 0.1
	end)
end

function CapyGoBoom:GetResults()
	local ctx = self.context
	local entries = {}
	for player in ctx.Participants do
		if not player.Parent then
			continue
		end
		local mass = self.mass[player] or 0
		local pops = self.pops[player] or 0
		table.insert(entries, {
			Player = player,
			Rank = mass * 1000 + math.min(pops, 999),
			ScoreText = `{mass} {Rules.UNIT} • {if pops == 1 then "1 pop" else `{pops} pops`}`,
			BestScore = mass,
		})
	end
	return { Entries = entries }
end

return CapyGoBoom

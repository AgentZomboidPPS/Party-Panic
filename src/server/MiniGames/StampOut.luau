-- Stamp Out (Versus, 40s): bounce around a giant paper pad on a rubber stamp and ink the most paper.
--
-- After "Stamp Out!" (Mario Party 4 / Jamboree): every player rides a bouncing rubber stamp around a
-- giant paper pad, leaving a stamp of their ink wherever it lands; stamps cover rivals' ink; tap to
-- hop forward, hold to charge a longer jump; when time runs out the biggest share of the pad wins.
--
-- How it works here:
--   * The arena is a giant school desk in a kid's room: a cream paper pad (120 studs square, 100 for
--     up to 6 participants so small rounds stay lively; ruled
--     like a notebook) on a wooden desk top, giant pencils, an ink pad, rubber stamps and paper
--     clips around it. Everything solid is drawn: the desk top, the paper, the pad's binding and the
--     props that collide (pencils, ink pad, stamps: one MeshPart per piece, so their collision hugs
--     what you see). The room, the desk's legs and the paper clips are decoration nobody can touch.
--   * Each participant gets an ink: one of 12 colours AND a symbol (Logic/StampGrid.INKS), so colour
--     is never the only cue. They wear a rubber stamp under their feet in their ink, with their
--     symbol on its sides (welded, massless, nothing collides with it).
--   * EVERY landing stamps. The server watches every participant's feet against the paper: once
--     they've been up in the air and come back down onto the paper, it stamps a disc of their ink
--     there (cells within the radius, Logic/StampGrid.Disc). A plain jump makes a small stamp; the
--     STAMP button hops forward (tap: 10 studs, hold up to 0.8 s: 30 studs) and lands a bigger one.
--     In the last quarter of the round every stamp is 30% bigger ("BIG STAMPS!").
--   * The server owns it all: where you landed is where the server saw your feet touch down (the
--     player's own device moves their character, so it's the same spot they saw, just a moment
--     later). A landing farther from the take-off than that hop (or jump) could carry, or a second
--     landing within 0.3 s, doesn't stamp; a hop's charge is the shorter of what the device says
--     and what the server timed between the presses (plus ping leeway), so nobody fakes a big one.
--   * The pad travels to clients as one string (one character per cell) twice a second, plus a
--     "Stamp" event per landing so everyone sees it at once; clients redraw with the same Disc().
--   * Score = cells you own (shown as % of the pad). Falling off the desk puts you back on the paper.
--   * Bots: Bots/StampOut.luau. Their jumps go through BotService like a player's; their hops are
--     flown by the server here (the same arc a player's device flies), and the same landing check
--     stamps for them (hazard parity: nothing here only happens on clients).
--
-- Sweep pass (owner: "Let's do a full bug and clean sweep."; the owner's "Bots are still rubber
-- banding on spleef" was this): a bot's root is anchored for its hop and unanchored at the landing
-- (and at the end), which put it back to automatic network ownership, so the engine could hand the
-- bot to the nearest player's device and it snapped about. Each unanchor now gives it straight back
-- to the server (giveBack).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaKit = require(script.Parent.Kit.ArenaKit)
local MiniGame = require(script.Parent.Kit.MiniGame)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local StampGrid = require(ReplicatedStorage.Shared.Logic.StampGrid)

local StampOut = MiniGame.Define("StampOut", { Results = "Score" })

local PAPER_TOP = StampGrid.PAPER_TOP
local DESK = Vector3.new(236, 4, 184) -- the desk top (its top is the arena origin's Y)
local AIR_HEIGHT = 1.6 -- feet this far above the paper: in the air
local LAND_HEIGHT = 0.7 -- ...and back within this: landed
local MIN_STAMP_GAP = 0.3 -- seconds between two stamps of one player
local MIN_AIRTIME = 0.25 -- a landing counts only after this long in the air (no bobbing)
local MAX_JUMP_AIR = 1.2 -- a plain jump's reach grows with airtime up to this (no hovering)
local TAKEOFF_NEAR = 3 -- a Hop arriving while the feet are this close to the paper is a take-off
local GRID_EVERY = 2.5 -- seconds between full-pad resyncs (Stamp events carry the changes)
local SYNC_EVERY = 0.5

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Lets a bot's root go after a hop the server flew, and keeps the bot the server's: a part that was
-- anchored goes back to automatic network ownership, and the engine would hand the bot to the
-- nearest player's device (it snaps about as it hops between devices).
local function giveBack(root: BasePart)
	root.Anchored = false
	pcall(root.SetNetworkOwner, root, nil)
end

-- How far below the root's center a character's soles are.
local function legs(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		return 3
	end
	return humanoid.HipHeight + root.Size.Y / 2
end

local function isBot(player: any): boolean
	return typeof(player) ~= "Instance"
end

function StampOut:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	local origin = ctx.Origin.Position
	self.Paper = origin + Vector3.new(0, PAPER_TOP, 0) -- the paper's top center
	StampGrid.Configure(StampGrid.SizeFor(#ctx:GetPlayers()))
	self.Owners = table.create(StampGrid.N * StampGrid.N, 0)
	self.Counts = {} -- ink -> cells
	self.InkOf = {} -- player -> ink
	self.PlayerOf = {} -- ink -> player
	self.Track = {} -- player -> landing tracker
	self.ChargeStart = {} -- player -> server time of their last "Charge"
	self.Flying = {} -- bot -> server-flown hop
	self.Dirty = true

	self:BuildArena()

	-- Inks in join order; shared as userId -> ink.
	local inks = {}
	for index, player in ctx:GetPlayers() do
		local ink = (index - 1) % #StampGrid.INKS + 1
		self.InkOf[player] = ink
		self.PlayerOf[ink] = player
		self.Counts[ink] = 0
		inks[tostring(player.UserId)] = ink
		ctx:SetScoreText(player, "0%")
	end
	ctx:SetSharedJSON("Inks", inks)
	ctx:SetSharedJSON("Pad", { X = self.Paper.X, Y = self.Paper.Y, Z = self.Paper.Z, N = StampGrid.N })
	ctx:SetShared("Grid", StampGrid.Encode(self.Owners))

	ctx.Hooks.CharacterReady = function(player, character)
		self:Dress(player, character)
		self.Track[player] = nil
	end
	ctx.Hooks.Respawn = function(player)
		self.Track[player] = nil
		self.Flying[player] = nil
		local rng = Random.new()
		local spot = self.Paper
			+ Vector3.new(rng:NextNumber(-1, 1) * StampGrid.PAD * 0.3, 0, rng:NextNumber(-1, 1) * StampGrid.PAD * 0.3)
		return CFrame.lookAt(spot, Vector3.new(self.Paper.X, spot.Y, self.Paper.Z))
	end
	ctx.Hooks.PlayerLeft = function(player)
		self.Track[player] = nil
		self.Flying[player] = nil
		self.ChargeStart[player] = nil
		-- Their ink stays on the paper, but they leave the standings.
		inks[tostring(player.UserId)] = nil
		ctx:SetSharedJSON("Inks", inks)
	end

	local count = #ctx:GetPlayers()
	ctx:SpawnAll(ArenaKit.SpawnRing(self.Paper, if count <= 4 then 24 else 38, count), true)
	ctx:SetStatus("Every landing stamps your ink!")
end

-- The desk, the paper pad and the room around them.
function StampOut:BuildArena()
	local ctx = self.context
	local origin = ctx.Origin.Position
	local arena = ctx.Arena
	local PAD = StampGrid.PAD

	-- The desk top (solid, drawn) and its legs down to the floor far below (decoration).
	Build.Part({
		Name = "Desk",
		Size = DESK,
		CFrame = CFrame.new(origin - Vector3.new(0, DESK.Y / 2, 0)),
		Color = rgb(196, 140, 86),
		Material = Enum.Material.Wood,
		Parent = arena,
	})
	Build.Decor({
		Name = "DeskApron",
		Size = Vector3.new(DESK.X - 6, 6, DESK.Z - 6),
		CFrame = CFrame.new(origin - Vector3.new(0, DESK.Y + 3.05, 0)),
		Color = rgb(150, 98, 56),
		Material = Enum.Material.Wood,
		Parent = arena,
	})
	for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		Build.Decor({
			Name = "DeskLeg",
			Size = Vector3.new(10, 116, 10),
			CFrame = CFrame.new(origin + Vector3.new(corner.X * (DESK.X / 2 - 9), -67, corner.Y * (DESK.Z / 2 - 9))),
			Color = rgb(160, 108, 62),
			Material = Enum.Material.Wood,
			Parent = arena,
		})
	end
	-- The room: a carpet far below, two papered walls and a window (nothing anyone can reach: you'd
	-- fall past KillY long before the carpet).
	Build.Decor({
		Name = "Carpet",
		Size = Vector3.new(900, 2, 900),
		CFrame = CFrame.new(origin + Vector3.new(0, -126, 0)),
		Color = rgb(86, 120, 190),
		Material = Enum.Material.Fabric,
		Parent = arena,
	})
	-- (each wall down to the carpet's top, -125: they stopped 1 and 1.5 over it. Their tops stay 0.5
	-- apart, 216 and 216.5, where they meet in the corner.)
	for _, wall in
		{
			{ CFrame.new(origin + Vector3.new(59.5, 45.5, -300)), Vector3.new(781, 341, 4) },
			{ CFrame.new(origin + Vector3.new(-330, 45.75, 74.5)), Vector3.new(4, 341.5, 751) },
		}
	do
		Build.Decor({
			Name = "Wall",
			Size = wall[2],
			CFrame = wall[1],
			Color = rgb(250, 226, 170),
			Parent = arena,
		})
	end
	Build.Decor({
		Name = "Window",
		Size = Vector3.new(220, 130, 0.4),
		CFrame = CFrame.new(origin + Vector3.new(40, 70, -297.6)),
		Color = rgb(150, 214, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		Parent = arena,
	})
	for _, bar in
		{
			-- (each bar its own depth, 0.2 apart: no two faces share a plane)
			{ Vector3.new(40, 70, -295), Vector3.new(6, 136, 2) },
			{ Vector3.new(40, 70, -295), Vector3.new(226, 6, 2.4) },
			{ Vector3.new(40, 138, -295), Vector3.new(232, 8, 2.8) },
			{ Vector3.new(40, 2, -295), Vector3.new(232, 8, 3.2) },
			{ Vector3.new(-73, 70, -295), Vector3.new(8, 136, 3.6) },
			{ Vector3.new(153, 70, -295), Vector3.new(8, 136, 4) },
		}
	do
		Build.Decor({
			Name = "WindowFrame",
			Size = bar[2],
			CFrame = CFrame.new(origin + bar[1]),
			Color = rgb(255, 255, 255),
			Parent = arena,
		})
	end

	-- The paper pad: a cardboard back, the paper block and a red cloth binding along the far edge.
	Build.Part({
		Name = "Cardboard",
		Size = Vector3.new(PAD + 4, 0.6, PAD + 4),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.1, 0)),
		Color = rgb(150, 120, 92),
		Material = Enum.Material.Cardboard,
		Parent = arena,
	})
	Build.Part({
		Name = "Paper",
		Size = Vector3.new(PAD, PAPER_TOP - 0.3, PAD),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.3 + (PAPER_TOP - 0.3) / 2, 0)),
		Color = rgb(252, 249, 238),
		Parent = arena,
	})
	Build.Part({
		Name = "Binding",
		Size = Vector3.new(PAD + 4.4, PAPER_TOP + 0.95, 4),
		CFrame = CFrame.new(origin + Vector3.new(0, (PAPER_TOP + 0.95) / 2 - 0.35, -PAD / 2 - 2)),
		Color = rgb(200, 44, 52),
		Material = Enum.Material.Fabric,
		Parent = arena,
	})
	-- Notebook ruling: pale blue lines and a red margin, flat on the paper (under the ink). One layer
	-- 0.1 above the paper (the rules stop at the margin, so nothing overlaps), the ink tiles 0.1 above
	-- that: every layer clear of the next, nothing flickers.
	local lineY = PAPER_TOP + 0.1
	local marginX = -PAD / 2 + 14
	for index = 1, 15 do
		local z = -PAD / 2 + index * PAD / 16
		for _, span in { { -PAD / 2 + 0.1, marginX - 0.3 }, { marginX + 0.3, PAD / 2 - 0.1 } } do
			Build.Decor({
				Name = "Rule",
				Size = Vector3.new(span[2] - span[1], 0.02, 0.3),
				CFrame = CFrame.new(origin + Vector3.new((span[1] + span[2]) / 2, lineY, z)),
				Color = rgb(150, 190, 240),
				Parent = arena,
			})
		end
	end
	Build.Decor({
		Name = "Margin",
		Size = Vector3.new(0.35, 0.02, PAD - 0.2),
		CFrame = CFrame.new(origin + Vector3.new(marginX, lineY, 0)),
		Color = rgb(236, 120, 130),
		Parent = arena,
	})

	-- Desk clutter around the pad (meshes; see World/Props/StampOut.luau).
	local function at(x: number, z: number, yaw: number): CFrame
		return CFrame.new(origin + Vector3.new(x, 0, z)) * CFrame.Angles(0, math.rad(yaw), 0)
	end
	MeshLibrary.Get("StampOutPencil", { CFrame = at(0, 76, 180), Parent = arena })
	MeshLibrary.Get("StampOutPencil", {
		CFrame = at(-88, 4, 98),
		Colors = { Body = rgb(70, 150, 230) },
		Parent = arena,
	})
	MeshLibrary.Get("StampOutPencil", {
		CFrame = at(90, 0, -94),
		Colors = { Body = rgb(240, 90, 120) },
		Parent = arena,
	})
	MeshLibrary.Get("StampOutInkPad", { CFrame = at(94, 62, -20), Parent = arena })
	MeshLibrary.Get("StampOutBigStamp", { CFrame = at(-94, -64, 30), Scale = 1.5, Parent = arena })
	MeshLibrary.Get("StampOutBigStamp", {
		CFrame = at(98, -68, -40),
		Scale = 1.3,
		Colors = { Rubber = rgb(36, 104, 236), Knob = rgb(36, 104, 236) },
		Parent = arena,
	})
	MeshLibrary.Get("StampOutClip", { CFrame = at(-92, 62, 30), Parent = arena })
	MeshLibrary.Get("StampOutClip", {
		CFrame = at(40, -80, 10),
		Colors = { Wire = rgb(240, 200, 60) },
		Parent = arena,
	})
	MeshLibrary.Get("StampOutClip", {
		CFrame = at(-72, 84, 5),
		Colors = { Wire = rgb(90, 200, 120) },
		Parent = arena,
	})
end

-- Puts a rubber stamp in the player's ink under their feet, their symbol on its sides.
function StampOut:Dress(player: any, character: Model)
	local ink = StampGrid.INKS[self.InkOf[player] or 1]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or character:FindFirstChild("StampOutRider") then
		return
	end
	local model = MeshLibrary.Get("StampOutRider", { Colors = { Rubber = ink.Color, Band = ink.Color } })
	local _, size = model:GetBoundingBox()
	-- The rubber's face sits a hair below the soles; the wooden block rises around the feet.
	-- (Its rubber starts a hair above the soles, so the ink tiles on the paper never cover it.)
	model:PivotTo(root.CFrame * CFrame.new(0, -legs(humanoid, root) + 0.05, 0))
	local pivot = model:GetPivot()
	local base = MeshLibrary.Assemble(model, true)
	local badge = Build.Part({
		Name = "Badge",
		Size = Vector3.new(size.X * 1.01, size.Y * 0.45, size.Z * 1.01),
		CFrame = pivot * CFrame.new(0, size.Y * 0.6, 0),
		Transparency = 1,
		Anchored = false,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
		CastShadow = false,
		Parent = model,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		Build.SurfaceText(badge, face, ink.Symbol, {
			Name = "Symbol",
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.25,
			LightInfluence = 0.5,
			Brightness = 1,
			Padding = 0.02,
			MaxDistance = 120,
		})
	end
	Build.Weld(base, badge)
	Build.Weld(root, base)
	model.Parent = character
end

-- Pad-local flat coordinates of a world point.
function StampOut:Local(position: Vector3): (number, number)
	return position.X - self.Paper.X, position.Z - self.Paper.Z
end

-- Stamps `player`'s ink on every cell within `radius` of pad-local (x, z).
function StampOut:Stamp(player: any, x: number, z: number, radius: number)
	local ctx = self.context
	local ink = self.InkOf[player]
	if not ink or not ctx:IsRunning() then
		return
	end
	if ctx:Progress() >= StampGrid.FINAL_PROGRESS then
		radius *= StampGrid.FINAL_BOOST
	end
	-- Rounded the way the event carries them, so every client's Disc() gives the same cells.
	x = math.floor(x * 10 + 0.5) / 10
	z = math.floor(z * 10 + 0.5) / 10
	radius = math.floor(radius * 100 + 0.5) / 100
	local owners, counts = self.Owners, self.Counts
	local changed = {} -- ink -> delta
	for _, cell in StampGrid.Disc(x, z, radius) do
		local previous = owners[cell]
		if previous ~= ink then
			owners[cell] = ink
			changed[ink] = (changed[ink] or 0) + 1
			if previous > 0 then
				changed[previous] = (changed[previous] or 0) - 1
			end
		end
	end
	for owner, delta in changed do
		counts[owner] = (counts[owner] or 0) + delta
		local who = self.PlayerOf[owner]
		if who and ctx:State(who) then
			ctx:AddScore(who, delta)
			ctx:SetScoreText(who, `{StampGrid.Percent(counts[owner])}%`)
		end
	end
	self.Dirty = true
	self.Stamps = (self.Stamps or 0) + 1
	ctx:Fire(nil, "Stamp", ink, x, z, radius)
end

-- Watches everyone's feet: up in the air, then back down on the paper = a stamp.
function StampOut:WatchLandings()
	local ctx = self.context
	local paperY = self.Paper.Y
	local now = ctx:Now()
	for _, player in ctx:GetAlivePlayers() do
		local _, humanoid, root = ctx:GetCharacter(player)
		if not humanoid or not root then
			self.Track[player] = nil
			continue
		end
		local position = root.Position
		local height = position.Y - legs(humanoid, root) - paperY
		local track = self.Track[player]
		if not track then
			track = { Air = false, From = position, LastStamp = 0 }
			self.Track[player] = track
		end
		if not track.Air then
			if height > AIR_HEIGHT then
				track.Air = true
				track.AirAt = now
			else
				track.From = position
			end
			continue
		end
		if height >= LAND_HEIGHT then
			continue
		end
		self:Land(player, track, humanoid, root, height, now)
	end
end

-- A touchdown: stamps if it's a fair landing. A hop counts as a hop (its reach and bigger stamp)
-- only if the server saw the take-off right around the Hop and it really travelled; anything else
-- is a plain jump, whose reach is capped (no hovering) and which must have been in the air a moment.
function StampOut:Land(player: any, track, humanoid: Humanoid, root: BasePart, height: number, now: number)
	track.Air = false
	local position = root.Position
	local x, z = self:Local(position)
	local hop = track.Hop
	track.Hop = nil
	local airtime = now - (track.AirAt or now)
	local travelled = Vector3.new(position.X - track.From.X, 0, position.Z - track.From.Z).Magnitude
	track.From = position
	local reach = humanoid.WalkSpeed * math.min(airtime, MAX_JUMP_AIR) + 10
	local radius = StampGrid.JUMP_RADIUS
	if hop then
		local slack = 0.2 + hop.Ping * 2
		local tookOff = track.AirAt and track.AirAt >= hop.At - slack - 0.1 and track.AirAt <= hop.At + slack
		if tookOff and travelled >= hop.Distance * 0.5 then
			reach = math.max(reach, hop.Reach)
			radius = hop.Radius
		end
	end
	if
		height > -0.6 -- on the paper, not down on the desk beside it
		and StampGrid.OnPad(x, z)
		and airtime >= MIN_AIRTIME
		and travelled <= reach
		and now - track.LastStamp >= MIN_STAMP_GAP
	then
		track.LastStamp = now
		self:Stamp(player, x, z, radius)
	end
end

-- Bots' hops, flown by the server along the same arc a player's device flies.
function StampOut:FlyBots(dt: number)
	local ctx = self.context
	for bot, flight in self.Flying do
		local character, _, root = ctx:GetCharacter(bot)
		if not character or not root or not ctx:IsAlive(bot) then
			self.Flying[bot] = nil
			if root then
				giveBack(root)
			end
			continue
		end
		flight.T += dt
		local t = math.min(flight.T, flight.Airtime)
		local flat = flight.From + flight.Direction * (flight.Along * t)
		local y = flight.From.Y + flight.Up * t - workspace.Gravity * t * t / 2
		local position = Vector3.new(flat.X, math.max(y, flight.From.Y), flat.Z)
		character:PivotTo(CFrame.lookAt(position, position + flight.Direction))
		if flight.T >= flight.Airtime then
			self.Flying[bot] = nil
			giveBack(root)
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

function StampOut:Start()
	local ctx = self.context
	local gravity = workspace.Gravity

	-- The STAMP button: "Charge" when it goes down, "Hop" (charge 0..1, direction x, z) when it's let go.
	ctx:OnAction("Charge", function(player)
		self.ChargeStart[player] = ctx:Now()
	end, { Interval = 0 })
	ctx:OnAction("Hop", function(player, charge, dx, dz)
		if type(charge) ~= "number" or type(dx) ~= "number" or type(dz) ~= "number" then
			return
		end
		if charge ~= charge or dx ~= dx or dz ~= dz then
			return -- NaN
		end
		local _, humanoid, root = ctx:GetCharacter(player)
		if not humanoid or not root or ctx:IsStunned(player) then
			return
		end
		-- The stamp's size comes from the charge the device says, but never more than the server timed
		-- between the presses (plus ping leeway). How far the landing may be is what the device flew
		-- (its own charge), so a legit hop always stamps even if a "Charge" got lost.
		local started = self.ChargeStart[player]
		self.ChargeStart[player] = nil
		local ping = math.min(player:GetNetworkPing(), 0.5)
		local timed = if started then (ctx:Now() - started) / StampGrid.CHARGE_TIME else 0
		local claimed = math.clamp(charge, 0, 1)
		charge = math.clamp(math.min(claimed, timed + 0.15 + ping * 2), 0, 1)
		local distance, up, along, airtime, radius = StampGrid.Hop(charge, gravity)
		local flown = StampGrid.Hop(claimed, gravity)
		self.Hops = (self.Hops or 0) + 1
		local track = self.Track[player]
		if track then
			-- A hop chained straight off a landing the server hasn't seen yet (positions arrive ~20
			-- times a second): that landing happened, stamp it first.
			if track.Air then
				local height = root.Position.Y - legs(humanoid, root) - self.Paper.Y
				if height < TAKEOFF_NEAR then
					self:Land(player, track, humanoid, root, math.max(height, 0), ctx:Now())
				end
			end
			track.Hop = {
				At = ctx:Now(),
				Ping = ping,
				Distance = distance,
				Reach = flown + 8,
				Radius = radius,
			}
		end
		if not isBot(player) then
			return -- their own device flies the hop; the landing watch stamps it
		end
		-- Bots: fly the hop here (from standing only, like a player's device allows).
		local direction = Vector3.new(dx, 0, dz)
		if direction.Magnitude < 0.1 or self.Flying[player] or (track and track.Air) then
			return
		end
		direction = direction.Unit
		root.Anchored = true
		self.Flying[player] = {
			From = root.Position,
			Direction = direction,
			Along = along,
			Up = up,
			Airtime = airtime,
			T = 0,
		}
	end, { Interval = 0.25 })

	ctx:Heartbeat(function(dt)
		self:FlyBots(dt)
		self:WatchLandings()
	end)

	-- Share the pad and the standings a couple of times a second.
	local final = false
	ctx:Loop(function()
		if not final and ctx:Progress() >= StampGrid.FINAL_PROGRESS then
			final = true
			ctx:SetShared("Final", true)
			ctx:Announce("BIG STAMPS! Every stamp is bigger now!", "warning", 2.5)
			ctx:Sound("HazardWarning")
		end
		local tip = ctx:Elapsed() < 6 -- the status line explains the game for the first seconds
		if tip then
			ctx:SetStatus("Jump: every landing stamps! Hold STAMP to hop far")
		end
		if self.Dirty then
			self.Dirty = false
			if ctx:Now() - (self.GridAt or 0) >= GRID_EVERY then
				self.GridAt = ctx:Now()
				ctx:SetShared("Grid", StampGrid.Encode(self.Owners))
			else
				self.Dirty = true -- (standings below still refresh; the pad goes out on the next resync)
			end
			local bestInk, best = nil, 0
			for ink, cells in self.Counts do
				local owner = self.PlayerOf[ink]
				if cells > best and owner and ctx:State(owner) then -- (not someone who left)
					bestInk, best = ink, cells
				end
			end
			local leader = bestInk and self.PlayerOf[bestInk]
			if leader and not tip then
				local symbol = StampGrid.INKS[bestInk].Symbol
				ctx:SetStatus(`{symbol} {leader.DisplayName} leads with {StampGrid.Percent(best)}%`)
			end
		end
		return SYNC_EVERY
	end)
end

function StampOut:Stop()
	-- Put down any bot still in the air (an anchored root would stay hanging).
	local ctx = self.context
	for bot in self.Flying do
		local _, _, root = ctx:GetCharacter(bot)
		if root then
			giveBack(root)
		end
	end
	self.Flying = {}
end

return StampOut

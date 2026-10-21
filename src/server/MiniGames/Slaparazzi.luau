-- Slaparazzi (Knockback, 1-12 players). After "Slaparazzi" (Super Mario Party): a photographer
-- snaps a photo every few seconds and everyone fights to be in the middle of the shot. Here it's a
-- red-carpet premiere: a stage with spotlights in front of a cheering crowd, and a photographer on
-- a tripod camera at the end of the carpet. A glowing photo frame (three rings and viewfinder
-- corners) sits on the stage; when the countdown runs out the camera flashes and everyone inside
-- the frame scores: 3 points in the gold middle, 2 in the silver ring, 1 in the bronze one. Then
-- the frame glides to a new spot. SLAP a rival (big cartoon glove, short cooldown) to knock them
-- out of the shot. 7 photos, most points wins. Each photo pops up for everyone as a snapshot card
-- with who scored.
--
-- How it works: the frame is a shared schedule (MG_Frame: where it glides from and to and when, the
-- next photo's time; Logic/Slaparazzi has the rule both halves use), so every client glides its
-- copy of the frame and counts down in step with the server. A photo is judged where each person
-- was on their own screen at the flash: the server keeps a short history of everyone's position
-- and looks a player up their one-way ping later (their device is ahead of what the server has).
--
-- Slaps (fair hits, owner: "the precision games will feel super bad if we dont"): the client picks
-- the target it sees within reach and turns to it; the server checks range and facing against
-- where the target was on the slapper's screen (the target's positions over the slapper's ping
-- plus the drawing delay) and where the slapper was, so a slap that looks like a hit counts. The
-- cooldown runs from the press itself. A hit throws the target with ctx:Knockback, which works the
-- same for players and bots; bots slap through ctx:BotAction exactly like a client.
--
-- Nothing solid where nothing is drawn (owner: "Theres invisible stuff you can jump on and hang on
-- in several games"): only the drawn grass, plaza, stage tiers and backdrop wall collide; every
-- mesh prop (cameras, tripods, spotlights, crowd, ropes) is non-colliding, and the spotlights' light
-- holders are invisible but neither solid nor hit by rays. Bots and players don't bump into each
-- other here (slaps go by position), so a crowd of people can't shove a server-moved bot into the sky.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.Slaparazzi)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local Shapes = require(script.Parent.Parent.World.Shapes)

local Slaparazzi = MiniGame.Define("Slaparazzi", { Results = "Score" })

local PHOTOS = 7
local FIRST_SHOT = 5.5 -- seconds after GO
local GAP = 7 -- between photos
local GLIDE_AFTER = 1.2 -- the frame starts gliding this long after a photo...
local GLIDE_TIME = 1.6 -- ... and takes this long
local END_AFTER = 3.2 -- the round ends this long after the last photo (its card is up)
local JUDGE_AFTER = 0.25 -- a photo is scored this long after the flash (players' news arrives late)
local PING_MAX = 0.35 -- the most of a round trip that is made up for
local SEEN_LAG = 0.15 -- other characters are drawn about this far behind the server on a screen
local HISTORY_STEP = 1 / 20
local HISTORY_KEEP = 1.5 -- seconds

-- The arena (studs from the origin; +Z is toward the photographer).
local PLAZA_Y = 0.15 -- the plaza's top
local FLOOR_Y = 1.45 -- the stage's top
local STAGE_Z = -2 -- the stage's middle
local STAGE = Vector3.new(60, 0.7, 40) -- the upper tier (the lower one is 4 studs bigger)
local FRAME_X = 17 -- how far from the stage's middle the frame's middle can go
local FRAME_Z0, FRAME_Z1 = -12, 7
local FRAME_MOVE = 11 -- each new spot is at least this far from the last one
local CAMERA_Z = 31

-- Bots and players don't touch in this mode (see the top). People use the lobby's PP_Players group.
local BOT_GROUP, PEOPLE_GROUP = "PP_SlapBots", "PP_Players"
local BOT_MAX_UP, BOT_MAX_FLAT = 60, Rules.KNOCK + 10

local rng = Random.new()

type Sample = { T: number, P: Vector3, L: Vector3 }

local function pingOf(player: any): number
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and type(ping) == "number" and ping == ping then math.clamp(ping, 0, PING_MAX) else 0.15
end

-- Puts every character in the round in the bots' or the people's collision group (parts that load
-- later too). Returns the function that does one character, or nil if the groups can't be set up.
local function separateBotsFromPeople(ctx): ((any, Model) -> ())?
	local ok = pcall(function()
		for _, group in { BOT_GROUP, PEOPLE_GROUP } do
			if not PhysicsService:IsCollisionGroupRegistered(group) then
				PhysicsService:RegisterCollisionGroup(group)
			end
		end
		PhysicsService:CollisionGroupSetCollidable(BOT_GROUP, PEOPLE_GROUP, false)
	end)
	if not ok then
		return nil
	end
	local function put(player: any, character: Model)
		local group = if BotRegistry.IsBot(player) then BOT_GROUP else PEOPLE_GROUP
		for _, item in character:GetDescendants() do
			if item:IsA("BasePart") then
				item.CollisionGroup = group
			end
		end
		ctx:Track(character.DescendantAdded:Connect(function(item)
			if item:IsA("BasePart") then
				item.CollisionGroup = group
			end
		end))
	end
	for _, player in ctx:GetPlayers() do
		local character = ctx:GetCharacter(player)
		if character then
			put(player, character)
		end
	end
	return put
end

-- Where the frame's middle is at server time t (on the stage floor).
function Slaparazzi:FramePosition(t: number?): Vector3
	local frame = self.frame
	local x, z = Rules.FrameAt(frame, t or self.context:Now())
	return Vector3.new(x, frame.Y, z)
end

-- Where `player` was at server time t (from the history; the newest sample if t is later).
function Slaparazzi:PositionAt(player: any, t: number): Vector3?
	local history: { Sample }? = self.history[player]
	if not history or #history == 0 then
		local _, _, root = self.context:GetCharacter(player)
		return root and root.Position
	end
	local newest = history[#history]
	if t >= newest.T then
		return newest.P
	end
	for index = #history - 1, 1, -1 do
		local a = history[index]
		if a.T <= t then
			local b = history[index + 1]
			local alpha = (t - a.T) / math.max(b.T - a.T, 1e-3)
			return a.P:Lerp(b.P, alpha)
		end
	end
	return history[1].P
end

-- History samples of `player` from server time t0 to now (newest first; at least the newest one).
function Slaparazzi:SamplesSince(player: any, t0: number): { Sample }
	local history: { Sample }? = self.history[player]
	local list = {}
	if history then
		for index = #history, 1, -1 do
			local sample = history[index]
			if sample.T < t0 and #list > 0 then
				break
			end
			table.insert(list, sample)
		end
	end
	return list
end

function Slaparazzi:_participant(userId: number): any
	for _, player in self.context:GetAlivePlayers() do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

function Slaparazzi:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 30
	local origin = ctx.Origin.Position
	self.origin = origin
	self.history = {} :: { [any]: { Sample } }
	self.readyAt = {} :: { [any]: number }
	self.stunnedUntil = {} :: { [any]: number }
	self.points = {} :: { [any]: number }
	self.slaps = {} :: { [any]: number }
	self.photo = 0

	self:_buildArena()

	local floor = origin.Y + FLOOR_Y
	local center = origin + Vector3.new(0, 0, STAGE_Z)
	self.frame = {
		X0 = center.X,
		Z0 = center.Z,
		X1 = center.X,
		Z1 = center.Z,
		T0 = 0,
		T1 = 0,
		Shot = ctx:Now() + 1e6,
		N = 1,
		Of = PHOTOS,
		Y = floor,
	} :: Rules.Frame
	self.frameModel = MeshLibrary.Get("SlaparazziFrame", {
		CFrame = CFrame.new(center.X, floor + 0.03, center.Z),
		Parent = ctx.Arena,
	})
	self:_publishFrame()

	-- Everyone starts the same distance from the frame's middle, just outside it.
	local players = ctx:GetPlayers()
	local count = #players
	local spawns = {}
	for index = 1, count do
		local angle = (index - 0.5) / count * math.pi * 2
		local at = center + Vector3.new(math.cos(angle) * 14, FLOOR_Y + 3, math.sin(angle) * 12.5)
		table.insert(spawns, CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z)))
	end
	ctx:SpawnAll(spawns, true)
	ctx.Hooks.Respawn = function()
		local angle = rng:NextNumber(0, math.pi * 2)
		local at = center + Vector3.new(math.cos(angle) * 22, FLOOR_Y + 3, math.sin(angle) * 14)
		return CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z))
	end
	for _, player in players do
		self.points[player] = 0
		self.slaps[player] = 0
		ctx:SetScoreText(player, "0 pts")
		ctx:SetPlayerShared(player, "Ready", 0)
	end

	local put = separateBotsFromPeople(ctx)
	ctx.Hooks.CharacterReady = function(player, character)
		if put then
			put(player, character)
		end
	end
	ctx.Hooks.PlayerLeft = function(player)
		self.history[player] = nil
	end

	ctx:ShareTemplate("SlaparazziGlove", MeshLibrary.Get("SlaparazziGlove"))
	ctx:SetSharedJSON("Layout", {
		Camera = { origin.X, origin.Y + PLAZA_Y, origin.Z + CAMERA_Z },
		Reach = Rules.CLIENT_REACH,
		Cooldown = Rules.COOLDOWN,
	})
	ctx:SetStatus("Get in the photo frame!")
end

function Slaparazzi:_buildArena()
	local ctx = self.context
	local origin = self.origin
	local arena = ctx.Arena
	local function at(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z)
	end
	local upright = CFrame.Angles(0, 0, math.rad(90))

	-- Grass out to the horizon (drawn and solid) and a ring of trees far away.
	Build.Part({
		Name = "Grass",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 640, 640),
		CFrame = CFrame.new(at(0, -2, 0)) * upright,
		Color = Color3.fromRGB(98, 178, 84),
		Material = Enum.Material.Grass,
		Parent = arena,
	})
	local leaves = { Color3.fromRGB(80, 190, 90), Color3.fromRGB(110, 200, 80), Color3.fromRGB(70, 165, 95) }
	for index = 0, 25 do
		local angle = (index + rng:NextNumber(-0.35, 0.35)) / 26 * math.pi * 2
		local distance = rng:NextNumber(74, 110)
		MeshLibrary.Get("Tree", {
			Scale = rng:NextNumber(1.6, 2.6),
			Colors = { Leaves = leaves[rng:NextInteger(1, #leaves)] },
			CFrame = CFrame.new(at(math.cos(angle) * distance, 0, math.sin(angle) * distance))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = arena,
		})
	end

	-- The plaza (a stone disc with a gold rim) and the stage on it: two tiers, so stepping up needs no
	-- jump.
	Build.Part({
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 80, 80),
		CFrame = CFrame.new(at(0, PLAZA_Y - 0.15, 0)) * upright,
		Color = Color3.fromRGB(214, 206, 196),
		Material = Enum.Material.Slate,
		Parent = arena,
	})
	Build.Part({
		Name = "PlazaRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.24, 82, 82),
		CFrame = CFrame.new(at(0, PLAZA_Y - 0.19, 0)) * upright,
		Color = Color3.fromRGB(196, 160, 70),
		Material = Enum.Material.SmoothPlastic,
		Parent = arena,
	})
	Shapes.Slab(STAGE + Vector3.new(4, 0, 4), 6, {
		Name = "StageStep",
		CFrame = CFrame.new(at(0, FLOOR_Y - 0.65 - 0.35, STAGE_Z)),
		Color = Color3.fromRGB(58, 40, 70),
		Material = Enum.Material.SmoothPlastic,
		Parent = arena,
	})
	Shapes.Slab(STAGE, 5, {
		Name = "Stage",
		CFrame = CFrame.new(at(0, FLOOR_Y - 0.35, STAGE_Z)),
		Color = Color3.fromRGB(86, 58, 44),
		Material = Enum.Material.WoodPlanks,
		Parent = arena,
	})
	-- The red carpet: a runner across the stage and down the plaza to the photographer.
	Build.Decor({
		Name = "CarpetStage",
		Size = Vector3.new(9, 0.06, STAGE.Z - 1),
		CFrame = CFrame.new(at(0, FLOOR_Y + 0.02, STAGE_Z)),
		Color = Color3.fromRGB(196, 24, 40),
		Material = Enum.Material.Fabric,
		Parent = arena,
	})
	local carpetFrom = STAGE_Z + STAGE.Z / 2 + 2
	Build.Decor({
		Name = "CarpetPlaza",
		Size = Vector3.new(9, 0.06, CAMERA_Z + 4 - carpetFrom),
		CFrame = CFrame.new(at(0, PLAZA_Y + 0.02, (carpetFrom + CAMERA_Z + 4) / 2)),
		Color = Color3.fromRGB(196, 24, 40),
		Material = Enum.Material.Fabric,
		Parent = arena,
	})
	for _, side in { -1, 1 } do
		for _, z in { carpetFrom + 1, carpetFrom + 7.5 } do
			MeshLibrary.Get("SlaparazziRope", {
				CFrame = CFrame.new(at(side * 6, PLAZA_Y, z + 3)) * CFrame.Angles(0, math.pi / 2, 0),
				Parent = arena,
			})
		end
	end

	-- The step-and-repeat wall behind the stage (drawn and solid: a wall you can see is one you hit).
	local wallZ = STAGE_Z - STAGE.Z / 2 - 0.55
	local wall = Build.Part({
		Name = "Backdrop",
		Size = Vector3.new(56, 13, 1.2),
		CFrame = CFrame.new(at(0, FLOOR_Y - 0.65 + 6.5, wallZ)),
		Color = Color3.fromRGB(34, 22, 58),
		Material = Enum.Material.Fabric,
		Parent = arena,
	})
	local title = Build.SurfaceText(wall, Enum.NormalId.Back, "★ SLAPARAZZI ★", {
		TextColor3 = Color3.fromRGB(255, 214, 90),
		PixelsPerStud = 16,
		Padding = 0.02,
		TextStrokeTransparency = 0.3,
	})
	local gui = title.Parent :: SurfaceGui
	title.Size = UDim2.fromScale(1, 0.3)
	title.Position = UDim2.fromScale(0, 0.05)
	-- The repeating logo pattern under the title.
	local grid = Instance.new("Frame")
	grid.Name = "Pattern"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromScale(0.03, 0.4)
	grid.Size = UDim2.fromScale(0.94, 0.56)
	grid.Parent = gui
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromScale(1 / 7, 1 / 3)
	layout.CellPadding = UDim2.fromOffset(0, 0)
	layout.Parent = grid
	for index = 1, 21 do
		local cell = Instance.new("TextLabel")
		cell.BackgroundTransparency = 1
		cell.Text = if index % 2 == 0 then "📸" else "★"
		cell.TextScaled = true
		cell.Font = Enum.Font.FredokaOne
		cell.TextColor3 = if index % 2 == 0 then Color3.new(1, 1, 1) else Color3.fromRGB(255, 120, 190)
		cell.TextTransparency = 0.3
		cell.Parent = grid
	end
	Build.Part({
		Name = "BackdropTrim",
		Size = Vector3.new(56.6, 0.8, 1.6),
		CFrame = CFrame.new(at(0, FLOOR_Y - 0.65 + 13.2, wallZ)),
		Color = Color3.fromRGB(214, 170, 64),
		Material = Enum.Material.Metal,
		Parent = arena,
	})

	-- Spotlights on stands at the stage's corners; their light follows the frame (client).
	local stageMid = at(0, PLAZA_Y, STAGE_Z)
	for index, spot in { { -36, -14 }, { 36, -14 }, { -35, 12 }, { 35, 12 } } do
		local base = at(spot[1], PLAZA_Y, spot[2])
		MeshLibrary.Get("SlaparazziSpotlight", {
			CFrame = CFrame.lookAt(base, Vector3.new(stageMid.X, base.Y, stageMid.Z)),
			Parent = arena,
		}).Name = "Spotlight"
			.. index
		-- The light itself: invisible, never solid or hit by rays; the client aims it at the frame.
		local holder = Build.Decor({
			Name = "SpotBeam",
			Size = Vector3.new(0.4, 0.4, 0.4),
			Transparency = 1,
			CFrame = CFrame.lookAt(base + Vector3.new(0, 7.6, 0), at(0, FLOOR_Y, STAGE_Z)),
			Parent = arena,
		})
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Angle = 30
		light.Range = 60
		light.Brightness = 3
		light.Shadows = false
		light.Color = if index % 2 == 0 then Color3.fromRGB(255, 222, 170) else Color3.fromRGB(255, 190, 235)
		light.Parent = holder
	end

	-- The photographer at the end of the carpet, and two more paparazzi beside it.
	local main = at(0, PLAZA_Y, CAMERA_Z)
	MeshLibrary.Get("SlaparazziCamera", {
		CFrame = CFrame.lookAt(main, Vector3.new(stageMid.X, main.Y, stageMid.Z)),
		Parent = arena,
	}).Name =
		"MainCamera"
	for _, side in { -1, 1 } do
		local spot = at(side * 15, PLAZA_Y, CAMERA_Z - 3)
		MeshLibrary.Get("SlaparazziCamera", {
			Scale = 0.92,
			CFrame = CFrame.lookAt(spot, Vector3.new(stageMid.X, spot.Y, stageMid.Z)),
			Parent = arena,
		}).Name =
			"Paparazzo"
	end

	-- The crowd: sections of cheering fans on risers around the plaza, out on the grass.
	for _, spot in { { -49, -16 }, { -50, 8 }, { 49, -16 }, { 50, 8 }, { -27, 46 }, { 27, 46 }, { 0, -40 } } do
		local base = at(spot[1], 0, spot[2])
		MeshLibrary.Get("SlaparazziCrowd", {
			Scale = if spot[1] == 0 then 1.3 else 1,
			CFrame = CFrame.lookAt(base, Vector3.new(stageMid.X, base.Y, stageMid.Z)),
			Parent = arena,
		})
	end
end

function Slaparazzi:_publishFrame()
	self.context:SetSharedJSON("Frame", self.frame)
end

-- Picks the frame's next spot: on the stage, well away from the last one.
function Slaparazzi:_nextSpot(): (number, number)
	local center = self.origin + Vector3.new(0, 0, STAGE_Z)
	local x0, z0 = self.frame.X1, self.frame.Z1
	local bestX, bestZ, bestD = x0, z0, -1
	for _ = 1, 16 do
		local x = center.X + rng:NextNumber(-FRAME_X, FRAME_X)
		local z = center.Z + rng:NextNumber(FRAME_Z0, FRAME_Z1)
		local d = Vector2.new(x - x0, z - z0).Magnitude
		if d >= FRAME_MOVE then
			return x, z
		end
		if d > bestD then
			bestX, bestZ, bestD = x, z, d
		end
	end
	return bestX, bestZ
end

-- The flash: scores everyone where they stood on their own screen (see the top), shares the photo.
function Slaparazzi:_snap(shotAt: number)
	local ctx = self.context
	local fx, fz = Rules.FrameAt(self.frame, shotAt)
	local entries = {}
	for _, player in ctx:GetAlivePlayers() do
		local seen = if BotRegistry.IsBot(player) then shotAt else shotAt + math.min(pingOf(player) / 2, 0.2)
		local position = self:PositionAt(player, seen)
		if not position or math.abs(position.Y - self.frame.Y) > 8 then
			continue -- no character yet, or flying high over the stage
		end
		local dx, dz = position.X - fx, position.Z - fz
		local points = Rules.PointsFor(Vector2.new(dx, dz).Magnitude)
		if points > 0 then
			self.points[player] = (self.points[player] or 0) + points
			ctx:AddScore(player, points)
			ctx:SetScoreText(player, `{self.points[player]} pts`)
		end
		if math.abs(dx) < 16 and math.abs(dz) < 16 then
			table.insert(entries, {
				U = player.UserId,
				P = points,
				X = math.floor(dx * 10 + 0.5) / 10,
				Z = math.floor(dz * 10 + 0.5) / 10,
			})
		end
	end
	table.sort(entries, function(a, b)
		return a.P > b.P
	end)
	ctx:SetSharedJSON("Photo", { N = self.photo, At = shotAt, Shots = entries })
	local best, bestPoints = nil, 0
	for player, points in self.points do
		if points > bestPoints and ctx:IsAlive(player) then
			best, bestPoints = player, points
		end
	end
	ctx:SetStatus(if best then `👑 {best.DisplayName} · {bestPoints} pts` else "Get in the photo frame!")
end

-- Whether a slap pressed now (as the server hears it) hit: the slapper's positions over half their
-- ping against the target's over their whole ping plus the drawing delay (see the top).
function Slaparazzi:_judge(player: any, target: any, now: number, lag: number): boolean
	local froms = self:SamplesSince(player, now - lag / 2 - 0.1)
	local tos = self:SamplesSince(target, now - lag - SEEN_LAG - 0.05)
	local _, _, root = self.context:GetCharacter(player)
	local _, _, targetRoot = self.context:GetCharacter(target)
	if root then
		table.insert(froms, { T = now, P = root.Position, L = root.CFrame.LookVector })
	end
	if targetRoot then
		table.insert(tos, { T = now, P = targetRoot.Position, L = targetRoot.CFrame.LookVector })
	end
	for _, from in froms do
		for _, to in tos do
			if Rules.Reaches(from.P, from.L, to.P, Rules.REACH) then
				return true
			end
		end
	end
	return false
end

function Slaparazzi:_slap(player: any, targetId: any)
	local ctx = self.context
	local now = ctx:Now()
	local lag = if BotRegistry.IsBot(player) then 0 else pingOf(player)
	local pressed = now - lag / 2
	if pressed < (self.readyAt[player] or 0) - 0.08 or (self.stunnedUntil[player] or 0) > now then
		return
	end
	local _, _, root = ctx:GetCharacter(player)
	if not root then
		return
	end
	local ready = pressed + Rules.COOLDOWN
	self.readyAt[player] = ready
	ctx:SetPlayerShared(player, "Ready", ready)
	local target = if type(targetId) == "number" and targetId == targetId then self:_participant(targetId) else nil
	local hit = target ~= nil and target ~= player and self:_judge(player, target, now, lag)
	if hit then
		local _, _, targetRoot = ctx:GetCharacter(target)
		local away = if targetRoot then targetRoot.Position - root.Position else root.CFrame.LookVector
		local flat = Vector3.new(away.X, 0, away.Z)
		if flat.Magnitude < 0.1 then
			flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		end
		if flat.Magnitude < 0.1 then
			flat = Vector3.new(0, 0, 1)
		end
		ctx:Knockback(target, flat.Unit * Rules.KNOCK + Vector3.new(0, Rules.LIFT, 0), Rules.STUN)
		self.stunnedUntil[target] = now + Rules.STUN
		self.slaps[player] = (self.slaps[player] or 0) + 1
	end
	ctx:Fire(nil, "Slap", player.UserId, if target then target.UserId else 0, hit)
end

-- A safety net under the bots: nothing shoves one faster than a slap throws it.
function Slaparazzi:_limitBots()
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

function Slaparazzi:Start()
	local ctx = self.context
	self.frame.Shot = ctx:Now() + FIRST_SHOT
	self.frame.N = 1
	self:_publishFrame()

	ctx:OnAction("Slap", function(player, targetId)
		self:_slap(player, targetId)
	end, { Interval = 0.2 })

	-- Everyone's recent positions (for fair photos and slaps).
	local sinceSample = math.huge
	ctx:Heartbeat(function(dt)
		sinceSample += dt
		if sinceSample < HISTORY_STEP then
			return
		end
		sinceSample = 0
		local now = ctx:Now()
		for _, player in ctx:GetAlivePlayers() do
			local _, _, root = ctx:GetCharacter(player)
			if not root then
				continue
			end
			local history = self.history[player]
			if not history then
				history = {}
				self.history[player] = history
			end
			table.insert(history, { T = now, P = root.Position, L = root.CFrame.LookVector })
			while #history > 2 and history[1].T < now - HISTORY_KEEP do
				table.remove(history, 1)
			end
		end
		self:_limitBots()
	end)

	-- The photos: count down, flash, score, glide the frame to its next spot.
	ctx:Loop(function(): number?
		local now = ctx:Now()
		local frame = self.frame
		if frame.Done or now < frame.Shot then
			return 0.03
		end
		local shotAt = frame.Shot
		self.photo = frame.N
		ctx:Fire(nil, "Flash", self.photo, shotAt)
		ctx:Delay(JUDGE_AFTER, function()
			self:_snap(shotAt)
		end)
		if self.photo >= PHOTOS then
			frame.Done = true
			self:_publishFrame()
			ctx:Delay(END_AFTER, function()
				ctx:End("AllPhotos")
			end)
			return nil
		end
		local x, z = self:_nextSpot()
		frame.X0, frame.Z0 = frame.X1, frame.Z1
		frame.X1, frame.Z1 = x, z
		frame.T0 = shotAt + GLIDE_AFTER
		frame.T1 = frame.T0 + GLIDE_TIME
		frame.Shot = shotAt + GAP
		frame.N = self.photo + 1
		self:_publishFrame()
		ctx:Delay(GLIDE_AFTER + GLIDE_TIME + 0.1, function()
			if self.frameModel.Parent then
				self.frameModel:PivotTo(CFrame.new(x, frame.Y + 0.03, z))
			end
		end)
		return 0.03
	end)
end

function Slaparazzi:GetResults()
	local results = self.context:ScoreResults("pts")
	for _, entry in results.Entries do
		local slaps = self.slaps[entry.Player] or 0
		entry.ScoreText = `{self.points[entry.Player] or 0} pts · {slaps} slap{if slaps == 1 then "" else "s"}`
	end
	return results
end

return Slaparazzi

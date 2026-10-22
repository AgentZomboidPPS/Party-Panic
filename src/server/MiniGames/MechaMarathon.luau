-- Mecha-Marathon (Reaction, up to 30s, 1-12 players). After "Mecha-Marathon" (Mario Party 2): every
-- player winds up a wind-up flying toy by mashing WIND for 10 seconds; then all the toys launch at
-- once and fly down their lanes, and the more yours was wound, the farther it flies. Farthest flight
-- wins. Distance boards stand every 10 m along a long, festive, sunny field.
--
-- How it works: each player has a lane with a launch pad and a toy in their color (the lane number
-- painted in front of it is the second cue). Presses of WIND (api:Action "Wind"; ctx:BotAction for
-- bots) are counted here only, during the wind time plus a little leeway for the player's ping, at
-- most Flight.RATE a second (Shared/Logic/MechaMarathonFlight.Take: a human drumming two fingers is
-- about that fast, so an auto-clicker gains nothing). Everyone's winds are shared ("Winds") a few
-- times a second, and the standings show them.
--
-- When the winding is over the server works out every flight: Flight.Meters(winds, wobble), where
-- the wobble is a little randomness under half a wind's worth either way, so it can split equal
-- winds but never flips a lead. It shares the flights ("Flights": launch time and meters per toy)
-- before lift-off, and every client flies the toys along the same path (Flight.At): the pack
-- leaves together and cruises side by side, and each toy sputters and glides down when its spring
-- runs out. The server knows when each one lands (Flight.Plan), puts its distance in the standings
-- then, and ends the round a moment after the last one is down. Results rank the exact distances.
--
-- Bots mash WIND at their own pace through ctx:BotAction (Bots/MechaMarathon.luau), through the same
-- counter as players. Nothing on the field can touch anyone (the toys are only animated on clients
-- and decide nothing), so there's no hazard to apply to bots on the server.
--
-- Sweep pass (owner: "Let's do a full bug and clean sweep."): the start banner's ★ stars drew as
-- missing-glyph boxes (the game's fonts don't have ★); they're ⭐ now.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flight = require(ReplicatedStorage.Shared.Logic.MechaMarathonFlight)

local MiniGame = require(script.Parent.Kit.MiniGame)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local MechaMarathon = MiniGame.Define("MechaMarathon", { Results = "Score", ScoreUnit = "m" })

local LANE = 9 -- lane width (studs)
local FIELD_METERS = 80 -- the field's length; the best possible flight is just under 75 m
local STAND_BACK = 6 -- where players stand behind their pads
local MAX_LEEWAY = 0.35 -- the most lag leeway a press gets after the winding ends
local CELEBRATE = 3.2 -- seconds between the last landing and the end of the round
local BUNTING_TIE = 8.25 -- where bunting is tied to a board's posts (their tops)
local BUNTING_HEIGHT = 2.47 -- the bunting mesh's height (its string ends are at the top)
local STANDS = { -14, -40 } -- grandstand middles along the first stretch (studs from the pads)

-- Lane colors (each toy, pad and landing flag; the lane number is the second cue).
local COLORS = {
	Color3.fromRGB(255, 80, 90),
	Color3.fromRGB(70, 150, 255),
	Color3.fromRGB(255, 205, 50),
	Color3.fromRGB(90, 210, 100),
	Color3.fromRGB(190, 110, 255),
	Color3.fromRGB(255, 145, 50),
	Color3.fromRGB(70, 220, 215),
	Color3.fromRGB(255, 120, 200),
	Color3.fromRGB(160, 110, 70),
	Color3.fromRGB(40, 150, 140),
	Color3.fromRGB(225, 50, 150),
	Color3.fromRGB(170, 215, 40),
}

local rng = Random.new()

type Winder = {
	Lane: number,
	X: number,
	Color: Color3,
	Winds: number,
	Shown: number, -- winds already in the score
	Tokens: number,
	At: number,
	Meters: number?,
	Gone: boolean,
	Spot: CFrame,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function color3(color: Color3): { number }
	return { math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5) }
end

-- Slack after the end of the winding for presses still on their way (part of the player's ping).
local function leewayFor(player: Player): number
	local ok, ping = pcall(function()
		return (player :: any):GetNetworkPing()
	end)
	local lag = if ok and type(ping) == "number" then ping else 0.1
	return math.clamp(lag * 0.6 + 0.05, 0.05, MAX_LEEWAY)
end

-- Scenery props here are only to look at: nothing solid where nothing is drawn (a tree's collision
-- hull is bigger than its leaves), and nobody can walk to them anyway.
local function decor(model: Instance): Instance
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	return model
end

-- Party balloons tied to a post top at `top`, bobbing a little apart.
local BALLOON_COLORS = {
	Color3.fromRGB(255, 90, 140),
	Color3.fromRGB(255, 205, 50),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(120, 220, 110),
	Color3.fromRGB(190, 120, 255),
	Color3.fromRGB(255, 140, 60),
}
local function balloonBunch(parent: Instance, top: Vector3, count: number)
	for index = 1, count do
		local angle = (index / count) * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local tilt = math.rad(rng:NextNumber(6, 14))
		decor(MeshLibrary.Get("Balloon", {
			Scale = rng:NextNumber(0.5, 0.62),
			Colors = { Balloon = BALLOON_COLORS[rng:NextInteger(1, #BALLOON_COLORS)] },
			CFrame = CFrame.new(top) * CFrame.Angles(0, angle, 0) * CFrame.Angles(tilt, 0, 0),
			Parent = parent,
		}))
	end
end

-- A flat painted strip lying on the field (lines, bands), `top` its upper face.
local function strip(
	parent: Instance,
	name: string,
	center: Vector3,
	size: Vector2,
	top: number,
	color: Color3,
	thick: number?
)
	local height = thick or 0.2
	return Build.Decor({
		Name = name,
		Size = Vector3.new(size.X, height, size.Y),
		CFrame = CFrame.new(center.X, top - height / 2, center.Z),
		Color = color,
		Parent = parent,
	})
end

-- Big painted text on the field, read from the start (the letters' tops point down the field).
local function paint(parent: Instance, text: string, center: Vector3, size: Vector2, top: number, color: Color3)
	local part = Build.Decor({
		Name = "Paint",
		Size = Vector3.new(size.X, 0.1, size.Y),
		CFrame = CFrame.new(center.X, top - 0.05, center.Z),
		Transparency = 1,
		Parent = parent,
	})
	local label = Build.SurfaceText(part, Enum.NormalId.Top, text, {
		PixelsPerStud = 12,
		TextColor3 = color,
		TextStrokeTransparency = 1,
		Brightness = 1,
		LightInfluence = 1,
		MaxDistance = 400,
	})
	label.Font = Enum.Font.FredokaOne
	return part
end

-- The field: a long mowed strip with lane lines, a start line, a line and painted distance every
-- 10 m, boards on both sides with bunting strung between them, a start gantry, trees, hot air
-- balloons and hills far away.
local function buildField(ctx, origin: Vector3, laneCount: number)
	local arena = ctx.Arena
	local ground = origin.Y
	local spm = Flight.STUDS_PER_METER
	local length = FIELD_METERS * spm
	local lanes = math.max(laneCount, 4)
	local half = lanes * LANE / 2 + 2 -- half the mowed track's width
	local trackBack = STAND_BACK + 8 -- the track runs from behind the players...
	local trackEnd = length + 16 -- ...to past the last board
	local field = Build.Folder("Field", arena)

	-- Grass out to the hills, its top a little under the track's (it stops short of the lobby, far
	-- below: the field runs toward it).
	Build.Part({
		Name = "Grass",
		Size = Vector3.new(1200, 4, 960),
		CFrame = CFrame.new(origin.X, ground - 0.35 - 2, origin.Z - 320),
		Color = rgb(104, 186, 80),
		Material = Enum.Material.Grass,
		CastShadow = false,
		Parent = field,
	})
	-- Mowed bands every 5 m (they stream past under the toys), light and dark.
	local band = 5 * spm
	local z = origin.Z + trackBack
	local index = 0
	while z > origin.Z - trackEnd do
		local bandLength = math.min(band, z - (origin.Z - trackEnd))
		Build.Part({
			Name = "Track",
			Size = Vector3.new(half * 2, 0.6, bandLength),
			CFrame = CFrame.new(origin.X, ground - 0.3, z - bandLength / 2),
			Color = if index % 2 == 0 then rgb(122, 204, 92) else rgb(104, 184, 80),
			Material = Enum.Material.Grass,
			CastShadow = false,
			Parent = field,
		})
		z -= bandLength
		index += 1
	end
	local white = rgb(250, 250, 245)
	-- Curbs along both edges, lane lines, the start line.
	for _, side in { -1, 1 } do
		strip(
			field,
			"Curb",
			Vector3.new(origin.X + side * (half - 0.4), 0, origin.Z + trackBack / 2 - trackEnd / 2),
			Vector2.new(0.8, trackBack + trackEnd),
			ground + 0.12,
			white,
			0.4
		)
	end
	for line = 0, laneCount do
		local x = origin.X + (line - laneCount / 2) * LANE
		if math.abs(x - origin.X) < half - 1.5 then
			strip(
				field,
				"LaneLine",
				Vector3.new(x, 0, origin.Z - 3 - length / 2),
				Vector2.new(0.3, length),
				ground + 0.05,
				white
			)
		end
	end
	strip(
		field,
		"StartLine",
		Vector3.new(origin.X, 0, origin.Z - 3),
		Vector2.new(half * 2 - 1.6, 1),
		ground + 0.08,
		white
	)

	-- Every 10 m: a line across, the distance painted at both edges and a board on each side.
	local signs = {}
	for meters = Flight.MARKER, FIELD_METERS, Flight.MARKER do
		local markZ = origin.Z - meters * spm
		strip(field, "Marker", Vector3.new(origin.X, 0, markZ), Vector2.new(half * 2 - 1.6, 0.7), ground + 0.09, white)
		for _, side in { -1, 1 } do
			paint(
				field,
				`{meters} m`,
				Vector3.new(origin.X + side * (half - 6.5), 0, markZ - 3),
				Vector2.new(9, 4.5),
				ground + 0.13,
				white
			)
			local base = Vector3.new(origin.X + side * (half + 4.5), ground, markZ)
			local sign = MeshLibrary.Get("MechaMarathonSign", {
				Colors = { Frame = if (meters // Flight.MARKER) % 2 == 0 then rgb(255, 190, 40) else rgb(255, 110, 80) },
				CFrame = CFrame.new(base) * CFrame.Angles(0, math.pi, 0), -- the board faces the start
				Parent = field,
			})
			-- The number on a plain panel just in front of the mesh board (so it reads the same
			-- whether the mesh or its fallback is used).
			local face = Build.Decor({
				Name = "SignFace",
				Size = Vector3.new(5.6, 2.6, 0.1),
				CFrame = CFrame.new(base + Vector3.new(0, 6.15, 0.32)),
				Color = white,
				Parent = sign,
			})
			Build.SurfaceText(face, Enum.NormalId.Back, `{meters} m`, {
				TextColor3 = rgb(40, 50, 80),
				TextStrokeTransparency = 1,
				PixelsPerStud = 24,
				MaxDistance = 500,
			}).Font =
				Enum.Font.FredokaOne
			signs[side] = signs[side] or {}
			table.insert(signs[side], base)
			balloonBunch(field, base + Vector3.new(side * 2.35, 8.3, 0), 2)
		end
	end
	-- Bunting from board to board along both sides, tied to the outer posts' tops.
	for _, side in { -1, 1 } do
		local list = signs[side]
		for i = 1, #list - 1 do
			local from, to = list[i], list[i + 1]
			MeshLibrary.Get("MechaMarathonBunting", {
				CFrame = CFrame.new((from + to) / 2 + Vector3.new(side * 2.35, BUNTING_TIE - BUNTING_HEIGHT, 0)),
				Parent = field,
			})
		end
	end

	-- The start gantry: striped towers either side with a banner high over the pads.
	for _, side in { -1, 1 } do
		MeshLibrary.Get("MechaMarathonTower", {
			CFrame = CFrame.new(origin.X + side * (half + 3), ground, origin.Z - 3),
			Parent = field,
		})
		balloonBunch(field, Vector3.new(origin.X + side * (half + 3), ground + 18.2, origin.Z - 3), 3)
	end

	-- Grandstands full of fans along the first stretch, facing the track.
	local stands = Build.Folder("Stands", field)
	for _, side in { -1, 1 } do
		for _, standZ in STANDS do
			MeshLibrary.Get("MechaMarathonStand", {
				Colors = { Seats = if side < 0 then rgb(70, 150, 255) else rgb(255, 110, 80) },
				CFrame = CFrame.new(origin.X + side * (half + 13.6), ground - 0.33, origin.Z + standZ)
					* CFrame.Angles(0, side * math.pi / 2, 0), -- facing the track
				Parent = stands,
			})
		end
	end
	local banner = Build.Decor({
		Name = "Banner",
		Size = Vector3.new(half * 2 + 6, 3.2, 0.4),
		CFrame = CFrame.new(origin.X, ground + 17, origin.Z - 3),
		Color = rgb(255, 90, 90),
		Material = Enum.Material.Fabric,
		CastShadow = true,
		Parent = field,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		Build.SurfaceText(banner, face, "⭐  WIND · FLY · WIN!  ⭐", {
			TextColor3 = rgb(255, 250, 235),
			TextStrokeTransparency = 0.6,
			PixelsPerStud = 14,
			MaxDistance = 500,
		}).Font =
			Enum.Font.FredokaOne
	end

	-- Trees and flowering bushes along both sides, beyond the boards.
	local leafColors = { rgb(80, 190, 90), rgb(110, 200, 80), rgb(70, 165, 95), rgb(140, 205, 85) }
	local flowerColors = { rgb(255, 130, 190), rgb(255, 220, 90), rgb(180, 140, 255), rgb(255, 255, 255) }
	for _, side in { -1, 1 } do
		local treeZ = origin.Z + 40
		while treeZ > origin.Z - trackEnd - 60 do
			for column = 0, 1 do
				-- (the near row steps back behind the grandstands)
				local behindStands = treeZ > origin.Z - 60 and treeZ < origin.Z + 6
				local x = origin.X
					+ side * (half + 24 + column * 22 + (if behindStands then 10 else 0) + rng:NextNumber(-5, 5))
				decor(MeshLibrary.Get("Tree", {
					Scale = rng:NextNumber(1.6, 2.6),
					Colors = { Leaves = leafColors[rng:NextInteger(1, #leafColors)] },
					CFrame = CFrame.new(x, ground - 0.3, treeZ + rng:NextNumber(-8, 8))
						* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
					Parent = field,
				}))
			end
			treeZ -= rng:NextNumber(24, 32)
		end
		local bushZ = origin.Z - 64
		while bushZ > origin.Z - trackEnd do
			decor(MeshLibrary.Get("Bush", {
				Scale = rng:NextNumber(1.1, 1.7),
				Colors = { Flowers = flowerColors[rng:NextInteger(1, #flowerColors)] },
				CFrame = CFrame.new(origin.X + side * (half + 12 + rng:NextNumber(-1.5, 1.5)), ground - 0.3, bushZ)
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = field,
			}))
			bushZ -= rng:NextNumber(26, 40)
		end
	end

	-- Hot air balloons over the far field.
	local balloons = {
		{ -90, 52, 140, rgb(255, 90, 90) },
		{ 115, 70, 250, rgb(70, 160, 255) },
		{ -150, 84, 380, rgb(255, 200, 60) },
		{ 70, 96, 470, rgb(130, 220, 120) },
		{ -40, 64, 560, rgb(200, 120, 255) },
	}
	for _, spec in balloons do
		MeshLibrary.Get("MechaMarathonSkyBalloon", {
			Scale = rng:NextNumber(1.1, 1.5),
			Colors = { StripesA = spec[4] },
			CFrame = CFrame.new(origin.X + spec[1], ground + spec[2], origin.Z - spec[3])
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = field,
		})
	end
	-- Soft hills on the horizon ahead and to the sides (squashed spheres half sunk into the grass).
	for hill = 0, 8 do
		local angle = math.rad(-150 + hill * 15 + rng:NextNumber(-4, 4))
		local distance = rng:NextNumber(440, 500)
		local size = Vector3.new(rng:NextNumber(170, 250), rng:NextNumber(60, 100), rng:NextNumber(120, 170))
		local center = Vector3.new(
			origin.X + math.cos(angle) * distance,
			ground - size.Y * 0.2,
			origin.Z - length / 2 + math.sin(angle) * distance
		)
		local part = Build.Decor({
			Name = "Hill",
			Size = size,
			CFrame = CFrame.lookAt(center, Vector3.new(origin.X, center.Y, origin.Z - length / 2)),
			Color = rgb(96, 176, 86):Lerp(rgb(70, 140, 90), rng:NextNumber(0, 1)),
			Material = Enum.Material.Grass,
			Parent = field,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	return half
end

function MechaMarathon:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn" -- nothing knocks anyone out; a fall just puts you back
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 30
	local origin = ctx.Origin.Position
	self.winders = {} :: { [any]: Winder }
	self.phase = "Ready"
	self.windStart = math.huge
	self.windEnd = math.huge
	self.launchAt = math.huge

	local players = ctx:GetPlayers()
	for index = #players, 2, -1 do -- lanes in a random order
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local count = #players
	buildField(ctx, origin, count)

	local toys = Build.Folder("Toys", ctx.Arena)
	local lanes = {}
	local points = {}
	for index, player in players do
		local x = origin.X + (index - (count + 1) / 2) * LANE
		local color = COLORS[(index - 1) % #COLORS + 1]
		local padAt = Vector3.new(x, origin.Y, origin.Z)
		MeshLibrary.Get("MechaMarathonPad", {
			Colors = { Top = color },
			CFrame = CFrame.new(padAt),
			Parent = ctx.Arena,
		})
		local toy = MeshLibrary.Get("MechaMarathonFlyer", {
			Colors = { Body = color },
			CFrame = CFrame.new(padAt + Vector3.new(0, Flight.PAD, 0)),
			Parent = toys,
		})
		toy.Name = "Toy_" .. player.UserId
		toy:SetAttribute("User", player.UserId)
		toy:SetAttribute("Lane", index)
		-- The lane number, painted big on the field in front of the pad.
		local tile = Build.Decor({
			Name = "LaneTile",
			Size = Vector3.new(4.4, 0.16, 4.4),
			CFrame = CFrame.new(x, origin.Y + 0.08, origin.Z - 7),
			Color = rgb(250, 250, 245),
			Parent = ctx.Arena,
		})
		Build.SurfaceText(tile, Enum.NormalId.Top, tostring(index), {
			TextColor3 = rgb(40, 50, 80), -- dark ink on the white tile, ringed in the lane's color
			TextStrokeColor3 = color,
			TextStrokeTransparency = 0,
			PixelsPerStud = 16,
			LightInfluence = 1,
			Brightness = 1,
		}).Font =
			Enum.Font.FredokaOne

		local spot =
			CFrame.lookAt(Vector3.new(x, origin.Y, origin.Z + STAND_BACK), Vector3.new(x, origin.Y, origin.Z - 10))
		table.insert(points, spot)
		self.winders[player] = {
			Lane = index,
			X = x,
			Color = color,
			Winds = 0,
			Shown = 0,
			Tokens = 1,
			At = 0,
			Meters = nil,
			Gone = false,
			Spot = spot,
		}
		table.insert(lanes, {
			User = player.UserId,
			Lane = index,
			X = x,
			Color = color3(color),
			Name = player.DisplayName,
		})
	end
	ctx:ShareTemplate("MechaMarathonFlag", MeshLibrary.Get("MechaMarathonFlag"))
	ctx:SetSharedJSON("Layout", {
		Lanes = lanes,
		Origin = { origin.X, origin.Y, origin.Z },
		Field = FIELD_METERS,
	})
	ctx:SetShared("Stage", "Ready")

	-- SpawnAll hands out points in ctx:GetPlayers() order, not the shuffled lane order.
	local ordered = {}
	for _, player in ctx:GetPlayers() do
		local winder = self.winders[player]
		table.insert(ordered, if winder then winder.Spot else points[1])
	end
	ctx:SpawnAll(ordered, true)
	ctx.Hooks.Respawn = function(player)
		local winder = self.winders[player]
		return if winder then winder.Spot else nil
	end
	for _, player in players do
		ctx:SetScoreText(player, "0 winds")
	end
	ctx:SetStatus("Mash WIND to wind up your toy!")
	ctx.Hooks.PlayerLeft = function(player)
		self:_leave(player)
	end
end

function MechaMarathon:_leave(player)
	local winder = self.winders[player]
	if winder and not winder.Gone then
		winder.Gone = true
		local gone = {}
		for other, entry in self.winders do
			if entry.Gone then
				table.insert(gone, other.UserId)
			end
		end
		self.context:SetSharedJSON("Gone", gone)
	end
end

-- One press of WIND. Counted only during the winding (plus the player's leeway for presses still on
-- their way when it ended), and at most Flight.RATE a second (Flight.Take).
function MechaMarathon:_wind(player)
	local winder = self.winders[player]
	if not winder or winder.Gone or self.phase ~= "Wind" then
		return
	end
	local now = self.context:Now()
	if now < self.windStart or now > self.windEnd + leewayFor(player) then
		return
	end
	if winder.Winds < Flight.MAX_WINDS and Flight.Take(winder, now) then
		winder.Winds += 1
	end
end

-- Shares everyone's winds and puts them in the standings (a few times a second, not every press).
function MechaMarathon:_publish()
	local ctx = self.context
	local winds = {}
	local changed = false
	for player, winder in self.winders do
		winds[tostring(player.UserId)] = winder.Winds
		if winder.Winds ~= winder.Shown and ctx:State(player) then
			ctx:AddScore(player, winder.Winds - winder.Shown)
			ctx:SetScoreText(player, `{winder.Winds} winds`)
			winder.Shown = winder.Winds
			changed = true
		end
	end
	if changed or not self.published then
		self.published = true
		ctx:SetSharedJSON("Winds", winds)
	end
end

function MechaMarathon:Start()
	local ctx = self.context
	local now = ctx:Now()
	self.windStart = now
	self.windEnd = now + Flight.WIND_TIME
	self.phase = "Wind"
	for player, winder in self.winders do
		winder.At = now
		winder.Tokens = 1
		if not ctx:State(player) then
			self:_leave(player) -- left (or never got a character) before GO
		end
	end
	ctx:SetShared("WindEnd", self.windEnd)
	ctx:SetShared("Stage", "Wind")
	-- Everyone stays at their pad (jumping still works, for joy).
	for _, player in ctx:GetPlayers() do
		ctx:SetWalkSpeed(player, 0)
	end
	ctx.Hooks.CharacterReady = function(player)
		ctx:SetWalkSpeed(player, 0)
	end
	-- Every press counts on its own (the counter above limits the rate), so no minimum interval:
	-- presses that arrive bunched together after a lag spike aren't thrown away.
	ctx:OnAction("Wind", function(player)
		self:_wind(player)
	end, { Interval = 0 })

	local lastSecond = -1
	ctx:Loop(function(): number?
		local time = ctx:Now()
		if self.phase == "Wind" then
			self:_publish()
			local left = math.ceil(self.windEnd - time)
			if left ~= lastSecond and left >= 1 then
				lastSecond = left
				ctx:SetStatus(`WIND IT UP! {left}s`)
			end
			if time >= self.windEnd + MAX_LEEWAY then
				self:_publish()
				self:_launch()
			end
		end
		return 0.2
	end)
end

-- The winding is over: work out every flight, share it before lift-off and schedule the landings.
function MechaMarathon:_launch()
	local ctx = self.context
	self.phase = "Launch"
	local now = ctx:Now()
	self.launchAt = self.windEnd + Flight.LAUNCH_DELAY
	local toys = {}
	local last = 0
	local taken = {}
	for player, winder in self.winders do
		if winder.Gone then
			continue
		end
		-- The wobble, nudged a centimeter at a time until no other toy lands on exactly the same
		-- spot (so there are no ties to split); the draw leaves room for the nudge under WOBBLE.
		local wobble = rng:NextNumber(-Flight.WOBBLE + 0.07, Flight.WOBBLE - 0.07)
		local meters = Flight.Meters(winder.Winds, wobble)
		local step = 0
		while taken[meters] and step < 12 do
			step += 1
			meters =
				Flight.Meters(winder.Winds, wobble + (if step % 2 == 1 then 1 else -1) * math.ceil(step / 2) * 0.01)
		end
		taken[meters] = true
		winder.Meters = meters
		local plan = Flight.Plan(winder.Meters :: number)
		toys[tostring(player.UserId)] = { M = winder.Meters, W = winder.Winds, S = rng:NextInteger(1, 9999) }
		last = math.max(last, plan.Total)
		ctx:Delay(math.max(self.launchAt + plan.Total - now, 0), function()
			if ctx:State(player) then
				ctx:SetScoreText(player, string.format("%.2f m", winder.Meters :: number))
			end
		end)
	end
	ctx:SetSharedJSON("Flights", { LaunchAt = self.launchAt, Toys = toys })
	ctx:SetShared("Stage", "Launch")
	ctx:SetStatus("Ready... LAUNCH!")
	ctx:Delay(math.max(self.launchAt - now, 0), function()
		self.phase = "Flight"
		ctx:SetShared("Stage", "Flight")
		ctx:SetStatus("Fly, fly, fly!")
	end)
	ctx:Delay(math.max(self.launchAt + last - now, 0) + 0.2, function()
		self:_finish()
	end)
	ctx:Delay(math.max(self.launchAt + last - now, 0) + CELEBRATE, function()
		ctx:End("Landed")
	end)
end

-- The best flight among players still here (nil with nobody left).
function MechaMarathon:_best(): (any, number)
	local best, bestMeters = nil, -1
	for player, winder in self.winders do
		if winder.Meters and not winder.Gone and self.context:State(player) and winder.Meters > bestMeters then
			best, bestMeters = player, winder.Meters
		end
	end
	return best, bestMeters
end

function MechaMarathon:_finish()
	local ctx = self.context
	self.phase = "Done"
	ctx:SetShared("Stage", "Done")
	local best, meters = self:_best()
	if best then
		ctx:SetShared("Winner", best.UserId)
		ctx:SetStatus(`🏆 {best.DisplayName}: {string.format("%.2f", meters)} m!`)
		ctx:Announce(`🏆 {best.DisplayName} flew {string.format("%.2f", meters)} m!`, "success", 3)
	end
end

-- Farthest flight first (exact distances); before the launch, the distance the winds were worth.
function MechaMarathon:GetResults()
	local ctx = self.context
	local entries = {}
	for player in ctx.Participants do
		if not player.Parent then
			continue
		end
		local winder = self.winders[player]
		local meters = 0
		if winder then
			meters = winder.Meters or Flight.Meters(winder.Winds, 0)
		end
		table.insert(entries, {
			Player = player,
			Rank = meters,
			ScoreText = string.format("%.2f m", meters),
			BestScore = meters,
		})
	end
	return { Entries = entries }
end

return MechaMarathon

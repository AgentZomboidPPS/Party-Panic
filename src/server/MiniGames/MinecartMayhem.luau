-- Minecart Mayhem (Race, up to 90 s, 1-12 players). Owner's pitch (2026-10-22): "race mine carts
-- through a cave. At every split you pick left or right; some routes are shortcuts, some are dead
-- ends, and a TNT track blows you off. You also jump gaps and lean into curves, and the first cart
-- out of the mine wins. It works well on phones with just left, right and jump." After the classic
-- mine-cart levels, with an original look: a crystal cave crossed on wooden trestles.
--
-- How it works: every rider has a cart that rolls by itself along the rails (faster downhill,
-- slower uphill). The server rides every cart (Shared/Logic/MinecartMayhemTrack: Ride) from the
-- riders' inputs only: LEFT / RIGHT (api:Action "Lean", -1 / 0 / 1, with the moment it was pressed on
-- the player's screen) and JUMP (api:Action "Jump", with its moment). It shares every cart's place
-- ("Riders", 10 times a second) and clients draw the carts from that (each player's own client also
-- predicts its own cart and seats its own character in it; bots are seated by the server here).
--
-- The course (Track.Generate) is shuffled every round: five junctions, three broken bridges, two
-- bends and a hill in a new order, and at each junction which side is the long safe way and what the
-- other way is (a shortcut, a dead end or a TNT track). The server owns the layout and shares it
-- ("Layout"); signs at each switch say what's down each way with an icon AND a word (★ FAST, ● SAFE,
-- ☠ TNT, ✖ DEAD END), never colour alone, and the ways themselves show it too (a light at the far
-- end of a shortcut, crates and a skull down a TNT track, a buffer stop and rubble at a dead end).
--
-- Fair presses (owner: "the precision games will feel super bad if we dont"): everything a press
-- decides waits out that rider's ping before it's judged, and is judged by when it was pressed on
-- their screen (clamped to at most MAX_LEEWAY ago). A switch takes the side of the latest press
-- made near it, up to Track.GRACE after the cart's front reached it (Track.Choose); a gap is cleared
-- only if the jump holds the whole cart, wheel to wheel, over it (Track.Clears); a crystal dashes
-- unless the cart was in the air over it.
--
-- Hazard parity: bots press LEFT, RIGHT and JUMP through ctx:BotAction (Bots/MinecartMayhem.luau)
-- and every cart is ridden and judged here, so TNT, dead ends and gaps catch bots exactly like
-- players. The race freezes the moment it closes (no riding, no input, bots stop); carts home in the
-- same step take places by the exact moment they crossed; the results leave out riders who left
-- and renumber the rest. Nothing is solid but the station deck the riders start over: every rail,
-- trestle, rock and prop is decoration (riders are carried by the game, never by physics).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Track = require(ReplicatedStorage.Shared.Logic.MinecartMayhemTrack)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local MinecartMayhem = MiniGame.Define("MinecartMayhem", { Results = "Score" })

local FINISH_CLOCK = 12 -- seconds the finish stays open after the first cart is out
local MAX_LEEWAY = 0.4
local SEAT_Y = 1.15 -- a seated rider's root above a standing one's, relative to the cart's floor
local CART_FLOOR = 1.1 -- the cart's floor above the rail line
local CAVE_STEP = 44 -- studs between the cave's rock rings

-- Cart trims, one per start lane (the lane number on the cart's badge is the second cue).
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
	Color3.fromRGB(250, 250, 250),
	Color3.fromRGB(225, 50, 150),
	Color3.fromRGB(170, 215, 40),
}

-- What each way's sign says (icon and word: never colour alone).
local HINTS = {
	Long = { Icon = "●", Word = "SAFE", Color = Color3.fromRGB(120, 200, 255) },
	Short = { Icon = "★", Word = "FAST", Color = Color3.fromRGB(255, 215, 80) },
	Dead = { Icon = "✖", Word = "DEAD END", Color = Color3.fromRGB(230, 230, 230) },
	TNT = { Icon = "☠", Word = "TNT", Color = Color3.fromRGB(255, 90, 70) },
}

local RAIL_PROPS = {
	Start = "MinecartMayhemRailStart",
	Gap = "MinecartMayhemRailGap",
	Hill = "MinecartMayhemRailHill",
	Finish = "MinecartMayhemRailFinish",
}

local rng = Random.new()

type Pending = { K: string, At: number, Tile: number, V: number, Gap: number?, JudgeAt: number }

type Rider = Track.Rider & {
	Player: any,
	Lane: number,
	Picks: { Track.Pick },
	ZoneAt: { [number]: number },
	Pending: { Pending },
	DownKind: string?,
	Place: number?,
	Shown: number,
	Falls: number,
	Blasts: number,
	Bumps: number,
	Dashes: number,
	Shortcuts: number,
	Gone: boolean,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function color3(color: Color3): { number }
	return { math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5) }
end

local function round(value: number, step: number): number
	return math.floor(value / step + 0.5) * step
end

-- How long after a moment the server waits for a press still on its way (part of the ping).
local function leewayFor(player: any): number
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	local lag = if ok and type(ping) == "number" then ping else 0.1
	return math.clamp(lag + 0.06, 0.06, MAX_LEEWAY)
end

-- Scenery only to look at: nothing solid where nothing is drawn.
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

-- The world frame of a cart (its rail-line point, facing along the rails) and nothing else.
function MinecartMayhem:_frame(tileIndex: number, branch: number, s: number, lane: number?): CFrame
	local tile = self.course.Tiles[tileIndex]
	local path = tile.Paths[branch] or tile.Paths[1]
	local x, y, z, hx, hy, hz = Track.At(path, s)
	local position = self.origin + Vector3.new(x, y, z)
	local frame = CFrame.lookAt(position, position + Vector3.new(hx, hy, hz))
	if lane and tileIndex == 1 then
		frame = CFrame.new(position + frame.RightVector * Track.StartOffset(lane, s)) * frame.Rotation
	end
	return frame
end

-- A point on the main way of a tile, `f` forward studs in, `x` to the side and `y` up (tile axes).
function MinecartMayhem:_tilePoint(tile: Track.BuiltTile, f: number, x: number?, y: number?, branch: number?): CFrame
	local sx, sy = Track.Shape(tile, branch or 1, f)
	local entry = tile.Entry
	return CFrame.new(
		self.origin + Vector3.new(entry[1] + sx + (x or 0), entry[2] + sy + (y or 0), entry[3] - f)
	)
end

-- A sign board on a post with a surface text on its front (toward riders coming down the mine).
function MinecartMayhem:_board(parent: Instance, at: CFrame, width: number, lines: string, color: Color3)
	local board = Build.Decor({
		Name = "SignBoard",
		Size = Vector3.new(width, 2.6, 0.4),
		CFrame = at,
		Color = rgb(92, 62, 38),
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	local label = Build.SurfaceText(board, Enum.NormalId.Back, lines, {
		TextColor3 = color,
		TextStrokeColor3 = rgb(20, 14, 10),
		TextStrokeTransparency = 0,
		PixelsPerStud = 24,
		LightInfluence = 0,
		Brightness = 1.4,
		MaxDistance = 260,
	})
	label.Font = Enum.Font.FredokaOne
	return board
end

function MinecartMayhem:_buildArena()
	local ctx = self.context
	local arena = ctx.Arena
	local origin = self.origin
	local course = self.course
	local mine = Build.Folder("Mine", arena)
	local props = Build.Folder("Props", arena)

	-- Rails, ties and trestles: one mesh per tile, placed by its pivot relative to its entry.
	for _, tile in course.Tiles do
		local name = RAIL_PROPS[tile.K]
		if tile.K == "Bend" then
			name = if (tile.D or 1) < 0 then "MinecartMayhemRailBendL" else "MinecartMayhemRailBendR"
		elseif tile.K == "Junction" then
			name = if (tile.L or 1) < 0 then "MinecartMayhemRailJunctionL" else "MinecartMayhemRailJunctionR"
		end
		local anchor = Track.Anchor[name]
		local entry = tile.Entry
		local model = MeshLibrary.Get(name, {
			CFrame = CFrame.new(origin + Vector3.new(entry[1] + anchor[1], entry[2] + anchor[2], entry[3] + anchor[3])),
			Parent = mine,
		})
		model.Name = "Rails" .. tile.Index
	end

	-- The station deck the riders start over (the only solid thing: it's drawn, and it's under them),
	-- and the mine's entrance just past it.
	local first = course.Tiles[1]
	local deckTop = origin.Y - 0.1
	Build.Part({
		Name = "StationDeck",
		Size = Vector3.new(76, 1.2, 44),
		CFrame = CFrame.new(origin.X, deckTop - 0.6, origin.Z - 8),
		Color = rgb(120, 84, 52),
		Material = Enum.Material.WoodPlanks,
		Parent = mine,
	})
	MeshLibrary.Get("MinecartMayhemPortal", {
		CFrame = self:_tilePoint(first, 58, 0, -46),
		Parent = mine,
	}).Name =
		"Entrance"
	-- (a sunny meadow in front of the mine, far below the deck's edge, and some trees)
	local meadow = Build.Decor({
		Name = "Meadow",
		Size = Vector3.new(420, 4, 200),
		CFrame = CFrame.new(origin.X, origin.Y - 48, origin.Z + 70),
		Color = rgb(104, 176, 82),
		Material = Enum.Material.Grass,
		Parent = mine,
	})
	meadow.CastShadow = false

	-- The way out into daylight and the FINISH banner over the line.
	local last = course.Tiles[#course.Tiles]
	local exitAt = self:_tilePoint(last, Track.FINISH_AT + 2, 0, -46)
	local exitPortal = MeshLibrary.Get("MinecartMayhemPortal", {
		CFrame = exitAt * CFrame.Angles(0, math.pi, 0), -- (its face toward the riders coming out)
		Parent = mine,
	})
	exitPortal.Name = "Exit"
	local bannerAt = self:_tilePoint(last, Track.FINISH_AT, 0, 9.5)
	local banner = Build.Decor({
		Name = "FinishBanner",
		Size = Vector3.new(16, 3.4, 0.3),
		CFrame = bannerAt,
		Color = rgb(255, 250, 235),
		Parent = mine,
	})
	for _, face in { Enum.NormalId.Back, Enum.NormalId.Front } do
		Build.SurfaceText(banner, face, "🏁 FINISH 🏁", {
			TextColor3 = rgb(225, 50, 70),
			TextStrokeColor3 = rgb(255, 255, 255),
			TextStrokeTransparency = 0.2,
			PixelsPerStud = 16,
			MaxDistance = 600,
		}).Font =
			Enum.Font.FredokaOne
	end
	for _, side in { -1, 1 } do
		Build.Decor({
			Name = "BannerPole",
			Size = Vector3.new(0.5, 13, 0.5),
			CFrame = self:_tilePoint(last, Track.FINISH_AT, side * 8.2, 5),
			Color = rgb(92, 62, 38),
			Material = Enum.Material.Wood,
			Parent = mine,
		})
	end
	local finishLine = Build.Decor({
		Name = "FinishLine",
		Size = Vector3.new(5.4, 0.1, 1.2),
		CFrame = self:_tilePoint(last, Track.FINISH_AT, 0, Track.RAIL_TOP - 0.25),
		Color = rgb(250, 250, 250),
		Material = Enum.Material.Neon,
		Parent = mine,
	})
	finishLine.CastShadow = false
	local outside = Build.Decor({
		Name = "Daylight",
		Size = Vector3.new(420, 4, 260),
		CFrame = self:_tilePoint(last, last.Len + 60, 0, -50),
		Color = rgb(104, 176, 82),
		Material = Enum.Material.Grass,
		Parent = mine,
	})
	outside.CastShadow = false
	for k = 1, 10 do
		local side = if k % 2 == 0 then 1 else -1
		decor(MeshLibrary.Get("Tree", {
			Scale = rng:NextNumber(1.8, 2.6),
			CFrame = self:_tilePoint(last, last.Len + rng:NextNumber(10, 140), side * rng:NextNumber(24, 120), -48)
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = mine,
		}))
	end

	-- The cave: rock rings along the way (centred between the ways of a junction), a dark floor far
	-- below with glowing crystal clusters, crystals in the walls.
	local cave = Build.Folder("Cave", arena)
	local total = 0
	for _, tile in course.Tiles do
		total += tile.Len
	end
	local startF, endF = 70, total - (last.Len - Track.FINISH_AT) - 16
	local f = startF
	local flip = false
	while f < endF do
		-- (find the tile at forward stud f)
		local tile, local_f = course.Tiles[1], f
		for _, candidate in course.Tiles do
			if local_f <= candidate.Len then
				tile = candidate
				break
			end
			local_f -= candidate.Len
		end
		local x1, y1 = Track.Shape(tile, 1, local_f)
		local x2 = x1
		if tile.Paths[2] then
			x2 = Track.Shape(tile, 2, local_f)
		end
		local entry = tile.Entry
		local center = self.origin
			+ Vector3.new(entry[1] + (x1 + x2) / 2, entry[2] + y1 - 54, entry[3] - local_f)
		flip = not flip
		MeshLibrary.Get("MinecartMayhemCave", {
			CFrame = CFrame.new(center) * CFrame.Angles(0, if flip then math.pi else 0, 0),
			Parent = cave,
		})
		f += CAVE_STEP
	end
	local lowest = math.huge
	for _, tile in course.Tiles do
		lowest = math.min(lowest, tile.Entry[2])
	end
	local floorY = origin.Y + lowest - 56
	local floor = Build.Decor({
		Name = "CaveFloor",
		Size = Vector3.new(220, 4, total - 60),
		CFrame = CFrame.new(origin.X, floorY - 2, origin.Z - 30 - (total - 60) / 2),
		Color = rgb(38, 32, 48),
		Material = Enum.Material.Slate,
		Parent = cave,
	})
	floor.CastShadow = false
	local crystalColors = { rgb(120, 220, 255), rgb(200, 120, 255), rgb(110, 255, 190), rgb(255, 140, 220) }
	for k = 1, 26 do
		local along = 90 + (k - 0.5) / 26 * (total - 200)
		local side = if k % 2 == 0 then 1 else -1
		MeshLibrary.Get("MinecartMayhemCluster", {
			Scale = rng:NextNumber(1.2, 2.4),
			Colors = { Crystal = crystalColors[rng:NextInteger(1, #crystalColors)] },
			CFrame = CFrame.new(origin.X + side * rng:NextNumber(20, 70), floorY, origin.Z - along)
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = cave,
		})
	end

	-- Lanterns on posts beside the main line every so often, some with a light.
	local lit = 0
	for _, tile in course.Tiles do
		if tile.K == "Junction" or tile.K == "Start" then
			continue
		end
		for _, at in { 12, tile.Len - 20 } do
			local side = if (tile.Index + at) % 2 == 0 then 1 else -1
			local lantern = MeshLibrary.Get("MinecartMayhemLantern", {
				CFrame = self:_tilePoint(tile, at, side * 3.6, 0.2) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
				Parent = props,
			})
			local glass = lantern:FindFirstChild("Glow", true)
			if glass and glass:IsA("BasePart") and lit < 18 then
				lit += 1
				Build.Light(glass, rgb(255, 190, 110), 26, 1.6)
			end
		end
	end

	-- Every junction: the sign before the switch, a board down each way, and what's down there.
	for _, tile in course.Tiles do
		if tile.K ~= "Junction" then
			continue
		end
		local longSide = tile.L or 1
		local kinds = { [longSide] = "Long", [-longSide] = tile.O or "Short" }
		local signAt = self:_tilePoint(tile, Track.SPLIT - 30, 0, 0)
		local sign = Build.Folder("JunctionSign" .. tile.Index, props)
		MeshLibrary.Get("MinecartMayhemSign", { CFrame = signAt, Parent = sign })
		for _, side in { -1, 1 } do
			local hint = HINTS[kinds[side]]
			local arrow = if side < 0 then "◀" else "▶"
			local text = if side < 0 then `{arrow} {hint.Icon} {hint.Word}` else `{hint.Icon} {hint.Word} {arrow}`
			self:_board(sign, signAt * CFrame.new(side * 3.6, 8.2, 0), 7, text, hint.Color)
		end
		-- (the board at the start of each way, and its tell-tale)
		for _, side in { -1, 1 } do
			local branch = if side == longSide then 1 else 2
			local kind = kinds[side]
			local hint = HINTS[kind]
			local postAt = self:_tilePoint(tile, Track.SPLIT + 16, side * 4.2, 0, branch)
			MeshLibrary.Get("MinecartMayhemPost", { CFrame = postAt, Parent = props })
			self:_board(props, postAt * CFrame.new(0, 5.6, 0), 4.2, `{hint.Icon} {hint.Word}`, hint.Color)
		end
		local span = Track.MERGE - Track.SPLIT
		local otherSide = -longSide
		if tile.O == "TNT" then
			local fAt = Track.SPLIT + span * Track.TNT_T
			for k, offset in { { 0, 0.7 }, { -1.1, 2.4 }, { 1.2, 2.6 } } do
				MeshLibrary.Get("MinecartMayhemTNT", {
					CFrame = self:_tilePoint(tile, fAt + offset[2], offset[1], Track.RAIL_TOP, 2)
						* CFrame.Angles(0, k * 0.4, 0),
					Parent = props,
				}).Name =
					"TNT"
			end
			local skullAt = self:_tilePoint(tile, fAt - 4, otherSide * 3.4, 0, 2)
			MeshLibrary.Get("MinecartMayhemPost", { CFrame = skullAt, Parent = props })
			self:_board(props, skullAt * CFrame.new(0, 5.6, 0), 3.2, "☠", HINTS.TNT.Color)
		elseif tile.O == "Dead" then
			local fAt = Track.SPLIT + span * Track.BUFFER_T
			MeshLibrary.Get("MinecartMayhemBuffer", {
				CFrame = self:_tilePoint(tile, fAt + 0.4, 0, 0, 2),
				Parent = props,
			})
			MeshLibrary.Get("MinecartMayhemRubble", {
				CFrame = self:_tilePoint(tile, fAt + 9, 0, -1, 2),
				Parent = props,
			})
		else
			-- (a shortcut: a lantern glowing at its far end)
			for _, sideOff in { -1, 1 } do
				local lantern = MeshLibrary.Get("MinecartMayhemLantern", {
					CFrame = self:_tilePoint(tile, Track.MERGE - 26, sideOff * 3.6, 0.2, 2)
						* CFrame.Angles(0, if sideOff > 0 then math.pi else 0, 0),
					Parent = props,
				})
				local glass = lantern:FindFirstChild("Glow", true)
				if glass and glass:IsA("BasePart") and sideOff > 0 then
					Build.Light(glass, rgb(255, 230, 140), 34, 2.4)
				end
			end
		end
	end

	-- Crystals on the rails (a DASH).
	for _, tile in course.Tiles do
		for _, feature in tile.Features do
			if feature.K ~= "Crystal" then
				continue
			end
			local path = tile.Paths[feature.B]
			local x, y, z, hx, _, hz = Track.At(path, feature.S)
			local at = origin + Vector3.new(x, y + Track.RAIL_TOP + 0.3, z)
			MeshLibrary.Get("MinecartMayhemCrystal", {
				CFrame = CFrame.lookAt(at, at + Vector3.new(hx, 0, hz)),
				Parent = props,
			}).Name =
				"Crystal"
		end
	end
end

function MinecartMayhem:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn" -- nothing knocks anyone out
	ctx.EndWhenOneLeft = false
	self.origin = ctx.Origin.Position
	self.tiles = Track.Generate(rng)
	self.course = Track.Build(self.tiles)
	self.Track = Track -- (for the bots' brain)
	local lowest = 0
	for _, tile in self.course.Tiles do
		lowest = math.min(lowest, tile.Entry[2])
	end
	ctx.KillY = self.origin.Y + lowest - 90
	self.riders = {} :: { [any]: Rider }
	self.finished = 0
	self.racing = false
	self.closeAt = nil :: number?

	local players = table.clone(ctx:GetPlayers())
	for index = #players, 2, -1 do -- start lanes in a random order
		local other = rng:NextInteger(1, index)
		players[index], players[other] = players[other], players[index]
	end
	local lanes = {}
	for index, player in players do
		local lane = math.clamp(math.floor((index - 0.5) * 12 / math.max(#players, 1)) + 1, 1, 12)
		local rider: Rider = {
			Player = player,
			Lane = lane,
			Tile = 1,
			B = 1,
			S = 0,
			V = 0,
			Lean = 0,
			JumpAt = -math.huge,
			DashUntil = 0,
			DownUntil = 0,
			Back = false,
			Picks = {},
			ZoneAt = {},
			Pending = {},
			Shown = 0,
			Falls = 0,
			Blasts = 0,
			Bumps = 0,
			Dashes = 0,
			Shortcuts = 0,
			Gone = false,
		}
		self.riders[player] = rider
		table.insert(lanes, { U = player.UserId, L = lane, C = color3(COLORS[lane]), N = player.DisplayName })
		ctx:SetScoreText(player, "0%")
	end
	self:_buildArena()
	ctx:ShareTemplate("MinecartMayhemCart", MeshLibrary.Get("MinecartMayhemCart"))
	ctx:SetSharedJSON("Layout", {
		O = { self.origin.X, self.origin.Y, self.origin.Z },
		Tiles = self.tiles,
		Riders = lanes,
	})
	ctx:SetShared("Stage", "Ready")
	self:_share()

	ctx.Hooks.CharacterReady = function(player)
		if BotRegistry.IsBot(player) then
			self:_placeBot(player, ctx:Now())
		end
		if self.racing then
			ctx:SetWalkSpeed(player, 0)
		end
	end
	ctx.Hooks.Respawn = function(player)
		local rider = self.riders[player]
		return if rider then self:_seat(rider) else nil
	end
	ctx.Hooks.PlayerLeft = function(player)
		self:_leave(player)
	end
	-- SpawnAll hands out points in ctx:GetPlayers() order, not the shuffled lane order.
	local points = {}
	for _, player in ctx:GetPlayers() do
		local rider = self.riders[player]
		table.insert(points, if rider then self:_seat(rider) else self:_frame(1, 1, 0) * CFrame.new(0, 3, 0))
	end
	ctx:SpawnAll(points, true)
	for _, player in players do
		if BotRegistry.IsBot(player) then
			self:_placeBot(player, ctx:Now())
		end
	end
	ctx:SetStatus("Pick your way with LEFT / RIGHT · JUMP the gaps!")
end

-- Where a rider sits: in its cart (a standing root's height, lowered into the cart).
function MinecartMayhem:_seat(rider: Rider): CFrame
	return self:_frame(rider.Tile, rider.B, rider.S, rider.Lane) * CFrame.new(0, CART_FLOOR + 3 - SEAT_Y, 0.3)
end

-- Bots ride where the server has them (players' own clients seat themselves in their carts).
function MinecartMayhem:_placeBot(player: any, now: number)
	local rider = self.riders[player]
	local character, humanoid, root = self.context:GetCharacter(player)
	if not rider or not character or not humanoid or not root then
		return
	end
	if not root.Anchored then
		root.Anchored = true
	end
	if not humanoid.PlatformStand then
		humanoid.PlatformStand = true
	end
	local frame = self:_seat(rider) * CFrame.new(0, Track.JumpHeight(now - rider.JumpAt), 0)
	if rider.DownUntil > now then
		-- (off the rails: dropping into the gap, or thrown up by the blast and down again)
		local since = Track.COMEBACK - (rider.DownUntil - now)
		local lift = if rider.DownKind == "boom" then 14 * since - 16 * since * since else -14 * since * since
		frame = frame * CFrame.new(0, math.max(lift, -60), 0)
	end
	root.CFrame = frame
end

function MinecartMayhem:_leave(player: any)
	local rider = self.riders[player]
	if rider and not rider.Gone then
		rider.Gone = true
		self:_share()
		self:_checkDone()
	end
end

function MinecartMayhem:Start()
	local ctx = self.context
	self.startAt = ctx:Now()
	self.racing = true
	for player, rider in self.riders do
		if not ctx:State(player) then
			rider.Gone = true -- left (or never got a character) before GO
		end
	end
	for _, player in ctx:GetPlayers() do
		ctx:SetWalkSpeed(player, 0)
	end
	ctx:SetShared("Stage", "Race")
	ctx:SetStatus("◀ ▶ pick a way · JUMP the gaps · lean into bends!")

	ctx:OnAction("Lean", function(player, dir, pressedAt)
		self:_lean(player, dir, pressedAt)
	end, { Interval = 0 })
	ctx:OnAction("Jump", function(player, pressedAt)
		self:_jump(player, pressedAt)
	end, { Interval = 0.1 })

	local lastShare = 0
	local lastScore = 0
	local lastBots = 0
	ctx:Heartbeat(function(dt)
		if self.ending then
			return -- the race is over: every cart stays where it was when it closed
		end
		local now = ctx:Now()
		dt = math.min(dt, 0.1)
		local home = {}
		for player, rider in self.riders do
			if rider.Gone then
				continue
			end
			if not rider.Finish and self:_ride(player, rider, dt, now) then
				table.insert(home, player)
			end
			self:_judge(player, rider, now)
		end
		-- Carts home in the same step take their places in the order they crossed the line.
		table.sort(home, function(a, b)
			return (self.riders[a].Finish :: number) < (self.riders[b].Finish :: number)
		end)
		for _, player in home do
			self:_home(player, self.riders[player], now)
		end
		if #home > 0 then
			self:_score()
			self:_checkDone()
		end
		if now - lastBots >= 1 / 20 then
			lastBots = now
			for player, rider in self.riders do
				if not rider.Gone and BotRegistry.IsBot(player) then
					self:_placeBot(player, now)
				end
			end
		end
		if now - lastShare >= 0.1 then
			lastShare = now
			self:_share()
		end
		if now - lastScore >= 0.5 then
			lastScore = now
			self:_score()
		end
		if self.closeAt and now >= self.closeAt and not self.ending then
			self:_end("Time")
		end
	end)
end

-- When a press was made on the player's screen: never later than now, never earlier than the
-- player's ping allows.
function MinecartMayhem:_pressTime(player: any, pressedAt: any): number
	local now = self.context:Now()
	local at = if type(pressedAt) == "number" and pressedAt == pressedAt then pressedAt else now
	return math.clamp(at, now - leewayFor(player), now)
end

function MinecartMayhem:_lean(player: any, dir: any, pressedAt: any)
	local rider = self.riders[player]
	if not rider or rider.Gone or rider.Finish or not self.racing or self.ending then
		return
	end
	if dir ~= -1 and dir ~= 0 and dir ~= 1 then
		return
	end
	local at = self:_pressTime(player, pressedAt)
	if dir == rider.Lean then
		return
	end
	local last = rider.Picks[#rider.Picks]
	if last and last.Until == nil then
		last.Until = at
	end
	rider.Lean = dir
	if dir ~= 0 then
		table.insert(rider.Picks, { Dir = dir, At = at })
		if #rider.Picks > 8 then
			table.remove(rider.Picks, 1)
		end
	end
end

function MinecartMayhem:_jump(player: any, pressedAt: any)
	local rider = self.riders[player]
	if not rider or rider.Gone or rider.Finish or not self.racing or self.ending then
		return
	end
	local at = self:_pressTime(player, pressedAt)
	if at < self.startAt or rider.Back or rider.DownUntil > 0 then
		return
	end
	if at < rider.JumpAt + Track.JUMP_TIME + Track.JUMP_REST - 0.05 then
		return -- still in the air (or just landed)
	end
	rider.JumpAt = at
end

-- One step of a cart's ride; true when it crossed the finish line in this step.
function MinecartMayhem:_ride(player: any, rider: Rider, dt: number, now: number): boolean
	local ctx = self.context
	local events = Track.Ride(self.course, rider, dt, now)
	-- (when the cart came within reach of its next switch: presses count from then)
	local index, away = Track.NextSwitch(self.course, rider, Track.CHOOSE)
	if index and rider.ZoneAt[index] == nil then
		rider.ZoneAt[index] = now - math.max(0, Track.CHOOSE - away) / math.max(rider.V, 1)
	end
	local leeway = leewayFor(player)
	local home = false
	for _, event in events do
		local kind = event.K
		if kind == "Switch" then
			table.insert(rider.Pending, {
				K = kind,
				At = event.At,
				Tile = event.Tile,
				V = event.V,
				JudgeAt = event.At + Track.GRACE + leeway,
			})
		elseif kind == "Gap" or kind == "Crystal" then
			table.insert(rider.Pending, {
				K = kind,
				At = event.At,
				Tile = event.Tile,
				V = event.V,
				Gap = event.Gap,
				JudgeAt = event.At + leeway,
			})
		elseif kind == "Buffer" then
			rider.Bumps += 1
			rider.Pending = {}
			ctx:Fire(nil, "Bump", player.UserId)
		elseif kind == "TNT" then
			rider.Blasts += 1
			rider.DownKind = "boom"
			rider.Pending = {}
			ctx:Fire(nil, "Boom", player.UserId)
		elseif kind == "Return" then
			rider.DownKind = nil
		elseif kind == "Finish" then
			rider.Lean = 0
			home = true
		end
	end
	return home
end

-- Judges what waited for a press still on its way.
function MinecartMayhem:_judge(player: any, rider: Rider, now: number)
	local ctx = self.context
	local pending = rider.Pending
	while pending[1] and pending[1].JudgeAt <= now do
		local item = table.remove(pending, 1) :: Pending
		if rider.DownUntil > 0 or rider.Finish then
			continue
		end
		local tile = self.course.Tiles[item.Tile]
		if item.K == "Switch" then
			if rider.Tile ~= item.Tile or rider.B ~= 1 or rider.Back then
				continue
			end
			local dir = Track.Choose(rider.Picks, rider.ZoneAt[item.Tile] or item.At, item.At)
			local branch = Track.BranchFor(tile, dir)
			rider.B = branch
			if branch == 2 and tile.O == "Short" then
				rider.Shortcuts += 1
			end
			ctx:Fire(nil, "Way", player.UserId, item.Tile, branch)
		elseif item.K == "Gap" then
			if rider.Tile ~= item.Tile then
				continue
			end
			if Track.Clears(rider.JumpAt, item.At, item.V, item.Gap or 8) then
				ctx:Fire(nil, "Cleared", player.UserId, item.Tile)
			else
				rider.Falls += 1
				rider.DownKind = "fall"
				Track.Fall(self.course, rider, item.Tile, now)
				rider.Pending = {}
				ctx:Fire(nil, "Fall", player.UserId, item.Tile)
				return
			end
		elseif item.K == "Crystal" then
			if Track.Airborne(rider.JumpAt, item.At) then
				ctx:Fire(player, "Missed", player.UserId)
			else
				rider.Dashes += 1
				rider.DashUntil = now + Track.DASH_TIME
				ctx:Fire(nil, "Dash", player.UserId)
			end
		end
	end
end

-- A cart out of the mine: its place, the cheer, the finish clock for everyone else.
function MinecartMayhem:_home(player: any, rider: Rider, now: number)
	local ctx = self.context
	self.finished += 1
	rider.Place = self.finished
	local time = (rider.Finish :: number) - self.startAt
	ctx:SetScoreText(player, `{Track.Ordinal(self.finished)} · {string.format("%.1f", time)}s`)
	ctx:Fire(nil, "Finish", player.UserId, self.finished, time)
	if self.finished == 1 then
		ctx:Announce(`🏁 {player.DisplayName} is out of the mine!`, "success", 3)
		ctx:Sound("Victory")
		self.closeAt = now + FINISH_CLOCK
		ctx:SetShared("CloseAt", self.closeAt)
	end
end

-- Every cart for the clients (10 times a second).
function MinecartMayhem:_share()
	local ctx = self.context
	local now = ctx:Now()
	local list = {}
	for player, rider in self.riders do
		if rider.Gone then
			continue
		end
		list[tostring(player.UserId)] = {
			T = rider.Tile,
			B = rider.B,
			S = round(rider.S, 0.01),
			V = round(rider.V, 0.01),
			Ln = if rider.Lean ~= 0 then rider.Lean else nil,
			J = if now - rider.JumpAt < 2 then round(rider.JumpAt, 0.001) else nil,
			Da = if rider.DashUntil > now then round(rider.DashUntil, 0.001) else nil,
			Dn = if rider.DownUntil > 0 then round(rider.DownUntil, 0.001) else nil,
			Dk = if rider.DownUntil > 0 then rider.DownKind else nil,
			Rt = if rider.DownUntil > 0 then rider.ReTile else nil,
			Rs = if rider.DownUntil > 0 then rider.ReS else nil,
			Bk = if rider.Back then 1 else nil,
			F = if rider.Finish then round(rider.Finish - (self.startAt or 0), 0.01) else nil,
			E = if rider.Finish then round(rider.Finish, 0.001) else nil,
			P = rider.Place,
		}
	end
	ctx:SetSharedJSON("Riders", { T = now, R = list })
end

-- The standings: finishers by place, the rest by how far down the mine they are.
function MinecartMayhem:_score()
	local ctx = self.context
	local leader, best = nil, -1
	for player, rider in self.riders do
		if rider.Gone or not ctx:State(player) then
			continue
		end
		local percent = math.floor(math.clamp(Track.Progress(self.course, rider) / self.course.Goal, 0, 1) * 100)
		local score = if rider.Place then 200 - rider.Place else percent
		if score ~= rider.Shown then
			ctx:AddScore(player, score - rider.Shown)
			rider.Shown = score
			if not rider.Place then
				ctx:SetScoreText(player, `{percent}%`)
			end
		end
		if score > best then
			leader, best = player, score
		end
	end
	if self.closeAt then
		local left = math.max(0, math.ceil(self.closeAt - ctx:Now()))
		ctx:SetStatus(`🏁 The mine closes in {left}s!`)
	elseif leader and self.racing and ctx:Now() - self.startAt > 6 then
		ctx:SetStatus(`⛏️ {leader.DisplayName} leads!`)
	end
end

function MinecartMayhem:_checkDone()
	if not self.racing or self.ending then
		return
	end
	for player, rider in self.riders do
		if not rider.Gone and not rider.Finish and self.context:State(player) then
			return
		end
	end
	self:_end("Finished")
end

function MinecartMayhem:_end(reason: string)
	if self.ending then
		return
	end
	self.ending = true
	local ctx = self.context
	for _, rider in self.riders do
		rider.Lean = 0
		rider.Pending = {}
		if not rider.Finish then
			rider.V = 0
		end
	end
	self:_share()
	ctx:SetShared("Stage", "Done")
	ctx:Delay(if reason == "Finished" then 2.5 else 0.5, function()
		ctx:End(reason)
	end)
end

-- The time-out: the race closes where everyone is.
function MinecartMayhem:Stop(_reason)
	if not self.ending then
		self.ending = true
		for _, rider in self.riders or {} do
			rider.Lean = 0
			rider.Pending = {}
			if not rider.Finish then
				rider.V = 0
			end
		end
		if self.course then
			self:_share()
		end
		self.context:SetShared("Stage", "Done")
	end
end

-- Finish order first, then how far down the mine each cart got.
function MinecartMayhem:GetResults()
	local ctx = self.context
	local entries = {}
	local home = {}
	for player in ctx.Participants do
		local rider = self.riders[player]
		if player.Parent and rider and rider.Finish then
			table.insert(home, rider)
		end
	end
	table.sort(home, function(a, b)
		return (a.Finish :: number) < (b.Finish :: number)
	end)
	local places = {}
	for index, rider in home do
		places[rider] = index -- (a finisher who left gives up their place)
	end
	for player in ctx.Participants do
		if not player.Parent then
			continue
		end
		local rider = self.riders[player]
		if not rider then
			continue
		end
		local progress = math.clamp(Track.Progress(self.course, rider), 0, self.course.Goal)
		local percent = math.floor(progress / self.course.Goal * 100)
		local place = places[rider]
		if place then
			table.insert(entries, {
				Player = player,
				Rank = 1e6 - place,
				ScoreText = `{Track.Ordinal(place)} · {string.format(
					"%.1f",
					(rider.Finish or 0) - (self.startAt or 0)
				)}s`,
				BestScore = 100,
			})
		else
			table.insert(entries, {
				Player = player,
				Rank = progress,
				ScoreText = `{percent}% of the way`,
				BestScore = percent,
			})
		end
	end
	return { Entries = entries }
end

return MinecartMayhem

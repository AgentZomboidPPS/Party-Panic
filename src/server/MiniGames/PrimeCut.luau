-- Prime Cut (Team, 50s, 2-12 players). After "Prime Cut" (Super Mario Party Jamboree, 2 vs 2): each
-- team holds a giant knife over an oddly shaped grilled steak and has ten seconds to line it up; then
-- the knife comes down, and the team whose two pieces are closest to 50:50 by area wins the steak.
-- Three steaks, a different shape each time; most steaks won wins (then the smaller total miss).
--
-- Here the players split into 2-4 teams (Teams.CountFor), each at its own grill in a backyard BBQ,
-- all cutting the same steak (same shape, same turn, the knife starting at the same spot). Everyone on
-- a team steers the one knife: ◀ / ▶ nudge it a notch, holding repeats, and teammates' nudges add up
-- (two pushing opposite ways get nowhere), so the crew has to agree on where the middle is. Nobody
-- sees a percentage until the cut: then each team's two pieces and their shares are revealed.
--
-- How it works: the knife's position is the server's (one number per team, `X` studs right of the
-- steak's middle). A client sends its nudges in small batches, numbered, with when they were pressed
-- on its screen ("Nudge" dir, count, seq, pressedAt); the server applies them (a token bucket caps the
-- rate), shares every knife and the last nudge number it took from each player ("Knives", 20 times a
-- second while they move), and the client draws its own knife at the shared spot plus its own nudges
-- still on the way, so it moves the instant the player presses. A nudge pressed before the window
-- closed still counts when it arrives up to LOCK later (judged by the time the press carries, kept
-- within the player's ping, like Bobsled Run). Then the server splits each steak exactly
-- (Shared/Logic/PrimeCut: the polygon on either side of the cut) and shares the results ("Cut").
-- The steak meshes and the outlines come from one generator, so the split is the steak you see.
--
-- Bots nudge through ctx:BotAction like a player's client (Bots/PrimeCut.luau), aiming for where they
-- think the middle is (off by more for clumsier bots). There's nothing a client animates that touches
-- anyone: every knife is judged on the server from the same nudges.
--
-- Which grill is whose (owner: "I couldnt tell what color I was on prime cut."): each player's camera
-- looks straight down at their grate, where only the grill's rim and side tables show, so those are
-- painted in the team's color as well as the body and hood, and the team's rug lies under its grill.
-- The client half adds YOU and the team to its HUD (its badge over the player's own grill went in
-- the sweep pass, owner: "The top circled is fine. we dont need both.").
--
-- Sweep pass (owner: "Let's do a full bug and clean sweep."): the team marks on the grills' signs,
-- the status line and the announcements are Shared/Teams' own, like the client half's (Red's ★
-- draws as a missing-glyph box in the game's fonts; the shared marks get one fix for every game).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local PrimeCutLogic = require(ReplicatedStorage.Shared.Logic.PrimeCut)
local Teams = require(ReplicatedStorage.Shared.Teams)

local MiniGame = require(script.Parent.Kit.MiniGame)
local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local PrimeCut = MiniGame.Define("PrimeCut", { Results = "Team" })

PrimeCut.Shapes = Teams.Shapes -- (every game marks a team the same way)

local SPACING = 44 -- between the grills
local STAND_Z = 17.5 -- where a team stands, in front of its grill (clear of the knife's handle)
local READY = 1.2 -- a new steak lands; the knives unlock this long after
local LOCK = 0.4 -- presses made before the window closed still arrive this long after
local REVEAL = 4.2 -- the pieces and shares on screen
local WINNER_AT = 2.2 -- (into the reveal) when the best cut is announced
local FINALE = 2.4 -- after the last reveal
local START_SHARE = { 0.2, 0.34 } -- where the knife starts: this share of the steak's width in from a side

local rng = Random.new()

type Member = {
	Player: any,
	Team: string,
	Seq: number, -- the last nudge message taken (clients number them)
	Tokens: number,
	TokensAt: number,
	Nudges: number,
	Dir: number, -- the last way they pushed
	DirAt: number,
}
type Station = {
	Team: string,
	Index: number,
	Frame: CFrame, -- the team's frame: the steak's middle at the origin, the team standing at +Z
	Members: { any },
	X: number, -- the knife: studs right of the steak's middle
	Wins: number,
	Off: number, -- the cuts' misses added up (percentage points)
	Results: { any },
	Gone: boolean?,
	Steak: Model?,
}

local function round(x: number, step: number): number
	return math.floor(x / step + 0.5) * step
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- A player's round trip (GetNetworkPing); a press only travels one way, half of it.
local function ping(player: any): number
	if BotRegistry.IsBot(player) then
		return 0
	end
	local ok, value = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and type(value) == "number" then math.clamp(value, 0, 0.5) else 0.15
end

-- Arena -------------------------------------------------------------------------------------------

-- Where a grill's grate is in its prop (measured, so the mesh and its fallback both line up): the
-- grate's middle relative to the prop's pivot, and the grate's top.
local function grateOffset(grill: Model): (Vector3, number)
	local grate = grill:FindFirstChild("Grate", true) :: BasePart?
	if not grate then
		return Vector3.new(0, 4.35, 0), 4.5
	end
	local relative = grill:GetPivot():ToObjectSpace(grate.CFrame)
	return relative.Position, relative.Position.Y + grate.Size.Y / 2
end

function PrimeCut:_buildArena()
	local ctx = self.context
	local arena = ctx.Arena
	local origin = self.origin
	local count = #self.order
	local halfRow = (count - 1) / 2 * SPACING

	-- The lawn, a deck under the grills and a stone path in front of it.
	Build.Part({
		Name = "Lawn",
		Size = Vector3.new(900, 2, 900),
		CFrame = CFrame.new(origin + Vector3.new(0, -2.2, 0)),
		Color = rgb(98, 172, 78),
		Material = Enum.Material.Grass,
		Parent = arena,
	})
	local deckWidth = halfRow * 2 + 46
	Build.Part({
		Name = "Deck",
		Size = Vector3.new(deckWidth, 1.3, 44),
		CFrame = CFrame.new(origin + Vector3.new(0, -0.65, 2)),
		Color = rgb(170, 118, 76),
		Material = Enum.Material.WoodPlanks,
		Parent = arena,
	})
	Build.Part({
		Name = "DeckTrim",
		Size = Vector3.new(deckWidth + 1.2, 0.9, 45.2),
		CFrame = CFrame.new(origin + Vector3.new(0, -0.9, 2)),
		Color = rgb(124, 82, 52),
		Material = Enum.Material.Wood,
		Parent = arena,
	})
	for step = 1, 2 do
		Build.Part({
			Name = "Step",
			Size = Vector3.new(deckWidth * 0.5, 0.6, 2.2),
			CFrame = CFrame.new(origin + Vector3.new(0, -0.3 - step * 0.6 + 0.3, 24 + step * 2.2 - 1.1)),
			Color = rgb(150, 104, 66),
			Material = Enum.Material.WoodPlanks,
			Parent = arena,
		})
	end

	-- The fence round the yard (a gate gap at the front), trees and bushes beyond it.
	local yardX = math.max(halfRow + 52, 92)
	local backZ, frontZ = -52, 62
	local function fenceRun(from: Vector3, to: Vector3, gap: number?)
		local run = to - from
		local segments = math.floor(run.Magnitude / 8 + 0.5)
		local direction = run.Unit
		for index = 0, segments - 1 do
			local middle = from + direction * (index * 8 + 4)
			if gap and math.abs(middle.X - origin.X) < gap then
				continue
			end
			MeshLibrary.Get("PrimeCutFence", {
				CFrame = CFrame.lookAt(middle, middle + direction:Cross(Vector3.yAxis)) * CFrame.Angles(0, 0, 0),
				Parent = arena,
			})
		end
	end
	local y0 = origin.Y - 1.2
	fenceRun(Vector3.new(origin.X - yardX, y0, origin.Z + backZ), Vector3.new(origin.X + yardX, y0, origin.Z + backZ))
	fenceRun(
		Vector3.new(origin.X - yardX, y0, origin.Z + frontZ),
		Vector3.new(origin.X + yardX, y0, origin.Z + frontZ),
		12
	)
	fenceRun(Vector3.new(origin.X - yardX, y0, origin.Z + backZ), Vector3.new(origin.X - yardX, y0, origin.Z + frontZ))
	fenceRun(Vector3.new(origin.X + yardX, y0, origin.Z + backZ), Vector3.new(origin.X + yardX, y0, origin.Z + frontZ))

	local leafColors = { rgb(80, 186, 88), rgb(108, 196, 78), rgb(70, 160, 92), rgb(136, 200, 84) }
	local planted = 0
	local tries = 0
	while planted < 34 and tries < 400 do
		tries += 1
		local x = rng:NextNumber(-yardX - 90, yardX + 90)
		local z = rng:NextNumber(backZ - 110, frontZ + 60)
		local outside = math.abs(x) > yardX + 10 or z < backZ - 10 or z > frontZ + 10
		if outside and (z < frontZ - 4 or math.abs(x) > yardX + 10) then
			planted += 1
			MeshLibrary.Get("Tree", {
				Scale = rng:NextNumber(1.6, 2.8),
				Colors = { Leaves = leafColors[rng:NextInteger(1, #leafColors)] },
				CFrame = CFrame.new(origin + Vector3.new(x, -1.2, z))
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Parent = arena,
			})
		end
	end
	local flowerColors = { rgb(255, 130, 190), rgb(255, 220, 90), rgb(180, 140, 255), rgb(255, 255, 255) }
	for index = 0, 13 do
		local t = (index + 0.5) / 14
		local x = -yardX + 6 + t * (yardX * 2 - 12)
		MeshLibrary.Get("Bush", {
			Scale = rng:NextNumber(1.0, 1.6),
			Colors = { Flowers = flowerColors[rng:NextInteger(1, #flowerColors)] },
			CFrame = CFrame.new(origin + Vector3.new(x, -1.2, backZ + 5))
				* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			Parent = arena,
		})
	end

	-- String lights on posts along the back and the front of the deck.
	local postX = {}
	local postCount = math.max(2, math.ceil((halfRow * 2 + 40) / 40) + 1)
	for index = 0, postCount - 1 do
		table.insert(postX, (index - (postCount - 1) / 2) * 40)
	end
	for _, z in { -30, 26 } do
		for index, x in postX do
			MeshLibrary.Get("PrimeCutPost", {
				CFrame = CFrame.new(origin + Vector3.new(x, -1.2, z))
					* CFrame.Angles(0, if z > 0 then 0 else math.pi, 0),
				Parent = arena,
			})
			local nextX = postX[index + 1]
			if nextX then
				-- (The string's ends are 3.55 above its lowest bulb; the posts' hooks 11.2 up.)
				MeshLibrary.Get("PrimeCutLights", {
					CFrame = CFrame.new(origin + Vector3.new((x + nextX) / 2, -1.2 + 11.2 - 3.55, z)),
					Parent = arena,
				})
			end
		end
	end

	-- Picnic tables and coolers on the lawn in front.
	for _, side in { -1, 1 } do
		local x = side * (halfRow + 30)
		MeshLibrary.Get("PrimeCutTable", {
			CFrame = CFrame.new(origin + Vector3.new(x, -1.2, 40)) * CFrame.Angles(0, side * 0.25, 0),
			Parent = arena,
		})
		MeshLibrary.Get("PrimeCutCooler", {
			CFrame = CFrame.new(origin + Vector3.new(x - side * 10, -1.2, 44)) * CFrame.Angles(0, side * 0.6, 0),
			Parent = arena,
		})
	end

	-- The grills, one per team, in the team's color with its sign on the hood. Seen from a player's
	-- camera (straight down at the grate) the hood is off the top of the screen, so the rim round
	-- the grate and the side tables are in the team's color too (its own color, not a lighter coat:
	-- a light red reads as pink), and the team's rug lies under its grill: every grill reads as its
	-- team's from above.
	local grate, grateTop = self.grate, self.grateTop
	for _, team in self.order do
		local station = self.stations[team]
		local frame = station.Frame
		local color = Teams.Colors[team]
		Build.Decor({
			Name = `Rug_{team}`,
			Size = Vector3.new(40, 0.1, 34),
			CFrame = CFrame.new(frame.Position.X, self.origin.Y + 0.05, frame.Position.Z + 5),
			Color = color:Lerp(Color3.new(0, 0, 0), 0.35),
			Material = Enum.Material.Fabric,
			Parent = arena,
		})
		Build.Decor({
			Name = `RugMiddle_{team}`, -- (its top a full 0.1 over the rug's: at 0.03 the two flickered)
			Size = Vector3.new(37, 0.1, 31),
			CFrame = CFrame.new(frame.Position.X, self.origin.Y + 0.15, frame.Position.Z + 5),
			Color = color:Lerp(Color3.new(0, 0, 0), 0.1),
			Material = Enum.Material.Fabric,
			Parent = arena,
		})
		-- The grill's front (its -Z) faces the team (+Z); its grate's middle under the steak's spot.
		local base = frame * CFrame.new(0, -grateTop, 0) * CFrame.Angles(0, math.pi, 0)
		MeshLibrary.Get("PrimeCutGrill", {
			Colors = { Enamel = color, Steel = color },
			CFrame = base * CFrame.new(-grate.X, 0, -grate.Z),
			Parent = arena,
		})
		MeshLibrary.Get("PrimeCutSauces", {
			CFrame = frame * CFrame.new(-15.4, -grateTop + 4.78, -2.5) * CFrame.Angles(0, 0.3, 0),
			Parent = arena,
		})
		-- The team's sign, standing in the open hood: its shape and name (color is never the only cue).
		local sign = Build.Decor({
			Name = "TeamSign",
			Size = Vector3.new(11, 3.6, 0.2),
			CFrame = frame * CFrame.new(0, -grateTop + 10.4, -12.9) * CFrame.Angles(math.rad(-22), 0, 0),
			Transparency = 1,
			Parent = arena,
		})
		Build.SurfaceText(sign, Enum.NormalId.Back, `{PrimeCut.Shapes[team] or ""} {string.upper(team)}`, {
			PixelsPerStud = 16,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.3,
			Brightness = 1.6,
		})
		-- Heat shimmer and a wisp of smoke over the coals (ambient: off with reduced effects).
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(rgb(240, 240, 240))
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.82),
			NumberSequenceKeypoint.new(1, 1),
		})
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 6) })
		smoke.Lifetime = NumberRange.new(2.5, 4)
		smoke.Speed = NumberRange.new(2.5, 4.5)
		smoke.SpreadAngle = Vector2.new(12, 12)
		smoke.Rate = 5
		smoke.LightInfluence = 0.6
		local emitter = Build.Decor({
			Name = "Smoke",
			Size = Vector3.new(20, 0.2, 14),
			CFrame = frame * CFrame.new(0, -0.6, 0),
			Transparency = 1,
			Parent = arena,
		})
		smoke.Parent = emitter
		CollectionService:AddTag(smoke, "PP_Ambient")
	end
end

-- Round ------------------------------------------------------------------------------------------

function PrimeCut:_standAt(player: any): CFrame?
	local member = self.members[player]
	local station = member and self.stations[member.Team]
	if not station then
		return nil
	end
	local index = table.find(station.Members, player) or 1
	local count = math.max(#station.Members, 1)
	local x = (index - (count + 1) / 2) * 4.2
	local spot = station.Frame * CFrame.new(x, -self.grateTop, STAND_Z)
	return CFrame.lookAt(spot.Position, (station.Frame * CFrame.new(x * 0.5, -self.grateTop, 0)).Position)
end

function PrimeCut:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	self.origin = ctx.Origin.Position
	ctx.KillY = self.origin.Y - 40

	local players = ctx:GetPlayers()
	local names = {}
	-- (A solo test gets one grill instead of an empty rival.)
	for index = 1, math.min(Teams.CountFor(#players, 2), math.max(#players, 1)) do
		table.insert(names, Teams.Order[index])
	end
	self.order = names
	local teams = ctx:AssignTeams(names)
	self.stations = {} :: { [string]: Station }
	self.members = {} :: { [any]: Member }
	for index, team in names do
		local x = (index - (#names + 1) / 2) * SPACING
		-- (The frame is raised onto the grate once the grill is measured, below.)
		self.stations[team] = {
			Team = team,
			Index = index,
			Frame = CFrame.new(self.origin + Vector3.new(x, 0, 0)),
			Members = teams[team] or {},
			X = 0,
			Wins = 0,
			Off = 0,
			Results = {},
		}
		for _, player in self.stations[team].Members do
			self.members[player] = {
				Player = player,
				Team = team,
				Seq = 0,
				Tokens = PrimeCutLogic.BURST,
				TokensAt = 0,
				Nudges = 0,
				Dir = 0,
				DirAt = -math.huge,
			}
		end
	end
	-- The grills stand on the deck (y = origin): the steak's spot is on the grate.
	local probe = MeshLibrary.Get("PrimeCutGrill")
	self.grate, self.grateTop = grateOffset(probe)
	probe:Destroy()
	for _, station in self.stations do
		station.Frame = station.Frame + Vector3.new(0, self.grateTop, 0)
	end
	self:_buildArena()

	-- Three different steaks, each at its own turn.
	local steakIds = {}
	for _, steak in PrimeCutLogic.Steaks do
		table.insert(steakIds, steak.Id)
	end
	for index = #steakIds, 2, -1 do
		local other = rng:NextInteger(1, index)
		steakIds[index], steakIds[other] = steakIds[other], steakIds[index]
	end
	self.plan = {}
	for cut = 1, PrimeCutLogic.CUTS do
		table.insert(self.plan, { Id = steakIds[(cut - 1) % #steakIds + 1], Angle = rng:NextNumber(0, math.pi * 2) })
	end
	-- (Loaded up front, so serving the next steak never waits on a mesh; and shared, so every device
	-- downloads the round's steaks before they're served rather than as each one lands.)
	for _, plan in self.plan do
		ctx:ShareTemplate(`PrimeCutSteak_{plan.Id}`, MeshLibrary.Get(PrimeCutLogic.Steak(plan.Id).Prop))
	end
	self.cut = 0
	self.phase = "Wait"
	self:_serve(1)

	ctx:ShareTemplate("PrimeCutKnife", MeshLibrary.Get("PrimeCutKnife"))
	ctx.Hooks.Respawn = function(player)
		return self:_standAt(player)
	end
	-- Everyone stays at their grill, a late or respawned character too (no prop here is solid).
	ctx.Hooks.CharacterReady = function(player)
		ctx:Freeze(player, true)
	end
	ctx.Hooks.PlayerLeft = function(player)
		self:_leave(player)
	end
	local stations = {}
	for _, team in names do
		local station = self.stations[team]
		local ids = {}
		for _, player in station.Members do
			table.insert(ids, player.UserId)
		end
		local p = station.Frame.Position
		table.insert(stations, { T = team, P = { round(p.X, 0.01), round(p.Y, 0.01), round(p.Z, 0.01) }, M = ids })
	end
	self.layout = stations
	ctx:SetSharedJSON("Layout", { Stations = stations })
	-- (Spots in ctx:GetPlayers() order, as SpawnAll hands them out: someone may have left while
	-- the meshes loaded.)
	local points = {}
	for _, player in ctx:GetPlayers() do
		table.insert(points, self:_standAt(player) or CFrame.new(self.origin + Vector3.new(0, 0, STAND_Z)))
	end
	ctx:SpawnAll(points, true)
	self:_shareCut()
	self:_shareKnives(ctx:Now())
	ctx:SetStatus("Cut your steak 50 : 50!")
end

function PrimeCut:_leave(player: any)
	local member = self.members[player]
	self.members[player] = nil
	local station = member and self.stations[member.Team]
	if not station then
		return
	end
	local index = table.find(station.Members, player)
	if index then
		table.remove(station.Members, index)
	end
	if #station.Members == 0 then
		station.Gone = true
	end
	self:_shareLayout()
end

function PrimeCut:_shareLayout()
	local stations = {}
	for _, entry in self.layout do
		local station = self.stations[entry.T]
		local ids = {}
		for _, player in station.Members do
			table.insert(ids, player.UserId)
		end
		table.insert(stations, { T = entry.T, P = entry.P, M = ids, G = if station.Gone then 1 else nil })
	end
	self.layout = stations
	self.context:SetSharedJSON("Layout", { Stations = stations })
end

-- Puts cut `cut`'s steak on every grill and the knives at their start.
function PrimeCut:_serve(cut: number)
	local ctx = self.context
	local plan = self.plan[cut]
	local outline = PrimeCutLogic.Place(PrimeCutLogic.Outline(plan.Id), plan.Angle)
	local minX, maxX = PrimeCutLogic.Bounds(outline)
	local width = maxX - minX
	local share = rng:NextNumber(START_SHARE[1], START_SHARE[2])
	local start = if rng:NextNumber() < 0.5 then minX + width * share else maxX - width * share
	self.cut = cut
	self.steak = {
		Id = plan.Id,
		Angle = plan.Angle,
		Outline = outline,
		Lo = minX - PrimeCutLogic.MARGIN,
		Hi = maxX + PrimeCutLogic.MARGIN,
		Start = start,
		Even = PrimeCutLogic.Even(outline),
	}
	local prop = PrimeCutLogic.Steak(plan.Id).Prop
	for _, team in self.order do
		local station = self.stations[team]
		if station.Steak then
			station.Steak:Destroy()
		end
		local steak = MeshLibrary.Get(prop, {
			CFrame = station.Frame * CFrame.Angles(0, plan.Angle, 0),
			Parent = ctx.Arena,
		})
		steak.Name = `Steak_{team}`
		station.Steak = steak
		station.X = start
	end
	for _, member in self.members do
		member.Dir = 0
	end
end

function PrimeCut:Start()
	local ctx = self.context
	-- Players whose character never loaded aren't in the round: they don't steer (or count).
	for player in table.clone(self.members) do
		if not ctx:State(player) then
			self:_leave(player)
		end
	end
	for _, player in ctx:GetPlayers() do
		ctx:Freeze(player, true) -- everyone stays at their grill
	end

	ctx:OnAction("Nudge", function(player, dir, count, seq, pressedAt)
		local member = self.members[player]
		if not member or (dir ~= 1 and dir ~= -1) then
			return
		end
		if type(count) ~= "number" or count ~= count or type(seq) ~= "number" or seq ~= seq then
			return
		end
		seq = math.floor(seq)
		if seq <= member.Seq or seq > member.Seq + 1000 then
			return -- (each message counts once, in order)
		end
		member.Seq = seq
		self.dirty = true
		count = math.clamp(math.floor(count), 1, PrimeCutLogic.MAX_BATCH)
		-- When it was pressed: the client's clock, kept within the press's one-way trip (plus a
		-- little jitter) so nobody can nudge back in time; without it, half the round trip back.
		local now = ctx:Now()
		local oneWay = ping(player) / 2
		local at = now - oneWay
		if type(pressedAt) == "number" and pressedAt == pressedAt then
			at = math.clamp(pressedAt, now - oneWay - 0.1, now)
		end
		if not self.openAt or not self.closeAt or at < self.openAt or at > self.closeAt or self.locked then
			return -- (taken, so the client's knife lets go of it, but it doesn't move anything)
		end
		-- The rate: a bucket refilling RATE nudges a second, BURST deep.
		member.Tokens = math.min(PrimeCutLogic.BURST, member.Tokens + (now - member.TokensAt) * PrimeCutLogic.RATE)
		member.TokensAt = now
		local allowed = math.min(count, math.floor(member.Tokens))
		if allowed <= 0 then
			return
		end
		member.Tokens -= allowed
		local station = self.stations[member.Team]
		station.X = math.clamp(station.X + dir * allowed * PrimeCutLogic.STEP, self.steak.Lo, self.steak.Hi)
		member.Nudges += allowed
		member.Dir = dir
		member.DirAt = now
	end, { Interval = 0 })

	self:_open(ctx:Now())
	local lastShare = 0
	ctx:Heartbeat(function()
		local now = ctx:Now()
		self:_tick(now)
		if self.dirty and now - lastShare >= 0.05 then
			lastShare = now
			self.dirty = false
			self:_shareKnives(now)
		end
	end)
end

-- The knives unlock for this cut.
function PrimeCut:_open(now: number)
	self.phase = "Steer"
	self.locked = false
	self.openAt = now
	self.closeAt = now + PrimeCutLogic.STEER
	self.judgeAt = self.closeAt + LOCK
	self:_shareCut()
	self:_shareKnives(now)
	self.context:SetStatus(`STEAK {self.cut}/{PrimeCutLogic.CUTS}  •  Cut it 50 : 50!`)
end

function PrimeCut:_tick(now: number)
	local ctx = self.context
	if self.phase == "Steer" then
		if now >= self.closeAt and not self.chopped then
			self.chopped = true
			self.phase = "Chop"
			self:_shareCut()
			ctx:Sound("Hit")
		end
		if now >= self.judgeAt then
			self:_judge(now)
		end
	elseif self.phase == "Chop" then
		if now >= self.judgeAt then
			self:_judge(now)
		end
	elseif self.phase == "Reveal" then
		if now >= self.nextAt then
			if self.cut >= PrimeCutLogic.CUTS or self:_unopposed() then
				self:_finish()
			else
				-- (Ready first: a steak's mesh can yield on its first load, and this runs every frame.)
				self.phase = "Ready"
				self.nextAt = math.huge
				self:_serve(self.cut + 1)
				now = ctx:Now()
				self.readyAt = now
				self.nextAt = now + READY
				self.chopped = false
				self:_shareCut()
				self:_shareKnives(now)
				ctx:SetStatus(`STEAK {self.cut}/{PrimeCutLogic.CUTS}  •  Get ready...`)
			end
		end
	elseif self.phase == "Ready" then
		if now >= self.nextAt then
			self:_open(now)
		end
	end
end

-- The knives come down: split every steak and find the best cut(s).
function PrimeCut:_judge(now: number)
	local ctx = self.context
	self.locked = true
	self.phase = "Reveal"
	self.revealAt = now
	self.nextAt = now + REVEAL
	local results = {}
	local best = math.huge
	for _, team in self.order do
		local station = self.stations[team]
		local percent = PrimeCutLogic.Percent(self.steak.Outline, station.X)
		local off = PrimeCutLogic.Off(percent)
		-- (P as it's shown, from the same rounding as O, so "PERFECT" never sits next to 50.1%.)
		results[team] = { P = PrimeCutLogic.Round(percent), O = off, X = round(station.X, 0.001) }
		table.insert(station.Results, { P = percent, O = off })
		if not station.Gone then
			station.Off += off
			best = math.min(best, off)
		end
	end
	local winners = {}
	for _, team in self.order do
		local station = self.stations[team]
		if not station.Gone and results[team].O == best then
			table.insert(winners, team)
		end
	end
	self.lastResults = results
	self.lastWinners = winners
	self:_shareKnives(now)
	self:_shareCut()
	ctx:SetStatus(`STEAK {self.cut}/{PrimeCutLogic.CUTS}  •  The verdict...`)
	-- The best cut is announced as the reveal gets to it (WINNER_AT in), so the team scores don't
	-- give it away early.
	ctx:Delay(WINNER_AT, function()
		local names = {}
		for _, team in winners do
			local station = self.stations[team]
			station.Wins += 1
			ctx:AddTeamScore(team, 1)
			table.insert(names, `{PrimeCut.Shapes[team] or ""} {string.upper(team)}`)
		end
		ctx:Sound("Victory")
		if #names > 0 then
			ctx:SetStatus(
				if #names == 1
					then `{names[1]} WINS STEAK {self.cut}!`
					else `TIE! {table.concat(names, " & ")} WIN STEAK {self.cut}!`
			)
		end
	end)
end

-- Whether every rival team has left (a round that started with rivals then ends after this steak).
function PrimeCut:_unopposed(): boolean
	if #self.order < 2 then
		return false
	end
	local left = 0
	for _, team in self.order do
		if not self.stations[team].Gone then
			left += 1
		end
	end
	return left <= 1
end

-- Exact order: steaks won, then the smaller total miss (teams whose players all left come last).
function PrimeCut:_rank(team: string): number
	local station = self.stations[team]
	if not station or station.Gone then
		return -1
	end
	return station.Wins * 1000 + (500 - math.min(station.Off, 499))
end

function PrimeCut:_winner(): string?
	local best, bestRank, tie = nil, -math.huge, false
	for _, team in self.order do
		local rank = self:_rank(team)
		if rank > bestRank + 1e-6 then
			best, bestRank, tie = team, rank, false
		elseif math.abs(rank - bestRank) <= 1e-6 then
			tie = true
		end
	end
	return if tie then nil else best
end

function PrimeCut:_finish()
	local ctx = self.context
	self.phase = "Done"
	self.nextAt = math.huge
	local winner = self:_winner()
	self:_shareCut()
	if winner then
		local station = self.stations[winner]
		ctx:Announce(
			`{PrimeCut.Shapes[winner] or ""} {string.upper(winner)} WINS PRIME CUT! ({station.Wins} of {PrimeCutLogic.CUTS})`,
			"success",
			3
		)
		ctx:SetStatus(`{PrimeCut.Shapes[winner] or ""} {string.upper(winner)} WINS!`)
	else
		ctx:Announce("IT'S A DRAW!", "success", 3)
		ctx:SetStatus("IT'S A DRAW!")
	end
	ctx:Delay(FINALE, function()
		ctx:End("AllCuts")
	end)
end

-- Sharing ----------------------------------------------------------------------------------------

function PrimeCut:_shareCut()
	local steak = self.steak
	self.context:SetSharedJSON("Cut", {
		N = self.cut,
		Of = PrimeCutLogic.CUTS,
		S = steak.Id,
		A = round(steak.Angle, 0.00001),
		X0 = round(steak.Start, 0.001),
		Lo = round(steak.Lo, 0.001),
		Hi = round(steak.Hi, 0.001),
		Ph = self.phase,
		O = self.openAt and round(self.openAt, 0.001),
		C = self.closeAt and round(self.closeAt, 0.001),
		Nx = if self.nextAt and self.nextAt < math.huge then round(self.nextAt, 0.001) else nil,
		R = if self.phase == "Reveal" or self.phase == "Done" then self.lastResults else nil,
		W = if self.phase == "Reveal" or self.phase == "Done" then self.lastWinners else nil,
		Wt = if self.revealAt then round(self.revealAt + WINNER_AT, 0.001) else nil,
	})
end

function PrimeCut:_shareKnives(now: number)
	local knives = {}
	for _, team in self.order do
		local station = self.stations[team]
		local taken, pushing = {}, {}
		for _, player in station.Members do
			local member = self.members[player]
			if member then
				taken[tostring(player.UserId)] = member.Seq
				if member.Dir ~= 0 and now - member.DirAt < 0.35 then
					pushing[tostring(player.UserId)] = member.Dir
				end
			end
		end
		knives[team] = { X = round(station.X, 0.001), K = taken, P = pushing }
	end
	-- (Clients let a push fade a moment after the update that showed it.)
	self.context:SetSharedJSON("Knives", { T = round(now, 0.001), C = self.cut, S = knives })
end

-- Results ----------------------------------------------------------------------------------------

-- Each row says the team with its mark, like the rest of the round: "★ RED 1/3 steaks". (It also
-- had "• best cut ±1.5%", which never fitted the results card's result column and ended in "...".)
function PrimeCut:GetResults()
	local results = self.context:TeamResults()
	for _, entry in results.Entries do
		local station = entry.Team and self.stations[entry.Team]
		if not station then
			continue
		end
		entry.Rank = self:_rank(entry.Team)
		entry.ScoreText = `{Teams.Label(entry.Team)} {station.Wins}/{#station.Results} steaks`
		entry.BestScore = station.Wins
	end
	results.WinningTeam = self:_winner()
	return results
end

return PrimeCut

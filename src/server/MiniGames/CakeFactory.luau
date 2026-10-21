-- Cake Factory (Team, 45s, 2-12 players). After "Cake Factory" (Mario Party 2, 2 vs. 2): each team
-- works its own conveyor belt of cakes. One teammate drops the sponge onto each plate as it passes,
-- the other puts the strawberry on top; a wrong or mistimed press ruins that cake, the belts speed
-- up as the round goes on, and the team with the most finished cakes wins.
--
-- Here 2 to 4 teams (about three players each) get a line each: a plate stacker drops an empty
-- plate onto the belt every SPACING studs, then the cakes pass two or three machines (SPONGE oven,
-- CREAM nozzle, BERRY dropper) and a packing machine boxes every cake that has all its layers. The
-- recipe has as many steps as the biggest team (2 or 3); every station has exactly one owner, so a
-- short-handed team's players run more than one machine (their one ADD button works whichever of
-- their machines has a cake under it). The machines stand off the cakes' rhythm (a gap of
-- SPACING * (1 + 1/steps)), so a player's machines never want a press at the same moment. A press
-- is matched to the cake that needs this player (not a ruined one, not one that already has their
-- layer) before the nearest one, so running two or three machines never ruins a cake by accident.
--
-- A press is good when a cake's middle is within WINDOW studs of the machine, and only if the
-- cake has every earlier layer. Pressing on a cake that's missing a layer ("WRONG"), adding a layer
-- twice, or pressing with a cake only near the machine ("SPLAT") ruins it; pressing with no cake
-- near jams the machine for a moment ("MISS"; a press by a ruined cake does nothing). Ruined and
-- unfinished cakes are tipped into the bin.
--
-- The server owns the belt: its distance is a shared schedule (V0, Acc from T0), clients slide the
-- cakes along it every frame and the server judges each press against the same schedule, at the
-- moment the press was made on the player's own screen (see below). The state of the cakes on each
-- belt is shared as a string ("Cakes_<Team>"), and the "Add"/"Missed"/"Boxed" events animate the
-- machines for everyone.
-- Every team gets the same plates, so a good team could finish them all: skill shows in the score
-- through ⭐ cakes. A finished cake scores 1, a ⭐ cake (every layer a PERFECT press) scores 2, and
-- the pills show both counts (🎂 cakes, ⭐ cakes). A tie on points is broken by perfect presses, then
-- good layers (the results say so).
--
-- Judged by what each player saw (owner: "We need to fine tune some of the hitboxes. the precision
-- games will feel super bad if we dont."): the ADD button sends the time on the player's clock
-- (the synced server time) when they pressed, and the press is judged where the belt was SEEN
-- (0.05 s) before that, the frame their finger reacted to, so phone ping and its jitter no longer
-- push a press late. A lit gate is always a good press: the server allows SLACK (0.05 s of belt)
-- either side of the window for the screen's own delay. A cake is only splatted when the machine's
-- head is over its plate (RUIN: the plate is 4.2 wide, the heads about 1 wide); a press further
-- off just jams. A second press on the cake you just did, within DOUBLE_TAP of the first (before
-- its layer can show on your screen), is ignored instead of ruining it; the client also stops
-- lighting the gate for that cake the moment you press, so it never asks for a second tap.
--
-- Bots press through ctx:BotAction with skill-based timing on the same schedule (Bots/CakeFactory);
-- even the best bots slip now and then, so a sharp human team beats them. There are no moving
-- hazards: the belt only carries cakes, so nothing needs a separate bot check. Bots on the winning
-- team hop for joy when the belts stop.
--
-- Audit pass (owner: "it just has to work"): the packer judges each cake the frame it reaches it,
-- and the frame the round ends the belt stops where the packer last looked, so time-up never
-- leaves a cake past the packer unjudged (it used to look every 0.1 s while the belt ran on until
-- Stop, so a finished cake could stop past it unboxed and not count). A repeat press on the cake
-- you just did is ignored even once that cake has slid past the window (it used to SPLAT it).
-- Presses may come 0.05 s apart (was 0.12 s): a player running two machines can need two presses
-- a tenth of a second apart, and the old limit dropped the second one without a word while their
-- lane showed it done.
-- When a teammate leaves, the belt's new owners are shared before the player who took over is told,
-- so their "You now run" hint goes under their new lane instead of over it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Teams = require(ReplicatedStorage.Shared.Teams)

local BotRegistry = require(script.Parent.Parent.Services.BotRegistry)

local MiniGame = require(script.Parent.Kit.MiniGame)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local CakeFactory = MiniGame.Define("CakeFactory", { Results = "Team" })

-- The belt, in studs along it ("u": 0 where the belt starts, cakes ride towards BELT_LENGTH).
CakeFactory.BELT_LENGTH = 44
CakeFactory.START = 3 -- where the stacker drops each plate
CakeFactory.BOX = 40.5 -- the packing machine judges each cake here
CakeFactory.FINISH = 44.6 -- where a cake leaves the belt
CakeFactory.SPACING = 9 -- between cakes
CakeFactory.V0 = 4 -- belt speed at GO (studs/s)
CakeFactory.V_END = 8.5 -- ...and when the time is up
CakeFactory.WINDOW = 1.5 -- a press within this of a cake's middle is good
CakeFactory.PERFECT = 0.55 -- ...within this, perfect
CakeFactory.RUIN = 2.6 -- a press with a cake nearer than this (but outside the window) splats it:
-- the plate's radius (2.1) plus about half a machine head, so only a press that visibly comes down
-- on the plate ruins the cake
CakeFactory.SLACK = 0.05 -- seconds of belt allowed past either edge of the window (screen delay)
CakeFactory.SEEN = 0.05 -- a press is judged this long before the player's clock said they pressed
CakeFactory.MAX_LAG = 0.35 -- ...and never further back than this before it reached the server
CakeFactory.DOUBLE_TAP = 0.25 -- a repeat press this soon on the cake you just did is ignored
CakeFactory.JAM = 0.5 -- a machine pressed with no cake under it jams this long
CakeFactory.BELT_TOP = 3.2 -- height of the belt's surface
CakeFactory.KINDS = { "Sponge", "Cream", "Berry" }
CakeFactory.Icons = { Sponge = "🍰", Cream = "🍦", Berry = "🍓" }
CakeFactory.Machines = { Sponge = "CakePress", Cream = "CakeNozzle", Berry = "CakeHopper" }
CakeFactory.Shapes = { Red = "★", Blue = "●", Green = "▲", Yellow = "◆" }

local LINE_GAP = 64 -- between neighboring lines' middles
local STAND_Z = -6.4 -- where players stand, in front of their belt
local SIDESTEP = 3.6 -- ...and this far upstream of their machine
local REACH = 12 -- how far from their spot a player may be and still press
local FLOOR_Y = 0

type Station = { X: number, Kind: string, Owner: Player? }
type Cake = { N: number, Bad: boolean, P: number } -- layers, ruined, perfect layers
type Line = {
	Team: string,
	Index: number,
	Center: Vector3,
	Stations: { Station },
	Members: { Player },
	Cakes: { [number]: Cake },
	Judged: number, -- the highest cake the packer has judged
	Passed: { number }, -- per station, the highest cake that has gone past it
	Low: number, -- the lowest cake still on the belt (for sharing)
	Done: number,
	Stars: number, -- finished cakes with every layer perfect (worth 2)
	Ruined: number,
	Layers: number,
	Perfect: number,
}
type Worker = {
	Team: string,
	Spot: CFrame,
	JamUntil: number,
	Good: number,
	Perfect: number,
	Bad: number,
	Last: { K: number, Index: number, At: number }?, -- the last cake this player layered
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function upright(position: Vector3): CFrame
	return CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
end

-- Slides a prop so its piece `name` stands right over `spot` (a prop's pivot is the middle of its
-- whole footprint, which a machine's back column pulls off its nozzle).
local function centerOn(model: Model, name: string, spot: Vector3)
	local piece = model:FindFirstChild(name, true) :: BasePart?
	if piece then
		local offset = spot - piece.Position
		model:PivotTo(model:GetPivot() + Vector3.new(offset.X, 0, offset.Z))
	end
end

-- Station positions along the belt for a recipe of `steps`: off the cakes' rhythm by 1/steps.
function CakeFactory.StationXs(steps: number): { number }
	local gap = CakeFactory.SPACING * (1 + 1 / steps)
	local first = if steps == 3 then 11 else 13
	local list = {}
	for index = 1, steps do
		table.insert(list, first + (index - 1) * gap)
	end
	return list
end

-- The recipe for `steps` stations: 2 = sponge and strawberry (like the original), 3 adds cream.
function CakeFactory.Recipe(steps: number): { string }
	return if steps >= 3 then { "Sponge", "Cream", "Berry" } else { "Sponge", "Berry" }
end

-- How far the belt has moved at server time `t` (the schedule every client draws from too).
function CakeFactory:Distance(t: number): number
	local t0 = self.t0
	if not t0 then
		return 0
	end
	local tau = math.clamp(t - t0, 0, (self.stopAt or math.huge) - t0)
	return CakeFactory.V0 * tau + 0.5 * self.acc * tau * tau
end

function CakeFactory:Speed(t: number): number
	if not self.t0 or (self.stopAt and t >= self.stopAt) then
		return 0
	end
	return CakeFactory.V0 + self.acc * math.max(t - self.t0, 0)
end

-- Where cake k is along the belt at time t (it exists once the belt has moved k spacings).
function CakeFactory:CakeAt(k: number, t: number): number
	return CakeFactory.START + self:Distance(t) - k * CakeFactory.SPACING
end

-- When cake k's middle reaches `u` along the belt (server time), or nil if the belt stops first.
function CakeFactory:ArrivalTime(k: number, u: number): number?
	if not self.t0 then
		return nil
	end
	local d = u - CakeFactory.START + k * CakeFactory.SPACING
	if d <= 0 then
		return self.t0
	end
	local a, v = self.acc, CakeFactory.V0
	local tau = if a > 1e-6 then (-v + math.sqrt(v * v + 2 * a * d)) / a else d / v
	local at = self.t0 + tau
	if self.stopAt and at > self.stopAt then
		return nil
	end
	return at
end

function CakeFactory:Cake(line: Line, k: number): Cake
	local cake = line.Cakes[k]
	if not cake then
		cake = { N = 0, Bad = false, P = 0 }
		line.Cakes[k] = cake
	end
	return cake
end

-- The machines `player` runs on their line (indices into line.Stations).
function CakeFactory:StationsOf(player: Player): (Line?, { number })
	local worker = self.workers[player]
	local line = worker and self.lines[worker.Team]
	local list = {}
	if line then
		for index, station in line.Stations do
			if station.Owner == player then
				table.insert(list, index)
			end
		end
	end
	return line, list
end

-- Hands out a line's stations round-robin to its members and puts each member at their spot.
function CakeFactory:_assign(line: Line)
	local members = line.Members
	for index, station in line.Stations do
		station.Owner = if #members > 0 then members[((index - 1) % #members) + 1] else nil
	end
	self:_spots(line)
end

-- Each member's spot: by their machine, or between their machines when they run more than one.
function CakeFactory:_spots(line: Line)
	local members = line.Members
	local spots = {}
	for _, player in members do
		local sum, count = 0, 0
		for _, station in line.Stations do
			if station.Owner == player then
				sum += station.X
				count += 1
			end
		end
		-- A little upstream of the machine, so the player's own character never hides the cake
		-- under it (the camera sits behind them).
		table.insert(spots, (if count > 0 then sum / count else 22) - SIDESTEP)
	end
	-- Two members standing at the same place shuffle apart.
	for a = 1, #spots do
		for b = a + 1, #spots do
			if math.abs(spots[a] - spots[b]) < 3 then
				spots[b] = spots[a] + 3.2
				spots[a] -= 0.6
			end
		end
	end
	for index, player in members do
		local position = self:World(line, spots[index], FLOOR_Y, STAND_Z)
		local spot = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
		local worker = self.workers[player]
		if worker then
			worker.Spot = spot
		end
	end
end

-- A point on a line: `u` along its belt, `y` up from the floor, `z` across (negative: the front).
-- Cakes ride towards -X, which is left to right for the players looking at the belt.
function CakeFactory:World(line: Line, u: number, y: number, z: number): Vector3
	return line.Center + Vector3.new(CakeFactory.BELT_LENGTH / 2 - u, y, z)
end

function CakeFactory:_shareBelt()
	local lines = {}
	for _, team in self.order do
		local line = self.lines[team]
		local stations = {}
		for _, station in line.Stations do
			table.insert(
				stations,
				{ X = station.X, Kind = station.Kind, Owner = station.Owner and station.Owner.UserId or 0 }
			)
		end
		table.insert(lines, {
			Team = team,
			Shape = CakeFactory.Shapes[team],
			C = { line.Center.X, line.Center.Y, line.Center.Z },
			Stations = stations,
			Gone = #line.Members == 0,
		})
	end
	self.context:SetSharedJSON("Belt", {
		T0 = self.t0,
		StopAt = self.stopAt,
		V0 = CakeFactory.V0,
		Acc = self.acc,
		Spacing = CakeFactory.SPACING,
		Length = CakeFactory.BELT_LENGTH,
		Start = CakeFactory.START,
		Box = CakeFactory.BOX,
		Finish = CakeFactory.FINISH,
		Window = CakeFactory.WINDOW,
		Slack = CakeFactory.SLACK,
		Seen = CakeFactory.SEEN,
		Ruin = CakeFactory.RUIN,
		Top = CakeFactory.BELT_TOP,
		Jam = CakeFactory.JAM,
		Lines = lines,
	})
end

-- The cakes on a line's belt as a string from cake `K` on: a digit per cake for its layers, or a
-- letter (a, b, c, d = 0..3 layers) for a ruined one.
function CakeFactory:_shareCakes(line: Line)
	local now = self.context:Now()
	while self:CakeAt(line.Low, now) > CakeFactory.FINISH + 2 do
		line.Cakes[line.Low] = nil
		line.Low += 1
	end
	local top = math.floor(self:Distance(now) / CakeFactory.SPACING)
	local chars = table.create(math.max(top - line.Low + 1, 0))
	for k = line.Low, top do
		local cake = line.Cakes[k]
		local n = cake and cake.N or 0
		table.insert(chars, if cake and cake.Bad then string.char(97 + n) else tostring(n))
	end
	self.context:SetSharedJSON(
		"Cakes_" .. line.Team,
		{ K = line.Low, S = table.concat(chars), D = line.Done, St = line.Stars }
	)
end

function CakeFactory:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 30
	ctx.WalkSpeed = 0 -- everyone works at their machine (the framework keeps it on unfreeze/respawn)
	local origin = ctx.Origin.Position
	local duration = (ctx.Definition and ctx.Definition.Duration) or 45
	self.acc = (CakeFactory.V_END - CakeFactory.V0) / duration
	self.t0 = nil :: number?
	self.stopAt = nil :: number?
	self.packedAt = nil :: number? -- when the packer last looked (the belt stops there)
	self.stopped = false
	self.workers = {} :: { [Player]: Worker }
	self.lines = {} :: { [string]: Line }
	self.order = {} :: { string }
	self.started = false

	local players = ctx:GetPlayers()
	local names = {}
	-- About three to a team, 2 to 4 teams (a solo test gets a single line).
	local count = math.min(math.clamp(math.ceil(#players / 3), 2, 4), math.max(#players, 1))
	for index = 1, count do
		table.insert(names, Teams.Order[index])
	end
	local teams = ctx:AssignTeams(names)
	local biggest = 1
	for _, team in names do
		biggest = math.max(biggest, #(teams[team] or {}))
	end
	local steps = math.clamp(biggest, 2, 3)
	self.steps = steps
	local recipe = CakeFactory.Recipe(steps)
	local xs = CakeFactory.StationXs(steps)

	self:_buildHall(origin, #names)

	for index, team in names do
		local offset = ((#names + 1) / 2 - index) * LINE_GAP
		local center = origin + Vector3.new(offset, FLOOR_Y, 0)
		local stations = {}
		for step = 1, steps do
			table.insert(stations, { X = xs[step], Kind = recipe[step], Owner = nil })
		end
		local line: Line = {
			Team = team,
			Index = index,
			Center = center,
			Stations = stations,
			Members = table.clone(teams[team] or {}),
			Cakes = {},
			Judged = -1,
			Passed = table.create(steps, -1),
			Low = 0,
			Done = 0,
			Stars = 0,
			Ruined = 0,
			Layers = 0,
			Perfect = 0,
		}
		self.lines[team] = line
		table.insert(self.order, team)
		for _, player in line.Members do
			self.workers[player] =
				{ Team = team, Spot = CFrame.new(center), JamUntil = 0, Good = 0, Perfect = 0, Bad = 0 }
		end
		self:_assign(line)
		self:_buildLine(line)
		ctx:AddTeamScore(team, 0)
	end

	-- The cake pieces the clients stack on the plates.
	for _, name in { "CakePlate", "CakeSponge", "CakeCream", "CakeBerry", "CakeBox" } do
		ctx:ShareTemplate(name, MeshLibrary.Get(name))
	end
	self:_shareBelt()
	for _, team in self.order do
		self:_shareCakes(self.lines[team])
	end

	local points = {}
	for _, player in players do
		local worker = self.workers[player]
		table.insert(points, if worker then worker.Spot else CFrame.new(origin + Vector3.new(0, 0, STAND_Z)))
	end
	ctx:SpawnAll(points, true)
	ctx.Hooks.Respawn = function(player)
		local worker = self.workers[player]
		return if worker then worker.Spot else nil
	end
	for _, player in players do
		ctx:SetScoreText(player, "0 layers")
	end
	ctx:SetStatus("Tap ADD when a cake is under your machine!")
	ctx.Hooks.PlayerLeft = function(player)
		self:_leave(player)
	end
end

-- The factory hall: a checkered floor, a candy-striped back wall with a big sign, giant cakes,
-- a stand mixer and cupcakes between the lines, and grassy hills outside.
function CakeFactory:_buildHall(origin: Vector3, lineCount: number)
	local ctx = self.context
	local width = lineCount * LINE_GAP + 24
	local depth = 64
	local floorCenter = origin + Vector3.new(0, 0, 4)
	-- Grass out to the horizon, under the hall.
	Build.Part({
		Name = "Grass",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 900, 900),
		CFrame = upright(origin - Vector3.new(0, 2.6, 0)),
		Color = rgb(120, 200, 96),
		Material = Enum.Material.Grass,
		Parent = ctx.Arena,
	})
	-- Checkered tiles (cream and pink), 16 studs each; the floor's top is at the origin's height.
	local tile = 16
	local columns = math.ceil(width / tile)
	local rows = math.ceil(depth / tile)
	local floorFolder = Build.Folder("Floor", ctx.Arena)
	for column = 0, columns - 1 do
		for row = 0, rows - 1 do
			local x = (column - (columns - 1) / 2) * tile
			local z = (row - (rows - 1) / 2) * tile
			Build.Part({
				Name = "Tile",
				Size = Vector3.new(tile, 1, tile),
				CFrame = CFrame.new(floorCenter + Vector3.new(x, -0.5, z)),
				Color = if (column + row) % 2 == 0 then rgb(255, 244, 236) else rgb(255, 205, 222),
				Material = Enum.Material.SmoothPlastic,
				Parent = floorFolder,
			})
		end
	end
	local floorWidth, floorDepth = columns * tile, rows * tile
	-- A chocolate skirting round the floor, its top a little under the tiles' top.
	Build.Part({
		Name = "FloorEdge",
		Size = Vector3.new(floorWidth + 3, 1.6, floorDepth + 3),
		CFrame = CFrame.new(floorCenter + Vector3.new(0, -1.25, 0)),
		Color = rgb(120, 72, 52),
		Material = Enum.Material.SmoothPlastic,
		Parent = ctx.Arena,
	})
	-- The back wall: candy-striped panels, a frosting trim along the top and a big sign.
	local wallZ = floorCenter.Z + floorDepth / 2 - 2
	local panels = math.ceil(floorWidth / 8)
	for index = 0, panels - 1 do
		local x = (index - (panels - 1) / 2) * 8
		Build.Part({
			Name = "WallPanel",
			Size = Vector3.new(8, 26, 2),
			CFrame = CFrame.new(floorCenter.X + x, origin.Y + 13, wallZ),
			Color = if index % 2 == 0 then rgb(255, 170, 200) else rgb(255, 236, 244),
			Material = Enum.Material.SmoothPlastic,
			Parent = ctx.Arena,
		})
	end
	Build.Part({
		Name = "WallTrim",
		Size = Vector3.new(floorWidth + 2, 2.4, 3),
		CFrame = CFrame.new(floorCenter.X, origin.Y + 27.2, wallZ),
		Color = rgb(150, 92, 64),
		Material = Enum.Material.SmoothPlastic,
		Parent = ctx.Arena,
	})
	for index = 0, math.floor(floorWidth / 4) do
		Build.Decor({
			Name = "Frosting",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3.6, 3.6, 3.6),
			CFrame = CFrame.new(floorCenter.X - floorWidth / 2 + index * 4, origin.Y + 28.6, wallZ - 0.2),
			Color = if index % 3 == 0 then rgb(255, 120, 170) else rgb(255, 252, 248),
			Parent = ctx.Arena,
		})
	end
	Build.Part({
		Name = "WallBase",
		Size = Vector3.new(floorWidth + 2, 2.4, 3.6),
		CFrame = CFrame.new(floorCenter.X, origin.Y + 1.45, wallZ - 0.3),
		Color = rgb(255, 120, 150),
		Material = Enum.Material.SmoothPlastic,
		Parent = ctx.Arena,
	})
	local sign = Build.Part({
		Name = "Sign",
		Size = Vector3.new(44, 9, 1),
		CFrame = CFrame.new(floorCenter.X, origin.Y + 33.6, wallZ - 0.6),
		Color = rgb(255, 255, 255),
		Material = Enum.Material.SmoothPlastic,
		Parent = ctx.Arena,
	})
	Build.Part({
		Name = "SignBack",
		Size = Vector3.new(46, 11, 0.8),
		CFrame = CFrame.new(floorCenter.X, origin.Y + 33.6, wallZ - 0.1),
		Color = rgb(255, 90, 140),
		Material = Enum.Material.SmoothPlastic,
		Parent = ctx.Arena,
	})
	Build.SurfaceText(sign, Enum.NormalId.Front, "🎂 CAKE FACTORY 🍓", {
		TextColor3 = rgb(255, 90, 140),
	})

	-- Giant treats between and beside the lines, against the wall.
	local spots = {}
	for gap = 0, lineCount do
		table.insert(spots, ((lineCount / 2) - gap) * LINE_GAP)
	end
	local decor = Random.new(7)
	for index, x in spots do
		local base = Vector3.new(floorCenter.X + x, origin.Y, wallZ - 9)
		local outer = index == 1 or index == #spots
		if outer then
			MeshLibrary.Get("CakeTiered", {
				Scale = 1.1,
				CFrame = CFrame.new(base + Vector3.new(0, 0, -4)) * CFrame.Angles(0, decor:NextNumber(0, 6), 0),
				Parent = ctx.Arena,
			})
		elseif index % 2 == 0 then
			MeshLibrary.Get("CakeMixer", {
				Scale = 1,
				CFrame = CFrame.new(base) * CFrame.Angles(0, math.rad(decor:NextNumber(-30, 30)), 0),
				Parent = ctx.Arena,
			})
		else
			MeshLibrary.Get("CakeTiered", {
				Scale = 0.8,
				CFrame = CFrame.new(base + Vector3.new(0, 0, -4)) * CFrame.Angles(0, decor:NextNumber(0, 6), 0),
				Parent = ctx.Arena,
			})
		end
		for side = -1, 1, 2 do
			MeshLibrary.Get("CakeCupcake", {
				Scale = decor:NextNumber(1.6, 2.1),
				Colors = {
					Wrapper = ({ rgb(140, 200, 255), rgb(255, 160, 200), rgb(170, 230, 160) })[decor:NextInteger(1, 3)],
					Frosting = ({ rgb(255, 170, 210), rgb(255, 245, 235), rgb(160, 110, 80) })[decor:NextInteger(1, 3)],
				},
				CFrame = CFrame.new(base + Vector3.new(side * 9.5, 0, -15))
					* CFrame.Angles(0, decor:NextNumber(0, 6), 0),
				Parent = ctx.Arena,
			})
		end
	end

	-- Giant lollipops along the sides of the hall, and giant cupcakes at its front corners.
	local swirls = { rgb(255, 90, 150), rgb(120, 200, 255), rgb(255, 200, 70), rgb(140, 220, 140) }
	for side = -1, 1, 2 do
		for index, z in { -18, 2, 22 } do
			local base = floorCenter + Vector3.new(side * (floorWidth / 2 - 4), 0, z)
			local height = 13 + (index % 2) * 3
			Build.Part({
				Name = "LollipopStick",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(height, 0.9, 0.9),
				CFrame = upright(base + Vector3.new(0, height / 2, 0)),
				Color = rgb(255, 255, 255),
				Material = Enum.Material.SmoothPlastic,
				Parent = ctx.Arena,
			})
			local center = base + Vector3.new(0, height + 3, 0)
			local facing = CFrame.new(center) * CFrame.Angles(0, math.rad(90), 0) -- the candy faces the players
			local color = swirls[(index + (if side > 0 then 1 else 0)) % #swirls + 1]
			for ring, size in { 7.4, 5.2, 3.0, 1.0 } do
				Build.Part({
					Name = "Lollipop",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(1.2 + ring * 0.3, size, size),
					CFrame = facing,
					Color = if ring % 2 == 1 then color else rgb(255, 250, 245),
					Material = Enum.Material.SmoothPlastic,
					Parent = ctx.Arena,
				})
			end
		end
		MeshLibrary.Get("CakeCupcake", {
			Scale = 2.3,
			Colors = { Wrapper = rgb(255, 160, 200), Frosting = rgb(255, 245, 235) },
			CFrame = CFrame.new(floorCenter + Vector3.new(side * (floorWidth / 2 - 6), 0, -floorDepth / 2 + 6))
				* CFrame.Angles(0, decor:NextNumber(0, 6), 0),
			Parent = ctx.Arena,
		})
	end

	-- Soft hills far away, and a few lollipop-pink ones.
	for index = 0, 13 do
		local angle = (index + decor:NextNumber(-0.3, 0.3)) / 14 * math.pi * 2
		local distance = decor:NextNumber(300, 380)
		local size = Vector3.new(decor:NextNumber(150, 230), decor:NextNumber(50, 90), decor:NextNumber(110, 160))
		local hill = Build.Part({
			Name = "Hill",
			Size = size,
			CFrame = CFrame.new(
				origin + Vector3.new(math.cos(angle) * distance, -size.Y * 0.2, math.sin(angle) * distance)
			) * CFrame.Angles(0, -angle + math.pi / 2, 0),
			Color = if index % 4 == 0
				then rgb(255, 180, 210)
				else rgb(110, 190, 96):Lerp(rgb(80, 150, 96), decor:NextNumber()),
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = ctx.Arena,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = hill
	end
end

-- One line: the belt, its stacker, machines, packer, bin and shelf, a window gate at each
-- machine, and the team's name and shape over it all.
function CakeFactory:_buildLine(line: Line)
	local ctx = self.context
	local color = Teams.Colors[line.Team]
	local folder = Build.Model("Line_" .. line.Team, ctx.Arena)
	local tint = color:Lerp(Color3.new(1, 1, 1), 0.15)
	local belt = MeshLibrary.Get("CakeBelt", {
		Colors = { Stripe = tint },
		CFrame = CFrame.new(self:World(line, CakeFactory.BELT_LENGTH / 2, FLOOR_Y, 0)),
		Parent = folder,
	})
	belt.Name = "Belt"
	-- A team-colored mat under the line, where the players stand.
	Build.Decor({
		Name = "Mat",
		Size = Vector3.new(CakeFactory.BELT_LENGTH + 10, 0.2, 7),
		CFrame = CFrame.new(self:World(line, CakeFactory.BELT_LENGTH / 2, FLOOR_Y + 0.2, STAND_Z)),
		Color = color:Lerp(Color3.new(1, 1, 1), 0.5),
		Parent = folder,
	})
	Build.Decor({
		Name = "MatEdge",
		Size = Vector3.new(CakeFactory.BELT_LENGTH + 10.6, 0.11, 7.6),
		CFrame = CFrame.new(self:World(line, CakeFactory.BELT_LENGTH / 2, FLOOR_Y + 0.065, STAND_Z)),
		Color = color,
		Parent = folder,
	})

	local stacker = MeshLibrary.Get("CakeStacker", {
		Colors = { Stripe = tint },
		CFrame = CFrame.new(self:World(line, CakeFactory.START, FLOOR_Y, 0)),
		Parent = folder,
	})
	stacker.Name = "Stacker"
	centerOn(stacker, "Plates", self:World(line, CakeFactory.START, 0, 0))

	for index, station in line.Stations do
		local machine = MeshLibrary.Get(CakeFactory.Machines[station.Kind], {
			Colors = { Stripe = tint },
			CFrame = CFrame.new(self:World(line, station.X, FLOOR_Y, 0)),
			Parent = folder,
		})
		machine.Name = "Machine_" .. index
		local business = if station.Kind == "Sponge"
			then "Stamp"
			elseif station.Kind == "Cream" then "Nozzle"
			else "Chute"
		centerOn(machine, business, self:World(line, station.X, 0, 0))
		-- The window gate: a post on each rail at each edge of the good window.
		for _, edge in { -1, 1 } do
			for _, side in { -1, 1 } do
				Build.Decor({
					Name = `Gate_{index}`,
					Size = Vector3.new(0.34, 1.1, 0.56),
					CFrame = CFrame.new(
						self:World(
							line,
							station.X + edge * CakeFactory.WINDOW,
							CakeFactory.BELT_TOP + 0.85,
							side * 2.48
						)
					),
					Color = rgb(255, 255, 255),
					Material = Enum.Material.SmoothPlastic,
					Parent = folder,
				})
			end
		end
		-- The ingredient's sign on the machine.
		local anchor = Build.Part({
			Name = "SignAnchor_" .. index,
			Size = Vector3.new(0.2, 0.2, 0.2),
			CFrame = CFrame.new(self:World(line, station.X, 15.5, -1)),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Parent = folder,
		})
		Build.Billboard(anchor, `{CakeFactory.Icons[station.Kind]} {string.upper(station.Kind)}`, {
			Name = "Ingredient",
			Size = UDim2.fromOffset(170, 44),
			MaxDistance = 140,
			TextColor3 = Color3.new(1, 1, 1),
		})
	end

	local boxer = MeshLibrary.Get("CakeBoxer", {
		Colors = { Stripe = tint },
		CFrame = CFrame.new(self:World(line, CakeFactory.BOX, FLOOR_Y, 0)),
		Parent = folder,
	})
	boxer.Name = "Boxer"
	centerOn(boxer, "Body", self:World(line, CakeFactory.BOX, 0, 0))
	local bin = MeshLibrary.Get("CakeBin", {
		Colors = { Stripe = tint },
		CFrame = CFrame.new(self:World(line, CakeFactory.FINISH + 2.4, FLOOR_Y, -0.4)),
		Parent = folder,
	})
	bin.Name = "Bin"
	local shelf = MeshLibrary.Get("CakeShelf", {
		Colors = { Stripe = tint },
		CFrame = CFrame.new(self:World(line, CakeFactory.FINISH + 3, FLOOR_Y, 7.5)),
		Parent = folder,
	})
	shelf.Name = "Shelf"

	-- The team's shape and name high over the line.
	local labelAnchor = Build.Part({
		Name = "TeamAnchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(self:World(line, CakeFactory.BELT_LENGTH / 2, 21, 0)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = folder,
	})
	Build.Billboard(labelAnchor, `{CakeFactory.Shapes[line.Team]} {string.upper(line.Team)}`, {
		Name = "TeamLabel",
		Size = UDim2.fromOffset(200, 54),
		MaxDistance = 400,
		TextColor3 = color,
	})
end

-- How far apart two machines are in the cakes' rhythm (0: they'd want a press at the same moment).
local function phaseGap(a: number, b: number): number
	local gap = math.abs(a - b) % CakeFactory.SPACING
	return math.min(gap, CakeFactory.SPACING - gap)
end

-- Someone left: only their machines change hands, each to the teammate running the fewest (the one
-- whose machines are furthest off its rhythm on a tie), who walks over and is told. A team with
-- nobody left keeps its cakes but drops out of the running.
function CakeFactory:_leave(player: Player)
	local worker = self.workers[player]
	self.workers[player] = nil
	local line = worker and self.lines[worker.Team]
	if not line then
		return
	end
	local index = table.find(line.Members, player)
	if index then
		table.remove(line.Members, index)
	end
	local before = {}
	for _, member in line.Members do
		local other = self.workers[member]
		before[member] = other and other.Spot
	end
	local gained = {} :: { [Player]: boolean }
	for _, orphan in line.Stations do
		if orphan.Owner and table.find(line.Members, orphan.Owner) then
			continue
		end
		local best, bestCount, bestGap = nil, math.huge, -1
		for _, member in line.Members do
			local count, gap = 0, math.huge
			for _, station in line.Stations do
				if station.Owner == member then
					count += 1
					gap = math.min(gap, phaseGap(station.X, orphan.X))
				end
			end
			if count < bestCount or (count == bestCount and gap > bestGap) then
				best, bestCount, bestGap = member, count, gap
			end
		end
		orphan.Owner = best
		if best then
			gained[best] = true
		end
	end
	self:_spots(line)
	-- The new owners go out first: a client places the "You now run" hint under its lanes, so the
	-- lane it just gained has to be there before the hint (it used to land on top of that lane).
	self:_shareBelt()
	-- Only teammates whose spot changed walk over (and are told what they run now).
	for _, member in line.Members do
		local other = self.workers[member]
		local old = before[member]
		if not other or (old and (old.Position - other.Spot.Position).Magnitude < 0.5 and not gained[member]) then
			continue
		end
		local character, _, root = self.context:GetCharacter(member)
		if character and root then
			character:PivotTo(other.Spot + Vector3.new(0, 3, 0))
		end
		local kinds = {}
		for _, station in line.Stations do
			if station.Owner == member then
				table.insert(kinds, station.Kind)
			end
		end
		self.context:Fire(member, "Reassigned", kinds)
	end
end

-- When a press of ADD is judged: where the belt was on the player's screen when they pressed.
-- `sentAt` is the client's synced clock at the press; bots (and old clients) send none, so their
-- press is judged at its arrival less half the player's ping. Never more than MAX_LAG back, so a
-- made-up time can't reach for a cake that's long gone.
function CakeFactory:PressTime(player: Player, sentAt: any): number
	local now = self.context:Now()
	if type(sentAt) == "number" and sentAt == sentAt then
		return math.clamp(sentAt - CakeFactory.SEEN, now - CakeFactory.MAX_LAG, now)
	end
	local lag = 0
	if typeof(player) == "Instance" then
		local ok, ping = pcall(function()
			return player:GetNetworkPing()
		end)
		lag = CakeFactory.SEEN + (if ok and type(ping) == "number" then math.clamp(ping, 0, 0.5) / 2 else 0.05)
	end
	return now - math.min(lag, CakeFactory.MAX_LAG)
end

-- A press of ADD: judged against the belt at the moment the player's screen showed (PressTime).
function CakeFactory:_add(player: Player, sentAt: any)
	local ctx = self.context
	local worker = self.workers[player]
	if not worker or not self.t0 or self.stopAt then
		return
	end
	local now = ctx:Now()
	if now < worker.JamUntil then
		return -- the client shows ✕ JAMMED (and holds presses) for as long
	end
	local line, owned = self:StationsOf(player)
	if not line or #owned == 0 then
		return
	end
	local _, _, root = ctx:GetCharacter(player)
	if not root then
		return
	end
	local flat = Vector3.new(root.Position.X - worker.Spot.X, 0, root.Position.Z - worker.Spot.Z)
	if flat.Magnitude > REACH then
		return
	end
	local at = self:PressTime(player, sentAt)
	local slack = self:Speed(at) * CakeFactory.SLACK
	local distance = self:Distance(at)

	-- Which cake this press is for: one under any of this player's machines that needs exactly that
	-- machine's layer and is in its window, the nearest such; else the nearest cake that isn't
	-- ruined. (A player running several machines has their windows close together.)
	local best, bestK, bestOffset = nil, nil, math.huge
	local near, nearK, nearOffset = nil, nil, math.huge
	local ruinedAt = nil
	for _, index in owned do
		local station = line.Stations[index]
		local k = math.floor((CakeFactory.START + distance - station.X) / CakeFactory.SPACING + 0.5)
		if k < 0 or k * CakeFactory.SPACING > distance + 1e-6 then
			continue
		end
		local offset = CakeFactory.START + distance - k * CakeFactory.SPACING - station.X
		if math.abs(offset) > CakeFactory.RUIN then
			continue
		end
		local cake = line.Cakes[k]
		if cake and cake.Bad then
			ruinedAt = ruinedAt or index
			continue
		end
		local layers = if cake then cake.N else 0
		if
			layers == index - 1
			and math.abs(offset) <= CakeFactory.WINDOW + slack
			and math.abs(offset) < math.abs(bestOffset)
		then
			best, bestK, bestOffset = index, k, offset
		end
		if math.abs(offset) < math.abs(nearOffset) then
			near, nearK, nearOffset = index, k, offset
		end
	end
	if not best then
		best, bestK, bestOffset = near, nearK, nearOffset
	end
	local station = best and line.Stations[best]
	local kind
	if not station or not bestK then
		kind = if ruinedAt then "ruined" else "miss"
	else
		local cake = self:Cake(line, bestK)
		local last = worker.Last
		if
			cake.N >= best
			and last
			and last.K == bestK
			and last.Index == best
			and at - last.At < CakeFactory.DOUBLE_TAP
		then
			-- A double tap on the cake you just did, before its layer could show: nothing (checked
			-- before the window, as the cake may have slid past it since the first tap).
			return
		elseif math.abs(bestOffset) > CakeFactory.WINDOW + slack then
			kind = "splat"
		elseif cake.N ~= best - 1 then
			kind = if cake.N >= best then "double" else "wrong"
		else
			kind = if math.abs(bestOffset) <= CakeFactory.PERFECT + slack * 0.5 then "perfect" else "good"
		end
		if kind == "perfect" or kind == "good" then
			cake.N = best
			worker.Last = { K = bestK, Index = best, At = at }
			worker.Good += 1
			line.Layers += 1
			if kind == "perfect" then
				cake.P += 1
				worker.Perfect += 1
				line.Perfect += 1
			end
			ctx:AddScore(player, if kind == "perfect" then 2 else 1)
			ctx:SetScoreText(player, `{worker.Good} layers`)
		else
			cake.Bad = true
			worker.Bad += 1
		end
	end
	if kind == "miss" then
		worker.JamUntil = now + CakeFactory.JAM
	end
	ctx:Fire(nil, "Add", line.Team, best or ruinedAt or owned[1], bestK or -1, kind, player.UserId)
	if kind ~= "miss" and kind ~= "ruined" then
		self:_shareCakes(line)
	end
end

function CakeFactory:Start()
	local ctx = self.context
	self.started = true
	self.t0 = ctx:Now() + 0.2
	self:_shareBelt()
	-- One press per 0.05 s: a player running two machines can need two presses a tenth of a second
	-- apart (their windows come back to back), and mashing gains nothing (a repeat on the cake you
	-- just did is ignored, an early press splats, a press with no cake near jams).
	ctx:OnAction("Add", function(player, sentAt)
		self:_add(player, sentAt)
	end, { Interval = 0.05 })

	-- Anyone who left (or never spawned) before the hook was set.
	local gone = {}
	for player in self.workers do
		if not ctx:State(player) then
			table.insert(gone, player)
		end
	end
	for _, player in gone do
		self:_leave(player)
	end

	-- The packer judges each cake the frame it reaches it; the first frame after the round ends
	-- (time up, or everyone left) the belt stops where the packer last looked (the round manager
	-- calls Stop a moment later), so no cake is ever left past the packer unjudged.
	ctx:Heartbeat(function()
		self:_pack(ctx:Now())
	end)
	local watch: RBXScriptConnection
	watch = ctx:Track(RunService.Heartbeat:Connect(function()
		if not ctx:IsRunning() then
			watch:Disconnect()
			self:_halt()
		end
	end))

	-- The machines note cakes that went by without their layer (judged where the belt was MAX_LAG
	-- ago, the most a press can be judged in the past, so no press still on its way could have
	-- counted).
	local lastStatus, status, faster = 0, nil, 1
	ctx:Loop(function(): number?
		local now = ctx:Now()
		local late = self:Distance(now - CakeFactory.MAX_LAG)
		for _, team in self.order do
			local line = self.lines[team]
			for index, station in line.Stations do
				local passed =
					math.floor((CakeFactory.START + late - station.X - CakeFactory.RUIN) / CakeFactory.SPACING)
				passed = math.min(passed, math.floor(late / CakeFactory.SPACING))
				for k = line.Passed[index] + 1, passed do
					local cake = self:Cake(line, k)
					if not cake.Bad and cake.N == index - 1 and #line.Members > 0 then
						ctx:Fire(nil, "Missed", team, index, k)
					end
				end
				line.Passed[index] = math.max(line.Passed[index], passed)
			end
			if now - lastStatus > 0.9 then
				self:_shareCakes(line)
			end
		end
		if now - lastStatus > 0.9 then
			lastStatus = now
		end
		-- The status says who's ahead on points (the numbers on the score bar), ties included.
		local text = self:_statusText()
		if text and text ~= status then
			status = text
			ctx:SetStatus(text)
		end
		-- The belts speed up: say so at each step up.
		local speed = self:Speed(now)
		if speed >= CakeFactory.V0 * (1 + faster * 0.35) and not self.stopAt then
			faster += 1
			ctx:Announce("FASTER! ⏩", "warning", 1.4)
			ctx:Fire(nil, "Faster", faster)
		end
		return 0.1
	end)
end

-- The packer: each cake that has reached it by `now` is boxed if it has every layer (1 point, 2
-- for a ⭐ cake whose every layer was perfect) or tipped into the bin.
function CakeFactory:_pack(now: number)
	local ctx = self.context
	local distance = self:Distance(now)
	for _, team in self.order do
		local line = self.lines[team]
		local judged = math.floor((CakeFactory.START + distance - CakeFactory.BOX) / CakeFactory.SPACING)
		if judged > line.Judged then
			for k = line.Judged + 1, judged do
				local cake = self:Cake(line, k)
				local good = not cake.Bad and cake.N == #line.Stations
				local star = good and cake.P >= #line.Stations
				if good then
					line.Done += 1
					if star then
						line.Stars += 1
					end
					ctx:AddTeamScore(team, if star then 2 else 1)
				else
					line.Ruined += 1
				end
				ctx:Fire(nil, "Boxed", team, k, good, line.Done, star, line.Stars)
			end
			line.Judged = judged
			self:_shareCakes(line)
		end
	end
	self.packedAt = now
end

-- Stops the belts where the packer last looked (never before GO) and tells everyone.
function CakeFactory:_halt()
	if self.stopAt then
		return
	end
	self.stopAt = math.max(self.packedAt or self.context:Now(), self.t0 or -math.huge)
	self:_shareBelt()
	for _, team in self.order do
		self:_shareCakes(self.lines[team])
	end
end

-- A team's points: 1 per finished cake, 2 per ⭐ cake.
function CakeFactory:Points(team: string): number
	local line = self.lines[team]
	return if line then line.Done + line.Stars else 0
end

-- "★ RED leads 12–9" or "TIED at 12" (points among teams with players), nil before anyone scores.
function CakeFactory:_statusText(): string?
	local top, second, leader, shared = -1, -1, nil, false
	for _, team in self.order do
		if #self.lines[team].Members == 0 then
			continue
		end
		local points = self:Points(team)
		if points > top then
			second, top, leader, shared = top, points, team, false
		elseif points == top then
			second, shared = points, true
		elseif points > second then
			second = points
		end
	end
	if not leader or top <= 0 then
		return nil
	elseif shared then
		return `TIED at {top}!`
	end
	return `{CakeFactory.Shapes[leader]} {string.upper(leader)} leads {top}–{math.max(second, 0)}`
end

-- The team with the most points (ties broken by perfect presses, then good layers) among teams
-- with players, or nil on a dead heat.
function CakeFactory:_leader(): string?
	local best, bestRank, tie = nil, -1, false
	for _, team in self.order do
		local line = self.lines[team]
		if #line.Members == 0 then
			continue
		end
		local rank = self:_rank(team)
		if rank > bestRank then
			best, bestRank, tie = team, rank, false
		elseif rank == bestRank then
			tie = true
		end
	end
	return if tie then nil else best
end

function CakeFactory:_rank(team: string): number
	local line = self.lines[team]
	if not line then
		return 0
	end
	return self:Points(team) + math.min(line.Perfect, 9999) / 1e4 + math.min(line.Layers, 9999) / 1e8
end

function CakeFactory:Stop(_reason: string?)
	if not self.started or self.stopped then
		return
	end
	self.stopped = true
	local ctx = self.context
	self:_halt() -- (usually done already, the frame the round ended)
	local team = self:_leader()
	if team then
		ctx:Announce(`{CakeFactory.Shapes[team]} {string.upper(team)} WINS!`, "success", 2.5)
		ctx:Fire(nil, "Winner", team)
		-- The winning team's bots hop for joy (the bot loop has already stopped).
		for _, bot in self.lines[team].Members do
			if BotRegistry.IsBot(bot) then
				task.delay(0.15 + math.random() * 0.4, function()
					pcall(function()
						bot:Jump()
					end)
				end)
			end
		end
	end
end

-- Team results (most points first, then perfect presses); each player's line shows their own work.
function CakeFactory:GetResults()
	local results = self.context:TeamResults()
	for _, entry in results.Entries do
		local line = entry.Team and self.lines[entry.Team]
		if line then
			entry.Rank = self:_rank(entry.Team) * 100
		end
		local worker = self.workers[entry.Player]
		if worker and line then
			entry.ScoreText =
				`{entry.Team} {line.Done} cakes, {line.Stars} ⭐ • {worker.Good} layers, {worker.Perfect} perfect`
		end
	end
	results.WinningTeam = self:_leader()
	return results
end

return CakeFactory

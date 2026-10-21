-- Crazy Cutters (Reaction, 80s, 1-12 players). After "Crazy Cutters" (Mario Party 1), where everyone
-- jackhammers a fossil's outline as accurately as they can in 30 seconds. Here it's a cookie
-- bake-off: everyone has their own cutting board with a sheet of dough on it, and runs a pastry
-- wheel round a dotted outline (a star, a heart, a ghost, a mushroom...). Three shapes, easy to
-- hard; each cut scores 0-100% for how closely it follows the line and how much of it it covers.
-- The best average wins; finishing faster breaks ties. A finished cut pops out as an iced cookie.
--
-- How it works: the shapes and the scoring are plain math in Shared/Logic/CrazyCutters (the client
-- uses the same code to show a player their score live). For each shape the server shares "Round"
-- (which shape, when cutting starts and ends). A player's client moves their cutter (finger, mouse,
-- keys or stick) and sends its positions in small batches ("Cut"); the server checks every
-- position (time, order, board bounds, the cutter's top speed, with leeway for ping), scores the
-- accepted ones and relays them to every client, which draws everyone's cut on their boards. Bots
-- send positions through the very same action (bot paths: CrazyCutters:BotSamples), so they are
-- checked, scored and drawn exactly like players.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.CrazyCutters)

local MiniGame = require(script.Parent.Kit.MiniGame)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local CrazyCutters = MiniGame.Define("CrazyCutters", { Results = "Score" })

local RING = 37 -- boards' middles from the arena's middle
local SLOT = math.rad(30) -- between neighbouring boards (12 fill the ring)
local FLOOR = 3.75 -- the cookie floor's top above the arena origin
local BOARD_UP = 0.1 -- boards sit this far above the floor (clear of the cookie's lumps)
local DOUGH = 0.8 -- the dough sheet's bottom above the board's
local DOUGH_TOP = 1.22 -- the dough's top surface above the board's bottom
local STAND = 11.2 -- players stand this far behind their board's middle
local SHOW = 3.2 -- seconds a shape is shown before cutting starts (the first one a little longer)
local SCORE_TIME = 3.4 -- seconds the scores show after each shape
local SHAPES_PER_GAME = 3

local rng = Random.new()

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

type Track = Rules.Tracker & {
	LastT: number,
	DoneAt: number?,
}

-- Picks one shape of each tier (easy, medium, hard).
local function pickShapes(): { string }
	local picked = {}
	for tier = 1, SHAPES_PER_GAME do
		local ids = Rules.OfTier(tier)
		if #ids > 0 then
			table.insert(picked, ids[rng:NextInteger(1, #ids)])
		end
	end
	return picked
end

-- A cylinder lying flat (Roblox cylinders run along X).
local function flat(cframe: CFrame): CFrame
	return cframe * CFrame.Angles(0, 0, math.rad(90))
end

function CrazyCutters:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 30
	local origin = ctx.Origin.Position
	self.shapeIds = pickShapes()
	self.boards = {} :: { [Player]: CFrame }
	self.tracks = {} :: { [Player]: Track }
	self.scores = {} :: { [Player]: { number } }
	self.times = {} :: { [Player]: number }
	self.botPlans = {} :: { [Player]: any }
	self.round = nil :: any
	self:_buildArena(origin)

	-- Boards in an arc round the milk glass (a full ring with 12), each player behind theirs.
	local players = ctx:GetPlayers()
	local count = #players
	local floorY = origin.Y + FLOOR
	local boards = {}
	local spawns = {}
	for index, player in players do
		local angle = (index - (count + 1) / 2) * SLOT
		local outward = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local center = Vector3.new(origin.X, floorY + BOARD_UP, origin.Z) + outward * RING
		local frame = CFrame.lookAt(center, center - outward) -- the board's far side faces the middle
		self.boards[player] = frame
		self.scores[player] = {}
		self.times[player] = 0
		MeshLibrary.Get("CuttingBoard", { CFrame = frame, Parent = ctx.Arena })
		MeshLibrary.Get("DoughSheet", { CFrame = frame + Vector3.new(0, DOUGH, 0), Parent = ctx.Arena })
		MeshLibrary.Get("CookiePlate", {
			Scale = 0.8,
			CFrame = (frame * CFrame.new(9.6, 0, 9.5)) - Vector3.new(0, BOARD_UP, 0),
			Parent = ctx.Arena,
		})
		local stand = frame * CFrame.new(0, 0, STAND)
		table.insert(spawns, CFrame.lookAt(stand.Position, center) - Vector3.new(0, BOARD_UP, 0))
		table.insert(boards, {
			User = player.UserId,
			P = { center.X, center.Y, center.Z },
			Yaw = angle,
		})
		ctx:SetScoreText(player, "0%")
	end
	ctx:SpawnAll(spawns, true)

	for _, id in self.shapeIds do
		ctx:ShareTemplate(id .. "Cookie", MeshLibrary.Get(id .. "Cookie"))
	end
	ctx:ShareTemplate("PastryCutter", MeshLibrary.Get("PastryCutter"))
	ctx:SetSharedJSON("Layout", {
		Boards = boards,
		DoughTop = DOUGH_TOP,
		Shapes = self.shapeIds,
		Center = { origin.X, floorY, origin.Z },
	})
	ctx:SetStatus("Trace the dotted line to cut out the cookie!")
end

-- A giant chocolate-chip cookie on a picnic blanket in a meadow, with a glass of milk in the middle.
function CrazyCutters:_buildArena(origin: Vector3)
	local ctx = self.context
	local arena = ctx.Arena
	Build.Part({
		Name = "Grass",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 900, 900),
		CFrame = flat(CFrame.new(origin - Vector3.new(0, 2, 0))) * CFrame.Angles(0, 0, 0),
		Color = rgb(106, 188, 82),
		Material = Enum.Material.Grass,
		Parent = arena,
	})
	-- Gingham picnic blanket: white cloth with see-through red bands both ways.
	local blanket = 150
	Build.Decor({
		Name = "Blanket",
		Size = Vector3.new(blanket, 0.2, blanket),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, math.rad(12), 0),
		Color = rgb(255, 250, 245),
		Material = Enum.Material.Fabric,
		Parent = arena,
	})
	local stripes = 9
	for index = 1, stripes do
		local offset = (index - (stripes + 1) / 2) * (blanket / stripes)
		for axis = 0, 1 do
			Build.Decor({
				Name = "Gingham",
				Size = Vector3.new(blanket / stripes / 2, 0.04, blanket),
				CFrame = CFrame.new(origin + Vector3.new(0, 0.22 + axis * 0.04, 0))
					* CFrame.Angles(0, math.rad(12) + axis * math.pi / 2, 0)
					* CFrame.new(offset, 0, 0),
				Color = rgb(230, 60, 70),
				Transparency = 0.35,
				Material = Enum.Material.Fabric,
				Parent = arena,
			})
		end
	end
	MeshLibrary.Get("GiantCookie", { CFrame = CFrame.new(origin + Vector3.new(0, 0.3, 0)), Parent = arena })
	-- What everyone stands on: the cookie's top is a little lumpy, so a flat invisible floor.
	Build.Part({
		Name = "CookieFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 112, 112),
		CFrame = flat(CFrame.new(origin + Vector3.new(0, FLOOR - 0.5, 0))),
		Transparency = 1,
		CastShadow = false,
		Parent = arena,
	})
	local top = origin + Vector3.new(0, FLOOR, 0)
	MeshLibrary.Get("MilkGlass", {
		CFrame = CFrame.new(top) * CFrame.Angles(0, math.rad(200), 0),
		Parent = arena,
	})
	MeshLibrary.Get("StarCutter", {
		Scale = 1.3,
		CFrame = CFrame.new(top + Vector3.new(14, 0, 9)) * CFrame.Angles(0, math.rad(25), 0),
		Parent = arena,
	})
	MeshLibrary.Get("HeartCutter", {
		Scale = 1.3,
		CFrame = CFrame.new(top + Vector3.new(-15, 0, -6)) * CFrame.Angles(0, math.rad(-40), 0),
		Parent = arena,
	})
	MeshLibrary.Get("RollingPin", {
		CFrame = CFrame.new(top + Vector3.new(3, 0, -17)) * CFrame.Angles(0, math.rad(15), 0),
		Parent = arena,
	})
	-- A ring of trees and flowering bushes well beyond the blanket.
	local leafColors = { rgb(80, 190, 90), rgb(110, 200, 80), rgb(70, 165, 95), rgb(140, 205, 85) }
	for index = 0, 27 do
		local angle = (index + rng:NextNumber(-0.35, 0.35)) / 28 * math.pi * 2
		local distance = rng:NextNumber(105, 150)
		MeshLibrary.Get("Tree", {
			Scale = rng:NextNumber(2, 3.2),
			Colors = { Leaves = leafColors[rng:NextInteger(1, #leafColors)] },
			CFrame = CFrame.new(origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = arena,
		})
	end
	local flowerColors = { rgb(255, 130, 190), rgb(255, 220, 90), rgb(180, 140, 255), rgb(255, 255, 255) }
	for index = 0, 15 do
		local angle = (index + rng:NextNumber(-0.4, 0.4)) / 16 * math.pi * 2
		local distance = rng:NextNumber(84, 98)
		MeshLibrary.Get("Bush", {
			Scale = rng:NextNumber(1.4, 2.2),
			Colors = { Flowers = flowerColors[rng:NextInteger(1, #flowerColors)] },
			CFrame = CFrame.new(origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			Parent = arena,
		})
	end
end

-- Shape `index` of the game: shown for a moment, then cut, then scored; then the next one.
function CrazyCutters:_startShape(index: number)
	local ctx = self.context
	local id = self.shapeIds[index]
	local shape = Rules.Get(id) :: Rules.Shape
	local now = ctx:Now()
	local t0 = now + SHOW + (if index == 1 then 0.6 else 0)
	self.round = {
		Index = index,
		Count = #self.shapeIds,
		Shape = id,
		T0 = t0,
		T1 = t0 + shape.Time,
		Phase = "Cut",
	}
	self.tracks = {}
	self.botPlans = {}
	for _, player in ctx:GetPlayers() do
		local track = Rules.Tracker(shape) :: Track
		track.LastT = t0
		self.tracks[player] = track
	end
	self:_shareRound()
	ctx:SetStatus(`Cookie {index} of {#self.shapeIds}: {string.upper(id)}!`)
end

function CrazyCutters:_shareRound()
	local round = self.round
	self.context:SetSharedJSON("Round", {
		Index = round.Index,
		Count = round.Count,
		Shape = round.Shape,
		T0 = round.T0,
		T1 = round.T1,
		Phase = round.Phase,
	})
end

-- The cut is over: everyone's score for this shape is final.
function CrazyCutters:_finishShape()
	local ctx = self.context
	local round = self.round
	round.Phase = "Score"
	round.T1 = math.min(round.T1, ctx:Now())
	self:_shareRound()
	-- Positions sent just before the end may still be on their way: score a moment later.
	ctx:Delay(0.35, function()
		local results = {}
		for player, track in self.tracks do
			if not player.Parent then
				continue
			end
			local score = track:Score()
			table.insert(self.scores[player], score)
			local took = if track.DoneAt then track.DoneAt - round.T0 else round.T1 - round.T0
			self.times[player] += took
			results[tostring(player.UserId)] = score
			local total = 0
			for _, value in self.scores[player] do
				total += value
			end
			ctx:SetScoreText(player, `{math.floor(total / #self.scores[player] + 0.5)}%`)
		end
		ctx:Fire(nil, "Scores", round.Index, results)
	end)
	ctx:Delay(SCORE_TIME, function()
		if round.Index < #self.shapeIds then
			self:_startShape(round.Index + 1)
		else
			ctx:End("AllCut")
		end
	end)
end

-- A batch of cutter positions from a player's device (or a bot): flat { t, u, v, t, u, v, ... }.
function CrazyCutters:_onCut(player: Player, index: any, data: any)
	local ctx = self.context
	local round = self.round
	local track = self.tracks[player]
	if not round or round.Phase ~= "Cut" or index ~= round.Index or not track or track.Done then
		return
	end
	if type(data) ~= "table" or #data % 3 ~= 0 or #data == 0 or #data > Rules.MAX_CHUNK * 3 then
		return
	end
	local now = ctx:Now()
	local ok, ping = pcall(function()
		return (player :: any):GetNetworkPing()
	end)
	local lag = if ok and type(ping) == "number" then math.clamp(ping, 0, 0.5) else 0.2
	if now < round.T0 - 0.2 or now > round.T1 + lag + 0.3 then
		return
	end
	local accepted = {}
	local limit = Rules.LIMIT + 0.05
	for at = 1, #data, 3 do
		local t, u, v = data[at], data[at + 1], data[at + 2]
		if type(t) ~= "number" or type(u) ~= "number" or type(v) ~= "number" then
			return
		end
		if t ~= t or u ~= u or v ~= v then
			return -- NaN
		end
		-- In order, inside the cut's time (never ahead of the server's clock), on the dough, and no
		-- further from the last position than the cutter can travel.
		if
			t < track.LastT + Rules.SAMPLE_GAP * 0.5
			or t < round.T0 - 0.05
			or t > math.min(now + 0.1, round.T1 + 0.05)
		then
			continue
		end
		if math.abs(u) > limit or math.abs(v) > limit then
			continue
		end
		local reach = Rules.MAX_SPEED * 1.25 * (t - track.LastT) + 0.25
		if (u - track.U) ^ 2 + (v - track.V) ^ 2 > reach * reach then
			continue
		end
		track.LastT = t
		track:Add(u, v)
		table.insert(accepted, math.floor(t * 1000 + 0.5) / 1000)
		table.insert(accepted, math.floor(u * 100 + 0.5) / 100)
		table.insert(accepted, math.floor(v * 100 + 0.5) / 100)
		if track.Done then
			track.DoneAt = t
			break
		end
	end
	if #accepted > 0 then
		ctx:Fire(nil, "Cut", player.UserId, round.Index, accepted)
	end
	if track.Done then
		ctx:Fire(nil, "Done", player.UserId, round.Index, track:Score())
		self:_checkAllDone()
	end
end

function CrazyCutters:_checkAllDone()
	local round = self.round
	if not round or round.Phase ~= "Cut" then
		return
	end
	for player, track in self.tracks do
		if player.Parent and not track.Done then
			return
		end
	end
	self:_finishShape()
end

function CrazyCutters:Start()
	local ctx = self.context
	-- Everyone stays at their board.
	for _, player in ctx:GetPlayers() do
		ctx:SetWalkSpeed(player, 0)
	end
	ctx.Hooks.CharacterReady = function(player)
		ctx:SetWalkSpeed(player, 0)
	end
	ctx.Hooks.Respawn = function(player)
		local frame = self.boards[player]
		if not frame then
			return nil
		end
		local stand = frame * CFrame.new(0, 0, STAND)
		return CFrame.lookAt(stand.Position, frame.Position) - Vector3.new(0, BOARD_UP, 0)
	end
	ctx.Hooks.PlayerLeft = function(player)
		self.tracks[player] = nil
		self:_checkAllDone()
	end

	ctx:OnAction("Cut", function(player, index, data)
		self:_onCut(player, index, data)
	end, { Interval = 0.08 })

	self:_startShape(1)
	ctx:Loop(function(): number?
		local round = self.round
		if round and round.Phase == "Cut" and ctx:Now() >= round.T1 then
			self:_finishShape()
		end
		return 0.1
	end)
end

-- Bots -------------------------------------------------------------------------------------------

-- A gaussian-ish wobble: two sine waves at odd rates, so it never looks regular.
local function wobble(plan, t: number): number
	local value = math.sin(t * plan.W1 + plan.P1) * 0.65 + math.sin(t * plan.W2 + plan.P2) * 0.35
	-- Now and then a slip: a quick swerve off the line and back.
	for _, slip in plan.Slips do
		local x = (t - slip.At) / 0.45
		if x > 0 and x < 1 then
			value += slip.Size * math.sin(x * math.pi)
		end
	end
	return value * plan.Amp
end

-- The next cutter positions for a bot (or a test player) of this skill (0..1), up to `now`, in the
-- same flat { t, u, v, ... } form a client sends. Skilled cutters are steadier and quicker.
function CrazyCutters:BotSamples(player: Player, skill: number, random: Random, now: number): { number }?
	local round = self.round
	if not round or round.Phase ~= "Cut" or now < round.T0 then
		return nil
	end
	local track = self.tracks[player]
	if not track or track.Done then
		return nil
	end
	local shape = Rules.Get(round.Shape) :: Rules.Shape
	local plan = self.botPlans[player]
	if not plan or plan.Index ~= round.Index then
		local slips = {}
		local start = round.T0 + 0.25 + (1 - skill) * 0.6 + random:NextNumber(0, 0.35)
		local speed = (2.4 + 3.2 * skill) * random:NextNumber(0.88, 1.12) / (1 + 0.08 * (shape.Tier - 1))
		local t = start
		local finish = start + shape.Length / speed
		while t < finish do
			t += random:NextNumber(1.2, 4) / (0.25 + (1 - skill) * 1.2)
			if t < finish then
				table.insert(
					slips,
					{ At = t, Size = random:NextNumber(0.9, 1.8) * (if random:NextNumber() < 0.5 then -1 else 1) }
				)
			end
		end
		plan = {
			Index = round.Index,
			Start = start,
			Speed = speed,
			Amp = 0.12 + 1.0 * (1 - skill) ^ 1.5,
			W1 = random:NextNumber(1.6, 2.6),
			W2 = random:NextNumber(4.5, 6.5),
			P1 = random:NextNumber(0, 6.28),
			P2 = random:NextNumber(0, 6.28),
			Slips = slips,
			Last = round.T0,
		}
		self.botPlans[player] = plan
	end
	local out = {}
	local t = math.max(plan.Last, plan.Start)
	while t + 0.07 <= now and #out < Rules.MAX_CHUNK * 3 do
		t += 0.07
		local s = (t - plan.Start) * plan.Speed
		local u, v, du, dv
		if s >= shape.Length then
			u, v = shape.U[1], shape.V[1] -- the lap is closed: back at the start
		else
			u, v, du, dv = Rules.PointAt(shape, s)
			local w = wobble(plan, t)
			-- Ease in from the start and out at the end, where a player slows down to line up.
			w *= math.clamp(s / 2, 0.3, 1) * math.clamp((shape.Length - s) / 2, 0.3, 1)
			u, v = u - dv * w, v + du * w
		end
		table.insert(out, t)
		table.insert(out, math.clamp(u, -Rules.LIMIT, Rules.LIMIT))
		table.insert(out, math.clamp(v, -Rules.LIMIT, Rules.LIMIT))
		if s >= shape.Length then
			break
		end
	end
	plan.Last = t
	return if #out > 0 then out else nil
end

-- Best average wins; the quicker cutter wins a tie.
function CrazyCutters:GetResults()
	local ctx = self.context
	local entries = {}
	for _, player in ctx:GetPlayers() do
		if not player.Parent then
			continue
		end
		local scores = self.scores[player] or {}
		local total = 0
		for _, value in scores do
			total += value
		end
		local average = if #scores > 0 then total / #scores else 0
		table.insert(entries, {
			Player = player,
			Rank = math.floor(average * 10 + 0.5) / 10 + math.max(0, 0.099 - (self.times[player] or 0) / 1000),
			ScoreText = `{math.floor(average + 0.5)}% avg`,
			BestScore = math.floor(average + 0.5),
		})
	end
	return { Entries = entries }
end

return CrazyCutters

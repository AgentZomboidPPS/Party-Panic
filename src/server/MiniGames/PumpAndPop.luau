-- Pump & Pop (Team, 35s, 2-12 players). After "Balloon Burst" (Mario Party, 2 vs. 2): each team
-- pumps air into its own balloon with plunger pumps, and the first team to burst its balloon wins.
--
-- The players split into 2-4 teams (Teams.CountFor). Every team has a station on an arc facing the
-- middle: an air tank with a big balloon tied to it and one floor pump per member, in an arc in
-- front of the tank. Pumping is a rhythm: hold PUMP to push the plunger down while a meter fills,
-- and let go in the green band at the top for a full pump. Let go early and it's a weak puff; hold
-- past the top and the air hisses out. Then the plunger springs back up and you go again.
--
-- The server times every press itself from the Down and Up actions (with leeway for the player's
-- ping, a minimum cycle and at most one full pump of air per press): a client never says how much
-- air it pumped. Air needed grows with team size, so uneven teams are fair. The team's air is
-- shared ("Air_<Team>", 0..1) and each client grows, wobbles and pops the balloons from it; the
-- "Push" and "Pump" events animate everyone's plungers, bots' included. First team to pop wins;
-- when time runs out the fullest balloon wins and bursts anyway (team scores are the balloons'
-- percentages; the results rank the exact fill, so 99% vs 99% still has a winner).
--
-- Bots press Down and Up through ctx:BotAction with skill-based timing (Bots/PumpAndPop.luau);
-- there are no hazards here, so nothing needs a separate server check for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Teams = require(ReplicatedStorage.Shared.Teams)

local MiniGame = require(script.Parent.Kit.MiniGame)
local Scenery = require(script.Parent.Kit.Scenery)
local Build = require(script.Parent.Parent.World.Build)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)

local PumpAndPop = MiniGame.Define("PumpAndPop", { Results = "Team" })

-- Pump timing (seconds). The clients draw the meter from the same numbers (shared in "Layout").
PumpAndPop.FILL_TIME = 0.6 -- holding this long fills the meter to the top
PumpAndPop.SWEET = 0.72 -- from this much of the meter to the top is a full pump
PumpAndPop.SPRING = 0.22 -- the plunger springs back up for this long after a pump
PumpAndPop.STUCK = 1.6 -- a plunger held down this long slips back up (the air is lost)
PumpAndPop.PUMPS_PER_PLAYER = 22 -- full pumps per team member to pop the balloon

-- Balloon size (its scale; 1 = 15 studs tall) from empty to bursting. Clients use these too.
PumpAndPop.EMPTY_SCALE = 0.45
PumpAndPop.FULL_SCALE = 1.12

-- A shape for every team, so a team never reads by color alone.
PumpAndPop.Shapes = { Red = "★", Blue = "●", Green = "▲", Yellow = "◆" }

local ARC_RADIUS = 38 -- the stations face a point this far in front of them
local STATION_GAP = 20 -- between neighboring stations (the biggest balloon is ~14 wide)
local PAD_RADIUS = 9.4
local PLUNGER_DISTANCE = 7.5 -- tank center to each pump (the pump's hose is made for this)
local STAND_DISTANCE = 9.1 -- tank center to where the player stands
local PLUNGER_SPREAD = math.rad(30) -- between neighboring pumps around the tank
local TANK_TOP = 4.6 -- where the balloon's knot sits on the tank
local REACH = 7 -- how far from their spot a player may be and still pump

type Pumper = {
	Team: string,
	Spot: CFrame,
	Plunger: Vector3,
	Down: boolean,
	DownAt: number,
	UpAt: number,
	LastDownAt: number,
	Pumps: number,
	Perfect: number,
	Air: number,
}

type Station = {
	Team: string,
	CFrame: CFrame,
	Members: { Player },
	Air: number,
	Need: number,
	Shown: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function upright(position: Vector3): CFrame
	return CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
end

-- Slides a prop sideways so its piece `name` stands right over `spot` (a prop's pivot is the middle
-- of its whole footprint: the pump's hose and the tank's valve wheel pull it off the barrel/body).
local function centerOn(model: Model, name: string, spot: Vector3)
	local piece = model:FindFirstChild(name, true) :: BasePart?
	if piece then
		local offset = spot - piece.Position
		model:PivotTo(model:GetPivot() + Vector3.new(offset.X, 0, offset.Z))
	end
end

-- How much air a press held for `held` seconds is worth, with `leeway` seconds of slack on both
-- edges of the green band. Returns the air (0..1) and its kind: "perfect", "weak" or "over".
function PumpAndPop.Judge(held: number, leeway: number): (number, string)
	local fill = PumpAndPop.FILL_TIME
	if held > fill + leeway then
		return 0.1, "over"
	elseif held >= fill * PumpAndPop.SWEET - leeway then
		return 1, "perfect"
	end
	local meter = math.clamp(held / (fill * PumpAndPop.SWEET), 0, 1)
	return 0.15 + 0.45 * meter, "weak"
end

-- Slack for a press's timing: the Down and Up messages each wander by part of the player's ping.
local function leewayFor(player: Player): number
	local ok, ping = pcall(function()
		return (player :: any):GetNetworkPing()
	end)
	local lag = if ok and type(ping) == "number" then ping else 0.1
	return math.clamp(lag * 0.6, 0.03, 0.12)
end

function PumpAndPop:Prepare()
	local ctx = self.context
	ctx.RespawnMode = "Respawn"
	ctx.EndWhenOneLeft = false
	ctx.KillY = ctx.Origin.Y - 30
	local origin = ctx.Origin.Position
	self.pumpers = {} :: { [Player]: Pumper }
	self.stations = {} :: { [string]: Station }
	self.order = {} :: { string }
	self.winner = nil :: string?

	local players = ctx:GetPlayers()
	local names = {}
	-- (A solo test gets a single station instead of an empty rival that can never fill.)
	for index = 1, math.min(Teams.CountFor(#players, 3), math.max(#players, 1)) do
		table.insert(names, Teams.Order[index])
	end
	local teams = ctx:AssignTeams(names)

	-- The stations sit on an arc facing a point in front of them, placed so the row is centered on
	-- the arena: neighbors see each other's balloons, and everyone faces the same way.
	local step = STATION_GAP / ARC_RADIUS
	local depth = 0
	for index = 1, #names do
		depth += math.cos((index - (#names + 1) / 2) * step) * ARC_RADIUS / #names
	end
	local focus = origin + Vector3.new(0, 0, depth)
	local span = math.sin(((#names - 1) / 2) * step) * ARC_RADIUS -- the outer stations' distance from the middle
	local stageRadius = math.sqrt(span * span + 16) + PAD_RADIUS + 6

	-- A sunny fairground: meadow, a round stage and bunches of party balloons around the back.
	Scenery.Meadow(ctx, origin, 300)
	local stageCenter = origin + Vector3.new(0, 0, 3)
	Build.Part({
		Name = "Stage",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.75, stageRadius * 2, stageRadius * 2),
		CFrame = upright(stageCenter + Vector3.new(0, 0.075, 0)),
		Color = rgb(250, 240, 222),
		Material = Enum.Material.SmoothPlastic,
		Parent = ctx.Arena,
	})
	Build.Decor({
		Name = "StageTrim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.75, stageRadius * 2 + 2, stageRadius * 2 + 2),
		CFrame = upright(stageCenter + Vector3.new(0, -0.125, 0)),
		Color = rgb(255, 196, 80),
		Parent = ctx.Arena,
	})

	local layout = {}
	local spotOf = {} :: { [Player]: CFrame }
	for index, team in names do
		local angle = (index - (#names + 1) / 2) * step
		local center = focus + Vector3.new(math.sin(angle) * ARC_RADIUS, 0, -math.cos(angle) * ARC_RADIUS)
		local forward = flat(focus - center).Unit
		local cframe = CFrame.lookAt(center, center + forward) -- -Z (the props' fronts) faces the players
		local color = Teams.Colors[team]
		local members = teams[team] or {}
		-- Every other station stands a little higher, so neighbors' rims never share a plane.
		local lift = (index % 2) * 0.45

		Build.Part({
			Name = "Pad_" .. team,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, PAD_RADIUS * 2, PAD_RADIUS * 2),
			CFrame = upright(center + Vector3.new(0, 0.55 + lift, 0)),
			Color = color:Lerp(Color3.new(1, 1, 1), 0.55),
			Material = Enum.Material.SmoothPlastic,
			Parent = ctx.Arena,
		})
		Build.Decor({
			Name = "PadRim_" .. team,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, PAD_RADIUS * 2 + 0.7, PAD_RADIUS * 2 + 0.7),
			CFrame = upright(center + Vector3.new(0, 0.35 + lift, 0)),
			Color = color,
			Parent = ctx.Arena,
		})
		local floor = cframe + Vector3.new(0, 0.85 + lift, 0)
		local tank = MeshLibrary.Get("AirTank", { CFrame = floor, Parent = ctx.Arena })
		centerOn(tank, "Tank", floor.Position)
		tank.Name = "Tank_" .. team
		local balloon = MeshLibrary.Get("PumpBalloon", {
			Scale = PumpAndPop.EMPTY_SCALE,
			Colors = { Skin = color, Blush = color:Lerp(Color3.new(1, 1, 1), 0.45) },
			CFrame = floor + Vector3.new(0, TANK_TOP, 0),
			Parent = ctx.Arena,
		})
		balloon.Name = "Balloon_" .. team
		centerOn(balloon, "Skin", floor.Position)
		for _, part in balloon:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				-- The worried face appears as it fills (the client shows these pieces).
				if part.Name == "Ooh" or part.Name == "Brows" or part.Name == "Sweat" then
					part.Transparency = 1
				end
			end
		end
		-- The team's name and shape float high over the station, above the biggest balloon.
		local tankRoot = tank.PrimaryPart or tank:FindFirstChildWhichIsA("BasePart", true)
		if tankRoot then
			Build.Billboard(tankRoot :: BasePart, `{PumpAndPop.Shapes[team]} {string.upper(team)}`, {
				Name = "TeamLabel",
				Size = UDim2.fromOffset(190, 52),
				StudsOffset = Vector3.new(0, 22, 0),
				MaxDistance = 400,
				TextColor3 = color,
			})
		end

		local plungers = {}
		for slot, player in members do
			local turn = (slot - (#members + 1) / 2) * PLUNGER_SPREAD
			local direction = (cframe * CFrame.Angles(0, turn, 0)).LookVector
			local plungerAt = floor.Position + direction * PLUNGER_DISTANCE
			local plunger = MeshLibrary.Get("Plunger", {
				Colors = { Barrel = color },
				CFrame = CFrame.lookAt(plungerAt, Vector3.new(center.X, plungerAt.Y, center.Z)),
				Parent = ctx.Arena,
			})
			centerOn(plunger, "Barrel", plungerAt)
			plunger.Name = "Plunger_" .. player.UserId
			plunger:SetAttribute("Team", team)
			local stand = floor.Position + direction * STAND_DISTANCE
			local spot = CFrame.lookAt(stand, Vector3.new(center.X, stand.Y, center.Z))
			spotOf[player] = spot
			self.pumpers[player] = {
				Team = team,
				Spot = spot,
				Plunger = plungerAt,
				Down = false,
				DownAt = 0,
				UpAt = -math.huge,
				LastDownAt = -math.huge,
				Pumps = 0,
				Perfect = 0,
				Air = 0,
			}
			table.insert(plungers, { User = player.UserId, Pos = { plungerAt.X, plungerAt.Y, plungerAt.Z } })
		end

		self.stations[team] = {
			Team = team,
			CFrame = floor,
			Members = members,
			Air = 0,
			Need = PumpAndPop.PUMPS_PER_PLAYER * math.max(#members, 1),
			Shown = 0,
		}
		table.insert(self.order, team)
		table.insert(layout, {
			Team = team,
			Shape = PumpAndPop.Shapes[team],
			Pos = { floor.X, floor.Y, floor.Z },
			Plungers = plungers,
		})
		ctx:SetShared("Air_" .. team, 0)
	end

	-- Party balloons tied in bunches behind the stations, in the teams' colors.
	local decor = Random.new()
	for index = 0, 8 do
		local angle = (index - 4) * 0.21
		local spot = focus + Vector3.new(math.sin(angle) * 70, 0, -math.cos(angle) * 70)
		for bunch = 1, 3 do
			local team = names[decor:NextInteger(1, #names)]
			MeshLibrary.Get("Balloon", {
				Scale = decor:NextNumber(0.9, 1.25),
				Colors = { Balloon = Teams.Colors[team] },
				CFrame = CFrame.new(spot + Vector3.new(decor:NextNumber(-2, 2), 0, decor:NextNumber(-2, 2)))
					* CFrame.Angles(0, decor:NextNumber(0, math.pi * 2), (bunch - 2) * 0.12),
				Parent = ctx.Arena,
			})
		end
	end

	ctx:SetSharedJSON("Layout", {
		Stations = layout,
		Fill = PumpAndPop.FILL_TIME,
		Sweet = PumpAndPop.SWEET,
		Spring = PumpAndPop.SPRING,
		Stuck = PumpAndPop.STUCK,
		Empty = PumpAndPop.EMPTY_SCALE,
		Full = PumpAndPop.FULL_SCALE,
	})

	local points = {}
	for _, player in players do
		table.insert(points, spotOf[player] or CFrame.new(focus))
	end
	ctx:SpawnAll(points, true)
	ctx.Hooks.Respawn = function(player)
		local pumper = self.pumpers[player]
		return if pumper then pumper.Spot else nil
	end
	for _, player in players do
		ctx:SetScoreText(player, "0 perfect")
	end
	ctx:SetStatus("Hold PUMP, let go in the green!")

	-- Leaving is handled from now on (the rules card and countdown included); Start also catches
	-- anyone who left or failed to spawn before this was set.
	ctx.Hooks.PlayerLeft = function(player)
		self:_leave(player)
	end
end

-- A team that loses members needs less air in all (the same per player as every other team); a
-- team with nobody left drops out of the scores and its pill says so.
function PumpAndPop:_leave(player: Player)
	local ctx = self.context
	local pumper = self.pumpers[player]
	self.pumpers[player] = nil
	if pumper and pumper.Down then
		ctx:Fire(nil, "Pump", player.UserId, 0, "none") -- their plunger springs back up everywhere
	end
	local station = pumper and self.stations[pumper.Team]
	if not station then
		return
	end
	local index = table.find(station.Members, player)
	if index then
		table.remove(station.Members, index)
	end
	if #station.Members == 0 then
		ctx:SetShared("Gone_" .. station.Team, true)
		if self.winner ~= station.Team then
			ctx:AddTeamScore(station.Team, -station.Shown)
			station.Shown = 0
			station.Air = 0
			ctx:SetShared("Air_" .. station.Team, 0)
		end
		return
	end
	-- The balloon stays as full as it was; what's left to pump shrinks with the team.
	local need = PumpAndPop.PUMPS_PER_PLAYER * #station.Members
	station.Air *= need / station.Need
	station.Need = need
	self:_publish(station)
end

-- The team's balloon as a whole percentage (what the team scores show).
function PumpAndPop:_percent(station: Station): number
	return math.clamp(math.floor(station.Air / station.Need * 100), 0, if self.winner == station.Team then 100 else 99)
end

function PumpAndPop:_publish(station: Station)
	local ctx = self.context
	ctx:SetShared("Air_" .. station.Team, math.floor(math.min(station.Air / station.Need, 1) * 1000) / 1000)
	local percent = self:_percent(station)
	if percent ~= station.Shown then
		ctx:AddTeamScore(station.Team, percent - station.Shown)
		station.Shown = percent
	end
end

function PumpAndPop:_pop(station: Station)
	local ctx = self.context
	self.winner = station.Team
	self:_publish(station)
	ctx:SetShared("Popped", station.Team)
	ctx:Fire(nil, "Pop", station.Team)
	ctx:Announce(`{PumpAndPop.Shapes[station.Team]} {string.upper(station.Team)} POPPED IT!`, "success", 2.5)
	ctx:SetStatus(`{string.upper(station.Team)} wins!`)
	ctx:Delay(2.6, function()
		ctx:End("Popped")
	end)
end

function PumpAndPop:_down(player: Player)
	local pumper = self.pumpers[player]
	if not pumper or self.winner then
		return
	end
	local ctx = self.context
	local now = ctx:Now()
	if pumper.Down and now - pumper.DownAt > PumpAndPop.STUCK - 0.15 then
		self:_up(player, true) -- a re-press right after a stuck hold: slip that one now
	end
	if pumper.Down then
		return
	end
	local _, _, root = ctx:GetCharacter(player)
	if not root or (flat(root.Position) - flat(pumper.Spot.Position)).Magnitude > REACH then
		return
	end
	-- A press that arrives while the plunger is still springing back (network jitter) counts, but
	-- its hold starts once the plunger is up; and presses are never closer than a full cycle,
	-- whatever the ping, so an early Down gains nothing.
	local leeway = leewayFor(player)
	local start = math.max(
		now,
		pumper.UpAt + PumpAndPop.SPRING - leeway,
		pumper.LastDownAt + PumpAndPop.FILL_TIME * PumpAndPop.SWEET + PumpAndPop.SPRING - 0.12
	)
	pumper.Down = true
	pumper.DownAt = start
	pumper.LastDownAt = start
	ctx:Fire(nil, "Push", player.UserId)
end

function PumpAndPop:_up(player: Player, slipped: boolean?)
	local pumper = self.pumpers[player]
	if not pumper or not pumper.Down then
		return
	end
	local ctx = self.context
	local now = ctx:Now()
	pumper.Down = false
	pumper.UpAt = now
	local station = self.stations[pumper.Team]
	if self.winner or not station then
		ctx:Fire(nil, "Pump", player.UserId, 0, "none") -- the plunger springs back, no verdict
		return
	end
	local air, kind = 0, "over"
	if not slipped then
		air, kind = PumpAndPop.Judge(math.max(now - pumper.DownAt, 0), leewayFor(player))
	end
	pumper.Pumps += 1
	pumper.Air += air
	if kind == "perfect" then
		pumper.Perfect += 1
	end
	station.Air += air
	ctx:AddScore(player, math.floor(air * 10 + 0.5))
	ctx:SetScoreText(player, `{pumper.Perfect} perfect`)
	ctx:Fire(nil, "Pump", player.UserId, air, kind)
	if station.Air >= station.Need then
		self:_pop(station)
	else
		self:_publish(station)
	end
end

function PumpAndPop:Start()
	local ctx = self.context
	self.started = true
	-- Everyone stays at their pump (jumping still works, for joy).
	for _, player in ctx:GetPlayers() do
		ctx:SetWalkSpeed(player, 0)
	end
	ctx.Hooks.CharacterReady = function(player)
		ctx:SetWalkSpeed(player, 0)
	end

	ctx:OnAction("Down", function(player)
		self:_down(player)
	end, { Interval = 0.08 })
	ctx:OnAction("Up", function(player)
		self:_up(player)
	end, { Interval = 0.08 })

	-- Anyone who left (or never spawned) before the hook was set.
	local gone = {}
	for player in self.pumpers do
		if not ctx:State(player) then
			table.insert(gone, player)
		end
	end
	for _, player in gone do
		self:_leave(player)
	end

	-- Plungers held down too long slip back up, and the status line shows who's ahead.
	local lastStatus = 0
	ctx:Loop(function(): number?
		local now = ctx:Now()
		for player, pumper in self.pumpers do
			if pumper.Down and now - pumper.DownAt > PumpAndPop.STUCK then
				self:_up(player, true)
			end
		end
		if not self.winner and now - lastStatus > 1 then
			lastStatus = now
			local best, bestAir = nil, -1
			for _, team in self.order do
				local station = self.stations[team]
				local fill = station.Air / station.Need
				if #station.Members > 0 and fill > bestAir then
					best, bestAir = team, fill
				end
			end
			if best and bestAir > 0 then
				ctx:SetStatus(`{PumpAndPop.Shapes[best]} {string.upper(best)} leads: {math.floor(bestAir * 100)}%`)
			end
		end
		return 0.1
	end)
end

-- How full a team's balloon is, exactly (1 for the team that popped it).
function PumpAndPop:_fill(team: string): number
	local station = self.stations[team]
	if not station then
		return 0
	end
	return if self.winner == team then 1 else math.min(station.Air / station.Need, 0.999)
end

-- The fullest balloon among teams that still have players, or nil on an exact tie (or no air).
function PumpAndPop:_leader(): string?
	if self.winner then
		return self.winner
	end
	local best, bestFill, tie = nil, 0, false
	for _, team in self.order do
		local fill = self:_fill(team)
		if #self.stations[team].Members == 0 then
			continue
		elseif fill > bestFill then
			best, bestFill, tie = team, fill, false
		elseif fill == bestFill and fill > 0 then
			tie = true
		end
	end
	return if tie then nil else best
end

-- Time's up with nobody popped: the fullest balloon bursts anyway, so every round ends with a bang.
function PumpAndPop:Stop(reason: string?)
	if reason ~= "TimeUp" or self.winner or not self.started then
		return
	end
	local ctx = self.context
	local team = self:_leader()
	if team then
		ctx:SetShared("Popped", team)
		ctx:Fire(nil, "Pop", team)
		ctx:Announce(`{PumpAndPop.Shapes[team]} {string.upper(team)} WINS!`, "success", 2.5)
	end
end

-- Team results (best balloon first, by exact fill); each player's line shows their own pumps.
function PumpAndPop:GetResults()
	local results = self.context:TeamResults()
	for _, entry in results.Entries do
		local station = entry.Team and self.stations[entry.Team]
		if station then
			entry.Rank = self:_fill(entry.Team) * 100
		end
		local pumper = self.pumpers[entry.Player]
		if pumper then
			entry.ScoreText =
				`{entry.Team} {station and self:_percent(station) or 0}% • {pumper.Pumps} pumps, {pumper.Perfect} perfect`
		end
	end
	results.WinningTeam = self:_leader()
	return results
end

return PumpAndPop

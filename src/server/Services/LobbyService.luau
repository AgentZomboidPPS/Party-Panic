-- Lobby activities (design doc §5): daily reward machine, confetti cannon, the hidden daily token,
-- the arcade target range, the champion podium, beach balls to kick around and the obby's
-- checkpoints. (Votes come from the cards on screen; the stage's portals just preview the games.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local DailyLogic = require(Shared.Logic.DailyLogic)
local GameState = require(Shared.GameState)
local ParkourCourse = require(Shared.Logic.ParkourCourse)

local BeachBalls = require(script.Parent.Parent.World.BeachBalls)
local Build = require(script.Parent.Parent.World.Build)
local LobbyBuilder = require(script.Parent.Parent.World.LobbyBuilder)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local ClientReports = require(script.Parent.ClientReports)
local Notifier = require(script.Parent.Notifier)
local SocialService = require(script.Parent.SocialService)
local Telemetry = require(script.Parent.Telemetry)

local LobbyService = {}

local refs: LobbyBuilder.LobbyRefs

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function LobbyService.SetChampions(champions: { { Name: string, UserId: number, Place: number } })
	GameState.SetJSON("Champions", champions)
end

local function setupConfettiCannon()
	local lastFired = 0
	refs.ConfettiPrompt.Triggered:Connect(function(player)
		local now = os.clock()
		if now - lastFired < Config.ConfettiCannonCooldown then
			Notifier.Send(player, "The cannon is reloading...")
			return
		end
		lastFired = now
		Notifier.Effect("Confetti", refs.ConfettiPosition)
		Notifier.Effect("Fireworks", refs.ConfettiPosition + Vector3.new(0, 8, 0))
	end)
end

local function setupDailyMachine()
	refs.DailyPrompt.Triggered:Connect(function(player)
		SocialService.ClaimDaily(player)
	end)
end

-- One hidden token per day at a rotating spot. Found tokens hide per player on the client.
-- At midnight UTC it moves to the new day's spot (a server can run for days), and its Day
-- attribute tells clients which day it is for.
local function setupSecretToken()
	local spots = refs.TokenSpots
	local today = DailyLogic.DayNumber(os.time())
	local spot = spots[(today % #spots) + 1]

	local token = Build.Part({
		Name = "SecretToken",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 2.4, 2.4),
		CFrame = CFrame.new(spot),
		Color = Color3.fromRGB(255, 225, 90),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = true,
		Parent = refs.Root,
	})
	token:SetAttribute("Day", today)
	token:SetAttribute("Spot", spot) -- where it bobs and spins (on each client: WorldScreensController)
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = Color3.fromRGB(255, 240, 150)
	sparkles.Parent = token

	-- A new UTC day: the new spot. True when it just moved.
	local function rollOver(): boolean
		local now = DailyLogic.DayNumber(os.time())
		if now == today then
			return false
		end
		today = now
		spot = spots[(today % #spots) + 1]
		token:SetAttribute("Day", today)
		token:SetAttribute("Spot", spot)
		token.CFrame = CFrame.new(spot)
		return true
	end

	local debounce: { [Player]: number } = {}
	token.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player or rollOver() then
			return -- (a touch at the old spot as the day turns doesn't count for the new day)
		end
		local now = os.clock()
		if now - (debounce[player] or 0) < 2 then
			return
		end
		debounce[player] = now
		if SocialService.ClaimSecretToken(player) then
			Notifier.Effect("Sparkles", token.Position)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		debounce[player] = nil
	end)

	-- A look at the date now and then. (The token's gentle spin is drawn by each client: spinning it
	-- here sent every phone a new position 60 times a second, all game long.)
	local sinceCheck = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceCheck += dt
		if sinceCheck >= 5 then
			sinceCheck = 0
			rollOver()
		end
	end)
end

-- Arcade target range: one lit target at a time; hits count toward a session leaderboard.
local function setupTargetRange()
	local targets = refs.Targets
	local scores: { [Player]: number } = {}
	local lit: BasePart? = nil
	local idleColor = Color3.fromRGB(230, 230, 240)
	local litColor = Color3.fromRGB(255, 80, 80)

	local function updateBoard()
		local list = {}
		for player, score in scores do
			if player.Parent then
				table.insert(list, { name = player.DisplayName, score = score })
			end
		end
		table.sort(list, function(a, b)
			return a.score > b.score
		end)
		local lines = { "🎯 TARGET RANGE - top hitters" }
		for index = 1, math.min(5, #list) do
			table.insert(lines, `{index}. {list[index].name}  {list[index].score}`)
		end
		if #list == 0 then
			table.insert(lines, "Click the red targets!")
		end
		refs.TargetBoard.Text = table.concat(lines, "\n")
	end

	local function lightRandom()
		if lit then
			lit.Color = idleColor
			lit.Material = Enum.Material.SmoothPlastic
		end
		local choice = targets[math.random(1, #targets)]
		if choice == lit and #targets > 1 then
			choice = targets[(table.find(targets, choice) :: number % #targets) + 1]
		end
		lit = choice
		choice.Color = litColor
		choice.Material = Enum.Material.Neon
	end

	for _, target in targets do
		local detector = target:FindFirstChildOfClass("ClickDetector")
		if not detector then
			continue
		end
		detector.MouseClick:Connect(function(player)
			if target ~= lit then
				return
			end
			local root = rootOf(player)
			-- Server-side range check: the client can't score from across the map.
			if not root or (root.Position - target.Position).Magnitude > detector.MaxActivationDistance + 5 then
				return
			end
			scores[player] = (scores[player] or 0) + 1
			Notifier.Sound({ player }, "Pickup")
			lightRandom()
			updateBoard()
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		if scores[player] then
			scores[player] = nil
			updateBoard()
		end
	end)

	task.spawn(function()
		while true do
			lightRandom()
			task.wait(2.5)
		end
	end)
	updateBoard()
end

-- The obby (World/LobbyObby, layout in Shared/Logic/ParkourCourse). The server remembers the last
-- glowing pad each player reached on this run and puts anyone whose feet go down into the goo back on
-- it (falling never costs more than the section you're on), as it does anyone who lands on an earlier
-- section after a fall. The start pad begins a run; the view deck ends it, so jumping off the deck
-- lands you back at the start. Run times are the client's (MovementController).
local function setupParkour()
	local frame = refs.ParkourFrame
	local near = (ParkourCourse.PoolRadius + 10) ^ 2 -- squared: anyone further out is nowhere near
	local total = #ParkourCourse.Checkpoints
	local reached: { [Player]: number } = {}
	local putBackAt: { [Player]: number } = {}

	local function putBack(player: Player, character: Model, root: BasePart, humanoid: Humanoid)
		local x, top, z, fx, fz = ParkourCourse.Respawn(reached[player] or 0)
		local position = frame:PointToWorldSpace(Vector3.new(x, top + root.Size.Y / 2 + humanoid.HipHeight + 0.3, z))
		local look = frame:VectorToWorldSpace(Vector3.new(fx, 0, fz))
		character:PivotTo(CFrame.lookAt(position, position + look))
		root.AssemblyLinearVelocity = Vector3.zero
		putBackAt[player] = os.clock()
		Notifier.Sound({ player }, "Splash")
		Notifier.Effect("Poof", position)
	end

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("PP_InRound") then
				reached[player] = nil
				continue
			end
			local character = player.Character
			local root = rootOf(player)
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not character or not root or not humanoid or humanoid.Health <= 0 then
				continue
			end
			local p = frame:PointToObjectSpace(root.Position)
			if p.X * p.X + p.Z * p.Z > near or now - (putBackAt[player] or 0) < 0.75 then
				continue
			end
			-- Where the feet are (an R15 root's bottom is HipHeight above the ground under it).
			local hip = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
			local feet = p.Y - root.Size.Y / 2 - hip
			local checkpoint, fell, gained = ParkourCourse.Step(reached[player] or 0, p.X, p.Z, feet)
			reached[player] = if checkpoint > 0 then checkpoint else nil
			if fell then
				putBack(player, character, root, humanoid)
			elseif gained then
				Notifier.Send(player, `🚩 Checkpoint {checkpoint}/{total}!`, "success", 2)
				Notifier.Sound({ player }, "Pickup")
			end
		end
	end)

	local function forget(player: Player)
		reached[player] = nil
		putBackAt[player] = nil
	end
	Players.PlayerRemoving:Connect(forget)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			forget(player) -- a new character (reset, or back from a round) starts from the start
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
end

-- Nobody hangs in the air over the lobby (owner: "Friend spawned above the lobby floating. We need
-- to make sure this doesnt happen again."; the cause, a device holding a respawned character in the
-- air, is fixed in Controllers/ArrivalController). Whatever else might ever do it: a lobby player
-- (not in a round's arena) who stays put with nothing solid under their feet for FLOAT_GAP studs,
-- FLOAT_TIME seconds on end, is put back on a spawn pad, and it's written down for the check tools
-- (ClientReports, key m<UserId>: "Lobby Float", where they were) so we'd know it happened.
-- LobbyService.Floating says what it sees for one player (the check tools ask it too).
local FLOAT_GAP = 6 -- studs under the soles with nothing to stand on
local FLOAT_TIME = 4 -- seconds of it, standing still, before the server steps in
local FLOAT_CHECK = 0.5
local FOOTPRINT = Vector3.new(4, 1, 4) -- what's looked under: anything solid there is ground

local floatRays = RaycastParams.new()
floatRays.FilterType = Enum.RaycastFilterType.Exclude
floatRays.RespectCanCollide = true

-- Whether `player` stands still in the lobby with nothing under their feet, and where.
function LobbyService.Floating(player: any): (boolean, string)
	if player:GetAttribute("PP_InRound") == true and player:GetAttribute("PP_Alive") == true then
		return false, "" -- in a round's arena: the mode's business
	end
	local character = player.Character
	local root = rootOf(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 or root.Anchored then
		return false, ""
	end
	if root.AssemblyLinearVelocity.Magnitude > 1 or humanoid:GetState() == Enum.HumanoidStateType.Climbing then
		return false, "" -- walking, jumping or falling: physics is on it
	end
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2
	floatRays.FilterDescendantsInstances = { character }
	floatRays.CollisionGroup = root.CollisionGroup
	-- (a box the size of a generous footprint, so a heel on a ledge counts as standing)
	if workspace:Blockcast(root.CFrame, FOOTPRINT, Vector3.new(0, -(legs + FLOAT_GAP), 0), floatRays) then
		return false, ""
	end
	local below = workspace:Raycast(root.Position, Vector3.new(0, -500, 0), floatRays)
	local p = root.Position
	return true,
		string.format(
			"at (%.1f, %.1f, %.1f), %s below",
			p.X,
			p.Y,
			p.Z,
			if below
				then `{below.Instance:GetFullName()} {math.floor(below.Distance - legs + 0.5)} studs`
				else "nothing"
		)
end

local function setupFloatWatch()
	local since: { [Player]: number } = {}
	local function putOnPad(player: Player, where: string)
		local character = player.Character
		local pads = refs.Root:FindFirstChild("Spawns")
		local list = if pads then pads:GetChildren() else {}
		local pad = list[math.random(1, math.max(1, #list))] :: BasePart?
		if not character or not pad or not pad:IsA("BasePart") then
			return
		end
		character:PivotTo(pad.CFrame + Vector3.new(0, 3, 0))
		local root = rootOf(player)
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
		Telemetry.Error("LobbyFloat", `{player.Name} {where}`)
		ClientReports.Record(player, "Lobby", "Float", `put back on {pad.Name}: stood still {FLOAT_TIME} s {where}`)
	end
	task.spawn(function()
		while true do
			task.wait(FLOAT_CHECK)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local ok, isFloating, where = pcall(LobbyService.Floating, player)
				if not ok or not isFloating then
					since[player] = nil
				elseif now - (since[player] or now) >= FLOAT_TIME then
					since[player] = nil
					putOnPad(player, where)
				else
					since[player] = since[player] or now
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		since[player] = nil
	end)
end

function LobbyService.Init()
	refs = LobbyBuilder.Build()
	MeshLibrary.Preload() -- resolves any props the lobby didn't use and reports mesh sources
	setupConfettiCannon()
	setupDailyMachine()
	setupSecretToken()
	setupTargetRange()
	setupParkour()
	setupFloatWatch()
	BeachBalls.Setup(refs.Root, refs.BallSpots, {
		PlazaRadius = LobbyBuilder.PlazaRadius,
		StageFrontZ = LobbyBuilder.StageFrontZ,
		Traps = LobbyBuilder.BallTraps,
	})
	LobbyService.SetChampions({})
end

return LobbyService

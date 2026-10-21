-- Lobby activities (design doc §5): vote pads, daily reward machine, confetti cannon, the hidden
-- daily token, the arcade target range and the champion podium.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local DailyLogic = require(Shared.Logic.DailyLogic)
local GameState = require(Shared.GameState)

local Build = require(script.Parent.Parent.World.Build)
local LobbyBuilder = require(script.Parent.Parent.World.LobbyBuilder)
local MeshLibrary = require(script.Parent.Parent.World.MeshLibrary)
local Notifier = require(script.Parent.Notifier)
local SocialService = require(script.Parent.SocialService)
local VotingService = require(script.Parent.VotingService)

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
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = Color3.fromRGB(255, 240, 150)
	sparkles.Parent = token

	local debounce: { [Player]: number } = {}
	token.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then
			return
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

	-- Gentle spin (server-side CFrame on one anchored part is cheap).
	local angle = 0
	RunService.Heartbeat:Connect(function(dt)
		angle += dt * 1.5
		token.CFrame = CFrame.new(spot + Vector3.new(0, math.sin(angle * 2) * 0.3, 0)) * CFrame.Angles(0, angle, 0)
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

-- Beach balls to kick around the plaza. Walking into one punts it (the server sets its velocity,
-- so every player sees the same ball); balls that leave the plaza, land on the vote stage or sit
-- far from home for a minute roll back to their spot.
local BALL_KICK_SPEED = 28
local BALL_KICK_LIFT = 22
local BALL_IDLE_RESET = 60

local function setupBeachBalls()
	local folder = Build.Model("BeachBalls", refs.Root)
	for index, spot in refs.BallSpots do
		local home = CFrame.new(spot + Vector3.new(0, 2.5, 0))
		local ball = Build.Part({
			Name = "BeachBall" .. index,
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 5,
			CFrame = home,
			Transparency = 1,
			CustomPhysicalProperties = PhysicalProperties.new(0.12, 0.4, 0.6, 1, 1),
		})
		ball.Anchored = false
		-- The look comes from the mesh prop, welded on and weightless; the ball part is the physics.
		local look = MeshLibrary.Get("LobbyBeachBall", { CFrame = home * CFrame.new(0, -2.5, 0), Parent = ball })
		for _, descendant in look:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				descendant.Massless = true
				Build.Weld(ball, descendant)
			end
		end
		ball.Parent = folder
		ball:SetNetworkOwner(nil)

		local lastKick, lastMoved = 0, os.clock()
		ball.Touched:Connect(function(hit)
			local character = hit.Parent
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not humanoid or not root or humanoid.Health <= 0 then
				return
			end
			local now = os.clock()
			if now - lastKick < 0.35 then
				return
			end
			lastKick = now
			local away = (ball.Position - root.Position) * Vector3.new(1, 0, 1)
			if away.Magnitude < 0.1 then
				away = root.CFrame.LookVector * Vector3.new(1, 0, 1)
			end
			local run = (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
			ball.AssemblyLinearVelocity = away.Unit * (BALL_KICK_SPEED + run * 0.5) + Vector3.new(0, BALL_KICK_LIFT, 0)
			ball.AssemblyAngularVelocity = away.Unit:Cross(Vector3.yAxis) * -6
		end)

		task.spawn(function()
			while ball.Parent do
				task.wait(2)
				local position = ball.Position
				local flat = Vector3.new(position.X, 0, position.Z)
				if ball.AssemblyLinearVelocity.Magnitude > 1 then
					lastMoved = os.clock()
				end
				local outside = position.Y < -10 or flat.Magnitude > LobbyBuilder.PlazaRadius - 2
				local onStage = position.Z < LobbyBuilder.StageFrontZ and math.abs(position.X) < 50
				local idleAway = os.clock() - lastMoved > BALL_IDLE_RESET and (position - home.Position).Magnitude > 20
				if outside or onStage or idleAway then
					ball.AssemblyLinearVelocity = Vector3.zero
					ball.AssemblyAngularVelocity = Vector3.zero
					ball:PivotTo(home)
					lastMoved = os.clock()
				end
			end
		end)
	end
end

function LobbyService.Init()
	refs = LobbyBuilder.Build()
	MeshLibrary.Preload() -- resolves any props the lobby didn't use and reports mesh sources
	for index, pad in refs.VotePads do
		VotingService.BindPad(pad, index)
	end
	setupConfettiCannon()
	setupDailyMachine()
	setupSecretToken()
	setupTargetRange()
	setupBeachBalls()
	LobbyService.SetChampions({})
end

return LobbyService

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
	LobbyService.SetChampions({})
end

return LobbyService

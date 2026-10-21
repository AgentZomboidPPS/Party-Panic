-- Applies equipped cosmetics to characters, grants unlocks, and handles the optional VIP pass.
-- Cosmetics are purely visual (design doc §10 "Economy guardrails").
-- Name tags show the level in its prestige color, which changes every 10 levels, so long-time
-- players stand out in the lobby (owner: "Also we need cool payoffs for players that keep playing
-- the game."; colors in Shared/Progression).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local LevelCurve = require(Shared.Logic.LevelCurve)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local RateLimiter = require(script.Parent.RateLimiter)

local CosmeticService = {}

local NAMEPLATE = "PP_Nameplate"
local TRAIL = "PP_Trail"

local function equippedItem(player: Player, slot: string): Cosmetics.Cosmetic?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local id = profile.Data.Equipped[slot]
	if type(id) ~= "string" or id == "" or not profile.Data.Owned[id] then
		return nil
	end
	return Cosmetics.Get(id)
end

local function buildNameplate(player: Player, head: BasePart)
	local existing = head:FindFirstChild(NAMEPLATE)
	if existing then
		existing:Destroy()
	end
	local profile = DataService.Get(player)
	local level = if profile then LevelCurve.FromTotalXP(profile.Data.XP) else 1
	local title = equippedItem(player, "Title")

	local gui = Instance.new("BillboardGui")
	gui.Name = NAMEPLATE
	gui.Size = UDim2.fromOffset(220, 54)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.RichText = true
	local text, gradient = Progression.NameTag(player.DisplayName, level)
	nameLabel.Text = text
	if gradient then
		local tint = Instance.new("UIGradient")
		tint.Color = gradient
		tint.Parent = nameLabel
	end
	nameLabel.Parent = gui

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromScale(0, 0.55)
	titleLabel.Size = UDim2.new(1, 0, 0.42, 0)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextStrokeTransparency = 0.5
	titleLabel.Text = if title then `{title.Icon} {title.Name}` else ""
	titleLabel.TextColor3 = if title and title.Colors then title.Colors[1] else Color3.new(1, 1, 1)
	titleLabel.Parent = gui

	gui.Parent = head
end

local function applyTrail(player: Player, character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local old = root:FindFirstChild(TRAIL)
	if old then
		old:Destroy()
	end
	for _, name in { "PP_TrailTop", "PP_TrailBottom" } do
		local attachment = root:FindFirstChild(name)
		if attachment then
			attachment:Destroy()
		end
	end

	local item = equippedItem(player, "Trail")
	if not item or not item.Colors then
		return
	end

	local top = Instance.new("Attachment")
	top.Name = "PP_TrailTop"
	top.Position = Vector3.new(0, 0.9, 0.4)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "PP_TrailBottom"
	bottom.Position = Vector3.new(0, -0.9, 0.4)
	bottom.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = TRAIL
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = Cosmetics.ColorSequence(item.Colors)
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.Lifetime = 0.45
	trail.MinLength = 0.2
	trail.LightEmission = 0.4
	trail.FaceCamera = true
	trail.Parent = root
end

function CosmeticService.Refresh(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	if head then
		buildNameplate(player, head)
	end
	applyTrail(player, character)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	character:WaitForChild("HumanoidRootPart", 10)
	character:WaitForChild("Head", 10)
	if player.Parent and player.Character == character then
		CosmeticService.Refresh(player)
	end
end

-- Grants default, level, stat and VIP cosmetics the player qualifies for, once each (owning an
-- item is the record). Returns the ones it just unlocked (not the defaults); `silent` leaves the
-- telling to the caller (ProgressionService celebrates level and milestone unlocks).
function CosmeticService.CheckUnlocks(player: Player, silent: boolean?): { Cosmetics.Cosmetic }
	local unlocked: { Cosmetics.Cosmetic } = {}
	local profile = DataService.Get(player)
	if not profile then
		return unlocked
	end
	local data = profile.Data
	local level = LevelCurve.FromTotalXP(data.XP)
	local unlockedNames = {}
	for _, item in Cosmetics.List do
		if data.Owned[item.Id] then
			continue
		end
		local qualifies = item.Default == true
			or (item.UnlockLevel ~= nil and level >= item.UnlockLevel)
			or (item.UnlockStat ~= nil and (data.Stats[item.UnlockStat.Stat] or 0) >= item.UnlockStat.Value)
			or (item.Vip == true and profile.IsVip)
		if qualifies then
			data.Owned[item.Id] = true
			if not item.Default then
				table.insert(unlocked, item)
				table.insert(unlockedNames, `{item.Icon} {item.Name}`)
			end
		end
	end
	if #unlockedNames > 0 and not silent then
		Notifier.Send(player, `Unlocked: {table.concat(unlockedNames, ", ")}! Equip it in the Shop.`, "reward", 6)
	end
	DataService.Changed(player)
	return unlocked
end

local function effectFor(player: Player, slot: string, fallback: string): (string, { Color3 }?)
	local item = equippedItem(player, slot)
	return (item and item.Effect) or fallback, item and item.Colors
end

function CosmeticService.PlayVictory(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local effect, colors = effectFor(player, "Victory", "Confetti")
		Notifier.Effect(effect, root.Position + Vector3.new(0, 3, 0), colors)
	end
end

function CosmeticService.PlayElimination(player: Player, position: Vector3)
	local effect, colors = effectFor(player, "Elimination", "Poof")
	Notifier.Effect(effect, position, colors)
end

local function checkVip(player: Player)
	local passId = Config.Monetization.VipGamePassId
	if passId == 0 then
		return
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
	local profile = DataService.Get(player)
	if ok and owns and profile then
		profile.IsVip = true
		CosmeticService.CheckUnlocks(player, true)
		CosmeticService.Refresh(player)
	end
end

function CosmeticService.Init()
	DataService.ProfileLoaded:Connect(function(player: Player, profile)
		local unlocked = CosmeticService.CheckUnlocks(player, true)
		CosmeticService.Refresh(player)
		task.spawn(checkVip, player)
		-- A returning player whose level or career already earned rewards that are new to the game
		-- (the Rewards Road's first day, or new items added later): tell them where to find them.
		if #unlocked > 0 and profile and profile.Data.Meta.Sessions > 1 then
			local count = #unlocked
			task.delay(10, function()
				if player.Parent then
					Notifier.Send(
						player,
						`You've unlocked {count} new reward{if count == 1 then "" else "s"}! Tap your level to see the Rewards Road.`,
						"reward",
						8
					)
				end
			end)
		end
	end)

	local function track(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == Config.Monetization.VipGamePassId and passId ~= 0 then
			local profile = DataService.Get(player)
			if profile then
				profile.IsVip = true
				CosmeticService.CheckUnlocks(player)
				CosmeticService.Refresh(player)
				Notifier.Send(player, "Thanks for supporting Party Panic! VIP cosmetics unlocked.", "reward", 6)
			end
		end
	end)

	local vipLimiter = RateLimiter.new(2, 5)
	Remotes.Get("PromptVip").OnServerEvent:Connect(function(player)
		local passId = Config.Monetization.VipGamePassId
		if passId ~= 0 and vipLimiter:Check(player) then
			MarketplaceService:PromptGamePassPurchase(player, passId)
		end
	end)
end

return CosmeticService

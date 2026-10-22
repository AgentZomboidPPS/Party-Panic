-- Applies equipped cosmetics to characters and grants unlocks.
-- Cosmetics are purely visual (design doc §10 "Economy guardrails").
-- Name tags show the level in its prestige color, which changes every 10 levels, so long-time
-- players stand out in the lobby (owner: "Also we need cool payoffs for players that keep playing
-- the game."; colors in Shared/Progression). A returning player whose level or career already
-- earned rewards new to the game gets them in a "NEW REWARDS!" celebration when they join.
-- Hats (owner: "do pumpkin hat now"): the equipped hat (World/Hats) is worn in the lobby, on every
-- new character too. It comes off for the rounds its wearer plays (PP_InRound, like the PARTY CUP
-- crown) and steps aside while the crown is on (the crown wins), and goes back on after either.
-- The GOLD PASS (owner: "Also we do need a paid battle pass too. I like the current free one. But the
-- paid one should also be insane."; it replaced the old VIP pass, Services/GoldPassService buys and
-- checks it):
--   * An owner's gold rewards unlock with their level like the road's (CheckUnlocks: GoldLevel).
--   * An owner's name tag wears a GOLD badge over the name, and the name shimmers in gold; a gold
--     title shimmers in its own colours (Shared/NameTag builds the tag; each device moves the glint).
--   * A gold trail can have a Style (Shared/GoldPass): a texture, more glow, a wider ribbon that
--     tapers, a longer tail, glitter shed behind it (PP_GoldGlitter: off on a device with reduced
--     effects) and a soft light.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local LevelCurve = require(Shared.Logic.LevelCurve)
local NameTag = require(Shared.NameTag)
local Remotes = require(Shared.Remotes)

local CupCrown = require(script.Parent.Parent.World.CupCrown)
local Hats = require(script.Parent.Parent.World.Hats)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)

local CosmeticService = {}

local NAMEPLATE = NameTag.Name
local TRAIL = "PP_Trail"
local GLITTER = "PP_TrailGlitter"
local GLOW = "PP_TrailLight"
local GLITTER_TAG = "PP_GoldGlitter" -- emitters a device with reduced effects switches off
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

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
	local gold = profile ~= nil and (profile.Data :: any).GoldPass.Owned == true
	NameTag.Build(player.DisplayName, level, gold, equippedItem(player, "Title")).Parent = head
end

local function applyTrail(player: Player, character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	for _, name in { TRAIL, GLITTER, GLOW, "PP_TrailTop", "PP_TrailBottom" } do
		local attachment = root:FindFirstChild(name)
		if attachment then
			attachment:Destroy()
		end
	end

	local item = equippedItem(player, "Trail")
	if not item or not item.Colors then
		return
	end

	-- A gold trail's Style (Shared/GoldPass): wider, longer, brighter, textured, with glitter and light.
	local style = item.Style or {}
	local half = 0.9 * (style.Width or 1)
	local top = Instance.new("Attachment")
	top.Name = "PP_TrailTop"
	top.Position = Vector3.new(0, half, 0.4)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "PP_TrailBottom"
	bottom.Position = Vector3.new(0, -half, 0.4)
	bottom.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = TRAIL
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = Cosmetics.ColorSequence(item.Colors)
	trail.Transparency = NumberSequence.new(if style.Texture then 0.05 else 0.15, 1)
	trail.Lifetime = style.Lifetime or 0.45
	trail.MinLength = 0.2
	trail.LightEmission = style.Emission or 0.4
	trail.FaceCamera = true
	if style.Texture then
		trail.Texture = style.Texture
		trail.TextureMode = Enum.TextureMode.Wrap
		trail.TextureLength = style.TextureLength or 2
		trail.WidthScale = NumberSequence.new(1, 0.35) -- the tail tapers
	end
	trail.Parent = root

	if style.Glitter then
		local glitter = Instance.new("ParticleEmitter")
		glitter.Name = GLITTER
		glitter.Texture = SPARKLE
		glitter.Color = ColorSequence.new(style.Glitter)
		glitter.LightEmission = 1
		glitter.Size = NumberSequence.new(0.45, 0)
		glitter.Transparency = NumberSequence.new(0.1, 1)
		glitter.Lifetime = NumberRange.new(0.6, 1.1)
		glitter.Rate = 9
		glitter.Speed = NumberRange.new(0.5, 2)
		glitter.SpreadAngle = Vector2.new(180, 180)
		glitter.Acceleration = Vector3.new(0, -3, 0)
		glitter.Drag = 2
		glitter.Rotation = NumberRange.new(0, 360)
		glitter.RotSpeed = NumberRange.new(-180, 180)
		glitter.Parent = root
		CollectionService:AddTag(glitter, GLITTER_TAG)
	end
	if style.Light then
		local light = Instance.new("PointLight")
		light.Name = GLOW
		light.Color = style.Light
		light.Range = 9
		light.Brightness = 0.9
		light.Shadows = false
		light.Parent = root
	end
end

-- The hat this character should wear now: the equipped one, in the lobby (not in a round its wearer
-- plays) and not while the PARTY CUP crown is on.
local function hatWanted(player: Player, character: Model): Cosmetics.Cosmetic?
	local item = equippedItem(player, "Hat")
	if
		item
		and Hats.Has(item.Id)
		and player.Parent
		and player.Character == character
		and player:GetAttribute("PP_InRound") ~= true
		and not character:FindFirstChild(CupCrown.Name)
	then
		return item
	end
	return nil
end

local hatLoading: { [Model]: boolean } = {} -- characters whose hat is being made (its mesh loads once)

-- Puts the wanted hat on (or takes it off). Making one can wait for its mesh the first time, so
-- once it's on, it looks again: a round or the crown may have come meanwhile.
local function applyHat(player: Player, character: Model?)
	if not character or hatLoading[character] then
		return
	end
	local item = hatWanted(player, character)
	local id = if item then item.Id else nil
	if Hats.Worn(character) == id then
		return
	elseif not id then
		Hats.Remove(character)
		return
	end
	hatLoading[character] = true
	task.spawn(function()
		local ok, result = pcall(Hats.Attach, character, id :: string)
		hatLoading[character] = nil
		if not ok then
			warn(`[CosmeticService] {player.Name}'s hat: {result}`)
		elseif result then
			applyHat(player, character)
		end
	end)
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
	applyHat(player, character)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	character:WaitForChild("HumanoidRootPart", 10)
	character:WaitForChild("Head", 10)
	if player.Parent and player.Character == character then
		-- The crown going on or off (CupService) moves the hat aside or back.
		for _, signal in { character.ChildAdded, character.ChildRemoved } do
			signal:Connect(function(child)
				if child.Name == CupCrown.Name then
					applyHat(player, character)
				end
			end)
		end
		CosmeticService.Refresh(player)
	end
end

-- Grants default, level, stat and GOLD PASS cosmetics the player qualifies for, once each (owning
-- an item is the record). Returns the ones it just unlocked (not the defaults); `silent` leaves the
-- telling to the caller (ProgressionService celebrates level and milestone unlocks, GoldPassService
-- the pass's).
function CosmeticService.CheckUnlocks(player: Player, silent: boolean?): { Cosmetics.Cosmetic }
	local unlocked: { Cosmetics.Cosmetic } = {}
	local profile = DataService.Get(player)
	if not profile then
		return unlocked
	end
	local data = profile.Data
	local level = LevelCurve.FromTotalXP(data.XP)
	local gold = (data :: any).GoldPass.Owned == true
	local unlockedNames = {}
	for _, item in Cosmetics.List do
		if data.Owned[item.Id] then
			continue
		end
		local qualifies = item.Default == true
			or (item.UnlockLevel ~= nil and level >= item.UnlockLevel)
			or (item.UnlockStat ~= nil and (data.Stats[item.UnlockStat.Stat] or 0) >= item.UnlockStat.Value)
			or (item.GoldLevel ~= nil and gold and level >= item.GoldLevel)
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

function CosmeticService.Init()
	DataService.ProfileLoaded:Connect(function(player: Player, profile)
		local unlocked = CosmeticService.CheckUnlocks(player, true)
		CosmeticService.Refresh(player)
		-- A returning player whose level or career already earned rewards that are new to the game
		-- (the Rewards Road's first day, or new items added later) gets them in a celebration of
		-- their own (CelebrationController shows it once they're in the lobby).
		if #unlocked > 0 and profile and profile.Data.Meta.Sessions > 1 then
			local ids = {}
			for _, item in unlocked do
				table.insert(ids, item.Id)
			end
			Remotes.Get("Celebrate"):FireClient(player, { Kind = "Welcome", Coins = 0, Items = ids })
		end
	end)

	local function track(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		-- Off for the rounds they play, back on in the lobby.
		player:GetAttributeChangedSignal("PP_InRound"):Connect(function()
			applyHat(player, player.Character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
end

return CosmeticService

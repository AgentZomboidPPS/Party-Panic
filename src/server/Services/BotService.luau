-- Bots: friendly AI players that fill empty spots so every round feels full (owner: "we need bots
-- in the mini games. we can have the bots fade in/out if a player joins or leaves").
--
-- While anyone is here, the server keeps Config.Bots.FillTo participants: when a player joins, a
-- bot fades out to make room (right away from the lobby, or after its round if it's playing one);
-- when a player leaves, a bot fades in. Someone sitting out (SitOutService) leaves their spot to
-- a bot the same way. Bots are clearly labelled (🤖 name and a BOT tag), never earn rewards and
-- never save data.
--
-- A bot is a table that looks like a Player to the round code (Name, DisplayName, UserId < 0,
-- Character, Parent, attributes, CharacterAdded, LoadCharacterAsync), so RoundContext and every
-- mode treat it like anyone else. Its attributes live on a Configuration in
-- ReplicatedStorage.PartyBots, so clients can list bots next to players. In a round the mode's
-- brain (MiniGames/Bots/<Id>.luau) drives it with the helpers below; in the lobby it wanders. Bots
-- never vote: only people pick the next game (owner: "remove the option for bots voting on the next
-- game mode").
--
-- Movement goes through the Humanoid. Where physics isn't running (the Open Cloud test servers),
-- bots walk and jump by moving their rig directly, so the same brains can be tested there.
--
-- Slaparazzi pass (owner: "Bots are terrible at slaparazzi"): on those test servers a bot stood on
-- whatever was under it, other characters too, even in a mode where characters pass through each
-- other (Slaparazzi's PP_SlapCast). A crowd of bots on one spot became a tower, which a real game
-- never shows. Now a character a bot can't touch is no floor for it either.
--
-- Bots and people pass through each other, in every mode and the lobby (owner: "Bots are STILL
-- ruberbanding and floating." "This has got to be fixed. You said last time you did but clearly you
-- didnt fix it."). The server moves a bot and each person's own device moves them, so when the two
-- touch, each side works out the bump on its own with the other where it last heard it was: on the
-- server the person's body is an unstoppable wall that shoves the bot aside or lifts it onto their
-- head, on their screen the bot is a wall that stops them, and everyone sees the bot jerk, snap
-- back as it walks back to where it was going, or ride a head in mid-air. Hex Meltdown, Shark Bait
-- and Slaparazzi each split them this way after "Bot is floating." reports; now every bot's body is
-- in PP_Bots, which touches everything Default does except people (the lobby's PP_Players, World/
-- BeachBalls.luau). Bots still bump into each other (the server moves both, so they agree), and a
-- mode that puts characters in its own groups still does. Hits, stomps and tags never needed bodies
-- to touch: they go by position. The rebalance loop keeps PP_Bots in step with Default as modes add
-- their own groups.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)

local BotRegistry = require(script.Parent.BotRegistry)
local Notifier = require(script.Parent.Notifier)
local SitOutService = require(script.Parent.SitOutService)

local BotService = {}

local NAMES = {
	"Pip",
	"Mochi",
	"Bloop",
	"Sprocket",
	"Noodle",
	"Ziggy",
	"Pickle",
	"Bonbon",
	"Taffy",
	"Waffles",
	"Gizmo",
	"Nugget",
	"Bubbles",
	"Tofu",
	"Pebble",
	"Sunny",
	"Jelly",
	"Biscuit",
	"Comet",
	"Doodle",
	"Fizz",
	"Momo",
	"Peanut",
	"Rolo",
}

local SKIN = {
	Color3.fromRGB(245, 205, 48), -- classic
	Color3.fromRGB(255, 204, 170),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(199, 148, 108),
	Color3.fromRGB(150, 103, 73),
	Color3.fromRGB(99, 67, 48),
}
local OUTFIT = {
	Color3.fromRGB(255, 92, 170),
	Color3.fromRGB(80, 205, 255),
	Color3.fromRGB(110, 230, 140),
	Color3.fromRGB(255, 150, 60),
	Color3.fromRGB(170, 120, 255),
	Color3.fromRGB(255, 212, 70),
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(60, 200, 190),
}

-- Roblox's standard R15 animations (the same ones player characters use).
local ANIMATIONS = {
	idle = "rbxassetid://507766666",
	walk = "rbxassetid://507777826",
	run = "rbxassetid://507767714",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
}

local JUMP_TIME = 0.75 -- simulated jump (no physics): time in the air
local JUMP_HEIGHT = 7

-- Bots' bodies: they touch everything Default does except people's (see the header).
local BOT_GROUP, PEOPLE_GROUP = "PP_Bots", "PP_Players"

local rng = Random.new()
local folder: Folder
local nextId = 0
local usedNames: { [string]: boolean } = {}
local physics = false
local grouped = false -- PP_Bots is set up (if it couldn't be, bots stay in Default and touch people)

local Bot = {}
Bot.__index = Bot

export type Bot = typeof(setmetatable(
	{} :: {
		IsBot: boolean,
		Name: string,
		DisplayName: string,
		UserId: number,
		Skill: number,
		Memory: { [any]: any },
		Rng: Random,
		Character: Model?,
		Parent: Instance?,
		Info: Configuration,
		CharacterAdded: any,
		CharacterRemoving: any,
		Description: HumanoidDescription,
		Goal: Vector3?,
		Leaving: boolean,
		JumpStart: number?,
		JumpBase: number?,
		Lobby: { [string]: any },
	},
	Bot
))

-- Player-like surface ------------------------------------------------------------------------------

function Bot.SetAttribute(self: Bot, name: string, value: any)
	self.Info:SetAttribute(name, value)
end

function Bot.GetAttribute(self: Bot, name: string): any
	return self.Info:GetAttribute(name)
end

function Bot.GetAttributeChangedSignal(self: Bot, name: string): RBXScriptSignal
	return self.Info:GetAttributeChangedSignal(name)
end

function Bot.GetNetworkPing(_self: Bot): number
	return 0
end

function Bot.IsA(_self: Bot, className: string): boolean
	return className == "Bot"
end

function Bot.FindFirstChild(_self: Bot, _name: string): Instance?
	return nil
end

-- Back to the lobby with a fresh character (RoundContext calls this after a round, like it does
-- for players).
function Bot.LoadCharacterAsync(self: Bot)
	BotService.SpawnCharacter(self, false)
end

function Bot.Kick(self: Bot)
	BotService.Remove(self)
end

-- Helpers for brains -------------------------------------------------------------------------------

function Bot.Humanoid(self: Bot): Humanoid?
	local character = self.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

function Bot.Root(self: Bot): BasePart?
	local character = self.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Walks toward a point (call it again each step to keep going; brains usually do).
function Bot.MoveTo(self: Bot, position: Vector3)
	self.Goal = position
	local humanoid = self:Humanoid()
	if humanoid and physics then
		humanoid:MoveTo(position)
	end
end

function Bot.Stop(self: Bot)
	self.Goal = nil
	local humanoid, root = self:Humanoid(), self:Root()
	if humanoid and root and physics then
		humanoid:MoveTo(root.Position)
	end
end

function Bot.Jump(self: Bot)
	local humanoid, root = self:Humanoid(), self:Root()
	if not humanoid or not root or humanoid.JumpPower <= 0 and humanoid.JumpHeight <= 0 then
		return
	end
	if physics then
		humanoid.Jump = true
	elseif not self.JumpStart then
		self.JumpStart = os.clock()
		self.JumpBase = root.Position.Y
	end
end

-- How long this bot takes to react, in seconds: quicker for skilled bots, never exactly the same.
function Bot.Reaction(self: Bot): number
	return (0.85 - self.Skill * 0.6) * self.Rng:NextNumber(0.75, 1.35)
end

function Bot.Chance(self: Bot, probability: number): boolean
	return self.Rng:NextNumber() < probability
end

-- Characters ---------------------------------------------------------------------------------------

local function lobbySpawn(): CFrame
	local points = {}
	local lobby = workspace:FindFirstChild("Lobby")
	local spawns = lobby and lobby:FindFirstChild("Spawns", true)
	if spawns then
		for _, spawn in spawns:GetChildren() do
			if spawn:IsA("SpawnLocation") then
				table.insert(points, spawn.CFrame)
			end
		end
	end
	if #points == 0 then
		return CFrame.new(rng:NextNumber(-12, 12), Config.LobbySpawnHeight, rng:NextNumber(10, 22))
	end
	return points[rng:NextInteger(1, #points)] * CFrame.new(rng:NextNumber(-1.5, 1.5), 3, rng:NextNumber(-1.5, 1.5))
end

local function weldTo(part: BasePart, to: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = part
	weld.Parent = part
end

-- A little antenna with a glowing tip, and a nameplate saying who it is: never mistaken for a person.
local function decorate(bot: Bot, model: Model, color: Color3)
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local top = head.CFrame * CFrame.new(0, head.Size.Y / 2, 0)
	local stalk = Instance.new("Part")
	stalk.Name = "BotAntenna"
	stalk.Shape = Enum.PartType.Cylinder
	stalk.Size = Vector3.new(1.1, 0.16, 0.16)
	stalk.CFrame = top * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90))
	stalk.Color = Color3.fromRGB(70, 70, 90)
	stalk.Material = Enum.Material.Metal
	local bulb = Instance.new("Part")
	bulb.Name = "BotAntennaTip"
	bulb.Shape = Enum.PartType.Ball
	bulb.Size = Vector3.one * 0.5
	bulb.CFrame = top * CFrame.new(0, 1.15, 0)
	bulb.Color = color
	bulb.Material = Enum.Material.Neon
	for _, part in { stalk, bulb } do
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		weldTo(part, head)
		part.Parent = model
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "PP_Nameplate"
	gui.Size = UDim2.fromOffset(220, 54)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0.55, 0)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.4
	name.Text = bot.DisplayName
	name.Parent = gui
	local tag = Instance.new("TextLabel")
	tag.BackgroundTransparency = 1
	tag.Position = UDim2.fromScale(0, 0.55)
	tag.Size = UDim2.new(1, 0, 0.42, 0)
	tag.Font = Enum.Font.GothamBold
	tag.TextScaled = true
	tag.TextStrokeTransparency = 0.5
	tag.TextColor3 = color
	tag.Text = "BOT"
	tag.Parent = gui
	gui.Parent = head
end

-- Plays Roblox's walk/run/jump/fall animations on the server (they replicate to everyone).
local function animate(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local tracks = {}
	for name, id in ANIMATIONS do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(animator.LoadAnimation, animator, animation)
		if ok then
			tracks[name] = track
		end
	end
	local current: string? = nil
	local function play(name: string, fade: number?)
		if current == name or not tracks[name] then
			return
		end
		if current and tracks[current] then
			tracks[current]:Stop(fade or 0.2)
		end
		current = name
		tracks[name]:Play(fade or 0.2)
	end
	humanoid.Running:Connect(function(speed)
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
			return
		end
		if speed > 12 then
			play("run")
		elseif speed > 0.5 then
			play("walk")
		else
			play("idle")
		end
	end)
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			play("jump", 0.1)
		elseif new == Enum.HumanoidStateType.Freefall then
			play("fall", 0.3)
		elseif new == Enum.HumanoidStateType.Landed then
			play("idle", 0.15)
		end
	end)
	play("idle")
end

-- Fades every visible piece of a character in (to how it was made) or out (to invisible).
local function fade(model: Model, visible: boolean, time: number)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			local item = descendant :: any
			if item.Name == "HumanoidRootPart" then
				continue
			end
			local base = item:GetAttribute("PP_BaseTransparency")
			if base == nil then
				base = item.Transparency
				item:SetAttribute("PP_BaseTransparency", base)
			end
			if visible then
				item.Transparency = 1
			end
			TweenService:Create(item, TweenInfo.new(time, Enum.EasingStyle.Quad), {
				Transparency = if visible then base else 1,
			}):Play()
		elseif descendant:IsA("BillboardGui") then
			(descendant :: BillboardGui).Enabled = visible
		end
	end
end

-- PP_Bots never touches people, nor any group Default doesn't touch (a mode may add groups later:
-- the rebalance loop calls this again). (Only ever turned off: a group that keeps itself to Default
-- alone, like MeshLibrary's camera-only scenery, turns PP_Bots off itself.)
local function syncGroups()
	for _, group in PhysicsService:GetRegisteredCollisionGroups() do
		local name = group.name
		if name == BOT_GROUP or name == PEOPLE_GROUP then
			continue
		end
		if
			not PhysicsService:CollisionGroupsAreCollidable("Default", name)
			and PhysicsService:CollisionGroupsAreCollidable(BOT_GROUP, name)
		then
			PhysicsService:CollisionGroupSetCollidable(BOT_GROUP, name, false)
		end
	end
	if PhysicsService:CollisionGroupsAreCollidable(BOT_GROUP, PEOPLE_GROUP) then
		PhysicsService:CollisionGroupSetCollidable(BOT_GROUP, PEOPLE_GROUP, false)
	end
end

local function setupGroups()
	grouped = pcall(function()
		for _, name in { BOT_GROUP, PEOPLE_GROUP } do
			if not PhysicsService:IsCollisionGroupRegistered(name) then
				PhysicsService:RegisterCollisionGroup(name)
			end
		end
		syncGroups()
	end)
	if not grouped then
		warn("[BotService] couldn't set up PP_Bots: bots and people will bump into each other")
	end
end

-- Puts a bot's body in PP_Bots, parts it gets later too (unless a mode already put one in a group of
-- its own).
local function groupBody(character: Model)
	if not grouped then
		return
	end
	for _, item in character:GetDescendants() do
		if item:IsA("BasePart") then
			item.CollisionGroup = BOT_GROUP
		end
	end
	character.DescendantAdded:Connect(function(item)
		if item:IsA("BasePart") and item.CollisionGroup == "Default" then
			item.CollisionGroup = BOT_GROUP
		end
	end)
end

function BotService.SpawnCharacter(bot: Bot, fadeIn: boolean)
	if not bot.Parent then
		return
	end
	local ok, model =
		pcall(Players.CreateHumanoidModelFromDescription, Players, bot.Description, Enum.HumanoidRigType.R15)
	if not ok or not model then
		warn(`[BotService] couldn't build {bot.Name}: {model}`)
		return
	end
	local character = model :: Model
	character.Name = bot.Name
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.DisplayName = bot.DisplayName
	decorate(bot, character, bot.Info:GetAttribute("Color") :: Color3)
	groupBody(character)
	character:PivotTo(lobbySpawn())

	local old = bot.Character
	if old then
		bot.CharacterRemoving:Fire(old)
		BotRegistry.SetCharacter(bot, nil, old)
		old:Destroy()
	end
	bot.Goal = nil
	bot.JumpStart = nil
	bot.Lobby = {}
	character.Parent = workspace
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		pcall(root.SetNetworkOwner, root, nil) -- the server moves bots; no handing them to a player
	end
	animate(character)
	bot.Character = character
	BotRegistry.SetCharacter(bot, character)
	local pointer = bot.Info:FindFirstChild("Character") :: ObjectValue
	pointer.Value = character
	bot.CharacterAdded:Fire(character)
	if fadeIn then
		fade(character, true, 0.7)
		if root then
			Notifier.Effect("Sparkles", root.Position, { bot.Info:GetAttribute("Color") :: Color3 })
		end
	end

	-- Like players, a bot that dies in the lobby comes back a moment later.
	humanoid.Died:Connect(function()
		task.delay(3, function()
			if bot.Parent and bot.Character == character and not bot:GetAttribute("PP_InRound") then
				BotService.SpawnCharacter(bot, false)
			end
		end)
	end)
end

local function pickName(): string
	local free = {}
	for _, name in NAMES do
		if not usedNames[name] then
			table.insert(free, name)
		end
	end
	local name = if #free > 0 then free[rng:NextInteger(1, #free)] else `Bot{nextId + 1}`
	usedNames[name] = true
	return name
end

-- Creates a bot and fades it into the lobby.
function BotService.Add(): Bot
	nextId += 1
	local name = pickName()
	local self = setmetatable({}, Bot) :: any
	self.IsBot = true
	self.ShortName = name
	self.Name = "Bot_" .. name
	self.DisplayName = "🤖 " .. name
	self.UserId = -nextId
	self.Skill = rng:NextNumber(0.35, 0.9)
	self.Memory = {}
	self.Lobby = {}
	self.Rng = Random.new()
	self.Leaving = false
	self.CharacterAdded = Signal.new()
	self.CharacterRemoving = Signal.new()
	local color = OUTFIT[rng:NextInteger(1, #OUTFIT)]
	local info = Instance.new("Configuration")
	info.Name = self.Name
	info:SetAttribute("DisplayName", self.DisplayName)
	info:SetAttribute("UserId", self.UserId)
	info:SetAttribute("IsBot", true)
	info:SetAttribute("Color", color)
	local pointer = Instance.new("ObjectValue")
	pointer.Name = "Character"
	pointer.Parent = info
	info.Parent = folder
	self.Info = info
	self.Parent = info -- set while the bot is here, like Player.Parent

	local description = Instance.new("HumanoidDescription")
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.TorsoColor = color
	local pants = OUTFIT[rng:NextInteger(1, #OUTFIT)]:Lerp(Color3.fromRGB(40, 40, 60), 0.55)
	description.LeftLegColor = pants
	description.RightLegColor = pants
	self.Description = description

	BotRegistry.Add(self)
	BotService.SpawnCharacter(self, true)
	return self
end

-- Fades a bot out and removes it.
function BotService.Remove(bot: Bot)
	if not bot.Parent then
		return
	end
	local character = bot.Character
	local root = bot:Root()
	if root then
		Notifier.Effect("Poof", root.Position)
	end
	bot.Parent = nil
	BotRegistry.Remove(bot)
	usedNames[bot.ShortName] = nil
	if character then
		fade(character, false, 0.6)
		task.delay(0.65, function()
			BotRegistry.SetCharacter(bot, nil, character)
			character:Destroy()
		end)
	end
	task.delay(0.7, function()
		bot.Info:Destroy()
	end)
end

-- Population -----------------------------------------------------------------------------------------

local function enabled(): boolean
	local settings = Config.Bots
	return settings.Enabled and (settings.InStudio or not RunService:IsStudio())
end

function BotService.Desired(): number
	local players = Players:GetPlayers()
	if not enabled() or #players == 0 then
		return 0
	end
	-- People sitting out leave their spot to a bot. While everyone's on a break there's no round
	-- to fill, so the lobby keeps its usual crowd.
	local playing = 0
	for _, player in players do
		if not SitOutService.IsSittingOut(player) then
			playing += 1
		end
	end
	local people = if playing > 0 then playing else #players
	return math.clamp(Config.Bots.FillTo - people, 0, Config.Bots.MaxBots)
end

local lastArrival = 0
-- One step towards the desired number of bots: a bot fades in, or one leaves (from the lobby, or
-- after its round).
function BotService.Rebalance()
	local bots = BotRegistry.List()
	local desired = BotService.Desired()
	if #bots < desired and os.clock() - lastArrival >= Config.Bots.ArriveEvery then
		lastArrival = os.clock()
		BotService.Add()
	elseif #bots > desired then
		for _, bot in bots do
			if not bot:GetAttribute("PP_InRound") then
				BotService.Remove(bot)
				return
			end
		end
	end
end

-- Lobby life ---------------------------------------------------------------------------------------

local WANDER_RADIUS = 52

function BotService.LobbyStep(bot: Bot, now: number)
	local root = bot:Root()
	local humanoid = bot:Humanoid()
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local memory = bot.Lobby

	-- Wander the plaza: stroll somewhere, look around for a bit, sometimes hop.
	if not memory.Goal or now > (memory.GoalUntil or 0) then
		local angle = bot.Rng:NextNumber(0, math.pi * 2)
		local distance = bot.Rng:NextNumber(14, WANDER_RADIUS)
		memory.Goal = Vector3.new(math.cos(angle) * distance, root.Position.Y, math.sin(angle) * distance)
		memory.GoalUntil = now + bot.Rng:NextNumber(5, 11)
		memory.Pause = bot:Chance(0.35)
	end
	local goal = memory.Goal :: Vector3
	local flat = Vector3.new(goal.X - root.Position.X, 0, goal.Z - root.Position.Z)
	if memory.Pause or flat.Magnitude < 3 then
		bot:Stop()
	else
		bot:MoveTo(goal)
	end
	if bot:Chance(0.01) then
		bot:Jump()
	end
end

-- Without physics, walk, jump and fall by moving the rig directly: a jump is a fixed arc, and
-- outside a jump the rig settles onto whatever is under it or falls if there's nothing (so a bot
-- that misses a hop drops like a player would, and never drifts upward jump after jump).
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true -- stand only on what a player could stand on

-- A bot's own character and every character it passes through (their collision groups don't
-- collide, as in a mode that turns bumping into each other off): none of them is floor for it.
local function notFloor(character: Model, root: BasePart): { Instance }
	local list: { Instance } = { character }
	local function consider(other: Model?)
		local otherRoot = if other and other ~= character then other:FindFirstChild("HumanoidRootPart") else nil
		if not other or not otherRoot or not otherRoot:IsA("BasePart") then
			return
		end
		local ok, collides = pcall(
			PhysicsService.CollisionGroupsAreCollidable,
			PhysicsService,
			root.CollisionGroup,
			otherRoot.CollisionGroup
		)
		if ok and not collides then
			table.insert(list, other)
		end
	end
	for _, other in BotRegistry.List() do
		consider(other.Character)
	end
	for _, player in Players:GetPlayers() do
		consider(player.Character)
	end
	return list
end

local function simulate(dt: number)
	local now = os.clock()
	for _, bot in BotRegistry.List() do
		local root, humanoid = bot:Root(), bot:Humanoid()
		local character = bot.Character
		if not root or not humanoid or not character or root.Anchored then
			continue -- anchored: the mode is moving it itself
		end
		local position = root.Position
		local goal = bot.Goal
		local step = Vector3.zero
		if goal and humanoid.WalkSpeed > 0 then
			local flat = Vector3.new(goal.X - position.X, 0, goal.Z - position.Z)
			if flat.Magnitude > 0.5 then
				step = flat.Unit * math.min(flat.Magnitude, humanoid.WalkSpeed * dt)
			end
		end
		local y = position.Y
		local jumping = false
		if bot.JumpStart then
			local t = (now - bot.JumpStart) / JUMP_TIME
			if t >= 1 then
				bot.JumpStart = nil
			else
				jumping = true
				y = (bot.JumpBase or position.Y) + 4 * JUMP_HEIGHT * t * (1 - t)
			end
		end
		if not jumping then
			bot.JumpBase = nil
			groundParams.FilterDescendantsInstances = notFloor(character, root)
			local hit = workspace:Raycast(position + step, Vector3.new(0, -400, 0), groundParams)
			local rest = if hit then hit.Position.Y + humanoid.HipHeight + root.Size.Y / 2 else -math.huge
			if y > rest + 0.05 then
				bot.FallSpeed = (bot.FallSpeed or 0) + workspace.Gravity * dt
				y = math.max(rest, y - bot.FallSpeed * dt)
			else
				bot.FallSpeed = 0
				y = math.max(y, rest)
			end
		end
		if step.Magnitude > 0 or math.abs(y - position.Y) > 1e-3 then
			local target = Vector3.new(position.X + step.X, y, position.Z + step.Z)
			local look = if step.Magnitude > 0.01 then target + step else target + root.CFrame.LookVector
			character:PivotTo(CFrame.lookAt(target, Vector3.new(look.X, target.Y, look.Z)))
		end
	end
end

-- Bots stay the server's (owner: "Bots are still rubber banding on spleef"). A part that is anchored
-- for a moment (a mode's scripted fall, a put-back) goes back to automatic network ownership when it's
-- unanchored, and the engine then hands the bot to the nearest player's device: everyone else sees it
-- snap back and forth as it hops between players' devices, and the server's own pushes on it (velocity
-- limits, knockback) fight that device. Checked with the rebalance loop, a few times a second.
local function keepServerOwned(bot: Bot)
	local root = bot:Root()
	if not physics or not root or root.Anchored or not root:IsDescendantOf(workspace) then
		return
	end
	local okAuto, auto = pcall(root.GetNetworkOwnershipAuto, root)
	local okOwner, owner = pcall(root.GetNetworkOwner, root)
	if (okAuto and auto) or (okOwner and owner ~= nil) then
		pcall(root.SetNetworkOwner, root, nil)
	end
end

function BotService.Init()
	BotService.Setup()

	Players.PlayerAdded:Connect(BotService.Rebalance)
	Players.PlayerRemoving:Connect(function()
		task.defer(BotService.Rebalance)
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(BotService.Rebalance)
			if not ok then
				warn("[BotService] rebalance failed:", err)
			end
			if grouped then
				pcall(syncGroups)
			end
			local now = os.clock()
			for _, bot in BotRegistry.List() do
				pcall(keepServerOwned, bot)
				if not bot:GetAttribute("PP_InRound") then
					local okStep, stepErr = pcall(BotService.LobbyStep, bot, now)
					if not okStep then
						warn("[BotService] lobby step failed:", stepErr)
					end
				end
			end
			task.wait(0.4)
		end
	end)
end

-- For tools and tests: bots without the lobby (a harness makes them, a round uses them).
function BotService.Setup()
	if not folder then
		local created = Instance.new("Folder")
		created.Name = "PartyBots"
		created.Parent = ReplicatedStorage
		folder = created
		physics = RunService:IsRunning()
		setupGroups()
		if not physics then
			RunService.Heartbeat:Connect(simulate)
		end
	end
end

return BotService

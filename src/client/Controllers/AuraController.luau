-- The crate seasons' auras (a new cosmetic slot: an effect that's always on around you in the lobby;
-- owner: "next tier can be seasonal effects ... 3 of each", then "This has to be sick. This will be
-- players first season. I want it to look insane."). HOLLOW NIGHT's three:
--   * LEAF WHIRL: autumn leaves spiral up round you (two leaf streams circling you, each leaving its
--     leaves where they were, so they make a spiral as you move);
--   * FIREFLY SWARM: fireflies drift round you and blink;
--   * LANTERN RING: three small paper lanterns float round you at waist height, glowing warm.
-- Kept low and soft, so a plaza full of them never turns into noise. Drawn by every device for
-- every player from the server's word (PP_Aura); lobby only: it goes while its wearer plays a round
-- (PP_InRound) and comes back after. Beyond 100 studs it rests; with reduced effects there are fewer
-- leaves and fireflies and the lanterns give no light.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)

local SeasonParts = require(script.Parent.Parent.SeasonParts)
local State = require(script.Parent.Parent.State)

local AuraController = {}

local RANGE = 100 -- studs from the camera: beyond it, an aura rests
local LANTERN_RADIUS = 2.6
local LANTERN_HEIGHT = -0.4 -- from the root: waist height
local WHIRL_RADIUS = 2.2

type Aura = {
	Owner: Player,
	Id: string,
	Kind: string,
	Root: BasePart,
	Attachments: { Attachment },
	Emitters: { ParticleEmitter },
	Lanterns: { BasePart },
	LanternOffsets: { { CFrame } },
	LanternModels: { Model },
	Lights: { PointLight },
	Clock: number,
	Active: boolean,
}

local folder: Folder
local auras: { [Player]: Aura } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function colorsOf(id: string): { Color3 }
	local item = Cosmetics.Get(id)
	return (item and item.Colors) or { Color3.fromRGB(255, 138, 42), Color3.fromRGB(255, 208, 74) }
end

local function newEmitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = parent
	return emitter
end

local function destroy(player: Player)
	local aura = auras[player]
	if not aura then
		return
	end
	auras[player] = nil
	for _, attachment in aura.Attachments do
		attachment:Destroy()
	end
	for _, model in aura.LanternModels do
		model:Destroy()
	end
end

-- Builds `player`'s aura `id` on their character's root (nil without a root, or an aura it doesn't know).
local function build(player: Player, id: string, root: BasePart): Aura?
	local item = Cosmetics.Get(id)
	local kind = item and item.Effect
	if not item or item.Slot ~= "Aura" or not kind then
		return nil
	end
	local colors = colorsOf(id)
	local reduced = State.ReducedEffects()
	local aura: Aura = {
		Owner = player,
		Id = id,
		Kind = kind,
		Root = root,
		Attachments = {},
		Emitters = {},
		Lanterns = {},
		LanternOffsets = {},
		LanternModels = {},
		Lights = {},
		Clock = math.random() * 10,
		Active = true,
	}
	if kind == "LeafWhirl" then
		for index = 1, 2 do
			local attachment = Instance.new("Attachment")
			attachment.Name = "PP_AuraWhirl"
			attachment.Parent = root
			table.insert(aura.Attachments, attachment)
			local emitter = newEmitter(attachment, {
				Name = "PP_AuraLeaves",
				Color = ColorSequence.new(colors[index] or colors[1]),
				LightEmission = 0.15,
				Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.15, 0.42),
					NumberSequenceKeypoint.new(1, 0.3),
				}),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.2),
					NumberSequenceKeypoint.new(0.75, 0.3),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Lifetime = NumberRange.new(0.9, 1.3),
				Speed = NumberRange.new(0.2, 0.6),
				SpreadAngle = Vector2.new(40, 40),
				Acceleration = Vector3.new(0, 1.5, 0),
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-200, 200),
				Rate = if reduced then 3 else 9,
			})
			SeasonParts.Leaves(emitter)
			table.insert(aura.Emitters, emitter)
		end
	elseif kind == "Fireflies" then
		local attachment = Instance.new("Attachment")
		attachment.Name = "PP_AuraFireflies"
		attachment.Position = Vector3.new(0, 0.4, 0)
		attachment.Parent = root
		table.insert(aura.Attachments, attachment)
		local emitter = newEmitter(attachment, {
			Name = "PP_AuraFireflies",
			Texture = SeasonParts.EmberTexture(),
			Color = ColorSequence.new(colors[1], colors[2] or colors[1]),
			LightEmission = 1,
			LockedToPart = true, -- (they drift round you as you go, not left behind)
			Size = NumberSequence.new(0.2),
			-- Blinking: bright, dim, bright, then out.
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.1, 0.05),
				NumberSequenceKeypoint.new(0.3, 0.85),
				NumberSequenceKeypoint.new(0.45, 0.05),
				NumberSequenceKeypoint.new(0.65, 0.9),
				NumberSequenceKeypoint.new(0.8, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(3, 5),
			Speed = NumberRange.new(0.6, 1.6),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 0.7,
			Acceleration = Vector3.new(0, 0.15, 0),
			Rate = if reduced then 1.2 else 3.5,
		})
		table.insert(aura.Emitters, emitter)
	elseif kind == "LanternRing" then
		for index = 1, 3 do
			local model = SeasonParts.Copy("PaperLantern")
			if not model then
				break
			end
			model.Name = "PP_AuraLantern"
			local paper = model:FindFirstChild("Paper", true)
			if paper and paper:IsA("BasePart") then
				paper.Color = colors[(index - 1) % #colors + 1]
				if not reduced then
					local light = Instance.new("PointLight")
					light.Color = paper.Color
					light.Range = 6
					light.Brightness = 0.55
					light.Shadows = false
					light.Parent = paper
					table.insert(aura.Lights, light)
				end
			end
			local pivot = model:GetPivot()
			local offsets = {}
			local lanternParts = {}
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					table.insert(lanternParts, part)
					table.insert(offsets, pivot:ToObjectSpace(part.CFrame))
				end
			end
			for _, part in lanternParts do
				table.insert(aura.Lanterns, part)
			end
			table.insert(aura.LanternOffsets, offsets)
			table.insert(aura.LanternModels, model)
			model.Parent = folder
		end
		if #aura.LanternModels == 0 then
			return nil -- (the lanterns' mesh hasn't arrived yet: built when it does)
		end
	end
	return aura
end

local function refresh(player: Player)
	local id = player:GetAttribute("PP_Aura")
	local wanted = if type(id) == "string" and id ~= "" then id else nil
	local root = rootOf(player)
	local current = auras[player]
	if current and current.Id == wanted and current.Root == root then
		return
	end
	destroy(player)
	if wanted and root then
		local aura = build(player, wanted, root)
		if aura then
			auras[player] = aura
		end
	end
end

local function setActive(aura: Aura, active: boolean)
	if aura.Active == active then
		return
	end
	aura.Active = active
	for _, emitter in aura.Emitters do
		emitter.Enabled = active
	end
	for _, model in aura.LanternModels do
		model.Parent = if active then folder else nil
	end
end

-- Every frame: the whirl's streams circle, the lanterns float round; each aura rests when its wearer
-- is in a round, gone or far away.
local function step(dt: number)
	local camera = workspace.CurrentCamera
	local cameraAt = if camera then camera.CFrame.Position else Vector3.zero
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	for owner, aura in auras do
		local root = aura.Root
		if not root.Parent then
			destroy(owner)
			continue
		end
		local active = owner:GetAttribute("PP_InRound") ~= true and (root.Position - cameraAt).Magnitude <= RANGE
		setActive(aura, active)
		if not active then
			continue
		end
		aura.Clock += dt
		local t = aura.Clock
		if aura.Kind == "LeafWhirl" then
			for index, attachment in aura.Attachments do
				local angle = t * 3.2 + index * math.pi
				local height = -1.6 + ((t * 0.9 + index * 0.5) % 1) * 3.6
				attachment.Position =
					Vector3.new(math.cos(angle) * WHIRL_RADIUS, height, math.sin(angle) * WHIRL_RADIUS)
			end
		elseif aura.Kind == "LanternRing" then
			-- Level with the ground whatever the root does (a root tilts when its wearer falls over).
			local center = CFrame.new(root.Position + Vector3.new(0, LANTERN_HEIGHT, 0))
			local partIndex = 0
			for index in aura.LanternModels do
				local angle = t * 0.9 + index * math.pi * 2 / 3
				local bob = math.sin(t * 1.8 + index * 2) * 0.22
				local frame = center
					* CFrame.new(math.cos(angle) * LANTERN_RADIUS, bob, math.sin(angle) * LANTERN_RADIUS)
					* CFrame.Angles(0, -angle, math.sin(t * 1.3 + index) * 0.12)
				for _, offset in aura.LanternOffsets[index] do
					partIndex += 1
					table.insert(parts, aura.Lanterns[partIndex])
					table.insert(frames, frame * offset)
				end
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("PP_Aura"):Connect(function()
		refresh(player)
	end)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		refresh(player)
	end)
	refresh(player)
end

function AuraController.Start(_context)
	folder = Instance.new("Folder")
	folder.Name = "LocalAuras"
	folder.Parent = workspace
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(destroy)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	SeasonParts.OnTemplates(function()
		for _, player in Players:GetPlayers() do
			refresh(player)
		end
	end)
	-- Reduced effects switched: every aura is made again at its new strength.
	State.SettingsChanged:Connect(function()
		for player in table.clone(auras) do
			destroy(player)
			refresh(player)
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return AuraController

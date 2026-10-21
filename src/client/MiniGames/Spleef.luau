-- Client half of Spleef: picks the block you click or tap (or DIG's pick: the block under the
-- nearest rival in reach) and asks the server to break it, showing the break at once (puff, chunks,
-- crunch, your shovel's swing) and putting the block back if the server says no. Draws everyone
-- else's breaks, shakes and flashes the blocks that are cracking until they drop (the server's
-- DropAt schedule), splashes whoever hits the water, and shows which floor you're on.
-- Floors above you turn see-through (and the camera fades what's in its way instead of zooming in),
-- so being under a floor never hides the game.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local Spleef = {}

local PUFF = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local COOLDOWN = 0.2 -- between your breaks (the server allows a little faster)
local GHOST = 0.6 -- floors above you are this see-through
local GRAVITY = 110 -- for chunks and dropping blocks (a little floaty: they read better)
local FLOOR_COLORS = {
	Color3.fromRGB(248, 251, 255),
	Color3.fromRGB(186, 222, 252),
	Color3.fromRGB(120, 188, 246),
}
local WARN_COLOR = Color3.fromRGB(150, 236, 255)

type Block = {
	Index: number,
	Floor: number,
	I: number,
	J: number,
	Part: BasePart,
	Base: CFrame,
	Top: Vector3,
	Gone: boolean, -- broken (on the server or by our own guess)
	Guessed: number?, -- when we broke it ahead of the server
	DropAt: number?,
	Dust: ParticleEmitter?,
}

type Bit = {
	Part: BasePart,
	Velocity: Vector3,
	Spin: Vector3,
	Born: number,
	Life: number,
	Size: Vector3,
}

-- One of the shared sound effects at a pitch and volume of our own (PumpAndPop does the same).
local function playSound(api, name: string, speed: number, volume: number)
	local sprite = Sounds.Sprite
	local region = sprite and sprite.Regions[name]
	if not sprite or not region then
		api:Sound(name)
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = sprite.Id
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(region.Start, region.Start + region.Length)
	sound.PlaybackSpeed = speed
	sound.Volume = volume
	sound.Parent = SoundService
	api:Track(sound)
	sound:Play()
	task.delay(region.Length / speed + 0.3, function()
		sound:Destroy()
	end)
end

local function key(i: number, j: number): number
	return (i + 64) * 256 + (j + 64)
end

function Spleef.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(236, 246, 255),
		Saturation = -0.04,
		Contrast = 0.08,
		Brightness = 0.02,
		Haze = Color3.fromRGB(222, 236, 255),
		HazeDecay = Color3.fromRGB(170, 196, 232),
		Density = 0.26,
	})
	local arena = api:Arena()
	if not arena then
		return
	end
	local localPlayer = Players.LocalPlayer
	local myId = if localPlayer then localPlayer.UserId else 0
	local camera = workspace.CurrentCamera

	-- The camera fades what's between it and you instead of zooming in under a floor.
	pcall(function()
		local saved = localPlayer.DevCameraOcclusionMode
		localPlayer.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
		api:Track(function()
			pcall(function()
				localPlayer.DevCameraOcclusionMode = saved
			end)
		end)
	end)

	local layout = api:SharedJSON("Layout")
	local function refreshLayout()
		layout = api:SharedJSON("Layout") or layout
	end
	api:OnShared("Layout", refreshLayout)
	local BLOCK = 4
	local HEIGHT = 3

	-- Effects live on one invisible anchor: attachments for puffs and splashes.
	local anchor = Instance.new("Part")
	anchor.Name = "SpleefFx"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.identity
	anchor.Parent = api.World

	local function burst(position: Vector3, props: { [string]: any }, count: number)
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = position
		attachment.Parent = anchor
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 0
		for name, value in props do
			(emitter :: any)[name] = value
		end
		emitter.Parent = attachment
		emitter:Emit(count)
		task.delay(2.5, function()
			attachment:Destroy()
		end)
	end

	local reduced = State.ReducedEffects()
	local function puff(position: Vector3, color: Color3, big: boolean)
		burst(position, {
			Texture = PUFF,
			Color = ColorSequence.new(Color3.new(1, 1, 1), color),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.15),
				NumberSequenceKeypoint.new(0.6, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Size = NumberSequence.new(if big then 2.4 else 1.6, if big then 4.6 else 3.2),
			Lifetime = NumberRange.new(0.45, 0.8),
			Speed = NumberRange.new(5, 11),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 4,
			Acceleration = Vector3.new(0, -6, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-90, 90),
			LightEmission = 0.15,
		}, if reduced then 5 else 11)
		if not reduced then
			burst(position, {
				Texture = SPARKLE,
				Color = ColorSequence.new(Color3.fromRGB(220, 244, 255)),
				Size = NumberSequence.new(0.5, 0),
				Lifetime = NumberRange.new(0.5, 0.9),
				Speed = NumberRange.new(8, 16),
				SpreadAngle = Vector2.new(70, 70),
				EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, -40, 0),
				LightEmission = 0.8,
			}, 8)
		end
	end

	-- Bits: snow chunks flung from a dug block, and whole blocks dropping out of a floor.
	local bits: { Bit } = {}
	local function addBit(part: BasePart, velocity: Vector3, spin: Vector3, life: number)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = api.World
		table.insert(bits, {
			Part = part,
			Velocity = velocity,
			Spin = spin,
			Born = os.clock(),
			Life = life,
			Size = part.Size,
		})
	end

	local rng = Random.new()
	local lastCrunch = 0
	local function crunch(position: Vector3, mine: boolean)
		local distance = (camera.CFrame.Position - position).Magnitude
		if distance > 120 or os.clock() - lastCrunch < 0.05 then
			return
		end
		lastCrunch = os.clock()
		local volume = (if mine then 1 else 0.75) * math.clamp(1 - distance / 120, 0.15, 1)
		playSound(api, "Splash", 2.5 + rng:NextNumber(-0.2, 0.25), volume * 0.9)
		playSound(api, "Hit", 1.5 + rng:NextNumber(-0.1, 0.15), volume * 0.3)
	end

	-- Blocks ---------------------------------------------------------------------------------
	local blocks: { [number]: Block } = {}
	local grid: { { [number]: Block } } = { {}, {}, {} }
	local folders: { Instance } = {}
	local templates: { BasePart } = {}
	local myFloor: number? = nil
	local cracking: { [Block]: boolean } = {}

	local function ghostOf(block: Block): number
		return if myFloor and block.Floor < myFloor then GHOST else 0
	end

	local function startCrack(block: Block, dropAt: number)
		if block.Gone or block.DropAt then
			return
		end
		block.DropAt = dropAt
		cracking[block] = true
		if not reduced and block.Part.Parent then
			local dust = Instance.new("ParticleEmitter")
			dust.Texture = PUFF
			dust.Color = ColorSequence.new(Color3.new(1, 1, 1))
			dust.Transparency = NumberSequence.new(0.35, 1)
			dust.Size = NumberSequence.new(0.6, 1.4)
			dust.Lifetime = NumberRange.new(0.6, 1)
			dust.Speed = NumberRange.new(1, 3)
			dust.EmissionDirection = Enum.NormalId.Bottom
			dust.Acceleration = Vector3.new(0, -14, 0)
			dust.Rate = 14
			dust.Parent = block.Part
			block.Dust = dust
		end
	end

	local function addBlock(part: Instance)
		if not part:IsA("BasePart") then
			return
		end
		local index = part:GetAttribute("Cell")
		local floor = part:GetAttribute("Floor")
		if type(index) ~= "number" or type(floor) ~= "number" or blocks[index] then
			return
		end
		local top = part.Position + Vector3.new(0, HEIGHT / 2, 0)
		local x = if layout then layout.X else 0
		local z = if layout then layout.Z else 0
		local block: Block = {
			Index = index,
			Floor = floor,
			I = math.floor((top.X - x) / BLOCK + 0.5),
			J = math.floor((top.Z - z) / BLOCK + 0.5),
			Part = part,
			Base = part.CFrame,
			Top = top,
			Gone = false,
		}
		blocks[index] = block
		grid[floor][key(block.I, block.J)] = block
		part.LocalTransparencyModifier = ghostOf(block)
		if not templates[floor] then
			local copy = part:Clone()
			for name in copy:GetAttributes() do
				copy:SetAttribute(name, nil)
			end
			templates[floor] = copy
		end
		local dropAt = part:GetAttribute("DropAt")
		if type(dropAt) == "number" then
			startCrack(block, dropAt)
		end
	end

	-- Shows a block breaking: dug ones burst into chunks, crumbling ones drop out whole.
	local function breakVisual(block: Block, dropping: boolean, mine: boolean)
		if block.Gone then
			return
		end
		block.Gone = true
		cracking[block] = nil
		local part = block.Part
		if part.Parent then
			part.LocalTransparencyModifier = 1
			part.CanCollide = false
			part.CanQuery = false
			part.CFrame = block.Base
			if block.Dust then
				block.Dust.Enabled = false
			end
		end
		local color = FLOOR_COLORS[block.Floor] or Color3.new(1, 1, 1)
		local center = block.Base.Position
		if dropping then
			local template = templates[block.Floor]
			if template then
				local copy = template:Clone()
				copy.CFrame = block.Base
				copy.Color = color
				addBit(
					copy,
					Vector3.new(0, -4, 0),
					Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * 1.2,
					1.6
				)
			end
			puff(block.Top, color, false)
			return
		end
		puff(block.Top, color, true)
		local count = if reduced then 3 else 6
		for index = 1, count do
			local chunk = Instance.new("Part")
			chunk.Name = "Chunk"
			local size = rng:NextNumber(0.8, 1.5)
			chunk.Size = Vector3.new(size, size * rng:NextNumber(0.7, 1), size)
			chunk.Color = color
			chunk.Material = Enum.Material.Snow
			local angle = (index / count + rng:NextNumber(-0.08, 0.08)) * math.pi * 2
			local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
			chunk.CFrame = CFrame.new(center + out * 1.2 + Vector3.new(0, rng:NextNumber(-0.6, 1), 0))
				* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
			addBit(
				chunk,
				out * rng:NextNumber(6, 13) + Vector3.new(0, rng:NextNumber(14, 26), 0),
				Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8)),
				rng:NextNumber(0.8, 1.1)
			)
		end
		crunch(center, mine)
	end

	-- Puts back a block we broke ahead of the server when it says no (or never confirms).
	local function restore(block: Block)
		if not block.Gone or not block.Guessed or not block.Part.Parent then
			return
		end
		block.Gone = false
		block.Guessed = nil
		block.Part.LocalTransparencyModifier = ghostOf(block)
		block.Part.CanCollide = true
		block.Part.CanQuery = true
	end

	task.spawn(function()
		local holder = arena:WaitForChild("Blocks", 15)
		local deadline = os.clock() + 10
		while not layout and os.clock() < deadline do
			task.wait(0.1)
			refreshLayout()
		end
		if not holder or not layout then
			return
		end
		for floor = 1, 3 do
			local folder = holder:WaitForChild("Floor" .. floor, 10)
			if not folder then
				continue
			end
			folders[floor] = folder
			for _, part in folder:GetChildren() do
				addBlock(part)
			end
			api:Track(folder.ChildAdded:Connect(addBlock))
			api:Track(folder.ChildRemoved:Connect(function(part)
				local index = part:GetAttribute("Cell")
				local block = if type(index) == "number" then blocks[index] else nil
				if block then
					block.Guessed = nil
					breakVisual(block, block.DropAt ~= nil, false)
				end
			end))
		end
	end)

	-- Where everyone is, as on this screen ----------------------------------------------------
	local function feetOf(character: Model?): (number?, BasePart?)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root then
			return nil, nil
		end
		return root.Position.Y - humanoid.HipHeight - root.Size.Y / 2, root
	end

	local function floorAt(feet: number): number?
		if not layout then
			return nil
		end
		for floor, top in layout.Tops do
			if math.abs(feet - top) <= 1 then
				return floor
			end
		end
		return nil
	end

	-- The floor you're on, or the one you'll land on (nil once you're under the last one).
	local function floorBelow(feet: number): number?
		if not layout then
			return nil
		end
		for floor, top in layout.Tops do
			if feet >= top - 1 then
				return floor
			end
		end
		return nil
	end

	local function supports(floor: number, position: Vector3): { Block }
		local found = {}
		if not layout then
			return found
		end
		local i0 = math.floor((position.X - layout.X) / BLOCK + 0.5)
		local j0 = math.floor((position.Z - layout.Z) / BLOCK + 0.5)
		local reach = BLOCK / 2 + 1
		for i = i0 - 1, i0 + 1 do
			for j = j0 - 1, j0 + 1 do
				local block = grid[floor][key(i, j)]
				if
					block
					and not block.Gone
					and math.abs(position.X - block.Top.X) <= reach
					and math.abs(position.Z - block.Top.Z) <= reach
				then
					table.insert(found, block)
				end
			end
		end
		return found
	end

	-- Whether you can break this block now: on your floor or below, within reach of your eyes.
	local function canBreak(block: Block): boolean
		local _, humanoid, root = api:Character()
		if block.Gone or not humanoid or not root or not layout then
			return false
		end
		local feet = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
		if block.Top.Y > feet + 1 then
			return false
		end
		local eye = root.Position + Vector3.new(0, layout.Eye, 0)
		local nearest = Vector3.new(
			math.clamp(eye.X, block.Top.X - BLOCK / 2, block.Top.X + BLOCK / 2),
			math.clamp(eye.Y, block.Top.Y - HEIGHT, block.Top.Y),
			math.clamp(eye.Z, block.Top.Z - BLOCK / 2, block.Top.Z + BLOCK / 2)
		)
		return (nearest - eye).Magnitude <= layout.Reach
	end

	-- Shovel swings (anyone's): the shovel's weld dips forward and back.
	local swings: { [Weld]: { Start: number, Base: CFrame } } = {}
	local function swing(character: Model?)
		local shovel = character and character:FindFirstChild("SpleefShovel")
		local weld = shovel and shovel:FindFirstChild("ShovelWeld", true)
		if weld and weld:IsA("Weld") then
			local current = swings[weld]
			swings[weld] = { Start = os.clock(), Base = if current then current.Base else weld.C0 }
		end
	end

	-- Breaking -------------------------------------------------------------------------------
	local hover = Instance.new("SelectionBox")
	hover.Name = "SpleefHover"
	hover.LineThickness = 0.07
	hover.SurfaceTransparency = 0.82
	hover.Transparency = 0.1
	hover.Parent = api.World
	local flashUntil = 0
	local function showBox(block: Block?, ok: boolean, flash: number?)
		hover.Adornee = if block and block.Part.Parent then block.Part else nil
		hover.Color3 = if ok then Color3.new(1, 1, 1) else Theme.Colors.Red
		hover.SurfaceColor3 = if ok then Color3.fromRGB(200, 240, 255) else Theme.Colors.Red
		if flash then
			flashUntil = os.clock() + flash
		end
	end

	local lastBreak = 0
	local broken = 0
	local hintShown = true
	local function tryBreak(block: Block, quiet: boolean?): boolean
		if os.clock() - lastBreak < COOLDOWN or not api:CanAct() then
			return false
		end
		if not canBreak(block) then
			if not quiet then
				showBox(block, false, 0.35)
			end
			return false
		end
		lastBreak = os.clock()
		api:Action("Break", block.Index)
		block.Guessed = os.clock()
		breakVisual(block, false, true)
		swing(api:Character())
		broken += 1
		if hintShown and broken >= 2 then
			hintShown = false
			api:Hint("")
		end
		return true
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local function pick(ray: Ray): Block?
		local include = {}
		for floor = myFloor or 1, 3 do
			if folders[floor] then
				table.insert(include, folders[floor])
			end
		end
		params.FilterDescendantsInstances = include
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, params)
		local index = hit and hit.Instance:GetAttribute("Cell")
		return if type(index) == "number" then blocks[index] else nil
	end

	-- DIG: the block under the nearest rival in reach (the one right under them first), else the
	-- block ahead of you.
	local function autoTarget(): Block?
		local _, humanoid, root = api:Character()
		if not humanoid or not root or not myFloor then
			return nil
		end
		local mine = {}
		for _, block in supports(myFloor, root.Position) do
			mine[block] = true
		end
		local best, bestDistance = nil, math.huge
		for _, participant in api:Participants() do
			if participant.UserId == myId or participant:GetAttribute("PP_Alive") ~= true then
				continue
			end
			local feet, otherRoot = feetOf(participant:Character())
			if not feet or not otherRoot or floorAt(feet) ~= myFloor then
				continue
			end
			local distance = (otherRoot.Position - root.Position).Magnitude
			if distance >= bestDistance then
				continue
			end
			local under = supports(myFloor, otherRoot.Position)
			table.sort(under, function(a, b)
				return (a.Top - otherRoot.Position).Magnitude < (b.Top - otherRoot.Position).Magnitude
			end)
			for _, block in under do
				if not mine[block] and canBreak(block) then
					best, bestDistance = block, distance
					break
				end
			end
		end
		if best then
			return best
		end
		local look = root.CFrame.LookVector
		local ahead = root.Position + Vector3.new(look.X, 0, look.Z).Unit * BLOCK * 1.6
		for _, block in supports(myFloor, ahead) do
			if not mine[block] and canBreak(block) then
				return block
			end
		end
		return nil
	end

	local dig = api:Button({ Text = "DIG", Key = Enum.KeyCode.E, Color = Theme.Colors.Cyan })
	dig.Pressed:Connect(function()
		local block = autoTarget()
		if block then
			tryBreak(block)
		end
	end)

	local holding = false
	api:Track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = true
			local block = pick(camera:ScreenPointToRay(input.Position.X, input.Position.Y))
			if block then
				tryBreak(block)
			end
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			local block = autoTarget()
			if block then
				tryBreak(block)
			end
		end
	end))
	api:Track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = false
		end
	end))
	api:Track(UserInputService.TouchTap:Connect(function(positions, processed)
		if processed or not positions[1] then
			return
		end
		local point = positions[1]
		local block = pick(camera:ScreenPointToRay(point.X, point.Y))
		if block and tryBreak(block) then
			showBox(block, true, 0.2)
		end
	end))

	-- Server cues ----------------------------------------------------------------------------
	api:OnEvent("Broke", function(index, userId)
		local block = blocks[index]
		if not block then
			return
		end
		local mine = userId == myId
		if block.Guessed then
			block.Guessed = nil -- confirmed
		else
			breakVisual(block, false, mine)
		end
		if not mine then
			swing(api:CharacterOf(userId))
		end
	end)
	api:OnEvent("Denied", function(index)
		local block = blocks[index]
		if block then
			restore(block)
		end
	end)
	api:OnEvent("Crack", function(indices, dropAt)
		if type(indices) ~= "table" or type(dropAt) ~= "number" then
			return
		end
		local near = false
		local _, _, root = api:Character()
		for _, index in indices do
			local block = blocks[index]
			if block then
				startCrack(block, dropAt)
				if root and (block.Top - root.Position).Magnitude < 14 then
					near = true
				end
			end
		end
		if near then
			playSound(api, "HazardWarning", 0.8, 0.5)
		end
	end)

	-- HUD: which floor you're on ---------------------------------------------------------------
	local hud = api:TopHud()
	local panel = UIKit.Panel({
		Name = "Floor",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY()),
		Size = UDim2.fromOffset(250, 58),
		CornerRadius = 18,
		Visible = false,
		Parent = hud,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local stack = UIKit.new("Frame", {
		Name = "Stack",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	local bars = {}
	for floor = 1, 3 do
		local bar = UIKit.new("Frame", {
			Name = "Bar" .. floor,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, (floor - 1) * 14),
			Size = UDim2.fromOffset(34, 10),
			BackgroundColor3 = FLOOR_COLORS[floor],
			Parent = stack,
			Children = { UIKit.Corner(3) },
		})
		local stroke = UIKit.Stroke(Theme.Colors.Yellow, 2.5, 1)
		stroke.Parent = bar
		bars[floor] = { Bar = bar, Stroke = stroke }
	end
	local floorText = UIKit.Label({
		Name = "FloorText",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(68, 0),
		Size = UDim2.new(1, -78, 1, 0),
		Parent = panel,
		Children = { UIKit.TextStroke(0.1) },
	})
	local shownFloor: number? = -1
	local function showFloor(floor: number?)
		if floor == shownFloor then
			return
		end
		shownFloor = floor
		panel.Visible = floor ~= nil and api:Alive()
		if not floor then
			return
		end
		for index, entry in bars do
			entry.Stroke.Transparency = if index == floor then 0 else 1
			entry.Bar.Size = if index == floor then UDim2.fromOffset(38, 12) else UDim2.fromOffset(30, 9)
			entry.Bar.BackgroundTransparency = if index < floor then 0.65 else 0
		end
		floorText.Text = if floor == 3 then "LAST FLOOR!" else `FLOOR {floor} / 3`
		floorText.TextColor3 = if floor == 3 then Theme.Colors.Orange else Color3.new(1, 1, 1)
		UIKit.PopIn(panel, 0.25)
	end

	local cheer = UIKit.Label({
		Name = "Spleef",
		Text = "SPLEEF!",
		Font = Theme.Fonts.Display,
		TextSize = 58,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY() + 70),
		Size = UDim2.fromOffset(420, 70),
		TextColor3 = Theme.Colors.Cyan,
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0) },
	})
	local cheerUntil = 0
	api:OnEvent("Spleefed", function(_victim, by)
		if by == myId then
			cheer.Visible = true
			cheerUntil = os.clock() + 1.6
			UIKit.PopIn(cheer, 0.3)
			api:Sound("Pickup")
		end
	end)

	api:Hint(if api:IsTouch() then "Tap blocks near you to break them!" else "Click blocks near you to break them!")
	task.delay(8, function()
		if hintShown then
			hintShown = false
			api:Hint("")
		end
	end)

	-- Falling snow (ambient: off with reduced effects).
	local sky = Instance.new("Part")
	sky.Name = "Snowfall"
	sky.Anchored = true
	sky.CanCollide = false
	sky.CanQuery = false
	sky.CanTouch = false
	sky.Transparency = 1
	sky.Size = Vector3.new(170, 1, 170)
	sky.CFrame = CFrame.new(0, -1000, 0) -- placed over the floors once the layout is in
	sky.Parent = api.World
	local snow = Instance.new("ParticleEmitter")
	snow.Texture = SPARKLE
	snow.Color = ColorSequence.new(Color3.new(1, 1, 1))
	snow.LightEmission = 0.3
	snow.Size = NumberSequence.new(0.35, 0.25)
	snow.Lifetime = NumberRange.new(9, 13)
	snow.Speed = NumberRange.new(5, 8)
	snow.SpreadAngle = Vector2.new(12, 12)
	snow.Acceleration = Vector3.new(1.5, 0, 0.8)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.Rate = 70
	snow.Rotation = NumberRange.new(0, 360)
	snow.RotSpeed = NumberRange.new(-40, 40)
	snow.Enabled = not reduced
	snow.Parent = sky
	CollectionService:AddTag(snow, "PP_Ambient")

	-- Every frame -----------------------------------------------------------------------------
	local lastY: { [Model]: number } = {}
	api:RenderStep(function(dt)
		local now = os.clock()
		local serverNow = api:Now()
		if layout and sky.Position.Y < layout.Tops[1] then
			sky.CFrame = CFrame.new(layout.X, layout.Tops[1] + 45, layout.Z)
		end

		-- Which floor I'm on (or falling to): floors above me go see-through.
		local character, humanoid, root = api:Character()
		local floor: number? = nil
		if humanoid and root and api:Alive() then
			floor = floorBelow(root.Position.Y - humanoid.HipHeight - root.Size.Y / 2)
		end
		if floor ~= myFloor then
			myFloor = floor
			for _, block in blocks do
				if not block.Gone and block.Part.Parent then
					block.Part.LocalTransparencyModifier = ghostOf(block)
				end
			end
		end
		showFloor(if humanoid and root and api:Alive() then floor else nil)

		-- Our guesses the server never confirmed come back.
		for _, block in blocks do
			if block.Guessed and now - block.Guessed > 1.2 then
				restore(block)
			end
		end

		-- Cracking blocks shake and flash, harder as they're about to go; on time, they drop.
		for block in cracking do
			local part = block.Part
			local dropAt = block.DropAt or 0
			if not part.Parent or serverNow >= dropAt then
				breakVisual(block, true, false)
				continue
			end
			local left = math.clamp((dropAt - serverNow) / 1.9, 0, 1)
			local amount = 0.05 + 0.12 * (1 - left)
			local pulse = 0.5 + 0.5 * math.sin(now * (9 + 14 * (1 - left)))
			part.CFrame = block.Base
				* CFrame.new(rng:NextNumber(-amount, amount), 0, rng:NextNumber(-amount, amount))
				* CFrame.Angles(0, rng:NextNumber(-0.02, 0.02), 0)
			part.Color = (FLOOR_COLORS[block.Floor] or Color3.new(1, 1, 1)):Lerp(WARN_COLOR, pulse)
			part.Material = if pulse > 0.72 then Enum.Material.Neon else Enum.Material.Snow
		end

		-- Chunks and dropping blocks.
		for index = #bits, 1, -1 do
			local bit = bits[index]
			local age = now - bit.Born
			if age >= bit.Life or not bit.Part.Parent then
				bit.Part:Destroy()
				table.remove(bits, index)
				continue
			end
			bit.Velocity -= Vector3.new(0, GRAVITY * dt, 0)
			local spin = bit.Spin * dt
			bit.Part.CFrame = (bit.Part.CFrame + bit.Velocity * dt) * CFrame.Angles(spin.X, spin.Y, spin.Z)
			local fade = math.clamp((age - bit.Life * 0.6) / (bit.Life * 0.4), 0, 1)
			bit.Part.Transparency = fade
		end

		-- Shovel swings.
		for weld, entry in swings do
			local t = (now - entry.Start) / 0.3
			if t >= 1 or not weld.Parent then
				weld.C0 = entry.Base
				swings[weld] = nil
				continue
			end
			weld.C0 = entry.Base * CFrame.Angles(math.rad(-75 * math.sin(t * math.pi)), 0, 0)
		end

		-- Splashes where anyone hits the water.
		if layout then
			for _, participant in api:Participants() do
				local model = participant:Character()
				local body = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
				if model and body then
					local y = body.Position.Y
					local before = lastY[model]
					lastY[model] = y
					if before and before > layout.Water and y <= layout.Water then
						local spot = Vector3.new(body.Position.X, layout.Water, body.Position.Z)
						burst(spot, {
							Texture = PUFF,
							Color = ColorSequence.new(Color3.fromRGB(210, 240, 255)),
							Transparency = NumberSequence.new(0.1, 1),
							Size = NumberSequence.new(2, 5),
							Lifetime = NumberRange.new(0.6, 1.1),
							Speed = NumberRange.new(18, 34),
							SpreadAngle = Vector2.new(28, 28),
							EmissionDirection = Enum.NormalId.Top,
							Acceleration = Vector3.new(0, -70, 0),
						}, if reduced then 8 else 22)
						if (camera.CFrame.Position - spot).Magnitude < 160 then
							api:Sound("Splash")
						end
					end
				end
			end
		end

		-- Hovering a block (mouse): white if you can break it, red if it's too far; hold to dig.
		if now > flashUntil then
			if UserInputService.MouseEnabled and not api:IsTouch() and character then
				local mouse = UserInputService:GetMouseLocation()
				local block = pick(camera:ViewportPointToRay(mouse.X, mouse.Y))
				local ok = block ~= nil and canBreak(block)
				showBox(block, ok)
				if holding and block and ok then
					tryBreak(block, true)
				end
			else
				hover.Adornee = nil
			end
		end
		if cheer.Visible and now > cheerUntil then
			cheer.Visible = false
		end
	end)
end

return Spleef

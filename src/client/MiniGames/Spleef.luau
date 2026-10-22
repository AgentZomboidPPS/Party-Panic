-- Client half of Spleef.
--
-- First pass: picked the block you clicked or tapped (or DIG's pick) and asked the server to break
-- it, swung your shovel, burst the blocks the server broke and shook the ones crumbling.
--
-- Second pass (owner: "spleef doesnt require you to dig. It should be you walk over it and it fades
-- out within like 1 second or so"): no shovel, no buttons, no clicking. The server decides which
-- blocks anyone stepped on and gives each a DropAt time on the shared clock ("Fade" event and
-- attribute). Every client shows the same countdown on it: it shakes, cracks open and turns orange
-- (shape, motion and colour, not colour alone), turns see-through for the last moment (Layout.Fade),
-- and at DropAt it's hidden and its collision goes off here, the same moment the server destroys it.
-- So a block holds you up exactly as long as it's drawn. Also splashes whoever hits the water and
-- shows which floor you're on. Under a floor, the camera fades whatever is in its way (Invisicam)
-- instead of zooming in.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local Spleef = {}

local PUFF = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FLOOR_COLORS = {
	Color3.fromRGB(248, 251, 255),
	Color3.fromRGB(150, 194, 238),
	Color3.fromRGB(84, 148, 222),
}
local WARN_COLOR = Color3.fromRGB(255, 150, 70) -- a fading block warms to orange as it goes
local CRACK_COLOR = Color3.fromRGB(46, 58, 92)
local CRACKS = 4 -- crack lines on a fading block's top

type Block = {
	Index: number,
	Floor: number,
	Part: BasePart,
	Base: CFrame,
	Top: Vector3,
	Gone: boolean, -- hidden here (its time is up, or the server removed it)
	DropAt: number?,
	Total: number?, -- its whole countdown, as first seen here
	Cracks: { { Part: BasePart, Angle: number, Length: number } }?,
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
	local function fadeTime(): number
		return if layout and type(layout.Fade) == "number" then layout.Fade else 0.3
	end

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
	local function puff(position: Vector3, color: Color3)
		burst(position, {
			Texture = PUFF,
			Color = ColorSequence.new(Color3.new(1, 1, 1), color),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.25),
				NumberSequenceKeypoint.new(0.6, 0.55),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Size = NumberSequence.new(1.8, 3.6),
			Lifetime = NumberRange.new(0.4, 0.7),
			Speed = NumberRange.new(3, 7),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 4,
			Acceleration = Vector3.new(0, -8, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-90, 90),
			LightEmission = 0.15,
		}, if reduced then 3 else 7)
	end

	local rng = Random.new()
	local lastCrunch = 0
	local function crunch(position: Vector3)
		local distance = (camera.CFrame.Position - position).Magnitude
		if distance > 60 or os.clock() - lastCrunch < 0.09 then
			return
		end
		lastCrunch = os.clock()
		local volume = math.clamp(1 - distance / 60, 0.15, 1)
		playSound(api, "Splash", 2.6 + rng:NextNumber(-0.2, 0.25), volume * 0.45)
	end

	-- Cracks: thin dark lines across a fading block's top, from its middle out (pooled).
	local crackPool: { BasePart } = {}
	local function newCrack(): BasePart
		local part = table.remove(crackPool)
		if part then
			return part
		end
		part = Instance.new("Part")
		part.Name = "Crack"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = CRACK_COLOR
		part.Size = Vector3.new(0.16, 0.05, 1)
		return part
	end
	local function freeCracks(block: Block)
		if block.Cracks then
			for _, crack in block.Cracks do
				crack.Part.Parent = nil
				table.insert(crackPool, crack.Part)
			end
			block.Cracks = nil
		end
	end
	api:Track(function()
		for _, part in crackPool do
			part:Destroy()
		end
	end)

	-- Blocks ---------------------------------------------------------------------------------
	local blocks: { [number]: Block } = {}
	local fading: { [Block]: boolean } = {}

	local function startFade(block: Block, dropAt: number)
		if block.Gone or block.DropAt then
			return
		end
		block.DropAt = dropAt
		block.Total = math.max(dropAt - api:Now(), fadeTime() + 0.1)
		fading[block] = true
		local cracks = {}
		local turn = rng:NextNumber(0, math.pi * 2)
		for index = 1, CRACKS do
			table.insert(cracks, {
				Part = newCrack(),
				Angle = turn + (index / CRACKS) * math.pi * 2 + rng:NextNumber(-0.35, 0.35),
				Length = rng:NextNumber(1.4, 2.3),
			})
		end
		block.Cracks = cracks
	end

	-- Hides a block whose time is up: from this moment it's neither drawn nor solid here (the
	-- server destroys it at the same DropAt).
	local function vanish(block: Block)
		if block.Gone then
			return
		end
		block.Gone = true
		fading[block] = nil
		freeCracks(block)
		local part = block.Part
		if part.Parent then
			part.LocalTransparencyModifier = 1
			part.CanCollide = false
			part.CanQuery = false
			part.CFrame = block.Base
		end
		puff(block.Top - Vector3.new(0, 1, 0), FLOOR_COLORS[block.Floor] or Color3.new(1, 1, 1))
		crunch(block.Top)
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
		local block: Block = {
			Index = index,
			Floor = floor,
			Part = part,
			Base = part.CFrame,
			Top = part.Position + Vector3.new(0, part.Size.Y / 2, 0),
			Gone = false,
		}
		blocks[index] = block
		local dropAt = part:GetAttribute("DropAt")
		if type(dropAt) == "number" then
			startFade(block, dropAt)
		end
	end

	task.spawn(function()
		local holder = arena:WaitForChild("Blocks", 15)
		if not holder then
			return
		end
		for floor = 1, 3 do
			local folder = holder:WaitForChild("Floor" .. floor, 10)
			if not folder then
				continue
			end
			for _, part in folder:GetChildren() do
				addBlock(part)
			end
			api:Track(folder.ChildAdded:Connect(addBlock))
			api:Track(folder.ChildRemoved:Connect(function(part)
				local index = part:GetAttribute("Cell")
				local block = if type(index) == "number" then blocks[index] else nil
				if block then
					vanish(block)
				end
			end))
		end
	end)

	api:OnEvent("Fade", function(indices, dropAt)
		if type(indices) ~= "table" or type(dropAt) ~= "number" then
			return
		end
		for _, index in indices do
			local block = blocks[index]
			if block then
				startFade(block, dropAt)
			end
		end
	end)

	-- Where you are, as on this screen ---------------------------------------------------------
	-- Feet height, the server's way (Spleef.Feet: R6 bodies have no hip height).
	local function feetFrom(humanoid: Humanoid, root: BasePart): number
		local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2
		return root.Position.Y - legs
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

	api:Hint("Keep moving! Blocks vanish after you step on them", api:HudY() + 66)
	task.delay(8, function()
		api:Hint("")
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
	api:RenderStep(function()
		local serverNow = api:Now()
		if layout and sky.Position.Y < layout.Tops[1] then
			sky.CFrame = CFrame.new(layout.X, layout.Tops[1] + 45, layout.Z)
		end

		-- Which floor I'm on (or falling to).
		local _, humanoid, root = api:Character()
		local floor: number? = nil
		if humanoid and root and api:Alive() then
			floor = floorBelow(feetFrom(humanoid, root))
		end
		showFloor(floor)

		-- Fading blocks: shake, crack and warm to orange, then turn see-through, then go (at
		-- DropAt, the server's moment).
		local fade = fadeTime()
		for block in fading do
			local part = block.Part
			local dropAt = block.DropAt or 0
			local left = dropAt - serverNow
			if left <= 0 or not part.Parent then
				vanish(block)
				continue
			end
			local total = block.Total or 1
			local warn = math.max(total - fade, 0.05)
			local p = math.clamp(1 - (left - fade) / warn, 0, 1) -- through the warning: 0 to 1
			local q = math.clamp(1 - left / fade, 0, 1) -- through the fade: 0 to 1
			local amount = 0.04 + 0.12 * p + 0.06 * q
			local offset = Vector3.new(rng:NextNumber(-amount, amount), 0, rng:NextNumber(-amount, amount))
			part.CFrame = block.Base + offset
			part.Color = (FLOOR_COLORS[block.Floor] or Color3.new(1, 1, 1)):Lerp(WARN_COLOR, 0.3 + 0.55 * p)
			part.LocalTransparencyModifier = 0.7 * q
			if block.Cracks then
				local top = block.Top + offset + Vector3.new(0, 0.03, 0)
				for _, crack in block.Cracks do
					local length = crack.Length * (0.3 + 0.7 * p)
					local crackPart = crack.Part
					crackPart.Size = Vector3.new(0.16, 0.05, length)
					crackPart.CFrame = CFrame.new(top)
						* CFrame.Angles(0, crack.Angle, 0)
						* CFrame.new(0, 0, -length / 2)
					crackPart.Transparency = 0.7 * q
					if crackPart.Parent ~= api.World then
						crackPart.Parent = api.World
					end
				end
			end
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
	end)
end

return Spleef

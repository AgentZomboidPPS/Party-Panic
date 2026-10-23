-- The crate season's lobby on this device (World/SeasonWorld builds what everyone shares; owner: "This
-- has to be sick. This will be players first season. I want it to look insane."). All of it is this
-- device's own and costs the server nothing:
--   * the harvest moon low over the vote stage, and a warm autumn grade on the lobby's light (only at
--     the lobby, and never over a limited-time event's own look: Controllers/EventController);
--   * green wisps drifting round the top of the pile ("Wisps that answer: When someone opens a crate,
--     the wisps on the pile drift over to that altar and circle it");
--   * the crows on the rooftops: they look about and ruffle their wings, and fly off across the sky
--     at a pet or title pull ("Crows that react"), coming back a little later;
--   * the leaf heaps on the lawn burst when anyone jumps in ("A free lobby toy that sells the season");
--   * the key over each altar hides while it's in use; the pile's glow flares in a prize's tier colour;
--   * the Top Unboxers board (GameState CrateBoard, both faces);
--   * the season's moments: the trees turning from green to orange for the welcome (TurnTrees), and
--     THE HARVESTER's (TitleMoment: the lights dip and the moon flares).
-- Reduced effects: no wisps' trails, fewer leaves, no lighting dips.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local SeasonArt = require(Shared.SeasonArt)
local Seasons = require(Shared.Seasons)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local CrateTheme = require(script.Parent.Parent.Crates.CrateTheme)

local SeasonWorldController = {}

local player = Players.LocalPlayer
local season = Seasons.CurrentSeason()
local colors = CrateTheme.Colors(season)

local LOBBY_REACH = 600 -- the camera is at the lobby (the arenas are 1400 away)
local PILE_TOP = Vector3.new(0, 14, 0)
local MOON_AT = Vector3.new(380, 205, -1000)
local MOON_RADIUS = 62
local WISPS = 5
local LEAF = "rbxasset://textures/particles/sparkles_main.dds"

type Wisp = { Part: BasePart, Phase: number, Target: Vector3?, Until: number, Blend: number }
type Crow = {
	Model: Model,
	Perch: CFrame,
	Wings: { { Part: BasePart, Base: CFrame, Side: number } },
	Flying: number?,
	Away: Vector3,
	Next: number,
}
type Heap = {
	Model: Model,
	Base: CFrame,
	Radius: number,
	Emitter: ParticleEmitter,
	Cooldown: number,
	Inside: { [Model]: boolean },
	Squash: number,
}

local folder: Folder? = nil
local moon: Model? = nil
local moonFlare = 0
local wisps: { Wisp } = {}
local crows: { [Model]: Crow } = {}
local heaps: { [Model]: Heap } = {}
local look: ColorCorrectionEffect? = nil
local atLobby = true

local function localFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "SeasonLocal"
	made.Parent = workspace
	folder = made
	return made
end

local function decor(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- The moon ----------------------------------------------------------------------------------------

local function buildMoon()
	local model = Instance.new("Model")
	model.Name = "HarvestMoon"
	local facing = (Vector3.zero - MOON_AT).Unit
	decor({
		Name = "Moon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * MOON_RADIUS * 2,
		Position = MOON_AT,
		Color = Color3.fromRGB(255, 196, 112),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	-- Its seas: a few darker patches on the side facing the lobby.
	local rng = Random.new(2)
	for _ = 1, 8 do
		local side = Vector3.new(rng:NextNumber(-0.7, 0.7), rng:NextNumber(-0.6, 0.6), 0)
		local right = facing:Cross(Vector3.yAxis).Unit
		local up = right:Cross(facing).Unit
		local offset = (right * side.X + up * side.Y) * MOON_RADIUS * 0.85
		local depth = math.sqrt(math.max(0, 1 - (offset.Magnitude / MOON_RADIUS) ^ 2)) * MOON_RADIUS
		decor({
			Name = "Sea",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * MOON_RADIUS * rng:NextNumber(0.18, 0.4),
			Position = MOON_AT + offset + facing * (depth - MOON_RADIUS * 0.06),
			Color = Color3.fromRGB(236, 150, 76),
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end
	-- A soft halo round it.
	decor({
		Name = "Halo",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * MOON_RADIUS * 2.7,
		Position = MOON_AT - facing * MOON_RADIUS * 0.5,
		Color = Color3.fromRGB(255, 150, 80),
		Material = Enum.Material.Neon,
		Transparency = 0.93,
		Parent = model,
	})
	model.Parent = localFolder()
	moon = model
end

-- The lobby's light: the season's warm grade, while the camera is at the lobby and no event has its
-- own look on.
local function setLook(on: boolean)
	if on and not look then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "PP_SeasonLook"
		effect.TintColor = Color3.fromRGB(255, 240, 224)
		effect.Saturation = 0.05
		effect.Contrast = 0.04
		effect.Parent = Lighting
		look = effect
	elseif not on and look then
		look:Destroy()
		look = nil
	end
end

-- Wisps -------------------------------------------------------------------------------------------

local function buildWisps()
	for index = 1, WISPS do
		local part = decor({
			Name = "Wisp",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.7,
			Color = CrateTheme.rgb(season.Colors.Wisp),
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			Position = PILE_TOP,
			Parent = localFolder(),
		})
		local light = Instance.new("PointLight")
		light.Color = part.Color
		light.Range = 8
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = part
		local trail = Instance.new("ParticleEmitter")
		trail.Name = "Trail"
		trail.Texture = LEAF
		trail.Color = ColorSequence.new(part.Color)
		trail.LightEmission = 1
		trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Lifetime = NumberRange.new(0.6, 1)
		trail.Speed = NumberRange.new(0.2, 0.6)
		trail.Rate = 14
		trail.Parent = part
		table.insert(wisps, { Part = part, Phase = index / WISPS * math.pi * 2, Target = nil, Until = 0, Blend = 0 })
	end
end

local function stepWisps(now: number, dt: number)
	local reduced = State.ReducedEffects()
	for index, wisp in wisps do
		local a = now * 0.4 + wisp.Phase
		local r = 5 + math.sin(now * 0.7 + index) * 1.4
		local home = PILE_TOP + Vector3.new(math.cos(a) * r, math.sin(now * 1.1 + index * 1.7) * 1.6, math.sin(a) * r)
		local going = wisp.Target ~= nil and now < wisp.Until
		wisp.Blend = math.clamp(wisp.Blend + (if going then dt / 1.1 else -dt / 1.4), 0, 1)
		local position = home
		if wisp.Target and wisp.Blend > 0 then
			local b = now * 2.2 + wisp.Phase
			local around = wisp.Target
				+ Vector3.new(math.cos(b) * 3, 1.5 + math.sin(now * 3 + index) * 0.6, math.sin(b) * 3)
			local k = wisp.Blend * wisp.Blend * (3 - 2 * wisp.Blend)
			position = home:Lerp(around, k)
		elseif wisp.Blend <= 0 then
			wisp.Target = nil
		end
		wisp.Part.Position = position
		local trail = wisp.Part:FindFirstChild("Trail")
		if trail and trail:IsA("ParticleEmitter") then
			trail.Enabled = not reduced and atLobby
		end
	end
end

-- Crows -------------------------------------------------------------------------------------------

local function trackCrow(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local perch = model:GetAttribute("PP_Perch")
	local base = if typeof(perch) == "CFrame" then perch else model:GetPivot()
	local wings = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and string.sub(part.Name, 1, 4) == "Wing" then
			local side = if string.sub(part.Name, 5, 5) == "L" then 1 else -1
			table.insert(wings, { Part = part, Base = base:ToObjectSpace(part.CFrame), Side = side })
		end
	end
	local outward = Vector3.new(base.Position.X, 0, base.Position.Z)
	local away = if outward.Magnitude > 1 then outward.Unit else Vector3.new(1, 0, 0)
	crows[model] = {
		Model = model,
		Perch = base,
		Wings = wings,
		Flying = nil,
		Away = away,
		Next = os.clock() + math.random() * 6,
	}
end

local function poseCrow(crow: Crow, frame: CFrame, flap: number)
	crow.Model:PivotTo(frame)
	for _, wing in crow.Wings do
		-- Each wing swings about the body's middle, along its length.
		local hinge = frame * CFrame.new(wing.Side * 0.08, 0.1, 0)
		local swing = CFrame.Angles(0, 0, wing.Side * flap)
		wing.Part.CFrame = hinge * swing * hinge:ToObjectSpace(frame * wing.Base)
	end
end

local function stepCrows(now: number)
	for model, crow in crows do
		if not model.Parent then
			crows[model] = nil
			continue
		end
		local flying = crow.Flying
		if flying then
			local t = now - flying
			local fly = 6
			if t < fly then
				-- Up and away across the sky, wings beating fast.
				local k = t / fly
				local rise = math.sin(math.min(k, 0.5) * math.pi) * 40 + k * 60
				local position = crow.Perch.Position + crow.Away * (k * 260) + Vector3.new(0, rise, 0)
				local ahead = crow.Away + Vector3.new(0, 0.3, 0)
				poseCrow(crow, CFrame.lookAt(position, position + ahead), math.sin(now * 22) * 0.9)
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = math.clamp((k - 0.75) / 0.25, 0, 1)
					end
				end
			elseif t < fly + 8 then
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = 1
					end
				end
			else
				-- Back on the perch, settling in.
				crow.Flying = nil
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = 0
					end
				end
				crow.Next = now + 1
			end
			continue
		end
		-- On the perch: now and then it turns its head about and ruffles its wings.
		if now >= crow.Next then
			crow.Next = now + 3 + math.random() * 7
			crow.Model:SetAttribute("PP_Look", (math.random() - 0.5) * 1.2)
			crow.Model:SetAttribute("PP_Ruffle", now)
		end
		local turn = crow.Model:GetAttribute("PP_Look") or 0
		local ruffle = now - (crow.Model:GetAttribute("PP_Ruffle") or -10)
		local flap = if ruffle < 0.6 then math.sin(ruffle * 30) * 0.5 * (1 - ruffle / 0.6) else 0
		local hop = if ruffle < 0.3 then math.sin(ruffle / 0.3 * math.pi) * 0.25 else 0
		poseCrow(crow, crow.Perch * CFrame.new(0, hop, 0) * CFrame.Angles(0, turn, 0), flap)
	end
end

-- Leaf heaps ----------------------------------------------------------------------------------------

local function trackHeap(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local holder = decor({
		Name = "HeapBurst",
		Size = Vector3.one * 0.2,
		Transparency = 1,
		CFrame = model:GetPivot() * CFrame.new(0, 1.2, 0),
		Parent = localFolder(),
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = if SeasonArt.Leaves ~= "" then SeasonArt.Leaves else LEAF
	if SeasonArt.Leaves ~= "" then
		emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
		emitter.FlipbookMode = Enum.ParticleFlipbookMode.Random
	end
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(214, 72, 38)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(238, 120, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(246, 168, 48)),
	})
	emitter.Size = NumberSequence.new(0.6)
	emitter.Lifetime = NumberRange.new(1.6, 2.6)
	emitter.Speed = NumberRange.new(12, 20)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Acceleration = Vector3.new(0, -12, 0)
	emitter.Drag = 1.8
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-240, 240)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Rate = 0
	emitter.Parent = holder
	local radius = model:GetAttribute("PP_HeapRadius")
	heaps[model] = {
		Model = model,
		Base = model:GetPivot(),
		Radius = if type(radius) == "number" then radius else 3.5,
		Emitter = emitter,
		Cooldown = 0,
		Inside = {},
		Squash = -10,
	}
end

local lastHeapCheck = 0
local function stepHeaps(now: number)
	for model, heap in heaps do
		-- The heap squashes down and springs back after a burst.
		local s = now - heap.Squash
		if s < 1.2 then
			local dip = math.sin(math.min(s / 0.15, 1) * math.pi / 2) * math.exp(-s * 3) * 0.7
			model:PivotTo(heap.Base * CFrame.new(0, -dip, 0))
		end
	end
	if now - lastHeapCheck < 1 / 15 then
		return
	end
	lastHeapCheck = now
	local camera = workspace.CurrentCamera
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart") and character) then
			continue
		end
		if camera and (camera.CFrame.Position - root.Position).Magnitude > 200 then
			continue
		end
		for _, heap in heaps do
			local offset = root.Position - heap.Base.Position
			local inside = Vector3.new(offset.X, 0, offset.Z).Magnitude < heap.Radius and offset.Y < 4.2
			local was = heap.Inside[character] == true
			heap.Inside[character] = inside or nil
			if inside and not was and now >= heap.Cooldown then
				heap.Cooldown = now + 0.8
				heap.Squash = now
				local falling = root.AssemblyLinearVelocity.Y < -6
				heap.Emitter:Emit(if State.ReducedEffects() then 12 elseif falling then 60 else 30)
			end
		end
	end
end

-- The altars and the pile ---------------------------------------------------------------------------

local function watchAltar(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local function refresh()
		local busy = (model:GetAttribute("PP_AltarBusy") or 0) ~= 0
		local key = model:FindFirstChild("FloatingKey")
		if key then
			for _, part in key:GetDescendants() do
				if part:IsA("BasePart") then
					part.LocalTransparencyModifier = if busy then 1 else 0
				end
			end
		end
	end
	model:GetAttributeChangedSignal("PP_AltarBusy"):Connect(refresh)
	refresh()
end

local function pileLight(): PointLight?
	for _, pile in CollectionService:GetTagged("PP_CratePile") do
		local glow = pile:FindFirstChild("PileGlow", true)
		local light = glow and glow:FindFirstChildOfClass("PointLight")
		if light then
			return light
		end
	end
	return nil
end

-- The board ------------------------------------------------------------------------------------------

local boards: { { Gui: SurfaceGui, Rows: Frame, Footer: TextLabel } } = {}

local function drawBoards()
	local data = GameState.GetJSON("CrateBoard")
	local rows = if type(data) == "table" and type(data.Top) == "table" then data.Top else {}
	local firsts = if type(data) == "table" and type(data.Firsts) == "table" then data.Firsts else {}
	local title = firsts[season.Title]
	for _, board in boards do
		for _, child in board.Rows:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if #rows == 0 then
			UIKit.Label({
				Text = "Open a crate to get on the board!",
				Font = Theme.Fonts.Display,
				TextSize = 34,
				TextColor3 = Theme.Colors.TextDim,
				Size = UDim2.new(1, 0, 0, 80),
				Parent = board.Rows,
			})
		end
		for index, row in rows do
			if index > 10 then
				break
			end
			local line = UIKit.new("Frame", {
				BackgroundColor3 = if index % 2 == 0 then colors.Panel else colors.Deep,
				BackgroundTransparency = 0.2,
				Size = UDim2.new(1, 0, 0, 42),
				LayoutOrder = index,
				Parent = board.Rows,
				Children = { UIKit.Corner(10) },
			})
			UIKit.Label({
				Text = `{({ "🥇", "🥈", "🥉" })[index] or `{index}.`}  {row.Name}`,
				Font = Theme.Fonts.Display,
				TextSize = 28,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(1, -150, 1, 0),
				Parent = line,
				Children = { UIKit.TextStroke(0.4) },
			})
			UIKit.Label({
				Text = `📦 {UIKit.FormatNumber(row.Opened or 0)}`,
				Font = Theme.Fonts.Display,
				TextSize = 28,
				TextColor3 = colors.Gold,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 0),
				Size = UDim2.new(0, 140, 1, 0),
				Parent = line,
			})
		end
		board.Footer.Text = if type(title) == "table"
			then `👑 FIRST {string.upper(CrateTheme.NameOf(season.Title))}: {title.Name}`
			else `👑 {string.upper(CrateTheme.NameOf(season.Title))}: NOT FOUND YET!`
	end
end

local function bindBoard(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = UIKit.new("SurfaceGui", {
			Name = "TopUnboxers",
			Adornee = part,
			Face = face,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 50,
			LightInfluence = 0,
			Brightness = 1.4,
			MaxDistance = 160,
			ResetOnSpawn = false,
			Parent = player:WaitForChild("PlayerGui"),
		})
		local root = UIKit.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = colors.Deep,
			Parent = gui,
			Children = { UIKit.Gradient(colors.Panel, colors.Deep), UIKit.Padding(18) },
		})
		UIKit.Label({
			Text = "TOP UNBOXERS",
			Font = Enum.Font.GrenzeGotisch,
			TextSize = 66,
			TextWrapped = false,
			Size = UDim2.new(1, 0, 0, 74),
			Parent = root,
			Children = {
				UIKit.new("UIGradient", { Color = ColorSequence.new(colors.Gold, colors.Main), Rotation = 90 }),
				UIKit.new("UIStroke", { Color = Color3.fromRGB(70, 20, 10), Thickness = 3 }),
			},
		})
		UIKit.Label({
			Text = `{season.Name} · CRATES OPENED`,
			Font = Theme.Fonts.Display,
			TextSize = 26,
			TextColor3 = colors.Glow,
			Position = UDim2.fromOffset(0, 74),
			Size = UDim2.new(1, 0, 0, 32),
			Parent = root,
		})
		local list = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 116),
			Size = UDim2.new(1, 0, 1, -116 - 56),
			Parent = root,
			Children = { UIKit.List(Enum.FillDirection.Vertical, 6) },
		})
		local footer = UIKit.Label({
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = 26,
			TextColor3 = colors.Gold,
			TextScaled = true,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 44),
			Parent = root,
			Children = { UIKit.TextStroke(0.3), UIKit.new("UITextSizeConstraint", { MaxTextSize = 28 }) },
		})
		table.insert(boards, { Gui = gui, Rows = list, Footer = footer })
	end
	drawBoards()
end

-- The season's moments ---------------------------------------------------------------------------------

-- The welcome: every tree (and the lawn) goes back to its summer green, then turns orange over
-- `seconds`, tree by tree.
function SeasonWorldController.TurnTrees(seconds: number)
	local rng = Random.new()
	for _, model in CollectionService:GetTagged("PP_AutumnTree") do
		local parts = {}
		if model:IsA("BasePart") then
			table.insert(parts, model)
		else
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					table.insert(parts, part)
				end
			end
		end
		local delay = rng:NextNumber(0, seconds * 0.55)
		for _, part in parts do
			local spring = part:GetAttribute("PP_SpringColor")
			if typeof(spring) == "Color3" then
				local autumn = part.Color
				part.Color = spring
				task.delay(delay, function()
					TweenService:Create(part, TweenInfo.new(seconds * 0.45, Enum.EasingStyle.Sine), { Color = autumn })
						:Play()
				end)
			end
		end
	end
	-- A gust of leaves over the plaza as they turn.
	local holder = decor({
		Name = "Gust",
		Size = Vector3.new(90, 1, 90),
		Transparency = 1,
		CFrame = CFrame.new(0, 30, 0),
		Parent = localFolder(),
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = if SeasonArt.Leaves ~= "" then SeasonArt.Leaves else LEAF
	if SeasonArt.Leaves ~= "" then
		emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
		emitter.FlipbookMode = Enum.ParticleFlipbookMode.Random
	end
	emitter.Color = ColorSequence.new(Color3.fromRGB(238, 120, 40), Color3.fromRGB(246, 168, 48))
	emitter.Size = NumberSequence.new(0.8)
	emitter.Lifetime = NumberRange.new(5, 7)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.Acceleration = Vector3.new(4, -2, 1)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Rate = if State.ReducedEffects() then 15 else 60
	emitter.Parent = holder
	task.delay(seconds, function()
		emitter.Enabled = false
		task.delay(8, function()
			holder:Destroy()
		end)
	end)
end

-- A pet or the title came out: the crows take off.
function SeasonWorldController.ScareCrows()
	local now = os.clock()
	for _, crow in crows do
		if not crow.Flying then
			crow.Flying = now + math.random() * 0.4
		end
	end
end

-- THE HARVESTER came out here: the lights dip, the moon flares.
function SeasonWorldController.TitleMoment()
	moonFlare = os.clock()
	if State.ReducedEffects() or not atLobby then
		return
	end
	local before = Lighting.ExposureCompensation
	TweenService:Create(Lighting, TweenInfo.new(0.4), { ExposureCompensation = before - 0.8 }):Play()
	task.delay(1.8, function()
		TweenService:Create(Lighting, TweenInfo.new(1.2), { ExposureCompensation = before }):Play()
	end)
end

-- A show began: the wisps nearest it drift over and circle it while it plays.
function SeasonWorldController.ShowStarted(show: { [string]: any }, position: Vector3)
	if (show.Altar or 0) <= 0 then
		return
	end
	local sorted = table.clone(wisps)
	table.sort(sorted, function(a, b)
		return (a.Part.Position - position).Magnitude < (b.Part.Position - position).Magnitude
	end)
	local untilTime = os.clock() + (tonumber(show.Duration) or 5.2) + 0.6
	for index = 1, math.min(3, #sorted) do
		sorted[index].Target = position + Vector3.new(0, 4, 0)
		sorted[index].Until = untilTime
	end
end

-- The prize showed: the pile's glow flares in its tier's colour.
function SeasonWorldController.ShowLanded(_show: { [string]: any }, _position: Vector3, color: Color3)
	local light = pileLight()
	if not light then
		return
	end
	local color0 = light:GetAttribute("PP_Color") or light.Color
	local bright0 = light:GetAttribute("PP_Brightness") or light.Brightness
	light:SetAttribute("PP_Color", color0)
	light:SetAttribute("PP_Brightness", bright0)
	light.Color = color
	light.Brightness = 4
	TweenService:Create(light, TweenInfo.new(2.2), { Color = color0, Brightness = bright0 }):Play()
end

function SeasonWorldController.Start(_context)
	if not season.Props then
		return
	end
	buildMoon()
	buildWisps()
	local function watch(tag: string, callback: (Instance) -> ())
		for _, instance in CollectionService:GetTagged(tag) do
			task.spawn(callback, instance)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(callback)
	end
	watch("PP_Crow", trackCrow)
	watch("PP_LeafHeap", trackHeap)
	watch("PP_CrateAltar", watchAltar)
	watch("PP_CrateBoard", function(part)
		task.spawn(bindBoard, part)
	end)
	CollectionService:GetInstanceRemovedSignal("PP_LeafHeap"):Connect(function(model)
		heaps[model :: Model] = nil
	end)
	GameState.Changed("CrateBoard", drawBoards)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		local camera = workspace.CurrentCamera
		elapsed += dt
		if elapsed > 0.25 then
			elapsed = 0
			atLobby = camera ~= nil and camera.CFrame.Position.Magnitude < LOBBY_REACH
			setLook(atLobby and Lighting:FindFirstChild("PP_EventLook") == nil)
			local shown = moon
			local home = if atLobby then localFolder() else nil
			if shown and shown.Parent ~= home then
				shown.Parent = home
			end
		end
		if not atLobby then
			return
		end
		stepWisps(now, dt)
		stepCrows(now)
		stepHeaps(now)
		local shown = moon
		if shown then
			-- THE HARVESTER's flare: the moon swells and brightens, then settles.
			local f = now - moonFlare
			local swell = if f < 3 then math.sin(math.min(f / 0.5, 1) * math.pi / 2) * math.exp(-f * 0.9) else 0
			local body = shown:FindFirstChild("Moon")
			if body and body:IsA("BasePart") then
				body.Size = Vector3.one * MOON_RADIUS * 2 * (1 + swell * 0.25)
				body.Color = Color3.fromRGB(255, 196, 112):Lerp(Color3.fromRGB(255, 240, 200), swell)
			end
		end
	end)
end

return SeasonWorldController

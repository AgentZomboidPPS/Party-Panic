-- Client half of Shark Bait: draws the cove's moving parts from the server's shared state and gives
-- each role its controls (owner: "I want players to be like damn. That was the best mini game I
-- have ever played.").
--   * Rafts (MG_Layout, MG_Rafts): bobbing on the swell, rocking harder and harder while they
--     WOBBLE (with a ⚠️ over them), tipping over and under the water when they FLIP (away from the
--     shark that chomped them, in a burst of spray) and bobbing back up.
--   * Sharks (MG_Sharks): a shark mesh at each shark's character (the server hides the body),
--     swimming with a tail wag, a body wiggle and a foamy wake behind the fin, and lunging up out
--     of the water with its jaws wide on every CHOMP.
--   * Coins, pearls and chests (MG_Coins): spinning and bobbing, popping up as they appear, flying
--     off a flipped raft into the water, sinking when their time is up; a treasure chest shines a
--     beam of light. A coin this player runs through pops at once (the server's own rule, see
--     Server/MiniGames/SharkBait) and comes back if the server says otherwise.
--   * Swimmers in the water wear a swim ring; the shark sees each one ringed in red (dinner).
-- HUD: the swimmers' haul against the goal, the role hint, big flashes (TIPPING! / SPLASH! /
-- CHOMPED!) and, for the shark, CHOMP (E, the button or the jump button) with its cooldown.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Teams = require(ReplicatedStorage.Shared.Teams)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SharkBait = {}

local READY, WOBBLING, FLIPPED = 0, 1, 2
-- Must match the server's kinds (index = kind number).
-- Lift: from the coin's middle (the server's position) down to the model's pivot (its bottom).
local KINDS = {
	{ Prop = "SharkBaitCoin", Value = 1, Spin = 3.4, Lift = -1, Glint = Theme.Colors.Coin },
	{ Prop = "SharkBaitPearl", Value = 3, Spin = 0.7, Lift = -0.6, Glint = Color3.fromRGB(255, 200, 230) },
	{ Prop = "SharkBaitChest", Value = 6, Spin = 0.4, Lift = -1.1, Glint = Color3.fromRGB(255, 220, 90) },
}
local POP_IN = 0.35
local SPILL_TIME = 0.55
local SINK_TIME = 1.2 -- a coin in the water sinks over its last moments
local PENDING_TIME = 0.6 -- a predicted grab the server hasn't confirmed by then comes back
local LUNGE_TIME = 0.5
local FLIP_TIME = 0.5 -- a flipping raft goes over this fast...
local RISE_TIME = 0.65 -- ...and comes back up this fast at the end of its dunk
local SHARK_CAMERA = Vector3.new(0, 2.5, 0) -- the shark's camera sits a little higher

local SPRAY_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local RING_TEXTURE = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local GLINT_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

type RaftView = {
	Index: number,
	Center: Vector3,
	Radius: number,
	Yaw: number,
	Scale: number,
	Phase: number,
	State: number,
	Since: number,
	SafeUntil: number,
	Axis: Vector3, -- the horizontal axis it tips over (away from the shark that chomped it)
	Model: Model?,
	Foam: BasePart,
	Warning: BillboardGui,
	WarningLabel: TextLabel,
}

type SharkView = {
	UserId: number,
	Model: Model,
	Pieces: { { Part: BasePart, Rel: CFrame, Kind: string } },
	JawHinge: CFrame, -- in the model's own space
	TailHinge: CFrame,
	Yaw: number,
	Last: Vector3?,
	Speed: number,
	LungeAt: number,
	Phase: number,
	Wake: ParticleEmitter?,
	WakeAnchor: BasePart,
}

type CoinView = {
	Id: number,
	Kind: number,
	Position: Vector3,
	Born: number,
	Expires: number,
	From: Vector3?,
	SpillAt: number?,
	Model: Model,
	BaseScale: number, -- the model's own scale (animations scale relative to it)
	Ring: BasePart?,
	Beam: BasePart?,
	Spin: number,
	Shown: Vector3?,
	Gone: string?, -- "Grab" | "Sink" | "Lost"
	GoneAt: number,
	GoneFrom: Vector3?,
	Taker: number?,
	Pending: number?,
	Predicted: boolean?,
	Missing: boolean?,
	Rel: Vector3?, -- this player's middle last frame (for the swept test)
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function partsOf(model: Instance): { BasePart }
	local list = {}
	if model:IsA("BasePart") then
		table.insert(list, model)
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

local function quiet(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (math.pi * 2) - math.pi
	return a + d * t
end

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function easeInOut(t: number): number
	return t * t * (3 - 2 * t)
end

-- The same swept grab test as the server (SharkBait.Swept): coins don't move, so this player's own
-- path is all that matters.
local function swept(a: Vector3, b: Vector3, coin: Vector3, reach: number, below: number, above: number): boolean
	for step = 0, 5 do
		local p = a:Lerp(b, step / 5)
		local dy = coin.Y - p.Y
		if dy >= -below and dy <= above and flatDistance(p, coin) <= reach then
			return true
		end
	end
	local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
	local length = ab:Dot(ab)
	if length > 1e-6 then
		local t = math.clamp(Vector2.new(coin.X - a.X, coin.Z - a.Z):Dot(ab) / length, 0, 1)
		local p = a:Lerp(b, t)
		local dy = coin.Y - p.Y
		if dy >= -below and dy <= above and flatDistance(p, coin) <= reach then
			return true
		end
	end
	return false
end

function SharkBait.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(250, 252, 255),
		Saturation = 0.2,
		Contrast = 0.08,
		Brightness = 0.02,
		Haze = Color3.fromRGB(190, 230, 245),
		HazeDecay = Color3.fromRGB(140, 200, 230),
		Density = 0.26,
	})
	local reduced = State.ReducedEffects()

	-- The layout arrives during the countdown.
	local layout = api:SharedJSON("Layout")
	for _ = 1, 100 do
		if type(layout) == "table" then
			break
		end
		task.wait(0.1)
		layout = api:SharedJSON("Layout")
	end
	if type(layout) ~= "table" then
		return
	end
	local origin = Vector3.new(layout.Origin[1], layout.Origin[2], layout.Origin[3])
	local deckY: number = layout.Deck
	local waterY: number = layout.Water
	local sharkY: number = layout.SharkY
	local wetY: number = layout.Wet
	local meshRadius, meshHeight = layout.RaftMesh[1], layout.RaftMesh[2]
	local wobbleTime: number = layout.Wobble
	local dunkTime: number = layout.Dunk
	local reaches = layout.Reach
	local grabBelow, grabAbove = layout.Grab[1], layout.Grab[2]

	local templates: { [string]: Instance | false } = {}
	local function loadTemplate(name: string)
		task.spawn(function()
			templates[name] = api:Template(name, 10) or false
		end)
	end
	for _, kind in KINDS do
		loadTemplate(kind.Prop)
	end
	loadTemplate("SharkBaitShark")
	loadTemplate("SharkBaitFloatie")
	loadTemplate("SharkBaitGull")
	local function copy(name: string): Instance?
		local found = templates[name]
		return if found then found:Clone() else nil
	end

	local function newPart(props: { [string]: any }): Part
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		for key, value in props do
			(part :: any)[key] = value
		end
		part.Parent = props.Parent or api.World
		return part
	end
	-- A flat disc lying on the water (cylinders run along X).
	local function disc(name: string, diameter: number, color: Color3, transparency: number): Part
		return newPart({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.08, diameter, diameter),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Transparency = transparency,
		})
	end
	local function flatAt(position: Vector3): CFrame
		return CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	end

	-- Splashes: spray thrown up and a ring spreading on the water.
	local function splash(position: Vector3, size: number)
		local at = Vector3.new(position.X, waterY + 0.1, position.Z)
		local anchor = newPart({ Name = "Splash", Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(at) })
		local spray = Instance.new("ParticleEmitter")
		spray.Texture = SPRAY_TEXTURE
		spray.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 230, 255))
		spray.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8 * size),
			NumberSequenceKeypoint.new(1, 2.4 * size),
		})
		spray.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.6, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		spray.Lifetime = NumberRange.new(0.6, 1.1)
		spray.Speed = NumberRange.new(14 * size, 26 * size)
		spray.SpreadAngle = Vector2.new(28, 28)
		spray.Acceleration = Vector3.new(0, -70, 0)
		spray.EmissionDirection = Enum.NormalId.Top
		spray.Rate = 0
		spray.Parent = anchor
		spray:Emit(if reduced then math.floor(8 * size) else math.floor(22 * size))
		local ring = Instance.new("ParticleEmitter")
		ring.Texture = RING_TEXTURE
		ring.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		ring.Color = ColorSequence.new(Color3.fromRGB(240, 252, 255))
		ring.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.5 * size),
			NumberSequenceKeypoint.new(1, 9 * size),
		})
		ring.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		ring.Lifetime = NumberRange.new(0.9, 0.9)
		ring.Speed = NumberRange.new(0.01, 0.01)
		ring.EmissionDirection = Enum.NormalId.Top
		ring.Rate = 0
		ring.Parent = anchor
		ring:Emit(if reduced then 1 else 2)
		task.delay(1.6, function()
			anchor:Destroy()
		end)
	end

	-- Floating text that rises and fades ("+3", "CHOMP!").
	local function floatText(position: Vector3, text: string, color: Color3, size: number?)
		local anchor =
			newPart({ Name = "FloatText", Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(position) })
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(180, 60)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 180
		gui.LightInfluence = 0
		gui.Parent = anchor
		UIKit.Label({
			Text = text,
			Font = Theme.Fonts.Display,
			TextSize = size or 34,
			TextColor3 = color,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0.1) },
		})
		local start = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = os.clock() - start
			if t > 1.1 or not anchor.Parent then
				connection:Disconnect()
				anchor:Destroy()
				return
			end
			anchor.CFrame = CFrame.new(position + Vector3.new(0, 2 + t * 4, 0))
		end)
		api:Track(connection)
	end

	local isShark = false

	-- HUD -----------------------------------------------------------------------------------------------

	local hud = api:TopHud()
	local swimmerColor = Teams.Colors.Swimmers or Theme.Colors.Coin
	local panel = UIKit.Panel({
		Name = "Haul",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY()),
		Size = UDim2.fromOffset(380, 58),
		CornerRadius = 20,
		Parent = hud,
	}, Color3.fromRGB(30, 150, 200), Color3.fromRGB(14, 84, 140))
	UIKit.Coin({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(34, 34),
		Parent = panel,
	})
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 58, 0.5, 0),
		Size = UDim2.new(1, -112, 0, 30),
		BackgroundColor3 = Color3.fromRGB(10, 50, 90),
		BackgroundTransparency = 0.2,
		Parent = panel,
		Children = { UIKit.Round(), UIKit.Stroke(Color3.new(1, 1, 1), 2, 0.5) },
	})
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = bar,
		Children = { UIKit.Round(), UIKit.Gradient(Color3.fromRGB(255, 236, 120), swimmerColor) },
	})
	local haulLabel = UIKit.Label({
		Name = "Count",
		Text = "0 / 0",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = bar,
		Children = { UIKit.TextStroke(0.15) },
	})
	local roleIcon = UIKit.Label({
		Name = "Role",
		Text = "🏊",
		TextSize = 32,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		Parent = panel,
	})
	local shownHaul = 0
	local function refreshHaul()
		local haul = api:Shared("Haul") or 0
		local goal = math.max(1, api:Shared("Goal") or 1)
		haulLabel.Text = `{haul} / {goal}`
		if haul > shownHaul then
			UIKit.PopIn(haulLabel, 0.25)
		end
		shownHaul = haul
		UIKit.Tween(fill, 0.25, { Size = UDim2.fromScale(math.clamp(haul / goal, 0, 1), 1) })
	end
	api:OnShared("Haul", refreshHaul)
	api:OnShared("Goal", refreshHaul)
	refreshHaul()
	local rushStroke = UIKit.Stroke(Theme.Colors.Yellow, 4, 1)
	rushStroke.Parent = panel

	-- The role hint, and big flashes in the same spot ("TIPPING!", "CHOMPED!").
	local hint = UIKit.Label({
		Name = "RoleHint",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY() + 66),
		Size = UDim2.fromOffset(420, 66),
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.2) },
	})
	local flash = UIKit.Label({
		Name = "Flash",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 50,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY() + 66),
		Size = UDim2.fromOffset(440, 62),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.05), UIKit.new("UITextSizeConstraint", { MaxTextSize = 50 }) },
	})
	-- Swallowed: a red belly tint over the screen and a countdown while this player's camera rides
	-- along behind the shark that ate them.
	local belly = UIKit.new("Frame", {
		Name = "Belly",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(120, 10, 30),
		BackgroundTransparency = 0.35,
		Visible = false,
		Parent = api.Gui,
		Children = {
			UIKit.new("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.3, 0.75),
					NumberSequenceKeypoint.new(0.7, 0.75),
					NumberSequenceKeypoint.new(1, 0),
				}),
			}),
		},
	})
	local bellyLabel = UIKit.Label({
		Name = "Gulp",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 44,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(460, 110),
		Parent = belly,
		Children = { UIKit.TextStroke(0.1), UIKit.new("UITextSizeConstraint", { MaxTextSize = 44 }) },
	})
	UIKit.AutoScale(bellyLabel)

	local flashUntil = 0
	local function showFlash(text: string, color: Color3, seconds: number)
		flash.Text = text
		flash.TextColor3 = color
		flash.Visible = true
		flashUntil = os.clock() + seconds
		hint.Visible = false -- same spot: the flash takes over
		UIKit.PopIn(flash, 0.25)
	end

	-- Rafts ---------------------------------------------------------------------------------------

	local rafts: { RaftView } = {}
	for index, entry in layout.Rafts do
		local center = Vector3.new(entry.X, deckY, entry.Z)
		local foam = disc("RaftFoam", entry.R * 2 + 1.4, Color3.fromRGB(235, 250, 255), 0.45)
		foam.CFrame = flatAt(Vector3.new(center.X, waterY + 0.12, center.Z))
		local warning = Instance.new("BillboardGui")
		warning.Name = "RaftWarning"
		warning.Size = UDim2.fromOffset(110, 110)
		warning.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
		warning.AlwaysOnTop = true
		warning.MaxDistance = 260
		warning.LightInfluence = 0
		warning.Enabled = false
		warning.Adornee = foam
		warning.Parent = foam
		local label = UIKit.Label({
			Text = "⚠️",
			TextSize = 80,
			TextScaled = true,
			Font = Theme.Fonts.Display,
			Size = UDim2.fromScale(1, 1),
			Parent = warning,
		})
		local angle = math.random() * math.pi * 2
		rafts[index] = {
			Index = index,
			Center = center,
			Radius = entry.R,
			Yaw = entry.Yaw,
			Scale = entry.R / meshRadius,
			Phase = index * 1.7,
			State = READY,
			Since = 0,
			SafeUntil = 0,
			Axis = Vector3.new(math.cos(angle), 0, math.sin(angle)),
			Model = nil,
			Foam = foam,
			Warning = warning,
			WarningLabel = label,
		}
	end
	task.spawn(function()
		for _, raft in rafts do
			local model = api:Template("SharkBaitRaft", 10) :: Model?
			if not model then
				return
			end
			for _, part in partsOf(model) do
				quiet(part)
			end
			model:ScaleTo(model:GetScale() * raft.Scale)
			model.Parent = api.World
			raft.Model = model
		end
	end)

	-- Who's on which raft (this player), for the TIPPING warning.
	local function myRaft(): RaftView?
		local _, _, root = api:Character()
		if not root or root.Position.Y < wetY then
			return nil
		end
		for _, raft in rafts do
			if flatDistance(root.Position, raft.Center) <= raft.Radius + 0.6 then
				return raft
			end
		end
		return nil
	end

	local function refreshRafts()
		local list = api:SharedJSON("Rafts")
		if type(list) ~= "table" then
			return
		end
		for index, entry in list do
			local raft = rafts[index]
			if not raft then
				continue
			end
			local state, since, safe = entry[1], entry[2], entry[3]
			local before = raft.State
			raft.State, raft.Since, raft.SafeUntil = state, since, safe
			if before == state then
				continue
			end
			if state == WOBBLING then
				raft.Warning.Enabled = true
				if not isShark and myRaft() == raft then
					showFlash("⚠️ TIPPING! JUMP! ⚠️", Theme.Colors.Orange, 1.4)
					api:Sound("HazardWarning")
				end
			elseif state == FLIPPED then
				raft.Warning.Enabled = false
				splash(raft.Center, 1.6)
				api:Sound("Splash")
			elseif state == READY and before == FLIPPED then
				raft.Warning.Enabled = false
				splash(raft.Center, 1.1)
			end
		end
	end
	api:OnShared("Rafts", refreshRafts)
	refreshRafts()

	-- A raft's pose: bobbing on the swell, rocking while it wobbles, over and under while it's
	-- flipped, and back up at the end of its dunk. The model's pivot is its bottom; its deck top is
	-- meshHeight * scale above that.
	local function raftPose(raft: RaftView, now: number): CFrame
		local bob = math.sin(now * 1.3 + raft.Phase) * 0.05
		local swell =
			CFrame.Angles(math.sin(now * 0.9 + raft.Phase * 2) * 0.008, 0, math.cos(now * 0.7 + raft.Phase) * 0.008)
		local tip = CFrame.identity
		local drop = 0
		if raft.State == WOBBLING then
			local s = now - raft.Since
			local k = math.clamp(s / wobbleTime, 0, 1)
			local wave = math.sin(s * (15 + 12 * k))
			tip = CFrame.fromAxisAngle(raft.Axis, wave * math.rad(2.5 + 8 * k))
				* CFrame.fromAxisAngle(raft.Axis:Cross(Vector3.yAxis), math.sin(s * 11) * math.rad(1.5 + 3 * k))
			drop = -0.25 * k
		elseif raft.State == FLIPPED then
			local s = now - raft.Since
			local over = easeOut(math.clamp(s / FLIP_TIME, 0, 1))
			local back = easeInOut(math.clamp((s - (dunkTime - RISE_TIME)) / RISE_TIME, 0, 1))
			local k = over * (1 - back)
			tip = CFrame.fromAxisAngle(raft.Axis, math.rad(168) * k)
			drop = -3.4 * k + math.sin(now * 2 + raft.Phase) * 0.15 * k
		end
		local deck = CFrame.new(raft.Center.X, deckY + bob + drop, raft.Center.Z)
		return deck * tip * swell * CFrame.Angles(0, raft.Yaw, 0) * CFrame.new(0, -meshHeight * raft.Scale, 0)
	end

	-- Sharks --------------------------------------------------------------------------------------

	local sharks: { [number]: SharkView } = {}
	local sharkIds: { number } = {}
	local function buildShark(userId: number): SharkView?
		local model = copy("SharkBaitShark") :: Model?
		if not model then
			return nil
		end
		local pivot = model:GetPivot()
		local pieces = {}
		local jawBox: { BasePart } = {}
		local tailBox: { BasePart } = {}
		for _, part in partsOf(model) do
			quiet(part)
			part.CastShadow = true
			local kind = if part.Name == "Jaw" or part.Name == "JawTeeth"
				then "Jaw"
				elseif part.Name == "Tail" then "Tail"
				else "Body"
			table.insert(pieces, { Part = part, Rel = pivot:ToObjectSpace(part.CFrame), Kind = kind })
			if part.Name == "Jaw" then
				table.insert(jawBox, part)
			elseif part.Name == "Tail" then
				table.insert(tailBox, part)
			end
		end
		-- Hinges: the jaw turns about the back top edge of the lower jaw, the tail about its front end
		-- (measured in the model's own space: an imported mesh's parts are turned half a turn).
		local function box(part: BasePart): (Vector3, Vector3)
			local rel = pivot:ToObjectSpace(part.CFrame)
			local half = part.Size / 2
			local extent = Vector3.zero
			for _, axis in { rel.RightVector * half.X, rel.UpVector * half.Y, rel.LookVector * half.Z } do
				extent += Vector3.new(math.abs(axis.X), math.abs(axis.Y), math.abs(axis.Z))
			end
			return rel.Position, extent
		end
		local jawHinge, tailHinge = CFrame.identity, CFrame.identity
		if jawBox[1] then
			local center, extent = box(jawBox[1])
			jawHinge = CFrame.new(center + Vector3.new(0, extent.Y * 0.35, extent.Z))
		end
		if tailBox[1] then
			local center, extent = box(tailBox[1])
			tailHinge = CFrame.new(center - Vector3.new(0, 0, extent.Z))
		end
		-- The wake: foam thrown off behind the fin as it cuts the water.
		local anchor = newPart({ Name = "SharkWake", Size = Vector3.one * 0.2, Transparency = 1 })
		local wake = Instance.new("ParticleEmitter")
		wake.Texture = SPRAY_TEXTURE
		wake.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 240, 255))
		wake.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(1, 3.2),
		})
		wake.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		wake.Lifetime = NumberRange.new(0.8, 1.4)
		wake.Speed = NumberRange.new(0.5, 1.5)
		wake.SpreadAngle = Vector2.new(60, 10)
		wake.EmissionDirection = Enum.NormalId.Top
		wake.Rate = 0
		wake.Parent = anchor
		model.Parent = api.World
		return {
			UserId = userId,
			Model = model,
			Pieces = pieces,
			JawHinge = jawHinge,
			TailHinge = tailHinge,
			Yaw = 0,
			Last = nil,
			Speed = 0,
			LungeAt = -math.huge,
			Phase = math.random() * math.pi * 2,
			Wake = wake,
			WakeAnchor = anchor,
		}
	end
	local function refreshSharks()
		local ids = api:SharedJSON("Sharks")
		if type(ids) == "table" then
			sharkIds = ids
		end
	end
	api:OnShared("Sharks", refreshSharks)
	refreshSharks()

	-- Where a shark's lunge is (0..1) `t` seconds after a chomp: out fast, back slower.
	local function lunge(t: number): number
		if t < 0 or t > LUNGE_TIME then
			return 0
		end
		if t < 0.12 then
			return easeOut(t / 0.12)
		end
		return 1 - easeInOut((t - 0.12) / (LUNGE_TIME - 0.12))
	end
	-- The jaw's opening (radians) `t` seconds after a chomp: wide, then SNAP.
	local function jaw(t: number): number
		if t < 0 or t > 0.4 then
			return 0
		end
		if t < 0.1 then
			return math.rad(36) * easeOut(t / 0.1)
		elseif t < 0.17 then
			return math.rad(36) * (1 - (t - 0.1) / 0.07) - math.rad(4) * ((t - 0.1) / 0.07)
		end
		return -math.rad(4) * (1 - (t - 0.17) / 0.23)
	end

	local function drawShark(view: SharkView, now: number, dt: number)
		local character = api:CharacterOf(view.UserId)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			view.Model.Parent = nil
			return
		end
		view.Model.Parent = api.World
		local p = root.Position
		if view.Last and dt > 0 then
			local moved = flatDistance(p, view.Last) / dt
			view.Speed = view.Speed + (math.min(moved, 40) - view.Speed) * math.min(1, dt * 6)
		end
		view.Last = p
		local look = flat(root.CFrame.LookVector)
		if look.Magnitude > 0.01 then
			local target = math.atan2(-look.X, -look.Z)
			view.Yaw = lerpAngle(view.Yaw, target, 1 - math.exp(-dt * 14))
		end
		local swim = math.clamp(view.Speed / 22, 0, 1)
		local t = now - view.LungeAt
		local out = lunge(t)
		local forward = CFrame.Angles(0, view.Yaw, 0).LookVector
		local position = Vector3.new(p.X, sharkY + math.sin(now * 2.1 + view.Phase) * 0.12 + out * 1.7, p.Z)
			+ forward * (out * 2.6)
		local wiggle = math.sin(now * 7.5 + view.Phase) * (0.025 + 0.06 * swim)
		local frame = CFrame.new(position)
			* CFrame.Angles(0, view.Yaw + wiggle, 0)
			* CFrame.Angles(out * math.rad(16), 0, math.sin(now * 2.6 + view.Phase) * 0.04)
		local open = jaw(t)
		local wag = math.sin(now * (6 + 5 * swim) + view.Phase) * (0.16 + 0.3 * swim)
		local jawTurn = view.JawHinge * CFrame.Angles(-open, 0, 0) * view.JawHinge:Inverse()
		local tailTurn = view.TailHinge * CFrame.Angles(0, wag, 0) * view.TailHinge:Inverse()
		for _, piece in view.Pieces do
			local rel = piece.Rel
			if piece.Kind == "Jaw" then
				rel = jawTurn * rel
			elseif piece.Kind == "Tail" then
				rel = tailTurn * rel
			end
			piece.Part.CFrame = frame * rel
		end
		-- The wake streams off the fin at the waterline while it swims.
		view.WakeAnchor.CFrame = CFrame.new(Vector3.new(p.X, waterY + 0.15, p.Z) - forward * 1.5)
		if view.Wake then
			view.Wake.Rate = if reduced then swim * 6 else swim * 22
		end
	end

	-- Swim rings for swimmers in the water --------------------------------------------------------------

	local gulped: { [number]: boolean } = {} -- swimmers in a shark's belly right now
	local floaties: { [number]: { Model: Model?, Prey: BasePart } } = {}
	local function drawFloaties(now: number)
		local seen = {}
		for _, participant in api:Participants() do
			local userId = participant.UserId
			local wet = participant:GetAttribute("MG_InWater") == true
				and participant:GetAttribute("PP_Alive") == true
				and participant:GetAttribute("MG_Role") == "Swimmer"
				and not gulped[userId]
			local character = if wet then participant:Character() else nil
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				continue
			end
			seen[userId] = true
			local entry = floaties[userId]
			if not entry then
				local model = copy("SharkBaitFloatie") :: Model?
				if model then
					for _, part in partsOf(model) do
						quiet(part)
					end
					model.Parent = api.World
				end
				local prey = disc("Prey", 6, Theme.Colors.Red, 0.55)
				prey.Material = Enum.Material.Neon
				entry = { Model = model, Prey = prey }
				floaties[userId] = entry
			end
			local p = root.Position
			local bob = math.sin(now * 3 + userId % 7) * 0.08
			if entry.Model then
				local yaw = math.atan2(-root.CFrame.LookVector.X, -root.CFrame.LookVector.Z)
				entry.Model:PivotTo(
					CFrame.new(p.X, waterY - 0.5 + bob, p.Z) * CFrame.Angles(0.08 * math.sin(now * 2), yaw, 0)
				)
			end
			-- The shark sees its dinner: a pulsing red ring round every swimmer in the water.
			entry.Prey.Transparency = if isShark then 0.45 + 0.2 * math.sin(now * 8) else 1
			entry.Prey.CFrame = flatAt(Vector3.new(p.X, waterY + 0.18, p.Z))
		end
		for userId, entry in floaties do
			if not seen[userId] then
				if entry.Model then
					entry.Model:Destroy()
				end
				entry.Prey:Destroy()
				floaties[userId] = nil
			end
		end
	end

	-- Coins -------------------------------------------------------------------------------------------

	local coins: { [number]: CoinView } = {}
	local function newCoinModel(kind: number): Model
		local model = copy(KINDS[kind].Prop) :: Model?
		if not model then
			model = Instance.new("Model")
			local part = Instance.new("Part")
			part.Name = "Coin"
			part.Shape = Enum.PartType.Cylinder
			part.Size = Vector3.new(0.3, 2, 2)
			part.Color = Theme.Colors.Coin
			part.Material = Enum.Material.Metal
			part.Parent = model
		end
		local built = model :: Model
		for _, part in partsOf(built) do
			quiet(part)
			part.CastShadow = false
		end
		local primary = built.PrimaryPart or partsOf(built)[1]
		if primary and not reduced then
			local twinkle = Instance.new("ParticleEmitter")
			twinkle.Texture = GLINT_TEXTURE
			twinkle.Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(KINDS[kind].Glint, 0.6))
			twinkle.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.4, if kind == 3 then 0.9 else 0.5),
				NumberSequenceKeypoint.new(1, 0),
			})
			twinkle.Rate = if kind == 1 then 1.5 else 4
			twinkle.Lifetime = NumberRange.new(0.4, 0.8)
			twinkle.Speed = NumberRange.new(0.3, 0.9)
			twinkle.SpreadAngle = Vector2.new(180, 180)
			twinkle.LightEmission = 1
			twinkle.Parent = primary
			CollectionService:AddTag(twinkle, "PP_Ambient")
		end
		if primary and kind == 3 then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 210, 90)
			light.Range = 16
			light.Brightness = 2.5
			light.Parent = primary
		end
		built.Parent = api.World
		return built
	end

	local function refreshCoins()
		local list = api:SharedJSON("Coins")
		if type(list) ~= "table" then
			return
		end
		local seen = {}
		local now = api:Now()
		for _, entry in list do
			local id = entry[1]
			seen[id] = true
			local coin = coins[id]
			local position = Vector3.new(entry[3], entry[4], entry[5])
			if coin then
				coin.Position = position
				coin.Born, coin.Expires = entry[6], entry[7]
				if entry[11] then
					coin.From = Vector3.new(entry[8], entry[9], entry[10])
					coin.SpillAt = entry[11]
				end
			elseif KINDS[entry[2]] then
				local kind = entry[2]
				-- A ring of foam marks it once it's in the water (a deck coin can be spilled in later).
				local ring = disc("CoinRing", if kind == 3 then 5 else 3.2, Color3.fromRGB(255, 255, 255), 1)
				local beam = nil
				if kind == 3 then
					beam = newPart({
						Name = "ChestBeam",
						Shape = Enum.PartType.Cylinder,
						Size = Vector3.new(60, 2.2, 2.2),
						Color = Color3.fromRGB(255, 220, 110),
						Material = Enum.Material.Neon,
						Transparency = 0.72,
						CFrame = CFrame.new(position + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.rad(90)),
					})
				end
				local model = newCoinModel(kind)
				coins[id] = {
					Id = id,
					Kind = kind,
					Position = position,
					Born = entry[6],
					Expires = entry[7],
					From = if entry[11] then Vector3.new(entry[8], entry[9], entry[10]) else nil,
					SpillAt = entry[11],
					Model = model,
					BaseScale = model:GetScale(),
					Ring = ring,
					Beam = beam,
					Spin = math.random() * math.pi * 2,
					GoneAt = 0,
				}
			end
		end
		for id, coin in coins do
			if not seen[id] and not coin.Gone then
				if coin.Pending then
					coin.Missing = true -- the Grab event says who got it (or it times out)
				else
					coin.Gone = "Lost"
					coin.GoneAt = now
					coin.GoneFrom = coin.Shown
				end
			end
		end
	end
	api:OnShared("Coins", refreshCoins)
	refreshCoins()

	local function removeCoin(id: number)
		local coin = coins[id]
		if not coin then
			return
		end
		coin.Model:Destroy()
		if coin.Ring then
			coin.Ring:Destroy()
		end
		if coin.Beam then
			coin.Beam:Destroy()
		end
		coins[id] = nil
	end

	-- Shark controls: CHOMP (the button, E, or the jump button, which a shark has no other use for).
	local chompButton = nil
	local lastPress = 0
	local punch = 0 -- the shark's camera lurches forward on a chomp (field of view)
	local camera = workspace.CurrentCamera
	local baseFov = if camera then camera.FieldOfView else 70
	api:Track(function()
		if camera then
			camera.FieldOfView = baseFov
		end
	end)
	local function chomp()
		local clock = os.clock()
		if clock - lastPress < 0.15 then
			return
		end
		lastPress = clock
		if (api:Mine("ChompAt") or 0) <= api:Now() + 0.05 then
			local mine = sharks[api.Player.UserId]
			if mine then
				mine.LungeAt = api:Now() -- the lunge starts on my screen at once; the server's echo is skipped
			end
			api:Sound("Hit")
			punch = if reduced then 0 else 1
		end
		api:Action("Chomp")
	end
	local hintUntil = 0
	local function refreshRole()
		local role = api:Mine("Role")
		if role == nil then
			return
		end
		isShark = role == "Shark"
		roleIcon.Text = if isShark then "🦈" else "🏊"
		hint.Text = if isShark then "🦈 CHOMP swimmers and rafts!" else "🏊 Grab coins! Stay out of the water!"
		hint.Visible = true
		hintUntil = math.huge -- counted from GO (below)
		if isShark and not chompButton then
			chompButton = api:Button({ Text = "CHOMP", Key = Enum.KeyCode.E, Color = Theme.Colors.Red })
			chompButton.Pressed:Connect(chomp)
			local ok, signal = pcall(function()
				return UserInputService.JumpRequest
			end)
			if ok and signal then
				api:Track(signal:Connect(function()
					if GameState.Get("Phase") == "InRound" and api:Alive() then
						chomp()
					end
				end))
			end
		end
	end
	api:OnMine("Role", refreshRole)
	refreshRole()

	-- Events ---------------------------------------------------------------------------------------------

	local shake = 0
	api:OnEvent("Chomp", function(userId: number, x: number, z: number, lx: number, lz: number, raftIndex: number)
		local view = sharks[userId]
		local now = api:Now()
		if view and not (userId == api.Player.UserId and now - view.LungeAt < 0.4) then
			view.LungeAt = now
		end
		local look = Vector3.new(lx, 0, lz)
		local snout = Vector3.new(x, waterY, z) + look * 6
		task.delay(0.1, function()
			splash(snout, 0.8)
		end)
		local raft = rafts[raftIndex]
		if raft then
			local dir = flat(raft.Center - Vector3.new(x, raft.Center.Y, z))
			if dir.Magnitude > 0.1 then
				raft.Axis = Vector3.yAxis:Cross(dir.Unit)
			end
			if userId == api.Player.UserId then
				showFlash("💥 RAFT TIPPING!", Theme.Colors.Orange, 1)
			end
		end
		local _, _, root = api:Character()
		if root and flatDistance(root.Position, snout) < 16 and not reduced then
			shake = math.max(shake, 0.25)
		end
	end)
	local gulpedBy: number? = nil -- the shark whose belly this player is in
	local gulpUntil = 0
	local gulpCamera: Vector3? = nil
	local function releaseGulp()
		gulpedBy = nil
		gulpCamera = nil
		belly.Visible = false
		if camera and camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Custom
			local _, humanoid = api:Character()
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end
	api:Track(releaseGulp)
	api:OnEvent("Eaten", function(userId: number, sharkId: number, x: number, z: number, lost: number?)
		gulped[userId] = true
		local at = Vector3.new(x, waterY, z)
		splash(at, 1.5)
		floatText(at + Vector3.new(0, 3, 0), "CHOMP!", Theme.Colors.Red, 44)
		if lost and lost > 0 then
			task.delay(0.35, function()
				floatText(at + Vector3.new(0, 1, 0), `-{lost} 💰`, Theme.Colors.Orange, 32)
			end)
		end
		api:Effect("Bubbles", at)
		if userId == api.Player.UserId then
			gulpedBy = sharkId
			gulpUntil = os.clock() + 4.5
			belly.Visible = true
			bellyLabel.Text = "GULP! 🦈"
			showFlash("CHOMPED! 🦈", Theme.Colors.Red, 2.2)
			shake = if reduced then 0 else 0.6
		elseif sharkId == api.Player.UserId then
			showFlash("🦈 CHOMP! Got one!", Theme.Colors.Green, 1.4)
			api:Sound("Pickup")
		end
		api:Sound("Splash")
	end)
	api:OnEvent("SpatOut", function(userId: number, x: number, z: number)
		gulped[userId] = nil
		local at = Vector3.new(x, deckY, z)
		splash(at, 1)
		floatText(at + Vector3.new(0, 4, 0), "SPAT OUT!", Theme.Colors.Cyan, 34)
		if userId == api.Player.UserId then
			releaseGulp()
			showFlash("PTOOEY! Back on a raft!", Theme.Colors.Cyan, 1.6)
			api:Sound("Boing")
		end
	end)
	api:OnEvent("Tossed", function(userId: number)
		local character = api:CharacterOf(userId)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			splash(root.Position, 0.9)
		end
		if userId == api.Player.UserId then
			showFlash("SPLASH! Swim to a raft! 🌊", Theme.Colors.Cyan, 1.8)
		end
	end)
	api:OnEvent("Splash", function(userId: number, x: number, z: number)
		splash(Vector3.new(x, waterY, z), 0.7)
		if userId == api.Player.UserId and not isShark then
			api:Sound("Splash")
			if flash.Visible == false or os.clock() > flashUntil - 0.5 then
				showFlash("🌊 IN THE WATER! Get on a raft!", Theme.Colors.Cyan, 1.6)
			end
		end
	end)
	api:OnEvent("Grab", function(id: number, userId: number, value: number)
		local coin = coins[id]
		local now = api:Now()
		local mine = userId == api.Player.UserId
		local where = if coin then coin.Shown or coin.Position else nil
		if coin then
			if mine and coin.Pending then
				coin.Gone = "Grab"
				coin.GoneAt = coin.Pending
				coin.GoneFrom = coin.Shown
				coin.Pending = nil
			else
				coin.Pending = nil
				coin.Model.Parent = api.World
				coin.Gone = "Grab"
				coin.GoneAt = now
				coin.GoneFrom = coin.Shown
			end
			coin.Taker = userId
		end
		if where then
			floatText(where, `+{value}`, Theme.Colors.Coin)
			api:Effect("Sparkles", where, { Theme.Colors.Coin, Color3.new(1, 1, 1) })
		end
		if mine and not (coin and coin.Predicted) then
			api:Sound("Pickup")
		end
	end)
	api:OnEvent("Sink", function(id: number)
		local coin = coins[id]
		if coin and not coin.Gone then
			coin.Gone = "Sink"
			coin.GoneAt = api:Now()
			coin.GoneFrom = coin.Shown
		end
	end)
	api:OnEvent("Chest", function(x: number, z: number)
		splash(Vector3.new(x, waterY, z), 1.2)
		api:Sound("VoteOpen")
	end)
	local rushing = false
	local function refreshRush()
		if api:Shared("Rush") == true and not rushing then
			rushing = true
			showFlash("🌊 COIN RUSH! 🌊", Theme.Colors.Yellow, 2)
		end
	end
	api:OnShared("Rush", refreshRush)
	refreshRush()
	api:OnEvent("Win", function(team: string)
		api:Effect("Fireworks", origin + Vector3.new(0, 12, 0))
		if team == "Swimmers" then
			showFlash("🏊 SWIMMERS WIN! 🏊", swimmerColor, 3)
		else
			showFlash("🦈 SHARK WINS! 🦈", Teams.Colors.Sharks or Theme.Colors.Red, 3)
		end
	end)

	-- The water moves: each texture layer drifts its own way (ripples on top, caustics on the sand).
	local drifting: { { Texture: Texture, U: number, V: number } } = {}
	local speeds = {
		Ripples1 = { 0.9, 0.45 },
		Ripples2 = { -0.55, 0.8 },
		Caustics1 = { 0.55, 0.3 },
		Caustics2 = { -0.4, 0.5 },
	}
	local arena = api:Arena(10)
	for _, name in { "Ripples", "Caustics" } do
		local plane = if arena then arena:FindFirstChild(name) else nil
		if plane then
			for _, texture in plane:GetChildren() do
				local speed = speeds[texture.Name]
				if texture:IsA("Texture") and speed then
					table.insert(drifting, { Texture = texture, U = speed[1], V = speed[2] })
				end
			end
		end
	end

	-- Ambient: buoys and floats bob on the swell, sun glints dance on the water.
	local bobbers: { { Model: Model, Base: CFrame, Phase: number } } = {}
	local floatsFolder = arena and arena:FindFirstChild("Floats")
	if floatsFolder and not reduced then
		for _, model in floatsFolder:GetChildren() do
			if model:IsA("Model") then
				local base = model:GetPivot()
				table.insert(
					bobbers,
					{ Model = model, Base = base, Phase = (base.X * 0.07 + base.Z * 0.05) % (math.pi * 2) }
				)
			end
		end
	end
	if not reduced then
		local glints = newPart({
			Name = "SunGlints",
			Size = Vector3.new(80, 0.2, 80),
			Transparency = 1,
			CFrame = CFrame.new(origin.X, waterY + 0.2, origin.Z),
		})
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = GLINT_TEXTURE
		sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 255, 240))
		sparkle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0.9),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkle.Lifetime = NumberRange.new(0.4, 0.9)
		sparkle.Rate = 14
		sparkle.Speed = NumberRange.new(0, 0)
		sparkle.LightEmission = 1
		sparkle.Parent = glints
		CollectionService:AddTag(sparkle, "PP_Ambient")
	end

	-- Seagulls wheel high over the lagoon, banking round their circles.
	local gulls: { { Model: Model, Center: Vector3, Radius: number, Speed: number, Height: number, Phase: number } } =
		{}
	local function buildGulls()
		for index = 1, if reduced then 3 else 6 do
			local model = copy("SharkBaitGull") :: Model?
			if not model then
				return
			end
			for _, part in partsOf(model) do
				quiet(part)
			end
			model:ScaleTo(model:GetScale() * (1.4 + (index % 3) * 0.15))
			model.Parent = api.World
			local angle = index * 2.1
			table.insert(gulls, {
				Model = model,
				Center = origin + Vector3.new(math.cos(angle) * 14, 0, math.sin(angle) * 14),
				Radius = 22 + (index * 7) % 30,
				Speed = (0.22 + (index % 4) * 0.05) * (if index % 2 == 0 then 1 else -1),
				Height = deckY + 26 + (index * 5) % 16,
				Phase = index * 1.3,
			})
		end
	end
	local function drawGulls(clock: number)
		for _, gull in gulls do
			local angle = gull.Phase + clock * gull.Speed
			local position = gull.Center + Vector3.new(math.cos(angle) * gull.Radius, 0, math.sin(angle) * gull.Radius)
			position = Vector3.new(position.X, gull.Height + math.sin(clock * 0.8 + gull.Phase) * 1.5, position.Z)
			-- Flying along the circle (its tangent), banked into the turn.
			local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle)) * math.sign(gull.Speed)
			local bank = math.rad(22) * math.sign(gull.Speed)
			gull.Model:PivotTo(CFrame.lookAt(position, position + tangent) * CFrame.Angles(0, 0, bank))
		end
	end

	-- The shark's camera sits a little higher (so it sees over the rafts) and never closer than
	-- its whole body.
	local cameraHumanoid: Humanoid? = nil
	local savedZoom = tonumber((api.Player :: any).CameraMinZoomDistance) or 0.5
	local zoomSet = false
	api:Track(function()
		if cameraHumanoid and cameraHumanoid.Parent then
			cameraHumanoid.CameraOffset = Vector3.zero
		end
		if zoomSet then
			api.Player.CameraMinZoomDistance = savedZoom
		end
	end)

	-- Every frame ------------------------------------------------------------------------------------------

	local nextBob = 0
	local lastWet = false
	local nextWarning = 0
	api:RenderStep(function(dt: number)
		local now = api:Now()
		local clock = os.clock()

		-- Rafts.
		for _, raft in rafts do
			if raft.Model then
				raft.Model:PivotTo(raftPose(raft, now))
			end
			local safe = raft.State == READY and now < raft.SafeUntil
			raft.Foam.Transparency = if raft.State == FLIPPED then 0.15 else 0.45
			raft.Foam.Color = if safe then Color3.fromRGB(150, 255, 210) else Color3.fromRGB(235, 250, 255)
			if raft.State == WOBBLING then
				local pulse = 1 + 0.18 * math.sin(clock * 18)
				raft.Warning.Size = UDim2.fromOffset(110 * pulse, 110 * pulse)
			end
		end

		-- Sharks: build the ones we don't have yet (once the mesh has arrived).
		for _, userId in sharkIds do
			if not sharks[userId] and templates.SharkBaitShark then
				local view = buildShark(userId)
				if view then
					sharks[userId] = view
				end
			end
		end
		for _, view in sharks do
			drawShark(view, now, dt)
		end

		-- Swim rings and gulls.
		drawFloaties(now)
		if #gulls == 0 and templates.SharkBaitGull then
			buildGulls()
		end
		drawGulls(clock)

		-- Coins.
		local inRound = GameState.Get("Phase") == "InRound"
		local _, myHumanoid, myRoot = api:Character()
		local canGrab = inRound and not isShark and api:Alive() and myRoot ~= nil and not gulped[api.Player.UserId]
		for id, coin in coins do
			local kind = KINDS[coin.Kind]
			if coin.Pending and not coin.Gone then
				-- Predicted grab: fly to me and vanish, or come back if the server disagrees.
				local t = now - coin.Pending
				if t > PENDING_TIME then
					if coin.Missing then
						coin.Gone = "Lost"
						coin.GoneAt = now
						coin.GoneFrom = coin.Shown
					end
					coin.Pending = nil
					coin.Model.Parent = api.World
					coin.Model:ScaleTo(coin.BaseScale)
				else
					local from = coin.Shown or coin.Position
					local to = if myRoot then myRoot.Position + Vector3.new(0, 1.5, 0) else from + Vector3.new(0, 4, 0)
					local k = math.clamp(t / 0.3, 0, 1)
					if k >= 1 then
						coin.Model.Parent = nil
					else
						coin.Model:PivotTo(
							CFrame.new(from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * 2.5, 0))
								* CFrame.Angles(0, coin.Spin + t * 20, 0)
						)
						coin.Model:ScaleTo(coin.BaseScale * math.max(0.1, 1 - k * 0.8))
					end
					continue
				end
			end
			if coin.Gone then
				local t = now - coin.GoneAt
				local from = coin.GoneFrom or coin.Position
				if coin.Ring then
					coin.Ring.Transparency = 1
				end
				if coin.Beam then
					coin.Beam.Transparency = 1
				end
				if coin.Gone == "Grab" then
					local character = api:CharacterOf(coin.Taker)
					local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
					local to = if root then root.Position + Vector3.new(0, 1.5, 0) else from + Vector3.new(0, 4, 0)
					local k = math.clamp(t / 0.3, 0, 1)
					coin.Model:PivotTo(
						CFrame.new(from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * 2.5, 0))
							* CFrame.Angles(0, coin.Spin + t * 20, 0)
					)
					coin.Model:ScaleTo(coin.BaseScale * math.max(0.1, 1 - k * 0.8))
					if k >= 1 then
						removeCoin(id)
					end
				else
					-- Sunk (or gone): down through the water, spinning, and away.
					local k = math.clamp(t / 0.8, 0, 1)
					coin.Model:PivotTo(
						CFrame.new(from - Vector3.new(0, 4 * k, 0)) * CFrame.Angles(0, coin.Spin + t * 6, k)
					)
					if k >= 1 then
						removeCoin(id)
					end
				end
				continue
			end

			-- Where it is: flying off a flipped raft, rising into view, bobbing, or sinking at the end.
			local position = coin.Position
			local water = position.Y < waterY + 1.5
			local target: Vector3
			local scale = 1
			if coin.SpillAt and coin.From and now < coin.SpillAt + SPILL_TIME then
				local k = math.clamp((now - coin.SpillAt) / SPILL_TIME, 0, 1)
				target = coin.From:Lerp(position, k) + Vector3.new(0, 12 * k * (1 - k), 0)
			elseif now < coin.Born and not coin.SpillAt then
				local k = 1 - math.clamp((coin.Born - now) / POP_IN, 0, 1)
				target = position - Vector3.new(0, (1 - k) * 1.2, 0)
				scale = 0.3 + 0.7 * easeOut(k)
			else
				local bob = if water
					then math.sin(now * 1.8 + coin.Spin) * 0.18
					else math.sin(now * 2.4 + coin.Spin) * 0.15
				target = position + Vector3.new(0, bob + kind.Lift, 0)
				if coin.Expires > 0 and now > coin.Expires - SINK_TIME then
					local k = math.clamp((now - (coin.Expires - SINK_TIME)) / SINK_TIME, 0, 1)
					target -= Vector3.new(0, 2.2 * k * k, 0)
				end
			end
			coin.Shown = target
			local turn = CFrame.Angles(0, coin.Spin + now * kind.Spin, 0)
			if coin.Kind == 3 then
				turn *= CFrame.Angles(math.sin(now * 1.6 + coin.Spin) * 0.08, 0, math.cos(now * 1.3) * 0.08)
			end
			local want = coin.BaseScale * scale
			if math.abs(coin.Model:GetScale() - want) > 1e-3 then
				coin.Model:ScaleTo(want)
			end
			coin.Model:PivotTo(CFrame.new(target) * turn)
			if coin.Ring then
				local landed = not coin.SpillAt or now >= coin.SpillAt + SPILL_TIME
				coin.Ring.Transparency = if water and landed then 0.55 + 0.15 * math.sin(now * 3 + coin.Spin) else 1
				coin.Ring.CFrame = flatAt(Vector3.new(position.X, waterY + 0.15, position.Z))
			end

			-- Ran through it (or hopped through it): grab it now; the server confirms in a moment.
			if canGrab and myRoot and now >= coin.Born and not coin.Predicted then
				local p = myRoot.Position
				local before = coin.Rel
				if not before or (before - p).Magnitude > 24 then
					before = p
				end
				coin.Rel = p
				if swept(before, p, position, reaches[coin.Kind] or 2.8, grabBelow, grabAbove) then
					coin.Pending = now
					coin.Predicted = true
					api:Sound("Pickup")
				end
			else
				coin.Rel = nil
			end
		end

		-- In a shark's belly: ride along behind it until spat out.
		if gulpedBy then
			local view = sharks[gulpedBy]
			if clock > gulpUntil + 1 then
				releaseGulp() -- (the spit-out cue never came)
			elseif camera and view and view.Last then
				local forward = CFrame.Angles(0, view.Yaw, 0).LookVector
				local p = Vector3.new(view.Last.X, waterY, view.Last.Z)
				local want = p - forward * 17 + Vector3.new(0, 10, 0)
				gulpCamera = if gulpCamera then gulpCamera:Lerp(want, 1 - math.exp(-dt * 5)) else want
				camera.CameraType = Enum.CameraType.Scriptable
				camera.CFrame = CFrame.lookAt(gulpCamera :: Vector3, p + Vector3.new(0, 1.5, 0))
			end
			local left = math.max(0, math.ceil(gulpUntil - 0.5 - clock))
			bellyLabel.Text = if left > 0 then `GULP! 🦈  Spat out in {left}…` else "GULP! 🦈"
		end

		-- In the water: a warning when a shark closes in.
		local wet = api:Mine("InWater") == true and not isShark and api:Alive()
		if wet and not lastWet then
			hint.Visible = false
		end
		lastWet = wet
		if wet and myRoot and clock >= nextWarning then
			for _, view in sharks do
				if view.Last and flatDistance(view.Last, myRoot.Position) < 15 then
					nextWarning = clock + 2.5
					showFlash("🦈 SHARK! GET OUT! 🦈", Theme.Colors.Red, 1.2)
					api:Sound("HazardWarning")
					break
				end
			end
		end

		-- The shark's camera, and a little shake when the jaws snap close by.
		if isShark and myHumanoid and myHumanoid ~= cameraHumanoid then
			cameraHumanoid = myHumanoid
		end
		if isShark and not zoomSet then
			zoomSet = true
			api.Player.CameraMinZoomDistance = math.max(savedZoom, 16)
		end
		shake = math.max(0, shake - dt)
		if camera and (punch > 0 or camera.FieldOfView ~= baseFov) then
			punch = math.max(0, punch - dt * 3)
			camera.FieldOfView = baseFov + 7 * math.sin(punch * math.pi) * punch
		end
		local humanoid = cameraHumanoid or myHumanoid
		if humanoid and humanoid.Parent then
			local base = if isShark then SHARK_CAMERA else Vector3.zero
			local jolt = if shake > 0
				then Vector3.new(math.sin(clock * 71), math.sin(clock * 83), 0) * shake * 0.8
				else Vector3.zero
			if isShark or shake > 0 or humanoid.CameraOffset ~= Vector3.zero then
				humanoid.CameraOffset = base + jolt
			end
			cameraHumanoid = humanoid
		end

		-- Buoys and floats bob and the water drifts (both read fine at 30 Hz).
		if clock >= nextBob then
			nextBob = clock + 1 / 30
			for _, layer in drifting do
				local texture = layer.Texture
				texture.OffsetStudsU = (clock * layer.U) % texture.StudsPerTileU
				texture.OffsetStudsV = (clock * layer.V) % texture.StudsPerTileV
			end
			for _, bob in bobbers do
				local t = clock * 1.4 + bob.Phase
				bob.Model:PivotTo(
					bob.Base
						* CFrame.new(0, math.sin(t) * 0.22, 0)
						* CFrame.Angles(math.sin(t * 0.8) * 0.05, 0, math.cos(t * 0.9) * 0.05)
				)
			end
		end

		-- The role hint stays through the countdown and 6 seconds into the round.
		if hintUntil == math.huge and inRound then
			hintUntil = clock + 6
		end
		if hintUntil > 0 and clock > hintUntil then
			hintUntil = 0
			hint.Visible = false
		end
		if flash.Visible and clock > flashUntil then
			flash.Visible = false
		end

		if rushing then
			rushStroke.Transparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(clock * 9))
		end

		if chompButton then
			local readyAt = api:Mine("ChompAt") or 0
			local length = math.max(0.1, api:Mine("ChompLength") or 1)
			local left = math.max(0, readyAt - now)
			chompButton:SetFill(1 - left / length)
			chompButton:SetEnabled(left <= 0)
		end
	end)

	api:Track(function()
		for id in coins do
			removeCoin(id)
		end
		for _, view in sharks do
			view.Model:Destroy()
			view.WakeAnchor:Destroy()
		end
		for _, raft in rafts do
			if raft.Model then
				raft.Model:Destroy()
			end
		end
		for _, entry in floaties do
			if entry.Model then
				entry.Model:Destroy()
			end
			entry.Prey:Destroy()
		end
	end)
end

return SharkBait

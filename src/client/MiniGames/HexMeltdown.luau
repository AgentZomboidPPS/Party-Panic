-- Client half of Hex Meltdown: sinks and raises the hexes smoothly from the server's schedule
-- (MG_Call), makes the hexes of the called color glow, and shows the call big on screen.
-- Art pass ("make every arena look really cool"): sinking hexes splash lava sparks as they plunge
-- in, the referee robot hops when it raises a new flag, and the lava torches throw embers (ambient,
-- off with reduced effects).
-- Round's end (owner: "Bot is floating." "Theres invisible stuff."): the hexes move by the server's
-- own rule (Shared/Logic/HexMeltdown), which calls the call off when the round ends: nothing more
-- sinks, whatever was down comes back up and the call pill goes away. The last call used to play on
-- through the results, sinking survivors into the lava under bots left standing in the air.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Logic.HexMeltdown)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local HexMeltdown = {}

type Hex = {
	Model: Model,
	Base: CFrame,
	ColorIndex: number,
	Tops: { BasePart },
	Offset: number,
	Splash: ParticleEmitter?,
	SeenAbove: number, -- the last call during which this hex was seen above the lava
	SplashedCall: number,
}

local SPARKS = "rbxasset://textures/particles/sparkles_main.dds"
local LAVA_BELOW_TOP = 20 -- the lava surface under the hex tops (server: LAVA_DROP)

-- The parts that show a hex's color: the column's tile and band (or the cap, on an old arena).
local function findTops(model: Model): { BasePart }
	local column = model:WaitForChild("HexColumn", 5)
	local tops = {}
	if column then
		for _, part in column:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "Top" then
				table.insert(tops, part)
			end
		end
	end
	if #tops == 0 then
		local cap = model:FindFirstChild("Cap")
		if cap and cap:IsA("BasePart") then
			table.insert(tops, cap)
		end
	end
	return tops
end

local function sparks(parent: Instance, color: Color3): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKS
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), color)
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Parent = parent
	return emitter
end

function HexMeltdown.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 232, 214),
		Saturation = 0.18,
		Contrast = 0.1,
		Haze = Color3.fromRGB(255, 170, 120),
		HazeDecay = Color3.fromRGB(150, 70, 50),
		Density = 0.3,
	})
	local arena = api:Arena()
	if not arena then
		return
	end

	-- Lava sparks where each hex plunges in: one emitter per hex, on an attachment at the lava.
	local splashAnchor = Instance.new("Part")
	splashAnchor.Name = "SplashAnchor"
	splashAnchor.Anchored = true
	splashAnchor.CanCollide = false
	splashAnchor.CanQuery = false
	splashAnchor.CanTouch = false
	splashAnchor.Transparency = 1
	splashAnchor.Size = Vector3.one
	splashAnchor.CFrame = CFrame.identity
	splashAnchor.Parent = api.World

	local hexes: { Hex } = {}
	local function addHex(child: Instance)
		if not child:IsA("Model") or not string.match(child.Name, "^Hex%d+$") then
			return
		end
		local model = child :: Model
		model:WaitForChild("Cap", 5)
		local base = model:GetPivot()
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = base.Position - Vector3.new(0, LAVA_BELOW_TOP - 0.5, 0)
		attachment.Parent = splashAnchor
		local splash = sparks(attachment, Color3.fromRGB(255, 90, 30))
		splash.Size = NumberSequence.new(1.1, 0)
		splash.Lifetime = NumberRange.new(0.6, 1.1)
		splash.Speed = NumberRange.new(16, 30)
		splash.SpreadAngle = Vector2.new(40, 40)
		splash.Acceleration = Vector3.new(0, -60, 0)
		splash.EmissionDirection = Enum.NormalId.Top
		table.insert(hexes, {
			Model = model,
			Base = base,
			ColorIndex = model:GetAttribute("ColorIndex") or 0,
			Tops = findTops(model),
			Offset = 0,
			Splash = splash,
			SeenAbove = 0,
			SplashedCall = 0,
		})
	end

	-- Embers off the lava torches, tagged ambient so the reduced effects setting turns them off
	-- (AmbienceController).
	local function addEmbers(child: Instance)
		if child.Name ~= "LavaTorch" then
			return
		end
		local flame = child:FindFirstChild("Flame", true) or child:WaitForChild("Flame", 5)
		if not flame or not flame:IsA("BasePart") then
			return
		end
		local embers = sparks(flame, Color3.fromRGB(255, 120, 30))
		embers.Rate = 6
		embers.Size = NumberSequence.new(0.5, 0)
		embers.Lifetime = NumberRange.new(1.2, 2.2)
		embers.Speed = NumberRange.new(5, 9)
		embers.SpreadAngle = Vector2.new(25, 25)
		embers.Acceleration = Vector3.new(1.5, 2, 0)
		embers.EmissionDirection = Enum.NormalId.Top
		embers.Enabled = not State.ReducedEffects()
		CollectionService:AddTag(embers, "PP_Ambient")
	end

	local function addChild(child: Instance)
		addHex(child)
		addEmbers(child)
	end
	for _, child in arena:GetChildren() do
		task.spawn(addChild, child)
	end
	api:Track(arena.ChildAdded:Connect(addChild))

	-- The referee robot (it hops when it raises a new flag).
	local robot: Model? = nil
	local robotBase = CFrame.identity
	task.spawn(function()
		local found = arena:WaitForChild("RefereeBot", 5)
		if found and found:IsA("Model") then
			robotBase = found:GetPivot()
			robot = found
		end
	end)
	-- The call banner: shape and color name with a bar that runs out when the hexes sink. Kept small
	-- (owner, of the old big one over the referee's board: "This"): the flag and the board in the
	-- arena are the call, this is the reminder and the timer.
	local banner = UIKit.Panel({
		Name = "Call",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, api:HudY()),
		Size = UDim2.fromOffset(270, 60),
		CornerRadius = 18,
		Visible = false,
		Parent = api:TopHud(),
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local callText = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 32,
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 4),
		Parent = banner,
		Children = { UIKit.TextStroke(0.1) },
	})
	local barBack = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -32, 0, 8),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = banner,
		Children = { UIKit.Round() },
	})
	local bar = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Yellow,
		Parent = barBack,
		Children = { UIKit.Round() },
	})

	local call = nil
	local hopAt = -math.huge
	local function refreshCall()
		local previous = call
		call = api:SharedJSON("Call")
		if call then
			local color = Color3.fromRGB(call.RGB[1], call.RGB[2], call.RGB[3])
			callText.Text = `{call.Shape} {string.upper(call.Name)} {call.Shape}`
			callText.TextColor3 = color
			bar.BackgroundColor3 = color
			-- A call with StopAt is one the round's end called off: no reminder for it.
			banner.Visible = call.StopAt == nil
			if not previous or previous.Id ~= call.Id then
				hopAt = api:Now()
				UIKit.PopIn(banner, 0.3)
			end
		end
	end
	api:OnShared("Call", refreshCall)
	refreshCall()

	local robotHopping = false
	api:RenderStep(function()
		local now = api:Now()
		local warning = call ~= nil and call.StopAt == nil and now < call.SinkAt
		if call then
			bar.Size =
				UDim2.fromScale(math.clamp((call.SinkAt - now) / math.max(0.1, call.SinkAt - call.WarnAt), 0, 1), 1)
		end
		for _, hex in hexes do
			local matches = call ~= nil and hex.ColorIndex == call.Color
			local offset = if call and not matches then -Rules.Sunk(call, now) else 0
			-- Doomed hexes tremble in the last moments of the warning.
			local shake = 0
			if warning and not matches and call.SinkAt - now < 0.8 then
				shake = math.sin(now * 60 + hex.ColorIndex) * 0.12
			end
			if math.abs(offset + shake - hex.Offset) > 0.001 then
				hex.Offset = offset + shake
				hex.Model:PivotTo(hex.Base * CFrame.new(0, hex.Offset, 0))
			end
			-- A spray of lava sparks as the hex top plunges past the lava (only if it was seen above
			-- the lava during this call, so a player who joins mid-sink gets no burst of splashes).
			if call and offset >= -LAVA_BELOW_TOP then
				hex.SeenAbove = call.Id
			end
			if
				call
				and not matches
				and hex.Splash
				and hex.SeenAbove == call.Id
				and hex.SplashedCall ~= call.Id
				and offset < -LAVA_BELOW_TOP
			then
				hex.SplashedCall = call.Id
				hex.Splash:Emit(if State.ReducedEffects() then 5 else 14)
			end
			local material = if warning and matches then Enum.Material.Neon else Enum.Material.SmoothPlastic
			for _, top in hex.Tops do
				if top.Material ~= material then
					top.Material = material
				end
			end
		end
		-- The referee hops as the new flag goes up.
		local hop = now - hopAt
		if robot then
			if hop >= 0 and hop < 0.5 then
				robotHopping = true
				robot:PivotTo(robotBase * CFrame.new(0, math.sin(hop / 0.5 * math.pi) * 1.8, 0))
			elseif robotHopping then
				robotHopping = false
				robot:PivotTo(robotBase)
			end
		end
	end)
end

return HexMeltdown

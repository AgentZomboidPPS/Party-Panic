-- Client half of Hex Meltdown: sinks and raises the hexes smoothly from the server's schedule
-- (MG_Call), makes the hexes of the called color glow, and shows the call big on screen.

local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local HexMeltdown = {}

type Hex = { Model: Model, Base: CFrame, ColorIndex: number, Cap: BasePart?, Offset: number }

local function easeInOut(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- How far below its resting place a sinking hex is at `now`.
local function sinkOffset(call, now: number): number
	local move = call.Move or 0.7
	local depth = call.Depth or 26
	if now < call.SinkAt then
		return 0
	elseif now < call.SinkAt + move then
		return -depth * easeInOut((now - call.SinkAt) / move)
	elseif now < call.RiseAt then
		return -depth
	elseif now < call.RiseAt + move then
		return -depth * (1 - easeInOut((now - call.RiseAt) / move))
	end
	return 0
end

function HexMeltdown.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 232, 214),
		Saturation = 0.12,
		Contrast = 0.08,
		Haze = Color3.fromRGB(255, 170, 120),
		HazeDecay = Color3.fromRGB(150, 70, 50),
		Density = 0.32,
	})
	local arena = api:Arena()
	if not arena then
		return
	end

	local hexes: { Hex } = {}
	local function addHex(child: Instance)
		if not child:IsA("Model") or not string.match(child.Name, "^Hex%d+$") then
			return
		end
		local model = child :: Model
		local cap = model:WaitForChild("Cap", 5) :: BasePart?
		table.insert(hexes, {
			Model = model,
			Base = model:GetPivot(),
			ColorIndex = model:GetAttribute("ColorIndex") or 0,
			Cap = cap,
			Offset = 0,
		})
	end
	for _, child in arena:GetChildren() do
		task.spawn(addHex, child)
	end
	api:Track(arena.ChildAdded:Connect(addHex))

	-- The call banner: shape and color name with a bar that runs out when the hexes sink.
	local banner = UIKit.Panel({
		Name = "Call",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.fromOffset(380, 92),
		CornerRadius = 22,
		Visible = false,
		Parent = api.Gui,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	UIKit.AutoScale(banner)
	local callText = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 46,
		Size = UDim2.new(1, 0, 0, 62),
		Position = UDim2.fromOffset(0, 6),
		Parent = banner,
		Children = { UIKit.TextStroke(0.1) },
	})
	local barBack = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -40, 0, 10),
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
	local function refreshCall()
		call = api:SharedJSON("Call")
		if call then
			local color = Color3.fromRGB(call.RGB[1], call.RGB[2], call.RGB[3])
			callText.Text = `{call.Shape} {string.upper(call.Name)} {call.Shape}`
			callText.TextColor3 = color
			bar.BackgroundColor3 = color
			banner.Visible = true
			UIKit.PopIn(banner, 0.3)
		end
	end
	api:OnShared("Call", refreshCall)
	refreshCall()

	api:RenderStep(function()
		local now = api:Now()
		local warning = call ~= nil and now < call.SinkAt
		if call then
			bar.Size =
				UDim2.fromScale(math.clamp((call.SinkAt - now) / math.max(0.1, call.SinkAt - call.WarnAt), 0, 1), 1)
		end
		for _, hex in hexes do
			local matches = call ~= nil and hex.ColorIndex == call.Color
			local offset = if call and not matches then sinkOffset(call, now) else 0
			-- Doomed hexes tremble in the last moments of the warning.
			local shake = 0
			if warning and not matches and call.SinkAt - now < 0.8 then
				shake = math.sin(now * 60 + hex.ColorIndex) * 0.12
			end
			if math.abs(offset + shake - hex.Offset) > 0.001 then
				hex.Offset = offset + shake
				hex.Model:PivotTo(hex.Base * CFrame.new(0, hex.Offset, 0))
			end
			local material = if warning and matches then Enum.Material.Neon else Enum.Material.SmoothPlastic
			if hex.Cap and hex.Cap.Material ~= material then
				hex.Cap.Material = material
			end
		end
	end)
end

return HexMeltdown

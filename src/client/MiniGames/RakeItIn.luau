-- Client half of Rake It In: spins this player's copy of the field and the produce on it from the
-- server's shared schedule (MG_Spin, MG_Field), pops new produce out of the silo, swings everyone's
-- rake (bots too: stations are by UserId) and flies raked produce into the right basket. The HUD
-- shows your score, what each kind is worth and what's in your lane right now, and the RAKE button
-- (E or a click on PC; beside the jump button on phones).
--
-- Rakes are judged on the server at the moment you pressed; your own rake swings right away.

local UserInputService = game:GetService("UserInputService")

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local RakeItIn = {}

local KINDS = { "VeggieCarrot", "VeggieTomato", "VeggieBroccoli", "GoldenPumpkin", "VeggieBomb" }
local BOMB = 5
local SWING = 0.62 -- seconds a rake swing takes
local FLY = 0.55 -- seconds raked produce takes to reach the basket
local SOCKET = Vector3.new(0, 6.25, 0.5) -- where the handle meets the rake head, from the rake's pivot
local CAMERA_OFFSET = Vector3.new(0, 2.5, 0) -- the camera looks over the player's head at their lane

type Seg = { T: number, A: number, W0: number, W1: number, Ramp: number }

local function vec(list: { number }): Vector3
	return Vector3.new(list[1], list[2], list[3])
end

local function segAngle(seg: Seg, t: number): number
	local dt = t - seg.T
	if dt <= 0 then
		return seg.A + seg.W0 * dt
	elseif dt < seg.Ramp then
		return seg.A + seg.W0 * dt + (seg.W1 - seg.W0) * dt * dt / (2 * seg.Ramp)
	end
	return seg.A + (seg.W0 + seg.W1) / 2 * seg.Ramp + seg.W1 * (dt - seg.Ramp)
end

local function unpackSeg(list: { number }?): Seg?
	if not list then
		return nil
	end
	return { T = list[1], A = list[2], W0 = list[3], W1 = list[4], Ramp = list[5] }
end

local function partsOf(model: Instance): { BasePart }
	local list = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

-- Client-only decoration: anchored, never in the way of anything.
local function settle(model: Instance)
	for _, part in partsOf(model) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
end

local function fallbackModel(kind: number): Model
	local model = Instance.new("Model")
	local part = Instance.new("Part")
	part.Name = if kind == BOMB then "BombBody" else "Body"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * (if kind == 4 then 2.6 else 1.8)
	part.Color = if kind == BOMB
		then Color3.fromRGB(40, 40, 55)
		elseif kind == 4 then Color3.fromRGB(255, 196, 40)
		else Color3.fromRGB(255, 130, 40)
	part.CFrame = CFrame.new(0, part.Size.Y / 2, 0)
	part.Parent = model
	model.WorldPivot = CFrame.new()
	return model
end

local function ease(alpha: number): number
	return 1 - (1 - alpha) ^ 3
end

function RakeItIn.Start(api)
	api:Mood({ Tint = Color3.fromRGB(255, 249, 236), Saturation = 0.18, Contrast = 0.05 })
	local layout = api:SharedJSON("Layout")
	while not layout do
		task.wait(0.1)
		layout = api:SharedJSON("Layout")
	end
	local effects = not State.ReducedEffects()
	local stopped = false -- set when the round's cleanup runs (delayed effects check it)
	local function later(seconds: number, callback: () -> ())
		task.delay(seconds, function()
			if not stopped then
				callback()
			end
		end)
	end
	local rng = Random.new()
	local me = api.Player.UserId
	local center = vec(layout.Center)
	local soilY = center.Y + layout.SoilY
	local vent = center + Vector3.new(0, layout.VentY, 0)
	local rIn, rOut, half = layout.RIn, layout.ROut, layout.Half
	local values = layout.Values

	-- Stations by UserId (players and bots alike).
	local stations = {}
	for _, info in layout.Stations do
		local out = Vector3.new(math.cos(info.Angle), 0, math.sin(info.Angle))
		stations[info.User] = {
			Angle = info.Angle,
			Out = out,
			Stand = vec(info.Stand),
			Basket = vec(info.Basket),
			Color = Color3.fromRGB(info.Color[1], info.Color[2], info.Color[3]),
			SwingAt = -100,
		}
	end
	local mine = stations[me]

	-- Templates.
	local templates = {}
	for _, name in { "GardenRake", table.unpack(KINDS) } do
		task.spawn(function()
			templates[name] = api:Template(name)
		end)
	end
	local waited = 0
	while waited < 5 do
		local all = templates.GardenRake ~= nil
		for _, name in KINDS do
			all = all and templates[name] ~= nil
		end
		if all then
			break
		end
		waited += task.wait(0.1)
	end

	-- The field: this client spins the arena's copy.
	local arena = api:Arena(5)
	local field = arena and arena:FindFirstChild("TurningField") :: Model?
	local fieldBase = if field then field:GetPivot() else nil
	local myLane = arena and arena:FindFirstChild("Lane_" .. me) :: BasePart?
	if myLane then
		myLane.Material = Enum.Material.Neon
	end

	-- The turning schedule.
	local spinCur: Seg = { T = 0, A = 0, W0 = 0, W1 = 0, Ramp = 1 }
	local spinPrev: Seg? = nil
	local rush = api:Shared("Rush") == true
	local function readSpin()
		local spin = api:SharedJSON("Spin")
		if spin and spin.Cur then
			spinCur = unpackSeg(spin.Cur) :: Seg
			spinPrev = unpackSeg(spin.Prev)
		end
	end
	readSpin()
	api:OnShared("Spin", readSpin)
	local function angleAt(t: number): number
		local seg = if spinPrev and t < spinCur.T then spinPrev else spinCur
		return segAngle(seg, t)
	end
	local function onField(r: number, th: number, t: number): Vector3
		local angle = th + angleAt(t)
		return Vector3.new(center.X + math.cos(angle) * r, soilY, center.Z + math.sin(angle) * r)
	end
	local function inLane(station, item, t: number): boolean
		if t < item.Land or (item.Fuse > 0 and t >= item.Fuse) then
			return false
		end
		local d = item.Th + angleAt(t) - station.Angle
		local along = item.R * math.cos(d)
		return math.abs(item.R * math.sin(d)) <= half and along >= rIn and along <= rOut
	end

	-- Produce.
	local items = {}
	local flying = {}
	local function makeItem(kind: number): Model
		local template = templates[KINDS[kind]]
		local model = if template then template:Clone() :: Model else fallbackModel(kind)
		settle(model)
		for _, part in partsOf(model) do
			part.CastShadow = false
		end
		model.Parent = api.World
		return model
	end

	-- A floating "+3" (or "-3") over a basket.
	local function popup(position: Vector3, text: string, color: Color3)
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		anchor.CFrame = CFrame.new(position)
		anchor.Parent = api.World
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(120, 56)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 90
		gui.Parent = anchor
		UIKit.Label({
			Text = text,
			Font = Theme.Fonts.Display,
			TextScaled = true,
			TextColor3 = color,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0.1) },
		})
		local start = os.clock()
		local connection
		connection = api:Track(game:GetService("RunService").RenderStepped:Connect(function()
			local age = os.clock() - start
			if age > 1.1 or not anchor.Parent then
				connection:Disconnect()
				anchor:Destroy()
				return
			end
			anchor.CFrame = CFrame.new(position + Vector3.new(0, age * 3, 0))
			gui.Size = UDim2.fromOffset(120, 56)
		end))
	end

	local function boom(position: Vector3)
		api:Effect("Poof", position)
		if effects then
			local blast = Instance.new("Explosion")
			blast.BlastPressure = 0
			blast.ExplosionType = Enum.ExplosionType.NoCraters
			blast.BlastRadius = 3
			blast.DestroyJointRadiusPercent = 0
			blast.Position = position
			blast.Parent = api.World
		end
	end

	local function syncField()
		local data = api:SharedJSON("Field")
		if not data then
			return
		end
		local seen = {}
		for _, entry in data.Items do
			local id = entry[1]
			seen[id] = true
			if not items[id] then
				local item = {
					Id = id,
					Kind = entry[2],
					R = entry[3],
					Th = entry[4],
					Land = entry[5],
					Fuse = entry[6] or 0,
					Yaw = rng:NextNumber(0, math.pi * 2),
				}
				item.Model = makeItem(item.Kind)
				items[id] = item
			end
		end
		local goneBy = {}
		for _, entry in data.Gone or {} do
			goneBy[entry[1]] = entry[2]
		end
		local t = api:Now()
		for id, item in items do
			if seen[id] then
				continue
			end
			items[id] = nil
			local by = goneBy[id]
			local station = by and stations[by]
			local from = item.Model:GetPivot().Position
			if station and by ~= 0 and item.Kind == BOMB then
				boom(from + Vector3.new(0, 1, 0))
				item.Model:Destroy()
			elseif station and by ~= 0 then
				table.insert(flying, {
					Model = item.Model,
					From = from,
					To = station.Basket + Vector3.new(0, 2.6, 0),
					Start = os.clock() + (if station.SwingAt > os.clock() - 0.3 then 0.12 else 0),
					Spin = item.Yaw,
				})
			else
				if item.Kind == BOMB and t >= item.Fuse - 0.3 then
					boom(from + Vector3.new(0, 1, 0))
				else
					api:Effect("Poof", from)
				end
				item.Model:Destroy()
			end
		end
	end
	api:OnShared("Field", syncField)

	-- Rakes: one per station, lying over the field's edge in front of the stand.
	for userId, station in stations do
		local template = templates.GardenRake
		if not template then
			continue
		end
		local head = template:Clone() :: Model
		settle(head)
		for _, part in partsOf(head) do
			if part.Name == "RakeHandle" or part.Name == "RakeGrip" then
				part.Transparency = 1
			end
		end
		head.Parent = api.World
		local handle = Instance.new("Part")
		handle.Name = "RakeShaft"
		handle.Shape = Enum.PartType.Cylinder
		handle.Size = Vector3.new(4, 0.34, 0.34)
		handle.Color = Color3.fromRGB(200, 144, 88)
		handle.Material = Enum.Material.Wood
		settle(handle)
		handle.Parent = api.World
		local grip = Instance.new("Part")
		grip.Name = "RakeGrip"
		grip.Shape = Enum.PartType.Cylinder
		grip.Size = Vector3.new(1, 0.56, 0.56)
		grip.Color = station.Color
		settle(grip)
		grip.Parent = api.World
		station.Head = head
		station.Handle = handle
		station.Grip = grip
		station.User = userId
	end

	-- Where a station's rake head is, `u` (0..1) through a swing: out to the far end of the lane and
	-- down, a drag back to the rim, then up to rest.
	local function headSpot(station, u: number): Vector3
		local restR, restH = rOut - 1.2, 2.4
		local farR, lowH = rIn + 0.9, 0.35
		local r, h
		if u <= 0 or u >= 1 then
			r, h = restR, restH
		elseif u < 0.3 then
			local a = ease(u / 0.3)
			r, h = restR + (farR - restR) * a, restH + (lowH - restH) * a
		elseif u < 0.8 then
			local a = (u - 0.3) / 0.5
			a = a * a * (3 - 2 * a)
			r, h = farR + (rOut - 0.6 - farR) * a, lowH
		else
			local a = ease((u - 0.8) / 0.2)
			r, h = rOut - 0.6 + (restR - (rOut - 0.6)) * a, lowH + (restH - lowH) * a
		end
		return center + station.Out * r + Vector3.new(0, soilY - center.Y + h, 0)
	end

	local function placeRake(station, now: number)
		local head = station.Head
		if not head then
			return
		end
		local u = (now - station.SwingAt) / SWING
		local socket = headSpot(station, u)
		local hands = station.Stand + Vector3.new(0, 3.1, 0) - station.Out * 1.1
		local character = api:CharacterOf(station.User)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - station.Stand).Magnitude < 12 then
			hands = root.Position + Vector3.new(0, 0.2, 0) - station.Out * 1.1
		end
		local along = socket - hands
		if along.Magnitude < 0.5 then
			along = -station.Out
		end
		local y = along.Unit
		local up = Vector3.yAxis - y * y.Y
		local z = if up.Magnitude > 1e-3 then up.Unit else station.Out
		local x = y:Cross(z)
		head:PivotTo(CFrame.fromMatrix(socket, x, y, z) * CFrame.new(-SOCKET))
		local length = math.max(along.Magnitude, 0.5)
		local mid = hands + along / 2
		station.Handle.Size = Vector3.new(length, 0.34, 0.34)
		station.Handle.CFrame = CFrame.lookAt(mid, socket) * CFrame.Angles(0, math.pi / 2, 0)
		station.Grip.CFrame = CFrame.lookAt(hands, socket) * CFrame.new(0, 0, -0.65) * CFrame.Angles(0, math.pi / 2, 0)
	end

	-- HUD: your score, the legend (what's in your lane now), and RAKE.
	local hud = api:TopHud()
	local y = api:HudY()
	local legend = UIKit.Panel({
		Name = "Legend",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(350, 50),
		CornerRadius = 25,
		Parent = hud,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local legendText = UIKit.Label({
		Text = "🥕🍅 +1   🎃 +3   💣 -3",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		Size = UDim2.fromScale(1, 1),
		Parent = legend,
		Children = { UIKit.TextStroke(0.2) },
	})
	local scorePill = UIKit.Panel({
		Name = "Score",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, y),
		Size = UDim2.fromOffset(128, 50),
		CornerRadius = 25,
		Visible = mine ~= nil,
		Parent = hud,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local scoreText = UIKit.Label({
		Text = "🥕 0",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		Size = UDim2.fromScale(1, 1),
		Parent = scorePill,
		Children = { UIKit.TextStroke(0.2) },
	})
	api:OnMine("Score", function(value)
		scoreText.Text = `🥕 {value or 0}`
		UIKit.PopIn(scorePill, 0.25)
	end)
	local lanePill = UIKit.Panel({
		Name = "Lane",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 0, 0, y),
		Size = UDim2.fromOffset(128, 50),
		CornerRadius = 25,
		Visible = mine ~= nil,
		Parent = hud,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local laneText = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		Size = UDim2.fromScale(1, 1),
		Parent = lanePill,
		Children = { UIKit.TextStroke(0.2) },
	})
	local function showRush()
		if rush then
			legendText.Text = "RUSH! 🥕+1 🎃+3 💣-3"
			legendText.TextSize = 26
			legendText.TextColor3 = Theme.Colors.Yellow
			UIKit.PopIn(legend, 0.3)
		end
	end
	showRush()
	api:OnShared("Rush", function(value)
		rush = value == true
		showRush()
	end)

	local readyAt = 0 -- server time this player's rake is ready again (as far as this client knows)
	local readyFor = layout.Cooldown -- how long the current wait is (for the button's fill)
	local button = api:Button({ Text = "RAKE!", Key = Enum.KeyCode.E, Color = Theme.Colors.Orange })
	button:SetVisible(mine ~= nil)
	local function rake()
		if not mine or not api:Alive() then
			return
		end
		local t = api:Now()
		if t < readyAt then
			return
		end
		readyAt = t + layout.Cooldown
		readyFor = layout.Cooldown
		mine.SwingAt = os.clock()
		api:Action("Rake", t)
		api:Sound("Click")
	end
	button.Pressed:Connect(rake)
	if not api:IsTouch() then
		api:Track(UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
				rake()
			end
		end))
	end
	api:OnMine("Jammed", function(value)
		if type(value) == "number" and value > readyAt then
			readyFor = layout.Jam
			readyAt = value
		end
	end)

	-- value is the change to the raker's score; ids are the items raked; ready is when that rake can
	-- be used again (later after a bomb or an empty rake).
	api:OnEvent("Rake", function(userId, t, value, bomb, ids, ready)
		local station = stations[userId]
		if not station then
			return
		end
		if userId ~= me or os.clock() - station.SwingAt > 0.5 then
			station.SwingAt = os.clock()
		end
		-- Raked items leave the field right away (the field update comes a moment later): produce flies
		-- to the basket while the rake drags back, a bomb goes off where it was.
		for _, id in (if type(ids) == "table" then ids else {}) do
			local item = items[id]
			if not item then
				continue
			end
			items[id] = nil
			local model = item.Model
			if item.Kind == BOMB then
				later(0.15, function()
					boom(model:GetPivot().Position + Vector3.new(0, 1, 0))
					model:Destroy()
				end)
			else
				table.insert(flying, {
					Model = model,
					From = model:GetPivot().Position,
					To = station.Basket + Vector3.new(0, 2.6, 0),
					Start = os.clock() + 0.15,
					Spin = item.Yaw,
				})
			end
		end
		local spot = station.Basket + Vector3.new(0, 4.2, 0)
		local empty = type(ids) == "table" and #ids == 0
		if value ~= 0 or bomb then
			later(FLY, function()
				popup(
					spot,
					if value > 0 then `+{value}` else `{value} 💣`,
					if value > 0 then Theme.Colors.Green else Theme.Colors.Red
				)
			end)
		elseif empty and userId == me then
			popup(spot, "MISS", Theme.Colors.TextDim)
		end
		if userId == me then
			if type(ready) == "number" and type(t) == "number" and ready > readyAt then
				readyAt = ready
				readyFor = ready - t
			end
			if bomb then
				api:Sound("Hit")
				api:Hint("💣 Your rake is jammed!", y + 60)
				later(layout.Jam, function()
					api:Hint("", y + 60)
				end)
			elseif value > 0 then
				later(FLY, function()
					api:Sound("Pickup")
				end)
			end
		end
	end)

	syncField()

	local bombHighlights = {}
	local cameraHumanoid: Humanoid? = nil
	api:RenderStep(function()
		local t = api:Now()
		local clock = os.clock()
		local angle = angleAt(t)
		if field and fieldBase then
			field:PivotTo(fieldBase * CFrame.Angles(0, -angle, 0))
		end

		local laneValue, laneBomb, laneCount = 0, false, 0
		for id, item in items do
			local model = item.Model
			local position, yaw
			if t < item.Land then
				-- Flying out of the silo onto its spot.
				local a = math.clamp(1 - (item.Land - t) / layout.Flight, 0, 1)
				local landing = onField(item.R, item.Th, item.Land)
				position = vent:Lerp(landing, a) + Vector3.new(0, 7 * 4 * a * (1 - a), 0)
				yaw = item.Yaw + a * 6
			else
				position = onField(item.R, item.Th, t)
				yaw = item.Yaw - angle
				local lane = mine and inLane(mine, item, t)
				if lane then
					laneCount += 1
					laneValue += values[item.Kind]
					laneBomb = laneBomb or item.Kind == BOMB
					position += Vector3.new(0, 0.25 + 0.2 * math.abs(math.sin(clock * 7 + id)), 0)
				end
				if item.Kind == BOMB then
					local left = item.Fuse - t
					if left < 2.5 then
						position += Vector3.new(math.sin(clock * 50) * 0.08, 0, math.cos(clock * 43) * 0.08)
					end
					local highlight = bombHighlights[id]
					if lane and not highlight then
						highlight = Instance.new("Highlight")
						highlight.FillColor = Theme.Colors.Red
						highlight.OutlineColor = Color3.new(1, 1, 1)
						highlight.FillTransparency = 0.45
						highlight.DepthMode = Enum.HighlightDepthMode.Occluded
						highlight.Adornee = model
						highlight.Parent = model
						bombHighlights[id] = highlight
					elseif not lane and highlight then
						highlight:Destroy()
						bombHighlights[id] = nil
					end
				end
			end
			model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
		end
		for id in bombHighlights do
			if not items[id] then
				bombHighlights[id] = nil
			end
		end

		-- Raked produce flies to its basket.
		for index = #flying, 1, -1 do
			local fly = flying[index]
			local a = math.clamp((clock - fly.Start) / FLY, 0, 1)
			local position = fly.From:Lerp(fly.To, ease(a)) + Vector3.new(0, 4 * 4 * a * (1 - a), 0)
			fly.Model:PivotTo(CFrame.new(position) * CFrame.Angles(a * 4, fly.Spin + a * 5, 0))
			if a >= 1 then
				fly.Model:Destroy()
				table.remove(flying, index)
			end
		end

		for _, station in stations do
			placeRake(station, clock)
		end

		-- HUD: what raking now would get, and the rake's recharge.
		if mine then
			if laneCount == 0 then
				laneText.Text = "EMPTY"
				laneText.TextColor3 = Theme.Colors.TextDim
			else
				laneText.Text = if laneBomb then `💣 {laneValue}` else `LANE +{laneValue}`
				laneText.TextColor3 = if laneBomb or laneValue < 0 then Theme.Colors.Red else Theme.Colors.Green
			end
			local wait = readyAt - t
			button:SetFill(if wait > 0 then 1 - math.clamp(wait / math.max(readyFor, 0.1), 0, 1) else 0)
			button:SetEnabled(wait <= 0)
			if myLane then
				myLane.Transparency = 0.62 + 0.12 * math.sin(clock * 4)
			end
			-- The camera looks over your head, so your own character doesn't hide your lane.
			local character = api.Player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid ~= cameraHumanoid then
				cameraHumanoid = humanoid
				humanoid.CameraOffset = CAMERA_OFFSET
			end
		end
	end)

	api:Track(function()
		stopped = true
		if cameraHumanoid and cameraHumanoid.Parent then
			cameraHumanoid.CameraOffset = Vector3.zero
		end
		for _, item in items do
			item.Model:Destroy()
		end
		for _, fly in flying do
			fly.Model:Destroy()
		end
		if field and fieldBase and field.Parent then
			field:PivotTo(fieldBase)
		end
	end)
end

return RakeItIn

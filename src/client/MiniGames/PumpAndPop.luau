-- Client half of Pump & Pop: grows, wobbles and pops the teams' balloons from the air the server
-- shares ("Air_<Team>", 0..1), turns the tanks' gauge needles, works everyone's plungers (players'
-- and bots', from the "Push" and "Pump" events) and gives this player the PUMP button with its
-- timing meter: hold, let go in the green band (✓) for a full pump, not in the red (✕).
--
-- The server times the presses itself; the meter here only shows the same clock (FILL_TIME, SWEET
-- from "Layout"), and the PERFECT / WEAK / TOO LONG words come from the server's verdict. The
-- arena's balloons, tanks and plungers are built by the server and moved here, locally.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Teams = require(ReplicatedStorage.Shared.Teams)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local PumpAndPop = {}

local TRAVEL = 0.8 -- how far a plunger's handle goes down (studs)
local METER_TOP = 1.25 -- the meter shows holds up to this much of FILL_TIME (the red band above 1)
local DIAL_HUB = CFrame.new(0, 2.15, -2.8) -- the gauge needle's hub in the tank's space
local GREEN = Color3.fromRGB(90, 225, 120)
local RED = Color3.fromRGB(255, 80, 80)

type Station = {
	Team: string,
	Color: Color3,
	Shape: string,
	Balloon: Model?,
	BaseCFrame: CFrame,
	BaseScale: number,
	Scale: number,
	Shown: number,
	Puff: number,
	PuffSpeed: number,
	Popped: boolean,
	Smile: { BasePart },
	Ooh: { BasePart },
	Brows: { BasePart },
	Sweat: { BasePart },
	Needle: BasePart?,
	NeedleRest: CFrame,
	Hub: CFrame,
	Phase: number,
	Pill: Frame?,
}

type Plunger = {
	Team: string,
	Parts: { { Part: BasePart, Rest: CFrame } },
	Depth: number,
	PushedAt: number?,
	ReleasedAt: number,
	ReleasedFrom: number,
}

local function vec(list: { number }): Vector3
	return Vector3.new(list[1], list[2], list[3])
end

local function named(model: Instance, name: string): { BasePart }
	local list = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name == name then
			table.insert(list, part)
		end
	end
	return list
end

local function show(parts: { BasePart }, visible: boolean)
	for _, part in parts do
		part.Transparency = if visible then 0 else 1
	end
end

-- A plunger springing back up: overshoots a little and settles.
local function springBack(from: number, t: number, duration: number): number
	if t >= duration * 1.6 then
		return 0
	end
	local alpha = t / duration
	return from * math.exp(-4 * alpha) * math.cos(alpha * 7)
end

-- One of the shared sound effects at a pitch of our own (the pump's whoosh rises as the balloon
-- fills). Without the uploaded effects sprite it falls back to the plain effect.
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

function PumpAndPop.Start(api)
	api:Mood({ Tint = Color3.fromRGB(255, 250, 242), Saturation = 0.14, Contrast = 0.05 })
	local layout = api:SharedJSON("Layout")
	local waited = 0
	while not layout and waited < 10 do
		waited += task.wait(0.1)
		layout = api:SharedJSON("Layout")
	end
	local arena = api:Arena(10)
	if not layout or not arena then
		return
	end
	local effects = not State.ReducedEffects()
	local rng = Random.new()
	local me = Players.LocalPlayer.UserId
	local fill: number = layout.Fill
	local sweet: number = layout.Sweet
	local spring: number = layout.Spring
	local stuck: number = layout.Stuck

	-- The stations, their balloons and tanks, and every plunger.
	local stations = {} :: { [string]: Station }
	local order = {} :: { string }
	local plungers = {} :: { [number]: Plunger }
	local myTeam: string? = nil
	for _, info in layout.Stations do
		local team = info.Team
		local balloon = arena:FindFirstChild("Balloon_" .. team) :: Model?
		local tank = arena:FindFirstChild("Tank_" .. team) :: Model?
		local needle = if tank then tank:FindFirstChild("Needle", true) :: BasePart? else nil
		local station: Station = {
			Team = team,
			Color = Teams.Colors[team] or Theme.Colors.Pink,
			Shape = info.Shape or "",
			Balloon = balloon,
			BaseCFrame = if balloon then balloon:GetPivot() else CFrame.new(vec(info.Pos)),
			BaseScale = if balloon then balloon:GetScale() / layout.Empty else 1,
			Scale = layout.Empty,
			Shown = 0,
			Puff = 0,
			PuffSpeed = 0,
			Popped = false,
			Smile = if balloon then named(balloon, "Smile") else {},
			Ooh = if balloon then named(balloon, "Ooh") else {},
			Brows = if balloon then named(balloon, "Brows") else {},
			Sweat = if balloon then named(balloon, "Sweat") else {},
			Needle = needle,
			NeedleRest = if needle then needle.CFrame else CFrame.identity,
			Hub = if tank then tank:GetPivot() * DIAL_HUB else CFrame.identity,
			Phase = rng:NextNumber(0, math.pi * 2),
			Pill = nil,
		}
		stations[team] = station
		table.insert(order, team)
		for _, entry in info.Plungers do
			if entry.User == me then
				myTeam = team
			end
			local model = arena:FindFirstChild("Plunger_" .. entry.User)
			if model then
				local parts = {}
				for _, name in { "Rod", "Handle", "Grips" } do
					for _, part in named(model, name) do
						table.insert(parts, { Part = part, Rest = part.CFrame })
					end
				end
				plungers[entry.User] = {
					Team = team,
					Parts = parts,
					Depth = 0,
					PushedAt = nil,
					ReleasedAt = -math.huge,
					ReleasedFrom = 0,
				}
			end
		end
	end
	local myColor = if myTeam then stations[myTeam].Color else Theme.Colors.Pink
	local myPlunger = arena:FindFirstChild("Plunger_" .. me) :: Model?

	-- Your own pump stands out: an outline and a "YOU" marker over it.
	local feedbackAnchor: BasePart? = nil
	if myPlunger then
		local highlight = Instance.new("Highlight")
		highlight.Adornee = myPlunger
		highlight.FillColor = Color3.new(1, 1, 1)
		highlight.FillTransparency = 0.8
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = api.World
		local handle = myPlunger:FindFirstChild("Handle", true) :: BasePart?
		local anchor = Instance.new("Part")
		anchor.Name = "YouAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		anchor.CFrame = CFrame.new(if handle then handle.Position else myPlunger:GetPivot().Position)
		anchor.Parent = api.World
		feedbackAnchor = anchor
		local you = Instance.new("BillboardGui")
		you.Name = "You"
		you.Adornee = anchor
		you.Size = UDim2.fromOffset(90, 44)
		you.StudsOffset = Vector3.new(0, 2.2, 0)
		you.MaxDistance = 80
		you.LightInfluence = 0
		you.Parent = api.World
		UIKit.Label({
			Text = "▼ YOU",
			Font = Theme.Fonts.Display,
			TextSize = 26,
			TextColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromScale(1, 1),
			Parent = you,
			Children = { UIKit.TextStroke(0.1) },
		})
	end

	-- Everyone's team shape over their head (bots too), so teams read without color.
	local tags = {} :: { [number]: BillboardGui }
	local function refreshTags()
		for _, participant in api:Participants() do
			local team = participant:GetAttribute("PP_Team")
			local station = team and stations[team]
			local character = api:CharacterOf(participant.UserId)
			local head = character and character:FindFirstChild("Head") :: BasePart?
			local tag = tags[participant.UserId]
			if not station or not head or (tag and tag.Parent and tag.Adornee == head) then
				continue
			end
			if tag then
				tag:Destroy()
			end
			local gui = Instance.new("BillboardGui")
			gui.Name = "TeamTag"
			gui.Adornee = head
			gui.Size = UDim2.fromOffset(40, 40)
			gui.StudsOffset = Vector3.new(0, 3.1, 0)
			gui.MaxDistance = 90
			gui.LightInfluence = 0
			gui.Parent = api.World
			UIKit.Label({
				Text = station.Shape,
				Font = Theme.Fonts.Display,
				TextSize = 32,
				TextColor3 = station.Color,
				Size = UDim2.fromScale(1, 1),
				Parent = gui,
				Children = { UIKit.TextStroke(0) },
			})
			tags[participant.UserId] = gui
		end
	end
	refreshTags()

	-- HUD: one pill per team (shape, name, how full), yours outlined.
	local hud = api:TopHud()
	local y = api:HudY()
	local count = #order
	local pillWidth = math.min(150, math.floor(600 / count) - 10)
	for index, team in order do
		local station = stations[team]
		local mine = team == myTeam
		local pill = UIKit.new("Frame", {
			Name = "Team_" .. team,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, (index - (count + 1) / 2) * (pillWidth + 10), 0, y),
			Size = UDim2.fromOffset(pillWidth, 48),
			BackgroundColor3 = Theme.Colors.PanelDark,
			BackgroundTransparency = 0.15,
			Parent = hud,
			Children = {
				UIKit.Corner(14),
				UIKit.Stroke(if mine then Color3.new(1, 1, 1) else station.Color, if mine then 3 else 2, 0),
			},
		})
		UIKit.Label({
			Name = "Name",
			Text = `{station.Shape} {string.upper(team)}`,
			Font = Theme.Fonts.Display,
			TextSize = 20,
			TextColor3 = station.Color,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(10, 3),
			Size = UDim2.new(1, -60, 0, 26),
			Parent = pill,
			Children = { UIKit.TextStroke(0.3) },
		})
		UIKit.Label({
			Name = "Percent",
			Text = "0%",
			Font = Theme.Fonts.Display,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 3),
			Size = UDim2.fromOffset(52, 26),
			Parent = pill,
			Children = { UIKit.TextStroke(0.3) },
		})
		local track = UIKit.new("Frame", {
			Name = "Track",
			Position = UDim2.new(0, 10, 1, -15),
			Size = UDim2.new(1, -20, 0, 9),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.8,
			Parent = pill,
			Children = { UIKit.Round() },
		})
		UIKit.new("Frame", {
			Name = "Bar",
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = station.Color,
			Parent = track,
			Children = { UIKit.Round() },
		})
		if mine then
			UIKit.Label({
				Name = "You",
				Text = "▲ YOU",
				Font = Theme.Fonts.Display,
				TextSize = 16,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 1, 2),
				Size = UDim2.fromOffset(80, 18),
				Parent = pill,
				Children = { UIKit.TextStroke(0.2) },
			})
		end
		station.Pill = pill
	end
	if myTeam then
		api:Hint("Hold PUMP, let go in the green ✓", y + 74)
		task.delay(8, function()
			api:Hint("")
		end)
	end

	-- PUMP: the button, with a meter beside it showing how long you've held.
	local pump = if myTeam then api:Button({ Text = "PUMP", Key = Enum.KeyCode.E, Color = myColor }) else nil
	local meterFill: Frame? = nil
	local meterMark: Frame? = nil
	if pump then
		local holder = api.Gui:FindFirstChild("Action_PUMP")
		if holder then
			local meter = UIKit.new("Frame", {
				Name = "PumpMeter",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(0, -10, 0, 0),
				Size = UDim2.new(0, 34, 1, 0),
				BackgroundColor3 = Theme.Colors.PanelDark,
				BackgroundTransparency = 0.1,
				Parent = holder,
				Children = { UIKit.Corner(10), UIKit.Stroke(Color3.new(1, 1, 1), 2, 0.1) },
			})
			local function band(name: string, from: number, to: number, color: Color3, glyph: string)
				local frame = UIKit.new("Frame", {
					Name = name,
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale(0, 1 - from / METER_TOP),
					Size = UDim2.fromScale(1, (to - from) / METER_TOP),
					BackgroundColor3 = color,
					BackgroundTransparency = 0.35,
					Parent = meter,
				})
				UIKit.Label({
					Text = glyph,
					Font = Theme.Fonts.Display,
					TextSize = 18,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 3,
					Parent = frame,
					Children = { UIKit.TextStroke(0.2) },
				})
			end
			band("Sweet", sweet, 1, GREEN, "✓")
			band("Over", 1, METER_TOP, RED, "✕")
			meterFill = UIKit.new("Frame", {
				Name = "Fill",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.fromScale(1, 0),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.45,
				ZIndex = 2,
				Parent = meter,
			})
			meterMark = UIKit.new("Frame", {
				Name = "Mark",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.new(1, 8, 0, 5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				ZIndex = 4,
				Parent = meter,
				Children = { UIKit.Round(), UIKit.Stroke(Color3.new(0, 0, 0), 1, 0.4) },
			})
		end
	end

	-- Words over your pump: the server's verdict on each press.
	local streak = 0
	local function feedback(kind: string)
		if not feedbackAnchor then
			return
		end
		local text, color
		if kind == "perfect" then
			streak += 1
			text = if streak >= 3 then `PERFECT x{streak}!` else "PERFECT!"
			color = GREEN
		elseif kind == "weak" then
			streak = 0
			text, color = "WEAK", Theme.Colors.Yellow
		else
			streak = 0
			text, color = "TOO LONG!", RED
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "Feedback"
		gui.Adornee = feedbackAnchor
		gui.Size = UDim2.fromOffset(220, 50)
		gui.StudsOffset = Vector3.new(0, 4, 0)
		gui.MaxDistance = 80
		gui.LightInfluence = 0
		gui.AlwaysOnTop = true
		gui.Parent = api.World
		local label = UIKit.Label({
			Text = (if kind == "perfect" then "★ " elseif kind == "over" then "✕ " else "") .. text,
			Font = Theme.Fonts.Display,
			TextSize = 34,
			TextColor3 = color,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0) },
		})
		UIKit.Tween(gui, 0.7, { StudsOffset = Vector3.new(0, 6, 0) })
		UIKit.Tween(label, 0.7, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.75, function()
			gui:Destroy()
		end)
	end

	-- Your own presses (the plunger moves right away; the server judges them).
	local holding, wantDown = false, false
	local downClock, upClock = 0, -math.huge
	local mine = plungers[me]
	local poppedTeam: string? = api:Shared("Popped")

	local function release(send: boolean)
		if not holding then
			return
		end
		holding = false
		upClock = os.clock()
		if send then
			api:Action("Up")
		end
		if mine then
			mine.ReleasedFrom = mine.Depth
			mine.ReleasedAt = os.clock()
			mine.PushedAt = nil
		end
		local station = myTeam and stations[myTeam]
		local held = (os.clock() - downClock) / fill
		playSound(
			api,
			"ReturnToLobby",
			(if held > 1 then 0.8 else 1.3) + 0.7 * (if station then station.Shown else 0),
			if held >= sweet then 0.6 else 0.35
		)
	end
	if pump then
		pump.Pressed:Connect(function()
			wantDown = true
		end)
		pump.Released:Connect(function()
			wantDown = false
			release(true)
		end)
	end

	api:OnEvent("Push", function(userId)
		local plunger = plungers[userId]
		if plunger and userId ~= me then
			plunger.PushedAt = os.clock()
		end
	end)
	api:OnEvent("Pump", function(userId, air, kind)
		local plunger = plungers[userId]
		if plunger and userId ~= me then
			plunger.ReleasedFrom = plunger.Depth
			plunger.ReleasedAt = os.clock()
			plunger.PushedAt = nil
		end
		local station = plunger and stations[plunger.Team]
		if station and type(air) == "number" and air > 0 then
			station.PuffSpeed += 2.2 * math.clamp(air, 0, 1)
			if station.Team == myTeam and station.Shown > 0.75 and rng:NextNumber() < 0.35 then
				playSound(api, "Boing", 1.7 + rng:NextNumber(0, 0.3), 0.4) -- the rubber squeaks
			end
		end
		if userId == me and type(kind) == "string" then
			feedback(kind)
		end
	end)

	local function pop(team: string)
		local station = stations[team]
		if not station or station.Popped then
			return
		end
		station.Popped = true
		local balloon = station.Balloon
		local center = station.BaseCFrame.Position + Vector3.new(0, 15 * station.Scale * 0.55, 0)
		if balloon then
			for _, part in balloon:GetDescendants() do
				if part:IsA("BasePart") then
					part.Transparency = 1
				end
			end
		end
		api:Effect("Confetti", center, { station.Color, Color3.new(1, 1, 1), Theme.Colors.Yellow })
		if team == myTeam then
			api:Effect("Fireworks", center + Vector3.new(0, 4, 0), { station.Color, Theme.Colors.Yellow })
			api:Sound("Victory")
		end
		playSound(api, "Hit", 0.75, 1)
		playSound(api, "Boing", 0.6, 0.7)
		-- Shreds of rubber fly everywhere.
		local shreds = if effects then 16 else 5
		for _ = 1, shreds do
			local shred = Instance.new("Part")
			shred.Name = "Shred"
			shred.Size = Vector3.new(rng:NextNumber(0.6, 1.4), 0.15, rng:NextNumber(0.4, 1))
			shred.Color = station.Color
			shred.Material = Enum.Material.SmoothPlastic
			shred.CanQuery = false
			shred.CanTouch = false
			shred.CFrame = CFrame.new(center + rng:NextUnitVector() * 3)
				* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
			shred.AssemblyLinearVelocity = rng:NextUnitVector() * rng:NextNumber(20, 40) + Vector3.new(0, 25, 0)
			shred.AssemblyAngularVelocity = rng:NextUnitVector() * 12
			shred.Parent = api.World
			task.delay(2.5, function()
				shred:Destroy()
			end)
		end
		local pill = station.Pill
		if pill then
			local name = pill:FindFirstChild("Name") :: TextLabel?
			if name then
				name.Text = `{station.Shape} POP!`
			end
			UIKit.PopIn(pill, 0.3)
		end
		if pump then
			pump:SetEnabled(false)
		end
	end
	api:OnEvent("Pop", pop)
	if poppedTeam then
		pop(poppedTeam)
	end

	local tagClock = 0
	api:RenderStep(function(dt)
		local now = os.clock()
		dt = math.min(dt, 0.1)

		-- Start a press once the plunger is back up (a press during the spring waits for it).
		if wantDown and not holding and pump and pump:IsDown() and now >= upClock + spring + 0.03 then
			if not api:Shared("Popped") then
				holding = true
				downClock = now
				api:Action("Down")
				if mine then
					mine.PushedAt = now
				end
			end
		end
		if holding and now - downClock > stuck then
			release(false) -- held too long: the server lets the plunger slip back up
			wantDown = false
		end

		-- The meter and the button's fill.
		local held = if holding then (now - downClock) / fill else 0
		local color = if held > 1 then RED elseif held >= sweet then GREEN else Color3.new(1, 1, 1)
		if meterFill and meterMark then
			local level = math.min(held, METER_TOP) / METER_TOP
			meterFill.Size = UDim2.fromScale(1, level)
			meterFill.BackgroundColor3 = color
			meterMark.Position = UDim2.fromScale(0.5, 1 - level)
			meterMark.Visible = holding
		end
		if pump then
			pump:SetFill(math.min(held, 1), color)
		end

		-- Plungers: pushed down while held, then springing back up.
		for userId, plunger in plungers do
			local depth
			if plunger.PushedAt then
				local alpha = math.clamp((now - plunger.PushedAt) / fill, 0, 1)
				depth = 1 - (1 - alpha) ^ 2
				if userId == me and not holding then
					depth = 0
				end
			else
				depth = springBack(plunger.ReleasedFrom, now - plunger.ReleasedAt, spring)
			end
			if math.abs(depth - plunger.Depth) > 0.002 or (depth == 0 and plunger.Depth ~= 0) then
				plunger.Depth = depth
				local drop = Vector3.new(0, -TRAVEL * depth, 0)
				for _, piece in plunger.Parts do
					piece.Part.CFrame = piece.Rest + drop
				end
			end
		end

		-- Balloons: ease toward the shared air, puff on each pump, tremble when nearly full.
		local t = now
		for _, team in order do
			local station = stations[team]
			local target = api:Shared("Air_" .. team)
			target = if type(target) == "number" then math.clamp(target, 0, 1) else station.Shown
			station.Shown += (target - station.Shown) * math.min(1, dt * 6)
			station.PuffSpeed += (-260 * station.Puff - 11 * station.PuffSpeed) * dt
			station.Puff += station.PuffSpeed * dt
			local shown = station.Shown
			local pill = station.Pill
			if pill then
				local track = pill:FindFirstChild("Track")
				local bar = track and track:FindFirstChild("Bar") :: Frame?
				if bar then
					bar.Size = UDim2.fromScale(shown, 1)
				end
				local percent = pill:FindFirstChild("Percent") :: TextLabel?
				if percent then
					percent.Text = `{math.floor(math.clamp(target, 0, 1) * 100)}%`
				end
			end
			if station.Needle then
				local angle = math.rad(-120 + 240 * shown)
				station.Needle.CFrame = station.Hub
					* CFrame.Angles(0, 0, angle)
					* station.Hub:Inverse()
					* station.NeedleRest
			end
			local balloon = station.Balloon
			if balloon and not station.Popped then
				local scale = (layout.Empty + (layout.Full - layout.Empty) * shown ^ 0.85) * (1 + 0.06 * station.Puff)
				local nervous = math.clamp((shown - 0.7) / 0.3, 0, 1)
				local sway = math.sin(t * 1.3 + station.Phase) * 0.03
				local shake = if effects then math.sin(t * 27 + station.Phase) * 0.035 * nervous else 0
				if math.abs(scale - station.Scale) > 0.0015 then
					station.Scale = scale
					balloon:ScaleTo(station.BaseScale * scale)
				end
				balloon:PivotTo(station.BaseCFrame * CFrame.Angles(shake * 0.6, 0, sway + shake))
				show(station.Brows, shown >= 0.45)
				show(station.Ooh, shown >= 0.62)
				show(station.Smile, shown < 0.62)
				show(station.Sweat, shown >= 0.8)
			end
		end

		tagClock += dt
		if tagClock > 1 then
			tagClock = 0
			refreshTags()
		end
	end)
end

return PumpAndPop

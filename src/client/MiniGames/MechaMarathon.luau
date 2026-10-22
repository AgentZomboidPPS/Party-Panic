-- Client half of Mecha-Marathon: the WIND controls and their counter, the toys' keys turning as
-- everyone winds, then the flight itself: every toy lifts off its pad, cruises down its lane with
-- its rotor whirring and its key unwinding, sputters and glides down where its spring runs out,
-- and a flag in its color pops up on the spot with the distance. The camera follows the leaders.
--
-- The server counts the winds (presses are sent one by one with api:Action "Wind"; this side only
-- predicts its own count with the same counter, Shared/Logic/MechaMarathonFlight.Take, so the
-- number never runs ahead of what the server will count). Everyone's winds come in "Winds"; the
-- flights come in "Flights" (the launch time and each toy's meters) before lift-off, and every toy
-- flies the shared path (Flight.At), so the landings here are exactly where the server ranks them.
-- The toys are the server's models in the arena, moved here, locally; the wobble on top of the
-- path is cosmetic and fades out before touchdown.
--
-- Controls: PC players alternate Q and E (two WIND buttons; any press counts, alternating is just
-- faster), phones tap the big WIND button (every finger counts, so two thumbs can drum on it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Flight = require(ReplicatedStorage.Shared.Logic.MechaMarathonFlight)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local MechaMarathon = {}

local KEY_TURN = math.rad(90) -- one wind turns the key a quarter
local BODY_UP = 1.3 -- the toy turns about this point over its pivot (the middle of its body)
local GOLD = Color3.fromRGB(255, 212, 70)

type Toy = {
	User: number,
	Lane: number,
	Name: string,
	Color: Color3,
	Model: Model,
	Base: CFrame, -- on its pad
	Parts: { BasePart },
	Offsets: { CFrame },
	Kinds: { string }, -- "Rotor", "Key" or "" for each part
	RotorCenter: Vector3,
	KeyCenter: Vector3,
	KeyAngle: number,
	KeyShown: number,
	RotorAngle: number,
	Jolt: number, -- a little hop as a wind goes in
	Winds: number,
	Meters: number?,
	Plan: Flight.Plan?,
	Seed: number,
	Phases: { number },
	Landed: boolean,
	Sputtered: boolean,
	Tag: BillboardGui?,
	Trail: Trail?,
	Along: number,
	Height: number,
}

local function vec(list: any): Vector3
	return Vector3.new(list[1], list[2], list[3])
end

-- One of the shared sound effects at a pitch and volume of our own (falls back to the plain effect
-- without the uploaded effects sprite).
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

local function ordinal(place: number): string
	local suffix = "th"
	if place % 100 < 11 or place % 100 > 13 then
		suffix = ({ "st", "nd", "rd" })[place % 10] or "th"
	end
	return `{place}{suffix}`
end

function MechaMarathon.Start(api)
	api:Mood({ Tint = Color3.fromRGB(255, 251, 240), Saturation = 0.16, Contrast = 0.06 })
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
	local folder = arena:WaitForChild("Toys", 10)
	if not folder then
		return
	end
	local me = api.Player
	local origin = vec(layout.Origin)
	local effects = not State.ReducedEffects()
	local touch = api:IsTouch()

	-- The toys -------------------------------------------------------------------------------------
	local toys = {} :: { Toy }
	local byUser = {} :: { [number]: Toy }
	local mine: Toy? = nil
	for _, lane in layout.Lanes do
		local model = folder:WaitForChild("Toy_" .. tostring(lane.User), 5) :: Model?
		if not model then
			continue
		end
		local base = model:GetPivot()
		local toy: Toy = {
			User = lane.User,
			Lane = lane.Lane,
			Name = tostring(lane.Name),
			Color = Color3.fromRGB(lane.Color[1], lane.Color[2], lane.Color[3]),
			Model = model,
			Base = base,
			Parts = {},
			Offsets = {},
			Kinds = {},
			RotorCenter = Vector3.new(0, 3, 0),
			KeyCenter = Vector3.new(0, 1.4, 1.2),
			KeyAngle = 0,
			KeyShown = 0,
			RotorAngle = math.random() * math.pi,
			Jolt = 0,
			Winds = 0,
			Meters = nil,
			Plan = nil,
			Seed = lane.Lane,
			Phases = { 0, 0, 0 },
			Landed = false,
			Sputtered = false,
			Tag = nil,
			Trail = nil,
			Along = 0,
			Height = Flight.PAD,
		}
		-- Each piece's place in the toy, and the axes the rotor and key turn about (the middle of
		-- their pieces: both are symmetric about their axles).
		local rotorSum, rotorCount, keySum, keyCount = Vector3.zero, 0, Vector3.zero, 0
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				local offset = base:ToObjectSpace(part.CFrame)
				local kind = if part.Name == "Rotor" or part.Name == "Key" then part.Name else ""
				table.insert(toy.Parts, part)
				table.insert(toy.Offsets, offset)
				table.insert(toy.Kinds, kind)
				if kind == "Rotor" then
					rotorSum += offset.Position
					rotorCount += 1
				elseif kind == "Key" then
					keySum += offset.Position
					keyCount += 1
				end
			end
		end
		if rotorCount > 0 then
			toy.RotorCenter = rotorSum / rotorCount
		end
		if keyCount > 0 then
			toy.KeyCenter = keySum / keyCount
		end
		table.insert(toys, toy)
		byUser[toy.User] = toy
		if toy.User == me.UserId then
			mine = toy
		end
	end
	if #toys == 0 then
		return
	end

	-- Name tags over the toys: the lane number and name (yours says YOU, in gold).
	for _, toy in toys do
		local body = toy.Model.PrimaryPart or toy.Parts[1]
		local gui = Instance.new("BillboardGui")
		gui.Name = "ToyTag"
		gui.Adornee = body
		gui.Size = UDim2.fromOffset(150, 30)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
		gui.MaxDistance = 140
		gui.LightInfluence = 0
		gui.Parent = api.World
		local isMine = toy == mine
		UIKit.Label({
			Text = if isMine then `{toy.Lane} · YOU` else `{toy.Lane} · {toy.Name}`,
			Font = Theme.Fonts.Display,
			TextSize = if isMine then 24 else 18,
			TextColor3 = if isMine then GOLD else Color3.new(1, 1, 1),
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0.1) },
		})
		toy.Tag = gui
		-- A ribbon of the toy's color behind it in flight (makes the lanes easy to follow).
		if effects and body then
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, 0.5, 0.6)
			a0.Parent = body
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -0.3, 0.6)
			a1.Parent = body
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = ColorSequence.new(toy.Color)
			trail.Transparency = NumberSequence.new(0.35, 1)
			trail.Lifetime = 0.45
			trail.LightEmission = 0.3
			trail.Enabled = false
			trail.Parent = body
			api:Track(a0)
			api:Track(a1)
			api:Track(trail)
			toy.Trail = trail
		end
	end

	-- The crowd in the grandstands bounces while the toys fly (each stand in its own time).
	local crowd = {} :: { { Parts: { BasePart }, Rest: { CFrame }, Phase: number } }
	local field = arena:FindFirstChild("Field")
	local standsFolder = field and field:FindFirstChild("Stands")
	if standsFolder and effects then
		for index, stand in standsFolder:GetChildren() do
			local entry = { Parts = {}, Rest = {}, Phase = index * 1.7 }
			for _, part in stand:GetDescendants() do
				if part:IsA("BasePart") and (string.match(part.Name, "^Fans") or part.Name == "Heads") then
					table.insert(entry.Parts, part)
					table.insert(entry.Rest, part.CFrame)
				end
			end
			if #entry.Parts > 0 then
				table.insert(crowd, entry)
			end
		end
	end

	-- HUD -----------------------------------------------------------------------------------------
	local hud = api:TopHud()
	local y = api:HudY()
	local panel = UIKit.new("Frame", {
		Name = "WindPanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(if touch then 340 else 300, if touch then 100 else 80),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.2,
		Parent = hud,
		Children = { UIKit.Corner(16), UIKit.Stroke(Color3.new(1, 1, 1), 2, 0.2) },
	})
	local bigText = UIKit.Label({
		Name = "Count",
		Text = "🔑 0",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 40 else 36,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, if touch then 46 else 40),
		Parent = panel,
		Children = { UIKit.TextStroke(0.2) },
	})
	local track = UIKit.new("Frame", {
		Name = "Tension",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -28, 0, if touch then 28 else 18),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		Parent = panel,
		Children = { UIKit.Round() },
	})
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = if mine then mine.Color else Theme.Colors.Yellow,
		Parent = track,
		Children = { UIKit.Round() },
	})
	local barText = UIKit.Label({
		Name = "Detail",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 24 else 16,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = track,
		Children = { UIKit.TextStroke(0.15) },
	})
	local panelBottom = y + (if touch then 100 else 80)
	local shout = UIKit.Label({
		Name = "Shout",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 54 else 58,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, panelBottom + (if touch then 52 else 80)),
		Size = UDim2.fromOffset(560, 66),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0) },
	})
	local shoutUntil = 0
	local function yell(text: string, color: Color3?, seconds: number?)
		shout.Text = text
		shout.TextColor3 = color or Color3.new(1, 1, 1)
		shout.Size =
			UDim2.fromOffset(math.min(600, UIKit.TextWidth(text, shout.TextSize, Theme.Fonts.Display) + 24), 66)
		shout.Visible = true
		shoutUntil = os.clock() + (seconds or 1.2)
		UIKit.PopIn(shout, 0.3)
	end

	-- Controls ------------------------------------------------------------------------------------
	local wind = api:Button({ Text = "WIND", Key = Enum.KeyCode.E, Color = if mine then mine.Color else nil })
	local wind2 = if touch
		then nil
		else api:Button({ Text = "WIND", Key = Enum.KeyCode.Q, Color = if mine then mine.Color else nil, Slot = 2 })
	local counter = { Tokens = 1, At = 0 }
	local myWinds = 0
	local maxedAt = -10
	local lastPress = -10
	local function window(): (number?, number?)
		local windEnd = api:Shared("WindEnd")
		if type(windEnd) ~= "number" then
			return nil, nil
		end
		return windEnd - Flight.WIND_TIME, windEnd
	end
	local function press()
		local start, finish = window()
		local now = api:Now()
		if not start or not finish or now < start or now > finish or not api:CanAct() then
			return
		end
		if counter.At == 0 then
			counter.At = start
		end
		if not Flight.Take(counter, now) then
			maxedAt = os.clock()
			return
		end
		myWinds += 1
		lastPress = os.clock()
		api:Action("Wind")
		if mine then
			mine.KeyAngle += KEY_TURN
			mine.Jolt = 1
		end
		playSound(api, "Click", 0.9 + math.min(myWinds / Flight.MAX_WINDS, 1) * 0.9, 0.35)
	end
	if touch then
		-- Every finger that lands on the button is a press (two thumbs can drum on it).
		local holder = api.Gui:FindFirstChild("Action_WIND")
		local button = holder and holder:FindFirstChild("Button") :: GuiObject?
		if button then
			api:Track(button.InputBegan:Connect(function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.Touch then
					press()
				end
			end))
		end
	else
		wind.Pressed:Connect(press)
		if wind2 then
			wind2.Pressed:Connect(press)
		end
	end
	local function setButtons(on: boolean)
		wind:SetVisible(on)
		if wind2 then
			wind2:SetVisible(on)
		end
	end
	local function enableButtons(on: boolean)
		wind:SetEnabled(on)
		if wind2 then
			wind2:SetEnabled(on)
		end
	end
	enableButtons(false) -- they wake up at GO (the rules card and countdown come first)

	-- Camera (only for the players in the round) ---------------------------------------------------
	local camera = workspace.CurrentCamera
	local filming = State.InRound() and mine ~= nil
	if filming then
		local savedType, savedFov = camera.CameraType, camera.FieldOfView
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 58
		api:Track(function()
			camera.CameraType = savedType
			camera.FieldOfView = savedFov
		end)
	end
	local camEye: Vector3? = nil
	local camLook: Vector3? = nil

	-- Shared state --------------------------------------------------------------------------------
	local flights = nil
	local placeOf = {} :: { [number]: number }
	local winner: Toy? = nil
	local gone = {} :: { [number]: boolean }
	-- Places among toys whose players are still here (the server leaves out anyone who left; the
	-- server spreads equal distances apart, so there are no ties), and the server's own winner.
	local function rank()
		local order = {}
		for _, toy in toys do
			if toy.Meters and not gone[toy.User] then
				table.insert(order, toy)
			end
		end
		table.sort(order, function(a, b)
			return (a.Meters :: number) > (b.Meters :: number)
		end)
		table.clear(placeOf)
		for index, toy in order do
			placeOf[toy.User] = index
		end
		local named = api:Shared("Winner")
		winner = (if type(named) == "number" then byUser[named] else nil) or order[1]
	end
	api:OnShared("Winner", rank)
	local function readWinds()
		local winds = api:SharedJSON("Winds")
		if type(winds) ~= "table" then
			return
		end
		for user, count in winds do
			local toy = byUser[tonumber(user) or 0]
			if toy and type(count) == "number" and count > toy.Winds then
				if toy ~= mine then
					toy.KeyAngle += (count - toy.Winds) * KEY_TURN
					toy.Jolt = 1
				end
				toy.Winds = count
			end
		end
		-- Presses bunched by a lag spike that the server dropped: show its count, not ours.
		if mine and myWinds > mine.Winds + Flight.BURST + 4 then
			myWinds = mine.Winds
		end
	end
	api:OnShared("Winds", readWinds)
	readWinds()
	local function readFlights()
		local data = api:SharedJSON("Flights")
		if type(data) ~= "table" or type(data.Toys) ~= "table" then
			return
		end
		flights = data
		for user, entry in data.Toys do
			local toy = byUser[tonumber(user) or 0]
			if toy and type(entry) == "table" and type(entry.M) == "number" then
				toy.Meters = entry.M
				toy.Plan = Flight.Plan(entry.M)
				toy.Seed = tonumber(entry.S) or toy.Lane
				local rng = Random.new(toy.Seed)
				toy.Phases = { rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28) }
				toy.Winds = tonumber(entry.W) or toy.Winds
			end
		end
		rank()
	end
	api:OnShared("Flights", readFlights)
	readFlights()
	local function readGone()
		local list = api:SharedJSON("Gone")
		if type(list) ~= "table" then
			return
		end
		for _, user in list do
			local toy = byUser[tonumber(user) or 0]
			if toy then
				gone[toy.User] = true
				if toy.Tag then
					toy.Tag.Enabled = false
				end
			end
		end
		rank()
	end
	api:OnShared("Gone", readGone)
	readGone()

	-- Landing flags: a pole in the toy's color where it came down, with the distance over it.
	local flagTemplate: Instance? = nil
	task.spawn(function()
		flagTemplate = api:Template("MechaMarathonFlag", 8)
	end)
	local function plantFlag(toy: Toy, spot: Vector3)
		if flagTemplate then
			local flag = (flagTemplate :: Instance):Clone() :: Model
			for _, part in flag:GetDescendants() do
				if part:IsA("BasePart") and part.Name == "Pennant" then
					part.Color = toy.Color
				end
			end
			flag:PivotTo(CFrame.new(spot + Vector3.new(2.2, 0, 0)) * CFrame.Angles(0, math.rad(-20), 0))
			flag.Parent = api.World
		end
		local anchor = Instance.new("Part")
		anchor.Name = "FlagSpot"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		anchor.CFrame = CFrame.new(spot + Vector3.new(2.2, 5.6, 0))
		anchor.Parent = api.World
		local gui = Instance.new("BillboardGui")
		gui.Name = "Distance"
		gui.Adornee = anchor
		gui.Size = UDim2.fromOffset(130, 34)
		gui.MaxDistance = 220
		gui.LightInfluence = 0
		gui.Parent = anchor
		local isMine = toy == mine
		local label = UIKit.Label({
			Text = string.format("%d · %.2f m", toy.Lane, toy.Meters or 0),
			Font = Theme.Fonts.Display,
			TextSize = if isMine then 24 else 19,
			TextColor3 = if isMine then GOLD else Color3.new(1, 1, 1),
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0.1) },
		})
		UIKit.PopIn(label, 0.3)
	end

	-- Where a toy is and how it's turned at time t after lift-off (the path plus its wobble).
	local function flightFrame(toy: Toy, t: number): (CFrame, string, number)
		local plan = toy.Plan :: Flight.Plan
		local along, height, stage, u = Flight.At(plan, t)
		local p1, p2, p3 = toy.Phases[1], toy.Phases[2], toy.Phases[3]
		-- The wobble fades in after lift-off and out before touchdown, so the landing spot is exact.
		local envelope = math.clamp(t / 1.2, 0, 1) * math.clamp((plan.Total - t) / 1.4, 0, 1)
		along += math.sin(t * 0.85 + p1) * 1.6 * envelope
		height += (math.sin(t * 2.3 + p2) * 0.55 + math.sin(t * 4.1 + p3) * 0.2) * envelope
		local side = math.sin(t * 1.15 + p3) * 0.7 * envelope
		local pitch, roll, yaw
		if stage == "power" then
			local climb = math.clamp(1 - t / 0.5, 0, 1)
			pitch = math.rad(-9 + 20 * climb)
			roll = math.rad(math.sin(t * 1.9 + p2) * 9) * envelope
			yaw = math.rad(math.sin(t * 1.3 + p1) * 5) * envelope
		elseif stage == "glide" then
			-- The spring has run down: nose drops, it rocks, and it comes down.
			pitch = math.rad(-9 - 22 * u)
			roll = math.rad(math.sin(t * 7 + p2) * (6 + 10 * u))
			yaw = math.rad(math.sin(t * 2.4 + p1) * 7)
		else
			-- Down: a little hop, then it settles, tipped on its nose.
			local since = t - plan.Total
			local hop = math.max(0, 1 - since / 0.7)
			height = math.abs(math.sin(math.min(since, 0.7) / 0.7 * math.pi * 2)) * 0.7 * hop
			pitch = math.rad(-14 * math.min(since / 0.4, 1))
			roll = math.rad(math.sin(since * 14) * 8 * hop)
			yaw = 0
		end
		local position = toy.Base.Position + Vector3.new(side, height - Flight.PAD, -along)
		local frame = CFrame.new(position + Vector3.new(0, BODY_UP, 0))
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(pitch, 0, roll)
			* CFrame.new(0, -BODY_UP, 0)
		toy.Along = along
		toy.Height = height
		return frame, stage, u
	end

	-- Every frame ---------------------------------------------------------------------------------
	local parts = {} :: { BasePart }
	local frames = {} :: { CFrame }
	local stagePrev = ""
	local done = false
	local hinted = false
	local lastLeader = 0
	api:RenderStep(function(dt)
		local now = api:Now()
		local start, finish = window()
		local launchAt = if flights then tonumber(flights.LaunchAt) else nil
		local stage
		if not start or not finish or now < start then
			stage = "ready"
		elseif now <= finish then
			stage = "wind"
		elseif not launchAt or now < launchAt then
			stage = "launch"
		else
			stage = "flight"
		end

		-- Cues as the stages change.
		if stage ~= stagePrev then
			if stage == "wind" then
				enableButtons(true)
				yell("WIND IT UP!", GOLD, 1.4)
				if not hinted then
					hinted = true
					api:Hint(
						if touch then "Tap WIND as fast as you can!" else "Alternate Q and E, fast!",
						panelBottom + (if touch then 8 else 6)
					)
				end
			elseif stage == "launch" then
				api:Hint("")
				setButtons(false)
				yell("READY...", Color3.new(1, 1, 1), 1.2)
			elseif stage == "flight" then
				api:Hint("")
				setButtons(false)
				yell("LAUNCH!", Theme.Colors.Orange, 1.4)
				playSound(api, "Boing", 0.8, 0.8)
				playSound(api, "ReturnToLobby", 0.75, 0.7)
				for _, toy in toys do
					if toy.Plan then
						if effects then
							api:Effect("Poof", toy.Base.Position, { Color3.new(1, 1, 1) })
						end
						if toy.Trail then
							toy.Trail.Enabled = true
						end
					end
				end
			end
			stagePrev = stage
		end
		if shout.Visible and os.clock() > shoutUntil then
			shout.Visible = false
		end

		-- The panel: your winds while winding, then the flight.
		local shownWinds = if mine then math.max(myWinds, mine.Winds) else 0
		if mine and mine.Meters and stage ~= "wind" then
			shownWinds = mine.Winds
		end
		if stage == "ready" or stage == "wind" or stage == "launch" then
			bigText.Text = `🔑 {shownWinds}`
			bar.Size = UDim2.fromScale(math.clamp(shownWinds / Flight.MAX_WINDS, 0, 1), 1)
			if stage == "wind" and finish then
				if os.clock() - maxedAt < 0.5 then
					barText.Text = "MAX SPEED!"
				else
					barText.Text = string.format("WIND! %.1fs", math.max(finish - now, 0))
				end
			elseif stage == "launch" then
				barText.Text = string.format("≈ %.0f m", Flight.Meters(shownWinds, 0))
			else
				barText.Text = "Get ready to WIND"
			end
		end

		-- Toys on their pads: keys turning, a jolt as each wind goes in, shaking with tension.
		table.clear(parts)
		table.clear(frames)
		local front, frontX, frontCount = 0, 0, 0
		local minX, maxX = math.huge, -math.huge
		local flying = 0
		local t = if launchAt then now - launchAt else -1
		for _, toy in toys do
			if not toy.Model.Parent then
				continue
			end
			local frame: CFrame
			local spin: number
			if stage ~= "flight" or not toy.Plan then
				toy.Jolt = math.max(0, toy.Jolt - dt * 7)
				local tension = math.clamp(toy.Winds / 90, 0, 1)
				local shake = if stage == "launch" and toy.Plan
					then math.sin(os.clock() * 55 + toy.Lane) * 0.05 * (0.4 + tension)
					else 0
				frame = toy.Base
					* CFrame.new(shake, toy.Jolt * 0.18, 0)
					* CFrame.Angles(math.rad(toy.Jolt * 4), 0, math.rad(shake * 30))
				spin = if stage == "launch" and toy.Plan then 4 + tension * 8 else 0.6
				toy.KeyShown += (toy.KeyAngle - toy.KeyShown) * math.clamp(dt * 18, 0, 1)
			else
				local stageNow, u
				frame, stageNow, u = flightFrame(toy, t)
				local plan = toy.Plan :: Flight.Plan
				if stageNow == "power" then
					spin = 30
					-- The key unwinds as the spring runs down.
					toy.KeyShown = toy.KeyAngle * (1 - u)
					flying += 1
				elseif stageNow == "glide" then
					spin = 30 * (1 - u) ^ 1.5
					flying += 1
					if not toy.Sputtered then
						toy.Sputtered = true
						if effects then
							api:Effect(
								"Poof",
								frame.Position + Vector3.new(0, 1.5, 0),
								{ Color3.fromRGB(200, 200, 210) }
							)
						end
					end
				else
					spin = 0
					if not toy.Landed then
						toy.Landed = true
						if toy.Trail then
							toy.Trail.Enabled = false
						end
						local spot = toy.Base.Position + Vector3.new(0, -Flight.PAD, -plan.Distance)
						plantFlag(toy, spot)
						if effects then
							api:Effect("Poof", spot + Vector3.new(0, 0.5, 0), { Color3.fromRGB(190, 170, 130) })
						end
						if toy == mine then
							local place = placeOf[toy.User]
							yell(
								string.format("%.2f m%s", toy.Meters or 0, if place then ` · {ordinal(place)}` else ""),
								GOLD,
								2.4
							)
							playSound(api, "Boing", 1.1, 0.7)
						end
					end
				end
				if stageNow ~= "landed" then
					front = math.max(front, toy.Along)
				end
			end
			toy.RotorAngle += spin * dt
			-- (A toy that has landed is written once where it lies, not every frame for the rest of
			-- the round: ~100 part moves a frame on phones for nothing.)
			local resting = toy.Landed and spin == 0
			if resting and toy.RestWritten then
				continue
			end
			toy.RestWritten = resting
			for index, part in toy.Parts do
				local offset = toy.Offsets[index]
				local kind = toy.Kinds[index]
				local cframe
				if kind == "Rotor" then
					local center = toy.RotorCenter
					cframe = frame
						* CFrame.new(center)
						* CFrame.Angles(0, toy.RotorAngle, 0)
						* CFrame.new(-center)
						* offset
				elseif kind == "Key" then
					local center = toy.KeyCenter
					cframe = frame
						* CFrame.new(center)
						* CFrame.Angles(0, 0, toy.KeyShown)
						* CFrame.new(-center)
						* offset
				else
					cframe = frame * offset
				end
				table.insert(parts, part)
				table.insert(frames, cframe)
			end
		end
		local cheer = if stage == "flight" then 0.3 elseif stage == "launch" then 0.18 else 0.06
		local beat = if stage == "flight" or stage == "launch" then 9 else 3
		for _, stand in crowd do
			local hop = math.abs(math.sin(os.clock() * beat + stand.Phase)) * cheer
			for index, part in stand.Parts do
				if part.Parent then
					table.insert(parts, part)
					table.insert(frames, stand.Rest[index] + Vector3.new(0, hop, 0))
				end
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
		-- The leaders: every toy still flying within a few studs of the front one.
		for _, toy in toys do
			if toy.Plan and not toy.Landed and stage == "flight" and toy.Along >= front - 8 then
				local x = toy.Base.Position.X
				frontX += x
				frontCount += 1
				minX, maxX = math.min(minX, x), math.max(maxX, x)
			end
		end

		-- The flight on the panel: the leaders' distance, then your own landing.
		if stage == "flight" then
			if flying > 0 then
				lastLeader = front
				bigText.Text = string.format("✈ %.1f m", front / Flight.STUDS_PER_METER)
			elseif winner and winner.Meters then
				bigText.Text = string.format("🏆 %.2f m", winner.Meters)
			end
			local total = if winner and winner.Plan then winner.Plan.Distance else 1
			bar.Size = UDim2.fromScale(math.clamp(lastLeader / math.max(total, 1), 0, 1), 1)
			if mine and mine.Landed then
				local place = placeOf[mine.User]
				barText.Text =
					string.format("YOU %.2f m%s", mine.Meters or 0, if place then ` · {ordinal(place)}` else "")
			elseif mine and mine.Plan then
				barText.Text = string.format("YOU ✈ %.1f m", mine.Along / Flight.STUDS_PER_METER)
			else
				barText.Text = "Watch them fly!"
			end
			if flying == 0 and not done and winner and winner.Landed then
				done = true
				local spot = winner.Base.Position + Vector3.new(0, -Flight.PAD, -(winner.Plan :: Flight.Plan).Distance)
				yell(if winner == mine then "🏆 YOU WIN!" else `🏆 {string.upper(winner.Name)}`, GOLD, 3)
				api:Effect("Confetti", spot + Vector3.new(0, 2, 0), { winner.Color, GOLD, Color3.new(1, 1, 1) })
				if effects then
					api:Effect("Fireworks", spot + Vector3.new(0, 8, 0), { winner.Color, GOLD })
				end
				api:Sound("Victory")
			end
		end

		-- Camera: behind your toy while winding, then chasing the leaders, then on the winner.
		if filming and mine then
			if camera.CameraType ~= Enum.CameraType.Scriptable then
				camera.CameraType = Enum.CameraType.Scriptable
			end
			local pad = mine.Base.Position
			local eye, look
			if stage == "ready" then
				eye = pad + Vector3.new(5.5, 6.5, 17)
				look = pad + Vector3.new(0, 1.5, -16)
			elseif stage == "wind" then
				local progress = math.clamp((now - (start :: number)) / Flight.WIND_TIME, 0, 1)
				eye = pad + Vector3.new(5 - progress * 1.5, 5.6 - progress * 1, 14 - progress * 3.5)
				look = pad + Vector3.new(0, 1.6, -14)
			elseif stage == "launch" then
				eye = pad + Vector3.new(3, 8, 16)
				look = pad + Vector3.new(0, 4, -22)
			elseif flying > 0 then
				-- Frame every leader and your own toy if it's still flying: back off until they fit.
				if mine.Plan and not mine.Landed then
					minX, maxX = math.min(minX, pad.X), math.max(maxX, pad.X)
				end
				if minX > maxX then
					minX, maxX = pad.X, pad.X
				end
				local x = (minX + maxX) / 2
				local viewport = camera.ViewportSize
				local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
				local halfWide = math.atan(math.tan(math.rad(camera.FieldOfView) / 2) * aspect)
				local need = ((maxX - minX) / 2 + 6) / math.tan(halfWide) -- distance to fit the spread
				local back = math.clamp(need / 22, 1, 3) -- 22: the default eye's distance to the pack
				local ahead = origin.Z - front
				eye = Vector3.new(x + 7, origin.Y + Flight.HEIGHT - 3 + 10 * back, ahead + 21 * back)
				look = Vector3.new(x, origin.Y + Flight.HEIGHT - 3, ahead - 16)
			else
				local target = winner or mine
				local plan = target.Plan
				local spot = target.Base.Position + Vector3.new(0, -Flight.PAD, -(if plan then plan.Distance else 0))
				local drift = math.sin(os.clock() * 0.3) * 3
				eye = spot + Vector3.new(9 + drift, 8, 19)
				look = spot + Vector3.new(0, 1.5, -2)
			end
			local rate = if stage == "flight" then 5 else 2.5
			local alpha = math.clamp(dt * rate, 0, 1)
			camEye = if camEye then camEye:Lerp(eye, alpha) else eye
			camLook = if camLook then camLook:Lerp(look, alpha) else look
			local nudge = Vector3.zero
			if stage == "wind" and os.clock() - lastPress < 0.08 then
				nudge = Vector3.new(0, 0.05, 0) -- a tiny kick on every wind
			end
			camera.CFrame = CFrame.lookAt((camEye :: Vector3) + nudge, camLook :: Vector3)
		end
	end)
end

return MechaMarathon

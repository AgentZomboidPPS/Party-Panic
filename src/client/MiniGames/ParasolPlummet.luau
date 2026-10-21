-- Client half of Parasol Plummet: everyone drifting down the sunny sky under their umbrella, the
-- throwers winding up on their bobbing clouds, every coin, bag and hammer flying on its arc, the side
-- camera, the DIVE button and the coin HUD.
--
-- The sky comes from MG_Sky (its middle and who flies where); the fallers from MG_Fallers (the
-- server's simulation, 10 times a second). Your own faller is predicted here with the server's own
-- step (Shared/Logic/ParasolPlummetSim) from the controls you press, so it answers your thumb at
-- once, and it eases onto the server's faller so the two never drift apart. Everyone else glides
-- smoothly between snapshots. Every participant's character (players and bots, via api:CharacterOf)
-- is set in its spot each frame, holding its umbrella overhead (open, or furled while diving), legs
-- swinging, twirling when a hammer bonks it; your own is moved for real, so the server sees you
-- where you fly.
--
-- Throws arrive as "Throw" events a wind-up before they leave the thrower's hand: the thrower leans
-- back with the coin, bag or hammer in hand, then flings it, and it flies on the exact arc the server
-- judges (Sim.ItemAt). "Take" pops a caught one (+1 / +5 over you when it's yours); "Bonk" knocks a
-- hammer off whoever it hit, with stars.
--
-- Review pass: a coin is drawn faded until it can be caught (Sim.Catchable: on its way down, in the
-- middle of the sky), a faller blinks through the second after a stun when no hammer can hit, the
-- body and umbrella lean only a little (the catch shapes stand upright), a hammer spins about the
-- middle of its head (where it's judged), the camera keeps the whole sky below the HUD, and an
-- unchanged Input is re-sent every RESEND seconds so a lost packet never leaves DIVE stuck.
--
-- Controls: steer with the MOVE stick, A/D or the arrows; hold DIVE (Space, S or the down arrow) to
-- shut the umbrella and drop, let go to float. Only changes are sent ("Input": steer, open).
-- The falling feel comes from cloud puffs streaming up past the sky at different depths (fewer with
-- reduced effects).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Sim = require(ReplicatedStorage.Shared.Logic.ParasolPlummetSim)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ParasolPlummet = {}

local rad = math.rad
local CAMERA_DISTANCE = 90
local VIEW_HALF_W = 50 -- the sky and both throwers' clouds
local SKY_TOP = Sim.Y_MAX + Sim.CANOPY_Y + Sim.CANOPY_H + 1.5 -- the highest canopy, and a little air
local SKY_BOTTOM = Sim.Y_MIN - 4.5 -- the lowest feet (and the lower throwers' clouds)
local HOLD_OFFSET = CFrame.new(0, Sim.UMBRELLA_BASE, -0.15)
local RESEND = 0.2 -- seconds between repeats of an unchanged Input
local FADED = 0.6 -- a coin's transparency while it can't be caught yet (still rising, or by a wall)

-- Each faller's colour, with a shape on their tag so colour is never the only cue.
local COLORS = {
	Color3.fromRGB(235, 70, 80),
	Color3.fromRGB(60, 140, 240),
	Color3.fromRGB(255, 200, 40),
	Color3.fromRGB(80, 200, 110),
	Color3.fromRGB(180, 100, 240),
	Color3.fromRGB(255, 140, 50),
	Color3.fromRGB(255, 120, 200),
	Color3.fromRGB(40, 200, 210),
	Color3.fromRGB(150, 220, 60),
	Color3.fromRGB(240, 240, 250),
	Color3.fromRGB(120, 90, 60),
	Color3.fromRGB(70, 70, 90),
}
local SHAPES = { "★", "●", "▲", "◆", "■", "♥", "♣", "♠", "✚", "☀", "☾", "✦" }

local JOINTS = {
	UpperTorso = "Waist",
	Head = "Neck",
	LeftUpperArm = "LeftShoulder",
	RightUpperArm = "RightShoulder",
	LeftLowerArm = "LeftElbow",
	RightLowerArm = "RightElbow",
	LeftUpperLeg = "LeftHip",
	RightUpperLeg = "RightHip",
	LeftLowerLeg = "LeftKnee",
	RightLowerLeg = "RightKnee",
}

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

-- A faller's pose: both hands up on the umbrella, legs swinging; diving pulls the legs together,
-- a bonk flails the arms.
local function fallPose(open: boolean, stunned: boolean, t: number, phase: number): { [string]: CFrame }
	local swing = math.sin(t * 2.4 + phase)
	if stunned then
		local flail = math.sin(t * 14 + phase) * 30
		return {
			Waist = angles(0, 0, math.sin(t * 9) * 10),
			Neck = angles(-10, 0, math.sin(t * 11) * 14),
			LeftShoulder = angles(flail, 0, -120),
			RightShoulder = angles(-flail, 0, 120),
			LeftElbow = angles(30, 0, 0),
			RightElbow = angles(30, 0, 0),
			LeftHip = angles(flail * 0.8, 0, -12),
			RightHip = angles(-flail * 0.8, 0, 12),
			LeftKnee = angles(-30, 0, 0),
			RightKnee = angles(-30, 0, 0),
		}
	end
	if not open then
		return {
			Waist = angles(0, 0, 0),
			Neck = angles(-8, 0, 0),
			LeftShoulder = angles(0, 0, -168),
			RightShoulder = angles(0, 0, 168),
			LeftElbow = angles(8, 0, 0),
			RightElbow = angles(8, 0, 0),
			LeftHip = angles(swing * 4, 0, 3),
			RightHip = angles(-swing * 4, 0, -3),
			LeftKnee = angles(-4, 0, 0),
			RightKnee = angles(-4, 0, 0),
		}
	end
	return {
		Waist = angles(4, 0, swing * 3),
		Neck = angles(6, 0, 0),
		LeftShoulder = angles(0, 0, -160),
		RightShoulder = angles(0, 0, 160),
		LeftElbow = angles(18, 0, 0),
		RightElbow = angles(18, 0, 0),
		LeftHip = angles(18 + swing * 16, 0, -6),
		RightHip = angles(18 - swing * 16, 0, 6),
		LeftKnee = angles(-30 - swing * 10, 0, 0),
		RightKnee = angles(-30 + swing * 10, 0, 0),
	}
end

type Visual = {
	UserId: number,
	Index: number,
	X: number,
	Y: number,
	VX: number,
	VY: number,
	Open: boolean,
	StunUntil: number,
	SafeUntil: number,
	Fade: number?,
	Coins: number,
	Umbrella: Model?,
	Shut: Model?,
	Tag: BillboardGui?,
	TagLabel: TextLabel?,
	Character: Model?,
	Seen: boolean,
}
type Flying = {
	Id: number,
	Kind: string,
	Thrower: number,
	At: number,
	X0: number,
	Y0: number,
	VX: number,
	VY: number,
	Model: Model?,
	Spin: number,
	Knocked: number?, -- when a hammer was knocked off someone (it tumbles away and fades)
	Faded: boolean?,
}

function ParasolPlummet.Start(api)
	local reduced = State.ReducedEffects()
	api:Mood({
		Tint = Color3.fromRGB(255, 250, 240),
		Saturation = 0.18,
		Brightness = 0.03,
		Haze = Color3.fromRGB(200, 228, 255),
		Density = 0.22,
	})
	local camera = workspace.CurrentCamera
	local myId = Players.LocalPlayer.UserId
	local touch = api:IsTouch()

	-- The sky -------------------------------------------------------------------------------------------

	local center: Vector3? = nil
	local visuals: { [number]: Visual } = {}
	local order: { number } = {}
	local function readSky()
		local sky = api:SharedJSON("Sky")
		if type(sky) ~= "table" or type(sky.O) ~= "table" or type(sky.P) ~= "table" then
			return
		end
		center = Vector3.new(sky.O[1] or 0, sky.O[2] or 0, sky.O[3] or 0)
		for _, entry in sky.P do
			local userId, index = tonumber(entry.U), tonumber(entry.I)
			if userId and index and not visuals[userId] then
				local x, y = Sim.StartAt(index, #sky.P)
				visuals[userId] = {
					UserId = userId,
					Index = index,
					X = x,
					Y = y,
					VX = 0,
					VY = 0,
					Open = true,
					StunUntil = 0,
					SafeUntil = 0,
					Coins = 0,
					Seen = false,
				}
				table.insert(order, userId)
			end
		end
	end
	api:OnShared("Sky", readSky)
	readSky()

	local snapshot: { [string]: any } = {}
	local snapshotT = 0
	local function readFallers()
		local value = api:SharedJSON("Fallers")
		if type(value) == "table" and type(value.F) == "table" then
			snapshot = value.F
			snapshotT = tonumber(value.T) or api:Now()
		end
	end
	api:OnShared("Fallers", readFallers)
	readFallers()

	local function world(x: number, y: number, depth: number): Vector3
		return (center :: Vector3) + Vector3.new(x, y, depth)
	end

	-- Templates (waited for in the background: a slow phone draws them when they arrive).
	local templates: { [string]: Model } = {}
	task.spawn(function()
		for _, name in
			{
				"ParasolPlummetUmbrella",
				"ParasolPlummetUmbrellaShut",
				"ParasolPlummetCoin",
				"ParasolPlummetBag",
				"ParasolPlummetHammer",
				"ParasolPlummetCloud",
			}
		do
			local template = api:Template(name, 30)
			if template and template:IsA("Model") then
				templates[name] = template
			end
		end
	end)
	local function copy(name: string): Model?
		local template = templates[name]
		if not template then
			return nil
		end
		local model = template:Clone()
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
		model.Parent = api.World
		return model
	end
	local function recolor(model: Model, color: Color3)
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "Canopy" then
				part.Color = color
			end
		end
	end

	-- My controls ---------------------------------------------------------------------------------------

	local controls = nil
	pcall(function()
		local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
		local module = playerScripts and playerScripts:FindFirstChild("PlayerModule")
		if module then
			controls = (require(module) :: any):GetControls()
		end
	end)
	local diveButton = false
	local diveKeys = 0
	local dive = api:Button({ Text = "DIVE", Key = Enum.KeyCode.Space, Color = Color3.fromRGB(60, 140, 240) })
	dive.Pressed:Connect(function()
		diveButton = true
	end)
	dive.Released:Connect(function()
		diveButton = false
	end)
	local DIVE_KEYS = { [Enum.KeyCode.S] = true, [Enum.KeyCode.Down] = true, [Enum.KeyCode.ButtonA] = true }
	api:Track(UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and DIVE_KEYS[input.KeyCode] then
			diveKeys += 1
		end
	end))
	api:Track(UserInputService.InputEnded:Connect(function(input)
		if DIVE_KEYS[input.KeyCode] then
			diveKeys = math.max(0, diveKeys - 1)
		end
	end))
	local function steerInput(): number
		local x = 0
		if controls then
			local ok, value = pcall(controls.GetMoveVector, controls)
			if ok and typeof(value) == "Vector3" then
				x = value.X
			end
		end
		return math.clamp(math.floor(x * 4 + 0.5) / 4, -1, 1)
	end

	local mine = { X = 0, Y = 0, VX = 0, VY = 0 }
	local mineReady = false
	local sentKey = ""
	local sentAt = 0
	local disagreeSince: number? = nil
	local myStunUntil = 0

	-- Flying things -------------------------------------------------------------------------------------

	local flying: { [number]: Flying } = {}
	local windups: { [number]: { At: number, Side: number } } = {}
	api:OnEvent("Throw", function(id, kind, thrower, at, x0, y0, vx, vy)
		if type(id) ~= "number" or Sim.Kinds[kind] == nil or type(at) ~= "number" then
			return
		end
		flying[id] = {
			Id = id,
			Kind = kind,
			Thrower = tonumber(thrower) or 1,
			At = at,
			X0 = tonumber(x0) or 0,
			Y0 = tonumber(y0) or 0,
			VX = tonumber(vx) or 0,
			VY = tonumber(vy) or 0,
			Spin = math.random() * math.pi * 2,
		}
		local _, _, side = Sim.ThrowerAt(tonumber(thrower) or 1, at)
		windups[tonumber(thrower) or 1] = { At = at, Side = side }
	end)

	-- Pop-ups ("+1", "+5", "BONK!") rising over a spot and fading.
	local popups: { { Gui: BillboardGui, Label: TextLabel, Born: number, Base: Vector3 } } = {}
	local popAnchor = Instance.new("Part")
	popAnchor.Name = "PopAnchor"
	popAnchor.Anchored = true
	popAnchor.CanCollide = false
	popAnchor.CanQuery = false
	popAnchor.CanTouch = false
	popAnchor.Transparency = 1
	popAnchor.Size = Vector3.one
	popAnchor.Parent = api.World
	local function popup(position: Vector3, text: string, color: Color3)
		if center and popAnchor.Position ~= center then
			popAnchor.Position = center -- (pop-ups hang off a point in the sky, not the world's origin)
		end
		local gui = Instance.new("BillboardGui")
		gui.Adornee = popAnchor
		gui.Size = UDim2.fromOffset(120, 50)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.StudsOffsetWorldSpace = position - popAnchor.Position
		gui.Parent = api.World
		local label = UIKit.Label({
			Text = text,
			Font = Theme.Fonts.Display,
			TextSize = 34,
			TextColor3 = color,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0.1) },
		})
		table.insert(popups, { Gui = gui, Label = label, Born = os.clock(), Base = position })
	end

	local shake = 0
	api:OnEvent("Take", function(id, userId, value)
		local item = flying[id]
		flying[id] = nil
		local position = nil
		if item then
			local x, y = Sim.ItemAt(item, api:Now())
			if center then
				position = world(x, y, 0)
			end
			if item.Model then
				item.Model:Destroy()
			end
		end
		if position then
			api:Effect("Sparkles", position)
		end
		if userId == myId then
			api:Sound("Pickup")
			local visual = visuals[myId]
			local spot = position
			if visual and center then
				spot = world(mine.X, mine.Y + 9.5, 0)
			end
			if spot then
				popup(spot, `+{tonumber(value) or 1}`, Theme.Colors.Yellow)
			end
		end
	end)
	api:OnEvent("Bonk", function(id, userId, stunUntil)
		local item = flying[id]
		local now = api:Now()
		local visual = visuals[userId]
		if visual and type(stunUntil) == "number" then
			visual.StunUntil = stunUntil
			visual.SafeUntil = stunUntil + Sim.SAFE
		end
		if item then
			-- The hammer bounces off and tumbles away.
			local x, y = Sim.ItemAt(item, now)
			item.X0, item.Y0 = x, y
			item.VX = -item.VX * 0.4
			item.VY = 9
			item.At = now
			item.Knocked = now
		end
		local spot = nil
		if visual and center then
			spot = world(visual.X, visual.Y + 3, 0)
			api:Effect("Stars", spot)
		end
		if userId == myId then
			myStunUntil = if type(stunUntil) == "number" then stunUntil else now + Sim.STUN
			api:Sound("Hit")
			shake = 0.45
			if spot then
				popup(spot + Vector3.new(0, 6, 0), "BONK!", Theme.Colors.Red)
			end
		end
	end)

	-- Throwers on their clouds (the server's models in the arena, bobbed here on the shared clock).
	local throwers: { [number]: { Holder: Model, Figure: Model?, Offset: CFrame? } } = {}
	task.spawn(function()
		local arena = api:Arena(15)
		if not arena then
			return
		end
		for index = 1, 4 do
			local holder = arena:WaitForChild(`Thrower{index}`, 10)
			if holder and holder:IsA("Model") then
				local figure = holder:FindFirstChild("ParasolPlummetThrower")
				local entry = { Holder = holder, Figure = nil :: Model?, Offset = nil :: CFrame? }
				if figure and figure:IsA("Model") then
					entry.Figure = figure
					entry.Offset = holder:GetPivot():ToObjectSpace(figure:GetPivot())
				end
				throwers[index] = entry
			end
		end
	end)

	-- Cloud puffs streaming up past the sky (the fall), at a few depths.
	local puffs: { { Model: Model?, X: number, Y: number, Z: number, Speed: number, Scale: number } } = {}
	local puffCount = if reduced then 4 else 10
	for index = 1, puffCount do
		local behind = index % 5 ~= 0
		table.insert(puffs, {
			Model = nil,
			X = if behind then math.random(-150, 150) else (if index % 2 == 0 then -1 else 1) * math.random(62, 90),
			Y = math.random(-80, 80),
			Z = if behind then -math.random(70, 150) else math.random(18, 30),
			Speed = if behind then math.random(16, 26) else math.random(30, 40),
			Scale = if behind then math.random(10, 18) / 10 else math.random(6, 9) / 10,
		})
	end

	-- HUD -----------------------------------------------------------------------------------------------

	local hud = api:TopHud()
	local hudY = api:HudY()
	local panel = UIKit.new("Frame", {
		Name = "Coins",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY),
		Size = UDim2.fromOffset(250, 50),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.25,
		Parent = hud,
		Children = { UIKit.Round(), UIKit.Stroke(Color3.new(1, 1, 1), 2, 0.4) },
	})
	UIKit.Coin({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		Parent = panel,
	})
	local coinsLabel = UIKit.Label({
		Name = "Count",
		Text = "0",
		Font = Theme.Fonts.Display,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 52, 0.5, 0),
		Size = UDim2.fromOffset(80, 44),
		Parent = panel,
		Children = { UIKit.TextStroke(0.2) },
	})
	local placeLabel = UIKit.Label({
		Name = "Place",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextColor3 = Theme.Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(110, 40),
		Parent = panel,
		Children = { UIKit.TextStroke(0.2) },
	})
	local function ordinal(n: number): string
		local tail = if n % 100 >= 11 and n % 100 <= 13
			then "th"
			elseif n % 10 == 1 then "st"
			elseif n % 10 == 2 then "nd"
			elseif n % 10 == 3 then "rd"
			else "th"
		return `{n}{tail}`
	end

	-- Name tags under each faller: shape, name and coins (yours says YOU).
	local function makeTag(visual: Visual, root: BasePart)
		if visual.Tag then
			visual.Tag.Adornee = root
			return
		end
		local isMe = visual.UserId == myId
		local gui = Instance.new("BillboardGui")
		gui.Name = "FallerTag"
		gui.Adornee = root
		gui.Size = UDim2.fromOffset(150, 26)
		gui.StudsOffsetWorldSpace = Vector3.new(0, -4.3, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 400
		gui.Parent = api.World
		local label = UIKit.Label({
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = if isMe then 22 else 17,
			TextColor3 = if isMe then Theme.Colors.Yellow else Color3.new(1, 1, 1),
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0.15) },
		})
		visual.Tag = gui
		visual.TagLabel = label
	end
	local function nameOf(userId: number): string
		for _, participant in api:Participants() do
			if participant.UserId == userId then
				local name = participant.DisplayName or ""
				return if #name > 10 then string.sub(name, 1, 9) .. "…" else name
			end
		end
		return ""
	end
	local names: { [number]: string } = {}

	-- Characters ------------------------------------------------------------------------------------------

	local rigs: { [Model]: { [string]: { Motor: Motor6D, Current: CFrame } } } = {}
	local function rigOf(character: Model): { [string]: { Motor: Motor6D, Current: CFrame } }
		local rig = rigs[character]
		if rig then
			return rig
		end
		rig = {}
		for partName, jointName in JOINTS do
			local part = character:FindFirstChild(partName)
			local motor = part and part:FindFirstChild(jointName)
			if motor and motor:IsA("Motor6D") then
				rig[jointName] = { Motor = motor, Current = CFrame.identity }
			end
		end
		rigs[character] = rig
		return rig
	end
	local hiddenNames: { [Humanoid]: Enum.HumanoidDisplayDistanceType } = {}
	local posed: { [Model]: Visual } = {}
	local poseConnection = (RunService :: any).PreSimulation or RunService.Stepped
	api:Track(poseConnection:Connect(function(dt)
		local now = api:Now()
		local step = if type(dt) == "number" then dt else 1 / 60
		local alpha = 1 - math.exp(-step * 14)
		for character, visual in posed do
			if not character.Parent then
				posed[character] = nil
				rigs[character] = nil
				continue
			end
			local target = fallPose(visual.Open, now < visual.StunUntil, now, visual.Index * 1.3)
			for name, joint in rigOf(character) do
				joint.Current = joint.Current:Lerp(target[name] or CFrame.identity, alpha)
				joint.Motor.Transform = joint.Current
			end
		end
	end))

	-- Camera --------------------------------------------------------------------------------------------

	local cameraTaken = false
	local cameraX = 0
	local viewY = (SKY_TOP + SKY_BOTTOM) / 2
	local viewHeight = SKY_TOP - SKY_BOTTOM + 20
	local function releaseCamera()
		if cameraTaken then
			cameraTaken = false
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
			local _, humanoid = api:Character()
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end
	api:Track(function()
		releaseCamera()
		for character, visual in posed do
			local rig = rigs[character]
			if rig then
				for _, joint in rig do
					joint.Motor.Transform = CFrame.identity
				end
			end
			if visual.Fade and visual.Fade ~= 0 then
				for _, part in character:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = 0
					end
				end
			end
		end
		for humanoid, kind in hiddenNames do
			if humanoid.Parent then
				humanoid.DisplayDistanceType = kind
			end
		end
		local _, humanoid, root = api:Character()
		if humanoid then
			humanoid.PlatformStand = false
		end
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)

	-- Every frame -----------------------------------------------------------------------------------------

	local hintUntil = 0
	local hintShown = false
	local lastPlace = ""
	local lastCoins = -1
	local diveShown = nil :: boolean?
	api:RenderStep(function(dt)
		if not center then
			return
		end
		dt = math.min(dt, 0.1)
		local now = api:Now()
		local go = api:Shared("Go")
		local started = type(go) == "number" and now >= go
		local over = api:Shared("Over") == true
		local amFaller = visuals[myId] ~= nil and api:Alive()

		-- My faller: predicted from my controls, eased onto the server's.
		local mineEntry = snapshot[tostring(myId)]
		if amFaller and mineEntry then
			local sx = (mineEntry.x or 0) + (mineEntry.vx or 0) * math.clamp(now - snapshotT, 0, 0.3)
			local sy = (mineEntry.y or 0) + (mineEntry.vy or 0) * math.clamp(now - snapshotT, 0, 0.3)
			sx = math.clamp(sx, -Sim.HALF_W, Sim.HALF_W)
			sy = math.clamp(sy, Sim.Y_MIN, Sim.Y_MAX)
			if type(mineEntry.st) == "number" then
				myStunUntil = math.max(myStunUntil, mineEntry.st)
			end
			if not mineReady then
				mineReady = true
				mine.X, mine.Y, mine.VX, mine.VY = sx, sy, mineEntry.vx or 0, mineEntry.vy or 0
			end
			local steer = steerInput()
			local open = not (diveButton or diveKeys > 0)
			if started and not over then
				local left = dt
				while left > 1e-4 do
					local h = math.min(left, 1 / 30)
					left -= h
					Sim.Step(mine, steer, open, now < myStunUntil, h)
				end
				-- Sent on every change, and again every RESEND while held (a dropped packet must never
				-- leave DIVE or a steer stuck), and at once when the server's umbrella disagrees.
				local key = `{steer}:{open}`
				local serverOpen = mineEntry.o == 1
				if serverOpen == open or now < myStunUntil then
					disagreeSince = nil
				elseif not disagreeSince then
					disagreeSince = os.clock()
				end
				local stale = disagreeSince ~= nil and os.clock() - disagreeSince > 0.3
				local clock = os.clock()
				if
					(key ~= sentKey and clock - sentAt >= 0.02)
					or clock - sentAt >= RESEND
					or (stale and clock - sentAt >= 0.1)
				then
					sentKey = key
					sentAt = clock
					api:Action("Input", steer, open)
				end
			end
			local ex, ey = sx - mine.X, sy - mine.Y
			if math.abs(ex) > 7 or math.abs(ey) > 7 or not started or over then
				local snap = if started and not over then 1 else 1 - math.exp(-dt * 6)
				mine.X += ex * snap
				mine.Y += ey * snap
			else
				local ease = 1 - math.exp(-dt * 2.5)
				mine.X += ex * ease
				mine.Y += ey * ease
			end
		end

		-- Every faller: glide to the server's (mine: the prediction), place and pose the character.
		local places = {}
		for _, userId in order do
			local visual = visuals[userId]
			local entry = snapshot[tostring(userId)]
			if not entry then
				-- Left the round: hide what was theirs.
				if visual.Umbrella then
					visual.Umbrella.Parent = nil
				end
				if visual.Shut then
					visual.Shut.Parent = nil
				end
				if visual.Tag then
					visual.Tag.Enabled = false
				end
				continue
			end
			visual.Coins = tonumber(entry.c) or 0
			table.insert(places, { UserId = userId, Coins = visual.Coins })
			if type(entry.st) == "number" then
				visual.StunUntil = math.max(visual.StunUntil, entry.st)
			end
			if type(entry.sf) == "number" then
				visual.SafeUntil = math.max(visual.SafeUntil, entry.sf)
			end
			if userId == myId and amFaller and mineReady then
				visual.X, visual.Y, visual.VX, visual.VY = mine.X, mine.Y, mine.VX, mine.VY
				visual.Open = not (diveButton or diveKeys > 0) and now >= myStunUntil and not over
				if over then
					visual.Open = entry.o == 1
				end
			else
				local ahead = math.clamp(now - snapshotT, 0, 0.3)
				local tx = math.clamp((entry.x or 0) + (entry.vx or 0) * ahead, -Sim.HALF_W, Sim.HALF_W)
				local ty = math.clamp((entry.y or 0) + (entry.vy or 0) * ahead, Sim.Y_MIN, Sim.Y_MAX)
				if not visual.Seen or math.abs(tx - visual.X) > 12 or math.abs(ty - visual.Y) > 12 then
					visual.X, visual.Y = tx, ty
				else
					local ease = 1 - math.exp(-dt * 10)
					visual.X += (tx - visual.X) * ease
					visual.Y += (ty - visual.Y) * ease
				end
				visual.VX, visual.VY = entry.vx or 0, entry.vy or 0
				visual.Open = entry.o == 1 and now >= visual.StunUntil
			end
			visual.Seen = true

			local stunned = now < visual.StunUntil
			local bob = if visual.Open then math.sin(now * 1.7 + visual.Index) * 0.25 else 0
			local position = world(visual.X, visual.Y + bob, Sim.Depth(visual.Index))
			-- (A small lean only: the catch shapes stand upright, so the drawn umbrella must too.)
			local lean = math.clamp(-visual.VX * 0.004, -Sim.MAX_LEAN, Sim.MAX_LEAN)
			local spin = if stunned then (visual.StunUntil - now) / Sim.STUN * math.pi * 4 else 0
			local frame = CFrame.lookAt(position, position + Vector3.zAxis) * CFrame.Angles(0, spin, lean)

			-- The umbrella, open or furled, in this faller's colour.
			if not visual.Umbrella then
				local umbrella = copy("ParasolPlummetUmbrella")
				local shut = copy("ParasolPlummetUmbrellaShut")
				if umbrella and shut then
					local color = COLORS[(visual.Index - 1) % #COLORS + 1]
					recolor(umbrella, color)
					recolor(shut, color)
					visual.Umbrella, visual.Shut = umbrella, shut
				elseif umbrella then
					umbrella:Destroy()
				elseif shut then
					shut:Destroy()
				end
			end
			local held = frame * HOLD_OFFSET * CFrame.Angles(0, now * (if visual.Open then 0.6 else 0), 0)
			if visual.Umbrella and visual.Shut then
				local showing, hidden = visual.Umbrella, visual.Shut
				if not visual.Open then
					showing, hidden = visual.Shut, visual.Umbrella
				end
				-- Blinking through the second after a stun when no hammer can hit (Sim.SAFE).
				local blink = not stunned and now < visual.SafeUntil and math.floor(now * 10) % 2 == 0
				hidden.Parent = nil
				showing.Parent = if blink then nil else api.World
				showing:PivotTo(held)
			end

			local character = api:CharacterOf(userId)
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if character and root then
				if not posed[character] then
					posed[character] = visual
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid and hiddenNames[humanoid] == nil then
						hiddenNames[humanoid] = humanoid.DisplayDistanceType
						humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					end
				end
				if userId == myId then
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid and not humanoid.PlatformStand then
						humanoid.PlatformStand = true
					end
					root.AssemblyLinearVelocity = Vector3.new(visual.VX, visual.VY, 0)
					root.AssemblyAngularVelocity = Vector3.zero
				end
				root.CFrame = frame
				makeTag(visual, root)
				local fade = if not stunned and now < visual.SafeUntil and math.floor(now * 10) % 2 == 0 then 0.6 else 0
				if visual.Fade ~= fade then
					visual.Fade = fade
					for _, part in character:GetDescendants() do
						if part:IsA("BasePart") then
							part.LocalTransparencyModifier = fade
						end
					end
				end
			end
			if visual.TagLabel then
				local name = names[userId]
				if not name or name == "" then
					name = nameOf(userId)
					names[userId] = name
				end
				local shape = SHAPES[(visual.Index - 1) % #SHAPES + 1]
				local text = if userId == myId then `{shape} YOU  {visual.Coins}` else `{shape} {name}  {visual.Coins}`
				if visual.TagLabel.Text ~= text then
					visual.TagLabel.Text = text
				end
				if visual.Tag then
					visual.Tag.Enabled = true
				end
			end
		end

		-- Throwers bob; one about to throw leans back, then flings.
		for index, entry in throwers do
			local x, y = Sim.ThrowerAt(index, now)
			local base = CFrame.new(world(x, y, 0))
			entry.Holder:PivotTo(base)
			local windup = windups[index]
			if entry.Figure and entry.Offset and windup then
				local t = now - (windup.At - Sim.WINDUP)
				local tilt = 0
				if t >= 0 and t < Sim.WINDUP then
					tilt = -(t / Sim.WINDUP) * rad(28)
				elseif t >= Sim.WINDUP and t < Sim.WINDUP + 0.35 then
					tilt = rad(28) * math.sin((t - Sim.WINDUP) / 0.35 * math.pi)
				end
				-- Leaning toward the middle of the sky: its own side decides which way that is.
				entry.Figure:PivotTo(base * CFrame.Angles(0, 0, tilt * windup.Side) * entry.Offset)
			end
		end

		-- Thrown things: in the thrower's hand during the wind-up, then on their arc.
		for id, item in flying do
			if item.Knocked then
				if now - item.Knocked > 1.2 then
					if item.Model then
						item.Model:Destroy()
					end
					flying[id] = nil
					continue
				end
			elseif Sim.Gone(item, now) then
				if item.Model then
					item.Model:Destroy()
				end
				flying[id] = nil
				continue
			end
			if not item.Model then
				item.Model = copy(`ParasolPlummet{item.Kind}`)
				if not item.Model then
					continue
				end
			end
			local x, y
			if now < item.At and not item.Knocked then
				local cx, cy, side = Sim.ThrowerAt(item.Thrower, now)
				local hx, hy = Sim.HandOffset(side)
				x, y = cx + hx, cy + hy
			else
				x, y = Sim.ItemAt(item, now)
			end
			local middle = Sim.Kinds[item.Kind].Middle
			if item.Kind ~= "Hammer" then
				-- Faded until it can be caught, so what looks catchable is catchable.
				local faded = not item.Knocked and not Sim.Catchable(item, now)
				if item.Faded ~= faded then
					item.Faded = faded
					for _, part in item.Model:GetDescendants() do
						if part:IsA("BasePart") then
							part.Transparency = if faded then FADED else 0
						end
					end
				end
			end
			local turn
			if item.Kind == "Hammer" then
				turn = CFrame.Angles(0, 0, item.Spin + now * (if item.Knocked then 14 else 8) * -math.sign(item.VX))
			elseif item.Kind == "Bag" then
				turn = CFrame.Angles(0, 0, math.sin(now * 3 + item.Spin) * 0.35)
			else
				turn = CFrame.Angles(0, item.Spin + now * 5, 0)
			end
			item.Model:PivotTo(CFrame.new(world(x, y, 0)) * turn * CFrame.new(0, -middle, 0))
		end

		-- Cloud puffs.
		for _, puff in puffs do
			if not puff.Model then
				puff.Model = copy("ParasolPlummetCloud")
				if puff.Model then
					puff.Model:ScaleTo(puff.Model:GetScale() * puff.Scale)
					if puff.Z > 0 then
						for _, part in puff.Model:GetDescendants() do
							if part:IsA("BasePart") then
								part.Transparency = 0.45
							end
						end
					end
				end
			end
			puff.Y += puff.Speed * dt
			if puff.Y > 85 then
				puff.Y = -85
				puff.X = math.random(-150, 150)
				if puff.Z > 0 then
					-- (In front of the sky only off to the sides: never over a faller.)
					puff.X = (if math.random() < 0.5 then -1 else 1) * math.random(60, 90)
				end
			end
			if puff.Model then
				puff.Model:PivotTo(CFrame.new(world(puff.X, puff.Y, puff.Z)))
			end
		end

		-- Pop-ups.
		for index = #popups, 1, -1 do
			local pop = popups[index]
			local age = os.clock() - pop.Born
			if age > 0.9 then
				pop.Gui:Destroy()
				table.remove(popups, index)
			else
				pop.Gui.StudsOffsetWorldSpace = pop.Base + Vector3.new(0, age * 4, 0) - popAnchor.Position
				pop.Label.TextTransparency = math.max(0, (age - 0.5) / 0.4)
			end
		end

		-- The side camera: the whole sky, drifting a little after me.
		if amFaller then
			if not cameraTaken then
				cameraTaken = true
				camera.CameraType = Enum.CameraType.Scriptable
			end
			cameraX += ((if mineReady then mine.X * 0.12 else 0) - cameraX) * (1 - math.exp(-dt * 2))
			shake = math.max(0, shake - dt)
			local jolt = if shake > 0
				then Vector3.new(math.sin(now * 71), math.sin(now * 83), 0) * shake * 1.2
				else Vector3.zero
			-- Framed so the whole sky (canopies at the top, feet at the bottom) sits below the HUD (the
			-- banner, status line, coin panel and the leaderboard beside them), and both throwers fit.
			local viewport = camera.ViewportSize
			local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
			local hudBottom = viewport.Y * (if touch then 0.32 else 0.22)
			if panel.Visible and panel.AbsoluteSize.Y > 0 then
				hudBottom = panel.AbsolutePosition.Y + panel.AbsoluteSize.Y + GuiService:GetGuiInset().Y + 26
			end
			local p0 = math.clamp(hudBottom / math.max(viewport.Y, 1), 0.08, 0.45)
			local height = math.max((SKY_TOP - SKY_BOTTOM) / (1 - p0), 2 * VIEW_HALF_W / aspect)
			viewY += ((SKY_TOP - (0.5 - p0) * height) - viewY) * (1 - math.exp(-dt * 4))
			viewHeight += (height - viewHeight) * (1 - math.exp(-dt * 4))
			local look = world(cameraX, viewY, 0)
			camera.FieldOfView = math.deg(2 * math.atan(viewHeight / 2 / CAMERA_DISTANCE))
			camera.CFrame = CFrame.lookAt(look + Vector3.new(0, 0, CAMERA_DISTANCE) + jolt, look + jolt)
		else
			releaseCamera()
		end

		-- HUD: my coins and place.
		local visual = visuals[myId]
		panel.Visible = visual ~= nil and snapshot[tostring(myId)] ~= nil
		if visual then
			if visual.Coins ~= lastCoins then
				lastCoins = visual.Coins
				coinsLabel.Text = tostring(visual.Coins)
				if lastCoins > 0 then
					UIKit.PopIn(coinsLabel, 0.15)
				end
			end
			local better = 0
			local tied = false
			for _, entry in places do
				if entry.UserId ~= myId then
					if entry.Coins > visual.Coins then
						better += 1
					elseif entry.Coins == visual.Coins then
						tied = true
					end
				end
			end
			local place = if #places <= 1 then "" else `{if tied then "=" else ""}{ordinal(better + 1)}`
			if place ~= lastPlace then
				lastPlace = place
				placeLabel.Text = place
			end
		end

		-- The controls hint for the first seconds after GO.
		if started and not hintShown and amFaller then
			hintShown = true
			hintUntil = now + 7
			api:Hint(
				if touch then "Steer with the stick • hold DIVE to drop" else "A/D to steer • hold SPACE to drop",
				hudY + 60
			)
		elseif hintShown and hintUntil > 0 and now >= hintUntil then
			hintUntil = 0
			api:Hint("")
		end
		local diveWanted = amFaller and not over
		if diveWanted ~= diveShown then
			diveShown = diveWanted
			dive:SetVisible(diveWanted)
		end
	end)
end

return ParasolPlummet

-- Client half of Minecart Mayhem: every rider's cart rolling down the mine, your own character
-- standing in yours, the chase camera, the LEFT / RIGHT / JUMP controls, the progress strip, the
-- next switch's two ways, and the JUMP and LEAN prompts with their countdown rings.
--
-- The course comes from MG_Layout (Shared/Logic/MinecartMayhemTrack builds the same rails the
-- server rides on). Every cart follows MG_Riders (its tile, way and distance with the server's time,
-- carried on and eased so it never jumps). Your own cart is also ridden here with the same rules
-- (Track.Ride) from the server's last snapshot and what you're pressing right now, so it answers your
-- thumb at once: it takes the way you picked the moment it reaches a switch (Track.Choose with your
-- own presses), jumps the moment you press JUMP, and falls when your jump wouldn't carry it over a
-- gap (Track.Clears: the server judges your press by the same rule, with the moment you pressed it).
-- The server's word ("Way", "Cleared", "Fall") settles anything it saw differently.
--
-- Every rider's character (players and bots, via api:CharacterOf) is stood in its cart here each
-- frame and posed (hands on the rim, leaning with the cart, arms up in a jump); your own is moved
-- for real, so the server and everyone else see you where you ride. Carts side by side on the same
-- rails shift sideways so nobody hides anybody, and carts right next to yours turn see-through.
--
-- Controls: PC, A / D or the arrow keys to pick a way and lean, Space to JUMP. Phones: two big
-- ◀ ▶ pads just right of the middle (clear of the MOVE stick's half; the stick pushed left or right
-- leans too), JUMP beside the jump button (the jump button jumps too).
--
-- Sweep pass (owner: "Let's do a full bug and clean sweep."): only icons every device draws. On a
-- real Roblox server ★ measures as the missing-glyph box in FredokaOne and Builder Sans (it showed
-- only where a device's own fallback fonts had it) and ✖ comes from the emoji font as a dark grey
-- cross that the dark panels swallow: FAST is ⭐ and DEAD END / WOBBLE ❌ now. ◀ ▶ ● measure as
-- real glyphs in those fonts, so they stay.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local RaceBar = require(ReplicatedStorage.Shared.Logic.RaceBar)
local Track = require(ReplicatedStorage.Shared.Logic.MinecartMayhemTrack)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local MinecartMayhem = {}

local CART_FLOOR = 1.15 -- the cart's floor above the rails' top
local SEAT_DROP = 0.5 -- a rider stands this much lower in the cart than on the ground
local COAST = 18 -- how far a finished cart rolls on past the line
local SPREAD = 1.5 -- sideways studs between carts side by side
local RING_DOTS = 12
local rad = math.rad

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
local R6_JOINTS = { "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" }

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

-- A rider's pose in the cart: knees bent, hands on the rim in front; `lean` tilts the body into a
-- bend, `air` throws the arms up, `flail` (off the rails) waves them about, `cheer` after the finish.
local function ridePose(lean: number, air: number, flail: boolean, cheer: boolean, t: number)
	local up = if cheer then 150 + math.sin(t * 9) * 14 elseif flail then 120 + math.sin(t * 16) * 40 else air * 130
	local reach = 42 * (1 - math.min(1, up / 100))
	return {
		Waist = angles(-8, 0, -lean * 14),
		Neck = angles(4, 0, lean * 6),
		LeftShoulder = angles(reach + up, 0, 8),
		RightShoulder = angles(reach + up, 0, -8),
		LeftElbow = angles(20, 0, 0),
		RightElbow = angles(20, 0, 0),
		LeftHip = angles(40, 0, -4),
		RightHip = angles(40, 0, 4),
		LeftKnee = angles(-60, 0, 0),
		RightKnee = angles(-60, 0, 0),
		-- R6: each limb swings about its joint's Z axis (forward is + on the right, - on the left).
		["Right Shoulder"] = angles(0, 0, 50 + up * 0.9),
		["Left Shoulder"] = angles(0, 0, -50 - up * 0.9),
		["Right Hip"] = angles(0, 0, 25),
		["Left Hip"] = angles(0, 0, -25),
	}
end

type Shown = {
	Pos: Vector3?,
	Rot: CFrame,
	V: number,
	Shift: number,
	Roll: number,
	Model: Model?,
	Faded: boolean,
	Frame: CFrame?,
}

function MinecartMayhem.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(235, 228, 255),
		Saturation = 0.15,
		Contrast = 0.08,
		Brightness = 0,
		Haze = Color3.fromRGB(70, 60, 110),
		HazeDecay = Color3.fromRGB(40, 30, 70),
		Density = 0.32,
	})
	local mood = Lighting:FindFirstChild("MiniGameMood") :: ColorCorrectionEffect?
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

	local myId = Players.LocalPlayer.UserId
	local myKey = tostring(myId)
	local camera = workspace.CurrentCamera
	local touch = api:IsTouch()
	local reduced = State.ReducedEffects()

	local origin: Vector3? = nil
	local course: Track.Course? = nil
	local riders: { [string]: { L: number, C: Color3, N: string } } = {}
	local snapshot: { T: number, R: { [string]: any } } = { T = 0, R = {} }
	local shown: { [string]: Shown } = {}
	local stage = api:Shared("Stage") or "Ready"
	api:OnShared("Stage", function(value)
		stage = value or stage
	end)

	local function readLayout()
		local value = api:SharedJSON("Layout")
		if type(value) ~= "table" or type(value.O) ~= "table" or type(value.Tiles) ~= "table" then
			return
		end
		origin = Vector3.new(value.O[1], value.O[2], value.O[3])
		course = Track.Build(value.Tiles)
		for _, entry in value.Riders or {} do
			local c = entry.C or { 255, 255, 255 }
			riders[tostring(entry.U)] = { L = entry.L or 1, C = Color3.fromRGB(c[1], c[2], c[3]), N = entry.N or "" }
		end
	end
	readLayout()
	api:OnShared("Layout", readLayout)

	-- Where a cart is: the world frame on its rails (with the start lane's glide on the station).
	local function railFrame(tileIndex: number, branch: number, s: number, lane: number?): CFrame?
		local c, o = course, origin
		if not c or not o then
			return nil
		end
		local tile = c.Tiles[tileIndex]
		if not tile then
			return nil
		end
		local path = tile.Paths[branch] or tile.Paths[1]
		local x, y, z, hx, hy, hz = Track.At(path, s)
		local position = o + Vector3.new(x, y, z)
		local frame = CFrame.lookAt(position, position + Vector3.new(hx, hy, hz))
		if lane and tileIndex == 1 then
			frame = CFrame.new(position + frame.RightVector * Track.StartOffset(lane, s)) * frame.Rotation
		end
		return frame
	end

	-- My own ride ------------------------------------------------------------------------------------
	-- Predicted from the last snapshot with what I'm pressing now. My own presses (with their
	-- moments) decide my ways and jumps the way the server will; its word settles the rest.

	local myLean = 0
	local myJumpAt = -math.huge
	local myPicks: { Track.Pick } = {}
	local myWays: { [number]: number } = {} -- tile -> the way I took there (mine, then the server's)
	local myGaps: { [number]: number } = {} -- tile -> when my cart fell into its gap here (not yet settled)
	local zoneAt: { [number]: number } = {}
	local mine: Track.Rider? = nil
	local called: { [string]: boolean } = {} -- callouts already shown (by what and where)

	local say: (text: string, color: Color3, seconds: number) -> () = function() end

	local function rideMine(rider: Track.Rider, dt: number, now: number, live: boolean)
		local c = course
		if not c then
			return
		end
		local events = Track.Ride(c, rider, dt, now)
		local index, away = Track.NextSwitch(c, rider, Track.CHOOSE)
		if index and zoneAt[index] == nil then
			zoneAt[index] = now - math.max(0, Track.CHOOSE - away) / math.max(rider.V, 1)
		end
		for _, event in events do
			local tile = c.Tiles[event.Tile]
			if event.K == "Switch" then
				local way = myWays[event.Tile]
				if way == nil then
					way = Track.BranchFor(tile, Track.Choose(myPicks, zoneAt[event.Tile] or event.At, event.At))
					myWays[event.Tile] = way
				end
				rider.B = way
				if live and way == 2 and tile.O == "Short" and not called["short" .. event.Tile] then
					called["short" .. event.Tile] = true
					say("⭐ SHORTCUT!", Theme.Colors.Yellow, 1.2)
				end
			elseif event.K == "Gap" then
				local fell = myGaps[event.Tile]
				if fell and math.abs(event.At - fell) > 0.5 then
					fell = nil -- (an earlier try at this gap: this is a fresh one)
					myGaps[event.Tile] = nil
				end
				if fell == nil and not Track.Clears(myJumpAt, event.At, event.V, event.Gap or 8) then
					fell = event.At
					myGaps[event.Tile] = fell
				end
				if fell then
					Track.Fall(c, rider, event.Tile, fell)
				elseif live and not called["clear" .. event.Tile] then
					called["clear" .. event.Tile] = true
					say("✔ CLEARED!", Theme.Colors.Green, 0.9)
				end
			elseif event.K == "Crystal" then
				if not Track.Airborne(myJumpAt, event.At) then
					rider.DashUntil = event.At + Track.DASH_TIME
				end
			end
		end
	end

	local function readRiders()
		local value = api:SharedJSON("Riders")
		if type(value) ~= "table" or type(value.R) ~= "table" then
			return
		end
		snapshot = { T = tonumber(value.T) or api:Now(), R = value.R }
		local entry = value.R[myKey]
		local c = course
		if not entry or not c then
			mine = nil
			return
		end
		local now = api:Now()
		local rider: Track.Rider = {
			Tile = entry.T or 1,
			B = entry.B or 1,
			S = entry.S or 0,
			V = entry.V or 0,
			Lean = myLean,
			JumpAt = if entry.J and entry.J > myJumpAt - 0.3 then math.max(entry.J, myJumpAt) else myJumpAt,
			DashUntil = entry.Da or 0,
			DownUntil = entry.Dn or 0,
			Back = entry.Bk == 1,
			Finish = if entry.E then entry.E else nil,
			ReTile = entry.Rt,
			ReS = entry.Rs,
		}
		-- (a way I already took here, before the server's judge reached this snapshot)
		local tile = c.Tiles[rider.Tile]
		local way = myWays[rider.Tile]
		if tile and tile.SplitS and way and rider.B == 1 and rider.S > tile.SplitS and not rider.Back then
			rider.B = way
		end
		-- (a fall I already saw here, before the server's word on it)
		local fell = myGaps[rider.Tile]
		if fell and rider.DownUntil == 0 and now - fell < Track.COMEBACK then
			Track.Fall(c, rider, rider.Tile, fell)
		end
		if stage == "Race" and not rider.Finish then
			local behind = math.clamp(now - snapshot.T, 0, 0.5)
			local steps = math.ceil(behind / (1 / 30))
			for k = 1, steps do
				local step = behind / steps
				rideMine(rider, step, now - behind + k * step, false)
			end
		end
		mine = rider
	end
	readRiders()
	api:OnShared("Riders", readRiders)

	-- Carts --------------------------------------------------------------------------------------------

	local template = nil :: Instance?
	task.spawn(function()
		template = api:Template("MinecartMayhemCart", 30)
	end)
	local function cartFor(key: string, info): Model?
		local entry = shown[key]
		if entry and entry.Model then
			return entry.Model
		end
		if not template then
			return nil
		end
		local model = (template :: Instance):Clone() :: Model
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				if part.Name == "Trim" then
					part.Color = info.C
				elseif part.Name == "Badge" then
					local gui = Instance.new("SurfaceGui")
					gui.Face = Enum.NormalId.Back
					gui.CanvasSize = Vector2.new(100, 100)
					gui.LightInfluence = 0
					gui.Parent = part
					local label = Instance.new("TextLabel")
					label.Size = UDim2.fromScale(1, 1)
					label.BackgroundColor3 = info.C
					label.BackgroundTransparency = 0
					label.Text = tostring(info.L)
					label.TextScaled = true
					label.Font = Enum.Font.FredokaOne
					label.TextColor3 = Color3.fromRGB(30, 24, 40)
					label.Parent = gui
					local corner = Instance.new("UICorner")
					corner.CornerRadius = UDim.new(0.5, 0)
					corner.Parent = label
				end
			end
		end
		model.Name = "Cart_" .. key
		model.Parent = api.World
		if entry then
			entry.Model = model
		end
		return model
	end
	local function fade(entry: Shown, on: boolean)
		if entry.Faded == on or not entry.Model then
			return
		end
		entry.Faded = on
		for _, part in (entry.Model :: Model):GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = if on then 0.55 else 0
			end
		end
	end

	-- Posing riders -----------------------------------------------------------------------------------

	local rigs: { [Model]: { [string]: { Motor: Motor6D, Current: CFrame } } } = {}
	local posed: { [Model]: string } = {}
	local function rigOf(character: Model)
		local rig = rigs[character]
		if rig then
			return rig
		end
		rig = {}
		for partName, motorName in JOINTS do
			local part = character:FindFirstChild(partName)
			local motor = part and part:FindFirstChild(motorName)
			if motor and motor:IsA("Motor6D") then
				rig[motorName] = { Motor = motor, Current = CFrame.identity }
			end
		end
		local torso = character:FindFirstChild("Torso")
		for _, motorName in R6_JOINTS do
			local motor = torso and torso:FindFirstChild(motorName)
			if motor and motor:IsA("Motor6D") then
				rig[motorName] = { Motor = motor, Current = CFrame.identity }
			end
		end
		rigs[character] = rig
		return rig
	end
	local function unpose(character: Model)
		local rig = rigs[character]
		if rig then
			for _, joint in rig do
				joint.Motor.Transform = CFrame.identity
			end
		end
		rigs[character] = nil
		posed[character] = nil
	end
	local poses: { [string]: { Lean: number, Air: number, Flail: boolean, Cheer: boolean } } = {}
	local poseConnection = (RunService :: any).PreSimulation or RunService.Stepped
	api:Track(poseConnection:Connect(function(dt)
		local now = api:Now()
		local step = if type(dt) == "number" then dt else 1 / 60
		local alpha = 1 - math.exp(-step * 14)
		for character, key in posed do
			if not character.Parent then
				posed[character] = nil
				rigs[character] = nil
				continue
			end
			local pose = poses[key]
			if not pose then
				continue
			end
			local target = ridePose(pose.Lean, pose.Air, pose.Flail, pose.Cheer, now)
			for name, joint in rigOf(character) do
				joint.Current = joint.Current:Lerp(target[name] or CFrame.identity, alpha)
				joint.Motor.Transform = joint.Current
			end
		end
	end))

	-- HUD ----------------------------------------------------------------------------------------------

	local hud = api:TopHud()
	local hudY = api:HudY()
	local barWidth = 560
	local trackLength = barWidth - 64
	local DOT = if touch then 30 else 18
	local MY_DOT = if touch then 36 else 26
	local LIFT = if touch then 15 else 9
	local barHeight = if touch then 60 else 36
	local shiftX = if touch then 100 else 0 -- (phones: right of the middle, clear of the stick's corner)
	local bar = UIKit.Panel({
		Name = "RaceBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY + 4),
		Size = UDim2.fromOffset(barWidth, barHeight),
		CornerRadius = 15,
		Parent = hud,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local lane = UIKit.new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -64, 0, 8),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = bar,
		Children = { UIKit.Round() },
	})
	UIKit.Label({
		Name = "Goal",
		Text = "☀️",
		TextSize = if touch then 24 else 22,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 4, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		Parent = lane,
	})
	local markers: { [string]: Frame } = {}
	local myGlow: Frame? = nil
	local function marker(key: string): Frame
		local existing = markers[key]
		if existing then
			return existing
		end
		local info = riders[key]
		local isMine = key == myKey
		local size = if isMine then MY_DOT else DOT
		local dot = UIKit.new("Frame", {
			Name = "Rider" .. key,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = if info then info.C else Theme.Colors.Text,
			ZIndex = if isMine then 5 else 3,
			Parent = lane,
			Children = {
				UIKit.Round(),
				if isMine
					then UIKit.Stroke(Theme.Colors.Text, if touch then 4 else 3, 0)
					else UIKit.Stroke(Theme.Colors.PanelDark, 2, 0.3),
			},
		})
		if isMine then
			myGlow = UIKit.new("Frame", {
				Name = "MyGlow",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(size + 10, size + 10),
				BackgroundColor3 = Theme.Colors.Text,
				BackgroundTransparency = 0.55,
				ZIndex = 2,
				Parent = lane,
				Children = { UIKit.Round() },
			})
		end
		UIKit.Label({
			Text = tostring(if info then info.L else "?"),
			TextSize = if touch then (if isMine then 26 else 24) else (if isMine then 16 else 12),
			Font = Theme.Fonts.Bold,
			TextColor3 = Color3.fromRGB(30, 24, 40),
			Size = UDim2.fromScale(1, 1),
			ZIndex = dot.ZIndex,
			Parent = dot,
		})
		markers[key] = dot
		return dot
	end

	local placeY = hudY + barHeight + 8
	local placeLabel = UIKit.Label({
		Name = "Place",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, shiftX, 0, placeY),
		Size = UDim2.fromOffset(300, 32),
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})

	-- The next switch: both ways side by side (arrow, icon, word), the one I'm picking lit up, and a
	-- countdown ring between them.
	local wayY = placeY + 38
	local wayHeight = if touch then 62 else 54
	local wayPanel = UIKit.new("Frame", {
		Name = "Ways",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, shiftX, 0, wayY),
		Size = UDim2.fromOffset(if touch then 470 else 430, wayHeight),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud,
	})
	local HINTS = {
		Long = { Icon = "●", Word = "SAFE", Color = Color3.fromRGB(120, 200, 255) },
		Short = { Icon = "⭐", Word = "FAST", Color = Color3.fromRGB(255, 215, 80) },
		Dead = { Icon = "❌", Word = "DEAD END", Color = Color3.fromRGB(230, 230, 230) },
		TNT = { Icon = "☠", Word = "TNT", Color = Color3.fromRGB(255, 90, 70) },
	}
	local wayBoxes = {}
	for _, side in { -1, 1 } do
		local boxFrame = UIKit.Panel({
			Name = if side < 0 then "Left" else "Right",
			AnchorPoint = Vector2.new(if side < 0 then 0 else 1, 0),
			Position = UDim2.fromScale(if side < 0 then 0 else 1, 0),
			Size = UDim2.new(0.5, -34, 1, 0),
			CornerRadius = 12,
			Parent = wayPanel,
		}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
		local stroke = UIKit.Stroke(Theme.Colors.Text, 4, 1)
		stroke.Parent = boxFrame
		local label = UIKit.Label({
			Name = "Text",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = if touch then 28 else 24,
			Size = UDim2.new(1, -8, 1, 0),
			Position = UDim2.fromOffset(4, 0),
			Parent = boxFrame,
			Children = { UIKit.TextStroke(0.2) },
		})
		wayBoxes[side] = { Frame = boxFrame, Stroke = stroke, Label = label }
	end
	local function ring(parent: Instance, size: number, name: string)
		local holder = UIKit.new("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			Parent = parent,
		})
		local dots = {}
		for k = 1, RING_DOTS do
			local a = (k - 1) / RING_DOTS * math.pi * 2
			table.insert(
				dots,
				UIKit.new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5 + 0.42 * math.sin(a), 0, 0.5 - 0.42 * math.cos(a), 0),
					Size = UDim2.fromOffset(math.floor(size * 0.16), math.floor(size * 0.16)),
					BackgroundColor3 = Theme.Colors.Text,
					Parent = holder,
					Children = { UIKit.Round() },
				})
			)
		end
		return holder,
			function(fraction: number, color: Color3)
				local lit = math.clamp(math.ceil(fraction * RING_DOTS), 0, RING_DOTS)
				for k, dot in dots do
					dot.BackgroundColor3 = color
					dot.BackgroundTransparency = if k <= lit then 0 else 0.8
				end
			end
	end
	local _, wayRing = ring(wayPanel, 56, "Ring")

	-- The action prompt: JUMP! or LEAN ◀ / ▶, with its own countdown ring.
	local promptY = wayY + wayHeight + 8
	local prompt = UIKit.Panel({
		Name = "Prompt",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, shiftX, 0, promptY),
		Size = UDim2.fromOffset(300, 56),
		CornerRadius = 14,
		Visible = false,
		Parent = hud,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local promptRingHolder, promptRing = ring(prompt, 48, "Ring")
	promptRingHolder.AnchorPoint = Vector2.new(0, 0.5)
	promptRingHolder.Position = UDim2.new(0, 6, 0.5, 0)
	local promptText = UIKit.Label({
		Name = "Text",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 30 else 28,
		Position = UDim2.fromOffset(58, 0),
		Size = UDim2.new(1, -64, 1, 0),
		Parent = prompt,
		Children = { UIKit.TextStroke(0.15) },
	})

	local callout = UIKit.Label({
		Name = "Callout",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 32 else 38,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, shiftX, 0, promptY + 64),
		Size = UDim2.fromOffset(if touch then 360 else 520, 44),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})
	local startHint = UIKit.Label({
		Name = "StartHint",
		Text = "◀ ▶ pick a way & lean\nJUMP at the yellow arrows",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, shiftX, 0, promptY + 64),
		Size = UDim2.fromOffset(420, 80),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})
	local calloutUntil = 0
	say = function(text: string, color: Color3, seconds: number)
		callout.Text = text
		callout.TextColor3 = color
		callout.Visible = true
		calloutUntil = os.clock() + seconds
	end

	-- Controls ---------------------------------------------------------------------------------------

	local keys = { Left = false, Right = false }
	local padTouches: { [InputObject]: number } = {} -- (each touch's order: the newest one wins)
	local touchCount = 0
	local pads: { [number]: Frame } = {}
	local padHolder: Frame? = nil
	if touch then
		local holder = UIKit.new("Frame", {
			Name = "LeanPads",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0.5, 10, 1, -20), -- (right of the middle: the left half is the MOVE stick's)
			Size = UDim2.fromOffset(204, 96),
			BackgroundTransparency = 1,
			Parent = api.Gui,
		})
		UIKit.AutoScale(holder)
		for _, side in { -1, 1 } do
			local face = UIKit.new("Frame", {
				Name = if side < 0 then "LeftPad" else "RightPad",
				AnchorPoint = Vector2.new(if side < 0 then 0 else 1, 0),
				Position = UDim2.fromScale(if side < 0 then 0 else 1, 0),
				Size = UDim2.fromOffset(96, 96),
				BackgroundColor3 = Theme.Colors.Cyan,
				Parent = holder,
				Children = { UIKit.Round(), UIKit.Stroke(Color3.new(1, 1, 1), 4, 0.1) },
			})
			UIKit.Label({
				Name = "Arrow",
				Text = if side < 0 then "◀" else "▶",
				Font = Theme.Fonts.Display,
				TextSize = 40,
				Size = UDim2.new(1, 0, 0, 44),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.42),
				Parent = face,
				Children = { UIKit.TextStroke(0.15) },
			})
			UIKit.Label({
				Name = "Sub",
				Text = if side < 0 then "LEFT" else "RIGHT",
				Font = Theme.Fonts.Bold,
				TextSize = 18,
				Size = UDim2.new(1, 0, 0, 20),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.78),
				Parent = face,
				Children = { UIKit.TextStroke(0.3) },
			})
			pads[side] = face
		end
		padHolder = holder
		holder.Visible = api:CanAct()
		api:OnCanAct(function(value)
			holder.Visible = value
		end)
	end
	local jump = api:Button({ Text = "JUMP", Key = Enum.KeyCode.Space, Color = Theme.Colors.Yellow, Slot = 1 })

	local function racing(): boolean
		local entry = snapshot.R[myKey]
		return stage == "Race" and entry ~= nil and entry.E == nil and api:CanAct()
	end
	-- The side a touch on the pads is on: left of the line between them is LEFT.
	local function touchSide(input: InputObject): number
		local holder = padHolder
		if holder then
			local split = holder.AbsolutePosition.X + holder.AbsoluteSize.X / 2
			return if input.Position.X < split then -1 else 1
		end
		return 0
	end
	local function onPads(input: InputObject): boolean
		local holder = padHolder
		if not holder or not holder.Visible then
			return false
		end
		local at, size = holder.AbsolutePosition, holder.AbsoluteSize
		local x, y = input.Position.X, input.Position.Y
		return x >= at.X - 12 and x <= at.X + size.X + 12 and y >= at.Y - 16 and y <= at.Y + size.Y + 16
	end
	-- Phones: the MOVE stick leans too (pushed well left or right).
	local controls = nil
	if touch then
		pcall(function()
			local module = Players.LocalPlayer:FindFirstChild("PlayerScripts")
			module = module and module:FindFirstChild("PlayerModule")
			if module then
				controls = (require :: any)(module):GetControls()
			end
		end)
	end
	local function wantedLean(): number
		local dir = 0
		if keys.Left then
			dir -= 1
		end
		if keys.Right then
			dir += 1
		end
		if dir == 0 then
			local newest, order = nil, -1
			for input, n in padTouches do
				if n > order then
					newest, order = input, n
				end
			end
			if newest then
				dir = touchSide(newest)
			end
		end
		if dir == 0 and controls then
			local ok, move = pcall(function()
				return controls:GetMoveVector()
			end)
			if ok and typeof(move) == "Vector3" and math.abs(move.X) > 0.5 then
				dir = if move.X < 0 then -1 else 1
			end
		end
		return dir
	end
	local function refreshLean()
		local value = if racing() then wantedLean() else 0
		if value ~= myLean then
			local now = api:Now()
			local last = myPicks[#myPicks]
			if last and last.Until == nil then
				last.Until = now
			end
			myLean = value
			if value ~= 0 then
				table.insert(myPicks, { Dir = value, At = now })
				if #myPicks > 8 then
					table.remove(myPicks, 1)
				end
			end
			if mine then
				mine.Lean = value
			end
			api:Action("Lean", value, now)
		end
	end
	local LEFT_KEYS = { [Enum.KeyCode.A] = true, [Enum.KeyCode.Left] = true }
	local RIGHT_KEYS = { [Enum.KeyCode.D] = true, [Enum.KeyCode.Right] = true }
	api:Track(UserInputService.InputBegan:Connect(function(input, processed)
		if LEFT_KEYS[input.KeyCode] and not processed then
			keys.Left = true
		elseif RIGHT_KEYS[input.KeyCode] and not processed then
			keys.Right = true
		elseif input.UserInputType == Enum.UserInputType.Touch and touch then
			if onPads(input) then
				touchCount += 1
				padTouches[input] = touchCount
			end
		end
		refreshLean()
	end))
	api:Track(UserInputService.InputChanged:Connect(function(input)
		if padTouches[input] then
			refreshLean()
		end
	end))
	api:Track(UserInputService.InputEnded:Connect(function(input)
		if LEFT_KEYS[input.KeyCode] then
			keys.Left = false
		elseif RIGHT_KEYS[input.KeyCode] then
			keys.Right = false
		end
		padTouches[input] = nil
		refreshLean()
	end))
	local function doJump()
		local now = api:Now()
		if not racing() then
			return
		end
		if now < myJumpAt + Track.JUMP_TIME + Track.JUMP_REST then
			return
		end
		if mine and (mine.DownUntil > 0 or mine.Back) then
			return
		end
		myJumpAt = now
		if mine then
			mine.JumpAt = now
		end
		api:Action("Jump", now)
		api:Sound("Boing")
	end
	jump.Pressed:Connect(doJump)
	api:Track(UserInputService.JumpRequest:Connect(doJump)) -- (Roblox's own jump button jumps too)
	api:Track(function()
		padTouches = {}
		myLean = 0
	end)

	local shake = 0

	-- Events -------------------------------------------------------------------------------------------

	local function cartAt(userId: any): Vector3?
		local entry = shown[tostring(userId)]
		return if entry and entry.Frame then (entry.Frame :: CFrame).Position else nil
	end
	api:OnEvent("Way", function(userId, tileIndex, branch)
		if userId == myId and type(tileIndex) == "number" and (branch == 1 or branch == 2) then
			myWays[tileIndex] = branch
		end
	end)
	api:OnEvent("Cleared", function(userId, tileIndex)
		if userId == myId and type(tileIndex) == "number" then
			myGaps[tileIndex] = nil -- (the server saw it clear)
		end
	end)
	api:OnEvent("Fall", function(userId, tileIndex)
		local at = cartAt(userId)
		if at then
			api:Effect("Poof", at)
		end
		if userId == myId then
			if type(tileIndex) == "number" then
				myGaps[tileIndex] = nil -- (the snapshot carries it from here)
			end
			say("💫 FELL! Jump at the yellow arrows!", Theme.Colors.Red, 2.2)
			api:Sound("Eliminated")
			shake = 0.35
		end
	end)
	api:OnEvent("Boom", function(userId)
		local at = cartAt(userId)
		if at then
			api:Effect("Fireworks", at + Vector3.new(0, 2, 0), {
				Color3.fromRGB(255, 120, 40),
				Color3.fromRGB(255, 220, 80),
				Color3.fromRGB(230, 60, 40),
			})
			api:Effect("Poof", at)
		end
		if userId == myId then
			say("💥 BOOM! That was the TNT way!", Theme.Colors.Red, 2.2)
			api:Sound("HazardWarning")
			shake = 0.7
		end
	end)
	api:OnEvent("Bump", function(userId)
		local at = cartAt(userId)
		if at then
			api:Effect("Stars", at + Vector3.new(0, 5, 0))
		end
		if userId == myId then
			say("❌ DEAD END! Rolling back…", Theme.Colors.TextDim, 2)
			api:Sound("Hit")
			shake = 0.3
		end
	end)
	api:OnEvent("Dash", function(userId)
		local at = cartAt(userId)
		if at and not reduced then
			api:Effect("Sparkles", at + Vector3.new(0, 3, 0), { Color3.fromRGB(110, 255, 200) })
		end
		if userId == myId then
			say("💎 DASH!", Theme.Colors.Cyan, 1)
			api:Sound("Pickup")
		end
	end)
	api:OnEvent("Missed", function(userId)
		if userId == myId then
			say("Jumped over the crystal!", Theme.Colors.TextDim, 1)
		end
	end)
	api:OnEvent("Finish", function(userId, place)
		local at = cartAt(userId)
		if at and not reduced then
			api:Effect("Confetti", at + Vector3.new(0, 5, 0))
		end
		if userId == myId and type(place) == "number" then
			say(`☀️ {Track.Ordinal(place)} out of the mine!`, Theme.Colors.Yellow, 4)
			api:Sound(if place == 1 then "Victory" else "Pickup")
		end
	end)

	-- Camera ---------------------------------------------------------------------------------------------

	local cameraPosition: Vector3? = nil
	local cameraTaken = false
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
		for character in table.clone(posed) do
			unpose(character)
		end
		local _, humanoid, root = api:Character()
		if humanoid then
			humanoid.PlatformStand = false
		end
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)

	-- Daylight at both ends of the mine, the cave's gloom in between (only this screen's grading).
	local saved = if atmosphere then { Density = atmosphere.Density, Color = atmosphere.Color } else nil
	local lastInside = -1
	local function setInside(inside: number)
		if math.abs(inside - lastInside) < 0.02 then
			return
		end
		lastInside = inside
		if mood then
			mood.Brightness = -0.06 * inside
			mood.TintColor = Color3.fromRGB(255, 250, 240):Lerp(Color3.fromRGB(215, 205, 255), inside)
		end
		if atmosphere and saved then
			atmosphere.Density = saved.Density + (0.45 - saved.Density) * inside
		end
	end

	-- Every frame ----------------------------------------------------------------------------------------

	local dotTiers: { [string]: number } = {}
	local dotRanks: { [string]: number } = {}
	local dotShifts: { [string]: { X: number, Y: number } } = {}
	local lastPlace = ""
	local hintShown = false
	local hintUntil = 0

	-- Where a rider is right now: the snapshot carried on (my own: my prediction).
	local function placeOf(key: string, data: any, now: number): (number, number, number, number)
		if key == myKey and mine then
			return mine.Tile, mine.B, mine.S, mine.V
		end
		local c = course :: Track.Course
		local tileIndex, branch, s, v = data.T or 1, data.B or 1, data.S or 0, data.V or 0
		local since = math.clamp(now - snapshot.T, 0, 0.5)
		if stage ~= "Race" or data.E or (data.Dn and now < data.Dn) then
			return tileIndex, branch, s, v
		end
		if data.Bk then
			return tileIndex, branch, s - Track.BACK_SPEED * since, 0
		end
		s += v * since
		local tile = c.Tiles[tileIndex]
		local path = tile and (tile.Paths[branch] or tile.Paths[1])
		if path and s > path.Total and c.Tiles[tileIndex + 1] then
			s -= path.Total
			tileIndex += 1
			branch = 1
		end
		return tileIndex, branch, s, v
	end

	api:RenderStep(function(dt)
		local c = course
		if not c or not origin then
			return
		end
		dt = math.min(dt, 0.1)
		local now = api:Now()

		-- My own ride, carried on from the last snapshot.
		refreshLean()
		if mine then
			mine.Lean = myLean
			if stage == "Race" and not mine.Finish and snapshot.R[myKey] and not snapshot.R[myKey].E then
				rideMine(mine, dt, now, true)
			end
		end

		-- Where everyone is, then who's side by side on the same rails (they shift apart).
		local places = {}
		for key in riders do
			local data = snapshot.R[key]
			if data then
				local t, b, s, v = placeOf(key, data, now)
				places[key] = { T = t, B = b, S = s, V = v, Data = data }
			end
		end
		local groups: { [string]: { string } } = {}
		for key, place in places do
			local id = `{place.T}:{place.B}`
			groups[id] = groups[id] or {}
			table.insert(groups[id], key)
		end
		local shifts: { [string]: number } = {}
		for _, members in groups do
			table.sort(members, function(a, b)
				return places[a].S < places[b].S
			end)
			local run = { members[1] }
			local function flush()
				local n = #run
				for index, key in run do
					shifts[key] = math.clamp((index - (n + 1) / 2) * SPREAD, -4, 4)
				end
			end
			for k = 2, #members do
				if places[members[k]].S - places[members[k - 1]].S < 4.6 then
					table.insert(run, members[k])
				else
					flush()
					run = { members[k] }
				end
			end
			flush()
		end

		local dots: { RaceBar.Dot } = {}
		local order = {}
		local myFrame: CFrame? = nil
		for key, info in riders do
			local place = places[key]
			local entry = shown[key]
			if not place then
				-- Left the round: hide the cart and the dot.
				if entry and entry.Model then
					entry.Model:Destroy()
					entry.Model = nil
				end
				local dot = markers[key]
				if dot then
					dot.Visible = false
				end
				continue
			end
			if not entry then
				entry = { Pos = nil, Rot = CFrame.identity, V = 0, Shift = 0, Roll = 0, Model = nil, Faded = false }
				shown[key] = entry
			end
			local cart = entry :: Shown
			local data = place.Data
			local isMine = key == myKey
			local rail = railFrame(place.T, place.B, place.S, info.L)
			if not rail then
				continue
			end
			-- A finished cart coasts on out into the daylight.
			if data.E and stage ~= "Ready" then
				local since = math.max(0, now - data.E)
				local extra = COAST * (1 - math.exp(-since / 1.4))
				rail = railFrame(#c.Tiles, 1, c.FinishS + extra) or rail
			end
			cart.Shift += ((shifts[key] or 0) - cart.Shift) * (1 - math.exp(-dt * 6))
			local jumpAt = if isMine then myJumpAt else (data.J or -math.huge)
			local lift = Track.JumpHeight(now - jumpAt)
			local lean = if isMine then myLean else (data.Ln or 0)
			local tile = c.Tiles[place.T]
			local bend = if tile then Track.LeanAt(tile, place.B, place.S) else 0
			local wobble = if bend ~= 0 and lean == -bend then math.sin(now * 30) * 0.08 else 0
			cart.Roll += (lean * 0.14 + wobble - cart.Roll) * (1 - math.exp(-dt * 10))
			local target = rail * CFrame.new(cart.Shift, Track.RAIL_TOP + lift, 0)
			-- Off the rails: dropping into the gap, or thrown up by the TNT and tumbling.
			local downUntil = if isMine and mine then (if mine.DownUntil > 0 then mine.DownUntil else nil) else data.Dn
			local flail = false
			if downUntil and now < downUntil then
				local since = Track.COMEBACK - (downUntil - now)
				flail = true
				local kind = if isMine and myGaps[place.T] then "fall" else data.Dk
				if kind == "boom" then
					target = target
						* CFrame.new(3 * since, math.max(14 * since - 16 * since * since, -60), 0)
						* CFrame.Angles(since * 5, since * 3, since * 2)
				else
					target = target
						* CFrame.new(0, math.max(-14 * since * since, -60), 0)
						* CFrame.Angles(-since * 1.2, 0, 0)
				end
			end
			-- (eased toward where it should be: on the move, then pulled in)
			local position = target.Position
			local pos = cart.Pos
			if pos == nil or (position - pos).Magnitude > 20 then
				pos = position
			else
				pos += target.LookVector * place.V * dt
				pos += (position - pos) * (1 - math.exp(-dt * (if isMine then 14 else 8)))
			end
			cart.Pos = pos
			cart.Rot = cart.Rot:Lerp(target.Rotation, 1 - math.exp(-dt * 12))
			local frame = CFrame.new(pos :: Vector3) * cart.Rot * CFrame.Angles(0, 0, -cart.Roll)
			cart.Frame = frame
			cart.V = place.V
			if isMine then
				myFrame = frame
			end
			local model = cartFor(key, info)
			if model then
				model:PivotTo(frame)
			end
			poses[key] = {
				Lean = lean,
				Air = math.clamp(lift / Track.JUMP_HEIGHT, 0, 1),
				Flail = flail,
				Cheer = data.E ~= nil,
			}
			local character = api:CharacterOf(tonumber(key))
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if character and root then
				if not posed[character] then
					posed[character] = key
				end
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				local rootY = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15
					then humanoid.HipHeight + root.Size.Y / 2
					else 3 -- (an R6 root stands 3 studs up; its HipHeight is 0)
				if isMine then
					if humanoid and not humanoid.PlatformStand then
						humanoid.PlatformStand = true
					end
					root.AssemblyLinearVelocity = frame.LookVector * place.V
					root.AssemblyAngularVelocity = Vector3.zero
				end
				root.CFrame = frame * CFrame.new(0, CART_FLOOR + rootY - SEAT_DROP, 0.3)
			end

			local data0 = place.Data
			local down = if isMine and mine then mine.DownUntil else (data0.Dn or 0)
			local progress = Track.Progress(
				c,
				{
					Tile = place.T,
					B = place.B,
					S = place.S,
					DownUntil = down,
					ReTile = if isMine and mine then mine.ReTile else data0.Rt,
					ReS = if isMine and mine then mine.ReS else data0.Rs,
				} :: any
			)
			local dot = marker(key)
			dot.Visible = true
			table.insert(dots, {
				Key = key,
				X = math.clamp(progress / c.Goal, 0, 1) * trackLength,
				Size = if isMine then MY_DOT else DOT,
				Tier = dotTiers[key],
				Rank = dotRanks[key],
			})
			table.insert(order, { Key = key, Score = if data.P then 1e6 - data.P else progress })
		end
		-- Carts right next to mine go see-through, so they never hide my own.
		for key, cart in shown do
			if key ~= myKey and cart.Frame then
				fade(cart, myFrame ~= nil and ((cart.Frame :: CFrame).Position - myFrame.Position).Magnitude < 7)
			end
		end

		-- The progress strip (riders side by side step above and below the line: Logic/RaceBar).
		local spots = RaceBar.Layout(dots, { Width = trackLength, Lift = LIFT })
		local ease = 1 - math.exp(-dt * 30)
		for _, item in dots do
			local spot = spots[item.Key]
			dotTiers[item.Key] = spot.Tier
			dotRanks[item.Key] = spot.Rank
			local shift = dotShifts[item.Key]
			if shift then
				shift.X += (spot.X - item.X - shift.X) * ease
				shift.Y += (spot.Y - shift.Y) * ease
			else
				shift = { X = spot.X - item.X, Y = spot.Y }
				dotShifts[item.Key] = shift
			end
			local at = UDim2.new(0, item.X + shift.X, 0.5, shift.Y)
			markers[item.Key].Position = at
			if item.Key == myKey and myGlow then
				myGlow.Position = at
				myGlow.Visible = true
			end
		end
		table.sort(order, function(a, b)
			return a.Score > b.Score
		end)
		local placeText = ""
		for index, item in order do
			if item.Key == myKey then
				local data = snapshot.R[myKey]
				placeText = if data and data.P
					then `☀️ {Track.Ordinal(data.P)} · {string.format("%.1f", data.F or 0)}s`
					else `{Track.Ordinal(index)} of {#order}`
			end
		end
		if placeText ~= lastPlace then
			lastPlace = placeText
			placeLabel.Text = placeText
		end

		-- The next switch, and the JUMP / LEAN prompt.
		local canRide = racing()
		jump:SetEnabled(canRide)
		for side, face in pads do
			face.BackgroundTransparency = if canRide then (if myLean == side then 0 else 0.25) else 0.6
		end
		local m = mine
		local showWays, showPrompt = false, false
		local jumpNow = false
		if m and canRide and m.DownUntil == 0 and not m.Back then
			local index, away = Track.NextSwitch(c, m, 110)
			if index then
				showWays = true
				local junction = c.Tiles[index]
				local long = junction.L or 1
				local picked = 0
				if away <= Track.CHOOSE or myLean ~= 0 then
					picked = Track.Choose(myPicks, zoneAt[index] or now, now)
					if picked == 0 then
						picked = myLean
					end
				end
				for _, side in { -1, 1 } do
					local kind = if side == long then "Long" else (junction.O or "Short")
					local hint = HINTS[kind]
					local box = wayBoxes[side]
					local text = if side < 0 then `◀ {hint.Icon} {hint.Word}` else `{hint.Icon} {hint.Word} ▶`
					if box.Label.Text ~= text then
						box.Label.Text = text
					end
					box.Label.TextColor3 = hint.Color
					local chosen = picked == side or (picked == 0 and side == long and away < 12)
					box.Stroke.Transparency = if chosen then 0 else 1
				end
				wayRing(
					math.clamp(away / 110, 0, 1),
					if away <= Track.CHOOSE then Theme.Colors.Yellow else Theme.Colors.Text
				)
			end
			-- A gap ahead (this tile or the next): the ring counts down to the best moment to jump.
			local tile = c.Tiles[m.Tile]
			local path = tile.Paths[m.B] or tile.Paths[1]
			local gapFront, gapLength = nil, 0
			for _, candidate in { { tile, 0 }, { c.Tiles[m.Tile + 1], path.Total } } do
				local t, extra = candidate[1], candidate[2]
				if t and gapFront == nil then
					for _, feature in t.Features do
						if feature.K == "Gap" then
							local front = feature.S - Track.HALF_BASE + extra - m.S
							if front > -2 and front < 60 then
								gapFront, gapLength = front, (feature.S1 :: number) - feature.S
							end
						end
					end
				end
			end
			local leanAhead = 0
			local leanNow = Track.LeanAt(tile, m.B, m.S)
			if leanNow == 0 then
				leanAhead = Track.LeanAt(tile, m.B, m.S + 22)
			end
			if gapFront and gapFront > 0 then
				showPrompt = true
				local v = math.max(m.V, 1)
				local lead = Track.JUMP_TIME / 2 - (gapLength + Track.WHEELBASE) / (2 * v)
				local wait = gapFront / v - lead
				jumpNow = now >= myJumpAt + Track.JUMP_TIME + Track.JUMP_REST
					and Track.Clears(now, now + gapFront / v, v, gapLength)
				promptText.Text = if jumpNow then "JUMP NOW!" else "JUMP…"
				promptText.TextColor3 = if jumpNow then Theme.Colors.Green else Theme.Colors.Yellow
				promptRing(math.clamp(wait / 1.6, 0, 1), if jumpNow then Theme.Colors.Green else Theme.Colors.Yellow)
			elseif leanNow ~= 0 or leanAhead ~= 0 then
				showPrompt = true
				local dir = if leanNow ~= 0 then leanNow else leanAhead
				local arrow = if dir < 0 then "◀" else "▶"
				if leanNow ~= 0 and myLean == leanNow then
					promptText.Text = `✔ BOOST {arrow}`
					promptText.TextColor3 = Theme.Colors.Green
				elseif leanNow ~= 0 and myLean == -leanNow then
					promptText.Text = `❌ WOBBLE! {arrow}`
					promptText.TextColor3 = Theme.Colors.Red
				else
					promptText.Text = if dir < 0 then "◀ LEAN" else "LEAN ▶"
					promptText.TextColor3 = Theme.Colors.Text
				end
				local feature = nil
				for _, f in tile.Features do
					if f.K == "Lean" and f.B == m.B and m.S <= (f.S1 :: number) and m.S + 22 >= f.S then
						feature = f
						break
					end
				end
				local fraction = if feature and m.S >= feature.S
					then 1 - (m.S - feature.S) / ((feature.S1 :: number) - feature.S)
					elseif feature then (feature.S - m.S) / 22
					else 0
				promptRing(math.clamp(fraction, 0, 1), promptText.TextColor3)
			end
		end
		wayPanel.Visible = showWays
		prompt.Visible = showPrompt
		jump:SetFill(if jumpNow then 1 else 0, Theme.Colors.Text)

		if callout.Visible and os.clock() > calloutUntil then
			callout.Visible = false
		end
		if stage == "Race" and not hintShown and api.Gui.Enabled then -- (not while the rules card is up)
			hintShown = true
			hintUntil = os.clock() + 6
			if not touch then
				api:Hint("A / D: pick a way & lean into bends · SPACE: jump at the yellow arrows", promptY + 112)
			end
		end
		startHint.Visible = touch and hintUntil > 0 and os.clock() <= hintUntil and not callout.Visible
		if hintUntil > 0 and os.clock() > hintUntil then
			hintUntil = -1
			if not touch then
				api:Hint("")
			end
		end

		-- Chase camera behind my cart, and the light: the cave's gloom inside, daylight at the ends.
		local me = shown[myKey]
		if me and me.Frame and api:Alive() and m then
			local frame = me.Frame :: CFrame
			local flat =
				CFrame.lookAt(frame.Position, frame.Position + Vector3.new(frame.LookVector.X, 0, frame.LookVector.Z))
			local desired = (flat * CFrame.new(0, 7.5, 15)).Position
			cameraPosition = if cameraPosition then cameraPosition:Lerp(desired, 1 - math.exp(-dt * 7)) else desired
			if not cameraTaken then
				cameraTaken = true
				camera.CameraType = Enum.CameraType.Scriptable
			end
			shake = math.max(0, shake - dt)
			local jolt = if shake > 0
				then Vector3.new(math.sin(now * 61), math.sin(now * 73), 0) * shake
				else Vector3.zero
			local look = (flat * CFrame.new(0, 2.5, -14)).Position
			if m.DownUntil > 0 then
				look = (flat * CFrame.new(0, 0, -6)).Position + Vector3.new(0, frame.Position.Y - flat.Position.Y, 0)
			end
			camera.CFrame = CFrame.lookAt((cameraPosition :: Vector3) + jolt, look)
			camera.FieldOfView = 66 + 14 * math.clamp((m.V - Track.CRUISE) / (Track.DASH - Track.CRUISE), 0, 1)
			local progress = Track.Progress(c, m)
			local enter = c.Tiles[1].Nominal * 0.85
			local leave = c.Goal - 6
			setInside(math.clamp(math.min((progress - enter + 20) / 30, (leave - progress) / 30), 0, 1))
		else
			releaseCamera()
		end
	end)
end

return MinecartMayhem

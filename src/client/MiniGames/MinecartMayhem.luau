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
--
-- Poses pass (owner: "Bots are STILL ruberbanding and floating."): riders crouch in their carts on
-- R15 bodies now, hands on the rim, leaning into the bends and throwing their arms up in a jump.
-- This place's servers build R15 bodies (every bot's, and players' R15 avatars) with
-- AnimationConstraint joints instead of Motor6Ds, and the pose only looked for Motor6Ds, so it
-- found none there and no limb moved (measured on a test server: 0 of a rider's 10 joints; riders
-- stood straight up in their carts). The pose goes through client/Pose now, which turns either kind
-- of joint; the poses themselves are as before (R6's too).
--
-- Jump pass (owner: "Minecart mayhem needs to be fixed on mobile. you cannot see where to jump."):
-- measured on a test server from the rider's own camera on an iPhone-sized screen (844 x 390 pt),
-- a gap was never on screen. The camera sat 7.5 studs up and (trailing at cruising speed) 18.6
-- back, so the rider's own head hid the rails out to about 80 studs ahead (3 s); past that the rails
-- were a 23 pt band right under the next-switch panel and the JUMP prompt, a 140 x 26 pt box with
-- 14 pt words in the middle of the screen. At the moment to press, the gap was under the cart's nose.
-- Now phones ride with a higher, closer camera that looks down the rails (10 up, 9.5 back, aimed 13
-- ahead on the rails): the rider sits low on the screen and the rails show above their head from
-- about 20 studs out, and the gate at every gap (server half: glowing posts at the take-off arrows,
-- red lights on the broken rails' ends) reads from far down the mine. Their strip is narrower, with
-- the next switch's two ways beside it, so nothing of the HUD covers the rails ahead. The JUMP cue
-- sits on my own cart on every screen (its own full-screen ScreenGui, placed from the camera each
-- frame): GAP AHEAD 2.6 s before the best moment to press, READY... at 0.9 s, then JUMP! (green,
-- bigger, with a haptic tap where the device has one) exactly while a press clears the gap
-- (Track.Clears, the server's own rule); an arc of lamps over the rider and the gate's lamps fill
-- toward that moment, and so does the JUMP button. LEAN prompts, the callouts and the controls hint
-- show there too. PC keeps its camera, its strip and its switch panel.

local HapticService = game:GetService("HapticService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RaceBar = require(ReplicatedStorage.Shared.Logic.RaceBar)
local Track = require(ReplicatedStorage.Shared.Logic.MinecartMayhemTrack)

local Pose = require(script.Parent.Parent.Pose)
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

-- The chase camera: Up studs over my cart and Back behind it (it trails a little more at speed),
-- looking at a point Ahead on the rails and Aim up. Phones ride higher and closer, looking down the
-- rails ahead, so the rider never hides a gap's approach (tools/checks/scenarios/MinecartMayhem_jump
-- shows it). The server hangs the junction gantries higher for it, and
-- tools/checks/MinecartMayhemCamera checks that both cameras pass under everything over the rails
-- (it has a copy of these numbers: change them together).
local CAMERA = { Up = 7.5, Back = 15, Ahead = 14, Aim = 2.5 }
local PHONE_CAMERA = { Up = 10, Back = 9.5, Ahead = 13, Aim = 0 }

-- The JUMP cue on my cart: GAP AHEAD from WARN seconds before the best moment to press, READY...
-- from READY, the lamps filling over the last FILL seconds, JUMP! while a press clears the gap.
local WARN = 2.6
local READY = 0.9
local FILL = 1.6
local CUE_SIZE = 0.44 -- the cue's square, a share of the screen's height (my cart's size on screen)
local ARC_LAMPS = 7 -- over the rider, lit from both ends toward the top (4 steps, like the gate's lamps)
local GATE_YELLOW = Color3.fromRGB(255, 205, 40) -- the gate as the server built it

-- The joints a rider's pose turns: R15's, then R6's (client/Pose finds them on either kind of body).
local JOINTS = {
	"Waist",
	"Neck",
	"LeftShoulder",
	"RightShoulder",
	"LeftElbow",
	"RightElbow",
	"LeftHip",
	"RightHip",
	"LeftKnee",
	"RightKnee",
	"Left Shoulder",
	"Right Shoulder",
	"Left Hip",
	"Right Hip",
}

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
					say("✓ CLEARED!", Theme.Colors.Green, 0.9)
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

	local rigs: { [Model]: { [string]: Pose.Joint } } = {}
	local posed: { [Model]: string } = {}
	local function rigOf(character: Model)
		local rig = rigs[character]
		if not rig then
			rig = Pose.Rig(character, JOINTS)
			rigs[character] = rig
		end
		return rig
	end
	local function unpose(character: Model)
		local rig = rigs[character]
		if rig then
			Pose.ReleaseAll(rig)
		end
		rigs[character] = nil
		posed[character] = nil
	end
	local poses: { [string]: { Lean: number, Air: number, Flail: boolean, Cheer: boolean } } = {}
	-- Just before physics, every frame: after the Animator, so the pose is what shows.
	api:Track(Pose.Step(function(dt)
		local now = api:Now()
		local alpha = 1 - math.exp(-dt * 14)
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
				Pose.Ease(joint, target[name] or CFrame.identity, alpha)
			end
		end
	end))

	-- HUD ----------------------------------------------------------------------------------------------
	-- (Phones: a narrower strip with the next switch's two ways either side of it and my place under
	-- its left end, so nothing covers the rails ahead in the middle of the screen. PC: the strip, my
	-- place and the switch panel under each other, as before.)

	local hud = api:TopHud()
	local hudY = api:HudY()
	local barWidth = if touch then 380 else 560
	local trackLength = barWidth - 64
	local DOT = if touch then 30 else 18
	local MY_DOT = if touch then 36 else 26
	local LIFT = if touch then 15 else 9
	local barHeight = if touch then 60 else 36
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
		AnchorPoint = Vector2.new(if touch then 0 else 0.5, 0),
		Position = UDim2.new(0.5, if touch then -barWidth / 2 + 6 else 0, 0, placeY),
		Size = UDim2.fromOffset(if touch then 240 else 300, 32),
		TextXAlignment = if touch then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})

	-- The next switch: both ways (arrow, icon, word), the one I'm picking lit up. PC: side by side
	-- under my place, with a countdown ring between them. Phones: either side of the strip, on its
	-- row; their rims turn yellow once a press counts (the ring's job on PC).
	local WAY_BOX = 206 -- (phones: each way's box; the row clears the standings on a 667 pt screen)
	local wayY = if touch then hudY + 4 else placeY + 38
	local wayHeight = if touch then barHeight else 54
	local wayPanel = UIKit.new("Frame", {
		Name = "Ways",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, wayY),
		Size = UDim2.fromOffset(if touch then barWidth + 2 * (WAY_BOX + 8) else 430, wayHeight),
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
			Size = if touch then UDim2.new(0, WAY_BOX, 1, 0) else UDim2.new(0.5, -34, 1, 0),
			CornerRadius = 12,
			Parent = wayPanel,
		}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
		local stroke = UIKit.Stroke(Theme.Colors.Text, 4, 1)
		stroke.Parent = boxFrame
		local label = UIKit.Label({
			Name = "Text",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = if touch then 26 else 24,
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
	local wayRing: ((number, Color3) -> ())? = nil
	if not touch then
		local _, setRing = ring(wayPanel, 56, "Ring")
		wayRing = setRing
	end

	-- The cue on my own cart, on every screen: the JUMP and LEAN prompts, an arc of lamps over the
	-- rider counting down to the moment, and the callouts. It has its own full-screen ScreenGui, so
	-- it sits where my cart is drawn (placed from the camera every frame; it's a share of the
	-- screen's height, like the cart itself) and nothing of it covers the rails ahead. It shows and
	-- hides with the mode's HUD (the rules card).
	local cueGui = UIKit.new("ScreenGui", {
		Name = "MiniGame_MinecartMayhemCue",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = api.Gui.DisplayOrder,
		Enabled = api.Gui.Enabled,
		Parent = api.Gui.Parent,
	})
	api:Track(cueGui)
	api:Track(api.Gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		cueGui.Enabled = api.Gui.Enabled
	end))
	local cue = UIKit.new("Frame", {
		Name = "Cue",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.66),
		Size = UDim2.fromScale(CUE_SIZE, CUE_SIZE),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		Parent = cueGui,
	})
	local ink = Color3.fromRGB(30, 15, 60)
	-- (the words' width, a share of the cue: PC's wide screens take long words big; touch screens
	-- keep them to 190 pt, clear of the MOVE stick's corner on a tablet too)
	local CUE_WORDS = if touch then 0.95 else 1.4
	-- (a callout no taller than two lines then, or a tablet's tall box would wrap it onto four)
	local function narrow(tallest: number): { Instance }
		return if touch then { UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(190, tallest) }) } else {}
	end
	local lamps: { Frame } = {}
	local arc = if touch then 0.42 else 0.36 -- (PC: a little tighter, under the switch panel's ring)
	for k = 1, ARC_LAMPS do
		-- (from upper left over the rider's head to upper right: clear of the pads and the stick)
		local a = rad(145 - (k - 1) * 110 / (ARC_LAMPS - 1))
		lamps[k] = UIKit.new("Frame", {
			Name = "Lamp" .. k,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + arc * math.cos(a), 0.5 - arc * math.sin(a)),
			Size = UDim2.fromScale(0.07, 0.07),
			BackgroundColor3 = Theme.Colors.Yellow,
			Visible = false,
			Parent = cue,
			Children = { UIKit.Round(), UIKit.Stroke(ink, 2, 0.1) },
		})
	end
	local cueWords = UIKit.Label({
		Name = "Prompt",
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(CUE_WORDS, 0.16),
		Visible = false,
		Parent = cue,
		Children = { UIKit.new("UIStroke", { Color = ink, Thickness = 3, Transparency = 0.05 }) },
	})
	local callout = UIKit.Label({
		Name = "Callout",
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(CUE_WORDS * 1.1, 0.26),
		Visible = false,
		Parent = cue,
		Children = {
			UIKit.new("UIStroke", { Color = ink, Thickness = 2, Transparency = 0.1 }),
			UIKit.new("UITextSizeConstraint", { MaxTextSize = 40 }),
		},
	})
	callout:SetAttribute("PP_Lines", 2) -- (a long one, and the phones' start hint, take two lines)
	for label, tallest in { [cueWords] = math.huge, [callout] = 48 } do
		for _, limit in narrow(tallest) do
			limit.Parent = label
		end
	end
	local calloutUntil = 0
	say = function(text: string, color: Color3, seconds: number)
		callout.Text = text
		callout.TextColor3 = color
		calloutUntil = os.clock() + seconds
	end

	-- A light tap at the moment to JUMP, where the device has haptics (phones: HapticEffect; a
	-- gamepad: its small motor). Anything missing just does nothing.
	local tapEffect: HapticEffect? = nil
	local function tap()
		pcall(function()
			if not tapEffect then
				local effect = Instance.new("HapticEffect")
				effect.Type = Enum.HapticEffectType.UIClick
				effect.Parent = api.World
				tapEffect = effect
			end
			(tapEffect :: HapticEffect):Play()
		end)
		pcall(function()
			local pad = Enum.UserInputType.Gamepad1
			if
				HapticService:IsVibrationSupported(pad)
				and HapticService:IsMotorSupported(pad, Enum.VibrationMotor.Small)
			then
				HapticService:SetMotor(pad, Enum.VibrationMotor.Small, 0.6)
				task.delay(0.08, function()
					pcall(HapticService.SetMotor, HapticService, pad, Enum.VibrationMotor.Small, 0)
				end)
			end
		end)
	end

	-- The gate at the gap my cart is coming up to (server half): its lamps turn green from the bottom
	-- as my cue counts down, and the whole gate in the moment to JUMP (only on this screen).
	type Gate = { Lamps: { { BasePart } }, Beacons: { BasePart } }
	local gates: { [number]: Gate } = {}
	local gateShows: { [number]: number } = {}
	local function gateOf(tileIndex: number): Gate?
		local found = gates[tileIndex]
		if found then
			return found
		end
		local arena = workspace:FindFirstChild("Arena_" .. api.Id)
		local folder = arena and arena:FindFirstChild("JumpGate" .. tileIndex, true)
		if not folder then
			return nil
		end
		local gate: Gate = { Lamps = { {}, {}, {}, {} }, Beacons = {} }
		for _, part in folder:GetChildren() do
			if part:IsA("BasePart") then
				local k = tonumber(string.match(part.Name, "^GateLamp(%d)$"))
				if k and gate.Lamps[k] then
					table.insert(gate.Lamps[k], part)
				elseif part.Name == "GateBeacon" then
					table.insert(gate.Beacons, part)
				end
			end
		end
		gates[tileIndex] = gate
		return gate
	end
	-- `lit`: how many lamps up each post are green (0: the gate as built; 5: all of it, JUMP!).
	local function showGate(tileIndex: number, lit: number)
		if (gateShows[tileIndex] or 0) == lit then
			return
		end
		local gate = gateOf(tileIndex)
		if not gate then
			return
		end
		gateShows[tileIndex] = lit
		for k, parts in gate.Lamps do
			for _, part in parts do
				part.Color = if k <= lit then Theme.Colors.Green else GATE_YELLOW
			end
		end
		for _, part in gate.Beacons do
			part.Color = if lit >= 5 then Theme.Colors.Green else GATE_YELLOW
		end
	end
	local shownGate: number? = nil
	local shownLit, shownLampColor = -2, Theme.Colors.Yellow
	-- (the gap my cue last warned about and tapped for: once per run at a gap, again after a fall)
	local warnedGap: number?, tappedGap: number? = nil, nil

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
			warnedGap, tappedGap = nil, nil -- (the comeback rides up to the same gap again)
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
	local steep = if touch then 1 else 0 -- (how much of PHONE_CAMERA the camera takes)
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

		-- The next switch, and the JUMP / LEAN cue on my cart.
		local canRide = racing()
		jump:SetEnabled(canRide)
		for side, face in pads do
			face.BackgroundTransparency = if canRide then (if myLean == side then 0 else 0.25) else 0.6
		end
		local m = mine
		local showWays = false
		local cueText: string?, cueColor, cueBig = nil, Theme.Colors.Yellow, false
		local lit, lampColor = -1, Theme.Colors.Yellow -- (the arc's lamps: -1 hides them, 0..4 lit)
		local jumpNow = false
		local gateTile: number?, gateLit = nil, 0
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
					-- (white round the way I'm taking; phones: yellow round the other once a press counts)
					box.Stroke.Color = if chosen then Theme.Colors.Text else Theme.Colors.Yellow
					box.Stroke.Transparency = if chosen then 0 elseif touch and away <= Track.CHOOSE then 0.2 else 1
				end
				if wayRing then
					wayRing(
						math.clamp(away / 110, 0, 1),
						if away <= Track.CHOOSE then Theme.Colors.Yellow else Theme.Colors.Text
					)
				end
			end
			-- A gap ahead (this tile or the next): GAP AHEAD, then READY..., then JUMP! exactly while
			-- a press now clears it (Track.Clears, the server's own rule); the lamps fill toward the
			-- best moment to press. Nothing while my cart is in the air.
			local tile = c.Tiles[m.Tile]
			local path = tile.Paths[m.B] or tile.Paths[1]
			local gapFront, gapLength, gapAt = nil, 0, nil
			for _, candidate in { { tile, 0 }, { c.Tiles[m.Tile + 1], path.Total } } do
				local t, extra = candidate[1], candidate[2]
				if t and gapFront == nil then
					for _, feature in t.Features do
						if feature.K == "Gap" then
							local front = feature.S - Track.HALF_BASE + extra - m.S
							if front > -2 and front < 90 then
								gapFront, gapLength, gapAt = front, (feature.S1 :: number) - feature.S, t.Index
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
			local v = math.max(m.V, 1)
			local lead = Track.JUMP_TIME / 2 - (gapLength + Track.WHEELBASE) / (2 * v)
			local wait = if gapFront then gapFront / v - lead else math.huge
			local resting = now < myJumpAt + Track.JUMP_TIME + Track.JUMP_REST
			if gapFront and gapAt and gapFront > 0 and wait <= WARN and not resting then
				jumpNow = Track.Clears(now, now + gapFront / v, v, gapLength)
				if jumpNow or wait > 0 then
					lit = if jumpNow then 4 else math.clamp(math.ceil((1 - wait / FILL) * 4), 0, 4)
					lampColor = if jumpNow then Theme.Colors.Green else Theme.Colors.Yellow
					gateTile, gateLit = gapAt, if jumpNow then 5 else lit
					if jumpNow then
						cueText, cueColor, cueBig = "JUMP!", Theme.Colors.Green, true
					else
						cueText = if wait > READY then "GAP AHEAD" else "READY…"
					end
					if warnedGap ~= gapAt then
						warnedGap = gapAt
						api:Sound("HazardWarning")
					end
					if jumpNow and tappedGap ~= gapAt then
						tappedGap = gapAt
						tap()
						if not reduced then
							UIKit.PopIn(cueWords, 0.25)
						end
					end
				end
			elseif leanNow ~= 0 or leanAhead ~= 0 then
				local dir = if leanNow ~= 0 then leanNow else leanAhead
				local arrow = if dir < 0 then "◀" else "▶"
				if leanNow ~= 0 and myLean == leanNow then
					cueText, cueColor = `✓ BOOST {arrow}`, Theme.Colors.Green
				elseif leanNow ~= 0 and myLean == -leanNow then
					cueText, cueColor = `❌ WOBBLE! {arrow}`, Theme.Colors.Red
				else
					cueText, cueColor = if dir < 0 then "◀ LEAN" else "LEAN ▶", Theme.Colors.Text
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
				lit, lampColor = math.clamp(math.ceil(fraction * 4), 0, 4), cueColor
			end
		end
		wayPanel.Visible = showWays
		jump:SetFill(
			if jumpNow then 1 elseif gateTile then gateLit / 5 else 0,
			if jumpNow then Theme.Colors.Green else Theme.Colors.Text
		)
		if shownGate and shownGate ~= gateTile then
			showGate(shownGate, 0)
		end
		shownGate = gateTile
		if gateTile then
			showGate(gateTile, gateLit)
		end

		-- What the cue on my cart says: a prompt first, then a callout, then the controls for the
		-- first seconds of the race (not while the rules card is up).
		if stage == "Race" and not hintShown and api.Gui.Enabled then
			hintShown = true
			hintUntil = os.clock() + 6
		end
		local hinting = os.clock() <= hintUntil
		if cueText then
			if cueWords.Text ~= cueText then
				cueWords.Text = cueText
			end
			cueWords.TextColor3 = cueColor
			cueWords.Size = UDim2.fromScale(CUE_WORDS, if cueBig then 0.24 else 0.16)
			cueWords.Visible = true
			callout.Visible = false
		else
			cueWords.Visible = false
			if os.clock() <= calloutUntil then
				callout.Visible = true
			elseif hinting then
				callout.Text = if touch
					then "◀ ▶ pick a way & lean\nJUMP at the yellow arrows"
					else "A / D: pick a way & lean\nSPACE: JUMP at the yellow arrows"
				callout.TextColor3 = Theme.Colors.Text
				callout.Visible = true
			else
				callout.Visible = false
			end
		end
		if lit ~= shownLit or lampColor ~= shownLampColor then
			shownLit, shownLampColor = lit, lampColor
			for k, lamp in lamps do
				lamp.Visible = lit >= 0
				lamp.BackgroundColor3 = lampColor
				lamp.BackgroundTransparency = if math.min(k, ARC_LAMPS + 1 - k) <= lit then 0 else 0.65
			end
		end

		-- Chase camera behind my cart, and the light: the cave's gloom inside, daylight at the ends.
		-- (Phones: the high camera while riding, easing back to the usual one past the finish line, so
		-- it rolls out under the exit's lintel as on PC.)
		local me = shown[myKey]
		if me and me.Frame and api:Alive() and m then
			local frame = me.Frame :: CFrame
			local flat =
				CFrame.lookAt(frame.Position, frame.Position + Vector3.new(frame.LookVector.X, 0, frame.LookVector.Z))
			steep += ((if touch and not m.Finish then 1 else 0) - steep) * (1 - math.exp(-dt * 1.5))
			local up = CAMERA.Up + (PHONE_CAMERA.Up - CAMERA.Up) * steep
			local back = CAMERA.Back + (PHONE_CAMERA.Back - CAMERA.Back) * steep
			local ahead = CAMERA.Ahead + (PHONE_CAMERA.Ahead - CAMERA.Ahead) * steep
			local aim = CAMERA.Aim + (PHONE_CAMERA.Aim - CAMERA.Aim) * steep
			local desired = (flat * CFrame.new(0, up, back)).Position
			cameraPosition = if cameraPosition then cameraPosition:Lerp(desired, 1 - math.exp(-dt * 7)) else desired
			if not cameraTaken then
				cameraTaken = true
				camera.CameraType = Enum.CameraType.Scriptable
			end
			shake = math.max(0, shake - dt)
			local jolt = if shake > 0
				then Vector3.new(math.sin(now * 61), math.sin(now * 73), 0) * shake
				else Vector3.zero
			local look = (flat * CFrame.new(0, aim, -ahead)).Position
			if m.DownUntil > 0 then
				look = (flat * CFrame.new(0, 0, -6)).Position + Vector3.new(0, frame.Position.Y - flat.Position.Y, 0)
			end
			camera.CFrame = CFrame.lookAt((cameraPosition :: Vector3) + jolt, look)
			camera.FieldOfView = 66 + 14 * math.clamp((m.V - Track.CRUISE) / (Track.DASH - Track.CRUISE), 0, 1)
			-- (the cue sits where my cart's middle is drawn: worked out from the camera, so on any screen)
			local middle = camera.CFrame:PointToObjectSpace((frame * CFrame.new(0, 1.6, 0)).Position)
			if middle.Z < -1 then
				local span = 2 * math.tan(rad(camera.FieldOfView) / 2)
				local view = camera.ViewportSize
				local x = if view.X > 100 and view.Y > 100
					then 0.5 + middle.X / -middle.Z / (span * view.X / view.Y)
					else 0.5
				local y = 0.5 - middle.Y / -middle.Z / span
				cue.Position = UDim2.fromScale(math.clamp(x, 0.35, 0.65), math.clamp(y, 0.3, 0.8))
			end
			cue.Visible = true
			local progress = Track.Progress(c, m)
			local enter = c.Tiles[1].Nominal * 0.85
			local leave = c.Goal - 6
			setInside(math.clamp(math.min((progress - enter + 20) / 30, (leave - progress) / 30), 0, 1))
		else
			cue.Visible = false
			releaseCamera()
		end
	end)
end

return MinecartMayhem

-- Client half of Skate Escape: your own skater, everyone's skating poses, the crumbling bridge, the
-- chase camera and the race HUD.
--
-- Your skater runs the shared rules (Shared/Logic/SkateCourse) right here, so PUSH and JUMP answer
-- at once; the server runs the same race and has the final say (MG_Racers): when they disagree you
-- slide to its numbers, take its wipeouts, and drop if it says the bridge got you. Everyone else's
-- skater moves by itself (players' clients and the server's bots) and is posed here from MG_Racers:
-- the push kick, the ollie tuck, the wipeout flip. The bridge crumbles from the shared schedule
-- MG_Collapse, the same one the server checks distances against.
--
-- The start (owner: "it spawns you when the game starts not on the bridge and you kinda just float to
-- the bridge"): the server puts every skater exactly where this client draws them (lane, start line,
-- riding height) and holds them there until GO, so taking over my skater never moves it; at GO the
-- server hands it back to this device before the race's schedule arrives, and the bridge stays still
-- until the collapse actually begins.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SkateCourse = require(ReplicatedStorage.Shared.Logic.SkateCourse)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SkateEscape = {}

local KICK_TIME = 0.32
local CAMERA_BACK = 15
local CAMERA_UP = 7
local LAVA_DEPTH = 46 -- the lava river's surface below the deck (as the server builds it)
local DECK_WIDTH = 100
local START_BACK = 36 -- the start pad behind the line
local rad = math.rad

type Obstacle = SkateCourse.Obstacle

-- R15 joints we pose: part name -> motor name.
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
	LeftFoot = "LeftAnkle",
	RightFoot = "RightAnkle",
}

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

-- The pose of a skater, as joint rotations. `kick` 0..1 through a push, `air` 0..1 through an ollie,
-- `mode` "Ride" | "Air" | "Wipe" | "Fall" | "Cheer", `t` seconds for wobbles.
local function targetPose(mode: string, kick: number, t: number): { [string]: CFrame }
	if mode == "Air" then
		return {
			Waist = angles(-14, 20, 0),
			Neck = angles(0, 50, 0),
			LeftShoulder = angles(20, 0, -75),
			RightShoulder = angles(20, 0, 75),
			LeftElbow = angles(30, 0, 0),
			RightElbow = angles(30, 0, 0),
			LeftHip = angles(55, 0, -10),
			RightHip = angles(55, 0, 10),
			LeftKnee = angles(-85, 0, 0),
			RightKnee = angles(-85, 0, 0),
			LeftAnkle = angles(25, 0, 10),
			RightAnkle = angles(25, 0, -10),
		}
	elseif mode == "Wipe" or mode == "Fall" then
		local flail = math.sin(t * 16) * 30
		return {
			Waist = angles(10, 0, 0),
			Neck = angles(-15, 0, 0),
			LeftShoulder = angles(flail, 0, -140),
			RightShoulder = angles(-flail, 0, 140),
			LeftElbow = angles(20, 0, 0),
			RightElbow = angles(20, 0, 0),
			LeftHip = angles(30 + flail, 0, -25),
			RightHip = angles(-20 - flail, 0, 25),
			LeftKnee = angles(-40, 0, 0),
			RightKnee = angles(-20, 0, 0),
			LeftAnkle = CFrame.identity,
			RightAnkle = CFrame.identity,
		}
	elseif mode == "Cheer" then
		local bounce = math.sin(t * 9) * 12
		return {
			Waist = angles(4, 20, 0),
			Neck = angles(10, 40, 0),
			LeftShoulder = angles(0, 0, -160 + bounce),
			RightShoulder = angles(0, 0, 160 - bounce),
			LeftElbow = angles(15, 0, 0),
			RightElbow = angles(15, 0, 0),
			LeftHip = angles(15, 0, -12),
			RightHip = angles(15, 0, 12),
			LeftKnee = angles(-20, 0, 0),
			RightKnee = angles(-20, 0, 0),
			LeftAnkle = angles(5, 0, 12),
			RightAnkle = angles(5, 0, -12),
		}
	end
	-- Riding: sideways on the board, knees bent, arms out, looking down the course (to the left).
	-- A push swings the back (right) foot down beside the board and back up.
	local s = math.sin(math.clamp(kick, 0, 1) * math.pi)
	local sway = math.sin(t * 2.2) * 3
	return {
		Waist = angles(-10 - 8 * s, 28, sway * 0.5),
		Neck = angles(4, 52 - 6 * s, 0),
		LeftShoulder = angles(10 + 15 * s, 0, -48 + sway),
		RightShoulder = angles(-10 - 25 * s, 0, 52 + sway),
		LeftElbow = angles(25, 0, 0),
		RightElbow = angles(25 + 10 * s, 0, 0),
		LeftHip = angles(30 + 10 * s, 0, -14),
		RightHip = angles(30 * (1 - s) - 12 * s, 0, 14 + 20 * s),
		LeftKnee = angles(-45 - 15 * s, 0, 0),
		RightKnee = angles(-45 * (1 - s), 0, 0),
		LeftAnkle = angles(15 + 5 * s, 0, 14),
		RightAnkle = angles(15 * (1 - s), 0, -14 - 10 * s),
	}
end

function SkateEscape.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 236, 220),
		Saturation = 0.14,
		Contrast = 0.08,
		Haze = Color3.fromRGB(255, 160, 110),
		HazeDecay = Color3.fromRGB(140, 70, 60),
		Density = 0.3,
	})

	local localPlayer = Players.LocalPlayer
	local myKey = tostring(localPlayer.UserId)
	local camera = workspace.CurrentCamera
	local reduced = State.ReducedEffects()

	local race = nil
	local origin = Vector3.zero
	local obstacles: { Obstacle } = {}
	local length = SkateCourse.Length
	local lanes = 12
	local myLane: number? = nil
	local collapse: SkateCourse.Collapse? = nil
	local racers: { [string]: any } = {}
	local snapshotAt = 0

	local me = SkateCourse.NewRacer() :: any
	local drawOffset = 0
	local kickAt = -math.huge
	local outAt: number? = nil
	local lastJump = -math.huge
	local lastPush = -math.huge
	local wipeD: number? = nil -- where my last local wipeout's obstacle stands
	local driving: Model? = nil
	local shake = 0
	local fovPunch = 0

	local function nextIndex(d: number): number
		return SkateCourse.NextIndex(obstacles, d)
	end

	local function setupRace(value)
		if race or type(value) ~= "table" or type(value.O) ~= "table" then
			return
		end
		race = value
		origin = Vector3.new(value.O[1], value.O[2], value.O[3])
		length = value.Length or length
		lanes = value.Lanes or lanes
		for _, o in value.Obstacles or {} do
			table.insert(obstacles, { Kind = o.K, D = o.D, Len = o.N })
		end
		myLane = value.Lane and value.Lane[myKey]
	end
	setupRace(api:SharedJSON("Race"))
	api:OnShared("Race", function()
		setupRace(api:SharedJSON("Race"))
	end)
	local function refreshCollapse()
		local value = api:SharedJSON("Collapse")
		if type(value) == "table" and value.T0 then
			collapse = value
		end
	end
	refreshCollapse()
	api:OnShared("Collapse", refreshCollapse)

	-- HUD -------------------------------------------------------------------------------------------

	local hud = api:TopHud()
	local hudY = api:HudY()
	-- Phones draw the HUD at 75%: bigger dots, numbers and icons there keep them readable (11 pt+).
	local touch = api:IsTouch()
	local barWidth = 560
	local bar = UIKit.Panel({
		Name = "RaceBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY + 4),
		Size = UDim2.fromOffset(barWidth, if touch then 40 else 30),
		CornerRadius = 15,
		Parent = hud,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local track = UIKit.new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -64, 0, 8),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = bar,
		Children = { UIKit.Round() },
	})
	local fire = UIKit.new("Frame", {
		Name = "Collapse",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 90, 40),
		Parent = track,
		Children = { UIKit.Round() },
	})
	local fireIcon = UIKit.Label({
		Name = "FireIcon",
		Text = "🔥",
		TextSize = if touch then 24 else 20,
		AnchorPoint = Vector2.new(1, 0.5), -- just behind the front, so it only covers a racer it's catching
		Position = UDim2.fromScale(0, 0.5),
		Size = if touch then UDim2.fromOffset(28, 28) else UDim2.fromOffset(24, 24),
		Parent = track,
	})
	UIKit.Label({
		Name = "Goal",
		Text = "🏁",
		TextSize = if touch then 24 else 22,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 4, 0.5, 0),
		Size = if touch then UDim2.fromOffset(28, 28) else UDim2.fromOffset(26, 26),
		Parent = track,
	})
	local markers: { [string]: Frame } = {}
	local function marker(key: string, lane: number): Frame
		local existing = markers[key]
		if existing then
			return existing
		end
		local mine = key == myKey
		local size = if touch then (if mine then 36 else 30) else (if mine then 26 else 18)
		local dot = UIKit.new("Frame", {
			Name = "Racer" .. key,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = SkateCourse.LaneColors[lane] or Theme.Colors.Text,
			ZIndex = if mine then 4 else 3,
			Parent = track,
			Children = {
				UIKit.Round(),
				UIKit.Stroke(if mine then Theme.Colors.Text else Theme.Colors.PanelDark, if mine then 3 else 2),
			},
		})
		UIKit.Label({
			Text = tostring(lane),
			TextSize = if touch then (if mine then 26 else 24) else (if mine then 16 else 12),
			Font = Theme.Fonts.Bold,
			TextColor3 = Color3.fromRGB(30, 24, 40),
			Size = UDim2.fromScale(1, 1),
			ZIndex = dot.ZIndex,
			Parent = dot,
		})
		markers[key] = dot
		return dot
	end

	local placeLabel = UIKit.Label({
		Name = "Place",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 34,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY + if touch then 44 else 38), -- (under the taller phone bar)
		Size = UDim2.fromOffset(300, 40),
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})
	local callout = UIKit.Label({
		Name = "Callout",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 40,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hudY + 84),
		Size = UDim2.fromOffset(660, 48), -- the bridge warning is one long line
		TextWrapped = false,
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})
	local function setCallout(text: string)
		callout.Text = text
		if touch then
			-- Phones: only as wide as the words, so it stays clear of the move stick's corner.
			local width = UIKit.TextWidth(text, 40, Theme.Fonts.Display) + 24
			callout.Size = UDim2.fromOffset(math.ceil(width), 48)
		end
	end
	local calloutUntil = 0
	local function say(text: string, color: Color3, seconds: number)
		setCallout(text)
		callout.TextColor3 = color
		callout.Visible = true
		calloutUntil = os.clock() + seconds
		UIKit.PopIn(callout, 0.25)
	end

	local push = api:Button({ Text = "PUSH", Key = Enum.KeyCode.E, Color = Theme.Colors.Cyan })

	-- Wind streaks that rush past the camera at speed (fewer with reduced effects).
	local streaks = {}
	for index = 1, if reduced then 6 else 16 do
		local streak = Instance.new("Part")
		streak.Name = "Wind"
		streak.Anchored = true
		streak.CanCollide = false
		streak.CanQuery = false
		streak.CanTouch = false
		streak.CastShadow = false
		streak.Material = Enum.Material.Neon
		streak.Color = Color3.fromRGB(255, 240, 225)
		streak.Size = Vector3.new(0.07, 0.07, 6)
		streak.Transparency = 1
		streak.Parent = api.World
		streaks[index] = { Part = streak, At = nil :: Vector3? }
	end

	-- Controls --------------------------------------------------------------------------------------

	local function racing(): boolean
		return myLane ~= nil and collapse ~= nil and not me.Done and outAt == nil
	end

	local function doPush()
		if not racing() then
			return
		end
		local now = api:Now()
		if now - lastPush < 0.09 then
			return -- the server takes about this many a second; counting more would run ahead of it
		end
		lastPush = now
		api:Action("Push")
		if SkateCourse.Push(me, now) then
			kickAt = now
		end
	end

	local function doJump()
		if not racing() then
			return
		end
		local now = api:Now()
		if now - lastJump < 0.2 then
			return
		end
		if SkateCourse.Jump(me, now) then
			lastJump = now
			api:Action("Jump", me.D) -- the server counts the jump from this spot (see the server's Jump)
			api:Sound("Boing")
		end
	end

	push.Pressed:Connect(doPush)
	api:Track(UserInputService.JumpRequest:Connect(doJump))
	-- Also watch the driven humanoid's Jump flag (the phone jump button sets it), in case JumpRequest
	-- doesn't fire while it's PlatformStanding; the lastJump guard keeps the two from doubling up.
	local jumpWatch: RBXScriptConnection? = nil
	local jumpWatched: Humanoid? = nil
	local function watchJump(humanoid: Humanoid?)
		if humanoid == jumpWatched then
			return
		end
		if jumpWatch then
			jumpWatch:Disconnect()
			jumpWatch = nil
		end
		jumpWatched = humanoid
		if humanoid then
			jumpWatch = humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
				if humanoid.Jump then
					doJump()
				end
			end)
		end
	end
	api:Track(function()
		watchJump(nil)
	end)
	api:Track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if
			key == Enum.KeyCode.W
			or key == Enum.KeyCode.Up
			or key == Enum.KeyCode.ButtonR2
			or key == Enum.KeyCode.ButtonX
		then
			doPush()
		end
	end))

	-- What the server says ----------------------------------------------------------------------------

	local kickSeen: { [string]: { P: number, At: number } } = {}
	local function refreshRacers()
		local value = api:SharedJSON("Racers")
		if type(value) ~= "table" then
			return
		end
		racers = value
		snapshotAt = api:Now()
		for key, entry in value do
			local seen = kickSeen[key]
			if not seen then
				kickSeen[key] = { P = entry.P or 0, At = -math.huge }
			elseif (entry.P or 0) > seen.P then
				seen.P = entry.P
				seen.At = snapshotAt
			end
		end
		local mine = value[myKey]
		if not mine or not collapse then
			return
		end
		local now = api:Now()
		if mine.F then
			me.Place = mine.F -- even when my own prediction got me over the line first
			if not me.Done then
				me.Done = true
				me.D = math.max(me.D, length)
			end
		end
		if mine.O and not outAt then
			outAt = now
			me.Done = true
		end
		if me.Done then
			return
		end
		local serverWiped = mine.W ~= nil and mine.W > now
		local localWiped = SkateCourse.IsWiped(me, now)
		-- The same wipeout if it started at about the same moment, whether or not mine has ended yet.
		local known = me.WipeAt ~= nil and math.abs(me.WipeAt - (mine.WA or -math.huge)) < 1
		if serverWiped and not known then
			-- The server saw a wipeout this client didn't: take it.
			drawOffset += me.D - mine.D
			me.D = mine.D
			me.V = 0
			me.Air = nil
			me.Wipe = mine.W
			me.WipeAt = mine.WA
			me.WipeKind = mine.WK
			me.FallD = mine.FD
			me.Next = nextIndex(me.D)
			wipeD = nil
			shake = 0.5
			api:Sound("Hit")
			say("WIPEOUT!", Theme.Colors.Red, 1.2)
			return
		end
		if serverWiped then
			return -- its wipeout is mine; nothing to correct until it's over
		end
		if localWiped and not mine.PW and wipeD and (mine.D or 0) > wipeD and (mine.T or 0) > (me.WipeAt or 0) then
			-- The server's skater got past that obstacle with no wipeout and none pending (a jump
			-- inside its ping allowance): carry on from its numbers.
			me.Wipe = nil
			me.WipeKind = nil
			me.FallD = nil
			me.V = mine.V or me.V
			me.Air = mine.A
		end
		if SkateCourse.IsWiped(me, now) then
			return
		end
		-- My pushes reach the server one trip later, so I'm normally that far ahead of its skater.
		local ok, ping = pcall(function()
			return localPlayer:GetNetworkPing()
		end)
		local v = mine.V or 0
		local lead = v * math.clamp(if ok and type(ping) == "number" then ping * 0.5 else 0.05, 0, 0.3)
		local expected = mine.D + v * math.max(0, now - (mine.T or now)) + lead
		local diff = expected - me.D
		if math.abs(diff) > 14 + 0.1 * v then
			drawOffset -= diff
			me.D = expected
			me.V = mine.V or me.V
			me.Next = nextIndex(me.D)
		elseif math.abs(diff) > 6 + 0.1 * v then
			local step = diff * 0.12
			drawOffset -= step
			me.D += step
			me.Next = nextIndex(me.D)
		end
	end
	refreshRacers()
	api:OnShared("Racers", refreshRacers)

	local function racerPosition(key: string): Vector3?
		local entry = racers[key]
		if not entry then
			return nil
		end
		return origin + Vector3.new(SkateCourse.LaneX(entry.L or 1, lanes), 2, -(entry.D or 0))
	end

	api:OnEvent("Wipe", function(key, kind)
		if key == myKey then
			return
		end
		local at = racerPosition(key)
		if at and (at - camera.CFrame.Position).Magnitude < 160 then
			api:Effect("Poof", at, if kind == "Fall" then { Color3.fromRGB(255, 120, 40) } else nil)
		end
	end)
	api:OnEvent("Finish", function(key, place)
		local at = racerPosition(key)
		if key == myKey then
			api:Sound("Victory")
			say(`🏁 {SkateCourse.Ordinal(place)}!`, Theme.Colors.Yellow, 4)
			if at then
				api:Effect("Confetti", at + Vector3.new(0, 4, -6))
			end
		elseif place == 1 and at then
			api:Effect("Fireworks", origin + Vector3.new(0, 26, -length - 6))
		end
	end)
	-- A fallen skater ends in the lava with a splash (they respawn 1.2 s after falling, about when
	-- they reach it).
	local splashes: { { At: number, Position: Vector3 } } = {}
	api:OnEvent("Out", function(key)
		local fellAt = api:Now()
		if key == myKey then
			if not outAt then
				outAt = fellAt
				me.Done = true
			end
			fellAt = outAt :: number
		end
		local at = if key == myKey and myLane
			then origin + Vector3.new(SkateCourse.LaneX(myLane, lanes), 0, -me.D)
			else racerPosition(key)
		if at then
			table.insert(splashes, { At = fellAt + 1.1, Position = Vector3.new(at.X, origin.Y - LAVA_DEPTH, at.Z) })
		end
	end)

	-- The crumbling bridge ------------------------------------------------------------------------------

	local pieces = {}
	local added: { [Instance]: boolean } = {}
	local arena = api:Arena()
	local hot = Color3.fromRGB(255, 110, 50)
	local startLamps: { [string]: { Part: BasePart, Color: Color3 } } = {}
	local lampsGreen: boolean? = nil
	local function addPiece(child: Instance)
		if not child:IsA("Model") or not string.match(child.Name, "^Seg%d+$") then
			return
		end
		local d0, d1 = child:GetAttribute("D0"), child:GetAttribute("D1")
		if type(d0) ~= "number" or type(d1) ~= "number" or added[child] then
			return
		end
		added[child] = true
		-- The deck's surface parts (both plank tones, or the start pad) glow hot as the collapse nears.
		local planks = {}
		for _, part in child:GetDescendants() do
			if part:IsA("BasePart") then
				if part.Name == "Planks" or part.Name == "PlanksB" or part.Name == "StartPad" then
					table.insert(planks, { Part = part, Color = part.Color })
				elseif part.Name == "LampRed" or part.Name == "LampAmber" or part.Name == "LampGreen" then
					startLamps[part.Name] = { Part = part, Color = part.Color }
					lampsGreen = nil -- (re)light them on the next frame
				end
			end
		end
		table.insert(pieces, {
			Model = child,
			Base = child:GetPivot(),
			D0 = d0,
			D1 = d1,
			Planks = planks,
			State = "Still",
			Cracked = false,
			Splashed = false,
		})
	end
	if arena then
		for _, child in arena:GetChildren() do
			addPiece(child)
		end
		api:Track(arena.ChildAdded:Connect(addPiece))
	end

	-- The start lamps: red until GO, then green (the others dark).
	local function setLamps(green: boolean)
		if lampsGreen == green then
			return
		end
		lampsGreen = green
		for name, lamp in startLamps do
			local lit = if name == "LampGreen" then green elseif name == "LampRed" then not green else false
			lamp.Part.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
			lamp.Part.Color = if lit then lamp.Color else lamp.Color:Lerp(Color3.new(0, 0, 0), 0.65)
		end
	end

	-- The collapse front: a band of dust, sparks and lava glow riding along where the bridge is
	-- giving way, so the danger behind the pack reads from anywhere (particles only with full effects).
	local frontPart = Instance.new("Part")
	frontPart.Name = "CollapseFront"
	frontPart.Anchored = true
	frontPart.CanCollide = false
	frontPart.CanQuery = false
	frontPart.CanTouch = false
	frontPart.CastShadow = false
	frontPart.Transparency = 1
	frontPart.Size = Vector3.new(DECK_WIDTH, 1, 6)
	frontPart.CFrame = CFrame.new(0, -1e4, 0)
	frontPart.Parent = api.World
	local frontGlow = Instance.new("PointLight")
	frontGlow.Color = Color3.fromRGB(255, 110, 40)
	frontGlow.Range = 40
	frontGlow.Brightness = 2.5
	frontGlow.Shadows = false
	frontGlow.Parent = frontPart
	local frontEmitters: { ParticleEmitter } = {}
	if not reduced then
		local dust = Instance.new("ParticleEmitter")
		dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
		dust.Color = ColorSequence.new(Color3.fromRGB(150, 110, 90), Color3.fromRGB(70, 56, 58))
		dust.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.5, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
		dust.Size = NumberSequence.new(5, 14)
		dust.Lifetime = NumberRange.new(1.6, 2.6)
		dust.Speed = NumberRange.new(6, 12)
		dust.SpreadAngle = Vector2.new(25, 25)
		dust.Acceleration = Vector3.new(0, 4, 0)
		dust.RotSpeed = NumberRange.new(-30, 30)
		dust.EmissionDirection = Enum.NormalId.Top
		dust.Rate = 14
		dust.Enabled = false
		dust.Parent = frontPart
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 210, 90), Color3.fromRGB(255, 100, 40))
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new(0.7, 0)
		sparks.Lifetime = NumberRange.new(0.8, 1.4)
		sparks.Speed = NumberRange.new(14, 24)
		sparks.SpreadAngle = Vector2.new(35, 35)
		sparks.Acceleration = Vector3.new(0, -30, 0)
		sparks.EmissionDirection = Enum.NormalId.Top
		sparks.Rate = 40
		sparks.Enabled = false
		sparks.Parent = frontPart
		frontEmitters = { dust, sparks }
	end
	api:Track(function()
		frontPart:Destroy()
	end)

	-- Sparks drifting up from the lava past both rails, wherever I am (full effects only).
	local sparkParts: { { Part: BasePart, Side: number } } = {}
	if not reduced then
		for _, side in { -1, 1 } do
			local part = Instance.new("Part")
			part.Name = "LavaSparks"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Transparency = 1
			part.Size = Vector3.new(70, 1, 140)
			part.CFrame = CFrame.new(0, -1e4, 0)
			local sparks = Instance.new("ParticleEmitter")
			sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 100, 40))
			sparks.LightEmission = 1
			sparks.Size = NumberSequence.new(0.6, 0)
			sparks.Lifetime = NumberRange.new(4, 6)
			sparks.Speed = NumberRange.new(9, 15)
			sparks.SpreadAngle = Vector2.new(15, 15)
			sparks.EmissionDirection = Enum.NormalId.Top
			sparks.Rate = 10
			sparks.Parent = part
			part.Parent = api.World
			table.insert(sparkParts, { Part = part, Side = side })
		end
	end
	api:Track(function()
		for _, spark in sparkParts do
			spark.Part:Destroy()
		end
	end)

	local function updateBridge(now: number)
		for index = #splashes, 1, -1 do
			local splash = splashes[index]
			if now >= splash.At then
				table.remove(splashes, index)
				if (splash.Position - camera.CFrame.Position).Magnitude < 260 then
					api:Effect("Poof", splash.Position, { Color3.fromRGB(255, 120, 40), Color3.fromRGB(255, 200, 80) })
				end
			end
		end
		if #sparkParts > 0 then
			local z = camera.CFrame.Position.Z - 40
			for _, spark in sparkParts do
				spark.Part.CFrame = CFrame.new(origin.X + spark.Side * 90, origin.Y - 30, z)
			end
		end
		if not collapse then
			setLamps(false)
			return
		end
		setLamps(now >= collapse.T0 - 5) -- the race starts (GO) five seconds before the collapse does
		local front = SkateCourse.CollapseAt(collapse, now, length)
		local crumbling = now >= collapse.T0 and front < length
		frontPart.CFrame = if crumbling
			then CFrame.new(origin + Vector3.new(0, -1, -math.max(front, -START_BACK)))
			else CFrame.new(0, -1e4, 0)
		frontGlow.Enabled = crumbling
		for _, emitter in frontEmitters do
			emitter.Enabled = crumbling
		end
		if now < collapse.T0 then
			-- The bridge is still until the collapse begins: the front waits inside the start pad
			-- (collapse.D0), and the pad used to tip back under the start line at GO.
			return
		end
		for _, piece in pieces do
			if piece.State == "Gone" or front < piece.D0 - 32 then
				continue
			end
			local model = piece.Model
			local hinge = origin + Vector3.new(0, 0, -piece.D1)
			if front < piece.D0 then
				-- Trembling and glowing hot just ahead of the collapse.
				local heat = 1 - (piece.D0 - front) / 32
				local jitter = heat * heat * 0.18
				model:PivotTo(piece.Base * CFrame.new(math.sin(now * 53) * jitter, math.sin(now * 61) * jitter, 0))
				for _, plank in piece.Planks do
					plank.Part.Color = plank.Color:Lerp(hot, heat * 0.6)
				end
				piece.State = "Warn"
			elseif front < piece.D1 then
				-- The back end gives way first, hinging on the front, with a puff of splinters. (The
				-- start pad tips from level: the front sets off from inside it.)
				local from = math.max(piece.D0, collapse.D0)
				local t = (front - from) / math.max(1, piece.D1 - from)
				local tilt = CFrame.new(hinge) * CFrame.Angles(rad(28 * t), 0, 0) * CFrame.new(-hinge)
				model:PivotTo(tilt * piece.Base)
				if not piece.Cracked then
					piece.Cracked = true
					for _, plank in piece.Planks do
						plank.Part.Color = plank.Color:Lerp(hot, 0.75)
					end
					local at = origin + Vector3.new(0, 0, -piece.D0)
					if not reduced and (at - camera.CFrame.Position).Magnitude < 160 then
						api:Effect("Poof", at, { Color3.fromRGB(150, 104, 70), Color3.fromRGB(255, 140, 60) })
					end
				end
				piece.State = "Tilt"
			else
				local t = now - SkateCourse.CollapseTime(collapse, piece.D1)
				local drop = 0.5 * 60 * t * t
				local tilt = CFrame.new(hinge - Vector3.new(0, drop, 0))
					* CFrame.Angles(rad(28 + t * 40), 0, rad(t * 8))
					* CFrame.new(-hinge)
				model:PivotTo(tilt * piece.Base)
				if not piece.Splashed and drop > LAVA_DEPTH then
					piece.Splashed = true
					local at = origin + Vector3.new(0, -LAVA_DEPTH, -(piece.D0 + piece.D1) / 2)
					if (at - camera.CFrame.Position).Magnitude < 220 then
						api:Effect("Poof", at, { Color3.fromRGB(255, 120, 40), Color3.fromRGB(90, 70, 70) })
					end
				end
				-- Gone once even its pier's tower tops are under the lava.
				if drop > LAVA_DEPTH + 80 then
					model:PivotTo(piece.Base - Vector3.new(0, 400, 0))
					piece.State = "Gone"
				end
			end
		end
	end

	-- Posing every skater ------------------------------------------------------------------------------

	local rigs: { [Model]: { [string]: { Motor: Motor6D, Current: CFrame } } } = {}
	local welds: { [Model]: Weld } = {} -- each skater's board weld, found once
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
		rigs[character] = rig
		return rig
	end

	local function poseFor(key: string, now: number): (string, number)
		if key == myKey then
			if outAt then
				return "Fall", 0
			elseif me.Place then
				return "Cheer", 0
			elseif SkateCourse.IsWiped(me, now) then
				return "Wipe", 0
			elseif SkateCourse.Height(me, now) > 0 then
				return "Air", 0
			end
			return "Ride", (now - kickAt) / KICK_TIME
		end
		local entry = racers[key]
		if not entry then
			return "Ride", 1
		end
		if entry.O then
			return "Fall", 0
		elseif entry.F then
			return "Cheer", 0
		elseif entry.W and entry.W > now then
			return "Wipe", 0
		elseif entry.A and now >= entry.A and now - entry.A < SkateCourse.AirTime then
			-- (A jump the server holds until its skater reaches the spot it was pressed at starts later.)
			return "Air", 0
		end
		local seen = kickSeen[key]
		return "Ride", if seen then (now - seen.At) / KICK_TIME else 1
	end

	local function boardPitch(key: string, now: number): number
		local air = nil
		if key == myKey then
			air = me.Air
		else
			local entry = racers[key]
			air = entry and entry.A
		end
		if not air then
			return 0
		end
		local x = (now - air) / SkateCourse.AirTime
		if x < 0 or x > 1 then
			return 0
		end
		-- Pop (nose up), level out, then nose down for the landing.
		return math.sin(x * math.pi * 2) * 16
	end

	local poseConnection = (RunService :: any).PreSimulation or RunService.Stepped
	api:Track(poseConnection:Connect(function(dt)
		if not race then
			return
		end
		local now = api:Now()
		local alpha = 1 - math.exp(-(if type(dt) == "number" then dt else 1 / 60) * 18)
		for key in race.Lane or {} do
			local character = api:CharacterOf(tonumber(key))
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not character or not root then
				continue
			end
			-- Only skaters on the course: someone sent back to the lobby gets their own animations back.
			local offset = root.Position - origin
			if math.abs(offset.X) > 120 or offset.Z > 120 or offset.Z < -length - 200 or offset.Y < -200 then
				local rig = rigs[character]
				if rig then
					for _, joint in rig do
						joint.Motor.Transform = CFrame.identity
					end
					rigs[character] = nil
					welds[character] = nil
				end
				continue
			end
			local mode, kick = poseFor(key, now)
			local target = targetPose(mode, kick, now)
			-- A skater just arrived on the course is in the stance from their first frame here (no
			-- crouching into it on the start line); after that, poses blend.
			local fresh = rigs[character] == nil
			for name, joint in rigOf(character) do
				local want = target[name] or CFrame.identity
				joint.Current = if fresh then want else joint.Current:Lerp(want, alpha)
				joint.Motor.Transform = joint.Current
			end
			local weld = welds[character]
			if not weld or weld.Parent == nil then
				-- Not found yet, or the board was replaced: look it up (only until it's found).
				local board = character:FindFirstChild("Skateboard")
				local found = board and board:FindFirstChild("BoardWeld", true)
				weld = if found and found:IsA("Weld") then found else nil
				welds[character] = weld
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if weld and humanoid then
				local height = SkateCourse.RootHeight(humanoid, root)
				weld.C0 = CFrame.new(0, -height, 0)
					* CFrame.Angles(0, 0, rad(-boardPitch(key, now)))
					* CFrame.Angles(0, rad(90), 0)
			end
		end
	end))
	api:Track(function()
		for character, rig in rigs do
			if character.Parent then
				for _, joint in rig do
					joint.Motor.Transform = CFrame.identity
				end
			end
		end
	end)

	-- Driving my skater, the camera and the HUD ---------------------------------------------------------

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
		local character = driving
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
		end
	end)

	local dangerShown = false
	local pushEnabled = nil :: boolean?
	local hintUntil = 0
	local lastPlace = ""

	api:RenderStep(function(dt)
		if not race then
			return
		end
		local now = api:Now()
		dt = math.min(dt, 0.1)
		updateBridge(now)

		-- My skater: the shared rules, run here.
		local character, humanoid, root = api:Character()
		local lane = myLane
		if lane and character and humanoid and root then
			local x = SkateCourse.LaneX(lane, lanes)
			if driving ~= character then
				-- Only take over a character that's actually standing at its lane (not one back in the lobby).
				local expected = origin + Vector3.new(x, 3, -me.D)
				if (root.Position - expected).Magnitude < 60 then
					driving = character
				end
			end
			if driving == character and not (outAt and now - outAt > 1.6) then
				watchJump(humanoid)
				if collapse and not me.Done then
					if hintUntil == 0 then
						hintUntil = os.clock() + 6
						api:Hint(
							if touch
								then "Mash PUSH • JUMP gaps • ride ⚡" -- (short: clear of the move stick)
								else "Mash PUSH • JUMP crates & gaps • ride ⚡ pads",
							hudY + 140
						)
					end
					local event = SkateCourse.Step(me, obstacles, now, dt)
					if event then
						SkateCourse.Apply(me, event, obstacles, event.At)
						if event.Kind ~= "Boost" then
							local o = obstacles[event.Index]
							wipeD = o and o.D
						end
						if event.Kind == "Boost" then
							fovPunch = 10
							api:Sound("Pickup")
							say("BOOST!", Theme.Colors.Yellow, 0.8)
						else
							shake = 0.6
							api:Sound("Hit")
							say(if event.Kind == "Fall" then "FELL IN!" else "WIPEOUT!", Theme.Colors.Red, 1.2)
						end
					end
					if me.D >= length then
						me.Done = true
					elseif SkateCourse.Caught(SkateCourse.CollapseAt(collapse, now, length), me.D, 0, length) then
						-- (The server's rule, from where I'm drawn: it adds the lead my screen has on it.)
						outAt = now
						me.Done = true
					end
				elseif me.Place or (me.Done and not outAt) then
					me.V = math.max(0, me.V - (8 + 0.6 * me.V) * dt)
					me.D = math.min(me.D + me.V * dt, length + SkateCourse.RunOut)
				end
				drawOffset *= math.exp(-dt * 6)
				local d, lift, tumble, drop = SkateCourse.Pose(me, now)
				if outAt then
					local t = now - outAt
					drop = 0.5 * 70 * t * t
					tumble = t * 1.5
				end
				local height = SkateCourse.RootHeight(humanoid, root)
				if not humanoid.PlatformStand then
					humanoid.PlatformStand = true
				end
				root.CFrame = SkateCourse.StanceCFrame(origin, x, d + drawOffset, height + lift - drop, tumble)
				root.AssemblyLinearVelocity = Vector3.new(0, 0, -me.V)
				root.AssemblyAngularVelocity = Vector3.zero

				-- Chase camera: behind and above, falling back and widening with speed.
				local target = origin + Vector3.new(x, 2.5 + lift * 0.5 - math.min(drop, 8), -(d + drawOffset))
				local desired = target + Vector3.new(0, CAMERA_UP, CAMERA_BACK)
				cameraPosition = if cameraPosition then cameraPosition:Lerp(desired, 1 - math.exp(-dt * 9)) else desired
				if not cameraTaken then
					cameraTaken = true
					camera.CameraType = Enum.CameraType.Scriptable
				end
				shake = math.max(0, shake - dt)
				fovPunch = math.max(0, fovPunch - dt * 14)
				local jolt = if shake > 0
					then Vector3.new(math.sin(now * 70), math.sin(now * 83), 0) * shake * 0.6
					else Vector3.zero
				local position = cameraPosition :: Vector3
				camera.CFrame = CFrame.lookAt(position + jolt, target + Vector3.new(0, 1, -24))
				camera.FieldOfView = 68 + 16 * math.clamp(me.V / 50, 0, 1) + fovPunch

				-- Wind streaks.
				local strength = math.clamp((me.V - 22) / 28, 0, 1)
				for index, streak in streaks do
					local at = streak.At
					if not at or at.Z > position.Z + 2 or at.Z < position.Z - 70 then
						local angle = (index / #streaks) * math.pi * 2 + math.random() * 0.4
						local radius = 3 + math.random() * 6
						at = position
							+ Vector3.new(
								math.cos(angle) * radius * 1.6,
								math.sin(angle) * radius,
								-30 - math.random() * 40
							)
						streak.At = at
					end
					streak.Part.Size = Vector3.new(0.07, 0.07, 2 + 7 * strength)
					streak.Part.CFrame = CFrame.new(at :: Vector3)
					streak.Part.Transparency = 1 - 0.55 * strength
				end
			elseif cameraTaken and outAt and now - outAt > 1.6 then
				releaseCamera()
				for _, streak in streaks do
					streak.Part.Transparency = 1
				end
			end
		end
		if outAt and now - outAt > 1.6 then
			releaseCamera()
		end

		-- HUD: the progress bar, my place, warnings.
		if collapse then
			local front = SkateCourse.CollapseAt(collapse, now, length)
			local fraction = math.clamp(front / length, 0, 1)
			fire.Size = UDim2.fromScale(fraction, 1)
			fireIcon.Position = UDim2.fromScale(fraction, 0.5)
			local danger = racing() and now > collapse.T0 + 0.5 and me.D - front < 45
			if danger and not dangerShown then
				dangerShown = true
				api:Sound("HazardWarning")
			end
			if danger then
				local warning = if touch then "⚠ FALLING! PUSH! ⚠" else "⚠ THE BRIDGE IS FALLING! PUSH! ⚠"
				if callout.Text ~= warning then
					setCallout(warning)
				end
				callout.TextColor3 = Color3.fromRGB(255, 110 + math.floor(math.sin(now * 12) * 60), 60)
				callout.Visible = true
				calloutUntil = os.clock() + 0.2
			elseif me.D - front > 80 then
				dangerShown = false
			end
		end
		if callout.Visible and os.clock() > calloutUntil then
			callout.Visible = false
		end
		if hintUntil > 0 and os.clock() > hintUntil then
			hintUntil = -1
			api:Hint("")
		end

		local order = {}
		for key, entry in racers do
			local d = if key == myKey and myLane
				then me.D
				else (entry.D or 0) + (entry.V or 0) * math.clamp(now - (entry.T or now), 0, 0.5)
			local dot = marker(key, entry.L or 1)
			dot.Position = UDim2.fromScale(math.clamp(d / length, 0, 1), 0.5)
			dot.BackgroundTransparency = if entry.O then 0.7 else 0
			table.insert(order, {
				Key = key,
				Score = if entry.F then 1e6 - entry.F elseif entry.O then -1e6 + d else d,
			})
		end
		for key, dot in markers do
			if not racers[key] then
				dot.Visible = false
			end
		end
		table.sort(order, function(a, b)
			return a.Score > b.Score
		end)
		local place = ""
		for index, item in order do
			if item.Key == myKey then
				local entry = racers[myKey]
				if entry and entry.O then
					place = "🌋 Fell in!"
				else
					place = `{SkateCourse.Ordinal(index)} of {#order}`
				end
			end
		end
		if place ~= lastPlace then
			lastPlace = place
			placeLabel.Text = place
		end
		push:SetFill(math.clamp(me.V / SkateCourse.Max, 0, 1))
		local canPush = racing()
		if canPush ~= pushEnabled then
			pushEnabled = canPush
			push:SetEnabled(canPush)
		end
	end)
end

return SkateEscape

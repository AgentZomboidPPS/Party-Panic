-- Client half of Dice Dash: draws the board race the server plans and sends ROLL.
--
-- The server shares the board ("Board": origin, tile kinds, the racers' numbers and colours), the
-- turn ("Turn": when it started, the roll deadline, when the hops start) and every racer's tile,
-- roll and this turn's timed moves ("Racers"). This client poses every character from those moves
-- (Logic/DiceDashBoard.Sample: the same plan for everyone, so all hops are smooth and in step),
-- spins a giant die over each racer's head until their number comes in, shows the callouts when
-- each effect happens ("Event") and keeps a race strip with every racer's badge from START to
-- FINISH. ROLL is a button (E), the jump button / Space (jump into your die), or a tap or click
-- anywhere on the board. The camera follows you along the board (the leader if you're watching).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Board = require(ReplicatedStorage.Shared.Logic.DiceDashBoard)
local RaceBar = require(ReplicatedStorage.Shared.Logic.RaceBar)

local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local DiceDash = {}

local rad = math.rad
local ROOT_Y = 3 -- an R6 root above the ground
local DIE_LIFT = 4.2 -- the die's bottom above a racer's head top
local PRESS_HOP = 0.4 -- seconds of the little hop into your die when you press ROLL

-- Which way a die turns to put each number on top (the mesh has 1 up, 2 front, 3 right).
local FACES = {
	CFrame.identity,
	CFrame.Angles(rad(90), 0, 0),
	CFrame.Angles(0, 0, rad(90)),
	CFrame.Angles(0, 0, rad(-90)),
	CFrame.Angles(rad(-90), 0, 0),
	CFrame.Angles(rad(180), 0, 0),
}

local EVENT_STYLE = {
	BOOST = { Color = Color3.fromRGB(120, 255, 140), Effect = "Stars", Sound = "Boing" },
	SLIP = { Color = Color3.fromRGB(255, 225, 80), Effect = "Poof", Sound = "Hit" },
	CANNON = { Color = Color3.fromRGB(255, 160, 70), Effect = "Poof", Sound = "Hit" },
	TRAP = { Color = Color3.fromRGB(255, 95, 105), Effect = "Poof", Sound = "Eliminated" },
	SWAP = { Color = Color3.fromRGB(255, 215, 60), Effect = "Sparkles", Sound = "Pickup" },
	EVENT = { Color = Color3.fromRGB(200, 160, 255), Effect = "Stars", Sound = "Boing" },
	GUST = { Color = Color3.fromRGB(140, 220, 255), Effect = "Poof", Sound = "HazardWarning" },
	LAST = { Color = Color3.fromRGB(200, 160, 255), Effect = "Confetti", Sound = "Boing" },
}

local JOINTS = {
	LeftUpperArm = "LeftShoulder",
	RightUpperArm = "RightShoulder",
	LeftUpperLeg = "LeftHip",
	RightUpperLeg = "RightHip",
	LeftLowerLeg = "LeftKnee",
	RightLowerLeg = "RightKnee",
}
local R6_JOINTS = { "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" }

-- A hopping racer tucks its legs and throws its arms up; a finished one waves both arms.
local function pose(air: number, cheer: boolean, t: number): { [string]: CFrame }
	local arm = if cheer then 150 + math.sin(t * 9) * 15 else 25 + air * 120
	local tuck = air * 45
	return {
		LeftShoulder = CFrame.Angles(0, 0, rad(-arm)),
		RightShoulder = CFrame.Angles(0, 0, rad(arm)),
		LeftHip = CFrame.Angles(rad(tuck), 0, 0),
		RightHip = CFrame.Angles(rad(tuck), 0, 0),
		LeftKnee = CFrame.Angles(rad(-tuck * 1.4), 0, 0),
		RightKnee = CFrame.Angles(rad(-tuck * 1.4), 0, 0),
		["Left Shoulder"] = CFrame.Angles(0, 0, rad(-arm)),
		["Right Shoulder"] = CFrame.Angles(0, 0, rad(arm)),
		["Left Hip"] = CFrame.Angles(0, 0, rad(-tuck)),
		["Right Hip"] = CFrame.Angles(0, 0, rad(tuck)),
	}
end

type Info = { N: number, C: Color3, Name: string }
type Entry = { P: number, D: number?, Au: number?, M: { Board.Move }?, F: number? }
type Die = { Model: Model, Size: number, Label: TextLabel, Board: BillboardGui, RolledAt: number?, Spin: number }

function DiceDash.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 250, 238),
		Saturation = 0.2,
		Contrast = 0.06,
		Brightness = 0.03,
		Haze = Color3.fromRGB(215, 235, 255),
		HazeDecay = Color3.fromRGB(175, 205, 240),
		Density = 0.2,
	})

	local myKey = tostring(Players.LocalPlayer.UserId)
	local camera = workspace.CurrentCamera
	local touch = api:IsTouch()

	local origin: Vector3? = nil
	local roster: { [string]: Info } = {}
	local function readBoard()
		local value = api:SharedJSON("Board")
		if type(value) ~= "table" or type(value.O) ~= "table" then
			return
		end
		origin = Vector3.new(value.O[1], value.O[2], value.O[3])
		for _, item in value.R or {} do
			local c = item.C or { 255, 255, 255 }
			roster[tostring(item.U)] = {
				N = tonumber(item.N) or 0,
				C = Color3.fromRGB(c[1], c[2], c[3]),
				Name = tostring(item.Name or ""),
			}
		end
	end
	readBoard()
	api:OnShared("Board", readBoard)

	local turn: { N: number, A: number, E: number, M: number? } = { N = 0, A = 0, E = 0 }
	local function readTurn()
		local value = api:SharedJSON("Turn")
		if type(value) == "table" and type(value.A) == "number" then
			turn = { N = tonumber(value.N) or 0, A = value.A, E = tonumber(value.E) or value.A, M = value.M }
		end
	end
	readTurn()
	api:OnShared("Turn", readTurn)

	local racers: { [string]: Entry } = {}
	local function readRacers()
		local value = api:SharedJSON("Racers")
		if type(value) == "table" and type(value.R) == "table" then
			racers = value.R
		end
	end
	readRacers()
	api:OnShared("Racers", readRacers)

	local stage = api:Shared("Stage") or "Ready"
	api:OnShared("Stage", function(value)
		stage = value or stage
	end)

	-- Dice ---------------------------------------------------------------------------------------------

	local template = nil :: Instance?
	task.spawn(function()
		template = api:Template("DiceDashDie", 30)
	end)
	local dice: { [string]: Die } = {}
	local function dieFor(key: string): Die?
		local existing = dice[key]
		if existing then
			return existing
		end
		if not template then
			return nil
		end
		local info = roster[key]
		local model = (template :: Instance):Clone() :: Model
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				if part.Name == "Body" and info then
					part.Color = info.C:Lerp(Color3.new(1, 1, 1), 0.25)
				elseif part.Name == "Pips" then
					part.Color = Color3.fromRGB(255, 255, 255)
				end
			end
		end
		model.Name = "Die_" .. key
		model.Parent = api.World
		local size = model:GetExtentsSize().Y
		local gui = Instance.new("BillboardGui")
		gui.Name = "Number"
		gui.Size = UDim2.fromOffset(70, 70)
		gui.StudsOffsetWorldSpace = Vector3.new(0, size + 1.6, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 140
		gui.Enabled = false
		gui.Adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		gui.Parent = api.World -- (it stays up while the die is put away during the hops)
		local label = UIKit.Label({
			Name = "Value",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = 54,
			TextColor3 = if info then info.C:Lerp(Color3.new(1, 1, 1), 0.35) else Theme.Colors.Text,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0) },
		})
		local die: Die = {
			Model = model,
			Size = size,
			Label = label,
			Board = gui,
			Spin = (tonumber(key) or 0) % 7,
		}
		dice[key] = die
		return die
	end

	-- Posing ---------------------------------------------------------------------------------------------

	local rigs: { [Model]: { [string]: { Motor: Motor6D, Current: CFrame } } } = {}
	local posed: { [Model]: { Air: number, Cheer: boolean } } = {}
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
	local poseConnection = (RunService :: any).PreSimulation or RunService.Stepped
	api:Track(poseConnection:Connect(function(dt)
		local step = if type(dt) == "number" then dt else 1 / 60
		local alpha = 1 - math.exp(-step * 16)
		local t = os.clock()
		for character, state in posed do
			if not character.Parent then
				posed[character] = nil
				rigs[character] = nil
				continue
			end
			local target = pose(state.Air, state.Cheer, t)
			for name, joint in rigOf(character) do
				joint.Current = joint.Current:Lerp(target[name] or CFrame.identity, alpha)
				joint.Motor.Transform = joint.Current
			end
		end
	end))

	-- HUD ------------------------------------------------------------------------------------------------

	local hud = api:TopHud()
	local hudY = api:HudY()
	local barWidth = 560
	local trackLength = barWidth - 96
	local DOT = if touch then 33 else 26
	local MY_DOT = if touch then 39 else 32
	local LIFT = if touch then 16 else 13
	local barHeight = if touch then 66 else 52
	local bar = UIKit.Panel({
		Name = "RaceStrip",
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
		Size = UDim2.new(0, trackLength, 0, 8),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = bar,
		Children = { UIKit.Round() },
	})
	UIKit.Label({
		Name = "Start",
		Text = "🎲",
		TextSize = if touch then 24 else 22,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -20, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		Parent = lane,
	})
	UIKit.Label({
		Name = "Goal",
		Text = "🏁",
		TextSize = if touch then 24 else 22,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 20, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		Parent = lane,
	})
	local markers: { [string]: Frame } = {}
	local function marker(key: string): Frame
		local existing = markers[key]
		if existing then
			return existing
		end
		local info = roster[key]
		local isMine = key == myKey
		local size = if isMine then MY_DOT else DOT
		local dot = UIKit.new("Frame", {
			Name = "Racer" .. key,
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
		UIKit.Label({
			Text = tostring(if info then info.N else "?"),
			TextSize = if touch then (if isMine then 29 else 25) else (if isMine then 22 else 19),
			Font = Theme.Fonts.Bold,
			TextColor3 = Color3.fromRGB(30, 24, 40),
			Size = UDim2.fromScale(1, 1),
			ZIndex = dot.ZIndex,
			Parent = dot,
		})
		markers[key] = dot
		return dot
	end

	-- (on phones the text under the strip sits right of the middle, clear of the thumbstick corner)
	local shiftX = if touch then 90 else 0
	local promptY = hudY + barHeight + 10
	local prompt = UIKit.Label({
		Name = "Prompt",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 30 else 32,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, shiftX, 0, promptY),
		Size = UDim2.fromOffset(if touch then 340 else 420, 38),
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})
	local callout = UIKit.Label({
		Name = "Callout",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 32 else 42,
		TextScaled = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, shiftX, 0, promptY + 44),
		Size = UDim2.fromOffset(if touch then 380 else 620, 48),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.05) },
	})
	local calloutUntil = 0
	local function say(text: string, color: Color3, seconds: number)
		callout.Text = text
		callout.TextColor3 = color
		callout.Visible = true
		callout.TextSize = if touch then 32 else 42
		calloutUntil = os.clock() + seconds
	end

	-- Controls ---------------------------------------------------------------------------------------------

	local roll = api:Button({ Text = "ROLL", Key = Enum.KeyCode.E, Color = Theme.Colors.Yellow })
	local pressedTurn = -1
	local pressAt = -math.huge
	local function canRoll(): boolean
		local mine = racers[myKey]
		local now = api:Now()
		return stage == "Race"
			and mine ~= nil
			and mine.D == nil
			and mine.F == nil
			and turn.M == nil
			and now >= turn.A
			and pressedTurn ~= turn.N
			and api:CanAct()
	end
	local function doRoll()
		if not canRoll() then
			return
		end
		pressedTurn = turn.N
		pressAt = os.clock()
		api:Action("Roll")
		api:Sound("Click")
	end
	roll.Pressed:Connect(doRoll)
	api:Track(UserInputService.JumpRequest:Connect(doRoll))
	api:Track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			doRoll()
		end
	end))

	-- Events: callouts when each effect happens (mine first), with a burst on the tile.
	local queue: { any } = {}
	api:OnEvent("Event", function(data)
		if type(data) == "table" and type(data.At) == "number" then
			table.insert(queue, data)
		end
	end)
	api:OnEvent("Finish", function(userId, place)
		local key = tostring(userId)
		local info = roster[key]
		local spot = if origin then origin + Board.Spot(Board.LAST) else nil
		if spot then
			api:Effect("Confetti", spot + Vector3.new(0, 4, 0), if info then { info.C } else nil)
		end
		if key == myKey then
			say(`🏁 You finished {Board.Ordinal(tonumber(place) or 1)}!`, Theme.Colors.Yellow, 2.5)
			api:Sound("Victory")
		elseif info and place == 1 then
			say(`🏁 {info.Name} wins!`, Theme.Colors.Yellow, 2)
		end
	end)

	-- Camera -----------------------------------------------------------------------------------------------

	local cameraFocus: Vector3? = nil
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
		for character in posed do
			local rig = rigs[character]
			if rig then
				for _, joint in rig do
					joint.Motor.Transform = CFrame.identity
				end
			end
		end
		table.clear(posed)
		local _, humanoid, root = api:Character()
		if humanoid then
			humanoid.PlatformStand = false
		end
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)

	-- Every frame -----------------------------------------------------------------------------------------

	local offsets: { [string]: Vector3 } = {}
	local dotX: { [string]: number } = {}
	local dotTiers: { [string]: number } = {}
	local dotRanks: { [string]: number } = {}

	api:RenderStep(function(dt)
		local base = origin
		if not base then
			return
		end
		local now = api:Now()
		local ease = 1 - math.exp(-dt * 10)

		-- Who rests on which tile (they stand in a ring there).
		local samples: { [string]: Board.Sample } = {}
		local rests: { [number]: { string } } = {}
		for key, entry in racers do
			local sample = Board.Sample(entry.M, tonumber(entry.P) or 0, now)
			samples[key] = sample
			local rest = sample.Rest
			if rest then
				local list = rests[rest] or {}
				rests[rest] = list
				table.insert(list, key)
			end
		end
		for _, list in rests do
			table.sort(list, function(a, b)
				return (roster[a] and roster[a].N or 0) < (roster[b] and roster[b].N or 0)
			end)
		end

		local focus: Vector3? = nil
		local leaderKey, leaderScore = nil, -math.huge
		local dots = {}
		local seen = {}
		for key, entry in racers do
			seen[key] = true
			local sample = samples[key]
			local target = Vector3.zero
			local rest = sample.Rest
			if rest then
				local list = rests[rest]
				target = Board.Ring(table.find(list, key) or 1, #list, rest == 0 or rest == Board.LAST)
			end
			local offset = (offsets[key] or target):Lerp(target, ease)
			offsets[key] = offset
			local feet = base + sample.Position + offset
			if key == myKey and os.clock() - pressAt < PRESS_HOP then
				feet += Vector3.new(0, 2.6 * math.sin(math.pi * (os.clock() - pressAt) / PRESS_HOP), 0)
			end
			if sample.Hidden then
				feet -= Vector3.new(0, 4, 0)
			end

			-- The character.
			local character = api:CharacterOf(tonumber(key))
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local headTop = feet.Y + 5.2
			if character and root then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				local rootY = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15
					then humanoid.HipHeight + root.Size.Y / 2
					else ROOT_Y
				if key == myKey then
					if humanoid and not humanoid.PlatformStand then
						humanoid.PlatformStand = true
					end
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end
				root.CFrame = CFrame.new(feet + Vector3.new(0, rootY, 0)) * CFrame.Angles(0, sample.Yaw, 0)
				headTop = feet.Y + rootY + root.Size.Y / 2 + 1.4
				posed[character] = { Air = sample.Air, Cheer = entry.F ~= nil and sample.Rest ~= nil }
			end

			-- The die over the head: spinning until the number comes in, then it settles on it.
			local rolling = stage == "Race" and entry.F == nil and now >= turn.A and (turn.M == nil or now < turn.M)
			local die = if rolling or dice[key] then dieFor(key) else nil
			if die then
				local value = tonumber(entry.D)
				local walking = turn.M ~= nil and value ~= nil and now < turn.M + value * Board.HOP + 0.1
				local show = rolling or walking
				local parent = if rolling then api.World else nil
				if die.Model.Parent ~= parent then
					die.Model.Parent = parent
				end
				die.Board.Enabled = show and value ~= nil
				if rolling then
					local center = Vector3.new(feet.X, headTop + DIE_LIFT + die.Size / 2, feet.Z)
					local spin = now * 1.0 + die.Spin
					local turnCF
					if value and FACES[value] then
						die.RolledAt = die.RolledAt or now
						local u = math.clamp((now - (die.RolledAt :: number)) / 0.25, 0, 1)
						local settle = CFrame.Angles(0, sample.Yaw, 0) * FACES[value]
						local spinning = CFrame.Angles(spin * 7, spin * 9.3, spin * 5.1)
						turnCF = spinning:Lerp(settle, 1 - (1 - u) ^ 3)
						center += Vector3.new(0, 0.8 * math.sin(math.pi * u), 0)
					else
						die.RolledAt = nil
						turnCF = CFrame.Angles(spin * 7, spin * 9.3, spin * 5.1)
					end
					die.Model:PivotTo(CFrame.new(center) * turnCF * CFrame.new(0, -die.Size / 2, 0))
				end
				if value and show then
					local left = if walking
							and turn.M
							and now >= turn.M
						then math.max(0, value - math.floor((now - turn.M) / Board.HOP))
						else value
					die.Label.Text = if left > 0 then tostring(left) else ""
					if not rolling then
						die.Board.Adornee = root
						die.Board.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
					else
						die.Board.Adornee = die.Model.PrimaryPart or die.Model:FindFirstChildWhichIsA("BasePart")
						die.Board.StudsOffsetWorldSpace = Vector3.new(0, die.Size + 1.6, 0)
					end
				end
			end

			if key == myKey then
				focus = feet
			end
			local progress = if entry.F
				then Board.LAST + 1 - (tonumber(entry.F) or 0) * 0.01
				else (sample.Rest or entry.P)
			if progress > leaderScore then
				leaderKey, leaderScore = key, progress
			end

			-- The race strip badge (between tiles it slides along with the hop).
			local d = math.clamp(sample.Rest or dotX[key] or tonumber(entry.P) or 0, 0, Board.LAST)
			local shownX = dotX[key] or d
			shownX += (d - shownX) * (1 - math.exp(-dt * 6))
			dotX[key] = shownX
			local dot = marker(key)
			dot.Visible = true
			table.insert(dots, {
				Key = key,
				X = shownX / Board.LAST * trackLength,
				Size = if key == myKey then MY_DOT else DOT,
				Tier = dotTiers[key],
				Rank = dotRanks[key],
			})
		end
		for key, dot in markers do
			if not seen[key] then
				dot.Visible = false
			end
		end
		for key, die in dice do
			if not seen[key] then
				die.Model:Destroy()
				die.Board:Destroy()
				dice[key] = nil
			end
		end
		local spots = RaceBar.Layout(dots, { Width = trackLength, Lift = LIFT })
		for _, item in dots do
			local spot = spots[item.Key]
			dotTiers[item.Key] = spot.Tier
			dotRanks[item.Key] = spot.Rank
			markers[item.Key].Position = UDim2.new(0, spot.X, 0.5, spot.Y)
		end

		-- The prompt under the strip.
		local mine = racers[myKey]
		if stage ~= "Race" then
			prompt.Text = if stage == "Ready" then "🎲 Get ready to ROLL!" else ""
			prompt.TextColor3 = Theme.Colors.Text
		elseif mine and mine.F then
			prompt.Text = `🏁 You finished {Board.Ordinal(tonumber(mine.F) or 1)}!`
			prompt.TextColor3 = Theme.Colors.Yellow
		elseif mine and mine.D == nil and turn.M == nil and now >= turn.A then
			local left = math.max(0, turn.E - now)
			prompt.Text = `🎲 ROLL!  {string.format("%.1f", left)}s`
			prompt.TextColor3 = Theme.Colors.Yellow
		elseif mine and mine.D then
			prompt.Text = if mine.Au then `🎲 Auto roll: {mine.D}` else `🎲 You rolled {mine.D}!`
			prompt.TextColor3 = Theme.Colors.Text
		elseif mine then
			local tile = math.floor(tonumber(mine.P) or 0)
			prompt.Text = if tile <= 0 then "At START" else `Tile {tile} of {Board.LAST}`
			prompt.TextColor3 = Theme.Colors.Text
		else
			prompt.Text = ""
		end
		local rollable = canRoll()
		roll:SetEnabled(rollable)
		roll:SetFill(if rollable then math.clamp((turn.E - now) / Board.ROLL_WINDOW, 0, 1) else 0)

		-- Callouts as their moments come (mine always; others when nothing of mine is showing).
		local index = 1
		while index <= #queue do
			local item = queue[index]
			if now < item.At then
				index += 1
				continue
			end
			table.remove(queue, index)
			local involved = false
			for _, id in item.U or {} do
				if tostring(id) == myKey then
					involved = true
				end
			end
			local style = EVENT_STYLE[item.K] or EVENT_STYLE.EVENT
			local text = tostring(item.T or "")
			if now - item.At < 1.2 and (involved or os.clock() >= calloutUntil - 0.6) then
				say(text, style.Color, if involved then 2 else 1.4)
			end
			if involved then
				api:Sound(style.Sound)
			end
			local tile = tonumber(item.P)
			if tile and now - item.At < 1 then
				api:Effect(style.Effect, base + Board.Spot(tile) + Vector3.new(0, 3, 0), { style.Color })
			end
		end
		if callout.Visible and os.clock() > calloutUntil then
			callout.Visible = false
		end

		-- The camera follows me along the board (the leader if I'm watching), from the south side.
		if stage ~= "Done" then
			local target = focus
			if not target and leaderKey and racers[leaderKey] then
				local sample = samples[leaderKey]
				target = base + sample.Position
			end
			if target then
				local flat = Vector3.new(target.X, base.Y + Board.TOP + math.min(4, target.Y - base.Y), target.Z)
				cameraFocus = if cameraFocus then cameraFocus:Lerp(flat, 1 - math.exp(-dt * 4)) else flat
				if not cameraTaken then
					cameraTaken = true
					camera.CameraType = Enum.CameraType.Scriptable
				end
				local at = cameraFocus :: Vector3
				camera.CFrame = CFrame.lookAt(at + Vector3.new(0, 30, 31), at + Vector3.new(0, 1, -3))
				camera.FieldOfView = 58
			end
		else
			releaseCamera()
		end
	end)
end

return DiceDash

-- Client half of Last Dancer: the note highway with its four pads, the groove meter with the cut line,
-- and the disco floor's lights, all drawn from the chart and the state the server shares.
--
-- The highway sits at the bottom of the screen: notes fall down four lanes (▲ ■ ● ◆, each its own colour
-- too) towards the pads, and a tap on a pad when a note reaches it is a hit. Phones tap the pads (they
-- take the touch the moment it lands, so two fingers work); PC uses D F J K. The notes come from the same
-- chart as the server's and are timed by the same clock (the server's, shared as "Go"), so what falls
-- here is what the server judges. This client also runs the same judging logic (Logic/LastDancer) on
-- the player's own taps for instant PERFECT / GREAT / OK / MISS text and a combo; the server judges
-- again, from the taps it receives, and its numbers are the ones that count (the groove meter shows its
-- "Board", not this prediction).
--
-- SYNC. The sound reaches a player a little after the clock says (a late-loading song, Bluetooth speakers can
-- add 200 ms), so notes can look early to the ear. The + and - beside the highway shift the picture and the
-- taps' time by 25 ms a step (0 to 300 ms) until the notes land on the beat; that setting is kept for the
-- rest of the visit. On top of it the client measures how far behind where it should be the song is playing
-- (the song's own TimePosition against the shared clock, which the audio only corrects once it is 0.35 s
-- off) and shifts by that too. The total is told to the server (it waits that long before counting a note
-- as missed). If the round's song isn't playing (it hasn't loaded, or isn't uploaded) a quiet tick keeps the beat.
--
-- The meters: GROOVE (the server's number for this dancer, with a tick where the cut line is: whoever is
-- left of it is in DANGER), the place among the dancers still on the floor, and the next cut (when, how
-- many fall). Dancers about to fall flash red on their mats for a third of a second before the drop.
--
-- The dance mat (owner: "I want it to show your character basically playing on a DDR mat from an arcade").
-- Every dancer stands on an arcade dance mat, and the four lanes are its four arrows (LEFT DOWN UP RIGHT,
-- Logic.ARROWS): each tap, a dancer's own or one of the others' (the server batches everyone's steps), lights
-- that arrow panel and makes the character step onto it: the body shifts over the panel, the foot goes out,
-- they hop and lean. Between steps they dance on the beat as before. Arrow keys work as well as D F J K.
-- Anyone watching (cut, or sitting out) sees the standings instead of the highway.

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Chart = require(ReplicatedStorage.Shared.LastDancerChart)
local GameState = require(ReplicatedStorage.Shared.GameState)
local Logic = require(ReplicatedStorage.Shared.Logic.LastDancer)
local SongTiming = require(ReplicatedStorage.Shared.Logic.SongTiming)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local Pose = require(script.Parent.Parent.Pose)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local LastDancer = {}

local GLYPH = "▲" -- every arrow is this triangle turned (Logic.ARROWS[lane].Rotation)
local LANE_COLORS = {}
local KEYCODES: { [Enum.KeyCode]: number } = {} -- which key steps on which arrow
local KEYLIST: { Enum.KeyCode } = {}
for lane, arrow in Logic.ARROWS do
	LANE_COLORS[lane] = Color3.fromRGB(arrow.Color[1], arrow.Color[2], arrow.Color[3])
	for _, key in arrow.Keys do
		local code = (Enum.KeyCode :: any)[key] :: Enum.KeyCode
		KEYCODES[code] = lane
		table.insert(KEYLIST, code)
	end
end
local KEY_NAMES = { "D", "F", "J", "K" } -- shown under the pads on a computer (the arrow keys work too)
local STEP_CODES = { Perfect = 1, Great = 2, Ok = 3, Stray = 4, Late = 4 } -- as the server sends them
local STEP_SHIFT = 2.3 -- how far a dancer's body goes over the panel they step on (studs)
local STEP_LIFE = 0.4 -- a step's animation (seconds)
local JUDGE_COLORS = {
	Perfect = Color3.fromRGB(120, 235, 255),
	Great = Color3.fromRGB(140, 255, 150),
	Ok = Color3.fromRGB(255, 225, 90),
	Miss = Color3.fromRGB(255, 100, 110),
}
local JUDGE_TEXT = { Perfect = "PERFECT!", Great = "GREAT", Ok = "OK", Miss = "MISS" }

-- The highway, in design units (the holder scales to the screen).
local LANE_W = 78
local LANE_GAP = 6
local WIDTH = Logic.LANES * LANE_W + (Logic.LANES + 1) * LANE_GAP
local HIGHWAY_H = 230 -- from the top to the hit line
local PAD_H = 74
local NOTE_H = 36
local TRAVEL = 1.5 -- seconds from the top of the highway to the hit line

local SIDE = 84 -- the SYNC column beside the highway (design units)
local SYNC_STEP = 0.025
local savedSync = 0 -- the player's own sync setting, kept for the rest of the visit

local function laneX(lane: number): number
	return LANE_GAP + (lane - 1) * (LANE_W + LANE_GAP) + LANE_W / 2
end

-- One of the shared sound effects at a pitch of our own (falls back to the plain effect).
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

-- The dance ----------------------------------------------------------------------------------------------
-- Every dancer, bots too, moves to the beat on their mat, drawn on this device only: the character's R15
-- joints get an offset on top of the Animator's pose (client/Pose: a Motor6D or the AnimationConstraint this
-- place's R15 bodies have, written just before physics so it shows) that hops, sways, nods and lifts the
-- arms in time. A dancer in form (a high groove) dances big; one losing the beat droops; one whose mat is
-- flashing red flails. Every joint is handed back to the Animator when the round ends.

type Rig = {
	Root: Pose.Joint,
	Waist: Pose.Joint?,
	Neck: Pose.Joint?,
	LeftArm: Pose.Joint?,
	RightArm: Pose.Joint?,
	LeftLeg: Pose.Joint?,
	RightLeg: Pose.Joint?,
	All: { Pose.Joint },
	Offsets: { [Pose.Joint]: CFrame }, -- this frame's dance, written by `apply`
}
type Step = { Dx: number, Dz: number, Env: number, Foot: number }

local function rigOf(character: Model): Rig?
	local root = Pose.Joint(character, "Root")
	if not root then
		return nil -- (not an R15 rig)
	end
	local rig: Rig = {
		Root = root,
		Waist = Pose.Joint(character, "Waist"),
		Neck = Pose.Joint(character, "Neck"),
		LeftArm = Pose.Joint(character, "LeftShoulder"),
		RightArm = Pose.Joint(character, "RightShoulder"),
		LeftLeg = Pose.Joint(character, "LeftHip"),
		RightLeg = Pose.Joint(character, "RightHip"),
		All = {},
		Offsets = {},
	}
	for _, entry in { rig.Root, rig.Waist, rig.Neck, rig.LeftArm, rig.RightArm, rig.LeftLeg, rig.RightLeg } do
		table.insert(rig.All, entry)
	end
	return rig
end

local function restore(rig: Rig)
	table.clear(rig.Offsets)
	Pose.ReleaseAll(rig.All)
end

local function pose(rig: Rig, entry: Pose.Joint?, offset: CFrame)
	if entry then
		rig.Offsets[entry] = offset
	end
end

-- Writes a rig's dance over what the Animator gave each joint this frame (the offset in the joint's first
-- part's axes, about the joint: what an offset on a Motor6D's C0 did).
local function apply(rig: Rig)
	for entry, offset in rig.Offsets do
		if entry.Instance.Parent then
			local under = Pose.Under((entry.Instance :: any).Transform, entry.Written, entry.Under)
			entry.Under = under
			Pose.Set(entry, entry.Base:Inverse() * offset * entry.Base * under)
		end
	end
end

-- One frame of dancing for a rig: `beat` counts beats, `energy` is 0-1, `phase` offsets this dancer from
-- the others, `panic` is true for a dancer about to fall, `step` is the arrow they are stepping on (if
-- they just did). A step moves the whole body over the panel (the Root joint's offset is in the dancer's
-- own frame: +X their right, -Z the way they face, the way the UP arrow lies), puts that foot out (a hip
-- turned about Z for a side step, about X for forward and back: R15 hips hang the leg down -Y, so +Z
-- swings it to +X and +X swings it to -Z), hops a little and leans the way they went.
local function dance(rig: Rig, beat: number, energy: number, phase: number, panic: boolean, step: Step?)
	local t = beat + phase
	local hop = math.abs(math.sin(math.pi * (t % 1))) -- up on the beat, down between
	local sway = math.sin(t * math.pi) -- side to side every two beats
	local e = if panic then 1 else energy
	local shiftX, shiftY, shiftZ = 0, 0, 0
	local lean, legLeft, legRight = CFrame.identity, CFrame.identity, CFrame.identity
	if step then
		local env = step.Env
		shiftX, shiftY, shiftZ = step.Dx * STEP_SHIFT * env, 0.4 * env, step.Dz * STEP_SHIFT * env
		if step.Dx > 0 then
			legRight = CFrame.Angles(0, 0, 0.6 * env)
		elseif step.Dx < 0 then
			legLeft = CFrame.Angles(0, 0, -0.6 * env)
		else
			local swing = if step.Dz < 0 then 0.8 * env else -0.6 * env
			if step.Foot == 1 then
				legLeft = CFrame.Angles(swing, 0, 0)
			else
				legRight = CFrame.Angles(swing, 0, 0)
			end
		end
		lean = CFrame.Angles(step.Dz * 0.2 * env, 0, -step.Dx * 0.2 * env)
	end
	pose(rig, rig.Root, CFrame.new(shiftX, 0.3 * e * hop + shiftY, shiftZ) * CFrame.Angles(0, sway * 0.3 * e, 0))
	pose(rig, rig.Waist, CFrame.Angles(-0.12 * e * hop, 0, sway * 0.12 * e) * lean)
	pose(rig, rig.LeftLeg, legLeft)
	pose(rig, rig.RightLeg, legRight)
	pose(rig, rig.Neck, CFrame.Angles((0.15 * hop - 0.25 * (1 - e)) * (if panic then 0.2 else 1), 0, -sway * 0.1 * e))
	-- arms: alternately up on the beat when in form, hanging slack when not (flailing when about to fall)
	local lift = 0.15 + 1.9 * e * e
	local right = lift * math.max(0, sway) + 0.12 * e
	local left = lift * math.max(0, -sway) + 0.12 * e
	if panic then
		local flail = math.sin(os.clock() * 20)
		right, left = 2.6 + flail * 0.5, 2.6 - flail * 0.5
	end
	pose(rig, rig.RightArm, CFrame.Angles(0, 0, right))
	pose(rig, rig.LeftArm, CFrame.Angles(0, 0, -left))
end

local function percentText(groove: number): string
	return `{math.clamp(math.floor(groove + 0.5), 0, 100)}%`
end

function LastDancer.Start(api)
	-- A club at midnight: the floor's own lights are the show (put back afterwards).
	api:Mood({
		Tint = Color3.fromRGB(235, 205, 255),
		Saturation = 0.3,
		Contrast = 0.12,
		Brightness = -0.03,
		Haze = Color3.fromRGB(120, 60, 190),
		HazeDecay = Color3.fromRGB(60, 25, 110),
		Density = 0.22,
	})
	local clockTime = Lighting.ClockTime
	Lighting.ClockTime = 0
	api:Track(function()
		Lighting.ClockTime = clockTime
	end)
	local waited = 0
	while (not api:Shared("Go") or not api:SharedJSON("Floor")) and waited < 10 do
		waited += task.wait(0.1)
	end
	local go = api:Shared("Go")
	local floor = api:SharedJSON("Floor")
	local arena = api:Arena(10)
	-- GO moves when the round began late (server/MiniGames/LastDancer Start), possibly while the arena was
	-- still arriving: read it again now, and follow it from here on, the song too.
	go = api:Shared("Go") or go
	if type(go) ~= "number" or not floor or not arena then
		return
	end
	api:OnShared("Go", function(value)
		if type(value) == "number" and value ~= go then
			go = value
			AudioController.ResyncModeSong()
		end
	end)
	local touch = api:IsTouch()
	local effects = not State.ReducedEffects()
	local me = Players.LocalPlayer.UserId
	local notes = Chart.Notes

	-- Who stepped on which arrow when (everyone's, own taps at once and the others' from the server's batches).
	local steps: { [number]: { Lane: number, At: number, Foot: number } } = {}
	local flashes: { [number]: { [number]: { At: number, Code: number } } } = {}
	local feet: { [number]: number } = {}
	local function stepOn(userId: number, lane: number, code: number)
		local now = os.clock()
		local foot = (feet[userId] or 0) % 2 + 1 -- up and down steps alternate feet
		feet[userId] = foot
		steps[userId] = { Lane = lane, At = now, Foot = foot }
		local list = flashes[userId]
		if not list then
			list = {}
			flashes[userId] = list
		end
		list[lane] = { At = now, Code = code }
	end

	local mine = Logic.new() -- this player's taps judged here, for the instant feedback
	local results: { [number]: string } = {} -- note index -> what happened to it
	local manual = savedSync -- the player's own setting
	local auto = 0 -- what the song's measured lateness adds
	local sync = math.clamp(manual, 0, Logic.SYNC_MAX) -- the total in use: the picture and the taps are this late

	-- The people in the round (names for the banners and the standings).
	local function nameOf(userId: number): string
		for _, participant in api:Participants() do
			if participant.UserId == userId then
				return participant.DisplayName
			end
		end
		return "A dancer"
	end
	local function namesOf(ids: { number }): string
		local names = {}
		for _, id in ids do
			table.insert(names, if id == me then "YOU" else nameOf(id))
		end
		return table.concat(names, ", ")
	end

	-- The server's board: {userId, groove %, points, alive, combo} for every dancer.
	local board = {}
	local function readBoard()
		board = api:SharedJSON("Board") or {}
	end
	readBoard()
	local cut = api:SharedJSON("Cut") or {}

	local function myRow()
		for _, row in board do
			if row[1] == me then
				return row
			end
		end
		return nil
	end
	-- Whether this player is still dancing: in the round and on the floor (the board knows a moment before
	-- the server's own "out" reaches this device).
	local function dancing(): boolean
		if not api:CanAct() then
			return false
		end
		local row = myRow()
		return row == nil or row[4] == 1
	end
	local function aliveGrooves(): { number }
		local list = {}
		for _, row in board do
			if row[4] == 1 then
				table.insert(list, row[2])
			end
		end
		table.sort(list)
		return list
	end
	-- The groove a dancer needs to be safe at the next cut: between the lowest `count` and the rest.
	local function cutLine(): number?
		local count = cut.Count or 0
		local list = aliveGrooves()
		if count <= 0 or count >= #list then
			return nil
		end
		return (list[count] + list[count + 1]) / 2
	end

	-- HUD ------------------------------------------------------------------------------------------
	-- (Three rows under the round banner, all above the thumbstick zone's top on phones: the groove meter,
	-- the next cut, and the announcements.)
	local hud = api:TopHud()
	local y = api:HudY()
	local meter = UIKit.new("Frame", {
		Name = "GroovePanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(470, 62),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.2,
		Parent = hud,
		Children = { UIKit.Corner(16), UIKit.Stroke(Color3.new(1, 1, 1), 3, 0.35) },
	})
	local meterStroke = meter:FindFirstChildOfClass("UIStroke") :: UIStroke
	UIKit.Label({
		Name = "Title",
		Text = "GROOVE",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 2),
		Size = UDim2.fromOffset(130, 28),
		Parent = meter,
		Children = { UIKit.TextStroke(0.2) },
	})
	local percent = UIKit.Label({
		Name = "Percent",
		Text = "60%",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -204, 0, 0),
		Size = UDim2.fromOffset(84, 30),
		Parent = meter,
		Children = { UIKit.TextStroke(0.2) },
	})
	local place = UIKit.Label({
		Name = "Place",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -112, 0, 2),
		Size = UDim2.fromOffset(100, 28),
		Parent = meter,
		Children = { UIKit.TextStroke(0.2) },
	})
	local track = UIKit.new("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(14, 36),
		Size = UDim2.new(1, -28, 0, 18),
		BackgroundColor3 = Color3.fromRGB(14, 10, 34),
		Parent = meter,
		Children = { UIKit.Round() },
	})
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.6, 1),
		BackgroundColor3 = Theme.Colors.Green,
		Parent = track,
		Children = { UIKit.Round() },
	})
	local line = UIKit.new("Frame", {
		Name = "CutLine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 5, 1, 10),
		BackgroundColor3 = Theme.Colors.Red,
		Visible = false,
		ZIndex = 3,
		Parent = track,
		Children = { UIKit.Corner(2) },
	})

	-- The next cut; in danger it turns red and flashes ("DANGER!" first).
	local ticker = UIKit.Label({
		Name = "CutTicker",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y + 64),
		Size = UDim2.fromOffset(580, 30),
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})
	-- Announcements (who is about to fall, who fell) and, before the first one, the hint. On phones it's
	-- only as wide as its words, clear of the judgement over the highway and of the thumbstick's corner
	-- (and the hint is shown here too, for the same reason).
	local banner = UIKit.Label({
		Name = "Banner",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 28,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y + 96),
		Size = UDim2.fromOffset(600, 34),
		TextTransparency = 1,
		Parent = hud,
		Children = { UIKit.TextStroke(0.1), UIKit.new("UITextSizeConstraint", { MaxTextSize = 28 }) },
	})
	local function hideHint()
		if api.Gui.Parent then
			api:Hint("", y + 96)
		end
	end
	local function showBanner(text: string, color: Color3?, life: number?)
		hideHint()
		if touch then
			-- (as wide as its words, up to 520; longer ones, two names about to fall, shrink to fit one line)
			banner.Size = UDim2.fromOffset(math.min(520, UIKit.TextWidth(text, 28, Theme.Fonts.Display) + 24), 34)
			banner.TextScaled = true
		end
		banner.Text = text
		banner.TextColor3 = color or Color3.new(1, 1, 1)
		banner.TextTransparency = 0
		UIKit.PopIn(banner, 0.25)
		local stamp = os.clock()
		banner:SetAttribute("Stamp", stamp)
		task.delay(life or 2.6, function()
			if banner.Parent and banner:GetAttribute("Stamp") == stamp then
				UIKit.Tween(banner, 0.4, { TextTransparency = 1 })
			end
		end)
	end

	-- The highway ------------------------------------------------------------------------------------
	-- On phones it stands between the thumbstick zone (the left 41% of the screen: nobody walks in this
	-- game, but it's the thumb's) and the jump button, which also leaves the dancers in the middle of the
	-- screen in view; on a computer it's centred. The SYNC column hangs off its left side.
	local camera = workspace.CurrentCamera
	local holder = UIKit.new("Frame", {
		Name = "Highway",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(WIDTH, HIGHWAY_H + PAD_H + 8),
		BackgroundTransparency = 1,
		Parent = api.Gui,
	})
	UIKit.AutoScale(holder)
	local function placeHighway()
		if touch then
			holder.AnchorPoint = Vector2.new(0, 1)
			holder.Position = UDim2.new(0.41, 8 + SIDE * UIKit.CurrentScale(), 1, -10)
		end
	end
	placeHighway()
	api:Track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(placeHighway))

	-- The sync setting: the player's own part, and the total in use (the measured part is added in the frame).
	local syncLabel: TextLabel
	local function refreshSync()
		sync = math.clamp(manual + auto, 0, Logic.SYNC_MAX)
		if syncLabel then
			syncLabel.Text = `SYNC\n{math.floor(sync * 1000 + 0.5)} ms`
		end
	end
	local function setSync(value: number)
		manual = math.clamp(math.floor(value / SYNC_STEP + 0.5) * SYNC_STEP, -0.1, Logic.SYNC_MAX)
		savedSync = manual
		refreshSync()
	end
	local syncColumn = UIKit.new("Frame", {
		Name = "Sync",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromOffset(-SIDE, HIGHWAY_H + PAD_H + 8),
		Size = UDim2.fromOffset(SIDE - 8, 196),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	syncLabel = UIKit.Label({
		Name = "SyncLabel",
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 20,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(SIDE - 8, 48),
		Parent = syncColumn,
		Children = { UIKit.TextStroke(0.3) },
	})
	local function syncButton(text: string, top: number, delta: number)
		local button = UIKit.new("TextButton", {
			Name = "Sync" .. text,
			Position = UDim2.fromOffset(0, top),
			Size = UDim2.fromOffset(SIDE - 8, 72),
			BackgroundColor3 = Theme.Colors.PanelLight,
			BackgroundTransparency = 0.2,
			AutoButtonColor = true,
			Text = text,
			Font = Theme.Fonts.Display,
			TextSize = 40,
			TextColor3 = Color3.new(1, 1, 1),
			Parent = syncColumn,
			Children = { UIKit.Corner(14), UIKit.Stroke(Color3.new(1, 1, 1), 3, 0.4) },
		})
		api:Track(button.Activated:Connect(function()
			setSync(manual + delta)
		end))
	end
	syncButton("+", 50, SYNC_STEP)
	syncButton("−", 124, -SYNC_STEP)
	refreshSync()
	local lanes = UIKit.new("Frame", {
		Name = "Lanes",
		Size = UDim2.fromOffset(WIDTH, HIGHWAY_H + 6),
		BackgroundColor3 = Color3.fromRGB(14, 8, 36),
		BackgroundTransparency = 0.45,
		ClipsDescendants = true,
		Parent = holder,
		Children = { UIKit.Corner(14), UIKit.Stroke(Color3.new(1, 1, 1), 3, 0.5) },
	})
	local laneStrips = {}
	for lane = 1, Logic.LANES do
		laneStrips[lane] = UIKit.new("Frame", {
			Name = "Lane" .. lane,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(laneX(lane), 0),
			Size = UDim2.fromOffset(LANE_W, HIGHWAY_H + 6),
			BackgroundColor3 = LANE_COLORS[lane],
			BackgroundTransparency = 0.88,
			Parent = lanes,
		})
	end
	UIKit.new("Frame", {
		Name = "HitLine",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(0, HIGHWAY_H),
		Size = UDim2.fromOffset(WIDTH, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.25,
		ZIndex = 2,
		Parent = lanes,
	})
	local noteHolder = UIKit.new("Frame", {
		Name = "Notes",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = lanes,
	})
	local judgement = UIKit.Label({
		Name = "Judgement",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 34,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.fromOffset(WIDTH, 40),
		Parent = holder,
		Children = { UIKit.TextStroke(0.1) },
	})
	local combo = UIKit.Label({
		Name = "Combo",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 22,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -42),
		Size = UDim2.fromOffset(WIDTH, 28),
		Parent = holder,
		Children = { UIKit.TextStroke(0.2) },
	})

	local padFrames = {}
	local padScales = {}
	local tap -- below
	for lane = 1, Logic.LANES do
		local pad = UIKit.new("Frame", {
			Name = "Pad" .. lane,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(laneX(lane), HIGHWAY_H + 12),
			Size = UDim2.fromOffset(LANE_W, PAD_H),
			BackgroundColor3 = LANE_COLORS[lane],
			Active = true,
			Parent = holder,
			Children = { UIKit.Corner(16), UIKit.Stroke(Color3.new(1, 1, 1), 4, 0.1) },
		})
		UIKit.Label({
			Name = "Glyph",
			Text = GLYPH,
			Rotation = Logic.ARROWS[lane].Rotation,
			Font = Theme.Fonts.Display,
			TextSize = 52,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, if touch then 0.5 else 0.42),
			Size = UDim2.fromOffset(56, 56),
			ZIndex = 2,
			Parent = pad,
			Children = { UIKit.TextStroke(0.1) },
		})
		if not touch then
			UIKit.Label({
				Name = "Key",
				Text = KEY_NAMES[lane],
				Font = Theme.Fonts.Bold,
				TextSize = 20,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -2),
				Size = UDim2.new(1, 0, 0, 24),
				ZIndex = 2,
				Parent = pad,
				Children = { UIKit.TextStroke(0.3) },
			})
		end
		padFrames[lane] = pad
		padScales[lane] = UIKit.new("UIScale", { Parent = pad })
		api:Track(pad.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				tap(lane)
			end
		end))
	end
	-- The keyboard: the arrow keys and D F J K, bound ahead of the camera and the walking controls (the arrow
	-- keys would turn the camera) for as long as this player is dancing; anyone watching keeps their keys.
	local action = "LastDancerStep"
	local bound = pcall(function()
		ContextActionService:BindActionAtPriority(action, function(_name, state, input)
			if not dancing() then
				return Enum.ContextActionResult.Pass
			end
			if state == Enum.UserInputState.Begin then
				local lane = KEYCODES[input.KeyCode]
				if lane then
					tap(lane)
				end
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, table.unpack(KEYLIST))
	end)
	if bound then
		api:Track(function()
			ContextActionService:UnbindAction(action)
		end)
	else
		-- (no action service to bind to: listen for the keys the plain way)
		api:Track(UserInputService.InputBegan:Connect(function(input, processed)
			local lane = KEYCODES[input.KeyCode]
			if lane and not processed then
				tap(lane)
			end
		end))
	end

	-- Feedback -----------------------------------------------------------------------------------------
	local judgeStamp = 0
	local function judge(kind: string)
		judgeStamp += 1
		local stamp = judgeStamp
		judgement.Text = JUDGE_TEXT[kind]
		judgement.TextColor3 = JUDGE_COLORS[kind]
		judgement.TextTransparency = 0
		UIKit.PopIn(judgement, 0.18)
		combo.Text = if mine.Combo >= 4 then `{mine.Combo} COMBO` else ""
		task.delay(0.7, function()
			if judgement.Parent and judgeStamp == stamp then
				UIKit.Tween(judgement, 0.25, { TextTransparency = 1 })
			end
		end)
	end
	local function flashPad(lane: number, kind: string)
		local pad = padFrames[lane]
		pad.BackgroundColor3 = JUDGE_COLORS[kind]:Lerp(LANE_COLORS[lane], 0.3)
		padScales[lane].Scale = 0.9
		UIKit.Tween(padScales[lane], 0.15, { Scale = 1 })
		UIKit.Tween(pad, 0.2, { BackgroundColor3 = LANE_COLORS[lane] })
	end
	local function myPanel(lane: number): BasePart?
		local tile = arena:FindFirstChild("Tile_" .. me)
		return tile and tile:FindFirstChild("Panel" .. lane) :: BasePart?
	end

	local function relNow(): number
		return api:Now() - go
	end

	function tap(lane: number)
		if not dancing() or GameState.Get("Phase") ~= "InRound" then
			return
		end
		local now = api:Now()
		local rel = now - go - sync
		api:Action("Tap", lane, now - sync)
		if Logic.InWarmup(Chart, rel) then
			flashPad(lane, "Ok")
			stepOn(me, lane, STEP_CODES.Ok)
			return
		end
		local outcome = Logic.Tap(Chart, mine, lane, rel)
		stepOn(me, lane, STEP_CODES[outcome.Kind]) -- the foot went there, hit or not
		if outcome.Index then
			results[outcome.Index] = outcome.Kind
			flashPad(lane, outcome.Kind)
			judge(outcome.Kind)
			playSound(api, "Click", 1.3 + lane * 0.1, 0.25)
			if effects and outcome.Kind == "Perfect" then
				local panel = myPanel(lane)
				if panel then
					api:Effect("Sparkles", panel.Position + Vector3.new(0, 2, 0), { LANE_COLORS[lane] })
				end
			end
		elseif outcome.Kind == "Late" then
			flashPad(lane, "Ok") -- (a tap for a note that already says MISS: nothing more to say)
		else
			flashPad(lane, "Miss")
			combo.Text = ""
		end
	end

	-- The notes: a few frames, reused.
	local frames: { [number]: Frame } = {}
	local spare: { Frame } = {}
	local function takeFrame(index: number): Frame
		local frame = table.remove(spare)
		if not frame then
			frame = UIKit.new("Frame", {
				Name = "Note",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(LANE_W - 8, NOTE_H),
				Parent = noteHolder,
				Children = { UIKit.Corner(12), UIKit.Stroke(Color3.new(1, 1, 1), 3, 0.15) },
			})
			UIKit.Label({
				Name = "Glyph",
				Text = GLYPH,
				Font = Theme.Fonts.Display,
				TextSize = 30,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(36, 36),
				ZIndex = 2,
				Parent = frame,
				Children = { UIKit.TextStroke(0.2) },
			})
		end
		local note = notes[index]
		frame.BackgroundColor3 = LANE_COLORS[note.Lane]
		frame.BackgroundTransparency = 0
		frame.Visible = true
		(frame:FindFirstChild("Glyph") :: TextLabel).Rotation = Logic.ARROWS[note.Lane].Rotation
		frame.Size = UDim2.fromOffset(LANE_W - 8, NOTE_H)
		frames[index] = frame
		return frame
	end
	local function giveBack(index: number)
		local frame = frames[index]
		if frame then
			frame.Visible = false
			frames[index] = nil
			table.insert(spare, frame)
		end
	end

	-- The beat (tick when the song isn't playing).
	local lastBeat = -1
	local songOk = false
	local songCheck = 0
	local function songPlaying(): boolean
		local status = AudioController.Status()
		return status.Track == "Music_LastDancer" and status.Playing == true and status.Loaded == true
	end

	-- Who is about to fall, and the mats' lights.
	local doomed: { [number]: boolean } = {}
	local tiles = {}
	for _, entry in floor.Tiles do
		local tile = arena:FindFirstChild("Tile_" .. entry.Id)
		if tile then
			local panels = {}
			for lane = 1, Logic.LANES do
				panels[lane] = tile:FindFirstChild("Panel" .. lane) :: BasePart?
			end
			table.insert(tiles, { Id = entry.Id, Tile = tile, Panels = panels })
		end
	end
	-- Everyone's steps, from the server (this player's own are made at the tap).
	api:OnEvent("Steps", function(batch)
		if type(batch) ~= "table" then
			return
		end
		for _, entry in batch do
			local id, lane, code = entry[1], entry[2], entry[3]
			if id ~= me and type(id) == "number" and type(lane) == "number" and Logic.ARROWS[lane] then
				stepOn(id, lane, if type(code) == "number" then code else STEP_CODES.Ok)
			end
		end
	end)
	api:OnEvent("CutWarn", function(ids)
		for _, id in ids do
			doomed[id] = true
		end
		showBanner(
			`{namesOf(ids)} {if #ids == 1 and ids[1] ~= me then "is" else "are"} about to FALL!`,
			JUDGE_COLORS.Miss
		)
	end)
	api:OnEvent("Cut", function(ids, _phase, spared)
		for _, id in ids do
			doomed[id] = nil
		end
		if type(spared) == "table" then
			for _, id in spared do
				doomed[id] = nil -- (someone left: they are not falling after all)
			end
		end
		if #ids > 0 then
			showBanner(`{namesOf(ids)} fell through the floor!`, Color3.new(1, 1, 1))
			if effects then
				for _, id in ids do
					for _, t in tiles do
						if t.Id == id then
							api:Effect("Poof", t.Tile:GetPivot().Position, nil)
						end
					end
				end
			end
		end
	end)
	local refreshStandings: () -> () = function() end
	api:OnShared("Board", function()
		readBoard()
		refreshStandings()
	end)
	api:OnShared("Cut", function(value)
		cut = api:SharedJSON("Cut") or {}
		if value == nil then
			cut = {}
		end
	end)

	-- Spectators see the standings.
	local standings = UIKit.new("Frame", {
		Name = "Standings",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(12, 150),
		Size = UDim2.fromOffset(230, 40 + 12 * 26),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = api.Gui,
		Children = { UIKit.Corner(14), UIKit.Stroke(Color3.new(1, 1, 1), 2, 0.5) },
	})
	UIKit.AutoScale(standings)
	UIKit.Label({
		Name = "Head",
		Text = "STANDINGS",
		Font = Theme.Fonts.Display,
		TextSize = 22,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = standings,
		Children = { UIKit.TextStroke(0.2) },
	})
	local rows = {}
	for index = 1, 12 do
		rows[index] = UIKit.Label({
			Name = "Row" .. index,
			Text = "",
			Font = Theme.Fonts.Bold,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(14, 38 + (index - 1) * 26),
			Size = UDim2.new(1, -28, 0, 24),
			Parent = standings,
			Children = { UIKit.TextStroke(0.3) },
		})
	end

	local function updateStandings()
		local sorted = table.clone(board)
		table.sort(sorted, function(a, b)
			if a[4] ~= b[4] then
				return a[4] > b[4]
			end
			if a[2] ~= b[2] then
				return a[2] > b[2]
			end
			return a[3] > b[3]
		end)
		for index, label in rows do
			local row = sorted[index]
			if row then
				local name = if row[1] == me then "YOU" else nameOf(row[1])
				label.Text = if row[4] == 1 then `{index}. {name}  {row[2]}%` else `{index}. {name}  out`
				label.TextTransparency = if row[4] == 1 then 0 else 0.5
			else
				label.Text = ""
			end
		end
	end
	local function applyMode()
		local playing = dancing()
		if not playing then
			updateStandings()
		end
		holder.Visible = playing
		meter.Visible = playing
		-- (not on phones: there it would cover the thumbstick, and the HUD's own standings are a tap away)
		standings.Visible = not playing and not touch
		combo.Visible = playing
	end
	applyMode()
	api:OnCanAct(applyMode)
	refreshStandings = function()
		applyMode() -- (who is still dancing may have changed: it also updates the standings)
	end

	if touch then
		showBanner("Step on each arrow as it lands!", nil, 7)
	else
		api:Hint("Step on each arrow as it lands!", y + 96)
	end
	task.delay(9, hideHint)

	-- Every frame ---------------------------------------------------------------------------------------
	local scanStart = 1
	local displayed = 60
	local songClock = 0
	local sentSync = -1
	local danceOn = effects
	local danceCheck = 1
	local rigs: { [Model]: { Rig: Rig, UserId: number, Phase: number } } = {}
	api:Track(function()
		for _, entry in rigs do
			restore(entry.Rig)
		end
		table.clear(rigs)
	end)
	-- The dance shows when it's written just before physics, after the Animator (client/Pose).
	api:Track(Pose.Step(function()
		for _, entry in rigs do
			apply(entry.Rig)
		end
	end))
	api:RenderStep(function(dt)
		local rel = relNow()
		local chartRel = rel - sync -- the chart's time as this player hears it
		local phase = GameState.Get("Phase")

		-- how late the song is playing, and the sync in use told to the server (four times a second)
		songClock += dt
		if songClock > 0.25 then
			songClock = 0
			local song = Sounds.ModeSongs.LastDancer
			if song and rel > 0.5 and rel < Logic.DURATION and songPlaying() then
				local diff = AudioController.Status().Time - SongTiming.Position(song, rel)
				if math.abs(diff) < 0.6 then
					-- (behind where it should be: the picture waits for it; ahead can't be helped)
					auto += (math.clamp(-diff, 0, Logic.SYNC_MAX) - auto) * 0.35
				end
			end
			refreshSync()
			if math.abs(sync - sentSync) >= 0.008 then
				sentSync = sync
				api:Action("Sync", sync)
			end
		end

		-- notes
		if holder.Visible then
			local missed = Logic.Expire(Chart, mine, chartRel - 0.02)
			for _, index in missed do
				results[index] = "Miss"
				judge("Miss")
				combo.Text = ""
			end
			while scanStart <= #notes and notes[scanStart].T + sync < rel - 0.45 do
				giveBack(scanStart)
				scanStart += 1
			end
			local index = scanStart
			local speed = HIGHWAY_H / TRAVEL
			while index <= #notes and notes[index].T + sync < rel + TRAVEL do
				local note = notes[index]
				local frame = frames[index] or takeFrame(index)
				local result = results[index]
				local height = HIGHWAY_H - (note.T + sync - rel) * speed
				frame.Position = UDim2.fromOffset(laneX(note.Lane), height)
				if result == "Miss" then
					frame.BackgroundTransparency = math.min(0.85, 0.4 + (rel - note.T - sync) * 0.6)
				elseif result then
					frame.Visible = false -- hit: gone (the pad flashed)
				else
					frame.BackgroundTransparency = math.clamp((60 - height) / 60, 0, 0.9)
				end
				index += 1
			end
		end

		-- the groove meter: the server's number, eased
		local row = myRow()
		local alive = row ~= nil and row[4] == 1
		if row then
			displayed += (row[2] - displayed) * math.min(1, dt * 8)
			fill.Size = UDim2.fromScale(math.clamp(displayed / 100, 0.02, 1), 1)
			percent.Text = percentText(displayed)
			local good = displayed >= 70
			fill.BackgroundColor3 = if good
				then Theme.Colors.Green
				elseif displayed >= 40 then Theme.Colors.Yellow
				else Theme.Colors.Red
			local grooves = aliveGrooves()
			if alive then
				place.Text = `#{Logic.Place(grooves, row[2])}/{#grooves}`
			else
				place.Text = "OUT"
			end
		end
		-- the line to stay clear of: the cut line (the lowest few fall), or in the final duel the other
		-- dancer's groove
		local cutAt = cut.At
		local cutLineValue = cutLine()
		local inDanger = false
		if alive and cut.Final then
			local lead = nil
			for _, other in board do
				if other[1] ~= me and other[4] == 1 and (lead == nil or other[2] > lead) then
					lead = other[2]
				end
			end
			cutLineValue = lead
			inDanger = lead ~= nil and row[2] < lead
		elseif alive and cutLineValue and (cut.Count or 0) > 0 then
			inDanger = row[2] <= cutLineValue
		end
		line.Visible = cutLineValue ~= nil and alive
		if cutLineValue then
			line.Position = UDim2.fromScale(math.clamp(cutLineValue / 100, 0, 1), 0.5)
		end
		local alarm = inDanger and phase == "InRound"
		local blink = math.floor(os.clock() * 4) % 2 == 0
		meterStroke.Color = if alarm and blink then Theme.Colors.Red else Color3.new(1, 1, 1)
		ticker.TextColor3 = if alarm and blink then Theme.Colors.Red else Color3.new(1, 1, 1)
		if phase == "Preparing" then
			ticker.Text = "GET READY!"
		elseif phase == "InRound" and cut.Final then
			ticker.Text = if inDanger then "FINAL DUEL! YOU'RE BEHIND!" else "FINAL DUEL! HIGHEST GROOVE WINS"
		elseif phase == "InRound" and cutAt then
			local left = math.max(0, cutAt - api:Now())
			local text = `CUT IN {math.ceil(left)}s • {cut.Count or 0} FALL`
			ticker.Text = if alarm then `DANGER! {text}` else `NEXT {text}`
		else
			ticker.Text = ""
		end

		-- the mats' arrows: each lights up on the beat, flares when a dancer steps on it (white for a perfect
		-- step, its own colour for a great one, half for an ok, a dull red for a wrong one), and flashes red
		-- on a mat that is about to fall
		local beat = chartRel / Logic.BEAT
		local pulse = math.max(0, 1 - (beat % 1) * 2.5) ^ 2
		local flash = math.floor(os.clock() * 8) % 2 == 0
		local clock = os.clock()
		for _, t in tiles do
			if not t.Tile.Parent then
				continue
			end
			local list = flashes[t.Id]
			for lane, panel in t.Panels do
				local lit = LANE_COLORS[lane]
				local target = lit:Lerp(Color3.new(0, 0, 0), 0.45):Lerp(lit, 0.6 * pulse)
				local last = list and list[lane]
				local age = if last then clock - last.At else 1
				if last and age < 0.3 then
					local k = 1 - age / 0.3
					if last.Code == STEP_CODES.Perfect then
						target = target:Lerp(Color3.new(1, 1, 1), k)
					elseif last.Code == STEP_CODES.Great then
						target = target:Lerp(lit, k)
					elseif last.Code == STEP_CODES.Ok then
						target = target:Lerp(lit, k * 0.6)
					else
						target = target:Lerp(Color3.fromRGB(190, 45, 65), k * 0.8)
					end
				end
				if doomed[t.Id] then
					target = if flash then Color3.fromRGB(255, 40, 50) else Color3.fromRGB(90, 0, 10)
				end
				panel.Color = target
			end
		end

		-- the dancers, in time with the beat (this device only; off with reduced effects)
		if danceOn then
			danceCheck += dt
			if danceCheck > 0.5 then
				danceCheck = 0
				for _, participant in api:Participants() do
					local character = participant:Character()
					if
						character
						and character.Parent
						and not rigs[character]
						and participant:GetAttribute("PP_Alive") ~= false
					then
						local rig = rigOf(character)
						if rig then
							rigs[character] =
								{ Rig = rig, UserId = participant.UserId, Phase = (participant.UserId % 7) / 14 }
						end
					end
				end
			end
			local grooves = {}
			for _, standing in board do
				grooves[standing[1]] = if standing[4] == 1 then standing[2] else nil
			end
			for character, entry in rigs do
				local groove = grooves[entry.UserId]
				if not character.Parent or groove == nil then
					restore(entry.Rig)
					rigs[character] = nil
				elseif phase ~= "InRound" and phase ~= "Preparing" then
					restore(entry.Rig) -- (the results: everyone stands at ease, not frozen mid-step)
				elseif phase == "InRound" or phase == "Preparing" then
					local energy = 0.3 + 0.7 * math.clamp(groove / 100, 0, 1)
					if phase == "Preparing" then
						energy = 0.6
					end
					-- (the step they are in the middle of: up to 0.06 s in, down to nothing by 0.36 s)
					local step: Step? = nil
					local last = steps[entry.UserId]
					local age = if last then clock - last.At else STEP_LIFE
					if last and age < STEP_LIFE then
						local arrow = Logic.ARROWS[last.Lane]
						local env = if age < 0.06 then age / 0.06 else math.max(0, 1 - (age - 0.06) / 0.3)
						step = { Dx = arrow.Dx, Dz = arrow.Dz, Env = env, Foot = last.Foot }
					end
					pcall(dance, entry.Rig, beat, energy, entry.Phase, doomed[entry.UserId] == true, step)
				end
			end
		end

		-- the tick (only when the song isn't playing)
		if phase == "InRound" or (phase == "Preparing" and rel > -2.2) then
			local now = os.clock()
			if now - songCheck > 0.5 then
				songCheck = now
				songOk = songPlaying()
			end
			local number = math.floor(chartRel / Logic.BEAT)
			if number > lastBeat then
				lastBeat = number
				if not songOk and number >= -4 then
					playSound(api, "Click", if number % 4 == 0 then 1.25 else 0.95, 0.35)
				end
			end
		end
	end)
end

return LastDancer

-- Skee-Ball in the lobby arcade (owner: "Can we also add skiball to the lobby?"): everything a player
-- sees and does at the four machines World/Arcade builds. The server (SkeeBallService) decides
-- every score; this draws it.
--
-- Everyone: each machine's score screen, the TODAY'S BEST board, the balls waiting in each chute,
-- every roll (the same path the server scored, from Shared/Logic/SkeeBall), the ring that lights up
-- when a ball drops in, a "+50" over the machine, and the marquee bulbs chasing.
--
-- Playing (after the "Play SKEE-BALL" prompt): the camera frames your lane and you roll 9 balls.
--   Phones and PC: drag back anywhere on the lane and let go (pull further for more power, to the
--   side to aim; the dotted line shows where it'll go). Or tap ROLL (Space / A on a controller):
--   tap once to stop the swinging aim, again to stop the power.
--   Each ball pops its score; after the 9th, a fanfare and PLAY AGAIN / DONE. DONE or walking
--   away (WASD) frees the machine. The ball rolls at once on your device and the server checks it,
--   so it feels instant.
-- Layout: the lane in the middle of the screen; the score, ROLL and the power meter low on the left,
-- beside the lane. Phones put the MOVE stick and jump button away while you play (like Arrow
-- Ambush's archers), so a stray thumb can't walk you off mid-game and the whole screen is for
-- rolling; DONE sits beside the menu column and brings them back.
--
-- Review pass (same request): you can vote while you roll. The vote cards keep their places (a row
-- under the top bar on phones, along the bottom on PC), so on phones DONE sits under that row, and
-- on PC the controls sit on the left above it, DONE in the bottom-right corner past its end, and the
-- camera eases to a framing that keeps your lane and rings clear of the cards (POSES). While the
-- vote is on, the tip over the score says a round is coming and the sit-out switch keeps you
-- rolling. When a round takes you, the game ends at once on this device (before the round's own
-- camera and controls start), and while you play the camera is held on your lane every frame, so
-- nothing else (a round's clean-up after you were knocked out) can pull it away; the move controls
-- are put away again after each phase change for the same reason. The next machine's "Play
-- SKEE-BALL" prompt (within reach of your spot) stays off your screen while you play.
--
-- Second review pass (same request): a ball you roll counts once the server says so (its echo or
-- the machine's ball count); if the server refused it, its "Sync" puts the ball back ("ROLL
-- AGAIN") so this device never runs ahead of the real game, and a ball's points only pop once the
-- server has taken it. Your ball waits in its hole for that word however quickly it drops in (a
-- slow word, or none, is a safety net: the machine's ball count decides), a drop's points pop even
-- if a hitch skipped its frames, the server's roll wins over this device's own if they differ,
-- and a machine that goes idle takes its balls off the lane (a game that ended scores nothing). A
-- drag from the waiting ball reaches full power at the bottom edge of the screen, in every layout
-- (SkeeBallView: the vote's camera poses keep room below the ball and keep the camera clear of the
-- lobby's scenery). Only the drag's own finger ends it. On PC the controls column rises above the
-- vote cards only while they're up, and sits low the rest of the time, under the round's
-- standings. The machines are solid only where they're drawn now (owner: "invisible stuff you can
-- jump on and hang on in several games"; World/Arcade), so people can climb onto them and hop into
-- a lane: anyone on your machine or between it and your camera fades on your screen while you
-- play, so nobody stands in front of your lane and rings.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local SkeeBall = require(Shared.Logic.SkeeBall)
local SkeeBallView = require(Shared.Logic.SkeeBallView)
local Sounds = require(Shared.Sounds)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SkeeBallController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote: RemoteEvent

-- The play camera, in the machine's frame (Shared/Logic/SkeeBallView has the poses and why): behind
-- and above the player, looking down the lane, the ball three quarters of the way down the screen
-- and the 100 cups a quarter. While the vote cards show (they keep their places), the view turns
-- and widens so the ring board sits under the phones' row of cards, and the ball and the lane stay
-- above the PC's cards along the bottom.
type Pose = { Eye: Vector3, Look: Vector3, Fov: number }
local POSES: { [string]: Pose } = {}
for name, pose in SkeeBallView.Poses do
	POSES[name] = {
		Eye = Vector3.new(pose.Eye[1], pose.Eye[2], pose.Eye[3]),
		Look = Vector3.new(pose.Look[1], pose.Look[2], pose.Look[3]),
		Fov = pose.Fov,
	}
end
local CAMERA_BLEND = 0.7 -- seconds the camera takes to swing in behind your lane, or to a new pose
local SELF_FADE = 0.8 -- your own character fades while you play (it would hide the ball)
local AIM_SWING = 1.5 -- seconds for the ROLL meter's aim to swing across and back
local POWER_SWING = 1.25 -- and for its power to fill and empty
-- A ball this device rolled counts once the server says so: its echo, the machine's ball count, or
-- (for a refused one) its "Sync". With no word by this long after the roll, the machine's ball
-- count decides (a safety net: the server answers every roll).
local CONFIRM_TIMEOUT = 4
local ANIMATE_RANGE = 220
-- The controls column low on the left (UI units): the score card over the ROLL button, the power
-- meter beside them, and the tip on top until the first roll.
local COLUMN_WIDTH = 270
local SCORE_HEIGHT = 86
local ROLL_HEIGHT = 100
local METER_WIDTH = 40
local HINT_HEIGHT = 84
-- PC: a lower ROLL button and tip (Space rolls too), so the column fits between the profile pill
-- and the room the vote cards take along the bottom (VoteController: 214 tall cards, 34 over them
-- for the YOUR VOTE tag, 18 from the bottom), where it rises to while the vote is up. The rest of
-- the time it sits PC_BOTTOM from the bottom, under the round's standings.
local PC_ROLL_HEIGHT = 72
local PC_HINT_HEIGHT = 66
local PC_VOTE_ROOM = 18 + 34 + 214 + 10
local PC_BOTTOM = 24
-- Phones: DONE sits under the top bar's row (the vote timer and the sit-out switch). The vote cards
-- are at the bottom middle now (VoteController: 110 tall, drawn 1.25 times, 10 off the bottom, the
-- sit-out note over them), and the controls column rises above them while they're up
-- (placeColumn), so the leftmost card never sits on ROLL.
local TOUCH_VOTE_ROOM = 96
local TOUCH_VOTE_ROW = 110 * 1.25 + 10 + 12
local HINT_TEXT = {
	Touch = "DRAG DOWN & LET GO\nor tap ROLL",
	Pc = "DRAG DOWN & LET GO\nor press SPACE",
	Soon = "ROUND SOON! SIT OUT\nto keep rolling",
}

local RING_COLORS = {
	["10"] = Color3.fromRGB(156, 108, 255),
	["20"] = Color3.fromRGB(64, 196, 255),
	["30"] = Color3.fromRGB(110, 226, 140),
	["40"] = Color3.fromRGB(255, 204, 64),
	["50"] = Color3.fromRGB(255, 84, 150),
	["100L"] = Color3.fromRGB(255, 170, 40),
	["100R"] = Color3.fromRGB(255, 170, 40),
}
local POCKET_PIECE = {
	["10"] = "Band10",
	["20"] = "Band20",
	["30"] = "Band30",
	["40"] = "Band40",
	["50"] = "Band50",
	["100L"] = "Cup100L",
	["100R"] = "Cup100R",
}
local MISS_WORDS = { Gutter = "TOO SOFT!", Over = "TOO HARD!" }
local PLACES = { "1ST", "2ND", "3RD", "4TH", "5TH" }

type Roll = {
	Path: SkeeBall.Path,
	Start: number,
	Model: Model,
	Spin: CFrame,
	Last: Vector3?,
	Hopped: boolean,
	Landed: boolean,
	Dropped: boolean,
	Mine: boolean,
	Number: number,
	Confirmed: boolean, -- the server took it (always, for someone else's)
	DropWaiting: boolean, -- your ball dropped in before the server's word came: its points pop then
}

type Machine = {
	Model: Model,
	Index: number,
	Frame: CFrame,
	Color: Color3,
	Screen: BasePart?,
	Prompt: ProximityPrompt?,
	Draw: (() -> ())?,
	Bulbs: { { BasePart } },
	BulbColors: { [BasePart]: Color3 },
	Glow: { BasePart },
	Pieces: { [string]: BasePart },
	PieceLooks: { [BasePart]: { Color3 | Enum.Material } },
	Chute: { Model },
	Ready: Model?,
	Rolls: { Roll },
	Flash: number, -- os.clock() until which the bulbs party (a 100, a new best)
}

local machines: { [number]: Machine } = {}
local ballTemplate: Model? = nil
local ballCenter = Vector3.new(0, 0.389, 0) -- from a ball model's pivot to its center
local folder: Folder
local boardPart: BasePart? = nil

-- The local game.
local play = {
	Active = false,
	Index = 0,
	Best = 0,
	Rolled = 0, -- balls this device has rolled this game
	NextRollAt = 0,
	Over = false,
	Meter = "Idle", -- "Idle" | "Aim" | "Power"
	MeterStart = 0,
	MeterAim = 0,
	Dragging = nil :: InputObject?,
	DragStart = Vector2.zero,
	DragAt = Vector2.zero,
	Aim = 0,
	Power = 0,
	SavedFov = 70,
	Pose = nil :: Pose?, -- the camera's pose (POSES), and where and when it set off toward it
	CameraFrom = CFrame.identity,
	FovFrom = 70,
	CameraStart = 0,
	MovingSince = 0,
	Controls = nil :: any, -- the PlayerModule's move controls, while they're put away (phones)
	Connections = {} :: { RBXScriptConnection },
}

local ui = {} :: { [string]: any }
local refreshControls: () -> () -- the score, balls and ROLL button under your lane (below)
local refreshHint: () -> () -- the tip over them (below)
local voteShowing = false -- the vote cards are up (the Voting phase): the camera makes room

-- Sound ---------------------------------------------------------------------------------------------

-- Plays one of the game's sound effects: pitched, and from a part in the world if `at` is given
-- (other players' machines), else for this player only.
local function sfx(name: string, pitch: number, volume: number, at: BasePart?)
	local sound = Instance.new("Sound")
	local sprite = Sounds.Sprite
	local length = 2
	if sprite and sprite.Regions[name] then
		local region = sprite.Regions[name]
		sound.SoundId = sprite.Id
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(region.Start, region.Start + region.Length)
		length = region.Length
	else
		local id = (Sounds.Sfx :: any)[name]
		if type(id) ~= "string" then
			return
		end
		sound.SoundId = id
	end
	sound.PlaybackSpeed = pitch
	sound.Volume = volume
	if at then
		sound.RollOffMinDistance = 10
		sound.RollOffMaxDistance = 70
		sound.Parent = at
	else
		sound.Parent = SoundService
	end
	sound:Play()
	Debris:AddItem(sound, length / pitch + 0.5)
end

-- Balls ---------------------------------------------------------------------------------------------

local function newBall(color: Color3): Model?
	local template = ballTemplate
	if not template then
		return nil
	end
	local ball = template:Clone()
	for _, part in ball:GetDescendants() do
		if part:IsA("BasePart") and part.Name == "Ball" then
			part.Color = color
		end
	end
	ball.Parent = folder
	return ball
end

-- Puts a ball's center at `position` (machine frame), turned by `spin`.
local function placeBall(machine: Machine, ball: Model, position: Vector3, spin: CFrame?)
	local world = machine.Frame * CFrame.new(position)
	ball:PivotTo(CFrame.new(world.Position) * (spin or machine.Frame.Rotation) * CFrame.new(-ballCenter))
end

local function lanePoint(u: number, y: number, s: number): Vector3
	local x, my, z = SkeeBall.ToMachine(u, y, s)
	return Vector3.new(x, my, z)
end

-- The balls waiting in the chute (and the next one at the release point, while someone plays).
local function showWaiting(machine: Machine)
	local model = machine.Model
	local state = model:GetAttribute("SkeeState") or "Idle"
	local rolled = model:GetAttribute("SkeeBalls") or 0
	if play.Active and play.Index == machine.Index then
		rolled = math.max(rolled, play.Rolled)
	end
	local left = if state == "Idle" then SkeeBall.BALLS elseif state == "Over" then 0 else SkeeBall.BALLS - rolled
	local ready = state == "Playing" and left > 0
	local inChute = if ready then left - 1 else left
	for index, ball in machine.Chute do
		local shown = index <= inChute
		if shown then
			local z = SkeeBall.CHUTE_Z + (index - 1) * SkeeBall.CHUTE_STEP
			local y = SkeeBall.CHUTE_Y + (z - SkeeBall.CHUTE_Z) * SkeeBall.CHUTE_RISE
			placeBall(machine, ball, Vector3.new(SkeeBall.CHUTE_X, y, z))
		else
			ball:PivotTo(CFrame.new(0, -500, 0))
		end
	end
	local readyBall = machine.Ready
	if readyBall then
		if ready then
			placeBall(machine, readyBall, lanePoint(0, SkeeBall.LANE_Y + SkeeBall.BALL_R, 0))
		else
			readyBall:PivotTo(CFrame.new(0, -500, 0))
		end
	end
end

-- Pops "+50" over a machine's rings, for everyone near.
local function popOver(machine: Machine, text: string, color: Color3, big: boolean)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = machine.Frame * CFrame.new(0, SkeeBall.TOP_Y + 1, 4.2)
	anchor.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(if big then 220 else 150, if big then 90 else 64)
	gui.StudsOffset = Vector3.zero
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = UIKit.Label({
		Text = text,
		Font = Theme.Fonts.Display,
		TextScaled = true,
		TextColor3 = color,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
		Children = { UIKit.TextStroke(0) },
	})
	UIKit.PopIn(label, 0.3)
	UIKit.Tween(gui, 1.4, { StudsOffset = Vector3.new(0, 3, 0) }, Enum.EasingStyle.Quad)
	task.delay(0.8, function()
		UIKit.Tween(label, 0.6, { TextTransparency = 1 })
	end)
	Debris:AddItem(anchor, 1.6)
end

-- Lights up the ring (or cup) a ball dropped into.
local function flashPocket(machine: Machine, pocket: string)
	local part = machine.Pieces[POCKET_PIECE[pocket] or ""]
	if not part then
		return
	end
	local look = machine.PieceLooks[part]
	if not look then
		look = { part.Color, part.Material }
		machine.PieceLooks[part] = look
	end
	local base = look[1] :: Color3
	part.Material = Enum.Material.Neon
	part.Color = base:Lerp(Color3.new(1, 1, 1), 0.35)
	local count = 0
	local function blink()
		count += 1
		if not part.Parent then
			return
		end
		if count >= 6 then
			part.Color = base
			part.Material = look[2] :: Enum.Material
			return
		end
		part.Color = if count % 2 == 0 then base:Lerp(Color3.new(1, 1, 1), 0.35) else base
		task.delay(0.12, blink)
	end
	task.delay(0.12, blink)
end

-- Screen pops ---------------------------------------------------------------------------------------

local function popScreen(text: string, color: Color3, big: boolean)
	local label = ui.Pop
	if not label then
		return
	end
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	label.TextSize = if big then 92 else 70
	label.Visible = true
	UIKit.PopIn(label, 0.35)
	local stamp = os.clock()
	ui.PopStamp = stamp
	task.delay(0.9, function()
		if ui.PopStamp == stamp then
			UIKit.Tween(label, 0.4, { TextTransparency = 1 }).Completed:Once(function()
				if ui.PopStamp == stamp then
					label.Visible = false
				end
			end)
		end
	end)
end

-- Rolling -------------------------------------------------------------------------------------------

local function dropped(machine: Machine, roll: Roll)
	local path = roll.Path
	local pocket = path.Pocket
	local mine = roll.Mine
	local screen = machine.Screen
	-- Your own ball pops big on your screen, over the machine; everyone else's over their machine.
	if path.Points > 0 then
		local color = RING_COLORS[pocket] or Theme.Colors.Yellow
		flashPocket(machine, pocket)
		if path.Points >= 100 then
			machine.Flash = os.clock() + 2.5
		end
		if mine then
			popScreen(if path.Points >= 100 then "+100!" else `+{path.Points}`, color, path.Points >= 50)
			sfx("Pickup", 0.8 + path.Points / 125, 0.7)
			if path.Points >= 100 then
				sfx("Purchase", 1, 0.6)
			end
		else
			popOver(machine, `+{path.Points}`, color, path.Points >= 100)
			if screen then
				sfx("Pickup", 0.8 + path.Points / 125, 0.5, screen)
			end
		end
	elseif mine then
		popScreen(MISS_WORDS[pocket] or "MISS", Color3.fromRGB(230, 230, 245), false)
		sfx("Countdown", 0.55, 0.6)
	else
		popOver(machine, MISS_WORDS[pocket] or "MISS", Color3.fromRGB(220, 220, 235), false)
	end
end

local function startRoll(machine: Machine, path: SkeeBall.Path, number: number, mine: boolean): Roll?
	for _, existing in machine.Rolls do
		if existing.Number == number then
			return existing -- already rolling (this device rolled it before the server's echo)
		end
	end
	local model = newBall(machine.Color)
	if not model then
		return nil
	end
	local roll: Roll = {
		Path = path,
		Start = os.clock(),
		Model = model,
		Spin = machine.Frame.Rotation,
		Last = nil,
		Hopped = false,
		Landed = false,
		Dropped = false,
		Mine = mine,
		Number = number,
		Confirmed = not mine,
		DropWaiting = false,
	}
	table.insert(machine.Rolls, roll)
	if mine then
		sfx("VoteClick", 0.8, 0.6)
	elseif machine.Screen then
		sfx("VoteClick", 0.8, 0.4, machine.Screen)
	end
	return roll
end

-- The server took this device's ball: if it already dropped in on screen, its points pop now.
local function confirm(machine: Machine, roll: Roll)
	if roll.Confirmed then
		return
	end
	roll.Confirmed = true
	if roll.DropWaiting then
		roll.DropWaiting = false
		dropped(machine, roll)
	end
end

-- The server counts `counted` balls of this device's game: the ones it rolled up to there count,
-- any after that were refused and go back (gone from the lane, to be rolled again). If the server
-- did take one of those after all, its echo brings it back ("Rolled", below).
local function settleRolls(machine: Machine, counted: number)
	for index = #machine.Rolls, 1, -1 do
		local roll = machine.Rolls[index]
		if roll.Mine and not roll.Confirmed then
			if roll.Number <= counted then
				confirm(machine, roll)
			else
				roll.Model:Destroy()
				table.remove(machine.Rolls, index)
			end
		end
	end
	if play.Active and play.Index == machine.Index and play.Rolled > counted then
		play.Rolled = counted
		play.NextRollAt = 0
		showWaiting(machine)
		if machine.Draw then
			machine.Draw()
		end
		refreshHint()
		refreshControls()
		popScreen("ROLL AGAIN", Color3.fromRGB(230, 230, 245), false)
	end
end

-- Takes every ball off a machine's lane (a game that ended: they don't count).
local function clearRolls(machine: Machine)
	for _, roll in machine.Rolls do
		roll.Model:Destroy()
	end
	table.clear(machine.Rolls)
end

local function stepRolls(machine: Machine, now: number)
	-- Your own balls the server hasn't answered in a long while (it answers every roll, so this is
	-- a safety net): the machine's ball count decides, for all of them at once.
	for _, roll in machine.Rolls do
		if roll.Mine and not roll.Confirmed and now - roll.Start > CONFIRM_TIMEOUT then
			local counted = machine.Model:GetAttribute("SkeeBalls")
			settleRolls(machine, if type(counted) == "number" then counted else 0)
			break
		end
	end
	for index = #machine.Rolls, 1, -1 do
		local roll = machine.Rolls[index]
		local path = roll.Path
		local t = now - roll.Start
		-- The drop (and its points) even when a hitch skipped its frames.
		if t >= path.Phases[#path.Phases].T0 and not roll.Dropped then
			roll.Dropped = true
			if roll.Confirmed then
				dropped(machine, roll)
			else
				roll.DropWaiting = true -- no points pop for a ball the server hasn't taken yet
			end
		end
		if t >= path.Done + 0.05 then
			-- Sunk in its hole: gone, unless it's yours and still waiting for the server's word.
			if not roll.Mine or roll.Confirmed then
				roll.Model:Destroy()
				table.remove(machine.Rolls, index)
			end
			continue
		end
		local u, y, s = SkeeBall.Sample(path, t)
		local position = lanePoint(u, y, s)
		if roll.Last then
			local delta = machine.Frame:VectorToWorldSpace(position - roll.Last)
			local distance = delta.Magnitude
			if distance > 1e-4 then
				local axis = Vector3.yAxis:Cross(delta)
				if axis.Magnitude > 1e-5 then
					roll.Spin = CFrame.fromAxisAngle(axis.Unit, distance / SkeeBall.BALL_R) * roll.Spin
				end
			end
		end
		roll.Last = position
		placeBall(machine, roll.Model, position, roll.Spin)
		if not roll.Hopped and t >= path.Phases[2].T0 then
			roll.Hopped = true
			if roll.Mine then
				sfx("Boing", 1.35, 0.35)
			end
		end
		if not roll.Landed and t >= path.Landed then
			roll.Landed = true
			if roll.Mine then
				sfx("Click", 0.9, 0.5)
			end
		end
	end
end

-- Screens -------------------------------------------------------------------------------------------

local function surface(part: BasePart, pixels: number): SurfaceGui
	return UIKit.new("SurfaceGui", {
		Name = "Screen_" .. part.Name,
		Adornee = part,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = pixels,
		LightInfluence = 0,
		Brightness = 1.5,
		MaxDistance = 260,
		ResetOnSpawn = false,
		Parent = playerGui,
	})
end

local function todayTop(): (string?, number?)
	local part = boardPart
	local raw = part and part:GetAttribute("Board")
	if type(raw) ~= "string" then
		return nil, nil
	end
	local ok, rows = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok and type(rows) == "table" and rows[1] then
		return rows[1].N, rows[1].S
	end
	return nil, nil
end

-- A machine's score screen: PLAY ME! while it's free, the player's name, score, best and balls left
-- while they play, and the final score after.
local function buildScreen(machine: Machine, part: BasePart)
	local gui = surface(part, 50)
	local frame = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(14, 10, 30),
		BorderSizePixel = 0,
		Parent = gui,
		Children = {
			UIKit.Gradient(Color3.fromRGB(34, 22, 70), Color3.fromRGB(10, 8, 24)),
			UIKit.new("UIStroke", { Color = machine.Color, Thickness = 3, Transparency = 0.1 }),
		},
	})
	local big = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		TextColor3 = Theme.Colors.Yellow,
		Position = UDim2.fromScale(0.3, 0.06),
		Size = UDim2.fromScale(0.4, 0.88),
		Parent = frame,
	})
	local name = UIKit.Label({
		Text = "",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.04, 0.1),
		Size = UDim2.fromScale(0.27, 0.42),
		Parent = frame,
	})
	local best = UIKit.Label({
		Text = "",
		TextScaled = true,
		TextColor3 = Theme.Colors.Cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.04, 0.55),
		Size = UDim2.fromScale(0.27, 0.34),
		Parent = frame,
	})
	local dots = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.73, 0.12),
		Size = UDim2.fromScale(0.24, 0.76),
		Parent = frame,
		Children = {
			UIKit.new("UIGridLayout", {
				CellSize = UDim2.fromScale(0.28, 0.28),
				CellPadding = UDim2.fromScale(0.06, 0.08),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})
	local dotFrames = {}
	for index = 1, SkeeBall.BALLS do
		dotFrames[index] = UIKit.new("Frame", {
			LayoutOrder = index,
			BackgroundColor3 = machine.Color,
			Parent = dots,
			Children = { UIKit.Round() },
		})
	end
	local wide = UIKit.Label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextScaled = true,
		TextColor3 = Theme.Colors.Yellow,
		Position = UDim2.fromScale(0.04, 0.04),
		Size = UDim2.fromScale(0.92, 0.6),
		Parent = frame,
	})
	local sub = UIKit.Label({
		Text = "",
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromScale(0.06, 0.62),
		Size = UDim2.fromScale(0.88, 0.32),
		Parent = frame,
	})
	local model = machine.Model
	local function draw()
		local state = model:GetAttribute("SkeeState") or "Idle"
		local score = model:GetAttribute("SkeeScore") or 0
		local playing = state == "Playing"
		big.Visible = playing
		name.Visible = playing
		best.Visible = playing
		dots.Visible = playing
		wide.Visible = not playing
		sub.Visible = not playing
		if playing then
			local rolled = model:GetAttribute("SkeeBalls") or 0
			if play.Active and play.Index == machine.Index then
				rolled = math.max(rolled, play.Rolled)
			end
			big.Text = tostring(score)
			name.Text = model:GetAttribute("SkeeName") or ""
			local previous = model:GetAttribute("SkeeBest") or 0
			best.Text = if previous > 0 then `BEST {previous}` else "FIRST GAME!"
			for index, dot in dotFrames do
				dot.BackgroundTransparency = if index <= SkeeBall.BALLS - rolled then 0 else 0.8
			end
		elseif state == "Over" then
			local previous = model:GetAttribute("SkeeBest") or 0
			wide.Text = `{score}`
			sub.Text = if score > previous and score > 0
				then "NEW BEST!"
				else `FINAL • BEST {math.max(previous, score)}`
		else
			-- Free: invite people over, and now and then show today's best.
			local _, topScore = todayTop()
			local phase = math.floor(os.clock() / 3) % 2
			wide.Text = "PLAY ME!"
			sub.Text = if topScore and phase == 1 then `TODAY'S BEST {topScore}` else "9 BALLS • BEAT YOUR BEST"
		end
	end
	machine.Draw = draw
	draw()
end

-- The TODAY'S BEST board over the machines: the top five today (one entry each), you in yellow.
local function buildBoard(part: BasePart)
	boardPart = part
	local gui = surface(part, 24)
	local frame = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = gui,
		Children = { UIKit.Gradient(Color3.fromRGB(70, 44, 150), Color3.fromRGB(30, 18, 70)) },
	})
	UIKit.Label({
		Text = "⭐ TODAY'S BEST ⭐",
		Font = Enum.Font.LuckiestGuy,
		TextScaled = true,
		TextColor3 = Theme.Colors.Yellow,
		Position = UDim2.fromScale(0.02, 0.03),
		Size = UDim2.fromScale(0.96, 0.3),
		Parent = frame,
		Children = { UIKit.TextStroke(0.1) },
	})
	local empty = UIKit.Label({
		Text = "Nobody yet today - be the first on the board!",
		TextScaled = true,
		Position = UDim2.fromScale(0.05, 0.42),
		Size = UDim2.fromScale(0.9, 0.36),
		Parent = frame,
	})
	local slots = {}
	for index = 1, #PLACES do
		local slot = UIKit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.88,
			Position = UDim2.fromScale(0.012 + (index - 1) * 0.1976, 0.38),
			Size = UDim2.fromScale(0.185, 0.58),
			Parent = frame,
			Children = { UIKit.Corner(10) },
		})
		local place = UIKit.Label({
			Text = PLACES[index],
			Font = Theme.Fonts.Display,
			TextScaled = true,
			TextColor3 = if index == 1
				then Color3.fromRGB(255, 214, 70)
				elseif index == 2 then Color3.fromRGB(220, 228, 245)
				elseif index == 3 then Color3.fromRGB(240, 160, 100)
				else Theme.Colors.TextDim,
			Position = UDim2.fromScale(0.05, 0.04),
			Size = UDim2.fromScale(0.9, 0.28),
			Parent = slot,
		})
		local who = UIKit.Label({
			Text = "",
			TextScaled = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromScale(0.05, 0.33),
			Size = UDim2.fromScale(0.9, 0.25),
			Parent = slot,
		})
		local score = UIKit.Label({
			Text = "",
			Font = Theme.Fonts.Display,
			TextScaled = true,
			TextColor3 = Theme.Colors.Yellow,
			Position = UDim2.fromScale(0.05, 0.6),
			Size = UDim2.fromScale(0.9, 0.36),
			Parent = slot,
		})
		slots[index] = { Frame = slot, Place = place, Who = who, Score = score }
	end
	local function draw()
		local raw = part:GetAttribute("Board")
		local ok, rows = pcall(HttpService.JSONDecode, HttpService, if type(raw) == "string" then raw else "[]")
		if not ok or type(rows) ~= "table" then
			rows = {}
		end
		empty.Visible = #rows == 0
		for index, slot in slots do
			local row = rows[index]
			slot.Frame.Visible = row ~= nil
			if row then
				slot.Who.Text = tostring(row.N or "")
				slot.Score.Text = tostring(row.S or 0)
				local mine = row.U == player.UserId
				slot.Frame.BackgroundColor3 = if mine then Theme.Colors.Yellow else Color3.new(1, 1, 1)
				slot.Frame.BackgroundTransparency = if mine then 0.55 else 0.88
			end
		end
		for _, machine in machines do
			if machine.Draw then
				machine.Draw()
			end
		end
	end
	part:GetAttributeChangedSignal("Board"):Connect(draw)
	draw()
end

-- Machines ------------------------------------------------------------------------------------------

local function addMachine(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local index = model:GetAttribute("SkeeIndex")
	local frame = model:GetAttribute("SkeeFrame")
	if type(index) ~= "number" or machines[index] then
		return
	end
	local color = model:GetAttribute("SkeeColor")
	local machine: Machine = {
		Model = model,
		Index = index,
		Frame = if typeof(frame) == "CFrame" then frame else model:GetPivot(),
		Color = if typeof(color) == "Color3" then color else Theme.Colors.Pink,
		Screen = nil,
		Prompt = nil,
		Draw = nil,
		Bulbs = { {}, {} },
		BulbColors = {},
		Glow = {},
		Pieces = {},
		PieceLooks = {},
		Chute = {},
		Ready = nil,
		Rolls = {},
		Flash = 0,
	}
	machines[index] = machine
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		if part.Name == "BulbsA" or part.Name == "BulbsB" then
			table.insert(machine.Bulbs[if part.Name == "BulbsA" then 1 else 2], part)
			machine.BulbColors[part] = part.Color
		elseif part.Name == "Glow" then
			table.insert(machine.Glow, part)
		elseif string.match(part.Name, "^Band%d+$") or string.match(part.Name, "^Cup100") then
			machine.Pieces[part.Name] = part
		elseif part.Name == "Screen" then
			machine.Screen = part
		end
	end
	for _ = 1, SkeeBall.BALLS do
		local ball = newBall(machine.Color)
		if ball then
			table.insert(machine.Chute, ball)
		end
	end
	machine.Ready = newBall(machine.Color)
	if machine.Screen then
		buildScreen(machine, machine.Screen)
	end
	-- While you play, the next machine's "Play SKEE-BALL" prompt (its spot is within reach of
	-- yours) stays off your screen, even when the server turns it back on (showPrompts).
	local stand = model:FindFirstChild("Stand")
	local prompt = stand and stand:FindFirstChildOfClass("ProximityPrompt")
	machine.Prompt = prompt
	if prompt then
		prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
			if play.Active and prompt.Enabled then
				prompt.Enabled = false
			end
		end)
		if play.Active then
			prompt.Enabled = false
		end
	end
	for _, attribute in { "SkeeState", "SkeeScore", "SkeeBalls", "SkeeName", "SkeeBest" } do
		model:GetAttributeChangedSignal(attribute):Connect(function()
			if attribute == "SkeeState" and model:GetAttribute("SkeeState") == "Idle" then
				clearRolls(machine) -- a game that ended: balls still rolling don't count
			end
			if attribute == "SkeeBalls" then
				-- The server took this device's balls up to its count (a ball that had to wait
				-- its turn there is echoed a moment later).
				local counted = model:GetAttribute("SkeeBalls") or 0
				for _, roll in machine.Rolls do
					if roll.Mine and roll.Number <= counted then
						confirm(machine, roll)
					end
				end
			end
			if machine.Draw then
				machine.Draw()
			end
			showWaiting(machine)
			if play.Active and play.Index == machine.Index then
				refreshControls()
			end
		end)
	end
	showWaiting(machine)
end

-- The bulbs chase (faster while someone plays, a party after a 100 or a new best), and a playing
-- machine's neon strips breathe.
local function lights(now: number)
	local reduced = State.ReducedEffects()
	for _, machine in machines do
		local state = machine.Model:GetAttribute("SkeeState") or "Idle"
		local party = now < machine.Flash
		local rate = if party then 10 elseif state == "Playing" then 4 else 1.6
		local beat = if reduced then 0 else math.floor(now * rate) % 2
		for set, parts in machine.Bulbs do
			local lit = (set - 1) == beat
			for _, part in parts do
				local base = machine.BulbColors[part]
				if party and not reduced then
					part.Color = Color3.fromHSV((now * 1.5 + set * 0.5) % 1, 0.5, 1)
				else
					part.Color = if lit or reduced then base else base:Lerp(Color3.fromRGB(70, 50, 90), 0.75)
				end
			end
		end
		local pulse = if state == "Playing" and not reduced then 0.5 + 0.5 * math.sin(now * 3) else 0.6
		for _, part in machine.Glow do
			part.Color = machine.Color:Lerp(Color3.new(1, 1, 1), pulse * 0.45)
		end
	end
end

-- The local game -------------------------------------------------------------------------------------

local function myMachine(): Machine?
	return if play.Active then machines[play.Index] else nil
end

local function character(): (Model?, Humanoid?, BasePart?)
	local model = player.Character
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	return model, humanoid, root
end

local function fadeModel(model: Model, amount: number)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") or item:IsA("Decal") then
			item.LocalTransparencyModifier = amount
		end
	end
end

local function setFade(amount: number)
	local model = player.Character
	if model then
		fadeModel(model, amount)
	end
end

-- Anyone else on your machine while you play (in its lane, up on its rails or its cage, or between
-- it and your camera) fades on your screen, so nobody can stand in front of your lane and rings.
local OTHERS_FADE = 0.85
local fadedOthers: { [Model]: boolean } = {}
local function fadeOthers(machine: Machine?)
	local inView: { [Model]: boolean } = {}
	if machine then
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local skip: { Instance } = { folder }
		if player.Character then
			table.insert(skip, player.Character)
		end
		params.FilterDescendantsInstances = skip
		local near, far = POSES.Play.Eye.Z - 1, -SkeeBall.FRONT_Z + 0.5
		local region = machine.Frame * CFrame.new(0, 8, (near + far) / 2)
		local size = Vector3.new(SkeeBall.HALF_WIDTH * 2 + 2, 16, far - near)
		for _, part in workspace:GetPartBoundsInBox(region, size, params) do
			local model = part:FindFirstAncestorOfClass("Model")
			if model and not inView[model] and model:FindFirstChildOfClass("Humanoid") then
				inView[model] = true
			end
		end
	end
	for model in fadedOthers do
		if not inView[model] then
			fadedOthers[model] = nil
			if model.Parent then
				fadeModel(model, 0)
			end
		end
	end
	for model in inView do
		fadedOthers[model] = true
		fadeModel(model, OTHERS_FADE)
	end
end

-- The dotted aim line on the lane: where the ball will head, longer and hotter with more power.
local function showAim(aim: number, power: number, visible: boolean)
	local machine = myMachine()
	local dots = ui.AimDots
	if not dots then
		return
	end
	local slant = math.clamp(aim, -1, 1) * SkeeBall.AIM_SLANT
	local reach = 1 + math.clamp(power, 0, 1) * 5.4
	local color = Color3.fromHSV(0.33 - math.clamp(power, 0, 1) * 0.33, 0.85, 1)
	for index, dot in dots do
		local s = 0.75 + (index - 1) * 0.62
		if not machine or not visible or s > reach then
			dot.Parent = nil
			continue
		end
		local u = slant * s
		dot.Color = color
		dot.CFrame = machine.Frame * CFrame.new(lanePoint(u, SkeeBall.FloorY(s) + 0.07, s))
		dot.Parent = folder
	end
	-- The ball itself, pulled back a little toward your finger.
	local ready = machine and machine.Ready
	if machine and ready and play.Rolled < SkeeBall.BALLS then
		local back = if visible then math.clamp(power, 0, 1) * 0.55 else 0
		local side = if visible then -slant * 3 else 0
		placeBall(machine, ready, lanePoint(side, SkeeBall.FloorY(-back) + SkeeBall.BALL_R, -back))
	end
end

-- Whether you can aim your next ball (you can start while the last one is still in the air).
local function canAim(): boolean
	return play.Active and not play.Over and play.Rolled < SkeeBall.BALLS and (myMachine() ~= nil)
end

-- Whether it can roll right now (the last ball has come down).
local function canRoll(): boolean
	return canAim() and os.clock() >= play.NextRollAt
end

function refreshControls()
	local button = ui.Roll
	if not button then
		return
	end
	local ready = canAim()
	button.Text = if play.Meter == "Aim" then "AIM!" elseif play.Meter == "Power" then "POWER!" else "ROLL"
	button.AutoButtonColor = false
	button.TextTransparency = if ready or play.Meter ~= "Idle" then 0 else 0.45
	ui.Meter.Visible = play.Meter == "Power" or play.Dragging ~= nil
	local machine = myMachine()
	local model = machine and machine.Model
	local score = model and model:GetAttribute("SkeeScore") or 0
	ui.Score.Text = `SCORE {score}`
	local left = SkeeBall.BALLS - play.Rolled
	ui.Balls.Text = string.rep("●", left) .. string.rep("○", SkeeBall.BALLS - left)
	ui.BestLabel.Text = if play.Best > 0 then `BEST {play.Best}` else "FIRST GAME!"
end

-- The tip over the score: how to roll (until your first ball), or, while the vote is on and you're
-- down to play, that a round is coming (sitting out keeps you rolling).
function refreshHint()
	local hint = ui.Hint
	if not hint then
		return
	end
	local showing = play.Active and not play.Over
	local soon = showing and GameState.Get("Phase") == "Voting" and player:GetAttribute("PP_SitOut") ~= true
	hint.Text = if soon then HINT_TEXT.Soon elseif UIKit.IsTouch() then HINT_TEXT.Touch else HINT_TEXT.Pc
	hint.TextColor3 = if soon then Theme.Colors.Yellow else ui.HintColor
	-- (Phones put it away while the vote's up: the column rises over the vote cards then, and its top
	-- would reach the profile chip; the cards and the timer say a round is coming anyway.)
	hint.Visible = showing and (soon or play.Rolled == 0) and not (voteShowing and UIKit.IsTouch())
end

local function roll(aim: number, power: number)
	local machine = myMachine()
	if not machine or not canAim() then
		return
	end
	local wait = play.NextRollAt - os.clock()
	if wait > 0 then
		-- Let go while the last ball's still in the air: this one goes as soon as it lands.
		local number = play.Rolled
		task.delay(wait, function()
			if play.Rolled == number and canRoll() then
				roll(aim, power)
			end
		end)
		return
	end
	local number = play.Rolled + 1
	local aimQ, powerQ = SkeeBall.Quantize(aim, power)
	local path = SkeeBall.Path(aimQ, powerQ, number)
	remote:FireServer("Roll", number, aimQ / 1000 - 1, powerQ / 1000)
	play.Rolled = number
	play.NextRollAt = os.clock() + path.Landed
	startRoll(machine, path, number, true)
	showWaiting(machine)
	if machine.Draw then
		machine.Draw()
	end
	refreshHint()
	refreshControls()
end

-- The ROLL meter: tap to stop the aim, tap to stop the power (and roll).
local function pressRoll()
	if not play.Active or play.Over then
		return
	end
	if play.Meter == "Idle" then
		if not canAim() then
			return
		end
		play.Meter = "Aim"
		play.MeterStart = os.clock()
	elseif play.Meter == "Aim" then
		play.Meter = "Power"
		play.MeterStart = os.clock()
	else
		play.Meter = "Idle"
		roll(play.MeterAim, play.Power)
		showAim(0, 0, false)
	end
	refreshControls()
end

local function meterValues(now: number)
	local t = now - play.MeterStart
	if play.Meter == "Aim" then
		-- Swings from the middle out to the right, across to the left and back.
		local phase = (t / AIM_SWING) % 1
		local tri = if phase < 0.25 then phase * 4 elseif phase < 0.75 then 2 - phase * 4 else phase * 4 - 4
		play.MeterAim = tri
		showAim(tri, 0.45, true)
	elseif play.Meter == "Power" then
		local phase = (t / POWER_SWING) % 1
		play.Power = if phase < 0.5 then phase * 2 else 2 - phase * 2
		showAim(play.MeterAim, play.Power, true)
		ui.MeterFill.Size = UDim2.fromScale(1, play.Power)
	end
end

-- Dragging back on the lane: down for power, sideways to aim (the ball goes the other way, like a
-- slingshot), let go to roll (SkeeBallView.Drag). A drag that starts low, on the waiting ball,
-- reaches full power at the screen's bottom edge, so every target can be hit from there.
local function dragValues(): (number, number)
	local size = workspace.CurrentCamera.ViewportSize
	-- Touch and mouse positions leave out the top bar, so the bottom edge is that much higher.
	local bottom = size.Y - GuiService:GetGuiInset().Y
	return SkeeBallView.Drag(play.DragStart.X, play.DragStart.Y, play.DragAt.X, play.DragAt.Y, size.X, size.Y, bottom)
end

-- Follows the finger or mouse. A locked mouse (shift lock) stays in the middle of the screen, so
-- its movements add up instead.
local function dragTo(input: InputObject)
	local kind = input.UserInputType
	local locked = UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default
	if kind == Enum.UserInputType.MouseMovement and locked then
		play.DragAt += Vector2.new(input.Delta.X, input.Delta.Y)
	elseif kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch then
		play.DragAt = Vector2.new(input.Position.X, input.Position.Y)
	end
end

-- Where a touch moves you instead (unless the move controls are put away).
local function inThumbstickZone(position: Vector2): boolean
	if not UIKit.IsTouch() or play.Controls then
		return false
	end
	local size = workspace.CurrentCamera.ViewportSize
	return position.X < size.X * 0.4 and position.Y > size.Y / 3
end

-- Drops a drag without rolling (the window lost focus, or the system took the touch).
local function cancelDrag()
	if play.Dragging then
		play.Dragging = nil
		showAim(0, 0, false)
		refreshControls()
	end
end

local function onInputBegan(input: InputObject, processed: boolean)
	local dragging = play.Dragging
	if
		dragging
		and (
			dragging.UserInputState == Enum.UserInputState.End
			or dragging.UserInputState == Enum.UserInputState.Cancel
		)
	then
		play.Dragging = nil -- its end never came here: a new touch starts afresh
	end
	if processed or not play.Active or play.Over or play.Dragging then
		return
	end
	local kind = input.UserInputType
	if kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	if inThumbstickZone(position) or not canAim() then
		return
	end
	play.Meter = "Idle"
	play.Dragging = input
	play.DragStart = position
	play.DragAt = position
	play.Aim, play.Power = 0, 0
	refreshControls()
end

local function onInputChanged(input: InputObject)
	local dragging = play.Dragging
	if not dragging then
		return
	end
	local follows = input == dragging
		or (
			dragging.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseMovement
		)
	if not follows then
		return
	end
	dragTo(input)
	play.Aim, play.Power = dragValues()
	showAim(play.Aim, play.Power, true)
	ui.MeterFill.Size = UDim2.fromScale(1, play.Power)
end

local function onInputEnded(input: InputObject)
	local dragging = play.Dragging
	if not dragging then
		return
	end
	-- Only the drag's own finger ends it: another finger lifting meanwhile (a thumb brushing the
	-- screen, a tap on a vote card) changes nothing. A mouse drag ends with its button.
	local mouse = dragging.UserInputType == Enum.UserInputType.MouseButton1
		and input.UserInputType == Enum.UserInputType.MouseButton1
	if input ~= dragging and not mouse then
		return
	end
	if input.UserInputState == Enum.UserInputState.Cancel then
		cancelDrag() -- the system took the touch (a notification, a swipe from the edge): no roll
		return
	end
	play.Dragging = nil
	dragTo(input)
	local aim, power = dragValues()
	showAim(0, 0, false)
	if power >= 0.06 then
		roll(aim, power)
	end
	refreshControls()
end

local function leave()
	if play.Active then
		remote:FireServer("Leave")
	end
end

-- Phones: puts the MOVE stick and jump button away while you play, and back after.
local function putControlsAway(away: boolean)
	local touch = UIKit.IsTouch()
	if away and touch and not play.Controls then
		pcall(function()
			local scripts = player:FindFirstChild("PlayerScripts")
			local module = scripts and scripts:FindFirstChild("PlayerModule")
			if module then
				local controls = (require(module :: any) :: any):GetControls()
				controls:Disable()
				play.Controls = controls
			end
		end)
	elseif not away and play.Controls then
		local controls = play.Controls
		play.Controls = nil
		pcall(function()
			controls:Enable()
		end)
	end
	if ui.Hud then
		-- Tells the UI checks (ui_render.py) the stick and jump button aren't on screen.
		ui.Hud:SetAttribute("PP_NoTouchControls", if away and touch then true else nil)
	end
end

-- Puts the move controls away again a moment after a phase change, in case something else brought
-- them back meanwhile (a round's clean-up hands back the controls it put away).
local function holdControlsAway()
	task.delay(0.1, function()
		local controls = play.Controls
		if play.Active and controls then
			pcall(function()
				controls:Disable()
			end)
		end
	end)
end

-- The machines' prompts on this screen: all off while you play; after, on where the machine is
-- free (the server's own rule, so this device agrees with it).
local function showPrompts(show: boolean)
	for _, machine in machines do
		local prompt = machine.Prompt
		if prompt then
			prompt.Enabled = show and (machine.Model:GetAttribute("SkeeUser") or 0) == 0
		end
	end
end

local function exitPlay()
	if not play.Active then
		return
	end
	play.Active = false
	play.Over = false
	play.Dragging = nil
	play.Meter = "Idle"
	for _, connection in play.Connections do
		connection:Disconnect()
	end
	table.clear(play.Connections)
	pcall(ContextActionService.UnbindAction, ContextActionService, "SkeeBallRoll")
	RunService:UnbindFromRenderStep("SkeeBallCamera")
	putControlsAway(false)
	showPrompts(true)
	showAim(0, 0, false)
	setFade(0)
	fadeOthers(nil)
	local camera = workspace.CurrentCamera
	local _, humanoid = character()
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = play.SavedFov
	if humanoid then
		camera.CameraSubject = humanoid
	end
	for _, name in { "SkeeBallControls", "SkeeBallDone", "SkeeBallOver", "Pop" } do
		local item = ui[name]
		if item then
			item.Visible = false
		end
	end
	-- The first-join tips step back in (OnboardingController).
	ui.Hud:SetAttribute("PP_TipsAside", nil)
	local machine = machines[play.Index]
	if machine then
		showWaiting(machine)
	end
end

local function enterPlay(index: number, best: number)
	local machine = machines[index]
	if not machine then
		-- This device hasn't set the machine up yet (it's still loading): free it again.
		remote:FireServer("Leave")
		return
	end
	local fresh = not play.Active
	play.Active = true
	play.Index = index
	play.Best = if type(best) == "number" then best else 0
	play.Rolled = 0
	play.NextRollAt = os.clock() + 0.3
	play.Over = false
	play.Meter = "Idle"
	ui.SkeeBallOver.Visible = false
	ui.SkeeBallControls.Visible = true
	ui.SkeeBallDone.Visible = true
	refreshHint()
	refreshControls()
	showWaiting(machine)
	if not fresh then
		return
	end
	-- The first-join tips ("tap a card to vote") step aside while you play: on phones they share
	-- the top of the screen with DONE (OnboardingController).
	ui.Hud:SetAttribute("PP_TipsAside", true)
	showPrompts(false)
	-- Step up to the machine (at the height you stand at), facing it, and frame the lane.
	local _, _, root = character()
	local stand = machine.Frame:PointToWorldSpace(Vector3.new(0, 0, SkeeBall.STAND_Z))
	if root then
		local model = player.Character :: Model
		local at = Vector3.new(stand.X, root.Position.Y, stand.Z)
		model:PivotTo(CFrame.lookAt(at, at - machine.Frame.LookVector))
		root.AssemblyLinearVelocity = Vector3.zero
	end
	local camera = workspace.CurrentCamera
	play.SavedFov = camera.FieldOfView
	play.Pose = nil
	camera.CameraType = Enum.CameraType.Scriptable
	-- Held every frame while you play: it swings in behind your lane (and to the vote's pose and
	-- back), then stays there whatever else touches the camera.
	RunService:BindToRenderStep("SkeeBallCamera", Enum.RenderPriority.Camera.Value + 1, function()
		local mine = myMachine()
		if not mine then
			return
		end
		local current = workspace.CurrentCamera
		if current.CameraType ~= Enum.CameraType.Scriptable then
			current.CameraType = Enum.CameraType.Scriptable
		end
		local pose = if voteShowing then POSES.Vote else POSES.Play
		if pose ~= play.Pose then
			play.Pose = pose
			play.CameraFrom = current.CFrame
			play.FovFrom = current.FieldOfView
			play.CameraStart = os.clock()
		end
		local goal = CFrame.lookAt(mine.Frame:PointToWorldSpace(pose.Eye), mine.Frame:PointToWorldSpace(pose.Look))
		local k = math.clamp((os.clock() - play.CameraStart) / CAMERA_BLEND, 0, 1)
		local eased = 1 - (1 - k) * (1 - k)
		current.CFrame = play.CameraFrom:Lerp(goal, eased)
		current.FieldOfView = play.FovFrom + (pose.Fov - play.FovFrom) * eased
		setFade(SELF_FADE)
	end)
	-- Space, Enter or a controller's A press ROLL (and don't jump while you play).
	pcall(function()
		ContextActionService:BindActionAtPriority(
			"SkeeBallRoll",
			function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					pressRoll()
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.Space,
			Enum.KeyCode.Return,
			Enum.KeyCode.ButtonA
		)
	end)
	table.insert(play.Connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(play.Connections, UserInputService.InputChanged:Connect(onInputChanged))
	table.insert(play.Connections, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(play.Connections, UserInputService.WindowFocusReleased:Connect(cancelDrag))
	putControlsAway(true)
	play.MovingSince = 0
	sfx("VoteOpen", 1.15, 0.45)
end

-- After the ninth ball: the final score, a fanfare, PLAY AGAIN or DONE.
local function showOver(score: number, previous: number, newBest: boolean, place: number)
	play.Over = true
	play.Meter = "Idle"
	ui.SkeeBallControls.Visible = false
	ui.SkeeBallDone.Visible = false -- the panel has its own DONE
	ui.Hint.Visible = false
	ui.Meter.Visible = false
	ui.Pop.Visible = false
	ui.OverScore.Text = tostring(score)
	if newBest then
		ui.OverTitle.Text = if previous > 0 then "NEW BEST!" else "FIRST SCORE!"
		ui.OverTitle.TextColor3 = Theme.Colors.Yellow
	else
		ui.OverTitle.Text = "FINAL SCORE"
		ui.OverTitle.TextColor3 = Color3.new(1, 1, 1)
	end
	local lines = {}
	if newBest and previous > 0 then
		table.insert(lines, `Your old best was {previous}`)
	elseif not newBest then
		table.insert(lines, `Your best: {math.max(previous, score)}`)
	end
	if place > 0 then
		table.insert(lines, `{PLACES[place] or "#" .. place} on today's board!`)
	end
	ui.OverInfo.Text = table.concat(lines, "  •  ")
	ui.SkeeBallOver.Visible = true
	UIKit.PopIn(ui.OverPanel, 0.45)
	sfx(if newBest or place == 1 then "Victory" else "Results", 1, 0.7)
	if newBest then
		play.Best = score
	end
end

-- UI ------------------------------------------------------------------------------------------------

local function buildUi(hud: Instance)
	local touch = UIKit.IsTouch()
	ui.Hud = hud

	-- Low on the left, beside the lane: what to do (until the first roll), your score and balls,
	-- the big ROLL button, and the power meter between them and the lane. One scaled holder, so it
	-- keeps its shape on every screen. (On phones that's the MOVE stick's corner: the stick is put
	-- away while you play.) On PC the holder has room for the vote cards under the controls: the
	-- column sits low in it, and rises above the cards while they're up (placeColumn), so it's
	-- never over the cards nor, during a round, over the standings on the left.
	local rollHeight = if touch then ROLL_HEIGHT else PC_ROLL_HEIGHT
	local hintHeight = if touch then HINT_HEIGHT else PC_HINT_HEIGHT
	local controlsHeight = SCORE_HEIGHT + 12 + rollHeight
	local width = COLUMN_WIDTH + 12 + METER_WIDTH
	local holder = UIKit.new("Frame", {
		Name = "SkeeBallControls",
		AnchorPoint = Vector2.new(0, 1),
		Position = if touch then UDim2.new(0, 12, 1, -10) else UDim2.new(0, 24, 1, 0),
		Size = UDim2.fromOffset(width, hintHeight + controlsHeight + (if touch then TOUCH_VOTE_ROW else PC_VOTE_ROOM)),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud,
	})
	UIKit.AutoScale(holder)
	ui.SkeeBallControls = holder
	local column = UIKit.new("Frame", {
		Name = "Column",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, if touch then 0 else -PC_BOTTOM),
		Size = UDim2.fromOffset(width, hintHeight + controlsHeight),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	ui.Column = column
	local card = UIKit.Panel({
		Name = "ScoreCard",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -(rollHeight + 12)),
		Size = UDim2.fromOffset(COLUMN_WIDTH, SCORE_HEIGHT),
		CornerRadius = 22,
		Parent = column,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	ui.Score = UIKit.Label({
		Text = "SCORE 0",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.fromOffset(COLUMN_WIDTH - 32, 38),
		Parent = card,
		Children = { UIKit.TextStroke(0.2) },
	})
	ui.Balls = UIKit.Label({
		Text = "",
		TextSize = 22,
		TextWrapped = false,
		TextColor3 = Theme.Colors.Yellow,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 46),
		Size = UDim2.fromOffset(130, 30),
		Parent = card,
	})
	ui.BestLabel = UIKit.Label({
		Text = "",
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextColor3 = Theme.Colors.Cyan,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(COLUMN_WIDTH - 16 - 104, 47),
		Size = UDim2.fromOffset(104, 28),
		Parent = card,
	})
	ui.Roll = UIKit.Button({
		Name = "Roll",
		Text = "ROLL",
		TextSize = if touch then 40 else 34,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(COLUMN_WIDTH, rollHeight),
		CornerRadius = 30,
		Parent = column,
	}, pressRoll, Theme.Colors.Green, Color3.fromRGB(40, 160, 90))

	-- The power meter by the lane (while dragging or charging).
	local meter = UIKit.new("Frame", {
		Name = "Meter",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(METER_WIDTH, controlsHeight),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Visible = false,
		Parent = column,
		Children = { UIKit.Corner(14), UIKit.Stroke(nil, 2, 0.4) },
	})
	ui.Meter = meter
	ui.MeterFill = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = meter,
		Children = {
			UIKit.Corner(14),
			UIKit.Gradient(Color3.fromRGB(255, 80, 90), Color3.fromRGB(110, 230, 140)),
		},
	})

	-- What to do, on top of the column until the first roll (and that a round is coming, while the
	-- vote is on: refreshHint).
	local hint = UIKit.Label({
		Name = "Hint",
		Text = if touch then HINT_TEXT.Touch else HINT_TEXT.Pc,
		Font = Theme.Fonts.Display,
		TextSize = if touch then 26 else 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Position = UDim2.fromOffset(4, 0),
		Size = UDim2.fromOffset(width - 4, hintHeight - 10),
		Visible = false,
		Parent = column,
		Children = { UIKit.TextStroke(0.1) },
	})
	hint:SetAttribute("PP_Lines", 2)
	ui.Hint = hint
	ui.HintColor = hint.TextColor3

	-- DONE: on phones top right, beside the menu column and under the vote cards' row (one scaled
	-- holder with room for the column and the row, so the gaps stay the same on every screen); on
	-- PC bottom right, past the end of the vote cards.
	local doneWidth = if touch then 150 else 120
	local doneHolder = UIKit.new("Frame", {
		Name = "SkeeBallDone",
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(1, 1),
		Position = if touch then UDim2.new(1, -8, 0, 0) else UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(
			if touch then doneWidth + 12 + Theme.Touch.Target + 20 else doneWidth,
			if touch then TOUCH_VOTE_ROOM + Theme.Touch.Target else 64
		),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud,
	})
	UIKit.AutoScale(doneHolder)
	UIKit.Button({
		Name = "Done",
		Text = "DONE",
		TextSize = 30,
		Position = UDim2.fromOffset(0, if touch then TOUCH_VOTE_ROOM else 0),
		Size = UDim2.fromOffset(doneWidth, if touch then Theme.Touch.Target else 64),
		CornerRadius = 22,
		Parent = doneHolder,
	}, leave, Theme.Colors.Pink, Color3.fromRGB(200, 50, 140))
	ui.SkeeBallDone = doneHolder

	-- The score pop for each ball, over the machine's rings (on phones a little lower, under the
	-- vote cards' row).
	local pop = UIKit.Label({
		Name = "SkeeBallPop",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 70,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if touch then 0.34 else 0.28),
		Size = UDim2.fromOffset(360, 110),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0) },
	})
	UIKit.AutoScale(pop)
	ui.Pop = pop

	-- The end of a game: final score, best, today's place, PLAY AGAIN / DONE (on PC clear of the
	-- vote cards along the bottom).
	local over = UIKit.new("Frame", {
		Name = "SkeeBallOver",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if touch then 0.48 else 0.42),
		Size = UDim2.fromOffset(440, 260),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud,
	})
	UIKit.AutoScale(over)
	ui.SkeeBallOver = over
	local panel = UIKit.Panel({
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		CornerRadius = 26,
		Parent = over,
	})
	ui.OverPanel = panel
	ui.OverTitle = UIKit.Label({
		Text = "FINAL SCORE",
		Font = Theme.Fonts.Display,
		TextSize = 34,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = panel,
		Children = { UIKit.TextStroke(0.1) },
	})
	ui.OverScore = UIKit.Label({
		Text = "0",
		Font = Theme.Fonts.Display,
		TextSize = 64,
		TextWrapped = false,
		TextColor3 = Theme.Colors.Yellow,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 70),
		Parent = panel,
		Children = { UIKit.TextStroke(0) },
	})
	ui.OverInfo = UIKit.Label({
		Text = "",
		TextSize = Theme.Touch.MinText + 2,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(16, 120),
		Size = UDim2.new(1, -32, 0, 44),
		Parent = panel,
	})
	ui.OverInfo:SetAttribute("PP_Lines", 2)
	UIKit.Button({
		Name = "Again",
		Text = "PLAY AGAIN",
		TextSize = 28,
		Position = UDim2.fromOffset(20, 172),
		Size = UDim2.fromOffset(230, 72),
		CornerRadius = 22,
		Parent = panel,
	}, function()
		remote:FireServer("Again")
	end, Theme.Colors.Green, Color3.fromRGB(40, 160, 90))
	UIKit.Button({
		Name = "Done",
		Text = "DONE",
		TextSize = 28,
		Position = UDim2.fromOffset(266, 172),
		Size = UDim2.fromOffset(154, 72),
		CornerRadius = 22,
		Parent = panel,
	}, leave, Theme.Colors.Pink, Color3.fromRGB(200, 50, 140))

	-- The aim line's dots live in the world.
	ui.AimDots = {}
	for _ = 1, 10 do
		local dot = Instance.new("Part")
		dot.Name = "AimDot"
		dot.Shape = Enum.PartType.Ball
		dot.Size = Vector3.one * 0.22
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CanTouch = false
		dot.CastShadow = false
		dot.Material = Enum.Material.Neon
		table.insert(ui.AimDots, dot)
	end
end

-- The controls column rises above the vote cards while they're up, and sits low the rest of the
-- time (PC: under the round's standings on the left; phones: in the MOVE stick's corner).
local function placeColumn(animate: boolean)
	local column = ui.Column
	if not column then
		return
	end
	local touch = UIKit.IsTouch()
	local goal = if touch
		then UDim2.new(0, 0, 1, if voteShowing then -TOUCH_VOTE_ROW else 0)
		else UDim2.new(0, 0, 1, -(if voteShowing then PC_VOTE_ROOM else PC_BOTTOM))
	if animate then
		UIKit.Tween(column, 0.3, { Position = goal })
	else
		column.Position = goal
	end
end

-- Remote events ---------------------------------------------------------------------------------------

local function onEvent(kind: any, index: any, ...: any)
	if type(index) ~= "number" then
		return
	end
	local machine = machines[index]
	if kind == "Start" then
		local best = ...
		enterPlay(index, best)
	elseif kind == "End" then
		if play.Active and play.Index == index then
			exitPlay()
		end
	elseif kind == "Sync" and machine then
		-- The server refused a roll from this device: these many balls count.
		local counted = ...
		if type(counted) == "number" and play.Active and play.Index == index then
			settleRolls(machine, counted)
		end
	elseif kind == "Rolled" and machine then
		local ball, aimQ, powerQ = ...
		if type(ball) ~= "number" or type(aimQ) ~= "number" or type(powerQ) ~= "number" then
			return
		end
		local mine = play.Active and play.Index == index
		local existing = nil
		for _, rolling in machine.Rolls do
			if rolling.Number == ball then
				existing = rolling
			end
		end
		local path = SkeeBall.Path(aimQ, powerQ, ball)
		if existing then
			if existing.Path.AimQ == aimQ and existing.Path.PowerQ == powerQ then
				confirm(machine, existing)
				return
			end
			-- This device rolled that ball another way than the server took it (it rolled again
			-- after a refusal while the first one was taken after all): the server's is the real one.
			existing.Model:Destroy()
			table.remove(machine.Rolls, table.find(machine.Rolls, existing) :: number)
			if mine and play.Rolled == ball then
				play.NextRollAt = os.clock() + path.Landed
			end
		elseif mine then
			if play.Rolled >= ball then
				return -- this device's roll that already finished
			end
			-- The server took a roll this device had given up on: catch up.
			play.Rolled = ball
			play.NextRollAt = os.clock() + path.Landed
			showWaiting(machine)
			refreshControls()
		end
		local camera = workspace.CurrentCamera
		if (camera.CFrame.Position - machine.Frame.Position).Magnitude > ANIMATE_RANGE then
			return
		end
		local rolled = startRoll(machine, path, ball, mine)
		if rolled then
			rolled.Confirmed = true
		end
	elseif kind == "Over" and machine then
		local userId, score, previous, newBest, place = ...
		if type(score) ~= "number" then
			return
		end
		if newBest or (type(place) == "number" and place > 0) then
			machine.Flash = os.clock() + 3
		end
		if userId == player.UserId and play.Active and play.Index == index then
			showOver(score, previous or 0, newBest == true, if type(place) == "number" then place else 0)
		elseif newBest then
			popOver(machine, "NEW BEST!", Theme.Colors.Yellow, true)
		end
	end
end

-- Rolls your next ball as if you'd let go of a drag (aim -1..1, power 0..1); false if you can't
-- roll right now. The UI checks use it; any other input could too.
function SkeeBallController.Roll(aim: number, power: number): boolean
	if not canRoll() then
		return false
	end
	play.Meter = "Idle"
	roll(aim, power)
	showAim(0, 0, false)
	return true
end

-- Presses ROLL, like the button or Space: starts the aim swinging, stops it, then the power.
function SkeeBallController.PressRoll()
	pressRoll()
end

-- What the local game stands at (for the UI checks): playing, balls rolled, a drag going on.
function SkeeBallController.Status(): { Active: boolean, Rolled: number, Dragging: boolean, Aim: number, Power: number }
	return {
		Active = play.Active,
		Rolled = play.Rolled,
		Dragging = play.Dragging ~= nil,
		Aim = play.Aim,
		Power = play.Power,
	}
end

function SkeeBallController.Start(context)
	remote = Remotes.Get("SkeeBall")
	folder = Instance.new("Folder")
	folder.Name = "SkeeBallLocal"
	folder.Parent = workspace
	buildUi(context.Hud)

	task.spawn(function()
		local assets = ReplicatedStorage:WaitForChild("ArcadeAssets", 60)
		local template = assets and assets:WaitForChild("SkeeBall", 30)
		if not template or not template:IsA("Model") then
			return
		end
		ballTemplate = template
		local box = template:GetBoundingBox()
		ballCenter = template:GetPivot():PointToObjectSpace(box.Position)
		for _, tagged in CollectionService:GetTagged("SkeeMachine") do
			task.spawn(addMachine, tagged)
		end
		CollectionService:GetInstanceAddedSignal("SkeeMachine"):Connect(addMachine)
	end)
	for _, part in CollectionService:GetTagged("SkeeBestBoard") do
		if part:IsA("BasePart") then
			buildBoard(part)
		end
	end
	CollectionService:GetInstanceAddedSignal("SkeeBestBoard"):Connect(function(part)
		if part:IsA("BasePart") and not boardPart then
			buildBoard(part)
		end
	end)

	remote.OnClientEvent:Connect(onEvent)

	-- A round taking you ends your game here and now, so the round's own camera and controls start
	-- from the lobby's (the server ends it too, and frees the machine).
	player:GetAttributeChangedSignal("PP_InRound"):Connect(function()
		if player:GetAttribute("PP_InRound") == true and play.Active then
			exitPlay()
		end
	end)
	voteShowing = GameState.Get("Phase") == "Voting"
	placeColumn(false)
	GameState.Changed("Phase", function(phase)
		voteShowing = phase == "Voting"
		refreshHint()
		placeColumn(play.Active)
		if play.Active then
			holdControlsAway()
		end
	end)
	player:GetAttributeChangedSignal("PP_SitOut"):Connect(refreshHint)

	local lastLights, lastScreens, lastOthers = 0, 0, 0
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for _, machine in machines do
			stepRolls(machine, now)
		end
		if play.Active then
			if play.Meter ~= "Idle" then
				meterValues(now)
			end
			if now - lastOthers > 0.2 then
				lastOthers = now
				fadeOthers(myMachine())
			end
			-- Walking away (WASD, a controller's stick) or being pushed off ends the game.
			local _, humanoid, root = character()
			local machine = myMachine()
			if humanoid and root and machine then
				local stand = machine.Frame * CFrame.new(0, 0, SkeeBall.STAND_Z)
				local away = Vector3.new(root.Position.X - stand.X, 0, root.Position.Z - stand.Z).Magnitude
				if humanoid.MoveDirection.Magnitude > 0.2 then
					if play.MovingSince == 0 then
						play.MovingSince = now
					end
				else
					play.MovingSince = 0
				end
				if away > 4 or (play.MovingSince > 0 and now - play.MovingSince > 0.25) then
					leave()
					exitPlay()
				end
			end
		end
		if now - lastLights > 0.05 then
			lastLights = now
			local camera = workspace.CurrentCamera
			local near = false
			for _, machine in machines do
				if (camera.CFrame.Position - machine.Frame.Position).Magnitude < ANIMATE_RANGE then
					near = true
				end
			end
			if near then
				lights(now)
			end
		end
		if now - lastScreens > 1 then
			lastScreens = now
			for _, machine in machines do
				if machine.Draw and (machine.Model:GetAttribute("SkeeState") or "Idle") == "Idle" then
					machine.Draw()
				end
			end
			if play.Active then
				refreshControls()
			end
		end
	end)
end

return SkeeBallController

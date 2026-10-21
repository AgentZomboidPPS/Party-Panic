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
--   Each ball pops its score; after the 9th, a fanfare and PLAY AGAIN / DONE. Walking away (the
--   MOVE stick) or DONE frees the machine. The ball rolls at once on your device and the server
--   checks it, so it feels instant.
-- Phones: the controls sit low between the MOVE stick's corner and the jump button, DONE beside the
-- menu column, nothing over the stick, the jump button or the menu.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local SkeeBall = require(Shared.Logic.SkeeBall)
local Sounds = require(Shared.Sounds)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local SkeeBallController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote: RemoteEvent

-- The play camera, in the machine's frame: behind and above the player, looking down the lane.
local CAMERA_EYE = Vector3.new(0, 9.6, -14.2)
local CAMERA_LOOK = Vector3.new(0, 3.5, 0.9)
local CAMERA_FOV = 52
local SELF_FADE = 0.8 -- your own character fades while you play (it would hide the ball)
local DRAG_POWER = 0.32 -- a drag this much of the screen's height is full power
local DRAG_AIM = 0.17 -- and this much of its width sideways is full aim
local AIM_SWING = 1.5 -- seconds for the ROLL meter's aim to swing across and back
local POWER_SWING = 1.25 -- and for its power to fill and empty
local CONFIRM_TIMEOUT = 2 -- a roll the server hasn't echoed by then didn't count
local ANIMATE_RANGE = 220
local CONTROLS_HEIGHT = 190 -- the low controls (score and ROLL), in UI units

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
	Confirmed: boolean,
}

type Machine = {
	Model: Model,
	Index: number,
	Frame: CFrame,
	Color: Color3,
	Screen: BasePart?,
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
	Aim = 0,
	Power = 0,
	SavedFov = 70,
	MovingSince = 0,
	Connections = {} :: { RBXScriptConnection },
}

local ui = {} :: { [string]: any }
local refreshControls: () -> () -- the score, balls and ROLL button under your lane (below)

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
	if path.Points > 0 then
		local color = RING_COLORS[pocket] or Theme.Colors.Yellow
		flashPocket(machine, pocket)
		popOver(machine, `+{path.Points}`, color, path.Points >= 100)
		if path.Points >= 100 then
			machine.Flash = os.clock() + 2.5
		end
		if mine then
			popScreen(if path.Points >= 100 then "+100!" else `+{path.Points}`, color, path.Points >= 50)
			sfx("Pickup", 0.8 + path.Points / 125, 0.7)
			if path.Points >= 100 then
				sfx("Purchase", 1, 0.6)
			end
		elseif screen then
			sfx("Pickup", 0.8 + path.Points / 125, 0.5, screen)
		end
	else
		popOver(machine, MISS_WORDS[pocket] or "MISS", Color3.fromRGB(220, 220, 235), false)
		if mine then
			popScreen(MISS_WORDS[pocket] or "MISS", Color3.fromRGB(230, 230, 245), false)
			sfx("Countdown", 0.55, 0.6)
		end
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
	}
	table.insert(machine.Rolls, roll)
	if mine then
		sfx("VoteClick", 0.8, 0.6)
	elseif machine.Screen then
		sfx("VoteClick", 0.8, 0.4, machine.Screen)
	end
	return roll
end

local function stepRolls(machine: Machine, now: number)
	local index = 1
	while index <= #machine.Rolls do
		local roll = machine.Rolls[index]
		local path = roll.Path
		local t = now - roll.Start
		if roll.Mine and not roll.Confirmed and t > CONFIRM_TIMEOUT then
			local counted = machine.Model:GetAttribute("SkeeBalls") or 0
			if counted >= roll.Number then
				roll.Confirmed = true -- the server took it; its word is on the way
			else
				-- The server never took it (a hiccup): this ball doesn't count, roll it again.
				roll.Model:Destroy()
				table.remove(machine.Rolls, index)
				if play.Active and play.Index == machine.Index then
					play.Rolled = counted
					play.NextRollAt = 0
					showWaiting(machine)
					refreshControls()
				end
				continue
			end
		end
		if t >= path.Done + 0.05 then
			roll.Model:Destroy()
			table.remove(machine.Rolls, index)
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
		local phase = path.Phases[#path.Phases]
		if t >= phase.T0 and not roll.Dropped then
			roll.Dropped = true
			dropped(machine, roll)
		end
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
		index += 1
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
		Text = "★ TODAY'S BEST ★",
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
	for _, attribute in { "SkeeState", "SkeeScore", "SkeeBalls", "SkeeName", "SkeeBest" } do
		model:GetAttributeChangedSignal(attribute):Connect(function()
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

local function setFade(amount: number)
	local model = player.Character
	if not model then
		return
	end
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") or item:IsA("Decal") then
			item.LocalTransparencyModifier = amount
		end
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
	ui.Hint.Visible = false
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
-- slingshot), let go to roll.
local function dragValues(position: Vector2): (number, number)
	local camera = workspace.CurrentCamera
	local size = camera.ViewportSize
	local delta = position - play.DragStart
	local power = math.clamp(delta.Y / (size.Y * DRAG_POWER), 0, 1)
	local aim = math.clamp(-delta.X / (size.X * DRAG_AIM), -1, 1)
	return aim, power
end

local function inThumbstickZone(position: Vector2): boolean
	if not UIKit.IsTouch() then
		return false
	end
	local size = workspace.CurrentCamera.ViewportSize
	return position.X < size.X * 0.4 and position.Y > size.Y / 3
end

local function onInputBegan(input: InputObject, processed: boolean)
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
	play.Aim, play.Power = dragValues(Vector2.new(input.Position.X, input.Position.Y))
	showAim(play.Aim, play.Power, true)
	ui.MeterFill.Size = UDim2.fromScale(1, play.Power)
end

local function onInputEnded(input: InputObject)
	local dragging = play.Dragging
	if not dragging or input ~= dragging and input.UserInputType ~= dragging.UserInputType then
		return
	end
	play.Dragging = nil
	local aim, power = dragValues(Vector2.new(input.Position.X, input.Position.Y))
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
	showAim(0, 0, false)
	setFade(0)
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
	-- The first-join tips step back in.
	local tip = ui.SteppedAside
	if tip and tip.Parent then
		tip.Visible = true
	end
	ui.SteppedAside = nil
	local machine = machines[play.Index]
	if machine then
		showWaiting(machine)
	end
end

local function enterPlay(index: number, best: number)
	local machine = machines[index]
	if not machine then
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
	ui.Hint.Visible = true
	refreshControls()
	showWaiting(machine)
	if not fresh then
		return
	end
	-- A first-join tip ("tap a card to vote") steps aside while you play: on phones it shares the
	-- top of the screen with DONE.
	local tip = ui.Hud and ui.Hud:FindFirstChild("Onboarding")
	if tip and tip:IsA("GuiObject") and tip.Visible then
		tip.Visible = false
		ui.SteppedAside = tip
	end
	-- Step up to the machine, facing it, and frame the lane.
	local _, _, root = character()
	local stand = machine.Frame * CFrame.new(0, 3, SkeeBall.STAND_Z)
	if root then
		local model = player.Character :: Model
		model:PivotTo(CFrame.lookAt(stand.Position, stand.Position + machine.Frame.LookVector * -1))
		root.AssemblyLinearVelocity = Vector3.zero
	end
	local camera = workspace.CurrentCamera
	play.SavedFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	local goal =
		CFrame.lookAt(machine.Frame:PointToWorldSpace(CAMERA_EYE), machine.Frame:PointToWorldSpace(CAMERA_LOOK))
	TweenService:Create(
		camera,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = goal, FieldOfView = CAMERA_FOV }
	):Play()
	RunService:BindToRenderStep("SkeeBallCamera", Enum.RenderPriority.Camera.Value + 1, function()
		if play.Active then
			setFade(SELF_FADE)
		end
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

	-- Low in the middle: what to do (until the first roll), your score and balls, the big ROLL
	-- button and the power meter beside it. Phones: right of the MOVE stick's corner, left of the
	-- jump button (everything in one scaled holder, so it keeps its shape on every screen).
	local holder = UIKit.new("Frame", {
		Name = "SkeeBallControls",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, if touch then 70 else 0, 1, if touch then -8 else -24),
		Size = UDim2.fromOffset(362, CONTROLS_HEIGHT + 86),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud,
	})
	UIKit.AutoScale(holder)
	ui.SkeeBallControls = holder
	local controls = UIKit.new("Frame", {
		Name = "Controls",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(300, CONTROLS_HEIGHT),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	local pill = UIKit.Panel({
		Name = "ScorePill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(300, 74),
		CornerRadius = 22,
		Parent = controls,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	ui.Score = UIKit.Label({
		Text = "SCORE 0",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 4),
		Size = UDim2.fromOffset(170, 34),
		Parent = pill,
		Children = { UIKit.TextStroke(0.2) },
	})
	ui.BestLabel = UIKit.Label({
		Text = "",
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextColor3 = Theme.Colors.Cyan,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(170, 8),
		Size = UDim2.fromOffset(114, 28),
		Parent = pill,
	})
	ui.Balls = UIKit.Label({
		Text = "",
		TextSize = 22,
		TextWrapped = false,
		TextColor3 = Theme.Colors.Yellow,
		Position = UDim2.fromOffset(12, 38),
		Size = UDim2.fromOffset(276, 30),
		Parent = pill,
	})
	ui.Roll = UIKit.Button({
		Name = "Roll",
		Text = "ROLL",
		TextSize = 40,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(250, 100),
		CornerRadius = 30,
		Parent = controls,
	}, pressRoll, Theme.Colors.Green, Color3.fromRGB(40, 160, 90))

	-- The power meter beside the controls (while dragging or charging).
	local meter = UIKit.new("Frame", {
		Name = "Meter",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(42, CONTROLS_HEIGHT),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Visible = false,
		Parent = holder,
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

	-- What to do, over the controls until the first roll.
	local hint = UIKit.Label({
		Name = "Hint",
		Text = if touch then "DRAG BACK & LET GO\nor tap ROLL" else "DRAG BACK & LET GO\nor press ROLL (Space)",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		Position = UDim2.fromOffset(-15, 0),
		Size = UDim2.fromOffset(330, 74),
		Visible = false,
		Parent = holder,
		Children = { UIKit.TextStroke(0.1) },
	})
	hint:SetAttribute("PP_Lines", 2)
	ui.Hint = hint

	-- DONE: on phones top right, beside the menu column (one scaled holder with room for the
	-- column, so the gap stays the same on every screen); on PC bottom left.
	local doneHolder = UIKit.new("Frame", {
		Name = "SkeeBallDone",
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(0, 1),
		Position = if touch then UDim2.new(1, -8, 0, 6) else UDim2.new(0, 16, 1, -24),
		Size = UDim2.fromOffset(
			if touch then 150 + 12 + Theme.Touch.Target + 20 else 150,
			if touch then Theme.Touch.Target else 64
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
		Size = UDim2.fromOffset(150, if touch then Theme.Touch.Target else 64),
		CornerRadius = 22,
		Parent = doneHolder,
	}, leave, Theme.Colors.Pink, Color3.fromRGB(200, 50, 140))
	ui.SkeeBallDone = doneHolder

	-- The score pop for each ball (clear of the MOVE stick's corner on phones).
	local pop = UIKit.Label({
		Name = "SkeeBallPop",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 70,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(if touch then 0.62 else 0.5, 0.4),
		Size = UDim2.fromOffset(360, 110),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0) },
	})
	UIKit.AutoScale(pop)
	ui.Pop = pop

	-- The end of a game: final score, best, today's place, PLAY AGAIN / DONE.
	local over = UIKit.new("Frame", {
		Name = "SkeeBallOver",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(if touch then 0.62 else 0.5, 0.48),
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
		if existing then
			existing.Confirmed = true
			return
		end
		if mine then
			if play.Rolled >= ball then
				return -- this device's roll that already finished
			end
			play.Rolled = ball -- the server took a roll this device had given up on: catch up
			showWaiting(machine)
			refreshControls()
		end
		local camera = workspace.CurrentCamera
		if (camera.CFrame.Position - machine.Frame.Position).Magnitude > ANIMATE_RANGE then
			return
		end
		local rolled = startRoll(machine, SkeeBall.Path(aimQ, powerQ, ball), ball, false)
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
	roll(aim, power)
	return true
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

	local lastLights, lastScreens = 0, 0
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for _, machine in machines do
			stepRolls(machine, now)
		end
		if play.Active then
			if play.Meter ~= "Idle" then
				meterValues(now)
			end
			-- Walking away (the MOVE stick, WASD) ends the game.
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

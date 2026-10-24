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
-- SYNC. The sound reaches a player a little after the clock says (Bluetooth speakers can add 200 ms), so
-- notes can look early to the ear. The - and + under the meters shift the picture and the taps' time by 25 ms
-- a step (up to 300 ms) until the notes land on the beat; the setting is kept for the rest of the visit.
-- If the round's song isn't playing (it hasn't loaded, or isn't uploaded) a quiet tick keeps the beat.
--
-- The meters: GROOVE (the server's number for this dancer, with a tick where the cut line is: whoever is
-- left of it is in DANGER), the place among the dancers still on the floor, and the next cut (when, how
-- many fall). Dancers about to fall flash red on their tiles for a third of a second before the drop.
-- Anyone watching (cut, or sitting out) sees the standings instead of the highway.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Chart = require(ReplicatedStorage.Shared.LastDancerChart)
local GameState = require(ReplicatedStorage.Shared.GameState)
local Logic = require(ReplicatedStorage.Shared.Logic.LastDancer)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local LastDancer = {}

local SYMBOLS = { "▲", "■", "●", "◆" }
local LANE_COLORS = {
	Color3.fromRGB(255, 96, 150),
	Color3.fromRGB(70, 200, 255),
	Color3.fromRGB(255, 205, 60),
	Color3.fromRGB(150, 235, 110),
}
local KEYS = { Enum.KeyCode.D, Enum.KeyCode.F, Enum.KeyCode.J, Enum.KeyCode.K }
local KEY_NAMES = { "D", "F", "J", "K" }
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

local SYNC_STEP = 0.025
local savedSync = 0 -- the player's sync setting, kept for the rest of the visit

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

local function percentText(groove: number): string
	return `{math.clamp(math.floor(groove + 0.5), 0, 100)}%`
end

function LastDancer.Start(api)
	api:Mood({
		Tint = Color3.fromRGB(255, 232, 255),
		Saturation = 0.2,
		Contrast = 0.08,
		Brightness = -0.03,
	})
	local waited = 0
	while (not api:Shared("Go") or not api:SharedJSON("Floor")) and waited < 10 do
		waited += task.wait(0.1)
	end
	local go = api:Shared("Go")
	local floor = api:SharedJSON("Floor")
	local arena = api:Arena(10)
	if type(go) ~= "number" or not floor or not arena then
		return
	end
	local touch = api:IsTouch()
	local effects = not State.ReducedEffects()
	local me = Players.LocalPlayer.UserId
	local notes = Chart.Notes

	local mine = Logic.new() -- this player's taps judged here, for the instant feedback
	local results: { [number]: string } = {} -- note index -> what happened to it
	local sync = savedSync

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
	local hud = api:TopHud()
	local y = api:HudY()
	local meter = UIKit.new("Frame", {
		Name = "GroovePanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(430, 62),
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
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.fromOffset(120, 24),
		Parent = meter,
		Children = { UIKit.TextStroke(0.2) },
	})
	local percent = UIKit.Label({
		Name = "Percent",
		Text = "60%",
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -170, 0, 2),
		Size = UDim2.fromOffset(70, 28),
		Parent = meter,
		Children = { UIKit.TextStroke(0.2) },
	})
	local place = UIKit.Label({
		Name = "Place",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -92, 0, 4),
		Size = UDim2.fromOffset(80, 26),
		Parent = meter,
		Children = { UIKit.TextStroke(0.2) },
	})
	local track = UIKit.new("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(14, 36),
		Size = UDim2.new(1, -28, 0, 16),
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
		Size = UDim2.new(0, 4, 1, 8),
		BackgroundColor3 = Theme.Colors.Red,
		Visible = false,
		ZIndex = 3,
		Parent = track,
		Children = { UIKit.Corner(2) },
	})

	local ticker = UIKit.Label({
		Name = "CutTicker",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y + 68),
		Size = UDim2.fromOffset(500, 32),
		Parent = hud,
		Children = { UIKit.TextStroke(0.15) },
	})
	local danger = UIKit.Label({
		Name = "Danger",
		Text = "DANGER! KEEP DANCING!",
		Font = Theme.Fonts.Display,
		TextSize = 24,
		TextColor3 = Theme.Colors.Red,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y + 100),
		Size = UDim2.fromOffset(500, 32),
		Visible = false,
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})
	local banner = UIKit.Label({
		Name = "Banner",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 30,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y + 136),
		Size = UDim2.fromOffset(560, 40),
		TextTransparency = 1,
		Parent = hud,
		Children = { UIKit.TextStroke(0.1) },
	})
	local function showBanner(text: string, color: Color3?)
		banner.Text = text
		banner.TextColor3 = color or Color3.new(1, 1, 1)
		banner.TextTransparency = 0
		UIKit.PopIn(banner, 0.25)
		local stamp = os.clock()
		banner:SetAttribute("Stamp", stamp)
		task.delay(2.6, function()
			if banner.Parent and banner:GetAttribute("Stamp") == stamp then
				UIKit.Tween(banner, 0.4, { TextTransparency = 1 })
			end
		end)
	end

	-- The sync setting.
	local syncLabel
	local function setSync(value: number)
		sync = math.clamp(math.floor(value / SYNC_STEP + 0.5) * SYNC_STEP, -Logic.SYNC_MAX, Logic.SYNC_MAX)
		savedSync = sync
		if syncLabel then
			syncLabel.Text = `SYNC {math.floor(sync * 1000 + 0.5)} ms`
		end
	end
	local syncRow = UIKit.new("Frame", {
		Name = "Sync",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y + 182),
		Size = UDim2.fromOffset(250, 40),
		BackgroundTransparency = 1,
		Parent = hud,
	})
	local function syncButton(text: string, x: number, delta: number)
		local button = UIKit.new("TextButton", {
			Name = "Sync" .. text,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, x, 0.5, 0),
			Size = UDim2.fromOffset(52, 36),
			BackgroundColor3 = Theme.Colors.PanelLight,
			BackgroundTransparency = 0.25,
			AutoButtonColor = true,
			Text = text,
			Font = Theme.Fonts.Display,
			TextSize = 26,
			TextColor3 = Color3.new(1, 1, 1),
			Parent = syncRow,
			Children = { UIKit.Corner(10), UIKit.Stroke(Color3.new(1, 1, 1), 2, 0.5) },
		})
		api:Track(button.Activated:Connect(function()
			setSync(sync + delta)
		end))
	end
	syncButton("−", 26, -SYNC_STEP)
	syncButton("+", 224, SYNC_STEP)
	syncLabel = UIKit.Label({
		Name = "SyncLabel",
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		Position = UDim2.fromOffset(54, 0),
		Size = UDim2.fromOffset(142, 40),
		Parent = syncRow,
		Children = { UIKit.TextStroke(0.3) },
	})
	setSync(sync)

	-- The highway ------------------------------------------------------------------------------------
	local holder = UIKit.new("Frame", {
		Name = "Highway",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(WIDTH, HIGHWAY_H + PAD_H + 8),
		BackgroundTransparency = 1,
		Parent = api.Gui,
	})
	UIKit.AutoScale(holder)
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
			Text = SYMBOLS[lane],
			Font = Theme.Fonts.Display,
			TextSize = 44,
			Size = UDim2.fromScale(1, if touch then 1 else 0.7),
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
	api:Track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local lane = table.find(KEYS, input.KeyCode)
		if lane then
			tap(lane)
		end
	end))

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
	local function myPad(): BasePart?
		local tile = arena:FindFirstChild("Tile_" .. me)
		return tile and tile:FindFirstChild("Pad") :: BasePart?
	end

	local function relNow(): number
		return api:Now() - go
	end

	function tap(lane: number)
		if not api:CanAct() or GameState.Get("Phase") ~= "InRound" then
			return
		end
		local now = api:Now()
		local rel = now - go - sync
		api:Action("Tap", lane, now - sync)
		if Logic.InWarmup(Chart, rel) then
			flashPad(lane, "Ok")
			return
		end
		local outcome = Logic.Tap(Chart, mine, lane, rel)
		if outcome.Index then
			results[outcome.Index] = outcome.Kind
			flashPad(lane, outcome.Kind)
			judge(outcome.Kind)
			playSound(api, "Click", 1.3 + lane * 0.1, 0.25)
			if effects and outcome.Kind == "Perfect" then
				local pad = myPad()
				if pad then
					api:Effect("Sparkles", pad.Position + Vector3.new(0, 2, 0), { LANE_COLORS[lane] })
				end
			end
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
				Text = "",
				Font = Theme.Fonts.Display,
				TextSize = 26,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 2,
				Parent = frame,
				Children = { UIKit.TextStroke(0.2) },
			})
		end
		local note = notes[index]
		frame.BackgroundColor3 = LANE_COLORS[note.Lane]
		frame.BackgroundTransparency = 0
		frame.Visible = true
		(frame:FindFirstChild("Glyph") :: TextLabel).Text = SYMBOLS[note.Lane]
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

	-- Who is about to fall, and the tiles' lights.
	local doomed: { [number]: boolean } = {}
	local tiles = {}
	for _, entry in floor.Tiles do
		local tile = arena:FindFirstChild("Tile_" .. entry.Id)
		local pad = tile and tile:FindFirstChild("Pad") :: BasePart?
		if pad then
			table.insert(tiles, { Id = entry.Id, Pad = pad, Color = pad.Color, Tile = tile })
		end
	end
	api:OnEvent("CutWarn", function(ids)
		for _, id in ids do
			doomed[id] = true
		end
		showBanner(
			`{namesOf(ids)} {if #ids == 1 and ids[1] ~= me then "is" else "are"} about to FALL!`,
			JUDGE_COLORS.Miss
		)
	end)
	api:OnEvent("Cut", function(ids)
		for _, id in ids do
			doomed[id] = nil
		end
		if #ids > 0 then
			showBanner(`{namesOf(ids)} fell through the floor!`, Color3.new(1, 1, 1))
			if effects then
				for _, id in ids do
					for _, t in tiles do
						if t.Id == id then
							api:Effect("Poof", t.Pad.Position, nil)
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
		local playing = api:CanAct()
		if not playing then
			updateStandings()
		end
		holder.Visible = playing
		syncRow.Visible = playing
		standings.Visible = not playing
		combo.Visible = playing
	end
	applyMode()
	api:OnCanAct(applyMode)
	refreshStandings = function()
		if not api:CanAct() then
			updateStandings()
		end
	end

	api:Hint("Tap the pad under each note when it lands on the line!", y + 226)
	task.delay(9, function()
		if api.Gui.Parent then
			api:Hint("", y + 226)
		end
	end)

	-- Every frame ---------------------------------------------------------------------------------------
	local scanStart = 1
	local displayed = 60
	api:RenderStep(function(dt)
		local rel = relNow()
		local chartRel = rel - sync -- the chart's time as this player hears it
		local phase = GameState.Get("Phase")

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
			if row[4] == 1 then
				place.Text = `#{Logic.Place(grooves, row[2])}/{#grooves}`
			else
				place.Text = "OUT"
			end
		end
		local cutAt = cut.At
		local cutLineValue = cutLine()
		line.Visible = cutLineValue ~= nil and row ~= nil and row[4] == 1
		if cutLineValue then
			line.Position = UDim2.fromScale(math.clamp(cutLineValue / 100, 0, 1), 0.5)
		end
		local inDanger = false
		if row and row[4] == 1 and cutLineValue and (cut.Count or 0) > 0 then
			inDanger = row[2] <= cutLineValue
		end
		danger.Visible = inDanger and phase == "InRound"
		meterStroke.Color = if inDanger
				and phase == "InRound"
				and math.floor(os.clock() * 4) % 2 == 0
			then Theme.Colors.Red
			else Color3.new(1, 1, 1)
		if phase ~= "InRound" then
			ticker.Text = "GET READY!"
		elseif cut.Final then
			ticker.Text = "FINAL DUEL! HIGHEST GROOVE WINS"
		elseif cutAt then
			local left = math.max(0, cutAt - api:Now())
			ticker.Text = `NEXT CUT IN {math.ceil(left)}s • {cut.Count or 0} FALL`
		else
			ticker.Text = ""
		end

		-- the tiles' lights: a pulse on every beat, red when about to fall
		local beat = chartRel / Logic.BEAT
		local pulse = math.max(0, 1 - (beat % 1) * 2.5) ^ 2
		local flash = math.floor(os.clock() * 8) % 2 == 0
		for _, t in tiles do
			if t.Tile.Parent then
				local target = t.Color:Lerp(Color3.new(1, 1, 1), 0.55 * pulse)
				if doomed[t.Id] then
					target = if flash then Color3.fromRGB(255, 40, 50) else Color3.fromRGB(90, 0, 10)
				end
				t.Pad.Color = target
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

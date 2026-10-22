-- Client half of Log Jam: draws every team's sawmill from the state the server shares ("Mill_<Team>"),
-- and gives this player the four shape buttons (▲ ■ ● ◆, each its own colour too) and a prompt card.
--
-- The mills: when a log is placed it flies from the rack and lands upright on the stump (the
-- server's BEAT); when it's chopped the big axe swings down on its hinge, the log splits into two
-- halves that tumble off the stump, chips fly, and the next log rolls down the rack. A jam rattles
-- the mill and puffs smoke. Every station animates the same way, bots' included; the server built
-- the models, and they're moved here, locally.
--
-- The card (under the round banner) says what to do: PLACE IT! or CHOP IT! with the big shape when
-- it's your turn, GET READY while your partner places, JAMMED! with a countdown after a wrong press.
-- The buttons only light up while your prompt is showing on your screen (a press before that would
-- be a guess, and the server jams a guess), so what you see is what counts. A press sends the shape,
-- the log number and the phase it answered, plus the synced time it was pressed (for the buzzer).
-- Phones get the buttons as a 2 x 2 pad beside the jump button (▲ ■ over ● ◆); PC a row with Q W E R.
-- Each player on turn gets a PLACE / CHOP tag over their head, and each mill's sign counts its logs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Teams = require(ReplicatedStorage.Shared.Teams)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local LogJam = {}

local SYMBOLS = { "▲", "■", "●", "◆" }
local SYMBOL_COLORS = {
	Color3.fromRGB(255, 92, 92),
	Color3.fromRGB(70, 150, 255),
	Color3.fromRGB(255, 196, 40),
	Color3.fromRGB(176, 104, 255),
}
local KEYS = { Enum.KeyCode.Q, Enum.KeyCode.W, Enum.KeyCode.E, Enum.KeyCode.R }
local SWING = 0.13 -- the axe's swing down (seconds)
local BITE_HOLD = 0.18 -- stuck in the stump
local RAISE = 0.35 -- back up
local HALF_FLIGHT = 0.55
local HALF_FADE = 0.3
local ROLL = 0.28 -- the next log rolling down the rack

type Mill = {
	Team: string,
	Frame: CFrame,
	Hinge: CFrame,
	Axe: Model?,
	AxeRel: CFrame,
	Log: Model?,
	LogRel: CFrame,
	LogParts: { BasePart },
	Halves: { { Model: Model, Rest: CFrame, Parts: { BasePart }, Side: number } },
	Label: TextLabel?,
	State: any,
	Seq: number,
	Phase: string,
	FlyAt: number?, -- the log's flight to the stump started (os.clock)
	ChopAt: number?,
	SplitDone: boolean,
	RollAt: number?,
	ShakeAt: number,
	LogUp: boolean,
}

local function vec(list: { number }): Vector3
	return Vector3.new(list[1], list[2], list[3])
end

local function partsOf(model: Instance): { BasePart }
	local list = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(list, part)
		end
	end
	return list
end

local function setTransparency(parts: { BasePart }, value: number)
	for _, part in parts do
		part.Transparency = value
	end
end

local function point(frame: CFrame, offset: Vector3): Vector3
	return frame.Position - frame.RightVector * offset.X + Vector3.yAxis * offset.Y + frame.LookVector * offset.Z
end

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) * (1 - t)
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

function LogJam.Start(api)
	api:Mood({ Tint = Color3.fromRGB(255, 246, 232), Saturation = 0.12, Contrast = 0.05 })
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
	local effects = not State.ReducedEffects()
	local rng = Random.new()
	local me = Players.LocalPlayer.UserId
	local beat: number = layout.Beat or 0.4
	local hingeOffset = vec(layout.Hinge)
	local logRest = vec(layout.LogRest)
	local logUp = vec(layout.LogUp)
	local axeRest = math.rad(layout.AxeRest or -70)
	local axeBite = math.rad(layout.AxeBite or 17.3)
	-- The axe's edge meets the log's top this far down its swing (see LogJam.py: hinge 5.2 up, edge
	-- 1.3 below the hinge and 4.6 out; the log's top is 4.66 up).
	local splitAngle = math.rad(-9.5)

	local mills = {} :: { [string]: Mill }
	local order = {} :: { string }
	for _, info in layout.Stations do
		local team = info.Team
		local position = vec(info.Pos)
		local look = Vector3.new(info.Look[1], 0, info.Look[2])
		local frame = CFrame.lookAt(position, position + look)
		local hinge = CFrame.fromMatrix(point(frame, hingeOffset), -frame.RightVector, Vector3.yAxis)
		local axe = arena:FindFirstChild("Axe_" .. team) :: Model?
		local log = arena:FindFirstChild("Log_" .. team) :: Model?
		local restFrame = CFrame.fromMatrix(point(frame, logRest), frame.RightVector, frame.LookVector)
		local halves = {}
		for index, side in { 1, -1 } do
			local half = arena:FindFirstChild(`Half_{team}_{index}`) :: Model?
			if half then
				table.insert(halves, { Model = half, Rest = half:GetPivot(), Parts = partsOf(half), Side = side })
			end
		end
		local stump = arena:FindFirstChild("Stump_" .. team)
		local labelGui = stump and stump:FindFirstChild("TeamLabel", true)
		local label = if labelGui and labelGui:IsA("BillboardGui")
			then labelGui:FindFirstChildWhichIsA("TextLabel", true)
			elseif labelGui and labelGui:IsA("TextLabel") then labelGui
			else nil
		mills[team] = {
			Team = team,
			Frame = frame,
			Hinge = hinge,
			Axe = axe,
			AxeRel = if axe
				then (hinge * CFrame.Angles(0, 0, axeRest)):ToObjectSpace(axe:GetPivot())
				else CFrame.identity,
			Log = log,
			LogRel = if log then restFrame:ToObjectSpace(log:GetPivot()) else CFrame.identity,
			LogParts = if log then partsOf(log) else {},
			Halves = halves,
			Label = label,
			State = nil,
			Seq = 0,
			Phase = "Wait",
			FlyAt = nil,
			ChopAt = nil,
			SplitDone = true,
			RollAt = nil,
			ShakeAt = -math.huge,
			LogUp = false,
		}
		table.insert(order, team)
	end
	local function myTeam(): string?
		local team = Players.LocalPlayer:GetAttribute("PP_Team")
		return if type(team) == "string" and mills[team] then team else nil
	end

	-- Log poses: on the rack (lying), standing on the stump, or somewhere on the flight between.
	local function restPose(mill: Mill): CFrame
		return CFrame.fromMatrix(point(mill.Frame, logRest), mill.Frame.RightVector, mill.Frame.LookVector)
	end
	local function upPose(mill: Mill): CFrame
		return CFrame.fromMatrix(point(mill.Frame, logUp), mill.Frame.RightVector, Vector3.yAxis)
	end

	-- The chips that fly off a chop (and the smoke of a jam).
	local function chips(at: Vector3, count: number)
		for _ = 1, count do
			local chip = Instance.new("Part")
			chip.Name = "Chip"
			chip.Size = Vector3.new(rng:NextNumber(0.25, 0.5), 0.1, rng:NextNumber(0.15, 0.3))
			chip.Color = Color3.fromRGB(226, 186, 128):Lerp(Color3.fromRGB(150, 104, 62), rng:NextNumber(0, 0.6))
			chip.Material = Enum.Material.Wood
			chip.CanCollide = false
			chip.CanQuery = false
			chip.CanTouch = false
			chip.CastShadow = false
			chip.CFrame = CFrame.new(at + rng:NextUnitVector() * 0.3)
				* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
			chip.AssemblyLinearVelocity = rng:NextUnitVector() * rng:NextNumber(8, 16) + Vector3.new(0, 14, 0)
			chip.AssemblyAngularVelocity = rng:NextUnitVector() * 14
			chip.Parent = api.World
			task.delay(1.4, function()
				chip:Destroy()
			end)
		end
	end

	-- A floating word over a mill.
	local function float(mill: Mill, text: string, color: Color3)
		local anchor = Instance.new("Part")
		anchor.Name = "WordAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		anchor.CFrame = CFrame.new(point(mill.Frame, Vector3.new(0, 6, 0)))
		anchor.Parent = api.World
		local gui = Instance.new("BillboardGui")
		gui.Adornee = anchor
		gui.Size = UDim2.fromOffset(220, 54)
		gui.MaxDistance = 120
		gui.LightInfluence = 0
		gui.AlwaysOnTop = true
		gui.Parent = anchor
		local label = UIKit.Label({
			Text = text,
			Font = Theme.Fonts.Display,
			TextSize = 36,
			TextColor3 = color,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
			Children = { UIKit.TextStroke(0) },
		})
		UIKit.Tween(gui, 0.8, { StudsOffset = Vector3.new(0, 2.5, 0) })
		UIKit.Tween(label, 0.8, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.85, function()
			anchor:Destroy()
		end)
	end

	-- HUD: the prompt card under the banner.
	local hud = api:TopHud()
	local touch = api:IsTouch()
	local y = api:HudY()
	local card = UIKit.new("Frame", {
		Name = "PromptCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(if touch then 340 else 300, 150),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = hud,
		Children = { UIKit.Corner(18), UIKit.Stroke(Color3.new(1, 1, 1), 3, 0.2) },
	})
	local title = UIKit.Label({
		Name = "Title",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = if touch then 30 else 26,
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 34),
		Parent = card,
		Children = { UIKit.TextStroke(0.2) },
	})
	local badge = UIKit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 42),
		Size = UDim2.fromOffset(96, 96),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
		Children = { UIKit.Corner(22), UIKit.Stroke(Color3.new(1, 1, 1), 4, 0) },
	})
	local glyph = UIKit.Label({
		Name = "Glyph",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 70,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
		Children = { UIKit.TextStroke(0.1) },
	})
	local jamBar = UIKit.new("Frame", {
		Name = "JamBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(0.8, 0, 0, 12),
		BackgroundColor3 = Color3.fromRGB(255, 80, 80),
		Visible = false,
		Parent = card,
		Children = { UIKit.Round() },
	})
	local badgeScale = UIKit.new("UIScale", { Parent = badge })

	-- The four buttons.
	local buttons = {}
	local function placeButtons()
		for index in buttons do
			local holder = api.Gui:FindFirstChild("Action_" .. SYMBOLS[index]) :: Frame?
			if not holder then
				continue
			end
			local inner = holder:FindFirstChild("Button") :: GuiObject?
			if touch then
				-- Slots 1-2 are the bottom row (beside the jump button); ▲ ■ sit right above ● ◆.
				if inner then
					inner.Position = if index <= 2 then UDim2.new(0, 0, -1, -12) else UDim2.new()
				end
			else
				local scale = holder:FindFirstChildOfClass("UIScale")
				local step = 132 * (if scale then scale.Scale else 1)
				holder.Position = UDim2.new(0.5, (index - 2.5) * step + 59 * (if scale then scale.Scale else 1), 1, -24)
			end
		end
	end
	local touchSlots = { 2, 1, 2, 1 } -- ▲ ■ (top row, raised) and ● ◆ (bottom row)
	local live = {
		Seq = -1,
		Phase = "",
		Enabled = false,
	}
	local function press(index: number)
		local team = myTeam()
		local mill = team and mills[team]
		local state = mill and mill.State
		if not state or not live.Enabled then
			return
		end
		api:Action("Press", index, state.Seq, state.Phase, api:Now())
		playSound(api, "Click", 1.1, 0.5)
	end
	if myTeam() then
		for index, symbol in SYMBOLS do
			local button = api:Button({
				Text = symbol,
				Key = KEYS[index],
				Color = SYMBOL_COLORS[index],
				Slot = if touch then touchSlots[index] else 1,
			})
			button.Pressed:Connect(function()
				press(index)
			end)
			button:SetEnabled(false)
			buttons[index] = button
		end
		placeButtons()
		task.delay(1.2, placeButtons) -- after the touch controls exist (the buttons re-place then)
		api:Track(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(placeButtons)
		end))
	end
	local function enableButtons(on: boolean)
		if live.Enabled == on then
			return
		end
		live.Enabled = on
		for _, button in buttons do
			button:SetEnabled(on)
		end
	end

	-- PLACE / CHOP tags over the heads of whoever is on turn at each mill.
	local tags = {} :: { [number]: BillboardGui }
	local function tag(userId: number, text: string?)
		local gui = tags[userId]
		local character = api:CharacterOf(userId)
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if not text or not head then
			if gui then
				gui.Enabled = false
			end
			return
		end
		if not gui or gui.Adornee ~= head then
			if gui then
				gui:Destroy()
			end
			local made = Instance.new("BillboardGui")
			made.Name = "RoleTag"
			made.Adornee = head
			made.Size = UDim2.fromOffset(110, 36)
			made.StudsOffset = Vector3.new(0, 3.2, 0)
			made.MaxDistance = 90
			made.LightInfluence = 0
			made.Parent = api.World
			UIKit.Label({
				Name = "Text",
				Text = "",
				Font = Theme.Fonts.Display,
				TextSize = 28,
				Size = UDim2.fromScale(1, 1),
				Parent = made,
				Children = { UIKit.TextStroke(0) },
			})
			tags[userId] = made
			gui = made
		end
		local holder = gui :: BillboardGui
		holder.Enabled = true
		local label = holder:FindFirstChild("Text") :: TextLabel?
		if label then
			label.Text = text
			label.TextColor3 = if text == "CHOP" then Color3.fromRGB(255, 170, 70) else Color3.new(1, 1, 1)
		end
	end
	local function refreshTags()
		local wanted = {} :: { [number]: string }
		for _, team in order do
			local state = mills[team].State
			if state and (state.Phase == "Place" or state.Phase == "Chop") then
				if state.Phase == "Place" and state.Placer ~= 0 then
					wanted[state.Placer] = "PLACE"
				end
				if state.Chopper ~= 0 and wanted[state.Chopper] == nil then
					wanted[state.Chopper] = "CHOP"
				end
			end
		end
		for userId in tags do
			if not wanted[userId] then
				tag(userId, nil)
			end
		end
		for userId, text in wanted do
			tag(userId, text)
		end
	end

	-- A mill's new state: start whatever animation the change calls for.
	local function onMill(team: string, state: any)
		local mill = mills[team]
		if not mill or type(state) ~= "table" then
			return
		end
		local mine = team == myTeam()
		local previous = mill.Phase
		local now = os.clock()
		mill.State = state
		if state.Seq ~= mill.Seq or state.Phase ~= previous then
			if state.Phase == "Chop" and previous == "Place" and state.Seq == mill.Seq then
				mill.FlyAt = now
				if mine then
					playSound(api, "ReturnToLobby", 1.2, 0.5)
				end
			elseif state.Phase == "Split" then
				mill.FlyAt = nil
				mill.LogUp = true
				mill.ChopAt = now
				mill.SplitDone = false
			elseif state.Phase == "Place" and state.Seq ~= mill.Seq then
				mill.FlyAt = nil
				mill.LogUp = false
				if mill.Seq > 0 then
					mill.RollAt = now
				end
			elseif state.Phase == "Chop" then
				-- Joined mid-way: the log is already on the stump.
				mill.LogUp = true
			end
			mill.Seq = state.Seq
			mill.Phase = state.Phase
		end
		if mill.Label then
			mill.Label.Text = `{string.upper(team)} MILL • {state.Logs or 0}`
		end
		refreshTags()
	end
	for _, team in order do
		onMill(team, api:SharedJSON("Mill_" .. team))
		api:OnShared("Mill_" .. team, function()
			onMill(team, api:SharedJSON("Mill_" .. team))
		end)
	end

	api:OnEvent("Jam", function(team, userId)
		local mill = mills[team]
		if not mill then
			return
		end
		mill.ShakeAt = os.clock()
		local at = point(mill.Frame, if mill.LogUp then logUp else logRest)
		api:Effect("Poof", at + Vector3.new(0, 1, 0))
		if team == myTeam() then
			playSound(api, "HazardWarning", 0.7, 0.8)
			float(mill, "✕ JAMMED!", Color3.fromRGB(255, 90, 90))
			if userId == me then
				UIKit.PopIn(card, 0.25)
			end
		end
	end)

	-- The card: what this player should do right now.
	local function showCard(text: string, symbol: number?, dim: boolean, color: Color3?)
		card.Visible = true
		title.Text = text
		title.TextColor3 = color or Color3.new(1, 1, 1)
		if symbol and SYMBOLS[symbol] then
			badge.Visible = true
			glyph.Text = SYMBOLS[symbol]
			badge.BackgroundColor3 = SYMBOL_COLORS[symbol]
			badge.BackgroundTransparency = if dim then 0.6 else 0
			glyph.TextTransparency = if dim then 0.5 else 0
		elseif symbol == 0 then
			badge.Visible = true
			glyph.Text = "?"
			badge.BackgroundColor3 = Theme.Colors.PanelDark
			badge.BackgroundTransparency = 0.3
			glyph.TextTransparency = 0.2
		else
			badge.Visible = false
		end
	end
	local lastPrompt = ""
	local hintUntil = math.huge
	local started = false
	local function updateCard(nowServer: number)
		local team = myTeam()
		local mill = team and mills[team]
		local state = mill and mill.State
		local inRound = GameState.Get("Phase") == "InRound" and api:CanAct()
		if not state or not inRound or state.Phase == "Done" or state.Phase == "Gone" or state.Phase == "Wait" then
			card.Visible = false
			enableButtons(false)
			return
		end
		if not started then
			started = true
			api:Hint("Press the shape on your card when it's your turn!", y + 160)
			hintUntil = os.clock() + 6
		end
		local jammed = nowServer < (state.JamUntil or 0)
		local placing = state.Phase == "Place" and state.Placer == me
		local chopping = state.Phase == "Chop" and state.Chopper == me
		local shown = nowServer >= (state.ShowAt or 0)
		local myTurn = (placing or chopping) and shown and not jammed
		enableButtons(myTurn)
		jamBar.Visible = jammed
		if jammed then
			local left = math.clamp((state.JamUntil - nowServer) / (layout.Jam or 1.1), 0, 1)
			jamBar.Size = UDim2.new(0.8 * left, 0, 0, 12)
			showCard("✕ JAMMED!", nil, false, Color3.fromRGB(255, 100, 100))
			return
		end
		local prompt = ""
		if myTurn then
			showCard(if placing then "PLACE IT!" else "CHOP IT!", state.Symbol, false, Theme.Colors.Yellow)
			prompt = `{state.Seq}{state.Phase}`
		elseif placing or chopping then
			showCard("GET READY…", 0, true)
		elseif state.Phase == "Place" and state.Chopper == me then
			showCard("GET READY TO CHOP", 0, true)
		elseif state.Phase == "Split" then
			showCard("CHOPPED! +1", nil, false, Color3.fromRGB(120, 230, 120))
		elseif state.Phase == "Chop" and state.Placer == me then
			showCard("PARTNER CHOPS…", state.Symbol, true)
		else
			showCard("WAIT FOR YOUR TURN", nil, false, Color3.fromRGB(210, 210, 220))
		end
		if prompt ~= "" and prompt ~= lastPrompt then
			lastPrompt = prompt
			badgeScale.Scale = 1.35
			UIKit.Tween(badgeScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
			playSound(api, "Pickup", 1.3, 0.45)
		end
		if os.clock() > hintUntil then
			hintUntil = math.huge
			api:Hint("")
		end
	end

	local winnerShown = false
	api:OnShared("Winner", function(team)
		local mill = type(team) == "string" and mills[team]
		if mill and not winnerShown then
			winnerShown = true
			local at = point(mill.Frame, Vector3.new(0, 6, 0))
			api:Effect("Confetti", at, { Teams.Colors[team] or Color3.new(1, 1, 1), Theme.Colors.Yellow })
			if team == myTeam() then
				api:Sound("Victory")
			end
		end
	end)

	-- Every frame: the logs, axes and halves.
	local tagClock = 0
	api:RenderStep(function(dt)
		local now = os.clock()
		updateCard(api:Now())
		for _, team in order do
			local mill = mills[team]
			local mine = team == myTeam()
			local shake = 0
			if now - mill.ShakeAt < 0.45 and effects then
				shake = math.sin((now - mill.ShakeAt) * 60) * 0.12 * (1 - (now - mill.ShakeAt) / 0.45)
			end
			-- The log.
			local log = mill.Log
			if log then
				local pose: CFrame
				if mill.FlyAt then
					local t = math.clamp((now - mill.FlyAt) / beat, 0, 1)
					local from, to = restPose(mill), upPose(mill)
					local position = from.Position:Lerp(to.Position, t) + Vector3.new(0, math.sin(t * math.pi) * 2.4, 0)
					pose = from:Lerp(to, ease(t)) - from:Lerp(to, ease(t)).Position + position
					if t >= 1 then
						mill.FlyAt = nil
						mill.LogUp = true
						if mine then
							playSound(api, "Boing", 0.6, 0.45)
						end
					end
				elseif mill.LogUp then
					pose = upPose(mill)
				else
					pose = restPose(mill)
					if mill.RollAt then
						local t = math.clamp((now - mill.RollAt) / ROLL, 0, 1)
						-- Rolls down off the pile: from up the rack, turning as it goes.
						local back = (1 - ease(t)) * 1.7
						pose = pose + mill.Frame.RightVector * back + Vector3.new(0, back * 0.3, 0)
						pose = pose * CFrame.Angles(0, -back / 0.88, 0)
						if t >= 1 then
							mill.RollAt = nil
						end
					end
				end
				if shake ~= 0 then
					pose = pose + mill.Frame.RightVector * shake
				end
				local hidden = mill.LogUp and mill.ChopAt ~= nil and mill.SplitDone
				log:PivotTo(pose * mill.LogRel)
				local transparency = if hidden or mill.Phase == "Gone" then 1 else 0
				if mill.LogParts[1] and mill.LogParts[1].Transparency ~= transparency then
					setTransparency(mill.LogParts, transparency)
				end
			end
			-- The axe: resting up, or the chop (swing down, bite, rise).
			local axe = mill.Axe
			local angle = axeRest
			if mill.ChopAt then
				local t = now - mill.ChopAt
				if t < SWING then
					angle = axeRest + (axeBite - axeRest) * (t / SWING) ^ 2
				elseif t < SWING + BITE_HOLD then
					angle = axeBite
				elseif t < SWING + BITE_HOLD + RAISE then
					angle = axeBite + (axeRest - axeBite) * ease((t - SWING - BITE_HOLD) / RAISE)
				end
				if not mill.SplitDone and angle >= splitAngle then
					-- The edge meets the log: it splits.
					mill.SplitDone = true
					local at = point(mill.Frame, logUp + Vector3.new(0, 1.1, 0))
					chips(at, if effects then 12 else 4)
					if mine then
						playSound(api, "Hit", 0.8 + rng:NextNumber(0, 0.15), 0.9)
						float(mill, "+1", Color3.fromRGB(120, 230, 120))
					end
					for _, half in mill.Halves do
						setTransparency(half.Parts, 0)
					end
				end
				-- The halves tumble off the stump and fade.
				local since = t - SWING
				for _, half in mill.Halves do
					if since < 0 then
						continue
					end
					local u = math.clamp(since / HALF_FLIGHT, 0, 1)
					local out = mill.Frame.LookVector * half.Side * (2.2 * ease(u))
					local drop = Vector3.new(0, 1.6 * math.sin(u * math.pi) * 0.6 - 2.9 * u * u, 0)
					local tip = CFrame.fromAxisAngle(-mill.Frame.RightVector * half.Side, math.rad(85) * ease(u))
					local pivot = half.Rest.Position
					half.Model:PivotTo(CFrame.new(pivot + out + drop) * tip * (half.Rest - pivot))
					if since > HALF_FLIGHT then
						local fade = math.clamp((since - HALF_FLIGHT) / HALF_FADE, 0, 1)
						setTransparency(half.Parts, fade)
					end
				end
				if t > SWING + math.max(BITE_HOLD + RAISE, HALF_FLIGHT + HALF_FADE) then
					mill.ChopAt = nil
					mill.LogUp = false
					for _, half in mill.Halves do
						setTransparency(half.Parts, 1)
						half.Model:PivotTo(half.Rest)
					end
				end
			end
			if axe then
				axe:PivotTo(mill.Hinge * CFrame.Angles(0, 0, angle + shake * 0.3) * mill.AxeRel)
			end
		end
		tagClock += dt
		if tagClock > 1 then
			tagClock = 0
			refreshTags()
		end
	end)
end

return LogJam

-- The limited-time event and double coins weekends on screen (owner, asked what keeps players coming
-- back, then: "Can you work on all of that? this wont mess with what the other workers are working
-- on right?"; the idea they were offered: "a Halloween event: candy, free limited rewards like a
-- pumpkin hat, a banner with a countdown, lobby decorations and lighting; and double coins
-- weekends"). The server decides all of it (Services/EventService: GameState "Event" says what's
-- on, the profile's Events field holds the candy); this only shows it and asks.
--
--   * The chip, first in the lobby's row (UI/LobbyRibbon, priority 1): "🎃 HALLOWEEN · 9D" (PC
--     adds the candy), and "🎃 2× COINS · 1D 4H" on one of the event's double coins weekends (there
--     are none outside an event; owner, on double coins after Halloween: "NO"). A red "!" when a
--     reward is ready to claim.
--     After a round, the candy it paid pops on the chip ("+2 🍬 CANDY") once the player is back in
--     the lobby: never on the results card, and never a toast (the end of a round has enough).
--   * The event screen (tap the chip, or a locked event reward in the Shop): the candy, the track of
--     free rewards with CLAIM and EQUIP, the time left, and where to find candy. Phones first: it
--     fits the shortest phone window, 44 pt buttons, 18-unit text.
--   * The pumpkin hunt: the golden pumpkins this player found today disappear on their screen only
--     (World/EventDecor tags them PP_EventPumpkin; like the daily secret token).
--   * The lobby's light for the event (Shared/Events' Look: dusk colours, purple shadows) is set on
--     this device only, and only while the camera is at the lobby: Lighting is the whole world's,
--     so the arenas keep their own (modes set their mood on the device too: Kit/Api's Mood, Fire
--     Rope's clock). Only its own colour correction and two Lighting values nothing else touches
--     (OutdoorAmbient, ColorShift_Top), put back exactly when it's off.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Cosmetics)
local EventLogic = require(Shared.Logic.EventLogic)
local Events = require(Shared.Events)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.Parent.State)
local HubTabs = require(script.Parent.Parent.UI.HubTabs)
local LobbyRibbon = require(script.Parent.Parent.UI.LobbyRibbon)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local EventController = {}

local LOBBY = { Waiting = true, Intermission = true, Voting = true, Cleanup = true }
local ORANGE_DARK = Color3.fromRGB(205, 92, 24)
local PURPLE = Color3.fromRGB(120, 70, 200)
local GREEN_DARK = Color3.fromRGB(60, 160, 90)
local CYAN_DARK = Color3.fromRGB(50, 120, 230)
local POP_TIME = 3 -- seconds the "+2 🍬 CANDY" stays on the chip
local LOBBY_REACH = 600 -- studs from the lobby's middle: the camera is at the lobby (arenas are 1400 away)

local touch = false
local current: EventLogic.State? = nil -- what's on (GameState "Event")
local chip: LobbyRibbon.Chip? = nil
local badge: Frame? = nil
local modal: Modal.Modal? = nil
local body: Frame? = nil
local lastCandy: number? = nil
local pendingCandy = 0 -- candy from a round, popped on the chip back in the lobby
local popUntil = 0
local justClaimed: string? = nil -- the reward just asked for: its card pops when the server says yes
local ticking: { [TextLabel]: () -> string } = {} -- the open screen's countdowns, and their words

-- What's on --------------------------------------------------------------------------------------

local function event(): Events.Event?
	return if current and current.Id ~= "" then Events.Get(current.Id) else nil
end

local function progress(): EventLogic.Progress?
	local definition = event()
	local profile = State.Profile
	local events = profile and profile.Events
	local saved = definition and type(events) == "table" and events[definition.Id]
	return if type(saved) == "table" then EventLogic.Progress(table.clone(saved)) else nil
end

local function candy(): number
	local mine = progress()
	return if mine then mine.Candy else 0
end

local function timeLeft(endsAt: number): string
	return EventLogic.Countdown(endsAt - workspace:GetServerTimeNow())
end

-- The chip -----------------------------------------------------------------------------------------

local function claimable(): boolean
	local definition, mine = event(), progress()
	return definition ~= nil and mine ~= nil and #EventLogic.Claimable(mine, definition.Track) > 0
end

local function refreshChip()
	-- The season hub's event tab, there while an event is on, with the chip's "!".
	local definition = event()
	HubTabs.SetEvent(if definition then definition.Icon else nil, if definition then definition.Short else nil)
	HubTabs.SetBadge("Event", definition ~= nil and claimable())
	local ribbonChip = chip
	if not ribbonChip or os.clock() < popUntil then
		return
	end
	local state = current
	if badge then
		badge.Visible = claimable()
	end
	if state and definition and state.DoubleCoins then
		ribbonChip:Set(definition.Icon, `2× COINS · {timeLeft(state.DoubleEndsAt)}`)
	elseif state and definition then
		local words = `{definition.Short} · {timeLeft(state.EndsAt)}`
		-- PC has the room for the candy too; phones keep the row for the other chips.
		ribbonChip:Set(definition.Icon, if touch then words else `{words} · 🍬 {candy()}`)
	else
		ribbonChip:Set("", "") -- nothing on: off the row
	end
end

-- Whether the chip is on screen now (the row shows it, and the row is up).
local function chipShowing(): boolean
	local button = chip and chip.Button
	local row = button and button.Parent
	return button ~= nil and button.Visible and row ~= nil and row:IsA("GuiObject") and row.Visible
end

-- The candy a round paid, popped on the chip once it's back on screen in the lobby.
local function popCandy()
	local ribbonChip = chip
	if pendingCandy <= 0 or not ribbonChip or not chipShowing() then
		return
	end
	local amount = pendingCandy
	pendingCandy = 0
	ribbonChip:Set("🍬", `+{amount} CANDY`)
	popUntil = os.clock() + POP_TIME
	UIKit.PopIn(ribbonChip.Button, 0.45)
	task.delay(POP_TIME + 0.05, refreshChip)
end

local function buildChip(context)
	chip = LobbyRibbon.Add(context, {
		Name = "Event",
		Priority = 1,
		OnClick = function()
			if event() then
				State.OpenScreen:Fire("Event")
			end
		end,
		Top = Theme.Colors.Orange,
		Bottom = ORANGE_DARK,
	})
	local button = (chip :: LobbyRibbon.Chip).Button
	-- A reward ready to claim: a red "!" on the chip's corner, gently pulsing.
	local dot = UIKit.new("Frame", {
		Name = "Ready",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Theme.Colors.Red,
		Visible = false,
		ZIndex = 3,
		Parent = button,
		Children = { UIKit.Round(), UIKit.Stroke(nil, 2, 0.1) },
	})
	UIKit.Label({
		Text = "!",
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = dot,
	})
	local pulse = UIKit.new("UIScale", { Parent = dot })
	TweenService
		:Create(
			pulse,
			TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.18 }
		)
		:Play()
	badge = dot
	-- Back in the lobby after a round: the chip comes back (a moment after the phase turns), and
	-- shows what the round paid.
	button:GetPropertyChangedSignal("Visible"):Connect(popCandy)
	local row = button.Parent
	if row and row:IsA("GuiObject") then
		row:GetPropertyChangedSignal("Visible"):Connect(popCandy)
	end
end

-- The event screen -----------------------------------------------------------------------------------

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- A note where a button would be (same place and size).
local function note(props: { [string]: any }): TextLabel
	props.CornerRadius = nil
	props.Font = Theme.Fonts.Display
	props.TextWrapped = false
	return UIKit.Label(props)
end

-- One step of the track: what it gives, the candy it takes, and CLAIM / EQUIP / how much more.
local function stepCard(
	parent: Instance,
	order: number,
	step: EventLogic.Step,
	mine: EventLogic.Progress,
	size: Vector2,
	medal: boolean -- the track's last step, which also gives the event's medal
)
	local item = Cosmetics.Get(step.Reward)
	if not item then
		return
	end
	local profile = State.Profile
	local claimed = mine.Claimed[step.Reward] == true
	local ready = not claimed and mine.Candy >= step.Candy
	local card = UIKit.Panel({
		Name = step.Reward,
		Size = UDim2.fromOffset(size.X, size.Y),
		LayoutOrder = order,
		CornerRadius = 18,
		Parent = parent,
	}, if claimed or ready then Theme.Colors.Card else Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	if ready then
		local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = Theme.Colors.Yellow
		stroke.Thickness = 4
		stroke.Transparency = 0
	elseif claimed and justClaimed == step.Reward then
		justClaimed = nil
		UIKit.PopIn(card, 0.5) -- it's theirs: the card pops, with EQUIP on it
	end
	-- The candy it takes, on a ribbon (with the medal on the last one).
	local ribbon = UIKit.new("Frame", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 0, if touch then 30 else 34),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
		Children = { UIKit.Round(), UIKit.Gradient(Theme.Colors.Orange, PURPLE, 0) },
	})
	UIKit.Label({
		Text = if medal then `🍬 {step.Candy} + 🏅` else `🍬 {step.Candy}`,
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = ribbon,
		Children = { UIKit.TextStroke(0.15) },
	})
	local iconTop = if touch then 40 else 50
	local iconHeight = if touch then 42 else 56
	UIKit.Label({
		Text = item.Icon,
		TextSize = if touch then 36 else 46,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, iconTop),
		Size = UDim2.new(1, 0, 0, iconHeight),
		Parent = card,
	})
	local nameTop = iconTop + iconHeight
	UIKit.Label({
		Text = item.Name,
		Font = Theme.Fonts.Display,
		TextSize = 20,
		TextWrapped = false,
		Position = UDim2.fromOffset(6, nameTop),
		Size = UDim2.new(1, -12, 0, 24),
		Parent = card,
		Children = { UIKit.TextStroke(0.3) },
	})
	UIKit.Label({
		Text = string.upper(Cosmetics.SlotNames[item.Slot] or item.Slot),
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(6, nameTop + 24),
		Size = UDim2.new(1, -12, 0, 22),
		Parent = card,
	})
	if not touch then
		UIKit.Label({
			Text = item.Description,
			TextSize = 16,
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(8, nameTop + 48),
			Size = UDim2.new(1, -16, 0, 44),
			Parent = card,
		})
	end

	local props: { [string]: any } = {
		Name = "Action",
		TextSize = 20,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -16, 0, if touch then Theme.Touch.Target else 48),
		CornerRadius = 14,
		Parent = card,
	}
	if claimed and Cosmetics.IsEquipSlot(item.Slot) then
		local equipped = profile ~= nil and profile.Equipped[item.Slot] == item.Id
		props.Text = if equipped then "EQUIPPED ✓" else "EQUIP"
		UIKit.Button(props, function()
			Remotes.Get("ShopEquip"):FireServer(item.Slot, if equipped then "" else item.Id)
		end, if equipped then Theme.Colors.Green else Theme.Colors.Cyan, if equipped then GREEN_DARK else CYAN_DARK)
	elseif claimed then
		props.Text = "✓ IN EMOTES"
		props.TextColor3 = Theme.Colors.Green
		note(props)
	elseif ready then
		props.Text = "CLAIM!"
		props.TextSize = 24
		local button
		button = UIKit.Button(props, function()
			justClaimed = step.Reward
			Remotes.Get("EventAction"):FireServer("Claim", step.Reward)
			button.Text = "..."
			button.Active = false
		end, Theme.Colors.Yellow, Theme.Colors.Orange)
	else
		props.Text = `🔒 {step.Candy - mine.Candy} MORE`
		props.TextColor3 = Theme.Colors.TextDim
		note(props)
	end
end

local function render()
	local frame = body
	local window = modal
	if not frame or not window or not window.IsOpen then
		return
	end
	clear(frame)
	local definition, state = event(), current
	if not definition or not state then
		window:Close() -- the event just ended
		return
	end
	local mine = progress() or EventLogic.Progress({})
	local perDay = definition.Candy.PumpkinsPerDay
	local today = EventLogic.DayNumber(workspace:GetServerTimeNow())

	-- The candy, the time left (and a double coins weekend).
	local headerHeight = if touch then 56 else 60
	local header = UIKit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, headerHeight),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = frame,
	})
	local count = UIKit.Panel({
		Name = "Candy",
		Size = UDim2.fromOffset(230, headerHeight),
		CornerRadius = 18,
		Parent = header,
	}, Theme.Colors.Orange, ORANGE_DARK)
	UIKit.Label({
		Text = `🍬 {mine.Candy} CANDY`,
		Font = Theme.Fonts.Display,
		TextSize = 26,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = count,
		Children = { UIKit.TextStroke(0.1) },
	})
	local function endsIn(): string
		return `ENDS IN {timeLeft(state.EndsAt)}`
	end
	local ends = UIKit.Label({
		Text = endsIn(),
		Font = Theme.Fonts.Display,
		TextSize = 22,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 220, 1, 0),
		Parent = header,
		Children = { UIKit.TextStroke(0.2) },
	})
	table.clear(ticking)
	ticking[ends] = endsIn
	if state.DoubleCoins then
		local pill = UIKit.Panel({
			Name = "DoubleCoins",
			Position = UDim2.fromOffset(242, 0),
			Size = UDim2.new(1, -(242 + 232), 1, 0),
			CornerRadius = 18,
			Parent = header,
		}, Theme.Colors.Yellow, Theme.Colors.Orange)
		local function weekend(): string
			return `{Theme.CoinIcon} 2× COINS WEEKEND · {timeLeft(state.DoubleEndsAt)}`
		end
		local label = UIKit.Label({
			Text = weekend(),
			Font = Theme.Fonts.Display,
			TextSize = 20,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			Parent = pill,
			Children = { UIKit.TextStroke(0.2) },
		})
		ticking[label] = weekend
	end

	-- The track: one card a step, in order, every card in the window's width (940 units) side by side.
	local cardHeight = if touch then 212 else 270
	local steps = #definition.Track
	local cardSize = Vector2.new(math.min(176, math.floor((940 - 10 * (steps - 1)) / steps)), cardHeight)
	local track = UIKit.new("ScrollingFrame", {
		Name = "Track",
		Size = UDim2.new(1, 0, 0, cardHeight + 8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = if touch then 6 else 8,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		LayoutOrder = 2,
		Parent = frame,
		Children = {
			UIKit.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
		},
	})
	for order, step in definition.Track do
		stepCard(track, order, step, mine, cardSize, order == steps and definition.Medal ~= nil)
	end

	-- Where candy comes from (and the medal, once the track is done).
	local found = EventLogic.FoundToday(mine, today)
	local rounds =
		`🎮 Every round: +{definition.Candy.Played} 🍬 for playing, +{definition.Candy.TopHalf} more in the top half, +{definition.Candy.Win} more for a win.`
	if EventLogic.Complete(mine, definition.Track) then
		rounds = `🏅 Track complete: the {definition.Label} medal is yours!`
	end
	local hunt = if found >= perDay
		then `🎃 You found all {perDay} golden pumpkins today! New ones hide in the lobby tomorrow.`
		else `🎃 {perDay} golden pumpkins hide in the lobby every day: +{definition.Candy.Pumpkin} 🍬 each. {perDay - found} left today!`
	for index, text in { rounds, hunt } do
		UIKit.Label({
			Name = "Where" .. index,
			Text = text,
			TextSize = Theme.Touch.MinText,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = 2 + index,
			Parent = frame,
		})
	end
end

local function buildScreen(context)
	local definition = event()
	local window = Modal.new(
		context.Overlay,
		if definition then definition.Name else "EVENT",
		if definition then definition.Icon else "🎃",
		Vector2.new(980, 600) -- (the season hub's size: UI/HubTabs)
	)
	modal = window
	HubTabs.Attach(window, "Event")
	body = UIKit.new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = window.Content,
		Children = { UIKit.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left) },
	})
	window.Opened:Connect(render)
	window.Closed:Connect(function()
		if body then
			clear(body)
		end
	end)
end

-- The pumpkin hunt: today's finds disappear on this screen -------------------------------------------

local function foundHere(model: Instance): boolean
	local profile = State.Profile
	local events = profile and profile.Events
	local id = model:GetAttribute("Event")
	local saved = type(events) == "table" and type(id) == "string" and events[id]
	if type(saved) ~= "table" then
		return false
	end
	local mine = EventLogic.Progress(table.clone(saved))
	local day, spot = model:GetAttribute("Day"), model:GetAttribute("Spot")
	return type(day) == "number" and type(spot) == "number" and EventLogic.HasFound(mine, day, spot)
end

local function showPumpkin(model: Instance)
	local hidden = foundHere(model)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.LocalTransparencyModifier = if hidden then 1 else 0
		elseif item:IsA("ParticleEmitter") or item:IsA("Light") or item:IsA("BillboardGui") then
			item.Enabled = not hidden
		end
	end
end

local function watchPumpkins()
	local function track(model: Instance)
		showPumpkin(model)
		-- (Its Day and Event are set just after it's placed, and its pieces may arrive a moment later.)
		model:GetAttributeChangedSignal("Day"):Connect(function()
			showPumpkin(model)
		end)
		model:GetAttributeChangedSignal("Event"):Connect(function()
			showPumpkin(model)
		end)
		model.DescendantAdded:Connect(function()
			showPumpkin(model)
		end)
	end
	for _, model in CollectionService:GetTagged("PP_EventPumpkin") do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal("PP_EventPumpkin"):Connect(track)
	State.ProfileChanged:Connect(function()
		for _, model in CollectionService:GetTagged("PP_EventPumpkin") do
			showPumpkin(model)
		end
	end)
end

-- The lobby's look on this device -----------------------------------------------------------------------

local lookEffect: ColorCorrectionEffect? = nil
local saved: { OutdoorAmbient: Color3, ShiftTop: Color3 }? = nil

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function setLook(look: any?)
	if look and not lookEffect then
		saved = { OutdoorAmbient = Lighting.OutdoorAmbient, ShiftTop = Lighting.ColorShift_Top }
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "PP_EventLook"
		effect.TintColor = color(look.Tint)
		effect.Saturation = look.Saturation
		effect.Contrast = look.Contrast
		effect.Brightness = look.Brightness
		effect.Parent = Lighting
		lookEffect = effect
		Lighting.OutdoorAmbient = color(look.OutdoorAmbient)
		Lighting.ColorShift_Top = color(look.ShiftTop)
	elseif not look and lookEffect then
		lookEffect:Destroy()
		lookEffect = nil
		local before = saved
		if before then
			Lighting.OutdoorAmbient = before.OutdoorAmbient
			Lighting.ColorShift_Top = before.ShiftTop
		end
		saved = nil
	end
end

local function watchLook()
	local camera = workspace.CurrentCamera
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.25 then
			return
		end
		elapsed = 0
		local definition = event()
		local atLobby = camera ~= nil and camera.CFrame.Position.Magnitude < LOBBY_REACH
		setLook(if definition and definition.Look and atLobby then definition.Look else nil)
	end)
end

-- Start -----------------------------------------------------------------------------------------------

local function readState()
	local raw = GameState.Get("Event")
	local decoded = nil
	if type(raw) == "string" and raw ~= "" then
		local ok, value = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(value) == "table" and type(value.Id) == "string" then
			decoded = value
		end
	end
	current = decoded
	-- Candy counts from here: an event coming on (or a profile arriving before the event did) is
	-- never a "+31 CANDY" moment.
	lastCandy = if State.Profile then candy() else nil
	-- The window's title is the event's name (another event later gets its own).
	local definition = event()
	local titleBar = modal and modal.Window:FindFirstChild("TitleBar")
	local title = titleBar and titleBar:FindFirstChildOfClass("TextLabel")
	if title and definition then
		title.Text = `{definition.Icon}  {definition.Name}`
	end
	refreshChip()
	if modal and modal.IsOpen then
		render()
	end
end

function EventController.Start(context)
	touch = UIKit.IsTouch()
	readState()
	buildChip(context)
	buildScreen(context)
	GameState.Changed("Event", readState)
	refreshChip()

	State.OpenScreen:Connect(function(name)
		if name == "Event" and modal and event() then
			modal:Toggle()
		end
	end)
	State.ProfileChanged:Connect(function()
		local now = candy()
		if lastCandy and now > lastCandy then
			-- Candy from a round arrives with its results: it pops once the player is back in the
			-- lobby. A pumpkin found in the lobby pops right away (its toast says the rest).
			pendingCandy += now - lastCandy
			if LOBBY[GameState.Get("Phase") or "Waiting"] and not State.InRound() then
				popCandy()
			end
		end
		lastCandy = now
		refreshChip()
		if modal and modal.IsOpen then
			render()
		end
	end)
	GameState.Changed("Phase", function(phase)
		if LOBBY[phase] then
			task.delay(1.2, popCandy) -- after the row has come back
		end
	end)
	-- The countdowns tick (the words only change once a minute; the row redraws only then), the
	-- open screen's too (just their words: nothing else on it moves).
	task.spawn(function()
		while true do
			task.wait(1)
			refreshChip()
			for label, words in ticking do
				if label.Parent then
					label.Text = words()
				else
					ticking[label] = nil
				end
			end
		end
	end)
	watchPumpkins()
	watchLook()
end

return EventController

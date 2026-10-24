-- What the client half of a mini-game gets from Controllers/MiniGameController.
--
-- A client module (src/client/MiniGames/<Id>.luau) returns { Start = function(api) ... end } and
-- uses this API for everything; anything it creates through api:Track(), api:RenderStep() or the
-- buttons is cleaned up automatically when the round ends.
--
--   api:Now()                    server time, the same clock the server schedules with
--   api:Shared(key) / OnShared   round state the server set with ctx:SetShared(key, ...)
--   api:Mine(key) / OnMine       this player's state from ctx:SetPlayerShared(player, key, ...)
--   api:Action(name, ...)        tell the server about a control (handled by ctx:OnAction)
--   api:OnEvent(name, fn)        cues the server sent with ctx:Fire(...)
--   api:Button({ ... })          big touch-friendly action button with a keyboard key
--   api:Tilt()                   phone tilt as a move direction (nil without an accelerometer)
--   api:Template(name)           a copy of a model the server shared with ctx:ShareTemplate
--   api:Sound(name) / Effect     sound and particle effects for this player only
--   api:Participants()           everyone in this round, players and bots alike
--   api:CharacterOf(userId)      anyone's character by UserId, bots included
--   api:CanAct() / OnCanAct      whether this player can use the mode's controls right now
--
-- Buttons are only for people who can use them: anyone watching the round (sitting it out with the
-- PLAYING / SITTING OUT switch, joined after it started, or already knocked out) and everyone once it's
-- over sees the mode without its buttons, because the server only takes actions from players still
-- in the round. Api.Button does this for every mode; a mode's own SetVisible still applies on top.
--
-- More of the game on screen (owner: "During the mini games, any way we can save UI space so they
-- can see more of the game at one time?"): the TopHud moves up into the status line's room when the
-- line has nothing to say (its players-left count is a pill in the banner now: HudController), and
-- back down when it has, so whatever a mode places at y >= api:HudY() still sits right under the
-- banner, status line and team scores on every screen (State.TopHudShift, in the HUD's scaled
-- units; at once with reduced effects). A hint fades out once it has been up 6 seconds and comes
-- back whenever the mode sets a new one.

local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local Janitor = require(Shared.Janitor)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local AudioController = require(script.Parent.Parent.Parent.Controllers.AudioController)
local EffectsController = require(script.Parent.Parent.Parent.Controllers.EffectsController)
local Haptics = require(script.Parent.Parent.Parent.Haptics)
local Participants = require(script.Parent.Parent.Parent.Participants)
local State = require(script.Parent.Parent.Parent.State)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.Parent.UI.UIKit)

local Api = {}
Api.__index = Api

export type ButtonOptions = {
	Text: string,
	Key: Enum.KeyCode?,
	Color: Color3?,
	Slot: number?, -- 1 is the main button; 2 sits beside it
}

export type ActionButton = {
	Pressed: any,
	Released: any,
	IsDown: (self: ActionButton) -> boolean,
	SetText: (self: ActionButton, text: string) -> (),
	SetEnabled: (self: ActionButton, enabled: boolean) -> (),
	SetFill: (self: ActionButton, fraction: number, color: Color3?) -> (),
	SetVisible: (self: ActionButton, visible: boolean) -> (),
}

export type Tilt = {
	Calibrate: (self: Tilt) -> (),
	Get: (self: Tilt) -> Vector2,
	Flip: (self: Tilt) -> (),
}

local actionRemote = Remotes.Get("MiniGameAction")
local eventRemote = Remotes.Get("MiniGameEvent")

local HINT_FADE = 6 -- seconds a hint is on screen before it fades (a new hint comes back)
local HINT_FADE_TIME = 0.6
local HINT_STROKE = 0.2
local SHIFT_TIME = 0.25 -- the TopHud's move with the status line (HudController's team pill's too)

function Api.new(id: string)
	local self = setmetatable({}, Api)
	self.Id = id
	self.Player = Players.LocalPlayer
	self.Janitor = Janitor.new()
	local playerGui = self.Player:WaitForChild("PlayerGui")
	self.Gui = UIKit.new("ScreenGui", {
		Name = "MiniGame_" .. id,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, -- same safe area as the main HUD
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 6,
		Parent = playerGui,
	})
	self.Janitor:Add(self.Gui)
	-- Hidden while the round's rules card is up (RoundController sets PP_RulesShowing), so the mode's
	-- scores and meters never cover the rules; they appear with the 3-2-1.
	local function syncWithRules()
		self.Gui.Enabled = self.Player:GetAttribute("PP_RulesShowing") ~= true
	end
	syncWithRules()
	self.Janitor:Add(self.Player:GetAttributeChangedSignal("PP_RulesShowing"):Connect(syncWithRules))
	-- Parts the client half creates go here (removed with the round).
	local world = Instance.new("Folder")
	world.Name = "MiniGameClient"
	world.Parent = workspace
	self.World = world
	self.Janitor:Add(world)
	return self
end

export type Api = typeof(Api.new(""))

-- State ------------------------------------------------------------------------------------------

function Api.Now(_self: Api): number
	return workspace:GetServerTimeNow()
end

-- The round's arena, once it's all here: the server marks it built with how many parts it holds
-- (RoundContext.MarkBuilt) and this waits until this device has them, so nothing reads a model that
-- came before its parts (its pivot then reads as the world's middle: Skate Escape's bridge pieces
-- landed in the lobby; owner: "The skate peices are in the lobby"). The client half starts as
-- Preparing does, while the server is still building. It waits as long as Preparing lasts (building
-- can take most of it: first loads of the props, characters arriving) and ARENA_WAIT more, at most
-- ARENA_MAX in all, or until the count stops growing for a moment (the server may have taken parts
-- out since).
local ARENA_WAIT, ARENA_MAX = 5, 40
function Api.Arena(self: Api, timeout: number?): Model?
	local arena = workspace:WaitForChild("Arena_" .. self.Id, timeout or 10) :: Model?
	if not arena then
		return nil
	end
	local started = os.clock()
	local deadline = started + ARENA_WAIT
	local last, steadySince = -1, os.clock()
	while arena.Parent and os.clock() - started < ARENA_MAX do
		local expected = arena:GetAttribute("PP_Parts")
		if type(expected) ~= "number" then
			if GameState.Get("Phase") == "Preparing" then
				deadline = os.clock() + ARENA_WAIT -- (still being built)
			elseif os.clock() >= deadline then
				break
			end
		else
			local count = 0
			for _, descendant in arena:GetDescendants() do
				if descendant:IsA("BasePart") then
					count += 1
				end
			end
			if count >= expected then
				break
			elseif count ~= last then
				last, steadySince = count, os.clock()
			elseif os.clock() - steadySince > 1.5 then
				break
			end
		end
		task.wait(0.1)
	end
	return arena
end

function Api.Shared(_self: Api, key: string): any
	return GameState.Get("MG_" .. key)
end

function Api.SharedJSON(_self: Api, key: string): any
	return GameState.GetJSON("MG_" .. key)
end

function Api.OnShared(self: Api, key: string, callback: (value: any) -> ())
	self.Janitor:Add(GameState.Changed("MG_" .. key, callback))
end

function Api.Mine(self: Api, key: string): any
	return self.Player:GetAttribute("MG_" .. key)
end

function Api.OnMine(self: Api, key: string, callback: (value: any) -> ())
	self.Janitor:Add(self.Player:GetAttributeChangedSignal("MG_" .. key):Connect(function()
		callback(self.Player:GetAttribute("MG_" .. key))
	end))
end

function Api.Decode(_self: Api, raw: any): any
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok then value else nil
end

function Api.Alive(_self: Api): boolean
	return State.InRound() and State.Alive()
end

-- Whether this player's controls can do anything right now: they're in this round, not knocked out,
-- and the round isn't over (the server turns away actions from anyone else: RoundContext._onAction).
-- Someone who flips to SITTING OUT mid-round still finishes it (Services/SitOutService), so that
-- switch alone doesn't count; they're in the round until it ends.
function Api.CanAct(self: Api): boolean
	local phase = GameState.Get("Phase")
	return (phase == "Preparing" or phase == "InRound") and self:Alive()
end

-- Calls `callback(canAct)` whenever Api.CanAct may have changed (joined, knocked out, round over).
function Api.OnCanAct(self: Api, callback: (canAct: boolean) -> ())
	local function changed()
		callback(self:CanAct())
	end
	self.Janitor:Add(self.Player:GetAttributeChangedSignal("PP_InRound"):Connect(changed))
	self.Janitor:Add(self.Player:GetAttributeChangedSignal("PP_Alive"):Connect(changed))
	self.Janitor:Add(GameState.Changed("Phase", changed))
end

function Api.Character(self: Api): (Model?, Humanoid?, BasePart?)
	local character = self.Player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return character, humanoid, root
end

-- Everyone playing this round, bots included (Participants.luau): DisplayName, UserId, IsBot,
-- IsLocal, :GetAttribute(name) (PP_Alive, PP_Score, MG_<key>...) and :Character().
function Api.Participants(_self: Api): { Participants.Participant }
	return Participants.InRound()
end

-- A participant's character by UserId, e.g. one the server shared ("Taker = player.UserId"). Bots
-- aren't in Players, so look people up here rather than with Players:GetPlayers().
function Api.CharacterOf(_self: Api, userId: number?): Model?
	return Participants.CharacterOf(userId)
end

function Api.IsTouch(_self: Api): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- A copy of a model the server shared with ctx:ShareTemplate (nil if it doesn't arrive in time).
-- Whether a shared template has all its parts on this device yet (RoundContext.ShareTemplate's
-- PP_Parts): a model can arrive before its parts do, and a copy made in between lacks them for good.
function Api.Arrived(template: Instance): boolean
	local expected = template:GetAttribute("PP_Parts")
	if type(expected) ~= "number" then
		return true
	end
	local parts = 0
	for _, descendant in template:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	return parts >= expected
end

function Api.Template(_self: Api, name: string, timeout: number?): Instance?
	local limit = timeout or 10
	local folder = ReplicatedStorage:WaitForChild("MiniGameAssets", limit)
	local template = folder and folder:WaitForChild(name, limit)
	if not template then
		return nil
	end
	local deadline = os.clock() + limit
	while not Api.Arrived(template) and os.clock() < deadline do
		task.wait()
	end
	return template:Clone()
end

-- Plays a sound effect (Shared/Sounds names) or a particle effect (EffectsController names) for
-- this player only.
function Api.Sound(_self: Api, name: string)
	AudioController.Play(name)
end

function Api.Effect(_self: Api, name: string, position: Vector3, colors: { Color3 }?)
	EffectsController.Play(name, position, colors)
end

-- Server traffic ---------------------------------------------------------------------------------

function Api.Action(_self: Api, name: string, ...: any)
	actionRemote:FireServer(name, ...)
end

function Api.OnEvent(self: Api, name: string, callback: (...any) -> ())
	self.Janitor:Add(eventRemote.OnClientEvent:Connect(function(eventName, ...)
		if eventName == name then
			callback(...)
		end
	end))
end

-- Lifetime ---------------------------------------------------------------------------------------

function Api.Track<T>(self: Api, item: T): T
	return self.Janitor:Add(item)
end

function Api.RenderStep(self: Api, callback: (dt: number) -> ())
	self.Janitor:Add(RunService.RenderStepped:Connect(callback))
end

function Api.Destroy(self: Api)
	self.Janitor:Cleanup()
end

-- Controls ---------------------------------------------------------------------------------------

-- Where Roblox's touch jump button is, in `gui`'s coordinates: its left edge, its middle height and
-- its size. Read from the real button when it exists, else Roblox's own placement rule.
local function jumpButtonSpot(gui: ScreenGui): (number, number, number)
	local touchGui = gui.Parent and gui.Parent:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton") :: GuiObject?
	if jump and jump.AbsoluteSize.X > 0 then
		local origin = gui.AbsolutePosition
		return jump.AbsolutePosition.X - origin.X,
			jump.AbsolutePosition.Y - origin.Y + jump.AbsoluteSize.Y / 2,
			jump.AbsoluteSize.X
	end
	local screen = gui.AbsoluteSize
	local small = math.min(screen.X, screen.Y) <= 500
	local size = if small then 70 else 120
	local top = if small then screen.Y - size - 20 else screen.Y - size * 1.75
	return screen.X - (size * 1.5 - 10), top + size / 2, size
end

-- A big round button (beside the jump button on phones, bottom middle on PC) that also listens to a key.
-- It only shows (and its key only works) while this player can act (Api.CanAct): spectators never see it.
function Api.Button(self: Api, options: ButtonOptions): ActionButton
	local slot = options.Slot or 1
	local color = options.Color or Theme.Colors.Pink
	local pressed = Signal.new()
	local released = Signal.new()
	local isDown = false
	local enabled = true
	local wanted = true -- the mode's own SetVisible
	local canAct = self:CanAct()

	local holder = UIKit.new("Frame", {
		Name = "Action_" .. options.Text,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, 90 - (slot - 1) * 180, 1, -24),
		Size = UDim2.fromOffset(118, 118),
		BackgroundTransparency = 1,
		Parent = self.Gui,
	})
	local holderScale = UIKit.AutoScale(holder)
	if self:IsTouch() then
		-- Right beside Roblox's jump button (slot 2 further left), where the right thumb already is.
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder:SetAttribute("TouchSlot", slot) -- tools/checks/ui_render.py places it the same way
		local function place()
			local left, centerY, size = jumpButtonSpot(self.Gui)
			local width = 118 * holderScale.Scale
			holder.Position = UDim2.fromOffset(left - 12 - (slot - 1) * (width + 12), centerY - size * 0.15)
		end
		place()
		self.Janitor:Add(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(place))
		self.Janitor:Add(holderScale:GetPropertyChangedSignal("Scale"):Connect(place))
		task.delay(1, place) -- the touch controls are created after the character spawns
	end
	local button = UIKit.new("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = "",
		Parent = holder,
		Children = { UIKit.Round(), UIKit.Stroke(Color3.new(1, 1, 1), 4, 0.1) },
	})
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.55,
		Parent = button,
		Children = { UIKit.Round() },
	})
	local label = UIKit.Label({
		Text = options.Text,
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextScaled = true,
		Size = UDim2.fromScale(0.86, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		ZIndex = 2,
		Parent = button,
		Children = { UIKit.TextStroke(0.15) },
	})
	if options.Key and not self:IsTouch() then
		UIKit.Label({
			Text = `[{options.Key.Name}]`,
			Font = Theme.Fonts.Bold,
			TextSize = 18,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.7),
			Size = UDim2.fromScale(1, 0.2),
			ZIndex = 2,
			Parent = button,
			Children = { UIKit.TextStroke(0.3) },
		})
	end
	local scale = UIKit.new("UIScale", { Parent = button })

	-- On a phone a hold lasts until that finger lifts, wherever it slides meanwhile (owner: "I want
	-- playing on mobile to feel really good."): a thumb drifting off the button's edge mid-pump or
	-- mid-dive no longer lets go.
	local holdingTouch: InputObject? = nil
	local touchWatch: RBXScriptConnection? = nil
	local function forgetTouch()
		holdingTouch = nil
		if touchWatch then
			touchWatch:Disconnect()
			touchWatch = nil
		end
	end
	local function press()
		if not enabled or isDown or not canAct then
			return
		end
		isDown = true
		scale.Scale = 0.9
		Haptics.Play("Tap")
		pressed:Fire()
	end
	local function release()
		forgetTouch()
		if not isDown then
			return
		end
		isDown = false
		scale.Scale = 1
		released:Fire()
	end
	local function refreshShown()
		holder.Visible = wanted and canAct
		if not holder.Visible then
			release()
		end
	end
	refreshShown()
	self:OnCanAct(function(value)
		canAct = value
		refreshShown()
	end)
	self.Janitor:Add(button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local held = holdingTouch
		if held then
			local state = held.UserInputState
			if state ~= Enum.UserInputState.End and state ~= Enum.UserInputState.Cancel then
				return -- (another finger on it: the first one holds it)
			end
			release() -- (a hold whose end never came)
		end
		press()
		if isDown then
			holdingTouch = input
			touchWatch = input.Changed:Connect(function()
				local state = input.UserInputState
				if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
					release()
				end
			end)
		end
	end))
	self.Janitor:Add(UserInputService.TouchEnded:Connect(function(touch)
		if touch == holdingTouch then
			release()
		end
	end))
	-- Roblox's menu, the notification shade or another app can swallow the finger's lift: let go then.
	self.Janitor:Add(GuiService.MenuOpened:Connect(release))
	self.Janitor:Add(UserInputService.WindowFocusReleased:Connect(release))
	self.Janitor:Add(forgetTouch)
	-- (A mouse, or a touch the InputBegan above didn't take: the button's own edges.)
	self.Janitor:Add(button.MouseButton1Down:Connect(press))
	self.Janitor:Add(button.MouseButton1Up:Connect(function()
		if not holdingTouch then
			release()
		end
	end))
	self.Janitor:Add(button.MouseLeave:Connect(function()
		if not holdingTouch then
			release()
		end
	end))
	if options.Key then
		local key = options.Key
		self.Janitor:Add(UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.KeyCode == key then
				press()
			end
		end))
		self.Janitor:Add(UserInputService.InputEnded:Connect(function(input)
			if input.KeyCode == key then
				release()
			end
		end))
	end

	local api = {
		Pressed = pressed,
		Released = released,
	}
	function api.IsDown(_api)
		return isDown
	end
	-- (Modes call these every frame: they only touch the button when something changes.)
	function api.SetText(_api, text: string)
		if label.Text ~= text then
			label.Text = text
		end
	end
	function api.SetEnabled(_api, value: boolean)
		if value == enabled then
			return
		end
		enabled = value
		button.BackgroundTransparency = if value then 0 else 0.55
		if not value then
			release()
		end
	end
	function api.SetVisible(_api, value: boolean)
		wanted = value
		refreshShown()
	end
	local lastFill, lastFillColor = -1, nil
	function api.SetFill(_api, fraction: number, fillColor: Color3?)
		fraction = math.clamp(fraction, 0, 1)
		if math.abs(fraction - lastFill) > 0.002 then
			lastFill = fraction
			fill.Size = UDim2.fromScale(1, fraction)
		end
		if fillColor and fillColor ~= lastFillColor then
			lastFillColor = fillColor
			fill.BackgroundColor3 = fillColor
		end
	end
	return api :: any
end

export type Mood = {
	Tint: Color3?,
	Saturation: number?,
	Contrast: number?,
	Brightness: number?,
	Haze: Color3?, -- atmosphere color (sky haze)
	HazeDecay: Color3?,
	Density: number?,
}

-- Sets the look of the arena for this player while the mode runs (color grading and sky haze);
-- everything is put back when the round ends. Only this client sees it.
function Api.Mood(self: Api, mood: Mood)
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "MiniGameMood"
	correction.TintColor = mood.Tint or Color3.new(1, 1, 1)
	correction.Saturation = mood.Saturation or 0
	correction.Contrast = mood.Contrast or 0
	correction.Brightness = mood.Brightness or 0
	correction.Parent = Lighting
	self.Janitor:Add(correction)

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and (mood.Haze or mood.HazeDecay or mood.Density) then
		local saved = { Color = atmosphere.Color, Decay = atmosphere.Decay, Density = atmosphere.Density }
		atmosphere.Color = mood.Haze or saved.Color
		atmosphere.Decay = mood.HazeDecay or saved.Decay
		atmosphere.Density = mood.Density or saved.Density
		self.Janitor:Add(function()
			if atmosphere.Parent then
				atmosphere.Color = saved.Color
				atmosphere.Decay = saved.Decay
				atmosphere.Density = saved.Density
			end
		end)
	end
end

-- Phones: mode HUDs are drawn at this share of the PC size, so a mode's banner and counters stay
-- compact there (owner: "Wtf is this mobile Ui lol").
local TOUCH_HUD_SCALE = 0.75

-- The space under the round banner (title, timer, status line and team scores) for a mode's own
-- HUD, 620 units wide. It's laid out like the banner and scales with it, so anything placed at
-- y >= api:HudY() never covers the banner on any screen. On phones the banner is up in Roblox's
-- top bar row and this space starts under the status line, drawn a little smaller. It sits in a
-- holder scaled like the banner, and moves inside it with the status line (State.TopHudShift).
function Api.TopHud(self: Api): Frame
	local hud = self.Gui:FindFirstChild("TopHud", true) :: Frame?
	if not hud then
		local touch = self:IsTouch()
		local holder = UIKit.new("Frame", {
			Name = "TopHudHolder",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = if touch then UDim2.fromScale(0.5, 0) else UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.fromOffset(620, 420),
			BackgroundTransparency = 1,
			Parent = self.Gui,
		})
		UIKit.AutoScale(holder)
		local made = UIKit.new("Frame", {
			Name = "TopHud",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, State.TopHudShift),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = holder,
			Children = if touch then { UIKit.new("UIScale", { Scale = TOUCH_HUD_SCALE }) } else {},
		})
		self.Janitor:Add(State.TopHudShiftChanged:Connect(function(shift: number)
			local goal = UDim2.new(0.5, 0, 0, shift)
			if State.ReducedEffects() then
				made.Position = goal
			else
				UIKit.Tween(made, SHIFT_TIME, { Position = goal })
			end
		end))
		hud = made
	end
	return hud :: Frame
end

-- First free line in the TopHud: under the status line, or under the team scores in team modes.
-- (Phones: HudController's status line ends 36 units down and the team scores 82, in the HUD's
-- units; the TopHud's units are TOUCH_HUD_SCALE of those.) The same number all round: when the
-- status line is out of the way the whole TopHud moves up instead (State.TopHudShift), so this line
-- is then right under the banner, or under the team scores.
function Api.HudY(self: Api): number
	local definition = GameDefinitions.Get(self.Id)
	local team = definition and definition.IsTeam
	if self:IsTouch() then
		return if team then 116 else 56
	end
	return if team then 156 else 112
end

-- Each mode HUD's hint: how long its words have been on screen, and whether they've faded.
type HintClock = { Shown: number, Faded: boolean }
local hintClocks: { [TextLabel]: HintClock } = setmetatable({}, { __mode = "k" }) :: any

-- Counts how long a hint is on screen during the round: from GO at the earliest (a hint set while
-- the rules card is up waits behind it, then shows through the 3-2-1), only while the mode's HUD
-- shows, and fades it out at HINT_FADE seconds.
local function followHint(self: Api, hint: TextLabel)
	local stroke = hint:FindFirstChildOfClass("UIStroke")
	self.Janitor:Add(RunService.Heartbeat:Connect(function(dt)
		local clock = hintClocks[hint]
		if
			not clock
			or clock.Faded
			or hint.Text == ""
			or not hint.Visible
			or not self.Gui.Enabled
			or GameState.Get("Phase") ~= "InRound"
		then
			return
		end
		clock.Shown += dt
		if clock.Shown < HINT_FADE then
			return
		end
		clock.Faded = true
		UIKit.Tween(hint, HINT_FADE_TIME, { TextTransparency = 1 })
		if stroke then
			UIKit.Tween(stroke, HINT_FADE_TIME, { Transparency = 1 })
		end
		task.delay(HINT_FADE_TIME, function()
			if hintClocks[hint] == clock then
				hint.Visible = false
			end
		end)
	end))
end

-- A line of instructions under the banner (pass "" to hide it). `y` is a TopHud offset (default
-- api:HudY()). It fades out once it has been on screen HINT_FADE seconds; setting the same words
-- again leaves it be, new words bring it back.
function Api.Hint(self: Api, text: string, y: number?)
	local hud = self:TopHud()
	local label = hud:FindFirstChild("Hint") :: TextLabel?
	if not label then
		label = UIKit.Label({
			Name = "Hint",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = 26,
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(620, 64),
			TextYAlignment = Enum.TextYAlignment.Top,
			Visible = false,
			Parent = hud,
			Children = { UIKit.TextStroke(HINT_STROKE) },
		})
		followHint(self, label :: TextLabel)
	end
	local hint = label :: TextLabel
	hint.Position = UDim2.new(0.5, 0, 0, y or self:HudY())
	if text == hint.Text then
		return -- the same words: a hint that has faded stays gone
	end
	hint.Text = text
	hint.Visible = text ~= ""
	-- Fully shown again (a tween too: it takes over from a fade still running), with a new clock.
	local stroke = hint:FindFirstChildOfClass("UIStroke")
	UIKit.Tween(hint, 0, { TextTransparency = 0 })
	hint.TextTransparency = 0
	if stroke then
		UIKit.Tween(stroke, 0, { Transparency = HINT_STROKE })
		stroke.Transparency = HINT_STROKE
	end
	if text ~= "" then
		hintClocks[hint] = { Shown = 0, Faded = false }
	else
		hintClocks[hint] = nil
	end
	if self:IsTouch() then
		-- Phones: only as wide (and as tall) as the words, so the line stays clear of the thumbstick's
		-- corner and of anything a mode shows under it.
		local width = UIKit.TextWidth(text, 26, Theme.Fonts.Display) + 24
		local oneLine = width <= 620 and not string.find(text, "\n", 1, true)
		hint.Size = UDim2.fromOffset(math.min(620, math.ceil(width)), if oneLine then 36 else 64)
	end
end

-- Phone tilt as a camera-relative move input. The screen's axes are worked out from the way the
-- phone is held when it calibrates, so portrait and both landscape grips work without settings.
function Api.Tilt(self: Api): Tilt?
	if not UserInputService.AccelerometerEnabled then
		return nil
	end
	local neutral = Vector3.new(0, -1, 0)
	local right = Vector3.new(1, 0, 0)
	local up = Vector3.new(0, 1, 0)
	local flip = 1
	local known = false -- the axes have been read from a tilted phone at least once

	local function gravity(): Vector3
		local ok, input = pcall(UserInputService.GetDeviceGravity, UserInputService)
		if ok and input then
			local value = input.Position
			if value.Magnitude > 0.01 then
				return value.Unit
			end
		end
		return neutral
	end

	local tilt = {}
	function tilt.Calibrate(_tilt)
		neutral = gravity()
		-- "Up" on the screen points away from where gravity pulls within the screen plane.
		local flat = Vector2.new(-neutral.X, -neutral.Y)
		if flat.Magnitude < 0.25 then
			-- Phone held nearly flat: the grip can't be read from gravity. Keep the axes from the
			-- last calibration that could; failing that, go by the screen's shape and orientation.
			if known then
				return
			end
			local camera = workspace.CurrentCamera
			local viewport = if camera then camera.ViewportSize else Vector2.new(16, 9)
			if viewport.X > viewport.Y then
				local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
				local orientation = playerGui and playerGui.CurrentScreenOrientation
				flat = if orientation == Enum.ScreenOrientation.LandscapeRight
					then Vector2.new(-1, 0)
					else Vector2.new(1, 0)
			else
				flat = Vector2.new(0, 1)
			end
		else
			known = true
		end
		flat = flat.Unit
		up = Vector3.new(flat.X, flat.Y, 0)
		right = Vector3.new(flat.Y, -flat.X, 0)
	end
	function tilt.Get(_tilt): Vector2
		local delta = gravity() - neutral
		local x = delta:Dot(right) * flip
		local y = delta:Dot(up)
		local value = Vector2.new(x, y) / 0.35 -- about 20 degrees of tilt is full speed
		local magnitude = value.Magnitude
		if magnitude < 0.25 then -- about 5 degrees: a hand holding still doesn't drift
			return Vector2.zero
		end
		-- Speed ramps up from the edge of the dead zone, so there's no jump when tilt kicks in.
		return value.Unit * math.min(1, (magnitude - 0.25) / 0.65)
	end
	function tilt.Flip(_tilt)
		flip = -flip
	end
	tilt.Calibrate(tilt)
	self.Janitor:Add(function()
		neutral = Vector3.new(0, -1, 0)
	end)
	return tilt :: any
end

return Api

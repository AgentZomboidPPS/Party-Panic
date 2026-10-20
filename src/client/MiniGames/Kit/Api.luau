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

local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local GameDefinitions = require(Shared.GameDefinitions)
local GameState = require(Shared.GameState)
local Janitor = require(Shared.Janitor)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local AudioController = require(script.Parent.Parent.Parent.Controllers.AudioController)
local EffectsController = require(script.Parent.Parent.Parent.Controllers.EffectsController)
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

function Api.Arena(self: Api, timeout: number?): Model?
	return workspace:WaitForChild("Arena_" .. self.Id, timeout or 10) :: Model?
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

function Api.Character(self: Api): (Model?, Humanoid?, BasePart?)
	local character = self.Player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return character, humanoid, root
end

function Api.IsTouch(_self: Api): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- A copy of a model the server shared with ctx:ShareTemplate (nil if it doesn't arrive in time).
function Api.Template(_self: Api, name: string, timeout: number?): Instance?
	local folder = ReplicatedStorage:WaitForChild("MiniGameAssets", timeout or 10)
	local template = folder and folder:WaitForChild(name, timeout or 10)
	return if template then template:Clone() else nil
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
function Api.Button(self: Api, options: ButtonOptions): ActionButton
	local slot = options.Slot or 1
	local color = options.Color or Theme.Colors.Pink
	local pressed = Signal.new()
	local released = Signal.new()
	local isDown = false
	local enabled = true

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

	local function press()
		if not enabled or isDown then
			return
		end
		isDown = true
		scale.Scale = 0.9
		pressed:Fire()
	end
	local function release()
		if not isDown then
			return
		end
		isDown = false
		scale.Scale = 1
		released:Fire()
	end
	self.Janitor:Add(button.MouseButton1Down:Connect(press))
	self.Janitor:Add(button.MouseButton1Up:Connect(release))
	self.Janitor:Add(button.MouseLeave:Connect(release))
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
	function api.SetText(_api, text: string)
		label.Text = text
	end
	function api.SetEnabled(_api, value: boolean)
		enabled = value
		button.BackgroundTransparency = if value then 0 else 0.55
		if not value then
			release()
		end
	end
	function api.SetVisible(_api, value: boolean)
		holder.Visible = value
		if not value then
			release()
		end
	end
	function api.SetFill(_api, fraction: number, fillColor: Color3?)
		fill.Size = UDim2.fromScale(1, math.clamp(fraction, 0, 1))
		if fillColor then
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

-- The space under the round banner (title, timer, status line and team scores) for a mode's own
-- HUD. It's laid out like the banner and scales with it, so anything placed at y >= api:HudY()
-- never covers the banner on any screen.
function Api.TopHud(self: Api): Frame
	local hud = self.Gui:FindFirstChild("TopHud") :: Frame?
	if not hud then
		hud = UIKit.new("Frame", {
			Name = "TopHud",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.fromOffset(620, 420),
			BackgroundTransparency = 1,
			Parent = self.Gui,
		})
		UIKit.AutoScale(hud :: Frame)
	end
	return hud :: Frame
end

-- First free line in the TopHud: under the status line, or under the team scores in team modes.
function Api.HudY(self: Api): number
	local definition = GameDefinitions.Get(self.Id)
	return if definition and definition.IsTeam then 156 else 112
end

-- A line of instructions under the banner (pass "" to hide it). `y` is a TopHud offset (default
-- api:HudY()).
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
			Parent = hud,
			Children = { UIKit.TextStroke(0.2) },
		})
	end
	local hint = label :: TextLabel
	hint.Position = UDim2.new(0.5, 0, 0, y or self:HudY())
	hint.Text = text
	hint.Visible = text ~= ""
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
			flat = Vector2.new(0, 1) -- phone held nearly flat: assume portrait axes
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
		if value.Magnitude < 0.12 then
			return Vector2.zero
		end
		if value.Magnitude > 1 then
			value = value.Unit
		end
		return value
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

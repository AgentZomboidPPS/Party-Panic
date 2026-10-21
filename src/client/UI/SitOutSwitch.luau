-- The "sit out next round" switch (owner: "Also we do need to add somewhere super apparent a
-- toggle where you skip next round or somethiong like that"). HudController puts one right by the
-- phase banner (phones: in Roblox's top bar row beside the banner; PC: in that row, above it) and
-- one in the Settings window; they always agree.
--
--   🎮 PLAYING / next round      green, knob on the right
--   💤 SITTING OUT / tap to play muted, knob on the left
--
-- The icon, the words and the knob's side say which, never the colour alone. A tap slides the
-- knob, bounces the pill and plays a sound at once, then asks the server (Services/SitOutService),
-- which sets the PP_SitOut attribute and sends a short notification; if no answer comes, the
-- switch slides back. The banner's switch steps aside while you're playing a round (you finish it
-- either way) and comes back when you're out, or the round's over.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)

local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local SitOutSwitch = {}

local ATTRIBUTE = "PP_SitOut"
local TAP_GAP = 0.35 -- seconds: a second tap sooner than this is the same tap
local ANSWER_TIME = 2 -- the server answers well within this; if it doesn't, the switch slides back

-- Layout in the units of the frame the switch sits in. The tap area is a 44 pt touch target on
-- phones; the pill inside it is as tall as the phase banner.
local HIT_H, PILL_H = 72, 66
local TRACK_X, TRACK_W, TRACK_H, KNOB = 9, 72, 44, 38
local TEXT_X = TRACK_X + TRACK_W + 11
local TITLE_SIZE, HINT_SIZE = 26, Theme.Touch.MinText
local KNOB_INSET = (TRACK_H - KNOB) / 2

type Look = {
	Icon: string,
	Title: string,
	Hint: string,
	Color: Color3,
	Knob: Color3,
	HintColor: Color3,
	Rim: number,
	Sound: string,
}

local PLAYING: Look = {
	Icon = "🎮",
	Title = "PLAYING",
	Hint = "next round",
	Color = Color3.fromRGB(70, 205, 115),
	Knob = Color3.new(1, 1, 1),
	HintColor = Color3.fromRGB(230, 255, 236),
	Rim = 0.15,
	Sound = "Pickup",
}
local SITTING_OUT: Look = {
	Icon = "💤",
	Title = "SITTING OUT",
	Hint = "tap to play",
	Color = Color3.fromRGB(116, 106, 156),
	Knob = Color3.fromRGB(222, 216, 245),
	HintColor = Theme.Colors.Yellow,
	Rim = 0.55,
	Sound = "VoteClick",
}

export type Options = {
	Name: string?,
	AnchorPoint: Vector2?,
	Position: UDim2?,
	Hud: boolean?, -- the banner's switch: steps aside while you're playing a round
}

type View = {
	Root: TextButton,
	Pill: Frame,
	Knob: Frame,
	Icon: TextLabel,
	Title: TextLabel,
	Hint: TextLabel,
	Rim: UIStroke,
	Scale: UIScale,
	Hud: boolean,
}

local views: { View } = {}
local showing = false -- what the switches show: the server's word, or the tap it's answering
local wanted: boolean? = nil -- the latest tap, until its answer is due
local answerDue = 0
local lastTap = -math.huge
local requestId = 0
local listening = false

local function lookFor(sitOut: boolean): Look
	return if sitOut then SITTING_OUT else PLAYING
end

-- Wide enough for either state's words, so the pill never jumps when it flips.
local function measureWidth(): number
	local widest = 0
	for _, look in { PLAYING, SITTING_OUT } do
		widest = math.max(
			widest,
			UIKit.TextWidth(look.Title, TITLE_SIZE, Theme.Fonts.Display),
			UIKit.TextWidth(look.Hint, HINT_SIZE, Theme.Fonts.Bold)
		)
	end
	return TEXT_X + math.ceil(widest) + 20
end

local function knobPosition(sitOut: boolean): UDim2
	return UDim2.new(0, if sitOut then KNOB_INSET else TRACK_W - KNOB - KNOB_INSET, 0.5, 0)
end

-- A ring that grows out of the knob and fades: the "it flipped" moment.
local function ripple(view: View)
	if State.ReducedEffects() then
		return
	end
	local stroke = UIKit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3, Transparency = 0.1 })
	local ring = UIKit.new("Frame", {
		Name = "Ripple",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(KNOB, KNOB),
		BackgroundTransparency = 1,
		Parent = view.Knob,
		Children = { UIKit.Round(), stroke },
	})
	UIKit.Tween(ring, 0.4, { Size = UDim2.fromOffset(KNOB * 2.4, KNOB * 2.4) })
	UIKit.Tween(stroke, 0.4, { Transparency = 1 })
	task.delay(0.45, function()
		ring:Destroy()
	end)
end

local function bounce(view: View, from: number)
	view.Scale.Scale = from
	UIKit.Tween(view.Scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- `flip`: animate it (a slide, a bounce, and a ring unless it's sliding back).
local function paint(view: View, flip: boolean, ring: boolean)
	local look = lookFor(showing)
	view.Icon.Text = look.Icon
	view.Title.Text = look.Title
	view.Hint.Text = look.Hint
	view.Hint.TextColor3 = look.HintColor
	view.Rim.Transparency = look.Rim
	if flip then
		UIKit.Tween(view.Knob, 0.28, { Position = knobPosition(showing) }, Enum.EasingStyle.Back)
		UIKit.Tween(view.Knob, 0.2, { BackgroundColor3 = look.Knob })
		UIKit.Tween(view.Pill, 0.2, { BackgroundColor3 = look.Color })
		bounce(view, 1.1)
		if ring then
			ripple(view)
		end
	else
		view.Knob.Position = knobPosition(showing)
		view.Knob.BackgroundColor3 = look.Knob
		view.Pill.BackgroundColor3 = look.Color
	end
end

-- Flips every switch, with the new state's sound and ring unless it's a slide back.
local function setShowing(sitOut: boolean, celebrate: boolean)
	showing = sitOut
	for _, view in views do
		paint(view, true, celebrate)
	end
	if celebrate then
		AudioController.Play(lookFor(sitOut).Sound)
	end
end

-- The banner's switch steps aside while you're playing a round.
local function playingRound(): boolean
	local phase = State.Phase()
	return (phase == "Preparing" or phase == "InRound") and State.InRound() and State.Alive()
end

local function refreshVisible()
	local visible = not playingRound()
	for _, view in views do
		if view.Hud and view.Root.Visible ~= visible then
			view.Root.Visible = visible
			if visible then
				bounce(view, 0.8)
			end
		end
	end
end

local function listen()
	if listening then
		return
	end
	listening = true
	showing = State.SittingOut()
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		local actual = State.SittingOut()
		if wanted ~= nil and actual ~= wanted and os.clock() < answerDue then
			return -- the answer to an earlier tap; the latest tap's answer is on its way
		end
		wanted = nil
		if actual ~= showing then
			setShowing(actual, true)
		end
	end)
	GameState.Changed("Phase", refreshVisible)
	player:GetAttributeChangedSignal("PP_InRound"):Connect(refreshVisible)
	player:GetAttributeChangedSignal("PP_Alive"):Connect(refreshVisible)
end

-- Asks to sit out (true) or to play again (false). The switches flip right away.
function SitOutSwitch.Request(sitOut: boolean)
	listen()
	local now = os.clock()
	if sitOut == showing or now - lastTap < TAP_GAP then
		return
	end
	lastTap = now
	requestId += 1
	local id = requestId
	wanted = sitOut
	answerDue = now + ANSWER_TIME
	setShowing(sitOut, true)
	Remotes.Get("SetSitOut"):FireServer(sitOut)
	task.delay(ANSWER_TIME, function()
		if id ~= requestId then
			return
		end
		wanted = nil
		local actual = State.SittingOut()
		if actual ~= showing then
			setShowing(actual, false) -- the server said no (too many taps): slide back to its word
		end
	end)
end

-- A switch in `parent`. Its tap area is HIT_H tall and as wide as the words need.
function SitOutSwitch.new(parent: Instance, options: Options?): TextButton
	listen()
	local opts: Options = options or {}
	local width = measureWidth()
	local scale = UIKit.new("UIScale", { Scale = 1 })
	local root = UIKit.new("TextButton", {
		Name = opts.Name or "SitOut",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = opts.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = opts.Position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, HIT_H),
		Parent = parent,
		Children = { scale },
	}) :: TextButton
	local rim = UIKit.Stroke(nil, 2, PLAYING.Rim)
	local pill = UIKit.new("Frame", {
		Name = "Pill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, PILL_H),
		BackgroundColor3 = PLAYING.Color,
		Parent = root,
		-- White to grey over the colour: the same glossy shading as the other buttons.
		Children = { UIKit.Round(), UIKit.Gradient(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 178)), rim },
	})
	local track = UIKit.new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, TRACK_X, 0.5, 0),
		Size = UDim2.fromOffset(TRACK_W, TRACK_H),
		BackgroundColor3 = Color3.fromRGB(20, 12, 46),
		BackgroundTransparency = 0.5,
		Parent = pill,
		Children = { UIKit.Round() },
	})
	local knob = UIKit.new("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(KNOB, KNOB),
		Parent = track,
		Children = {
			UIKit.Round(),
			UIKit.new("UIStroke", { Color = Color3.fromRGB(30, 15, 60), Thickness = 1.5, Transparency = 0.5 }),
		},
	})
	local icon = UIKit.Label({
		Name = "Icon",
		Text = "",
		TextSize = 22,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = knob,
	})
	local title = UIKit.Label({
		Name = "Title",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = TITLE_SIZE,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(TEXT_X, 4),
		Size = UDim2.new(1, -(TEXT_X + 8), 0, 32),
		Parent = pill,
		Children = { UIKit.TextStroke(0.25) },
	})
	local hint = UIKit.Label({
		Name = "Hint",
		Text = "",
		TextSize = HINT_SIZE,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(TEXT_X, 38),
		Size = UDim2.new(1, -(TEXT_X + 8), 0, 22),
		Parent = pill,
		Children = { UIKit.TextStroke(0.3) },
	})
	local view: View = {
		Root = root,
		Pill = pill,
		Knob = knob,
		Icon = icon,
		Title = title,
		Hint = hint,
		Rim = rim,
		Scale = scale,
		Hud = opts.Hud == true,
	}
	table.insert(views, view)
	paint(view, false, false)
	if view.Hud then
		root.Visible = not playingRound()
	end

	-- A squish under the thumb, then the flip.
	root.MouseButton1Down:Connect(function()
		UIKit.Tween(scale, 0.06, { Scale = 0.93 })
	end)
	root.MouseButton1Up:Connect(function()
		UIKit.Tween(scale, 0.1, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	root.MouseLeave:Connect(function()
		UIKit.Tween(scale, 0.1, { Scale = 1 })
	end)
	root.Activated:Connect(function()
		SitOutSwitch.Request(not showing)
	end)
	task.delay(3, function() -- again once the font has surely loaded
		root.Size = UDim2.fromOffset(math.max(width, measureWidth()), HIT_H)
	end)
	return root
end

return SitOutSwitch

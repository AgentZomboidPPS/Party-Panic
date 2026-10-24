-- Toast notifications: short, icon-led messages that slide in and fade out (design doc §12).
-- They draw above the HUD and mode HUDs (but under pop-ups) in a spot nothing else uses: the top
-- right corner on PC (above the side menu), and on phones low down in the middle (owner, on layout
-- A: "certain buttons aren't centered?"), lifted above the "you're out" and spectate panels (and
-- only the newest while the rules card is up).
-- Two at a time (a new one pushes the oldest out), so they never reach the menu or the vote.
-- A toast is as tall as its lines (measured, not AutomaticSize, which cut text short on phones).
--
-- Toasts wait while the results card or a Party Cup podium is up (the local player's
-- PP_ResultsShowing / PP_CupPodium): those windows draw over them, so a toast sent then (a quest done
-- with the round's rewards, a friend beaten) would come and go unseen. They show when it closes, a
-- couple at a time, oldest first.
--
-- Phones in a round: a mode's action buttons (HIT, RAKE!, PUMP, Bobsled's LEFT...: Api.Button) sit
-- beside the jump button, right in that low gap, and the toasts drew over them just when an
-- announcement told players to press ("GOLDEN RUSH!"). While any is showing, the toasts sit above
-- the buttons' row instead (still clear of the thumbstick's corner and the menu column).
--
-- A quieter round (owner: "During the mini games, any way we can save UI space so they can see more
-- of the game at one time?"): while the player is playing a round (State.PlayingRound: from its
-- rules card to its end, still in), toasts that aren't about the round (quests, who joined or left,
-- coin tips, friends) wait like they do under the results card, and show once the round is over for
-- them (the results, or knocked out and watching); a window opened mid-round (the menu's ☰) gets its
-- answers at once. The round's own callouts (the server's topic "Round": RoundContext.Announce, "🎃
-- GOLDEN RUSH! 🎃") still show: on phones one at a time in a strip under the banner
-- (HudController), not over the middle of the play area; on PC in the top right corner as before.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Parent.UI.Modal)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local NotificationController = {}

local KINDS = {
	info = { Icon = "💬", Color = Theme.Colors.Cyan },
	success = { Icon = "✅", Color = Theme.Colors.Green },
	warning = { Icon = "⚠️", Color = Theme.Colors.Orange },
	reward = { Icon = "🎁", Color = Theme.Colors.Yellow },
}

-- Low HUD panels (RoundController, SpectateController, SquadController's squad bar in the lobby,
-- VoteController's cards: 110 laid out, drawn 1.25 times, 10 off the bottom) the phone toasts stay
-- above: name -> their height plus a gap, in the same scaled units.
local BOTTOM_PANELS = {
	OutPanel = 86 + 12,
	Spectate = 86 + 12,
	SpectateButton = 84 + 12, -- (WATCH / PLAY NEXT ROUND)
	SquadBar = 84 + 18,
	Vote = 110 * 1.25 + 10 + 12,
}

-- Toast width and text (scaled units): PC, then phones.
local WIDTH, TEXT, PAD_X, PAD_Y = 360, 21, 18, 10
local TOUCH_WIDTH, TOUCH_TEXT, TOUCH_PAD_X, TOUCH_PAD_Y = 440, 19, 16, 8

local MAX_TOASTS = 2
-- Windows that draw over the toasts while they're up (attributes on the local player).
local COVERS = { "PP_ResultsShowing", "PP_CupPodium" }
local MAX_WAITING = 6 -- toasts kept while covered or held for the round (the oldest go first past this)
local ROUND = "Round" -- the topic of a callout about the round (Services/Notifier.ROUND)
local PLAYING_GAP = 0.4 -- seconds after the round is over for the player before held toasts show
local RELEASE_GAP = 1.6 -- seconds between waiting toasts once the window closes, after the first two
local ACTION_GAP = 8 -- phones: between the toasts and the mode's action buttons under them (pixels)
local touch = false
local newestLast = false -- phones: the newest toast sits at the bottom of the stack
local stack: Frame
local active: { Frame } = {}
local order = 0
local waiting: { { Text: string, Kind: string?, Duration: number?, Topic: string? } } = {}
local releasing = false
local windowOpen = false -- a window (shop, quests, settings...) is open: Modal.AnyOpenChanged

local function covered(): boolean
	for _, name in COVERS do
		if Players.LocalPlayer:GetAttribute(name) == true then
			return true
		end
	end
	return false
end

-- Whether a toast waits for now: under a window that covers the toasts, or, if it isn't about the
-- round, while the player is playing one (unless they're in a window: then it's the answer to
-- something they did there, like a purchase).
local function held(topic: string?): boolean
	if covered() then
		return true
	end
	return topic ~= ROUND and State.PlayingRound() and not windowOpen
end

local show: (text: string, kind: string?, duration: number?) -> ()

-- The toasts that waited: two at once (as many as show), the rest one by one, oldest first.
local function release()
	if releasing then
		return
	end
	releasing = true
	local shown = 0
	while #waiting > 0 and not held(waiting[1].Topic) do
		local nextToast = table.remove(waiting, 1)
		if nextToast then
			show(nextToast.Text, nextToast.Kind, nextToast.Duration)
			shown += 1
		end
		if shown >= MAX_TOASTS and #waiting > 0 then
			task.wait(RELEASE_GAP)
		end
	end
	releasing = false
end

-- `topic` is the server's (Services/Notifier): "Round" for a callout about the round.
function NotificationController.Show(text: string, kind: string?, duration: number?, topic: string?)
	if held(topic) then
		table.insert(waiting, { Text = text, Kind = kind, Duration = duration, Topic = topic })
		while #waiting > MAX_WAITING do
			table.remove(waiting, 1)
		end
		return
	end
	-- Phones in a round: its callouts go to the strip under the banner, one at a time.
	if topic == ROUND and touch and GameState.Get("Phase") == "InRound" and State.InRound() then
		local style = KINDS[kind or "info"] or KINDS.info
		State.RoundCallout:Fire(`{style.Icon}  {text}`, style.Color, duration or 3.5)
		return
	end
	show(text, kind, duration)
end

function show(text: string, kind: string?, duration: number?)
	local style = KINDS[kind or "info"] or KINDS.info
	order += 1

	local message = `{style.Icon}  {text}`
	local width = if touch then TOUCH_WIDTH else WIDTH
	local size = if touch then TOUCH_TEXT else TEXT
	local padX = if touch then TOUCH_PAD_X else PAD_X
	local padY = if touch then TOUCH_PAD_Y else PAD_Y
	local lines = UIKit.TextLines(message, size, Theme.Fonts.Bold, width - 2 * padX)
	local height = lines * size + 2 * padY + 4
	local toast = UIKit.Panel({
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = if newestLast then order else -order,
		BackgroundTransparency = 0.05,
		CornerRadius = 14,
		Parent = stack,
	}, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	UIKit.new("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, 8, 1, 0),
		BackgroundColor3 = style.Color,
		BorderSizePixel = 0,
		Parent = toast,
		Children = { UIKit.Corner(6) },
	})
	UIKit.Label({
		Text = message,
		TextSize = size,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(1, 1),
		Parent = toast,
		Children = { UIKit.Padding(padY, padX) },
	})
	table.insert(active, toast)
	while #active > MAX_TOASTS do
		local oldest = table.remove(active, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	UIKit.PopIn(toast, 0.25)

	task.delay(duration or 3.5, function()
		if not toast.Parent then
			return
		end
		UIKit.Tween(toast, 0.3, { BackgroundTransparency = 1 })
		for _, descendant in toast:GetDescendants() do
			if descendant:IsA("TextLabel") then
				UIKit.Tween(descendant, 0.3, { TextTransparency = 1 })
			elseif descendant:IsA("UIStroke") then
				UIKit.Tween(descendant, 0.3, { Transparency = 1 })
			elseif descendant:IsA("Frame") then
				UIKit.Tween(descendant, 0.3, { BackgroundTransparency = 1 })
			end
		end
		task.wait(0.32)
		local index = table.find(active, toast)
		if index then
			table.remove(active, index)
		end
		toast:Destroy()
	end)
end

function NotificationController.Start(context)
	touch = UIKit.IsTouch()
	-- Their own layer: above the HUD (5) and mode HUDs (6), under pop-ups (10).
	local gui = UIKit.new("ScreenGui", {
		Name = "PartyPanicToasts",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 8,
		Parent = context.Hud.Parent,
	})
	if touch then
		newestLast = true
		local holder = UIKit.new("Frame", {
			Name = "ToastArea",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.fromOffset(TOUCH_WIDTH, 300),
			BackgroundTransparency = 1,
			Parent = gui,
		})
		UIKit.AutoScale(holder)
		-- (In the middle a toast's left end reaches the MOVE stick's zone on smaller phones: nothing on
		-- one takes taps, so a thumb starting there still walks. tools/checks: allowed there.)
		holder:SetAttribute("PP_Popup", true)
		stack = UIKit.new("Frame", {
			Name = "Toasts",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = holder,
			Children = {
				UIKit.List(
					Enum.FillDirection.Vertical,
					8,
					Enum.HorizontalAlignment.Center,
					Enum.VerticalAlignment.Bottom
				),
			},
		})
		-- The top of the mode's action buttons (Api.Button holders, beside the jump button) in the
		-- toasts' ScreenGui, or nil when none is showing.
		local playerGui = context.Hud.Parent
		local function actionsTop(): number?
			local top: number? = nil
			for _, other in playerGui:GetChildren() do
				if not (other:IsA("ScreenGui") and other.Enabled and string.sub(other.Name, 1, 9) == "MiniGame_") then
					continue
				end
				for _, child in other:GetChildren() do
					if child:IsA("GuiObject") and child.Visible and string.sub(child.Name, 1, 7) == "Action_" then
						local y = child.AbsolutePosition.Y - gui.AbsolutePosition.Y
						top = if top then math.min(top, y) else y
					end
				end
			end
			return top
		end
		local function lift()
			local top = actionsTop()
			-- tools/checks (gui_dump.luau, ui_render.py) place it the same way on each screen they draw.
			holder:SetAttribute("PP_AboveActions", if top then true else nil)
			if top then
				holder.Position = UDim2.new(0.5, 0, 0, top - ACTION_GAP)
				stack.Position = UDim2.fromScale(0.5, 1)
			else
				holder.Position = UDim2.new(0.5, 0, 1, -8)
				local height = 0
				for name, panelHeight in BOTTOM_PANELS do
					local panel = context.Hud:FindFirstChild(name)
					if panel and panel:IsA("GuiObject") and panel.Visible then
						height = math.max(height, panelHeight)
					end
				end
				stack.Position = UDim2.new(0.5, 0, 1, -height)
			end
			-- Under the rules card there's only room for one: the newest.
			local rules = context.Hud:FindFirstChild("Rules")
			local crowded = rules ~= nil and rules:IsA("GuiObject") and rules.Visible
			for index, toast in active do
				toast.Visible = not crowded or index == #active
			end
		end
		local elapsed = 0
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed > 0.2 then
				elapsed = 0
				lift()
			end
		end)
		lift()
	else
		stack = UIKit.new("Frame", {
			Name = "Toasts",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 8),
			Size = UDim2.fromOffset(WIDTH, 400),
			BackgroundTransparency = 1,
			Parent = gui,
			Children = { UIKit.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right) },
		})
		UIKit.AutoScale(stack, 0.95)
	end

	Remotes.Get("Notify").OnClientEvent:Connect(function(text, kind, duration, topic)
		if type(text) == "string" then
			NotificationController.Show(text, kind, duration, if type(topic) == "string" then topic else nil)
		end
	end)
	for _, name in COVERS do
		Players.LocalPlayer:GetAttributeChangedSignal(name):Connect(function()
			if not covered() and #waiting > 0 then
				task.spawn(release)
			end
		end)
	end
	Modal.AnyOpenChanged:Connect(function(open)
		windowOpen = open
	end)
	-- The round is over for the player (its results, or knocked out): what waited shows, a moment
	-- later (the results card opens as the round ends and holds them on until it closes).
	State.OnPlayingChanged(function()
		if not State.PlayingRound() and #waiting > 0 then
			task.delay(PLAYING_GAP, release)
		end
	end)
end

return NotificationController

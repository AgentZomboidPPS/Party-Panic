-- The lobby's row of chips (owner, asked what keeps players coming back, then: "Can you work on all
-- of that?"): what's on right now (the Halloween party, double coins weekends), the Party Cup's
-- round, the invite button. Each feature adds its own chip here instead of finding its own spot on
-- the screen, so no two of them ever draw on top of each other: the row keeps them side by side in
-- priority order and leaves out the ones that don't fit, lowest priority first.
-- Phones (layout A; owner: "move the ones we keep over more"): one row under the menu's grid in the
-- top right corner, right-aligned with it (the edge ScreenGui, scaled like the grid), each chip a
-- slim face on top of its 40 pt tap area. PC: under
-- the phase banner, below the line of the coins and their pink NEXT reward pill (which a full row
-- reached over at first). It shows in the lobby only: never during a round, the rules card or the
-- results, and not while a level-up or medal card is up (PP_Celebrating: its top reaches the row on
-- PC) or a lobby game has the screen (the HUD's PP_TipsAside: Skee-Ball).
--
--   local chip = LobbyRibbon.Add(context, { Name = "Cup", Priority = 2, OnClick = openStandings })
--   chip:Set("🏆", "CUP 3/5")   -- icon and words; empty words take the chip off the row
--   chip.Button                 -- the chip itself, for extras (a "!" badge, a pulse)
--
-- Priorities: 2 Party Cup, 2.5 Party (owner: "stuff to work on right now is parties."), 3 Invite,
-- 4 Weekly leaderboard. A priority can be a fraction (one between two others): the chips line up by
-- it in tenths. The event and the crates had chips too; with layout A (owner: "We dont need a
-- separate open crate button. I thought we said the event button goes inside of the season button?")
-- the event is the Season hub's tab and the crates are counted on the profile card.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState = require(ReplicatedStorage.Shared.GameState)

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local LobbyRibbon = {}

export type Chip = {
	Name: string,
	Priority: number,
	Button: TextButton,
	Icon: string,
	Text: string,
	Set: (self: Chip, icon: string, text: string) -> (),
}

-- Scaled units (UIKit.AutoScale): phones get 0.62 points per unit. Phones: Height is a chip's face,
-- Hit its tap area (40 pt), Top where the row starts under the menu's grid (in a holder level with
-- the grid's top).
local MENU = Theme.Touch.Menu
local TOUCH = {
	Width = 300,
	Height = 42,
	Hit = 65,
	Text = 20,
	Top = 2 * MENU.Tile + MENU.Gap + 8,
	Pad = 12,
	Gap = 8,
}
-- PC: right under the phase banner (70 tall; its holder sits 10 px from the top and scales the same
-- way), clear of the profile card on the left and the toasts down the right. The banner's status
-- line only shows during a round, when the row is away, so it needs no room here (owner, on the space
-- the row left for it: "Why is there a gap?").
local PC = { Width = 560, Height = 44, Text = 20, Top = 80, Pad = 16, Gap = 10 }
-- Where the row ends (scaled units, in a holder 10 points from the top on PC): what goes just under
-- it lines up with it (CupController's standings moment). Phones: under the top bar in the middle
-- the sit-out switch is what's there (HudController, 72 tall in a holder 4 points down).
LobbyRibbon.Bottom = { Touch = 72, Pc = PC.Top + PC.Height }

local LOBBY = { Waiting = true, Intermission = true, Voting = true, Cleanup = true }

local touch = false
local hud: Instance? = nil
local row: Frame? = nil
local chips: { Chip } = {}

local function size()
	return if touch then TOUCH else PC
end

local function chipWidth(chip: Chip): number
	local s = size()
	local words = if chip.Icon ~= "" then `{chip.Icon} {chip.Text}` else chip.Text
	return math.ceil(UIKit.TextWidth(words, s.Text, Theme.Fonts.Display)) + 2 * s.Pad
end

-- Shows the row when its spot is free, and in it the chips that fit, best first.
local function refresh()
	local frame = row
	if not frame or not hud then
		return
	end
	local phase = GameState.Get("Phase") or "Waiting"
	local player = Players.LocalPlayer
	-- A PLAY AGAIN replay's Cleanup goes straight into its rules card: no lobby to show the row in.
	local replaying = phase == "Cleanup" and (GameState.Get("Replay") or "") ~= ""
	local free = LOBBY[phase]
		and not replaying
		and player:GetAttribute("PP_Celebrating") ~= true
		and hud:GetAttribute("PP_TipsAside") ~= true
	local s = size()
	local used = 0
	local order = table.clone(chips)
	table.sort(order, function(a, b)
		return a.Priority < b.Priority
	end)
	for _, chip in order do
		local wanted = chip.Text ~= ""
		local width = chipWidth(chip)
		local room = used + (if used > 0 then s.Gap else 0) + width
		local fits = wanted and room <= s.Width
		if fits then
			used = room
			chip.Button.Size = UDim2.fromOffset(width, if touch then TOUCH.Hit else s.Height)
		end
		chip.Button.Visible = fits
	end
	local shown = free == true and used > 0
	if shown and not frame.Visible then
		frame.Visible = true
		UIKit.PopIn(frame, 0.3)
	else
		frame.Visible = shown
	end
end

local function build(context)
	touch = UIKit.IsTouch()
	hud = context.Hud
	local s = size()
	local holder
	if touch then
		holder = UIKit.new("Frame", {
			Name = "LobbyRibbon",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -Theme.Touch.Edge, 0, MENU.Top),
			Size = UDim2.fromOffset(s.Width, s.Top + TOUCH.Hit),
			BackgroundTransparency = 1,
			Parent = context.Edge or context.Hud,
		})
	else
		holder = UIKit.new("Frame", {
			Name = "LobbyRibbon",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.fromOffset(s.Width, s.Top + s.Height + 8),
			BackgroundTransparency = 1,
			Parent = context.Hud,
		})
	end
	UIKit.AutoScale(holder)
	row = UIKit.new("Frame", {
		Name = "Row",
		Position = UDim2.fromOffset(0, s.Top),
		Size = UDim2.fromOffset(s.Width, if touch then TOUCH.Hit else s.Height),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = holder,
		Children = {
			UIKit.List(
				Enum.FillDirection.Horizontal,
				s.Gap,
				if touch then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Center
			),
		},
	})
	GameState.Changed("Phase", refresh)
	Players.LocalPlayer:GetAttributeChangedSignal("PP_Celebrating"):Connect(refresh)
	context.Hud:GetAttributeChangedSignal("PP_TipsAside"):Connect(refresh)
	task.delay(3, refresh) -- again once the font has surely loaded (widths measure narrow before)
end

local function set(self: Chip, icon: string, text: string)
	if self.Icon == icon and self.Text == text then
		return
	end
	self.Icon = icon
	self.Text = text
	self.Button.Text = if icon ~= "" then `{icon} {text}` else text
	local words = self.Button:FindFirstChild("Words", true)
	if words and words:IsA("TextLabel") then
		words.Text = self.Button.Text -- (phones: on the chip's face; the tap area's own stay hidden)
	end
	refresh()
end

-- Adds a chip to the row (it starts empty, off the row, until its feature calls chip:Set).
-- `context` is the controllers' start-up context (its Hud is where the row lives).
function LobbyRibbon.Add(
	context,
	options: { Name: string, Priority: number, OnClick: (() -> ())?, Top: Color3?, Bottom: Color3? }
): Chip
	if not row then
		build(context)
	end
	local s = size()
	local top, bottom = options.Top or Theme.Colors.Lavender, options.Bottom or Theme.Colors.Purple
	local button
	if touch then
		button = UIKit.new("TextButton", {
			Name = options.Name,
			Text = "",
			TextTransparency = 1,
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, TOUCH.Hit),
			LayoutOrder = math.round(options.Priority * 10),
			Visible = false,
			Parent = row,
		})
		local face = UIKit.Panel({
			Name = "Face",
			Size = UDim2.new(1, 0, 0, s.Height),
			CornerRadius = s.Height / 2,
			Parent = button,
		}, top, bottom)
		UIKit.Label({
			Name = "Words",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = s.Text,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			Parent = face,
			Children = { UIKit.TextStroke(0.35) },
		})
		if options.OnClick then
			button.Activated:Connect(options.OnClick)
		end
	else
		button = UIKit.Button({
			Name = options.Name,
			Text = "",
			TextSize = s.Text,
			TextWrapped = false,
			Size = UDim2.fromOffset(0, s.Height),
			CornerRadius = "round",
			LayoutOrder = math.round(options.Priority * 10),
			Visible = false,
			Parent = row,
		}, options.OnClick, top, bottom)
	end
	local chip: Chip = {
		Name = options.Name,
		Priority = options.Priority,
		Button = button,
		Icon = "",
		Text = "",
		Set = set,
	}
	table.insert(chips, chip)
	return chip
end

return LobbyRibbon

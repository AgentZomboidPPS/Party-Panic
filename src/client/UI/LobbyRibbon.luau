-- The lobby's row of chips (owner, asked what keeps players coming back, then: "Can you work on all
-- of that?"): what's on right now (the Halloween party, double coins weekends), the Party Cup's
-- round, the invite button. Each feature adds its own chip here instead of finding its own spot on
-- the screen, so no two of them ever draw on top of each other: the row keeps them side by side in
-- priority order and leaves out the ones that don't fit, lowest priority first.
-- Phones: under the top bar in the middle, the first-join tip's spot (the row gives way to the tip,
-- which uses it too), between the profile chip and the menu column; chips are 44 pt tall. PC: under
-- the phase banner, below the line of the coins and their pink NEXT reward pill (which a full row
-- reached over at first). It shows in the lobby only: never during a round, the rules card or the
-- results, not during the vote on phones (the vote cards' spot), and not while a level-up or medal
-- card is up (PP_Celebrating: on phones it's in the same spot, on PC its top reaches the row) or a
-- lobby game has the screen (the HUD's PP_TipsAside: Skee-Ball).
--
--   local chip = LobbyRibbon.Add(context, { Name = "Cup", Priority = 2, OnClick = openStandings })
--   chip:Set("🏆", "CUP 3/5")   -- icon and words; empty words take the chip off the row
--   chip.Button                 -- the chip itself, for extras (a "!" badge, a pulse)
--
-- Priorities: 1 Event (Halloween, double coins), 2 Party Cup, 3 Invite, 4 Weekly leaderboard.

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

-- Scaled units (UIKit.AutoScale): phones get 0.62 points per unit, so a 72-unit chip is 44 pt.
local TOUCH = { Width = 620, Height = Theme.Touch.Target, Text = 24, Top = 4 + 8, Pad = 18, Gap = 10 }
-- PC: under the phase banner (its holder sits 10 px from the top and scales the same way), below
-- the line of the coins and the pink NEXT reward pill beside them (RewardsController), which reaches
-- 129 units down and past where a full row would start; clear of the toasts down the right.
local PC = { Width = 560, Height = 44, Text = 20, Top = 137, Pad = 16, Gap = 10 }
local TOUCH_ROW_Y = 8 -- phones: the row's top in its holder (the first-join tip's spot)

-- Where the row ends (scaled units, in a holder 4 points from the top on phones and 10 on PC, like
-- the row's own): what goes just under it lines up with it (CupController's standings moment).
LobbyRibbon.Bottom = { Touch = TOUCH_ROW_Y + TOUCH.Height, Pc = PC.Top + PC.Height }

local LOBBY = { Waiting = true, Intermission = true, Voting = true, Cleanup = true }
local HIDDEN_ON_PHONES = { Voting = true }

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
		and not (touch and HIDDEN_ON_PHONES[phase])
		and player:GetAttribute("PP_Celebrating") ~= true
		and not (touch and hud:GetAttribute("PP_TipShowing") == true)
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
			chip.Button.Size = UDim2.fromOffset(width, s.Height)
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
	local holder = UIKit.new("Frame", {
		Name = "LobbyRibbon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, if touch then 4 else 10),
		Size = UDim2.fromOffset(s.Width, s.Top - (if touch then 4 else 0) + s.Height + 8),
		BackgroundTransparency = 1,
		Parent = context.Hud,
	})
	UIKit.AutoScale(holder)
	row = UIKit.new("Frame", {
		Name = "Row",
		Position = UDim2.fromOffset(0, if touch then TOUCH_ROW_Y else s.Top),
		Size = UDim2.fromOffset(s.Width, s.Height),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = holder,
		Children = { UIKit.List(Enum.FillDirection.Horizontal, s.Gap, Enum.HorizontalAlignment.Center) },
	})
	GameState.Changed("Phase", refresh)
	Players.LocalPlayer:GetAttributeChangedSignal("PP_Celebrating"):Connect(refresh)
	context.Hud:GetAttributeChangedSignal("PP_TipShowing"):Connect(refresh)
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
	local button = UIKit.Button({
		Name = options.Name,
		Text = "",
		TextSize = s.Text,
		TextWrapped = false,
		Size = UDim2.fromOffset(0, s.Height),
		CornerRadius = "round",
		LayoutOrder = options.Priority,
		Visible = false,
		Parent = row,
	}, options.OnClick, options.Top or Theme.Colors.PanelLight, options.Bottom or Theme.Colors.PanelDark)
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

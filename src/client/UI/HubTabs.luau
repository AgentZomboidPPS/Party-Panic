-- The season hub (owner: "What if we rolled season/event/quests into one button?"): the season's crate
-- window (Crates/CrateMenu), the event's window (Controllers/EventController) and the quests'
-- (Controllers/QuestController) share one strip of tabs in their title bars, in place of their
-- titles, and one 🎃 button in the menu column (Controllers/HudController, State.OpenScreen "Hub")
-- opens the tab used last (the season's at first). A tab opens its window in the same place, at the
-- same size, with no pop, so the three read as one window. The event's tab is there only while an
-- event is on; a tab with something to claim wears the red "!", and so does the hub's button.
--
--   HubTabs.Attach(modal, "Season")   strip in this window's title bar ("Season" | "Event" | "Quests")
--   HubTabs.SetEvent(icon, name)      the event's tab (nil: no event on)
--   HubTabs.SetBadge("Quests", true)  a red "!" on a tab
--   HubTabs.AnyBadge()                whether any tab has one (the hub button's "!")
--   HubTabs.Changed                   fires when a tab or a badge changes
--   HubTabs.Last()                    the screen to open for the hub button

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Seasons = require(ReplicatedStorage.Shared.Seasons)
local Signal = require(ReplicatedStorage.Shared.Signal)

local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Modal)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local HubTabs = {}

export type Key = "Season" | "Event" | "Quests"

HubTabs.Changed = Signal.new()

local ORDER: { Key } = { "Season", "Event", "Quests" }
local SCREENS: { [Key]: string } = { Season = "Crates", Event = "Event", Quests = "Quests" }
-- Each tab's colours when it's the one showing (the others wear the neutral lavender).
local ACTIVE: { [Key]: { Color3 } } = {
	Season = { Theme.Colors.Orange, Color3.fromRGB(205, 92, 24) },
	Event = { Theme.Colors.Pink, Color3.fromRGB(200, 50, 140) },
	Quests = { Theme.Colors.Yellow, Theme.Colors.Orange },
}

local eventIcon: string?, eventName: string? = nil, nil
local badges: { [Key]: boolean } = {}
local last: Key = "Season"
local strips: { { Modal: any, Key: Key, Frame: Frame } } = {}

local function label(key: Key): string
	if key == "Season" then
		return `🍂 {string.upper(Seasons.CurrentSeason().Name)}`
	elseif key == "Event" then
		return `{eventIcon or "🎃"} {string.upper(eventName or "EVENT")}`
	end
	return "📜 QUESTS"
end

local function shown(): { Key }
	local keys: { Key } = {}
	for _, key in ORDER do
		if key ~= "Event" or eventName ~= nil then
			table.insert(keys, key)
		end
	end
	return keys
end

local function draw(strip: { Modal: any, Key: Key, Frame: Frame })
	local touch = UIKit.IsTouch()
	local frame = strip.Frame
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for order, key in shown() do
		local active = key == strip.Key
		local colors = if active then ACTIVE[key] else { Theme.Colors.Lavender, Theme.Colors.Purple }
		local text = label(key)
		local button = UIKit.Button({
			Name = key,
			Text = text,
			TextSize = if touch then 22 else 21,
			TextWrapped = false,
			-- (wide enough for its words: the season's name is the longest)
			Size = UDim2.new(0, 34 + (utf8.len(text) or #text) * (if touch then 14 else 13), 1, 0),
			CornerRadius = 16,
			LayoutOrder = order,
			Parent = frame,
		}, function()
			if key ~= strip.Key then
				HubTabs.Open(key)
			end
		end, colors[1], colors[2])
		if not active then
			button.TextTransparency = 0.12
		end
		UIKit.Label({
			Name = "Badge",
			Text = "!",
			Font = Theme.Fonts.Display,
			TextSize = 18,
			TextWrapped = false,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Colors.Red,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(24, 24),
			Visible = badges[key] == true and not active,
			ZIndex = 24,
			Parent = button,
			Children = { UIKit.Round() },
		})
	end
end

local function redraw()
	for _, strip in strips do
		draw(strip)
	end
	HubTabs.Changed:Fire()
end

-- Puts the hub's tabs in `modal`'s title bar, in place of its title; `key` is this window's tab.
function HubTabs.Attach(modal: any, key: Key)
	local touch = UIKit.IsTouch()
	local titleBar = modal.Window:FindFirstChild("TitleBar")
	if not titleBar then
		return
	end
	local title = titleBar:FindFirstChildOfClass("TextLabel")
	if title then
		title.Visible = false
	end
	local titleHeight = Modal.TitleHeight()
	local height = if touch then Theme.Touch.Target else 50 -- (a thumb's size, like the close button)
	local frame = UIKit.new("Frame", {
		Name = "HubTabs",
		Position = UDim2.fromOffset(18, (titleHeight - height) / 2 + 2),
		-- (clear of the close button on the right)
		Size = UDim2.new(1, -(18 + (if touch then Theme.Touch.Target else 46) + 24), 0, height),
		BackgroundTransparency = 1,
		ZIndex = 23,
		Parent = titleBar,
		Children = { UIKit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) },
	})
	local strip = { Modal = modal, Key = key, Frame = frame }
	table.insert(strips, strip)
	modal.Opened:Connect(function()
		last = key
	end)
	draw(strip)
end

-- Opens a tab's window in place of the one showing.
function HubTabs.Open(key: Key)
	if key == "Event" and eventName == nil then
		key = "Season"
	end
	Modal.SkipNextPop()
	State.OpenScreen:Fire(SCREENS[key])
end

-- The event's tab: its icon and name, or nil when no event is on.
function HubTabs.SetEvent(icon: string?, name: string?)
	if icon == eventIcon and name == eventName then
		return
	end
	eventIcon, eventName = icon, name
	if name == nil and last == "Event" then
		last = "Season"
	end
	redraw()
end

function HubTabs.SetBadge(key: Key, on: boolean)
	if (badges[key] == true) == on then
		return
	end
	badges[key] = on
	redraw()
end

function HubTabs.AnyBadge(): boolean
	for _, key in shown() do
		if badges[key] then
			return true
		end
	end
	return false
end

-- The screen the hub's button opens: the tab used last.
function HubTabs.Last(): string
	local key: Key = if last == "Event" and eventName == nil then "Season" else last
	return SCREENS[key]
end

return HubTabs

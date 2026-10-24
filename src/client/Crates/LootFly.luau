-- Keys and crates won in a round fly into their counters (owner: "Can we make the earning of keys and
-- crates more apparent?"). The results card shows what a round gave (ResultsController); when it
-- closes, the crate and the keys fly from the middle of the screen into where they're counted: the
-- 🔑 and 📦 pills under the coins on PC (HudController), the lobby's crate chip on phones
-- (CrateController). Each one that lands pops its counter and ticks the number up.
--
-- Until they land, the counters keep showing what the player had before the round (Hold / Shown),
-- so the number goes up as the loot arrives instead of while the card is still covering it.
--
--   LootFly.Target("Keys", pill, 1)       -- where keys land (the lowest order that's on screen)
--   LootFly.Hold("Keys", 3, 8)            -- 3 keys on their way; 8 once they've all landed
--   LootFly.Shown("Keys", profile.Keys)   -- the number a counter should show now
--   LootFly.Fly()                         -- send everything held (the card closed)
--   LootFly.Changed:Connect(redraw)       -- a held number changed: redraw the counters

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local CrateTheme = require(script.Parent.CrateTheme)

local LootFly = {}

export type Kind = "Keys" | "Crates"

LootFly.Changed = Signal.new()
LootFly.OnLand = nil :: ((kind: Kind) -> ())? -- a sound and a buzz for each one (CrateController)

local PICTURE = { Keys = "Key", Crates = "Crate" }
local COLOR = { Keys = Color3.fromRGB(150, 225, 255), Crates = Color3.fromRGB(255, 190, 110) }
local MOST = 5 -- pictures in flight for one kind (more keys than this land in bigger steps)
-- Seconds to wait for somewhere to land: the phones' crate chip is on the lobby's row, which comes
-- back once the Results phase is over (a card closed early waits for it).
local WAIT_FOR_TARGET = 15
local HOLD_FOR = 45 -- seconds: a hold that's never flown (the card never closed) lets go by itself

type Hold = { Left: number, Final: number, Since: number }
type Target = { Gui: GuiObject, Order: number }

local holds: { [string]: Hold } = {}
local targets: { [string]: { Target } } = { Keys = {}, Crates = {} }
local flying = false

local function release(kind: string, amount: number?)
	local hold = holds[kind]
	if not hold then
		return
	end
	hold.Left -= amount or hold.Left
	if hold.Left <= 0 then
		holds[kind] = nil
	end
	LootFly.Changed:Fire(kind)
end

-- Whether `gui` is on screen: it and everything above it visible, in an enabled ScreenGui.
local function onScreen(gui: GuiObject): boolean
	if gui.AbsoluteSize.X < 2 then
		return false
	end
	local node: Instance? = gui
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		elseif node:IsA("ScreenGui") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

local function targetFor(kind: string): GuiObject?
	local best: Target? = nil
	for _, target in targets[kind] do
		if target.Gui.Parent and onScreen(target.Gui) and (not best or target.Order < best.Order) then
			best = target
		end
	end
	return if best then best.Gui else nil
end

-- Where `kind` lands: `order` picks between several on screen at once (the lowest wins).
function LootFly.Target(kind: Kind, gui: GuiObject, order: number?)
	table.insert(targets[kind], { Gui = gui, Order = order or 1 })
end

-- `count` of `kind` are on their way; the counter reads `final` once they've all landed.
function LootFly.Hold(kind: Kind, count: number, final: number)
	count = math.floor(count)
	if count <= 0 then
		return
	end
	holds[kind] = { Left = count, Final = math.floor(final), Since = os.clock() }
	LootFly.Changed:Fire(kind)
	task.delay(HOLD_FOR, function()
		local hold = holds[kind]
		if hold and os.clock() - hold.Since >= HOLD_FOR - 0.5 then
			release(kind)
		end
	end)
end

-- The number a counter shows now: the profile's, less what's still in flight.
function LootFly.Shown(kind: Kind, actual: number): number
	local hold = holds[kind]
	if not hold then
		return actual
	end
	return math.max(0, math.min(actual, hold.Final - hold.Left))
end

-- "+3" beside a counter as the last one lands, drifting up as it fades.
local function plus(layer: Frame, at: Vector2, text: string, color: Color3)
	local label = UIKit.Label({
		Text = text,
		Font = Theme.Fonts.Display,
		TextSize = 30,
		TextWrapped = false,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(90, 36),
		ZIndex = 62,
		Parent = layer,
		Children = { UIKit.TextStroke(0.1) },
	})
	UIKit.PopIn(label, 0.3)
	UIKit.Tween(label, 1.1, { Position = UDim2.fromOffset(at.X, at.Y - 30) })
	task.delay(0.6, function()
		UIKit.Tween(label, 0.5, { TextTransparency = 1 })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			UIKit.Tween(stroke, 0.5, { Transparency = 1 })
		end
	end)
end

-- One kind's pictures: out of the middle in a burst, then each curving into the counter.
local function flyKind(kind: Kind, target: GuiObject, delay: number): number
	local hold = holds[kind]
	if not hold then
		return 0
	end
	local screen = target:FindFirstAncestorOfClass("ScreenGui")
	if not screen then
		release(kind)
		return 0
	end
	local total = hold.Left
	local pictures = math.min(total, MOST)
	-- A layer over the counter's own screen, so both are measured the same way (insets, safe areas).
	local layer = UIKit.new("Frame", {
		Name = "LootFly",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 60,
		Parent = screen,
	})
	local origin = layer.AbsolutePosition
	local middle = layer.AbsoluteSize / 2
	local size = math.clamp(math.floor(layer.AbsoluteSize.Y * 0.13), 48, 84)
	local landed = 0
	for index = 1, pictures do
		local holder = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(middle.X, middle.Y),
			Size = UDim2.fromOffset(size, size),
			ZIndex = 61,
			Parent = layer,
		})
		holder.Visible = false
		local picture = CrateTheme.Picture(PICTURE[kind], holder)
		picture.ZIndex = 61 -- (over everything, whichever way the screen sorts)
		local spread = (index - (pictures + 1) / 2) * size * 0.75
		local burst = middle + Vector2.new(spread, -size * 0.6 + math.random(-10, 10))
		task.delay(delay + (index - 1) * 0.11, function()
			holder.Visible = true
			UIKit.PopIn(holder, 0.25)
			UIKit.Tween(holder, 0.3, { Position = UDim2.fromOffset(burst.X, burst.Y) }, Enum.EasingStyle.Back)
			task.wait(0.32)
			-- The counter can move while they fly (the lobby's row settling): aim at where it is now.
			local start = os.clock()
			local from = burst
			local bend = Vector2.new(0, -size * 1.2)
			local time = 0.55
			while true do
				local t = math.min(1, (os.clock() - start) / time)
				local goal = target.AbsolutePosition - origin + target.AbsoluteSize / 2
				local ease = t * t
				local straight = from:Lerp(goal, ease)
				local point = straight + bend * (4 * ease * (1 - ease))
				holder.Position = UDim2.fromOffset(point.X, point.Y)
				holder.Size = UDim2.fromOffset(size * (1 - 0.55 * ease), size * (1 - 0.55 * ease))
				if t >= 1 then
					break
				end
				task.wait()
			end
			holder:Destroy()
			landed += 1
			-- Each lands its share; the last one whatever's left.
			local step = if landed == pictures
				then (holds[kind] and holds[kind].Left or 0)
				else math.floor(total / pictures)
			release(kind, step)
			if target.Parent then
				UIKit.PopIn(target, 0.3)
			end
			if LootFly.OnLand then
				LootFly.OnLand(kind)
			end
			if landed == pictures then
				local beside = target.AbsolutePosition
					- origin
					+ Vector2.new(target.AbsoluteSize.X + 6, target.AbsoluteSize.Y / 2)
				plus(layer, beside, `+{total}`, COLOR[kind])
				task.delay(1.4, function()
					layer:Destroy()
				end)
			end
		end)
	end
	return delay + (pictures - 1) * 0.11 + 0.9
end

-- Sends everything held to its counter (the results card just closed). Anything with nowhere to go
-- on screen, or with effects turned down, just counts up where it is.
function LootFly.Fly()
	if flying or next(holds) == nil then
		return
	end
	flying = true
	task.spawn(function()
		task.wait(0.35)
		local waited = 0
		while waited < WAIT_FOR_TARGET and not (targetFor("Crates") or targetFor("Keys")) do
			waited += task.wait(0.2)
		end
		local delay = 0
		for _, kind in { "Crates", "Keys" } :: { Kind } do
			local target = targetFor(kind)
			if not holds[kind] then
				continue
			elseif not target or State.ReducedEffects() or Players.LocalPlayer:GetAttribute("PP_ResultsShowing") then
				release(kind)
				if target then
					UIKit.PopIn(target, 0.3)
				end
			else
				delay = math.max(0, flyKind(kind, target, delay) - 0.5)
			end
		end
		flying = false
	end)
end

return LootFly

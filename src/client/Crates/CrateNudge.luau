-- The profile card's 📦 pill asks to be opened (owner: "we need a way to push players to open crates
-- if they have never opened any. can we make it flashy but elegant?"; HudController puts it on the
-- pill, phones and PC alike):
--   * a crate and a key to open it with: a warm halo behind the pill, breathing (the lobby's crate
--     chip glowed like this until layout A took the chip away);
--   * and never opened one yet (every season's Opened is 0): the pill says OPEN! on a gold tag where
--     its count was (the crate window has the count), bobbing, the crate beside it giving a little
--     shake now and then, and the first time it comes up each session a burst of sparkles round the
--     pill. Their first crate opened, it's the count again and just the halo.
-- What the pill counts is what's landed (Crates/LootFly), so a round's first crate and key only
-- start it once they've flown in. With reduced effects it holds still: the halo and the tag, no
-- motion.
--
--   CrateNudge.Attach(pill, icon, count)   -- the pill (a sibling halo goes behind it), its 📦 and its number

local RunService = game:GetService("RunService")

local Seasons = require(game:GetService("ReplicatedStorage").Shared.Seasons)

local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local LootFly = require(script.Parent.LootFly)

local CrateNudge = {}

local HALO = 6 -- scaled units round the pill
local SHAKE_EVERY = 2.6 -- seconds between the crate's shakes
local SPARKLES = 8

-- Crates opened over every season (the profile's Seasons, as CrateService counts them).
local function lifetimeOpened(profile: any): number
	local total = 0
	for _, progress in if type(profile.Seasons) == "table" then profile.Seasons else {} do
		if type(progress) == "table" then
			total += progress.Opened or 0
		end
	end
	return total
end

-- Whether there's a crate to open (and a key to open it with), and whether it'd be their first.
local function wants(): (boolean, boolean)
	local profile = State.Profile
	if not profile then
		return false, false
	end
	local crates = LootFly.Shown("Crates", if profile.Crates then profile.Crates.Count or 0 else 0)
	local keys = LootFly.Shown("Keys", profile.Keys or 0)
	local canOpen = crates > 0 and keys > 0
	return canOpen, canOpen and lifetimeOpened(profile) == 0
end

-- Sparkles flying out of the pill's middle and fading.
local function burst(pill: GuiObject)
	for index = 1, SPARKLES do
		local angle = (index - 1) / SPARKLES * math.pi * 2 + math.random() * 0.4
		local sparkle = UIKit.Label({
			Name = "Sparkle",
			Text = "✨",
			TextSize = 22,
			TextWrapped = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(26, 26),
			ZIndex = 6,
			Parent = pill,
		})
		local reach = 44 + math.random() * 22
		UIKit.Tween(sparkle, 0.7, {
			Position = UDim2.new(0.5, math.cos(angle) * reach, 0.5, math.sin(angle) * reach * 0.7),
			TextTransparency = 1,
			Rotation = math.random(-60, 60),
		})
		task.delay(0.75, function()
			sparkle:Destroy()
		end)
	end
end

function CrateNudge.Attach(pill: GuiObject, icon: GuiObject, count: GuiObject)
	local amber = Seasons.CurrentSeason().Colors.Glow
	local halo = UIKit.new("Frame", {
		Name = "CrateHalo",
		AnchorPoint = pill.AnchorPoint,
		Position = pill.Position - UDim2.fromOffset(HALO, HALO),
		Size = pill.Size + UDim2.fromOffset(2 * HALO, 2 * HALO),
		BackgroundColor3 = Color3.fromRGB(amber[1], amber[2], amber[3]),
		BackgroundTransparency = 0.45,
		ZIndex = pill.ZIndex - 1, -- (behind the pill, in front of what it sits on)
		Visible = false,
		Parent = pill.Parent,
		Children = { UIKit.Round() },
	})
	-- (In the count's place, beside the crate.)
	local tag = UIKit.new("Frame", {
		Name = "OpenTag",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, count.Position.X.Offset - 4, 0.5, 0),
		Size = UDim2.new(1, -(count.Position.X.Offset - 4) - 4, 0, 28),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 5,
		Visible = false,
		Parent = count.Parent,
		Children = {
			UIKit.Round(),
			UIKit.Gradient(Theme.Colors.Yellow, Theme.Colors.Orange),
			UIKit.Stroke(Color3.new(1, 1, 1), 2, 0.1),
		},
	})
	UIKit.Label({
		Text = "OPEN!",
		Font = Theme.Fonts.Display,
		TextSize = Theme.Touch.MinText,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = tag,
		Children = { UIKit.TextStroke(0.2) },
	})

	local burstShown = false
	local first = false
	local function refresh()
		local canOpen, firstCrate = wants()
		halo.Visible = canOpen
		tag.Visible = firstCrate
		count.Visible = not firstCrate
		first = firstCrate
		if firstCrate and not burstShown and pill.Visible and not State.ReducedEffects() then
			burstShown = true
			task.defer(burst, pill)
			UIKit.PopIn(pill, 0.4)
		end
	end
	State.ProfileChanged:Connect(refresh)
	LootFly.Changed:Connect(refresh)
	refresh()

	-- The motion: the halo breathing, the tag bobbing, the crate's shake.
	local tagRest = tag.Position
	local nextShake = os.clock() + SHAKE_EVERY
	RunService.Heartbeat:Connect(function()
		if not halo.Visible or State.ReducedEffects() then
			return
		end
		local now = os.clock()
		halo.BackgroundTransparency = 0.35 + 0.4 * (0.5 + 0.5 * math.sin(now * 3))
		if not first then
			return
		end
		tag.Position = tagRest + UDim2.fromOffset(0, -2 * math.abs(math.sin(now * 3.4)))
		if now >= nextShake then
			nextShake = now + SHAKE_EVERY
			task.spawn(function()
				for _, angle in { 12, -10, 7, -4, 0 } do
					UIKit.Tween(icon, 0.07, { Rotation = angle })
					task.wait(0.07)
				end
			end)
		end
	end)
end

return CrateNudge

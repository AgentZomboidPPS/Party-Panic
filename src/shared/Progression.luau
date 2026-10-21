-- The Rewards Road, the career milestones and the prestige colors, as the HUD, the Rewards screen,
-- the celebrations and the name tags show them (owner: "Also we need cool payoffs for players that
-- keep playing the game."). The rules live in Logic/ProgressionLogic; the exclusive cosmetics are
-- the Cosmetics with an UnlockLevel (the road) or an UnlockStat (the career milestones).

local Config = require(script.Parent.Config)
local Cosmetics = require(script.Parent.Cosmetics)
local LevelCurve = require(script.Parent.Logic.LevelCurve)
local ProgressionLogic = require(script.Parent.Logic.ProgressionLogic)

local Progression = {}

Progression.MaxLevel = LevelCurve.MaxLevel

-- Road -------------------------------------------------------------------------------------------

local byLevel: { [number]: { Cosmetics.Cosmetic } } = {}
local milestones: { Cosmetics.Cosmetic } = {}
for _, item in Cosmetics.List do
	if item.UnlockLevel then
		local list = byLevel[item.UnlockLevel] or {}
		byLevel[item.UnlockLevel] = list
		table.insert(list, item)
	elseif item.UnlockStat then
		table.insert(milestones, item)
	end
end
-- On each level, trails first (the most visible), then titles, effects and emotes.
local SLOT_ORDER = { Trail = 1, Title = 2, Victory = 3, Elimination = 4, Emote = 5 }
for _, list in byLevel do
	table.sort(list, function(a, b)
		local sa, sb = SLOT_ORDER[a.Slot] or 9, SLOT_ORDER[b.Slot] or 9
		return if sa == sb then a.Id < b.Id else sa < sb
	end)
end

-- The exclusive cosmetics reaching this level unlocks (the first is the one to show off).
function Progression.ItemsAt(level: number): { Cosmetics.Cosmetic }
	return byLevel[level] or {}
end

-- Coins the road pays for reaching this level.
function Progression.Coins(level: number): number
	return ProgressionLogic.LevelCoins(level, Config.Road)
end

-- The next level above `level` with an exclusive cosmetic (nil once they're all unlocked).
function Progression.NextItemLevel(level: number): number?
	for candidate = math.max(1, level) + 1, LevelCurve.MaxLevel do
		if byLevel[candidate] then
			return candidate
		end
	end
	return nil
end

-- The levels the Rewards screen shows a player at `current`: every level near them (2 back, 12
-- ahead), every level with an exclusive reward (the ones they have and the goals) and every 10th
-- (a new name tag color). The levels in between pay coins too; the screen says so.
function Progression.RoadLevels(current: number): { number }
	local levels = {}
	for level = 2, LevelCurve.MaxLevel do
		local near = level >= current - 2 and level <= current + 12
		if near or byLevel[level] or level % 10 == 0 then
			table.insert(levels, level)
		end
	end
	return levels
end

-- Total XP a player needs to reach this level.
function Progression.XPFor(level: number): number
	return LevelCurve.TotalXPForLevel(level)
end

-- Career milestones ------------------------------------------------------------------------------

-- Every cosmetic unlocked by a lifetime stat, in catalog order.
Progression.Milestones = milestones

-- How far along a milestone is: the stat now (capped at the target) and the target.
function Progression.MilestoneProgress(item: Cosmetics.Cosmetic, stats: { [string]: any }?): (number, number)
	local unlock = item.UnlockStat
	if not unlock then
		return 0, 1
	end
	local have = tonumber(stats and stats[unlock.Stat]) or 0
	return math.min(have, unlock.Value), unlock.Value
end

-- Prestige ---------------------------------------------------------------------------------------

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

export type Look = {
	Index: number,
	Name: string,
	Icon: string,
	Level: number, -- the tier's first level
	Gradient: ColorSequence, -- the level badge
	Text: Color3, -- the level on a name tag
	Rainbow: boolean, -- the top tier: shimmers
}

local looks: { Look } = {}
for index, tier in ProgressionLogic.Tiers do
	local keypoints = {}
	for position, rgb in tier.Colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((position - 1) / (#tier.Colors - 1), color(rgb)))
	end
	table.insert(looks, {
		Index = index,
		Name = tier.Name,
		Icon = tier.Icon,
		Level = tier.Level,
		Gradient = ColorSequence.new(keypoints),
		Text = color(tier.Text),
		Rainbow = #tier.Colors > 2,
	})
end
Progression.Looks = looks

function Progression.Look(level: number): Look
	return looks[ProgressionLogic.TierIndex(level)]
end

-- The look after this level's (nil at the top).
function Progression.NextLook(level: number): Look?
	return looks[ProgressionLogic.TierIndex(level) + 1]
end

-- A name tag's first line: "Name  ⭐Lv 12" with the level in its tier's color (rich text), and for
-- the gold and rainbow tiers a gradient for the whole line.
function Progression.NameTag(name: string, level: number): (string, ColorSequence?)
	local look = Progression.Look(level)
	local escaped = name:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	local levelText = `{look.Icon}Lv {level}`
	if look.Index >= 5 then
		return `{escaped}  {levelText}`, look.Gradient
	end
	return `{escaped}  <font color="#{look.Text:ToHex()}">{levelText}</font>`, nil
end

return Progression

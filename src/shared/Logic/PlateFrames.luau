--!strict
-- The frames round a name tag for crates opened (the crate seasons' design: "Badges and nameplate
-- frames at 10, 50, 100, 250 and 500 crates opened ... Owning all 23 items gives the Frostfall
-- Complete frame"; owner, for Hollow Night: "Also do all of your ideas."). Services/CrateService
-- says which one a player has earned (PP_CrateFrame: the best milestone, every season's crates
-- together; PP_SeasonComplete: a season whose 23 items are all theirs), Shared/NameTag draws it.
--
-- Bronze, silver and gold are a plain rim; ember (250) glows in the season's colours; HARVEST MOON
-- (500) sweeps gold across its rim now and then; a season's COMPLETE frame (the best: it can't be
-- bought with crates alone, only finished) drifts through that season's colours with a leaf at each
-- end. No frame at all below 10 crates, so most tags look as they always have.
-- Leaf module: no requires, no Roblox APIs.

local PlateFrames = {}

export type Frame = {
	Kind: string, -- "Bronze" | "Silver" | "Gold" | "Ember" | "HarvestMoon" | "Complete"
	Colors: { { number } }, -- the rim's colours, {r, g, b}, along it
	Thickness: number, -- the rim, in pixels of the 220 x 54 tag
	Shimmer: string?, -- the rim moves: "Sweep" (a glint now and then) or "Drift" (its colours sway)
	Ends: string?, -- what sits at each end of the frame: "Leaf" or "Ember"
	Backing: number, -- how see-through the dark fill behind the words is (1: none)
}

-- By the crates opened: the best milestone reached picks the frame.
local BY_MILESTONE: { [number]: Frame } = {
	[10] = { Kind = "Bronze", Colors = { { 214, 140, 76 }, { 150, 86, 40 } }, Thickness = 2, Backing = 0.62 },
	[50] = { Kind = "Silver", Colors = { { 236, 240, 248 }, { 156, 166, 186 } }, Thickness = 2, Backing = 0.6 },
	[100] = { Kind = "Gold", Colors = { { 255, 226, 120 }, { 214, 132, 18 } }, Thickness = 2.5, Backing = 0.58 },
	[250] = {
		Kind = "Ember",
		Colors = { { 255, 214, 120 }, { 255, 138, 42 }, { 200, 50, 42 } },
		Thickness = 2.5,
		Ends = "Ember",
		Backing = 0.55,
	},
	[500] = {
		Kind = "HarvestMoon",
		Colors = { { 255, 243, 210 }, { 255, 196, 92 }, { 255, 106, 31 }, { 255, 196, 92 }, { 255, 243, 210 } },
		Thickness = 3,
		Shimmer = "Sweep",
		Ends = "Ember",
		Backing = 0.5,
	},
}

-- A season's complete frame, in its colours (Shared/Seasons' Colors).
local function complete(colors: { [string]: { number } }): Frame
	return {
		Kind = "Complete",
		Colors = { colors.Gold, colors.Main, colors.Crimson, colors.Main, colors.Gold },
		Thickness = 3,
		Shimmer = "Drift",
		Ends = "Leaf",
		Backing = 0.45,
	}
end

PlateFrames.Milestones = { 10, 50, 100, 250, 500 } -- (Logic/CrateLogic.Milestones)

-- The frame for a tag: `milestone` the best one reached (0 below the first), `seasonColors` the
-- colours of a season they've completed (nil if none). Nil: no frame.
function PlateFrames.For(milestone: number?, seasonColors: { [string]: { number } }?): Frame?
	if seasonColors and seasonColors.Main and seasonColors.Gold and seasonColors.Crimson then
		return complete(seasonColors)
	end
	local best: Frame? = nil
	for _, mark in PlateFrames.Milestones do
		if (milestone or 0) >= mark then
			best = BY_MILESTONE[mark]
		end
	end
	return best
end

return PlateFrames

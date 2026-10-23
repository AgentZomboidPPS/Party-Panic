-- Images for the crate seasons (Shared/Seasons): uploaded once by tools/meshgen/season/art.py, which
-- fills these in. "" means not uploaded yet: everything that uses one has a plain stand-in (a
-- built-in particle, an emoji), so the season works without them.
--
--   Leaves    a 2 x 2 flipbook of fallen leaves, white (particles tint them): the falling leaves,
--             the leaf heaps' bursts, the Leaf Whirl aura and the Falling Leaves trail
--   Ember     a soft glowing dot: embers off the pile, the title and the Ember Trail
--   Moon      a crescent moon: either side of THE HARVESTER on the name tag
--   Icons     the season's item and crate icons in one sheet (IconCells: each id's cell); the
--             collection log, the odds, the reveal cards and the banners
--   IconSize  the size of one cell in the sheet, in pixels
-- Leaf module: no requires, no Roblox APIs.

return {
	Leaves = "rbxassetid://75255011425315",
	Ember = "rbxassetid://108956217002977",
	Moon = "rbxassetid://123032692789433",
	Icons = "rbxassetid://101398750220380",
	IconSize = 204,
	IconCells = {
		Pet_HarvestOwl = { 0, 0 },
		Pet_EmberStag = { 1, 0 },
		Pet_Gourdian = { 2, 0 },
		Pet_ToadstoolTot = { 3, 0 },
		Pet_LanternWisp = { 4, 0 },
		Hat_LeafCrown = { 0, 1 },
		Hat_Scarecrow = { 1, 1 },
		Hat_AntlerCirclet = { 2, 1 },
		Hat_AcornHelm = { 3, 1 },
		Hat_CrescentMoon = { 4, 1 },
		Aura_LeafWhirl = { 0, 2 },
		Aura_Fireflies = { 1, 2 },
		Aura_LanternRing = { 2, 2 },
		Trail_Embers = { 3, 2 },
		Trail_FallingLeaves = { 4, 2 },
		Trail_WispSteps = { 0, 3 },
		Elim_CrowScatter = { 1, 3 },
		Elim_LeafPile = { 2, 3 },
		Elim_LanternSnuff = { 3, 3 },
		Victory_Bonfire = { 4, 3 },
		Victory_HarvestRain = { 0, 4 },
		Victory_Moonrise = { 1, 4 },
		Title_Harvester = { 2, 4 },
		Crate = { 3, 4 },
		Key = { 4, 4 },
	} :: { [string]: { number } }, -- id -> { column, row } (from 0)
}

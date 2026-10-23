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
	Leaves = "",
	Ember = "",
	Moon = "",
	Icons = "",
	IconSize = 256,
	IconCells = {} :: { [string]: { number } }, -- id -> { column, row } (from 0)
}

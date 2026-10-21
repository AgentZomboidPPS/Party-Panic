-- Props for Honey Trap's storybook meadow. MeshLibrary loads this file at startup (see
-- World/Props/README.md). The meshes come from tools/meshgen/props/HoneyTrap.py; until they're
-- uploaded the Fallback is used.
--
-- Art pass ("make every arena look really cool"): a giant honey oak with a front door, a beehive,
-- a swing and lanterns; a lawn with flower beds, toadstools and a sand crescent; flower pads,
-- picnic baskets, sunflowers and straw beehives. "Mark" pieces mark a prop's true middle, for the
-- props whose bounding box is off-center (Honey Trap places them by it).
return function(h)
	local smooth = Enum.Material.SmoothPlastic
	local wood = Enum.Material.Wood
	local neon = Enum.Material.Neon
	local fabric = Enum.Material.Fabric
	return {
		-- The tree. "Anchor" is the tip of the front branch, where the vine hangs.
		HoneyOak = {
			Height = 64.259,
			AssetId = 0,
			Collide = true,
			Palette = {
				Trunk = h.rgb(139, 94, 62),
				Leaves = h.rgb(98, 190, 86),
				LeavesLight = h.rgb(160, 222, 98),
				Blossoms = h.rgb(255, 192, 218),
				Pollen = h.rgb(255, 214, 70),
				Hive = h.rgb(246, 184, 66),
				Honey = h.rgb(255, 168, 24),
				Hole = h.rgb(62, 38, 26),
				Bark = h.rgb(112, 74, 48),
				Door = h.rgb(224, 98, 72),
				Stone = h.rgb(216, 206, 188),
				Window = h.rgb(255, 214, 120),
				Rope = h.rgb(214, 184, 132),
				Glow = h.rgb(255, 178, 110),
				Anchor = h.rgb(139, 94, 62),
			},
			Materials = {
				Trunk = wood,
				Bark = wood,
				Door = wood,
				Leaves = smooth,
				LeavesLight = smooth,
				Blossoms = smooth,
				Honey = smooth,
				Hive = fabric,
				Rope = fabric,
				Window = neon,
				Glow = neon,
			},
			Fallback = function(m)
				h.pillar(m, "Trunk", 10, 38, Vector3.new(0, 19, 0))
				h.cluster(m, "Leaves", "HoneyOakLeaves", {
					{ 0, 0, 0, 27 },
					{ -12, -4, -1, 20 },
					{ 12, -4, 2, 20 },
					{ 0, -4, 11, 19 },
					{ 0, -4.5, -9, 17 },
				}, Vector3.new(0, 46, 0))
				h.blob(m, "Hive", Vector3.new(6.4, 6.8, 6.4), Vector3.new(10.2, 29.6, 2.3))
				h.rounded(m, "Trunk", Vector3.new(3, 3, 14), 1.4, Vector3.new(0, 30.5, -8))
				h.ball(m, "Anchor", 0.6, Vector3.new(0, 29.6, -14.5))
			end,
		},
		-- The vine the fruit hangs on (the client places it under the branch tip).
		HoneyVine = {
			Height = 25.545,
			AssetId = 0,
			Shadow = false,
			Palette = { Vine = h.rgb(78, 140, 52), VineLeaves = h.rgb(118, 198, 78) },
			Materials = { Vine = smooth, VineLeaves = smooth },
			Fallback = function(m)
				h.pillar(m, "Vine", 0.4, 25.5, Vector3.new(0, 12.75, 0))
			end,
		},
		-- The flower each player stands on (petals are recolored per pad).
		HoneyDaisyPad = {
			Height = 0.413,
			AssetId = 0,
			Shadow = false,
			Palette = {
				Petals = h.rgb(255, 255, 255),
				Center = h.rgb(255, 196, 50),
				Seeds = h.rgb(214, 140, 40),
				Leaves = h.rgb(96, 176, 72),
				Mark = h.rgb(255, 196, 50),
			},
			Materials = { Petals = smooth, Center = smooth, Leaves = smooth },
			Fallback = function(m)
				h.pillar(m, "Petals", 4.8, 0.2, Vector3.new(0, 0.12, 0))
				h.pillar(m, "Center", 2.6, 0.3, Vector3.new(0, 0.18, 0))
				h.ball(m, "Mark", 0.1, Vector3.new(0, 0, 0))
			end,
		},
		HoneyBasket = {
			Height = 1.695,
			AssetId = 0,
			Palette = {
				Basket = h.rgb(190, 132, 74),
				Weave = h.rgb(226, 174, 106),
				Rim = h.rgb(160, 106, 58),
				Cloth = h.rgb(238, 88, 88),
			},
			Materials = { Basket = wood, Weave = wood, Rim = wood, Cloth = fabric },
			Fallback = function(m)
				h.pillar(m, "Basket", 3.4, 1.4, Vector3.new(0, 0.7, 0))
				h.pillar(m, "Rim", 3.8, 0.25, Vector3.new(0, 1.45, 0))
			end,
		},
		-- The clearing: lawn, sand crescent, stepping stones, flower beds, toadstools, tufts.
		HoneyGlade = {
			Height = 2.488,
			AssetId = 0,
			Shadow = false,
			Palette = {
				Lawn = h.rgb(136, 206, 90),
				Sand = h.rgb(240, 208, 142),
				Stones = h.rgb(218, 210, 196),
				FlowerPink = h.rgb(255, 146, 190),
				FlowerWhite = h.rgb(255, 255, 250),
				FlowerLilac = h.rgb(186, 156, 255),
				FlowerMiddles = h.rgb(255, 208, 56),
				Stems = h.rgb(86, 162, 66),
				Caps = h.rgb(232, 66, 60),
				Spots = h.rgb(255, 250, 240),
				Stalks = h.rgb(250, 236, 210),
				Mark = h.rgb(136, 206, 90),
			},
			Materials = {
				Lawn = Enum.Material.Grass,
				Sand = Enum.Material.Sand,
				Stones = smooth,
				FlowerPink = smooth,
				FlowerWhite = smooth,
				FlowerLilac = smooth,
				Caps = smooth,
			},
			Fallback = function(m)
				h.pillar(m, "Lawn", 66, 0.55, Vector3.new(0, -0.075, -4))
				h.ball(m, "Mark", 0.1, Vector3.new(0, 0, 0))
			end,
		},
		-- Tall storybook sunflowers around the meadow, facing the front (-Z).
		HoneySunflower = {
			Height = 14.094,
			AssetId = 0,
			Palette = {
				Stem = h.rgb(92, 160, 62),
				SunLeaves = h.rgb(104, 182, 70),
				SunPetals = h.rgb(255, 204, 40),
				SeedHead = h.rgb(132, 80, 40),
			},
			Materials = { SunPetals = smooth, SunLeaves = smooth },
			Fallback = function(m)
				h.pillar(m, "Stem", 0.5, 11.4, Vector3.new(0, 5.7, 0))
				h.pillar(m, "SunPetals", 0.4, 5, Vector3.new(0, 11.6, -1.2))
			end,
		},
		-- A straw beehive on a stool (entrance at the front, -Z).
		HoneySkep = {
			Height = 5.037,
			AssetId = 0,
			Collide = true,
			Palette = {
				Straw = h.rgb(236, 188, 98),
				Bands = h.rgb(176, 120, 64),
				Entrance = h.rgb(50, 32, 22),
				Stool = h.rgb(150, 100, 62),
			},
			Materials = { Straw = fabric, Stool = wood },
			Fallback = function(m)
				h.pillar(m, "Stool", 4.1, 0.3, Vector3.new(0, 1.3, 0))
				h.blob(m, "Straw", Vector3.new(3.8, 3.6, 3.8), Vector3.new(0, 3.1, 0))
			end,
		},
		-- The 1-or-2 block (the client colors "Block" and writes the number on its sides).
		HoneyDice = {
			Height = 5.16,
			AssetId = 0,
			Palette = {
				Block = h.rgb(255, 210, 60),
				Trim = h.rgb(255, 246, 222),
				Wings = h.rgb(240, 250, 255),
			},
			Materials = { Block = smooth, Trim = smooth, Wings = smooth },
			Fallback = function(m)
				h.rounded(m, "Block", Vector3.new(4, 4, 4), 0.7, Vector3.new(0, 2, 0))
			end,
		},
	}
end

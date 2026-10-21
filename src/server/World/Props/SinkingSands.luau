-- Props for Sinking Sands (meshes from tools/meshgen/props/SinkingSands.py). The pit and the swirl
-- are positioned by their bounding boxes, which the meshes keep centered on the funnel's axis.
return function(h)
	local sand = h.rgb(238, 198, 128)
	-- The temple's colors: cream sandstone, gold, turquoise paint, royal red cloth, glowing gems.
	local stone = h.rgb(242, 216, 168)
	local gold = h.rgb(255, 198, 52)
	local paint = h.rgb(36, 184, 196)
	local cloth = h.rgb(214, 38, 62)
	local glow = h.rgb(120, 255, 226)
	local Metal, Neon, Sandstone = Enum.Material.Metal, Enum.Material.Neon, Enum.Material.Sandstone
	return {
		-- The desert mesa with the quicksand funnel in its middle. Walkable collision is built by the
		-- mode (invisible parts on the same profile), so the mesh never collides.
		SandPit = {
			Height = 40.4,
			AssetId = 77228243131686,
			Collide = false,
			Shadow = false,
			Palette = {
				Sand = sand,
				Lip = h.rgb(170, 94, 58), -- the danger ring round the hole: darker, redder sand
				Throat = h.rgb(64, 40, 30),
				Cliff = h.rgb(212, 124, 76),
				Strata = h.rgb(240, 186, 130),
			},
			Materials = {
				Sand = Enum.Material.Sand,
				Lip = Enum.Material.Sand,
				Throat = Enum.Material.Sand,
				Cliff = Enum.Material.Sandstone,
				Strata = Enum.Material.Sandstone,
			},
			Fallback = function(m)
				-- The mesa's cliffs as a ring of blocks; the mode shows its sand collision instead.
				for index = 0, 15 do
					local angle = index / 16 * math.pi * 2
					local part = h.block(m, "Cliff", Vector3.new(36, 39.6, 44), Vector3.zero)
					part.CFrame = CFrame.new(math.cos(angle) * 60, 19.8 - index % 2 * 0.1, math.sin(angle) * 60)
						* CFrame.Angles(0, -angle, 0)
					part.Material = Enum.Material.Sandstone
				end
			end,
		},
		-- Light streaks on the funnel in five rings plus the whirl down the throat; the client turns
		-- each ring with the sand.
		SandSwirl = {
			Height = 20.1,
			AssetId = 99423756504362,
			Collide = false,
			Shadow = false,
			Palette = {
				Swirl1 = h.rgb(118, 60, 38), -- the innermost streaks, on the danger ring
				Swirl2 = h.rgb(250, 222, 164),
				Swirl3 = h.rgb(220, 172, 110),
				Swirl4 = h.rgb(250, 224, 168),
				Swirl5 = h.rgb(224, 178, 116),
				Whirl = h.rgb(170, 118, 76),
			},
			Materials = { Whirl = Enum.Material.Sand },
			Fallback = function(m)
				local part = h.block(m, "Swirl5", Vector3.new(1, 1, 1), Vector3.new(0, 0.5, 0))
				part.Transparency = 1
			end,
		},
		SandCoin = {
			Height = 2.3,
			AssetId = 108661375244125,
			Shadow = false,
			Palette = { Coin = h.rgb(255, 196, 40), Emblem = h.rgb(255, 238, 140) },
			Materials = { Coin = Enum.Material.Metal, Emblem = Enum.Material.Neon },
			Fallback = function(m)
				local coin = h.roller(m, "Coin", 2.3, 0.4, Vector3.new(0, 1.15, 0))
				coin.CFrame = CFrame.new(0, 1.15, 0) * CFrame.Angles(0, math.rad(90), 0)
			end,
		},
		SandGem = {
			Height = 1.95,
			AssetId = 81961172880389,
			Shadow = false,
			Palette = { Gem = h.rgb(70, 200, 255) },
			Materials = { Gem = Enum.Material.Glass },
			Fallback = function(m)
				local gem = h.block(m, "Gem", Vector3.new(1.5, 1.5, 1.5), Vector3.new(0, 1, 0))
				gem.CFrame = CFrame.new(0, 1, 0) * CFrame.Angles(math.rad(45), math.rad(45), 0)
			end,
		},
		CoinBag = {
			Height = 3.2,
			AssetId = 74005376971390,
			Shadow = false,
			Palette = { Sack = h.rgb(200, 144, 88), Rope = h.rgb(120, 78, 46), Emblem = h.rgb(255, 204, 50) },
			Materials = { Sack = Enum.Material.Fabric, Emblem = Enum.Material.Metal },
			Fallback = function(m)
				h.blob(m, "Sack", Vector3.new(2.8, 2.6, 2.8), Vector3.new(0, 1.3, 0))
				h.pillar(m, "Rope", 1.1, 0.5, Vector3.new(0, 2.7, 0))
			end,
		},
		GoldenIdol = {
			Height = 3.9,
			AssetId = 91937344897147,
			Palette = { Gold = h.rgb(255, 200, 40), Eyes = h.rgb(60, 235, 160) },
			Materials = { Gold = Enum.Material.Metal, Eyes = Enum.Material.Neon },
			Fallback = function(m)
				h.rounded(m, "Gold", Vector3.new(2.2, 0.8, 2), 0.2, Vector3.new(0, 0.4, 0))
				h.blob(m, "Gold", Vector3.new(1.6, 2, 1.4), Vector3.new(0, 1.8, 0))
				h.ball(m, "Gold", 1.2, Vector3.new(0, 3.2, -0.2))
			end,
		},
		-- A Sand King's royal throne: gold-rimmed dais, a back (low, so the King's camera sees over it) with
		-- a golden sunburst and gem, cat-head armrests and glowing orb posts. The seat stays where the
		-- mode's Seat is.
		SandThrone = {
			Height = 11.2,
			AssetId = 131179636869596,
			Collide = true,
			Palette = { Stone = stone, Gold = gold, Paint = paint, Cushion = h.rgb(200, 60, 60), Glow = glow },
			Materials = {
				Stone = Enum.Material.Sandstone,
				Gold = Enum.Material.Metal,
				Cushion = Enum.Material.Fabric,
				Glow = Enum.Material.Neon,
			},
			Fallback = function(m)
				h.rounded(m, "Stone", Vector3.new(9.6, 1.4, 7.4), 0.3, Vector3.new(0, 0.7, 0))
				h.rounded(m, "Stone", Vector3.new(4.4, 6.8, 1), 0.3, Vector3.new(0, 4.8, 2.6))
				h.rounded(m, "Cushion", Vector3.new(3.6, 1.6, 3), 0.3, Vector3.new(0, 2.6, 0.5))
				for side = -1, 1, 2 do
					h.pillar(m, "Gold", 0.6, 7.8, Vector3.new(side * 4.2, 4.6, 1.9))
					h.ball(m, "Glow", 1.2, Vector3.new(side * 4.2, 9.3, 1.9))
				end
				local sun = h.pillar(m, "Gold", 2.3, 0.45, Vector3.new(0, 9.55, 2.75))
				sun.CFrame = CFrame.new(0, 9.55, 2.75) * CFrame.Angles(math.rad(20), math.rad(90), 0)
			end,
		},
		SandCrown = {
			Height = 1.05,
			AssetId = 105161757060146,
			Shadow = false,
			Palette = { Gold = h.rgb(255, 204, 50), Gems = h.rgb(230, 50, 90) },
			Materials = { Gold = Enum.Material.Metal, Gems = Enum.Material.Neon },
			Fallback = function(m)
				h.pillar(m, "Gold", 1.5, 0.7, Vector3.new(0, 0.35, 0))
			end,
		},
		Cactus = {
			Height = 9.85,
			AssetId = 80365311469214,
			Collide = true,
			Palette = { Cactus = h.rgb(84, 150, 82), Flower = h.rgb(255, 120, 170) },
			Materials = { Cactus = Enum.Material.Grass },
			Fallback = function(m)
				local up = CFrame.Angles(0, 0, math.rad(90))
				h.capsule(m, "Cactus", 9.6, 2, CFrame.new(0, 4.9, 0) * up)
				h.capsule(m, "Cactus", 3.2, 1.1, CFrame.new(-2.1, 5.2, 0) * up)
				h.capsule(m, "Cactus", 2.6, 1.1, CFrame.new(1.8, 6.4, 0) * up)
			end,
		},
		SandRuin = {
			Height = 9,
			AssetId = 131429647301144,
			Collide = true,
			Palette = { Stone = h.rgb(232, 196, 142), Base = h.rgb(204, 160, 108) },
			Materials = { Stone = Enum.Material.Sandstone, Base = Enum.Material.Sandstone },
			Fallback = function(m)
				h.block(m, "Base", Vector3.new(4.6, 1.3, 4.6), Vector3.new(0, 0.65, 0))
				h.pillar(m, "Stone", 2.2, 6.5, Vector3.new(0, 4.5, 0))
			end,
		},
		-- The temple courtyard round the funnel: a curb on the rim, a sun-ray mosaic, gold and turquoise
		-- inlays and paths to the gateways. Flat paving that never collides (the mode's floor does).
		SandMosaic = {
			Height = 0.45,
			AssetId = 124625971567784,
			Shadow = false,
			Palette = {
				Curb = h.rgb(236, 206, 156),
				Tile = h.rgb(250, 230, 190),
				TileDark = h.rgb(232, 184, 112),
				Inlay = gold,
				Accent = paint,
			},
			Materials = { Curb = Sandstone, Tile = Sandstone, TileDark = Sandstone, Inlay = Metal },
			Fallback = function(m)
				local part = h.block(m, "Curb", Vector3.new(1, 0.45, 1), Vector3.new(0, 0.22, 0))
				part.Transparency = 1
			end,
		},
		-- A tall painted column with a royal banner down its front (-Z).
		SandColumn = {
			Height = 27.89,
			AssetId = 116838347727083,
			Collide = true,
			Palette = { Stone = stone, Paint = paint, Gold = gold, Cloth = cloth },
			Materials = { Stone = Sandstone, Gold = Metal, Cloth = Enum.Material.Fabric },
			Fallback = function(m)
				h.block(m, "Stone", Vector3.new(6.2, 2, 6.2), Vector3.new(0, 1, 0))
				h.pillar(m, "Stone", 4, 21, Vector3.new(0, 12.5, 0))
				h.pillar(m, "Paint", 5.6, 3, Vector3.new(0, 24.6, 0))
				h.block(m, "Stone", Vector3.new(6.6, 1.6, 6.6), Vector3.new(0, 27.1, 0))
				h.block(m, "Cloth", Vector3.new(4.2, 13.5, 0.25), Vector3.new(0, 14.4, -2.75))
			end,
		},
		SandColumnBroken = {
			Height = 14.15,
			AssetId = 84462374502012,
			Collide = true,
			Palette = { Stone = stone, Gold = gold },
			Materials = { Stone = Sandstone, Gold = Metal },
			Fallback = function(m)
				h.block(m, "Stone", Vector3.new(6.2, 2, 6.2), Vector3.new(0, 1, 0))
				h.pillar(m, "Stone", 4, 11.5, Vector3.new(0, 7.75, 0))
			end,
		},
		-- A gateway: two columns under a lintel with a turquoise cornice and a gold winged sun.
		SandArch = {
			Height = 32.97,
			AssetId = 84569703748343,
			Collide = true,
			Palette = { Stone = stone, Paint = paint, Gold = gold, Glow = glow },
			Materials = { Stone = Sandstone, Gold = Metal, Glow = Neon },
			Fallback = function(m)
				for side = -1, 1, 2 do
					h.block(m, "Stone", Vector3.new(6.4, 2, 6.4), Vector3.new(side * 9, 1, 0))
					h.pillar(m, "Stone", 4.2, 20, Vector3.new(side * 9, 12, 0))
					h.pillar(m, "Paint", 5.8, 3, Vector3.new(side * 9, 23, 0))
				end
				h.block(m, "Stone", Vector3.new(25.6, 3.6, 6.4), Vector3.new(0, 27.8, 0))
				h.block(m, "Paint", Vector3.new(27.6, 1.8, 8), Vector3.new(0, 30.5, 0))
				h.block(m, "Gold", Vector3.new(20, 2, 0.5), Vector3.new(0, 27.9, -3.4))
			end,
		},
		-- The golden step-temple behind the arena, with its grand stair, obelisks and banners.
		SandTemple = {
			Height = 88.58,
			AssetId = 130718627517346,
			Shadow = false,
			Palette = {
				Stone = stone,
				Steps = h.rgb(250, 230, 192),
				Gold = gold,
				Paint = paint,
				Dark = h.rgb(52, 30, 36),
				Cloth = cloth,
				Glow = glow,
			},
			Materials = {
				Stone = Sandstone,
				Steps = Sandstone,
				Gold = Metal,
				Cloth = Enum.Material.Fabric,
				Glow = Neon,
			},
			Fallback = function(m)
				local tiers = { { 150, 0, 6 }, { 128, 6, 19 }, { 104, 19, 32 }, { 80, 32, 45 }, { 56, 45, 58 } }
				for _, tier in tiers do
					local w, y0, y1 = tier[1], tier[2], tier[3]
					h.block(m, "Stone", Vector3.new(w, y1 - y0, w * 0.86), Vector3.new(0, (y0 + y1) / 2, 12.8))
				end
				h.block(m, "Stone", Vector3.new(34, 10, 30), Vector3.new(0, 63, 12.8))
				h.block(m, "Gold", Vector3.new(18, 18, 18), Vector3.new(0, 77, 12.8))
			end,
		},
		-- A giant cat sphinx in a striped royal headdress, lying with its paws forward (-Z).
		SandSphinx = {
			Height = 36.2,
			AssetId = 81162770836161,
			Shadow = false,
			Palette = {
				Body = h.rgb(242, 198, 122),
				Nemes = gold,
				NemesBlue = h.rgb(40, 96, 214),
				Eyes = h.rgb(60, 235, 160),
				Nose = h.rgb(120, 64, 64),
				Gem = h.rgb(232, 50, 90),
				Plinth = h.rgb(222, 178, 118),
			},
			Materials = { Body = Sandstone, Nemes = Metal, Eyes = Neon, Gem = Neon, Plinth = Sandstone },
			Fallback = function(m)
				h.block(m, "Plinth", Vector3.new(34, 3, 64), Vector3.new(0, 1.5, 0))
				h.blob(m, "Body", Vector3.new(20, 16, 36), Vector3.new(0, 11, 6))
				h.ball(m, "Body", 13, Vector3.new(0, 28, -11))
				h.block(m, "Nemes", Vector3.new(15, 12, 8), Vector3.new(0, 26, -8))
			end,
		},
		-- A far pyramid with a gold capstone (skyline).
		SandPyramid = {
			Height = 59.79,
			AssetId = 136034533145401,
			Shadow = false,
			Palette = { Stone = h.rgb(238, 196, 128), Gold = gold },
			Materials = { Stone = Sandstone, Gold = Metal },
			Fallback = function(m)
				for index = 0, 5 do
					local w = 90 * (1 - index / 6)
					h.block(m, "Stone", Vector3.new(w, 9, w), Vector3.new(0, 4.5 + index * 9, 0))
				end
			end,
		},
		-- A big crescent dune (recolored per dune for depth). Its skirt sits 3 studs below its foot.
		SandDune = {
			Height = 26,
			AssetId = 107954322554378,
			Shadow = false,
			Palette = { Dune = h.rgb(236, 184, 110) },
			Materials = { Dune = Enum.Material.Sand },
			Fallback = function(m)
				local part = h.blob(m, "Dune", Vector3.new(160, 26, 80), Vector3.new(0, 0, 0))
				part.Material = Enum.Material.Sand
			end,
		},
		SandPalm = {
			Height = 21.17,
			AssetId = 96764941109646,
			Collide = true,
			Palette = { Trunk = h.rgb(170, 112, 64), Frond = h.rgb(64, 182, 76), Nut = h.rgb(124, 80, 40) },
			Materials = { Trunk = Enum.Material.Wood },
			Fallback = function(m)
				h.pillar(m, "Trunk", 1.6, 18, Vector3.new(0, 9, 0))
				h.blob(m, "Frond", Vector3.new(14, 3, 14), Vector3.new(0, 18.5, 0))
			end,
		},
		-- An oasis pond with a damp bank, rocks, grass, reeds and lilies (on the desert floor).
		SandOasis = {
			Height = 6.33,
			AssetId = 92709425112819,
			Shadow = false,
			Palette = {
				Water = h.rgb(36, 206, 226),
				Bank = h.rgb(196, 152, 98),
				Rock = h.rgb(200, 150, 106),
				Grass = h.rgb(112, 200, 80),
				Reed = h.rgb(126, 156, 64),
				Lily = h.rgb(255, 130, 190),
			},
			Materials = {
				Water = Enum.Material.Glass,
				Bank = Enum.Material.Sand,
				Rock = Sandstone,
				Grass = Enum.Material.Grass,
			},
			Fallback = function(m)
				local water = h.pillar(m, "Water", 40, 0.6, Vector3.new(0, 0.3, 0))
				water.Material = Enum.Material.Glass
			end,
		},
		-- A heap of treasure: coins, an open chest and big gems.
		SandHoard = {
			Height = 4.77,
			AssetId = 119732771823772,
			Shadow = false,
			Palette = { Gold = gold, Wood = h.rgb(150, 88, 46), Gem = h.rgb(230, 60, 90) },
			Materials = { Gold = Metal, Wood = Enum.Material.Wood, Gem = Neon },
			Fallback = function(m)
				h.blob(m, "Gold", Vector3.new(9, 3, 9), Vector3.new(0, 0.8, 0))
				h.block(m, "Wood", Vector3.new(3.6, 2, 2.4), Vector3.new(1.4, 1, 2.4))
			end,
		},
	}
end

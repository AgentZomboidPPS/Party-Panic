-- Props for Sinking Sands (meshes from tools/meshgen/props/SinkingSands.py). The pit and the swirl
-- are positioned by their bounding boxes, which the meshes keep centered on the funnel's axis.
return function(h)
	local sand = h.rgb(238, 198, 128)
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
		SandThrone = {
			Height = 9.7,
			AssetId = 112007036462495,
			Collide = true,
			Palette = { Stone = h.rgb(226, 182, 124), Gold = h.rgb(255, 198, 50), Cushion = h.rgb(200, 60, 60) },
			Materials = { Stone = Enum.Material.Sandstone, Gold = Enum.Material.Metal, Cushion = Enum.Material.Fabric },
			Fallback = function(m)
				h.rounded(m, "Stone", Vector3.new(7, 1.6, 7), 0.3, Vector3.new(0, 0.8, 0))
				h.rounded(m, "Stone", Vector3.new(3.8, 6.4, 1), 0.3, Vector3.new(0, 4.6, 2.2))
				h.rounded(m, "Cushion", Vector3.new(3.4, 1.6, 3), 0.3, Vector3.new(0, 2.4, 0.6))
				local sun = h.pillar(m, "Gold", 2.6, 0.3, Vector3.new(0, 7.4, 2))
				sun.CFrame = CFrame.new(0, 7.4, 2) * CFrame.Angles(0, math.rad(90), 0)
			end,
		},
		SandCrown = {
			Height = 1.05,
			AssetId = 99276892682303,
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
	}
end

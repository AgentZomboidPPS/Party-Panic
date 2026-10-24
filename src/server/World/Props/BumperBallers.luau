-- Props for Bumper Ballers. MeshLibrary loads this file at startup (see World/Props/README.md).
-- The meshes come from tools/meshgen/props/BumperBallers.py; until they're uploaded the Fallback is
-- used. Balls: Shell takes the rider's color (MeshLibrary.Get Colors), Pattern stays white.
return function(h)
	local ballPalette = { Shell = h.rgb(240, 70, 70), Pattern = h.rgb(248, 248, 248) }
	local ballMaterials = { Shell = Enum.Material.SmoothPlastic, Pattern = Enum.Material.SmoothPlastic }
	return {
		BumperBallGores = {
			Height = 8,
			AssetId = 101756819052049,
			Palette = ballPalette,
			Materials = ballMaterials,
			Fallback = function(m)
				h.ball(m, "Shell", 8, Vector3.new(0, 4, 0))
				h.roller(m, "Pattern", 8.12, 1.2, Vector3.new(0, 4, 0))
			end,
		},
		BumperBallBands = {
			Height = 8,
			AssetId = 124794818084464,
			Palette = ballPalette,
			Materials = ballMaterials,
			Fallback = function(m)
				h.ball(m, "Shell", 8, Vector3.new(0, 4, 0))
				h.pillar(m, "Pattern", 8.12, 1.4, Vector3.new(0, 4, 0))
			end,
		},
		BumperBallDots = {
			Height = 8,
			AssetId = 124123644253149,
			Palette = ballPalette,
			Materials = ballMaterials,
			Fallback = function(m)
				h.ball(m, "Shell", 8, Vector3.new(0, 4, 0))
				for _, offset in { Vector3.yAxis, -Vector3.yAxis, Vector3.xAxis, -Vector3.xAxis } do
					h.ball(m, "Pattern", 2.4, Vector3.new(0, 4, 0) + offset * 3.45)
				end
			end,
		},
		-- The beach ring, striped warning lip, cliffs, surf rocks and foam. The grass top is a part
		-- the mode builds (it's also what the balls roll on); this mesh's top sits 0.15 above it.
		BumperIsland = {
			Height = 14,
			AssetId = 135104412261869,
			Palette = {
				Sand = h.rgb(240, 222, 165),
				StripeRed = h.rgb(232, 62, 62),
				StripeWhite = h.rgb(255, 255, 255),
				Rock = h.rgb(128, 120, 112),
				Foam = h.rgb(245, 252, 255),
			},
			Materials = { Rock = Enum.Material.Slate, Foam = Enum.Material.SmoothPlastic },
			Fallback = function(m)
				h.pillar(m, "Rock", 104, 4, Vector3.new(0, 2, 0))
				h.pillar(m, "Rock", 96, 8, Vector3.new(0, 8, 0))
				h.pillar(m, "Sand", 92, 1.6, Vector3.new(0, 12.9, 0))
			end,
			PostProcess = function(model: Model)
				local foam = model:FindFirstChild("Foam", true)
				if foam and foam:IsA("BasePart") then
					foam.Transparency = 0.25
					foam.CastShadow = false
				end
			end,
		},
		BumperPalm = {
			Height = 18.35,
			AssetId = 119762767657624,
			Palette = {
				Trunk = h.rgb(150, 110, 72),
				Leaves = h.rgb(66, 168, 72),
				Coconuts = h.rgb(110, 74, 40),
			},
			Materials = { Trunk = Enum.Material.Wood },
			Fallback = function(m)
				h.pillar(m, "Trunk", 1.2, 15, Vector3.new(0, 7.5, 0))
				h.blob(m, "Leaves", Vector3.new(12, 3, 12), Vector3.new(0, 15.5, 0))
				h.ball(m, "Coconuts", 1.1, Vector3.new(0.6, 14.4, 0))
			end,
		},
		BumperIslet = {
			Height = 3.57,
			AssetId = 118505733776037,
			Palette = { Sand = h.rgb(240, 222, 165), Rock = h.rgb(128, 120, 112), Grass = h.rgb(90, 180, 80) },
			Materials = { Rock = Enum.Material.Slate },
			Fallback = function(m)
				h.blob(m, "Sand", Vector3.new(20, 6, 20), Vector3.new(0, 0.6, 0))
			end,
		},
		-- The sea floor around the island: a pale sand shelf, a turquoise reef slope and deep blue
		-- beyond, so the water reads shallow-to-deep. Base (y = 0) is 15.2 under the water.
		BumperLagoon = {
			Height = 12.19,
			AssetId = 119357834218953,
			Shadow = false,
			Palette = {
				Shelf = h.rgb(186, 244, 222),
				Reef = h.rgb(58, 204, 206),
				Deep = h.rgb(22, 106, 168),
				Coral = h.rgb(255, 122, 150),
			},
			Materials = { Shelf = Enum.Material.Sand },
			Fallback = function(m)
				h.pillar(m, "Deep", 300, 1.2, Vector3.new(0, 0.6, 0))
				h.pillar(m, "Shelf", 180, 10.7, Vector3.new(0, 5.35, 0))
				h.blob(m, "Coral", Vector3.new(4, 3, 4), Vector3.new(70, 10.7, 0))
			end,
		},
		-- A ring of red and white lane-rope floats (radius 70) that marks the play area from afar.
		BumperFloatLine = {
			Height = 0.86,
			AssetId = 127614857456778,
			Shadow = false,
			Palette = { FloatRed = h.rgb(240, 60, 66), FloatWhite = h.rgb(255, 255, 255), Rope = h.rgb(245, 240, 225) },
			Fallback = function(m)
				for index = 0, 35 do
					local angle = index / 36 * math.pi * 2
					h.ball(
						m,
						if index % 2 == 0 then "FloatRed" else "FloatWhite",
						0.86,
						Vector3.new(math.cos(angle) * 70, 0.43, math.sin(angle) * 70)
					)
				end
			end,
		},
		BumperBuoy = {
			Height = 6.15,
			AssetId = 80967593476667,
			Palette = {
				Red = h.rgb(240, 58, 58),
				White = h.rgb(255, 255, 255),
				Metal = h.rgb(70, 74, 86),
				Lamp = h.rgb(255, 214, 80),
			},
			Materials = { Metal = Enum.Material.Metal, Lamp = Enum.Material.Neon },
			Fallback = function(m)
				h.pillar(m, "Red", 3.2, 3.8, Vector3.new(0, 1.9, 0))
				h.pillar(m, "White", 3.3, 0.9, Vector3.new(0, 2.5, 0))
				h.pillar(m, "Metal", 0.5, 1.8, Vector3.new(0, 4.6, 0))
				h.ball(m, "Lamp", 0.65, Vector3.new(0, 5.82, 0))
			end,
		},
		-- Pool floats bobbing in the lagoon.
		BumperFlamingo = {
			Height = 5.1,
			AssetId = 120009284873587,
			Palette = { Pink = h.rgb(255, 128, 182), Beak = h.rgb(40, 40, 46) },
			Fallback = function(m)
				h.pillar(m, "Pink", 4.9, 1.5, Vector3.new(0, 0.75, 0))
				h.pillar(m, "Pink", 0.8, 3.4, Vector3.new(0, 2.9, -1.9))
				h.ball(m, "Pink", 1.1, Vector3.new(0, 4.55, -2.2))
				h.block(m, "Beak", Vector3.new(0.3, 0.3, 0.8), Vector3.new(0, 4.4, -3))
			end,
		},
		BumperDonutFloat = {
			Height = 1.69,
			AssetId = 134467364506689,
			Palette = { Dough = h.rgb(236, 178, 110), Frosting = h.rgb(255, 136, 204), Sprinkles = h.rgb(80, 205, 255) },
			Fallback = function(m)
				h.pillar(m, "Dough", 5.1, 1.0, Vector3.new(0, 0.5, 0))
				h.pillar(m, "Frosting", 4.6, 0.69, Vector3.new(0, 1.34, 0))
			end,
		},
		BumperLifebuoy = {
			Height = 0.9,
			AssetId = 112895079587760,
			Palette = { Red = h.rgb(240, 58, 58), White = h.rgb(255, 255, 255), Rope = h.rgb(245, 240, 225) },
			Fallback = function(m)
				h.pillar(m, "Red", 4, 0.9, Vector3.new(0, 0.45, 0))
			end,
		},
		-- The beach bar on the party islet: deck on stilts, bamboo counter, thatched roof, bottles.
		BumperTikiBar = {
			Height = 13.9,
			AssetId = 96184342144657,
			Palette = {
				Wood = h.rgb(168, 108, 62),
				Bamboo = h.rgb(222, 196, 112),
				Thatch = h.rgb(232, 184, 96),
				Bottles = h.rgb(60, 200, 168),
				Cups = h.rgb(255, 196, 60),
				Sign = h.rgb(70, 200, 210),
				SignWave = h.rgb(255, 110, 170),
			},
			Materials = { Wood = Enum.Material.Wood, Thatch = Enum.Material.Fabric, Bottles = Enum.Material.Glass },
			Fallback = function(m)
				h.block(m, "Wood", Vector3.new(14, 0.35, 11.5), Vector3.new(0, 1.32, -0.75))
				for _, x in { -5.2, 5.2 } do
					for _, z in { -2.6, 4 } do
						h.pillar(m, "Bamboo", 0.64, 8.2, Vector3.new(x, 5.6, z))
					end
				end
				h.block(m, "Wood", Vector3.new(10.2, 3.35, 1.9), Vector3.new(0, 3.18, -3.35))
				h.block(m, "Thatch", Vector3.new(14.8, 2.7, 12.8), Vector3.new(0, 10.75, 0))
				h.block(m, "Thatch", Vector3.new(8.4, 2.5, 7.2), Vector3.new(0, 12.65, 0))
				h.block(m, "Sign", Vector3.new(7.2, 1.3, 0.3), Vector3.new(0, 9.45, -6.6))
				h.block(m, "SignWave", Vector3.new(6.2, 0.3, 0.2), Vector3.new(0, 9.45, -6.85))
			end,
		},
		BumperTikiTotem = {
			Height = 7.26,
			AssetId = 94904228462477,
			Palette = {
				Wood = h.rgb(150, 96, 58),
				Paint = h.rgb(236, 72, 52),
				Eyes = h.rgb(255, 248, 232),
				Teeth = h.rgb(40, 30, 30),
				Leaves = h.rgb(66, 172, 72),
			},
			Materials = { Wood = Enum.Material.Wood },
			Fallback = function(m)
				h.pillar(m, "Wood", 2.6, 6.45, Vector3.new(0, 3.22, 0))
				h.block(m, "Paint", Vector3.new(1.7, 0.6, 0.4), Vector3.new(0, 2.9, -1.2))
				h.blob(m, "Leaves", Vector3.new(4.5, 1.6, 4.5), Vector3.new(0, 6.46, 0))
			end,
		},
		BumperTikiTorch = {
			Height = 8.55,
			AssetId = 117995362656311,
			Shadow = false,
			Palette = { Bamboo = h.rgb(222, 196, 112), Bowl = h.rgb(120, 80, 45), Flame = h.rgb(255, 150, 40) },
			Materials = { Flame = Enum.Material.Neon },
			Fallback = function(m)
				h.pillar(m, "Bamboo", 0.32, 6, Vector3.new(0, 3, 0))
				h.pillar(m, "Bowl", 1.2, 0.9, Vector3.new(0, 6.3, 0))
				h.blob(m, "Flame", Vector3.new(1, 1.8, 1), Vector3.new(0, 7.65, 0))
			end,
		},
		BumperParasol = {
			Height = 6.7,
			AssetId = 137963524721700,
			Palette = { CanopyA = h.rgb(255, 92, 126), CanopyB = h.rgb(255, 248, 230), Pole = h.rgb(245, 245, 245) },
			Fallback = function(m)
				h.pillar(m, "Pole", 0.18, 6.7, Vector3.new(0, 3.35, 0))
				h.blob(m, "CanopyA", Vector3.new(6.9, 0.9, 6.9), Vector3.new(0, 5.8, 0))
			end,
		},
		-- Big jungle islands on the horizon (beach at y = 6 unscaled).
		BumperFarIslandA = {
			Height = 95.18,
			AssetId = 82796407079713,
			Shadow = false,
			Palette = { Sand = h.rgb(244, 226, 168), Jungle = h.rgb(62, 158, 78), Rock = h.rgb(132, 150, 112) },
			Materials = { Rock = Enum.Material.Slate },
			Fallback = function(m)
				h.blob(m, "Jungle", Vector3.new(180, 95.18, 120), Vector3.new(0, 47.59, 0))
				h.blob(m, "Sand", Vector3.new(200, 12, 140), Vector3.new(0, 4, 0))
			end,
		},
		BumperFarIslandB = {
			Height = 81.96,
			AssetId = 124367681049793,
			Shadow = false,
			Palette = { Sand = h.rgb(244, 226, 168), Jungle = h.rgb(74, 166, 86), Rock = h.rgb(132, 150, 112) },
			Materials = { Rock = Enum.Material.Slate },
			Fallback = function(m)
				h.blob(m, "Jungle", Vector3.new(180, 81.96, 120), Vector3.new(0, 40.98, 0))
				h.blob(m, "Sand", Vector3.new(200, 12, 140), Vector3.new(0, 4, 0))
			end,
		},
	}
end

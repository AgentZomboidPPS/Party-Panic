-- Props for Skate Escape. MeshLibrary loads this file at startup (see World/Props/README.md).
-- The meshes come from tools/meshgen/props/SkateEscape.py; until they're uploaded the Fallback is used.
return function(h)
	local wood = Enum.Material.Wood
	return {
		SkateBoard = {
			Height = 0.825,
			AssetId = 128887480377174,
			Shadow = false,
			Palette = {
				Grip = h.rgb(40, 40, 48),
				Deck = h.rgb(255, 120, 60),
				Trucks = h.rgb(190, 195, 205),
				Wheels = h.rgb(255, 230, 90),
			},
			Materials = { Grip = Enum.Material.Sand, Deck = wood, Trucks = Enum.Material.Metal },
			Fallback = function(m)
				h.rounded(m, "Grip", Vector3.new(1.05, 0.12, 3.7), 0.05, Vector3.new(0, 0.45, 0))
				h.block(m, "Trucks", Vector3.new(0.9, 0.12, 0.2), Vector3.new(0, 0.25, -1.05))
				h.block(m, "Trucks", Vector3.new(0.9, 0.12, 0.2), Vector3.new(0, 0.25, 1.05))
				for _, z in { -1.05, 1.05 } do
					for _, x in { -0.44, 0.44 } do
						h.roller(m, "Wheels", 0.34, 0.16, Vector3.new(x, 0.17, z))
					end
				end
			end,
		},
		SkateCrate = {
			Height = 2.6,
			AssetId = 89347066014266,
			Palette = { Slats = h.rgb(196, 140, 82), Frame = h.rgb(140, 92, 52), Metal = h.rgb(90, 92, 100) },
			Materials = { Slats = wood, Frame = wood, Metal = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "Slats", Vector3.new(4.2, 2.6, 3.4), Vector3.new(0, 1.3, 0))
				h.block(m, "Frame", Vector3.new(4.3, 0.3, 3.5), Vector3.new(0, 2.45, 0))
				h.block(m, "Frame", Vector3.new(4.3, 0.3, 3.5), Vector3.new(0, 0.15, 0))
			end,
		},
		SkateBarrier = {
			Height = 3.6,
			AssetId = 79107194580564,
			Palette = {
				Legs = h.rgb(70, 70, 80),
				Red = h.rgb(235, 60, 60),
				White = h.rgb(250, 250, 250),
				Lamp = h.rgb(255, 170, 40),
			},
			Materials = { Lamp = Enum.Material.Neon, Legs = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "Legs", Vector3.new(0.3, 3.2, 0.3), Vector3.new(-3.05, 1.6, 0))
				h.block(m, "Legs", Vector3.new(0.3, 3.2, 0.3), Vector3.new(3.05, 1.6, 0))
				h.block(m, "White", Vector3.new(7, 1, 0.3), Vector3.new(0, 2.7, 0))
				h.ball(m, "Lamp", 0.5, Vector3.new(0, 3.35, 0))
			end,
		},
		SkateBoost = {
			Height = 0.3,
			AssetId = 129442765777999,
			Shadow = false,
			Palette = { Pad = h.rgb(40, 36, 60), Rim = h.rgb(90, 80, 120), Arrows = h.rgb(255, 220, 60) },
			Materials = { Arrows = Enum.Material.Neon },
			Fallback = function(m)
				h.block(m, "Pad", Vector3.new(6.4, 0.2, 7), Vector3.new(0, 0.1, 0))
				for index = 0, 2 do
					h.block(m, "Arrows", Vector3.new(3, 0.1, 0.6), Vector3.new(0, 0.25, 1.9 - index * 1.9))
				end
			end,
		},
		SkateDeck = {
			Height = 2.045,
			AssetId = 112015498953242,
			Collide = true,
			Palette = {
				Planks = h.rgb(150, 102, 66),
				Beams = h.rgb(96, 64, 44),
				Bolts = h.rgb(70, 70, 76),
				Paint = h.rgb(245, 240, 225),
			},
			Materials = { Planks = Enum.Material.WoodPlanks, Beams = wood, Bolts = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "Planks", Vector3.new(100, 0.45, 24), Vector3.new(0, 1.775, 0))
				h.block(m, "Beams", Vector3.new(96, 1.3, 2), Vector3.new(0, 0.9, 0))
			end,
		},
		SkateRail = {
			Height = 3.675,
			AssetId = 127518926056832,
			Palette = { Posts = h.rgb(110, 74, 48), Rail = h.rgb(130, 88, 56), Rope = h.rgb(210, 180, 130) },
			Materials = { Posts = wood, Rail = wood, Rope = Enum.Material.Fabric },
			Fallback = function(m)
				for _, z in { -9, -3, 3, 9 } do
					h.block(m, "Posts", Vector3.new(0.7, 3.6, 0.7), Vector3.new(0, 1.8, z))
				end
				h.block(m, "Rail", Vector3.new(0.5, 0.4, 24), Vector3.new(0, 3.15, 0))
			end,
		},
		SkateTorch = {
			Height = 4.0,
			AssetId = 88518381598054,
			Palette = { Iron = h.rgb(60, 58, 62), Coals = h.rgb(255, 120, 40) },
			Materials = { Iron = Enum.Material.Metal, Coals = Enum.Material.Neon },
			Fallback = function(m)
				h.pillar(m, "Iron", 0.32, 3.4, Vector3.new(0, 1.7, 0))
				h.ball(m, "Coals", 1, Vector3.new(0, 3.6, 0))
			end,
		},
		SkateArch = {
			Height = 30.8,
			AssetId = 110839506779670,
			Collide = true,
			Palette = {
				Stone = h.rgb(120, 110, 115),
				Trim = h.rgb(80, 64, 60),
				Beam = h.rgb(110, 74, 48),
				Dark = h.rgb(30, 30, 36),
				Light = h.rgb(250, 250, 250),
				Pennant = h.rgb(255, 90, 90),
			},
			Materials = { Stone = Enum.Material.Slate, Beam = wood, Trim = Enum.Material.Slate },
			Fallback = function(m)
				h.block(m, "Stone", Vector3.new(6, 24, 6), Vector3.new(-55.3, 12, 0))
				h.block(m, "Stone", Vector3.new(6, 24, 6), Vector3.new(55.3, 12, 0))
				h.block(m, "Dark", Vector3.new(108, 5.4, 0.4), Vector3.new(0, 19, 0))
				h.block(m, "Beam", Vector3.new(110, 1.4, 1.6), Vector3.new(0, 22.6, 0))
			end,
		},
	}
end

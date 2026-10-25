-- Props for Skate Escape. MeshLibrary loads this file at startup (see World/Props/README.md).
-- The meshes come from tools/meshgen/props/SkateEscape.py; until they're uploaded the Fallback is used.
return function(h)
	local wood = Enum.Material.Wood
	return {
		SkateBoard = {
			Height = 0.825,
			AssetId = 91529705586550,
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
			-- Painted toy colors the deck never uses, so every crate row stands out on the brown planks.
			Palette = { Slats = h.rgb(244, 192, 92), Frame = h.rgb(222, 62, 50), Metal = h.rgb(90, 92, 100) },
			Materials = { Slats = wood, Frame = wood, Metal = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "Slats", Vector3.new(4.2, 2.6, 3.4), Vector3.new(0, 1.3, 0))
				h.block(m, "Frame", Vector3.new(4.3, 0.3, 3.5), Vector3.new(0, 2.45, 0))
				h.block(m, "Frame", Vector3.new(4.3, 0.3, 3.5), Vector3.new(0, 0.15, 0))
			end,
		},
		SkateBarrier = {
			Height = 3.6,
			AssetId = 105085257585720,
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
			AssetId = 114012835317318,
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
			Height = 2.26,
			AssetId = 130808942087961,
			Collide = true,
			-- Keeps Roblox's rough hull (MeshLibrary: preciseCollision): it's one smooth floor at the
			-- planks' top, where precise collision would have every 0.12-stud seam and the boards'
			-- 0.04-stud steps under the skaters' wheels.
			Precise = false,
			Palette = {
				Planks = h.rgb(158, 104, 68),
				PlanksB = h.rgb(124, 82, 56),
				Beams = h.rgb(96, 64, 44),
				CurbRed = h.rgb(236, 66, 54),
				CurbWhite = h.rgb(250, 246, 236),
			},
			Materials = { Planks = Enum.Material.WoodPlanks, PlanksB = Enum.Material.WoodPlanks, Beams = wood },
			Fallback = function(m)
				h.block(m, "Planks", Vector3.new(96, 0.42, 24), Vector3.new(0, 1.79, 0))
				h.block(m, "Beams", Vector3.new(100.4, 1.2, 23.9), Vector3.new(0, 0.98, 0))
				for _, x in { -48.45, 48.45 } do
					h.block(m, "CurbRed", Vector3.new(1.25, 0.26, 23.9), Vector3.new(x, 2.13, 0))
				end
			end,
		},
		SkateRail = {
			Height = 3.65,
			AssetId = 74909258656020,
			Palette = { Posts = h.rgb(110, 74, 48), Rail = h.rgb(140, 94, 58), Rope = h.rgb(228, 194, 136) },
			Materials = { Posts = wood, Rail = wood, Rope = Enum.Material.Fabric },
			Fallback = function(m)
				for _, z in { -9, -3, 3, 9 } do
					h.block(m, "Posts", Vector3.new(0.8, 3.65, 0.8), Vector3.new(0, 1.825, z))
				end
				h.block(m, "Rail", Vector3.new(0.55, 0.42, 24), Vector3.new(0, 3.12, 0))
			end,
		},
		SkateTorch = {
			Height = 4.0,
			AssetId = 101236794696421,
			Palette = { Iron = h.rgb(60, 58, 62), Coals = h.rgb(255, 120, 40) },
			Materials = { Iron = Enum.Material.Metal, Coals = Enum.Material.Neon },
			Fallback = function(m)
				h.pillar(m, "Iron", 0.32, 3.4, Vector3.new(0, 1.7, 0))
				h.ball(m, "Coals", 1, Vector3.new(0, 3.6, 0))
			end,
		},
		-- A 200-stud stretch of the lava canyon's side (faces -Z, foot 2 studs under the lava, top a few
		-- studs under the deck): layered rock bands stepping back as they rise, with two lava falls. Dark
		-- reds, so the lava is the only hot color.
		SkateCanyonWall = {
			Height = 45.21,
			AssetId = 122726475480222,
			Shadow = false,
			Palette = {
				Basalt = h.rgb(60, 42, 50),
				RockLow = h.rgb(118, 50, 52),
				RockMid = h.rgb(176, 84, 72),
				Stripe = h.rgb(222, 150, 118),
				RockTop = h.rgb(150, 70, 64),
				Boulders = h.rgb(100, 56, 52),
				Lava = h.rgb(255, 136, 40),
				Crust = h.rgb(84, 38, 32),
			},
			Materials = {
				Basalt = Enum.Material.Basalt,
				RockLow = Enum.Material.Slate,
				RockMid = Enum.Material.Sandstone,
				Stripe = Enum.Material.Sandstone,
				RockTop = Enum.Material.Sandstone,
				Boulders = Enum.Material.Slate,
				Lava = Enum.Material.Neon,
				Crust = Enum.Material.Basalt,
			},
			Fallback = function(m)
				h.block(m, "Basalt", Vector3.new(200, 7, 64), Vector3.new(0, 3.5, 32))
				h.block(m, "RockLow", Vector3.new(200, 9, 60), Vector3.new(0, 11.5, 34))
				h.block(m, "RockMid", Vector3.new(200, 13, 56), Vector3.new(0, 22.5, 36))
				h.block(m, "Stripe", Vector3.new(200, 3.5, 52.5), Vector3.new(0, 30.75, 37.75))
				h.block(m, "RockTop", Vector3.new(200, 12.7, 51), Vector3.new(0, 38.85, 38.5))
				h.block(m, "Lava", Vector3.new(8, 30, 2), Vector3.new(-52, 15, -5.1))
			end,
		},
		-- A far-off layered mesa on the plateau, for a rugged skyline (low-poly: it's only ever far away).
		SkateButte = {
			AssetId = 112906917689410,
			Height = 42.58,
			Shadow = false,
			Palette = {
				RockLow = h.rgb(118, 50, 52),
				RockMid = h.rgb(176, 84, 72),
				Stripe = h.rgb(222, 150, 118),
				RockTop = h.rgb(150, 70, 64),
				Boulders = h.rgb(100, 56, 52),
			},
			Materials = {
				RockLow = Enum.Material.Slate,
				RockMid = Enum.Material.Sandstone,
				Stripe = Enum.Material.Sandstone,
				RockTop = Enum.Material.Sandstone,
				Boulders = Enum.Material.Slate,
			},
			Fallback = function(m)
				h.block(m, "RockLow", Vector3.new(76, 16.6, 50), Vector3.new(0, 8.3, 0))
				h.block(m, "RockMid", Vector3.new(66, 10, 44), Vector3.new(0, 21.6, 0))
				h.block(m, "Stripe", Vector3.new(62, 3, 41), Vector3.new(0, 28.1, 0))
				h.block(m, "RockMid", Vector3.new(57, 6, 38), Vector3.new(0, 32.6, 0))
				h.block(m, "RockTop", Vector3.new(51, 7, 33), Vector3.new(0, 39.1, 0))
			end,
		},
		-- A stone viaduct pier under the bridge (foot 2 studs under the lava, deck 66 above it) with a
		-- rope tower on each end. Faces -Z.
		SkatePylon = {
			Height = 99.55,
			AssetId = 134758477356231,
			Palette = {
				Stone = h.rgb(220, 190, 152),
				Trim = h.rgb(176, 148, 124),
				Soot = h.rgb(64, 48, 52),
				Timber = h.rgb(132, 86, 52),
				Roof = h.rgb(224, 70, 52),
				Rope = h.rgb(228, 194, 136),
				Iron = h.rgb(60, 58, 62),
				Flag = h.rgb(255, 212, 60),
				Glow = h.rgb(255, 204, 100),
			},
			Materials = {
				Stone = Enum.Material.Sandstone,
				Trim = Enum.Material.Slate,
				Soot = Enum.Material.Basalt,
				Timber = wood,
				Rope = Enum.Material.Fabric,
				Iron = Enum.Material.Metal,
				Glow = Enum.Material.Neon,
			},
			Fallback = function(m)
				for _, x in { -40.25, 40.25 } do
					h.block(m, "Stone", Vector3.new(12, 58.8, 8), Vector3.new(x, 29.4, 0))
				end
				h.block(m, "Trim", Vector3.new(116, 5, 10.4), Vector3.new(0, 61.3, 0))
				for _, x in { -54, 54 } do
					h.block(m, "Stone", Vector3.new(6.4, 6, 6.4), Vector3.new(x, 66.8, 0))
					h.block(m, "Timber", Vector3.new(3.5, 18, 3.5), Vector3.new(x, 78.8, 0))
					h.block(m, "Roof", Vector3.new(5, 4, 5), Vector3.new(x, 91, 0))
					h.block(m, "Iron", Vector3.new(0.3, 6.5, 0.3), Vector3.new(x, 96.3, 0))
				end
			end,
		},
		-- The rope swag between two pylon towers (96 long, stretched to fit), hangers down to the rail.
		SkateCable = {
			Height = 17.59,
			AssetId = 72751985503752,
			Shadow = false,
			Palette = { Rope = h.rgb(228, 194, 136), Hangers = h.rgb(204, 170, 118) },
			Materials = { Rope = Enum.Material.Fabric, Hangers = Enum.Material.Fabric },
			Fallback = function(m)
				h.block(m, "Rope", Vector3.new(0.6, 0.6, 96), Vector3.new(2.3, 8.8, 0))
				h.block(m, "Hangers", Vector3.new(4.75, 17.59, 0.2), Vector3.new(0, 8.8, 48))
			end,
		},
		-- The start gate over all twelve lanes: striped towers, a banner beam and three start lamps.
		SkateStartGate = {
			Height = 38,
			AssetId = 123118841481494,
			Collide = true,
			Palette = {
				Stone = h.rgb(190, 172, 160),
				StripeA = h.rgb(60, 204, 110),
				StripeB = h.rgb(250, 250, 245),
				Beam = h.rgb(124, 80, 50),
				Banner = h.rgb(36, 160, 88),
				Trim = h.rgb(112, 98, 98),
				Housing = h.rgb(34, 32, 40),
				LampRed = h.rgb(255, 64, 56),
				LampAmber = h.rgb(255, 190, 50),
				LampGreen = h.rgb(80, 255, 120),
				Flag = h.rgb(80, 230, 130),
				Iron = h.rgb(60, 58, 62),
			},
			Materials = {
				Stone = Enum.Material.Slate,
				Beam = wood,
				Trim = Enum.Material.Slate,
				Housing = Enum.Material.Metal,
				LampRed = Enum.Material.Neon,
				LampAmber = Enum.Material.Neon,
				LampGreen = Enum.Material.Neon,
				Iron = Enum.Material.Metal,
			},
			Fallback = function(m)
				for _, x in { -57, 57 } do
					h.block(m, "Stone", Vector3.new(9.8, 6.8, 9.8), Vector3.new(x, 3.4, 0))
					h.block(m, "StripeA", Vector3.new(6.2, 23.2, 6.2), Vector3.new(x, 18.4, 0))
					h.block(m, "Iron", Vector3.new(0.36, 8, 0.36), Vector3.new(x, 34, 0))
				end
				h.block(m, "Beam", Vector3.new(108, 2.2, 2.6), Vector3.new(0, 26.8, 0))
				h.block(m, "Banner", Vector3.new(100, 8, 0.8), Vector3.new(0, 21.7, 0))
				h.block(m, "Housing", Vector3.new(16, 6.4, 3), Vector3.new(0, 31.4, 0))
				-- The start lamps (the client lights them red, then green), red on the racers' left.
				for name, x in { LampRed = 5, LampAmber = 0, LampGreen = -5 } do
					h.block(m, name, Vector3.new(3.8, 3.8, 1), Vector3.new(x, 31.4, -1.6))
				end
			end,
		},
		-- The finish: a giant round stone arch with a checkered band, a golden trophy on the keystone
		-- and fire bowls on its feet. Faces -Z.
		SkateFinishArch = {
			Height = 84.2,
			AssetId = 71503248321049,
			Collide = true,
			Palette = {
				Stone = h.rgb(222, 196, 160),
				StoneB = h.rgb(242, 222, 186),
				Trim = h.rgb(150, 126, 110),
				Dark = h.rgb(30, 30, 36),
				Light = h.rgb(250, 250, 250),
				Gold = h.rgb(255, 196, 50),
				Bowl = h.rgb(70, 66, 72),
				Coals = h.rgb(255, 120, 40),
				Flag = h.rgb(255, 84, 84),
				Iron = h.rgb(60, 58, 62),
			},
			Materials = {
				Stone = Enum.Material.Sandstone,
				StoneB = Enum.Material.Sandstone,
				Trim = Enum.Material.Slate,
				Gold = Enum.Material.Metal,
				Bowl = Enum.Material.Metal,
				Coals = Enum.Material.Neon,
				Iron = Enum.Material.Metal,
			},
			Fallback = function(m)
				for _, x in { -57.75, 57.75 } do
					h.block(m, "Stone", Vector3.new(7.5, 58, 8), Vector3.new(x, 29, 0))
					h.block(m, "Trim", Vector3.new(11.5, 3, 12), Vector3.new(x, 1.5, 0))
				end
				h.block(m, "Dark", Vector3.new(127, 7.5, 8.5), Vector3.new(0, 57.75, 0))
				h.block(m, "Gold", Vector3.new(11, 16.2, 11), Vector3.new(0, 76.1, 0))
			end,
		},
	}
end

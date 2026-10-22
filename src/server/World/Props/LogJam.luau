-- Props for Log Jam (meshes from tools/meshgen/props/LogJam.py). A team's sawmill station is a
-- chopping stump in the middle, the log rack on the players' left feeding it and the big axe on its
-- hinge post on their right. The server places these by named pieces whose centres the meshes and the
-- fallbacks share (see the top of LogJam.py), so keep those pieces where they are:
--   LogJamStump     "Top" centred at (0, 2.39, 0): the log lands on it.
--   LogJamLog       "Wood" centred at (0, 1.1, 0): one upright log, the one the placer sends over.
--   LogJamHalf      "Wood" centred at (0, 1.1, -0.4): a split half, flat side facing +Z.
--   LogJamAxe       "Collar" centred on the hinge; the axe lies level, its head 4.6 along -X.
--   LogJamAxeFrame  "Bolt" centred on the hinge, 5.2 up.
--   LogJamRack      "Peg" centred at (-0.3, 1.6, 0); the waiting log lies at (0.45, 2.45, 0).
-- Nothing here collides (owner: "Theres invisible stuff you can jump on and hang on in several
-- games"): players stand on the plain wooden decks the mode builds, and the props are only looked at.

return function(h)
	local rgb = h.rgb
	local Build = h.Build
	local wood = Enum.Material.Wood
	local planks = Enum.Material.WoodPlanks
	local metal = Enum.Material.Metal

	-- A cylinder lying along Z.
	local function alongZ(m: Model, name: string, diameter: number, length: number, position: Vector3): Part
		return Build.Part({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(length, diameter, diameter),
			CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0),
			Parent = m,
		})
	end

	return {
		LogJamStump = {
			Height = 2.53,
			AssetId = 0,
			Palette = {
				Bark = rgb(116, 78, 50),
				Top = rgb(228, 188, 130),
				Rings = rgb(178, 128, 82),
				Cuts = rgb(92, 60, 40),
			},
			Materials = { Bark = wood, Top = wood },
			Fallback = function(m)
				h.pillar(m, "Bark", 3.9, 2.33, Vector3.new(0, 1.165, 0))
				h.pillar(m, "Top", 3.48, 0.12, Vector3.new(0, 2.39, 0))
				h.pillar(m, "Rings", 1.6, 0.06, Vector3.new(0, 2.47, 0))
			end,
		},
		LogJamLog = {
			Height = 2.24,
			AssetId = 0,
			Palette = { Bark = rgb(126, 86, 54), Wood = rgb(232, 196, 140), Rings = rgb(186, 136, 86) },
			Materials = { Bark = wood, Wood = wood },
			Fallback = function(m)
				h.pillar(m, "Bark", 1.76, 2.12, Vector3.new(0, 1.1, 0))
				h.pillar(m, "Wood", 1.56, 2.2, Vector3.new(0, 1.1, 0))
			end,
		},
		LogJamHalf = {
			Height = 2.2,
			AssetId = 0,
			Palette = { Bark = rgb(126, 86, 54), Wood = rgb(238, 204, 150) },
			Materials = { Bark = wood, Wood = wood },
			Fallback = function(m)
				h.block(m, "Bark", Vector3.new(1.7, 2.12, 0.82), Vector3.new(0, 1.1, -0.47))
				h.block(m, "Wood", Vector3.new(1.6, 2.2, 0.8), Vector3.new(0, 1.1, -0.4))
			end,
		},
		LogJamAxe = {
			Height = 1.88,
			AssetId = 0,
			Shadow = true,
			Palette = {
				Handle = rgb(198, 142, 86),
				Grip = rgb(156, 58, 48),
				Collar = rgb(84, 88, 98),
				Bands = rgb(84, 88, 98),
				Head = rgb(116, 124, 138),
				Edge = rgb(236, 240, 248),
			},
			Materials = { Handle = wood, Collar = metal, Bands = metal, Head = metal, Edge = metal },
			Fallback = function(m)
				-- (Fallback y is from the prop's bottom: the hinge sits 1.33 up.)
				alongZ(m, "Collar", 0.84, 0.6, Vector3.new(0, 1.33, 0))
				h.roller(m, "Handle", 0.38, 5.4, Vector3.new(-2.35, 1.33, 0))
				h.block(m, "Head", Vector3.new(1.2, 1.85, 0.3), Vector3.new(-4.6, 0.955, 0))
				h.block(m, "Edge", Vector3.new(1.6, 0.25, 0.14), Vector3.new(-4.6, 0.165, 0))
			end,
		},
		LogJamAxeFrame = {
			Height = 6.1,
			AssetId = 0,
			Palette = {
				Base = rgb(132, 130, 136),
				Post = rgb(150, 100, 62),
				Bolt = rgb(70, 72, 80),
				Plates = rgb(92, 96, 106),
				Spring = rgb(214, 176, 70),
			},
			Materials = { Base = Enum.Material.Slate, Post = wood, Bolt = metal, Plates = metal, Spring = metal },
			Fallback = function(m)
				h.block(m, "Base", Vector3.new(1.9, 0.6, 1.9), Vector3.new(0, 0.3, 0.8))
				h.block(m, "Post", Vector3.new(0.8, 5.6, 0.8), Vector3.new(0, 3.3, 0.85))
				alongZ(m, "Bolt", 0.32, 1, Vector3.new(0, 5.2, 0))
			end,
		},
		LogJamRack = {
			Height = 5.66,
			AssetId = 0,
			Palette = {
				Frame = rgb(140, 94, 58),
				Peg = rgb(104, 70, 44),
				Logs = rgb(120, 82, 52),
				LogEnds = rgb(230, 192, 136),
			},
			Materials = { Frame = wood, Peg = wood, Logs = wood, LogEnds = wood },
			Fallback = function(m)
				h.block(m, "Peg", Vector3.new(0.3, 0.6, 1.6), Vector3.new(-0.3, 1.6, 0))
				h.block(m, "Frame", Vector3.new(4.8, 0.3, 2.0), Vector3.new(2.3, 1.9, 0))
				alongZ(m, "Logs", 1.76, 2.2, Vector3.new(2.2, 3.0, 0))
				alongZ(m, "Logs", 1.76, 2.2, Vector3.new(3.95, 3.5, 0))
				alongZ(m, "Logs", 1.76, 2.2, Vector3.new(3.08, 4.8, 0))
			end,
		},
		LogJamChips = {
			Height = 0.39,
			AssetId = 0,
			Shadow = false,
			Palette = { Sawdust = rgb(236, 206, 152), Chips = rgb(212, 166, 106) },
			Materials = { Sawdust = Enum.Material.Sand, Chips = wood },
			Fallback = function(m)
				h.blob(m, "Sawdust", Vector3.new(3.4, 0.6, 2.8), Vector3.new(0, 0, 0))
			end,
		},
		LogJamPine = {
			Height = 19.45,
			AssetId = 0,
			Palette = { Trunk = rgb(108, 72, 46), Needles = rgb(58, 132, 82) },
			Materials = { Trunk = wood },
			Fallback = function(m)
				h.pillar(m, "Trunk", 1.4, 18, Vector3.new(0, 9, 0))
				h.blob(m, "Needles", Vector3.new(9, 16, 9), Vector3.new(0, 11, 0))
			end,
		},
		LogJamMill = {
			Height = 20.9,
			AssetId = 0,
			Palette = {
				Walls = rgb(198, 142, 90),
				Trim = rgb(118, 76, 46),
				Roof = rgb(168, 68, 56),
				Inside = rgb(38, 28, 22),
				Saw = rgb(204, 210, 218),
				Hub = rgb(204, 62, 52),
				Chimney = rgb(140, 136, 130),
				Wheel = rgb(128, 86, 54),
			},
			Materials = {
				Walls = planks,
				Trim = wood,
				Roof = Enum.Material.Slate,
				Saw = metal,
				Chimney = Enum.Material.Cobblestone,
				Wheel = wood,
			},
			Fallback = function(m)
				h.block(m, "Walls", Vector3.new(30, 11, 16), Vector3.new(0, 5.5, 0))
				h.block(m, "Roof", Vector3.new(32, 4, 18), Vector3.new(0, 13, 0))
				h.block(m, "Inside", Vector3.new(11.6, 8, 0.4), Vector3.new(0, 4, -8.1))
			end,
		},
		LogJamLumber = {
			Height = 4.83,
			AssetId = 0,
			Palette = {
				Planks = rgb(228, 186, 126),
				Straps = rgb(62, 66, 74),
				Logs = rgb(120, 82, 52),
				LogEnds = rgb(230, 192, 136),
				Chocks = rgb(108, 72, 44),
			},
			Materials = { Planks = planks, Straps = metal, Logs = wood, LogEnds = wood, Chocks = wood },
			Fallback = function(m)
				h.block(m, "Planks", Vector3.new(7, 2.5, 5), Vector3.new(0, 1.35, 0))
				h.block(m, "Logs", Vector3.new(7, 4.5, 4.8), Vector3.new(6.4, 2.3, 0))
			end,
		},
	}
end

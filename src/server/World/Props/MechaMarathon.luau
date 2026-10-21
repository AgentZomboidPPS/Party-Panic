-- Props for Mecha-Marathon (meshes from tools/meshgen/props/MechaMarathon.py):
--   MechaMarathonFlyer       the wind-up copter-bot every player winds. Body takes the player's color;
--                            the client spins the Rotor about the toy's up axis and the Key about its
--                            back-to-front axis, each through the middle of its pieces, so the
--                            fallbacks keep those pieces centered on the same axles.
--   MechaMarathonPad         the spring launch pad (Top in the lane's color, at y = 1.3: Flight.PAD).
--   MechaMarathonSign        a distance board; the game puts the number on a panel in front of the
--                            white Board (front face at z = -0.25, middle at y = 6.15).
--   MechaMarathonFlag        the flag planted where a toy lands; the client colors the Pennant.
--   MechaMarathonBunting     40 studs of sagging bunting along Z, its string ends at the top.
--   MechaMarathonTower       a candy-striped pylon of the start gantry.
--   MechaMarathonSkyBalloon  a hot air balloon over the field (StripesA recolored per balloon).
return function(h)
	local rgb = h.rgb
	local Build = h.Build
	local metal = Enum.Material.Metal

	return {
		MechaMarathonFlyer = {
			Height = 3.09,
			AssetId = 113474492425206, -- tools/upload_assets.py --only MechaMarathonFlyer fills this in
			Shadow = true,
			Palette = {
				Body = rgb(255, 80, 90),
				Trim = rgb(205, 212, 225),
				Visor = rgb(40, 62, 110),
				Eyes = rgb(160, 245, 255),
				Cheeks = rgb(255, 150, 175),
				Accent = rgb(255, 248, 232),
				Dark = rgb(62, 64, 84),
				Rotor = rgb(255, 205, 50),
				Key = rgb(235, 180, 70),
			},
			Materials = { Trim = metal, Key = metal, Visor = Enum.Material.Glass, Eyes = Enum.Material.Neon },
			Fallback = function(m)
				h.blob(m, "Body", Vector3.new(2.06, 2.2, 2.06), Vector3.new(0, 1.39, 0))
				h.blob(m, "Visor", Vector3.new(0.86, 0.84, 0.36), Vector3.new(0, 1.66, -0.95))
				for _, side in { -1, 1 } do
					h.blob(m, "Eyes", Vector3.new(0.17, 0.26, 0.1), Vector3.new(side * 0.15, 1.7, -1.12))
					h.blob(m, "Dark", Vector3.new(0.6, 0.4, 0.84), Vector3.new(side * 0.42, 0.2, -0.08))
					h.block(m, "Accent", Vector3.new(0.8, 0.14, 0.62), Vector3.new(side * 1.22, 1.28, 0.05))
				end
				h.pillar(m, "Trim", 2.15, 0.15, Vector3.new(0, 0.98, 0))
				h.pillar(m, "Trim", 0.16, 0.5, Vector3.new(0, 2.6, 0))
				h.block(m, "Rotor", Vector3.new(4.1, 0.08, 0.34), Vector3.new(0, 2.92, 0))
				h.ball(m, "Rotor", 0.34, Vector3.new(0, 2.92, 0))
				h.block(m, "Key", Vector3.new(0.15, 0.15, 0.66), Vector3.new(0, 1.3, 1.15))
				h.block(m, "Key", Vector3.new(0.12, 1.1, 0.42), Vector3.new(0, 1.3, 1.62))
			end,
		},
		MechaMarathonPad = {
			Height = 1.335,
			AssetId = 127098361425733,
			Collide = false, -- decoration only: nothing solid where nothing is drawn
			Palette = {
				Base = rgb(248, 246, 240),
				Dark = rgb(70, 74, 92),
				Spring = rgb(205, 212, 225),
				Top = rgb(70, 150, 255),
				Ring = rgb(255, 255, 255),
				Trim = rgb(150, 156, 172),
			},
			Materials = { Spring = metal, Trim = metal },
			Fallback = function(m)
				h.pillar(m, "Base", 5.3, 0.48, Vector3.new(0, 0.24, 0))
				h.pillar(m, "Spring", 3.3, 0.5, Vector3.new(0, 0.73, 0))
				h.pillar(m, "Top", 4.5, 0.32, Vector3.new(0, 1.14, 0))
				h.pillar(m, "Ring", 3.3, 0.035, Vector3.new(0, 1.3175, 0))
			end,
		},
		MechaMarathonSign = {
			Height = 9.22,
			AssetId = 105881838993783,
			Collide = false, -- decoration only: nothing solid where nothing is drawn
			Palette = {
				Post = rgb(250, 250, 250),
				Dark = rgb(70, 74, 92),
				Board = rgb(255, 255, 255),
				Frame = rgb(255, 190, 40),
			},
			Fallback = function(m)
				for _, side in { -1, 1 } do
					h.pillar(m, "Post", 0.34, 8.3, Vector3.new(side * 2.35, 4.15, 0))
					h.ball(m, "Post", 0.44, Vector3.new(side * 2.35, 8.32, 0))
				end
				h.block(m, "Board", Vector3.new(6.2, 3, 0.5), Vector3.new(0, 6.15, 0))
				h.block(m, "Frame", Vector3.new(6.7, 0.32, 0.62), Vector3.new(0, 7.75, 0))
				h.block(m, "Frame", Vector3.new(6.7, 0.32, 0.62), Vector3.new(0, 4.55, 0))
				h.ball(m, "Frame", 1.0, Vector3.new(0, 8.72, 0))
			end,
		},
		MechaMarathonFlag = {
			Height = 4.62,
			AssetId = 97047190438662,
			Palette = {
				Base = rgb(250, 250, 250),
				Pole = rgb(235, 238, 245),
				Finial = rgb(255, 205, 60),
				Pennant = rgb(255, 80, 90),
			},
			Materials = { Finial = metal },
			Fallback = function(m)
				h.pillar(m, "Base", 0.9, 0.3, Vector3.new(0, 0.15, 0))
				h.pillar(m, "Pole", 0.13, 4.2, Vector3.new(0, 2.3, 0))
				h.ball(m, "Finial", 0.3, Vector3.new(0, 4.47, 0))
				Build.Wedge({
					Name = "Pennant",
					Size = Vector3.new(0.06, 1.1, 1.9),
					CFrame = CFrame.new(1.0, 3.7, 0) * CFrame.Angles(0, math.rad(90), 0),
					Parent = m,
				})
			end,
		},
		MechaMarathonBunting = {
			Height = 2.47,
			AssetId = 127061827373685,
			Shadow = false,
			Palette = {
				String = rgb(250, 250, 250),
				FlagsA = rgb(255, 85, 95),
				FlagsB = rgb(255, 210, 60),
				FlagsC = rgb(70, 160, 255),
			},
			Fallback = function(m)
				-- A sagging string in four straight runs, with a pennant hanging at each bend.
				local points = {}
				for i = 0, 4 do
					local z = -20 + i * 10
					table.insert(points, Vector3.new(0, 2.47 - 1.5 * (1 - (z / 20) ^ 2), z))
				end
				for i = 1, 4 do
					local a, b = points[i], points[i + 1]
					Build.Part({
						Name = "String",
						Size = Vector3.new(0.08, 0.08, (b - a).Magnitude),
						CFrame = CFrame.lookAt((a + b) / 2, b),
						Parent = m,
					})
				end
				local names = { "FlagsA", "FlagsB", "FlagsC" }
				for i = 1, 3 do
					local p = points[i + 1]
					h.block(m, names[i], Vector3.new(0.05, 0.9, 0.8), p - Vector3.new(0, 0.5, 0))
				end
			end,
		},
		MechaMarathonTower = {
			Height = 21.3,
			AssetId = 83079223821743,
			Collide = false, -- decoration only: nothing solid where nothing is drawn
			Palette = {
				Base = rgb(70, 74, 92),
				Pole = rgb(250, 250, 250),
				Stripes = rgb(240, 60, 70),
				Gold = rgb(255, 200, 60),
			},
			Materials = { Gold = metal },
			Fallback = function(m)
				h.pillar(m, "Base", 2.6, 0.78, Vector3.new(0, 0.39, 0))
				h.pillar(m, "Pole", 1.0, 17.4, Vector3.new(0, 9.4, 0))
				for i = 0, 5 do
					h.pillar(m, "Stripes", 1.06, 1.45, Vector3.new(0, 2.15 + i * 2.9, 0))
				end
				h.ball(m, "Gold", 1.9, Vector3.new(0, 19.05, 0))
				h.ball(m, "Gold", 0.9, Vector3.new(0, 20.85, 0))
			end,
		},
		MechaMarathonSkyBalloon = {
			Height = 23,
			AssetId = 70482829335433,
			Shadow = false,
			Palette = {
				StripesA = rgb(255, 90, 90),
				StripesB = rgb(255, 246, 228),
				Skirt = rgb(120, 82, 52),
				Basket = rgb(176, 124, 72),
				Rope = rgb(150, 122, 92),
				Burner = rgb(90, 92, 104),
			},
			Materials = { Basket = Enum.Material.WoodPlanks },
			Fallback = function(m)
				h.blob(m, "StripesA", Vector3.new(14.8, 17, 14.8), Vector3.new(0, 14.5, 0))
				h.pillar(m, "Skirt", 3.4, 0.9, Vector3.new(0, 5.6, 0))
				h.rounded(m, "Basket", Vector3.new(2.6, 2, 2.6), 0.25, Vector3.new(0, 1, 0))
			end,
		},
	}
end

-- Props for the lobby plaza: the paving, the fountain and its ducks, the theme-park skyline (Ferris
-- wheel, hot-air balloons, carnival turrets), flower beds and bunting.
-- Meshes: tools/meshgen/props/Lobby.py. Names start with "Lobby" so they never clash with a
-- mini-game's props. LobbyBuilder places them; AmbienceController animates the moving ones.
return function(h)
	local rgb = h.rgb
	return {
		-- The promenade ring between the central court and the lawn (radius 27.6 to 45.9).
		LobbyPavers = {
			Height = 0.1,
			AssetId = 128624548370320,
			Shadow = false,
			Palette = {
				TileA = rgb(255, 208, 150),
				TileB = rgb(238, 138, 104),
				Band = rgb(84, 190, 238),
				Stripe = rgb(255, 255, 255),
			},
			Fallback = function(m)
				h.pillar(m, "TileA", 91.8, 0.1, Vector3.new(0, 0.05, 0))
			end,
		},
		-- The sunburst court around the fountain (radius 27.5).
		LobbyCourt = {
			Height = 0.1,
			AssetId = 103368218308832,
			Shadow = false,
			Palette = {
				RayA = rgb(255, 238, 200),
				RayB = rgb(255, 120, 150),
				Accent = rgb(255, 92, 160),
				Ring = rgb(255, 204, 64),
			},
			Fallback = function(m)
				h.pillar(m, "RayA", 55, 0.1, Vector3.new(0, 0.05, 0))
			end,
		},
		-- Scalloped stone basin, fluted column and upper bowl (26.4 across). The water surfaces are
		-- separate glass parts, and colliders are added by LobbyBuilder so players can wade in.
		LobbyFountain = {
			Height = 8.5,
			AssetId = 139721157931846,
			Palette = {
				Stone = rgb(255, 252, 248),
				Trim = rgb(255, 204, 64),
				Accent = rgb(255, 110, 170),
				Pool = rgb(70, 190, 235),
			},
			Materials = { Trim = Enum.Material.Metal },
			Fallback = function(m)
				h.pillar(m, "Stone", 25, 2.6, Vector3.new(0, 1.3, 0))
				h.pillar(m, "Trim", 25.6, 0.4, Vector3.new(0, 2.4, 0))
				h.pillar(m, "Stone", 3, 6, Vector3.new(0, 3, 0))
				h.pillar(m, "Stone", 11, 1.6, Vector3.new(0, 7.7, 0))
			end,
		},
		LobbyDuck = {
			Height = 1.84,
			AssetId = 126905865176551,
			Palette = { Body = rgb(255, 220, 60), Beak = rgb(255, 140, 40), Eyes = rgb(30, 30, 40) },
			Fallback = function(m)
				h.blob(m, "Body", Vector3.new(1.5, 1.1, 1.9), Vector3.new(0, 0.6, 0.1))
				h.ball(m, "Body", 0.9, Vector3.new(0, 1.4, -0.45))
				h.blob(m, "Beak", Vector3.new(0.5, 0.2, 0.5), Vector3.new(0, 1.35, -0.9))
			end,
		},
		-- The turning part of the Ferris wheel (its axle runs along Z through the bounding box
		-- center). Cabins are separate props that hang from it.
		LobbyFerrisWheel = {
			Height = 65.6,
			AssetId = 117553986418264,
			Palette = { Frame = rgb(255, 92, 150), Hub = rgb(255, 204, 64), Lights = rgb(255, 240, 170) },
			Materials = { Lights = Enum.Material.Neon, Hub = Enum.Material.Metal },
			Fallback = function(m)
				for index = 0, 15 do
					local angle = index / 16 * math.pi * 2
					local position = Vector3.new(math.cos(angle) * 32, 32.8 + math.sin(angle) * 32, 0)
					h.Build.Part({
						Name = "Frame",
						Size = Vector3.new(1, 12.8, 1),
						CFrame = CFrame.new(position) * CFrame.Angles(0, 0, angle),
						Parent = m,
					})
				end
				h.roller(m, "Hub", 5, 4, Vector3.new(0, 32.8, 0)).CFrame = CFrame.new(0, 32.8, 0)
					* CFrame.Angles(0, math.rad(90), 0)
			end,
		},
		-- A gondola; its hang point is the top center.
		LobbyFerrisCabin = {
			Height = 7.57,
			AssetId = 123860185649714,
			Palette = { Body = rgb(64, 196, 255), Roof = rgb(255, 255, 255), Frame = rgb(255, 204, 64) },
			Fallback = function(m)
				h.rounded(m, "Body", Vector3.new(4.4, 2.6, 3.4), 0.7, Vector3.new(0, 1.3, 0))
				h.blob(m, "Roof", Vector3.new(5.4, 1.2, 4.2), Vector3.new(0, 5.5, 0))
				h.pillar(m, "Frame", 0.3, 4.6, Vector3.new(0, 5.2, 0))
			end,
		},
		-- Two A-frames on a boarding deck; the axle is 43 above the base.
		LobbyFerrisStand = {
			Height = 44.7,
			AssetId = 80815460183700,
			Palette = { Legs = rgb(156, 108, 255), Base = rgb(255, 255, 255), Trim = rgb(255, 204, 64) },
			Fallback = function(m)
				h.rounded(m, "Base", Vector3.new(40, 1.2, 20), 0.5, Vector3.new(0, 0.6, 0.625))
				for _, z in { -4.6, 4.6 } do
					for _, x in { -1, 1 } do
						h.Build.Part({
							Name = "Legs",
							Size = Vector3.new(1.2, 46, 1.2),
							CFrame = CFrame.new(x * 8.4, 22, z + 0.625) * CFrame.Angles(0, 0, math.rad(x * 20)),
							Parent = m,
						})
					end
				end
				h.pillar(m, "Trim", 3.4, 0.2, Vector3.new(0, 44.6, 0.625))
			end,
		},
		LobbyHotAirBalloon = {
			Height = 26.7,
			AssetId = 132548190259649,
			Shadow = false,
			Palette = {
				Envelope = rgb(255, 92, 150),
				Stripes = rgb(255, 236, 120),
				Band = rgb(255, 204, 64),
				Basket = rgb(196, 140, 92),
				Ropes = rgb(90, 70, 60),
			},
			Materials = { Basket = Enum.Material.Wood },
			Fallback = function(m)
				h.blob(m, "Envelope", Vector3.new(18, 20, 18), Vector3.new(0, 16.6, 0))
				h.rounded(m, "Basket", Vector3.new(3, 2, 3), 0.4, Vector3.new(0, 1, 0))
			end,
		},
		-- An oval raised bed, 10 x 5, long axis along X.
		LobbyFlowerBed = {
			Height = 2.05,
			AssetId = 123118473829279,
			Collide = true,
			Palette = {
				Curb = rgb(250, 246, 240),
				Soil = rgb(110, 75, 55),
				Leaves = rgb(70, 176, 84),
				Hearts = rgb(255, 220, 70),
				FlowerA = rgb(255, 92, 150),
				FlowerB = rgb(255, 255, 255),
				FlowerC = rgb(170, 120, 255),
			},
			Materials = { Leaves = Enum.Material.Grass },
			Fallback = function(m)
				h.blob(m, "Curb", Vector3.new(10, 1.4, 5), Vector3.new(0, 0.35, 0))
				h.blob(m, "Leaves", Vector3.new(9, 2.4, 4.2), Vector3.new(0, 0.85, 0))
			end,
		},
		-- A candy-striped carnival turret with a balcony of bulbs and a pennant (37 tall).
		LobbyTower = {
			Height = 37.15,
			AssetId = 135960815310824,
			Collide = true,
			Palette = {
				Body = rgb(255, 255, 255),
				Stripes = rgb(255, 92, 150),
				Trim = rgb(255, 204, 64),
				Roof = rgb(120, 84, 230),
				RoofStripes = rgb(255, 255, 255),
				Windows = rgb(60, 40, 110),
				Lights = rgb(255, 240, 170),
				Flag = rgb(255, 204, 64),
			},
			Materials = { Lights = Enum.Material.Neon, Trim = Enum.Material.Metal },
			Fallback = function(m)
				h.pillar(m, "Stripes", 6.6, 20, Vector3.new(0, 10, 0))
				h.pillar(m, "Trim", 9.6, 1.2, Vector3.new(0, 20.4, 0))
				h.blob(m, "Roof", Vector3.new(9, 13, 9), Vector3.new(0, 26, 0))
				h.pillar(m, "Trim", 0.3, 4, Vector3.new(0, 35, 0))
			end,
		},
		-- A string of pennants 24 long along X; the ends are at the top.
		LobbyBunting = {
			Height = 4.05,
			AssetId = 126353407929177,
			Shadow = false,
			Palette = {
				Rope = rgb(250, 250, 250),
				FlagA = rgb(255, 92, 150),
				FlagB = rgb(64, 196, 255),
				FlagC = rgb(255, 204, 64),
			},
			Fallback = function(m)
				h.block(m, "Rope", Vector3.new(24, 0.15, 0.15), Vector3.new(0, 3.9, 0))
				for index = -2, 2 do
					h.block(
						m,
						if index % 2 == 0 then "FlagA" else "FlagB",
						Vector3.new(1.4, 1.6, 0.1),
						Vector3.new(index * 4.5, 3.0, 0)
					)
				end
			end,
		},
		-- A beach ball 5 across, for kicking around the plaza (LobbyService keeps them in play).
		LobbyBeachBall = {
			Height = 5,
			AssetId = 89021070042620,
			Palette = {
				White = rgb(255, 255, 255),
				GoreA = rgb(255, 70, 90),
				GoreB = rgb(60, 160, 255),
				GoreC = rgb(255, 210, 50),
				Cap = rgb(255, 70, 90),
			},
			Fallback = function(m)
				h.ball(m, "GoreA", 5, Vector3.new(0, 2.5, 0))
			end,
		},
	}
end

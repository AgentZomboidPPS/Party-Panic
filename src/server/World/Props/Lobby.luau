-- Props for the lobby plaza: the paving, the fountain and its ducks, the theme-park skyline (Ferris
-- wheel, hot-air balloons, carnival turrets), flower beds and bunting, and the set pieces of the
-- zones players walk to (shooting-gallery booth, podium arch, emote-stage arch, quest kiosk,
-- confetti cannon, paved patios).
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
			AssetId = 117846000426134,
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
			AssetId = 115106276723268,
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
			AssetId = 101788580276212,
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
			AssetId = 116539640556409,
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
			AssetId = 139016732387318,
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
		-- A paved pad (32 x 24, 0.4 tall in four 0.1 steps) for a zone on the lawn.
		LobbyPatio = {
			Height = 0.4,
			AssetId = 77633316569760,
			Shadow = false,
			Palette = {
				Stripe = rgb(255, 255, 255),
				Band = rgb(84, 190, 238),
				Grout = rgb(250, 240, 225),
				TileA = rgb(255, 208, 150),
				TileB = rgb(238, 138, 104),
			},
			Fallback = function(m)
				h.block(m, "TileA", Vector3.new(32, 0.4, 24), Vector3.new(0, 0.2, 0))
			end,
		},
		-- The arcade's shooting-gallery booth, open toward -Z. Its back panel (32 x 17) stands on the
		-- local origin's line; the game's targets sit in front of it. The box center is 4.29 in front.
		LobbyGalleryBooth = {
			Height = 21.3,
			AssetId = 93121744943221,
			Collide = true,
			Palette = {
				Back = rgb(45, 65, 130),
				Frame = rgb(255, 255, 255),
				Stripes = rgb(255, 70, 110),
				Trim = rgb(255, 204, 64),
				Stars = rgb(255, 214, 92),
				Ducks = rgb(255, 214, 60),
				Beaks = rgb(255, 140, 40),
				Counter = rgb(225, 60, 95),
				Panels = rgb(255, 255, 255),
				Bulbs = rgb(255, 240, 170),
				AwningA = rgb(255, 70, 110),
				AwningB = rgb(255, 255, 255),
			},
			Materials = { Trim = Enum.Material.Metal, Bulbs = Enum.Material.Neon },
			Fallback = function(m)
				h.rounded(m, "Back", Vector3.new(32, 17, 2.5), 0.6, Vector3.new(0, 8.5, 4.69))
				h.rounded(m, "Counter", Vector3.new(32.6, 3.6, 2.4), 0.3, Vector3.new(0, 1.8, -3.21))
				for _, x in { -17.2, 17.2 } do
					h.pillar(m, "Stripes", 1.8, 19.3, Vector3.new(x, 9.65, -4.71))
				end
				h.block(m, "AwningA", Vector3.new(36, 0.4, 12), Vector3.new(0, 20.6, -0.6))
			end,
		},
		-- The winners' podium, front -Z: a stage, three tiers (1st at x 0, 2nd at x 9.5, 3rd at
		-- x -9.5) and a bulb arch around the champion board (z 9.6). The box center is at z 2.
		LobbyPodium = {
			Height = 34.9,
			AssetId = 94884052453718,
			Collide = true,
			Palette = {
				Base = rgb(52, 36, 104),
				Trim = rgb(255, 204, 64),
				Body = rgb(255, 250, 242),
				Gold = rgb(255, 200, 50),
				Silver = rgb(205, 215, 235),
				Bronze = rgb(226, 142, 84),
				Frame = rgb(255, 255, 255),
				Stripes = rgb(156, 108, 255),
				Bulbs = rgb(255, 240, 170),
			},
			Materials = {
				Trim = Enum.Material.Metal,
				Gold = Enum.Material.Metal,
				Silver = Enum.Material.Metal,
				Bronze = Enum.Material.Metal,
				Bulbs = Enum.Material.Neon,
			},
			Fallback = function(m)
				h.rounded(m, "Base", Vector3.new(36, 0.8, 24), 0.35, Vector3.new(0, 0.4, 0))
				for _, step in { { 0, 6.5, "Gold" }, { 9.5, 4.6, "Silver" }, { -9.5, 3, "Bronze" } } do
					h.rounded(m, step[3], Vector3.new(9, step[2], 9), 0.9, Vector3.new(step[1], 0.8 + step[2] / 2, -2))
				end
				for _, x in { -18.5, 18.5 } do
					h.pillar(m, "Stripes", 2, 19, Vector3.new(x, 10, 7.6))
				end
			end,
		},
		-- The emote stage's back arch, front -Z: candy columns at x +-14, a header beam, a fan crown
		-- with bulbs and a speaker stack each side. The box center is 0.21 in front of the columns.
		LobbyEmoteArch = {
			Height = 33.8,
			AssetId = 86541767455946,
			Collide = true,
			Palette = {
				Frame = rgb(120, 84, 230),
				Stripes = rgb(255, 255, 255),
				Trim = rgb(255, 204, 64),
				Bulbs = rgb(255, 240, 170),
				Speakers = rgb(50, 40, 80),
				Cones = rgb(28, 28, 40),
				FanA = rgb(255, 204, 64),
				FanB = rgb(255, 92, 150),
			},
			Materials = { Trim = Enum.Material.Metal, Bulbs = Enum.Material.Neon },
			Fallback = function(m)
				for _, x in { -14, 14 } do
					h.pillar(m, "Frame", 2.2, 17.6, Vector3.new(x, 8.8, 0.21))
				end
				h.rounded(m, "Frame", Vector3.new(31, 2.2, 2.4), 0.5, Vector3.new(0, 18.6, 0.21))
				for _, x in { -18.5, 18.5 } do
					h.rounded(m, "Speakers", Vector3.new(3.6, 7.4, 3), 0.4, Vector3.new(x, 3.7, -0.19))
				end
			end,
		},
		-- A wooden kiosk with a gabled roof that frames the quest board (16 x 11, centered 8 up),
		-- front -Z. The box center is 0.09 behind the board.
		LobbyQuestKiosk = {
			Height = 20.85,
			AssetId = 127544750099005,
			Collide = true,
			Palette = {
				Wood = rgb(196, 140, 92),
				Roof = rgb(170, 110, 240),
				RoofB = rgb(255, 255, 255),
				Trim = rgb(255, 204, 64),
				Bulbs = rgb(255, 240, 170),
				Planter = rgb(255, 110, 160),
				Leaves = rgb(70, 176, 84),
				Flowers = rgb(255, 236, 120),
			},
			Materials = { Wood = Enum.Material.Wood, Bulbs = Enum.Material.Neon, Leaves = Enum.Material.Grass },
			Fallback = function(m)
				h.rounded(m, "Wood", Vector3.new(18.4, 13.4, 1.6), 0.4, Vector3.new(0, 8, 0.21))
				for _, x in { -10.3, 10.3 } do
					h.pillar(m, "Wood", 1.2, 16.4, Vector3.new(x, 8.2, 0.21))
				end
				h.rounded(m, "Roof", Vector3.new(25, 1, 10.6), 0.4, Vector3.new(0, 18.2, 0.21))
			end,
		},
		-- A circus cannon on a wheeled cart, its barrel aimed up and forward (-Z).
		LobbyConfettiCannon = {
			Height = 7.33,
			AssetId = 130260503026635,
			Collide = true,
			Palette = {
				Cart = rgb(64, 150, 255),
				Wheels = rgb(255, 70, 100),
				Trim = rgb(255, 204, 64),
				Barrel = rgb(255, 92, 150),
				BarrelStripes = rgb(255, 255, 255),
			},
			Materials = { Trim = Enum.Material.Metal },
			Fallback = function(m)
				h.rounded(m, "Cart", Vector3.new(3.2, 1.4, 4.4), 0.4, Vector3.new(0, 1.9, 0.6))
				h.capsule(m, "Barrel", 5, 2.2, CFrame.new(0, 4.4, -0.6) * CFrame.Angles(math.rad(-40), 0, 0))
			end,
		},
	}
end

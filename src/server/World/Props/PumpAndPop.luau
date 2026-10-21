-- Props for Pump & Pop (meshes from tools/meshgen/props/PumpAndPop.py):
--   PumpBalloon  the team balloon. Its face looks along -Z; the client scales it as the team pumps
--                and shows the spare face pieces (Brows, Ooh, Sweat) as it gets close to popping.
--   AirTank      the tank each balloon is tied to (knot on the brass neck at the top). The client
--                turns the gauge's Needle, which points at 12 o'clock in the mesh.
--   Plunger      a floor pump; its hose runs along -Z into the tank. Rod, Handle and Grips are the
--                parts the client slides down while a player pushes.
-- Every piece name matters to the client half (src/client/MiniGames/PumpAndPop.luau), so the
-- fallbacks use the same names.
--
-- Art pass ("make every arena look really cool"; a bright carnival stage): a bandshell of striped
-- arches behind the balloons, a round sunburst stage deck, team grandstands full of peg-doll fans,
-- big-top tents, game booths, candy-striped light poles with bunting and a Ferris wheel on the
-- skyline. BulbsA / BulbsB are the light bulbs the client chases (see the client half).

return function(h)
	local rgb = h.rgb
	local Build = h.Build
	local neon = Enum.Material.Neon
	local fabric = Enum.Material.Fabric
	local BULB = rgb(255, 238, 170) -- a lit bulb (the client dims every other one in turn)

	-- A part facing along Z (the fallback dial and its needle).
	local function facing(m: Model, name: string, shape: Enum.PartType, size: Vector3, position: Vector3): Part
		return Build.Part({
			Name = name,
			Shape = shape,
			Size = size,
			CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0),
			Parent = m,
		})
	end

	return {
		PumpBalloon = {
			Height = 15,
			AssetId = 94794024650107,
			Shadow = true,
			Palette = {
				Skin = rgb(255, 80, 95),
				Eyes = rgb(255, 255, 255),
				Pupils = rgb(35, 25, 45),
				Shine = rgb(255, 255, 255),
				Smile = rgb(120, 25, 45),
				Ooh = rgb(110, 20, 40),
				Brows = rgb(90, 30, 40),
				Blush = rgb(255, 150, 170),
				Sweat = rgb(120, 200, 255),
				Gleam = rgb(255, 255, 255),
			},
			Materials = { Skin = Enum.Material.Glass, Sweat = Enum.Material.Glass },
			Fallback = function(m)
				h.blob(m, "Skin", Vector3.new(11.4, 13.6, 11.4), Vector3.new(0, 8.3, 0))
				h.ball(m, "Skin", 0.9, Vector3.new(0, 0.5, 0))
				for _, side in { -1, 1 } do
					h.blob(m, "Eyes", Vector3.new(1.8, 2.4, 0.7), Vector3.new(side * 1.75, 9.4, -5.35))
					h.blob(m, "Pupils", Vector3.new(1.0, 1.3, 0.5), Vector3.new(side * 1.63, 9.28, -5.62))
					h.ball(m, "Shine", 0.34, Vector3.new(side * 1.63 + 0.18, 9.54, -5.86))
					h.block(m, "Brows", Vector3.new(1.5, 0.26, 0.26), Vector3.new(side * 1.75, 11.05, -5.1))
					h.blob(m, "Blush", Vector3.new(1.5, 0.8, 0.3), Vector3.new(side * 3.1, 8.0, -4.75))
				end
				h.rounded(m, "Smile", Vector3.new(2.2, 0.32, 0.32), 0.15, Vector3.new(0, 6.85, -5.68))
				h.blob(m, "Ooh", Vector3.new(0.95, 1.3, 0.3), Vector3.new(0, 7.0, -5.72))
				h.ball(m, "Sweat", 0.6, Vector3.new(3.55, 11.2, -3.8))
			end,
		},
		AirTank = {
			Height = 4.7,
			AssetId = 92699226368322,
			Collide = true,
			Palette = {
				Feet = rgb(70, 60, 90),
				Tank = rgb(250, 245, 255),
				TankBands = rgb(255, 200, 60),
				Brass = rgb(230, 175, 70),
				Dial = rgb(255, 255, 250),
				Ticks = rgb(40, 35, 60),
				DialRed = rgb(255, 70, 70),
				Needle = rgb(235, 40, 50),
			},
			Materials = { Brass = Enum.Material.Metal, TankBands = Enum.Material.Metal },
			Fallback = function(m)
				h.pillar(m, "Feet", 5.6, 0.36, Vector3.new(0, 0.18, 0))
				h.pillar(m, "Tank", 4.9, 3.6, Vector3.new(0, 2.14, 0))
				h.blob(m, "Tank", Vector3.new(4.6, 1.1, 4.6), Vector3.new(0, 3.9, 0))
				h.pillar(m, "TankBands", 5.15, 0.26, Vector3.new(0, 0.62, 0))
				h.pillar(m, "TankBands", 5.15, 0.26, Vector3.new(0, 3.3, 0))
				h.pillar(m, "Brass", 0.9, 0.7, Vector3.new(0, 4.35, 0))
				facing(m, "Brass", Enum.PartType.Cylinder, Vector3.new(0.3, 1.9, 1.9), Vector3.new(0, 2.15, -2.55))
				facing(m, "Dial", Enum.PartType.Cylinder, Vector3.new(0.1, 1.6, 1.6), Vector3.new(0, 2.15, -2.72))
				h.block(m, "DialRed", Vector3.new(0.3, 0.3, 0.05), Vector3.new(-0.62, 1.95, -2.78))
				h.block(m, "Needle", Vector3.new(0.12, 0.62, 0.06), Vector3.new(0, 2.46, -2.82))
			end,
		},
		Plunger = {
			Height = 4.18,
			AssetId = 96075152171242,
			Palette = {
				PumpBase = rgb(60, 55, 75),
				Barrel = rgb(255, 80, 95),
				Chrome = rgb(215, 220, 235),
				Hose = rgb(60, 55, 75),
				Rod = rgb(225, 230, 240),
				Handle = rgb(250, 250, 255),
				Grips = rgb(45, 40, 55),
			},
			Materials = { Chrome = Enum.Material.Metal, Rod = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "PumpBase", Vector3.new(2.4, 0.2, 1.0), Vector3.new(0, 0.1, 0))
				h.pillar(m, "Barrel", 0.8, 2.42, Vector3.new(0, 1.51, 0))
				h.pillar(m, "Chrome", 0.95, 0.25, Vector3.new(0, 0.38, 0))
				h.pillar(m, "Chrome", 0.95, 0.25, Vector3.new(0, 2.72, 0))
				h.rounded(m, "Hose", Vector3.new(0.26, 0.26, 4.6), 0.12, Vector3.new(0, 0.15, -2.75))
				h.pillar(m, "Rod", 0.17, 2.25, Vector3.new(0, 2.775, 0))
				h.roller(m, "Handle", 0.22, 2.4, Vector3.new(0, 3.9, 0))
				h.roller(m, "Grips", 0.38, 0.8, Vector3.new(-0.86, 3.9, 0))
				h.roller(m, "Grips", 0.38, 0.8, Vector3.new(0.86, 3.9, 0))
			end,
		},
		-- The concert bandshell behind the stage (open side -Z): violet and cream arches, gold steps.
		PumpBandshell = {
			Height = 56.665,
			AssetId = 71178333266467,
			Palette = {
				ShellA = rgb(132, 86, 220),
				ShellB = rgb(255, 242, 220),
				Steps = rgb(255, 196, 64),
				Frame = rgb(112, 64, 196),
				Facade = rgb(255, 236, 214),
				Crest = rgb(255, 204, 56),
				BulbsA = BULB,
				BulbsB = BULB,
				Cans = rgb(58, 50, 78),
				Lens = rgb(255, 250, 214),
			},
			Materials = { BulbsA = neon, BulbsB = neon, Lens = neon },
			Fallback = function(m)
				h.block(m, "Facade", Vector3.new(100, 40, 1), Vector3.new(0, 20, 20.5))
				h.block(m, "ShellA", Vector3.new(80, 30, 0.6), Vector3.new(0, 15, 19.6))
				h.block(m, "ShellB", Vector3.new(36, 20, 0.6), Vector3.new(0, 10, 19))
				for _, side in { -1, 1 } do
					h.block(m, "Frame", Vector3.new(6, 42, 2), Vector3.new(side * 50.5, 21, -0.5))
					h.block(m, "Facade", Vector3.new(1, 40, 21), Vector3.new(side * 53.5, 20, 10))
					h.pillar(m, "Cans", 2.4, 4.6, Vector3.new(side * 44, 2.3, -5))
				end
				h.block(m, "Frame", Vector3.new(107, 6, 2), Vector3.new(0, 42, -0.5))
				h.block(m, "Steps", Vector3.new(100, 0.6, 1), Vector3.new(0, 39, -1.6))
				h.ball(m, "Crest", 7, Vector3.new(0, 53.1, -0.5))
				h.ball(m, "BulbsA", 1.2, Vector3.new(-20, 44, -1.6))
				h.ball(m, "BulbsB", 1.2, Vector3.new(20, 44, -1.6))
			end,
		},
		-- The round stage floor (radius 40, top at 1.2): cream and butter sunburst wedges, a gold lip,
		-- a striped skirt and a ring of bulbs. The server scales it to the stage.
		PumpStageDeck = {
			Height = 1.86,
			AssetId = 138020419253609,
			Shadow = false,
			Palette = {
				DeckA = rgb(255, 246, 228),
				DeckB = rgb(255, 205, 120),
				Lip = rgb(255, 190, 60),
				SkirtA = rgb(132, 86, 220),
				SkirtB = rgb(255, 242, 220),
				BulbsA = BULB,
				BulbsB = BULB,
			},
			Materials = { BulbsA = neon, BulbsB = neon },
			Fallback = function(m)
				h.pillar(m, "SkirtA", 79.9, 0.9, Vector3.new(0, 0.45, 0))
				h.pillar(m, "DeckA", 76.8, 0.5, Vector3.new(0, 0.95, 0))
				h.pillar(m, "Lip", 80.1, 0.3, Vector3.new(0, 1.0, 0))
				h.ball(m, "BulbsA", 0.6, Vector3.new(0, 1.56, -39))
				h.ball(m, "BulbsB", 0.6, Vector3.new(0, 1.56, 39))
			end,
		},
		-- A team's grandstand facing -Z: Seats, CanopyA and Flags take the team color.
		PumpGrandstand = {
			Height = 20.56,
			AssetId = 80718488396468,
			Palette = {
				Frame = rgb(250, 246, 255),
				Seats = rgb(255, 80, 95),
				CanopyA = rgb(255, 80, 95),
				CanopyB = rgb(255, 252, 246),
				Flags = rgb(255, 80, 95),
				FansA = rgb(255, 170, 80),
				FansB = rgb(120, 200, 255),
				FansC = rgb(190, 140, 255),
				Heads = rgb(255, 214, 180),
			},
			Materials = { CanopyA = fabric, CanopyB = fabric, Flags = fabric },
			Fallback = function(m)
				for tier = 0, 3 do
					local y = 0.9 + 1.6 * tier
					h.block(m, "Frame", Vector3.new(23, y, 2.5), Vector3.new(0, y / 2, -4.1 + 2.5 * tier))
					h.block(m, "Seats", Vector3.new(22.6, 0.45, 1.3), Vector3.new(0, y + 0.22, -4.4 + 2.5 * tier))
				end
				for _, x in { -11.7, 0, 11.7 } do
					h.pillar(m, "Frame", 0.56, 15.2, Vector3.new(x, 7.6, -6.2))
					h.pillar(m, "Frame", 0.56, 20.5, Vector3.new(x, 10.25, 5.8))
				end
				h.block(m, "CanopyA", Vector3.new(25.6, 0.35, 13.8), Vector3.new(0, 15.9, -0.4))
				h.block(m, "Flags", Vector3.new(2.6, 1.3, 0.1), Vector3.new(1.4, 19.35, 5.8))
			end,
		},
		-- A circus big top, its doorway facing -Z.
		PumpBigTop = {
			Height = 28.423,
			AssetId = 71264971611528,
			Palette = {
				TentA = rgb(236, 64, 80),
				TentB = rgb(255, 248, 234),
				Trim = rgb(255, 196, 64),
				Door = rgb(78, 44, 104),
				Flag = rgb(255, 204, 56),
			},
			Materials = { TentA = fabric, TentB = fabric, Flag = fabric },
			Fallback = function(m)
				h.pillar(m, "TentA", 28, 7.6, Vector3.new(0, 3.8, 0))
				h.blob(m, "TentB", Vector3.new(30, 26, 30), Vector3.new(0, 7.6, 0))
				h.block(m, "Door", Vector3.new(5.2, 6, 0.8), Vector3.new(0, 3, -13.9))
				h.pillar(m, "Trim", 0.7, 7, Vector3.new(0, 24.9, 0))
			end,
		},
		-- A carnival game booth facing -Z: striped counter and awning, shelves of plush prizes.
		PumpGameBooth = {
			Height = 12.1,
			AssetId = 86793913282920,
			Palette = {
				BoothA = rgb(64, 172, 234),
				BoothB = rgb(255, 250, 240),
				Frame = rgb(255, 236, 206),
				PrizesA = rgb(255, 140, 190),
				PrizesB = rgb(120, 220, 160),
				Sign = rgb(255, 204, 56),
			},
			Materials = { BoothA = fabric, BoothB = fabric },
			Fallback = function(m)
				h.block(m, "BoothA", Vector3.new(10, 3.4, 0.5), Vector3.new(0, 1.7, -3))
				h.block(m, "Frame", Vector3.new(10, 8, 0.4), Vector3.new(0, 4, 3))
				h.block(m, "BoothB", Vector3.new(11.2, 0.3, 7.8), Vector3.new(0, 8.8, -0.7))
				h.ball(m, "PrizesA", 1.4, Vector3.new(-2, 6.3, 2.2))
				h.ball(m, "PrizesB", 1.4, Vector3.new(2, 6.3, 2.2))
				h.ball(m, "Sign", 2, Vector3.new(0, 11.1, -3.2))
			end,
		},
		-- A candy-striped light pole; bunting ties on at 13.6 studs.
		PumpLightPole = {
			Height = 15,
			AssetId = 88538265837144,
			Palette = {
				Foot = rgb(255, 196, 64),
				PoleA = rgb(236, 64, 80),
				PoleB = rgb(255, 248, 234),
				BulbsA = BULB,
				BulbsB = BULB,
			},
			Materials = { BulbsA = neon, BulbsB = neon },
			Fallback = function(m)
				h.pillar(m, "Foot", 1.8, 1.2, Vector3.new(0, 0.6, 0))
				h.pillar(m, "PoleA", 0.6, 12.5, Vector3.new(0, 7.35, 0))
				h.ball(m, "BulbsA", 0.6, Vector3.new(1.1, 14.15, 0))
				h.ball(m, "BulbsB", 0.6, Vector3.new(-1.1, 14.15, 0))
				h.ball(m, "Foot", 1.4, Vector3.new(0, 14.3, 0))
			end,
		},
		-- A string of pennants 24 studs long (both ends at the top), sagging 3 studs.
		PumpBunting = {
			Height = 5.02,
			AssetId = 98727303733230,
			Shadow = false,
			Palette = {
				String = rgb(250, 250, 250),
				FlagA = rgb(236, 64, 80),
				FlagB = rgb(255, 204, 56),
				FlagC = rgb(64, 172, 234),
				FlagD = rgb(96, 204, 124),
			},
			Materials = { FlagA = fabric, FlagB = fabric, FlagC = fabric, FlagD = fabric },
			Fallback = function(m)
				h.block(m, "String", Vector3.new(24, 0.12, 0.12), Vector3.new(0, 4.96, 0))
				h.block(m, "FlagA", Vector3.new(1.5, 2, 0.08), Vector3.new(-6, 1, 0))
				h.block(m, "FlagB", Vector3.new(1.5, 2, 0.08), Vector3.new(-2, 1, 0))
				h.block(m, "FlagC", Vector3.new(1.5, 2, 0.08), Vector3.new(2, 1, 0))
				h.block(m, "FlagD", Vector3.new(1.5, 2, 0.08), Vector3.new(6, 1, 0))
			end,
		},
		-- A Ferris wheel for the skyline, facing -Z (hub 34.4 studs up).
		PumpFerrisWheel = {
			Height = 63.361,
			AssetId = 109867641003515,
			Palette = {
				Frame = rgb(250, 246, 255),
				Wheel = rgb(250, 246, 255),
				Hub = rgb(255, 196, 64),
				CarsA = rgb(236, 64, 80),
				CarsB = rgb(64, 172, 234),
				CarsC = rgb(255, 204, 56),
				BulbsA = BULB,
				BulbsB = BULB,
			},
			Materials = { BulbsA = neon, BulbsB = neon },
			Fallback = function(m)
				for _, side in { -1, 1 } do
					h.block(m, "Frame", Vector3.new(1.2, 36, 1.2), Vector3.new(side * 8.5, 18, 0))
				end
				local ring = h.pillar(m, "Wheel", 57.8, 0.6, Vector3.new(0, 34.4, -2))
				ring.CFrame = CFrame.new(0, 34.4, -2) * CFrame.Angles(0, math.rad(90), 0)
				ring.Transparency = 0.6
				h.pillar(m, "Hub", 4, 5.6, Vector3.new(0, 34.4, 0)).CFrame = CFrame.new(0, 34.4, 0)
					* CFrame.Angles(0, math.rad(90), 0)
				h.block(m, "CarsA", Vector3.new(3.2, 3, 3.4), Vector3.new(0, 61.5, 0))
				h.block(m, "CarsB", Vector3.new(3.2, 3, 3.4), Vector3.new(-28, 33, 0))
				h.block(m, "CarsC", Vector3.new(3.2, 3, 3.4), Vector3.new(28, 33, 0))
				h.ball(m, "BulbsA", 0.84, Vector3.new(0, 63, -2))
				h.ball(m, "BulbsB", 0.84, Vector3.new(0, 5.8, -2))
			end,
		},
	}
end

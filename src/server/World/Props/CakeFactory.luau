-- Props for Cake Factory (meshes from tools/meshgen/props/CakeFactory.py). Every piece name matters
-- to the mode (src/server/MiniGames/CakeFactory.luau lines things up by Stamp, Nozzle, Chute,
-- Plates and Body) or its client half (which slides Cleats, presses Stamp, dips Nozzle, pops
-- Berries and flashes Lamp/Beacon), so the fallbacks use the same names. Pieces called Stripe take
-- the team's color.
--
--   CakePlate, CakeSponge, CakeCream, CakeBerry  the layers the clients stack on the belt (plate
--        top 0.2; sponge 1.25 tall; the cream's underside sits 0.56 up its pivot, its top 0.86)
--   CakeBox        dropped over a finished cake by the packer, then stacked on the shelf
--   CakeBelt       44 long along X, its surface 3.2 up, team-colored side rails
--   CakePress, CakeNozzle, CakeHopper   the SPONGE, CREAM and BERRY machines over the belt
--   CakeStacker    drops a plate for every cake; CakeBoxer boxes finished cakes
--   CakeBin, CakeShelf   where ruined cakes and boxed cakes end up
--   CakeTiered, CakeMixer, CakeCupcake   giant decorations

return function(h)
	local rgb = h.rgb
	local Build = h.Build

	-- A cylinder facing along Z (windows, dials).
	local function disc(m: Model, name: string, diameter: number, depth: number, position: Vector3): Part
		return Build.Part({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(depth, diameter, diameter),
			CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0),
			Parent = m,
		})
	end

	local MACHINE = {
		Body = rgb(255, 200, 170),
		Frame = rgb(240, 240, 250),
		Trim = rgb(255, 205, 80),
		Stripe = rgb(255, 80, 90),
		Eyes = rgb(255, 255, 255),
		Pupils = rgb(30, 26, 40),
	}
	local function machine(extra: { [string]: Color3 }): { [string]: Color3 }
		local palette = table.clone(MACHINE)
		for key, value in extra do
			palette[key] = value
		end
		return palette
	end
	-- The back column and the googly eyes every machine has.
	local function column(m: Model, height: number)
		h.rounded(m, "Frame", Vector3.new(1.7, height, 1.6), 0.4, Vector3.new(0, height / 2, 3.6))
		h.rounded(m, "Frame", Vector3.new(3.1, 0.5, 2.8), 0.2, Vector3.new(0, 0.25, 3.8))
	end
	local function eyes(m: Model, y: number, z: number, spread: number, size: number)
		for _, side in { -1, 1 } do
			h.blob(m, "Eyes", Vector3.new(size * 2, size * 2.3, size * 1.1), Vector3.new(side * spread, y, z))
			h.blob(
				m,
				"Pupils",
				Vector3.new(size * 1.04, size * 1.15, size * 0.5),
				Vector3.new(side * spread, y - 0.05, z - size * 0.4)
			)
		end
	end

	return {
		CakePlate = {
			Height = 0.37,
			AssetId = 139405542176293,
			Palette = { Plate = rgb(250, 250, 252), Doily = rgb(255, 214, 228) },
			Fallback = function(m)
				h.pillar(m, "Plate", 4.2, 0.17, Vector3.new(0, 0.085, 0))
				h.pillar(m, "Plate", 4.2, 0.12, Vector3.new(0, 0.31, 0))
				h.pillar(m, "Doily", 3.6, 0.04, Vector3.new(0, 0.19, 0))
			end,
		},
		CakeSponge = {
			Height = 1.25,
			AssetId = 126954810574497,
			Palette = { Sponge = rgb(246, 196, 112), Filling = rgb(255, 244, 232) },
			Fallback = function(m)
				h.pillar(m, "Sponge", 3.2, 0.56, Vector3.new(0, 0.28, 0))
				h.pillar(m, "Filling", 3.24, 0.14, Vector3.new(0, 0.625, 0))
				h.pillar(m, "Sponge", 3.2, 0.55, Vector3.new(0, 0.975, 0))
			end,
		},
		CakeCream = {
			Height = 1.24,
			AssetId = 114344963803893,
			Palette = {
				Cream = rgb(255, 246, 240),
				SprinklesA = rgb(255, 120, 170),
				SprinklesB = rgb(120, 200, 255),
				SprinklesC = rgb(255, 215, 80),
			},
			Fallback = function(m)
				h.pillar(m, "Cream", 3.5, 0.4, Vector3.new(0, 0.6, 0))
				h.blob(m, "Cream", Vector3.new(3.3, 0.5, 3.3), Vector3.new(0, 0.8, 0))
				for index = 0, 7 do
					local angle = index / 8 * math.pi * 2
					h.ball(m, "Cream", 0.6, Vector3.new(math.cos(angle) * 1.2, 1.0, math.sin(angle) * 1.2))
				end
				h.ball(m, "Cream", 0.24, Vector3.new(0, 0.12, 1.7))
				h.block(m, "SprinklesA", Vector3.new(0.2, 0.07, 0.07), Vector3.new(0.6, 1.05, 0.2))
				h.block(m, "SprinklesB", Vector3.new(0.07, 0.07, 0.2), Vector3.new(-0.5, 1.05, -0.3))
				h.block(m, "SprinklesC", Vector3.new(0.2, 0.07, 0.07), Vector3.new(0.1, 1.05, -0.7))
			end,
		},
		CakeBerry = {
			Height = 1.1,
			AssetId = 77899735720044,
			Palette = { Berry = rgb(232, 40, 60), Seeds = rgb(255, 226, 120), BerryLeaves = rgb(80, 190, 80) },
			Fallback = function(m)
				h.blob(m, "Berry", Vector3.new(1.1, 1.05, 1.1), Vector3.new(0, 0.58, 0))
				h.pillar(m, "BerryLeaves", 1.2, 0.08, Vector3.new(0, 0.1, 0))
			end,
		},
		CakeBox = {
			Height = 5.07,
			AssetId = 80114061986876,
			Palette = { Box = rgb(255, 250, 245), Window = rgb(190, 230, 255), Stripe = rgb(255, 80, 90) },
			Materials = { Window = Enum.Material.Glass },
			Fallback = function(m)
				h.rounded(m, "Box", Vector3.new(4.5, 4, 4.5), 0.3, Vector3.new(0, 2, 0))
				h.block(m, "Window", Vector3.new(2.4, 1.5, 0.1), Vector3.new(0, 2, -2.27))
				h.block(m, "Stripe", Vector3.new(0.5, 4.1, 4.7), Vector3.new(0, 2.03, 0))
				h.block(m, "Stripe", Vector3.new(4.7, 4.1, 0.5), Vector3.new(0, 2.03, 0))
				h.ball(m, "Stripe", 1.1, Vector3.new(0, 4.5, 0))
			end,
		},
		CakeBelt = {
			Height = 3.56,
			AssetId = 78386516739179,
			Collide = true,
			Palette = {
				Belt = rgb(70, 64, 86),
				Stripe = rgb(255, 80, 90),
				Frame = rgb(236, 236, 246),
				Cleats = rgb(52, 48, 66),
			},
			Materials = { Belt = Enum.Material.Rubber, Frame = Enum.Material.SmoothPlastic },
			Fallback = function(m)
				h.block(m, "Belt", Vector3.new(44, 0.32, 4.4), Vector3.new(22, 3.04, 0))
				for _, side in { -1, 1 } do
					h.block(m, "Stripe", Vector3.new(44.4, 0.75, 0.42), Vector3.new(22, 3.18, side * 2.48))
					for index = 0, 5 do
						h.block(m, "Frame", Vector3.new(0.55, 2.7, 0.55), Vector3.new(2 + index * 8, 1.35, side * 2.2))
					end
				end
				h.block(m, "Frame", Vector3.new(43, 0.5, 4), Vector3.new(22, 2.45, 0))
				for index = 0, 20 do
					h.block(m, "Cleats", Vector3.new(0.28, 0.1, 4), Vector3.new(0.6 + index * 2, 3.23, 0))
				end
			end,
		},
		CakePress = {
			Height = 14.4,
			AssetId = 131841845142522,
			Collide = true,
			Palette = machine({
				Window = rgb(255, 190, 110),
				Hat = rgb(255, 255, 255),
				Stamp = rgb(200, 205, 220),
			}),
			Materials = { Window = Enum.Material.Glass, Stamp = Enum.Material.Metal, Trim = Enum.Material.Metal },
			Fallback = function(m)
				column(m, 8)
				h.rounded(m, "Body", Vector3.new(6.2, 4.3, 7.6), 0.8, Vector3.new(0, 9.75, 0))
				disc(m, "Window", 2.4, 0.3, Vector3.new(0, 9.55, -3.83))
				h.rounded(m, "Stripe", Vector3.new(6.34, 0.55, 7.74), 0.25, Vector3.new(0, 8.35, 0))
				h.ball(m, "Hat", 2.6, Vector3.new(-0.9, 13.2, 0.6))
				h.pillar(m, "Trim", 1, 2, Vector3.new(2, 12.6, 1.6))
				eyes(m, 11, -3.82, 1.15, 0.55)
				h.pillar(m, "Stamp", 0.48, 1.4, Vector3.new(0, 7.1, 0))
				h.pillar(m, "Stamp", 3, 0.32, Vector3.new(0, 6.26, 0))
			end,
		},
		CakeNozzle = {
			Height = 14.57,
			AssetId = 96214481764512,
			Collide = true,
			Palette = machine({
				Tank = rgb(210, 235, 255),
				CreamFill = rgb(255, 214, 226),
				Nozzle = rgb(205, 210, 225),
			}),
			Materials = { Tank = Enum.Material.Glass, Nozzle = Enum.Material.Metal },
			Fallback = function(m)
				column(m, 8)
				h.rounded(m, "Frame", Vector3.new(2.3, 1.5, 8.8), 0.5, Vector3.new(0, 8.55, 0))
				h.rounded(m, "Stripe", Vector3.new(2.42, 0.45, 8.92), 0.2, Vector3.new(0, 8.15, 0))
				h.pillar(m, "CreamFill", 4.2, 2.1, Vector3.new(0, 10.45, 0))
				h.pillar(m, "Tank", 4.5, 3.75, Vector3.new(0, 11.18, 0))
				h.pillar(m, "Trim", 3.9, 0.4, Vector3.new(0, 13.2, 0))
				h.pillar(m, "Nozzle", 1.6, 1.2, Vector3.new(0, 6.85, 0))
				h.pillar(m, "Nozzle", 0.9, 0.5, Vector3.new(0, 6.05, 0))
				eyes(m, 8.65, -4.42, 0.62, 0.4)
			end,
		},
		CakeHopper = {
			Height = 13.29,
			AssetId = 123272792324644,
			Collide = true,
			Palette = machine({
				Hopper = rgb(255, 110, 120),
				Rim = rgb(255, 255, 255),
				Berries = rgb(232, 40, 60),
				BerryLeaves = rgb(80, 190, 80),
				Chute = rgb(205, 210, 225),
			}),
			Materials = { Chute = Enum.Material.Metal },
			Fallback = function(m)
				column(m, 7.8)
				h.rounded(m, "Frame", Vector3.new(2.2, 1.3, 8.8), 0.5, Vector3.new(0, 8.25, 0))
				h.rounded(m, "Stripe", Vector3.new(2.32, 0.42, 8.92), 0.18, Vector3.new(0, 7.9, 0))
				h.pillar(m, "Chute", 1.24, 1, Vector3.new(0, 7.4, 0))
				h.pillar(m, "Hopper", 3, 1.6, Vector3.new(0, 9.7, 0))
				h.pillar(m, "Hopper", 5.4, 1.6, Vector3.new(0, 11.2, 0))
				h.pillar(m, "Rim", 5.8, 0.3, Vector3.new(0, 12.1, 0))
				h.blob(m, "Berries", Vector3.new(4.6, 1.6, 4.2), Vector3.new(0, 12.4, 0))
				eyes(m, 10.2, -2.1, 0.6, 0.42)
			end,
		},
		CakeStacker = {
			Height = 12.95,
			AssetId = 135606329232971,
			Collide = true,
			Palette = machine({
				Glass = rgb(210, 235, 255),
				Plates = rgb(250, 250, 252),
				Dome = rgb(255, 196, 160),
				Beacon = rgb(255, 230, 120),
			}),
			Materials = { Glass = Enum.Material.Glass, Beacon = Enum.Material.Neon },
			Fallback = function(m)
				column(m, 3.8)
				h.pillar(m, "Frame", 5.4, 0.6, Vector3.new(0, 3.9, 0))
				h.pillar(m, "Plates", 4.16, 5.3, Vector3.new(0, 6.95, 0))
				h.pillar(m, "Glass", 4.8, 6.1, Vector3.new(0, 7.05, 0))
				h.pillar(m, "Frame", 5.4, 0.6, Vector3.new(0, 10.3, 0))
				h.blob(m, "Dome", Vector3.new(4.4, 2.6, 4.4), Vector3.new(0, 10.8, 0))
				h.ball(m, "Beacon", 1.1, Vector3.new(0, 12.4, 0))
				h.pillar(m, "Stripe", 5, 0.28, Vector3.new(0, 7.1, 0))
				eyes(m, 11.3, -2.0, 0.6, 0.38)
			end,
		},
		CakeBoxer = {
			Height = 13.3,
			AssetId = 73344471196114,
			Collide = true,
			Palette = machine({
				Lamp = rgb(140, 255, 160),
				Icon = rgb(255, 255, 255),
			}),
			Materials = { Lamp = Enum.Material.Neon },
			Fallback = function(m)
				column(m, 8.8)
				h.rounded(m, "Body", Vector3.new(6.4, 3.6, 7.6), 0.8, Vector3.new(0, 10.2, 0))
				h.rounded(m, "Trim", Vector3.new(4.6, 0.6, 7.7), 0.25, Vector3.new(0, 8.6, 0))
				h.rounded(m, "Stripe", Vector3.new(6.54, 0.5, 7.74), 0.22, Vector3.new(0, 11.8, 0))
				h.blob(m, "Lamp", Vector3.new(1.5, 1.5, 1.05), Vector3.new(0, 12.55, -1.2))
				h.block(m, "Icon", Vector3.new(1.1, 0.8, 0.12), Vector3.new(0, 10.15, -4.02))
				eyes(m, 11.25, -3.82, 1.9, 0.42)
			end,
		},
		CakeBin = {
			Height = 5.54,
			AssetId = 97159669784158,
			Collide = true,
			Palette = {
				Bin = rgb(120, 210, 200),
				Lid = rgb(120, 210, 200),
				Rim = rgb(235, 240, 245),
				Stripe = rgb(255, 80, 90),
			},
			Fallback = function(m)
				h.pillar(m, "Bin", 3.9, 3.15, Vector3.new(0, 1.575, 0))
				h.pillar(m, "Rim", 4.1, 0.26, Vector3.new(0, 3.17, 0))
				h.pillar(m, "Stripe", 4, 0.14, Vector3.new(0, 1.0, 0))
				Build.Part({
					Name = "Lid",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.4, 4.1, 4.1),
					CFrame = CFrame.new(0, 4.4, 2.4)
						* CFrame.Angles(0, math.rad(90), 0)
						* CFrame.Angles(0, 0, math.rad(-15)),
					Parent = m,
				})
			end,
		},
		CakeShelf = {
			Height = 11.8,
			AssetId = 88862121708237,
			Collide = true,
			Palette = {
				Frame = rgb(255, 225, 190),
				Back = rgb(255, 236, 244),
				Caps = rgb(255, 205, 80),
				Stripe = rgb(255, 80, 90),
				Sign = rgb(255, 255, 255),
				Icon = rgb(246, 196, 112),
				Berry = rgb(232, 40, 60),
			},
			Fallback = function(m)
				for _, side in { -1, 1 } do
					h.rounded(m, "Frame", Vector3.new(0.7, 10.2, 3.4), 0.3, Vector3.new(side * 5.65, 5.1, 0))
					h.ball(m, "Caps", 1.2, Vector3.new(side * 5.65, 10.4, 0))
				end
				for _, y in { 0, 3, 6, 9 } do
					h.block(m, "Frame", Vector3.new(10.8, 0.4, 3.4), Vector3.new(0, y + 0.3, 0))
					h.block(m, "Stripe", Vector3.new(10.9, 0.22, 0.2), Vector3.new(0, y + 0.42, -1.75))
				end
				h.block(m, "Back", Vector3.new(10.6, 9.4, 0.25), Vector3.new(0, 4.9, 1.55))
				h.rounded(m, "Sign", Vector3.new(4.2, 1.6, 0.35), 0.3, Vector3.new(0, 11, 0.6))
				h.pillar(m, "Icon", 1.2, 0.45, Vector3.new(-1.3, 10.98, 0.38))
				h.ball(m, "Berry", 0.44, Vector3.new(-1.3, 11.45, 0.38))
			end,
		},
		CakeTiered = {
			Height = 17.15,
			AssetId = 76469774015382,
			Collide = true,
			Palette = {
				Board = rgb(255, 225, 140),
				Sponge = rgb(255, 170, 200),
				Cream = rgb(255, 250, 246),
				Piping = rgb(255, 250, 246),
				Drips = rgb(255, 250, 246),
				Berries = rgb(232, 40, 60),
				BerryLeaves = rgb(80, 190, 80),
				Candles = rgb(150, 210, 255),
				Flames = rgb(255, 200, 80),
			},
			Materials = { Flames = Enum.Material.Neon },
			Fallback = function(m)
				h.pillar(m, "Board", 17.2, 0.6, Vector3.new(0, 0.3, 0))
				h.pillar(m, "Sponge", 15, 4.6, Vector3.new(0, 2.9, 0))
				h.pillar(m, "Cream", 15.4, 0.6, Vector3.new(0, 5.3, 0))
				h.pillar(m, "Sponge", 11.2, 4, Vector3.new(0, 7.6, 0))
				h.pillar(m, "Cream", 11.6, 0.6, Vector3.new(0, 9.7, 0))
				h.pillar(m, "Sponge", 7.6, 3.6, Vector3.new(0, 11.8, 0))
				h.pillar(m, "Cream", 8, 0.6, Vector3.new(0, 13.7, 0))
				h.blob(m, "Berries", Vector3.new(3.2, 3.2, 3.2), Vector3.new(0, 15.6, 0))
			end,
		},
		CakeMixer = {
			Height = 18.33,
			AssetId = 100560005165048,
			Collide = true,
			Palette = {
				Body = rgb(130, 215, 230),
				Trim = rgb(235, 240, 248),
				Bowl = rgb(215, 220, 232),
				Batter = rgb(255, 190, 210),
				Whisk = rgb(215, 220, 232),
			},
			Materials = { Bowl = Enum.Material.Metal, Whisk = Enum.Material.Metal, Trim = Enum.Material.Metal },
			Fallback = function(m)
				h.rounded(m, "Body", Vector3.new(9, 2.2, 13), 1, Vector3.new(0, 1.1, 1))
				h.rounded(m, "Body", Vector3.new(4.6, 13, 4.4), 1.6, Vector3.new(0, 7.5, 5.5))
				h.capsule(m, "Body", 13, 5.6, CFrame.new(0, 15.2, 1.5) * CFrame.Angles(math.rad(90), 0, 0))
				h.pillar(m, "Bowl", 9, 6, Vector3.new(0, 5.2, -2))
				h.pillar(m, "Batter", 8.2, 0.4, Vector3.new(0, 8.25, -2))
				h.pillar(m, "Whisk", 2.4, 4.6, Vector3.new(0, 9.5, -2))
			end,
		},
		CakeCupcake = {
			Height = 5.09,
			AssetId = 128328045858326,
			Collide = true,
			Palette = {
				Wrapper = rgb(140, 200, 255),
				Sponge = rgb(220, 150, 90),
				Frosting = rgb(255, 170, 210),
				Cherry = rgb(225, 30, 60),
				Stem = rgb(110, 160, 60),
			},
			Fallback = function(m)
				h.pillar(m, "Wrapper", 3.1, 1.6, Vector3.new(0, 0.8, 0))
				h.blob(m, "Sponge", Vector3.new(3.4, 0.8, 3.4), Vector3.new(0, 1.8, 0))
				h.blob(m, "Frosting", Vector3.new(3, 2.2, 3), Vector3.new(0, 3, 0))
				h.ball(m, "Cherry", 0.84, Vector3.new(0, 4.4, 0))
			end,
		},
	}
end

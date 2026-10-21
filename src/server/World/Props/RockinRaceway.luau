-- Props for Rockin' Raceway (meshes from tools/meshgen/props/RockinRaceway.py). None of them is
-- solid: riders are carried round the track by the game, and nothing else is in reach, so there is
-- nothing anyone could stand or hang on where nothing is drawn.
--   RockinRacewayHorse     the hobby horse every rider gallops on; Body takes the rider's colour.
--                          Its head is at the front (-Z); the rider's root stands over its middle.
--   RockinRacewayCarrot    an orange dash panel on the track (3.8 x 4) with a big carrot and arrows.
--   RockinRacewayHurdle    a blue slow panel with a low striped hurdle (bar top 0.8 studs up).
--   RockinRacewayTurn      half of one of the oval's turns (dirt, lane lines, curbs); dirt top at 0.4.
--   RockinRacewayArch      the finish arch (pillars 63 studs apart along X); the game hangs the banner.
--   RockinRacewayFence     10 studs of white fence along X.
--   RockinRacewayBunting   two striped poles 20 studs apart with pennants strung between.
--   RockinRacewayStand     a grandstand of cheering fans under a striped awning, facing -Z.
--   RockinRacewayCarousel  the merry-go-round in the infield.
--   RockinRacewayTent      a striped fair tent (Stripes recoloured per tent).
--   RockinRacewayWheel     a Ferris wheel past the back straight.
return function(h)
	local rgb = h.rgb
	local metal = Enum.Material.Metal
	local wood = Enum.Material.Wood
	local fabric = Enum.Material.Fabric
	local neon = Enum.Material.Neon

	return {
		RockinRacewayHorse = {
			Height = 4.62,
			AssetId = 126786881978749, -- tools/upload_assets.py --only RockinRacewayHorse fills this in
			Shadow = true,
			Palette = {
				Body = rgb(255, 80, 90),
				Mane = rgb(255, 244, 214),
				Ears = rgb(255, 205, 190),
				Eyes = rgb(255, 255, 255),
				Pupils = rgb(35, 30, 45),
				Bridle = rgb(60, 120, 230),
				Studs = rgb(255, 205, 50),
				Stick = rgb(196, 140, 84),
				Wheel = rgb(60, 60, 75),
			},
			Materials = { Body = fabric, Mane = fabric, Stick = wood, Studs = metal },
			Fallback = function(m)
				h.blob(m, "Body", Vector3.new(1.0, 1.1, 1.6), Vector3.new(0, 3.7, -1.3))
				h.blob(m, "Body", Vector3.new(0.75, 0.7, 0.9), Vector3.new(0, 3.4, -1.95))
				h.blob(m, "Mane", Vector3.new(0.3, 1.2, 0.5), Vector3.new(0, 3.9, -0.65))
				h.blob(m, "Ears", Vector3.new(0.7, 0.5, 0.2), Vector3.new(0, 4.37, -0.92))
				h.blob(m, "Eyes", Vector3.new(1.2, 0.25, 0.16), Vector3.new(0, 3.86, -1.3))
				h.capsule(
					m,
					"Stick",
					3.7,
					0.24,
					CFrame.lookAt(Vector3.new(0, 1.7, 0.6), Vector3.new(0, 0.42, 1.75))
						* CFrame.Angles(math.rad(90), 0, 0)
				)
				h.roller(m, "Stick", 0.16, 1.9, Vector3.new(0, 3.02, -0.62))
				h.roller(m, "Wheel", 0.84, 0.2, Vector3.new(0, 0.42, 1.75))
			end,
		},
		RockinRacewayCarrot = {
			Height = 0.41,
			AssetId = 84877669459711,
			Collide = false, -- a flat panel on the track: decoration only
			Shadow = false,
			Palette = {
				Pad = rgb(255, 140, 40),
				Trim = rgb(255, 250, 235),
				Carrot = rgb(255, 110, 25),
				Leaves = rgb(90, 200, 80),
			},
			Materials = { Pad = Enum.Material.SmoothPlastic },
			Fallback = function(m)
				h.block(m, "Pad", Vector3.new(3.8, 0.16, 4), Vector3.new(0, 0.08, 0))
				h.blob(m, "Carrot", Vector3.new(0.8, 0.31, 1.8), Vector3.new(0, 0.255, -0.1)) -- (top at 0.41, like the mesh)
				h.blob(m, "Leaves", Vector3.new(0.7, 0.1, 0.5), Vector3.new(0, 0.3, 1.1))
				h.block(m, "Trim", Vector3.new(1.4, 0.08, 0.28), Vector3.new(0, 0.21, -1.5))
			end,
		},
		RockinRacewayHurdle = {
			Height = 0.8,
			AssetId = 121724237313910,
			Collide = false, -- riders hop it; the game judges the bump, nothing physical
			Shadow = false,
			Palette = {
				Pad = rgb(60, 130, 240),
				Trim = rgb(235, 245, 255),
				Posts = rgb(250, 250, 250),
				BarA = rgb(40, 100, 220),
				BarB = rgb(250, 250, 250),
			},
			Fallback = function(m)
				h.block(m, "Pad", Vector3.new(3.8, 0.16, 4), Vector3.new(0, 0.08, 0))
				h.block(m, "Posts", Vector3.new(0.18, 0.64, 0.18), Vector3.new(-1.55, 0.48, 0))
				h.block(m, "Posts", Vector3.new(0.18, 0.64, 0.18), Vector3.new(1.55, 0.48, 0))
				h.block(m, "BarA", Vector3.new(3.0, 0.2, 0.2), Vector3.new(0, 0.7, 0))
			end,
		},
		RockinRacewayTurn = {
			Height = 0.58,
			AssetId = 136616326775445,
			Collide = false, -- the grass slab under it is the solid ground
			Shadow = false,
			Palette = {
				Dirt = rgb(214, 160, 104),
				Lines = rgb(250, 248, 240),
				CurbRed = rgb(235, 60, 60),
				CurbWhite = rgb(250, 248, 240),
			},
			Fallback = function(m)
				-- Dirt sectors fanned round the half circle, each a little lower than the last so
				-- their overlaps never share a plane.
				local count = 18
				for k = 0, count - 1 do
					local a = -math.pi / 2 + (k + 0.5) * math.pi / count
					local middle = 58
					local length = 2 * 86.8 * math.sin(math.pi / count / 2) + 0.4
					local part = h.block(m, "Dirt", Vector3.new(55.8, 0.4 - (k % 2) * 0.2, length), Vector3.zero)
					part.CFrame = CFrame.new(math.cos(a) * middle, 0.2 - (k % 2) * 0.02, math.sin(a) * middle)
						* CFrame.Angles(0, -a, 0)
				end
				h.block(m, "CurbRed", Vector3.new(1.8, 0.28, 0.4), Vector3.new(85.9, 0.44, 0))
			end,
		},
		RockinRacewayArch = {
			Height = 22.6,
			AssetId = 128963519431134,
			Collide = false, -- it stands outside the curbs; nothing to climb
			BlocksCamera = { "CheckDark", "CheckLight" },
			Palette = {
				CheckDark = rgb(35, 35, 45),
				CheckLight = rgb(250, 250, 250),
				Gold = rgb(255, 200, 60),
				Beam = rgb(230, 50, 70),
				Bulbs = rgb(255, 240, 150),
				Ropes = rgb(120, 90, 60),
			},
			Materials = { Gold = metal, Bulbs = neon },
			Fallback = function(m)
				for _, side in { -1, 1 } do
					h.block(m, "CheckDark", Vector3.new(2.4, 19.2, 2.4), Vector3.new(side * 31.5, 10.4, 0))
					h.block(m, "Gold", Vector3.new(3.4, 0.8, 3.4), Vector3.new(side * 31.5, 0.4, 0))
					h.ball(m, "Gold", 2, Vector3.new(side * 31.5, 21.45, 0))
				end
				h.block(m, "Beam", Vector3.new(64.4, 1.4, 1.4), Vector3.new(0, 20.6, 0))
			end,
		},
		RockinRacewayFence = {
			Height = 2.79,
			AssetId = 101784712044453,
			Collide = false, -- nobody walks here: riders stay on the track
			Shadow = false,
			Palette = { Rails = rgb(250, 250, 250), Posts = rgb(250, 250, 250), Caps = rgb(230, 60, 70) },
			Fallback = function(m)
				h.block(m, "Rails", Vector3.new(9.96, 0.24, 0.16), Vector3.new(0, 1.2, 0))
				h.block(m, "Rails", Vector3.new(9.96, 0.24, 0.16), Vector3.new(0, 2.2, 0))
				for _, x in { -2.5, 2.5 } do
					h.block(m, "Posts", Vector3.new(0.34, 2.5, 0.34), Vector3.new(x, 1.25, 0))
					h.ball(m, "Caps", 0.48, Vector3.new(x, 2.55, 0))
				end
			end,
		},
		RockinRacewayBunting = {
			Height = 9.3,
			AssetId = 91393016743628,
			Collide = false,
			Palette = {
				Pole = rgb(250, 250, 250),
				Stripes = rgb(230, 60, 70),
				Top = rgb(255, 200, 60),
				String = rgb(90, 80, 70),
				FlagA = rgb(255, 90, 140),
				FlagB = rgb(80, 170, 255),
				FlagC = rgb(255, 210, 60),
			},
			Materials = { FlagA = fabric, FlagB = fabric, FlagC = fabric, Top = metal },
			Fallback = function(m)
				for _, x in { -10, 10 } do
					h.pillar(m, "Pole", 0.4, 8.6, Vector3.new(x, 4.3, 0))
					h.ball(m, "Top", 0.8, Vector3.new(x, 8.9, 0))
				end
				h.block(m, "String", Vector3.new(20, 0.1, 0.1), Vector3.new(0, 7.7, 0))
				for k = 0, 6 do
					h.block(
						m,
						if k % 2 == 0 then "FlagA" else "FlagB",
						Vector3.new(1, 1, 0.05),
						Vector3.new(-8.5 + k * 2.8, 7.1, 0)
					)
				end
			end,
		},
		RockinRacewayStand = {
			Height = 14.1,
			AssetId = 75906433740655,
			Collide = false, -- behind the fence, out of reach
			BlocksCamera = true,
			Palette = {
				Frame = rgb(225, 220, 210),
				Seats = rgb(70, 150, 255),
				FansA = rgb(255, 110, 90),
				FansB = rgb(90, 200, 120),
				FansC = rgb(250, 210, 70),
				Heads = rgb(240, 200, 160),
				Posts = rgb(250, 250, 250),
				AwningA = rgb(230, 60, 70),
				AwningB = rgb(250, 250, 250),
			},
			Materials = { AwningA = fabric, AwningB = fabric },
			Fallback = function(m)
				for k = 0, 4 do
					h.block(
						m,
						"Frame",
						Vector3.new(40, 0.4 + k * 1.3, 2.6),
						Vector3.new(0, (0.4 + k * 1.3) / 2, -5.7 + k * 2.6)
					)
					h.block(
						m,
						if k % 2 == 0 then "FansA" else "FansB",
						Vector3.new(36, 1.6, 0.8),
						Vector3.new(0, 1.9 + k * 1.3, -5.4 + k * 2.6)
					)
				end
				h.block(m, "AwningA", Vector3.new(41, 0.3, 15), Vector3.new(0, 12.3, -0.3)).CFrame *= CFrame.Angles(
					math.rad(12.7),
					0,
					0
				)
			end,
		},
		RockinRacewayCarousel = {
			Height = 17.4,
			AssetId = 112695960659311,
			Collide = false, -- in the infield, out of reach
			Palette = {
				Deck = rgb(250, 240, 220),
				Center = rgb(255, 180, 200),
				Mirrors = rgb(200, 230, 255),
				Horses = rgb(250, 250, 250),
				Poles = rgb(255, 200, 60),
				CanopyA = rgb(230, 60, 70),
				CanopyB = rgb(250, 250, 250),
				Flag = rgb(80, 170, 255),
			},
			Materials = { Poles = metal, Mirrors = Enum.Material.Glass, CanopyA = fabric, CanopyB = fabric },
			Fallback = function(m)
				h.pillar(m, "Deck", 22.6, 1, Vector3.new(0, 0.5, 0))
				h.pillar(m, "Center", 4.4, 9.5, Vector3.new(0, 5.75, 0))
				h.pillar(m, "CanopyA", 24.4, 1.2, Vector3.new(0, 10.8, 0))
				h.blob(m, "CanopyB", Vector3.new(20, 8, 20), Vector3.new(0, 11.4, 0))
				for k = 0, 9 do
					local a = k * math.pi / 5
					h.pillar(m, "Poles", 0.24, 9, Vector3.new(math.cos(a) * 8.6, 5.5, math.sin(a) * 8.6))
					h.blob(
						m,
						"Horses",
						Vector3.new(1.1, 1.2, 2.6),
						Vector3.new(math.cos(a) * 8.6, 3.4, math.sin(a) * 8.6)
					)
				end
				h.ball(m, "Flag", 0.9, Vector3.new(0, 16.95, 0))
			end,
		},
		RockinRacewayTent = {
			Height = 9.6,
			AssetId = 110175596841138,
			Collide = false,
			Palette = {
				Walls = rgb(250, 250, 250),
				Stripes = rgb(230, 60, 70),
				Roof = rgb(250, 250, 250),
				Door = rgb(60, 40, 70),
				Pole = rgb(120, 90, 60),
				Pennant = rgb(255, 210, 60),
			},
			Materials = { Walls = fabric, Stripes = fabric, Roof = fabric },
			Fallback = function(m)
				h.pillar(m, "Walls", 8, 3.6, Vector3.new(0, 1.8, 0))
				h.blob(m, "Stripes", Vector3.new(9.4, 5.6, 9.4), Vector3.new(0, 4.8, 0))
				h.pillar(m, "Pole", 0.16, 2, Vector3.new(0, 8.6, 0))
			end,
		},
		RockinRacewayWheel = {
			Height = 45.9,
			AssetId = 129216002551582,
			Collide = false, -- far past the back straight
			Palette = {
				Rim = rgb(250, 250, 250),
				Spokes = rgb(220, 220, 230),
				Legs = rgb(70, 120, 220),
				GondolaA = rgb(255, 90, 120),
				GondolaB = rgb(80, 190, 255),
				Gold = rgb(255, 200, 60),
				Lights = rgb(255, 240, 150),
			},
			Materials = { Rim = metal, Spokes = metal, Gold = metal, Lights = neon },
			Fallback = function(m)
				h.block(m, "Legs", Vector3.new(30, 0.8, 9), Vector3.new(0, 0.4, 0))
				h.roller(m, "Rim", 41, 2.8, Vector3.new(0, 25, 0)).CFrame *= CFrame.Angles(0, math.rad(90), 0)
				for _, side in { -1, 1 } do
					h.capsule(
						m,
						"Legs",
						27,
						1,
						CFrame.new(side * 6.5, 12.5, side * 0.4) * CFrame.Angles(0, 0, side * math.rad(27))
					)
				end
			end,
		},
	}
end

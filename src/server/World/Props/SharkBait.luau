-- Props for Shark Bait. MeshLibrary loads this file at startup (see World/Props/README.md). The
-- meshes come from tools/meshgen/props/SharkBait.py; until each is uploaded its Fallback is used.
-- Pieces the client half animates: the shark's Jaw and JawTeeth (they turn together about the back
-- of the mouth) and its Tail (it wags about its front end). The raft's deck top is the mesh's top
-- (the game puts it exactly level with the raft's collider).
return function(h)
	-- A wedge (a fin or a sail) for the fallbacks.
	local function wedge(m: Model, name: string, size: Vector3, cframe: CFrame)
		h.Build.Wedge({ Name = name, Size = size, CFrame = cframe, Parent = m })
	end
	-- Every fallback ends on a level pivot: MeshLibrary measures a prop's height along its pivot's
	-- axes, and a pivot that took after a turned part (an upright cylinder is a turned one) measured
	-- the rafts 7 times too small and the sea stacks 2.5 times too big.
	local function level(parts: (m: Model) -> ()): (m: Model) -> ()
		return function(m: Model)
			parts(m)
			m.WorldPivot = CFrame.new()
		end
	end
	return {
		-- A cartoon great white, snout at -Z. The game floats it with y = 2.6 at the waterline.
		SharkBaitShark = {
			Height = 6,
			AssetId = 99900036698603,
			Palette = {
				Body = h.rgb(110, 130, 160),
				Tail = h.rgb(110, 130, 160),
				Belly = h.rgb(240, 240, 232),
				Jaw = h.rgb(240, 240, 232),
				Mouth = h.rgb(170, 40, 60),
				Teeth = h.rgb(255, 255, 250),
				JawTeeth = h.rgb(255, 255, 250),
				Eyes = h.rgb(20, 20, 30),
				EyeShine = h.rgb(255, 255, 255),
				Gills = h.rgb(70, 85, 110),
			},
			Materials = { Eyes = Enum.Material.Glass, EyeShine = Enum.Material.Neon },
			Fallback = level(function(m)
				h.blob(m, "Body", Vector3.new(3.2, 3.3, 11), Vector3.new(0, 1.95, -0.4))
				h.blob(m, "Belly", Vector3.new(2.7, 1.7, 9), Vector3.new(0, 1.15, -0.6))
				wedge(m, "Body", Vector3.new(0.4, 2.7, 2.6), CFrame.new(0, 4.6, 0.6))
				wedge(m, "Tail", Vector3.new(0.4, 3.4, 1.8), CFrame.new(0, 3.1, 5.2))
				wedge(m, "Tail", Vector3.new(0.4, 1.6, 1.2), CFrame.new(0, 1.1, 5.1) * CFrame.Angles(math.pi, 0, 0))
				h.blob(m, "Jaw", Vector3.new(2.2, 0.7, 3.2), Vector3.new(0, 0.6, -3.9))
				h.block(m, "Mouth", Vector3.new(1.9, 0.5, 2.6), Vector3.new(0, 1.0, -3.9))
				h.block(m, "Teeth", Vector3.new(2.0, 0.25, 0.2), Vector3.new(0, 1.2, -5.1))
				h.block(m, "JawTeeth", Vector3.new(1.8, 0.25, 0.2), Vector3.new(0, 0.85, -5.0))
				for _, side in { -1, 1 } do
					h.ball(m, "Eyes", 0.5, Vector3.new(side * 1.3, 2.5, -3.4))
					h.blob(m, "Body", Vector3.new(2.6, 0.25, 1.2), Vector3.new(side * 2.0, 1.0, -1.3))
				end
			end),
		},
		-- A round log raft: deck radius 7 (the game scales it per raft), the deck's top at y = 2.
		SharkBaitRaft = {
			Height = 2,
			AssetId = 72954904653443,
			Palette = {
				Deck = h.rgb(196, 146, 92),
				Beams = h.rgb(140, 96, 60),
				Barrels = h.rgb(160, 104, 62),
				Hoops = h.rgb(90, 90, 100),
				Rope = h.rgb(226, 200, 150),
			},
			Materials = {
				Deck = Enum.Material.WoodPlanks,
				Beams = Enum.Material.Wood,
				Barrels = Enum.Material.Wood,
				Hoops = Enum.Material.Metal,
				Rope = Enum.Material.Fabric,
			},
			Fallback = level(function(m)
				h.pillar(m, "Deck", 14, 0.4, Vector3.new(0, 1.8, 0))
				-- (The biggest piece must sit level: MeshLibrary takes the pivot's turn from it.)
				h.block(m, "Beams", Vector3.new(9.5, 1, 9.5), Vector3.new(0, 1.1, 0))
				for index = 0, 7 do
					local angle = index / 8 * math.pi * 2
					h.pillar(m, "Barrels", 1.7, 1.3, Vector3.new(math.cos(angle) * 5, 0.65, math.sin(angle) * 5))
				end
			end),
		},
		SharkBaitCoin = {
			Height = 2,
			AssetId = 102971836785377,
			Shadow = false,
			Palette = { Coin = h.rgb(255, 205, 50), Rim = h.rgb(230, 165, 30) },
			Materials = { Coin = Enum.Material.Metal, Rim = Enum.Material.Metal },
			Fallback = level(function(m)
				local coin = h.roller(m, "Coin", 2, 0.32, Vector3.new(0, 1, 0))
				coin.CFrame = CFrame.new(0, 1, 0) * CFrame.Angles(0, math.rad(90), 0)
			end),
		},
		SharkBaitPearl = {
			Height = 1.6,
			AssetId = 97962283838819,
			Shadow = false,
			Palette = {
				Shell = h.rgb(255, 150, 170),
				ShellInside = h.rgb(255, 225, 230),
				Pearl = h.rgb(250, 245, 255),
			},
			Fallback = level(function(m)
				h.blob(m, "Shell", Vector3.new(2.2, 0.5, 2), Vector3.new(0, 0.25, 0))
				h.ball(m, "Pearl", 0.9, Vector3.new(0, 0.85, 0))
				h.blob(m, "Shell", Vector3.new(2.2, 1.4, 0.4), Vector3.new(0, 0.9, 0.8))
			end),
			PostProcess = function(model: Model)
				local pearl = model:FindFirstChild("Pearl", true)
				if pearl and pearl:IsA("BasePart") then
					pearl.Reflectance = 0.25
				end
			end,
		},
		SharkBaitChest = {
			Height = 2.4,
			AssetId = 136486848365204,
			Palette = {
				Wood = h.rgb(150, 90, 50),
				Trim = h.rgb(255, 200, 60),
				Gold = h.rgb(255, 215, 70),
				Lock = h.rgb(90, 90, 100),
			},
			Materials = { Wood = Enum.Material.WoodPlanks, Trim = Enum.Material.Metal, Lock = Enum.Material.Metal },
			Fallback = level(function(m)
				h.rounded(m, "Wood", Vector3.new(2.8, 1.5, 1.9), 0.15, Vector3.new(0, 0.75, 0))
				h.blob(m, "Gold", Vector3.new(2.4, 0.6, 1.6), Vector3.new(0, 1.6, 0))
				h.capsule(m, "Wood", 2.8, 0.9, CFrame.new(0, 2.0, 0.15) * CFrame.Angles(0, math.rad(90), 0))
				h.block(m, "Lock", Vector3.new(0.4, 0.5, 0.15), Vector3.new(0, 1.4, -0.98))
			end),
		},
		-- An inflatable swim ring, worn by swimmers while they're in the water.
		SharkBaitFloatie = {
			Height = 1,
			AssetId = 105609274155626,
			Shadow = false,
			Palette = { Ring = h.rgb(255, 120, 60), Stripes = h.rgb(255, 255, 255) },
			Fallback = level(function(m)
				for index = 0, 7 do
					local angle = index / 8 * math.pi * 2
					h.ball(
						m,
						if index % 2 == 0 then "Ring" else "Stripes",
						1,
						Vector3.new(math.cos(angle) * 1.3, 0.5, math.sin(angle) * 1.3)
					)
				end
			end),
		},
		-- The float line round the lagoon (radius 44), centered on the arena.
		SharkBaitFloatLine = {
			Height = 1.2,
			AssetId = 136466135059047,
			Shadow = false,
			Palette = { FloatsA = h.rgb(255, 210, 60), FloatsB = h.rgb(240, 70, 70), Rope = h.rgb(230, 225, 210) },
			Materials = { Rope = Enum.Material.Fabric },
			Fallback = level(function(m)
				for index = 0, 59 do
					local angle = index / 60 * math.pi * 2
					h.ball(
						m,
						if index % 2 == 0 then "FloatsA" else "FloatsB",
						1.2,
						Vector3.new(math.cos(angle) * 44, 0.6, math.sin(angle) * 44)
					)
				end
			end),
		},
		SharkBaitBuoy = {
			Height = 7,
			AssetId = 85083594096246,
			Palette = {
				Float = h.rgb(220, 60, 60),
				Stripe = h.rgb(245, 245, 245),
				Cage = h.rgb(70, 70, 80),
				Lamp = h.rgb(255, 220, 120),
				Flag = h.rgb(255, 210, 60),
				FlagMark = h.rgb(25, 25, 30),
			},
			Materials = { Cage = Enum.Material.Metal, Lamp = Enum.Material.Neon, Flag = Enum.Material.Fabric },
			Fallback = level(function(m)
				h.blob(m, "Float", Vector3.new(3.2, 1.8, 3.2), Vector3.new(0, 0.9, 0))
				h.pillar(m, "Stripe", 2.9, 0.4, Vector3.new(0, 1.3, 0))
				h.pillar(m, "Cage", 0.4, 4, Vector3.new(0, 3.6, 0))
				h.ball(m, "Lamp", 0.8, Vector3.new(0, 5.8, 0))
				h.block(m, "Flag", Vector3.new(0.1, 0.8, 1.2), Vector3.new(0, 6.5, 0.6))
			end),
		},
		-- A seagull gliding, wings spread (it circles high over the lagoon).
		SharkBaitGull = {
			Height = 1,
			AssetId = 82748078681255,
			Shadow = false,
			Palette = {
				Body = h.rgb(250, 250, 250),
				Wings = h.rgb(235, 238, 245),
				WingTips = h.rgb(70, 75, 90),
				Beak = h.rgb(255, 170, 40),
				Eyes = h.rgb(20, 20, 30),
			},
			Fallback = level(function(m)
				h.blob(m, "Body", Vector3.new(0.6, 0.6, 1.6), Vector3.new(0, 0.5, 0))
				h.block(m, "Wings", Vector3.new(3.4, 0.08, 0.6), Vector3.new(0, 0.7, 0.1))
				h.block(m, "WingTips", Vector3.new(4.2, 0.07, 0.4), Vector3.new(0, 0.72, 0.15))
				h.block(m, "Beak", Vector3.new(0.15, 0.15, 0.4), Vector3.new(0, 0.55, -0.95))
			end),
		},
		-- Under the water: coral heads, kelp and starfish on the lagoon floor.
		SharkBaitCoral = {
			Height = 6,
			AssetId = 78476909007682,
			Palette = {
				Rock = h.rgb(150, 140, 130),
				CoralA = h.rgb(255, 110, 140),
				CoralB = h.rgb(255, 170, 60),
				CoralC = h.rgb(150, 110, 255),
				Fan = h.rgb(255, 90, 90),
			},
			Materials = { Rock = Enum.Material.Slate },
			Fallback = level(function(m)
				h.blob(m, "Rock", Vector3.new(8, 2, 6), Vector3.new(0, 1, 0))
				h.blob(m, "CoralA", Vector3.new(2.4, 3.6, 2.4), Vector3.new(-1.8, 3.4, 0))
				h.ball(m, "CoralB", 2.6, Vector3.new(1.6, 2.6, 0.6))
				h.blob(m, "CoralC", Vector3.new(1.4, 4, 1.4), Vector3.new(0.4, 3.9, -1.4))
				h.block(m, "Fan", Vector3.new(2.4, 2.6, 0.15), Vector3.new(-0.2, 3.2, 1.6))
			end),
		},
		SharkBaitKelp = {
			Height = 12,
			AssetId = 90541970109554,
			Shadow = false,
			Palette = { Kelp = h.rgb(60, 160, 90), Bulbs = h.rgb(150, 190, 70) },
			Fallback = level(function(m)
				for index = 0, 3 do
					local angle = index / 4 * math.pi * 2
					local height = 9 + index
					h.block(
						m,
						"Kelp",
						Vector3.new(0.7, height, 0.1),
						Vector3.new(math.cos(angle) * 0.9, height / 2, math.sin(angle) * 0.9)
					)
					h.ball(m, "Bulbs", 0.5, Vector3.new(math.cos(angle) * 0.9, height * 0.6, math.sin(angle) * 0.9))
				end
			end),
		},
		SharkBaitStarfish = {
			Height = 0.5,
			AssetId = 134189417101621,
			Shadow = false,
			Palette = { Star = h.rgb(255, 130, 60), Dots = h.rgb(255, 220, 170) },
			Fallback = level(function(m)
				for index = 0, 4 do
					local angle = index / 5 * math.pi * 2
					local at = Vector3.new(math.sin(angle) * 0.65, 0.22, math.cos(angle) * 0.65)
					local arm = h.blob(m, "Star", Vector3.new(0.6, 0.45, 1.3), at)
					arm.CFrame = CFrame.new(at) * CFrame.Angles(0, angle, 0)
				end
				h.ball(m, "Dots", 0.5, Vector3.new(0, 0.25, 0))
			end),
		},
		-- A low sand bar for the scenery; its base sits 2 studs under the water.
		SharkBaitSandBar = {
			Height = 3,
			AssetId = 114062864335104,
			Shadow = false,
			Palette = { Sand = h.rgb(240, 220, 170), WetSand = h.rgb(200, 175, 130), Shells = h.rgb(255, 235, 220) },
			Materials = { Sand = Enum.Material.Sand, WetSand = Enum.Material.Sand },
			Fallback = level(function(m)
				h.blob(m, "WetSand", Vector3.new(40, 4, 24), Vector3.new(0, 0.8, 0))
				h.blob(m, "Sand", Vector3.new(34, 4.4, 19), Vector3.new(0, 0.8, 0))
			end),
		},
		-- A lifeguard tower on stilts, its warning sign facing -Z.
		SharkBaitHut = {
			Height = 18,
			AssetId = 91252373330148,
			Palette = {
				Stilts = h.rgb(235, 235, 230),
				Cabin = h.rgb(230, 70, 60),
				Roof = h.rgb(250, 250, 245),
				Ladder = h.rgb(200, 150, 90),
				Sign = h.rgb(255, 210, 60),
				SignMark = h.rgb(25, 25, 30),
				Float = h.rgb(255, 120, 40),
				FloatStripe = h.rgb(255, 255, 255),
				Flag = h.rgb(230, 50, 50),
			},
			Materials = {
				Stilts = Enum.Material.Wood,
				Cabin = Enum.Material.WoodPlanks,
				Ladder = Enum.Material.Wood,
				Flag = Enum.Material.Fabric,
			},
			Fallback = level(function(m)
				for _, x in { -2.6, 2.6 } do
					for _, z in { -2.6, 2.6 } do
						h.pillar(m, "Stilts", 0.5, 9, Vector3.new(x, 4.5, z))
					end
				end
				h.rounded(m, "Cabin", Vector3.new(6.4, 4.4, 6.4), 0.3, Vector3.new(0, 11.2, 0))
				h.blob(m, "Roof", Vector3.new(8, 2.4, 8), Vector3.new(0, 14.2, 0))
				h.pillar(m, "Stilts", 0.25, 2.6, Vector3.new(0, 16.6, 0))
				h.block(m, "Flag", Vector3.new(0.1, 1, 1.6), Vector3.new(0, 17.4, 0.8))
				h.block(m, "Sign", Vector3.new(2.6, 2.6, 0.2), Vector3.new(0, 11.4, -3.3))
			end),
		},
		SharkBaitLighthouse = {
			Height = 46,
			AssetId = 133994622737467,
			Palette = {
				Rock = h.rgb(120, 112, 104),
				Grass = h.rgb(100, 180, 80),
				Tower = h.rgb(245, 245, 240),
				Stripes = h.rgb(220, 60, 60),
				Rail = h.rgb(60, 60, 70),
				Lantern = h.rgb(255, 230, 140),
				Roof = h.rgb(200, 50, 50),
				Door = h.rgb(110, 70, 45),
			},
			Materials = {
				Rock = Enum.Material.Slate,
				Grass = Enum.Material.Grass,
				Rail = Enum.Material.Metal,
				Lantern = Enum.Material.Neon,
				Door = Enum.Material.Wood,
			},
			Fallback = level(function(m)
				h.blob(m, "Rock", Vector3.new(22, 10, 20), Vector3.new(0, 4, 0))
				h.pillar(m, "Tower", 6, 26, Vector3.new(0, 21, 0))
				for index = 0, 2 do
					h.pillar(m, "Stripes", 6.1, 3, Vector3.new(0, 12 + index * 8, 0))
				end
				h.pillar(m, "Lantern", 4, 4, Vector3.new(0, 36, 0))
				h.blob(m, "Roof", Vector3.new(5.4, 5, 5.4), Vector3.new(0, 40.5, 0))
			end),
		},
		SharkBaitShipwreck = {
			Height = 34,
			AssetId = 107993268017094,
			Palette = {
				Hull = h.rgb(110, 70, 45),
				Planks = h.rgb(150, 100, 60),
				Trim = h.rgb(200, 160, 70),
				Mast = h.rgb(120, 80, 50),
				Sail = h.rgb(235, 225, 200),
				Flag = h.rgb(30, 30, 35),
				FlagMark = h.rgb(245, 245, 245),
				Rope = h.rgb(210, 190, 150),
			},
			Materials = {
				Hull = Enum.Material.WoodPlanks,
				Planks = Enum.Material.WoodPlanks,
				Mast = Enum.Material.Wood,
				Sail = Enum.Material.Fabric,
				Flag = Enum.Material.Fabric,
				Rope = Enum.Material.Fabric,
			},
			Fallback = level(function(m)
				h.rounded(m, "Hull", Vector3.new(13, 9, 46), 3, Vector3.new(0, 4.5, 0))
				h.pillar(m, "Mast", 1.2, 24, Vector3.new(0, 20, -2))
				h.block(m, "Sail", Vector3.new(10, 8, 0.2), Vector3.new(0, 24, -1))
				h.block(m, "Flag", Vector3.new(0.1, 2.2, 3.2), Vector3.new(0, 32.5, -1))
			end),
		},
		-- A tall limestone sea stack with jungle on top; its waterline is about 4 studs up.
		SharkBaitSeaStack = {
			Height = 48,
			AssetId = 81005352097958,
			Shadow = false,
			Palette = { Rock = h.rgb(170, 160, 140), Jungle = h.rgb(70, 150, 70), Foam = h.rgb(240, 250, 255) },
			Materials = { Rock = Enum.Material.Limestone, Jungle = Enum.Material.Grass },
			Fallback = level(function(m)
				h.blob(m, "Rock", Vector3.new(18, 30, 16), Vector3.new(0, 15, 0))
				h.blob(m, "Rock", Vector3.new(13, 24, 12), Vector3.new(0, 32, 0))
				h.blob(m, "Jungle", Vector3.new(15, 6, 14), Vector3.new(0, 45, 0))
				h.pillar(m, "Foam", 19, 0.4, Vector3.new(0, 4, 0))
			end),
		},
	}
end

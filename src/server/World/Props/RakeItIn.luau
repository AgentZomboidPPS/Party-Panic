-- Props for Rake It In (meshes from tools/meshgen/props/RakeItIn.py):
--   TurningField    the big round field that turns in the middle of the farm (41 studs across, a hole
--                   for the silo in its middle). Clients spin their own copy; the server's stays still.
--   HarvestSilo     the red silo in the middle; produce pops out of its vent cap.
--   GardenRake      the rake each player pulls produce in with. Built standing up (grip at the bottom,
--                   tines pointing forward, -Z); the client lays it down and stretches a handle to it.
--   BushelBasket    each player's basket, open at the top.
--   VeggieCarrot / VeggieTomato / VeggieBroccoli (1 point), GoldenPumpkin (3), VeggieBomb (-3).
-- Piece names matter to the client half (src/client/MiniGames/RakeItIn.luau), so the fallbacks use
-- the same names.

return function(h)
	local rgb = h.rgb
	local Build = h.Build

	-- A flat ring of wedge-ish blocks around the Y axis (the fallback field's rim and lip).
	local function ringOf(m: Model, name: string, radius: number, y: number, size: Vector3, count: number)
		for index = 0, count - 1 do
			local angle = index / count * math.pi * 2
			Build.Part({
				Name = name,
				Size = size,
				CFrame = CFrame.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
					* CFrame.Angles(0, -angle + math.pi / 2, 0),
				Parent = m,
			})
		end
	end

	return {
		TurningField = {
			Height = 1.873,
			AssetId = 76308012944899,
			Palette = {
				FieldWood = rgb(176, 116, 66),
				FieldLip = rgb(214, 64, 52),
				FieldMarks = rgb(255, 238, 196),
				FieldSoil = rgb(124, 82, 52),
				FieldSprouts = rgb(112, 204, 72),
			},
			Materials = {
				FieldWood = Enum.Material.WoodPlanks,
				FieldLip = Enum.Material.Wood,
				FieldSoil = Enum.Material.Ground,
			},
			Fallback = function(m)
				Build.Part({
					Name = "FieldSoil",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(1.3, 39.6, 39.6),
					CFrame = CFrame.new(0, 0.65, 0) * CFrame.Angles(0, 0, math.rad(90)),
					Parent = m,
				})
				ringOf(m, "FieldWood", 20.1, 0.72, Vector3.new(3.3, 1.45, 0.85), 40)
				ringOf(m, "FieldLip", 20.1, 1.6, Vector3.new(3.4, 0.3, 1.05), 40)
				ringOf(m, "FieldWood", 7.4, 0.8, Vector3.new(1.4, 1.6, 0.75), 32)
				for index = 0, 19 do
					local angle = index / 20 * math.pi * 2
					Build.Part({
						Name = "FieldSprouts",
						Size = Vector3.new(10, 0.2, 0.35),
						CFrame = CFrame.new(math.cos(angle) * 14, 1.35, math.sin(angle) * 14)
							* CFrame.Angles(0, -angle, 0),
						Parent = m,
					})
				end
				ringOf(m, "FieldMarks", 20.62, 0.8, Vector3.new(0.8, 1.0, 0.12), 8)
			end,
		},
		HarvestSilo = {
			Height = 19.5,
			AssetId = 85599049692297,
			Collide = true,
			Palette = {
				SiloStone = rgb(160, 152, 146),
				SiloBody = rgb(204, 52, 46),
				SiloTrim = rgb(252, 246, 236),
				SiloDoor = rgb(116, 64, 42),
				SiloRoof = rgb(198, 204, 214),
				SiloLadder = rgb(84, 84, 96),
			},
			Materials = {
				SiloStone = Enum.Material.Cobblestone,
				SiloBody = Enum.Material.CorrodedMetal,
				SiloDoor = Enum.Material.WoodPlanks,
				SiloRoof = Enum.Material.Metal,
				SiloLadder = Enum.Material.Metal,
			},
			Fallback = function(m)
				h.pillar(m, "SiloStone", 14, 1.75, Vector3.new(0, 0.875, 0))
				h.pillar(m, "SiloBody", 10.6, 11.9, Vector3.new(0, 7.45, 0))
				for _, y in { 1.8, 5.6, 9.4, 13.2 } do
					h.pillar(m, "SiloTrim", 11, 0.32, Vector3.new(0, y, 0))
				end
				h.blob(m, "SiloRoof", Vector3.new(11.5, 8.6, 11.5), Vector3.new(0, 13.2, 0))
				h.pillar(m, "SiloRoof", 2.5, 1.2, Vector3.new(0, 17.8, 0))
				h.pillar(m, "SiloRoof", 3.9, 1.0, Vector3.new(0, 19.0, 0))
				h.block(m, "SiloDoor", Vector3.new(3.4, 4.6, 0.3), Vector3.new(0, 4.0, -5.27))
			end,
		},
		GardenRake = {
			Height = 7.22,
			AssetId = 132623769464339,
			Palette = {
				RakeHandle = rgb(200, 144, 88),
				RakeGrip = rgb(255, 205, 50),
				RakeHead = rgb(232, 56, 62),
				RakeTines = rgb(206, 212, 222),
			},
			Materials = { RakeTines = Enum.Material.Metal },
			Fallback = function(m)
				h.pillar(m, "RakeHandle", 0.34, 6.2, Vector3.new(0, 3.65, 0))
				h.pillar(m, "RakeGrip", 0.44, 1.1, Vector3.new(0, 0.55, 0))
				h.rounded(m, "RakeHead", Vector3.new(4.3, 0.34, 0.46), 0.15, Vector3.new(0, 7.02, -0.05))
				for index = 0, 9 do
					local x = -1.9 + index * 3.8 / 9
					h.block(m, "RakeTines", Vector3.new(0.13, 0.13, 1.1), Vector3.new(x, 6.88, -0.75))
				end
			end,
		},
		BushelBasket = {
			Height = 3.04,
			AssetId = 136309655092045,
			Collide = true,
			Palette = {
				BushelWood = rgb(226, 182, 116),
				BushelBands = rgb(96, 86, 98),
				BushelHandles = rgb(170, 112, 62),
			},
			Materials = { BushelWood = Enum.Material.Wood, BushelBands = Enum.Material.Metal },
			Fallback = function(m)
				h.pillar(m, "BushelWood", 3.6, 2.7, Vector3.new(0, 1.55, 0))
				h.pillar(m, "BushelBands", 4.1, 0.25, Vector3.new(0, 2.92, 0))
				h.pillar(m, "BushelBands", 3.5, 0.2, Vector3.new(0, 0.55, 0))
			end,
		},
		VeggieCarrot = {
			Height = 2.0,
			AssetId = 117945456983708,
			Palette = { CarrotRoot = rgb(255, 136, 32), CarrotLeaves = rgb(80, 186, 64) },
			Fallback = function(m)
				h.capsule(m, "CarrotRoot", 3.0, 1.0, CFrame.new(0.3, 0.6, 0) * CFrame.Angles(0, 0, math.rad(78)))
				h.ball(m, "CarrotLeaves", 1.2, Vector3.new(2.0, 1.3, 0))
			end,
		},
		VeggieTomato = {
			Height = 1.9,
			AssetId = 107546864650370,
			Palette = { TomatoBody = rgb(236, 48, 42), TomatoLeaves = rgb(64, 156, 54) },
			Materials = { TomatoBody = Enum.Material.SmoothPlastic },
			Fallback = function(m)
				h.blob(m, "TomatoBody", Vector3.new(2.2, 1.7, 2.2), Vector3.new(0, 0.85, 0))
				h.pillar(m, "TomatoLeaves", 0.25, 0.4, Vector3.new(0, 1.85, 0))
			end,
		},
		VeggieBroccoli = {
			Height = 2.4,
			AssetId = 131970749623975,
			Palette = { BroccoliStalk = rgb(170, 214, 112), BroccoliCrown = rgb(52, 144, 58) },
			Fallback = function(m)
				h.pillar(m, "BroccoliStalk", 0.8, 1.2, Vector3.new(0, 0.6, 0))
				h.blob(m, "BroccoliCrown", Vector3.new(2.1, 1.5, 2.1), Vector3.new(0, 1.65, 0))
			end,
		},
		GoldenPumpkin = {
			Height = 2.9,
			AssetId = 106507537768183,
			Palette = { PumpkinBody = rgb(255, 196, 40), PumpkinStem = rgb(98, 150, 56) },
			Materials = { PumpkinBody = Enum.Material.Foil },
			Fallback = function(m)
				h.blob(m, "PumpkinBody", Vector3.new(3.4, 2.4, 3.4), Vector3.new(0, 1.2, 0))
				h.pillar(m, "PumpkinStem", 0.4, 0.6, Vector3.new(0, 2.6, 0))
			end,
		},
		VeggieBomb = {
			Height = 2.3,
			AssetId = 93653961212537,
			Palette = {
				BombBody = rgb(42, 40, 56),
				BombCap = rgb(152, 158, 172),
				BombFuse = rgb(218, 182, 122),
				BombShine = rgb(240, 240, 255),
			},
			Materials = { BombCap = Enum.Material.Metal },
			Fallback = function(m)
				h.ball(m, "BombBody", 1.6, Vector3.new(0, 0.8, 0))
				h.pillar(m, "BombCap", 0.7, 0.3, Vector3.new(0, 1.6, 0))
				h.pillar(m, "BombFuse", 0.16, 0.6, Vector3.new(0, 2.0, 0))
			end,
		},
	}
end

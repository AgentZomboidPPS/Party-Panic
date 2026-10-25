-- Props for Tanks! (meshes from tools/meshgen/props/Tanks.py; until one is uploaded its Fallback
-- is used). The tank's hull is 6.4 x 7.6 studs, exactly the footprint the rules use
-- (Shared/Logic/TankField), its turret turns on the hull's center, and the client colours its
-- "Body" and "Turret" pieces per tank. Only the wooden blocks collide (plain convex boxes, exactly
-- what's drawn); everything else is decoration nobody can stand on.
return function(h)
	return {
		TanksTank = {
			Height = 5.76,
			AssetId = 109025665137831,
			Collide = false,
			Palette = {
				Body = h.rgb(232, 64, 58),
				Turret = h.rgb(232, 64, 58),
				Tracks = h.rgb(52, 50, 56),
				Wheels = h.rgb(190, 192, 200),
				Trim = h.rgb(250, 238, 205),
				Barrel = h.rgb(88, 92, 104),
				Hatch = h.rgb(70, 72, 80),
				Badge = h.rgb(250, 250, 245),
			},
			Materials = { Barrel = Enum.Material.Metal, Wheels = Enum.Material.Metal },
			Fallback = function(m)
				for _, side in { -1, 1 } do
					h.rounded(m, "Tracks", Vector3.new(1.5, 2.1, 7.6), 0.5, Vector3.new(side * 2.45, 1.05, 0))
				end
				h.rounded(m, "Body", Vector3.new(4.2, 1.5, 6.8), 0.35, Vector3.new(0, 2.15, 0))
				h.pillar(m, "Turret", 3.8, 1.5, Vector3.new(0, 3.65, 0))
				h.capsule(m, "Barrel", 3.4, 0.7, CFrame.new(0, 3.1, -3.5) * CFrame.Angles(0, math.rad(90), 0))
				h.pillar(m, "Hatch", 2.2, 0.3, Vector3.new(0, 4.45, 0))
				h.pillar(m, "Hatch", 0.12, 2.0, Vector3.new(-1.3, 4.76, 1.3))
			end,
		},
		TanksShell = {
			Height = 0.89,
			AssetId = 83375380421145,
			Collide = false,
			Palette = { Shell = h.rgb(70, 72, 84) },
			Materials = { Shell = Enum.Material.Metal },
			Fallback = function(m)
				h.capsule(m, "Shell", 1.8, 0.9, CFrame.new(0, 0.45, 0) * CFrame.Angles(0, math.rad(90), 0))
			end,
		},
		TanksMine = {
			Height = 1.04,
			AssetId = 72829682312680,
			Collide = false,
			Palette = {
				Body = h.rgb(60, 62, 70),
				Band = h.rgb(250, 205, 50),
				Light = h.rgb(110, 20, 20),
			},
			Fallback = function(m)
				h.pillar(m, "Body", 2.6, 0.6, Vector3.new(0, 0.3, 0))
				h.pillar(m, "Band", 2.7, 0.2, Vector3.new(0, 0.5, 0))
				h.ball(m, "Light", 0.6, Vector3.new(0, 0.74, 0))
			end,
		},
		TanksBlock = {
			Height = 8.03,
			AssetId = 93151363928051,
			Collide = true,
			Palette = { Wood = h.rgb(232, 196, 140), Grain = h.rgb(196, 150, 96) },
			Materials = { Wood = Enum.Material.Wood, Grain = Enum.Material.Wood },
			Fallback = function(m)
				h.rounded(m, "Wood", Vector3.new(8, 8, 8), 0.5, Vector3.new(0, 4, 0))
			end,
			PostProcess = function(model: Model)
				-- Only the block itself is solid (its box is what's drawn); the painted grain isn't.
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") and part.Name == "Grain" then
						part.CanCollide = false
						part.CanQuery = false
					end
				end
			end,
		},
		TanksBrick = {
			Height = 4.3,
			AssetId = 124894763273127,
			Collide = false,
			Palette = { Plastic = h.rgb(225, 60, 55) },
			Fallback = function(m)
				h.rounded(m, "Plastic", Vector3.new(7.8, 3.6, 7.8), 0.3, Vector3.new(0, 1.8, 0))
				for _, x in { -1.9, 1.9 } do
					for _, z in { -1.9, 1.9 } do
						h.pillar(m, "Plastic", 2.2, 0.7, Vector3.new(x, 3.95, z))
					end
				end
			end,
		},
		TanksBear = {
			Height = 33.63,
			AssetId = 120595582935478,
			Collide = false,
			Palette = {
				Fur = h.rgb(176, 112, 62),
				Muzzle = h.rgb(240, 214, 170),
				Eyes = h.rgb(30, 24, 22),
				Bow = h.rgb(220, 50, 70),
			},
			Fallback = function(m)
				h.ball(m, "Fur", 18, Vector3.new(0, 9, 0))
				h.ball(m, "Fur", 14, Vector3.new(0, 24, 0))
				h.ball(m, "Fur", 5, Vector3.new(-5.5, 30, 0))
				h.ball(m, "Fur", 5, Vector3.new(5.5, 30, 0))
				h.ball(m, "Muzzle", 6, Vector3.new(0, 22.5, -5.6))
				h.block(m, "Bow", Vector3.new(7, 2.6, 2), Vector3.new(0, 17.4, -5))
			end,
		},
		TanksBall = {
			Height = 16.06,
			AssetId = 78105391753459,
			Collide = false,
			Palette = {
				Red = h.rgb(235, 60, 60),
				Yellow = h.rgb(250, 210, 60),
				Blue = h.rgb(60, 130, 235),
				White = h.rgb(250, 250, 245),
			},
			Fallback = function(m)
				h.ball(m, "Red", 16, Vector3.new(0, 8, 0))
			end,
		},
		TanksRug = {
			Height = 0.42,
			AssetId = 91404601726582,
			Collide = false,
			Palette = {
				Outer = h.rgb(120, 170, 220),
				Middle = h.rgb(250, 235, 200),
				Inner = h.rgb(240, 130, 120),
			},
			Materials = { Outer = Enum.Material.Fabric, Middle = Enum.Material.Fabric, Inner = Enum.Material.Fabric },
			Fallback = function(m)
				local rug = h.pillar(m, "Outer", 44, 0.4, Vector3.new(0, 0.2, 0))
				rug.Material = Enum.Material.Fabric
			end,
		},
		TanksCrayon = {
			Height = 1.9,
			AssetId = 122708381994355,
			Collide = false,
			Palette = { Wax = h.rgb(235, 70, 60), Wrapper = h.rgb(245, 140, 130) },
			Fallback = function(m)
				h.capsule(m, "Wax", 16, 1.9, CFrame.new(0, 0.95, 0) * CFrame.Angles(0, math.rad(90), 0))
			end,
		},
		TanksWindow = {
			Height = 44.4,
			AssetId = 136270568520820,
			Collide = false,
			Palette = {
				Frame = h.rgb(250, 250, 245),
				Glass = h.rgb(170, 220, 255),
				Cloud = h.rgb(255, 255, 255),
				Curtain = h.rgb(255, 214, 120),
			},
			Materials = { Glass = Enum.Material.Glass, Curtain = Enum.Material.Fabric },
			Fallback = function(m)
				h.block(m, "Frame", Vector3.new(44, 36, 1.4), Vector3.new(0, 23, 0))
				h.block(m, "Glass", Vector3.new(40, 32, 1.6), Vector3.new(0, 23, 0))
				h.block(m, "Curtain", Vector3.new(9, 46, 1.2), Vector3.new(-24, 23, -1))
				h.block(m, "Curtain", Vector3.new(9, 46, 1.2), Vector3.new(24, 23, -1))
			end,
		},
	}
end

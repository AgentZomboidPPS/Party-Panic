-- Props for Arrow Ambush: the archers' stone tower, the target boards on rails, the bow and the
-- arrow. Meshes come from tools/meshgen/props/ArrowAmbush.py; until they're uploaded and approved
-- the Fallback is used.
return function(h)
	-- A cylinder facing Z (a disc on the front of a board).
	local function disc(m: Model, name: string, diameter: number, thickness: number, position: Vector3)
		return h.Build.Part({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(thickness, diameter, diameter),
			CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0),
			Parent = m,
		})
	end

	return {
		ArcherTower = {
			Height = 25.62,
			AssetId = 0, -- tools/upload_assets.py --only ArcherTower fills this in
			Collide = false, -- the game puts a solid core under the deck
			Palette = {
				Mortar = h.rgb(150, 140, 132),
				Stone = h.rgb(212, 202, 186),
				Trim = h.rgb(232, 222, 204),
				Deck = h.rgb(176, 124, 82),
				Wood = h.rgb(150, 98, 60),
				Iron = h.rgb(64, 64, 74),
				Window = h.rgb(38, 32, 40),
				Pole = h.rgb(255, 205, 80),
				Flag = h.rgb(255, 120, 60),
			},
			Materials = {
				Mortar = Enum.Material.Slate,
				Stone = Enum.Material.Slate,
				Trim = Enum.Material.Slate,
				Deck = Enum.Material.WoodPlanks,
				Wood = Enum.Material.Wood,
				Iron = Enum.Material.Metal,
				Pole = Enum.Material.Metal,
				Flag = Enum.Material.Fabric,
			},
			Fallback = function(m)
				h.pillar(m, "Mortar", 12.6, 16, Vector3.new(0, 8, 0))
				h.pillar(m, "Trim", 14.7, 1.4, Vector3.new(0, 16.6, 0))
				for k = 0, 11 do
					local angle = k / 12 * math.pi * 2
					h.rounded(
						m,
						"Trim",
						Vector3.new(1.8, 1.3, 1.8),
						0.2,
						Vector3.new(math.cos(angle) * 6.9, 17.9, math.sin(angle) * 6.9)
					)
				end
				h.pillar(m, "Pole", 0.3, 9.2, Vector3.new(-4.4, 20.6, 4.4))
				h.block(m, "Flag", Vector3.new(0.2, 2.2, 3.2), Vector3.new(-4.4, 24.2, 6))
				h.ball(m, "Pole", 0.64, Vector3.new(-4.4, 25.3, 4.4))
			end,
		},
		TargetBoard = {
			Height = 7.79,
			AssetId = 0,
			Collide = false, -- the client moves boards; arrows are blocked by the server's own check
			Palette = {
				Wood = h.rgb(196, 146, 96),
				Frame = h.rgb(122, 82, 52),
				Iron = h.rgb(64, 64, 74),
				Wheels = h.rgb(96, 66, 44),
				Face = h.rgb(250, 246, 236),
				Rings = h.rgb(232, 58, 58),
				Bull = h.rgb(255, 205, 60),
				Rim = h.rgb(60, 60, 70),
			},
			Materials = { Wood = Enum.Material.WoodPlanks, Frame = Enum.Material.Wood, Iron = Enum.Material.Metal },
			Fallback = function(m)
				h.rounded(m, "Wood", Vector3.new(6.2, 0.45, 2.5), 0.12, Vector3.new(0, 0.95, 0))
				for _, x in { -2.3, 2.3 } do
					h.roller(m, "Wheels", 1, 2.2, Vector3.new(x, 0.55, 0)).CFrame = CFrame.new(x, 0.55, 0)
						* CFrame.Angles(0, math.rad(90), 0)
					h.block(m, "Wood", Vector3.new(0.42, 2, 0.42), Vector3.new(x, 1.8, 0.45))
				end
				h.rounded(m, "Wood", Vector3.new(7.2, 6.2, 0.5), 0.15, Vector3.new(0, 4.5, 0.05))
				disc(m, "Face", 5.7, 0.1, Vector3.new(0, 4.5, -0.22))
				disc(m, "Rings", 3.5, 0.12, Vector3.new(0, 4.5, -0.25))
				disc(m, "Bull", 1.24, 0.14, Vector3.new(0, 4.5, -0.28))
				h.block(m, "Iron", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, 7.55, 0.05))
			end,
		},
		AmbushBow = {
			Height = 4.84,
			AssetId = 0,
			Palette = {
				Limbs = h.rgb(156, 98, 56),
				Grip = h.rgb(92, 52, 42),
				String = h.rgb(245, 240, 225),
				Tips = h.rgb(255, 205, 80),
			},
			Materials = { Limbs = Enum.Material.Wood, Tips = Enum.Material.Metal },
			Fallback = function(m)
				h.capsule(m, "Limbs", 2.6, 0.3, CFrame.new(0, 3.4, -0.35) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, math.rad(20), 0))
				h.capsule(m, "Limbs", 2.6, 0.3, CFrame.new(0, 1.4, -0.35) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, math.rad(-20), 0))
				h.block(m, "Grip", Vector3.new(0.38, 1.1, 0.46), Vector3.new(0, 2.42, -0.6))
				h.block(m, "String", Vector3.new(0.06, 4.7, 0.06), Vector3.new(0, 2.42, 0.2))
			end,
		},
		AmbushArrow = {
			Height = 0.63,
			AssetId = 0,
			Shadow = false,
			Palette = {
				Shaft = h.rgb(210, 166, 112),
				Head = h.rgb(176, 186, 200),
				Fletching = h.rgb(255, 110, 60),
				Nock = h.rgb(255, 205, 80),
			},
			Materials = { Head = Enum.Material.Metal },
			Fallback = function(m)
				h.capsule(m, "Shaft", 3.8, 0.15, CFrame.new(0, 0.32, 0.2) * CFrame.Angles(0, math.rad(90), 0))
				h.block(m, "Head", Vector3.new(0.4, 0.2, 0.7), Vector3.new(0, 0.32, -1.95))
				h.block(m, "Fletching", Vector3.new(0.06, 0.63, 1), Vector3.new(0, 0.315, 1.45))
			end,
		},
	}
end

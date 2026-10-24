-- Props for Fire Rope: the Dragon Temple fire festival. A stepped temple with a dragon head pouring
-- lava down its stairs, basalt cliffs with lava falls, stone towers that hold the rope's sun wheels,
-- fire braziers rising out of the lava and the arches under the bridge. Meshes come from
-- tools/meshgen/props/FireRope.py; each has a few-part fallback.
--
-- All of them block the camera (owner: "I keep clipping into some chair on fire rope what is going
-- on?"): the default camera, 12.5 studs behind a player, slid inside the back braziers' fire bowls
-- (the bowl's rim and gold claws, seen from inside, look like the back of a chair) when a player at
-- the back of the bridge tipped the camera up to watch the rope, and inside the rope towers and the
-- wheels' hubs when a player at either end looked back along the bridge. They still don't collide
-- with anyone (see MeshLibrary).
return function(h)
	local Lava = h.rgb(255, 110, 30)
	local Gold = h.rgb(255, 198, 60)
	local Stone = h.rgb(176, 78, 64) -- deep red-brown: stands out against the yellow-orange lava
	local Iron = h.rgb(64, 48, 60)
	local Neon = Enum.Material.Neon

	return {
		-- Backdrop centerpiece; faces -Z (turn it to face the bridge).
		DragonTemple = {
			AssetId = 106143423849449,
			Height = 97.5,
			BlocksCamera = true,
			Shadow = false,
			Palette = {
				Stone = Stone,
				Trim = Gold,
				Dark = h.rgb(58, 40, 54), -- the dragon and stair walls: darker than the lava-fall basalt, so the gold and lava pop
				Glow = h.rgb(255, 176, 60),
				Eyes = h.rgb(255, 246, 150),
				Teeth = h.rgb(252, 244, 224),
				Lava = Lava,
				Crust = h.rgb(200, 64, 30),
				Cloth = h.rgb(220, 38, 62), -- banners and the dragon's frills
				Emblem = Gold,
			},
			Materials = {
				Stone = Enum.Material.Sandstone,
				Dark = Enum.Material.Slate,
				Glow = Neon,
				Eyes = Neon,
				Lava = Neon,
				Cloth = Enum.Material.Fabric,
				Crust = Enum.Material.Basalt,
			},
			Fallback = function(m)
				h.block(m, "Stone", Vector3.new(100, 14, 70), Vector3.new(0, 7, 0))
				h.block(m, "Stone", Vector3.new(82, 13, 56), Vector3.new(0, 20.5, 3))
				h.block(m, "Stone", Vector3.new(64, 12, 44), Vector3.new(0, 33, 6))
				h.block(m, "Stone", Vector3.new(46, 11, 32), Vector3.new(0, 44.5, 9))
				h.block(m, "Cloth", Vector3.new(44, 22, 1), Vector3.new(0, 72, 17)) -- frills
				h.blob(m, "Dark", Vector3.new(28, 30, 40), Vector3.new(0, 72, -2))
				h.block(m, "Lava", Vector3.new(7, 0.8, 40), Vector3.new(0, 26, -26))
				for _, x in { -12, 12 } do -- horns
					h.block(m, "Trim", Vector3.new(2.5, 14, 2.5), Vector3.new(x, 90.5, 30))
				end
			end,
		},
		-- Holds a sun wheel's axle; the medallion at 35.4 studs up on its front (-Z) face is where the
		-- axle goes in. Fire bowl on top.
		RopeTower = {
			AssetId = 89239174801545,
			Height = 43.3,
			BlocksCamera = true,
			Palette = {
				Stone = Stone,
				Trim = Gold,
				Glow = h.rgb(255, 176, 60),
				Cloth = h.rgb(220, 38, 62),
				Emblem = Gold,
				Metal = Iron,
				Coals = h.rgb(255, 150, 50),
			},
			Materials = {
				Stone = Enum.Material.Sandstone,
				Glow = Neon,
				Cloth = Enum.Material.Fabric,
				Metal = Enum.Material.Metal,
				Coals = Neon,
			},
			Fallback = function(m)
				h.block(m, "Stone", Vector3.new(9.5, 4, 9.5), Vector3.new(0, 2, 0))
				h.block(m, "Stone", Vector3.new(6, 36, 6), Vector3.new(0, 22, 0))
				h.block(m, "Trim", Vector3.new(8.2, 1.6, 8.2), Vector3.new(0, 38.6, 0))
				h.pillar(m, "Metal", 7, 3, Vector3.new(0, 41.5, 0))
				h.pillar(m, "Coals", 5.8, 0.6, Vector3.new(0, 43, 0))
			end,
		},
		-- Turns the fire rope: stands in the YZ plane with its axle along X; the rope hangs 9.5 studs
		-- from the axle.
		SunWheel = {
			AssetId = 109791260711279,
			Height = 29.4,
			-- It spins: only its round parts (rim, hub, axle; the same shape at every turn) stop the camera,
			-- not the spokes and flame blades sweeping past it.
			BlocksCamera = { "Rim", "Trim", "Eye" },
			Shadow = false, -- no spinning spoke shadow across the players at the bridge's ends
			Palette = {
				Rim = Iron,
				Trim = Gold,
				Flames = h.rgb(255, 120, 36),
				Spokes = h.rgb(255, 170, 50),
				Eye = h.rgb(255, 236, 110),
			},
			Materials = { Rim = Enum.Material.Metal, Flames = Neon, Spokes = Neon, Eye = Neon },
			Fallback = function(m)
				h.roller(m, "Rim", 22.4, 1.2, Vector3.new(0, 14.7, 0))
				for spoke = 0, 3 do
					h.Build.Part({
						Name = "Spokes",
						Size = Vector3.new(1.2, 19, 0.9),
						CFrame = CFrame.new(0, 14.7, 0) * CFrame.Angles(spoke * math.pi / 4, 0, 0),
						Parent = m,
					})
				end
				h.roller(m, "Trim", 4.2, 3, Vector3.new(0, 14.7, 0))
				h.roller(m, "Rim", 1.6, 6.4, Vector3.new(0, 14.7, 0))
				h.ball(m, "Flames", 0.5, Vector3.new(0, 29.15, 0)) -- keeps the box as tall as the mesh
				h.ball(m, "Flames", 0.5, Vector3.new(0, 0.25, 0))
			end,
		},
		-- A fluted column rising out of the lava with a fire bowl on top (the bowl's coals at 27 up).
		FireBrazier = {
			AssetId = 102363003339428,
			Height = 28.9,
			BlocksCamera = true,
			Palette = {
				Stone = Stone,
				Trim = Gold,
				Glow = h.rgb(255, 176, 60),
				Metal = Iron,
				Coals = h.rgb(255, 150, 50),
			},
			Materials = { Stone = Enum.Material.Sandstone, Glow = Neon, Metal = Enum.Material.Metal, Coals = Neon },
			Fallback = function(m)
				h.pillar(m, "Stone", 4.4, 22, Vector3.new(0, 11, 0))
				h.pillar(m, "Metal", 9, 5.8, Vector3.new(0, 24.8, 0))
				h.pillar(m, "Coals", 7.6, 0.6, Vector3.new(0, 27.6, 0))
				h.ball(m, "Trim", 0.6, Vector3.new(0, 28.6, 0))
			end,
		},
		-- Basalt-column cliff with three crusted lava streams pouring over its middle; faces -Z.
		LavaFall = {
			AssetId = 110344895154199,
			Height = 53.1,
			BlocksCamera = true,
			Shadow = false,
			Palette = { Rock = h.rgb(74, 54, 66), Lava = Lava, Crust = h.rgb(200, 64, 30) },
			Materials = { Rock = Enum.Material.Basalt, Lava = Neon, Crust = Enum.Material.Basalt },
			Fallback = function(m)
				h.block(m, "Rock", Vector3.new(30, 50, 8), Vector3.new(0, 25, 9))
				h.block(m, "Rock", Vector3.new(24, 40, 7), Vector3.new(0, 20, 2.5))
				h.block(m, "Rock", Vector3.new(30, 53.1, 6), Vector3.new(0, 53.1 / 2, 13))
				h.block(m, "Lava", Vector3.new(9, 40, 1), Vector3.new(0, 21, -5))
			end,
		},
		-- A stretch of the crater's basalt wall with a lava trickle, curving to fit a 172-stud circle;
		-- faces -Z.
		BasaltWall = {
			AssetId = 71684404393362,
			Height = 59.2,
			BlocksCamera = true,
			Shadow = false,
			Palette = { Rock = h.rgb(74, 54, 66), Lava = Lava, Crust = h.rgb(200, 64, 30) },
			Materials = { Rock = Enum.Material.Basalt, Lava = Neon, Crust = Enum.Material.Basalt },
			Fallback = function(m)
				-- (bottoms at different depths, so they never share a plane)
				h.block(m, "Rock", Vector3.new(92, 52, 8), Vector3.new(0, 26, 7))
				h.block(m, "Rock", Vector3.new(80, 59.6, 4), Vector3.new(0, 29.4, 10))
				h.block(m, "Rock", Vector3.new(84, 34.8, 7), Vector3.new(0, 16.6, 0))
				h.block(m, "Rock", Vector3.new(70, 15.2, 6), Vector3.new(0, 6.4, -6))
			end,
		},
		-- Arches, piers and the rune fascia under the bridge deck (the deck is the arena's own part).
		-- The deck's underside is 22 studs up; spans x = -37..37.
		TempleBridge = {
			AssetId = 80539564743048,
			Height = 22.6,
			BlocksCamera = true,
			Shadow = false,
			Palette = {
				Stone = h.rgb(150, 62, 58),
				Trim = Gold,
				Glow = h.rgb(255, 176, 60),
				Dark = h.rgb(110, 66, 80),
			},
			Materials = { Stone = Enum.Material.Sandstone, Glow = Neon },
			Fallback = function(m)
				for _, x in { -35.5, -12, 12, 35.5 } do
					h.block(m, "Stone", Vector3.new(5, 20.6, 9), Vector3.new(x, 10.3, 0))
				end
				h.block(m, "Dark", Vector3.new(74.6, 2, 9.2), Vector3.new(0, 21.2, 0))
				h.block(m, "Trim", Vector3.new(75.2, 0.6, 9.8), Vector3.new(0, 22.3, 0))
			end,
		},
	}
end

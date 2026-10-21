-- Props for Parasol Plummet. MeshLibrary loads this file at startup (see World/Props/README.md).
-- The meshes come from tools/meshgen/props/ParasolPlummet.py; until they're uploaded the Fallback is
-- used. Nothing here collides (fallers fly where the server puts them; see the mode's top comment).
--
-- The umbrellas' sizes match the catch shapes in Shared/Logic/ParasolPlummetSim (CANOPY_*, FURL_*):
-- the client half holds one with its base Sim.UMBRELLA_BASE (2.6 studs) above the faller's root.
-- The client recolours each faller's "Canopy" piece in that faller's own colour (the "Stripe" panels stay white).
return function(h)
	local gold = h.rgb(255, 200, 40)
	local cloud = h.rgb(250, 252, 255)
	return {
		ParasolPlummetUmbrella = {
			Height = 5.6,
			AssetId = 105144261230779,
			Palette = {
				Canopy = h.rgb(235, 70, 80),
				Stripe = h.rgb(255, 250, 245),
				Shaft = h.rgb(200, 204, 214),
				Handle = h.rgb(120, 72, 44),
				Tip = gold,
			},
			Materials = { Shaft = Enum.Material.Metal, Handle = Enum.Material.Wood, Canopy = Enum.Material.Fabric },
			Fallback = function(m)
				h.blob(m, "Canopy", Vector3.new(7.6, 2.4, 7.6), Vector3.new(0, 4.4, 0))
				h.pillar(m, "Shaft", 0.22, 5.4, Vector3.new(0, 2.7, 0))
				h.block(m, "Handle", Vector3.new(0.4, 0.9, 0.4), Vector3.new(0, 0.45, 0))
				h.ball(m, "Tip", 0.4, Vector3.new(0, 5.45, 0))
			end,
		},
		ParasolPlummetUmbrellaShut = {
			Height = 5.6,
			AssetId = 81534965010793,
			Palette = {
				Canopy = h.rgb(235, 70, 80),
				Stripe = h.rgb(255, 250, 245),
				Shaft = h.rgb(200, 204, 214),
				Handle = h.rgb(120, 72, 44),
				Tip = gold,
			},
			Materials = { Shaft = Enum.Material.Metal, Handle = Enum.Material.Wood, Canopy = Enum.Material.Fabric },
			Fallback = function(m)
				h.pillar(m, "Canopy", 1, 3.8, Vector3.new(0, 3.2, 0))
				h.pillar(m, "Shaft", 0.22, 5.4, Vector3.new(0, 2.7, 0))
				h.block(m, "Handle", Vector3.new(0.4, 0.9, 0.4), Vector3.new(0, 0.45, 0))
				h.ball(m, "Tip", 0.4, Vector3.new(0, 5.45, 0))
			end,
		},
		ParasolPlummetCoin = {
			Height = 2.8,
			AssetId = 100830698162882,
			Shadow = false,
			Palette = { Coin = gold, Emblem = h.rgb(255, 238, 140) },
			Materials = { Coin = Enum.Material.Metal, Emblem = Enum.Material.Metal },
			Fallback = function(m)
				h.Build.Part({
					Name = "Coin",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.35, 2.2, 2.2),
					CFrame = CFrame.new(0, 1.1, 0) * CFrame.Angles(0, math.rad(90), 0),
					Parent = m,
				})
				h.block(m, "Emblem", Vector3.new(0.8, 0.8, 0.45), Vector3.new(0, 1.1, 0))
			end,
		},
		ParasolPlummetBag = {
			Height = 3.6,
			AssetId = 99372427279332,
			Shadow = false,
			Palette = { Sack = h.rgb(196, 140, 84), Tie = h.rgb(120, 70, 40), Emblem = gold },
			Materials = { Sack = Enum.Material.Fabric, Emblem = Enum.Material.Metal },
			Fallback = function(m)
				h.blob(m, "Sack", Vector3.new(2.8, 2.4, 2.4), Vector3.new(0, 1.2, 0))
				h.blob(m, "Tie", Vector3.new(1.2, 0.8, 1.2), Vector3.new(0, 2.6, 0))
				h.block(m, "Emblem", Vector3.new(1, 1, 0.2), Vector3.new(0, 1.2, -1.15))
			end,
		},
		ParasolPlummetHammer = {
			Height = 4.2,
			AssetId = 117076517085122,
			Shadow = false,
			Palette = { Head = h.rgb(120, 126, 140), Handle = h.rgb(150, 98, 58), Band = gold },
			Materials = { Head = Enum.Material.Metal, Handle = Enum.Material.Wood, Band = Enum.Material.Metal },
			Fallback = function(m)
				h.pillar(m, "Handle", 0.45, 2.6, Vector3.new(0, 1.3, 0))
				h.block(m, "Head", Vector3.new(2.6, 1.2, 1.2), Vector3.new(0, 3, 0))
			end,
		},
		ParasolPlummetCloud = {
			Height = 5,
			AssetId = 132771041638249,
			Shadow = false,
			Palette = { Cloud = cloud, Shade = h.rgb(214, 228, 248) },
			Materials = { Cloud = Enum.Material.SmoothPlastic, Shade = Enum.Material.SmoothPlastic },
			Fallback = function(m)
				h.blob(m, "Shade", Vector3.new(14, 2.4, 7), Vector3.new(0, 1.2, 0))
				h.blob(m, "Cloud", Vector3.new(8, 5, 6), Vector3.new(0, 2.6, 0))
				h.blob(m, "Cloud", Vector3.new(6, 4, 5), Vector3.new(-4.2, 2, 0))
				h.blob(m, "Cloud", Vector3.new(6, 4, 5), Vector3.new(4.2, 2, 0))
			end,
		},
		ParasolPlummetThrower = {
			Height = 5.4,
			AssetId = 82701868422805,
			Palette = {
				Body = h.rgb(120, 200, 110),
				Belly = h.rgb(255, 238, 200),
				Cap = h.rgb(70, 110, 230),
				Eyes = h.rgb(255, 255, 255),
				Pupils = h.rgb(30, 30, 40),
				Boots = h.rgb(130, 80, 50),
			},
			Materials = { Body = Enum.Material.SmoothPlastic, Belly = Enum.Material.SmoothPlastic },
			Fallback = function(m)
				h.blob(m, "Body", Vector3.new(3.4, 3.6, 3), Vector3.new(0, 2.2, 0))
				h.blob(m, "Belly", Vector3.new(2.4, 2.6, 1), Vector3.new(0, 2, -1.2))
				h.blob(m, "Cap", Vector3.new(3, 1.4, 3), Vector3.new(0, 4.4, 0))
				h.ball(m, "Eyes", 0.9, Vector3.new(-0.55, 3.4, -1.3))
				h.ball(m, "Eyes", 0.9, Vector3.new(0.55, 3.4, -1.3))
				h.blob(m, "Boots", Vector3.new(1.2, 0.6, 1.6), Vector3.new(-0.8, 0.3, -0.2))
				h.blob(m, "Boots", Vector3.new(1.2, 0.6, 1.6), Vector3.new(0.8, 0.3, -0.2))
			end,
		},
		ParasolPlummetSun = {
			Height = 59,
			AssetId = 92749096219059,
			Shadow = false,
			Palette = { Sun = h.rgb(255, 236, 140), Rays = h.rgb(255, 205, 90) },
			Materials = { Sun = Enum.Material.Neon, Rays = Enum.Material.Neon },
			Fallback = function(m)
				h.Build.Part({
					Name = "Sun",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(2, 36, 36),
					CFrame = CFrame.new(0, 30, 0) * CFrame.Angles(0, math.rad(90), 0),
					Parent = m,
				})
				h.block(m, "Rays", Vector3.new(60, 4, 1), Vector3.new(0, 30, 1))
				h.block(m, "Rays", Vector3.new(4, 60, 1), Vector3.new(0, 30, 1))
			end,
		},
		ParasolPlummetBalloon = {
			Height = 21.6,
			AssetId = 89049309041996,
			Shadow = false,
			Palette = {
				Envelope = h.rgb(255, 120, 90),
				Stripe = h.rgb(255, 220, 90),
				Basket = h.rgb(150, 100, 60),
				Rope = h.rgb(90, 70, 50),
			},
			Materials = { Basket = Enum.Material.Wood, Envelope = Enum.Material.Fabric },
			Fallback = function(m)
				h.ball(m, "Envelope", 14, Vector3.new(0, 14, 0))
				h.block(m, "Basket", Vector3.new(3.2, 2.4, 3.2), Vector3.new(0, 1.2, 0))
			end,
		},
	}
end

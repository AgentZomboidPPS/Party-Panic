-- Props for Struggle (meshes from tools/meshgen/props/Struggle.py). MeshLibrary loads this file at
-- startup; get one with MeshLibrary.Get("StruggleFence", { CFrame = ..., Parent = ctx.Arena }).
--
-- Only the fence collides (owner: "Theres invisible stuff you can jump on and hang on in several
-- games"): its boards, rails and post are separate pieces, each collision its own drawn shape.
-- Everything else stands behind the fence where nobody can reach it, or is carried (the bat) or
-- drawn by clients (the orbs), so none of it is solid. The orbs are coloured per player by the client.
return function(h)
	local orbPalette = { Orb = h.rgb(120, 220, 255) }
	local orbMaterials = { Orb = Enum.Material.Neon }
	return {
		-- The bat (owner: "they dont even look like bats"): a knob, a thin taped handle, a smooth flare
		-- and a long thick barrel. The client colours the knob and barrel (Foam) in the player's colour
		-- and holds it in the right hand at the shared rules' BAT_GRIP (its pivot is the knob's end).
		StruggleBat = {
			Height = 4.4,
			AssetId = 103167926267453,
			Palette = { Grip = h.rgb(44, 44, 52), Foam = h.rgb(255, 120, 60), Band = h.rgb(250, 250, 250) },
			Materials = { Grip = Enum.Material.Fabric, Foam = Enum.Material.SmoothPlastic },
			Shadow = false,
			Fallback = function(m)
				h.pillar(m, "Foam", 0.56, 0.22, Vector3.new(0, 0.11, 0))
				h.pillar(m, "Grip", 0.31, 1.56, Vector3.new(0, 0.98, 0))
				h.pillar(m, "Foam", 0.6, 0.9, Vector3.new(0, 2.15, 0))
				h.capsule(m, "Foam", 2.0, 1.0, CFrame.new(0, 3.4, 0))
				h.pillar(m, "Band", 1.08, 0.22, Vector3.new(0, 3.77, 0))
			end,
		},
		StruggleOrbBall = {
			Height = 1.6,
			AssetId = 73098953975178,
			Palette = orbPalette,
			Materials = orbMaterials,
			Shadow = false,
			Fallback = function(m)
				h.ball(m, "Orb", 1.6, Vector3.new(0, 0.8, 0))
			end,
		},
		StruggleOrbCube = {
			Height = 1.3,
			AssetId = 85396579013177,
			Palette = orbPalette,
			Materials = orbMaterials,
			Shadow = false,
			Fallback = function(m)
				h.block(m, "Orb", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 0.65, 0))
			end,
		},
		StruggleOrbPyramid = {
			Height = 1.5,
			AssetId = 138314803791608,
			Palette = orbPalette,
			Materials = orbMaterials,
			Shadow = false,
			Fallback = function(m)
				h.block(m, "Orb", Vector3.new(1.2, 0.5, 1.2), Vector3.new(0, 0.25, 0))
				h.block(m, "Orb", Vector3.new(0.6, 0.9, 0.6), Vector3.new(0, 0.9, 0))
			end,
		},
		StruggleOrbDiamond = {
			Height = 1.6,
			AssetId = 99947043847275,
			Palette = orbPalette,
			Materials = orbMaterials,
			Shadow = false,
			Fallback = function(m)
				local part = h.block(m, "Orb", Vector3.new(1.1, 1.1, 0.5), Vector3.new(0, 0.8, 0))
				part.CFrame *= CFrame.Angles(0, 0, math.rad(45))
			end,
		},
		StruggleOrbStar = {
			Height = 1.5,
			AssetId = 87746981604248,
			Palette = orbPalette,
			Materials = orbMaterials,
			Shadow = false,
			Fallback = function(m)
				h.ball(m, "Orb", 1.5, Vector3.new(0, 0.75, 0))
			end,
		},
		StruggleOrbRing = {
			Height = 1.6,
			AssetId = 84876043006293,
			Palette = orbPalette,
			Materials = orbMaterials,
			Shadow = false,
			Fallback = function(m)
				h.roller(m, "Orb", 1.6, 0.4, Vector3.new(0, 0.8, 0))
			end,
		},
		StruggleOrbPlus = {
			Height = 1.6,
			AssetId = 128938696631806,
			Palette = orbPalette,
			Materials = orbMaterials,
			Shadow = false,
			Fallback = function(m)
				h.block(m, "Orb", Vector3.new(1.6, 0.5, 0.45), Vector3.new(0, 0.8, 0))
				h.block(m, "Orb", Vector3.new(0.5, 1.6, 0.45), Vector3.new(0, 0.8, 0))
			end,
		},
		StruggleOrbCross = {
			Height = 1.5,
			AssetId = 85278136207862,
			Palette = orbPalette,
			Materials = orbMaterials,
			Shadow = false,
			Fallback = function(m)
				local a = h.block(m, "Orb", Vector3.new(1.8, 0.45, 0.45), Vector3.new(0, 0.75, 0))
				a.CFrame *= CFrame.Angles(0, 0, math.rad(45))
				local b = h.block(m, "Orb", Vector3.new(1.8, 0.45, 0.45), Vector3.new(0, 0.75, 0))
				b.CFrame *= CFrame.Angles(0, 0, math.rad(-45))
			end,
		},
		StruggleOrbCone = {
			Height = 1.5,
			AssetId = 140231652345016,
			Palette = orbPalette,
			Materials = orbMaterials,
			Shadow = false,
			Fallback = function(m)
				h.pillar(m, "Orb", 1.5, 0.5, Vector3.new(0, 1.25, 0))
				h.pillar(m, "Orb", 0.6, 1.0, Vector3.new(0, 0.5, 0))
			end,
		},
		StruggleOrbFrame = {
			Height = 1.35,
			AssetId = 85143365552121,
			Palette = orbPalette,
			Materials = orbMaterials,
			Shadow = false,
			Fallback = function(m)
				h.block(m, "Orb", Vector3.new(1.35, 0.34, 0.45), Vector3.new(0, 0.17, 0))
				h.block(m, "Orb", Vector3.new(1.35, 0.34, 0.45), Vector3.new(0, 1.18, 0))
				h.block(m, "Orb", Vector3.new(0.34, 0.7, 0.45), Vector3.new(-0.5, 0.68, 0))
				h.block(m, "Orb", Vector3.new(0.34, 0.7, 0.45), Vector3.new(0.5, 0.68, 0))
			end,
		},
		StruggleOrbPill = {
			Height = 0.84,
			AssetId = 108419938530446,
			Palette = orbPalette,
			Materials = orbMaterials,
			Shadow = false,
			Fallback = function(m)
				h.capsule(m, "Orb", 1.8, 0.84, CFrame.new(0, 0.42, 0) * CFrame.Angles(0, 0, math.rad(90)))
			end,
		},
		StruggleOrbKite = {
			Height = 1.55,
			AssetId = 111546909516275,
			Palette = orbPalette,
			Materials = orbMaterials,
			Shadow = false,
			Fallback = function(m)
				local part = h.block(m, "Orb", Vector3.new(1.0, 1.0, 0.45), Vector3.new(0, 0.78, 0))
				part.CFrame *= CFrame.Angles(0, 0, math.rad(45))
			end,
		},
		StruggleFence = {
			Height = 10.5,
			AssetId = 82866516079462,
			Collide = true,
			Palette = { Boards = h.rgb(196, 146, 96), Rails = h.rgb(150, 104, 66), Post = h.rgb(120, 84, 56) },
			Materials = {
				Boards = Enum.Material.WoodPlanks,
				Rails = Enum.Material.Wood,
				Post = Enum.Material.Wood,
			},
			Fallback = function(m)
				h.block(m, "Boards", Vector3.new(12, 9.8, 0.26), Vector3.new(0, 5.15, -0.05))
				h.block(m, "Rails", Vector3.new(12, 0.45, 0.36), Vector3.new(0, 1.6, 0.3))
				h.block(m, "Post", Vector3.new(0.8, 10.5, 0.8), Vector3.new(-6, 5.25, 0.15))
			end,
		},
		StruggleReach = {
			Height = 0.02, -- a flat fan of radius 1 (the client scales it to the swing's reach)
			AssetId = 106007616538835,
			Palette = { Fan = h.rgb(255, 255, 255) },
			Materials = { Fan = Enum.Material.Neon },
			Shadow = false,
			Fallback = function(m)
				h.block(m, "Fan", Vector3.new(1.97, 0.02, 1), Vector3.new(0, 0.01, -0.5))
			end,
		},
		StruggleScoreboard = {
			Height = 16.9,
			AssetId = 93074651791987,
			BlocksCamera = true,
			Palette = {
				Legs = h.rgb(110, 78, 52),
				Frame = h.rgb(130, 92, 60),
				Face = h.rgb(34, 60, 48),
				Plaque = h.rgb(240, 200, 90),
				Bulbs = h.rgb(255, 235, 150),
			},
			Materials = { Legs = Enum.Material.Wood, Frame = Enum.Material.WoodPlanks, Bulbs = Enum.Material.Neon },
			Fallback = function(m)
				h.block(m, "Legs", Vector3.new(0.9, 14, 0.9), Vector3.new(-8.2, 7, 0.3))
				h.block(m, "Legs", Vector3.new(0.9, 14, 0.9), Vector3.new(8.2, 7, 0.3))
				h.block(m, "Frame", Vector3.new(18.4, 8.4, 0.8), Vector3.new(0, 10.6, 0.15))
				h.block(m, "Face", Vector3.new(15.5, 6.2, 0.1), Vector3.new(0, 10.6, -0.3))
				h.block(m, "Plaque", Vector3.new(7, 1.6, 0.6), Vector3.new(0, 16.1, 0.15))
			end,
		},
		StruggleTram = {
			Height = 11.1,
			AssetId = 130157278749122,
			BlocksCamera = true,
			Palette = {
				Body = h.rgb(210, 80, 60),
				Stripe = h.rgb(245, 230, 200),
				Windows = h.rgb(40, 60, 80),
				Roof = h.rgb(170, 170, 175),
				Bogies = h.rgb(50, 50, 55),
				Pantograph = h.rgb(60, 60, 64),
				Lamps = h.rgb(255, 240, 180),
			},
			Materials = {
				Windows = Enum.Material.Glass,
				Roof = Enum.Material.Metal,
				Bogies = Enum.Material.Metal,
				Pantograph = Enum.Material.Metal,
				Lamps = Enum.Material.Neon,
			},
			Fallback = function(m)
				h.rounded(m, "Body", Vector3.new(6.2, 6.4, 20), 0.9, Vector3.new(0, 5.4, 0))
				h.block(m, "Roof", Vector3.new(5.4, 0.6, 19), Vector3.new(0, 8.75, 0))
				h.block(m, "Bogies", Vector3.new(4.6, 2, 18), Vector3.new(0, 1.2, 0))
				h.block(m, "Pantograph", Vector3.new(3.6, 0.2, 0.2), Vector3.new(0, 11, 0))
			end,
		},
		StruggleTrack = {
			Height = 1.15,
			AssetId = 113593058801207,
			Palette = { Ballast = h.rgb(120, 110, 100), Sleepers = h.rgb(100, 72, 50), Rails = h.rgb(150, 150, 155) },
			Materials = { Ballast = Enum.Material.Pebble, Sleepers = Enum.Material.Wood, Rails = Enum.Material.Metal },
			Shadow = false,
			Fallback = function(m)
				h.block(m, "Ballast", Vector3.new(7.6, 0.45, 40), Vector3.new(0, 0.22, 0))
				h.block(m, "Rails", Vector3.new(5.1, 0.4, 40), Vector3.new(0, 0.95, 0))
			end,
		},
		StruggleBench = {
			Height = 3.7,
			AssetId = 122997575548971,
			Palette = { Seat = h.rgb(190, 130, 80), Back = h.rgb(176, 120, 74), Legs = h.rgb(60, 60, 66) },
			Materials = { Seat = Enum.Material.WoodPlanks, Back = Enum.Material.WoodPlanks, Legs = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "Seat", Vector3.new(8, 0.25, 1.7), Vector3.new(0, 1.75, 0))
				h.block(m, "Back", Vector3.new(8, 1.2, 0.2), Vector3.new(0, 2.9, 0.95))
				h.block(m, "Legs", Vector3.new(7.2, 1.6, 0.25), Vector3.new(0, 0.8, -0.6))
			end,
		},
		StruggleBanner = {
			Height = 12.6,
			AssetId = 113335134452205,
			Palette = {
				Pole = h.rgb(230, 230, 230),
				Finial = h.rgb(240, 200, 80),
				Cloth = h.rgb(240, 160, 50),
				Emblem = h.rgb(255, 250, 235),
			},
			Materials = { Pole = Enum.Material.Metal, Finial = Enum.Material.Metal, Cloth = Enum.Material.Fabric },
			Fallback = function(m)
				h.pillar(m, "Pole", 0.36, 12, Vector3.new(0, 6, 0))
				h.block(m, "Cloth", Vector3.new(3.8, 6.4, 0.12), Vector3.new(0, 8, -0.2))
			end,
		},
	}
end

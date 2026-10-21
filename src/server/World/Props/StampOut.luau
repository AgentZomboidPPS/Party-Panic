-- Props for Stamp Out (meshes from tools/meshgen/props/StampOut.py; until a mesh is uploaded and
-- approved the Fallback is used).
--
-- Collision ("nothing solid where nothing is drawn"): the desk props that collide (big stamps, ink
-- pad: tray, lid and hinge apart; pencils) are one MeshPart per piece, each piece a simple convex-ish solid, so their collision
-- hugs what's drawn. The paper clips are thin wire loops whose collision hull would fill the loops,
-- so they don't collide at all (they're 1 stud tall, lying flat). The rider stamp is carried by a
-- character (MeshLibrary.Assemble: never collides).
return function(h)
	local wood = h.rgb(206, 160, 108)
	return {
		StampOutRider = {
			Height = 1.42,
			AssetId = 73397414880871, -- tools/upload_assets.py --only StampOutRider fills this in
			Palette = { Rubber = h.rgb(226, 40, 52), Block = wood, Band = h.rgb(226, 40, 52) },
			Materials = { Block = Enum.Material.Wood },
			Fallback = function(m)
				h.rounded(m, "Rubber", Vector3.new(3.4, 0.36, 2.8), 0.12, Vector3.new(0, 0.18, 0))
				h.rounded(m, "Block", Vector3.new(3.7, 1, 3.1), 0.28, Vector3.new(0, 0.86, 0))
				h.rounded(m, "Band", Vector3.new(3.8, 0.24, 3.2), 0.1, Vector3.new(0, 1.3, 0))
			end,
		},
		StampOutBigStamp = {
			Height = 21.6,
			AssetId = 83349437901810, -- tools/upload_assets.py --only StampOutBigStamp fills this in
			Collide = true,
			Palette = {
				Rubber = h.rgb(226, 40, 52),
				Block = wood,
				Handle = h.rgb(176, 120, 70),
				Knob = h.rgb(226, 40, 52),
			},
			Materials = { Block = Enum.Material.Wood, Handle = Enum.Material.Wood },
			Fallback = function(m)
				h.rounded(m, "Rubber", Vector3.new(16, 1.6, 12), 0.4, Vector3.new(0, 0.8, 0))
				h.rounded(m, "Block", Vector3.new(17, 5, 13), 1, Vector3.new(0, 4.1, 0))
				h.pillar(m, "Handle", 3.8, 7.8, Vector3.new(0, 10.3, 0))
				h.ball(m, "Knob", 8.2, Vector3.new(0, 17.5, 0))
			end,
		},
		StampOutInkPad = {
			Height = 21.8,
			AssetId = 97418802985216, -- tools/upload_assets.py --only StampOutInkPad fills this in
			Collide = true,
			Palette = {
				Tin = h.rgb(200, 50, 60),
				Lid = h.rgb(200, 50, 60),
				Hinge = h.rgb(200, 200, 210),
				Felt = h.rgb(70, 40, 120),
			},
			Materials = {
				Tin = Enum.Material.Metal,
				Lid = Enum.Material.Metal,
				Hinge = Enum.Material.Metal,
				Felt = Enum.Material.Fabric,
			},
			Fallback = function(m)
				h.rounded(m, "Tin", Vector3.new(30, 2.4, 20), 0.6, Vector3.new(0, 1.2, 0))
				h.rounded(m, "Felt", Vector3.new(27, 0.6, 17), 0.25, Vector3.new(0, 2.35, 0))
				local lid = h.block(m, "Lid", Vector3.new(30, 20, 1), Vector3.new(0, 12, 11.5))
				lid.CFrame = CFrame.new(0, 12, 11.7) * CFrame.Angles(math.rad(-10), 0, 0)
			end,
		},
		StampOutPencil = {
			Height = 5.7,
			AssetId = 97491736669429, -- tools/upload_assets.py --only StampOutPencil fills this in
			Collide = true,
			Palette = {
				Body = h.rgb(250, 196, 40),
				Wood = h.rgb(232, 196, 150),
				Lead = h.rgb(50, 50, 56),
				Ferrule = h.rgb(200, 200, 210),
				Eraser = h.rgb(246, 140, 160),
			},
			Materials = { Wood = Enum.Material.Wood, Ferrule = Enum.Material.Metal },
			Fallback = function(m)
				h.roller(m, "Body", 5.2, 70, Vector3.new(0, 2.6, 0))
				h.roller(m, "Ferrule", 5.6, 5, Vector3.new(-37.5, 2.6, 0))
				h.roller(m, "Eraser", 5.2, 6, Vector3.new(-43, 2.6, 0))
				h.roller(m, "Wood", 3.6, 9, Vector3.new(39.5, 2.6, 0))
			end,
		},
		StampOutClip = {
			Height = 1,
			AssetId = 108727151684414, -- tools/upload_assets.py --only StampOutClip fills this in
			Palette = { Wire = h.rgb(200, 205, 215) },
			Materials = { Wire = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "Wire", Vector3.new(30, 1, 1), Vector3.new(0, 0.5, -1))
				h.block(m, "Wire", Vector3.new(26, 1, 1), Vector3.new(0, 0.5, 4))
			end,
		},
	}
end

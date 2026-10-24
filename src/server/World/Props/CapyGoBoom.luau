-- Props for Capy Go Boom (made from rounded parts; MeshLibrary loads this file at startup and uses an
-- uploaded mesh instead once a prop has an AssetId, see tools/upload_assets.py). Get one with
-- MeshLibrary.Get("CapyBoomCookie", { CFrame = ..., Parent = ctx.Arena }).
--
-- The capybara is the one from the owner's game CAPY GO BOOM (Visuals.CreateCapy there): a potato of a
-- body, a big square head with an emotional-support orange on it, little ears and feet, and a snack
-- cannon on its right side. The scarf ("Band") and the cannon's rim are recoloured per player by the
-- client, so a capy's colour shows from every side. It faces -Z, its feet on the pivot.
--
-- Only the standing stones collide (owner: "Theres invisible stuff you can jump on and hang on in
-- several games"): a pillar and a ball cap, each collision its own drawn shape. The capys, snacks and
-- shells are drawn by clients and never solid.
return function(h)
	-- A part turned to lie along Z (the cannon).
	local function alongZ(part: BasePart, position: Vector3)
		part.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0)
		return part
	end

	return {
		CapyBoomCapy = {
			Height = 5.4,
			AssetId = 0,
			Shadow = true,
			Palette = {
				Body = h.rgb(198, 143, 84),
				Snout = h.rgb(173, 119, 67),
				Foot = h.rgb(150, 100, 58),
				Eye = h.rgb(35, 25, 21),
				Nose = h.rgb(77, 47, 30),
				Orange = h.rgb(255, 151, 33),
				Leaf = h.rgb(96, 192, 55),
				Cannon = h.rgb(130, 225, 174),
				CannonRim = h.rgb(247, 215, 117),
				Band = h.rgb(235, 70, 70),
			},
			Fallback = function(m)
				h.blob(m, "Body", Vector3.new(4.5, 3.1, 5.8), Vector3.new(0, 2, 0))
				h.blob(m, "Body", Vector3.new(3.6, 2.8, 3.3), Vector3.new(0, 2.65, -2.1)) -- the big square head
				h.blob(m, "Snout", Vector3.new(3.1, 1.65, 2), Vector3.new(0, 2, -3.1))
				h.blob(m, "Nose", Vector3.new(1.4, 0.5, 0.5), Vector3.new(0, 2.3, -3.95))
				for _, x in { -1, 1 } do
					for _, z in { -1.3, 1.5 } do
						h.blob(m, "Foot", Vector3.new(1.45, 1.6, 1.6), Vector3.new(x * 1.3, 0.8, z))
					end
					h.blob(m, "Body", Vector3.new(0.85, 0.95, 0.72), Vector3.new(x * 1.35, 4, -1.8)) -- an ear
					h.blob(m, "Eye", Vector3.new(0.34, 0.46, 0.34), Vector3.new(x * 1.61, 3, -2.8))
				end
				h.blob(m, "Orange", Vector3.new(1.36, 1.3, 1.36), Vector3.new(0, 4.45, -2.1))
				local leaf = h.blob(m, "Leaf", Vector3.new(0.7, 0.16, 0.33), Vector3.new(0.28, 5.08, -2.1))
				leaf.CFrame *= CFrame.Angles(0, 0, math.rad(18))
				-- The scarf round the neck, with a knot at the back.
				alongZ(h.roller(m, "Band", 3.5, 0.55, Vector3.new(0, 2.3, -1.15)), Vector3.new(0, 2.3, -1.15))
				h.blob(m, "Band", Vector3.new(0.9, 1.1, 0.7), Vector3.new(0, 1.7, -0.45))
				-- The snack cannon on its right side, pointing forward.
				alongZ(h.roller(m, "Cannon", 1.1, 2.5, Vector3.new(2.65, 2.1, -1.35)), Vector3.new(2.65, 2.1, -1.35))
				alongZ(
					h.roller(m, "CannonRim", 1.3, 0.25, Vector3.new(2.65, 2.1, -2.65)),
					Vector3.new(2.65, 2.1, -2.65)
				)
			end,
		},
		CapyBoomCookie = {
			Height = 1.0,
			AssetId = 0,
			Shadow = false,
			Palette = { Cookie = h.rgb(222, 162, 92), Chip = h.rgb(88, 52, 34) },
			Fallback = function(m)
				h.pillar(m, "Cookie", 2.2, 0.55, Vector3.new(0, 0.28, 0))
				for _, spot in { { -0.5, 0.3 }, { 0.45, -0.1 }, { -0.1, -0.55 }, { 0.5, 0.55 } } do
					h.ball(m, "Chip", 0.42, Vector3.new(spot[1], 0.58, spot[2]))
				end
			end,
		},
		CapyBoomCupcake = {
			Height = 1.9,
			AssetId = 0,
			Shadow = false,
			Palette = {
				Wrapper = h.rgb(255, 245, 235),
				Frosting = h.rgb(255, 150, 200),
				Cherry = h.rgb(230, 40, 60),
			},
			Fallback = function(m)
				h.pillar(m, "Wrapper", 1.5, 0.8, Vector3.new(0, 0.4, 0))
				h.blob(m, "Frosting", Vector3.new(1.9, 1.15, 1.9), Vector3.new(0, 1.2, 0))
				h.ball(m, "Cherry", 0.5, Vector3.new(0, 1.7, 0))
			end,
		},
		CapyBoomMelon = {
			Height = 2.4,
			AssetId = 0,
			Shadow = false,
			Palette = { Rind = h.rgb(86, 178, 80), Stripe = h.rgb(36, 112, 54) },
			Fallback = function(m)
				h.blob(m, "Rind", Vector3.new(2.8, 2.2, 2.8), Vector3.new(0, 1.1, 0))
				h.blob(m, "Stripe", Vector3.new(2.85, 2.25, 0.5), Vector3.new(0, 1.1, 0))
				h.blob(m, "Stripe", Vector3.new(0.5, 2.25, 2.85), Vector3.new(0, 1.1, 0))
			end,
		},
		CapyBoomGoldMelon = {
			Height = 3.6,
			AssetId = 0,
			Shadow = false,
			Palette = { Rind = h.rgb(255, 205, 60), Stripe = h.rgb(255, 150, 30), Glow = h.rgb(255, 240, 160) },
			Materials = { Rind = Enum.Material.Neon, Glow = Enum.Material.Neon },
			Fallback = function(m)
				h.blob(m, "Rind", Vector3.new(4.1, 3.3, 4.1), Vector3.new(0, 1.65, 0))
				h.blob(m, "Stripe", Vector3.new(4.15, 3.35, 0.7), Vector3.new(0, 1.65, 0))
				h.blob(m, "Stripe", Vector3.new(0.7, 3.35, 4.15), Vector3.new(0, 1.65, 0))
				h.ball(m, "Glow", 0.9, Vector3.new(0, 3.2, 0))
			end,
		},
		CapyBoomShell = {
			Height = 1.5,
			AssetId = 0,
			Shadow = false,
			Palette = { Shell = h.rgb(255, 255, 255), Core = h.rgb(255, 255, 255) },
			Materials = { Shell = Enum.Material.Neon, Core = Enum.Material.Neon },
			Fallback = function(m)
				h.ball(m, "Shell", 1.5, Vector3.new(0, 0.75, 0))
			end,
		},
		CapyBoomRock = {
			Height = 12.7,
			AssetId = 0,
			Collide = true,
			BlocksCamera = true,
			Palette = { Stone = h.rgb(150, 146, 152), Cap = h.rgb(168, 164, 170) },
			Materials = { Stone = Enum.Material.Slate, Cap = Enum.Material.Slate },
			Fallback = function(m)
				h.pillar(m, "Stone", 7.0, 9, Vector3.new(0, 4.5, 0))
				h.ball(m, "Cap", 7.4, Vector3.new(0, 9, 0))
			end,
		},
	}
end

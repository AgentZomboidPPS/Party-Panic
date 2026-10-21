-- Props for Eatsa Pizza. MeshLibrary loads this file at startup (see World/Props/README.md); the
-- meshes come from tools/meshgen/props/EatsaPizza.py and until they're uploaded the Fallback is used.
--
-- A slice (four stages of being eaten) is drawn at radius 20 with its tip at the pivot's back end
-- and its crust towards -Z: its bounding box runs from the tip (z = 0) forward, so the game puts the
-- tip at the pizza's middle by measuring the box (every stage, mesh or fallback, lines up the same).
-- None of these props is solid: players stand on the pan (a plain part) and the pizza is thin.

return function(h)
	local smooth = Enum.Material.SmoothPlastic
	local metal = Enum.Material.Metal
	local wood = Enum.Material.Wood
	local neon = Enum.Material.Neon

	local slicePalette = {
		Dough = h.rgb(232, 186, 118),
		Sauce = h.rgb(196, 46, 30),
		Cheese = h.rgb(255, 210, 96),
		Crust = h.rgb(212, 140, 64),
		Olives = h.rgb(38, 34, 40),
		Basil = h.rgb(54, 150, 60),
		Peppers = h.rgb(96, 186, 64),
		Toasty = h.rgb(232, 150, 64),
	}
	local sliceMaterials = {
		Dough = smooth,
		Sauce = smooth,
		Cheese = smooth,
		Crust = smooth,
		Olives = smooth,
		Basil = smooth,
		Peppers = smooth,
		Toasty = smooth,
	}

	-- A slice's stand-in: strips across the wedge out to `reach` (and a crust bar on the whole one).
	local function sliceFallback(reach: number, crust: boolean)
		return function(m)
			local half = math.rad(14.6)
			local strips = 8
			for index = 1, strips do
				local r0 = reach * (index - 1) / strips
				local r1 = reach * index / strips
				local width = 2 * math.tan(half) * (r0 + r1) / 2
				h.block(
					m,
					"Cheese",
					Vector3.new(math.max(width, 0.2), 0.3, r1 - r0),
					Vector3.new(0, 0.15, -(r0 + r1) / 2)
				)
			end
			if crust then
				h.block(m, "Crust", Vector3.new(2 * math.tan(half) * 19, 1.0, 1.6), Vector3.new(0, 0.5, -19.2))
			end
		end
	end

	return {
		EatsaPizzaSlice = {
			Height = 1.114,
			AssetId = 0,
			Shadow = false,
			Palette = slicePalette,
			Materials = sliceMaterials,
			Fallback = sliceFallback(20, true),
		},
		EatsaPizzaSlice1 = {
			Height = 0.515,
			AssetId = 0,
			Shadow = false,
			Palette = slicePalette,
			Materials = sliceMaterials,
			Fallback = sliceFallback(15.7, false),
		},
		EatsaPizzaSlice2 = {
			Height = 0.515,
			AssetId = 0,
			Shadow = false,
			Palette = slicePalette,
			Materials = sliceMaterials,
			Fallback = sliceFallback(11.7, false),
		},
		EatsaPizzaSlice3 = {
			Height = 0.515,
			AssetId = 0,
			Shadow = false,
			Palette = slicePalette,
			Materials = sliceMaterials,
			Fallback = sliceFallback(7.3, false),
		},
		EatsaPizzaPepperoni = {
			Height = 0.17,
			AssetId = 0,
			Shadow = false,
			Palette = { Meat = h.rgb(184, 44, 36), Fat = h.rgb(240, 150, 120) },
			Materials = { Meat = smooth, Fat = smooth },
			Fallback = function(m)
				h.pillar(m, "Meat", 2.2, 0.17, Vector3.new(0, 0.085, 0))
			end,
		},
		EatsaPizzaPan = {
			Height = 0.4,
			AssetId = 0,
			Shadow = false,
			Palette = { Rim = h.rgb(196, 200, 210) },
			Materials = { Rim = metal },
			Fallback = function(m)
				for index = 0, 47 do
					local a = index / 48 * math.pi * 2
					local piece = h.block(m, "Rim", Vector3.new(2.9, 0.4, 1.3), Vector3.zero)
					piece.CFrame = CFrame.Angles(0, a, 0) * CFrame.new(0, 0.2, -21.3)
				end
			end,
		},
		EatsaPizzaOven = {
			Height = 13.3,
			AssetId = 0,
			BlocksCamera = true,
			Palette = {
				Base = h.rgb(150, 146, 140),
				Dome = h.rgb(200, 104, 66),
				Bricks = h.rgb(150, 70, 46),
				Rim = h.rgb(120, 110, 104),
				Mouth = h.rgb(30, 20, 18),
				Fire = h.rgb(255, 150, 40),
				Logs = h.rgb(110, 70, 40),
				Chimney = h.rgb(164, 82, 56),
			},
			Materials = {
				Base = Enum.Material.Cobblestone,
				Dome = smooth,
				Bricks = smooth,
				Rim = Enum.Material.Slate,
				Mouth = smooth,
				Fire = neon,
				Logs = wood,
				Chimney = Enum.Material.Brick,
			},
			Fallback = function(m)
				h.block(m, "Base", Vector3.new(12, 4.6, 11), Vector3.new(0, 2.3, 0))
				h.ball(m, "Dome", 9.6, Vector3.new(0, 5.2, 0))
				h.pillar(m, "Chimney", 1.8, 4.5, Vector3.new(0, 10.6, 2))
			end,
		},
		EatsaPizzaBoxes = {
			Height = 3.28,
			AssetId = 0,
			Palette = { Box = h.rgb(214, 176, 120), Print = h.rgb(210, 40, 40), Dots = h.rgb(210, 40, 40) },
			Materials = { Box = Enum.Material.Cardboard, Print = smooth, Dots = smooth },
			Fallback = function(m)
				h.block(m, "Box", Vector3.new(6, 3.2, 6), Vector3.new(0, 1.6, 0))
			end,
		},
		EatsaPizzaSign = {
			Height = 17.57,
			AssetId = 0,
			Palette = {
				Legs = h.rgb(120, 126, 136),
				Board = h.rgb(196, 36, 40),
				Neon = h.rgb(255, 214, 80),
				Bulbs = h.rgb(255, 236, 170),
			},
			Materials = { Legs = metal, Board = smooth, Neon = neon, Bulbs = neon },
			Fallback = function(m)
				h.block(m, "Board", Vector3.new(30, 9, 0.8), Vector3.new(0, 12.5, 0))
				h.block(m, "Legs", Vector3.new(0.9, 9, 0.9), Vector3.new(-10, 4.5, 0.6))
				h.block(m, "Legs", Vector3.new(0.9, 9, 0.9), Vector3.new(10, 4.5, 0.6))
			end,
		},
		EatsaPizzaFlag = {
			Height = 7.83,
			AssetId = 0,
			Palette = { Pick = h.rgb(222, 192, 140), Flag = h.rgb(255, 80, 90) }, -- recolored per team
			Materials = { Pick = wood, Flag = smooth },
			Fallback = function(m)
				h.block(m, "Pick", Vector3.new(0.24, 7.6, 0.24), Vector3.new(0, 3.8, 0))
				h.block(m, "Flag", Vector3.new(3.4, 2.3, 0.1), Vector3.new(1.8, 6.15, 0))
			end,
		},
		EatsaPizzaVent = {
			Height = 3.95,
			AssetId = 0,
			Palette = {
				Body = h.rgb(212, 216, 222),
				Feet = h.rgb(90, 94, 100),
				Fan = h.rgb(60, 64, 70),
				Grille = h.rgb(140, 144, 150),
				Slats = h.rgb(170, 174, 180),
			},
			Materials = { Body = metal, Feet = metal, Fan = metal, Grille = metal, Slats = metal },
			Fallback = function(m)
				h.block(m, "Body", Vector3.new(6, 3.4, 5), Vector3.new(0, 2.1, 0))
			end,
		},
		EatsaPizzaCutter = {
			Height = 9.0,
			AssetId = 0,
			Palette = {
				Wheel = h.rgb(206, 212, 222),
				Hub = h.rgb(90, 94, 100),
				Fork = h.rgb(160, 166, 176),
				Handle = h.rgb(214, 50, 50),
			},
			Materials = { Wheel = metal, Hub = metal, Fork = metal, Handle = smooth },
			Fallback = function(m)
				-- (a cylinder's axis is its X: the wheel stands upright, facing the sides)
				h.pillar(m, "Wheel", 7.2, 0.2, Vector3.new(0, 3.6, 0)).CFrame = CFrame.new(0, 3.6, 0)
				h.block(m, "Handle", Vector3.new(1.1, 1.1, 5.6), Vector3.new(0, 6.6, 4.4))
			end,
		},
	}
end

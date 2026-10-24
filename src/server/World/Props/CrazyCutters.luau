-- Props for Crazy Cutters. MeshLibrary loads this file at startup (see World/Props/README.md).
-- The meshes come from tools/meshgen/props/CrazyCutters.py (which also writes the shapes' outlines
-- into Shared/Logic/CrazyCutters, so a cookie is exactly the shape that was traced); until they're
-- uploaded the Fallback is used.
--
-- Board coordinates: a board, its dough and a cookie all share one frame (x = u to the right,
-- z = -v towards the board's far side), so a cookie placed at the board's pivot sits exactly on
-- the dotted line.
--
-- A fallback that starts with a cylinder resets its pivot (m.WorldPivot): a new model takes its first
-- part's turned orientation, which would tip its bounding box on its side when MeshLibrary sizes it.
return function(h)
	local cookieColor = h.rgb(226, 160, 88)
	local face = h.rgb(70, 40, 30)
	local smooth = Enum.Material.SmoothPlastic
	local baked = Enum.Material.Sand

	-- Fills in an iced cookie's spec from its Size (width, height, depth), its Icing color and its
	-- Extra color (a second icing or dots). (Each cookie's own table keeps its AssetId, where
	-- tools/upload_assets.py writes it.)
	local function cookie(spec)
		local width, height, depth = spec.Size.X, spec.Size.Y, spec.Size.Z
		local icing, extra = spec.Icing, spec.Extra
		for key, value in
			{
				Height = height,
				Shadow = false,
				Palette = {
					Cookie = cookieColor,
					Icing = icing,
					Icing2 = extra or h.rgb(255, 240, 215),
					Dots = extra or h.rgb(255, 255, 255),
					Face = face,
					Shine = h.rgb(255, 255, 255),
					Cheeks = h.rgb(255, 140, 160),
					Sprinkles = h.rgb(255, 110, 170),
					Sprinkles2 = h.rgb(90, 200, 255),
				},
				Materials = {
					Cookie = baked,
					Icing = smooth,
					Icing2 = smooth,
					Dots = smooth,
					Face = smooth,
					Shine = Enum.Material.Neon,
					Cheeks = smooth,
				},
				Fallback = function(m)
					h.blob(m, "Cookie", Vector3.new(width, 0.75, depth), Vector3.new(0, 0.375, 0))
					h.blob(m, "Icing", Vector3.new(width * 0.85, 0.3, depth * 0.85), Vector3.new(0, 0.8, 0))
					h.ball(m, "Face", 0.6, Vector3.new(-0.9, height - 0.15, 0))
					h.ball(m, "Face", 0.6, Vector3.new(0.9, height - 0.15, 0))
				end,
			} :: { [string]: any }
		do
			spec[key] = value
		end
	end

	local props = {
		CuttingBoard = {
			Height = 0.91,
			AssetId = 101395370292756,
			Collide = true,
			Palette = { Board = h.rgb(90, 190, 255), Groove = h.rgb(60, 150, 220) },
			Materials = { Board = smooth, Groove = smooth },
			Fallback = function(m)
				h.rounded(m, "Board", Vector3.new(14.8, 0.8, 17.2), 0.3, Vector3.new(0, 0.4, 0))
			end,
		},
		DoughSheet = {
			Height = 0.42,
			AssetId = 116926183517820,
			Shadow = false,
			Palette = { Dough = h.rgb(250, 228, 190), Flour = h.rgb(255, 255, 255) },
			Materials = { Dough = smooth, Flour = smooth },
			Fallback = function(m)
				h.rounded(m, "Dough", Vector3.new(12.5, 0.42, 12.5), 0.2, Vector3.new(0, 0.21, 0))
			end,
		},
		-- A pastry wheel on a swivel; "Tip" is where the wheel touches the dough.
		PastryCutter = {
			Height = 4.77,
			AssetId = 128077506040018,
			Shadow = false,
			Palette = {
				Wheel = h.rgb(215, 220, 230),
				Fork = h.rgb(255, 205, 90),
				Handle = h.rgb(255, 90, 140),
				Bands = h.rgb(255, 255, 255),
				Tip = h.rgb(255, 255, 255),
			},
			Materials = { Wheel = Enum.Material.Metal, Fork = Enum.Material.Metal },
			PostProcess = function(model: Model)
				local tip = model:FindFirstChild("Tip", true)
				if tip and tip:IsA("BasePart") then
					tip.Transparency = 1
				end
			end,
			Fallback = function(m)
				h.roller(m, "Wheel", 1.7, 0.25, Vector3.new(0, 0.85, 0))
				h.block(m, "Fork", Vector3.new(0.7, 1.2, 0.2), Vector3.new(0, 1.7, 0))
				h.pillar(m, "Handle", 0.6, 2.4, Vector3.new(0, 3.3, 0))
				h.ball(m, "Tip", 0.08, Vector3.new(0, 0.04, 0))
			end,
		},
		CookiePlate = {
			Height = 2.46,
			AssetId = 125521582044980,
			Collide = true,
			Palette = { Plate = h.rgb(255, 255, 255), Rim = h.rgb(255, 150, 190) },
			Materials = { Plate = smooth, Rim = smooth },
			Fallback = function(m)
				h.pillar(m, "Plate", 1.2, 2, Vector3.new(0, 1, 0))
				h.pillar(m, "Plate", 6, 0.3, Vector3.new(0, 2.2, 0))
				m.WorldPivot = CFrame.identity
			end,
		},
		GiantCookie = {
			Height = 4.59,
			AssetId = 139562302204598,
			Palette = { Cookie = h.rgb(222, 158, 86), Chips = h.rgb(84, 48, 34) },
			Materials = { Cookie = baked, Chips = smooth },
			Fallback = function(m)
				h.pillar(m, "Cookie", 116, 3.7, Vector3.new(0, 1.85, 0))
				m.WorldPivot = CFrame.identity
			end,
		},
		MilkGlass = {
			Height = 27.06,
			AssetId = 129885236544387,
			Collide = true,
			Palette = {
				Glass = h.rgb(225, 240, 255),
				Milk = h.rgb(255, 255, 250),
				Straw = h.rgb(255, 90, 120),
				Stripes = h.rgb(255, 255, 255),
			},
			Materials = { Glass = Enum.Material.Glass, Milk = smooth, Straw = smooth, Stripes = smooth },
			PostProcess = function(model: Model)
				local glass = model:FindFirstChild("Glass", true)
				if glass and glass:IsA("BasePart") then
					glass.Transparency = 0.55
				end
			end,
			Fallback = function(m)
				h.pillar(m, "Milk", 9.8, 13, Vector3.new(0, 7.5, 0))
				h.pillar(m, "Glass", 11, 21, Vector3.new(0, 10.5, 0))
				h.pillar(m, "Straw", 1, 26, Vector3.new(2, 13, 0))
				m.WorldPivot = CFrame.identity
			end,
		},
		RollingPin = {
			Height = 3.56,
			AssetId = 119066027978260,
			Collide = true,
			Palette = { Pin = h.rgb(225, 180, 120), Handles = h.rgb(230, 70, 70) },
			Materials = { Pin = Enum.Material.Wood, Handles = smooth },
			Fallback = function(m)
				h.roller(m, "Pin", 3.5, 16, Vector3.new(0, 1.78, 0))
				h.roller(m, "Handles", 1.4, 23, Vector3.new(0, 1.78, 0))
			end,
		},
		StarCutter = {
			Height = 1.73,
			AssetId = 94290492838916,
			Palette = { Steel = h.rgb(200, 205, 215), Rim = h.rgb(225, 230, 240) },
			Materials = { Steel = Enum.Material.Metal, Rim = Enum.Material.Metal },
			Fallback = function(m)
				h.pillar(m, "Steel", 9, 1.7, Vector3.new(0, 0.85, 0))
				m.WorldPivot = CFrame.identity
			end,
		},
		HeartCutter = {
			Height = 1.73,
			AssetId = 110086054650072,
			Palette = { Steel = h.rgb(255, 140, 170), Rim = h.rgb(255, 190, 210) },
			Materials = { Steel = Enum.Material.Metal, Rim = Enum.Material.Metal },
			Fallback = function(m)
				h.pillar(m, "Steel", 10, 1.7, Vector3.new(0, 0.85, 0))
				m.WorldPivot = CFrame.identity
			end,
		},
		StarCookie = {
			AssetId = 95637840745491,
			Size = Vector3.new(9, 1.144, 8.6),
			Icing = h.rgb(255, 214, 72),
		},
		HeartCookie = {
			AssetId = 134179517580561,
			Size = Vector3.new(10.5, 1.178, 8.8),
			Icing = h.rgb(255, 120, 170),
		},
		FishCookie = {
			AssetId = 122310029647475,
			Size = Vector3.new(9.7, 1.142, 6.8),
			Icing = h.rgb(85, 200, 240),
		},
		GhostCookie = {
			AssetId = 74853469484817,
			Size = Vector3.new(10.5, 1.19, 9.9),
			Icing = h.rgb(250, 248, 255),
		},
		MoonCookie = {
			AssetId = 124616441287825,
			Size = Vector3.new(9, 1.14, 10.2),
			Icing = h.rgb(255, 230, 110),
		},
		MushroomCookie = {
			AssetId = 92504966338442,
			Size = Vector3.new(10.5, 1.086, 9.7),
			Icing = h.rgb(240, 72, 72),
			Extra = h.rgb(255, 245, 225),
		},
		FlowerCookie = {
			AssetId = 118501822867049,
			Size = Vector3.new(10.3, 1.462, 10),
			Icing = h.rgb(200, 150, 255),
			Extra = h.rgb(255, 220, 90),
		},
	}
	for name, spec in props do
		if string.sub(name, -6) == "Cookie" and spec.Icing then
			cookie(spec)
		end
	end
	return props
end

-- Props for Prime Cut. MeshLibrary loads this file at startup (see World/Props/README.md).
-- The meshes come from tools/meshgen/props/PrimeCut.py, which also writes the steaks' outlines into
-- Shared/Logic/PrimeCut, so the steak the server splits is exactly the steak on the grill; until
-- they're uploaded the Fallback is used.
--
-- A steak's pivot is the middle of its outline's bounding box, on its underside, so a steak placed at
-- a grill's grate centre lies exactly where the outline says. The knife's blade is the plane x = 0
-- (its edge at y = 0, the tip towards -Z, the handle towards +Z); the grill's grate is
-- GRATE_TOP studs up with its middle over the pivot, the knobs at the front (-Z), the hood open at the
-- back.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PrimeCutLogic = require(ReplicatedStorage.Shared.Logic.PrimeCut)

return function(h)
	local smooth = Enum.Material.SmoothPlastic
	local metal = Enum.Material.Metal
	local wood = Enum.Material.Wood

	-- A steak's stand-in made from strips across its outline (so even the fallback has the exact
	-- shape the server splits).
	local function steakFallback(id: string)
		return function(m)
			local outline = PrimeCutLogic.Outline(id)
			local minX, maxX = PrimeCutLogic.Bounds(outline)
			local width = 0.5
			local x = minX + width / 2
			while x < maxX do
				local crossings = {}
				for index = 1, #outline do
					local a = outline[index]
					local b = outline[index % #outline + 1]
					if (a.X <= x) ~= (b.X <= x) then
						table.insert(crossings, a.Y + (b.Y - a.Y) * (x - a.X) / (b.X - a.X))
					end
				end
				table.sort(crossings)
				for index = 1, #crossings - 1, 2 do
					local z0, z1 = crossings[index], crossings[index + 1]
					h.block(m, "Meat", Vector3.new(width, 1.45, z1 - z0), Vector3.new(x, 0.725, (z0 + z1) / 2))
				end
				x += width
			end
		end
	end

	local function steak(id: string, assetId: number)
		return {
			Height = 1.77,
			AssetId = assetId,
			Shadow = false,
			Palette = {
				Meat = h.rgb(156, 86, 52),
				Crust = h.rgb(104, 52, 30),
				Fat = h.rgb(240, 218, 176),
				Marks = h.rgb(52, 27, 17),
			},
			Materials = { Meat = smooth, Crust = smooth, Fat = smooth, Marks = smooth },
			Fallback = steakFallback(id),
		}
	end

	local props = {
		PrimeCutRibeye = {
			AssetId = 139041453507649,
			Steak = "Ribeye",
		},
		PrimeCutStrip = {
			AssetId = 111832472356610,
			Steak = "Strip",
		},
		PrimeCutTriTip = {
			AssetId = 108392883610995,
			Steak = "TriTip",
		},
		PrimeCutKidney = {
			AssetId = 82082073436404,
			Steak = "Kidney",
		},
		PrimeCutHeart = {
			AssetId = 95000294024880,
			Steak = "Heart",
		},
		PrimeCutChuck = {
			AssetId = 107127698420926,
			Steak = "Chuck",
		},
		PrimeCutKnife = {
			Height = 3.3,
			AssetId = 108387426433490,
			Shadow = true,
			Palette = {
				Blade = h.rgb(196, 204, 216),
				Edge = h.rgb(238, 242, 248),
				Metal = h.rgb(170, 176, 188),
				Handle = h.rgb(52, 36, 32),
				Rivets = h.rgb(226, 229, 236),
			},
			Materials = { Blade = metal, Edge = smooth, Metal = metal, Handle = wood, Rivets = metal },
			Fallback = function(m)
				h.block(m, "Blade", Vector3.new(0.34, 3.2, 17.5), Vector3.new(0, 1.65, -1.75))
				h.rounded(m, "Handle", Vector3.new(1.25, 2.2, 6.6), 0.5, Vector3.new(0, 1.55, 11.1))
				h.block(m, "Metal", Vector3.new(0.9, 2.9, 0.9), Vector3.new(0, 1.75, 7.35))
			end,
		},
		PrimeCutGrill = {
			Height = 23.5,
			AssetId = 78887571401658,
			Palette = {
				Enamel = h.rgb(220, 60, 60), -- recolored per team
				-- Recolored per team too, a lighter coat (MiniGames/PrimeCut): the rim round the grate
				-- and the side tables are what a player's camera sees of their grill.
				Steel = h.rgb(178, 184, 194),
				Grate = h.rgb(44, 44, 48),
				Coals = h.rgb(255, 112, 32),
				Black = h.rgb(34, 34, 38),
				Tick = h.rgb(250, 250, 250),
			},
			Materials = {
				Enamel = smooth,
				Steel = metal,
				Grate = metal,
				Coals = Enum.Material.Neon,
				Black = smooth,
				Tick = smooth,
			},
			Fallback = function(m)
				h.block(m, "Enamel", Vector3.new(25.6, 2.9, 0.45), Vector3.new(0, 3.4, -9.1))
				h.block(m, "Enamel", Vector3.new(25.6, 2.9, 0.45), Vector3.new(0, 3.4, 9.1))
				h.block(m, "Enamel", Vector3.new(0.45, 2.9, 18.6), Vector3.new(-12.6, 3.4, 0))
				h.block(m, "Enamel", Vector3.new(0.45, 2.9, 18.6), Vector3.new(12.6, 3.4, 0))
				h.block(m, "Coals", Vector3.new(24.6, 0.6, 17.6), Vector3.new(0, 2.3, 0))
				h.block(m, "Grate", Vector3.new(24.4, 0.3, 17.4), Vector3.new(0, 4.35, 0))
				local hood = h.block(m, "Enamel", Vector3.new(25.4, 18.6, 0.45), Vector3.new(0, 13.6, 12.4))
				hood.CFrame = CFrame.new(0, 13.6, 12.4) * CFrame.Angles(math.rad(-20), 0, 0)
				for _, x in { -11.8, 11.8 } do
					for _, z in { -8.3, 8.3 } do
						h.block(m, "Black", Vector3.new(0.75, 2.2, 0.75), Vector3.new(x, 1.1, z))
					end
				end
				h.block(m, "Steel", Vector3.new(4.7, 0.36, 14), Vector3.new(-15.25, 4.6, 0))
				h.block(m, "Steel", Vector3.new(4.7, 0.36, 14), Vector3.new(15.25, 4.6, 0))
			end,
		},
		PrimeCutFence = {
			Height = 4.39,
			AssetId = 78309083580880,
			Palette = { Paint = h.rgb(246, 246, 240) },
			Materials = { Paint = wood },
			Fallback = function(m)
				h.block(m, "Paint", Vector3.new(8, 3.8, 0.2), Vector3.new(0, 2.1, 0))
				h.block(m, "Paint", Vector3.new(0.55, 4.3, 0.55), Vector3.new(-4, 2.15, 0.1))
				h.block(m, "Paint", Vector3.new(0.55, 4.3, 0.55), Vector3.new(4, 2.15, 0.1))
			end,
		},
		PrimeCutLights = {
			Height = 3.6,
			AssetId = 123247863598789,
			Shadow = false,
			Palette = { Wire = h.rgb(34, 34, 34), Bulbs = h.rgb(255, 214, 130) },
			Materials = { Wire = smooth, Bulbs = Enum.Material.Neon },
			Fallback = function(m)
				h.block(m, "Wire", Vector3.new(40, 0.12, 0.12), Vector3.new(0, 2.6, 0))
				for index = 0, 8 do
					h.ball(m, "Bulbs", 0.55, Vector3.new(-18 + index * 4.5, 2.1, 0))
				end
			end,
		},
		PrimeCutPost = {
			Height = 12.25,
			AssetId = 82146741120949,
			Palette = { Wood = h.rgb(140, 92, 56), Wire = h.rgb(34, 34, 34) },
			Materials = { Wood = wood },
			Fallback = function(m)
				h.block(m, "Wood", Vector3.new(0.8, 12.2, 0.8), Vector3.new(0, 6.1, 0))
			end,
		},
		PrimeCutTable = {
			Height = 3.28,
			AssetId = 117832438875253,
			Palette = { Wood = h.rgb(176, 116, 70) },
			Materials = { Wood = wood },
			Fallback = function(m)
				h.block(m, "Wood", Vector3.new(12, 0.36, 4.4), Vector3.new(0, 3.1, 0))
				h.block(m, "Wood", Vector3.new(12, 0.34, 1.3), Vector3.new(0, 1.85, -3.45))
				h.block(m, "Wood", Vector3.new(12, 0.34, 1.3), Vector3.new(0, 1.85, 3.45))
			end,
		},
		PrimeCutCooler = {
			Height = 3.21,
			AssetId = 89014426844667,
			Palette = { Body = h.rgb(40, 124, 222), Lid = h.rgb(246, 246, 246), Steel = h.rgb(178, 184, 194) },
			Materials = { Body = smooth, Lid = smooth, Steel = metal },
			Fallback = function(m)
				h.rounded(m, "Body", Vector3.new(4.8, 2.6, 3), 0.4, Vector3.new(0, 1.35, 0))
				h.rounded(m, "Lid", Vector3.new(5, 0.62, 3.2), 0.25, Vector3.new(0, 2.9, 0))
			end,
		},
		PrimeCutSauces = {
			Height = 3.5,
			AssetId = 85512946993024,
			Palette = { Ketchup = h.rgb(212, 32, 32), Mustard = h.rgb(246, 192, 32), Caps = h.rgb(246, 246, 246) },
			Materials = { Ketchup = smooth, Mustard = smooth, Caps = smooth },
			Fallback = function(m)
				h.pillar(m, "Ketchup", 1.4, 2.4, Vector3.new(-0.85, 1.2, 0))
				h.pillar(m, "Mustard", 1.4, 2.4, Vector3.new(0.85, 1.2, 0))
			end,
		},
	}
	-- The steaks share everything but their outline (each keeps its own AssetId above).
	for _, spec in props do
		if spec.Steak then
			for key, value in steak(spec.Steak, spec.AssetId) do
				spec[key] = value
			end
		end
	end
	return props
end

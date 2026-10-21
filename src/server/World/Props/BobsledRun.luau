-- Props for Bobsled Run. MeshLibrary loads this file at startup (see World/Props/README.md).
-- The meshes come from tools/meshgen/props/BobsledRun.py; until they're uploaded the Fallback is used.
--
-- The four track pieces are swept along the course's own path (Shared/Logic/BobsledCourse), so
-- their fallbacks carry an invisible "Bounds" box the size of the mesh: both versions then get the
-- same pivot, and BobsledCourse.Anchor places either one exactly.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BobsledCourse = require(ReplicatedStorage.Shared.Logic.BobsledCourse)

return function(h)
	local ice = h.rgb(168, 214, 246)
	local snow = h.rgb(244, 248, 255)
	local trim = h.rgb(230, 56, 66)
	local trackPalette = { Ice = ice, Snow = snow, Trim = trim, Kicker = h.rgb(200, 232, 252) }
	local trackMaterials = {
		Ice = Enum.Material.Ice,
		Snow = Enum.Material.Snow,
		Trim = Enum.Material.SmoothPlastic,
		Kicker = Enum.Material.Glacier,
	}

	-- A primitive stand-in for a track piece: floor and walls along the path, no banking.
	local function trackFallback(kind: string)
		return function(m: Model)
			local anchor = BobsledCourse.Anchor[kind]
			local size = BobsledCourse.PieceSize[kind]
			h.Build.Decor({
				Name = "Bounds",
				Size = size,
				CFrame = CFrame.new(anchor + Vector3.new(0, size.Y / 2, 0)),
				Transparency = 1,
				Parent = m,
			})
			local course = BobsledCourse.Build(kind)
			local length = course.Total
			local steps = if kind == "L" or kind == "R" then 6 else 1
			local half = BobsledCourse.FLOOR_HALF
			for index = 0, steps - 1 do
				local d0 = length * index / steps
				local d1 = length * (index + 1) / steps
				local a = BobsledCourse.Sample(course, d0)
				local b = BobsledCourse.Sample(course, d1)
				local middle = (a + b) / 2
				local frame = CFrame.lookAt(middle, middle + (b - a))
				local run = (b - a).Magnitude + 1
				h.Build.Decor({
					Name = "Ice",
					Size = Vector3.new(half * 2 + 2, 1, run),
					CFrame = frame * CFrame.new(0, -0.5, 0),
					Parent = m,
				})
				for _, side in { -1, 1 } do
					h.Build.Decor({
						Name = "Snow",
						Size = Vector3.new(4, 7, run),
						CFrame = frame * CFrame.new(side * (half + 2), 2.5, 0),
						Parent = m,
					})
					h.Build.Decor({
						Name = "Trim",
						Size = Vector3.new(2.4, 0.8, run),
						CFrame = frame * CFrame.new(side * (half + 1.6), 6.3, 0),
						Parent = m,
					})
				end
			end
		end
	end

	local function track(kind: string, assetId: number)
		return {
			Height = BobsledCourse.PieceSize[kind].Y,
			AssetId = assetId,
			Shadow = true,
			Palette = trackPalette,
			Materials = trackMaterials,
			Fallback = trackFallback(kind),
		}
	end

	return {
		BobsledTrack = track("S", 140619817274803),
		BobsledKicker = track("J", 105400705129786),
		BobsledCurveL = track("L", 135659421666039),
		BobsledCurveR = track("R", 78885544532507),
		BobsledSled = {
			Height = 2.5,
			AssetId = 91750447706831,
			Palette = {
				Body = h.rgb(230, 60, 70),
				Rim = h.rgb(250, 250, 250),
				Runner = h.rgb(70, 74, 86),
				Nose = h.rgb(40, 40, 48),
			},
			Materials = { Runner = Enum.Material.Metal, Body = Enum.Material.SmoothPlastic },
			Fallback = function(m)
				h.rounded(m, "Body", Vector3.new(3.9, 1.6, 9), 0.7, Vector3.new(0, 0.6, 1.5))
				h.rounded(m, "Body", Vector3.new(3.3, 1.6, 4.2), 0.7, Vector3.new(0, 0.6, -4.6))
				h.block(m, "Rim", Vector3.new(3.4, 0.2, 0.3), Vector3.new(0, 1.95, -2.9))
				h.block(m, "Runner", Vector3.new(0.25, 0.25, 12), Vector3.new(-1.25, 0.12, 0))
				h.block(m, "Runner", Vector3.new(0.25, 0.25, 12), Vector3.new(1.25, 0.12, 0))
				h.ball(m, "Nose", 1, Vector3.new(0, 1, -7))
			end,
		},
		BobsledPine = {
			Height = 14,
			AssetId = 96339533442449,
			Palette = { Needles = h.rgb(38, 92, 66), Snow = snow, Trunk = h.rgb(96, 64, 44) },
			Materials = { Snow = Enum.Material.Snow, Needles = Enum.Material.Grass, Trunk = Enum.Material.Wood },
			Fallback = function(m)
				h.pillar(m, "Trunk", 1.1, 2.6, Vector3.new(0, 1.3, 0))
				for index, size in { 9, 7, 5, 3 } do
					h.blob(m, "Needles", Vector3.new(size, 3.2, size), Vector3.new(0, 1.5 + index * 2.6, 0))
				end
				h.blob(m, "Snow", Vector3.new(2, 2.4, 2), Vector3.new(0, 12.6, 0))
			end,
		},
		BobsledPeak = {
			Height = 100,
			AssetId = 83070320680188,
			Shadow = false,
			Palette = { Rock = h.rgb(104, 110, 128), Snow = snow },
			Materials = { Rock = Enum.Material.Slate, Snow = Enum.Material.Snow },
			Fallback = function(m)
				h.blob(m, "Rock", Vector3.new(150, 120, 150), Vector3.new(0, 30, 0))
				h.blob(m, "Snow", Vector3.new(60, 50, 60), Vector3.new(0, 78, 0))
			end,
		},
		BobsledGate = {
			Height = 28.2,
			AssetId = 120413711639723,
			Palette = {
				Frame = h.rgb(130, 86, 56),
				Banner = trim,
				Bar = h.rgb(255, 210, 60),
				Lights = h.rgb(255, 80, 70),
			},
			Materials = { Frame = Enum.Material.Wood, Lights = Enum.Material.Neon },
			Fallback = function(m)
				for _, x in { -25.8, 25.8 } do
					h.block(m, "Frame", Vector3.new(2.6, 28, 2.6), Vector3.new(x, 14, 0))
				end
				h.block(m, "Frame", Vector3.new(54, 1.6, 2.2), Vector3.new(0, 22.6, 0))
				h.block(m, "Banner", Vector3.new(45, 4.2, 0.5), Vector3.new(0, 19.7, 0))
				h.block(m, "Bar", Vector3.new(39, 0.55, 0.55), Vector3.new(0, 9.6, -1.6))
			end,
		},
		BobsledArch = {
			Height = 30.6,
			AssetId = 135271869131668,
			Palette = { Arch = h.rgb(40, 120, 220), Dark = h.rgb(30, 30, 36), Light = h.rgb(250, 250, 250) },
			Fallback = function(m)
				for _, x in { -25.8, 25.8 } do
					h.block(m, "Arch", Vector3.new(3.2, 30, 3.2), Vector3.new(x, 15, 0))
				end
				h.block(m, "Arch", Vector3.new(55, 3.2, 3.2), Vector3.new(0, 28.6, 0))
				h.block(m, "Dark", Vector3.new(24, 2, 0.4), Vector3.new(0, 25.2, 0))
				h.block(m, "Light", Vector3.new(24, 2, 0.4), Vector3.new(0, 23.2, 0))
			end,
		},
		BobsledFlag = {
			Height = 9.45,
			AssetId = 105634790999210,
			Shadow = false,
			Palette = { Pole = h.rgb(232, 232, 238), Cloth = h.rgb(255, 90, 90) },
			Materials = { Pole = Enum.Material.Metal, Cloth = Enum.Material.Fabric },
			Fallback = function(m)
				h.pillar(m, "Pole", 0.28, 9, Vector3.new(0, 4.5, 0))
				h.block(m, "Cloth", Vector3.new(3.4, 1.8, 0.1), Vector3.new(1.9, 7.8, 0))
			end,
		},
	}
end

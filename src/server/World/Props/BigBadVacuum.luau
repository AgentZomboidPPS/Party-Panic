-- Props for Big Bad Vacuum: the boss itself (a squat robot vacuum with an angry eye, a hungry mouth, a
-- hatch on top that opens onto its glowing core, a swinging brush arm, a dust bag, a power cord and plug),
-- the toy bricks (carried, thrown, piled), the giant toy blocks of the arena wall, and the living room
-- beyond it (a floor lamp, a TV and a couch). The meshes come from tools/meshgen/props/BigBadVacuum.py
-- (the client finds the boss's parts by name, so the meshes keep the same names); the primitive
-- Fallbacks here stand in until an AssetId loads.
--
-- Nothing solid where nothing is drawn: only the wall blocks collide, and they are drawn blocks.
--
-- The boss faces -Z. Its parts are found by name on the client (client/MiniGames/BigBadVacuum): Eye,
-- Iris, Pupil (the eye), BrowL / BrowR, FlapL / FlapR (the core's hatch), Orb (the core), Stripe and
-- VentGlow (they glow with its mood), SideBrushL / SideBrushR and their bristles (they spin: BristlesL /
-- BristlesR on the mesh, Bristles left and right of the middle on the Fallback).
return function(h)
	local rgb = h.rgb
	local Build = h.Build

	-- A disc whose flat faces point along Z (the eye and the core's rim sit on the boss's front/top).
	local function faceDisc(m, name: string, diameter: number, thickness: number, position: Vector3)
		return Build.Part({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(thickness, diameter, diameter),
			CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0),
			Parent = m,
		})
	end

	local function tilted(m, name: string, size: Vector3, position: Vector3, roll: number)
		return Build.Part({
			Name = name,
			Size = size,
			CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(roll)),
			Parent = m,
		})
	end

	local function stud(m, name: string, position: Vector3, diameter: number, height: number)
		local part = h.pillar(m, name, diameter, height, position)
		part.CanCollide = false
		return part
	end

	return {
		-- The boss ------------------------------------------------------------------------------------------
		BigBadVacuumBody = {
			Height = 20.2,
			AssetId = 133394569829714, -- tools/upload_assets.py --only BigBadVacuumBody fills this in
			Palette = {
				Skirt = rgb(24, 24, 30),
				Base = rgb(40, 42, 54),
				Bumper = rgb(26, 26, 32),
				Hazard = rgb(255, 204, 40),
				Hull = rgb(78, 84, 110),
				Stripe = rgb(60, 220, 255),
				Plate = rgb(58, 62, 84),
				Rivet = rgb(170, 176, 196),
				EyeRing = rgb(30, 30, 38),
				Eye = rgb(255, 70, 60),
				Iris = rgb(255, 190, 80),
				Pupil = rgb(12, 12, 16),
				BrowL = rgb(30, 30, 38),
				BrowR = rgb(30, 30, 38),
				Mouth = rgb(22, 20, 28),
				Throat = rgb(8, 6, 12),
				Teeth = rgb(240, 240, 248),
				CoreRim = rgb(255, 196, 60),
				CoreWell = rgb(14, 12, 20),
				FlapL = rgb(96, 102, 130),
				FlapR = rgb(96, 102, 130),
				Orb = rgb(70, 255, 220),
				VentGlow = rgb(255, 120, 40),
				Vent = rgb(24, 24, 30),
				SirenPost = rgb(170, 176, 196),
				Siren = rgb(255, 60, 60),
				Handle = rgb(255, 90, 90),
				SideBrushL = rgb(255, 90, 90),
				SideBrushR = rgb(255, 90, 90),
				Bristles = rgb(250, 230, 120),
				BristlesL = rgb(250, 230, 120),
				BristlesR = rgb(250, 230, 120),
			},
			Materials = {
				Skirt = Enum.Material.SmoothPlastic,
				Base = Enum.Material.Metal,
				Bumper = Enum.Material.SmoothPlastic,
				Hazard = Enum.Material.SmoothPlastic,
				Hull = Enum.Material.Metal,
				Stripe = Enum.Material.Neon,
				Plate = Enum.Material.Metal,
				Rivet = Enum.Material.Metal,
				Eye = Enum.Material.Neon,
				Iris = Enum.Material.Neon,
				CoreRim = Enum.Material.Metal,
				Orb = Enum.Material.Neon,
				VentGlow = Enum.Material.Neon,
				Siren = Enum.Material.Neon,
				SirenPost = Enum.Material.Metal,
				FlapL = Enum.Material.Metal,
				FlapR = Enum.Material.Metal,
				Teeth = Enum.Material.SmoothPlastic,
				Handle = Enum.Material.SmoothPlastic,
				BristlesL = Enum.Material.Fabric,
				BristlesR = Enum.Material.Fabric,
			},
			Fallback = function(m)
				-- The body: a wide base with a rubber bumper (hazard-striped), under a steel dome. (A plain block
				-- comes first: a model's bounding box is turned the way its first part is.)
				h.blob(m, "Hull", Vector3.new(24.6, 13.4, 24.6), Vector3.new(0, 7.6, 0))
				h.pillar(m, "Skirt", 22, 1.2, Vector3.new(0, 0.6, 0))
				h.pillar(m, "Base", 25, 3.2, Vector3.new(0, 2.8, 0))
				h.pillar(m, "Bumper", 27.2, 2.2, Vector3.new(0, 2.5, 0))
				for index = 0, 15 do
					local angle = index / 16 * math.pi * 2
					Build.Part({
						Name = "Hazard",
						Size = Vector3.new(2.6, 1.3, 0.5),
						CFrame = CFrame.lookAt(
							Vector3.new(math.cos(angle) * 13.62, 2.5, math.sin(angle) * 13.62),
							Vector3.new(0, 2.5, 0)
						) * CFrame.Angles(0, 0, math.rad(if index % 2 == 0 then 28 else -28)),
						Parent = m,
					})
				end
				h.pillar(m, "Stripe", 24.9, 0.5, Vector3.new(0, 6.4, 0))
				for index = 0, 11 do
					local angle = (index + 0.5) / 12 * math.pi * 2
					h.ball(m, "Rivet", 0.8, Vector3.new(math.cos(angle) * 12.7, 4.3, math.sin(angle) * 12.7))
				end

				-- The angry eye on the front, with heavy brows.
				faceDisc(m, "EyeRing", 9.4, 1.6, Vector3.new(0, 8.4, -11.3))
				faceDisc(m, "Eye", 7.8, 0.5, Vector3.new(0, 8.4, -12.2))
				faceDisc(m, "Iris", 5.0, 0.5, Vector3.new(0, 8.4, -12.5))
				faceDisc(m, "Pupil", 2.4, 0.5, Vector3.new(0, 8.4, -12.8))
				tilted(m, "BrowL", Vector3.new(5.6, 1.4, 1.6), Vector3.new(-3.2, 13.1, -9.6), -22)
				tilted(m, "BrowR", Vector3.new(5.6, 1.4, 1.6), Vector3.new(3.2, 13.1, -9.6), 22)

				-- The mouth: a wide dark intake with a row of teeth along its top lip.
				h.block(m, "Mouth", Vector3.new(15.6, 4.4, 3.2), Vector3.new(0, 4.4, -12.4))
				h.block(m, "Throat", Vector3.new(13.4, 2.8, 0.5), Vector3.new(0, 4.3, -14.1))
				for index = -3, 3 do
					Build.Part({
						Name = "Teeth",
						Size = Vector3.new(1.5, 1.3, 0.7),
						CFrame = CFrame.new(index * 1.9, 5.9, -14.0),
						Parent = m,
					})
				end

				-- The hatch on top, over the core: rim, well, two sliding flaps and the glowing orb.
				h.pillar(m, "CoreRim", 8.6, 0.9, Vector3.new(0, 14.0, 0))
				h.pillar(m, "CoreWell", 7.2, 0.5, Vector3.new(0, 14.35, 0))
				h.ball(m, "Orb", 4.2, Vector3.new(0, 14.6, 0))
				h.block(m, "FlapL", Vector3.new(3.7, 0.7, 7.2), Vector3.new(-1.85, 14.95, 0))
				h.block(m, "FlapR", Vector3.new(3.7, 0.7, 7.2), Vector3.new(1.85, 14.95, 0))

				-- Back: vents, a siren on a post, and the handle the dust bag hangs from.
				for _, x in { -5, 0, 5 } do
					h.block(m, "Vent", Vector3.new(3.4, 0.5, 1.4), Vector3.new(x, 11.6, 6.6))
					h.block(m, "VentGlow", Vector3.new(2.8, 0.4, 0.8), Vector3.new(x, 11.9, 6.6))
				end
				h.pillar(m, "SirenPost", 0.8, 3.6, Vector3.new(6.4, 14.9, 4.2))
				h.ball(m, "Siren", 2.4, Vector3.new(6.4, 17.6, 4.2))
				h.block(m, "Handle", Vector3.new(1.4, 9.2, 1.4), Vector3.new(-4.2, 14.4, 11.4))
				h.block(m, "Handle", Vector3.new(1.4, 9.2, 1.4), Vector3.new(4.2, 14.4, 11.4))
				h.block(m, "Handle", Vector3.new(9.8, 1.6, 1.6), Vector3.new(0, 19.4, 11.4))

				-- The two side brushes at the front corners (they spin).
				for _, side in { { "SideBrushL", -1 }, { "SideBrushR", 1 } } do
					local x = side[2] * 10.4
					h.pillar(m, side[1], 6.4, 0.7, Vector3.new(x, 1.3, -10.4))
					for bar = 0, 2 do
						Build.Part({
							Name = "Bristles",
							Size = Vector3.new(7.6, 0.5, 0.9),
							CFrame = CFrame.new(x, 1.8, -10.4) * CFrame.Angles(0, math.rad(bar * 60 + 20), 0),
							Parent = m,
						})
					end
				end
				m.PrimaryPart = m:FindFirstChild("Hull") :: BasePart? -- (turns the bounding box with the model, not with a cylinder)
			end,
			PostProcess = function(model)
				-- Pivot on the boss's middle (the handle and mouth make the box lopsided), on the floor: the
				-- round Hull's centre line.
				local primary = model.PrimaryPart
				local hull = model:FindFirstChild("Hull") :: BasePart?
				if primary and hull then
					local box, size = model:GetBoundingBox()
					primary.PivotOffset = primary.CFrame:ToObjectSpace(
						CFrame.new(hull.Position.X, box.Position.Y - size.Y / 2, hull.Position.Z)
					)
				end
			end,
		},

		-- The brush arm: a boom with a spinning brush at its tip, pivoting on the boss's middle.
		BigBadVacuumBrush = {
			Height = 3.05,
			AssetId = 82119850954142,
			Palette = {
				Hub = rgb(255, 196, 60),
				Boom = rgb(72, 78, 100),
				BoomTop = rgb(255, 90, 90),
				Head = rgb(255, 90, 90),
				Bristles = rgb(250, 230, 120),
			},
			Materials = {
				Hub = Enum.Material.Metal,
				Boom = Enum.Material.Metal,
				BoomTop = Enum.Material.SmoothPlastic,
				Bristles = Enum.Material.Fabric,
			},
			Fallback = function(m)
				h.block(m, "Boom", Vector3.new(3, 1.8, 21), Vector3.new(0, 1.7, -16.5))
				h.pillar(m, "Hub", 5, 2.4, Vector3.new(0, 1.2, 0))
				h.block(m, "BoomTop", Vector3.new(1.6, 0.5, 19), Vector3.new(0, 2.8, -16.5))
				h.pillar(m, "Head", 8, 1.8, Vector3.new(0, 1.9, -27))
				for bar = 0, 5 do
					Build.Part({
						Name = "Bristles",
						Size = Vector3.new(8.8, 1.4, 0.8),
						CFrame = CFrame.new(0, 1.3, -27) * CFrame.Angles(0, math.rad(bar * 30), 0),
						Parent = m,
					})
				end
				m.PrimaryPart = m:FindFirstChild("Boom") :: BasePart?
			end,
			PostProcess = function(model)
				-- Pivot on the hub, so turning the model turns the arm round the boss.
				local primary = model.PrimaryPart
				local hub = model:FindFirstChild("Hub") :: BasePart?
				if primary and hub then
					primary.PivotOffset =
						primary.CFrame:ToObjectSpace(CFrame.new(hub.Position.X, hub.Position.Y - 1.2, hub.Position.Z))
				end
			end,
		},

		-- The dust bag: a big translucent bag on a collar, hung from the handle.
		BigBadVacuumBag = {
			Height = 14.3,
			AssetId = 79386099331121,
			Shadow = false,
			Palette = {
				Bag = rgb(236, 236, 250),
				Collar = rgb(255, 90, 90),
			},
			Materials = {
				Bag = Enum.Material.Glass,
				Collar = Enum.Material.SmoothPlastic,
			},
			Fallback = function(m)
				local bag = h.ball(m, "Bag", 14, Vector3.new(0, 7.3, 0))
				bag.Transparency = 0.55
				bag.Reflectance = 0.05
				h.pillar(m, "Collar", 7.4, 1.6, Vector3.new(0, 0.8, 0))
				m.PrimaryPart = m:FindFirstChild("Bag") :: BasePart?
			end,
		},

		BigBadVacuumCordLink = {
			Height = 2.2,
			AssetId = 85126924426452,
			Shadow = false,
			Palette = { Cord = rgb(250, 250, 244), Band = rgb(255, 90, 90) },
			Fallback = function(m)
				h.roller(m, "Cord", 1.8, 2.6, Vector3.new(0, 1.1, 0))
				h.roller(m, "Band", 2.2, 0.5, Vector3.new(0, 1.1, 0))
				m.PrimaryPart = m:FindFirstChild("Cord") :: BasePart?
			end,
		},

		BigBadVacuumPlug = {
			Height = 6.5,
			AssetId = 107707103445449,
			Palette = { Plug = rgb(250, 250, 244), Prong = rgb(210, 214, 224), Glow = rgb(255, 230, 90) },
			Materials = { Prong = Enum.Material.Metal, Glow = Enum.Material.Neon },
			Fallback = function(m)
				h.block(m, "Plug", Vector3.new(6.6, 5.4, 5), Vector3.new(0, 3.2, 0))
				h.block(m, "Prong", Vector3.new(0.8, 2.4, 0.6), Vector3.new(-1.5, 5.8, -3.3))
				h.block(m, "Prong", Vector3.new(0.8, 2.4, 0.6), Vector3.new(1.5, 5.8, -3.3))
				h.block(m, "Glow", Vector3.new(4.4, 0.4, 3.2), Vector3.new(0, 5.95, 0))
				m.PrimaryPart = m:FindFirstChild("Plug") :: BasePart?
			end,
		},

		-- The toy bricks ---------------------------------------------------------------------------------
		BigBadVacuumBrick = {
			Height = 2.4,
			AssetId = 113646589451518,
			Palette = { Body = rgb(250, 90, 80), Stud = rgb(250, 120, 110) },
			Fallback = function(m)
				h.block(m, "Body", Vector3.new(3.4, 1.9, 2.0), Vector3.new(0, 0.95, 0))
				stud(m, "Stud", Vector3.new(-0.8, 2.15, 0), 1.0, 0.5)
				stud(m, "Stud", Vector3.new(0.8, 2.15, 0), 1.0, 0.5)
				m.PrimaryPart = m:FindFirstChild("Body") :: BasePart?
			end,
		},

		BigBadVacuumPile = {
			Height = 5.7,
			AssetId = 139407645212840,
			Palette = {
				Red = rgb(232, 76, 84),
				Blue = rgb(70, 140, 235),
				Yellow = rgb(250, 200, 60),
				Green = rgb(86, 200, 120),
				Orange = rgb(250, 140, 60),
				Purple = rgb(160, 110, 230),
			},
			Fallback = function(m)
				local function brick(name: string, x: number, y: number, z: number, turn: number, size: Vector3)
					local part = Build.Part({
						Name = name,
						Size = size,
						CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(turn), 0),
						Parent = m,
					})
					part.CanCollide = false
					return part
				end
				brick("Red", -1.6, 0.95, 0.4, 14, Vector3.new(3.4, 1.9, 2))
				brick("Blue", 1.9, 0.95, -0.6, -20, Vector3.new(3.4, 1.9, 2))
				brick("Yellow", 0.2, 0.95, -2.6, 70, Vector3.new(3.4, 1.9, 2))
				brick("Green", -0.2, 0.95, 2.6, -80, Vector3.new(3.4, 1.9, 2))
				brick("Orange", -0.6, 2.85, 0.2, 30, Vector3.new(3.4, 1.9, 2))
				brick("Purple", 1.2, 2.85, -0.8, -50, Vector3.new(3.4, 1.9, 2))
				brick("Blue", 0.1, 4.75, -0.2, 8, Vector3.new(3.4, 1.9, 2))
				m.PrimaryPart = m:FindFirstChild("Red") :: BasePart?
			end,
		},

		BigBadVacuumDebris = {
			Height = 1.9,
			AssetId = 72683840240434,
			Shadow = false,
			Palette = { Chunk = rgb(78, 84, 110), Spark = rgb(255, 160, 60) },
			Materials = { Chunk = Enum.Material.Metal, Spark = Enum.Material.Neon },
			Fallback = function(m)
				h.block(m, "Chunk", Vector3.new(2.2, 1.4, 1.6), Vector3.new(0, 0.7, 0))
				h.block(m, "Spark", Vector3.new(0.9, 0.6, 0.9), Vector3.new(0.5, 1.6, 0.2))
				m.PrimaryPart = m:FindFirstChild("Chunk") :: BasePart?
			end,
		},

		-- The arena ----------------------------------------------------------------------------------------
		BigBadVacuumBlock = {
			Height = 15.8,
			AssetId = 80906435565292,
			Collide = true,
			Palette = { Body = rgb(232, 76, 84), Face = rgb(240, 130, 136), Stud = rgb(255, 255, 255) },
			Materials = { Body = Enum.Material.SmoothPlastic, Face = Enum.Material.SmoothPlastic },
			Fallback = function(m)
				h.block(m, "Body", Vector3.new(15, 15.2, 14), Vector3.new(0, 7.6, 0))
				-- The inward face (-Z) gets a raised panel.
				h.block(m, "Face", Vector3.new(10.4, 10.4, 0.7), Vector3.new(0, 7.6, -7.2))
				for _, x in { -3.4, 3.4 } do
					for _, z in { -3, 3 } do
						stud(m, "Stud", Vector3.new(x, 15.45, z), 3.4, 0.7)
					end
				end
				m.PrimaryPart = m:FindFirstChild("Body") :: BasePart?
			end,
		},

		BigBadVacuumLamp = {
			Height = 47,
			AssetId = 120987859160114,
			Shadow = false,
			Palette = { Pole = rgb(50, 48, 58), Foot = rgb(36, 34, 44), Shade = rgb(255, 214, 140) },
			Materials = { Pole = Enum.Material.Metal, Shade = Enum.Material.Neon },
			Fallback = function(m)
				h.block(m, "Foot", Vector3.new(12, 1.5, 12), Vector3.new(0, 0.75, 0))
				h.pillar(m, "Pole", 2, 32, Vector3.new(0, 17.5, 0))
				h.pillar(m, "Shade", 20, 14, Vector3.new(0, 40, 0))
				m.PrimaryPart = m:FindFirstChild("Foot") :: BasePart?
			end,
			PostProcess = function(model)
				local shade = model:FindFirstChild("Shade") :: BasePart?
				if shade then
					shade.Transparency = 0.15
					Build.Light(shade, rgb(255, 200, 120), 80, 2.4)
				end
			end,
		},

		BigBadVacuumTV = {
			Height = 36,
			AssetId = 88103386342478,
			Shadow = false,
			Palette = { Frame = rgb(24, 24, 30), Screen = rgb(70, 130, 255), Stand = rgb(40, 40, 50) },
			Materials = { Screen = Enum.Material.Neon, Stand = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "Stand", Vector3.new(24, 3, 10), Vector3.new(0, 1.5, 0))
				h.block(m, "Frame", Vector3.new(56, 32, 4), Vector3.new(0, 20, 0))
				h.block(m, "Screen", Vector3.new(51, 27, 0.6), Vector3.new(0, 20, -2.2))
				m.PrimaryPart = m:FindFirstChild("Stand") :: BasePart?
			end,
			PostProcess = function(model)
				local screen = model:FindFirstChild("Screen") :: BasePart?
				if screen then
					Build.Light(screen, rgb(110, 160, 255), 90, 1.6)
				end
			end,
		},

		BigBadVacuumCouch = {
			Height = 31,
			AssetId = 73568888582023,
			Shadow = false,
			Palette = {
				Seat = rgb(120, 40, 60),
				Back = rgb(104, 34, 52),
				Arm = rgb(96, 30, 48),
				Cushion = rgb(140, 52, 72),
				Leg = rgb(92, 62, 40),
			},
			Materials = {
				Seat = Enum.Material.Fabric,
				Back = Enum.Material.Fabric,
				Arm = Enum.Material.Fabric,
				Cushion = Enum.Material.Fabric,
				Leg = Enum.Material.Wood,
			},
			Fallback = function(m)
				h.block(m, "Seat", Vector3.new(72, 12, 26), Vector3.new(0, 6, 0))
				h.block(m, "Back", Vector3.new(72, 26, 8), Vector3.new(0, 18, 9))
				h.block(m, "Arm", Vector3.new(8, 20, 26), Vector3.new(-40, 10, 0))
				h.block(m, "Arm", Vector3.new(8, 20, 26), Vector3.new(40, 10, 0))
				h.block(m, "Cushion", Vector3.new(22, 6, 20), Vector3.new(-14, 15, -2))
				h.block(m, "Cushion", Vector3.new(22, 6, 20), Vector3.new(14, 15, -2))
				m.PrimaryPart = m:FindFirstChild("Seat") :: BasePart?
			end,
		},
	}
end

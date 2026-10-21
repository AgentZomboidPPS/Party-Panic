-- Props for Pump & Pop (meshes from tools/meshgen/props/PumpAndPop.py):
--   PumpBalloon  the team balloon. Its face looks along -Z; the client scales it as the team pumps
--                and shows the spare face pieces (Brows, Ooh, Sweat) as it gets close to popping.
--   AirTank      the tank each balloon is tied to (knot on the brass neck at the top). The client
--                turns the gauge's Needle, which points at 12 o'clock in the mesh.
--   Plunger      a floor pump; its hose runs along -Z into the tank. Rod, Handle and Grips are the
--                parts the client slides down while a player pushes.
-- Every piece name matters to the client half (src/client/MiniGames/PumpAndPop.luau), so the
-- fallbacks use the same names.

return function(h)
	local rgb = h.rgb
	local Build = h.Build

	-- A part facing along Z (the fallback dial and its needle).
	local function facing(m: Model, name: string, shape: Enum.PartType, size: Vector3, position: Vector3): Part
		return Build.Part({
			Name = name,
			Shape = shape,
			Size = size,
			CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0),
			Parent = m,
		})
	end

	return {
		PumpBalloon = {
			Height = 15,
			AssetId = 0,
			Shadow = true,
			Palette = {
				Skin = rgb(255, 80, 95),
				Eyes = rgb(255, 255, 255),
				Pupils = rgb(35, 25, 45),
				Shine = rgb(255, 255, 255),
				Smile = rgb(120, 25, 45),
				Ooh = rgb(110, 20, 40),
				Brows = rgb(90, 30, 40),
				Blush = rgb(255, 150, 170),
				Sweat = rgb(120, 200, 255),
			},
			Materials = { Skin = Enum.Material.Glass, Sweat = Enum.Material.Glass },
			Fallback = function(m)
				h.blob(m, "Skin", Vector3.new(11.4, 13.6, 11.4), Vector3.new(0, 8.3, 0))
				h.ball(m, "Skin", 0.9, Vector3.new(0, 0.5, 0))
				for _, side in { -1, 1 } do
					h.blob(m, "Eyes", Vector3.new(1.8, 2.4, 0.7), Vector3.new(side * 1.75, 9.4, -5.35))
					h.blob(m, "Pupils", Vector3.new(1.0, 1.3, 0.5), Vector3.new(side * 1.63, 9.28, -5.62))
					h.ball(m, "Shine", 0.34, Vector3.new(side * 1.63 + 0.18, 9.54, -5.86))
					h.block(m, "Brows", Vector3.new(1.5, 0.26, 0.26), Vector3.new(side * 1.75, 11.05, -5.1))
					h.blob(m, "Blush", Vector3.new(1.5, 0.8, 0.3), Vector3.new(side * 3.1, 8.0, -4.75))
				end
				h.rounded(m, "Smile", Vector3.new(2.2, 0.32, 0.32), 0.15, Vector3.new(0, 6.85, -5.68))
				h.blob(m, "Ooh", Vector3.new(0.95, 1.3, 0.3), Vector3.new(0, 7.0, -5.72))
				h.ball(m, "Sweat", 0.6, Vector3.new(3.55, 11.2, -3.8))
			end,
		},
		AirTank = {
			Height = 4.7,
			AssetId = 0,
			Collide = true,
			Palette = {
				Feet = rgb(70, 60, 90),
				Tank = rgb(250, 245, 255),
				TankBands = rgb(255, 200, 60),
				Brass = rgb(230, 175, 70),
				Dial = rgb(255, 255, 250),
				Ticks = rgb(40, 35, 60),
				DialRed = rgb(255, 70, 70),
				Needle = rgb(235, 40, 50),
			},
			Materials = { Brass = Enum.Material.Metal, TankBands = Enum.Material.Metal },
			Fallback = function(m)
				h.pillar(m, "Feet", 5.6, 0.36, Vector3.new(0, 0.18, 0))
				h.pillar(m, "Tank", 4.9, 3.6, Vector3.new(0, 2.14, 0))
				h.blob(m, "Tank", Vector3.new(4.6, 1.1, 4.6), Vector3.new(0, 3.9, 0))
				h.pillar(m, "TankBands", 5.15, 0.26, Vector3.new(0, 0.62, 0))
				h.pillar(m, "TankBands", 5.15, 0.26, Vector3.new(0, 3.3, 0))
				h.pillar(m, "Brass", 0.9, 0.7, Vector3.new(0, 4.35, 0))
				facing(m, "Brass", Enum.PartType.Cylinder, Vector3.new(0.3, 1.9, 1.9), Vector3.new(0, 2.15, -2.55))
				facing(m, "Dial", Enum.PartType.Cylinder, Vector3.new(0.1, 1.6, 1.6), Vector3.new(0, 2.15, -2.72))
				h.block(m, "DialRed", Vector3.new(0.3, 0.3, 0.05), Vector3.new(-0.62, 1.95, -2.78))
				h.block(m, "Needle", Vector3.new(0.12, 0.62, 0.06), Vector3.new(0, 2.46, -2.82))
			end,
		},
		Plunger = {
			Height = 4.18,
			AssetId = 0,
			Palette = {
				PumpBase = rgb(60, 55, 75),
				Barrel = rgb(255, 80, 95),
				Chrome = rgb(215, 220, 235),
				Hose = rgb(60, 55, 75),
				Rod = rgb(225, 230, 240),
				Handle = rgb(250, 250, 255),
				Grips = rgb(45, 40, 55),
			},
			Materials = { Chrome = Enum.Material.Metal, Rod = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "PumpBase", Vector3.new(2.4, 0.2, 1.0), Vector3.new(0, 0.1, 0))
				h.pillar(m, "Barrel", 0.8, 2.42, Vector3.new(0, 1.51, 0))
				h.pillar(m, "Chrome", 0.95, 0.25, Vector3.new(0, 0.38, 0))
				h.pillar(m, "Chrome", 0.95, 0.25, Vector3.new(0, 2.72, 0))
				h.rounded(m, "Hose", Vector3.new(0.26, 0.26, 4.6), 0.12, Vector3.new(0, 0.15, -2.75))
				h.pillar(m, "Rod", 0.17, 2.25, Vector3.new(0, 2.775, 0))
				h.roller(m, "Handle", 0.22, 2.4, Vector3.new(0, 3.9, 0))
				h.roller(m, "Grips", 0.38, 0.8, Vector3.new(-0.86, 3.9, 0))
				h.roller(m, "Grips", 0.38, 0.8, Vector3.new(0.86, 3.9, 0))
			end,
		},
	}
end

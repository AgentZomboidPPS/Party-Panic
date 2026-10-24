-- Props for Trace Race (meshes from tools/meshgen/props/TraceRace.py): the giant crayon everyone
-- rides (Wax and Wrapper take the rider's colour), the clipboard's clip and the desk clutter round
-- the clipboard. None of them collide: riders never walk in this mode, and nothing solid may stand
-- where nothing is drawn.
return function(h)
	local function tilted(m: Model, name: string, diameter: number, length: number, along: number)
		-- A cylinder on the crayon's axis: it rises 22 degrees from the tip (front, -Z) backwards.
		local tilt = math.rad(22)
		local axis = Vector3.new(0, math.sin(tilt), math.cos(tilt))
		local tip = Vector3.new(0, 0.3, -6.37)
		local part = h.roller(m, name, diameter, length, Vector3.zero)
		part.CFrame = CFrame.lookAt(tip + axis * along, tip + axis * (along + 1)) * CFrame.Angles(0, math.rad(90), 0)
		return part
	end
	return {
		TraceRaceCrayon = {
			Height = 6.46,
			AssetId = 108044411554238, -- tools/upload_assets.py --only TraceRaceCrayon fills this in
			Palette = { Wax = h.rgb(235, 55, 60), Wrapper = h.rgb(200, 40, 50), Bands = h.rgb(40, 30, 35) },
			Materials = { Wrapper = Enum.Material.Fabric },
			Fallback = function(m)
				-- (An upright piece first: the model's box is measured square to its first part.)
				h.ball(m, "Wax", 0.7, Vector3.new(0, 0.35, -6.37))
				tilted(m, "Wax", 0.7, 1.2, 0.5)
				tilted(m, "Wax", 1.5, 2, 2)
				tilted(m, "Wax", 2.3, 10.5, 8.6)
				tilted(m, "Wrapper", 2.45, 8, 8.7)
			end,
		},
		TraceRaceClip = {
			Height = 7.2,
			AssetId = 137039929094291,
			Palette = { Metal = h.rgb(200, 205, 215), Hinge = h.rgb(170, 175, 185), Rivets = h.rgb(150, 155, 165) },
			Materials = { Metal = Enum.Material.Metal, Hinge = Enum.Material.Metal, Rivets = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "Metal", Vector3.new(22, 0.7, 7), Vector3.new(0, 0.35, 0))
				h.block(m, "Metal", Vector3.new(19, 0.5, 7), Vector3.new(0, 3, 0.4))
				h.roller(m, "Hinge", 1.1, 19.4, Vector3.new(0, 2.3, 0.6))
			end,
		},
		TraceRaceCrayonBox = {
			Height = 26.6,
			AssetId = 114066388288612,
			Palette = {
				Box = h.rgb(250, 210, 40),
				Band = h.rgb(40, 150, 70),
				Chevrons = h.rgb(40, 150, 70),
				CrayonA = h.rgb(235, 55, 60),
				CrayonB = h.rgb(45, 120, 235),
				CrayonC = h.rgb(50, 185, 80),
				CrayonD = h.rgb(255, 145, 30),
				CrayonE = h.rgb(150, 80, 220),
				CrayonF = h.rgb(255, 105, 180),
			},
			Materials = { Box = Enum.Material.Cardboard, Band = Enum.Material.Cardboard },
			Fallback = function(m)
				h.block(m, "Box", Vector3.new(16, 18, 6), Vector3.new(0, 9, 0))
				h.block(m, "Band", Vector3.new(16.2, 3, 6.2), Vector3.new(0, 13.5, 0))
				for index, name in { "CrayonA", "CrayonB", "CrayonC", "CrayonD", "CrayonE", "CrayonF" } do
					h.pillar(m, name, 2.3, 14, Vector3.new(-6.25 + (index - 1) * 2.5, 14 + ((index - 1) % 3) * 1.6, 0))
				end
			end,
		},
		TraceRacePencil = {
			Height = 4.3,
			AssetId = 73461830652650,
			Palette = {
				Body = h.rgb(250, 200, 40),
				Wood = h.rgb(235, 200, 150),
				Lead = h.rgb(60, 60, 70),
				Ferrule = h.rgb(200, 200, 210),
				Eraser = h.rgb(255, 140, 160),
			},
			Materials = { Wood = Enum.Material.Wood, Ferrule = Enum.Material.Metal },
			Fallback = function(m)
				local along = CFrame.Angles(0, math.rad(90), 0)
				h.roller(m, "Body", 4, 46, Vector3.zero).CFrame = CFrame.new(0, 2, 0) * along
				h.roller(m, "Wood", 2.4, 4.4, Vector3.zero).CFrame = CFrame.new(0, 2, -25.2) * along
				h.roller(m, "Lead", 0.9, 1.6, Vector3.zero).CFrame = CFrame.new(0, 2, -28.2) * along
				h.roller(m, "Ferrule", 4.2, 3.2, Vector3.zero).CFrame = CFrame.new(0, 2, 24.6) * along
				h.roller(m, "Eraser", 3.9, 3.6, Vector3.zero).CFrame = CFrame.new(0, 2, 27.8) * along
			end,
		},
		TraceRaceEraser = {
			Height = 4.5,
			AssetId = 96770399702903,
			Palette = { Rubber = h.rgb(255, 150, 170), Sleeve = h.rgb(60, 110, 220), Stripe = h.rgb(255, 255, 255) },
			Materials = { Sleeve = Enum.Material.Cardboard },
			Fallback = function(m)
				h.block(m, "Rubber", Vector3.new(10, 4, 18), Vector3.new(0, 2, 0))
				h.block(m, "Sleeve", Vector3.new(10.5, 4.5, 9), Vector3.new(0, 2.25, 2))
			end,
		},
		TraceRaceSharpener = {
			Height = 7.7,
			AssetId = 93701630339581,
			Palette = {
				Body = h.rgb(185, 190, 200),
				Hole = h.rgb(60, 60, 70),
				Blade = h.rgb(225, 230, 240),
				Screw = h.rgb(120, 125, 135),
			},
			Materials = { Body = Enum.Material.Metal, Blade = Enum.Material.Metal, Screw = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "Body", Vector3.new(10, 7, 12), Vector3.new(0, 3.5, 0))
				h.block(m, "Blade", Vector3.new(6, 0.4, 4.6), Vector3.new(0.6, 7.2, -2))
			end,
		},
		TraceRacePaperClip = {
			Height = 1,
			AssetId = 88357872996387,
			Palette = { Wire = h.rgb(190, 195, 205) },
			Materials = { Wire = Enum.Material.Metal },
			Fallback = function(m)
				h.block(m, "Wire", Vector3.new(1, 1, 30), Vector3.new(-3, 0.5, 0))
				h.block(m, "Wire", Vector3.new(1, 1, 26), Vector3.new(3, 0.5, 0))
			end,
		},
	}
end

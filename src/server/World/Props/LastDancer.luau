-- Props for Last Dancer. MeshLibrary loads this file at startup (see World/Props/README.md); get one with
-- MeshLibrary.Get("LastDancerMirrorBall", { CFrame = ..., Parent = ctx.Arena }).
-- The meshes come from tools/meshgen/props/LastDancer.py; until they're uploaded (and approved) the
-- Fallbacks are used: the same shapes in plain parts. Both are decoration: nothing collides.
return function(h)
	return {
		-- The disco ball over the stage (its lowest point on the prop's ground).
		LastDancerMirrorBall = {
			Height = 10.7,
			AssetId = 119450628247692, -- tools/upload_assets.py --only LastDancerMirrorBall,LastDancerSpeaker fills this in
			Palette = { Ball = h.rgb(235, 240, 255), Cap = h.rgb(180, 180, 195) },
			Materials = { Ball = Enum.Material.Metal, Cap = Enum.Material.Metal },
			Fallback = function(m)
				h.ball(m, "Ball", 9, Vector3.new(0, 4.5, 0))
				h.pillar(m, "Cap", 1.8, 1.2, Vector3.new(0, 9.4, 0))
			end,
		},
		-- Three speaker cabinets stacked, the cones facing the front (-Z).
		LastDancerSpeaker = {
			Height = 13.1,
			AssetId = 102236463569054, -- (see above)
			Palette = { Body = h.rgb(28, 26, 42), Cone = h.rgb(70, 70, 92), Rim = h.rgb(150, 150, 170) },
			Materials = {
				Body = Enum.Material.Slate,
				Cone = Enum.Material.SmoothPlastic,
				Rim = Enum.Material.Metal,
			},
			Fallback = function(m)
				for level = 0, 2 do
					local y = 2.2 + 4.4 * level
					h.block(m, "Body", Vector3.new(5 - 0.6 * level, 4.3, 4.4), Vector3.new(0, y, 0))
					h.Build.Decor({
						Name = "Cone",
						Shape = Enum.PartType.Cylinder,
						Size = Vector3.new(0.3, 3.1, 3.1),
						CFrame = CFrame.new(0, y - 0.35, -2.25) * CFrame.Angles(0, math.rad(90), 0),
						Parent = m,
					})
				end
			end,
		},
	}
end

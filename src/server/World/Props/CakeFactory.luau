-- Props for Cake Factory. MeshLibrary loads this file at startup (see World/Props/README.md); get one
-- with MeshLibrary.Get("CakeFactoryTrophy", { CFrame = ..., Parent = ctx.Arena }).
-- The mesh comes from tools/meshgen/props/CakeFactory.py; until it's uploaded the Fallback is used.
return function(h)
	return {
		CakeFactoryTrophy = {
			Height = 6,
			AssetId = 0, -- tools/upload_assets.py --only CakeFactoryTrophy fills this in
			Collide = true,
			Palette = { Cup = h.rgb(255, 205, 60), Base = h.rgb(90, 70, 160) },
			Fallback = function(m)
				h.rounded(m, "Base", Vector3.new(3, 1, 3), 0.3, Vector3.new(0, 0.5, 0))
				h.ball(m, "Cup", 3, Vector3.new(0, 3.5, 0))
			end,
		},
	}
end

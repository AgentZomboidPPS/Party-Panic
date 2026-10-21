# Mini-game props

Each mini-game keeps its own props here, in `<Game>.luau`, so modes built side by side never edit the
same file. MeshLibrary loads every module in this folder at startup:

```lua
-- Props for Pump & Pop.
return function(h)
	return {
		Pump = {
			Height = 4.6, -- canonical height in studs (the mesh is scaled to it)
			AssetId = 0, -- filled in by tools/upload_assets.py
			Collide = true,
			Palette = { Body = h.rgb(230, 60, 70), Handle = h.rgb(250, 250, 250) },
			Materials = { Handle = Enum.Material.Metal },
			Fallback = function(m) -- primitive stand-in if the mesh can't load
				h.pillar(m, "Body", 1.6, 3, Vector3.new(0, 1.5, 0))
				h.block(m, "Handle", Vector3.new(2.4, 0.4, 0.4), Vector3.new(0, 4.2, 0))
			end,
		},
	}
end
```

Props don't collide unless `Collide = true`. Scenery the camera could slide inside (big props next to
where players stand, or anything the default camera, 12.5 studs behind a player, can reach) gets
`BlocksCamera = true`: still nothing collides with it, but the camera stops in front of it instead of
showing its inside. A prop that turns in place lists only its round pieces (`BlocksCamera = { "Rim" }`);
never use it on props that move around.

Helpers: `rgb block ball pillar roller blob rounded capsule cluster Build Shapes` (see MeshLibrary).
The meshes themselves come from `tools/meshgen/props/<Game>.py`.

Give every prop its own `Name = { ... AssetId = ..., ... }` block like the one above, even when a
helper fills in the rest of its fields: the upload, permission and moderation tools read those
blocks to find the game's meshes. A mesh whose id only appears inside a helper call isn't granted
to the game, so nobody but the owner would see it.

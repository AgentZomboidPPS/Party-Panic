-- Uploaded asset ids for the original soundtrack and sound effects in assets/audio.
-- 0 = not uploaded yet (Sounds.luau then uses its defaults). Filled in by tools/upload_assets.py.

return {
	-- One upload holding every sound effect (see src/shared/SfxSprite.luau for the offsets).
	SfxSprite = 0,
	Music = {
		Lobby = 0,
		Lobby2 = 0,
		Round = 0,
	},
	Sfx = {
		VoteOpen = 0,
		VoteClick = 0,
		Countdown = 0,
		RoundStart = 0,
		HazardWarning = 0,
		Hit = 0,
		Pickup = 0,
		Eliminated = 0,
		Victory = 0,
		Results = 0,
		ReturnToLobby = 0,
		Boing = 0,
		Purchase = 0,
		Splash = 0,
		Click = 0,
	},
}

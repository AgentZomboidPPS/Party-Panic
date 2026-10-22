-- Uploaded asset ids for the original soundtrack and sound effects in assets/audio.
-- 0 = not uploaded yet (Sounds.luau then uses its defaults). Filled in by tools/upload_assets.py.

return {
	-- One upload holding every sound effect (see src/shared/SfxSprite.luau for the offsets).
	SfxSprite = 135145103433440,
	Music = {
		Lobby = 125330857433697,
		Lobby2 = 101866514278416,
		Round = 74689013738140,
	},
	-- The mini-games' own round songs, packed several to a file (tools/music/modes.py; where each song
	-- sits is in ModeMusic.luau). A game whose pack isn't uploaded yet plays "Panic Mode" (Music.Round).
	ModeMusic = {
		ModePack1 = 133632130255608,
		ModePack2 = 117185721710928,
		ModePack3 = 96432706159875,
		ModePack4 = 91819577463974,
		ModePack5 = 111855655225102,
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

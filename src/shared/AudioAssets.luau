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
	-- Each mini-game's own round track by mode id (tools/music/rounds.py; RoundMusic.luau has their
	-- drop times). A mode without one, or whose track doesn't load, plays Music.Round.
	Rounds = {
		FireRope = 118157821114084,
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

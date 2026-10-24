--!strict
-- Where a mini-game's own round song should be playing at a given moment (owner: "put in the backlog
-- custom music for each mini game", then "take over the music."). Each song (tools/music/modes.py)
-- sits in a packed audio file from Start to End; its intro ends at Drop, which the game lines up with
-- GO, and the part from Drop to End loops for as long as the round runs. AudioController asks this
-- module for the song's position from the time to GO, so every player hears the band kick in exactly
-- when the round starts, whenever their song finished loading.
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.

local SongTiming = {}

-- How far off a playing song may be before AudioController jumps it to where it should be (a jump is
-- audible, so small drifts stay). Last Dancer's chart follows the same rule (MiniGames/LastDancer).
SongTiming.DRIFT = 0.35

export type Song = {
	Start: number, -- where the song starts in its pack (seconds)
	Drop: number, -- where its intro ends: this moment plays at GO
	End: number, -- where it ends; Drop..End loops
}

-- The song's position (seconds into its pack) `sinceGo` seconds after GO (negative: before GO). Before
-- GO it's in the intro, or at its very start if GO is further away than the intro is long; after GO it
-- goes round the loop.
function SongTiming.Position(song: Song, sinceGo: number): number
	if sinceGo < 0 then
		return math.max(song.Start, song.Drop + sinceGo)
	end
	local loop = song.End - song.Drop
	if loop <= 0 then
		return song.Drop
	end
	return song.Drop + sinceGo % loop
end

-- How long to wait before starting the song, so its intro ends on GO even when GO is further away
-- than the intro is long (0: start now).
function SongTiming.Wait(song: Song, sinceGo: number): number
	return math.max(0, -sinceGo - (song.Drop - song.Start))
end

-- Seconds since GO from the round's phase and its timer: during Preparing the timer counts down to GO;
-- during the round it counts down the round's `duration` from GO. Nil in any other phase.
function SongTiming.SinceGo(phase: string, timeLeft: number, duration: number): number?
	if phase == "Preparing" then
		return -timeLeft
	elseif phase == "InRound" then
		return duration - timeLeft
	end
	return nil
end

-- Whether a song playing at `position` has drifted far enough from where it should be (`expected`)
-- to jump back in time: a late load, a hitch, or a round that started late. Small drifts are left
-- alone (a jump is audible). Positions inside the loop compare round the loop, so a song that just
-- went round isn't "far off".
function SongTiming.Drifted(song: Song, position: number, expected: number, tolerance: number): boolean
	local difference = math.abs(position - expected)
	local loop = song.End - song.Drop
	if loop > 0 and position >= song.Drop and expected >= song.Drop then
		difference = math.min(difference, loop - difference)
	end
	return difference > tolerance
end

return SongTiming

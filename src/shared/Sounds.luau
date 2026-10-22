-- Audio cues (design doc §13 "Audio plan").
--
-- Music and most effects are ORIGINAL audio rendered by tools/music (see docs/ASSETS.md); every
-- mini-game also has its own round song (tools/music/modes.py), packed several to an upload.
-- tools/upload_assets.py uploads them and writes their asset ids into AudioAssets.luau, which
-- overrides the defaults below. Until then, effects fall back to sounds that ship with the Roblox
-- client and music stays silent. To use a track from the Roblox audio library instead, paste its
-- id ("rbxassetid://123") into AudioAssets.luau.

local AudioAssets = require(script.Parent.AudioAssets)
local ModeMusic = require(script.Parent.ModeMusic)
local SfxSprite = require(script.Parent.SfxSprite)

local defaults = {
	Music = {
		Lobby = "", -- "Party Plaza"
		Lobby2 = "", -- "Sunset Social"
		Round = "", -- "Panic Mode"
	},
	Sfx = {
		VoteOpen = "rbxasset://sounds/electronicpingshort.wav",
		VoteClick = "rbxasset://sounds/button.wav",
		Countdown = "rbxasset://sounds/clickfast.wav",
		RoundStart = "rbxasset://sounds/electronicpingshort.wav",
		HazardWarning = "rbxasset://sounds/clickfast.wav",
		Hit = "rbxasset://sounds/swordlunge.wav",
		Pickup = "rbxasset://sounds/electronicpingshort.wav",
		Eliminated = "rbxasset://sounds/uuhhh.mp3",
		Victory = "rbxasset://sounds/electronicpingshort.wav",
		Results = "rbxasset://sounds/electronicpingshort.wav",
		ReturnToLobby = "rbxasset://sounds/swoosh.wav",
		Boing = "rbxasset://sounds/action_jump.mp3",
		Purchase = "rbxasset://sounds/electronicpingshort.wav",
		Splash = "rbxasset://sounds/impact_water.mp3",
		Click = "rbxasset://sounds/button.wav",
	},
}

local function idFor(value: any): string?
	if type(value) == "number" and value > 0 then
		return "rbxassetid://" .. value
	elseif type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

for group, entries in defaults do
	for name in entries do
		local override = AudioAssets[group] and AudioAssets[group][name]
		local id = idFor(override)
		if id then
			entries[name] = id
		end
	end
end

-- When the effects sprite is uploaded, every effect plays as a region of that one sound.
local spriteId = idFor(AudioAssets.SfxSprite)
local sprite = if spriteId then { Id = spriteId, Regions = SfxSprite } else nil

-- Each mini-game's own round song (owner: "custom music for each mini game"), once its pack is
-- uploaded: the pack's id and where the song sits in it (Logic/SongTiming says how they're played).
export type ModeSong = { Id: string, Title: string, Start: number, Drop: number, End: number }
local modeSongs: { [string]: ModeSong } = {}
local packs = (AudioAssets :: any).ModeMusic or {}
for modeId, song in ModeMusic :: { [string]: any } do
	local id = idFor(packs[song.Pack])
	if id then
		modeSongs[modeId] = { Id = id, Title = song.Title, Start = song.Start, Drop = song.Drop, End = song.End }
	end
end

return {
	Music = defaults.Music,
	Sfx = defaults.Sfx,
	Sprite = sprite,
	ModeSongs = modeSongs,
}

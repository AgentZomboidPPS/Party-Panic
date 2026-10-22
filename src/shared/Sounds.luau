-- Audio cues (design doc §13 "Audio plan").
--
-- Music and most effects are ORIGINAL audio rendered by tools/music (see docs/AUDIO.md).
-- tools/upload_assets.py uploads them and writes their asset ids into AudioAssets.luau, which
-- overrides the defaults below. Until then, effects fall back to sounds that ship with the Roblox
-- client and music stays silent. To use a track from the Roblox audio library instead, paste its
-- id ("rbxassetid://123") into AudioAssets.luau.

local AudioAssets = require(script.Parent.AudioAssets)
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

-- Each mini-game's own round track (mode id -> sound id), for the ones uploaded.
local rounds = {}
for modeId, value in (AudioAssets :: any).Rounds or {} do
	local id = idFor(value)
	if id then
		rounds[modeId] = id
	end
end

return {
	Music = defaults.Music,
	Sfx = defaults.Sfx,
	Sprite = sprite,
	Rounds = rounds,
}

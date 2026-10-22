-- Music and sound effects, played locally so each player controls their own mix.
--
-- Music is organised as playlists that never restart from the top:
--   * Lobby plays "Party Plaza" then "Sunset Social" (~4 minutes before anything repeats), and
--     each lobby visit RESUMES where the last one stopped, so short lobby stints don't replay the
--     same opening over and over.
--   * Rounds play "Panic Mode", which speeds up for the final 10 seconds ("hurry up!").
-- Comfort: music starts quiet on first launch and fades in slowly, ducks while a menu is open,
-- and the player picks Off / Low / Medium / High in Settings.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)

local State = require(script.Parent.Parent.State)
local Modal = require(script.Parent.Parent.UI.Modal)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local AudioController = {}

local MUSIC_BASE_VOLUME = 0.5 -- multiplied by the player's level (Medium = 0.5 -> 0.25)
local DEFAULT_LEVEL = 0.5
local MENU_DUCK = 0.55
local FIRST_FADE_DELAY = 2
local FIRST_FADE_TIME = 6
local SWITCH_FADE_TIME = 1.2
local HURRY_TIME = 10

local PLAYLISTS = {
	Lobby = { "Lobby", "Lobby2" },
	Round = { "Round" },
}

type Playlist = { tracks: { Sound }, index: number, positions: { [Sound]: number } }

local sfx: { [string]: Sound } = {}
local playlists: { [string]: Playlist } = {}
local currentList: string? = nil
local currentSound: Sound? = nil
local menuOpen = false
local warmup = 0 -- 0..1 during the first-launch fade-in
local fades: { [Sound]: Tween } = {} -- one fade per sound so a crossfade never cancels itself

local function makeSound(name: string, id: string, volume: number, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume
	sound.Looped = looped
	sound.Parent = SoundService
	return sound
end

function AudioController.Play(name: string)
	local sound = sfx[name]
	if not sound then
		return
	end
	if sound.PlaybackRegionsEnabled then
		-- Sprite effects play a region of one shared sound; clone so effects can overlap.
		local clone = sound:Clone()
		clone.Parent = SoundService
		clone:Play()
		Debris:AddItem(clone, sound.PlaybackRegion.Max - sound.PlaybackRegion.Min + 0.5)
	else
		SoundService:PlayLocalSound(sound)
	end
end

local function playerLevel(): number
	local level = State.Setting("MusicVolume")
	return if type(level) == "number" then math.clamp(level, 0, 1) else DEFAULT_LEVEL
end

local function targetVolume(): number
	return MUSIC_BASE_VOLUME * playerLevel() * warmup * (if menuOpen then MENU_DUCK else 1)
end

local function fadeTo(sound: Sound, volume: number, time: number): Tween
	local previous = fades[sound]
	if previous then
		previous:Cancel()
	end
	local tween = UIKit.Tween(sound, time, { Volume = volume })
	fades[sound] = tween
	return tween
end

local function pauseCurrent()
	local sound = currentSound
	local list = currentList and playlists[currentList]
	if not sound or not list then
		return
	end
	list.positions[sound] = sound.TimePosition
	local tween = fadeTo(sound, 0, SWITCH_FADE_TIME)
	tween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and currentSound ~= sound then
			sound:Pause()
		end
	end)
end

local function startCurrent()
	local list = currentList and playlists[currentList]
	if not list or #list.tracks == 0 then
		currentSound = nil
		return
	end
	local sound = list.tracks[list.index]
	currentSound = sound
	if not sound.IsPlaying then
		sound.Volume = 0
		local resumeAt = list.positions[sound]
		if resumeAt and resumeAt > 0 then
			sound.TimePosition = resumeAt
			sound:Resume()
		else
			sound:Play()
		end
	end
	fadeTo(sound, targetVolume(), SWITCH_FADE_TIME)
end

local function switchTo(listName: string)
	if listName == currentList then
		return
	end
	pauseCurrent()
	currentList = listName
	startCurrent()
end

-- When a lobby track finishes, move on to the next one in the playlist.
local function onEnded(listName: string, sound: Sound)
	local list = playlists[listName]
	list.positions[sound] = 0
	list.index = (list.index % #list.tracks) + 1
	if currentList == listName and currentSound == sound then
		currentSound = nil
		startCurrent()
	end
end

local function listForPhase(phase: string): string
	return if phase == "Preparing" or phase == "InRound" then "Round" else "Lobby"
end

local function refreshVolume(time: number?)
	local sound = currentSound
	if sound then
		fadeTo(sound, targetVolume(), time or 0.6)
	end
end

-- What this device's music is doing right now, for the sound report (AssetReportController).
function AudioController.Status(): { [string]: any }
	local sound = currentSound
	return {
		Track = if sound then sound.Name else "none",
		Loaded = sound ~= nil and sound.IsLoaded,
		Playing = sound ~= nil and sound.IsPlaying,
		Time = if sound then sound.TimePosition else 0,
		Volume = if sound then sound.Volume else 0,
		Loudness = if sound then sound.PlaybackLoudness else 0,
		Level = playerLevel(),
	}
end

function AudioController.Start(_context)
	local function effectVolume(name: string): number
		return if name == "Click" or name == "VoteClick" then 0.4 else 0.6
	end
	local sprite = Sounds.Sprite
	if sprite then
		for name, region in sprite.Regions do
			local sound = makeSound("Sfx_" .. name, sprite.Id, effectVolume(name), false)
			sound.PlaybackRegionsEnabled = true
			sound.PlaybackRegion = NumberRange.new(region.Start, region.Start + region.Length)
			sfx[name] = sound
		end
	else
		for name, id in Sounds.Sfx do
			sfx[name] = makeSound("Sfx_" .. name, id, effectVolume(name), false)
		end
	end
	UIKit.SetClickHandler(function()
		AudioController.Play("Click")
	end)

	for listName, trackNames in PLAYLISTS do
		local list: Playlist = { tracks = {}, index = 1, positions = {} }
		local looped = #trackNames == 1
		for _, trackName in trackNames do
			local id = (Sounds.Music :: any)[trackName]
			if type(id) == "string" and id ~= "" then
				local sound = makeSound("Music_" .. trackName, id, 0, looped)
				table.insert(list.tracks, sound)
				if not looped then
					sound.Ended:Connect(function()
						onEnded(listName, sound)
					end)
				end
			end
		end
		playlists[listName] = list
	end

	Remotes.Get("PlaySound").OnClientEvent:Connect(function(name)
		if type(name) == "string" then
			AudioController.Play(name)
		end
	end)

	GameState.Changed("Phase", function(phase)
		switchTo(listForPhase(phase))
	end)
	switchTo(listForPhase(GameState.Get("Phase")))

	-- First launch: start silent, then fade in gently once the player is in.
	task.delay(FIRST_FADE_DELAY, function()
		local warm = Instance.new("NumberValue")
		warm.Value = 0
		warm.Changed:Connect(function(value)
			warmup = value
			local sound = currentSound
			local fade = sound and fades[sound]
			if sound and (not fade or fade.PlaybackState ~= Enum.PlaybackState.Playing) then
				sound.Volume = targetVolume()
			end
		end)
		local tween =
			UIKit.Tween(warm, FIRST_FADE_TIME, { Value = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		tween.Completed:Once(function()
			warm:Destroy()
			refreshVolume()
		end)
	end)

	State.SettingsChanged:Connect(function()
		refreshVolume()
	end)
	Modal.AnyOpenChanged:Connect(function(open)
		menuOpen = open
		refreshVolume(0.4)
	end)

	-- Countdown beeps during the last 3 seconds of Preparing (for the players in the round, not someone
	-- sitting it out in the lobby), and the hurry-up speed-up.
	local localPlayer = Players.LocalPlayer
	local lastBeep = -1
	local roundTrack = playlists.Round.tracks[1]
	RunService.Heartbeat:Connect(function()
		local phase = GameState.Get("Phase")
		local left = GameState.TimeLeft()
		if phase == "Preparing" then
			local second = math.ceil(left)
			if second <= 3 and second >= 1 and second ~= lastBeep then
				lastBeep = second
				if localPlayer and localPlayer:GetAttribute("PP_InRound") == true then
					AudioController.Play("Countdown")
				end
			end
		else
			lastBeep = -1
		end
		if roundTrack then
			local speed = if phase == "InRound" and left > 0 and left <= HURRY_TIME then 1.12 else 1
			if math.abs(roundTrack.PlaybackSpeed - speed) > 0.001 then
				roundTrack.PlaybackSpeed += (speed - roundTrack.PlaybackSpeed) * 0.05
			end
		end
	end)
end

return AudioController

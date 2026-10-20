-- Music and sound effects, played locally so each player controls their own mix.
-- * Lobby and round tracks crossfade with the phase.
-- * The round track speeds up for the final 10 seconds ("hurry up!").
-- * Phase stings: vote opening, countdown beeps, round start.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)

local State = require(script.Parent.Parent.State)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local AudioController = {}

local MUSIC_VOLUME = 0.42
local HURRY_TIME = 10

local sfx: { [string]: Sound } = {}
local music: { [string]: Sound } = {}
local currentTrack: string? = nil

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
	if sound then
		SoundService:PlayLocalSound(sound)
	end
end

local function musicEnabled(): boolean
	return State.Setting("MusicOn") ~= false
end

local function setTrack(name: string?)
	if name == currentTrack then
		return
	end
	currentTrack = name
	for trackName, sound in music do
		if trackName == name and musicEnabled() then
			if not sound.IsPlaying then
				sound.Volume = 0
				sound.PlaybackSpeed = 1
				sound:Play()
			end
			UIKit.Tween(sound, 1.2, { Volume = MUSIC_VOLUME })
		elseif sound.IsPlaying then
			local tween = UIKit.Tween(sound, 1, { Volume = 0 })
			tween.Completed:Once(function()
				if currentTrack ~= trackName then
					sound:Stop()
				end
			end)
		end
	end
end

local function trackForPhase(phase: string): string
	if phase == "Preparing" or phase == "InRound" then
		return "Round"
	end
	return "Lobby"
end

function AudioController.Start(_context)
	for name, id in Sounds.Sfx do
		sfx[name] = makeSound("Sfx_" .. name, id, if name == "Click" or name == "VoteClick" then 0.45 else 0.7, false)
	end
	for name, id in Sounds.Music do
		if id ~= "" then
			music[name] = makeSound("Music_" .. name, id, 0, true)
		end
	end
	UIKit.SetClickSound(sfx.Click)

	Remotes.Get("PlaySound").OnClientEvent:Connect(function(name)
		if type(name) == "string" then
			AudioController.Play(name)
		end
	end)

	local function onPhase()
		local phase = GameState.Get("Phase")
		setTrack(trackForPhase(phase))
	end
	GameState.Changed("Phase", onPhase)
	onPhase()

	State.SettingsChanged:Connect(function()
		local wanted = currentTrack
		currentTrack = nil
		if not musicEnabled() then
			for _, sound in music do
				sound:Stop()
			end
		end
		setTrack(wanted)
	end)

	-- Countdown beeps during the last 3 seconds of Preparing, and the hurry-up speed-up.
	local lastBeep = -1
	RunService.Heartbeat:Connect(function()
		local phase = GameState.Get("Phase")
		local left = GameState.TimeLeft()
		if phase == "Preparing" then
			local second = math.ceil(left)
			if second <= 3 and second >= 1 and second ~= lastBeep then
				lastBeep = second
				AudioController.Play("Countdown")
			end
		else
			lastBeep = -1
		end
		local roundTrack = music.Round
		if roundTrack then
			local speed = if phase == "InRound" and left > 0 and left <= HURRY_TIME then 1.12 else 1
			if math.abs(roundTrack.PlaybackSpeed - speed) > 0.001 then
				roundTrack.PlaybackSpeed = roundTrack.PlaybackSpeed + (speed - roundTrack.PlaybackSpeed) * 0.05
			end
		end
	end)
end

return AudioController

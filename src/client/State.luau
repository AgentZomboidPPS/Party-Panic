-- Client-side view of the player's profile and the replicated round state.
-- The server is the source of truth; this module only caches what it sends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local State = {}

State.Profile = nil :: any
State.ProfileChanged = Signal.new()
State.GameState = GameState
State.LocalPlayer = Players.LocalPlayer

-- Local UI-only events that controllers use to talk to each other.
State.OpenScreen = Signal.new() -- (screenName: string)
State.SettingsChanged = Signal.new()

function State.Init()
	Remotes.Get("ProfileData").OnClientEvent:Connect(function(snapshot)
		local previous = State.Profile
		State.Profile = snapshot
		State.ProfileChanged:Fire(snapshot, previous)
		if
			not previous
			or previous.Settings.ReducedEffects ~= snapshot.Settings.ReducedEffects
			or previous.Settings.MusicVolume ~= snapshot.Settings.MusicVolume
		then
			State.SettingsChanged:Fire(snapshot.Settings)
		end
	end)
end

function State.Setting(key: string): any
	local profile = State.Profile
	return profile and profile.Settings and profile.Settings[key]
end

function State.ReducedEffects(): boolean
	return State.Setting("ReducedEffects") == true
end

function State.Owns(itemId: string): boolean
	local profile = State.Profile
	return profile ~= nil and profile.Owned[itemId] == true
end

function State.Phase(): string
	return GameState.Get("Phase") or "Waiting"
end

function State.InRound(): boolean
	return State.LocalPlayer:GetAttribute("PP_InRound") == true
end

function State.Alive(): boolean
	return State.LocalPlayer:GetAttribute("PP_Alive") == true
end

-- Sitting out the next rounds (the server's word: Services/SitOutService sets PP_SitOut).
function State.SittingOut(): boolean
	return State.LocalPlayer:GetAttribute("PP_SitOut") == true
end

return State

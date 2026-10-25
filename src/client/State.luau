-- Client-side view of the player's profile and the replicated round state.
-- The server is the source of truth; this module only caches what it sends.
--
-- More room to see the game in a round (owner: "During the mini games, any way we can save UI space
-- so they can see more of the game at one time?"): PlayingRound says who gets the round's quiet
-- screen (the menu column tucked away, toasts held back), RoundCallout carries the round's
-- announcements to the strip under the banner on phones, and TopHudShift moves the mode HUDs up
-- into the status line's room when that line has nothing to say.

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
-- (message: string, color: Color3, duration: number) a round callout (the server's Notify topic
-- "Round": RoundContext.Announce) for the strip under the banner on phones (HudController).
State.RoundCallout = Signal.new()
-- How far the mode HUDs' TopHud sits from where api:HudY() expects the status line and team scores
-- to end, in the HUD's scaled units (HudController sets it, Kit/Api follows it): 0 with a status
-- line, less when the line is out of the way, more while a two-line callout is up.
State.TopHudShift = 0
State.TopHudShiftChanged = Signal.new() -- (shift: number)
-- True while something in the lobby films with its own camera (Skee-Ball): MiniGameController
-- leaves the camera alone then, and otherwise puts it back on the player between rounds.
State.CameraHeld = false

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

-- Still playing the round they're in (in it, and not out of it): once out they're back in the lobby
-- while it goes on, and the lobby's crates open for them (Services/CrateService.Open asks the same).
function State.StillPlaying(): boolean
	return State.InRound() and State.Alive()
end

-- Sitting out the next rounds (the server's word: Services/SitOutService sets PP_SitOut).
function State.SittingOut(): boolean
	return State.LocalPlayer:GetAttribute("PP_SitOut") == true
end

-- Playing the round right now: in it, from its rules card to its end, and not knocked out. Not
-- someone sitting it out, who joined after it started, or who's out and watching.
function State.PlayingRound(): boolean
	local phase = State.Phase()
	return (phase == "Preparing" or phase == "InRound") and State.InRound() and State.Alive()
end

-- Calls `callback()` whenever State.PlayingRound may have changed.
function State.OnPlayingChanged(callback: () -> ())
	GameState.Changed("Phase", callback)
	State.LocalPlayer:GetAttributeChangedSignal("PP_InRound"):Connect(callback)
	State.LocalPlayer:GetAttributeChangedSignal("PP_Alive"):Connect(callback)
end

function State.SetTopHudShift(shift: number)
	if shift ~= State.TopHudShift then
		State.TopHudShift = shift
		State.TopHudShiftChanged:Fire(shift)
	end
end

return State

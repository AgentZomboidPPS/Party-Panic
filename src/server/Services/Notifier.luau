-- Server helpers for toasts, client effects and sound cues.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local notifyRemote = Remotes.Get("Notify")
local effectRemote = Remotes.Get("PlayEffect")
local soundRemote = Remotes.Get("PlaySound")

local Notifier = {}

-- Bots (BotService) look like players but have no device to send anything to.
local function reachable(player: any): boolean
	return typeof(player) == "Instance" and player.Parent ~= nil
end

-- kind: "info" | "success" | "warning" | "reward"
function Notifier.Send(player: Player, text: string, kind: string?, duration: number?)
	if reachable(player) then
		notifyRemote:FireClient(player, text, kind or "info", duration)
	end
end

function Notifier.All(text: string, kind: string?, duration: number?)
	notifyRemote:FireAllClients(text, kind or "info", duration)
end

function Notifier.Players(players: { Player }, text: string, kind: string?, duration: number?)
	for _, player in players do
		if reachable(player) then
			notifyRemote:FireClient(player, text, kind or "info", duration)
		end
	end
end

-- Visual effects are rendered on clients so each player's "reduced effects" setting is respected.
function Notifier.Effect(effectName: string, position: Vector3, colors: { Color3 }?)
	effectRemote:FireAllClients(effectName, position, colors)
end

function Notifier.Sound(players: { Player }?, soundName: string)
	if players then
		for _, player in players do
			if reachable(player) then
				soundRemote:FireClient(player, soundName)
			end
		end
	else
		soundRemote:FireAllClients(soundName)
	end
end

function Notifier.AllPlayers(): { Player }
	return Players:GetPlayers()
end

return Notifier

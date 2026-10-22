-- Server helpers for toasts, client effects and sound cues.
--
-- Toasts can carry a topic (owner: "During the mini games, any way we can save UI space so they can
-- see more of the game at one time?"): Notifier.ROUND marks a callout about the round itself (Golden
-- Rush, Big Bumps: RoundContext.Announce), which a player's screen shows while they play; any other
-- toast waits there until the round is over (client NotificationController).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local notifyRemote = Remotes.Get("Notify")
local effectRemote = Remotes.Get("PlayEffect")
local soundRemote = Remotes.Get("PlaySound")

local Notifier = {}

-- The topic of a callout about the round being played.
Notifier.ROUND = "Round"

-- Bots (BotService) look like players but have no device to send anything to.
local function reachable(player: any): boolean
	return typeof(player) == "Instance" and player.Parent ~= nil
end

-- kind: "info" | "success" | "warning" | "reward"; topic: nil, or Notifier.ROUND
function Notifier.Send(player: Player, text: string, kind: string?, duration: number?, topic: string?)
	if reachable(player) then
		notifyRemote:FireClient(player, text, kind or "info", duration, topic)
	end
end

function Notifier.All(text: string, kind: string?, duration: number?, topic: string?)
	notifyRemote:FireAllClients(text, kind or "info", duration, topic)
end

function Notifier.Players(players: { Player }, text: string, kind: string?, duration: number?, topic: string?)
	for _, player in players do
		if reachable(player) then
			notifyRemote:FireClient(player, text, kind or "info", duration, topic)
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

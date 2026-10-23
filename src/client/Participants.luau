-- Everyone taking part, players and bots alike, behind one small interface, so the standings,
-- spectating, the podium, results and mini-game visuals show bots wherever they show players
-- (bots fill rounds: "we need bots in the mini games").
--
-- A bot (server: Services/BotService) is a Configuration in ReplicatedStorage.PartyBots with the
-- attributes players get in a round (PP_InRound, PP_Alive, PP_Score, PP_ScoreText, PP_Team,
-- PP_Vote, MG_<key>), plus DisplayName ("Mochi"), a negative UserId, IsBot, Color, and an
-- ObjectValue "Character" pointing at its character model.
--
--   Participants.All()               players, then bots
--   Participants.InRound()           the ones playing the current round
--   Participants.FromUserId(id)      one of them by UserId (bots have negative ids)
--   Participants.CharacterOf(id)     their character model, if it's in the world
--   Participants.Changed             fires when a player or a bot arrives or leaves
--
-- Each one has Name, DisplayName, UserId, IsBot, IsLocal, Color (bots' accent color), Instance (the
-- Player, or the bot's Configuration), :GetAttribute(name), :GetAttributeChangedSignal(name) and
-- :Character().

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

local Participants = {}

export type Participant = {
	Name: string,
	DisplayName: string,
	UserId: number,
	IsBot: boolean,
	IsLocal: boolean,
	Color: Color3?,
	Instance: any, -- the Player, or the bot's Configuration
	GetAttribute: (self: Participant, name: string) -> any,
	GetAttributeChangedSignal: (self: Participant, name: string) -> RBXScriptSignal,
	Character: (self: Participant) -> Model?,
}

Participants.Changed = Signal.new()

local Entry = {}
Entry.__index = Entry

function Entry.GetAttribute(self: Participant, name: string): any
	return self.Instance:GetAttribute(name)
end

function Entry.GetAttributeChangedSignal(self: Participant, name: string): RBXScriptSignal
	return self.Instance:GetAttributeChangedSignal(name)
end

function Entry.Character(self: Participant): Model?
	if not self.IsBot then
		return self.Instance.Character
	end
	local pointer = self.Instance:FindFirstChild("Character")
	local model = if pointer and pointer:IsA("ObjectValue") then pointer.Value else nil
	return if model and model:IsA("Model") and model.Parent then model else nil
end

-- One entry per Player or bot Configuration, kept while it's here so entries can be table keys.
local entries: { [any]: Participant } = {}
local botFolder: Instance? = nil

local function playerEntry(player: Player): Participant
	local entry = entries[player]
	if not entry then
		entry = setmetatable({
			Name = player.Name,
			DisplayName = player.DisplayName,
			UserId = player.UserId,
			IsBot = false,
			IsLocal = player == Players.LocalPlayer,
			Color = nil,
			Instance = player,
		}, Entry) :: any
		entries[player] = entry
	end
	return entry :: Participant
end

local function botEntry(info: Instance): Participant
	local entry = entries[info]
	if not entry then
		local shortName = string.gsub(info.Name, "^Bot_", "")
		entry = setmetatable({
			Name = info.Name,
			DisplayName = info:GetAttribute("DisplayName") or shortName,
			UserId = info:GetAttribute("UserId") or 0,
			IsBot = true,
			IsLocal = false,
			Color = info:GetAttribute("Color"),
			Instance = info,
		}, Entry) :: any
		entries[info] = entry
	end
	return entry :: Participant
end

local function isBotInfo(child: Instance): boolean
	return child:IsA("Configuration") and child:GetAttribute("IsBot") ~= false
end

function Participants.All(): { Participant }
	local list = {}
	for _, player in Players:GetPlayers() do
		table.insert(list, playerEntry(player))
	end
	if botFolder then
		for _, child in botFolder:GetChildren() do
			if isBotInfo(child) then
				table.insert(list, botEntry(child))
			end
		end
	end
	return list
end

function Participants.InRound(): { Participant }
	local list = {}
	for _, entry in Participants.All() do
		if entry:GetAttribute("PP_InRound") == true then
			table.insert(list, entry)
		end
	end
	return list
end

-- (Mini-games look riders up by UserId every frame, so the lookup is a cached map, refreshed when
-- someone arrives or leaves; building the full list each time cost phones a table per call.)
local byUserId: { [number]: Participant } = {}
local notHere: { [number]: boolean } = {}

local function stillHere(entry: Participant): boolean
	local instance = entry.Instance
	return instance.Parent ~= nil and (not entry.IsBot or instance.Parent == botFolder)
end

function Participants.FromUserId(userId: number?): Participant?
	if type(userId) ~= "number" then
		return nil
	end
	local entry = byUserId[userId]
	if entry and stillHere(entry) then
		return entry
	end
	if notHere[userId] then
		return nil
	end
	table.clear(byUserId)
	for _, each in Participants.All() do
		byUserId[each.UserId] = each
	end
	entry = byUserId[userId]
	if entry then
		return entry
	end
	notHere[userId] = true -- until the next arrival or departure
	return nil
end

function Participants.CharacterOf(userId: number?): Model?
	local entry = Participants.FromUserId(userId)
	return if entry then entry:Character() else nil
end

-- Bots have negative UserIds (real ones are positive), so an id in results or shared state tells.
function Participants.IsBotId(userId: any): boolean
	return type(userId) == "number" and userId < 0
end

-- Text that's safe inside a RichText label.
function Participants.Escape(text: string): string
	return (string.gsub(text, "[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }))
end

-- A name for a RichText list row (escaped). Bots' names look like anyone's (owner: "Lets remove the
-- bot tag so people dont know they are playing with a bot."): `_bot` says nothing on screen.
function Participants.ListName(name: string, _bot: boolean): string
	return Participants.Escape(name)
end

-- Keeping up with arrivals and departures ----------------------------------------------------------

local function changed()
	table.clear(notHere)
	Participants.Changed:Fire()
end

local function watchBots(folder: Instance)
	botFolder = folder
	folder.ChildAdded:Connect(function(child)
		if isBotInfo(child) then
			changed()
		end
	end)
	folder.ChildRemoved:Connect(function(child)
		if entries[child] or isBotInfo(child) then
			entries[child] = nil
			changed()
		end
	end)
	if #folder:GetChildren() > 0 then
		changed()
	end
end

-- The server makes the bot folder when it starts, which can replicate after this script runs.
local existing = ReplicatedStorage:FindFirstChild("PartyBots")
if existing then
	watchBots(existing)
else
	local waiting: RBXScriptConnection? = nil
	waiting = ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == "PartyBots" and not botFolder then
			if waiting then
				waiting:Disconnect()
			end
			watchBots(child)
		end
	end)
end

Players.PlayerAdded:Connect(changed)
Players.PlayerRemoving:Connect(function(player)
	-- After the player is gone from Players:GetPlayers(), so lists refreshed on Changed drop them.
	task.defer(function()
		entries[player] = nil
		changed()
	end)
end)

return Participants

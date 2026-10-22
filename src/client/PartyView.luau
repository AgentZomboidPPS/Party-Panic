-- Parties as this device sees them (owner: "Also make the party system insane. I want it to look
-- super epic."): who's in which party (the server's PP_Party and PP_PartySeat on each player) and
-- each party's look and streak (the GameState attribute "Parties": Services/PartyService), for the
-- PARTY window and invite card (Controllers/PartyController), the squad bar, the party-up moment and
-- the SQUAD card (Controllers/SquadController), and the rings, crests and beams in the world
-- (Controllers/PartyWorldController).
--
--   PartyView.Start()           once per controller that uses it (only the first one wires it up)
--   PartyView.Changed           fires (at most once a frame) when anyone's party, a party's look or
--                               streak, or who's here changes
--   PartyView.Mine()            the local player's party id, or nil
--   PartyView.Members(id)       a party's players, its leader first
--   PartyView.Info(id)          its look: Name, Color (a Color3), Emblem (an icon), Streak, and the
--                               picks' names and indices
-- Bots are never in parties: only Players are read.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameState = require(Shared.GameState)
local PartyIdentity = require(Shared.Logic.PartyIdentity)
local Signal = require(Shared.Signal)

local PartyView = {}

export type Info = {
	Id: number,
	Name: string,
	Color: Color3,
	ColorIndex: number,
	ColorName: string,
	Emblem: string,
	EmblemIndex: number,
	EmblemName: string,
	Streak: number,
}

PartyView.Changed = Signal.new()

local started = false
local queued = false
local watched: { [any]: boolean } = {}
local looks: { [string]: any } = {}

local function fire()
	if queued then
		return
	end
	queued = true
	task.defer(function()
		queued = false
		PartyView.Changed:Fire()
	end)
end

function PartyView.PartyOf(player: any): number?
	local id = player:GetAttribute("PP_Party")
	return if type(id) == "number" then id else nil
end

-- Their place in their party (1 leads); math.huge when they're on their own.
function PartyView.SeatOf(player: any): number
	local seat = player:GetAttribute("PP_PartySeat")
	return if type(seat) == "number" then seat else math.huge
end

function PartyView.IsLeader(player: any): boolean
	return PartyView.PartyOf(player) ~= nil and PartyView.SeatOf(player) == 1
end

function PartyView.Mine(): number?
	return PartyView.PartyOf(Players.LocalPlayer)
end

-- The people in a party, its leader first (none for nil).
function PartyView.Members(id: number?): { Player }
	local members = {}
	if id == nil then
		return members
	end
	for _, player in Players:GetPlayers() do
		if PartyView.PartyOf(player) == id then
			table.insert(members, player)
		end
	end
	table.sort(members, function(a, b)
		return PartyView.SeatOf(a) < PartyView.SeatOf(b)
	end)
	return members
end

local function color(index: number): Color3
	local rgb = PartyIdentity.Colors[index].Rgb
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- A party's look and streak, as the server last said (a plain look until it has).
function PartyView.Info(id: number?): Info
	local entry = if id then looks[tostring(id)] else nil
	local colorIndex = PartyIdentity.Index(entry and entry.Color, #PartyIdentity.Colors) or 2
	local emblemIndex = PartyIdentity.Index(entry and entry.Emblem, #PartyIdentity.Emblems) or 1
	local name = entry and entry.Name
	local streak = entry and entry.Streak
	return {
		Id = id or 0,
		Name = if type(name) == "string" and name ~= "" then name else "PARTY",
		Color = color(colorIndex),
		ColorIndex = colorIndex,
		ColorName = PartyIdentity.Colors[colorIndex].Name,
		Emblem = PartyIdentity.Emblems[emblemIndex].Icon,
		EmblemIndex = emblemIndex,
		EmblemName = PartyIdentity.Emblems[emblemIndex].Name,
		Streak = if type(streak) == "number" and streak == streak then math.max(0, math.floor(streak)) else 0,
	}
end

-- Every party's colour, as a Color3, by index (the leader's picker).
function PartyView.ColorAt(index: number): Color3
	return color(index)
end

local function readLooks()
	local decoded = GameState.GetJSON("Parties")
	looks = if type(decoded) == "table" then decoded else {}
	fire()
end

local function watch(player: Player)
	if watched[player] then
		return
	end
	watched[player] = true
	player:GetAttributeChangedSignal("PP_Party"):Connect(fire)
	player:GetAttributeChangedSignal("PP_PartySeat"):Connect(fire)
end

function PartyView.Start()
	if started then
		return
	end
	started = true
	GameState.Changed("Parties", readLooks)
	readLooks()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(function(player)
		watch(player)
		fire()
	end)
	Players.PlayerRemoving:Connect(function(player)
		watched[player] = nil
		fire()
	end)
end

return PartyView

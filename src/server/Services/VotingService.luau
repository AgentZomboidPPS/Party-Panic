-- Builds valid options, records one vote per player, resolves ties and broadcasts live counts
-- (design doc §6 and §14 "VotingService"). Players vote from the UI or by stepping on a portal pad.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GameDefinitions = require(Shared.GameDefinitions)
local GamePicker = require(Shared.Logic.GamePicker)
local GameState = require(Shared.GameState)
local Remotes = require(Shared.Remotes)
local VoteLogic = require(Shared.Logic.VoteLogic)

local BotRegistry = require(script.Parent.BotRegistry)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local QuestService = require(script.Parent.QuestService)
local RateLimiter = require(script.Parent.RateLimiter)
local Telemetry = require(script.Parent.Telemetry)

local VotingService = {}

export type VoteOption = { Id: string, Mystery: boolean }

local rng = Random.new()
local active = false
local options: { VoteOption } = {}
local votes: { [Player]: number } = {}
local votedThisRound: { [Player]: boolean } = {}
local pads: { [number]: BasePart } = {}

local function publishCounts()
	local counts = VoteLogic.Tally(votes, #options)
	GameState.SetJSON("VoteCounts", counts)
end

function VotingService.BuildOptions(playerCount: number, recent: { string }, ignoreLimits: boolean): { VoteOption }
	local pool = {}
	for _, definition in GameDefinitions.List do
		table.insert(pool, {
			Id = definition.Id,
			Category = definition.Category,
			MinPlayers = definition.MinPlayers,
			Weight = definition.Weight,
			IsNew = definition.IsNew,
			Enabled = definition.Enabled,
		})
	end
	local ids = GamePicker.Pick(pool, {
		PlayerCount = playerCount,
		Count = Config.Session.VoteChoices,
		Recent = recent,
		RecentMemory = Config.Session.RecentGameMemory,
		RandomFloat = function()
			return rng:NextNumber()
		end,
		IgnorePlayerLimits = ignoreLimits,
	})
	local result: { VoteOption } = {}
	for _, id in ids do
		table.insert(result, { Id = id, Mystery = false })
	end
	-- §6 Mystery option: occasionally hide one card until it wins. Never when it is the only choice.
	if #result >= 3 and rng:NextNumber() < Config.Session.MysteryOptionChance then
		result[rng:NextInteger(1, #result)].Mystery = true
	end
	return result
end

function VotingService.Begin(newOptions: { VoteOption })
	options = newOptions
	votes = {}
	votedThisRound = {}
	active = true
	for _, player in Players:GetPlayers() do
		player:SetAttribute("PP_Vote", 0)
	end
	for _, bot in BotRegistry.List() do
		bot:SetAttribute("PP_Vote", 0)
	end
	GameState.SetJSON("VoteOptions", options)
	publishCounts()
	Notifier.Sound(nil, "VoteOpen")
end

function VotingService.IsActive(): boolean
	return active
end

function VotingService.Cast(player: Player, index: any): boolean
	if not active or not player.Parent then
		return false
	end
	if not VoteLogic.IsValidChoice(index, #options) then
		return false
	end
	if BotRegistry.IsBot(player) then
		-- Bots count like anyone else, without stats, quests or sounds.
		if votes[player] ~= index then
			votes[player] = index
			player:SetAttribute("PP_Vote", index)
			publishCounts()
		end
		return true
	end
	if not DataService.Get(player) then
		return false -- profile still loading
	end
	if votes[player] == index then
		return true
	end
	local changed = votes[player] ~= nil
	votes[player] = index
	player:SetAttribute("PP_Vote", index)
	publishCounts()
	Notifier.Sound({ player }, "VoteClick")

	if not votedThisRound[player] then
		votedThisRound[player] = true
		local profile = DataService.Get(player)
		if profile then
			profile.Data.Stats.Votes += 1
		end
		QuestService.Track(player, "Voted")
	end
	Telemetry.PlayerEvent(player, if changed then "VoteChanged" else "VoteCast", index)
	return true
end

-- Ends voting and returns the winning option (ties broken randomly between tied options).
function VotingService.End(): (VoteOption?, { number }, boolean)
	active = false
	-- Ignore votes from players who left during the vote.
	for player in votes do
		if not player.Parent then
			votes[player] = nil
		end
	end
	local counts = VoteLogic.Tally(votes, #options)
	GameState.SetJSON("VoteCounts", counts)
	if #options == 0 then
		return nil, counts, false
	end
	local winnerIndex, wasTie = VoteLogic.ResolveWinner(counts, function(count)
		return rng:NextInteger(1, count)
	end)
	if wasTie then
		Telemetry.ServerEvent("TieResolved", { winner = options[winnerIndex].Id })
	end
	return options[winnerIndex], counts, wasTie
end

function VotingService.Options(): { VoteOption }
	return options
end

-- Where the portal pad for option `index` is (bots walk there to vote).
function VotingService.PadPosition(index: number): Vector3?
	local pad = pads[index]
	return if pad then pad.Position else nil
end

-- Lets a physical portal pad cast a vote when a player steps on it.
function VotingService.BindPad(pad: BasePart, index: number)
	local lastTouch: { [Player]: number } = {}
	pads[index] = pad
	pad.Touched:Connect(function(hit)
		if not active then
			return
		end
		local character = hit.Parent
		local player = character and (Players:GetPlayerFromCharacter(character) or BotRegistry.FromCharacter(character))
		if not player then
			return
		end
		local now = os.clock()
		if now - (lastTouch[player] or 0) < 0.5 then
			return
		end
		lastTouch[player] = now
		VotingService.Cast(player, index)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTouch[player] = nil
	end)
end

function VotingService.Init()
	local limit = Config.RateLimits.CastVote
	local limiter = RateLimiter.new(limit[1], limit[2])
	Remotes.Get("CastVote").OnServerEvent:Connect(function(player, index)
		if limiter:Check(player) then
			VotingService.Cast(player, index)
		end
	end)
	local function forget(player: any)
		if votes[player] then
			votes[player] = nil
			if active then
				publishCounts()
			end
		end
		votedThisRound[player] = nil
	end
	Players.PlayerRemoving:Connect(forget)
	BotRegistry.Removed:Connect(forget)
end

return VotingService

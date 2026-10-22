-- Replicated round state. The server writes attributes on ReplicatedStorage.GameState;
-- clients only read them, so the server stays the single source of truth (design doc §14).
--
-- Attributes:
--   Phase         "Waiting" | "Intermission" | "Voting" | "Preparing" | "InRound" | "Results" | "Cleanup"
--   PhaseEndsAt   server time (workspace:GetServerTimeNow()) when the phase ends, 0 if open-ended
--   RoundId       increments every round
--   GameId        selected mini-game id ("" when none)
--   Message       short banner text for the current phase
--   Status        mini-game status line, e.g. "Survivors: 4"
--   VoteOptions   JSON list of { Id, Mystery }
--   VoteCounts    JSON list of numbers
--   TeamScores    JSON map of team name -> score ("" when not a team game)
--   Champions     JSON list of the last round's top three display names
--   Cup           JSON of the Party Cup in progress ("" before the first round): see CupService
--   Event         JSON of the limited-time event on now ("" when none): see EventService
--   HallOfFame    JSON of last week's top three and this week's leaders ("" until loaded): see
--                 LeaderboardService
--   ReplayVote    JSON { Open, Game, Yes, No, Voters (UserIds), Need, Capped }: the results card's
--                 PLAY AGAIN vote (Services/ReplayService); each voter's answer is their PP_Replay
--   Replay        the game a PLAY AGAIN vote chose to play again straight after this round's results,
--                 from the end of those results until the replay's own results ("" if none)
--   Parties       JSON of every party's look and streak, by party id (a player's PP_Party):
--                 { Name, Color, Emblem, Streak } ("" with no parties): see Services/PartyService

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameState = {}

local cachedFolder: Folder? = nil

function GameState.Folder(): Folder
	if cachedFolder then
		return cachedFolder
	end
	local folder: Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("GameState")
		if existing then
			folder = existing :: Folder
		else
			local created = Instance.new("Folder")
			created.Name = "GameState"
			created:SetAttribute("Phase", "Waiting")
			created:SetAttribute("PhaseEndsAt", 0)
			created:SetAttribute("RoundId", 0)
			created:SetAttribute("GameId", "")
			created:SetAttribute("Message", "")
			created:SetAttribute("Status", "")
			created:SetAttribute("VoteOptions", "[]")
			created:SetAttribute("VoteCounts", "[]")
			created:SetAttribute("TeamScores", "")
			created:SetAttribute("Champions", "[]")
			created:SetAttribute("Cup", "")
			created:SetAttribute("Event", "")
			created:SetAttribute("HallOfFame", "")
			created:SetAttribute("ReplayVote", "")
			created:SetAttribute("Replay", "")
			created:SetAttribute("Parties", "")
			created.Parent = ReplicatedStorage
			folder = created
		end
	else
		folder = ReplicatedStorage:WaitForChild("GameState") :: Folder
	end
	cachedFolder = folder
	return folder
end

function GameState.Get(key: string): any
	return GameState.Folder():GetAttribute(key)
end

function GameState.Set(key: string, value: any)
	assert(RunService:IsServer(), "GameState can only be written by the server")
	GameState.Folder():SetAttribute(key, value)
end

function GameState.SetJSON(key: string, value: any)
	GameState.Set(key, HttpService:JSONEncode(value))
end

function GameState.GetJSON(key: string): any
	local raw = GameState.Get(key)
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok then decoded else nil
end

function GameState.Changed(key: string, callback: (value: any) -> ()): RBXScriptConnection
	return GameState.Folder():GetAttributeChangedSignal(key):Connect(function()
		callback(GameState.Get(key))
	end)
end

function GameState.TimeLeft(): number
	local endsAt = GameState.Get("PhaseEndsAt") or 0
	if endsAt <= 0 then
		return 0
	end
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

return GameState

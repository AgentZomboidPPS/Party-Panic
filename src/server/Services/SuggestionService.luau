-- The suggestion box (owner: "Can we add a suggestion box?"): a player sends what it's about (a new
-- game, something to make better, a bug, anything else) and a few lines of their own words
-- (Controllers/SuggestionController). The rules are Shared/Logic/Suggestions.
--
-- Each one goes into the PP_Suggestions data store of its own (never the profile store), in the key
-- for its UTC hour, with when, who (UserId and name), the kind, the words and the place version.
-- Nobody else in the game ever sees them: tools/checks/suggestions.py reads them back for the owner.
-- The sender's window hears back on the same remote (ok, words for them): a thank-you once it's kept,
-- or why not (too soon, too many, the write failed: try again), and keeps their words until then.
--
-- Not a stream: Config.RateLimits.Suggest caps how often the remote is heard at all, and on top of
-- that one suggestion a minute, SESSION_MOST a server session. Bots never send any.
--
-- Test runs (workspace PP_Harness) write to PP_Suggestions_Test instead (suggestions.py --test reads
-- it); Studio keeps nothing.
--
-- The owner's inbox (owner: "did we ever add in a way for me the dev to read the suggestion box?"):
-- the game's owner (its creator) sends "Inbox" on the same remote and hears back ("Inbox", the last
-- INBOX_DAYS days' suggestions, newest first). Nobody else gets anything back.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Suggestions = require(Shared.Logic.Suggestions)

local BotRegistry = require(script.Parent.BotRegistry)
local RateLimiter = require(script.Parent.RateLimiter)
local Telemetry = require(script.Parent.Telemetry)

local SuggestionService = {}

local STORE = "PP_Suggestions"
local TEST_STORE = "PP_Suggestions_Test"
local GAP = 60 -- seconds between one player's suggestions
local SESSION_MOST = 6 -- suggestions one player can send in one server session

local INBOX_DAYS = 7 -- how far back the owner's inbox reads
local INBOX_MOST = 150 -- suggestions it sends at most
local INBOX_GAP = 10 -- seconds between the owner's inbox reads

local lastSent: { [Player]: number } = {}
local sent: { [Player]: number } = {}
local inboxAt = 0

local function harness(): boolean
	return workspace:GetAttribute("PP_Harness") == true
end

local function store(): DataStore?
	if RunService:IsStudio() and not harness() then
		return nil
	end
	return DataStoreService:GetDataStore(if harness() then TEST_STORE else STORE)
end

-- Why a suggestion from `player` can't go in now ("" if it can).
local function refusal(player: Player): string
	local last = lastSent[player]
	if last and os.clock() - last < GAP then
		return `One idea a minute, please! Try again in {math.ceil(GAP - (os.clock() - last))}s.`
	elseif (sent[player] or 0) >= SESSION_MOST then
		return "Thanks for all the ideas! That's plenty for one visit."
	end
	return ""
end

-- Keeps a suggestion from `player`. Returns whether it was kept, and the words for them.
function SuggestionService.Submit(player: Player, kind: any, text: any): (boolean, string)
	if not player.Parent or BotRegistry.IsBot(player) then
		return false, "Only players can send ideas."
	end
	local words = Suggestions.Clean(text)
	if not Suggestions.IsKind(kind) or not words then
		return false, `Tell us a bit more ({Suggestions.MIN_LENGTH} to {Suggestions.MAX_LENGTH} letters).`
	end
	local why = refusal(player)
	if why ~= "" then
		return false, why
	end
	lastSent[player] = os.clock()
	sent[player] = (sent[player] or 0) + 1
	local entry: Suggestions.Entry = {
		T = os.time(),
		U = player.UserId,
		N = player.Name,
		K = kind,
		S = words :: string,
		V = game.PlaceVersion,
	}
	local target = store()
	local ok, err = true, nil
	local kept = true
	if target then
		ok, err = pcall(function()
			target:UpdateAsync(Suggestions.Key(entry.T), function(old)
				local list, added = Suggestions.Append(old, entry)
				kept = added
				return list
			end)
		end)
	end
	if not ok then
		lastSent[player] = nil -- (it didn't count: they can try again straight away)
		sent[player] -= 1
		Telemetry.Error("Suggestions", tostring(err))
		return false, "Your idea didn't send. Try again in a moment!"
	end
	if not kept then
		Telemetry.Error("Suggestions", `{entry.T}: a full hour`)
	end
	Telemetry.PlayerEvent(player, "Suggestion", Suggestions.Length(entry.S), kind)
	return true, "Thanks! Your idea is in the box. We read every one!"
end

-- Whether `player` made the game (only they may read the box in game).
function SuggestionService.IsOwner(player: Player): boolean
	return game.CreatorType == Enum.CreatorType.User and game.CreatorId ~= 0 and player.UserId == game.CreatorId
end

-- The last INBOX_DAYS days' suggestions, newest first (at most INBOX_MOST), and whether it could read.
-- Listing is the data store's scarcest request, so it lists by month (one or two calls: keys are
-- "YYYY-MM-DDTHH") and then reads the newest hours that have any, until it has enough.
function SuggestionService.Inbox(): ({ Suggestions.Entry }, boolean)
	local target = store()
	if not target then
		return {}, true
	end
	local now = os.time()
	local oldest = Suggestions.Key(now - INBOX_DAYS * 86400)
	local months = { os.date("!%Y-%m", now) :: string }
	local earlier = os.date("!%Y-%m", now - INBOX_DAYS * 86400) :: string
	if earlier ~= months[1] then
		table.insert(months, earlier)
	end
	local entries: { Suggestions.Entry } = {}
	local ok = pcall(function()
		local keys = {}
		for _, month in months do
			local pages = target:ListKeysAsync(month, 100)
			while true do
				for _, key in pages:GetCurrentPage() do
					if key.KeyName >= oldest then
						table.insert(keys, key.KeyName)
					end
				end
				if pages.IsFinished then
					break
				end
				pages:AdvanceToNextPageAsync()
			end
		end
		table.sort(keys, function(a, b)
			return a > b
		end)
		for _, key in keys do
			if #entries >= INBOX_MOST then
				break
			end
			local list = target:GetAsync(key)
			for _, entry in if type(list) == "table" then list else {} do
				if type(entry) == "table" then
					table.insert(entries, entry)
				end
			end
		end
	end)
	table.sort(entries, function(a, b)
		return (a.T or 0) > (b.T or 0)
	end)
	while #entries > INBOX_MOST do
		table.remove(entries)
	end
	return entries, ok
end

function SuggestionService.Init()
	local limit = Config.RateLimits.Suggest
	local limiter = RateLimiter.new(limit[1], limit[2])
	local remote = Remotes.Get("Suggest")
	remote.OnServerEvent:Connect(function(player, kind, text)
		if not limiter:Check(player) then
			return
		elseif kind == "Inbox" then
			if SuggestionService.IsOwner(player) and os.clock() - inboxAt >= INBOX_GAP then
				inboxAt = os.clock()
				local entries, ok = SuggestionService.Inbox()
				remote:FireClient(player, "Inbox", entries, ok)
			end
			return
		end
		local ok, words = SuggestionService.Submit(player, kind, text)
		remote:FireClient(player, ok, words)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSent[player] = nil
		sent[player] = nil
	end)
end

return SuggestionService

-- Every RemoteEvent the game uses. The server creates them; clients wait for them.
-- Client -> server remotes are validated and rate limited on the server (design doc §14, §15).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	-- client -> server
	"CastVote", -- (optionIndex: number)
	"ReplayVote", -- (again: boolean) PLAY AGAIN or NO THANKS on the results card; see Services/ReplayService
	"ShopPurchase", -- (itemId: string)
	"ShopEquip", -- (slot: string, itemId: string?)
	"UseEmote", -- (itemId: string)
	"ClaimDaily", -- ()
	"TutorialDone", -- ()
	"SetSetting", -- (key: string, value: any)
	"PromptVip", -- ()
	"MiniGameAction", -- (action: string, ...) a mini-game control (pump, push, shoot...); see RoundContext:OnAction
	"ClientReport", -- (report: table) which uploaded meshes this device couldn't load; see Services/ClientReports
	"SetSitOut", -- (sitOut: boolean) sit out the next rounds, or play again; see Services/SitOutService
	"SkeeBall", -- both ways: the lobby arcade's Skee-Ball games; see Services/SkeeBallService
	"EventAction", -- (action: string, ...) the limited-time event (claim a reward...); see Services/EventService
	"Party", -- both ways: invites, JOIN / NO and LEAVE for parties; see Services/PartyService
	"RateGame", -- (choice: "Up" | "Down" | "None") 👍 / 👎 on the results card; see Services/RatingService
	"Funnel", -- (step: string, detail: string?) a funnel step only the screen sees; see Services/FunnelService
	-- server -> client
	"ProfileData", -- (snapshot)
	"Notify", -- (text, kind?, duration?, topic?) a toast; topic "Round" is a callout about the round (Services/Notifier)
	"RoundResults", -- (results payload)
	"PlayEffect", -- (effectName, position, colors?)
	"Knockback", -- (velocity: Vector3, stunTime: number)
	"PlaySound", -- (soundName)
	"MiniGameEvent", -- (event: string, ...) mini-game specific cue for the client half of a mode
	"Celebrate", -- (payload) a level up or career milestone to celebrate; see Services/ProgressionService
	"LevelPop", -- (character: Model, level: number) the "Lv 10!" that pops over a player's head
	"MedalEarned", -- (medalId: string, earlier: boolean?) a new medal for the collection; see Services/MedalService
	"GoldPass", -- both ways: "Prompt" (buy the GOLD PASS), "Unlocked" (what it gave); see Services/GoldPassService
	"Crate", -- both ways: open crates, buy and gift keys; the openings everyone sees; see Services/CrateService
	"Suggest", -- both ways: (kind, text) the suggestion box, and (ok, words) back; see Services/SuggestionService
}

local Remotes = {}

local cachedFolder: Folder? = nil

local function getFolder(): Folder
	if cachedFolder then
		return cachedFolder
	end
	local folder: Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if existing then
			folder = existing :: Folder
		else
			local created = Instance.new("Folder")
			created.Name = "Remotes"
			for _, name in NAMES do
				local remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = created
			end
			created.Parent = ReplicatedStorage
			folder = created
		end
	else
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	cachedFolder = folder
	return folder
end

function Remotes.Get(name: string): RemoteEvent
	assert(table.find(NAMES, name), `Unknown remote '{name}'`)
	return getFolder():WaitForChild(name) :: RemoteEvent
end

return Remotes

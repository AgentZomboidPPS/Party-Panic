-- Every RemoteEvent the game uses. The server creates them; clients wait for them.
-- Client -> server remotes are validated and rate limited on the server (design doc §14, §15).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	-- client -> server
	"CastVote", -- (optionIndex: number)
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
	-- server -> client
	"ProfileData", -- (snapshot)
	"Notify", -- (text, kind?, duration?)
	"RoundResults", -- (results payload)
	"PlayEffect", -- (effectName, position, colors?)
	"Knockback", -- (velocity: Vector3, stunTime: number)
	"PlaySound", -- (soundName)
	"MiniGameEvent", -- (event: string, ...) mini-game specific cue for the client half of a mode
	"Celebrate", -- (payload) a level up or career milestone to celebrate; see Services/ProgressionService
	"LevelPop", -- (character: Model, level: number) the "Lv 10!" that pops over a player's head
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

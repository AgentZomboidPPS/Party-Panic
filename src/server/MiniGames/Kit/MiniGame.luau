-- Base for every mini-game. A mode only has to implement :Prepare() (build the arena, place players)
-- and usually :Start() (begin hazards / scoring). Everything else has a sensible default.
--
--   local MiniGame = require(script.Parent.Kit.MiniGame)
--   local MyGame = MiniGame.Define("MyGame", { Results = "Score" })
--
--   function MyGame:Prepare()  -- build the arena under self.context.Arena and spawn players
--   function MyGame:Start()    -- start loops with self.context:Loop / :Heartbeat / :Delay
--
-- Contract the round manager calls (design doc §14 "Suggested mini-game module contract"):
--   Class.CanStart(playerCount, ignoreLimits) -> boolean
--   Class.new(context)
--   instance:Prepare()  instance:Start()  instance:Stop(reason)  instance:GetResults()  instance:Cleanup()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameDefinitions = require(ReplicatedStorage.Shared.GameDefinitions)

local MiniGame = {}

export type Options = {
	-- How :GetResults() ranks players unless the mode overrides it:
	--   "Survival" (default) survivors share 1st, others by time lasted
	--   "Score"    highest context score wins
	--   "Team"     best team score wins
	Results: string?,
	ScoreUnit: string?, -- label used by "Score" results, e.g. "coins"
}

function MiniGame.Define(id: string, options: Options?)
	local opts = options or {}
	local class = {}
	class.__index = class
	class.Id = id
	class.ResultsStyle = opts.Results or "Survival"
	class.ScoreUnit = opts.ScoreUnit

	function class.CanStart(playerCount: number, ignoreLimits: boolean?): boolean
		local definition = GameDefinitions.Get(id)
		if not definition or definition.Enabled == false then
			return false
		end
		return ignoreLimits == true or playerCount >= definition.MinPlayers
	end

	function class.new(context)
		local self = setmetatable({ context = context }, class)
		return self
	end

	function class.Prepare(_self)
		error(`{id} must implement :Prepare()`)
	end

	function class.Start(_self) end

	function class.Stop(_self, _reason: string?) end

	function class.GetResults(self)
		local context = self.context
		if class.ResultsStyle == "Score" then
			return context:ScoreResults(class.ScoreUnit)
		elseif class.ResultsStyle == "Team" then
			return context:TeamResults()
		end
		return context:SurvivalResults()
	end

	function class.Cleanup(_self) end

	return class
end

-- Methods every mode must expose for the round manager.
MiniGame.RequiredMethods = { "CanStart", "new", "Prepare", "Start", "Stop", "GetResults", "Cleanup" }

return MiniGame

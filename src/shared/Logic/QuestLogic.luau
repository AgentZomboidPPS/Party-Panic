--!strict
-- Daily / weekly quest rotation and progress (design doc §9 "Daily and weekly quests").
-- Leaf module: no requires, no Roblox APIs. Definitions are passed in by the caller.

local QuestLogic = {}

export type QuestDef = {
	Id: string,
	Period: string, -- "Daily" | "Weekly"
	Text: string,
	Event: string,
	Target: number,
	Unique: boolean?, -- progress counts distinct keys (e.g. different emotes)
	RewardCoins: number,
	RewardXP: number,
}

export type ActiveQuest = {
	Id: string,
	Progress: number,
	Done: boolean,
	Seen: { [string]: boolean }?,
}

export type PeriodState = {
	Number: number,
	Active: { ActiveQuest },
}

export type PickIndex = (count: number) -> number

-- Re-rolls the quest list when the period (day or week number) has changed.
-- Returns true when a new set of quests was rolled.
function QuestLogic.Refresh(
	state: PeriodState,
	defs: { QuestDef },
	period: string,
	periodNumber: number,
	count: number,
	pickIndex: PickIndex
): boolean
	if state.Number == periodNumber and #state.Active > 0 then
		return false
	end

	local candidates: { QuestDef } = {}
	for _, def in defs do
		if def.Period == period then
			table.insert(candidates, def)
		end
	end

	local active: { ActiveQuest } = {}
	for _ = 1, math.min(count, #candidates) do
		local index = math.clamp(math.floor(pickIndex(#candidates)), 1, #candidates)
		local def = table.remove(candidates, index) :: QuestDef
		table.insert(active, { Id = def.Id, Progress = 0, Done = false, Seen = if def.Unique then {} else nil })
	end

	state.Number = periodNumber
	state.Active = active
	return true
end

-- Applies a gameplay event to the active quests. Returns the definitions completed by this event.
function QuestLogic.ApplyEvent(
	state: PeriodState,
	defsById: { [string]: QuestDef },
	eventName: string,
	amount: number?,
	uniqueKey: string?
): { QuestDef }
	local completed: { QuestDef } = {}
	local step = math.max(0, math.floor(amount or 1))

	for _, quest in state.Active do
		local def = defsById[quest.Id]
		if not def or quest.Done or def.Event ~= eventName then
			continue
		end

		if def.Unique then
			if not uniqueKey then
				continue
			end
			local seen = quest.Seen or {}
			quest.Seen = seen
			if seen[uniqueKey] then
				continue
			end
			seen[uniqueKey] = true
			quest.Progress = math.min(def.Target, quest.Progress + 1)
		else
			quest.Progress = math.min(def.Target, quest.Progress + step)
		end

		if quest.Progress >= def.Target then
			quest.Done = true
			table.insert(completed, def)
		end
	end

	return completed
end

return QuestLogic

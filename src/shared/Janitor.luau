-- Tracks connections, instances, threads and callbacks so they can be released together.
-- Cleanup is idempotent: calling it twice is safe (design doc §14 "idempotent cleanup").

export type Janitor = {
	Add: <T>(self: Janitor, item: T) -> T,
	Cleanup: (self: Janitor) -> (),
	Destroy: (self: Janitor) -> (),
	_items: { any },
}

local Janitor = {}
Janitor.__index = Janitor

function Janitor.new(): Janitor
	return setmetatable({ _items = {} }, Janitor) :: any
end

function Janitor:Add<T>(item: T): T
	table.insert(self._items, item)
	return item
end

local function release(item: any)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" and item ~= coroutine.running() then
			pcall(task.cancel, item)
		end
	elseif kind == "function" then
		local ok, err = pcall(item)
		if not ok then
			warn("[Janitor] cleanup callback failed:", err)
		end
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		end
	end
end

function Janitor:Cleanup()
	local items = self._items
	self._items = {}
	for index = #items, 1, -1 do
		release(items[index])
	end
end

Janitor.Destroy = Janitor.Cleanup

return Janitor

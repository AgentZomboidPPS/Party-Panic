--!strict
-- Small table helpers used by the data layer.
-- Leaf module: no requires, no Roblox APIs.

local TableUtil = {}

function TableUtil.DeepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value :: any do
		copy[TableUtil.DeepCopy(key)] = TableUtil.DeepCopy(item)
	end
	return (copy :: any) :: T
end

-- Fills keys that exist in `template` but are missing from `target` (recursively).
-- Existing values are never overwritten, so saved progress always wins over defaults.
function TableUtil.Reconcile(target: { [any]: any }, template: { [any]: any }): { [any]: any }
	for key, default in template do
		local current = target[key]
		if current == nil then
			target[key] = TableUtil.DeepCopy(default)
		elseif type(current) == "table" and type(default) == "table" then
			TableUtil.Reconcile(current, default)
		end
	end
	return target
end

function TableUtil.Count(dictionary: { [any]: any }): number
	local count = 0
	for _ in dictionary do
		count += 1
	end
	return count
end

return TableUtil

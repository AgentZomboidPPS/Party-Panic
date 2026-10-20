-- Minimal test harness for Lune. Run all tests with: lune run tests/run
local TestKit = {}

local results = { passed = 0, failed = 0, failures = {} }

local function describe(value: any): string
	if type(value) == "table" then
		local parts = {}
		for key, item in value do
			table.insert(parts, `{tostring(key)}={describe(item)}`)
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

function TestKit.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, `{name}\n    {tostring(err)}`)
	end
end

function TestKit.expectEqual(actual: any, expected: any, message: string?)
	if not deepEqual(actual, expected) then
		error(`{message or "values differ"}: expected {describe(expected)}, got {describe(actual)}`, 2)
	end
end

function TestKit.expectTrue(value: any, message: string?)
	if not value then
		error(message or "expected value to be truthy", 2)
	end
end

-- Deterministic pseudo random generator (LCG) so tests are reproducible.
function TestKit.seeded(seed: number)
	local state = seed
	local function nextFloat(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	return {
		float = nextFloat,
		index = function(count: number): number
			return math.floor(nextFloat() * count) + 1
		end,
	}
end

function TestKit.report(): boolean
	for _, failure in results.failures do
		print(`FAIL {failure}`)
	end
	print(`{results.passed} passed, {results.failed} failed`)
	return results.failed == 0
end

return TestKit

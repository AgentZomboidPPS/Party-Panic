-- Runs every *.spec.luau file in this folder: lune run tests/run
local fs = require("@lune/fs")
local process = require("@lune/process")

local TestKit = require("./TestKit")

local specs = {}
for _, name in fs.readDir("tests") do
	if string.match(name, "%.spec%.luau$") then
		table.insert(specs, name)
	end
end
table.sort(specs)

for _, name in specs do
	print(`• {name}`)
	require(`./{string.gsub(name, "%.luau$", "")}`)
end

if not TestKit.report() then
	process.exit(1)
end

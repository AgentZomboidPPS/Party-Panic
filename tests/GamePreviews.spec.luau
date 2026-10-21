-- Checks the portal previews (Shared/GamePreviews, made by tools/preview/make_preview.py): each is
-- for a real game, its sheet fits in Roblox's 1024x1024 image limit with every frame on it, and the
-- Luau file says the same as the record the tool writes it from.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local TestKit = require("./TestKit")

local test, expectTrue, expectEqual = TestKit.test, TestKit.expectTrue, TestKit.expectEqual

local definitions = fs.readFile("src/shared/GameDefinitions.luau")
local defined = {}
for id in string.gmatch(definitions, '\n\t\tId = "(%w+)"') do
	defined[id] = true
end

local source = fs.readFile("src/shared/GamePreviews.luau")
local previews = {}
for id, body in string.gmatch(source, "\n\t(%w+) = (%b{})") do
	previews[id] = {
		Image = string.match(body, 'Image = "([^"]+)"'),
		Frames = tonumber(string.match(body, "Frames = (%d+)")),
		Columns = tonumber(string.match(body, "Columns = (%d+)")),
		Width = tonumber(string.match(body, "FrameSize = Vector2%.new%((%d+),")),
		Height = tonumber(string.match(body, "FrameSize = Vector2%.new%(%d+, (%d+)%)")),
		Fps = tonumber(string.match(body, "Fps = (%d+)")),
	}
end
local record = if fs.isFile("assets/previews/previews.json")
	then serde.decode("json", fs.readFile("assets/previews/previews.json"))
	else {}

test("every preview is for a game, with a usable sheet", function()
	for id, preview in previews do
		expectTrue(defined[id], `GamePreviews has {id}, which isn't in GameDefinitions`)
		expectTrue(preview.Image and string.match(preview.Image, "^rbxassetid://%d+$"), `{id}: Image is an asset id`)
		local frames, columns = preview.Frames or 0, preview.Columns or 0
		expectTrue(frames > 0 and columns > 0 and (preview.Fps or 0) > 0, `{id}: frames, columns and fps`)
		local rows = math.ceil(frames / math.max(columns, 1))
		expectTrue(
			(preview.Width or 0) * columns <= 1024 and (preview.Height or 0) * rows <= 1024,
			`{id}: the sheet must fit in 1024x1024`
		)
	end
end)

test("GamePreviews.luau matches assets/previews/previews.json", function()
	for id, entry in record do
		local preview = previews[id]
		expectTrue(preview ~= nil, `{id} is recorded but not in GamePreviews.luau (run make_preview.py --write-luau)`)
		if preview then
			expectEqual(preview.Image, `rbxassetid://{entry.image}`, `{id}: image`)
			expectEqual(preview.Frames, entry.frames, `{id}: frames`)
			expectEqual(preview.Width, entry.width, `{id}: frame width`)
		end
	end
	for id in previews do
		expectTrue(record[id] ~= nil, `{id} is in GamePreviews.luau but not recorded`)
	end
end)

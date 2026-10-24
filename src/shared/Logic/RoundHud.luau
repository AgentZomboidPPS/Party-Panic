-- What the round's HUD shows where room is tight (owner: "During the mini games, any way we can save
-- UI space so they can see more of the game at one time?"). Pure, so tests can check it with Lune.
--
--   * SplitStatus: the "players left" part of a mode's status line ("Players left: 6", "Survivors:
--     9", "On the summit: 4", "5 tanks left", "🏃 3 runners left") goes into a small pill in the
--     round banner as an icon and the number (HudController); the rest of the line stays under the
--     banner. Modes keep calling ctx:SetStatus as before: the count is read from the words they
--     already send, one "  •  "-separated part at a time.
--   * BoardPlaces: which places the phone standings strip shows (RoundController): the top three,
--     with you in the third place if you're further down.

local RoundHud = {}

-- The icon the count pill wears when the status's words have none of their own.
RoundHud.CountIcon = "👤"

local SEPARATOR = "•"

-- "Players left: 6" and the like: the words before the number, as the modes write them.
local LABELS = { "Players left", "Survivors", "On the summit", "Alive", "Still in" }

local function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

-- The count in one part of a status line, and its own icon if it has one ("🏃 3 runners left").
local function countIn(part: string): (number?, string?)
	for _, label in LABELS do
		local number = string.match(part, "^" .. label .. ":%s*(%d+)!?$")
		if number then
			return tonumber(number), nil
		end
	end
	local number = string.match(part, "^(%d+)%s+%a+%s+left!?$")
	if number then
		return tonumber(number), nil
	end
	local icon, iconNumber = string.match(part, "^([^%w%s]+)%s+(%d+)%s+%a+%s+left!?$")
	if icon and iconNumber then
		return tonumber(iconNumber), icon
	end
	return nil, nil
end

-- Splits a status line into its players-left count (with the icon to show it with) and the rest
-- of the words, which keep the line's own separators. No count: (nil, nil, the line unchanged).
function RoundHud.SplitStatus(text: string?): (number?, string?, string)
	if type(text) ~= "string" or text == "" then
		return nil, nil, ""
	end
	local parts = string.split(text, SEPARATOR)
	for index, part in parts do
		local count, icon = countIn(trim(part))
		if count then
			table.remove(parts, index)
			local rest = {}
			for _, other in parts do
				local words = trim(other)
				if words ~= "" then
					table.insert(rest, words)
				end
			end
			return count, icon or RoundHud.CountIcon, table.concat(rest, `  {SEPARATOR}  `)
		end
	end
	return nil, nil, text
end

-- The places (1 = the leader) the phone standings strip shows, in order. `count` is how many are in
-- the round, `mine` the player's own place (nil if they're not in it).
function RoundHud.BoardPlaces(count: number, mine: number?): { number }
	local places = {}
	for place = 1, math.min(3, count) do
		table.insert(places, place)
	end
	if mine and mine > 3 then
		places[3] = mine
	end
	return places
end

return RoundHud

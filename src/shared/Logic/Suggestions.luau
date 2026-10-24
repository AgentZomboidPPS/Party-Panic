--!strict
-- The suggestion box (owner: "Can we add a suggestion box?"): anyone can send the team an idea, a
-- thing to make better or a bug, a few lines of their own words. Services/SuggestionService keeps
-- them in the PP_Suggestions data store (never the profile store), one key per hour of UTC
-- ("2026-10-24T17"), and nobody else in the game ever sees them. tools/checks/suggestions.py reads
-- them back, newest first. The window is Controllers/SuggestionController (the Settings window's
-- 💡 button, and the mailbox by the quest board in the lobby).
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune.

local Suggestions = {}

-- What it's about: the window's choices, in order (Id is what's stored).
export type Kind = { Id: string, Icon: string, Label: string }
Suggestions.Kinds = {
	{ Id = "Game", Icon = "🎮", Label = "New game" },
	{ Id = "Better", Icon = "⭐", Label = "Improve" },
	{ Id = "Bug", Icon = "🐛", Label = "Bug" },
	{ Id = "Other", Icon = "💬", Label = "Other" },
} :: { Kind }

Suggestions.MIN_LENGTH = 8 -- characters: shorter isn't an idea yet ("hi", "lol")
Suggestions.MAX_LENGTH = 300
Suggestions.PER_KEY = 250 -- one hour's suggestions kept at most (a key stays small)

-- One stored suggestion: when (os.time), who (UserId and name), what it's about, the words, and the
-- place version it came from.
export type Entry = { T: number, U: number, N: string, K: string, S: string, V: number }

function Suggestions.IsKind(id: any): boolean
	for _, kind in Suggestions.Kinds do
		if kind.Id == id then
			return true
		end
	end
	return false
end

-- How many characters a string has (UTF-8 aware; a broken string counts its bytes).
function Suggestions.Length(text: string): number
	return utf8.len(text) or #text
end

-- The words as they're kept: control characters gone, runs of spaces and new lines down to one (at
-- most two new lines in a row), the ends trimmed. nil when that's not text, too short, or too long.
function Suggestions.Clean(text: any): string?
	if type(text) ~= "string" or #text > Suggestions.MAX_LENGTH * 4 then
		return nil
	end
	if not utf8.len(text) then
		return nil -- not UTF-8
	end
	local cleaned = string.gsub(text, "\r\n?", "\n")
	cleaned = string.gsub(cleaned, "[ \t]+", " ")
	cleaned = string.gsub(cleaned, "[%z\1-\8\11-\31\127]", "")
	cleaned = string.gsub(cleaned, " ?\n ?", "\n")
	cleaned = string.gsub(cleaned, "\n\n\n+", "\n\n")
	cleaned = string.match(cleaned, "^%s*(.-)%s*$") or ""
	local length = Suggestions.Length(cleaned)
	if length < Suggestions.MIN_LENGTH or length > Suggestions.MAX_LENGTH then
		return nil
	end
	return cleaned
end

-- The data store key for a moment (os.time): its UTC hour.
function Suggestions.Key(time: number): string
	return os.date("!%Y-%m-%dT%H", time) :: string
end

-- A key's list with `entry` added (the newest at the end), as the data store keeps it. A full hour
-- keeps what it has.
function Suggestions.Append(old: any, entry: Entry): ({ Entry }, boolean)
	local list = if type(old) == "table" then table.clone(old) else {}
	if #list >= Suggestions.PER_KEY then
		return list, false
	end
	table.insert(list, entry)
	return list, true
end

return Suggestions

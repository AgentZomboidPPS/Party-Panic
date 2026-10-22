--!strict
-- A party's look (owner: "Also make the party system insane. I want it to look super epic."): every
-- party gets its own name, colour and emblem, so a squad looks like one wherever it shows: the
-- PARTY window's header, the squad bar, the invite card, the party-up banner and the crests over
-- its members' heads in the lobby.
--   * The name is an adjective and a noun from two fixed, family-friendly lists ("Turbo
--     Pancakes"). Nobody types anything, so there's nothing to filter: the server picks the words
--     at random when the party is made, and the leader can roll new ones (never the same name
--     twice in a row).
--   * The colour and the emblem come from fixed sets of 8. A new party gets one of each that no
--     other party here wears (while there are some left), and the leader can pick others.
--   * Only the leader changes them, and not more often than EditCooldown: Services/PartyService
--     runs every request through Edit after its own rate limit, and publishes the result.
-- Leaf module: no requires, no Roblox APIs, so it can be unit tested under Lune (colours are RGB,
-- 0-255, like Logic/ProgressionLogic's).

local PartyIdentity = {}

-- A random whole number from 1 to `count` (the server's Random:NextInteger(1, count)).
export type Pick = (count: number) -> number

export type Identity = {
	Adjective: number, -- index into Adjectives
	Noun: number, -- index into Nouns
	Color: number, -- index into Colors
	Emblem: number, -- index into Emblems
	EditedAt: number, -- when the leader last changed it (the caller's clock), for EditCooldown
}

-- What everyone is told about a party (GameState "Parties", by party id).
export type Shown = { Name: string, Color: number, Emblem: number }

-- What other parties already wear, so a new one gets something of its own.
export type Taken = { Colors: { [number]: boolean }?, Emblems: { [number]: boolean }?, Names: { [string]: boolean }? }

-- Short, kid-friendly words (8 letters at most each, so the longest name, "Electric Raccoons",
-- still fits the crest and the squad bar), no word in both lists ("Rocket Rockets").
PartyIdentity.Adjectives = {
	"Turbo",
	"Cosmic",
	"Mighty",
	"Sparkly",
	"Funky",
	"Jolly",
	"Wobbly",
	"Mega",
	"Zippy",
	"Bouncy",
	"Fuzzy",
	"Groovy",
	"Lucky",
	"Sneaky",
	"Dizzy",
	"Giggly",
	"Speedy",
	"Brave",
	"Fancy",
	"Silly",
	"Crunchy",
	"Snazzy",
	"Electric",
	"Galactic",
	"Golden",
	"Thunder",
	"Neon",
	"Super",
	"Comfy",
	"Epic",
}

PartyIdentity.Nouns = {
	"Pancakes",
	"Penguins",
	"Llamas",
	"Dragons",
	"Noodles",
	"Tacos",
	"Waffles",
	"Unicorns",
	"Pickles",
	"Rockets",
	"Bananas",
	"Ninjas",
	"Pirates",
	"Robots",
	"Dinos",
	"Comets",
	"Cupcakes",
	"Squids",
	"Muffins",
	"Hamsters",
	"Gummies",
	"Koalas",
	"Otters",
	"Yetis",
	"Sloths",
	"Donuts",
	"Nuggets",
	"Wizards",
	"Raccoons",
	"Pandas",
}

-- The party colours: bright, and apart from each other and from the panels' purple. Names for the
-- leader's picker (colour is never the only cue: the emblem and the name go with it everywhere).
PartyIdentity.Colors = {
	{ Name = "Bubblegum", Rgb = { 255, 92, 170 } },
	{ Name = "Sky", Rgb = { 70, 190, 255 } },
	{ Name = "Lime", Rgb = { 120, 225, 80 } },
	{ Name = "Sunny", Rgb = { 255, 205, 60 } },
	{ Name = "Tangerine", Rgb = { 255, 130, 40 } },
	{ Name = "Grape", Rgb = { 165, 105, 255 } },
	{ Name = "Cherry", Rgb = { 255, 70, 90 } },
	{ Name = "Mint", Rgb = { 50, 225, 190 } },
}

-- The emblems: emoji every phone draws (Unicode 10 and older; tests/Marks.spec.luau checks the set),
-- none that the HUD already uses for something else (👑 leads, ⭐ is a friend, 🔥 the streak).
PartyIdentity.Emblems = {
	{ Name = "Unicorn", Icon = "🦄" },
	{ Name = "Dragon", Icon = "🐉" },
	{ Name = "Rocket", Icon = "🚀" },
	{ Name = "Lightning", Icon = "⚡" },
	{ Name = "Pizza", Icon = "🍕" },
	{ Name = "Dino", Icon = "🦖" },
	{ Name = "Octopus", Icon = "🐙" },
	{ Name = "Alien", Icon = "👾" },
}

-- Seconds between two changes to one party's look (a reroll, a colour, an emblem).
PartyIdentity.EditCooldown = 0.6

-- An index into a list of `count`: a whole number from 1 to `count`, or nil for anything else
-- (another type, NaN, a fraction, out of range): whatever a client sends is checked here.
function PartyIdentity.Index(value: any, count: number): number?
	if type(value) ~= "number" or value ~= value or value % 1 ~= 0 then
		return nil
	end
	return if value >= 1 and value <= count then value else nil
end

function PartyIdentity.Name(identity: Identity): string
	return `{PartyIdentity.Adjectives[identity.Adjective]} {PartyIdentity.Nouns[identity.Noun]}`
end

-- A random pick among 1..count, skipping the ones `taken` has (any of them when all are taken).
local function pickFree(count: number, taken: { [number]: boolean }?, pick: Pick): number
	local free = {}
	for index = 1, count do
		if not (taken and taken[index]) then
			table.insert(free, index)
		end
	end
	if #free == 0 then
		return pick(count)
	end
	return free[pick(#free)]
end

-- A new party's look: random words (a name no other party here has, when it can), and a colour and
-- an emblem no other party here wears while there are some left.
function PartyIdentity.New(pick: Pick, taken: Taken?): Identity
	local identity: Identity = {
		Adjective = pick(#PartyIdentity.Adjectives),
		Noun = pick(#PartyIdentity.Nouns),
		Color = pickFree(#PartyIdentity.Colors, taken and taken.Colors, pick),
		Emblem = pickFree(#PartyIdentity.Emblems, taken and taken.Emblems, pick),
		EditedAt = -math.huge,
	}
	local names = taken and taken.Names
	for _ = 1, 8 do
		if not (names and names[PartyIdentity.Name(identity)]) then
			break
		end
		identity.Adjective = pick(#PartyIdentity.Adjectives)
		identity.Noun = pick(#PartyIdentity.Nouns)
	end
	return identity
end

-- New words for the name: any pair but the one it has now.
function PartyIdentity.Reroll(identity: Identity, pick: Pick)
	local nouns = #PartyIdentity.Nouns
	local total = #PartyIdentity.Adjectives * nouns
	local current = (identity.Adjective - 1) * nouns + identity.Noun
	local roll = pick(total - 1)
	if roll >= current then
		roll += 1
	end
	identity.Adjective = (roll - 1) // nouns + 1
	identity.Noun = (roll - 1) % nouns + 1
end

-- A request to change a party's look, from the member in `seat` (1 leads) at time `now`:
-- "Reroll" (new words), "Color" with an index into Colors, or "Emblem" with an index into Emblems.
-- Returns true when it changed, or false and why not: "NotLeader", "Soon" (EditCooldown since the
-- last change), "Bad" (an unknown action or an index that isn't one) or "Same" (it wears that
-- already).
function PartyIdentity.Edit(
	identity: Identity,
	seat: number?,
	action: any,
	value: any,
	now: number,
	pick: Pick
): (boolean, string?)
	if seat ~= 1 then
		return false, "NotLeader"
	elseif now - identity.EditedAt < PartyIdentity.EditCooldown then
		return false, "Soon"
	end
	if action == "Reroll" then
		PartyIdentity.Reroll(identity, pick)
	elseif action == "Color" then
		local index = PartyIdentity.Index(value, #PartyIdentity.Colors)
		if not index then
			return false, "Bad"
		elseif identity.Color == index then
			return false, "Same"
		end
		identity.Color = index
	elseif action == "Emblem" then
		local index = PartyIdentity.Index(value, #PartyIdentity.Emblems)
		if not index then
			return false, "Bad"
		elseif identity.Emblem == index then
			return false, "Same"
		end
		identity.Emblem = index
	else
		return false, "Bad"
	end
	identity.EditedAt = now
	return true, nil
end

function PartyIdentity.Show(identity: Identity): Shown
	return { Name = PartyIdentity.Name(identity), Color = identity.Color, Emblem = identity.Emblem }
end

return PartyIdentity

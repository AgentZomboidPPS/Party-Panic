-- Team names and colors for team and versus mini-games. Team names double as HUD labels, so
-- versus roles ("Archers", "Runners") live here too.
--
-- Which team you're on, in words (owner: "I couldnt tell what color I was on prime cut."): Label
-- names a team with its mark ("★ RED", "🦈 SHARKS") and YouAre says it to its players ("YOU'RE ON
-- ★ RED", "YOU'RE A 🦈 SHARK"), for the rules card, the team pill and the modes' own HUDs.

local Teams = {}

-- Order used when splitting players into teams.
Teams.Order = { "Red", "Blue", "Green", "Yellow" }

Teams.Colors = {
	Red = Color3.fromRGB(255, 80, 90),
	Blue = Color3.fromRGB(70, 150, 255),
	Green = Color3.fromRGB(80, 215, 110),
	Yellow = Color3.fromRGB(255, 200, 50),
	Archers = Color3.fromRGB(255, 120, 60),
	Runners = Color3.fromRGB(80, 200, 255),
	SandKings = Color3.fromRGB(230, 170, 70),
	Divers = Color3.fromRGB(110, 210, 255),
	Sharks = Color3.fromRGB(235, 85, 100),
	Swimmers = Color3.fromRGB(255, 196, 60),
} :: { [string]: Color3 }

Teams.Icons = {
	Red = "🔴",
	Blue = "🔵",
	Green = "🟢",
	Yellow = "🟡",
	Archers = "🏹",
	Runners = "🏃",
	SandKings = "👑",
	Divers = "💎", -- not 🪙: phones show nothing for it (newer than Roblox's emoji font)
	Sharks = "🦈",
	Swimmers = "🏊",
} :: { [string]: string }

-- The shape each colour team wears, so a team never goes by its colour alone (the team modes draw the
-- same ones on their pills, stations and sleds: Pump & Pop, Cake Factory, Bobsled Run).
Teams.Shapes = {
	Red = "★",
	Blue = "●",
	Green = "▲",
	Yellow = "◆",
} :: { [string]: string }

-- What one player of each versus role is ("YOU'RE A 🦈 SHARK"), and the roles whose name isn't just
-- the key in capitals.
Teams.Roles = {
	Archers = "AN 🏹 ARCHER",
	Runners = "A 🏃 RUNNER",
	SandKings = "A 👑 SAND KING",
	Divers = "A 💎 DIVER",
	Sharks = "A 🦈 SHARK",
	Swimmers = "A 🏊 SWIMMER",
} :: { [string]: string }
local NAMES = { SandKings = "SAND KINGS" }

function Teams.Color(name: string?): Color3?
	return if name then Teams.Colors[name] else nil
end

-- A team's name on screen with its mark: "★ RED" for a colour team, "🦈 SHARKS" for a role.
function Teams.Label(name: string): string
	local mark = Teams.Shapes[name] or Teams.Icons[name]
	local shown = NAMES[name] or string.upper(name)
	return if mark then `{mark} {shown}` else shown
end

-- What the rules card tells a player on this team ("YOU'RE ON ★ RED", "YOU'RE AN 🏹 ARCHER"), or
-- nil for no team (a free-for-all round, or between rounds).
function Teams.YouAre(name: any): string?
	if type(name) ~= "string" or name == "" then
		return nil
	elseif Teams.Roles[name] then
		return `YOU'RE {Teams.Roles[name]}`
	elseif Teams.Colors[name] then
		return `YOU'RE ON {Teams.Label(name)}`
	end
	return nil
end

-- How many teams to make for `playerCount` players with about `perTeam` in each (2 to 4 teams).
function Teams.CountFor(playerCount: number, perTeam: number): number
	return math.clamp(math.floor(playerCount / perTeam + 0.5), 2, 4)
end

return Teams

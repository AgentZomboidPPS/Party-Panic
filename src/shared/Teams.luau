-- Team names and colors for team and versus mini-games. Team names double as HUD labels, so
-- versus roles ("Archers", "Runners") live here too.

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

function Teams.Color(name: string?): Color3?
	return if name then Teams.Colors[name] else nil
end

-- How many teams to make for `playerCount` players with about `perTeam` in each (2 to 4 teams).
function Teams.CountFor(playerCount: number, perTeam: number): number
	return math.clamp(math.floor(playerCount / perTeam + 0.5), 2, 4)
end

return Teams

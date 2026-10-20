-- Player-facing metadata for every mini-game (design doc §7 template, §8 launch roster).
-- Server modules live in ServerScriptService.Server.MiniGames and must use the same Id.

export type GameDefinition = {
	Id: string,
	Name: string,
	Category: string,
	Icon: string,
	Color: Color3,
	Objective: string,
	Controls: string,
	Duration: number,
	MinPlayers: number,
	IsTeam: boolean,
	Weight: number?,
	IsNew: boolean?,
	Enabled: boolean?,
}

local Categories = {
	Survival = { Icon = "🛡️", Color = Color3.fromRGB(255, 120, 90) },
	Race = { Icon = "🏁", Color = Color3.fromRGB(80, 200, 255) },
	Knockback = { Icon = "🥊", Color = Color3.fromRGB(255, 90, 170) },
	Reaction = { Icon = "⚡", Color = Color3.fromRGB(255, 210, 60) },
	Team = { Icon = "🤝", Color = Color3.fromRGB(120, 230, 120) },
}

local list: { GameDefinition } = {
	{
		Id = "DontGetFlattened",
		Name = "Don't Get Flattened",
		Category = "Survival",
		Icon = "🔨",
		Color = Color3.fromRGB(255, 120, 90),
		Objective = "Dodge boulders, hammers and anvils. Last ones standing win!",
		Controls = "Move and jump. Red markers show where danger lands.",
		Duration = 90,
		MinPlayers = 1,
		IsTeam = false,
	},
	{
		Id = "FloorIsLava",
		Name = "Floor Is Lava",
		Category = "Survival",
		Icon = "🌋",
		Color = Color3.fromRGB(255, 150, 40),
		Objective = "Stay on solid tiles while the floor melts away.",
		Controls = "Flashing tiles with ! are about to sink. Jump to safety!",
		Duration = 85,
		MinPlayers = 1,
		IsTeam = false,
	},
	{
		Id = "YeetArena",
		Name = "Yeet Arena",
		Category = "Knockback",
		Icon = "🥊",
		Color = Color3.fromRGB(255, 90, 170),
		Objective = "Knock everyone off the shrinking platform. Last one on wins!",
		Controls = "Click / tap to swing your Yeet Glove.",
		Duration = 90,
		MinPlayers = 2,
		IsTeam = false,
	},
	{
		Id = "ShoppingCartGrandPrix",
		Name = "Shopping Cart Grand Prix",
		Category = "Race",
		Icon = "🛒",
		Color = Color3.fromRGB(80, 200, 255),
		Objective = "Race your cart through every checkpoint to the finish line.",
		Controls = "Run! Blue pads boost you. Fall off and you restart at your last checkpoint.",
		Duration = 90,
		MinPlayers = 1,
		IsTeam = false,
	},
	{
		Id = "GreedyGoblins",
		Name = "Greedy Goblins",
		Category = "Team",
		Icon = "💰",
		Color = Color3.fromRGB(120, 230, 120),
		Objective = "Grab treasure and deliver it to your team's chest.",
		Controls = "Touch gold to carry it (max 3). Bonk enemies to make them drop theirs.",
		Duration = 110,
		MinPlayers = 2,
		IsTeam = true,
	},
	{
		Id = "TheWrongButton",
		Name = "The Wrong Button",
		Category = "Reaction",
		Icon = "🔘",
		Color = Color3.fromRGB(255, 210, 60),
		Objective = "Stand on the announced color and symbol before the others vanish.",
		Controls = "Read the call, then move fast. Later calls get tricky!",
		Duration = 70,
		MinPlayers = 1,
		IsTeam = false,
	},
}

local GameDefinitions = {
	List = list,
	ById = {} :: { [string]: GameDefinition },
	Categories = Categories,
}

for _, definition in list do
	GameDefinitions.ById[definition.Id] = definition
end

function GameDefinitions.Get(id: string): GameDefinition?
	return GameDefinitions.ById[id]
end

return GameDefinitions

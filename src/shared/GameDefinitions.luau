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
	Luck = { Icon = "🎲", Color = Color3.fromRGB(190, 130, 255) },
	Versus = { Icon = "⚔️", Color = Color3.fromRGB(255, 150, 60) },
}

-- Every mode is built for up to 12 players (Config.Session.MaxPlayers).
local list: { GameDefinition } = {
	{
		Id = "BumperBallers",
		Name = "Bumper Ballers",
		Category = "Knockback",
		Icon = "🎱",
		Color = Color3.fromRGB(255, 90, 170),
		Objective = "Ride your ball and bump rivals into the sea. Last one rolling wins!",
		Controls = "Push the stick (or WASD) the way you want to roll on screen. Phones: tap TILT to steer by tilting.",
		Duration = 65,
		MinPlayers = 1,
		IsTeam = false,
	},
	{
		Id = "FireRope",
		Name = "Fire Rope",
		Category = "Survival",
		Icon = "🔥",
		Color = Color3.fromRGB(255, 120, 50),
		Objective = "Jump the swinging fire rope. It keeps speeding up - last one jumping wins!",
		Controls = "Jump just before the rope reaches your feet.",
		Duration = 80,
		MinPlayers = 1,
		IsTeam = false,
	},
	{
		Id = "HexMeltdown",
		Name = "Hex Meltdown",
		Category = "Reaction",
		Icon = "🌋",
		Color = Color3.fromRGB(255, 170, 40),
		Objective = "Reach a hex that matches the flag before the others sink into the lava!",
		Controls = "Jump hex to hex. Land on a rival's head to stun them.",
		Duration = 90,
		MinPlayers = 1,
		IsTeam = false,
	},
	{
		Id = "HoneyTrap",
		Name = "Honey Trap",
		Category = "Luck",
		Icon = "🍯",
		Color = Color3.fromRGB(255, 200, 60),
		Objective = "Stay on your flower! On your turn, pick 1 or 2 off the vine. A 🍯 honeycomb means you're out. Last one left wins!",
		Controls = "No walking! On your turn, press HIT or jump to stop the block over your head on 1 or 2.",
		Duration = 150,
		MinPlayers = 2,
		IsTeam = false,
	},
	{
		Id = "SkateEscape",
		Name = "Skate Escape",
		Category = "Race",
		Icon = "🛹",
		Color = Color3.fromRGB(80, 200, 255),
		Objective = "Skate across the bridge before it crumbles into the lava. First to the goal wins!",
		Controls = "Mash PUSH (E) to speed up. JUMP crates, barriers and gaps. Ride the ⚡ pads for a boost.",
		Duration = 60,
		MinPlayers = 1,
		IsTeam = false,
	},
	{
		Id = "SinkingSands",
		Name = "Sinking Sands",
		Category = "Versus",
		Icon = "⏳",
		Color = Color3.fromRGB(230, 170, 70),
		Objective = "Divers grab treasure on the swirling quicksand. Sand Kings SWIRL and PULL to sink it! Bigger haul wins.",
		Controls = "Divers: run and keep out of the hole (a hop eases the pull). Sand Kings: tap SWIRL (E) and PULL (Q).",
		Duration = 55,
		MinPlayers = 1,
		IsTeam = true,
	},
	{
		Id = "ArrowAmbush",
		Name = "Arrow Ambush",
		Category = "Versus",
		Icon = "🏹",
		Color = Color3.fromRGB(255, 130, 70),
		Objective = "Archers on the tower must tag every runner. Runners win if anyone is left!",
		Controls = "Archers: click or tap where to shoot. Runners: dodge the red rings and hide behind the target boards.",
		Duration = 45,
		MinPlayers = 2,
		IsTeam = true,
	},
	{
		Id = "PumpAndPop",
		Name = "Pump & Pop",
		Category = "Team",
		Icon = "🎈",
		Color = Color3.fromRGB(120, 230, 120),
		Objective = "Pump air into your team's balloon. First team to pop it wins!",
		Controls = "Hold PUMP, let go in the green ✓. Too long wastes air: keep a rhythm!",
		Duration = 40,
		MinPlayers = 2,
		IsTeam = true,
	},
	{
		Id = "RakeItIn",
		Name = "Rake It In",
		Category = "Reaction",
		Icon = "🥕",
		Color = Color3.fromRGB(255, 150, 60),
		Objective = "Rake veggies off the spinning field into your basket. 🎃 = 3, 💣 = -3!",
		Controls = "Press RAKE when veggies are in your lane. Skip the bombs!",
		Duration = 55,
		MinPlayers = 1,
		IsTeam = false,
		IsNew = true, -- a little extra vote exposure while it's new; remove later
	},
	{
		Id = "CrazyCutters",
		Name = "Crazy Cutters",
		Category = "Reaction",
		Icon = "🍪",
		Color = Color3.fromRGB(240, 170, 90),
		Objective = "Cut 3 cookies by tracing the dotted line. Most accurate cutter wins!",
		Controls = "Drag your finger or hold the mouse to steer the cutter. Keys / stick work too.",
		Duration = 85,
		MinPlayers = 1,
		IsTeam = false,
		IsNew = true, -- a little extra vote exposure while it's new; remove later
	},
	{
		Id = "BobsledRun",
		Name = "Bobsled Run",
		Category = "Team",
		Icon = "🛷",
		Color = Color3.fromRGB(110, 200, 255),
		Objective = "Race your crew's bobsled down the ice. Lean together into every curve - first sled home wins!",
		Controls = "When the arrow shows, press LEAN LEFT or LEAN RIGHT (A / D) with your crew. Wrong or late hits the wall!",
		Duration = 55,
		MinPlayers = 2,
		IsTeam = true,
		IsNew = true, -- a little extra vote exposure while it's new; remove later
	},
	{
		Id = "CakeFactory",
		Name = "Cake Factory",
		Category = "Team",
		Icon = "🎂",
		Color = Color3.fromRGB(255, 130, 175),
		Objective = "Build cakes on your team's belt. A finished cake is 1 point, a ⭐ cake (every layer PERFECT) is 2. Most points wins!",
		Controls = "Tap ADD (E) when a cake is in your machine's gate. Skip cakes missing a layer!",
		Duration = 55,
		MinPlayers = 2,
		IsTeam = true,
		IsNew = true, -- a little extra vote exposure while it's new; remove later
	},
	{
		Id = "SharkBait",
		Name = "Shark Bait",
		Category = "Versus",
		Icon = "🦈",
		Color = Color3.fromRGB(40, 170, 225),
		Objective = "Swimmers: grab coins together and hit the goal! The SHARK tips rafts and chomps anyone in the water.",
		Controls = "Swimmers: hop raft to raft and stay dry. Shark: swim and tap CHOMP (E) at rafts and swimmers.",
		Duration = 60,
		MinPlayers = 2,
		IsTeam = true,
		IsNew = true, -- a little extra vote exposure while it's new; remove later
	},
	{
		Id = "MechaMarathon",
		Name = "Mecha-Marathon",
		Category = "Reaction",
		Icon = "🚁",
		Color = Color3.fromRGB(255, 170, 60),
		Objective = "Mash WIND for 10 seconds to wind up your toy. The farthest flight wins!",
		Controls = "PC: alternate Q and E, fast. Phone: tap WIND as fast as you can (two thumbs work)!",
		Duration = 30,
		MinPlayers = 1,
		IsTeam = false,
		IsNew = true, -- a little extra vote exposure while it's new; remove later
	},
	{
		Id = "Spleef",
		Name = "Spleef",
		Category = "Survival",
		Icon = "❄️",
		Color = Color3.fromRGB(120, 200, 255),
		Objective = "Break the snow under your rivals! Fall through all 3 floors into the water and you're out. Last one standing wins!",
		Controls = "Click or tap a block near you to break it. DIG (E) breaks the block under the nearest rival.",
		Duration = 75,
		MinPlayers = 2,
		IsTeam = false,
		IsNew = true, -- a little extra vote exposure while it's new; remove later
	},
	{
		Id = "PrimeCut",
		Name = "Prime Cut",
		Category = "Team",
		Icon = "🥩",
		Color = Color3.fromRGB(214, 96, 72),
		Objective = "Line up your team's giant knife and cut the steak exactly 50 : 50. Closest split wins - 3 steaks!",
		Controls = "Tap or hold ◀ ▶ (A / D) to nudge the knife. Teammates push it too: agree on the middle!",
		Duration = 56,
		MinPlayers = 2,
		IsTeam = true,
		IsNew = true, -- a little extra vote exposure while it's new; remove later
	},
	{
		Id = "TraceRace",
		Name = "Trace Race",
		Category = "Reaction",
		Icon = "🖍️",
		Color = Color3.fromRGB(120, 170, 255),
		Objective = "Ride your giant crayon down the dotted line. The most accurate line wins!",
		Controls = "Steer left and right with the MOVE stick, A / D or the arrow keys. The crayon goes forward by itself.",
		Duration = 45,
		MinPlayers = 1,
		IsTeam = false,
		IsNew = true, -- a little extra vote exposure while it's new; remove later
	},
	-- NEW MINI-GAMES GO ABOVE THIS LINE (`lune run tools/new-minigame` adds them here)
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

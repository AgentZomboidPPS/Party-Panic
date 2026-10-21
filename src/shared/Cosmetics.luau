-- Cosmetic catalog (design doc §10). Cosmetics never change gameplay.
-- Unlock sources: coin Price, account level (UnlockLevel), lifetime stat (UnlockStat), or the VIP pass.
-- Prices are on the low coin scale (owner: "Also lets balance the shop down. I want low currency
-- not high."): a round pays 2-6 coins, so the cheapest items take a few rounds and the best a few
-- dozen. Level and stat items can't be bought: they are the Rewards Road (one at most milestone
-- levels) and the career milestones (owner: "Also we need cool payoffs for players that keep
-- playing the game."). Every UnlockStat must be a stat Logic/ProgressionLogic.RecordRound keeps.

local GameDefinitions = require(script.Parent.GameDefinitions)

export type Cosmetic = {
	Id: string,
	Slot: string, -- "Trail" | "Title" | "Emote" | "Victory" | "Elimination"
	Name: string,
	Description: string,
	Icon: string,
	Price: number?, -- coins; nil means not sold for coins
	Default: boolean?, -- owned by every new profile
	UnlockLevel: number?,
	UnlockStat: { Stat: string, Value: number, Label: string }?,
	Vip: boolean?,
	Colors: { Color3 }?, -- trails, title accents and effect tints
	Animation: number?, -- emote animation asset id (Roblox default R15 emotes)
	Looped: boolean?,
	Effect: string?, -- visual effect played by emotes / victory / elimination
}

-- Every game, for the Game Explorer milestone ("play every game once").
local gameCount = 0
for _, definition in GameDefinitions.List do
	if definition.Enabled ~= false then
		gameCount += 1
	end
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local list: { Cosmetic } = {
	-- Trails
	{
		Id = "Trail_Bubbles",
		Slot = "Trail",
		Name = "Bubble Stream",
		Description = "A soft trail of soapy blues.",
		Icon = "🔵", -- not 🫧: newer than Roblox's emoji font, blank on phones
		Price = 12,
		Colors = { rgb(160, 230, 255), rgb(255, 255, 255) },
	},
	{
		Id = "Trail_Pixel",
		Slot = "Trail",
		Name = "Pixel Dust",
		Description = "Retro green sparkle dust.",
		Icon = "👾",
		Price = 12,
		Colors = { rgb(90, 255, 120), rgb(20, 160, 80) },
	},
	{
		Id = "Trail_Confetti",
		Slot = "Trail",
		Name = "Confetti Streak",
		Description = "Party colors wherever you run.",
		Icon = "🎊",
		Price = 20,
		Colors = { rgb(255, 90, 170), rgb(255, 220, 60), rgb(80, 200, 255) },
	},
	{
		Id = "Trail_Comic",
		Slot = "Trail",
		Name = "Comic Speed Lines",
		Description = "Zoom like a cartoon.",
		Icon = "💨",
		Price = 20,
		Colors = { rgb(255, 255, 255), rgb(40, 40, 60) },
	},
	{
		Id = "Trail_Fire",
		Slot = "Trail",
		Name = "Hot Sauce",
		Description = "Spicy orange flames.",
		Icon = "🔥",
		Price = 25,
		Colors = { rgb(255, 230, 80), rgb(255, 110, 30), rgb(200, 30, 30) },
	},
	{
		Id = "Trail_Rainbow",
		Slot = "Trail",
		Name = "Rainbow Dash",
		Description = "Every color, all at once.",
		Icon = "🌈",
		Price = 30,
		Colors = { rgb(255, 80, 80), rgb(255, 200, 60), rgb(90, 230, 110), rgb(80, 170, 255), rgb(190, 110, 255) },
	},
	{
		Id = "Trail_Bubblegum",
		Slot = "Trail",
		Name = "Bubblegum Swirl",
		Description = "Sweet pink swirls.",
		Icon = "🍬",
		UnlockLevel = 3,
		Colors = { rgb(255, 150, 210), rgb(255, 255, 255), rgb(255, 100, 175) },
	},
	{
		Id = "Trail_Starry",
		Slot = "Trail",
		Name = "Starry Night",
		Description = "A sky full of stars.",
		Icon = "🌌",
		UnlockLevel = 10,
		Colors = { rgb(60, 60, 160), rgb(150, 100, 240), rgb(255, 255, 255) },
	},
	{
		Id = "Trail_Gold",
		Slot = "Trail",
		Name = "Golden Glory",
		Description = "Shine like a champion.",
		Icon = "🏅",
		UnlockLevel = 15,
		Colors = { rgb(255, 230, 120), rgb(230, 160, 30) },
	},
	{
		Id = "Trail_Comet",
		Slot = "Trail",
		Name = "Comet Tail",
		Description = "Streak across the sky.",
		Icon = "💫",
		UnlockLevel = 35,
		Colors = { rgb(255, 255, 255), rgb(120, 220, 255), rgb(170, 110, 255) },
	},
	{
		Id = "Trail_Solar",
		Slot = "Trail",
		Name = "Solar Flare",
		Description = "Hot as the sun.",
		Icon = "🌞",
		UnlockLevel = 60,
		Colors = { rgb(255, 250, 180), rgb(255, 180, 40), rgb(255, 90, 40) },
	},
	{
		Id = "Trail_Hearts",
		Slot = "Trail",
		Name = "Loyal Hearts",
		Description = "Party on 30 different days.",
		Icon = "💖",
		UnlockStat = { Stat = "DaysPlayed", Value = 30, Label = "Days" },
		Colors = { rgb(255, 130, 190), rgb(255, 60, 110) },
	},
	{
		Id = "Trail_VIP",
		Slot = "Trail",
		Name = "VIP Starlight",
		Description = "Included with the VIP pass.",
		Icon = "💎",
		Vip = true,
		Colors = { rgb(255, 245, 200), rgb(190, 140, 255) },
	},

	-- Titles
	{
		Id = "Title_Rookie",
		Slot = "Title",
		Name = "Party Rookie",
		Description = "Everyone starts somewhere.",
		Icon = "🎈",
		Default = true,
		Colors = { rgb(200, 220, 255) },
	},
	{
		Id = "Title_Regular",
		Slot = "Title",
		Name = "Party Regular",
		Description = "A familiar face at the party.",
		Icon = "🎉",
		UnlockLevel = 5,
		Colors = { rgb(140, 230, 255) },
	},
	{
		Id = "Title_Pro",
		Slot = "Title",
		Name = "Party Pro",
		Description = "You know every trick.",
		Icon = "⭐",
		UnlockLevel = 10,
		Colors = { rgb(255, 220, 90) },
	},
	{
		Id = "Title_Legend",
		Slot = "Title",
		Name = "Party Legend",
		Description = "They tell stories about you.",
		Icon = "👑",
		UnlockLevel = 25,
		Colors = { rgb(255, 170, 60) },
	},
	{
		Id = "Title_Superstar",
		Slot = "Title",
		Name = "Party Superstar",
		Description = "All eyes on you.",
		Icon = "🌟",
		UnlockLevel = 45,
		Colors = { rgb(255, 240, 120) },
	},
	{
		Id = "Title_Icon",
		Slot = "Title",
		Name = "Party Icon",
		Description = "Shines like a diamond.",
		Icon = "💎",
		UnlockLevel = 50,
		Colors = { rgb(150, 240, 255) },
	},
	{
		Id = "Title_Immortal",
		Slot = "Title",
		Name = "Party Immortal",
		Description = "Level 100. The party never ends.",
		Icon = "🌈",
		UnlockLevel = 100,
		Colors = { rgb(255, 150, 230) },
	},
	{
		Id = "Title_Animal",
		Slot = "Title",
		Name = "Party Animal",
		Description = "Play 50 rounds.",
		Icon = "🐾",
		UnlockStat = { Stat = "RoundsPlayed", Value = 50, Label = "Rounds" },
		Colors = { rgb(255, 190, 120) },
	},
	{
		Id = "Title_Veteran",
		Slot = "Title",
		Name = "Party Veteran",
		Description = "Play 250 rounds.",
		Icon = "🎖️",
		UnlockStat = { Stat = "RoundsPlayed", Value = 250, Label = "Rounds" },
		Colors = { rgb(255, 200, 90) },
	},
	{
		Id = "Title_WinnerWinner",
		Slot = "Title",
		Name = "Winner Winner",
		Description = "Win 10 rounds.",
		Icon = "🍗",
		UnlockStat = { Stat = "Wins", Value = 10, Label = "Wins" },
		Colors = { rgb(255, 210, 120) },
	},
	{
		Id = "Title_PodiumPro",
		Slot = "Title",
		Name = "Podium Pro",
		Description = "Make the podium (top 3) 25 times.",
		Icon = "🥇",
		UnlockStat = { Stat = "Podiums", Value = 25, Label = "Podiums" },
		Colors = { rgb(255, 225, 90) },
	},
	{
		Id = "Title_Explorer",
		Slot = "Title",
		Name = "Game Explorer",
		Description = `Play all {gameCount} games.`,
		Icon = "🗺️",
		UnlockStat = { Stat = "GamesTried", Value = gameCount, Label = "Games" },
		Colors = { rgb(120, 230, 200) },
	},
	{
		Id = "Title_WeekWarrior",
		Slot = "Title",
		Name = "Week Warrior",
		Description = "Party on 7 different days.",
		Icon = "📅",
		UnlockStat = { Stat = "DaysPlayed", Value = 7, Label = "Days" },
		Colors = { rgb(160, 200, 255) },
	},
	{
		Id = "Title_HazardDodger",
		Slot = "Title",
		Name = "Hazard Dodger",
		Description = "Win 5 survival rounds.",
		Icon = "🛡️",
		UnlockStat = { Stat = "SurvivalWins", Value = 5, Label = "Survival wins" },
		Colors = { rgb(255, 130, 100) },
	},
	{
		Id = "Title_TeamMVP",
		Slot = "Title",
		Name = "Team MVP",
		Description = "Win 10 rounds with your team.",
		Icon = "🤝",
		UnlockStat = { Stat = "TeamWins", Value = 10, Label = "Team wins" },
		Colors = { rgb(130, 240, 130) },
	},
	{
		Id = "Title_SpeedDemon",
		Slot = "Title",
		Name = "Speed Demon",
		Description = "Top 3 in 5 races: SKATE ESCAPE or BOBSLED RUN.",
		Icon = "🏎️",
		UnlockStat = { Stat = "RacePodiums", Value = 5, Label = "Race podiums" },
		Colors = { rgb(90, 200, 255) },
	},
	{
		Id = "Title_Confetti",
		Slot = "Title",
		Name = "Confetti Connoisseur",
		Description = "For the true party animal.",
		Icon = "🎊",
		Price = 25,
		Colors = { rgb(255, 120, 200) },
	},
	{
		Id = "Title_ChaosChampion",
		Slot = "Title",
		Name = "Chaos Champion",
		Description = "Thrives in the panic.",
		Icon = "🌀",
		Price = 40,
		Colors = { rgb(200, 130, 255) },
	},
	{
		Id = "Title_VIP",
		Slot = "Title",
		Name = "VIP Partier",
		Description = "Included with the VIP pass.",
		Icon = "💎",
		Vip = true,
		Colors = { rgb(255, 230, 140) },
	},

	-- Emotes (all owned emotes appear in the emote menu)
	{
		Id = "Emote_Wave",
		Slot = "Emote",
		Name = "Wave",
		Description = "Say hi!",
		Icon = "👋",
		Default = true,
		Animation = 507770239,
	},
	{
		Id = "Emote_Cheer",
		Slot = "Emote",
		Name = "Cheer",
		Description = "Celebrate a friend.",
		Icon = "🙌",
		Default = true,
		Animation = 507770677,
	},
	{
		Id = "Emote_Point",
		Slot = "Emote",
		Name = "Point",
		Description = "Over there!",
		Icon = "👉",
		Default = true,
		Animation = 507770453,
	},
	{
		Id = "Emote_Laugh",
		Slot = "Emote",
		Name = "Laugh",
		Description = "That was hilarious.",
		Icon = "😂",
		Price = 8,
		Animation = 507770818,
	},
	{
		Id = "Emote_Dance",
		Slot = "Emote",
		Name = "Groove",
		Description = "A classic dance.",
		Icon = "🕺",
		Price = 15,
		Animation = 507771019,
		Looped = true,
	},
	{
		Id = "Emote_Dance2",
		Slot = "Emote",
		Name = "Bounce",
		Description = "Feel the beat.",
		Icon = "💃",
		Price = 20,
		Animation = 507776043,
		Looped = true,
	},
	{
		Id = "Emote_Dance3",
		Slot = "Emote",
		Name = "Disco",
		Description = "Saturday night moves.",
		Icon = "🎶", -- not 🪩: newer than Roblox's emoji font, blank on phones
		Price = 25,
		Animation = 507777268,
		Looped = true,
	},
	{
		Id = "Emote_Confetti",
		Slot = "Emote",
		Name = "Confetti Pop",
		Description = "Burst of confetti.",
		Icon = "🎉",
		Price = 10,
		Effect = "Confetti",
	},
	{
		Id = "Emote_Hearts",
		Slot = "Emote",
		Name = "Heart Burst",
		Description = "Spread the love.",
		Icon = "💖",
		Price = 10,
		Effect = "Hearts",
	},
	{
		Id = "Emote_Stars",
		Slot = "Emote",
		Name = "Star Shower",
		Description = "You're a star.",
		Icon = "✨",
		Price = 20,
		Effect = "Stars",
	},
	{
		Id = "Emote_Balloons",
		Slot = "Emote",
		Name = "Balloon Bash",
		Description = "Let a bunch of balloons go.",
		Icon = "🎈",
		UnlockLevel = 2,
		Effect = "Balloons",
	},
	{
		Id = "Emote_Sing",
		Slot = "Emote",
		Name = "Sing Along",
		Description = "Everybody sing!",
		Icon = "🎵",
		UnlockLevel = 18,
		Effect = "Notes",
	},
	{
		Id = "Emote_Crowns",
		Slot = "Emote",
		Name = "Crown Shower",
		Description = "Make it rain crowns.",
		Icon = "👑",
		UnlockLevel = 30,
		Effect = "Crowns",
	},

	-- Victory effects
	{
		Id = "Victory_Confetti",
		Slot = "Victory",
		Name = "Confetti Rain",
		Description = "Classic celebration.",
		Icon = "🎉",
		Default = true,
		Effect = "Confetti",
	},
	{
		Id = "Victory_Sparkles",
		Slot = "Victory",
		Name = "Golden Sparkles",
		Description = "Shine on the podium.",
		Icon = "✨",
		Price = 25,
		Effect = "Sparkles",
	},
	{
		Id = "Victory_Fireworks",
		Slot = "Victory",
		Name = "Fireworks",
		Description = "Light up the sky.",
		Icon = "🎆",
		Price = 30,
		Effect = "Fireworks",
	},
	{
		Id = "Victory_GoldFireworks",
		Slot = "Victory",
		Name = "Golden Fireworks",
		Description = "Gold sparks for a gold finish.",
		Icon = "🎇",
		UnlockLevel = 12,
		Effect = "Fireworks",
		Colors = { rgb(255, 230, 120), rgb(255, 190, 60), rgb(255, 250, 210) },
	},
	{
		Id = "Victory_RainbowFireworks",
		Slot = "Victory",
		Name = "Rainbow Fireworks",
		Description = "Every color in the sky.",
		Icon = "🌈",
		UnlockLevel = 20,
		Effect = "Fireworks",
		Colors = { rgb(255, 80, 80), rgb(255, 200, 60), rgb(90, 230, 110), rgb(80, 170, 255), rgb(190, 110, 255) },
	},
	{
		Id = "Victory_Finale",
		Slot = "Victory",
		Name = "Grand Finale",
		Description = "Confetti, sparkles AND fireworks.",
		Icon = "🎆",
		UnlockLevel = 75,
		Effect = "Finale",
	},
	{
		Id = "Victory_Trophies",
		Slot = "Victory",
		Name = "Trophy Rain",
		Description = "Win 50 rounds.",
		Icon = "🏆",
		UnlockStat = { Stat = "Wins", Value = 50, Label = "Wins" },
		Effect = "Trophies",
	},

	-- Elimination effects
	{
		Id = "Elim_Poof",
		Slot = "Elimination",
		Name = "Cartoon Poof",
		Description = "Gone in a puff.",
		Icon = "💨",
		Default = true,
		Effect = "Poof",
	},
	{
		Id = "Elim_Stars",
		Slot = "Elimination",
		Name = "Seeing Stars",
		Description = "Dizzy little stars.",
		Icon = "💫",
		Price = 12,
		Effect = "Stars",
	},
	{
		Id = "Elim_Bubbles",
		Slot = "Elimination",
		Name = "Bubble Pop",
		Description = "Pop!",
		Icon = "🔵", -- not 🫧: newer than Roblox's emoji font, blank on phones
		Price = 12,
		Effect = "Bubbles",
	},
	{
		Id = "Elim_Ghost",
		Slot = "Elimination",
		Name = "Ghosted",
		Description = "Float away as a little ghost.",
		Icon = "👻",
		UnlockLevel = 7,
		Effect = "Ghosts",
	},
	{
		Id = "Elim_Kaboom",
		Slot = "Elimination",
		Name = "Kaboom",
		Description = "Go out with a bang.",
		Icon = "💥",
		UnlockLevel = 40,
		Effect = "Fireworks",
	},
}

local Cosmetics = {
	List = list,
	ById = {} :: { [string]: Cosmetic },
	-- Slots a player equips one item into (emotes are not equipped; every owned emote is usable).
	EquipSlots = { "Trail", "Title", "Victory", "Elimination" },
	-- What each slot is called on reward cards ("TRAIL", "KNOCKOUT").
	SlotNames = {
		Trail = "Trail",
		Title = "Title",
		Emote = "Emote",
		Victory = "Victory",
		Elimination = "Knockout",
	} :: { [string]: string },
	ShopTabs = {
		{ Slot = "Trail", Label = "Trails", Icon = "🌈" },
		{ Slot = "Title", Label = "Titles", Icon = "🏷️" },
		{ Slot = "Emote", Label = "Emotes", Icon = "🕺" },
		{ Slot = "Victory", Label = "Victory", Icon = "🏆" },
		{ Slot = "Elimination", Label = "Knockout", Icon = "💥" },
	},
}

for _, item in list do
	Cosmetics.ById[item.Id] = item
end

function Cosmetics.Get(id: string): Cosmetic?
	return Cosmetics.ById[id]
end

function Cosmetics.IsEquipSlot(slot: string): boolean
	return table.find(Cosmetics.EquipSlots, slot) ~= nil
end

function Cosmetics.ColorSequence(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keypoints = {}
	for index, color in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keypoints)
end

return Cosmetics

-- Cosmetic catalog (design doc §10). Cosmetics never change gameplay.
-- Unlock sources: coin Price, account level (UnlockLevel), lifetime stat (UnlockStat), or the VIP pass.

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
		Icon = "🫧",
		Price = 150,
		Colors = { rgb(160, 230, 255), rgb(255, 255, 255) },
	},
	{
		Id = "Trail_Pixel",
		Slot = "Trail",
		Name = "Pixel Dust",
		Description = "Retro green sparkle dust.",
		Icon = "👾",
		Price = 150,
		Colors = { rgb(90, 255, 120), rgb(20, 160, 80) },
	},
	{
		Id = "Trail_Confetti",
		Slot = "Trail",
		Name = "Confetti Streak",
		Description = "Party colors wherever you run.",
		Icon = "🎊",
		Price = 200,
		Colors = { rgb(255, 90, 170), rgb(255, 220, 60), rgb(80, 200, 255) },
	},
	{
		Id = "Trail_Comic",
		Slot = "Trail",
		Name = "Comic Speed Lines",
		Description = "Zoom like a cartoon.",
		Icon = "💨",
		Price = 200,
		Colors = { rgb(255, 255, 255), rgb(40, 40, 60) },
	},
	{
		Id = "Trail_Fire",
		Slot = "Trail",
		Name = "Hot Sauce",
		Description = "Spicy orange flames.",
		Icon = "🔥",
		Price = 250,
		Colors = { rgb(255, 230, 80), rgb(255, 110, 30), rgb(200, 30, 30) },
	},
	{
		Id = "Trail_Rainbow",
		Slot = "Trail",
		Name = "Rainbow Dash",
		Description = "Every color, all at once.",
		Icon = "🌈",
		Price = 300,
		Colors = { rgb(255, 80, 80), rgb(255, 200, 60), rgb(90, 230, 110), rgb(80, 170, 255), rgb(190, 110, 255) },
	},
	{
		Id = "Trail_Gold",
		Slot = "Trail",
		Name = "Golden Glory",
		Description = "Reach level 15 to unlock.",
		Icon = "🏅",
		UnlockLevel = 15,
		Colors = { rgb(255, 230, 120), rgb(230, 160, 30) },
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
		Description = "Reach level 5.",
		Icon = "🎉",
		UnlockLevel = 5,
		Colors = { rgb(140, 230, 255) },
	},
	{
		Id = "Title_Pro",
		Slot = "Title",
		Name = "Party Pro",
		Description = "Reach level 10.",
		Icon = "⭐",
		UnlockLevel = 10,
		Colors = { rgb(255, 220, 90) },
	},
	{
		Id = "Title_Legend",
		Slot = "Title",
		Name = "Party Legend",
		Description = "Reach level 25.",
		Icon = "👑",
		UnlockLevel = 25,
		Colors = { rgb(255, 170, 60) },
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
		Description = "Deliver 50 treasure for your team.",
		Icon = "🤝",
		UnlockStat = { Stat = "TreasureDelivered", Value = 50, Label = "Treasure delivered" },
		Colors = { rgb(130, 240, 130) },
	},
	{
		Id = "Title_SpeedDemon",
		Slot = "Title",
		Name = "Speed Demon",
		Description = "Finish 10 races.",
		Icon = "🏎️",
		UnlockStat = { Stat = "RaceFinishes", Value = 10, Label = "Races finished" },
		Colors = { rgb(90, 200, 255) },
	},
	{
		Id = "Title_Confetti",
		Slot = "Title",
		Name = "Confetti Connoisseur",
		Description = "For the true party animal.",
		Icon = "🎊",
		Price = 250,
		Colors = { rgb(255, 120, 200) },
	},
	{
		Id = "Title_ChaosChampion",
		Slot = "Title",
		Name = "Chaos Champion",
		Description = "Thrives in the panic.",
		Icon = "🌀",
		Price = 400,
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
		Price = 100,
		Animation = 507770818,
	},
	{
		Id = "Emote_Dance",
		Slot = "Emote",
		Name = "Groove",
		Description = "A classic dance.",
		Icon = "🕺",
		Price = 150,
		Animation = 507771019,
		Looped = true,
	},
	{
		Id = "Emote_Dance2",
		Slot = "Emote",
		Name = "Bounce",
		Description = "Feel the beat.",
		Icon = "💃",
		Price = 200,
		Animation = 507776043,
		Looped = true,
	},
	{
		Id = "Emote_Dance3",
		Slot = "Emote",
		Name = "Disco",
		Description = "Saturday night moves.",
		Icon = "🪩",
		Price = 250,
		Animation = 507777268,
		Looped = true,
	},
	{
		Id = "Emote_Confetti",
		Slot = "Emote",
		Name = "Confetti Pop",
		Description = "Burst of confetti.",
		Icon = "🎉",
		Price = 120,
		Effect = "Confetti",
	},
	{
		Id = "Emote_Hearts",
		Slot = "Emote",
		Name = "Heart Burst",
		Description = "Spread the love.",
		Icon = "💖",
		Price = 120,
		Effect = "Hearts",
	},
	{
		Id = "Emote_Stars",
		Slot = "Emote",
		Name = "Star Shower",
		Description = "You're a star.",
		Icon = "✨",
		Price = 200,
		Effect = "Stars",
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
		Price = 250,
		Effect = "Sparkles",
	},
	{
		Id = "Victory_Fireworks",
		Slot = "Victory",
		Name = "Fireworks",
		Description = "Light up the sky.",
		Icon = "🎆",
		Price = 300,
		Effect = "Fireworks",
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
		Price = 150,
		Effect = "Stars",
	},
	{
		Id = "Elim_Bubbles",
		Slot = "Elimination",
		Name = "Bubble Pop",
		Description = "Pop!",
		Icon = "🫧",
		Price = 150,
		Effect = "Bubbles",
	},
}

local Cosmetics = {
	List = list,
	ById = {} :: { [string]: Cosmetic },
	-- Slots a player equips one item into (emotes are not equipped; every owned emote is usable).
	EquipSlots = { "Trail", "Title", "Victory", "Elimination" },
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

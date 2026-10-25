-- Cosmetic catalog (design doc §10). Cosmetics never change gameplay.
-- Unlock sources: coin Price, account level (UnlockLevel), lifetime stat (UnlockStat), or the GOLD PASS.
-- Prices are on the low coin scale (owner: "Also lets balance the shop down. I want low currency
-- not high."): a round pays 2-6 coins, so the cheapest items take a few rounds and the best a few
-- dozen. Level and stat items can't be bought: they are the Rewards Road (one at most milestone
-- levels) and the career milestones (owner: "Also we need cool payoffs for players that keep
-- playing the game."). Every UnlockStat must be a stat Logic/ProgressionLogic.RecordRound keeps (or
-- Game Mastery's counts across every game, which Logic/MasteryLogic.SetStats keeps after each round).
-- Event rewards (owner, asked what keeps players coming back: "Can you work on all of that? this
-- wont mess with what the other workers are working on right?"): an item with Event = "<event id>"
-- is a step of that limited-time event's free reward track (Shared/Events), claimed with candy in the
-- event screen and never sold; the shop's card says which event it came from (Shared/Events' Label).
-- Hats (owner: "do pumpkin hat now"): the Hat slot is worn on the head in the lobby (World/Hats builds
-- each as an Accessory; Services/CosmeticService puts it on and takes it off). The PUMPKIN HAT is the
-- HALLOWEEN PARTY's headline reward.
-- The GOLD PASS (owner: "the paid one should also be insane"): an item with a GoldLevel is on the
-- Rewards Road's gold lane, its owners' at that level. Its own cosmetics live in Shared/GoldPass and
-- come last in the list; the two old VIP items are gold rewards now.
-- Second shop pass (told "On the low-coin scale a regular player can buy the whole shop in about a
-- week", the owner said: "Yes lets add more items after everything else is finished"): 25 more coin
-- items across the same five slots, so the whole shop takes a regular player about 3-4 weeks.
--   The sums (tests/Catalog.spec checks them): an average round pays 2.85 coins (2 for playing,
--   half the time 1 for the top half, one round in 8 a 2-coin win, one in 10 a personal best). A
--   regular player plays 15 rounds a day (about 45 minutes), wins once (5 coins for the first win of
--   the day) and claims the daily gift, which climbs 5, 6, 7, 8, 9, 10 over the first week and stays
--   at 15 from day 7 on: about 56 coins a day in the first week, then about 63 (call it 60). The 19
--   first items cost 371 coins (about a week); the shop now costs 1381 (371 + 1010): about 23 days,
--   3.3 weeks. Quests and Rewards Road coins (about 28 a day more) make it about 2 weeks for someone
--   who does everything; rounds alone (no gifts, first wins or quests) about 4.5 weeks. The GOLD
--   PASS's gold-lane coins (about 1-8% more) and double coins weekends only make it quicker. Hats
--   aren't sold: they're the events' and the GOLD PASS's (tests/Catalog.spec checks neither has a
--   Price).
--   Price bands: a few at 10-20 for new players, most at 25-50, and four to save up for (Spotlight
--   70, Panic Royalty 80, Northern Lights 100, Supernova 120).
--   Roblox's default emote animations are all in use already (the other Dance variants it ships
--   are the same animation), so the new emotes are effects, or a default dance with an effect.
--   Every new effect is short and small (EffectsController), and trails stay the same thin ribbon.

local GameDefinitions = require(script.Parent.GameDefinitions)

export type Cosmetic = {
	Id: string,
	Slot: string, -- "Trail" | "Hat" | "Title" | "Emote" | "Victory" | "Elimination"
	Name: string,
	Description: string,
	Icon: string,
	Price: number?, -- coins; nil means not sold for coins
	Default: boolean?, -- owned by every new profile
	UnlockLevel: number?,
	UnlockStat: { Stat: string, Value: number, Label: string }?,
	GoldLevel: number?, -- the GOLD PASS lane's level (Shared/GoldPass): its owners get it there
	Style: { [string]: any }?, -- a gold trail's extra looks (Shared/GoldPass: texture, glow, glitter)
	Event: string?, -- a limited-time event's reward (Shared/Events id): claimed on its track, never sold
	Colors: { Color3 }?, -- trails, title accents and effect tints
	Animation: number?, -- emote animation asset id (Roblox default R15 emotes)
	Looped: boolean?,
	Effect: string?, -- visual effect played by emotes / victory / elimination
	Season: string?, -- a crate season's item (Shared/Seasons id): found in its crates, never sold for coins
	Look: string?, -- a title with a look of its own on the name tag ("Harvester": Shared/NameTag)
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
		Description = "A GOLD PASS reward.",
		Icon = "💎",
		GoldLevel = 6,
		Colors = { rgb(255, 245, 200), rgb(190, 140, 255) },
	},
	-- Second shop pass: more for coins.
	{
		Id = "Trail_Mint",
		Slot = "Trail",
		Name = "Mint Breeze",
		Description = "A cool, fresh green swish.",
		Icon = "🍃",
		Price = 15,
		Colors = { rgb(190, 255, 220), rgb(90, 220, 160) },
	},
	{
		Id = "Trail_Ocean",
		Slot = "Trail",
		Name = "Ocean Spray",
		Description = "Deep blue with a foamy edge.",
		Icon = "🌊",
		Price = 30,
		Colors = { rgb(230, 250, 255), rgb(60, 170, 230), rgb(20, 80, 170) },
	},
	{
		Id = "Trail_Sunset",
		Slot = "Trail",
		Name = "Sunset Glow",
		Description = "Peach, pink and purple skies.",
		Icon = "🌅",
		Price = 40,
		Colors = { rgb(255, 200, 120), rgb(255, 110, 140), rgb(150, 80, 200) },
	},
	{
		Id = "Trail_Neon",
		Slot = "Trail",
		Name = "Neon Nights",
		Description = "Bright city lights after dark.",
		Icon = "🌃",
		Price = 50,
		Colors = { rgb(255, 60, 200), rgb(80, 240, 255), rgb(140, 90, 255) },
	},
	{
		Id = "Trail_Aurora",
		Slot = "Trail",
		Name = "Northern Lights",
		Description = "Glowing ribbons from the far north.",
		Icon = "🌠",
		Price = 100,
		Colors = { rgb(120, 255, 170), rgb(60, 220, 220), rgb(110, 140, 255), rgb(210, 110, 255), rgb(255, 130, 200) },
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
	-- Game Mastery's goals across every game (owner: "Let's build it. 1 yes 2 gold pass should help a
	-- little. 3 yes"; Logic/MasteryLogic).
	{
		Id = "Title_AllRounder",
		Slot = "Title",
		Name = "All-Rounder",
		Description = "Reach GOLD mastery in 5 games.",
		Icon = "🥇",
		UnlockStat = { Stat = "MasteryGold", Value = 5, Label = "GOLD games" },
		Colors = { rgb(255, 214, 70) },
	},
	{
		Id = "Title_DiamondPartier",
		Slot = "Title",
		Name = "Diamond Partier",
		Description = "Reach DIAMOND mastery in 10 games.",
		Icon = "💎",
		UnlockStat = { Stat = "MasteryDiamond", Value = 10, Label = "DIAMOND games" },
		Colors = { rgb(120, 230, 255) },
	},
	{
		Id = "Title_PartyPro",
		Slot = "Title",
		Name = "Party Pro",
		Description = `Reach GOLD mastery in all {gameCount} games.`,
		Icon = "🏆",
		UnlockStat = { Stat = "MasteryGold", Value = gameCount, Label = "GOLD games" },
		Colors = { rgb(255, 190, 60) },
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
		Description = "A GOLD PASS reward.",
		Icon = "💎",
		GoldLevel = 2,
		Colors = { rgb(255, 230, 140) },
	},
	-- Second shop pass: more for coins.
	{
		Id = "Title_JustVibing",
		Slot = "Title",
		Name = "Just Vibing",
		Description = "No pressure, just fun.",
		Icon = "😎",
		Price = 10,
		Colors = { rgb(170, 230, 255) },
	},
	{
		Id = "Title_LuckyDuck",
		Slot = "Title",
		Name = "Lucky Duck",
		Description = "Somehow it always works out.",
		Icon = "🍀",
		Price = 15,
		Colors = { rgb(140, 240, 140) },
	},
	{
		Id = "Title_SnackAttack",
		Slot = "Title",
		Name = "Snack Attack",
		Description = "Here for the party snacks.",
		Icon = "🍪",
		Price = 25,
		Colors = { rgb(240, 190, 130) },
	},
	{
		Id = "Title_ComebackKid",
		Slot = "Title",
		Name = "Comeback Kid",
		Description = "Never count you out.",
		Icon = "🔁",
		Price = 35,
		Colors = { rgb(120, 210, 255) },
	},
	{
		Id = "Title_Unstoppable",
		Slot = "Title",
		Name = "Unstoppable",
		Description = "Nothing slows you down.",
		Icon = "🚀",
		Price = 50,
		Colors = { rgb(255, 150, 90) },
	},
	{
		Id = "Title_PanicRoyalty",
		Slot = "Title",
		Name = "Panic Royalty",
		Description = "Rules the party with style.",
		Icon = "🏰",
		Price = 80,
		Colors = { rgb(255, 215, 110) },
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
	-- Second shop pass: more for coins.
	{
		Id = "Emote_ThumbsUp",
		Slot = "Emote",
		Name = "Thumbs Up",
		Description = "Nice one!",
		Icon = "👍",
		Price = 10,
		Effect = "Thumbs",
	},
	{
		Id = "Emote_Snow",
		Slot = "Emote",
		Name = "Snow Flurry",
		Description = "A little snow shower.",
		Icon = "❄️",
		Price = 20,
		Effect = "Snow",
	},
	{
		Id = "Emote_Flowers",
		Slot = "Emote",
		Name = "Flower Toss",
		Description = "Throw a handful of petals.",
		Icon = "🌸",
		Price = 25,
		Effect = "Flowers",
	},
	{
		Id = "Emote_Rainbows",
		Slot = "Emote",
		Name = "Rainbow Pop",
		Description = "Rainbows pop out of thin air.",
		Icon = "🌈",
		Price = 30,
		Effect = "Rainbows",
	},
	{
		Id = "Emote_Encore",
		Slot = "Emote",
		Name = "Encore!",
		Description = "Cheer with a burst of streamers.",
		Icon = "👏",
		Price = 35,
		Animation = 507770677, -- the default Cheer, with streamers
		Effect = "Streamers",
	},
	{
		Id = "Emote_DiscoFever",
		Slot = "Emote",
		Name = "Disco Fever",
		Description = "The Disco dance in a cloud of sparkles.",
		Icon = "🕶️",
		Price = 45,
		Animation = 507777268, -- the default Disco dance, with sparkles
		Looped = true,
		Effect = "Sparkles",
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
	-- Second shop pass: more for coins.
	{
		Id = "Victory_Balloons",
		Slot = "Victory",
		Name = "Balloon Release",
		Description = "A bunch of balloons floats up.",
		Icon = "🎈",
		Price = 40,
		Effect = "BalloonFlight",
		Colors = { rgb(255, 90, 110), rgb(255, 210, 70), rgb(90, 180, 255) },
	},
	{
		Id = "Victory_Streamers",
		Slot = "Victory",
		Name = "Streamer Storm",
		Description = "Party streamers shoot up high.",
		Icon = "🎏",
		Price = 45,
		Effect = "StreamerStorm",
		Colors = { rgb(255, 215, 90), rgb(255, 110, 190), rgb(70, 220, 210) },
	},
	{
		Id = "Victory_Spotlight",
		Slot = "Victory",
		Name = "Spotlight",
		Description = "A beam of light, all on you.",
		Icon = "🔦",
		Price = 70,
		Effect = "Spotlight",
	},
	{
		Id = "Victory_Supernova",
		Slot = "Victory",
		Name = "Supernova",
		Description = "A shining ring, stars and fireworks.",
		Icon = "🌟",
		Price = 120,
		Effect = "Supernova",
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

	-- The HALLOWEEN PARTY's free reward track (Shared/Events), in track order: claimed with candy in
	-- the event screen, never sold.
	{
		Id = "Emote_CandyToss",
		Slot = "Emote",
		Name = "Candy Toss",
		Description = "Throw a handful of candy.",
		Icon = "🍭",
		Event = "Halloween2026",
		Effect = "Candy",
	},
	{
		Id = "Title_PumpkinKing",
		Slot = "Title",
		Name = "Pumpkin King",
		Description = "Ruler of the pumpkin patch.",
		Icon = "👑",
		Event = "Halloween2026",
		Colors = { rgb(255, 150, 40) },
	},
	{
		Id = "Elim_Spooked",
		Slot = "Elimination",
		Name = "Spooked",
		Description = "Vanish in purple smoke.",
		Icon = "🕸️",
		Event = "Halloween2026",
		Effect = "Spooky",
	},
	{
		Id = "Hat_Pumpkin",
		Slot = "Hat",
		Name = "Pumpkin Hat",
		Description = "A glowing jack-o'-lantern.",
		Icon = "🎃",
		Event = "Halloween2026",
		Colors = { rgb(255, 128, 24), rgb(255, 186, 64) },
	},
	{
		Id = "Victory_BatBurst",
		Slot = "Victory",
		Name = "Bat Burst",
		Description = "A swarm of bats takes off.",
		Icon = "🦇",
		Event = "Halloween2026",
		Effect = "Bats",
		Colors = { rgb(160, 90, 255), rgb(255, 140, 40), rgb(255, 214, 90) },
	},
	{
		Id = "Trail_CandyCorn",
		Slot = "Trail",
		Name = "Candy Corn",
		Description = "Sweet candy-corn stripes.",
		Icon = "🍬",
		Event = "Halloween2026",
		Colors = { rgb(255, 250, 236), rgb(255, 146, 34), rgb(255, 212, 58) },
	},
	-- Second shop pass: more for coins.
	{
		Id = "Elim_Frozen",
		Slot = "Elimination",
		Name = "Frozen Out",
		Description = "Out in a flurry of snow.",
		Icon = "❄️",
		Price = 25,
		Effect = "Blizzard",
		Colors = { rgb(255, 255, 255), rgb(150, 210, 255) },
	},
	{
		Id = "Elim_Splat",
		Slot = "Elimination",
		Name = "Paint Splat",
		Description = "Splat! A quick splash of paint.",
		Icon = "🎨",
		Price = 25,
		Effect = "Splat",
	},
	{
		Id = "Elim_Ducks",
		Slot = "Elimination",
		Name = "Rubber Ducks",
		Description = "A few rubber ducks bob away.",
		Icon = "🦆",
		Price = 30,
		Effect = "Ducks",
	},
	{
		Id = "Elim_Zap",
		Slot = "Elimination",
		Name = "Zapped",
		Description = "A quick electric zap.",
		Icon = "⚡",
		Price = 40,
		Effect = "Zap",
	},
}
-- The GOLD PASS lane's own cosmetics (Shared/GoldPass) come next.
for _, item in require(script.Parent.GoldPass).Items do
	table.insert(list, item)
end

-- Then every crate season's (Shared/Seasons; owner: "Hollow night comes first ... This will be players
-- first season. I want it to look insane."): the title, the pets, the hats and the effects found in
-- its crates, and the starter pack's trail. Their colours come as {r, g, b} lists; a trail's extra
-- looks (Trail = {...}) become its Style.
local TEXTURES = {
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
}
local function color3(c: { number }): Color3
	return rgb(c[1], c[2], c[3])
end
local Seasons = require(script.Parent.Seasons)
for _, entry in Seasons.Items do
	local colors: { Color3 }? = nil
	if entry.Colors then
		local converted = {}
		for _, c in entry.Colors do
			table.insert(converted, color3(c))
		end
		colors = converted
	end
	local style: { [string]: any }? = nil
	local trail = (entry :: any).Trail
	if trail then
		style = {
			Texture = trail.Texture and TEXTURES[trail.Texture],
			TextureLength = trail.TextureLength,
			Emission = trail.Emission,
			Width = trail.Width,
			Lifetime = trail.Lifetime,
			Glitter = trail.Glitter and color3(trail.Glitter),
			Light = trail.Light and color3(trail.Light),
			Particles = trail.Particles,
		}
	end
	local season = Seasons.SeasonOf(entry.Id)
	table.insert(list, {
		Id = entry.Id,
		Slot = entry.Slot,
		Name = entry.Name,
		Description = entry.Description,
		Icon = entry.Icon,
		Effect = entry.Effect,
		Colors = colors,
		Style = style,
		Season = season and season.Id,
		Look = entry.Look,
	})
end

local Cosmetics = {
	List = list,
	ById = {} :: { [string]: Cosmetic },
	-- Slots a player equips one item into (emotes are not equipped; every owned emote is usable).
	EquipSlots = { "Trail", "Hat", "Title", "Victory", "Elimination", "Pet", "Aura" },
	-- What each slot is called on reward cards ("TRAIL", "KNOCKOUT").
	SlotNames = {
		Trail = "Trail",
		Hat = "Hat",
		Title = "Title",
		Emote = "Emote",
		Victory = "Victory",
		Elimination = "Knockout",
		Pet = "Pet",
		Aura = "Aura",
	} :: { [string]: string },
	ShopTabs = {
		{ Slot = "Trail", Label = "Trails", Icon = "🌈" },
		{ Slot = "Hat", Label = "Hats", Icon = "🎩" },
		{ Slot = "Pet", Label = "Pets", Icon = "🐾" },
		{ Slot = "Aura", Label = "Auras", Icon = "✨" },
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

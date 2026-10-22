-- Limited-time events and double coins weekends: when they run and what they give (owner, asked
-- what keeps players coming back, then: "Can you work on all of that? this wont mess with what the
-- other workers are working on right?"; the idea they were offered: "a Halloween event: candy, free
-- limited rewards like a pumpkin hat, a banner with a countdown, lobby decorations and lighting; and
-- double coins weekends").
--
-- Every date is UTC and sits on a line of its own, so changing one is changing one line. The server
-- (Services/EventService) reads this to decide what's on; Logic/EventLogic has the rules; each
-- device shows the same numbers (Controllers/EventController).
--
-- Double coins come with an event, never on their own (owner, asked about double coins after
-- Halloween: "NO"): an event with DoubleCoinsWeekends pays every round's coins twice on the
-- Saturdays and Sundays (UTC) it's on, with a line of their own on the results card. Once it's
-- over, weekends are ordinary again.
--
-- An event's rewards are cosmetics marked with its Id (Cosmetics.luau: Event = "Halloween2026"):
-- nobody can buy them, and the shop says where they came from after the event too.
-- Leaf module: plain data and a lookup, no requires (Lune reads it: tests/EventLogic.spec.luau).

local Events = {}

export type Event = {
	Id: string, -- the save key (profile.Events[Id]) and the medal it gives
	Name: string, -- in capitals, like every event and game name on screen
	Short: string, -- the lobby chip ("🎃 HALLOWEEN · 9D")
	Label: string, -- where its rewards came from, on the shop's cards after the event
	Icon: string,
	Starts: string, -- "YYYY-MM-DD HH:MM", UTC
	Ends: string, -- "YYYY-MM-DD HH:MM", UTC (the first moment it's over)
	DoubleCoinsWeekends: boolean?, -- 2× coins on the Saturdays and Sundays (UTC) while it's on
	Medal: string?, -- MedalService id, for finishing the reward track
	Candy: { Played: number, TopHalf: number, Win: number, Pumpkin: number, PumpkinsPerDay: number },
	Track: { { Candy: number, Reward: string } }, -- in order; the last step is the whole track
	Headline: string?, -- the track's star reward, shown off on the Rewards screen too
	Decor: string?, -- World/EventDecor's lobby decorations (and each device's lobby look)
	-- The lobby's light on each device while the event is on (colours as { r, g, b }, 0-255).
	Look: {
		Tint: { number }, -- colour grading
		Saturation: number,
		Contrast: number,
		Brightness: number,
		OutdoorAmbient: { number }, -- shadows outdoors
		ShiftTop: { number }, -- sunlit surfaces (Lighting.ColorShift_Top)
	}?,
}

Events.List = {
	{
		Id = "Halloween2026",
		Name = "HALLOWEEN PARTY",
		Short = "HALLOWEEN",
		Label = "HALLOWEEN 2026",
		Icon = "🎃",
		Starts = "2026-10-22 00:00", -- UTC
		Ends = "2026-11-02 00:00", -- UTC: over at midnight after Sunday 1 November
		-- 2× coins on its two weekends: Saturday 24 - Sunday 25 and Saturday 31 October - Sunday
		-- 1 November (UTC). Nothing after it ends.
		DoubleCoinsWeekends = true,
		Medal = "Halloween2026",
		-- Candy: a little from every round, and 3 golden pumpkins hidden in the lobby each day.
		Candy = { Played = 1, TopHalf = 1, Win = 2, Pumpkin = 3, PumpkinsPerDay = 3 },
		-- The free rewards (the Cosmetics with Event = "Halloween2026"), claimed in the event screen.
		Track = {
			{ Candy = 10, Reward = "Emote_CandyToss" },
			{ Candy = 25, Reward = "Title_PumpkinKing" },
			{ Candy = 45, Reward = "Elim_Spooked" },
			{ Candy = 55, Reward = "Hat_Pumpkin" },
			{ Candy = 70, Reward = "Victory_BatBurst" },
			{ Candy = 100, Reward = "Trail_CandyCorn" },
		},
		-- The one to show off: the Rewards screen's road opens with it (owner: "do pumpkin hat now").
		Headline = "Hat_Pumpkin",
		Decor = "Halloween",
		-- Dusk in the lobby: warm light, purple shadows (kept bright enough for phones).
		Look = {
			Tint = { 255, 238, 232 },
			Saturation = 0.08,
			Contrast = 0.06,
			Brightness = -0.02,
			OutdoorAmbient = { 146, 124, 182 },
			ShiftTop = { 90, 46, 14 },
		},
	},
} :: { Event }

-- The event with this Id (on or not).
function Events.Get(id: string?): Event?
	for _, event in Events.List do
		if event.Id == id then
			return event
		end
	end
	return nil
end

return Events

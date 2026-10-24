-- Visual language for every screen: bright toy colors on deep purple glass (design doc §13).
--
-- Brighter buttons (owner: "why are the close menu buttons and the invite friend button so
-- dark?", then "Stop making all of the buttons so dark."): a button never wears the panels'
-- colours. Lavender to Purple is the neutral one (Settings, Skip, Cancel, NO THANKS, a tab that
-- isn't picked), clearly tappable and apart from the menu column's pink, yellow and cyan; Muted to
-- MutedDark is one that can't be used yet (locked, too dear), light enough to read; every close ✕
-- is Red, like the windows' own. (A button's gradient tints its own text too: dark colours turn
-- its words dark.)
--
-- Made by hand, not by a template (owner, with a guide to the tells of an AI-made game: "Can we fix
-- these issues?"): panels are a bright party purple, not the dark navy every generated UI has;
-- outlines are a thick dark ink like a cartoon's (Ink), never a thin see-through white line; titles
-- are in Luckiest Guy, buttons in Fredoka, words in Builder Sans; and the icons are the game's own
-- pictures (UI/Icons), not emoji.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

return {
	Colors = {
		Panel = rgb(82, 48, 182),
		PanelLight = rgb(120, 78, 232),
		PanelDark = rgb(52, 28, 124),
		Card = rgb(98, 62, 200),
		Text = rgb(255, 255, 255),
		TextDim = rgb(220, 210, 252),
		Ink = rgb(34, 16, 58), -- outlines: panels, buttons, icons (the art's own outline is this too)
		Pink = rgb(255, 92, 170),
		Cyan = rgb(80, 205, 255),
		Yellow = rgb(255, 212, 70),
		Green = rgb(110, 230, 140),
		Orange = rgb(255, 150, 60),
		Red = rgb(255, 80, 90),
		Lavender = rgb(185, 150, 255), -- neutral buttons: top
		Purple = rgb(120, 80, 220), -- neutral buttons: bottom
		Muted = rgb(184, 174, 216), -- buttons that can't be used yet: top
		MutedDark = rgb(126, 114, 172), -- buttons that can't be used yet: bottom
		Coin = rgb(255, 205, 50),
		Stroke = rgb(255, 255, 255),
	},
	Fonts = {
		Title = Enum.Font.LuckiestGuy, -- window titles and headlines
		Display = Enum.Font.FredokaOne,
		Bold = Enum.Font.BuilderSansExtraBold,
		Body = Enum.Font.BuilderSansBold,
	},
	Corner = 16,
	-- Coins in running text ("+25 💰"). The 🪙 coin emoji is newer than Roblox's emoji font and
	-- shows as nothing on phones; the HUD draws its coins (UIKit.Coin).
	CoinIcon = "💰",
	-- Layout is authored at this resolution and scaled to the device (see UIKit.AutoScale).
	DesignSize = Vector2.new(1280, 720),
	MinScale = 0.62,
	MaxScale = 1.35,
	-- Every phone in landscape gets MinScale (0.62 points per unit), so phone layouts use these:
	-- a 44 pt touch target and 11 pt text, the smallest that reads well on a phone.
	Touch = {
		Target = 72,
		MinText = 18,
		-- Points from the screen's sides to the profile card and the menu (the edge ScreenGui,
		-- init.client.luau): into the safe area's side insets, still clear of the screen's corners and
		-- of a notch (30 points deep) or the Dynamic Island further down the side.
		Edge = 32,
		-- The menu's 2 x 2 grid in the top right corner (HudController): its top in points, its tiles
		-- and their gap in scaled units. The lobby's chips line up under it (UI/LobbyRibbon).
		Menu = { Top = 8, Tile = 84, Gap = 10 },
	},
}

-- Visual language for every screen: bright toy colors on deep purple glass (design doc §13).
--
-- Brighter buttons (owner: "why are the close menu buttons and the invite friend button so
-- dark?"): a button never wears the panels' colours. Lavender to Purple is the neutral one
-- (Settings, Skip, Cancel, NO THANKS), clearly tappable and apart from the menu column's pink,
-- yellow and cyan; every close ✕ is Red, like the windows' own.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

return {
	Colors = {
		Panel = rgb(44, 30, 92),
		PanelLight = rgb(78, 52, 150),
		PanelDark = rgb(26, 18, 56),
		Card = rgb(60, 42, 120),
		Text = rgb(255, 255, 255),
		TextDim = rgb(205, 195, 240),
		Pink = rgb(255, 92, 170),
		Cyan = rgb(80, 205, 255),
		Yellow = rgb(255, 212, 70),
		Green = rgb(110, 230, 140),
		Orange = rgb(255, 150, 60),
		Red = rgb(255, 80, 90),
		Lavender = rgb(185, 150, 255), -- neutral buttons: top
		Purple = rgb(120, 80, 220), -- neutral buttons: bottom
		Coin = rgb(255, 205, 50),
		Stroke = rgb(255, 255, 255),
	},
	Fonts = {
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
	},
}

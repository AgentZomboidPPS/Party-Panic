-- Prints the lobby obby's jump table: every step of the route with its gap, rise, the flat distance a
-- character's centre has to carry (gap + slack) and what a jump reaches at that rise.
--   lune run tools/checks/obby_jumps
local ParkourCourse = require("../../src/shared/Logic/ParkourCourse")

local function pad(text: string, width: number): string
	return text .. string.rep(" ", math.max(0, width - #text))
end

print(
	`walk {ParkourCourse.WalkSpeed}, jump height {ParkourCourse.JumpHeight}, gravity {ParkourCourse.Gravity}; slack {ParkourCourse.Slack}`
)
print(pad("step", 26) .. "  gap   rise   need  reach  spare")
local worst = math.huge
for _, jump in ParkourCourse.Jumps() do
	local name = pad(`{jump.From.Id} > {jump.To.Id}`, 26)
	if jump.Walk then
		print(`{name}  walk onto the beam`)
		continue
	end
	worst = math.min(worst, jump.Margin)
	print(
		string.format("%s %5.2f %6.2f %6.2f %6.2f %6.2f", name, jump.Gap, jump.Rise, jump.Need, jump.Reach, jump.Margin)
	)
end
print(string.format("least to spare: %.2f studs (the layout keeps at least %.1f)", worst, ParkourCourse.MinMargin))
print(string.format("view deck at %.1f studs", ParkourCourse.Deck.Top))

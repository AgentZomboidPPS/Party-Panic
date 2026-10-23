-- Prints Obby Odyssey's jump table: every way on from every piece with its gap, rise, the flat distance a
-- character's middle has to carry (gap + slack) and what a jump reaches at that rise.
--   lune run tools/checks/obby_odyssey_jumps
local ObbyOdyssey = require("../../src/shared/Logic/ObbyOdyssey")

local function pad(text: string, width: number): string
	return text .. string.rep(" ", math.max(0, width - #text))
end

print(
	`walk {ObbyOdyssey.WalkSpeed}, jump height {ObbyOdyssey.JumpHeight}, gravity {ObbyOdyssey.Gravity}; slack {ObbyOdyssey.Slack}`
)
print(pad("step", 30) .. "  gap   rise   need  reach  spare")
local worst = math.huge
for index = 1, #ObbyOdyssey.Rows - 1 do
	for _, from in ObbyOdyssey.Rows[index] do
		for _, jump in ObbyOdyssey.WaysOn(from) do
			local name = pad(`{from.Id} > {jump.To.Id}`, 30)
			if jump.Walk then
				print(`{name}  walk on`)
				continue
			end
			worst = math.min(worst, jump.Margin)
			print(
				string.format(
					"%s %5.2f %6.2f %6.2f %6.2f %6.2f",
					name,
					jump.Gap,
					jump.Rise,
					jump.Need,
					jump.Reach,
					jump.Margin
				)
			)
		end
	end
end
print(string.format("least to spare: %.2f studs (the layout keeps at least %.1f)", worst, ObbyOdyssey.MinMargin))
print(string.format("route %.0f studs, summit at %.1f", ObbyOdyssey.Length, ObbyOdyssey.Summit.Top))

-- No character ever sits (owner: "Also theres times where I will sit on invisible shit in game. NO
-- mini game should require you to sit."). Two invisible Seats used to catch people, one in every
-- lobby bench and one on each Sand King's throne; both are gone, nothing in the game sits anyone
-- down, and tests/NoSeats.spec.luau keeps Seats out of the code. This is the guard behind that: a
-- character can't take the Seated state at all, so a Seat that turns up anyway (a new prop, a
-- model from somewhere) can't catch anyone. Turning the state off isn't enough on its own: a Seat
-- that grabs a humanoid still welds it to itself (its "SeatWeld"), and checked on a test server, the
-- weld and the seat's Occupant stayed with Sit false, so the character would hang on the seat
-- standing up: latched onto something invisible. So whenever Sit or SeatPart changes, the guard
-- breaks the weld that holds this character to its seat and sets Sit back to false (on that test
-- server the weld went, the seat let go and Sit stayed false, both for Seat:Sit and for a bare
-- SeatWeld like the one a touch leaves).
--
-- A humanoid's states change only on the machine that simulates it, so Guard runs there: on each
-- player's own device for their character (Controllers/MovementController) and on the server for
-- the bots (Services/NoSitService, which also watches players' characters from the server's side).
-- The rides that look seated, Bobsled Run's sleds and Minecart Mayhem's carts, pose their riders
-- themselves (PlatformStand and their own joint poses), not with the Seated state, so this leaves
-- them alone; Shark Bait's stuck watchdog still frees a character held by any other state.

local NoSitting = {}

-- Lets go of any seat holding this humanoid: breaks the seat's weld to the character and stands it up.
local function letGo(character: Model, humanoid: Humanoid)
	local seat = humanoid.SeatPart
	if seat then
		for _, child in seat:GetChildren() do
			if child.Name == "SeatWeld" and child:IsA("JointInstance") then
				local held = (child :: JointInstance).Part1
				if held and held:IsDescendantOf(character) then
					child:Destroy()
				end
			end
		end
	end
	if humanoid.Sit then
		humanoid.Sit = false
	end
end

-- Turns sitting off for a character's humanoid, waiting a moment for it on a fresh character.
function NoSitting.Guard(character: Model)
	task.spawn(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			local found = character:WaitForChild("Humanoid", 10)
			humanoid = if found and found:IsA("Humanoid") then found else nil
		end
		if not humanoid then
			return
		end
		local guarded = humanoid :: Humanoid
		guarded:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
		-- (Deferred: a seat sets Sit, SeatPart and its weld one after another.)
		local function check()
			task.defer(letGo, character, guarded)
		end
		check()
		guarded:GetPropertyChangedSignal("Sit"):Connect(check)
		guarded:GetPropertyChangedSignal("SeatPart"):Connect(check)
	end)
end

return NoSitting

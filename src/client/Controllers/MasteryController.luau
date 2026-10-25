-- Game Mastery's window in the GOALS hub (owner: "I also want to mastery tab to be in the season
-- button I want to rename that button to better reflect everything in it though"): the 🏆 MASTERY tab
-- beside the season's crates, the event and the quests (UI/HubTabs), drawing the same wall of every
-- game's rank as the Rewards screen's MASTERY tab (UI/MasteryWall). State.OpenScreen:Fire("Mastery")
-- opens it (a new rank's card does).

local Modal = require(script.Parent.Parent.UI.Modal)
local HubTabs = require(script.Parent.Parent.UI.HubTabs)
local MasteryWall = require(script.Parent.Parent.UI.MasteryWall)
local State = require(script.Parent.Parent.State)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local MasteryController = {}

local modal: Modal.Modal
local body: Frame

local function render(keep: Vector2?)
	if not modal.IsOpen then
		return
	end
	body:ClearAllChildren()
	if not State.Profile then
		return
	end
	MasteryWall.Render(body, keep, function()
		local list = body:FindFirstChildOfClass("ScrollingFrame")
		render(if list then list.CanvasPosition else nil)
	end)
end

function MasteryController.Start(context)
	modal = Modal.new(context.Overlay, "Mastery", "🏆", Vector2.new(980, 600)) -- (the GOALS hub's size)
	HubTabs.Attach(modal, "Mastery")
	body = UIKit.new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = modal.Content,
	})
	State.OpenScreen:Connect(function(name)
		if name == "Mastery" then
			modal:Toggle()
		end
	end)
	modal.Opened:Connect(function()
		render()
	end)
	modal.Closed:Connect(function()
		body:ClearAllChildren()
	end)
	State.ProfileChanged:Connect(function()
		if modal.IsOpen then
			local list = body:FindFirstChildOfClass("ScrollingFrame")
			render(if list then list.CanvasPosition else nil) -- (scrolled where it was)
		end
	end)
end

return MasteryController

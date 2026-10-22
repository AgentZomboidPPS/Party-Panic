-- Invite friends (owner, asked what keeps players coming back, then: "Can you work on all of that?
-- this wont mess with what the other workers are working on right?"; the idea as given: "Friends:
-- an invite button, a coin bonus for playing with friends, beat-a-friend moments"): the lobby's
-- invite chip (UI/LobbyRibbon, priority 3) opens Roblox's invite prompt. Its words say what a
-- friend is worth, "👋 INVITE +1 💰" (a round played with a friend pays a coin more: Services/
-- FriendsService), or just "👋 INVITE" when the row has no room for that.
-- It only shows for players who can send invites (SocialService:CanSendGameInviteAsync). The
-- experience is private, so only people with access to it can join, but invites still work for
-- them.
-- SocialService here is Roblox's, not the game's server module of that name (Services/
-- SocialService: emotes, the daily reward...).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService") -- Roblox's invites

local Shared = ReplicatedStorage.Shared
local FriendLogic = require(Shared.Logic.FriendLogic)
local GameState = require(Shared.GameState)

local LobbyRibbon = require(script.Parent.Parent.UI.LobbyRibbon)
local Theme = require(script.Parent.Parent.UI.Theme)

local InviteController = {}

local ICON = "👋"
local WORDS = `INVITE +{FriendLogic.Bonus} {Theme.CoinIcon}` -- with what a friend is worth
local SHORT_WORDS = "INVITE" -- when the row has no room for that
local ASK_AGAIN = { 10, 30, 90 } -- seconds before asking Roblox again when it doesn't answer
local PROMPT_GAP = 1 -- seconds: a double tap opens one prompt

local chip: LobbyRibbon.Chip? = nil
local canInvite = false
local lastPrompt = -math.huge

-- The chip's words: the long ones if the row has room for them, else the short ones; none (off the
-- row) for a player who can't send invites.
local function refresh()
	local current = chip
	if not current then
		return
	elseif not canInvite then
		current:Set("", "")
		return
	end
	current:Set(ICON, WORDS)
	if not current.Button.Visible then
		current:Set(ICON, SHORT_WORDS)
	end
end

local function invite()
	local now = os.clock()
	if now - lastPrompt < PROMPT_GAP then
		return
	end
	lastPrompt = now
	local ok, err = pcall(SocialService.PromptGameInvite, SocialService, Players.LocalPlayer)
	if not ok then
		warn(`[InviteController] the invite prompt didn't open: {err}`)
	end
end

function InviteController.Start(context)
	local added = LobbyRibbon.Add(context, { Name = "Invite", Priority = 3, OnClick = invite })
	chip = added
	-- A chip ahead of it that grew can push the long words off the row; the short ones may still fit.
	added.Button:GetPropertyChangedSignal("Visible"):Connect(function()
		if canInvite and not added.Button.Visible and added.Text ~= SHORT_WORDS then
			refresh()
		end
	end)
	-- Every phase change gives the long words another go (a chip ahead of it may have gone).
	GameState.Changed("Phase", function()
		refresh()
	end)
	-- Whether this player can send invites at all (it asks Roblox, so it can fail: ask again later).
	local function askRoblox(): boolean
		local ok, result = pcall(SocialService.CanSendGameInviteAsync, SocialService, Players.LocalPlayer)
		if ok then
			canInvite = result == true
			refresh()
		end
		return ok
	end
	task.spawn(function()
		if askRoblox() then
			return
		end
		for _, seconds in ASK_AGAIN do
			task.wait(seconds)
			if askRoblox() then
				return
			end
		end
	end)
end

return InviteController

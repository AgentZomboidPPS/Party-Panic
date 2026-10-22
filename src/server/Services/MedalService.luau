-- Medals: one for winning each game and a few big ones, kept in the profile (and awarded as
-- Roblox badges once their ids exist); the medal wall in the lobby shows them.
-- (owner, asked what keeps players coming back, then: "Can you work on all of that?")
-- Placeholder: the feature is being built.
--
-- Other features give their medal with MedalService.Award(player, id):
--   "CupChampion"   CupService: won a Party Cup
--   "HallOfFame"    LeaderboardService: finished a week in the top three
--   "Halloween2026" EventService: took part in the Halloween 2026 party
--   "FriendsParty"  FriendsService: played a round with a friend

local MedalService = {}

-- Gives `player` the medal `id` (a real player's, never a bot's) the first time; later calls do
-- nothing. Safe to call from anywhere on the server.
function MedalService.Award(_player: Player, _id: string) end

function MedalService.Init() end

function MedalService.Start() end

return MedalService

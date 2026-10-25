-- Game Mastery (owner: "Let's build it. 1 yes 2 gold pass should help a little. 3 yes"; Config.Mastery,
-- Logic/MasteryLogic): what a round pays, when a win counts, the ranks and their rewards, the goal
-- and bar texts, the credit for past rounds, and the Spotlight.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local TestKit = require("./TestKit")
local MasteryLogic = require("../src/shared/Logic/MasteryLogic")

-- (Config uses Roblox's types: loaded with them.)
local Config = luau.load(fs.readFile("src/shared/Config.luau"), {
	debugName = "Config",
	environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3 },
})()

local test, expectEqual, expectTrue = TestKit.test, TestKit.expectEqual, TestKit.expectTrue

local ranks = Config.Mastery.Ranks
local points = Config.Mastery.Points

test("Mastery: a round pays by place, a team game by the team's result", function()
	local function at(place: number, count: number): number
		return MasteryLogic.Points({ Place = place, PlayerCount = count }, points)
	end
	expectEqual(at(1, 12), 5)
	expectEqual(at(2, 12), 4)
	expectEqual(at(3, 12), 3)
	expectEqual(at(6, 12), 2, "top half")
	expectEqual(at(7, 12), 1, "played it to the end")
	expectEqual(at(1, 1), 5, "a round alone still pays a win")
	expectEqual(MasteryLogic.Points({ Place = 1, PlayerCount = 8, Team = true, Won = true }, points), 4)
	expectEqual(MasteryLogic.Points({ Place = 5, PlayerCount = 8, Team = true, Won = false }, points), 1)
	-- The Spotlight doubles the round; the GOLD PASS adds 1 for a good round only.
	expectEqual(MasteryLogic.Earned(4, true, false, true, 2, 1), 8)
	local total, extra, bonus = MasteryLogic.Earned(4, true, true, true, 2, 1)
	expectEqual(total, 9)
	expectEqual(extra, 4)
	expectEqual(bonus, 1)
	expectEqual(MasteryLogic.Earned(1, false, true, false, 2, 1), 1, "no GOLD PASS bonus for the bottom half")
end)

test("Mastery: a win counts for the top ranks with 3 real players, never in a private server", function()
	expectEqual(MasteryLogic.ProvenWin(true, 3, false, 3), true)
	expectEqual(MasteryLogic.ProvenWin(true, 2, false, 3), false, "a win among bots")
	expectEqual(MasteryLogic.ProvenWin(true, 12, true, 3), false, "a private server")
	expectEqual(MasteryLogic.ProvenWin(false, 12, false, 3), false)
end)

test("Mastery: ranks climb with points, the top ones wait for wins, and each pays once", function()
	local mastery = {}
	local before, after = MasteryLogic.Record(mastery, "HexMeltdown", 5, false, ranks)
	expectEqual(before, 0)
	expectEqual(after, 1, "BRONZE after the first round")
	_, after = MasteryLogic.Record(mastery, "HexMeltdown", 15, false, ranks)
	expectEqual(after, 3, "20 points: GOLD (SILVER on the way)")
	expectEqual(mastery.HexMeltdown.N, 2)
	local coins, keys, crates = MasteryLogic.Rewards(ranks, 1, 3)
	expectEqual(coins, 35)
	expectEqual(keys, 3)
	expectEqual(crates, 0)
	-- 60 points but no wins: DIAMOND waits for 3.
	mastery.HexMeltdown.P = 60
	expectEqual(MasteryLogic.RankOf(mastery.HexMeltdown, ranks), 3)
	local progress = MasteryLogic.Progress(mastery.HexMeltdown, ranks)
	expectEqual(progress.Short, "Wins")
	expectEqual(MasteryLogic.Goal(progress), "3 wins to DIAMOND")
	expectEqual(MasteryLogic.BarText(progress), "WINS 0/3")
	for _ = 1, 3 do
		MasteryLogic.Record(mastery, "HexMeltdown", 0, true, ranks)
	end
	expectEqual(MasteryLogic.RankOf(mastery.HexMeltdown, ranks), 4, "DIAMOND")
	-- A LEGEND's points without its wins stay DIAMOND; with them, LEGEND, the top.
	mastery.HexMeltdown.P = 200
	expectEqual(MasteryLogic.RankOf(mastery.HexMeltdown, ranks), 4)
	mastery.HexMeltdown.W = 10
	expectEqual(MasteryLogic.RankOf(mastery.HexMeltdown, ranks), 5)
	local top = MasteryLogic.Progress(mastery.HexMeltdown, ranks)
	expectEqual(MasteryLogic.Goal(top), "MAX RANK")
	expectEqual(MasteryLogic.BarText(top), "MAX")
	-- On the way to SILVER: a bar from BRONZE's 1 point to SILVER's 8.
	local early = MasteryLogic.Progress({ P = 4, W = 0, N = 2 }, ranks)
	expectEqual(MasteryLogic.Goal(early), "4 pts to SILVER")
	expectEqual(MasteryLogic.BarText(early), "4/8")
	expectTrue(math.abs(early.Fraction - 3 / 7) < 1e-9)
	expectEqual(MasteryLogic.Goal(MasteryLogic.Progress(nil, ranks)), "1 pt to BRONZE")
end)

test("Mastery: past rounds are credited once, with a win for a game medal, and nothing is paid", function()
	local data = {
		Stats = { ModePlays = { HexMeltdown = 9, FireRope = 1, OldGame = 40 } },
		Medals = { WinHexMeltdown = 20000 },
	}
	local known = { HexMeltdown = true, FireRope = true }
	local medalOf = function(gameId: string): string
		return "Win" .. gameId
	end
	local credited = MasteryLogic.Load(data, ranks, known, medalOf)
	expectEqual(credited, 3, "SILVER (2 ranks) at Hex Meltdown and BRONZE at Fire Rope")
	expectEqual(data.Mastery.HexMeltdown.P, 9)
	expectEqual(data.Mastery.HexMeltdown.W, 1)
	expectEqual(data.Mastery.FireRope.N, 1)
	expectEqual(data.Mastery.OldGame, nil, "a game that's gone")
	expectEqual(data.MasteryIntro.Ranks, 3)
	-- Loading again changes nothing, even after more rounds.
	data.Stats.ModePlays.HexMeltdown = 30
	expectEqual(MasteryLogic.Load(data, ranks, known, medalOf), 0)
	expectEqual(data.Mastery.HexMeltdown.P, 9)
	-- Broken saves are made safe; the counts are worked out on every load.
	data.Mastery.HexMeltdown.P = 25
	data.Mastery.Broken = "x"
	data.Mastery.FireRope.W = -3
	MasteryLogic.Load(data, ranks, known, medalOf)
	expectEqual(data.Mastery.Broken, nil)
	expectEqual(data.Mastery.FireRope.W, 0)
	expectEqual(data.Stats.MasteryGold, 1)
	expectEqual(data.Stats.MasteryDiamond, 0)
end)

test("Mastery: the Spotlight is the same everywhere for a day, and changes from day to day", function()
	local ids = { "A", "B", "C", "D", "E", "F", "G", "H" }
	local today = MasteryLogic.Spotlight(20000, ids, 3)
	expectEqual(#today, 3)
	local shuffled = { "H", "G", "F", "E", "D", "C", "B", "A" }
	expectEqual(table.concat(MasteryLogic.Spotlight(20000, shuffled, 3), ","), table.concat(today, ","))
	local differs = false
	for day = 20001, 20010 do
		if table.concat(MasteryLogic.Spotlight(day, ids, 3), ",") ~= table.concat(today, ",") then
			differs = true
		end
	end
	expectTrue(differs, "other days pick other games")
	expectEqual(#MasteryLogic.Spotlight(1, { "A" }, 3), 1)
end)

return nil

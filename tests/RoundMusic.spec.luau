-- Checks the mini-games' own round tracks (src/shared/RoundMusic.luau, written by
-- tools/music/round_music.py pack): every track belongs to a mini-game, its pack exists, its intro
-- covers the rules card and the 3-2-1 (Config: RulesTime + CountdownTime) so the drop lands on GO,
-- there's at least the round's Duration of music after it, and tracks in one pack don't overlap.
local fs = require("@lune/fs")

local TestKit = require("./TestKit")
local RoundMusic = require("../src/shared/RoundMusic")

local test, expectTrue = TestKit.test, TestKit.expectTrue

local PREPARING = 13 -- Config.Session.RulesTime (10) + CountdownTime (3)

local definitions = fs.readFile("src/shared/GameDefinitions.luau")
local durations = {}
for id, body in string.gmatch(definitions, '\n\t\tId = "(%w+)",(.-)\n\t}') do
	durations[id] = tonumber(string.match(body, "Duration = (%d+)"))
end

local config = fs.readFile("src/shared/Config.luau")
local rules = tonumber(string.match(config, "RulesTime = (%d+)"))
local countdown = tonumber(string.match(config, "CountdownTime = (%d+)"))

test("Preparing is still as long as the intros expect", function()
	expectTrue(
		rules ~= nil and countdown ~= nil and rules + countdown == PREPARING,
		"RulesTime + CountdownTime changed"
	)
end)

test("every round track fits its mini-game", function()
	for id, track in RoundMusic.Tracks :: any do
		local duration = durations[id]
		expectTrue(duration ~= nil, `{id} has a track but no GameDefinitions entry`)
		expectTrue((RoundMusic.Packs :: any)[track.Pack] ~= nil, `{id}'s pack {track.Pack} isn't listed`)
		expectTrue(track.Intro >= PREPARING - 1e-6, `{id}'s intro is {track.Intro}s, shorter than Preparing`)
		if duration then
			expectTrue(track.Length - track.Intro >= duration, `{id} has less music after the intro than its round`)
		end
	end
end)

test("tracks in one pack don't overlap", function()
	local byPack = {}
	for id, track in RoundMusic.Tracks :: any do
		byPack[track.Pack] = byPack[track.Pack] or {}
		table.insert(byPack[track.Pack], { Id = id, Start = track.Start, Finish = track.Start + track.Length })
	end
	for pack, list in byPack do
		table.sort(list, function(a, b)
			return a.Start < b.Start
		end)
		for index = 2, #list do
			expectTrue(
				list[index].Start >= list[index - 1].Finish,
				`{list[index].Id} overlaps {list[index - 1].Id} in {pack}`
			)
		end
	end
end)

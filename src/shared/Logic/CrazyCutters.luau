-- Crazy Cutters' rules as plain math, shared by the server (which scores every cut) and the client
-- (which shows a player their own score live while they cut, and draws everyone's boards).
--
-- A shape is a closed outline of evenly spaced points in board coordinates (u to the right, v away
-- from the player, in studs; the shape's middle is 0, 0). It is traced from its first point in the
-- order the points are listed. The outlines come from the cookie meshes' generator
-- (tools/meshgen/props/CrazyCutters.py), so the dotted line, the cookie that pops out and the giant
-- cutters in the arena always have exactly the same shape.
--
-- A cut is scored by a Tracker fed the cutter's positions one by one:
--   * Precision: each point of the outline earns full credit if the cutter first passes it within
--     FULL studs and none beyond COVER (later passes don't change it, so going back over a stretch
--     can't raise the score); stretches cut away from the line count against it by their length.
--   * Coverage: the share of the outline's points the cutter passed within COVER studs of.
--   score = coverage x precision, as a percentage. Nothing here touches instances.

local CrazyCutters = {}

CrazyCutters.FULL = 0.15 -- full credit this close to the line (studs)
CrazyCutters.ZERO = 1.2 -- no credit this far from it
CrazyCutters.COVER = 0.75 -- an outline point counts as cut when the cutter passes this close
CrazyCutters.COVER_NEEDED = 0.98 -- this share of the points counts as the whole outline
CrazyCutters.DONE_RADIUS = 1.0 -- a full lap ends when the cutter is back this close to the start
CrazyCutters.MAX_SPEED = 16 -- the cutter's top speed (studs/s); the server allows a little more
CrazyCutters.LIMIT = 7 -- the cutter stays on the dough: |u|, |v| <= LIMIT
CrazyCutters.SAMPLE_GAP = 0.03 -- at least this many seconds between two cutter positions
CrazyCutters.MAX_CHUNK = 40 -- positions per message

-- BEGIN GENERATED SHAPES (tools/meshgen/props/CrazyCutters.py writes this block)
CrazyCutters.Shapes = {
	{
		Id = "Star",
		Tier = 1,
		Length = 31.0,
		Points = "0.01 4.26 0.25 4.18 0.43 3.99 0.56 3.75 0.66 3.49 0.77 3.23 0.87 2.98 0.97 2.72 1.07 2.46 1.18 2.21 1.28 1.95 1.43 1.73 1.65 1.59 1.93 1.53 2.21 1.51 2.51 1.49 2.80 1.47 3.09 1.45 3.38 1.43 3.67 1.41 3.96 1.38 4.21 1.29 4.40 1.11 4.46 0.86 4.38 0.62 4.20 0.40 3.98 0.21 3.76 0.03 3.54 -0.16 3.32 -0.35 3.10 -0.53 2.87 -0.72 2.65 -0.91 2.48 -1.12 2.42 -1.37 2.45 -1.64 2.52 -1.91 2.58 -2.18 2.65 -2.45 2.72 -2.73 2.79 -3.00 2.85 -3.27 2.92 -3.54 2.94 -3.82 2.85 -4.06 2.66 -4.23 2.41 -4.28 2.15 -4.20 1.91 -4.07 1.67 -3.92 1.43 -3.77 1.20 -3.62 0.96 -3.47 0.72 -3.33 0.48 -3.18 0.24 -3.04 -0.01 -2.98 -0.26 -3.05 -0.51 -3.19 -0.74 -3.34 -0.98 -3.49 -1.22 -3.63 -1.46 -3.78 -1.70 -3.93 -1.93 -4.08 -2.18 -4.21 -2.44 -4.28 -2.68 -4.22 -2.86 -4.04 -2.94 -3.79 -2.91 -3.52 -2.85 -3.24 -2.78 -2.97 -2.71 -2.70 -2.65 -2.43 -2.58 -2.16 -2.51 -1.89 -2.44 -1.61 -2.41 -1.34 -2.49 -1.10 -2.67 -0.89 -2.89 -0.70 -3.12 -0.51 -3.34 -0.33 -3.56 -0.15 -3.78 0.04 -4.01 0.23 -4.22 0.42 -4.40 0.64 -4.47 0.88 -4.39 1.13 -4.19 1.30 -3.93 1.38 -3.64 1.41 -3.35 1.43 -3.06 1.45 -2.77 1.47 -2.48 1.49 -2.19 1.51 -1.90 1.53 -1.63 1.60 -1.41 1.75 -1.27 1.97 -1.17 2.23 -1.07 2.49 -0.96 2.74 -0.86 3.00 -0.75 3.26 -0.65 3.51 -0.55 3.77 -0.42 4.01 -0.23 4.20",
	},
	{
		Id = "Heart",
		Tier = 1,
		Length = 30.9,
		Points = "2.56 4.38 2.85 4.37 3.13 4.33 3.40 4.26 3.66 4.16 3.91 4.03 4.14 3.88 4.37 3.71 4.58 3.50 4.76 3.28 4.92 3.04 5.05 2.79 5.15 2.53 5.22 2.26 5.26 1.98 5.26 1.69 5.24 1.40 5.18 1.12 5.10 0.85 5.00 0.60 4.87 0.35 4.73 0.11 4.57 -0.12 4.39 -0.35 4.21 -0.58 4.01 -0.79 3.80 -1.00 3.58 -1.21 3.37 -1.40 3.15 -1.60 2.93 -1.80 2.71 -1.99 2.49 -2.18 2.26 -2.37 2.04 -2.55 1.82 -2.75 1.60 -2.95 1.39 -3.15 1.17 -3.36 0.97 -3.57 0.77 -3.79 0.58 -4.01 0.38 -4.22 0.15 -4.35 -0.11 -4.36 -0.36 -4.24 -0.56 -4.04 -0.75 -3.82 -0.94 -3.60 -1.15 -3.38 -1.36 -3.17 -1.58 -2.97 -1.80 -2.77 -2.02 -2.58 -2.24 -2.39 -2.46 -2.20 -2.68 -2.01 -2.90 -1.82 -3.12 -1.63 -3.34 -1.43 -3.56 -1.23 -3.77 -1.03 -3.98 -0.82 -4.18 -0.60 -4.37 -0.38 -4.55 -0.15 -4.71 0.08 -4.86 0.32 -4.98 0.57 -5.09 0.82 -5.18 1.09 -5.24 1.36 -5.26 1.65 -5.26 1.94 -5.22 2.23 -5.16 2.50 -5.07 2.76 -4.94 3.01 -4.79 3.25 -4.61 3.47 -4.40 3.68 -4.17 3.87 -3.94 4.02 -3.69 4.14 -3.43 4.25 -3.16 4.32 -2.88 4.37 -2.59 4.38 -2.30 4.37 -2.02 4.32 -1.75 4.24 -1.50 4.14 -1.25 4.00 -1.02 3.84 -0.80 3.64 -0.59 3.43 -0.39 3.24 -0.15 3.11 0.12 3.10 0.36 3.21 0.57 3.40 0.78 3.62 0.99 3.81 1.22 3.98 1.46 4.12 1.72 4.24 1.98 4.32 2.26 4.36",
	},
	{
		Id = "Fish",
		Tier = 2,
		Length = 28.7,
		Points = "-4.88 -0.31 -4.85 -0.02 -4.79 0.25 -4.70 0.52 -4.58 0.77 -4.44 1.01 -4.26 1.23 -4.06 1.45 -3.84 1.65 -3.61 1.82 -3.38 1.97 -3.13 2.11 -2.88 2.23 -2.62 2.33 -2.36 2.41 -2.09 2.49 -1.82 2.56 -1.57 2.68 -1.33 2.82 -1.10 2.98 -0.86 3.14 -0.62 3.28 -0.37 3.34 -0.13 3.25 0.06 3.05 0.21 2.82 0.37 2.59 0.59 2.41 0.84 2.29 1.09 2.18 1.34 2.06 1.58 1.92 1.82 1.76 2.04 1.58 2.25 1.37 2.45 1.16 2.67 0.97 2.92 0.89 3.17 0.96 3.40 1.11 3.63 1.30 3.85 1.48 4.08 1.66 4.32 1.78 4.57 1.77 4.76 1.61 4.82 1.37 4.77 1.10 4.69 0.84 4.61 0.57 4.53 0.30 4.45 0.04 4.38 -0.23 4.37 -0.51 4.44 -0.79 4.52 -1.05 4.61 -1.31 4.69 -1.58 4.77 -1.85 4.82 -2.11 4.77 -2.36 4.58 -2.53 4.34 -2.54 4.09 -2.43 3.87 -2.25 3.64 -2.07 3.42 -1.89 3.19 -1.73 2.93 -1.65 2.68 -1.72 2.47 -1.90 2.27 -2.12 2.05 -2.33 1.83 -2.51 1.60 -2.67 1.36 -2.81 1.11 -2.94 0.85 -3.05 0.59 -3.14 0.33 -3.22 0.05 -3.28 -0.23 -3.33 -0.51 -3.36 -0.81 -3.37 -1.10 -3.37 -1.39 -3.36 -1.67 -3.32 -1.95 -3.27 -2.23 -3.21 -2.49 -3.13 -2.76 -3.04 -3.01 -2.93 -3.26 -2.80 -3.50 -2.66 -3.73 -2.50 -3.95 -2.31 -4.16 -2.10 -4.35 -1.88 -4.51 -1.65 -4.65 -1.40 -4.75 -1.15 -4.82 -0.88 -4.87 -0.59",
	},
	{
		Id = "Ghost",
		Tier = 2,
		Length = 33.9,
		Points = "-0.01 4.92 0.29 4.92 0.58 4.88 0.85 4.83 1.13 4.77 1.39 4.68 1.65 4.58 1.90 4.46 2.15 4.32 2.38 4.16 2.61 3.99 2.83 3.79 3.04 3.58 3.23 3.36 3.39 3.13 3.54 2.89 3.67 2.64 3.79 2.39 3.89 2.13 3.97 1.86 4.03 1.59 4.06 1.30 4.09 1.01 4.14 0.73 4.28 0.51 4.51 0.37 4.77 0.27 5.01 0.14 5.18 -0.07 5.24 -0.33 5.19 -0.60 5.07 -0.85 4.88 -1.07 4.66 -1.25 4.43 -1.42 4.24 -1.61 4.14 -1.87 4.11 -2.16 4.11 -2.45 4.11 -2.75 4.11 -3.05 4.11 -3.36 4.10 -3.65 4.05 -3.93 3.96 -4.19 3.80 -4.43 3.59 -4.63 3.36 -4.78 3.09 -4.88 2.81 -4.92 2.52 -4.91 2.25 -4.84 2.01 -4.70 1.78 -4.54 1.53 -4.40 1.28 -4.39 1.03 -4.50 0.80 -4.67 0.56 -4.81 0.29 -4.89 0.01 -4.92 -0.28 -4.89 -0.55 -4.81 -0.79 -4.68 -1.02 -4.51 -1.27 -4.39 -1.52 -4.40 -1.77 -4.53 -2.00 -4.70 -2.24 -4.83 -2.51 -4.90 -2.80 -4.92 -3.08 -4.88 -3.34 -4.78 -3.58 -4.64 -3.79 -4.44 -3.95 -4.20 -4.05 -3.95 -4.10 -3.67 -4.11 -3.37 -4.11 -3.07 -4.11 -2.77 -4.11 -2.47 -4.11 -2.17 -4.14 -1.88 -4.24 -1.62 -4.42 -1.43 -4.65 -1.26 -4.88 -1.08 -5.06 -0.86 -5.19 -0.62 -5.24 -0.35 -5.18 -0.08 -5.02 0.13 -4.78 0.27 -4.52 0.36 -4.29 0.50 -4.14 0.72 -4.09 1.00 -4.06 1.29 -4.02 1.57 -3.96 1.85 -3.89 2.12 -3.79 2.38 -3.67 2.63 -3.55 2.88 -3.40 3.12 -3.23 3.35 -3.04 3.57 -2.84 3.79 -2.62 3.98 -2.39 4.15 -2.15 4.31 -1.91 4.45 -1.66 4.57 -1.40 4.68 -1.14 4.76 -0.87 4.83 -0.59 4.88 -0.30 4.91",
	},
	{
		Id = "Moon",
		Tier = 2,
		Length = 31.8,
		Points = "-4.25 -1.55 -4.33 -1.28 -4.39 -1.01 -4.45 -0.73 -4.48 -0.45 -4.50 -0.16 -4.51 0.13 -4.50 0.42 -4.48 0.71 -4.45 0.99 -4.39 1.27 -4.31 1.54 -4.23 1.80 -4.13 2.06 -4.02 2.31 -3.90 2.56 -3.76 2.80 -3.61 3.04 -3.44 3.27 -3.25 3.49 -3.06 3.71 -2.84 3.92 -2.62 4.11 -2.40 4.28 -2.17 4.45 -1.93 4.59 -1.68 4.73 -1.43 4.85 -1.18 4.95 -0.92 5.04 -0.65 5.07 -0.41 4.98 -0.24 4.79 -0.20 4.54 -0.28 4.28 -0.43 4.04 -0.58 3.81 -0.72 3.57 -0.84 3.32 -0.95 3.06 -1.03 2.80 -1.11 2.53 -1.16 2.25 -1.20 1.97 -1.21 1.67 -1.20 1.38 -1.18 1.09 -1.15 0.80 -1.09 0.53 -1.02 0.26 -0.93 -0.01 -0.82 -0.26 -0.70 -0.51 -0.56 -0.75 -0.40 -0.98 -0.23 -1.21 -0.03 -1.43 0.18 -1.64 0.40 -1.83 0.62 -2.00 0.86 -2.16 1.10 -2.29 1.35 -2.42 1.61 -2.52 1.87 -2.61 2.14 -2.68 2.41 -2.74 2.70 -2.77 2.99 -2.79 3.29 -2.79 3.58 -2.76 3.86 -2.74 4.13 -2.77 4.35 -2.91 4.45 -3.15 4.42 -3.40 4.28 -3.63 4.07 -3.84 3.85 -4.02 3.62 -4.19 3.38 -4.34 3.14 -4.48 2.89 -4.61 2.64 -4.71 2.38 -4.81 2.11 -4.89 1.84 -4.97 1.57 -5.03 1.29 -5.07 1.00 -5.09 0.70 -5.09 0.41 -5.09 0.13 -5.07 -0.16 -5.03 -0.43 -4.97 -0.71 -4.91 -0.97 -4.83 -1.23 -4.73 -1.49 -4.63 -1.74 -4.51 -1.98 -4.37 -2.21 -4.22 -2.45 -4.05 -2.67 -3.87 -2.89 -3.68 -3.10 -3.47 -3.30 -3.25 -3.48 -3.02 -3.64 -2.79 -3.79 -2.56 -3.93 -2.31 -4.05 -2.06 -4.15 -1.81",
	},
	{
		Id = "Mushroom",
		Tier = 3,
		Length = 33.8,
		Points = "0.05 4.85 0.35 4.83 0.64 4.81 0.92 4.77 1.20 4.72 1.48 4.67 1.74 4.58 2.00 4.49 2.26 4.39 2.51 4.27 2.76 4.15 3.00 4.01 3.24 3.85 3.47 3.68 3.69 3.50 3.91 3.30 4.11 3.09 4.30 2.86 4.47 2.63 4.63 2.40 4.76 2.15 4.88 1.90 4.98 1.65 5.07 1.38 5.14 1.11 5.20 0.84 5.23 0.55 5.22 0.27 5.12 0.01 4.92 -0.18 4.68 -0.32 4.42 -0.41 4.16 -0.50 3.89 -0.57 3.61 -0.63 3.33 -0.68 3.05 -0.73 2.77 -0.77 2.49 -0.81 2.21 -0.86 1.95 -0.96 1.77 -1.15 1.69 -1.40 1.69 -1.69 1.72 -1.98 1.75 -2.27 1.77 -2.56 1.79 -2.85 1.81 -3.14 1.83 -3.43 1.86 -3.72 1.88 -4.01 1.86 -4.29 1.75 -4.55 1.55 -4.74 1.29 -4.83 1.00 -4.85 0.70 -4.85 0.40 -4.85 0.10 -4.85 -0.20 -4.85 -0.50 -4.85 -0.80 -4.85 -1.10 -4.84 -1.38 -4.80 -1.63 -4.67 -1.80 -4.46 -1.87 -4.19 -1.87 -3.91 -1.85 -3.61 -1.83 -3.32 -1.81 -3.03 -1.78 -2.74 -1.75 -2.45 -1.73 -2.16 -1.71 -1.87 -1.69 -1.58 -1.72 -1.30 -1.82 -1.07 -2.04 -0.91 -2.31 -0.84 -2.59 -0.80 -2.88 -0.76 -3.16 -0.72 -3.43 -0.67 -3.71 -0.61 -3.98 -0.54 -4.25 -0.47 -4.52 -0.38 -4.77 -0.27 -5.00 -0.12 -5.16 0.10 -5.23 0.37 -5.22 0.66 -5.18 0.94 -5.12 1.21 -5.04 1.48 -4.95 1.74 -4.84 2.00 -4.71 2.24 -4.57 2.48 -4.41 2.72 -4.24 2.94 -4.04 3.16 -3.83 3.37 -3.61 3.57 -3.39 3.75 -3.16 3.91 -2.92 4.06 -2.67 4.20 -2.42 4.32 -2.17 4.43 -1.91 4.52 -1.65 4.61 -1.38 4.68 -1.10 4.75 -0.82 4.79 -0.53 4.83 -0.24 4.84",
	},
	{
		Id = "Flower",
		Tier = 3,
		Length = 33.0,
		Points = "0.01 4.99 0.31 4.97 0.58 4.91 0.85 4.82 1.10 4.71 1.34 4.56 1.56 4.38 1.75 4.16 1.92 3.93 2.05 3.69 2.17 3.44 2.30 3.20 2.51 3.02 2.77 2.94 3.06 2.91 3.34 2.86 3.61 2.79 3.87 2.68 4.11 2.54 4.33 2.37 4.54 2.16 4.72 1.94 4.86 1.70 4.98 1.45 5.06 1.18 5.11 0.90 5.12 0.61 5.10 0.32 5.04 0.05 4.96 -0.22 4.83 -0.47 4.68 -0.70 4.49 -0.92 4.28 -1.12 4.08 -1.33 3.94 -1.56 3.91 -1.82 3.96 -2.10 4.01 -2.38 4.04 -2.66 4.03 -2.95 3.98 -3.23 3.90 -3.50 3.78 -3.75 3.64 -3.99 3.46 -4.22 3.25 -4.42 3.03 -4.59 2.78 -4.73 2.53 -4.84 2.26 -4.92 1.98 -4.96 1.69 -4.98 1.41 -4.95 1.13 -4.89 0.87 -4.80 0.62 -4.67 0.38 -4.53 0.12 -4.44 -0.15 -4.44 -0.40 -4.54 -0.64 -4.68 -0.89 -4.81 -1.15 -4.90 -1.43 -4.96 -1.72 -4.98 -2.01 -4.96 -2.29 -4.92 -2.55 -4.84 -2.81 -4.72 -3.05 -4.58 -3.27 -4.40 -3.48 -4.20 -3.65 -3.97 -3.79 -3.73 -3.90 -3.47 -3.98 -3.20 -4.02 -2.92 -4.04 -2.63 -4.00 -2.35 -3.95 -2.07 -3.91 -1.80 -3.95 -1.54 -4.10 -1.30 -4.30 -1.10 -4.51 -0.90 -4.69 -0.68 -4.84 -0.44 -4.96 -0.19 -5.05 0.07 -5.10 0.35 -5.12 0.64 -5.10 0.93 -5.06 1.21 -4.97 1.47 -4.85 1.72 -4.70 1.96 -4.53 2.19 -4.32 2.38 -4.09 2.55 -3.84 2.69 -3.59 2.80 -3.32 2.87 -3.03 2.91 -2.75 2.95 -2.49 3.04 -2.29 3.22 -2.16 3.46 -2.04 3.71 -1.90 3.95 -1.74 4.18 -1.54 4.39 -1.31 4.57 -1.07 4.72 -0.82 4.84 -0.56 4.92 -0.28 4.97",
	},
}
-- END GENERATED SHAPES

export type Shape = {
	Id: string,
	Tier: number,
	U: { number },
	V: { number },
	Cum: { number }, -- distance along the outline to each point
	N: number,
	Length: number,
	Time: number, -- seconds to cut it
}

local parsed: { [string]: Shape } = {}

-- The shape with this id, ready to trace and score (nil if there is no such shape).
function CrazyCutters.Get(id: string): Shape?
	if parsed[id] then
		return parsed[id]
	end
	for _, entry in CrazyCutters.Shapes do
		if entry.Id ~= id then
			continue
		end
		local u, v = {}, {}
		local numbers = {}
		for word in string.gmatch(entry.Points, "%S+") do
			table.insert(numbers, tonumber(word) :: number)
		end
		for index = 1, #numbers - 1, 2 do
			table.insert(u, numbers[index])
			table.insert(v, numbers[index + 1])
		end
		local cum = { 0 }
		local n = #u
		for index = 2, n + 1 do
			local a, b = index - 1, if index > n then 1 else index
			cum[index] = cum[index - 1] + math.sqrt((u[b] - u[a]) ^ 2 + (v[b] - v[a]) ^ 2)
		end
		local shape: Shape = {
			Id = entry.Id,
			Tier = entry.Tier,
			U = u,
			V = v,
			Cum = cum,
			N = n,
			Length = cum[n + 1],
			-- About 3 studs a second, plus time to find the start and line up the last corner.
			Time = math.floor(cum[n + 1] / 3 + 3.5),
		}
		parsed[id] = shape
		return shape
	end
	return nil
end

-- Ids of the shapes of one tier (1 easy .. 3 hard).
function CrazyCutters.OfTier(tier: number): { string }
	local ids = {}
	for _, entry in CrazyCutters.Shapes do
		if entry.Tier == tier then
			table.insert(ids, entry.Id)
		end
	end
	return ids
end

-- The point `s` studs along the outline (wrapping round), and the direction of travel there.
function CrazyCutters.PointAt(shape: Shape, s: number): (number, number, number, number)
	local length = shape.Length
	s = s % length
	local cum, n = shape.Cum, shape.N
	-- Binary search for the segment that holds s.
	local lo, hi = 1, n
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if cum[mid] <= s then
			lo = mid
		else
			hi = mid - 1
		end
	end
	local a, b = lo, if lo == n then 1 else lo + 1
	local span = cum[lo + 1] - cum[lo]
	local f = if span > 1e-6 then (s - cum[lo]) / span else 0
	local du, dv = shape.U[b] - shape.U[a], shape.V[b] - shape.V[a]
	local l = math.max(1e-6, math.sqrt(du * du + dv * dv))
	return shape.U[a] + du * f, shape.V[a] + dv * f, du / l, dv / l
end

-- Distance from (u, v) to the outline, and the outline point nearest to (u, v).
function CrazyCutters.Distance(shape: Shape, u: number, v: number): (number, number)
	local best, nearest = math.huge, 1
	local U, V, n = shape.U, shape.V, shape.N
	for a = 1, n do
		local b = if a == n then 1 else a + 1
		local ax, ay = U[a], V[a]
		local dx, dy = U[b] - ax, V[b] - ay
		local px, py = u - ax, v - ay
		local len2 = dx * dx + dy * dy
		local t = if len2 > 1e-9 then math.clamp((px * dx + py * dy) / len2, 0, 1) else 0
		local ex, ey = px - dx * t, py - dy * t
		local d2 = ex * ex + ey * ey
		if d2 < best then
			best = d2
			nearest = if t < 0.5 then a else b
		end
	end
	return math.sqrt(best), nearest
end

function CrazyCutters.Credit(distance: number): number
	return math.clamp(1 - (distance - CrazyCutters.FULL) / (CrazyCutters.ZERO - CrazyCutters.FULL), 0, 1)
end

-- Scores one cut as positions come in. Starts at the shape's first point (where the cutter waits).
export type Tracker = {
	Shape: Shape,
	U: number,
	V: number,
	Credit: { [number]: number }, -- outline point -> credit from the first pass over it
	Credited: number,
	CreditSum: number,
	OffLen: number, -- studs cut away from the line (weighted by how far)
	Covered: { [number]: boolean },
	Count: number,
	Done: boolean,
	_cover: (self: Tracker, u: number, v: number) -> (),
	Add: (self: Tracker, u: number, v: number) -> number,
	Coverage: (self: Tracker) -> number,
	Precision: (self: Tracker) -> number,
	Score: (self: Tracker) -> number,
}

local Tracker = {}
Tracker.__index = Tracker

function CrazyCutters.Tracker(shape: Shape): Tracker
	local self = setmetatable({
		Shape = shape,
		U = shape.U[1],
		V = shape.V[1],
		Credit = {},
		Credited = 0,
		CreditSum = 0,
		OffLen = 0,
		Covered = {},
		Count = 0,
		Done = false,
	}, Tracker)
	self:_cover(shape.U[1], shape.V[1])
	return self :: any
end

function Tracker._cover(self: Tracker, u: number, v: number)
	local shape = self.Shape
	local r2 = CrazyCutters.COVER * CrazyCutters.COVER
	local U, V, covered = shape.U, shape.V, self.Covered
	for index = 1, shape.N do
		if not covered[index] and (U[index] - u) ^ 2 + (V[index] - v) ^ 2 <= r2 then
			covered[index] = true
			self.Count += 1
		end
	end
end

-- Moves the cutter to (u, v), scoring the stretch from where it was. Returns the distance from the
-- new position to the line.
function Tracker.Add(self: Tracker, u: number, v: number): number
	local du, dv = u - self.U, v - self.V
	local length = math.sqrt(du * du + dv * dv)
	local shape = self.Shape
	local distance = 0
	if length > 1e-4 then
		-- Look at the stretch every quarter stud, so a quick swipe can't skip over the scoring.
		local steps = math.max(1, math.ceil(length / 0.25))
		for step = 1, steps do
			local f = step / steps
			local pu, pv = self.U + du * f, self.V + dv * f
			local nearest
			distance, nearest = CrazyCutters.Distance(shape, pu, pv)
			local credit = CrazyCutters.Credit(distance)
			if distance <= CrazyCutters.COVER then
				if self.Credit[nearest] == nil then
					self.Credit[nearest] = credit
					self.Credited += 1
					self.CreditSum += credit
				end
				self:_cover(pu, pv)
			else
				self.OffLen += (1 - credit) * length / steps
			end
		end
	else
		distance = CrazyCutters.Distance(shape, u, v)
	end
	self.U, self.V = u, v
	if
		not self.Done
		and self:Coverage() >= 1
		and (u - shape.U[1]) ^ 2 + (v - shape.V[1]) ^ 2 <= CrazyCutters.DONE_RADIUS ^ 2
	then
		self.Done = true
	end
	return distance
end

function Tracker.Coverage(self: Tracker): number
	return math.min(1, self.Count / (self.Shape.N * CrazyCutters.COVER_NEEDED))
end

function Tracker.Precision(self: Tracker): number
	if self.Credited == 0 then
		return 0
	end
	local length = self.Shape.Length
	return self.CreditSum / self.Credited * length / (length + self.OffLen)
end

-- The cut's score, 0..100.
function Tracker.Score(self: Tracker): number
	return math.floor(100 * self:Coverage() * self:Precision() + 0.5)
end

-- A word for a score, with its own symbol so it reads without color too.
function CrazyCutters.Grade(score: number): (string, string)
	if score >= 95 then
		return "PERFECT!", "★"
	elseif score >= 80 then
		return "NICE CUT!", "✔"
	elseif score >= 50 then
		return "WOBBLY", "~"
	end
	return "MISS!", "✖"
end

return CrazyCutters

-- Prime Cut's rules as plain math, shared by the server (which judges every cut), the bots' brain
-- and the client half (which draws the cut line and labels the two pieces).
--
-- A steak is a closed outline in its own frame (x to the right, z towards the far side of the grill,
-- in studs; the middle of its bounding box is 0, 0). The outlines come from the steak meshes'
-- generator (tools/meshgen/props/PrimeCut.py), so the steak on the grill and the shape the server
-- splits are exactly the same. On the grill a steak is turned (Place), and the knife cuts straight
-- across it along z at some x: Split gives the two pieces' areas, Even the x of a perfect 50:50.
-- Nothing here touches instances.

local PrimeCut = {}

PrimeCut.CUTS = 3 -- steaks per round
PrimeCut.STEER = 10 -- seconds a team has to line its knife up (as in the original)
PrimeCut.STEP = 0.1 -- studs the knife moves per nudge
PrimeCut.MAX_BATCH = 4 -- nudges one message may carry
PrimeCut.RATE = 26 -- nudges a second a player can make (holding a button repeats a little below it)
PrimeCut.BURST = 8 -- ...after saving up this many
PrimeCut.MARGIN = 1.2 -- the knife can go this far past the steak's sides

-- The steak meshes' build (tools/meshgen/props/PrimeCut.py): the top is THICKNESS up at the rim
-- (rounded over TOP_RADIUS) and domes up by DOME over DOME_DEPTH studs in; HEIGHT is the whole steak.
PrimeCut.THICKNESS = 1.45
PrimeCut.TOP_RADIUS = 0.5
PrimeCut.DOME = 0.28
PrimeCut.DOME_DEPTH = 2.4
PrimeCut.HEIGHT = 1.77

-- BEGIN GENERATED STEAKS (tools/meshgen/props/PrimeCut.py writes this block)
PrimeCut.Steaks = {
	{
		Id = "Ribeye",
		Prop = "PrimeCutRibeye",
		Points = "-3.27 5.41 -3.57 5.41 -3.87 5.40 -4.15 5.35 -4.42 5.29 -4.69 5.21 -4.95 5.11 -5.20 4.99 -5.45 4.87 -5.69 4.71 -5.92 4.54 -6.13 4.34 -6.34 4.12 -6.53 3.90 -6.69 3.67 -6.83 3.42 -6.94 3.17 -7.03 2.91 -7.10 2.64 -7.14 2.35 -7.15 2.05 -7.13 1.76 -7.08 1.48 -6.99 1.22 -6.88 0.96 -6.74 0.72 -6.57 0.49 -6.37 0.28 -6.16 0.07 -5.96 -0.14 -5.80 -0.38 -5.68 -0.63 -5.60 -0.90 -5.55 -1.17 -5.49 -1.45 -5.41 -1.72 -5.31 -1.98 -5.19 -2.23 -5.06 -2.47 -4.91 -2.71 -4.74 -2.94 -4.55 -3.17 -4.36 -3.38 -4.14 -3.58 -3.92 -3.77 -3.69 -3.94 -3.46 -4.11 -3.22 -4.25 -2.97 -4.39 -2.72 -4.51 -2.47 -4.62 -2.21 -4.72 -1.95 -4.82 -1.68 -4.90 -1.41 -4.97 -1.13 -5.03 -0.86 -5.08 -0.57 -5.12 -0.28 -5.15 0.01 -5.17 0.31 -5.18 0.60 -5.17 0.90 -5.16 1.19 -5.13 1.48 -5.10 1.76 -5.05 2.04 -5.02 2.33 -5.01 2.62 -5.05 2.89 -5.12 3.15 -5.21 3.42 -5.29 3.69 -5.35 3.98 -5.39 4.27 -5.41 4.56 -5.41 4.85 -5.38 5.13 -5.32 5.39 -5.23 5.65 -5.12 5.89 -4.99 6.13 -4.83 6.34 -4.64 6.52 -4.42 6.67 -4.18 6.79 -3.93 6.86 -3.66 6.91 -3.38 6.91 -3.09 6.86 -2.81 6.80 -2.54 6.75 -2.26 6.73 -1.97 6.77 -1.69 6.84 -1.42 6.93 -1.16 7.01 -0.89 7.07 -0.62 7.12 -0.33 7.14 -0.04 7.15 0.25 7.13 0.54 7.10 0.82 7.03 1.10 6.95 1.36 6.86 1.62 6.74 1.88 6.61 2.13 6.47 2.37 6.30 2.60 6.12 2.82 5.92 3.04 5.70 3.25 5.48 3.44 5.25 3.61 5.02 3.78 4.78 3.93 4.54 4.06 4.28 4.17 4.01 4.22 3.73 4.20 3.46 4.12 3.19 4.04 2.92 3.98 2.63 3.96 2.34 3.97 2.06 4.02 1.80 4.10 1.54 4.22 1.30 4.36 1.07 4.53 0.83 4.67 0.57 4.77 0.29 4.80 -0.00 4.78 -0.29 4.74 -0.57 4.71 -0.86 4.70 -1.15 4.74 -1.41 4.82 -1.67 4.93 -1.92 5.06 -2.17 5.17 -2.43 5.27 -2.70 5.34 -2.98 5.39",
	},
	{
		Id = "Strip",
		Prop = "PrimeCutStrip",
		Points = "1.64 5.23 1.34 5.23 1.05 5.21 0.76 5.18 0.47 5.17 0.18 5.15 -0.12 5.12 -0.41 5.11 -0.70 5.09 -0.99 5.06 -1.29 5.05 -1.58 5.03 -1.87 5.00 -2.16 4.99 -2.45 4.97 -2.75 4.94 -3.04 4.93 -3.33 4.91 -3.62 4.88 -3.92 4.87 -4.21 4.84 -4.48 4.78 -4.74 4.69 -4.99 4.57 -5.23 4.41 -5.45 4.22 -5.64 4.00 -5.80 3.77 -5.97 3.53 -6.13 3.30 -6.29 3.07 -6.45 2.83 -6.61 2.60 -6.77 2.36 -6.93 2.13 -7.09 1.89 -7.23 1.65 -7.33 1.39 -7.41 1.13 -7.45 0.84 -7.45 0.55 -7.44 0.25 -7.42 -0.04 -7.39 -0.33 -7.37 -0.63 -7.36 -0.92 -7.33 -1.21 -7.31 -1.50 -7.30 -1.80 -7.27 -2.09 -7.25 -2.38 -7.23 -2.67 -7.18 -2.95 -7.12 -3.22 -7.02 -3.49 -6.89 -3.73 -6.71 -3.96 -6.50 -4.15 -6.27 -4.32 -6.03 -4.45 -5.77 -4.55 -5.49 -4.61 -5.20 -4.64 -4.91 -4.66 -4.61 -4.67 -4.32 -4.69 -4.03 -4.72 -3.74 -4.73 -3.44 -4.75 -3.15 -4.76 -2.86 -4.78 -2.57 -4.81 -2.27 -4.82 -1.98 -4.84 -1.68 -4.85 -1.39 -4.87 -1.10 -4.90 -0.81 -4.91 -0.51 -4.93 -0.22 -4.95 0.07 -4.97 0.37 -4.99 0.66 -5.00 0.95 -5.02 1.24 -5.05 1.54 -5.06 1.83 -5.08 2.13 -5.09 2.42 -5.11 2.71 -5.14 3.00 -5.15 3.30 -5.17 3.59 -5.18 3.88 -5.20 4.17 -5.23 4.47 -5.23 4.76 -5.22 5.04 -5.16 5.30 -5.06 5.55 -4.92 5.78 -4.76 5.99 -4.56 6.17 -4.34 6.32 -4.10 6.46 -3.86 6.59 -3.62 6.72 -3.37 6.85 -3.12 6.98 -2.87 7.11 -2.63 7.24 -2.38 7.34 -2.12 7.41 -1.85 7.45 -1.57 7.45 -1.27 7.41 -0.99 7.35 -0.71 7.28 -0.44 7.22 -0.17 7.16 0.11 7.10 0.39 7.03 0.66 6.96 0.93 6.89 1.20 6.83 1.48 6.76 1.75 6.69 2.02 6.58 2.28 6.46 2.53 6.30 2.76 6.11 2.98 5.89 3.17 5.66 3.33 5.42 3.47 5.17 3.60 4.93 3.73 4.68 3.87 4.44 4.00 4.19 4.14 3.95 4.27 3.70 4.40 3.46 4.54 3.21 4.67 2.96 4.80 2.72 4.93 2.47 5.05 2.21 5.15 1.93 5.21",
	},
	{
		Id = "TriTip",
		Prop = "PrimeCutTriTip",
		Points = "-0.14 4.80 -0.44 4.80 -0.74 4.79 -1.02 4.76 -1.30 4.71 -1.58 4.65 -1.85 4.58 -2.11 4.50 -2.37 4.41 -2.63 4.31 -2.89 4.20 -3.14 4.08 -3.38 3.96 -3.63 3.83 -3.87 3.69 -4.11 3.55 -4.35 3.40 -4.59 3.24 -4.82 3.08 -5.05 2.91 -5.27 2.72 -5.49 2.53 -5.71 2.34 -5.92 2.13 -6.13 1.92 -6.34 1.70 -6.54 1.49 -6.72 1.26 -6.90 1.04 -7.06 0.80 -7.21 0.57 -7.34 0.32 -7.47 0.08 -7.59 -0.17 -7.69 -0.43 -7.77 -0.70 -7.83 -0.97 -7.87 -1.25 -7.88 -1.54 -7.84 -1.83 -7.76 -2.09 -7.64 -2.34 -7.47 -2.57 -7.27 -2.77 -7.03 -2.93 -6.78 -3.05 -6.51 -3.12 -6.23 -3.17 -5.95 -3.20 -5.65 -3.21 -5.35 -3.20 -5.07 -3.17 -4.79 -3.12 -4.51 -3.06 -4.24 -2.99 -3.98 -2.91 -3.71 -2.83 -3.45 -2.73 -3.20 -2.62 -2.94 -2.53 -2.66 -2.48 -2.37 -2.47 -2.09 -2.50 -1.82 -2.59 -1.58 -2.72 -1.33 -2.85 -1.08 -2.96 -0.81 -3.03 -0.53 -3.08 -0.25 -3.14 0.01 -3.24 0.25 -3.36 0.50 -3.50 0.74 -3.63 0.99 -3.76 1.24 -3.87 1.49 -3.99 1.75 -4.10 2.00 -4.20 2.26 -4.29 2.53 -4.38 2.79 -4.46 3.06 -4.53 3.34 -4.59 3.61 -4.65 3.89 -4.70 4.17 -4.74 4.46 -4.77 4.75 -4.79 5.05 -4.80 5.35 -4.80 5.64 -4.79 5.93 -4.76 6.21 -4.71 6.48 -4.64 6.74 -4.54 6.99 -4.42 7.23 -4.27 7.45 -4.09 7.63 -3.86 7.76 -3.62 7.85 -3.36 7.88 -3.07 7.85 -2.79 7.79 -2.52 7.70 -2.26 7.57 -2.01 7.42 -1.77 7.26 -1.54 7.08 -1.32 6.88 -1.10 6.66 -0.89 6.45 -0.68 6.23 -0.49 6.00 -0.32 5.77 -0.15 5.54 0.00 5.30 0.15 5.06 0.29 4.81 0.42 4.56 0.55 4.31 0.66 4.06 0.78 3.81 0.89 3.55 0.99 3.29 1.08 3.03 1.17 2.77 1.27 2.52 1.39 2.29 1.57 2.10 1.79 1.96 2.03 1.88 2.29 1.84 2.58 1.83 2.87 1.82 3.17 1.79 3.45 1.70 3.72 1.58 3.96 1.40 4.19 1.18 4.38 0.94 4.53 0.69 4.64 0.43 4.73 0.15 4.78",
	},
	{
		Id = "Kidney",
		Prop = "PrimeCutKidney",
		Points = "-2.69 4.73 -2.97 4.68 -3.22 4.58 -3.48 4.47 -3.73 4.36 -3.99 4.26 -4.26 4.22 -4.55 4.22 -4.83 4.24 -5.12 4.26 -5.41 4.25 -5.69 4.20 -5.96 4.13 -6.21 4.03 -6.46 3.90 -6.69 3.74 -6.91 3.55 -7.09 3.33 -7.25 3.09 -7.38 2.85 -7.47 2.59 -7.54 2.32 -7.58 2.04 -7.59 1.74 -7.56 1.46 -7.50 1.18 -7.40 0.92 -7.28 0.68 -7.13 0.44 -6.98 0.20 -6.85 -0.05 -6.76 -0.31 -6.69 -0.58 -6.61 -0.84 -6.51 -1.10 -6.40 -1.35 -6.27 -1.60 -6.12 -1.84 -5.96 -2.07 -5.78 -2.30 -5.59 -2.51 -5.38 -2.72 -5.16 -2.91 -4.93 -3.09 -4.70 -3.25 -4.47 -3.41 -4.23 -3.56 -3.99 -3.70 -3.74 -3.83 -3.49 -3.94 -3.24 -4.05 -2.98 -4.15 -2.72 -4.25 -2.46 -4.33 -2.18 -4.40 -1.91 -4.46 -1.64 -4.52 -1.36 -4.58 -1.09 -4.63 -0.80 -4.67 -0.52 -4.70 -0.23 -4.72 0.07 -4.73 0.37 -4.73 0.67 -4.73 0.97 -4.72 1.26 -4.70 1.54 -4.67 1.83 -4.63 2.11 -4.59 2.39 -4.54 2.66 -4.49 2.93 -4.42 3.20 -4.34 3.46 -4.25 3.73 -4.16 3.98 -4.07 4.24 -3.96 4.49 -3.84 4.74 -3.72 4.98 -3.59 5.22 -3.45 5.46 -3.29 5.69 -3.13 5.92 -2.95 6.13 -2.76 6.34 -2.55 6.54 -2.34 6.73 -2.12 6.90 -1.89 7.04 -1.65 7.18 -1.41 7.30 -1.16 7.40 -0.90 7.49 -0.64 7.55 -0.36 7.58 -0.08 7.59 0.22 7.58 0.52 7.55 0.80 7.49 1.08 7.42 1.35 7.33 1.61 7.22 1.86 7.09 2.11 6.94 2.34 6.78 2.58 6.60 2.80 6.41 3.02 6.20 3.23 5.98 3.43 5.76 3.60 5.53 3.77 5.29 3.93 5.06 4.08 4.81 4.21 4.56 4.31 4.28 4.37 4.01 4.35 3.74 4.26 3.50 4.12 3.27 3.96 3.03 3.82 2.78 3.68 2.54 3.56 2.28 3.47 2.01 3.39 1.73 3.34 1.44 3.31 1.16 3.29 0.88 3.28 0.59 3.29 0.30 3.32 0.03 3.38 -0.24 3.46 -0.50 3.56 -0.75 3.67 -1.00 3.80 -1.24 3.94 -1.46 4.11 -1.68 4.31 -1.90 4.50 -2.14 4.64 -2.41 4.72",
	},
	{
		Id = "Heart",
		Prop = "PrimeCutHeart",
		Points = "-0.12 5.82 -0.39 5.77 -0.64 5.65 -0.88 5.49 -1.09 5.28 -1.29 5.07 -1.49 4.85 -1.69 4.64 -1.89 4.42 -2.09 4.20 -2.28 3.98 -2.48 3.77 -2.68 3.55 -2.88 3.34 -3.08 3.12 -3.28 2.90 -3.48 2.68 -3.68 2.47 -3.88 2.25 -4.08 2.05 -4.31 1.88 -4.55 1.74 -4.80 1.63 -5.05 1.50 -5.29 1.36 -5.52 1.20 -5.75 1.02 -5.96 0.82 -6.16 0.61 -6.33 0.38 -6.49 0.15 -6.64 -0.09 -6.76 -0.34 -6.85 -0.60 -6.94 -0.86 -7.00 -1.14 -7.05 -1.41 -7.08 -1.70 -7.09 -2.00 -7.08 -2.29 -7.03 -2.57 -6.97 -2.84 -6.90 -3.12 -6.81 -3.38 -6.70 -3.63 -6.57 -3.87 -6.42 -4.11 -6.25 -4.34 -6.06 -4.56 -5.85 -4.77 -5.63 -4.96 -5.40 -5.13 -5.17 -5.28 -4.92 -5.41 -4.67 -5.52 -4.41 -5.62 -4.14 -5.70 -3.87 -5.76 -3.59 -5.80 -3.30 -5.82 -3.00 -5.82 -2.72 -5.79 -2.44 -5.74 -2.17 -5.67 -1.90 -5.59 -1.64 -5.49 -1.39 -5.37 -1.15 -5.24 -0.91 -5.09 -0.68 -4.93 -0.43 -4.81 -0.16 -4.75 0.13 -4.74 0.40 -4.79 0.65 -4.91 0.89 -5.06 1.12 -5.22 1.36 -5.36 1.61 -5.48 1.87 -5.59 2.13 -5.67 2.40 -5.74 2.68 -5.79 2.97 -5.82 3.26 -5.82 3.55 -5.80 3.83 -5.76 4.11 -5.71 4.38 -5.64 4.64 -5.55 4.89 -5.44 5.14 -5.31 5.38 -5.16 5.61 -4.99 5.83 -4.80 6.03 -4.59 6.23 -4.37 6.40 -4.14 6.55 -3.91 6.69 -3.66 6.80 -3.41 6.90 -3.15 6.97 -2.89 7.03 -2.61 7.07 -2.33 7.09 -2.04 7.09 -1.74 7.07 -1.45 7.03 -1.17 6.97 -0.90 6.88 -0.63 6.78 -0.38 6.66 -0.13 6.52 0.11 6.36 0.35 6.19 0.58 6.00 0.79 5.78 0.99 5.56 1.17 5.33 1.34 5.09 1.48 4.85 1.61 4.60 1.73 4.35 1.86 4.12 2.02 3.91 2.22 3.71 2.44 3.51 2.65 3.31 2.87 3.12 3.09 2.92 3.31 2.72 3.52 2.52 3.74 2.32 3.95 2.12 4.17 1.93 4.39 1.73 4.61 1.52 4.82 1.32 5.04 1.12 5.25 0.91 5.46 0.68 5.63 0.43 5.75 0.16 5.81",
	},
	{
		Id = "Chuck",
		Prop = "PrimeCutChuck",
		Points = "-4.34 5.78 -4.63 5.76 -4.91 5.72 -5.18 5.64 -5.44 5.54 -5.68 5.42 -5.92 5.26 -6.15 5.09 -6.37 4.91 -6.58 4.70 -6.75 4.47 -6.89 4.23 -7.00 3.98 -7.07 3.71 -7.12 3.43 -7.14 3.14 -7.14 2.84 -7.14 2.54 -7.14 2.24 -7.14 1.94 -7.14 1.64 -7.14 1.34 -7.14 1.04 -7.14 0.74 -7.14 0.44 -7.14 0.14 -7.14 -0.16 -7.14 -0.46 -7.14 -0.76 -7.14 -1.06 -7.14 -1.36 -7.14 -1.66 -7.14 -1.96 -7.14 -2.26 -7.14 -2.56 -7.14 -2.86 -7.13 -3.15 -7.11 -3.44 -7.06 -3.72 -6.98 -3.99 -6.86 -4.24 -6.71 -4.48 -6.52 -4.70 -6.31 -4.90 -6.08 -5.06 -5.83 -5.19 -5.57 -5.29 -5.30 -5.36 -5.02 -5.39 -4.72 -5.40 -4.42 -5.40 -4.12 -5.40 -3.82 -5.40 -3.52 -5.40 -3.22 -5.40 -2.92 -5.40 -2.62 -5.40 -2.32 -5.40 -2.02 -5.40 -1.72 -5.40 -1.42 -5.40 -1.12 -5.40 -0.82 -5.40 -0.52 -5.40 -0.22 -5.40 0.08 -5.40 0.38 -5.40 0.67 -5.40 0.97 -5.40 1.27 -5.40 1.57 -5.40 1.87 -5.40 2.17 -5.40 2.47 -5.39 2.76 -5.39 3.04 -5.42 3.32 -5.47 3.58 -5.56 3.84 -5.65 4.11 -5.73 4.39 -5.77 4.68 -5.78 4.97 -5.76 5.25 -5.71 5.52 -5.64 5.78 -5.54 6.02 -5.41 6.25 -5.24 6.46 -5.04 6.65 -4.81 6.81 -4.58 6.93 -4.33 7.02 -4.07 7.09 -3.80 7.13 -3.51 7.14 -3.22 7.11 -2.93 7.07 -2.65 6.98 -2.39 6.87 -2.13 6.73 -1.89 6.56 -1.66 6.36 -1.45 6.13 -1.27 5.90 -1.12 5.65 -1.00 5.38 -0.91 5.11 -0.85 4.82 -0.82 4.53 -0.82 4.24 -0.85 3.96 -0.90 3.69 -0.97 3.41 -1.01 3.12 -1.03 2.83 -1.03 2.55 -1.00 2.27 -0.94 2.01 -0.84 1.77 -0.71 1.54 -0.54 1.33 -0.34 1.16 -0.11 1.03 0.14 0.95 0.40 0.90 0.68 0.88 0.97 0.87 1.27 0.87 1.57 0.87 1.87 0.87 2.17 0.87 2.47 0.86 2.76 0.81 3.04 0.74 3.31 0.63 3.57 0.49 3.81 0.32 4.04 0.11 4.24 -0.12 4.42 -0.36 4.56 -0.61 4.66 -0.88 4.74 -1.16 4.79 -1.45 4.81 -1.74 4.83 -2.02 4.88 -2.28 4.98 -2.52 5.11 -2.76 5.26 -3.00 5.41 -3.25 5.54 -3.50 5.64 -3.77 5.72 -4.05 5.77",
	},
}
-- END GENERATED STEAKS

export type Outline = { Vector2 }

local parsed: { [string]: Outline } = {}

-- The steak with this id (or nil).
function PrimeCut.Steak(id: string): any
	for _, steak in PrimeCut.Steaks do
		if steak.Id == id then
			return steak
		end
	end
	return nil
end

-- A steak's outline in its own frame (cached).
function PrimeCut.Outline(id: string): Outline
	local cached = parsed[id]
	if cached then
		return cached
	end
	local steak = PrimeCut.Steak(id)
	assert(steak, `PrimeCut has no steak {id}`)
	local numbers = {}
	for token in string.gmatch(steak.Points, "%S+") do
		table.insert(numbers, tonumber(token) :: number)
	end
	local points = {}
	for index = 1, #numbers - 1, 2 do
		table.insert(points, Vector2.new(numbers[index], numbers[index + 1]))
	end
	parsed[id] = points
	return points
end

-- The outline turned the way the steak lies on the grill: turned `angle` radians about its middle,
-- exactly like CFrame.Angles(0, angle, 0) turns the mesh (x right, y = z of the grill).
function PrimeCut.Place(outline: Outline, angle: number): Outline
	local c, s = math.cos(angle), math.sin(angle)
	local placed = table.create(#outline)
	for index, point in outline do
		-- CFrame.Angles(0, a, 0) * (x, 0, z) = (x cos a + z sin a, 0, -x sin a + z cos a)
		placed[index] = Vector2.new(point.X * c + point.Y * s, -point.X * s + point.Y * c)
	end
	return placed
end

function PrimeCut.Bounds(outline: Outline): (number, number, number, number)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, point in outline do
		minX = math.min(minX, point.X)
		maxX = math.max(maxX, point.X)
		minZ = math.min(minZ, point.Y)
		maxZ = math.max(maxZ, point.Y)
	end
	return minX, maxX, minZ, maxZ
end

-- Signed area (shoelace) of a polygon.
local function signedArea(points: Outline): number
	local sum = 0
	local count = #points
	for index = 1, count do
		local a = points[index]
		local b = points[index % count + 1]
		sum += a.X * b.Y - b.X * a.Y
	end
	return sum / 2
end

function PrimeCut.Area(points: Outline): number
	return math.abs(signedArea(points))
end

-- The part of the outline on one side of the line x = cut (Sutherland-Hodgman against a half-plane:
-- for a hollow-sided steak the piece can come out as one polygon touching itself along the cut, which
-- still has exactly the right area).
function PrimeCut.Piece(outline: Outline, cut: number, left: boolean): Outline
	local result = {}
	local count = #outline
	for index = 1, count do
		local a = outline[index]
		local b = outline[index % count + 1]
		local aIn = if left then a.X <= cut else a.X >= cut
		local bIn = if left then b.X <= cut else b.X >= cut
		if aIn then
			table.insert(result, a)
		end
		if aIn ~= bIn then
			local t = (cut - a.X) / (b.X - a.X)
			table.insert(result, Vector2.new(cut, a.Y + (b.Y - a.Y) * t))
		end
	end
	return result
end

-- The two pieces' areas when the knife comes down at x = cut: left, right.
function PrimeCut.Split(outline: Outline, cut: number): (number, number)
	local total = PrimeCut.Area(outline)
	local left = if #outline > 0 then PrimeCut.Area(PrimeCut.Piece(outline, cut, true)) else 0
	return left, math.max(0, total - left)
end

-- The left piece's share in percent (0..100).
function PrimeCut.Percent(outline: Outline, cut: number): number
	local left, right = PrimeCut.Split(outline, cut)
	local total = left + right
	return if total > 0 then left / total * 100 else 50
end

-- A share as it's shown: to one decimal (the right piece shows 100 minus the left's).
function PrimeCut.Round(percent: number): number
	return math.floor(percent * 10 + 0.5) / 10
end

-- How far a cut is from an even split, as it's shown: |left% - 50| to one decimal.
function PrimeCut.Off(percent: number): number
	return math.floor(math.abs(PrimeCut.Round(percent) - 50) * 10 + 0.5) / 10
end

-- The x of a perfect 50:50 cut (the left share only grows with x, so halve the gap).
function PrimeCut.Even(outline: Outline): number
	local lo, hi = PrimeCut.Bounds(outline)
	for _ = 1, 40 do
		local middle = (lo + hi) / 2
		if PrimeCut.Percent(outline, middle) < 50 then
			lo = middle
		else
			hi = middle
		end
	end
	return (lo + hi) / 2
end

-- Where the line x = cut crosses the outline: the nearest and farthest z (nil if it misses).
function PrimeCut.Chord(outline: Outline, cut: number): (number?, number?)
	local near, far = nil, nil
	local count = #outline
	for index = 1, count do
		local a = outline[index]
		local b = outline[index % count + 1]
		if (a.X <= cut) ~= (b.X <= cut) then
			local z = a.Y + (b.Y - a.Y) * (cut - a.X) / (b.X - a.X)
			near = if near then math.min(near, z) else z
			far = if far then math.max(far, z) else z
		end
	end
	return near, far
end

-- How far a point is from the outline (studs).
function PrimeCut.EdgeDistance(outline: Outline, point: Vector2): number
	local best = math.huge
	local count = #outline
	for index = 1, count do
		local a = outline[index]
		local b = outline[index % count + 1]
		local ab = b - a
		local t = math.clamp((point - a):Dot(ab) / math.max(ab:Dot(ab), 1e-9), 0, 1)
		best = math.min(best, (a + ab * t - point).Magnitude)
	end
	return best
end

-- The height of the steak's top over its underside at a point inside it (the cut line hugs it).
function PrimeCut.TopAt(outline: Outline, point: Vector2): number
	local d = PrimeCut.EdgeDistance(outline, point)
	local r = PrimeCut.TOP_RADIUS
	if d < r then
		return PrimeCut.THICKNESS - r + math.sqrt(math.max(0, r * r - (r - d) ^ 2))
	end
	local t = math.clamp((d - r) / PrimeCut.DOME_DEPTH, 0, 1)
	return PrimeCut.THICKNESS + PrimeCut.DOME * t * t * (3 - 2 * t)
end

-- A polygon's centroid (its balance point: where a piece's label goes).
function PrimeCut.Centroid(points: Outline): Vector2
	local area = signedArea(points)
	if math.abs(area) < 1e-6 then
		local sum = Vector2.zero
		for _, point in points do
			sum += point
		end
		return if #points > 0 then sum / #points else Vector2.zero
	end
	local cx, cz = 0, 0
	local count = #points
	for index = 1, count do
		local a = points[index]
		local b = points[index % count + 1]
		local cross = a.X * b.Y - b.X * a.Y
		cx += (a.X + b.X) * cross
		cz += (a.Y + b.Y) * cross
	end
	return Vector2.new(cx, cz) / (6 * area)
end

-- The two pieces' shares as they're shown, e.g. "48.7", "51.3" (they always add up to 100).
function PrimeCut.Format(percent: number): (string, string)
	local left = PrimeCut.Round(percent)
	return string.format("%.1f", left), string.format("%.1f", 100 - left)
end

return PrimeCut

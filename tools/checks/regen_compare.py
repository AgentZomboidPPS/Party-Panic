"""Regenerates props with the current generator code and compares them with the committed glbs, so a
merge that changed shared mesh helpers shows which props would change shape (and need re-uploading).

    python3 tools/checks/regen_compare.py PumpBandshell,PumpBigTop
    python3 tools/checks/regen_compare.py --changed      # the glbs staged in a merge (git diff --cached)

Prints, per prop, the pieces whose triangles differ ("12/300 tris flipped, 0 differ" means only
facing changed); the last line lists the props that really differ. Exits 1 if any do. The props are
written to a temporary folder, never over assets/meshes.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "meshgen"))
sys.path.insert(0, str(ROOT / "tools" / "checks"))
from mesh_orientation import read_glb  # noqa: E402


def oriented(positions: np.ndarray, triangles: np.ndarray) -> Counter:
    """Triangles as rotation-normalised corner tuples (a flipped triangle is a different key)."""
    out: Counter = Counter()
    for tri in triangles:
        points = [tuple(np.round(positions[i], 3)) for i in tri]
        first = min(range(3), key=lambda i: points[i])
        out[tuple(points[first:] + points[:first])] += 1
    return out


def changed_names() -> list[str]:
    files = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=AM", "HEAD", "--", "assets/meshes"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout.split()
    return sorted({Path(f).stem for f in files if f.endswith(".glb")})


def main() -> int:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    names = changed_names() if sys.argv[1] == "--changed" else sys.argv[1].split(",")
    if not names:
        print("no props to compare")
        return 0
    import generate_meshes as g

    g.load_mode_props()
    real = []
    with tempfile.TemporaryDirectory() as folder:
        out = Path(folder)
        for name in names:
            if name not in g.PROPS:
                print(f"{name:22s} not a generated prop (skipped)")
                continue
            pieces = {piece: g.face_outward(mesh) for piece, mesh in g.PROPS[name]().items()}
            g.write_glb(out / f"{name}.glb", pieces)
            committed = ROOT / "assets" / "meshes" / f"{name}.glb"
            if not committed.exists():
                print(f"{name:22s} new prop (nothing committed to compare)")
                continue
            a, b = read_glb(committed), read_glb(out / f"{name}.glb")
            notes = []
            for piece in b:
                if piece not in a:
                    notes.append(f"{piece}: new piece")
                    continue
                ta, tb = oriented(*a[piece]), oriented(*b[piece])
                if ta == tb:
                    continue
                flipped = sum((ta & Counter({(t[0], t[2], t[1]): n for t, n in tb.items()})).values())
                notes.append(f"{piece}: {flipped}/{sum(tb.values())} tris flipped, {sum((tb - ta).values())} differ")
            if notes:
                real.append(name)
                print(f"{name:22s} " + "; ".join(notes))
        # Some generators also rewrite Luau modules in src/shared/Logic as they run.
        subprocess.run(["git", "checkout", "--", "src/shared/Logic"], cwd=ROOT, capture_output=True)
    print("REAL:", ",".join(real) or "none")
    return 1 if real else 0


if __name__ == "__main__":
    sys.exit(main())

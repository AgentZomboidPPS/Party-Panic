# Mini-game props

One file per mini-game, e.g. `PumpAndPop.py`:

```python
import math
from generate_meshes import Mesh, merge, lathe, tube, rounded_box, cylinder, sphere, capsule, torus, icosphere, taper

def pump():
    """A plunger pump, facing -Z."""
    body = cylinder(0.8, 3.0, 24, 0.15)
    return {"Body": body, "Handle": rounded_box(2.4, 0.4, 0.4, 0.15).translate(0, 4.2, 0)}

PROPS = {"Pump": pump}
COLORS = {"Handle": (255, 90, 90)}  # preview colors only; the game colors pieces by name
```

Units are studs, +Y is up, the base sits on y = 0 and -Z is the front. Piece names become MeshPart
names; give each piece a palette color (and material) in the matching `src/server/World/Props/<Game>.luau`.

    python3 tools/meshgen/generate_meshes.py --only Pump

Roblox doesn't draw the back of a face, so every face must point outward (counter-clockwise seen
from outside). The shared helpers do (`tube`, `taper`, `sdf_mesh` and `extrude` with points either
way round); run `lathe` profiles bottom, outside, then top. Don't flip a helper's faces yourself.
The generator warns about inside-out closed parts as it writes each prop, and
`python3 tools/checks/mesh_orientation.py` checks every `assets/meshes/*.glb`.

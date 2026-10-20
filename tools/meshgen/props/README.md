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

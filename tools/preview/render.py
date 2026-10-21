"""Renders a world dump from tools/preview/dump_world.luau with Blender (pip package `bpy`), so the
lobby can be checked visually without opening Roblox.

    python render.py dump.json out_prefix [--views spawn,overview,...] [--samples 32] [--width 1280]

Coordinates: Roblox is Y-up, Blender is Z-up. A Roblox point (x, y, z) maps to Blender (x, -z, y).
Parts are redrawn from their primitive shapes (unions from the PP_Pieces attribute that
Shapes.RecordPieces adds), mesh props from the local .glb files, terrain from the height grid.
Text, GUIs, particles and grass blades are not drawn.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
import mathutils
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
MESH_DIR = ROOT / "assets" / "meshes"

# Roblox -> Blender basis change.
M = mathutils.Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


def to_blender(x, y, z):
    return mathutils.Vector((x, -z, y))


def cframe_matrix(components, scale=(1, 1, 1)):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = components
    rot = mathutils.Matrix(((r00, r01, r02), (r10, r11, r12), (r20, r21, r22)))
    rot_b = M @ rot @ M.transposed()
    # Scale is applied in the part's local (Roblox) axes, which map to Blender local axes via M.
    sx, sy, sz = scale
    local_scale = M @ mathutils.Matrix.Diagonal((sx, sy, sz)) @ M.transposed()
    mat = (rot_b @ local_scale).to_4x4()
    mat.translation = to_blender(x, y, z)
    return mat


def srgb_to_linear(c):
    c = c / 255.0 if c > 1.0 else c
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


MATERIAL_CACHE: dict = {}


def material(color, mat_name, transparency):
    rgb = tuple(srgb_to_linear(c) for c in color)
    key = (tuple(round(c, 3) for c in rgb), mat_name, round(transparency, 2))
    if key in MATERIAL_CACHE:
        return MATERIAL_CACHE[key]
    mat = bpy.data.materials.new(f"m{len(MATERIAL_CACHE)}")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    rough = {"SmoothPlastic": 0.45, "Plastic": 0.6, "Glass": 0.05, "Metal": 0.3, "DiamondPlate": 0.35,
             "Foil": 0.25, "Ice": 0.1, "Marble": 0.3, "Wood": 0.7, "WoodPlanks": 0.7}.get(mat_name, 0.55)
    bsdf.inputs["Roughness"].default_value = rough
    if mat_name in ("Metal", "DiamondPlate", "Foil"):
        # Roblox metal reads as shiny paint, not a mirror.
        bsdf.inputs["Metallic"].default_value = 0.35
    if mat_name == "Neon":
        bsdf.inputs["Emission Color"].default_value = (*rgb, 1)
        bsdf.inputs["Emission Strength"].default_value = 4.0
    if mat_name == "Glass":
        bsdf.inputs["Transmission Weight"].default_value = 0.8
    if transparency > 0.01:
        bsdf.inputs["Alpha"].default_value = max(0.0, 1 - transparency)
    cull_back_faces(mat)
    MATERIAL_CACHE[key] = mat
    return mat


def cull_back_faces(mat):
    """Roblox draws only the front of each face, so back faces render see-through here too: an
    inside-out mesh looks hollow in the render, as it would in game."""
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    output = next(node for node in nodes if node.type == "OUTPUT_MATERIAL")
    surface = output.inputs["Surface"].links[0].from_socket
    geometry = nodes.new("ShaderNodeNewGeometry")
    clear = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    links.new(geometry.outputs["Backfacing"], mix.inputs["Fac"])
    links.new(surface, mix.inputs[1])
    links.new(clear.outputs["BSDF"], mix.inputs[2])
    links.new(mix.outputs["Shader"], output.inputs["Surface"])


PRIMS: dict = {}


def primitive(kind):
    """Unit-size meshes (fit a 1x1x1 box in Roblox axes) reused by every part."""
    if kind in PRIMS:
        return PRIMS[kind]
    if kind == "Block":
        bpy.ops.mesh.primitive_cube_add(size=1)
    elif kind == "Ball":
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, segments=32, ring_count=16)
    elif kind == "Cylinder":
        # Roblox cylinders run along X.
        bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1, vertices=40, rotation=(0, math.pi / 2, 0))
        bpy.ops.object.transform_apply(rotation=True)
    elif kind == "Wedge":
        # Roblox wedge: slope rises from front (-Z) bottom to back (+Z) top; in Blender local axes
        # (x, -z, y): back is -Y.
        verts = [(-0.5, 0.5, -0.5), (0.5, 0.5, -0.5), (-0.5, -0.5, -0.5), (0.5, -0.5, -0.5),
                 (-0.5, -0.5, 0.5), (0.5, -0.5, 0.5)]
        faces = [(0, 1, 3, 2), (2, 3, 5, 4), (0, 4, 5, 1), (0, 2, 4), (1, 5, 3)]
        mesh = bpy.data.meshes.new("wedge")
        mesh.from_pydata(verts, [], faces)
        obj = bpy.data.objects.new("wedge", mesh)
        bpy.context.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
    obj = bpy.context.active_object
    obj.hide_render = True
    obj.hide_viewport = True
    if kind in ("Ball", "Cylinder"):
        smooth(obj.data)
    PRIMS[kind] = obj.data
    return obj.data


GLB_CACHE: dict = {}


def glb_pieces(prop):
    """Returns {piece name: (verts Nx3 in Roblox axes, faces)} from the prop's .glb."""
    if prop in GLB_CACHE:
        return GLB_CACHE[prop]
    import struct

    path = MESH_DIR / f"{prop}.glb"
    result = {}
    if path.exists():
        data = path.read_bytes()
        json_len = struct.unpack_from("<I", data, 12)[0]
        doc = json.loads(data[20:20 + json_len])
        bin_start = 20 + json_len + 8
        blob = data[bin_start:]

        def accessor(index):
            acc = doc["accessors"][index]
            view = doc["bufferViews"][acc["bufferView"]]
            comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
            dtype = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[acc["componentType"]]
            offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
            arr = np.frombuffer(blob, dtype=dtype, count=acc["count"] * comps, offset=offset)
            return arr.reshape(acc["count"], comps) if comps > 1 else arr

        for node in doc.get("nodes", []):
            if "mesh" not in node:
                continue
            mesh = doc["meshes"][node["mesh"]]
            verts_all, faces_all = [], []
            base = 0
            for prim in mesh["primitives"]:
                v = accessor(prim["attributes"]["POSITION"]).astype(np.float64)
                f = accessor(prim["indices"]).astype(np.int64).reshape(-1, 3)
                verts_all.append(v)
                faces_all.append(f + base)
                base += len(v)
            name = node.get("name") or mesh.get("name")
            result[name] = (np.concatenate(verts_all), np.concatenate(faces_all))
    GLB_CACHE[prop] = result
    return result


def add_object(name, mesh, matrix, mat, shadow=True):
    """Objects share meshes; each one carries its own material (object-linked slot)."""
    obj = bpy.data.objects.new(name, mesh)
    obj.matrix_world = matrix
    bpy.context.collection.objects.link(obj)
    if len(obj.material_slots):
        obj.material_slots[0].link = "OBJECT"
        obj.material_slots[0].material = mat
    obj.visible_shadow = shadow
    return obj


def smooth(mesh, angle=40):
    mesh.shade_smooth()
    mesh.set_sharp_from_angle(angle=math.radians(angle))


def prim_mesh(kind):
    base = primitive(kind)
    if not base.materials:
        base.materials.append(None)
    return base


def shape_kind(value):
    # Enum.PartType values: Ball 0, Block 1, Cylinder 2, Wedge 3, CornerWedge 4.
    return {0: "Ball", 1: "Block", 2: "Cylinder", 3: "Wedge"}.get(value, "Block")


MESH_CACHE: dict = {}


def mesh_from_arrays(key, verts, faces):
    if key in MESH_CACHE:
        return MESH_CACHE[key]
    mesh = bpy.data.meshes.new(key)
    mesh.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    mesh.update()
    smooth(mesh, 50)
    mesh.materials.append(None)
    MESH_CACHE[key] = mesh
    return mesh


def build_parts(parts):
    unknown_meshes = set()
    for index, p in enumerate(parts):
        mat = material(p["col"], p["m"], p["t"])
        shadow = p.get("sh", True)
        size = p["s"]
        if p.get("pieces"):
            info = p["pieces"]
            orig = info["size"]
            k = [size[i] / orig[i] if orig[i] else 1 for i in range(3)]
            parent = cframe_matrix(p["cf"])
            positives, cutters = [], []
            for piece_index, piece in enumerate(info["pieces"]):
                kind = shape_kind(piece[0])
                psize = piece[1:4]
                rel = piece[4:16]
                rel = [rel[0] * k[0], rel[1] * k[1], rel[2] * k[2]] + list(rel[3:])
                if kind == "Ball":
                    psize = [min(psize)] * 3
                if kind == "Cylinder":
                    d = min(psize[1], psize[2])
                    psize = [psize[0], d, d]
                # Approximate non-uniform union scaling by scaling each piece's size. The tiny
                # per-piece growth keeps coplanar faces of overlapping pieces apart (Roblox merges
                # them into one mesh; Cycles would render coincident faces black).
                jitter = 1 + 0.0008 * piece_index
                psize = [psize[0] * k[0] * jitter, psize[1] * k[1] * jitter, psize[2] * k[2] * jitter]
                matrix = parent @ cframe_matrix(rel, psize)
                is_cutter = len(piece) > 16 and piece[16] == 1
                (cutters if is_cutter else positives).append((kind, matrix))
            cutter_collection = None
            if cutters:
                cutter_collection = bpy.data.collections.new(f"cut{index}")
                for kind, matrix in cutters:
                    cutter = bpy.data.objects.new("cutter", prim_mesh(kind))
                    cutter.matrix_world = matrix
                    cutter.hide_render = True
                    cutter.material_slots[0].link = "OBJECT"
                    cutter.material_slots[0].material = mat
                    cutter_collection.objects.link(cutter)
            if not cutter_collection:
                for kind, matrix in positives:
                    add_object(f"u{index}", prim_mesh(kind), matrix, mat, shadow)
            else:
                # Merge the pieces into one solid first (coplanar faces between pieces render black
                # in Cycles), then cut.
                first_kind, first_matrix = positives[0]
                obj = add_object(f"u{index}", prim_mesh(first_kind), first_matrix, mat, shadow)
                if len(positives) > 1:
                    others = bpy.data.collections.new(f"pos{index}")
                    for kind, matrix in positives[1:]:
                        other = bpy.data.objects.new("piece", prim_mesh(kind))
                        other.matrix_world = matrix
                        others.objects.link(other)
                    merge = obj.modifiers.new("merge", "BOOLEAN")
                    merge.operation = "UNION"
                    merge.operand_type = "COLLECTION"
                    merge.collection = others
                    merge.solver = "EXACT"
                mod = obj.modifiers.new("cut", "BOOLEAN")
                mod.operation = "DIFFERENCE"
                mod.operand_type = "COLLECTION"
                mod.collection = cutter_collection
                mod.solver = "EXACT"
                mod.material_mode = "TRANSFER"
            continue
        if p["c"] == "MeshPart" and p.get("prop"):
            pieces = glb_pieces(p["prop"])
            piece = pieces.get(p["n"])
            if piece is not None:
                verts, faces = piece
                vmin, vmax = verts.min(0), verts.max(0)
                center = (vmin + vmax) / 2
                ext = np.maximum(vmax - vmin, 1e-4)
                unit = (verts - center) / ext  # fits a 1x1x1 box, Roblox axes
                key = f"{p['prop']}:{p['n']}"
                # Roblox's glTF import turns each mesh half a turn inside its MeshPart (x -> -x,
                # z -> -z), so draw it the way the engine does.
                blender_verts = np.stack([-unit[:, 0], unit[:, 2], unit[:, 1]], 1)
                mesh = mesh_from_arrays(key, blender_verts, faces)
                add_object(key, mesh, cframe_matrix(p["cf"], size), mat, shadow)
                continue
            unknown_meshes.add(f"{p['prop']}:{p['n']}")
        kind = p.get("shape", "Block") if p["c"] in ("Part", "SpawnLocation") else "Block"
        if p["c"] == "WedgePart":
            kind = "Wedge"
        if kind == "Ball":
            size = [min(size)] * 3
        if kind == "Cylinder":
            d = min(size[1], size[2])
            size = [size[0], d, d]
        if kind not in ("Ball", "Block", "Cylinder", "Wedge"):
            kind = "Block"
        add_object(p["n"], prim_mesh(kind), cframe_matrix(p["cf"], size), mat, shadow)
    if unknown_meshes:
        print("meshes drawn as boxes (no matching glb node):", sorted(unknown_meshes)[:20])


def build_terrain(t):
    half, step = t["half"], t["step"]
    if not t.get("heights"):
        return
    n = int(round(2 * half / step)) + 1
    h = np.array(t["heights"], dtype=np.float64).reshape(n, n)  # [z][x]
    mats = np.array(t["mats"]).reshape(n, n)
    names = t["materials"]
    colors = t["colors"]
    valid = h > -900
    verts = []
    vcol = []
    for zi in range(n):
        for xi in range(n):
            x = -half + xi * step
            z = -half + zi * step
            y = h[zi, xi] if valid[zi, xi] else -60
            verts.append((x, -z, y))
            m = mats[zi, xi]
            c = colors.get(names[m - 1], [0.4, 0.6, 0.3]) if m > 0 else [0.3, 0.3, 0.3]
            vcol.append([srgb_to_linear(ch) for ch in c])
    faces = []
    for zi in range(n - 1):
        for xi in range(n - 1):
            a = zi * n + xi
            if not (valid[zi, xi] or valid[zi, xi + 1] or valid[zi + 1, xi] or valid[zi + 1, xi + 1]):
                continue
            faces.append((a, a + 1, a + n + 1, a + n))
    mesh = bpy.data.meshes.new("terrain")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    attr = mesh.color_attributes.new("col", "FLOAT_COLOR", "POINT")
    for i, c in enumerate(vcol):
        attr.data[i].color = (*c, 1)
    mesh.shade_smooth()
    mat = bpy.data.materials.new("terrain")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.9
    attr_node = nodes.new("ShaderNodeVertexColor")
    attr_node.layer_name = "col"
    # A little noise so grass doesn't look like flat paint.
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.15
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 0.25
    links.new(attr_node.outputs["Color"], mix.inputs["A"])
    links.new(noise.outputs["Color"], mix.inputs["B"])
    links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("terrain", mesh)
    bpy.context.collection.objects.link(obj)

    water = np.array(t["water"], dtype=np.float64).reshape(n, n)
    wet = water > -900
    if wet.any():
        wverts, wfaces = [], []
        index = {}
        for zi in range(n):
            for xi in range(n):
                if wet[zi, xi]:
                    index[(zi, xi)] = len(wverts)
                    wverts.append((-half + xi * step, half - zi * step, water[zi, xi]))
        for zi in range(n - 1):
            for xi in range(n - 1):
                quad = [(zi, xi), (zi, xi + 1), (zi + 1, xi + 1), (zi + 1, xi)]
                if all(q in index for q in quad):
                    wfaces.append(tuple(index[q] for q in quad))
        wmesh = bpy.data.meshes.new("water")
        wmesh.from_pydata(wverts, [], wfaces)
        wmat = bpy.data.materials.new("water")
        wmat.use_nodes = True
        wb = wmat.node_tree.nodes["Principled BSDF"]
        wb.inputs["Base Color"].default_value = (0.05, 0.35, 0.55, 1)
        wb.inputs["Roughness"].default_value = 0.05
        wmesh.materials.append(wmat)
        wobj = bpy.data.objects.new("water", wmesh)
        bpy.context.collection.objects.link(wobj)


def add_dummy(position, yaw=0.0, color=(0.95, 0.75, 0.55)):
    """A rough R15-sized avatar (about 5.2 studs tall) for scale."""
    x, y, z = position
    parts = [
        ((0, 4.6, 0), (1.25, 1.25, 1.25), (0.98, 0.8, 0.6)),  # head
        ((0, 3.0, 0), (2.0, 2.0, 1.0), (0.2, 0.45, 0.95)),  # torso
        ((-1.5, 3.0, 0), (0.95, 2.0, 0.95), (0.98, 0.8, 0.6)),
        ((1.5, 3.0, 0), (0.95, 2.0, 0.95), (0.98, 0.8, 0.6)),
        ((-0.5, 1.0, 0), (0.95, 2.0, 0.95), (0.15, 0.2, 0.35)),
        ((0.5, 1.0, 0), (0.95, 2.0, 0.95), (0.15, 0.2, 0.35)),
    ]
    c, s = math.cos(yaw), math.sin(yaw)
    for (ox, oy, oz), size, col in parts:
        rx, rz = ox * c + oz * s, -ox * s + oz * c
        comps = [x + rx, y + oy, z + rz, c, 0, s, 0, 1, 0, -s, 0, c]
        add_object("dummy", prim_mesh("Block"), cframe_matrix(comps, size), material([v * 255 for v in col], "SmoothPlastic", 0))


def setup_world(lighting):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.use_denoising = True
    scene.view_settings.view_transform = "AgX" if "AgX" in [v.identifier for v in scene.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    scene.view_settings.look = "AgX - Medium High Contrast" if scene.view_settings.view_transform == "AgX" else "None"
    world = bpy.data.worlds.new("sky")
    scene.world = world
    world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    bg = nodes["Background"]
    # Roblox's default sky: pale near the horizon, clear blue overhead.
    coords = nodes.new("ShaderNodeTexCoord")
    split = nodes.new("ShaderNodeSeparateXYZ")
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0.62, 0.78, 0.98, 1)
    ramp.color_ramp.elements[1].position = 0.6
    ramp.color_ramp.elements[1].color = (0.16, 0.42, 0.9, 1)
    links.new(coords.outputs["Generated"], split.inputs[0])
    links.new(split.outputs["Z"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    sun = lighting.get("sun", [0.3, 0.8, 0.3])
    sun_b = to_blender(*sun).normalized()

    light_data = bpy.data.lights.new("sun", "SUN")
    light_data.energy = 4.5 * lighting.get("brightness", 2) / 2
    light_data.angle = math.radians(2.5)
    light_data.color = (1.0, 0.97, 0.92)
    sun_obj = bpy.data.objects.new("sun", light_data)
    sun_obj.rotation_euler = sun_b.to_track_quat("-Z", "Y").to_euler()
    # to_track_quat aims -Z along the vector; the sun shines from sun_b, so point -Z at -sun_b.
    sun_obj.rotation_euler = (-sun_b).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(sun_obj)

    atmo = lighting.get("atmosphere")
    if atmo and atmo.get("density", 0) > 0:
        scene.view_layers[0].use_pass_mist = True
        world.mist_settings.start = 60
        world.mist_settings.depth = max(200.0, 900.0 * (1 - atmo["density"]))
        world.mist_settings.falloff = "QUADRATIC"


def setup_compositor(lighting):
    atmo = lighting.get("atmosphere")
    scene = bpy.context.scene
    if not atmo or atmo.get("density", 0) <= 0:
        return
    try:
        scene.use_nodes = True
        tree = scene.node_tree
    except AttributeError:
        return
    if tree is None:
        return
    nodes, links = tree.nodes, tree.links
    rl = nodes.get("Render Layers") or nodes.new("CompositorNodeRLayers")
    comp = nodes.get("Composite") or nodes.new("CompositorNodeComposite")
    mix = nodes.new("CompositorNodeMixRGB")
    haze_color = [srgb_to_linear(c) for c in atmo["color"]]
    mix.inputs[2].default_value = (*haze_color, 1)
    amount = nodes.new("CompositorNodeMath")
    amount.operation = "MULTIPLY"
    amount.inputs[1].default_value = min(0.85, 0.25 + atmo.get("haze", 0) * 0.2)
    links.new(rl.outputs["Mist"], amount.inputs[0])
    links.new(amount.outputs[0], mix.inputs[0])
    links.new(rl.outputs["Image"], mix.inputs[1])
    links.new(mix.outputs[0], comp.inputs["Image"])


def camera(name, eye, target, fov=70):
    cam_data = bpy.data.cameras.new(name)
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle_y = math.radians(fov)
    cam_data.clip_end = 3000
    cam = bpy.data.objects.new(name, cam_data)
    eye_b, target_b = to_blender(*eye), to_blender(*target)
    cam.location = eye_b
    cam.rotation_euler = (target_b - eye_b).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(cam)
    return cam


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser()
    parser.add_argument("dump")
    parser.add_argument("out")
    parser.add_argument("--views", default="spawn,overview")
    parser.add_argument("--samples", type=int, default=24)
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--cameras", help="json file with extra named cameras {name: [eye, target, fov]}")
    parser.add_argument("--dummies", help="json list of [x, y, z, yaw] avatar positions")
    args = parser.parse_args(argv)

    data = json.loads(Path(args.dump).read_text())
    if isinstance(data, list):
        data = data[0]
    if isinstance(data, str):
        data = json.loads(data)
    if not data.get("ok"):
        print("BUILD ERROR:", data.get("err"))
    for line in data.get("logs", []):
        print("log:", line[:300])
    print("mesh sources:", data.get("sources"))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_world(data.get("lighting", {}))
    build_parts(data["parts"])
    build_terrain(data["terrain"])
    dummies = json.loads(Path(args.dummies).read_text()) if args.dummies else [[0, 0.2, 26, 0], [4, 0.2, 22, 0.6], [-5, 0.2, 21, -0.4]]
    for d in dummies:
        add_dummy(d[:3], d[3] if len(d) > 3 else 0)
    setup_compositor(data.get("lighting", {}))

    views = {
        "spawn": [(0, 14, 48), (0, 6, 0), 70],
        "overview": [(0, 130, 190), (0, 0, 0), 70],
        "top": [(0, 420, 1), (0, 0, 0), 60],
        "vote": [(0, 12, -20), (0, 14, -90), 70],
    }
    if args.cameras:
        views.update(json.loads(Path(args.cameras).read_text()))
    scene = bpy.context.scene
    scene.cycles.samples = args.samples
    scene.render.resolution_x = args.width
    scene.render.resolution_y = int(args.width * 9 / 16)
    scene.render.image_settings.file_format = "PNG"
    for name in args.views.split(","):
        eye, target, fov = views[name]
        scene.camera = camera(name, eye, target, fov)
        scene.render.filepath = str(Path(f"{args.out}_{name}.png").resolve())
        bpy.ops.render.render(write_still=True)
        print("wrote", scene.render.filepath)


if __name__ == "__main__":
    main()

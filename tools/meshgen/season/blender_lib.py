"""Building blocks for the season models (Blender 5 via the `bpy` module): the concept renders and,
through export.py, the meshes the game uses (owner, on the crate seasons: "Can you make renders and
ideas for this?", then "I want you to actually work on adding it to the game right now ... I want it
to look insane."). Blender coordinates: Z up, things face -Y unless turned.

EXPORT (set by export.py) builds for the game instead of a render: rounder shapes get fewer sides
and the sparkles are left out (the game draws those with particles)."""

import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EXPORT = False
sys.path.insert(0, str(ROOT / "tools" / "preview"))
import render as R  # noqa: E402


def lin(c):
    c = c / 255.0 if c > 1.0 else c
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def col(h):
    if isinstance(h, str):
        h = h.lstrip("#")
        return tuple(lin(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4))
    return tuple(h[:3])


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))


# Season palette (sRGB hex).
NAVY, DEEP, ICE, CYAN = "#1b2466", "#0b1033", "#bfefff", "#6ff6ff"
GREEN, VIOLET, PINK, GOLD = "#5cffb0", "#b07cff", "#ff4fd8", "#ffd24a"
SILVER, SNOW = "#d6e6ff", "#f4f8ff"
TIER = {"coins": GOLD, "effect": "#4aa8ff", "hat": "#b26bff", "pet": PINK, "title": GREEN}

# ---------------------------------------------------------------------------------------------
# Collections, objects, materials

_coll = None


def use_collection(name):
    global _coll
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    _coll = c
    return c


def link(o):
    (_coll or bpy.context.scene.collection).objects.link(o)
    return o


_M = {}


def pbr(name, base, rough=0.5, metal=0.0, emit=None, es=0.0, trans=0.0, ior=1.45, alpha=1.0, sheen=0.0,
        coat=0.0, sss=0.0):
    if name in _M:
        return _M[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    i = b.inputs
    i["Base Color"].default_value = (*col(base), 1)
    i["Roughness"].default_value = rough
    i["Metallic"].default_value = metal
    i["IOR"].default_value = ior
    i["Alpha"].default_value = alpha
    i["Transmission Weight"].default_value = trans
    i["Sheen Weight"].default_value = sheen
    i["Coat Weight"].default_value = coat
    i["Subsurface Weight"].default_value = sss
    if emit:
        i["Emission Color"].default_value = (*col(emit), 1)
        i["Emission Strength"].default_value = es
    _M[name] = m
    return m


def glow(color, strength=8.0):
    return pbr(f"glow{color}{strength}", "#000000", rough=1, emit=color, es=strength)


def ice():
    return pbr("ice", "#cdeeff", rough=0.08, trans=1.0, ior=1.31, emit=CYAN, es=0.25, coat=0.5)


def snow():
    return pbr("snow", SNOW, rough=0.75, sss=0.25, sheen=0.4)


def vmat(name, strength=5.0):
    """Glowing, see-through: the mesh's Col attribute is the color and its alpha the opacity."""
    if name in _M:
        return _M[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    n, ln = nt.nodes, nt.links
    n.remove(n["Principled BSDF"])
    attr = n.new("ShaderNodeAttribute")
    attr.attribute_name = "Col"
    em = n.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = strength
    tr = n.new("ShaderNodeBsdfTransparent")
    mx = n.new("ShaderNodeMixShader")
    ln.new(attr.outputs["Color"], em.inputs["Color"])
    ln.new(attr.outputs["Alpha"], mx.inputs["Fac"])
    ln.new(tr.outputs[0], mx.inputs[1])
    ln.new(em.outputs[0], mx.inputs[2])
    ln.new(mx.outputs[0], n["Material Output"].inputs["Surface"])
    _M[name] = m
    return m


def vsolid(name, strength=6.0, rough=0.45, sheen=0.6):
    """A solid surface colored by Col, glowing by Col's alpha (0 = not at all)."""
    if name in _M:
        return _M[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    n, ln = nt.nodes, nt.links
    b = n["Principled BSDF"]
    b.inputs["Roughness"].default_value = rough
    b.inputs["Sheen Weight"].default_value = sheen
    attr = n.new("ShaderNodeAttribute")
    attr.attribute_name = "Col"
    k = n.new("ShaderNodeMath")
    k.operation = "MULTIPLY"
    k.inputs[1].default_value = strength
    ln.new(attr.outputs["Color"], b.inputs["Base Color"])
    ln.new(attr.outputs["Color"], b.inputs["Emission Color"])
    ln.new(attr.outputs["Alpha"], k.inputs[0])
    ln.new(k.outputs[0], b.inputs["Emission Strength"])
    _M[name] = m
    return m


def image_mat(path, strength=1.5, alpha=False):
    key = f"img{path}{strength}"
    if key in _M:
        return _M[key]
    m = bpy.data.materials.new("screen")
    m.use_nodes = True
    nt = m.node_tree
    n, ln = nt.nodes, nt.links
    n.remove(n["Principled BSDF"])
    tex = n.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(path))
    em = n.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = strength
    ln.new(tex.outputs["Color"], em.inputs["Color"])
    out = n["Material Output"].inputs["Surface"]
    if alpha:
        tr = n.new("ShaderNodeBsdfTransparent")
        mx = n.new("ShaderNodeMixShader")
        ln.new(tex.outputs["Alpha"], mx.inputs["Fac"])
        ln.new(tr.outputs[0], mx.inputs[1])
        ln.new(em.outputs[0], mx.inputs[2])
        ln.new(mx.outputs[0], out)
    else:
        ln.new(em.outputs[0], out)
    _M[key] = m
    return m


_DEFAULT = None
_ME = {}
SMOOTH = {"sphere", "lsphere", "cyl", "cone", "torus", "half"}


def prim(kind):
    global _DEFAULT
    if kind in _ME:
        return _ME[kind]
    bm = bmesh.new()
    lo = EXPORT
    if kind == "sphere":
        bmesh.ops.create_uvsphere(bm, u_segments=20 if lo else 48, v_segments=10 if lo else 24, radius=1)
    elif kind == "lsphere":
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=1)
    elif kind == "half":
        bmesh.ops.create_uvsphere(bm, u_segments=24 if lo else 48, v_segments=12 if lo else 24, radius=1)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.05], context="VERTS")
    elif kind == "ico":
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1)
    elif kind == "ico2":
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1)
    elif kind == "cube":
        bmesh.ops.create_cube(bm, size=2)
    elif kind == "cyl":
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=20 if lo else 48, radius1=1, radius2=1, depth=2)
    elif kind == "hex":
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=6, radius1=1, radius2=1, depth=2)
    elif kind == "cone":
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=16 if lo else 40, radius1=1, radius2=0, depth=2)
    elif kind == "cone6":
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=6, radius1=1, radius2=0, depth=2)
    elif kind == "torus":
        bm.free()
        me = torus_mesh(1.0, 0.12, 28 if EXPORT else 64, 8 if EXPORT else 16)
        _ME[kind] = me
        return me
    me = bpy.data.meshes.new(kind)
    bm.to_mesh(me)
    bm.free()
    if kind in SMOOTH:
        me.shade_smooth()
    if _DEFAULT is None:
        _DEFAULT = pbr("default", "#888888")
    me.materials.append(_DEFAULT)
    _ME[kind] = me
    return me


def torus_mesh(major, minor, seg=64, ring=16):
    verts, faces = [], []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        for j in range(ring):
            b = 2 * math.pi * j / ring
            r = major + minor * math.cos(b)
            verts.append((r * math.cos(a), r * math.sin(a), minor * math.sin(b)))
    for i in range(seg):
        for j in range(ring):
            a0, a1 = i * ring + j, i * ring + (j + 1) % ring
            b0, b1 = ((i + 1) % seg) * ring + j, ((i + 1) % seg) * ring + (j + 1) % ring
            faces.append((a0, b0, b1, a1))
    me = bpy.data.meshes.new("torus")
    me.from_pydata(verts, [], faces)
    me.shade_smooth()
    me.materials.append(pbr("default", "#888888"))
    return me


def torus(loc, major, minor, m, rot=(0, 0, 0), parent=None):
    key = f"torus{round(minor / major, 3)}"
    if key not in _ME:
        _ME[key] = torus_mesh(1.0, minor / major, 28 if EXPORT else 64, 8 if EXPORT else 16)
    return obj(_ME[key], loc, major, rot, m, parent)


def rbox(dims, bevel):
    key = ("rbox", tuple(round(d, 3) for d in dims), round(bevel, 3))
    if key in _ME:
        return _ME[key]
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        v.co = Vector((v.co.x * dims[0], v.co.y * dims[1], v.co.z * dims[2]))
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=3, profile=0.5, affect="EDGES")
    me = bpy.data.meshes.new("rbox")
    bm.to_mesh(me)
    bm.free()
    me.shade_smooth()
    me.materials.append(pbr("default", "#888888"))
    _ME[key] = me
    return me


def obj(kind, loc=(0, 0, 0), scale=1.0, rot=(0, 0, 0), m=None, parent=None, name=None, sub=0):
    me = prim(kind) if isinstance(kind, str) else kind
    o = bpy.data.objects.new(name or me.name, me)
    o.location = loc
    o.scale = (scale, scale, scale) if isinstance(scale, (int, float)) else scale
    o.rotation_euler = rot
    if parent is not None:
        o.parent = parent
    link(o)
    if m is not None:
        o.material_slots[0].link = "OBJECT"
        o.material_slots[0].material = m
    if sub:
        mod = o.modifiers.new("s", "SUBSURF")
        mod.levels = sub
        mod.render_levels = sub
    return o


def group(loc=(0, 0, 0), rot=(0, 0, 0), scale=1.0, parent=None):
    e = bpy.data.objects.new("g", None)
    e.location = loc
    e.rotation_euler = rot
    e.scale = (scale, scale, scale) if isinstance(scale, (int, float)) else scale
    if parent is not None:
        e.parent = parent
    link(e)
    return e


def point_light(loc, color, power, radius=0.5, parent=None):
    if EXPORT:
        return None  # the game adds its own lights
    ld = bpy.data.lights.new("pl", "POINT")
    ld.energy = power
    ld.color = col(color)
    ld.shadow_soft_size = radius
    o = bpy.data.objects.new("pl", ld)
    o.location = loc
    if parent is not None:
        o.parent = parent
    link(o)
    return o


def area_light(loc, target, color, power, size=4):
    ld = bpy.data.lights.new("al", "AREA")
    ld.energy = power
    ld.color = col(color)
    ld.size = size
    o = bpy.data.objects.new("al", ld)
    o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    link(o)
    return o


def yaw_to(src, dst):
    d = Vector(dst) - Vector(src)
    return math.atan2(d.x, -d.y)


def rb(x, y, z):
    """A Roblox position in Blender coordinates."""
    return Vector((x, -z, y))


# ---------------------------------------------------------------------------------------------
# Curves: tubes and sheets with per-vertex color (Col)

def catmull(ctrl, n=10):
    pts = [Vector(p) for p in ctrl]
    P = [pts[0]] + pts + [pts[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(pts[-1])
    return out


def _finish(me, cols, m):
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    flat = [c for rgba in cols for c in rgba]
    attr.data.foreach_set("color", flat)
    me.shade_smooth()
    me.materials.append(m)


def tube(pts, rfn, cfn, m, seg=16, parent=None, name="tube"):
    if EXPORT:
        seg = max(6, seg // 2)
        pts = pts[::2] + ([pts[-1]] if (len(pts) - 1) % 2 else [])
    N = len(pts)
    T = [(pts[min(i + 1, N - 1)] - pts[max(i - 1, 0)]).normalized() for i in range(N)]
    up = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((1, 0, 0))
    nrm = T[0].cross(up).normalized()
    verts, cols, faces = [], [], []
    for i in range(N):
        if i > 0:
            axis = T[i - 1].cross(T[i])
            if axis.length > 1e-6:
                nrm = Matrix.Rotation(T[i - 1].angle(T[i]), 3, axis.normalized()) @ nrm
        b = T[i].cross(nrm)
        t = i / (N - 1)
        r, c = rfn(t), cfn(t)
        for k in range(seg):
            a = 2 * math.pi * k / seg
            verts.append(pts[i] + (nrm * math.cos(a) + b * math.sin(a)) * r)
            cols.append(c)
    for i in range(N - 1):
        for k in range(seg):
            a, b2 = i * seg + k, i * seg + (k + 1) % seg
            faces.append((a, b2, b2 + seg, a + seg))
    # Caps.
    verts.append(pts[0] - T[0] * rfn(0) * 0.3)
    cols.append(cfn(0))
    verts.append(pts[-1] + T[-1] * rfn(1) * 0.3)
    cols.append(cfn(1))
    s0, s1 = len(verts) - 2, len(verts) - 1
    for k in range(seg):
        faces.append((s0, (k + 1) % seg, k))
        base = (N - 1) * seg
        faces.append((base + k, base + (k + 1) % seg, s1))
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    _finish(me, cols, m)
    o = bpy.data.objects.new(name, me)
    if parent is not None:
        o.parent = parent
    link(o)
    return o


def sheet(path, hfn, cfn, m, nv=8, up=(0, 0, 1), parent=None, name="sheet"):
    """A curtain: for each path point, a column up `up` of height hfn(u); cfn(u, v) its color."""
    up = Vector(up)
    N = len(path)
    verts, cols, faces = [], [], []
    for i, p in enumerate(path):
        u = i / (N - 1)
        h = hfn(u)
        for j in range(nv + 1):
            v = j / nv
            verts.append(tuple(p + up * h * v))
            cols.append(cfn(u, v))
    for i in range(N - 1):
        for j in range(nv):
            a = i * (nv + 1) + j
            faces.append((a, a + nv + 1, a + nv + 2, a + 1))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    _finish(me, cols, m)
    o = bpy.data.objects.new(name, me)
    if parent is not None:
        o.parent = parent
    link(o)
    return o


def ribbon(path, wfn, cfn, m, side=(0, 0, 1), parent=None, name="ribbon"):
    """A flat strip along `path`, width wfn(u) across `side`; cfn(u, v) its color."""
    return sheet([Vector(p) - Vector(side) * wfn(i / (len(path) - 1)) / 2 for i, p in enumerate(path)],
                 wfn, cfn, m, nv=2, up=side, parent=parent, name=name)


def blob(loc, scale, m, seed=0, amp=0.12, freq=1.6, parent=None, res=48):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=res, v_segments=res // 2, radius=1)
    off = Vector((seed * 7.1, seed * 3.3, seed * 1.7))
    for v in bm.verts:
        n = noise.noise(v.co * freq + off)
        v.co = v.co * (1 + amp * n)
    me = bpy.data.meshes.new("blob")
    bm.to_mesh(me)
    bm.free()
    me.shade_smooth()
    me.materials.append(m)
    o = bpy.data.objects.new("blob", me)
    o.location = loc
    o.scale = scale
    if parent is not None:
        o.parent = parent
    link(o)
    return o


def plane_uv(w, h):
    me = bpy.data.meshes.new("plane")
    me.from_pydata([(-w / 2, -h / 2, 0), (w / 2, -h / 2, 0), (w / 2, h / 2, 0), (-w / 2, h / 2, 0)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new()
    for i, c in enumerate([(0, 0), (1, 0), (1, 1), (0, 1)]):
        uv.data[i].uv = c
    return me


def screen(path, loc, w, h, rot, strength=1.5, alpha=False, parent=None):
    me = plane_uv(w, h)
    me.materials.append(image_mat(path, strength, alpha))
    o = bpy.data.objects.new("screen", me)
    o.location = loc
    o.rotation_euler = rot
    if parent is not None:
        o.parent = parent
    link(o)
    return o


_FONTS = {}


def text(body, loc, size, m, font="LuckiestGuy", rot=(math.pi / 2, 0, 0), extrude=0.02, parent=None):
    if font not in _FONTS:
        _FONTS[font] = bpy.data.fonts.load(str(HERE / "fonts" / f"{font}.ttf"))
    cu = bpy.data.curves.new("t", "FONT")
    cu.body = body
    cu.font = _FONTS[font]
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = extrude
    o = bpy.data.objects.new("t", cu)
    o.data.materials.append(m)
    o.location = loc
    o.rotation_euler = rot
    if parent is not None:
        o.parent = parent
    link(o)
    return o


# ---------------------------------------------------------------------------------------------
# Avatars

def avatar(loc, yaw=0.0, shirt="#3a7bff", pants="#22284a", skin="#ffd0a0", arms=0.0, arms_fwd=0.0, run=0.0,
           parent=None):
    """A blocky R15-sized avatar (5.2 studs), feet at loc, facing -Y turned by yaw. arms: raise angle
    (0 down, pi up); run: stride angle."""
    g = group(loc, (0, 0, yaw), 1.0, parent)
    sk = pbr(f"skin{skin}", skin, rough=0.5)
    sh = pbr(f"shirt{shirt}", shirt, rough=0.6)
    pa = pbr(f"pants{pants}", pants, rough=0.7)
    dark = pbr("eye", "#14142a", rough=0.2)
    obj(rbox((1.25, 1.2, 1.2), 0.28), (0, 0, 4.62), 1, m=sk, parent=g)
    for sx in (-1, 1):
        obj("sphere", (sx * 0.24, -0.6, 4.72), (0.09, 0.04, 0.15), m=dark, parent=g)
    obj(rbox((0.36, 0.06, 0.08), 0.02), (0, -0.6, 4.36), 1, m=dark, parent=g)
    obj(rbox((2.0, 1.0, 2.0), 0.14), (0, 0, 3.0), 1, m=sh, parent=g)
    for sx in (-1, 1):
        sh_g = group((sx * 1.5, 0, 3.9), (-arms_fwd + run * sx, -sx * arms, 0), 1, g)
        obj(rbox((0.96, 0.96, 2.0), 0.14), (0, 0, -0.9), 1, m=sk, parent=sh_g)
        hip = group((sx * 0.5, 0, 2.0), (-run * sx, 0, 0), 1, g)
        obj(rbox((0.96, 0.96, 2.0), 0.14), (0, 0, -1.0), 1, m=pa, parent=hip)
    return g


# ---------------------------------------------------------------------------------------------
# The Frostfall crate and key

def snowflake(loc, rot, size, m, parent):
    g = group(loc, rot, size, parent)
    for a in (0, 60, 120):
        r = math.radians(a)
        obj("cube", (0, 0, 0), (0.5, 0.035, 0.05), (0, r, 0), m, g)
        for s in (-1, 1):
            cx, cz = math.cos(r) * 0.3 * s, -math.sin(r) * 0.3 * s
            for b in (-1, 1):
                obj("cube", (cx + math.cos(r + b * 0.8 * s) * 0.08 * s, 0, cz - math.sin(r + b * 0.8 * s) * 0.08 * s),
                    (0.12, 0.03, 0.035), (0, r + b * 0.9, 0), m, g)
    obj("hex", (0, -0.02, 0), (0.13, 0.13, 0.05), (math.pi / 2, 0, 0), ice(), g)
    return g


def crate(loc, scale=1.0, rot=(0, 0, 0), lid=0.0, lid_at=None, inner=None, parent=None, seam=CYAN,
          snowcap=True, icicles=True):
    """The Frostfall crate (3 x 3 x 3 studs at scale 1), base at loc. lid: hinge angle (radians,
    opens backwards); lid_at: (loc, rot) of a lid blown off instead; inner: glow color inside."""
    W, H, LH = 3.0, 2.2, 0.8
    g = group(loc, rot, scale, parent)
    wood = pbr("crate_wood", "#3046b8", rough=0.5, coat=0.4)
    metal = pbr("crate_metal", SILVER, rough=0.22, metal=1.0)
    gold = pbr("crate_gold", GOLD, rough=0.25, metal=1.0)
    obj(rbox((W, W, H), 0.1), (0, 0, H / 2), 1, m=wood, parent=g)
    for sx in (-1, 1):
        for sy in (-1, 1):
            obj(rbox((0.42, 0.42, H + 0.02), 0.08), (sx * (W / 2 - 0.12), sy * (W / 2 - 0.12), H / 2), 1, m=metal, parent=g)
            obj(rbox((0.56, 0.56, 0.56), 0.12), (sx * (W / 2 - 0.12), sy * (W / 2 - 0.12), 0.26), 1, m=gold, parent=g)
    obj(rbox((W + 0.1, W + 0.1, 0.28), 0.06), (0, 0, 0.14), 1, m=metal, parent=g)
    obj(rbox((W + 0.06, W + 0.06, 0.12), 0.03), (0, 0, H - 0.04), 1, m=glow(seam, 9), parent=g)
    for k in range(4):
        a = k * math.pi / 2
        face = group((math.sin(a) * (W / 2 + 0.02), -math.cos(a) * (W / 2 + 0.02), H / 2 - 0.05), (0, 0, a), 1, g)
        obj(rbox((1.5, 0.1, 1.5), 0.2), (0, 0.02, 0), (1, 1, 1), (0, math.pi / 4, 0), metal, face)
        obj(rbox((1.3, 0.1, 1.3), 0.18), (0, -0.01, 0), (1, 1, 1), (0, math.pi / 4, 0), wood, face)
        snowflake((0, -0.07, 0), (0, 0, 0), 1.25, glow(seam, 7), face)
    if inner:
        obj("cube", (0, 0, H - 0.08), (W / 2 - 0.2, W / 2 - 0.2, 0.02), m=glow(inner, 30), parent=g)
        point_light((0, 0, H + 0.6), inner, 800, 0.8, g)
    if lid_at:
        lg = group(lid_at[0], lid_at[1], 1, g)
        body = group((0, W / 2, 0), (0, 0, 0), 1, lg)
    else:
        lg = group((0, W / 2, H), (-lid, 0, 0), 1, g)
        body = lg
    obj(rbox((W + 0.14, W + 0.14, LH), 0.16), (0, -W / 2, LH / 2), 1, m=wood, parent=body)
    obj(rbox((W + 0.24, W + 0.24, 0.2), 0.06), (0, -W / 2, 0.1), 1, m=metal, parent=body)
    obj("hex", (0, -W / 2, LH + 0.02), (0.6, 0.6, 0.05), m=gold, parent=body)
    obj("ico", (0, -W / 2, LH + 0.22), 0.26, m=ice(), parent=body)
    if snowcap:
        blob((0, -W / 2, LH - 0.02), (W / 2 * 0.92, W / 2 * 0.92, 0.26), snow(), seed=random.random() * 9, amp=0.15,
             parent=body)
    if icicles:
        for i in range(6):
            x = -W / 2 + 0.3 + i * (W - 0.6) / 5
            ln = 0.18 + 0.22 * ((i * 37) % 5) / 4
            obj("cone6", (x, -W - 0.06, -ln), (0.07, 0.07, ln), (math.pi, 0, 0), ice(), body)
    return g


def key(loc, rot=(0, 0, 0), scale=1.0, parent=None):
    """The Frost Key (about 2.4 studs long at scale 1), lying along +X."""
    g = group(loc, rot, scale, parent)
    gold = pbr("crate_gold", GOLD, rough=0.25, metal=1.0)
    torus((0, 0, 0), 0.55, 0.13, gold, (math.pi / 2, 0, 0), g)
    obj("hex", (0, 0, 0), (0.36, 0.36, 0.09), (math.pi / 2, 0, 0), glow(CYAN, 10), g)
    obj("ico", (0, -0.05, 0), 0.18, m=ice(), parent=g)
    obj("cyl", (1.25, 0, 0), (0.1, 0.1, 0.75), (0, math.pi / 2, 0), pbr("crate_metal", SILVER, 0.22, 1.0), g)
    obj("cube", (0.62, 0, 0), (0.08, 0.16, 0.16), m=gold, parent=g)
    for i, (x, h) in enumerate([(1.55, 0.36), (1.85, 0.26)]):
        obj(rbox((0.16, 0.14, h), 0.03), (x, 0, -h / 2), 1, m=glow(CYAN, 6), parent=g)
    obj("cone6", (2.08, 0, 0), (0.12, 0.12, 0.16), (0, math.pi / 2, 0), ice(), g)
    return g


def coin(loc, rot=(0, 0, 0), scale=1.0, parent=None):
    g = group(loc, rot, scale, parent)
    gold = pbr("coin", "#ffc21a", rough=0.25, metal=1.0, emit="#ffb000", es=0.4)
    obj("cyl", (0, 0, 0), (0.55, 0.55, 0.08), m=gold, parent=g)
    obj("cyl", (0, 0, 0), (0.4, 0.4, 0.1), m=pbr("coin_in", "#ffb81f", 0.3, 1.0), parent=g)
    return g


# ---------------------------------------------------------------------------------------------
# Beams and bursts

def beam(base, height, r0, r1, color, strength=5.0, core=None, parent=None):
    c = col(color)
    core = core or "#%02x%02x%02x" % tuple(int(255 * (0.55 + 0.45 * (x ** (1 / 2.2)))) for x in c)
    pts = [Vector(base) + Vector((0, 0, height * k / 20)) for k in range(21)]
    tube(pts, lambda t: r0 + (r1 - r0) * t, lambda t: (*c, 0.6 * (1 - t) ** 1.6), vmat(f"beam{color}{strength}", strength),
         seg=32, parent=parent, name="beam")
    cw = col(core)
    tube(pts, lambda t: r0 * 0.35 + (r1 - r0) * 0.2 * t, lambda t: (*cw, 0.9 * (1 - t) ** 2.2),
         vmat(f"beamcore{core}{strength}", strength * 1.4), seg=24, parent=parent, name="beamcore")


def ring_burst(center, radius, color, strength=8, parent=None, width=0.35):
    c = col(color)
    pts = [Vector(center) + Vector((math.cos(a) * radius, math.sin(a) * radius, 0))
           for a in [2 * math.pi * k / 96 for k in range(97)]]
    ribbon(pts, lambda u: width, lambda u, v: (*c, 0.95 * (1 - abs(v - 0.5) * 2) ** 0.6), vmat(f"ring{color}", strength),
           side=(0, 0, 1), parent=parent, name="ringburst")


def sparks(center, radius, n, colors, size=(0.05, 0.12), seed=1, z=(0, 1), parent=None, strength=12):
    if EXPORT:
        return  # the game draws sparkles with particles
    rng = random.Random(seed)
    for _ in range(n):
        a = rng.uniform(0, 2 * math.pi)
        r = radius * rng.uniform(0.3, 1.0)
        h = rng.uniform(*z)
        obj("ico", Vector(center) + Vector((math.cos(a) * r, math.sin(a) * r, h)), rng.uniform(*size),
            (rng.random(), rng.random(), rng.random()), glow(rng.choice(colors), strength), parent)


def aurora_curtain(center, radius, a0, a1, z0, height, parent=None, strength=4.0, wave=0.15, n=90, alpha=0.7):
    g, cy, v = col(GREEN), col(CYAN), col(VIOLET)

    def c(u, t):
        base = mix(g, cy, min(1, t * 1.6)) if t < 0.6 else mix(cy, v, (t - 0.6) / 0.4)
        edge = math.sin(math.pi * u) ** 0.5
        fade = (1 - t) ** 1.3 * min(1, t * 6)
        rays = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(u * 140 + math.sin(u * 23) * 4)) ** 2
        return (*base, alpha * edge * fade * rays)

    n = max(n, int(abs(a1 - a0) * radius * 1.5))
    pts = []
    for k in range(n + 1):
        a = a0 + (a1 - a0) * k / n
        rr = radius * (1 + wave * math.sin(a * 5) * 0.5)
        pts.append(Vector(center) + Vector((math.cos(a) * rr, math.sin(a) * rr, z0 + math.sin(a * 3) * height * 0.08)))
    return sheet(pts, lambda u: height * (0.75 + 0.25 * math.sin(u * 17)), c, vmat("aurora", strength), nv=12,
                 parent=parent, name="aurora")


# ---------------------------------------------------------------------------------------------
# Scene setup

def bloom(threshold=1.0, strength=0.7, size=0.6):
    scene = bpy.context.scene
    ng = bpy.data.node_groups.new("comp", "CompositorNodeTree")
    ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    rl = ng.nodes.new("CompositorNodeRLayers")
    g = ng.nodes.new("CompositorNodeGlare")
    out = ng.nodes.new("NodeGroupOutput")
    g.inputs["Type"].default_value = "Bloom"
    g.inputs["Threshold"].default_value = threshold
    g.inputs["Strength"].default_value = strength
    g.inputs["Size"].default_value = size
    ng.links.new(rl.outputs["Image"], g.inputs["Image"])
    ng.links.new(g.outputs["Image"], out.inputs[0])
    scene.compositing_node_group = ng


def studio_world(top="#0b1033", bottom="#1b1f5a", strength=0.6):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.use_denoising = True
    scene.cycles.transparent_max_bounces = 48
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    n, ln = world.node_tree.nodes, world.node_tree.links
    bg = n["Background"]
    tc = n.new("ShaderNodeTexCoord")
    sp = n.new("ShaderNodeSeparateXYZ")
    rp = n.new("ShaderNodeValToRGB")
    rp.color_ramp.elements[0].color = (*col(bottom), 1)
    rp.color_ramp.elements[1].color = (*col(top), 1)
    rp.color_ramp.elements[1].position = 0.5
    ln.new(tc.outputs["Generated"], sp.inputs[0])
    ln.new(sp.outputs["Z"], rp.inputs["Fac"])
    ln.new(rp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength


def cam(eye, target, fov=40, lens_shift=(0, 0)):
    cd = bpy.data.cameras.new("cam")
    cd.sensor_fit = "VERTICAL"
    cd.angle_y = math.radians(fov)
    cd.clip_end = 5000
    cd.shift_x, cd.shift_y = lens_shift
    c = bpy.data.objects.new("cam", cd)
    c.location = Vector(eye)
    c.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(c)
    bpy.context.scene.camera = c
    return c


def render(path, w, h, samples):
    s = bpy.context.scene
    s.cycles.samples = samples
    s.render.resolution_x = w
    s.render.resolution_y = h
    s.render.image_settings.file_format = "PNG"
    s.render.filepath = str(path)
    s.render.use_persistent_data = True
    bpy.ops.render.render(write_still=True)
    print("wrote", path)

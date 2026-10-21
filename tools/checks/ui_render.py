"""Draws the player's on-screen UI from a harness snapshot at several screen sizes (PC and phones),
with Roblox's own buttons, the touch thumbstick and the jump button drawn on top, and reports
overlaps, anything off-screen or outside the safe area, text that's cut off, and text too small to
read on a phone, so layouts can be checked without a device.

    python3 tools/checks/round_harness.py HoneyTrap --client --ui-at 2,12 ... > run.luau
    python3 tools/preview/luau_task.py run.luau - run.json
    python3 tools/checks/ui_render.py run.json /tmp/honey_ui            # every snapshot, every size
    python3 tools/checks/ui_render.py run.json /tmp/honey_ui --sizes phone

Layout follows Roblox's rules for what the HUD uses: UDim2 position/size/anchor, AutomaticSize,
UIScale (the UIKit.AutoScale ones are recomputed for each screen), UIListLayout, UIGridLayout,
UIPadding, UIAspectRatioConstraint, ScrollingFrame canvases and clipping, sibling ZIndex order,
UICorner, UIGradient, UIStroke and text (TextScaled, wrapping, truncation, alignment). Text is laid
out with the engine's own measurements when the snapshot has them (tools/checks/gui_dump.luau) and
drawn with stand-in fonts squeezed to those widths. Images are drawn as placeholders.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / "tools" / "art" / "fonts"
DESIGN = (1280, 720)
MIN_SCALE, MAX_SCALE = 0.62, 1.35
TOPBAR = 58
SMALL_TEXT = 10  # px: smaller text is reported on touch screens
FIT_MARGIN = 8  # UI/Modal.luau: room around a window shrunk to fit the screen

# name: (width, height, side safe inset, touch controls)
SIZES = {
    "pc": (1280, 720, 0, False),
    "pc-hd": (1920, 1080, 0, False),
    "phone": (844, 390, 47, True),  # notched phone, landscape
    "phone-small": (667, 375, 0, True),
    "tablet": (1024, 768, 0, True),
}
SIZE_GROUPS = {"phone": ["phone", "phone-small"], "pc": ["pc", "pc-hd"], "touch": ["phone", "phone-small", "tablet"], "all": list(SIZES)}
MODIFIERS = ("UIScale", "UICorner", "UIStroke", "UIGradient", "UIListLayout", "UIGridLayout", "UIPadding",
             "UIAspectRatioConstraint", "UITextSizeConstraint", "UISizeConstraint")

# Each character is drawn with the node's font when that has the glyph; pictographs prefer the
# emoji font; anything else falls back to the emoji font, then DejaVu (which has most symbols).
EMOJI = re.compile("[\\U0001F000-\\U0001FAFF\\u2600-\\u2604\\u2606-\\u265F\\u2668-\\u27BF\\u2B00-\\u2BFF\\u2300-\\u23FF]")
NOTO = str(FONTS / "NotoEmoji.ttf")
DEJAVU = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SANS = [("/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf", "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf"),
        (DEJAVU, "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")]
_font_cache: dict = {}
_cmap_cache: dict = {}


def font_path(name: str) -> str:
    if "Fredoka" in name:
        return str(FONTS / "Fredoka.ttf")
    if "Luckiest" in name:
        return str(FONTS / "LuckiestGuy-Regular.ttf")
    bold = any(word in name for word in ("Bold", "Black", "Heavy", "Builder", "Gotham"))
    return next(pair[0 if bold else 1] for pair in SANS if Path(pair[0]).exists())


def covers(path: str, ch: str) -> bool:
    if path not in _cmap_cache:
        try:
            from fontTools.ttLib import TTFont

            _cmap_cache[path] = set(TTFont(path, lazy=True).getBestCmap())
        except Exception:
            _cmap_cache[path] = None  # without fontTools, trust the font
    cmap = _cmap_cache[path]
    return cmap is None or ord(ch) in cmap


def font_at(path: str, size: float) -> ImageFont.FreeTypeFont:
    key = (path, max(4, int(round(size))))
    if key not in _font_cache:
        result = ImageFont.truetype(path, key[1])
        if path.endswith("Fredoka.ttf"):
            try:
                result.set_variation_by_name("SemiBold")
            except Exception:
                pass
        _font_cache[key] = result
    return _font_cache[key]


def font(name: str, size: float) -> ImageFont.FreeTypeFont:
    return font_at(font_path(name), size)


def runs(text: str, name: str) -> list[tuple[str, str]]:
    """Splits text into (font file, piece) runs."""
    main = font_path(name)
    out: list[tuple[str, str]] = []
    for ch in text:
        if ch in "\ufe0f\u200d":
            continue
        if EMOJI.match(ch) and covers(NOTO, ch):
            path = NOTO
        elif covers(main, ch):
            path = main
        elif covers(NOTO, ch):
            path = NOTO
        else:
            path = DEJAVU
        if out and out[-1][0] == path:
            out[-1] = (path, out[-1][1] + ch)
        else:
            out.append((path, ch))
    return out


def text_width(text: str, name: str, size: float) -> float:
    """Width with the stand-in fonts (used to draw, and when the snapshot has no measurements)."""
    return sum(font_at(path, size).getlength(piece) for path, piece in runs(text, name))


class Text:
    """A text node's words and their widths at TextSize 100: the engine's measurements from the
    snapshot when it has them, else estimates with the stand-in fonts."""

    def __init__(self, n: dict):
        raw = n.get("text") or ""
        self.raw = re.sub(r"<[^>]+>", "", raw)
        self.name = n.get("font", "")
        self.paragraphs = [p.split(" ") for p in self.raw.split("\n")]
        tw = n.get("tw")
        if tw and len(tw) == len(self.paragraphs) and all(len(a) == len(b) for a, b in zip(tw, self.paragraphs)):
            self.widths, self.space, self.line = tw, n.get("sw", 20), n.get("lh", 1.0)
        else:
            self.widths = [[text_width(w, self.name, 100) for w in p] for p in self.paragraphs]
            self.space, self.line = text_width(" ", self.name, 100), 1.15

    def wrap(self, size: float, width: float, enabled: bool) -> list[tuple[str, float]]:
        """Lines as (text, width in px) at this size."""
        k = size / 100
        lines = []
        for words, widths in zip(self.paragraphs, self.widths):
            current, current_w = [], 0.0
            for word, w in zip(words, widths):
                candidate = w if not current else current_w + self.space + w
                if not enabled or not current or candidate * k <= width + 0.5:
                    current.append(word)
                    current_w = candidate
                else:
                    lines.append((" ".join(current), current_w * k))
                    current, current_w = [word], w
            lines.append((" ".join(current), current_w * k))
        return lines

    def fit(self, w: float, h: float, wrapping: bool, low: float = 1, high: float = 100) -> float:
        """TextScaled: the biggest size that fits the box."""
        best = max(1, low)
        for size in range(max(1, int(low)), int(high) + 1):
            lines = self.wrap(size, w, wrapping)
            if max(lw for _, lw in lines) <= w and len(lines) * size * self.line <= h:
                best = size
            else:
                break
        return best


class Transform:
    """p -> p * k + b (uniform scale plus offset), composed from nested UIScales."""

    def __init__(self, k=1.0, bx=0.0, by=0.0):
        self.k, self.bx, self.by = k, bx, by

    def apply(self, x, y):
        return x * self.k + self.bx, y * self.k + self.by

    def then_scale_about(self, ax, ay, s):
        # New transform: first scale about (ax, ay) by s (in local coords), then this one.
        return Transform(self.k * s, self.bx + self.k * (ax - ax * s), self.by + self.k * (ay - ay * s))


def rgba(color, transparency=0.0):
    return (int(color[0]), int(color[1]), int(color[2]), int(round(255 * (1 - max(0.0, min(1.0, transparency))))))


def intersect(a, b):
    if a is None:
        return b
    if b is None:
        return a
    return (max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3]))


def render(nodes: list, size_name: str, out: Path):
    vw, vh, side, touch = SIZES[size_name]
    children = defaultdict(list)
    for index, node in enumerate(nodes, start=1):
        children[node["p"]].append(index)

    def node(i):
        return nodes[i - 1]

    def modifier(i, cls):
        for c in children[i]:
            if node(c)["c"] == cls:
                return node(c)
        return None

    def gui_kids(i):
        return [c for c in children[i] if node(c)["c"] not in MODIFIERS]

    raw_scale = min(vw / DESIGN[0], vh / DESIGN[1])
    auto_scale = max(MIN_SCALE, min(MAX_SCALE, raw_scale))  # UIKit.CurrentScale()
    draws = []  # (paint order, node, screen rect, scale, clip rect, text layout)
    boxes = []  # content boxes for the checks: (screen, path, x0, y0, x1, y1, label, paint order)
    dimmers = []  # paint order of full-screen dimmers (pop-up backdrops)
    problems = []
    counter = [0]

    def node_scale(i):
        """The scale a node's own UIScale applies (UIKit.AutoScale ones redone for this screen)."""
        scale_mod = modifier(i, "UIScale")
        if not scale_mod:
            return 1.0
        if scale_mod.get("auto"):
            return max(MIN_SCALE, min(MAX_SCALE, raw_scale * scale_mod["auto"]))
        return scale_mod.get("scale", 1)

    def path_of(i):
        parts = []
        while i:
            parts.append(node(i)["n"])
            i = node(i)["p"]
        return "/".join(reversed(parts))

    def padding_of(i, w, h):
        padding = modifier(i, "UIPadding")
        if not padding:
            return 0.0, 0.0, 0.0, 0.0
        (lsc, lof), (rsc, rof), (tsc, tof), (bsc, bof) = padding["pad"]
        return lsc * w + lof, rsc * w + rof, tsc * h + tof, bsc * h + bof

    def grid_layout(grid, cw, ch, count):
        cell_w = grid["cell"][0] * cw + grid["cell"][1]
        cell_h = grid["cell"][2] * ch + grid["cell"][3]
        pad_x = grid["cpad"][0] * cw + grid["cpad"][1]
        pad_y = grid["cpad"][2] * ch + grid["cpad"][3]
        horizontal = grid.get("dir", "Horizontal") == "Horizontal"
        room, cell, gap = (cw, cell_w, pad_x) if horizontal else (ch, cell_h, pad_y)
        per = max(1, int((room + gap + 1e-6) // max(1e-6, cell + gap)))
        if grid.get("maxcells"):
            per = min(per, grid["maxcells"])
        per = min(per, max(1, count))
        lines = math.ceil(count / per) if count else 0
        cols, rows = (per, lines) if horizontal else (lines, per)
        block_w = cols * cell_w + max(0, cols - 1) * pad_x
        block_h = rows * cell_h + max(0, rows - 1) * pad_y
        return cell_w, cell_h, pad_x, pad_y, per, horizontal, block_w, block_h

    def measure(i, pw, ph):
        """A node's size in its parent's units: Size, AutomaticSize, then the aspect ratio."""
        n = node(i)
        sx, ox, sy, oy = n["size"]
        w, h = sx * pw + ox, sy * ph + oy
        auto = n.get("autosize", "None")
        if auto != "None":
            w, h = auto_size(i, w, h, auto)
        ratio = modifier(i, "UIAspectRatioConstraint")
        if ratio and ratio.get("ratio"):
            if w / max(h, 1e-6) > ratio["ratio"]:
                w = h * ratio["ratio"]
            else:
                h = w / ratio["ratio"]
        limits = modifier(i, "UISizeConstraint")
        if limits:
            w = min(max(w, limits["minsz"][0]), limits["maxsz"][0])
            h = min(max(h, limits["minsz"][1]), limits["maxsz"][1])
        return w, h

    def content_size(i, w, h):
        """What the children need (with the layout), plus padding."""
        left, right, top, bottom = padding_of(i, w, h)
        inner_w, inner_h = w - left - right, h - top - bottom
        kids = [c for c in gui_kids(i) if node(c).get("vis", True)]
        layout, grid = modifier(i, "UIListLayout"), modifier(i, "UIGridLayout")
        if grid:
            *_, block_w, block_h = grid_layout(grid, inner_w, inner_h, len(kids))
            need_w, need_h = block_w, block_h
        elif layout:
            sizes = [measure(c, inner_w, inner_h) for c in kids]
            gap = layout["pad"][0] * (inner_h if layout["dir"] == "Vertical" else inner_w) + layout["pad"][1]
            if layout["dir"] == "Vertical":
                need_w = max((s[0] for s in sizes), default=0)
                need_h = sum(s[1] for s in sizes) + gap * max(0, len(sizes) - 1)
            else:
                need_w = sum(s[0] for s in sizes) + gap * max(0, len(sizes) - 1)
                need_h = max((s[1] for s in sizes), default=0)
        else:
            need_w = need_h = 0.0
            for c in kids:
                cw, ch = measure(c, inner_w, inner_h)
                pos = node(c)["pos"]
                need_w = max(need_w, pos[0] * inner_w + pos[1] + cw * (1 - node(c)["anchor"][0]))
                need_h = max(need_h, pos[2] * inner_h + pos[3] + ch * (1 - node(c)["anchor"][1]))
        return need_w + left + right, need_h + top + bottom, inner_w

    def auto_size(i, w, h, axes):
        """AutomaticSize: grow to fit the children, or the text."""
        n = node(i)
        need_w, need_h, inner_w = content_size(i, w, h)
        if n.get("text") and not [c for c in gui_kids(i) if node(c).get("vis", True)]:
            left, right, top, bottom = padding_of(i, w, h)
            text = Text(n)
            lines = text.wrap(n.get("ts", 14), inner_w if axes == "Y" else 1e9, n.get("wrap", False) and axes == "Y")
            need_w = max(lw for _, lw in lines) + left + right
            need_h = len(lines) * n.get("ts", 14) * text.line + top + bottom
        if axes in ("Y", "XY"):
            h = max(h, need_h)
        if axes in ("X", "XY"):
            w = max(w, need_w)
        return w, h

    def text_layout(n, w, h, k):
        """(size, lines, overflow note) for a text node in a w x h box at scale k."""
        text = Text(n)
        limits = None
        for c in children.get(n["_id"], []):
            if node(c)["c"] == "UITextSizeConstraint":
                limits = node(c)
        if n.get("scaled"):
            high = (limits["maxts"] if limits else 100) * k
            low = (limits["mints"] if limits else 1) * k
            size = text.fit(w, h, n.get("wrap", False), low, high)
        else:
            size = n.get("ts", 14) * k
        lines = text.wrap(size, w, n.get("wrap", False))
        line_h = size * text.line
        note = None
        too_wide = max(lw for _, lw in lines) > w + 2
        too_tall = len(lines) * line_h > h + 2
        if (too_wide or too_tall) and not n.get("scaled"):
            if n.get("trunc", "None") != "None":
                keep = max(1, int((h + 2) // max(line_h, 1e-6)))
                cut = lines[:keep]
                last, last_w = cut[-1]
                if len(cut) < len(lines) or last_w > w:
                    ratio = last_w / max(1e-6, text_width(last, text.name, size))
                    while last and text_width(last + "...", text.name, size) * ratio > w:
                        last = last[:-1]
                    cut[-1] = (last.rstrip() + "...", text_width(last.rstrip() + "...", text.name, size) * ratio)
                lines = cut
                note = "truncated"
            else:
                need_w = max(lw for _, lw in lines)
                note = f"cut off (needs {need_w:.0f}x{len(lines) * line_h:.0f}, has {w:.0f}x{h:.0f})"
        return size, lines, line_h, note

    def place(i, rect, transform, screen, visible, clip):
        n = node(i)
        n["_id"] = i
        px, py, pw, ph = rect
        w, h = measure(i, pw, ph)
        if "_cellsize" in n:
            w, h = n.pop("_cellsize")
        if n.get("fit"):
            # UI/Modal: the window shrinks (never grows) to fit its parent at its UI scale.
            s = node_scale(i)
            w = min(n["fit"][0], (pw - 2 * FIT_MARGIN) / s)
            h = min(n["fit"][1], (ph - 2 * FIT_MARGIN) / s)
        ax, ay = n["anchor"]
        psx, pox, psy, poy = n["pos"]
        if n.get("touchSlot") and touch:
            # Api.Button on touch screens: beside the jump button (same rule as Api.jumpButtonSpot).
            small = min(pw, ph) <= 500
            jump = 70 if small else 120
            left = pw - (jump * 1.5 - 10)
            center = (ph - jump - 20 if small else ph - jump * 1.75) + jump / 2
            width = w * node_scale(i)
            ax, ay = 1, 0.5
            psx, psy = 0, 0
            pox = left - 12 - (n["touchSlot"] - 1) * (width + 12)
            poy = center - jump * 0.15
        if n.get("underProfile"):
            psx, psy, pox, poy = 0, 0, 14, 12 + 130 * auto_scale + 8  # RoundController: under the profile chip
        x = px + psx * pw + pox - ax * w
        y = py + psy * ph + poy - ay * h
        if "_listpos" in n:
            x, y = n.pop("_listpos")
        own = transform
        if modifier(i, "UIScale"):
            own = transform.then_scale_about(x + ax * w, y + ay * h, node_scale(i))
        visible = visible and n.get("vis", True)
        x0, y0 = own.apply(x, y)
        x1, y1 = own.apply(x + w, y + h)
        if visible:
            counter[0] += 1
            seq = counter[0]
            text_info = text_layout(n, x1 - x0, y1 - y0, own.k) if "text" in n else None
            draws.append((seq, i, (x0, y0, x1, y1), own.k, clip, text_info))
            if x1 - x0 >= vw * 0.9 and y1 - y0 >= vh * 0.9 and n.get("bgt", 1) < 0.9 and not n.get("text"):
                dimmers.append(seq)
            shown = intersect((x0, y0, x1, y1), clip)
            if (n.get("text", "") != "" or n["c"] in ("TextButton", "ImageButton")) and shown[2] - shown[0] > 1 and shown[3] - shown[1] > 1:
                label = (re.sub(r"<[^>]+>", "", n.get("text") or "") or n["n"])[:40]
                boxes.append((screen, path_of(i), *shown, label, seq))
                if text_info and n.get("text", "").strip():
                    size, _, _, note = text_info
                    if note:
                        problems.append(f"text {note}: {path_of(i)} '{label}'")
                    if touch and size < SMALL_TEXT and n.get("tt", 0) < 0.9:
                        problems.append(f"small text {size:.1f}px: {path_of(i)} '{label}'")
        # Children's content rect (padding, and a scrolling frame's canvas).
        left, right, top, bottom = padding_of(i, w, h)
        cx, cy, cw, ch = x + left, y + top, w - left - right, h - top - bottom
        if n["c"] == "ScrollingFrame":
            canvas = n.get("canvas", [0, 0, 0, 0])
            canvas_w = max(w, canvas[0] * w + canvas[1])
            canvas_h = max(h, canvas[2] * h + canvas[3])
            need_w, need_h, _ = content_size(i, w, h)
            if n.get("autocanvas", "None") in ("Y", "XY"):
                canvas_h = max(canvas_h, need_h)
            if n.get("autocanvas", "None") in ("X", "XY"):
                canvas_w = max(canvas_w, need_w)
            sx_, sy_ = n.get("cpos", [0, 0])
            cx, cy = x - sx_ + left, y - sy_ + top
            cw, ch = canvas_w - left - right, canvas_h - top - bottom
        child_clip = intersect(clip, (x0, y0, x1, y1)) if n.get("clip") or n["c"] == "ScrollingFrame" else clip
        kids = gui_kids(i)
        layout, grid = modifier(i, "UIListLayout"), modifier(i, "UIGridLayout")
        flow = [c for c in kids if node(c).get("vis", True)]
        sort = (layout or grid or {}).get("sort", "LayoutOrder")
        flow.sort(key=(lambda c: node(c).get("lo", 0)) if sort == "LayoutOrder" else (lambda c: node(c)["n"]))
        if grid:
            cell_w, cell_h, pad_x, pad_y, per, horizontal, block_w, block_h = grid_layout(grid, cw, ch, len(flow))
            sx = cx + {"Left": 0, "Center": (cw - block_w) / 2, "Right": cw - block_w}.get(grid["ha"], 0)
            sy = cy + {"Top": 0, "Center": (ch - block_h) / 2, "Bottom": ch - block_h}.get(grid["va"], 0)
            for index, c in enumerate(flow):
                col, row = (index % per, index // per) if horizontal else (index // per, index % per)
                node(c)["_listpos"] = (sx + col * (cell_w + pad_x), sy + row * (cell_h + pad_y))
                node(c)["_cellsize"] = (cell_w, cell_h)
        elif layout:
            vertical = layout["dir"] == "Vertical"
            gap = layout["pad"][0] * (ch if vertical else cw) + layout["pad"][1]
            sizes = [measure(c, cw, ch) for c in flow]
            total = sum(s[1] if vertical else s[0] for s in sizes) + gap * max(0, len(flow) - 1)
            if vertical:
                cursor = cy + {"Top": 0, "Center": (ch - total) / 2, "Bottom": ch - total}.get(layout["va"], 0)
            else:
                cursor = cx + {"Left": 0, "Center": (cw - total) / 2, "Right": cw - total}.get(layout["ha"], 0)
            for c, (sw, sh) in zip(flow, sizes):
                if vertical:
                    lx = cx + {"Left": 0, "Center": (cw - sw) / 2, "Right": cw - sw}.get(layout["ha"], 0)
                    node(c)["_listpos"] = (lx, cursor)
                    cursor += sh + gap
                else:
                    ly = cy + {"Top": 0, "Center": (ch - sh) / 2, "Bottom": ch - sh}.get(layout["va"], 0)
                    node(c)["_listpos"] = (cursor, ly)
                    cursor += sw + gap
        # Sibling ZIndex order: children paint after their parent, siblings by ZIndex (stable).
        for c in sorted(kids, key=lambda c: node(c).get("z", 1)):
            place(c, (cx, cy, cw, ch), own, screen, visible, child_clip)

    screens = [i for i in children[0] if node(i)["c"] == "ScreenGui" and node(i).get("enabled", True)]
    screens.sort(key=lambda i: node(i).get("order", 0))
    screen_inset = {}
    for i in screens:
        n = node(i)
        screen_inset[n["n"]] = n.get("inset", True)
        area = (side, TOPBAR, vw - 2 * side, vh - TOPBAR) if n.get("inset", True) else (0, 0, vw, vh)
        for c in sorted(gui_kids(i), key=lambda c: node(c).get("z", 1)):
            place(c, area, Transform(), n["n"], True, None)

    # Paint.
    image = Image.new("RGBA", (vw, vh), (120, 170, 120, 255))
    backdrop = ImageDraw.Draw(image)
    for row in range(vh):  # a sky-and-grass backdrop so the HUD reads like it does in game
        t = row / vh
        color = (140, 190, 240) if t < 0.45 else (110, 175, 95)
        backdrop.line([(0, row), (vw, row)], fill=color)
    draws.sort(key=lambda d: d[0])
    for _, i, (x0, y0, x1, y1), k, clip, layout in draws:
        n = node(i)
        w, h = x1 - x0, y1 - y0
        if w <= 0 or h <= 0:
            continue
        margin = 8
        ox, oy = int(math.floor(x0)) - margin, int(math.floor(y0)) - margin
        lw_, lh_ = int(math.ceil(w)) + 2 * margin + 1, int(math.ceil(h)) + 2 * margin + 1
        if lw_ * lh_ > 4 * vw * vh:
            continue
        layer = Image.new("RGBA", (lw_, lh_), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        bx0, by0 = x0 - ox, y0 - oy
        box = [bx0, by0, max(bx0 + 1, bx0 + w), max(by0 + 1, by0 + h)]
        corner = modifier(i, "UICorner")
        radius = 0
        if corner:
            rs, ro = corner["radius"]
            radius = max(0, min(min(w, h) / 2, rs * min(w, h) + ro * k))
        bgt = n.get("bgt", 1)
        if bgt < 1:
            gradient = modifier(i, "UIGradient")
            base = n.get("bg", [255, 255, 255])
            if gradient:
                fill_layer = Image.new("RGBA", layer.size, (0, 0, 0, 0))
                fd = ImageDraw.Draw(fill_layer)
                steps = max(2, int(h))
                for s in range(steps):
                    t = s / (steps - 1)
                    c = [base[j] * (gradient["c0"][j] + (gradient["c1"][j] - gradient["c0"][j]) * t) / 255 for j in range(3)]
                    fd.line([(box[0], box[1] + s), (box[2], box[1] + s)], fill=rgba(c, bgt))
                mask = Image.new("L", layer.size, 0)
                ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
                layer.paste(fill_layer, (0, 0), mask)
            else:
                d.rounded_rectangle(box, radius=radius, fill=rgba(base, bgt))
        stroke = modifier(i, "UIStroke")
        is_text = "text" in n
        if stroke and stroke.get("enabled", True) and (stroke.get("mode") == "Border" or not is_text):
            d.rounded_rectangle(box, radius=radius, outline=rgba(stroke["color"], stroke["t"]), width=max(1, int(round(stroke["thick"] * k))))
        if n.get("img"):
            d.rounded_rectangle(box, radius=radius, outline=rgba(n.get("ic", [255, 255, 255]), 0.4), width=1)
        if is_text and layout and n.get("text") and n.get("tt", 0) < 1:
            size, lines, line_h, _ = layout
            name = n.get("font", "")
            total = line_h * len(lines)
            ty = {"Top": box[1], "Center": box[1] + (h - total) / 2, "Bottom": box[3] - total}.get(n.get("ya", "Center"), box[1])
            text_stroke = None
            if stroke and stroke.get("enabled", True) and stroke.get("mode") != "Border":
                text_stroke = (rgba(stroke["color"], stroke["t"]), max(1, int(round(stroke["thick"] * k))))
            elif n.get("st", 1) < 1:
                text_stroke = ((0, 0, 0, int(255 * (1 - n["st"]))), 1)
            fill = rgba(n.get("tc", [255, 255, 255]), n.get("tt", 0))
            for line, measured in lines:
                tx = {"Left": box[0], "Center": box[0] + (w - measured) / 2, "Right": box[2] - measured}.get(n.get("xa", "Center"), box[0])
                draw_line(layer, tx, ty + line_h / 2, line, name, size, measured, fill, text_stroke)
                ty += line_h
        visible_box = intersect((0, 0, vw, vh), clip)
        crop = (int(max(0, math.floor(visible_box[0]) - ox)), int(max(0, math.floor(visible_box[1]) - oy)),
                int(min(lw_, math.ceil(visible_box[2]) - ox)), int(min(lh_, math.ceil(visible_box[3]) - oy)))
        if crop[2] <= crop[0] or crop[3] <= crop[1]:
            continue
        image.alpha_composite(layer.crop(crop), (ox + crop[0], oy + crop[1]))

    # Roblox's own UI on top: top bar buttons, and touch controls on phones/tablets.
    overlay = Image.new("RGBA", (vw, vh), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    core = [(side + 12, 7, side + 56, 51, "R"), (side + 64, 7, side + 108, 51, "chat"), (vw - side - 56, 7, vw - side - 12, 51, "...")]
    top = counter[0] + 1
    for x0, y0, x1, y1, label in core:
        od.rounded_rectangle([x0, y0, x1, y1], radius=22, fill=(20, 20, 30, 150))
        od.text(((x0 + x1) / 2, (y0 + y1) / 2), label, font=font("Bold", 13), fill=(255, 255, 255, 220), anchor="mm")
        boxes.append(("RobloxCore", "TopBar/" + label, x0, y0, x1, y1, label, top))
    if touch:
        # Roblox's TouchJump rule, and the DynamicThumbstick's touch zone (left 40%, bottom 2/3).
        cw, ch = vw - 2 * side, vh - TOPBAR
        small = min(cw, ch) <= 500
        jump = 70 if small else 120
        jx0 = side + cw - (jump * 1.5 - 10)
        jy0 = TOPBAR + (ch - jump - 20 if small else ch - jump * 1.75)
        od.ellipse([jx0, jy0, jx0 + jump, jy0 + jump], fill=(255, 255, 255, 70), outline=(255, 255, 255, 160), width=2)
        od.text((jx0 + jump / 2, jy0 + jump / 2), "JUMP", font=font("Bold", 12), fill=(255, 255, 255, 230), anchor="mm")
        boxes.append(("RobloxCore", "Touch/Jump", jx0, jy0, jx0 + jump, jy0 + jump, "JUMP", top))
        zone = (side, TOPBAR + ch / 3, side + cw * 0.4, vh)
        od.rectangle(zone, outline=(255, 255, 255, 60), width=1)
        ring = 90 if small else 140
        rx, ry = side + 40 + ring / 2, vh - 40 - ring / 2
        od.ellipse([rx - ring / 2, ry - ring / 2, rx + ring / 2, ry + ring / 2], fill=(255, 255, 255, 45), outline=(255, 255, 255, 140), width=2)
        od.text((rx, ry), "MOVE", font=font("Bold", 12), fill=(255, 255, 255, 220), anchor="mm")
        boxes.append(("RobloxCore", "Touch/Thumbstick", rx - ring / 2, ry - ring / 2, rx + ring / 2, ry + ring / 2, "MOVE", top))
    if side:
        od.rectangle([0, 0, side, vh], fill=(0, 0, 0, 90))
        od.rectangle([vw - side, 0, vw, vh], fill=(0, 0, 0, 90))
    image = Image.alpha_composite(image, overlay)
    image.convert("RGB").save(out)

    # Checks.
    # Full-screen backdrops behind pop-ups (the click-to-close dimmer) cover everything on purpose,
    # and what's under a dimmer is only compared with what's under it too.
    boxes = [b for b in boxes if not ((b[4] - b[2]) >= vw * 0.9 and (b[5] - b[3]) >= vh * 0.9)]

    def layer_of(b):
        return math.inf if b[0] == "RobloxCore" else sum(1 for s in dimmers if s < b[7])

    for a in range(len(boxes)):
        sa, pa, ax0, ay0, ax1, ay1, la, _ = boxes[a]
        if ax1 < 0 or ay1 < 0 or ax0 > vw or ay0 > vh:
            continue
        if sa != "RobloxCore" and (ax0 < -1 or ay0 < -1 or ax1 > vw + 1 or ay1 > vh + 1):
            problems.append(f"off-screen: {pa} '{la}' at ({ax0:.0f},{ay0:.0f})-({ax1:.0f},{ay1:.0f})")
        elif sa != "RobloxCore" and side and not screen_inset.get(sa, True) and (ax0 < side - 1 or ax1 > vw - side + 1):
            problems.append(f"outside the safe area (notch): {pa} '{la}' at ({ax0:.0f},{ay0:.0f})-({ax1:.0f},{ay1:.0f})")
        for b in range(a + 1, len(boxes)):
            sb, pb, bx0, by0, bx1, by1, lb, _ = boxes[b]
            if pa.startswith(pb + "/") or pb.startswith(pa + "/"):
                continue  # a label inside its own button/panel
            la_, lb_ = layer_of(boxes[a]), layer_of(boxes[b])
            if la_ != lb_ and math.inf not in (la_, lb_):
                continue  # one is under a pop-up's dimmer
            ix = min(ax1, bx1) - max(ax0, bx0)
            iy = min(ay1, by1) - max(ay0, by0)
            if ix > 2 and iy > 2:
                area = ix * iy
                smaller = min((ax1 - ax0) * (ay1 - ay0), (bx1 - bx0) * (by1 - by0))
                if smaller > 0 and area / smaller > 0.15:
                    problems.append(f"overlap {area / smaller:.0%}: {pa} '{la}'  x  {pb} '{lb}'")
    return problems


def draw_line(layer, x, center_y, text, name, size, measured, fill, stroke):
    """Draws one line of text with the stand-in fonts, squeezed to the engine's width for it."""
    natural = text_width(text, name, size)
    if natural <= 0 or measured <= 0:
        return
    pad = (stroke[1] if stroke else 0) + 2
    tmp = Image.new("RGBA", (int(math.ceil(natural)) + 2 * pad + 2, int(math.ceil(size * 1.6)) + 2 * pad), (0, 0, 0, 0))
    td = ImageDraw.Draw(tmp)
    tx = pad
    for path, piece in runs(text, name):
        f = font_at(path, size)
        kwargs = {}
        if stroke and path != NOTO:
            kwargs = {"stroke_width": stroke[1], "stroke_fill": stroke[0]}
        td.text((tx, tmp.height / 2), piece, font=f, fill=fill, anchor="lm", **kwargs)
        tx += f.getlength(piece)
    factor = measured / natural
    if abs(factor - 1) > 0.01:
        tmp = tmp.resize((max(1, int(round(tmp.width * factor))), tmp.height), Image.LANCZOS)
        pad = pad * factor
    layer.alpha_composite(tmp, (int(round(x - pad)), int(round(center_y - tmp.height / 2))))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("results", help="what luau_task.py saved for a round_harness --ui-at run or a client_harness run")
    parser.add_argument("out", help="output prefix: <out>_<time>_<size>.png")
    parser.add_argument("--sizes", default="all", help="all, pc, phone, touch, or comma-separated names: " + ", ".join(SIZES))
    parser.add_argument("--only", help="comma-separated snapshot names to draw (default: all of them)")
    args = parser.parse_args()
    data = json.load(open(args.results))
    data = data[0] if isinstance(data, list) else data
    data = json.loads(data) if isinstance(data, str) else data
    snapshots = (data or {}).get("ui") or {}
    if not snapshots:
        raise SystemExit("No UI snapshots: run round_harness.py with --client --ui-at <seconds>")
    names = SIZE_GROUPS.get(args.sizes) or args.sizes.split(",")
    only = set(args.only.split(",")) if args.only else None

    def order(key):
        try:
            return (0, float(key), "")
        except ValueError:
            return (1, 0.0, key)

    total = 0
    for at, nodes in sorted(snapshots.items(), key=lambda kv: order(kv[0])):
        if only and at not in only:
            continue
        label = f"{float(at):g}s" if order(at)[0] == 0 else at
        for size_name in names:
            out = Path(f"{args.out}_{label}_{size_name}.png")
            problems = render(json.loads(json.dumps(nodes)), size_name, out)
            total += len(problems)
            print(f"wrote {out}")
            for problem in problems:
                print("    ", problem)
    print(f"{total} problem(s)")


if __name__ == "__main__":
    main()

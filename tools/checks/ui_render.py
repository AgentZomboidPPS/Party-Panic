"""Draws the player's on-screen UI from a harness snapshot at several screen sizes (PC and phones),
with Roblox's own buttons, the touch thumbstick and the jump button drawn on top, and reports
overlaps, anything off-screen or outside the safe area, text that's cut off or wraps where it
shouldn't, text too small to read on a phone, small touch targets, anything in the thumbstick zone,
and emoji phones don't show, so layouts can be checked without a device.

    python3 tools/checks/client_harness.py --touch --bots 8 > client.luau     # phones (or no --touch: PC)
    python3 tools/preview/luau_task.py client.luau - client.json
    python3 tools/checks/ui_render.py client.json /tmp/screens --sizes touch   # every snapshot, those sizes

    python3 tools/checks/round_harness.py HoneyTrap --client --touch --ui-at 2,12 ... > run.luau
    python3 tools/checks/ui_render.py run.json /tmp/honey_ui --sizes phone

The harness lays the UI out with the ENGINE for each screen size it was asked for (--sizes on the
harness, default: the touch sizes with --touch, else the PC ones; tools/checks/gui_dump.luau): real
positions, sizes, text measurements, wrapping and whether each text fits, with the fonts loaded.
Those are what's drawn and checked. For a size the snapshot has no engine layout for, the layout is
redone here following Roblox's rules (UDim2, AutomaticSize, UIScale with the UIKit.AutoScale ones
recomputed for the screen, UIListLayout, UIGridLayout, UIPadding, UIAspectRatioConstraint,
ScrollingFrame canvases, ZIndex order, text with the engine's word widths), which can be off by a
few points: trust the engine sizes. Text is drawn with stand-in fonts squeezed to the engine's
widths; images are placeholders.
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
SMALL_TEXT = 11  # pt: smaller text is reported on touch screens
TOUCH_TARGET = 40  # pt: smaller buttons are reported on touch screens (aim for 44)
FIT_MARGIN = 8  # UI/Modal.luau: room around a window shrunk to fit the screen

# Screens, in points: size, the safe area's insets in landscape (left, right, bottom: notch or
# Dynamic Island, home bar) and the top inset Roblox's top bar takes (CoreUISafeInsets).
SIZES = {
    "pc": dict(w=1280, h=720, l=0, r=0, b=0, t=58, touch=False),
    "pc-hd": dict(w=1920, h=1080, l=0, r=0, b=0, t=58, touch=False),
    "phone-large": dict(w=932, h=430, l=59, r=59, b=21, t=56, touch=True),  # iPhone Pro Max (the owner's phone)
    "phone": dict(w=844, h=390, l=47, r=47, b=21, t=56, touch=True),  # iPhone 12 to 16
    "phone-android": dict(w=800, h=360, l=32, r=0, b=0, t=56, touch=True),  # 20:9 Android, camera hole on one side
    "phone-small": dict(w=667, h=375, l=0, r=0, b=0, t=56, touch=True),  # iPhone SE / 8
    "tablet": dict(w=1024, h=768, l=0, r=0, b=0, t=56, touch=True),  # iPad
}
SIZE_GROUPS = {
    "phone": ["phone-large", "phone", "phone-android", "phone-small"],
    "pc": ["pc", "pc-hd"],
    "touch": ["phone-large", "phone", "phone-android", "phone-small", "tablet"],
    "all": list(SIZES),
}
MODIFIERS = ("UIScale", "UICorner", "UIStroke", "UIGradient", "UIListLayout", "UIGridLayout", "UIPadding",
             "UIAspectRatioConstraint", "UITextSizeConstraint", "UISizeConstraint")
DISPLAY_FONTS = ("Fredoka", "Luckiest")  # headline fonts: their text stays on one line unless PP_Lines says


def core_buttons(dev: dict) -> list:
    """Roblox's own top bar buttons as phones show them today (measured on an iPhone Pro Max): the
    round Roblox button, then the menu and chat pill, 43 pt tall at the top left of the safe area."""
    left = dev["l"]
    return [(left + 18, 12, left + 60, 55, "Roblox"), (left + 68, 12, left + 161, 55, "menu chat")]


def jump_button(dev: dict) -> tuple:
    """Roblox's TouchJump rule: (left, top, size). Its frame spans the safe area's width and the
    whole height (measured on an iPhone Pro Max)."""
    width, height = dev["w"] - dev["l"] - dev["r"], dev["h"]
    small = min(width, height) <= 500
    size = 70 if small else 120
    x0 = dev["w"] - dev["r"] - (size * 1.5 - 10)
    y0 = height - size - 20 if small else height - size * 1.75
    return x0, y0, size


def thumbstick_zone(dev: dict) -> tuple:
    """Where a touch starts the DynamicThumbstick: the left 40% of the safe area, bottom two thirds."""
    return dev["l"], dev["h"] / 3, dev["l"] + 0.4 * (dev["w"] - dev["l"] - dev["r"]), dev["h"]


def screen_area(dev: dict, insets: str, inset: bool = True) -> tuple:
    """(x, y, w, h) a ScreenGui's contents get, by its ScreenInsets (like gui_dump.luau's)."""
    w, h = dev["w"], dev["h"]
    if insets == "None" or (not inset and insets in ("CoreUISafeInsets", "")):
        return 0, 0, w, h
    if insets == "DeviceSafeInsets":
        return dev["l"], 0, w - dev["l"] - dev["r"], h - dev["b"]
    if insets == "TopbarSafeInsets":
        bar = core_buttons(dev)[-1][2] + 12
        return bar, 0, w - dev["r"] - 12 - bar, dev["t"]
    return dev["l"], dev["t"], w - dev["l"] - dev["r"], h - dev["t"] - dev["b"]


def devices_luau(names: list) -> str:
    """The screens as a Luau table for gui_dump.luau's engine layout (__devices)."""
    rows = []
    for name in names:
        dev = SIZES[name]
        jx, jy, js = jump_button(dev)
        bar = core_buttons(dev)[-1][2] + 12
        rows.append(f'{{ n = "{name}", w = {dev["w"]}, h = {dev["h"]}, l = {dev["l"]}, r = {dev["r"]}, t = {dev["t"]}, '
                    f'b = {dev["b"]}, bar = {bar}, touch = {str(dev["touch"]).lower()}, jump = {{ {jx}, {jy}, {js} }} }}')
    return "__devices = { " + ", ".join(rows) + " }\n"


def size_names(spec: str) -> list:
    names = SIZE_GROUPS.get(spec) or spec.split(",")
    unknown = [name for name in names if name not in SIZES]
    if unknown:
        raise SystemExit(f"unknown screen size(s) {unknown}: use {', '.join(list(SIZES) + list(SIZE_GROUPS))}")
    return names


# Emoji newer than Roblox's emoji font (Unicode 13 and later): phones show nothing for them (the
# coin 🪙, Unicode 13, was missing on the owner's iPhone; Unicode 12 ones like 🟢 are left alone).
NEW_EMOJI = re.compile("[\U0001FA74-\U0001FA77\U0001FA7B-\U0001FA7F\U0001FA83-\U0001FA8F\U0001FA96-\U0001FAFF"
                       "\U0001F6D6-\U0001F6D7\U0001F6DC-\U0001F6DF\U0001F6FB-\U0001F6FC\U0001F90C\U0001F972"
                       "\U0001F977-\U0001F979\U0001F9A3-\U0001F9A4\U0001F9AB-\U0001F9AD\U0001F9CB-\U0001F9CC"
                       "\U0001F7F0]")

# Each character is drawn with the node's font when that has the glyph; pictographs prefer the
# emoji font; anything else falls back to the emoji font, then DejaVu (which has most symbols).
EMOJI = re.compile("[\\U0001F000-\\U0001FAFF\\u2600-\\u2604\\u2606-\\u265F\\u2668-\\u27BF\\u2B00-\\u2BFF\\u2300-\\u23FF]")
NOTO = str(FONTS / "NotoEmoji.ttf")
DEJAVU = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SANS = [("/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf", "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf"),
        (DEJAVU, "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")]
_font_cache: dict = {}
_cmap_cache: dict = {}
_drawn_cache: dict = {}


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
            _cmap_cache[path] = None  # without fontTools: drawn() below
    cmap = _cmap_cache[path]
    return drawn(path, ch) if cmap is None else ord(ch) in cmap


def drawn(path: str, ch: str) -> bool:
    """Without fontTools: whether the font draws `ch` as anything but its missing-glyph box (so the
    team shapes ★ ● ▲ ◆, which Fredoka lacks, are drawn with a font that has them)."""
    key = (path, ch)
    if key not in _drawn_cache:
        face = font_at(path, 40)
        if path not in _drawn_cache:
            box = face.getmask("\U0010fffd")  # a private-use character no font has
            _drawn_cache[path] = (box.size, bytes(box))
        mask = face.getmask(ch)
        _drawn_cache[key] = (mask.size, bytes(mask)) != _drawn_cache[path]
    return _drawn_cache[key]


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
        if ch in "️‍":
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


def area_of(box) -> float:
    return max(0.0, box[2] - box[0]) * max(0.0, box[3] - box[1])


def render(nodes: list, size_name: str, out: Path):
    dev = SIZES[size_name]
    vw, vh, touch = dev["w"], dev["h"], dev["touch"]
    engine = any(size_name in (n.get("L") or {}) for n in nodes)
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
    auto_scale = max(MIN_SCALE, min(MAX_SCALE, raw_scale))  # UIKit.ScaleFor()
    draws = []  # (paint order, node, screen rect, scale, clip rect, text layout)
    boxes = []  # what the overlap checks compare
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

    def text_padding(i, w, h, k):
        """A text node's UIPadding in screen points (its box is w x h on screen at scale k)."""
        left, right, top, bottom = padding_of(i, w / max(k, 1e-6), h / max(k, 1e-6))
        return left * k, right * k, top * k, bottom * k

    def allowed_lines(n, text):
        """How many lines a text may take: PP_Lines, else one per paragraph for headlines and
        scaled text that isn't meant to wrap, else as many as fit its box."""
        if n.get("lines"):
            return n["lines"]
        if any(word in n.get("font", "") for word in DISPLAY_FONTS) or (n.get("scaled") and not n.get("wrap")):
            return len(text.paragraphs)
        return None

    def text_layout(n, w, h, k, record):
        """(size, lines, line height, problem) for a text node in a w x h box at scale k."""
        text = Text(n)
        if record and len(record) >= 11:
            # The engine's measurements (gui_dump.luau): size, line count and whether it fits.
            _, _, _, _, _, _, fits, size, count, need_w, need_h = record[:11]
            wrapping = bool(n.get("wrap") or n.get("scaled"))
            width, lines = w, text.wrap(size, w, wrapping)
            for _ in range(12):  # wrap where the engine does (its small sizes run a little wider)
                if not wrapping or len(lines) >= count:
                    break
                width *= 0.96
                lines = text.wrap(size, width, wrapping)
            line_h = size * text.line
            note = None
            if not fits:
                if wrapping:  # the engine leaves out the lines that don't fit
                    lines = lines[: max(1, int((h + 1) // max(line_h, 1e-6)))]
                if n.get("trunc", "None") != "None":
                    last, last_w = lines[-1]
                    while last and text_width(last + "...", text.name, size) > w:
                        last = last[:-1]
                    lines[-1] = (last.rstrip() + "...", min(w, last_w))
                    if not n.get("truncOk"):
                        note = f"truncated (needs {need_w:.0f}x{need_h:.0f}, has {w:.0f}x{h:.0f})"
                else:
                    note = f"cut off (needs {need_w:.0f}x{need_h:.0f}, has {w:.0f}x{h:.0f})"
            else:
                allowed = allowed_lines(n, text)
                if allowed and count > allowed:
                    note = f"wraps onto {count} lines"
            return size, lines, line_h, note

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
                note = None if n.get("truncOk") else "truncated"
            else:
                need_w = max(lw for _, lw in lines)
                note = f"cut off (needs {need_w:.0f}x{len(lines) * line_h:.0f}, has {w:.0f}x{h:.0f})"
        elif (allowed := allowed_lines(n, text)) and len(lines) > allowed:
            note = f"wraps onto {len(lines)} lines"
        return size, lines, line_h, note

    def place(i, rect, transform, screen, visible, clip, popup):
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
            jx, jy, jump = jump_button(dev)
            width = w * node_scale(i)
            ax, ay = 1, 0.5
            psx, psy = 0, 0
            pox = jx - px - 12 - (n["touchSlot"] - 1) * (width + 12)
            poy = jy + jump / 2 - py - jump * 0.15
        if n.get("underProfile"):
            psx, psy, pox, poy = 0, 0, 14, 12 + 130 * auto_scale + 8  # RoundController: under the profile chip
        if n.get("aboveActions") and touch:
            # NotificationController: the toasts sit above the mode's action buttons (their row, as above).
            jx, jy, jump = jump_button(dev)
            psy, poy = 0, jy + jump / 2 - py - jump * 0.15 - 118 * auto_scale / 2 - 8
        x = px + psx * pw + pox - ax * w
        y = py + psy * ph + poy - ay * h
        if "_listpos" in n:
            x, y = n.pop("_listpos")
        own = transform
        if modifier(i, "UIScale"):
            own = transform.then_scale_about(x + ax * w, y + ay * h, node_scale(i))
        visible = visible and n.get("vis", True)
        popup = popup or bool(n.get("popup"))
        x0, y0 = own.apply(x, y)
        x1, y1 = own.apply(x + w, y + h)
        record = (n.get("L") or {}).get(size_name) if engine else None
        if record:
            x0, y0, x1, y1 = record[0], record[1], record[0] + record[2], record[1] + record[3]
        if visible:
            counter[0] += 1
            seq = counter[0]
            pl, pr, pt, pb = text_padding(i, x1 - x0, y1 - y0, own.k)
            text_info = text_layout(n, x1 - x0 - pl - pr, y1 - y0 - pt - pb, own.k, record) if "text" in n else None
            draws.append((seq, i, (x0, y0, x1, y1), own.k, clip, text_info))
            if x1 - x0 >= vw * 0.9 and y1 - y0 >= vh * 0.9 and n.get("bgt", 1) < 0.9 and not n.get("text"):
                dimmers.append(seq)
            shown = intersect((x0, y0, x1, y1), clip)
            is_button = n["c"] in ("TextButton", "ImageButton")
            if (n.get("text", "") != "" or is_button) and shown[2] - shown[0] > 1 and shown[3] - shown[1] > 1:
                raw_text = re.sub(r"<[^>]+>", "", n.get("text") or "")
                label = (raw_text or n["n"])[:40]
                boxes.append(dict(screen=screen, path=path_of(i), box=shown, label=label, seq=seq, popup=popup))
                if is_button and touch and min(x1 - x0, y1 - y0) < TOUCH_TARGET and (x1 - x0) * (y1 - y0) < vw * vh / 2:
                    problems.append(f"small touch target {x1 - x0:.0f}x{y1 - y0:.0f}: {path_of(i)} '{label}'")
                if text_info and raw_text.strip() and n.get("tt", 0) < 0.9:
                    size, _, _, note = text_info
                    if note:
                        problems.append(f"text {note}: {path_of(i)} '{label}'")
                    if touch and size < SMALL_TEXT - 0.05:
                        problems.append(f"small text {size:.1f}pt: {path_of(i)} '{label}'")
                    missing = sorted(set(NEW_EMOJI.findall(raw_text)))
                    if touch and missing:
                        problems.append(f"emoji phones don't show ({''.join(missing)}): {path_of(i)} '{label}'")
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
            place(c, (cx, cy, cw, ch), own, screen, visible, child_clip, popup)

    screens = [i for i in children[0] if node(i)["c"] == "ScreenGui" and node(i).get("enabled", True)]
    screens.sort(key=lambda i: node(i).get("order", 0))
    screen_rect = {}
    billboards = {node(i)["n"] for i in screens if node(i).get("billboards")}
    for i in screens:
        n = node(i)
        area = screen_area(dev, n.get("insets", "CoreUISafeInsets"), n.get("inset", True))
        screen_rect[n["n"]] = area
        for c in sorted(gui_kids(i), key=lambda c: node(c).get("z", 1)):
            place(c, area, Transform(), n["n"], True, None, False)

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
        if w * h > 2 * vw * vh and not n.get("text") and not modifier(i, "UICorner"):
            # A plain frame much bigger than the screen (a modal's dim backdrop): paint what's on it.
            x0, y0, x1, y1 = max(x0, -margin), max(y0, -margin), min(x1, vw + margin), min(y1, vh + margin)
            w, h = x1 - x0, y1 - y0
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
            pl, pr, pt, pb = text_padding(i, w, h, k)
            box = [box[0] + pl, box[1] + pt, box[2] - pr, box[3] - pb]
            w, h = box[2] - box[0], box[3] - box[1]
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
    top = counter[0] + 1
    core = []
    for x0, y0, x1, y1, label in core_buttons(dev):
        od.rounded_rectangle([x0, y0, x1, y1], radius=(y1 - y0) / 2, fill=(255, 255, 255, 235))
        od.text(((x0 + x1) / 2, (y0 + y1) / 2), label, font=font("Bold", 11), fill=(30, 30, 40, 255), anchor="mm")
        core.append(dict(screen="RobloxCore", path="TopBar/" + label, box=(x0, y0, x1, y1), label=label, seq=top, popup=False))
    zone = None
    # A screen that put the MOVE stick and jump button away (the PlayerModule's controls disabled,
    # like Skee-Ball's play screen) has none of them to draw or keep clear of.
    controls_away = any(n.get("noTouch") and n.get("enabled", True) for n in nodes if n["c"] == "ScreenGui")
    if touch and not controls_away:
        jx0, jy0, jump = jump_button(dev)
        od.ellipse([jx0, jy0, jx0 + jump, jy0 + jump], fill=(255, 255, 255, 70), outline=(255, 255, 255, 160), width=2)
        od.text((jx0 + jump / 2, jy0 + jump / 2), "JUMP", font=font("Bold", 12), fill=(255, 255, 255, 230), anchor="mm")
        core.append(dict(screen="RobloxCore", path="Touch/Jump", box=(jx0, jy0, jx0 + jump, jy0 + jump), label="JUMP", seq=top, popup=False))
        zone = thumbstick_zone(dev)
        od.rectangle(zone, outline=(255, 255, 255, 70), width=1)
        od.text((zone[0] + 6, zone[1] + 4), "thumbstick zone", font=font("Bold", 10), fill=(255, 255, 255, 140))
        small = min(dev["w"] - dev["l"] - dev["r"], vh) <= 500
        ring = 90 if small else 140
        rx, ry = dev["l"] + 40 + ring / 2, vh - 40 - ring / 2
        od.ellipse([rx - ring / 2, ry - ring / 2, rx + ring / 2, ry + ring / 2], fill=(255, 255, 255, 45), outline=(255, 255, 255, 140), width=2)
        od.text((rx, ry), "MOVE", font=font("Bold", 12), fill=(255, 255, 255, 220), anchor="mm")
    if dev["l"]:
        od.rectangle([0, 0, dev["l"], vh], fill=(0, 0, 0, 90))
    if dev["r"]:
        od.rectangle([vw - dev["r"], 0, vw, vh], fill=(0, 0, 0, 90))
    if dev["b"]:
        od.rectangle([0, vh - dev["b"], vw, vh], fill=(0, 0, 0, 40))
    image = Image.alpha_composite(image, overlay)
    image.convert("RGB").save(out)

    # Checks.
    # Full-screen backdrops behind pop-ups (the click-to-close dimmer) cover everything on purpose,
    # and what's under a dimmer is only compared with what's under it too.
    boxes = [b for b in boxes if not ((b["box"][2] - b["box"][0]) >= vw * 0.9 and (b["box"][3] - b["box"][1]) >= vh * 0.9)]

    def layer_of(b):
        return math.inf if b["screen"] == "RobloxCore" else sum(1 for s in dimmers if s < b["seq"])

    everything = [b for b in boxes if b["screen"] not in billboards] + core
    for a in range(len(everything)):
        A = everything[a]
        ax0, ay0, ax1, ay1 = A["box"]
        if ax1 < 0 or ay1 < 0 or ax0 > vw or ay0 > vh:
            continue
        if A["screen"] != "RobloxCore":
            sx, sy, sw, sh = screen_rect.get(A["screen"], (0, 0, vw, vh))
            if ax0 < -1 or ay0 < -1 or ax1 > vw + 1 or ay1 > vh + 1:
                problems.append(f"off-screen: {A['path']} '{A['label']}' at ({ax0:.0f},{ay0:.0f})-({ax1:.0f},{ay1:.0f})")
            elif ax0 < dev["l"] - 1 or ax1 > vw - dev["r"] + 1 or ay1 > vh - dev["b"] + 1:
                problems.append(f"outside the safe area (notch/home bar): {A['path']} '{A['label']}' at ({ax0:.0f},{ay0:.0f})-({ax1:.0f},{ay1:.0f})")
            if zone and layer_of(A) == 0 and not A["popup"]:
                inside = area_of(intersect(A["box"], zone))
                if inside > 0.15 * max(1.0, area_of(A["box"])):
                    problems.append(f"in the thumbstick zone {inside / max(1.0, area_of(A['box'])):.0%}: {A['path']} '{A['label']}'")
        for b in range(a + 1, len(everything)):
            B = everything[b]
            if A["path"].startswith(B["path"] + "/") or B["path"].startswith(A["path"] + "/"):
                continue  # a label inside its own button/panel
            la_, lb_ = layer_of(A), layer_of(B)
            if la_ != lb_ and math.inf not in (la_, lb_):
                continue  # one is under a pop-up's dimmer
            if math.inf in (la_, lb_) and max(la_, lb_) == math.inf and min(la_, lb_) > 0:
                continue  # Roblox's buttons over a pop-up's dimmed backdrop
            bx0, by0, bx1, by1 = B["box"]
            ix = min(ax1, bx1) - max(ax0, bx0)
            iy = min(ay1, by1) - max(ay0, by0)
            if ix > 2 and iy > 2:
                inter = ix * iy
                smaller = min(area_of(A["box"]), area_of(B["box"]))
                if smaller > 0 and inter / smaller > 0.15:
                    problems.append(f"overlap {inter / smaller:.0%}: {A['path']} '{A['label']}'  x  {B['path']} '{B['label']}'")
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
    parser.add_argument("--sizes", default="measured", help="measured (the sizes the harness laid out with the engine), "
                        "all, pc, phone, touch, or comma-separated names: " + ", ".join(SIZES))
    parser.add_argument("--only", help="comma-separated snapshot names to draw (default: all of them)")
    args = parser.parse_args()
    data = json.load(open(args.results))
    data = data[0] if isinstance(data, list) else data
    data = json.loads(data) if isinstance(data, str) else data
    snapshots = (data or {}).get("ui") or {}
    if not snapshots:
        raise SystemExit("No UI snapshots: run round_harness.py with --client --ui-at <seconds>")
    if args.sizes == "measured":
        measured = {name for nodes in snapshots.values() for n in nodes for name in (n.get("L") or {})}
        names = [name for name in SIZES if name in measured] or SIZE_GROUPS["all"]
    else:
        names = size_names(args.sizes)
    only = set(args.only.split(",")) if args.only else None

    def order(key):
        try:
            return (0, float(key), "")
        except ValueError:
            return (1, 0.0, key)

    total = 0
    # The harness's own list of texts the engine says don't fit (gui_dump.luau), for every screen
    # it laid out, drawn or not.
    report = [line for line in (data.get("textReport") or []) if not only or line.split(" ")[0] in only]
    if report:
        print(f"engine text report ({len(report)}):")
        for line in report:
            print("    ", line)
        total += len(report)
    for at, nodes in sorted(snapshots.items(), key=lambda kv: order(kv[0])):
        if only and at not in only:
            continue
        label = f"{float(at):g}s" if order(at)[0] == 0 else at
        for size_name in names:
            out = Path(f"{args.out}_{label.replace(' ', '-')}_{size_name}.png")
            problems = render(json.loads(json.dumps(nodes)), size_name, out)
            engine = any(size_name in (n.get("L") or {}) for n in nodes)
            total += len(problems)
            print(f"wrote {out}" + ("" if engine else "   (no engine layout for this size: estimated)"))
            for problem in problems:
                print("    ", problem)
    print(f"{total} problem(s)")


if __name__ == "__main__":
    main()

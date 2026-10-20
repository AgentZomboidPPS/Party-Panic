"""Draws the player's on-screen UI from a round_harness snapshot at several screen sizes (PC and
phones), with Roblox's own buttons, the touch thumbstick and the jump button drawn on top, and
reports overlaps and anything off-screen, so HUD layouts can be checked without a device.

    python3 tools/checks/round_harness.py HoneyTrap --client --ui-at 2,12 ... > run.luau
    python3 tools/preview/luau_task.py run.luau - run.json
    python3 tools/checks/ui_render.py run.json /tmp/honey_ui            # every snapshot, every size
    python3 tools/checks/ui_render.py run.json /tmp/honey_ui --sizes phone

Layout follows Roblox's rules for what the HUD uses: UDim2 position/size/anchor, UIScale (the
UIKit.AutoScale ones are recomputed for each screen), UIListLayout, UIPadding,
UIAspectRatioConstraint, UICorner, UIGradient, UIStroke and text (TextScaled, wrapping,
alignment). Images are drawn as placeholders. Fonts: Fredoka for FredokaOne, Luckiest Guy, DejaVu
Sans Bold for the rest, Noto Emoji for emoji.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / "tools" / "art" / "fonts"
DESIGN = (1280, 720)
MIN_SCALE, MAX_SCALE = 0.62, 1.35
TOPBAR = 58

# name: (width, height, side safe inset, touch controls)
SIZES = {
    "pc": (1280, 720, 0, False),
    "pc-hd": (1920, 1080, 0, False),
    "phone": (844, 390, 47, True),  # notched phone, landscape
    "phone-small": (667, 375, 0, True),
    "tablet": (1024, 768, 0, True),
}
SIZE_GROUPS = {"phone": ["phone", "phone-small"], "pc": ["pc", "pc-hd"], "all": list(SIZES)}

# Pictographs go to the emoji font; plain symbols (arrows, shapes, suits, stars) stay in DejaVu,
# which has them, like Roblox's fonts do.
EMOJI = re.compile("[\\U0001F000-\\U0001FAFF\\u2600-\\u2604\\u2606-\\u265F\\u2668-\\u27BF\\u2B00-\\u2BFF\\u2300-\\u23FF\\uFE0F\\u200D]")
_font_cache: dict = {}


def font(name: str, size: int, emoji: bool = False) -> ImageFont.FreeTypeFont:
    size = max(4, int(round(size)))
    key = (name, size, emoji)
    if key in _font_cache:
        return _font_cache[key]
    if emoji:
        result = ImageFont.truetype(str(FONTS / "NotoEmoji.ttf"), size)
    elif "Fredoka" in name:
        result = ImageFont.truetype(str(FONTS / "Fredoka.ttf"), size)
        try:
            result.set_variation_by_name("SemiBold")
        except Exception:
            pass
    elif "Luckiest" in name:
        result = ImageFont.truetype(str(FONTS / "LuckiestGuy-Regular.ttf"), size)
    else:
        bold = any(word in name for word in ("Bold", "Black", "Heavy", "Builder", "Gotham", "Fredoka"))
        path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
        result = ImageFont.truetype(path, size)
    _font_cache[key] = result
    return result


def runs(text: str):
    """Splits text into (is_emoji, piece) runs."""
    out, current, is_emoji = [], "", None
    for ch in text:
        e = bool(EMOJI.match(ch))
        if is_emoji is None or e == is_emoji:
            current += ch
        else:
            out.append((is_emoji, current))
            current = ch
        is_emoji = e
    if current:
        out.append((is_emoji, current))
    return out


def text_width(text: str, name: str, size: float) -> float:
    total = 0.0
    for is_emoji, piece in runs(text):
        piece = piece.replace("️", "").replace("‍", "")
        if piece:
            total += font(name, size, is_emoji).getlength(piece)
    return total


def wrap(text: str, name: str, size: float, width: float, enabled: bool) -> list[str]:
    lines = []
    for paragraph in text.split("\n"):
        if not enabled:
            lines.append(paragraph)
            continue
        words, line = paragraph.split(" "), ""
        for word in words:
            candidate = word if not line else line + " " + word
            if text_width(candidate, name, size) <= width or not line:
                line = candidate
            else:
                lines.append(line)
                line = word
        lines.append(line)
    return lines


def fit_scaled(text: str, name: str, w: float, h: float, wrapping: bool) -> float:
    best = 4
    for size in range(4, 101):
        lines = wrap(text, name, size, w, wrapping)
        if max((text_width(line, name, size) for line in lines), default=0) <= w and len(lines) * size * 1.2 <= h:
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

    auto_scale = max(MIN_SCALE, min(MAX_SCALE, min(vw / DESIGN[0], vh / DESIGN[1])))
    draws = []  # (order key, kind, data)
    boxes = []  # content boxes for overlap checks: (screen, path, x0, y0, x1, y1, label)

    def path_of(i):
        parts = []
        while i:
            parts.append(node(i)["n"])
            i = node(i)["p"]
        return "/".join(reversed(parts))

    def auto_size(i, w, h, axes):
        """AutomaticSize: grow to fit the children (list layouts and plain children)."""
        padding = modifier(i, "UIPadding")
        left = right = top = bottom = 0.0
        if padding:
            (lsc, lof), (rsc, rof), (tsc, tof), (bsc, bof) = padding["pad"]
            left, right, top, bottom = lsc * w + lof, rsc * w + rof, tsc * h + tof, bsc * h + bof
        kids = [c for c in children[i] if "size" in node(c) and node(c).get("vis", True)]
        layout = modifier(i, "UIListLayout")
        inner_w = w - left - right
        if layout:
            gap = layout["pad"][1]
            sizes = [(node(c)["size"][0] * inner_w + node(c)["size"][1], node(c)["size"][3]) for c in kids]
            if layout["dir"] == "Vertical":
                need_w = max((s[0] for s in sizes), default=0)
                need_h = sum(s[1] for s in sizes) + gap * max(0, len(sizes) - 1)
            else:
                need_w = sum(s[0] for s in sizes) + gap * max(0, len(sizes) - 1)
                need_h = max((s[1] for s in sizes), default=0)
        else:
            need_w = max((node(c)["pos"][1] + node(c)["size"][1] for c in kids), default=0)
            need_h = max((node(c)["pos"][3] + node(c)["size"][3] for c in kids), default=0)
            if not kids and node(i).get("text"):
                size = node(i).get("ts", 14)
                need_w = text_width(node(i)["text"], node(i).get("font", ""), size)
                need_h = size * 1.2
        if axes in ("Y", "XY"):
            h = max(h, need_h + top + bottom)
        if axes in ("X", "XY"):
            w = max(w, need_w + left + right)
        return w, h

    def place(i, rect, transform, screen, order, visible):
        n = node(i)
        if n["c"] in ("UIScale", "UICorner", "UIStroke", "UIGradient", "UIListLayout", "UIPadding", "UIAspectRatioConstraint"):
            return
        px, py, pw, ph = rect
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
        ax, ay = n["anchor"]
        psx, pox, psy, poy = n["pos"]
        if n.get("touchSlot") and touch:
            # Api.Button on touch screens: beside the jump button (same rule as Api.jumpButtonSpot).
            small = min(pw, ph) <= 500
            jump = 70 if small else 120
            left = pw - (jump * 1.5 - 10)
            center = (ph - jump - 20 if small else ph - jump * 1.75) + jump / 2
            scale_mod = modifier(i, "UIScale")
            width = w * (auto_scale if scale_mod and scale_mod.get("auto") else 1)
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
        scale_mod = modifier(i, "UIScale")
        if scale_mod:
            s = auto_scale * scale_mod["auto"] if scale_mod.get("auto") else scale_mod.get("scale", 1)
            s = max(MIN_SCALE, min(MAX_SCALE, s)) if scale_mod.get("auto") else s
            own = transform.then_scale_about(x + ax * w, y + ay * h, s)
        visible = visible and n.get("vis", True)
        x0, y0 = own.apply(x, y)
        x1, y1 = own.apply(x + w, y + h)
        if visible:
            draws.append(((order, n.get("z", 1)), i, (x0, y0, x1, y1), own.k))
            if n.get("text", "") != "" or n["c"] in ("TextButton", "ImageButton"):
                boxes.append((screen, path_of(i), x0, y0, x1, y1, (n.get("text") or n["n"])[:40]))
        # Children's content rect (padding).
        cx, cy, cw, ch = x, y, w, h
        padding = modifier(i, "UIPadding")
        if padding:
            (lsc, lof), (rsc, rof), (tsc, tof), (bsc, bof) = padding["pad"]
            left, right, top, bottom = lsc * w + lof, rsc * w + rof, tsc * h + tof, bsc * h + bof
            cx, cy, cw, ch = x + left, y + top, w - left - right, h - top - bottom
        layout = modifier(i, "UIListLayout")
        kids = [c for c in children[i] if node(c)["c"] not in ("UIScale", "UICorner", "UIStroke", "UIGradient", "UIListLayout", "UIPadding", "UIAspectRatioConstraint")]
        if layout:
            flow = [c for c in kids if node(c).get("vis", True)]
            flow.sort(key=(lambda c: node(c).get("lo", 0)) if layout["sort"] == "LayoutOrder" else (lambda c: node(c)["n"]))
            gap_s, gap_o = layout["pad"]
            vertical = layout["dir"] == "Vertical"
            gap = gap_s * (ch if vertical else cw) + gap_o
            sizes = []
            for c in flow:
                cs = node(c)["size"]
                sizes.append((cs[0] * cw + cs[1], cs[2] * ch + cs[3]))
            total = sum(s[1] if vertical else s[0] for s in sizes) + gap * max(0, len(flow) - 1)
            if vertical:
                start = cy + {"Top": 0, "Center": (ch - total) / 2, "Bottom": ch - total}.get(layout["va"], 0)
            else:
                start = cx + {"Left": 0, "Center": (cw - total) / 2, "Right": cw - total}.get(layout["ha"], 0)
            cursor = start
            for c, (sw, sh) in zip(flow, sizes):
                if vertical:
                    lx = cx + {"Left": 0, "Center": (cw - sw) / 2, "Right": cw - sw}.get(layout["ha"], 0)
                    node(c)["_listpos"] = (lx, cursor)
                    cursor += sh + gap
                else:
                    ly = cy + {"Top": 0, "Center": (ch - sh) / 2, "Bottom": ch - sh}.get(layout["va"], 0)
                    node(c)["_listpos"] = (cursor, ly)
                    cursor += sw + gap
        kids.sort(key=lambda c: node(c).get("z", 1))
        for c in kids:
            place(c, (cx, cy, cw, ch), own, screen, order + 1, visible)

    screens = [i for i in children[0] if node(i)["c"] == "ScreenGui" and node(i).get("enabled", True)]
    screens.sort(key=lambda i: node(i).get("order", 0))
    for rank, i in enumerate(screens):
        n = node(i)
        area = (side, TOPBAR, vw - 2 * side, vh - TOPBAR) if n.get("inset", True) else (0, 0, vw, vh)
        for c in sorted(children[i], key=lambda c: node(c).get("z", 1)):
            place(c, area, Transform(), n["n"], rank * 1000, True)

    # Paint.
    image = Image.new("RGBA", (vw, vh), (120, 170, 120, 255))
    backdrop = ImageDraw.Draw(image)
    for row in range(vh):  # a sky-and-grass backdrop so the HUD reads like it does in game
        t = row / vh
        color = (140, 190, 240) if t < 0.45 else (110, 175, 95)
        backdrop.line([(0, row), (vw, row)], fill=color)
    draws.sort(key=lambda d: d[0])
    for _, i, (x0, y0, x1, y1), k in draws:
        n = node(i)
        layer = Image.new("RGBA", (vw, vh), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        w, h = x1 - x0, y1 - y0
        corner = modifier(i, "UICorner")
        radius = 0
        if corner:
            rs, ro = corner["radius"]
            radius = max(0, min(min(w, h) / 2, rs * min(w, h) + ro * k))
        box = [x0, y0, max(x0 + 1, x1), max(y0 + 1, y1)]
        bgt = n.get("bgt", 1)
        if bgt < 1 and w > 0 and h > 0:
            gradient = modifier(i, "UIGradient")
            base = n.get("bg", [255, 255, 255])
            if gradient:
                fill_layer = Image.new("RGBA", (vw, vh), (0, 0, 0, 0))
                fd = ImageDraw.Draw(fill_layer)
                steps = max(2, int(h))
                for s in range(steps):
                    t = s / (steps - 1)
                    c = [base[j] * (gradient["c0"][j] + (gradient["c1"][j] - gradient["c0"][j]) * t) / 255 for j in range(3)]
                    fd.line([(x0, y0 + s), (x1, y0 + s)], fill=rgba(c, bgt))
                mask = Image.new("L", (vw, vh), 0)
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
        if is_text and n.get("text") and n.get("tt", 0) < 1 and w > 2 and h > 2:
            name = n.get("font", "")
            text = re.sub(r"<[^>]+>", "", n["text"])  # rich text tags
            size = fit_scaled(text, name, w, h, n.get("wrap", False)) if n.get("scaled") else n.get("ts", 14) * k
            lines = wrap(text, name, size, w, n.get("wrap", False))
            line_h = size * 1.15
            total = line_h * len(lines)
            ty = {"Top": y0, "Center": y0 + (h - total) / 2, "Bottom": y1 - total}.get(n.get("ya", "Center"), y0)
            text_stroke = None
            if stroke and stroke.get("enabled", True) and stroke.get("mode") != "Border":
                text_stroke = (rgba(stroke["color"], stroke["t"]), max(1, int(round(stroke["thick"] * k))))
            elif n.get("st", 1) < 1:
                text_stroke = ((0, 0, 0, int(255 * (1 - n["st"]))), 1)
            for line in lines:
                lw = text_width(line, name, size)
                tx = {"Left": x0, "Center": x0 + (w - lw) / 2, "Right": x1 - lw}.get(n.get("xa", "Center"), x0)
                for is_emoji, piece in runs(line):
                    piece = piece.replace("️", "").replace("‍", "")
                    if not piece:
                        continue
                    f = font(name, size, is_emoji)
                    kwargs = {}
                    if text_stroke and not is_emoji:
                        kwargs = {"stroke_width": text_stroke[1], "stroke_fill": text_stroke[0]}
                    d.text((tx, ty + (line_h - size) / 2), piece, font=f, fill=rgba(n.get("tc", [255, 255, 255]), n.get("tt", 0)), **kwargs)
                    tx += f.getlength(piece)
                ty += line_h
        image = Image.alpha_composite(image, layer)

    # Roblox's own UI on top: top bar buttons, and touch controls on phones/tablets.
    overlay = Image.new("RGBA", (vw, vh), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    core = [(side + 12, 7, side + 56, 51, "R"), (side + 64, 7, side + 108, 51, "chat"), (vw - side - 56, 7, vw - side - 12, 51, "...")]
    for x0, y0, x1, y1, label in core:
        od.rounded_rectangle([x0, y0, x1, y1], radius=22, fill=(20, 20, 30, 150))
        od.text(((x0 + x1) / 2, (y0 + y1) / 2), label, font=font("Bold", 13), fill=(255, 255, 255, 220), anchor="mm")
        boxes.append(("RobloxCore", "TopBar/" + label, x0, y0, x1, y1, label))
    if touch:
        # Roblox's TouchJump rule, and the DynamicThumbstick's touch zone (left 40%, bottom 2/3).
        cw, ch = vw - 2 * side, vh - TOPBAR
        small = min(cw, ch) <= 500
        jump = 70 if small else 120
        jx0 = side + cw - (jump * 1.5 - 10)
        jy0 = TOPBAR + (ch - jump - 20 if small else ch - jump * 1.75)
        od.ellipse([jx0, jy0, jx0 + jump, jy0 + jump], fill=(255, 255, 255, 70), outline=(255, 255, 255, 160), width=2)
        od.text((jx0 + jump / 2, jy0 + jump / 2), "JUMP", font=font("Bold", 12), fill=(255, 255, 255, 230), anchor="mm")
        boxes.append(("RobloxCore", "Touch/Jump", jx0, jy0, jx0 + jump, jy0 + jump, "JUMP"))
        zone = (side, TOPBAR + ch / 3, side + cw * 0.4, vh)
        od.rectangle(zone, outline=(255, 255, 255, 60), width=1)
        ring = 90 if small else 140
        rx, ry = side + 40 + ring / 2, vh - 40 - ring / 2
        od.ellipse([rx - ring / 2, ry - ring / 2, rx + ring / 2, ry + ring / 2], fill=(255, 255, 255, 45), outline=(255, 255, 255, 140), width=2)
        od.text((rx, ry), "MOVE", font=font("Bold", 12), fill=(255, 255, 255, 220), anchor="mm")
        boxes.append(("RobloxCore", "Touch/Thumbstick", rx - ring / 2, ry - ring / 2, rx + ring / 2, ry + ring / 2, "MOVE"))
    if side:
        od.rectangle([0, 0, side, vh], fill=(0, 0, 0, 90))
        od.rectangle([vw - side, 0, vw, vh], fill=(0, 0, 0, 90))
    image = Image.alpha_composite(image, overlay)
    image.convert("RGB").save(out)

    # Checks.
    problems = []
    for a in range(len(boxes)):
        sa, pa, ax0, ay0, ax1, ay1, la = boxes[a]
        if ax1 < 0 or ay1 < 0 or ax0 > vw or ay0 > vh:
            continue
        if sa != "RobloxCore" and (ax0 < -1 or ay0 < -1 or ax1 > vw + 1 or ay1 > vh + 1):
            problems.append(f"off-screen: {pa} '{la}' at ({ax0:.0f},{ay0:.0f})-({ax1:.0f},{ay1:.0f})")
        for b in range(a + 1, len(boxes)):
            sb, pb, bx0, by0, bx1, by1, lb = boxes[b]
            if pa.startswith(pb + "/") or pb.startswith(pa + "/"):
                continue  # a label inside its own button/panel
            if sa == sb and sa != "RobloxCore" and pa.split("/")[:2] == pb.split("/")[:2]:
                continue  # same widget group
            ix = min(ax1, bx1) - max(ax0, bx0)
            iy = min(ay1, by1) - max(ay0, by0)
            if ix > 2 and iy > 2:
                area = ix * iy
                smaller = min((ax1 - ax0) * (ay1 - ay0), (bx1 - bx0) * (by1 - by0))
                if smaller > 0 and area / smaller > 0.15:
                    problems.append(f"overlap {area / smaller:.0%}: {pa} '{la}'  x  {pb} '{lb}'")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("results", help="the file luau_task.py saved for a round_harness run with --ui-at")
    parser.add_argument("out", help="output prefix: <out>_<time>_<size>.png")
    parser.add_argument("--sizes", default="all", help="all, pc, phone, or comma-separated names: " + ", ".join(SIZES))
    args = parser.parse_args()
    data = json.load(open(args.results))
    data = data[0] if isinstance(data, list) else data
    data = json.loads(data) if isinstance(data, str) else data
    snapshots = (data or {}).get("ui") or {}
    if not snapshots:
        raise SystemExit("No UI snapshots: run round_harness.py with --client --ui-at <seconds>")
    names = SIZE_GROUPS.get(args.sizes) or args.sizes.split(",")
    for at, nodes in sorted(snapshots.items(), key=lambda kv: float(kv[0])):
        for size_name in names:
            out = Path(f"{args.out}_{float(at):g}s_{size_name}.png")
            problems = render(json.loads(json.dumps(nodes)), size_name, out)
            print(f"wrote {out}")
            for problem in problems:
                print("    ", problem)


if __name__ == "__main__":
    main()

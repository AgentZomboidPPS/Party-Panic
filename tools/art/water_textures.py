"""Seamless water textures for Shark Bait (owner: "visually look sick af"): light caustics that
dance on the sea floor and ripple lines that drift over the water's surface. Both are RGBA (white
lines on transparent), tile without seams, and are scrolled by the client half in two layers.

    python3 tools/art/water_textures.py            # writes assets/textures/SharkBait{Caustics,Ripples}.png
    python3 tools/art/water_textures.py --upload   # ...and uploads them (owner's account, Open Use,
                                                   # the game may use them); prints the image ids for
                                                   # SharkBait.Textures in src/server/MiniGames/SharkBait.luau
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "textures"
N = 512


def worley_edges(points: int, seed: int) -> np.ndarray:
    """Tileable Worley noise, F2 - F1 (small along the cells' edges), on a torus."""
    rng = np.random.default_rng(seed)
    pts = rng.random((points, 2)) * N
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    best1 = np.full((N, N), 1e9, np.float32)
    best2 = np.full((N, N), 1e9, np.float32)
    for px, py in pts:
        dx = np.abs(x - px)
        dy = np.abs(y - py)
        dx = np.minimum(dx, N - dx)
        dy = np.minimum(dy, N - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < best1
        best2 = np.where(closer, best1, np.minimum(best2, d))
        best1 = np.where(closer, d, best1)
    return best2 - best1


def waves(seed: int, freqs=(1, 2, 3)) -> np.ndarray:
    """A smooth tileable field: a few sine trains whose wavelengths divide the tile."""
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    field = np.zeros((N, N), np.float32)
    for k in freqs:
        for _ in range(3):
            a, b = rng.integers(-k, k + 1, 2)
            if a == 0 and b == 0:
                continue
            field += np.sin(2 * np.pi * (a * x + b * y) / N + rng.random() * 6.28) / k
    return field


def warp(field: np.ndarray, amount: float, seed: int) -> np.ndarray:
    """Bends a tileable field by a tileable displacement (it stays seamless)."""
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    ox = waves(seed) * amount
    oy = waves(seed + 1) * amount
    return field[((y + oy) % N).astype(int), ((x + ox) % N).astype(int)]


def save(alpha: np.ndarray, color: tuple[int, int, int], peak: int, name: str, blur: float) -> Path:
    img = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(blur))
    a = np.asarray(img).astype(np.float32) / 255
    rgba = np.zeros((N, N, 4), np.uint8)
    rgba[..., 0], rgba[..., 1], rgba[..., 2] = color
    rgba[..., 3] = (np.clip(a * 1.25, 0, 1) * peak).astype(np.uint8)
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.png"
    Image.fromarray(rgba, "RGBA").save(path)
    return path


def make() -> list[Path]:
    # Caustics: a web of light, the cells wobbled so it never looks like a grid.
    caustics = np.clip(1 - warp(worley_edges(26, 3), 6, 5) / 7.5, 0, 1) ** 2.2
    # Ripples: a sparse web of bent lines, broken into dashes by a smooth mask.
    lines = np.clip(1 - warp(worley_edges(14, 21), 10, 4) / 4.0, 0, 1) ** 1.5
    mask = np.clip((waves(9, (2, 3, 4)) + 0.2) / 1.2, 0, 1)
    return [
        save(caustics, (235, 255, 250), 255, "SharkBaitCaustics", 1.2),
        save(lines * mask, (255, 255, 255), 230, "SharkBaitRipples", 1.0),
    ]


def upload(paths: list[Path]):
    sys.path.insert(0, str(ROOT / "tools"))
    sys.path.insert(0, str(ROOT / "tools" / "preview"))
    from asset_permissions import grant, open_use
    from make_preview import USER_ID, image_in
    from upload_assets import upload as upload_asset

    for path in paths:
        decal = upload_asset(path, "Decal", f"Party Panic: {path.stem}", "Party Panic: Shark Bait water texture.",
                             {"userId": USER_ID}, "image/png")
        image = image_in(decal)
        opened, errors = open_use([image])
        granted, grant_errors = grant([image, decal])
        print(f"{path.stem}: image {image} (decal {decal}); open use {image in opened}; the game may use it "
              f"{image in granted}; errors {errors + grant_errors}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--upload", action="store_true")
    args = parser.parse_args()
    made = make()
    for path in made:
        print(f"wrote {path.relative_to(ROOT)}")
    if args.upload:
        upload(made)

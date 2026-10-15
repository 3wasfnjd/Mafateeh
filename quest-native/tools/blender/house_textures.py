"""Tileable textures for the house kit, matched to the owner's sandstone tower
(art_source/world/sandstone_tower.usdz): orange mud plaster with patches fallen away to show
the mud bricks underneath, soft baked relief, a few cracks. Also a painted Najdi door and wood.
Plain NumPy + PIL, deterministic. Run alone to write the PNGs:  python3 house_textures.py out_dir
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# sampled from the tower's base colour (sRGB): plaster mid tone, light, brick, shadow
PLASTER = np.array([204, 128, 56], float)
PLASTER_HI = np.array([224, 148, 70], float)
BRICK = np.array([178, 104, 42], float)
SHADOW = np.array([128, 66, 22], float)


def tile_noise(n, seed, octaves=(4, 8, 16, 32, 64), falloff=1.7):
    """Smooth noise in 0..1 that wraps at the edges (so the texture tiles)."""
    r = np.random.default_rng(seed)
    acc = np.zeros((n, n))
    for o, s in enumerate(octaves):
        g = r.random((s, s))
        big = np.tile(g, (3, 3))
        im = Image.fromarray((big * 255).astype(np.uint8)).resize((n * 3, n * 3), Image.BICUBIC)
        acc += np.asarray(im, float)[n:2 * n, n:2 * n] / 255 / (falloff ** o)
    acc -= acc.min()
    return acc / acc.max()


def shift(a, dy, dx):
    return np.roll(np.roll(a, dy, 0), dx, 1)


def mud_wall(n=1024, seed=3, metres=2.0):
    """Plaster with brick patches. One tile covers `metres`; bricks are about 28 x 9 cm."""
    rng = np.random.default_rng(seed)
    px = n / metres
    bh, bw = int(0.09 * px), int(0.28 * px)
    # bricks: running bond, per-brick tint and slight size jitter, dark mortar, each brick
    # lit along its top edge and shaded along its bottom (raised, like the tower)
    yy, xx = np.mgrid[0:n, 0:n]
    row = yy // bh
    off = (row % 2) * (bw // 2) + (row * 37) % 11
    col = (xx + off) // bw
    tint = rng.random((n // bh + 2, n // bw + 3))
    bt = tint[row % tint.shape[0], col % tint.shape[1]]
    ly, lx = yy % bh, (xx + off) % bw
    mortar = (ly < 4) | (lx < 4)
    fine = tile_noise(n, seed + 7, octaves=(32, 64, 128, 256), falloff=1.3)
    brick = (BRICK + 22) * (0.86 + 0.2 * bt[..., None]) * (0.9 + 0.14 * fine[..., None])
    brick = brick * (1 + 0.16 * ((ly >= 4) & (ly < 8))[..., None]) * (1 - 0.22 * (ly > bh - 4)[..., None])
    brick[mortar] = SHADOW
    # plaster
    big = tile_noise(n, seed + 1)
    mid = tile_noise(n, seed + 2, octaves=(16, 32, 64, 128), falloff=1.4)
    plaster = PLASTER * (0.9 + 0.14 * big[..., None]) * (0.95 + 0.08 * mid[..., None])
    pits = tile_noise(n, seed + 11, octaves=(128, 256, 512), falloff=1.1)
    plaster = plaster * (1 - 0.08 * (pits[..., None] > 0.78)) + 6 * (fine[..., None] - 0.5)
    # where the plaster has fallen: a blotchy mask, edges ragged
    m = tile_noise(n, seed + 3, octaves=(4, 8, 16, 32, 64, 128), falloff=1.55)
    holes = m < 0.33
    out = np.where(holes[..., None], brick, plaster)
    # baked relief: plaster edge lit on top, shadow on the brick just below it
    h = holes.astype(float)
    rim_light = np.clip(h - shift(h, 3, 0), 0, 1)       # plaster just above a hole
    rim_shadow = np.clip(h - shift(h, -4, 0), 0, 1)     # brick just below plaster edge
    edge = np.clip(shift(h, 0, 2) + shift(h, 0, -2) + shift(h, 2, 0) + shift(h, -2, 0) - 4 * h, 0, 1)
    out = out * (1 - 0.35 * rim_shadow[..., None]) + 25 * rim_light[..., None]
    out = out * (1 - 0.18 * edge[..., None])
    # hairline cracks
    im = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    for _ in range(9):
        x, y = rng.random(2) * n
        a = rng.random() * np.pi
        for _ in range(rng.integers(6, 14)):
            a += rng.normal(0, 0.5)
            x2, y2 = x + np.cos(a) * 14, y + np.sin(a) * 14
            for ox in (-n, 0, n):
                for oy in (-n, 0, n):
                    d.line([(x + ox, y + oy), (x2 + ox, y2 + oy)], fill=tuple(int(c) for c in SHADOW), width=2)
            x, y = x2, y2
    return im.filter(ImageFilter.SMOOTH)


def mud_top(n=512, seed=9):
    """Smooth plaster for roofs, parapet tops and steps (no brick)."""
    big = tile_noise(n, seed)
    fine = tile_noise(n, seed + 1, octaves=(32, 64, 128), falloff=1.3)
    a = PLASTER_HI * (0.86 + 0.14 * big[..., None]) * (0.95 + 0.07 * fine[..., None])
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def sand(n=512, seed=12):
    big = tile_noise(n, seed)
    fine = tile_noise(n, seed + 1, octaves=(64, 128, 256), falloff=1.2)
    a = np.array([214, 178, 132], float) * (0.9 + 0.12 * big[..., None]) * (0.96 + 0.06 * fine[..., None])
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def wood(n=256, seed=5):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n]
    g = tile_noise(n, seed, octaves=(4, 8, 16), falloff=1.5)
    grain = 0.5 + 0.5 * np.sin((xx / n * 6 + g * 5) * np.pi * 2)
    a = np.array([118, 80, 50], float) * (0.8 + 0.25 * grain[..., None])
    a *= 0.95 + 0.1 * rng.random((n, n))[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def door(w=256, h=512, seed=6):
    """Painted Najdi door: planks, rows of triangles, diamonds, white dots."""
    n = tile_noise(512, seed)[:h, :w]
    d = np.array([126, 86, 56], float) * (0.85 + 0.2 * n[..., None])
    for x in range(0, w, 32):
        d[:, x:x + 2] = [86, 58, 38]
    im = Image.fromarray(np.clip(d, 0, 255).astype(np.uint8))
    dr = ImageDraw.Draw(im)

    def tri_row(y, col, th=14, step=24):
        for x in range(6, w - 10, step):
            dr.polygon([(x, y + th), (x + step / 2 - 2, y), (x + step - 4, y + th)], fill=col)
    for y, col in [(30, (196, 64, 52)), (150, (232, 184, 75)), (330, (42, 140, 135)), (460, (196, 64, 52))]:
        tri_row(y, col)
    for cy in (100, 250, 400):
        for cx in (64, 192):
            dr.polygon([(cx, cy - 36), (cx + 30, cy), (cx, cy + 36), (cx - 30, cy)], outline=(232, 184, 75), width=4)
            dr.polygon([(cx, cy - 16), (cx + 13, cy), (cx, cy + 16), (cx - 13, cy)], fill=(42, 140, 135))
            dr.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(244, 237, 224))
    for y in (192, 372):
        for x in range(12, w, 20):
            dr.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(244, 237, 224))
    return im


def clean_tower_texture(src, dst, size=2048):
    """Removes the red specks Tripo left in the tower texture (pure red against orange mud)."""
    a = np.asarray(Image.open(src).convert("RGB")).astype(float)
    r, g = a[..., 0], a[..., 1]
    bad = (r > 120) & (g / np.maximum(r, 1) < 0.42)
    bad = np.asarray(Image.fromarray((bad * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) > 0
    blur = np.asarray(Image.fromarray(a.astype(np.uint8)).filter(ImageFilter.MedianFilter(15)), float)
    # fill specks from the median of their surroundings (twice, for larger blobs)
    a[bad] = blur[bad]
    blur = np.asarray(Image.fromarray(a.astype(np.uint8)).filter(ImageFilter.MedianFilter(9)), float)
    a[bad] = blur[bad]
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    if im.size[0] != size:
        im = im.resize((size, size), Image.LANCZOS)
    im.save(dst, quality=90)
    return int(bad.sum())


def write_all(out):
    os.makedirs(out, exist_ok=True)
    mud_wall().save(os.path.join(out, "house_wall.png"))
    mud_top().save(os.path.join(out, "house_top.png"))
    wood().save(os.path.join(out, "house_wood.png"))
    door().save(os.path.join(out, "house_door.png"))


if __name__ == "__main__":
    write_all(sys.argv[1])

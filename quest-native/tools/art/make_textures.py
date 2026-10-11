"""Procedural, tileable textures for Mafateeh (no external images).
Usage: python3 make_textures.py <out_dir>
Writes: shemagh_albedo, thobe_albedo, plaster_albedo/normal, stone_albedo/normal, wood_albedo."""
import sys, os
import numpy as np
from PIL import Image

out = sys.argv[1]
rng = np.random.default_rng(1447)


def save(name, arr):
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(os.path.join(out, name))


def tile_noise(n, octaves, seed):
    r = np.random.default_rng(seed)
    acc = np.zeros((n, n))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        f = 4 * 2 ** o
        g = r.random((f, f))
        # bilinear upsample with wrap -> tileable
        x = np.linspace(0, f, n, endpoint=False)
        i0 = np.floor(x).astype(int) % f
        i1 = (i0 + 1) % f
        t = x - np.floor(x)
        t = t * t * (3 - 2 * t)
        a = g[i0][:, i0] * (1 - t)[None, :] + g[i0][:, i1] * t[None, :]
        b = g[i1][:, i0] * (1 - t)[None, :] + g[i1][:, i1] * t[None, :]
        acc += amp * (a * (1 - t)[:, None] + b * t[:, None])
        total += amp
        amp *= 0.5
    return acc / total


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    nz = np.ones_like(h)
    l = np.sqrt(dx * dx + dy * dy + nz * nz)
    n = np.stack([-dx / l, -dy / l, nz / l], -1)
    return (n * 0.5 + 0.5) * 255


# Shemagh: red ground with white diamond checks, as worn in Najd.
N = 512
y, x = np.mgrid[0:N, 0:N]
cell = 16
cx = (x % cell) - cell / 2 + 0.5
cy = (y % cell) - cell / 2 + 0.5
diamond = (np.abs(cx) + np.abs(cy)) < cell * 0.3
check = ((x // cell) + (y // cell)) % 2 == 0
dot = (np.abs(cx) + np.abs(cy)) < cell * 0.12
red = np.array([176, 30, 40])
white = np.array([244, 238, 228])
mask = (diamond & check) | (dot & ~check)
img = np.where(mask[..., None], white, red).astype(float)
weave = (tile_noise(N, 3, 3)[..., None] - 0.5) * 18 + ((x + y) % 3 == 0)[..., None] * -6
save("shemagh_albedo.png", img + weave)

# Thobe: warm ivory with a faint twill.
tw = ((x + y) % 6 < 3) * 5.0
base = np.array([241, 233, 216], float)
save("thobe_albedo.png", base[None, None, :] + (tile_noise(N, 4, 5)[..., None] - 0.5) * 14 - tw[..., None])

# Mud plaster: warm earth, trowel undulation and straw flecks.
h = tile_noise(N, 6, 11)
fleck = (rng.random((N, N)) > 0.996) * 1.0
col = np.stack([200 + (h - 0.5) * 50, 147 + (h - 0.5) * 42, 96 + (h - 0.5) * 34], -1) + fleck[..., None] * np.array([30, 25, 5])
save("plaster_albedo.png", col)
save("plaster_normal.png", normal_from_height(h + fleck * 0.08, 6.0))

# Sand stone (per tile; joints come from the tile mesh bevel).
h2 = tile_noise(N, 6, 21)
pores = (rng.random((N, N)) > 0.985) * -0.06
col2 = np.stack([206 + (h2 - 0.5) * 40, 178 + (h2 - 0.5) * 34, 134 + (h2 - 0.5) * 30], -1) + pores[..., None] * 300
save("stone_albedo.png", col2)
save("stone_normal.png", normal_from_height(h2 + pores, 4.0))

# Wood: dark tamarisk/palm wood planks.
grain = np.sin((y / N) * 2 * np.pi * 9 + tile_noise(N, 4, 31) * 9) * 0.5 + 0.5
col3 = np.stack([96 + grain * 40, 60 + grain * 26, 34 + grain * 14], -1)
save("wood_albedo.png", col3)
print("textures written to", out)

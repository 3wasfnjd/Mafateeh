"""Procedural textures for the v2 hero «الشايب» (NumPy + Pillow, deterministic).
paint_all(out_dir) writes shaib_*.png and returns {key: path}."""
import os

import numpy as np
from PIL import Image


def _noise(n, octaves, seed, base=4):
    """Tileable value noise in [0, 1]."""
    rng = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        k = base * 2 ** o
        g = rng.random((k, k))
        x = np.arange(n) * k / n
        i0 = np.floor(x).astype(int)
        f = x - i0
        f = f * f * (3 - 2 * f)
        i1 = (i0 + 1) % k
        a = g[np.ix_(i0, i0)] * (1 - f)[None, :] + g[np.ix_(i0, i1)] * f[None, :]
        b = g[np.ix_(i1, i0)] * (1 - f)[None, :] + g[np.ix_(i1, i1)] * f[None, :]
        out += amp * (a * (1 - f)[:, None] + b * f[:, None])
        tot += amp
        amp *= 0.5
    return out / tot


def _normal(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.stack([-dx, dy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return (n * 0.5 + 0.5)


def _save(out, name, arr):
    p = os.path.join(out, name)
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(p, optimize=True)
    return p


def _hex(h):
    return np.array([int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)])


def paint_all(out):
    os.makedirs(out, exist_ok=True)
    t = {}
    n = 512
    yy, xx = np.mgrid[0:n, 0:n] / n

    # Skin: warm tan with soft mottling and fine pores.
    m = _noise(n, 5, 1, 4)
    pores = _noise(n, 2, 2, 64)
    c = _hex("#c58e66")[None, None] * (0.92 + 0.12 * m[..., None])
    c += (_hex("#b5654e") - _hex("#c58e66"))[None, None] * 0.18 * _noise(n, 3, 3, 3)[..., None]
    c *= (0.97 + 0.05 * pores[..., None])
    t["skin"] = _save(out, "shaib_skin.png", c)

    # Face (head sphere UVs: u around from the front centre towards the left, v from the
    # crown down): cheek warmth, crow's feet, nasolabial creases, faint age spots.
    fu = np.minimum(xx, 1 - xx)  # 0 at the front centre, mirrored left/right
    face = c.copy()
    blush = np.exp(-(((fu - 0.105) / 0.045) ** 2 + ((yy - 0.56) / 0.06) ** 2))
    face += (_hex("#c8644e") - _hex("#c58e66"))[None, None] * 0.55 * blush[..., None]
    nose = np.exp(-((fu / 0.03) ** 2 + ((yy - 0.55) / 0.05) ** 2))
    face += (_hex("#c46a52") - _hex("#c58e66"))[None, None] * 0.35 * nose[..., None]
    hgt = np.zeros((n, n))
    for k in range(3):  # crow's feet: three short lines fanning from the outer eye corner
        ang = (-0.5 + k * 0.5)
        cx, cy = 0.118, 0.455
        dx, dy = fu - cx, yy - cy
        along = dx * np.cos(ang) + dy * np.sin(ang)
        across = -dx * np.sin(ang) + dy * np.cos(ang)
        line = np.exp(-(across / 0.0035) ** 2) * np.clip(1 - np.abs(along - 0.018) / 0.018, 0, 1)
        hgt -= line
    # nasolabial crease from the nose wing down towards the mouth corner
    for i in range(40):
        t_ = i / 39
        px, py = 0.045 + 0.03 * t_, 0.565 + 0.07 * t_
        hgt -= 0.5 * np.exp(-(((fu - px) / 0.006) ** 2 + ((yy - py) / 0.006) ** 2))
    # under-eye fine lines
    hgt -= 0.5 * np.exp(-(((yy - 0.505 - 0.25 * (fu - 0.07) ** 2 * 20) / 0.0035) ** 2)) * np.exp(-((fu - 0.07) / 0.035) ** 2)
    rng = np.random.default_rng(21)
    for _ in range(9):
        sx, sy, sr = rng.uniform(0.12, 0.2), rng.uniform(0.38, 0.6), rng.uniform(0.004, 0.008)
        spot = np.exp(-(((fu - sx) ** 2 + (yy - sy) ** 2) / sr ** 2))
        face += (_hex("#9a6446") - _hex("#c58e66"))[None, None] * 0.35 * spot[..., None]
    face *= (1 + 0.06 * np.clip(hgt, -1, 0)[..., None])
    t["face"] = _save(out, "shaib_face.png", face)
    t["face_n"] = _save(out, "shaib_face_n.png", _normal(hgt * 0.45 + pores * 0.15, 2.2))

    # Eye: ivory sclera, deep brown iris with radial fibres, dark limbal ring, pupil,
    # two painted catchlights (stylised; the real highlight comes from the lights).
    e = 256
    y, x = np.mgrid[0:e, 0:e] / e - 0.5
    r = np.hypot(x, y) * 2  # 0 centre .. 1 at the texture edge (= the back of the eye)
    a = np.arctan2(y, x)
    scl = _hex("#f3eee4")[None, None] * np.ones((e, e, 3))
    scl = scl * (1 - 0.10 * np.clip((r - 0.35) / 0.4, 0, 1)[..., None])
    scl += np.array([0.10, -0.02, -0.03]) * (np.clip((r - 0.32) / 0.3, 0, 1) * (0.5 + 0.5 * np.sin(a * 23)) * 0.4)[..., None]
    iris_r, pupil_r = 0.29, 0.115
    fib = 0.5 + 0.5 * np.sin(a * 41 + 3 * np.sin(a * 7)) * np.sin(a * 17 + r * 30)
    iris = _hex("#5a3518")[None, None] * (0.75 + 0.4 * fib[..., None]) * 1.0
    iris = iris * (0.75 + 0.45 * np.clip((r - pupil_r) / (iris_r - pupil_r), 0, 1)[..., None] * (1 - np.clip((r - iris_r * 0.8) / (iris_r * 0.2), 0, 1))[..., None])
    iris += _hex("#8a6a2a")[None, None] * 0.35 * np.clip(1 - np.abs(r - pupil_r * 1.6) / 0.05, 0, 1)[..., None]
    k = np.clip((iris_r - r) / 0.012, 0, 1)[..., None]
    col = scl * (1 - k) + iris * k
    ring = np.clip(1 - np.abs(r - iris_r + 0.006) / 0.016, 0, 1)[..., None]
    col = col * (1 - 0.65 * ring)
    pk = np.clip((pupil_r - r) / 0.01, 0, 1)[..., None]
    col = col * (1 - pk) + np.array([0.03, 0.02, 0.02]) * pk
    for cx, cy, rr in ((-0.055, 0.06, 0.035), (0.05, -0.05, 0.016)):
        hl = np.clip((rr - np.hypot(x - cx * 2 / 2, y - cy)) / 0.006, 0, 1)[..., None]
        col = col * (1 - hl) + hl
    t["eye"] = _save(out, "shaib_eye.png", col)

    # Hair (beard, brows, mustache): white with soft grey strands along v.
    s = _noise(n, 3, 5, 8)
    strands = 0.5 + 0.5 * np.sin(xx * np.pi * 2 * 90 + s * 12)
    h = 0.6 * strands + 0.4 * _noise(n, 4, 6, 16)
    hair = _hex("#f4f1ea")[None, None] * (0.86 + 0.16 * h[..., None])
    hair += np.array([-0.04, -0.04, -0.02]) * (h < 0.25)[..., None]
    t["hair"] = _save(out, "shaib_hair.png", hair)
    t["hair_n"] = _save(out, "shaib_hair_n.png", _normal(h, 2.0))

    # Thobe: fine cotton plain weave, warm white.
    wv = (0.5 + 0.5 * np.sin(xx * np.pi * 2 * 256)) * (0.5 + 0.5 * np.sin(yy * np.pi * 2 * 256))
    slub = _noise(n, 3, 7, 32)
    th = _hex("#f5f2eb")[None, None] * (0.97 + 0.02 * wv[..., None] + 0.03 * slub[..., None])
    t["thobe"] = _save(out, "shaib_thobe.png", th)
    t["thobe_n"] = _save(out, "shaib_thobe_n.png", _normal(wv * 0.25 + slub * 0.5, 0.6))

    # Shemagh (after the owner's reference photos): the Saudi red-on-white "dog-tooth"
    # weave: each cell holds a red diamond with four short diagonal teeth, laid on a
    # diagonal lattice so white diamonds read between them. Tileable; 10 cells per tile.
    k = 10
    u, v = xx * k, yy * k
    fu, fv = u % 1 - 0.5, v % 1 - 0.5
    red = _hex("#b8182a")
    white = _hex("#f3eee6")
    dia = (np.abs(fu) + np.abs(fv)) < 0.36
    teeth = np.zeros_like(dia)
    for sx in (-1, 1):
        for sy in (-1, 1):
            # a short arm along the diagonal from the diamond towards the cell corner
            px, py = fu * sx, fv * sy
            along = (px + py) / np.sqrt(2)
            across = (px - py) / np.sqrt(2)
            teeth |= (along > 0.12) & (along < 0.62) & (np.abs(across) < 0.10 - 0.03 * (along > 0.47))
    hole = (np.abs(fu) + np.abs(fv)) < 0.10  # small white eye in the diamond
    motif = (dia | teeth) & ~hole
    # Woven edges: soften with the thread grid so it reads as cloth, not print.
    weave = (0.5 + 0.5 * np.sin(xx * np.pi * 2 * 200)) * (0.5 + 0.5 * np.sin(yy * np.pi * 2 * 200))
    m = motif.astype(float)
    m = 0.5 * m + 0.125 * (np.roll(m, 1, 0) + np.roll(m, -1, 0) + np.roll(m, 1, 1) + np.roll(m, -1, 1))
    sh = white[None, None] * (1 - m[..., None]) + red[None, None] * m[..., None]
    sh = sh * (0.94 + 0.06 * weave[..., None]) * (0.96 + 0.06 * _noise(n, 3, 9, 8)[..., None])
    t["shemagh"] = _save(out, "shaib_shemagh.png", sh)
    t["shemagh_n"] = _save(out, "shaib_shemagh_n.png", _normal(weave * 0.6 + m * 0.15, 0.9))

    # Border band at the hanging edges (u along the hem, v across: 0 inner -> 1 edge):
    # thick red bar, zigzag row, dotted row, fine lines, then the rolled white edge.
    b = np.ones((n, n, 3)) * white
    uu = (xx * 12) % 1
    def band(lo, hi):
        return (yy > lo) & (yy < hi)
    zig = np.abs(((uu * 2) % 1) - 0.5) * 2  # 0..1 triangle wave
    rows = (band(0.10, 0.20) | band(0.26, 0.29) | band(0.70, 0.73) |
            (band(0.36, 0.62) & (np.abs((yy - 0.36) / 0.26 - zig) < 0.30)) |
            (band(0.78, 0.86) & (np.abs(((xx * 24) % 1) - 0.5) < 0.2)))
    b = np.where(rows[..., None], red, b)
    b = b * (0.94 + 0.06 * weave[..., None])
    t["shemagh_border"] = _save(out, "shaib_shemagh_border.png", b)

    # Agal: twisted black goat-hair cord (diagonal twist).
    tw = 0.5 + 0.5 * np.sin((xx * 3 + yy) * np.pi * 2 * 6)
    ag = _hex("#1b191d")[None, None] * (0.75 + 0.6 * tw[..., None]) * (0.9 + 0.2 * _noise(n, 3, 11, 16)[..., None])
    t["agal"] = _save(out, "shaib_agal.png", ag)

    # Wood: warm walnut grain along v (cane length).
    g = _noise(n, 4, 13, 4)
    grain = 0.5 + 0.5 * np.sin(xx * np.pi * 2 * 6 + g * 10 + yy * 2)
    wd = _hex("#6b3f22")[None, None] * (0.78 + 0.35 * grain[..., None]) * (0.9 + 0.15 * _noise(n, 3, 14, 32)[..., None])
    t["wood"] = _save(out, "shaib_wood.png", wd)

    # Leather sandals.
    lt = _hex("#5c3823")[None, None] * (0.85 + 0.25 * _noise(n, 5, 15, 8)[..., None])
    t["leather"] = _save(out, "shaib_leather.png", lt)
    return t

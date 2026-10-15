"""Perspective rectification of a flat face in a reference image (the owner's renders of
house pieces) into a straight-on texture.

A face is given by four image points of a rectangle on it, TL, TR, BR, BL (pixels), whose
real size is width x ref_h metres. The output can extend above that rectangle (up to
total_h metres, same plane) to take in parapets, gables and peaks.
"""
import numpy as np
from PIL import Image


def homography(src, dst):
    """3x3 H with dst ~ H @ src for four point pairs."""
    A = []
    for (x, y), (u, v) in zip(src, dst):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y, -u])
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y, -v])
    _, _, vt = np.linalg.svd(np.array(A, float))
    H = vt[-1].reshape(3, 3)
    return H / H[2, 2]


def rectify(img, quad, width, ref_h, total_h=None, px_per_m=256, below=0.0):
    """Returns (RGBA image, px_per_m). Output x: 0..width m, z: -below..total_h m (bottom = 0)."""
    total_h = total_h or ref_h
    W = int(round(width * px_per_m))
    Hh = int(round((total_h + below) * px_per_m))
    # output pixel coords of the reference rectangle corners
    top = (total_h - ref_h) * px_per_m
    bot = total_h * px_per_m
    out_pts = [(0, top), (W, top), (W, bot), (0, bot)]
    H = homography(out_pts, quad)  # output pixel -> input pixel
    coeffs = (H.flatten() / H[2, 2])[:8]
    im = img.convert("RGBA").transform((W, Hh), Image.Transform.PERSPECTIVE, tuple(coeffs), Image.Resampling.BICUBIC)
    return im

"""The procedural, tileable skin micro-relief texture of the bake (numpy + scipy), a 16-bit PNG.

It replaces per-sample Voronoi pore networks in the bake's skin shader (one box-projected image
lookup). Ported from the M10 research run's frozen kit snapshot; the file is now written where the
caller asks (the bake's cache or temporary folder), never into the repository.
"""
from __future__ import annotations

import os

import numpy as np

MICRO_TILE_M = 0.024     # one tile covers 24 mm of (human-scale) skin
MICRO_SIZE = 1024
MICRO_SEED = 7


def _periodic_points(n, rng):
    return rng.random((n, 2))


def _wrap_kdtree(pts):
    from scipy.spatial import cKDTree
    offs = np.array([[dx, dy] for dx in (-1, 0, 1) for dy in (-1, 0, 1)], float)
    allp = (pts[None, :, :] + offs[:, None, :]).reshape(-1, 2)
    idx = np.tile(np.arange(len(pts)), 9)
    return cKDTree(allp), idx


def _fbm(size, rng, octaves=5, base=4):
    """Tileable fractal value noise in [0,1]."""
    out = np.zeros((size, size))
    amp, tot = 1.0, 0.0
    for _o in range(octaves):
        n = base * (2 ** _o)
        g = rng.random((n, n))
        # band-limited upsample with wrap via FFT zero padding (keeps it tileable)
        G = np.fft.fft2(g)
        P = np.zeros((size, size), complex)
        h = n // 2
        P[:h, :h] = G[:h, :h]
        P[:h, -h:] = G[:h, -h:]
        P[-h:, :h] = G[-h:, :h]
        P[-h:, -h:] = G[-h:, -h:]
        up = np.real(np.fft.ifft2(P)) * (size * size) / (n * n)
        up = (up - up.min()) / (np.ptp(up) + 1e-9)
        out += amp * up
        tot += amp
        amp *= 0.5
    return out / tot


def make_micro(path, size=MICRO_SIZE, seed=MICRO_SEED):
    """Height map: pores (dimples), polygonal skin furrows, fine noise. Mid-grey = 0. Writes
    ``path`` (16-bit greyscale PNG) unless it exists; returns ``path``."""
    if os.path.exists(path):
        return path
    rng = np.random.default_rng(seed)
    tile = MICRO_TILE_M
    yy, xx = np.mgrid[0:size, 0:size]
    uv = np.stack([(xx + 0.5) / size, (yy + 0.5) / size], axis=-1).reshape(-1, 2)
    # furrows: edges of a cell network (~0.55 mm cells), with jitter
    ncell = int((tile / 0.00055) ** 2)
    cells = _periodic_points(ncell, rng)
    kd, _ = _wrap_kdtree(cells)
    d, _ = kd.query(uv, k=2)
    edge = (d[:, 1] - d[:, 0]) * (tile * 1000.0)       # mm
    furrow = np.exp(-(edge / 0.035) ** 2)
    # a coarser furrow family (~1.6 mm), deeper
    cells2 = _periodic_points(int((tile / 0.0016) ** 2), rng)
    kd2, _ = _wrap_kdtree(cells2)
    d2, _ = kd2.query(uv, k=2)
    edge2 = (d2[:, 1] - d2[:, 0]) * (tile * 1000.0)
    furrow2 = np.exp(-(edge2 / 0.03) ** 2)
    # pores: dimples at random points (~0.75 mm spacing), random sizes
    npore = int((tile / 0.00075) ** 2)
    pores = _periodic_points(npore, rng)
    kd3, idx3 = _wrap_kdtree(pores)
    d3, i3 = kd3.query(uv, k=1)
    prad = 0.05 + 0.07 * rng.random(npore)          # mm
    pdep = 0.5 + 0.5 * rng.random(npore)
    r = d3 * (tile * 1000.0)
    pit = pdep[idx3[i3]] * np.exp(-(r / prad[idx3[i3]]) ** 2)
    fine = _fbm(size, rng, octaves=4, base=32).reshape(-1)
    h = 0.5 - 0.22 * furrow - 0.30 * furrow2 - 0.45 * pit + 0.06 * (fine - 0.5)
    h = h.reshape(size, size)
    h = (h - h.min()) / (np.ptp(h) + 1e-9)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    from PIL import Image
    tmp = path + ".part.png"
    Image.fromarray((h * 65535).astype(np.uint16)).save(tmp)
    os.replace(tmp, path)
    return path

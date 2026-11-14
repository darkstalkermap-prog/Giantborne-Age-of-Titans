"""The game's texture set (the step --pack): two tiers of the baked maps, the hair atlas and the
cloth detail maps (numpy + Pillow; no Blender).

  tex/albedo.png     RGB  base colour at the neutral tone (sRGB), 512 px
  tex/normal.png     RGB  tangent-space normal (OpenGL, Y up), 512 px
  tex/orm.png        RGB  R ambient occlusion, G roughness, B thickness (1 = thin), 512 px
  tex/masks.png      RGBA R stubble/beard area, G scalp, B brows, A lips, 512 px
  tex_hi/normal.png  RGB  the normal map at 1024 px (desktop; the Web too since the owner's 26 MiB answer)
  tex_hi/orm.png     RGB  the ORM map at 1024 px, AO and thickness at full precision: build_giant.py
                          --skip-bake reads them back from here
  hair_atlas.png     RGBA 512 px strands: A coverage, R strand brightness, G strand id (grey strands),
                          B root-to-tip (0 at the root); four columns: dense straight, dense wavy,
                          clumped, sparse wispy
  cloth_weave.png    RGBA 128 px tileable detail: RGB a tangent-space normal (OpenGL, Y up), A the
  cloth_leather.png       albedo detail (0.75 = neutral): plain weave, grained leather and fur
  cloth_fur.png

Every downscale resizes one channel at a time (Pillow's RGBA resize premultiplies by alpha and
wiped the RGB channels of the research's 512 px masks). Ported from the research's pack and hair
card scripts (the atlas); the cloth maps are new.

Usage: python pack.py <bake dir> <out dir> [--orm-from=<tex_hi/orm.png>]
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image

LO, HI = 512, 1024
ATLAS = 512
ATLAS_COLUMNS = 4
DETAIL = 128


def _load(path, mode):
    return np.asarray(Image.open(path).convert(mode))


def resize_channels(arr, size):
    """Resize an (h, w[, c]) uint8 array to size x size one channel at a time (LANCZOS, "L" mode)."""
    if arr.shape[0] == size:
        return arr
    if arr.ndim == 2:
        return np.asarray(Image.fromarray(arr, "L").resize((size, size), Image.LANCZOS))
    chans = [np.asarray(Image.fromarray(np.ascontiguousarray(arr[..., c]), "L").resize((size, size), Image.LANCZOS))
             for c in range(arr.shape[2])]
    return np.stack(chans, axis=-1)


def save(arr, path, mode):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(np.ascontiguousarray(arr), mode).save(path, optimize=True)


def orm_channels(bake_dir, orm_from=None):
    """(ao, rough, thick) at 1024 px: AO and thickness from the bake, or read back (R and B) from
    ``orm_from`` (the committed tex_hi/orm.png) when the expensive passes were skipped."""
    rough = _load(os.path.join(bake_dir, "rough.png"), "L")
    if orm_from:
        orm = _load(orm_from, "RGB")
        return orm[..., 0], rough, orm[..., 2]
    return _load(os.path.join(bake_dir, "ao.png"), "L"), rough, _load(os.path.join(bake_dir, "thick.png"), "L")


def pack_tiers(bake_dir, out_dir, orm_from=None):
    """Write tex/ and tex_hi/; returns the written paths (relative to out_dir)."""
    albedo = _load(os.path.join(bake_dir, "albedo.png"), "RGB")
    normal = _load(os.path.join(bake_dir, "normal.png"), "RGB")
    ao, rough, thick = orm_channels(bake_dir, orm_from)
    orm = np.stack([ao, rough, thick], axis=-1)
    m1 = _load(os.path.join(bake_dir, "masks_rgb.png"), "RGB")
    m2 = _load(os.path.join(bake_dir, "masks2_rgb.png"), "RGB")
    masks = np.dstack([m1, m2[..., :1]])
    out = {
        "tex/albedo.png": (resize_channels(albedo, LO), "RGB"),
        "tex/normal.png": (resize_channels(normal, LO), "RGB"),
        "tex/orm.png": (resize_channels(orm, LO), "RGB"),
        "tex/masks.png": (resize_channels(masks, LO), "RGBA"),
        "tex_hi/normal.png": (normal, "RGB"),
        "tex_hi/orm.png": (orm, "RGB"),
    }
    for rel, (arr, mode) in out.items():
        save(arr, os.path.join(out_dir, rel), mode)
    return sorted(out)


# --------------------------------------------------------------------------------------
# the hair atlas
# --------------------------------------------------------------------------------------
def make_atlas(path, seed=3):
    """Strands drawn as anti-aliased tapered lines, root at the top. Columns: 0 dense straight,
    1 dense wavy, 2 clumped, 3 sparse wispy (outer layer edges)."""
    rng = np.random.default_rng(seed)
    W = ATLAS // ATLAS_COLUMNS
    A = np.zeros((ATLAS, ATLAS), np.float32)
    R = np.zeros((ATLAS, ATLAS), np.float32)
    G = np.zeros((ATLAS, ATLAS), np.float32)
    yy = np.arange(ATLAS, dtype=np.float32)
    for c in range(ATLAS_COLUMNS):
        n = (120, 104, 80, 30)[c]
        for _i in range(n):
            x0 = c * W + 4 + rng.random() * (W - 8)
            if c == 2:      # clumps: strands gather towards 3 centres down the length
                cx = c * W + W * (0.2 + 0.3 * rng.integers(0, 3))
            length = ATLAS * (0.62 + 0.38 * rng.random()) if c != 3 else ATLAS * (0.5 + 0.5 * rng.random())
            amp = (0.0, 3.5, 1.5, 4.0)[c] * (0.5 + rng.random())
            wl = 60 + 80 * rng.random()
            ph = rng.random() * 6.28
            bright = 0.55 + 0.45 * rng.random()
            sid = rng.random()
            t = np.clip(yy / length, 0, 1)
            x = x0 + amp * np.sin(yy / wl * 6.28 + ph) * t
            if c == 2:
                x = x0 + (cx - x0) * 0.55 * t ** 1.5 + amp * np.sin(yy / wl * 6.28 + ph) * t
            x = np.clip(x, c * W + 1.5, (c + 1) * W - 2.5)
            width = (3.0 if c != 3 else 1.8) * (1.0 - 0.75 * t ** 1.3)
            alive = yy < length
            for k in range(-4, 5):
                px = np.floor(x).astype(int) + k
                d = np.abs(px + 0.5 - x)
                cov = np.clip(width * 0.5 + 0.5 - d, 0, 1) * alive
                rows = np.nonzero(cov > 0)[0]
                cols = np.clip(px[rows], 0, ATLAS - 1)
                old = A[rows, cols]
                new = 1 - (1 - old) * (1 - cov[rows])
                R[rows, cols] = np.where(cov[rows] >= old, bright, R[rows, cols])
                G[rows, cols] = np.where(cov[rows] >= old, sid, G[rows, cols])
                A[rows, cols] = new
    B = np.broadcast_to((yy / ATLAS)[:, None], (ATLAS, ATLAS))
    img = np.stack([R, G, B, A], axis=-1)
    save((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), path, "RGBA")


# --------------------------------------------------------------------------------------
# the cloth detail maps (tileable)
# --------------------------------------------------------------------------------------
def _fbm(size, rng, octaves=5, base=4, stretch=(1, 1)):
    """Tileable fractal noise in [0, 1]: random lattices band-limited by FFT zero padding
    (``stretch`` makes it anisotropic: fewer lattice cells along that axis)."""
    out = np.zeros((size, size))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        ny = min(size, max(2, base * (2 ** o) // stretch[0]))
        nx = min(size, max(2, base * (2 ** o) // stretch[1]))
        g = rng.random((ny, nx))
        G = np.fft.fft2(g)
        P = np.zeros((size, size), complex)
        hy, hx = ny // 2, nx // 2
        P[:hy, :hx] = G[:hy, :hx]
        P[:hy, -hx:] = G[:hy, -hx:]
        P[-hy:, :hx] = G[-hy:, :hx]
        P[-hy:, -hx:] = G[-hy:, -hx:]
        up = np.real(np.fft.ifft2(P))
        up = (up - up.min()) / (np.ptp(up) + 1e-9)
        out += amp * up
        tot += amp
        amp *= 0.5
    return out / tot


def _normal_rgba(height, albedo, strength):
    """A tileable tangent-space normal (OpenGL, Y up) from a height map, and the albedo in A."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * strength
    n = np.stack([-dx, dy, np.ones_like(height)], axis=-1)    # image rows go down: +Y is up the image
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    rgba = np.concatenate([n * 0.5 + 0.5, np.clip(albedo, 0, 1)[..., None]], axis=-1)
    return (rgba * 255 + 0.5).astype(np.uint8)


def make_weave(path, seed=41):
    """Plain weave: warp and weft threads over and under, 8 threads across the tile."""
    rng = np.random.default_rng(seed)
    s = DETAIL
    yy, xx = np.mgrid[0:s, 0:s] / s
    k = 8
    u, v = xx * k, yy * k
    fu, fv = u % 1.0, v % 1.0
    warp_up = ((np.floor(u) + np.floor(v)) % 2) == 0
    thread_u = np.sin(math.pi * fu) ** 0.6          # across a warp thread
    thread_v = np.sin(math.pi * fv) ** 0.6
    h = np.where(warp_up, 0.6 + 0.4 * thread_u * np.sin(math.pi * fv), 0.6 + 0.4 * thread_v * np.sin(math.pi * fu))
    fibre = _fbm(s, rng, 3, 16)
    h = h * 0.85 + 0.15 * fibre
    albedo = 0.62 + 0.18 * h + 0.06 * (_fbm(s, rng, 4, 4) - 0.5)
    save(_normal_rgba(h, albedo, 6.0), path, "RGBA")


def make_leather(path, seed=43):
    """Grained leather: soft pebbles and fine creases."""
    rng = np.random.default_rng(seed)
    s = DETAIL
    pebble = _fbm(s, rng, 3, 16)
    crease = np.abs(_fbm(s, rng, 4, 8) - 0.5) * 2.0
    h = 0.7 * pebble + 0.3 * np.clip(crease * 3.0, 0, 1)
    albedo = 0.66 + 0.14 * pebble - 0.08 * (1.0 - np.clip(crease * 4.0, 0, 1)) + 0.05 * (_fbm(s, rng, 3, 4) - 0.5)
    save(_normal_rgba(h, albedo, 3.0), path, "RGBA")


def make_fur(path, seed=47):
    """Fur: streaks along the tile's Y axis (the garment's UV v)."""
    rng = np.random.default_rng(seed)
    s = DETAIL
    streak = _fbm(s, rng, 4, 64, stretch=(16, 1))
    clump = _fbm(s, rng, 3, 8)
    h = 0.75 * streak + 0.25 * clump
    albedo = 0.55 + 0.35 * streak * (0.6 + 0.4 * clump)
    save(_normal_rgba(h, albedo, 5.0), path, "RGBA")


def pack_all(bake_dir, out_dir, orm_from=None):
    written = pack_tiers(bake_dir, out_dir, orm_from)
    make_atlas(os.path.join(out_dir, "hair_atlas.png"))
    make_weave(os.path.join(out_dir, "cloth_weave.png"))
    make_leather(os.path.join(out_dir, "cloth_leather.png"))
    make_fur(os.path.join(out_dir, "cloth_fur.png"))
    return written + ["cloth_fur.png", "cloth_leather.png", "cloth_weave.png", "hair_atlas.png"]


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    orm = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--orm-from=")), None)
    for rel in pack_all(args[0], args[1], orm):
        p = os.path.join(args[1], rel)
        print(rel, os.path.getsize(p))

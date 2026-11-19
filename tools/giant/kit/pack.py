"""The game's texture set (the step --pack): two tiers of the baked maps, the hair atlas and the
cloth detail maps (numpy + Pillow; no Blender).

  tex/albedo.png     RGB  base colour at the neutral tone (sRGB), 512 px
  tex/normal.png     RGB  tangent-space normal (OpenGL, Y up), 512 px
  tex/orm.png        RGB  R ambient occlusion, G roughness, B thickness (1 = thin), 512 px
  tex/masks.png      RGBA R stubble/beard area, G scalp, B brows, A lips, 512 px
  tex/curvature.png  L    the skin's curvature (P51: the subsurface term's lookup coordinate, 1/r over
                          CURV_MAX_PER_M), 256 px. Plan M11 §2.4 put it in masks.png's A; there, under the
                          import's VRAM compression, it spoiled the masks' RGB (the brows' tint drew blocks on
                          the forehead), so it has a map of its own
  tex/skin_lut.png   RGB  64 x 64 pre-integrated skin diffusion (P51; plan M11 decision 9) of a light wrapped
                          round the terminator per channel (Gate A, SKIN_WRAP): u = N.L * 0.5 + 0.5, v = curvature;
                          sRGB, imported lossless without mipmaps
  tex_hi/normal.png  RGB  the normal map at 1024 px (desktop; the Web too since the owner's 26 MiB answer)
  tex_hi/orm.png     RGB  the ORM map at 1024 px, AO and thickness at full precision: build_giant.py
                          --skip-bake reads them back from here
  hair_atlas.png     RGBA 512 px strands: A coverage, R strand brightness, G strand id (grey strands),
                          B root-to-tip (0 at the root); four columns: dense straight, dense wavy,
                          clumped, sparse wispy
  cloth_weave.png    RGBA 256 px tileable detail (P51; 128 px before): RGB a tangent-space normal (OpenGL,
  cloth_leather.png       Y up), A the albedo detail (0.75 = neutral): plain weave, grained leather, fur
  cloth_fur.png           and hammered metal (the giant_cloth shader's metal kind, used from P54 on)
  cloth_metal.png
  cloth_mail.png          P54: riveted mail (the mail hauberk) and overlapping scales (the scale coat), the same
  cloth_scale.png         layout: the gaps dark in A
  shell_strands.png  RGB  128 px tileable strand cells for the shell styles (P51): R a strand's section, G its
                          length, B its id; imported lossless with mipmaps

The skin's albedo is graded here (P51, ``SKIN_GRADE``): the baked albedo keeps the research's saturated tone,
and the lit chest in the creator's light read (208, 141, 106) against the approved studio render's
(198, 170, 157); the grade desaturates it in linear light (less on the lips). P51 took it to the studio render
(saturation 0.42, gain 1.2), which read near white and grey in the world's sun; Gate A eased it (0.8, no gain): the
chest draws (220, 160, 131) in the creator's light (tests/slow/test_skin_tone_render.gd) and the skin keeps its
colour in the world's (tests/slow/test_skin_world_render.gd).

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
DETAIL = 256
LUT = 64
# The skin's grade (P51; eased at Gate A from 0.42 / 0.75 / 1.2), in linear light: the saturation kept (on the lips
# ``sat_lips``) and a gain. The skin shader's TONE_RESAT_MAX is 1 / sat.
SKIN_GRADE = {"sat": 0.8, "sat_lips": 0.9, "gain": (1.0, 1.0, 1.0)}
# The curvature (1/m, human scale) that masks.png's A = 1 stands for: a radius of 3.8 mm (the ears' rims, the
# nostrils, the fingers' sides); flatter skin reads lower, the chest about 0.01-0.03.
CURV_MAX_PER_M = 260.0
CURV_BLUR = 5.0
CURV_SIZE = 256
# The profile's distances are divided by this: the giant's skin scatters as a human's would at two sevenths of his
# size (a look, not physics: at the true scale the band along the terminator is too thin to see).
SCATTER_SCALE = 3.5
CURV_STEP = 3
# The light each channel wraps round the terminator before the profile spreads it (Gate A): the giant's skin is
# nearly flat at the profile's scale (the chest's ring is 13-38 cm wide), so without it the lookup's flat rows are
# Lambert's hard terminator, which the normal map's grain and the self-shadow broke into ragged white patches in
# the world's sun. Like M10's light_model 2 wrap (0.36, 0.25, 0.20) but evener: the self-shadow cuts the wrapped light
# a little past the terminator, and M10's red reach drew a red band there. The profile softens the curved parts more.
SKIN_WRAP = (0.28, 0.24, 0.22)
# The skin's diffusion profile (d'Eon and Luebke's six Gaussians, variances in mm^2, weights R G B).
SKIN_PROFILE = (
    (0.0064, (0.233, 0.455, 0.649)),
    (0.0484, (0.100, 0.336, 0.344)),
    (0.187, (0.118, 0.198, 0.0)),
    (0.567, (0.113, 0.007, 0.007)),
    (1.99, (0.358, 0.004, 0.0)),
    (7.41, (0.078, 0.0, 0.0)),
)


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
    albedo = grade_albedo(albedo, m2[..., 0])
    masks = np.dstack([m1, m2[..., :1]])
    curv = curvature_map(bake_dir)
    out = {
        "tex/albedo.png": (resize_channels(albedo, LO), "RGB"),
        "tex/normal.png": (resize_channels(normal, LO), "RGB"),
        "tex/orm.png": (resize_channels(orm, LO), "RGB"),
        "tex/masks.png": (resize_channels(masks, LO), "RGBA"),
        "tex/curvature.png": (resize_channels(curv, CURV_SIZE), "L"),
        "tex_hi/normal.png": (normal, "RGB"),
        "tex_hi/orm.png": (orm, "RGB"),
    }
    for rel, (arr, mode) in out.items():
        save(arr, os.path.join(out_dir, rel), mode)
    return sorted(out)


def _to_linear(c):
    c = np.asarray(c, np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _to_srgb8(c):
    c = np.clip(c, 0.0, 1.0)
    s = np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1.0 / 2.4) - 0.055)
    return (s * 255.0 + 0.5).astype(np.uint8)


def grade_albedo(albedo, lips):
    """The skin's albedo (sRGB uint8, h x w x 3) graded by SKIN_GRADE in linear light: towards its own
    luminance (less where ``lips``, 0-255, marks the lips) and lifted by the gain."""
    lin = _to_linear(albedo)
    lum = lin @ np.array([0.2126, 0.7152, 0.0722])
    sat = SKIN_GRADE["sat"] + (SKIN_GRADE["sat_lips"] - SKIN_GRADE["sat"]) * (lips.astype(np.float64) / 255.0)
    out = (lum[..., None] + (lin - lum[..., None]) * sat[..., None]) * np.asarray(SKIN_GRADE["gain"])
    return _to_srgb8(out)


def curvature_map(bake_dir):
    """The skin's mean curvature per texel (uint8, 1024 px): the change of the rest normal over the change of the
    rest position between a texel's neighbours (human-scale metres), the two directions averaged, over CURV_MAX_PER_M, blurred and grown into the
    gutters so a filtered read near a seam finds the skin's own value."""
    from scipy import ndimage
    P = np.load(os.path.join(bake_dir, "restpos.npy")).astype(np.float64)
    N = np.load(os.path.join(bake_dir, "restnrm.npy")).astype(np.float64) * 2.0 - 1.0
    valid = np.abs(P).sum(axis=-1) > 0.0
    # the rest maps are smoothed first (masked) and differenced over CURV_STEP texels each way: per texel the
    # interpolated normal is noisy against the head's dense texels
    wv = ndimage.gaussian_filter(valid.astype(np.float64), CURV_BLUR)
    P = np.stack([ndimage.gaussian_filter(P[..., c] * valid, CURV_BLUR) for c in range(3)], axis=-1) / np.maximum(wv, 1e-6)[..., None]
    N = np.stack([ndimage.gaussian_filter(N[..., c] * valid, CURV_BLUR) for c in range(3)], axis=-1) / np.maximum(wv, 1e-6)[..., None]
    N /= np.maximum(np.linalg.norm(N, axis=-1, keepdims=True), 1e-6)
    inner = ndimage.binary_erosion(valid, iterations=CURV_STEP + 3)   # an island's edge reads no false bend
    k = np.zeros(P.shape[:2])
    cnt = np.zeros(P.shape[:2])
    for axis in (0, 1):
        dP = np.linalg.norm(np.roll(P, -CURV_STEP, axis) - np.roll(P, CURV_STEP, axis), axis=-1)
        dN = np.linalg.norm(np.roll(N, -CURV_STEP, axis) - np.roll(N, CURV_STEP, axis), axis=-1)
        ok = inner & np.roll(inner, -CURV_STEP, axis) & np.roll(inner, CURV_STEP, axis) & (dP > 1e-6) & (dP < 0.05)
        k += np.where(ok, dN / np.maximum(dP, 1e-6), 0.0)
        cnt += ok
    have = cnt > 0
    k = np.where(have, k / np.maximum(cnt, 1), 0.0)
    w = ndimage.gaussian_filter(have.astype(np.float64), 2.0)
    k = ndimage.gaussian_filter(k, 2.0) / np.maximum(w, 1e-6)
    _, (iy, ix) = ndimage.distance_transform_edt(~have, return_indices=True)
    k = k[iy, ix]
    return (np.clip(k / CURV_MAX_PER_M, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def make_skin_lut(path):
    """The pre-integrated skin lookup (Penner's method): for curvature 1/r and the angle to the light, the
    light a ring of radius r gathers through the profile, normalized; sRGB. The light on the ring is wrapped per
    channel by SKIN_WRAP (Gate A), so the flattest rows are a soft wrap, not Lambert."""
    th = np.arccos(np.clip(2.0 * (np.arange(LUT) + 0.5) / LUT - 1.0, -1.0, 1.0))      # u: N.L * 0.5 + 0.5
    x = np.linspace(-np.pi, np.pi, 721)[None, :]
    out = np.zeros((LUT, LUT, 3))
    for j in range(LUT):
        k = max((j + 0.5) / LUT * CURV_MAX_PER_M, 1e-3)
        r_mm = 1000.0 / k
        d2 = (2.0 * r_mm * np.sin(x / 2.0) / SCATTER_SCALE) ** 2
        prof = np.zeros((x.shape[1], 3))
        for v, wrgb in SKIN_PROFILE:
            g = np.exp(-d2 / (2.0 * v)) / (2.0 * np.pi * v)
            prof += g[0][:, None] * np.asarray(wrgb)[None, :]
        c = np.cos(th[:, None] + x)
        for ch in range(3):
            w = SKIN_WRAP[ch]
            lit = np.clip((c + w) / (1.0 + w), 0.0, None)                           # (LUT, samples)
            out[j, :, ch] = (lit @ prof[:, ch]) / max(prof[:, ch].sum(), 1e-12)
    # row 0 of the image (UV v = 0 in the game) is the flattest
    save(_to_srgb8(out), path, "RGB")


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
            # Strands end anywhere in the card's lower two thirds, so its tip thins out strand by strand,
            # and they thin towards its sides (the look pass, P46: a card must not show its outline).
            if rng.random() < 0.5:
                x0 = c * W + W * (0.5 + 0.42 * (rng.random() - rng.random()))
            length = ATLAS * (0.34 + 0.66 * rng.random() ** 0.8) if c != 3 else ATLAS * (0.4 + 0.6 * rng.random())
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
    # Empty texels take the brightness and the id of the nearest strand, so the filtered and mipmapped
    # atlas never blends a strand's id towards zero at its edge (that drew grey fringes; P46).
    from scipy import ndimage
    _, (iy, ix) = ndimage.distance_transform_edt(A <= 0.0, return_indices=True)
    R = R[iy, ix]
    G = G[iy, ix]
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


STRANDS = 128
STRAND_CELLS = 32


def make_strands(path, seed=59):
    """The shells' strands (P51): a jittered grid of STRAND_CELLS x STRAND_CELLS strands across a tileable tile,
    R the strand's section (1 at its axis, 0 at its edge: a layer keeps it while R is above the layer's
    height, so it tapers), G the strand's own length (0.55-1 of the style's), B its id (grey strands)."""
    rng = np.random.default_rng(seed)
    s, c = STRANDS, STRAND_CELLS
    cell = s / c
    cx = (np.arange(c)[None, :] + 0.2 + 0.6 * rng.random((c, c))) * cell
    cy = (np.arange(c)[:, None] + 0.2 + 0.6 * rng.random((c, c))) * cell
    length = 0.55 + 0.45 * rng.random((c, c))
    ident = rng.random((c, c))
    radius = cell * (0.55 + 0.25 * rng.random((c, c)))
    yy, xx = np.mgrid[0:s, 0:s] + 0.5
    R = np.zeros((s, s))
    G = np.zeros((s, s))
    B = np.zeros((s, s))
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            for j in range(c):
                for i in range(c):
                    px = cx[j, i] + dx * s
                    py = cy[j, i] + dy * s
                    d = np.hypot(xx - px, yy - py) / radius[j, i]
                    v = np.clip(1.0 - d, 0.0, 1.0)
                    win = v > R
                    R = np.where(win, v, R)
                    G = np.where(win, length[j, i], G)
                    B = np.where(win, ident[j, i], B)
    save((np.stack([R, G, B], axis=-1) * 255 + 0.5).astype(np.uint8), path, "RGB")


def make_metal(path, seed=53):
    """Hammered metal (P51, the metal kind): shallow overlapping dents and fine scratches."""
    rng = np.random.default_rng(seed)
    s = DETAIL
    yy, xx = np.mgrid[0:s, 0:s] / s
    h = np.zeros((s, s))
    for _ in range(90):
        cx, cy, r = rng.random(), rng.random(), 0.03 + 0.05 * rng.random()
        dx = (xx - cx + 0.5) % 1.0 - 0.5
        dy = (yy - cy + 0.5) % 1.0 - 0.5
        h -= np.clip(1.0 - (dx * dx + dy * dy) / (r * r), 0.0, None) ** 2 * 0.5
    h = (h - h.min()) / (np.ptp(h) + 1e-9)
    scratch = _fbm(s, rng, 4, 64, stretch=(1, 32))
    h = 0.85 * h + 0.15 * scratch
    albedo = 0.68 + 0.12 * h + 0.06 * (_fbm(s, rng, 3, 4) - 0.5)
    save(_normal_rgba(h, albedo, 2.5), path, "RGBA")


def make_mail(path, seed=61):
    """Riveted mail (P54, the mail hauberk): rows of interlinked rings, 3 x 3 a tile, each row offset by half a
    ring and overlapping the next; the gaps between the rings dark (the albedo's A low), the rings' wire raised."""
    rng = np.random.default_rng(seed)
    s = DETAIL
    yy, xx = (np.mgrid[0:s, 0:s] + 0.5) / s
    k = 3
    h = np.zeros((s, s))
    wire = np.zeros((s, s))
    for row in range(-1, k + 1):
        for col in range(-1, k + 1):
            cx = (col + 0.5 * (row % 2) + 0.5) / k
            cy = (row + 0.5) / k
            dx = (xx - cx + 0.5) % 1.0 - 0.5
            dy = ((yy - cy + 0.5) % 1.0 - 0.5) * 1.15
            r = np.sqrt(dx * dx + dy * dy) * k
            ring = np.clip(1.0 - np.abs(r - 0.42) / 0.13, 0.0, 1.0)
            # each ring lies a little over the one above it (the overlap reads as rows)
            tilt = 0.75 + 0.25 * np.clip(0.5 + dy * k, 0.0, 1.0)
            v = np.sin(ring * math.pi / 2.0) * tilt
            win = v > wire
            wire = np.where(win, v, wire)
    h = wire
    grit = _fbm(s, rng, 3, 32)
    albedo = 0.18 + 0.62 * np.clip(wire * 1.4, 0.0, 1.0) + 0.06 * (grit - 0.5)
    save(_normal_rgba(h, albedo, 9.0), path, "RGBA")


def make_scale(path, seed=67):
    """Scale armour (P54, the scale coat): rounded scales 2 x 2 a tile in rows offset by half a scale, each
    overlapping the one below; the scale rises toward its free lower edge and the gaps between scales are dark."""
    rng = np.random.default_rng(seed)
    s = DETAIL
    yy, xx = (np.mgrid[0:s, 0:s] + 0.5) / s
    k = 2
    h = np.full((s, s), -1.0)
    edge = np.zeros((s, s))
    for row in range(k + 1, -2, -1):          # lower rows first: an upper scale lies over the one below it
        for col in range(-1, k + 1):
            cx = (col + 0.5 * (row % 2) + 0.5) / k
            cy = (row + 0.35) / k
            dx = ((xx - cx + 0.5) % 1.0 - 0.5) * k
            dy = ((yy - cy + 0.5) % 1.0 - 0.5) * k
            inside = (np.abs(dx) < 0.48) & (dy > -0.62) & (dx * dx + np.maximum(dy, 0.0) ** 2 * 1.4 < 0.23)
            rise = 0.4 + 0.6 * np.clip((dy + 0.62) / 1.1, 0.0, 1.0)
            dome = rise * (1.0 - 0.6 * (dx / 0.48) ** 2)
            win = inside & (dome > h - 0.15)
            h = np.where(win, dome, h)
            rim = np.clip(1.0 - (0.23 - dx * dx - np.maximum(dy, 0.0) ** 2 * 1.4) / 0.04, 0.0, 1.0)
            edge = np.where(win, rim, edge)
    h = np.clip(h, 0.0, None)
    grit = _fbm(s, rng, 3, 32)
    albedo = 0.22 + 0.55 * np.clip(h * 1.3, 0.0, 1.0) - 0.2 * edge + 0.06 * (grit - 0.5)
    save(_normal_rgba(h, albedo, 5.0), path, "RGBA")


def pack_all(bake_dir, out_dir, orm_from=None):
    written = pack_tiers(bake_dir, out_dir, orm_from)
    make_skin_lut(os.path.join(out_dir, "tex", "skin_lut.png"))
    make_atlas(os.path.join(out_dir, "hair_atlas.png"))
    make_weave(os.path.join(out_dir, "cloth_weave.png"))
    make_leather(os.path.join(out_dir, "cloth_leather.png"))
    make_fur(os.path.join(out_dir, "cloth_fur.png"))
    make_metal(os.path.join(out_dir, "cloth_metal.png"))
    make_mail(os.path.join(out_dir, "cloth_mail.png"))
    make_scale(os.path.join(out_dir, "cloth_scale.png"))
    make_strands(os.path.join(out_dir, "shell_strands.png"))
    return written + ["cloth_fur.png", "cloth_leather.png", "cloth_mail.png", "cloth_metal.png", "cloth_scale.png",
                      "cloth_weave.png", "hair_atlas.png",
                      "shell_strands.png", "tex/skin_lut.png"]


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    orm = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--orm-from=")), None)
    for rel in pack_all(args[0], args[1], orm):
        p = os.path.join(args[1], rel)
        print(rel, os.path.getsize(p))

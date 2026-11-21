"""The quadruped kit (plan M11 §2.8, decision 17; P61): a four-legged body from the project's own code.

The body is a signed distance field: ellipsoids and round cones (tapered capsules) placed on the animal's
anatomical landmarks - the barrel, the chest, the withers, the shoulder blades and the upper arms, the croup and
the hindquarters' muscles, the arched neck, the head from its cranium, jowls, face and muzzle, the ears, and per leg
the forearm or gaskin, the knee or hock with its point, the cannon with the tendons behind it, the fetlock, the
pastern and the hoof - joined by a smooth union so that the joints read as bulges and the muscles run into one
another. The field is polygonized by marching tetrahedra on a regular grid (closed and manifold by construction),
smoothed (Taubin, volume kept), decimated by Blender's collapse to the animal's budget and unwrapped by the
script. Every number is the project's own (a riding horse of 1.58 m at the withers); no outside mesh is read.

Coordinates here: x the animal's left, u forward, z up, metres, the ground at z = 0; ``to_blender`` maps (x, u, z)
to Blender's (x, -u, z) so the exported glTF faces +Z as the giant and the people do.

The field, the polygonizer, the skeleton, the weights and the poses are numpy only; the build at the end of the module
(``python quadruped.py <out dir> <work dir>``, run by build_people.py --horse) adds the mane, the forelock and the
tail as cards, the tack (a saddle from the same field's offset, the headstall, the reins, the stirrups, a housing in
the faction's colour), Blender's collapse, unwrap, tangents and glTF export, and the bake of one atlas (albedo with
the strands' alpha, normal from the dense field's normals, and the ORM map whose B channel is the person shader's
palette band: the coat takes the coat's colour, the points and the hair the mane's, the housing the faction's).
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np  # noqa: E402

# ---- the SDF primitives --------------------------------------------------------------------------------------


def _unit(v):
    v = np.asarray(v, np.float64)
    return v / np.linalg.norm(v)


def frame_from(axis, up=(0.0, 0.0, 1.0)):
    """An orthonormal frame (3, 3) whose second row is ``axis`` (the long axis, u-like), first the lateral."""
    a = _unit(axis)
    up = np.asarray(up, np.float64)
    lat = np.cross(a, up)
    if np.linalg.norm(lat) < 1e-6:
        lat = np.cross(a, np.array([0.0, 1.0, 0.0]))
    lat = _unit(lat)
    third = np.cross(lat, a)
    return np.stack([lat, a, third])


def sd_ellipsoid(P, c, r, frame=None):
    """An ellipsoid's approximate distance (iq's bound): centre c, semi-axes r along the frame's rows (x, u, z)."""
    Q = P - np.asarray(c, np.float64)
    if frame is not None:
        Q = Q @ np.asarray(frame).T
    r = np.asarray(r, np.float64)
    k0 = np.linalg.norm(Q / r, axis=1)
    k1 = np.linalg.norm(Q / (r * r), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_round_cone(P, a, b, ra, rb, squash=1.0):
    """A round cone (iq): spheres of radius ra at a and rb at b and the cone tangent to both. ``squash`` scales the
    field's lateral (x) axis: below 1 the section is an ellipse narrower than it is deep."""
    a = np.asarray(a, np.float64)
    b = np.asarray(b, np.float64)
    s = np.array([1.0 / squash, 1.0, 1.0])
    Q = (P - a) * s
    ba = (b - a) * s
    l2 = float(ba @ ba)
    rr = ra - rb
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    y = Q @ ba
    z = y - l2
    xv = Q * l2 - y[:, None] * ba
    x2 = np.einsum("ij,ij->i", xv, xv)
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    d = np.where(np.sign(z) * a2 * z2 > k, np.sqrt(x2 + z2) * il2 - rb,
                 np.where(np.sign(y) * a2 * y2 < k, np.sqrt(x2 + y2) * il2 - ra,
                          (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - ra))
    return d * min(squash, 1.0)


def sd_plane(P, point, normal):
    """Signed distance to a plane: positive on the normal's side."""
    return (P - np.asarray(point, np.float64)) @ _unit(normal)


def smin(a, b, k):
    """Polynomial smooth minimum (the smooth union), blending within k."""
    if k <= 0.0:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a, b, k):
    return -smin(-a, -b, k)


# ---- the horse's anatomy --------------------------------------------------------------------------------------
# Landmarks (x, u, z), metres; a riding horse of 1.58 m at the withers, body length (point of shoulder to point of
# buttock) about 1.65 m, the chest's floor 0.80 m over the ground (the leg as long as the body is deep).
HORSE = dict(
    withers_m=1.58,
    # the joints of the legs (left side; the right mirrors x)
    shoulder=(0.150, 0.73, 1.12),       # the shoulder joint (point of shoulder)
    elbow=(0.160, 0.52, 0.95),
    knee=(0.148, 0.53, 0.475),          # the carpus
    fore_fetlock=(0.145, 0.52, 0.200),
    fore_coronet=(0.145, 0.565, 0.090),
    hip=(0.165, -0.60, 1.17),           # the hip joint
    stifle=(0.190, -0.40, 0.92),
    hock=(0.155, -0.73, 0.555),
    hind_fetlock=(0.145, -0.715, 0.215),
    hind_coronet=(0.145, -0.670, 0.095),
    # the spine and the head
    pelvis=(0.0, -0.52, 1.36),
    loin=(0.0, -0.15, 1.40),
    back=(0.0, 0.25, 1.42),
    withers=(0.0, 0.50, 1.40),
    neck_top=(0.0, 1.03, 1.79),         # the throat's height, the neck bone's end
    poll=(0.0, 1.15, 1.94),
    muzzle=(0.0, 1.51, 1.47),
    jaw_joint=(0.0, 1.17, 1.83),
    chin=(0.0, 1.50, 1.45),
    tail_root=(0.0, -0.86, 1.42),
    tail_mid=(0.0, -0.95, 1.20),
    tail_end=(0.0, -0.99, 0.95),
)


def _mirror(p):
    return (-p[0], p[1], p[2])


def _lerp(a, b, t):
    a = np.asarray(a, np.float64)
    return a + (np.asarray(b, np.float64) - a) * t


class Field:
    """The smooth union of the parts, accumulated in order (each part's own blend radius)."""

    def __init__(self, P):
        self.P = P
        self.d = np.full(len(P), 1e9)

    def add(self, d, k):
        self.d = smin(self.d, d, k)

    def cut(self, d, k):
        self.d = smax(self.d, -d, k)


def horse_leg(P, side, h=HORSE):
    """One side's two legs (the left's landmarks mirrored for the right): a field of the legs below the body."""
    m = (lambda p: p) if side > 0 else _mirror
    out = Field(P)
    sh, el, kn, ff, fc = (np.array(m(h[k])) for k in ("shoulder", "elbow", "knee", "fore_fetlock", "fore_coronet"))
    # ---- the foreleg
    # the forearm: broad and muscular at the elbow, tapering to the knee; its muscles bulge at the front-top
    out.add(sd_round_cone(P, el + np.array([0, 0.005, -0.03]), kn + np.array([0, 0.0, 0.055]), 0.088, 0.044, 0.85), 0.0)
    out.add(sd_ellipsoid(P, el + np.array([0, 0.035, -0.17]), (0.062, 0.066, 0.16)), 0.05)
    out.add(sd_ellipsoid(P, (el[0] - 0.012 * np.sign(el[0]), el[1] + 0.012, el[2] - 0.13), (0.050, 0.06, 0.12)), 0.04)
    # the point of the elbow (olecranon) behind the forearm's top
    out.add(sd_ellipsoid(P, (el[0], el[1] - 0.075, el[2] + 0.0), (0.050, 0.055, 0.060)), 0.05)
    # the knee: a flat-fronted block, wider than the cannon, the accessory carpal bone behind it
    out.add(sd_ellipsoid(P, kn, (0.047, 0.047, 0.055)), 0.035)
    out.add(sd_ellipsoid(P, kn + np.array([0, -0.045, 0.015]), (0.020, 0.024, 0.030)), 0.02)
    # the cannon: flat-sided, the flexor tendons a ridge behind the bone
    out.add(sd_round_cone(P, kn + np.array([0, 0.008, -0.03]), ff + np.array([0, 0.012, 0.03]), 0.032, 0.030, 0.82), 0.03)
    out.add(sd_round_cone(P, kn + np.array([0, -0.030, -0.05]), ff + np.array([0, -0.022, 0.02]), 0.022, 0.024, 0.75), 0.025)
    # the fetlock: a rounded joint, deeper behind (the sesamoids), the ergot under it
    out.add(sd_ellipsoid(P, ff + np.array([0, -0.008, 0.0]), (0.040, 0.046, 0.040)), 0.03)
    out.add(sd_ellipsoid(P, ff + np.array([0, -0.035, -0.022]), (0.026, 0.026, 0.026)), 0.02)
    # the pastern: sloping forward-down to the coronet
    out.add(sd_round_cone(P, ff + np.array([0, 0.004, -0.02]), fc + np.array([0, -0.005, 0.01]), 0.031, 0.034, 0.95), 0.025)
    out.add(hoof(P, fc), 0.012)
    # ---- the hind leg
    hp, st, hk, hf, hc = (np.array(m(h[k])) for k in ("hip", "stifle", "hock", "hind_fetlock", "hind_coronet"))
    # the gaskin (second thigh): muscular under the stifle, narrowing to the hock; the hamstring to the point of hock
    out.add(sd_round_cone(P, st + np.array([-0.025 * np.sign(st[0]), -0.04, -0.03]), hk + np.array([0, 0.005, 0.07]),
                          0.105, 0.048, 0.82), 0.0)
    gk = _lerp(st, hk, 0.40) + np.array([-0.018 * np.sign(st[0]), -0.045, 0.0])
    out.add(sd_ellipsoid(P, gk, (0.062, 0.092, 0.14), frame_from(hk - st)[[0, 2, 1]]), 0.05)
    poh = hk + np.array([0, -0.065, 0.055])                 # the point of the hock (calcaneus)
    out.add(sd_round_cone(P, gk + np.array([0, -0.05, 0.03]), poh, 0.030, 0.026, 0.70), 0.04)
    out.add(sd_ellipsoid(P, poh, (0.024, 0.030, 0.030)), 0.025)
    # the hock: a broad flat joint
    out.add(sd_ellipsoid(P, hk, (0.048, 0.058, 0.060)), 0.04)
    # the hind cannon (longer than the fore), its tendons, the fetlock, the pastern, the hoof
    out.add(sd_round_cone(P, hk + np.array([0, 0.006, -0.035]), hf + np.array([0, 0.012, 0.03]), 0.033, 0.030, 0.82), 0.03)
    out.add(sd_round_cone(P, hk + np.array([0, -0.040, -0.04]), hf + np.array([0, -0.022, 0.02]), 0.022, 0.024, 0.75), 0.025)
    out.add(sd_ellipsoid(P, hf + np.array([0, -0.008, 0.0]), (0.040, 0.046, 0.040)), 0.03)
    out.add(sd_ellipsoid(P, hf + np.array([0, -0.035, -0.022]), (0.026, 0.026, 0.026)), 0.02)
    out.add(sd_round_cone(P, hf + np.array([0, 0.004, -0.02]), hc + np.array([0, -0.005, 0.01]), 0.031, 0.034, 0.95), 0.025)
    out.add(hoof(P, hc), 0.012)
    return out.d


def hoof(P, coronet):
    """A hoof under its coronet: a cone widening to the ground, sheared forward (the front wall at about 55 degrees),
    the coronet band sloping down to the heels, the sole on the ground."""
    c = np.asarray(coronet, np.float64)
    z = P[:, 2]
    t = np.clip(z / max(c[2], 1e-6), 0.0, 1.0)             # 0 at the ground, 1 at the coronet
    cu = c[1] + 0.030 * (1.0 - t)                            # the centre runs forward toward the ground
    rx = 0.050 + 0.017 * (1.0 - t)                           # half width
    ru = 0.054 + 0.022 * (1.0 - t)                           # half length
    q = np.stack([(P[:, 0] - c[0]) / rx, (P[:, 1] - cu) / ru], axis=1)
    d_side = (np.linalg.norm(q, axis=1) - 1.0) * np.minimum(rx, ru)
    # the top: the coronet band, higher at the toe than at the heels
    top = c[2] + 0.010 + 0.45 * (P[:, 1] - c[1])
    d_top = z - top
    d_bottom = -z
    return smax(smax(d_side, d_top, 0.012), d_bottom, 0.004)


def horse_head(P, h=HORSE):
    out = Field(P)
    poll, muz = np.array(h["poll"]), np.array(h["muzzle"])
    axis = muz - poll
    L = float(np.linalg.norm(axis))
    fr = frame_from(axis)              # rows: lateral, along the face (down-forward), the face's front (up-forward)
    front = fr[2]
    # the cranium between the ears and the eyes
    out.add(sd_ellipsoid(P, poll + axis * 0.17 + front * 0.005, (0.098, 0.15, 0.105), fr), 0.0)
    # the jowls (the cheeks over the lower jaw's broad end), paired, behind the face's axis
    for s in (1.0, -1.0):
        out.add(sd_ellipsoid(P, poll + axis * 0.30 - front * 0.10 + np.array([0.048 * s, 0, 0]), (0.068, 0.125, 0.12), fr), 0.06)
    # the face: the nasal bone, flat fronted, narrowing toward the muzzle
    out.add(sd_round_cone(P, poll + axis * 0.30 + front * 0.01, poll + axis * 0.80 - front * 0.005, 0.090, 0.060, 0.92), 0.06)
    # the lower jaw's line under the face, narrower toward the chin
    out.add(sd_round_cone(P, poll + axis * 0.38 - front * 0.12, poll + axis * 0.88 - front * 0.07, 0.060, 0.042, 0.80), 0.06)
    # the muzzle: rounder and a little broader than the face above it, the lips and the chin under
    out.add(sd_ellipsoid(P, poll + axis * 0.93 - front * 0.025, (0.062, 0.075, 0.072), fr), 0.045)
    out.add(sd_ellipsoid(P, poll + axis * 0.96 - front * 0.085, (0.045, 0.050, 0.035), fr), 0.03)
    # the nostrils: two hollows at the muzzle's front-sides
    for s in (1.0, -1.0):
        nos = poll + axis * 0.965 + front * 0.020 + np.array([0.040 * s, 0, 0])
        out.cut(sd_ellipsoid(P, nos, (0.014, 0.030, 0.012), fr), 0.012)
    # the eyes: a bony orbit and the eyeball at the cranium's sides
    for s in (1.0, -1.0):
        orb = poll + axis * 0.27 + front * 0.03 + np.array([0.082 * s, 0, 0])
        out.add(sd_ellipsoid(P, orb, (0.030, 0.034, 0.028), fr), 0.03)
    # the ears: upright, a little forward, pointed
    for s in (1.0, -1.0):
        base = poll + np.array([0.052 * s, -0.015, 0.03])
        tip = poll + np.array([0.082 * s, 0.020, 0.185])
        out.add(sd_round_cone(P, base, tip, 0.033, 0.006, 0.75), 0.03)
    return out.d


def eye_centres(h=HORSE):
    poll, muz = np.array(h["poll"]), np.array(h["muzzle"])
    axis = muz - poll
    front = frame_from(axis)[2]
    return [poll + axis * 0.27 + front * 0.03 + np.array([0.105 * s, 0, 0]) for s in (1.0, -1.0)]


def horse_trunk(P, h=HORSE, limbs=True):
    """The trunk, the neck and (``limbs``) the upper legs' muscles: the shoulder blades, the upper arms, the thighs and
    the buttocks (the parts the legs grow out of; without them, the core the skinning keeps on the spine)."""
    out = Field(P)
    # the barrel (the rib cage) and the belly under it
    out.add(sd_ellipsoid(P, (0, 0.03, 1.17), (0.28, 0.60, 0.35)), 0.0)
    out.add(sd_ellipsoid(P, (0, -0.10, 1.10), (0.25, 0.40, 0.21)), 0.10)
    # the chest between the forelegs, the breast muscles in front
    out.add(sd_ellipsoid(P, (0, 0.45, 1.16), (0.17, 0.30, 0.28)), 0.10)
    for s in (1.0, -1.0):
        out.add(sd_ellipsoid(P, (0.085 * s, 0.66, 1.10), (0.09, 0.11, 0.15)), 0.06)
    # the withers: the spine's high point over the shoulder blades
    out.add(sd_ellipsoid(P, (0, 0.42, 1.48), (0.075, 0.25, 0.12)), 0.08)
    # the back and the loin's top line
    out.add(sd_ellipsoid(P, (0, -0.10, 1.43), (0.17, 0.48, 0.10)), 0.10)
    # the croup and the hindquarters' muscles: the rump in two halves, the thigh and the buttock behind
    out.add(sd_ellipsoid(P, (0, -0.50, 1.43), (0.16, 0.36, 0.13)), 0.08)
    for s in (1.0, -1.0):
        out.add(sd_ellipsoid(P, (0.115 * s, -0.53, 1.26), (0.165, 0.34, 0.27)), 0.08)
        # the point of the hip (tuber coxae) under the skin
        out.add(sd_ellipsoid(P, (0.17 * s, -0.37, 1.40), (0.04, 0.05, 0.04)), 0.10)
        if not limbs:
            continue
        # the thigh down to the stifle
        out.add(sd_round_cone(P, (0.145 * s, -0.55, 1.20), (0.18 * s, -0.43, 0.94), 0.19, 0.105, 0.80), 0.08)
        # the buttock's back (the hamstrings) down to the gaskin
        out.add(sd_round_cone(P, (0.11 * s, -0.78, 1.26), (0.13 * s, -0.66, 0.84), 0.13, 0.07, 0.85), 0.08)
        # the shoulder blade from the withers down to the point of shoulder, the upper arm back to the elbow
        sh, el = np.array(h["shoulder"]) * [s, 1, 1], np.array(h["elbow"]) * [s, 1, 1]
        out.add(sd_round_cone(P, (0.10 * s, 0.42, 1.40), sh + np.array([-0.01 * s, -0.01, 0.0]), 0.075, 0.092, 0.68), 0.08)
        out.add(sd_round_cone(P, sh + np.array([-0.01 * s, -0.02, 0.0]), el + np.array([0, -0.02, 0.04]), 0.085, 0.075, 0.66), 0.07)
    # the neck: an arch from the withers and the chest to the throat and the poll, deep and narrow
    base_lo, base_hi = np.array((0, 0.77, 1.15)), np.array((0, 0.52, 1.45))
    thr, pol = np.array((0, 1.03, 1.68)), np.array(h["poll"])
    for t in np.linspace(0.0, 1.0, 7):
        lo = _lerp(base_lo, thr, t)
        hi = _lerp(base_hi, pol + np.array([0, -0.10, -0.06]), t)
        # the crest arches over the straight line between the withers and the poll
        hi = hi + np.array([0, -0.03, 0.06]) * math.sin(math.pi * t)
        c = (lo + hi) * 0.5
        depth = float(np.linalg.norm(hi - lo)) * 0.5
        width = 0.205 - 0.12 * t ** 1.2
        out.add(sd_ellipsoid(P, c, (width, 0.10 + 0.02 * (1 - t), depth), frame_from(hi - lo)[[0, 2, 1]]), 0.12)
    return out.d


def horse_sdf(P, h=HORSE):
    d = horse_trunk(P, h)
    d = smin(d, horse_head(P, h), 0.07)
    for side in (1, -1):
        d = smin(d, horse_leg(P, side, h), 0.05)
    return smin(d, horse_dock(P, h), 0.05)


HORSE_BOX = ((-0.36, 0.36), (-1.02, 1.70), (-0.004, 2.22))     # x, u, z bounds of the field's grid


# ---- polygonizing: marching tetrahedra (a Kuhn split of each cube: conforming, so closed and manifold) ------------
_CUBE = np.array([(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0), (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)])
_TETS = np.array([(0, 1, 2, 6), (0, 2, 3, 6), (0, 3, 7, 6), (0, 7, 4, 6), (0, 4, 5, 6), (0, 5, 1, 6)])


def _tet_table():
    """For each inside-mask of a tet's 4 corners: its triangles, as triples of corner pairs (edges)."""
    table = {}
    for mask in range(1, 15):
        ins = [i for i in range(4) if mask >> i & 1]
        out = [i for i in range(4) if not mask >> i & 1]
        if len(ins) == 1 or len(out) == 1:
            a = ins[0] if len(ins) == 1 else out[0]
            others = [i for i in range(4) if i != a]
            table[mask] = [((a, others[0]), (a, others[1]), (a, others[2]))]
        else:
            a, b = ins
            c, d = out
            table[mask] = [((a, c), (a, d), (b, d)), ((a, c), (b, d), (b, c))]
    return table


_TABLE = _tet_table()


def grid_points(box, step):
    axes = [np.arange(lo, hi + step * 0.5, step) for lo, hi in box]
    return axes


def polygonize(fn, box, step, chunk=400000):
    """(V, T) of the zero set of fn (negative inside) over a grid of ``step``: triangles wound outward."""
    ax = grid_points(box, step)
    nx, ny, nz = (len(a) for a in ax)
    X, Y, Z = np.meshgrid(*ax, indexing="ij")
    P = np.stack([X.ravel(), Y.ravel(), Z.ravel()], axis=1)
    f = np.empty(len(P))
    for s in range(0, len(P), chunk):
        f[s:s + chunk] = fn(P[s:s + chunk])
    f[f == 0.0] = 1e-9
    F = f.reshape(nx, ny, nz)
    # the active cubes: their corners' signs differ
    c = [F[i:nx - 1 + i, j:ny - 1 + j, k:nz - 1 + k] for i, j, k in _CUBE]
    lo = np.minimum.reduce(c)
    hi = np.maximum.reduce(c)
    ci, cj, ck = np.nonzero((lo < 0) & (hi > 0))
    base = (ci * ny + cj) * nz + ck
    off = np.array([(i * ny + j) * nz + k for i, j, k in _CUBE])
    G = base[:, None] + off[None, :]                                  # (m, 8) global corner ids
    tris_edges = []
    for tet in _TETS:
        g = G[:, tet]                                                 # (m, 4)
        val = f[g]
        mask = ((val < 0) * (1 << np.arange(4))).sum(axis=1)
        for mk, tris in _TABLE.items():
            sel = mask == mk
            if not sel.any():
                continue
            gs = g[sel]
            for tri in tris:
                tris_edges.append(np.stack([np.stack([gs[:, e[0]], gs[:, e[1]]], axis=1) for e in tri], axis=1))
    E = np.concatenate(tris_edges)                                    # (t, 3, 2) corner ids
    a = np.minimum(E[..., 0], E[..., 1])
    b = np.maximum(E[..., 0], E[..., 1])
    key = a * len(P) + b
    uniq, inv = np.unique(key.ravel(), return_inverse=True)
    ea, eb = uniq // len(P), uniq % len(P)
    fa, fb = f[ea], f[eb]
    t = fa / (fa - fb)
    V = P[ea] + (P[eb] - P[ea]) * t[:, None]
    T = inv.reshape(-1, 3)
    # wind outward: along the field's rise (from the inside corner of each triangle's first edge to its outside one)
    e0a, e0b = E[:, 0, 0], E[:, 0, 1]
    inside_first = f[e0a] < 0
    rise = np.where(inside_first[:, None], P[e0b] - P[e0a], P[e0a] - P[e0b])
    n = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    flip = np.einsum("ij,ij->i", n, rise) < 0
    T[flip] = T[flip][:, ::-1]
    # drop triangles whose corners coincide (t at 0 or 1 on two edges)
    good = (T[:, 0] != T[:, 1]) & (T[:, 1] != T[:, 2]) & (T[:, 0] != T[:, 2])
    return V, T[good]


def weld(V, T, tol=1e-7):
    """Merge coincident vertices (a contour through a grid corner), dropping the triangles that collapse."""
    q = np.round(V / tol).astype(np.int64)
    _u, idx, inv = np.unique(q, axis=0, return_index=True, return_inverse=True)
    inv = inv.ravel()
    V2 = V[idx]
    T2 = inv[T]
    good = (T2[:, 0] != T2[:, 1]) & (T2[:, 1] != T2[:, 2]) & (T2[:, 0] != T2[:, 2])
    return V2, T2[good]


def adjacency(T, n):
    from scipy import sparse
    i = np.concatenate([T[:, 0], T[:, 1], T[:, 2], T[:, 1], T[:, 2], T[:, 0]])
    j = np.concatenate([T[:, 1], T[:, 2], T[:, 0], T[:, 0], T[:, 1], T[:, 2]])
    A = sparse.coo_matrix((np.ones(len(i)), (i, j)), shape=(n, n)).tocsr()
    A.data[:] = 1.0
    deg = np.asarray(A.sum(axis=1)).ravel()
    return A, deg


def taubin(V, T, iters=10, lam=0.5, mu=-0.53, fixed=None):
    """Taubin's smoothing (shrink, then inflate): removes the grid's ripples and keeps the volume."""
    A, deg = adjacency(T, len(V))
    V = V.copy()
    for _ in range(iters):
        for f in (lam, mu):
            avg = (A @ V) / np.maximum(deg, 1)[:, None]
            dV = f * (avg - V)
            if fixed is not None:
                dV[fixed] = 0.0
            V = V + dV
    return V


def to_blender(V):
    V = np.asarray(V, np.float64)
    return np.stack([V[:, 0], -V[:, 1], V[:, 2]], axis=1)


def flip(A):
    """Triangles (or per-corner arrays) with their winding reversed: to_blender mirrors the forward axis, so a
    triangle wound outward in (x, u, z) is wound outward in Blender's frame only with its corners reversed."""
    return np.asarray(A)[:, ::-1]


def mesh_stats(T):
    """(boundary edges, non-manifold edges, edges) of a triangle mesh."""
    E = np.sort(np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), axis=1)
    _u, cnt = np.unique(E, axis=0, return_counts=True)
    return int((cnt == 1).sum()), int((cnt > 2).sum()), len(cnt)


def directed_edges_ok(T):
    """True when every directed edge appears once and its reverse once (closed, manifold, consistently wound)."""
    D = np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]])
    key = D[:, 0].astype(np.int64) * (int(T.max()) + 1) + D[:, 1]
    rkey = D[:, 1].astype(np.int64) * (int(T.max()) + 1) + D[:, 0]
    u, c = np.unique(key, return_counts=True)
    if (c != 1).any():
        return False
    return bool(np.isin(rkey, u).all())


# ---- the tail's dock (part of the closed body) ------------------------------------------------------------------
def horse_dock(P, h=HORSE):
    r, m = np.array(h["tail_root"]), np.array(h["tail_mid"])
    return smin(sd_round_cone(P, r + np.array([0, 0.03, 0.0]), r + (m - r) * 0.55, 0.050, 0.032, 0.9),
                sd_ellipsoid(P, r + np.array([0, 0.02, -0.01]), (0.05, 0.06, 0.05)), 0.04)


# ---- the skeleton: 25 bones (plan §2.8) ---------------------------------------------------------------------------
# Root, pelvis, spine_01-02, neck, head, jaw, tail_01-02, and per leg three bones and a foot: the foreleg's upper arm
# (shoulder joint to elbow), forearm (elbow to knee), cannon (knee to fetlock) and foot (fetlock to the hoof's sole);
# the hind leg's thigh (hip to stifle), gaskin (stifle to hock), cannon (hock to fetlock) and foot.
LEGS = ("fore_l", "fore_r", "hind_l", "hind_r")
LEG_BONES = ("upper", "lower", "cannon", "foot")
BONES = ("Root", "pelvis", "spine_01", "spine_02", "neck", "head", "jaw", "tail_01", "tail_02") + tuple(
    "%s_%s_%s" % (leg.split("_")[0], part, leg.split("_")[1]) for leg in LEGS for part in LEG_BONES)
PARENTS = {"Root": "", "pelvis": "Root", "spine_01": "pelvis", "spine_02": "spine_01", "neck": "spine_02",
           "head": "neck", "jaw": "head", "tail_01": "pelvis", "tail_02": "tail_01"}
for _leg in LEGS:
    _end, _side = _leg.split("_")
    _chain = ["%s_%s_%s" % (_end, p, _side) for p in LEG_BONES]
    PARENTS[_chain[0]] = "spine_02" if _end == "fore" else "pelvis"
    for _a, _b in zip(_chain, _chain[1:]):
        PARENTS[_b] = _a


def joints(h=HORSE) -> dict:
    """{bone: (head, tail)} in (x, u, z) metres."""
    J = {"Root": ((0, 0, 0), (0, 0.30, 0)),
         "pelvis": ((0, -0.52, 1.30), (0, -0.16, 1.33)),
         "spine_01": ((0, -0.16, 1.33), (0, 0.24, 1.35)),
         "spine_02": ((0, 0.24, 1.35), (0, 0.62, 1.32)),
         "neck": ((0, 0.62, 1.32), h["neck_top"]),
         "head": (h["neck_top"], h["muzzle"]),
         "jaw": (h["jaw_joint"], h["chin"]),
         "tail_01": (h["tail_root"], h["tail_mid"]),
         "tail_02": (h["tail_mid"], h["tail_end"])}
    for side, m in (("l", lambda p: p), ("r", _mirror)):
        fore = [h["shoulder"], h["elbow"], h["knee"], h["fore_fetlock"]]
        fore_toe = (h["fore_coronet"][0], h["fore_coronet"][1] + 0.03, 0.0)
        hind = [h["hip"], h["stifle"], h["hock"], h["hind_fetlock"]]
        hind_toe = (h["hind_coronet"][0], h["hind_coronet"][1] + 0.03, 0.0)
        for end, pts, toe in (("fore", fore, fore_toe), ("hind", hind, hind_toe)):
            seq = [m(p) for p in pts] + [m(toe)]
            for i, part in enumerate(LEG_BONES):
                J["%s_%s_%s" % (end, part, side)] = (seq[i], seq[i + 1])
    return {b: (np.asarray(J[b][0], np.float64), np.asarray(J[b][1], np.float64)) for b in BONES}


def _seg_dist(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1), t


WEIGHT_SIGMA_M = 0.030             # the falloff of a bone's weight beyond the nearest bone's distance
WEIGHT_REACH = 3.5                 # bones further than nearest + REACH x SIGMA take nothing


def core_sdf(P, h=HORSE):
    """The body without its limbs (the trunk's core, the neck, the head, the dock): what stays on the spine."""
    return smin(smin(horse_trunk(P, h, limbs=False), horse_head(P, h), 0.07), horse_dock(P, h), 0.05)


LIMB_BLEND_M = (0.004, 0.07)       # a vertex this far outside the core is wholly its leg's (from the first, none)


def _falloff(D):
    dmin = D.min(axis=1, keepdims=True)
    W = np.where(D < dmin + WEIGHT_REACH * WEIGHT_SIGMA_M, np.exp(-(D - dmin) / WEIGHT_SIGMA_M), 0.0)
    return W / np.maximum(W.sum(axis=1, keepdims=True), 1e-12)


def weights(P, h=HORSE):
    """(n, 4) bone indices into BONES and (n, 4) weights, normalized. A vertex is its leg's as far as it stands
    outside the body's core (``core_sdf``: the trunk without the shoulder blades, upper arms, thighs and buttocks, and
    the legs), the core's otherwise; within each, by distance to the bone chains (each vertex's nearest bone and the
    others within WEIGHT_REACH falloffs of it): a leg's four bones on its own side and end, the core's the spine, the
    neck, the head, the jaw only under the face's middle line, the tail only behind the croup. Root takes nothing."""
    P = np.asarray(P, np.float64)
    J = joints(h)
    n = len(P)
    D = np.full((n, len(BONES)), np.inf)
    side = np.where(P[:, 0] >= 0.0, "l", "r")
    end = np.where(P[:, 1] > -0.05, "fore", "hind")
    leg_bone = np.zeros(len(BONES), bool)
    for i, b in enumerate(BONES):
        if b == "Root":
            continue
        d, _t = _seg_dist(P, J[b][0], J[b][1])
        if b.startswith(("fore_", "hind_")):
            leg_bone[i] = True
            mine = (side == b[-1]) & (end == b.split("_")[0])
            d = np.where(mine, d, np.inf)
        if b.startswith("tail"):
            d = np.where(P[:, 1] < h["tail_root"][1] + 0.03, d, np.inf)
        if b == "jaw":
            a, c = J["head"]
            fr = frame_from(c - a)
            below = (P - a) @ fr[2] < -0.07          # under the face's axis (the front row points up-forward)
            d = np.where(below & (d < 0.12), d, np.inf)
        D[:, i] = d
    Dl = np.where(leg_bone[None, :], D, np.inf)
    Dc = np.where(leg_bone[None, :], np.inf, D)
    Dc[:, 0] = np.inf
    f = sstep(core_sdf(P, h), *LIMB_BLEND_M)[:, None]
    W = f * _falloff(Dl) + (1.0 - f) * _falloff(Dc)
    idx = np.argsort(-W, axis=1, kind="stable")[:, :4]
    w4 = np.take_along_axis(W, idx, axis=1)
    w4 = w4 / np.maximum(w4.sum(axis=1, keepdims=True), 1e-12)
    w4 = np.round(w4, 6)
    w4[:, 0] += 1.0 - w4.sum(axis=1)
    return idx, w4


# ---- the gait's extremes (a check, not clips: P62's QuadrupedRig drives the bones) ---------------------------------
# Each pose: {bone: degrees about the lateral (+x) axis at the bone's head, relative to its parent}: + swings a
# hanging leg's lower end forward, raises the neck and the head, and swings a hanging tail under; - the reverse.
POSES = {
    "stand": {},
    # the trot's two extremes: the diagonal pairs at the end of their reach and of their push
    "trot_reach_left": {"fore_upper_l": 24, "fore_lower_l": 4, "fore_cannon_l": -6, "fore_foot_l": -14,
                        "hind_upper_r": 22, "hind_lower_r": -2, "hind_cannon_r": -6, "hind_foot_r": -10,
                        "fore_upper_r": -12, "fore_lower_r": -14, "fore_cannon_r": -46, "fore_foot_r": -30,
                        "hind_upper_l": -14, "hind_lower_l": 8, "hind_cannon_l": -12, "hind_foot_l": -24,
                        "neck": 4, "tail_01": -12},
    "trot_reach_right": {},              # the mirror of the left (filled below)
    # the gallop's extended and gathered moments
    "gallop_extended": {"fore_upper_l": 40, "fore_lower_l": 6, "fore_cannon_l": -4, "fore_foot_l": -10,
                        "fore_upper_r": 30, "fore_lower_r": 4, "fore_cannon_r": -8, "fore_foot_r": -12,
                        "hind_upper_l": -32, "hind_lower_l": 16, "hind_cannon_l": -18, "hind_foot_l": -20,
                        "hind_upper_r": -26, "hind_lower_r": 14, "hind_cannon_r": -16, "hind_foot_r": -22,
                        "neck": 10, "head": -6, "tail_01": -30, "tail_02": -10},
    "gallop_gathered": {"fore_upper_l": -18, "fore_lower_l": -22, "fore_cannon_l": -70, "fore_foot_l": -30,
                        "fore_upper_r": -10, "fore_lower_r": -16, "fore_cannon_r": -60, "fore_foot_r": -24,
                        "hind_upper_l": 32, "hind_lower_l": -26, "hind_cannon_l": 26, "hind_foot_l": -14,
                        "hind_upper_r": 26, "hind_lower_r": -22, "hind_cannon_r": 22, "hind_foot_r": -12,
                        "neck": -6, "head": 4, "tail_01": -20},
}
POSES["trot_reach_right"] = {(k[:-2] + ("_r" if k.endswith("_l") else "_l")) if k.endswith(("_l", "_r")) else k: v
                             for k, v in POSES["trot_reach_left"].items()}
POSE_ORDER = ("stand", "trot_reach_left", "trot_reach_right", "gallop_extended", "gallop_gathered")


def _rot_x(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], np.float64)


def pose_matrices(pose, h=HORSE) -> dict:
    """{bone: 4x4} the skinning matrices (posed world from rest world) of a pose, in (x, u, z)."""
    J = joints(h)
    out = {}
    for b in BONES:                     # BONES lists every parent before its children
        p = PARENTS[b]
        M = out[p] if p else np.eye(4)
        a = pose.get(b, 0.0)
        if a:
            head = J[b][0]
            R = np.eye(4)
            R[:3, :3] = _rot_x(a)
            T1, T2 = np.eye(4), np.eye(4)
            T1[:3, 3] = head
            T2[:3, 3] = -head
            M = M @ T1 @ R @ T2
        out[b] = M
    return out


def skin(P, idx, w4, mats):
    Ms = np.stack([mats[b] for b in BONES])
    Ph = np.concatenate([P, np.ones((len(P), 1))], axis=1)
    out = np.zeros((len(P), 3))
    for k in range(4):
        out += w4[:, k, None] * np.einsum("nij,nj->ni", Ms[idx[:, k]], Ph)[:, :3]
    return out


def volume(V, T):
    return float(np.einsum("ij,ij->i", V[T[:, 0]], np.cross(V[T[:, 1]], V[T[:, 2]])).sum() / 6.0)


# ======================================================================================================================
# The horse's build: Blender's decimation, unwrap and glTF export (``python quadruped.py <out dir> <work dir>``)
# ======================================================================================================================
BODY_STEP_M = 0.012                # the field's grid
SMOOTH_ITERS = 6                   # Taubin passes on the dense mesh
BODY_TRIS = 4700                   # the body after the collapse (closed, manifold)
TRIS_MAX = 6000                    # a horse, bare or tacked: one mesh, one surface (plan §3.14)
SADDLE_TRIS = 440
SADDLE_STEP_M = 0.008
CAPARISON_OFF_M = 0.016            # the housing's cloth over the coat
SADDLE_IN_M = 0.024                # the saddle's underside over the coat (over the housing's cloth)
STRAP_W_M, STRAP_OFF_M = 0.022, 0.008
ALBEDO_PX, NORMAL_PX, ORM_PX = 512, 256, 256
# the atlas's rectangles (u0, v0, u1, v1; v up)
RECTS = {"body": (0.0, 0.25, 0.75, 1.0), "caparison": (0.0, 0.0, 0.75, 0.25), "hair": (0.75, 0.75, 1.0, 1.0),
         "leather": (0.75, 0.5, 1.0, 0.75), "metal": (0.75, 0.25, 1.0, 0.5)}
# materials: the band of the palette mask (people_roles.BANDS: the person shader's) and roughness; the coat's own
# texels choose among coat (skin band: the coat colour), points (hair band: the mane's colour), white, hoof and eye
MATERIALS = {"coat": ("skin", 0.55), "points": ("hair", 0.58), "white": ("none", 0.6), "hoof": ("none", 0.42),
             "eye": ("none", 0.32), "hair": ("hair", 0.6), "leather": ("none", 0.55), "metal": ("none", 0.35),
             "faction": ("faction", 0.85)}
PIECE_MATERIAL = {"body": "coat", "mane": "hair", "tail": "hair", "saddle": "leather", "straps": "leather",
                  "irons": "metal", "caparison": "faction"}
PIECE_RECT = {"body": "body", "mane": "hair", "tail": "hair", "saddle": "leather", "straps": "leather",
              "irons": "metal", "caparison": "caparison"}
TACK = ("saddle", "straps", "irons", "caparison")
PREVIEW_PALETTE = {"skin": (0.40, 0.20, 0.10), "hair": (0.07, 0.06, 0.05), "cloth": (0.8, 0.8, 0.8),
                   "faction": (0.62, 0.13, 0.10)}       # a bay with black points, a red housing (the sheets only)
SEAT_U = 0.16


def log(*a):
    print("[quadruped]", *a, flush=True)


def r6(x):
    return float(round(float(x), 6))


def sstep(x, a, b):
    t = np.clip((np.asarray(x, np.float64) - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def surface_point(c, d, fn=None, reach=0.6):
    """The field's zero along the ray c + s d (from inside), by bisection."""
    fn = fn or horse_sdf
    c, d = np.asarray(c, np.float64), _unit(d)
    lo, hi = 0.0, reach
    for _ in range(40):
        mid = (lo + hi) * 0.5
        if fn((c + d * mid)[None])[0] < 0.0:
            lo = mid
        else:
            hi = mid
    return c + d * lo


def field_normal(p, fn=None, e=1e-3):
    fn = fn or horse_sdf
    p = np.asarray(p, np.float64)
    off = np.eye(3) * e
    g = np.array([fn((p + off[i])[None])[0] - fn((p - off[i])[None])[0] for i in range(3)])
    return _unit(g)


def project_out(p, off, fn=None):
    """A point moved along the field's gradient onto the surface offset by ``off``."""
    fn = fn or horse_sdf
    p = np.asarray(p, np.float64)
    for _ in range(6):
        d = fn(p[None])[0]
        p = p - field_normal(p, fn) * (d - off)
    return p


# ---- the mane, the forelock and the tail: cards (the hair tile, the hair band) -------------------------------------
class Piece:
    """A piece of the horse in (x, u, z): V, T, corner UVs (m, 3, 2) inside its rectangle (0..1 there), and the
    weights (idx (n, 4), w (n, 4)) once known."""

    def __init__(self, name, V, T, uv):
        self.name, self.V, self.T, self.uv = name, np.asarray(V, np.float64), np.asarray(T, np.int64), np.asarray(uv)
        self.idx = self.w = None


def strip(rows_l, rows_r, vs):
    """A ribbon between two polylines (k, 3): triangles and corner UVs (u 0 at the left, 1 at the right; v by vs)."""
    k = len(rows_l)
    V = np.concatenate([rows_l, rows_r])
    T, UV = [], []
    for i in range(k - 1):
        a, b, c, d = i, i + 1, k + i + 1, k + i
        T += [(a, b, c), (a, c, d)]
        UV += [((0, vs[i]), (0, vs[i + 1]), (1, vs[i + 1])), ((0, vs[i]), (1, vs[i + 1]), (1, vs[i]))]
    return V, np.array(T), np.array(UV, np.float64)


def merge_parts(parts):
    Vs, Ts, UVs, n = [], [], [], 0
    for V, T, UV in parts:
        Vs.append(V)
        Ts.append(T + n)
        UVs.append(UV)
        n += len(V)
    return np.concatenate(Vs), np.concatenate(Ts), np.concatenate(UVs)


MANE_STATIONS = 15


def neck_section(t, h=HORSE):
    """The neck's section at t (0 the withers' end, 1 the poll's): (lower point, upper point) as horse_trunk lays it."""
    base_lo, base_hi = np.array((0, 0.77, 1.15)), np.array((0, 0.52, 1.45))
    thr, pol = np.array((0, 1.03, 1.68)), np.array(h["poll"])
    lo = _lerp(base_lo, thr, t)
    hi = _lerp(base_hi, pol + np.array([0, -0.10, -0.06]), t) + np.array([0, -0.03, 0.06]) * math.sin(math.pi * t)
    return lo, hi


def mane(h=HORSE):
    """The mane lying on the neck's right side from the poll to the withers, a short fringe on the left, an upright
    crest along the top, and the forelock between the ears."""
    parts = []
    ts = np.linspace(0.16, 0.985, MANE_STATIONS)
    crest, axis = [], []
    for t in ts:
        lo, hi = neck_section(t, h)
        c = (lo + hi) * 0.5
        up = _unit(hi - lo)
        crest.append(surface_point(c, up))
        axis.append(c)
    crest, axis = np.array(crest), np.array(axis)
    tang = np.gradient(crest, axis=0)
    tang /= np.linalg.norm(tang, axis=1, keepdims=True)
    for side, length in ((-1.0, 1.0), (1.0, 0.35)):
        for i, t in enumerate(ts):
            L = (0.17 + 0.10 * math.sin(math.pi * min(1.0, t * 1.1))) * length
            if t > 0.93:
                L *= 0.6
            c = axis[i]
            up = _unit(crest[i] - c)
            lat = np.array([side, 0.0, 0.0])
            rows = []
            nseg = 4 if length > 0.5 else 2
            for k in range(nseg + 1):
                f = k / nseg
                ang = f * (1.75 if length > 0.5 else 0.9) * (L / 0.27)
                d = _unit(up * math.cos(ang) + lat * math.sin(ang))
                p = surface_point(c, d) + d * (0.012 + 0.010 * f) + np.array([0, 0, -0.02 * f * f])
                rows.append(p)
            rows = np.array(rows)
            w = 0.085 if length > 0.5 else 0.06
            left = rows - tang[i] * w * 0.5
            right = rows + tang[i] * w * 0.5
            vs = np.linspace(1.0, 0.0, len(rows))
            parts.append(strip(left, right, vs))
    # the crest: an upright card along the top
    up_all = crest + _unit_rows(crest - axis) * 0.055
    parts.append(strip(crest - _unit_rows(crest - axis) * 0.005, up_all, np.linspace(0.05, 0.95, len(crest))))
    parts[-1] = (parts[-1][0], parts[-1][1], parts[-1][2][:, :, ::-1])     # its strands run across the strip
    # the forelock: two cards from between the ears down the forehead
    poll, muz = np.array(h["poll"]), np.array(h["muzzle"])
    ax = muz - poll
    front = frame_from(ax)[2]
    for s in (-0.018, 0.018):
        rows = []
        for k in range(4):
            f = k / 3.0
            q = poll + ax * (0.02 + 0.30 * f) + np.array([s * (1 + f), 0, 0])
            rows.append(surface_point(q - front * 0.06, front) + front * (0.012 + 0.006 * (1 - f)))
        rows = np.array(rows)
        parts.append(strip(rows - np.array([0.03, 0, 0]), rows + np.array([0.03, 0, 0]), np.linspace(1.0, 0.0, 4)))
    V, T, UV = merge_parts(parts)
    return Piece("mane", V, T, UV)


def _unit_rows(A):
    return A / np.maximum(np.linalg.norm(A, axis=1, keepdims=True), 1e-12)


TAIL_CARDS, TAIL_SEGMENTS = 5, 7


def tail_path(s, h=HORSE):
    """The tail's hair: out and back from the dock, then falling to a little above the hocks."""
    r = np.array(h["tail_root"])
    p0, p1, p2 = r + np.array([0, -0.01, 0.01]), r + np.array([0, -0.16, -0.12]), np.array((0.0, -1.02, 0.58))
    s = np.asarray(s, np.float64)[:, None]
    return (1 - s) ** 2 * p0 + 2 * (1 - s) * s * p1 + s * s * p2


def tail(h=HORSE):
    s = np.linspace(0.0, 1.0, TAIL_SEGMENTS + 1)
    P = tail_path(s, h)
    tang = _unit_rows(np.gradient(P, axis=0))
    width = 0.07 + 0.11 * np.sin(np.pi * np.clip(s * 0.85 + 0.08, 0, 1)) - 0.03 * s
    parts = []
    for k in range(TAIL_CARDS):
        a = math.pi * k / TAIL_CARDS
        side = []
        for i in range(len(P)):
            n1 = _unit(np.cross(tang[i], np.array([1.0, 0, 0])))
            d = math.cos(a) * np.array([1.0, 0, 0]) + math.sin(a) * n1
            side.append(d * width[i] * 0.5)
        side = np.array(side)
        parts.append(strip(P - side, P + side, np.linspace(1.0, 0.0, len(P))))
    V, T, UV = merge_parts(parts)
    pc = Piece("tail", V, T, UV)
    # weights: the dock's bone, then the second
    sv = np.tile(s, TAIL_CARDS * 2)
    w2 = sstep(sv, 0.18, 0.5)
    pc.idx = np.zeros((len(V), 4), np.int64)
    pc.idx[:, 0] = BONES.index("tail_01")
    pc.idx[:, 1] = BONES.index("tail_02")
    pc.idx[:, 2] = BONES.index("pelvis")
    pc.idx[:, 3] = BONES.index("spine_01")
    pc.w = np.zeros((len(V), 4))
    pc.w[:, 0] = np.round(1.0 - w2, 6)
    pc.w[:, 1] = 1.0 - pc.w[:, 0]
    return pc


# ---- the tack ----------------------------------------------------------------------------------------------------
def saddle_sdf(P, h=HORSE):
    """A saddle over the housing: a shell of the trunk from SADDLE_IN_M out, thicker at the pommel and the cantle,
    its flaps down the sides; the girth under the belly."""
    b = horse_trunk(P, h)
    x, u, z = P[:, 0], P[:, 1], P[:, 2]
    ax = np.abs(x)
    pommel = 0.050 * np.exp(-((u - 0.355) / 0.04) ** 2) * np.exp(-(x / 0.08) ** 2)
    cantle = 0.060 * np.exp(-((u + 0.06) / 0.035) ** 2) * sstep(-ax, -0.18, -0.10)
    thick = 0.026 + pommel + cantle
    shell = np.maximum(b - (SADDLE_IN_M + thick), SADDLE_IN_M - b)
    # the seat's outline: from behind the withers to the cantle, down the sides to the flaps
    region = np.maximum(-0.095 - u, u - 0.40)
    flap = sstep(u, 0.06, 0.10) * sstep(-u, -0.34, -0.30) * sstep(ax, 0.10, 0.14)
    zlow = 1.30 - 0.6 * np.maximum(0.0, ax - 0.12) - (1.30 - 1.10) * flap
    region = smax(region, zlow - z, 0.03)
    d = smax(shell, region, 0.012)
    # the girth: a band round the barrel under the flaps
    girth = smax(np.maximum(b - (SADDLE_IN_M + 0.010), SADDLE_IN_M - 0.004 - b), np.abs(u - 0.27) - 0.032, 0.006)
    girth = smax(girth, z - 1.08, 0.01)
    return smin(d, girth, 0.01)


SADDLE_BOX = ((-0.36, 0.36), (-0.25, 0.55), (0.70, 1.80))


def saddle_seat(h=HORSE):
    """The seat's lowest point on the saddle's top (where a rider sits)."""
    z = np.arange(1.90, 1.20, -0.002)
    P = np.stack([np.zeros_like(z), np.full_like(z, SEAT_U), z], axis=1)
    inside = np.nonzero(saddle_sdf(P, h) < 0.0)[0]
    return P[inside[0]] if len(inside) else P[-1]


def caparison(h=HORSE):
    """The housing: a cloth over the barrel from behind the shoulders to in front of the stifles, over the back and down
    the sides, falling straight from the barrel's widest line to a dagged hem."""
    us = np.linspace(0.44, -0.40, 9)
    n_arc, n_drop = 5, 3
    hem = 0.76
    rows = []
    for u in us:
        c = np.array([0.0, u, 1.18])
        # the arc over the back, from the top to the widest point
        th = np.linspace(0.0, math.radians(105), 40)
        pts = np.array([surface_point(c, (math.sin(a), 0, math.cos(a)), horse_trunk) for a in th])
        k = int(np.argmax(pts[:, 0]))
        widest = pts[k]
        arc_th = np.linspace(0.0, th[k], n_arc + 1)
        arc = [surface_point(c, (math.sin(a), 0, math.cos(a)), horse_trunk) for a in arc_th]
        arc = [p + field_normal(p, horse_trunk) * CAPARISON_OFF_M for p in arc]
        x_w = arc[-1][0]
        drop = [np.array([x_w, u, arc[-1][2] - (arc[-1][2] - hem) * (j / n_drop)]) for j in range(1, n_drop + 1)]
        col = arc + drop                      # from the top down the left side
        rows.append(col)
    rows = np.array(rows)                     # (stations, n_arc + 1 + n_drop, 3), the left half
    ns, nc = rows.shape[:2]
    # dags: every other hem point a little higher
    rows[1:-1:2, -1, 2] += 0.045
    V, T, UV = [], [], []
    for side in (1.0, -1.0):
        base = len(V)
        for i in range(ns):
            for j in range(nc):
                p = rows[i, j].copy()
                p[0] *= side
                V.append(p)
        for i in range(ns - 1):
            for j in range(nc - 1):
                a, b, c, d = base + i * nc + j, base + (i + 1) * nc + j, base + (i + 1) * nc + j + 1, base + i * nc + j + 1
                tri = [(a, b, c), (a, c, d)] if side > 0 else [(a, c, b), (a, d, c)]
                T += tri
                uvq = {a: (i / (ns - 1), 1 - j / (nc - 1)), b: ((i + 1) / (ns - 1), 1 - j / (nc - 1)),
                       c: ((i + 1) / (ns - 1), 1 - (j + 1) / (nc - 1)), d: (i / (ns - 1), 1 - (j + 1) / (nc - 1))}
                UV += [[uvq[t] for t in tt] for tt in tri]
    V = np.array(V)
    T = np.array(T)
    # the two halves share the top line: weld it
    V, T, UV = _weld_uv(V, T, np.array(UV, np.float64))
    return Piece("caparison", V, T, UV)


def _weld_uv(V, T, UV, tol=1e-6):
    q = np.round(V / tol).astype(np.int64)
    _u, idx, inv = np.unique(q, axis=0, return_index=True, return_inverse=True)
    return V[idx], inv.ravel()[T], UV


def ribbon(points, normals, width, v0=0.0, v1=1.0):
    """A flat strap along a polyline lying on the surface (its width across, in the tangent plane)."""
    P = np.asarray(points, np.float64)
    N = _unit_rows(np.asarray(normals, np.float64))
    tang = _unit_rows(np.gradient(P, axis=0))
    side = _unit_rows(np.cross(tang, N)) * width * 0.5
    return strip(P - side, P + side, np.linspace(v0, v1, len(P)))


def _head_frame(h=HORSE):
    poll, muz = np.array(h["poll"]), np.array(h["muzzle"])
    ax = muz - poll
    fr = frame_from(ax)
    return poll, ax, fr[0], fr[2]


def _on_head(a, theta, off=STRAP_OFF_M, h=HORSE):
    """A point on the head's surface at ``a`` along the poll-muzzle axis, ``theta`` round it (0 the face's front, +90
    the left side), lifted ``off``; and the surface's normal there."""
    poll, ax, lat, front = _head_frame(h)
    c = poll + ax * a - front * 0.02
    d = math.cos(theta) * front + math.sin(theta) * lat
    p = surface_point(c, d, horse_sdf, 0.4)
    n = field_normal(p)
    return p + n * off, n


def bridle_and_reins(h=HORSE):
    """The headstall (crownpiece and cheekpieces in one strap from bit to bit over the poll, the browband, the
    noseband), the reins from the bit rings to the pommel, the stirrup leathers; and the bit rings and the stirrup
    irons (metal)."""
    parts = []
    rad = math.radians
    # the headstall: from the left bit ring up the cheek, over the poll behind the ears, down to the right ring
    pts, nrm = [], []
    for a, th in [(0.86, 100), (0.70, 98), (0.52, 96), (0.34, 95), (0.18, 96), (0.06, 100)]:
        p, n = _on_head(a, rad(th), h=h)
        pts.append(p)
        nrm.append(n)
    for th in (125, 150, 180, 210, 235):
        p, n = _on_head(0.0, rad(th), h=h)
        pts.append(p)
        nrm.append(n)
    for a, th in [(0.06, 260), (0.18, 264), (0.34, 265), (0.52, 264), (0.70, 262), (0.86, 260)]:
        p, n = _on_head(a, rad(th), h=h)
        pts.append(p)
        nrm.append(n)
    parts.append(ribbon(pts, nrm, STRAP_W_M))
    # the browband under the ears
    pts, nrm = zip(*[_on_head(0.12, rad(t), h=h) for t in range(-80, 81, 32)])
    parts.append(ribbon(pts, nrm, STRAP_W_M * 0.9))
    # the noseband round the face
    pts, nrm = zip(*[_on_head(0.64, rad(t), h=h) for t in range(-180, 181, 30)])
    parts.append(ribbon(pts, nrm, STRAP_W_M * 1.1))
    # the reins: from the bit rings in a slack curve over the neck to the pommel's front
    bit = {s: _on_head(0.88, rad(100 if s > 0 else 260), 0.02, h)[0] for s in (1, -1)}
    pommel = surface_point(np.array([0.0, 0.36, 1.35]), (0, 0, 1), lambda P: saddle_sdf(P, h), 0.6)
    for s in (1, -1):
        a = bit[s]
        b = pommel + np.array([0.06 * s, 0.03, -0.01])
        pts, nrm = [], []
        for k in range(11):
            f = k / 10.0
            p = a + (b - a) * f + np.array([0.0, 0.0, -0.10 * math.sin(math.pi * f)])
            d = horse_sdf(p[None])[0]
            if d < 0.025:
                p = p + np.array([0.025 - d, 0.0, 0.0]) * s * 1.5
            pts.append(p)
            nrm.append(np.array([s, 0.0, 0.3]))
        parts.append(ribbon(pts, nrm, 0.018))
    # the stirrup leathers from the saddle's sides
    tops = {}
    for s in (1, -1):
        top = surface_point(np.array([0.0, 0.20, 1.20]), (s, 0, 0.35), lambda P: saddle_sdf(P, h), 0.6)
        tops[s] = top
        bot = np.array([top[0] + 0.03 * s, top[1], 0.99])
        pts = [top + (bot - top) * f for f in np.linspace(0, 1, 4)]
        parts.append(ribbon(pts, [np.array([s, 0, 0.0])] * 4, 0.028))
    straps = Piece("straps", *merge_parts(parts))
    # metal: the bit rings and the stirrup irons (flat loops)
    mparts = []
    for s in (1, -1):
        c = bit[s] + np.array([0.008 * s, 0, 0])
        ring = [c + 0.021 * np.array([0, math.cos(a), math.sin(a)]) for a in np.linspace(0, 2 * math.pi, 9)]
        mparts.append(ribbon(ring, [np.array([s, 0, 0.0])] * 9, 0.006))
        top = np.array([tops[s][0] + 0.03 * s, tops[s][1], 0.99])
        loop = [top + np.array([0.06 * math.sin(a) * s * 0.0, 0.055 * math.sin(a), -0.075 * (1 - math.cos(a)) * 0.5
                                - 0.0 * a]) for a in np.linspace(0, 2 * math.pi, 11)]
        mparts.append(ribbon(loop, [np.array([s, 0, 0.0])] * 11, 0.022))
    irons = Piece("irons", *merge_parts(mparts))
    return straps, irons


# ---- the atlas ---------------------------------------------------------------------------------------------------
UV_INSET_PX = 2.0
STRAP_U = (0.90, 1.0)              # straps take this column of the leather rectangle (the saddle the rest)
SADDLE_U = (0.0, 0.88)


def rect_uv(uv01, rect, sub=None):
    """Corner UVs in 0..1 placed into an atlas rectangle (inset by UV_INSET_PX), optionally its sub-column first."""
    uv = np.asarray(uv01, np.float64).copy()
    if sub is not None:
        uv[..., 0] = sub[0] + uv[..., 0] * (sub[1] - sub[0])
    u0, v0, u1, v1 = RECTS[rect]
    e = UV_INSET_PX / ALBEDO_PX
    return np.stack([u0 + e + uv[..., 0] * (u1 - u0 - 2 * e), v0 + e + uv[..., 1] * (v1 - v0 - 2 * e)], axis=-1)


def _from_main(uv):
    """people_outfit.unwrap's UVs (people_roles.MAIN_UV's square) back to 0..1."""
    import people_roles as pr
    u0, v0, u1, v1 = pr.MAIN_UV
    return np.stack([(uv[..., 0] - u0) / (u1 - u0), (uv[..., 1] - v0) / (v1 - v0)], axis=-1)


def hair_tile(s, t):
    """The mane's and the tail's strands: (albedo grey, alpha) at tile coordinates s across, t along (1 the root)."""
    rng = np.random.default_rng(61)
    n = 44
    cen = (np.arange(n) + 0.5 + 0.4 * (rng.random(n) - 0.5)) / n
    wid = (0.55 + 0.35 * rng.random(n)) / n
    lng = 0.70 + 0.30 * rng.random(n)
    val = 0.72 + 0.28 * rng.random(n)
    ph = rng.random(n) * 6.28
    cov = np.zeros_like(s)
    alb = np.zeros_like(s)
    for j in range(n):
        c = cen[j] + 0.012 * np.sin(t * 7.0 + ph[j])
        a = np.exp(-((s - c) / wid[j]) ** 2) * sstep(t, 1.0 - lng[j], 1.0 - lng[j] + 0.15)
        alb = alb + a * val[j]
        cov = 1.0 - (1.0 - cov) * (1.0 - a)
    cov = np.maximum(cov, sstep(t, 0.55, 0.85))
    grey = np.clip(alb / np.maximum(1e-6, -np.log(np.maximum(1.0 - cov, 1e-4)) + 1e-6), 0.0, 1.0)
    grey = np.where(cov > 0.02, np.clip(0.55 + 0.45 * grey, 0, 1), 0.8)
    return grey, np.clip(cov * 1.15, 0.0, 1.0)


def coat(P, h=HORSE):
    """Per point (x, u, z) of the coat: (material, grey albedo): the coat (tinted by the palette's coat colour), the
    points below the knees and hocks and at the ears' tips (the mane's colour), a white left hind sock,
    the hooves, the eyes; the muzzle and the dock darker, the spine a little darker, the belly lighter."""
    import people_bake as pbk
    x, u, z = P[:, 0], P[:, 1], P[:, 2]
    n = len(P)
    noise = pbk.fbm(P, 7.0, 3)
    fine = pbk.fbm(P, 30.0, 5)
    grey = 0.88 + 0.06 * (noise - 0.5) + 0.03 * (fine - 0.5)
    grey = grey - 0.06 * sstep(z, 1.35, 1.6) * sstep(-np.abs(x), -0.12, -0.02)        # the darker topline
    grey = grey + 0.05 * sstep(-z, -1.0, -0.85) * sstep(np.abs(x), 0.0, 0.2) * (u > -0.5) * (u < 0.5)
    poll, ax, lat, front = _head_frame(h)
    muzzle = poll + ax * 0.95
    dm = np.linalg.norm(P - muzzle, axis=1)
    grey = grey * (1.0 - 0.45 * sstep(-dm, -0.13, -0.06))
    mat = np.array(["coat"] * n, dtype=object)
    # points: under the knees and the hocks (a ragged line), the ears' tips, the dock
    kz = np.where(u > 0.0, h["knee"][2] + 0.03, h["hock"][2] - 0.01) + 0.05 * (noise - 0.5)
    pts = (z < kz)
    ear = (z > poll[2] + 0.07) & (np.abs(u - poll[1]) < 0.08)
    mat[pts | ear] = "points"
    # the white left hind sock (to above the fetlock)
    sock = (x > 0.05) & (u < -0.4) & (z < 0.30 + 0.03 * (fine - 0.5))
    mat[sock] = "white"
    grey = np.where(sock, 0.93 + 0.03 * (fine - 0.5), grey)
    # the hooves under the coronet band
    hoof = np.zeros(n, bool)
    for key, side in (("fore_coronet", 1), ("fore_coronet", -1), ("hind_coronet", 1), ("hind_coronet", -1)):
        c = np.array(h[key]) * [side, 1, 1]
        near = np.linalg.norm((P - c)[:, :2], axis=1) < 0.12
        hoof |= near & (z < c[2] + 0.004 + 0.45 * (u - c[1]))
    mat[hoof] = "hoof"
    pale = hoof & (x > 0.05) & (u < -0.4)
    grey = np.where(hoof, np.where(pale, 0.62, 0.22) * (1.0 + 0.12 * (fine - 0.5)) * (1.0 - 0.25 * sstep(-z, -0.03, 0.0)),
                    grey)
    # the eyes
    fr = frame_from(ax)
    for e in eye_centres(h):
        q = P - e
        d = np.sqrt((q @ fr[1] / 0.030) ** 2 + (q @ fr[2] / 0.020) ** 2 + (q @ fr[0] / 0.05) ** 2)
        mat[d < 1.0] = "eye"
        grey = np.where(d < 1.0, 0.07, grey * (1.0 - 0.45 * sstep(-d, -1.45, -1.0)))
    return mat, np.clip(grey, 0.0, 1.0)


HOOF_RGB = np.array([0.30, 0.27, 0.24])
EYE_RGB = np.array([0.10, 0.065, 0.045])
WHITE_RGB = np.array([0.95, 0.94, 0.90])
LEATHER_RGB = np.array([0.34, 0.22, 0.13])
METAL_RGB = np.array([0.45, 0.46, 0.48])


def bake(pieces, dense, out_dir, ao_by_piece):
    """horse_albedo.png (RGBA, 512 px: A the strands' coverage), horse_normal.png and horse_orm.png (256 px)."""
    import people_bake as pbk
    import people_roles as pr
    from scipy.spatial import cKDTree
    names = [p.name for p in pieces]
    UV = np.concatenate([p.uv_atlas for p in pieces])
    owner = np.concatenate([np.full(len(p.T), i) for i, p in enumerate(pieces)])
    local = np.concatenate([np.arange(len(p.T)) for p in pieces])
    dV, dN = dense
    dtree = cKDTree(dV)

    def texels(size):
        tri, bar = pbk.raster(UV, size)
        filled = tri >= 0
        ys, xs = np.nonzero(filled)
        t = tri[ys, xs]
        b = bar[ys, xs]
        pos = np.zeros((len(t), 3))
        uvt = np.zeros((len(t), 2))
        for i, p in enumerate(pieces):
            sel = owner[t] == i
            tt = local[t[sel]]
            pos[sel] = np.einsum("nk,nkj->nj", b[sel], p.V[p.T[tt]])
            uvt[sel] = np.einsum("nk,nkj->nj", b[sel], p.uv01[tt])
        return filled, ys, xs, t, b, pos, uvt

    # ---- albedo
    filled, ys, xs, t, b, pos, uvt = texels(ALBEDO_PX)
    rgb = np.zeros((ALBEDO_PX, ALBEDO_PX, 3))
    alpha = np.ones((ALBEDO_PX, ALBEDO_PX))
    for i, p in enumerate(pieces):
        sel = owner[t] == i
        if not sel.any():
            continue
        yy, xx = ys[sel], xs[sel]
        P = pos[sel]
        mat = PIECE_MATERIAL[p.name]
        if mat == "coat":
            m, g = coat(P)
            col = np.repeat(g[:, None], 3, axis=1)
            for k, c in (("hoof", HOOF_RGB / 0.30), ("eye", EYE_RGB / 0.10), ("white", WHITE_RGB / 0.95)):
                sel2 = m == k
                col[sel2] = g[sel2, None] * c
        elif mat == "hair":
            g, a = hair_tile(uvt[sel, 0], uvt[sel, 1])
            col = np.repeat(g[:, None], 3, axis=1)
            alpha[yy, xx] = a
        elif mat == "faction":
            v = uvt[sel, 1]
            g = 0.88 - 0.30 * sstep(-v, -0.13, -0.10) + 0.08 * (sstep(v, 0.15, 0.16) - sstep(v, 0.18, 0.19))
            g = g - 0.20 * sstep(v, 0.965, 0.98)
            g = g * (1.0 + 0.05 * (pbk.fbm(P, 60.0, 7) - 0.5))
            col = np.repeat(g[:, None], 3, axis=1)
        else:
            base = LEATHER_RGB if mat == "leather" else METAL_RGB
            col = base[None, :] * (1.0 + 0.16 * (pbk.fbm(P, 40.0, 9) - 0.5))[:, None]
        rgb[yy, xx] = col
    rgb = pbk.dilate(rgb, filled)
    alpha = pbk.dilate(alpha[..., None], filled)[..., 0]
    u0, v0, u1, v1 = RECTS["hair"]                         # only the strands' tile is ever transparent
    keep = np.ones_like(alpha)
    keep[int(round((1 - v1) * ALBEDO_PX)):int(round((1 - v0) * ALBEDO_PX)),
         int(round(u0 * ALBEDO_PX)):int(round(u1 * ALBEDO_PX))] = 0.0
    alpha = np.maximum(alpha, keep)
    alb = np.concatenate([pbk.to_u8(rgb), pbk.to_u8(alpha)[..., None]], axis=-1)
    pbk.save_png(os.path.join(out_dir, "horse_albedo.png"), alb)
    # ---- normal and ORM at 256 px
    filled, ys, xs, t, b, pos, uvt = texels(NORMAL_PX)
    nrm = np.zeros((NORMAL_PX, NORMAL_PX, 3))
    nrm[..., 2] = 1.0
    orm = np.zeros((ORM_PX, ORM_PX, 3))
    for i, p in enumerate(pieces):
        sel = owner[t] == i
        if not sel.any():
            continue
        yy, xx = ys[sel], xs[sel]
        tt = local[t[sel]]
        bb = b[sel]
        P = pos[sel]
        mat = PIECE_MATERIAL[p.name]
        if p.name == "body":
            tan = np.einsum("nk,nkj->nj", bb, p.tan[tt])
            nor = _unit_rows(np.einsum("nk,nkj->nj", bb, p.nor[tt]))
            sgn = np.where(np.einsum("nk,nk->n", bb, p.sgn[tt]) >= 0, 1.0, -1.0)
            tan = _unit_rows(tan - nor * np.einsum("ij,ij->i", tan, nor)[:, None])
            bit = np.cross(nor, tan) * sgn[:, None]
            d, k = dtree.query(to_blender(P), k=4)
            w = 1.0 / np.maximum(d, 1e-5)
            hn = _unit_rows(np.einsum("nk,nkj->nj", w, dN[k]))
            ts = np.stack([np.einsum("ij,ij->i", hn, tan), np.einsum("ij,ij->i", hn, bit),
                           np.einsum("ij,ij->i", hn, nor)], axis=1)
            nrm[yy, xx] = _unit_rows(ts)
            m, _g = coat(P)
            rough = np.array([MATERIALS[s][1] for s in m])
            band = np.array([pr.band_byte(MATERIALS[s][0]) for s in m])
        else:
            rough = np.full(len(P), MATERIALS[mat][1])
            band = np.full(len(P), pr.band_byte(MATERIALS[mat][0]))
        ao = np.einsum("nk,nk->n", bb, ao_by_piece[p.name][p.T[tt]])
        orm[yy, xx, 0] = ao
        orm[yy, xx, 1] = rough
        orm[yy, xx, 2] = band / 255.0
    nrm = pbk.dilate(nrm, filled)
    orm = pbk.dilate(orm, filled)
    pbk.save_png(os.path.join(out_dir, "horse_normal.png"), pbk.to_u8(nrm * 0.5 + 0.5))
    o8 = pbk.to_u8(orm)
    o8[..., 2] = np.round(orm[..., 2] * 255.0).astype(np.uint8)
    pbk.save_png(os.path.join(out_dir, "horse_orm.png"), o8)
    return names


def vertex_ao(V, N, occ_V, occ_T, reach=0.25, rays=16):
    """Per vertex: the share of cosine rays that leave unoccluded within ``reach`` (Blender's BVH)."""
    import people_bake as pbk
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    tree = BVHTree.FromPolygons([tuple(map(float, v)) for v in occ_V], [tuple(map(int, t)) for t in occ_T],
                                all_triangles=True)
    H = pbk.hemisphere(rays)
    out = np.ones(len(V))
    for i in range(len(V)):
        n = N[i]
        a = np.array([1.0, 0.0, 0.0]) if abs(n[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
        t = _unit(np.cross(n, a))
        bt = np.cross(n, t)
        o = Vector((V[i] + n * 2e-3).tolist())
        occ = 0.0
        for d in H[:, 0:1] * t + H[:, 1:2] * bt + H[:, 2:3] * n:
            hit = tree.ray_cast(o, Vector(d.tolist()), reach)
            if hit[0] is not None:
                occ += 1.0 - hit[3] / reach
        out[i] = 1.0 - occ / rays
    return np.clip(0.35 + 0.65 * out, 0.0, 1.0)


# ---- the build ---------------------------------------------------------------------------------------------------
DETAIL = {"head": 0.7, "lower_legs": 0.35}    # the collapse keeps more of the head and of the joints below the body


def body_detail(V, h=HORSE):
    """Per vertex 0..1: where the decimation keeps more (the head and the ears; the knees, hocks, fetlocks, hooves)."""
    head = sstep(V[:, 1], h["poll"][1] - 0.20, h["poll"][1] - 0.05) * sstep(V[:, 2], 1.35, 1.5)
    legs = sstep(-V[:, 2], -0.62, -0.52)
    return np.maximum(DETAIL["head"] * head, DETAIL["lower_legs"] * legs)


def _decimated(V, T, budget, name, symmetric=True, detail=None):
    import people_outfit as po
    Vb = to_blender(V)
    Vd, Td, _m, _uv = po.decimate(Vb, flip(T), np.zeros(len(T), np.int32), budget, name, symmetric=symmetric,
                                  detail=detail)
    Vd = np.asarray(Vd, np.float64)
    return np.stack([Vd[:, 0], -Vd[:, 1], Vd[:, 2]], axis=1), flip(np.asarray(Td, np.int64))


def _unwrap01(V, T, name):
    import bpy
    import people_outfit as po
    bpy.context.view_layer.update()
    return flip(_from_main(po.unwrap(to_blender(V), flip(T), name)))


def _nearest_weights(piece, body):
    from scipy.spatial import cKDTree
    _d, k = cKDTree(body.V).query(piece.V)
    piece.idx, piece.w = body.idx[k].copy(), body.w[k].copy()


def build_pieces(h=HORSE, verbose=True):
    t0 = time.time()
    V, T = polygonize(lambda P: horse_sdf(P, h), HORSE_BOX, BODY_STEP_M)
    V, T = weld(V, T)
    V = taubin(V, T, SMOOTH_ITERS)
    dense_n = vertex_normals_np(to_blender(V), flip(T))
    dense = (to_blender(V), dense_n)
    if verbose:
        log("field: %d vertices, %d triangles (%.1f s)" % (len(V), len(T), time.time() - t0))
    stats_dense = mesh_stats(T)
    bV, bT = _decimated(V, T, BODY_TRIS, "horse_body", detail=body_detail(V, h))
    body = Piece("body", bV, bT, _unwrap01(bV, bT, "horse_body_uv"))
    body.idx, body.w = weights(bV, h)
    sV, sT = polygonize(lambda P: saddle_sdf(P, h), SADDLE_BOX, SADDLE_STEP_M)
    sV, sT = weld(sV, sT)
    sV = taubin(sV, sT, 4)
    sV, sT = _decimated(sV, sT, SADDLE_TRIS, "saddle")
    saddle = Piece("saddle", sV, sT, _unwrap01(sV, sT, "saddle_uv"))
    mane_p = mane(h)
    tail_p = tail(h)
    cap = caparison(h)
    straps, irons = bridle_and_reins(h)
    for p in (mane_p, saddle, cap, straps, irons):
        _nearest_weights(p, body)
    if verbose:
        log("pieces built (%.1f s)" % (time.time() - t0))
    return {"body": body, "mane": mane_p, "tail": tail_p, "saddle": saddle, "caparison": cap, "straps": straps,
            "irons": irons}, dense, stats_dense


def vertex_normals_np(V, T):
    n = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    out = np.zeros_like(V)
    for k in range(3):
        np.add.at(out, T[:, k], n)
    return _unit_rows(out)


def combine(pieces, names):
    V, T, UV, I, W, n = [], [], [], [], [], 0
    for nm in names:
        p = pieces[nm]
        V.append(p.V)
        T.append(p.T + n)
        UV.append(p.uv_atlas)
        I.append(p.idx)
        W.append(p.w)
        n += len(p.V)
    return np.concatenate(V), np.concatenate(T), np.concatenate(UV), np.concatenate(I), np.concatenate(W)


BARE = ("body", "mane", "tail")
TACKED = ("body", "mane", "tail", "caparison", "saddle", "straps", "irons")
GLB, POSES_GLB = "horse.glb", "horse_poses.glb"


def make_armature(name, coll, h=HORSE):
    import bpy
    J = joints(h)
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    coll.objects.link(ob)
    vl = bpy.context.view_layer
    vl.update()
    for o in vl.objects:
        if o is not None:
            o.select_set(False)
    vl.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for b in BONES:
        eb = arm.edit_bones.new(b)
        hd, tl = to_blender(np.array([J[b][0], J[b][1]]))
        eb.head = tuple(hd)
        eb.tail = tuple(tl)
        eb.roll = 0.0
        eb.use_deform = True
    for b in BONES:
        if PARENTS[b]:
            arm.edit_bones[b].parent = arm.edit_bones[PARENTS[b]]
            arm.edit_bones[b].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in ob.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return ob


def skinned(name, V, T, UV, I, W, arm, coll, mat):
    import people_outfit as po
    ob = po.mesh_object(name, to_blender(V), flip(T), None, flip(UV), coll)
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    for b in BONES:
        ob.vertex_groups.new(name=b)
    for vi in range(len(V)):
        for j in range(4):
            if W[vi, j] > 0.0:
                ob.vertex_groups[int(I[vi, j])].add([vi], float(W[vi, j]), "REPLACE")
    ob.parent = arm
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = arm
    return ob


def pose_basis(arm, pose):
    """{bone: (w, x, y, z)} Blender pose-bone rotations of a pose: each joint's rotation about the lateral axis in the
    bone's own rest frame (the (x, u, z) frame's rotation by a is Blender's by -a: the forward axis is flipped)."""
    out = {}
    for b in BONES:
        a = pose.get(b, 0.0)
        if not a:
            continue
        R = np.array([list(r) for r in arm.data.bones[b].matrix_local.to_3x3()], np.float64)
        Rl = R.T @ _rot_x(-a) @ R
        from mathutils import Matrix
        q = Matrix(Rl.tolist()).to_quaternion()
        out[b] = (q.w, q.x, q.y, q.z)
    return out


def check_poses(pieces, h=HORSE):
    """Each gait extreme on the bare body: its volume against the rest's, its lowest point, every hoof's sole height."""
    body = pieces["body"]
    v0 = volume(body.V, body.T)
    out = {}
    J = joints(h)
    for name in POSE_ORDER:
        M = pose_matrices(POSES[name], h)
        Pp = skin(body.V, body.idx, body.w, M)
        soles = {}
        for leg in LEGS:
            end, side = leg.split("_")
            b = "%s_foot_%s" % (end, side)
            tip = (M[b] @ np.append(J[b][1], 1.0))[:3]
            soles[leg] = r6(tip[2])
        out[name] = {"volume_ratio": r6(volume(Pp, body.T) / v0), "lowest_m": r6(Pp[:, 2].min()), "soles_m": soles}
    return out


def export_poses(path, arm, coll):
    import bpy
    from mathutils import Quaternion
    verts, faces = [], []
    for i, b in enumerate(BONES):
        hd = np.asarray(arm.data.bones[b].head_local)
        verts += [tuple(hd), tuple(hd + np.array([0.002, 0.0, 0.0])), tuple(hd + np.array([0.0, 0.0, 0.002]))]
        faces.append((3 * i, 3 * i + 1, 3 * i + 2))
    me = bpy.data.meshes.new("PosesAnchor")
    me.from_pydata(verts, [], faces)
    me.update()
    anchor = bpy.data.objects.new("PosesAnchor", me)
    coll.objects.link(anchor)
    for i, b in enumerate(BONES):
        anchor.vertex_groups.new(name=b).add([3 * i, 3 * i + 1, 3 * i + 2], 1.0, "REPLACE")
    anchor.parent = arm
    anchor.modifiers.new("Armature", "ARMATURE").object = arm
    arm.animation_data_create()
    for name in POSE_ORDER:
        act = bpy.data.actions.new(name)
        arm.animation_data.action = act
        basis = pose_basis(arm, POSES[name])
        for pb in arm.pose.bones:
            pb.rotation_quaternion = Quaternion(basis.get(pb.name, (1.0, 0.0, 0.0, 0.0)))
            pb.keyframe_insert("rotation_quaternion", frame=0)
        act.use_fake_user = True
        tr = arm.animation_data.nla_tracks.new()
        tr.name = name
        tr.strips.new(name, 0, act)
        arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        o.select_set(False)
    arm.select_set(True)
    anchor.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_skins=True, export_influence_nb=4, export_all_influences=False,
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_force_sampling=True, export_frame_step=1,
                              export_optimize_animation_size=False, export_reset_pose_bones=True,
                              export_morph=False, export_materials="NONE", export_yup=True,
                              export_def_bones=False, export_leaf_bone=False, export_extras=False,
                              export_cameras=False, export_lights=False, export_rest_position_armature=True)
    bpy.data.objects.remove(anchor, do_unlink=True)


def gd(p):
    """(x, u, z) to the game's frame (glTF / Godot: x left, y up, z forward)."""
    return [r6(p[0]), r6(p[2]), r6(p[1])]


def build(out_dir, work_dir, h=HORSE):
    import bpy
    import people_outfit as po
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    pieces, dense, stats_dense = build_pieces(h)
    body = pieces["body"]
    boundary, nonmanifold, _e = mesh_stats(body.T)
    if boundary or nonmanifold or not directed_edges_ok(body.T):
        raise SystemExit("quadruped: the horse's body is not closed and manifold (%d open, %d non-manifold edges)" % (
            boundary, nonmanifold))
    # the atlas's UVs
    for nm, p in pieces.items():
        rect = PIECE_RECT[nm]
        p.uv01 = p.uv
        sub = SADDLE_U if nm == "saddle" else (STRAP_U if nm == "straps" else None)
        p.uv_atlas = rect_uv(p.uv, rect, sub)
    # the body's tangent frames as Blender computes and exports them (the normal map's frame)
    tan, sgn, nor = (flip(a) for a in po.tangents(to_blender(body.V), flip(body.T), flip(body.uv_atlas)))
    body.tan, body.sgn, body.nor = tan, sgn, nor          # Blender's frame (the dense normals are looked up there)
    # ambient occlusion: the body by itself (the bare horse), the tack over the body
    bn = vertex_normals_np(to_blender(body.V), flip(body.T))
    ao = {"body": vertex_ao(to_blender(body.V), bn, to_blender(body.V), body.T)}
    occV = np.concatenate([body.V, pieces["saddle"].V, pieces["caparison"].V])
    occT = np.concatenate([body.T, pieces["saddle"].T + len(body.V),
                           pieces["caparison"].T + len(body.V) + len(pieces["saddle"].V)])
    for nm in ("saddle", "caparison"):
        p = pieces[nm]
        pn = vertex_normals_np(to_blender(p.V), flip(p.T))
        ao[nm] = vertex_ao(to_blender(p.V), pn, to_blender(occV), occT)
    for nm in ("mane", "tail", "straps", "irons"):
        ao[nm] = np.full(len(pieces[nm].V), 0.9)
    os.makedirs(out_dir, exist_ok=True)
    bake_pieces = [pieces[n] for n in ("body", "caparison", "saddle", "mane", "tail", "straps", "irons")]
    bake(bake_pieces, dense, out_dir, ao)
    # the scene
    coll = bpy.data.collections.new("Horse")
    bpy.context.scene.collection.children.link(coll)
    arm = make_armature("Horse", coll, h)
    mat = bpy.data.materials.new("horse")
    objs = [arm]
    counts = {}
    for name, parts in (("horse", BARE), ("horse_tacked", TACKED)):
        V, T, UV, I, W = combine(pieces, parts)
        if len(T) > TRIS_MAX:
            raise SystemExit("quadruped: %s has %d triangles, over %d" % (name, len(T), TRIS_MAX))
        counts[name] = int(len(T))
        objs.append(skinned(name, V, T, UV, I, W, arm, coll, mat))
    po.export(os.path.join(out_dir, GLB), objs)
    export_poses(os.path.join(out_dir, POSES_GLB), arm, coll)
    J = joints(h)
    seat = saddle_seat(h)
    eyes = eye_centres(h)
    info = {
        "bones": list(BONES), "parents": dict(PARENTS),
        "triangles": {**counts, **{n: int(len(p.T)) for n, p in pieces.items()}},
        "vertices": {n: int(len(p.V)) for n, p in pieces.items()},
        "body_closed": True,
        "measures": {"withers_m": r6(max(body.V[np.abs(body.V[:, 1] - 0.42) < 0.05][:, 2])),
                     "length_m": r6(body.V[:, 1].max() - body.V[:, 1].min()),
                     "height_m": r6(body.V[:, 2].max()), "width_m": r6(body.V[:, 0].max() - body.V[:, 0].min())},
        "landmarks": {"saddle_seat": {"bone": "spine_01", "position": gd(seat)},
                      "bit_l": gd(_on_head(0.88, math.radians(100), 0.02, h)[0]),
                      "bit_r": gd(_on_head(0.88, math.radians(260), 0.02, h)[0]),
                      "eyes": [gd(e) for e in eyes],
                      "soles": {leg: gd(J["%s_foot_%s" % tuple(leg.split("_"))][1]) for leg in LEGS}},
        "poses": check_poses(pieces, h), "pose_order": list(POSE_ORDER),
        "atlas": {"albedo_px": ALBEDO_PX, "normal_px": NORMAL_PX, "orm_px": ORM_PX, "rects": RECTS,
                  "materials": {k: {"band": b, "roughness": r} for k, (b, r) in MATERIALS.items()},
                  "albedo_alpha": "the strands' coverage (the mane and the tail): alpha scissor"},
        "preview_palette": {k: list(v) for k, v in PREVIEW_PALETTE.items()},
    }
    info["dense"] = {"step_m": BODY_STEP_M, "boundary_edges": stats_dense[0], "nonmanifold_edges": stats_dense[1]}
    if work_dir:
        os.makedirs(work_dir, exist_ok=True)
        with open(os.path.join(work_dir, "horse_info.json"), "w", encoding="utf-8") as fh:
            json.dump(info, fh, indent=1, sort_keys=True)
    log("horse: %s triangles; %.1f s" % (counts, time.time() - t0))
    return info


if __name__ == "__main__":
    import sys as _sys
    build(_sys.argv[1] if len(_sys.argv) > 1 else os.getcwd(), _sys.argv[2] if len(_sys.argv) > 2 else "")

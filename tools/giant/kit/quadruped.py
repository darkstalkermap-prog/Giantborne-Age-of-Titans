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
(``python quadruped.py horse <out dir> <work dir>``, run by build_people.py --horse) adds the mane, the forelock and the
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
    # P65b: the falloff between a leg's own bones (WEIGHT_SIGMA_M times this): the knee and the hock folded in a smooth
    # curve over 12 cm at the gallop's tuck (a rubber leg); a joint's crease is nearer 7 cm
    leg_sigma=0.6,
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
    out.add(sd_ellipsoid(P, (0, 0.45, 1.19), (0.165, 0.30, 0.25)), 0.10)
    for s in (1.0, -1.0):
        out.add(sd_ellipsoid(P, (0.085 * s, 0.655, 1.13), (0.085, 0.10, 0.13)), 0.06)
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


def drop_slivers(V, T, min_area=1e-9):
    """A collapse can leave a sliver (three corners on a line) or a fin (two triangles on the same corners), which the
    glTF export drops (and the mesh opens): each sliver's shortest edge is collapsed (its two corners merged) and the
    triangles that collapse with it dropped; a fin is dropped whole."""
    V = np.asarray(V, np.float64).copy()
    T = np.asarray(T, np.int64)
    for _ in range(20):
        area = 0.5 * np.linalg.norm(np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]]), axis=1)
        bad = np.nonzero(area < min_area)[0]
        if not len(bad):
            break
        for t in bad:
            a, b, c = T[t]
            e = [(np.linalg.norm(V[a] - V[b]), a, b), (np.linalg.norm(V[b] - V[c]), b, c),
                 (np.linalg.norm(V[c] - V[a]), c, a)]
            _l, i, j = min(e)
            T = np.where(T == j, i, T)
        T = T[(T[:, 0] != T[:, 1]) & (T[:, 1] != T[:, 2]) & (T[:, 0] != T[:, 2])]
    # a pair of triangles on the same three corners (a fin, back to back) is dropped whole
    _u, inv, cnt = np.unique(np.sort(T, axis=1), axis=0, return_inverse=True, return_counts=True)
    T = T[cnt[inv.ravel()] == 1]
    used = np.unique(T.ravel())
    remap = -np.ones(len(V), np.int64)
    remap[used] = np.arange(len(used))
    return V[used], remap[T]


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
    sp = h.get("spine", ((0, -0.52, 1.30), (0, -0.16, 1.33), (0, 0.24, 1.35), (0, 0.62, 1.32)))
    J = {"Root": ((0, 0, 0), (0, h.get("root_len", 0.30), 0)),
         "pelvis": (sp[0], sp[1]),
         "spine_01": (sp[1], sp[2]),
         "spine_02": (sp[2], sp[3]),
         "neck": (sp[3], h["neck_top"]),
         "head": (h["neck_top"], h["muzzle"]),
         "jaw": (h["jaw_joint"], h["chin"]),
         "tail_01": (h["tail_root"], h["tail_mid"]),
         "tail_02": (h["tail_mid"], h["tail_end"])}
    for side, m in (("l", lambda p: p), ("r", _mirror)):
        fore = [h["shoulder"], h["elbow"], h["knee"], h["fore_fetlock"]]
        fore_toe = (h["fore_coronet"][0], h["fore_coronet"][1] + h.get("toe_m", 0.03), 0.0)
        hind = [h["hip"], h["stifle"], h["hock"], h["hind_fetlock"]]
        hind_toe = (h["hind_coronet"][0], h["hind_coronet"][1] + h.get("toe_m", 0.03), 0.0)
        for end, pts, toe in (("fore", fore, fore_toe), ("hind", hind, hind_toe)):
            seq = [m(p) for p in pts] + [m(toe)]
            for i, part in enumerate(LEG_BONES):
                J["%s_%s_%s" % (end, part, side)] = (seq[i], seq[i + 1])
    return {b: (np.asarray(J[b][0], np.float64), np.asarray(J[b][1], np.float64)) for b in BONES}


def _seg_dist(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1), t


WEIGHT_SIGMA_M = 0.060             # the falloff of a bone's weight beyond the nearest bone's distance
WEIGHT_REACH = 3.5                 # bones further than nearest + REACH x SIGMA take nothing


def core_sdf(P, h=HORSE):
    """The body without its limbs (the trunk's core, the neck, the head, the dock): what stays on the spine."""
    return smin(smin(horse_trunk(P, h, limbs=False), horse_head(P, h), 0.07), horse_dock(P, h), 0.05)


# a vertex this far outside the core is wholly its leg's (from the first, none). P63: from (0.004, 0.07) with a 3 cm
# falloff, which stretched the skin over the shoulder and the stifle at the gallop's extremes (the 99th percentile of
# the edges there 4.2 and 3.6 times their rest length); a wider blend and a 6 cm falloff: 1.5 and 1.6 (STRETCH_REGIONS)
LIMB_BLEND_M = (-0.02, 0.30)


def _falloff(D, k=1.0):
    dmin = D.min(axis=1, keepdims=True)
    sig = WEIGHT_SIGMA_M * k
    W = np.where(D < dmin + WEIGHT_REACH * sig, np.exp(-(D - dmin) / sig), 0.0)
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
    k = h.get("scale", 1.0)                       # the animal's size against the horse's (the falloffs scale with it)
    D = np.full((n, len(BONES)), np.inf)
    side = np.where(P[:, 0] >= 0.0, "l", "r")
    end = np.where(P[:, 1] > h.get("split_u", -0.05), "fore", "hind")
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
            below = (P - a) @ fr[2] < -h.get("jaw_below_m", 0.07)   # under the face's axis (the front row: up-forward)
            d = np.where(below & (d < 0.12 * k), d, np.inf)
        D[:, i] = d
    Dl = np.where(leg_bone[None, :], D, np.inf)
    Dc = np.where(leg_bone[None, :], np.inf, D)
    Dc[:, 0] = np.inf
    core = h["core"](P) if "core" in h else core_sdf(P, h)
    f = sstep(core, LIMB_BLEND_M[0] * k, LIMB_BLEND_M[1] * k)[:, None]
    W = f * _falloff(Dl, k * h.get("leg_sigma", 1.0)) + (1.0 - f) * _falloff(Dc, k)
    if "jaw_share" in h:                           # (P65c, the wolf) the mouth's gap parts the jaw from the head
        js, near = h["jaw_share"](P)
        one = np.zeros_like(W)
        one[:, BONES.index("jaw")] = js
        one[:, BONES.index("head")] = 1.0 - js
        W = W * (1.0 - near[:, None]) + one * near[:, None]
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
# The horse's build: Blender's decimation, unwrap and glTF export (``python quadruped.py horse <out dir> <work dir>``)
# ======================================================================================================================
BODY_STEP_M = 0.012                # the field's grid
SMOOTH_ITERS = 6                   # Taubin passes on the dense mesh
BODY_TRIS = 4670                   # the body after the collapse (closed, manifold; P63 4,750: 80 to the saddle)
TRIS_MAX = 6000                    # a horse, bare or tacked: one mesh, one surface (plan §3.14)
SADDLE_TRIS = 400
SADDLE_STEP_M = 0.006
SADDLE_SMOOTH = 14
CAPARISON_OFF_M = 0.016            # the housing's cloth over the coat
SADDLE_IN_M = 0.024                # the saddle's underside over the coat (over the housing's cloth)
STRAP_W_M, STRAP_OFF_M = 0.022, 0.008
ALBEDO_PX, NORMAL_PX, ORM_PX = 512, 256, 256
# the atlas's rectangles (u0, v0, u1, v1; v up)
RECTS = {"body": (0.0, 0.25, 0.75, 1.0), "caparison": (0.0, 0.0, 0.75, 0.25), "hair": (0.75, 0.75, 1.0, 1.0),
         "leather": (0.75, 0.5, 1.0, 0.75), "metal": (0.75, 0.25, 1.0, 0.375), "eye": (0.75, 0.375, 1.0, 0.5)}
# materials: the band of the palette mask (people_roles.BANDS: the person shader's) and roughness; the coat's own
# texels choose among coat (skin band: the coat colour), points (hair band: the mane's colour), white, hoof and eye
MATERIALS = {"coat": ("skin", 0.55), "points": ("hair", 0.58), "white": ("none", 0.6), "hoof": ("none", 0.42),
             "eye": ("none", 0.36), "hair": ("hair", 0.6), "leather": ("none", 0.55), "metal": ("none", 0.35),
             "faction": ("faction", 0.85)}
PIECE_MATERIAL = {"body": "coat", "eyes": "eye", "mane": "hair", "tail": "hair", "saddle": "leather", "straps": "leather",
                  "irons": "metal", "caparison": "faction"}
PIECE_RECT = {"body": "body", "eyes": "eye", "mane": "hair", "tail": "hair", "saddle": "leather", "straps": "leather",
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


MANE_STATIONS = 13


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
    # (side, length, segments, lift off the coat, shift along the crest): the mane falls to the right in two layers
    # (the outer one standing off the inner, for volume); on the left a fringe half as long shows over the crest
    for side, length, nseg, lift, shift in ((-1.0, 1.0, 4, 0.012, 0.0), (-1.0, 0.85, 3, 0.030, 0.5),
                                            (1.0, 0.55, 3, 0.014, 0.25)):
        for i, t in enumerate(ts):
            L = (0.17 + 0.10 * math.sin(math.pi * min(1.0, t * 1.1))) * length
            if t > 0.93:
                L *= 0.6
            j = min(i + shift, len(ts) - 1.0)
            j0 = int(j)
            fj = j - j0
            j1 = min(j0 + 1, len(ts) - 1)
            c = axis[j0] * (1 - fj) + axis[j1] * fj
            up = _unit(crest[j0] * (1 - fj) + crest[j1] * fj - c)
            lat = np.array([side, 0.0, 0.0])
            rows = []
            for k in range(nseg + 1):
                f = k / nseg
                ang = f * (1.75 if length > 0.7 else 1.25) * (L / 0.27)
                d = _unit(up * math.cos(ang) + lat * math.sin(ang))
                p = surface_point(c, d) + d * (lift + 0.012 * f) + np.array([0, 0, -0.02 * f * f])
                rows.append(p)
            rows = np.array(rows)
            w = 0.11 if length > 0.7 else 0.09
            left = rows - tang[i] * w * 0.5
            right = rows + tang[i] * w * 0.5
            vs = np.linspace(1.0, 0.0, len(rows))
            parts.append(strip(left, right, vs))
    # the crest: an upright card along the top
    up_all = crest + _unit_rows(crest - axis) * 0.085
    parts.append(strip(crest - _unit_rows(crest - axis) * 0.005, up_all, np.linspace(0.05, 0.95, len(crest))))
    parts[-1] = (parts[-1][0], parts[-1][1], parts[-1][2][:, :, ::-1])     # its strands run across the strip
    # the forelock: two cards from between the ears down the forehead
    poll, muz = np.array(h["poll"]), np.array(h["muzzle"])
    ax = muz - poll
    front = frame_from(ax)[2]
    for s in (-0.024, 0.0, 0.024):
        rows = []
        for k in range(4):
            f = k / 3.0
            q = poll + ax * (0.02 + 0.32 * f) + np.array([s * (1 + f), 0, 0])
            rows.append(surface_point(q - front * 0.06, front) + front * (0.012 + 0.006 * (1 - f)))
        rows = np.array(rows)
        parts.append(strip(rows - np.array([0.03, 0, 0]), rows + np.array([0.03, 0, 0]), np.linspace(1.0, 0.0, 4)))
    V, T, UV = merge_parts(parts)
    return Piece("mane", V, T, UV)


def _unit_rows(A):
    return A / np.maximum(np.linalg.norm(A, axis=1, keepdims=True), 1e-12)


TAIL_CARDS, TAIL_SEGMENTS = 8, 7


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
    width = 0.07 + 0.13 * np.sin(np.pi * np.clip(s * 0.7 + 0.08, 0, 1)) + 0.04 * s
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


# ---- the eyes: an almond with its lids ---------------------------------------------------------------------------
EYE_POINTS = 10                    # the almond's outline
EYE_LENGTH_M, EYE_WIDTH_M = 0.033, 0.017
EYE_BULGE_M = 0.007                # the eyeball stands this far out of the outline at its middle
LID_M = 0.009                      # the lids' rim: this far out from the outline, the upper one thicker


def eyes(h=HORSE, orbits=None, size=1.0, fn=None, tilt=0.25, reach=0.6):
    """Both eyes: an almond-shaped eyeball (a fan from its raised middle to the outline, pointed at the corners, the
    long axis along the face a little tilted) set in the orbit's surface, and a rim of lids round it (the upper lid
    heavier and standing further out). UVs: the eye tile (v 0..0.6 the eyeball, 0.6..1 the lids)."""
    fn = fn or horse_sdf
    poll, muz = np.array(h["poll"]), np.array(h["muzzle"])
    ax = muz - poll
    fr = frame_from(ax)
    parts = []
    for side in (1.0, -1.0):
        if orbits is None:
            orb = poll + ax * 0.27 + fr[2] * 0.03 + np.array([0.082 * side, 0, 0])
            out = _unit(np.array([side, 0.0, 0.0]) + 0.35 * fr[2] + 0.25 * fr[1])
        else:
            orb, out = orbits(side)
        c = surface_point(orb, out, fn, reach)
        n = field_normal(c, fn)
        a = fr[1] - n * float(fr[1] @ n)             # along the face (down-forward), in the surface's plane
        a = _unit(a - tilt * fr[2])                  # the outer corner a little up
        b = _unit(np.cross(n, a))
        if float(b @ fr[2]) < 0:
            b = -b                                   # b toward the face's front (up): the upper lid
        V, UV = [c + n * EYE_BULGE_M * size], [(0.5, 0.05)]
        ring, lid = [], []
        for k in range(EYE_POINTS):
            th = 2.0 * math.pi * k / EYE_POINTS
            x = math.cos(th) * EYE_LENGTH_M * size
            y = math.sin(th) * EYE_WIDTH_M * size * (1.0 - 0.55 * math.cos(th) ** 2) * (1.15 if math.sin(th) > 0 else 1.0)
            q = c + a * x + b * y
            q = project_out(q, 0.0015 * size, fn)
            ring.append(q)
            upper = max(0.0, math.sin(th))
            r = 1.0 + (LID_M + 0.006 * upper) * size / max(math.hypot(x, y), 1e-6)
            ql = c + (a * x + b * y) * r
            ql = project_out(ql, (0.002 + 0.0035 * upper) * size, fn)
            lid.append(ql)
        V += ring + lid
        for k in range(EYE_POINTS):
            UV.append((0.5 + 0.45 * math.cos(2.0 * math.pi * k / EYE_POINTS), 0.55))
        for k in range(EYE_POINTS):
            UV.append((0.5 + 0.45 * math.cos(2.0 * math.pi * k / EYE_POINTS), 0.95))
        T, TUV = [], []
        for k in range(EYE_POINTS):
            i, j = 1 + k, 1 + (k + 1) % EYE_POINTS
            T.append((0, i, j))
            li, lj = i + EYE_POINTS, j + EYE_POINTS
            T += [(i, li, lj), (i, lj, j)]
        T = np.array(T)
        if side < 0:
            T = T[:, ::-1]
        UVa = np.array(UV)
        parts.append((np.array(V), T, UVa[T]))
    # wind each triangle outward (along the surface's normal)
    V, T, UV = merge_parts(parts)
    nrm = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    cen = V[T].mean(axis=1)
    outward = np.array([field_normal(q, fn) for q in cen])
    bad = np.einsum("ij,ij->i", nrm, outward) < 0
    T[bad] = T[bad][:, ::-1]
    UV[bad] = UV[bad][:, ::-1]
    return Piece("eyes", V, T, UV)


# ---- the tack ----------------------------------------------------------------------------------------------------
def saddle_sdf(P, h=HORSE):
    """A saddle over the housing: a shell of the trunk from SADDLE_IN_M out. P65a (P63's read as a flat leather slab):
    the seat dished (rising toward the pommel and the cantle from its lowest point at SEAT_U, where the rider's seat
    is measured: every term below is nought there), a raised pommel arching over the withers, a high curved cantle,
    rolled bars along the seat's edges, knee rolls at the flaps' front, thinner flaps, a rear skirt under the cantle;
    the girth under the belly."""
    b = horse_trunk(P, h)
    x, u, z = P[:, 0], P[:, 1], P[:, 2]
    ax = np.abs(x)
    pommel = 0.075 * np.exp(-((u - 0.355) / 0.035) ** 2) * np.exp(-(x / 0.065) ** 2)
    cantle = 0.078 * np.exp(-((u + 0.065) / 0.030) ** 2) * sstep(-ax, -0.17, -0.08)
    dish = 0.030 * np.clip((u - SEAT_U) / 0.18, 0.0, 1.0) ** 2 + 0.034 * np.clip((SEAT_U - u) / 0.20, 0.0, 1.0) ** 2
    dish = dish * (1.0 - sstep(ax, 0.10, 0.15))
    bars = 0.010 * sstep(ax, 0.07, 0.105) * (1.0 - sstep(ax, 0.13, 0.16)) * sstep(u, -0.05, 0.0) * sstep(-u, -0.36, -0.31)
    knee = 0.018 * np.exp(-((u - 0.31) / 0.028) ** 2) * sstep(ax, 0.13, 0.17) * sstep(-z, -1.34, -1.27)
    thin = 0.012 * sstep(ax, 0.15, 0.20)
    thick = 0.026 + pommel + cantle + dish + bars + knee - thin
    shell = np.maximum(b - (SADDLE_IN_M + thick), SADDLE_IN_M - b)
    # the seat's outline: from behind the withers to behind the cantle, down the sides to the flaps and the rear skirt
    region = np.maximum(-0.125 - u, u - 0.40)
    flap = sstep(u, 0.07, 0.11) * sstep(-u, -0.30, -0.26) * sstep(ax, 0.10, 0.14)
    skirt = sstep(u, -0.115, -0.09) * sstep(-u, -0.06, -0.03) * sstep(ax, 0.10, 0.14)
    zlow = 1.30 - 0.6 * np.maximum(0.0, ax - 0.12) - (1.30 - 1.15) * flap - (1.30 - 1.235) * skirt
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
    # the stirrup leathers from the saddle's sides, over the housing's widest line (outside its skirt), down to the irons
    tops = {}
    x_out = float(np.abs(caparison(h).V[:, 0]).max()) + 0.012          # outside the housing's widest line
    for s in (1, -1):
        top = surface_point(np.array([0.0, 0.20, 1.20]), (s, 0, 0.35), lambda P: saddle_sdf(P, h), 0.6)
        tops[s] = np.array([x_out * s, top[1], top[2]])
        mid = np.array([x_out * s, top[1], 1.16])
        bot = np.array([x_out * s, top[1], 0.99])
        pts = [top, top + (mid - top) * 0.5 + np.array([0.012 * s, 0, 0]), mid, bot]
        parts.append(ribbon(pts, [np.array([s, 0, 0.0])] * 4, 0.028))
    straps = Piece("straps", *merge_parts(parts))
    # metal: the bit rings and the stirrup irons (flat loops)
    mparts = []
    for s in (1, -1):
        c = bit[s] + np.array([0.008 * s, 0, 0])
        ring = [c + 0.021 * np.array([0, math.cos(a), math.sin(a)]) for a in np.linspace(0, 2 * math.pi, 9)]
        mparts.append(ribbon(ring, [np.array([s, 0, 0.0])] * 9, 0.006))
        top = np.array([tops[s][0], tops[s][1], 0.99])
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
    n = 60
    cen = (np.arange(n) + 0.5 + 0.4 * (rng.random(n) - 0.5)) / n
    wid = (0.65 + 0.35 * rng.random(n)) / n
    lng = 0.86 + 0.14 * rng.random(n)
    val = 0.72 + 0.28 * rng.random(n)
    ph = rng.random(n) * 6.28
    cov = np.zeros_like(s)
    alb = np.zeros_like(s)
    for j in range(n):
        c = cen[j] + 0.012 * np.sin(t * 7.0 + ph[j])
        a = np.exp(-((s - c) / wid[j]) ** 2) * sstep(t, 1.0 - lng[j], 1.0 - lng[j] + 0.15)
        alb = alb + a * val[j]
        cov = 1.0 - (1.0 - cov) * (1.0 - a)
    cov = np.maximum(cov, sstep(t, 0.30, 0.70))
    grey = np.clip(alb / np.maximum(1e-6, -np.log(np.maximum(1.0 - cov, 1e-4)) + 1e-6), 0.0, 1.0)
    grey = np.where(cov > 0.02, np.clip(0.55 + 0.45 * grey, 0, 1), 0.8)
    return grey, np.clip(cov * 1.15, 0.0, 1.0)


def coat_flow(P, across=25.0, along=3.0):
    """0..1 streaks of the coat's hair along its flow (from the head back along the neck and the trunk, down the legs
    below the body): value noise stretched along the flow, ``across`` cycles a metre across it."""
    import people_bake as pbk
    x, u, z = P[:, 0], P[:, 1], P[:, 2]
    legs = sstep(-z, -0.95, -0.80)
    trunk = pbk.vnoise(np.stack([x * across, u * along, z * across * 0.8], axis=1), 1.0, 17)
    down = pbk.vnoise(np.stack([x * across, u * across, z * along], axis=1), 1.0, 19)
    return trunk * (1.0 - legs) + down * legs


HAIR_NORMAL_AMP = 0.006            # the streaks' relief in the normal map (metres of height per unit of streak)


def coat(P, h=HORSE):
    """Per point (x, u, z) of the coat: (material, grey albedo): the coat (tinted by the palette's coat colour), the
    points below the knees and hocks and at the ears' tips (the mane's colour), a white left hind sock,
    the hooves, the eyes; the muzzle and the dock darker, the spine a little darker, the belly lighter."""
    import people_bake as pbk
    x, u, z = P[:, 0], P[:, 1], P[:, 2]
    n = len(P)
    noise = pbk.fbm(P, 7.0, 3)
    fine = pbk.fbm(P, 30.0, 5)
    grey = 0.88 + 0.09 * (noise - 0.5) + 0.04 * (fine - 0.5) + 0.05 * (coat_flow(P, 60.0) - 0.5)
    # a bay's shading: darker along the back and the croup, lighter on the lower flanks, the elbow and the stifle
    grey = grey - 0.05 * sstep(z, 1.15, 1.45) + 0.04 * sstep(-z, -1.05, -0.9) * sstep(z, 0.75, 0.9)
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
        d = np.sqrt((q @ fr[1] / 0.034) ** 2 + (q @ fr[2] / 0.024) ** 2 + (q @ fr[0] / 0.05) ** 2)
        grey = grey * (1.0 - 0.40 * sstep(-d, -1.9, -1.0))        # the bare dark skin round the eye
    return mat, np.clip(grey, 0.0, 1.0)


HOOF_RGB = np.array([0.30, 0.27, 0.24])
EYE_RGB = np.array([0.075, 0.050, 0.036])
LID_GREY = 0.42                    # the lids: the coat's colour (its band), darker
WHITE_RGB = np.array([0.95, 0.94, 0.90])
LEATHER_RGB = np.array([0.34, 0.22, 0.13])
# P65b: the saddle's panels (the flaps were plain leather): seams sewn along the seat's edge, round the flaps and across
# the cantle and the pommel, each a dark groove with a lighter stitched thread beside it (x, u, z rest metres; the
# line's coordinate, its value, the extent along it as (coordinate, low, high) bounds; None: the axis the stitches run
# along). The albedo's leather is about 8 mm a texel, so the thread reads as a dashed line, not single stitches.
SADDLE_SEAMS = (
    ("ax", 0.128, (("u", -0.04, 0.33),), "u"),                               # the seat's edge
    ("u", 0.088, (("ax", 0.13, 0.40), ("z", 0.0, 1.27)), "z"),                # the flap's front
    ("u", 0.285, (("ax", 0.13, 0.40), ("z", 0.0, 1.27)), "z"),                # the flap's back
    ("z", 1.18, (("ax", 0.13, 0.40), ("u", 0.088, 0.285)), "u"),             # the flap's bottom
    ("u", -0.085, (("ax", 0.0, 0.17),), "x"),                                 # across the cantle
    ("u", 0.325, (("ax", 0.0, 0.11),), "x"))                                  # across the pommel
SEAM_GROOVE_M = 0.004
SEAM_THREAD = (0.010, 0.0035, 0.03)       # the thread's offset from the groove, its half width, the stitches' period
THREAD_RGB = np.array([0.56, 0.45, 0.31])


def saddle_panels(P, col):
    """The saddle's albedo ``col`` (n, 3) at rest points P with its seams (SADDLE_SEAMS) drawn in."""
    x, u, z = P[:, 0], P[:, 1], P[:, 2]
    c = {"x": x, "ax": np.abs(x), "u": u, "z": z}
    out = col.copy()
    for axis, val, bounds, along in SADDLE_SEAMS:
        inside = np.ones(len(P), bool)
        for a, lo, hi in bounds:
            inside &= (c[a] >= lo) & (c[a] <= hi)
        d = c[axis] - val
        groove = np.exp(-(d / SEAM_GROOVE_M) ** 2) * inside
        out *= (1.0 - 0.45 * groove)[:, None]
        off, half, period = SEAM_THREAD
        thread = np.exp(-((np.abs(d) - off) / half) ** 2) * inside
        dash = 0.5 + 0.5 * np.cos(2.0 * np.pi * c[along] / period)
        t = np.clip(thread * (0.35 + 0.65 * dash), 0.0, 1.0)[:, None]
        out = out * (1.0 - 0.7 * t) + THREAD_RGB[None, :] * 0.7 * t
    return out
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
    dV, dN, _dT = dense
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
        elif mat == "eye":
            u, v = uvt[sel, 0], uvt[sel, 1]
            lidc = sstep(v, 0.62, 0.70)
            hl = np.exp(-(((u - 0.38) / 0.09) ** 2 + ((v - 0.22) / 0.12) ** 2))      # the sky's reflection
            ball = EYE_RGB[None, :] * (0.75 + 0.5 * v)[:, None] + hl[:, None] * np.array([0.10, 0.11, 0.12])
            col = ball * (1.0 - lidc[:, None]) + np.array([LID_GREY] * 3)[None, :] * lidc[:, None]
        elif mat == "faction":
            v = uvt[sel, 1]
            g = 0.88 - 0.30 * sstep(-v, -0.13, -0.10) + 0.08 * (sstep(v, 0.15, 0.16) - sstep(v, 0.18, 0.19))
            g = g - 0.20 * sstep(v, 0.965, 0.98)
            g = g * (1.0 + 0.05 * (pbk.fbm(P, 60.0, 7) - 0.5))
            col = np.repeat(g[:, None], 3, axis=1)
        else:
            base = LEATHER_RGB if mat == "leather" else METAL_RGB
            col = base[None, :] * (1.0 + 0.16 * (pbk.fbm(P, 40.0, 9) - 0.5))[:, None]
            if p.name == "saddle":
                col = saddle_panels(P, col)
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
            hn = dense_normal(dense, P, nor)
            ts = np.stack([np.einsum("ij,ij->i", hn, tan), np.einsum("ij,ij->i", hn, bit),
                           np.einsum("ij,ij->i", hn, nor)], axis=1)
            # the hair's direction: the streaks' slope along the texel's tangent and bitangent
            e = 0.004
            tx = np.stack([tan[:, 0], -tan[:, 1], tan[:, 2]], axis=1)
            bx = np.stack([bit[:, 0], -bit[:, 1], bit[:, 2]], axis=1)
            h0 = coat_flow(P)
            g1 = (coat_flow(P + tx * e) - h0) / e
            g2 = (coat_flow(P + bx * e) - h0) / e
            ts = ts - HAIR_NORMAL_AMP * np.stack([g1, g2, np.zeros_like(g1)], axis=1) * ts[:, 2:3]
            nrm[yy, xx] = _unit_rows(ts)
            m, _g = coat(P)
            rough = np.array([MATERIALS[s][1] for s in m])
            band = np.array([pr.band_byte(MATERIALS[s][0]) for s in m])
        else:
            rough = np.full(len(P), MATERIALS[mat][1])
            band = np.full(len(P), pr.band_byte(MATERIALS[mat][0]))
            if mat == "eye":
                # the lids are the coat's skin (its band, its roughness); the eyeball keeps its own
                lid = uvt[sel, 1] > 0.66
                band = np.where(lid, pr.band_byte("skin"), band)
                rough = np.where(lid, MATERIALS["coat"][1], rough)
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


DENSE_FACING_REACH_M = 0.03


def dense_normal(dense, P, Nlow):
    """The dense surface's normal (Blender's frame) for texels at P (x, u, z) whose low-mesh normal is Nlow (Blender's
    frame): at the nearest point on the dense mesh's triangles facing the texel's way, its vertex normals
    interpolated (P65a, as the people's bake since P59b: P61-P63 took the inverse-distance mean of the four nearest
    dense vertices, which can read a surface facing the other way where two lie close - the lips, an ear's hollow)."""
    import people_bake as pbk
    dV, dN, dT = dense
    tri, bar = pbk._nearest_on(dV, dT, to_blender(P), Nlow, DENSE_FACING_REACH_M)
    return _unit_rows(np.einsum("nk,nkj->nj", bar, dN[dT[tri]]))


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
DETAIL = {"head": 0.85, "lower_legs": 0.35}    # the collapse keeps more of the head and of the joints below the body


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
    dense = (to_blender(V), dense_n, flip(T))
    if verbose:
        log("field: %d vertices, %d triangles (%.1f s)" % (len(V), len(T), time.time() - t0))
    stats_dense = mesh_stats(T)
    bV, bT = _decimated(V, T, BODY_TRIS, "horse_body", detail=body_detail(V, h))
    body = Piece("body", bV, bT, _unwrap01(bV, bT, "horse_body_uv"))
    body.idx, body.w = weights(bV, h)
    sV, sT = polygonize(lambda P: saddle_sdf(P, h), SADDLE_BOX, SADDLE_STEP_M)
    sV, sT = weld(sV, sT)
    sV = taubin(sV, sT, SADDLE_SMOOTH)
    sV, sT = _decimated(sV, sT, SADDLE_TRIS, "saddle")
    saddle = Piece("saddle", sV, sT, _unwrap01(sV, sT, "saddle_uv"))
    mane_p = mane(h)
    eyes_p = eyes(h)
    tail_p = tail(h)
    cap = caparison(h)
    straps, irons = bridle_and_reins(h)
    for p in (mane_p, eyes_p, saddle, cap, straps, irons):
        _nearest_weights(p, body)
    if verbose:
        log("pieces built (%.1f s)" % (time.time() - t0))
    return {"body": body, "eyes": eyes_p, "mane": mane_p, "tail": tail_p, "saddle": saddle, "caparison": cap, "straps": straps,
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


BARE = ("body", "eyes", "mane", "tail")
TACKED = ("body", "eyes", "mane", "tail", "caparison", "saddle", "straps", "irons")
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


STRETCH_REGIONS = {"shoulder": ((0.35, 0.85), (0.85, 1.35)), "stifle": ((-0.75, -0.25), (0.75, 1.25))}   # (u, z)


def stretch(V, T, Pp, regions=STRETCH_REGIONS):
    """{region: the 99th percentile of the edges' posed over rest lengths there}."""
    E = np.unique(np.sort(np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), axis=1), axis=0)
    r = np.linalg.norm(Pp[E[:, 0]] - Pp[E[:, 1]], axis=1) / np.maximum(np.linalg.norm(V[E[:, 0]] - V[E[:, 1]], axis=1),
                                                                        1e-9)
    m = 0.5 * (V[E[:, 0]] + V[E[:, 1]])
    out = {}
    for k, ((u0, u1), (z0, z1)) in regions.items():
        sel = (m[:, 1] > u0) & (m[:, 1] < u1) & (m[:, 2] > z0) & (m[:, 2] < z1)
        out[k] = r6(np.percentile(r[sel], 99))
    return out


def check_poses(pieces, h=HORSE, poses=None, order=None):
    """Each gait extreme on the bare body: its volume against the rest's, its lowest point, every hoof's sole height,
    the skin's stretch over the shoulder and the stifle."""
    body = pieces["body"]
    v0 = volume(body.V, body.T)
    out = {}
    J = joints(h)
    poses, order = poses or POSES, order or POSE_ORDER
    for name in order:
        M = pose_matrices(poses[name], h)
        Pp = skin(body.V, body.idx, body.w, M)
        soles = {}
        for leg in LEGS:
            end, side = leg.split("_")
            b = "%s_foot_%s" % (end, side)
            tip = (M[b] @ np.append(J[b][1], 1.0))[:3]
            soles[leg] = r6(tip[2])
        out[name] = {"volume_ratio": r6(volume(Pp, body.T) / v0), "lowest_m": r6(Pp[:, 2].min()), "soles_m": soles,
                     "stretch_p99": stretch(body.V, body.T, Pp, h.get("stretch_regions", STRETCH_REGIONS))}
    return out


def export_poses(path, arm, coll, poses=None, order=None):
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
    poses, order = poses or POSES, order or POSE_ORDER
    for name in order:
        act = bpy.data.actions.new(name)
        arm.animation_data.action = act
        basis = pose_basis(arm, poses[name])
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
    for nm in ("mane", "tail", "straps", "irons", "eyes"):
        ao[nm] = np.full(len(pieces[nm].V), 0.9)
    os.makedirs(out_dir, exist_ok=True)
    bake_pieces = [pieces[n] for n in ("body", "caparison", "saddle", "mane", "tail", "straps", "irons", "eyes")]
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
        "stirrups": {"irons_x_min_m": r6(np.abs(pieces["irons"].V[pieces["irons"].V[:, 2] < 1.0][:, 0]).min()),
                     "housing_x_max_m": r6(np.abs(pieces["caparison"].V[:, 0]).max())},
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


# ======================================================================================================================
# The wolf (P63): the same kit on a wolf's anatomy, its coat, its fur (cards and the shell's mesh and map)
# ======================================================================================================================
# A grey wolf of 0.80 m at the withers (the box rig's 0.9 m wolf: tools/builders/wolf.gd), 1.25 m from the nose to the
# root of the tail; the dire wolf is the same mesh at twice the size (big.gd's dire wolf is the wolf's plan x 2) with
# its own palette. Digitigrade legs on the same 25 bones: the foreleg's upper arm, forearm, the metacarpus (``cannon``)
# and the toes (``foot``); the hind leg's thigh, gaskin, metatarsus and toes.
WOLF = dict(
    withers_m=0.80, scale=0.5, split_u=0.0, jaw_below_m=0.03, toe_m=0.02, root_len=0.15,
    shoulder=(0.085, 0.30, 0.56), elbow=(0.085, 0.215, 0.40), knee=(0.072, 0.255, 0.15),
    fore_fetlock=(0.072, 0.285, 0.045), fore_coronet=(0.072, 0.315, 0.025),
    hip=(0.075, -0.30, 0.60), stifle=(0.095, -0.17, 0.43), hock=(0.072, -0.41, 0.19),
    hind_fetlock=(0.072, -0.375, 0.045), hind_coronet=(0.072, -0.345, 0.025),
    spine=((0, -0.30, 0.66), (0, -0.08, 0.70), (0, 0.16, 0.73), (0, 0.34, 0.71)),
    neck_top=(0.0, 0.52, 0.80), poll=(0.0, 0.545, 0.865), muzzle=(0.0, 0.785, 0.772),
    jaw_joint=(0.0, 0.56, 0.745), chin=(0.0, 0.752, 0.712),
    tail_root=(0.0, -0.43, 0.68), tail_mid=(0.0, -0.56, 0.50), tail_end=(0.0, -0.61, 0.26),
    stretch_regions={"shoulder": ((0.18, 0.42), (0.40, 0.70)), "stifle": ((-0.38, -0.10), (0.36, 0.64))},
)
WOLF_BOX = ((-0.20, 0.20), (-0.70, 0.88), (-0.004, 1.03))
WOLF_STEP_M = 0.0055
WOLF_BODY_TRIS = 4500
WOLF_SHELL_TRIS = 1800             # the fur shell's mesh (the body decimated; the shell shader draws it in layers)
WOLF_FAR_TRIS = 150
FUR_LENGTH_M = 0.045               # the fur map's B at 1: the longest fur (the ruff, the tail), in metres at the wolf's size
WOLF_SIZES = {"wolf": 1.0, "dire_wolf": 2.0}
# The palettes (sRGB; the person shader's bands): skin the coat, hair the dark markings (the saddle, the tail's tip, the
# ears' backs, the muzzle's ridge), cloth the eyes (amber; the dire wolf's ember), faction unused.
WOLF_PALETTES = {"wolf": {"skin": "#8e8476", "hair": "#3a3430", "cloth": "#d9a23a", "faction": "#808080"},
                 "dire_wolf": {"skin": "#5a5550", "hair": "#181514", "cloth": "#f06a2c", "faction": "#808080"}}
WOLF_RECTS = {"body": (0.0, 0.25, 0.75, 1.0), "fur": (0.0, 0.0, 0.75, 0.25), "eye": (0.75, 0.75, 1.0, 1.0),
              "teeth": (0.75, 0.5, 1.0, 0.75)}
WOLF_MATERIALS = {"coat": ("skin", 0.75), "mark": ("hair", 0.75), "pad": ("none", 0.72), "fur": ("skin", 0.8),
                  "eye": ("cloth", 0.36), "lid": ("none", 0.6), "mouth": ("none", 0.5), "tooth": ("none", 0.45)}


def wolf_leg(P, side, h=WOLF):
    m = (lambda p: p) if side > 0 else _mirror
    out = Field(P)
    sh, el, kn, ff, fc = (np.array(m(h[k])) for k in ("shoulder", "elbow", "knee", "fore_fetlock", "fore_coronet"))
    sx = np.sign(sh[0])
    # the forearm: muscular under the elbow (the flexors behind, the extensors in front), strong to the wrist; the
    # point of the elbow behind
    out.add(sd_round_cone(P, el + np.array([0, 0.004, -0.01]), kn + np.array([0, 0.0, 0.02]), 0.043, 0.025, 0.85), 0.0)
    out.add(sd_ellipsoid(P, el + np.array([0, 0.016, -0.065]), (0.034, 0.036, 0.08)), 0.03)
    out.add(sd_ellipsoid(P, el + np.array([0, -0.03, 0.005]), (0.026, 0.028, 0.03)), 0.02)
    # the wrist, the metacarpus sloping forward, the paw (four toes in a tight oval, the pads under)
    out.add(sd_ellipsoid(P, kn, (0.026, 0.026, 0.028)), 0.015)
    out.add(sd_round_cone(P, kn + np.array([0, 0.0, -0.01]), ff, 0.022, 0.021, 0.85), 0.012)
    out.add(paw(P, fc, sx, 1.0), 0.016)
    hp, st, hk, hf, hc = (np.array(m(h[k])) for k in ("hip", "stifle", "hock", "hind_fetlock", "hind_coronet"))
    # the gaskin (the second thigh) behind the stifle down to the hock, the hamstring to the point of the hock
    out.add(sd_round_cone(P, st + np.array([-0.01 * sx, -0.02, -0.01]), hk + np.array([0, 0.006, 0.03]),
                          0.052, 0.025, 0.82), 0.0)
    gk = _lerp(st, hk, 0.35) + np.array([-0.006 * sx, -0.025, 0.0])
    out.add(sd_ellipsoid(P, gk, (0.040, 0.052, 0.085), frame_from(hk - st)[[0, 2, 1]]), 0.03)
    poh = hk + np.array([0, -0.025, 0.02])
    out.add(sd_round_cone(P, gk + np.array([0, -0.03, 0.02]), poh, 0.018, 0.014, 0.7), 0.02)
    out.add(sd_ellipsoid(P, hk, (0.024, 0.027, 0.027)), 0.015)
    out.add(sd_round_cone(P, hk + np.array([0, 0.004, -0.015]), hf, 0.021, 0.020, 0.85), 0.012)
    out.add(paw(P, hc, sx, 0.90), 0.016)
    return out.d


def paw(P, c, sx, k=1.0):
    """A paw: an oval of four toes round the centre ``c`` (on the ground), the flat sole on the ground. A wolf's paws
    are large (the forefeet larger than the hind: ``k``)."""
    c = np.asarray(c, np.float64)
    out = Field(P)
    out.add(sd_ellipsoid(P, c + np.array([0, -0.006, 0.002]), np.array((0.031, 0.036, 0.027)) * k), 0.0)
    for dx, du in ((-0.019, 0.020), (-0.007, 0.031), (0.007, 0.031), (0.019, 0.020)):
        out.add(sd_ellipsoid(P, c + np.array([dx * k, du * k, 0.013]), np.array((0.012, 0.015, 0.013)) * k), 0.008)
    return smax(out.d, -P[:, 2], 0.004)


def _sd_flat_cone(P, a, b, ra, rb, thin):
    """A round cone flattened along u (the ear's thickness: ``thin`` of its width), its long axis a to b."""
    sw = [1, 0, 2]
    return sd_round_cone(P[:, sw], np.asarray(a, np.float64)[sw], np.asarray(b, np.float64)[sw], ra, rb, thin)


# the head's two pieces whose meeting line is the mouth (the bake darkens the lips along it)
def wolf_upper_muzzle(P):
    return sd_round_cone(P, (0, 0.656, 0.786), (0, 0.762, 0.768), 0.043, 0.027, 0.92)


def wolf_lower_jaw(P):
    return sd_round_cone(P, (0, 0.600, 0.748), (0, 0.733, 0.735), 0.030, 0.016, 0.86)


# P65c: the mouth is open to the jaw. The lower jaw is its own body inside the upper muzzle: a gap of WOLF_GAP_M runs
# round its top and sides (the upper teeth's and the palate's side above, the gums and the tongue below) from the
# front to the corner of the mouth (WOLF_CORNER_U, under the eye), tapering shut over WOLF_CORNER_TAPER_M; the upper
# lip (the flews) hangs over the jaw's sides, its edge straight and a little lower toward the corner (P65a's lip
# fullness was an ellipsoid whose edge rose toward the corner: a smile). The jaw bone opens the gap (the bite's
# wind-up, `jaw_open`): every point under the gap's middle is the jaw's, every point over it the head's.
WOLF_CORNER_U = 0.632
WOLF_CORNER_TAPER_M = 0.024
WOLF_GAP_M = 0.009


def wolf_flews(P):
    """The upper lip's fullness over the jaw's sides: a round cone each side from behind the nose pad to the corner
    of the mouth, its lower edge a little lower at the corner than at the front."""
    d = np.full(len(P), 1e9)
    for s in (1.0, -1.0):
        d = np.minimum(d, sd_round_cone(P, (0.020 * s, 0.758, 0.752), (0.027 * s, 0.646, 0.748), 0.0125, 0.0165,
                                        0.95))
    return d


def wolf_gap_width(P):
    u = P[:, 1]
    return WOLF_GAP_M * np.sqrt(np.clip((u - WOLF_CORNER_U) / WOLF_CORNER_TAPER_M, 0.0, 1.0))


def wolf_mouth_cut(P):
    """The mouth's gap (negative inside): a shell over the lower jaw's surface, WOLF_GAP_M thick, in front of the
    corner of the mouth."""
    dj = wolf_lower_jaw(P)
    g = wolf_gap_width(P)
    return np.maximum(np.abs(dj - 0.5 * g) - 0.5 * g, WOLF_CORNER_U - P[:, 1])


def wolf_head(P, h=WOLF, jaw=True):
    """A grey wolf's head: a broad skull (wide at the cheekbones), a clear stop under the brows, a muzzle about 45 % of
    the head's length, deep and blunt, the black nose pad over it; the lower jaw under the upper lip (P65c: its own
    body inside the mouth's gap, ``wolf_mouth_cut``); ears rounded triangles with thickness, their hollow in front.
    The cheeks' and the throat's ruff is the trunk's (``wolf_trunk``). ``jaw`` False: the upper head alone."""
    out = Field(P)
    # the cranium, broad between the ears, and the cheekbones (the zygomatic arches) wide behind the eyes
    out.add(sd_ellipsoid(P, (0, 0.570, 0.840), (0.079, 0.082, 0.060)), 0.0)
    for s in (1.0, -1.0):
        out.add(sd_ellipsoid(P, (0.056 * s, 0.598, 0.792), (0.053, 0.058, 0.047)), 0.03)
        # the brow over the eye; the stop is the dip in front of the brows
        out.add(sd_ellipsoid(P, (0.028 * s, 0.630, 0.851), (0.027, 0.027, 0.020)), 0.018)
    # the muzzle: the upper (the nasal bridge and the upper lip) and the lower jaw; the nose pad at the front
    out.add(wolf_upper_muzzle(P), 0.03)
    out.add(wolf_flews(P), 0.018)                  # the upper lip's fullness over the lower jaw at the sides
    if jaw:
        out.add(wolf_lower_jaw(P), 0.02)
    out.add(sd_ellipsoid(P, (0, 0.776, 0.775), (0.018, 0.014, 0.014)), 0.012)
    for s in (1.0, -1.0):          # the nostrils
        out.cut(sd_ellipsoid(P, (0.008 * s, 0.790, 0.775), (0.005, 0.005, 0.004)), 0.003)
    # the ears: rounded triangles, upright, a little apart and turned out, thick at the root; the hollow in front
    for s in (1.0, -1.0):
        base = np.array((0.047 * s, 0.553, 0.878))
        tip = np.array((0.066 * s, 0.546, 0.968))
        out.add(_sd_flat_cone(P, base, tip, 0.034, 0.008, 0.56), 0.022)
        out.cut(_sd_flat_cone(P, base + np.array([0.0, 0.016, 0.012]), tip + np.array([0, 0.010, -0.012]), 0.020, 0.003,
                              0.32), 0.005)
    return out.d


def wolf_jaw_share(P):
    """0..1: how much of a point the jaw bone carries by the mouth (1 under the gap's middle, 0 over it), and the
    share (0..1) of that rule against the bones' distances (1 in front of the corner of the mouth)."""
    g = np.maximum(wolf_gap_width(P), 1e-4)
    dj = wolf_lower_jaw(P)
    share = 1.0 - sstep(dj, 0.35 * WOLF_GAP_M, 0.65 * WOLF_GAP_M)
    near = sstep(P[:, 1], WOLF_CORNER_U - 0.022, WOLF_CORNER_U + 0.004) * (1.0 - sstep(dj - g, 0.012, 0.03))
    return share, near


def wolf_trunk(P, h=WOLF, limbs=True):
    out = Field(P)
    # the rib cage (deep, the coat rounding it), the brisket, the tucked waist, the croup and the hindquarters
    out.add(sd_ellipsoid(P, (0, 0.17, 0.585), (0.130, 0.25, 0.19)), 0.0)
    out.add(sd_ellipsoid(P, (0, 0.33, 0.52), (0.095, 0.11, 0.14)), 0.06)
    out.add(sd_round_cone(P, (0, -0.04, 0.645), (0, -0.27, 0.630), 0.100, 0.105, 0.95), 0.07)
    out.add(sd_ellipsoid(P, (0, -0.31, 0.615), (0.110, 0.14, 0.12)), 0.05)
    out.add(sd_ellipsoid(P, (0, 0.25, 0.755), (0.075, 0.16, 0.05)), 0.05)              # the withers
    out.add(sd_ellipsoid(P, (0, -0.02, 0.715), (0.085, 0.28, 0.04)), 0.05)             # the back's line
    for s in (1.0, -1.0):
        if not limbs:
            continue
        sh, el = np.array(h["shoulder"]) * [s, 1, 1], np.array(h["elbow"]) * [s, 1, 1]
        st = np.array(h["stifle"]) * [s, 1, 1]
        # the shoulder blade and the upper arm; the thigh to the stifle and the buttock behind
        out.add(sd_round_cone(P, (0.068 * s, 0.26, 0.73), sh, 0.048, 0.062, 0.62), 0.04)
        out.add(sd_round_cone(P, sh, el + np.array([0, 0, 0.015]), 0.060, 0.047, 0.72), 0.035)
        out.add(sd_round_cone(P, (0.07 * s, -0.30, 0.61), st, 0.095, 0.055, 0.78), 0.04)
        out.add(sd_round_cone(P, (0.055 * s, -0.40, 0.59), st + np.array([-0.02 * s, -0.10, -0.03]), 0.070, 0.045,
                              0.82), 0.04)
    # the neck, thick, under the mane (the long fur over the nape and the withers) and the ruff (the throat's and the
    # cheeks' fur standing out behind the jaw): the coat's volume, part of the body's own surface
    nb, nt = np.array((0, 0.33, 0.64)), np.array((0, 0.51, 0.79))
    out.add(sd_round_cone(P, nb, nt, 0.125, 0.092, 0.88), 0.06)
    out.add(sd_ellipsoid(P, (0, 0.41, 0.69), (0.13, 0.11, 0.14)), 0.06)
    out.add(sd_ellipsoid(P, (0, 0.43, 0.785), (0.080, 0.14, 0.055), frame_from(nt - nb)), 0.06)          # the mane
    out.add(sd_ellipsoid(P, (0, 0.49, 0.705), (0.072, 0.075, 0.080)), 0.05)                              # the throat
    for s in (1.0, -1.0):
        out.add(sd_ellipsoid(P, (0.060 * s, 0.530, 0.752), (0.050, 0.058, 0.070)), 0.04)                 # the cheeks
    return out.d


def wolf_tail(P, h=WOLF):
    """The brush: thick with fur from the root, widest past its middle, to a blunt tip."""
    r, m, e = (np.array(h[k]) for k in ("tail_root", "tail_mid", "tail_end"))
    d = sd_round_cone(P, r + np.array([0, 0.02, 0.0]), m, 0.038, 0.068, 0.88)
    return smin(d, sd_round_cone(P, m, e + np.array([0, 0, 0.02]), 0.068, 0.036, 0.88), 0.05)


def wolf_sdf(P, h=WOLF):
    d = wolf_trunk(P, h)
    d = smin(d, wolf_head(P, h), 0.045)
    for side in (1, -1):
        d = smin(d, wolf_leg(P, side, h), 0.03)
    return smax(smin(d, wolf_tail(P, h), 0.03), -wolf_mouth_cut(P), 0.0015)


def wolf_core(P, h=WOLF):
    return smin(smin(wolf_trunk(P, h, limbs=False), wolf_head(P, h), 0.045), wolf_tail(P, h), 0.03)


WOLF["core"] = wolf_core
WOLF["jaw_share"] = lambda P: wolf_jaw_share(np.asarray(P, np.float64))


# P65c: the teeth (their own piece, on the head and the jaw bones; hidden in the closed mouth, shown when the jaw
# opens): per side (u along the jaw's axis share t, angle from the top toward the side in degrees, length m,
# radius m, flat: the blade's thinness across the jaw). The upper teeth hang from the gap's roof into the jaw's
# place, the lower stand on the jaw; a wolf's: three incisors, the canine, the premolars and the carnassial.
WOLF_TEETH_UPPER = ((1.075, 10, 0.0050, 0.0022, 1.0), (1.055, 34, 0.0055, 0.0023, 1.0), (1.025, 54, 0.0060, 0.0024, 1.0),
                    (0.965, 56, 0.0220, 0.0046, 1.0), (0.80, 52, 0.0070, 0.0040, 0.5), (0.60, 50, 0.0100, 0.0048, 0.5),
                    (0.40, 50, 0.0130, 0.0058, 0.5), (0.24, 50, 0.0060, 0.0045, 0.65))
WOLF_TEETH_LOWER = ((1.08, 12, 0.0042, 0.0019, 1.0), (1.06, 34, 0.0046, 0.0020, 1.0), (1.035, 50, 0.0050, 0.0021, 1.0),
                    (0.94, 42, 0.0175, 0.0040, 1.0), (0.78, 38, 0.0060, 0.0036, 0.5), (0.58, 38, 0.0075, 0.0040, 0.5),
                    (0.38, 38, 0.0095, 0.0048, 0.5))
TOOTH_SIDES = 6
TOOTH_RGB = np.array([0.86, 0.82, 0.70])
MOUTH_RGB = np.array([0.36, 0.17, 0.17])


def _jaw_axis():
    a, b = np.array((0.0, 0.600, 0.748)), np.array((0.0, 0.733, 0.735))
    return a, b, 0.030, 0.016


def _ray_to(fn, origin, direction, level, reach=0.05, steps=60):
    """The first point from origin along direction where fn crosses ``level`` (bisection)."""
    lo, hi = 0.0, reach
    f0 = float(fn(origin[None, :])[0]) - level
    for _ in range(steps):
        mid = 0.5 * (lo + hi)
        f = float(fn((origin + direction * mid)[None, :])[0]) - level
        if (f > 0) == (f0 > 0):
            lo = mid
        else:
            hi = mid
    return origin + direction * 0.5 * (lo + hi)


def wolf_teeth(h=WOLF):
    """The teeth: a cone each (TOOTH_SIDES sides, its root sunk into the gum), in the teeth's tile (v 0 at the root,
    1 at the tip). Upper roots on the gap's roof (the lower jaw's surface offset by the gap), lower on the jaw."""
    a, b, ra, rb = _jaw_axis()
    parts = []
    for upper, table in ((True, WOLF_TEETH_UPPER), (False, WOLF_TEETH_LOWER)):
        for t, ang, length, rad, flat in table:
            for s in (1.0, -1.0):
                c = a + (b - a) * t
                th = math.radians(ang)
                d = _unit(np.array([math.sin(th) * s * 0.86, 0.0, math.cos(th)]))
                if t > 1.0:                        # the incisors round the jaw's front (past its axis's end)
                    d = _unit(d + np.array([0.0, 0.9, 0.0]))
                level = WOLF_GAP_M if upper else 0.0
                root = _ray_to(wolf_lower_jaw, c, d, level, reach=0.06)
                n = _unit(np.array([0.0, 0.0, 1.0]) * 0.85 + d * 0.15) if not upper else \
                    _unit(np.array([0.0, 0.0, -1.0]) * 0.85 - d * 0.15)
                if t > 1.0:
                    n = _unit(n + np.array([0.0, -0.25 if not upper else 0.25, 0.0]))
                base = root - n * 0.0025               # sunk into the gum
                tip = root + n * length
                side = _unit(np.cross(n, np.array([0.0, 1.0, 0.0])))
                fwd = _unit(np.cross(side, n))
                ring = [base + rad * (math.cos(2 * math.pi * k / TOOTH_SIDES) * side * flat
                                      + math.sin(2 * math.pi * k / TOOTH_SIDES) * fwd) for k in range(TOOTH_SIDES)]
                V = np.array(ring + [tip])
                T = np.array([(k, (k + 1) % TOOTH_SIDES, TOOTH_SIDES) for k in range(TOOTH_SIDES)])
                out = V[:TOOTH_SIDES].mean(axis=0)
                nrm = np.cross(V[T[0, 1]] - V[T[0, 0]], V[T[0, 2]] - V[T[0, 0]])
                if float(nrm @ (V[T[0]].mean(axis=0) - out)) < 0:
                    T = T[:, ::-1]
                UV = np.array([[(0.5 + 0.4 * math.cos(2 * math.pi * k / TOOTH_SIDES), 0.05) if q < TOOTH_SIDES
                                else (0.5, 0.95) for q, k in zip(tri, tri)] for tri in T])
                parts.append((V, T, UV))
    V, T, UV = merge_parts(parts)
    return Piece("teeth", V, T, UV)


def _wolf_mirror(pose):
    return {(k[:-2] + ("_r" if k.endswith("_l") else "_l")) if k.endswith(("_l", "_r")) else k: v
            for k, v in pose.items()}


# The wolf's gait extremes and its attacks' extremes (a check, as the horse's: P64's rig drives the bones).
WOLF_POSES = {
    "stand": {},
    "trot_reach_left": {"fore_upper_l": 24, "fore_lower_l": 4, "fore_cannon_l": -6, "fore_foot_l": -8,
                        "hind_upper_r": 18, "hind_lower_r": -4, "hind_cannon_r": -4, "hind_foot_r": -6,
                        "fore_upper_r": -14, "fore_lower_r": -12, "fore_cannon_r": -36, "fore_foot_r": -18,
                        "hind_upper_l": -16, "hind_lower_l": 10, "hind_cannon_l": -14, "hind_foot_l": -18,
                        "neck": -2, "tail_01": -6},
    "gallop_extended": {"spine_01": -6, "fore_upper_l": 44, "fore_lower_l": 6, "fore_cannon_l": -6, "fore_foot_l": -8,
                        "fore_upper_r": 34, "fore_lower_r": 4, "fore_cannon_r": -8, "fore_foot_r": -10,
                        "hind_upper_l": -34, "hind_lower_l": 16, "hind_cannon_l": -16, "hind_foot_l": -16,
                        "hind_upper_r": -28, "hind_lower_r": 14, "hind_cannon_r": -14, "hind_foot_r": -16,
                        "neck": 4, "tail_01": -20},
    "gallop_gathered": {"spine_01": 10, "fore_upper_l": -24, "fore_lower_l": -20, "fore_cannon_l": -50,
                        "fore_foot_l": -20, "fore_upper_r": -16, "fore_lower_r": -14, "fore_cannon_r": -40,
                        "fore_foot_r": -16, "hind_upper_l": 36, "hind_lower_l": -24, "hind_cannon_l": 22,
                        "hind_foot_l": -10, "hind_upper_r": 30, "hind_lower_r": -20, "hind_cannon_r": 18,
                        "hind_foot_r": -8, "neck": -6, "tail_01": -10},
    "lunge": {"spine_01": -4, "fore_upper_l": 56, "fore_lower_l": -6, "fore_cannon_l": -20, "fore_foot_l": -20,
              "fore_upper_r": 48, "fore_lower_r": -4, "fore_cannon_r": -16, "fore_foot_r": -18,
              "hind_upper_l": -30, "hind_lower_l": 12, "hind_cannon_l": -10, "hind_foot_l": -12,
              "hind_upper_r": -26, "hind_lower_r": 10, "hind_cannon_r": -10, "hind_foot_r": -12,
              "neck": -12, "head": 10, "jaw": -24, "tail_01": -16},
    "jaw_open": {"jaw": -26},
}
WOLF_POSES["trot_reach_right"] = _wolf_mirror(WOLF_POSES["trot_reach_left"])
WOLF_POSE_ORDER = ("stand", "trot_reach_left", "trot_reach_right", "gallop_extended", "gallop_gathered", "lunge",
                   "jaw_open")


def _wolf_frame(h=WOLF):
    poll, muz = np.array(h["poll"]), np.array(h["muzzle"])
    return poll, muz - poll


def wolf_eye_orbits(side, h=WOLF):
    return np.array((0.036 * side, 0.636, 0.816)), _unit(np.array([side * 0.85, 0.6, 0.25]))


WOLF_TAIL_CARDS = 2                # crossed cards along the brush (P65a: the ruff's, cheeks', breeches' and belly's
WOLF_TAIL_FRINGE_M = 0.014         # cards went: that fur is the body's own volume); their edges this far out of it


def fur_cards(h=WOLF):
    """The brush's soft edge: WOLF_TAIL_CARDS crossed cards along the tail's middle line, each a little wider than the
    tail's volume so only their strands' edges stand out of it (laid along the tail; their colour the coat's under
    them, ``wolf_bake``). UVs: the fur tile (v 1 at the root)."""
    r, m, e = (np.array(h[k]) for k in ("tail_root", "tail_mid", "tail_end"))
    s_ = np.linspace(0.0, 1.0, 9)
    a0, m0, e0 = r + np.array([0, 0.01, 0.0]), m, e + np.array([0, 0, -0.005])
    path = np.array([(1 - t) ** 2 * a0 + 2 * (1 - t) * t * m0 + t * t * e0 for t in s_])
    tang = _unit_rows(np.gradient(path, axis=0))
    # the volume's radius along the path (wolf_tail's cones), the cards' half width beyond it; narrowing to the tip
    rad = np.interp(s_, (0.0, 0.5, 0.92, 1.0), (0.032, 0.064, 0.040, 0.014))
    half = rad + WOLF_TAIL_FRINGE_M * np.interp(s_, (0.0, 0.15, 0.9, 1.0), (0.2, 1.0, 1.0, 0.4))
    parts = []
    for kc in range(WOLF_TAIL_CARDS):
        a = math.pi * kc / WOLF_TAIL_CARDS
        side = []
        for i in range(len(path)):
            n1 = _unit(np.cross(tang[i], np.array([1.0, 0, 0])))
            side.append((math.cos(a) * np.array([1.0, 0, 0]) + math.sin(a) * n1) * half[i])
        side = np.array(side)
        parts.append(strip(path - side, path + side, np.linspace(1.0, 0.02, len(path))))
    V, T, UV = merge_parts(parts)
    return Piece("fur", V, T, UV)


def wolf_flow(P, h=WOLF):
    """The coat's flow (x, u, z) per point: from the nose back over the head and along the neck and the trunk, down the
    legs and the flanks, out along the tail."""
    x, u, z = P[:, 0], P[:, 1], P[:, 2]
    back = np.stack([np.zeros_like(x), -np.ones_like(x), -0.25 * np.ones_like(x)], axis=1)
    down = np.stack([np.zeros_like(x), -0.15 * np.ones_like(x), -np.ones_like(x)], axis=1)
    legs = sstep(-z, -0.42, -0.34)[:, None]
    flank = (sstep(np.abs(x), 0.05, 0.11) * 0.5)[:, None]
    f = back * (1 - legs) + down * legs
    f = f * (1 - flank) + down * flank
    return _unit_rows(f)


def wolf_coat(P, Nrm, h=WOLF):
    """Per point: (material, grey): the coat (agouti: banded grey, a pale throat, chest, belly, insides of the legs and
    cheeks), the dark saddle over the back and the shoulders, the tail's tip and its top, the ears' backs and the
    muzzle's ridge (the hair band), the nose pad, the lips' line and the claws (black, no band)."""
    import people_bake as pbk
    x, u, z = P[:, 0], P[:, 1], P[:, 2]
    n = len(P)
    noise = pbk.fbm(P, 9.0, 23)
    fine = pbk.fbm(P, 40.0, 29)
    streak = coat_flow(np.stack([x, u, z], axis=1) * 2.0, 40.0)
    up = Nrm[:, 2]
    grey = 0.74 + 0.10 * (noise - 0.5) + 0.06 * (fine - 0.5) + 0.12 * (streak - 0.5)
    pale = np.clip(sstep(-up, 0.1, 0.6) * sstep(-z, -0.66, -0.5) + sstep(-z, -0.40, -0.30) * 0.45
                   + sstep(u, 0.30, 0.40) * sstep(-z, -0.66, -0.56) * sstep(-u, -0.6, -0.5), 0, 1)
    grey = grey * (1 - pale) + (0.95 + 0.04 * (fine - 0.5)) * pale
    mat = np.array(["coat"] * n, dtype=object)
    # the saddle: the back, the shoulders' and the neck's tops darker, a soft ragged edge (the coat's own band)
    sad = sstep(up + 0.18 * (pbk.fbm(P, 2.0, 31) - 0.5), 0.0, 0.65) * sstep(z, 0.55, 0.66)         * sstep(u, -0.46, -0.40) * (1.0 - sstep(u, 0.50, 0.56))
    grey = grey * (1.0 - 0.45 * sad * (0.8 + 0.4 * streak))
    # the face (P65a): the pale cheeks and upper lips under the eyes, a darker bridge to the nose
    cheek = sstep(u, 0.600, 0.640) * sstep(np.abs(x), 0.018, 0.032) * sstep(-z, -0.805, -0.790) * (1 - sstep(u, 0.75, 0.78))
    grey = grey * (1 - 0.8 * cheek) + (0.93 + 0.04 * (fine - 0.5)) * 0.8 * cheek
    bridge = sstep(u, 0.640, 0.680) * sstep(up, 0.45, 0.8)
    grey = grey * (1.0 - 0.22 * bridge)
    # the dark markings (the hair band): the tail's tip and its top, the ears' backs and rims
    # (the tail's dark tip and top in the coat's own band, darkened: a band's edge on the 256 px map is a saw-tooth)
    tail_near = (u < h["tail_root"][1] + 0.01) * np.maximum(sstep(-z, -0.44, -0.30), 0.75 * sstep(up, 0.2, 0.7))
    grey = grey * (1.0 - 0.68 * tail_near)
    tail = np.zeros(n, bool)
    on_ear = (u < 0.585) & (z > 0.86)
    back = sstep(-Nrm[:, 1], -0.35, 0.25)
    grey = grey * (1.0 - on_ear * np.maximum(0.62 * sstep(z, 0.865, 0.92) * back, 0.62 * sstep(z, 0.925, 0.945)))
    ears = on_ear & (z > 0.945)
    mark = tail | ears
    mat[mark] = "mark"
    grey = np.where(mark, 0.75 + 0.20 * (streak - 0.5) + 0.10 * (noise - 0.5), grey)
    ear_in = on_ear * sstep(z, 0.875, 0.90) * (1.0 - back) * (1.0 - sstep(z, 0.925, 0.945))
    grey = grey * (1.0 - ear_in) + (0.88 + 0.05 * (fine - 0.5)) * ear_in
    # P65c: the mouth: the gap's walls inside the upper lip (the gums, the palate, the tongue: the mouth's colour, no
    # band), the lips black along the gap's edges (the upper lip's hem and the lower lip), the black nose pad, the claws
    dj, du = wolf_lower_jaw(P), wolf_head(P, h, jaw=False)
    front = sstep(u, WOLF_CORNER_U - 0.006, WOLF_CORNER_U + 0.002)
    inside = front * (1.0 - sstep(dj, WOLF_GAP_M + 0.0008, WOLF_GAP_M + 0.0025)) * (1.0 - sstep(du, -0.0045, -0.002))
    lip = np.maximum(front * (1.0 - sstep(dj, WOLF_GAP_M + 0.002, WOLF_GAP_M + 0.006)) * (1.0 - sstep(du, 0.002, 0.0055)),
                     sstep(u, WOLF_CORNER_U - 0.016, WOLF_CORNER_U - 0.004) * (1.0 - front)
                     * np.exp(-(wolf_mouth_cut(P + np.array([0.0, 0.012, 0.0])) / 0.003) ** 2) * (dj < 0.012))
    lip = np.maximum(lip, front * (1.0 - sstep(np.abs(dj), 0.002, 0.004)) * (1.0 - sstep(du, 0.008, 0.014)))
    lip = np.clip(lip - inside, 0.0, 1.0)
    grey = grey * (1.0 - 0.86 * lip)
    mouth = inside > 0.5
    mat[mouth] = "mouth"
    grey = np.where(mouth, 0.75 + 0.25 * sstep(-dj, -0.002, 0.0) - 0.25 * sstep(dj, 0.002, 0.005)
                    + 0.08 * (fine - 0.5), grey)
    nose = (np.linalg.norm((P - np.array([0.0, 0.777, 0.775])) / [0.022, 0.021, 0.021], axis=1) < 1.0) & (z > 0.757)
    claws = (z < 0.018) & (np.abs(u - np.where(u > 0, 0.34, -0.32)) < 0.03)
    pad = (nose | claws | (lip > 0.6)) & ~mouth
    mat[pad] = "pad"
    grey = np.where(pad & ~(lip > 0.6), 0.10 + 0.05 * (fine - 0.5), grey)
    # the darker skin round the eyes (the lids' rims)
    for side in (1.0, -1.0):
        e = np.array((0.040 * side, 0.640, 0.815))
        d = np.linalg.norm((P - e) / [0.022, 0.026, 0.020], axis=1)
        grey = grey * (1.0 - 0.30 * sstep(-d, -1.5, -1.0))
    return mat, np.clip(grey, 0.0, 1.0)


def wolf_fur_length(P, h=WOLF):
    """0..1 of FUR_LENGTH_M: long on the ruff, the back, the thighs and the tail; short on the face, the legs and paws."""
    x, u, z = P[:, 0], P[:, 1], P[:, 2]
    base = 0.35 + 0.25 * sstep(z, 0.45, 0.70)
    ruff = np.exp(-((u - 0.42) / 0.10) ** 2) * sstep(z, 0.55, 0.65) * 0.6
    tail = sstep(-u, 0.42, 0.46) * 0.6
    face = sstep(u, 0.55, 0.62) * 0.75
    legs = sstep(-z, -0.40, -0.30) * 0.75
    out = np.clip(base + ruff + tail - face - legs, 0.05, 1.0)
    # P65c: the ears, the muzzle and the lower legs near bare (the shell spiked on the ears: their 3 cm of fur)
    ears = (u < 0.60) * np.maximum(sstep(z, 0.86, 0.885) * sstep(np.abs(x), 0.022, 0.034), sstep(z, 0.915, 0.93))
    muzzle = sstep(u, 0.62, 0.66)
    shins = sstep(-z, -0.36, -0.30)
    bare = np.maximum(np.maximum(ears, muzzle), shins)
    return out * (1.0 - bare) + 0.02 * bare


def wolf_bake(pieces, dense, out_dir, ao_by_piece):
    """wolf_albedo.png (RGBA 512 px: A the fur cards' strands), wolf_normal.png, wolf_orm.png (256 px) and
    wolf_fur.png (256 px: RG the flow in the tangent frame, B the fur's length; for the shell)."""
    import people_bake as pbk
    import people_roles as pr
    from scipy.spatial import cKDTree
    UV = np.concatenate([p.uv_atlas for p in pieces])
    owner = np.concatenate([np.full(len(p.T), i) for i, p in enumerate(pieces)])
    local = np.concatenate([np.arange(len(p.T)) for p in pieces])
    dV, dN, _dT = dense
    dtree = cKDTree(dV)
    body = pieces[0]

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

    def frames(sel, t, b):
        tt = local[t[sel]]
        bb = b[sel]
        tan = np.einsum("nk,nkj->nj", bb, body.tan[tt])
        nor = _unit_rows(np.einsum("nk,nkj->nj", bb, body.nor[tt]))
        sgn = np.where(np.einsum("nk,nk->n", bb, body.sgn[tt]) >= 0, 1.0, -1.0)
        tan = _unit_rows(tan - nor * np.einsum("ij,ij->i", tan, nor)[:, None])
        return tan, np.cross(nor, tan) * sgn[:, None], nor

    def under_coat(P):
        """The coat under a fur card's texel (the nearest point of the dense surface): its material and grey."""
        _d, k = dtree.query(to_blender(P), k=1)
        nq = dN[k]
        return wolf_coat(to_blender(dV[k]), np.stack([nq[:, 0], -nq[:, 1], nq[:, 2]], axis=1))

    def hi_normal(P):
        d, k = dtree.query(to_blender(P), k=4)
        w = 1.0 / np.maximum(d, 1e-5)
        return _unit_rows(np.einsum("nk,nkj->nj", w, dN[k]))

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
        if p.name == "body":
            hn = hi_normal(P)
            hz = np.stack([hn[:, 0], -hn[:, 1], hn[:, 2]], axis=1)
            m_, g = wolf_coat(P, hz)
            col = np.repeat(g[:, None], 3, axis=1)
            col[m_ == "mouth"] = MOUTH_RGB * g[m_ == "mouth", None]
        elif p.name == "teeth":
            v = uvt[sel, 1]
            col = TOOTH_RGB * (0.72 + 0.28 * sstep(v, 0.05, 0.5))[:, None]
        elif p.name == "fur":
            g, a = hair_tile(uvt[sel, 0], uvt[sel, 1])
            _m, cg = under_coat(P)
            col = np.repeat((cg * (0.92 + 0.30 * (g - 0.55)))[:, None], 3, axis=1)
            alpha[yy, xx] = a
        else:
            u, v = uvt[sel, 0], uvt[sel, 1]
            lidc = sstep(v, 0.62, 0.70)
            pupil = np.exp(-((u - 0.5) / 0.12) ** 2 - ((v - 0.25) / 0.22) ** 2)
            hl = np.exp(-(((u - 0.38) / 0.08) ** 2 + ((v - 0.18) / 0.10) ** 2))
            ball = 0.85 * (1.0 - 0.9 * sstep(pupil, 0.45, 0.6))[:, None] * np.ones(3) + hl[:, None] * 0.25
            col = ball * (1.0 - lidc[:, None]) + 0.10 * lidc[:, None]
        rgb[yy, xx] = col
    rgb = pbk.dilate(rgb, filled)
    alpha = pbk.dilate(alpha[..., None], filled)[..., 0]
    u0, v0, u1, v1 = WOLF_RECTS["fur"]
    keep = np.ones_like(alpha)
    keep[int(round((1 - v1) * ALBEDO_PX)):int(round((1 - v0) * ALBEDO_PX)),
         int(round(u0 * ALBEDO_PX)):int(round(u1 * ALBEDO_PX))] = 0.0
    alpha = np.maximum(alpha, keep)
    alb = np.concatenate([pbk.to_u8(rgb), pbk.to_u8(alpha)[..., None]], axis=-1)
    pbk.save_png(os.path.join(out_dir, "wolf_albedo.png"), alb)
    # ---- normal, ORM, fur at 256 px
    filled, ys, xs, t, b, pos, uvt = texels(NORMAL_PX)
    nrm = np.zeros((NORMAL_PX, NORMAL_PX, 3))
    nrm[..., 2] = 1.0
    orm = np.zeros((ORM_PX, ORM_PX, 3))
    fur = np.zeros((NORMAL_PX, NORMAL_PX, 3))
    fur[..., :2] = 0.5
    for i, p in enumerate(pieces):
        sel = owner[t] == i
        if not sel.any():
            continue
        yy, xx = ys[sel], xs[sel]
        tt = local[t[sel]]
        P = pos[sel]
        if p.name == "body":
            tan, bit, nor = frames(sel, t, b)
            hn = dense_normal(dense, P, nor)
            ts = np.stack([np.einsum("ij,ij->i", hn, tan), np.einsum("ij,ij->i", hn, bit),
                           np.einsum("ij,ij->i", hn, nor)], axis=1)
            # the fur's grain: streaks along the flow, their slope in the tangent frame
            fl = wolf_flow(P)
            flb = np.stack([fl[:, 0], -fl[:, 1], fl[:, 2]], axis=1)
            e = 0.002
            tx = np.stack([tan[:, 0], -tan[:, 1], tan[:, 2]], axis=1)
            bx = np.stack([bit[:, 0], -bit[:, 1], bit[:, 2]], axis=1)
            h0 = coat_flow(P * 2.0, 40.0)
            g1 = (coat_flow((P + tx * e) * 2.0, 40.0) - h0) / e
            g2 = (coat_flow((P + bx * e) * 2.0, 40.0) - h0) / e
            ts = ts - 0.004 * np.stack([g1, g2, np.zeros_like(g1)], axis=1) * ts[:, 2:3]
            nrm[yy, xx] = _unit_rows(ts)
            hz = np.stack([hn[:, 0], -hn[:, 1], hn[:, 2]], axis=1)
            m, _g = wolf_coat(P, hz)
            rough = np.array([WOLF_MATERIALS[s_][1] for s_ in m])
            band = np.array([pr.band_byte(WOLF_MATERIALS[s_][0]) for s_ in m])
            fdir = np.stack([np.einsum("ij,ij->i", flb, tan), np.einsum("ij,ij->i", flb, bit)], axis=1)
            fdir = fdir / np.maximum(np.linalg.norm(fdir, axis=1, keepdims=True), 1e-6)
            fur[yy, xx, 0] = 0.5 + 0.5 * fdir[:, 0]
            fur[yy, xx, 1] = 0.5 + 0.5 * fdir[:, 1]
            fur[yy, xx, 2] = np.where((m == "pad") | (m == "mouth"), 0.0, wolf_fur_length(P))
        elif p.name == "teeth":
            rough = np.full(len(P), WOLF_MATERIALS["tooth"][1])
            band = np.full(len(P), pr.band_byte("none"))
        elif p.name == "fur":
            m, _g = under_coat(P)
            rough = np.full(len(P), WOLF_MATERIALS["fur"][1])
            band = np.array([pr.band_byte(WOLF_MATERIALS[s_][0]) for s_ in m])
        else:
            lid = uvt[sel, 1] > 0.66
            rough = np.where(lid, WOLF_MATERIALS["lid"][1], WOLF_MATERIALS["eye"][1])
            band = np.where(lid, pr.band_byte("none"), pr.band_byte("cloth"))
        ao = np.einsum("nk,nk->n", b[sel], ao_by_piece[p.name][p.T[tt]])
        orm[yy, xx, 0] = ao
        orm[yy, xx, 1] = rough
        orm[yy, xx, 2] = band / 255.0
    nrm = pbk.dilate(nrm, filled)
    orm = pbk.dilate(orm, filled)
    fur = pbk.dilate(fur, filled)
    pbk.save_png(os.path.join(out_dir, "wolf_normal.png"), pbk.to_u8(nrm * 0.5 + 0.5))
    o8 = pbk.to_u8(orm)
    o8[..., 2] = np.round(orm[..., 2] * 255.0).astype(np.uint8)
    pbk.save_png(os.path.join(out_dir, "wolf_orm.png"), o8)
    pbk.save_png(os.path.join(out_dir, "wolf_fur.png"), pbk.to_u8(fur))


def build_wolf(out_dir, work_dir, h=WOLF):
    import bpy
    import people_outfit as po
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    fn = lambda P: wolf_sdf(P, h)  # noqa: E731
    V, T = polygonize(fn, WOLF_BOX, WOLF_STEP_M)
    V, T = weld(V, T)
    V = taubin(V, T, SMOOTH_ITERS)
    dense = (to_blender(V), vertex_normals_np(to_blender(V), flip(T)), flip(T))
    stats_dense = mesh_stats(T)
    log("wolf field: %d vertices, %d triangles (%.1f s)" % (len(V), len(T), time.time() - t0))
    head = sstep(V[:, 1], 0.50, 0.56) * sstep(V[:, 2], 0.66, 0.72)
    paws = sstep(-V[:, 2], -0.20, -0.12)
    bV, bT = _decimated(V, T, WOLF_BODY_TRIS, "wolf_body", detail=np.maximum(0.85 * head, 0.3 * paws))
    bV, bT = drop_slivers(bV, bT)
    boundary, nonmanifold, _e = mesh_stats(bT)
    if boundary or nonmanifold or not directed_edges_ok(bT):
        raise SystemExit("quadruped: the wolf's body is not closed and manifold (%d open, %d non-manifold edges)" % (
            boundary, nonmanifold))
    body = Piece("body", bV, bT, _unwrap01(bV, bT, "wolf_body_uv"))
    body.idx, body.w = weights(bV, h)
    eyes_p = eyes(h, orbits=lambda s_: wolf_eye_orbits(s_, h), size=0.42, fn=fn, tilt=0.45, reach=0.06)
    fur_p = fur_cards(h)
    teeth_p = wolf_teeth(h)
    for p in (eyes_p, fur_p):
        _nearest_weights(p, body)
    # the upper teeth are the head's, the lower the jaw's (each tooth whole on its bone)
    lower = np.repeat(np.array([False] * (len(WOLF_TEETH_UPPER) * 2) + [True] * (len(WOLF_TEETH_LOWER) * 2)),
                      TOOTH_SIDES + 1)
    teeth_p.idx = np.zeros((len(teeth_p.V), 4), np.int64)
    teeth_p.idx[:, 0] = np.where(lower, BONES.index("jaw"), BONES.index("head"))
    teeth_p.idx[:, 1:] = [BONES.index("neck"), BONES.index("spine_02"), BONES.index("spine_01")]
    teeth_p.w = np.zeros((len(teeth_p.V), 4))
    teeth_p.w[:, 0] = 1.0
    # the tail's cards ride on the tail's bones
    tail_sel = fur_p.V[:, 1] < h["tail_root"][1] + 0.02
    s_t = np.clip((h["tail_root"][1] - fur_p.V[:, 1]) / max(h["tail_root"][1] - h["tail_end"][1], 1e-6), 0, 1)
    w2 = sstep(s_t, 0.25, 0.6)
    fur_p.idx[tail_sel] = [BONES.index("tail_01"), BONES.index("tail_02"), BONES.index("pelvis"),
                           BONES.index("spine_01")]
    fur_p.w[tail_sel] = np.stack([np.round(1 - w2[tail_sel], 6), 1 - np.round(1 - w2[tail_sel], 6),
                                  np.zeros(tail_sel.sum()), np.zeros(tail_sel.sum())], axis=1)
    pieces = {"body": body, "eyes": eyes_p, "fur": fur_p, "teeth": teeth_p}
    for nm, p in pieces.items():
        p.uv01 = p.uv
        rect = {"body": "body", "eyes": "eye", "fur": "fur", "teeth": "teeth"}[nm]
        u0, v0, u1, v1 = WOLF_RECTS[rect]
        e = UV_INSET_PX / ALBEDO_PX
        p.uv_atlas = np.stack([u0 + e + p.uv[..., 0] * (u1 - u0 - 2 * e), v0 + e + p.uv[..., 1] * (v1 - v0 - 2 * e)],
                              axis=-1)
    tan, sgn, nor = (flip(a) for a in po.tangents(to_blender(body.V), flip(body.T), flip(body.uv_atlas)))
    body.tan, body.sgn, body.nor = tan, sgn, nor
    bn = vertex_normals_np(to_blender(body.V), flip(body.T))
    ao = {"body": vertex_ao(to_blender(body.V), bn, to_blender(body.V), body.T, reach=0.12),
          "eyes": np.full(len(eyes_p.V), 0.85), "fur": np.full(len(fur_p.V), 0.9),
          "teeth": np.full(len(teeth_p.V), 0.8)}
    os.makedirs(out_dir, exist_ok=True)
    wolf_bake([body, fur_p, eyes_p, teeth_p], dense, out_dir, ao)
    # the shell's mesh and the far mesh: the body decimated with its UVs, the shell weighted as the body
    uvb = flip(body.uv_atlas)
    sV, sT, _m, s_uv = po.decimate(to_blender(body.V), flip(body.T), np.zeros(len(body.T), np.int32), WOLF_SHELL_TRIS,
                                   "wolf_shell", uv=uvb)
    sV = np.asarray(sV, np.float64)
    sV = np.stack([sV[:, 0], -sV[:, 1], sV[:, 2]], axis=1)
    sT = flip(np.asarray(sT, np.int64))
    s_uv = flip(np.asarray(s_uv))
    # P65c: no shell over the mouth's gap and its lips (a triangle bridging the gap would hide the open mouth)
    cen = sV[sT].mean(axis=1)
    keep = ~((cen[:, 1] > WOLF_CORNER_U - 0.012) & (wolf_lower_jaw(cen) < WOLF_GAP_M + 0.008)
             & (wolf_head(cen, h, jaw=False) < 0.006))
    sT, s_uv = sT[keep], s_uv[keep]
    shell = Piece("shell", sV, sT, None)
    shell.uv_atlas = s_uv
    _nearest_weights(shell, body)
    fV, fT, _m2, f_uv = po.decimate(to_blender(body.V), flip(body.T), np.zeros(len(body.T), np.int32), WOLF_FAR_TRIS,
                                    "wolf_far", uv=uvb)
    coll = bpy.data.collections.new("Wolf")
    bpy.context.scene.collection.children.link(coll)
    arm = make_armature("Wolf", coll, h)
    mat = bpy.data.materials.new("wolf")
    objs = [arm]
    pieces_all = dict(pieces, shell=shell)
    counts = {}
    for name, parts in (("wolf", ("body", "eyes", "fur", "teeth")), ("wolf_shell", ("shell",))):
        V2, T2, UV2, I2, W2 = combine(pieces_all, parts)
        if len(T2) > TRIS_MAX:
            raise SystemExit("quadruped: %s has %d triangles, over %d" % (name, len(T2), TRIS_MAX))
        ob = skinned(name, V2, T2, UV2, I2, W2, arm, coll, mat)
        ob.data.validate()                   # a decimation's fin (two triangles on three corners) goes, as the export
        counts[name] = len(ob.data.polygons)  # would drop it
        objs.append(ob)
    far = po.mesh_object("wolf_far", np.asarray(fV, np.float64), np.asarray(fT, np.int64), None, np.asarray(f_uv),
                         coll)
    far.data.materials.clear()
    far.data.materials.append(mat)
    far.data.validate()
    objs.append(far)
    counts["wolf_far"] = len(far.data.polygons)
    po.export(os.path.join(out_dir, "wolf.glb"), objs)
    export_poses(os.path.join(out_dir, "wolf_poses.glb"), arm, coll, WOLF_POSES, WOLF_POSE_ORDER)
    J = joints(h)
    info = {
        "bones": list(BONES), "parents": dict(PARENTS),
        "triangles": {**counts, **{n: int(len(p.T)) for n, p in pieces.items()}},
        "vertices": {n: int(len(p.V)) for n, p in pieces.items()},
        "body_closed": True,
        "meshes": {"body": "wolf", "shell": "wolf_shell", "far": "wolf_far"},
        "measures": {"withers_m": r6(max(body.V[np.abs(body.V[:, 1] - 0.25) < 0.04][:, 2])),
                     "length_m": r6(body.V[:, 1].max() - body.V[:, 1].min()),
                     "height_m": r6(body.V[:, 2].max()), "width_m": r6(body.V[:, 0].max() - body.V[:, 0].min())},
        "landmarks": {"eyes": [gd(wolf_eye_orbits(s_, h)[0]) for s_ in (1.0, -1.0)],
                      "nose": gd(h["muzzle"]), "jaw": gd(h["jaw_joint"]),
                      "soles": {leg: gd(J["%s_foot_%s" % tuple(leg.split("_"))][1]) for leg in LEGS}},
        "poses": check_poses({"body": body}, h, WOLF_POSES, WOLF_POSE_ORDER), "pose_order": list(WOLF_POSE_ORDER),
        "atlas": {"albedo_px": ALBEDO_PX, "normal_px": NORMAL_PX, "orm_px": ORM_PX, "fur_px": NORMAL_PX,
                  "rects": WOLF_RECTS,
                  "materials": {k: {"band": b_, "roughness": r_} for k, (b_, r_) in WOLF_MATERIALS.items()},
                  "albedo_alpha": "the fur cards' strands: alpha scissor"},
        "shell": {"mesh": "wolf_shell", "map": "wolf_fur.png", "length_m": FUR_LENGTH_M,
                  "encoding": "R, G: the fur's flow in the tangent frame (0.5 + 0.5 x); B: its length over length_m",
                  "layers": {"desktop": 12, "low": 6}},
        "palettes": WOLF_PALETTES, "sizes": WOLF_SIZES,
        "dense": {"step_m": WOLF_STEP_M, "boundary_edges": stats_dense[0], "nonmanifold_edges": stats_dense[1]},
    }
    if work_dir:
        os.makedirs(work_dir, exist_ok=True)
        with open(os.path.join(work_dir, "wolf_info.json"), "w", encoding="utf-8") as fh:
            json.dump(info, fh, indent=1, sort_keys=True)
    log("wolf: %s triangles; %.1f s" % (counts, time.time() - t0))
    return info


if __name__ == "__main__":
    import sys as _sys
    _animal = _sys.argv[1]
    _out, _work = _sys.argv[2], (_sys.argv[3] if len(_sys.argv) > 3 else "")
    if _animal == "horse":
        build(_out, _work)
    else:
        build_wolf(_out, _work)

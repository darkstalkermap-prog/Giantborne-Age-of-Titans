"""Hair and beards as game meshes: cards grown from the kit's strand generator (numpy + scipy).

The kit grows guide strands on the body's scalp and beard masks along comb flow fields with
gravity, kept outside the skin by a KD-tree collision against the surface. Each guide becomes a
card: a ribbon along the guide, lying tangent to the head (side = normal x tangent), tapering to
the tip, curled slightly towards the head, in two layers for the long styles (an inner, wider one
that hides the scalp and an outer, longer, wispier one). UV: one of the atlas's four columns per
card (u), the root at the top of the atlas (v). Normals: the head surface normal under the card.
Every vertex is skinned 100 % to the game_engine "head" bone.

Ported from the M10 research run's frozen kit snapshot (Surface, grow, post_collide) and its hair
card script (ribbons, the growth of the scalp and beard guides, the four styles). The strand
Curves objects of the renders are not ported. Changes: the crop has twice the research's cards
(the research crop was patchy), and the styles are named by the giant index's mesh ids. The look
pass (P46) made the cards narrower and more numerous (a card wider than it is long reads as a
shingle), with fewer points along the short ones. The M10 gate (LC-6) added the hairline's fringe
(``FRINGE``: a row of short, narrow, wispy cards rooted evenly along the front of the scalp's edge,
grown from a random stream of their own so every other card stays as it was), made a long beard's cards
no wider than ``BEARD_ASPECT`` of their own length and taper to a point (``BEARD_TAPER``), and lays
the wild mane's locks under the shoulders' garments as the other long styles lie (``tuck``).

The look pass II (P51; plan M11 §2.4, decision 8): a card's normal is the style's head-centred normal
(``volume_normal``: outward from the head's centre above it, from a vertical axis through it below), which the
hair shader blends with the card's own facing, so a style shades as one volume; the long styles gain a sparse
third layer of thin loose strands (``LOOSE``) from a random stream of their own; braids are twisted tubes with
bead rings (``braid_tube``; the second UV's x marks a vertex's kind: 0 a card, 1 a braid, 2 a bead), not
herringbone cards; the crop and the short beard are shells (``SHELLS``: the scalp's or the beard's skin, cut
from the body with its own UVs, which the game stacks into layers at load time; ``shell_cap``), still grown
here as cards first so the random stream of every later style stays as it was; the full and the forked beard
gain a row of cards under the jaw (``UNDER_JAW``), so a beard is there from behind.
"""
from __future__ import annotations

import bpy
import numpy as np

ATLAS_COLUMNS = 4

# The floor's styles (plan §2.3): mesh id -> layers (count, length m human scale, layer lo, hi,
# guide points, sampling power, card width m, curl, wispy-column share of the outer layer).
STYLES = {
    "Hair_long_back": {"kind": "scalp", "layers": [
        dict(n=240, length=0.17, lo=0.006, hi=0.012, npts=6, power=0.6, width=0.042, curl=0.12, wispy=0.0),
        dict(n=180, length=0.21, lo=0.014, hi=0.024, npts=9, power=0.6, width=0.032, curl=0.2, wispy=0.3)],
        "fringe": dict(n=110), "loose": dict(n=40)},
    "Hair_crop": {"kind": "scalp", "layers": [
        dict(n=1100, length=0.065, lo=0.003, hi=0.008, npts=3, power=0.4, width=0.026, curl=0.05, wispy=0.0)]},
    "Beard_full": {"kind": "beard", "layers": [
        dict(n=190, length=0.13, lo=0.004, hi=0.008, npts=7, power=1.0, width=0.03, curl=0.1, wispy=0.0),
        dict(n=120, length=0.16, lo=0.009, hi=0.016, npts=7, power=1.0, width=0.024, curl=0.15, wispy=0.3)],
        "under_jaw": dict(n=40)},
    "Beard_short": {"kind": "beard", "locks": False, "layers": [
        dict(n=560, length=0.05, lo=0.002, hi=0.006, npts=3, power=1.0, width=0.022, curl=0.05, wispy=0.0)]},
}
# The target catalogue's styles (the look pass, P46; plan §2.3). Their layers carry a "grow" (the grower)
# and its parameters; "braids" are plaits built from cards (herringbone lobes on a core), so they need no
# atlas of their own.
STYLES.update({
    "Hair_long_braided": {"kind": "scalp", "layers": [
        dict(n=240, length=0.17, lo=0.006, hi=0.012, npts=7, power=0.6, width=0.042, curl=0.12, wispy=0.0),
        dict(n=110, length=0.19, lo=0.014, hi=0.022, npts=8, power=0.6, width=0.034, curl=0.2, wispy=0.3)],
        "braids": [dict(at="ear", side=s, length=0.27, width=0.034, step=0.017, lean=(0.10 * s, -0.42, -1.0))
                   for s in (1.0, -1.0)], "fringe": dict(n=90), "loose": dict(n=40)},
    "Hair_warrior_tail": {"kind": "scalp", "layers": [
        dict(n=430, length=0.17, lo=0.003, hi=0.007, npts=5, power=0.5, width=0.04, curl=0.04, wispy=0.0,
             grow="knot"),
        dict(n=64, length=0.30, lo=0.0, hi=0.0, npts=9, power=1.0, width=0.034, curl=0.1, wispy=0.25,
             grow="tail")], "fringe": dict(n=90), "loose": dict(n=30, length=0.12)},
    "Hair_wild_mane": {"kind": "scalp", "layers": [
        dict(n=230, length=0.2, lo=0.008, hi=0.016, npts=7, power=0.6, width=0.044, curl=0.1, wispy=0.0,
             wild=0.3, tuck=0.02),
        dict(n=168, length=0.29, lo=0.02, hi=0.045, npts=9, power=0.6, width=0.036, curl=0.3, wispy=0.5,
             wild=0.55, tuck=0.02)], "fringe": dict(n=50), "loose": dict(n=58, length=0.25, wild=0.35)},
    "Beard_braided": {"kind": "beard", "locks": False, "layers": [
        dict(n=300, length=0.1, lo=0.004, hi=0.008, npts=5, power=1.0, width=0.03, curl=0.1, wispy=0.0)],
        "braids": [dict(at="chin", side=s, length=0.17, width=0.027, step=0.014, lean=(0.05 * s, -0.16, -1.0))
                   for s in (1.0, -1.0)]},
    "Beard_forked": {"kind": "beard", "layers": [
        dict(n=190, length=0.15, lo=0.004, hi=0.008, npts=7, power=1.0, width=0.03, curl=0.1, wispy=0.0, fork=1.0),
        dict(n=120, length=0.19, lo=0.009, hi=0.016, npts=7, power=1.0, width=0.024, curl=0.15, wispy=0.3,
             fork=1.0)], "under_jaw": dict(n=36)},
})
# The order the styles are grown in (one random stream, seed HAIR_SEED): the floor's four first, so the
# target's styles leave them as they were.
STYLE_ORDER = ("Hair_long_back", "Hair_crop", "Beard_full", "Beard_short",
               "Hair_long_braided", "Hair_warrior_tail", "Hair_wild_mane", "Beard_braided", "Beard_forked")
HAIR_SEED = 11
# The hairline's fringe (the M10 gate, LC-6): what a style's "fringe" entry does not give. Short, narrow cards
# (three points, four triangles a card), most of them from the atlas's wispy column, lying back over the roots
# of the style's first cards. The long hair's inner layer gave up a point a card for them (7 to 6).
FRINGE = dict(length=0.05, lo=0.008, hi=0.016, npts=3, width=0.013, curl=0.1, wispy=0.7)
FRINGE_SEED = 1011
# A beard's card is at most this share of its own length wide (the cheeks' short cards were squares: steps
# along the beard's sides), and loses this share of its width towards the tip (0.55 on the scalp: a blunt end).
# Not the short and the braided beard ("locks": False): their cards are short, and as narrow locks they left
# gaps on the cheeks.
BEARD_ASPECT = 0.5
BEARD_TAPER = 0.85
SCALP_TAPER = 0.55
# tuck_shoulders: how near the skin (human-scale metres) a point must be to be laid under the garments.
TUCK_REACH = 0.11
# How far a card's shading normal leans from the skin's normal towards the style's head-centred normal (P46: 0.5,
# towards the direction from the head's centre; P51: the whole way, to the volume normal of ``volume_normal``).
NORMAL_ROUND = 1.0
# The loose strands at the hairline and over the long styles (P51): thin, sparse strips off the volume, from a
# random stream of their own per style (LOOSE_SEED), the wispy column.
LOOSE = dict(n=40, length=0.19, lo=0.012, hi=0.03, npts=4, width=0.006, curl=0.0, wild=0.2)
LOOSE_SEED = 2011
# Styles drawn as shells (P51): the skin under the mask (a body vertex attribute) is cut out a little off the
# skin; height_m (human scale) is how far the outermost layer stands; the game builds the layers.
SHELLS = {"Hair_crop": dict(mask="m_scalp", channel="scalp", height=0.012, threshold=0.003, lift=0.0006),
          "Beard_short": dict(mask="m_beard", channel="beard", height=0.010, threshold=0.003, lift=0.0005)}
# The braids as tubes (P51): sides round a tube, the plait's three-strand relief and its twist a step, beads.
BRAID_SIDES = 7
BRAID_RELIEF = 0.22
BRAID_TWIST = 1.1
BEAD_SIDES = 8
BEAD_RADIUS = 0.55          # of the braid's width
BEAD_LENGTH = 0.55          # of the braid's width
# A beard's cards under the jaw (P51): grown from the beard's lowest skin, hanging down and a little back.
UNDER_JAW = dict(n=40, length=0.09, lo=0.004, hi=0.008, npts=4, width=0.03, curl=0.1)
UNDER_JAW_SEED = 3011


def log(*a):
    print("[giant_hair]", *a, flush=True)


# --------------------------------------------------------------------------------------
# the body surface
# --------------------------------------------------------------------------------------
class Surface:
    """The body's rest surface at a subdivision level: vertices, normals, triangles, masks, KD-tree."""

    def __init__(self, body, level=0, attrs=()):
        from scipy.spatial import cKDTree
        ss = body.modifiers.get("Subdivision")
        old = ss.levels if ss else None
        if ss:
            ss.levels = level
        dg = bpy.context.evaluated_depsgraph_get()
        dg.update()
        ev = body.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        n = len(me.vertices)
        V = np.empty(n * 3)
        me.vertices.foreach_get("co", V)
        Nn = np.empty(n * 3)
        me.vertex_normals.foreach_get("vector", Nn)
        T = np.empty(len(me.loop_triangles) * 3, np.int64)
        me.loop_triangles.foreach_get("vertices", T)
        mw = np.array(body.matrix_world)
        self.V = V.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3]
        self.N = Nn.reshape(-1, 3) @ mw[:3, :3].T
        self.N /= np.linalg.norm(self.N, axis=1, keepdims=True) + 1e-12
        self.T = T.reshape(-1, 3)
        self.attr = {}
        for a in attrs:
            if a in me.attributes:
                buf = np.empty(n)
                me.attributes[a].data.foreach_get("value", buf)
                self.attr[a] = buf
        ev.to_mesh_clear()
        if ss:
            ss.levels = old
        self.kd = cKDTree(self.V)
        a = self.V[self.T]
        self.tri_area = 0.5 * np.linalg.norm(np.cross(a[:, 1] - a[:, 0], a[:, 2] - a[:, 0]), axis=1)

    def sample(self, mask, count, rng, power=1.0):
        """Area x mask^power weighted random points: (P, N, mask value, tri index)."""
        m = self.attr[mask] if isinstance(mask, str) else mask
        w = self.tri_area * np.clip(m[self.T].mean(axis=1), 0, 1) ** power
        tot = w.sum()
        if tot <= 0:
            return np.zeros((0, 3)), np.zeros((0, 3)), np.zeros(0), np.zeros(0, int)
        ti = rng.choice(len(w), size=count, p=w / tot)
        r1 = np.sqrt(rng.random(count))
        r2 = rng.random(count)
        b = np.stack([1 - r1, r1 * (1 - r2), r1 * r2], axis=1)
        tri = self.T[ti]
        P = np.einsum("ij,ijk->ik", b, self.V[tri])
        Nn = np.einsum("ij,ijk->ik", b, self.N[tri])
        Nn /= np.linalg.norm(Nn, axis=1, keepdims=True) + 1e-12
        mv = np.einsum("ij,ij->i", b, m[tri])
        return P, Nn, mv, ti

    def nearest(self, P):
        _, i = self.kd.query(P)
        return self.V[i], self.N[i]


def _unit(v):
    return v / (np.linalg.norm(v, axis=-1, keepdims=True) + 1e-12)


def _tangent(v, n):
    return v - n * np.einsum("ij,ij->i", v, n)[:, None]


# --------------------------------------------------------------------------------------
# strand growth
# --------------------------------------------------------------------------------------
def grow(surf, roots, normals, lengths, npts, flow, lift, inertia, w_flow, w_grav, h0, h1,
         gravity_ramp=1.0):
    """Grow strands step by step: flow field + gravity, kept at a layer height above skin.

    flow(P, nrm, s) -> desired direction (N,3) at strand parameter s in [0,1].
    h0/h1: per-strand layer height (m) at root/tip (arrays or floats).
    """
    N = len(roots)
    P = np.zeros((N, npts, 3))
    P[:, 0] = roots
    seg = (lengths / (npts - 1))[:, None]
    nrm = normals.copy()
    d = _unit(_unit(flow(roots, nrm, 0.0)) + normals * lift[:, None])
    G = np.array([0.0, 0.0, -1.0])
    h0 = np.broadcast_to(np.asarray(h0, float), (N,))
    h1 = np.broadcast_to(np.asarray(h1, float), (N,))
    for k in range(1, npts):
        s = k / (npts - 1)
        t = _unit(flow(P[:, k - 1], nrm, s))
        wg = w_grav * s ** gravity_ramp
        d = _unit(d * inertia + t * w_flow + G * wg)
        Pn = P[:, k - 1] + d * seg
        v, nn = surf.nearest(Pn)
        dist = np.einsum("ij,ij->i", Pn - v, nn)
        h = h0 + (h1 - h0) * s
        push = np.maximum(0.0, h - dist)
        Pn = Pn + nn * push[:, None]
        d = _unit(Pn - P[:, k - 1])
        P[:, k] = P[:, k - 1] + d * seg
        nrm = nn
    return P


def post_collide(surf, P, hmin):
    """Push every point (except roots) at least ``hmin`` outside the skin."""
    sh = P.shape
    Q = P[:, 1:].reshape(-1, 3)
    for _ in range(2):
        v, nn = surf.nearest(Q)
        dist = np.einsum("ij,ij->i", Q - v, nn)
        Q = Q + nn * np.maximum(0.0, hmin - dist)[:, None]
    P = P.copy()
    P[:, 1:] = Q.reshape(sh[0], sh[1] - 1, 3)
    return P


def tuck_shoulders(surf, P, L, S, hs, tuck):
    """Lay every point under the head that is near the body within ``tuck`` (human-scale metres) of the skin:
    under the garments of the shoulders (the furs stand 0.05-0.07 off, the cape 0.05, the jerkin 0.045), as
    the other long styles lie, so no lock dips in and out of one (the wild mane's flecks on the furs; the M10
    gate, LC-6). A lock that flies free (further than ``TUCK_REACH`` off the skin) stays where it is."""
    sh = P.shape
    Q = P[:, 1:].reshape(-1, 3).copy()
    for _ in range(3):
        v, nn = surf.nearest(Q)
        dist = np.einsum("ij,ij->i", Q - v, nn)
        under = np.clip((L["chin"] - Q[:, 2]) / (0.05 * hs * S), 0.0, 1.0) * (dist < TUCK_REACH * S)
        Q = Q - nn * (np.maximum(0.0, dist - tuck * S) * under)[:, None]
    P = P.copy()
    P[:, 1:] = Q.reshape(sh[0], sh[1] - 1, 3)
    return P


def grow_scalp(surf, L, S, hs, rng, n, length, layer_lo, layer_hi, npts=10, power=0.6, wild=0.0, tuck=0.0):
    roots, nrm, mv, _ = surf.sample("m_scalp", n, rng, power=power)
    roots += nrm * 0.0004 * S
    front = np.array([0.0, L["face_y"] - 0.07 * hs * S, L["brow_z"] + 0.06 * hs * S])

    def flow(P, nn, s):
        radial = _unit(P - front)
        down = np.array([0.0, 0.25, -1.0])
        v = radial + down * (0.25 + 1.2 * s)
        return _unit(_tangent(v, nn) * (1.0 - 0.6 * s) + v * 0.6 * s)

    Lh = length * S * (0.75 + 0.5 * rng.random(n)) * (0.4 + 0.6 * np.clip(mv, 0, 1) ** 0.7)
    lift = 0.35 + 0.3 * rng.random(n)
    layer = (layer_lo + (layer_hi - layer_lo) * rng.random(n)) * hs * S
    if wild > 0.0:
        # the mane (P46): the locks stand off the head, each with a bend of its own, and hang less
        lift = lift + wild * (0.5 + 0.6 * rng.random(n))
        kick = rng.normal(size=(n, 3)) * 0.4 * wild
        base_flow = flow

        def flow(P, nn, s):   # noqa: F811
            return _unit(base_flow(P, nn, s) + kick * (0.3 + 0.7 * s) + nn * 0.5 * wild * (1.0 - s))

        P = grow(surf, roots, nrm, Lh, npts, flow, lift, 0.6, 0.9, 0.3, 0.0015 * S, layer)
        P = post_collide(surf, P, 0.0015 * S)
        return tuck_shoulders(surf, P, L, S, hs, tuck) if tuck > 0.0 else P
    P = grow(surf, roots, nrm, Lh, npts, flow, lift, 0.55, 0.9, 0.55, 0.0015 * S, layer)
    return post_collide(surf, P, 0.0015 * S)


def grow_fringe(surf, L, S, hs, rng, n, length, layer_lo, layer_hi, npts=3):
    """The hairline's fringe (the M10 gate, LC-6): ``n`` short guides rooted evenly along the front of the
    scalp's edge (forehead, temples, in front of the ears), lying back along the scalp's own flow over the
    roots of the style's cards. Candidates are drawn on the triangles the scalp mask's edge crosses and the
    roots are picked farthest-first among them, so the row has no gap (the bare notch above the temple)."""
    m = np.clip(surf.attr["m_scalp"], 0.0, 1.0)
    tm = m[surf.T]
    _Vs, _Ns, c, _ztop, _yback, _zmin = _scalp_frame(surf)
    cen = surf.V[surf.T].mean(axis=1)
    edge = np.clip(1.0 - np.abs(tm.mean(axis=1) - 0.5) / 0.5, 0.0, 1.0) * (tm.max(axis=1) > 0.05)
    w = surf.tri_area * edge * (cen[:, 1] < c[1])            # the front half of the head (-Y is the face)
    count = 24 * n
    ti = rng.choice(len(w), size=count, p=w / w.sum())
    r1 = np.sqrt(rng.random(count))
    r2 = rng.random(count)
    b = np.stack([1 - r1, r1 * (1 - r2), r1 * r2], axis=1)
    tri = surf.T[ti]
    cand = np.einsum("ij,ijk->ik", b, surf.V[tri])
    cn = _unit(np.einsum("ij,ijk->ik", b, surf.N[tri]))
    mv = np.einsum("ij,ij->i", b, m[tri])
    ok = np.nonzero((mv > 0.08) & (mv < 0.6))[0]
    cand, cn = cand[ok], cn[ok]
    pick = [0]
    d = np.linalg.norm(cand - cand[0], axis=1)
    for _ in range(min(n, len(cand)) - 1):
        i = int(np.argmax(d))
        pick.append(i)
        d = np.minimum(d, np.linalg.norm(cand - cand[i], axis=1))
    roots, nrm = cand[pick] + cn[pick] * 0.0006 * S, cn[pick]
    k = len(roots)
    front = np.array([0.0, L["face_y"] - 0.07 * hs * S, L["brow_z"] + 0.06 * hs * S])

    def flow(P, nn, s):
        v = _unit(P - front) + np.array([0.0, 0.25, -1.0]) * (0.2 + 0.6 * s)
        return _unit(_tangent(v, nn))

    Lh = length * S * (0.7 + 0.6 * rng.random(k))
    lift = 0.05 + 0.1 * rng.random(k)
    layer = (layer_lo + (layer_hi - layer_lo) * rng.random(k)) * hs * S
    P = grow(surf, roots, nrm, Lh, npts, flow, lift, 0.5, 0.9, 0.2, 0.002 * S, layer)
    return post_collide(surf, P, 0.002 * S)


def _scalp_frame(surf):
    """The scalp's vertices, their centre and the top, back and bottom of the scalp."""
    sel = surf.attr["m_scalp"] > 0.5
    Vs, Ns = surf.V[sel], surf.N[sel]
    return Vs, Ns, Vs.mean(axis=0), Vs[:, 2].max(), Vs[:, 1].max(), Vs[:, 2].min()


def knot_point(surf, S):
    """Where the warrior's tail is tied: high on the back of the head, a little off the scalp."""
    Vs, Ns, c, ztop, yback, _zmin = _scalp_frame(surf)
    target = np.array([0.0, c[1] + 0.62 * (yback - c[1]), c[2] + 0.8 * (ztop - c[2])])
    i = int(np.argmin(np.linalg.norm(Vs - target, axis=1)))
    return Vs[i] + Ns[i] * 0.012 * S


def grow_knot(surf, L, S, hs, rng, n, length, layer_lo, layer_hi, npts=5, power=0.5):
    """The warrior's tail, on the head: every lock lies flat and runs to the knot."""
    roots, nrm, mv, _ = surf.sample("m_scalp", n, rng, power=power)
    roots += nrm * 0.0004 * S
    knot = knot_point(surf, S)

    def flow(P, nn, s):
        return _unit(_tangent(knot - P, nn))

    dist = np.linalg.norm(roots - knot, axis=1)
    Lh = np.clip(dist * (0.75 + 0.35 * rng.random(n)), 0.04 * S, length * S)
    lift = 0.05 + 0.08 * rng.random(n)
    layer = (layer_lo + (layer_hi - layer_lo) * rng.random(n)) * hs * S
    P = grow(surf, roots, nrm, Lh, npts, flow, lift, 0.35, 1.0, 0.0, 0.001 * S, layer)
    return post_collide(surf, P, 0.001 * S)


def grow_tail(surf, L, S, hs, rng, n, length, layer_lo, layer_hi, npts=9, power=1.0):
    """The warrior's tail, off the head: locks from the knot, out behind the head and down the back."""
    knot = knot_point(surf, S)
    G = np.array([0.0, 0.0, -1.0])
    start = knot + rng.normal(size=(n, 3)) * 0.012 * S
    d = _unit(np.array([0.0, 0.85, 0.35]) + rng.normal(size=(n, 3)) * 0.22)
    Lh = length * S * (0.75 + 0.35 * rng.random(n))
    seg = (Lh / (npts - 1))[:, None]
    P = np.zeros((n, npts, 3))
    P[:, 0] = start
    for k in range(1, npts):
        d = _unit(d * 0.62 + G * 0.5)
        P[:, k] = P[:, k - 1] + d * seg
    return post_collide(surf, P, 0.012 * S)


def grow_beard(surf, L, S, hs, rng, n, length, layer_lo, layer_hi, npts=8, power=1.0, fork=0.0):
    roots, nrm, mv, _ = surf.sample("m_beard", n, rng, power=power)
    roots += nrm * 0.0003 * S
    chin, lip_bot, lip_top = L["chin"], L["lip_bot"], L["lip_top"]
    z = roots[:, 2]
    must = (z > lip_bot) & (np.abs(roots[:, 0]) < 0.045 * hs * S) & (roots[:, 1] < L["face_y"] + 0.05 * hs * S)
    zr = np.clip((lip_top - z) / ((lip_top - chin) + 0.04 * hs * S), 0, 1.4)
    base = length * S * (0.3 + 0.7 * np.clip(zr, 0, 1) ** 1.3)
    base = np.where(must, 0.035 * hs * S, base)
    Lb = base * (0.8 + 0.4 * rng.random(n)) * (0.55 + 0.45 * np.clip(mv, 0, 1))
    side = np.sign(roots[:, 0])[:, None]
    # the forked beard (P46): short under the middle of the chin, long to either side of it, and the
    # strands of each half gather towards its point
    off = np.abs(roots[:, 0]) / (0.04 * hs * S)
    if fork > 0.0:
        Lb = np.where(must, Lb, Lb * (0.22 + 0.95 * np.clip(off, 0.0, 1.0)))
    tine = 0.05 * hs * S

    def flow(P, nn, s):
        down = np.array([0.0, -0.18, -1.0])
        lateral = np.concatenate([side * 0.55, np.zeros((len(P), 1)), np.zeros((len(P), 1))], axis=1)
        v = np.where(must[:, None], down + lateral + nn * 0.3, down + nn * (0.35 * (1 - s)))
        if fork > 0.0:
            to_tine = np.zeros_like(P)
            to_tine[:, 0] = (side[:, 0] * tine - P[:, 0]) / (0.03 * hs * S)
            v = np.where(must[:, None], v, v + to_tine * 1.3 * fork * s + lateral * 0.5 * fork * (1 - s))
        return _unit(v)

    lift = np.where(must, 0.5, 0.4) + 0.3 * rng.random(n)
    layer = (layer_lo + (layer_hi - layer_lo) * rng.random(n)) * hs * S
    P = grow(surf, roots, nrm, Lb, npts, flow, lift, 0.5, 0.7, 0.9, 0.001 * S, layer)
    return post_collide(surf, P, 0.0012 * S)


# --------------------------------------------------------------------------------------
# cards
# --------------------------------------------------------------------------------------
def ribbons(surf, P, widths, col_idx, curl, centre=None, facing=None, taper=SCALP_TAPER):
    """Guides P (N, K, 3) -> card vertices, faces (quads), uvs, normals. ``facing`` (N, 3) replaces the
    skin's normal as the way each card faces (a braid's lobes); a card loses ``taper`` of its width
    towards its tip."""
    N, K, _ = P.shape
    T = np.gradient(P, axis=1)
    T /= np.linalg.norm(T, axis=2, keepdims=True) + 1e-12
    _, nrm = surf.nearest(P.reshape(-1, 3))
    nrm = nrm.reshape(N, K, 3)
    skin_nrm = nrm
    if facing is not None:
        nrm = np.repeat(_unit(facing)[:, None, :], K, axis=1)
    side = np.cross(nrm, T)
    side /= np.linalg.norm(side, axis=2, keepdims=True) + 1e-12
    s = np.linspace(0, 1, K)[None, :, None]
    w = widths[:, None, None] * (1.0 - taper * s ** 1.4)
    c = curl[:, None, None] * w
    Lft = P - side * w * 0.5 - nrm * c
    Rgt = P + side * w * 0.5 - nrm * c
    V = np.stack([Lft, Rgt], axis=2).reshape(N, K * 2, 3)            # per card: l0 r0 l1 r1 ...
    # The shading normal: the head's normal under the card, turned towards the style's head-centred normal
    # (P46 half-way, towards the direction from the head's centre; P51 the whole way, to volume_normal), so
    # neighbouring cards over the jaw, the ears and the temples are lit alike and a style shades as one volume.
    if centre is not None:
        shade = _unit(skin_nrm * (1.0 - NORMAL_ROUND) + volume_normal(P, centre) * NORMAL_ROUND)
    else:
        shade = skin_nrm
    Nn = np.stack([shade, shade], axis=2).reshape(N, K * 2, 3)
    faces = []
    for k in range(K - 1):
        a = 2 * k
        faces.append((a, a + 2, a + 3, a + 1))
    faces = np.array(faces)
    F = (faces[None, :, :] + (np.arange(N) * K * 2)[:, None, None]).reshape(-1, 4)
    u0 = col_idx / ATLAS_COLUMNS
    uu = np.stack([u0 + 0.004, u0 + 1.0 / ATLAS_COLUMNS - 0.004], axis=1)    # (N, 2)
    vv = 1.0 - np.linspace(0, 1, K)                                          # Blender v: root at the top
    UV = np.zeros((N, K, 2, 2))
    UV[:, :, 0, 0] = uu[:, None, 0]
    UV[:, :, 1, 0] = uu[:, None, 1]
    UV[:, :, :, 1] = vv[None, :, None]
    return V.reshape(-1, 3), F, UV.reshape(-1, 2), Nn.reshape(-1, 3)


def volume_normal(P, centre):
    """The style's head-centred normal at points P (..., 3) (P51): outward from the head's centre above it and
    from the vertical axis through the centre below it (hanging hair and a beard face out, not down)."""
    C = np.broadcast_to(np.asarray(centre, float), P.shape).copy()
    C[..., 2] = np.minimum(P[..., 2], C[..., 2])
    return _unit(P - C)


def grow_under_jaw(surf, L, S, hs, rng, n, length, layer_lo, layer_hi, npts=5):
    """A row of beard cards under the jaw (P51): rooted on the beard's skin below the chin's height, hanging
    down and a little back, so the beard has a body seen from behind and from below."""
    m = np.clip(surf.attr["m_beard"], 0.0, 1.0) * (surf.V[:, 2] < L["chin"] + 0.01 * hs * S)
    roots, nrm, mv, _ = surf.sample(m, n, rng, power=1.0)
    roots += nrm * 0.0003 * S

    def flow(P, nn, s):
        return _unit(np.array([0.0, 0.25, -1.0]) + nn * 0.2 * (1.0 - s))

    Lb = length * S * (0.7 + 0.5 * rng.random(len(roots)))
    lift = 0.3 + 0.2 * rng.random(len(roots))
    layer = (layer_lo + (layer_hi - layer_lo) * rng.random(len(roots))) * hs * S
    P = grow(surf, roots, nrm, Lb, npts, flow, lift, 0.5, 0.7, 0.9, 0.001 * S, layer)
    return post_collide(surf, P, 0.0012 * S)


def braid_tube(path, width, S, centre):
    """A braid as a twisted tube along ``path`` (K, 3) (P51): BRAID_SIDES round, its radius rippling with the
    three strands of a plait (BRAID_RELIEF) that turn BRAID_TWIST radians a ring, narrowing towards the tie, and
    a bead ring at its tie and one at two fifths. Returns V, F (quads), UV, normals and UV2 (1 the tube, 2 the
    beads); the tube's u runs round the atlas's dense column, its v from the root (1) to the tie (0)."""
    K = len(path)
    w = width * S
    T = np.gradient(path, axis=0)
    T /= np.linalg.norm(T, axis=1, keepdims=True) + 1e-12
    out0 = volume_normal(path[0], centre)
    Vs, Fs, UVs, Ns, U2 = [], [], [], [], []
    frames = []
    ref = _unit(out0 - T[0] * float(out0 @ T[0]))
    for i in range(K):
        x = _unit(ref - T[i] * float(ref @ T[i]))
        y = np.cross(T[i], x)
        frames.append((x, y))
        ref = x
    ring = BRAID_SIDES + 1
    for i in range(K):
        x, y = frames[i]
        thin = 1.0 - 0.45 * (i / (K - 1)) ** 2
        for j in range(ring):
            a = 2.0 * np.pi * j / BRAID_SIDES
            rel = 1.0 + BRAID_RELIEF * np.cos(3.0 * a + BRAID_TWIST * i)
            d = np.cos(a) * x + np.sin(a) * y
            Vs.append(path[i] + d * 0.5 * w * thin * rel)
            Ns.append(d)
            UVs.append((0.004 + 0.242 * j / BRAID_SIDES, 1.0 - i / (K - 1)))
            U2.append((1.0, 0.0))
    for i in range(K - 1):
        for j in range(BRAID_SIDES):
            a = i * ring + j
            Fs.append((a, a + ring, a + ring + 1, a + 1))
    # beads: short rings round the tube
    for at in (int(round(0.4 * (K - 1))), K - 2):
        base = len(Vs)
        x, y = frames[at]
        r = BEAD_RADIUS * w
        for e, off in enumerate((-0.5, 0.5)):
            c = path[at] + T[at] * off * BEAD_LENGTH * w
            for j in range(BEAD_SIDES + 1):
                a = 2.0 * np.pi * j / BEAD_SIDES
                d = np.cos(a) * x + np.sin(a) * y
                Vs.append(c + d * r)
                Ns.append(_unit(d + T[at] * off * 0.6))
                UVs.append((0.004 + 0.242 * j / BEAD_SIDES, 1.0 - at / (K - 1)))
                U2.append((2.0, 0.0))
        for j in range(BEAD_SIDES):
            a = base + j
            Fs.append((a, a + BEAD_SIDES + 1, a + BEAD_SIDES + 2, a + 1))
    return np.asarray(Vs), np.asarray(Fs), np.asarray(UVs), np.asarray(Ns), np.asarray(U2)


def shell_cap(A, mask, S, threshold, lift):
    """The skin a shell style grows on (P51): the body faces whose vertices' mean ``mask`` (per body vertex) is
    above ``threshold``, lifted ``lift`` (human-scale metres) along the skin's normal, with the body's own UVs
    (the game reads the hair's density from the skin's mask map there). Returns (arrays for make_object, the
    body vertex of each cap vertex)."""
    faces = [f for f in A["faces"] if float(np.mean(mask[list(f)])) > threshold]
    keep = sorted({v for f in faces for v in f})
    remap = {v: i for i, v in enumerate(keep)}
    ids = np.asarray(keep, np.int64)
    V = A["V"][ids] + A["vnormal"][ids] * lift * S
    face_index = {tuple(f): k for k, f in enumerate(A["faces"])}
    corner_uv = [A["corner_uv"][face_index[tuple(f)]] for f in faces]
    out = {"V": V, "faces": [tuple(remap[v] for v in f) for f in faces], "corner_uv": corner_uv,
           "corner_normal": [[tuple(A["vnormal"][v]) for v in f] for f in faces],
           "groups": {"head": np.ones(len(ids))}}
    return out, ids


# The vertices of each style that belong to its braids (tubes and beads), set by build_styles (P51; the
# export's skin hangs them whole from where they leave the head).
BRAID_MASKS = {}


def braid_start(surf, L, S, hs, at, side):
    """Where a braid leaves the head: behind an ear ("ear") or under the chin ("chin")."""
    if at == "ear":
        Vs, Ns, c, _ztop, _yback, zmin = _scalp_frame(surf)
        target = np.array([side * (np.abs(Vs[:, 0]).max() + 0.01 * S), c[1] + 0.01 * S, c[2] - 0.45 * (c[2] - zmin)])
        i = int(np.argmin(np.linalg.norm(Vs - target, axis=1)))
        return Vs[i] + Ns[i] * 0.008 * S
    sel = surf.attr["m_beard"] > 0.5
    Vb, Nb = surf.V[sel], surf.N[sel]
    target = np.array([side * 0.02 * hs * S, Vb[:, 1].min(), L["chin"] - 0.005 * hs * S])
    i = int(np.argmin(np.linalg.norm(Vb - target, axis=1)))
    return Vb[i] + Nb[i] * 0.01 * S


def braid_guides(surf, S, start, lean, length, width, step):
    """A braid as card guides: (lobes (n, 3, 3), their facings, core (1, K, 3)). The path hangs from
    ``start`` along ``lean`` and is kept off the body; every ``step`` a lobe crosses from each edge down
    to the middle (a herringbone), on two planes at right angles so the braid has a body from the side."""
    n_steps = max(4, int(round(length * S / (step * S))))
    d = _unit(np.asarray(lean, float))
    path = start[None, :] + d[None, :] * (np.arange(n_steps + 2)[:, None] * step * S)
    path = post_collide(surf, path[None, :, :], 0.014 * S)[0]
    _, nrm = surf.nearest(path)
    lobes, facing = [], []
    w = width * S
    for i in range(n_steps):
        t = _unit(path[i + 1] - path[i])
        out = _unit(nrm[i] - t * float(nrm[i] @ t))
        u = _unit(np.cross(out, t))
        thin = 1.0 - 0.45 * (i / n_steps) ** 2          # the braid narrows towards its tie
        for plane_u, plane_n in ((u, out), (out, u)):
            for sgn in (1.0, -1.0):
                a = path[i] + plane_u * sgn * 0.42 * w * thin
                m = path[i] + t * 0.9 * step * S + plane_u * sgn * 0.2 * w * thin
                b = path[i] + t * 1.9 * step * S - plane_u * sgn * 0.05 * w * thin
                lobes.append(np.stack([a, m, b]))
                facing.append(plane_n)
    return np.array(lobes), np.array(facing), path[None, :, :]


def card_object(name, V, F, UV, Nn, coll, rig, mat_name, UV2=None):
    import giant_body as gb
    me = bpy.data.meshes.new(name)
    me.from_pydata(V.tolist(), [], F.tolist())
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    lv = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", lv)
    uvl.data.foreach_set("uv", UV[lv].astype(np.float32).ravel())
    if UV2 is not None:
        # P51: the vertex's kind (0 a card, 1 a braid's tube, 2 a bead) for the hair shader; a style without
        # braids carries no second UV (the shader reads 0)
        uv2 = me.uv_layers.new(name="UV2")
        uv2.data.foreach_set("uv", UV2[lv].astype(np.float32).ravel())
    me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), dtype=bool))
    me.normals_split_custom_set_from_vertices(Nn.tolist())
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    vg = ob.vertex_groups.new(name="head")
    vg.add(list(range(len(V))), 1.0, "REPLACE")
    gb.parent_keep(ob, rig)
    gb.armature_modifier(ob, rig)
    ob.data.materials.append(bpy.data.materials.get(mat_name) or bpy.data.materials.new(mat_name))
    return ob


def build_styles(body, rig, coll, bd, S):
    """Grow every floor style on the unsubdivided body; returns {mesh id: (object, cards)}."""
    land = bd.landmarks
    L = {k: (np.asarray(v) * S if isinstance(v, (list, tuple)) else (v * S if isinstance(v, float) else v))
         for k, v in land.items() if k != "hs"}
    hs = land["hs"]
    surf = Surface(body, 0, ("m_scalp", "m_beard", "m_head"))
    rng = np.random.default_rng(HAIR_SEED)
    wh = np.clip(surf.attr["m_head"], 0, 1)
    centre = (surf.V * wh[:, None]).sum(axis=0) / wh.sum()
    out = {}
    for mesh_id in STYLE_ORDER:
        style = STYLES[mesh_id]
        Vs, Fs, UVs, Ns = [], [], [], []
        off = 0
        cards = 0
        for ly in style["layers"]:
            grower = grow_scalp if style["kind"] == "scalp" else grow_beard
            extra = {k: ly[k] for k in ("wild", "fork", "tuck") if k in ly}
            if ly.get("grow") == "knot":
                grower = grow_knot
            elif ly.get("grow") == "tail":
                grower = grow_tail
            P = grower(surf, L, S, hs, rng, ly["n"], ly["length"], ly["lo"], ly["hi"], npts=ly["npts"],
                       power=ly["power"], **extra)
            n = len(P)
            width = ly["width"] * S * (0.8 + 0.4 * rng.random(n))
            if ly["wispy"] > 0:
                cols = np.where(rng.random(n) < ly["wispy"], 3, rng.integers(0, 3, n))
            else:
                cols = rng.integers(0, 3, n)
            taper = SCALP_TAPER
            if style["kind"] == "beard" and style.get("locks", True):
                along = np.linalg.norm(np.diff(P, axis=1), axis=2).sum(axis=1)
                width = np.minimum(width, BEARD_ASPECT * along)
                taper = BEARD_TAPER
            V, F, UV, Nn = ribbons(surf, P, width, cols, np.full(n, ly["curl"]), centre, taper=taper)
            Vs.append(V)
            Fs.append(F + off)
            UVs.append(UV)
            Ns.append(Nn)
            off += len(V)
            cards += n
        if "fringe" in style:
            # a random stream of its own per style: the other cards of every style stay as they were grown
            fr = dict(FRINGE, **style["fringe"])
            frng = np.random.default_rng([FRINGE_SEED, STYLE_ORDER.index(mesh_id)])
            P = grow_fringe(surf, L, S, hs, frng, fr["n"], fr["length"], fr["lo"], fr["hi"], npts=fr["npts"])
            n = len(P)
            width = fr["width"] * S * (0.8 + 0.4 * frng.random(n))
            cols = np.where(frng.random(n) < fr["wispy"], 3, frng.integers(0, 3, n))
            V, F, UV, Nn = ribbons(surf, P, width, cols, np.full(n, fr["curl"]), centre, taper=0.7)
            Vs.append(V)
            Fs.append(F + off)
            UVs.append(UV)
            Ns.append(Nn)
            off += len(V)
            cards += n
        if "loose" in style:
            # P51: thin loose strands off the style's volume, from a random stream of their own
            lo = dict(LOOSE, **style["loose"])
            lrng = np.random.default_rng([LOOSE_SEED, STYLE_ORDER.index(mesh_id)])
            P = grow_scalp(surf, L, S, hs, lrng, lo["n"], lo["length"], lo["lo"], lo["hi"], npts=lo["npts"],
                           power=0.6, wild=lo["wild"])
            # only strands that hang back or down over the style: none falls forward over the face
            back = ((P[:, -1, 1] - P[:, 0, 1] > -0.005 * S) & (P[:, 1:, 2] < P[:, :1, 2] + 0.004 * S).all(axis=1)
                    & (P[:, 0, 1] > centre[1] - 0.02 * S))
            P = P[back]
            n = len(P)
            width = lo["width"] * S * (0.7 + 0.6 * lrng.random(n))
            V, F, UV, Nn = ribbons(surf, P, width, np.full(n, 3), np.full(n, lo["curl"]), centre, taper=0.8)
            Vs.append(V)
            Fs.append(F + off)
            UVs.append(UV)
            Ns.append(Nn)
            off += len(V)
            cards += n
        if "under_jaw" in style:
            # P51: a row of cards under the jaw, so a beard is there from behind and from below
            uj = dict(UNDER_JAW, **style["under_jaw"])
            urng = np.random.default_rng([UNDER_JAW_SEED, STYLE_ORDER.index(mesh_id)])
            P = grow_under_jaw(surf, L, S, hs, urng, uj["n"], uj["length"], uj["lo"], uj["hi"], npts=uj["npts"])
            n = len(P)
            along = np.linalg.norm(np.diff(P, axis=1), axis=2).sum(axis=1)
            width = np.minimum(uj["width"] * S * (0.8 + 0.4 * urng.random(n)), BEARD_ASPECT * along)
            V, F, UV, Nn = ribbons(surf, P, width, urng.integers(0, 3, n), np.full(n, uj["curl"]), centre,
                                   taper=BEARD_TAPER)
            Vs.append(V)
            Fs.append(F + off)
            UVs.append(UV)
            Ns.append(Nn)
            off += len(V)
            cards += n
        card_verts = off
        U2s = []
        for br in style.get("braids", ()):
            # P51: a twisted tube with beads along the braid's path (it was herringbone cards)
            start = braid_start(surf, L, S, hs, br["at"], br["side"])
            _lobes, _facing, core = braid_guides(surf, S, start, br["lean"], br["length"], br["width"], br["step"])
            V, F, UV, Nn, u2 = braid_tube(core[0], br["width"], S, centre)
            U2s.append(u2)
            Vs.append(V)
            Fs.append(F + off)
            UVs.append(UV)
            Ns.append(Nn)
            off += len(V)
            cards += 1
        if mesh_id in SHELLS:
            # P51: a shell style; its cards were grown above only to keep the random stream of the later styles
            out[mesh_id] = (None, 0)
            log(f"{mesh_id}: a shell style (its skin is cut in export_game)")
            continue
        V_all = np.concatenate(Vs)
        UV2 = None
        if off > card_verts:
            kinds = np.zeros((off, 2))
            kinds[card_verts:] = np.concatenate(U2s)
            UV2 = kinds
        BRAID_MASKS[mesh_id] = np.arange(off) >= card_verts
        mat = "giant_hair" if style["kind"] == "scalp" else "giant_beard"
        ob = card_object(mesh_id, V_all, np.concatenate(Fs), np.concatenate(UVs),
                         np.concatenate(Ns), coll, rig, mat, UV2)
        out[mesh_id] = (ob, cards)
        log(f"{mesh_id}: {cards} cards, {len(ob.data.polygons) * 2} triangles")
    return out

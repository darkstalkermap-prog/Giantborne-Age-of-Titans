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

import giant_body as gb

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
        dict(n=190, length=0.13, lo=0.004, hi=0.008, npts=6, power=1.0, width=0.03, curl=0.1, wispy=0.0),
        dict(n=120, length=0.16, lo=0.009, hi=0.016, npts=6, power=1.0, width=0.024, curl=0.15, wispy=0.3)],
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
        dict(n=190, length=0.15, lo=0.004, hi=0.008, npts=6, power=1.0, width=0.03, curl=0.1, wispy=0.0, fork=1.0),
        dict(n=120, length=0.19, lo=0.009, hi=0.016, npts=6, power=1.0, width=0.024, curl=0.15, wispy=0.3,
             fork=1.0)], "under_jaw": dict(n=36)},
})
# The catalogue II (P56; plan M11 §2.6, §3.9): five hair and four beard styles, every one with bead anchors. A
# layer's "grow" picks its grower ("knot" and "tail" take an "at": the back knot or the crown; "toward" combs the
# locks to the braids' roots), a "region" narrows the skin it grows on ("strip": the top of a side-shaved head;
# "chops": the beard without the chin; "mustache": the upper lip). A braid's "at" is where it leaves the head
# (see braid_start), its "ties" the share of its length where a tie ring sits, its "beads" where the bead sets
# (bead_shapes) sit on it; "lean" the way it hangs; "grow": True lets it fall along the body (twin braids over the
# chest) instead of a straight line pushed off the skin.
STYLES.update({
    "Hair_top_knot": {"kind": "scalp", "layers": [
        dict(n=420, length=0.18, lo=0.003, hi=0.007, npts=5, power=0.5, width=0.04, curl=0.04, wispy=0.0,
             grow="knot", at="crown"),
        dict(n=90, length=0.10, lo=0.0, hi=0.0, npts=5, power=1.0, width=0.036, curl=0.12, wispy=0.35,
             grow="tail", at="crown")], "fringe": dict(n=70),
        "braids": [dict(at="crown", side=0.0, length=0.24, width=0.032, step=0.016, lean=(0.0, 0.75, -1.0),
                        ties=(1.0,), beads=(0.3, 0.55, 0.8))]},
    "Hair_side_braids": {"kind": "scalp", "layers": [
        dict(n=300, length=0.2, lo=0.003, hi=0.008, npts=6, power=0.5, width=0.038, curl=0.05, wispy=0.0,
             grow="toward", region="strip"),
        dict(n=120, length=0.22, lo=0.009, hi=0.014, npts=7, power=0.7, width=0.032, curl=0.12, wispy=0.3,
             grow="toward", region="strip")], "fringe": dict(n=36, region="strip"),
        "braids": [dict(at="back", side=0.0, length=0.34, width=0.044, step=0.017, lean=(0.0, 0.3, -1.0),
                        ties=(1.0,), beads=(0.25, 0.5, 0.75)),
                   dict(at="back_side", side=1.0, length=0.2, width=0.022, step=0.014, lean=(0.08, 0.3, -1.0),
                        ties=(1.0,), beads=(0.55,)),
                   dict(at="back_side", side=-1.0, length=0.2, width=0.022, step=0.014, lean=(-0.08, 0.3, -1.0),
                        ties=(1.0,), beads=(0.55,))]},
    "Hair_twin_braids": {"kind": "scalp", "layers": [
        dict(n=300, length=0.2, lo=0.003, hi=0.008, npts=6, power=0.5, width=0.04, curl=0.05, wispy=0.0,
             grow="toward"),
        dict(n=130, length=0.22, lo=0.009, hi=0.015, npts=6, power=0.7, width=0.034, curl=0.1, wispy=0.25,
             grow="toward")], "fringe": dict(n=80),
        "cover": dict(n=48, length=0.12, lo=0.006, hi=0.016, npts=4, width=0.065, curl=0.05),
        "braids": [dict(at="nape_side", side=s, length=0.56, width=0.04, step=0.018, lean=(0.22 * s, -0.55, -1.0),
                        ties=(1.0,), beads=(0.35, 0.6, 0.85), grow=True) for s in (1.0, -1.0)]},
    "Hair_long_loose": {"kind": "scalp", "layers": [
        dict(n=230, length=0.21, lo=0.006, hi=0.012, npts=6, power=0.6, width=0.044, curl=0.12, wispy=0.0,
             tuck=0.02),
        dict(n=150, length=0.33, lo=0.014, hi=0.03, npts=9, power=0.6, width=0.036, curl=0.22, wispy=0.4,
             wild=0.15, tuck=0.02)], "fringe": dict(n=80), "loose": dict(n=44, length=0.3, wild=0.25),
        "braids": [dict(at="temple", side=s, length=0.26, width=0.018, step=0.013, lean=(0.1 * s, -0.25, -1.0),
                        ties=(1.0,), beads=(0.45, 0.75), grow=True) for s in (1.0, -1.0)]},
    "Hair_circlet_braid": {"kind": "scalp", "layers": [
        dict(n=260, length=0.15, lo=0.004, hi=0.009, npts=6, power=0.6, width=0.042, curl=0.1, wispy=0.0),
        dict(n=150, length=0.2, lo=0.011, hi=0.018, npts=7, power=0.6, width=0.034, curl=0.18, wispy=0.3)],
        "fringe": dict(n=80),
        "braids": [dict(at="circlet", side=0.0, length=0.0, width=0.022, step=0.013, lean=(0.0, 0.0, 0.0),
                        ties=(0.0,), beads=(0.125, 0.25, 0.375, 0.625, 0.75, 0.875))]},
    "Beard_chin_braid": {"kind": "beard", "locks": False, "layers": [
        dict(n=340, length=0.09, lo=0.004, hi=0.008, npts=5, power=1.0, width=0.022, curl=0.1, wispy=0.2)],
        "braids": [dict(at="chin", side=0.0, length=0.26, width=0.038, step=0.015, lean=(0.0, -0.2, -1.0),
                        ties=(1.0,), beads=(0.3, 0.55, 0.8))]},
    "Beard_long_forked": {"kind": "beard", "layers": [
        dict(n=160, length=0.24, lo=0.004, hi=0.008, npts=6, power=1.0, width=0.03, curl=0.1, wispy=0.0, fork=1.0),
        dict(n=110, length=0.3, lo=0.009, hi=0.016, npts=7, power=1.0, width=0.024, curl=0.15, wispy=0.3,
             fork=1.0)], "under_jaw": dict(n=30),
        "braids": [dict(at="tine", side=s, length=0.1, width=0.03, step=0.014, lean=(0.02 * s, -0.1, -1.0),
                        ties=(1.0,), beads=(0.45,)) for s in (1.0, -1.0)]},
    "Beard_mutton_chops": {"kind": "beard", "locks": False, "edge": dict(n=90), "layers": [
        dict(n=400, length=0.06, lo=0.004, hi=0.009, npts=4, power=1.0, width=0.028, curl=0.1, wispy=0.15,
             region="chops"),
        dict(n=160, length=0.075, lo=0.009, hi=0.014, npts=4, power=1.0, width=0.022, curl=0.14, wispy=0.4,
             region="chops")],
        "braids": [dict(at="chop", side=s, length=0.08, width=0.022, step=0.012, lean=(0.04 * s, -0.1, -1.0),
                        ties=(1.0,), beads=(0.5,)) for s in (1.0, -1.0)]},
    "Beard_braided_moustache": {"kind": "beard", "locks": False, "edge": dict(n=60), "layers": [
        dict(n=300, length=0.06, lo=0.003, hi=0.007, npts=4, power=1.0, width=0.018, curl=0.1, wispy=0.2,
             region="mustache")],
        "braids": [dict(at="corner", side=s, length=0.21, width=0.022, step=0.013, lean=(0.12 * s, -0.2, -1.0),
                        ties=(1.0,), beads=(0.4, 0.7), grow=True) for s in (1.0, -1.0)]},
})
# The bead anchors of M10's braided styles (P56): beads between their own two rings (at two fifths and at the tie).
OLD_BRAID_BEADS = {"Hair_long_braided": (0.2, 0.68), "Beard_braided": (0.2, 0.65)}
# The order the styles are grown in (one random stream, seed HAIR_SEED): the floor's four first, so the
# target's styles leave them as they were; the catalogue II's after them (P56), so every earlier style is as it was.
STYLE_ORDER = ("Hair_long_back", "Hair_crop", "Beard_full", "Beard_short",
               "Hair_long_braided", "Hair_warrior_tail", "Hair_wild_mane", "Beard_braided", "Beard_forked",
               "Hair_top_knot", "Hair_side_braids", "Hair_twin_braids", "Hair_long_loose", "Hair_circlet_braid",
               "Beard_chin_braid", "Beard_long_forked", "Beard_mutton_chops", "Beard_braided_moustache")
NEW_STYLES = STYLE_ORDER[9:]
# The bead sets (P56): their shape round a braid (bead_shapes), detail kind and colour; the index's "bead" meshes.
BEAD_SETS = {"Beads_bone": dict(shape="barrel", detail="bone", color="#d9ccb0"),
             "Beads_bronze": dict(shape="rings", detail="metal", color="#a8743c"),
             "Beads_silver": dict(shape="round", detail="metal", color="#c9ccd1"),
             # P61: the rival giants' braided-beard rings, broad and heavy, on the beards' braids only (their looks
             # only: the catalogue's npc option)
             "Beads_iron": dict(shape="band", detail="metal", color="#5d6166", styles="Beard_")}
BEAD_SIDES_SET = 6
HAIR_SEED = 11
COVER_SEED = 4041            # the fourth look lane: a style's "cover" locks (their own random stream)
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
# The fifth look lane: a card beard's edge - fine short strands in the band where its mask thins out (their own random
# stream), and its cards there narrower (beard_edge_share).
BEARD_EDGE = dict(n=150, length=0.04, lo=0.002, hi=0.005, npts=3, width=0.010, curl=0.05)
BEARD_EDGE_SEED = 5011
BEARD_EDGE_NARROW = 0.4      # a card's width where the beard's mask is 0 (its share; 1 where it is whole)


def beard_edge_share(surf, roots):
    """Per card the share of its width it keeps by the beard's mask at its root (BEARD_EDGE_NARROW at the edge)."""
    _, i = surf.kd.query(roots)
    m = np.clip(surf.attr["m_beard"][i], 0.0, 1.0)
    return BEARD_EDGE_NARROW + (1.0 - BEARD_EDGE_NARROW) * np.clip(m / 0.8, 0.0, 1.0) ** 0.8


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


def grow_scalp(surf, L, S, hs, rng, n, length, layer_lo, layer_hi, npts=10, power=0.6, wild=0.0, tuck=0.0,
               mask="m_scalp"):
    roots, nrm, mv, _ = surf.sample(mask, n, rng, power=power)
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


def grow_fringe(surf, L, S, hs, rng, n, length, layer_lo, layer_hi, npts=3, mask=None):
    """The hairline's fringe (the M10 gate, LC-6): ``n`` short guides rooted evenly along the front of the
    scalp's edge (forehead, temples, in front of the ears), lying back along the scalp's own flow over the
    roots of the style's cards. Candidates are drawn on the triangles the scalp mask's edge crosses and the
    roots are picked farthest-first among them, so the row has no gap (the bare notch above the temple).
    ``mask`` (P56): a narrower scalp (the side-shaved top's strip)."""
    m = np.clip(surf.attr["m_scalp"] if mask is None else mask, 0.0, 1.0)
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


def knot_point(surf, S, at="back"):
    """Where the warrior's tail is tied: high on the back of the head, a little off the scalp; ``at`` "crown" (P56):
    the top knot's, on the crown a little behind the top."""
    Vs, Ns, c, ztop, yback, _zmin = _scalp_frame(surf)
    if at == "crown":
        target = np.array([0.0, c[1] + 0.2 * (yback - c[1]), ztop])
    else:
        target = np.array([0.0, c[1] + 0.62 * (yback - c[1]), c[2] + 0.8 * (ztop - c[2])])
    i = int(np.argmin(np.linalg.norm(Vs - target, axis=1)))
    return Vs[i] + Ns[i] * 0.012 * S


def grow_knot(surf, L, S, hs, rng, n, length, layer_lo, layer_hi, npts=5, power=0.5, at="back", mask="m_scalp"):
    """The warrior's tail, on the head: every lock lies flat and runs to the knot."""
    roots, nrm, mv, _ = surf.sample(mask, n, rng, power=power)
    roots += nrm * 0.0004 * S
    knot = knot_point(surf, S, at)

    def flow(P, nn, s):
        return _unit(_tangent(knot - P, nn))

    dist = np.linalg.norm(roots - knot, axis=1)
    Lh = np.clip(dist * (0.75 + 0.35 * rng.random(n)), 0.04 * S, length * S)
    lift = 0.05 + 0.08 * rng.random(n)
    layer = (layer_lo + (layer_hi - layer_lo) * rng.random(n)) * hs * S
    P = grow(surf, roots, nrm, Lh, npts, flow, lift, 0.35, 1.0, 0.0, 0.001 * S, layer)
    return post_collide(surf, P, 0.001 * S)


def grow_tail(surf, L, S, hs, rng, n, length, layer_lo, layer_hi, npts=9, power=1.0, at="back"):
    """The warrior's tail, off the head: locks from the knot, out behind the head and down the back. ``at``
    "crown" (P56): the top knot's tuft, rising from the knot and falling over it all round."""
    knot = knot_point(surf, S, at)
    G = np.array([0.0, 0.0, -1.0])
    start = knot + rng.normal(size=(n, 3)) * 0.012 * S
    if at == "crown":
        d = _unit(np.array([0.0, 0.25, 1.0]) + rng.normal(size=(n, 3)) * 0.55)
        keep, fall = 0.7, 0.32
    else:
        d = _unit(np.array([0.0, 0.85, 0.35]) + rng.normal(size=(n, 3)) * 0.22)
        keep, fall = 0.62, 0.5
    Lh = length * S * (0.75 + 0.35 * rng.random(n))
    seg = (Lh / (npts - 1))[:, None]
    P = np.zeros((n, npts, 3))
    P[:, 0] = start
    for k in range(1, npts):
        d = _unit(d * keep + G * fall)
        P[:, k] = P[:, k - 1] + d * seg
    return post_collide(surf, P, 0.012 * S)


def grow_toward(surf, L, S, hs, rng, n, length, layer_lo, layer_hi, npts=6, power=0.5, targets=None,
                mask="m_scalp"):
    """Locks combed to where a braid leaves the head (P56: the twin braids, the side-shaved top): every lock lies
    flat on the scalp and runs to ``targets(roots)`` (n, 3), at most ``length`` long."""
    roots, nrm, mv, _ = surf.sample(mask, n, rng, power=power)
    roots += nrm * 0.0004 * S
    tgt = targets(roots)

    def flow(P, nn, s):
        return _unit(_tangent(tgt - P, nn) + np.array([0.0, 0.0, -0.15]))

    dist = np.linalg.norm(roots - tgt, axis=1)
    Lh = np.clip(dist * (0.85 + 0.3 * rng.random(n)), 0.04 * S, length * S)
    lift = 0.05 + 0.08 * rng.random(n)
    layer = (layer_lo + (layer_hi - layer_lo) * rng.random(n)) * hs * S
    P = grow(surf, roots, nrm, Lh, npts, flow, lift, 0.4, 1.0, 0.1, 0.001 * S, layer)
    return post_collide(surf, P, 0.001 * S)


def grow_beard(surf, L, S, hs, rng, n, length, layer_lo, layer_hi, npts=8, power=1.0, fork=0.0, mask="m_beard"):
    roots, nrm, mv, _ = surf.sample(mask, n, rng, power=power)
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


def braid_thin(i, K, closed=False):
    """A braid's narrowing towards its tie at ring ``i`` of ``K`` (a closed braid, the circlet, keeps its width)."""
    return 1.0 if closed else 1.0 - 0.45 * (i / (K - 1)) ** 2


def braid_tube(path, width, S, centre, ties=None, closed=False):
    """A braid as a twisted tube along ``path`` (K, 3) (P51): BRAID_SIDES round, its radius rippling with the
    three strands of a plait (BRAID_RELIEF) that turn BRAID_TWIST radians a ring, narrowing towards the tie, and
    a bead ring at its tie and one at two fifths. Returns V, F (quads), UV, normals and UV2 (1 the tube, 2 the
    beads); the tube's u runs round the atlas's dense column, its v from the root (1) to the tie (0). ``ties``
    (P56): the shares of its length where its rings sit (None: M10's two); ``closed``: a ring round the head
    (the circlet: no narrowing; its last ring meets its first under a tie)."""
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
        thin = braid_thin(i, K, closed)
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
    rings = (int(round(0.4 * (K - 1))), K - 2) if ties is None else \
        tuple(min(max(int(round(f * (K - 1))), 0), K - 2) for f in ties)
    for at in rings:
        base = len(Vs)
        x, y = frames[at]
        r = BEAD_RADIUS * w * (1.0 if ties is None else braid_thin(at, K, closed) * 1.3)
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
# Each style's fringe as vertex ranges (P56: the hairline strips; the face keys keep off the scalp, so they take none).
STRIP_RANGES = {}


def _toward_targets(surf, L, S, hs, style):
    """The point every lock of a "toward" layer runs to (P56): the root of the braid on its side (the twin braids),
    else the first braid's (the side-shaved head's back braid)."""
    braids = style["braids"]
    by_side = {b["side"]: braid_start(surf, L, S, hs, b["at"], b["side"]) for b in braids}
    if 1.0 in by_side and -1.0 in by_side and 0.0 not in by_side:
        return lambda R: np.where((R[:, 0] >= 0.0)[:, None], by_side[1.0][None, :], by_side[-1.0][None, :])
    first = braid_start(surf, L, S, hs, braids[0]["at"], braids[0]["side"])
    return lambda R: np.broadcast_to(first, R.shape).copy()


def braid_start(surf, L, S, hs, at, side):
    """Where a braid leaves the head: behind an ear ("ear") or under the chin ("chin")."""
    if at == "ear":
        Vs, Ns, c, _ztop, _yback, zmin = _scalp_frame(surf)
        target = np.array([side * (np.abs(Vs[:, 0]).max() + 0.01 * S), c[1] + 0.01 * S, c[2] - 0.45 * (c[2] - zmin)])
        i = int(np.argmin(np.linalg.norm(Vs - target, axis=1)))
        return Vs[i] + Ns[i] * 0.008 * S
    if at in ("crown", "back", "back_side", "temple", "nape_side"):
        # P56: the top knot's crown; the side-shaved head's back (its middle, and a little to either side); the
        # temple in front of the ear (the long loose hair's thin braids)
        Vs, Ns, c, ztop, yback, zmin = _scalp_frame(surf)
        half_x = np.abs(Vs[:, 0]).max()
        if at == "crown":
            return knot_point(surf, S, "crown") + np.array([0.0, 0.01 * S, 0.0])
        if at == "back":
            target = np.array([0.0, yback, c[2] + 0.15 * (ztop - c[2])])
        elif at == "nape_side":
            target = np.array([side * 0.85 * half_x, c[1] + 0.3 * (yback - c[1]), L["ear_z"][0] - 0.005 * hs * S])
        elif at == "back_side":
            target = np.array([side * 0.3 * half_x, yback, c[2] - 0.1 * (c[2] - zmin)])
        else:
            target = np.array([side * half_x, c[1] - 0.45 * (yback - c[1]), L["ear_z"][1] + 0.012 * hs * S])
        i = int(np.argmin(np.linalg.norm(Vs - target, axis=1)))
        return Vs[i] + Ns[i] * 0.012 * S
    if at in ("corner", "chop"):
        # P56: a corner of the mouth (the braided moustache), the lower end of a chop
        sel = surf.attr["m_beard"] > 0.3
        Vb, Nb = surf.V[sel], surf.N[sel]
        if at == "corner":
            target = np.array([side * 0.03 * hs * S, L["face_y"] + 0.022 * hs * S, L["lip_bot"] - 0.004 * hs * S])
        else:
            target = np.array([side * 0.058 * hs * S, L["face_y"] + 0.07 * hs * S, L["chin"] + 0.012 * hs * S])
        i = int(np.argmin(np.linalg.norm(Vb - target, axis=1)))
        return Vb[i] + Nb[i] * 0.008 * S
    sel = surf.attr["m_beard"] > 0.5
    Vb, Nb = surf.V[sel], surf.N[sel]
    target = np.array([side * 0.02 * hs * S, Vb[:, 1].min(), L["chin"] - 0.005 * hs * S])
    i = int(np.argmin(np.linalg.norm(Vb - target, axis=1)))
    return Vb[i] + Nb[i] * 0.01 * S


def braid_path(surf, S, start, lean, length, width, step, hang=False):
    """A braid's path (K, 3) from ``start`` (P56): along ``lean`` pushed off the body like braid_guides', or with
    ``hang`` grown step by step under gravity over the body's surface (a braid falling over the shoulder onto the
    chest), its middle kept a braid's radius and a little off the skin."""
    n_steps = max(4, int(round(length / step)))
    clear = 0.5 * width * S * (1.0 + BRAID_RELIEF) + 0.004 * S
    if not hang:
        d = _unit(np.asarray(lean, float))
        path = start[None, :] + d[None, :] * (np.arange(n_steps + 2)[:, None] * step * S)
        return post_collide(surf, path[None, :, :], max(0.014 * S, clear))[0]
    lean = _unit(np.asarray(lean, float))
    _, nrm = surf.nearest(start[None, :])

    def flow(P, nn, s):
        return np.broadcast_to(lean, P.shape)

    P = grow(surf, start[None, :], nrm, np.array([(n_steps + 1) * step * S]), n_steps + 2, flow,
             np.array([0.4]), 0.55, 1.0, 0.5, clear, clear)
    return post_collide(surf, P, clear)[0]


def circlet_path(surf, L, S, hs, width, step):
    """The circlet braid's ring round the head (P56): at the hairline in front, a little lower behind, standing a
    braid's radius off the hair's inner layer; closed (its last point is its first)."""
    Vs, Ns, c, ztop, yback, zmin = _scalp_frame(surf)
    # the second look lane: round the brow at the hairline and over the back of the skull (it went round the crown
    # 9.5 cm over the brow, level with the top of the hair: a halo standing on the head), resting on the hair's
    # inner layer rather than on the skin under it
    z_front = L["brow_z"] + 0.058 * hs * S
    z_back = z_front - 0.05 * hs * S
    clear = 0.5 * width * S * (1.0 + BRAID_RELIEF) + 0.009 * hs * S
    pts = []
    head = surf.V[np.clip(surf.attr["m_head"], 0, 1) > 0.5]
    n = 48
    for k in range(n):
        th = 2.0 * np.pi * k / n                      # 0 the face (-Y), round by the giant's left (+X)
        d = np.array([np.sin(th), -np.cos(th), 0.0])
        z = z_back + (z_front - z_back) * 0.5 * (1.0 + np.cos(th))
        band = head[np.abs(head[:, 2] - z) < 0.006 * S]
        # the W33 look lane: the farthest point of the slice in this direction's own sector (the farthest along the
        # direction over the whole slice was an ear's or the brow's, and the ring stood off the temples)
        rel = band[:, :2] - c[:2]
        ang = np.abs((np.arctan2(rel[:, 0], -rel[:, 1]) - th + np.pi) % (2.0 * np.pi) - np.pi)
        sector = ang < 0.16
        cand = band[sector] if sector.any() else band
        far = cand[int(np.argmax((cand[:, :2] - c[:2]) @ d[:2]))]
        # (behind, the hair is thicker over the skull: the ring stands a little further out there, or it sank into it)
        pts.append(np.array([far[0], far[1], z]) + d * (clear + 0.006 * hs * S * 0.5 * (1.0 - np.cos(th))))
    path = np.asarray(pts)
    # smooth the ring (the slice's farthest points step with the mesh)
    for _ in range(3):
        path = 0.5 * path + 0.25 * (np.roll(path, 1, axis=0) + np.roll(path, -1, axis=0))
    # resample at the braid's step
    seg = np.linalg.norm(np.diff(np.vstack([path, path[:1]]), axis=0), axis=1)
    total = seg.sum()
    m = max(8, int(round(total / (step * S))))
    s = np.concatenate([[0.0], np.cumsum(seg)])
    closed = np.vstack([path, path[:1]])
    out = np.stack([np.interp(np.linspace(0.0, total, m + 1), s, closed[:, a]) for a in range(3)], axis=1)
    return post_collide(surf, out[None, :, :], clear)[0]


def region_mask(surf, L, S, hs, region):
    """A narrower skin for a layer (P56): "strip" the top of a side-shaved head (the sides bare), "chops" the beard
    without the chin, "mustache" the upper lip."""
    V = surf.V
    if region == "strip":
        Vs = surf.V[surf.attr["m_scalp"] > 0.5]
        half_x = np.abs(Vs[:, 0]).max()
        return np.clip(surf.attr["m_scalp"], 0, 1) * (1.0 - sstep_np(np.abs(V[:, 0]), 0.3 * half_x, 0.42 * half_x))
    if region == "chops":
        chin = (1.0 - sstep_np(np.abs(V[:, 0]), 0.045 * hs * S, 0.065 * hs * S)) * \
            sstep_np(L["lip_bot"] - V[:, 2], -0.004 * hs * S, 0.006 * hs * S)
        throat = sstep_np(L["chin"] + 0.01 * hs * S - V[:, 2], 0.0, 0.01 * hs * S)
        return np.clip(surf.attr["m_beard"], 0, 1) * (1.0 - chin) * (1.0 - throat)
    if region == "mustache":
        return np.clip(surf.attr["m_mustache"], 0, 1)
    raise ValueError("unknown region %s" % region)


def sstep_np(x, a, b):
    t = np.clip((np.asarray(x, np.float64) - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def tine_point(tips, side, hs, S):
    """Where the long forked beard's tine on ``side`` gathers (P56): the mean of the lowest tips (n, 3) on that side."""
    sel = tips[:, 0] * side > 0.02 * hs * S
    t = tips[sel]
    lo = t[t[:, 2] <= np.quantile(t[:, 2], 0.2)]
    return lo.mean(axis=0) + np.array([0.0, 0.0, 0.012 * S])


def anchors_on(path, width, S, fractions, closed=False):
    """The bead anchors of a braid (P56): at each share of its length, (point, tangent, radius the bead wraps)."""
    K = len(path)
    seg = np.linalg.norm(np.diff(path, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)]) / max(seg.sum(), 1e-9)
    T = np.gradient(path, axis=0)
    T /= np.linalg.norm(T, axis=1, keepdims=True) + 1e-12
    out = []
    for f in fractions:
        i = int(np.clip(np.searchsorted(s, f), 1, K - 1))
        a = (f - s[i - 1]) / max(s[i] - s[i - 1], 1e-9)
        p = path[i - 1] * (1.0 - a) + path[i] * a
        t = _unit(T[i - 1] * (1.0 - a) + T[i] * a)
        thin = braid_thin((i - 1) + a, K, closed)
        out.append((p, t, 0.5 * width * S * thin * (1.0 + BRAID_RELIEF)))
    return out


def bead_shape(shape, p, t, r, ref):
    """One bead round a braid (P56): V (n, 3), F (quads), N, UV for the bead set's ``shape``: "barrel" a long bone
    bead, "rings" two flat rings, "round" a round bead; ``r`` the radius it wraps, ``ref`` a direction across."""
    x = _unit(ref - t * float(ref @ t))
    y = np.cross(t, x)
    if shape == "barrel":
        prof = [(-0.7, 1.02), (-0.5, 1.16), (0.5, 1.16), (0.7, 1.02)]
    elif shape == "rings":
        prof = [(-0.55, 1.04), (-0.45, 1.2), (-0.25, 1.2), (-0.15, 1.04), (0.15, 1.04), (0.25, 1.2), (0.45, 1.2),
                (0.55, 1.04)]
    elif shape == "band":
        prof = [(-0.70, 1.04), (-0.58, 1.38), (0.58, 1.38), (0.70, 1.04)]
    else:
        prof = [(-0.5, 1.02), (-0.34, 1.26), (0.0, 1.38), (0.34, 1.26), (0.5, 1.02)]
    n = BEAD_SIDES_SET
    V, N, UV, F = [], [], [], []
    for k, (a, rad) in enumerate(prof):
        for j in range(n + 1):
            ang = 2.0 * np.pi * j / n
            d = np.cos(ang) * x + np.sin(ang) * y
            V.append(p + t * a * r * 1.2 + d * rad * r)
            nb = prof[min(k + 1, len(prof) - 1)][1] - prof[max(k - 1, 0)][1]
            N.append(_unit(d - t * nb * 0.8))
            UV.append((j / n, k / (len(prof) - 1)))
    for k in range(len(prof) - 1):
        if shape == "rings" and k == 3:
            continue                                   # the gap between the two rings
        for j in range(n):
            a = k * (n + 1) + j
            F.append((a, a + n + 1, a + n + 2, a + 1))
    return np.asarray(V), np.asarray(F), np.asarray(N), np.asarray(UV)


# The bead anchors of every style that takes beads (P56), set by build_styles: mesh id -> [(point, tangent, radius)]
# in Blender's frame at stage 1; the export builds the bead sets on them.
BEAD_ANCHORS = {}


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
    # the body's proportions (2026-11-20): the cards and the braids grow with the head (their widths and lengths are
    # human metres; the head was scaled by PROPORTIONS["head"], so at stage 1 they were 6 % smaller while the head grew)
    f = gb.PROPORTIONS["head"]
    surf = Surface(body, 0, ("m_scalp", "m_beard", "m_head", "m_mustache"))
    rng = np.random.default_rng(HAIR_SEED)
    wh = np.clip(surf.attr["m_head"], 0, 1)
    centre = (surf.V * wh[:, None]).sum(axis=0) / wh.sum()
    out = {}
    for mesh_id in STYLE_ORDER:
        style = STYLES[mesh_id]
        Vs, Fs, UVs, Ns = [], [], [], []
        off = 0
        cards = 0
        grown = []      # P56: the layers' guides (the long forked beard's tines gather from them)
        strips = []     # P56: the fringe's vertex range (the hairline strips that take the face keys)
        for ly in style["layers"]:
            grower = grow_scalp if style["kind"] == "scalp" else grow_beard
            extra = {k: ly[k] for k in ("wild", "fork", "tuck") if k in ly}
            if ly.get("grow") == "knot":
                grower = grow_knot
            elif ly.get("grow") == "tail":
                grower = grow_tail
            elif ly.get("grow") == "toward":
                # P56: the locks run to the braids' roots (each side's own, or the back's on a side-shaved head)
                grower = grow_toward
                extra["targets"] = _toward_targets(surf, L, S, hs, style)
            if "at" in ly:
                extra["at"] = ly["at"]
            if "region" in ly:
                extra["mask"] = region_mask(surf, L, S, hs, ly["region"])
            P = grower(surf, L, S, hs, rng, ly["n"], ly["length"] * f, ly["lo"], ly["hi"], npts=ly["npts"],
                       power=ly["power"], **extra)
            n = len(P)
            grown.append(P)
            width = ly["width"] * S * f * (0.8 + 0.4 * rng.random(n))
            if ly["wispy"] > 0:
                cols = np.where(rng.random(n) < ly["wispy"], 3, rng.integers(0, 3, n))
            else:
                cols = rng.integers(0, 3, n)
            taper = SCALP_TAPER
            if style["kind"] == "beard" and style.get("locks", True):
                along = np.linalg.norm(np.diff(P, axis=1), axis=2).sum(axis=1)
                width = np.minimum(width, BEARD_ASPECT * along)
                taper = BEARD_TAPER
            if style["kind"] == "beard" and mesh_id not in SHELLS and ly.get("region") != "mustache":
                # the fifth look lane: narrower where the beard thins out (the cheek's edge was a row of full-width
                # cards: a staircase of blocks from the side)
                width = width * beard_edge_share(surf, P[:, 0])
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
            fmask = region_mask(surf, L, S, hs, fr["region"]) if "region" in fr else None
            P = grow_fringe(surf, L, S, hs, frng, fr["n"], fr["length"] * f, fr["lo"], fr["hi"], npts=fr["npts"],
                            mask=fmask)
            strips.append((off, off + len(P) * fr["npts"] * 2))
            n = len(P)
            width = fr["width"] * S * f * (0.8 + 0.4 * frng.random(n))
            cols = np.where(frng.random(n) < fr["wispy"], 3, frng.integers(0, 3, n))
            V, F, UV, Nn = ribbons(surf, P, width, cols, np.full(n, fr["curl"]), centre, taper=0.7)
            Vs.append(V)
            Fs.append(F + off)
            UVs.append(UV)
            Ns.append(Nn)
            off += len(V)
            cards += n
        if "cover" in style:
            # the fourth look lane: a few short locks combed straight back over the top of the head, from a random
            # stream of their own (the twin braids' locks run apart to each side and left a ragged scalp patch)
            cv = style["cover"]
            crng = np.random.default_rng([COVER_SEED, STYLE_ORDER.index(mesh_id)])
            P = grow_scalp(surf, L, S, hs, crng, cv["n"], cv["length"] * f, cv["lo"], cv["hi"], npts=cv["npts"], power=0.6,
                           mask=region_mask(surf, L, S, hs, cv.get("region", "strip"))
                           * sstep_np(surf.V[:, 2], L["ear_z"][1] + 0.01 * hs * S, L["ear_z"][1] + 0.04 * hs * S))
            n = len(P)
            width = cv["width"] * S * f * (0.8 + 0.4 * crng.random(n))
            V, F, UV, Nn = ribbons(surf, P, width, crng.integers(0, 3, n), np.full(n, cv["curl"]), centre,
                                   taper=SCALP_TAPER)
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
            P = grow_scalp(surf, L, S, hs, lrng, lo["n"], lo["length"] * f, lo["lo"], lo["hi"], npts=lo["npts"],
                           power=0.6, wild=lo["wild"])
            # only strands that hang back or down over the style: none falls forward over the face
            back = ((P[:, -1, 1] - P[:, 0, 1] > -0.005 * S) & (P[:, 1:, 2] < P[:, :1, 2] + 0.004 * S).all(axis=1)
                    & (P[:, 0, 1] > centre[1] - 0.02 * S))
            P = P[back]
            n = len(P)
            width = lo["width"] * S * f * (0.7 + 0.6 * lrng.random(n))
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
            P = grow_under_jaw(surf, L, S, hs, urng, uj["n"], uj["length"] * f, uj["lo"], uj["hi"], npts=uj["npts"])
            n = len(P)
            along = np.linalg.norm(np.diff(P, axis=1), axis=2).sum(axis=1)
            width = np.minimum(uj["width"] * S * f * (0.8 + 0.4 * urng.random(n)), BEARD_ASPECT * along)
            V, F, UV, Nn = ribbons(surf, P, width, urng.integers(0, 3, n), np.full(n, uj["curl"]), centre,
                                   taper=BEARD_TAPER)
            Vs.append(V)
            Fs.append(F + off)
            UVs.append(UV)
            Ns.append(Nn)
            off += len(V)
            cards += n
        if style["kind"] == "beard" and mesh_id not in SHELLS:
            # the fifth look lane: fine short strands along the beard's edge, sparser toward the skin, from a random
            # stream of their own, so the cheek fades from the beard to stray hairs to bare skin
            ed = dict(BEARD_EDGE, **style.get("edge", {}))
            erng = np.random.default_rng([BEARD_EDGE_SEED, STYLE_ORDER.index(mesh_id)])
            m = np.clip(surf.attr["m_beard"], 0.0, 1.0)
            band = np.clip(4.0 * m * (1.0 - m), 0.0, 1.0) * (surf.V[:, 2] > L["chin"])
            reg = style["layers"][0].get("region")
            if reg is not None:
                # (only round the style's own skin: no stray hairs on a bare chin or cheek)
                rm = np.clip(region_mask(surf, L, S, hs, reg), 0.0, 1.0)
                band = band * np.clip(rm * 3.0, 0.0, 1.0)
            P = grow_beard(surf, L, S, hs, erng, ed["n"], ed["length"] * f, ed["lo"], ed["hi"], npts=ed["npts"],
                           power=1.0, mask=band)
            n = len(P)
            along = np.linalg.norm(np.diff(P, axis=1), axis=2).sum(axis=1)
            width = np.minimum(ed["width"] * S * f * (0.6 + 0.8 * erng.random(n)), BEARD_ASPECT * along)
            V, F, UV, Nn = ribbons(surf, P, width, np.full(n, 3), np.full(n, ed["curl"]), centre, taper=BEARD_TAPER)
            Vs.append(V)
            Fs.append(F + off)
            UVs.append(UV)
            Ns.append(Nn)
            off += len(V)
            cards += n
        card_verts = off
        U2s = []
        anchors = []
        for br in style.get("braids", ()):
            # P51: a twisted tube with beads along the braid's path (it was herringbone cards)
            if mesh_id not in NEW_STYLES:
                start = braid_start(surf, L, S, hs, br["at"], br["side"])
                _lobes, _facing, core = braid_guides(surf, S, start, br["lean"], br["length"] * f, br["width"] * f, br["step"] * f)
                path, ties, closed = core[0], None, False
            elif br["at"] == "circlet":
                path, ties, closed = circlet_path(surf, L, S, hs, br["width"] * f, br["step"] * f), br["ties"], True
            else:
                start = tine_point(np.concatenate([g[:, -1] for g in grown]), br["side"], hs, S) if br["at"] == "tine" else \
                    braid_start(surf, L, S, hs, br["at"], br["side"])
                path = braid_path(surf, S, start, br["lean"], br["length"] * f, br["width"] * f, br["step"] * f,
                                  hang=br.get("grow", False))
                ties, closed = br["ties"], False
            V, F, UV, Nn, u2 = braid_tube(path, br["width"] * f, S, centre, ties=ties, closed=closed)
            # P56: the bead sets' anchors on this braid (M10's braided styles: between their own rings)
            beads = br.get("beads", OLD_BRAID_BEADS.get(mesh_id, ()))
            anchors += anchors_on(path, br["width"] * f, S, beads, closed)
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
        STRIP_RANGES[mesh_id] = strips
        if anchors:
            BEAD_ANCHORS[mesh_id] = anchors
        mat = "giant_hair" if style["kind"] == "scalp" else "giant_beard"
        ob = card_object(mesh_id, V_all, np.concatenate(Fs), np.concatenate(UVs),
                         np.concatenate(Ns), coll, rig, mat, UV2)
        out[mesh_id] = (ob, cards)
        log(f"{mesh_id}: {cards} cards, {len(ob.data.polygons) * 2} triangles")
    return out

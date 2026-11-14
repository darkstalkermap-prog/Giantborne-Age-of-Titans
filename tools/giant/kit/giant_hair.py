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
(the research crop was patchy), and the styles are named by the giant index's mesh ids.
"""
from __future__ import annotations

import bpy
import numpy as np

ATLAS_COLUMNS = 4

# The floor's styles (plan §2.3): mesh id -> layers (count, length m human scale, layer lo, hi,
# guide points, sampling power, card width m, curl, wispy-column share of the outer layer).
STYLES = {
    "Hair_long_back": {"kind": "scalp", "layers": [
        dict(n=170, length=0.17, lo=0.006, hi=0.012, npts=10, power=0.6, width=0.06, curl=0.12, wispy=0.0),
        dict(n=140, length=0.21, lo=0.014, hi=0.024, npts=10, power=0.6, width=0.045, curl=0.2, wispy=0.3)]},
    "Hair_crop": {"kind": "scalp", "layers": [
        dict(n=400, length=0.05, lo=0.005, hi=0.009, npts=5, power=0.4, width=0.04, curl=0.05, wispy=0.0)]},
    "Beard_full": {"kind": "beard", "layers": [
        dict(n=140, length=0.13, lo=0.004, hi=0.008, npts=8, power=1.0, width=0.04, curl=0.1, wispy=0.0),
        dict(n=100, length=0.16, lo=0.009, hi=0.016, npts=8, power=1.0, width=0.032, curl=0.15, wispy=0.3)]},
    "Beard_short": {"kind": "beard", "layers": [
        dict(n=160, length=0.04, lo=0.003, hi=0.006, npts=5, power=1.0, width=0.03, curl=0.05, wispy=0.0)]},
}
# The order the styles are grown in (one random stream, seed HAIR_SEED).
STYLE_ORDER = ("Hair_long_back", "Hair_crop", "Beard_full", "Beard_short")
HAIR_SEED = 11


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


def grow_scalp(surf, L, S, hs, rng, n, length, layer_lo, layer_hi, npts=10, power=0.6):
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
    P = grow(surf, roots, nrm, Lh, npts, flow, lift, 0.55, 0.9, 0.55, 0.0015 * S, layer)
    return post_collide(surf, P, 0.0015 * S)


def grow_beard(surf, L, S, hs, rng, n, length, layer_lo, layer_hi, npts=8, power=1.0):
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

    def flow(P, nn, s):
        down = np.array([0.0, -0.18, -1.0])
        lateral = np.concatenate([side * 0.55, np.zeros((len(P), 1)), np.zeros((len(P), 1))], axis=1)
        v = np.where(must[:, None], down + lateral + nn * 0.3, down + nn * (0.35 * (1 - s)))
        return _unit(v)

    lift = np.where(must, 0.5, 0.4) + 0.3 * rng.random(n)
    layer = (layer_lo + (layer_hi - layer_lo) * rng.random(n)) * hs * S
    P = grow(surf, roots, nrm, Lb, npts, flow, lift, 0.5, 0.7, 0.9, 0.001 * S, layer)
    return post_collide(surf, P, 0.0012 * S)


# --------------------------------------------------------------------------------------
# cards
# --------------------------------------------------------------------------------------
def ribbons(surf, P, widths, col_idx, curl):
    """Guides P (N, K, 3) -> card vertices, faces (quads), uvs, normals."""
    N, K, _ = P.shape
    T = np.gradient(P, axis=1)
    T /= np.linalg.norm(T, axis=2, keepdims=True) + 1e-12
    _, nrm = surf.nearest(P.reshape(-1, 3))
    nrm = nrm.reshape(N, K, 3)
    side = np.cross(nrm, T)
    side /= np.linalg.norm(side, axis=2, keepdims=True) + 1e-12
    s = np.linspace(0, 1, K)[None, :, None]
    w = widths[:, None, None] * (1.0 - 0.55 * s ** 1.4)
    c = curl[:, None, None] * w
    Lft = P - side * w * 0.5 - nrm * c
    Rgt = P + side * w * 0.5 - nrm * c
    V = np.stack([Lft, Rgt], axis=2).reshape(N, K * 2, 3)            # per card: l0 r0 l1 r1 ...
    Nn = np.stack([nrm, nrm], axis=2).reshape(N, K * 2, 3)
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


def card_object(name, V, F, UV, Nn, coll, rig, mat_name):
    import giant_body as gb
    me = bpy.data.meshes.new(name)
    me.from_pydata(V.tolist(), [], F.tolist())
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    lv = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", lv)
    uvl.data.foreach_set("uv", UV[lv].astype(np.float32).ravel())
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
    out = {}
    for mesh_id in STYLE_ORDER:
        style = STYLES[mesh_id]
        Vs, Fs, UVs, Ns = [], [], [], []
        off = 0
        cards = 0
        for ly in style["layers"]:
            grower = grow_scalp if style["kind"] == "scalp" else grow_beard
            P = grower(surf, L, S, hs, rng, ly["n"], ly["length"], ly["lo"], ly["hi"], npts=ly["npts"],
                       power=ly["power"])
            n = len(P)
            width = ly["width"] * S * (0.8 + 0.4 * rng.random(n))
            if ly["wispy"] > 0:
                cols = np.where(rng.random(n) < ly["wispy"], 3, rng.integers(0, 3, n))
            else:
                cols = rng.integers(0, 3, n)
            V, F, UV, Nn = ribbons(surf, P, width, cols, np.full(n, ly["curl"]))
            Vs.append(V)
            Fs.append(F + off)
            UVs.append(UV)
            Ns.append(Nn)
            off += len(V)
            cards += n
        mat = "giant_hair" if style["kind"] == "scalp" else "giant_beard"
        ob = card_object(mesh_id, np.concatenate(Vs), np.concatenate(Fs), np.concatenate(UVs),
                         np.concatenate(Ns), coll, rig, mat)
        out[mesh_id] = (ob, cards)
        log(f"{mesh_id}: {cards} cards, {len(ob.data.polygons) * 2} triangles")
    return out

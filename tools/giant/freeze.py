"""The freeze of the giant's body (plan M11 §2.2, P48 design 1): what must stay bit-identical to
0.10.0-m10 when the pipeline grows - the three body meshes' positions, normals, UVs, region ids and
skin weights, the 53 game_engine bones' names, parents and rests, and the tracks of M10's nine clips.

``body_freeze(giant.glb)`` and ``clip_freeze(giant_clips.glb)`` reduce a glTF binary to hashes that do
not depend on what else the file holds (other meshes, more bones, the joints' order, the vertices'
order, the other colour channels); ``tools/giant/fixtures/m10_freeze.json`` holds them as read once
from the files committed at the 0.10.0-m10 release, and test_giant_tools.py compares every
regeneration with it.

  python freeze.py --write <giant.glb> <giant_clips.glb> <out.json>     (only by an orchestrator's decision: M10's
                                                                          files, then the proportioned body's,
                                                                          2026-11-20, docs/DECISIONS.md)
"""
from __future__ import annotations

import hashlib
import json
import struct
import sys

import numpy as np

BODY_MESHES = ("Body_Head", "Body_Torso", "Body_Limbs")
M10_CLIPS = ("idle", "walk", "run", "airborne", "death", "grip_r", "grip_l", "open_r", "open_l")
HAND_CLIPS = ("grip_r", "grip_l", "open_r", "open_l")
COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    with open(path, "rb") as fh:
        data = fh.read()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2, "not a glTF 2 binary"
    pos, doc, binary = 12, None, b""
    while pos < length:
        clen, ctype = struct.unpack_from("<I4s", data, pos)
        chunk = data[pos + 8: pos + 8 + clen]
        if ctype == b"JSON":
            doc = json.loads(chunk.decode("utf-8"))
        elif ctype == b"BIN\x00":
            binary = chunk
        pos += 8 + clen
    return doc, binary


def raw_accessor(doc, binary, i):
    """An accessor's values as stored (no normalisation), shape (count, width)."""
    acc = doc["accessors"][i]
    bv = doc["bufferViews"][acc["bufferView"]]
    dt = np.dtype(COMPONENT[acc["componentType"]])
    width = WIDTH[acc["type"]]
    start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    size = dt.itemsize * width
    stride = bv.get("byteStride", 0) or size
    count = acc["count"]
    raw = np.frombuffer(binary, np.uint8, count=stride * (count - 1) + size, offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, shape=(count, size), strides=(stride, 1))
    return np.frombuffer(rows.copy().tobytes(), dt).reshape(count, width)


def _sha(*arrays) -> str:
    h = hashlib.sha256()
    for a in arrays:
        h.update(np.ascontiguousarray(a).tobytes())
    return h.hexdigest()


def _sorted_rows(a):
    a = np.ascontiguousarray(a)
    return a[np.lexsort(a.T[::-1])]


def skeleton_freeze(doc, binary, bones=None) -> dict:
    """{bone: [parent, sha256 of its node's translation, rotation and scale and its inverse bind matrix]}
    of the skin's joints (all of them, or the names in ``bones``)."""
    skin = doc["skins"][0]
    nodes = doc["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    ibm = raw_accessor(doc, binary, skin["inverseBindMatrices"])
    out = {}
    for k, j in enumerate(skin["joints"]):
        n = nodes[j]
        if bones is not None and n["name"] not in bones:
            continue
        p = parent.get(j)
        pname = nodes[p]["name"] if p is not None and p in skin["joints"] else ""
        trs = np.asarray(n.get("translation", [0, 0, 0]) + n.get("rotation", [0, 0, 0, 1]) + n.get("scale", [1, 1, 1]),
                         np.float32)
        out[n["name"]] = [pname, _sha(trs, ibm[k])]
    return out


def body_freeze(path, bones=None) -> dict:
    """The frozen facts of a giant.glb: per body mesh the hashes of its vertex data (as sets: neither the
    vertices' nor the joints' order matters) and of its triangles, and the skeleton's bones."""
    doc, binary = read_glb(path)
    skin = doc["skins"][0]
    joint_names = [doc["nodes"][j]["name"] for j in skin["joints"]]
    names = sorted(bones if bones is not None else joint_names)
    rank = {n: i for i, n in enumerate(names)}
    out = {"bones": skeleton_freeze(doc, binary, set(names)), "meshes": {}}
    for node in doc["nodes"]:
        if node.get("name") not in BODY_MESHES:
            continue
        prims = doc["meshes"][node["mesh"]]["primitives"]
        assert len(prims) == 1, "%s: one surface" % node["name"]
        at = prims[0]["attributes"]
        P = raw_accessor(doc, binary, at["POSITION"])
        N = raw_accessor(doc, binary, at["NORMAL"])
        UV = raw_accessor(doc, binary, at["TEXCOORD_0"])
        C = raw_accessor(doc, binary, at["COLOR_0"]).astype(np.float64)
        C = C / float(np.iinfo(COMPONENT[doc["accessors"][at["COLOR_0"]]["componentType"]]).max)
        region = np.floor(C[:, 0] * 16.0).astype(np.float32).reshape(-1, 1)
        J = raw_accessor(doc, binary, at["JOINTS_0"]).astype(np.int64)
        W = raw_accessor(doc, binary, at["WEIGHTS_0"]).astype(np.float32)
        stray = sorted({joint_names[j] for j in np.unique(J[W > 0]) if joint_names[j] not in rank})
        assert not stray, "%s is weighted to bones outside the frozen skeleton: %s" % (node["name"], stray)
        R = np.vectorize(lambda j: rank.get(joint_names[j], -1))(J).astype(np.float32)
        R[W <= 0] = -1.0
        order = np.argsort(R, axis=1, kind="stable")
        R = np.take_along_axis(R, order, axis=1)
        Wn = np.take_along_axis(W, order, axis=1)
        rows = np.concatenate([P, N, UV, region, R, Wn], axis=1).astype(np.float32)
        uniq, inverse = np.unique(rows, axis=0, return_inverse=True)
        T = inverse.reshape(-1)[raw_accessor(doc, binary, prims[0]["indices"]).astype(np.int64).reshape(-1, 3)]
        T = np.stack([np.roll(t, -int(np.argmin(t))) for t in T]) if len(T) else T
        out["meshes"][node["name"]] = {
            "vertices": int(len(P)), "triangles": int(len(T)),
            "positions": _sha(_sorted_rows(P)), "normals": _sha(_sorted_rows(np.concatenate([P, N], axis=1))),
            "uvs": _sha(_sorted_rows(np.concatenate([P, UV], axis=1))),
            "regions": _sha(_sorted_rows(np.concatenate([P, region], axis=1))),
            "weights": _sha(_sorted_rows(np.concatenate([P, R, Wn], axis=1))),
            "all": _sha(uniq), "faces": _sha(_sorted_rows(T.astype(np.int64)))}
    return out


def clip_freeze(path, clips=None) -> dict:
    """{clip: {bone: a hash of its tracks (path, interpolation, key times and values, in path order)}} of a
    clip library's animations."""
    doc, binary = read_glb(path)
    out = {}
    for a in doc.get("animations", []):
        if clips is not None and a["name"] not in clips:
            continue
        per_bone = {}
        for ch in a["channels"]:
            s = a["samplers"][ch["sampler"]]
            per_bone.setdefault(doc["nodes"][ch["target"]["node"]]["name"], []).append(
                (ch["target"]["path"], s["interpolation"], raw_accessor(doc, binary, s["input"]),
                 raw_accessor(doc, binary, s["output"])))
        tracks = {}
        for bone, chans in per_bone.items():
            h = hashlib.sha256()
            for path_name, interp, times, values in sorted(chans, key=lambda c: c[0]):
                h.update(("%s|%s|" % (path_name, interp)).encode())
                h.update(np.ascontiguousarray(times).tobytes())
                h.update(np.ascontiguousarray(values).tobytes())
            tracks[bone] = h.hexdigest()[:24]
        out[a["name"]] = tracks
    return out


def main(argv) -> int:
    if len(argv) == 4 and argv[0] == "--write":
        doc = {"source": "assets/giant/giant.glb and giant_clips.glb as committed at the 0.10.0-m10 release (5ff50f0)",
               "body": body_freeze(argv[1]), "clips": clip_freeze(argv[2], M10_CLIPS)}
        with open(argv[3], "w", encoding="utf-8") as fh:
            fh.write(json.dumps(doc, sort_keys=True, indent=1) + "\n")
        print("wrote %s: %d bones, %d meshes, %d clips" % (argv[3], len(doc["body"]["bones"]), len(doc["body"]["meshes"]),
                                                           len(doc["clips"])))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

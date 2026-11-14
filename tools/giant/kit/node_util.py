"""A small helper to write Blender shader node trees in Python (the bake's procedural skin).

Ported from the M10 research run's frozen kit snapshot (class NB). The snapshot's builder of
MPFB2's JSON node trees is not ported: the pipeline bakes the kit's own skin and never builds
MPFB's skin or eye graphs.
"""
from __future__ import annotations

import bpy


def _is_socket(x):
    return isinstance(x, bpy.types.NodeSocket)


class NB:
    """Terse node-tree writer. Inputs may be numbers/tuples or output sockets."""

    def __init__(self, nt):
        self.nt = nt
        self._n = 0

    def new(self, type_, label=None, **props):
        n = self.nt.nodes.new(type_)
        for k, v in props.items():
            setattr(n, k, v)
        if label:
            n.label = label
        self._n += 1
        n.location = (-200 * (self._n % 12), -160 * (self._n // 12))
        return n

    @staticmethod
    def sock(node, key, out=False):
        coll = node.outputs if out else node.inputs
        if isinstance(key, int):
            return coll[key]
        cands = [s for s in coll if s.name == key or s.identifier == key]
        for s in cands:
            if s.enabled:
                return s
        if cands:
            return cands[0]
        raise KeyError(f"{node.bl_idname} has no {'output' if out else 'input'} {key!r}")

    def put(self, sock, value):
        if value is None:
            return
        if _is_socket(value):
            self.nt.links.new(value, sock)
        else:
            try:
                sock.default_value = value
            except TypeError:
                if isinstance(value, (int, float)):
                    sock.default_value = (value, value, value, 1.0)[: len(sock.default_value)]
                elif len(value) == 3 and len(sock.default_value) == 4:
                    sock.default_value = (*value, 1.0)
                else:
                    raise

    def link(self, a, b):
        self.nt.links.new(a, b)

    # -- math -------------------------------------------------------------------------
    def math(self, op, a, b=None, c=None, clamp=False):
        n = self.new("ShaderNodeMath", operation=op, use_clamp=clamp)
        self.put(n.inputs[0], a)
        if b is not None:
            self.put(n.inputs[1], b)
        if c is not None:
            self.put(n.inputs[2], c)
        return n.outputs[0]

    def add(self, a, b, clamp=False):
        return self.math("ADD", a, b, clamp=clamp)

    def mul(self, a, b, clamp=False):
        return self.math("MULTIPLY", a, b, clamp=clamp)

    def sub(self, a, b, clamp=False):
        return self.math("SUBTRACT", a, b, clamp=clamp)

    def madd(self, a, b, c, clamp=False):
        return self.math("MULTIPLY_ADD", a, b, c, clamp=clamp)

    def vmath(self, op, a, b=None, scale=None):
        n = self.new("ShaderNodeVectorMath", operation=op)
        self.put(n.inputs[0], a)
        if b is not None:
            self.put(n.inputs[1], b)
        if scale is not None:
            self.put(self.sock(n, "Scale"), scale)
        if op in ("DOT_PRODUCT", "LENGTH", "DISTANCE"):
            return self.sock(n, "Value", out=True)
        return self.sock(n, "Vector", out=True)

    def maprange(self, x, a, b, c=0.0, d=1.0, interp="LINEAR", clamp=True):
        n = self.new("ShaderNodeMapRange", interpolation_type=interp, clamp=clamp)
        self.put(n.inputs["Value"], x)
        self.put(n.inputs["From Min"], a)
        self.put(n.inputs["From Max"], b)
        self.put(n.inputs["To Min"], c)
        self.put(n.inputs["To Max"], d)
        return n.outputs["Result"]

    def smooth(self, x, a, b):
        return self.maprange(x, a, b, 0.0, 1.0, "SMOOTHSTEP")

    def mixf(self, fac, a, b):
        n = self.new("ShaderNodeMix", data_type="FLOAT", clamp_factor=True)
        self.put(n.inputs[0], fac)
        self.put(n.inputs[2], a)
        self.put(n.inputs[3], b)
        return n.outputs[0]

    def mixc(self, fac, a, b, blend="MIX", clamp_result=False):
        n = self.new("ShaderNodeMix", data_type="RGBA", blend_type=blend, clamp_factor=True,
                     clamp_result=clamp_result)
        self.put(n.inputs[0], fac)
        self.put(n.inputs[6], a)
        self.put(n.inputs[7], b)
        return n.outputs[2]

    def rgb(self, r, g, b):
        n = self.new("ShaderNodeRGB")
        n.outputs[0].default_value = (r, g, b, 1.0)
        return n.outputs[0]

    def value(self, v, label=None):
        n = self.new("ShaderNodeValue", label=label)
        n.outputs[0].default_value = v
        return n.outputs[0]

    def combine(self, x, y, z):
        n = self.new("ShaderNodeCombineXYZ")
        self.put(n.inputs[0], x)
        self.put(n.inputs[1], y)
        self.put(n.inputs[2], z)
        return n.outputs[0]

    def separate(self, v):
        n = self.new("ShaderNodeSeparateXYZ")
        self.put(n.inputs[0], v)
        return n.outputs

    def bw(self, c):
        n = self.new("ShaderNodeRGBToBW")
        self.put(n.inputs[0], c)
        return n.outputs[0]

    # -- inputs ---------------------------------------------------------------------------
    def attr(self, name, out="Fac"):
        n = self.new("ShaderNodeAttribute", attribute_name=name)
        return n.outputs[out]

    def texcoord(self, out="UV"):
        return self.new("ShaderNodeTexCoord").outputs[out]

    def image(self, path, vector=None, colorspace="Non-Color", interp="Linear"):
        img = bpy.data.images.load(path, check_existing=True)
        img.colorspace_settings.name = colorspace
        n = self.new("ShaderNodeTexImage", interpolation=interp)
        n.image = img
        if vector is not None:
            self.put(n.inputs["Vector"], vector)
        return n

    # -- textures -------------------------------------------------------------------------
    def noise(self, vec, scale, detail=2.0, rough=0.5, distortion=0.0, ntype="FBM", dims="3D",
              out="Fac", lacunarity=2.0, normalize=True):
        n = self.new("ShaderNodeTexNoise", noise_dimensions=dims, noise_type=ntype, normalize=normalize)
        self.put(n.inputs["Vector"], vec)
        self.put(n.inputs["Scale"], scale)
        self.put(n.inputs["Detail"], detail)
        self.put(n.inputs["Roughness"], rough)
        self.put(n.inputs["Distortion"], distortion)
        self.put(n.inputs["Lacunarity"], lacunarity)
        return n.outputs[out]

    def voronoi(self, vec, scale, feature="F1", randomness=1.0, distance="EUCLIDEAN", detail=0.0):
        n = self.new("ShaderNodeTexVoronoi", feature=feature, distance=distance, voronoi_dimensions="3D")
        self.put(n.inputs["Vector"], vec)
        self.put(n.inputs["Scale"], scale)
        self.put(n.inputs["Randomness"], randomness)
        self.put(n.inputs["Detail"], detail)
        return n

    def ridged(self, vec, scale, width, detail=1.0, distortion=0.0, rough=0.5):
        """Thin meandering lines: 1 where a noise field crosses 0.5, 0 elsewhere."""
        n = self.noise(vec, scale, detail=detail, distortion=distortion, rough=rough)
        d = self.math("ABSOLUTE", self.sub(n, 0.5))
        return self.maprange(d, 0.0, width, 1.0, 0.0, "SMOOTHSTEP")

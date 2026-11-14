extends TestSuite
## P41 (plan M10 §2.5, §3.1 tests): the design array survives the GPU's texture compression. Every
## layer of assets/giant/designs.png (the committed source, 512 x 512 RGBA layers stacked vertically)
## goes through Godot's own S3TC compressor (Image.compress, DXT5: R, G and B share one colour block per
## 4 x 4 texels, A has its own) and back. The packing rule (a region's texels carry at most one design in
## R, G and B plus one in A) keeps the designs apart; this is the feasibility review's compressor probe
## as a test, per design (plan §2.5; W25 review T5: a channel holds up to four designs, and a mean over
## the channel let a small design's error vanish beside a large one):
##   * each design keeps a mean error of at most 0.05 over its own texels;
##   * no other design shows through: over a design's texels, every other channel of the layer that is
##     dark there stays dark (mean at most 0.05).
## A design's texels are the lit texels of its channel in its own body regions (the packing rule keeps the
## designs of one channel in different regions): the region of each texel comes from the body meshes of
## assets/giant/giant.glb, rasterized in UV space with their vertices' region ids, as the bake's own
## region map is made. Headless; a second or two (the raster and four layers).

const DESIGNS := "res://assets/giant/designs.png"
const MANIFEST := "res://assets/giant/manifest.json"
const LAYER := 512
const MAX_ERROR := 0.05
const MAX_GHOST := 0.05
const LIT := 0.5
const MODEL := "res://assets/giant/giant.glb"
const BODY := ["Body_Head", "Body_Torso", "Body_Limbs"]
const NO_REGION := 255
## A lit texel no body triangle covers takes the region of the nearest covered texel within this many
## texels: the bake extends its islands by 8 texels at 1024 px (tools/giant/kit/bake.py, "margin"), 4 at
## 512, and the downscale smears one more.
const FILL_TEXELS := 5
## At most this share of a channel's lit texels may fall in no region of its designs.
const MAX_STRAY := 0.02
## A design's attributed texels are within this share (and 2 texels) of the count --designs recorded in the
## manifest (designs.designs[*].texels_512): the region map stands for the bake's.
const ATTRIBUTION_SLACK := 0.05


## The body region of every texel of a LAYER x LAYER layer (NO_REGION outside the islands): the body
## meshes' triangles rasterized at the texel centres in UV space, the region the floor of 16 x the
## interpolated COLOR.r ((id + 0.5) / 16 at each vertex; how the bake's regions.png is made).
static func region_map() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(LAYER * LAYER)
	out.fill(NO_REGION)
	var scene := (load(MODEL) as PackedScene).instantiate()
	for mesh_name: String in BODY:
		var mi := scene.find_child(mesh_name, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if uv.is_empty() or col.size() != uv.size():
				continue
			if idx.is_empty():
				idx.resize(uv.size())
				for i in uv.size():
					idx[i] = i
			for t in range(0, idx.size() - 2, 3):
				_raster(out, uv[idx[t]] * LAYER, uv[idx[t + 1]] * LAYER, uv[idx[t + 2]] * LAYER,
					col[idx[t]].r, col[idx[t + 1]].r, col[idx[t + 2]].r)
	scene.free()
	return out


static func _raster(out: PackedByteArray, a: Vector2, b: Vector2, c: Vector2, ra: float, rb: float, rc: float) -> void:
	var area := (b - a).cross(c - a)
	if absf(area) < 1e-9:
		return
	var x0 := maxi(int(floor(minf(a.x, minf(b.x, c.x)) - 0.5)), 0)
	var x1 := mini(int(ceil(maxf(a.x, maxf(b.x, c.x)) - 0.5)), LAYER - 1)
	var y0 := maxi(int(floor(minf(a.y, minf(b.y, c.y)) - 0.5)), 0)
	var y1 := mini(int(ceil(maxf(a.y, maxf(b.y, c.y)) - 0.5)), LAYER - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var wa := (c - b).cross(p - b) / area
			var wb := (a - c).cross(p - c) / area
			var wc := 1.0 - wa - wb
			if wa < -1e-6 or wb < -1e-6 or wc < -1e-6:
				continue
			out[y * LAYER + x] = clampi(int((wa * ra + wb * rb + wc * rc) * 16.0), 0, 15)


## The region of texel `i` of the map, or of the nearest covered texel within FILL_TEXELS.
static func region_at(map: PackedByteArray, i: int) -> int:
	if map[i] != NO_REGION:
		return map[i]
	var x := i % LAYER
	var y := i / LAYER
	for r in range(1, FILL_TEXELS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r or x + dx < 0 or x + dx >= LAYER or y + dy < 0 or y + dy >= LAYER:
					continue
				var v := map[(y + dy) * LAYER + x + dx]
				if v != NO_REGION:
					return v
	return NO_REGION


func test_every_layer_survives_s3tc_with_no_design_showing_through() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(DESIGNS))
	assert_true(src != null and not src.is_empty(), "designs.png loads")
	if src == null or src.is_empty():
		return
	src.convert(Image.FORMAT_RGBA8)
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var designs: Dictionary = (doc as Dictionary).index.designs
	var texels: Dictionary = (doc as Dictionary).get("designs", {}).get("designs", {})   # the bake's per-design counts
	var layers := src.get_height() / LAYER
	assert_eq(layers, int((doc as Dictionary).index.textures.design_layers), "the manifest's layer count")
	var regions := region_map()
	assert_true(regions.count(NO_REGION) < regions.size(), "the body's region map is drawn")
	var checked := 0
	var worst := 0.0
	for li in layers:
		var layer := src.get_region(Rect2i(0, li * LAYER, LAYER, LAYER))
		var packed := layer.duplicate() as Image
		assert_eq(packed.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_GENERIC), OK, "layer %d compresses" % li)
		assert_eq(packed.get_format(), Image.FORMAT_DXT5, "layer %d as DXT5" % li)
		packed.decompress()
		packed.convert(Image.FORMAT_RGBA8)
		var a := layer.get_data()
		var b := packed.get_data()
		for c in 4:
			var names: Array[String] = []
			for d: String in designs:
				if int(designs[d].layer) == li and int(designs[d].channel) == c:
					names.append(d)
			if names.is_empty():
				continue
			var owner := {}   # body region -> the design of this channel drawn there
			for d in names:
				for r: Variant in designs[d].regions:
					assert_false(owner.has(int(r)), "layer %d channel %d: %s and %s share region %d" % [li, c,
						owner.get(int(r), ""), d, int(r)])
					owner[int(r)] = d
			var err := {}
			var lit := {}
			var ghost := {}     # design -> {other channel: [sum, count]}
			var stray := 0
			var total := 0
			for i in range(c, a.size(), 4):
				if a[i] < 255 * LIT:
					continue
				total += 1
				var px := i - c
				var d := str(owner.get(region_at(regions, px / 4), ""))
				if d == "":
					stray += 1
					continue
				lit[d] = int(lit.get(d, 0)) + 1
				err[d] = float(err.get(d, 0.0)) + absf(a[i] - b[i]) / 255.0
				var g: Dictionary = ghost.get(d, {})
				for o in 4:
					if o == c or a[px + o] > 8:
						continue
					var acc: Array = g.get(o, [0.0, 0])
					g[o] = [float(acc[0]) + b[px + o] / 255.0, int(acc[1]) + 1]
				ghost[d] = g
			assert_true(float(stray) <= MAX_STRAY * maxi(total, 1), "layer %d channel %d: %d of %d lit texels in no region of %s" % [
				li, c, stray, total, ", ".join(names)])
			for d in names:
				var n := int(lit.get(d, 0))
				assert_true(n > 0, "layer %d channel %d draws %s" % [li, c, d])
				if n == 0:
					continue
				var want := int(texels.get(d, {}).get("texels_512", n))
				assert_true(absi(n - want) <= 2 + int(ATTRIBUTION_SLACK * want), "%s: %d texels attributed, the bake counted %d" % [
					d, n, want])
				var mean := float(err[d]) / n
				assert_true(mean <= MAX_ERROR, "%s (layer %d channel %d): mean error %.3f over its %d texels" % [
					d, li, c, mean, n])
				worst = maxf(worst, mean)
				for o: int in ghost.get(d, {}):
					var acc: Array = ghost[d][o]
					assert_true(float(acc[0]) / int(acc[1]) <= MAX_GHOST, "layer %d: channel %d does not show through %s (mean %.3f)" % [
						li, o, d, float(acc[0]) / int(acc[1])])
				checked += 1
	assert_eq(checked, designs.size(), "every design was checked")
	print("    test_design_array: %d designs, the largest mean error %.4f" % [checked, worst])

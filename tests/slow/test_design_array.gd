extends TestSuite
## P41 (plan M10 §2.5, §3.1 tests): the design array survives the GPU's texture compression. Every
## layer of assets/giant/designs.png (the committed source, 512 x 512 RGBA layers stacked vertically)
## goes through Godot's own S3TC compressor (Image.compress, DXT5: R, G and B share one colour block per
## 4 x 4 texels, A has its own) and back. The packing rule (a region's texels carry at most one design in
## R, G and B plus one in A) keeps the designs apart; this is the feasibility review's compressor probe
## as a test:
##   * each channel's designs keep a mean error of at most 0.05 over their own texels;
##   * no other design shows through: over a channel's texels, every other channel of the layer that is
##     dark there stays dark (mean at most 0.05).
## Headless; about a second (four layers).

const DESIGNS := "res://assets/giant/designs.png"
const MANIFEST := "res://assets/giant/manifest.json"
const LAYER := 512
const MAX_ERROR := 0.05
const MAX_GHOST := 0.05
const LIT := 0.5


func test_every_layer_survives_s3tc_with_no_design_showing_through() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(DESIGNS))
	assert_true(src != null and not src.is_empty(), "designs.png loads")
	if src == null or src.is_empty():
		return
	src.convert(Image.FORMAT_RGBA8)
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var designs: Dictionary = (doc as Dictionary).index.designs
	var layers := src.get_height() / LAYER
	assert_eq(layers, int((doc as Dictionary).index.textures.design_layers), "the manifest's layer count")
	var checked := 0
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
			var err := 0.0
			var lit := 0
			var ghost := {}
			var ghost_n := {}
			for i in range(c, a.size(), 4):
				if a[i] < 255 * LIT:
					continue
				lit += 1
				err += absf(a[i] - b[i]) / 255.0
				var px := i - c
				for o in 4:
					if o == c or a[px + o] > 8:
						continue
					ghost[o] = float(ghost.get(o, 0.0)) + b[px + o] / 255.0
					ghost_n[o] = int(ghost_n.get(o, 0)) + 1
			assert_true(lit > 0, "layer %d channel %d draws %s" % [li, c, str(names)])
			if lit == 0:
				continue
			assert_true(err / lit <= MAX_ERROR, "layer %d channel %d (%s): mean error %.3f over %d texels" % [
				li, c, ", ".join(names), err / lit, lit])
			for o: int in ghost:
				var mean := float(ghost[o]) / int(ghost_n[o])
				assert_true(mean <= MAX_GHOST, "layer %d: channel %d does not show through %s (mean %.3f)" % [
					li, o, ", ".join(names), mean])
			checked += names.size()
	assert_eq(checked, designs.size(), "every design was checked")

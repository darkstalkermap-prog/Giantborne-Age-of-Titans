class_name ThumbnailCache
extends Node
## The creator II's option thumbnails (P55; plan M11 §2.7, §3.8 item 3): 96 x 96 pictures of the options an option
## grid shows, made at run time and kept for the screen's life. Nothing is shipped for them.
##
##   * A garment, an accessory, an outfit, a hair or beard style, beads: drawn by a second, unshown GiantPreview
##     (`thumbnail`: still, its viewport UPDATE_ONCE, 96 x 96, the studio light) in the item's framing, then read
##     back into an ImageTexture after the frame that drew it.
##   * A design (a tattoo, a war paint): a flat picture of its own layer and channel of the giant's design array -
##     the design's ink over the skin tone, cropped to where the design is - instead of a render.
##
## The Web's rule, kept everywhere: at most one thumbnail is made a frame (THUMBS_PER_FRAME), and only for the page
## the grid shows: request() replaces the queue with the visible page's items, so a page turned past is never
## drawn. Items are cached by their key (the option id, the skin tone and the dyes or colour it is drawn in:
## CreatorScreen.thumb_item()); a cached item is handed back at once (`thumbnail_ready`) without a frame's work.
## The unshown preview is made on the first request, never when the creator opens (its first frame stays as it was).
##
## Without a display nothing is drawn: the look is still put on the preview and a blank texture stands for the
## frame, one a frame, so the scheduling is the same headless (tests). reset_for_tests() (ResetHooks.AFTER_EACH,
## pre-declared by P53) frees every live cache's preview and textures.

## A thumbnail is made for an item: its option id and the texture.
signal thumbnail_ready(id: String, texture: Texture2D)

const SIZE := 96
## The Web's rule (plan M11 §2.7): never more than this many thumbnails a frame.
const THUMBS_PER_FRAME := 1
## The skin around a design's flat picture, and how much of the layer around the design's ink is kept.
const DESIGN_MARGIN := 0.12
## A design's ink counts where its channel is above this (the crop).
const DESIGN_INK := 0.2
## The resolution the flat pictures are cut from (the array's layers are halved down to it).
const DESIGN_SOURCE_PX := 256
## The copy the ink's box is found on.
const BOX_PX := 64
const BACKDROP := Color(0.12, 0.13, 0.16)

## Every live cache (reset_for_tests frees what they hold).
static var _live: Array = []

## The textures made so far: item key -> Texture2D.
var textures: Dictionary = {}
## The items still to make (the visible page's, in page order).
var queue: Array = []
## Counters for the tests and the probe: the thumbnails made (rendered and flat), the most made in one frame, the
## frame numbers (Engine.get_process_frames) each was started in, and the ids made in order.
var made := 0
var rendered := 0
var flat := 0
var most_in_a_frame := 0
var made_frames: Array = []
var made_ids: Array = []
## The milliseconds each thumbnail's own work took in its frame (the look and framing, or the flat picture; the
## read-back of a rendered one is added in the next frame).
var work_ms: Array = []
var preview: GiantPreview = null
## The last design picture's parts (ms): reading its layer (the first of a layer: the array's read-back and
## decompression), the rest.
var design_timings := {}
var _pending: Dictionary = {}   ## the item drawn this frame, read back in the next
var _drawn := false
var _frame_count := {}          ## frame -> thumbnails started in it
var _layers: Dictionary = {}    ## design array layer -> Image (decompressed, DESIGN_SOURCE_PX), or null
var _designs_texture: Variant = null


func _init() -> void:
	name = "ThumbnailCache"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_live.append(weakref(self))


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_drawn):
		RenderingServer.frame_post_draw.disconnect(_on_drawn)


## The visible page's items (CreatorScreen.thumb_item: {"id", "key", "kind": "render" | "design", "look",
## "framing"} or {"id", "key", "kind": "design", "design", "color", "skin"}): the cached ones are handed back at
## once, the rest replace whatever was still queued (a page turned past is never drawn).
func request(items: Array) -> void:
	queue.clear()
	for item: Dictionary in items:
		var key := str(item.get("key", ""))
		if key == "":
			continue
		if textures.has(key):
			thumbnail_ready.emit(str(item.id), textures[key])
		elif str(_pending.get("key", "")) != key:
			queue.append(item)


## The texture of an item key (null when not made yet).
func cached(key: String) -> Texture2D:
	return textures.get(key)


## True while something is queued or being drawn.
func busy() -> bool:
	return not queue.is_empty() or not _pending.is_empty()


## Forgets every texture and the queue (the screen's life is over, or a test's).
func clear() -> void:
	queue.clear()
	_pending = {}
	textures.clear()
	_layers.clear()


## Frees what every live cache holds (ResetHooks.AFTER_EACH): the unshown previews, the textures, the queues.
## Returns how many caches still held something (not reported as a failure: a screen closed by the stack frees
## its own cache in the same frame).
static func reset_for_tests() -> int:
	var n := 0
	for w: WeakRef in _live:
		var c := w.get_ref() as ThumbnailCache
		if c == null:
			continue
		if not c.textures.is_empty() or c.preview != null:
			n += 1
		c.clear()
		if c.preview != null and is_instance_valid(c.preview):
			c.preview.queue_free()
		c.preview = null
	_live = _live.filter(func(w: WeakRef) -> bool: return w.get_ref() != null)
	return n


func _process(_delta: float) -> void:
	_harvest()
	if queue.is_empty() or not _pending.is_empty():
		return
	var frame := Engine.get_process_frames()
	if int(_frame_count.get(frame, 0)) >= THUMBS_PER_FRAME:
		return
	var item: Dictionary = queue.pop_front()
	var t0 := Time.get_ticks_usec()
	_frame_count = {frame: int(_frame_count.get(frame, 0)) + 1}
	most_in_a_frame = maxi(most_in_a_frame, int(_frame_count[frame]))
	made_frames.append(frame)
	made_ids.append(str(item.id))
	if str(item.get("kind", "")) == "design":
		var tex := design_picture(item)
		flat += 1
		_store(item, tex)
	else:
		_start_render(item)
	work_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)


## Puts the item's look on the unshown preview and asks for one frame; it is read back in the next _process.
func _start_render(item: Dictionary) -> void:
	_ensure_preview()
	preview.apply_look(item.get("look", {}) as Dictionary)
	preview.frame(str(item.get("framing", "full")))
	preview.render_thumbnail()
	_pending = item
	_drawn = DisplayServer.get_name() == "headless"   # nothing draws: the next frame stands for it
	if not _drawn and not RenderingServer.frame_post_draw.is_connected(_on_drawn):
		RenderingServer.frame_post_draw.connect(_on_drawn, CONNECT_ONE_SHOT)


func _on_drawn() -> void:
	_drawn = true


## The drawn frame of the pending item, read back into a texture of its own.
func _harvest() -> void:
	if _pending.is_empty() or not _drawn:
		return
	var item := _pending
	_pending = {}
	var img: Image = null
	if DisplayServer.get_name() != "headless" and preview != null:
		var t0 := Time.get_ticks_usec()
		img = preview.viewport.get_texture().get_image()
		if not work_ms.is_empty():
			work_ms[work_ms.size() - 1] = float(work_ms[-1]) + float(Time.get_ticks_usec() - t0) / 1000.0
		preview.stop_thumbnail()
	if img == null or img.is_empty():
		img = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		img.fill(BACKDROP)
	rendered += 1
	_store(item, ImageTexture.create_from_image(img))


func _store(item: Dictionary, tex: Texture2D) -> void:
	made += 1
	if tex != null:
		textures[str(item.key)] = tex
	thumbnail_ready.emit(str(item.id), tex)


## The unshown preview: made on the first thumbnail, kept for the screen's life.
func _ensure_preview() -> void:
	if preview != null and is_instance_valid(preview):
		return
	preview = GiantPreview.new()
	preview.name = "ThumbnailPreview"
	preview.thumbnail = true
	preview.still = true
	preview.stretch = false
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.size = Vector2(SIZE, SIZE)
	preview.position = Vector2(-4 * SIZE, -4 * SIZE)   # never on screen: only its viewport's frames are read
	preview.viewport.size = Vector2i(SIZE, SIZE)
	preview.viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(preview)
	preview.stop_thumbnail()


# --------------------------------------------------------------------------- the designs' flat pictures

## A design's flat picture (plan M11 §2.7): the ink of the design's channel of its layer in the giant's design
## array over the skin tone, cropped to the ink's box, SIZE x SIZE. null when the array cannot be read (no display:
## the layers live on the GPU) - the cell then shows the option's name.
func design_picture(item: Dictionary) -> Texture2D:
	var d: Dictionary = item.get("design", {}) if typeof(item.get("design")) == TYPE_DICTIONARY else {}
	var t0 := Time.get_ticks_usec()
	var layer := _layer_image(int(d.get("layer", -1)))
	design_timings["layer_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	if layer == null:
		return null
	var channel := clampi(int(d.get("channel", 0)), 0, 3)
	# the ink's box, found on a BOX_PX copy (cheap), then cut from the layer
	var small: Image = _layers.get("small:%d" % int(d.layer))
	var sw := small.get_width()
	var box := Rect2i()
	var found := false
	for y in small.get_height():
		for x in sw:
			if small.get_pixel(x, y)[channel] > DESIGN_INK:
				box = Rect2i(x, y, 1, 1) if not found else box.merge(Rect2i(x, y, 1, 1))
				found = true
	if not found:
		return null
	var k := float(layer.get_width()) / float(sw)
	var side := int(ceil(maxf(box.size.x, box.size.y) * k * (1.0 + 2.0 * DESIGN_MARGIN))) + 2
	side = mini(side, mini(layer.get_width(), layer.get_height()))
	var centre := Vector2(box.get_center()) * k
	var x0 := clampi(int(centre.x) - side / 2, 0, layer.get_width() - side)
	var y0 := clampi(int(centre.y) - side / 2, 0, layer.get_height() - side)
	var cut := layer.get_region(Rect2i(x0, y0, side, side))
	cut.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	var skin: Color = item.get("skin", Color(0.69, 0.53, 0.44))
	var ink: Color = item.get("color", Color(0.1, 0.18, 0.4))
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			out.set_pixel(x, y, skin.lerp(ink, clampf(cut.get_pixel(x, y)[channel], 0.0, 1.0)))
	return ImageTexture.create_from_image(out)


## A layer of the design array, decompressed and halved down to DESIGN_SOURCE_PX (cached); null without one.
func _layer_image(layer: int) -> Image:
	if layer < 0:
		return null
	if _layers.has(layer):
		return _layers[layer]
	var img: Image = null
	if _designs_texture == null:
		_designs_texture = load(GiantLook.DESIGN_ARRAY) if ResourceLoader.exists(GiantLook.DESIGN_ARRAY) else false
	var tex := _designs_texture as TextureLayered
	if tex != null and layer < tex.get_layers():
		var t0 := Time.get_ticks_usec()
		img = tex.get_layer_data(layer)
		design_timings["read_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
		if img != null and not img.is_empty():
			design_timings["format"] = img.get_format()
			design_timings["size"] = [img.get_width(), img.get_height(), img.has_mipmaps()]
			img = img.duplicate() as Image
			t0 = Time.get_ticks_usec()
			if img.is_compressed() and img.decompress() != OK:
				img = null
			design_timings["decompress_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
			if img != null:
				img.clear_mipmaps()
				if img.get_format() != Image.FORMAT_RGBA8:
					img.convert(Image.FORMAT_RGBA8)
				var k := maxi(1, img.get_width() / DESIGN_SOURCE_PX)
				if k > 1:
					img.resize(img.get_width() / k, img.get_height() / k, Image.INTERPOLATE_BILINEAR)
				var small := img.duplicate() as Image
				small.resize(BOX_PX, BOX_PX, Image.INTERPOLATE_BILINEAR)
				_layers["small:%d" % layer] = small
		else:
			img = null
	_layers[layer] = img
	return img

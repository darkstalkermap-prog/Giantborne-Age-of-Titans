class_name ThumbnailCache
extends Node
## The creator II's option thumbnails (P55; plan M11 §2.7, §3.8 item 3): 96 x 96 pictures of the options an option
## grid shows, made at run time and kept for the screen's life. Nothing is shipped for them.
##
##   * A garment, an accessory, an outfit, a hair or beard style, beads: drawn by a second, unshown GiantPreview
##     (`thumbnail`: still, its viewport UPDATE_ONCE, 96 x 96, the studio light) in the item's framing, then read
##     back into an ImageTexture after the frame that drew it.
##   * A design (a tattoo, a war paint): drawn the same way, alone on the giant at its region's framing (P57: P55's
##     flat picture of its layer and channel showed the other designs sharing the channel and every island of the UV
##     map, cropped to all its ink).
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

## The smallest picture (P55's size); P57: a picture is made at the cell's own pixel size (set_cell_pixels), from SIZE
## to MAX_SIZE in steps of SIZE_STEP, so a cell at 1920x1080 (about 210 px) is not a 96 px picture stretched.
const SIZE := 96
const MAX_SIZE := 256
const SIZE_STEP := 32
## P57: the time a frame may spend loading the parts of the next picture (natively a part takes about 1 ms).
const PART_BUDGET_MS := 4.0
## The Web's rule (plan M11 §2.7): never more than this many thumbnails a frame.
const THUMBS_PER_FRAME := 1
const BACKDROP := Color(0.12, 0.13, 0.16)

## P57 (plan M11 §2.7: "if P57 measures a thumbnail above the stall rule there, garment grids on the Web show names
## with the live preview only"): measured in creator_check.mjs on the Web build (SwiftShader), a picture's read-back
## of its frame took 0.7-3.9 s (the renderer's whole queue waited for; the part loads 1-11 ms), so on the Web no
## picture is made: every grid shows the options' names and the live preview puts each on as the focus moves. The
## command line's --creator-pictures=on|off overrides it either way (to try a GPU's browser; tests).
static func pictures_wanted() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--creator-pictures=on":
			return true
		if arg == "--creator-pictures=off":
			return false
	return not OS.has_feature("web")

## Every live cache (reset_for_tests frees what they hold).
static var _live: Array = []

## The textures made so far: item key -> Texture2D.
var textures: Dictionary = {}
## The items still to make (the visible page's, in page order).
var queue: Array = []
## Counters for the tests and the probe: the thumbnails made (all rendered since P57), the most made in one frame, the
## frame numbers (Engine.get_process_frames) each was started in, and the ids made in order.
var made := 0
var rendered := 0
var most_in_a_frame := 0
var made_frames: Array = []
var made_ids: Array = []
## The milliseconds each thumbnail's own work took in its frame (the look and framing; the read-back is added in the
## next frame).
var work_ms: Array = []
## P57: the read-backs' milliseconds, and the parts loaded ahead of a picture (one a frame) with their milliseconds.
var readback_ms: Array = []
var parts_loaded := 0
var parts_ms: Array = []
var preview: GiantPreview = null
## False on the Web (pictures_wanted()): request() makes nothing and the grid shows the names.
var enabled := true
## The pictures' side in pixels now (set_cell_pixels); part of every item's key.
var size := SIZE
var _pending: Dictionary = {}   ## the item drawn this frame, read back in the next
var _drawn := false
var _frame_count := {}          ## frame -> thumbnails started in it
var _held: Dictionary = {}      ## part path -> its mesh, held from its load until the picture that needs it is made


func _init() -> void:
	name = "ThumbnailCache"
	enabled = pictures_wanted()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_live.append(weakref(self))


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_drawn):
		RenderingServer.frame_post_draw.disconnect(_on_drawn)


## The visible page's items (CreatorScreen.thumb_item: {"id", "key", "kind": "render", "look", "framing", "aim"}):
## the cached ones are handed back at
## once, the rest replace whatever was still queued (a page turned past is never drawn).
func request(items: Array) -> void:
	queue.clear()
	if not enabled:
		return
	for item: Dictionary in items:
		if str(item.get("key", "")) == "":
			continue
		var key := key_of(item)
		if textures.has(key):
			thumbnail_ready.emit(str(item.id), textures[key])
		elif str(_pending.get("sized_key", "")) != key:
			var sized := item.duplicate()
			sized["sized_key"] = key
			queue.append(sized)


## P57: the cells' side in window pixels: the pictures are made at that size (rounded up to SIZE_STEP, SIZE to
## MAX_SIZE). Pictures made at another size stay cached under their own key.
func set_cell_pixels(px: float) -> void:
	var want := clampi(int(ceil(px / SIZE_STEP)) * SIZE_STEP, SIZE, MAX_SIZE)
	if want == size:
		return
	size = want
	if preview != null and is_instance_valid(preview) and _pending.is_empty():
		_fit_preview()


## An item's key at the size the pictures are made at now.
func key_of(item: Dictionary) -> String:
	return "%s@%d" % [str(item.get("key", "")), size]


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
	_held.clear()
	textures.clear()


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
	# P57: the parts the next picture shows are loaded ahead, for at most PART_BUDGET_MS a frame (a picture of an
	# outfit loads up to ten), and its picture is made once they are all in hand
	var t_frame := Time.get_ticks_usec()
	while true:
		var t_part := Time.get_ticks_usec()
		if not _load_a_part(queue[0] as Dictionary):
			break
		parts_loaded += 1
		parts_ms.append(float(Time.get_ticks_usec() - t_part) / 1000.0)
		if float(Time.get_ticks_usec() - t_frame) / 1000.0 >= PART_BUDGET_MS:
			return   # the rest next frame
	var item: Dictionary = queue.pop_front()
	var t0 := Time.get_ticks_usec()
	_frame_count = {frame: int(_frame_count.get(frame, 0)) + 1}
	most_in_a_frame = maxi(most_in_a_frame, int(_frame_count[frame]))
	made_frames.append(frame)
	made_ids.append(str(item.id))
	_start_render(item)
	work_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)


## P57: loads one part the item's look shows that is not loaded yet (held until its picture is made); false when
## every part it shows is in hand.
func _load_a_part(item: Dictionary) -> bool:
	_ensure_preview()
	var index: Dictionary = preview.model.index
	var meshes: Dictionary = index.get("meshes", {}) if typeof(index.get("meshes")) == TYPE_DICTIONARY else {}
	var look: Dictionary = item.get("look", {})
	var ids: Array = GiantLook.garment_meshes(index, GiantLook.complete(look)).keys()
	for k: String in ["hair_mesh", "beard_mesh", "hair_beads", "beard_beads"]:
		ids.append(str(look.get(k, "")))
	ids.append_array(look.get("accessories", []) as Array)
	for id: Variant in ids:
		var e: Variant = meshes.get(str(id))
		if typeof(e) != TYPE_DICTIONARY or not (e as Dictionary).has(GiantModel.PART_PATH):
			continue
		var path := str((e as Dictionary)[GiantModel.PART_PATH])
		if _held.has(path) or preview.model.is_part_loaded(str(id)):
			continue
		var res := GiantModel.load_part(path)
		_held[path] = res.get("mesh")
		return true
	return false


## Puts the item's look on the unshown preview and asks for one frame; it is read back in the next _process.
func _start_render(item: Dictionary) -> void:
	_ensure_preview()
	if Vector2i(preview.viewport.size) != Vector2i(size, size):
		_fit_preview()
	preview.apply_look(item.get("look", {}) as Dictionary)
	var framing := str(item.get("framing", "full"))
	if framing == GiantPreview.AIM:
		preview.frame_on(preview.aim_box(item.get("aim", []) as Array))   # P57: at the piece itself (the belt's trophies)
	else:
		preview.frame(framing)
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
		var read := float(Time.get_ticks_usec() - t0) / 1000.0
		readback_ms.append(read)
		if not work_ms.is_empty():
			work_ms[work_ms.size() - 1] = float(work_ms[-1]) + read
		preview.stop_thumbnail()
	if img == null or img.is_empty():
		img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(BACKDROP)
	rendered += 1
	_held.clear()   # the preview holds the parts it shows; the rest go back to GiantModel's recent list as they will
	_store(item, ImageTexture.create_from_image(img))


func _store(item: Dictionary, tex: Texture2D) -> void:
	made += 1
	if tex != null:
		textures[str(item.get("sized_key", item.key))] = tex
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
	preview.viewport.msaa_3d = Viewport.MSAA_DISABLED
	_fit_preview()
	add_child(preview)
	preview.stop_thumbnail()


## The unshown preview at the pictures' size, off the screen.
func _fit_preview() -> void:
	preview.size = Vector2(size, size)
	preview.position = Vector2(-4 * MAX_SIZE, -4 * MAX_SIZE)   # never on screen: only its viewport's frames are read
	preview.viewport.size = Vector2i(size, size)

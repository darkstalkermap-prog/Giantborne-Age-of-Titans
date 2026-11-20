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
## The Web's rule (plan M11 §2.7): never more than this many thumbnails a frame.
const THUMBS_PER_FRAME := 1
const BACKDROP := Color(0.12, 0.13, 0.16)

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
var preview: GiantPreview = null
## The pictures' side in pixels now (set_cell_pixels); part of every item's key.
var size := SIZE
var _pending: Dictionary = {}   ## the item drawn this frame, read back in the next
var _drawn := false
var _frame_count := {}          ## frame -> thumbnails started in it


func _init() -> void:
	name = "ThumbnailCache"
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
	var item: Dictionary = queue.pop_front()
	var t0 := Time.get_ticks_usec()
	_frame_count = {frame: int(_frame_count.get(frame, 0)) + 1}
	most_in_a_frame = maxi(most_in_a_frame, int(_frame_count[frame]))
	made_frames.append(frame)
	made_ids.append(str(item.id))
	_start_render(item)
	work_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)


## Puts the item's look on the unshown preview and asks for one frame; it is read back in the next _process.
func _start_render(item: Dictionary) -> void:
	_ensure_preview()
	if Vector2i(preview.viewport.size) != Vector2i(size, size):
		_fit_preview()
	preview.apply_look(item.get("look", {}) as Dictionary)
	var framing := str(item.get("framing", "full"))
	if framing == GiantPreview.AIM:
		preview.frame_on(aim_box(item.get("aim", []) as Array))   # P57: at the piece itself (the belt's trophies)
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
		if not work_ms.is_empty():
			work_ms[work_ms.size() - 1] = float(work_ms[-1]) + float(Time.get_ticks_usec() - t0) / 1000.0
		preview.stop_thumbnail()
	if img == null or img.is_empty():
		img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(BACKDROP)
	rendered += 1
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


## P57: the box (the model's frame) of the shown meshes among `ids` (index mesh ids), from their meshes' own boxes;
## the whole giant's when none shows.
func aim_box(ids: Array) -> AABB:
	var box := AABB()
	var any := false
	for id: Variant in ids:
		if str(id) == "":
			continue
		var mi := GiantLook.mesh_node(preview.model, preview.model.index, str(id))
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var b := preview.model.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if not any else box.merge(b)
		any = true
	return box if any else AABB(Vector3(-0.5, 0.0, -0.4), Vector3(1.0, 3.8, 0.8))

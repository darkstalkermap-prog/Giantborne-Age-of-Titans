class_name CreatureSlots
extends RefCounted
## The skinned slots of plan M11 §2.10's "others" (P64): at most MAX_SKINNED brutes and wolves are drawn skinned and
## animated at once (BruteRig, SkinnedWolfRig); the rest show their creature's far mesh, unanimated, until a slot is
## free. Decided for every such rig at once every FRAMES frames, by whichever rig processes first: the bosses always
## (they never leave the skinned level), then the striking, the staggered, the falling and the held, then the nearest
## the camera; a rig that holds a slot keeps it against a newcomer up to KEEP_SHARE nearer (no flicker at the line).
## The cavalry's horses keep their own throttle (SkinnedQuadrupedRig.MAX_SKINNED_OTHERS). `--others-cap=N` (tests,
## benches) lowers the cap. Presentation only: the rigs read their actors, nothing here is read by the simulation.
##
## A rig in the list answers slot_wanted() (it is drawn skinned and not dormant), slot_priority(camera position) (the
## lower the earlier; bosses and the acting below 0) and set_slot(on).

const MAX_SKINNED := 8
const FRAMES := 2
const KEEP_SHARE := 0.85
## Priorities below these are a boss's and an acting rig's (their distance is added).
const BOSS := -2000000.0
const ACTING := -1000000.0

static var _rigs: Array = []
static var _frame := -1
static var _cap := -1
## The run's numbers (PEOPLE_STATS' "others"): frames posed skinned, the most at once, rigs that waited for a slot.
static var totals := {"skinned_frames": 0, "skinned_max": 0, "waited": 0, "far_frames": 0}


static func register(rig: Object) -> void:
	if not _rigs.has(rig):
		_rigs.append(rig)


static func unregister(rig: Object) -> void:
	_rigs.erase(rig)


static func cap() -> int:
	if _cap < 0:
		_cap = MAX_SKINNED
		for a: String in OS.get_cmdline_user_args():
			if a.begins_with("--others-cap="):
				_cap = clampi(int(a.get_slice("=", 1)), 0, 64)
	return _cap


static func set_cap(n: int) -> void:
	_cap = clampi(n, 0, 64)
	_frame = -1


static func reset_for_tests() -> void:
	_cap = -1
	_frame = -1


## The slots for this frame (see the class notes); `force` decides now whatever the frame.
static func allocate(any: Node, force := false) -> void:
	var frame := Engine.get_process_frames()
	if not force and (_frame == frame or (_frame >= 0 and frame - _frame < FRAMES and frame >= _frame)):
		return
	_frame = frame
	var cam: Camera3D = null
	if any != null and any.is_inside_tree() and any.get_viewport() != null:
		cam = any.get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam != null else Vector3.ZERO
	var list: Array = []
	for r: Variant in _rigs:
		if not is_instance_valid(r):
			continue
		var o := r as Object
		if not bool(o.call("slot_wanted")):
			o.call("set_slot", false)
			continue
		list.append([float(o.call("slot_priority", cam_pos)), o])
	list.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var slots := cap()
	var shown := 0
	for e: Array in list:
		var on := float(e[0]) < BOSS * 0.5 or shown < slots
		if on:
			shown += 1
		elif bool((e[1] as Object).call("has_slot")):
			pass
		else:
			totals.waited = int(totals.waited) + 1
		(e[1] as Object).call("set_slot", on)
	totals.skinned_max = maxi(int(totals.skinned_max), shown)


## The live rigs (tests).
static func rigs() -> Array:
	return _rigs.filter(func(r: Variant) -> bool: return is_instance_valid(r))

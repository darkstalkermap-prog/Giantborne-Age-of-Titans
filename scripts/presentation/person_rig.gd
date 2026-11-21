class_name PersonRig
extends ActorRig
## A realistic person in play (P60; plan M11 §2.9, decisions 3, 4 and 12): soldiers, archers, mages, pikemen,
## shieldmen, bannermen, the iron guard and siege crews. The pose brain stays: this is an ActorRig, and
## ActorRig._process computes every pose on the frame clock as before (the stylized pivots under Visual/Body -
## HipL, HipR, Torso, ShoulderL, ShoulderR - stay, with no meshes); the body follows it at one of three levels,
## chosen every frame for every person at once (_allocate):
##
##   skinned  a pooled PersonModel under Visual/Body ("Model": P59's body variant on the 23-bone skeleton), one
##            AnimationPlayer in manual mode playing P59's clips from the brain's state - the walk and the run on
##            the brain's walk phase, the flee, the brace, the held body's limp and the thrown body's tumble, the
##            death - seeked with seek(t, false) and advanced (probe 7), each change of clip cross-faded over
##            FADE_S; then the arms: while the brain acts (an attack, a cast, a block, a brace, a pose override)
##            each arm is put where the brain's arm pose points by a two-bone solve (the torso's twist on the
##            spine), during a weapon arc by tip matching (TipMatching on the person's own joints: the visible
##            weapon shows the tested swing); otherwise the clips' arms swing as they walk. The gear (P59's
##            gear.glb: the weapon in the right fist, a shield on the left forearm, a quiver on the back) follows
##            the bones. Draw calls: the body, the weapon and a shield; one shadow draw (the body).
##   crowd    the role's crowd-pose mesh (hold, brace, advance, flee) as an instance of a MultiMesh, with the
##            palette row and the flash in its custom data (CrowdRenderer: the formation's renderer for its
##            members, one shared renderer for everyone else);
##   far      the role's far mesh, the same way.
## Skinned first: the held, the thrown, the striking, the staggered and the falling; then the nearest to the giant
## (in the giant's distance scale) within SKIN_RADIUS_M; never more than MAX_SKINNED (the `--people-cap=N`
## command line lowers it) - a held body is skinned even then. A person not skinned is a crowd instance out to
## its far distance from the camera (the record's render_lod_m x the giant's distance scale's square root), a far
## instance beyond. The levels are decided every ALLOC_FRAMES frames; an instanced person poses no pivots and reads
## its brain's state as often as the levels are decided (the CPU of a crowd: docs/systems/P60.md). A corpse: the death plays skinned; CORPSE_AFTER_S after the fall ends the body becomes a
## `corpse` crowd instance and frees its slot. AI LOD tier 2 (dormant): Visual/LodProxy shows the far mesh as
## EnemyActor already does (one instance of its own).
##
## Who the person is (PersonLook): the record's `body` (the role, a named variant, palette overrides, the gear),
## else the scene's exports; the variant and the palette row by the hash of the entity id (decision 12: no random
## stream is read). The skinned layers run where something is drawn, as the giant's (decision 6): with a display,
## with --skin, or after enable_for_tests(); never with --no-skin. Headless nothing is made or instanced: the
## brain poses its empty pivots as before.
##
## Presentation only (plan M10 §2.7, extended to the people): this rig writes under its own Visual node and reads
## the actor; nothing in the simulation reads it. PEOPLE_STATS (--skin-stats): run_stats(), printed by the
## Autopilot at exit, proves what ran.

## After the skinned body was posed this frame (the weapon's segment is valid inside it).
signal posed

const MAX_SKINNED := 16
## P64 (plan M11 §3.17 design 3, the people's tier): at the `low` graphics preset (the Web) this many are skinned; the
## Web bench's people's CPU with sixteen was twice its 2.5 ms (docs/systems/P64.md).
const LOW_SKINNED := 12
const GROUP := "person_rigs"
enum Level { NONE, SKINNED, CROWD, FAR, CORPSE, DORMANT }
const LEVEL_NAMES := ["none", "skinned", "crowd", "far", "corpse", "dormant"]
const MODEL_NAME := "Model"
const SOCKET_NAME := "WeaponSocket"
const POSES_PATH := "CrowdPoses"
const LOD_PROXY := "LodProxy"
## The clips' cross-fade (seconds; plan §2.9).
const FADE_S := 0.15
## Skinned out to this distance from the giant (metres x the giant's distance scale), the cap allowing.
const SKIN_RADIUS_M := 40.0
## A skinned person keeps its slot against a newcomer this much nearer (its distance x this).
const KEEP_SHARE := 0.85
## The far mesh beyond this distance from the camera when the record sets no render_lod_m (metres).
const FAR_DEFAULT_M := 45.0
## The levels are decided every this many frames (a person that starts to strike waits at most that long).
const ALLOC_FRAMES := 2
## A corpse leaves the skinned level this long after its fall ended (seconds).
const CORPSE_AFTER_S := 2.0
## The gaits: the run's clip above this speed (m/s, x the height scale). The walk clip covers the manifest's
## walk_cycle_m a cycle (P59b: 1.5 m, a natural 0.75 m step at 1.8 m): its time is the brain's walk phase (two
## stride_length_m a turn) scaled by 2 stride_length_m / walk_cycle_m, so no foot slides; the run and the flee
## cover the manifest's run_cycle_m (RUN_CYCLE_M without it) on a phase of their own (the brain's would turn them
## over twice as fast).
const RUN_FROM_MPS := 2.6
const RUN_CYCLE_M := 2.6
const WALK_CYCLE_M := 1.8
## P62: a fleeing civilian standing this long cowers (seconds), the crouch faded in and out over COWER_FADE_S.
const COWER_AFTER_S := 0.5
## P65b: a person standing and turning faster than TURN_STEP_FROM (rad/s; to TURN_STEP_TO to stop) steps round on the
## walk clip, a cycle every TURN_STEP_RAD of turn, instead of pivoting on planted feet (the feet slid round).
const TURN_STEP_FROM := 1.1
const TURN_STEP_TO := 0.5
const TURN_STEP_RAD := 2.4
const COWER_FADE_S := 0.35
## The thrown body's tumble and the held body's limp play at their own pace.
const HELD_RATE := 1.0
## How fast the arms go over to the brain's pose and back to the clips' (1 / s of weight).
const ARM_RATE := 10.0
## The brain's arm reaches this share of the real arm's reach (the generic mapping, as the giant's).
const GENERIC_REACH_USE := 0.9
## The fist's centre, in the hand bone's own frame (the bone's +Y runs from the wrist to the knuckles, +X across the
## curled fingers toward the thumb, +Z out of the palm's back), and the line a carried blade or haft takes from it:
## P59b's grip landmark of the variant (the manifest's grip_local_<side> and grip_axis_<side>: the handle through
## the curl of the four fingers, toward the index's side); these where a variant has none.
const FIST_LOCAL := Vector3(0.0, 0.075, 0.0)
const FIST_AXIS := Vector3(0.44, 0.88, 0.2)
## The elbow's pole (Body space, per arm: down, back and out).
const POLES := {"r": Vector3(0.55, -0.55, 0.6), "l": Vector3(-0.55, -0.55, 0.6)}
## Gear held upright when the clips carry it (a pike or a staff stands, a bow hangs), leaning this far forward.
const UPRIGHT_GEAR := ["spear", "staff", "bow"]
const UPRIGHT_LEAN_DEG := 8.0
## The gear's fit (a piece of gear.glb: its grip at the origin and its length along +Y): a scale along the length
## and a shift of the grip (metres at 1.8 m), so the pike is the formation's 4.2 m with 3.5 m before the hand, and
## the blade ends where the gameplay sword's length does.
const GEAR_FIT := {"spear": {"scale": 1.6, "shift": 1.22}, "sword": {"scale": 1.08, "shift": 0.0}}

## P64c: the strikes and braces keyed on the action (not on its hit shape: the box rig's sector pulse put onto real
## arms read as a T-pose). Each action's keys, mixed on its own clock (strike_key): "ready" -> "top" over the windup
## (eased out: drawn back), "top" -> "hit" over the first half of the active phase, "hit" -> "ready" over the
## recovery; a brace ("hold": true) is lowered into over the windup and held. A key: "r" [the weapon fist's direction
## from its shoulder (yaw, pitch: AttackGeometry's), its share of the palm's reach], "w" the weapon's direction (yaw,
## pitch), "haft" the off fist on the weapon this far above the weapon fist (metres at 1.8 m) or "l" [the off fist's
## direction, its share, the hand's long axis (actor space)], "twist" the torso's (degrees, + to the left), "lean" the
## spine bent forward (degrees), "kick" the right hip's flexion and the knee's bend (degrees). A weapon arc's ("arc":
## true, the mage's staff) keys are its windup only: its active phase keeps tip matching (the tested swing) with the
## off hand on the haft.
const STRIKE_KEYS := {
	"ability.pike_thrust": {"ready": {"r": [Vector2(28.0, -58.0), 0.72], "w": Vector2(-2.0, 14.0), "haft": 0.5, "twist": 0.0, "lean": 4.0},
		"top": {"r": [Vector2(42.0, -62.0), 0.5], "w": Vector2(-2.0, 12.0), "haft": 0.5, "twist": -22.0, "lean": 0.0},
		"hit": {"r": [Vector2(-6.0, -32.0), 0.74], "w": Vector2(-1.0, 10.0), "haft": 0.45, "twist": -2.0, "lean": 14.0}},
	"ability.shield_bash": {"ready": {"r": [Vector2(22.0, -62.0), 0.82], "w": Vector2(10.0, 35.0),
			"l": [Vector2(10.0, -30.0), 0.6, Vector3(0.9, 0.1, -0.4), Vector3(-1.0, -0.6, 0.3)], "twist": 0.0, "lean": 4.0},
		"top": {"r": [Vector2(35.0, -55.0), 0.7], "w": Vector2(15.0, 40.0),
			"l": [Vector2(38.0, -28.0), 0.5, Vector3(1.0, 0.1, 0.0), Vector3(-1.0, -0.4, 0.4)], "twist": -26.0, "lean": 10.0},
		"hit": {"r": [Vector2(28.0, -62.0), 0.75], "w": Vector2(10.0, 35.0),
			"l": [Vector2(30.0, -14.0), 0.72, Vector3(1.0, 0.1, -0.1), Vector3(-1.0, -0.3, -0.1)], "twist": -14.0, "lean": 18.0}},
	"ability.archer_kick": {"ready": {"r": [Vector2(18.0, -70.0), 0.85], "w": Vector2(10.0, 75.0),
			"l": [Vector2(-25.0, -40.0), 0.75, Vector3(-0.2, -0.5, -0.8)], "twist": 0.0, "lean": 0.0, "kick": Vector2(0.0, 0.0)},
		"top": {"r": [Vector2(35.0, -45.0), 0.75], "w": Vector2(20.0, 60.0), "l": [Vector2(-40.0, -15.0), 0.75, Vector3(-0.5, -0.2, -0.8)],
			"twist": 0.0, "lean": -6.0, "kick": Vector2(80.0, 110.0)},
		"hit": {"r": [Vector2(40.0, -35.0), 0.8], "w": Vector2(25.0, 55.0), "l": [Vector2(-45.0, -10.0), 0.8, Vector3(-0.6, -0.2, -0.7)],
			"twist": 0.0, "lean": -14.0, "kick": Vector2(82.0, 8.0)}},
	"ability.mage_staff": {"arc": true, "ready": {"r": [Vector2(25.0, -40.0), 0.7], "w": Vector2(30.0, 45.0), "haft": 0.25, "twist": 0.0, "lean": 0.0},
		"top": {"r": [Vector2(30.0, 18.0), 0.5], "w": Vector2(120.0, 42.0), "haft": 0.25, "twist": -22.0, "lean": -4.0},
		"hit": {"r": [Vector2(30.0, 18.0), 0.5], "w": Vector2(120.0, 42.0), "haft": 0.25, "twist": -22.0, "lean": -4.0}},
	"ability.formation_brace_pike": {"hold": true, "ready": {"r": [Vector2(25.0, -62.0), 0.8], "w": Vector2(0.0, 75.0), "haft": 0.6, "twist": 0.0, "lean": 0.0},
		"top": {"r": [Vector2(20.0, -84.0), 1.0], "w": Vector2(-2.0, 45.0), "haft": 0.55, "twist": -10.0, "lean": 20.0},
		"hit": {"r": [Vector2(20.0, -84.0), 1.0], "w": Vector2(-2.0, 45.0), "haft": 0.55, "twist": -10.0, "lean": 20.0}},
	"ability.formation_brace_shield": {"hold": true, "ready": {"r": [Vector2(22.0, -62.0), 0.82], "w": Vector2(10.0, 35.0),
			"l": [Vector2(10.0, -30.0), 0.6, Vector3(0.9, 0.1, -0.4), Vector3(-1.0, -0.6, 0.3)], "twist": 0.0, "lean": 0.0},
		"top": {"r": [Vector2(30.0, -50.0), 0.75], "w": Vector2(5.0, 45.0),
			"l": [Vector2(38.0, -20.0), 0.62, Vector3(1.0, 0.05, -0.05), Vector3(-1.0, -0.3, 0.0)], "twist": 0.0, "lean": 12.0},
		"hit": {"r": [Vector2(30.0, -50.0), 0.75], "w": Vector2(5.0, 45.0),
			"l": [Vector2(38.0, -20.0), 0.62, Vector3(1.0, 0.05, -0.05), Vector3(-1.0, -0.3, 0.0)], "twist": 0.0, "lean": 12.0}},
}

## The run's numbers over every PersonRig of the process (PEOPLE_STATS).
static var totals := {"skinned_frames": 0, "promotions": 0, "crowd_frames": 0, "crowd_instances": 0,
	"crowd_instances_max": 0, "far_instances": 0, "corpses": 0, "skinned_max": 0, "rigs": 0, "posed_frames": 0}
static var variants_drawn := {}
static var _forced := false
## {"role|variant": {"grip_r", "axis_r", "grip_l", "axis_l"}} read once from the people's manifest.
static var _grips := {}
static var _cli := 2               # 2 unread, 1 --skin, -1 --no-skin, 0 neither
static var _cap := -1              # -1 unread, else the cap (MAX_SKINNED or --people-cap / set_cap)
static var _rigs: Array = []
static var _alloc_frame := -1
static var _loners: WeakRef = null
static var _far_override := -2     # -2 unread, 0 no, 1 --people-far
static var _lengths := {}

## Exports the scene sets (people_models.gd): the default body when the record has none.
@export var person_role := "person_role.soldier"
@export var gear: PackedStringArray = PackedStringArray(["sword"])
@export var variant := ""

## PersonLook.spec() of this actor ({} until the first frame with the layers on).
var look: Dictionary = {}
var level := Level.NONE
## The frame a CrowdRenderer drew this person in (so two renderers never draw one person).
## The entity id and the model's transform in Visual's space (no lean), held for the renderers.
var entity_id := ""
var crowd_role := ""
var crowd_person_role := ""
var _base_xf := Transform3D.IDENTITY
var _custom := Color()
var _tint_mult := Color.WHITE
var drawn_frame := -1
## The crowd's per-pose gear of this person ([mesh, transform, set key] each; CrowdRenderer fills it once).
var crowd_cache := {}
var drawn_by := 0
var skinned_frames := 0
var _layers := false
var _model: PersonModel = null
var _socket: Node3D = null
var _gear: Dictionary = {}          # piece -> MeshInstance3D
var _gear_material: ShaderMaterial = null
var _clip := ""
var _clip_t := 0.0
var _run_phase := 0.0
var _dead_t := -1.0
var _w_arm := 0.0
var _w_off := 0.0
var _tm: TipMatching = null
var _tm_key := ""
var _bones := {}
## The shown variant's grip landmarks (grips_of).
var _grip := {"grip_r": FIST_LOCAL, "axis_r": FIST_AXIS.normalized(), "grip_l": FIST_LOCAL,
	"axis_l": (FIST_AXIS * Vector3(-1.0, 1.0, 1.0)).normalized()}
var _priority := 0.0
var _distance := 0.0
var _cam_distance := 0.0
var _flash_shown := 0.0
var _weapon_dir := Vector3.FORWARD
var _thrown_seen := false
var _still_t := 0.0
var _turn_yaw := INF
var _turn_rate := 0.0
var _turn_phase := 0.0
var _turning := false


# --------------------------------------------------------------------------- the switch (decision 6)

## The skinned people on in a headless test until reset_for_tests() (ResetHooks runs it after every test).
static func enable_for_tests() -> void:
	_forced = true


static func reset_for_tests() -> void:
	_forced = false
	_cap = -1
	_far_override = -2


## True where the people are drawn: a display, --skin or enable_for_tests(); never with --no-skin (the same switch
## as SkinnedRig.layers_enabled()).
static func layers_enabled() -> bool:
	if _cli == 2:
		var args := OS.get_cmdline_user_args()
		_cli = -1 if args.has("--no-skin") else (1 if args.has("--skin") else 0)
	if _cli < 0:
		return false
	if _forced or _cli > 0:
		return true
	return DisplayServer.get_name() != "headless"


## The most people skinned at once: MAX_SKINNED (LOW_SKINNED at the `low` preset), or --people-cap=N, or set_cap()
## (tests, benches).
static func cap() -> int:
	if _cap < 0:
		_cap = MAX_SKINNED
		var tree := Engine.get_main_loop() as SceneTree
		var settings: Node = tree.root.get_node_or_null("Settings") if tree != null else null
		if settings != null and str(settings.get("graphics_quality")) == "low":
			_cap = LOW_SKINNED
		for a: String in OS.get_cmdline_user_args():
			if a.begins_with("--people-cap="):
				_cap = clampi(int(a.get_slice("=", 1)), 0, 64)
	return _cap


static func set_cap(n: int) -> void:
	_cap = clampi(n, 0, 64)


## --people-far: every person not held or striking is drawn at the far level (the sheets' fallback view).
static func far_forced() -> bool:
	if _far_override == -2:
		_far_override = 1 if OS.get_cmdline_user_args().has("--people-far") else 0
	return _far_override == 1


## The run's numbers for PEOPLE_STATS: skinned frames, promotions, the variants drawn skinned, the crowd's
## instances (frames drawn, the sum and the largest frame), corpses, the most skinned at once, the rigs made; P64:
## "others", the brutes' and the wolves' (CreatureSlots.totals and the cap).
static func run_stats() -> Dictionary:
	var out := totals.duplicate()
	out["layers"] = layers_enabled()
	out["cap"] = cap()
	var names: Array = variants_drawn.keys()
	names.sort()
	out["variants"] = names
	# P64: the brutes and the wolves (plan §2.10's "others": CreatureSlots)
	var others := CreatureSlots.totals.duplicate()
	others["cap"] = CreatureSlots.cap()
	out["others"] = others
	return out


## Every live PersonRig (registered in the tree).
static func rigs() -> Array:
	var out: Array = []
	for r: Variant in _rigs:
		if is_instance_valid(r):
			out.append(r)
	return out


## The shared renderer of the people outside a formation (made with the first one it draws; null headless).
static func loner_renderer() -> CrowdRenderer:
	return _loners.get_ref() as CrowdRenderer if _loners != null else null


# --------------------------------------------------------------------------- setup

func _enter_tree() -> void:
	if not _rigs.has(self):
		_rigs.append(self)


func _exit_tree() -> void:
	_rigs.erase(self)
	_release_model()
	level = Level.NONE


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	totals.rigs = int(totals.rigs) + 1
	_layers = layers_enabled()


## The distance LOD: a person's levels are this rig's own (not RigPaint's proxies); render_lod_m sets where the
## far mesh takes over (see the class notes).
func set_render_lod(lod_m: float) -> void:
	render_lod_m = maxf(0.0, lod_m)


## The look (PersonLook.spec) from the actor's record, id and faction, and the scene's defaults; the crowd poses'
## and the far mesh's nodes take the role's meshes.
func _ensure_look() -> void:
	if not look.is_empty():
		return
	var rec: Variant = actor.get("record") if actor != null and "record" in actor else null
	var record: Dictionary = rec if typeof(rec) == TYPE_DICTIONARY else {}
	var id := str(actor.get("entity_id")) if actor != null and "entity_id" in actor else ""
	if id == "" and actor != null:
		id = str(actor.name)
	var faction := str(actor.get("faction")) if actor != null and "faction" in actor else ""
	look = PersonLook.spec(record.get("body"), id, faction, float(record.get("height_m", PersonModel.HEIGHT_M)),
		{"person_role": person_role, "gear": Array(gear), "variant": variant})
	entity_id = id
	_base_xf = model_transform(false)
	crowd_role = str(look.get("role", ""))
	crowd_person_role = str(look.get("person_role", ""))
	_custom = Color(float(look.get("row", 0)), 0.0, float(look.get("faction_row", 0)), 0.0)
	_fill_scene_meshes()


## body_spec() (plan §2.9): the role, the variant, the palette, the height scale and the gear.
func body_spec() -> Dictionary:
	if look.is_empty() and actor != null:
		_ensure_look()
	return look


## Visual/CrowdPoses/<pose> and Visual/LodProxy take the role's meshes (the scene holds empty nodes: the meshes
## are P59's, never copied into a scene).
func _fill_scene_meshes() -> void:
	var r := PersonModel.role_data(str(look.get("role", "")))
	if r.is_empty():
		return
	var poses := get_node_or_null(POSES_PATH)
	if poses != null:
		for c in poses.get_children():
			if c is MeshInstance3D and (r.poses as Dictionary).has(str(c.name)):
				(c as MeshInstance3D).mesh = r.poses[str(c.name)]
	var proxy := get_node_or_null(LOD_PROXY) as MultiMeshInstance3D
	if proxy != null and r.far != null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = r.far
		mm.instance_count = 1
		mm.set_instance_transform(0, model_transform(false))
		mm.set_instance_color(0, Color.WHITE)
		mm.set_instance_custom_data(0, custom_data())
		proxy.multimesh = mm
		proxy.material_override = PersonModel.crowd_material(str(look.person_role))
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The model's transform in this rig's space (Visual): turned 180 degrees (P59's people face +Z) and scaled by the
## body's height; `with_body`: under Visual/Body as it leans and staggers.
func model_transform(with_body := true) -> Transform3D:
	var h := float(look.get("height_scale", 1.0))
	var xf := Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * h), Vector3.ZERO)
	return body.transform * xf if with_body and body != null else xf


## A crowd instance's custom data: the palette row, the flash shown, the faction's row.
func custom_data() -> Color:
	_custom.g = _flash_shown
	return _custom


## The crowd instance's transform (global): the actor's, Visual's, then the model's turn and height.
func crowd_transform() -> Transform3D:
	return actor.global_transform * transform * _base_xf


## The status tint's albedo multiplier (a crowd instance's colour).
func tint_color() -> Color:
	return _tint_mult


func set_status_tint(color: Color) -> void:
	super.set_status_tint(color)
	var m := RigPaint.tint_multiplier(_tint)
	_tint_mult = Color(m.r, m.g, m.b, 1.0)


func flash_shown() -> float:
	return _flash_shown


# --------------------------------------------------------------------------- the levels

## The levels of every person for this frame (once a frame, whichever rig processes first; see the class notes).
static func _allocate(any: Node) -> void:
	var frame := Engine.get_process_frames()
	if _alloc_frame == frame or (frame % ALLOC_FRAMES != 0 and _alloc_frame >= 0 and absi(frame - _alloc_frame) < ALLOC_FRAMES):
		return
	_alloc_frame = frame
	var tree := any.get_tree() if any != null and any.is_inside_tree() else null
	if tree == null:
		return
	var giant := tree.get_first_node_in_group("player") as Node3D
	var scale := CrowdRenderer._distance_scale(giant)
	var cam := any.get_viewport().get_camera_3d() if any.get_viewport() != null else null
	var cands: Array = []
	var shown := 0
	for r: Variant in _rigs:
		if not is_instance_valid(r):
			continue
		var rig := r as PersonRig
		if not rig._layers or not rig.is_inside_tree() or rig.actor == null:
			continue
		var a := rig.actor
		var ea := a as EnemyActor
		var held := ea.is_held() if ea != null else (a.has_method("is_held") and bool(a.call("is_held")))
		var tier := ea.lod_tier if ea != null else (int(a.get("lod_tier")) if "lod_tier" in a else 0)
		if (tier >= 2 or not a.visible) and not held:   # P62: a sheltered civilian is hidden (indoors)
			rig._set_level(Level.DORMANT)
			continue
		var pos := a.global_position
		rig._distance = pos.distance_to(giant.global_position) / scale if giant != null else 0.0
		rig._cam_distance = pos.distance_to(cam.global_position) if cam != null else rig._distance * scale
		if rig._is_corpse():
			rig._set_level(Level.CORPSE)
			continue
		var urgent := 0 if held else (1 if rig._acting() else 2)
		var d := rig._distance * (KEEP_SHARE if rig.level == Level.SKINNED else 1.0)
		rig._priority = float(urgent) * 100000.0 + d
		cands.append(rig)
	cands.sort_custom(_before)
	var slots := cap()
	var far_all := far_forced()
	for rig: PersonRig in cands:
		var held := rig._priority < 100000.0
		var urgent := rig._priority < 200000.0
		var eligible := urgent or rig._distance <= SKIN_RADIUS_M
		if far_all and not urgent:
			eligible = false
		if held or (eligible and slots > 0):
			slots -= 1
			shown += 1
			rig._set_level(Level.SKINNED)
		elif not far_all and rig._cam_distance <= rig.far_distance(scale):
			rig._set_level(Level.CROWD)
		else:
			rig._set_level(Level.FAR)
	totals.skinned_max = maxi(int(totals.skinned_max), shown)
	if loner_renderer() == null and not cands.is_empty():
		var lr := CrowdRenderer.new()
		lr.name = "PeopleCrowd"
		lr.loners = true
		_loners = weakref(lr)
		tree.root.add_child.call_deferred(lr)


static func _before(x: PersonRig, y: PersonRig) -> bool:
	return x._priority < y._priority


## Every person's state read and the levels decided now (tests: the frames' own decisions come every ALLOC_FRAMES).
static func decide_now() -> void:
	var any: PersonRig = null
	for r: Variant in _rigs:
		if is_instance_valid(r) and (r as PersonRig).actor != null and (r as PersonRig).actor.has_method("get_rig_state"):
			(r as PersonRig)._last_state = (r as PersonRig).actor.get_rig_state()
			any = r
	_alloc_frame = -1
	if any != null:
		_allocate(any)


## Where the far mesh takes over (metres from the camera): the record's render_lod_m (FAR_DEFAULT_M without one)
## x the square root of the giant's distance scale.
func far_distance(scale: float) -> float:
	return (render_lod_m if render_lod_m > 0.0 else FAR_DEFAULT_M) * sqrt(maxf(scale, 1.0))


func _set_level(l: int) -> void:
	if l == level:
		return
	if l == Level.SKINNED:
		totals.promotions = int(totals.promotions) + 1
	elif level == Level.SKINNED:
		_release_model()
	if l == Level.CORPSE:
		totals.corpses = int(totals.corpses) + 1
	level = l


## Striking (an action), staggered, or falling (dead and not yet a corpse): it must show its own body.
func _acting() -> bool:
	var s := rig_state()
	return s.get("action") != null or bool(s.get("staggered", false)) or bool(s.get("dead", false))


func _is_corpse() -> bool:
	return _dead_t >= 0.0 and _dead_t >= _death_length() + CORPSE_AFTER_S


func _death_length() -> float:
	return clip_length("death")


## A clip's length (seconds; 1 without the clips), read once a process.
static func clip_length(clip: String) -> float:
	if not _lengths.has(clip):
		var lib := PersonModel.clip_library()
		_lengths[clip] = lib.get_animation(clip).length if lib != null and lib.has_animation(clip) else 1.0
	return _lengths[clip]


func level_name() -> String:
	return LEVEL_NAMES[level]


## True while this person holds a skinned slot.
func skinned() -> bool:
	return level == Level.SKINNED and _model != null


# --------------------------------------------------------------------------- the frame

func _process(delta: float) -> void:
	if _layers and actor != null and (level == Level.CROWD or level == Level.FAR or level == Level.CORPSE) \
			and actor.has_method("get_rig_state"):
		# an instance: nothing poses its pivots; the brain's state is read for the levels (as often as they are
		# decided) and the corpse's clock
		if Engine.get_process_frames() % ALLOC_FRAMES == 0:
			_last_state = actor.get_rig_state()
		_update_flash(delta)
	else:
		super._process(delta)
	if not _layers or actor == null:
		return
	_ensure_look()
	var s := rig_state()
	if bool(s.get("dead", false)):
		_dead_t = maxf(_dead_t, 0.0) + delta
	elif _dead_t >= 0.0:
		_dead_t = -1.0   # a respawn
	_allocate(self)
	if level == Level.SKINNED:
		_skinned_frame(delta)
	else:
		_release_model()


## The brain's body lean, without its fall: the death clip falls the skinned body (the crowd's corpse lies).
func _update_body(s: Dictionary, delta: float) -> void:
	if bool(s.get("dead", false)) and _layers:
		body.rotation = body.rotation.lerp(Vector3.ZERO, 1.0 - exp(-12.0 * delta))
		body.position = body.position.lerp(Vector3.ZERO, 1.0 - exp(-12.0 * delta))
		_fall = move_toward(_fall, 1.0, delta * 1.6)
		return
	super._update_body(s, delta)


func _ensure_model() -> bool:
	if _model != null:
		return true
	if body == null:
		return false
	_model = PersonModel.acquire(str(look.get("role", "")), str(look.get("variant", "")))
	if _model == null:
		return false
	_model.name = MODEL_NAME
	body.add_child(_model)
	_model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * float(look.get("height_scale", 1.0))), Vector3.ZERO)
	_model.mesh_instance().cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	PersonLook.apply(_model.material, look)
	variants_drawn[str(look.get("variant", ""))] = true
	_index_bones()
	_build_gear()
	_clip = ""
	_w_arm = 0.0
	_w_off = 0.0
	_tint_dirty = true
	return true


func _release_model() -> void:
	if _model != null:
		PersonModel.release(_model)
		_model = null
	if _socket != null:
		_socket.queue_free()
		_socket = null
	for n: Variant in _gear.values():
		if is_instance_valid(n):
			(n as Node).queue_free()
	_gear.clear()


## A variant's grip landmarks ({"grip_r", "axis_r", "grip_l", "axis_l"}, the hand bones' frames, metres at 1.8 m):
## the manifest's, else FIST_LOCAL and FIST_AXIS.
static func grips_of(role: String, p_variant: String) -> Dictionary:
	if _grips.is_empty():
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(PersonModel.MANIFEST))
		var roles: Dictionary = (doc as Dictionary).get("roles", {}) if doc is Dictionary else {}
		for r: String in roles:
			var vs: Dictionary = (roles[r] as Dictionary).get("variants", {})
			for v: String in vs:
				var e: Dictionary = vs[v]
				var g := {}
				for side: String in ["r", "l"]:
					g["grip_" + side] = _vec(e.get("grip_local_" + side), FIST_LOCAL * Vector3(1.0 if side == "r" else -1.0, 1.0, 1.0))
					g["axis_" + side] = _vec(e.get("grip_axis_" + side), FIST_AXIS * Vector3(1.0 if side == "r" else -1.0, 1.0, 1.0)).normalized()
				_grips["%s|%s" % [r, v]] = g
		if _grips.is_empty():
			_grips["-"] = {}
	var out: Dictionary = _grips.get("%s|%s" % [role, p_variant], {})
	if out.is_empty():
		return {"grip_r": FIST_LOCAL, "axis_r": FIST_AXIS.normalized(), "grip_l": FIST_LOCAL,
			"axis_l": (FIST_AXIS * Vector3(-1.0, 1.0, 1.0)).normalized()}
	return out


static func _vec(v: Variant, fallback: Vector3) -> Vector3:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return fallback


func _index_bones() -> void:
	var sk := _model.skeleton()
	_bones.clear()
	for i in sk.get_bone_count():
		_bones[sk.get_bone_name(i)] = i
	_grip = grips_of(_model.role, _model.variant)
	var key := "%s|%s|%s" % [look.get("role", ""), look.get("variant", ""), look.get("height_scale", 1.0)]
	if key != _tm_key:
		_tm_key = key
		_tm = TipMatching.from_landmarks(_landmarks(sk))


## The person's joints in Body space at rest (TipMatching's landmarks: +X the right, -Z the front).
func _landmarks(sk: Skeleton3D) -> Dictionary:
	var m := model_transform(false)
	var lm := {}
	for side: String in ["r", "l"]:
		var up := m * sk.get_bone_global_rest(sk.find_bone("upperarm_" + side)).origin
		var lo := m * sk.get_bone_global_rest(sk.find_bone("lowerarm_" + side)).origin
		var ha_t := sk.get_bone_global_rest(sk.find_bone("hand_" + side))
		lm["shoulder_" + side] = up
		lm["elbow_" + side] = lo
		lm["wrist_" + side] = m * ha_t.origin
		lm["palm_" + side] = m * (ha_t * (_grip["grip_" + side] as Vector3))
		lm["hip_" + side] = m * sk.get_bone_global_rest(sk.find_bone("thigh_" + side)).origin
		lm["knee_" + side] = m * sk.get_bone_global_rest(sk.find_bone("calf_" + side)).origin
		lm["ankle_" + side] = m * sk.get_bone_global_rest(sk.find_bone("foot_" + side)).origin
	lm["pelvis"] = m * sk.get_bone_global_rest(sk.find_bone("pelvis")).origin
	lm["eye_mid"] = m * sk.get_bone_global_rest(sk.find_bone("head")).origin
	return lm


## One skinned frame: the clip from the brain's state, the arms, the gear.
func _skinned_frame(delta: float) -> void:
	if not _ensure_model():
		return
	skinned_frames += 1
	totals.skinned_frames = int(totals.skinned_frames) + 1
	var s := rig_state()
	_play(s, delta)
	var sk := _model.skeleton()
	if sk != null and not _bones.is_empty():
		_pose_arms(sk, s, delta)
		_place_gear(sk, s)
	totals.posed_frames = int(totals.posed_frames) + 1
	posed.emit()


## The clip and its time from the brain's state (see the class notes), cross-faded on a change.
func _play(s: Dictionary, delta: float) -> void:
	var ap := _model.player()
	if ap == null:
		return
	var speed := float(s.get("speed", 0.0))
	var h := maxf(float(look.get("height_scale", 1.0)), 0.1)
	var clip := "idle"
	var t := -1.0
	var held := actor.has_method("is_held") and bool(actor.call("is_held"))
	if bool(s.get("dead", false)) and not held:
		clip = "death"
		t = minf(maxf(_dead_t, 0.0), _death_length())
	elif held:
		clip = "tumble" if _thrown() else "held"
	elif is_walking():
		_still_t = 0.0
		var fleeing := _fleeing()
		if speed / h >= RUN_FROM_MPS or fleeing:
			clip = "flee" if fleeing else "run"
			_run_phase += delta * speed / (float(PersonModel.index().get("run_cycle_m", RUN_CYCLE_M)) * h) * TAU
			t = fposmod(_run_phase + PI * 0.5, TAU) / TAU
		else:
			clip = "walk"
			t = fposmod(walk_phase() * walk_ratio() + PI * 0.5, TAU) / TAU
		t *= clip_length(clip)
	elif _bracing(s):
		clip = "brace"
		t = 0.0
	elif _cowering(delta):
		clip = "cower"
	if _step_turn(delta) and clip == "idle":
		clip = "walk"
		t = fposmod(_turn_phase, 1.0) * clip_length("walk")
	if clip != _clip:
		var first := _clip == ""
		var fade := COWER_FADE_S if clip == "cower" or _clip == "cower" else FADE_S
		_clip = clip
		ap.play(StringName(String(PersonModel.LIBRARY) + "/" + clip), 0.0 if first else fade)
		_clip_t = 0.0
	if t < 0.0:
		_clip_t += delta * (HELD_RATE if held else 1.0)
		t = _clip_t
	var length := clip_length(clip)
	var loops := clip in PersonModel.LOOPS
	var before := fposmod(t - delta, length) if loops else maxf(t - delta, 0.0)
	ap.seek(before, false)
	ap.advance(delta if loops or t >= delta else t)


## Turning on the spot (P65b): the actor's yaw rate, smoothed; true while it is fast enough to step round (see
## TURN_STEP_FROM), the step's phase advanced by the turn.
func _step_turn(delta: float) -> bool:
	var yaw := actor.global_rotation.y
	if _turn_yaw == INF or delta <= 0.0:
		_turn_yaw = yaw
		return false
	var d := wrapf(yaw - _turn_yaw, -PI, PI)
	_turn_yaw = yaw
	_turn_rate = lerpf(_turn_rate, absf(d) / delta, 1.0 - exp(-10.0 * delta))
	_turning = _turn_rate > (TURN_STEP_TO if _turning else TURN_STEP_FROM)
	if _turning:
		_turn_phase += absf(d) / TURN_STEP_RAD
	return _turning


## Fleeing: an enemy's brain in FLEE or ROUTED, a civilian's in FLEE (P62).
func _fleeing() -> bool:
	var brain: Variant = actor.get("brain") if "brain" in actor else null
	if brain is CivilianBrain:
		return (brain as CivilianBrain).state == CivilianBrain.State.FLEE
	return brain != null and int((brain as Object).get("state")) in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED]


## A civilian cowers (P62; plan §2.8's `cower`): fleeing with nowhere to run (or waiting for its path) for longer
## than COWER_AFTER_S, it crouches with its arms over its head where it stands.
func _cowering(delta: float) -> bool:
	var brain: Variant = actor.get("brain") if "brain" in actor else null
	if not (brain is CivilianBrain) or (brain as CivilianBrain).state != CivilianBrain.State.FLEE:
		_still_t = 0.0
		return false
	_still_t += delta
	return _still_t >= COWER_AFTER_S


## The walk clip's turns per turn of the brain's walk phase: 2 stride_length_m / the clip's cycle (the manifest's
## walk_cycle_m).
func walk_ratio() -> float:
	var cycle := float(PersonModel.index().get("walk_cycle_m", WALK_CYCLE_M))
	return 2.0 * stride_length_m / maxf(cycle, 0.1)


## The brain braces (a block, a guard, a formation's brace) standing still.
func _bracing(s: Dictionary) -> bool:
	if int(s.get("state", 0)) == CombatController.State.BLOCKING or bool(s.get("guarding", false)):
		return true
	var a: ActionDef = s.get("action")
	return a != null and a.hit_shape == "band_pulse"


## A held body that left the hand: the projectile system carries it (it tumbles until it lands).
func _thrown() -> bool:
	var giant := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	var grab: Variant = giant.get("grab") if giant != null and "grab" in giant else null
	if grab == null or not (grab as Object).has_method("held_entity"):
		return false
	var e: Variant = (grab as Object).call("held_entity")
	var mine: Variant = actor.get("entity") if "entity" in actor else null
	return e == null or not is_instance_valid(e) or e != mine


# --------------------------------------------------------------------------- the arms

## The arms: the clips' unless the brain acts; then each arm on the brain's pose by a two-bone solve (the weapon
## arm in a weapon arc by tip matching), weighted in and out at ARM_RATE; the torso's twist on the spine.
func _pose_arms(sk: Skeleton3D, s: Dictionary, delta: float) -> void:
	var action: ActionDef = s.get("action")
	var override := typeof(s.get("pose_override")) == TYPE_DICTIONARY
	var state := int(s.get("state", 0))
	var dead := bool(s.get("dead", false))
	var held := actor.has_method("is_held") and bool(actor.call("is_held"))
	var acting := not dead and not held and (action != null or override or state == CombatController.State.BLOCKING
		or bool(s.get("guarding", false)))
	var arc := acting and action != null and action.hit_shape == "weapon_arc" and not override
	var exact := arc and int(s.get("phase", 0)) == ActionDef.Phase.ACTIVE
	_w_arm = 1.0 if exact else move_toward(_w_arm, 1.0 if acting else 0.0, delta * ARM_RATE)
	_w_off = move_toward(_w_off, 1.0 if acting else 0.0, delta * ARM_RATE)
	var m := _model.transform
	var mi := m.affine_inverse()
	var to_body := (transform * body.transform).affine_inverse()
	# P64c: an action with keys (STRIKE_KEYS) takes its keyed pose (a weapon arc's: its windup only)
	var keyed: Dictionary = strike_key(action, int(s.get("phase", 0)), float(s.get("phase_fraction", 0.0))) \
		if acting and not override else {}
	if keyed.has("r") and arc and int(s.get("phase", 0)) != ActionDef.Phase.WINDUP:
		keyed = {"haft": keyed.haft, "two": keyed.get("two", 1.0)}   # (the tested swing: tip matching, the off hand on the haft)
	var twist := (deg_to_rad(float(keyed.twist)) if keyed.has("twist") else torso_twist()) * _w_arm
	if absf(twist) > 1e-5:
		var q := Basis(Vector3.UP, twist / 3.0)
		for b: String in ["spine_01", "spine_02", "spine_03"]:
			var i: int = _bones[b]
			var gp := sk.get_bone_global_pose(i)
			gp.basis = q * gp.basis
			_set_global_rotation(sk, i, gp.basis)
	if absf(float(keyed.get("lean", 0.0))) > 1e-3:
		bend_spine(sk, _bones, mi, deg_to_rad(float(keyed.lean)) * _w_arm)
	if keyed.has("kick"):
		_kick(sk, mi, keyed.kick as Vector2, _w_arm)
	_butt_w = _w_arm if keyed.has("r") and action.id == "ability.formation_brace_pike" else 0.0
	if keyed.has("r"):
		_keyed_arms(sk, m, mi, to_body, keyed)
		return
	var hand_r := sk.get_bone_global_pose(_bones.hand_r)
	var clip_dir := _carried_dir(m, hand_r)
	_weapon_dir = clip_dir
	if _w_arm > 0.0:
		var pose := arm_pose()
		var dir := (to_body.basis * AttackGeometry.local_direction(pose.x, clampf(pose.y, -AttackGeometry.MAX_PITCH_DEG,
			AttackGeometry.MAX_PITCH_DEG))).normalized()
		var sh := m * sk.get_bone_global_pose(_bones.upperarm_r).origin
		var target := sh + dir * GENERIC_REACH_USE * _tm.palm_reach("r")
		var hand_dir := dir
		var wdir := _held_dir(dir)
		if arc and _tm != null:
			var pivot := to_body * (actor.get("weapon_pivot") as Vector3) if "weapon_pivot" in actor else sh
			var mt := _tm.match_swing_at(sh, pivot, dir, float(actor.get("arm_length")), float(actor.get("weapon_length")), "r")
			target = mt.grip
			hand_dir = mt.hand_dir
			wdir = mt.weapon_dir
		_arm_ik(sk, "r", m, mi, target, hand_dir, _w_arm)
		_weapon_dir = _slerp_dir(clip_dir, wdir.normalized(), _w_arm) if _w_arm < 1.0 else wdir
		if not _weapon_dir.is_finite():
			_weapon_dir = clip_dir
	if keyed.has("haft"):
		_off_on_haft(sk, m, mi, float(keyed.haft), _w_off * float(keyed.get("two", 1.0)))
	elif _w_off > 0.0:
		var off := off_pose()
		var odir := (to_body.basis * AttackGeometry.local_direction(off.x, clampf(off.y, -80.0, 80.0))).normalized()
		var shl := m * sk.get_bone_global_pose(_bones.upperarm_l).origin
		_arm_ik(sk, "l", m, mi, shl + odir * GENERIC_REACH_USE * _tm.palm_reach("l"), odir, _w_off)


## P64c: the keyed pose of `action` at `phase` / `f` (STRIKE_KEYS mixed on the action's clock; {} without keys). A
## weapon arc's key carries "two", the off hand's weight on the haft (letting go over the recovery).
static func strike_key(action: ActionDef, phase: int, f: float) -> Dictionary:
	if action == null or not STRIKE_KEYS.has(action.id):
		return {}
	var spec: Dictionary = STRIKE_KEYS[action.id]
	var t := clampf(f, 0.0, 1.0)
	var e := 1.0 - (1.0 - t) * (1.0 - t)
	var out: Dictionary
	if bool(spec.get("hold", false)):
		out = _mix_key(spec.ready, spec.top, smoothstep(0.0, 1.0, e)) if phase == ActionDef.Phase.WINDUP else (spec.top as Dictionary).duplicate()
	else:
		match phase:
			ActionDef.Phase.WINDUP:
				out = _mix_key(spec.ready, spec.top, e)
			ActionDef.Phase.ACTIVE:
				out = _mix_key(spec.top, spec.hit, smoothstep(0.0, 0.5, t))
			ActionDef.Phase.RECOVERY:
				out = _mix_key(spec.hit, spec.ready, smoothstep(0.0, 1.0, t))
			_:
				out = (spec.ready as Dictionary).duplicate()
	if bool(spec.get("arc", false)):
		out["two"] = 1.0 - smoothstep(0.15, 0.7, t) if phase == ActionDef.Phase.RECOVERY else 1.0
	return out


static func _mix_key(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k: String in a:
		var va: Variant = a[k]
		var vb: Variant = b.get(k, va)
		match typeof(va):
			TYPE_FLOAT:
				out[k] = lerpf(float(va), float(vb), t)
			TYPE_VECTOR2:
				out[k] = (va as Vector2).lerp(vb as Vector2, t)
			TYPE_ARRAY:
				var arr: Array = []
				for i in (va as Array).size():
					var x: Variant = (va as Array)[i]
					var y: Variant = (vb as Array)[i]
					if typeof(x) == TYPE_VECTOR2:
						arr.append((x as Vector2).lerp(y as Vector2, t))
					elif typeof(x) == TYPE_VECTOR3:
						arr.append((x as Vector3).lerp(y as Vector3, t))
					else:
						arr.append(lerpf(float(x), float(y), t))
				out[k] = arr
			_:
				out[k] = va
	return out


## The keyed arms (P64c, STRIKE_KEYS): the weapon fist from its shoulder along the key, the weapon along the key's
## direction; the off fist on the haft or along its own key.
func _keyed_arms(sk: Skeleton3D, m: Transform3D, mi: Transform3D, to_body: Transform3D, k: Dictionary) -> void:
	var hand_r := sk.get_bone_global_pose(_bones.hand_r)
	var clip_dir := _carried_dir(m, hand_r)
	var r: Array = k.r
	var dir := (to_body.basis * AttackGeometry.local_direction((r[0] as Vector2).x, (r[0] as Vector2).y)).normalized()
	var wdir := (to_body.basis * AttackGeometry.local_direction((k.w as Vector2).x, (k.w as Vector2).y)).normalized()
	var sh := m * sk.get_bone_global_pose(_bones.upperarm_r).origin
	var target := sh + dir * float(r[1]) * _tm.palm_reach("r")
	_arm_ik(sk, "r", m, mi, target, _slerp_dir(wdir, dir, 0.35), _w_arm)
	_weapon_dir = _slerp_dir(clip_dir, wdir, _w_arm) if _w_arm < 1.0 else wdir
	if k.has("haft"):
		_off_on_haft(sk, m, mi, float(k.haft), _w_off)
	elif k.has("l") and _w_off > 0.0:
		var l: Array = k.l
		var odir := (to_body.basis * AttackGeometry.local_direction((l[0] as Vector2).x, (l[0] as Vector2).y)).normalized()
		var shl := m * sk.get_bone_global_pose(_bones.upperarm_l).origin
		var pole := (to_body.basis * (l[3] as Vector3)).normalized() if l.size() > 3 else Vector3.ZERO
		_arm_ik(sk, "l", m, mi, shl + odir * float(l[1]) * _tm.palm_reach("l"), (to_body.basis * (l[2] as Vector3)).normalized(), _w_off,
			pole)


## P64c: the pike's butt is this far behind the fist as carried (GEAR_FIT: 4.2 m, 3.5 m before the hand; metres at
## 1.8 m); braced it slides back through the fist, at most BUTT_SLIDE_MAX_M, to BUTT_GROUND_M over the ground.
const BUTT_BEHIND_M := 0.7
const BUTT_SLIDE_MAX_M := 1.0
const BUTT_GROUND_M := 0.04
var _butt_w := 0.0


## P64c: the off fist never comes nearer the weapon fist on a haft than this (metres at 1.8 m: a hand's breadth).
const HAFT_MIN_M := 0.14


## P64c: the off fist on the weapon `gap` metres (at 1.8 m) above the weapon fist, the hand along the haft, by `w`.
func _off_on_haft(sk: Skeleton3D, m: Transform3D, mi: Transform3D, gap: float, w: float) -> void:
	if w <= 0.0:
		return
	var h := float(look.get("height_scale", 1.0))
	var hand := sk.get_bone_global_pose(_bones.hand_r)
	var fist := m * (hand * (_grip.grip_r as Vector3))
	var u := _weapon_dir.normalized()
	var shl := m * sk.get_bone_global_pose(_bones.upperarm_l).origin
	# beyond the arm's reach the hand slides down the haft toward the point nearest the shoulder (not closer to the
	# weapon fist than HAFT_MIN_M)
	var t := gap * h
	var reach := _tm.palm_reach("l") * 0.97
	if shl.distance_to(fist + u * t) > reach:
		var nearest := clampf((shl - fist).dot(u), HAFT_MIN_M * h, t)
		var lo := nearest
		var hi := t
		for i in 8:
			var mid := (lo + hi) * 0.5
			if shl.distance_to(fist + u * mid) > reach:
				hi = mid
			else:
				lo = mid
		t = lo
	var on := fist + u * t
	_arm_ik(sk, "l", m, mi, on, _slerp_dir(u, (on - shl).normalized(), 0.4), w)


## Bends the spine forward (+) by `ang` radians over its three bones, about the body's side axis (`mi` the model's
## inverse transform in Body space).
static func bend_spine(sk: Skeleton3D, bones: Dictionary, mi: Transform3D, ang: float) -> void:
	var axis := (mi.basis * Vector3.RIGHT).normalized()
	for b: String in ["spine_01", "spine_02", "spine_03"]:
		var i: int = bones[b]
		_set_global_rotation(sk, i, Basis(axis, -ang / 3.0) * sk.get_bone_global_pose(i).basis)


## P64c: the right leg's kick: the hip flexed forward by `k.x` degrees, the knee bent back by `k.y`, by `w`.
func _kick(sk: Skeleton3D, mi: Transform3D, k: Vector2, w: float) -> void:
	if w <= 0.0 or k == Vector2.ZERO:
		return
	var axis := (mi.basis * Vector3.RIGHT).normalized()
	var it: int = _bones.thigh_r
	var ic: int = _bones.calf_r
	_set_global_rotation(sk, it, Basis(axis, deg_to_rad(k.x) * w) * sk.get_bone_global_pose(it).basis)
	_set_global_rotation(sk, ic, Basis(axis, -deg_to_rad(k.y) * w) * sk.get_bone_global_pose(ic).basis)


## The weapon's direction (Body space) as the clips' hand carries it: an upright piece stands, leaning a little
## forward; any other lies along the fist's handle line.
func _carried_dir(m: Transform3D, hand: Transform3D) -> Vector3:
	if _main_gear() in UPRIGHT_GEAR:
		return Vector3(0.0, cos(deg_to_rad(UPRIGHT_LEAN_DEG)), -sin(deg_to_rad(UPRIGHT_LEAN_DEG)))
	return (m.basis * (hand.basis * (_grip.axis_r as Vector3))).normalized()


## The weapon's direction in the brain's pose `dir` (Body space): along the arm, tilted up from the forearm's line
## by TipMatching's grip angle; a bow stands across the aim.
func _held_dir(dir: Vector3) -> Vector3:
	if _main_gear() == "bow":
		var up := Vector3.UP - dir * dir.dot(Vector3.UP)
		return up.normalized() if up.length_squared() > 1e-6 else Vector3.UP
	var perp := Vector3.UP - dir * dir.dot(Vector3.UP)
	if perp.length_squared() < 1e-6:
		perp = Vector3.FORWARD - dir * dir.dot(Vector3.FORWARD)
	var a := deg_to_rad(TipMatching.GRIP_AXIS_DEG)
	return (dir * cos(a) + perp.normalized() * sin(a)).normalized()


## Puts the fist of `side` on `target` (Body space) with the hand's long axis along `hand_dir`, blended over the
## clip's arm by `w`: the upper arm and the forearm turned by the shortest arc onto a two-bone solve (the elbow
## toward POLES), the hand turned onto its direction.
func _arm_ik(sk: Skeleton3D, side: String, m: Transform3D, mi: Transform3D, target: Vector3, hand_dir: Vector3, w: float,
		pole := Vector3.ZERO) -> void:
	solve_arm(sk, _bones, side, m, mi, target, hand_dir, w, float(look.get("height_scale", 1.0)), _grip["grip_" + side], pole)


## _arm_ik's solve for any skinned person (P62: the cavalry's rider too): `bones` the skeleton's bone indices by
## name, `m` the model's transform in the space of `target` and `hand_dir` (`mi` its inverse), `h` the model's
## height scale, `fist_local` the fist's centre in the hand bone's frame.
static func solve_arm(sk: Skeleton3D, bones: Dictionary, side: String, m: Transform3D, mi: Transform3D, target: Vector3,
		hand_dir: Vector3, w: float, h: float, fist_local: Vector3, pole := Vector3.ZERO) -> void:
	var iu: int = bones["upperarm_" + side]
	var il: int = bones["lowerarm_" + side]
	var ih: int = bones["hand_" + side]
	var gu := sk.get_bone_global_pose(iu)
	var gl := sk.get_bone_global_pose(il)
	var gh := sk.get_bone_global_pose(ih)
	var sh := m * gu.origin
	var fist_now := m * (gh * fist_local)
	var dir_now := (m.basis * gh.basis.y).normalized()
	if not target.is_finite() or not hand_dir.is_finite() or hand_dir.length_squared() < 1e-8:
		return
	if w < 1.0:
		target = fist_now.lerp(target, w)
		hand_dir = _slerp_dir(dir_now, hand_dir.normalized(), w)
	hand_dir = hand_dir.normalized()
	var l1 := gu.origin.distance_to(gl.origin) * h
	var l2 := gl.origin.distance_to(gh.origin) * h
	var hl := (gh.basis * fist_local).length() * h
	var wrist := target - hand_dir * hl
	var solve := TipMatching.two_bone(sh, wrist, l1, l2, POLES[side] if pole == Vector3.ZERO else pole)
	var el_s: Vector3 = mi * (solve.elbow as Vector3)
	var wr_s: Vector3 = mi * (solve.end as Vector3)
	var from_u := (gl.origin - gu.origin).normalized()
	var to_u := (el_s - gu.origin).normalized()
	if from_u.angle_to(to_u) > 1e-6:
		gu.basis = _arc(from_u, to_u) * gu.basis
		_set_global_rotation(sk, iu, gu.basis)
	gl = sk.get_bone_global_pose(il)
	gh = sk.get_bone_global_pose(ih)
	var from_l := (gh.origin - gl.origin).normalized()
	var to_l := (wr_s - gl.origin).normalized()
	if from_l.angle_to(to_l) > 1e-6:
		gl.basis = _arc(from_l, to_l) * gl.basis
		_set_global_rotation(sk, il, gl.basis)
	gh = sk.get_bone_global_pose(ih)
	var want := (mi.basis * hand_dir).normalized()
	var cur := gh.basis.y.normalized()
	if cur.angle_to(want) > 1e-6:
		gh.basis = _arc(cur, want) * gh.basis
		_set_global_rotation(sk, ih, gh.basis)


## Turns bone `i` so its global basis is `basis` (skeleton space): only the bone's rotation is written (its position
## and scale stay the clip's), and nothing when the result is not a rotation.
static func _set_global_rotation(sk: Skeleton3D, i: int, basis: Basis) -> void:
	var p := sk.get_bone_parent(i)
	var parent := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	var q := (parent.inverse() * basis.orthonormalized()).get_rotation_quaternion()
	if q.is_finite() and q.is_normalized():
		sk.set_bone_pose_rotation(i, q)


## The shortest turn from `a` to `b` (unit vectors); about a perpendicular axis when they are opposite, none when
## either is not a direction.
static func _arc(a: Vector3, b: Vector3) -> Basis:
	if not a.is_finite() or not b.is_finite() or a.length_squared() < 1e-8 or b.length_squared() < 1e-8:
		return Basis()
	var axis := a.cross(b)
	var ang := a.angle_to(b)
	if axis.length_squared() < 1e-10:
		if ang < 1e-3:
			return Basis()
		axis = a.cross(Vector3.RIGHT if absf(a.x) < 0.9 else Vector3.UP)
	return Basis(axis.normalized(), ang)


## `a` turned toward `b` by `t` (unit vectors), safe when they are opposite.
static func _slerp_dir(a: Vector3, b: Vector3, t: float) -> Vector3:
	if not a.is_finite() or not b.is_finite():
		return b if b.is_finite() else a
	if a.angle_to(b) > PI - 1e-3:
		return (Basis(a.cross(Vector3.RIGHT if absf(a.x) < 0.9 else Vector3.UP).normalized(), PI * t) * a).normalized()
	return a.slerp(b, t).normalized()


# --------------------------------------------------------------------------- the gear

## The weapon (the first piece of the look's gear that is not worn: not the shield or the quiver).
func _main_gear() -> String:
	for p: Variant in look.get("gear", []):
		if not str(p) in ["shield", "quiver"]:
			return str(p)
	return ""


func _build_gear() -> void:
	if _gear_material == null:
		_gear_material = PersonModel.gear_material()
	PersonLook.apply(_gear_material, look)
	_socket = Node3D.new()
	_socket.name = SOCKET_NAME
	body.add_child(_socket)
	for p: Variant in look.get("gear", []):
		var piece := str(p)
		var mesh := PersonModel.gear_mesh(piece)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Gear_" + piece
		mi.mesh = mesh
		mi.material_override = _gear_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if piece == _main_gear():
			var fit: Dictionary = GEAR_FIT.get(piece, {})
			var h := float(look.get("height_scale", 1.0))
			mi.transform = Transform3D(Basis.from_scale(Vector3(h, h * float(fit.get("scale", 1.0)), h)),
				Vector3(0.0, float(fit.get("shift", 0.0)) * h, 0.0))
			_socket.add_child(mi)
		else:
			body.add_child(mi)
		_gear[piece] = mi


## The gear on the bones: the weapon's socket on the fist along the weapon's direction (its +Y), a shield on the
## left forearm facing out, a quiver on the back.
func _place_gear(sk: Skeleton3D, _s: Dictionary) -> void:
	var m := _model.transform
	var h := float(look.get("height_scale", 1.0))
	if _socket != null:
		var hand := sk.get_bone_global_pose(_bones.hand_r)
		var fist := m * (hand * (_grip.grip_r as Vector3))
		var y := _weapon_dir.normalized()
		var z := (m.basis * hand.basis.y).normalized()
		z = (z - y * y.dot(z))
		if z.length_squared() < 1e-6:
			z = Vector3.BACK - y * y.dot(Vector3.BACK)
		z = z.normalized()
		_socket.transform = Transform3D(Basis(y.cross(z), y, z), fist)
	# P64c: a braced pike slides back through the fist until its butt is on the ground (BUTT_* below)
	var main := _gear.get(_main_gear()) as MeshInstance3D
	if main != null and _main_gear() == "spear" and _socket != null:
		var fit: Dictionary = GEAR_FIT.spear
		var slide := 0.0
		if _butt_w > 0.0 and _weapon_dir.y > 0.2:
			var behind := (_socket.position.y - BUTT_GROUND_M * h) / _weapon_dir.normalized().y
			slide = clampf(behind - BUTT_BEHIND_M * h, 0.0, BUTT_SLIDE_MAX_M * h) * _butt_w
		var want := (float(fit.shift) * h) - slide
		if absf(main.position.y - want) > 1e-5:
			main.position.y = want
	var shield := _gear.get("shield") as MeshInstance3D
	if shield != null:
		var lo := sk.get_bone_global_pose(_bones.lowerarm_l)
		var ha := sk.get_bone_global_pose(_bones.hand_l)
		var a := m * lo.origin
		var b := m * ha.origin
		var along := (b - a).normalized()
		var centre := a.lerp(b, 0.55)
		var chest := m * sk.get_bone_global_pose(_bones.spine_03).origin
		var out := centre - chest
		out = (out - along * along.dot(out)).normalized()
		var x := (-along).cross(out).normalized()
		shield.transform = Transform3D(Basis(x, -along, out).scaled(Vector3.ONE * h), centre + out * 0.07 * h)
	var quiver := _gear.get("quiver") as MeshInstance3D
	if quiver != null:
		var sp := sk.get_bone_global_pose(_bones.spine_03)
		var back := m * sp.origin
		var up := (m.basis * sp.basis.y).normalized()
		var behind := (m.basis * -sp.basis.z).normalized()
		var tilt := Basis(behind, deg_to_rad(-20.0))
		var yb := (tilt * up).normalized()
		var zb := behind
		quiver.transform = Transform3D(Basis(yb.cross(zb).normalized(), yb, zb).scaled(Vector3.ONE * h),
			back + behind * 0.16 * h + Vector3(0.08 * h, -0.05 * h, 0.0))


## The visible weapon [grip, tip] in global space (valid inside `posed`; [] without a skinned body).
func visible_weapon_segment() -> Array:
	if _socket == null or not _socket.is_inside_tree():
		return []
	var grip := _socket.global_position
	var dir := _socket.global_transform.basis.y.normalized()
	var length := float(actor.get("weapon_length")) if actor != null and "weapon_length" in actor else 0.95
	return [grip, grip + dir * length]


func model() -> PersonModel:
	return _model


func weapon_socket() -> Node3D:
	return _socket


## The arms' weights over the clips' (tests): {"arm", "off"}.
func arm_weights() -> Dictionary:
	return {"arm": _w_arm, "off": _w_off}


func current_clip() -> String:
	return _clip


# --------------------------------------------------------------------------- paint

## The flash and the status tint on the skinned body and its gear (the `tint` and `flash` uniforms); a crowd
## instance reads flash_shown() and tint_color().
func _update_flash(delta: float) -> void:
	if _flash <= 0.0 and _flash_applied <= 0.0 and not _tint_dirty:
		return
	_tint_dirty = false
	_flash = maxf(0.0, _flash - delta * 6.0)
	_flash_applied = _flash
	_flash_shown = _flash
	var mats: Array = []
	if _model != null and _model.material != null:
		mats.append(_model.material)
	if _gear_material != null:
		mats.append(_gear_material)
	RigPaint.paint_shaders(mats, _tint, _flash, _flash_color)
	RigPaint.paint(_materials, _base_colors, _tint, _flash, _flash_color)

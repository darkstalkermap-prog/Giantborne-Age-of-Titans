class_name LevelRoot
extends Node3D
## The root node of a level built for encounters (the Valley, the director test level; plan
## §2.7.4, §2.12). It names the level's `level` record and answers the lookups gameplay needs:
## markers, checkpoints, area triggers and patrol routes by id, the district at a point, the
## player, and the navigation map and regions. Group "level_root": ProjectileSystem parents
## its projectiles here, EnemyActor snaps flee points to nav_region(), and GameSession reads
## the start checkpoint of the level record named by level_id.
##
## Expected children (the builders make them): Navigation/{Human,Large,Giant,SmallGiant}
## (NavigationRegion3D on nav layers 1/2/4/8), Markers/<kind>/<marker> (LevelMarker),
## Markers/Patrol/<route>/<n> (a route node whose Node3D children are its points; the node is
## named after the route id with dots as underscores, String.validate_node_name()), Triggers/
## (AreaTrigger), Spawns/PlayerSpawn, Spawned (the EncounterDirector's actors), Player and
## EncounterDirector.
##
## Lookups are built once at _ready from the groups (descendants of this root only) and
## rebuilt when an id is not found, so nodes added later (tests) are found too.
##
## Graphics presets (P14, plan §3.16, §5.4): at _ready, and whenever the graphics setting
## changes, the level record's `render` preset for the quality in effect is applied - the Sun's
## directional_shadow_max_distance (0 switches its shadows off; a sun built without shadows never
## gets them), visibility_range_end on every scenery geometry below this
## root (groups SCENERY_GROUPS) and the viewport's 3D MSAA (put back when the level leaves the
## tree). The quality is Settings.graphics_quality; on the web (or with force_web_for_tests) the
## record's `web_overrides` decide instead: their `quality` (low) and `ai_tier1_m`, the distance
## beyond which the EncounterDirector runs AI LOD tier 1 (its near_m: 30 m instead of 40 m).

const GROUP := "level_root"
## Navigation layer bit -> the child of Navigation that holds it (plan §2.2).
const NAV_REGION_NAMES := {1: "Human", 2: "Large", 4: "Giant", 8: "SmallGiant"}
## Scenery geometry the preset's scenery_visibility_end_m applies to: "scenery" (any level) and
## the Valley builder's "valley_scenery" (its tree MultiMeshes).
const SCENERY_GROUPS := ["scenery", "valley_scenery"]
## A preset's msaa (samples) -> Viewport.MSAA.
const MSAA_MODES := {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}
## The quality the web build runs when the record's web_overrides name none.
const WEB_QUALITY := "low"
## Level-wide nodes later packages own, created at run time so no builder needs them (P20, plan
## M6-M9 §2.6): [node name, script path, the level ids it serves]. _ready makes each one whose
## script exists for this level (a missing script is skipped silently), as a child of this root.
const RUNTIME_NODES := [
	["Discovery", "res://scripts/world/discovery.gd", ["level.valley", "level.world"]],   # P27
	["WanderDirector", "res://scripts/world/wander_director.gd", ["level.world"]],         # P37
]

## The id of this level's `level` record (budget, AI LOD, districts, start checkpoint).
@export var level_id := "level.valley"

## Tests: behave as the web build (apply the record's web_overrides). Reset it after the test.
static var force_web_for_tests := false

## What apply_graphics() did last: {"quality", "web", "shadow_distance_m", "scenery_visibility_end_m",
## "scenery_nodes", "msaa", "ai_tier1_m"} (only the keys it applied; {} before the first call).
var applied_graphics: Dictionary = {}

var _markers: Dictionary = {}       # marker_id -> LevelMarker
var _checkpoints: Dictionary = {}   # checkpoint_id -> CheckpointMarker
var _areas: Dictionary = {}         # area_id -> AreaTrigger
var _player_ref: WeakRef = null
var _msaa_before := -1              # the viewport's MSAA before this level changed it (-1: unchanged)
var _sun_shadows := -1              # whether the scene's sun cast shadows before the first preset (-1: unread)


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	rebuild_lookups()
	apply_graphics()
	if not Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.connect(_on_settings_changed)
	create_runtime_nodes()


func _exit_tree() -> void:
	_restore_msaa()


## The level record named by level_id ({} when there is none, e.g. a level without data).
func level_record() -> Dictionary:
	var rec := GameData.get_record(level_id)
	return rec if str(rec.get("type", "")) == "level" else {}


## This level's world index (P20, plan M6-M9 §2.6): positions, display names and arrival limits
## of its checkpoints, markers, areas, POIs, exits, encounters and quest props, also for nodes that
## are not loaded. null when the level has none (WorldIndex.for_level; cached).
func index() -> WorldIndex:
	return WorldIndex.for_level(level_id)


## The navigation layer the player uses here when its growth profile's layer is not baked in this
## level: the record's player_nav_fallback (P20 declares it; the Valley's 4 comes with P26, the
## world's 16 with P25); 0 when the record has none.
func player_nav_fallback() -> int:
	return int(level_record().get("player_nav_fallback", 0))


## Makes the RUNTIME_NODES (or `entries`, tests) this level serves whose scripts exist (once: a
## node of that name already below this root is kept). Returns the nodes made now.
func create_runtime_nodes(entries: Array = RUNTIME_NODES) -> Array[Node]:
	var made: Array[Node] = []
	for entry: Array in entries:
		var node_name := str(entry[0])
		var path := str(entry[1])
		var levels: Array = entry[2]
		if not levels.has(level_id) or has_node(NodePath(node_name)) or not ResourceLoader.exists(path):
			continue
		var script := load(path) as Script
		if script == null:
			continue
		var n: Variant = script.new()
		if not (n is Node):
			push_warning("LevelRoot: runtime node %s (%s) is not a Node" % [node_name, path])
			continue
		(n as Node).name = node_name
		add_child(n as Node)
		made.append(n as Node)
	return made


## Re-reads the groups (called at _ready and when a lookup misses).
func rebuild_lookups() -> void:
	_markers.clear()
	_checkpoints.clear()
	_areas.clear()
	if not is_inside_tree():
		return
	var tree := get_tree()
	for n in tree.get_nodes_in_group(LevelMarker.GROUP):
		var m := n as LevelMarker
		if m != null and m.marker_id != "" and _owns(m) and not _markers.has(m.marker_id):
			_markers[m.marker_id] = m
	for n in tree.get_nodes_in_group("checkpoints"):
		var c := n as CheckpointMarker
		if c != null and c.checkpoint_id != "" and _owns(c) and not _checkpoints.has(c.checkpoint_id):
			_checkpoints[c.checkpoint_id] = c
	for n in tree.get_nodes_in_group(AreaTrigger.GROUP):
		var a := n as AreaTrigger
		if a != null and a.area_id != "" and _owns(a) and not _areas.has(a.area_id):
			_areas[a.area_id] = a


## The LevelMarker with this marker_id (null when there is none).
func marker(id: String) -> Node3D:
	return _lookup(_markers, id) as Node3D


## The checkpoint marker (CheckpointMarker, Waystone or a shrine's SpawnPoint) with this id.
func checkpoint(id: String) -> Node3D:
	return _lookup(_checkpoints, id) as Node3D


## The AreaTrigger with this area_id (null when there is none).
func area(id: String) -> AreaTrigger:
	return _lookup(_areas, id) as AreaTrigger


## Markers/Patrol/<route> for a route id such as "valley.patrol.wolves_a" (the node's name is
## the id with dots as underscores; a route node may also carry the id as meta "route_id").
## Its Node3D children are the patrol points, in order. null when there is none.
func patrol_route(route_id: String) -> Node3D:
	if route_id == "":
		return null
	var routes := get_node_or_null("Markers/Patrol")
	if routes == null:
		return null
	var n := routes.get_node_or_null(NodePath(route_id.validate_node_name())) as Node3D
	if n != null:
		return n
	for child in routes.get_children():
		if child is Node3D and str(child.get_meta("route_id", "")) == route_id:
			return child as Node3D
	return null


## The id of the level record's district whose rectangle (x and z, level space) contains
## `pos` (a global position), or "" when none does.
func district_at(pos: Vector3) -> String:
	var local := to_local(pos) if is_inside_tree() else pos
	var districts: Variant = level_record().get("districts")
	if typeof(districts) != TYPE_ARRAY:
		return ""
	for d: Variant in districts:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var lo: Variant = d.get("min_m")
		var hi: Variant = d.get("max_m")
		if typeof(lo) != TYPE_ARRAY or typeof(hi) != TYPE_ARRAY or (lo as Array).size() != 3 \
				or (hi as Array).size() != 3:
			continue
		if local.x >= float(lo[0]) and local.x <= float(hi[0]) and local.z >= float(lo[2]) \
				and local.z <= float(hi[2]):
			return str(d.get("id", ""))
	return ""


## The player of this level: the giant in group "player" below this root (else any giant in
## the tree, e.g. a test that added its own). null when there is none.
func player() -> GiantPlayer:
	if _player_ref != null:
		var p := _player_ref.get_ref() as GiantPlayer
		if p != null and p.is_inside_tree():
			return p
	_player_ref = null
	if not is_inside_tree():
		return null
	var fallback: GiantPlayer = null
	for n in get_tree().get_nodes_in_group("player"):
		var g := n as GiantPlayer
		if g == null or not g.is_inside_tree():
			continue
		if _owns(g):
			_player_ref = weakref(g)
			return g
		if fallback == null:
			fallback = g
	return fallback


## The navigation map of nav layer `layer` (0 = the human layer's): here the world's default map for
## every layer (an invalid RID outside the tree). A streamed world keeps one map per layer
## (WorldRoot, P24b; NavQuery and the actors ask through it).
func nav_map(layer := 0) -> RID:
	if layer < 0:
		return RID()
	return get_world_3d().navigation_map if is_inside_tree() else RID()


## The navigation region that serves nav layer `layer` (a single bit: 1 human, 2 large,
## 4 giant, 8 small giant): Navigation/<Human|Large|Giant|SmallGiant>, else any region below
## Navigation whose navigation_layers include it. Invalid RID when the level has none (for
## NavigationServer3D.region_get_closest_point: flee and safe points).
func nav_region(layer: int) -> RID:
	var nav := get_node_or_null("Navigation")
	if nav == null:
		return RID()
	var named := nav.get_node_or_null(NodePath(str(NAV_REGION_NAMES.get(layer, "")))) as NavigationRegion3D
	if named != null and (named.navigation_layers & layer) != 0:
		return named.get_rid()
	for r in nav.find_children("*", "NavigationRegion3D", true, false):
		var region := r as NavigationRegion3D
		if (region.navigation_layers & layer) != 0:
			return region.get_rid()
	return RID()


## The node encounter actors are spawned under (LevelRoot/Spawned; made when missing).
func spawn_parent() -> Node3D:
	var s := get_node_or_null("Spawned") as Node3D
	if s == null:
		s = Node3D.new()
		s.name = "Spawned"
		add_child(s)
	return s


## The level's EncounterDirector (LevelRoot/EncounterDirector), or null.
func director() -> EncounterDirector:
	return get_node_or_null("EncounterDirector") as EncounterDirector


func _lookup(table: Dictionary, id: String) -> Node:
	if id == "":
		return null
	var n: Variant = table.get(id)
	if n == null or not is_instance_valid(n) or not (n as Node).is_inside_tree():
		rebuild_lookups()
		n = table.get(id)
	return n as Node if n != null and is_instance_valid(n) else null


func _owns(n: Node) -> bool:
	return n == self or is_ancestor_of(n)


# --------------------------------------------------------------------------- graphics presets (P14)

## True in the web build, or while force_web_for_tests is set.
static func is_web() -> bool:
	return OS.has_feature("web") or force_web_for_tests


## The record's web_overrides ({} when it has none).
func web_overrides() -> Dictionary:
	var w: Variant = level_record().get("web_overrides", {})
	return w if typeof(w) == TYPE_DICTIONARY else {}


## The graphics quality this level runs: on the web the record's web_overrides.quality (default
## low), else Settings.graphics_quality (the saved setting or the --graphics flag).
func graphics_quality() -> String:
	if is_web():
		var q := str(web_overrides().get("quality", WEB_QUALITY))
		return q if Settings.GRAPHICS_QUALITIES.has(q) else WEB_QUALITY
	return Settings.graphics_quality


## The record's render preset for `quality` ({} when the record has none).
func render_preset(quality: String) -> Dictionary:
	var render: Variant = level_record().get("render", {})
	if typeof(render) != TYPE_DICTIONARY:
		return {}
	var preset: Variant = (render as Dictionary).get(quality, {})
	return preset if typeof(preset) == TYPE_DICTIONARY else {}


## Applies the render preset of graphics_quality() (and, on the web, the AI tier-1 distance of
## web_overrides) and returns what it applied (also kept in applied_graphics). Safe to call
## again: everything it sets is absolute. Called at _ready and on a graphics setting change.
func apply_graphics() -> Dictionary:
	var q := graphics_quality()
	var out := {"quality": q, "web": is_web()}
	var preset := render_preset(q)
	if SchemaUtil.is_number(preset.get("shadow_distance_m")):
		var sun := sun_light()
		if sun != null:
			# 0 turns the sun's shadows off (they roughly double a Valley view's draw calls).
			var dist := float(preset.shadow_distance_m)
			if _sun_shadows < 0:
				_sun_shadows = 1 if sun.shadow_enabled else 0
			sun.shadow_enabled = dist > 0.0 and _sun_shadows == 1
			if dist > 0.0:
				sun.directional_shadow_max_distance = dist
			out["shadow_distance_m"] = dist
	if SchemaUtil.is_number(preset.get("scenery_visibility_end_m")):
		var end := float(preset.scenery_visibility_end_m)
		var nodes := scenery_nodes()
		for g in nodes:
			g.visibility_range_end = end
		out["scenery_visibility_end_m"] = end
		out["scenery_nodes"] = nodes.size()
	if SchemaUtil.is_number(preset.get("msaa")) and is_inside_tree():
		var mode: int = MSAA_MODES.get(int(preset.msaa), Viewport.MSAA_DISABLED)
		var vp := get_viewport()
		if _msaa_before < 0:
			_msaa_before = vp.msaa_3d
		vp.msaa_3d = mode as Viewport.MSAA
		out["msaa"] = int(preset.msaa)
	if is_web():
		var tier1: Variant = web_overrides().get("ai_tier1_m")
		var d := director()
		if SchemaUtil.is_number(tier1) and d != null:
			# The director's tier-0 radius: beyond it members run the reduced tier-1 rates.
			d.near_m = minf(float(tier1), d.mid_m)
			out["ai_tier1_m"] = d.near_m
	_p24a_apply_view(preset, out)   # P24a: camera_far_m and terrain_visibility_end_m (anchor P24a)
	applied_graphics = out
	return out


## The level's sun: the child named "Sun", else the first DirectionalLight3D below this root.
func sun_light() -> DirectionalLight3D:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		return sun
	var found := find_children("*", "DirectionalLight3D", true, false)
	return found[0] as DirectionalLight3D if not found.is_empty() else null


## The scenery geometry below this root (members of SCENERY_GROUPS), each once.
func scenery_nodes() -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if not is_inside_tree():
		return out
	for group: String in SCENERY_GROUPS:
		for n in get_tree().get_nodes_in_group(group):
			var g := n as GeometryInstance3D
			if g != null and _owns(g) and not out.has(g):
				out.append(g)
	return out


func _on_settings_changed(key: String) -> void:
	if key == "graphics_quality" and is_inside_tree():
		apply_graphics()


## Puts the viewport's MSAA back as it was before this level changed it.
func _restore_msaa() -> void:
	if _msaa_before < 0:
		return
	var vp := get_viewport()
	if vp != null:
		vp.msaa_3d = _msaa_before as Viewport.MSAA
	_msaa_before = -1


# --------------------------------------------------------------------------- package anchors (M6-M9)
# Written by P20 (plan M6-M9 §1.5): a package adds its code directly below its own anchor
# (P24a: streaming hooks of WorldRoot's base; P24b: nav_map(layer), nav_layers(), NavQuery
# settings; P25: regions; P27: discovery and map lookups).

## @anchor P24a
# --- view distances (P24a, plan M6-M9 §2.7, decision 12) ------------------------------------------
# A render preset may name camera_far_m (the camera's far plane: 2,400 m in the world, so the fog
# and the skyline can show the world to its edge; DEFAULT_CAMERA_FAR_M, today's 800 m, when absent)
# and terrain_visibility_end_m (a streamed chunk's terrain beyond it from the camera is not drawn;
# the skyline shows instead). apply_graphics() applies both with the rest of the preset: the far
# plane to the player's CameraRig (which also asks camera_far_m() when it is set up), the
# visibility range to every terrain mesh below this root (TERRAIN_GROUP; WorldRoot passes it on to
# the chunks its streamer makes later).

const DEFAULT_CAMERA_FAR_M := 800.0
const TERRAIN_GROUP := "world_terrain"


## The camera far plane of the render preset in effect (camera_far_m), else DEFAULT_CAMERA_FAR_M.
func camera_far_m() -> float:
	var v: Variant = render_preset(graphics_quality()).get("camera_far_m")
	return float(v) if SchemaUtil.is_number(v) and float(v) > 0.0 else DEFAULT_CAMERA_FAR_M


## terrain_visibility_end_m of the render preset in effect (0 = no limit).
func terrain_visibility_end_m() -> float:
	var v: Variant = render_preset(graphics_quality()).get("terrain_visibility_end_m")
	return maxf(float(v), 0.0) if SchemaUtil.is_number(v) else 0.0


## The terrain meshes below this root (TERRAIN_GROUP).
func terrain_nodes() -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(TERRAIN_GROUP):
		var g := n as GeometryInstance3D
		if g != null and _owns(g):
			out.append(g)
	return out


func _p24a_apply_view(preset: Dictionary, out: Dictionary) -> void:
	var far := camera_far_m()
	var p := player()
	if p != null and p.camera_rig != null and p.camera_rig.camera != null:
		p.camera_rig.set_far_plane(far)
	out["camera_far_m"] = far
	if SchemaUtil.is_number(preset.get("terrain_visibility_end_m")):
		var end := terrain_visibility_end_m()
		for g in terrain_nodes():
			g.visibility_range_end = end
		out["terrain_visibility_end_m"] = end

## @anchor P24b
# --- navigation by layer (P24b, plan M6-M9 §2.8, decision 13) -------------------------------------
# nav_map(layer) (above: the default map for every layer here; WorldRoot's own map per layer),
# nav_layers() (the layers this level has navigation for), nav_layer_for(layers) (the layer a giant
# whose growth profile names `layers` uses here: its own when the level has it, else the record's
# player_nav_fallback) and nav_query_settings() (the record's nav_query block: NavQuery's parameters,
# the repath throttle and the per-tick query budget; {} keeps today's queries, so the Valley's paths
# do not change).

## The single nav layer bits this level has navigation for, ascending: the layers of its
## Navigation regions here ([1, 2, 4, 8] in the Valley); a streamed world's world.nav_layers.
func nav_layers() -> PackedInt32Array:
	var bits := 0
	var nav := get_node_or_null("Navigation")
	if nav != null:
		for r in nav.find_children("*", "NavigationRegion3D", true, false):
			bits |= int((r as NavigationRegion3D).navigation_layers)
	var out := PackedInt32Array()
	var bit := 1
	while bit <= bits and bit > 0:
		if (bits & bit) != 0:
			out.append(bit)
		bit <<= 1
	return out


## The layer a giant whose growth profile names `layers` paths on here: the lowest of `layers` the
## level has (nav_layers()), else the record's player_nav_fallback (the Valley's 4 for stages 4-6
## from P26, the world's 16 for stage 3), else `layers` unchanged.
func nav_layer_for(layers: int) -> int:
	for bit in nav_layers():
		if (layers & bit) != 0:
			return bit
	var fallback := player_nav_fallback()
	return fallback if fallback > 0 else layers


## The record's nav_query block ({} when it has none: NavQuery then uses map_get_path's parameters,
## and actors keep today's re-path rule).
func nav_query_settings() -> Dictionary:
	var q: Variant = level_record().get("nav_query")
	return (q as Dictionary).duplicate() if typeof(q) == TYPE_DICTIONARY else {}

## @anchor P25

## @anchor P27

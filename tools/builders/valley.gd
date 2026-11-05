extends RefCounted
## Builder: the Valley of Broken Kings (plan §3.11, §4, §2.12): a 400 x 400 m blockout built from
## one layout table, tools/data/valley_layout.json (not exported). It writes
##   * scenes/world/valley/<district>.tscn - one sub-scene per district (hollow, forest, barrow,
##     village, quarry, ruins, kingsfall, and "hills" for the impassable cliffs and the map edge):
##     Collision (one StaticBody3D on WORLD with a CollisionShape3D per element), Blockers (one
##     StaticBody3D on the blockers layer: the invisible river banks and bridge rails), Visual (one
##     MultiMeshInstance3D per material and unit mesh) and Scenery (the trees' MultiMeshes, with
##     visibility_range_end 220 m, group "valley_scenery");
##   * assets/nav/valley_{human,large,giant,small_giant}.res - the four navigation meshes (nav
##     layers 1/2/4/8, plan §2.2), baked here, offline, from the very elements the collision comes
##     from (plus the solid shapes of every placed prop, shrine, waystone and dummy) and saved
##     compressed; nothing bakes at runtime (the single-threaded web export);
##   * scenes/world/valley.tscn - the root: LevelRoot (level.valley), Environment (depth fog from
##     120 m), Sun, Districts/<id>, Navigation/{Human,Large,Giant,SmallGiant}, Props, Shrines,
##     Waystones, Dummies, Markers/<Kind>/<marker>, Markers/Patrol/<route>/<n>, Triggers/<area>,
##     Kingsfall/{ArenaGate,Pillars}, Signs, Spawns/PlayerSpawn, Spawned, Player,
##     EncounterDirector and DebrisPool.
## Runs after the player, prop, shrine and world-prop builders (tools/build_scenes.gd BUILDERS).
##
## Navigation layers and links. NavigationServer3D connects each end of a NavigationLink3D to the
## single closest polygon of the whole map, whatever its layer, so one link across a gate would
## serve one of the four overlapping regions only. The four regions therefore sit at different
## heights above the walking surface (NAV_LAYERS "above": human 0.35, small giant 0.25, large
## 0.15, giant 0.0 m), and every prop that blocks a road (the barricade, the practice gate, the
## Deadfall) gets one link per layer, NavLink<Region>, at its region's height, disabled until the
## prop breaks (BreakableProp enables every NavLink* child). A layer's paths are that much above
## the ground, which keeps every agent's waypoint distance (EnemyActor path_desired_distance 0.6)
## comfortable; the prop scene's own NavLinkThrough (y 0) connects the lowest region, the giant's.

const LAYOUT_PATH := "res://tools/data/valley_layout.json"
const ROOT_PATH := "res://scenes/world/valley.tscn"
const DISTRICT_DIR := "res://scenes/world/valley/"
const NAV_DIR := "res://assets/nav/"
const LEVEL_ID := "level.valley"

const S_LEVEL := "res://scripts/world/level_root.gd"
const S_DIRECTOR := "res://scripts/world/encounter_director.gd"
const S_MARKER := "res://scripts/world/level_marker.gd"
const S_TRIGGER := "res://scripts/world/area_trigger.gd"
const S_WAYSTONE := "res://scripts/world/waystone.gd"
const S_DEBRIS := "res://scripts/world/debris_pool.gd"
const GIANT := "res://scenes/player/giant.tscn"
const SHRINE := "res://scenes/world/shrine.tscn"
const DUMMY := "res://scenes/world/practice_dummy.tscn"

## Layout "scene" keys of the props -> their scenes (P08, P04; the forge is P12's and optional).
const PROP_SCENES := {
	"fence_wood": "res://scenes/world/fence_wood.tscn",
	"gate_practice": "res://scenes/world/gate_practice.tscn",
	"gate_fortified": "res://scenes/world/gate_fortified.tscn",
	"tree_small": "res://scenes/world/tree_small.tscn",
	"ancient_oak": "res://scenes/world/ancient_oak.tscn",
	"deadfall": "res://scenes/world/deadfall.tscn",
	"cart_barricade": "res://scenes/world/cart_barricade.tscn",
	"cairn": "res://scenes/world/cairn.tscn",
	"crate": "res://scenes/world/crate.tscn",
	"weapon_rack": "res://scenes/world/weapon_rack.tscn",
	"item_pickup": "res://scenes/world/item_pickup.tscn",
	"bush": "res://scenes/world/bush.tscn",
	"banner": "res://scenes/world/banner.tscn",
	"forge": "res://scenes/world/forge.tscn",
}

## The four navigation layers (plan §2.2). "above": the height of the layer's navmesh over the
## walking surface (the region is moved down from where Recast puts it, 2 cell heights up), and
## of its links. Agent heights and climbs are whole cell heights (0.25 m): the small giant's 3.7 m
## becomes 3.75 m.
const NAV_LAYERS := [
	{"layer": 1, "node": "Human", "file": "valley_human.res", "radius": 0.6, "height": 2.0, "climb": 0.25,
		"cell": 0.3, "above": 0.35},
	{"layer": 2, "node": "Large", "file": "valley_large.res", "radius": 1.5, "height": 4.0, "climb": 0.5,
		"cell": 0.5, "above": 0.15},
	{"layer": 4, "node": "Giant", "file": "valley_giant.res", "radius": 2.0, "height": 8.5, "climb": 0.75,
		"cell": 0.5, "above": 0.0},
	{"layer": 8, "node": "SmallGiant", "file": "valley_small_giant.res", "radius": 0.9, "height": 3.75,
		"climb": 0.5, "cell": 0.3, "above": 0.25},
]
const CELL_HEIGHT := 0.25
const MAX_SLOPE_DEG := 35.0
## Islands smaller than this many cells squared are dropped by the bake (Recast min region area).
const REGION_MIN_SIZE := 8.0
## The bake's fixed bounds: the map plus the inner half of the edge ring, from the bottom of the
## ground (-1 m), so the voxel grid (and with it the navmesh height) never shifts with the content.
const BAKE_AABB := AABB(Vector3(-205, -1, -205), Vector3(410, 61, 410))
## Where Recast puts a navmesh over a flat walking surface (two cell heights up); the builder
## measures it after each bake and moves the region so the layer ends up "above" the ground.
const EXPECTED_SURFACE_OFFSET := 0.5

## Scenery (trees) is hidden beyond this distance (plan §3.11; P14 applies the level record's
## presets to the group).
const SCENERY_VISIBILITY_END_M := 220.0
const SCENERY_GROUP := "valley_scenery"
const FOG_BEGIN_M := 120.0
const FOG_END_M := 300.0
const SKY := Color(0.56, 0.64, 0.74)

## Kinds of the markers (LevelMarker.Kind) and the folder under Markers/ each one goes in.
const MARKER_KINDS := {"objective": [0, "Objective"], "cover": [1, "Cover"], "elevation": [2, "Elevation"],
	"formation": [3, "Formation"], "safe": [4, "Safe"], "patrol": [5, "PatrolPoints"], "bot_route": [6, "BotRoute"]}

## Unit meshes the visuals scale (MultiMesh instance transforms carry the size).
const MESH_KINDS := ["box", "cyl", "cone", "prism", "plane"]

const LAYER_WORLD := 1
const LAYER_BLOCKER := 32


static func build_all(kit: SceneKit) -> void:
	var layout := load_layout(LAYOUT_PATH)
	if layout.is_empty():
		push_error("valley: cannot read %s" % LAYOUT_PATH)
		return
	_materials(kit)
	var geo := collect(layout)
	var district_ids: Array = []
	for d: Dictionary in layout.get("districts", []):
		district_ids.append(str(d.id))
	for id: String in district_ids:
		kit.save(build_district(kit, id, geo), DISTRICT_DIR + id + ".tscn")
	var root := build_root(kit, layout, district_ids)
	if root != null:
		kit.save(root, ROOT_PATH)


## The layout table ({} when it is missing or not a JSON object).
static func load_layout(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


# --------------------------------------------------------------------------- materials

static func _materials(kit: SceneKit) -> void:
	_ground_mat(kit, "valley_grass", Color(0.42, 0.52, 0.31), Color(0.39, 0.49, 0.29), Color(0.34, 0.43, 0.26), 8.0)
	_ground_mat(kit, "valley_forest_floor", Color(0.30, 0.38, 0.23), Color(0.28, 0.36, 0.21), Color(0.24, 0.31, 0.19), 8.0)
	_ground_mat(kit, "valley_dirt", Color(0.49, 0.43, 0.33), Color(0.46, 0.40, 0.31), Color(0.39, 0.34, 0.27), 8.0)
	_ground_mat(kit, "valley_pavement", Color(0.52, 0.51, 0.49), Color(0.48, 0.47, 0.46), Color(0.39, 0.38, 0.38), 4.0)
	kit.add_material("valley_road", Color(0.55, 0.47, 0.35), 1.0)
	kit.add_material("valley_water", Color(0.20, 0.38, 0.55), 0.15, 0.1)
	kit.add_material("valley_cliff", Color(0.46, 0.43, 0.38), 0.95)
	kit.add_material("valley_cliff_dark", Color(0.36, 0.34, 0.31), 0.95)
	kit.add_material("valley_plaster", Color(0.80, 0.74, 0.62), 0.9)
	kit.add_material("valley_thatch", Color(0.62, 0.50, 0.28), 0.95)
	kit.add_material("valley_timber", Color(0.40, 0.29, 0.18), 0.9)
	kit.add_material("valley_field", Color(0.74, 0.65, 0.33), 1.0)
	kit.add_material("valley_bark", Color(0.33, 0.24, 0.16), 0.95)
	kit.add_material("valley_leaves", Color(0.24, 0.40, 0.19), 0.95)
	kit.add_material("valley_leaves_dark", Color(0.16, 0.31, 0.15), 0.95)
	kit.add_material("valley_iron", Color(0.30, 0.31, 0.34), 0.5, 0.5)
	var glow := kit.add_material("valley_glow", Color(0.45, 0.85, 1.0), 0.3)
	glow.emission_enabled = true
	glow.emission = Color(0.40, 0.80, 1.0)
	glow.emission_energy_multiplier = 1.8
	if kit.out_root == "":
		ResourceSaver.save(glow, "%s/valley_glow.tres" % SceneKit.MAT_DIR, ResourceSaver.FLAG_CHANGE_PATH)


## A world-space checker ground (the sandbox's shader) in this district's colours.
static func _ground_mat(kit: SceneKit, mat_name: String, a: Color, b: Color, line: Color, cell: float) -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/ground_checker.gdshader")
	m.set_shader_parameter("color_a", Vector3(a.r, a.g, a.b))
	m.set_shader_parameter("color_b", Vector3(b.r, b.g, b.b))
	m.set_shader_parameter("line_color", Vector3(line.r, line.g, line.b))
	m.set_shader_parameter("cell_size", cell)
	if kit.out_root == "":
		ResourceSaver.save(m, "%s/%s.tres" % [SceneKit.MAT_DIR, mat_name], ResourceSaver.FLAG_CHANGE_PATH)
	kit.mats[mat_name] = m


## The material a layout element names: "grass" -> valley_grass, else a SceneKit palette entry
## ("stone", "wood_dark", "sack", ...).
static func _mat(kit: SceneKit, mat_name: String) -> Material:
	return kit.mats[_mat_key(kit, mat_name)]


## The kit.mats key of a layout material name ("stone" when it is unknown, after an error).
static func _mat_key(kit: SceneKit, mat_name: String) -> String:
	if kit.mats.has("valley_" + mat_name):
		return "valley_" + mat_name
	if kit.mats.has(mat_name):
		return mat_name
	push_error("valley: unknown material '%s'" % mat_name)
	return "stone"


# --------------------------------------------------------------------------- the geometry list

## Every element of the layout as plain records, assigned to a district:
##   "solids": {district, name, shape ("box"|"cyl"), xform (centre and rotation), size (box size;
##     cylinder: diameter, height, diameter), mat, layer (WORLD|BLOCKER), visible, scenery,
##     nav ("ground"|"obstacle"|"walkable"|"ramp")}
##   "visuals": {district, name, kind (MESH_KINDS), xform (with the scale), mat, scenery, shadow}
##   "nav_blocks": [Rect2] (x, z): areas the bake removes (the river)
static func collect(layout: Dictionary) -> Dictionary:
	var geo := {"solids": [], "visuals": [], "nav_blocks": [], "districts": layout.get("districts", [])}
	for g: Dictionary in layout.get("ground", []):
		var r := _rect(g)
		var centre := Vector3(r.get_center().x, -0.5, r.get_center().y)
		_solid(geo, g, str(g.name), "box", Transform3D(Basis(), centre), Vector3(r.size.x, 1.0, r.size.y),
			str(g.mat), LAYER_WORLD, false, "ground")
		_visual(geo, g, str(g.name), "plane", Transform3D(Basis.from_scale(Vector3(r.size.x, 1, r.size.y)),
			Vector3(r.get_center().x, 0.0, r.get_center().y)), str(g.mat), false, false)
	for c: Dictionary in layout.get("cliffs", []):
		var r := _rect(c)
		var h := float(c.get("h", 30.0))
		_solid(geo, c, str(c.name), "box", Transform3D(Basis(), Vector3(r.get_center().x, h * 0.5, r.get_center().y)),
			Vector3(r.size.x, h, r.size.y), str(c.get("mat", "cliff")), LAYER_WORLD, true, "obstacle")
	for w: Dictionary in layout.get("walls", []):
		_segment(geo, w, str(w.get("mat", "stone")), LAYER_WORLD, true)
	for b: Dictionary in layout.get("blockers", []):
		_segment(geo, b, "stone", LAYER_BLOCKER, false)
	for wt: Dictionary in layout.get("water", []):
		var r := _rect(wt)
		(geo.nav_blocks as Array).append(r)
		_visual(geo, wt, str(wt.name), "plane", Transform3D(Basis.from_scale(Vector3(r.size.x, 1, r.size.y)),
			Vector3(r.get_center().x, 0.05, r.get_center().y)), "water", false, false)
	for rd: Dictionary in layout.get("roads", []):
		var pts: Array = rd.points
		var w := float(rd.get("w", 12.0))
		for i in pts.size() - 1:
			var a := Vector3(float(pts[i][0]), 0.0, float(pts[i][1]))
			var b := Vector3(float(pts[i + 1][0]), 0.0, float(pts[i + 1][1]))
			var mid := (a + b) * 0.5
			var length := a.distance_to(b) + w * 0.5
			var yaw := _yaw_of(b - a)
			var e := {"name": rd.name, "district": rd.get("district", ""), "_centre": mid}
			_visual(geo, e, "%s_%d" % [rd.name, i], "plane", Transform3D(Basis(Vector3.UP, yaw)
				* Basis.from_scale(Vector3(w, 1, length)), mid + Vector3.UP * 0.02), str(rd.get("mat", "road")), false, false)
	for hs: Dictionary in layout.get("houses", []):
		var pos := Vector3(float(hs.pos[0]), 0.0, float(hs.pos[1]))
		var size := Vector3(float(hs.size[0]), float(hs.h), float(hs.size[1]))
		var basis := Basis(Vector3.UP, deg_to_rad(float(hs.get("yaw", 0.0))))
		_solid(geo, hs, str(hs.name), "box", Transform3D(basis, pos + Vector3.UP * size.y * 0.5), size,
			str(hs.get("mat", "plaster")), LAYER_WORLD, true, "obstacle")
		_roof(geo, hs, str(hs.name), basis, pos + Vector3.UP * size.y, Vector2(size.x, size.z),
			float(hs.get("roof_h", 2.5)), str(hs.get("roof_mat", "thatch")))
	for p: Dictionary in layout.get("platforms", []):
		_platform(geo, p)
	for lm: Dictionary in layout.get("landmarks", []):
		var size := _v3(lm.size)
		var basis := Basis(Vector3.UP, deg_to_rad(float(lm.get("yaw", 0.0))))
		var base := _v3(lm.pos)
		var shape := str(lm.get("shape", "box"))
		_solid(geo, lm, str(lm.name), shape, Transform3D(basis, base + Vector3.UP * size.y * 0.5), size,
			str(lm.get("mat", "stone")), LAYER_WORLD, true, "obstacle")
		if lm.has("roof_h"):
			_roof(geo, lm, str(lm.name), basis, base + Vector3.UP * size.y, Vector2(size.x, size.z),
				float(lm.roof_h), str(lm.get("roof_mat", lm.get("mat", "sack"))))
	for dc: Dictionary in layout.get("decor", []):
		var size := _v3(dc.size)
		var basis := Basis(Vector3.UP, deg_to_rad(float(dc.get("yaw", 0.0))))
		var kind := str(dc.get("shape", "box"))
		var origin := _v3(dc.pos) + (Vector3.ZERO if kind == "plane" else Vector3.UP * size.y * 0.5)
		_visual(geo, dc, str(dc.name), kind, Transform3D(basis * Basis.from_scale(size), origin),
			str(dc.get("mat", "stone")), false, kind != "plane")
	if layout.has("arena"):
		_arena_ring(geo, layout.arena)
	var trees: Array = layout.get("scenery_trees", [])
	for i in trees.size():
		_tree(geo, i, trees[i])
	return geo


static func _rect(e: Dictionary) -> Rect2:
	var mn := Vector2(float(e.min[0]), float(e.min[1]))
	var mx := Vector2(float(e.max[0]), float(e.max[1]))
	return Rect2(mn, mx - mn)


static func _v3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Godot yaw of a horizontal direction (forward = -Z).
static func _yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


static func _solid(geo: Dictionary, e: Dictionary, solid_name: String, shape: String, xform: Transform3D,
		size: Vector3, mat: String, layer: int, visible: bool, nav: String, scenery := false) -> void:
	(geo.solids as Array).append({"district": _district_of(geo, e, xform.origin), "name": solid_name,
		"shape": shape, "xform": xform, "size": size, "mat": mat, "layer": layer, "visible": visible,
		"nav": nav, "scenery": scenery})


static func _visual(geo: Dictionary, e: Dictionary, visual_name: String, kind: String, xform: Transform3D,
		mat: String, scenery: bool, shadow: bool) -> void:
	var at: Vector3 = e.get("_centre", xform.origin)
	(geo.visuals as Array).append({"district": _district_of(geo, e, at), "name": visual_name, "kind": kind,
		"xform": xform, "mat": mat, "scenery": scenery, "shadow": shadow})


## The element's "district", else the first walkable district whose rectangle holds `at` (x, z),
## else "hills".
static func _district_of(geo: Dictionary, e: Dictionary, at: Vector3) -> String:
	if str(e.get("district", "")) != "":
		return str(e.district)
	for d: Dictionary in geo.districts:
		if not bool(d.get("walkable", true)):
			continue
		if at.x >= float(d.min[0]) and at.x <= float(d.max[0]) and at.z >= float(d.min[1]) and at.z <= float(d.max[1]):
			return str(d.id)
	return "hills"


## A wall or blocker segment: a box from "from" to "to", thickness "t", height "h".
static func _segment(geo: Dictionary, e: Dictionary, mat: String, layer: int, visible: bool) -> void:
	var a := Vector3(float(e.from[0]), 0.0, float(e.from[1]))
	var b := Vector3(float(e.to[0]), 0.0, float(e.to[1]))
	var h := float(e.get("h", 5.0))
	var t := float(e.get("t", 1.0))
	var basis := Basis(Vector3.UP, _yaw_of(b - a))
	_solid(geo, e, str(e.name), "box", Transform3D(basis, (a + b) * 0.5 + Vector3.UP * h * 0.5),
		Vector3(t, h, a.distance_to(b)), mat, layer, visible, "obstacle")


## A gable roof (a prism) on top of a box of footprint `fp` (x, z), its ridge along the longer side.
static func _roof(geo: Dictionary, e: Dictionary, roof_name: String, basis: Basis, top: Vector3, fp: Vector2,
		h: float, mat: String) -> void:
	var b := basis
	var across := fp.x + 0.6
	var along := fp.y + 0.6
	if fp.x > fp.y:
		b = basis * Basis(Vector3.UP, PI * 0.5)
		across = fp.y + 0.6
		along = fp.x + 0.6
	_visual(geo, e, roof_name + "_roof", "prism", Transform3D(b * Basis.from_scale(Vector3(across, h, along)),
		top + Vector3.UP * h * 0.5), mat, false, true)


## A platform (walkable top) and its ramp (a pitched box from the ground to the top).
static func _platform(geo: Dictionary, p: Dictionary) -> void:
	var pos := Vector3(float(p.pos[0]), 0.0, float(p.pos[1]))
	var h := float(p.h)
	var size := Vector3(float(p.size[0]), h, float(p.size[1]))
	var basis := Basis(Vector3.UP, deg_to_rad(float(p.get("yaw", 0.0))))
	var mat := str(p.get("mat", "stone"))
	_solid(geo, p, str(p.name), "box", Transform3D(basis, pos + Vector3.UP * h * 0.5), size, mat,
		LAYER_WORLD, true, "walkable")
	if not p.has("ramp"):
		return
	var ramp: Dictionary = p.ramp
	var side := str(ramp.get("side", "south"))
	var length := float(ramp.get("length", 14.0))
	var width := float(ramp.get("width", 6.0))
	var offset := float(ramp.get("offset", 0.0))
	# Outward direction of the side (in the platform's frame) and the half-depth of that side.
	var out := {"north": Vector3(0, 0, -1), "south": Vector3(0, 0, 1), "west": Vector3(-1, 0, 0),
		"east": Vector3(1, 0, 0)}[side] as Vector3
	var half := size.z * 0.5 if side in ["north", "south"] else size.x * 0.5
	var lateral := Vector3(-out.z, 0, out.x)   # along the side
	var slope := atan2(h, length)
	var thickness := 1.0
	var run := length / cos(slope)
	# The ramp's top surface runs from the platform edge (height h) out to `length` (height 0).
	var top_mid := pos + basis * (out * (half + length * 0.5) + lateral * offset) + Vector3.UP * (h * 0.5)
	var dir := basis * out                     # downhill, horizontal
	var yaw := _yaw_of(-dir)                   # the ramp's local -Z points uphill
	var rb := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, slope)   # tilt the uphill end up
	var centre := top_mid - rb.y * (thickness * 0.5)
	_solid(geo, p, str(p.name) + "_ramp", "box", Transform3D(rb, centre), Vector3(width, thickness, run), mat,
		LAYER_WORLD, true, "ramp")


## The Kingsfall arena ring: wall segments on a circle, open at the entrance (north, -Z).
static func _arena_ring(geo: Dictionary, a: Dictionary) -> void:
	var c := Vector3(float(a.center[0]), 0.0, float(a.center[1]))
	var r := float(a.wall_radius)
	var gap := asin(float(a.entrance_half_width) / r)
	var start := -PI * 0.5 + gap
	var span := TAU - 2.0 * gap
	var n := int(a.get("segments", 27))
	var h := float(a.wall_h)
	var t := float(a.wall_t)
	for i in n:
		var a0 := start + span * float(i) / n
		var a1 := start + span * float(i + 1) / n
		var p0 := c + Vector3(cos(a0), 0, sin(a0)) * r
		var p1 := c + Vector3(cos(a1), 0, sin(a1)) * r
		var e := {"name": "arena_wall_%02d" % i, "from": [p0.x, p0.z], "to": [p1.x, p1.z], "h": h, "t": t,
			"district": str(a.get("district", "kingsfall"))}
		# Extend each chord a little so neighbouring segments overlap at the joints.
		var dir := (p1 - p0).normalized()
		e.from = [p0.x - dir.x * t * 0.5, p0.z - dir.z * t * 0.5]
		e.to = [p1.x + dir.x * t * 0.5, p1.z + dir.z * t * 0.5]
		_segment(geo, e, str(a.get("mat", "stone_dark")), LAYER_WORLD, true)


## A scenery tree [x, z, trunk radius]: a trunk (WORLD collision, a navigation obstacle) and two
## needle cones (visual only, scenery).
static func _tree(geo: Dictionary, i: int, t: Array) -> void:
	var x := float(t[0])
	var z := float(t[1])
	var r := float(t[2])
	var h := 7.0 + 6.0 * r
	var e := {"name": "tree_%03d" % i}
	_solid(geo, e, "Tree%03d" % i, "cyl", Transform3D(Basis(), Vector3(x, h * 0.5, z)), Vector3(r * 2, h, r * 2),
		"bark", LAYER_WORLD, true, "obstacle", true)
	var crown := 2.4 + 2.6 * r
	_visual(geo, e, "Tree%03d_a" % i, "cone", Transform3D(Basis.from_scale(Vector3(crown * 2, h * 0.55, crown * 2)),
		Vector3(x, h * 0.3 + h * 0.275, z)), "leaves_dark" if i % 3 != 0 else "leaves", true, true)
	_visual(geo, e, "Tree%03d_b" % i, "cone", Transform3D(Basis.from_scale(Vector3(crown * 1.4, h * 0.4, crown * 1.4)),
		Vector3(x, h * 0.62 + h * 0.2, z)), "leaves_dark", true, true)


# --------------------------------------------------------------------------- district sub-scenes

## One district: Collision (WORLD), Blockers, Visual and Scenery (MultiMeshes), all in level space.
static func build_district(kit: SceneKit, id: String, geo: Dictionary) -> Node:
	var root := Node3D.new()
	root.name = id
	var world := StaticBody3D.new()
	world.name = "Collision"
	world.collision_layer = LAYER_WORLD
	world.collision_mask = 0
	var blockers := StaticBody3D.new()
	blockers.name = "Blockers"
	blockers.collision_layer = LAYER_BLOCKER
	blockers.collision_mask = 0
	var shapes := {}
	var buckets := {}       # "<kind>|<mat>|<scenery>|<shadow>" -> Array[Transform3D]
	var used := {}
	for s: Dictionary in geo.solids:
		if s.district != id:
			continue
		var cs := CollisionShape3D.new()
		cs.name = _unique(used, str(s.name).to_pascal_case())
		var basis: Basis = (s.xform as Transform3D).basis
		cs.transform = Transform3D(basis.orthonormalized(), (s.xform as Transform3D).origin)
		cs.shape = _shape(shapes, s.shape, s.size)
		(blockers if int(s.layer) == LAYER_BLOCKER else world).add_child(cs)
		if s.visible:
			var kind := "cyl" if s.shape == "cyl" else "box"
			_bucket(buckets, kind, str(s.mat), bool(s.scenery), true).append(
				Transform3D(basis.orthonormalized() * Basis.from_scale(s.size), (s.xform as Transform3D).origin))
	for v: Dictionary in geo.visuals:
		if v.district != id:
			continue
		_bucket(buckets, str(v.kind), str(v.mat), bool(v.scenery), bool(v.shadow)).append(v.xform)
	root.add_child(world)
	if blockers.get_child_count() > 0:
		root.add_child(blockers)
	else:
		blockers.free()
	var visual := kit.n3("Visual")
	var scenery := kit.n3("Scenery")
	var keys := buckets.keys()
	keys.sort()
	var meshes := _unit_meshes()
	for key: String in keys:
		var parts := key.split("|")
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%s" % [parts[1].to_pascal_case(), parts[0].to_pascal_case()]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[parts[0]]
		var list: Array = buckets[key]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		mmi.multimesh = mm
		mmi.material_override = _mat(kit, parts[1])
		if parts[3] == "0":
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if parts[2] == "1":
			mmi.visibility_range_end = SCENERY_VISIBILITY_END_M
			mmi.add_to_group(SCENERY_GROUP, true)
			scenery.add_child(mmi)
		else:
			visual.add_child(mmi)
	root.add_child(visual)
	if scenery.get_child_count() > 0:
		root.add_child(scenery)
	else:
		scenery.free()
	return root


static func _bucket(buckets: Dictionary, kind: String, mat: String, scenery: bool, shadow: bool) -> Array:
	var key := "%s|%s|%d|%d" % [kind, mat, 1 if scenery else 0, 1 if shadow else 0]
	if not buckets.has(key):
		buckets[key] = []
	return buckets[key]


static func _unique(used: Dictionary, base: String) -> String:
	var n := base
	var i := 2
	while used.has(n):
		n = "%s%d" % [base, i]
		i += 1
	used[n] = true
	return n


## A shared collision shape for (shape, size): boxes by size, cylinders by radius and height.
static func _shape(cache: Dictionary, kind: String, size: Vector3) -> Shape3D:
	var key := "%s %.3f %.3f %.3f" % [kind, size.x, size.y, size.z]
	if cache.has(key):
		return cache[key]
	var s: Shape3D
	if kind == "cyl":
		var c := CylinderShape3D.new()
		c.radius = size.x * 0.5
		c.height = size.y
		s = c
	else:
		var b := BoxShape3D.new()
		b.size = size
		s = b
	cache[key] = s
	return s


static func _unit_meshes() -> Dictionary:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 10
	cyl.rings = 1
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 8
	cone.rings = 1
	var prism := PrismMesh.new()
	prism.size = Vector3.ONE
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	return {"box": box, "cyl": cyl, "cone": cone, "prism": prism, "plane": plane}


# --------------------------------------------------------------------------- the root scene

static func build_root(kit: SceneKit, layout: Dictionary, district_ids: Array) -> Node:
	var player: Node3D = kit.instance(GIANT)
	if player == null:
		push_error("valley: build the player scene first")
		return null
	var root := Node3D.new()
	root.name = "Valley"
	kit.scripted(root, S_LEVEL, {"level_id": LEVEL_ID})
	_add_environment(root)

	var districts := kit.n3("Districts")
	for id: String in district_ids:
		var d: Node3D = kit.instance(DISTRICT_DIR + id + ".tscn")
		if d != null:
			d.name = id
			districts.add_child(d)
	root.add_child(districts)

	var props := kit.n3("Props")
	for p: Dictionary in layout.get("props", []):
		var n := _prop(kit, p)
		if n != null:
			props.add_child(n)
	root.add_child(props)
	# Nodes added under an instanced prop (its per-layer links) are saved only when the scene's
	# root owns them (SceneKit.own does not descend into instances).
	for n in props.get_children():
		for child in n.get_children():
			if child.has_meta("valley_added"):
				child.remove_meta("valley_added")
				child.owner = root

	var shrines := kit.n3("Shrines")
	for s: Dictionary in layout.get("shrines", []):
		var sh: Node3D = kit.instance(SHRINE)
		if sh == null:
			continue
		sh.name = str(s.world_id).validate_node_name()
		sh.set("world_id", str(s.world_id))
		sh.set("shrine_id", str(s.record))
		sh.position = _v3(s.pos)
		sh.rotation.y = deg_to_rad(float(s.get("yaw", 0.0)))
		shrines.add_child(sh)
	root.add_child(shrines)

	var waystones := kit.n3("Waystones")
	for w: Dictionary in layout.get("waystones", []):
		waystones.add_child(_waystone(kit, w))
	root.add_child(waystones)

	var dummies := kit.n3("Dummies")
	for d: Dictionary in layout.get("dummies", []):
		var dm: Node3D = kit.instance(DUMMY)
		if dm == null:
			continue
		dm.name = str(d.entity_id).validate_node_name()
		dm.set("entity_id", str(d.entity_id))
		dm.position = _v3(d.pos)
		dm.rotation.y = deg_to_rad(float(d.get("yaw", 0.0)))
		dummies.add_child(dm)
	root.add_child(dummies)

	root.add_child(_markers(kit, layout))
	root.add_child(_triggers(kit, layout))
	var kingsfall := _kingsfall(kit, layout.get("arena", {}))
	root.add_child(kingsfall)

	# Navigation: baked here from the layout's elements and the solid shapes placed above.
	var extra: Array = []
	for container: Node in [props, shrines, waystones, dummies, kingsfall]:
		_collect_static_shapes(container, root, extra)
	var nav := kit.n3("Navigation")
	var geo := collect(layout)
	var src := nav_source(geo, extra)
	for spec: Dictionary in NAV_LAYERS:
		var region := NavigationRegion3D.new()
		region.name = str(spec.node)
		region.navigation_layers = int(spec.layer)
		region.use_edge_connections = false
		var nm := bake_layer(spec, src)
		var natural := surface_offset(nm)
		if absf(natural - EXPECTED_SURFACE_OFFSET) > 0.01:
			push_warning("valley: %s navmesh sits %.2f m above flat ground (expected %.2f)" % [spec.node,
				natural, EXPECTED_SURFACE_OFFSET])
		region.position.y = float(spec.above) - natural
		var path := kit.output_path(NAV_DIR + str(spec.file))
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var err := ResourceSaver.save(nm, path, ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			push_error("valley: could not save %s (error %d)" % [path, err])
			region.free()
			continue
		print("valley: %s navmesh: %d polygons, %d vertices, %d bytes, region y %.2f" % [spec.node,
			nm.get_polygon_count(), nm.get_vertices().size(), FileAccess.get_file_as_bytes(path).size(),
			region.position.y])
		# The file, not a copy: the scene references assets/nav/*.res (loaded fresh from disk).
		region.navigation_mesh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as NavigationMesh
		nav.add_child(region)
	root.add_child(nav)
	root.move_child(nav, 3)

	var signs := kit.n3("Signs")
	var sign_names := {}
	for s: Dictionary in layout.get("signs", []):
		var label := kit.sign(str(s.text), _v3(s.pos))
		label.name = _unique(sign_names, "Sign" + str(s.text).get_slice(" ", 0).to_pascal_case())
		label.visibility_range_end = 60.0
		signs.add_child(label)
	root.add_child(signs)

	var start: Dictionary = layout.get("player", {"pos": [0, 0.05, 0], "yaw": 0})
	var spawns := kit.n3("Spawns")
	var spawn := kit.marker("PlayerSpawn", _v3(start.pos))
	spawn.rotation.y = deg_to_rad(float(start.get("yaw", 0.0)))
	spawns.add_child(spawn)
	root.add_child(spawns)
	root.add_child(kit.n3("Spawned"))
	player.name = "Player"
	player.position = _v3(start.pos)
	player.rotation.y = deg_to_rad(float(start.get("yaw", 0.0)))
	root.add_child(player)
	var director := Node.new()
	director.name = "EncounterDirector"
	kit.scripted(director, S_DIRECTOR)
	root.add_child(director)
	var debris := kit.n3("DebrisPool")
	kit.scripted(debris, S_DEBRIS)
	root.add_child(debris)
	return root


static func _add_environment(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.70)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = SKY
	env.fog_depth_begin = FOG_BEGIN_M
	env.fog_depth_end = FOG_END_M
	env.fog_depth_curve = 1.0
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	root.add_child(sun)


## A placed prop: the scene, its world id and the layout's "set" properties (only those the node
## has), and per-layer nav links across it when the layout asks ("nav_link": {"half_m"}). A scene
## or a record that does not exist yet (the forge, P12's items) is skipped with a note.
static func _prop(kit: SceneKit, p: Dictionary) -> Node3D:
	var key := str(p.scene)
	var path := str(PROP_SCENES.get(key, ""))
	if path == "":
		push_error("valley: unknown prop scene key '%s'" % key)
		return null
	for rec_id: Variant in p.get("requires_records", []):
		if GameData.get_record(str(rec_id)).is_empty():
			print("valley: skipped %s (record %s not present yet)" % [p.world_id, rec_id])
			return null
	var n: Node3D = kit.instance(path)
	if n == null:
		print("valley: skipped %s (%s not built yet)" % [p.world_id, path])
		return null
	n.name = str(p.world_id).validate_node_name()
	n.set("world_id", str(p.world_id))
	var sets: Dictionary = p.get("set", {})
	for k: String in sets:
		if k in n:
			n.set(k, _coerce(n.get(k), sets[k]))
		else:
			print("valley: %s has no property '%s' yet (skipped)" % [p.world_id, k])
	n.position = _v3(p.pos)
	n.rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
	if p.has("nav_link"):
		var half := float(p.nav_link.get("half_m", 3.0))
		for spec: Dictionary in NAV_LAYERS:
			var link := NavigationLink3D.new()
			link.name = "NavLink" + str(spec.node)
			link.start_position = Vector3(0, float(spec.above), half)
			link.end_position = Vector3(0, float(spec.above), -half)
			link.bidirectional = true
			link.navigation_layers = int(spec.layer)
			link.enabled = false
			link.set_meta("valley_added", true)
			n.add_child(link)
	return n


## A JSON value converted to the type of the property it is written into.
static func _coerce(current: Variant, v: Variant) -> Variant:
	match typeof(current):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return float(v)
		TYPE_STRING:
			return str(v)
		TYPE_PACKED_STRING_ARRAY:
			return PackedStringArray(v)
	return v


## A waystone (P06): the marker (the respawn point, facing along the road), its stone (WORLD) at
## the layout's local "stone" offset, and the Glow shown while it is open.
static func _waystone(kit: SceneKit, w: Dictionary) -> Node3D:
	var m := kit.scripted(kit.marker(str(w.id).validate_node_name(), _v3(w.pos)), S_WAYSTONE, {
		"checkpoint_id": str(w.id), "radius_m": float(w.get("radius", 10.0)),
		"requires_flags": PackedStringArray(w.get("requires_flags", []))}) as Node3D
	m.position.y = maxf(m.position.y, 0.05)
	m.rotation.y = deg_to_rad(float(w.get("yaw", 0.0)))
	var off := Vector3(float(w.stone[0]), 0.0, float(w.stone[1]))
	m.add_child(kit.static_box("Stone", Vector3(1.2, 4.0, 1.2), off + Vector3(0, 2.0, 0), "stone_dark"))
	m.add_child(kit.box("Cap", Vector3(1.6, 0.4, 1.6), off + Vector3(0, 4.2, 0), "stone"))
	var glow := kit.box("Glow", Vector3(0.6, 0.6, 0.6), off + Vector3(0, 4.8, 0), "valley_glow")
	glow.visible = false
	m.add_child(glow)
	return m


## Markers/<Kind>/<marker> (LevelMarker) and Markers/Patrol/<route>/<n>.
static func _markers(kit: SceneKit, layout: Dictionary) -> Node3D:
	var markers := kit.n3("Markers")
	for e: Dictionary in layout.get("markers", []):
		var kind: Array = MARKER_KINDS.get(str(e.kind), MARKER_KINDS.objective)
		var folder := markers.get_node_or_null(NodePath(str(kind[1]))) as Node3D
		if folder == null:
			folder = kit.n3(str(kind[1]))
			markers.add_child(folder)
		folder.add_child(kit.scripted(kit.marker(str(e.id).validate_node_name(), _v3(e.pos)), S_MARKER,
			{"marker_id": str(e.id), "kind": int(kind[0]), "faction": str(e.get("faction", ""))}))
	var patrols := kit.n3("Patrol")
	for r: Dictionary in layout.get("patrols", []):
		var route := kit.n3(str(r.id).validate_node_name())
		route.set_meta("route_id", str(r.id))
		var pts: Array = r.points
		for i in pts.size():
			route.add_child(kit.marker(str(i + 1), _v3(pts[i])))
		patrols.add_child(route)
	markers.add_child(patrols)
	return markers


## Triggers/<area> (AreaTrigger): a cylinder or a box standing on the ground at "pos".
static func _triggers(kit: SceneKit, layout: Dictionary) -> Node3D:
	var triggers := kit.n3("Triggers")
	for t: Dictionary in layout.get("triggers", []):
		var a := Area3D.new()
		a.name = str(t.id).validate_node_name()
		a.position = _v3(t.pos)
		a.rotation.y = deg_to_rad(float(t.get("yaw", 0.0)))
		kit.scripted(a, S_TRIGGER, {"area_id": str(t.id), "once": bool(t.get("once", false))})
		a.collision_layer = 0
		a.collision_mask = SceneKit.L_ACTORS
		a.monitoring = true
		a.monitorable = false
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		if str(t.get("shape", "box")) == "cylinder":
			var cyl := CylinderShape3D.new()
			cyl.radius = float(t.r)
			cyl.height = float(t.h)
			cs.shape = cyl
			cs.position = Vector3(0, cyl.height * 0.5, 0)
		else:
			var size := _v3(t.size)
			cs.shape = kit.box_shape(size)
			cs.position = Vector3(0, size.y * 0.5, 0)
		a.add_child(cs)
		triggers.add_child(a)
	return triggers


## Kingsfall/ArenaGate (a StaticBody3D on WORLD, hidden, its collision disabled: P11a closes it on
## valley.area.arena_engage) and Kingsfall/Pillars/Pillar1..4 (WORLD boxes at the pillar radius).
static func _kingsfall(kit: SceneKit, a: Dictionary) -> Node3D:
	var kf := kit.n3("Kingsfall")
	if a.is_empty():
		return kf
	var g: Dictionary = a.gate
	var gsize := _v3(g.size)
	var gate := StaticBody3D.new()
	gate.name = "ArenaGate"
	gate.position = _v3(g.pos)
	gate.collision_layer = LAYER_WORLD
	gate.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = kit.box_shape(gsize)
	cs.position = Vector3(0, gsize.y * 0.5, 0)
	cs.disabled = true
	gate.add_child(cs)
	var bars := kit.n3("Bars")
	var count := 8
	for i in count:
		var x := -gsize.x * 0.5 + 0.6 + (gsize.x - 1.2) * float(i) / (count - 1)
		bars.add_child(kit.box("Bar%d" % i, Vector3(0.35, gsize.y, 0.35), Vector3(x, gsize.y * 0.5, 0), "valley_iron"))
	for j in 3:
		bars.add_child(kit.box("Cross%d" % j, Vector3(gsize.x, 0.3, 0.45), Vector3(0, 2.5 + 5.0 * j, 0), "valley_iron"))
	gate.add_child(bars)
	gate.visible = false
	kf.add_child(gate)
	var pillars := kit.n3("Pillars")
	var c := Vector3(float(a.center[0]), 0.0, float(a.center[1]))
	var psize := _v3(a.pillar_size)
	var angles: Array = a.pillar_angles
	for i in angles.size():
		var ang := deg_to_rad(float(angles[i]))
		var pos := c + Vector3(cos(ang), 0, sin(ang)) * float(a.pillar_radius)
		pillars.add_child(kit.static_box("Pillar%d" % (i + 1), psize, pos + Vector3.UP * psize.y * 0.5,
			_mat_key(kit, str(a.get("pillar_mat", "stone")))))
	kf.add_child(pillars)
	return kf


# --------------------------------------------------------------------------- navigation

## Every enabled CollisionShape3D of a static body below `node` (props, shrines, waystones,
## dummies, pillars) as {shape, xform (level space), size}: navigation obstacles.
static func _collect_static_shapes(node: Node, root: Node, out: Array) -> void:
	for child in node.get_children():
		if child is CollisionShape3D and child.get_parent() is StaticBody3D and not (child as CollisionShape3D).disabled:
			var cs := child as CollisionShape3D
			var xf := _rel_xform(cs, root)
			var s := cs.shape
			if s is BoxShape3D:
				out.append({"shape": "box", "xform": xf, "size": (s as BoxShape3D).size})
			elif s is CylinderShape3D:
				var cy := s as CylinderShape3D
				out.append({"shape": "cyl", "xform": xf, "size": Vector3(cy.radius * 2, cy.height, cy.radius * 2)})
			elif s is CapsuleShape3D:
				var cp := s as CapsuleShape3D
				out.append({"shape": "cyl", "xform": xf, "size": Vector3(cp.radius * 2, cp.height, cp.radius * 2)})
			elif s != null:
				var aabb := s.get_debug_mesh().get_aabb()
				out.append({"shape": "box", "xform": xf * Transform3D(Basis(), aabb.get_center()), "size": aabb.size})
		_collect_static_shapes(child, root, out)


## The transform of `node` relative to its ancestor `root` (nodes not in a tree).
static func _rel_xform(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## The navigation source of the whole Valley (shared by the four bakes): ground tops, platforms
## and ramps walkable; cliffs, walls, houses, blockers, landmarks, tree trunks and the placed
## props' shapes as obstacles (sides only, plus a projected obstruction over their footprint, so
## no navmesh island is left inside or on top of them); the river removed.
static func nav_source(geo: Dictionary, extra: Array) -> NavigationMeshSourceGeometryData3D:
	var src := NavigationMeshSourceGeometryData3D.new()
	for s: Dictionary in geo.solids:
		match str(s.nav):
			"ground":
				src.add_faces(solid_faces(s, true), Transform3D.IDENTITY)
			"walkable":
				src.add_faces(solid_faces(s, true), Transform3D.IDENTITY)
				var top := (s.xform as Transform3D).origin.y + (s.size as Vector3).y * 0.5
				src.add_projected_obstruction(footprint(s), -1.0, top - 0.5, false)
			"ramp":
				src.add_faces(solid_faces(s, true), Transform3D.IDENTITY)
				src.add_projected_obstruction(footprint(s), -1.0, 1.1, true)
			_:
				_add_obstacle(src, s)
	for s: Dictionary in extra:
		_add_obstacle(src, s)
	for r: Rect2 in geo.nav_blocks:
		src.add_projected_obstruction(PackedVector3Array([Vector3(r.position.x, 0, r.position.y),
			Vector3(r.end.x, 0, r.position.y), Vector3(r.end.x, 0, r.end.y), Vector3(r.position.x, 0, r.end.y)]),
			-1.0, 3.0, false)
	return src


static func _add_obstacle(src: NavigationMeshSourceGeometryData3D, s: Dictionary) -> void:
	src.add_faces(solid_faces(s, false), Transform3D.IDENTITY)
	var xf: Transform3D = s.xform
	var half := (s.size as Vector3).y * 0.5
	var base := xf.origin.y - half
	src.add_projected_obstruction(footprint(s), base - 0.25, (s.size as Vector3).y + 0.25, false)


## Bakes one layer's navmesh (NAV_LAYERS entry) from `src`, offline.
static func bake_layer(spec: Dictionary, src: NavigationMeshSourceGeometryData3D) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.agent_radius = float(spec.radius)
	nm.agent_height = float(spec.height)
	nm.agent_max_climb = float(spec.climb)
	nm.agent_max_slope = MAX_SLOPE_DEG
	nm.cell_size = float(spec.cell)
	nm.cell_height = CELL_HEIGHT
	nm.region_min_size = REGION_MIN_SIZE
	nm.filter_baking_aabb = BAKE_AABB
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	return nm


## How high above a flat walking surface the bake put the navmesh: the most common height of the
## vertices below 1.5 m (the ground), in metres.
static func surface_offset(nm: NavigationMesh) -> float:
	var counts := {}
	for v in nm.get_vertices():
		if v.y < 1.5:
			var k := snappedf(v.y, 0.05)
			counts[k] = int(counts.get(k, 0)) + 1
	var best := EXPECTED_SURFACE_OFFSET
	var best_n := -1
	for k: float in counts:
		if int(counts[k]) > best_n:
			best_n = counts[k]
			best = k
	return best


## The triangles of a box or cylinder solid in level space, wound as Godot's front faces
## (clockwise seen from outside, the convention NavigationMeshSourceGeometryData3D.add_faces
## expects); `top` false leaves out the top face (an obstacle nothing should stand on).
static func solid_faces(s: Dictionary, top: bool) -> PackedVector3Array:
	var xf: Transform3D = s.xform
	var size: Vector3 = s.size
	var b := xf.basis.orthonormalized()
	if str(s.shape) == "cyl":
		return cylinder_faces(xf.origin, size.x * 0.5, size.y, top)
	var h := size * 0.5
	var local := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var c: Array[Vector3] = []
	for p: Vector3 in local:
		c.append(xf.origin + b * p)
	var quads := [[4, 5, 6, 7], [3, 2, 1, 0], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
	var out := PackedVector3Array()
	for i in quads.size():
		if i == 0 and not top:
			continue
		var q: Array = quads[i]
		out.append_array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]])
	return out


const CYL_SIDES := 8


static func cylinder_faces(centre: Vector3, r: float, h: float, top: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	var y0 := centre.y - h * 0.5
	var y1 := centre.y + h * 0.5
	for i in CYL_SIDES:
		var a := TAU * float(i) / CYL_SIDES
		var b := TAU * float(i + 1) / CYL_SIDES
		var pa := Vector3(centre.x + cos(a) * r, 0, centre.z + sin(a) * r)
		var pb := Vector3(centre.x + cos(b) * r, 0, centre.z + sin(b) * r)
		var a0 := Vector3(pa.x, y0, pa.z)
		var b0 := Vector3(pb.x, y0, pb.z)
		var a1 := Vector3(pa.x, y1, pa.z)
		var b1 := Vector3(pb.x, y1, pb.z)
		out.append_array([a0, b0, b1, a0, b1, a1])
		if top:
			out.append_array([Vector3(centre.x, y1, centre.z), a1, b1])
	return out


## The solid's footprint on the ground plane (a convex polygon: the hull of its projected corners).
static func footprint(s: Dictionary) -> PackedVector3Array:
	var xf: Transform3D = s.xform
	var size: Vector3 = s.size
	var pts: Array[Vector2] = []
	if str(s.shape) == "cyl":
		for i in CYL_SIDES:
			var a := TAU * float(i) / CYL_SIDES
			pts.append(Vector2(xf.origin.x + cos(a) * size.x * 0.5, xf.origin.z + sin(a) * size.x * 0.5))
	else:
		var b := xf.basis.orthonormalized()
		var h := size * 0.5
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var p := xf.origin + b * Vector3(h.x * sx, h.y * sy, h.z * sz)
					pts.append(Vector2(p.x, p.z))
	var hull := Geometry2D.convex_hull(PackedVector2Array(pts))
	var out := PackedVector3Array()
	for i in hull.size() - 1:   # convex_hull repeats the first point at the end
		out.append(Vector3(hull[i].x, 0, hull[i].y))
	return out

extends RefCounted
## Element kind "arena" (P36; plan M6-M9 §2.10, §5.13): a boss's arena in the world - at `pos` (the
## arena's centre) its arena node with `inner_radius`, the AreaTrigger that begins the engagement
## (`engage_area` id, `engage` {"at": [x, z], "size": [w, h, d], "yaw"}) and, with `gate`
## ({"at", "size", "yaw"}), the gate BossArena closes behind the giant (ArenaGate: a StaticBody3D on the
## world layer with its Shape and bars, shown and solid only while the fight is engaged). Styles:
##   battle  FortBattle (scripts/world/fort_battle.gd: a BattleBoss) - `battle_id`, `battle_name`,
##           `phases` ([{"id", "name", "below", "encounters"}]), `engines` (world ids in the aggregate),
##           `commander_id`, `guard_formation`, `defeated_flag`, `peace_condition`, `settled_flag`,
##           `faction`, `open_flag`: Fort Aldmere's Iron Regiment, the inner portcullis behind the giant;
##   moot    MootArena (scripts/world/moot_arena.gd: a BossArena) - `boss_id`, `encounter_id`,
##           `defeated_flag`, `settled_flag`, `faction`, `empty_flag`: Harrok's ring, no gate.
## Its chunk's props sub-scene holds it; the index lists the engage trigger as an area.

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const S_TRIGGER := "res://scripts/world/area_trigger.gd"
const SCRIPTS := {"battle": "res://scripts/world/fort_battle.gd", "moot": "res://scripts/world/moot_arena.gd"}
## The arena script's exports an element may set (by style).
const KEYS := {
	"battle": ["battle_id", "battle_name", "phases", "engines", "commander_id", "guard_formation", "defeated_flag",
		"peace_condition", "settled_flag", "faction", "open_flag", "disengage_s", "disengage_margin_m"],
	"moot": ["boss_id", "encounter_id", "defeated_flag", "settled_flag", "faction", "empty_flag", "disengage_s",
		"disengage_margin_m"],
}


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func style_of(el: Dictionary) -> String:
	var s := str(el.get("style", "moot"))
	return s if SCRIPTS.has(s) else "moot"


## A world point (x, z) of the element as a position in its frame on the ground (+ dy).
static func _at(ctx: Dictionary, spec: Dictionary, dy := 0.0) -> Vector3:
	var a: Array = spec.get("at", [0, 0])
	return L.local_point(ctx, float(a[0]), float(a[1]), dy)


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var style := style_of(el)
	var root := Node3D.new()
	root.name = str(el.id).validate_node_name()
	var frame_yaw := rad_to_deg((ctx.frame as Transform3D).basis.get_euler().y)
	# the engage trigger
	var eng: Dictionary = el.get("engage", {})
	var triggers := kit.n3("Triggers")
	var trig := Area3D.new()
	trig.name = str(el.get("engage_area", "")).validate_node_name()
	trig.position = _at(ctx, eng)
	trig.rotation_degrees = Vector3(0, float(eng.get("yaw", 0.0)) - frame_yaw, 0)
	kit.scripted(trig, S_TRIGGER, {"area_id": str(el.get("engage_area", "")), "once": false})
	trig.collision_layer = 0
	trig.collision_mask = SceneKit.L_ACTORS
	trig.monitoring = true
	trig.monitorable = false
	var tcs := CollisionShape3D.new()
	tcs.name = "Shape"
	var tsize := Vector3(float(eng.get("size", [20, 12, 8])[0]), float(eng.get("size", [20, 12, 8])[1]),
		float(eng.get("size", [20, 12, 8])[2]))
	tcs.shape = kit.box_shape(tsize)
	tcs.position = Vector3(0, tsize.y * 0.5, 0)
	trig.add_child(tcs)
	triggers.add_child(trig)
	root.add_child(triggers)
	# the gate that closes behind the giant (shown and solid only while engaged)
	var gate_path := NodePath("")
	var g: Dictionary = el.get("gate", {})
	if not g.is_empty():
		var gate := StaticBody3D.new()
		gate.name = "ArenaGate"
		gate.collision_layer = SceneKit.L_WORLD
		gate.collision_mask = 0
		gate.position = _at(ctx, g, -0.5)
		gate.rotation_degrees = Vector3(0, float(g.get("yaw", 0.0)) - frame_yaw, 0)
		var gs: Array = g.get("size", [18, 12, 2])
		var gsize := Vector3(float(gs[0]), float(gs[1]), float(gs[2]))
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		shape.shape = kit.box_shape(gsize)
		shape.position = Vector3(0, gsize.y * 0.5, 0)
		gate.add_child(shape)
		var bars: Array = []
		var n := maxi(3, int(gsize.x / 1.6))
		for i in n:
			var x := -gsize.x * 0.5 + (i + 0.5) * gsize.x / n
			bars.append(L.part("box", Vector3(x, 0, 0), Vector3(0.35, gsize.y, 0.35), "iron"))
		for k in 3:
			bars.append(L.part("box", Vector3(0, gsize.y * (0.25 + k * 0.3), 0), Vector3(gsize.x, 0.4, 0.4), "iron"))
		gate.add_child(L.parts_node("Bars", bars, ctx.get("mat")))
		root.add_child(gate)
		gate_path = NodePath("../ArenaGate")
	# the arena node
	var arena := Node3D.new()
	arena.name = "Arena"
	var props := {"engage_area_id": str(el.get("engage_area", "")), "gate_path": gate_path, "pillars_path": NodePath(""),
		"inner_radius_m": float(el.get("inner_radius", 60.0))}
	for key: String in KEYS[style]:
		if el.has(key):
			var v: Variant = el[key]
			if key == "engines":
				v = PackedStringArray(v)
			elif key in ["disengage_s", "disengage_margin_m"]:
				v = float(v)
			props[key] = v
	kit.scripted(arena, str(SCRIPTS[style]), props)
	root.add_child(arena)
	return root

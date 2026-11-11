extends RefCounted
## Element kind "den_arena" (P35; plan M6-M9 §5.13): the Troll Den's boss arena - a BossArena
## (scripts/world/boss_arena.gd, P34's disengage rule) at the bowl's centre without a gate (the den
## is open to the south-east: its exit is open before engagement), and the den's fire pit beside it
## (a node of group fire_pits with meta radius_m: TrollEnemy sets a troll or whelp set down in it
## Burning). Fields: `boss_id` (the Matriarch's entity id), `encounter` (the encounter that spawns
## her), `engage_area` (the area whose entry engages her: an `areas` entry), `radius` (the arena's
## inner radius), `defeated_flag`, `pit` ([dx, dz] of the fire pit from the element), `pit_r`. Its
## chunk's props part holds it.

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const S_ARENA := "res://scripts/world/boss_arena.gd"
const FIRE_PIT_GROUP := "fire_pits"


static func pit_offset(el: Dictionary) -> Vector3:
	var p: Array = el.get("pit", [0, 0])
	return Vector3(float(p[0]), 0.0, float(p[1]))


static func pit_parts(r: float) -> Array:
	var out: Array = [L.part("cyl", Vector3(0, -0.2, 0), Vector3(r * 2.0, 0.35, 0), "black"),
		L.part("cyl", Vector3(0, 0.1, 0), Vector3(r * 1.3, 0.3, 0), "fire")]
	for k in 10:
		var a := TAU * k / 10.0
		out.append(L.part("sphere", Vector3(cos(a) * r, -0.3, sin(a) * r), Vector3(1.6, 1.1, 1.4), "stone_dark", 30.0 * k))
	for k in 3:
		var a := TAU * (k + 0.2) / 3.0
		out.append(L.part("cone", Vector3(cos(a) * r * 0.35, 0.2, sin(a) * r * 0.35), Vector3(1.6, 2.4, 0), "fire"))
	return out


## The map draws the fire pit (a scripted kind: nothing is merged).
static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var out: Array = []
	var off := pit_offset(el)
	for p: Dictionary in pit_parts(float(el.get("pit_r", 4.5))):
		var q := p.duplicate()
		q.pos = (p.pos as Vector3) + off
		out.append(q)
	return out


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var arena := Node3D.new()
	arena.name = str(el.get("id", "BossArena")).validate_node_name()
	kit.scripted(arena, S_ARENA, {"boss_id": str(el.get("boss_id", "")), "encounter_id": str(el.get("encounter", "")),
		"engage_area_id": str(el.get("engage_area", "")), "gate_path": NodePath(""), "pillars_path": NodePath(""),
		"inner_radius_m": float(el.get("radius", 45.0)), "defeated_flag": str(el.get("defeated_flag", ""))})
	var pit := Node3D.new()
	pit.name = "FirePit"
	pit.position = pit_offset(el)
	pit.add_to_group(FIRE_PIT_GROUP, true)
	pit.set_meta(&"radius_m", float(el.get("pit_r", 4.5)))
	var mesh := L.parts_node("Mesh", pit_parts(float(el.get("pit_r", 4.5))), ctx.get("mat"))
	mesh.add_to_group(TerrainChunk.SCENERY_GROUP, true)
	pit.add_child(mesh)
	arena.add_child(pit)
	return arena

extends RefCounted
## Element kind "bell" (P35; plan M6-M9 §5.7, quest.drowned_bells): one of the Mere's five sunken
## bells - a great bronze bell of the drowned kings hung from a stone frame standing in the water or on
## the shore. A giant rings it by striking it: a BreakableProp (record prop.bell: melee only, a
## few points of health, no debris) whose "broken" state is the rung bell - tilted on its yoke with a
## ring of runes alight round its waist - and whose destruction the quest counts (`destroyed` on its
## world id). Its hit and ring sound by the record's material "bell" (data/audio/bank_world_bells.json).
## The bell hangs so its lip clears the water by `clear_m` (or stands `lip_m` above dry ground); the
## frame (two posts and a lintel, a WORLD body) stays standing. Its chunk's props part holds it.
## M8 gate (F45): but never higher above its own bed than `max_lip_m` (MAX_LIP_M, the Mere's shallows'
## 3 m of water and 0.8 m clear): in deeper water - the Wend's deep reach, 6 m - the bell hangs half
## drowned instead, so its hurtbox and its lock anchor stay where a stage-4 giant wading on that bed
## rings it with a light swing, as in the shallows (at its old 9.3 m only a heavy swing reached it).

const L := preload("res://tools/world/layout.gd")
const K := preload("res://tools/world/kinds/_breakable_kit.gd")
const SCRIPTED := true
const S_BREAKABLE := "res://scripts/world/breakable_prop.gd"
const RECORD := "prop.bell"
const BELL_H := 5.0
const MOUTH_D := 4.6
## M8 gate (F45): the highest a bell's lip hangs above its own bed (an element may set `max_lip_m`).
const MAX_LIP_M := 3.8


## The bell's lip height above the element's ground: `lip_m` on dry ground, clear of the water by
## `clear_m` in it, at most `max_lip_m` (MAX_LIP_M) above the bed.
static func lip_y(el: Dictionary, ctx: Dictionary) -> float:
	var lip := float(el.get("lip_m", 3.0))
	var water := K.water_over(el, ctx)
	if is_finite(water):
		var f: HeightField = ctx.get("field")
		var p := L.pos2(el)
		lip = maxf(lip, water - f.sample(p.x, p.y) + float(el.get("clear_m", 0.8)))
	return minf(lip, maxf(float(el.get("max_lip_m", MAX_LIP_M)), float(el.get("lip_m", 3.0))))


static func _bell(y: float, tilt: float, rung: bool) -> Array:
	var out: Array = [
		L.part("frustum", Vector3(0, y, 0), Vector3(MOUTH_D, BELL_H * 0.8, MOUTH_D * 0.52), "gold", 0.0, Vector3(tilt, 0, 0)),
		L.part("cyl", Vector3(0, y + BELL_H * 0.78, 0), Vector3(MOUTH_D * 0.52, BELL_H * 0.14, 0), "gold", 0.0, Vector3(tilt, 0, 0)),
		L.part("box", Vector3(0, y + BELL_H * 0.9, 0), Vector3(1.2, 0.9, 0.5), "iron", 0.0, Vector3(tilt, 0, 0)),
		L.part("cyl", Vector3(0, y - 0.15, 0), Vector3(MOUTH_D + 0.25, 0.35, 0), "bone_dark", 0.0, Vector3(tilt, 0, 0)),
		L.part("box", Vector3(MOUTH_D * 0.3, y + 1.0, MOUTH_D * 0.2), Vector3(0.9, 1.6, 0.4), "moss", 25.0, Vector3(tilt, 0, 0)),
	]
	if rung:
		out.append(L.part("cyl", Vector3(0, y + BELL_H * 0.32, 0), Vector3(MOUTH_D * 0.86, 0.45, 0), "rune", 0.0, Vector3(tilt, 0, 0)))
		out.append(L.part("cyl", Vector3(0, y - 0.6, 0), Vector3(MOUTH_D * 1.5, 0.12, 0), "rune"))
	return out


## The frame: two stone posts either side and a lintel over the bell.
static func _frame(top: float) -> Array:
	var half := MOUTH_D * 0.5 + 1.8
	return [
		L.part("box", Vector3(-half, -2.0, 0), Vector3(1.6, top + 2.0, 1.6), "stone_dark"),
		L.part("box", Vector3(half, -2.0, 0), Vector3(1.6, top + 2.0, 1.6), "stone_dark"),
		L.part("box", Vector3(0, top, 0), Vector3(half * 2.0 + 2.4, 1.3, 2.0), "stone"),
		L.part("box", Vector3(-half, top + 1.3, 0), Vector3(2.0, 0.8, 2.0), "moss"),
	]


static func design(el: Dictionary, ctx: Dictionary) -> Dictionary:
	var y := lip_y(el, ctx)
	var top := y + BELL_H + 0.4
	var half := MOUTH_D * 0.5 + 1.8
	var mid := Vector3(0, y + BELL_H * 0.5, 0)
	return {"intact": _bell(y, 0.0, false), "broken": _bell(y, 9.0, true),
		"blocks": [[Vector3(MOUTH_D, BELL_H, MOUTH_D), mid]], "hurt": [Vector3(MOUTH_D + 1.6, BELL_H + 1.2, MOUTH_D + 1.6), mid],
		"center": mid, "frame": _frame(top),
		"frame_solids": [[Vector3(1.6, top + 2.0, 1.6), Vector3(-half, (top - 2.0) * 0.5, 0)],
			[Vector3(1.6, top + 2.0, 1.6), Vector3(half, (top - 2.0) * 0.5, 0)]]}


## The map and the skyline draw the frame and the bell (a scripted kind: nothing is merged).
static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	var d := design(el, ctx)
	return (d.frame as Array) + (d.intact as Array)


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


## The prop record of the element (its `record`, else prop.bell).
static func record_of(el: Dictionary) -> String:
	return str(el.get("record", RECORD))


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return K.build(kit, el, ctx, S_BREAKABLE, record_of(el), design(el, ctx))

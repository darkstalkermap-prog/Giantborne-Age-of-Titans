extends RefCounted
## Schema module for "cutscene" records (A4; data/cutscenes/): a shot list in ticks that CutscenePlayer plays in the
## world (CutsceneRules has what each field does). The intro (cutscene.intro) is the first; later titans get theirs.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).

const U := preload("res://scripts/core/schemas/schema_util.gd")
const MAX_TICKS := 60 * 180
const ACTOR_KINDS := ["stoneback", "giant", "villager", "ogre_king", "rootwarden"]   # B2: the Ogre King's model; B3: the Rootwarden's
const EASES := ["linear", "smooth", "in", "out"]


static func fields() -> Dictionary:
	return {
		"ticks": U.int_field(1, MAX_TICKS, true),
		# B2: the level it plays in alone (--cinematic=, export_cinematic.sh): the world by default; the Valley's for
		# the Ogre King's intro
		"level": U.str_field(false, ["level.world", "level.valley"]),
		"focus": U.vec3(),
		"shots": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"id": U.str_field(true),
			"start": U.int_field(0, MAX_TICKS, true),
			"end": U.int_field(1, MAX_TICKS, true),
			"from": U.vec3(true),
			"to": U.vec3(),
			"look_from": U.vec3(true),
			"look_to": U.vec3(),
			"fov": U.num(10.0, 120.0),
			"fov_to": U.num(10.0, 120.0),
			"ease": U.str_field(false, EASES),
			"note": U.str_field()}},
		"lines": {"t": "array", "items": "dict", "item_fields": {
			"start": U.int_field(0, MAX_TICKS, true),
			"end": U.int_field(1, MAX_TICKS, true),
			"text": U.str_field(true)}},
		"cues": {"t": "array", "items": "dict", "item_fields": {
			"tick": U.int_field(0, MAX_TICKS, true),
			"cue": U.str_field(true),
			"volume_db": U.num(-40.0, 12.0)}},
		"shakes": {"t": "array", "items": "dict", "item_fields": {
			"tick": U.int_field(0, MAX_TICKS, true),
			"amount": U.num(0.0, 4.0, true),
			"ticks": U.int_field(1, 600)}},
		"dust": {"t": "array", "items": "dict", "item_fields": {
			"tick": U.int_field(0, MAX_TICKS, true),
			"at": U.vec3(true),
			"size": U.num(0.5, 40.0),
			"count": U.int_field(1, 64),
			"speed": U.num(0.0, 40.0)}},
		"actors": {"t": "array", "items": "dict", "item_fields": {
			"id": U.str_field(true),
			"kind": U.str_field(true, ACTOR_KINDS),
			"stage": U.int_field(1, 10),
			"variant": U.str_field(),
			"on_ground": U.bool_field(),
			"show": {"t": "array", "items": "int"},
			"keys": {"t": "array", "req": true, "items": "dict", "item_fields": {
				"tick": U.int_field(0, MAX_TICKS, true),
				"at": U.vec3(true),
				"yaw": U.num(-720.0, 720.0),
				"clip": U.str_field(),
				"clip_s": U.num(0.0, 60.0),
				"rate": U.num(0.0, 4.0),
				"loop": U.bool_field(),
				"ease": U.str_field(false, EASES)}}}},
		"fades": {"t": "array", "items": "dict", "item_fields": {
			"start": U.int_field(0, MAX_TICKS, true),
			"end": U.int_field(1, MAX_TICKS, true),
			"from": U.num(0.0, 1.0),
			"to": U.num(0.0, 1.0)}},
		"title": {"t": "dict", "fields": {
			"start": U.int_field(0, MAX_TICKS, true),
			"end": U.int_field(1, MAX_TICKS, true),
			"text": U.str_field(true),
			"sub": U.str_field()}},
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var total := int(d.get("ticks", 0)) if U.is_number(d.get("ticks")) else 0
	for key: String in ["shots", "lines", "fades"]:
		var list: Variant = d.get(key, [])
		if typeof(list) != TYPE_ARRAY:
			continue
		for i in (list as Array).size():
			var e: Variant = list[i]
			if typeof(e) != TYPE_DICTIONARY:
				continue
			if int(e.get("end", 0)) <= int(e.get("start", 0)):
				out.errors.append("%s.%s[%d]: ends before it starts" % [ctx, key, i])
			if int(e.get("end", 0)) > total:
				out.errors.append("%s.%s[%d]: ends after the cutscene (%d ticks)" % [ctx, key, i, total])


static func required_ids() -> Dictionary:
	return {"cutscene.intro": "cutscene"}

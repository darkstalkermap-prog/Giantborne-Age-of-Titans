extends RefCounted
## Schema module for "npc" records (P11b; plan §2.8.3): the people of a level - civilians that
## flee from danger and talkers that stay to speak (the elder). A Civilian actor reads it.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "npc.elder", "type": "npc", "role": "talker", "display_name": "Elder Maren",
##    "scene": "res://scenes/npcs/elder.tscn", "height_m": 1.7, "capsule_radius_m": 0.3, "health": 60,
##    "armor": 0, "walk_speed_mps": 1.2, "run_speed_mps": 2.8, "flee_trigger_radius_m": 0,
##    "protected": true, "dialogue": "dialogue.elder", "lockable": false, "grants_fury": false,
##    "threat": 0.0, "nav_layers": 1, "grab_attach": "none"}
##
## role: "civilian" (flees to the nearest reachable safe marker: when the giant comes within
## flee_trigger_radius_m faster than 3 m/s, when combat starts within flee_noise_radius_m (20),
## or when its faction turns hostile or stands down) or "talker" (never flees).
## protected: every hit is refused (IMMUNE) - the elder cannot be killed.
## dialogue: the `dialogue` record an NpcTalker on the actor runs (P13). It is an id, not a
## checked reference: the dialogue may ship later than the npc (P15 writes dialogue.elder); a talk
## whose dialogue does not exist says "They have nothing to say right now."
##
## Defaults (the Civilian applies them when a key is absent): armor 0, walk 1.2 m/s, run 3.0 m/s,
## turn 360 deg/s, flee_trigger_radius_m 0 (never by proximity), flee_noise_radius_m 20,
## protected false, dialogue "", lockable false, grants_fury false, threat 0, nav_layers 1,
## grab_attach "none" (a Civilian has no grab hooks: it can never be held).

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	return {
		"role": U.str_field(true, DataValidator.NPC_ROLES),
		# The scene an EncounterDirector instances (must exist), like enemy records.
		"scene": U.str_field(true),
		"height_m": U.pos(true),
		"capsule_radius_m": U.pos(true),
		"health": U.pos(true),
		"armor": U.num(0.0),
		"walk_speed_mps": U.pos(),
		"run_speed_mps": U.pos(),
		"turn_rate_deg_s": U.pos(),
		# The giant scares a civilian when it comes this close moving faster than 3 m/s (0 = never).
		"flee_trigger_radius_m": U.num(0.0),
		# An attack starting, or a blow landing, this close sends a civilian running.
		"flee_noise_radius_m": U.num(0.0),
		"protected": U.bool_field(),
		"dialogue": U.str_field(),
		"lockable": U.bool_field(),
		"grants_fury": U.bool_field(),
		"threat": U.num(0.0, 1.0),
		"nav_layers": U.int_field(1, 255),
		"grab_attach": U.str_field(false, DataValidator.GRAB_ATTACH),
		"mass_class": U.str_field(false, DataValidator.MASS_CLASSES),
	}


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var scene: Variant = d.get("scene")
	if typeof(scene) == TYPE_STRING:
		if not (scene.begins_with("res://scenes/") and scene.ends_with(".tscn")):
			out.errors.append("%s: scene '%s' must be a res://scenes/....tscn path" % [ctx, scene])
		elif not ResourceLoader.exists(scene):
			out.errors.append("%s: scene '%s' does not exist (run tools/build_scenes)" % [ctx, scene])
	if U.is_number(d.get("walk_speed_mps")) and U.is_number(d.get("run_speed_mps")) \
			and float(d.run_speed_mps) < float(d.walk_speed_mps):
		out.errors.append("%s: run_speed_mps must be >= walk_speed_mps" % ctx)
	var dialogue: Variant = d.get("dialogue")
	if typeof(dialogue) == TYPE_STRING and dialogue != "":
		U.check_id_string(dialogue, ctx + ".dialogue", out)
	if str(d.get("role", "")) == "talker" and (typeof(dialogue) != TYPE_STRING or dialogue == ""):
		out.warnings.append("%s: a talker without a dialogue has nothing to say" % ctx)
	if str(d.get("grab_attach", "none")) != "none":
		out.warnings.append("%s: grab_attach has no effect on an npc (civilians cannot be held)" % ctx)


static func required_ids() -> Dictionary:
	return {}

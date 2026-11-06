extends RefCounted
## Schema module for "level" records (P10a; plan §2.8.3): one per loadable level (the Valley,
## test levels). The level's root node (LevelRoot) carries the same id as `level_id`; the
## EncounterDirector reads the budget and the AI LOD numbers from it, P14 the render presets
## and the web overrides, GameSession the start checkpoint and the scene.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "level.valley", "type": "level", "display_name": "Valley of Broken Kings",
##    "scene": "res://scenes/world/valley.tscn", "start_checkpoint": "valley.shrine.hollow", "max_active_enemies": 12,
##    "lod": {"near_m": 40, "mid_m": 90, "check_ticks": 30, "corpse_free_s": 6},
##    "render": {"low": {"shadow_distance_m": 60, "scenery_visibility_end_m": 160, "msaa": 0},
##               "medium": {"shadow_distance_m": 120, "scenery_visibility_end_m": 220, "msaa": 2}},
##    "web_overrides": {"quality": "low", "ai_tier1_m": 30},
##    "districts": [{"id": "hollow", "display_name": "Giant's Hollow", "min_m": [-200, 0, 100], "max_m": [-90, 0, 200]}]}
##
## Defaults (the EncounterDirector applies them when a key is absent): max_active_enemies 12,
## lod {near_m 40, mid_m 90, check_ticks 30, corpse_free_s 6}. District ids are plain words
## ("hollow"); encounters name theirs in `district` (checked by the GameData post-pass).

const U := preload("res://scripts/core/schemas/schema_util.gd")

## The graphics presets a level may tune (P14 applies them; Settings.graphics_quality).
const QUALITIES := ["low", "medium"]
const MSAA_VALUES := [0, 2, 4, 8]
const DISTRICT_ID_REGEX := "^[a-z][a-z0-9_]*$"


static func fields() -> Dictionary:
	var preset := {"t": "dict", "fields": {
		"shadow_distance_m": U.num(0.0),
		"scenery_visibility_end_m": U.num(0.0),
		"msaa": U.int_field(0, 8)}}
	var f := {
		# The scene main.gd instantiates for this level (must exist).
		"scene": U.str_field(true),
		# Where a New Game starts (a CheckpointMarker id in the scene).
		"start_checkpoint": U.str_field(true),
		# The EncounterDirector never has more budgeted combatants alive at once.
		"max_active_enemies": U.int_field(1, 64),
		# AI level of detail: tier 0 within near_m of the player, tier 1 within mid_m, else
		# tier 2 (dormant); checked every check_ticks; dead encounter members are freed
		# corpse_free_s after death.
		"lod": {"t": "dict", "fields": {
			"near_m": U.pos(true),
			"mid_m": U.pos(true),
			"check_ticks": U.int_field(1, 600, true),
			"corpse_free_s": U.num(0.0, null, true)}},
		"render": {"t": "dict", "keys_enum": QUALITIES, "values": preset},
		"web_overrides": {"t": "dict", "fields": {
			"quality": U.str_field(false, QUALITIES),
			"ai_tier1_m": U.pos()}},
		"districts": {"t": "array", "items": "dict", "item_fields": {
			"id": U.str_field(true),
			"display_name": U.str_field(),
			"min_m": U.vec3(true),
			"max_m": U.vec3(true),
			# the district's footfall surface when audio_mix.default does not name it (test levels)
			"surface": U.str_field(false, ["soft", "hard", "wet"])}},
	}
	# M6-M9 (P20, plan M6-M9 §2.6, §2.7): the level's world index (WorldIndex resource the builder
	# writes; LevelRoot.index(), WorldIndex.for_level) and the nav layer the player falls back to
	# when its growth profile's layer is not baked here (P24b reads it; the Valley gets 4 from P26).
	f.merge({
		"index": U.str_field(),
		"player_nav_fallback": U.int_field(1, 255),
	})
	# Later packages add their fields (a render preset's: f.render.values.fields) below their anchor.
	## @anchor P24a

	## @anchor P24b

	## @anchor P25

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var scene: Variant = d.get("scene")
	if typeof(scene) == TYPE_STRING:
		if not (scene.begins_with("res://scenes/") and scene.ends_with(".tscn")):
			out.errors.append("%s: scene '%s' must be a res://scenes/....tscn path" % [ctx, scene])
		elif not ResourceLoader.exists(scene):
			out.errors.append("%s: scene '%s' does not exist (run tools/build_scenes)" % [ctx, scene])
	var start: Variant = d.get("start_checkpoint")
	if typeof(start) == TYPE_STRING:
		U.check_id_string(start, ctx + ".start_checkpoint", out)
	var lod: Variant = d.get("lod")
	if typeof(lod) == TYPE_DICTIONARY and U.is_number(lod.get("near_m")) and U.is_number(lod.get("mid_m")) \
			and float(lod.near_m) > float(lod.mid_m):
		out.errors.append("%s: lod.near_m must be <= lod.mid_m" % ctx)
	var render: Variant = d.get("render")
	if typeof(render) == TYPE_DICTIONARY:
		for q: Variant in render:
			var preset: Variant = render[q]
			if typeof(preset) == TYPE_DICTIONARY and U.is_number(preset.get("msaa")) \
					and not MSAA_VALUES.has(int(preset.msaa)):
				out.errors.append("%s.render.%s.msaa: must be one of %s (got %s)" % [ctx, q, MSAA_VALUES, preset.msaa])
	var districts: Variant = d.get("districts")
	if typeof(districts) == TYPE_ARRAY:
		var re := RegEx.create_from_string(DISTRICT_ID_REGEX)
		var seen := {}
		var i := 0
		for dist: Variant in districts:
			var dctx := "%s.districts[%d]" % [ctx, i]
			i += 1
			if typeof(dist) != TYPE_DICTIONARY:
				continue
			var id: Variant = dist.get("id")
			if typeof(id) == TYPE_STRING:
				if re.search(id) == null:
					out.errors.append("%s.id: district id '%s' must be a plain lowercase word like 'hollow'" % [dctx, id])
				if seen.has(id):
					out.errors.append("%s.id: duplicate district id '%s'" % [dctx, id])
				seen[id] = true
			var lo: Variant = dist.get("min_m")
			var hi: Variant = dist.get("max_m")
			if _is_vec3(lo) and _is_vec3(hi):
				if float(lo[0]) > float(hi[0]) or float(lo[2]) > float(hi[2]):
					out.errors.append("%s: min_m must not exceed max_m in x and z" % dctx)
	# M6-M9 (P20): the index is a generated resource that must exist.
	var index: Variant = d.get("index")
	if typeof(index) == TYPE_STRING and index != "":
		if not (index.begins_with("res://assets/") and index.ends_with(".res")):
			out.errors.append("%s: index '%s' must be a res://assets/....res path" % [ctx, index])
		elif not ResourceLoader.exists(index):
			out.errors.append("%s: index '%s' does not exist (run tools/build_scenes)" % [ctx, index])
	var fallback: Variant = d.get("player_nav_fallback")
	if U.is_number(fallback) and int(fallback) > 0 and (int(fallback) & (int(fallback) - 1)) != 0:
		out.errors.append("%s: player_nav_fallback must be one nav layer bit (1, 2, 4, 8, 16, ...)" % ctx)
	## @anchor P24a

	## @anchor P24b

	## @anchor P25


static func required_ids() -> Dictionary:
	return {}


## The district ids a level record declares, in order.
static func district_ids(level: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var districts: Variant = level.get("districts")
	if typeof(districts) == TYPE_ARRAY:
		for dist: Variant in districts:
			if typeof(dist) == TYPE_DICTIONARY and typeof(dist.get("id")) == TYPE_STRING:
				out.append(dist.id)
	return out


static func _is_vec3(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 3:
		return false
	for c: Variant in v:
		if not U.is_number(c):
			return false
	return true

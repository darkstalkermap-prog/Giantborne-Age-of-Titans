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
	# P24a (plan M6-M9 §2.7, decision 12): a render preset's terrain_visibility_end_m (a streamed
	# chunk's terrain beyond it from the camera is not drawn: the skyline shows) and camera_far_m (the
	# camera's far plane; 800 m when absent), and a streamed level's `world` block (the chunk grid, the
	# streaming ring and budget, the chunk and navmesh folders, the nav layers and gate bits P24b uses,
	# the depth fog, the water level and the skyline's two meshes; world_checks() below).
	(((f.render as Dictionary).values as Dictionary).fields as Dictionary).merge({
		"terrain_visibility_end_m": U.num(0.0),
		"camera_far_m": U.pos(),
	})
	f["world"] = {"t": "dict", "fields": {
		"chunk_size_m": U.pos(true),
		"grid": {"t": "array", "req": true, "items": "int"},
		"origin_m": U.vec3(true),
		"height_spacing_m": U.pos(true),
		"load_ring": U.int_field(0, 4, true),
		"unload_at": U.int_field(1, 8, true),
		"budget_ms": U.pos(true),
		"steps_per_frame_headless": U.int_field(1, 64, true),
		"chunk_dir": U.str_field(true),
		"nav_dir": U.str_field(),
		"nav_layers": {"t": "array", "items": "int"},
		"gate_bits": {"t": "dict", "keys_enum": ["4", "5", "6", "7", "8", "9", "10"], "values": U.int_field(1)},
		"fog_m": {"t": "array", "items": "number"},
		"fog_max": U.num(0.0, 1.0),
		"water_level_m": U.num(),
		"skyline": U.str_field(),
		"skyline_landmarks": U.str_field(),
	}}

	## @anchor P24b
	# P24b (plan M6-M9 §2.7, §2.8, decision 13): the level's navigation queries (NavQuery): unlimited
	# polygons (max_polygons 0) with a distance cap by purpose (chase_distance_m for chases,
	# far_distance_m for the bot and the director), the tier-0 re-path throttle (at least
	# repath_min_ticks apart and only when the goal moved repath_min_move_m) and the per-tick query
	# budget (queries_per_tick). Absent: today's queries (map_get_path's parameters) - the Valley.
	f["nav_query"] = {"t": "dict", "fields": {
		"max_polygons": U.int_field(0, 1000000, true),
		"chase_distance_m": U.pos(true),
		"far_distance_m": U.pos(true),
		"repath_min_ticks": U.int_field(0, 600, true),
		"repath_min_move_m": U.num(0.0, null, true),
		"queries_per_tick": U.int_field(0, 1000, true),
	}}

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
	# P24a: the far plane covers what the preset draws; a streamed level's world block (P24a's
	# GameData post-pass checks that its chunk files exist).
	var p24a_render: Variant = d.get("render")
	var p24a_world: Variant = d.get("world")
	if typeof(p24a_render) == TYPE_DICTIONARY:
		for q: Variant in p24a_render:
			var preset: Variant = p24a_render[q]
			if typeof(preset) != TYPE_DICTIONARY:
				continue
			var far := float(preset.get("camera_far_m", 800.0)) if U.is_number(preset.get("camera_far_m", 800.0)) else 800.0
			for key: String in ["terrain_visibility_end_m", "scenery_visibility_end_m"]:
				if U.is_number(preset.get(key)) and float(preset[key]) > far:
					out.errors.append("%s.render.%s: %s (%s m) is beyond camera_far_m (%s m)" % [ctx, q, key, preset[key], far])
			if typeof(p24a_world) == TYPE_DICTIONARY and typeof(p24a_world.get("fog_m")) == TYPE_ARRAY \
					and (p24a_world.fog_m as Array).size() == 2 and U.is_number(p24a_world.fog_m[1]) \
					and float(p24a_world.fog_m[1]) > far:
				out.errors.append("%s.render.%s: camera_far_m (%s m) must reach the world's fog end (%s m)" % [ctx, q,
					far, p24a_world.fog_m[1]])
	if typeof(p24a_world) == TYPE_DICTIONARY:
		var wctx := ctx + ".world"
		var w: Dictionary = p24a_world
		var g: Variant = w.get("grid")
		if typeof(g) == TYPE_ARRAY and ((g as Array).size() != 2 or not U.is_number(g[0]) or not U.is_number(g[1]) \
				or int(g[0]) < 1 or int(g[1]) < 1):
			out.errors.append("%s.grid: expected [columns, rows], each at least 1" % wctx)
		if U.is_number(w.get("load_ring")) and U.is_number(w.get("unload_at")) \
				and int(w.unload_at) < int(w.load_ring) + 2:
			out.errors.append("%s: unload_at (%s) must be at least load_ring + 2 (%s): the streaming hysteresis" % [wctx,
				w.unload_at, int(w.load_ring) + 2])
		for key: String in ["chunk_dir", "nav_dir"]:
			if typeof(w.get(key)) == TYPE_STRING and str(w[key]) != "" and not str(w[key]).begins_with("res://"):
				out.errors.append("%s.%s: '%s' must be a res:// folder" % [wctx, key, w[key]])
		for key: String in ["skyline", "skyline_landmarks"]:
			var path: Variant = w.get(key)
			if typeof(path) == TYPE_STRING and path != "":
				if not (str(path).begins_with("res://") and str(path).ends_with(".res")):
					out.errors.append("%s.%s: '%s' must be a res://....res path" % [wctx, key, path])
				elif not ResourceLoader.exists(path):
					out.errors.append("%s.%s: '%s' does not exist (run tools/build_scenes)" % [wctx, key, path])
		var bits: Array = []
		if typeof(w.get("nav_layers")) == TYPE_ARRAY:
			bits.append_array(w.nav_layers)
		if typeof(w.get("gate_bits")) == TYPE_DICTIONARY:
			bits.append_array((w.gate_bits as Dictionary).values())
		for b: Variant in bits:
			if U.is_number(b) and (int(b) <= 0 or (int(b) & (int(b) - 1)) != 0):
				out.errors.append("%s: navigation bit %s must be one bit (1, 2, 4, 8, 16, ...)" % [wctx, b])
		var fog: Variant = w.get("fog_m")
		if typeof(fog) == TYPE_ARRAY and ((fog as Array).size() != 2 or not U.is_number(fog[0]) or not U.is_number(fog[1]) \
				or float(fog[0]) >= float(fog[1])):
			out.errors.append("%s.fog_m: expected [from, to] metres with from < to" % wctx)
		if typeof(d.get("index")) != TYPE_STRING or str(d.get("index")) == "":
			out.errors.append("%s: a streamed level needs its world index ('index')" % ctx)

	## @anchor P24b
	# P24b: a chase never searches farther than the bot and the director do.
	var p24b_q: Variant = d.get("nav_query")
	if typeof(p24b_q) == TYPE_DICTIONARY and U.is_number(p24b_q.get("chase_distance_m")) \
			and U.is_number(p24b_q.get("far_distance_m")) and float(p24b_q.chase_distance_m) > float(p24b_q.far_distance_m):
		out.errors.append("%s.nav_query: chase_distance_m (%s) must not exceed far_distance_m (%s)" % [ctx,
			p24b_q.chase_distance_m, p24b_q.far_distance_m])

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

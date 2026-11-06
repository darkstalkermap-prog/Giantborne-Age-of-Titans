extends IntegrationSuite
## P22 (plan M6-M9 §3.4 design 2, decision 9): the distance LOD. An actor's rig is drawn as itself
## up to render_lod_m + 5 m and as its one-box proxy (a copy of Visual/LodProxy under Visual/Body,
## "FarProxy") from render_lod_m - 5 m: the renderer swaps them by distance with an overlap and no
## gap. The enemy records set the distance (the Ogre King's 0 = never), the people's builder sets
## theirs; the AI LOD tier 2 is unchanged (Body hidden, Visual/LodProxy shown).

const WOLF := "res://scenes/enemies/wolf.tscn"
const VILLAGER := "res://scenes/npcs/villager.tscn"
const KING := "res://scenes/enemies/ogre_king.tscn"
## The record values (data/enemies/*.json render_lod_m).
const RECORD_LOD := {"enemy.soldier": 45.0, "enemy.archer": 45.0, "enemy.mage": 45.0,
	"enemy.wolf": 40.0, "enemy.ogre": 70.0, "enemy.ogre_king": 0.0}


## Every GeometryInstance3D under `node` except `skip`.
static func _geometry(node: Node, skip: Node, out: Array[GeometryInstance3D] = []) -> Array[GeometryInstance3D]:
	for c in node.get_children():
		if c == skip:
			continue
		if c is GeometryInstance3D:
			out.append(c as GeometryInstance3D)
		_geometry(c, skip, out)
	return out


## The rig `visual` is set up for `lod_m`: its parts end at lod_m + 5, its far proxy begins at
## lod_m - 5 and never ends, with the proxy's mesh and the actor's material.
func _assert_lod(visual: Node3D, body: Node3D, far: MeshInstance3D, lod_m: float, what: String) -> void:
	assert_true(far != null and far.name == RigPaint.FAR_PROXY and far.get_parent() == body,
		"%s: a FarProxy under Visual/Body" % what)
	if far == null:
		return
	var proxy := visual.get_node("LodProxy") as MeshInstance3D
	assert_true(far.mesh == proxy.mesh and far.material_override == proxy.material_override,
		"%s: the far proxy is the LodProxy's box in the actor's material" % what)
	assert_near(far.visibility_range_begin, lod_m - 5.0, 1e-4, "%s: the far proxy from %.0f m" % [what, lod_m - 5.0])
	assert_eq(far.visibility_range_end, 0.0, "%s: and on to any distance" % what)
	var parts := _geometry(body, far)
	assert_true(parts.size() >= 5, "%s: the rig's parts" % what)
	for g in parts:
		assert_near(g.visibility_range_end, lod_m + 5.0, 1e-4, "%s/%s ends at %.0f m" % [what, g.name, lod_m + 5.0])
		assert_eq(g.visibility_range_begin, 0.0, "%s/%s from the start" % [what, g.name])
	var far_proxies := body.find_children(RigPaint.FAR_PROXY, "MeshInstance3D", false, false)
	assert_eq(far_proxies.size(), 1, "%s: one far proxy" % what)


func test_the_records_set_the_distances() -> void:
	for id: String in RECORD_LOD:
		assert_eq(float(GameData.get_record(id).get("render_lod_m", -1.0)), float(RECORD_LOD[id]),
			"%s: render_lod_m %.0f" % [id, float(RECORD_LOD[id])])
	var v := (load(VILLAGER) as PackedScene).instantiate()
	assert_eq(float((v.get_node("Visual") as ActorRig).render_lod_m), 45.0, "the people's builder sets 45 m")
	v.free()


func test_a_soldier_swaps_its_rig_for_the_box_by_distance_and_tier_2_is_unchanged() -> void:
	var s := spawn_soldier(Vector3(0, 0.05, -4))
	await step_ticks(1)
	_assert_lod(s.rig, s.rig.body, s.rig.far_proxy, 45.0, "soldier")
	var mats: Array = s.rig.get("_materials")
	assert_true(s.rig.far_proxy.material_override == mats[0], "the far proxy flashes and tints with the rig")
	# Applying it again keeps the one far proxy and moves the ranges.
	s.rig.set_render_lod(30.0)
	_assert_lod(s.rig, s.rig.body, s.rig.far_proxy, 30.0, "soldier at 30 m")
	s.rig.set_render_lod(45.0)
	# AI LOD tier 2: Body (and the far proxy with it) hidden, Visual/LodProxy shown; back at tier 0.
	var proxy := s.rig.get_node("LodProxy") as MeshInstance3D
	assert_true(s.rig.body.visible and not proxy.visible, "tier 0: the rig, not the tier-2 proxy")
	s.set_lod_tier(2)
	assert_true(not s.rig.body.visible and proxy.visible, "tier 2: Body hidden, LodProxy shown")
	assert_false(s.rig.far_proxy.is_visible_in_tree(), "the far proxy hides with Body")
	s.set_lod_tier(0)
	assert_true(s.rig.body.visible and not proxy.visible and s.rig.far_proxy.is_visible_in_tree(), "tier 0 again")


func test_a_wolf_takes_its_record_distance_and_never_is_the_king() -> void:
	var w := (load(WOLF) as PackedScene).instantiate() as WolfEnemy
	w.entity_id = "test.wolf"
	w.ai_enabled = false
	w.position = Vector3(3, 0.05, -4)
	world.add_child(w)
	await step_ticks(1)
	_assert_lod(w.quad, w.quad.body, w.quad.far_proxy, 40.0, "wolf")
	# The Ogre King (render_lod_m 0): no far proxy, no range on its parts; a rig set back to 0
	# hides its far proxy and clears the ranges.
	var king := (load(KING) as PackedScene).instantiate()
	var visual := king.get_node("Visual") as Node3D
	var body := visual.get_node("Body") as Node3D
	assert_true(RigPaint.apply_render_lod(visual, body, 0.0) == null, "0 m: no far proxy")
	for g in _geometry(body, null):
		assert_eq(g.visibility_range_end, 0.0, "king/%s: drawn at any distance" % g.name)
	var far := RigPaint.apply_render_lod(visual, body, 70.0)
	assert_true(far != null and far.visible, "a far proxy at 70 m")
	assert_true(RigPaint.apply_render_lod(visual, body, 0.0) == null and not far.visible,
		"set back to 0: the far proxy hides")
	for g in _geometry(body, far):
		assert_eq(g.visibility_range_end, 0.0, "king/%s: drawn at any distance again" % g.name)
	king.free()

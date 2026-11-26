extends IntegrationSuite
## C3 (decision C3-6): every forge wears the smithy and every waystone the monument, put on by their own scripts
## wherever they stand, and both show their state.
##   * forge.tscn: the smithy behind its root (unturned, its size), the old boxes hidden, their solids kept; lit while
##     open (the light, the smoke, the embers), cold while shut; a forge built at a giant's scale (no Hearth body:
##     the condition_forge kind's) wears it turned and larger;
##   * a waystone: the monument at its old stone's foot, the old stone, cap and glow hidden; shut (its flag unmet):
##     dark, no ring, no beam; open: a faint pulse, still no beam; reached (or its visited flag): ring and beam;
##   * the HUD's place marker words: a waystone's three states, a forge's lit state with what it works, its cold one.

const FORGE_SCENE := "res://scenes/world/forge.tscn"


func _waystone(id: String, flags: PackedStringArray) -> Waystone:
	var m := Marker3D.new()
	m.name = id.validate_node_name()
	m.set_script(load("res://scripts/world/waystone.gd"))
	m.set("checkpoint_id", id)
	m.set("radius_m", 6.0)
	m.set("requires_flags", flags)
	m.set("display_name", "Test waystone")
	m.position = Vector3(30, 0.3, 0)
	var body := StaticBody3D.new()
	body.name = "Stone"
	body.position = Vector3(5, -0.3, 0)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 5.0, 1.6)
	cs.shape = box
	cs.position = Vector3(0, 2.5, 0)
	body.add_child(cs)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = BoxMesh.new()
	body.add_child(mesh)
	m.add_child(body)
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	glow.mesh = BoxMesh.new()
	m.add_child(glow)
	world.add_child(m)
	return m as Waystone


func test_a_forge_wears_the_smithy_lit_or_cold() -> void:
	var f := (load(FORGE_SCENE) as PackedScene).instantiate() as Forge
	f.world_id = "c3.forge"
	f.requires_flags = PackedStringArray(["c3.forge_open"])
	f.position = Vector3(0, 0, -8)
	world.add_child(f)
	await step_ticks(2)
	assert_true(f.look != null and f.look.get_parent() == f, "the smithy is on")
	assert_true(f.look.scale.is_equal_approx(Vector3.ONE) and is_zero_approx(f.look.rotation.y), "at forge.tscn's size, unturned")
	for n: Node in f.find_children("*", "GeometryInstance3D", true, false):
		if not f.look.is_ancestor_of(n):
			assert_false((n as GeometryInstance3D).visible, "the old %s hidden" % n.name)
	assert_true(f.get_node("Hearth") is StaticBody3D and f.get_node("Anvil") is StaticBody3D, "the old solids kept")
	assert_false(f.look.lit, "shut: cold")
	assert_false((f.look.get_node("Light") as Light3D).visible, "no fire's light")
	assert_false((f.look.get_node("Smoke") as CPUParticles3D).emitting, "no smoke")
	WorldState.set_flag("c3.forge_open", true)
	await get_tree().create_timer(Forge.LOOK_POLL_S + 0.2).timeout
	assert_true(f.look.lit, "open: lit")
	assert_true((f.look.get_node("Light") as Light3D).visible, "the fire's light")
	assert_true((f.look.get_node("Smoke") as CPUParticles3D).emitting, "smoke from the chimney")
	assert_true((f.look.get_node("Embers") as CPUParticles3D).emitting, "embers over the coals")
	assert_true(f.look.crown().y > f.global_position.y + 12.0, "its chimney stands over 12 m (%.1f)" % (f.look.crown().y - f.global_position.y))
	# a forge built at a giant's scale (no Hearth body: the condition_forge kind)
	var big := Forge.new()
	big.world_id = "c3.big_forge"
	big.position = Vector3(20, 0, -8)
	world.add_child(big)
	await step_ticks(1)
	assert_true(big.look != null, "a scripted forge wears it too")
	assert_near(big.look.scale.x, Forge.BIG_SMITHY_SCALE, 1e-4, "larger")
	assert_near(absf(big.look.rotation.y), PI, 1e-4, "turned: its hearth at -z")


func test_a_waystone_wears_the_monument_and_shows_its_state() -> void:
	var w := _waystone("c3.way", PackedStringArray(["c3.way_open"]))
	await step_ticks(2)
	assert_true(w.look != null, "the monument is on")
	assert_true(w.look.position.is_equal_approx(Vector3(5, -0.3, 0)), "at the old stone's foot (%s)" % w.look.position)
	assert_false((w.get_node("Stone/Mesh") as GeometryInstance3D).visible, "the old stone hidden")
	assert_false((w.get_node("Glow") as GeometryInstance3D).visible, "the old glow hidden")
	assert_true(w.get_node("Stone") is StaticBody3D, "its solid kept")
	assert_eq(w.look.state_name(), "shut", "shut")
	assert_false((w.look.get_node("Beam") as Node3D).visible, "no beam")
	assert_false((w.look.get_node("Ring") as Node3D).visible, "no ring")
	assert_eq(HudPlaceMarker.waystone_state(w), "Sealed", "the marker: sealed")
	WorldState.set_flag("c3.way_open", true)
	await step_ticks(1)
	assert_eq(w.look.state_name(), "open", "open, not yet reached")
	assert_false((w.look.get_node("Beam") as Node3D).visible, "still no beam")
	assert_eq(HudPlaceMarker.waystone_state(w), "Not yet reached: walk up to it", "the marker says so")
	WorldState.set_flag(GameSession.VISITED_PREFIX + "c3.way", true)
	await step_ticks(1)
	assert_eq(w.look.state_name(), "known", "reached once: known")
	assert_true((w.look.get_node("Ring") as Node3D).visible, "the ring of rune stones")
	await get_tree().create_timer(WaystoneLook.FADE_S * 0.5).timeout
	assert_true((w.look.get_node("Beam") as Node3D).visible, "the beam rising")
	assert_eq(HudPlaceMarker.waystone_state(w), "Reached: travel here from the map (M)", "the marker: travel")


func test_the_place_marker_names_a_forge_and_what_it_works() -> void:
	var f := (load(FORGE_SCENE) as PackedScene).instantiate() as Forge
	f.world_id = "c3.forge2"
	f.display_name = "Millford's quarry forge"
	f.works = PackedStringArray(["titan_stone"])
	world.add_child(f)
	await step_ticks(1)
	assert_eq(HudPlaceMarker.forge_name(f), "Millford's quarry forge", "its name")
	assert_eq(HudPlaceMarker.forge_state(f), "Lit: reforge and craft (E)  - works titan stone", "lit, with what it works")
	f.requires_flags = PackedStringArray(["c3.never"])
	f.closed_message = "The forge is cold."
	assert_eq(HudPlaceMarker.forge_state(f), "Cold: The forge is cold.", "cold, in its own words")
	f.display_name = "Kingsgate"
	assert_eq(HudPlaceMarker.forge_name(f), "Kingsgate (forge)", "a name without the word says it is a forge")

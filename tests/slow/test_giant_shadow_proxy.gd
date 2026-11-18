extends TestSuite
## P49 (plan M11 §2.2, §2.12 "shadows one draw call a cascade", §3.2 item 4): the shadow proxy path of
## RigPaint.use_shadow_proxy, which ActorRig runs in _ready. When a skinned model has a mesh named
## ShadowProxy, that mesh alone casts the model's shadow (shadows only) and every other mesh beside it
## casts none - a part that joins later included, a cape excepted - so a directional light's cascade draws
## one mesh of the giant instead of every shown one (0.10.0-m10: 9 to 12 again in each cascade; 395 draw
## calls in the Valley walk and 674 in the stress arena at `medium`).
##   * the rule, headless, on a model built here: with a proxy, without one (nothing changes), a part
##     joining later, a cape, a second call;
##   * rendered (a child Godot under Xvfb, tests/support/shadow_proxy_probe.gd: the rendering server's draw
##     calls in a still scene, the giant's model in its default look under a bare ActorRig): with one
##     shadow map the model costs its shown surfaces again without the proxy and ONE draw with it; with two
##     and four cascades two and four; a mesh joining later adds no shadow draw, a cape adds its own.
## The model's own ShadowProxy is P48's (assets/giant/giant.glb): until it is in the model the probe runs
## the same path on a stand-in (a copy of the torso's mesh under the same skeleton, named ShadowProxy) and
## the test says which it measured; with the real proxy it also checks that the rig found it by itself.
## Without xvfb-run the rendered part is skipped with a note (tools/check.sh --require makes that a failure).

const PROBE := "res://tests/support/shadow_proxy_probe.gd"
const PREFIX := "SHADOW_PROXY "
const MODEL := "res://scenes/player/giant_model.tscn"
const ON := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
const OFF := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
const ONLY := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func _mesh(mesh_name: String, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = BoxMesh.new()
	parent.add_child(mi)
	return mi


## A rig with a "skeleton" holding the named meshes: [rig, holder].
func _rig(names: Array) -> Array:
	var rig := ActorRig.new()
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	var model := Node3D.new()
	model.name = "Model"
	rig.add_child(model)
	var holder := Skeleton3D.new()
	holder.name = "Skeleton3D"
	model.add_child(holder)
	for n: String in names:
		_mesh(n, holder)
	return [rig, holder]


func test_with_a_proxy_only_the_proxy_and_a_cape_cast() -> void:
	var made := _rig(["Body_Torso", "Body_Limbs", "Eyes", "Hair_long_back", "Garment_cape", "ShadowProxy"])
	var rig: ActorRig = made[0]
	var holder: Node = made[1]
	var weapon := _mesh("Club", rig)   # beside the model, not in it: the weapon keeps its shadow
	(holder.get_node("ShadowProxy") as MeshInstance3D).visible = false
	add_child(rig)   # ActorRig._ready
	var proxy := holder.get_node("ShadowProxy") as MeshInstance3D
	assert_true(rig.shadow_proxy == proxy, "the rig found the model's ShadowProxy")
	assert_eq(proxy.cast_shadow, ONLY, "the proxy is drawn in shadow passes only")
	assert_true(proxy.visible, "and shown (a hidden mesh casts nothing)")
	for n: String in ["Body_Torso", "Body_Limbs", "Eyes", "Hair_long_back"]:
		assert_eq((holder.get_node(n) as MeshInstance3D).cast_shadow, OFF, "%s casts no shadow of its own" % n)
		assert_false(RigPaint.casts_beside_proxy(holder.get_node(n) as MeshInstance3D), "%s: casts_beside_proxy is false" % n)
	assert_eq((holder.get_node("Garment_cape") as MeshInstance3D).cast_shadow, ON, "a cape keeps its own shadow")
	assert_eq(weapon.cast_shadow, ON, "a mesh outside the model's skeleton is left alone (the weapon)")
	# A part loaded on demand joins the skeleton later.
	var hair := _mesh("Hair_braids", holder)
	assert_eq(hair.cast_shadow, OFF, "a mesh that joins later casts none either")
	var cape := _mesh("Garment_cape_long", holder)
	assert_eq(cape.cast_shadow, ON, "a cape that joins later keeps its shadow")
	var marker := Node3D.new()
	holder.add_child(marker)   # a node that is no mesh: nothing to do, no error
	# Calling it again changes nothing and connects nothing twice.
	assert_true(RigPaint.use_shadow_proxy(rig) == proxy, "a second call returns the same proxy")
	var connections := 0
	for c: Dictionary in holder.child_entered_tree.get_connections():
		if (c.callable as Callable).get_method() == &"shade_beside_proxy":
			connections += 1
	assert_eq(connections, 1, "the skeleton's child_entered_tree is connected once")
	rig.queue_free()


func test_without_a_proxy_nothing_changes() -> void:
	var made := _rig(["Body_Torso", "Body_Limbs", "Eyes"])
	var rig: ActorRig = made[0]
	var holder: Node = made[1]
	add_child(rig)
	assert_true(rig.shadow_proxy == null, "no ShadowProxy: the rig has none")
	for n: String in ["Body_Torso", "Body_Limbs", "Eyes"]:
		assert_eq((holder.get_node(n) as MeshInstance3D).cast_shadow, ON, "%s casts as before" % n)
	assert_eq(_mesh("Hair_late", holder).cast_shadow, ON, "and a mesh joining later too")
	assert_eq(holder.child_entered_tree.get_connections().size(), 0, "nothing is connected")
	assert_true(RigPaint.use_shadow_proxy(null) == null, "no root, no proxy")
	# A node named ShadowProxy that is not a mesh with a mesh is no proxy.
	var empty := MeshInstance3D.new()
	empty.name = "ShadowProxy"
	holder.add_child(empty)
	assert_true(RigPaint.use_shadow_proxy(rig) == null, "a ShadowProxy without a mesh is not used")
	assert_eq((holder.get_node("Body_Torso") as MeshInstance3D).cast_shadow, ON, "and nothing changed")
	rig.queue_free()


func test_the_box_rigs_and_the_giants_model_as_they_are_today() -> void:
	# An enemy's box rig has no proxy: its meshes cast as they did.
	var soldier := (load("res://scenes/enemies/soldier.tscn") as PackedScene).instantiate()
	var rig := soldier.get_node_or_null("Visual") as ActorRig
	assert_true(rig != null, "the soldier's rig")
	if rig != null:
		rig._ready()
		assert_true(rig.shadow_proxy == null, "a box rig has no shadow proxy")
	soldier.free()
	# The giant's model: with P48's ShadowProxy the rule holds on the real meshes; without it, nothing changes.
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	var holder_rig := ActorRig.new()
	holder_rig.process_mode = Node.PROCESS_MODE_DISABLED
	holder_rig.add_child(model)
	add_child(holder_rig)
	var proxy := model.find_child(RigPaint.SHADOW_PROXY, true, false) as MeshInstance3D
	var casting := 0
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in meshes:
		if mi != proxy and mi.visible and mi.cast_shadow != OFF:
			casting += 1
	if proxy != null:
		print("    test_giant_shadow_proxy: the model has its ShadowProxy (%d surfaces)" % proxy.mesh.get_surface_count())
		assert_true(holder_rig.shadow_proxy == proxy and proxy.cast_shadow == ONLY, "the rig uses the model's own proxy")
		assert_eq(casting, 0, "no shown mesh of the default look casts beside it")
		assert_true(proxy.mesh.get_surface_count() == 1, "the proxy is one surface: one draw a cascade")
	else:
		print("    test_giant_shadow_proxy: the model has no ShadowProxy yet (P48's): the rule is measured on a stand-in")
		assert_true(holder_rig.shadow_proxy == null, "no proxy in the model: the rig has none")
		assert_true(casting >= 9, "and the shown meshes cast as in 0.10.0-m10 (%d)" % casting)
	holder_rig.queue_free()


## The probe's reports, one for each of `splits` (one child process for them all).
func _probe(splits: Array) -> Array:
	var args := PackedStringArray(["-a", "-s", "-screen 0 640x360x24", OS.get_executable_path(),
		"--path", ProjectSettings.globalize_path("res://"), "--rendering-driver", "opengl3", "--resolution", "320x240",
		"--audio-driver", "Dummy", "-s", PROBE, "--", "--splits=" + ",".join(splits.map(func(n: int) -> String: return str(n)))])
	var output: Array = []
	var code := OS.execute("xvfb-run", args, output, true)
	var text := "\n".join(output)
	var reports: Array = []
	for l in text.split("\n"):
		if l.begins_with(PREFIX):
			var r: Variant = JSON.parse_string(l.substr(PREFIX.length()).strip_edges())
			if typeof(r) == TYPE_DICTIONARY:
				reports.append(r)
	assert_eq(code, 0, "the probe ran (exit %d)" % code)
	assert_eq(reports.size(), splits.size(), "it reported each shadow mode: %s" % text.right(600))
	return reports


func test_the_shadow_pass_draws_one_mesh_of_the_giant() -> void:
	if not _have("xvfb-run"):
		print("    test_giant_shadow_proxy: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	for r: Dictionary in _probe([1, 4]):
		var splits := int(r.splits)
		var shown := int(r.shown_surfaces)
		var all_shadow := int(r.all) - int(r.empty) - shown          # without the proxy: the shadow passes' draws
		var colour := int(r.unlit) - int(r.empty)                     # the colour pass at the end: shown + the two joined
		var proxy_shadow := int(r.proxy) - int(r.empty) - shown       # with it
		assert_true(shown >= 9 and int(r.proxy_surfaces) == 1, "the default look's %d surfaces; the proxy is one" % shown)
		assert_eq(all_shadow, splits * shown, "%d map(s), no proxy: every shown surface again in each (%d draws)" % [splits, all_shadow])
		assert_eq(proxy_shadow, splits * int(r.proxy_surfaces), "%d map(s), the proxy: ONE shadow draw in each (%d)" % [splits, proxy_shadow])
		assert_eq(r.casting, ["ShadowProxy"], "only the proxy casts")
		assert_true(bool(r.proxy_shadows_only), "and it is shadows only: the colour pass does not draw it")
		assert_eq(int(r.late) - int(r.proxy), int(r.join_surfaces), "a mesh joining later: its colour draw, no shadow draw")
		assert_eq(int(r.cape) - int(r.late), int(r.join_surfaces) * (1 + splits), "a cape joining: its colour draw and its own shadow in each map")
		assert_eq(colour, shown + 2 * int(r.join_surfaces), "with the sun's shadows off: the colour pass alone")
		if not bool(r.stand_in):
			assert_true(bool(r.rig_found_proxy_at_ready), "the rig found the model's own proxy by itself")
		print("    test_giant_shadow_proxy: %d shadow map(s): %d shadow draws without the proxy, %d with it (%s; %d surfaces shown) on %s" % [
			splits, all_shadow, proxy_shadow, "a stand-in proxy" if bool(r.stand_in) else "the model's own proxy", shown, str(r.get("adapter", "?"))])

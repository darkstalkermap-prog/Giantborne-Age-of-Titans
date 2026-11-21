extends TestSuite
## P60 (plan M11 §2.9, decision 12): PersonLook and the person_role records. Pure: no scene, no model.
##   * the four role records validate and name variants P59 built; the enemy records that are people carry a body
##     whose role exists, and every role's gear is a piece of P59's gear;
##   * a look is a function of the id: the same id the same variant and palette row, the hash of the id string
##     (no random stream); variants and rows spread over the role's pool;
##   * the crowd's palette texture holds the rows' colours in columns 0-2 and the factions' in column 3, in
##     factions_of()'s order, so the skinned body and its crowd instance show the same colours;
##   * a record's palette override wins on the skinned body.

const SCHEMA := preload("res://scripts/core/schemas/person_role_schema.gd")
const PEOPLE := ["enemy.soldier", "enemy.archer", "enemy.mage", "enemy.pikeman", "enemy.shieldman", "enemy.bannerman",
	"enemy.iron_guard", "enemy.siege_crew"]


func test_the_role_records_and_the_bodies() -> void:
	var index: Dictionary = PersonModel.index().get("roles", {})
	for id: String in ["person_role.soldier", "person_role.archer", "person_role.mage", "person_role.crew"]:
		var r := PersonLook.role_record(id)
		assert_false(r.is_empty(), "%s exists" % id)
		var ar := PersonLook.asset_role(id)
		assert_true(index.has(ar), "%s draws from P59's %s" % [id, ar])
		for v: Variant in r.get("variants", []):
			assert_true((index[ar].variants as Array).has(v), "%s: %s is one of P59's variants" % [id, v])
		assert_eq(PersonLook.factions_of(id)[0], "default", "%s: the default faction first" % id)
	for id: String in PEOPLE:
		var body: Variant = GameData.get_record(id).get("body")
		assert_true(typeof(body) == TYPE_DICTIONARY, "%s has a body" % id)
		assert_false(PersonLook.role_record(str(body.role)).is_empty(), "%s: its role exists" % id)
		for p: Variant in body.get("gear", []):
			assert_true(SCHEMA.GEAR.has(p) and PersonModel.gear_mesh(str(p)) != null, "%s: %s is a piece of P59's gear" % [id, p])
	var bad := DataValidator.validate_record({"schema_version": 1, "id": "person_role.bad", "type": "person_role",
		"asset_role": "soldier", "variants": [], "palette": {"skin": ["red"], "hair": [], "cloth": ["#000000"]},
		"factions": {"x": "#00000"}}, "test")
	assert_true(bad.errors.size() >= 4, "a broken role record is refused (%s)" % ", ".join(bad.errors))


func test_a_look_is_the_ids() -> void:
	var a := PersonLook.spec({"role": "person_role.soldier"}, "valley.soldier_3", "", 1.8, {})
	for i in 3:
		assert_eq(PersonLook.spec({"role": "person_role.soldier"}, "valley.soldier_3", "", 1.8, {}), a, "the same id, the same look")
	assert_eq(str(a.variant), str(["soldier_a", "soldier_b", "soldier_c"][absi(hash("valley.soldier_3")) % 3]),
		"the variant by the id's hash")
	var variants := {}
	var rows := {}
	for i in 40:
		var s := PersonLook.spec({"role": "person_role.soldier"}, "test.crowd_member_%d" % (i * 13), "", 1.8, {})
		variants[s.variant] = true
		rows[s.row] = true
	assert_eq(variants.size(), 3, "the pool's three variants all drawn")
	assert_true(rows.size() >= 8, "rows spread (%d of %d)" % [rows.size(), PersonLook.PALETTE_ROWS])
	var dflt := PersonLook.spec({}, "test.x", "", 1.8, {"person_role": "person_role.mage", "gear": ["staff"]})
	assert_eq(str(dflt.person_role), "person_role.mage", "no body: the scene's default role")
	assert_eq(dflt.gear, ["staff"], "and gear")


func test_the_palette_texture_matches_the_skinned_colours() -> void:
	var role := "person_role.soldier"
	var img := PersonLook.palette_image(role)
	var factions := PersonLook.factions_of(role)
	assert_true(img.get_width() == 4 and img.get_height() >= PersonLook.PALETTE_ROWS, "4 x rows")
	for row in [0, 5, 15]:
		var c := PersonLook.row_colors(role, row)
		for i in 3:
			var want: Color = [c.skin, c.hair, c.cloth][i]
			assert_true(img.get_pixel(i, row).is_equal_approx(want), "row %d column %d" % [row, i])
	for i in factions.size():
		assert_true(img.get_pixel(3, i).is_equal_approx(PersonLook.faction_color(role, factions[i])), "faction %s" % factions[i])
	var s := PersonLook.spec({"role": role, "palette": {"cloth": "#102030"}}, "test.p", "skarn", 1.8, {})
	assert_true((s.palette.cloth as Color).is_equal_approx(Color.html("#102030")), "a record's override wins")
	assert_eq(int(s.faction_row), factions.find("skarn"), "the faction's row")
	var m := ShaderMaterial.new()
	PersonLook.apply(m, s)
	assert_true((m.get_shader_parameter("cloth_color") as Color).is_equal_approx(Color.html("#102030")), "applied")

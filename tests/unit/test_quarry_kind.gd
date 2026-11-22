extends TestSuite
## A3: the quarry's terrain and works (tools/world/features.gd's "quarry", tools/world/kinds/quarry.gd): the pit's
## heights (the floor, each bench behind its cut face), the terraced faces stand only where the bench above them is
## cut, and every style makes parts (the crane broken and whole, the cart overturned and loaded) and its solids.

const K := preload("res://tools/world/kinds/quarry.gd")
const BENCHES := [[9.0, 7.0], [9.0, 7.0], [10.0, 7.0]]


func test_the_pits_heights() -> void:
	assert_eq(WorldFeatures.quarry_height(0.0, 34.0, 10.5, 3.0, BENCHES), 10.5, "the floor")
	assert_eq(WorldFeatures.quarry_height(34.0, 34.0, 10.5, 3.0, BENCHES), 10.5, "the floor's edge")
	assert_near(WorldFeatures.quarry_height(35.5, 34.0, 10.5, 3.0, BENCHES), 14.0, 0.01, "half up the first face")
	assert_eq(WorldFeatures.quarry_height(40.0, 34.0, 10.5, 3.0, BENCHES), 17.5, "the first bench")
	assert_eq(WorldFeatures.quarry_height(50.0, 34.0, 10.5, 3.0, BENCHES), 24.5, "the second")
	assert_eq(WorldFeatures.quarry_height(60.0, 34.0, 10.5, 3.0, BENCHES), 31.5, "the third")


func test_the_faces_stand_where_a_bench_is_cut() -> void:
	# a field: high ground (40 m) to the west (x < 0), low (5 m) to the east
	var f := HeightField.make(Vector2(-100, -100), 4.0, Vector2i(51, 51))
	for j in f.size.y:
		for i in f.size.x:
			f.h[j * f.size.x + i] = 40.0 if f.world_x(i) < 0.0 else 5.0
	var el := {"kind": "quarry", "style": "terrace", "id": "test.quarry.face", "pos": [0, 0], "y": 10.0, "radius": 30.0,
		"height": 7.0, "thick": 3.6, "from_deg": 0.0, "to_deg": 360.0, "seg_m": 7.0}
	var ctx := {"field": f, "frame": Transform3D(Basis(), Vector3(0, 10.0, 0))}
	var solids: Array = K.solids(el, ctx)
	assert_true(solids.size() > 6, "faces on the high side (%d)" % solids.size())
	for s: Dictionary in solids:
		assert_true((s.center as Vector3).x < 2.0, "none on the low side (%s)" % [s.center])
	assert_true(K.parts(el, ctx).size() >= solids.size() * 2, "each face two courses (and now and then a block)")


func test_every_style_has_parts() -> void:
	for el: Dictionary in [{"style": "crane", "size": [14]}, {"style": "crane", "size": [14], "broken": true},
			{"style": "shed", "size": [9, 4.5, 5]}, {"style": "blocks", "size": [7, 3, 4], "id": "a"},
			{"style": "cart", "size": [4.5], "loaded": true}, {"style": "cart", "size": [4.5], "overturned": true},
			{"style": "spoil", "size": [10, 4, 8], "id": "b"}]:
		assert_true(K.parts(el, {}).size() >= 3, "%s has its parts" % [el])
	assert_eq(K.solids({"style": "cart"}, {}).size(), 0, "a cart is no wall")
	assert_eq(K.solids({"style": "crane", "size": [14]}, {}).size(), 1, "a crane's mast is solid")

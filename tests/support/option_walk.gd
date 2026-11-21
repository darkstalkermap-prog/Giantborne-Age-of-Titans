class_name OptionWalk
extends RefCounted
## Every option of every set applied to the real model with its materials built (P42's walk in
## tests/integration/test_giant_look_real.gd, P57: shared with the slow tier's tests/slow/test_giant_look_walks.gd):
## through Appearance.to_look and GiantLook.apply, validate() empty and the hair, beard and garment meshes shown as
## the look says. `sample` walks only the first and the last option of each set (the default tier's share, plan M11
## §1.7 rule 2). Returns the number of options walked.


static func every_option(t: TestSuite, _root: Node3D, index: Dictionary, sample: bool) -> int:
	var n := 0
	# P57: Part B's sets too - the garments in their slots, the metals, the build and face sliders at their ends, the
	# accessories in their slots, the beads on the hair and the beard
	for c: String in Appearance.ALL_CATEGORIES:
		var ids := Appearance.option_ids(c)
		for k in ids.size():
			var id := ids[k]
			if sample and k != 0 and k != ids.size() - 1:
				continue
			var o := Appearance.option(id)
			var line := Appearance.required_ancestry(o)
			var r := Appearance.default_record()
			match c:
				"skin", "eyes":
					r[c] = id
				"hair":
					r.hair.style = id
				"haircolor":
					r.hair.color = id
				"beard":
					r.beard.style = id
				"tattoo":
					r.tattoos[str(o.region)] = id
				"ink":
					r.tattoos.arms = "tattoo.arm_bands"
					r.tattoos.ink = id
				"paint":
					r = Appearance.with_paint(r, id)   # P53: the paint in its place (face or body)
				"paintcolor":
					r = Appearance.with_paint(r, "paint.face_stripes")
					r.paint.color = id
				"scar":
					r.scars = [id]
				"outfit":
					r = Appearance.with_outfit(r, id)   # P53: an outfit fills the slots
				"dye":
					r.outfit.dyes.cloth = id   # P53: M10's primary dye is the cloth dye
				"garment":
					r = OptionRows.with_value(r, "outfit.slots.%s.item" % str(o.get("slot", "")), id)
				"metal":
					r.outfit.dyes.metal = id
				"accessory":
					r = OptionRows.with_value(r, "outfit.accessories." + str(o.get("slot", "")), id)
				"bead":
					r.hair.beads = id
					r.beard.beads = id
				"build", "face":
					r = OptionRows.with_value(r, "%s.%s" % [c, str(o.get("key", ""))], 1.0 if k % 2 == 0 else -1.0)
			var look := Appearance.to_look(r, line if line != "" else "ancestry.stoneblood")
			GiantLook.apply(_root, index, look)
			t.assert_eq(GiantLook.validate(_root, index, look), PackedStringArray(), "%s: validate() is empty" % id)
			# P54: a head garment hides the hair or cuts it by length (its index entry's hides_hair, hair_cut)
			var cut := GiantLook.hair_cut(index, GiantLook.garment_meshes(index, look).keys())
			for m: String in GiantLook.meshes_of(index, "hair"):
				t.assert_eq(GiantLook.mesh_node(_root, index, m).visible, m == str(look.hair_mesh) and float(cut.get(m, 1.0)) > 0.0,
					"%s: %s's visibility" % [id, m])
			for m: String in GiantLook.meshes_of(index, "beard"):
				t.assert_eq(GiantLook.mesh_node(_root, index, m).visible, m == str(look.beard_mesh), "%s: %s's visibility" % [id, m])
			var shown := {}
			for g: Variant in look.garments:
				for m: Variant in index.garments.get(Appearance.garment_id(g), []):
					shown[str(m)] = true
			for m: String in GiantLook.meshes_of(index, "garment"):
				t.assert_eq(GiantLook.mesh_node(_root, index, m).visible, shown.has(m), "%s: %s's visibility" % [id, m])
			for m: String in GiantLook.meshes_of(index, "accessory"):
				t.assert_eq(GiantLook.mesh_node(_root, index, m).visible, (look.get("accessories", []) as Array).has(m),
					"%s: %s's visibility" % [id, m])
			n += 1
	return n

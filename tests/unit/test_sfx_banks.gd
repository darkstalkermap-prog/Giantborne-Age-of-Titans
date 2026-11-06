extends TestSuite
## P21 (plan M6-M9 §3.3 bank tests, §4.4, §4.5, decision 8): the effect banks - their families,
## variants, buses, classes, caps, guards and priorities; the far versions of big sounds; every
## file generated, mono, at most 2.0 s, at 22.05 kHz (32 kHz only for bright metal); the size
## budget (the effects at most 0.95 MB imported) and the Valley's registered seconds (at most
## 110); and the threat family kept apart from the impacts (§4.2 F: a higher spectral RMS
## frequency than any hit and a later peak - threat cues swell, impacts strike and decay).
## Reads data and WAV bytes only (no audio engine needed).

## Each P21 bank and the cue-id prefixes it holds.
const BANKS := {
	"audio_bank.combat": ["sfx.hit.", "sfx.block.", "sfx.parry", "sfx.guard_break", "sfx.clank.", "sfx.body.",
		"sfx.swing.", "sfx.dodge.", "sfx.jump"],
	"audio_bank.abilities": ["sfx.ability.", "sfx.impact.", "sfx.projectile.", "sfx.status.", "sfx.grab.",
		"sfx.voice.giant.roar"],
	"audio_bank.steps": ["sfx.step."],
	"audio_bank.voices": ["sfx.voice.", "sfx.player."],
	"audio_bank.threat": ["sfx.threat."],
	"audio_bank.world": ["sfx.crack.", "sfx.break.", "sfx.world."],
	"audio_bank.ui": ["sfx.ui."],
}
## The generator families whose files the banks name (manifest "family").
const FAMILIES := ["combat", "abilities", "steps", "voices", "threat", "world", "ui"]
const SFX_BUDGET_BYTES := 0.95 * 1024.0 * 1024.0
const QOA_IMPORT_BYTES := 370
const VALLEY_CAP_S := 110.0
const SFX_MAX_S := 2.0
## Rendered at 32 kHz: the bright metal (§4.5).
const METAL_FILES := ["hit_armor_", "block_guard_", "parry_", "guard_break_"]
## Cues only the giant plays, at its own body: non-positional by design (at its chest or weapon
## a 3D voice sits at max_db whatever its volume, so their balance needs 2D voices).
const GIANT_ONLY := ["sfx.player.", "sfx.dodge.", "sfx.jump", "sfx.block.raise", "sfx.block.player", "sfx.grab.",
	"sfx.status.", "sfx.voice.giant.", "sfx.world.growth", "sfx.world.forge_upgrade"]
const GIANT_ABILITY_SUFFIXES := ["cast", "on", "roar"]


static func p21_banks() -> Array:
	var out: Array = []
	for id: String in BANKS:
		var rec := GameData.get_record(id)
		if not rec.is_empty():
			out.append(rec)
	return out


## Every cue of the P21 banks: cue id -> cue (with "bank").
static func p21_cues() -> Dictionary:
	var out := {}
	for bank: Dictionary in p21_banks():
		for cue_id: String in bank.cues:
			var c: Dictionary = (bank.cues[cue_id] as Dictionary).duplicate()
			c["bank"] = str(bank.id)
			out[cue_id] = c
	return out


static func p21_files() -> PackedStringArray:
	var out := PackedStringArray()
	for cue: Dictionary in p21_cues().values():
		for f: Variant in cue.files:
			if not out.has(str(f)):
				out.append(str(f))
	return out


static func _giant_only(cue_id: String) -> bool:
	for prefix: String in GIANT_ONLY:
		if cue_id.begins_with(prefix):
			return true
	if cue_id.begins_with("sfx.ability."):
		var parts := cue_id.split(".")
		var library: Array = GameData.get_record("progression.default").get("ability_library", [])
		var short := parts[2]
		var known := short == "default" or short == "grab_hold" or short == "throw_held"
		for id: Variant in library:
			if AudioMath.short_id(str(id)) == short:
				known = true
		return known and parts.size() == 4 and GIANT_ABILITY_SUFFIXES.has(parts[3])
	return false


# --------------------------------------------------------------------------- the banks

func test_the_seven_banks_ship_and_hold_their_families() -> void:
	var cues := p21_cues()
	assert_eq(p21_banks().size(), 7, "the seven effect banks ship")
	assert_true(cues.size() >= 200, "they hold the library (%d cues)" % cues.size())
	for bank: Dictionary in p21_banks():
		var prefixes: Array = BANKS[str(bank.id)]
		for cue_id: String in bank.cues:
			var ok := false
			for p: String in prefixes:
				ok = ok or cue_id.begins_with(p)
			assert_true(ok, "%s belongs in %s" % [cue_id, bank.id])
	var placeholder: Dictionary = GameData.get_record("audio_bank.placeholder").get("cues", {})
	for cue_id: String in placeholder:
		assert_false(cue_id.begins_with("sfx."), "the placeholder bank no longer holds effects (%s)" % cue_id)


func test_variants_buses_classes_and_spatial_use() -> void:
	var classes: Dictionary = GameData.get_record("audio_mix.default").classes
	var cues := p21_cues()
	for cue_id: String in cues:
		var c: Dictionary = cues[cue_id]
		var files: Array = c.files
		assert_true(files.size() >= 1 and files.size() <= 4, "%s has 1-4 variants (%d)" % [cue_id, files.size()])
		var ui := cue_id.begins_with("sfx.ui.")
		assert_eq(str(c.bus), "UI" if ui else "SFX", "%s plays on its bus" % cue_id)
		if ui:
			assert_false(bool(c.spatial), "%s is an interface cue (2D)" % cue_id)
		elif bool(c.spatial):
			assert_true(classes.has(str(c.get("class", ""))), "%s names a mix class" % cue_id)
		else:
			assert_true(_giant_only(cue_id), "%s is non-positional only because the giant alone plays it" % cue_id)


func test_caps_guards_and_priorities_follow_the_mix() -> void:
	var cues := p21_cues()
	for cue_id: String in cues:
		var c: Dictionary = cues[cue_id]
		var cap := int(c.max_voices)
		var retrig := int(c.retrigger_ms)
		var prio := int(c.priority)
		assert_true(retrig >= 30 and retrig <= 1500, "%s guards retriggers for 30-1500 ms (%d)" % [cue_id, retrig])
		if cue_id.begins_with("sfx.step.giant_"):
			assert_true(cap <= 2 and prio <= 50, "the giant's footfalls: 2 voices, priority 50 or less (%s)" % cue_id)
		elif cue_id.begins_with("sfx.step."):
			assert_true(cap <= 6 and prio <= 40, "other footfalls: 6 voices, priority 40 or less (%s)" % cue_id)
		elif cue_id.begins_with("sfx.hit."):
			assert_true(cap <= 8, "impacts: 8 voices (%s)" % cue_id)
		elif cue_id.begins_with("sfx.swing."):
			assert_true(cap <= 4, "swings: 4 voices (%s)" % cue_id)
		elif cue_id.begins_with("sfx.voice."):
			assert_true(cap <= 3, "a voice: 3 per archetype (%s)" % cue_id)
		elif cue_id.begins_with("sfx.threat."):
			assert_true(cap <= 2 and prio >= 80, "threat cues: 2 voices, priority 80 or more (%s)" % cue_id)
		elif cue_id.begins_with("sfx.ui."):
			assert_true(cap <= 4 and prio <= 50, "interface cues: 4 voices, priority 50 or less (%s)" % cue_id)
	for cue_id: String in ["sfx.threat.sting", "sfx.threat.aim_lock", "sfx.player.hurt", "sfx.player.hurt.heavy",
			"sfx.player.death"]:
		assert_eq(int((cues[cue_id] as Dictionary).priority), 100, "%s takes priority 100 (§4.4)" % cue_id)


func test_big_sounds_have_quieter_far_versions() -> void:
	var cues := p21_cues()
	var with_far := 0
	for cue_id: String in cues:
		var c: Dictionary = cues[cue_id]
		var far := str(c.far)
		if far == "":
			continue
		with_far += 1
		assert_true(["big", "giant", "boss"].has(str(c.get("class", ""))), "%s: far versions are for big, giant and boss cues" % cue_id)
		assert_true(cues.has(far), "%s's far version %s exists" % [cue_id, far])
		if cues.has(far):
			assert_eq(str((cues[far] as Dictionary).far), "", "%s does not chain further" % far)
	for cue_id: String in ["sfx.impact.stomp", "sfx.step.heavy.soft", "sfx.voice.ogre_king.roar", "sfx.break.wood.large",
			"sfx.break.stone.large"]:
		assert_true(str((cues[cue_id] as Dictionary).far) != "", "%s has a far version" % cue_id)
	assert_true(with_far >= 10, "big sounds carry far versions (%d)" % with_far)


# --------------------------------------------------------------------------- files and budget

func test_files_are_generated_mono_and_short() -> void:
	var files := p21_files()
	assert_true(files.size() >= 200, "the banks name the library (%d files)" % files.size())
	for path in files:
		var e := AudioMath.manifest_entry(path)
		assert_false(e.is_empty(), "%s was generated (in the manifest)" % path)
		if e.is_empty():
			continue
		assert_true(FAMILIES.has(str(e.family)), "%s comes from a P21 generator (%s)" % [path, e.family])
		assert_eq(str(e.kind), "sfx", "%s is a sample" % path)
		assert_eq(int(e.channels), 1, "%s is mono" % path)
		assert_true(float(e.seconds) <= SFX_MAX_S + 1e-6, "%s is at most 2.0 s (%.2f)" % [path, float(e.seconds)])
		if str(e.family) == "threat":
			assert_true(float(e.seconds) >= 0.2 and float(e.seconds) <= 0.6, "%s, a threat cue, lasts 0.2-0.6 s (%.2f)" % [
				path, float(e.seconds)])
		var metal := false
		for m: String in METAL_FILES:
			metal = metal or path.get_file().begins_with(m)
		assert_eq(int(e.rate), 32000 if metal else 22050, "%s at its rate" % path)


func test_the_budget_and_the_valleys_registered_seconds_hold() -> void:
	var manifest_files: Dictionary = AudioMath.manifest().get("files", {})
	var bytes := 0.0
	var seconds := 0.0
	var count := 0
	for path: String in manifest_files:
		var e: Dictionary = manifest_files[path]
		if not FAMILIES.has(str(e.family)):
			continue
		var frames := int(e.frames)
		bytes += float(int(e.channels) * (8 + 24 * ceili(frames / 5120.0) + 8 * ceili(frames / 20.0)) + QOA_IMPORT_BYTES)
		seconds += float(e.seconds)
		count += 1
	assert_true(bytes <= SFX_BUDGET_BYTES, "the effects import within 0.95 MB (%.3f MB, %d files, %.1f s)" % [
		bytes / 1048576.0, count, seconds])
	var valley := Audio.sample_paths_for("level.valley")
	var registered := 0.0
	for path in valley:
		registered += float(AudioMath.manifest_entry(path).get("seconds", 0.0))
	assert_true(registered <= VALLEY_CAP_S, "the Valley registers at most 110 s of samples (%.1f s)" % registered)
	var lookup := {}
	for path in valley:
		lookup[path] = true
	for path in p21_files():
		if not lookup.has(path):
			fail("%s is not registered for the Valley (every effect is global)" % path)
			break


# --------------------------------------------------------------------------- threat cues stand apart

## {"rate", "f_rms" (Hz: the spectrum's RMS frequency, from the energy of the first difference),
## "onset_s" (where the 5 ms RMS envelope peaks)} of a 16-bit mono WAV master.
static func features(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	var rate := 22050
	var pos := 12
	var data := PackedByteArray()
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size := bytes.decode_u32(pos + 4)
		if id == "fmt ":
			rate = bytes.decode_u32(pos + 12)
		elif id == "data":
			data = bytes.slice(pos + 8, pos + 8 + size)
			break
		pos += 8 + size + (size % 2)
	data.resize(data.size() - data.size() % 4)   # whole words (an odd last sample is dropped)
	var words := data.to_int32_array()   # two samples per word (little-endian)
	var win := maxi(1, int(0.005 * rate))
	var e2 := 0.0
	var d2 := 0.0
	var prev := 0.0
	var acc := 0.0
	var n := 0
	var best := -1.0
	var best_at := 0
	for w in words:
		for k in 2:
			var s := float((((w & 0xFFFF) ^ 0x8000) - 0x8000) if k == 0 else (w >> 16)) / 32767.0
			e2 += s * s
			d2 += (s - prev) * (s - prev)
			prev = s
			acc += s * s
			n += 1
			if n % win == 0:
				if acc > best:
					best = acc
					best_at = n - win
				acc = 0.0
	var ratio := d2 / maxf(e2, 1e-12)
	var f_rms := acos(clampf(1.0 - ratio * 0.5, -1.0, 1.0)) * float(rate) / TAU
	return {"rate": rate, "f_rms": f_rms, "onset_s": float(best_at) / float(rate)}


func test_threat_cues_stand_apart_from_the_impacts() -> void:
	var threat: Array = []
	var hits: Array = []
	var cues := p21_cues()
	for cue_id: String in cues:
		var c: Dictionary = cues[cue_id]
		if cue_id.begins_with("sfx.threat.") and not cue_id.ends_with(".default") and cue_id != "sfx.threat.windup":
			threat.append_array(c.files)
		elif cue_id.begins_with("sfx.hit.") and not cue_id.ends_with(".default") and cue_id != "sfx.hit.iron":
			hits.append_array(c.files)
	assert_true(threat.size() >= 8 and hits.size() >= 10, "both families measured (%d threat, %d hit files)" % [threat.size(), hits.size()])
	var max_hit_f := 0.0
	var max_hit_onset := 0.0
	var hit_mean := 0.0
	var seen := {}
	for path: String in hits:
		if seen.has(path):
			continue
		seen[path] = true
		var f := features(path)
		max_hit_f = maxf(max_hit_f, float(f.f_rms))
		max_hit_onset = maxf(max_hit_onset, float(f.onset_s))
		hit_mean += float(f.f_rms)
	hit_mean /= maxf(float(seen.size()), 1.0)
	var threat_mean := 0.0
	var threat_seen := {}
	for path: String in threat:
		if threat_seen.has(path):
			continue
		threat_seen[path] = true
		var f := features(path)
		threat_mean += float(f.f_rms)
		assert_true(float(f.f_rms) > max_hit_f * 1.2, "%s sits above every hit in frequency (%d Hz vs %d Hz)" % [
			path.get_file(), int(f.f_rms), int(max_hit_f)])
		assert_true(float(f.onset_s) >= 0.06, "%s swells (its peak at %d ms)" % [path.get_file(), int(float(f.onset_s) * 1000.0)])
	threat_mean /= maxf(float(threat_seen.size()), 1.0)
	assert_true(max_hit_onset <= 0.04, "every hit strikes at once (latest peak %d ms)" % int(max_hit_onset * 1000.0))
	assert_true(threat_mean >= 3.0 * hit_mean, "the threat family's mean RMS frequency is at least 3 x the hits' (%d vs %d Hz)" % [
		int(threat_mean), int(hit_mean)])

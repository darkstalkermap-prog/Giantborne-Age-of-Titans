extends SceneTree
## The world's seam check (P25; plan M6-M9 §3.8, §5.3): tools/check.sh runs it after a build that ran
## the world builder. For each chunk named (and its eight neighbours; every chunk without names):
## the heights and the one-sample aprons agree across each of its seams, and no walkable face within
## 8 m of a chunk border is steeper than 35 degrees (cliffs over 45 degrees and the rim excepted, the
## builder's rule). Reads assets/world/chunks only (ChunkData; no autoloads):
##
##   godot --headless --path . -s res://tools/world/seam_check.gd -- [--chunks=c2_6,c3_6]
##
## Prints "SEAM_CHECK ok: <n> chunks, <m> seams" or "SEAM_CHECK FAILED: <what>" and exits 0 / 1.
## Tools only (tools/ is never exported).

const CHUNK_DIR := "res://assets/world/chunks/"
const GRID := Vector2i(8, 8)
const CHUNK_M := 256.0
const INTERIOR := 896.0
## The walkable notches in the south rim (world.json's rim: the Kingsgate shelf, the Broken Stair).
const NOTCHES := [Rect2(-335, 892, 70, 53), Rect2(-62, 892, 44, 50)]
const BAND_M := 8.0
const RULE_DEG := 35.05
const CLIFF_DEG := 45.0
const TOLERANCE_M := 0.0005


func _initialize() -> void:
	var named := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--chunks="):
			for c in a.trim_prefix("--chunks=").split(",", false):
				named.append(c.strip_edges())
	var r := check(named)
	if bool(r.ok):
		print("SEAM_CHECK ok: %d chunks, %d seams" % [r.chunks, r.seams])
		quit(0)
	else:
		print("SEAM_CHECK FAILED: " + "; ".join(r.problems as PackedStringArray))
		quit(1)


## {"ok", "chunks", "seams", "problems": PackedStringArray} for the named chunks and their
## neighbours (every chunk when `named` is empty).
static func check(named: PackedStringArray) -> Dictionary:
	var wanted := {}
	for z in GRID.y:
		for x in GRID.x:
			wanted[Vector2i(x, z)] = named.is_empty()
	for id in named:
		var c := _coords(id)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var n := c + Vector2i(dx, dz)
				if wanted.has(n):
					wanted[n] = true
	var chunks := {}
	var problems := PackedStringArray()
	for c: Vector2i in wanted:
		if not bool(wanted[c]):
			continue
		var d := load("%sc%d_%d.res" % [CHUNK_DIR, c.x, c.y]) as ChunkData
		if d == null:
			problems.append("c%d_%d does not load" % [c.x, c.y])
			continue
		chunks[c] = d
	var seams := 0
	for c: Vector2i in chunks:
		var a: ChunkData = chunks[c]
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var b: ChunkData = chunks.get(c + step)
			if b == null:
				continue
			seams += 1
			for k in a.inner():
				var t := float(k) * a.spacing_m
				for off: float in [0.0, a.spacing_m]:
					var ha := a.height_at_local(CHUNK_M + off, t) if step.x == 1 else a.height_at_local(t, CHUNK_M + off)
					var hb := b.height_at_local(off, t) if step.x == 1 else b.height_at_local(t, off)
					if absf(ha - hb) > TOLERANCE_M:
						problems.append("%s / %s differ by %.3f m at %.0f m along the seam" % [a.chunk_id, b.chunk_id, absf(ha - hb), t])
						break
		var over := _steep_border_faces(a, c)
		if over != "":
			problems.append(over)
	return {"ok": problems.is_empty(), "chunks": chunks.size(), "seams": seams, "problems": problems}


## The first walkable face within BAND_M of one of the chunk's inner borders steeper than the rule
## ("" when none).
static func _steep_border_faces(d: ChunkData, c: Vector2i) -> String:
	var band := int(ceil(BAND_M / d.spacing_m))
	var m := d.inner() - 1
	for j in m:
		for i in m:
			var near_x := (c.x > 0 and i <= band) or (c.x < GRID.x - 1 and i >= m - 1 - band)
			var near_z := (c.y > 0 and j <= band) or (c.y < GRID.y - 1 and j >= m - 1 - band)
			if not near_x and not near_z:
				continue
			var cx := d.origin.x + (i + 0.5) * d.spacing_m
			var cz := d.origin.z + (j + 0.5) * d.spacing_m
			if not _walkable(cx, cz):
				continue
			var h00 := d.sample(i, j)
			var h10 := d.sample(i + 1, j)
			var h01 := d.sample(i, j + 1)
			var h11 := d.sample(i + 1, j + 1)
			var g := maxf(Vector2(h10 - h00, h11 - h10).length(), Vector2(h11 - h01, h01 - h00).length()) / d.spacing_m
			var deg := rad_to_deg(atan(g))
			if deg > RULE_DEG and deg <= CLIFF_DEG:
				return "%s: a walkable border face of %.1f degrees at (%.0f, %.0f) (the rule is 35)" % [d.chunk_id, deg, cx, cz]
	return ""


static func _walkable(x: float, z: float) -> bool:
	if absf(x) < INTERIOR and absf(z) < INTERIOR:
		return true
	for r: Rect2 in NOTCHES:
		if r.has_point(Vector2(x, z)):
			return true
	return false


static func _coords(id: String) -> Vector2i:
	var parts := id.trim_prefix("c").split("_")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-99, -99)
	return Vector2i(int(parts[0]), int(parts[1]))

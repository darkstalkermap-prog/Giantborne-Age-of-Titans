extends RefCounted
## The giant's far levels (the second W33 look lane; plan M11 §2.12: "at most 4,000 primitives beyond 120 m").
##
## The importer's LODs keep every mesh within about a pixel of its full shape, and for hair cards they barely reduce
## (a card is a strip of quads the simplifier cannot collapse): at 121 m, where the giant at stage 1 is about 47 px
## tall at 1920x1080, the Wanderer drew 10,952 primitives (5,942 of them the long hair's cards) and the fullest look
## 15,616. part_import.gd runs this on every part and on giant.glb's meshes when they are imported:
##
## - Every mesh gets one **far** level: the coarsest of the importer's levels whose key is at most FAR_ERROR_M and
##   that keeps at least FAR_LEAST_SHARE of the triangles, switched on at FAR_KEY (the importer's finer levels stay,
##   the coarser ones too). The renderer picks a level by its key against the distance and the viewport's pixels (the
##   key is the length the level may be off by; GeometryInstance3D.lod_bias and the model's scale scale it), so the
##   far level shows where the giant is under about 60 px tall: from about 85-100 m at stage 1 at 1920x1080 in the
##   creator's lens, nearer at a smaller window, farther at a larger stage.
## - A **hair or beard** mesh (cards: strips of two vertices a row; a braid's tube: rings of eight; a tie: two rings
##   of nine) gets its own levels instead of the importer's, which collapsed whole cards: STRAND_MID_KEY (every
##   strip with the rows that keep its middle line within STRAND_MID_TOL_M) and the far level (the strips that cover
##   the most, largest first, with the rows within FAR_ROW_TOL_M and a tube's ring as a triangle). Anything else in
##   such a mesh is kept whole.
##
## Index lists only: the vertices are the mesh's own, so a level costs its indices (2 bytes each) in the pack. Measured
## (tests/gate/test_giant_far_render.gd, 1920x1080): 1,722 primitives for the Wanderer and 2,981 for the fullest look
## at 121 m; the worst slot look's far levels sum to 3,641 triangles (tests/integration/test_giant_far_levels.gd).

## The key the far level is switched on at (a length in the mesh's units; see above).
const FAR_KEY := 0.045
## The coarsest importer level the far level may take (its key, in m: about 4 px at the switch; 0.4 drew the iron helm
## as a smaller cap) ...
const FAR_ERROR_M := 0.3
## ... keeping at least this share of the mesh's triangles and this many (a belt or a torc of a few triangles left
## the waist or the neck bare; the body's limbs at 1.5 % of theirs poked through the clothes in specks). A bead set
## (beads a few pixels across at most) keeps no share.
const FAR_LEAST_SHARE := 0.02
const FAR_LEAST_TRIS := 24
## A far level still over this share of the mesh's triangles (the importer stopped early: the wrapped sandals at a
## quarter) is thinned by clustering its vertices (index lists still: each cell's vertex nearest the cell's middle
## stands for it) to about FAR_CLUSTER_SHARE; a small mesh's far level (at most FAR_THIN_LEAST) is left as it is.
const FAR_MOST_SHARE := 0.1
const FAR_THIN_LEAST := 150
const FAR_CLUSTER_SHARE := 0.07
## A hair or beard mesh's middle level: its key and how far a strip's middle line may move.
const STRAND_MID_KEY := 0.02
const STRAND_MID_TOL_M := 0.004
## A hair or beard mesh's far level: the strips by area, largest first, until FAR_STRAND_AREA of their area or
## FAR_STRAND_TRIS triangles, each with the rows that keep its line within FAR_ROW_TOL_M.
const FAR_STRAND_AREA := 0.6
const FAR_STRAND_TRIS := 280
const FAR_ROW_TOL_M := 0.012
## The columns a tube's or a tie's ring keeps in the far level (of its eight or nine, the seam's twin last).
const FAR_RING_COLUMNS := 4


## `mesh` with its far levels (a new ArrayMesh of the same surfaces, vertex data, blend shapes and materials; only
## the "lods" of each surface differ), or `mesh` itself when it is not an ArrayMesh. `strands`: a hair or beard mesh
## (a shell style, without strips, takes the far level as any other mesh).
static func with_far_levels(mesh: Mesh, strands := false, least_share := FAR_LEAST_SHARE) -> Mesh:
	var am := mesh as ArrayMesh
	if am == null or am.get_surface_count() == 0:
		return mesh
	var surfaces: Array = am.get("_surfaces")
	var out_surfaces := []
	for s in surfaces.size():
		var d: Dictionary = (surfaces[s] as Dictionary).duplicate()
		var levels := _levels(d)
		var full_tris := int(d.get("index_count", 0)) / 3
		var strips := strips_of(am.surface_get_arrays(s)) if strands else []
		if not strips.is_empty():
			levels = _strand_levels(am.surface_get_arrays(s), strips)
		else:
			levels = far_level(levels, full_tris, least_share)
			levels = _thinned(levels, full_tris, am.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
			if levels.is_empty() and full_tris > FAR_LEAST_TRIS:
				levels = _from_whole(am.surface_get_arrays(s), full_tris)
		var flat := []
		for l: Array in levels:
			flat.append(float(l[0]))
			flat.append(_pack(l[1] as PackedInt32Array, _wide(d)))
		d["lods"] = flat
		out_surfaces.append(d)
	var out := ArrayMesh.new()
	out.resource_name = am.resource_name
	out.blend_shape_mode = am.blend_shape_mode
	for i in am.get_blend_shape_count():
		out.add_blend_shape(am.get_blend_shape_name(i))
	out.set("_surfaces", out_surfaces)
	out.custom_aabb = am.custom_aabb
	out.shadow_mesh = am.shadow_mesh
	return out


## A surface's levels as [[key, PackedInt32Array], ...], finest first.
static func _levels(d: Dictionary) -> Array:
	var out := []
	var lods: Array = d.get("lods", [])
	var wide := _wide(d)
	for i in range(0, lods.size() - 1, 2):
		out.append([float(lods[i]), _unpack(lods[i + 1] as PackedByteArray, wide)])
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return out


## The importer's levels with the far one (see the header) moved to FAR_KEY; the levels between FAR_KEY and it go.
static func far_level(levels: Array, full_tris: int, least_share := FAR_LEAST_SHARE) -> Array:
	var far := -1
	var least := maxi(FAR_LEAST_TRIS, ceili(full_tris * least_share))
	for i in levels.size():
		if float(levels[i][0]) <= FAR_ERROR_M and (levels[i][1] as PackedInt32Array).size() / 3 >= least:
			far = i
	if far < 0 or float(levels[far][0]) <= FAR_KEY:
		return levels
	var out := []
	for i in levels.size():
		var key := float(levels[i][0])
		if i < far and key < FAR_KEY * 0.9:
			out.append(levels[i])
		elif i == far:
			out.append([FAR_KEY, levels[i][1]])
		elif i > far:
			out.append(levels[i])
	return out


## `levels` with the level the renderer takes at FAR_KEY thinned by clustering when it keeps more than FAR_MOST_SHARE
## of the triangles (see the constants).
static func _thinned(levels: Array, full_tris: int, pos: PackedVector3Array) -> Array:
	var at := -1
	for i in levels.size():
		if float(levels[i][0]) <= FAR_KEY * 1.0001:
			at = i
	var src: PackedInt32Array = levels[at][1] if at >= 0 else PackedInt32Array()
	if at < 0 or src.size() / 3 <= maxi(FAR_THIN_LEAST, int(full_tris * FAR_MOST_SHARE)):
		return levels
	var target := maxi(FAR_LEAST_TRIS, int(full_tris * FAR_CLUSTER_SHARE))
	var box := AABB(pos[src[0]], Vector3.ZERO)
	for i in src:
		box = box.expand(pos[i])
	var lo := 0.0
	var hi := box.get_longest_axis_size() * 0.25
	var best := src
	for step in 18:
		var h := (lo + hi) * 0.5
		var out := clustered(src, pos, h)
		if out.size() / 3 > target:
			lo = h
		else:
			hi = h
			best = out
	var out_levels := []
	for i in levels.size():
		if i == at:
			out_levels.append([FAR_KEY, best])
		elif i < at and float(levels[i][0]) < FAR_KEY * 0.9:
			out_levels.append(levels[i])
		elif i > at and (levels[i][1] as PackedInt32Array).size() < best.size():
			out_levels.append(levels[i])
	return out_levels


## B1: a far level for a mesh the importer gave no level at all (a small mesh of separate flat-faced pieces: the
## Quarry set's heart-stone and its chain): the whole mesh clustered to about FAR_CLUSTER_SHARE x 3 of its triangles
## (at least FAR_LEAST_TRIS), at FAR_KEY. [] when clustering cannot thin it.
static func _from_whole(arrays: Array, full_tris: int) -> Array:
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if idx.is_empty():
		return []
	var target := maxi(FAR_LEAST_TRIS, int(full_tris * FAR_CLUSTER_SHARE * 3.0))
	var box := AABB(pos[idx[0]], Vector3.ZERO)
	for i in idx:
		box = box.expand(pos[i])
	var lo := 0.0
	var hi := box.get_longest_axis_size() * 0.25
	var best := PackedInt32Array()
	for step in 18:
		var h := (lo + hi) * 0.5
		var out := clustered(idx, pos, h)
		if out.size() / 3 > target:
			lo = h
		else:
			hi = h
			best = out
	if best.is_empty() or best.size() >= idx.size():
		return []
	return [[FAR_KEY, best]]


## The triangles `idx` with every vertex moved to its cell's representative (cells `h` wide; the vertex nearest the
## cell's middle, the lowest index on a tie), the collapsed and repeated triangles dropped.
static func clustered(idx: PackedInt32Array, pos: PackedVector3Array, h: float) -> PackedInt32Array:
	var cell_of := {}
	var sums := {}
	for i in idx:
		var c := Vector3i((pos[i] / h).floor())
		cell_of[i] = c
		if not sums.has(c):
			sums[c] = [Vector3.ZERO, 0]
		if true:
			var e: Array = sums[c]
			e[0] = (e[0] as Vector3) + pos[i]
			e[1] = int(e[1]) + 1
	var rep := {}
	var rep_d := {}
	var verts := cell_of.keys()
	verts.sort()
	for i: int in verts:
		var c: Vector3i = cell_of[i]
		var mid: Vector3 = (sums[c][0] as Vector3) / float(sums[c][1])
		var d := pos[i].distance_squared_to(mid)
		if not rep.has(c) or d < float(rep_d[c]):
			rep[c] = i
			rep_d[c] = d
	var out := PackedInt32Array()
	var seen := {}
	for t in range(0, idx.size(), 3):
		var a: int = rep[cell_of[idx[t]]]
		var b: int = rep[cell_of[idx[t + 1]]]
		var c: int = rep[cell_of[idx[t + 2]]]
		if a == b or b == c or a == c:
			continue
		var key := Vector3i(a, b, c)
		var m := mini(a, mini(b, c))
		key = Vector3i(b, c, a) if m == b else (Vector3i(c, a, b) if m == c else key)
		if seen.has(key):
			continue
		seen[key] = true
		out.append_array(PackedInt32Array([a, b, c]))
	return out


## The strips of a surface: [{"grid": [[vertex, ...] a row, ...], "sign", "area", "tris"}]. A strip is a connected
## piece whose vertices fall in rows of one V, each row of as many vertices of rising U, whose triangles join
## neighbouring rows and columns only: a card (two a row), a braid's tube (eight), a tie's bead ring (nine).
static func strips_of(arrays: Array) -> Array:
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	if idx.is_empty() or uv.size() != pos.size():
		return []
	var parent := PackedInt32Array()
	parent.resize(pos.size())
	for i in pos.size():
		parent[i] = i
	for t in range(0, idx.size(), 3):
		_join(parent, idx[t], idx[t + 1])
		_join(parent, idx[t], idx[t + 2])
	var pieces := {}
	var order := []
	for t in range(0, idx.size(), 3):
		var r := _root(parent, idx[t])
		if not pieces.has(r):
			pieces[r] = {"verts": {}, "tris": []}
			order.append(r)
		var p: Dictionary = pieces[r]
		for k in 3:
			p.verts[idx[t + k]] = true
		(p.tris as Array).append(t)
	var out := []
	for r: int in order:
		var p: Dictionary = pieces[r]
		var strip := _strip(p.verts.keys(), p.tris, idx, pos, uv)
		if not strip.is_empty():
			out.append(strip)
	return out


static func _strip(verts: Array, tris: Array, idx: PackedInt32Array, pos: PackedVector3Array,
		uv: PackedVector2Array) -> Dictionary:
	if verts.size() < 4:
		return {}
	verts.sort_custom(func(a: int, b: int) -> bool:
		return uv[a].y < uv[b].y if absf(uv[a].y - uv[b].y) > 1e-5 else uv[a].x < uv[b].x)
	var grid := []
	var at := {}
	for v: int in verts:
		if grid.is_empty() or absf(uv[v].y - uv[int((grid.back() as Array)[0])].y) > 1e-5:
			grid.append([])
		var row: Array = grid.back()
		if not row.is_empty() and absf(uv[v].x - uv[int(row.back())].x) < 1e-6:
			return {}
		at[v] = Vector2i(row.size(), grid.size() - 1)
		row.append(v)
	var cols: int = (grid[0] as Array).size()
	if grid.size() < 2 or cols < 2 or tris.size() != (grid.size() - 1) * (cols - 1) * 2:
		return {}
	for row: Array in grid:
		if row.size() != cols:
			return {}
	var area := 0.0
	var sign := 0
	for t: int in tris:
		var g: Array[Vector2i] = [at[idx[t]], at[idx[t + 1]], at[idx[t + 2]]]
		for k in 3:
			if absi(g[k].x - g[(k + 1) % 3].x) > 1 or absi(g[k].y - g[(k + 1) % 3].y) > 1:
				return {}
		var o := signi((g[1].x - g[0].x) * (g[2].y - g[0].y) - (g[1].y - g[0].y) * (g[2].x - g[0].x))
		if sign == 0:
			sign = o
		elif o != sign:
			return {}
		area += (pos[idx[t + 1]] - pos[idx[t]]).cross(pos[idx[t + 2]] - pos[idx[t]]).length() * 0.5
	return {"grid": grid, "sign": sign, "area": area, "tris": tris.size()}


## The triangles of a strip over the kept rows and columns, wound as its own.
static func _quads(strip: Dictionary, rows: Array, cols: Array, out: PackedInt32Array) -> PackedInt32Array:
	var grid: Array = strip.grid
	for i in range(1, rows.size()):
		var ra: Array = grid[int(rows[i - 1])]
		var rb: Array = grid[int(rows[i])]
		for j in range(1, cols.size()):
			var ca := int(cols[j - 1])
			var cb := int(cols[j])
			# (ca, ra) (ca, rb) (cb, rb) turns the other way round from the strip's own when its sign is +1
			if int(strip.sign) < 0:
				out.append_array(PackedInt32Array([ra[ca], rb[ca], rb[cb], ra[ca], rb[cb], ra[cb]]))
			else:
				out.append_array(PackedInt32Array([ra[ca], rb[cb], rb[ca], ra[ca], ra[cb], rb[cb]]))
	return out


## A hair or beard surface's levels: the middle one (every strip, fewer rows) and the far one (the largest strips,
## fewer rows, a ring as a triangle); triangles that are no strip's are kept in both.
static func _strand_levels(arrays: Array, strips: Array) -> Array:
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var in_strip := PackedByteArray()
	in_strip.resize(pos.size())
	var total_area := 0.0
	for c: Dictionary in strips:
		total_area += float(c.area)
		for row: Array in c.grid:
			for v: int in row:
				in_strip[v] = 1
	var rest := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if in_strip[idx[t]] == 0:
			rest.append_array(PackedInt32Array([idx[t], idx[t + 1], idx[t + 2]]))
	var mid := rest.duplicate()
	for c: Dictionary in strips:
		mid = _quads(c, rows_within(c, pos, STRAND_MID_TOL_M), range((c.grid[0] as Array).size()), mid)
	var by_area := strips.duplicate()
	by_area.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.area) > float(b.area) if float(a.area) != float(b.area) else int(a.grid[0][0]) < int(b.grid[0][0]))
	var far := rest.duplicate()
	var area := 0.0
	for c: Dictionary in by_area:
		if area >= total_area * FAR_STRAND_AREA or (far.size() - rest.size()) / 3 >= FAR_STRAND_TRIS:
			break
		far = _quads(c, rows_within(c, pos, FAR_ROW_TOL_M), _far_columns((c.grid[0] as Array).size()), far)
		area += float(c.area)
	return [[STRAND_MID_KEY, mid], [FAR_KEY, far]]


## A ring's columns in the far level: FAR_RING_COLUMNS of them evenly round (the first and the seam's last), or a
## card's two.
static func _far_columns(n: int) -> Array:
	if n <= FAR_RING_COLUMNS:
		return range(n)
	var out := []
	for k in FAR_RING_COLUMNS:
		out.append(roundi(float(k) * (n - 1) / (FAR_RING_COLUMNS - 1)))
	return out


## The rows of a strip that keep its middle line within `tol` of the whole line (Douglas-Peucker; both ends kept).
static func rows_within(c: Dictionary, pos: PackedVector3Array, tol: float) -> Array:
	var grid: Array = c.grid
	var mids := PackedVector3Array()
	for row: Array in grid:
		var m := Vector3.ZERO
		for v: int in row:
			m += pos[v]
		mids.append(m / row.size())
	var keep := {0: true, grid.size() - 1: true}
	var stack := [[0, grid.size() - 1]]
	while not stack.is_empty():
		var span: Array = stack.pop_back()
		var a: int = span[0]
		var b: int = span[1]
		var worst := -1
		var most := tol
		for i in range(a + 1, b):
			var d := _to_segment(mids[i], mids[a], mids[b])
			if d > most:
				most = d
				worst = i
		if worst >= 0:
			keep[worst] = true
			stack.append([a, worst])
			stack.append([worst, b])
	var out := keep.keys()
	out.sort()
	return out


static func _to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
	return (p - (a + ab * t)).length()


static func _root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _join(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _root(parent, a)
	var rb := _root(parent, b)
	if ra != rb:
		parent[maxi(ra, rb)] = mini(ra, rb)


## True when a surface's indices are 32-bit (the renderer's choice by the vertex count).
static func _wide(d: Dictionary) -> bool:
	return (d.get("index_data", PackedByteArray()) as PackedByteArray).size() >= 4 * int(d.get("index_count", 1))


static func _unpack(data: PackedByteArray, wide: bool) -> PackedInt32Array:
	var out := PackedInt32Array()
	if wide:
		out = data.to_int32_array()
	else:
		out.resize(data.size() / 2)
		for i in out.size():
			out[i] = data.decode_u16(i * 2)
	return out


static func _pack(indices: PackedInt32Array, wide: bool) -> PackedByteArray:
	if wide:
		return indices.to_byte_array()
	var out := PackedByteArray()
	out.resize(indices.size() * 2)
	for i in indices.size():
		out.encode_u16(i * 2, indices[i])
	return out

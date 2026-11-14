class_name HeightField
extends RefCounted
## A world's heights on one regular grid (P24a; plan M6-M9 §5.3, decision 12): the offline terrain
## library's base. A world builder (P24a's test world, P25's world) samples its terrain features
## into one HeightField, relaxes the chunk borders (relax_borders: the seam trap of
## open_world_tech.md §4.4 - a slope of 40 degrees or more across a chunk border stops a giant -
## so no face within BORDER_BAND_M of a border is steeper than BORDER_MAX_DEG), then
## tools/world/chunk_writer.gd cuts it into chunks (each with its one-sample apron) and
## tools/world/skyline_writer.gd takes its coarse minimum for the skyline.
##
## Sample (i, j) sits at world (origin.x + i * spacing, origin.y + j * spacing) - origin.y is the
## world z. A builder starts the field one sample before its world so the outermost chunks' aprons
## are inside it. Quantisation (quantise / encode): 16 bits from QUANT_MIN_M in QUANT_STEP_M steps
## (-32 .. +230 m), the format ChunkData stores.
##
## Tools only (tools/ is never exported); the game reads ChunkData.

const QUANT_MIN_M := -32.0
const QUANT_STEP_M := 0.004
const QUANT_MAX := 65535
## The border rule (§5.3 step 8): within this band of a chunk border no face is steeper than this.
const BORDER_MAX_DEG := 35.0
const BORDER_BAND_M := 8.0
## A face counts as over the rule only beyond this margin: a plane ramp built at exactly the limit
## stays at the limit, and quantising to 4 mm moves a 4 m face by at most about 0.04 degrees.
const SLOPE_EPS_DEG := 0.05
const RELAX_MAX_ITERATIONS := 400
## The relaxation gives up when the number of faces over the rule has not fallen for this many
## iterations (a ramp steeper than the rule: smoothing cannot bend a plane).
const RELAX_STALL_ITERATIONS := 25

var origin := Vector2.ZERO
var spacing := 4.0
var size := Vector2i.ZERO
var h := PackedFloat32Array()


static func make(p_origin: Vector2, p_spacing: float, p_size: Vector2i, fill_value := 0.0) -> HeightField:
	var f := HeightField.new()
	f.origin = p_origin
	f.spacing = p_spacing
	f.size = p_size
	f.h.resize(p_size.x * p_size.y)
	f.h.fill(fill_value)
	return f


func idx(i: int, j: int) -> int:
	return j * size.x + i


## The height of sample (i, j) (indices clamped to the field).
func at(i: int, j: int) -> float:
	return h[clampi(j, 0, size.y - 1) * size.x + clampi(i, 0, size.x - 1)]


func set_at(i: int, j: int, v: float) -> void:
	h[j * size.x + i] = v


func world_x(i: int) -> float:
	return origin.x + i * spacing


func world_z(j: int) -> float:
	return origin.y + j * spacing


## Fills every sample with fn.call(world_x, world_z).
func fill(fn: Callable) -> void:
	for j in size.y:
		var z := world_z(j)
		for i in size.x:
			h[j * size.x + i] = float(fn.call(world_x(i), z))


## Bilinear height at world (x, z) (clamped to the field).
func sample(x: float, z: float) -> float:
	var fx := clampf((x - origin.x) / spacing, 0.0, size.x - 1.000001)
	var fz := clampf((z - origin.y) / spacing, 0.0, size.y - 1.000001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	return lerpf(lerpf(at(i, j), at(i + 1, j), tx), lerpf(at(i, j + 1), at(i + 1, j + 1), tx), tz)


## The steeper of the two triangles of cell (i, j) (between samples i..i+1, j..j+1, split along
## the (i, j) - (i + 1, j + 1) diagonal as the terrain mesh and the ground body), in degrees.
func cell_slope_deg(i: int, j: int) -> float:
	var h00 := at(i, j)
	var h10 := at(i + 1, j)
	var h01 := at(i, j + 1)
	var h11 := at(i + 1, j + 1)
	var a := Vector2(h10 - h00, h11 - h10).length() / spacing
	var b := Vector2(h11 - h01, h01 - h00).length() / spacing
	return rad_to_deg(atan(maxf(a, b)))


# --------------------------------------------------------------------------- quantisation

## The 16-bit value of a height (clamped to the format's range).
static func quantise(v: float, h_min := QUANT_MIN_M, step := QUANT_STEP_M) -> int:
	return clampi(int(roundf((v - h_min) / step)), 0, QUANT_MAX)


static func dequantise(q: int, h_min := QUANT_MIN_M, step := QUANT_STEP_M) -> float:
	return h_min + q * step


## Heights as ChunkData stores them: 16-bit little-endian values.
static func encode(values: PackedFloat32Array, h_min := QUANT_MIN_M, step := QUANT_STEP_M) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(values.size() * 2)
	for k in values.size():
		out.encode_u16(2 * k, quantise(values[k], h_min, step))
	return out


## Every sample quantised and back (what a chunk will hold), in place.
func quantise_all(h_min := QUANT_MIN_M, step := QUANT_STEP_M) -> void:
	for k in h.size():
		h[k] = dequantise(quantise(h[k], h_min, step), h_min, step)


# --------------------------------------------------------------------------- chunk borders

## The sample indices of the chunk borders inside the field along one axis: every `cells` samples
## from `first` (the field index of the world's first sample), the world's own edges excluded.
static func border_lines(first: int, cells: int, chunks: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in range(1, chunks):
		out.append(first + k * cells)
	return out


## True when cell (i, j) lies within `band` samples of a border line (cells touching the band).
static func _near(i: int, lines: PackedInt32Array, band: int) -> bool:
	for s in lines:
		if i >= s - band - 1 and i <= s + band:
			return true
	return false


## The steepest face within the border band: {"deg", "x", "z" (world, the cell's centre), "cells"
## (how many band cells are over max_deg + SLOPE_EPS_DEG)}. `walkable` (Callable(x, z) -> bool) exempts cells that are
## not walkable (the rim, cliffs); an invalid Callable counts every cell.
func border_report(first: Vector2i, cells: int, chunks: Vector2i, band_m := BORDER_BAND_M,
		max_deg := BORDER_MAX_DEG, walkable := Callable()) -> Dictionary:
	var xs := border_lines(first.x, cells, chunks.x)
	var zs := border_lines(first.y, cells, chunks.y)
	var band := int(ceil(band_m / spacing))
	var worst := 0.0
	var where := Vector2.INF
	var over := 0
	for j in size.y - 1:
		var near_z := _near(j, zs, band)
		for i in size.x - 1:
			if not near_z and not _near(i, xs, band):
				continue
			var cx := world_x(i) + spacing * 0.5
			var cz := world_z(j) + spacing * 0.5
			if walkable.is_valid() and not bool(walkable.call(cx, cz)):
				continue
			var d := cell_slope_deg(i, j)
			if d > max_deg + SLOPE_EPS_DEG:
				over += 1
			if d > worst:
				worst = d
				where = Vector2(cx, cz)
	return {"deg": worst, "x": where.x, "z": where.y, "cells": over}


## Smooths the walkable samples within band_m of a chunk border (each moved to the mean of its four
## neighbours, the band's faces over max_deg first) until no band face is steeper than max_deg.
## A slope that smoothing cannot bring down (a long ramp steeper than the rule: the count of faces
## over it stops falling for RELAX_STALL_ITERATIONS) fails: {"ok": false, "message" naming the
## place}. {"ok": true, "iterations", "deg"} otherwise.
func relax_borders(first: Vector2i, cells: int, chunks: Vector2i, band_m := BORDER_BAND_M,
		max_deg := BORDER_MAX_DEG, walkable := Callable(), stall_after := RELAX_STALL_ITERATIONS) -> Dictionary:
	var xs := border_lines(first.x, cells, chunks.x)
	var zs := border_lines(first.y, cells, chunks.y)
	var band := int(ceil(band_m / spacing))
	var best_over := 1 << 30
	var stalled := 0
	for it in RELAX_MAX_ITERATIONS:
		var report := border_report(first, cells, chunks, band_m, max_deg, walkable)
		if int(report.cells) == 0:
			return {"ok": true, "iterations": it, "deg": report.deg}
		if int(report.cells) < best_over:
			best_over = int(report.cells)
			stalled = 0
		else:
			stalled += 1
			if stalled >= stall_after:
				break
		var moved := {}
		for j in range(1, size.y - 2):
			var near_z := _near(j, zs, band)
			for i in range(1, size.x - 2):
				if not near_z and not _near(i, xs, band):
					continue
				if cell_slope_deg(i, j) <= max_deg + SLOPE_EPS_DEG:
					continue
				var cx := world_x(i) + spacing * 0.5
				var cz := world_z(j) + spacing * 0.5
				if walkable.is_valid() and not bool(walkable.call(cx, cz)):
					continue
				for c: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1)]:
					moved[c] = (at(c.x - 1, c.y) + at(c.x + 1, c.y) + at(c.x, c.y - 1) + at(c.x, c.y + 1)) * 0.25
		for c: Vector2i in moved:
			set_at(c.x, c.y, float(moved[c]))
	var last := border_report(first, cells, chunks, band_m, max_deg, walkable)
	return {"ok": false, "iterations": RELAX_MAX_ITERATIONS if stalled < stall_after else -1, "deg": last.deg,
		"message": "a chunk border near (%.0f, %.0f) is still %.1f degrees steep (the rule is %.0f within %.0f m of a border)" % [
			float(last.x), float(last.z), float(last.deg), max_deg, band_m]}

class_name ItemIcon
extends Control
## C3: a drawn icon for an inventory cell or an equipment slot - no image files: a few shapes by what the thing is
## (kind_of: an armour piece by its slot, a weapon by its family, an item by its category and name) in a colour by
## what it is made of (tint_of: an armour set's own colour, iron, stone, hide, wood, gold for trophies). An empty
## slot draws its slot's outline faintly. `count` > 1 prints "x3" at the bottom right, `fresh` a "NEW" tag.

const IRON := Color(0.62, 0.64, 0.68)
const STONE := Color(0.60, 0.56, 0.50)
const HIDE := Color(0.55, 0.38, 0.24)
const WOOD := Color(0.50, 0.36, 0.20)
const GOLD := Color(0.95, 0.78, 0.35)
const CLOTH := Color(0.55, 0.52, 0.45)
const QUEST := Color(0.85, 0.72, 0.45)
const SHADE := Color(0, 0, 0, 0.45)
const FRESH := Color(1.0, 0.82, 0.30)

## head, shoulders, chest, arms, waist, legs, trinket, club, sword, axe, hammer, tree, fists, ingot, hide, stone,
## wood, gem, scroll, sack, key, ring, item.
var kind := "item"
var tint := IRON
var count := 0
var fresh := false
var empty := false


static func of(id: String, p_count := 0, p_fresh := false) -> ItemIcon:
	var ic := ItemIcon.new()
	ic.set_thing(id, p_count, p_fresh)
	return ic


static func of_slot(slot: String) -> ItemIcon:
	var ic := ItemIcon.new()
	ic.kind = slot
	ic.tint = Color(1, 1, 1, 0.22)
	ic.empty = true
	return ic


func set_thing(id: String, p_count := 0, p_fresh := false) -> void:
	kind = kind_of(id)
	tint = tint_of(id)
	count = p_count
	fresh = p_fresh
	empty = false
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(44, 44)


## The shape for record `id`.
static func kind_of(id: String) -> String:
	var rec := GameData.get_record(id)
	match str(rec.get("type", "")):
		"armour":
			return str(rec.get("slot", "chest"))
		"weapon":
			var fam := str(rec.get("family", "club"))
			return fam if fam in ["club", "sword", "axe", "hammer", "tree", "fists"] else "club"
	var cat := str(rec.get("category", "material"))
	var n := id.to_lower()
	if cat == "trophy":
		return "ring" if n.contains("ring") else ("scroll" if n.contains("annals") or n.contains("epitaph") else "gem")
	if cat == "quest":
		return "sack" if n.contains("cache") else "gem"
	if cat == "key":
		return "key"
	if n.contains("ingot") or n.contains("iron"):
		return "ingot"
	if n.contains("hide") or n.contains("pelt"):
		return "hide"
	if n.contains("wood") or n.contains("timber") or n.contains("heartwood") or n.contains("log"):
		return "wood"
	if n.contains("slab") or n.contains("stone") or n.contains("ashlar"):
		return "stone"
	return "item"


## The colour for record `id`.
static func tint_of(id: String) -> Color:
	var rec := GameData.get_record(id)
	match str(rec.get("type", "")):
		"armour":
			var s := GameData.get_record(str(rec.get("set", "")))
			var c := str(s.get("color", ""))
			return Color.from_string(c, IRON) if c != "" else IRON
		"weapon":
			var fam := str(rec.get("family", "club"))
			return WOOD if fam in ["club", "tree"] else IRON
	match kind_of(id):
		"ingot":
			return IRON
		"hide":
			return HIDE
		"wood":
			return WOOD
		"stone":
			return STONE
		"gem", "ring":
			return GOLD
		"scroll", "sack", "key":
			return QUEST
	return CLOTH


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var c := tint
	var dark := c.darkened(0.35)
	var lite := c.lightened(0.25)
	var P := func(pts: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for q: Vector2 in pts:
			out.append(o + q * s)
		return out
	var poly := func(pts: Array, col: Color) -> void:
		var arr: PackedVector2Array = P.call(pts)
		if empty:
			var loop := arr.duplicate()
			loop.append(arr[0])
			draw_polyline(loop, col, 1.5)
		else:
			draw_colored_polygon(arr, col)
	var rect := func(x: float, y: float, w: float, h: float, col: Color) -> void:
		poly.call([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)], col)
	match kind:
		"head":
			poly.call([Vector2(0.25, 0.55), Vector2(0.3, 0.28), Vector2(0.5, 0.16), Vector2(0.7, 0.28), Vector2(0.75, 0.55),
				Vector2(0.75, 0.78), Vector2(0.6, 0.78), Vector2(0.56, 0.5), Vector2(0.44, 0.5), Vector2(0.4, 0.78), Vector2(0.25, 0.78)], c)
			rect.call(0.47, 0.5, 0.06, 0.24, dark)
		"shoulders":
			poly.call([Vector2(0.1, 0.62), Vector2(0.18, 0.36), Vector2(0.42, 0.3), Vector2(0.45, 0.62)], c)
			poly.call([Vector2(0.55, 0.62), Vector2(0.58, 0.3), Vector2(0.82, 0.36), Vector2(0.9, 0.62)], c)
			rect.call(0.2, 0.5, 0.2, 0.05, dark)
			rect.call(0.6, 0.5, 0.2, 0.05, dark)
		"chest":
			poly.call([Vector2(0.22, 0.2), Vector2(0.4, 0.16), Vector2(0.5, 0.24), Vector2(0.6, 0.16), Vector2(0.78, 0.2),
				Vector2(0.74, 0.84), Vector2(0.26, 0.84)], c)
			rect.call(0.48, 0.3, 0.04, 0.5, dark)
			rect.call(0.3, 0.5, 0.4, 0.04, lite)
		"arms":
			poly.call([Vector2(0.18, 0.3), Vector2(0.42, 0.24), Vector2(0.46, 0.78), Vector2(0.24, 0.8)], c)
			poly.call([Vector2(0.58, 0.24), Vector2(0.82, 0.3), Vector2(0.76, 0.8), Vector2(0.54, 0.78)], c)
			rect.call(0.22, 0.5, 0.22, 0.05, dark)
			rect.call(0.56, 0.5, 0.22, 0.05, dark)
		"waist":
			rect.call(0.14, 0.36, 0.72, 0.16, c)
			rect.call(0.44, 0.34, 0.12, 0.2, lite)
			poly.call([Vector2(0.2, 0.52), Vector2(0.42, 0.52), Vector2(0.38, 0.84), Vector2(0.22, 0.82)], dark)
			poly.call([Vector2(0.58, 0.52), Vector2(0.8, 0.52), Vector2(0.78, 0.82), Vector2(0.62, 0.84)], dark)
		"legs":
			poly.call([Vector2(0.2, 0.14), Vector2(0.42, 0.14), Vector2(0.44, 0.86), Vector2(0.24, 0.86)], c)
			poly.call([Vector2(0.58, 0.14), Vector2(0.8, 0.14), Vector2(0.76, 0.86), Vector2(0.56, 0.86)], c)
			rect.call(0.22, 0.44, 0.2, 0.06, dark)
			rect.call(0.58, 0.44, 0.2, 0.06, dark)
		"trinket", "ring":
			if empty:
				draw_arc(o + Vector2(0.5, 0.52) * s, 0.24 * s, 0.0, TAU, 24, c, 1.5)
			else:
				draw_circle(o + Vector2(0.5, 0.52) * s, 0.26 * s, c)
				draw_circle(o + Vector2(0.5, 0.52) * s, 0.15 * s, Color(0.08, 0.09, 0.11))
				draw_circle(o + Vector2(0.5, 0.25) * s, 0.09 * s, lite)
		"club", "tree":
			poly.call([Vector2(0.28, 0.86), Vector2(0.2, 0.8), Vector2(0.56, 0.3), Vector2(0.7, 0.42)], c)
			poly.call([Vector2(0.5, 0.3), Vector2(0.62, 0.12), Vector2(0.86, 0.22), Vector2(0.84, 0.4), Vector2(0.7, 0.48)], dark if kind == "club" else Color(0.32, 0.45, 0.25))
		"sword":
			poly.call([Vector2(0.2, 0.82), Vector2(0.26, 0.74), Vector2(0.8, 0.16), Vector2(0.86, 0.14), Vector2(0.84, 0.2), Vector2(0.3, 0.78)], lite)
			rect.call(0.22, 0.62, 0.2, 0.05, dark)
		"axe":
			poly.call([Vector2(0.3, 0.88), Vector2(0.24, 0.84), Vector2(0.62, 0.2), Vector2(0.68, 0.24)], WOOD)
			poly.call([Vector2(0.52, 0.2), Vector2(0.72, 0.1), Vector2(0.86, 0.36), Vector2(0.66, 0.4)], c)
		"hammer":
			poly.call([Vector2(0.3, 0.88), Vector2(0.24, 0.84), Vector2(0.58, 0.3), Vector2(0.64, 0.34)], WOOD)
			poly.call([Vector2(0.42, 0.22), Vector2(0.62, 0.08), Vector2(0.84, 0.38), Vector2(0.64, 0.52)], c)
		"fists":
			poly.call([Vector2(0.26, 0.4), Vector2(0.74, 0.4), Vector2(0.78, 0.72), Vector2(0.5, 0.82), Vector2(0.22, 0.72)], c)
			for i in 4:
				rect.call(0.27 + i * 0.12, 0.3, 0.1, 0.14, lite)
		"ingot":
			poly.call([Vector2(0.18, 0.62), Vector2(0.3, 0.42), Vector2(0.82, 0.42), Vector2(0.7, 0.62)], lite)
			poly.call([Vector2(0.18, 0.62), Vector2(0.7, 0.62), Vector2(0.7, 0.72), Vector2(0.18, 0.72)], c)
		"hide":
			poly.call([Vector2(0.3, 0.18), Vector2(0.5, 0.26), Vector2(0.7, 0.18), Vector2(0.8, 0.42), Vector2(0.72, 0.82),
				Vector2(0.5, 0.74), Vector2(0.28, 0.82), Vector2(0.2, 0.42)], c)
		"wood":
			poly.call([Vector2(0.14, 0.4), Vector2(0.8, 0.36), Vector2(0.86, 0.62), Vector2(0.2, 0.66)], c)
			if not empty:
				draw_circle(o + Vector2(0.82, 0.49) * s, 0.13 * s, lite)
		"stone":
			poly.call([Vector2(0.16, 0.5), Vector2(0.3, 0.28), Vector2(0.7, 0.24), Vector2(0.86, 0.46), Vector2(0.76, 0.76), Vector2(0.24, 0.78)], c)
			rect.call(0.3, 0.46, 0.4, 0.04, dark)
		"gem":
			poly.call([Vector2(0.5, 0.14), Vector2(0.8, 0.4), Vector2(0.5, 0.86), Vector2(0.2, 0.4)], c)
			poly.call([Vector2(0.5, 0.14), Vector2(0.62, 0.4), Vector2(0.5, 0.6), Vector2(0.38, 0.4)], lite)
		"scroll":
			rect.call(0.24, 0.24, 0.52, 0.52, c)
			rect.call(0.2, 0.2, 0.6, 0.08, dark)
			rect.call(0.2, 0.72, 0.6, 0.08, dark)
		"sack":
			poly.call([Vector2(0.36, 0.22), Vector2(0.64, 0.22), Vector2(0.58, 0.34), Vector2(0.8, 0.56), Vector2(0.72, 0.84),
				Vector2(0.28, 0.84), Vector2(0.2, 0.56), Vector2(0.42, 0.34)], c)
		"key":
			if empty:
				draw_arc(o + Vector2(0.32, 0.4) * s, 0.14 * s, 0.0, TAU, 16, c, 1.5)
			else:
				draw_circle(o + Vector2(0.32, 0.4) * s, 0.15 * s, c)
			rect.call(0.42, 0.37, 0.42, 0.07, c)
			rect.call(0.74, 0.44, 0.06, 0.14, c)
		_:
			poly.call([Vector2(0.24, 0.3), Vector2(0.76, 0.3), Vector2(0.8, 0.76), Vector2(0.2, 0.76)], c)
	if count > 1:
		HudKit.draw_text(self, Vector2(size.x - 4.0, size.y - 3.0) - Vector2(22, 0), "x%d" % count, 11, UiKit.TEXT)
	if fresh:
		draw_rect(Rect2(Vector2(1, 1), Vector2(26, 12)), FRESH)
		HudKit.draw_text(self, Vector2(3, 11), "NEW", 9, Color(0.1, 0.08, 0.02))

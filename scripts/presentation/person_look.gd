class_name PersonLook
extends RefCounted
## Who a person looks like (P60; plan M11 §2.9, decision 12): the body variant, the palette, the height and the
## gear, from the actor record's `body` key (data/enemies/*.json, data/npcs/*.json), the role's record
## (data/people/role_<role>.json, type person_role) and the entity id. Pure: nothing here reads a random stream
## or the simulation, and the same id always gives the same look.
##
##   variant   the record's `body.variant` when it names one of the role's variants (a named character, the iron
##             guard); else the role's pool at absi(hash(entity_id)) % its size;
##   palette   a row of the role's palette table (PALETTE_ROWS rows of skin, hair and cloth, combined from the
##             role's lists so that neighbouring rows differ in all three) at a second hash of the id, and the
##             faction band's colour from the role's `factions` by the actor's faction ("default" without one);
##             the record's `body.palette` overrides a band (shown by the skinned body; a crowd instance keeps
##             its row);
##   height    the record's height over P59's 1.8 m, times the variant's suggested scale (0.93 for the women);
##   gear      the record's `body.gear`, else the scene's.
## The crowd's palette texture (palette_image): PALETTE_ROWS rows, columns skin, hair, cloth, and in column 3
## the faction colours in factions()' order.

const PALETTE_ROWS := 16
const DEFAULT_ROLE := "person_role.soldier"
const DEFAULT_FACTION := "default"
## The steps through the hair and cloth lists from one palette row to the next (prime to the lists' sizes).
const HAIR_STEP := 5
const CLOTH_STEP := 3


## The role's record (person_role), {} when unknown.
static func role_record(person_role: String) -> Dictionary:
	if person_role == "" or not GameData.has_record(person_role):
		return {}
	var r := GameData.get_record(person_role)
	return r if str(r.get("type", "")) == "person_role" else {}


## P59's role (the glTF's name) that `person_role` draws from ("soldier" for person_role.soldier).
static func asset_role(person_role: String) -> String:
	var r := role_record(person_role)
	return str(r.get("asset_role", person_role.trim_prefix("person_role.")))


## The look of one actor (see the class notes): {"person_role", "role" (P59's), "variant", "row", "faction",
## "faction_row", "palette": {"skin", "hair", "cloth", "faction": Color}, "height_scale", "gear": Array}.
## `body` is the record's body key (or {}), `defaults` the scene's {"person_role", "gear", "variant"}.
static func spec(body: Variant, entity_id: String, faction: String, height_m: float, defaults: Dictionary) -> Dictionary:
	var b: Dictionary = body if typeof(body) == TYPE_DICTIONARY else {}
	var person_role := str(b.get("role", defaults.get("person_role", DEFAULT_ROLE)))
	var rec := role_record(person_role)
	var pool: Array = rec.get("variants", [])
	var named := str(b.get("variant", defaults.get("variant", "")))
	var all_variants: Array = []
	var ar := asset_role(person_role)
	if PersonModel.has_role(ar):
		all_variants = (PersonModel.index().roles[ar] as Dictionary).get("variants", [])
	var variant := ""
	if named != "" and (all_variants.has(named) or pool.has(named)):
		variant = named
	elif not pool.is_empty():
		variant = str(pool[absi(hash(entity_id)) % pool.size()])
	elif not all_variants.is_empty():
		variant = str(all_variants[absi(hash(entity_id)) % all_variants.size()])
	var row := palette_row(entity_id)
	var factions := factions_of(person_role)
	var fkey := faction if factions.has(faction) else DEFAULT_FACTION
	var palette := row_colors(person_role, row)
	palette["faction"] = faction_color(person_role, fkey)
	var over: Variant = b.get("palette")
	if typeof(over) == TYPE_DICTIONARY:
		for k: Variant in over:
			palette[str(k)] = Color.html(str(over[k]))
	var natural := 1.0
	if PersonModel.has_role(ar) and variant != "":
		var facts: Dictionary = PersonModel.role_data(ar).get("variants", {}).get(variant, {})
		natural = float(facts.get("natural", 1.0))
	var gear: Array = b.get("gear", defaults.get("gear", []))
	return {"person_role": person_role, "role": ar, "variant": variant, "row": row, "faction": fkey,
		"faction_row": maxi(0, factions.find(fkey)), "palette": palette,
		"height_scale": maxf(0.1, height_m / PersonModel.HEIGHT_M) * natural, "gear": gear.duplicate()}


## The palette row an entity id takes (0 .. PALETTE_ROWS - 1).
static func palette_row(entity_id: String) -> int:
	return absi(hash(entity_id + "#palette")) % PALETTE_ROWS


## The faction keys of the role, "default" first, then the others sorted (the palette texture's rows).
static func factions_of(person_role: String) -> Array:
	var fac: Dictionary = role_record(person_role).get("factions", {})
	var keys: Array = fac.keys()
	keys.erase(DEFAULT_FACTION)
	keys.sort()
	keys.push_front(DEFAULT_FACTION)
	return keys


static func faction_color(person_role: String, faction: String) -> Color:
	var fac: Dictionary = role_record(person_role).get("factions", {})
	return Color.html(str(fac.get(faction, fac.get(DEFAULT_FACTION, "#7a2a22"))))


## Row `row`'s skin, hair and cloth colours (sRGB Colors).
static func row_colors(person_role: String, row: int) -> Dictionary:
	var pal: Dictionary = role_record(person_role).get("palette", {})
	var skin: Array = pal.get("skin", ["#c69a7e"])
	var hair: Array = pal.get("hair", ["#2b2019"])
	var cloth: Array = pal.get("cloth", ["#6e695d"])
	return {"skin": Color.html(str(skin[row % skin.size()])),
		"hair": Color.html(str(hair[(row * HAIR_STEP + 1) % hair.size()])),
		"cloth": Color.html(str(cloth[(row * CLOTH_STEP + 2) % cloth.size()]))}


## The crowd's palette texture of the role (see the class notes): 4 x max(rows, factions) texels, sRGB.
static func palette_image(person_role: String) -> Image:
	var factions := factions_of(person_role)
	var h := maxi(PALETTE_ROWS, factions.size())
	var img := Image.create(4, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var c := row_colors(person_role, y % PALETTE_ROWS)
		img.set_pixel(0, y, c.skin)
		img.set_pixel(1, y, c.hair)
		img.set_pixel(2, y, c.cloth)
		img.set_pixel(3, y, faction_color(person_role, str(factions[mini(y, factions.size() - 1)])))
	return img


## Puts a look's palette on a person material (person.gdshader).
static func apply(material: ShaderMaterial, look: Dictionary) -> void:
	if material == null:
		return
	var pal: Dictionary = look.get("palette", {})
	material.set_shader_parameter(&"skin_color", pal.get("skin", Color(0.78, 0.6, 0.5)))
	material.set_shader_parameter(&"hair_color", pal.get("hair", Color(0.17, 0.13, 0.1)))
	material.set_shader_parameter(&"cloth_color", pal.get("cloth", Color(0.43, 0.41, 0.36)))
	material.set_shader_parameter(&"faction_color", pal.get("faction", Color(0.48, 0.16, 0.13)))

class_name StatusDef
extends RefCounted
## Typed, cached view of one status_effect record (GameData.get_status). Seconds are converted
## to 60 Hz ticks once, here.
##
## modifiers: STATUS_MODIFIERS key -> value. When magnitude_key is set, an application's
## magnitude replaces that one modifier (NAN = default_magnitude). Keys and how they combine
## across active statuses (Combatant):
##   armor_flat            summed            (Stone Skin +30; armor_total = armor + sum)
##   slow_fraction         strongest only    (move_mult = 1 - clamp(max, 0, 0.9))
##   outgoing_damage_mult  multiplied        (Titan Surge 1.25)
##   outgoing_poise_mult   multiplied
##   fury_gain_mult        multiplied        (Titan Surge 0 = no fury gain)
##   damage_taken_mult     multiplied        (barrier, bot assist 0.25, debug invulnerable 0)
##   heal_per_tick         periodic heal every tick_ticks, the last one on the expiry tick

const STACKING := ["refresh_no_stack", "strongest_wins", "independent"]

var id := ""
var display_name := ""
var hud_label := ""
var stacking := "refresh_no_stack"  ## refresh_no_stack | strongest_wins | independent
var duration_ticks := 0
var tick_ticks := 0                 ## period of the periodic effect; 0 = none
var magnitude_key := ""             ## "" or the modifiers key fed by the application's magnitude
var default_magnitude := 0.0
var modifiers: Dictionary = {}
var tags := PackedStringArray()     ## STATUS_TAGS (status immunities match these)
var hidden := false                 ## left out of the HUD status row (tooling statuses)
var params: Dictionary = {}         ## the raw record


static func from_dict(d: Dictionary) -> StatusDef:
	var s := StatusDef.new()
	s.fill(d)
	return s


## (Re)reads every field from a record (GameData.override_record refreshes in place).
func fill(d: Dictionary) -> void:
	params = d
	id = str(d.get("id", ""))
	display_name = str(d.get("display_name", id))
	hud_label = str(d.get("hud_label", display_name))
	stacking = str(d.get("stacking", "refresh_no_stack"))
	duration_ticks = maxi(1, ActionDef.seconds_to_ticks(float(d.get("duration_s", 1.0))))
	tick_ticks = maxi(0, ActionDef.seconds_to_ticks(float(d.get("tick_s", 0.0))))
	magnitude_key = str(d.get("magnitude_key", ""))
	modifiers = {}
	var raw: Variant = d.get("modifiers", {})
	if typeof(raw) == TYPE_DICTIONARY:
		for k: Variant in raw:
			modifiers[str(k)] = float(raw[k])
	default_magnitude = float(d.get("default_magnitude", modifiers.get(magnitude_key, 0.0)))
	tags = PackedStringArray(d.get("tags", []))
	hidden = bool(d.get("hidden", false))


func duration_s() -> float:
	return duration_ticks / float(ActionDef.TICK_RATE)


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func is_debuff() -> bool:
	return tags.has("Debuff")

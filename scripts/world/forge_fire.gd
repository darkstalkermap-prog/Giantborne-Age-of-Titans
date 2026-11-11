class_name ForgeFire
extends BeaconFire
## The fire of a cold forge that must be lit before it works (P35; plan M6-M9 §5.4, §5.12,
## quest.titan_bones): the Titan Forge in the Titan's ribs. A BeaconFire (lit once its requires_flags
## hold - the bones' scavengers driven off -, it sets lit_flag, pays its cache once, says lit_message
## and shows its Fire) that offers "Light the <name>" and steps aside once lit: it disables itself, so
## the forge beside it (a Forge whose requires_flags wait for lit_flag) takes E from then on.
## Built by the world builder's forge_fire kind (tools/world/kinds/forge_fire.gd).


func _init() -> void:
	prompt = "Light the forge"
	priority = 35
	radius_m = 9.0


func _ready() -> void:
	super()
	enabled = not is_lit()


func prompt_text(_player: GiantPlayer) -> String:
	return "Light the %s" % display_name


func blocked_reason(_player: GiantPlayer) -> String:
	return "The %s burns already." % display_name if is_lit() else locked_message


func light() -> bool:
	var ok := super()
	enabled = not is_lit()
	return ok


func _on_flag_changed(tick: int, id: String, value: Variant) -> void:
	super(tick, id, value)
	if id == lit_flag:
		enabled = not is_lit()

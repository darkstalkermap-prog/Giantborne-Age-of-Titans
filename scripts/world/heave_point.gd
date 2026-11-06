class_name HeavePoint
extends Interactable
## The heave interaction of a heave prop (P26, plan M6-M9 §2.9, §5.5): "[E] Heave the rockfall
## aside". A child of the BreakableProp it heaves (a rockfall, a fallen titan-tree, a toppled statue:
## records with requires_permission "heave"). It is usable while that prop stands; E calls
## BreakableProp.heave(player): a giant whose stage grants heave (stage 5) heaves it aside at once,
## a smaller one gets the prop's locked message ("It will not move. Grow to stage 5.") and a
## size_gate_blocked event - the same answer a blow gets. interact_id is the prop's world id, so
## Events.interacted and the bots' heave action name the prop.

## The result of the last interaction (tests, bots).
var last_result: Dictionary = {}


func _ready() -> void:
	var p := prop()
	if interact_id == "" and p != null:
		interact_id = p.world_id


## The prop this heaves (its parent), or null.
func prop() -> BreakableProp:
	return get_parent() as BreakableProp


func can_interact(_player: GiantPlayer) -> bool:
	var p := prop()
	return p != null and not p.destroyed


func prompt_text(_player: GiantPlayer) -> String:
	var p := prop()
	if p == null:
		return prompt
	var label := str(p.record.get("display_name", "it")).to_lower()
	return "Heave the %s aside" % label


func interact(player: GiantPlayer) -> void:
	var p := prop()
	if p == null:
		return
	last_result = p.heave(player)

class_name HollowShard
extends Interactable
## E3: a plate torn from the Hollow Titan, lying where it fell (HollowEnemy.shards): "[E] Hurl the <plate> back at him" -
## the giant heaves it up and throws it (HollowEnemy.hurl_shard: it never comes back onto him, and it strikes his breast).
## Made by HollowEnemy when a plate breaks, freed when the shard is crushed, hurled or drawn back onto him.

const NAMES := {"helm": "crowned helm", "pauldron_l": "left pauldron", "pauldron_r": "right pauldron",
	"cuirass": "breastplate", "vambrace": "vambrace", "greave_l": "left greave", "greave_r": "right greave"}

var titan: HollowEnemy = null
var plate_id := ""


func _init() -> void:
	priority = 30
	prompt = "Hurl it back at him"


func can_interact(_player: GiantPlayer) -> bool:
	return titan != null and is_instance_valid(titan) and titan.entity != null and titan.entity.is_alive() \
		and titan.shard_state(plate_id) == HollowEnemy.LYING


func offered(player: GiantPlayer) -> bool:
	return can_interact(player)


func facing_free(_player: GiantPlayer) -> bool:
	return true


func prompt_text(_player: GiantPlayer) -> String:
	return "Hurl his %s back at him" % str(NAMES.get(plate_id, "plate"))


func interact(player: GiantPlayer) -> void:
	if can_interact(player):
		titan.hurl_shard(plate_id, player)

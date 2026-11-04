class_name ActionDef
extends RefCounted
## Typed, cached view of one action record (attacks, abilities, dodge, block, jump, sprint).
## Seconds are converted to 60 Hz simulation ticks once, here.

enum Phase { NONE, WINDUP, ACTIVE, RECOVERY, DONE }
const PHASE_NAMES := ["none", "windup", "active", "recovery", "done"]
const TICK_RATE := 60
const ATTACK_KINDS := ["light", "heavy", "ability", "enemy_attack", "ultimate"]

var id := ""
var kind := ""
var display_name := ""
var hotbar_label := ""
var power := 0.0
var damage_type := "physical"
var damage_split: Dictionary = {}
var ability_multiplier := 1.0
var stamina_cost := 0.0
var essence_cost := 0.0
var fury_cost := 0.0
var cooldown_s := 0.0
var windup_ticks := 0
var active_ticks := 0
var recovery_ticks := 0
var poise_damage := 0.0
var max_hits_per_target := 1
var tags := PackedStringArray()
var category := "melee"
var uses_weapon := true
var crit_eligible := true
var size_policy := "attacker_growth"
var flat_penetration := 0.0
var chain_next := ""
var chain_window_ticks := 21
var hit_shape := "none"
var radius_m := 0.0
var height_m := 0.0
var arc: Dictionary = {}
var cancels: Array = []
var movement: Dictionary = {}
var knockback_impulse := 0.0
var knockback_max_speed := 0.0
var tracking_fraction := 0.0
var soft_target_max_deg := 10.0
var unlock_stage := 1
var iframe_start_tick := 0
var iframe_end_tick := 0
var params: Dictionary = {}   ## the raw record, for kind-specific tuning


static func seconds_to_ticks(seconds: float) -> int:
	return int(roundf(seconds * TICK_RATE))


static func from_dict(d: Dictionary) -> ActionDef:
	var a := ActionDef.new()
	a.params = d
	a.id = str(d.get("id", ""))
	a.kind = str(d.get("kind", ""))
	a.display_name = str(d.get("display_name", a.id))
	a.hotbar_label = str(d.get("hotbar_label", a.display_name))
	a.power = float(d.get("power", 0.0))
	a.damage_type = str(d.get("damage_type", "physical"))
	a.damage_split = d.get("damage_split", {a.damage_type: 1.0})
	a.ability_multiplier = float(d.get("ability_multiplier", 1.0))
	a.stamina_cost = float(d.get("stamina_cost", 0.0))
	a.essence_cost = float(d.get("essence_cost", 0.0))
	a.fury_cost = float(d.get("fury_cost", 0.0))
	a.cooldown_s = float(d.get("cooldown_s", 0.0))
	a.poise_damage = float(d.get("poise_damage", 0.0))
	a.max_hits_per_target = int(d.get("max_hits_per_target", 1))
	a.tags = PackedStringArray(d.get("tags", []))
	a.category = str(d.get("category", "melee"))
	a.uses_weapon = bool(d.get("uses_weapon", a.kind in ["light", "heavy", "enemy_attack"]))
	a.crit_eligible = bool(d.get("crit_eligible", true))
	a.size_policy = str(d.get("size_policy", "attacker_growth"))
	a.flat_penetration = float(d.get("flat_penetration", 0.0))
	a.chain_next = str(d.get("chain_next", ""))
	a.chain_window_ticks = seconds_to_ticks(float(d.get("chain_window_s", 0.35)))
	a.hit_shape = str(d.get("hit_shape", "none"))
	a.radius_m = float(d.get("radius_m", 0.0))
	a.height_m = float(d.get("height_m", 0.0))
	a.arc = d.get("arc", {})
	a.cancels = d.get("cancels", [])
	a.movement = d.get("movement", {})
	a.knockback_impulse = float(d.get("knockback_impulse", 0.0))
	a.knockback_max_speed = float(d.get("knockback_max_speed", 0.0))
	a.tracking_fraction = float(d.get("tracking_fraction", 0.0))
	a.soft_target_max_deg = float(d.get("soft_target_max_deg", 10.0))
	a.unlock_stage = int(d.get("unlock_stage", 1))
	if a.kind == "dodge":
		# Dodge: "active" is the movement burst, "recovery" the rest of the 0.75 s.
		var total := seconds_to_ticks(float(d.get("duration_s", 0.75)))
		a.windup_ticks = 0
		a.active_ticks = seconds_to_ticks(float(d.get("move_s", 0.45)))
		a.recovery_ticks = maxi(0, total - a.active_ticks)
		a.iframe_start_tick = seconds_to_ticks(float(d.get("iframe_start_s", 0.10)))
		a.iframe_end_tick = seconds_to_ticks(float(d.get("iframe_end_s", 0.30)))
	else:
		a.windup_ticks = seconds_to_ticks(float(d.get("windup_s", 0.0)))
		a.active_ticks = seconds_to_ticks(float(d.get("active_s", 0.0)))
		a.recovery_ticks = seconds_to_ticks(float(d.get("recovery_s", 0.0)))
	return a


func is_attack() -> bool:
	return ATTACK_KINDS.has(kind)


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func param(key: String, default: Variant = null) -> Variant:
	return params.get(key, default)


func move_mult(phase: int) -> float:
	match phase:
		Phase.WINDUP:
			return float(movement.get("windup_speed_mult", 0.0))
		Phase.ACTIVE:
			return float(movement.get("active_speed_mult", 0.0))
		Phase.RECOVERY:
			return float(movement.get("recovery_speed_mult", 0.0))
	return 1.0


## Cancel rule lookup: may `into_group` interrupt this action at `phase`, `ticks_in_phase`?
func allows_cancel(into_group: String, phase: int, ticks_in_phase: int) -> bool:
	for rule: Dictionary in cancels:
		if not (rule.get("into", []) as Array).has(into_group):
			continue
		var rule_phase: int = Phase.RECOVERY
		match str(rule.get("phase", "recovery")):
			"windup":
				rule_phase = Phase.WINDUP
			"active":
				rule_phase = Phase.ACTIVE
		if rule_phase != phase:
			continue
		if ticks_in_phase >= seconds_to_ticks(float(rule.get("after_s", 0.0))):
			return true
	return false

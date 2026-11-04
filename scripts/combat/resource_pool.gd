class_name ResourcePool
extends RefCounted
## Health, stamina, essence and fury for one combatant (spec section 7).
##
## Spending is all-or-nothing and never drives a value below zero. Regeneration is driven by
## explicit tick(dt) calls from the fixed simulation step, so it is deterministic.

## Timers accumulate 1/60 s steps; compare with a tolerance so 60 ticks == 1.0 s exactly.
const TIME_EPSILON := 1e-6

var health := 500.0
var health_max := 500.0
var stamina := 100.0
var stamina_max := 100.0
var essence := 100.0
var essence_max := 100.0
var fury := 0.0
var fury_max := 100.0

var stamina_regen_per_s := 15.0
var stamina_regen_delay_s := 1.0
var essence_regen_per_s := 4.0
var essence_regen_delay_s := 2.0
var fury_decay_per_s := 5.0
var fury_decay_delay_s := 10.0

var since_stamina_spend := 999.0
var since_essence_spend := 999.0
var since_combat := 999.0


func configure(resources: Dictionary, regen: Dictionary) -> void:
	health_max = float(resources.get("health", health_max))
	stamina_max = float(resources.get("stamina", stamina_max))
	essence_max = float(resources.get("essence", essence_max))
	fury_max = float(resources.get("fury_max", fury_max))
	health = health_max
	stamina = stamina_max
	essence = essence_max
	fury = 0.0
	stamina_regen_per_s = float(regen.get("stamina_per_s", stamina_regen_per_s))
	stamina_regen_delay_s = float(regen.get("stamina_delay_s", stamina_regen_delay_s))
	essence_regen_per_s = float(regen.get("essence_per_s", essence_regen_per_s))
	essence_regen_delay_s = float(regen.get("essence_delay_s", essence_regen_delay_s))
	fury_decay_per_s = float(regen.get("fury_decay_per_s", fury_decay_per_s))
	fury_decay_delay_s = float(regen.get("fury_decay_delay_s", fury_decay_delay_s))


func can_spend_stamina(amount: float) -> bool:
	return amount <= stamina + 1e-6


## All-or-nothing spend. Returns false (and spends nothing) when there is not enough.
func spend_stamina(amount: float) -> bool:
	if amount < 0.0:
		push_error("ResourcePool: negative stamina cost %s" % amount)
		return false
	if not can_spend_stamina(amount):
		return false
	stamina = maxf(0.0, stamina - amount)
	if amount > 0.0:
		since_stamina_spend = 0.0
	return true


## Takes up to amount (sprint drain, block impact, guard break). Returns what was taken.
func consume_stamina_up_to(amount: float) -> float:
	var used := clampf(amount, 0.0, stamina)
	stamina -= used
	if amount > 0.0:
		since_stamina_spend = 0.0
	return used


func spend_essence(amount: float) -> bool:
	if amount < 0.0 or amount > essence + 1e-6:
		return false
	essence = maxf(0.0, essence - amount)
	if amount > 0.0:
		since_essence_spend = 0.0
	return true


func spend_fury(amount: float) -> bool:
	if amount < 0.0 or amount > fury + 1e-6:
		return false
	fury = maxf(0.0, fury - amount)
	return true


func add_fury(amount: float) -> void:
	fury = clampf(fury + amount, 0.0, fury_max)


func damage_health(amount: float) -> void:
	health = maxf(0.0, health - maxf(0.0, amount))


func heal(amount: float) -> void:
	health = minf(health_max, health + maxf(0.0, amount))


func mark_combat() -> void:
	since_combat = 0.0


func in_combat() -> bool:
	return since_combat < fury_decay_delay_s


## stamina_regen_allowed is false while sprinting, blocking, or committed to an attack/cast.
func tick(dt: float, stamina_regen_allowed: bool) -> void:
	since_stamina_spend += dt
	since_essence_spend += dt
	since_combat += dt
	if stamina_regen_allowed and since_stamina_spend >= stamina_regen_delay_s - TIME_EPSILON:
		stamina = minf(stamina_max, stamina + stamina_regen_per_s * dt)
	if since_essence_spend >= essence_regen_delay_s - TIME_EPSILON:
		essence = minf(essence_max, essence + essence_regen_per_s * dt)
	if since_combat >= fury_decay_delay_s - TIME_EPSILON:
		fury = maxf(0.0, fury - fury_decay_per_s * dt)


func ratio(name: String) -> float:
	match name:
		"health":
			return health / maxf(health_max, 0.001)
		"stamina":
			return stamina / maxf(stamina_max, 0.001)
		"essence":
			return essence / maxf(essence_max, 0.001)
		"fury":
			return fury / maxf(fury_max, 0.001)
	return 0.0

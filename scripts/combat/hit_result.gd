class_name HitResult
extends RefCounted
## Outcome of resolving one HitEvent against one defender.

enum Outcome { HIT, BLOCKED, PARRIED, GUARD_BROKEN, EVADED, IMMUNE, IGNORED }
const OUTCOME_NAMES := ["hit", "blocked", "parried", "guard_broken", "evaded", "immune", "ignored"]

var outcome: int = Outcome.HIT
var event: HitEvent
var raw_damage := 0.0           ## after crit and weak point, before mitigation
var mitigated_damage := 0.0     ## after armor/resistance, before block (unrounded)
var health_damage := 0          ## applied to health; rounded exactly once
var stamina_damage := 0.0       ## stamina the defender loses (block impact, parry cost)
var poise_damage := 0.0         ## applied to the defender's poise meter
var attacker_poise_damage := 0.0
var stagger_s := 0.0            ## guard-break stagger (poise staggers are added on apply)
var knockback_speed := 0.0
var crit := false
var poise_broken := false
var killed := false
var defender_health_after := 0.0
var notes := ""


func outcome_name() -> String:
	return OUTCOME_NAMES[outcome]


func dealt_damage() -> bool:
	return health_damage > 0

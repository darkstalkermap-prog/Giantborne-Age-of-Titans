class_name DefenseState
extends RefCounted
## Snapshot of a defender's defensive posture at the moment a hit is resolved.

var position := Vector3.ZERO
var forward := Vector3.FORWARD
var height_m := 1.8
var is_dead := false
var blocking := false
var block_elapsed_ticks := 0
var parry_available := false
var invulnerable := false       ## dodge invulnerability window
var stamina := 0.0
var stability := 1.0

# Block tuning (from the block action record).
var parry_window_ticks := 12
var parry_extra_stamina := 5.0
var parry_poise_damage := 40.0
var coverage_deg := 120.0
var physical_reduction := 0.75
var elemental_reduction := 0.5
var impact_stamina_factor := 0.25
var guard_break_damage_fraction := 0.5
var guard_break_stagger_s := 1.0


func apply_block_def(block: ActionDef) -> void:
	if block == null:
		return
	parry_window_ticks = ActionDef.seconds_to_ticks(float(block.param("parry_window_s", 0.2)))
	parry_extra_stamina = float(block.param("parry_extra_stamina", 5.0))
	parry_poise_damage = float(block.param("parry_poise_damage", 40.0))
	coverage_deg = float(block.param("coverage_deg", 120.0))
	physical_reduction = float(block.param("physical_reduction", 0.75))
	elemental_reduction = float(block.param("elemental_reduction", 0.5))
	impact_stamina_factor = float(block.param("impact_stamina_factor", 0.25))
	guard_break_damage_fraction = float(block.param("guard_break_damage_fraction", 0.5))
	guard_break_stagger_s = float(block.param("guard_break_stagger_s", 1.0))


func in_parry_window() -> bool:
	return blocking and block_elapsed_ticks >= 0 and block_elapsed_ticks < parry_window_ticks

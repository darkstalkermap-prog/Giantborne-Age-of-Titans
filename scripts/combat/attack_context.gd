class_name AttackContext
extends RefCounted
## Who is attacking, with what, from where: the per-tick facts HitFactory needs to build hits
## (plan §2.6.5). AttackRunner.context() fills one for an actor's running action; a projectile
## (P03) keeps a snapshot taken at launch, with its own HitRegistry and the impact point as
## attacker_position.
##
## Later packages add fields directly below their own anchor (plan §1.5).

var entity: CombatEntity
var instance_id := 0
var weapon: Dictionary = {}
var growth_stage := 1
## Where the blow comes from: the actor's position for melee and pulses, the impact point for
## projectiles. Block arcs and knockback direction are measured from it.
var attacker_position := Vector3.ZERO
## Dedup registry for this attack: controller.hit_registry, or a projectile's own.
var registry: HitRegistry
## True for area pulses (cylinder and sector pulses, projectile splash): the player's area
## effects skip entities the player may not target (HitFactory.skip_candidate).
var area_effect := false

## @anchor P03
## Projectiles (P03): set on a projectile's snapshot; HitFactory copies them into every hit.
var from_projectile := false
var projectile_id := 0
## Outgoing multipliers frozen when a projectile is launched, so a bolt keeps the Titan Surge it
## was fired with. NAN = read the attacker's statuses when the hit is built (melee, pulses).
var outgoing_damage_mult := NAN
var outgoing_poise_mult := NAN
## @anchor P07


## A copy that later changes to this context cannot affect (projectiles keep one in flight).
func snapshot() -> AttackContext:
	var c := AttackContext.new()
	for p: Dictionary in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			c.set(p.name, get(p.name))
	c.weapon = weapon.duplicate()
	return c

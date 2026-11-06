extends RefCounted
## Schema module for "shrine" records (P05; plan §2.8.3): what a placed Shrine node offers.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
##   {"schema_version": 1, "id": "shrine.kingsfall", "type": "shrine", "display_name": "Kingsfall Shrine",
##    "allows_growth": true, "max_stage": 3, "growth_requires_flags": ["world.ogre_king.defeated"],
##    "checkpoint": true, "rest_heals": true, "first_activation_rest": true, "loadout": true,
##    "attributes": true, "activation_radius_m": 14}
##
## Defaults (the Shrine node applies them when a key is absent): growth_requires_flags [],
## checkpoint, rest_heals, first_activation_rest, loadout and attributes true,
## activation_radius_m 14. growth_locked_message is optional: the player-facing text shown
## when a required flag is missing.

const U := preload("res://scripts/core/schemas/schema_util.gd")


static func fields() -> Dictionary:
	var f := {
		# Whether this shrine can make the giant grow at all, and up to which stage.
		"allows_growth": U.bool_field(true),
		"max_stage": U.int_field(1, 10, true),
		# Every flag here must be truthy before the shrine grows anyone (Kingsfall: the boss).
		"growth_requires_flags": {"t": "array", "items": "string"},
		"growth_locked_message": U.str_field(),
		# The first activation per load is a checkpoint (checkpoint_reached) ...
		"checkpoint": U.bool_field(),
		# ... and a free Rest (first_activation_rest); Rest restores the pools (rest_heals).
		"rest_heals": U.bool_field(),
		"first_activation_rest": U.bool_field(),
		# Shrine-screen tabs that later packages provide (P12: Loadout, Attributes).
		"loadout": U.bool_field(),
		"attributes": U.bool_field(),
		# The shrine activates when the player comes this close (horizontal metres).
		"activation_radius_m": U.pos(),
	}
	# M6-M9 (written by P20, plan M6-M9 §1.5): P26 adds growth_requires_conditions below.
	## @anchor P26

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	var flags: Variant = d.get("growth_requires_flags")
	if typeof(flags) == TYPE_ARRAY:
		var i := 0
		for f: Variant in flags:
			U.check_flag_id(f, "%s.growth_requires_flags[%d]" % [ctx, i], out)
			i += 1
		if not (flags as Array).is_empty() and d.get("allows_growth") == false:
			out.warnings.append("%s: growth_requires_flags has no effect while allows_growth is false" % ctx)
	# M6-M9 (written by P20, plan M6-M9 §1.5).
	## @anchor P26


static func required_ids() -> Dictionary:
	# The sandbox scene places this shrine (tools/builders/sandbox.gd).
	return {"shrine.sandbox": "shrine"}

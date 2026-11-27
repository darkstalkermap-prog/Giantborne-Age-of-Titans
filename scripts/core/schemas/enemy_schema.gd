extends RefCounted
## Schema module for "enemy" records.
## Loaded by DataValidator's registry (see data_validator.gd for the module contract).
##
## Anchors: a package listed below adds its fields under its own anchor in fields() and its
## checks under its own anchor in semantic(), and edits nothing else in this file.

const U := preload("res://scripts/core/schemas/schema_util.gd")
const PERSON_ROLE := preload("res://scripts/core/schemas/person_role_schema.gd")


static func fields() -> Dictionary:
	var f := {
		"archetype": U.str_field(true, DataValidator.ARCHETYPES),
		"height_m": U.pos(true),
		"capsule_radius_m": U.pos(true),
		"health": U.pos(true),
		"stamina": U.pos(),
		"guard": {"t": "dict", "fields": {
			"coverage_deg": U.num(0.0, 360.0, true),
			"min_stamina": U.num(0.0, null, true),
			"turn_rate_deg_s": U.pos(true),
			"physical_reduction": U.num(0.0, 1.0, true),
			"elemental_reduction": U.num(0.0, 1.0, true),
			"impact_stamina_factor": U.num(0.0, null, true),
			"guard_break_damage_fraction": U.num(0.0, 1.0, true),
			"guard_break_stagger_s": U.num(0.0, null, true)}},
		"armor": U.num(0.0),
		"resistances": {"t": "dict", "keys_enum": DataValidator.DAMAGE_TYPES, "values": U.num(-0.5, 0.75)},
		"immunities": {"t": "array", "items": "string", "items_enum": DataValidator.DAMAGE_TYPES + DataValidator.TAGS},
		"attributes": {"t": "dict", "keys_enum": DataValidator.ATTRIBUTES, "values": U.num(0.0)},
		"poise": {"t": "dict", "req": true, "fields": U.poise_fields()},
		"stability": U.pos(),
		"walk_speed_mps": U.pos(true),
		"run_speed_mps": U.pos(true),
		"turn_rate_deg_s": U.pos(true),
		"weapon": U.ref("weapon", true),
		"weapon_pivot_m": {"t": "vec3", "req": true},
		"attack_origin_m": {"t": "vec3", "req": true},
		"arm_length_m": U.pos(true),
		"attacks": {"t": "array", "req": true, "items": "string", "items_ref": "action"},
		"attack_weights": {"t": "array", "items": "number"},
		"ai": {"t": "dict", "req": true, "fields": {
			"sight_range_m": U.pos(true),
			"sight_half_angle_deg": {"t": "number", "gt": 0.0, "max": 180.0, "req": true},
			"hearing_radius_m": U.num(0.0, null, true),
			"memory_s": U.num(0.0, null, true),
			"perception_hz": U.pos(true),
			"decision_hz": U.pos(true),
			"notice_s": U.num(0.0, null, true),
			"attack_range_m": U.pos(true),
			"engage_distance_m": U.pos(true),
			"reposition_radius_m": U.pos(true),
			"strike_pause_min_s": U.num(0.0, null, true),
			"strike_pause_max_s": U.num(0.0, null, true),
			"path_fail_s": U.pos(true),
			"patrol_wait_s": U.num(0.0, null, true),
			"max_attackers": U.int_field(1, null, true),
			"flee_morale": U.num(0.0, 100.0, true),
			"regroup_morale": U.num(0.0, 100.0, true)}},
		"morale": U.num(0.0, 100.0),
		"threat": U.num(0.0, 1.0),
		"lockable": {"t": "bool"},
		"grants_fury": {"t": "bool"},
		"crit_chance": U.num(0.0, 1.0),
		# Experience awarded for a kill (PlayerProgression, P12).
		"xp_reward": U.int_field(0),
	}
	## @anchor P04
	# The scene an EncounterDirector instances (must exist), body mass for grabs, status
	# immunities, caster essence and regen, navigation layers, morale immunity (bosses), and
	# the tactics block read by the archetype brains (plan §2.8.2).
	f.merge({
		"scene": U.str_field(),
		"mass_class": U.str_field(false, DataValidator.MASS_CLASSES),
		"status_immunities": U.enum_array(DataValidator.STATUS_TAGS),
		"essence": U.num(0.0),
		"regen": {"t": "dict", "fields": {
			"stamina_per_s": U.num(0.0), "stamina_delay_s": U.num(0.0),
			"essence_per_s": U.num(0.0), "essence_delay_s": U.num(0.0),
			"fury_decay_per_s": U.num(0.0), "fury_decay_delay_s": U.num(0.0)}},
		"nav_layers": U.int_field(1, 255),
		"ignores_morale": U.bool_field(),
		"tactics": {"t": "dict", "fields": {
			"preferred_min_m": U.num(0.0), "preferred_max_m": U.num(0.0),
			"outmatched_ratio": U.num(0.0),
			"outmatched_behavior": U.str_field(false, DataValidator.OUTMATCHED_BEHAVIORS),
			"spread_m": U.num(0.0), "flank_angle_deg": U.num(0.0, 180.0), "lunge_range_m": U.num(0.0),
			"cover_search_radius_m": U.num(0.0), "launch_gap_s": U.num(0.0),
			"barrier_range_m": U.num(0.0), "charge_min_range_m": U.num(0.0),
			"commander_bonus_morale": U.num(0.0), "formation_spacing_m": U.num(0.0),
			"hold_attack": U.ref("action", false, true),
			"awe_ratio": U.num(0.0), "awe_morale_loss": U.num(0.0),
			# M9 gate: larger targets cost more awe (EnemyBrain.awe_loss_at; the largest ratio met wins)
			# D3: `breaks` - awe at that tier sends the unit running even when its record never flees (flee_morale 0:
			# trolls, ogres, the rimkin), and it routs once its flight ends (a stage-9 giant scatters what fought him)
			"awe_tiers": {"t": "array", "items": "dict", "item_fields": {
				"ratio": U.num(0.0, null, true), "morale_loss": U.num(0.0, null, true), "breaks": {"t": "bool"}}}}},
	})
	(f.ai.fields as Dictionary).merge({
		"awareness_radius_m": U.num(0.0),
		"ally_death_radius_m": U.num(0.0),
		"morale_debounce_s": U.num(0.0),
		"flee_distance_m": U.num(0.0),
		"corpse_linger_s": U.num(0.0),
		# B2: an encounter member's corpse is freed this long after its death instead of the director's corpse_free_s
		# (a titan's body stays a landmark: Stoneback, the Ogre King)
		"corpse_keep_s": U.num(0.0, 3600.0),
		"regroup_needs_leader": U.bool_field(),
		"leader_radius_m": U.num(0.0),
		"rout_after_s": U.num(0.0),
	})

	## @anchor P07
	# How a giant's hand holds this enemy [none = it cannot be grabbed]: torso_fist (soldiers,
	# archers, mages), scruff (wolves), two_hand (ogres, stage 3). The grab point is the scene's
	# Anchors/Grab marker.
	f.merge({"grab_attach": U.str_field(false, DataValidator.GRAB_ATTACH)})

	## @anchor P09

	## @anchor P10a

	## @anchor P11a
	# Boss phases (plan §2.8.2, §3.12): by descending health_frac_below; a phase applies at or
	# below its fraction and phases only advance. A phase with a sequence cycles it in order (the
	# weights are then ignored); enter_action is forced when the phase begins (the Ogre King's roar).
	f.merge({"boss": {"t": "dict", "fields": {
		"phases": {"t": "array", "req": true, "items": "dict", "item_fields": {
			"id": U.str_field(true),
			"health_frac_below": U.num(0.0, 1.0, true),
			"attacks": {"t": "array", "req": true, "items": "string", "items_ref": "action"},
			"attack_weights": {"t": "array", "items": "number"},
			"sequence": {"t": "array", "items": "string", "items_ref": "action"},
			"enter_action": U.ref("action", false, true)}}}}})

	## @anchor P11b
	# Training devices (P11b, plan §3.13 design 6): `unkillable` keeps the health at 1 or more (the
	# sparring post then resets to full); archetype "training" needs the `training` block: it swings
	# every swing_interval_s while a target stands within trigger_radius_m (centre to centre).
	f.merge({
		"unkillable": U.bool_field(),
		"training": {"t": "dict", "fields": {
			"swing_interval_s": U.pos(true),
			"trigger_radius_m": U.pos(true)}},
	})

	## @anchor P12
	# What a kill by the player drops, once per entity id (PlayerProgression, P12); a spawn's
	# own loot_table (EnemyActor.loot_table, set by the director) overrides it.
	f.merge({"loot_table": U.ref("loot_table", false, true)})

	# M6-M9 (written by P20, plan M6-M9 §1.5).
	## @anchor P22
	# The distance (m) beyond which the renderer draws the one-box proxy instead of the rig at AI
	# LOD tiers 0 and 1 (decision 9; 0 or absent = never: the Ogre King). Ranged units' positioning
	# (plan M6-M9 §3.4 design 8): front_arc_deg - firing points within this arc around the camera's
	# yaw (seen from the target) are taken first; off_camera_aim_s - the least windup of a shot
	# drawn from outside the camera's view (the threat cue leads it).
	# M6 gate: outmatched_rout - a unit the giant outmatches (outmatched_ratio) that would regroup
	# after a flight routs instead (EnemyBrain.routs_when_outmatched; the wolves).
	f.merge({"render_lod_m": U.num(0.0, 500.0)})
	(f.tactics.fields as Dictionary).merge({
		"front_arc_deg": U.num(0.0, 360.0),
		"off_camera_aim_s": U.num(0.0, 5.0),
		"outmatched_rout": U.bool_field(),
	})

	## @anchor P30
	# Formations and the target provider (P30, plan M6-M9 §2.10, decisions 19 and 20): a soldier's
	# `role` in a formation (SOLDIER_ROLES; the pike, shield and banner records ship with P30);
	# `targets`, whom the enemy fights besides the giant - NPCs of the listed factions (faction record
	# ids) and intact props carrying one of the listed prop_tags - with `aggro_player_m`, how close a
	# giant it has seen must be to come first (absent: any distance; without `targets` the giant is
	# the only target, the M1-M5 rule); a guard that `breaks_on_tags` (a shield wall: heavies, stomps
	# and sweeps break it whatever its stamina); a banner's `rally` (every interval_s, +morale to the
	# members of its formation within radius_m, through its rally action).
	f.merge({
		"role": U.str_field(false, DataValidator.SOLDIER_ROLES),
		"targets": {"t": "dict", "fields": {
			"teams": {"t": "array", "items": "string", "items_enum": ["player"]},
			"factions": U.ref_array("faction"),
			"prop_tags": {"t": "array", "items": "string"},
			"priority": U.str_field(false, ["nearest"]),
			"aggro_player_m": U.pos()}},
		"rally": {"t": "dict", "fields": {
			"action": U.ref("action", true),
			"interval_s": U.pos(true),
			"morale": U.num(0.0, 100.0, true),
			"radius_m": U.pos(true)}},
	})
	(f.guard.fields as Dictionary)["breaks_on_tags"] = U.enum_array(DataValidator.TAGS)

	## @anchor P32
	# P32 (plan M6-M9 §2.10, §5.11): the cavalry's charge cycle - after a charge it wheels away to a
	# point wheel_min_m..wheel_max_m from the giant before it turns and charges again (CavalryBrain).
	# A siege crew is a soldier of role "crew" (SOLDIER_ROLES) whose engine an encounter's `engines`
	# list names (EncounterDirector); its outmatched_behavior "crew" makes it run when it has none.
	(f.tactics.fields as Dictionary).merge({
		"wheel_min_m": U.num(0.0),
		"wheel_max_m": U.num(0.0),
	})

	## @anchor P34
	# P34 (plan M6-M9 §2.10, §5.11, §5.13): trolls, rival giants and the three bosses.
	#   regeneration  a status (tag Regeneration) the actor refreshes every interval_s while it is hurt
	#                 and carries none of blocked_by_tags (default Burning); it heals hp_per_s each
	#                 interval (phase_hp_per_s: a boss phase's own rate, "2": 40). Fire reaches it: a
	#                 prop tagged "fire" (a brazier) breaking within brazier_radius_m sets Burning for
	#                 brazier_burn_s; a burning body thrown into it sets Burning for thrown_burn_s and
	#                 deals thrown_damage fire damage.
	#   yield_at      the yield protocol (§2.10): at or below health_frac (a floor no blow passes), or
	#                 after poise_breaks poise breaks (challenge_poise_breaks while every
	#                 challenge_conditions quest condition holds: Wildheart's shorter duel), the actor
	#                 kneels, immune and harmless, and `dialogue` decides: its outcome "spare" sets the
	#                 boss_outcome flag to "spared", "strike" either kills it at once (on_strike "kill")
	#                 or makes it fight to the death (on_strike "fight": with strike_health_frac above 0
	#                 the Strike's blow lands first and leaves it that share of its health); boss_id is the id
	#                 boss_yielded carries ("" = its own entity id; Corvane: battle.iron_regiment).
	#   drive_out     the Matriarch's fled ending: once every requires_flags flag holds and its health
	#                 is at or below health_frac it runs to exit_marker and leaves ("fled").
	#   boss_outcome  the flags a boss's ending writes (plan §2.3): `flag` (boss.<short>.outcome: slain,
	#                 spared, fled) and defeated_flag (boss.<short>.defeated, set by every ending).
	#   brood         the Matriarch's whelps: the definition she throws and summons, how far she reaches
	#                 for one, how many of hers may live at once, and the ring her roar's summons appear in.
	f.merge({
		"regeneration": {"t": "dict", "fields": {
			"status": U.ref("status_effect", true),
			"hp_per_s": U.pos(true),
			"phase_hp_per_s": {"t": "dict", "values": U.num(0.0)},
			"interval_s": U.pos(),
			"blocked_by_tags": U.enum_array(DataValidator.STATUS_TAGS),
			"brazier_radius_m": U.pos(),
			"brazier_burn_s": U.pos(),
			"thrown_burn_s": U.pos(),
			"thrown_damage": U.num(0.0)}},
		"yield_at": {"t": "dict", "fields": {
			"health_frac": U.num(0.0, 1.0),
			"poise_breaks": U.int_field(0, 99),
			"challenge_poise_breaks": U.int_field(0, 99),
			"challenge_conditions": {"t": "array", "items": "dict"},
			"dialogue": U.ref("dialogue", true),
			"on_strike": U.str_field(true, ["kill", "fight"]),
			"strike_health_frac": U.num(0.0, 1.0),
			"boss_id": U.str_field()}},
		"drive_out": {"t": "dict", "fields": {
			"requires_flags": {"t": "array", "items": "string"},
			"health_frac": U.num(0.0, 1.0, true),
			"exit_marker": U.str_field(true),
			"leave_s": U.pos()}},
		"boss_outcome": {"t": "dict", "fields": {
			"flag": U.str_field(true),
			"defeated_flag": U.str_field()}},
		"brood": {"t": "dict", "fields": {
			"definition": U.ref("enemy", true),
			"throw_action": U.ref("action", true),
			"reach_m": U.pos(true),
			"max_alive": U.int_field(1, 16),
			"summon_radius_m": {"t": "array", "items": "number"}}},
	})
	# Boss phases (P11a's block) gain: enter_on_poise_breaks - the phase also begins after this many
	# poise breaks (Harrok's second phase after two); hazard - the arena hazard action the phase runs
	# (Harrok's falling stones: an action with an arena_hazard block); summon - how many of the
	# record's brood the phase's enter action calls (the Matriarch's roar: three whelps).
	(((f.boss.fields as Dictionary).phases as Dictionary).item_fields as Dictionary).merge({
		"enter_on_poise_breaks": U.int_field(1, 99),
		"hazard": U.ref("action", false, true),
		"summon": U.int_field(0, 16),
	})

	## @anchor A2
	# A2: a titan's breakable plates over its weak points (PlateRules: the fields and what they do) and the region
	# a hit without a hurtbox strikes; boss phases gain enter_on_plates_broken (the phase also begins once this
	# many plates broke: Stoneback's rage after two) and strike_pause_scale (the pause between its strikes scaled:
	# faster chains). `growth_stage` is the stage a titan tramples and charges through props as (its charge breaks
	# what a giant of that stage walks through).
	f.merge({
		"plates": {"t": "array", "items": "dict", "item_fields": {
			"id": U.str_field(true),
			"region": U.str_field(true),
			"piece": U.str_field(),
			"anchor": U.str_field(),
			"breakable": {"t": "bool"},
			"health": U.num(0.0),
			"reduction": U.num(0.0, 1.0, true),
			"poise_reduction": U.num(0.0, 1.0),
			"weak_multiplier": U.num(0.0, 10.0),
			"heavy_multiplier": U.num(0.0, 10.0),
			"break": {"t": "dict", "fields": {
				"stagger_s": U.num(0.0, 10.0),
				"debris": U.int_field(0, 40),
				"cue": U.str_field()}},
			# A4: added to the plate's lock score (below 0: the lock frames it sooner)
			"lock_bias_m": U.num(-30.0, 30.0),
			# A4: what the break does beyond its stagger (PlateRules.ON_BREAK_EFFECTS: "stagger", or "topple" -
			# down on a knee for down_s, and again after again_damage more to the broken region or the record's
			# topple.again_regions)
			"on_break": {"t": "dict", "fields": {
				"effect": U.str_field(true, PlateRules.ON_BREAK_EFFECTS),
				"down_s": U.num(0.0, 30.0),
				"again_damage": U.num(0.0),
				# B2: "unbalance" (the Ogre King's crown) - every later blow's poise x poise_mult
				"poise_mult": U.num(1.0, 5.0)}},
			# B1: what the plate gives besides his loot table when he dies with it broken (a reason to break more)
			"loot": {"t": "array", "items": "dict", "item_fields": {
				"item": U.ref("item", true), "count": U.int_field(1, 20, true)}}}},
		"plate_default_region": U.str_field(),
		# B2: the lock frames a plate on its own only within the giant's comfortable swing (TitanEnemy: the Ogre King
		# at stages 1-2 keeps P11a's knee framing; the lock-switch still picks a plate in reach)
		"lock_comfortable_only": {"t": "bool"},
		# B4: how near the lock's point a swing's first contact must be to land at once (HitFactory._aimed_swing;
		# AIM_SNAP_M by default, set for Stoneback's size): a smaller titan's plates stand closer together
		"aim_snap_m": U.num(0.1, 10.0),
		"growth_stage": U.int_field(1, 10),
		# A4: a toppled titan (PlateRules.parse_topple): the kneel's and the rise's lengths (his clips'), the
		# multipliers every blow (and a Heavy besides) takes while he is down, the regions whose damage after a
		# topple plate broke counts toward the next topple, the time after he rises before he can go down again, and
		# the time after he rises before his next strike (recover_s: dazed)
		"topple": {"t": "dict", "fields": {
			"kneel_s": U.num(0.0, 5.0),
			"rise_s": U.num(0.0, 5.0),
			"damage_mult": U.num(0.0, 5.0),
			"heavy_mult": U.num(0.0, 5.0),
			"again_regions": {"t": "array", "items": "string"},
			"again_immune_s": U.num(0.0, 120.0),
			"recover_s": U.num(0.0, 10.0)}},
	})
	(((f.boss.fields as Dictionary).phases as Dictionary).item_fields as Dictionary).merge({
		"enter_on_plates_broken": U.int_field(1, 99),
		"strike_pause_scale": U.num(0.05, 4.0),
	})

	## @anchor B3
	# B3 (the Rootwarden): a plate that regrows (PlateRules.parse_regrow: after_s open, over_s growing back,
	# health_frac of its health, burn_sears) and the "wither" break effect's block_s (no plate regrows for that
	# long); a boss phase may begin once a named plate broke (enter_on_plate: his knot); `dormant` (he waits
	# rooted and asleep, his AI off, until a blow or his territory wakes him), `rooted_until_phase` (he does not
	# walk before that boss phase, only turns), `fire` (a prop tagged fire smashed within brazier_radius_m of him
	# sets him Burning for burn_s: TitanEnemy), `hug` (the answer to a giant at his feet: the action struck when
	# the giant stays within within_m of his capsule for hold_s, at most every cooldown_s - TitanBrain).
	(((f.plates as Dictionary).item_fields as Dictionary).on_break.fields as Dictionary).merge({
		"block_s": U.num(0.0, 300.0)})
	((f.plates as Dictionary).item_fields as Dictionary).merge({
		"regrow": {"t": "dict", "fields": {
			"after_s": U.num(0.0, 300.0),
			"over_s": U.num(0.0, 120.0),
			"health_frac": U.num(0.0, 1.0),
			"burn_sears": {"t": "bool"}}}})
	(((f.boss.fields as Dictionary).phases as Dictionary).item_fields as Dictionary).merge({
		"enter_on_plate": U.str_field()})
	f.merge({
		"dormant": {"t": "bool"},
		"rooted_until_phase": U.int_field(1, 9),
		"fire": {"t": "dict", "fields": {
			"brazier_radius_m": U.pos(true),
			"burn_s": U.pos(true)}},
		"hug": {"t": "dict", "fields": {
			"action": U.ref("action", true),
			"within_m": U.pos(true),
			"hold_s": U.num(0.0, 10.0),
			"cooldown_s": U.num(0.0, 60.0)}},
	})

	## @anchor C2
	# C2 (the Broken Warden): a plate may be a shield he guards with (`guard`: PlateRules.parse_guard - the arc and its
	# turn to his left, the shield's top over his feet, the meter and what fills it, how long a broken guard stays open,
	# its stagger, the meter's drain) and may break with the "disarm" effect (the shield falls; his guard is gone); a
	# boss phase may throw a plate down as it begins (drops_plate: his last phase by health); `rubble` - a prop tagged
	# rubble destroyed within radius_m of him falls on him (a stagger, his guard open, every blow's poise x poise_mult
	# for for_s: TitanEnemy).
	((f.plates as Dictionary).item_fields as Dictionary).merge({
		"guard": {"t": "dict", "fields": {
			"arc_deg": U.num(1.0, 360.0),
			"yaw_deg": U.num(-180.0, 180.0),
			"top_m": U.num(0.0, 200.0),
			"meter": U.pos(true),
			"heavy_mult": U.num(0.0, 10.0),
			"light_mult": U.num(0.0, 10.0),
			"ability_mult": U.num(0.0, 10.0),
			"open_s": U.num(0.0, 30.0),
			"stagger_s": U.num(0.0, 10.0),
			"regen_per_s": U.num(0.0, 1000.0),
			"regen_delay_s": U.num(0.0, 30.0)}}})
	(((f.boss.fields as Dictionary).phases as Dictionary).item_fields as Dictionary).merge({
		"drops_plate": U.str_field()})
	f.merge({
		"rubble": {"t": "dict", "fields": {
			"radius_m": U.pos(true),
			"stagger_s": U.num(0.0, 10.0),
			"poise_mult": U.num(1.0, 5.0),
			"for_s": U.num(0.0, 120.0)}},
	})

	## @anchor D1
	# D1 (the Frostbound Titan): `ice` - on a frozen tarn's ice (IceSheet) he breaks through cracked or open ice and
	# goes down to the knee for down_s (his topple's kneel and rise round it), at most every cooldown_s after he rose;
	# a boss phase's `cold_aura` rimes a giant within radius_m by rime_per_s (PlayerRime); `wake_action`, the action
	# forced as he wakes (his intro).
	f.merge({
		"ice": {"t": "dict", "fields": {
			"down_s": U.num(0.0, 30.0, true),
			"cooldown_s": U.num(0.0, 120.0)}},
		"wake_action": U.ref("action"),
	})
	## @anchor D2
	# D2 (the Stormcaller): `storm` - his lightning runs through the storm's water (StormWater; TitanEnemy.storm_strike):
	# a bolt on water min_water_m deep or more sends shock_action to every body standing in water within spread_m (by
	# its wet share); he, standing ground_depth_m deep within that reach, is grounded - down ground_s (his topple's kneel
	# and rise round it), then not again for cooldown_s after he rose.
	f.merge({
		"storm": {"t": "dict", "fields": {
			"shock_action": U.ref("action", true),
			"spread_m": U.pos(true),
			"min_water_m": U.num(0.0, 20.0),
			"ground_depth_m": U.num(0.0, 40.0),
			"ground_s": U.num(0.0, 30.0, true),
			"cooldown_s": U.num(0.0, 120.0)}},
	})
	(((f.boss.fields as Dictionary).phases as Dictionary).item_fields as Dictionary).merge({
		"cold_aura": {"t": "dict", "fields": {
			"radius_m": U.pos(true),
			"rime_per_s": U.num(0.0, 100.0, true)}}})

	# P60 (plan M11 §2.9, §3.13; presentation only): `body`, the people pipeline's body of a human enemy (the role,
	# a named variant, palette overrides, the gear: person_role_schema.body_field()), and `appearance`, the look of a
	# giant enemy (an appearance_preset id; P62 ships the records that use it).
	f.merge({
		"body": PERSON_ROLE.body_field(),
		"appearance": U.ref("appearance_preset", false, true),
	})

	return f


static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void:
	if typeof(d.get("attacks")) == TYPE_ARRAY and (d.attacks as Array).is_empty():
		out.errors.append("%s: attacks must list at least one action" % ctx)
	if typeof(d.get("attack_weights")) == TYPE_ARRAY and typeof(d.get("attacks")) == TYPE_ARRAY:
		if (d.attack_weights as Array).size() != (d.attacks as Array).size():
			out.errors.append("%s: attack_weights must have one entry per attack" % ctx)
	var ai: Variant = d.get("ai")
	if typeof(ai) == TYPE_DICTIONARY and U.is_number(ai.get("strike_pause_min_s")) \
			and U.is_number(ai.get("strike_pause_max_s")):
		if float(ai.strike_pause_min_s) > float(ai.strike_pause_max_s):
			out.errors.append("%s: ai.strike_pause_min_s must be <= ai.strike_pause_max_s" % ctx)
	## @anchor P04
	var scene: Variant = d.get("scene")
	if typeof(scene) == TYPE_STRING:
		if not (scene.begins_with("res://scenes/") and scene.ends_with(".tscn")):
			out.errors.append("%s: scene '%s' must be a res://scenes/....tscn path" % [ctx, scene])
		elif not ResourceLoader.exists(scene):
			out.errors.append("%s: scene '%s' does not exist (run tools/build_scenes)" % [ctx, scene])
	if typeof(ai) == TYPE_DICTIONARY and U.is_number(ai.get("flee_morale")) \
			and U.is_number(ai.get("regroup_morale")) and float(ai.flee_morale) > float(ai.regroup_morale):
		out.errors.append("%s: ai.flee_morale must be <= ai.regroup_morale" % ctx)
	var tactics: Variant = d.get("tactics")
	if typeof(tactics) == TYPE_DICTIONARY:
		if U.is_number(tactics.get("preferred_min_m")) and U.is_number(tactics.get("preferred_max_m")) \
				and float(tactics.preferred_min_m) > float(tactics.preferred_max_m):
			out.errors.append("%s: tactics.preferred_min_m must be <= tactics.preferred_max_m" % ctx)
		var behavior := str(tactics.get("outmatched_behavior", "none"))
		if behavior != "none" and not (U.is_number(tactics.get("outmatched_ratio")) \
				and float(tactics.outmatched_ratio) > 0.0):
			out.errors.append("%s: tactics.outmatched_behavior '%s' needs an outmatched_ratio > 0" % [ctx, behavior])

	## @anchor P07

	## @anchor P09

	## @anchor P10a

	## @anchor P11a
	# Boss phases: at least one; sorted by descending health_frac_below; unique ids; weights match
	# their attacks; every sequence entry is one of the phase's attacks.
	var p11a_boss: Variant = d.get("boss")
	if typeof(p11a_boss) == TYPE_DICTIONARY and typeof(p11a_boss.get("phases")) == TYPE_ARRAY:
		var p11a_phases: Array = p11a_boss.phases
		if p11a_phases.is_empty():
			out.errors.append("%s.boss.phases: must list at least one phase" % ctx)
		var p11a_last := INF
		var p11a_ids := {}
		for i in p11a_phases.size():
			var ph: Variant = p11a_phases[i]
			if typeof(ph) != TYPE_DICTIONARY:
				continue
			var pctx := "%s.boss.phases[%d]" % [ctx, i]
			if U.is_number(ph.get("health_frac_below")):
				if float(ph.health_frac_below) >= p11a_last:
					out.errors.append("%s: phases must be sorted by descending health_frac_below" % pctx)
				p11a_last = float(ph.health_frac_below)
			var pid := str(ph.get("id", ""))
			if p11a_ids.has(pid):
				out.errors.append("%s: duplicate phase id '%s'" % [pctx, pid])
			p11a_ids[pid] = true
			var p_attacks: Variant = ph.get("attacks")
			if typeof(p_attacks) != TYPE_ARRAY:
				continue
			if (p_attacks as Array).is_empty():
				out.errors.append("%s: attacks must list at least one action" % pctx)
			if typeof(ph.get("attack_weights")) == TYPE_ARRAY \
					and (ph.attack_weights as Array).size() != (p_attacks as Array).size():
				out.errors.append("%s: attack_weights must have one entry per attack" % pctx)
			if typeof(ph.get("sequence")) == TYPE_ARRAY:
				for entry: Variant in ph.sequence:
					if typeof(entry) == TYPE_STRING and not (p_attacks as Array).has(entry):
						out.errors.append("%s: sequence entry '%s' is not one of the phase's attacks" % [pctx, entry])

	## @anchor P11b
	# A training device needs its training block; awe needs a loss to apply.
	if str(d.get("archetype", "")) == "training" and typeof(d.get("training")) != TYPE_DICTIONARY:
		out.errors.append("%s: archetype 'training' needs a 'training' block (swing_interval_s, trigger_radius_m)" % ctx)
	if typeof(tactics) == TYPE_DICTIONARY and U.is_number(tactics.get("awe_ratio")) \
			and float(tactics.awe_ratio) > 0.0 and not (U.is_number(tactics.get("awe_morale_loss")) \
			and float(tactics.awe_morale_loss) > 0.0):
		out.warnings.append("%s: tactics.awe_ratio is set but awe_morale_loss is not: awe costs nothing" % ctx)

	## @anchor P12

	# M6-M9 (written by P20, plan M6-M9 §1.5).
	## @anchor P22

	## @anchor P30
	# P30: a banner rallies only as a banner; a target list names at least one kind of target, and
	# its prop tags are plain lowercase words.
	if typeof(d.get("rally")) == TYPE_DICTIONARY and str(d.get("role", "")) != "banner":
		out.errors.append("%s: a rally block needs role 'banner'" % ctx)
	var p30_targets: Variant = d.get("targets")
	if typeof(p30_targets) == TYPE_DICTIONARY:
		var p30_kinds := 0
		for p30_key: String in ["teams", "factions", "prop_tags"]:
			if typeof(p30_targets.get(p30_key)) == TYPE_ARRAY:
				p30_kinds += (p30_targets[p30_key] as Array).size()
		if p30_kinds == 0:
			out.errors.append("%s.targets: names no team, faction or prop tag" % ctx)
		if typeof(p30_targets.get("prop_tags")) == TYPE_ARRAY:
			for p30_tag: Variant in p30_targets.prop_tags:
				if typeof(p30_tag) != TYPE_STRING or RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(p30_tag) == null:
					out.errors.append("%s.targets.prop_tags: '%s' must be a plain lowercase word like 'house'" % [ctx, p30_tag])

	## @anchor P32
	# P32: a wheel band that is not empty; a crew's role and its behaviour go together.
	if typeof(tactics) == TYPE_DICTIONARY and U.is_number(tactics.get("wheel_min_m")) \
			and U.is_number(tactics.get("wheel_max_m")) and float(tactics.wheel_min_m) > float(tactics.wheel_max_m):
		out.errors.append("%s: tactics.wheel_min_m must be <= tactics.wheel_max_m" % ctx)
	if str(d.get("role", "")) == "crew" and typeof(tactics) == TYPE_DICTIONARY \
			and str(tactics.get("outmatched_behavior", "crew")) != "crew":
		out.errors.append("%s: a siege crew (role 'crew') has tactics.outmatched_behavior 'crew'" % ctx)

	## @anchor P34
	# P34: a yield names at least one trigger, and a yield or a drive-out needs the boss_outcome flags it
	# writes; flags are flag ids; challenge conditions are valid quest conditions; a summoning phase has a
	# brood to call; phase regeneration rates name phases that exist.
	var p34_yield: Variant = d.get("yield_at")
	var p34_outcome: Variant = d.get("boss_outcome")
	if typeof(p34_yield) == TYPE_DICTIONARY:
		if float(p34_yield.get("health_frac", 0.0)) <= 0.0 and int(p34_yield.get("poise_breaks", 0)) <= 0:
			out.errors.append("%s.yield_at: needs a health_frac above 0 or poise_breaks" % ctx)
		if typeof(p34_yield.get("challenge_conditions")) == TYPE_ARRAY:
			U.check_conditions(p34_yield.challenge_conditions, "%s.yield_at.challenge_conditions" % ctx, out)
		# M9 gate: the Strike's blow before a boss rises (strike_health_frac) only where he rises (on_strike
		# "fight"), and below his health floor - a blow that left him above the share he yields at would not land.
		var p34_wound := float(p34_yield.get("strike_health_frac", 0.0))
		if p34_wound > 0.0 and str(p34_yield.get("on_strike", "")) != "fight":
			out.errors.append("%s.yield_at.strike_health_frac: only with on_strike 'fight' (he rises from it)" % ctx)
		var p34_floor := float(p34_yield.get("health_frac", 0.0))
		if p34_wound > 0.0 and p34_floor > 0.0 and p34_wound >= p34_floor:
			out.errors.append("%s.yield_at.strike_health_frac (%s) must be below its health_frac (%s)" % [ctx,
				p34_wound, p34_floor])
	var p34_drive: Variant = d.get("drive_out")
	if typeof(p34_drive) == TYPE_DICTIONARY:
		for p34_flag: Variant in p34_drive.get("requires_flags", []):
			U.check_flag_id(p34_flag, "%s.drive_out.requires_flags" % ctx, out)
	if (typeof(p34_yield) == TYPE_DICTIONARY or typeof(p34_drive) == TYPE_DICTIONARY) \
			and typeof(p34_outcome) != TYPE_DICTIONARY:
		out.errors.append("%s: a yield_at or drive_out needs boss_outcome (the flags its ending writes)" % ctx)
	if typeof(p34_outcome) == TYPE_DICTIONARY:
		for p34_key: String in ["flag", "defeated_flag"]:
			if str(p34_outcome.get(p34_key, "")) != "":
				U.check_flag_id(p34_outcome[p34_key], "%s.boss_outcome.%s" % [ctx, p34_key], out)
	var p34_boss: Variant = d.get("boss")
	var p34_phase_count := 0
	if typeof(p34_boss) == TYPE_DICTIONARY and typeof(p34_boss.get("phases")) == TYPE_ARRAY:
		p34_phase_count = (p34_boss.phases as Array).size()
		for p34_ph: Variant in p34_boss.phases:
			if typeof(p34_ph) == TYPE_DICTIONARY and int(p34_ph.get("summon", 0)) > 0 \
					and typeof(d.get("brood")) != TYPE_DICTIONARY:
				out.errors.append("%s.boss.phases: phase '%s' summons, but the record has no brood" % [ctx,
					str(p34_ph.get("id", ""))])
	var p34_regen: Variant = d.get("regeneration")
	if typeof(p34_regen) == TYPE_DICTIONARY and typeof(p34_regen.get("phase_hp_per_s")) == TYPE_DICTIONARY:
		for p34_key: Variant in p34_regen.phase_hp_per_s:
			if not str(p34_key).is_valid_int() or int(str(p34_key)) < 1 or int(str(p34_key)) > p34_phase_count:
				out.errors.append("%s.regeneration.phase_hp_per_s: '%s' is not one of its boss phases (1..%d)" % [
					ctx, p34_key, p34_phase_count])
	## @anchor A2
	# A2: plates with unique ids and regions, health on the breakable ones (PlateRules.errors).
	for a2_err: String in PlateRules.errors(d, ctx):
		out.errors.append(a2_err)
	## @anchor B3
	# C2: a phase that throws a plate down names one of its breakable plates.
	for c2_i in (d.get("boss", {}).get("phases", []) as Array).size() if typeof(d.get("boss")) == TYPE_DICTIONARY \
			and typeof(d.boss.get("phases")) == TYPE_ARRAY else 0:
		var c2_ph: Variant = d.boss.phases[c2_i]
		if typeof(c2_ph) != TYPE_DICTIONARY or str(c2_ph.get("drops_plate", "")) == "":
			continue
		var c2_found := false
		for c2_p: Variant in d.get("plates", []) if typeof(d.get("plates")) == TYPE_ARRAY else []:
			if typeof(c2_p) == TYPE_DICTIONARY and str(c2_p.get("id", "")) == str(c2_ph.drops_plate) \
					and bool(c2_p.get("breakable", true)):
				c2_found = true
		if not c2_found:
			out.errors.append("%s.boss.phases[%d].drops_plate: '%s' is not one of its breakable plates" % [ctx, c2_i,
				str(c2_ph.drops_plate)])
	# B3: a phase entered on a named plate's break names one of its breakable plates.
	var b3_ids := {}
	for b3_p: Variant in d.get("plates", []) if typeof(d.get("plates")) == TYPE_ARRAY else []:
		if typeof(b3_p) == TYPE_DICTIONARY and bool(b3_p.get("breakable", true)):
			b3_ids[str(b3_p.get("id", ""))] = true
	var b3_boss: Variant = d.get("boss")
	if typeof(b3_boss) == TYPE_DICTIONARY and typeof(b3_boss.get("phases")) == TYPE_ARRAY:
		for b3_i in (b3_boss.phases as Array).size():
			var b3_ph: Variant = b3_boss.phases[b3_i]
			if typeof(b3_ph) == TYPE_DICTIONARY and str(b3_ph.get("enter_on_plate", "")) != "" \
					and not b3_ids.has(str(b3_ph.enter_on_plate)):
				out.errors.append("%s.boss.phases[%d].enter_on_plate: '%s' is not one of its breakable plates" % [
					ctx, b3_i, str(b3_ph.enter_on_plate)])
	# P60: a body's palette colours are colours.
	PERSON_ROLE.check_body(d.get("body"), ctx, out)


static func required_ids() -> Dictionary:
	return {"enemy.soldier": "enemy"}

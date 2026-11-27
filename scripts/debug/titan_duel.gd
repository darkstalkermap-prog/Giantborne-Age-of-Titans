class_name TitanDuel
extends RefCounted
## A2: a giant made ready to fight a titan at a chosen stage - the test arena's start option (--titan-stage=N), the
## capture tour and the balance runs use it, so all three meet the same character. Debug only (no save is read or
## written): the growth to stage N through PlayerGrowth's debug path, the experience to that stage's required
## level (PlayerProgression.add_xp), the attribute points spent as the bots spend them (strength and endurance in
## turn: ValleyBot._allocate_points) and the weapon a giant of that stage carries in the campaign (TITAN_WEAPONS:
## the reinforced club at stages 3-4, the titanforged club at 5-6 - and, C3b, at 7-8, carried past its fit as the
## campaign's colossus carries it), full health, stamina and essence, no fury and
## every cooldown spent (called again it only refills them, so a duel starts from the same state).

const OPTION := "--titan-stage="
const DEFAULT_STAGE := 5
const TITAN_WEAPONS := {1: "weapon.club", 2: "weapon.club", 3: "weapon.club_reinforced", 4: "weapon.club_reinforced",
	5: "weapon.club_titan", 6: "weapon.club_titan", 7: "weapon.club_titan", 8: "weapon.club_titan"}


## The stage the command line asks for (OPTION), else `fallback`.
static func cli_stage(fallback := DEFAULT_STAGE) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(OPTION):
			return clampi(int(arg.substr(OPTION.length())), 1, 6)
	return fallback


## The growth profile of `stage` ({} when unknown).
static func profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


## Readies `p` for a titan at `stage`: {ok, stage, level, weapon, health}. The growth goes through the debug
## path (its checks hold in an open arena); with `growth` false only the stage's profile is set (tests that
## place the giant themselves).
static func prepare(p: GiantPlayer, stage: int, growth := true) -> Dictionary:
	var out := {"ok": false, "stage": stage, "level": 0, "weapon": "", "health": 0.0}
	if p == null:
		return out
	var prof := profile(stage)
	if prof.is_empty():
		return out
	if growth and p.growth != null and p.growth.stage() != stage:
		var r: Dictionary = p.growth.debug_set_stage(stage)
		if not bool(r.get("ok", false)):
			p.growth.call("_grow", stage, "debug")   # (busy or not yet on the floor: the growth itself, unchecked)
	elif not growth:
		p.set_profile(prof)
	var prog = p.progression
	var level := int(prof.get("required_level", 1))
	if prog != null:
		var guard := 0
		while int(prog.level) < level and guard < 40:
			prog.add_xp(CombatRules.xp_to_next_level(int(prog.level)), "titan_duel")
			guard += 1
		var flip := 0
		while int(prog.unspent_attribute_points) > 0 and flip < 200:
			prog.allocate({"strength" if flip % 2 == 0 else "endurance": 1})
			flip += 1
		out.level = int(prog.level)
	var weapon := str(TITAN_WEAPONS.get(stage, "weapon.club"))
	if p.equipment != null:
		p.equipment.grant_weapon(weapon, true)
		out.weapon = p.equipment.weapon_id()
	var pools := p.entity.combatant.pools
	pools.health = pools.health_max
	pools.stamina = pools.stamina_max
	pools.essence = pools.essence_max
	pools.fury = 0.0
	p.controller.cooldowns.clear()
	out.health = pools.health_max
	out.ok = p.growth == null or p.growth.stage() == stage or int(p.profile.get("stage", 0)) == stage
	return out


## D2: a stage-9 giant by its numbers (the growth track has no stage 9 yet: no record, no stone, no condition). The
## stage-8 giant readied (prepare), then a profile carried on from stage 7 to 8 by the same steps - every length
## times STAGE9_SCALE (116 ft over 96), the turn and the acceleration a step slower, the resource bonus a step up - and
## the experience to level 17 (the story's stage-9 level), its attribute points spent as prepare spends them. For the
## Stormcaller's duels only ("clearly won at stage-9 numbers"); nothing is saved.
const STAGE9_SCALE := 116.0 / 96.0
const STAGE9_LEVEL := 17


static func stage9_profile() -> Dictionary:
	var p7 := profile(7)
	var p8 := profile(8)
	if p7.is_empty() or p8.is_empty():
		return {}
	var out := p8.duplicate(true)
	out["id"] = "growth.09_numbers"
	out["display_name"] = "Stage 9 (by its numbers: the duels' only)"
	out["stage"] = 9
	out["required_level"] = STAGE9_LEVEL
	for key: String in ["height_m", "capsule_radius_m", "capsule_total_height_m", "melee_reach_m", "camera_distance_m",
			"camera_zoom_min_m", "camera_zoom_max_m", "camera_pivot_height_m", "camera_shoulder_offset_m",
			"step_height_m", "dodge_distance_m", "lock_range_m", "arm_length_m", "weapon_scale", "grab_reach_m",
			"grab_lunge_m", "camera_orbit_scale"]:
		if p8.has(key):
			out[key] = float(p8[key]) * STAGE9_SCALE
	for key: String in ["weapon_pivot_m", "attack_origin_m"]:
		if typeof(p8.get(key)) == TYPE_ARRAY:
			var a: Array = []
			for v: Variant in p8[key]:
				a.append(float(v) * STAGE9_SCALE)
			out[key] = a
	# the steps that are not lengths: carried on as from 7 to 8
	for key: String in ["walk_speed_mps", "acceleration_mps2", "turn_rate_deg_s", "jump_velocity_mps", "footstep_shake",
			"arc_pitch_offset_deg", "lock_half_angle_deg"]:
		if p7.has(key) and p8.has(key):
			out[key] = float(p8[key]) + (float(p8[key]) - float(p7[key]))
	var rb: Dictionary = (p8.get("resource_bonus", {}) as Dictionary).duplicate()
	var rb7: Dictionary = p7.get("resource_bonus", {})
	for key: String in rb:
		rb[key] = float(rb[key]) + (float(rb[key]) - float(rb7.get(key, rb[key])))
	out["resource_bonus"] = rb
	out["unlocks"] = []
	return out


## The weapon a stage-9 giant carries in the duels: the rimforged club (the Colossus Anvil's: the titanforged club the
## stages 7-8 carry, rimforged to fit a colossus).
const STAGE9_WEAPON := "weapon.club_rimforged"


static func prepare_stage9(p: GiantPlayer) -> Dictionary:
	var out := prepare(p, 8)
	var prof := stage9_profile()
	if p == null or prof.is_empty():
		return out
	p.set_profile(prof)
	if p.equipment != null:
		p.equipment.grant_weapon(STAGE9_WEAPON, true)
		out.weapon = p.equipment.weapon_id()
	var prog = p.progression
	if prog != null:
		var guard := 0
		while int(prog.level) < STAGE9_LEVEL and guard < 40:
			prog.add_xp(CombatRules.xp_to_next_level(int(prog.level)), "titan_duel")
			guard += 1
		var flip := 0
		while int(prog.unspent_attribute_points) > 0 and flip < 200:
			prog.allocate({"strength" if flip % 2 == 0 else "endurance": 1})
			flip += 1
		out.level = int(prog.level)
	var pools := p.entity.combatant.pools
	pools.health = pools.health_max
	pools.stamina = pools.stamina_max
	pools.essence = pools.essence_max
	pools.fury = 0.0
	p.controller.cooldowns.clear()
	out.stage = 9
	out.health = pools.health_max
	return out

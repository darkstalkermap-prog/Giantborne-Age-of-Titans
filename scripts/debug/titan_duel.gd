class_name TitanDuel
extends RefCounted
## A2: a giant made ready to fight a titan at a chosen stage - the test arena's start option (--titan-stage=N), the
## capture tour and the balance runs use it, so all three meet the same character. Debug only (no save is read or
## written): the growth to stage N through PlayerGrowth's debug path, the experience to that stage's required
## level (PlayerProgression.add_xp), the attribute points spent as the bots spend them (strength and endurance in
## turn: ValleyBot._allocate_points) and the weapon a giant of that stage carries in the campaign (TITAN_WEAPONS:
## the reinforced club at stages 3-4, the titanforged club at 5-6 - and, C3b, at 7-8, carried past its fit as the
## campaign's colossus carries it; D3: the greatforged club at 9, the Colossus Anvil's stage-9 weapon), full health, stamina and essence, no fury and
## every cooldown spent (called again it only refills them, so a duel starts from the same state).

const OPTION := "--titan-stage="
const DEFAULT_STAGE := 5
const TITAN_WEAPONS := {1: "weapon.club", 2: "weapon.club", 3: "weapon.club_reinforced", 4: "weapon.club_reinforced",
	5: "weapon.club_titan", 6: "weapon.club_titan", 7: "weapon.club_titan", 8: "weapon.club_titan",
	9: "weapon.club_greatforged"}


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


## D3: stage 9 is on the growth track (growth.09), so a stage-9 giant is readied as every other stage (prepare). D2's
## stand-in profile "by its numbers" (stage 8's lengths x116/96) is gone; prepare_stage9 is kept for its callers.
static func prepare_stage9(p: GiantPlayer) -> Dictionary:
	return prepare(p, 9)

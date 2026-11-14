class_name DataValidator
extends RefCounted
## Startup validation for every JSON content record.
##
## Reports every problem it finds (unknown keys, wrong types, negative costs, nonpositive
## heights, invalid timing, unknown enum values, missing references, duplicate ids) and
## never silently "fixes" data. GameData refuses to start the sandbox if any error remains.
##
## Each record type has its own schema module, scripts/core/schemas/<type>_schema.gd, with
##   static func fields() -> Dictionary                    # type-specific field specs
##   static func semantic(d, ctx, out) -> void             # cross-field rules
##   static func required_ids() -> Dictionary              # id -> type the code depends on
## The registry below is pre-declared for every planned type. Only the modules that exist are
## loaded (a missing path is skipped silently), so a later package adds a record type by
## creating its module file - it never edits this file. A record whose type has no module yet
## fails validation, so a type's first records ship together with its module.
## The shared field builders and checkers live in SchemaUtil (schemas/schema_util.gd).

const SUPPORTED_SCHEMA_VERSION := 1
const TICK_RATE := 60
const SCHEMA_DIR := "res://scripts/core/schemas"

## Every planned record type -> its schema module ("<type>_schema.gd"; the writer in brackets).
const SCHEMA_PATHS := {
	"action": "res://scripts/core/schemas/action_schema.gd",                    # P01
	"growth_profile": "res://scripts/core/schemas/growth_profile_schema.gd",    # P01
	"player": "res://scripts/core/schemas/player_schema.gd",                    # P01
	"enemy": "res://scripts/core/schemas/enemy_schema.gd",                      # P01
	"prop": "res://scripts/core/schemas/prop_schema.gd",                        # P01
	"weapon": "res://scripts/core/schemas/weapon_schema.gd",                    # P01
	"item": "res://scripts/core/schemas/item_schema.gd",                        # P01
	"ancestry": "res://scripts/core/schemas/ancestry_schema.gd",                # P01
	"input_bindings": "res://scripts/core/schemas/input_bindings_schema.gd",    # P01
	"status_effect": "res://scripts/core/schemas/status_effect_schema.gd",      # P01
	"progression": "res://scripts/core/schemas/progression_schema.gd",          # P01
	"audio_bank": "res://scripts/core/schemas/audio_bank_schema.gd",            # P19
	"audio_mix": "res://scripts/core/schemas/audio_mix_schema.gd",              # P19
	"music_set": "res://scripts/core/schemas/music_set_schema.gd",              # P19
	"ambience_set": "res://scripts/core/schemas/ambience_set_schema.gd",        # P19
	"audio_region": "res://scripts/core/schemas/audio_region_schema.gd",        # P19
	"shrine": "res://scripts/core/schemas/shrine_schema.gd",                    # P05
	"encounter": "res://scripts/core/schemas/encounter_schema.gd",              # P10a
	"level": "res://scripts/core/schemas/level_schema.gd",                      # P10a
	"loot_table": "res://scripts/core/schemas/loot_table_schema.gd",            # P12
	"npc": "res://scripts/core/schemas/npc_schema.gd",                          # P11b
	"dialogue": "res://scripts/core/schemas/dialogue_schema.gd",                # P13
	"quest": "res://scripts/core/schemas/quest_schema.gd",                      # P13
	"tutorial_prompt": "res://scripts/core/schemas/tutorial_prompt_schema.gd",  # P13
	# M7-M9 (P20 writes the modules; the first records: P22 faction, P25 region and poi, P33
	# talent, P37 wander_table and world_event).
	"region": "res://scripts/core/schemas/region_schema.gd",                    # P20
	"poi": "res://scripts/core/schemas/poi_schema.gd",                          # P20
	"faction": "res://scripts/core/schemas/faction_schema.gd",                  # P20
	"talent": "res://scripts/core/schemas/talent_schema.gd",                    # P20
	"wander_table": "res://scripts/core/schemas/wander_table_schema.gd",        # P20
	"world_event": "res://scripts/core/schemas/world_event_schema.gd",          # P20
}

## type -> loaded schema module (GDScript), built once from the SCHEMA_PATHS files that exist.
static var SCHEMAS: Dictionary = build_registry(SCHEMA_PATHS)
## The record types that can be validated now (= SCHEMAS.keys(), in SCHEMA_PATHS order).
static var RECORD_TYPES: Array = SCHEMAS.keys()

# --------------------------------------------------------------------------- shared enums
# Every value the M2-M5 plan needs is declared here now, so no later package edits an enum.
# P20 added every value of the M6-M9 plan (its §2.15; the audio enums live in the audio schema
# modules): each list's M6-M9 values follow its M2-M5 ones. A weapon's visual shapes are the
# weapon schema's own list (P31 and P32 extend it at their anchors there).

const DAMAGE_TYPES := ["physical", "fire", "frost", "lightning", "arcane", "poison"]
const TAGS := ["Melee", "Ranged", "Magic", "Parryable", "Unparryable", "Unblockable", "Unavoidable",
	"BasicAttack", "Light", "Heavy", "Ability", "AoE", "Projectile", "Grab", "Siege",
	"TreeWeapon", "Throw", "Charge"]
const ACTION_KINDS := ["light", "heavy", "ability", "enemy_attack", "ultimate", "dodge", "block",
	"jump", "sprint"]
const ATTACK_KINDS := ["light", "heavy", "ability", "enemy_attack", "ultimate"]
const HIT_SHAPES := ["weapon_arc", "cylinder_pulse", "none", "sector_pulse", "projectile", "grab",
	"body_sweep",
	"line_pulse", "band_pulse"]   # M6-M9: P31 / P32 lines, P30 a formation's brace band
const ATTACK_CATEGORIES := ["melee", "ability", "projectile", "magic", "siege"]
const PROP_CATEGORIES := ["cosmetic", "breakable", "structural", "training_target"]
const ARCHETYPES := ["soldier", "archer", "mage", "wolf", "ogre", "boss", "training",
	"troll", "rival_giant", "cavalry"]   # M6-M9: P34 trolls and rival giants, P32 cavalry
## A soldier record's "role" in a formation or a siege crew (P30, P32).
const SOLDIER_ROLES := ["line", "pike", "shield", "banner", "crew"]
const WEAPON_FAMILIES := ["club", "sword", "hammer", "axe", "fists", "tree", "bow", "staff", "jaws",
	"natural"]
const ATTRIBUTES := ["strength", "endurance", "dexterity", "intellect", "willpower", "constitution"]
const CANCEL_INTO := ["light", "heavy", "dodge", "block", "ability", "jump"]
const PHASES := ["windup", "active", "recovery"]
const SIZE_POLICIES := ["attacker_growth", "none",
	"fixed"]   # M6-M9
const INTERRUPT_POLICIES := ["hard_stagger", "super_armor"]
const INTERACTION_PERMISSIONS := ["grab_small", "throw_boulder", "tree_weapon", "gate_breach",
	"formation_sweep", "siege_disruption", "monster_grapple", "titan_execution",
	"heave", "trample"]   # M6-M9: P26 (stage 5 heave, stage 4 trample)
const STATUS_STACKING := ["refresh_no_stack", "strongest_wins", "independent"]
const STATUS_MODIFIERS := ["armor_flat", "slow_fraction", "outgoing_damage_mult", "outgoing_poise_mult",
	"fury_gain_mult", "heal_per_tick", "damage_taken_mult",
	# M6-M9: the talents' and ancestries' passives (P33, §5.12) use only these and the keys above.
	"heal_received_mult", "stamina_cost_mult", "essence_cost_mult", "cooldown_mult", "poise_threshold_add",
	"poise_damage_taken_mult", "grab_reach_add", "fury_on_kill_add", "move_speed_mult",
	"elemental_resist_add", "health_add", "stamina_add", "essence_add", "heavy_damage_mult",
	"throw_damage_mult", "magic_damage_mult"]
const STATUS_TAGS := ["Buff", "Debuff", "Slow", "Fear", "Heal", "Barrier", "Ultimate",
	"Burning", "Regeneration"]   # M6-M9: P34 (a troll regenerates unless it burns)
const MASS_CLASSES := ["small", "medium", "large", "immovable"]
const PROJECTILE_VISUALS := ["bolt", "boulder", "arrow", "thrown_body",
	"ballista_bolt", "catapult_stone", "rune_lance", "storm_bolt", "engine"]   # M6-M9: P31, P32
const AIM_MODES := ["lock_or_camera", "camera", "target", "forward"]
const TELEGRAPH_SHAPES := ["circle", "line", "cone"]
const GRAB_ATTACH := ["none", "torso_fist", "scruff", "two_hand"]
const OUTMATCHED_BEHAVIORS := ["none", "formation", "harass", "spread", "kite", "retreat",
	"crew", "charge"]   # M6-M9: P32 (siege crews, cavalry)
const NPC_ROLES := ["civilian", "talker"]
const ITEM_CATEGORIES := ["material", "quest", "trophy", "key"]
const DODGE_STYLES := ["roll", "sidestep"]
const CONDITION_TYPES := ["flag", "entered", "killed", "encounter_cleared", "destroyed", "has_item",
	"hits_on", "stage_at_least", "level_at_least", "weapon_equipped", "dialogue_outcome", "all", "any",
	"not",
	# M6-M9 (§2.12): P20 evaluates count, quest_done, level_is, ancestry_is and ancestry_chosen;
	# discovered and region_entered (P27), event_done (P37) and near (P29) are evaluated below their
	# packages' anchors in QuestConditions.
	"count", "quest_done", "level_is", "discovered", "region_entered", "ancestry_is",
	"ancestry_chosen", "event_done", "near"]
const BOT_ACTIONS := ["go", "fight_encounter", "kill", "attack", "break", "hurl_at", "interact", "talk",
	"grow", "rest", "equip", "wait",
	"travel", "fast_travel", "discover", "breach", "protect", "duel", "choose_ancestry", "heave",
	"burn"]   # M6-M9: the world bot's (P38)
const TUTORIAL_TRIGGERS := ["entered", "flag", "level", "stage", "event"]
const TUTORIAL_DISMISS := ["action_kind", "action_id", "event", "flag", "timeout"]
const TUTORIAL_EVENTS := ["camera_mode_changed", "lock_target_changed", "ability_started",
	"telegraph_started", "hit_resolved", "staggered", "grab_started", "boss_phase_changed", "interacted",
	"attributes_changed", "shrine_activated", "encounter_activated",
	"poi_discovered", "region_changed", "formation_changed", "size_gate_blocked", "level_entered",
	"ability_evolved"]   # M6-M9 (Quests forwards each to the tutorial director)
## A point of interest's kind (poi records, P25; §2.7).
const POI_KINDS := ["settlement", "shrine", "waystone", "ruin", "landmark", "camp", "lair", "boss",
	"forge", "gate", "vista", "exit", "secret"]
## A faction's standing toward the giant at the start (faction records; §2.12).
const FACTION_INITIAL := ["neutral", "hostile"]
## A forge's tier: iron reinforces, titan also titanforges (P31; §2.11).
const FORGE_TIERS := ["iron", "titan"]
const ID_REGEX := "^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$"


## Loads the schema module of every declared type whose file exists. Missing files are skipped
## without any error (they belong to packages that have not landed yet).
static func build_registry(paths: Dictionary) -> Dictionary:
	var out := {}
	for type: String in paths:
		var path: String = paths[type]
		if ResourceLoader.exists(path):
			var module: Variant = load(path)
			if module != null:
				out[type] = module
	return out


## Every id that shipped code looks up unconditionally (id -> type): the merge of every
## module's required_ids(). Missing or mistyped -> startup error.
static func required_records() -> Dictionary:
	var out := {}
	for type: String in SCHEMAS:
		out.merge(SCHEMAS[type].required_ids(), true)
	return out


## Validates one parsed JSON document.
## Returns {"errors": PackedStringArray, "warnings": PackedStringArray, "refs": Array}.
## refs holds {"ctx", "id", "type"} entries that validate_references() checks later.
static func validate_record(rec: Variant, path: String) -> Dictionary:
	var out := {"errors": PackedStringArray(), "warnings": PackedStringArray(), "refs": []}
	if typeof(rec) != TYPE_DICTIONARY:
		out.errors.append("%s: top-level JSON value must be an object" % path)
		return out
	var d: Dictionary = rec
	var ctx := path
	var id_value: Variant = d.get("id")
	if typeof(id_value) == TYPE_STRING:
		ctx = "%s (%s)" % [path, id_value]
		var re := RegEx.create_from_string(ID_REGEX)
		if re.search(id_value) == null:
			out.errors.append("%s: id '%s' must be lowercase dotted form like 'ability.light_1'" % [ctx, id_value])
	var version: Variant = d.get("schema_version")
	if SchemaUtil.is_number(version) and int(version) > SUPPORTED_SCHEMA_VERSION:
		out.errors.append("%s: schema_version %d is newer than supported version %d" % [
			ctx, int(version), SUPPORTED_SCHEMA_VERSION])
		return out
	var type_value: Variant = d.get("type")
	if typeof(type_value) != TYPE_STRING or not RECORD_TYPES.has(type_value):
		out.errors.append("%s: 'type' must be one of %s (got %s)" % [ctx, RECORD_TYPES, type_value])
		return out
	SchemaUtil.check_fields(d, schema_for(type_value), ctx, out)
	SCHEMAS[type_value].semantic(d, ctx, out)
	return out


## Cross-record checks: every reference must exist and point to a record of the right type.
static func validate_references(records: Dictionary, refs: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	for ref: Dictionary in refs:
		var target: String = ref.id
		if not records.has(target):
			errors.append("%s: missing reference '%s' (expected a %s record)" % [ref.ctx, target, ref.type])
		elif records[target].get("type") != ref.type:
			errors.append("%s: reference '%s' is a %s, expected %s" % [
				ref.ctx, target, records[target].get("type"), ref.type])
	return errors


## The full field schema of one record type: the base fields plus the module's fields().
static func schema_for(type: String) -> Dictionary:
	var s := {
		"schema_version": SchemaUtil.int_field(1, null, true),
		"id": SchemaUtil.str_field(true),
		"type": SchemaUtil.str_field(true, RECORD_TYPES),
		"display_name": SchemaUtil.str_field(),
		"description": SchemaUtil.str_field(),
	}
	if SCHEMAS.has(type):
		s.merge(SCHEMAS[type].fields())
	return s

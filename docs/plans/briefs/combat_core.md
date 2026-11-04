# Brief: combat core (M0/M1 code as merged) — for M2–M5 planners and implementers

Scope: `scripts/combat/*.gd`, `scripts/core/sim.gd`, `scripts/core/events.gd`,
`scripts/adapters/hit_query_adapter.gd`, `data/abilities/*.json`, `data/actions/*.json`, plus the
two actors that produce hits (`scripts/actors/giant_player.gd`, `scripts/actors/soldier_enemy.gd`)
and the action schema in `scripts/core/data_validator.gd`. Line numbers are from the merged M1 code.

## 1. Files and responsibilities

| File | Responsibility |
| --- | --- |
| `combat/action_def.gd` | `ActionDef`: a typed, cached view of one action JSON record. Converts seconds to 60 Hz ticks once. Handles cancel-rule lookup and movement multipliers per phase. |
| `combat/combat_controller.gd` | `CombatController`: the state machine for one actor. Covers requests, validation, cost and cooldown commit, timelines, cancels, the buffer, block/parry, stagger and death. Engine-free. |
| `combat/combat_entity.gd` | `CombatEntity` (Node child of an actor): owns a `Combatant`, collects Hurtboxes and occluder RIDs, registers with Sim, applies `HitResult`s (resources, stagger, death, fury, events). |
| `combat/combatant.gd` | `Combatant`: stats, armor, resistances, immunities, crit and stability, built from a record. Owns a `ResourcePool` and a `PoiseMeter`. |
| `combat/combat_rules.gd` | `CombatRules`: pure formulas (size multiplier, raw damage, armor, resistance, poise scale, knockback, impact stamina, block arc, Dexterity, Willpower, XP). |
| `combat/damage_resolver.gd` | `DamageResolver`: pure `HitEvent` + `Combatant` + `DefenseState` → `HitResult`. |
| `combat/defense_state.gd` | `DefenseState`: a snapshot of the defender's posture (block, parry window, i-frames, stamina, block tuning). |
| `combat/hit_event.gd` | `HitEvent`: one attack instance touching one target. Also defines the stable sort `compare_stable`. |
| `combat/hit_result.gd` | `HitResult`: the outcome enum and the numbers that get applied. |
| `combat/hit_registry.gd` | `HitRegistry`: dedup keyed by (instance_id, pulse_id, entity_id). |
| `combat/hurtbox.gd` | `Hurtbox` (Area3D, layer value 4 = layer 3): `region` and `weak_point` exports, plus a back-pointer `entity`. |
| `combat/input_buffer.gd` | `InputBuffer`: one slot, 9 ticks, newest request wins. |
| `combat/cooldowns.gd` | `Cooldowns`: ready-tick per action id. |
| `combat/resource_pool.gd` | `ResourcePool`: health, stamina, essence and fury, with regen and decay in `tick(dt, …)`. |
| `combat/poise_meter.gd` | `PoiseMeter`: accumulation, threshold, recovery and post-stagger immunity. |
| `combat/attack_geometry.gd` | `AttackGeometry`: the arc, pose and segment math shared by the hit sweep and the rig. |
| `combat/targeting_rules.gd`, `lock_on_tracker.gd` | Lock-on math and state (not covered further here). |
| `core/sim.gd` | Autoload `Sim`: the 60 Hz driver, actor and entity registries, `rng`, instance ids, pending-hit queue and stable resolution, attack tokens. |
| `core/events.gd` | Autoload `Events`: the global signal bus. |
| `adapters/hit_query_adapter.gd` | `HitQueryAdapter`: capsule sweeps, cylinder pulses, line-of-sight rays, physics layer constants. |

## 2. Key classes and APIs

### ActionDef (`RefCounted`)
- Enum `Phase { NONE, WINDUP, ACTIVE, RECOVERY, DONE }`. `ATTACK_KINDS = ["light","heavy","ability","enemy_attack","ultimate"]`.
- Fields: `id, kind, display_name, hotbar_label, power, damage_type, damage_split` (defaults to `{damage_type: 1.0}`), `ability_multiplier, stamina_cost, essence_cost, fury_cost, cooldown_s, windup_ticks, active_ticks, recovery_ticks, poise_damage, max_hits_per_target, tags (PackedStringArray), category` ("melee" default), `uses_weapon` (defaults to true for light/heavy/enemy_attack), `crit_eligible` (true default), `size_policy` ("attacker_growth"|"none"), `flat_penetration, chain_next, chain_window_ticks, hit_shape` ("weapon_arc"|"cylinder_pulse"|"none"), `radius_m, height_m, arc, cancels, movement, knockback_impulse, knockback_max_speed, tracking_fraction, soft_target_max_deg, unlock_stage, interrupt_policy` ("hard_stagger"|"super_armor"), `iframe_start_tick, iframe_end_tick`, and `params` (the raw dict).
- `static from_dict(d)`: dodge timing comes from `duration_s`/`move_s`/`iframe_*` (lines 94-101). Other kinds use `windup_s`/`active_s`/`recovery_s`.
- `is_attack()`, `has_tag(t)`, `param(key, default)` (use this for kind-specific tuning such as `parry_window_s`, `distance_m`, `velocity_mps`), `move_mult(phase)`, and `allows_cancel(into_group, phase, ticks_in_phase)`. The cancel phase defaults to "recovery".
- Loaded once by `GameData._actions` (id → ActionDef). Get one with `GameData.get_action(id)`.

### CombatController (`RefCounted`, one per actor)
- `enum State { LOCOMOTION, ATTACKING, BLOCKING, DODGING, CASTING, STAGGERED, GRABBED, EXECUTING, DEAD }`. **CASTING, GRABBED and EXECUTING already exist.** CASTING is entered by kind "ability"/"ultimate" (line 382). Nothing enters GRABBED or EXECUTING yet.
- `enum Verdict { ACCEPT, RETRY, REJECT }`.
- Signals: `action_started(action, instance_id)`, `action_ended(action, instance_id, interrupted)`, `request_rejected(kind, action_id, reason)`, `state_changed(old, new)`, `staggered(duration_s, reason)`.
- Vars: `actor_id, combatant, state, action, instance_id, elapsed, now, growth_stage, on_floor, recovery_scale, cooldowns, buffer, hit_registry, loadout` (keys "light","heavy","dodge","block","jump","slot_1".."slot_8","ultimate" → action id), `library` (id → ActionDef the actor may run), `chain_next_id, chain_expire_tick, block_def, block_start_tick, block_held, parry_available, min_block_ticks, stagger_ticks_left`.
- Per tick: `begin_tick(now)` advances `elapsed` for ATTACKING/CASTING/DODGING, finishes at `_total_ticks()`, counts down stagger, ends a released block, expires or consumes the buffer. Then `request(kind, params) -> Verdict`. Kinds: `&"light", &"heavy", &"dodge", &"block", &"block_release", &"jump", &"slot"` (`{"slot": n}`), `&"ultimate"`, `&"attack"` (`{"action_id": id}`, used by AI).
- Queries: `phase()`, `ticks_in_phase()`, `phase_fraction()`, `active_fraction()`, `active_fraction_prev()`, `is_first_active_tick()`, `is_invulnerable()` (DODGING only), `block_elapsed_ticks()`, `is_committed()`, `can_rotate()`, `move_speed_multiplier()`, `stamina_regen_allowed(sprinting)`, `state_name()`, `action_id()`, `next_light_id()`.
- Reactions: `on_block_impact(failed_parry)`, `apply_stagger(seconds, reason) -> bool` (false under super_armor), `kill()`, `resume_held_block()`.
- Wiring: `set_instance_source(Sim.new_instance_id)` and `add_action(def)`.

### CombatEntity (`Node`, must be a direct child of the actor; actor scripts use `$CombatEntity`)
- Exports: `entity_id, definition_id, team (Team.NEUTRAL/PLAYER/ENEMY), anchor_path, height_override_m`. The id is overridden by the actor's `entity_id` or `world_id` property.
- Signals: `hit_taken(result)`, `hit_landed(result)`, `died(killer_id)`, `staggered(duration_s, reason)`.
- `static can_damage(attacker_team, target_team)`: PLAYER hits non-PLAYER, ENEMY hits only PLAYER, NEUTRAL hits nothing.
- `receive_hit(hit, attacker) -> HitResult`, `_apply(result, attacker)` (the single place hits mutate state), `_on_hit_landed` (fury), `apply_poise_damage(amount, reason)`, `stagger(seconds, reason)`, `build_defense_state()`, `is_alive()`, `is_lockable()`, `anchor_position()`.
- Optional actor duck-typed hooks: `get_defense_state()`, `accepts_hit(hit)`, `apply_knockback(dir, speed)`, `on_entity_died(killer_id)`, `flash(strength)`.
- Groups (set by actors): "player" (GiantPlayer), "enemies" (SoldierEnemy), "dummies", "breakables", "sandbox", "debris_pool".

### Combatant / ResourcePool / PoiseMeter
- `Combatant.from_record(entity_id, rec, height_override)`. Endurance adds +15 health and +2 stamina per point over 10; Intellect adds +2 essence per point; Constitution adds +3 poise threshold. `resistance(type)` adds the Willpower bonus for non-physical types and clamps to −0.5..0.75. `is_immune_to(type_or_tag)` is a flat `immunities` list check.
- `ResourcePool`: `can_spend_stamina`, `spend_stamina` (all-or-nothing), `consume_stamina_up_to`, `spend_essence`, `spend_fury`, `add_fury` (clamped, **no gating**), `damage_health`, `heal` (caps at max), `mark_combat`, `in_combat`, `tick(dt, stamina_regen_allowed)`, `ratio(name)`. Regen: stamina regenerates after `since_stamina_spend >= delay`, and only if allowed. Essence regenerates after `since_essence_spend >= delay`; only `spend_essence` resets that timer. Fury decays after 10 s without `mark_combat`. There is **no health regen**.
- `PoiseMeter`: `add(amount) -> bool broke`, `begin_stagger()`, `end_stagger()` (starts `immunity_s`), `tick(dt)`, `is_immune()`, and `locked` (true while staggered).

### HitEvent fields
`tick, instance_id, pulse_id, attacker_id, target_id, action_id, power, ability_multiplier, weapon_multiplier, attacker_stat, attacker_height_m, size_policy, damage_split, poise_damage, tags, crit, crit_multiplier, weak_point, flat_penetration, outgoing_damage_mult` (reserved for Titan Surge, never set today), `outgoing_poise_mult` (likewise), `knockback_impulse, knockback_max_speed, attacker_position, hit_point, substep, distance, category, attacker_growth_stage`. `compare_stable` orders hits by attacker_id, instance_id, pulse_id, substep, distance, target_id.

### HitResult
`enum Outcome { HIT, BLOCKED, PARRIED, GUARD_BROKEN, EVADED, IMMUNE, IGNORED }`. Fields: `event, raw_damage, mitigated_damage, health_damage (int), stamina_damage, poise_damage, attacker_poise_damage, stagger_s, knockback_speed, crit, poise_broken, killed, defender_health_after, notes` ("parry", "block", "failed_parry", "guard_broken", "immune", "invulnerable", "target_dead", "not_permitted").

### DamageResolver (pure)
- `mitigate(hit, defender)`: raw = `CombatRules.raw_damage(power, attacker_stat, ability_mult, weapon_mult, size_mult) * outgoing_damage_mult`. Then ×crit_multiplier if `hit.crit`, then ×1.25 if `weak_point`. Then each `damage_split` portion, in sorted type order: physical uses `defender.armor − flat_penetration` (line 39); other types use `defender.resistance(t)`. Immune types are skipped. A tag in `defender.immunities` makes the whole hit immune.
- `resolve(hit, defender, defense)`: dead → IGNORED; `defense.invulnerable` without the `Unavoidable` tag → EVADED; immune → IMMUNE. Parry needs guarding (blocking and inside the arc measured from `hit.attacker_position`), tags `Melee` and `Parryable` but not `Unparryable`, `parry_available`, the parry window, and enough stamina. Block needs guarding and not `Unblockable`, with impact stamina ≤ stamina; otherwise the result is GUARD_BROKEN. On HIT, `poise_damage = hit.poise_damage * outgoing_poise_mult * poise_scale(attacker_h, defender_h)`. Knockback uses `size_ratio / stability`, halved on a block.

### Sim (autoload)
`TICK_RATE=60, DT, DEFAULT_SEED=20261104, tick, rng`. `register_actor(id, node)` / `unregister_actor` (node must implement `sim_step(tick, dt)`). `register_entity` / `unregister_entity` / `get_entity` / `entities()` (sorted by id). `new_instance_id()`, `queue_hit(hit)`, `clear_pending()`, `pending_hit_count()`, `request_token` / `release_token` / `release_all_tokens` / `token_holders`, `reseed(seed)`, `step()`.

### Events (autoload) signals
`ability_started(tick, actor_id, action_id, instance_id)` (**emitted by actors** in `_on_action_started`, not by the controller), `action_rejected`, `hit_resolved(tick, result)`, `attack_clanked`, `area_pulse(tick, actor_id, action_id, center, radius)`, `entity_died`, `staggered`, `object_destroyed`, `loot_awarded`, `growth_changed` (declared, unused), `lock_target_changed`, `camera_mode_changed`, `hud_message(text, kind)`, `sandbox_reset_requested`.

### HitQueryAdapter
Layers: `LAYER_WORLD=1, LAYER_ACTORS=2, LAYER_HURTBOX=4, LAYER_DEBRIS=8, LAYER_BREAKABLE=16, OCCLUDER_MASK=WORLD|BREAKABLE`. `sweep_capsule(space, attacker, origin, prev_a, prev_b, cur_a, cur_b, radius)` sub-steps at ≤ 0.75·radius, up to 16 per tick. `cylinder_pulse(space, attacker, center, radius, height, los_origin)`. Candidates look like `{entity, hurtbox, point, substep, distance, weak_point}`, already filtered by team and occlusion. Also `intersect_all` (buffer grows to 4096), `line_clear`, `first_world_hit`, `basis_y_to`.

## 3. Data flow and invariants

Per tick: `Sim.step()` increments `tick`, then calls `sim_step` on each actor in **sorted entity-id order**, then `_resolve_hits()`. Inside `GiantPlayer.sim_step` (lines 133-154) the order is: intents → `controller.begin_tick` → meta, then `_handle_actions` (requests) → `resume_held_block` → sprint → facing → movement (`move_and_slide`) → `_run_hit_queries` (queues HitEvents) → `pools.tick` → `poise.tick` → lock. `SoldierEnemy.sim_step` (95-113) does `begin_tick` → perceive at 5 Hz → decide at 10 Hz → `request(&"attack")` → facing → movement → hits → pools → poise. `PracticeDummy` only refills health. **BreakableProp is not a Sim actor**, so nothing ticks for it.

Invariants (tests depend on all of them):
1. Costs and the cooldown are committed **once**, in `_accept` (lines 354-361). Requests that are rejected or waiting in the buffer spend nothing. A rejection always emits `request_rejected` with a reason code: `dead, empty_slot, unknown_action, locked, cooldown, already_blocking, airborne, stamina, essence, fury`.
2. Check order in `_evaluate` (250-300): dead → resolve → unlock_stage → cooldown → state/cancel (RETRY "busy") → airborne → stamina → essence → fury. RETRY is only for state or timing; everything else is REJECT.
3. Timing: an action accepted at tick T has `elapsed=0` on T. Light attacks are active at elapsed 12-20 and finish at 39. Dodge i-frames cover elapsed [6,17). Parry is `block_elapsed_ticks < 12`. The buffer is live until T+9 inclusive. Cooldowns are ready at `now >= start + round(s*60)`. `recovery_scale` (Dexterity) shortens recovery for `is_attack()` kinds only.
4. Hit dedup is per (instance_id, pulse_id, entity_id), never per collider. `hit_registry.forget(instance)` runs when the action finishes.
5. Hits resolve in `compare_stable` order. Hits from an attacker that died earlier in the same pass are dropped (sim.gd 189). Dead targets → IGNORED, which produces no events and no fury.
6. Death happens once (`combatant.dead` guard in `_apply`). `unkillable` floors health at 1.
7. Damage is rounded once (`CombatRules.round_damage`). The worked examples are pinned by tests: light 37, heavy 66 and Footfall 44 against armor 25; block 9 health / 10 stamina.
8. Fury: +4 once per BasicAttack instance (`_fury_instances`), +6 per parry, +8 per kill, only when the target has `grants_fury`. Every non-IGNORED exchange calls `mark_combat` for both sides.
9. Crits are rolled at **queue time** in the actor (`Sim.rng.randf() < crit_chance`, giant_player.gd 493). The test runner reseeds `Sim.rng` before each test (`tests/test_runner.gd:49`).
10. Presentation and UI never mutate combat state. The HUD reads `controller.loadout`, `controller.cooldowns.remaining_s/remaining_fraction` (`ui/hud.gd` 406-432). The rig reads `action.hit_shape` and `phase` (`actor_rig.gd` ~99-117).
11. Data: the validator treats **unknown JSON keys as errors**. Each enum list (`ACTION_KINDS, TAGS, HIT_SHAPES, ATTACK_CATEGORIES, CANCEL_INTO, DAMAGE_TYPES, INTERRUPT_POLICIES`) is closed. Attack kinds must carry `power, damage_type, ability_multiplier, stamina_cost, cooldown_s, windup_s, active_s(>0), recovery_s, poise_damage, max_hits_per_target, tags, hit_shape`. Test pins: `test_data_and_saves.gd:31-32` (Footfall numbers), `test_controller.gd` (timings, buffer, cooldown spam on slot_1 = Footfall), and `test_hits_integration.gd:86-104` (Footfall pulse and its cooldown).

## 4. Extension points: how to add each M2–M5 feature

**Schema first (every feature):** add each new action key to `DataValidator.schema_for("action")` (data_validator.gd ~142-212), add semantic checks to `_semantic_action` (~489), extend the enum consts (lines 14-29), and read the key in `ActionDef.from_dict` as a typed field (or use `param()`).

**a. Casting and spells (Runic Bolt uses Intellect).** CASTING already exists and pauses stamina regen. What is missing is an effect hook: an ability whose `hit_shape` is "none" does nothing today. Add to CombatController a signal `action_phase_entered(action, instance_id, phase)` (emitted from `begin_tick`, and from `_accept` when `windup_ticks == 0`), or let actors poll `is_first_active_tick()` as Footfall does (giant_player.gd 456). Add `ActionDef.effects: Array` (for example `{"type":"projectile"|"pulse"|"self_status"|"heal"}`) plus `effect_tick`. Intellect scaling already exists: `e.attacker_stat = intellect if a.category == "magic"` (giant_player.gd 487), so Runic Bolt needs `category:"magic"`, `damage_type:"arcane"`, `uses_weapon:false` and `size_policy:"none"` (the spec default for spells is M_size = 1). Add `"Magic"` and `"Projectile"` tags (they are already in TAGS).

**b. Projectiles (Boulder Hurl, Runic Bolt, arrows, mage bolts).** Add `scripts/combat/projectile.gd` (pure state: pos, vel, gravity, radius, range_m, owner_id, instance_id, pulse_id, plus a HitEvent template snapshot) and a `ProjectileSystem` stepped by Sim. Add a `Sim.step` phase between the actor loop and `_resolve_hits()`, stepping projectiles in spawn-id order. Add `HitQueryAdapter.sweep_sphere(space, owner, from, to, radius)` using the same sub-step and occluder rules as `sweep_capsule`. Make the first world hit stop the projectile. Use a projectile-owned `HitRegistry` or dedup set, **not** `controller.hit_registry`, because the action finishing calls `forget(instance)` (combat_controller.gd 413) while the projectile is still in flight. Give each projectile of a volley a distinct `pulse_id`. Set `hit.attacker_position` to the **projectile position** at impact. `block_covers` and knockback direction both use it (damage_resolver.gd 75, combat_entity.gd 177), so the shooter's position would give wrong block arcs. Decide whether a dead archer's arrows still land: Sim currently drops them (sim.gd 189). Add `"projectile"` to `HIT_SHAPES` plus fields `projectile_speed_mps, projectile_radius_m, range_m, gravity`. Add `Events.projectile_spawned/projectile_impact` for presentation. Projectile hits are not `Melee`, so they cannot be parried, but they can be blocked.

**c. AoE pulses (Thunder Roar).** Reuse `HitQueryAdapter.cylinder_pulse` and the Footfall path (giant_player.gd 455-461) with `radius_m: 6`. Damage may be 0 (`power: 0`). The slow and morale effects need hooks: add `ActionDef.on_hit_statuses` (for example `[{"id":"status.slow","magnitude":0.3,"duration_s":3}]`), applied in `CombatEntity._apply` when the outcome is HIT or BLOCKED. For morale, add `Events.morale_impulse(tick, source_id, center, radius, amount)` or a duck-typed `actor.on_morale_delta(amount)`. Morale lives in `SoldierBrain.morale` (soldier_brain.gd 37, change it like `on_ally_died` at line 109). Note: a 0-power HIT still emits `hit_resolved` and marks combat.

**d. Status effects (new `scripts/combat/status_set.gd` + `data/statuses/*.json`).** Make `Combatant.statuses: StatusSet` with `apply(def, magnitude, duration_ticks, source_id, now) -> bool`, `tick(now)`, `has(id)`, `modifier(stat) -> float`, and `clear()`. Policies, set per status in data:
- `refresh_no_stack` (Stone Skin): re-apply resets the duration and keeps the magnitude.
- `strongest_wins` (slow): keep the max magnitude and refresh the duration.
- `hot` (Ancestral Mend): 100 HP over 4 s = 8 ticks at 0.5 s (30-tick period), 12.5 per tick, via `pools.heal` (caps at max). Skip ticks once dead.

Status immunity: a status record lists `tags` (for example `"Slow"`, `"Fear"`), checked against `Combatant.immunities`. You must add those names to the validator's immunity list. Ticking: add a central `Sim` pass that walks `entities()` in id order and ticks statuses. Don't rely on actor `sim_step`, which the dummy and props don't share. Emit `Events.status_applied/status_expired(tick, entity_id, status_id, source_id)`.
- Stone Skin (+30 armor 6 s): change DamageResolver line 39 to `defender.armor_total()`, defined as `armor + statuses.modifier("armor")`. Never mutate `Combatant.armor`.
- Slow: multiply in the actors' movement (`speed = walk * controller.move_speed_multiplier()`, giant_player.gd 386, soldier_enemy.gd 217) by `combatant.statuses.move_mult()`. Or fold it into `CombatController.move_speed_multiplier()`, but some tests assert that value directly, so check them first.

**e. Titan Surge (+25% damage and poise for 6 s, 100 fury, no fury gain while active).** Make it `kind:"ultimate"`, `fury_cost:100`, `hit_shape:"none"`, with a self status `status.titan_surge` (`refresh_no_stack`). It must be in `loadout["ultimate"]` (giant.json `loadout.ultimate`, currently "", which yields "empty_slot"). When building a HitEvent, set `e.outgoing_damage_mult`/`e.outgoing_poise_mult` from the attacker's statuses. These fields already feed `mitigate` (line 19) and the poise formula (line 105). For projectiles, snapshot the values at spawn. To block fury gain, gate `ResourcePool.add_fury` with a flag (for example `fury_gain_blocked`) set by the status. The three call sites are combat_entity.gd 144, 199 and 203. Gating inside `add_fury` covers all of them.

**f. Crits (5%, seeded) and weak points (×1.25).** Both are already implemented. Crit is `crit_eligible and Sim.rng.randf() < crit_chance`, and the player's `crit_chance` is 0.05 in giant.json. Weak points use `Hurtbox.weak_point` (an export set in `tools/build_scenes.gd`). Gaps: the soldier path never copies `cand.weak_point` or `attacker_growth_stage` (soldier_enemy.gd 308-332). For bosses and ogres, author weak-point hurtboxes in `build_scenes.gd`.

**g. Magic damage and elemental resistance.** Already in `mitigate`: non-physical portions use `resistance(t)` (record `resistances` + Willpower), and armor is ignored for them. Mixed damage uses `damage_split`, whose portions must sum to 1. Block reduces elemental damage by 50%. Only new data is needed.

**h. Grabbed/Executing (Crushing Grip, throw).** The states exist. `_evaluate` returns RETRY "busy" in them, and `is_committed()` includes them. Add `enter_grabbed(holder_id)` / `release_grabbed(reason)` on the target controller, and `begin_execute(def, target_id)` / `end_execute()` for the holder, which runs an action timeline in EXECUTING (extend the `begin_tick` match at line 193 and `_finish_action` line 414 to include EXECUTING). `apply_stagger` (469) currently would yank a GRABBED target into STAGGERED. Add a guard so that only explicit escape rules leave GRABBED. `kill()` must release the hold on both sides. Eligibility check (spec 8): `poise.locked` (a staggered target means broken poise), the `"Grab"` tag in immunities via `is_immune_to("Grab")`, height ≤ 50% of the holder, reach, and LOS (`HitQueryAdapter.line_clear`). Damage for grip and throw goes through ordinary HitEvents (tags `Grab`, `Unavoidable`?). The GiantPlayer `interact` intent is currently a stub (giant_player.gd 191-192).

**i. Enemies on the same ability system.** Enemies already use `CombatController` + `request(&"attack", {"action_id"})`. To cast, enemies need essence: `Combatant.from_record` without a `resources` dict sets **essence 0** (combatant.gd 56-57), so give archer and mage records `resources`/`regen`. Move hit production out of `SoldierEnemy._run_hit_queries` (it only handles `weapon_arc`, line 288) into a shared component (see §5). Use `kind:"enemy_attack"` for melee and `"ability"` for spells (→ CASTING). Mage "telegraphs" can read `controller.phase()`.

**j. Unlocks and loadout.** `unlock_stage` is compared to `controller.growth_stage` (reason "locked"). `growth_stage` is set once, in `GiantPlayer._build_controller` (line 90), so on growth you must update `controller.growth_stage`, the `Combatant.height_m`, the profile geometry, and emit `Events.growth_changed`. The validator already accepts growth-profile `unlocks: [action ids]`. Changing the loadout at a shrine means rewriting `controller.loadout["slot_n"]` and calling `_add_action_chain(id)` for each new id, because `library` only holds what was loaded at build. Boulder Hurl's "stage 2, level 3" gate needs a level check too; add `unlock_level` or rely on stage 2 being reachable only at level 3. Persist the loadout through `WorldState`/`SaveIO`.

## 5. Hotspots and conflict-avoidance proposal

Hotspots, roughly in the order of how many packages will touch them:
1. **HitEvent construction is duplicated** in `GiantPlayer._queue_hits` (464-505) and `SoldierEnemy._run_hit_queries` (286-332), and every enemy archetype, projectile, throw and buff would copy it again. **Proposal:** before parallel work starts, one owner lands `scripts/combat/hit_factory.gd` with `HitFactory.build(attacker: CombatEntity, a: ActionDef, cand: Dictionary, instance_id, pulse_id, tick, weapon: Dictionary, growth_stage) -> HitEvent` (stat choice, crit roll, status multipliers, weak point), plus `HitFactory.queue_candidates(...)` (sort + registry + queue). Also a shared `ActionRunner` helper for `_run_hit_queries` that dispatches on `hit_shape` (weapon_arc / cylinder_pulse / projectile / none-with-effects).
2. **`CombatEntity._apply`** (136-189): statuses on hit, fury gating, grab and morale all land here. Add one hook, `_apply_on_hit_effects(result, attacker)`, and keep features inside it.
3. **`CombatController._accept` / `_evaluate` / `begin_tick`**: CASTING effects, EXECUTING and GRABBED all need edits. Land the state-machine extensions (phase signal, grab/execute API, stagger guard) as one small PR first.
4. **`DataValidator.schema_for("action")` and the enum consts**: every feature adds keys. Land all new schema keys at once from the plan (effects, statuses, projectile fields, unlock_level) before parallel work, or have each package append in its own clearly separated block.
5. **`Sim.step`**: add a fixed, ordered hook list now (`actors → projectiles → statuses → resolve_hits`) so packages register instead of editing `step()`.
6. **`Events`**: append-only. Reserve signal names up front: `status_applied, status_expired, projectile_spawned, projectile_impact, healed, morale_impulse, grab_started, grab_ended`.
7. `data/player/giant.json` loadout, `tools/build_scenes.gd`, `ui/hud.gd`: one owner each, or append-only sections.

## 6. Pitfalls and gotchas

- `ActionDef.damage_split` and `arc` are **shared Dictionary references**. `e.damage_split = a.damage_split` hands the same dict to every HitEvent, so never mutate it on an event.
- `controller.hit_registry.forget(instance)` runs on every finish and interrupt, so anything that outlives the action timeline (projectiles, damage-over-time, a delayed pulse) needs its own dedup.
- `Sim._resolve_hits` drops hits whose attacker died earlier in the pass. That also covers in-flight projectiles from dead shooters, unless you change it.
- Block arc and knockback use `hit.attacker_position`. Set it to the impact source for projectiles and throws.
- Parry requires the `Melee` tag. A ranged hit tagged `Parryable` is still unparryable.
- `is_invulnerable()` is true only in DODGING, so a grab or execute "invulnerability" needs explicit code (`DefenseState.invulnerable`).
- Crit rolls consume `Sim.rng` at queue time. Any new `Sim.rng` consumer (AI, loot, status procs) shifts every later crit roll. Worked-example tests (37/66/44) rely on the default seed not producing a crit at that point. Give new systems their own seeded RNGs, as `SoldierBrain` does with `DEFAULT_SEED ^ hash(id)`.
- The validator treats unknown keys as errors, and the enum lists are closed. A new tag (`"Slow"`), damage type, hit shape or immunity name fails at startup until it is added.
- Abilities are attack kinds, so they must carry `power`, `poise_damage`, `tags`, `hit_shape`, `max_hits_per_target` and `active_s > 0`, even pure self-buffs. Use `power: 0`, `hit_shape: "none"`, and an active tick of at least 1.
- `recovery_scale` (Dexterity) applies to `kind` ability and ultimate too (`is_attack()`).
- A 0-windup action is already ACTIVE on its accept tick (the request comes after `begin_tick`). `is_first_active_tick()` is true then, so effects fire the same tick.
- A cancel into a new action calls `_finish_action(false, true)` and emits `action_ended(interrupted=false)`. Listeners can't tell a cancel from natural completion.
- `apply_stagger` with `super_armor` resets poise and returns false, so `CombatEntity.stagger` emits nothing.
- Weak point and dedup: the first candidate per entity wins, and candidates are sorted by substep, then hurtbox-center distance. A weak-point hurtbox behind a closer body hurtbox is skipped in the same substep. For bosses, prefer the weak hurtbox when one entity has several overlaps in the same substep.
- Enemies have essence 0 unless their record has `resources`. The soldier's `pools.tick(dt, not is_guarding())` lets stamina regen while it attacks. That is fine for melee, but revisit it for casters.
- `ability_started` is emitted by actors, not the controller. A new actor type must connect `controller.action_started` and re-emit it, or AI hearing (`SoldierEnemy._on_any_ability_started`) and the HUD miss it.
- `Combatant.immunities` mixes damage types and tags in one list. A status immunity added to it also makes the entity immune to any *hit* carrying a tag of that name (`mitigate`, line 44). Use distinct names (for example `"status:slow"`) or a separate `status_immunities` list.
- `growth_stage` lives in two places: `GiantPlayer.growth_stage` and `controller.growth_stage`. The HitEvent's `attacker_growth_stage` (used by `BreakableProp.accepts_hit`) is taken from the actor's copy.
- Scenes are generated: hurtboxes, weak points and `CombatEntity` children are authored in `tools/build_scenes.gd`. Never hand-edit `.tscn`.
- `Events.growth_changed` is declared but nothing emits it yet. Listeners written now won't fire until M3 code does.

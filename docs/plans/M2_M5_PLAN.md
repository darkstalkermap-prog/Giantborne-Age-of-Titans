# Giantborn M2–M5 plan: the Valley of Broken Kings

| Item | Value |
| --- | --- |
| Base | `main` @ `e89001f` (M0 + M1 merged; 15 suites, 1133 checks, about 7 s) |
| Engine | Godot 4.6.3-stable, GDScript, Compatibility renderer, Jolt, fixed 60 Hz `Sim` |
| Targets | Windows desktop and the single-threaded Web export (play link) |
| Inputs | Spec `docs/GIANTBORN_SPEC_V2.md` §4–16, the five briefs in `docs/plans/briefs/`, `DECISIONS.md`, `M1_HANDOFF.md`, the M1 code |
| Output | 21 packages in 12 waves (at most 2 agents at once), ending with a merged, playable 20–30 minute Valley, measured by a headless Valley bot with a novice and an expert skill profile |
| Revision | v2. Three reviews (spec coverage, feasibility, gameplay) were folded in. §7 lists every finding, what changed, and the few that were rejected or changed in form. |

Engine behaviour this plan depends on, checked on 4.6.3 before writing it:
- An enum declared in a base class resolves through the subclass name (`SoldierBrain.AIState.RECOVER` still works after the enum moves to `EnemyBrain`).
- `const X := {"a": SomeClass}` is **not** a constant expression. Registries must use `preload("res://…")` values (verified) or a static function.
- `load(path).build_all(kit)` calls a static function on a loaded script, and `ResourceLoader.exists(path)` reports whether an optional script exists. Both were verified, and they make the "pre-declared optional registries" in §1.5 possible.
- `NavigationServer3D.bake_from_source_geometry_data()` with procedural faces (`add_faces`) bakes 400 × 400 m with 600 box obstacles in 0.2–0.8 s offline. The result saved with `FLAG_COMPRESS` is 48–82 KB per layer (human: radius 0.6, cell 0.3; large and giant: radius 1.5–2.0, cell 0.5). Navmeshes with cell sizes 0.3 and 0.5 on the default 0.25 map bake and path without errors. Runtime baking is therefore unnecessary, and the `.pck` stays small.
- `XDG_DATA_HOME=<dir>` moves `user://` to `<dir>/godot/app_userdata/Giantborn` on Linux (verified). Two worktrees running tests at once can therefore keep separate save folders.
- Every node in a generated `.tscn` carries a random `unique_id=` attribute, so each regeneration rewrites every node line. A scene with those attributes stripped still loads (verified), so `SceneKit.save` strips them and regenerated scenes diff deterministically.
- `RenderingServer.viewport_set_measure_render_time`, `viewport_get_measured_render_time_gpu` / `_cpu`, `NavigationServer3D.region_get_closest_point` and `map_get_path(map, from, to, optimize, navigation_layers)` exist. `map_get_closest_point` has **no** layer filter, so code that needs a point on one layer uses the region call or validates with a layered path.
- Headless speed: the M1 sandbox autopilot simulates 120 s in about 5 s of wall time (about 23× real time). The Valley, with up to 12 enemies, is expected to run at 5–10×, so a 20-minute bot run takes about 2–4 minutes of wall time.

---

## 0. Scope, interpretation and the deferred list

### 0.1 Goal

The goal is to build spec milestones M2 → M5 on top of the M1 sandbox: combat depth, the scale proof, the playable Valley of Broken Kings, then test and tune. The result is merged to `main`, and a measured "how it plays" report is written. Graphics stay primitive low-poly boxes with flat colours, and audio stays silent (the owner accepted this). Because there is no audio and no real animation, readability is carried by telegraph decals, aim lines and screen-edge threat arrows (decision 25). The M1 sandbox stays playable and keeps its tests.

### 0.2 Milestone gates (spec §15) and the packages that prove them

| Gate | Requirement | Proven by |
| --- | --- | --- |
| M2 | Targeting, three-hit combo, four abilities, two enemy roles | P03 (Footfall + Sweeping Blow, Stone Skin, Runic Bolt, plus Mend, Roar and Titan Surge; hotbar target line; hostile-only targeting), P02/P04 (soldier + wolf; pack target-switching tests), existing combo and lock tests |
| M3 | Three profiles, safe growth, grab/throw, persistent gate | P05 (growth 1–3, shrines, clearance, 3 sizes × 2 cameras route, per-stage lock range), P07 (grab with attachment profiles, throw, Crushing Grip, Boulder Hurl), P08 + P06 (structural practice gate keeps its damage stage and health through save/load) |
| M4 | Complete loop, five roles, eight abilities, boss, save/load | P15 (quest line content, walkthrough tests for all four village outcomes), P04/P09/P11a (soldier, wolf, archer, mage, ogre and boss), P03 + P07 (eight abilities), P11a (boss), P06 + P08 (save/load), P17a (the assisted bot completes the loop) |
| M5 | Usability, performance, controller and stability gates pass | P16 (usability script, pad navigation), P14 (stress route, CPU and GPU capture, low preset), P17a (Valley bot, 30-minute run), P17b (tuning, report), P18 (exports, web build, merge) |
| §15 combat correctness | Worked example 37/9/66, stamina ≥ 0, dedup, walls, 100 activations, boundaries, queue expiry, lock release | Existing tests; every package keeps them green. P01 keeps the crit RNG sequence (`Sim.rng`) untouched. |
| §15 camera/growth | Route in 3 sizes × 2 modes, no camera penetration **or obscured crosshair**, no invalid spawn, blocked growth changes nothing, downward first-person attacks | P05 (route with a screen-centre ray check each tick; wolves and soldiers at the feet), P07 (first person while holding), P08 (first person with the sword, hammer and tree) |
| §15 ability/AI/world | Invalid grabs spend nothing; interrupted grabs release both; cooldowns; target death during casting; reachable flee destinations; boss phases exactly once; save/load restores character, loadout, flags and gate; loot never twice; corrupt save → backup with a message | P07, P03, P09, P04 + P11b + P15 (Valley flee reachability), P11a, P08 + P06, P08/P12, P06 |
| §16 performance | 12 combatants, 20 breakables, 40 debris; p95 ≤ 16.7 ms, p99 < 33.3 ms at 1080p low on a reference PC | P14 (route, capture tools, `--graphics=low` preset; CPU per tick in the container). Real-PC numbers are **NOT RUN** until the owner runs them. |
| §16 usability / 30-minute session | 3 new players; 30 minutes with no crash, softlock, duplicated reward or stuck targeting | P16 (script; humans **NOT RUN**), P17a (assisted bot 30-minute run with invariants) |

### 0.3 Interpretations and decisions (P18 copies these into `DECISIONS.md`)

1. **One Valley scene, district sub-scenes.** `scenes/world/valley.tscn` instances one sub-scene per district (`scenes/world/valley/<district>.tscn`). Geometry comes from one layout table, `tools/data/valley_layout.json`, which lives in tools and is not shipped. Navigation is pre-baked offline into four layers (human, large, giant, small giant). Nothing re-bakes at runtime in the Valley. A breakable that blocks a path carries a `NavigationLink3D` that is enabled when it breaks. Open-world streaming stays deferred.
2. **Enemies spawn from data.** An `EncounterDirector` spawns encounter members from `encounter` records, using stable entity ids taken from the data. Kills are persisted as world deltas (`killed`). Living members of a far-away encounter that is not engaged are despawned and later respawn at full health; a cleared encounter never respawns. The director enforces an active-combatant budget of 12, three AI LOD tiers (tier 2 swaps the rig for a one-box proxy), and a per-encounter leash.
3. **Weapons fit up to a stage; the Giantforge refits them** (spec §9). Each growth profile carries `weapon_scale` (1.0 / 1.5 / 2.1667 = height ratio). A weapon follows the giant's growth only up to its `fit_max_stage`; above it the weapon keeps the scale of that stage and the HUD says it is too small. Ordinary gear (club, sword, hammer) fits stage 2. Reforging at a forge (the one upgrade interaction) gives the reinforced variant, which fits stage 3 and hits harder. The tree weapon has a fixed real size and is stage-3 only. The whole rig scales uniformly by `k = height / 3.6576`, so the visible swing still equals the tested swing.
4. **Growth adds body.** `resource_bonus` gives stage 2 +150 health and +10 stamina, and stage 3 +300 health and +20 stamina. Health, stamina and essence percentages are preserved through growth and debug shrink. Nothing heals by switching profiles.
5. **Big giants still hit humans and wolves.** Profile `arc_pitch_offset_deg` (0 / −6 / −12) tilts the player's weapon arcs downward at larger stages, in both the sweep and the rig. Without it, the stage-3 light 2 bottoms out at about 2.0 m and misses a 1.8 m soldier. P05 tests every light and heavy against a 1.8 m soldier **and** a 0.9 m wolf at stages 2 and 3 and may deepen the offsets (up to −10 / −18) until both pass.
6. **Levels gate abilities.** Actions gain `unlock_level`. The controller gets `level`, where 99 means no level gating; that is the default in the sandbox and in tests. Abilities taught by a quest reward before their level go into `controller.level_exempt`. Newly unlocked abilities auto-slot into the first empty slot, and the loadout can be changed at shrines.
7. **XP is accelerated and labelled.** HUD and docs show the text "Prototype pacing: accelerated quest XP". The XP budget in §4.7 guarantees level 3 before the Grove Shrine, level 4 by the practice gate, and level 5 before the stage-3 growth.
8. **In-flight projectiles still land after the shooter dies.** The existing same-pass rule stays: hits from an attacker killed earlier in the same resolution pass are dropped. A projectile's hit carries `from_projectile = true`, and `Sim` drops it only if its owner died on the current tick.
9. **Statuses are ticked centrally** by a `Sim` pass after hit resolution. Status immunity uses a separate `status_immunities` list of status tags, which keeps it apart from the damage-type/attack-tag `immunities`. Stone Skin changes `armor_total()` and never `armor`.
10. **Thunder Roar** is `Unblockable`, deals 0 damage, applies the 30% slow and 20 morale damage on HIT, and dodge invulnerability evades it.
11. **Village outcomes have lasting, different effects.** `help_cache` and `help_ogre` give 120 XP, 2 iron and Ancestral Mend early, and open the village forge. `intimidate` (dialogue choice, stage ≥ 2) gives 40 XP and Thunder Roar early, but no iron, and the forge stays shut. `force` is set **only** by smashing the cart barricade (stage ≥ 2); it gives kill XP only and makes the guards ambush the return leg. Attacking villagers or guards sets hostility but never the outcome. Every outcome opens the bridge, so none can softlock. Rewards are granted only through once-flags. The end screen names the outcome.
12. **Kingsfall growth requires the boss's defeat** (`growth_requires_flags`), so stage 3 always comes after the boss fight, as in spec §14.
13. **Checkpoints are frequent and never lose a boss kill.** A checkpoint is taken when a shrine is first activated (which also heals, a free Rest), on Rest, when the shrine screen opens, when the player reaches a waystone, after a successful growth, after the boss is defeated, and after every `quest.main` stage. The player respawns at the last shrine or waystone reached. A checkpoint waits while the player is dead, grabbed, executing, holding something or in another modal screen, or while any enemy within 40 m is aware of the player. Death reloads the last checkpoint with its world snapshot and resources, but restores at least 60% health and full stamina; there is no inventory loss. Checkpoints are written only in the Valley (or a test level); the sandbox shrine heals but never saves.
14. **One save slot** at `user://saves/valley_1.json` (IndexedDB on the web), versioned, with backup recovery, built on `SaveIO`.
15. **Modes.** A title screen offers New Valley / Continue / Sandbox / Settings / Quit. `--autoplay` and `--scenario` without `--mode` still boot the sandbox, so M1 tools keep working.
16. **Grab design.** E grabs a staggered target in reach. Grab reach is melee reach + 0.5 m (4.0 / 5.3 / 7.0), and the grab lunges up to 2.0 / 2.7 / 3.5 m during its windup. A target is grabbable only if it passes all six spec §8 rules, including a supported attachment profile (`grab_attach`: `torso_fist`, `scruff` or `two_hand`). A poise break against an attacker at least twice the defender's height staggers for 1.5 s instead of 1.0 s, so E lands reliably after a heavy. While holding, light or heavy throws the target (a swept trajectory with ordinary hits) and E drops it. Crushing Grip crushes only `small` targets, then releases. Boulder Hurl rips a rock from the ground (no prop needed); its category is `projectile`. From stage 3 a staggered ogre (`medium`, `two_hand`) can be grabbed and thrown. The boss is immune (`Grab` in its immunities).
17. **Factions and hostile-only targeting.** Hard lock, soft targeting and the player's area effects (Footfall, Sweep, Roar, splash) only consider entities the player may target: team ENEMY, or team NEUTRAL with no faction (dummies, props). Village guards and villagers spawn NEUTRAL with faction `village`, so they are skipped. A direct weapon or projectile hit on a village member is an offence: the first warns ("Thornwick's people cower. Strike again and they will fight you."), a second within 30 s sets `faction.village.hostile`, which turns guards ENEMY (now lockable) and makes civilians flee. Intimidation sets `faction.village.stood_down`, and guards walk to their formation markers.
18. **The fortified Citadel Gate** is a `structural` prop with `min_growth_stage 4` and a locked message. It is visible and permanently locked in the slice.
19. **The tree obstacle** (Deadfall) accepts only hits that carry the `TreeWeapon` tag. Every attack made with the tree weapon carries it.
20. **Talents and ancestry.** Talent points accrue (1 per level) and are shown, but no talent trees exist. There is one neutral ancestry; the character save stores its id and the Attributes screen shows it ("Ancestry: Unaligned — no modifiers in the prototype").
21. **Physics layer 6 "blockers"** (value 32) holds invisible movement walls (river banks). Every actor builder uses `SceneKit.ACTOR_MASK`, which includes it (P04). The camera, attack occluders, LOS and hurtboxes ignore it, and the navmesh treats it as an obstacle.
22. **Debug keys** (debug builds only): F6/F7 debug grow/shrink (separate from progression, and logged), F8 +100 XP, F9 reload checkpoint. F5 stays sandbox reset. Release exports have none of them.
23. **Selective destruction uses all three spec categories.** Cosmetic props (bushes, banners, barley) wobble or flatten on nearby pulses and footsteps and are never saved. Breakables have health and an intact/broken state. Structural objects have authored damage stages: the practice gate goes intact → cracked → broken, and only the last removes collision and enables its nav link. Every persistent prop saves its damage stage and health, so a cracked gate reloads cracked.
24. **Enemies commit their aim.** Melee and ranged enemies track the target only during the first `tracking_fraction` of their windup (0.6 for archers and mages). Projectiles fire at the point stored at that moment, and the aim line shows that point, so a sidestep after the lock dodges an arrow.
25. **Readable threats without audio or animation.** Every enemy attack with a windup of 0.8 s or more has a telegraph decal that fills from 0 to 100% over the windup and flashes when the strike is active. Archers and mages draw an aim line. A screen-edge arrow shows any telegraph aimed at the player from off-screen. At most two ranged enemies may be launching at the player at once (a ranged token pool), with at least 1.0 s between launches.
26. **Size changes enemy tactics and morale.** Outmatched soldiers hold formation at authored markers or, without one, in an ad-hoc line, and brace-counter a giant that steps into their spears. A unit that first sees a giant at least 4× its height loses 35 morale (awe). Fleeing units regroup above 45 morale only if a leader remains (a living commander of the encounter, or a non-fleeing ally within 20 m); without one they rout and stay out of the fight. Bosses ignore morale.
27. **The Ogre King is a real boss.** It is 8.5 m tall (the stage-2 player is 5.49 m; the stage-3 player 7.92 m). Phase 1 strictly alternates the two-hit combo and the slam. A 1.5 s roar marks phase 2, which adds a charge that runs until it hits the arena wall or one of four pillars, followed by a 2.5 s punishable recovery. The slam and the charge are unblockable; the combo can be blocked and parried.
28. **The tutorial encounter is in the Valley.** The Sandbox has no tutorial director. The spec §16 "tutorial encounter" is Giant's Hollow (dummies and a sparring post that teaches block, parry and dodge) plus the first wolf pack. The Sandbox also gets a sparring post.
29. **The navigation profile changes with growth.** Stage 1 uses the small-giant nav layer (8), which includes the 4 m village alleys; stages 2 and 3 use the giant layer (4). The bot and clearance checks use the current profile's layers.
30. **Balance is judged on a novice bot.** The Valley bot has a novice profile (reacts only to visible threats, with 250 ms latency and imperfect blocks and dodges) and an expert profile (reads controller phases). Balance targets use the novice; the expert is reported as the skill ceiling. Stability and softlock checks use an assisted bot (damage taken × 0.25) so they never depend on combat skill.

### 0.4 Deferred: the full-game vision, explicitly not built

- Growth stages 4–10 as playable profiles. Stage 4 is shown only as the locked Citadel Gate. Levels 7–20 exist in the XP table, but no content needs them.
- Dragons and flight AI; rival giants, trolls, titans and siege crews.
- Siege equipment and the siege-destruction morale event (−20). The morale hook exists (`on_morale_event("siege_destroyed")`, unit-tested), but nothing in the slice raises it.
- Open-world streaming, a 1 km² map or a continent, and the large-scale traversal spike for stages 7–10.
- The 24-ability library, ability upgrades, the three full talent trees (Destroyer, Guardian, Primordial), extra ancestries and the Worldbreaker ultimate.
- Formations as selectable lock groups (stages 4–6), siege disruption, large-monster grapple windows, limb poise (large monsters have several lock anchors that share one health pool, but no per-limb poise), titan executions and boss grapples.
- Building collapse, fortified-gate breach, structural damage beyond the authored practice-gate stages, and procedural terrain destruction.
- A crafting economy beyond the single forge upgrade, gear beyond club/sword/hammer/tree, inventory weight, inventory loss, and refitting beyond stage 3.
- Dispel, damage over time, elemental combinations and complex buff stacking (only the three spec stacking policies are built).
- Multiplayer, hundreds of NPCs or a simulated city, cinematic dialogue or voice, localization, multiple save slots, cloud saves, fast travel and a map screen.
- Production art, animation and audio; physics interpolation; the Unreal migration spike.
- Real-hardware, real-gamepad and human-playtest evidence. These cannot run in this environment: P14, P16 and P17a/b supply the scripts, and the owner runs them.

---

## 1. Execution model and wave schedule

### 1.1 Definition of done for every package

Each package is implemented by **one agent in one session**, within about 1,500–3,500 new lines including tests (moved code counts). Before committing, the package must:

1. **Run Godot with its own user folder.** Every Godot command goes through `tools/gd.sh` (P02), which sets `XDG_DATA_HOME=<worktree>/.userdata` and then runs `godot`. In wave 0, before `tools/gd.sh` exists, P01 prefixes each command with `XDG_DATA_HOME="$PWD/.userdata"`.
2. **Import, build, import, then test**, in this order:
   1. `tools/gd.sh --headless --path . --import`
   2. `tools/gd.sh --headless --path . res://tools/build_scenes.tscn -- --only=<builder>[,<builder>]` when the package changed a builder or code that a generated scene embeds (`--only` exists from P04; before P04, run the full builder)
   3. `tools/gd.sh --headless --path . --import` again, so new `class_name`s and resources are registered (the class cache under `.godot/` is not in git)
   4. `tools/gd.sh --headless --path . --fixed-fps 60 res://tests/run_tests.tscn -- --no-user-settings`, plus `-- --no-user-settings --slow` when the package added or changed slow suites

   `tools/check.sh [--slow] [--only=<builders>]` (P02) runs the same sequence and step 3 below.
3. **Leave no runtime errors.** Shipped data must validate (`GameData.errors` empty). `tools/gd.sh --headless --path . --fixed-fps 60 -- --no-user-settings --autoplay=120` must exit with code 0, and its `AUTOPILOT_RESULT` line must show `"errors":0`. The error counter and the non-zero exit come from P02. In wave 0 P01 instead checks that the output contains no `ERROR` or `SCRIPT ERROR` line.
4. **Never hand-edit scenes.** Regenerated `.tscn` files are committed. From P04 on, `SceneKit.save` strips the random `unique_id=` attributes, so only scenes whose content changed show a diff.
5. Write `docs/systems/<package-id>.md`: what was built, public APIs, data added, decisions taken, known gaps, and the runtime it added to the default and slow suites. P18 consolidates these files into `ARCHITECTURE.md` and `DECISIONS.md`. **No package except P18 edits `README.md`, `ARCHITECTURE.md` or `DECISIONS.md`.**
6. Commit on its package branch with a message that names the package id.

### 1.2 Branches, worktrees and the wave merge

- Integration branch: `claude/hopeful-gauss-0f323t` (the session's designated branch, restarted from `main` @ `e89001f`). Package branches `pkg/<id>` stay local and are never pushed; only the integration branch is pushed.
- Each package works on branch `pkg/<id>` in its own git worktree, branched from the integration tip at the start of its wave. Each worktree has its own `.godot/` import cache and its own `.userdata/` folder; `.userdata/` is git-ignored (P02 adds the line; P01 must not commit the folder).
- **Cross-lane API rule.** A package may use the APIs that exist on the integration tip at the start of its wave, plus its own. It never calls a symbol that its wave partner is adding. Where a forward reference cannot be avoided, the package spec lists it under "Cross-lane symbols" and the code reaches it defensively (`has_method`, `has_signal`, `"name" in object`), so the branch parses and passes on its own.
- **Wave merge** (done by the orchestrator, or by the package that finishes second):
  1. Merge the first package; then import → full builder → import → full suite.
  2. Merge the second package. Source conflicts can only occur in the hotspot files listed in its spec, and all of those edits are additive at named anchors (§1.5). A conflict in a generated `.tscn` or `.res` file is resolved by taking either side and regenerating.
  3. Import → full builder (`res://tools/build_scenes.tscn`, no `--only`) → import, so every generated scene reflects the merged code.
  4. Run the full suite plus `--slow` and the 120 s autoplay (0 errors). Commit "Merge wave N" and tag `wave-N`.
  5. If a merge breaks tests, fix forward on the integration branch only when the fix is small (under ~50 lines). Otherwise revert that package's merge and re-run the package.
- P18 opens the pull request from `claude/hopeful-gauss-0f323t` to `main` and merges it once all gates are reported.

### 1.3 Wave schedule (at most 2 agents at once)

| Wave | Lane A | Lane B | Leaves working |
| --- | --- | --- | --- |
| W0 | **P01** Core seams (validator registry, events, Sim phases, combat API, statuses, flags) | **P02** Actor seams (player components, enemy base, HitFactory/AttackRunner, interactables, HUD registry, test support, error counter, `tools/gd.sh`) | The same sandbox gameplay; all old checks pass; new seams are unit-tested. |
| W1 | **P03** M2 player abilities + projectiles + hostile-only targeting + UI screen stack | **P04** Scene kit split + wolf + morale and size tactics + actor masks | **M2 gate.** Sandbox has 7 working abilities plus Titan Surge, wolves in the NW corner, and pause as a `UiScreen`. |
| W2 | **P05** Growth 1–3 + shrines + growth course | **P06** GameSession, saves, checkpoints, waystones, title, death flow | Sandbox shrine grows stages 1–3 safely. Title, Continue and checkpoint/death reload work on a test level. |
| W3 | **P07** Grab, throw, Crushing Grip, Boulder Hurl | **P08** Props (cosmetic, breakable, structural), weapons with fit stages, nav links, pickups, persistence | **M3 gate.** All 8 abilities; club/sword/hammer/tree; the practice gate keeps its damage stage through save/load. |
| W4 | **P09** Archer + mage + telegraph visuals + threat arrows | **P10a** Level framework: LevelRoot, triggers, markers, EncounterDirector (budget, LOD, leash) | Ranged enemies; a director test level spawns, leashes and persists encounters. |
| W5 | **P10b** Valley world: layout, offline nav bake, Valley scene | **P12** Progression, attributes, loadout, inventory, loot, forge | The Valley can be walked from New Game; XP, levels, attributes, inventory and the upgrade. |
| W6 | **P11a** Ogre, Ogre King boss, arena | **P13** Quests, dialogue, NPC talker, tutorial director, end screen | Boss fight in Kingsfall; quest and dialogue systems on test data. |
| W7 | **P11b** Civilians, factions, guards, awe and brace tactics, sparring post | **P14** Stress route, performance capture, graphics presets | The village's people and guards behave; stress numbers. |
| W8 | **P15** Valley content: encounters, quest line, dialogue, tutorials, layout dressing | **P16** UX, controller and usability pass | **M4 gate.** The full 20–30 minute loop; pad-navigable menus; usability script. |
| W9 | **P17a** Valley bot, invariants, metrics, 30-minute stability run | — | **M5 stability gate**; the assisted bot completes all four outcomes. |
| W10 | **P17b** Balance loop and the how-it-plays report | — | **M5 tuning**; balance log and report. |
| W11 | **P18** Ship: final verification, docs, exports, web build, PR, merge | — | Merged to `main`; play link updated. |

**Why this order.** Shared seams (registries, events, components, schemas) land first, so later packages add files and data instead of editing shared functions. The critical path runs foundation → combat and AI → growth and session → grab and world objects → level framework → Valley geometry → boss → content → bot → tuning → ship. The level framework (P10a) is split from the Valley geometry (P10b) so that both fit one session and the director is tested on a small level before the Valley exists. The boss (P11a) is split from the village's people (P11b) for the same reason, and P13 owns the NPC talker so it does not wait for P11b. Content (P15) waits for every system so it can be tested end to end. The bot is split into a build package (P17a) and a tuning package (P17b), because the balance runs alone take one to two hours.

**Owner checkpoints (recommended, never blocking).** After W1 the owner can play the M2 sandbox from the integration branch, and after W8 the Valley. Spec §16 says to fix recurring failures before adding content, so findings become data or tuning changes in the next package that owns the data. No package waits for them.

### 1.4 Dependencies (each package builds and tests on merged earlier waves only)

| Package | Depends on |
| --- | --- |
| P01, P02 | — |
| P03, P04 | P01, P02 |
| P05 | P01–P04 (UiScreen from P03, SceneKit from P04) |
| P06 | P01–P04 |
| P07 | P03 (projectiles, AttackRunner shapes), P04 (EnemyActor, motion), P05 (stage profiles, grab fields) |
| P08 | P03 (HitFactory weapon tags), P04 (SceneKit), P05 (stage gates, body scale), P06 (saves for the persistence test) |
| P09 | P03 (projectiles, statuses), P04 (EnemyBrain tactics, telegraph events), P07 (projectile system as extended) |
| P10a | P04 (EnemyActor LOD and morale), P06 (level loading, checkpoints) |
| P10b | P05 (shrine scene), P06, P08 (prop scenes, nav-link enabling), P10a (LevelRoot, triggers, markers, director) |
| P12 | P05 (shrine tabs), P06 (CharacterState), P08 (weapons, equipment, pickups) |
| P11a | P07 (grab immunity, stage-3 ogre grab test), P10b (Kingsfall geometry) |
| P13 | P06 (flags, session), P10a (areas, markers), P12 (XP listener, items, `learn_ability`) |
| P11b | P10b (village markers), P13 (NpcTalker for the elder) |
| P14 | P08, P09, P10a, P11a |
| P15 | P07–P14, P11a, P11b |
| P16 | P03, P05, P06, P12, P13 |
| P17a | P14, P15 |
| P17b | P16, P17a |
| P18 | P17b |

### 1.5 Hotspot policy: pre-declared registries and anchors

Hotspot files are the ones many packages would otherwise edit. They are handled in three ways.

**1. Pre-declared optional registries.** The foundation packages list **every planned file path** up front. Code loads each entry only if `ResourceLoader.exists(path)`; a missing path is skipped silently, with no `push_error`, because errors fail tests. Later packages create the file and do not edit the list. The lists are:
- `GiantPlayer.COMPONENTS` (P02, §2.7.1)
- `HudWidgets.WIDGETS` (P02, §2.10.1)
- `ResetHooks.BEFORE_EACH` and `AFTER_EACH` (P02, §2.13): per-test resets for later autoloads and screens, so no package edits `tests/integration_suite.gd`
- `ScreenStack.SCREENS` and `ScreenStack.HOTKEYS` (P03, §2.10.2)
- `ShrineScreen.TABS` (P05, §2.10.2)
- `build_scenes.gd BUILDERS` (P04, §2.12)
- `DataValidator.SCHEMAS` (P01, §2.8.1). Every planned record type's schema path is declared by P01, but each schema file is written by the package that first ships records of that type. `RECORD_TYPES` is derived from the entries that exist.

**2. Package anchors.** Files that are still shared get one comment line per later package, written by their creator, such as `## @anchor P07`. A package that must add code to such a file inserts it directly below **its own** anchor. Two packages in one wave then edit different hunks, and git merges them cleanly. The anchors:

| File | Created by | Anchors |
| --- | --- | --- |
| `scripts/core/events.gd` | P01 | one per package (P02–P18) |
| `scripts/core/schemas/action_schema.gd` | P01 | P03, P04, P07, P09, P11a |
| `scripts/core/schemas/enemy_schema.gd` | P01 | P04, P07, P09, P10a, P11a, P11b, P12 |
| `scripts/core/schemas/prop_schema.gd`, `weapon_schema.gd` | P01 | P08, P12 |
| `scripts/core/schemas/growth_profile_schema.gd`, `player_schema.gd` | P01 | P05 |
| `scripts/core/schemas/item_schema.gd` | P01 | P12 |
| `scripts/core/game_data.gd` (post-pass) | P01 | P09, P10a, P12 |
| `scripts/actors/enemy_actor.gd`, `scripts/ai/enemy_brain.gd` | P02 | P04, P07, P09, P10a, P11a, P11b |
| `scripts/actors/attack_runner.gd` | P02 | P03, P07, P09, P11a |
| `scripts/combat/hit_factory.gd`, `attack_context.gd` | P02 | P03, P07 |
| `scripts/actors/player/player_targeting.gd` | P02 | P03, P11a |
| `scripts/presentation/actor_rig.gd` | P03 | P05, P07, P08 |
| `scripts/world/projectile_system.gd` | P03 | P07, P09 |

P02's anchor test (`tests/unit/test_anchors.gd`) reads this table from `tests/support/anchors_expected.gd` and fails if a listed anchor line is missing, so a package never has to invent one.

**3. Single owner per wave.** Every other shared file is edited by at most one package per wave. The ones that change more than once:

| File | W0 | W1 | W2 | W3 | W4 | W5 | W6 | W7 | W8 | W9+ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `scripts/main.gd` | — | P03 | P06 | — | P09 | — | — | — | P16 | — |
| `ui/hud.gd` | P02 | P03 | P06 | — | — | — | P11a | — | P16 | — |
| `project.godot` | P01 | — | P06 | — | — | — | P13 | — | — | P18 |
| `scripts/debug/autopilot.gd` | P02 | — | — | — | — | — | — | P14 | — | P17a |
| `data/player/giant.json` | — | P03 | — | P07 | — | — | — | — | — | — |
| `data/progression/progression_default.json` | P01 | P03 | — | P07 | — | P12 | — | — | P15 | P17b |
| `data/enemies/soldier.json`, `wolf.json` | — | P04 | — | P07 | — | P12 | — | P11b | P15 | P17b |
| `data/enemies/archer.json`, `mage.json` | — | — | — | — | P09 | P12 | — | P11b | P15 | P17b |
| `tools/builders/sandbox.gd` | — | P04 | P05 | P08 | — | — | — | P11b | — | — |
| `scripts/presentation/camera_rig.gd` | — | — | P05 | — | — | — | P11a | — | — | — |
| `scripts/combat/combat_entity.gd` | P01 | — | — | — | — | — | P11a | — | — | — |
| `scripts/actors/giant_player.gd` | P02 | — | P05 | P08 | — | — | — | — | — | — |
| `scripts/actors/player/player_attack.gd` | P02 | P03 | P05 | — | — | — | — | — | — | — |
| `tools/builders/soldier.gd`, `wolf.gd` | — | P04 | — | P07 | — | — | — | — | — | — |
| `scripts/world/level_root.gd`, `encounter_director.gd` | — | — | — | — | P10a | — | — | P14 | — | — |
| `data/world/level_valley.json` | — | — | — | — | — | P10b | — | P14 | — | P17b |
| `tools/data/valley_layout.json`, `tools/builders/valley.gd` | — | — | — | — | — | P10b | P11a | — | P15 | P17b |
| `scripts/core/settings.gd`, `ui/screens/settings_pages.gd` | — | P03 | — | — | — | — | — | P14 | P16 | — |
| `scripts/world/breakable_prop.gd` | — | — | — | P08 | — | P12 | — | — | — | — |

### 1.6 Test budget, slow tests and global state

- The default suite must stay under **45 s**; it takes about 7 s today. Each package reports its added runtime in its system doc.
- Long suites (the 3-size route, Valley load, walkthroughs, stress smoke and bot smoke) go in `tests/slow/` and run only with `--slow` (runner support from P02). The slow total stays under 6 minutes.
- New global state is reset through `ResetHooks` (P02, §2.13), never by editing `tests/integration_suite.gd`: P06 provides `GameSession.reset_for_tests()`, P13 `Quests.reset_for_tests()`, P02 `TestFixtures.restore_all()` and P03 `ScreenStack.close_all_static()`. `WorldState.clear()` already covers deltas, inventory and flags (P01). `Sim.clear_pending()` also clears launch slots (P01). `Sim.reseed()` reseeds every RNG stream (P01).
- New helpers go in `tests/support/*.gd` (static functions), not in `integration_suite.gd`.

---

## 2. Shared contracts

All units are SI (m, s, m/s, degrees in data, radians in code). All data records carry `schema_version: 1` and a stable dotted `id`. Signatures are GDScript 4.

### 2.1 Folders and ownership conventions

| Folder | New contents |
| --- | --- |
| `scripts/core/schemas/` | One schema module per record type (registry and existing types: P01; new types: the package that first ships them) |
| `scripts/combat/` | `status_def.gd`, `status_set.gd` (P01); `hit_factory.gd`, `attack_context.gd` (P02); `projectile.gd` (P03) |
| `scripts/actors/player/` | `PlayerComponent` and the 8 player components |
| `scripts/actors/` | `enemy_actor.gd`, `attack_runner.gd` (P02); `<archetype>_enemy.gd`; `civilian.gd`, `sparring_post.gd` (P11b) |
| `scripts/ai/` | `enemy_brain.gd` (P02); `<archetype>_brain.gd` |
| `scripts/world/` | Interactables, shrines, waystones, props, level root, director, triggers, markers, projectile system, boss arena, forge, faction state, NPC talker |
| `scripts/progression/` | `character_state.gd` (P06), `progression.gd`, `loot.gd` (P12) |
| `scripts/quests/` | `quests.gd` autoload, conditions, dialogue, tutorial (P13) |
| `scripts/debug/` | Autopilot dispatcher plus one file per scenario, error counter (P02), perf probe (P14), Valley bot and metrics (P17a) |
| `ui/hud/` | HUD widgets (one file each) |
| `ui/screens/` | Modal screens (one file each); `ui/screens/shrine/` for shrine tabs |
| `tools/` | `gd.sh` and `check.sh` (P02); `scene_kit.gd` (P04); `builders/` (one builder per area); `data/valley_layout.json` (P10b) |
| `data/` | At most two levels deep: the export filter is `data/*.json, data/*/*.json`. New folders: `statuses/`, `loot/`, `npcs/`, `dialogue/`, `quests/`, `shrines/`, `progression/`, `world/` (level and encounters), `tutorial/` |
| `docs/systems/` | One doc per package |

### 2.2 Physics layers, render layers, nav layers and groups

| Physics layer (value) | Name | Collides / used by |
| --- | --- | --- |
| 1 (1) | world | Unchanged: terrain, walls, houses, cliffs, arena pillars. Occludes attacks, camera and LOS. |
| 2 (2) | actors | Unchanged: player, enemies, NPCs, dummies |
| 3 (4) | hurtboxes | Unchanged |
| 4 (8) | debris | Unchanged |
| 5 (16) | breakables | Unchanged. Enemy sight now also uses it (P04), so gates and barricades block sight. |
| 6 (32) | blockers | **New.** P01 names it in `project.godot`. Invisible movement walls. P04 adds `SceneKit.L_BLOCKER = 32` and `SceneKit.ACTOR_MASK = L_WORLD \| L_ACTORS \| L_BREAKABLE \| L_BLOCKER` (51), which every actor builder uses (giant, soldier, wolf, and all later enemies and NPCs). Camera, `OCCLUDER_MASK`, LOS and hurtboxes do not use it. The nav bake treats it as an obstacle. |

- **Render layers:** layer 2 stays `first_person_hidden`. Any new head or chest mesh on the giant uses it. The camera also culls layer 2 in third person while its arm is retracted shorter than 1.2 × the capsule radius (P05), so a wall behind the giant never fills the screen with the back of its head. In first person a held body is posed out of the screen centre (P07), and the tree's canopy is on layer 2 (P08).
- **Navigation layers (bitmask):**

| Layer | Name | Agent radius / height / cell (m) | Used by |
| --- | --- | --- | --- |
| 1 | human | 0.6 / 2.0 / 0.3 | Soldiers, archers, mages, wolves, civilians |
| 2 | large | 1.5 / 4.0 / 0.5 | Ogres |
| 4 | giant | 2.0 / 8.5 / 0.5 | Player stages 2–3, Ogre King, Valley bot, clearance checks |
| 8 | small giant | 0.9 / 3.7 / 0.3 | Player stage 1 (includes the 4 m alleys) |

  Enemy and NPC records choose their layers with `nav_layers`; `EnemyActor` copies it into `NavigationAgent3D.navigation_layers` (P04). Growth profiles carry `nav_layers` (8 / 4 / 4), and P05 switches it on growth.

Groups: the existing `player`, `enemies`, `dummies`, `breakables`, `debris_pool`, `sandbox` and `hud_debug` stay. New groups:

| Group | Members | Created by |
| --- | --- | --- |
| `interactables` | `Interactable` nodes | P02 |
| `checkpoints` | `CheckpointMarker`, `Waystone` and `Shrine` spawn points | P02 |
| `debug_info_providers` | Nodes with `debug_lines() -> PackedStringArray` | P02 |
| `projectile_system` | The single `ProjectileSystem` per level | P03 |
| `shrines` | `Shrine` | P05 |
| `waystones` | `Waystone` | P06 |
| `cosmetic_props` | `CosmeticProp` | P08 |
| `level_root` | `LevelRoot` | P10a |
| `encounter_director` | `EncounterDirector` | P10a |
| `area_triggers` | `AreaTrigger` | P10a |
| `objective_markers`, `ai_cover_points`, `ai_elevation_points`, `ai_formation_points`, `safe_markers`, `patrol_points`, `bot_route_points` | `LevelMarker` by kind; plain `Marker3D` in test scenes | P10a (tests may add plain markers to these groups) |
| `ranged_enemies` | Archers and mages | P09 |
| `bosses` | Ogre King | P11a |
| `npcs`, `civilians` | NPC actors | P11b |

### 2.3 Id and flag conventions

All ids match `^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$`.

| Kind | Pattern | Examples |
| --- | --- | --- |
| Record ids | `<type-ish>.<name>` | `enemy.wolf`, `status.slow`, `quest.main`, `shrine.grove`, `encounter.forest_wolves_a` |
| Valley entity ids (spawned actors) | `valley.<district>.<name>` | `valley.forest.wolf_a1`, `valley.arena.ogre_king`, `valley.village.elder` |
| World ids (persistent props, pickups, shrines) | `valley.<district>.<name>` | `valley.ruins.practice_gate`, `valley.forest.deadfall`, `valley.shrine.grove` (= checkpoint id) |
| Waystones (checkpoint only) | `valley.cp.<name>` | `valley.cp.forest_road` |
| Area triggers | `valley.area.<name>` | `valley.area.arena_engage` |
| Markers | `valley.marker.<name>`; patrol routes `valley.patrol.<name>` | `valley.marker.elder`, `valley.patrol.wolves_a` |
| Flags (in `WorldState.flags`) | `<domain>.<subject>.<name>` | see below |

Flag domains:
- `quest.<q>.stage` (string) and `quest.<q>.done` (bool; false when a branch quest is abandoned)
- `quest.village.outcome` (`help_cache` \| `help_ogre` \| `intimidate` \| `force`) and `quest.village.offer` (`cache` \| `ogre`)
- `reward.<quest short id>.<stage>` for quest stages (the quest id without `quest.`, e.g. `reward.main.grove`, `reward.tutorial.awaken`) and `reward.<dialogue key>.<choice>` for dialogue rewards (e.g. `reward.village.help`); all are once-flags
- `faction.village.{warned,hostile,stood_down,gate_open}`
- `encounter.<encounter short id>.cleared` (example: `encounter.forest_wolves_a.cleared`)
- `tutorial.<prompt>.{seen,done}`
- `dialogue.elder.met`
- `world.ogre_king.defeated`, `world.tree_weapon_taken`, `world.ruins.gate_broken`, `world.forest.deadfall_broken`
- `slice.crown_claimed`, `slice.completed`

**Flag-write semantics:** `try_set_flag` (first write wins) is used for every dialogue `set_flags`, prop `on_destroyed_flags` and reward once-flag. `set_flag` (overwrite) is used only by the quest runner for `quest.*.stage` / `quest.*.done`, by the director for `encounter.*.cleared`, and by FactionState for `faction.village.warned`.

### 2.4 Events (P01 declares all of these; `events.gd` is frozen afterwards except at package anchors)

The existing signals are unchanged: `ability_started`, `action_rejected`, `hit_resolved`, `attack_clanked`, `area_pulse`, `entity_died`, `staggered`, `object_destroyed`, `loot_awarded`, `growth_changed` (now emitted by P05), `lock_target_changed`, `camera_mode_changed`, `hud_message`, `sandbox_reset_requested`.

| Signal (arguments) | Emitted by | Typical listeners |
| --- | --- | --- |
| `status_applied(tick: int, entity_id: String, status_id: String, source_id: String, duration_s: float)` | `CombatEntity.apply_status` (P01) | HUD status row, HitFeedback |
| `status_expired(tick: int, entity_id: String, status_id: String)` | Sim status pass (P01) | HUD |
| `healed(tick: int, entity_id: String, amount: float, source_id: String)` | `CombatEntity.heal` (P01) | HitFeedback (green numbers) |
| `ability_effect(tick: int, actor_id: String, action_id: String, kind: String, center: Vector3, radius: float, yaw: float, arc_deg: float)` — `kind` is `sector` \| `roar` \| `self_buff` \| `cast` \| `aim_preview` | AttackRunner handlers (P03), PlayerGrab (P07) | HitFeedback, cosmetic props |
| `projectile_spawned(tick: int, projectile_id: int, owner_id: String, action_id: String, position: Vector3, velocity: Vector3, visual: String)` | ProjectileSystem (P03) | Presentation; AI hearing |
| `projectile_impact(tick: int, projectile_id: int, position: Vector3, hit_entity_id: String)` (`""` = world) | ProjectileSystem (P03) | HitFeedback |
| `telegraph_started(tick: int, actor_id: String, action_id: String, target_id: String, shape: String, origin: Vector3, yaw: float, radius: float, length: float, duration_s: float)` | EnemyActor, on `controller.phase_entered` WINDUP for an action with `telegraph` (P04) | Telegraph visuals and threat arrows (P09), tutorial director, Valley bot |
| `morale_changed(tick: int, entity_id: String, morale: float, delta: float, reason: String)` | EnemyBrain via EnemyActor (P04) | Debug panel, bot metrics |
| `enemy_routed(tick: int, entity_id: String, encounter_id: String)` | EnemyBrain via EnemyActor (P04) | EncounterDirector, bot metrics |
| `encounter_leashed(tick: int, encounter_id: String, entity_id: String)` | EncounterDirector (P10a) | Debug, bot metrics |
| `grab_started(tick: int, holder_id: String, target_id: String)` | PlayerGrab (P07) | HUD, rig, tutorial |
| `grab_ended(tick: int, holder_id: String, target_id: String, reason: String)` — `reason` is `thrown` \| `dropped` \| `crushed` \| `interrupted` \| `holder_died` \| `target_died` \| `timeout` \| `unloaded` | PlayerGrab (P07) | Tests, HUD |
| `boss_engaged(tick: int, boss_id: String)` | BossArena (P11a) | Boss bar, director |
| `boss_phase_changed(tick: int, boss_id: String, phase: int)` | OgreBossBrain via actor (P11a) | Boss bar, tutorial, tests |
| `boss_defeated(tick: int, boss_id: String)` | BossArena (P11a), after the arena is clear | Quests, GameSession (checkpoint) |
| `faction_changed(tick: int, faction: String, state: String)` — `state` is `warned` \| `hostile` \| `stood_down` | FactionState (P11b) | NPCs, guards, HUD |
| `growth_blocked(tick: int, entity_id: String, reason: String, message: String)` | PlayerGrowth (P05) | Shrine screen, HUD |
| `shrine_activated(tick: int, shrine_id: String)` | Shrine (P05), first activation per load (after the free Rest) | GameSession (checkpoint), HUD, tutorial |
| `shrine_rested(tick: int, shrine_id: String)` | Shrine (P05) | GameSession (checkpoint) |
| `checkpoint_reached(tick: int, checkpoint_id: String, kind: String)` — `kind` is `shrine` \| `waystone` | Shrine (P05), Waystone (P06) | GameSession (respawn point) |
| `object_stage_changed(tick: int, world_id: String, stage_index: int, stage_id: String)` | BreakableProp for `structural` props (P08) | HitFeedback, quests |
| `weapon_equipped(tick: int, entity_id: String, weapon_id: String)` | PlayerEquipment (P08) | HUD, rig |
| `loadout_changed(tick: int, entity_id: String)` | P05 / P08 / P12 slot writers | HUD help |
| `interacted(tick: int, actor_id: String, interact_id: String)` | PlayerInteract (P02, emitted defensively until P01 merges) | Quests, tutorial, bot |
| `object_opened(tick: int, world_id: String, reason: String)` | BreakableProp.force_open (P08) | Director, quests |
| `area_entered(tick: int, area_id: String, entity_id: String)` and `area_exited(...)` | AreaTrigger (P10a) | Quests, tutorial, BossArena |
| `encounter_activated(tick: int, encounter_id: String)` and `encounter_cleared(tick: int, encounter_id: String)` | EncounterDirector (P10a) | Quests, tutorial, debug |
| `xp_award_requested(amount: int, source: String)` | Props with `xp_reward` (P08), Quests (P13), dialogue (P13) | PlayerProgression (P12) |
| `xp_gained(tick: int, amount: int, source: String, total: int)` | PlayerProgression (P12) | XP bar, bot metrics |
| `level_changed(tick: int, old_level: int, new_level: int)` | PlayerProgression (P12) | HUD, quests |
| `ability_learned(tick: int, action_id: String, slot_key: String)` (`slot_key` `""` = not slotted) | P12 (levels and rewards), P05 (stage unlocks) | HUD notice (deferred until out of combat) |
| `attributes_changed(tick: int)` | P12 | HUD, tutorial |
| `item_added(tick: int, item_id: String, count: int, source: String)` and `item_removed(tick: int, item_id: String, count: int, reason: String)` | `WorldState.add_item` / `remove_item` (P01) | Inventory, quests |
| `upgrade_applied(tick: int, from_weapon: String, to_weapon: String)` | Forge (P12) | HUD |
| `flag_changed(tick: int, flag_id: String, value: Variant)` | `WorldState.set_flag` / `try_set_flag` (P01) | Quests, props (`open_when_flag`), factions, waystones |
| `quest_started(tick: int, quest_id: String)`, `quest_stage_changed(tick: int, quest_id: String, stage_id: String)`, `quest_completed(tick: int, quest_id: String)`, `quest_abandoned(tick: int, quest_id: String)` | Quests (P13) | Tracker, GameSession (checkpoint on `quest.main` stages), bot |
| `dialogue_requested(npc_id: String, dialogue_id: String)` | NpcTalker (P13) | Quests (P13) |
| `dialogue_started(tick: int, dialogue_id: String, npc_id: String)`, `dialogue_outcome(tick: int, dialogue_id: String, outcome: String)`, `dialogue_ended(tick: int, dialogue_id: String)` | DialogueSession (P13) | Quests, bot |
| `tutorial_shown(tick: int, prompt_id: String)` and `tutorial_dismissed(tick: int, prompt_id: String, reason: String)` | Tutorial director (P13) | Tutorial widget |
| `slice_completed(tick: int)` | Quests (P13) | End screen, bot |
| `ui_screen_requested(screen: String, args: Dictionary)` | Gameplay (shrine, NPC, forge, end) | ScreenStack (P03), which opens it deferred |
| `checkpoint_saved(tick: int, checkpoint_id: String, ok: bool, message: String)` and `checkpoint_loaded(tick: int, checkpoint_id: String, source: String)` | GameSession (P06) | Checkpoint toast, bot |
| `reload_checkpoint_requested(reason: String)` | main (death confirm), debug F9 (P06) | GameSession |
| `mode_change_requested(mode: String, options: Dictionary)` | Title and pause screens (P06) | GameSession |

Rule (unchanged from M1): listeners never spend resources or change combat state on their own. Gameplay emits only after its state has changed.

### 2.5 Sim tick phases, hooks, RNG streams and launch slots (P01)

```gdscript
# scripts/core/sim.gd (autoload "Sim")
enum Hook { PRE_ACTORS, POST_ACTORS, POST_RESOLVE }
func add_hook(hook: int, owner: Object, callable: Callable, order: int = 100) -> void
func remove_hooks(owner: Object) -> void          # also pruned automatically when owner is freed
func rng_for(stream: String) -> RandomNumberGenerator   # seed = DEFAULT_SEED ^ hash(stream); reseed() resets all
func request_launch_slot(target_id: String, holder_id: String, min_gap_ticks: int) -> bool
func last_launch_tick(target_id: String) -> int
```

`step()` order:
1. `tick += 1`
2. PRE_ACTORS hooks: EncounterDirector activation, leash and LOD (order 10)
3. Actors in entity-id order (unchanged)
4. POST_ACTORS hooks: ProjectileSystem (order 100)
5. `_resolve_hits()`
6. Built-in status pass: every entity in id order runs `CombatEntity.tick_statuses(tick)`
7. POST_RESOLVE hooks: Quests (order 100); FactionState (order 150); GameSession deferred checkpoint (order 200)

Hooks run in (phase, order, registration sequence) order.

- **RNG streams.** Crits keep using `Sim.rng` (pinned by the 37/66/44 tests). Every new random consumer (loot, AI picks, debris, bot) uses `Sim.rng_for("<stream>")` or a private RNG seeded from its id. Nothing new draws from `Sim.rng`.
- **Launch slots.** `request_launch_slot` grants a slot when `tick − last_launch_tick(target) ≥ min_gap_ticks`, then records the tick. Archers and mages use it so ranged launches are staggered (spec §10).
- **Ranged tokens.** Ranged enemies also hold a token from the existing token API under the key `target_id + ":ranged"` with `max_holders` 2 (P09), separate from the 2 melee tokens.
- **Dead shooters.** `_resolve_hits` drops a hit from a dead attacker only if `not hit.from_projectile or attacker.died_tick == tick`. `CombatEntity.died_tick` is set on death.

### 2.6 Combat core API (P01 unless noted)

#### 2.6.1 CombatController additions

```gdscript
signal phase_entered(action: ActionDef, instance_id: int, phase: int)   # emitted when phase() changes, incl. on accept
var level := 99            # character level for unlock_level gating (99 = gating off: sandbox, tests)
var level_exempt := {}     # action id -> true: taught early by a reward (P12 fills it); skips unlock_level
var recovery_scale := 1.0  # Dexterity: multiplies the recovery ticks of light/heavy/ability/ultimate/enemy_attack
var held_by := ""          # holder id while GRABBED
var holding_id := ""       # target id while this actor holds something (set by PlayerGrab)
func request(kind: StringName, params: Dictionary = {}) -> int
	# params may carry "precheck": Callable() -> String (reason, "" = ok); evaluated last, before
	# accept, also when a buffered request is retried; a non-empty reason = REJECT, nothing spent.
func preview_reason(kind: StringName, params: Dictionary = {}) -> String
	# side-effect free; returns the reject reason the request would get now, "busy" if it would be
	# buffered, "" if it would be accepted. HUD uses it (one source of truth).
func force_action(def: ActionDef) -> void   # scripted follow-up (charge -> wall recovery, boss phase roar):
	# finishes the current action (not interrupted), starts def without cost/cooldown/state checks
func enter_grabbed(holder_id: String) -> bool   # from LOCOMOTION/ATTACKING/CASTING/STAGGERED/BLOCKING;
	# interrupts any action (no refund), clears buffer, ends stagger, state GRABBED
func release_grabbed(reason: String, recovery_s: float = 0.6) -> void   # GRABBED -> STAGGERED(recovery_s)
func set_growth_stage(stage: int) -> void
```

- `_evaluate` order: dead → resolve → `unlock_stage` ("locked") → `unlock_level` ("level_locked", skipped for ids in `level_exempt`) → cooldown → state ("busy" RETRY) → airborne → stamina → essence → fury → precheck.
- `recovery_scale` never changes windup, active, parry or dodge timing (spec §9). It applies to the recovery phase of attack kinds only; dodge, block, jump and sprint are untouched.
- Actions whose `hit_shape` is `"grab"` run in **EXECUTING**. It advances like CASTING, has the same move/rotate rules, pauses stamina regeneration, and returns to LOCOMOTION when finished.
- GRABBED does not advance timelines. `apply_stagger` returns false while GRABBED. `kill()` from GRABBED sets DEAD and clears `held_by`.
- `move_speed_multiplier()` is now multiplied by `combatant.move_mult()` (slows) in every state. With no statuses it is 1.0, so existing tests are unchanged.

#### 2.6.2 Combatant, ResourcePool and PoiseMeter

```gdscript
# Combatant
var statuses := StatusSet.new()
var status_immunities := PackedStringArray()   # status tags (e.g. "Fear", "Slow")
var mass_class := "small"                      # small < medium < large < immovable
var xp_reward := 0
var base_record: Dictionary = {}
var growth_bonus: Dictionary = {}              # {"health": 150, "stamina": 10}
func armor_total() -> float                    # armor + statuses.modifier_sum("armor_flat")
func outgoing_damage_mult() -> float           # product of "outgoing_damage_mult"
func outgoing_poise_mult() -> float
func damage_taken_mult() -> float              # product of "damage_taken_mult" (barrier, bot assist, stress)
func move_mult() -> float                      # 1 - clamp(max "slow_fraction", 0, 0.9)
func fury_gain_mult() -> float                 # product of "fury_gain_mult" (Titan Surge = 0)
func set_attributes(attrs: Dictionary) -> void # then recompute_derived()
func recompute_derived() -> void               # maxima = base resources + Endurance/Intellect bonuses +
	# growth_bonus; poise threshold from Constitution (value kept); pools.rescale(); recovery_scale
	# from Dexterity (1 - min(0.005 * (dex - 10), 0.15)) pushed to the controller by CombatEntity
func set_height(height_m: float) -> void
# ResourcePool
var fury_gain_mult := 1.0                      # maintained by Combatant when statuses change
func add_fury(amount: float) -> void           # fury += amount * fury_gain_mult (clamped)
func rescale(new_max: Dictionary) -> void      # health/stamina/essence keep ratios; fury absolute, clamped
func snapshot() -> Dictionary                  # {"health","stamina","essence","fury"}
func restore(values: Dictionary) -> void       # clamp to maxima; regen timers set as if idle (999)
# PoiseMeter
var recovery_mult := 1.0                       # poise config "recovery_mult": poise damage taken during the
	# owner's own RECOVERY phase is multiplied by it (ogre and boss 3.5: the "recovery punish")
var stagger_vs_larger_s := -1.0                # poise config; < 0 = stagger_s. Used when the attacker is at
	# least 2x the defender's height (soldier 1.5 s, so a grab after a heavy lands reliably)
func reconfigure(cfg: Dictionary, constitution: float, keep_value: bool = true) -> void
```

`Combatant.from_record` reads the new optional fields. For enemies it reads `essence` and `regen` when there is no `resources` block, which fixes "enemies have 0 essence".

#### 2.6.3 Statuses

```gdscript
class_name StatusDef extends RefCounted
var id: String; var display_name: String; var hud_label: String
var stacking: String          # "refresh_no_stack" | "strongest_wins" | "independent"
var duration_ticks: int; var tick_ticks: int    # tick_ticks 0 = no periodic effect
var magnitude_key: String     # "" or one STATUS_MODIFIERS key fed by the application's magnitude
var default_magnitude: float
var modifiers: Dictionary     # STATUS_MODIFIERS key -> float
var tags: PackedStringArray   # STATUS_TAGS
var hidden := false           # not shown in the HUD status row (bot assist, stress invulnerability)
static func from_dict(d: Dictionary) -> StatusDef

class_name StatusSet extends RefCounted
signal changed
func apply(def: StatusDef, magnitude: float, duration_s: float, source_id: String, now: int,
		immunities: PackedStringArray) -> bool        # false if immune; NAN magnitude = default
func remove(status_id: String) -> void
func clear() -> void
func has(status_id: String) -> bool
func remaining_s(status_id: String, now: int) -> float
func tick(now: int) -> Array          # [{"type": "expired"|"heal", "id": String, "amount": float}]
func modifier_sum(key: String) -> float
func modifier_product(key: String) -> float
func modifier_max(key: String) -> float
func hud_list(now: int) -> Array      # [{"id","label","remaining_s","debuff": bool}] sorted by id; hidden skipped
```

- **Policies (spec §8).** `refresh_no_stack` refreshes the duration and keeps the magnitude. `strongest_wins` keeps the maximum magnitude and refreshes the duration. `independent` appends a new instance (not used in the slice).
- **Healing over time** ticks every `tick_ticks` after application, the last tick on the expiry tick. Mend therefore heals 8 × 12.5 = 100 over 4 s. Healing caps at maximum health and is skipped once dead.
- **CombatEntity** (P01) adds:
  - `apply_status(status_id: String, magnitude: float = NAN, duration_s: float = -1.0, source_id: String = "") -> bool`, which emits `status_applied`
  - `heal(amount: float, source_id: String) -> void`, which emits `healed`
  - `tick_statuses(now: int) -> void`, which emits `status_expired` and applies heals
  - `var died_tick := -1`
  - `var faction := ""`, read in `_ready` from the actor's `faction` property (like `entity_id`); `""` for dummies, props and the player
  - `_apply_on_hit_effects(result, attacker)`. On HIT it applies `hit.on_hit_statuses` (and on BLOCKED those with `on_blocked`). For `hit.morale_damage > 0` on HIT or BLOCKED it calls `actor.on_morale_delta(-hit.morale_damage, hit.attacker_id)` if that method exists.
  - Poise rules: poise damage is multiplied by `poise.recovery_mult` while the defender's controller is in the RECOVERY phase of an attack; a poise break caused by an attacker at least twice the defender's height staggers for `stagger_vs_larger_s` when that is set.
- **DamageResolver** uses `defender.armor_total()` for physical damage and multiplies both typed portions by `defender.damage_taken_mult()` before block and rounding. All pinned numbers are unchanged without statuses.

#### 2.6.4 Targeting rules, record overrides

```gdscript
# TargetingRules (P01)
static func player_may_target(e: CombatEntity) -> bool
	# true for team ENEMY, and for team NEUTRAL with faction == "" (dummies, props);
	# false for the player and for NEUTRAL faction members (villagers, neutral guards).
	# Used for hard lock, soft targeting and the player's area effects (P03).
# GameData (P01)
func override_record(id: String, patch: Dictionary) -> Dictionary   # deep-merges patch into records[id],
	# refreshes the ActionDef/StatusDef caches, returns the previous record (for restore)
func restore_record(id: String, previous: Dictionary) -> void
func records_of_type(type: String) -> Array                          # raw dicts, sorted by id
func get_status(id: String) -> StatusDef
```

#### 2.6.5 HitEvent additions and HitFactory (P02 creates; P03 wires statuses)

```gdscript
# HitEvent (P01): new fields
var on_hit_statuses: Array = []   # [{"status","magnitude","duration_s","on_blocked"}]
var morale_damage := 0.0
var from_projectile := false
var projectile_id := 0
var area_effect := false          # set by P03 for cylinder and sector pulses and projectile splash

class_name AttackContext extends RefCounted        # P02; later packages add fields at their anchor
var entity: CombatEntity
var instance_id := 0
var weapon: Dictionary = {}
var growth_stage := 1
var attacker_position := Vector3.ZERO              # projectiles: impact point
var registry: HitRegistry                          # controller.hit_registry, or a projectile's own

class_name HitFactory extends RefCounted           # P02
static func sort_candidates(cands: Array) -> void  # substep, distance, entity id (stable)
static func skip_candidate(attacker: CombatEntity, target: CombatEntity, area_effect: bool) -> bool
	# P02: false (no filtering). P03: true when the attacker is the player, area_effect is true
	# and not TargetingRules.player_may_target(target): area effects never touch neutral bystanders.
static func build(ctx: AttackContext, a: ActionDef, cand: Dictionary, pulse_id: int, tick: int) -> HitEvent
static func queue(ctx: AttackContext, a: ActionDef, cands: Array, pulse_id: int, tick: int) -> int
```

`build` sets every field for every source:
- `weapon_multiplier` comes from `ctx.weapon` when `a.uses_weapon`.
- `attacker_stat` is Intellect for `category == "magic"`, otherwise Strength.
- `weak_point` comes from the candidate, and `attacker_growth_stage` from `ctx.growth_stage`.
- The crit is rolled with `Sim.rng` in build order (as today).
- From P03: `outgoing_damage_mult`/`outgoing_poise_mult` from the attacker's combatant, `on_hit_statuses` and `morale_damage` from the action, weapon `tags` appended when `a.uses_weapon`, and `area_effect`.

### 2.7 Actor-side contracts

#### 2.7.1 GiantPlayer and components (P02)

GiantPlayer keeps every public name that tests and the HUD use: `router`, `controller`, `lock`, `entity`, `camera_rig`, `rig`, `body_shape`, `profile`, `weapon`, `record`, `growth_stage`, `stats`, `facing_yaw`, `sprinting`, `sprint_toggled`, `move_velocity`, `knockback_velocity`, `dodge_direction`, `prev_segment`, `weapon_pivot`, `attack_origin`, `arm_length`, `weapon_length`, `weapon_radius`, `spawn_transform`, `last_intents`, group `player`, entity id `player`, and the node paths `Visual/Body/Torso/{Chest,Belt,Head}` and `Visual/Body/ShoulderR/Forearm`. Its methods stay public as well: `locked_entity()`, `weapon_segment_global()`, `get_defense_state()`, `apply_knockback()`, `on_entity_died()`, `flash()`, `get_rig_state()` and `get_debug_info()`.

```gdscript
const COMPONENTS := [   # [name, path]; missing files are skipped (ResourceLoader.exists)
	["motor", "res://scripts/actors/player/player_motor.gd"],              # P02
	["targeting", "res://scripts/actors/player/player_targeting.gd"],      # P02
	["attack", "res://scripts/actors/player/player_attack.gd"],            # P02
	["interact", "res://scripts/actors/player/player_interact.gd"],        # P02
	["growth", "res://scripts/actors/player/player_growth.gd"],            # P05
	["equipment", "res://scripts/actors/player/player_equipment.gd"],      # P08
	["grab", "res://scripts/actors/player/player_grab.gd"],                # P07
	["progression", "res://scripts/actors/player/player_progression.gd"],  # P12
]
var motor; var targeting; var attack; var interact          # always present (typed)
var growth = null; var equipment = null; var grab = null; var progression = null   # untyped
func component(name: StringName) -> PlayerComponent
func ensure_action(id: String) -> void                 # adds id + chain_next ids to controller.library
func set_loadout_slot(slot_key: String, action_id: String) -> void   # "slot_1".."slot_8"|"ultimate"; no gating
func apply_character_state(state: Dictionary) -> void  # order: growth, progression, equipment, core
func capture_character_state() -> Dictionary
func attack_origin_global() -> Vector3
func current_weapon() -> Dictionary
func current_growth_stage() -> int
func current_weapon_scale() -> float                   # P02: profile weapon_scale (1.0 default); P08 adds the fit cap
# PlayerMotor (P02)
func set_speed_mult(source: StringName, mult: float) -> void   # e.g. &"grab" 0.6; 1.0 removes the source
```

```gdscript
class_name PlayerComponent extends RefCounted
var player: GiantPlayer
func setup(p: GiantPlayer) -> void
func edge_priority() -> int                      # lower first; grab 10, interact 50, default 100
func handle_edge(edge: StringName) -> bool       # true = consumed
func pre_actions(intents: Dictionary, dt: float) -> void
func post_movement(tick: int, dt: float) -> void
func on_action_started(action: ActionDef, instance_id: int) -> void
func on_action_ended(action: ActionDef, instance_id: int, interrupted: bool) -> void
func on_profile_changed(old_profile: Dictionary, new_profile: Dictionary) -> void
func on_weapon_changed(weapon: Dictionary) -> void
func apply_state(state: Dictionary) -> void
func capture_state(out: Dictionary) -> void
func rig_state(out: Dictionary) -> void
func debug_info(out: Dictionary) -> void
func interact_candidate() -> Dictionary          # {} or {"priority","prompt","distance","call": Callable}
func on_exit() -> void                            # scene unload (release grabs)
```

`sim_step` order:
1. `router.consume()`.
2. Set `controller.on_floor` and `controller.block_held`, then `begin_tick`.
3. If not dead:
   - every component's `pre_actions`;
   - each edge is offered to components by `edge_priority`. Unconsumed edges get the default mapping: meta edges go to targeting/motor, and actions go to `controller.request`, as in M1;
   - `resume_held_block`.
4. Motor sprint, then facing, then movement.
5. `attack.run_hit_queries(tick)`, which uses AttackRunner.
6. Every component's `post_movement`.
7. Pools and poise tick. Statuses are ticked by Sim, not here.
8. `targeting.maintain_lock`.
9. Out-of-world reset.

**Core state handled by GiantPlayer itself** in `apply_character_state` / `capture_character_state`: `loadout`, `known_abilities` and `level` (which sets `controller.level`, unless a progression component owns it), plus `resources` (applied **last** via `pools.restore`). Keys that no one handles (`ancestry`, `xp`, `attributes`, …) are stored and returned unchanged on capture (passthrough). The save format therefore round-trips even before P05, P08 and P12 exist.

**Cross-lane symbols for P02 (wave 0).** P02 runs beside P01 and must not reference what P01 is adding. It writes `level` with `if "level" in controller: controller.set("level", v)`, applies `resources` with `pools.restore` only `if pools.has_method("restore")` (otherwise it assigns and clamps the existing pool fields), emits `interacted` only `if Events.has_signal(&"interacted")`, and calls `GameData.override_record` from `TestFixtures` only `if GameData.has_method("override_record")` (otherwise it patches `GameData.records` and restores it). Router edges such as `debug_grow` are plain `StringName`s that no P02 code needs. P02 never references `TargetingRules.player_may_target`, `CombatEntity.faction`, `ResourcePool.snapshot`, `Sim.add_hook` or the new `DataValidator` enums. The guards stay in the code after the merge; they cost nothing.

#### 2.7.2 AttackRunner (P02; shapes added by later packages)

```gdscript
class_name AttackRunner extends RefCounted
var actor: Node3D; var entity: CombatEntity; var controller: CombatController
var emit_clank := false
var prev_segment := PackedVector3Array()
var aim_point := Vector3.INF                   # P03: set by an enemy actor at its aim-lock tick; used and
	# cleared by the projectile handler for aim "target"
func _init(p_actor: Node3D, p_entity: CombatEntity, p_controller: CombatController) -> void
func register_shape(shape: String, handler: Callable) -> void   # handler(a: ActionDef, tick: int)
func run(tick: int) -> void
func context() -> AttackContext
func reset() -> void
```

The actor provides (duck typed): `weapon_segment_global(action, f)`, `attack_origin_global()`, `current_weapon()` and `current_growth_stage()`. Every candidate list passes through `HitFactory.skip_candidate` before queuing (§2.6.5). Shapes are added by package:

| Package | Shapes |
| --- | --- |
| P02 | `weapon_arc`, `cylinder_pulse` |
| P03 | `sector_pulse`, `projectile` (splash pulses inherit the projectile action's `category`, tags and statuses), `none` + `self_statuses` (on `phase_entered` ACTIVE), and `radius_by_stage_m` for pulses. P03 also sets `area_effect` on every cylinder pulse, sector pulse and splash, and fills in `skip_candidate`. |
| P07 | `grab` (registered from `PlayerGrab.setup`, or at the P07 anchor) |
| P11a | `body_sweep` (registered by `OgreBoss` on its own runner; no shared edit) |

Telegraphs are emitted by EnemyActor (P04), not by AttackRunner.

#### 2.7.3 EnemyActor and EnemyBrain (P02 creates; P04, P07, P09, P10a, P11a and P11b extend at anchors)

```gdscript
class_name EnemyActor extends CharacterBody3D
@export var entity_id := ""; @export var patrol_route: NodePath; @export var ai_enabled := true
@export var faction := ""           # P11b behaviour; "" = always hostile
@export var encounter_id := ""      # set by EncounterDirector
@export var persist_death := false  # director records kills when true
@export var commander := false      # P04: its death costs nearby allies 25 morale; it is the encounter's leader
@export var loot_table := ""        # per-spawn override set by the director; "" = the record's (P12 reads it)
var home_position := Vector3.ZERO   # spawn point; the director sets it (leash target)
var record; var weapon; var controller: CombatController; var brain: EnemyBrain; var runner: AttackRunner
func _make_brain() -> EnemyBrain                    # virtual
func _sense_extra(snapshot: Dictionary) -> void     # virtual
func _is_guarding() -> bool                         # virtual (soldier guard)
func _custom_movement(dt: float) -> bool            # virtual; P04 implements `motion` (lunge, charge, grab lunge)
func set_lod_tier(tier: int) -> void                # P04: 0 full; 1 reduced (1 Hz perceive, 2 Hz decide,
	# re-path at most 1 Hz and only after a path failure); 2 dormant (process_mode DISABLED,
	# Visual/Body hidden, Visual/LodProxy shown)
func on_morale_delta(delta: float, source_id: String) -> void   # P04
func on_morale_event(event: StringName) -> void     # P04: "siege_destroyed" (-20); no slice content raises it
func is_routed() -> bool                            # P04
func begin_leash_return() -> void                   # P10a: drop the target, walk to home_position, heal to
	# full after 6 s outside the leash
func can_be_grabbed() -> bool; func on_grabbed(holder_id: String) -> void; func on_released(reason: String) -> void  # P07
func current_aim_point() -> Vector3                 # P09: the point a drawn shot will fly to (INF when none)
func is_guarding() -> bool; func get_defense_state() -> DefenseState; func get_debug_info() -> Dictionary
```

```gdscript
class_name EnemyBrain extends RefCounted
enum AIState { IDLE, PATROL, ALERT, APPROACH, ATTACK, RECOVER, REPOSITION, FLEE, STAGGERED, DEAD,
	HOLD, STAND_DOWN, RETURN, ROUTED }
# perceive(tick, snapshot), on_noise(tick, pos, source_id, certain), on_ally_died(), on_morale_delta(delta, source_id, tick),
# decide(tick, controller_state, my_position, request_token: Callable, release_token: Callable), on_path_failed(pos),
# state_name(), is_outmatched() -> bool, has_leader() -> bool, _decide_engaged(...) (virtual), _choose_attack() -> String (virtual)
var aware := false   # existing; GameSession checks it for checkpoint deferral
```

- `SoldierEnemy extends EnemyActor` and `SoldierBrain extends EnemyBrain` keep their names, fields, exports and `SoldierBrain.AIState.*`. Inherited enum access was verified on 4.6.3.
- `HOLD`, `STAND_DOWN`, `RETURN` and `ROUTED` are appended at the end, so existing indices are unchanged.
- Snapshot keys add `target_forward` (Vector3), `target_height` (m), `target_radius` (m), `target_stage` (int), `target_state` (int), `self_health_frac` (P02 adds the keys; P04 uses them).
- A brain leaves ATTACK when the controller is neither ATTACKING nor CASTING (P04 fix), so `kind: "ability"` casts work.
- Every enemy scene has `Visual/LodProxy` (one box, hidden) beside `Visual/Body`, and `Anchors/Grab` where it can be grabbed (§2.12).

#### 2.7.4 Interactables, checkpoints and level classes

```gdscript
class_name Interactable extends Node3D          # P02; group "interactables"
@export var interact_id := ""; @export var prompt := "Interact"; @export var radius_m := 3.5
@export var priority := 50; @export var enabled := true
func can_interact(player: GiantPlayer) -> bool
func blocked_reason(player: GiantPlayer) -> String     # shown as a warn message when E is pressed
func prompt_text(player: GiantPlayer) -> String
func interact(player: GiantPlayer) -> void

class_name CheckpointMarker extends Marker3D     # P02; group "checkpoints"
@export var checkpoint_id := ""
func spawn_transform() -> Transform3D
```

PlayerInteract refreshes every 6 ticks. A candidate must be within `radius_m` plus the player's capsule radius (horizontal) and in front (dot ≥ 0.2, or closer than 1.5 m). Component candidates (`interact_candidate()`) are included. The best candidate has the lowest priority value, then the shortest distance. `player.interact.current_prompt() -> String` serves the HUD. An `interact` edge with no candidate does nothing.

Every placed class and its exports (the Valley layout and the builders set exactly these):

| Class (base) | Package | Exports | Public API beyond `Interactable` |
| --- | --- | --- | --- |
| `Waystone` (CheckpointMarker) | P06 | `checkpoint_id`, `radius_m` (10), `requires_flags: PackedStringArray` | `is_reached() -> bool`; emits `checkpoint_reached(…, "waystone")` once per load when the player is inside and every flag is truthy |
| `Shrine` (Interactable) | P05 | `world_id`, `shrine_id` (a `shrine` record id) | `activate(player) -> bool` (first time per load: free Rest, `checkpoint_reached`, `shrine_activated`); `rest(player) -> Dictionary`; `can_grow(player, target: int) -> Dictionary` (`{ok, reason, message}`); `grow(player, target: int) -> Dictionary`; `record() -> Dictionary`; children `SpawnPoint` (CheckpointMarker, `checkpoint_id = world_id`) and `GrowthPad` (Marker3D) |
| `UprootTree` (Interactable) | P08 | `world_id`, `prop_id` (`prop.ancient_oak`), `weapon_id` (`weapon.tree_oak`) | `interact` grants and equips the tree |
| `WeaponRack` (Interactable) | P08 | `world_id`, `weapon_id` | `interact` grants and equips once (delta `taken`) |
| `ItemPickup` (Interactable) | P08 | `world_id`, `item_id`, `count` (1), `set_flag` (`""` or a flag id) | `interact` grants once (delta `taken`) and hides |
| `Forge` (Interactable) | P12 | `world_id`, `display_name`, `requires_flags: PackedStringArray`, `requires_flag_values: Dictionary` | `can_upgrade(player) -> Dictionary`; `upgrade(player) -> Dictionary`; `interact` opens the forge screen |
| `NpcTalker` (Interactable) | P13 | `npc_id`, `dialogue_id` | `interact` emits `dialogue_requested(npc_id, dialogue_id)` |
| `CosmeticProp` (Node3D, not interactable, no CombatEntity) | P08 | `prop_id`, `react_radius_m` | `react(source: Vector3, strength: float)`; `react_count` (tests) |
| `PracticeDummy` (existing) | M1 | `entity_id` | unchanged; the layout table sets `entity_id` (`valley.hollow.dummy_1`) |
| Crown relic | P08 class, P15 data | an `ItemPickup` with `item.crown_first_king` and `set_flag = slice.crown_claimed` | — |

```gdscript
class_name LevelMarker extends Marker3D          # P10a
enum Kind { OBJECTIVE, COVER, ELEVATION, FORMATION, SAFE, PATROL, BOT_ROUTE }
@export var marker_id := ""; @export var kind: Kind; @export var faction := ""

class_name AreaTrigger extends Area3D            # P10a; layer 0, mask ACTORS, group "area_triggers"
@export var area_id := ""; @export var once := false
var player_inside := false                       # emits area_entered / area_exited for the player only

class_name LevelRoot extends Node3D              # P10a; group "level_root"
@export var level_id := "level.valley"
func level_record() -> Dictionary
func marker(id: String) -> Node3D; func checkpoint(id: String) -> Node3D; func area(id: String) -> AreaTrigger
func patrol_route(route_id: String) -> Node3D    # Markers/Patrol/<route_id>; its Node3D children are the points
func district_at(pos: Vector3) -> String; func player() -> GiantPlayer; func nav_map() -> RID
func nav_region(layer: int) -> RID               # for region_get_closest_point (flee and safe points)

class_name EncounterDirector extends Node        # P10a; group "encounter_director"
func spawned(entity_id: String) -> Node3D
func encounter_state(encounter_id: String) -> String   # "dormant" | "active" | "cleared"
func active_combatant_count() -> int
func force_activate(encounter_id: String) -> void      # tests and bot
func despawn(entity_id: String) -> void                # unspawned, respawns at home on the next activation (BossArena)
func debug_lines() -> PackedStringArray

class_name ProjectileSystem extends Node         # P03; group "projectile_system"; one per level, lazily created
static func instance(tree: SceneTree) -> ProjectileSystem   # parented to the "level_root" node if there is one,
	# otherwise to tree.current_scene, so it is freed with the level (no stale projectiles across reloads)
func spawn(owner: CombatEntity, a: ActionDef, origin: Vector3, velocity: Vector3, ctx: AttackContext) -> int
func active_count() -> int
```

The director spawns each actor before adding it to the tree under `LevelRoot/Spawned`, and sets `patrol_route` to the **absolute** path of `Markers/Patrol/<route_id>` (the soldier collects patrol points from that node's children in `_ready`).

### 2.8 Data schemas

#### 2.8.1 Validator structure (P01)

- `DataValidator` keeps `validate_record`, `validate_references`, the shared enum constants and every existing error string. It gains an **optional registry**:
  ```gdscript
  const SCHEMA_PATHS := {"action": "res://scripts/core/schemas/action_schema.gd", …}  # every planned type
  static var SCHEMAS := {}          # built once from the paths that exist (ResourceLoader.exists + load)
  static var RECORD_TYPES := []     # = SCHEMAS.keys(); a test asserts it equals the schema files present
  ```
- `scripts/core/schemas/schema_util.gd` (`class_name SchemaUtil`) holds the public builders and checkers moved from `DataValidator`: `num`, `pos`, `int_field`, `str_field`, `ref`, `vec3`, `poise_fields`, `check_fields`, `check_value`, `require`, `check_tick_multiple`, `is_number`, `check_flag_id`, `check_conditions`.
- Each `<type>_schema.gd` provides:
  ```gdscript
  static func fields() -> Dictionary
  static func semantic(d: Dictionary, ctx: String, out: Dictionary) -> void
  static func required_ids() -> Dictionary
  ```
- `GameData.REQUIRED_RECORDS` is the merge of all `required_ids()`. It holds the existing six ids plus `progression.default`.
- `GameData` gains `get_status(id) -> StatusDef`, `records_of_type(type) -> Array`, `override_record` / `restore_record` (§2.6.4), and a post-pass for cross-record checks with package anchors (P01 adds the enemy-telegraph warning, P09 turns it into an error, P10a adds the "Duplicate spawn entity_id '…'" check across encounters).

Who writes each schema module (a data file of a type whose module does not exist yet fails validation, so a type's first records ship with its module):

| Record types | Schema module written by |
| --- | --- |
| `action`, `growth_profile`, `player`, `enemy`, `prop`, `weapon`, `item`, `ancestry`, `input_bindings` | P01 (moved from `DataValidator`; later fields added at anchors by the packages in §2.8.2) |
| `status_effect`, `progression` | P01 |
| `shrine` | P05 |
| `encounter`, `level` | P10a |
| `loot_table` | P12 |
| `dialogue`, `quest`, `tutorial_prompt` | P13 |
| `npc` | P11b |

New enum constants on `DataValidator` (P01 declares every planned value now, so no later package edits an enum). Lists marked with + are additions to an existing list:

```
TAGS += TreeWeapon, Throw, Charge          HIT_SHAPES += sector_pulse, projectile, grab, body_sweep
WEAPON_FAMILIES += tree, bow, staff, jaws, natural      ARCHETYPES += training
STATUS_STACKING = refresh_no_stack, strongest_wins, independent
STATUS_MODIFIERS = armor_flat, slow_fraction, outgoing_damage_mult, outgoing_poise_mult, fury_gain_mult, heal_per_tick, damage_taken_mult
STATUS_TAGS = Buff, Debuff, Slow, Fear, Heal, Barrier, Ultimate
MASS_CLASSES = small, medium, large, immovable          PROJECTILE_VISUALS = bolt, boulder, arrow, thrown_body
AIM_MODES = lock_or_camera, camera, target, forward     TELEGRAPH_SHAPES = circle, line, cone
GRAB_ATTACH = none, torso_fist, scruff, two_hand
OUTMATCHED_BEHAVIORS = none, formation, harass, spread, kite, retreat
NPC_ROLES = civilian, talker      ITEM_CATEGORIES = material, quest, trophy, key     DODGE_STYLES = roll, sidestep
CONDITION_TYPES = flag, entered, killed, encounter_cleared, destroyed, has_item, hits_on, stage_at_least,
                  level_at_least, weapon_equipped, dialogue_outcome, all, any, not
BOT_ACTIONS = go, fight_encounter, kill, attack, break, hurl_at, interact, talk, grow, rest, equip, wait
TUTORIAL_TRIGGERS = entered, flag, level, stage, event      TUTORIAL_DISMISS = action_kind, action_id, event, flag, timeout
TUTORIAL_EVENTS = camera_mode_changed, lock_target_changed, ability_started, telegraph_started, hit_resolved,
                  staggered, grab_started, boss_phase_changed, interacted, attributes_changed, shrine_activated,
                  encounter_activated
```

`RECORD_TYPES` is no longer a constant list; it is derived from the registry.

#### 2.8.2 New fields on existing types (all optional; defaults in parentheses; "By" = the package that adds the field to the schema at its anchor)

**action**

| Field | Spec | By |
| --- | --- | --- |
| `unlock_level` | int 1–20 (1) | P01 |
| `sector_deg` | number > 0, ≤ 360; required for `sector_pulse` | P03 |
| `radius_from` | enum `fixed` \| `melee_reach` (`fixed`) | P03 |
| `radius_by_stage_m` | array of numbers > 0; index = stage − 1; the last value is used beyond the list | P03 |
| `self_statuses` | array of `{status: ref status_effect (req), magnitude: num, duration_s: pos}` | P03 |
| `on_hit_statuses` | array of `{status: ref (req), magnitude: num, duration_s: pos, on_blocked: bool}` | P03 |
| `morale_damage` | number ≥ 0 (0) | P03 |
| `projectile` | `{speed_mps: pos (req), radius_m: pos (req), range_m: pos (req), gravity_mps2: ≥0 (0), aim: AIM_MODES (lock_or_camera), arc_to_target: bool (false), launch_offset_m: vec3 (stage-1 local; scaled by k), visual: PROJECTILE_VISUALS (bolt), impact_radius_m: ≥0 (0), impact_height_m: pos (2.0), pierce: bool (false)}`; required for `hit_shape: projectile`. The impact splash always inherits the action's `category`, tags and `on_hit_statuses`. | P03 |
| `motion` | `{phase: windup\|active\|recovery (req), speed_mps: pos (req), max_distance_m: pos, stop_on_wall: bool, on_wall_action: ref action (allow empty), steer_deg_s: ≥0 (0), approach_stop_m: ≥0 (0; stop when this close to the target)}`; required for `body_sweep` | P04 |
| `telegraph` | `{shape: TELEGRAPH_SHAPES (req), radius_m: pos, length_m: pos, width_m: pos, arc_deg: pos}` | P04 |
| `ai_min_range_m` / `ai_max_range_m` | ≥ 0 / > 0, used by brains to pick attacks | P04 |
| `grab` | `{mode: hold\|crush (req), release_after: bool, max_mass: MASS_CLASSES (profile capacity)}`; required for `hit_shape: grab` | P07 |
| `targets_ally` | bool (mage barrier) | P09 |

Semantic checks: an action that an enemy uses (kind `enemy_attack`, or listed in any enemy record's `attacks` or `boss.phases[].attacks`; a GameData post-pass check) with `windup_s ≥ 0.8` must have a `telegraph` (a warning until P09, an error from P09 on); a `light` or `heavy` action without the `BasicAttack` tag is a warning (fury, spec §7).

**growth_profile** (P05 adds the fields and fills in the values in §4.8)

| Field | Spec |
| --- | --- |
| `weapon_scale` | pos (1) |
| `grab_reach_m` | pos |
| `grab_lunge_m` | ≥ 0 (0) |
| `grab_capacity` | MASS_CLASSES (`small`) |
| `grab_attach` | array of GRAB_ATTACH (`["torso_fist", "scruff"]`) |
| `resource_bonus` | dict `keys_enum [health, stamina, essence]`, values ≥ 0 |
| `arc_pitch_offset_deg` | −30 to 0 (0) |
| `dodge_style` | DODGE_STYLES (`roll`) |
| `camera_orbit_scale` | pos (1) |
| `nav_layers` | int 1–255 (4) |
| `footstep_shake` | 0–1 (0) |

**player** (P05): `mass_class` (`large`), `status_immunities` (array STATUS_TAGS).

**enemy**
- P01: `xp_reward` (int ≥ 0); the shared `poise` block gains `recovery_mult` (≥ 1, default 1) and `stagger_vs_larger_s` (pos).
- P04: `scene` (string starting `res://scenes/` and ending `.tscn`, which must exist; checked with `ResourceLoader.exists`), `mass_class`, `status_immunities`, `essence` (≥ 0), `regen` (player regen fields, none required), `nav_layers` (int, default 1), `ignores_morale` (bool).
- P04: `ai` gains optional `awareness_radius_m` (8), `ally_death_radius_m` (15), `morale_debounce_s` (2), `flee_distance_m` (12), `corpse_linger_s` (0 = never freed by the actor), `regroup_needs_leader` (**true**), `leader_radius_m` (20), `rout_after_s` (20). `sight_range_m` already exists; archers override it to 32.
- P04: `tactics`: `{preferred_min_m, preferred_max_m, outmatched_ratio, outmatched_behavior (OUTMATCHED_BEHAVIORS), spread_m, flank_angle_deg, lunge_range_m, cover_search_radius_m, launch_gap_s, barrier_range_m, charge_min_range_m, commander_bonus_morale, formation_spacing_m (3), hold_attack (ref action, allow empty), awe_ratio (0 = never), awe_morale_loss}`, all numbers ≥ 0.
- P07: `grab_attach` (GRAB_ATTACH, `none`).
- P11a: `boss`: `{phases: [{id: str (req), health_frac_below: 0–1 (req), attacks: [refs] (req), attack_weights: [nums], sequence: [refs], enter_action: ref action}]}`. When `sequence` is present the brain cycles it in order and ignores the weights. Semantic checks: phases are sorted by descending `health_frac_below`; weights match their attacks; every `sequence` entry is in `attacks`.
- P12: `loot_table` (ref `loot_table`, allow empty).

**prop** (P08 unless noted)
- `debris_length_m` (pos, default 8), `debris_layout` (`line` \| `pile`)
- `required_tags` (TAGS), `locked_message` (str; shown for a rejected category, tag, stage or permission), `protected` (bool)
- `xp_reward` (int), `uproot_weapon` (ref weapon), `requires_permission` (INTERACTION_PERMISSIONS)
- `on_destroyed_flags` (dict flag id → bool/number/string; flag ids checked by regex), `open_when_flag` (flag id)
- `damage_stages`: array of `{id: str (req), at_or_below_frac: 0–1 (req), visual: str (req; child node name), removes_collision: bool, enables_nav_links: bool}`; required for `category: structural`. Semantic checks: sorted by descending fraction; the first is 1.0; the last is 0.0 and removes collision.
- `react_radius_m` (pos; `cosmetic` only)
- `loot_table` (ref `loot_table`, allow empty) — P12

**weapon** (P08): `scales_with_growth` (bool, true), `fit_max_stage` (int 1–10, default 10 = never capped), `light_chain` (ref action), `heavy` (ref action), `required_stage` (int), `required_permission` (enum), `tags` (TAGS), `visual_shape` (`club` \| `sword` \| `hammer` \| `tree` \| `bow` \| `staff` \| `none`), `upgrade` (`{to: ref weapon (req), cost: [{item: ref item (req), count: int ≥1 (req)}]}`). Semantic check: an `upgrade.to` weapon must have a `fit_max_stage` at least as high as its source.

**item** (P12): `category` (ITEM_CATEGORIES, `material`), `quest_item` (bool).

#### 2.8.3 New record types (examples are normative for field names)

```json
{"schema_version":1,"id":"status.slow","type":"status_effect","display_name":"Slowed","hud_label":"SLOW",
 "stacking":"strongest_wins","duration_s":3.0,"tick_s":0,"magnitude_key":"slow_fraction","default_magnitude":0.3,
 "modifiers":{"slow_fraction":0.3},"tags":["Debuff","Slow"],"hidden":false}
```

The `status_effect` semantic checks: `magnitude_key` must be in `modifiers`; `heal_per_tick` needs `tick_s > 0`; tick-multiple warnings apply. Two hidden statuses exist for tooling only: `status.bot_assist` (`damage_taken_mult` 0.25; P17a) and `status.debug_invulnerable` (`damage_taken_mult` 0; P14). Nothing in normal play applies them.

```json
{"schema_version":1,"id":"loot.ogre_king","type":"loot_table","rolls":0,"entries":[],
 "guaranteed":[{"item":"item.ogre_tusk","count":1},{"item":"item.iron_ingot","count":1}]}
```

Weighted entries are `{item, count, weight}`, rolled `rolls` times with `Sim.rng_for("loot")`.

```json
{"schema_version":1,"id":"npc.elder","type":"npc","role":"talker","display_name":"Elder Maren",
 "scene":"res://scenes/npcs/elder.tscn","height_m":1.7,"capsule_radius_m":0.3,"health":60,"armor":0,
 "walk_speed_mps":1.2,"run_speed_mps":2.8,"flee_trigger_radius_m":0,"protected":true,
 "dialogue":"dialogue.elder","lockable":false,"grants_fury":false,"threat":0.0,"nav_layers":1,"grab_attach":"none"}
```

```json
{"schema_version":1,"id":"dialogue.elder","type":"dialogue","speaker":"Elder Maren",
 "entries":[{"node":"hostile","conditions":[{"type":"flag","flag":"faction.village.hostile"}]},
            {"node":"done","conditions":[{"type":"flag","flag":"quest.village.outcome"}]},
            {"node":"report_cache","conditions":[{"type":"has_item","item":"item.supply_cache","count":1}]},
            {"node":"report_ogre","conditions":[{"type":"killed","targets":["valley.fields.ogre"]}]},
            {"node":"greet","conditions":[]}],
 "nodes":[{"id":"greet","text":"A giant... we want no trouble. Raiders took our winter cache, and an ogre tramples our barley. The bridge stays barred until we are safe.",
   "choices":[
    {"text":"I'll bring back your stolen supplies.","next":"thanks","effects":{"set_flags":{"quest.village.offer":"cache","dialogue.elder.met":true},"outcome":"offer_cache"}},
    {"text":"I'll drive the ogre out of your fields.","next":"thanks","effects":{"set_flags":{"quest.village.offer":"ogre","dialogue.elder.met":true},"outcome":"offer_ogre"}},
    {"text":"[Loom over them] Open the bridge. Now.","next":"cowed","conditions":[{"type":"stage_at_least","stage":2}],
     "effects":{"set_flags":{"quest.village.outcome":"intimidate","faction.village.stood_down":true,"faction.village.gate_open":true,"dialogue.elder.met":true},
                "outcome":"intimidate","xp":40,"learn_abilities":["ability.thunder_roar"],"once_flag":"reward.village.intimidate"}},
    {"text":"Not now.","next":""}]}]}
```

The example is abridged: the nodes `thanks`, `cowed`, `report_cache`, `report_ogre`, `done` and `hostile` are left out here, and P15 authors them (the help reports carry `take_items`, `xp` 120, `give_items` 2 iron, `learn_abilities [ability.ancestral_mend]`, the outcome flags and `once_flag reward.village.help`). The semantic check below requires every referenced node to exist.

A choice's `effects` has the keys `{set_flags, outcome, give_items, take_items, xp, learn_abilities, once_flag, close}`. `xp`, `give_items` and `learn_abilities` require `once_flag`; they are granted only when `try_set_flag(once_flag)` returns true. `learn_abilities` calls `player.progression.learn_ability(id, "reward")` (P12), which adds the id to `known_abilities` and `controller.level_exempt` and auto-slots it.

The `dialogue` semantic checks: node ids are unique; `next` is `""` or an existing node; entry nodes exist; condition dicts are valid; flag ids pass the regex.

```json
{"schema_version":1,"id":"quest.main","type":"quest","display_name":"The Valley of Broken Kings",
 "prototype_pacing":true,"auto_start":true,"start_conditions":[],"abandon_when":null,
 "stages":[{"id":"ogre","objective":"Defeat the ogre blocking the forest trail",
            "complete_when":{"type":"killed","targets":["valley.forest.ogre"]},
            "marker":"valley.marker.ogre_clearing","xp":110,"items":[],"set_flags":{},
            "bot":{"action":"kill","target":"valley.forest.ogre"}}],
 "on_complete_flags":{"slice.completed":true}}
```

A quest with `auto_start: false` starts the first time its `start_conditions` all hold. `abandon_when` (a condition or null) ends an active quest without rewards (`quest.<q>.done = false`, `quest_abandoned`). Branch quests use both (§4.6).

Condition dict shapes:
- `{"type":"flag","flag":id,"equals":v?,"at_least":n?}`
- `{"type":"entered","area":id}`
- `{"type":"killed","targets":[ids]}`
- `{"type":"encounter_cleared","encounter":id}`
- `{"type":"destroyed","world_id":id}`
- `{"type":"has_item","item":id,"count":n}`
- `{"type":"hits_on","targets":[ids],"count":n,"action_kind":k?,"action_id":id?}` (only hits whose action matches the filters count)
- `{"type":"stage_at_least","stage":n}`
- `{"type":"level_at_least","level":n}`
- `{"type":"weapon_equipped","weapon":id}`
- `{"type":"dialogue_outcome","dialogue":id,"outcome":s}`
- `{"type":"all"|"any","of":[conds]}`
- `{"type":"not","of":cond}`

```json
{"schema_version":1,"id":"shrine.kingsfall","type":"shrine","display_name":"Kingsfall Shrine",
 "allows_growth":true,"max_stage":3,"growth_requires_flags":["world.ogre_king.defeated"],
 "checkpoint":true,"rest_heals":true,"first_activation_rest":true,"loadout":true,"attributes":true,"activation_radius_m":14}
```

```json
{"schema_version":1,"id":"progression.default","type":"progression","level_cap":20,
 "xp_to_next":[100,150,200,250,300,350,400,450,500,550,600,650,700,750,800,850,900,950,1000],
 "attribute_points_per_level":3,"talent_points_per_level":1,
 "prototype_xp_label":"Prototype pacing: accelerated quest XP",
 "death_reload_floor":{"health":0.6,"stamina":1.0,"essence":0.5},
 "ability_library":["ability.heavy_footfall","ability.sweeping_blow","ability.stone_skin","ability.crushing_grip",
   "ability.boulder_hurl","ability.runic_bolt","ability.ancestral_mend","ability.thunder_roar","ability.titan_surge"],
 "new_game":{"level":1,"growth_profile":"growth.01","weapon":"weapon.club","ancestry":"ancestry.neutral",
   "slots":["ability.heavy_footfall","ability.sweeping_blow","","","","","",""],"ultimate":"",
   "known_abilities":["ability.heavy_footfall","ability.sweeping_blow"]}}
```

`progression.default` is required (P01 ships it). The semantic checks: `xp_to_next` has 19 entries and is non-decreasing; `slots` has 8 entries.

```json
{"schema_version":1,"id":"level.valley","type":"level","display_name":"Valley of Broken Kings",
 "scene":"res://scenes/world/valley.tscn","start_checkpoint":"valley.shrine.hollow","max_active_enemies":12,
 "lod":{"near_m":40,"mid_m":90,"check_ticks":30,"corpse_free_s":6},
 "render":{"low":{"shadow_distance_m":60,"scenery_visibility_end_m":160,"msaa":0},
           "medium":{"shadow_distance_m":120,"scenery_visibility_end_m":220,"msaa":2}},
 "web_overrides":{"quality":"low","ai_tier1_m":30},
 "districts":[{"id":"hollow","display_name":"Giant's Hollow","min_m":[-200,0,100],"max_m":[-90,0,200]}]}
```

```json
{"schema_version":1,"id":"encounter.forest_wolves_a","type":"encounter","level":"level.valley","district":"forest",
 "center_m":[-142,0,55],"activate_radius_m":55,"deactivate_radius_m":110,"leash_radius_m":50,"alert_group":true,
 "requires_flags":[],"forbids_flags":[],"counts_toward_budget":true,
 "spawns":[{"entity_id":"valley.forest.wolf_a1","definition":"enemy.wolf","position_m":[-150,0,50],"yaw_deg":90,
            "patrol":"valley.patrol.wolves_a","faction":"","commander":false,"ai_enabled":true,"persist_death":true,
            "loot_table":""}]}
```

`definition` must reference an `enemy` or `npc` record. The validator's refs are exact-type, so this is a semantic check against `records` in the GameData post-pass. `leash_radius_m` 0 means no leash (the boss, whose arena gate holds it).

```json
{"schema_version":1,"id":"tutorial.block","type":"tutorial_prompt",
 "text":"Raise your guard with {block}. Block just as the blow lands to parry it.",
 "trigger":{"type":"event","event":"telegraph_started","target":"player","action_tags_any":["Parryable"]},
 "dismiss":{"type":"event","event":"hit_resolved","defender":"player","outcome_in":["blocked","parried"]},
 "requires_flags":[],"min_stage":1,"priority":20,"once":true,"defer_in_combat":false,"sets_flag":"tutorial.block.done"}
```

A prompt fires when its trigger holds and every `requires_flags` flag is truthy and the player is at least `min_stage`. An `entered` trigger is a state, not an edge: it holds while the player is inside the area (`AreaTrigger.player_inside`), so it combines with `min_stage` after growing inside the area.

Event filters by event: `telegraph_started` {`target`, `action_tags_any`, `actor_archetype`}; `hit_resolved` {`defender`, `attacker`, `outcome_in`}; `staggered` {`near_player_m`, `grabbable`}; `ability_started` {`actor`, `action_kind`, `action_id`}; `lock_target_changed` {`actor`, `non_empty`}; `boss_phase_changed` {`phase`}; `interacted` {`interact_prefix`}; others take no filter. `{action}` placeholders resolve through `InputBindings.describe_action` for the last-used device.

#### 2.8.4 Examples of extended existing types

```json
{"schema_version":1,"id":"ability.runic_bolt","type":"action","kind":"ability","display_name":"Runic Bolt","hotbar_label":"BOLT",
 "power":40,"damage_type":"arcane","ability_multiplier":1.0,"stamina_cost":0,"essence_cost":15,"cooldown_s":4,
 "windup_s":0.35,"active_s":0.05,"recovery_s":0.30,"poise_damage":15,"max_hits_per_target":1,
 "tags":["Ability","Magic","Projectile","Ranged"],"category":"magic","uses_weapon":false,"size_policy":"none","crit_eligible":true,
 "hit_shape":"projectile","projectile":{"speed_mps":35,"radius_m":0.3,"range_m":25,"gravity_mps2":0,"aim":"lock_or_camera",
   "launch_offset_m":[0.6,2.9,-0.8],"visual":"bolt"},
 "movement":{"windup_speed_mult":0.4,"active_speed_mult":0.4,"recovery_speed_mult":0.6},"unlock_level":3}
```

```json
{"schema_version":1,"id":"ability.boulder_hurl","type":"action","kind":"ability","display_name":"Boulder Hurl","hotbar_label":"HURL",
 "power":40,"damage_type":"physical","ability_multiplier":1.6,"stamina_cost":15,"cooldown_s":6,
 "windup_s":0.45,"active_s":0.05,"recovery_s":0.45,"poise_damage":30,"max_hits_per_target":1,
 "tags":["Ability","Projectile","Ranged","Unparryable"],"category":"projectile","uses_weapon":false,"size_policy":"attacker_growth",
 "hit_shape":"projectile","projectile":{"speed_mps":28,"radius_m":0.6,"range_m":25,"gravity_mps2":9.8,"aim":"lock_or_camera",
   "arc_to_target":true,"launch_offset_m":[0.7,3.2,-0.6],"visual":"boulder","impact_radius_m":1.5},
 "movement":{"windup_speed_mult":0.2,"active_speed_mult":0.2,"recovery_speed_mult":0.5},"unlock_stage":2,"unlock_level":3}
```

```json
{"schema_version":1,"id":"weapon.club","type":"weapon","family":"club","display_name":"Oak Club",
 "damage_multiplier":1.0,"length_m":1.85,"hit_radius_m":0.45,"scales_with_growth":true,"fit_max_stage":2,
 "visual_shape":"club","light_chain":"ability.light_1","heavy":"ability.heavy_1",
 "upgrade":{"to":"weapon.club_reinforced","cost":[{"item":"item.iron_ingot","count":2}]}}
```

```json
{"schema_version":1,"id":"weapon.tree_oak","type":"weapon","family":"tree","display_name":"Uprooted Oak",
 "damage_multiplier":1.4,"length_m":7.5,"hit_radius_m":0.9,"scales_with_growth":false,"required_stage":3,
 "required_permission":"tree_weapon","tags":["TreeWeapon"],"visual_shape":"tree",
 "light_chain":"ability.tree_light_1","heavy":"ability.tree_heavy"}
```

```json
{"schema_version":1,"id":"prop.gate_practice","type":"prop","category":"structural","display_name":"Practice Gate",
 "height_m":6.0,"health":240,"armor":10,"accepted_attack_categories":["melee","ability","projectile"],"min_growth_stage":1,
 "damage_stages":[{"id":"intact","at_or_below_frac":1.0,"visual":"Intact"},
                  {"id":"cracked","at_or_below_frac":0.5,"visual":"Cracked"},
                  {"id":"broken","at_or_below_frac":0.0,"visual":"Broken","removes_collision":true,"enables_nav_links":true}],
 "xp_reward":20,"on_destroyed_flags":{"world.ruins.gate_broken":true},
 "debris_count":10,"debris_length_m":10,"debris_layout":"line","lockable":true,"grants_fury":false,"threat":0.05,"stability":100.0}
```

```json
{"schema_version":1,"id":"prop.deadfall","type":"prop","category":"breakable","display_name":"Deadfall",
 "height_m":6.0,"health":300,"armor":0,"accepted_attack_categories":["melee","ability"],"min_growth_stage":3,
 "required_tags":["TreeWeapon"],"locked_message":"A wall of fallen trunks. Your hands can't move it - a tree-sized weapon could smash through.",
 "on_destroyed_flags":{"world.forest.deadfall_broken":true},
 "debris_count":12,"debris_length_m":14,"debris_layout":"pile","lockable":false,"grants_fury":false,"threat":0.0,"stability":100.0}
```

```json
{"schema_version":1,"id":"prop.cairn","type":"prop","category":"breakable","display_name":"Watch Cairn",
 "height_m":3.0,"health":60,"armor":0,"accepted_attack_categories":["projectile"],"min_growth_stage":1,
 "locked_message":"Only a hurled boulder can topple the cairn.",
 "debris_count":8,"debris_layout":"pile","lockable":true,"grants_fury":false,"threat":0.05,"stability":100.0}
```

### 2.9 Session, character state and the save schema (P06)

```gdscript
extends Node   # autoload "GameSession" (order: Events, GameData, Settings, WorldState, GameSession, Quests, Sim)
enum Mode { TITLE, SANDBOX, VALLEY }
var mode: int = Mode.SANDBOX; var level_override := ""; var character: Dictionary = {}
var checkpoint_doc: Dictionary = {}; var pending_restore := false; var persist := true
var respawn_id := ""          # the last shrine or waystone reached; where the next reload puts the player
var test_checkpoints := false # a test level opts in to checkpoints outside the Valley
var stats := {"deaths": 0, "checkpoint_loads": 0, "play_time_s": 0.0}
func configure_from_args(args: PackedStringArray) -> void     # once per process
func level_scene_path() -> String
func is_valley() -> bool
func checkpoints_enabled() -> bool          # is_valley() or test_checkpoints
func start_new_valley() -> void
func continue_valley() -> Dictionary        # {"ok","message"}
func start_sandbox() -> void
func go_to_title() -> void
func request_checkpoint(reason: String, respawn: String = "") -> void   # queued; taken in POST_RESOLVE when allowed
func take_checkpoint(reason: String) -> Dictionary   # {"ok","message","deferred"}; immediate when allowed
func checkpoint_blockers() -> PackedStringArray     # [] = allowed, e.g. ["holding"], ["aware:valley.forest.wolf_a1"]
func reload_checkpoint(reason: String) -> void       # reason "death" applies progression.default.death_reload_floor
func on_level_ready(level: Node, player: GiantPlayer) -> void              # main calls after add_child
func snapshot_document(reason: String) -> Dictionary
func reset_for_tests() -> void
func debug_lines() -> PackedStringArray

class_name SaveSlots extends RefCounted
const DIR := "user://saves"; const SLOT := "valley_1"; const SCHEMA_VERSION := 1
static var path_override := ""
static func path() -> String; static func exists() -> bool
static func write(doc: Dictionary) -> Dictionary            # {"ok","message"}; makes the dir; SaveIO.write_json
static func read() -> Dictionary                             # SaveIO.read_json + validate + sanitize; keeps
	# "valley_1.schemaN.rejected.json" for future versions; {"ok","data","source","message","future_version","dropped"}
static func validate(doc: Dictionary) -> PackedStringArray
static func delete_slot() -> void

class_name CharacterState extends RefCounted   # static helpers over a Dictionary
static func new_game(progression: Dictionary, player_record: Dictionary) -> Dictionary
static func from_player_record(player_record: Dictionary) -> Dictionary
static func normalize(d: Dictionary) -> Dictionary     # int() casts, defaults, unknown ids dropped
static func validate(d: Dictionary) -> PackedStringArray
```

Command-line flags: `--mode=title|sandbox|valley`, `--new-game`, `--continue`, `--level=res://….tscn`, `--save-dir=user://…`, `--no-user-settings` (sets `persist` false unless `--save-dir` is given), plus the existing `--autoplay`, `--scenario` and `--capture-dir`. The default mode is `title`. If `--autoplay` or `--scenario` is given without `--mode`, the mode is `sandbox`.

Save document (`user://saves/valley_1.json`):

```json
{"schema_version":1,"build_version":"0.3.0-m4","saved_at_unix":1793836800,"slot":"valley_1","level":"level.valley",
 "checkpoint":{"respawn":"valley.shrine.grove","reason":"quest_stage"},
 "character":{"id":"char.valley_1","definition_id":"player.giant","ancestry":"ancestry.neutral","level":3,"xp":268,
   "unspent_attribute_points":3,"talent_points":2,
   "attributes":{"strength":12,"endurance":13,"dexterity":10,"intellect":11,"willpower":10,"constitution":10},
   "growth_stage":2,"weapon":"weapon.club","weapons_owned":["weapon.club"],
   "loadout":{"slots":["ability.heavy_footfall","ability.sweeping_blow","ability.stone_skin","ability.crushing_grip",
                       "ability.boulder_hurl","ability.runic_bolt","",""],"ultimate":""},
   "known_abilities":["ability.heavy_footfall","ability.sweeping_blow","ability.stone_skin","ability.crushing_grip",
                      "ability.boulder_hurl","ability.runic_bolt"],
   "level_exempt":[],
   "resources":{"health":695.0,"stamina":110.0,"essence":102.0,"fury":0.0}},
 "world":{"schema_version":2,
   "deltas":{"valley.hollow.fence_pen":{"destroyed":true,"damage_stage":1,"health":0.0,"loot_awarded":true},
             "valley.ruins.practice_gate":{"destroyed":false,"damage_stage":1,"health":96.0},
             "valley.forest.wolf_a1":{"killed":true}},
   "inventory":{"item.wood_scrap":1},
   "flags":{"quest.main.stage":"hurl","reward.tutorial.awaken":true,"tutorial.camera.done":true,
            "encounter.forest_wolves_a.cleared":true}},
 "stats":{"deaths":1,"checkpoint_loads":1,"play_time_s":512.4}}
```

`WorldState` v2 (P01) adds:

```gdscript
var flags := {}
func get_flag(id: String, default: Variant = null) -> Variant
func set_flag(id: String, value: Variant) -> void
func try_set_flag(id: String, value: Variant = true) -> bool
func has_flag(id: String) -> bool
func record_killed(entity_id: String) -> void
func is_killed(entity_id: String) -> bool
func record_opened(world_id: String) -> void
func record_damage(world_id: String, damage_stage: int, health: float) -> void   # every persistent prop, on each damaging hit
func remove_item(id: String, count: int) -> bool
```

`to_save_dict` emits v2. `from_save_dict` accepts v1 (migrated with empty flags) and v2. `clear()` clears everything. `add_item` and `remove_item` emit their events.

**Checkpoint rules.**
- Checkpoints exist only when `checkpoints_enabled()`. In the sandbox a shrine still heals on Rest, but nothing is saved.
- Triggers and the respawn point each one sets:

| Trigger | Respawn point after it |
| --- | --- |
| `checkpoint_reached` (a shrine's first activation, a waystone) | that shrine or waystone |
| `shrine_activated` (after its free Rest), `shrine_rested`, and a shrine `interact` (taken before the screen opens) | that shrine |
| `growth_changed` from a shrine | that shrine |
| `boss_defeated` | `valley.shrine.kingsfall` |
| `quest_stage_changed` for `quest.main` | unchanged (the last one reached) |

- A request waits (retried each tick from POST_RESOLVE; later requests replace earlier ones) while `checkpoint_blockers()` is not empty: the player is DEAD, GRABBED or EXECUTING, has `controller.holding_id != ""`, has a modal screen open, or any node in the `enemies` group within 40 m has `brain.aware == true`. The sparring post never sets `aware`.
- Death in the Valley shows "Enter / A: load last checkpoint". The confirm emits `reload_checkpoint_requested("death")`. Then `WorldState.from_save_dict(doc.world)` and `character = doc.character` restore the snapshot, with resources raised to at least the `death_reload_floor` (health 60%, stamina 100%, essence 50%; fury 0; statuses cleared). `pending_restore = true`, `Sim.clear_pending()` runs, and the scene reloads. Continue from the title restores the snapshot exactly.
- `on_level_ready` moves the player to the respawn marker (it also sets `spawn_transform` and the camera yaw), then calls `apply_character_state(character)`.
- New Game clears `WorldState`, builds `character` from `progression.default.new_game`, sets `respawn_id = level.start_checkpoint`, creates a checkpoint document with spawn at the scene's `Player` node, and writes it if `persist` is true.
- A write failure shows a warning in the HUD and play continues.

### 2.10 UI contracts

#### 2.10.1 HUD widgets (`ui/hud/`, registry by P02)

```gdscript
class_name HudWidget extends Control          # widgets find hud.player; method-callable signal handlers only
var hud: Hud
func player() -> GiantPlayer
const WIDGETS := [  # HudWidgets.WIDGETS; missing files skipped
	"res://ui/hud/interact_prompt.gd",   # P02  centre, y +100..+136 below the crosshair
	"res://ui/hud/status_row.gd",        # P03  bottom-left, (16..340, -196..-170)
	"res://ui/hud/checkpoint_toast.gd",  # P06  top-left under the debug panel line, (12..352, 52..80)
	"res://ui/hud/threat_arrows.gd",     # P09  full-rect overlay; draws only edge arrows (24 px inside the edge)
	"res://ui/hud/xp_bar.gd",            # P12  bottom-left, (16..340, -166..-152), "Lv 3  120 / 200 XP"
	"res://ui/hud/ability_notice.gd",    # P12  centre, (-260..260, -250..-212); "New ability: Runic Bolt [6]", out of combat
	"res://ui/hud/boss_bar.gd",          # P11a top-centre, (-320..320, 14..58); Hud hides its target frame for bosses
	"res://ui/hud/quest_tracker.gd",     # P13  top-right, (-356..-16, 14..132)
	"res://ui/hud/objective_marker.gd",  # P13  projected marker + edge clamp + distance
	"res://ui/hud/tutorial_prompt.gd",   # P13  left-centre, (16..396, -70..70 around vertical centre)
]
```

Existing regions stay as they are: resources (16..340, −150..−16), hotbar (−284..284, −92..−16), messages (−300..300, −200..−116), loot label (−260..−16, −40..−16), target frame (−170..170, 14..74), and the debug panel at (12, 86).

#### 2.10.2 Screens (`ui/screens/`; ScreenStack by P03)

```gdscript
class_name UiScreen extends Control
signal closed(result: Dictionary)
var stack: ScreenStack; var args: Dictionary = {}
func pauses_game() -> bool                 # true (title: false)
func first_focus() -> Control              # ScreenStack calls grab_focus() on open (pad navigation)
func on_open() -> void; func on_close() -> void
func cancel() -> void                      # Esc / pad B; default close({"cancelled": true})
func close(result: Dictionary = {}) -> void

class_name ScreenStack extends Control     # child of main's CanvasLayer (layer 10), above Hud; group "screen_stack"
const SCREENS := {"pause": "res://ui/pause_menu.gd", "title": "res://ui/screens/title_screen.gd",
	"shrine": "res://ui/screens/shrine_screen.gd", "dialogue": "res://ui/screens/dialogue_screen.gd",
	"inventory": "res://ui/screens/inventory_screen.gd", "attributes": "res://ui/screens/attributes_screen.gd",
	"forge": "res://ui/screens/forge_screen.gd", "end": "res://ui/screens/end_screen.gd"}
const HOTKEYS := {"inventory": "inventory"}   # input action -> screen, when no modal is open
func open(screen_name: String, args: Dictionary = {}) -> UiScreen
func push(screen: UiScreen) -> void; func pop(screen: UiScreen, result: Dictionary = {}) -> void
func top() -> UiScreen; func is_open(screen_name: String) -> bool; func any_open() -> bool
func open_seconds() -> float               # real time the current pausing screen has been open (bot invariant)
func handle_cancel() -> bool
func close_all() -> void                   # mode changes, the bot after screen-backed actions
static func close_all_static() -> int      # closes every stack in the tree; returns how many screens it closed
```

While any open screen pauses the game: tree paused, `InputRouter` context MENU, mouse visible. When the last one closes: unpause, GAMEPLAY, recapture the mouse (never headless; on the web only after a click). `pause` closes the top screen first; otherwise it opens `pause`. Screens are `PROCESS_MODE_ALWAYS`. `ShrineScreen.TABS` (P05) is pre-declared:

```
["Rest", "res://ui/screens/shrine/rest_tab.gd"]               # P05
["Grow", "res://ui/screens/shrine/grow_tab.gd"]               # P05
["Loadout", "res://ui/screens/shrine/loadout_tab.gd"]         # P12
["Attributes", "res://ui/screens/shrine/attributes_tab.gd"]   # P12
```

### 2.11 Input actions and edges (P01)

| Action | Keyboard / mouse | Pad | Notes |
| --- | --- | --- | --- |
| `inventory` | I | Back | New. Handled by ScreenStack HOTKEYS, not by the router. |
| `debug_grow` | F6 | — | New, debug only. Router edge `debug_grow`, consumed by PlayerGrowth. |
| `debug_shrink` | F7 | — | New, debug only. Router edge `debug_shrink`, consumed by PlayerGrowth. |
| `debug_xp` | F8 | — | New, debug only. Router edge `debug_xp`, consumed by PlayerProgression. |
| `debug_checkpoint` | F9 | — | New, debug only. main.gd `_unhandled_input` emits `reload_checkpoint_requested("debug")`. |
| `interact` | E | X | Existing. Router edge `interact`, now dispatched to components. |

Each new action is added to `InputBindings.ACTIONS`, `LABELS` and `data/input/default_bindings.json`, so it appears in the rebinding grid automatically. Dialogue choices use the 1–4 keys inside the dialogue screen and pad focus plus A; there are no new actions for them.

### 2.12 Scenes and builders

`tools/build_scenes.gd` becomes a runner over an ordered, pre-declared list (P04). Each builder exposes `static func build_all(kit: SceneKit) -> void` and calls `kit.save(root, path)`. The list:

```
player.gd (giant), soldier.gd, wolf.gd, props.gd (fence, dummy), shrine.gd (P05), growth_course.gd (P05),
test_levels.gd (P06), world_props.gd (P08), ranged.gd (P09), test_director.gd (P10a), forge.gd (P12),
heavy.gd (P11a), npcs.gd (P11b), sandbox.gd, valley.gd (P10b), stress.gd (P14), main.gd
```

Order matters because later builders instance earlier scenes. A builder that instances an optional scene (one whose builder belongs to a later or parallel package) checks `ResourceLoader.exists` and prints a "skipped" note instead of failing; the wave merge's full rebuild then includes it. `-- --only=<name>[,<name>]` rebuilds selected builders. `SceneKit` (P04) holds `mats`, `save`, `own`, `scripted`, `n3`, `box`, `cyl`, `sphere`, `static_box`, `hurtbox`, `box_shape`, `arm_basis`, `sign`, `lod_proxy`, the layer constants (`L_WORLD 1, L_ACTORS 2, L_HURTBOX 4, L_DEBRIS 8, L_BREAKABLE 16, L_BLOCKER 32`), `ACTOR_MASK` (51) and `FP_HIDDEN`. `save` writes the scene with `ResourceSaver`, then removes every ` unique_id=<n>` attribute from the text (verified safe on 4.6.3). Materials are additive dictionary entries.

Generated scenes:
- **Existing:** `scenes/player/giant.tscn`, `scenes/enemies/soldier.tscn`, `scenes/world/{practice_dummy,fence_wood,sandbox_arena}.tscn`, `scenes/main.tscn`
- **New enemies and NPCs:** `scenes/enemies/{wolf,archer,mage,ogre,ogre_king,sparring_post}.tscn`, `scenes/npcs/{villager,elder}.tscn`
- **New world:** `scenes/world/{shrine,gate_practice,gate_fortified,tree_small,ancient_oak,deadfall,cart_barricade,cairn,crate,weapon_rack,item_pickup,bush,banner}.tscn` (P05, P08), `scenes/world/forge.tscn` (P12), `scenes/world/valley.tscn` + `scenes/world/valley/<district>.tscn` (P10b)
- **New test scenes:** `scenes/test/{growth_course,flow_test_level,ranged_test,director_test,boss_arena_test,village_test,stress_arena}.tscn`
- **Navmeshes:** `assets/nav/valley_{human,large,giant,small_giant}.res` (compressed)

Required node names:
- Enemy and NPC scenes: `CombatEntity`, `NavAgent`, `Visual/Body`, `Visual/LodProxy` (one box, hidden), `BodyShape`, `Anchors/Torso`, `Hurtboxes/*`; `Anchors/Grab` on every grabbable archetype (the point the hand holds); `Anchors/{KneeL,KneeR}` on the ogre and the Ogre King (lock anchors sharing the one CombatEntity).
- Prop scenes: `CombatEntity`, `Intact`, `Broken` (breakables), one child per `damage_stages[].visual` (structural), `Block*` shapes, `NavLink*` (`NavigationLink3D`, disabled until broken). Cosmetic props: `Visual` only.
- Shrine: `SpawnPoint` (a `CheckpointMarker` whose `checkpoint_id` = the shrine's `world_id`) and `GrowthPad` (`Marker3D`).
- The Valley root contains: `Environment`, `Sun`, `Districts/<id>`, `Navigation/{Human,Large,Giant,SmallGiant}`, `Props`, `Shrines`, `Waystones`, `Markers/<kind>/<marker_id>`, `Markers/Patrol/<route_id>/<n>`, `Triggers/<area_id>`, `Spawns/PlayerSpawn`, `Spawned`, `Player`, `EncounterDirector`, `DebrisPool`, `Kingsfall/{ArenaGate,Pillars}` (P10b), `Kingsfall/BossArena` (P11a).

### 2.13 Test conventions

- Unit tests (`tests/unit`) cover pure objects.
- Integration tests (`tests/integration`) spawn real scenes and step real ticks.
- Slow tests (`tests/slow`) run with `--slow`. The runner stays non-recursive, so each of these three folders is a flat list of files.
- `tests/support/` (P02) provides:
  - `TestWait.until(suite: TestSuite, cond: Callable, max_ticks: int) -> bool`
  - `TestSpawn.enemy(world: Node3D, scene_path: String, pos: Vector3, id: String, ai: bool) -> EnemyActor`
  - `TestSpawn.disable_all_ai(root: Node)`
  - `TestFixtures.record_override(id: String, patch: Dictionary) -> void` (through `GameData.override_record`, so cached ActionDefs refresh) and `TestFixtures.restore_all() -> void`
  - `ResetHooks` (`tests/support/reset_hooks.gd`): two pre-declared lists the runner calls around every test. Entries are `["autoload", "<name>", "<method>"]` (looked up with `get_node_or_null("/root/<name>")`) or `["script", "<path>", "<static method>"]` (loaded if `ResourceLoader.exists`); missing entries are skipped.
    ```gdscript
    const BEFORE_EACH := [["autoload", "GameSession", "reset_for_tests"], ["autoload", "Quests", "reset_for_tests"]]
    const AFTER_EACH := [["script", "res://tests/support/test_fixtures.gd", "restore_all"],
    	["script", "res://ui/screens/screen_stack.gd", "close_all_static"]]
    ```
  - `anchors_expected.gd` (the §1.5 anchor table, read by `test_anchors.gd`)
- The runner order per test: `Sim.reseed` → `ResetHooks.BEFORE_EACH` → `suite.before_each` → the test → `suite.after_each` → `ResetHooks.AFTER_EACH` → logged errors become failures. A screen that `close_all_static` had to close is also reported as a failure ("screen left open"), so tests stay honest.
- Tests never write the player's files. `tools/gd.sh` gives each worktree its own `user://`. Tests use `SaveSlots.path_override = "user://test_saves/valley_1.json"` and `GameSession.persist = false` unless the test is about saving.
- Screens opened in a test must be closed in the same test: Sim is pausable, so `step_ticks` times out while a pausing screen is open.
- Quest and dialogue fixtures are in-memory dictionaries (`TestFixtures`), never shipped data files.

---

## 3. Package specifications

Each package is listed with its goal, owned paths (exclusive within its wave), allowed hotspot edits, design, tests, acceptance (→ gate), and size. "Cross-lane symbols" lists anything a package must reach defensively because its wave partner is adding it (§1.2).

### 3.1 P01 — Core seams: validator registry, events, Sim phases, combat API, statuses, flags

- **Wave / lane:** W0, lane A, parallel with P02. **Depends on:** none. **Milestone:** M2 foundation.
- **Goal:** land the rule, data, event and persistence contracts that later packages need, so that they add data and files rather than editing the core.

**Owned paths**
- Core: `scripts/core/data_validator.gd`, `scripts/core/schemas/{schema_util,action_schema,growth_profile_schema,player_schema,enemy_schema,prop_schema,weapon_schema,item_schema,ancestry_schema,input_bindings_schema,status_effect_schema,progression_schema}.gd`, `scripts/core/game_data.gd`, `scripts/core/events.gd`, `scripts/core/sim.gd`, `scripts/core/world_state.gd`
- Combat: `scripts/combat/{combat_controller,combatant,resource_pool,poise_meter,damage_resolver,action_def,hit_event,combat_entity,combat_rules,targeting_rules,status_def,status_set}.gd`
- Input: `scripts/adapters/{input_bindings,input_router}.gd`, `data/input/default_bindings.json`
- Data: `data/progression/progression_default.json`
- Tests: `tests/unit/{test_schemas_v2,test_status_set,test_controller_v2,test_world_state_v2,test_poise_targeting_v2}.gd`, `tests/integration/test_sim_hooks_statuses.gd`
- Docs: `docs/systems/P01-core-seams.md`

**Hotspot edits:** `project.godot`, adding only `3d_physics/layer_6="blockers"`.

**Design**
1. **Validator split and optional registry** (§2.8.1). `SCHEMA_PATHS` declares a path for every planned record type; `SCHEMAS` and `RECORD_TYPES` are built from the modules that exist. P01 writes the modules for the nine existing types (moved code) plus `status_effect` and `progression`. Every existing error substring stays byte-identical. Tests pin "Duplicate id '", "must be > 0", "unknown value '", "unknown key '", "newer than supported", "stamina_cost: must be >= 0", "iframe_start_s must be < iframe_end_s", "active_s must be > 0", "missing reference '" and "height_m: must be > 0".
2. **Fields and enums.** P01 adds only the fields marked "By P01" in §2.8.2 (`unlock_level`, enemy `xp_reward`, the poise `recovery_mult` and `stagger_vs_larger_s`) and declares every enum value in §2.8.1, so no later package edits an enum. Two semantic warnings: a `light`/`heavy` action without `BasicAttack`, and an action used by an enemy (kind `enemy_attack` or listed in an enemy's attacks; checked in the GameData post-pass) with `windup_s ≥ 0.8` and no `telegraph`. Each schema file starts with the `## @anchor` lines in §1.5.
3. **Events:** every signal in §2.4, grouped by area, plus one `## @anchor Pxx` line per package.
4. **Sim:** hooks, `rng_for`, launch slots, the dead-shooter policy, and the built-in status pass (§2.5). `clear_pending()` also clears launch slots.
5. **CombatController** (§2.6.1): `phase_entered`, `level` / `level_locked` / `level_exempt`, `recovery_scale` (recovery of attack kinds only), `precheck`, `preview_reason`, `force_action`, `enter_grabbed` / `release_grabbed`, the EXECUTING timeline, the GRABBED stagger guard, and the slow multiplier. `preview_reason` must share `_evaluate` (one code path), so the HUD cannot drift from the controller.
6. **Combatant, ResourcePool, PoiseMeter, StatusDef, StatusSet and CombatEntity hooks** (§2.6.2–2.6.3): `faction`, the two poise rules, `heal`, `apply_status`, `tick_statuses`, `died_tick`, on-hit statuses and morale. DamageResolver uses `armor_total` / `damage_taken_mult`. HitEvent gets its new fields, including `area_effect` (§2.6.5). `TargetingRules.player_may_target` (§2.6.4).
7. **GameData:** `get_status`, `records_of_type`, `override_record` / `restore_record` (cache refresh), and the post-pass with anchors.
8. **`WorldState` v2** with flags, killed/opened deltas, `record_damage`, `remove_item`, migration and item events (§2.9).
9. **Input actions** (§2.11). The router emits the edges `debug_grow`, `debug_shrink` and `debug_xp`, in debug builds only. `debug_checkpoint` and `inventory` get no router edge (main.gd and ScreenStack handle them).
10. **`data/progression/progression_default.json`** as in §2.8.3. It must validate before the abilities it names exist, so `ability_library` and `known_abilities` hold only ids that already exist (`ability.heavy_footfall`). P03, P07 and P12 append theirs.

**Tests to add**
- Registry: `RECORD_TYPES` equals the schema modules present; a declared path whose file is missing is skipped with no error; REQUIRED_RECORDS is merged.
- `status_effect` and `progression`: one valid example and one invalid example each for unknown key, bad enum, bad ref and each semantic rule. The two warnings fire on a light action without `BasicAttack` and on an untelegraphed 0.85 s enemy attack.
- StatusSet:
  - refresh does not stack Stone Skin;
  - strongest slow wins and refreshes;
  - HOT heals exactly 100 over 240 ticks and caps at max;
  - an immune tag returns false;
  - expiry emits `status_expired` once;
  - `armor` is never mutated;
  - hidden statuses are left out of `hud_list`.
- Statuses in combat:
  - Stone Skin: synthetic hits on a dummy-like combatant drop from 37 to `round(46 * 100 / 155)` = 30 with +30 armor;
  - Titan Surge: ×1.25 damage and poise, with `add_fury` blocked;
  - `damage_taken_mult` 0 gives 0 health damage and 0 impact stamina.
- Controller:
  - a precheck rejection spends nothing and emits `request_rejected` with the reason;
  - a buffered request re-runs its precheck;
  - `preview_reason` matches `request` for all reason codes;
  - `level_locked`, and an id in `level_exempt` is accepted below its level;
  - `recovery_scale` 0.85 shortens the recovery of light and heavy by 15% and leaves windup, active, block and dodge ticks unchanged;
  - `apply_stagger` while GRABBED returns false;
  - EXECUTING advances and finishes;
  - `force_action` skips costs.
- Poise and targeting:
  - with `recovery_mult` 3.5, poise damage taken in the defender's RECOVERY phase is ×3.5 and in other phases ×1;
  - a poise break by an attacker twice the defender's height staggers for `stagger_vs_larger_s`, a smaller attacker for `stagger_s`;
  - `player_may_target`: ENEMY true; NEUTRAL with no faction (dummy) true; NEUTRAL with faction `village` false; the player false.
- Sim:
  - hooks run in phase/order;
  - `rng_for` streams do not change `Sim.rng` draws, and the 37/66/44 checks still pass;
  - a launch-slot gap;
  - projectile hits from an owner who died last tick still resolve, while same-tick deaths drop them.
- `WorldState` v1 → v2 migration; `try_set_flag` true only once; `flag_changed` emitted on change only; `record_damage` round-trips through `to_save_dict`.
- `ResourcePool.rescale` keeps ratios; `restore` clamps.
- `GameData.override_record` changes the cached ActionDef, and `restore_record` puts it back.

**Acceptance**
- All 1133 existing checks pass unchanged [§15 combat correctness].
- Shipped data validates.
- The new tests pass; the default suite stays under 12 s.
- `--autoplay=120` prints no `ERROR` or `SCRIPT ERROR` line (the error counter arrives with P02).

**Size:** ~3,200 lines (about 700 of them moved).

### 3.2 P02 — Actor seams: player components, enemy base, shared hits, interactables, HUD registry, test support, error counter

- **Wave / lane:** W0, lane B, parallel with P01. **Depends on:** none. **Milestone:** M2 foundation.
- **Goal:** split the three hotspot actors (player, soldier, soldier brain) into components and bases. Remove the duplicated hit building. Add the interaction, checkpoint and HUD-widget seams, the test-support and reset hooks, the error counter for tool runs, and the isolated Godot wrapper.

**Owned paths**
- Player: `scripts/actors/giant_player.gd`, `scripts/actors/player/{player_component,player_motor,player_targeting,player_attack,player_interact}.gd`
- Enemies: `scripts/actors/{soldier_enemy,enemy_actor,attack_runner}.gd`, `scripts/ai/{soldier_brain,enemy_brain}.gd`
- Shared hits: `scripts/combat/{hit_factory,attack_context}.gd`
- World seams: `scripts/world/{interactable,checkpoint_marker}.gd`
- UI: `ui/hud.gd`, `ui/hud/{hud_widget,hud_widgets,interact_prompt}.gd`, `ui/debug_panel.gd`
- Debug: `scripts/debug/{autopilot,error_counter}.gd`
- Tools: `tools/{gd,check,run_tests}.sh`, `.gitignore` (adds `.userdata/`)
- Tests: `tests/test_runner.gd`, `tests/support/**`, `tests/unit/{test_hit_factory,test_anchors,test_error_counter}.gd`, `tests/integration/{test_player_components,test_enemy_base,test_interact_seam,test_reset_hooks}.gd`
- Docs: `docs/systems/P02-actor-seams.md`

**Hotspot edits:** none outside the owned paths. `ui/hud.gd` gets only the widget-loading loop in `_ready` and an `Events.growth_changed → _refresh_mode_label` connection, which fixes the stale "Stage N" label.

**Cross-lane symbols:** see §2.7.1 (P01 adds `controller.level`, `ResourcePool.restore`, `Events.interacted`, `GameData.override_record`, `TargetingRules.player_may_target`, `CombatEntity.faction`, `HitEvent.area_effect`; P02 reaches the first four defensively and uses none of the others).

**Design**
1. GiantPlayer and components exactly as in §2.7.1. The behaviour is identical; this is a pure refactor. Edge-dispatch priorities, the `interact` edge to PlayerInteract, state apply/capture with passthrough keys, `ensure_action`, `set_loadout_slot`, `PlayerMotor.set_speed_mult`, and `current_weapon_scale()` (the profile's `weapon_scale`, 1.0 by default). Components must not reach into each other's private fields; they talk through `player.<component>` public methods. Targeting keeps using `CombatEntity.can_damage` (P03 switches it to `player_may_target`).
2. HitFactory and AttackContext (§2.6.5), and AttackRunner (§2.7.2) with `weapon_arc` and `cylinder_pulse`. `skip_candidate` exists and returns false (P03 fills it in). Both the player and the soldier use them, so `GiantPlayer._queue_hits` and `SoldierEnemy._run_hit_queries` are deleted. Soldier hits now carry `weak_point` and `attacker_growth_stage = 1`; the outcome is identical for the current content. `emit_clank` is true only for the player, so test clank counts stay unchanged.
3. EnemyActor and EnemyBrain (§2.7.3): move every generic piece out of SoldierEnemy and SoldierBrain. Keep the guard in SoldierEnemy via `_is_guarding()`. Add the snapshot keys, the exports (`loot_table`, `home_position`) and the appended AI states. Add the anchors in §1.5 to `enemy_actor.gd`, `enemy_brain.gd`, `attack_runner.gd`, `hit_factory.gd`, `attack_context.gd` and `player_targeting.gd`.
4. Interactable, CheckpointMarker and PlayerInteract (§2.7.4). The interact-prompt widget shows `[E] Talk` using `InputBindings.describe_action("interact", pad)`, with the pad choice = last device (P16 refines this; default keyboard).
5. HUD widget registry (§2.10.1) with `HudWidget`.
6. DebugPanel: duck-type enemies (`has_method("get_debug_info")`), cap enemy lines at 6, and print `debug_lines()` from the group `debug_info_providers`. Autopilot: `_alive_soldier` becomes `_alive_enemy` (duck-typed, enemies group).
7. Test runner: `tests/slow` behind `--slow`, the per-test order in §2.13, `ResetHooks`, and the support helpers. `tests/support/anchors_expected.gd` holds the §1.5 anchor table.
8. **Error counter.** `scripts/debug/error_counter.gd` (`class_name ErrorCounter extends Logger`, the same logic as `TestErrorLogger`, counting errors and warnings separately). Autopilot installs it whenever `--autoplay` or `--scenario` is given. `AUTOPILOT_RESULT` gains `errors`, `warnings` and `error_samples` (the first five), and `_finish` quits with code 1 when `errors > 0` (P14 and P17a add codes 2 and 3).
9. **Tools.** `tools/gd.sh` exports `XDG_DATA_HOME="${GB_USERDATA:-<worktree>/.userdata}"` and runs `${GODOT:-godot} "$@"`. `tools/run_tests.sh` calls it. `tools/check.sh [--slow] [--only=…]` runs the definition-of-done sequence (import → optional build → import → tests → 120 s autoplay) and fails on any step.

**Tests to add**
- Every test name used today keeps passing (68 `p.router`, 15 `p.lock`, `SoldierBrain.AIState.*`, `s.brain.aware`/`s.is_guarding()`).
- HitFactory: same fields for player and soldier hits; crit order unchanged (the 37/66/44 checks).
- Components: a fake component consumes `interact` before the default; `apply_character_state` → `capture_character_state` round-trips unknown keys; registry entries with missing files are skipped without errors.
- Interact seam: the nearest/priority candidate is chosen, `blocked_reason` posts a warning, and nothing happens without a candidate.
- The DebugPanel lists a non-soldier enemy (a stub EnemyActor subclass).
- ResetHooks: present entries are called in order, missing autoloads and scripts are skipped without errors.
- Anchors: every anchor in `anchors_expected.gd` exists in its file.
- ErrorCounter: counts `push_error` and engine errors, counts warnings separately, and `take()` empties it; the autopilot result dictionary contains `errors`.

**Acceptance**
- All existing checks pass [§15 combat, camera], and the obstacle route is unchanged.
- No code duplication remains between the player and soldier hit paths.
- `tools/check.sh` passes, including `--autoplay=120` with exit code 0 and `"errors":0`.

**Size:** ~3,100 lines (about 1,500 moved).

### 3.3 P03 — M2 player abilities, projectiles, hostile-only targeting, hotbar, screen stack

- **Wave / lane:** W1, lane A, parallel with P04. **Depends on:** P01, P02. **Milestone:** M2.
- **Goal:** implement the projectile system and ability effects. Ship Sweeping Blow, Stone Skin, Runic Bolt, Ancestral Mend, Thunder Roar and Titan Surge (Footfall already exists). Make lock, soft targeting and area effects hostile-only. Fix the hotbar's "selected target" and unify its unavailable reasons. Land UiScreen/ScreenStack and turn PauseMenu into a screen.

**Owned paths**
- Projectiles: `scripts/combat/projectile.gd`, `scripts/world/projectile_system.gd`, `scripts/adapters/hit_query_adapter.gd`
- Data: `data/abilities/{sweeping_blow,stone_skin,runic_bolt,ancestral_mend,thunder_roar,titan_surge}.json`, `data/statuses/{stone_skin,slow,mend,titan_surge}.json`
- UI: `ui/hud/status_row.gd`, `ui/screens/{ui_screen,screen_stack,settings_pages}.gd`, `ui/pause_menu.gd`
- Tests: `tests/unit/test_projectile.gd`, `tests/integration/{test_abilities_m2,test_screen_stack,test_hostile_targeting}.gd`
- Docs: `docs/systems/P03-abilities.md`

**Hotspot edits**
- `scripts/core/schemas/action_schema.gd` (anchor P03): the action fields marked P03 in §2.8.2.
- `scripts/actors/attack_runner.gd` (anchor P03): new shapes `sector_pulse` and `projectile`; `none` plus self statuses on `phase_entered`; `radius_by_stage_m`; `ability_effect` emits; `area_effect` on cylinder and sector pulses and on splash; `aim_point`.
- `scripts/combat/hit_factory.gd` and `attack_context.gd` (anchor P03): outgoing multipliers, `on_hit_statuses`, `morale_damage`, weapon tags, projectile fields, `area_effect`, and `skip_candidate` (§2.6.5).
- `scripts/actors/player/player_targeting.gd` (anchor P03): lock candidates and soft targeting use `TargetingRules.player_may_target` instead of `can_damage`.
- `scripts/actors/player/player_attack.gd`: aim resolution and `launch_offset_m × k`.
- `scripts/presentation/actor_rig.gd`: sector-swing pose, plus cast and throw poses for `none` and `projectile` actions; adds the anchors P05, P07 and P08.
- `scripts/presentation/hit_feedback.gd`: sector ring, roar ring, projectile meshes and impacts, heal numbers, status tints.
- `ui/hud.gd`: `_update_slots` calls `controller.preview_reason` and maps codes to text (`Dead`, `Stage N`, `Lv N`, `Cooldown`, `Stamina`, `Essence`, `Fury`, `Busy`, `No target`). Projectile slots get a target line (`→ Soldier` when locked, otherwise `aim`).
- `scripts/main.gd`: build the ScreenStack and route `pause` / Esc through it.
- `data/player/giant.json`: sandbox slots 2 (`sweeping_blow`), 3 (`stone_skin`), 6 (`runic_bolt`), 7 (`ancestral_mend`), 8 (`thunder_roar`), and ultimate `titan_surge`.
- `data/progression/progression_default.json`: append the 6 ids to `ability_library`, append `ability.sweeping_blow` to `new_game.known_abilities`, and set `new_game.slots[1] = "ability.sweeping_blow"`.

**Design**
1. **Projectile** holds pure state: id, owner, action, ctx snapshot, position, velocity, gravity, radius, traveled, range, its own hit registry, and `held_entity_id` (reserved for P07).
2. **ProjectileSystem** (Sim POST_ACTORS, order 100):
   - `instance(tree)` parents the node to the `level_root` node when there is one, otherwise to `tree.current_scene`, so it is freed with the level;
   - integrates each projectile, then `HitQueryAdapter.sweep_sphere(space, owner, from, to, radius)` (new; the same sub-step and occluder rules as `sweep_capsule`);
   - the first world hit stops it;
   - candidates are queued via HitFactory with `attacker_position = impact point`, `from_projectile = true` and `pulse_id = projectile id`;
   - `impact_radius_m > 0` triggers a cylinder pulse at the impact (pulse id = id + 1,000,000) with `area_effect`, using the projectile action's `category`, tags and statuses;
   - visuals are pooled meshes per visual kind;
   - events `projectile_spawned`/`projectile_impact`;
   - removal at range, on world hit, or after 5 s.
3. **Aim.**
   - `lock_or_camera` aims at the locked target's anchor; otherwise a camera-forward ray up to `range_m` gives the aim point.
   - `arc_to_target` solves the low ballistic angle for `speed_mps` and `gravity_mps2`; out-of-range aims clamp to `range_m`.
   - `target` (enemies) fires at `runner.aim_point` when the actor stored one at its aim-lock tick (P09 stores it at `tracking_fraction × windup`), otherwise at the target's anchor at launch. The point is cleared after the launch.
4. **Sector pulse** is a cylinder pulse (radius = `profile.melee_reach_m` when `radius_from: melee_reach`; height = actor height) filtered to |yaw delta| ≤ `sector_deg / 2`, with occlusion from `attack_origin`.
5. **Hostile-only targeting.** Lock candidates and the soft-target scan skip every entity for which `TargetingRules.player_may_target` is false. `HitFactory.skip_candidate` drops such entities from the player's area effects (cylinder pulse, sector pulse, splash, Roar). Direct weapon arcs and direct projectile hits are not filtered, so a deliberate swing still lands (P11b turns that into an offence).
6. **Abilities** (data in §4.7):
   - Sweeping Blow: `sector_pulse`, 120°.
   - Stone Skin: `none` + `status.stone_skin` (unlock level 2).
   - Runic Bolt: magic projectile with Intellect, poise 15 (unlock level 3).
   - Mend: `none` + HOT status (unlock level 4).
   - Roar: `cylinder_pulse` r 6, `morale_damage 20`, `on_hit_statuses` slow (unlock level 4).
   - Titan Surge: `ultimate`, 100 fury, self status (unlock level 4). It gives no invulnerability, and fury gain is 0 while active.
   - Heavy Footfall gains `radius_by_stage_m: [3, 4, 5]`. The test pin `f.radius_m == 3.0` stays true because the base `radius_m` is unchanged.
7. **ScreenStack and UiScreen** per §2.10.2. PauseMenu becomes a UiScreen with the same pages and behaviour, and keeps `open()`, `close()` and `is_open()` as thin wrappers for compatibility. Settings and controls pages move to `settings_pages.gd` for reuse. Existing pause, rebinding and settings tests must still pass, as must `test_mouse_capture` (keep `static func is_capture_click` in main.gd). `close_all_static()` serves the reset hook.

**Tests to add**
- Cooldown spam: each new ability, 100 requests spend once per cooldown [§15 cooldowns].
- Stone Skin refresh: with `TestFixtures.record_override("ability.stone_skin", {"cooldown_s": 0})`, a re-cast at 5 s refreshes the duration and armor stays +30 (no stacking); with the real record, the re-cast at 5 s is rejected with `cooldown` and spends nothing.
- Mend heals 100 in 4 s, capped. Titan Surge with 100 fury: damage on the dummy is ×1.25 and fury doesn't rise while active.
- Projectiles:
  - Runic Bolt uses Intellect (raising Intellect raises damage);
  - stops at a wall;
  - is blocked by a front guard, using the impact-point arc;
  - is not parryable;
  - dedups per projectile;
  - a target that dies mid-cast leaves no stale hits or errors [§15 target death during casting];
  - a splash pulse carries the projectile action's category: on a stub prop that accepts only `projectile`, a `projectile`-category splash deals damage and a `magic` bolt is rejected;
  - an enemy-side `target` aim uses a stored `aim_point` when one is set;
  - no projectile survives a scene reload (the system is freed with the level).
- Sweeping Blow hits two soldiers at ±50° and not one at 90°.
- Thunder Roar slows (`move_speed_multiplier` × 0.7 for 3 s) and calls `on_morale_delta(-20)` on a stub target (a TestSpawn stub EnemyActor that records the call). P04 adds the real-soldier morale test.
- Hostile-only targeting: with only a NEUTRAL stub carrying `faction = "village"` in front of the player, Tab selects nothing and soft targeting does not turn toward it; Footfall, Sweep and Roar beside it queue no hit on it; a direct light swing still hits it; the practice dummy stays lockable.
- The hotbar reason equals `preview_reason` for each state.
- Screen stack: Esc opens pause, closes the top first, and pause blocks gameplay edges; focus is grabbed on open; `close_all_static` closes a leftover screen.

**Acceptance**
- [M2] four abilities (Footfall, Sweep, Stone Skin, Runic Bolt) plus Mend, Roar and Titan Surge usable in the sandbox; hotbar shows cost, cooldown, binding, reason and target.
- [§15] cooldowns and target death during casting.
- All earlier tests still pass.

**Size:** ~3,000 lines.

### 3.4 P04 — Scene kit, wolf archetype, morale and size tactics, actor masks

- **Wave / lane:** W1, lane B, parallel with P03. **Depends on:** P01, P02. **Milestone:** M2.
- **Goal:** split the scene generator into a kit and builders, add the wolf (the second enemy role), and fix morale. Make enemy tactics react to the giant's size (spec §2, §10). Make actors collide with the blockers layer.

**Owned paths**
- Tools: `tools/build_scenes.gd`, `tools/scene_kit.gd`, `tools/builders/{player,soldier,wolf,props,sandbox,main}.gd`
- Enemies: `scripts/actors/wolf_enemy.gd`, `scripts/ai/wolf_brain.gd`, `scripts/presentation/quadruped_rig.gd`
- Data: `data/enemies/{soldier,wolf}.json`, `data/abilities/{wolf_bite,wolf_lunge,soldier_chop}.json`, `data/weapons/wolf_jaws.json`
- Scenes: `scenes/enemies/wolf.tscn` and every existing generated scene (regenerated)
- Tests: `tests/integration/{test_wolf,test_morale_tactics,test_blockers_lod}.gd`, `tests/unit/{test_enemy_brain_v2,test_scene_kit}.gd`
- Docs: `docs/systems/P04-enemy-ai-wolf.md`

**Hotspot edits**
- `scripts/actors/enemy_actor.gd`, `scripts/ai/enemy_brain.gd` (anchor P04); `scripts/actors/soldier_enemy.gd`, `scripts/ai/soldier_brain.gd` (the only editor in W1).
- `scripts/core/schemas/enemy_schema.gd` and `action_schema.gd` (anchor P04): the fields marked P04 in §2.8.2.
- Existing tests that load the sandbox arena (`test_obstacle_route.gd`, `test_ai_and_world_fixes.gd`, and others) switch from disabling only `Soldier01` to `TestSpawn.disable_all_ai(arena)`.

**Design**
1. **Scene kit** (§2.12). Builders are a straight move of the current code. The pre-declared BUILDERS list includes future builders; missing ones are skipped. `--only` is supported. All existing scenes must regenerate equivalently, with identical node names and properties, with two deliberate changes: the giant's and soldier's `collision_mask` becomes `SceneKit.ACTOR_MASK` (51, adding the blockers layer), and soldiers gain `Visual/LodProxy`. `SceneKit.save` strips `unique_id=`, so regenerating twice gives identical files.
2. **Wolf** (`enemy.wolf`): see §4.4 for numbers.
   - Quadruped visual with a QuadrupedRig: body, head, 4 legs, a tail; `get_rig_state` keys as in ActorRig; `Visual/LodProxy`.
   - Bite: `weapon_arc` at head height.
   - Lunge: `motion` (active phase, 9 m/s, at most 5 m) with a line telegraph and 0.9 s recovery. This is the "dodge then punish" window.
   - WolfBrain flanks to a point at ±`flank_angle_deg` from `target_forward`, lunges from 2.5–5.5 m, and uses the shared 2-token pool.
   - `threat` 0.4, `grants_fury` true, `nav_layers` 1.
3. **EnemyActor**:
   - `_custom_movement` implements `motion` for any action (speed along the facing locked at commit; `stop_on_wall` detects slide collisions with WORLD and calls `controller.force_action(on_wall_action)` if one is set);
   - `set_lod_tier` (§2.7.3): tier 1 re-paths at most once per second and only after a path failure (spec §10 "path failures over two seconds trigger a new destination"); tier 2 hides `Visual/Body` and shows `Visual/LodProxy`;
   - `on_morale_delta`, `on_morale_event` (`siege_destroyed` −20), `is_routed`;
   - enemy sight mask = WORLD | BREAKABLE;
   - `NavigationAgent3D.navigation_layers = record.nav_layers`;
   - awareness and ally radii come from `ai`;
   - dead actors stop deciding and stop `move_and_slide` once settled;
   - telegraph emit on WINDUP, with the brain's target as `target_id`.
4. **Morale (spec §10):**
   - ally deaths −10 within the debounce `morale_debounce_s` (2 s);
   - commander death −25 (placement export `commander`; the director sets it from the spawn's `commander` field);
   - morale damage from Roar;
   - flee below `flee_morale` for at least 4 s to a **reachable** point `flee_distance_m` away: the closest point on the actor's own nav layer (`NavigationServer3D.region_get_closest_point` on `LevelRoot.nav_region(layer)` when a level provides one, otherwise on the agent map's region), accepted only if `map_get_path(map, from, point, true, nav_layers)` ends within 1 m of it; without a navmesh, a direct point validated by a ray;
   - regroup above `regroup_morale` only when `has_leader()`: a living `commander` of the same encounter, or, when the encounter authors no commander, a living non-fleeing ally within `leader_radius_m` (20 m);
   - with no leader for `rout_after_s` (20 s) the unit becomes ROUTED: it stays at its flee point, attacks nothing, flees again if hit, and emits `enemy_routed`;
   - morale recovers 2/s after 6 s without new losses (up to the record's start value), so FLEE can end.
5. **Size tactics:**
   - `is_outmatched()` is true when `target_height / own height ≥ tactics.outmatched_ratio`.
   - Soldiers with `formation` take a HOLD stance at the nearest `ai_formation_points` marker within 25 m (matching faction or none), facing the giant with the guard up. With no marker in range they form an ad-hoc line: slots `formation_spacing_m` (3 m) apart, through the encounter's centre (or their own position outside an encounter), perpendicular to the direction to the giant. In HOLD they strike only when the giant's capsule comes within attack range; when `tactics.hold_attack` is set, they use that action instead (P11b's brace counter). They lose morale ×1.5 from Roar and ally deaths.
   - Wolves with `harass` attack only when behind the giant (|facing_deg| > 100) and retreat 8 m after each lunge.
   - The `spread`, `kite` and `retreat` hooks exist for P09.
6. **Telegraph data:** the wolf lunge gets a line telegraph, and the soldier chop (0.85 s windup) a 2.5 m line, so every enemy attack with a windup of 0.8 s or more is telegraphed.
7. **Sandbox:** add 3 wolves (`sandbox.wolf_1..3`) with a patrol in the NW corner around (−45, 0, −45), more than 40 m from every route feature.

**Tests to add**
- Wolf:
  - lunge windup ≥ 0.45 s and recovery ≥ 0.8 s (data check);
  - the lunge moves forward at most 5 m and stops at a wall;
  - with 3 wolves and 2 soldiers on one giant, at most 2 tokens are held [spec §10];
  - flanking reaches a > 60° offset within 6 s.
- Pack targeting: directional switching among 3 wolves respects the 0.20 s repeat debounce and never selects a wolf hidden behind a wall.
- Morale:
  - 3 deaths within 2 s cost only −10;
  - commander −25;
  - Thunder Roar on a real soldier calls `on_morale_delta(-20)`, applied as −30 when the soldier is outmatched;
  - `on_morale_event("siege_destroyed")` costs 20;
  - flee destinations are reachable on the sandbox navmesh (path end within 1 m of the target) [§15 fleeing enemies have a reachable destination];
  - with a living commander, a recovered soldier regroups; with no leader, morale above 45 does not leave FLEE, and the soldier routs after 20 s.
- Size tactics: with the player profile swapped to `growth.02`, soldiers enter HOLD at formation markers; with no marker in 25 m they form a line with 3 m spacing facing the giant; at `growth.01` they approach.
- Blockers and LOD: a CharacterBody3D with `ACTOR_MASK` cannot pass a wall that is only on layer 6, while the camera sweep and an attack sweep pass through it; a tier-2 actor's `can_process()` is false, its body is hidden and its proxy shown; a tier-1 actor re-paths after a path failure at most once per second; the agent's `navigation_layers` equals the record's `nav_layers`.
- Scene kit: `build_scenes --only=wolf` produces the wolf scene; a regenerated scene contains no `unique_id=`; regenerating twice gives byte-identical files.

**Acceptance**
- [M2] two enemy roles (soldier, wolf) with distinct counterplay.
- [§15] fleeing enemies have reachable destinations.
- All earlier tests still pass. Soak `--autoplay=300` in the sandbox (with wolves) exits with 0 errors.

**Size:** ~3,300 lines (about 650 moved).

### 3.5 P05 — Growth stages 1–3, shrines, clearance and the 3-size route

- **Wave / lane:** W2, lane A, parallel with P06. **Depends on:** P01–P04. **Milestone:** M3.
- **Goal:** apply growth safely at shrines (spec §9). Change collision, visuals, movement, camera, reach, unlocks, lock range and navigation profile together. Prove the obstacle route in all three sizes and both camera modes, with no camera penetration and no obscured crosshair.

**Owned paths**
- Growth and shrines: `scripts/actors/player/player_growth.gd`, `scripts/world/shrine.gd`, `scripts/core/schemas/shrine_schema.gd`, `ui/screens/shrine_screen.gd`, `ui/screens/shrine/{rest_tab,grow_tab}.gd`
- Data: `data/growth/growth_0{1,2,3}.json`, `data/shrines/{shrine_hollow,shrine_grove,shrine_thornwick,shrine_kingsfall,shrine_sandbox}.json`
- Tools and scenes: `tools/builders/{shrine,growth_course}.gd`, `scenes/world/shrine.tscn`, `scenes/test/growth_course.tscn`
- Tests: `tests/unit/test_growth_rules.gd`, `tests/integration/{test_growth,test_shrine,test_growth_targeting}.gd`, `tests/slow/test_growth_route.gd`, `tests/support/crosshair_probe.gd`
- Docs: `docs/systems/P05-growth-shrines.md`

**Hotspot edits**
- `scripts/core/schemas/growth_profile_schema.gd` and `player_schema.gd` (anchor P05): the fields in §2.8.2.
- `scripts/presentation/camera_rig.gd`: `apply_profile`; cull render layer 2 in third person while the arm is shorter than 1.2 × the capsule radius; footstep shake.
- `scripts/presentation/actor_rig.gd` (anchor P05): `set_body_scale(k)` and the arc pitch offset from rig state.
- `scripts/actors/player/player_attack.gd`: `player.current_weapon_scale()` and `arc_pitch_offset_deg` in `weapon_segment_global`.
- `scripts/actors/giant_player.gd`: `_read_geometry` applies `current_weapon_scale()`.
- `tools/builders/sandbox.gd`: one sandbox shrine (`shrine.sandbox`, growth allowed to stage 3, no flags) at (−40, 0, 40).

**Cross-lane symbols:** P06 (parallel) adds GameSession. P05 never calls it: shrines only emit events (`checkpoint_reached`, `shrine_activated`, `shrine_rested`, `ui_screen_requested("shrine", …)`, `growth_changed`), which P06 listens to.

**Design**
1. **PlayerGrowth API:**
   ```gdscript
   stage() -> int
   profile_for_stage(n) -> Dictionary
   check_growth(target: int, shrine: Node) -> Dictionary   # {ok, reason, message}
   check_clearance(profile) -> Dictionary
   grow_to(target, shrine, reason := "shrine") -> Dictionary
   debug_set_stage(target) -> Dictionary
   apply_state(state)
   capture_state(out)
   ```
   - `reason` codes: `level` (`controller.level < required_level`), `combat` (`pools.in_combat()`), `busy` (not LOCOMOTION), `holding`, `shrine_max`, `flags`, `clearance`, `no_profile`.
   - Messages are player-facing, for example "Not enough room to grow here. Step into the open." and "Enemies are near. You cannot grow while fighting."
2. **Clearance (before any change):**
   - Capsule shape query with the new radius and height at `global_position + up × (h/2 + 0.05)`, mask WORLD | BREAKABLE | BLOCKER, excluding self.
   - Plus an upward ray from the current head to the new head height.
   - A failure changes nothing and emits `growth_blocked`.
3. **Apply in one tick:**
   - profile, `growth_stage`, `controller.set_growth_stage`;
   - `combatant.set_height` and `growth_bonus` = `resource_bonus`, then `recompute_derived()` (percentages kept);
   - geometry: pivot, arm and weapon × `player.current_weapon_scale()`;
   - `GiantPlayer.nav_layers` (a new property) from the profile;
   - capsule and floor snap; lock range and lock half-angle from the profile (release beyond 1.25 × the current range);
   - `camera_rig.apply_profile` (keeps the zoom fraction, scales the orbit distances by `camera_orbit_scale`, never snaps `current_distance`);
   - `rig.set_body_scale(k)` with `set_weapon_pivot(pivot)` (the rig divides by k);
   - hurtboxes and anchors are re-sized by duplicating shapes from stage-1 base sizes × k. Node scaling is never used for collision;
   - `profile.unlocks` go through `ensure_action` plus auto-slot into the first empty slot, emitting `ability_learned`;
   - `on_profile_changed` to the components; `Events.growth_changed`.
4. **Shrine** (`Interactable`; exports and API in §2.7.4):
   - When the player comes within `activation_radius_m` (14), `activate(player)` runs. The first activation per load performs a free Rest when the record has `first_activation_rest`, then emits `checkpoint_reached(…, "shrine")` and `shrine_activated`.
   - `interact` emits `ui_screen_requested("shrine", {"shrine": self})` (P06 takes a checkpoint on it before the screen opens).
   - `rest(player)` heals all pools, refills Mend-like states, does not clear cooldowns, and emits `shrine_rested`.
   - `can_grow` / `grow` wrap PlayerGrowth for the Grow tab and the bot.
   - The Grow tab lists the target stage, requirements (level, flags, shrine max) and clearance, plus a Grow button; on success it summarises the changes (height, reach, health, new interactions, unlocks, and a weapon that no longer fits).
   - `SpawnPoint` is a CheckpointMarker; `GrowthPad` sits at an open spot.
5. **Debug grow:** F6/F7 edges call `debug_set_stage` (with clearance, no level, combat or shrine gates). It shows "DEBUG: stage N" and logs.
6. **Growth course:** stage-3-sized features, laid out in a line:
   - doorway 5 m wide × 9.5 m tall;
   - low passage 8 m wide × 8.6 m tall × 10 m long;
   - 20° ramp to a 4 m platform;
   - a wall lane 1 m from the path (it forces the camera arm to retract);
   - a "growth trap" alcove with a 6 m ceiling.
7. **Camera.** Footstep shake: on each footfall of the rig's stride at stage ≥ 2 the giant calls `camera_rig.add_shake(profile.footstep_shake)`; `add_shake` is already scaled by the `camera_shake` setting, so 0 disables it. While the third-person arm is shorter than 1.2 × the capsule radius, the camera culls render layer 2 (head, chest, belt), as first person does.
8. **Data:** profile values in §4.8. `dodge_style: sidestep` makes stages 2–3 use a slower lateral rig pose. The timing stays data-driven: same i-frame window, `dodge_distance_m` from the profile.
9. **Crosshair probe** (`tests/support/crosshair_probe.gd`, reused by P07 and P08): each tick, cast the screen-centre ray from the camera; for every `VisualInstance3D` under the player (and under a held entity) that the camera renders (`layers & cull_mask`, visible in tree), transform the ray into the mesh's local space and intersect its AABB. Report the number of consecutive ticks in which the player's own geometry is the first thing the ray meets within 40 m.

**Tests to add**
- Growth 1 → 2 → 3 → 2 (debug): health ratio preserved and never healed (damage to 40%, grow: 40% of the new max); every geometry and camera field updated; `nav_layers` 8 → 4; lock range 35 → 40 → 45.
- Blocked growth in the trap alcove changes **nothing**: every profile-derived field compared before and after [§15 blocked growth leaves old parameters intact].
- No invalid spawn after growth: no overlap query hits, and the player is on the floor within 0.5 s [§15].
- Route (`tests/slow`): stages 1, 2, 3 × third/first person reach every waypoint, with 0 ticks of the camera inside geometry and never more than 30 consecutive ticks of an obscured crosshair [§15 route in all sizes and modes; no persistent camera penetration or obscured crosshair].
- Camera switch at stage 3 preserves position, resources, target and attack timing.
- Downward attacks: at stages 2 and 3, in both camera modes, every hit of the light chain and the heavy reaches a 1.8 m soldier **and** a 0.9 m wolf standing at 0.6 × melee reach in front [§15 downward attacks]. If the wolf case fails, deepen `arc_pitch_offset_deg` in data (up to −10 / −18) until both targets pass, and record the final values in the system doc.
- Lock range per stage: after growth to stage 2, a target at 38 m is lockable, and the lock is released when it moves beyond 50 m.
- Footstep shake: with `camera_shake` 0 the camera's local transform stays identity while walking at stage 3; with 1 it does not.
- Shrine gating: level, combat, flags and max stage. The first activation heals and emits `checkpoint_reached` and `shrine_activated` once per load. Rest heals and emits `shrine_rested`.

**Acceptance**
- [M3] three profiles; safe growth only at a shrine, outside combat.
- [§15 camera/growth] all items above.
- Sandbox shrine works.

**Size:** ~2,900 lines.

### 3.6 P06 — Game session, saves, checkpoints, waystones, title and death flow

- **Wave / lane:** W2, lane B, parallel with P05. **Depends on:** P01–P04. **Milestone:** M3/M4.
- **Goal:** add game modes and a title screen. Build the versioned character and world save with backup recovery, the checkpoint triggers, waystones, snapshot and restore, and death → reload checkpoint (spec §12, §14).

**Owned paths**
- Session and saves: `scripts/core/{game_session,save_slots}.gd`, `scripts/progression/character_state.gd`, `scripts/world/waystone.gd`
- UI: `ui/screens/title_screen.gd`, `ui/hud/checkpoint_toast.gd`
- Tools and scenes: `tools/builders/test_levels.gd`, `scenes/test/flow_test_level.tscn`
- Tests: `tests/unit/{test_save_slots,test_character_state}.gd`, `tests/integration/{test_session_flow,test_checkpoint_triggers}.gd`
- Docs: `docs/systems/P06-session-saves.md`

**Hotspot edits**
- `project.godot`: GameSession autoload after WorldState; version `0.2.0-m3`.
- `scripts/main.gd`: modes, flags, loading label, `on_level_ready`, death branch, F9.
- `ui/pause_menu.gd`: mode-dependent items Resume / Load last checkpoint / Restart sandbox / Settings / Controls / Quit to title / Quit.
- `ui/hud.gd`: death hint text by mode.

**Cross-lane symbols:** P05 (parallel) adds `Shrine` and PlayerGrowth. P06 never references them. It listens to the events P01 declared and finds respawn markers through the `checkpoints` group.

**Design**
1. GameSession, SaveSlots and CharacterState per §2.9. The character dictionary includes `ancestry` (from the player record, `ancestry.neutral`) and `level_exempt`. The title screen offers New Game, Continue (enabled when `SaveSlots.read()` is ok; it shows the read `message`, such as "Recovered the previous save" or "Save from a newer version kept as valley_1.schema2.rejected.json"), Sandbox, Settings, Controls, and Quit (hidden on the web). On the web the Start click captures the mouse. New Game and Continue are disabled, with the note "Valley not built yet", while `level.valley` does not exist (until P10b merges).
2. main.gd builds the level:
   - title mode: TitleScreen only;
   - other modes: a "Loading…" label for one frame, instantiate `GameSession.level_scene_path()`, add the HUD, HitFeedback and DebugPanel, then call `GameSession.on_level_ready(level, player)`.
   - The sandbox keeps its reset behaviour (`WorldState.clear()` plus reload).
   - The Valley never clears WorldState on death; it reloads the checkpoint.
3. **Checkpoint triggers, deferral, respawn point, death floor and the save document:** exactly as §2.9. GameSession connects to `checkpoint_reached`, `shrine_activated`, `shrine_rested`, `ui_screen_requested` (screen `shrine`), `growth_changed`, `boss_defeated` and `quest_stage_changed` (only for `quest.main`), and calls `request_checkpoint`. The queue is drained from a POST_RESOLVE hook (order 200). Nothing is written unless `checkpoints_enabled()` and `persist`.
4. **Waystone** (§2.7.4): a CheckpointMarker that counts as reached when the player is inside `radius_m` and every `requires_flags` flag is truthy; it re-checks on `flag_changed` and at 2 Hz, and emits `checkpoint_reached(…, "waystone")` once per load.
5. **Test level:** a floor, two CheckpointMarkers (`test.cp_a`, `test.cp_b`), a Waystone `test.cp_way` (requires `test.way_open`), a fence (`test.flow_fence`) and a stub enemy spawn point. Its root sets `GameSession.test_checkpoints = true`.

**Tests to add**
- Round trip: character dict → SaveSlots → read is equal (ints are ints; `ancestry` and `level_exempt` kept).
- Corrupt main file → backup is used, and the message contains "corrupt" and "Recovered" [§15 backup recovery].
- A future version is rejected, the rejected copy is kept, and the backup is not overwritten.
- Death → reload restores loadout and world from the checkpoint and the player position at the respawn marker; a checkpoint holding 15% health reloads at 60% with full stamina; Continue from the title restores 15% exactly; the fence broken before the checkpoint stays broken, with no second loot [§15 loot never twice].
- Triggers: each row of the §2.9 trigger table (events emitted synthetically) takes one checkpoint with the right respawn point; `quest_stage_changed` for a quest other than `quest.main` takes none.
- Deferral: a request while EXECUTING waits until LOCOMOTION; with an aware stub enemy 30 m away it waits until that enemy is unaware or more than 40 m away; an unaware enemy 10 m away does not block.
- Sandbox: `shrine_rested` in sandbox mode writes no file.
- Waystone: not reached before `test.way_open` is set; reached once per load after it.
- Title → New Game → `pending_restore` path. Unknown ability ids in a save are dropped with a message.
- `--autoplay` without `--mode` still boots the sandbox, and `test_mouse_capture` still passes.

**Acceptance**
- [M4 save/load] the character, loadout and flags part; the gate part comes in P08.
- [§15] corrupt save → backup with a clear message.
- Title and modes work.
- The sandbox is unchanged when started with flags.

**Size:** ~2,900 lines.

### 3.7 P07 — Grab, throw, Crushing Grip and Boulder Hurl

- **Wave / lane:** W3, lane A, parallel with P08. **Depends on:** P03, P04, P05. **Milestone:** M3.
- **Goal:** implement grab and throw following every spec §8 rule, including the attachment profile. Add Crushing Grip (slot) and Boulder Hurl (stage 2). Together with P03 this completes the eight abilities.

**Owned paths**
- `scripts/actors/player/player_grab.gd`
- `data/abilities/{crushing_grip,boulder_hurl,grab_hold,throw_held}.json`
- Tests: `tests/integration/{test_grab_throw,test_boulder_hurl,test_grab_first_person}.gd`
- Docs: `docs/systems/P07-grab-throw.md`

**Hotspot edits**
- `scripts/core/schemas/action_schema.gd` (anchor P07): `grab`. `enemy_schema.gd` (anchor P07): `grab_attach`.
- `scripts/actors/enemy_actor.gd` (anchor P07): `can_be_grabbed`, `on_grabbed` (suspend AI and movement, collision off, and each tick place the actor so that its `Anchors/Grab` sits at the holder's hand socket with the attachment profile's offset and orientation), `on_released` (validated placement, restore).
- `scripts/presentation/actor_rig.gd` (anchor P07): reach, hold (one pose per attachment profile) and throw poses from rig state `holding`; in first person the hold pose keeps the held body low and to the left of the view.
- `scripts/world/projectile_system.gd` (anchor P07): a `thrown_body` projectile carries `held_entity_id`. It moves the body along the arc, and on impact releases it at a validated position and queues the landing hit on the body.
- `scripts/actors/attack_runner.gd` (anchor P07): the `grab` shape.
- `data/enemies/soldier.json` (`grab_attach: torso_fist`) and `wolf.json` (`scruff`); `tools/builders/{soldier,wolf}.gd`: an `Anchors/Grab` marker (soldier at the chest, wolf at the scruff).
- `data/player/giant.json`: slots 4 (`crushing_grip`) and 5 (`boulder_hurl`).
- `data/progression/progression_default.json`: append both ids to `ability_library`.

**Design**
1. **Eligibility** (`PlayerGrab.find_candidate() -> Dictionary`, also used as the precheck). Checks run in this order and each failure has a reason code:
   - `nothing_in_reach`: no candidate within `grab_reach_m + grab_lunge_m` (horizontal, centre to centre);
   - `no_los`: no line of sight from the eye to the anchor (WORLD | BREAKABLE);
   - `too_tall`: `target.height > 0.5 × player height`;
   - `too_heavy`: `mass_class` above `profile.grab_capacity` (Crushing Grip compares with its `grab.max_mass` and reports `too_heavy_to_crush`);
   - `immune`: `is_immune_to("Grab")`;
   - `no_attach_profile`: the target's `grab_attach` is `none` or is not in `profile.grab_attach`;
   - `not_grabbable`: `actor.can_be_grabbed()` is false (dead, already held, scripted);
   - `not_staggered`: a living target must be STAGGERED (broken poise);
   - eligibility is re-checked on attach, with the distance now limited to `grab_reach_m`.
2. **Inputs:**
   - Interact on a candidate → `request(&"attack", {"action_id": "ability.grab_hold", "precheck": …})`, which runs in EXECUTING (windup 0.25 s, active 0.10 s, recovery 0.20 s, no stamina cost, so it always fits inside a 1.5 s stagger). Its windup lunges toward the target through the motor (the action's `motion`, at most `profile.grab_lunge_m`, stopping at 0.8 × `grab_reach_m`). The first active tick attaches: `controller.enter_grabbed`, `holding_id`, and `grab_started`.
   - While holding, `motor.set_speed_mult(&"grab", 0.6)`. Light or heavy → `ability.throw_held` (projectile, `thrown_body`, category `projectile`, aim like Boulder Hurl, 12 stamina). Interact → drop in front.
   - Crushing Grip slot: if holding, crush the held target; otherwise grab and crush in one action. P = 40 × 1.5, tag `Grab`, `grab.max_mass: small`, then release (`grab.release_after`).
   - Auto-release after 5 s (`timeout`).
3. **Release on:**
   - the holder is staggered or killed (`state_changed`);
   - the target dies (`entity_died`);
   - the scene unloads (`on_exit`);
   - a checkpoint or growth attempt is refused while holding.

   Released targets go to `release_grabbed` → STAGGERED 0.6 s at a position validated by a capsule shape query; fallback is 1.5 m in front of the holder, then the holder's position.
4. **Boulder Hurl** (data in §2.8.4): a `projectile`-category arc (28 m/s, gravity 9.8, range 25 m), poise 30, `impact_radius_m 1.5` (the splash inherits the category), `unlock_stage 2`; the precheck needs `throw_boulder` in `interaction_permissions`. During its windup, PlayerGrab emits `ability_effect` of kind `aim_preview` at the predicted landing point (HitFeedback draws a ground ring).
5. **Stage 3** grabs staggered ogres (`medium`, `two_hand`) but cannot crush them. The boss has `Grab` immunity and `grab_attach: none` (data, P11a).

**Tests to add**
- Every invalid grab spends nothing and returns its reason code [§15 invalid grabs spend nothing]: `nothing_in_reach`, `no_los`, `too_tall`, `too_heavy`, `immune`, `no_attach_profile` (a stub enemy with `grab_attach: none`, and a `two_hand` stub at stage 2), `not_staggered`; Crushing Grip on a staggered `medium` stub at stage 3 gives `too_heavy_to_crush`.
- From melee range, at stages 1, 2 and 3, a heavy that breaks a soldier's poise followed by E grabs it (the lunge covers the knockback; the stagger lasts 1.5 s against the larger attacker).
- An interrupted grab releases both entities [§15]: stagger the holder → target no longer GRABBED and holder not EXECUTING; kill the target → holder `holding_id` cleared.
- Throwing a soldier into a second soldier hits each once and goes through HitFactory. The landing position is never inside geometry.
- Crushing Grip damage = round(40 × 1.15 × 1.5 vs armor 15) and the target is released.
- Boulder Hurl is locked at stage 1 ("Stage 2") and hits a target 20 m away at stage 2. Splash hits 2 wolves. It destroys a cairn stub (a prop that accepts only `projectile`), while a light attack and a Runic Bolt on the same cairn deal no damage.
- Stage 3 can grab a staggered ogre stub (`mass medium`, `two_hand`); stage 2 cannot.
- First person while holding a soldier, turning 360°: the crosshair probe never reports more than 30 consecutive obscured ticks.
- Scene unload while holding: no errors, target released.

**Acceptance**
- [M3] grab/throw.
- [M4] eight abilities.
- [§15] invalid grabs spend nothing; interrupted grabs release both.

**Size:** ~2,600 lines.

### 3.8 P08 — World props (cosmetic, breakable, structural), weapons with fit stages, equipment, nav links, pickups and persistence

- **Wave / lane:** W3, lane B, parallel with P07. **Depends on:** P03, P04, P05, P06. **Milestone:** M3/M4.
- **Goal:** build the selective-destruction set for the Valley in all three spec categories: cosmetic bushes and banners, breakable trees, deadfall, barricade, cairn and crates, and the structural practice gate with damage stages; plus the locked fortified gate. Add weapons (sword, hammer, tree) with fit stages and equipment, the uprootable oak, weapon racks and item pickups. Prove that a cracked gate survives save/load.

**Owned paths**
- World scripts: `scripts/world/{breakable_prop,debris_pool,cosmetic_prop,uproot_tree,weapon_rack,item_pickup}.gd`, `scripts/actors/player/player_equipment.gd`
- Prop data: `data/props/{gate_practice,gate_fortified,tree_small,ancient_oak,deadfall,cart_barricade,cairn,crate,bush,banner}.json`
- Weapon data: `data/weapons/{sword,hammer,tree_oak,club_reinforced,sword_reinforced,hammer_reinforced}.json`, `data/weapons/club.json`
- Moveset data: `data/abilities/{sword_light_1,sword_light_2,sword_light_3,sword_heavy,hammer_light_1,hammer_light_2,hammer_heavy,tree_light_1,tree_light_2,tree_heavy}.json`
- Item data: `data/items/iron_ingot.json`
- Tools and scenes: `tools/builders/world_props.gd`, `scenes/world/{gate_practice,gate_fortified,tree_small,ancient_oak,deadfall,cart_barricade,cairn,crate,weapon_rack,item_pickup,bush,banner}.tscn`
- Tests: `tests/integration/{test_world_props,test_weapons,test_save_load_world,test_cosmetic_structural}.gd`
- Docs: `docs/systems/P08-world-weapons.md`

**Hotspot edits**
- `scripts/core/schemas/prop_schema.gd` and `weapon_schema.gd` (anchor P08): the fields in §2.8.2.
- `scripts/actors/giant_player.gd`: `current_weapon_scale()` returns `equipment.effective_weapon_scale()` when equipment exists.
- `scripts/presentation/actor_rig.gd` (anchor P08): weapon visual swap support.
- `tools/builders/sandbox.gd`: a practice gate (`sandbox.gate_01`), a sword rack and a hammer rack, an ancient oak (`sandbox.oak_01`) near the shrine, and two bushes.
- P05's stage-3 test setups that swing the club (`tests/integration/test_growth.gd`, `tests/slow/test_growth_route.gd`) gain `TestFixtures.record_override("weapon.club", {"fit_max_stage": 3})`, so they keep testing full-scale reach.

**Design**
1. **BreakableProp** (breakable and structural):
   - debris layout from data (`debris_length_m`, `debris_layout`);
   - on break and on load-broken, enables child `NavigationLink3D`s named `NavLink*`;
   - `locked_message` for player hits rejected for category, `required_tags`, stage or permission (throttled to one per 3 s);
   - `protected` → IMMUNE "protected" with the message;
   - `xp_reward` → `Events.xp_award_requested` when the player destroys it;
   - `on_destroyed_flags` → `WorldState.try_set_flag`;
   - `open_when_flag` → `force_open(reason)` on `flag_changed` or on `_ready` (broken state without debris, loot or XP; nav links enabled; delta `opened`; emits `object_opened`).
   - **Damage stages** (`structural`): after each damaging hit, the current stage is the last entry whose `at_or_below_frac` is at least the health fraction. On a change it shows that stage's visual and hides the others, removes collision when `removes_collision`, enables nav links when `enables_nav_links`, and emits `object_stage_changed`. The final stage is the destruction (one `object_destroyed`, loot and XP once).
   - **Persistence:** every damaging hit calls `WorldState.record_damage(world_id, stage, health)`. `_ready` restores health and stage from the delta (visual, collision and nav links, with no events, loot or XP). This also fixes the M1 limitation "fence partial damage is not persisted".
   - The fortified gate is `structural` with one stage and `min_growth_stage 4`, so in the slice it is always IMMUNE with its locked message.
2. **CosmeticProp** (`category: cosmetic`; bush, banner): no CombatEntity and never saved. It reacts to `area_pulse` and to `ability_effect` sectors and roars whose area reaches it, and to actors passing within `react_radius_m` (checked at 5 Hz): a wobble tween, or a 4 s flatten for a stage-2+ giant's step. `react_count` counts reactions for tests.
3. **UprootTree** (`prop.ancient_oak`): requires `profile.interaction_permissions` to contain `tree_weapon`; otherwise "Too small to uproot this oak (stage 3)". `interact` → `equipment.grant_weapon("weapon.tree_oak", true)`, then `record_destroyed`, the flag `world.tree_weapon_taken`, and the oak hidden with collision off. **WeaponRack** grants and equips its weapon once per `world_id` (delta `taken`). **ItemPickup** grants items and an optional flag once (delta `taken`) and hides itself.
4. **PlayerEquipment:**
   ```gdscript
   equip_weapon(id) -> Dictionary      # {ok, reason}
   grant_weapon(id, equip) -> void
   owned() -> PackedStringArray
   effective_weapon_scale() -> float   # the weapon_scale of profile min(stage, fit_max_stage); fixed-size weapons undo k
   is_too_small() -> bool              # stage > fit_max_stage
   apply_state(state)
   capture_state(out)                  # weapon, weapons_owned
   ```
   - LOCOMOTION only. Checks `required_stage` and `required_permission`.
   - Sets `player.weapon`; loads `light_chain`/`heavy` into `controller.loadout` (falling back to the record's defaults) and calls `ensure_action`.
   - Rebuilds the visual under `Visual/Body/ShoulderR/Weapon` (hides the generated `Club`). The node scale is `effective_weapon_scale() / k`, so a capped weapon looks as small as it hits and the tree keeps its real size. The tree's canopy mesh is on render layer 2 and its trunk is offset to the right of the view centre in first person.
   - When growth or equipping puts the stage above `fit_max_stage`, the HUD warns "Your <weapon> is too small for you now. Reforge it at a forge to make it fit.", and the inventory marks it "(too small)".
   - Notifies `on_weapon_changed` and emits `weapon_equipped`.
5. **Weapons** (§4.7): club, sword and hammer fit stage 2, their reinforced variants fit stage 3, and each base weapon has an `upgrade` to its reinforced variant (cost 2 iron ingots; P12 implements the forge). Every light and heavy moveset carries `BasicAttack`, so fury works with every weapon. Sword: faster chain, lower poise. Hammer: slower, a 2-hit chain, high poise. Tree: wide sweeps, 7.5 m long, fixed size, `TreeWeapon` tag, ×1.4, stage 3 only.
6. **Props** (§4.3): practice gate (structural, any stage, data in §2.8.4); fortified gate (stage 4; locked message); deadfall (TreeWeapon only); cart barricade (stage 2; `on_destroyed_flags` sets outcome `force` and `faction.village.hostile`; `open_when_flag` is `faction.village.gate_open`); cairn (`projectile` category only, lockable, locked message); crates (inline `loot` now; P12 switches them to `loot_table`); bush and banner (cosmetic).

**Tests to add**
- Fortified gate at stage 3: IMMUNE plus the locked message, no damage.
- The deadfall ignores club hits and breaks with tree hits, setting `world.forest.deadfall_broken`.
- Barricade: `force_open` via flag gives no loot or XP, and loads open; smashing it sets both flags.
- A broken gate enables its nav link: path across shorter than 2 × direct distance; disabled before.
- Structural stages: the practice gate shows `Cracked` at ≤ 50% health with its collision kept, then `Broken` at 0 with collision removed and the nav link enabled; `object_stage_changed` fires once per stage; destruction XP and loot are awarded once.
- Save/load (cross-package M3/M4 gate):
  - crack the practice gate to 40% health, grow to stage 2, equip the sword, set a flag, take a checkpoint, reload the scene through GameSession;
  - the gate is still cracked at 40%, stage 2, sword equipped, loadout and flag restored;
  - break the gate after the reload: XP and loot once; reload again: still broken, nothing awarded twice [§15 save/load restores character, loadout, quest flags and gate state; loot never twice].
- Cosmetic: a Footfall beside a bush makes it react (`react_count` 1) and leaves `WorldState.deltas` unchanged; an attack sweep through a bush queues no hit.
- Weapons:
  - equipping is refused mid-swing; the tree is refused below stage 3;
  - the weapon visual length matches `weapon_length` within 2% at stages 1–3, and the swing reaches the expected distance per stage;
  - an unreforged sword (fit 2) at stage 3 keeps its stage-2 length, the HUD warns, and its heavy still lands on a soldier at the giant's feet; `weapon.sword_reinforced` scales to stage 3;
  - the sword's first light on a soldier grants 4 fury.
- First person at stage 3 with the sword, the hammer and the tree in turn, during a light chain: the crosshair probe never reports more than 30 consecutive obscured ticks.

**Acceptance**
- [M3] persistent gate (with damage stages).
- [M4] three weapons plus the tree at stage 3.
- [§15] save/load and loot-once items.

**Size:** ~3,300 lines.

### 3.9 P09 — Archer, mage, telegraph visuals and threat arrows

- **Wave / lane:** W4, lane A, parallel with P10a. **Depends on:** P03, P04, P07. **Milestone:** M4.
- **Goal:** the two ranged roles with their spec counterplay ("pressure or throw" for archers, "interrupt or evade" for mages), committed aim, and the readability layer of decision 25 (filling telegraph decals, aim lines, screen-edge threat arrows, a ranged token pool).

**Owned paths**
- `scripts/actors/{archer_enemy,mage_enemy}.gd`, `scripts/ai/{archer_brain,mage_brain}.gd`
- `data/enemies/{archer,mage}.json`, `data/abilities/{archer_shot,archer_kick,mage_slow_bolt,mage_barrier,mage_staff}.json`, `data/statuses/barrier.json`, `data/weapons/{archer_bow,mage_staff}.json`
- `tools/builders/ranged.gd`, `scenes/enemies/{archer,mage}.tscn`, `scenes/test/ranged_test.tscn`
- `scripts/presentation/telegraph_visuals.gd`, `ui/hud/threat_arrows.gd`
- Tests: `tests/integration/{test_archer,test_mage,test_telegraphs}.gd`, `tests/unit/test_ranged_brains.gd`
- Docs: `docs/systems/P09-ranged-enemies.md`

**Hotspot edits**
- `scripts/main.gd` (one line: add a `TelegraphVisuals` node beside HitFeedback).
- `scripts/ai/enemy_brain.gd` and `scripts/actors/enemy_actor.gd` (anchor P09): `current_aim_point()` and the shared aim-lock helper for ranged actors.
- `scripts/core/schemas/action_schema.gd` (anchor P09): `targets_ally`. `scripts/core/game_data.gd` (post-pass anchor P09): the "enemy action with a windup ≥ 0.8 s needs a telegraph" check becomes an error.

**Design**
1. **Committed aim** (decision 24). At `tracking_fraction × windup` ticks (0.6 for the shot and the slow bolt) a ranged actor stores the target's anchor position in `runner.aim_point` and stops turning. The projectile flies to that point (P03's `target` aim). `current_aim_point()` returns the live anchor before the lock and the stored point after it, for the aim line.
2. **ArcherBrain:**
   - keeps `preferred_min_m`–`preferred_max_m` (12–20; ×1.3 and spread 10 m when outmatched, so 15.6–26 m);
   - `ai.sight_range_m` is 32 (a role override of the spec's 25 m), so an archer at the top of its outmatched band still sees the giant;
   - picks a position from `ai_elevation_points`/`ai_cover_points` within `cover_search_radius_m` that has LOS to the target and lies in the band, rejecting points within `spread_m` of another ranged ally (allies cached at 1 Hz from `ranged_enemies` within 40 m); otherwise it uses a ring point;
   - retreats when the giant is closer than the minimum and kicks under 2.5 m;
   - shoots only with LOS, in band, with `Sim.request_launch_slot(target, self, launch_gap_s × 60)` (`launch_gap_s` 1.0), and while holding a ranged token (`target_id + ":ranged"`, at most 2 holders), released after the shot's recovery;
   - the draw (windup 0.9 s) shows a line telegraph from the bow to the aim point.
3. **MageBrain:**
   - band 10–16 m;
   - slow bolt: arcane projectile, `on_hit_statuses` slow 30% for 3 s, line telegraph to the aim point during its 1.0 s windup, aim lock at 60%;
   - barrier: `targets_ally`, applies `status.barrier` (×0.5 damage taken, 5 s) on the most hurt ally in 12 m, or on itself; circle telegraph, 1.2 s windup, 30 essence, 10 s cooldown;
   - staff strike when close;
   - poise 25, so heavies, Footfall, throws, Boulder Hurl and Runic Bolt (poise 15 × size scale 2 = 30) interrupt its casts (hard stagger). Its essence comes from data, and it casts with kind `ability` (CASTING).
   - Both records: `grants_fury` true, `threat` 0.7 (archer) / 0.8 (mage), `grab_attach: torso_fist` with an `Anchors/Grab` marker, `Visual/LodProxy`, `nav_layers` 1.
4. **TelegraphVisuals:** flat discs (circle), lines and cones listening to `telegraph_started`. Each decal fills from 0 to 100% over `duration_s` and flashes during the active phase. Line telegraphs of projectile actions follow `actor.current_aim_point()` until the lock, then freeze. A decal is removed when its actor leaves WINDUP/ACTIVE.
5. **Threat arrows** (HUD widget): for every live telegraph whose `target_id` is `player` and whose origin is behind the camera or outside the viewport, an arrow at the screen edge points toward the origin, brightening as the windup completes; it disappears with the telegraph.

**Tests to add**
- The archer settles in the band (12–20 m) and at an elevation marker when one exists.
- An outmatched archer (player at stage 2) holds its 15.6–26 m band for 10 s without falling back to ALERT.
- Two archers never launch on the same target within 1.0 s (launch slots) [spec §10 staggered launches]; with three ranged enemies on one target, at most two hold ranged tokens.
- Arrows are blocked by the guard, dodged by i-frames, and stop at walls.
- Committed aim: a player who steps 4 m sideways after the aim lock is missed by the arrow; a player who stands still is hit.
- A throw (P07) and Boulder Hurl interrupt or kill archers.
- Mage:
  - slow bolt slows for 3 s; a second slow refreshes (strongest wins);
  - a heavy hit during the windup cancels the cast with no hit and no cost refund;
  - a Runic Bolt fired 0.1 s after the slow bolt's windup starts staggers the mage before release (0.35 s + 16 m / 35 m/s ≈ 0.81 s < 1.0 s);
  - barrier halves damage on its ally;
  - target death mid-cast is handled [§15].
- Telegraphs: every action an enemy uses with a windup of 0.8 s or more in shipped data has a telegraph (validator error); a decal's fill goes from 0 to 1 over the windup; a telegraph from behind the player shows a threat arrow and one in front does not.

**Acceptance:** [M4 five roles] archer and mage; [§15] target death during casting; decision 24 and 25 in place.

**Size:** ~2,800 lines.

### 3.10 P10a — Level framework: LevelRoot, area triggers, markers, EncounterDirector

- **Wave / lane:** W4, lane B, parallel with P09. **Depends on:** P04, P06. **Milestone:** M4.
- **Goal:** the level-side systems the Valley needs, proven on a small test level before the Valley exists: LevelRoot, AreaTriggers, LevelMarkers, and an EncounterDirector with budget, LOD, leash, alert groups, despawn/respawn and kill persistence. Also the `level` and `encounter` schemas.

**Owned paths**
- `scripts/world/{level_root,encounter_director,area_trigger,level_marker}.gd`
- `scripts/core/schemas/{level_schema,encounter_schema}.gd`
- `tools/builders/test_director.gd`, `scenes/test/director_test.tscn`
- Tests: `tests/integration/{test_encounter_director,test_level_root}.gd`, `tests/unit/test_encounter_schema.gd`
- Docs: `docs/systems/P10a-level-framework.md`

**Hotspot edits**
- `scripts/core/game_data.gd` (post-pass anchor P10a): the "Duplicate spawn entity_id '…'" check across encounters, and the check that `definition` is an `enemy` or `npc` record.
- `scripts/actors/enemy_actor.gd` and `scripts/ai/enemy_brain.gd` (anchor P10a): `begin_leash_return()` and the RETURN state (walk home, ignore targets, regain full health after 6 s outside the leash).

**Design**
1. **LevelRoot** (§2.7.4): lookups built once at `_ready` from the groups; `patrol_route(id)` returns `Markers/Patrol/<id>`; `nav_region(layer)` returns the region RID for that nav layer; it is the parent the ProjectileSystem looks for.
2. **AreaTrigger and LevelMarker** (§2.7.4).
3. **EncounterDirector** (Sim PRE_ACTORS, order 10):
   - every `lod.check_ticks` (30): encounters in id order that are not cleared and whose flags allow (`requires_flags` all truthy, `forbids_flags` none) activate when the player is within `activate_radius_m` and the budget (`max_active_enemies` 12) allows;
   - spawning, before the actor enters the tree: instance `definition.scene`, set `entity_id`, `ai_enabled`, `patrol_route` (absolute path of the route node), `faction`, `encounter_id`, `persist_death`, `commander`, `loot_table`, `home_position`, position and yaw; skip ids `WorldState.is_killed`; parent under `LevelRoot/Spawned`;
   - deactivation (living members freed, not killed) happens beyond `deactivate_radius_m` when no member has been aware for 10 s;
   - **leash**: a member farther than `leash_radius_m` from its encounter's centre gets `begin_leash_return()` and an `encounter_leashed` event; it can engage again once back inside;
   - LOD tiers by distance (near ≤ 40 m tier 0, ≤ 90 m tier 1, else tier 2); engaged members stay tier 0;
   - alert groups share awareness;
   - kills → `record_killed` and corpse freed after `corpse_free_s`;
   - an encounter is cleared when every member is dead or routed (`enemy_routed`): `set_flag("encounter.<id>.cleared", true)` and `encounter_cleared` once; a cleared encounter never activates again;
   - NPC spawns do not count toward the budget;
   - `despawn(entity_id)` removes a living member without recording a kill; it respawns at home on the next activation.
4. **Schemas:** `level` (with `lod`, `render`, `web_overrides`, `districts`) and `encounter` (with `leash_radius_m`, per-spawn `commander` and `loot_table`) exactly as in §2.8.3.
5. **`director_test.tscn`:** a 120 × 120 m floor with a baked human nav region, three encounters (wolves; soldiers with a commander; a 14-member budget test), a patrol route, formation markers and two area triggers.

**Tests to add**
- Activation and deactivation radii; the budget of 12 is never exceeded (14 requested).
- Killed members don't respawn after a reload; a cleared encounter never activates again; routed members count toward clearing.
- Leash: a soldier lured 60 m out of a 40 m leash walks home, ignores the player while returning, and is back at full health 6 s later.
- LOD tiers are set by distance (a tier-2 actor's `can_process()` is false).
- A spawned soldier's `patrol_route` resolves and it collects all 3 route points.
- `encounter.<id>.cleared` is set once and `encounter_cleared` emitted once.
- Validator: duplicate spawn ids across encounters, and a `definition` that is not an enemy or npc, are errors.
- `despawn` followed by re-activation respawns the member at home.

**Acceptance**
- [§16] active-enemy budget and LOD in place.
- The director, leash and persistence work on the test level.

**Size:** ~2,000 lines.

### 3.11 P10b — Valley world: layout, offline navigation, Valley scene

- **Wave / lane:** W5, lane A, parallel with P12. **Depends on:** P05, P06, P08, P10a. **Milestone:** M4.
- **Goal:** build the 400 × 400 m Valley blockout (§4) from a layout table, with navigation baked offline in four layers and nav links. The world can be walked from New Game.

**Owned paths**
- Layout and builder: `tools/data/valley_layout.json`, `tools/builders/valley.gd`
- Scenes and nav: `scenes/world/valley.tscn`, `scenes/world/valley/*.tscn`, `assets/nav/valley_{human,large,giant,small_giant}.res`
- Data: `data/world/{level_valley,encounters_forest,encounters_road}.json`
- Tests: `tests/slow/test_valley_smoke.gd`
- Docs: `docs/systems/P10b-valley-world.md`

**Hotspot edits:** none.

**Design**
1. **Layout table** (all coordinates in §4). Sections: `districts`, `ground`, `cliffs`, `blockers`, `water`, `roads`, `houses`, `walls`, `platforms` (+ ramps), `scenery_trees` (positions and radii), `props` (scene key, world id, position, yaw, `nav_link {from, to, layers}`), `shrines` (record, world id, position, yaw), `waystones` (id, position, radius, `requires_flags`), `dummies` (entity id, position), `markers` (id, kind, position, faction), `patrols` (id, points), `triggers` (area id, size, position), `signs` (text, position).
2. **Scope: blockout.** P10b builds every element that collision, navigation and clearance depend on: ground, cliffs, the river with its banks and blocker walls, the bridge, roads, cottage boxes, the palisade, ruins walls and wall walks, ledges, the ravine, the arena with antechamber, gate and four pillars; every prop, shrine, waystone, dummy, marker and trigger; and landmark boxes (watchtower, citadel, crown altar). Decorative dressing (scenery density, barley rows, cosmetic props, extra signs) belongs to P15, which owns the layout afterwards.
3. **Builder:**
   - One StaticBody3D per district with many CollisionShape3D children.
   - Visuals as one `MultiMeshInstance3D` per (district, material) using unit box and cylinder meshes, with transforms carrying the scale. Target: at most about 250 draw calls in any view.
   - `visibility_range_end` 220 m on scenery; environment fog from 120 m.
   - Props instanced from P08 scenes with `world_id` set; shrines from P05; waystones as P06 `Waystone` nodes; dummies with `entity_id`. Forges use `scenes/world/forge.tscn` only if it exists (P12 is the parallel lane); otherwise the builder prints a "skipped" note, and the wave merge's full rebuild adds them.
   - Navigation for each of the four layers (§2.2) baked offline: `NavigationMeshSourceGeometryData3D.add_faces` from the same box and cylinder list as the collision, with blocking props (gates, barricade, deadfall) and blocker walls as obstacles. Saved compressed to `assets/nav/`, so the source of navigation and collision is one table.
   - The scene has four `NavigationRegion3D`s with layers 1/2/4/8; `NavLink`s go under the blocking props.
   - Kingsfall gets the arena walls, `Kingsfall/ArenaGate` (a StaticBody3D on WORLD, hidden and with collision disabled; P11a drives it), `Kingsfall/Pillars` (four 3 × 3 × 15 m WORLD boxes at radius 22 m), the trigger `valley.area.arena_engage` and the marker `valley.marker.arena_center`.
   - The root carries `LevelRoot` (`level_id = level.valley`) and the `EncounterDirector`. The district sub-scenes are saved first, then instanced by the root scene.
4. **Initial data:** `level.valley` (§2.8.3) and the encounters that only need existing archetypes: `forest_wolves_a`, `forest_hunters` and `road_patrol` (§4.4). P11a adds the ogre encounters and P11b the village; P15 owns all encounter files afterwards.

**Tests to add**
- Valley smoke (`tests/slow`):
  - loads in under 3 s headless; node count reported;
  - a small-giant-layer (8) path from the spawn to the Grove Shrine, and giant-layer (4) paths from the Grove to each shrine, waystone and critical-path objective marker in §4.2 (with the barricade, practice-gate and deadfall links treated as open);
  - the human-layer path across the river exists only over the bridge, and only after the barricade link is enabled;
  - the player cannot cross the river away from the bridge: a body with the stage-3 capsule and `ACTOR_MASK`, pushed east at three points along the west bank, stays west of x = 100;
  - every shrine pad, waystone and checkpoint marker has stage-3 clearance (capsule query passes);
  - each navmesh file is at most 100 KB, and loading the Valley performs no navigation bake.

**Acceptance**
- [M4] Valley walkable: New Game → explore all districts at stage 1 except behind gates.
- No runtime bake; navmesh files under 100 KB each.

**Size:** ~2,600 lines (including about 600 lines of layout JSON).

### 3.12 P11a — Ogre, Ogre King boss and arena

- **Wave / lane:** W6, lane A, parallel with P13. **Depends on:** P07, P10b (and through them P04, P09, P10a). **Milestone:** M4.
- **Goal:** the fifth role (ogre), and a boss that reads as a boss: 8.5 m tall, strictly alternating phase 1, a telegraphed phase change, a charge that ends against stone with a punishable recovery, phases that happen exactly once, lock framing on a low anchor, and a safe arena.

**Owned paths**
- Actors and AI: `scripts/actors/{ogre_enemy,ogre_boss}.gd`, `scripts/ai/{ogre_brain,ogre_boss_brain}.gd`
- World: `scripts/world/boss_arena.gd`
- Data: `data/enemies/{ogre,ogre_king}.json`, `data/abilities/{ogre_smash,ogre_sweep,boss_combo_1,boss_combo_2,boss_slam,boss_charge,boss_wall_recover,boss_phase_roar}.json`, `data/weapons/{ogre_club,king_club}.json`, `data/world/encounters_ogres.json` (forest ogre, field ogre, Kingsfall boss)
- Tools and scenes: `tools/builders/heavy.gd`, `scenes/enemies/{ogre,ogre_king}.tscn`, `scenes/test/boss_arena_test.tscn`
- UI: `ui/hud/boss_bar.gd`
- Tests: `tests/integration/{test_ogre,test_boss,test_boss_arena,test_lock_anchors}.gd`
- Docs: `docs/systems/P11a-ogre-boss.md`

**Hotspot edits**
- `scripts/actors/enemy_actor.gd` and `scripts/ai/enemy_brain.gd` (anchor P11a): sequence-based attack choice and phase hooks.
- `scripts/core/schemas/enemy_schema.gd` (anchor P11a): `boss`.
- `scripts/combat/combat_entity.gd`: `lock_anchors()` and `lock_anchor_position(viewer_height: float) -> Vector3`.
- `scripts/presentation/camera_rig.gd`: `_frame_lock_target` frames `lock_anchor_position(player height)`.
- `scripts/actors/player/player_targeting.gd` (anchor P11a): lock LOS and the target line use the same anchor.
- `ui/hud.gd`: `_update_target` hides the target frame when the boss bar shows the lock target.
- `tools/data/valley_layout.json` and `tools/builders/valley.gd`: attach `BossArena` at `Kingsfall/BossArena`, wired to `ArenaGate`, `Pillars` and `valley.area.arena_engage`; regenerate the Valley.

**Design**
1. **Ogre** (§4.4 numbers):
   - strikes have `interrupt_policy: super_armor`, windups ≥ 0.9 s with telegraphs (smash: circle r 3.5; sweep: cone 120°) and recovery 1.2 s (the punish window);
   - poise 120 with `recovery_mult` 3.5, so a heavy during its recovery staggers it at any stage; turn rate 90°/s; nav layer 2; `mass_class: medium` and `grab_attach: two_hand` (grabbable at stage 3); threat 0.9; `grants_fury` true; `xp_reward` 60; `Anchors/{Torso,KneeL,KneeR,Grab}`.
2. **Ogre King** (`archetype: boss`, §4.4 numbers):
   - 8.5 m tall, radius 2.0; 1,500 health, 150 poise (`recovery_mult` 3.5), armor 30; nav layer 4; threat 1.0; `grants_fury` true; `xp_reward` 300; `loot_table: loot.ogre_king` (P12's table exists by W6).
   - `boss.phases`: phase 1 (above 50% health) `sequence: [boss_combo_1, boss_slam]` (strict alternation; the combo chains `boss_combo_1 → boss_combo_2` via `chain_next`). Phase 2 (≤ 50%) has `enter_action: boss_phase_roar` and `sequence: [boss_combo_1, boss_slam, boss_charge]`. When an entry's `ai_min_range_m` / `ai_max_range_m` is not met, the brain approaches or backs off for up to 2 s, then skips to the next entry.
   - Combo: blockable and parryable, cone telegraph. Slam: circle r 5, 1.3 s windup, `Unblockable` and `Unparryable`.
   - Charge: a 0.9 s windup that turns toward the player at 90°/s, then a committed `motion` (15 m/s, `steer_deg_s 0`, `stop_on_wall` → `boss_wall_recover`, `active_s` capped at 6.0); `Unblockable` and `Unparryable`; a line telegraph along the committed direction; `charge_min_range_m` 8. Hitting the arena wall or a pillar forces `boss_wall_recover`, a 2.5 s recovery (the punish window, and with `recovery_mult` a poise opportunity). A charge that ends without a wall has a 1.4 s recovery.
   - Phase roar: 1.5 s, no damage, forced through `force_action` on entering phase 2; `boss_phase_changed` is emitted once, and the tutorial director shows the charge prompt on it.
   - `OgreBossBrain` sets `phase2_entered` once and never re-enters phase 1 behaviour, even if healed above 50% and damaged again.
   - `ignores_morale`, `Grab` immunity, `grab_attach: none`, `status_immunities ["Fear"]`, every attack telegraphed (no unseen instant phase damage).
   - The `body_sweep` shape is a capsule swept along the charge, deduped per instance.
3. **Lock anchors** (spec §5). The ogre and the boss have `Anchors/{Torso,KneeL,KneeR}`, all on one CombatEntity, so they share health. `lock_anchor_position(viewer_height)` returns the lowest anchor when the target is at least 1.3 × the viewer's height, otherwise the torso. Lock framing, lock LOS and the target line use it, so the camera never looks steeply up at the 8.5 m boss.
4. **BossArena:**
   - Before engagement the antechamber is open (safe exit).
   - Entering `valley.area.arena_engage` first despawns any non-boss enemy inside the arena bounds (`EncounterDirector.despawn`; they return to their encounters), then closes `ArenaGate` (collision and visual on) and emits `boss_engaged`.
   - On boss death: open the gate, `try_set_flag("world.ogre_king.defeated")`, `boss_defeated` (a checkpoint trigger).
   - If the player dies, the checkpoint reload resets the arena.
   - Boss bar: name, health and phase pips.

**Tests to add**
- Ogre: super armor keeps its strike through light hits; a stage-1 heavy during the ogre's recovery staggers it (35 × 1.08 × 3.5 ≈ 132 ≥ 120), while the same heavy outside recovery does not.
- Boss phases exactly once [§15]: damage to 49%, then heal to 80%, then damage to 30% → one `boss_phase_changed` and one roar.
- Phase 1 never repeats the same attack twice in a row over 20 decisions; phase 2 charges at least once every 3 decisions.
- Charge: 10 seeded phase-2 charges from random player positions at least 8 m away all end in `boss_wall_recover` (wall or pillar); in an open test arena with no wall the charge ends on its cap with the 1.4 s recovery.
- The slam and the charge deal full damage through a block; the combo can be blocked and parried.
- Every boss and ogre attack windup is ≥ 0.8 s and has a telegraph.
- Damage table: the slam deals 126 ± 1 to a stage-2 player with armor 0 (§4.4).
- Lock framing: at stage 2 the lock focus on the boss is a knee anchor; a locked soldier at stage 1 is still framed at its torso.
- Arena: leaving before engagement is possible; engagement closes the gate and removes a soldier that followed the player in; boss death opens the gate and emits `boss_defeated`.
- Stage 3 grabs a staggered real ogre and throws it.

**Acceptance:** [M4] five roles plus the boss; [§15] boss phases exactly once; [spec §10] alternation, punishable wall recovery, safe exit and a checkpoint outside (the Kingsfall shrine).

**Size:** ~2,900 lines.

### 3.13 P11b — Civilians, factions, guards, awe and brace tactics, sparring post

- **Wave / lane:** W7, lane A, parallel with P14. **Depends on:** P10b, P13 (and earlier waves). **Milestone:** M4.
- **Goal:** civilians that flee to reachable safe markers; the village faction behind the intimidation choice, with protection against accidental hostility; growth-dependent soldier tactics (awe at stage 3, the brace counter while holding formation); and the sparring post that teaches block, parry and dodge.

**Owned paths**
- Actors and AI: `scripts/actors/{civilian,sparring_post}.gd`, `scripts/ai/{civilian_brain,sparring_brain}.gd`
- World and schema: `scripts/world/faction_state.gd`, `scripts/core/schemas/npc_schema.gd`
- Data: `data/npcs/{villager,elder}.json`, `data/enemies/sparring_post.json`, `data/abilities/{soldier_brace,sparring_swing}.json`, `data/world/encounters_village.json` (guards and folk)
- Tools and scenes: `tools/builders/npcs.gd`, `scenes/npcs/{villager,elder}.tscn`, `scenes/enemies/sparring_post.tscn`, `scenes/test/village_test.tscn`
- Tests: `tests/integration/{test_civilians_factions,test_awe_brace,test_sparring_post}.gd`
- Docs: `docs/systems/P11b-village-factions.md`

**Hotspot edits**
- `scripts/actors/enemy_actor.gd` and `scripts/ai/enemy_brain.gd` (anchor P11b): faction team switching (NEUTRAL ↔ ENEMY on `faction_changed`), guard HOLD while neutral (no attacks), STAND_DOWN, and awe on first sight.
- `data/enemies/soldier.json`: `tactics.hold_attack: ability.soldier_brace`, `awe_ratio 4.0`, `awe_morale_loss 35`; `data/enemies/{archer,mage}.json`: the awe fields.
- `tools/builders/sandbox.gd`: a sparring post near the sandbox dummies.

**Design**
1. **Civilians** (`npc.villager`, team NEUTRAL, faction `village`, not lockable):
   - IDLE → FLEE (giant within `flee_trigger_radius_m` moving faster than 3 m/s, combat noise within 20 m, `faction.village.hostile`, or `stood_down`);
   - pick the nearest reachable `safe_markers` point once (`region_get_closest_point` on the human region, confirmed with `map_get_path` on layer 1);
   - re-path only on path failure; at the marker set `process_mode DISABLED`.
   - The elder is `protected` and has an `NpcTalker` child (P13's class) with `dialogue.elder`.
2. **FactionState** (POST_RESOLVE order 150; static helpers on WorldState flags):
   - An **offence** is a direct (non-area) player hit, with outcome HIT, BLOCKED, PARRIED or IMMUNE, on a member of a faction that is not hostile. Area effects never reach faction members (P03).
   - First offence: `set_flag("faction.village.warned", true)`, `faction_changed(…, "warned")`, and the HUD message "Thornwick's people cower. Strike again and they will fight you."
   - A second offence within 30 s of the previous one: `try_set_flag("faction.village.hostile")` and `faction_changed(…, "hostile")`. Guards switch to team ENEMY with normal AI (so they become lockable), and civilians flee. Offences older than 30 s are forgotten.
   - Hostility never sets `quest.village.outcome`; only the barricade does (decision 11).
   - `faction.village.stood_down` sets STAND_DOWN: walk to the matching formation markers, guard down, stay NEUTRAL.
3. **Guards** (`faction: village`): spawn NEUTRAL and HOLD at their posts facing the giant, with no attacks while neutral.
4. **Brace counter:** `ability.soldier_brace` (P30, poise 30, windup 0.8 s, active 0.15 s, recovery 0.7 s, a 3.5 m line telegraph, `ai_max_range_m` = 3.0 + the target's capsule radius), used by HOLD soldiers through `tactics.hold_attack`, holding a melee token. A giant that steps into the spears is punished; one that strikes from the edge of its own reach is not.
5. **Awe:** on the first perceive of a target whose height is at least `awe_ratio` × the unit's own height, the unit loses `awe_morale_loss` once per life (`on_morale_delta(-35, "awe")`).
6. **Sparring post** (`enemy.sparring_post`, archetype `training`): immobile; unkillable (resets at 1 health); team ENEMY and lockable (threat 0.1); `xp_reward` 0; `grants_fury` false. When the player is within 4 m it swings every 3 s (`ability.sparring_swing`: power 10, windup 0.8 s, circle telegraph r 3, `Parryable`). It never sets `brain.aware`, so it never defers checkpoints, and its encounter does not count toward the budget.

**Tests to add**
- Civilians reach their safe markers (all reachable) and stop processing [§15 reachable destination].
- Hostile-only rules: Tab near neutral guards selects nothing; a Footfall beside a guard and three villagers leaves the faction neutral; one direct light hit on a guard warns and does not set hostile; a second within 30 s sets hostile, after which guards are lockable and attack and villagers flee; a second hit 40 s after the first only warns again.
- Smashing the barricade sets outcome `force`; turning the village hostile by attacking never sets the outcome.
- Stand-down moves guards to their posts.
- Awe: at stage 3 a soldier that sees the giant drops from 70 to 35 morale and flees after one Roar (−30); at stage 2 there is no awe.
- Brace: a HOLD soldier braces when the stage-2 giant comes within 3.0 m + its radius, shows a line telegraph and deals 35 damage; a light swing from 4.5 m does not trigger it.
- Sparring post: swings every 3 s with a circle telegraph; blocking, parrying and dodging it give BLOCKED, PARRIED and EVADED; it never dies; it does not defer a checkpoint.

**Acceptance:** [§15] reachable civilian destinations; the faction rules of decision 17; the size tactics of decision 26.

**Size:** ~2,300 lines.

### 3.14 P12 — Progression, attributes, loadout, inventory, loot and the forge upgrade

- **Wave / lane:** W5, lane B, parallel with P10b. **Depends on:** P05, P06, P08. **Milestone:** M4.
- **Goal:** XP and levels (spec §9), attribute points with derived stats, level-based unlocks with auto-slotting and abilities taught by rewards, shrine loadout and attribute tabs, the inventory screen, loot tables (props and enemies), and the single upgrade interaction, which also refits the weapon for stage 3.

**Owned paths**
- Rules: `scripts/progression/{progression,loot}.gd`, `scripts/core/schemas/loot_table_schema.gd`
- Player and world: `scripts/actors/player/player_progression.gd`, `scripts/world/forge.gd`
- UI: `ui/screens/{inventory_screen,attributes_screen,forge_screen}.gd`, `ui/screens/shrine/{loadout_tab,attributes_tab}.gd`, `ui/hud/{xp_bar,ability_notice}.gd`
- Tools and scenes: `tools/builders/forge.gd`, `scenes/world/forge.tscn`
- Data: `data/loot/{ogre_king,crate_armory,crate_quarry,raider}.json`, `data/items/{supply_cache,ogre_tusk,crown_first_king}.json`
- Tests: `tests/unit/test_progression_rules.gd`, `tests/integration/{test_progression_player,test_inventory_forge_loot,test_dexterity_windows}.gd`
- Docs: `docs/systems/P12-progression-inventory.md`

**Hotspot edits**
- `scripts/world/breakable_prop.gd`: `loot_table` support.
- `scripts/progression/character_state.gd`: helpers.
- `scripts/core/schemas/{enemy,prop,weapon,item}_schema.gd` (anchor P12): `loot_table` refs and the item fields.
- `data/enemies/{soldier,wolf,archer,mage}.json`: `xp_reward` (20 / 15 / 25 / 30).
- `data/props/crate.json`: switch the inline `loot` to `loot_table`.
- `data/progression/progression_default.json`: unlock tuning.

**Design**
1. **Progression rules** (pure):
   - `xp_to_next(level)` from the table (100 + 50 × (L − 1)); level 20 is the cap;
   - `add_xp(character, n)` gives 3 attribute points and 1 talent point per level gained;
   - `allocate(character, delta)` validates points, no negatives, and only the six attributes;
   - `derived_preview(...)` shows the resulting maxima for the screen.
2. **PlayerProgression** (component):
   - owns `level`, `xp`, `attributes`, `unspent_attribute_points`, `talent_points`, `known_abilities` and `level_exempt` in apply/capture (and shows `ancestry`); level gating is **on only after `apply_state`** (sandbox and tests keep `controller.level = 99`);
   - listens to `xp_award_requested` and `entity_died` (kill XP when `killer_id == "player"` or a player projectile/throw, from the record's `xp_reward`; never for NEUTRAL entities, so guards give XP only after the village turns hostile);
   - level-up emits `level_changed`, `xp_gained` and newly met abilities (`unlock_level` ≤ level, `unlock_stage` ≤ stage, in `ability_library`) → `ability_learned` with auto-slot (first empty slot; `ultimate` for kind ultimate);
   - `learn_ability(id: String, source: String) -> bool`: adds `id` to `known_abilities`, and to `controller.level_exempt` when its `unlock_level` is above the current level; auto-slots it and emits `ability_learned`; false if already known (dialogue rewards use it);
   - `allocate` → `combatant.set_attributes` (Endurance +15 health and +2 stamina per point; Intellect +2 essence; Constitution +3 poise; Dexterity recovery −0.5% per point, capped at 15%, applied to attack recovery only; Willpower +0.5 points elemental resistance per point, capped at 20 points; percentages kept);
   - `set_slot` is only possible at a shrine (screen) and outside combat;
   - the HUD ability notice ("New ability: Runic Bolt [6]") waits until `pools.in_combat()` is false;
   - F8 debug adds 100 XP.
3. **Loot:** `Loot.roll(table_id) -> Array` (guaranteed items plus weighted entries with `Sim.rng_for("loot")`). Enemy loot is a PlayerProgression listener on `entity_died` with the same killer rule as XP: the table is the actor's `loot_table` (a per-spawn override) or the record's, and it is awarded through `WorldState.try_award_loot(entity_id)`, so it happens once. `enemy_actor.gd` needs no edit. BreakableProp `loot_table` likewise.
4. **Inventory screen:** items (name, count, description, quest tag), owned weapons with Equip (`equipment.equip_weapon`) and "(too small)" where it applies, current loadout, talent points ("talent trees are a full-game feature"). The I / Back hotkey works outside combat only; in combat it says "Not during combat".
5. **Attributes screen and shrine tab:** allocation with a derived preview, and the read-only line "Ancestry: Unaligned — no modifiers in the prototype".
6. **Forge** (`Interactable`; exports in §2.7.4): `can_upgrade` checks `requires_flags` / `requires_flag_values` (the village forge needs `quest.village.outcome` ∈ {`help_cache`, `help_ogre`}), that the equipped weapon has an `upgrade`, and that the cost items are held. `upgrade` → forge screen confirm → remove items, grant and equip the reinforced weapon (which fits stage 3), remove the old one from owned, `upgrade_applied`. It can't be repeated for the same weapon (the reinforced weapon has no further upgrade). This is the one upgrade interaction. `scenes/world/forge.tscn` is an anvil and hearth of boxes, built by `tools/builders/forge.gd`.

**Tests to add**
- XP table values; level-ups at 100/250/450/700/1,000 cumulative.
- 3 points and 1 talent point per level.
- Derived stats at 12 Endurance → +30 health; percentages kept; the Dexterity cap.
- Dexterity: at 40, light and heavy recovery is ×0.85, while windup, active, the 0.20 s parry window, the dodge i-frames (0.10–0.30 s) and the 0.75 s dodge total are identical to Dexterity 10.
- An ability learned at L2 auto-slots into slot 3, and its notice waits until the player is out of combat.
- `learn_ability("ability.ancestral_mend", "reward")` at level 3: usable at once, auto-slotted, and still known and usable after save/load.
- Loot never twice for the same id after reload; a soldier spawned with `loot_table: loot.raider` drops from that table.
- The forge consumes 2 iron once, equips the reinforced club, and damage on the dummy rises by 15% (worked: light 37 → round(46 × 1.15 × 100/125) = 42); the reinforced club is not "too small" at stage 3; a second upgrade is refused; the village forge refuses without a help outcome.
- Sandbox level gating stays off.

**Acceptance**
- [M4] minimal quest and inventory flow (inventory part); one upgrade interaction.
- [spec §9] attributes and level-up, the Dexterity rule, ancestry shown.
- [§15] loot never twice.

**Size:** ~2,900 lines.

### 3.15 P13 — Quests, dialogue, NPC talker, tutorial prompts and the end screen

- **Wave / lane:** W6, lane B, parallel with P11a. **Depends on:** P06, P10a, P12. **Milestone:** M4.
- **Goal:** data-driven quests with stage conditions, branch quests and once-only rewards; dialogue with choices that set flags, outcomes and taught abilities (the intimidate/help choice); the NPC talker; tutorial prompts with event triggers; an objective tracker and marker; and the slice end screen.

**Owned paths**
- `scripts/quests/{quests,quest_conditions,dialogue_session,tutorial_director}.gd`, `scripts/world/npc_talker.gd`
- Schemas: `scripts/core/schemas/{dialogue_schema,quest_schema,tutorial_prompt_schema}.gd`
- UI: `ui/screens/{dialogue_screen,end_screen}.gd`, `ui/hud/{quest_tracker,objective_marker,tutorial_prompt}.gd`
- Tests: `tests/unit/{test_quest_conditions,test_dialogue,test_quest_schema}.gd`, `tests/integration/{test_quest_runner,test_tutorial,test_npc_talker}.gd`
- Docs: `docs/systems/P13-quests-dialogue.md`

**Hotspot edits:** `project.godot` (autoload `Quests` after GameSession). Its reset runs through `ResetHooks` (no `integration_suite.gd` edit).

**Design**
1. **Quests autoload**, active only when `GameSession.is_valley()` or a test enables it:
   ```gdscript
   var dialogue: DialogueSession = null    # the active session (or null); the dialogue screen and the bot share it
   start_quest(id) -> bool
   stage_of(id) -> String
   is_complete(id) -> bool
   current_objective() -> Dictionary   # {"quest_id","stage_id","text","kind","marker_id","position","targets","bot"}
   objectives() -> Array               # main first, then active side quests
   evaluate_now() -> void
   current_tutorial() -> Dictionary
   start_dialogue(dialogue_id, npc_id) -> DialogueSession   # sets `dialogue`, ending any previous session
   end_dialogue() -> void
   reset_for_tests() -> void
   debug_lines() -> PackedStringArray
   ```
   - Sim POST_RESOLVE hook (order 100) evaluates every 10 ticks and on relevant events.
   - Stage progress is stored as `quest.<q>.stage`.
   - On stage completion: `try_set_flag("reward.<quest short id>.<stage>")` (for example `reward.main.grove`) grants XP (`xp_award_requested`), items (`add_item`) and `set_flags` once, then the next stage starts.
   - `auto_start` quests start on New Game; others start when their `start_conditions` hold; `abandon_when` ends a quest without rewards (`quest_abandoned`).
   - `dialogue_requested` → `start_dialogue` and the dialogue screen.
   - `hits_on` counters (with the `action_kind` / `action_id` filters) live in memory and reset on reload, which is acceptable.
2. **QuestConditions** (pure, §2.8.3 shapes) takes a context with flags, stage, level, inventory, killed, destroyed, area presence and counters.
3. **DialogueSession:** the first entry whose conditions pass is the start node; `choices()` lists only visible ones; `choose(i)` applies the effects (try-set flags; once-gated XP, items and `learn_abilities`, the last through `player.progression.learn_ability`; `outcome` → `dialogue_outcome`) and advances; `next == ""` ends it and clears `Quests.dialogue`. The dialogue screen shows the speaker, text and numbered buttons (keys 1–4, pad focus), reads `Quests.dialogue`, and pauses the game. The bot and tests call `Quests.dialogue.choose` directly without opening the screen.
4. **NpcTalker** (§2.7.4): an Interactable whose `interact` emits `dialogue_requested(npc_id, dialogue_id)`.
5. **Tutorial director:** evaluates `tutorial_prompt` triggers (`entered`, `flag`, `level`, `stage`, and `event` with the filters in §2.8.3); shows the highest-priority unseen prompt (one at a time); prompts with `defer_in_combat` wait until the player is out of combat; dismisses on the matching action kind or id, event, flag or timeout; sets `seen` and `sets_flag`. The widget resolves placeholders.
6. **Widgets and screens:**
   - Quest tracker: the main quest objective plus one side quest (the active village branch, otherwise `quest.village`), with the "Prototype pacing" label on XP gains.
   - Objective marker: a projected diamond at `marker_id`, clamped to the screen edge, with distance.
   - End screen on `slice_completed`: time, deaths, level, stage, the village outcome line ("Thornwick: you returned their stolen cache" / "you drove off the ogre" / "they opened the bridge in fear" / "you smashed your way through"), "Continue exploring", "Quit to title".

**Tests to add**
- Every condition type, true and false; `hits_on` counts only hits whose action matches `action_kind` / `action_id`.
- Quest rewards granted once across 3 re-evaluations and a checkpoint reload.
- A quest with `start_conditions` starts when they become true; `abandon_when` ends it without rewards and emits `quest_abandoned`.
- Dialogue: a hidden choice when its stage is below the requirement; an XP choice granted once when chosen twice in two sessions [spec §14 no farming by repeating dialogue]; `learn_abilities` applies once; `Quests.dialogue` is the active session during the conversation and null after it.
- NpcTalker: E next to a test NPC emits `dialogue_requested` and opens the dialogue screen on that session.
- Tutorial: a prompt is dismissed by the matching action and never shows again after its `seen` flag; an `event` trigger on `telegraph_started` aimed at the player with a `Parryable` action fires, and a `hit_resolved` dismiss with `outcome_in: [blocked, parried]` dismisses; a `defer_in_combat` prompt waits.
- The objective marker clamps to the screen edge.
- The end screen opens on `slice_completed` and shows the outcome line.

**Acceptance:** [M4] minimal quest flow and the peaceful/intimidation option mechanics; [spec §14] resolution flags prevent reward farming.

**Size:** ~3,100 lines.

### 3.16 P14 — Stress route, performance capture and graphics presets

- **Wave / lane:** W7, lane B, parallel with P11b. **Depends on:** P08, P09, P10a, P11a. **Milestone:** M5.
- **Goal:** the spec §16 stress route (12 active combatants, 20 breakables, at most 40 debris, 5 minutes); CPU-per-tick, frame-time and GPU-time capture; a reproducible low-settings preset for the reference-PC measurement; the web mitigations; and an AI LOD and budget tuning pass. Numbers are documented for the owner's reference PC.

**Owned paths**
- `tools/builders/stress.gd`, `scenes/test/stress_arena.tscn`
- `scripts/debug/{stress_scenario,perf_probe,valley_walk}.gd`
- `data/statuses/debug_invulnerable.json`
- `docs/PERFORMANCE.md`
- Tests: `tests/unit/test_perf_probe.gd`, `tests/integration/test_graphics_quality.gd`, `tests/slow/test_stress_smoke.gd`
- Docs: `docs/systems/P14-stress-perf.md`

**Hotspot edits**
- `scripts/debug/autopilot.gd`: `--scenario=stress` and `--scenario=valley_walk` dispatch; exit code 2 when a scenario's own check fails.
- `scripts/world/encounter_director.gd`: tuning constants only.
- `scripts/world/level_root.gd`: apply the level record's `render` preset for `Settings.graphics_quality` (Sun shadow distance, `visibility_range_end` on scenery, viewport MSAA), and on the web the `web_overrides` (forces `low`, AI tier-1 rates from 30 m).
- `scripts/core/settings.gd` and `ui/screens/settings_pages.gd`: `graphics_quality` (`low` \| `medium`; default `medium` on desktop, always `low` on the web) and the command-line flag `--graphics=low|medium`.
- `data/world/level_valley.json`: `lod`, `render` and `web_overrides` values.

**Design**
1. **Stress arena** (160 × 160 m):
   - a rectangular route of 8 waypoints;
   - 20 breakables along the route (8 fences, 6 small trees, 4 crates, 2 practice gates);
   - 12 combatants (4 soldiers, 3 wolves, 2 archers, 1 mage, 2 ogres) that respawn 5 s after death to keep 12 active;
   - a human (layer 1) and a large (layer 2) nav region baked when the scene is built, so ogres path instead of steering directly.
2. **Stress scenario:** only under `--scenario=stress`, the player gets the hidden `status.debug_invulnerable` (`damage_taken_mult` 0) for the whole run, so it survives 12 attackers. The bot loops the route for 300 s, heavy and Footfall on every breakable (debris saturates at 40), fighting what engages it. PERFORMANCE.md states that the probe numbers are taken with this status.
3. **PerfProbe** samples every tick:
   - `Performance.TIME_PHYSICS_PROCESS` and `TIME_PROCESS` (ms);
   - real `_process` delta when `--fixed-fps` is absent;
   - GPU and CPU render time: `RenderingServer.viewport_set_measure_render_time(viewport, true)`, then `viewport_get_measured_render_time_gpu` / `_cpu` each frame (reported as `"N/A"` headless);
   - draw calls, object and node counts, static memory;
   - active combatants and debris.

   It prints `PERF_RESULT {json}` with p50/p95/p99 and maxima.
4. **valley_walk:** a scripted walk through all districts of the Valley at stage 1 (teleporting between legs when blocked) with the director active, to capture Valley CPU and draw calls, including the draw-call difference with distant enemies at LOD tier 2 (the one-box proxy).
5. **`docs/PERFORMANCE.md`:** the budget table, commands (the reference-PC run uses `--graphics=low --resolution 1920x1080`), container results, the owner's reference-PC table (blank), and the web build checklist.

**Tests to add:** percentile math; graphics quality: `low` and `medium` set the Sun's shadow distance and a scenery node's `visibility_range_end` on a test level, and a forced web flag (`LevelRoot.force_web_for_tests`) applies `low` and the 30 m tier-1 distance; stress smoke (`tests/slow`, 60 s): no errors, active combatants ≥ 10 on average, debris ≤ 40, all 20 breakables destroyed at least once, the player never dies.

**Acceptance**
- [§16] stress route runnable with metrics, including GPU time where a GPU exists.
- [M5 performance] container CPU-per-tick p95 ≤ 8 ms reported (indicative only); real-PC frame times **NOT RUN** (owner), with a reproducible low preset.
- The tool exits non-zero on errors (P02's counter) or a failed scenario check.

**Size:** ~2,100 lines.

### 3.17 P15 — Valley content: encounters, quest line, dialogue, tutorials, layout dressing and tuning

- **Wave / lane:** W8, lane A, parallel with P16. **Depends on:** P07–P14, P11a, P11b. **Milestone:** M4.
- **Goal:** author the whole §4 design as data and dressing. Prove the complete loop with fast tests and walkthroughs. This is the M4 "complete loop" gate.

**Owned paths**
- World data: `data/world/encounters_*.json` (all, including the files of P10b, P11a and P11b)
- Quest data: `data/quests/{quest_tutorial,quest_main,quest_village,quest_village_cache,quest_village_ogre}.json`, `data/dialogue/dialogue_elder.json`, `data/tutorial/*.json`
- Tuning: `data/shrines/*.json`, `data/loot/*.json`, and the XP and text fields of `data/enemies/*.json` and `data/props/*.json`
- Layout and scenes: `tools/data/valley_layout.json`, `tools/builders/valley.gd`, `scenes/world/valley*.tscn`, `assets/nav/valley_*.res` (re-baked)
- Tests: `tests/integration/test_valley_content.gd`, `tests/unit/test_xp_budget.gd`, `tests/slow/{test_valley_walkthrough,test_valley_clearance,test_valley_flee}.gd`
- Docs: `docs/systems/P15-valley-content.md`

**Hotspot edits:** `data/progression/progression_default.json` (the final ability schedule).

**Design:** content exactly as §4.3–4.7: every encounter in §4.4 (including the forest hunters, the road patrol with its mage, the return patrol on the bridge, the village ambush, the Barrow wardens and the Hollow sparring post); the three quests plus the two village branch quests with stage `bot` hints; the elder dialogue with all outcomes and their rewards; the 13 tutorial prompts in §4.5; pickups (supply cache, crown), crates, racks, both forges, the three waystones and the moved Thornwick shrine; signs (locked Citadel "SEALED — Stage 4", "Prototype pacing" sign at the Hollow); the XP values, the barricade's `xp_reward` 30; and dressing (scenery density, barley rows, cosmetic bushes and banners in the village and fields).

**Tests to add**
- **Content integrity:** every marker, area, world id, entity id, patrol, encounter and dialogue referenced by quests, dialogue, encounters, tutorials or the layout exists in the Valley scene or in the data, and ids are unique.
- **Quest-critical objects:** every prop named by a mandatory `destroyed` stage is not `protected` and accepts a category or tag the player has by that stage (cairn: `projectile` from Boulder Hurl at stage 2; practice gate: `melee`; Deadfall: `TreeWeapon` at stage 3).
- **XP budget** (pure, from data): mandatory XP reaches level 3 before stage `grove`, level 4 by the end of stage `gate`, and level 5 before `grow3`, for each village outcome.
- **Growth shrine safety:** no encounter spawn or patrol point lies within 35 m (sight 25 m + 10 m) of a growth shrine's GrowthPad, and no encounter's leash circle contains one.
- **Checkpoint placement:** the road centrelines of §4.2 pass within the activation radius of every shrine and waystone on the critical path.
- **Introductions:** the first critical-path encounter that contains a mage contains no archer; the first soldiers on the critical path are met at stage 1 (`forest_hunters`).
- **Tutorial data:** every prompt's trigger and dismiss refer to existing areas, events, actions and flags; the Hollow has two dummies and the sparring post.
- **Clearance (slow):** the giant nav layer has a path for the stage-3 legs (Kingsfall → causeway → courtyard → bridge → village → Grove → Deadfall → Barrow), and each leg's corridor is ≥ 8 m wide (sampled capsule queries along the path).
- **Flee reachability (slow):** soldiers of `return_patrol` and `ruins_courtyard`, forced to flee in the Valley, reach their flee points on the human layer.
- **Walkthrough (slow), one run per village outcome** (`help_cache`, `help_ogre`, `intimidate`, `force`):
  - drives the real systems with direct calls: teleport to markers, `Quests.dialogue.choose`, `shrine.grow`, kills applied through synthetic lethal hits, `interact()` on pickups and forges;
  - asserts stage order, flags, XP ≥ thresholds at each gate, rewards granted once, the barricade open, Mend learned at the village on the help runs and Roar on the intimidate run, `slice.completed` set;
  - runs a death and reload mid-run, and asserts no duplicated reward.
- **Boss checkpoint (slow):** kill the boss, grow to stage 3, die on the return leg: the reload has `world.ogre_king.defeated` set, the player at stage 3 at the Kingsfall shrine with at least 60% health.

**Acceptance**
- [M4] complete loop, peaceful and intimidation options, checkpoint saves along the line.
- [spec §14] sequence order.
- Content tests pass.

**Size:** ~3,000 lines (mostly data).

### 3.18 P16 — UX, controller and usability pass

- **Wave / lane:** W8, lane B, parallel with P15. **Depends on:** P03, P05, P06, P12, P13. **Milestone:** M5.
- **Goal:** pad-navigable menus, keyboard and pad glyph switching, the help overlay generated from the live loadout, a HUD layout check, and the written usability script and form.

**Owned paths**
- `ui/**` (focus, navigation and layout fixes in every screen and widget)
- `docs/USABILITY_SCRIPT.md`
- Tests: `tests/integration/{test_ui_focus,test_hud_layout}.gd`
- Docs: `docs/systems/P16-ux-controller.md`

**Hotspot edits:** `scripts/adapters/input_bindings.gd` (`last_device_is_pad()` and `note_device(event)`); `scripts/main.gd` (call `InputBindings.note_device` in `_input`).

**Design**
- Every UiScreen gets a `first_focus`, `focus_neighbor_*` chains and wrap-around; pad B is cancel. Rebinding keeps Esc as cancel.
- Prompts and tutorial text use the last device.
- Help overlay rows are built from `controller.loadout`, with interact and inventory added.
- HUD layout at 1280 × 720 and 1920 × 1080: no widget rects overlap except where designed (the threat-arrow overlay draws only at the edges; the boss bar and the quest tracker do not touch).
- The death screen hint and pause items depend on the mode.
- **Usability script** (`docs/USABILITY_SCRIPT.md`): 3 new players; the Sandbox for 5 minutes of free play (with its sparring post), then the first 10 Valley minutes. The spec §16 "tutorial encounter" is Giant's Hollow (dummies and sparring post) plus the first wolf pack (decision 28). Record confusion, camera discomfort, accidental ability use and time to defeat, plus the "heavy, block and dodge timing identified" check.

**Tests to add:** synthetic pad events (`ui_down` and `ui_accept` as JoypadButton) navigate and press through Title, Pause, Shrine, Dialogue, Inventory, Attributes, Forge and End; glyph switching; layout overlap test.

**Acceptance:** [M5 controller] all menus usable by synthetic pad (real pad **NOT RUN**); [M5 usability] the script is delivered (human sessions **NOT RUN**).

**Size:** ~1,700 lines.

### 3.19 P17a — Valley bot, invariants, metrics and the 30-minute stability run

- **Wave / lane:** W9, solo. **Depends on:** P14, P15. **Milestone:** M5.
- **Goal:** a headless bot that plays the whole quest line under each village policy, with a novice and an expert skill profile and an assisted mode; the per-run metrics and the softlock diagnosis of §5.1; the 30-minute stability run with invariants (§5.2); and the batch runner P17b uses.

**Owned paths**
- `scripts/debug/{valley_bot,bot_combat,run_metrics,bot_diagnosis}.gd`
- `data/statuses/bot_assist.json`
- `tools/run_bots.sh`
- Tests: `tests/slow/test_bot_smoke.gd`
- Docs: `docs/systems/P17a-valley-bot.md`

**Hotspot edits:** `scripts/debug/autopilot.gd` (`--scenario=valley` dispatch; the flags `--bot-village=`, `--bot-skill=novice|expert`, `--bot-assist`, `--bot-loop`, `--bot-seed=`; exit code 2 on a watchdog breach, 3 on an invariant failure).

**Design:** §5.1–5.2. The bot node runs with `PROCESS_MODE_ALWAYS` (the M1 autopilot is pausable, so a pausing screen would freeze it). It calls screen-backed APIs directly (`Quests.start_dialogue` and `Quests.dialogue.choose`, `shrine.rest`, `shrine.grow`, `forge.upgrade`) instead of opening screens, and closes any pausing screen it does cause with `ScreenStack.close_all_static()`. `tools/run_bots.sh <matrix>` starts runs in the background with `timeout 900` each, at most 3 at once, each writing its `AUTOPILOT_RESULT` line to `user://bot_runs/<policy>_<skill>_<seed>.json`, and prints a summary table when all are done.

**Tests to add:** bot smoke (`tests/slow`): the first two objectives of `quest.main` complete within 120 s simulated (novice, assisted), with no errors; the diagnosis classifies an objective whose marker is unreachable on a test level as `world_blocked`; the result JSON has every metric key of §5.1.

**Acceptance**
- [M5 stability] the 30-minute assisted run (`--bot-loop`) passes: no crash, softlock, duplicated reward or unrecoverable targeting state, and bounded node growth.
- [M4 complete loop] the assisted novice bot completes the quest line for all four village outcomes.
- Unassisted novice and expert completion rates are reported as tuning metrics, not gates.

**Size:** ~2,800 lines.

### 3.20 P17b — Balance loop and the how-it-plays report

- **Wave / lane:** W10, solo. **Depends on:** P16, P17a. **Milestone:** M5.
- **Goal:** tune the data against the novice-bot targets of §5.6, and write `docs/HOW_IT_PLAYS.md` and `docs/BALANCE_LOG.md`.

**Owned paths**
- `docs/{HOW_IT_PLAYS,BALANCE_LOG}.md`, `docs/systems/P17b-balance.md`
- `data/**` (number changes only, each logged in `BALANCE_LOG.md`)
- `tools/data/valley_layout.json` (position nudges only, logged; followed by a rebuild and re-bake)

**Hotspot edits:** none beyond the owned data.

**Tests to add:** none; tuning changes data only, and the existing suite, `--slow` and the XP budget test must stay green.

**Design:** §5.6–5.7. All bot runs go through `tools/run_bots.sh`, started with `run_in_background` and polled by reading its output folder; no foreground command runs longer than 10 minutes. A run that exceeds its 900 s timeout is recorded as a failure with its last objective. Optional: `--scenario=valley_capture`, a rendered screenshot per §4.9 segment for the report and P18. It needs a display, and is recorded as skipped when headless.

**Acceptance**
- Every §5.6 target is met, or the balance log explains why not and what was tried.
- The full suite, `--slow` and the XP budget test still pass after tuning.
- `HOW_IT_PLAYS.md` is written per §5.7.

**Size:** ~900 lines (documentation and data edits), plus 1–2 hours of background bot runs.

### 3.21 P18 — Ship: final verification, documentation, exports, web build, merge

- **Wave / lane:** W11, solo. **Depends on:** P17b. **Milestone:** M5.
- **Goal:** deliver what spec §16 asks a handoff to contain, and merge.

**Owned paths:** `README.md`, `docs/{ARCHITECTURE,DECISIONS,M2_M5_HANDOFF}.md`, `project.godot` (version `0.5.0-m5`), `export_presets.cfg`, `web/launcher.html`, `tools/build_web.sh`.

**Hotspot edits:** none.

**Tests to add:** none; P18 runs every existing gate and records the evidence.

**Design**
1. Full suite plus `--slow`; the 30-minute run; stress; one assisted and one novice bot run per village outcome.
2. Windows export (produced) and Linux export (run headless with the bot, plus a rendered screenshot tour of the Valley through `--scenario=capture` extended to the Valley by P17b, or skipped).
3. Web export: verify `.pck` size, that the save survives a page reload (IndexedDB), and that the title Start click captures the mouse. Republish the play link through the Artifact tool, updating the existing artifact URL if known.
4. Consolidate `docs/systems/*` into `ARCHITECTURE.md` and `DECISIONS.md` (all §0.3 decisions, with the review log of §7 summarised). Write `M2_M5_HANDOFF.md` with the spec §16 contents: changed files, engine version, launch/export, controls, implemented versus deferred, test results with evidence (novice and expert bot tables included), known bugs, next smallest milestone.
5. PR `claude/hopeful-gauss-0f323t` → `main` with the gate table; merge.

**Acceptance:** every gate in §0.2 is reported PASS, PARTIAL or NOT RUN with evidence; `main` contains the release.

**Size:** ~900 lines (documentation).

---

## 4. The Valley of Broken Kings

### 4.1 Map frame and districts

The map is 400 × 400 m: x from −200 (west) to +200 (east), z from −200 (north, Godot −Z) to +200 (south). Ground top is y = 0. Cliffs 30 m tall (WORLD) ring the edge. The river runs north–south at x 100–112, impassable: water plane plus BLOCKER walls 12 m tall on both banks, except at the King's Bridge (z −26 to −14).

| District | id | Rect min → max (x, z) | Character |
| --- | --- | --- | --- |
| Giant's Hollow | `hollow` | (−200, 100) → (−90, 200) | Grassy bowl in cliffs; start, tutorial (dummies, sparring post), first shrine |
| Old Wood | `forest` | (−200, −130) → (−30, 100) | Dense scenery trees; 14 m road; wolf clearing; hunters' camp at the road bend; ogre clearing |
| Barrow of the First King | `barrow` | (−110, −200) → (−10, −130) | Walled courtyard behind the Deadfall gap; crown altar |
| Thornwick village and fields | `village` | (−30, −90) → (100, 100) | 18 cottages (4–6 m walls), palisade, square, watchtower, barley fields (south) |
| Raider Quarry | `quarry` | (−10, −200) → (100, −90) | Rock pit, 10 m ravine entrance, ledge, raider camp |
| Ruins of the Broken Kings | `ruins` | (100, −150) → (200, 20) | 10 m outer walls, courtyard, 5 m wall walks, armory, sealed citadel |
| Kingsfall | `kingsfall` | (100, 20) → (200, 200) | Shrine, antechamber, circular arena (r 40, 15 m walls, four 3 × 3 × 15 m pillars at r 22) |
| The Hills (impassable) | — | (−90, 100) → (100, 200) and (−200, −200) → (−110, −130) | Visual only (cliffs and trees), outside the nav |

### 4.2 Paths, corridors and clearance

Road centrelines, in order of play (a width of at least 12 m and no overhead geometry, unless noted):

1. **Hollow trail:** Cradle (−150, 170) → (−140, 140) → canyon exit (−140, 100). The canyon is 12 m wide with 20 m walls.
2. **Forest road:** (−140, 100) → (−140, 40) → (−120, 10) (hunters' camp at the bend) → (−100, −20) → ogre clearing (−90, −35) (clearing radius 25) → (−75, −55) → Grove Shrine (−60, −70).
3. **Barrow spur:** Grove (−60, −70) → (−50, −100) → Deadfall gap (−50, −112), 14 m between cliffs → Barrow courtyard (−55, −160) → crown altar (−55, −172).
4. **King's Road:** Grove (−60, −70) → (−25, −58) → (−8, −50) → village west gate (5, −40) → square (45, −20) → east gate (85, −20) → barricade (96, −20) → King's Bridge (100–112, −20; 12 m wide, rails) → (120, −20) → practice gate (125, −20) (10 m opening, no lintel).
5. **Quarry path:** north gate (45, −50) → (45, −90) → ravine (40, −110) (10 m wide; the first required stage-2 corridor) → quarry pit (40, −150) (60 × 50 m).
6. **Fields:** south gate (45, 10) → field ogre (40, 55).
7. **Ruins:** courtyard (125–190, −110 to 10) → causeway exit (155, 10–20) (12 m) → (150, 40) → Kingsfall Shrine (150, 55) → antechamber (150, 70–90) (14 m wide) → arena, centre (150, 135), r 40, z 95–175.
8. **Return leg** (stage 3): Kingsfall → causeway → courtyard (armory and Giantforge beside it) → practice gate → bridge (return patrol) → square (village ambush if hostile) → west gate → Grove → Deadfall → Barrow (wardens) → crown. About 410 m, roughly 55 s at stage-3 sprint and walk plus the fights.

**Clearance rules:**
- Every leg required after a growth point fits that stage: stage 2 (r 1.2, h 5.5) from the Grove onward; stage 3 (r 1.65, h 7.9) on the return leg.
- Required corridors are ≥ 8 m wide and have no roofs. Village side alleys (4 m) and the Hollow cottage arch (4.5 m) are optional, stage-1-only shortcuts; they exist only on the small-giant nav layer (8).
- Every shrine pad, waystone and checkpoint marker has stage-3 clearance. P10b and P15 test this.
- Every shrine and waystone on the critical path lies within its activation radius of a road centreline (P15 tests this).

### 4.3 Points of interest

**Shrines** (`activation_radius_m` 14; the first activation per load is a free Rest and a checkpoint)

| World id / checkpoint | Record | Position (x, y, z) | Growth | Notes |
| --- | --- | --- | --- | --- |
| `valley.shrine.hollow` | `shrine.hollow` | (−130, 0, 145) | — (max 1) | `level.start_checkpoint`; 11 m from the trail |
| `valley.shrine.grove` | `shrine.grove` | (−60, 0, −70) | to stage 2 (level 3) | End of the forest road; Deadfall visible 43 m north; no encounter within 35 m |
| `valley.shrine.thornwick` | `shrine.thornwick` | (14, 0, −26) | — | Just inside the west gate, 9 m off the King's Road; 46 m from the nearest guard post |
| `valley.shrine.kingsfall` | `shrine.kingsfall` | (150, 0, 55) | to stage 3 (level 5, after `world.ogre_king.defeated`) | On the ruins road, outside the arena |

**Waystones** (`Waystone`, radius 10 m; checkpoint only, no heal, no growth; taken when out of combat)

| Id | Position (x, y, z) | `requires_flags` | Covers |
| --- | --- | --- | --- |
| `valley.cp.forest_road` | (−140, 0, 38) | `encounter.forest_wolves_a.cleared` | Hunters and forest ogre after the first wolf pack |
| `valley.cp.ruins_gate` | (134, 0, −18) | `world.ruins.gate_broken` | The courtyard after the practice gate |
| `valley.cp.barrow_gap` | (−50, 0, −122) | `world.forest.deadfall_broken` | The Barrow wardens and the crown |

**Props**

| World id | Prop | Position | Notes |
| --- | --- | --- | --- |
| `valley.hollow.fence_pen` | `prop.fence_wood` | (−105, 0, 135), yaw 90 | Optional first break (wood scrap) |
| `valley.forest.tree_01` … `_12` | `prop.tree_small` | Along the forest road | Selective destruction |
| `valley.grove.cairn` | `prop.cairn` | (−42, 6, −88), on a 6 m ledge 20 m from the shrine | Boulder Hurl tutorial target; `projectile` category only; lockable (threat 0.05); locked message |
| `valley.forest.deadfall` | `prop.deadfall` | (−50, 0, −112), yaw 0, width 14 | TreeWeapon only; nav link through; sets `world.forest.deadfall_broken` |
| `valley.forest.oak_barrow` | `prop.ancient_oak` | (−30, 0, −110) | Backup tree source at the Deadfall |
| `valley.village.fence_01` … `_04` | `prop.fence_wood` | Palisade segments | Breakable; hitting them is not a faction offence |
| `valley.village.barricade` | `prop.cart_barricade` | (96, 0, −20), yaw 90 | Stage ≥ 2; XP 30; `open_when_flag faction.village.gate_open`; destroying it sets `quest.village.outcome = force` and `faction.village.hostile` |
| `valley.ruins.practice_gate` | `prop.gate_practice` | (125, 0, −20), yaw 90 | **Structural**: intact → cracked (≤ 50%) → broken; any stage; XP 20; nav link; sets `world.ruins.gate_broken` |
| `valley.ruins.citadel_gate` | `prop.gate_fortified` | (190, 0, −60), yaw 90 | Locked: "Fortified gates can be breached at stage 4" |
| `valley.quarry.chest` | `prop.crate` | (30, 0, −165) | `loot.crate_quarry` (1 iron) |
| `valley.ruins.armory_crate` | `prop.crate` | (172, 0, −98) | `loot.crate_armory` (1 iron) |
| `valley.kingsfall.oak` | `prop.ancient_oak` | (175, 0, 45) | Tree weapon |
| `valley.*.bush_*`, `valley.*.banner_*`, barley sheaves | `prop.bush`, `prop.banner` (cosmetic) | About 30 in the Hollow, the fields and the square; banners on the palisade and ruins walls | Placed by P15; react to steps and pulses; never saved |

**Interactables, dummies and NPCs**

| World / entity id | Kind | Position | Notes |
| --- | --- | --- | --- |
| `valley.hollow.dummy_1` / `_2` | PracticeDummy (`entity_id`) | (−118, 0, 160) / (−112, 0, 150) | Light, heavy and Footfall practice |
| `valley.hollow.sparring_post` | `enemy.sparring_post` (encounter `hollow_sparring`) | (−108, 0, 165) | Block, parry and dodge practice; unkillable |
| `valley.quarry.cache` | ItemPickup (`item.supply_cache`) | (30, 0, −158) | Help path A |
| `valley.quarry.hammer_rack` | WeaponRack (`weapon.hammer`) | (52, 0, −166) | |
| `valley.ruins.sword_rack` | WeaponRack (`weapon.sword`) | (180, 0, −100) | Armory |
| `valley.village.forge` | Forge | (40, 0, 2) | `requires_flag_values {quest.village.outcome: [help_cache, help_ogre]}` |
| `valley.ruins.giantforge` | Forge | (175, 0, −104) | Always available; beside the return leg |
| `valley.barrow.crown` | ItemPickup (`item.crown_first_king`, `set_flag slice.crown_claimed`) | (−55, 0, −172) | The end of the slice |
| `valley.village.elder` | NPC (`npc.elder`) with NpcTalker | (35, 0, −42) | Spawned by `encounter.village_folk`; protected |

**Markers**
- Objective markers (`valley.marker.*`): `dummies`, `sparring_post`, `forest_trail`, `wolves_a`, `hunters`, `ogre_clearing`, `grove_shrine`, `cairn`, `village_gate`, `elder`, `quarry_cache`, `field_ogre`, `bridge`, `practice_gate`, `ruins_courtyard`, `causeway`, `kingsfall_shrine`, `arena_center`, `kingsfall_oak`, `deadfall`, `crown`.
- Formation markers: `guard_post_1..4` (faction village; near the square and the barricade), `road_line_1..2` (−12, −46) / (−4, −52), `quarry_line_1..3` (around (40, −145)), `ruins_line_1..3` (inside the practice gate and across the courtyard).
- Safe markers: `safe_house_1..6` (cottage doors).
- Elevation markers: `tower` (75, 6, −40), `quarry_ledge` (25, 5, −165), `ruins_wall_w` (140, 5, −80), `ruins_wall_e` (180, 5, −20), `ruins_gate_wall` (128, 6, −34).
- Cover markers: `ruins_cover_1..4`, `quarry_cover_1..2`.
- Patrol routes (`Markers/Patrol/<route>/<n>`): `valley.patrol.wolves_a`, `road` ((−18, −55) → (0, −46)), `quarry`.
- Bot routes: `bot_route_*` (fallback chains through the village and ruins).

**Area triggers** (`valley.area.*`):

| Area | Position |
| --- | --- |
| `hollow_start` | Around the Cradle |
| `hollow_dummies` | (−115, 155), r 15 |
| `forest_edge` | (−140, 95) |
| `forest_hunters` | (−120, 10), r 30 |
| `ogre_clearing` | (−90, −35), r 25 |
| `grove` | (−60, −75), r 30 (includes the cairn ledge's foot) |
| `village` | West gate |
| `quarry` | Ravine |
| `fields` | South gate |
| `ruins_approach` | East bridgehead (118, −20) |
| `ruins_courtyard` | (158, −50), r 35 |
| `causeway` | (155, 18) |
| `arena_engage` | Arena threshold, z 95–100 |
| `barrow` | Barrow courtyard |

### 4.4 Encounters (spawned by the EncounterDirector; kill XP in parentheses)

| Encounter | Centre | Members (positions x, z) | Activate / deactivate / leash (m) | Flags | Purpose |
| --- | --- | --- | --- | --- | --- |
| `encounter.hollow_sparring` | (−108, 165) | `valley.hollow.sparring_post` (0) | 40 / 90 / — | Not budgeted | Block, parry, dodge practice |
| `encounter.forest_wolves_a` | (−142, 55) | 3 wolves (15) at (−150, 50), (−136, 48), (−145, 62); patrol `wolves_a` | 55 / 110 / 50 | — | First fight: dodge the lunge, then punish |
| `encounter.forest_hunters` | (−120, 10) | 2 soldiers (20) at (−125, 5), (−114, 4); 1 wolf at (−118, 16) | 50 / 110 / 45 | — | Stage-1 soldiers (guards, turns, 2 tokens); the grab tutorial |
| `encounter.forest_ogre` | (−90, −35) | `valley.forest.ogre` (60) at (−88, −38); 2 wolves at (−98, −30), (−82, −28) | 60 / 120 / 45 | — | Mandatory ogre; super armor and recovery punish |
| `encounter.road_patrol` | (−8, −50) | 2 soldiers at (−12, −52), (−4, −48); mage (30) at (−8, −58); patrol `road`; markers `road_line_1..2` | 45 / 100 / 50 | Requires `reward.main.grove` | After growth: outmatched soldiers hold a line and brace; the first mage, met alone |
| `encounter.village_guards` | (70, −20) | guards `guard_1..4` (soldier, faction village) at (60, −28), (60, −12), (88, −26), (88, −14); `captain` (commander) at (92, −20); `tower_archer` (25) at (75, 6, −40) | 90 / 150 / 40 | — | Neutral unless provoked; stand down on intimidation |
| `encounter.village_folk` | (40, −20) | 6 villagers around the square; elder at (35, −42) | 100 / 160 / — | Not budgeted | Civilians flee to safe markers |
| `encounter.quarry_raiders` | (40, −145) | 4 soldiers at (30, −140), (50, −140), (35, −155) (commander), (48, −158), each `loot_table: loot.raider`; archer at (25, 5, −165); mage at (45, −170); markers `quarry_line_1..3` | 60 / 120 / 50 | — | Help path A (cache); hammer rack |
| `encounter.field_ogre` | (40, 55) | `valley.fields.ogre` (60) at (42, 58); 2 wolves at (32, 50), (50, 48) | 60 / 120 / 45 | — | Help path B; harassing wolves at stage 2 |
| `encounter.ruins_gate` | (130, −20) | 2 soldiers at (132, −30), (132, −10) (inside); archer on `ruins_gate_wall` | 50 / 110 / 40 | — | Practice-gate fight |
| `encounter.ruins_courtyard` | (158, −50) | 3 soldiers at (150, −45), (165, −40), `sergeant` (commander) at (160, −60); archer on `ruins_wall_w`; mage at (158, −70) | 60 / 120 / 55 | — | Main fortress fight (8 active with the gate encounter); the leash keeps it south of z = 5 |
| `encounter.kingsfall_boss` | (150, 140) | `valley.arena.ogre_king` (300) at (150, 150), yaw 180 | 70 / 150 / — (arena gate) | Forbids `world.ogre_king.defeated` | Boss |
| `encounter.return_patrol` | (106, −20) | on the bridge deck: soldiers at (102, −24), (106, −20) (commander), (110, −16); archer at (116, −26); mage at (116, −14) | 60 / 120 / 40 | Requires `world.ogre_king.defeated` | Stage-3 demo: awe, the patrol breaks and scatters; cannot be bypassed |
| `encounter.village_ambush` | (45, −20) | 4 soldiers at (40, −25), (50, −15), (45, −28), (38, −14); archer on `tower` | 60 / 120 / 40 | Requires `faction.village.hostile` and `world.ogre_king.defeated` | The `force` consequence on the return leg |
| `encounter.barrow_wardens` | (−55, −162) | `valley.barrow.warden_ogre` (60) at (−55, −160); 3 wolves at (−65, −165), (−45, −165), (−55, −150) | 50 / 110 / 40 | Requires `world.ogre_king.defeated` | Stage-3 showcase: two heavies stagger the ogre; grab it and throw it into the wolves |

Enemy tuning (initial values from the spec; P17b tunes them). Every attack with a windup of 0.8 s or more has a telegraph.

| Archetype | Height / radius (m) | Health / armor / poise | Speed walk / run (m/s), turn (°/s) | Attacks (P, windup / active / recovery in s; telegraph) | Morale (start / flee / regroup) | Tactics, threat |
| --- | --- | --- | --- | --- | --- | --- |
| Soldier | 1.8 / 0.35 | 220 / 15 / 40; stagger 1.0 s (1.5 s against a ≥ 2× taller attacker) | 1.6 / 3.6, 300 | Slash 30 (0.55 / 0.15 / 0.65); chop 45 (0.85 / 0.15 / 0.80; line 2.5 m); brace 30 (0.8 / 0.15 / 0.7; line 3.5 m; HOLD only) | 70 / 25 / 45 | Guard front; `outmatched_ratio 2.5 → formation`; awe at ≥ 4.0 (−35); threat 0.6 |
| Wolf | 0.9 / 0.4 | 90 / 5 / 25 | 3.0 / 8.0, 540 | Bite 18 (0.45 / 0.10 / 0.50); lunge 25 (0.60 / 0.25 / 0.90, dash 9 m/s ≤ 5 m; line) | 50 / 20 / 40 | Flank 100°; `outmatched 6.0 → harass`; threat 0.4 |
| Archer | 1.8 / 0.35 | 140 / 5 / 30; sight 32 m | 1.8 / 3.8, 300 | Shot 22 (0.90 / 0.05 / 0.60; 32 m/s, gravity 4, range 30; aim lock at 60%; aim line); kick 15 (0.45 / 0.10 / 0.50) | 60 / 25 / 45 | Band 12–20 m, spread 6, gap 1.0 s, ranged token; outmatched → spread (×1.3 band); awe; threat 0.7 |
| Mage | 1.8 / 0.35 | 160 / 0 / 25; arcane resistance 0.3; essence 100 (+6/s) | 1.6 / 3.4, 300 | Slow bolt 20 arcane (1.0 / 0.05 / 0.6; 20 m/s; aim lock 60%; line); barrier (1.2 s; 30 essence; cooldown 10 s; circle); staff 12 (0.5 / 0.1 / 0.5) | 60 / 25 / 45 | Band 10–16 m; outmatched → kite; awe; threat 0.8 |
| Ogre | 3.4 / 0.9 | 600 / 20 / 120; poise ×3.5 during its recovery | 2.2 / 4.5, 90 | Smash 50 (1.0 / 0.2 / 1.2, super armor; circle r 3.5); sweep 40 (0.9 / 0.2 / 1.1, super armor; cone 120°) | Ignores fear | `mass medium`, `grab_attach two_hand`; nav layer 2; threat 0.9 |
| Ogre King | 8.5 / 2.0 | 1,500 / 30 / 150; poise ×3.5 during its recovery | 2.6 / 6.0, 80 | Combo 45 → 55 (0.8 / 0.2 / 0.4 → 0.8 / 0.2 / 1.0; blockable; cone); slam 75 r 5 (1.3 / 0.15 / 1.4; unblockable, unparryable; circle); charge 60 (windup 0.9 with 90°/s turning, then 15 m/s until a wall or pillar, ≤ 6 s; unblockable; line) → wall recover 2.5 s (1.4 s without a wall); phase roar 1.5 s | Ignores morale | Phase 1 alternates combo and slam; phase 2 adds the charge every third decision; immune to Grab and Fear; nav layer 4; threat 1.0 |
| Sparring post | 2.2 / 0.4 | unkillable | immobile | Swing 10 (0.8 / 0.15 / 0.6; circle r 3; parryable) every 3 s within 4 m | — | Training; never aware; threat 0.1 |

Worked combat numbers for the boss fight (spec §7 formulas; stage 2, level 4, Strength 15, Endurance 14, Oak Club; boss Strength 10, `king_club` multiplier 1.0, M_size (8.5 / 3.6576)^0.45 = 1.46; player M_size 1.20):

| Exchange | Value |
| --- | --- |
| Player maximum health | 500 + 4 × 15 + 150 = 710 |
| Player light 1 / 2 / 3 on the boss (armor 30) | 45 / 50 / 57 |
| Player heavy / Footfall / Boulder Hurl on the boss | 81 / 54 / 72 |
| Boss combo 1 / 2 on the player (armor 0) | 76 / 92 |
| Boss slam / charge | 126 / 101 |
| Boss poise per player heavy: normal / during its recovery | 23 / 79 (two heavies in a 2.5 s wall recovery stagger it) |
| Targets | A skilled kill in 90–150 s; about 5–6 major hits kill the player |

### 4.5 Quest line, triggers, flags and XP (`prototype_pacing: true`)

Stages advance in order, but every condition reads world **state**: kills, flags, destroyed objects, stage. A goal achieved early therefore completes at once when its stage comes up. The world gates the order: the barricade, the bridge, the gate, the boss flag on Kingsfall growth, and the tree permission on the Deadfall. No stage can block progress, and every main stage is a checkpoint.

**`quest.tutorial`** "Giant's Hollow" (auto-start, optional; it never blocks `quest.main`)

| Stage | Objective | `complete_when` | Marker | XP | Bot hint |
| --- | --- | --- | --- | --- | --- |
| `awaken` | Look through the giant's eyes (V), then step back | flag `tutorial.camera.done` | — | 10 | `wait` (bot toggles the camera twice) |
| `train` | Strike the practice dummies: light ×3, heavy, Heavy Footfall | `all` [`hits_on` dummies `action_kind light` 3, `hits_on` dummies `action_kind heavy` 1, `hits_on` dummies `action_id ability.heavy_footfall` 1] | `dummies` | 10 | `attack` `valley.hollow.dummy_1` |
| `spar` | Block, parry and dodge the sparring post | `all` [flag `tutorial.block.done`, flag `tutorial.dodge.done`] | `sparring_post` | 10 | `attack` `valley.hollow.sparring_post` |

**`quest.main`** "The Valley of Broken Kings" (auto-start)

| # | Stage id | Objective (HUD) | `complete_when` | Marker | XP | Bot hint |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `leave_hollow` | Follow the trail north into the Old Wood | entered `valley.area.forest_edge` | `forest_trail` | 60 | `go` |
| 2 | `wolves` | Survive the wolf pack | `any` [`encounter_cleared` `encounter.forest_wolves_a`, killed `valley.forest.ogre`] | `wolves_a` | 30 | `fight_encounter` |
| 3 | `ogre` | Defeat the ogre blocking the trail | killed `valley.forest.ogre` | `ogre_clearing` | 110 | `kill` `valley.forest.ogre` |
| 4 | `grove` | Reach the Grove Shrine and grow | `stage_at_least` 2 | `grove_shrine` | 30 | `grow` `valley.shrine.grove` |
| 5 | `hurl` | Hurl a boulder at the watch cairn on the ledge | destroyed `valley.grove.cairn` | `cairn` | 30 | `hurl_at` `valley.grove.cairn` |
| 6 | `to_village` | Follow the King's Road to Thornwick | entered `valley.area.village` | `village_gate` | 20 | `go` |
| 7 | `village` | Settle things with Thornwick (Elder Maren) | flag `quest.village.outcome` (any) | `elder` | 0 | `talk` `valley.village.elder` (policy) |
| 8 | `bridge` | Cross the King's Bridge to the ruins | entered `valley.area.ruins_approach` | `bridge` | 0 | `go` |
| 9 | `gate` | Break the practice gate of the ruins | destroyed `valley.ruins.practice_gate` | `practice_gate` | 60 | `break` |
| 10 | `courtyard` | Break the garrison in the courtyard | `any` [`encounter_cleared` `encounter.ruins_courtyard`, entered `valley.area.causeway`] | `ruins_courtyard` | 0 | `fight_encounter` |
| 11 | `causeway` | Find the Kings' Causeway | entered `valley.area.causeway` | `causeway` | 40 | `go` |
| 12 | `boss` | Defeat the Ogre King in Kingsfall | killed `valley.arena.ogre_king` | `arena_center` | 120 | `kill` (rest at the shrine first) |
| 13 | `grow3` | Return to the Kingsfall Shrine and grow | `stage_at_least` 3 | `kingsfall_shrine` | 30 | `grow` |
| 14 | `tree` | Uproot an ancient oak | flag `world.tree_weapon_taken` | `kingsfall_oak` | 20 | `interact` `valley.kingsfall.oak` |
| 15 | `deadfall` | Smash the Deadfall in the Old Wood with your tree | destroyed `valley.forest.deadfall` | `deadfall` | 40 | `break` |
| 16 | `crown` | Claim the Crown of the First King | flag `slice.crown_claimed` | `crown` | 50 | `interact` `valley.barrow.crown` |

On completion: `slice.completed` and the end screen. Every stage reward is gated by `reward.main.<stage>` (`reward.tutorial.<stage>` for the tutorial).

**Tutorial prompts** (`data/tutorial/*.json`; one prompt at a time; `{…}` placeholders use the last device):

| Prompt | Trigger | Text | Dismiss |
| --- | --- | --- | --- |
| `tutorial.camera` | entered `hollow_start` | "Press {camera_toggle} to see through the giant's eyes. Press it again to step back." | `camera_mode_changed` × 2 |
| `tutorial.light` | entered `hollow_dummies` | "Strike with {light_attack}. Press it again to chain up to three blows." | 3 light attacks |
| `tutorial.heavy` | requires `tutorial.light.done` | "{heavy_attack} is a slower, harder blow that breaks guards and staggers." | a heavy attack |
| `tutorial.footfall` | requires `tutorial.heavy.done` | "Stamp with {slot_1}: Heavy Footfall hits everything around you." | `ability.heavy_footfall` used |
| `tutorial.lock` | requires `tutorial.footfall.done` | "Press {lock_target} to lock on. Flick or scroll to switch targets." | `lock_target_changed` (player, a target) |
| `tutorial.block` | `telegraph_started` aimed at the player by a `Parryable` action | "Raise your guard with {block}. Block just as the blow lands to parry it." | the player BLOCKED or PARRIED a hit |
| `tutorial.dodge` | requires `tutorial.block.done`; `telegraph_started` aimed at the player | "Dodge with {dodge} as the strike lands: for a moment nothing can touch you." | the player EVADED a hit |
| `tutorial.shrine` | `shrine_activated` | "Shrines heal you and save your progress. Press {interact} to rest, change abilities or grow." | `interacted` with a shrine, or 15 s |
| `tutorial.soldier_guard` | entered `forest_hunters` | "Soldiers guard their front. Circle behind them, or break the guard with {heavy_attack}." | 10 s |
| `tutorial.grab` | `staggered` within 6 m, grabbable | "Staggered! Press {interact} to grab it, then {light_attack} to throw." | `grab_started` |
| `tutorial.hurl` | entered `grove`, `min_stage` 2 | "Lock on to the cairn ({lock_target}) and hurl a boulder ({slot_5}). First person ({camera_toggle}) helps you aim." | `ability.boulder_hurl` used |
| `tutorial.attributes` | level ≥ 2, `defer_in_combat` | "You have attribute points. Rest at a shrine or open the inventory ({inventory}) to spend them." | `attributes_changed`, or 20 s |
| `tutorial.boss_charge` | `boss_phase_changed` phase 2 | "It will charge. Dodge sideways and let it hit the wall or a pillar." | 8 s |

### 4.6 The village choice (`quest.village` and its two branches; no farming)

| Quest | Starts when | Stages (marker) | Ends |
| --- | --- | --- | --- |
| `quest.village` | entered `valley.area.village` | `meet`: speak with Elder Maren (`elder`; flag `dialogue.elder.met` or `quest.village.outcome`) → `resolve`: help Thornwick or make them open the bridge (`elder`; flag `quest.village.outcome`) | on any outcome |
| `quest.village_cache` | flag `quest.village.offer` equals `cache` | `get_cache`: recover the stolen supplies from the quarry (`quarry_cache`; `has_item item.supply_cache`) → `return_cache`: bring them to the elder (`elder`; outcome equals `help_cache`) | abandoned when the outcome is set to anything else |
| `quest.village_ogre` | flag `quest.village.offer` equals `ogre` | `kill_field_ogre`: drive the ogre out of the fields (`field_ogre`; killed `valley.fields.ogre`) → `report`: tell the elder (`elder`; outcome equals `help_ogre`) | abandoned when the outcome is set to anything else |

The tracker shows the main objective plus the active branch (otherwise `quest.village`).

| Outcome | How | Rewards (once-flag) | World effect |
| --- | --- | --- | --- |
| `help_cache` | Take `valley.quarry.cache` (fight the raiders), return to the elder → "Here is your supply cache" | 120 XP + 2 iron ingots + Ancestral Mend learned (`reward.village.help`) | Gate opens (`gate_open`); village forge usable; villagers stay calm |
| `help_ogre` | Kill `valley.fields.ogre`, report → "The ogre won't trouble you again" | Same as above (`reward.village.help`) | Same |
| `intimidate` | Dialogue "[Loom over them] Open the bridge. Now." (stage ≥ 2) | 40 XP + Thunder Roar learned (`reward.village.intimidate`); **no kill XP, no iron** | Guards stand down to their posts; villagers hide; village forge closed |
| `force` | Smash the barricade (stage ≥ 2). This is the **only** way to set `force`. | Kill XP only | `faction.village.hostile`: guards fight, villagers flee, the elder says "Get away from us!"; after the boss, `encounter.village_ambush` waits in the square |

- Attacking villagers or guards (decision 17: the first hit warns, a second within 30 s turns the village hostile) closes the help options in dialogue but never sets the outcome; the barricade still has to be smashed.
- Repeating dialogue never grants anything again: XP, items and abilities are gated by once-flags, and outcome flags are first-write-wins.
- The barricade opens for every outcome. A stage-1 player can still use the help paths, so no state blocks the bridge.
- The end screen's village line names the outcome (P13).

### 4.7 Progression schedule: XP budget, levels, abilities, weapons, loot and the upgrade

**XP.**
- Thresholds (cumulative): L2 100, L3 250, L4 450, L5 700, L6 1,000.
- Kill XP: wolf 15, soldier 20, archer 25, mage 30, ogre 60, Ogre King 300 (sparring post 0).
- Prop XP: practice gate 20, cart barricade 30.
- Guaranteed XP counts only mandatory stages, the two mandatory kills (forest ogre, boss) and the **worst** village outcome (`force`, whose barricade gives 30). No tutorial and no optional kills (the forest hunters are effectively mandatory but are not counted).

| Gate | Guaranteed XP (worst outcome) | Needed |
| --- | --- | --- |
| Before `grove` | 60 + 30 + 60 (ogre kill) + 110 = **260** | ≥ 250 (L3) ✓ |
| End of `gate` | 260 + 30 + 30 + 20 + 30 (barricade) + 60 + 20 (gate) = **450** | ≥ 450 (L4) ✓ (`intimidate` 460, `help` ≥ 540) |
| Before `boss` | 450 + 0 + 40 = **490** | ≥ 450 ✓ |
| Before `grow3` | 490 + 120 + 300 = **910** | ≥ 700 (L5) ✓ |
| End of the slice | 910 + 30 + 20 + 40 + 50 = **1,050** | L6 |

L2 typically arrives after wolves A (60 + 30 + 45 = 135), before the forest hunters, so Stone Skin and Crushing Grip are new when the first soldiers are met. L4 arrives at the practice gate at the latest, so Roar, Mend and Titan Surge are in hand for the courtyard. Typical help-path players reach L5 before the boss; stage 3 is still gated by the boss flag, and the surplus becomes attribute points. P15's `test_xp_budget` keeps these inequalities true under tuning, for every outcome.

**Abilities** (8 + ultimate):

| Unlock | Ability | Slot | Cost / cooldown | Key numbers |
| --- | --- | --- | --- | --- |
| L1 | Heavy Footfall | 1 | 20 stamina / 8 s | Cylinder r 3/4/5 by stage, h 2.6; P40 × 1.2; poise 25 |
| L1 | Sweeping Blow | 2 | 18 stamina / 7 s | Sector 120°, r = melee reach (3.5/4.8/6.5); P40 × 1.2; poise 20 |
| L2 | Stone Skin | 3 | 25 essence / 20 s | +30 armor 6 s (refresh, no stack) |
| L2 | Crushing Grip | 4 | 20 stamina / 10 s | Grab + P40 × 1.5 on a `small` target, then release |
| Stage 2 (L3) | Boulder Hurl | 5 | 15 stamina / 6 s | `projectile` category; arc 28 m/s, gravity 9.8, range 25 m; P40 × 1.6; poise 30; splash 1.5 m |
| L3 | Runic Bolt | 6 | 15 essence / 4 s | `magic`; projectile 35 m/s, range 25 m; P40 Intellect; arcane; poise 15 (interrupts mages) |
| L4 (help: taught at the village) | Ancestral Mend | 7 | 30 essence / 15 s | 100 health over 4 s (8 × 12.5) |
| L4 (intimidate: taught at the village) | Thunder Roar | 8 | 25 essence / 14 s | r 6; morale −20; slow 30% for 3 s |
| L4 | Titan Surge (ultimate) | U | 100 fury | +25% damage and poise for 6 s; no fury gain; no invulnerability |

The Grove therefore brings three things (growth, Boulder Hurl, Runic Bolt), and the "new ability" notices wait until the player is out of combat.

**Weapons** (each base weapon fits up to stage 2; reforging gives the variant that fits stage 3):

| Weapon | Where | Multiplier | Length / radius (m, stage 1) | Fits | Moveset | Reforged (2 iron) |
| --- | --- | --- | --- | --- | --- | --- |
| Oak Club | Start | 1.0 | 1.85 / 0.45 | ≤ 2 | Light 1–3 and heavy (M1) | Reinforced Club 1.15, fits 3 |
| Kingsguard Sword | Ruins armory rack | 0.95 | 1.6 / 0.3 | ≤ 2 | Light 0.16 / 0.12 / 0.24 ×3 (1.0 / 1.05 / 1.2); heavy thrust 1.6; poise 10 / 30 | Kingsguard Blade 1.10, fits 3 |
| Raider's Maul (hammer) | Quarry rack | 1.2 | 1.5 / 0.5 | ≤ 2 | Light 0.28 / 0.15 / 0.38 ×2 (1.0 / 1.2); heavy slam 2.0; poise 18 / 50 | Warmaul 1.35, fits 3 |
| Uprooted Oak (tree) | Stage 3, ancient oak | 1.4 | 7.5 / 0.9, fixed size | stage 3 only | Wide sweeps (yaw ±100°) ×2, heavy smash; `TreeWeapon` | — |

**Loot and items.**
- Wood scrap: fences.
- Iron ingot ×5: village help reward 2, quarry chest 1, armory crate 1, Ogre King 1.
- Quest and trophy items: supply cache (quest), ogre tusk (trophy), crown (quest, the end of the slice).

**The one upgrade interaction:** a forge reforges the equipped weapon into its reinforced variant for 2 iron: more damage, and it now fits stage 3. Forges are at the village smithy (help outcomes only) and the ruins Giantforge (always). When the upgrade is possible:

| Outcome | Iron before the boss | Upgrade |
| --- | --- | --- |
| `help_cache` | 2 + quarry chest 1 + armory 1 = 4 | Before the boss (the village forge at once, or the Giantforge) |
| `help_ogre` | 2 + armory 1 = 3 | Before the boss |
| `intimidate`, `force` | armory 1 (+ 1 with an optional quarry detour) | Before the boss only with the quarry detour; otherwise after it (the Ogre King drops 1 iron), at the Giantforge on the return leg |

### 4.8 How growth changes play (spec §2: interactions, reach, positioning, enemy tactics)

Profile values for P05:

| Field | Stage 1 | Stage 2 | Stage 3 |
| --- | --- | --- | --- |
| `weapon_scale` | 1.0 | 1.5 | 2.1667 |
| `grab_reach_m` (melee reach + 0.5) | 4.0 | 5.3 | 7.0 |
| `grab_lunge_m` | 2.0 | 2.7 | 3.5 |
| `grab_capacity` | small | small | medium |
| `grab_attach` | torso_fist, scruff | torso_fist, scruff | torso_fist, scruff, two_hand |
| `resource_bonus` | — | health +150, stamina +10 | health +300, stamina +20 |
| `arc_pitch_offset_deg` | 0 | −6 | −12 (P05 may deepen to −10 / −18 for the wolf test) |
| `dodge_style` | roll | sidestep | sidestep |
| `camera_orbit_scale` | 1.0 | 1.5 | 2.17 |
| `footstep_shake` | 0 | 0.05 | 0.12 |
| `unlocks` | — | `ability.boulder_hurl` | — |
| `nav_layers` | 8 | 4 | 4 |

The other profile values (height, capsule, speeds, camera, lock range 35/40/45 m and half-angle 60/55/50°) stay as shipped.

| Aspect | Stage 1 (3.66 m) | Stage 2 (5.49 m) | Stage 3 (7.92 m) |
| --- | --- | --- | --- |
| Interactions | Grab staggered soldiers and wolves (4 m reach plus a 2 m lunge); shrines, NPCs, pickups; cannot move the barricade; cannot uproot oaks | Boulder Hurl (cairn, archers on walls); can smash the barricade; intimidation option appears; weapons reach their fit limit | Uproot oaks (tree weapon); grab and throw staggered ogres with both hands; break the Deadfall; unreforged weapons are too small; the Citadel stays sealed (stage 4) |
| Reach | Club ≈ 3.5 m; Footfall 3 m; Sweep 3.5 m; grab 4 m (+2) | ≈ 4.8–5.0 m; Footfall 4 m; Sweep 4.8 m; grab 5.3 m (+2.7) | Reforged ≈ 6.5–7.3 m (unreforged ≈ 5.5–6 m; tree ≈ 9 m); Footfall 5 m; Sweep 6.5 m; grab 7 m (+3.5) |
| Positioning and traversal | Fits 4 m village alleys (small-giant nav); agile roll dodge; camera 6.5 m | Main streets only; weighty sidestep; camera 9 m; looks over 5 m walls; strikes soldiers from beyond their spears | Towers over cottages; camera 12 m; light arcs tilt down 12° to reach humans; the return journey is fast |
| Body | 500 health | +150 health, +10 stamina (percentage kept) | +300 health, +20 stamina |
| Enemy tactics | The forest hunters advance to the legs and take turns (2 tokens); wolves flank and lunge; the forest ogre must be punished in its recovery | Soldiers outmatched (ratio 3.05 ≥ 2.5): they hold formation (markers or an ad-hoc line) with guards up, brace-counter a giant that steps into their spears, and lose morale ×1.5. Wolves harass from behind; archers keep 15.6–26 m and spread; the first mage (road patrol) slows and shields | Awe (ratio 4.4 ≥ 4.0): soldiers drop to 35 morale on sight, so one Roar or one death breaks them; the return patrol on the bridge scatters; the Barrow ogre is staggered by two heavies and thrown into its wolves; the world feels smaller |

### 4.9 Pacing (target 26 minutes for a human; prototype pacing)

Segments are defined by quest stages, so the bot measures them exactly. Human targets assume a first-time player; the bot reports raw simulated time and a human estimate (§5.1).

| # | Segment (`quest.main` stages) | Content | Human target (min) | Range (min) |
| --- | --- | --- | --- | --- |
| 1 | start → `leave_hollow` | Wake, both cameras, move, dummies (light, heavy, Footfall), sparring post (block, parry, dodge), lock, shrine | 3.0 | 2–4 |
| 2 | → `ogre` | Wolves A; waystone; L2 (Stone Skin, Grip); forest hunters (stage-1 soldiers, grab); forest ogre | 5.5 | 4–7 |
| 3 | → `hurl` | Grove: L3, growth to stage 2, Boulder Hurl at the cairn, Runic Bolt; Deadfall seen | 2.0 | 1.5–2.5 |
| 4 | → `village` | Road patrol (outmatched soldiers, the first mage); Thornwick shrine; the elder; help (quarry or field ogre) / intimidate / force; village forge | 4.0 | 1.5–7 |
| 5 | → `causeway` | Bridge; gate fight; practice gate (cracks, breaks); waystone; L4 (Mend, Roar, Surge); courtyard; armory (sword, Giantforge) | 4.0 | 3–5 |
| 6 | → `boss` | Kingsfall shrine; antechamber; Ogre King (2 phases); typically one retry | 4.0 | 2.5–6 |
| 7 | → `crown` | Growth to stage 3; uproot the oak; Giantforge if not yet used; return patrol on the bridge (awe); ambush if hostile; Deadfall; waystone; Barrow wardens; crown; end screen | 3.5 | 2.5–4.5 |
| | **Total** | | **26.0** | **20–30** (extremes about 17–36) |

---

## 5. M5 test and tuning plan

### 5.1 Valley bot (P17a)

**Command:**
```
tools/gd.sh --headless --path . --fixed-fps 60 -- --no-user-settings --save-dir=user://bot_saves \
  --mode=valley --new-game --scenario=valley --autoplay=2400 \
  --bot-village=help_cache|help_ogre|intimidate|force --bot-skill=novice|expert [--bot-assist] [--bot-seed=N]
```
`--autoplay` is a hard timeout. The default skill is `novice`.

**Structure.** `scripts/debug/valley_bot.gd` is dispatched from Autopilot. Its state lives in statics, so it survives checkpoint reloads. The bot node runs with `PROCESS_MODE_ALWAYS`.

**Skill profiles.**

| | Novice (default; balance targets) | Expert (skill ceiling) |
| --- | --- | --- |
| What it reacts to | `telegraph_started` events aimed at the player, and the windup start (`ability_started`) of enemies that are on screen within 8 m. Never controller phases. | The controller phase and ticks-to-active of every enemy in reach |
| Reaction latency | 15 ticks (250 ms) | 0–2 ticks |
| Defence | Attempts a timed parry 50% of the time (otherwise a late block or none); dodges a dodgeable threat 70% of the time, 10% of those in the wrong direction | Parries 6–14 ticks before active; always dodges lunges, charges and slams |
| Ability rules | As below, with a 1 s decision delay | As below |

Random choices use `Sim.rng_for("bot")`, seeded by `--bot-seed`.

**Goal-driven.** Every 6 ticks it reads `Quests.current_objective()`, including the stage `bot` hint, and executes it:

| Bot action | Behaviour |
| --- | --- |
| `go` | Path on the current profile's nav layers (`NavigationServer3D.map_get_path(map, from, to, true, player.nav_layers)`), re-planned every 2 s or when more than 3 m off path. Stuck recovery: sidestep and jump; re-plan; the `bot_route_points` fallback; as a last resort, a teleport to the next path point (recorded). |
| `fight_encounter` / `kill` / `attack` | Lock the nearest threat; approach to 0.8 × reach. Light chain; heavy on a staggered or guarding target; grab a staggered grabbable target and throw it at another enemy. Defence per the skill profile. Abilities by rule: Footfall/Sweep with ≥ 2 enemies near, Stone Skin at boss start, Mend below 50% health, Runic Bolt on a casting mage or an archer beyond 10 m, Boulder Hurl on archers beyond 10 m, Roar with ≥ 3 nearby, Surge at 100 fury against the boss or ≥ 3 enemies, Grip on staggered small targets. Against the boss in phase 2 it baits the charge with its back to a pillar or wall. |
| `break` / `hurl_at` | Heavy attacks on the prop (tree weapon equipped for the Deadfall); Boulder Hurl locked on the cairn. |
| `interact` / `talk` / `grow` / `rest` / `equip` | Move within radius, then call the public API directly, without opening a screen: `Quests.start_dialogue` and `Quests.dialogue.choose(policy index)`, `shrine.grow(player, stage)`, `shrine.rest(player)`, `forge.upgrade(player)` when 2 iron are held, `progression.allocate` (Strength/Endurance alternating), `equipment.equip_weapon` (the sword when found, the reforged weapon when made). Pickups, racks and the oak use the real `interact` edge. If any pausing screen opens anyway, the bot closes it with `ScreenStack.close_all_static()`. |

**Village policy sub-plan:** `help_cache` → quarry, cache, back to the elder; `help_ogre` → fields; `intimidate` → the dialogue choice; `force` → smash the barricade.

**Deaths.** On death the bot waits for the death overlay, emits `reload_checkpoint_requested("death")` (as Enter does), and resumes from the current objective. In assisted mode (`--bot-assist`) it re-applies the hidden `status.bot_assist` (damage taken × 0.25) after every load; deaths are still counted, but they never trigger the death watchdog.

**Watchdogs.** Per-objective timeout of 240 s simulated (boss 480 s), at most 5 deaths per objective (unassisted runs only), and stuck detection (the distance to the objective has not dropped by 1 m in 6 s). A breach runs the diagnosis and exits with code 2.

**Diagnosis** (`bot_diagnosis.gd`). On a breach it checks (1) whether a path exists on the player's layers from the player to the objective marker, with breakable links treated as open, and (2) whether the objective's condition can still be satisfied in the current world (targets alive or killed as required, a destroy target breakable with the current weapon and stage, required flags settable). It classifies the breach as `world_blocked` (no path, or an unsatisfiable condition: a softlock) or `bot_failed` (the bot could not do something possible), and records the evidence.

**Human estimate.** `human_estimate_s` = raw simulated seconds + 4 s per dialogue node shown + (dialogue and tutorial text length) / 15 characters per second + 8 s per screen a player would open (shrine, forge, dialogue, inventory, end) + 10 s per district entered for the first time.

**Metrics** in `AUTOPILOT_RESULT {json}`:
- run: policy, skill, assist, seed, `simulated_s`, `human_estimate_s`, completed, village outcome, final flags hash;
- `segments` (§4.9, by quest stage): raw seconds, human estimate, combat seconds vs traversal seconds, deaths, damage taken, minimum health fraction, health on arrival at each checkpoint, rests used;
- `objectives`: id, start/end tick, seconds, deaths, damage taken, damage dealt;
- `deaths`: `[{tick, segment, killer_id, killer_archetype, action_id}]`;
- damage taken by archetype and by action id;
- readability: hits taken from an attacker that was off-camera when its windup started, and hits that landed less than 0.45 s after their telegraph (counts and share of all hits taken);
- time-to-kill per archetype per stage; mean engagement distance per stage;
- AI-state histogram per stage: seconds enemies spent in each state (HOLD, FLEE, ROUTED, ATTACK, …) and in harass, spread and kite behaviour, which shows whether tactics change with growth;
- abilities: uses per action id, damage share, and the "used when ready" ratio; `attacks` (light/heavy), `blocks`, `parries`, `dodges`, `grabs`, `throws`;
- the XP and level timeline (tick, level), growth ticks;
- `stuck_events`: `[{tick, position, objective, recovered_by}]`, every one, recovered or not (a heatmap list);
- `rewards` (once-flags and loot by world id; duplicates flagged);
- maximum active enemies, maximum debris;
- `errors`, `warnings`, `error_samples`;
- CPU per tick p95/p99 (PerfProbe);
- `diagnosis` (on a breach).

### 5.2 30-minute stability run (P17a)

`--scenario=valley --autoplay=1800 --bot-loop --bot-assist --bot-village=help_cache`. After `slice.completed` the bot starts a new game and continues with the next village policy in rotation; on a watchdog breach it records the diagnosis, reloads the checkpoint, and continues.

**Invariants checked every tick** (any failure is recorded and exits with code 3):
- player y > −50, no NaN positions;
- lock target alive or empty;
- `Sim.pending_hit_count()` < 512;
- debris ≤ 40;
- tokens ≤ 2 per target (melee) and ≤ 2 ranged tokens per target;
- every world id rewarded at most once;
- no once-flag rewarded twice;
- active combatants ≤ 12;
- no entity registered twice;
- no pausing screen open for more than 2 s of real time.

**Every 60 s:** `Performance.OBJECT_NODE_COUNT`, `OBJECT_ORPHAN_NODE_COUNT` and `MEMORY_STATIC`. Failure is monotonic growth across 5 consecutive reload cycles of more than 10% of nodes.

P02's error counter makes any engine or script error a failure.

**Pass:** no crash, softlock (a `world_blocked` diagnosis), duplicated reward or unrecoverable targeting state (spec §16). `bot_failed` breaches are reported and tuned in P17b but are not stability failures.

### 5.3 Stress route (P14)

`--level=res://scenes/test/stress_arena.tscn --scenario=stress --autoplay=300 --graphics=low`. In the container it runs with `--fixed-fps 60` to get CPU per tick. On the reference PC it runs **without** `--fixed-fps` (real frame times) at `--resolution 1920x1080`, using `Giantborn.console.exe`. The player carries the hidden `status.debug_invulnerable` during this scenario only.

**Content:** 12 combatants, 20 breakables, 40 debris (§3.16). Reported: CPU ms per tick p50/p95/p99, frame ms p50/p95/p99, GPU and CPU render ms (N/A headless), draw calls, nodes, memory, active combatants, debris, hits resolved.

### 5.4 Performance measurement and budgets (P14, P17a, P18)

| Budget | Value | Where measured |
| --- | --- | --- |
| Frame time | p95 ≤ 16.7 ms, p99 < 33.3 ms at 1080p with `--graphics=low` (spec) | Reference PC, exported build: **owner** |
| GPU render time | Reported separately from CPU (spec §16) | Reference PC: **owner**; N/A in the container |
| Sim CPU per tick | p95 ≤ 8 ms in stress and Valley | Container (indicative) and PC |
| Draw calls | ≤ 250 in any Valley view | PerfProbe (`valley_walk`) |
| Distant actors | Tier 2 shows a one-box proxy (low-detail background representation) | P04 test; `valley_walk` draw-call difference |
| Active combatants | ≤ 12 (director) | Bot invariant |
| Valley load | ≤ 3 s headless, ≤ 6 s web (documented loading screen) | Slow test, P18 browser |
| Navmesh files | ≤ 100 KB each | P10b test |
| Web `.pck` packed | ≤ 4 MB | P18 |

**Web-specific mitigations** (single thread; owner P14; applied by LevelRoot from the level record's `web_overrides`):
- `OS.has_feature("web")` forces the `low` preset: shadow distance 60 m, scenery `visibility_range_end` 160 m, MSAA off.
- AI tier-1 rates apply beyond 30 m instead of 40 m.

### 5.5 Usability script and controller checks (P16)

- `docs/USABILITY_SCRIPT.md`:
  - a 3-player protocol: 5 minutes of Sandbox free play (with its sparring post), then the first 10 Valley minutes;
  - the spec §16 tutorial encounter is Giant's Hollow (dummies and the sparring post) plus the first wolf pack (decision 28);
  - the success criteria from spec §16 (at least 2 of 3 finish the tutorial encounter unaided and correctly identify heavy attacks, blocking and dodge timing);
  - an observation sheet: confusion points, camera discomfort, accidental ability use, time to defeat;
  - a post-session questionnaire, and how to report results.
- The controller pass is automated with synthetic joypad events (P16 tests).
- A real-pad checklist is in the script. Real-pad and human results are **NOT RUN** until the owner runs them. The recommended owner checkpoints (after W1 and W8, §1.3) use the same sheet.

### 5.6 Balance loop (P17b)

1. **Run matrix per iteration** (through `tools/run_bots.sh`, started in the background and polled; at most 3 runs at once; 900 s timeout each; about 20–25 minutes of wall time):
   - novice × {`help_cache`, `help_ogre`, `intimidate`} × 5 seeds, and novice × `force` × 3 seeds;
   - expert × the 4 policies × 1 seed.
2. **Targets** (novice, unassisted, median over seeds unless noted):
   - human estimate 20–30 minutes in total, and each segment within its §4.9 range; raw simulated time 13–26 minutes (a sanity band);
   - deaths 1–4 in total, 1–2 of them at the boss, and at most 2 in any other segment;
   - damage taken ≤ 0.6 × maximum health in segments 2, 4 and 5 (where no healing exists between checkpoints before L4), and ≤ 1.0 × maximum health per boss attempt;
   - at least 4 of 5 seeds complete each policy;
   - readability: under 20% of the hits taken come from attackers that were off-camera at windup or land within 0.45 s of their telegraph;
   - growth shows in behaviour: soldiers spend 0% of engaged time in HOLD at stage 1, at least 50% in HOLD at stage 2, and at least 50% in FLEE or ROUTED at stage 3; soldier time-to-kill at stage 2 is at most 60% of stage 1;
   - every ability is used at least once per run, and no single ability deals more than 40% of ability damage;
   - expert: completes all four policies with 0–1 deaths (if it dies more, the game is too hard for anyone);
   - the XP budget test still passes.
3. **Adjust data only:**
   - enemy health, damage and windups (keeping the spec floors: windup ≥ 0.45 s, major ≥ 0.8 s);
   - encounter counts and positions (layout nudges are logged and followed by a rebuild and re-bake);
   - XP;
   - boss phase numbers and telegraph sizes.

   Log each change with its reason in `docs/BALANCE_LOG.md`, then re-run. Stop after at most 3 iterations or when all targets are met, then run one final confirmation matrix.
4. Never tune by deleting gameplay behaviour (spec §16).

### 5.7 The "how it plays" report (P17b → `docs/HOW_IT_PLAYS.md`)

The report contains:
- run tables per policy, skill and seed (segment times raw and human estimate, deaths, damage, abilities used, levels and growth times);
- novice versus expert: where skill matters and by how much;
- death causes (killer archetype and action), the readability numbers, and the stuck-event heatmap;
- the growth evidence: AI-state histograms and time-to-kill per stage;
- 30-minute stability results;
- stress and Valley performance numbers;
- what changed in tuning and why;
- observations: where the novice bot struggled and therefore where humans likely will, which abilities dominate, whether growth "feels" different;
- known issues;
- "what to try first" for the owner (5-minute and 25-minute tours);
- the list of NOT RUN gates and how to run them.

---

## 6. Risks and mitigations

| # | Risk | Mitigation |
| --- | --- | --- |
| 1 | Scope: 21 packages, about 54k lines, twelve waves | Strict per-package acceptance. If late, cut in this order: `force` outcome polish → hammer → field-ogre help option → village ambush → Barrow wardens (the crown stays) → tutorial prompts 13 → 8. None of these cuts touches a spec gate. |
| 2 | Merge conflicts in shared files | Pre-declared registries, package anchors with an anchor test, the single-owner table (§1.5), the cross-lane API rule and the wave merge procedure (§1.2). The second merge resolves only additive anchor hunks. |
| 3 | Generated `.tscn` churn and id noise | `SceneKit.save` strips the random `unique_id=` attributes (verified safe), so a regenerated scene only differs when its content does; a generated-file conflict is resolved by regenerating; never hand-edit. |
| 4 | Offline navmesh not matching collision | Both are generated from the same layout list. Slow tests compare path endpoints and sample capsule clearance along paths. Links are tested both closed and open. |
| 5 | Web single-thread performance in the Valley | MultiMesh visuals, fog and visibility ranges, budget 12, LOD tiers with a one-box proxy, the forced `low` preset. P14 measures early (W7). If the budget is missed, reduce scenery density before gameplay. |
| 6 | Bot flakiness (physics varies across machines) | Goal-driven bot with timeouts and re-plans; results judged by ranges over 3–5 seeds; fixed fps; the diagnosis separates softlocks (`world_blocked`) from bot mistakes (`bot_failed`); stability uses the assisted bot. |
| 7 | Grab and throw edge cases (bodies inside geometry, stuck GRABBED) | A validated release position with fallbacks. The controller guard prevents stagger while GRABBED. Every release path is tested, including scene unload. |
| 8 | Growth clearance false positives or negatives | Shrine pads are authored open and tested at stage 3. A failure changes nothing (tested). The debug path uses the same apply. |
| 9 | Jolt and uniform shape scaling | Resize shapes from base sizes; never node-scale collision. |
| 10 | Save persistence on the web (IndexedDB, rename) | `SaveIO` temp+rename tested in Chromium by P18. Fallback: on rename failure, write directly and keep the backup. The message is shown on Continue. |
| 11 | Balance (boss too hard or easy; pacing off; the bot plays nothing like a person) | XP budget test; the novice bot (perception-limited, 250 ms latency, imperfect defence) sets the targets and the expert shows the ceiling; a human time estimate; death-cause and readability metrics; at most 3 tuning iterations; the human usability script and owner checkpoints. |
| 12 | Test runtime creep | 45 s default budget; `tests/slow` behind `--slow`; each package reports its added time. |
| 13 | Determinism broken by new random draws | `Sim.rng_for` streams; crits pinned on `Sim.rng`; the test asserts the 37/66/44 sequence stays unchanged after P01. |
| 14 | Agent context limits on big packages | No package is planned above ~3,300 lines; the three largest areas were split (P10a/P10b, P11a/P11b, P17a/P17b) and P01's new record schemas moved to the packages that use them. Each §3 section is self-contained and points to §2 contracts. |
| 15 | Pausing screens hanging tests or the bot | `ResetHooks` closes leftover screens after each test and reports them as failures; the bot never opens screen-backed UIs, runs `PROCESS_MODE_ALWAYS`, and checks that no pausing screen stays open for more than 2 s. |
| 16 | Hidden coupling through `GameData.get_record` mutation | The rule: copy records before writing; character state lives in the save dictionary, never in records. Tests change records only through `GameData.override_record`, which `ResetHooks` restores. |
| 17 | "Full game" expectation mismatch | §0.4 deferred list is explicit in the handoff and README; the end screen labels the build "Vertical slice, prototype pacing". |
| 18 | Human-only gates (usability, real PC, real pad) | Scripts and commands delivered; reported as NOT RUN; P18 asks the owner for the reference-PC table. |
| 19 | Two lanes running Godot at once share `user://` | `tools/gd.sh` gives every worktree its own `XDG_DATA_HOME` (verified on 4.6.3). |
| 20 | A package calls an API its wave partner is still writing | The cross-lane API rule (§1.2), defensive access for the few listed symbols, and listeners on events P01 declared up front instead of direct calls. |
| 21 | Bot batches outlast a single tool call | `tools/run_bots.sh` runs in the background with per-run timeouts; P17b polls the output folder; no foreground command runs longer than 10 minutes. |

---

## 7. Review log

Three reviews (spec coverage, feasibility, gameplay) were folded into this revision. Every finding is listed. "Accepted" means the suggested fix was adopted as written. "Changed" means the finding was accepted but the fix was altered, with the reason. "Rejected" means the suggested fix was not adopted, with the reason. Claims about the existing code were re-checked against `e89001f` before they were written into the plan.

### 7.1 Spec coverage review

| # | Finding | Resolution | Where |
| --- | --- | --- | --- |
| 1 | Weapons grow automatically, against the Giantforge rule | **Changed.** Added `fit_max_stage`; reforging raises the fit and adds damage. The club fits stage 2, not stage 1 as suggested: growth to stage 2 happens at the Grove, long before any forge, so a club that fits only stage 1 would be undersized for the whole middle of the slice. Above its fit a weapon keeps its last fitted size with a warning instead of being refused, because refusing leaves the giant without a weapon. | Decision 3, §2.8.2, §3.8, §3.14, §4.7 |
| 2 | No grab attachment profile | Accepted: `grab_attach` on enemies, `grab_attach` lists on profiles, `Anchors/Grab`, reason `no_attach_profile` and its test. | Decision 16, §2.8.2, §2.12, §3.7 |
| 3 | Structural damage stages deferred; no cosmetic props; health not saved | Accepted: the practice gate is structural (intact → cracked → broken), every persistent prop saves stage and health, bushes and banners are cosmetic; tests for both. | Decision 23, §2.8.4, §2.9, §3.8, §0.4 |
| 4 | Enemy projectiles track through the whole windup | Accepted: the aim point is stored at `tracking_fraction × windup` (0.6) and the aim line shows it; a 4 m sidestep test. The existing `tracking_fraction` action field is reused. | Decision 24, §2.7.2, §3.3, §3.9 |
| 5 | Neutral guards can be locked, soft-targeted and hit by AoE | **Changed.** Eligibility is `TargetingRules.player_may_target` (team ENEMY, or NEUTRAL with no faction) rather than "team ENEMY only", because the practice dummy is team NEUTRAL and lockable (`tools/build_scenes.gd` line 376, `data/props/practice_dummy.json`) and the tutorial locks it. Player area effects skip faction members; the suggested tests were added. | Decision 17, §2.6.4, §3.3, §3.13 |
| 6 | The boss charge rarely reaches a wall | Accepted, merged with gameplay #10: the charge runs until it hits WORLD (wall or one of four pillars) with a 6 s cap, and a test of 10 seeded charges that all end in `boss_wall_recover`. | Decision 27, §3.12, §4.4 |
| 7 | No test for an obscured crosshair | Accepted: a crosshair probe in the 3-size route, first person while holding (P07) and with each weapon (P08); the camera culls the head when its arm is very short. The probe intersects the ray with the meshes' local bounds, because the giant's visuals have no collision shapes. | §0.2, §2.2, §3.5, §3.7, §3.8 |
| 8 | The Grove shrine is not safe from the road patrol | Accepted both fixes: the patrol requires `reward.main.grove` and moved 56 m from the Grove; a content test keeps every spawn and patrol point 35 m from growth pads. The Thornwick shrine moved away from the guard posts (see gameplay #2). | §4.3, §4.4, §3.17 |
| 9 | Boulder Hurl's category against the projectile-only cairn is unspecified | Accepted: `category: "projectile"`, the splash inherits it, a Boulder Hurl → cairn test where a light and a Runic Bolt do nothing, and a quest-critical content check. | §2.8.2, §2.8.4, §3.3, §3.7, §3.17 |
| 10 | `regroup_needs_leader` defaults to false | **Changed.** Default true, and a commander in the courtyard and the return patrol. With no authored commander the leader is "a living non-fleeing ally within 20 m", not "the highest-morale unit", which would nearly always exist and make the rule a no-op. A unit without a leader routs; routed units count as cleared. | Decision 26, §2.8.2, §3.4, §4.4 |
| 11 | Outmatched archers outrange their sight | Accepted: archers have `sight_range_m` 32, and a 10 s band-holding test. | §3.9, §4.4 |
| 12 | Boss attacks are weighted picks, not alternation | Accepted: phase `sequence` (phase 1 strictly alternates; phase 2 adds the charge every third decision) with a no-repeat test. | §2.8.2, §3.12 |
| 13 | The Stone Skin re-cast test cannot pass through the cooldown | Accepted: the refresh is tested with a cooldown override, and the real record's re-cast is rejected with `cooldown`. | §3.1, §3.3 |
| 14 | Dexterity must not change active, parry or dodge windows | Accepted: a dedicated test; `recovery_scale` touches attack recovery only. | §2.6.1, §3.1, §3.14 |
| 15 | Crushing Grip would crush staggered ogres at stage 3 | Accepted: `grab.max_mass: small` and the `too_heavy_to_crush` reason. | Decision 16, §3.7 |
| 16 | Ancestry is not saved or shown | Accepted: `ancestry` in the character save and on the Attributes screen; round-trip tested. | Decision 20, §2.9, §3.6, §3.14 |
| 17 | Every stage uses the same nav layer | Accepted the per-stage layer: a small-giant layer (8) for stage 1 and the giant layer (4) for stages 2–3, switched on growth and tested. | Decision 29, §2.2, §3.5, §3.11 |
| 18 | No threat values, cairn lock data or large-target lock anchors | Accepted: threat per role, the cairn lockable at 0.05, `Anchors/{Torso,KneeL,KneeR}` on the ogre and boss with low-anchor framing and a test. | §2.12, §3.12, §4.4 |
| 19 | New movesets and enemies might not grant fury | Accepted: every light/heavy moveset carries `BasicAttack`, every enemy sets `grants_fury`, a validator warning, and a sword fury test. | §2.8.2, §3.1, §3.8 |
| 20 | Footstep shake ignores the shake setting | Accepted: it goes through `camera_rig.add_shake`, which already multiplies by the `camera_shake` setting (the actual setting name), with a zero-setting test. | §3.5 |
| 21 | No GPU timing; distant actors keep full rigs | Accepted: GPU and CPU render time in PerfProbe (N/A headless), a one-box LOD proxy at tier 2, and the draw-call difference in `valley_walk`. The render-time APIs were checked to exist on 4.6.3. | §3.4, §3.16, §5.4 |
| 22 | No reproducible "1080p low" preset | Accepted: `graphics_quality` with `--graphics=low`, used by the stress command and PERFORMANCE.md. | §3.16, §5.3, §5.4 |
| 23 | The Sandbox has no tutorial encounter; no early human check | Accepted: the tutorial encounter is the Valley's Hollow plus wolves A (decision 28; the Sandbox gets a sparring post); recommended, non-blocking owner checkpoints after W1 and W8. | Decision 28, §1.3, §5.5 |
| 24 | Siege destruction morale is silently missing | Accepted both: listed as deferred, and an `on_morale_event("siege_destroyed")` hook with a unit test. | §0.4, §3.4 |
| 25 | Per-stage lock range and pack switching are untested | Accepted: stage-2 lock and release tests (P05) and wolf-pack switching tests (P04). | §3.4, §3.5 |
| 26 | Flee points can snap to the wrong nav layer; tier 1 never re-paths | Accepted: `region_get_closest_point` on the actor's own layer, confirmed with a layered `map_get_path` (`map_get_closest_point` has no layer filter, verified); a Valley flee test; tier 1 re-paths at most once per second after a failure. | §2.7.3, §3.4, §3.17 |

### 7.2 Feasibility review

| # | Finding | Resolution | Where |
| --- | --- | --- | --- |
| 1 | P02 uses P01 symbols while running in parallel | Accepted: a general cross-lane API rule and an explicit list of P01 symbols P02 must reach defensively (verified that `CombatController` has no `level` today). | §1.2, §2.7.1, §3.2 |
| 2 | Actors do not collide with the blockers layer | Accepted: P04 adds `SceneKit.L_BLOCKER` and `ACTOR_MASK` and uses it in every actor builder (the masks are set at `tools/build_scenes.gd` lines 222–223 and 297–298), with a blocker test and a river-crossing test. | Decision 21, §2.2, §3.4, §3.11 |
| 3 | Parallel test runs share one `user://` | Accepted: `tools/gd.sh` sets `XDG_DATA_HOME` per worktree (verified on 4.6.3); `.userdata/` is git-ignored. | §1.1, §1.2, §3.2 |
| 4 | Contracts contradict each other (`kill`, `Quests.dialogue`, `shrine.rest`) | Accepted all three: `kill` added to `BOT_ACTIONS`, `Quests.dialogue` added to the P13 API, and a public Shrine API. | §2.7.4, §2.8.1, §3.15 |
| 5 | Loot-table references cross lanes in one wave | Accepted, and the schedule removes the problem: P12 now runs in W5 and P11a in W6, so the boss references an existing table; raiders get a per-spawn `loot_table` override; enemy loot is a PlayerProgression listener on `entity_died`, so `enemy_actor.gd` needs no P12 edit. | §2.7.3, §2.8.3, §3.14 |
| 6 | The error counter arrives three waves too late | Accepted: the error counter and the non-zero exit move to P02; the wave-0 check for P01 is a grep for error lines. | §1.1, §3.2 |
| 7 | The stress player cannot survive | Accepted: the hidden `status.debug_invulnerable`, applied only by `--scenario=stress`, and stated in PERFORMANCE.md. | §3.16, §5.3 |
| 8 | P11 is too large | **Changed.** Split as suggested, but P11b (civilians, factions) runs in W7 beside P14 because W6 already has two lanes; the NPC talker moved to P13 so that P13 does not wait for P11b. | §1.3, §3.12, §3.13, §3.15 |
| 9 | P17 is too large and its runs exceed a tool call | Accepted: P17a (bot, metrics, assisted mode, stability) and P17b (balance runs, report); background runs with per-run timeouts and polling. | §1.3, §3.19, §3.20, §5.6 |
| 10 | P10 is too large and risky | Accepted both suggestions: P10a (level framework and director on a test level, W4) and P10b (Valley blockout; dressing moved to P15). | §1.3, §3.10, §3.11 |
| 11 | P01 is too large | Accepted: an optional schema registry; the `shrine`, `level`, `encounter`, `loot_table`, `npc`, `dialogue`, `quest` and `tutorial_prompt` modules move to their consumers, and later fields are added at anchors. All enum values stay in P01. | §2.8.1, §3.1 |
| 12 | `unique_id` churn; wrong import/build/test order | Accepted: import → build → import → tests everywhere; `SceneKit.save` strips `unique_id=` (verified: a stripped scene loads); generated-file conflicts are regenerated. | §1.1, §1.2, §2.12 |
| 13 | No P09 anchor in the enemy base files | Accepted: the full anchor table in §1.5 and an anchor test. | §1.5, §3.2 |
| 14 | Interactable exports, forge scene, patrol layout and dummies unspecified | Accepted: an export table for every placed class, `scenes/world/forge.tscn` (P12), `Markers/Patrol/<route>/<n>` with absolute paths set by the director, and a `dummies` layout section. | §2.7.4, §2.12, §3.11, §3.14 |
| 15 | `WEAPON_FAMILIES` is too short | Accepted: `bow`, `staff`, `jaws`, `natural` added by P01 (current list checked: club, sword, hammer, axe, fists). | §2.8.1 |
| 16 | Enemy nav layers never reach the agents; ogres unpathed in test worlds | Accepted: `EnemyActor` copies `nav_layers` to its agent; the stress arena bakes a large-layer region; the boss uses the giant layer. | §2.2, §3.4, §3.16 |
| 17 | The bot never closes pausing screens | Accepted, with one correction to the premise: the M1 Autopilot does **not** inherit `PROCESS_MODE_ALWAYS`; its `_ready` makes it pausable except for the capture scenario, so a pausing screen would freeze it. The bot runs `PROCESS_MODE_ALWAYS`, calls screen-backed APIs directly, closes any screen it causes, and checks a 2 s invariant. | §3.19, §5.1, §5.2 |
| 18 | Test-infrastructure ownership (restores, screen closing, action cache, projectile parent) | Accepted: `ResetHooks` run by the P02 runner, `GameData.override_record` refreshing the cache, `ScreenStack.close_all_static`, and the ProjectileSystem parented to the level. | §2.6.4, §2.7.4, §2.13 |
| 19 | The sandbox shrine would write the Valley save | Accepted: checkpoints only when `checkpoints_enabled()`; sandbox Rest heals without saving; tested. | Decision 13, §2.9, §3.6 |
| 20 | P03's Roar test needs P04's morale method | Accepted: a stub target records the call; P04 tests the real soldier. | §3.3, §3.4 |
| 21 | Web mitigations have no owner | Accepted: P14, applied by LevelRoot from the level record's `web_overrides`, with a forced-web test. | §3.16, §5.4 |
| 22 | `commander` and `is_commander` naming | Accepted: `commander` everywhere. | §2.7.3, §3.4 |

### 7.3 Gameplay review

| # | Finding | Resolution | Where |
| --- | --- | --- | --- |
| 1 | (Blocker) Boss kills and growth were not checkpointed | Accepted: checkpoints on growth, `boss_defeated`, every main stage and the shrine screen, with an aware-enemy deferral and a slow test of "boss, grow, die on the return leg". | Decision 13, §2.9, §3.6, §3.17 |
| 2 | Checkpoint spacing, snapshot health and the off-road Thornwick shrine | **Changed in two details.** Accepted the free Rest on first activation, the 60% health floor on death reloads, waystones and a road-walk test. The forest waystone moved to (−140, 38), because the suggested (−120, 10) is where the forest hunters now stand. The Thornwick shrine did not go to the suggested (80, −10): that is 8–10 m from the guard posts at (88, −14) and (88, −26), so a `force` player could never rest there; it is at (14, −26) instead, inside the west gate, 9 m off the road. | §2.9, §4.3 |
| 3 | Soldiers are never fought at stage 1; three wolf fights in a row | Accepted: `encounter.forest_hunters` (2 soldiers and a wolf at the road bend) replaces wolves B, with the guard prompt. | §4.4, §4.8, §4.9 |
| 4 | Wolves cannot be grabbed in practice; grab reach shorter than melee | **Changed.** Accepted teaching the grab on soldiers, reach = melee reach + 0.5, a lunge (2.0 / 2.7 / 3.5 m) and the 1.5 s stagger against a larger attacker, with a heavy → E test at every stage. Rejected suppressing knockback on the poise-breaking hit: the lunge already covers the ~1.35 m knockback, and the rule would special-case the player inside the core damage path. | Decision 16, §2.6.2, §3.7, §4.8 |
| 5 | The 12 tutorial prompts are never listed; nothing to practise defence on | Accepted: 13 prompts listed with triggers and dismissals, the sparring post, `hits_on` filters, and `train` requiring light ×3, heavy and Footfall. | §2.8.3, §3.13, §3.15, §4.5 |
| 6 | The bot defends perfectly, so its numbers say little about people | **Changed in one detail.** Accepted the novice/expert profiles, the human estimate, the death and damage targets and 5 seeds. The time target is placed on the human estimate (20–30 minutes), with a raw band of 13–26 minutes as a sanity check, instead of a raw 13–19, because the estimate formula already adds reading and navigation time. | Decision 30, §5.1, §5.6 |
| 7 | The metrics cannot explain deaths, readability or growth | Accepted: every suggested metric, stage-based segments, the stuck heatmap and the `world_blocked` / `bot_failed` diagnosis. | §4.9, §5.1 |
| 8 | Thin stage-3 payoff; awe numbers did not work; bypassable return patrol | Accepted: the Barrow wardens, the awe rule (−35 at a 4× ratio) and the return patrol on the bridge deck. | Decision 26, §4.4, §4.8 |
| 9 | The Ogre King is barely taller than the player; its damage is unworked | Accepted the 8.5 m height, unblockable slam and charge, and a worked table. The base powers stay at combo 45 / 55 and slam 75; recomputed with spec §7 (Strength term included) they give 76 / 92 / 126, not the review's "66 / 80 / 126", which mixed the two formulas. | Decision 27, §4.4 |
| 10 | The charge seldom reaches a wall; no phase-change cue | Accepted: four pillars at r 22, run-until-stone with a 1.4 s fallback recovery, steering only during the windup, and a 1.5 s phase roar with its prompt (merged with spec coverage #6). | §3.12, §4.4, §4.5 |
| 11 | Threats are unreadable without audio or animation; the courtyard overloads | Accepted: telegraphs for every windup ≥ 0.8 s, filling decals, aim lines, threat arrows, a ranged token pool, a 1.0 s launch gap, the first mage alone in the road patrol, and a smaller courtyard. | Decision 25, §3.4, §3.9, §4.4 |
| 12 | HOLD has no fallback and makes soldiers passive | Accepted: the ad-hoc line, `road_line` and `quarry_line` markers, and the brace counter. | Decision 26, §3.4, §3.13, §4.3 |
| 13 | The village choice has no lasting effect | Accepted: Mend for help, Roar for intimidate, the closed forge and no iron for intimidate, the ambush for force, one armory crate, and the outcome on the end screen. | Decision 11, §4.6, §4.7 |
| 14 | One stray area effect can make the village hostile | **Changed.** Area effects skip faction members, the first offence warns and only a second within 30 s turns the village hostile, and only the barricade sets `force`. The suggested "direct hit on a locked neutral" cannot happen here, because neutral faction members cannot be locked at all (spec coverage #5). | Decision 17, §3.13 |
| 15 | The `resolve` stage has no markers or branches | Accepted: two branch quests with markers, started from `quest.village.offer` and abandoned when another outcome is chosen. | §2.8.3, §3.15, §4.6 |
| 16 | Arc pitch is only tested against soldiers, not wolves | Accepted: lights and heavies must reach a 0.9 m wolf at stages 2–3 in both cameras, with authority for P05 to deepen the offsets. | Decision 5, §3.5 |
| 17 | No leash; courtyard enemies can follow into the arena | **Changed in one number.** Accepted the leash, the heal on return, the arena clean-up and the aware-enemy deferral. The courtyard leash is 55 m, not 70 m: 70 m from (158, −50) reaches z = 20, past the causeway exit, while 55 m stops at z = 5. | §2.9, §3.10, §3.12, §4.4 |
| 18 | Too much arrives at the Grove; L4 too late; no healing | **Changed.** Titan Surge moved to L4 as suggested. Mend stays at L4 but the help outcome teaches it at the village (and intimidate teaches Roar), instead of moving it to L3. The XP changes were taken (gate 30 → 60, causeway 70 → 40, a 0 XP `courtyard` stage) and extended (hurl 20 → 30, to_village 0 → 20), because with the suggested changes alone the worst case reaches only 420 XP at the gate, short of L4's 450. | §4.5, §4.7 |
| 19 | One stage-1 heavy cannot stagger an ogre | **Changed.** `recovery_mult` is 3.5, not 3.0: 35 × 1.08 × 3.0 = 113 is still below the ogre's 120, while 3.5 gives 132. | §2.6.2, §3.12, §4.4 |
| 20 | Runic Bolt cannot interrupt mages | Accepted: Runic Bolt poise 15 (×2 = 30 ≥ 25), Boulder Hurl poise 30, and the 0.1 s interrupt test. | §2.8.4, §3.9 |
| 21 | Hurling at the ledge cairn is hard to aim | **Changed in one detail.** Accepted the lockable cairn, the prompt and the locked message. The landing marker shows during Boulder Hurl's 0.45 s windup rather than "while the windup is held", because abilities fire on press in this design; lock-on is the main aid. | §3.7, §4.3, §4.5 |

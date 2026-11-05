# Implementation decisions and spec interpretations

The specification ([GIANTBORN_SPEC_V2.md](GIANTBORN_SPEC_V2.md)) asks that every interpretation
and conflict resolution be recorded. This file collects them for the whole build:

1. [The M2-M5 decisions](#1-the-m2-m5-decisions-plan-03): the 30 interpretations the M2-M5 plan
   fixed before any code was written (`docs/plans/M2_M5_PLAN.md` §0.3), each with what was built.
2. [Deviations recorded by the packages](#2-deviations-recorded-by-the-packages): where the 21
   packages (P01-P18) departed from the plan, and why. Each package's own record, with every
   detail and the test that covers it, is `docs/systems/<package>.md`.
3. [Fixes from the milestone gate reviews](#3-fixes-from-the-milestone-gate-reviews).
4. [The plan's review log](#4-the-plans-review-log-plan-7), in short.
5. [The M0/M1 decisions](#5-the-m0m1-decisions): the combat sandbox's rules, still in force unless
   a row says what replaced them.

Everything below is a proposed default: data, or a small code path, that can be changed.

## 1. The M2-M5 decisions (plan §0.3)

| # | Decision | What was built (and where it moved) |
| --- | --- | --- |
| 1 | **One Valley scene, district sub-scenes.** Geometry from one layout table (`tools/data/valley_layout.json`, not shipped); navigation pre-baked offline into four layers (human, large, giant, small giant); a breakable that blocks a path carries a `NavigationLink3D` enabled when it breaks; no runtime bake in the Valley; no streaming. | As planned (P10b): eight district scenes, four compressed navmeshes of 15-19 KB, one nav link per layer at that layer's height. A path query to an unreachable point can exhaust Godot 4.6.3's 4,096-polygon search limit, so the navmeshes were made leaner (fewer forest trees, hexagonal trunks, a coarser contour) and a slow test keeps whole-map queries under 3,500 polygons. |
| 2 | **Enemies spawn from data.** An `EncounterDirector` spawns `encounter` records with stable ids, persists kills, despawns far unengaged members (they return at full health), never respawns a cleared encounter, and enforces a budget of 12 active combatants, three AI LOD tiers (tier 2 a one-box proxy) and a leash. | As planned (P10a). Later: a level's encounter scenes load with the level and an activation spawns at most 2 members a tick (P17a, the spawn hitch); a hostile faction's armed members count toward the budget even in an unbudgeted encounter (P17b, the force branch's 16 hostiles). |
| 3 | **Weapons fit up to a stage; the Giantforge refits them.** `weapon_scale` 1.0 / 1.5 / 2.1667; a weapon follows growth up to `fit_max_stage`, then keeps that size with a "too small" warning; club, sword and hammer fit stage 2, their reforged variants stage 3; the tree is stage-3 only. | As planned (P08, P12). A forge reforges the equipped weapon for 2 iron; the village forge opens only on a help outcome, the ruins' Giantforge always. |
| 4 | **Growth adds body.** Stage 2 +150 health / +10 stamina, stage 3 +300 / +20; percentages kept; nothing heals by changing profile. | As planned (P05). |
| 5 | **Big giants still hit humans and wolves.** Arc pitch offsets 0 / −6 / −12 by stage. | P05 kept −6 / −12 and added per-action exceptions (`arc_pitch_offsets_deg`: stage 3's light 1 at −16) so the chain lands on a wolf at the giant's feet. P17b added the **vertical aim**: a light or heavy swung at the lock (or the soft target) lifts the stage's tilt just enough to reach it, so blows land at the stage's reach (3.5 / 5 / 6.5 m) while the default tilt still reaches the feet. |
| 6 | **Levels gate abilities** (`unlock_level`; `controller.level` 99 = no gating; `level_exempt` for rewards; auto-slot; loadout at shrines). | As planned (P01, P12). The auto-slot uses the ability's own slot from plan §4.7 when it is free (P12), so Boulder Hurl is always slot 5 and Runic Bolt slot 6. |
| 7 | **XP is accelerated and labelled** "Prototype pacing: accelerated quest XP". | As planned: the progression record's label, a sign in the Hollow, the tracker's pacing line, the inventory screen (P12, P13, P15). `test_xp_budget` keeps level 3 before the Grove, level 4 by the practice gate and level 5 before the stage-3 growth for every village outcome. |
| 8 | **In-flight projectiles still land after the shooter dies** (dropped only if the owner died this tick). | As planned (P01, P03). |
| 9 | **Statuses are ticked centrally**; status immunity is a separate list; Stone Skin changes `armor_total()`, never `armor`. | As planned (P01). A refresh never shortens a status (the later expiry wins). |
| 10 | **Thunder Roar** is unblockable, deals 0 damage, slows 30 % and costs 20 morale on HIT; a dodge evades it. | As planned (P03): a cylinder pulse with morale damage. |
| 11 | **Village outcomes last and differ.** Help (cache or ogre): 120 XP, 2 iron, Ancestral Mend, the village forge. Intimidate (stage ≥ 2): 40 XP and Thunder Roar, no iron, forge shut. Force: only by smashing the barricade (stage ≥ 2), kill XP only, an ambush on the return leg. Striking villagers sets hostility, never the outcome. Every outcome opens the bridge. Rewards only through once-flags. | As planned (P11b, P13, P15). The elder's conversation has the extra nodes a real talk needs (thanks, waiting, done; P15). |
| 12 | **Kingsfall growth requires the boss's defeat.** | As planned (`growth_requires_flags`, P05). |
| 13 | **Checkpoints are frequent and never lose a boss kill**: a shrine's first activation (a free Rest), Rest, the shrine screen, waystones, growth, the boss's defeat, every main-quest stage; deferred while dead, grabbed, executing, holding, in another screen or near an aware enemy; death reloads the last checkpoint with at least 60 % health and full stamina; only the Valley writes. | As planned (P06). Later: the slice's completion checkpoint ignores aware enemies and Quit to title commits it (P17a); New Game asks before replacing a saved game (P06). |
| 14 | **One save slot** `user://saves/valley_1.json` (IndexedDB on the web), versioned, with backup recovery. | As planned (P06). A main file that does not fully load is never copied over the backup (P16). The web persistence was checked in Chromium by P18 (`docs/M2_M5_HANDOFF.md`). |
| 15 | **Modes**: a title screen (New Valley, Continue, Sandbox, Settings, Quit); `--autoplay` / `--scenario` without `--mode` still boot the sandbox. | As planned (P06). The game opens at the title; Quit is hidden on the web. |
| 16 | **Grab design.** E grabs a staggered target in reach (melee reach + 0.5 m) with a lunge; the six spec §8 rules including an attachment profile; a poise break by a twice-taller attacker staggers 1.5 s; light or heavy throws, E drops; Crushing Grip crushes small targets; Boulder Hurl rips its own rock; a staggered ogre is grabbable from stage 3; the boss is immune. | As planned (P07). The lunge drives the motor's knockback channel; holds use the off hand; grab and throw have a 0.6 s input queue; every grab needs a fresh poise break (M3 gate). |
| 17 | **Factions and hostile-only targeting.** Lock, soft target and the player's area effects consider team ENEMY and faction-less NEUTRAL only; a direct hit on a village member warns, a second within 30 s turns the village hostile; intimidation stands the guards down. | As planned (P03, P11b). A broken guard is an offence too; one blow is one offence however many villagers it clips. |
| 18 | **The fortified Citadel Gate** is structural, `min_growth_stage` 4, permanently locked. | Two damage stages (intact, breached), because a structural prop's last stage must remove collision (P08); the breach is unreachable in the slice. |
| 19 | **The Deadfall** accepts only `TreeWeapon` hits. | As planned (P08). |
| 20 | **Talents and ancestry**: points accrue and show; one neutral ancestry, saved and shown. | As planned (P12). |
| 21 | **Physics layer 6 "blockers"** for invisible movement walls; every actor uses `SceneKit.ACTOR_MASK` (51); camera, attack occluders, LOS and hurtboxes ignore it; the navmesh treats it as an obstacle. | As planned (P01, P04, P10b). |
| 22 | **Debug keys** (debug builds only): F6 / F7 grow / shrink, F8 +100 XP, F9 reload the checkpoint; F5 sandbox reset; release exports have none. | As planned (P01, P05, P06, P12). |
| 23 | **Selective destruction in all three spec categories**: cosmetic (never saved), breakable, structural (the practice gate intact → cracked → broken); every persistent prop saves its stage and health. | As planned (P08); this ended the M1 limitation that partial damage was not saved. Each prop's meshes are merged per material (P17b, draw calls). |
| 24 | **Enemies commit their aim** at `tracking_fraction` of the windup (0.6 for archers and mages); a sidestep after the lock dodges the shot. | As planned (P09). Launch slots are padded by the difference in windups, so launches at one target are always at least 1.0 s apart. |
| 25 | **Readable threats without audio or animation**: a filling telegraph decal for every enemy attack with a windup of 0.8 s or more, aim lines, screen-edge threat arrows, at most two ranged attackers at once, 1.0 s between launches. | As planned (P09). An untelegraphed long windup is a data error. The arrows and the objective marker draw over every HUD panel and slide along the edge to stay clear of them (M4 gate). |
| 26 | **Size changes enemy tactics and morale**: outmatched soldiers hold formation and brace; awe (−35 morale) at 4x height; regroup only with a leader, else rout; bosses ignore morale. | As planned (P04, P11b). The brace reaches 4 m (the giant's leg hurtbox lies inside its capsule) and deals 28 to a stage-2 giant after tuning. Measured: soldiers hold formation 58 % of their engaged time at stage 2 and flee or rout 55 % at stage 3 (median of the novice runs). |
| 27 | **The Ogre King is a real boss**: 8.5 m; phase 1 alternates combo and slam; a 1.5 s roar marks phase 2, which adds a charge into the wall or a pillar and a 2.5 s punishable recovery; slam and charge unblockable. | As planned (P11a); super armour now ends at the recovery (the punish window). Tuned in P17b: the slam deals 101 to a stage-2 giant with a 1.5 s windup and a 1.8 s recovery, the combo 67 / 77, 0.6-1.0 s between attacks; health 1,500 and poise 150 kept. |
| 28 | **The tutorial encounter is in the Valley** (Giant's Hollow's dummies and sparring post, then the first wolf pack); the sandbox gets a sparring post. | As planned (P11b, P15). A lesson whose prompt timed out still counts when the player does it later (M4 gate). |
| 29 | **The navigation profile changes with growth**: stage 1 on the small-giant layer (8, with the 4 m alleys), stages 2-3 on the giant layer (4). | As planned (P05, P10b). |
| 30 | **Balance is judged on a novice bot**; the expert is the ceiling; stability uses an assisted bot (damage taken x0.25). | As planned (P17a, P17b). Final batch: the novice completes 17 of 18 runs and the expert 4 of 4; some §5.6 targets are still missed (`docs/HOW_IT_PLAYS.md`). |

## 2. Deviations recorded by the packages

The ones that change behaviour or a contract, in short; the system docs give the reasons in full.

**P01 Core seams.** Schema anchors sit inside each module's `fields()` and `semantic()` (code at
the top of a file cannot reach them). Hooks take `hook(tick)`. `override_record` refreshes cached
`ActionDef`s in place and can create and remove test records. `preview_reason` reports "busy" for
every RETRY. EXECUTING honours cancel rules like CASTING. A status refresh keeps the later expiry.
`healed` reports the health actually gained. `const V := DataValidator` does not parse on 4.6.3, so
schema modules spell the class out.

**P02 Actor seams.** `weapon_hit_radius()` is a fifth duck-typed actor method for AttackRunner.
`ResetHooks` entries may carry a failure message ("screen left open"). Anchor rows of other
packages are checked once their creator has landed. A compile check of every script backs
`tools/check.sh`, because `--import` does not parse scripts. The M1 "Nothing to grab here yet"
message is gone (E with no candidate does nothing). The M1 soak's result stayed byte-identical.

**P03 Abilities and screens.** The target line reads `» Soldier` (the default font has no `→`).
Projectile meshes live in ProjectileSystem. Timings the plan left open (Sweeping Blow 0.30 / 0.10 /
0.40 s, the self buffs, the roar; Titan Surge has no cooldown). A non-piercing projectile hits every
target touched at its first hit sub-step. ScreenStack sets the MENU input context for every modal
screen, pausing or not. Any player component may add request parameters for the hotbar
(`preview_params`), so the HUD and the controller share one code path.

**P04 Scene kit, wolf, morale.** The wolf lunge's active phase is 0.45 s, not 0.25 s (9 m/s for
0.25 s cannot reach the giant from the planned band). `SceneKit.save` also renumbers resource ids,
so `--only` and full builds write identical files. Flee points fall back to a path's end. Token
holders take turns, so a third attacker gets one. A dormant (tier 2) actor releases its tokens.
Weapon arcs gained `pitch_mid_deg` (M2 gate, below).

**P05 Growth and shrines.** The camera also hides the head when the arm is pressed close behind it
(the plan's 1.2 x radius rule missed a stage-3 giant under the growth course's roof). Per-action arc
pitch exceptions. Growth refusals gain `already`, and airborne counts as `busy`. Rest heals and
removes debuffs but keeps fury, buffs and cooldowns, and is not gated by combat. A save restore
applies the stage silently (no `growth_changed`).

**P06 Session and saves.** Only the Valley writes the slot (a test level in sandbox mode keeps its
checkpoints in memory). The death floor applies after the character state. New Game asks before
replacing a save. Continue needs the save's level, not the Valley. The loading frame pauses the
tree, so the seeded soak keeps its exact timeline. The death confirm (Enter / pad A) runs in
`main._input`.

**P07 Grab and throw.** A held body leaves the simulation through `process_mode` DISABLED (P04's
dormant tier). The lunge uses the motor's knockback channel. One-hand holds use the off hand; in
first person every hold is low and to the left. While holding, every ability but a crush is
refused. Throw numbers: P40 x 1.2, poise 30, 20 m/s, range 20 m, a 1.5 m splash. Crushing Grip is
0.25 / 0.10 / 0.35 s and never crits.

**P08 Props and weapons.** `protected` props report IMMUNE `not_permitted` (the notes are
CombatEntity's). The fortified gate has two stages. The practice gate drops 2 wood scraps. Moveset
timings are whole ticks (the sword 10 / 7 / 14, the maul 17 / 9 / 23). The tree is a mid-range
weapon carried raised; its sweeps miss the giant's feet. The nav-link test uses an authored navmesh
(a runtime bake raced Godot's asynchronous map iterations).

**P09 Archer, mage, readability.** Launch slots are padded by the windup difference. Shots wait
until the unit is settled at its firing point. Line of sight is checked from the launch height
(1.45 m), so cover lower than that works. The barrier is a `targets_ally` cast whose
`on_hit_statuses` land on the ally. The kick is a short sector pulse. The ranged playground's climb
is a slow suite.

**P10a Level framework.** RETURN (the leash) is driven by the actor with the AI paused; full health
6 s after the leash or on arrival. Members that do not fit the budget spawn in id order as room
frees up. `despawn` frees at the end of the frame. Area events are deferred to the end of the
physics frame. Offline navmeshes carve solid boxes with projected obstructions (no islands inside
pillars). Test records ship in `data/world/`, one record per JSON file.

**P10b Valley world.** One record per JSON file (`encounter_<name>.json`). Per-layer nav links. The
search-limit fix (decision 1). MultiMesh transforms are written as a buffer (the headless renderer
drops `set_instance_transform`). Navmeshes are external files. A ridge separates the forest from
the fields, the bridge has blocker rails, and nothing reaches the ruins but through the practice
gate. The Hollow cottage arch (an optional stage-1 shortcut) was not built.

**P11a Ogre and boss.** Super armour covers the windup and active phases only. Strikes are pulses
that match their telegraphs exactly. The combo chains through the controller's input buffer. The
charge passes through actors and shoves the giant aside. A sequence entry is skipped only after 2 s
of patience near its range band. The king faces the entrance (yaw 0). The ogre's stagger is 2.0 s
against a giant twice its height (the stage-3 grab window).

**P11b Civilians and factions.** Five one-line hooks outside the P11b anchors (the faction behaviour
acts inside existing functions). FactionState is a shared hub, not a node. The sparring post is not
in the `enemies` group (it would hold the M1 soak forever) and stands west of the sandbox's test
wall. The brace reaches 4 m. Neutral guards keep their guard up while they watch. Hostility wins
over standing down. The elder never flees. Village guards do not count toward the budget while
neutral (they held half the director's slots across the map).

**P12 Progression.** The auto-slot prefers an ability's own §4.7 slot. Level 99 in a save means
"never gated". `xp` in the save is the total. Kill XP needs team ENEMY and the `enemies` group (a
prop pays through its own XP). Raider loot is wood scrap, never iron (the five ingots of §4.7 stay
exact). The progression post-pass checks the forge's upgrade rule.

**P13 Quests and dialogue.** For quests, `entered` holds once the area was entered since the load
(tutorial triggers: presence only). Kill and destroy conditions read the saved deltas and the
deaths seen since the load. Dialogue outcomes persist as flags. Id prefixes are enforced. A node
with no choice gets an implicit `[Leave]`. The main quest's completion is a checkpoint. A quest's
start emits only `quest_started`.

**P14 Performance.** CPU per tick is timed from inside the physics step (the engine's `TIME_*`
monitors are per-second maxima on 4.6). The stress arena has its own level record and spawner (no
director, so every combatant runs AI tier 0, the worst case), puts fresh breakables in place after
each lap, and grows the giant to stage 2. A preset's `shadow_distance_m` 0 switches sun shadows off.

**P15 Content.** Stages that complete on `entered` also accept the states that can only come after
them (a reload resets level memory). `quest.tutorial` is abandoned at stage 2. Every prompt that
waits for an action has a fallback timeout. The village captain stands beside the barricade's road,
not in it. The dressing is batched in `CosmeticField` MultiMeshes. The Hollow cottage arch stays
unbuilt.

**P16 UX and controller.** Pad A and B join `ui_accept` / `ui_cancel` at run time (Godot 4.6's
defaults hold no pad button). A "Button prompts" setting pins the glyphs. A rebinding capture gives
up after 6 s (a pad has no Esc). LB / RB switch pages and tabs. A menu footer names the keys. The
ability notice moved to the top centre; the boss bar is 540 px wide. An out-of-range Runic Bolt is
refused, not only shown. Growth clearance counts actors.

**P17a Valley bot.** Result files go to `user://bot_runs/<tag>/`. The bot plays the optional
tutorial (bounded by 120 s). The assisted mode is a hidden status, so the damage path is unchanged.
Additions to the plan's bot rules, each found needed in a run: `--bot-trace`, the errand give-up,
the rest before a kill objective, the reach band, the tree only for the Deadfall, the walk back out
of a navmesh pocket.

**P17b Balance.** A game-code change in a tuning package: the vertical aim (decision 5), because the
short reach was geometry, not a number. Bot fixes that correct measurement mistakes, never the
difficulty. `test_obstacle_route` moved to the slow suites (the default suite's 75 s budget). The
village yard's navmesh pocket is not fixed. The human time estimate stays below 20 minutes and no
content was added to pad it. The Ogre King keeps 1,500 health.

**P18 Ship.** A Valley screenshot tour that runs beside the bot (`tools/valley_tour.gd`; P17b's
optional capture scenario was not built); the actors' draw calls documented as a known limitation
instead of a late renderer change; one HUD message fixed that the tour's shots showed (a destroyed
prop was named by its district); the version `0.5.0-m5`. See [docs/systems/P18.md](systems/P18.md).

## 3. Fixes from the milestone gate reviews

Each milestone gate, and the Ship gate at the end, had an independent review. Every confirmed
finding was fixed with a regression test, or handed to the package that owned the files through
`docs/plans/FOLLOWUPS.md` (all closed or deferred there).

| Gate | Finding | Fix |
| --- | --- | --- |
| M2 | The stage-1 light chain passed over a 0.9 m wolf at the giant's feet. | Weapon arcs gained `pitch_mid_deg` (a curved pitch); lights 1 and 2 dip low in front (P04). |
| M2 | The seeded soak no longer broke the fence after the wolves arrived. | A soak target order (engaged enemies, the fence, then the rest) and a `check.sh` coverage check. |
| M3 | A released body counted as broken poise, so one stagger allowed endless re-grabs. | `PlayerGrab.has_broken_poise`: a release's recovery is not a poise break (P07). |
| M4 | A tutorial prompt's fallback timeout lost its lesson (the quest stage could never complete). | A lesson stays open after its prompt is taken away (P13's tutorial director). |
| M4 | Threat arrows and the objective marker drew under the TIP box and the hotbar. | Both overlays draw last and slide along the edge clear of every panel (`HudEdge`, P16). |
| Ship | The handoff counted P17a's assisted runs of the four village outcomes as runs on the same game code, and as the M4 gate's evidence, but P17b retuned the game after them. | The four outcomes ran assisted on the final code (handoff §6.2, all completed) and the M4 row cites those runs; §1 and §6.4 say P17a's runs came before P17b's tuning (`test_ship_docs`). |
| Ship | The owner's spec names the AI tools it was written for and drawn from; the repository is meant to name no AI product or model. | One recorded exception: `GIANTBORN_SPEC_V2.md` stays verbatim, and its source note says so. No other file names an AI product or model. The hosting platform's own names are allowed, since they name no product or model: the claude.ai play link, the launcher's `claude:viewport-fit-sides` meta tag and `window.claude` hook, and the integration branch. `test_ship_docs` checks every text file in the repository. The owner may still redact the spec instead; the test's exception then goes. |

## 4. The plan's review log (plan §7)

Before any code, the plan was reviewed three times: spec coverage (26 findings), feasibility (22)
and gameplay (21). Every finding led to a change, most of them exactly as suggested. The ones whose
fix was changed, or partly rejected, and why:

- **Weapon fit** (coverage 1): the club fits stage 2, not stage 1 (growth to stage 2 comes long
  before any forge), and an outgrown weapon keeps its last fitted size with a warning instead of
  being refused.
- **Neutral guards** (coverage 5): eligibility is "team ENEMY, or NEUTRAL without a faction", not
  "team ENEMY only", because the practice dummy is NEUTRAL and lockable.
- **Regrouping** (coverage 10): `regroup_needs_leader` defaults to true and the leader is a commander
  or a non-fleeing ally within 20 m (the suggested "highest-morale unit" always exists).
- **The P11 split** (feasibility 8): P11b runs in wave 7 and the NPC talker moved to P13.
- **Checkpoint placement** (gameplay 2): the forest waystone is at (−140, 38) and the Thornwick shrine
  at (14, −26), away from the hunters and the guard posts.
- **Grab** (gameplay 4): reach = melee reach + 0.5 m with a lunge; knockback on the poise-breaking
  hit is not suppressed.
- **Time targets** (gameplay 6): the 20-30 minute target applies to the human estimate, with a raw
  13-26 minute sanity band.
- **The King's numbers** (gameplay 9): recomputed with the spec's formula (76 / 92 / 126 before
  tuning).
- **Village area effects** (gameplay 14): area effects skip faction members; the first direct hit
  only warns.
- **The courtyard's leash** (gameplay 17): 55 m, not 70 m (70 m reaches past the causeway).
- **The ability schedule** (gameplay 18): Mend and Roar are taught at the village, and the XP of four
  stages was raised so the worst outcome still reaches level 4 at the gate.
- **The ogre's punish window** (gameplay 19): the recovery multiplier is 3.5, not 3.0 (3.0 left one
  stage-1 heavy below the ogre's poise).
- **Boulder aim** (gameplay 21): the landing marker shows during the 0.45 s windup (abilities fire
  on press).

## 5. The M0/M1 decisions

The combat sandbox's rules. They still hold unless a row says what replaced them.

### Engine and project

| Decision | Why |
| --- | --- |
| **Godot 4.6.3-stable (official build `7d41c59c4`)**, GDScript, Compatibility renderer | Latest patch of the previous stable line (4.7.2 was newest on 2026-11-04). The spec asks for a pinned stable version, not the newest. |
| Jolt Physics selected explicitly in `project.godot` | Godot's recommended 3D engine in 4.6; Area3D shape queries were probed and work. |
| Fixed 60 Hz simulation in the `Sim` autoload | All combat runs in whole ticks; rendering (camera, animation, UI) runs in `_process`. Since M2 `Sim` also has hook phases, named RNG streams and a status pass (`ARCHITECTURE.md`). |
| Physics interpolation **off** | Bodies move at 60 Hz. On displays above 60 Hz, bodies update at 60 Hz while the camera's mouse look stays per-frame. |
| Input bindings live in `data/input/default_bindings.json`, not `project.godot` | Keeps every binding remappable and data-driven; user overrides are saved in `user://settings.json`. |
| Scenes are generated by `tools/build_scenes.tscn` (since M2 a runner over one builder per area in `tools/builders/`) | Valid, editor-friendly `.tscn` files from code; `SceneKit.save` strips random ids, so a rebuild changes only what changed. **Once you edit scenes in the editor, the editor copy is the source of truth; re-running the tool overwrites it.** |
| Resets reload the scene | Since M4 by mode: the sandbox reloads fresh (F5, Restart sandbox, Enter after death); the Valley reloads the last checkpoint after a death. |

### Combat rules

| Topic | Decision |
| --- | --- |
| Timing | Seconds convert to ticks once (`round(s * 60)`). An action accepted at tick T is at elapsed 0; light attacks are active from elapsed 12 to 20 and finish at 39 (0.65 s). Dodge invulnerability covers elapsed 6 to 17 (0.10 s up to, not including, 0.30 s). |
| Parry window | A hit is a parry when `block_elapsed_ticks < 12` (the first 0.20 s), counting from the tick block was accepted. |
| Tapped block | A block press lasts at least the parry window (0.20 s), so a tap gives a full parry window. Holding never reopens it; a new press (and a new 5 stamina) is needed. |
| Held block | Block is a held stance. If the block input is still held when the giant is free to block again, blocking resumes: the 5 stamina entry cost but **no** parry window. Without a lock the guard faces the aim; pressing block snaps the facing to the aim or the locked target. |
| Unblockable / Unparryable | Independent flags. An Unblockable melee attack can still be parried inside the parry window; outside it, it ignores the block. An Unparryable attack can still be blocked. (The Ogre King's slam and charge carry both.) |
| Failed parry | A parryable hit inside the window that cannot be parried (for example, under 5 stamina) is an ordinary block **and consumes the window**. Successful parries do not consume it; each costs its own 5 stamina. |
| Guard break | 50 % of the pre-block mitigated damage; remaining stamina consumed; a 1.0 s stagger. |
| Blocked hits and poise | A successful block applies no poise damage to the blocker; stamina is the guard meter. |
| Parry poise | 40 poise damage to the attacker, not size-scaled (Titan Surge's +25 % applies to it since P11a). |
| Stagger immunity | 1.5 s after any stagger, against stun-locks; poise damage is ignored while staggered. |
| Interrupt policy | `interrupt_policy` per action (`hard_stagger` by default). `super_armor` is used since M4 by the ogres' and the King's strikes and covers the windup and active phases only (P11a). Interrupted actions are never refunded. |
| Cancel windows | Lights may cancel their recovery into the next light, a dodge or a block. Heavies may only dodge-cancel, from 0.25 s into recovery. Dodge may cancel into attacks, block or dodge from 0.15 s into its recovery. |
| Input buffer | One slot, newest wins, live for 9 ticks (0.15 s), then revalidated. Requests that fail on resources, cooldown, locks or empty slots are rejected at once with a reason and spend nothing. |
| Combo chain | The next light is used if requested during the current light's recovery or within 0.35 s after it. After light 3 the chain restarts. A heavy, an ability or an interruption breaks it. |
| Sprint | 8 stamina/s; locked at zero until released or back to 25. Shift + light issues one heavy. |
| Stamina regeneration | 15/s after 1.0 s without spending. |
| Fury | +4 the first time a basic attack instance damages a fury-granting target, +6 per parry, +8 per kill. Props never grant fury; abilities are not basic attacks. Titan Surge (100 fury, since M2) spends it. |
| Crits | 5 % for the player, rolled from the seeded `Sim.rng` in stable hit order (pinned by the 37 / 66 / 44 tests). Enemies have 0 %. Every newer random consumer has its own stream (`Sim.rng_for`). |
| Same-tick deaths | Hits resolve in a stable order; hits from an attacker that died earlier in the same pass are dropped, except projectiles (decision 8). |
| Dead targets | Resolve as `IGNORED`: no damage, events, fury or resources. |
| Practice dummy | Armor 25, so on-screen numbers reproduce the worked example (light 37, heavy 66, Footfall 44). Unkillable; refills 3 s after the last hit; lockable. |
| Soldier | Health 220, armor 15, poise 40. Slash P=30 (0.55 s windup), overhead chop P=45 (0.85 s, telegraphed since M2). A frontal 120° guard with its own 40-point stamina while aware and not attacking; heavies break it; flank hits land fully. Since M4 also the brace counter, awe, and 1.2-1.8 s between strikes (P17b). |
| Heavy attack shape | An overhead slam from the right shoulder angled inward, so it lands on the centre line about 2 m ahead. |

### Hit detection

| Topic | Decision |
| --- | --- |
| Weapon shape | A capsule along the arm and weapon, swept from the previous to the current pose; the procedural rig reads the same `AttackGeometry`, so the visible swing is the tested swing. Since M3 it scales with the growth stage and the weapon's fit. |
| Sweeps | Sub-stepped at no more than 3/4 of the radius per step (up to 16 sub-steps per tick). |
| Occlusion | The line from the attack origin to the weapon point, and from the weapon point to the hurtbox, must be clear of world and breakable geometry (the target's own colliders excluded). |
| Query buffer | Starts at 64 results and doubles until nothing is cut off (hard cap 4096, with a warning). |
| Hurtboxes | Area3D volumes on their own layer; dedup per entity id. Large enemies have several lock anchors on one health pool (P11a). |

### Camera and targeting

| Topic | Decision |
| --- | --- |
| Third-person framing | Stage 1 shoulder offset 1.1 m, pitch −18°; growth scales the arm (about 6.5 / 9 / 12 m) and the lock orbit (P05). |
| Follow arm | One rigid arm swept with a 0.35 m sphere; retracts at once, restores at 6 m/s. The head is hidden when the arm is pressed close (P05). |
| Lock-on framing | Aims at the target's lock anchor for the viewer's height (a knee of the Ogre King at stages 1-2), pitch clamped −35°..+8°; small, close targets get a side orbit. |
| Aim and cone | Lock cone and target switching use horizontal directions; visibility is a ray from the eyes. Lock range 35 / 40 / 45 m by stage. Only hostile or faction-less targets are lockable (decision 17). |
| Wheel and stick flick | While locked the wheel switches targets; otherwise it zooms. A right-stick flick switches in third person; in first person only a flick that snaps back within 0.25 s does. |
| Controller combos | Ability slots and the ultimate are LT + button combos; while LT is held those buttons do nothing else. Remappable. |
| First person | Eye at 92 % of height; head, chest and belt on render layer 2, culled by the first-person camera. First-person lock never rotates the camera unless the optional aim assist is on. |
| Motion blur | None; the setting shows "Off". |

### AI, world and data

| Topic | Decision |
| --- | --- |
| Perception | 5 Hz with per-actor offsets; sight cone and range per record (archers 32 m); hearing of the player's attacks; being hit reveals the attacker; a hidden target is tracked only at its last known position. Distant actors perceive at 1 Hz (AI tier 1) or sleep (tier 2). |
| Path failure | No progress for 2 s triggers `on_path_failed`. Enemies never teleport. Without navmesh data, actors steer directly. |
| Navigation | The sandbox bakes its navmesh at load and re-bakes when the fence breaks. The Valley is baked offline and never re-bakes (decision 1). |
| Morale | Replaced in M2-M4 by decisions 26 and 17: ally deaths, commanders, awe, Thunder Roar, flee / regroup / rout. |
| Breakables | Replaced by decision 23: every persistent prop saves its damage stage and health. The blocking shape is disabled and detached at once, so a navmesh bake in the same frame never sees it. |
| World deltas | Saved with every checkpoint since M3 (decision 13), with flags, inventory and kills (`WorldState` v2). |
| Data validation | Unknown keys are errors; timings that are not whole ticks warn and are rounded; references are checked by type; the ids the code needs are required (`REQUIRED_RECORDS`, merged from the schema modules since M2); cross-record checks run in a post-pass. Any error replaces the game with the full list. |
| Settings file | Saved through `SaveIO` (temp file → verify → backup → replace). A corrupt file falls back to the backup with a message; a newer schema is kept as `settings.schemaN.rejected.json`. The Valley save uses the same path (decision 14). |

### Browser build

| Topic | Decision |
| --- | --- |
| Hosting | The play link is a claude.ai Artifact page: private by default, shared from the page's Share menu, with no extra branch, service or account. |
| Threads | The Web export is single-threaded, so it needs no cross-origin isolation headers, which the host cannot send. |
| File packing | The host serves `.js`, `.wasm`, text and images, but not `.pck` or archives, and caps text files at 16 MB. `index.wasm` (36 MB) and `index.pck` therefore ship gzipped and base64-encoded as `.txt` files; the launcher downloads them with progress, unpacks them with `DecompressionStream` and hands Godot ordinary responses. `tools/build_web.sh` writes the byte counts into the launcher. |
| Mouse | Browsers grant pointer lock only inside a click and keep the first Esc for themselves. On the web the game does not capture the mouse at start; a click on the game, or the title's button that starts a mode, captures it, and losing the lock opens the pause menu. |
| Release build | The play link is a release export: no debug panel or debug keys, Quit hidden. It always uses the `low` graphics preset and starts AI tier 1 at 30 m (`level.valley`'s `web_overrides`). |
| Saves | Settings and the one Valley save live in the browser's storage (IndexedDB), so Continue works after a reload. |
| Updates | When the page is republished, open viewers reload at a quiet moment; the launcher starts the game again, and Continue picks up the saved game. |

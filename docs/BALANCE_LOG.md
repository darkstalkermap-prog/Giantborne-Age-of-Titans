# Balance log

Every tuning change of the Valley slice, with its reason and the measurement before and after
(plan §5.6). P17b ran the loop; later packages append below.

**How it is measured.** One matrix per step: `tools/run_bots.sh --preset=balance --tag=<tag>` (22
unassisted runs, three at a time, 900 s of wall time at most each: novice x {help_cache, help_ogre,
intimidate} x seeds 1-5, novice x force x seeds 1-3, expert x the four policies x seed 1), headless
at `--fixed-fps 60` in the development container. A run stops on a watchdog breach (240 s on one
main-quest stage, 480 s on the boss, more than 5 deaths on one stage) and then counts as not
completed. The tables come from `python3 tools/bot_report.py <batch folder> [section]`; the batch
folders are `user://bot_runs/<tag>/` (`.userdata/godot/app_userdata/Giantborn- Age of Titans/bot_runs/`
in a worktree). The bot and its profiles are described in `docs/systems/P17a.md` and
`docs/HOW_IT_PLAYS.md`. Targets: plan §5.6 (novice, unassisted, median over seeds).

Damage shares of maximum health are estimates (the giant's maximum health at the segment's end,
rebuilt from the run's level and stage). Medians of segment times and totals are over the completed
runs; deaths, completion and death causes over all runs.

## Baseline (tag `base`): P17a's game and bot at the start of P17b

| Skill | Policy | Completed | Human est. median (min) | Raw median (min) | Deaths median (boss) | Max deaths in another segment |
| --- | --- | --- | --- | --- | --- | --- |
| novice | force | 0 / 3 | - | - | 9 (6) | 3 |
| novice | help_cache | 2 / 5 | 20.3 | 14.0 | 6 (4) | 1 |
| novice | help_ogre | 0 / 5 | - | - | 6 (6) | 1 |
| novice | intimidate | 0 / 5 | - | - | 7 (6) | 1 |
| expert | force | 0 / 1 | - | - | 2 (0) | 2 |
| expert | help_cache | 1 / 1 | 23.1 | 16.4 | 5 (3) | 1 |
| expert | help_ogre | 1 / 1 | 18.3 | 12.9 | 2 (0) | 2 |
| expert | intimidate | 0 / 1 | - | - | 10 (6) | 4 |

- Novice deaths (120): the Ogre King 89 (slam 42, combo 47), the soldiers' brace counter 17, archer
  shots 4, the ogres 6, others 4. Expert deaths (19): the King's slam 9, the brace 5, archers 4, a mage 1.
- By segment (novice): boss 89, ruins 16, forest 9, village 5, return 1. Completed novice runs: 2 of 18.
- Segment damage / maximum health (median, completed runs): forest 1.40, village 1.94, ruins 1.42;
  per boss attempt 1.23.
- Growth: soldiers in HOLD 0 % at stage 1, 60 % at stage 2; FLEE or ROUTED 42 % at stage 3;
  soldier time-to-kill 21.1 s at stage 1, 12.6 s at stage 2 (ratio 0.69).
- CPU per tick p95: median 7.04 ms, max 8.11 ms (budget 8). Hits from attackers off camera at their
  windup: median 15 %, max 31 %; within 0.45 s of the telegraph: 0.

**Diagnosis.** Replays of the boss deaths (`--continue` from each run's last save, with
`--bot-trace`) showed (1) the bot spent all its stamina on swings, so the dodge it planned against
the slam was refused for want of stamina (10 of 11 refused dodges in one expert replay came at 0
stamina); (2) it started heavies that a planned dodge then waited for; (3) the giant's light chain
landed well short of `melee_reach_m` (about 3.3 / 4.0 / 3.5 m by stage against a soldier, P17a's
measurement): each stage tilts its arcs down to reach the giant's feet, so a stage-2 giant could not
strike a holding soldier from beyond the brace counter's 4.2 m, and the bot stood 0.45 into the
band (about 2.9 m), inside the brace. The force branch's return leg put 16 hostiles round the giant
(FOLLOWUPS).

## Fixes before tuning (tag `fix`)

Not tuning: fixes to the game and to the bot so that the matrix measures the game.

| Change | Where | Why |
| --- | --- | --- |
| The swing's vertical aim: a light or heavy at the lock (or the soft target) tilts up from the stage's tilt just enough to reach it, up to 16 deg | `scripts/actors/player/player_attack.gd` (game) | Blows now land at about the §4.8 reach: 3.5 m at stage 1, 5 m at stage 2 (the overhead third blow 4.6 m), 6.5 m at stage 3 with a reforged club; a wolf at the feet keeps the default tilt (`test_vertical_aim`) |
| A hostile faction's armed members count toward the director's 12-active budget | `scripts/world/encounter_director.gd` (game) | The force branch's return leg (FOLLOWUPS): peak hostiles within 40 m 16 -> 12 |
| Only the expert keeps a dodge's stamina in reserve | `scripts/debug/bot_combat.gd` | The refused dodges above; a reserve for the novice too made it wait out whole forest-ogre fights between blows (it timed out there), so the novice spends freely, as plan §5.1 describes it |
| No heavy starts when a planned dodge falls inside its commitment (60 ticks) | `bot_combat.gd` | The heavies that ate the slam's dodge |
| The reach band is measured over the aim's tilts, through the target's core (half its radius), and the bot stands 0.8 into it | `bot_combat.gd` | The aim moved the band; P17a's 0.45 was chosen for the short fixed tilt |

| Skill | Policy | Completed | Human est. median (min) | Raw median (min) | Deaths median (boss) | Max deaths in another segment |
| --- | --- | --- | --- | --- | --- | --- |
| novice | force | 1 / 3 | 21.4 | 16.3 | 6 (5) | 1 |
| novice | help_cache | 2 / 5 | 20.1 | 14.2 | 6 (3) | 2 |
| novice | help_ogre | 4 / 5 | 16.1 | 10.8 | 2 (0) | 2 |
| novice | intimidate | 2 / 5 | 23.7 | 18.2 | 8 (6) | 5 |
| expert | force | 0 / 1 | - | - | 1 (0) | 1 |
| expert | help_cache | 1 / 1 | 18.6 | 13.5 | 1 (0) | 1 |
| expert | help_ogre | 1 / 1 | 16.5 | 11.9 | 0 (0) | 0 |
| expert | intimidate | 0 / 1 | - | - | 0 (0) | 0 |

- Completed novice runs 2 -> 9 of 18; the expert died 19 -> 2 times (two arrows) and finished
  help_cache and help_ogre; its intimidate run stood at the courtyard for 240 s with nothing in
  reach, its force run timed out on the return leg's Deadfall stage.
- Novice deaths 120 -> 99: the King's slam 33, combo 18, charge 3; the brace 20, archer shots 15,
  mage bolts 5, others 5. By segment: boss 54, ruins 39, forest 5, return 1.
- **The courtyard got harder**: the ruins' novice deaths 16 -> 39, the courtyard stage's median
  time 109 -> 172 s and damage 1,284 -> 2,121 (intimidate, which arrives at level 4 with the plain
  club: 0-1 -> 1-8 deaths). Standing 0.8 into the aimed band put the giant at 4.2 m, on the brace
  counter's edge, where a holding soldier keeps its guard up; and with every planned dodge holding
  heavies back, the courtyard's archer and mage kept it from breaking guards. The courtyard's
  archer on the west terrace (out of melee reach) killed the novice 15 times (3 in the baseline).
- Peak hostiles within 40 m: 12 (the force branch included). CPU per tick p95: median 6.47 ms, max
  8.82 ms (one run). Off-camera hits: median 20 %, max 53 % (one run). Growth: HOLD 54 % at stage 2,
  FLEE or ROUTED 39 % at stage 3, time-to-kill ratio 0.58.

## Iteration 1 (tag `iter1`)

Commits `a26fc40` (bot) and `c080d6c` (data).

| Change | Before -> after | Why |
| --- | --- | --- |
| `ability.boss_slam` power | 75 -> 60 (126 -> 101 damage to a stage-2 giant) | The slam killed the novice 33 times in 18 runs (42 in the baseline); 126 of a stage-2 giant's 740 was a sixth of its health for one mistake |
| `ability.boss_slam` windup | 1.3 -> 1.5 s | A novice who sees it (250 ms latency, 70 % dodge) gets 1.25 s to move instead of 1.05 s; still unblockable |
| `ability.boss_slam` recovery | 1.4 -> 1.8 s | A longer punish window after a dodged slam: the reward for reading it |
| `ability.boss_combo_1` / `_2` power | 45 / 55 -> 40 / 46 (76 / 92 -> 67 / 77) | 18 combo deaths; a combo taken whole was 168 |
| `enemy.ogre_king` strike pause | 0.3-0.6 -> 0.6-1.0 s | Back-to-back attacks left no time to recover stamina or reposition (spec §10: difficulty from readable threats, not overlapping damage) |
| `ability.soldier_brace` power | 30 -> 24 (35 -> 28 damage) | 20 deaths; the courtyard's three soldiers in formation brace together |
| `ability.archer_shot` power | 22 -> 18 (25 -> 21 damage) | 15 novice deaths, all of them to the courtyard's terrace archer, which shoots through the whole fight |
| The bot walks on from an encounter whose last members are out of its reach (fleeing, elevated, unreachable) after 8 s: to the stage's other way out (the courtyard's causeway) or to its objective (the barrow's crown) | `scripts/debug/valley_bot.gd` | Bot fix: two timeouts of 240 s spent standing at the courtyard |
| The bot stands at the plan's 0.8 x reach (+ half the target's radius), inside the light's band: 3.0 / 4.0 / 5.4 m by stage against a soldier | `bot_combat.gd` | Bot fix: plan §5.1's rule; 0.8 into the aimed band was 4.2 m, the brace counter's edge |
| Only a dodge planned against a blow from within 10 m holds a heavy back | `bot_combat.gd` | Bot fix: an arrow from 20 m kept the bot from breaking guards at all |

Tests that pin these numbers follow them: `test_boss` (slam 101, windup 1.5 s, combo 67 / 77),
`test_awe_brace` (brace 28), `test_npc_rules` (brace P24), `test_ranged_brains` (shot P18).

| Skill | Policy | Completed | Human est. median (min) | Raw median (min) | Deaths median (boss) | Max deaths in another segment |
| --- | --- | --- | --- | --- | --- | --- |
| novice | force | 0 / 3 | - | - | 1 (0) | 1 |
| novice | help_cache | 4 / 5 | 15.6 | 10.3 | 1 (0) | 1 |
| novice | help_ogre | 5 / 5 | 16.0 | 10.7 | 1 (0) | 1 |
| novice | intimidate | 3 / 5 | 14.8 | 10.4 | 2 (0) | 1 |
| expert | force | 0 / 1 | - | - | 3 (0) | 3 |
| expert | help_cache | 0 / 1 | - | - | 3 (0) | 3 |
| expert | help_ogre | 0 / 1 | - | - | 3 (0) | 3 |
| expert | intimidate | 0 / 1 | - | - | 2 (0) | 2 |

- **The Ogre King stopped killing**: 0 novice deaths at the boss (54 in `fix`); the novice kills him in
  34-48 s, its health falling to 3-37 % of its maximum on the way (median 18 %): a close race, not a
  walkover. The boss segment is 1.3 min (target 2.5-6, "typically one retry").
- **The courtyard is fixed**: ruins deaths 39 -> 9, the ruins' damage 2.88 -> 1.08 x maximum health,
  the segment 4.7 -> 2.8 min.
- Completed novice runs 9 -> 12 of 18. **The forest is now where runs end**: 13 of the 24 novice
  deaths (the ogre's smash 8, the hunters' chop 4, a wolf 1) and three novice timeouts on the
  `ogre` stage (seeds 2 and 5: two deaths and the walk back from the Hollow's shrine use up its
  240 s). **All four expert runs died to the forest's hunters** (11 deaths: chop 8, slash 3): the
  expert runs share seed 1, so they share one forest, and in it both hunters reached the giant's
  legs together; a replay (`--continue --bot-trace=3`) shows the expert standing between them at
  2 m, blocking and parrying both, its stamina going to the guard and its dodge reserve, its health
  falling about 15 per second until a chop got through.
- Other stops: the force branch's return leg twice on its Deadfall stage (the stage-3 giant fights
  the village's guards, the militia and the return patrol, and twice got stuck in the village yard's
  navmesh pocket, the known one from P17a), and one crown stage where the giant chased a harassing
  barrow wolf it never hit until the watchdog.
- Novice deaths by cause: the ogre's smash 8, the brace 5, archer shots 4, the hunters' chop 4, mage
  bolts 2, a wolf 1. Growth: HOLD 60 % at stage 2, FLEE or ROUTED 55 % at stage 3 (target met; 39 %
  in `fix`), time-to-kill ratio 0.57. CPU per tick p95: median 5.66 ms, max 7.96 ms. Off-camera hits:
  median 21 %.
- **Boss health was tried and left at the spec's 1,500.** Replays of two `fix` boss checkpoints
  (level 5; the reinforced club, and the plain sword of the intimidate path) with iteration 1's
  numbers: at 1,500 health both win the first attempt (38 and 41 s) with 120 and 20 health left; at
  1,800 the club wins with little left and the sword loses six attempts in a row; at 2,400 both lose
  six in a row. The bot's fight with the king is a race it either always wins or always loses, so
  "1-2 deaths at the boss" cannot be dialled in for it; 1,500 leaves the novice winning narrowly,
  which a person playing less evenly than the bot will often not do.

## Iteration 2 (tag `iter2`)

Commits `80dc086` (bot) and `322de67` (data).

| Change | Before -> after | Why |
| --- | --- | --- |
| `ability.ogre_smash` power | 50 -> 40 (58 -> 46 damage to a stage-1 giant; the ogre is shorter than the giant, so no size bonus) | 8 of the novice's 13 forest deaths; the forest ogre is a stage-1 fight with no healing yet |
| `enemy.soldier` strike pause | 0.8-1.4 -> 1.2-1.8 s | Two hunters at the giant's legs alternate blows faster than a stage-1 guard and stamina can take: every expert run died there. Soldiers hold and brace from stage 2 on, so this is mostly the stage-1 soldiers' pace (spec §10: they "pause between strikes") |
| The bot gives up a fight that takes no health off its target for 20 s and leaves that enemy alone for 30 s (never the boss) | `scripts/debug/valley_bot.gd` | Bot fix: the crown-stage timeout chasing a harassing wolf |

No test pins either number.

| Skill | Policy | Completed | Human est. median (min) | Raw median (min) | Deaths median (boss) | Max deaths in another segment |
| --- | --- | --- | --- | --- | --- | --- |
| novice | force | 2 / 3 | 16.0 | 12.1 | 1 (0) | 1 |
| novice | help_cache | 5 / 5 | 16.6 | 11.1 | 1 (0) | 1 |
| novice | help_ogre | 5 / 5 | 16.1 | 10.6 | 1 (0) | 1 |
| novice | intimidate | 5 / 5 | 12.9 | 8.7 | 0 (0) | 0 |
| expert | force | 1 / 1 | 21.8 | 17.9 | 1 (0) | 1 |
| expert | help_cache | 1 / 1 | 18.3 | 13.2 | 0 (0) | 0 |
| expert | help_ogre | 1 / 1 | 18.1 | 13.4 | 0 (0) | 0 |
| expert | intimidate | 1 / 1 | 17.7 | 13.5 | 1 (0) | 1 |

- Completed novice runs 12 -> 17 of 18; **the expert completes all four policies with 0-1 deaths**
  (it died twice in all four runs: an arrow and a brace).
- **The forest settled**: its novice deaths 13 -> 5 (a wolf 3, the smash 2) and no forest timeout;
  the segment's damage 1.62 -> 1.39 x maximum health.
- Novice deaths 24 -> 18: the brace 7, archer shots 3, wolves 3, the ogre's smash 2, the King 2, a
  mage bolt 1; by segment: ruins 11, forest 5, boss 2. One run (intimidate seed 5) died twice at the
  King before beating him; the others won the first attempt with 1-29 % of their health left
  (median 18 %).
- The one novice that did not finish (force seed 3) stood at the barrow for 240 s: it gave up on the
  two harassing wolves in turn (every 20 s) but each came back after the 30 s it left them alone, so
  the crown was never reached. The bot now leaves a given-up enemy alone for 90 s (commit `25c1fb7`,
  measured by the confirmation matrix below).
- Growth: HOLD 58 % at stage 2, FLEE or ROUTED 55 % at stage 3, time-to-kill ratio 0.54 (all three
  targets met). CPU per tick p95: median 5.74 ms, max 6.86 ms. Off-camera hits: median 27 %.

**No third tuning iteration.** What is still off target is either a property of the bot (the boss
race above; Sweeping Blow, which the bot's ability rules rarely reach because Heavy Footfall comes
first; the off-camera share, which counts the archers and mages behind the giant's back that the
novice cannot see by design) or pacing that only content could add: the human estimate is 15-16
minutes against 20-30 because the bot neither explores nor learns, and the Hollow, the forest and
the Grove, where a first-time player spends that time, are floors in the estimate
(`docs/HOW_IT_PLAYS.md`). The segment damage targets (0.6 x maximum health in the forest and the
ruins) are missed by the novice model's design: it takes a quarter of the blockable blows and 30 % of
the dodgeable ones whole, so damage piles up in long fights while deaths, the measure that matters
to a player, stay at about one a run.

## Confirmation (tag `final`)

The build of commit `25c1fb7`: iteration 2's game, the bot leaving a given-up enemy alone for 90 s.

| Skill | Policy | Completed | Human est. median (min) | Raw median (min) | Deaths median (boss) | Max deaths in another segment |
| --- | --- | --- | --- | --- | --- | --- |
| novice | force | 2 / 3 | 16.6 | 12.7 | 2 (0) | 1 |
| novice | help_cache | 5 / 5 | 16.5 | 11.0 | 1 (0) | 1 |
| novice | help_ogre | 5 / 5 | 15.6 | 10.3 | 1 (0) | 1 |
| novice | intimidate | 5 / 5 | 12.9 | 8.7 | 0 (0) | 0 |
| expert | force | 1 / 1 | 20.3 | 16.6 | 1 (0) | 1 |
| expert | help_cache | 1 / 1 | 18.3 | 13.2 | 0 (0) | 0 |
| expert | help_ogre | 1 / 1 | 18.1 | 13.4 | 0 (0) | 0 |
| expert | intimidate | 1 / 1 | 18.0 | 13.7 | 1 (0) | 1 |

- The force seed-3 run that stalled at the barrow in `iter2` now gets past it and, on this
  trajectory, runs out of the Deadfall stage's 240 s on the return leg instead (the village's guards
  and militia and the return patrol on the road; 2,460 damage taken in the stage). The other 21
  runs finish in both batches; ten are identical, eleven took another path where a chase was given
  up (deaths the same in all but two: help_cache seed 5 3 -> 1, intimidate seed 5 3 -> 4).
- Novice deaths 19: the brace 6, archer shots 4, wolves 3, the ogre's smash 2, the King 3 (two
  runs), a mage bolt 1; by segment: ruins 10, forest 5, boss 3, return 1.
- The §5.6 targets, met and missed, are tabled in `docs/HOW_IT_PLAYS.md`.

## P22 (wave 13): the Valley items after P22 (tags `p22_base`, `p22_after`, `p22_iter1`)

**How it is measured.** The M6-M9 matrix (plan §6.4): novice and expert x {help_cache, help_ogre,
intimidate, force} x seeds 1-3, 24 unassisted runs, three at a time (`tools/run_bots.sh --tag=<tag>
--timeout=1500 --autoplay=2400 --jobs=3` with the 24 `policy:skill:seed` runs), on P22's base
(`ae6e143`, tag `p22_base`) and on P22's build (`p22_after`), in the development container while
the other lane worked beside it. One `p22_after` run (intimidate novice seed 3) crashed in the
audio mixing thread at the Grove (FOLLOWUPS, "From P22"); it was run again with the same seed and
finished; that rerun is in the tables. The plan's targets: plan §3.4 design 9.

### What P22 changed that the bot sees

No balance number: the guard posts and the step-back (Thornwick), the yard fill, the ranged units'
front arc and off-camera aim time (`tactics.front_arc_deg` 150, `off_camera_aim_s` 1.2), the merged
rigs and the distance LOD.

| Skill | Policy | Completed, base -> P22 | Human est. median (min), base -> P22 | Deaths median (boss), base -> P22 |
| --- | --- | --- | --- | --- |
| novice | force | 3 / 3 -> 3 / 3 | 14.2 -> 14.8 | 1 (0) -> 0 (0) |
| novice | help_cache | 3 / 3 -> 3 / 3 | 14.9 -> 15.7 | 1 (0) -> 1 (0) |
| novice | help_ogre | 3 / 3 -> 3 / 3 | 14.7 -> 15.0 | 1 (0) -> 1 (0) |
| novice | intimidate | 2 / 3 -> 3 / 3 | 13.9 -> 12.7 | 1 (0) -> 1 (0) |
| expert | force | 1 / 3 -> 3 / 3 | 19.1 -> 18.3 | 1 (0) -> 0 (0) |
| expert | help_cache | 3 / 3 -> 3 / 3 | 19.0 -> 17.2 | 1 (0) -> 1 (0) |
| expert | help_ogre | 3 / 3 -> 3 / 3 | 20.3 -> 18.0 | 1 (0) -> 0 (0) |
| expert | intimidate | 3 / 3 -> 2 / 3 | 19.3 -> 16.8 | 3 (0) -> 0 (0) |

| Item (plan §3.4 design 9, design 8) | Target | Base | P22 |
| --- | --- | --- | --- |
| Off-camera hits (attacker outside the camera's view at its windup), median share of the hits taken | under 20 % | 25 % (max 38 %) | **16 %** (max 37 %) |
| Thornwick hostile at the end of a help or intimidate run (`faction_hostile`) | never | (not recorded) | **never** (18 unassisted runs and the two assisted runs below) |
| The novice's tries at the Ogre King (deaths there, median) | 1-2 deaths | 0 | 0 (one death in 12 runs) |
| Damage per segment, forest (x maximum health, novice median) | <= 0.6 | 1.27 | 1.27 (no ranged enemy there: unchanged) |
| Damage per segment, ruins | <= 0.6 | 1.00 | 1.23 |
| The force branch's return leg inside the 240 s watchdog | 3 of 3 | novice 3 / 3, expert 1 / 3 | **novice 3 / 3, expert 3 / 3** |
| The expert on seeds 1-3 | runs | 10 / 12 completed | 11 / 12 completed (intimidate seed 3: the crown stage's watchdog) |

- Novice deaths 9 at P22 (base 9): wolves' lunges 4, the brace 2, a mage bolt 1, the King's slam 1,
  an archer's shot 1; by segment: forest 4, ruins 4, boss 1. Expert deaths 6 (base 14).
- Growth (novice median): HOLD 57 % at stage 2, FLEE or ROUTED 40 % at stage 3 (base 40 %; target
  50 %), time-to-kill ratio 0.56. CPU per tick p95 median 4.59 ms, max 7.81 ms; 0 errors, 0
  invariant failures.
- **Thornwick, assisted** (the plan's check: `help_cache:novice:1:assist`,
  `intimidate:novice:1:assist`, tag `p22_assisted`): both complete with 0 deaths, `faction_hostile`
  false, the village outcome as chosen, 0 errors and 0 warnings.

### Iteration 1 (tag `p22_iter1`, reverted)

| Change | Before -> after | Why |
| --- | --- | --- |
| `enemy.ogre` strike pause | 0.6-1.2 -> 1.2-1.8 s | The forest's damage: the ogre's smash and sweep come back to back |
| `enemy.wolf` strike pause | 0.6-1.2 -> 1.0-1.6 s | Wolves' lunges were 4 of the 9 novice deaths |
| `enemy.soldier` strike pause | 1.2-1.8 -> 1.6-2.2 s | The ruins' damage: the brace counter follows the same pause |
| `enemy.archer` strike pause | 0.6-1.2 -> 1.0-1.6 s | The courtyard's terrace archer shoots through the whole fight |

The novice half of the matrix answered it (11 runs; one crashed in the audio thread like the one
above; the expert half was stopped):

| Measure | P22 | Iteration 1 |
| --- | --- | --- |
| Forest damage per seed (novice, seeds 1 / 2 / 3) | 694 / 522 / 1,022 | 776 / 740 / 1,055-1,581 |
| Forest damage / maximum health, median | 1.27 | 1.42 |
| Forest deaths (novice runs) | 4 | 6 |
| Runs stopped by the forest's 240 s watchdog | 0 | 2 (help_cache novice seed 3, help_cache expert seed 1) |
| Ruins damage / maximum health, median | 1.23 | 1.15 |

Slower enemies make longer fights, not cheaper ones: the novice model takes the same share of the
blows whole, and the openings it punishes come less often, so the forest's fights ran longer and
cost more, and two of them ran out of the stage's 240 s. **Reverted** (the records keep P17b's
pauses). No second iteration: the remaining levers are the attacks' damage, which the novice
model's design (it takes a quarter of the blockable blows and 30 % of the dodgeable ones whole,
P17b) would need halved to reach 0.6, and the boss race P17b measured (the bot either always wins
or always loses at a given health) cannot be dialled to 1-2 deaths by a number. The segment damage
and the boss items stay missed, as at the end of P17b; the off-camera share, Thornwick and the
force branch's return leg are met.

## M6 gate (wave 14): the Valley matrix after the gate's fixes (tag `m6gate_final`)

**How it is measured.** As P22's: the M6-M9 matrix (novice and expert x {help_cache, help_ogre,
intimidate, force} x seeds 1-3, 24 unassisted runs, three at a time: `tools/run_bots.sh
--tag=m6gate_final --timeout=1500 --autoplay=2400 --jobs=3` with the 24 `policy:skill:seed` runs),
plus `intimidate:expert:4`, `:5` and `:6` (three more seeds of the cell the gate's review found
failing) and the plan's two assisted Thornwick runs (`help_cache:novice:1:assist`,
`intimidate:novice:1:assist`): 29 runs on the gate's code (`013dd9c`), with nothing else running in
the container. The review ran the same 24 + 2 runs on the merged wave (`17dbed3`); its numbers are
quoted where it gave them.

### What the gate changed that the bot sees

- **Seeded runs replay exactly, with or without audio** (the review's finding 2): the loading gate
  also waits for the level's navigation map, the autopilot and the bot do nothing while it holds,
  and headless runs sync navigation on the main thread. Every run's timeline moved, so a seed here
  is not the same run as that seed in an earlier batch: the tables compare cells, not runs.
- **A wolf pack broken by a giant that outmatches it routs** instead of coming back to harass
  (`tactics.outmatched_rout`; the wolf's ratio is 6, so from stage 2 on) (finding 4).
- **The bot's stall at an encounter** (P17b: with every living member out of reach for 8 s it walks
  on or takes its objective) now lasts while the giant stays within 15 m of the encounter, where a
  dodge past 6 m restarted it (finding 4).
- No balance number changed. The threat alerts' mix class (finding 3) is audio only.

### The matrix

| Skill | Policy | Completed: P22 -> review (`17dbed3`) -> gate | Human est. median (min), P22 -> gate | Deaths median (boss), P22 -> gate |
| --- | --- | --- | --- | --- |
| novice | force | 3 / 3 -> 3 / 3 -> 3 / 3 | 14.8 -> 15.2 | 0 (0) -> 0 (0) |
| novice | help_cache | 3 / 3 -> 3 / 3 -> 3 / 3 | 15.7 -> 15.0 | 1 (0) -> 0 (0) |
| novice | help_ogre | 3 / 3 -> 3 / 3 -> 3 / 3 | 15.0 -> 13.9 | 1 (0) -> 0 (0) |
| novice | intimidate | 3 / 3 -> 3 / 3 -> 3 / 3 | 12.7 -> 12.7 | 1 (0) -> 0 (0) |
| expert | force | 3 / 3 -> 3 / 3 -> 3 / 3 | 18.3 -> 18.4 | 0 (0) -> 0 (0) |
| expert | help_cache | 3 / 3 -> 3 / 3 -> 3 / 3 | 17.2 -> 18.5 | 1 (0) -> 0 (0) |
| expert | help_ogre | 3 / 3 -> 3 / 3 -> 3 / 3 | 18.0 -> 17.5 | 0 (0) -> 0 (0) |
| expert | intimidate | 2 / 3 -> 1 / 3 -> **3 / 3** | 16.8 -> 16.4 | 0 (0) -> 0 (0) |

### The review's finding 4: the expert's crown stage on the intimidate path

| Measure (expert, intimidate, seeds 1-3) | Review (`17dbed3`) | Gate |
| --- | --- | --- |
| The crown stage (s; its watchdog is 240 s) | 225.4 / watchdog / watchdog | **55.1 / 39.6 / 55.4** |
| "Gave up chasing" a Barrow warden wolf | 3-4 a run | 0 |
| Aware wolves near the giant at stage 3 (s, all of a run's): outmatched (harassing) / in Flee | 505-634 / 161-231 | 64-125 / 48-72 |

The review's base for comparison (`22ed6ca`, the same seeds): 156, 118 and 78 s. The novice's
intimidate crown took 107 and 74 s in the review, 45-50 s here; the help paths' 35-56 s there,
29-53 s here; the force runs' 50-99 s. Seeds 4 and 6 of the expert cell take the crown in 92.8 and
48.3 s (seed 5 stopped earlier, below). The gate tier replays the pre-crown save with this bot
(`tests/gate/test_barrow_crown.gd`): seeds 1 and 2 claim the crown in 90.2 and 85.7 s; with the
wolves' rout but the bot's 6 m stall both ran out the 240 s, a lone unbroken wolf harassing the
giant at the crown.

### The plan's Valley items

| Item (plan §3.4 design 9, design 8; §6.4) | Target | P22 | M6 gate |
| --- | --- | --- | --- |
| Off-camera hits (attacker outside the camera's view at its windup), median share of the hits taken | under 20 % | 16 % (max 37 %) | **20 %** (20.4 %, max 29.5 %): a miss by 0.4 points; the novice's runs 16.8 %, the expert's 20.9 % |
| Thornwick hostile at the end of a help or intimidate run (`faction_hostile`) | never | never | **never** (18 unassisted runs and the two assisted runs; the six force runs end hostile, as that branch means) |
| The novice's tries at the Ogre King (deaths there, median) | 1-2 deaths | 0 (one death in 12 runs) | 0 (one death in 12 runs) |
| Damage per segment, forest (x maximum health, novice median) | <= 0.6 | 1.27 | 1.23 |
| Damage per segment, ruins | <= 0.6 | 1.23 | 1.00 |
| The force branch's return leg inside the 240 s watchdog | 3 of 3 | novice 3 / 3, expert 3 / 3 | novice 3 / 3, expert 3 / 3 (the Deadfall stage 80-124 s and 86-178 s) |
| The expert on seeds 1-3 | 3 of 3 a policy, at most 2 deaths each | 11 / 12 completed | **12 / 12**, no death |

- Novice deaths 6 (P22 9): the brace 2, an archer's shot 2, a mage's bolt 1, the King's combo 1; by
  segment: ruins 5, boss 1. Expert deaths 0 (P22 6).
- Growth (novice median): HOLD 56 % at stage 2, FLEE or ROUTED 52 % at stage 3 (P22 40 %; target
  50 %), time-to-kill ratio 0.51. CPU per tick p95 median 3.63 ms, max 4.02 ms; 0 errors, 0
  warnings, 0 invariant failures, 0 teleports; 21 stuck events, all recovered.
- **Thornwick, assisted** (`help_cache:novice:1:assist`, `intimidate:novice:1:assist`): both
  complete with 0 deaths, `faction_hostile` false, the village outcome as chosen, 0 errors and 0
  warnings.
- **The off-camera share** is reported as a miss (plan §6.4). Each run here is a new run (the
  timelines moved) and a run's share spreads from 4 % to 30 %, so a 24-run median moves by a few
  points between batches; the gate's changes do not reach the ranged units (the expert intimidate
  cell's seeds 1-3 took the same hits, off camera and all, with and without the wolves' rout and the
  bot's stall: 10 of 37, 14 of 96, 17 of 98). P39's loop measures it again at M9 (FOLLOWUPS).
- **Seed 5 of the expert intimidate cell** (outside the plan's seeds) stopped in the forest at stage
  1: `quest.main:ogre` ran past its 240 s watchdog (a death to a hunter's slash, a rest at the
  Hollow's shrine, the forest's fight again), before the village - every policy of that seed plays
  the same forest - and before any of the gate's changes act (the wolves are not outmatched at stage
  1, and a kill objective never stalls). Recorded for P39 (FOLLOWUPS).

## M9 (P39), iteration 0: the world and the Valley before tuning (tags `p39_iter0_world`, `p39_iter0_valley`)

Plan M6-M9 §6.2-§6.4. The game as W22 left it (`wave-22`, 1c33b8e) with nothing tuned, measured by the
world bot after P39's measurement fixes (below; `docs/systems/P38.md`, "P39 (W23)"), on the bot of commit
`b6fc032`. Every Godot run went through `tools/gd.sh`, two at a time on the 4-CPU container beside the
other W23 lane's work, so wall times and the CPU and streaming numbers are indicative.

**How it is measured.**

```
# §6.2 stability
tools/run_bots.sh --preset=world_stability --jobs=1 --timeout=5400 --tag=p39_world_stability3   # w.peaceful:novice:1:assist --bot-loop, 3,600 s
tools/run_bots.sh --preset=stability --jobs=1 --timeout=2700 --tag=p39_valley_stability
tools/run_bots.sh w.campaign:novice:1:assist --jobs=1 --timeout=5400 --tag=p39_campaign
# §6.4 item 1: the world matrix (the novice on seeds 1-2: the plan's rule when wall time is short)
tools/run_bots.sh w.{peaceful,conqueror,mixed}:novice:{1,2} w.{peaceful,conqueror,mixed}:expert:{1,2,3} \
  w.order_{march,wood,crown}:novice:1 --jobs=2 --timeout=3600 --tag=p39_iter0_world        # 18 runs, --autoplay=7200
# the Valley matrix (regression), as the M6 gate ran it: 24 runs, two at a time (two --jobs=1 streams
# of the same tag, so the full check could run beside the first)
tools/run_bots.sh {help_cache,help_ogre,intimidate,force}:{novice,expert}:{1,2,3} --jobs=1 --timeout=1500 \
  --autoplay=2400 --tag=p39_iter0_valley
python3 tools/bot_report.py ".userdata/godot/app_userdata/Giantborn- Age of Titans/bot_runs/p39_iter0_world" \
  world_targets world_summary world_segments world_bosses world_growth world_lone world_deaths
```

(the brace expansions are written out as single runs on the command line)

### What P39 changed in the bot before measuring (plan §3.23: measurement mistakes and mechanics the bot never tried)

All listed in `docs/systems/P38.md`, "P39 (W23)", each with its slow test (`tests/slow/test_bot_measures_p39.gd`):

| Change | Why (what P38's runs or P39's first runs showed) |
| --- | --- |
| Formation lock samples only while a formation is engaged with the giant | P38 counted every lock while any formation lived in the loaded world |
| §6.4's growth shares measured directly (lone humans, formations with their banner, lesser-only music), and the lone humans by archetype and state | P38 had them only through the AI-state histogram, where pikemen and a lone soldier share an archetype |
| The boss fights' damage by source | the M8 release check's question (the Iron Regiment's ballistae, about 85 %) |
| An engine's throw is no slotted ability in the ability share | it inflated the share's denominator |
| Siege disruption at stage 6 (strike, seize, throw an engine) | P38's runs threw 0-1 engines (§6.4: at least 2 per run reaching stage 6) |
| Waystones and shrines within 50 m walked into on the way | P38's runs lit few stones, so fast travel never had a visited stone near a far goal |
| A loop's next game counts its rewards afresh | the first 60-minute run stopped at its first loop on a false "reward granted twice" |
| The abilities' look waits for a free tick from stage 4 | the novice's light chains spent its looks: Titan Stomp 0 of 9 ready windows |
| Shots at an enemy above reach only along a clear line, from a spot chosen by it | the second 60-minute run stood 964 s under the toll fort's tower, every bolt striking its deck |
| A lone big foe (boss, troll, rival giant) within reach draws the roar and the area blows from stage 4 | the first two matrix runs died 6 and 7 times to Harrok with Earthquake never used |
| Load node counts kept with the level and place | a world load's count depends on the chunks around it |

### Stability (plan §6.2)

| Run | Result | Notes |
| --- | --- | --- |
| The Valley, 30 minutes (`--preset=stability`: help_cache novice assisted, `--bot-loop`) | **pass** | 1,800 s simulated in 832 s of wall; three loops completed (help_cache 507 s, help_ogre 473 s, intimidate 490 s); exit 0; no breach, no `world_blocked`, no duplicated reward, no invariant failure; nodes after each load 1,552 / 1,559 / 1,559 / 1,552 (0.5 %), orphans 0; 0 errors, 0 warnings; 0 deaths, 0 teleports, 2 stuck events (recovered); CPU per tick p95 5.18 ms |
| The campaign hand-over (`w.campaign:novice:1:assist`: the Valley's New Game, the Kings' Door, Brannock's oath, then on) | **pass** | the Valley in 503 s, the Kings' Door, the march sworn to Edda at 612 s, and on to the Stone Throne (2,016 s simulated, 1,152 s wall, campaign complete); exit 0, no breach, no invariant failure, 0 errors, 0 warnings, 0 deaths; its two loads are two levels (the Valley 1,552 nodes, the world 1,118) |
| The world, 60 minutes (`--preset=world_stability`) - first try (the P38 bot) | stopped (exit 3) | a false "reward granted twice" at the loop's second game: the bot's fix (above); not a game fault |
| The world, 60 minutes - second try | the plan's criteria held but one: the node count | 3,600 s simulated, the first game complete in 2,346 s, the second (conqueror) under way; exit 0, no `world_blocked`, no duplicated reward, no invariant failure, 0 errors, 0 warnings; one `bot_failed` breach (the march's toll fort tower, 964 s: the bot's fix above) and its reload by the toll fort (1,810 nodes against the start's 1,116 - a different place, see the load samples' change); the two starts 1,116 / 1,123 (0.6 %) |
| The world, 60 minutes - on the matrix's bot (`p39_world_stability3`, `9e2105b`) | **pass** | 3,600 s simulated in 2,439 s of wall, exit 0; two loops completed (peaceful in 1,591 s and conqueror in 1,280 s, both with 0 deaths; the mixed one under way at the end); no breach, no `world_blocked`, no duplicated reward, no invariant failure (the lock and targeting invariant included); 3 loads, 1,116 / 1,123 / 1,123 nodes at the Kingsgate shelf (0.6 %), orphans 0; 0 errors and 0 warnings; 0 teleports, 8 stuck events (recovered); CPU per tick p95 7.77 ms |

The world processes print, after their `AUTOPILOT_RESULT`, Godot's exit report of leaked resources
("ObjectDB instances leaked at exit", "N resources still in use at exit", Jolt shapes and dummy meshes):
static caches (`EncounterDirector._scene_cache`, `WorldRoot._preloaded`) still hold their scenes at quit.
They come after the run's own error count (0) and W22's smoke run printed them too; the other W23 lane's
P38 hand-over reports them.

### The world matrix (plan §6.4 item 1)

18 unassisted runs, `--autoplay=7200` and 3,600 s of wall time each, two at a time: the novice on seeds
1-2 of the three presets, the expert on seeds 1-3, and `world_orders` (each oath first, seed 1). No run
crashed, met an invariant failure, an error or a warning, or a duplicated reward; one stop was
diagnosed `world_blocked` (below). Every run but one stopped on its watchdog: six deaths on one main
stage, or the stage's time limit.

| Skill | Assisted | Preset | Oaths | Completed | Human est. median (min) | Raw median (min) | Deaths median | world_blocked |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| expert | no | conqueror | march:force,wood:slay | 0 / 3 | - | - | 2 | 1 |
| expert | no | mixed | march:intimidate,crown:sabotage | 0 / 3 | - | - | 5 | 0 |
| expert | no | peaceful | march:help,wood:drive | 0 / 3 | - | - | 5 | 0 |
| novice | no | conqueror | march:force,wood:slay | 0 / 2 | - | - | 7 | 0 |
| novice | no | mixed | march:intimidate,crown:sabotage | 0 / 2 | - | - | 7 | 0 |
| novice | no | peaceful | crown:breach,wood:slay | 0 / 1 | - | - | 5 | 0 |
| novice | no | peaceful | march:help,crown:parley | 0 / 1 | - | - | 6 | 0 |
| novice | no | peaceful | march:help,wood:drive | 1 / 2 | 41.0 | 30.9 | 6 | 0 |
| novice | no | peaceful | wood:drive,march:force | 0 / 1 | - | - | 6 | 0 |

Where each run stopped:

| Run | Stage reached | Stopped at | Why | Deaths (by whom) | Human est. (min) |
| --- | --- | --- | --- | --- | --- |
| w_peaceful_novice_1 | 6 | Harrok's duel | 6 deaths | 6 (Harrok 6) | 37.4 |
| w_peaceful_novice_2 | 6 | - | completed | 5 (Harrok 4, troll 1) | 41.0 |
| w_conqueror_novice_1 | 5 | the den | 6 deaths | 7 (the Matriarch 6, soldier 1) | 20.2 |
| w_conqueror_novice_2 | 5 | the den | 6 deaths | 7 (the Matriarch 6, troll 1) | 19.8 |
| w_mixed_novice_1 | 5 | the crown's meeting | 6 deaths | 6 (ballistae 5, soldier 1) | 19.9 |
| w_mixed_novice_2 | 6 | Harrok's duel | 6 deaths | 8 (Harrok 6, rival_giant 2) | 28.5 |
| w_peaceful_expert_1 | 6 | Harrok's duel | watchdog | 5 (Harrok 4, soldier 1) | 66.7 |
| w_peaceful_expert_2 | 4 | the march (toll fort) | 6 deaths | 6 (the toll fort 5, soldier 1) | 22.9 |
| w_peaceful_expert_3 | 4 | the march (toll fort) | watchdog | 5 (the toll fort 4, mage 1) | 24.3 |
| w_conqueror_expert_1 | 5 | the den | watchdog | 2 (ogre 1, the Matriarch 1) | 25.9 |
| w_conqueror_expert_2 | 5 | the den | watchdog | 1 (ogre 1) | 26.7 |
| w_conqueror_expert_3 | 5 | the den | watchdog | 2 (archer 1, troll 1) | 26.1 |
| w_mixed_expert_1 | 6 | Harrok's duel | watchdog | 5 (Harrok 4, troll 1) | 34.1 |
| w_mixed_expert_2 | 6 | Harrok's duel | watchdog | 5 (Harrok 5) | 35.7 |
| w_mixed_expert_3 | 6 | Harrok's duel | watchdog | 4 (Harrok 4) | 32.3 |
| w_order_wood_novice_1 | 4 | the den | 6 deaths | 6 (the Matriarch 6) | 17.2 |
| w_order_crown_novice_1 | 4 | the crown's meeting | watchdog | 5 (ballistae 5) | 25.1 |
| w_order_march_novice_1 | 6 | Harrok's duel | 6 deaths | 6 (Harrok 6) | 31.2 |

`w_conqueror_expert_2`'s stop is the matrix's one `world_blocked`: its den stage ran out of time with
the giant 375 m south-west of the den, where the diagnosis found no titan path back (layers 112, the
stage-5 mask) - the bot had left the den in its last 180 s, which no note records (no trace was taken).
The other two conqueror experts ran out the same stage in the den.

### The targets (plan §6.4 item 2)

`python3 tools/bot_report.py <p39_iter0_world> world_targets`:

| Target (plan §6.4) | Value | Met |
| --- | --- | --- |
| Completion, novice: at least 2 of 3 seeds per preset | peaceful 1 / 2, conqueror 0 / 2, mixed 0 / 2 | **miss** |
| Completion, expert: 3 of 3, at most 2 deaths each | peaceful 0 / 3 (deaths max 6), conqueror 0 / 3 (deaths max 2), mixed 0 / 3 (deaths max 5) | **miss** |
| Every first-oath order completes | crown no (breach), march no (breach), wood no (breach) | **miss** |
| Human estimate of the main path 75-140 min (novice median, completed runs) | 41.0 min (raw 30.9; per preset peaceful 41.0, conqueror -, mixed -) | **miss** |
| Each §5.15 segment within its range (novice median) | Opening 4.3 (7-14); First oath 9.1 (10-30); Second oath 11.2 (18-35); Growth to 5, roaming 5.6 (0-40); Stonehold 10.9 (15-32) | **miss** |
| Deaths: 1-3 per boss attempt sequence (novice median) | battle not met; matriarch median 3.0 (runs 6/6/0/0); harrok median 6.0 (runs 6/6/4) | **miss** |
| Deaths: at most 2 in any other segment (novice) | max 6 (w_mixed_novice_1 Second oath) | **miss** |
| Lone humans flee or rout >= 70 % of their engaged time, stages 4-6 (pooled) | 3 % (melee only, archers and mages left out as §5.14 keeps them at range: 0 % of 256 s) | **miss** |
| Formations hold or brace >= 50 % of their engaged time while the banner lives (pooled) | 82 % | met |
| At least half of the locks at stages 4-6 are formation groups or banners while a formation is engaged (pooled) | 75 % | met |
| At least 2 engines thrown per run that reaches stage 6 | 7 of 7 runs (per run 8/4/4/4/4/4/4) | met |
| Off-camera share of the hits taken under 20 % | median 12 % (pooled 12 % of 3129 hits) | met |
| Music in combat under 25 % of stage 4-6 time among only lesser enemies (pooled) | 38 % | **miss** |
| Every slotted ability used at least once a run | never used when ready, by runs: boulder_hurl 14, sweeping_blow 12, crag_hurl 8, titan_stomp 7, crushing_grip 7, heavy_footfall 5, formation_sweep 4, rampart_grip 4, stone_skin 3, titan_surge 2, thunder_roar 1 | **miss** |
| No ability over 40 % of ability damage | max 65 % (titan_stomp, w_conqueror_novice_1) | **miss** |
| Worst streaming work frame <= 12 ms (headless; two runs at a time on 4 shared CPUs) | 33.6 ms | **miss** |
| Loaded margin >= 200 m and no thrash | min 254 m, thrash 0 | met |
| CPU per tick p95 <= 8 ms | median 7.16 ms, max 9.92 ms | **miss** |

The rows the report does not judge: the XP and equipment budget tests (margins of at least 50 XP) pass
in the default tier of this commit's check; the Valley's items are the Valley matrix's (below).

### Why the misses (iteration 0)

Each cause below is what the runs show; "bot" marks a miss that measures the bot rather than the game
(plan §3.23: fixed in the bot before iteration 1's matrix), "game" one the tuning plan answers in data.

- **Harrok (game).** Every run that reached the Moot stopped at its duel but one: the novice died there
  6, 6 and 6 times (`w_peaceful_novice_1`, `w_mixed_novice_2`, `w_order_march_novice_1`) and 4 times
  in the one completed run, which won on its fifth try; the expert's peaceful run and its three mixed
  ones ran out the duel's 626 s after 4-5 deaths each. The overhead chop is the killing blow in 28 of
  the matrix's 39 deaths to Harrok and deals most of what he deals to the novice (63-77 % of the damage
  taken in his duel; the expert's 38-52 %). It is unblockable, 120 power, an 18 m line 5.8 m wide after a 1.4 s windup: at
  stage 6 (capsule radius 3.7 m) it strikes anything within 6.6 m of its line, so only a dodge timed into
  its i-frames (0.10-0.30 s of the roll) or carried 6.6 m sideways escapes it; the novice dodged 7 and
  12 times in its two peaceful runs. Each death reloads at the Moot's foot and the duel starts again
  from his full 5,000 health: the novice's attempts reached his phase 2 (half health or two poise
  breaks) in 1 of 6, 1 of 6, 3 of 6 and 2 of 5 (the won run), the expert's in 1-2 of 5-6.
- **The Troll Matriarch (game).** Driven out at stage 4 (`w_order_wood_novice_1`, the wood's oath
  first) she killed the novice 6 times (her stomp 4, her sweep 2) and never reached her phase 2 or the
  drive-out's 60 %. Slain at stage 5, both conqueror novices died 6 times in her bowl
  (11 of their 12 attempts reached her phase 2; the killing blows: her stomp 4, the whelps and their
  throws 4, the frenzy 3, the sweep 1); the three conqueror experts took 0-2 deaths but never brought her to phase 2
  in the den's 745 s (13,989 / 25,347 / 17,180 damage dealt in the den, whelps included): her
  regeneration (25 hp/s, 40 in phase 2, stopped only by 8 s of Burning beside one of three braziers)
  matches what the giant deals, as the M8 gate's F37 measured at stage 4. Driven out (the peaceful
  path, at stage 5) she fled in 112 s with no death.
- **Ballistae: the Ballista Ridge and the Iron Regiment (game).** `w_mixed_novice_1` died 5 times in a
  row to the ridge's ballistae on the way to the crown's meeting at stage 5, 50-75 s apart (the run
  counts 5 engines destroyed over those tries). `w_order_crown_novice_1` (the crown breached first, at
  stage 4) fought the Iron Regiment five times and died five times, every time to a fort ballista: the
  ballistae dealt 4,233 of the 5,472 the giant took in the battle (77 %; the M8 release check's 85 %),
  the battle never reached the Charge, and the bot gave up its ranged blows at the east and west
  ballistae and at the wall's two crews 15 times (8 s each without harm: from the bailey at stage 4
  nothing it throws reaches them). The bar the Wall leaves is 62 % of 14,080 (the M8 release check's
  8,760: the Charge, the Last Stand, four ballistae and the two crews), above the Charge's 60 %: with
  no engine or crew broken, the Charge never comes. The bolt is 90 power, 140 poise, unparryable,
  along a 140 m line.
- **The toll fort for the expert (bot).** The expert's runs that died there (`w_peaceful_expert_2`, 6
  deaths; `_3`, 5 deaths and the stage's watchdog) swung 68 and 56 light attacks in the whole run where
  the novice runs swung 213-253, and blocked 197 and 221 times: P17a's expert answers every blow aimed at
  it within 12 m and every shot at any range (a rule set for the Valley's handfuls of enemies), so before
  a pike formation with a tower of archers over it there is always a block or a dodge planned within
  20 ticks and it seldom attacks; the abilities' look also waits for the giant out of a block, so
  Sweeping Blow was used 0 and 1 times in 216 and 198 ready windows. The novice runs crossed the same
  fort at the same stage with no death. Its archers dealt 4,939 and 4,180 of the 9,090 and 8,500 the
  expert took in those runs. The skill ceiling is therefore not one in the world yet: the expert's
  completion row measures this rule, not the game.
- **Pace (game content and the bot's straight path).** The one completed novice run took 41.0 minutes
  by the human estimate (30.9 raw); its segments: the opening 4.3 min (target 7-14), the first oath 9.1
  (10-30), the second 11.2 (18-35), the growth to 6 and roaming 5.6 (0-40, met), the Stonehold 10.9
  (15-32). The bot walks straight from objective to objective (`--bot-explore` 0, as the matrix's
  presets): exploration is measured in the targeted run below.
- **Lone humans (game, and the measure's scope).** Pooled over the runs, lone humans fled or routed
  3 % of their engaged time at stages 4-6, the melee ones 0 % of 256 s (by archetype, `lone_states`:
  archers 7,010 s engaged and 2 % fled, mages 1,134 s and 10 %, soldiers 302 s and none). A lone soldier's awe costs 35
  of its 70 morale once, leaving 35 above its flee threshold of 25, so a lone soldier fights a stage-4
  giant to the end (the soldier record is shared with the Valley, where awe applies from stage 3: its
  ratio to a stage-3 giant is 4.4). Most of the pooled time is the toll fort's tower archers, which hold
  the tower by design (M7b B3) and shoot on: the two experts that stalled at the fort had lone humans
  engaged with them for 1,339 and 1,500 s.
- **Music among lesser enemies (audio data).** 38 % of the time among only lesser enemies at stages
  4-6 was in `combat` (target under 25 %): all of it in the mixed runs' Aldmere stretches
  (`w_mixed_novice_2` 65.8 of 65.9 s, `w_mixed_expert_2` 20.4 of 20.4 s, the ridge and its crews), 48 % of
  `w_peaceful_expert_2`'s, 0-23 % elsewhere. Not a §6.4 data lever (the music's
  intensity rules are P28's mix data): reported for the music's owner.
- **Abilities (bot).** Never used when ready, by runs (of 18): Boulder Hurl 14 (its rule wants a locked
  archer beyond 10 m or an elevated target), Sweeping Blow 12, Crag Hurl 8, Titan Stomp 7, Crushing
  Grip 7, Heavy Footfall 5, Formation Sweep 4, Rampart Grip 4, Stone Skin 3, Titan Surge 2, Thunder
  Roar 1; with few abilities used, one
  takes most of the ability damage (Titan Stomp 65 % in `w_conqueror_novice_1`). P17b kept every player
  number; this is the bot's ability policy.
- **Streaming and CPU (the container).** The worst work frame (33.6 ms) and the runs' CPU per tick p95
  over 8 ms (median 7.16 ms, max 9.92 ms) were measured with two bot runs and the other lane's builds on 4 CPUs; the
  loaded margin (254 m minimum) and thrash (0) are met. The other W23 lane measures the world walk's
  work frame alone (P39f, "web").

### Targeted measurements (plan §6.4 item 3; FOLLOWUPS "From the M8 release check" and "From the M8 gate review")

On the bot of `9e2105b` (the matrix's, plus each boss attempt's lowest health share), the novice
unassisted, one run at a time beside the 60-minute run; `tools/run_bots.sh <run> --jobs=1 --timeout=3600
--tag=<tag> --extra="<args>"`:

| Tag | Run and arguments | What it measures |
| --- | --- | --- |
| `p39_ir4` | `w.order_crown:novice:2`, `--bot-until=oath.crown.done` | the Iron Regiment at stage 4 (the crown breached first; seed 1 is the matrix's `w_order_crown_novice_1`) |
| `p39_ir5` | `w.peaceful:novice:1`, `--bot-oaths=march:help,crown:breach --bot-until=oath.crown.done` | the Iron Regiment at stage 5 |
| `p39_mat4_slay` | `w.peaceful:novice:1`, `--bot-oaths=wood:slay,march:intimidate --bot-until=oath.wood.done` | the Troll Matriarch slain at stage 4 |
| `p39_mat4_drive` | `w.order_wood:novice:2`, `--bot-until=oath.wood.done` | the Matriarch driven out at stage 4 (seed 1 is the matrix's `w_order_wood_novice_1`) |
| `p39_skarn5`, `p39_skarn6` | `w.peaceful:novice:1`, `--bot-skarn=5` / `6`, `--bot-until=world.skarn.saved` | the siege of Skarn at stages 5 and 6, its five engines broken first |
| `p39_explore30` | `w.peaceful:novice:1:assist`, `--bot-explore=0.3` | what exploring adds to the pace |

**The Iron Regiment (the M8 release check's R3).** Neither stage wins it, and the bar never falls far:

| Run | Stage | Battle attempts | Each attempt's lowest bar | Deaths (all in the crown's stage) | Damage the giant took in the battle |
| --- | --- | --- | --- | --- | --- |
| `w_order_crown_novice_1` (matrix) | 4 | 5 | not measured (before `lows`) | 5, all fort ballistae | 5,472: ballistae 4,233 (77 %), soldiers 1,239 |
| `p39_ir4` (`order_crown`, seed 2) | 4 | 5 | 87 %, 90 %, 80 %, 75 %, 76 % | 5: ballistae 3, the pikes' brace 2 | 4,161: ballistae 2,822 (68 %), soldiers 1,339 |
| `p39_ir5` (peaceful, then the breach) | 5 | 1 | 84 % | 6: ballistae 5 (three before the battle engaged, two after), a wall archer 1 | 281 in the one engaged attempt; 7,899 in the battle's stage |

No run reached the Charge (no phase change), broke an engine (0 destroyed, 0 thrown: siege
disruption is a stage-6 permission) or harmed a wall crew: the bot gave up its ranged blows at the
fort's ballistae and the wall crews 15 times in each stage-4 run and 4 times at stage 5. Unassisted, the
novice does not fell the Wall either (its lowest bars 75-90 %; the M8 release check's assisted run
reached 62 %, the Wall felled and nothing that shoots). The ballistae are the battle's killer at both
stages (147 engine shots at the giant in the stage-5 run). Iteration 1's ballista and Charge changes
(the plan, below) answer this; the battle's lows are the check.

**The Troll Matriarch at stage 4 (the M8 gate's F37, deferred to P39).** With the stall gone (F36) and
the bot's fire rule (a brazier broken while she stands within 8 m of it):

| Run | Resolution | Attempts | Each attempt's lowest health | Deaths | Result |
| --- | --- | --- | --- | --- | --- |
| `w_order_wood_novice_1` (matrix) | drive | 6 | not measured | 6 (her stomp 4, her sweep 2) | stopped on its sixth death; no attempt reached her phase 2 (half health) |
| `p39_mat4_drive` (`order_wood`, seed 2) | drive | 4 | 66 %, 70 %, 69 %, 60 % | 3 (her sweep 3) | driven out on the fourth attempt (fled at 0.596), 342 s in the den |
| `p39_mat4_slay` (peaceful, the wood slain first) | slay | 6 | 77 %, 46 %, 53 %, 50 %, 49 %, 48 % (open) | 6 (her frenzy 3, her stomp 2, her sweep 1) | stopped: phase 2 in four attempts, never under 46 % |

At stage 4 the drive-out is within reach (one run of two, with 3 deaths) and the slay is not: in her
phase 2 (40 hp/s) the giant held her at 46-53 % until her frenzy killed it. Iteration 1's regeneration
change (25 / 40 -> 15 / 25 hp/s) is aimed there; the slay and drive runs above are its check, with the
den's 1-3 deaths per sequence as the target.

**The siege of Skarn (FOLLOWUPS: "The siege of Skarn's pace is untuned").** The bot takes Ulfra's plea
on its way to the Standing Stones (stage 5) or arrives at stage 6, then breaks the line's five engines
nearest first while defending:

| Run | Stage | Siege | Deaths | Engines broken | What happened |
| --- | --- | --- | --- | --- | --- |
| `p39_skarn5` | 5 | started 70,080 (1,168 s), not ended when the run stopped 525 s later | 6 (catapult stones 3, ballista bolts 2, a rider's charge 1) | 3 (the same ballista three times: each death's reload brings the line back as the last checkpoint saw it) | the line's 119 shots went at the giant, so no longhouse fell (the event's fail needs two) and the line never broke |
| `p39_skarn6` | 6 | started on arrival (the bot fast-travelled to Skarn's waystone from the Standing Stones: the first fast travel in P39's runs), saved 60 s later | 0 | 5 of 5, all seized and thrown | 6 shots at the giant, 1,065 damage taken, the line routed as its last engine fell |

At stage 6 the siege is a minute of throwing engines, the growth showing; at stage 5 the line's five
engines and its riders kill the novice before it breaks them (catapult stones 2,424 and ballista bolts
2,573 of the damage taken there). The siege is the player's choice at stage 5 (Ulfra's plea), so it is
tuned for a fair fight rather than removed: iteration 1's ballista change and a lighter catapult stone
(below), checked with `p39_skarn5` again; the halls' health and the fail timer stay (no longhouse fell
in either run).

**The Iron Regiment's web aggregate (11,740 against the plan's about 12,300; FOLLOWUPS).** Kept for
iteration 0. The battle's phases are fractions of its own aggregate, so the web's composition (the
Wall's formations at 0.7, the guard at 0.5, so the bailey fits the web's 20 formation members) moves no
phase threshold; its 4.6 % short of the plan's figure is a shorter Wall and Last Stand, not a different
fight. The battle is not yet won on either composition (above), so the web aggregate is revisited with
iteration 1's Charge threshold, which is set from both aggregates.

### P38's findings (the hand-over in `docs/systems/P38.md`)

- **Engines thrown**: met. P39's siege disruption at stage 6 (strike, seize, throw) gives 4-8 engines
  thrown in each of the 7 runs that reached stage 6 (P38: 0-1).
- **The formation lock share**: met, 75 % pooled. P38 sampled every lock while any formation lived in
  the loaded world (4-41 %); P39 samples only while one is engaged with the giant, and the bot's lock
  rule (the Valley's) already locks the group it fights.
- **Fast travel**: never used in the matrix (0 in 18 runs), though the bot now walks into the waystones
  and shrines within 50 m of its way (4-13 lit a run); the targeted stage-6 Skarn run used it once (from
  the Standing Stones' shrine to Skarn's waystone, the siege's goal). Its rule takes the map's Travel to
  a goal more than 600 m off with a visited stone within 200 m of the goal; every far goal of every preset's main path
  is a first visit (the oaths' places, the Ironway, the Stones, the Moot), and a death's reload puts
  the giant at the checkpoint beside its fight. Fast travel is a player's return trip (a forge, a
  shrine, an old oath's place), which the main path does not make (the exploration run below made none
  either). Not a balance item.
- **Fights the bot gives up** (by rule, 0-15 a run): chases given up after 20 s (trolls of the
  woodcutters' camp and the wanderers 15, the toll fort's pikes and archers 7, scouts 4, the raider
  ogre 3), and ranged blows given up after 8 s without harm - all but three of them the Iron Regiment's
  fort ballistae and wall crews in `w_order_crown_novice_1` (15), which is that battle's stop (above).
  The toll fort's tower archers took 5 failed shot spots in `w_peaceful_expert_3` (the clear-line rule
  moving on, as designed).
- **The pace** (§6.4: the human estimate of the main path 75-140 min; P38: 23-42 min, "a bot's, not a
  player's"). The target is judged, as written, on the novice's unassisted runs that complete: 41.0
  min (the one completed run, 30.9 raw). What exploring adds was measured on one seed with the assist
  (so that no run stops on the way): explore 0 (the 60-minute run's first game) 36.0 min, 26.5 raw;
  `--bot-explore=0.3` (30 % of each oath region's places before its oath, `p39_explore30`) 39.5 min,
  29.6 raw, 21 places discovered, no death, no fast travel - 3.5 minutes more. Neither is near 75: the
  main path is short when played straight, and the rest of §5.15's estimate is content the main path
  does not ask for (sealed places, cairns, side quests, the third oath). No §6.4 data lever lengthens
  the main path without slowing growth or adding fights the targets do not ask for, so this miss is
  the report's (`docs/HOW_IT_PLAYS.md`), not the tuning plan's; the 100 % exploration run
  (`targeted.sh explore100`) is left for when the report wants the upper bound.

### The Valley matrix (regression; plan §6.4 item 1)

The M6 gate's matrix again (novice and expert x the four outcomes x seeds 1-3, 24 unassisted runs,
`--timeout=1500 --autoplay=2400`), on this branch's bot (its P39 changes act from stage 4 or in the
world only, so the Valley's rules are W22's); tag `p39_iter0_valley`, `python3 tools/bot_report.py
<batch> summary targets growth`:

| Skill | Policy | Completed: M6 gate -> P39 | Human est. median (min), M6 gate -> P39 | Deaths median (boss), M6 gate -> P39 |
| --- | --- | --- | --- | --- |
| novice | force | 3 / 3 -> 3 / 3 | 15.2 -> 14.9 | 0 (0) -> 0 (0) |
| novice | help_cache | 3 / 3 -> 3 / 3 | 15.0 -> 15.0 | 0 (0) -> 0 (0) |
| novice | help_ogre | 3 / 3 -> 3 / 3 | 13.9 -> 14.0 | 0 (0) -> 0 (0) |
| novice | intimidate | 3 / 3 -> 3 / 3 | 12.7 -> 12.6 | 0 (0) -> 0 (0) |
| expert | force | 3 / 3 -> **2 / 3** | 18.4 -> 18.1 | 0 (0) -> 0 (0) |
| expert | help_cache | 3 / 3 -> 3 / 3 | 18.5 -> 18.8 | 0 (0) -> 0 (0) |
| expert | help_ogre | 3 / 3 -> 3 / 3 | 17.5 -> 17.2 | 0 (0) -> 0 (0) |
| expert | intimidate | 3 / 3 -> 3 / 3 | 16.4 -> 16.4 | 0 (0) -> 0 (0) |

| Item (plan §3.4, §6.4; `docs/HOW_IT_PLAYS.md`) | Target | M6 gate | P39 iteration 0 |
| --- | --- | --- | --- |
| Off-camera hits, median share of the hits taken | under 20 % | 20 % (a miss by 0.4 points) | 19 % |
| Thornwick hostile at the end of a help or intimidate run | never | never | never (18 runs) |
| The novice's tries at the Ogre King (deaths there, median) | 1-2 deaths | 0 | 0 |
| Damage per segment, forest / ruins (x maximum health, novice median) | <= 0.6 | 1.23 / 1.00 | 1.23 / 1.00 |
| The force branch's return leg inside the 240 s watchdog | 3 of 3 | novice 3 / 3, expert 3 / 3 | novice 3 / 3 (the Deadfall 80, 124 and 221 s), expert **2 / 3** (113 and 115 s; seed 2 ran out the watchdog, below) |
| The expert on seeds 1-3 | 3 of 3 a policy, at most 2 deaths each | 12 / 12, no death | 11 / 12, no death |
| Soldiers in FLEE or ROUTED at stage 3 (novice median) | at least 50 % | 52 % | **38 %** (runs 11-61 %) |

- Novice deaths 5 (M6 gate 6), all in the ruins: the brace 2, an archer's shot 2, a mage's bolt 1.
  CPU per tick p95 median 5.47 ms, max 5.93 ms; 0 errors, 0 warnings, 0 invariant failures; one
  teleport (`force_expert_3`), 26 stuck events, all recovered.
- **The stage-3 flee share** read 40 % at P22 and 52 % at the M6 gate: a run's share spreads 11-61 %,
  so a 12-run median moves by more than the target's margin between batches. The world soldier record
  of iteration 1's plan would leave the Valley's soldiers as they are; if the Valley's share is to be
  held above 50 %, the shared `enemy.soldier`'s awe loss is the lever for both (a stage-3 giant is 4.4
  times a soldier's height), checked with this matrix.
- **The expert's force run on seed 2** stopped on the Deadfall stage's 240 s watchdog with no death
  (health 525 of 935). Replayed with a trace (`p39_valley_trace`, `--bot-trace=2`; the same stop at
  the same tick): about 206 s of the stage went to fights with the ruins' patrol and gate guards on the
  way back from Kingsfall (the patrol's mage and archers, the gate soldiers in HOLD, the patrol captain),
  and the giant was 17 m from the deadfall when the watchdog ran out. The expert's other two force runs
  took 113 and 115 s, the M6 gate's 86-178 s; the novice's seed 3 took 221 s. A slow expert fight, not
  a blocked path: the bot changes of iteration 1's plan (the expert's answers to blows) are re-checked
  on this seed.

### The plan for iteration 1

**The bot first** (plan §3.23: these misses measure the bot; each with its slow test, then the expert's
nine runs again before any number is judged):

| Bot change | Why (iteration 0) |
| --- | --- |
| From stage 4 the expert answers only blows that can land on it soon (its attacker within the blow's range of the giant's capsule, a shot only when no blow of its own is under way), and a planned answer never holds its attack off for more than about a second | the toll fort: 68 and 56 light attacks a run against the novice's 213-253, 197 and 221 blocks, 6 and 5 deaths where the novice had none |
| The abilities' look from stage 4 may release a block to cast | Sweeping Blow 0 and 1 of 216 and 198 ready windows in those runs, the expert blocking at every look |
| The ability policy covers every slotted ability: Boulder Hurl and Crag Hurl at shooters on walls and towers and at engines, Sweeping Blow and Formation Sweep at a formation's front, Heavy Footfall / Titan Stomp at a crowd or a big foe | of 18 runs, 14 never used Boulder Hurl when ready, 12 Sweeping Blow, 8 Crag Hurl, 7 Titan Stomp; one ability took 65 % of a run's ability damage |
| The Matriarch slain: with no brazier within 8 m of her, the giant draws her to one (stands beyond it) before breaking it | F37 asks for the fire "used as designed, a human-like policy"; the experts' 745 s at the den never reached her phase 2 |

**Then the data** (plan §6.4 item 3; every number within the spec's windup floors, no behaviour
removed):

| Change | From -> to | Reason | Checking runs |
| --- | --- | --- | --- |
| `ability.harrok_chop` power | 120 -> 95 | the killing blow in 28 of 39 deaths to Harrok and 63-77 % of what he dealt to the novice; the windup (1.4 s) and the 18 m line stay | `w.{peaceful,mixed}:novice:{1,2}` and the mixed and peaceful experts (the five runs that reached him): deaths per duel 1-3 (novice median), the expert at most 2 |
| `enemy.harrok` health | 5,000 -> 4,300 | the novice's attempts reached his phase 2 in 1-3 of 5-6; the yield comes at 25 % or the third poise break | as above, with each attempt's lowest health share (`lows`, P39) |
| `enemy.troll_matriarch` `regeneration.hp_per_s` / `phase_hp_per_s.2` | 25 / 40 -> 15 / 25 | her regeneration matches the giant's damage (F37 at stage 4, the conqueror experts at stage 5); `brazier_burn_s` stays 8 | `w.conqueror:{novice,expert}:{1,2,3}`, the stage-4 slay and drive runs (`p39_mat4_*`): deaths in the den 1-3 |
| the Matriarch's phase-2 `summon` | 3 -> 2 | 11 of the conqueror novices' 12 attempts died in her phase 2; the whelps and their throws were 4 of the 12 killing blows | as above |
| `ability.ballista_bolt` power / poise | 90 / 140 -> 60 / 100 | 5 deaths in a row on the Ballista Ridge (`w_mixed_novice_1`); about 85 % of the Iron Regiment's damage (the M8 release check) | `w.mixed:novice:{1,2}`, the Iron Regiment runs (`p39_ir4`, `p39_ir5`, `w_order_crown`): at most 2 deaths outside a boss, the engines' share of the battle's damage under half |
| the Iron Regiment's Charge: its phase's `below` (`tools/data/world/aldmere.json`, the battle arena; a world rebuild of its chunk) | 0.6 -> 0.64 | the Wall's fall leaves the bar at 0.622 of 14,080 with no engine or crew broken, and nothing the giant throws from the bailey at stage 4 reached the fort's ballistae or the wall's crews (15 ranged tries given up); the web composition's bar after the Wall is worked out the same way and the threshold set above both | `p39_ir4`, `p39_ir5`, `w.order_crown:novice:1`: the Charge reached, the battle's lows, deaths 1-3 |
| `ability.catapult_stone` power | 110 -> 85 | the siege of Skarn at stage 5: 3 of the novice's 6 deaths and 2,424 damage (the line's 119 shots went at the giant); the 2.0 s windup and the 6 m circle stay | `p39_skarn5` (and `p39_skarn6`, saved in 60 s, unchanged): the siege won at stage 5 with at most 3 deaths |
| a world soldier record for the world's encounters: `enemy.soldier`'s numbers with `tactics.awe_morale_loss` 50 (a lone soldier at 70 morale falls to 20, under its flee threshold of 25) | 35 -> 50, the world only | lone melee humans fled 0 % of 256 s at stages 4-6 (target at least 70 %); the Valley keeps `enemy.soldier` (its awe applies from stage 3, ratio 4.4, and the Valley's stage-3 numbers are met); a formation's members keep their banner's morale | the novice matrix's growth row (melee only), re-measured on the merged W23 (the other lane changed the raiders' rout from a far giant) |

Neither the XP curve nor the wander weights change in iteration 1: every run grew on time for its path
(stage 5 at 270-750 s, stage 6 at 820-1,490 s on the novice's runs) and the pace is the report's
(P38's findings, above), not the wanderers'.

## M9 (P39), iteration 1: the bosses, the engines and the bot's answers and abilities (tags `p39_i1d_*`, `p39_i1_world`)

Plan M6-M9 §6.4 item 3: the data of iteration 0's plan (above) and the bot's measurement fixes, checked by
the world matrix again. Every number below is data within the spec's windup floors (no windup, telegraph or
behaviour changed); the bot changes act from stage 4 only, so the Valley's rules (and its matrix) are
iteration 0's.

**What changed, and why** (commits `a2da78e` data, `1537836` and `b20617f` bot):

| Change | From -> to | Reason (iteration 0) |
| --- | --- | --- |
| `ability.harrok_chop` power | 120 -> 95 | the killing blow in 28 of the matrix's 39 deaths to Harrok, 63-77 % of what he dealt the novice; the 1.4 s windup and the 18 m line stay |
| `enemy.harrok` health | 5,000 -> 4,300 | the novice's attempts reached his phase 2 in 1-3 of 5-6; he yields at 25 % or his third poise break, as before |
| `enemy.troll_matriarch` regeneration (`hp_per_s` / phase 2) | 25 / 40 -> 15 / 25 hp/s | her regeneration matched what the giant deals (F37 at stage 4; the conqueror experts at stage 5 never reached her phase 2; the stage-4 slay held at 46-53 % by 40 hp/s); `brazier_burn_s` stays 8 |
| the Matriarch's phase-2 `summon` | 3 -> 2 whelps | 11 of the conqueror novices' 12 attempts died in her phase 2, the whelps and their throws 4 of the 12 killing blows |
| `ability.ballista_bolt` power | 90 -> 60 | five deaths in a row on the Ballista Ridge (`w_mixed_novice_1`); the Iron Regiment's ballistae 68-77 % of the damage the giant took in the battle. Its poise stays 140: plan decision 21 and P32's test want a bolt to stagger a stage-4 giant (iteration 0's plan had 140 -> 100, which would end that) |
| `ability.catapult_stone` power | 110 -> 85 | the siege of Skarn at stage 5: 3 of the novice's 6 deaths and 2,424 of the damage it took; the 2.0 s windup and the 6 m circle stay |
| Bot: from stage 4 the expert answers only blows that can land, an arrow holds no blow off, and answers hold its blows off one second at most (`BotCombat`, `docs/systems/P38.md`) | P17a's rules | the toll fort: the expert swung 68 and 56 lights a run against the novice's 213-253, and died there 6 and 5 times where the novice did not |
| Bot: from stage 4 every slotted ability takes its turn (one unused for 20 s is used when nothing refuses it), and the two area blows alternate | P17a's rules | of 18 runs, 14 never used Boulder Hurl when ready, 12 Sweeping Blow, 8 Crag Hurl, 7 Titan Stomp; Titan Stomp took 65 % of one run's ability damage |
| Bot: in the slay the giant draws the Matriarch to a standing brazier before breaking it | P38's rule (a brazier broken only when she stands beside one) | F37: the fire used as designed; the conqueror experts' 745 s in the den never reached her phase 2 |

Not changed in iteration 1, though iteration 0's plan listed them:

- **The Iron Regiment's Charge threshold** (the battle arena's phase `below`, 0.6) is in the world layout
  (`tools/data/world/aldmere.json`), which this lane does not touch while the other W23 lane rebuilds the
  world; it is the confirmation phase's (below, "Left for the confirmation phase").
- **The lone soldier's awe** (`tactics.awe_morale_loss`): its share must be measured again on the merged W23
  (the other lane changed the raiders' rout from a giant they do not see), and the lone humans' pooled share
  is the toll fort's tower archers', which hold the tower by design (M7b B3): see iteration 2.

**How it was measured.**

```
# the data alone on iteration 0's bot (a2da78e): the Iron Regiment at stage 4, as p39_ir4
tools/run_bots.sh w.order_crown:novice:2 --jobs=1 --timeout=3600 --tag=p39_i1d_ir4 --extra="--bot-until=oath.crown.done"
# the matrix's 18 runs on b20617f (the data and the bot), two at a time, from a snapshot of that commit
tools/run_bots.sh <iteration 0's 18 runs> --jobs=2 --timeout=3600 --tag=p39_i1_world
python3 tools/bot_report.py <p39_i1_world> world_targets
```

The matrix was stopped after 11 of its 18 runs (the novice's six, the peaceful experts' three, the
conqueror experts' seeds 1-2): by then Harrok had stopped every run that reached him and iteration 2's
changes were clear; the mixed experts and the three first-oath orders run in iteration 2's matrix, on the
same Matriarch, engine and bolt numbers.

**The Iron Regiment at stage 4 with the bolt at 60** (`p39_i1d_ir4`, the iteration-0 bot): 5 deaths (fort
ballistae 4, a soldier 1), the ballistae 66 % of the damage the giant took in the battle (iteration 0's
`p39_ir4`: 68 %), no Charge, and the crown's meeting stage ran out its 1,040 s; ranged blows given up at
the fort's ballistae 5 times and at the wall crews 6 times. A lighter bolt does not open the battle at
stage 4: the bar the Wall leaves (0.622) is above the Charge's 0.6 and nothing the giant throws from the
bailey harms an engine or a crew. The threshold (`tools/data/world/aldmere.json`) is the confirmation
phase's.

**The runs** (iteration 0 -> iteration 1; deaths by killer):

| Run | Iteration 0 | Iteration 1 | Bosses (attempts, each attempt's lowest health share) |
| --- | --- | --- | --- |
| w_peaceful_novice_1 | Harrok's duel, 6 deaths (Harrok 6) | the wood's oath (stage 4): 6 deaths to the woodcutters' two trolls | - |
| w_peaceful_novice_2 | **completed**, 5 deaths (Harrok 4, troll 1), 41.0 min | **completed**, 3 deaths (Harrok 2, archer 1), 40.2 min | the Matriarch driven out at 0.59 in 1 attempt; Harrok spared on the 3rd (0.48, 0.42, 0.25) |
| w_conqueror_novice_1 | the den, 7 deaths (Matriarch 6) | Harrok's duel, 10 deaths (the den 4, Harrok 6) | the Matriarch 4 (0.38, 0.29, 0.37, 0.34), fled; Harrok 6 (0.64-0.39), yielded twice, struck, not slain |
| w_conqueror_novice_2 | the den, 7 deaths (Matriarch 6) | Harrok's duel, 9 deaths (the den 2, archer 1, Harrok 6) | the Matriarch 2 (0.64, 0.26), fled; Harrok 6 (0.46-0.33), yielded three times, not slain |
| w_mixed_novice_1 | the crown's meeting, 6 deaths (ridge ballistae 5) | Harrok's duel, 6 deaths (Harrok 6) | Harrok 6 (0.62-0.30), never yielded |
| w_mixed_novice_2 | Harrok's duel, 8 deaths (Harrok 6) | Harrok's duel, 6 deaths (Harrok 6) | Harrok 6 (0.60-0.26), never yielded |
| w_peaceful_expert_1 | Harrok's duel, watchdog, 5 deaths | the Raiders' Hollow, 6 deaths (mage 3, archer, soldier, ogre) | - |
| w_peaceful_expert_2 | the toll fort, 6 deaths | the Raiders' Hollow, 6 deaths (archer 2, soldier 2, mage, ogre) | - |
| w_peaceful_expert_3 | the toll fort, watchdog, 5 deaths | the Raiders' Hollow, 6 deaths (archer 3, ogre 2, soldier) | - |
| w_conqueror_expert_1 | the den, watchdog, 2 deaths | Harrok's duel, watchdog, 7 deaths (Harrok 5) | the Matriarch 2 (0.81, 0.57), fled; Harrok 6 (0.68-0.26) |
| w_conqueror_expert_2 | the den, watchdog (`world_blocked`), 1 death | Harrok's duel, watchdog, 5 deaths (Harrok 4) | the Matriarch 1 (0.59), fled; Harrok 5 (0.56-0.34) |

What iteration 1 did:

- **The Ballista Ridge** (bolt 90 -> 60): `w_mixed_novice_1` crossed it with no death (iteration 0: five
  deaths in a row there); no run died to an engine outside the Iron Regiment.
- **The den** (regeneration 15 / 25, two whelps, the lure): every run that reached it got through - the
  conqueror novices with 4 and 2 deaths (iteration 0: 6 and 6, stopped), the experts with 1 and 0 (iteration
  0: 745 s without her phase 2). But in all four the lure broke the den's three braziers, the three nests
  burned, the woodfolk opened the back wall and she fled at 60 %: the conqueror's slay became a drive-out.
  Iteration 2's bot keeps the last brazier standing in the slay.
- **Harrok** (health 4,300, chop 95): every run that reached him but one stopped there - the novice's
  deaths per duel 6, 6, 6, 6 and 2 (median 6; iteration 0 median 6), its attempts' lowest shares 0.25-0.67
  (median about 0.40, where he yields at 0.25 or at his third poise break); the conqueror novices brought him to
  yield 2 and 3 times and then could not finish him. Of the 35 deaths to him in the 11 runs the chop is
  still the killing blow in 17 (the falling stones of his phase 2 8, his frenzy 7, his charge 3) and 59 % of the
  damage he deals (36,308 of 61,675).
- **The peaceful experts** reached the Raiders' Hollow (two of them crossed the toll fort, where iteration 0
  stopped them) and died there six times each: the light-shot rule took the raiders' mage's slowing bolt
  (20 power, a spell) for an arrow, so the expert struck through it, was slowed and caught (the mage 3 of
  `w_peaceful_expert_1`'s killing blows). Iteration 2: an arrow is the only light shot.
- **The woodcutters' trolls** (two at the Greywood's woodcutters' camp, on the way to Sedge at stage 4)
  killed `w_peaceful_novice_1` six times; iteration 0's run on the same seed walked past them. Its abilities
  now hurt them, so its 20 s chase give-up never ran out. One run of eleven: watched, not tuned (the troll
  record is shared by every troll, and the camp's second troll stands in the Greywood's solids until the
  other W23 lane's fix merges).
- **Abilities**: never used when ready, by runs (of 11): Boulder Hurl 11 (slotted at stage 3 in the world's
  opening, where the rotation did not act), Rampart Grip 7, Sweeping Blow 7, Earthquake 6, Titan Stomp 6,
  Heavy Footfall 5, Crushing Grip 5, Stone Skin 4, Titan Surge 2, Formation Sweep 1 (iteration 0, of 18:
  Boulder Hurl 14, Sweeping Blow 12, Crag Hurl 8, Titan Stomp 7, Crushing Grip 7). The largest share 100 %
  (Runic Bolt in `w_peaceful_expert_1`, which died before stage 5), else 29-52 %.

**The targets after iteration 1** (`world_targets`, 11 runs): completion novice peaceful 1 / 2, conqueror
0 / 2, mixed 0 / 2; expert 0 / 5; human estimate 40.2 min (the one completed run); segments Opening 4.3,
First oath 11.0 (met), Second oath 9.9, Roaming 5.7 (met), Stonehold 9.4; deaths per boss: the Matriarch
median 1.0 (runs 3 / 1 / 0, met), Harrok median 6.0; other segments max 6 (the woodcutters' trolls);
lone humans 2 % (melee 0 % of 210 s); formations hold 84 % (met); group locks 88 % (met); engines thrown
7 of 7 (met); off-camera 11 % (met); lesser-enemy music 51 %; abilities as above; worst work frame 172.4 ms
and CPU per tick p95 median 8.78 ms (two runs at a time beside the other lane's checks); margin 254 m,
thrash 0 (met).

## M9 (P39), iteration 2: Harrok, and the bot's arrows, abilities and the slay (tag `p39_i2_world`)

**What changed, and why** (commits `6726c18` data, `65293ad` bot):

| Change | From -> to | Reason (iteration 1) |
| --- | --- | --- |
| `enemy.harrok` health | 4,300 -> 3,400 | the novice's attempts ended at 0.25-0.67 of his health (median about 0.40) where he yields at 0.25: about 60 % of 4,300 dealt a try, which is 75 % of 3,400 |
| `ability.harrok_chop` power | 95 -> 75 | still the killing blow in 17 of the 35 deaths to him and 59 % of the damage he dealt; the 1.4 s windup and the 18 m line stay |
| Bot: an arrow is the only light shot (a projectile under 20 power that is no spell) | every projectile under 30 | the raiders' mage's slowing bolt (20, a spell) was taken for an arrow: the three peaceful experts, slowed while they struck, died six times each at the Raiders' Hollow |
| Bot: the rotation takes Stone Skin and Titan Surge too, and acts in the world at any stage | the heal, Stone Skin and Surge on their own rules; stage 4 on | Boulder Hurl (slotted in the world's stage-3 opening) never used in 11 of 11 runs; Stone Skin never used in 4, Titan Surge in 2 (their rules want a boss or three enemies) |
| Bot: the slay keeps the den's last brazier standing (neither lured to nor broken) | every brazier broken by the slay | with the three nests burned the woodfolk open the back wall and she flees at 60 %: all four conqueror runs drove her out instead of slaying her |

**How it was measured**: the matrix's 18 runs on `65293ad` from a snapshot, two at a time (`--tag=p39_i2_world`);
stopped after 11 runs (the novice's six, the three peaceful experts, the conqueror experts' seeds 1 and 3 - seed
2 was stopped in Harrok's duel, past the den, to free its slot) once iteration 3's den and expert changes were
clear; the mixed experts and the orders run in iteration 3.

| Run | Iteration 1 | Iteration 2 | Bosses (attempts, each attempt's lowest health share) |
| --- | --- | --- | --- |
| w_peaceful_novice_1 | the woodcutters' trolls, 6 deaths | **completed**, 2 deaths (Harrok 2), 35.7 min | the Matriarch driven out at 0.58 (1 attempt); Harrok spared on the 3rd (0.32, 0.37, 0.25) |
| w_peaceful_novice_2 | completed, 3 deaths | **completed**, 1 death (Harrok 1), 32.9 min | driven out at 0.59 (1); Harrok spared on the 2nd (0.61, 0.25) |
| w_conqueror_novice_1 | Harrok, 10 deaths | **completed**, 6 deaths (a troll 1, Harrok 5), 35.0 min | the Matriarch slain in 1 attempt; Harrok slain on the 6th (0.62, 0.36, 0.20, 0.33, 0.09, 0) |
| w_conqueror_novice_2 | Harrok, 9 deaths | the den, 7 deaths (the Matriarch's sweep 2 and frenzy 2, her whelps 2, a raider 1) | the Matriarch 6 (0.34, 0.47, 0.35, 0.33, 0.49, 0.36): not slain |
| w_mixed_novice_1 | Harrok, 6 deaths | **completed**, 2 deaths (Harrok 2), 24.7 min | Harrok spared on the 3rd (0.46, 0.43, 0.25) |
| w_mixed_novice_2 | Harrok, 6 deaths | **completed**, 3 deaths (Harrok 3), 25.3 min | Harrok spared on the 4th (0.45, 0.36, 0.35, 0.25) |
| w_peaceful_expert_1-3 | the Raiders' Hollow, 6 deaths each | the Raiders' Hollow, 6 deaths each (soldiers 5, archers 5, mages 5, the ogre 3 in all) | - |
| w_conqueror_expert_1 | Harrok, watchdog | the den, watchdog, 2 deaths | the Matriarch 2 (0.48; open at 0.48) |
| w_conqueror_expert_3 | (stopped) | the den, watchdog, 2 deaths | the Matriarch 2 (0.80; open at 0.49) |

What iteration 2 did:

- **Harrok** (3,400 health, chop 75): five of the six novice runs that reached him won the duel - spared
  on the 2nd-4th attempt (lowest shares 0.25 each time he yielded) or, in the conqueror run, slain on the
  6th; the novice's deaths per duel 5, 2, 3, 2, 1 (median 2: the target's 1-3). Five of the six novice
  runs completed (iteration 1: one of six).
- **The den, slain**: with the last brazier kept, the conqueror novices slew her once in one attempt
  (seed 1) and once not at all (seed 2: six attempts held at 0.33-0.49 in her phase 2), and both conqueror
  experts ran out the den's time near half her health (0.48, 0.49). The lure did not work: every brazier
  was given up at once ("not reached in 20 s") because each lure's walk clock was left from an earlier
  attempt - a bot fault fixed in iteration 3. At 25 hp/s in her phase 2 she outheals a giant that fights her
  without fire; iteration 3 lowers it.
- **The peaceful experts** died six times each at the Raiders' Hollow again (the arrow-only light shot did
  not change it): the one-second hold cap had them strike through the answers due and be caught by the
  raiders' soldiers, ogre and archers. Iteration 3 drops the cap.
- The woodcutters' trolls killed no run (one death to a troll in all 11).

**The targets after iteration 2** (`world_targets`, 11 runs): completion novice peaceful 2 / 2, conqueror
1 / 2, mixed 2 / 2 (on seeds 1-2: the plan's rule when wall time is short); expert 0 / 5; human estimate
32.9 min (median of the five completed; raw 23.5); segments Opening 3.8, First oath 2.4, Second oath 8.6,
Roaming 5.6 (met), Stonehold 8.9; deaths per boss: Harrok median 2.0 (runs 5 / 2 / 3 / 2 / 1, **met**), the
Matriarch median 0.0 (runs 0 / 6 / 0 / 0); other segments max 1 (**met**); lone humans 2 % (melee 0 % of
237 s); formations 89 % (met); group locks 92 % (met); engines thrown 5 of 5 (met); off-camera 10 % (met);
lesser-enemy music 45 %; never used when ready: Titan Stomp 6 runs, Earthquake 5, Heavy Footfall 5,
Rampart Grip 4, Crag Hurl 3, Boulder Hurl 3, Crushing Grip 1, Formation Sweep 1; the largest share 90 %
(Runic Bolt in a peaceful expert that died at stage 4), the novice's runs 31-51 %; worst work frame 61.0
ms and CPU per tick p95 median 17.3 ms (two runs at a time while the other lane's full checks ran);
margin 253 m, thrash 0 (met).

## M9 (P39), iteration 3: the Matriarch's regeneration and the expert's answers (tag `p39_i3_world`)

The last of §6.4's three iterations. **What changed, and why** (commit `cee2edd`):

| Change | From -> to | Reason (iteration 2) |
| --- | --- | --- |
| `enemy.troll_matriarch` regeneration (`hp_per_s` / phase 2) | 15 / 25 -> 12 / 15 hp/s (a troll's 12; her phase 2 still regenerates faster) | the slay held at 0.33-0.49 for the conqueror novice (seed 2, six attempts) and at 0.48 / 0.49 for the conqueror experts, who ran out the den's time: in her phase 2 she outhealed a giant fighting her without fire |
| Bot: the expert's one-second hold is dropped (an answer due holds its blows off again, as P17a's did; arrows still hold nothing off, and blows that cannot land are still not answered) | iterations 1-2's hold cap | the three peaceful experts died six times each at the Raiders' Hollow in both iterations, struck mid-blow by the raiders' soldiers, ogre and archers while the answer they had planned was due |
| Bot: a lure taken up again after a gap (0.5 s) starts its walk and wait afresh | the walk clock kept from an earlier attempt | iteration 2's den runs gave every brazier up at once ("not reached in 20 s") on clocks left from an earlier attempt, so no fire was drawn |

**How it was measured**: the runs that iteration 2 left or missed, on `cee2edd` from a snapshot, two at a time:

```
tools/run_bots.sh w.conqueror:novice:2 w.order_crown:novice:1 w.order_wood:novice:1 w.order_march:novice:1 \
  w.{conqueror,peaceful,mixed}:expert:{1,2,3} --jobs=2 --timeout=3600 --tag=p39_i3_world
tools/run_bots.sh force:expert:2 --jobs=1 --timeout=1500 --autoplay=2400 --tag=p39_i3_valley   # the Valley replays
```

| Run | Before (iteration 1 or 2) | Iteration 3 | Bosses (attempts, each attempt's lowest health share) |
| --- | --- | --- | --- |
| w_conqueror_novice_2 | the den, 7 deaths (i2) | the den, 7 deaths (the Matriarch's frenzy 3, stomp 2, a whelp 1, a raider 1) | the Matriarch 6 (0.48, 0.32, 0.24, 0.38, 0.84, 0.36): not slain |
| w_order_crown_novice_1 | the crown's meeting, 5 deaths (iteration 0) | the crown's meeting, 6 deaths (fort ballistae 5, a soldier 1) | the battle 6 (0.85, 0.79, 0.65, 0.69, 1.0, 0.69): no Charge |
| w_order_wood_novice_1 | the den, 6 deaths (iteration 0) | **completed**, 3 deaths (the den's troll 1, Harrok 2), 30.1 min | the Matriarch driven out at stage 4 on the 1st attempt (0.59); Harrok spared on the 2nd (0.47, 0.25) |
| w_order_march_novice_1 | Harrok's duel, 6 deaths (iteration 0) | **completed**, 4 deaths (Harrok 4), 32.3 min | Harrok spared on the 5th (0.44, 0.38, 0.30, 0.34, 0.25) |
| w_conqueror_expert_1 | the den, watchdog (i2) | Harrok's duel, 7 deaths (an archer 1, Harrok 6) | the Matriarch slain in 1 attempt; Harrok 6 (0.53, 0.34, 0.07, 0.22, 0.18, 0.35): yielded, struck, not slain |
| w_conqueror_expert_2 | (i2: stopped in Harrok's duel) | the den, 7 deaths (the den 3, a troll 3, an ogre 1) | the Matriarch 4 (0.47, 0.48, 0.35, 0.49): not slain |
| w_conqueror_expert_3 | the den, watchdog (i2) | Harrok's duel, 8 deaths (the den 1, a soldier 1, a Stonehold troll 1, Harrok 5) | the Matriarch slain on the 2nd (0.87, 0); Harrok 6 (0.49-0.19): not slain |
| w_peaceful_expert_1-3 | the Raiders' Hollow, 6 deaths each (i2) | the Raiders' Hollow, 6 deaths each - the same runs to the tick as iteration 2 | - |
| w_mixed_expert_1 | Harrok's duel, watchdog (iteration 0) | **completed**, 1 death, 29.1 min | Harrok spared on the 2nd (0.45, 0.25) |
| w_mixed_expert_2 | Harrok's duel, watchdog (iteration 0) | **completed**, 1 death, 27.0 min | Harrok spared on the 2nd (0.28, 0.25) |
| w_mixed_expert_3 | Harrok's duel, watchdog (iteration 0) | **completed**, no death, 26.6 min | Harrok spared on the 1st (0.25) |

What iteration 3 did:

- **The den** (12 / 15 hp/s, the lure's clock fixed): the conqueror experts slew her in two of three runs
  (1 and 2 attempts; iteration 2: neither); the drive-out at stage 4 (`w_order_wood_novice_1`) took one
  attempt with no death in the den (iteration 0: six deaths, stopped). The conqueror novice on seed 2 still
  could not slay her (six attempts, down to 0.24; her frenzy 3 of its 6 den deaths), while seed 1 slew her
  in one attempt in iteration 2: one of two conqueror novices slays her.
- **The peaceful experts** replayed iteration 2's runs to the tick: the hold cap was never what killed them
  at the Raiders' Hollow (no hold lasted a second there). What does is still open - the expert's world
  rules (the arrows, the blows not answered) or its abilities; the M6 gate's Valley-tuned expert has no
  world equivalent yet. Reported for the confirmation phase.
- **Harrok** with the experts: the mixed experts, who spare him, all three completed with at most one
  death; the conqueror experts, who strike him when he yields and fight on, brought him to 0.07-0.25 and
  died five and six times. The slay path is the harder one by design (a duel to the death from the yield);
  no fourth iteration is allowed to tune it.
- **The Iron Regiment at stage 4** is unchanged: six attempts at 0.65-1.0 with five deaths to the fort's
  ballistae, no Charge (see "Left for the confirmation phase").

**Targeted checks on the final numbers** (`cee2edd`, `tools/run_bots.sh <run> --jobs=1 --tag=<tag> --extra=...`, the
iteration-0 groups of `targeted.sh`):

- **The Valley replays** (`force:expert:2 --timeout=1500 --autoplay=2400`, tag `p39_i3_valley`): iteration 0's
  run to the tick - 933.33 s simulated, 32 kills, 472 hits, the same flags hash (`58420dccc2cd`) and the
  same Deadfall watchdog. None of the three iterations acts in the Valley, so its matrix (iteration 0's,
  above) stands.
- **The siege of Skarn at stage 5** (`p39_i3_skarn5`, `w.peaceful:novice:1 --bot-skarn=5`): 6 deaths
  (riders' charges 2, catapult stones 2, a rival giant 1, a pike brace 1) and the siege not ended, as in
  iteration 0 (6 deaths: stones 3, bolts 2, a rider 1). Lighter shots moved its killers from the engines to
  its riders; the siege at stage 5 is Ulfra's plea, a choice (at stage 6 it took 60 s, no death).
- **The Iron Regiment at stage 5** (`p39_i3_ir5`, `w.peaceful:novice:1 --bot-oaths=march:help,crown:breach`):
  five attempts (0.73, 0.90, 0.60, 0.71, 0.71), the Charge begun in one of them (iteration 0: one engaged
  attempt at 0.84, no Charge), 6 deaths (ballistae 3, the shields' brace 2, a rider 1), the ballistae 74 %
  of the damage taken in the battle.

## M9 (P39): where the targets stand after three iterations

The latest run of each of the matrix's 18 slots (`python3 tools/bot_report.py <set> world_targets`): iteration
3's thirteen (the conqueror novice seed 2, the three orders, the nine experts, on `cee2edd`) and iteration
2's five novice runs it did not repeat (peaceful 1-2, conqueror 1, mixed 1-2, on `65293ad`: the same data but
the Matriarch's 15 / 25 regeneration, which only the conqueror slay meets - and seed 1 slew her in one
attempt on it). Iteration 0's value in brackets.

| Target (plan §6.4) | After iteration 3 | Met |
| --- | --- | --- |
| Completion, novice: at least 2 of 3 seeds per preset | peaceful 2 / 2, conqueror 1 / 2, mixed 2 / 2 (1 / 2, 0 / 2, 0 / 2) | peaceful and mixed met; conqueror **miss** (the den's slay on seed 2) |
| Completion, expert: 3 of 3, at most 2 deaths each | mixed 3 / 3 (deaths 1, 1, 0); conqueror 0 / 3; peaceful 0 / 3 (0 / 9) | mixed met; **miss** |
| Every first-oath order completes | march yes, wood yes, crown no (none) | **miss** (the Iron Regiment at stage 4) |
| Human estimate of the main path 75-140 min | 32.9 min, completed novice runs (41.0) | **miss** (the report's: the main path played straight) |
| Each §5.15 segment within its range | Opening 3.8, First oath 2.4, Second oath 8.6, Roaming 5.6, Stonehold 8.9 | **miss** (as above) |
| Deaths: 1-3 per boss attempt sequence (novice median) | Harrok 2 (runs 5 / 2 / 3 / 2 / 1; the orders 4 and 2) (6); the Matriarch 0 (runs 0 / 6 / 0 / 0) (3); the battle not won | Harrok met; the Matriarch under the range on three runs of four; the battle **miss** |
| Deaths: at most 2 in any other segment (novice) | max 1 (6) | met |
| Lone humans flee or rout >= 70 % of their engaged time | 3 %; melee 0 % of 280 s (3 %; 0 % of 256 s) | **miss** (left for the merged W23: below) |
| Formations hold or brace >= 50 % while the banner lives | 85 % (82 %) | met |
| Group or banner locks >= half with a formation engaged | 86 % (75 %) | met |
| At least 2 engines thrown per run that reaches stage 6 | 10 of 10 runs (7 of 7) | met |
| Off-camera share of the hits taken under 20 % | median 11 % (12 %) | met |
| Music in combat under 25 % among only lesser enemies | 45 % (38 %) | **miss** (P28's mix data: reported) |
| Every slotted ability used at least once a run | never used when ready, by runs of 18: Titan Stomp 10, Rampart Grip 9, Earthquake 8, Heavy Footfall 6, Boulder Hurl 5, Formation Sweep 4, Crag Hurl 3, Crushing Grip 2 (Boulder Hurl 14, Sweeping Blow 12, Crag Hurl 8, Titan Stomp 7, Crushing Grip 7) | **miss** |
| No ability over 40 % of ability damage | 90 % (Runic Bolt in a peaceful expert dead at stage 4); the novice's completed runs 31-51 % (65 %) | **miss** |
| Worst streaming work frame <= 12 ms | 63.5 ms (33.6 ms) | **miss** (two runs beside the other lane's checks on 4 CPUs) |
| Loaded margin >= 200 m, no thrash | 253 m, 0 | met |
| CPU per tick p95 <= 8 ms | median 10.22 ms (7.16 ms) | **miss** (as the work frame) |

The rows the report does not judge: the XP and equipment budget tests (margins of at least 50 XP) pass in
this branch's check (no XP was tuned); the Valley's items hold as iteration 0 measured them - no change of
the three iterations acts in the Valley (the data is the world's bosses, engines and the Matriarch, and every
bot change acts from stage 4 or in the world only), which the Valley's force:expert:2 replay below confirms.

### Left for the confirmation phase (and why no fourth iteration)

- **The Iron Regiment's Charge** (`tools/data/world/aldmere.json`, the battle arena's phase `below`: 0.6).
  The Wall's fall leaves the bar at 0.622 of the desktop aggregate (and about 0.67 of the web's 11,740),
  above the Charge's 0.6, and at stage 4 nothing the giant throws from the bailey harms the fort's
  ballistae or the wall's crews: every stage-4 attempt in four iterations stopped at 0.65-1.0, five or six
  deaths to the fort's ballistae. A lighter bolt (60) did not change it. The threshold is a layout number
  (a chunk rebuild) that this lane leaves to the merge with the other W23 lane's world rebuild: set it
  above both aggregates' post-Wall bars (desktop 0.622, web about 0.67, so about 0.70), rebuild the arena's
  chunk, and re-run `w.order_crown:novice:1` and `p39_ir4`.
- **The lone humans** (§6.4 at least 70 %): a lone soldier's awe costs 35 of its 70 morale, leaving it above
  its flee threshold of 25, so it fights a stage-4 giant to the end (melee lone humans fled 0 % in every
  iteration); the pooled share is the toll fort's tower archers', which hold the tower by design (M7b B3).
  The lever is `tactics.awe_morale_loss` (46 or more makes a lone soldier flee on sight at stage 4, as §5.14
  says), for the world's soldiers only - the Valley's stage-3 share is a separate item - measured on the
  merged W23, where the other lane changed the raiders' rout from a giant they do not see.
- **The peaceful experts at the Raiders' Hollow**: six deaths each in iterations 1-3 (iteration 0: two of
  three died at the toll fort before it). The expert's world rules (from stage 4: arrows hold no blow off,
  blows that cannot land are not answered; the rotation) let it past the toll fort but not the Hollow; a
  trace of `w.peaceful:expert:1` (`--bot-trace=60`) is the next step, a bot change for the confirmation
  phase.
- **The conqueror's slay** of the Matriarch (one novice of two) and of Harrok (no expert of three):
  the slay paths are the harder ones by design (the den without its third brazier; Harrok fought to the
  death after his yield). Every iteration has been used; the confirmation matrix measures them as they are.
- **Ability use**: Titan Stomp, Earthquake and Rampart Grip are never used when ready in 8-10 runs of 18:
  their windows come while the novice is mid-blow (the readiness is sampled every 6 ticks in combat, the
  bot looks once a second at a free tick). A bot question for the confirmation phase.
- **Music and streaming**: not §6.4 data levers (the music's intensity rules are P28's mix data; the work
  frame and the CPU per tick were measured with two runs beside the other lane's full checks).

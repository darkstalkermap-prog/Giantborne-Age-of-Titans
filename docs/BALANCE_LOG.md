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

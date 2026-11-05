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

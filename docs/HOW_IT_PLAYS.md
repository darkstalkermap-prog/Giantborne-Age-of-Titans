# How it plays

What the Valley slice plays like, measured by the Valley bot after P17b's balance loop (plan §5.7):
times, deaths, damage, where the bot struggled and therefore where a person probably will, how
growth changes the fights, stability and performance, what changed in tuning, what is still wrong,
and what a person should try first. **No human has played these builds for this report**; the
human playtests and the reference-PC numbers are listed as NOT RUN at the end.

## In short

- **The novice finishes.** The novice bot (the balance target: 250 ms reactions; it tries to parry
  half the blockable blows, blocks a quarter late and takes the rest; it misses 30 % of the dodgeable
  ones) completes 17 of 18 unassisted runs - every help_cache,
  help_ogre and intimidate seed, two of three force seeds - dying about once a run (median 1). The
  expert completes all four outcomes with 0-1 deaths. Before P17b's balance loop the novice finished
  2 of 18 and the expert 2 of 4.
- **The Ogre King is hard but fair - perhaps a little too fair for the bot.** The novice usually wins
  its first attempt, ending the fight with a median 18 % of its health; two runs of 18 needed
  retries. The plan expects one retry from a first-time player, and a person plays less evenly than
  the bot.
- **Where it gets hard**: the ruins' courtyard (half of all deaths: a soldier formation that braces,
  a terrace archer out of reach, a mage), then the forest at stage 1 (wolves, the forest ogre's
  smash). These are where a person should be watched first.
- **It is short for the bot**: about 15 minutes of human estimate (10 of simulated time) against
  the plan's 20-30. The estimate counts no exploration or learning, so the Hollow, the forest and the
  Grove are floors; a timed human run is the real measure.
- **Growth changes the fights**: stage-1 soldiers trade blows at the giant's legs; at stage 2 they
  hold formation 58 % of the time and die in half the time; at stage 3 they break and flee (55 % in
  the median run); the giant's blows reach 3.5 / 5 / 6.5 m.
- **Stable and within the CPU budget**: the 30-minute run passed (three outcomes back to back, no error, breach or invariant failure, no node growth); the simulation's CPU per tick stays at p95
  5.3-6.4 ms in every run (budget 8 ms) with at most 12 active enemies. The Valley's static world is
  within the draw-call budget; views with five or more enemies are not.
- **Readability**: about a fifth to a quarter of the hits the novice takes come from attackers off
  camera (mostly arrows from behind; target under 20 %); none from a telegraph shorter than 0.45 s.

## How these numbers were made

Every number in this report comes from a headless run of the game itself in the development
container (Godot 4.6.3, `--fixed-fps 60`, a debug build, 4 shared CPU cores, no GPU), driven by the
Valley bot of P17a (`scripts/debug/valley_bot.gd`, `bot_combat.gd`), unless a section names
another source.

- **The bot** plays the whole quest line from New Game through the input router and the camera, as
  a player's inputs would, under a village policy (`help_cache`, `help_ogre`, `intimidate`,
  `force`). Two skill profiles (plan §5.1, decision 30):
  - *novice* (the balance target): sees only telegraphs aimed at it and the windups of enemies on
    screen within 8 m, decides 250 ms later; a blockable blow is parried half the time (with timing
    noise), else blocked late half the time, else taken; a dodgeable blow (unblockable, a dash or
    charge, an area slam, a shot) is dodged 70 % of the time, a tenth of those the wrong way;
    abilities at most once a second. It spends its stamina freely.
  - *expert* (the skill ceiling): reads every enemy's controller phase, parries 6-10 ticks before
    the blow, always dodges dodgeable blows, keeps a dodge's stamina in reserve.
  - Both fight every aware hostile within 16 / 22 / 28 m (by stage), stand at 0.8 x the stage's
    reach, use a heavy on a guarding or staggered target, grab staggered ones and throw them at
    another enemy, and use abilities by plan §5.1's rules. They rest at a shrine below 45 % health
    when one is within 70 m. They do not explore: they go straight to the next objective. Since P17b
    they also walk on from an encounter whose last members are out of reach (after 8 s) and give up
    a fight that takes no health off its target for 20 s (leaving that enemy alone for 90 s).
- **The human estimate** (P17a, plan §5.1): the bot's simulated seconds, plus 4 s per dialogue node
  shown, the dialogue and tutorial text at 15 characters per second, 8 s per screen a player would
  open (shrine, forge, dialogue, inventory, end) and 10 s per district entered for the first time. It
  does not count what a first-time player spends exploring, reading the HUD, looking for the way or
  learning the controls, so for the Hollow, the forest and the Grove it is a floor, not a forecast.
- **The balance matrix** (plan §5.6; `tools/run_bots.sh --preset=balance --tag=<batch>`, three runs at
  a time, 900 s wall-clock limit each): novice x {help_cache, help_ogre, intimidate} x seeds 1-5,
  novice x force x seeds 1-3, expert x the four policies x seed 1 - 22 unassisted runs. A run stops
  on a watchdog breach (240 s on one main-quest stage, 480 s on the boss, more than 5 deaths on one
  stage) and counts as not completed. Results: `user://bot_runs/<batch>/<run>.json` (the full
  `AUTOPILOT_RESULT`), `.log` and `.exit`. Every table below comes from
  `python3 tools/bot_report.py user://bot_runs/<batch> <section>` (in a worktree `user://` is
  `.userdata/godot/app_userdata/Giantborn- Age of Titans/`); medians of times are over the completed
  runs, deaths and completion over all runs. Damage as a share of maximum health is an estimate
  (the maximum health at the segment's end, rebuilt from the run's level and stage).
- The final batch is `final` (the build at commit `25c1fb7`; the game's code and data are those of `322de67`, the commits after it changed only the bot, the tools and the docs). The earlier batches (`base`,
  `fix`, `iter1`, `iter2`) are in `docs/BALANCE_LOG.md`.

## The runs

### Per policy and skill

| Skill | Policy | Completed | Human est. median (min) | Raw median (min) | Deaths median (boss) | Max deaths in another segment (median) |
| --- | --- | --- | --- | --- | --- | --- |
| novice | force | 2 / 3 | 16.6 | 12.7 | 2 (0) | 1 |
| novice | help_cache | 5 / 5 | 16.5 | 11.0 | 1 (0) | 1 |
| novice | help_ogre | 5 / 5 | 15.6 | 10.3 | 1 (0) | 1 |
| novice | intimidate | 5 / 5 | 12.9 | 8.7 | 0 (0) | 0 |
| expert | force | 1 / 1 | 20.3 | 16.6 | 1 (0) | 1 |
| expert | help_cache | 1 / 1 | 18.3 | 13.2 | 0 (0) | 0 |
| expert | help_ogre | 1 / 1 | 18.1 | 13.4 | 0 (0) | 0 |
| expert | intimidate | 1 / 1 | 18.0 | 13.7 | 1 (0) | 1 |

### Every run

Segment columns: the human estimate in minutes per §4.9 segment; "Level" is the level at the end.

| Run | Done | Raw (min) | Human est. (min) | Deaths (boss) | Level | Hollow | Forest | Grove | Village | Ruins | Boss | Return | Stopped at |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| force_expert_1 | yes | 16.6 | 20.3 | 1 (0) | 7 | 1.5 | 3.7 | 0.9 | 2.2 | 4.8 | 1.7 | 5.5 |  |
| force_novice_1 | yes | 14.0 | 17.8 | 2 (0) | 7 | 1.5 | 1.7 | 0.7 | 1.6 | 5.9 | 1.3 | 5.1 |  |
| force_novice_2 | yes | 11.5 | 15.4 | 1 (0) | 7 | 1.5 | 2.6 | 0.8 | 1.1 | 4.2 | 1.3 | 3.7 |  |
| force_novice_3 | no | 13.5 | 17.3 | 3 (1) | 7 | 1.6 | 2.8 | 0.6 | 1.0 | 3.9 | 2.5 | 4.8 | deadfall (timeout) |
| help_cache_expert_1 | yes | 13.2 | 18.3 | 0 (0) | 7 | 1.5 | 3.7 | 0.9 | 4.6 | 3.4 | 1.7 | 2.6 |  |
| help_cache_novice_1 | yes | 9.0 | 13.9 | 0 (0) | 7 | 1.5 | 1.7 | 0.7 | 3.8 | 2.3 | 1.1 | 2.8 |  |
| help_cache_novice_2 | yes | 11.1 | 16.6 | 1 (0) | 7 | 1.5 | 2.6 | 0.8 | 3.2 | 4.7 | 1.2 | 2.6 |  |
| help_cache_novice_3 | yes | 9.8 | 15.0 | 0 (0) | 7 | 1.6 | 2.8 | 0.6 | 3.1 | 2.9 | 1.6 | 2.4 |  |
| help_cache_novice_4 | yes | 13.0 | 18.5 | 2 (0) | 7 | 1.8 | 2.7 | 0.8 | 3.4 | 5.8 | 1.4 | 2.6 |  |
| help_cache_novice_5 | yes | 11.0 | 16.5 | 1 (0) | 7 | 1.8 | 4.0 | 0.6 | 3.6 | 2.5 | 1.4 | 2.5 |  |
| help_ogre_expert_1 | yes | 13.4 | 18.1 | 0 (0) | 7 | 1.5 | 3.7 | 0.9 | 4.1 | 3.0 | 1.8 | 3.1 |  |
| help_ogre_novice_1 | yes | 11.9 | 17.2 | 2 (0) | 8 | 1.5 | 1.7 | 0.7 | 2.8 | 5.5 | 1.5 | 3.5 |  |
| help_ogre_novice_2 | yes | 10.3 | 15.6 | 1 (0) | 7 | 1.5 | 2.6 | 0.8 | 2.6 | 4.0 | 1.4 | 2.6 |  |
| help_ogre_novice_3 | yes | 8.9 | 14.0 | 0 (0) | 8 | 1.6 | 2.8 | 0.6 | 2.5 | 2.6 | 1.2 | 2.6 |  |
| help_ogre_novice_4 | yes | 9.1 | 14.1 | 0 (0) | 8 | 1.8 | 2.7 | 0.8 | 2.5 | 2.3 | 1.4 | 2.6 |  |
| help_ogre_novice_5 | yes | 10.6 | 16.1 | 2 (0) | 7 | 1.8 | 5.0 | 0.6 | 2.7 | 2.2 | 1.3 | 2.5 |  |
| intimidate_expert_1 | yes | 13.7 | 18.0 | 1 (0) | 7 | 1.5 | 3.7 | 0.9 | 2.4 | 3.1 | 1.7 | 4.8 |  |
| intimidate_novice_1 | yes | 8.6 | 12.7 | 0 (0) | 7 | 1.5 | 1.7 | 0.7 | 1.5 | 2.0 | 1.3 | 4.1 |  |
| intimidate_novice_2 | yes | 8.7 | 12.9 | 0 (0) | 7 | 1.5 | 2.6 | 0.8 | 1.3 | 2.6 | 1.3 | 2.8 |  |
| intimidate_novice_3 | yes | 7.9 | 12.2 | 0 (0) | 7 | 1.6 | 2.8 | 0.6 | 1.1 | 2.2 | 1.2 | 2.6 |  |
| intimidate_novice_4 | yes | 9.7 | 13.9 | 0 (0) | 7 | 1.8 | 2.7 | 0.8 | 1.2 | 2.5 | 1.3 | 3.6 |  |
| intimidate_novice_5 | yes | 12.3 | 17.5 | 4 (2) | 7 | 1.8 | 4.9 | 0.6 | 1.2 | 2.6 | 3.5 | 2.9 |  |

### The segments against the plan's pacing (§4.9)

| Segment | Target (range), min | Novice human est. median, min | Raw median, min | Damage / max health, median (estimate) | Deaths (all novice runs) |
| --- | --- | --- | --- | --- | --- |
| Hollow | 3.0 (2-4) | 1.6 | 0.6 | 0.05 | 0 |
| Forest | 5.5 (4-7) | 2.7 | 2.1 | 1.39 | 5 |
| Grove | 2.0 (1.5-2.5) | 0.7 | 0.2 | 0.00 | 0 |
| Village | 4.0 (1.5-7) | 2.5 | 1.4 | 0.47 | 0 |
| Ruins | 4.0 (3-5) | 2.6 | 2.3 | 1.14 | 10 |
| Boss | 4.0 (2.5-6) | 1.3 | 0.9 | 0.93 | 3 |
| Return | 3.5 (2.5-4.5) | 2.6 | 1.9 | 0.30 | 1 |

The bot plays the slice in about 10 minutes of simulated time and 15 minutes of human
estimate (median of the completed novice runs), against the plan's 20-30. Every segment but the
village is under its range, and the shortfall is where a first-time player spends time the estimate
does not count: the Hollow's tutorial (1.6 against 3.0), the forest (2.7 against 5.5: a person
learning to guard, parry and grab will take longer than a bot that already knows), the Grove (0.7
against 2.0: the growth, the first boulder, the view). The boss segment is short because the novice
wins the first attempt (below); the plan expected one retry. Raw time spread: help_cache and
help_ogre 9-13 minutes, intimidate 8-12 (no quarry detour), force 11-14 (the hostile village on the
way back).

## Novice versus expert

| Measure (median per run) | Novice | Expert |
| --- | --- | --- |
| Completed | 17 / 18 | 4 / 4 |
| Deaths | 1 | 0.5 |
| Human estimate (min, completed runs) | 15.4 | 18.2 |
| Raw simulated time (min, completed runs) | 10.3 | 13.6 |
| Damage taken | 3,267 | 2,563 |
| Parries / blocks / dodges | 5 / 31 / 5 | 95 / 129 / 46 |
| Light attacks / heavies / throws | 152 / 9 / 10 | 134 / 5 / 22 |
| Ogre King time-to-kill (s) | 37 | 62 |
| Lowest health during the King's fight (share of maximum) | 0.18 | 0.57 |
| Soldier time-to-kill, stage 1 / stage 2 (s) | 25 / 13 | 26 / 30 |
| Hits from attackers off camera (share of the hits taken) | 0.22 | 0.34 |

Skill shows in defence, not speed: the expert parries about twenty times as often, dodges nine times
as often, takes about a fifth less damage and dies at most once; but it spends its stamina on
guarding and keeps a dodge in reserve, so its fights last longer (a stage-2 soldier takes it 30 s,
the novice 13) and its runs are about three minutes slower. Its larger off-camera share is the same
habit: it stands its ground and takes the arrows from behind while it parries what is in front.
Where skill matters most: the forest's two hunters at the giant's legs (P17b's iteration 1 had every expert die there until the soldiers'
pause between strikes was lengthened), the courtyard (the expert's deaths are an arrow and a brace),
the Ogre King (the novice wins with a median 18 % of its health left; the expert with
57 %, but taking 62 s to the novice's 37).

## Deaths, readability and getting stuck

novice deaths (19): soldier/soldier_brace 6, archer/archer_shot 4, wolf/wolf_lunge 3, ogre/ogre_smash 2, boss/boss_slam 2, boss/boss_combo_2 1, mage/mage_slow_bolt 1

expert deaths (2): soldier/soldier_brace 1, archer/archer_shot 1

novice deaths by segment: Ruins 10, Forest 5, Boss 3, Return 1

- **The ruins' courtyard is where the novice dies** (10 of 19 deaths in the final batch): three
  soldiers holding formation and bracing a giant that steps into their spears, the sergeant, a mage
  slowing and shielding, and an archer on the west terrace out of melee reach - with the practice
  gate's garrison, eight enemies.
- **The forest** (5): the wolves and the forest ogre's smash, at stage 1 with no healing, in three
  runs, all seed 5 (the policies part at the village, so a seed's forest is the same in each).
- **The Ogre King** (3, in two runs): the plan expects about one retry; the novice usually wins the
  first attempt.
- One arrow on the way back (the force branch's hostile village). No deaths in the Hollow, the Grove
  or the village.

**Readability.** Hits from attackers that were off camera at their windup are about a fifth to a
quarter of the hits the novice takes (median 0.24 over the novice runs, 0.27 with the experts, at
most 0.39 in one run; the plan's target is under 20 %); none landed within 0.45 s of its telegraph. The off-camera
hits are mostly arrows and bolts from behind the giant: the novice reacts only to what is on screen
within 8 m or telegraphed at it, so this is also how often a person who does not watch the threat
arrows will be hit from behind.

**Stuck events** (the bot's stuck detection: no progress toward the objective for 6 s; 20 m cells):

| Cell centre (x, z) | Stuck events | Objectives | Recovered by |
| --- | --- | --- | --- |
| (-110, 170) | 13 | leave_hollow 13 | sidestep_jump 10, replan 3 |
| (170, -90) | 7 | courtyard 4, causeway 3 | sidestep_jump 7 |
| (-10, -50) | 5 | deadfall 5 | sidestep_jump 4, replan 1 |
| (30, -90) | 4 | to_village 4 | sidestep_jump 4 |
| (110, -30) | 1 | deadfall 1 | sidestep_jump 1 |
| (10, -50) | 1 | deadfall 1 | sidestep_jump 1 |
| (-50, -170) | 1 | crown 1 | sidestep_jump 1 |

Every one was recovered (a sidestep and jump, a replan or retracing the breadcrumbs) and no run
teleported. The Hollow cell is the training ground (the dummies and the sparring post crowd the
path north); (30, -90) is the signposted junction on the way into Thornwick; (170, -90) the ruins'
armory, where the sword rack and the crate stand against the wall; (-10, -50) is the road patrol's
line west of the village, where the stage-3 giant fights its way back on the force branch.

## Growth: does the giant's size change the fights?

| Measure | Target | Median (novice) | Range |
| --- | --- | --- | --- |
| Soldiers in HOLD, stage 1 (share of engaged time) | 0 | 0.00 | 0.00-0.00 |
| Soldiers in HOLD, stage 2 | >= 0.5 | 0.58 | 0.47-0.68 |
| Soldiers in FLEE or ROUTED, stage 3 | >= 0.5 | 0.55 | 0.00-0.67 |
| Soldier time-to-kill, stage 2 / stage 1 | <= 0.6 | 0.54 | 0.27-1.11 |
| Soldier time-to-kill, stage 1 / stage 2 (s) | - | 24.8 / 11.8 | - |

Share of engaged time in each AI state, pooled over the novice runs, and the median time-to-kill:

| Stage | Archetype | Engaged (s, all runs) | Approach | Attack | Recover | Staggered | Hold | Reposition | Flee | Routed | Time-to-kill median (s) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | ogre | 630 | 20 % | 55 % | 15 % | 6 % | - | - | - | - | 21.6 |
| 1 | soldier | 1295 | 33 % | 27 % | 25 % | 13 % | - | - | - | - | 24.8 |
| 1 | wolf | 788 | 53 % | 21 % | 7 % | 4 % | - | 9 % | - | - | 1.4 |
| 2 | archer | 2781 | 31 % | 35 % | 19 % | 2 % | - | - | 11 % | - | 3.4 |
| 2 | boss | 868 | 19 % | 61 % | 13 % | 7 % | - | - | - | - | 37.7 |
| 2 | mage | 1588 | 34 % | 29 % | 16 % | 6 % | - | - | 13 % | - | 6.9 |
| 2 | ogre | 122 | 15 % | 57 % | 16 % | 9 % | - | - | - | - | 20.1 |
| 2 | soldier | 7016 | 1 % | 14 % | 10 % | 6 % | 58 % | - | 5 % | - | 11.8 |
| 2 | wolf | 234 | 27 % | 24 % | - | - | - | 16 % | 32 % | - | 2.6 |
| 3 | archer | 978 | 38 % | 25 % | 14 % | 3 % | - | - | 16 % | - | 2.6 |
| 3 | mage | 257 | 36 % | 25 % | 10 % | 17 % | - | - | 9 % | - | 3.9 |
| 3 | ogre | 451 | 21 % | 44 % | 16 % | 10 % | - | 7 % | - | - | 14.5 |
| 3 | soldier | 3413 | 1 % | 6 % | 4 % | 2 % | 50 % | - | 31 % | - | 9.6 |
| 3 | wolf | 1704 | 31 % | 8 % | - | - | - | 4 % | 56 % | - | 2.5 |

- **Stage 1**: soldiers advance to the giant's legs and fight (no HOLD); the forest ogre attacks
  more than half the time; a soldier takes about 25 s to kill (guard up, two at a time).
- **Stage 2**: soldiers are outmatched (3.05 x their height) and spend about 60 % of their engaged
  time holding formation, bracing a giant that steps into their spears; archers and mages keep their
  distance and spread; a soldier dies in about 12 s (half the stage-1 time).
- **Stage 3**: awe (4.4 x their height) - soldiers drop to 35 morale on sight and break after one
  loss or one Roar: in the median run they spend over half their engaged time fleeing (pooled over
  all runs about a third: the force branch's hostile village holds its formation longer); wolves
  harass and flee about half the time. The same soldier plays three different fights at the three
  sizes.

## Abilities

| Ability | Runs using it (novice) | Median uses |
| --- | --- | --- |
| heavy_footfall | 17 / 17 | 3 |
| sweeping_blow | 7 / 17 | 0 |
| stone_skin | 17 / 17 | 1 |
| crushing_grip | 17 / 17 | 2 |
| boulder_hurl | 17 / 17 | 2 |
| runic_bolt | 17 / 17 | 8 |
| ancestral_mend | 17 / 17 | 7 |
| thunder_roar | 17 / 17 | 3 |
| titan_surge | 14 / 17 | 1 |

Largest single-ability share of ability damage per run: heavy_footfall 0.40, runic_bolt 0.37, boulder_hurl 0.31, runic_bolt 0.30, heavy_footfall 0.34, boulder_hurl 0.33, runic_bolt 0.35, boulder_hurl 0.35, runic_bolt 0.28, heavy_footfall 0.34, boulder_hurl 0.31, heavy_footfall 0.26, heavy_footfall 0.34, runic_bolt 0.29, heavy_footfall 0.45, heavy_footfall 0.30, heavy_footfall 0.31

Every ability is used in most runs except Sweeping Blow, which the bot reaches only when Heavy
Footfall is on cooldown (its rules try Footfall first for a crowd); the largest single share of
ability damage per run is Heavy Footfall, Boulder Hurl or Runic Bolt at 26-45 %. Ancestral Mend is
the most used (about 7 times a run): the novice heals through its fights.

## The 30-minute stability run

`tools/run_bots.sh --preset=stability` (`--bot-loop --bot-assist`: the novice taking a quarter of
the damage, help_cache first, `--autoplay=1800`; tag `stability`, on the final build): **passed**,
exit 0. 1,800 s simulated in 622 s of wall time; three slices completed in a row (help_cache 520 s,
help_ogre 514 s, intimidate 491 s, each with its outcome and no death), the fourth (force) started;
4 level loads; 0 errors, 0 warnings, 0 breaches, 0 invariant failures, 0 duplicated rewards, 0
teleports; 3 stuck events in the completed slices, all recovered. Node count 5 s after each load:
1,404 every time (no growth); every 60 s: 1,411-2,110 as encounters spawn and despawn; static memory
110-135 MB (part of it the run's own per-tick samples). CPU per tick over the whole run: p50 3.1 ms,
p95 5.8 ms, p99 7.7 ms, max 68 ms (a level load); at most 12 active enemies.

## Performance

- **Simulation CPU per tick** (budget p95 <= 8 ms): in the final balance matrix the p95 of every
  run is at most 6.37 ms (median 5.30 ms), three runs at a time on 4 shared cores; the
  stress route (300 s, `low`, headless): CPU per tick p50 2.27 ms, p95 3.72 ms, p99 5.12 ms, max 32.1 ms (P14 measured 2.81 / 4.88 / 6.91 / 26.5); 12 active combatants (mean 11.8), up to 40 debris pieces, 138 breakables broken, 0 errors.
- **Active enemies**: at most 12 at once in every run, and at most 12 hostiles within 40 m of the
  giant (the force branch's return leg had 16 before P17b).
- **Draw calls** (`docs/PERFORMANCE.md`, "Draw calls after P17b"): the Valley's static world draws at
  most 93 calls per view at `low` and 221 at `medium` (was 402 / 584). Views with five or more enemies
  in full rig still pass the 250 budget (about 33 calls each); the Valley walk at `low`: p50 256,
  largest view 656 (was 608 / 1,354). Frame and GPU times need a real GPU: NOT RUN.

## What changed in tuning, and why

Every change, its reason and the matrix before and after are in `docs/BALANCE_LOG.md`. In short:

| What | Before -> after | Why |
| --- | --- | --- |
| The swing's vertical aim (game code) | fixed tilt -> aims at the lock or soft target | Blows landed short of the stage's reach; now 3.5 / 5 / 6.5 m |
| The director's budget (game code) | -> a hostile faction's members count | The force branch's 16 hostiles (FOLLOWUPS) |
| The Ogre King's slam | 126 damage, 1.3 s windup, 1.4 s recovery -> 101, 1.5 s, 1.8 s | 42 novice deaths in the baseline; a longer read and punish window |
| The King's combo | 76 / 92 -> 67 / 77 | 47 deaths in the baseline |
| The King's pause between attacks | 0.3-0.6 -> 0.6-1.0 s | Back-to-back attacks left no time to recover |
| The brace counter | 35 -> 28 | The courtyard's formation |
| The archer's shot | 25 -> 21 | The courtyard's terrace archer |
| The ogre's smash | 58 -> 46 (stage 1) | The forest ogre |
| Soldiers' pause between strikes | 0.8-1.4 -> 1.2-1.8 s | Two stage-1 soldiers at the giant's legs |
| The bot (measurement) | see `docs/BALANCE_LOG.md` | Stamina for the dodge, heavies, standoff, walking on, giving up a chase |

Kept at the spec's numbers: the King's 1,500 health and 150 poise (more health turned the bot's boss
fight into six losses in a row for the weaker builds), every player number (spec §7-§9), the windup
floors (§10).

## Observations

- **Where the novice struggled, and where people probably will.** The courtyard (a formation,
  a terrace archer and a mage at once), the forest at stage 1 (the first time the guard, the parry
  and the dodge all matter, with no healing), and the Ogre King's slam and combo. These are also the
  three places the design asks the most of a player, so they are the right places to be hard; a human
  playtest should check that they read as fair.
- **The boss is a race.** The bot wins or loses on consistency: at 1,500 health the novice wins its
  first attempt with a few to a few dozen per cent of its health left; with 20 % more health the
  plain sword of the intimidate path loses every attempt (replays in `docs/BALANCE_LOG.md`). A person
  plays less evenly, so the plan's "typically one retry" is plausible for people even though the bot
  rarely needs one.
- **Abilities.** Heavy Footfall, Boulder Hurl and Runic Bolt carry the ability damage (none above
  45 % in a run); Ancestral Mend is the most used. Sweeping Blow is the one ability the bot leaves on
  the bar.
- **Growth feels different by the numbers.** The same soldiers advance and trade blows at stage 1,
  hold formation and brace at stage 2, and break and flee at stage 3; a soldier dies in half the time
  at stage 2; the giant's blows reach 3.5, 5 and 6.5 m. Whether it *feels* different needs a person.
- **Village outcomes differ.** intimidate is the quickest path (no quarry detour) and force the
  longest (the village's guards and militia turn on the giant on the way back); help_cache and
  help_ogre reach the King at level 5-6 with a reforged club (the help's two iron ingots), intimidate
  and force at level 5 without one - and still win.

## Known issues

- **Pacing is short for the bot** (15-16 minutes of human estimate against 20-30); the estimate is a
  floor for the Hollow, the forest and the Grove. Only a timed human run can say how short.
- **The novice rarely needs a retry at the Ogre King** (target 1-2 deaths there): see above.
- **Segment damage** is above the plan's 0.6 x maximum health in the forest and the ruins (about
  1.4 and 1.1): the novice model takes many blows whole in long fights; deaths stay at about one a
  run.
- **Off-camera hits** are about a fifth to a quarter of the hits taken (target under 20 %): archers
  and mages behind the giant.
- **The force branch's return leg** is the slice's longest fight: one of the three force runs ran
  out of the 240 s the bot's watchdog allows its Deadfall stage, fighting the village's guards, the
  militia and the return patrol on the road west (the stage-3 soldiers hold formation there instead
  of breaking). A person is not timed out; they will find it a long fight.
- **The village yard's navmesh pocket** (x 62-72, z -50 to -35; P17a) is not fixed: the bot gets out
  through its breadcrumbs, a person might have to back out.
- **Draw calls with many enemies in view** exceed 250 (FOLLOWUPS row for P18 or later).
- **The expert runs share seed 1**, so their four runs share one tutorial and one forest: the
  expert is one sample up to the village.

## What to try first

Run the game from the editor (F5) or `godot --path .`, choose **New Game**. Debug builds have F3
(the debug panel: state, stage, stamina, target, AI state), F6 / F7 (grow / shrink one stage on the
spot, outside progression), F8 (XP) and F9 (reload the last checkpoint).

**The 5-minute tour: does the combat feel right?**

1. The Hollow (1-2 min): V switches the camera; the three dummies take the light chain (left
   mouse / RB), a heavy (Shift + left mouse / RT) and Heavy Footfall (1 / LT + A); the sparring
   post's swing is the block (right mouse / LB; a tap just before the hit is a parry) and the dodge
   (Space / B) lesson.
2. North to the first wolf pack (1 min): three wolves flank and lunge with a clear windup - dodge,
   then punish.
3. The forest hunters (1-2 min): two soldiers that guard their front (frontal blows mostly blocked).
   Break the guard with a heavy or step round it; parry a strike to stagger one; grab a staggered
   soldier (E / X) and throw it (light) at the other.
4. Press F6 once (stage 2) and meet what is left of the hunters or the road patrol: soldiers hold
   formation and brace; strike from the edge of your reach (about 5 m). F6 again (stage 3): they
   break and flee (awe) and the camera pulls back to 12 m. F7 brings the giant back down.

**The 25-minute tour: the whole slice as a first-time player would play it** (the bot's novice
needs about 15 minutes by the human estimate, 10 of simulated time; a person should expect more).
Play New Game to the crown without the debug keys. Choose at the elder:
- *help* (bring back the cache the quarry raiders stole, or drive the ogre out of the fields) for
  the intended path: both pay 120 XP, two iron ingots for the forge and Ancestral Mend;
- *force* (smash the barricade) for the hardest return leg: the village's guards and its militia
  turn on the giant on the way back.

Things to watch, from where the bot struggled (above): the forest ogre's smash at stage 1 (the
first fight whose punish window matters); the ruins' courtyard (soldiers in formation brace a giant
that steps into their spears; the archer on the west terrace is out of melee reach - throw a boulder
or cast Runic Bolt); the Ogre King's slam (circle telegraph, unblockable: dodge out, then punish the
1.8 s recovery) and, below half health, his charge (bait it into a pillar or the wall for a long
recovery).

## What a human playtest should look for

- **Readability.** About a fifth to a quarter of the hits the novice took came from attackers off
  camera at their windup (mostly archers and the mage behind the giant). Do players notice the
  threat arrows? Do they know which blows to block and which to dodge (the King's slam and charge
  cannot be blocked)?
- **The courtyard.** The densest fight of the slice (eight enemies with the gate's garrison, the
  terrace archer out of reach). Do players find the boulder and the bolt for the archer, the heavy
  for a guard, the edge of reach against the brace?
- **The boss.** Is one retry the norm (the design's intent), is the slam fair, does the charge read?
- **Growth.** Do players feel stage 2 (reach, the outmatched soldiers' formations) and stage 3
  (awe: the return patrol scatters) as a change of tactics, not only of numbers?
- **Pacing.** The bot's human estimate is a floor for the Hollow, the forest and the Grove; time a
  real first run per segment (the tracker's stage names are the segments of plan §4.9).
- **Getting lost.** The bot never explores. Where do players leave the road (the Grove, the quarry
  detour, the ruins' armory)?
- The usability script (`docs/USABILITY_SCRIPT.md`) has the observation sheets.

## NOT RUN (human or reference-hardware gates)

| Gate | How to run it |
| --- | --- |
| Usability sessions with 3 new players (spec §16) | `docs/USABILITY_SCRIPT.md`, §2-§5: an export or the editor's run, fresh saves, the observation sheet per player |
| Real-controller checklist | `docs/USABILITY_SCRIPT.md` §6, with an XInput pad |
| Frame time p95 <= 16.7 ms / p99 < 33.3 ms at 1080p `low`, GPU time | `docs/PERFORMANCE.md`, "Commands": the exported build on the reference PC, the stress route and the Valley walk, with and without `--disable-vsync` |
| Draw calls on a real GPU | The same runs print `draw_calls` in `PERF_RESULT` |
| Web build in a real browser (load time, `.pck` size, save persistence) | P18; `docs/PERFORMANCE.md`, "Web build checklist" |
| A human's time for the slice | Any playtest above: time each segment against plan §4.9 |


# How it plays

What the campaign plays like - the Valley of Broken Kings as its prologue and the open world after it - measured
by the game's own bots on the merged M9 code (plan M6-M9 §6.5): runs per preset, oath order and skill, the time of each
segment against the plan's pacing, deaths by region, boss and cause, how growth changes the fights at stages 4-6,
discoveries and fast travel, the music, streaming, performance and stability, what changed in tuning, what is
still wrong, and what a person should try first. **No human has played these builds for this report**: the human
playtests, a timed human run, the listening pass and the reference-PC and real-browser numbers are listed as NOT
RUN at the end.

Every number below comes from a named run (its batch tag is given) of the W23 confirmation phase, on the merged code:
lane P39's balance pass with lane P39f's fixes and rebuilt world, and the Iron Regiment's phase thresholds fixed first
("What changed in tuning"). Lane P39's own runs on its branch before the merge, and how the two compare, are in
`docs/BALANCE_LOG.md` ("M9 (P39)" and "M9 confirmation").

**The M9 gate (lane aldmere)** then fixed three things on the crown's way and measured the crown order again (not the
matrix): Fort Aldmere's gate garrison stood in the gateway's mouth on every titan path into the bailey (it now stands
beside the road's approach), the war camp's shield wall stood across the King's Road (it now stands beside it), and
the Iron Regiment's gate-bastion ballistae shot from the Wall's first blow where plan §5.13 has two ballistae in the
Wall and all four from the Charge (they now hold their fire until the Charge, and the battle tells the giant which
ballistae shoot). The lines these change say so;
`docs/BALANCE_LOG.md`, "M9 gate (lane aldmere)", has the runs.

## In short

- **The campaign is completable, and the novice finishes most of it.** Of the matrix's 21 unassisted runs (the
  novice and the expert on seeds 1-3 of the three policy presets, and each oath first), 12 reach the Stone Throne:
  the three peaceful novices, two mixed novices of three, the three mixed experts, two peaceful experts of three, and
  the march-first and wood-first orders. The three stability runs pass (below).
- **Where it stops**: the conqueror's slay of the Troll Matriarch (no novice of three - six attempts each, down to 9-14
  % of her health, a narrow miss - and no expert of three, whose brazier lure no longer pays in the den now that it is
  a clearing); the crown taken first (the Iron Regiment at stage 4: its phases now follow the Wall and the Charge, but
  the fort's ballistae kill the novice before the Charge; two crown runs of three stopped against the gate garrison in
  Fort Aldmere's gateway); Harrok's duel stopped one mixed novice, the toll fort's tower archers one peaceful expert.
  Assisted (P38's acceptance orders), the march-first and wood-first orders complete with no death; the crown-first
  reaches the battle's Last Stand twice - its phases follow now - but dies in it and runs out the oath's time. Since the
  M9 gate the gateway is clear and the crown-first order completes assisted too, with no death; unassisted, the novice
  still loses the battle at stage 4 - after each death it breaks the gate again under the garrison's arrows and bolts
  and enters the bailey with a quarter of its health or less ("Known issues").
- **The bosses**: the novice wins Harrok's duel with a median of 2.5 deaths (it was 6 before P39's balance pass), the
  Matriarch is driven out in one attempt with no death in the den, at stage 4 or 5, and the mixed experts spare Harrok
  with one to three deaths.
- **It is short when played straight**: about 41 minutes of human estimate for the main path after the Valley
  (the plan's target 75-140): the bot walks from objective to objective, opens no sealed place, reads no cairn and
  takes no side quest. The first oath's segment is now in its range (12 minutes: the bot fights the Raiders' Hollow
  on the King's Road, below).
- **Growth shows**: formations hold or brace 79 % of their engaged time while their banner lives, 89 % of the giant's
  locks with a formation engaged are group or banner locks, and 13 of the 14 runs that reach stage 6 throw 4 engines
  (one walked past the Moot battery out of the bot's reach and never came back). Lone soldiers do not flee a stage-4
  giant yet (4 % of the lone humans' engaged time against the target's 70 %: a known issue).
- **Stable**: the 60-minute world run (two campaigns back to back), the 30-minute Valley run and the campaign's
  hand-over from the Valley all passed: no crash, no blocked world, no duplicated reward, no invariant failure, no
  error or warning in the runs' own counts (Godot's exit report of leaked resources follows a campaign's result:
  below), node counts within 0.6 %.
- **CPU per tick** (the container, indicative; budget p95 8 ms): the world walk through every region at stage 6 runs
  at 5.89 ms, the 40-member formation stress with two siege engines at 4.39 ms and the unreachable chase at 3.32 ms;
  the campaign runs (three at a time) at 6.4-10.6 ms a run, by region the median run's 7.5 ms in the Crownmarch, 6.0 in
  the Greywood and 7.7 in the Stonehold, and 9.8 ms in the Aldmere March, where the war camp's sabotage reads 11.2-12.5
  ms. The worst streaming work frame is a props part's text parse (12.2 ms on the walk headless; exports ship binary
  scenes).
- **Readability**: about one hit in six that the giant takes in the world comes from an attacker off camera at its
  windup (median 16 %; in the Valley 19 %); the threat cues are proven present and directional by the audio
  suites - their effect on people is NOT RUN.
- **The Valley holds as lane P39's matrix measured it**: every one of the novice's 18 runs completes (14.5 minutes of
  human estimate in the median, no death in the median run, none at the Ogre King) and the expert 11 of 12 (the force
  run on seed 2 runs out the Deadfall's watchdog, as before); the stage-3 flee share is still under its target (38 % on
  seeds 1-3, 46 % over the 18). Of the merged code only lane P39f's leash return acts there: it changed seven of the 24
  runs lane P39's matrix made, and no item.

## How these numbers were made

Every number comes from a headless run of the game itself in the development container (Godot 4.6.3,
`--fixed-fps 60`, a debug build, 4 shared CPU cores, no GPU), unless a section names another source.

- **The code.** The merged W23 code (`wave-23`: lane P39's balance pass - three tuning iterations, its bot's
  measurement fixes and rules of play - with lane P39f's fixes and its rebuilt world), with the one defect the
  confirmation phase fixed before measuring (the Iron Regiment's phase thresholds, commit `a7da72d`: "What changed in
  tuning" below). The report of lane P39's own runs on its branch, before the merge, is in `docs/BALANCE_LOG.md`
  ("M9 (P39)"); where a result moved between the two, `docs/BALANCE_LOG.md`, "M9 confirmation", says why.
- **The bots.** The Valley bot (P17a, `scripts/debug/valley_bot.gd`) plays the prologue under a village policy
  (`help_cache`, `help_ogre`, `intimidate`, `force`); the world bot (P38, `scripts/debug/world_bot.gd`, with P39's
  measurement fixes and rules of play: `docs/systems/P38.md`, "P39 (W23)") plays the world from `--mode=world
  --new-game` (the `world_start` character: level 6, 1,050 XP, the base club, 1 iron - the Valley's worst outcome)
  to the Stone Throne, through the input router and the camera as a player's inputs would, under a preset:
  - `peaceful`: the march helped, the wood's Matriarch driven out, Harrok spared (two oaths);
  - `conqueror`: the march forced, the Matriarch slain, Harrok fought to the death;
  - `mixed`: the march intimidated, the crown's engines sabotaged, Harrok spared;
  - the three first-oath orders (`world_orders`): the march first (help, then the crown's parley), the wood first
    (drive, then the march by force), the crown first (the breach - the Iron Regiment - then the wood slain).
  Two skills (plan §5.1, decision 30): the **novice** (the balance target: 250 ms reactions, parries half the
  blockable blows, dodges 70 % of the dodgeable ones) and the **expert** (the skill ceiling). Assisted runs take a
  quarter of the damage; the balance matrix is unassisted. Both bots explore nothing by default (`--bot-explore`
  0): they walk the road graph from objective to objective, and fight any enemy aware of them within their engage
  radius on the way (28 m at stage 4).
- **The bot's rules from stage 4 shape the ability and boss numbers.** P39 did not only correct how the world bot
  measures; where P38's bot never tried something, it gave the bot rules of play (`docs/systems/P38.md`, "P39
  (W23)"): from stage 4 every slotted ability takes its turn once it has gone 20 s unused, and a lone big foe
  draws the roar and the area blows; the expert answers only the blows that can land on it and lets no arrow hold
  its own blows off; and the expert draws the Troll Matriarch to a brazier in her slay, while the novice breaks a
  brazier only when she stands beside one. The ability shares below are those rules' as much as the abilities', and
  the boss results are the bot's way of fighting the den and the duel as much as the bosses' numbers; how people
  fight them is the playtest's.
- **The human estimate**: the bot's simulated seconds plus 4 s per dialogue node, the text at 15 characters a
  second, 8 s per screen, 10 s per district or region first entered, and in the world 6 s per map screen, 4 s per
  fast travel, 5 s per place discovered and 8 s per sealed place opened. It counts no learning, searching or
  exploring, so it is a floor for a first-time player.
- **Watchdogs.** A world run stops after 6 deaths in one main-quest stage or on a stage's time limit (300 s, a
  boss stage 600 s, the oaths 900 s); a Valley run after more than 5 deaths in a stage or 240 s on one (480 s on
  the boss). A stopped run counts as not completed.
- **The batches** (`tools/run_bots.sh`, results `user://bot_runs/<tag>/<run>.json`, tables by
  `python3 tools/bot_report.py <batch> <section>`; every batch is kept in the confirmation phase's evidence folder,
  `m9_w23/confirm/runs/<tag>/`; the commands are in `docs/BALANCE_LOG.md`, "M9 confirmation"). Three runs at a time
  on the 4-CPU container with nothing else running, so their wall times, CPU per tick and streaming work frames are
  indicative; the simulated results are not:

| Tag | What |
| --- | --- |
| `confirm_world` | the world matrix, 21 runs: the novice and the expert on seeds 1-3 of the three presets, and each first-oath order once (the novice) |
| `confirm_ir4`, `confirm_ir5` | the crown order's battle at stage 4 (`w.order_crown:novice:2`) and at stage 5 (`w.peaceful:novice:1 --bot-oaths=march:help,crown:breach`), until the crown's oath is done |
| `confirm_world_stability`, `confirm_valley_stability`, `confirm_campaign` | plan §6.2's stability runs |
| `confirm_valley` | the Valley matrix, 30 runs: the novice on seeds 1-5 of `help_cache`, `help_ogre` and `intimidate` and on seeds 1-3 of `force`, the expert on seeds 1-3 of the four (`--timeout=1500 --autoplay=2400`) |
| `confirm_world_orders` | P38's acceptance runs: each first-oath order, the novice assisted |

The runs replay exactly: a seeded run on the same game code gives the same ticks, so where a run here differs from lane
P39's run of the same seed, the merged code is the cause. In the world every run parts from lane P39's at its first
main-quest stage, the beacon below the shelf (the rebuilt world's navmeshes move the bot's legs from the start;
`docs/BALANCE_LOG.md`, "M9 confirmation", traces the moves that matter). In the Valley 17 of the 24 runs that lane P39's
matrix also made replay it to the tick; the other seven part from it where lane P39f's leash return acts, which a copy
of the merged code without that one commit confirms ("The Valley" below).

## The campaign

### Runs per preset, order and skill

`python3 tools/bot_report.py <confirm_world> world_summary`:

| Skill | Preset | Oaths (in order) | Completed | Human est. median (min) | Raw median (min) | Deaths median |
| --- | --- | --- | --- | --- | --- | --- |
| novice | peaceful | march:help, wood:drive | 3 / 3 | 42.8 | 31.9 | 4 |
| novice | conqueror | march:force, wood:slay | 0 / 3 | - | - | 6 |
| novice | mixed | march:intimidate, crown:sabotage | 2 / 3 | 32.3 | 23.3 | 6 |
| novice | march first | march:help, crown:parley | 1 / 1 | 31.4 | 21.1 | 2 |
| novice | wood first | wood:drive, march:force | 1 / 1 | 29.8 | 20.3 | 1 |
| novice | crown first | crown:breach, wood:slay | 0 / 1 | - | - | 1 |
| expert | peaceful | march:help, wood:drive | 2 / 3 | 52.1 | 41.2 | 7 |
| expert | conqueror | march:force, wood:slay | 0 / 3 | - | - | 4 |
| expert | mixed | march:intimidate, crown:sabotage | 3 / 3 | 40.1 | 31.1 | 6 |

P38's acceptance orders, the novice assisted (`confirm_world_orders`): the march first completed in 28.0 minutes of human
estimate and the wood first in 30.2, with no death; the crown first stopped on the oath stage's time limit with the
battle in its Last Stand ("The bosses", below). P38's same runs on W22 all completed. Since the M9 gate the crown first
completes again (`aldmere_e5_crown_assist`: 42.7 minutes, no death, Corvane spared at the first attempt).

### Every run

`world_runs` and `world_bosses`; "stopped" names the main-quest stage and the watchdog:

| Run | Done | Human est. (min) | Raw (min) | Deaths | Stopped at | Bosses (attempts: each attempt's lowest health share) |
| --- | --- | --- | --- | --- | --- | --- |
| w_peaceful_novice_1 | yes | 42.8 | 31.9 | 6 | | the Matriarch driven out (1: 59 %); Harrok spared (4: 40, 30, 40, 25 %) |
| w_peaceful_novice_2 | yes | 41.3 | 30.3 | 4 | | the Matriarch driven out (1: 58 %); Harrok spared (3: 40, 37, 34 %) |
| w_peaceful_novice_3 | yes | 43.3 | 32.4 | 4 | | the Matriarch driven out (1: 60 %); Harrok spared (3: 35, 35, 25 %) |
| w_conqueror_novice_1 | no | 20.9 | 14.2 | 6 | the oaths (the den: 6 deaths) | the Matriarch (6: 36, 9, 23, 21, 33, 14 %) |
| w_conqueror_novice_2 | no | 24.0 | 16.0 | 7 | the oaths (the den: 6 deaths) | the Matriarch (6: 36, 14, 28, 24, 26, 26 %) |
| w_conqueror_novice_3 | no | 20.5 | 14.1 | 6 | the oaths (the den: 6 deaths) | the Matriarch (6: 32, 12, 20, 32, 17, 17 %) |
| w_mixed_novice_1 | yes | 30.4 | 21.6 | 6 | | Harrok spared (5: 33, 43, 37, 38, 25 %) |
| w_mixed_novice_2 | no | 30.2 | 22.8 | 7 | the champion (6 deaths) | Harrok (6: 38, 60, 35, 33, 40, 46 %) |
| w_mixed_novice_3 | yes | 34.2 | 25.0 | 6 | | Harrok spared (5: 52, 42, 33, 40, 25 %) |
| w_order_march_novice_1 | yes | 31.4 | 21.1 | 2 | | Harrok spared (1: 25 %) |
| w_order_wood_novice_1 | yes | 29.8 | 20.3 | 1 | | the Matriarch driven out at stage 4 (1: 58 %); Harrok spared (1: 25 %) |
| w_order_crown_novice_1 | no | 15.1 | 10.5 | 1 | the oaths (stuck in Fort Aldmere's gateway) | the battle (1: 94 % of its bar) |
| w_peaceful_expert_1 | yes | 57.8 | 46.6 | 7 | | the Matriarch driven out (1: 57 %); Harrok spared (3: 43, 37, 25 %) |
| w_peaceful_expert_2 | yes | 46.3 | 35.8 | 5 | | the Matriarch driven out (1: 59 %); Harrok spared (1: 25 %) |
| w_peaceful_expert_3 | no | 39.4 | 30.7 | 10 | the oaths (the march's help: 6 deaths, the toll fort's tower archers 4) | - |
| w_conqueror_expert_1 | no | 29.1 | 22.8 | 3 | the oaths (the den's time) | the Matriarch (4: 46, 47, 37, 48 %) |
| w_conqueror_expert_2 | no | 48.4 | 38.9 | 8 | the champion (the duel's time) | the Matriarch driven out (3: 50, 43, 48 %); Harrok (6: 47, 11, 22, 30, 18, 95 %) |
| w_conqueror_expert_3 | no | 30.8 | 23.4 | 4 | the oaths (the den's time) | the Matriarch (4: 48, 50, 46, 69 %) |
| w_mixed_expert_1-3 | yes | 44.0, 31.7, 40.1 | 35.4, 24.2, 31.1 | 7, 1, 6 | | Harrok spared (3, 2, 4 attempts) |

Harrok yields at 25 % of his health or his third poise break: the peaceful and mixed runs then spare him, the
conqueror runs strike and fight on to the death. The conqueror expert who drove the Matriarch out had burned all three
braziers before her slay (she flees then). No run crashed, met an invariant failure, an error or a warning, or granted
a reward twice; no stop was diagnosed `world_blocked` (each was `bot_failed`: a road route existed and the stage could
still be completed).

### The segments against the plan's pacing (§5.15)

Plan §6.4 judges each segment by the novice's median over the seeds: the policy presets' completed novice runs
(`world_targets`: the peaceful and mixed novices, five runs, as no conqueror novice completed). Beside it, the median
over every completed run of the matrix (`world_segments`: those five, the two orders that completed and the five
experts). The deaths count the novice's twelve runs, then all 21:

| # | Segment | Target (range), min | Novice median: human est. / raw, min | Every completed run: human est. / raw, min | Deaths: novice runs / all runs |
| --- | --- | --- | --- | --- | --- |
| 1 | The opening (the shelf's view, the beacon, stage 4, the ancestry) | 10 (7-14) | 5.3 / 2.5 | 5.3 / 2.5 | 1 / 1 |
| 2 | The first oath | 20 (10-30) | 12.3 / 9.3 | 10.4 / 7.8 | 7 / 29 |
| 3 | The second oath | 25 (18-35) | 8.7 / 5.9 | 9.0 / 6.8 | 18 / 31 |
| 4 | Growth to 5 and 6, roaming | 15 (0-40) | 5.9 / 4.9 | 3.0 / 2.5 | 0 / 0 |
| 5 | The Stonehold (the Ironway or the Stair, the Moot, Harrok, the throne) | 24 (15-32) | 10.3 / 8.7 | 10.5 / 9.0 | 30 / 46 |
| | **The main path after the Valley** | **94 (60-140)** | **41.3 / 30.3** | **40.7 / 30.7** | 56 / 107 |

The novice's main path is 41.3 minutes of human estimate (30.3 raw), per preset peaceful 42.8 and mixed 32.3 (no
conqueror novice completed); the two orders that completed took 31.4 (the march first) and 29.8 (the wood first).
The first oath's segment is inside its range for the first time: on the King's Road to Brannock the bot now passes
the Raiders' Hollow's shield wall at about 23 m and turns to fight it (`docs/BALANCE_LOG.md`, "M9 confirmation"), so
the march's meeting takes a median 226 s where it took 54. The roaming segment (whose range starts at 0) is inside
its range too; the rest are under. The bot walks straight from objective to objective: a person reads the map,
follows the compass, explores, opens sealed places and takes side quests, none of which the main path asks for.
Exploring 30 % of each oath region's places added 3.5 minutes to one run in lane P39's measure (`p39_explore30`). Only
a timed human run can say how long the campaign is.

### The bosses

| Boss | Measured (`confirm_world`, novice unless named) | Plan §6.4 |
| --- | --- | --- |
| **Harrok the Unbowed** (the Moot's ring, stage 6) | deaths per duel: 3, 2, 2 (peaceful), 4, 6, 4 (mixed; the second stopped on its sixth) and the orders' 0 and 0 - median 2.5, won in 7 of 8; the first tries end at 33-52 % of his health; the mixed experts spare him in 2-4 attempts with one to three deaths, the peaceful experts in 1 and 3; the one conqueror expert who reached him brought him to 11 % and died five times in the duel | 1-3 per boss sequence: **met** |
| **The Troll Matriarch** (the den, stages 4-5) | driven out: at the first attempt in all six runs that drive her out (stage 4 in the wood-first order, stage 5 for the peaceful novices and experts), no death in the den; slain: by no novice at stage 5 - six attempts on each of three seeds, every one into her phase 2, the lowest 9, 14 and 12 %, six deaths each (her frenzy 7, the whelps 7 - six swipes and one she threw - her stomp 3 and her sweep 1 of the 18) - and by no expert: four, three and four attempts at 37-50 %, two runs on the den's time limit, the third drove her out after burning the braziers | 1-3: the drive-out under the range, the slay **miss** |
| **The Iron Regiment** (Fort Aldmere's bailey, the crown's breach) | the phase thresholds are fixed (the Charge at 70 % of the bar, the Last Stand at 50 %: "What changed in tuning"); at stage 4 (`confirm_ir4`) six attempts at 78-91 % of the bar, the fort's ballistae five of six deaths (74 % of the damage taken in the battle), the Charge never begins; the matrix's crown-first run and the stage-5 run (`confirm_ir5`) stopped on stucks in the fort's gateway, against the gate garrison's pike formation; assisted (`confirm_world_orders`), the Charge began at 621 s and the Last Stand at 760 s (the bar at 0.50) and again at 1,081 s, but the giant died in the Last Stand both times (a rider's charge, a ballista) and the oath's 1,320 s ran out. Since the M9 gate (the gateway clear, the gate bastions' two ballistae holding their fire until the Charge as plan §5.13 has it): assisted, won at the first attempt with no death (`aldmere_e5_crown_assist`); unassisted at stage 4 (`aldmere_e5_ir4`) six deaths, the bar at 0.79 at best - each attempt breaks the gate again under the garrison's arrows and bolts and enters the bailey with 205-401 of 1,160 health; at stage 5 (`aldmere_e5_ir5`) the Charge in two attempts of four (the bar at 0.64, 0.63; the riders ended both), six deaths, two of them outside the broken gate to the garrison the breach roused, beside the waystone the reload gives back. The battle tells the giant which ballistae shoot ("Smash the ballistae: two shoot now, two more join when the Charge begins.") | **miss**: unassisted at stages 4 and 5 (the gate after each death) |

**The den without its trunks.** Lane P39's expert drew the Matriarch to a standing brazier before breaking it (the
lure) and slew her in two runs of three. Lane P39f's rebuild cleared the places' clearings of scenery, and the den lost
15 trunks within its 45 m arena, three of them 3-6 m from the braziers; on the cleared den the lure no longer pays.
The novice fights her where she stands and breaks a brazier only when she stands beside one (lane P39's fix-up 1),
and is where lane P39 left it: a narrow miss at stage 5 that the bot's way of fighting the den decides as much as her
numbers (her phase-2 regeneration, frenzy and whelps are the levers).

### Deaths by region, boss and cause

`world_deaths` and the killers' world ids, the novice's twelve runs (56 deaths):

| Where | Deaths | What killed |
| --- | --- | --- |
| The Stonehold | 30 | Harrok 21 (his overhead chop 14, the Moot's falling stones in his phase 2 3, his frenzy 3, his charge 1); the clan scouts 8 (a rival scout giant's axe 6 - the placed scout and a wandering one - and a scout's dire wolf 2); the Moot battery's catapult 1 |
| The Greywood | 18 | the den, all in the three conqueror slays (the Matriarch's frenzy 7, stomp 3 and sweep 1, the whelps 7 - six swipes and one she threw) |
| The Crownmarch | 7 | the Raiders' Hollow 6 (its archers 3, its shield wall's brace and bash 3) and a scout's brace 1 |
| The Aldmere March | 1 | the north-east bastion's ballista (the crown-first run) |

By segment: the opening 1, the first oath 7, the second 18, the Stonehold 30; outside the bosses' fights no novice
segment had more than two deaths (plan §6.4: at most 2, **met**). The experts' 51 deaths: the Crownmarch's 23 (the
toll fort's tower archers 10 and pikes 4 in the peaceful runs' help, the Raiders' Hollow 9), the Stonehold's 16
(Harrok 12, the clan scouts 3, the battery 1), the Greywood's 8 (the den) and the Aldmere March's 4 (the war camp's
riders 2 and ballista 1 and a wandering pike column in the mixed runs' sabotage).

### Growth: does the giant's size change the fights at stages 4-6?

| Measure (plan §6.4, §5.14) | Target | Measured (`world_targets`, the 18 preset runs pooled) |
| --- | --- | --- |
| Formations hold or brace while their banner lives (share of their engaged time) | at least 50 % | 79 % |
| The giant's locks with a formation engaged that are group or banner locks | at least half | 89 % |
| Engines thrown per run that reaches stage 6 | at least 2 | 4 in 11 of 12 runs; none in `w_peaceful_expert_2` (below) |
| Lone humans flee or rout (share of their engaged time) | at least 70 % | 4 %; the lone soldiers 0 % of 371 s |

**Formations and engines** (`world_formations`, `world_siege`; the novice's twelve runs): every completed run broke 3-5
formations and seized and threw the Moot battery's four engines (two ballistae, two catapults); the mixed runs also
wrecked the war camp's four engines in the sabotage and the Ballista Ridge's three on the way (11 engines each); the
crown-first run felled three banners at the fort before its stop. Of the 14 runs that reached stage 6, 13 threw four
engines - in four during the walk from the Standing Stones to the Moot, in the rest during the duel's stage, after a
death in it. `w_peaceful_expert_2` spared Harrok at its first attempt and never came back: on the merged world the walk
to the Moot passes the battery 50 m off, just beyond the bot's siege reach of 45 m, while the battery fires on it (15
shots in that run).

| Run | Formations seen | Group-lock share | Banners felled | Broken | Routed | Sweeps | Engines destroyed / thrown | Engine shots at the giant | Damage from engines | Wander spawns |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| w_peaceful_novice_1 | 2 | 0.78 | 3 | 3 | 2 | 3 | 4 / 4 | 28 | 773 | 17 |
| w_peaceful_novice_2 | 4 | 0.77 | 2 | 5 | 1 | 2 | 4 / 4 | 21 | 243 | 17 |
| w_peaceful_novice_3 | 2 | 0.75 | 2 | 5 | 2 | 2 | 4 / 4 | 22 | 509 | 20 |
| w_conqueror_novice_1 | 0 | 1.00 | 1 | 1 | 1 | 10 | 0 / 0 | 0 | 0 | 5 |
| w_conqueror_novice_2 | 0 | 0.64 | 1 | 2 | 0 | 10 | 0 / 0 | 0 | 0 | 7 |
| w_conqueror_novice_3 | 0 | 0.86 | 1 | 1 | 1 | 10 | 0 / 0 | 0 | 0 | 5 |
| w_mixed_novice_1 | 4 | 0.84 | 1 | 3 | 2 | 5 | 11 / 4 | 43 | 1,233 | 9 |
| w_mixed_novice_2 | 5 | 0.63 | 1 | 2 | 0 | 6 | 11 / 4 | 47 | 1,271 | 10 |
| w_mixed_novice_3 | 3 | 0.81 | 0 | 3 | 2 | 8 | 11 / 4 | 23 | 728 | 12 |
| w_order_march_novice_1 | 2 | 0.79 | 2 | 3 | 2 | 0 | 4 / 4 | 7 | 266 | 10 |
| w_order_wood_novice_1 | 2 | 0.60 | 1 | 3 | 0 | 1 | 4 / 4 | 7 | 110 | 13 |
| w_order_crown_novice_1 | 0 | 0.74 | 3 | 3 | 1 | 0 | 0 / 0 | 8 | 255 | 6 |

The AI states at stages 4-6 (`world_states`, the novice's twelve runs pooled; "as formation" is the share of the
archetype's engaged time spent in a formation, "as crew" serving an engine, "harass" a rider's or a wolf's circling,
"spread" and "kite" the shooters keeping their range):

| Stage | Archetype | Engaged (s) | Approach | Attack | Recover | Staggered | Hold | Reposition | Flee | as formation | as crew | other behaviour |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4 | soldier | 10,205 | 1 % | 1 % | 1 % | 6 % | 78 % | 0 % | 13 % | 95 % | 2 % | - |
| 4 | archer | 2,457 | 43 % | 30 % | 16 % | 2 % | - | - | 5 % | - | - | spread 98 % |
| 4 | mage | 580 | 31 % | 38 % | 24 % | 4 % | - | - | - | - | - | kite 100 % |
| 4 | ogre | 513 | 21 % | 48 % | 17 % | 10 % | - | - | - | - | - | - |
| 5 | troll | 2,823 | 24 % | 40 % | 14 % | 8 % | - | 13 % | - | - | - | - |
| 5 | soldier | 1,819 | 0 % | 0 % | 0 % | 5 % | 83 % | - | 11 % | 54 % | 46 % | - |
| 5 | cavalry | 353 | 28 % | 58 % | - | 1 % | - | 11 % | 1 % | - | - | harass 100 % |
| 5 | wolf | 290 | 38 % | 21 % | 0 % | 2 % | - | 13 % | 24 % | - | - | harass 100 % |
| 5 | archer | 239 | 47 % | 17 % | 8 % | 5 % | - | - | 22 % | - | - | spread 100 % |
| 5 | rival giant | 218 | 24 % | 57 % | 13 % | 3 % | - | - | - | - | - | - |
| 6 | soldier | 3,512 | 0 % | - | - | 7 % | 78 % | - | 16 % | 85 % | 15 % | - |
| 6 | rival giant | 1,175 | 17 % | 66 % | 11 % | 5 % | - | - | - | - | - | - |

What the numbers say, stage by stage:

- **Stage 4**: humans fight in formations (95 % of the soldiers' engaged time is in one) and hold or brace (78 %):
  the pike and shield walls meet the giant at its shins, and the giant locks them as one target. Archers and mages
  keep their range and their spread. Lone soldiers do not flee yet: a lone soldier's awe costs 35 of its 70 morale,
  which leaves it above its flee threshold (most of the lone humans' engaged time is the toll fort's tower archers',
  who hold their tower by design, and the Raiders' Hollow's archers and mage).
- **Stage 5**: the trolls are the den's and the Greywood's (they flank: 13 % repositioning); nearly half the soldiers'
  time is crews' (the war camp's and the Moot battery's engines), riders charge and wheel, archers flee a fifth of
  their time, and the clan scouts - rival giants - meet the giant on the Ironway.
- **Stage 6**: a sixth of the soldiers' time is flight (16 %) and the giant throws the Moot battery's engines at their
  own lines; the only equals are the clan giants (66 % of their time attacking).

### Abilities

The world bot's ability rotation (P39: a slotted ability unused for 20 s is used on the fight's target) uses most
abilities, but Rampart Grip was never used when ready in 12 of the 18 preset runs, Formation Sweep in 11, Titan Stomp
in 9, Earthquake in 8, Heavy Footfall and Crushing Grip in 7 (their windows come while the bot is mid-blow). Among the
novice's completed runs the largest single ability's share of the ability damage is 40-79 % (Crag Hurl, Runic Bolt);
the experts lean on Runic Bolt (up to 98 %). Plan §6.4 asks every slotted ability to be used once a run and none above
40 %: **miss**, a question about the bot's policy more than the abilities.

### Discoveries, sealed places, cairns and fast travel

| Measure | Measured |
| --- | --- |
| Places discovered (of the world's 48) | 21-22 in the completed novice runs that take the wood's oath (the shelf's vista, the three shrines on the way, the settlements, the camps, the den, the Raiders' Hollow, waystones, the gate and the boss's ring), 18 in the mixed and march-first runs, 10-17 in the runs that stop early; the experts 10-25 |
| Sealed places opened, cairns read | none: the bot does not seek them (P38's known gap); the journal and the map list them |
| Fast travel | none in the matrix's 21 runs: every far goal of the main path is a first visit, and a death's reload puts the giant beside its fight; the waystones and shrines within 50 m of the way are walked into |
| Map screens | none (the bot reads the world index; a person opens the map: 6 s each in the estimate) |

### The music's intensity

The share of each stage's time in each intensity (`world_music`, the novice's twelve runs pooled):

| Stage | Seconds | Explore | Danger | Combat |
| --- | --- | --- | --- | --- |
| 3 (the opening) | 1,762 | 37 % | 63 % | - |
| 4 | 5,783 | 40 % | 17 % | 43 % |
| 5 | 5,868 | 40 % | 15 % | 45 % |
| 6 | 2,520 | 4 % | 2 % | 94 % |

Stage 6 is the Stonehold's fights - the Moot battery, the Moot's clan giants and Harrok - so its music is combat
almost throughout; stage 5 holds the conqueror novices' long fights in the den. **Among only lesser enemies** (stages
4-6, none of them taller than the music's lesser height ratio of the giant), the music was in combat 43 % of the time
over the 18 preset runs (the novice's twelve runs: 42 % of 483 s; target under 25 %: **miss**); the rest danger.
§5.14 asks that lone humans no longer raise combat music from stage 4; the intensity rules are P28's mix data.

### Readability

- **Off camera**: the share of the hits the giant takes from attackers outside the camera's view at their windup:
  median 16 % over the 18 preset runs (pooled 16 % of 5,599 hits; the novice's twelve runs 15 %, at most 24 % in one
  run; the experts' nine 18 %); 4 hits landed within 0.45 s of their telegraph. Target under 20 %: **met**. In the
  Valley (`confirm_valley`): 19 % (the median of the 30 runs; at most 29 % in a run), as in lane P39's matrix.
- **The audio caveat.** The threat cues (the far threat stings, the incoming whistles of the engines' shots, the
  siege and formation calls) are proven present for every threat and placed in the direction of their source by the
  audio suites (`test_threat_cues`, the world audio coverage suites, P21 and P28); **whether people notice and use
  them is NOT RUN** (the listening pass and the usability sessions are the owner's: `docs/USABILITY_SCRIPT.md`).
  The bots do not hear: they read telegraphs and windups.

### Streaming and performance

The plan §6.3 captures, with their commands, are in `docs/PERFORMANCE.md`, "The M9 confirmation":

| Capture | What it shows | Budget |
| --- | --- | --- |
| **The world walk** through every region at stage 6, carried at 16 m/s (a 5,531 m tour: the Kingsgate shelf, Brannock's green, a border walk, the Drowned Steps, the Greywood and Hollowmere, Aldmere's fort gate and the Ironway, Skarn and Harrok's Hall) | headless: streaming work p50 0.51 / p99 6.97 / max 12.19 ms (the max a props part's text parse), 62 loads, 56 unloads, 0 thrash, the least margin 250.3 m, at most 16 chunks loaded; CPU per tick p50 2.89 / p95 5.89 / max 30.5 ms; path queries per tick p95 1, at most 4. Rendered (Xvfb, `low`, the loads on the loader thread): work p99 4.12 / max 4.77 ms; draw calls p50 39, max 91 | streaming 4 ms a frame, margin 200 m, thrash 0, CPU 8 ms: the margin, thrash and CPU met; the work frame not (12.2 ms headless against §6.4's 12, 4.8 ms rendered against §5.2's 4) |
| **The unreachable chase** (P24b's slow test: 20 soldiers chasing a giant in deep water) | CPU per tick p95 3.32-3.33 ms over three runs; at most 8 re-paths a tick | 8 ms: met |
| **The formation stress** (40 members at tier 0 and two crewed siege engines shooting) | CPU per tick p95 4.39 ms headless, 5.47 rendered; draw calls p50 63, max 100; both engines crewed and shooting (7 bolts and 5 stones in 60 s) | 8 ms, 250 draw calls: met |
| **The bot batches** by region (the matrix's 21 runs, three at a time) | CPU per tick p95 by region, the median run: the Crownmarch 7.5, the Greywood 6.0, the Aldmere March 9.8, the Stonehold 7.7 ms; the largest 12.5 ms (the war camp's sabotage, the mixed runs) and 10.0 ms (the peaceful experts' long Crownmarch fights); whole runs 6.4-10.6 ms | p95 8 ms: met in the Greywood and the median run of the Crownmarch and the Stonehold, **not met** in the Aldmere March's fights and the slower runs |

In every campaign run the loaded margin stayed at 252.7-255.3 m with no thrash (`world_streaming`); the worst work
frame was 17.9-33.9 ms in the runs (three at a time on four CPUs; plan §6.4: at most 12 ms headless, **not met**),
its heaviest steps a props part's load. The web (headless Chromium with software WebGL) is in `docs/PERFORMANCE.md`,
"The M9 confirmation": the release pck 16.67 MB of the 23 MB budget in two parts; the world, stream and audio checks;
real browsers and GPUs are NOT RUN.

### Stability (plan §6.2)

| Run | Result |
| --- | --- |
| **The world, 60 minutes** (`--preset=world_stability`: the assisted novice, `--bot-loop` through the presets from `--mode=world --new-game`, 3,600 s; `confirm_world_stability`) | **passed**: two campaigns completed back to back (peaceful in about 1,480 s, conqueror in 1,430 s) and the third (mixed) at its grow6 stage at the end; no death; exit 0; no breach, no `world_blocked`, no duplicated reward, no invariant failure (the lock and targeting invariant included); 3 loads at the Kingsgate shelf, 1,107 / 1,114 / 1,107 nodes (0.6 %), 0 orphans; 0 errors, 0 warnings; the last campaign's 5 stuck moments all recovered, no teleport; CPU per tick p95 6.93 ms; 2,305 s of wall |
| **The Valley, 30 minutes** (`--preset=stability`; `confirm_valley_stability`) | **passed**: three slices completed (help_cache 507 s, help_ogre 473 s, intimidate 490 s) and the fourth under way; 4 loads, 1,554 / 1,561 / 1,561 / 1,561 nodes (0.5 %); 0 errors, 0 warnings, no death; CPU per tick p95 6.52 ms |
| **The campaign's hand-over** (`w.campaign:novice:1:assist`: the Valley's New Game, the Kings' Door, the world; `confirm_campaign`) | **passed**: the Valley in 504 s, Edda met at 765 s, the Stone Throne at 1,972 s (1,129 s of wall), 0 errors, 0 warnings, no death; its two loads are two levels (the Valley 1,554 nodes, the world 1,109) |

Godot prints its exit report of leaked resources after each full campaign's result (static caches holding their
scenes at quit): it comes after the run's own error count and is lane P39f's recorded item.

**Where the giant got stuck** (`world_stuck`, the matrix's 21 runs; a stuck moment is no progress toward the objective
for 6 s): 227 moments: recovered by a sidestep and jump 192, a replan 31 and a teleport 3 (the war camp's entrance and the
fort's gateway in the crown-first run, the Stone Throne's ring in `w_peaceful_novice_2`), and the one in Fort
Aldmere's gateway that stopped the crown-first run. The busiest places are the Raiders' Hollow beside the King's Road
((-125, 575) and (-75, 575): 47, the bot fighting the Hollow on its way), the war camp's south entrance ((525, 175):
30, the giant pressing on the camp's neutral shield wall on the road), the Moot battery's plateau ((-225, -575):
15, the walk to the Moot) and Fort Aldmere's gate ((675, -75) and (625, -75): 8). Since the M9 gate the camp's wall
stands off the road and the gate garrison beside the gateway's approach: in the crown runs measured since, no stuck
moment at the camp and none at the gate that needed a teleport (`docs/BALANCE_LOG.md`, "M9 gate (lane aldmere)").

## The Valley (the prologue)

The Valley's report of P17b and the M6 gate, run again on the merged code: the 30-run matrix `confirm_valley` (the
novice on seeds 1-5 of `help_cache`, `help_ogre` and `intimidate` and on seeds 1-3 of `force` - P17b's
`--preset=balance` - and the expert on seeds 1-3 of the four; unassisted, three at a time). Lane P39's tuning does not
act in the Valley (its data is the world's bosses, engines and the Matriarch; its bot changes act from stage 4 or in the
world). Of lane P39f's changes one does: the leash return (a member sent home rides round a body in its way, and after
six path failures ends its return and fights on). So 17 of the 24 runs that lane P39's matrix also made
(`p39_iter0_valley`: the novice and the expert on seeds 1-3) replay it to the tick - the same simulated seconds, kills,
hits and world flags - and the other seven (six of the expert's and one of the novice's) part from it in the ruins'
courtyard or on the way back, where the ruins' patrol and gate guards walk home past the giant. Played again on the
merged code with only that commit (`0445b85`) reverted, in a copy of the tree (`m9_w23/confirm/leash/`), three of the
seven - the expert's `help_cache` seed 2 and `intimidate` seed 1 and the novice's `intimidate` seed 3 - replay lane
P39's runs to the tick: the leash return is the cause, and it moved no item. The tables below are the 30 runs unless
they say otherwise; on seeds 1-3 alone every novice number is lane P39's.

### Per policy and skill

| Skill | Policy | Completed | Human est. median (min) | Raw median (min) | Deaths median (boss) |
| --- | --- | --- | --- | --- | --- |
| novice | force | 3 / 3 | 14.9 | 11.0 | 0 (0) |
| novice | help_cache | 5 / 5 | 15.2 | 10.0 | 0 (0) |
| novice | help_ogre | 5 / 5 | 14.0 | 9.0 | 0 (0) |
| novice | intimidate | 5 / 5 | 13.2 | 8.9 | 0 (0) |
| expert | force | 2 / 3 | 18.0 | 14.5 | 0 (0) |
| expert | help_cache | 3 / 3 | 18.8 | 13.9 | 0 (0) |
| expert | help_ogre | 3 / 3 | 17.2 | 12.3 | 0 (0) |
| expert | intimidate | 3 / 3 | 16.4 | 12.3 | 0 (0) |

The expert's force run on seed 2 ran out the Deadfall stage's 240 s on the way back from Kingsfall, as in lane P39's
matrix (there traced: about 206 s of the stage went to the ruins' patrol and gate guards, `p39_valley_trace`); on the
merged code it also died once on that road, to the village road's ambush archer: a slow expert fight, not a blocked
path. Every help and intimidate run ends with Thornwick at peace (24 runs); every force run ends with it hostile, as
that branch means.

### The segments against the plan's pacing (M2-M5 §4.9)

The novice's 18 runs:

| Segment | Target (range), min | Novice human est. median, min | Raw median, min | Damage / max health, median (estimate) | Deaths (all novice runs) |
| --- | --- | --- | --- | --- | --- |
| Hollow | 3.0 (2-4) | 1.6 | 0.6 | 0.05 | 0 |
| Forest | 5.5 (4-7) | 2.7 | 2.1 | 1.39 | 3 |
| Grove | 2.0 (1.5-2.5) | 0.7 | 0.2 | 0.00 | 0 |
| Village | 4.0 (1.5-7) | 2.5 | 1.3 | 0.34 | 0 |
| Ruins | 4.0 (3-5) | 2.7 | 2.3 | 1.00 | 8 |
| Boss | 4.0 (2.5-6) | 1.3 | 0.9 | 0.97 | 0 |
| Return | 3.5 (2.5-4.5) | 2.7 | 1.9 | 0.29 | 0 |

On seeds 1-3 alone (lane P39's twelve novice runs, to the tick): 14.2 minutes of human estimate and 9.1 raw, the forest's
damage 1.23 and the ruins' 1.00 of maximum health, the five deaths all in the ruins. The bot plays the slice in about 9.5
minutes of simulated time and 14.5 of human estimate (the novice's median), against the plan's 20-30; the shortfall is
where a first-time player spends time the estimate does not count: the Hollow's tutorial, the forest (learning to
guard, parry and grab), the Grove (the growth, the first boulder, the view).

### Novice versus expert

| Measure (median per run) | Novice (18 runs) | Expert (12 runs) |
| --- | --- | --- |
| Completed | 18 / 18 | 11 / 12 |
| Deaths | 0 | 0 |
| Human estimate (min, completed runs) | 14.5 | 17.2 |
| Raw simulated time (min, completed runs) | 9.5 | 12.7 |
| Damage taken | 2,854 | 1,860 |
| Parries / blocks / dodges | 4 / 30 / 3.5 | 85 / 127 / 41 |
| Light attacks / heavies / throws | 140 / 9 / 11 | 117.5 / 4 / 23 |
| Ogre King time-to-kill (s) | 38 | 61 |
| Soldier time-to-kill, stage 1 / stage 2 (s) | 25 / 12 | 36 / 33 |
| Hits from attackers off camera (share of the hits taken) | 0.19 | 0.19 |

Skill shows in defence, not speed: the expert parries about twenty times as often and takes a third less damage, but
it spends its stamina guarding, so its fights and runs are longer.

### Deaths, readability and getting stuck

- **Deaths**: the novice's eleven in 18 runs - the ruins' courtyard 8 (the sergeant's brace 4, the terrace archer's
  shot 3, the mage's slowing bolt 1) and the forest 3 (seed 5, all three policies: the forest ogre's wolf's lunge at
  the same moment); on seeds 1-3 the five of lane P39's matrix, all in the ruins. The expert's one: the force run on
  seed 2, on the way back. The courtyard (a formation that braces, a terrace archer out of reach, a mage) is where a
  person should be watched first.
- **The Ogre King**: no novice died there (none of 18 runs; the plan expects one retry from a first-time player, and a
  person plays less evenly than the bot).
- **Off camera**: 19 % of the hits taken (median of the 30 runs; at most 29 % in a run), the plan's target under 20 %:
  met, as in lane P39's matrix; none landed within 0.45 s of its telegraph.
- **Stuck moments** (no progress for 6 s): 33 in the 30 runs, all recovered by a side-step and jump (30) or a replan
  (3), no teleport (lane P39's matrix: 26 in 24 runs, one teleport); the busiest cells are the Hollow's way out (-110,
  170: 13, nine of them on seeds 4-5), the ruins' armory (170, -90: 6), the junction on the way into Thornwick (10 to
  30, -90: 7) and the Deadfall's road west of the village (110, -10 and -30: 4).

### Growth in the Valley

| Measure | Target | Median (novice, 18 runs) | Range |
| --- | --- | --- | --- |
| Soldiers in HOLD, stage 1 (share of engaged time) | 0 | 0.00 | 0.00-0.00 |
| Soldiers in HOLD, stage 2 | at least 0.5 | 0.57 | 0.50-0.68 |
| Soldiers in FLEE or ROUTED, stage 3 | at least 0.5 | **0.46** (seeds 1-3: 0.38) | 0.11-0.64 |
| Soldier time-to-kill, stage 2 / stage 1 | at most 0.6 | 0.59 (seeds 1-3: 0.51) | 0.34-1.67 |

The same soldiers advance and trade blows at stage 1, hold formation and brace at stage 2, and break at stage 3 - but
at stage 3 they fled 46 % of their engaged time in the median of the 18 runs and 38 % on seeds 1-3, which are lane P39's
runs to the tick (the M6 gate's 52 %, P22's 40 %): a run's share spreads 11-64 %, so a median moves by more than the
target's margin between batches. Lane P39f's raider change (no rout from a giant the raider does not see) acts only on
units that have targets of their own (the world's raid), so the Valley's soldiers are as they were; the shared
`enemy.soldier`'s awe loss is the lever for this share and the world's lone humans alike.

### Abilities in the Valley

Every ability is used in every novice run but Sweeping Blow (2 of 18: the bot tries Heavy Footfall first for a crowd)
and Titan Surge (16 of 18); the largest single share of ability damage per run is Heavy Footfall's, Boulder Hurl's,
Runic Bolt's or Crushing Grip's, 28-46 % (target at most 40 %: five runs over, four of them on seeds 1-3 as in lane
P39's matrix).

### Performance in the Valley

CPU per tick p95 median 5.65 ms, at most 6.31 ms in the 30 runs (three at a time; lane P39's matrix, two at a time,
5.47 and 5.93 ms; budget 8 ms); at most 12 active enemies; 0 errors, 0 warnings, 0 invariant failures. The Valley's
draw calls: the rendered Valley walk at `low` is at p50 93, p95 143, max 154 (P27; `docs/PERFORMANCE.md`).

## What changed in tuning, and why

### The M9 gate (lane aldmere): Fort Aldmere and the war camp (`docs/BALANCE_LOG.md`, "M9 gate (lane aldmere)")

| What | Before -> after | Why |
| --- | --- | --- |
| Fort Aldmere's gate garrison: its pike formation's post (`data/world/encounter_aldmere_fort_gate.json`) | pivot (650, -79.1), on the gate's line -> (626, -75), in front of the west bastion beside the road's approach | every titan path into the bailey crosses the gate's nav link and the formation stood on it: a stage-4 to stage-6 giant stopped against it, breached or opened (two crown runs of three stopped there) |
| The war camp's shield wall (`data/world/encounter_aldmere_war_camp.json`) | pivot (520, 163), on the King's Road's line -> (500, 163), beside it | a giant at peace walking the road through the camp stood against the neutral front rank (30 stuck moments in the matrix) |
| The Iron Regiment's gate-bastion ballistae (the Charge's `engines` list; `BattleBoss`) | shoot from the Wall's first blow -> hold their fire until the Charge | plan §5.13: two ballistae fire in the Wall (the inner pair, the Wall's own crews), all four from the Charge; the bastion pair stands 16 m up behind a giant at the bailey's gate end, out of a stage-4 giant's reach and sight |
| The Iron Regiment's HUD lines (`BattleBoss.engines_line`, `phase_engines_line`) | the portcullis's line only -> also "Smash the ballistae: two shoot now, two more join when the Charge begins." as it engages and "Two more ballistae open fire." at the Charge | the ballistae take most of the giant's health in the battle (52-60 % unassisted); the quest's word for them was only in the journal |

No unit's numbers changed; the battle's bar and its thresholds are as they were.

### The M9 confirmation (W23): the Iron Regiment's phase thresholds (`docs/BALANCE_LOG.md`, "M9 confirmation")

| What | Before -> after | Why |
| --- | --- | --- |
| The Iron Regiment's Charge and Last Stand (the battle arena's phases in `tools/data/world/aldmere.json`) | at 60 % and 25 % of the battle's bar -> at 70 % and 50 % | the bar counts the fort's four ballistae (3,600) and the Wall's two inner-ballista crews, which plan §5.13 keeps shooting into the Charge: with them standing, the Wall's fall left the bar at 62 % (the web's smaller battle 67 %) and the riders' fall at 45 % (47 %), so neither phase could begin by its fraction - a layout defect, fixed for every composition; no unit's numbers changed |

### M9 (P39): the world's bosses and engines (`docs/BALANCE_LOG.md`, iterations 1-3)

| What | Before -> after | Why (the runs before) |
| --- | --- | --- |
| Harrok's overhead chop (power) | 120 -> 95 -> 75 | the killing blow in 28 of the novice's 39 deaths to Harrok; 63-77 % of the damage he dealt the novice |
| Harrok's health | 5,000 -> 4,300 -> 3,400 | the novice's tries ended at about 40 % of his health, where he yields at 25 % |
| The Troll Matriarch's regeneration (phase 1 / phase 2) | 25 / 40 -> 15 / 25 -> 12 / 15 hp/s | it matched what the giant deals (the M8 gate's F37); the slay held at 33-49 % in her phase 2 |
| The Matriarch's phase-2 call | 3 -> 2 whelps | 11 of 12 conqueror-novice tries died in her phase 2 |
| The ballista bolt (power; its poise stays) | 90 -> 60 | five deaths in a row on the Ballista Ridge; the ballistae 68-77 % of the Iron Regiment's damage |
| The catapult stone (power) | 110 -> 85 | the siege of Skarn at stage 5 |
| The bot (measurement fixes and rules of play: no game change) | `docs/systems/P38.md`, "P39 (W23)" | the measures of §6.4, siege disruption, shots only along a clear line, the ability rotation, the expert's answers from stage 4, the Matriarch's brazier lure (the expert's alone since the report's review) |

Kept: every windup and telegraph, every player number, the XP and the wander weights (every run grew on time for
its path), the Iron Regiment's web aggregate and everything in the Valley.

### M5-M6 (P17b, P22): the Valley

| What | Before -> after | Why |
| --- | --- | --- |
| The Ogre King's slam | 126 damage, 1.3 s windup, 1.4 s recovery -> 101, 1.5 s, 1.8 s | 42 novice deaths in P17b's baseline |
| The King's combo | 76 / 92 -> 67 / 77 | 47 deaths in the baseline |
| The King's pause between attacks | 0.3-0.6 -> 0.6-1.0 s | back-to-back attacks left no time to recover |
| The brace counter | 35 -> 28 | the courtyard's formation |
| The archer's shot | 25 -> 21 | the courtyard's terrace archer |
| The ogre's smash (stage 1) | 58 -> 46 | the forest ogre |
| Soldiers' pause between strikes | 0.8-1.4 -> 1.2-1.8 s | two stage-1 soldiers at the giant's legs |
| The swing's aim, the director's budget (game code) | fixed tilt -> aims at the lock; a hostile faction's members count | blows landed short; the force branch's 16 hostiles |

## Known issues

- **The conqueror's slay of the Troll Matriarch**: no novice slays her (six attempts on each of three seeds, every one
  into her phase 2, down to 9, 14 and 12 % of her health; her frenzy and her whelps kill it as she nears the end) and,
  on the merged code, no expert either: the den is a clearing since lane P39f's rebuild (15 trunks gone from its arena)
  and the expert's brazier lure, made on the old den, no longer pays (attempts at 37-50 %). Her phase-2 regeneration,
  frenzy and whelps are the levers; the owner's playtest decides how hard the slay should be.
- **The Iron Regiment at stage 4** (the crown's oath first): the phases now follow the Wall and the Charge (fixed in the
  confirmation phase), but the novice brings the battle's bar to 78 % at best before the fort's four ballistae kill it
  (five deaths of six, 74 % of the damage taken in the battle); assisted, it reaches the Last Stand (the bar at 50 %)
  twice and dies in it, to a rider's charge and a ballista. At stage 5 the battle was not reached. Since the M9 gate
  (the gateway clear; in the Wall only the two inner ballistae shoot, as plan §5.13 has it) the assisted order wins the
  battle at the first attempt with no death, but the unassisted novice still loses at stage 4 (0.79 at best, six
  deaths): every death reloads the fort gate's waystone, a checkpoint from before the breach, so each attempt breaks
  the gate again for over a minute under the garrison's four wall archers and the bastions' two ballistae and enters
  the bailey with a quarter of its health or less. At stage 5 (the march's help, then the breach) it reaches the Charge in two attempts of four, where the riders end
  them, and twice dies outside the broken gate: the death reload comes back at the gate's waystone beside the garrison
  the breach roused. The battle now tells the giant which ballistae shoot - "Smash the ballistae: two shoot now, two
  more join when the Charge begins." as it engages, "Two more ballistae open fire." as the Charge frees the bastions'
  pair.
- **Fort Aldmere's gateway** (fixed at the M9 gate): the gate garrison's pike formation stood in the gateway's mouth,
  on every titan path into the bailey, with about 5 m beside each flank - less than a stage-4 or stage-5 giant needs;
  two crown runs of three stopped there. It now stands in front of the west bastion beside the road's approach, and a
  stage-4 to stage-6 giant walks through the breached or opened gate past it (`tests/gate/test_fort_gateway.gd`).
- **The war camp's shield wall across the King's Road** (fixed at the M9 gate): moved 4 m into the camp by lane P39f,
  it stood on the road's line, and a giant at peace pressed against the neutral front rank (30 stuck moments in the
  matrix). It now stands on open ground west of the road between the camp's tents (`tests/gate/test_war_camp_road.gd`).
- **The Raiders' Hollow beside the King's Road**: the road to Brannock passes its shield wall at about 23 m on the
  rebuilt world and the bot turns to fight it in most runs (a person may walk on); it adds a few minutes and a death
  in some runs to the first oath.
- **The peaceful experts** die to the toll fort's tower archers on the march's help (ten of their 22 deaths; one run
  stopped there) - the expert's world rules, a bot question.
- **The Moot battery and the walk to the Moot**: the giant passes the battery 50 m off on the rebuilt world; the bot
  fights it only when it comes back after a death in Harrok's duel (one run of 14 never did and threw no engine).
- **The siege of Skarn at stage 5** (Ulfra's plea taken before stage 6; lane P39's targeted run `p39_i3_skarn5`, not
  repeated here) killed the novice six times and did not end: the line's riders and engines shoot the giant rather than
  the longhouses; at stage 6 it is a minute's work.
- **Lone humans do not flee a stage-4 giant** (4 % of their engaged time; §5.14: "single humans flee on sight"): a
  lone soldier's awe (35 of 70 morale) leaves it above its flee threshold. The lever is the awe's morale loss for the
  world's soldiers (46 or more); lane P39f's raider change did not move it.
- **Pace**: the main path played straight is about 41 minutes against 75-140 (above): a person's time is the
  measure.
- **The music among lesser enemies** is in combat 43 % of the time (target under 25 %): P28's mix data.
- **Abilities**: Rampart Grip, Formation Sweep and Titan Stomp sit unused in half the runs or more; one ability takes
  over 40 % of the ability damage in most runs (Runic Bolt for the experts: the bot's policy).
- **The worst streaming work frame** is a large props part's text parse (12.2 ms on the world walk headless,
  17.9-33.9 ms in the campaign runs three at a time; exports ship binary scenes, about a tenth of the time:
  `docs/systems/P39f.md`).
- **CPU per tick in the Aldmere March's big fights** (the war camp's sabotage 11.2-12.5 ms p95, three runs at a time on
  the container): over the 8 ms budget there; a reference PC is the measure.
- **The Valley's stage-3 flee share** is 38 % on the seeds lane P39's matrix measured (46 % over the 18 novice runs;
  target 50 %): the shared soldier's awe loss is the lever. The expert's force run on seed 2 still runs out the
  Deadfall's watchdog on the way back.
- **No fast travel in the matrix**: the main path never returns to a visited place far away; a person's return
  trips (a forge, a shrine, an old oath's town) are where fast travel matters, and the usability sheet checks it.

## What to try first

Run the game from the editor (F5) or `godot --path .`. Debug builds have F3 (the debug panel), F6 / F7 (grow / shrink
one stage on the spot, outside progression), F8 (XP) and F9 (reload the last checkpoint).

**The 10-minute world tour** (`godot --path . -- --mode=world --new-game`, or the launcher's "Start in the open
world": the giant wakes on the Kingsgate shelf at stage 3, level 6, as after the Valley):

1. **The view** (1 min): from the shelf the kingdom lies below - the Crownmarch's roads and towns, the Greywood in
   the west, the Drowned Steps' meres, Aldmere's fort far east, the Stonehold's highlands on the skyline. The compass
   (top centre) shows the quest's gold diamonds; M opens the map, J the journal.
2. **The beacon and stage 4** (2-3 min): down the ramp, relight the Kingsgate beacon, grow at the Kingsgate Shrine
   and choose an ancestry. The camera pulls back; humans now meet the giant's knees.
3. **A formation** (2-3 min): the King's Road south-east toward Brannock: the Raiders' Hollow's shield wall holds its
   post beside the road, and the toll fort beyond has a pike wall that braces at the giant's legs; locking either takes
   the whole formation as one target; break its banner and it routs. The fort's tower archers shoot from above - a Crag
   Hurl or a boulder reaches them.
4. **Stage 6 and an engine** (2 min): F6 twice, then on along the King's Road to the Ballista Ridge over it (about
   550 m past the toll fort: half a minute at a sprint); strike a ballista until it staggers, seize it and throw it
   at its own line.
5. **Fast travel** (1 min): the map, a waystone you touched (the Kingsgate shelf's), Travel.

**The full campaign** (New Game from the title; about 15 minutes for the Valley and 30-45 for the world's main path
by the bot's estimate, much more for a person who explores): the Valley's crown, the Kings' Door, the Kingsgate
shelf, two of the three oaths (the march's toll and raiders, the Greywood's Matriarch, Aldmere's Iron Regiment or
its war camp), stage 5 and the Drowned Steps, stage 6 at the Standing Stones, the Giant's Stair or the Ironway to the
Moot, Harrok's duel, the Stone Throne.

Things to watch, from where the bots struggled: Harrok's overhead chop (unblockable, a long line: dodge sideways,
not back) and the Moot's falling stones in his second phase; the Matriarch's regeneration and her whelps in her
second phase (fight her beside a brazier: its fire stops it); the Iron Regiment's ballistae, and Fort Aldmere's gate
under the garrison's arrows and bolts after a death, when the crown comes first; the toll fort's tower archers; the Raiders' Hollow's archers and
mage.

**The 5-minute combat tour** (New Game, the Valley's Hollow): the dummies and the sparring post teach the light
chain, the heavy, Heavy Footfall, the block, the parry and the dodge; the forest's first wolves and hunters follow;
F6 shows stage 2's formations and stage 3's awe on what is left of them.

## What a human playtest should look for

- **The world's first minutes**: does the shelf's view say where to go; do players find the beacon, the shrine, the
  map and the compass without the bot's index?
- **Formations at stage 4**: do players lock the group, see the brace, find the banner? Do they walk past the Raiders'
  Hollow on the King's Road or fight it?
- **Harrok**: does the chop read (a long line, unblockable); is the duel fair at a median of two or three deaths for
  the bot?
- **The Matriarch**: do players find the braziers' fire without being told; is the slay fair?
- **The Iron Regiment**: with the phases fixed, is the bailey a fair fight at stage 4 under the fort's ballistae, and do
  players get through the gate garrison in the gateway?
- **Fast travel and sealed places**: the bot never used them on the main path; where do players use them?
- **Readability and audio**: do players hear the threat stings and the engines' whistles and turn to them?
- **Pacing**: time each §5.15 segment; the bot's estimate is a floor.
- `docs/USABILITY_SCRIPT.md` has the sheets (the Valley's first 10 minutes, the world's 20 minutes from the Kings'
  Door, the audio sheet).

## NOT RUN (human or reference-hardware gates)

| Gate | How to run it |
| --- | --- |
| Usability sessions with 3 new players (the Valley's first 10 minutes; 20 minutes of the world from the Kings' Door) | `docs/USABILITY_SCRIPT.md` |
| A timed human run of the Valley and of the world's main path | any playtest above: time each segment against plan §4.9 and §5.15 |
| The listening pass on speakers and headphones (balance, harshness, threat readability, music fatigue) | `docs/USABILITY_SCRIPT.md`, the audio sheet |
| Real-controller checklist (the map, journal, track and pin bindings) | `docs/USABILITY_SCRIPT.md` |
| Frame time and GPU time at 1080p `low` on the reference PC | `docs/PERFORMANCE.md`, "Commands" and "Reference PC results" |
| Draw calls and frames on a real GPU (the world walk, the formation stress) | the same runs print `draw_calls` and `frame_ms` in `PERF_RESULT` |
| Real browsers (load time with the multi-part pack, streaming hitches, audio in a hidden tab, the strict audio criterion) | `docs/PERFORMANCE.md`, "Web build checklist"; `tools/web/stream_check.mjs --strict`, `world_check.mjs` |

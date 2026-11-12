# How it plays

What the campaign plays like - the Valley of Broken Kings as its prologue and the open world after it - measured
by the game's own bots on the M9 code (plan M6-M9 §6.5): runs per preset, oath order and skill, the time of each
segment against the plan's pacing, deaths by region, boss and cause, how growth changes the fights at stages 4-6,
discoveries and fast travel, the music, streaming, performance and stability, what changed in tuning, what is
still wrong, and what a person should try first. **No human has played these builds for this report**: the human
playtests, a timed human run, the listening pass and the reference-PC and real-browser numbers are listed as NOT
RUN at the end.

**Marked numbers.** Every number below comes from a named run (its batch tag is given). Numbers marked **[C]**
come from runs on the measurement lane's code (`pkg/P39`: `wave-22` with P39's tuning and bot fixes, before its
merge with the fixes lane P39f); the W23 confirmation phase runs the same batches on the merged code and replaces
them. The fixes lane changed what some of them measure: raiders no longer rout from a giant they do not see (the
lone humans, the Valley's stage-3 flee share), the world's placed fights stand on open ground and the world was
rebuilt (`docs/systems/P39f.md`).

## In short

- **The campaign is completable, and the novice finishes most of it** [C]. Of the matrix's 18 unassisted runs
  (the novice on seeds 1-2 of the three policy presets, the expert on seeds 1-3, and each oath first), 10
  reach the Stone Throne: both peaceful novices, both mixed novices and all three mixed experts, one of the two
  conqueror novices, and the march-first and wood-first orders. The three stability runs pass (below).
- **Where it stops**: the Iron Regiment at stage 4 (the crown's oath taken first: six attempts, the fort's
  ballistae kill the giant five times, the battle's Charge never comes - a layout threshold left for the merge,
  below); the conqueror's slays (the Troll Matriarch slain by one novice of two, Harrok slain by no expert of
  three); and the peaceful experts, who die six times each at the Raiders' Hollow (a question about the expert
  bot's world rules, not the game's numbers).
- **The bosses after tuning** [C]: the novice wins Harrok's duel with a median of 2 deaths (it was 6 before P39's
  balance pass), the Matriarch is driven out in one attempt, at stage 4 or 5, and the mixed experts spare Harrok
  with at most one death.
- **It is short when played straight** [C]: about 33 minutes of human estimate for the main path after the Valley
  (the plan's target 75-140): the bot walks from objective to objective, opens no sealed place, reads no cairn and
  takes no side quest. Exploring 30 % of each oath region's places adds 3.5 minutes.
- **Growth shows** [C]: formations hold or brace 85 % of their engaged time while their banner lives, 86 % of the
  giant's locks with a formation engaged are group or banner locks, every run that reaches stage 6 throws 4
  engines (the siege of Skarn at stage 6 is a minute of throwing engines). Lone soldiers do not flee a stage-4
  giant yet (3 % of the lone humans' engaged time against the target's 70 %: a known issue).
- **Stable**: the 60-minute world run (two campaigns back to back), the 30-minute Valley run and the campaign's
  hand-over from the Valley all passed: no crash, no blocked world, no duplicated reward, no invariant failure, no
  error or warning, node counts within 0.6 %.
- **Within the CPU budget when the machine is not shared** (the container, indicative): the world walk through every
  region at stage 6 runs at CPU per tick p95 5.3 ms, the 40-member formation stress with two siege engines at 4.2
  ms, the unreachable chase at 4.3-4.7 ms (budget 8 ms); the bot matrices ran two at a time beside the other lane's
  checks and read 6-21 ms. The worst streaming work frame is a text scene's parse (17.7 ms headless, about a tenth
  of that in an export's binary scenes).
- **Readability** [C]: about one hit in nine that the giant takes in the world comes from an attacker off camera at
  its windup (median 11 %; the Valley 19 %); the threat cues are proven present and directional by the audio
  suites - their effect on people is NOT RUN.
- **The Valley holds as P22 and the M6 gate left it** [C]: every novice run and 11 of 12 expert runs complete, with a
  median of no death; nothing of P39's tuning acts there.

## How these numbers were made

Every number comes from a headless run of the game itself in the development container (Godot 4.6.3,
`--fixed-fps 60`, a debug build, 4 shared CPU cores, no GPU), unless a section names another source.

- **The bots.** The Valley bot (P17a, `scripts/debug/valley_bot.gd`) plays the prologue under a village policy
  (`help_cache`, `help_ogre`, `intimidate`, `force`); the world bot (P38, `scripts/debug/world_bot.gd`, with P39's
  measurement fixes: `docs/systems/P38.md`, "P39 (W23)") plays the world from `--mode=world --new-game` (the
  `world_start` character: level 6, 1,050 XP, the base club, 1 iron - the Valley's worst outcome) to the Stone
  Throne, through the input router and the camera as a player's inputs would, under a preset:
  - `peaceful`: the march helped, the wood's Matriarch driven out, Harrok spared (two oaths);
  - `conqueror`: the march forced, the Matriarch slain, Harrok fought to the death;
  - `mixed`: the march intimidated, the crown's engines sabotaged, Harrok spared;
  - the three first-oath orders (`world_orders`): the march first (help, then the crown's parley), the wood first
    (drive, then the march by force), the crown first (the breach - the Iron Regiment - then the wood slain).
  Two skills (plan §5.1, decision 30): the **novice** (the balance target: 250 ms reactions, parries half the
  blockable blows, dodges 70 % of the dodgeable ones) and the **expert** (the skill ceiling). Assisted runs take a
  quarter of the damage; the balance matrix is unassisted. Both bots explore nothing by default (`--bot-explore`
  0): they walk the road graph from objective to objective.
- **The human estimate**: the bot's simulated seconds plus 4 s per dialogue node, the text at 15 characters a
  second, 8 s per screen, 10 s per district or region first entered, and in the world 6 s per map screen, 4 s per
  fast travel, 5 s per place discovered and 8 s per sealed place opened. It counts no learning, searching or
  exploring, so it is a floor for a first-time player.
- **Watchdogs.** A world run stops after 6 deaths in one main-quest stage or on a stage's time limit (300 s, a
  boss stage 600 s, the oaths 900 s); a Valley run after more than 5 deaths in a stage or 240 s on one (480 s on
  the boss). A stopped run counts as not completed.
- **The batches** (`tools/run_bots.sh`, results `user://bot_runs/<tag>/<run>.json`, tables by
  `python3 tools/bot_report.py <batch> <section>`; every batch is kept in the measurement lane's evidence folder,
  `m9_w23/P39/runs/<tag>/`):

| Tag | What | Code |
| --- | --- | --- |
| `p39_report_set` | the world matrix as it stands after P39's three iterations, 18 runs: the novice's nine (`p39_rep_world`, below) and the experts' nine (`p39_i3_world`) | the final numbers |
| `p39_rep_world` | the novice on seeds 1-2 of the three presets and the three orders, run again on the final numbers with the CPU per tick filed by region (`tools/run_bots.sh <9 runs> --jobs=1 --timeout=3600`, two streams) | `00a2bad` (`cee2edd`'s game) |
| `p39_i3_world` | iteration 3's runs: the experts on seeds 1-3 of the three presets, the conqueror novice on seed 2, the three orders | `cee2edd` |
| `p39_iter0_world` | iteration 0 (before tuning): the same 18 runs | `b6fc032` |
| `p39_iter0_valley` | the Valley matrix: novice and expert x the four policies x seeds 1-3, 24 runs (`--timeout=1500 --autoplay=2400`) | `b6fc032` (no later change acts in the Valley; `p39_i3_valley` replayed its expert force seed 2 to the tick on `cee2edd`) |
| `p39_world_stability3`, `p39_valley_stability`, `p39_campaign` | plan §6.2's stability runs | iteration 0's game and bot (`b6fc032`; the 60-minute world run `9e2105b`) |
| `p39_explore30` | exploration's pace: `w.peaceful:novice:1:assist --bot-explore=0.3` | `9e2105b` |
| `p39_i3_skarn5`, `p39_skarn6`, `p39_i3_ir5`, `p39_ir4`, `p39_mat4_drive`, `p39_mat4_slay` | targeted fights (`docs/BALANCE_LOG.md`, "Targeted measurements") | `9e2105b`, `cee2edd` |

The bot runs ran two at a time on the 4-CPU container, often beside the other W23 lane's builds and checks, so
their wall times, CPU per tick and streaming work frames are indicative; the simulated results replay exactly
(a seeded run on the same code gives the same ticks).

## The campaign

### Runs per preset, order and skill [C]

`python3 tools/bot_report.py <p39_report_set> world_summary`:

| Skill | Preset | Oaths (in order) | Completed | Human est. median (min) | Raw median (min) | Deaths median |
| --- | --- | --- | --- | --- | --- | --- |
| novice | peaceful | march:help, wood:drive | 2 / 2 | 34.3 | 24.8 | 2 |
| novice | conqueror | march:force, wood:slay | 1 / 2 | 35.0 | 25.7 | 6 |
| novice | mixed | march:intimidate, crown:sabotage | 2 / 2 | 25.0 | 17.6 | 2 |
| novice | march first | march:help, crown:parley | 1 / 1 | 32.3 | 23.1 | 4 |
| novice | wood first | wood:drive, march:force | 1 / 1 | 30.1 | 21.3 | 3 |
| novice | crown first | crown:breach, wood:slay | 0 / 1 | - | - | 6 |
| expert | peaceful | march:help, wood:drive | 0 / 3 | - | - | 6 |
| expert | conqueror | march:force, wood:slay | 0 / 3 | - | - | 7 |
| expert | mixed | march:intimidate, crown:sabotage | 3 / 3 | 27.0 | 19.7 | 1 |

### Every run [C]

`world_runs` and `world_bosses`; "stopped" names the main-quest stage and the watchdog:

| Run | Done | Human est. (min) | Raw (min) | Deaths | Stopped at | Bosses (attempts: each attempt's lowest health share) |
| --- | --- | --- | --- | --- | --- | --- |
| w_peaceful_novice_1 | yes | 35.7 | 26.2 | 2 | | the Matriarch driven out (1: 58 %); Harrok spared (3: 32, 37, 25 %) |
| w_peaceful_novice_2 | yes | 32.9 | 23.5 | 1 | | the Matriarch driven out (1: 59 %); Harrok spared (2: 61, 25 %) |
| w_conqueror_novice_1 | yes | 35.0 | 25.7 | 6 | | the Matriarch slain (1); Harrok slain (6: 62, 36, 20, 33, 9, 0 %) |
| w_conqueror_novice_2 | no | 22.9 | 16.3 | 7 | the oaths (the den: 6 deaths) | the Matriarch (6: 48, 32, 24, 38, 84, 36 %) |
| w_mixed_novice_1 | yes | 24.7 | 17.3 | 2 | | Harrok spared (3: 46, 43, 25 %) |
| w_mixed_novice_2 | yes | 25.3 | 17.9 | 3 | | Harrok spared (4: 45, 36, 35, 25 %) |
| w_order_march_novice_1 | yes | 32.3 | 23.1 | 4 | | Harrok spared (5: 44, 38, 30, 34, 25 %) |
| w_order_wood_novice_1 | yes | 30.1 | 21.3 | 3 | | the Matriarch driven out at stage 4 (1: 59 %); Harrok spared (2: 47, 25 %) |
| w_order_crown_novice_1 | no | 27.3 | 21.2 | 6 | the oaths (the Iron Regiment: 6 deaths) | the battle (6: 86, 79, 65, 70, 100, 69 % of its bar) |
| w_peaceful_expert_1-3 | no | 17.3-18.2 | 11.7-12.6 | 6 each | the oaths (the Raiders' Hollow: 6 deaths) | - |
| w_conqueror_expert_1 | no | 51.1 | 41.4 | 7 | the champion (6 deaths) | the Matriarch slain (1); Harrok (6: 53, 34, 8, 22, 18, 35 %) |
| w_conqueror_expert_2 | no | 37.4 | 31.1 | 7 | the oaths (the den's time) | the Matriarch (4: 47, 48, 35, 49 %) |
| w_conqueror_expert_3 | no | 49.6 | 40.0 | 8 | the champion (the duel's time) | the Matriarch slain (2: 87, 0 %); Harrok (6: 49-19 %) |
| w_mixed_expert_1-3 | yes | 26.6-29.1 | 19.3-21.7 | 1, 1, 0 | | Harrok spared (2, 2, 1 attempts) |

Harrok yields at 25 % of his health or his third poise break: the peaceful and mixed runs then spare him, the
conqueror runs strike and fight on to the death. No run crashed, met an invariant failure, an error or a
warning, or granted a reward twice; no stop was diagnosed `world_blocked`.

### The segments against the plan's pacing (§5.15) [C]

`world_segments` (median of the runs that reached each segment; human estimate, then raw simulated time):

| # | Segment | Target (range), min | Human est. median | Raw median | Deaths (all runs) |
| --- | --- | --- | --- | --- | --- |
| 1 | The opening (the shelf's view, the beacon, stage 4, the ancestry) | 10 (7-14) | 4.6 | 1.6 | 0 |
| 2 | The first oath | 20 (10-30) | 2.2 | 1.2 | 25 |
| 3 | The second oath | 25 (18-35) | 8.8 | 6.8 | 18 |
| 4 | Growth to 5 and 6, roaming | 15 (0-40) | 2.7 | 2.4 | 0 |
| 5 | The Stonehold (the Ironway or the Stair, the Moot, Harrok, the throne) | 24 (15-32) | 8.9 | 7.4 | 33 |
| | **The main path after the Valley** | **94 (60-140)** | **29.6** | **21.5** | 76 |

The novice's completed runs (plan §6.4 judges the pace on them): 32.9 minutes of human estimate (23.5 raw), per
preset peaceful 34.3, conqueror 35.0, mixed 25.0. A first oath by intimidation or force is a talk, or a gate broken
and a talk (about 2 minutes); one by help or a breach takes 8-13. Only the roaming segment (whose range starts at
0) is inside its range. The bot walks straight from objective to objective: a person reads the map, follows the
compass, explores, opens sealed places and takes side quests, none of which the main path asks for. What exploring
adds was measured once (`p39_explore30`, assisted so that no run stops on the way): visiting 30 % of each oath
region's places before its oath, 21 places discovered against 18 without, took 39.5 minutes against 36.0 for the
same seed walked straight. Only a timed human run can say how long the campaign is.

### The bosses [C]

| Boss | Measured (`p39_report_set`, novice unless named) | Plan §6.4 |
| --- | --- | --- |
| **Harrok the Unbowed** (the Moot's ring, stage 6) | deaths per duel: 5 (the conqueror, who slays him), 2, 3, 2, 1 and the orders' 4 and 1 - median 2; the first tries end at 32-62 % of his health (median 46 %); the mixed experts spare him in 1-2 attempts with at most 1 death; the conqueror experts bring him to 8 % and 19 % at their lowest and die five or six times | 1-3 per boss sequence: **met** |
| **The Troll Matriarch** (the den, stages 4-5) | driven out: at the first attempt in all three runs (stage 4 in the wood-first order, stage 5 for the peaceful novices), no death in the den; slain: one novice in one attempt (seed 1), the other not in six (seed 2: down to 24 %); two experts of three slay her (1 and 2 attempts) | 1-3: the drive-out under the range, the slay of seed 2 over it |
| **The Iron Regiment** (Fort Aldmere's bailey, the crown's breach) | at stage 4 (crown first): six attempts at 65-100 % of the battle's bar, five deaths to the fort's ballistae (76 % of the damage taken in the battle), the Charge never begins. At stage 5 (`p39_i3_ir5`) the Charge began once in five attempts, six deaths | **miss**: the Charge's threshold (below) |
| **The siege of Skarn** (a choice: Ulfra's plea) | at stage 6 (`p39_skarn6`) saved in 60 s with no death, its five engines seized and thrown; at stage 5 (`p39_i3_skarn5`) six deaths and the siege not ended (riders 2, stones 2, a rival giant, a pike brace) | the stage-5 siege is the player's choice; left as it is |

### Deaths by region, boss and cause [C]

`world_deaths` and the runs' `world.deaths_by_region`, the novice's nine runs (34 deaths):

| Where | Deaths | What killed |
| --- | --- | --- |
| The Stonehold | 19 | Harrok 18 (his overhead chop 6, his frenzy 6, the Moot's falling stones in his phase 2 5, his combo 1); a wandering clan scout's axe 1 (on the way to the Standing Stones) |
| The Greywood | 8 | the den 6 (the Matriarch's frenzy 3 and stomp 2, a whelp 1); trolls on the way 2 (the woodcutters' camp, a wandering troll) |
| The Aldmere March | 6 | the Iron Regiment: the fort's ballista bolts 5, the shield wall's brace 1 |
| The Crownmarch | 1 | the raiders' shield wall's brace (the march by force) |

By segment: the first oath 7, the second 8, the Stonehold 19; outside the bosses' fights no novice segment had
more than one death (plan §6.4: at most 2, **met**). The experts' 42 deaths are the peaceful runs' 18 at the
Raiders' Hollow (the raiders' shield brace, archers, mages' slowing bolts and ogre), the conqueror runs' 22 (Harrok
11, the den and its trolls, a few on the way) and the mixed runs' 2 to Harrok.

### Growth: does the giant's size change the fights at stages 4-6? [C]

| Measure (plan §6.4, §5.14) | Target | Measured |
| --- | --- | --- |
| Formations hold or brace while their banner lives (share of their engaged time) | at least 50 % | 85 % (pooled) |
| The giant's locks with a formation engaged that are group or banner locks | at least half | 86 % |
| Engines thrown per run that reaches stage 6 | at least 2 | 4 in each of the 10 runs |
| Lone humans flee or rout (share of their engaged time) | at least 70 % | 3 %; the lone soldiers 0 % of 280 s |

The AI states at stages 4-6 (`world_states`, the novice's runs pooled; "as formation" is the share of the
archetype's engaged time spent in a formation, "as crew" serving an engine, "harass" a rider's or a wolf's
circling, "spread" and "kite" the shooters keeping their range):

| Stage | Archetype | Engaged (s) | Approach | Attack | Recover | Staggered | Hold | Reposition | Flee | as formation | as crew | other behaviour |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4 | soldier | 10,517 | 1 % | 0 % | 0 % | 4 % | 86 % | 0 % | 8 % | 85 % | 13 % | - |
| 4 | archer | 3,023 | 71 % | 9 % | 5 % | 1 % | - | - | 5 % | - | - | spread 99 % |
| 4 | mage | 315 | 44 % | 22 % | 13 % | 4 % | - | - | 13 % | - | - | kite 100 % |
| 4 | troll | 185 | 34 % | 43 % | 15 % | 5 % | - | 2 % | - | - | - | - |
| 4 | ogre | 138 | 22 % | 51 % | 16 % | 10 % | - | - | - | - | - | - |
| 5 | soldier | 1,686 | 0 % | - | - | 7 % | 77 % | - | 16 % | 70 % | 30 % | - |
| 5 | troll | 1,410 | 29 % | 42 % | 14 % | 5 % | - | 9 % | - | - | - | - |
| 5 | cavalry | 249 | 21 % | 52 % | - | 2 % | - | 18 % | 6 % | - | - | harass 100 % |
| 5 | archer | 228 | 43 % | 9 % | 3 % | 10 % | - | - | 32 % | - | - | spread 100 % |
| 6 | soldier | 3,866 | 0 % | 0 % | 0 % | 8 % | 67 % | - | 25 % | 81 % | 19 % | - |
| 6 | rival giant | 1,029 | 18 % | 67 % | 11 % | 4 % | - | - | - | - | - | - |

What the numbers say, stage by stage:

- **Stage 4**: humans fight in formations (85 % of the soldiers' engaged time is in one) and hold or brace (86 %):
  the pike and shield walls meet the giant at its shins, and the giant locks them as one target. Archers and mages
  keep their range and their spread (71 % and 44 % of their time approaching or repositioning to it). Lone soldiers
  do not flee yet: a lone soldier's awe costs 35 of its 70 morale, which leaves it above its flee threshold (the
  lone humans' 3 % is mostly the toll fort's tower archers, who hold their tower by design).
- **Stage 5**: a third of the soldiers' time is crews' (the war camp's and the Moot battery's engines), trolls flank
  (9 % repositioning), riders charge and wheel; archers flee a third of their time.
- **Stage 6**: a quarter of the soldiers' time is flight (25 %) and every run throws four engines - the Moot
  battery's ballistae and catapults seized and thrown at their own lines; the only equals are the clan giants
  (67 % of their time attacking).

### Abilities [C]

The world bot's ability rotation (P39: a slotted ability unused for 20 s is used on the fight's target) uses most
abilities, but Titan Stomp, Rampart Grip and Earthquake were never used when ready in 8-10 runs of 18, Heavy
Footfall in 6, Boulder Hurl in 5 (their windows come while the novice is mid-blow). Among the novice's completed
runs the largest single ability's share of the ability damage is 31-51 % (Crag Hurl, Formation Sweep, Runic Bolt);
plan §6.4 asks every slotted ability to be used once a run and none above 40 %: **miss**, a question about the
bot's policy more than the abilities.

### Discoveries, sealed places, cairns and fast travel [C]

| Measure | Measured |
| --- | --- |
| Places discovered (of the world's 48) | 18-19 in a completed novice run (the shelf's vista, the three shrines it passes, the settlements, the camps, a waystone, the gate and the boss's ring), 10-15 in runs that stop early or play the mixed preset |
| Sealed places opened, cairns read | none: the bot does not seek them (P38's known gap); the journal and the map list them |
| Fast travel | none in the matrix's 18 runs: every far goal of the main path is a first visit, and a death's reload puts the giant beside its fight. The first fast travel of P39's runs was in `p39_skarn6` (from the Standing Stones' shrine to Skarn's waystone, the siege's goal); the waystones and shrines within 50 m of the way are walked into (4-13 lit a run) |
| Map screens | none (the bot reads the world index; a person opens the map: 6 s each in the estimate) |

### The music's intensity [C]

The share of each stage's time in each intensity (`world_music`, the novice's nine runs pooled):

| Stage | Seconds | Explore | Danger | Combat |
| --- | --- | --- | --- | --- |
| 3 (the opening) | 826 | 51 % | 49 % | - |
| 4 | 4,300 | 43 % | 17 % | 39 % |
| 5 | 4,460 | 49 % | 16 % | 35 % |
| 6 | 2,197 | 2 % | 2 % | 96 % |

Stage 6 is the Stonehold's fights - the Moot battery, the Moot's clan giants and Harrok - so its music is combat
almost throughout. **Among only lesser enemies** (stages 4-6, none of them taller than the music's lesser height
ratio of the giant), the music was in combat 42 % of 322 s (target under 25 %: **miss**); the rest danger. §5.14
asks that lone humans no longer raise combat music from stage 4; the intensity rules are P28's mix data
(`docs/BALANCE_LOG.md`, iteration 0).

### Readability

- **Off camera** [C]: the share of the hits the giant takes from attackers outside the camera's view at their
  windup: median 11 % over the 18 runs (the novice 13 %, at most 48 % in one run, the expert 11 %), 3,766 hits; 8
  hits landed within 0.45 s of their telegraph. Target under 20 %: **met**. In the Valley (`p39_iter0_valley`):
  19 %.
- **The audio caveat.** The threat cues (the far threat stings, the incoming whistles of the engines' shots, the
  siege and formation calls) are proven present for every threat and placed in the direction of their source by the
  audio suites (`test_threat_cues`, the world audio coverage suites, P21 and P28); **whether people notice and use
  them is NOT RUN** (the listening pass and the usability sessions are the owner's: `docs/USABILITY_SCRIPT.md`).
  The bots do not hear: they read telegraphs and windups.

### Streaming and performance

The plan §6.3 captures, with their commands, are in `docs/PERFORMANCE.md`, "The M9 performance captures (P39)":

| Capture | What it shows | Budget |
| --- | --- | --- |
| **The world walk** through every region at stage 6, carried at 16 m/s (a 5,555 m tour: the Kingsgate shelf, Brannock's green, a border walk, the Drowned Steps, the Greywood and Hollowmere, Aldmere's fort gate and the Ironway, Skarn and Harrok's Hall) | streaming work p50 0.63 / p99 7.50 / max 17.72 ms (the max a text props part's parse); 62 loads, 56 unloads, 0 thrash, the least margin 250.3 m, at most 16 chunks loaded; CPU per tick p50 2.57 / p95 5.32 / max 19.3 ms; path queries per tick p95 1, max 4; nodes 2,886-3,599; static memory 259-280 MB | streaming 4 ms a frame (p99 met, the max not), margin 200 m met, thrash 0 met, CPU 8 ms met |
| **The unreachable chase** (P24b's slow test: 20 soldiers chasing a giant in deep water) | CPU per tick p95 4.31 / 4.57 / 4.73 ms over three runs; at most 8 re-paths a tick | 8 ms: met |
| **The formation stress** (40 members at tier 0 and, since P39, two crewed siege engines shooting) | CPU per tick p95 4.21 ms headless; rendered, draw calls p50 63, max 100 | 8 ms, 250 draw calls: met |
| **The bot batches** by region | see `docs/PERFORMANCE.md` (the novice's nine runs, `p39_rep_world`) | p95 8 ms |

In the balance matrices, which ran two at a time beside the other lane's checks, CPU per tick p95 read 5.9-21 ms
and the worst streaming work frame 15.6-63.5 ms (`world_streaming`); the loaded margin stayed at 253-255 m with no
thrash in every run. The web (headless Chromium with software WebGL) is lane P39f's `world_check.mjs` and
`stream_check.mjs --world --audio` (`docs/systems/P39f.md`); real browsers and GPUs are NOT RUN.

### Stability (plan §6.2)

| Run | Result |
| --- | --- |
| **The world, 60 minutes** (`--preset=world_stability`: the assisted novice, `--bot-loop` through the presets from `--mode=world --new-game`, 3,600 s; `p39_world_stability3`) | **passed**: two campaigns completed back to back (peaceful in 1,591 s, conqueror in 1,280 s, no death), the third under way; exit 0; no breach, no `world_blocked`, no duplicated reward, no invariant failure (the lock and targeting invariant included); 3 loads at the Kingsgate shelf, 1,116 / 1,123 / 1,123 nodes (0.6 %), 0 orphans; 0 errors, 0 warnings; 8 stuck moments, all recovered, no teleport; CPU per tick p95 7.77 ms; 2,439 s of wall |
| **The Valley, 30 minutes** (`--preset=stability`; `p39_valley_stability`) | **passed**: three slices completed (help_cache 507 s, help_ogre 473 s, intimidate 490 s); 4 loads, 1,552 / 1,559 / 1,559 / 1,552 nodes (0.5 %); 0 errors, 0 warnings, no death; CPU per tick p95 5.18 ms |
| **The campaign's hand-over** (`w.campaign:novice:1:assist`: the Valley's New Game, the Kings' Door, the world; `p39_campaign`) | **passed**: the Valley in 503 s, the march sworn at 612 s, the Stone Throne at 2,016 s; 0 errors, 0 warnings, no death; its two loads are two levels (the Valley 1,552 nodes, the world 1,118) |

Godot prints its exit report of leaked resources after each full campaign's result (static caches holding their
scenes at quit): it comes after the run's own error count and is lane P39f's recorded item.

## The Valley (the prologue)

The Valley's report of P17b and the M6 gate, re-run on the M9 code: the 24-run matrix `p39_iter0_valley` [C]
(novice and expert x `help_cache`, `help_ogre`, `intimidate`, `force` x seeds 1-3, unassisted, two at a time). No
change of P39's three iterations acts in the Valley (the data is the world's bosses, engines and the Matriarch;
every bot change acts from stage 4 or in the world), which `p39_i3_valley` confirms: the expert's force run on
seed 2 replayed iteration 0's to the tick (933.33 s, 32 kills, the same flags hash).

### Per policy and skill [C]

| Skill | Policy | Completed | Human est. median (min) | Raw median (min) | Deaths median (boss) |
| --- | --- | --- | --- | --- | --- |
| novice | force | 3 / 3 | 14.9 | 11.0 | 0 (0) |
| novice | help_cache | 3 / 3 | 15.0 | 9.8 | 0 (0) |
| novice | help_ogre | 3 / 3 | 14.0 | 9.0 | 0 (0) |
| novice | intimidate | 3 / 3 | 12.6 | 8.4 | 0 (0) |
| expert | force | 2 / 3 | 18.1 | 14.7 | 0 (0) |
| expert | help_cache | 3 / 3 | 18.8 | 13.9 | 0 (0) |
| expert | help_ogre | 3 / 3 | 17.2 | 12.3 | 0 (0) |
| expert | intimidate | 3 / 3 | 16.4 | 12.3 | 0 (0) |

The expert's force run on seed 2 ran out the Deadfall stage's 240 s on the way back from Kingsfall with no death
(206 s of the stage went to the ruins' patrol and gate guards; traced in `p39_valley_trace`): a slow expert fight,
not a blocked path.

### The segments against the plan's pacing (M2-M5 §4.9) [C]

| Segment | Target (range), min | Novice human est. median, min | Raw median, min | Damage / max health, median (estimate) | Deaths (all novice runs) |
| --- | --- | --- | --- | --- | --- |
| Hollow | 3.0 (2-4) | 1.5 | 0.5 | 0.01 | 0 |
| Forest | 5.5 (4-7) | 2.6 | 2.1 | 1.23 | 0 |
| Grove | 2.0 (1.5-2.5) | 0.7 | 0.2 | 0.00 | 0 |
| Village | 4.0 (1.5-7) | 2.0 | 1.2 | 0.32 | 0 |
| Ruins | 4.0 (3-5) | 2.7 | 2.3 | 1.00 | 5 |
| Boss | 4.0 (2.5-6) | 1.3 | 0.9 | 0.96 | 0 |
| Return | 3.5 (2.5-4.5) | 2.7 | 1.9 | 0.41 | 0 |

The bot plays the slice in about 9 minutes of simulated time and 14 minutes of human estimate (the novice's
median), against the plan's 20-30; the shortfall is where a first-time player spends time the estimate does not
count: the Hollow's tutorial, the forest (learning to guard, parry and grab), the Grove (the growth, the first
boulder, the view).

### Novice versus expert [C]

| Measure (median per run) | Novice | Expert |
| --- | --- | --- |
| Completed | 12 / 12 | 11 / 12 |
| Deaths | 0 | 0 |
| Human estimate (min, completed runs) | 14.2 | 17.2 |
| Raw simulated time (min, completed runs) | 9.1 | 12.7 |
| Damage taken | 2,736 | 1,778 |
| Parries / blocks / dodges | 4 / 30 / 3 | 87 / 126 / 41 |
| Light attacks / heavies / throws | 140 / 8 / 12 | 121 / 4 / 23 |
| Ogre King time-to-kill (s) | 39 | 60 |
| Soldier time-to-kill, stage 1 / stage 2 (s) | 25 / 12 | 36 / 33 |
| Hits from attackers off camera (share of the hits taken) | 0.19 | 0.21 |

Skill shows in defence, not speed: the expert parries about twenty times as often and takes a third less damage,
but it spends its stamina guarding, so its fights and runs are longer.

### Deaths, readability and getting stuck [C]

- **Deaths**: the novice's five, all in the ruins' courtyard (the soldiers' brace 2, an archer's shot 2, a mage's
  slowing bolt 1); the expert's none. The courtyard (a formation that braces, a terrace archer out of reach, a mage)
  is where a person should be watched first.
- **The Ogre King**: no novice died there (the plan expects one retry from a first-time player; a person plays
  less evenly than the bot).
- **Off camera**: 19 % of the hits taken (median; at most 29 % in a run), the plan's target under 20 %: met by a
  hair; none landed within 0.45 s of its telegraph.
- **Stuck moments** (no progress for 6 s): 26 in the 24 runs, all recovered by a side-step and jump or a replan, one
  teleport (`force_expert_3`); the busiest cells are the ruins' armory (170, -90), the Deadfall's road west of the
  village (110, -30) and the junction on the way into Thornwick (10, -90).

### Growth in the Valley [C]

| Measure | Target | Median (novice) | Range |
| --- | --- | --- | --- |
| Soldiers in HOLD, stage 1 (share of engaged time) | 0 | 0.00 | 0.00-0.00 |
| Soldiers in HOLD, stage 2 | at least 0.5 | 0.56 | 0.50-0.69 |
| Soldiers in FLEE or ROUTED, stage 3 | at least 0.5 | **0.38** | 0.11-0.61 |
| Soldier time-to-kill, stage 2 / stage 1 | at most 0.6 | 0.51 | 0.34-1.67 |

The same soldiers advance and trade blows at stage 1, hold formation and brace at stage 2, and break at stage 3 -
but at stage 3 they fled 38 % of their engaged time in the median run (the M6 gate's 52 %, P22's 40 %): a run's
share spreads 11-61 %, so a 12-run median moves by more than the target's margin between batches. The
confirmation phase measures it again on the merged code (the fixes lane changed the raiders' rout).

### Abilities in the Valley [C]

Every ability is used in every novice run but Sweeping Blow (2 of 12: the bot tries Heavy Footfall first for a
crowd) and Titan Surge (10 of 12); the largest single share of ability damage per run is Heavy Footfall's, Boulder
Hurl's or Runic Bolt's, 28-46 % (target at most 40 %: four runs over).

### Performance in the Valley

CPU per tick p95 median 5.47 ms, at most 5.93 ms in the 24 runs (budget 8 ms); at most 12 active enemies. The
Valley's draw calls: the rendered Valley walk at `low` is at p50 93, p95 143, max 154 (P27; `docs/PERFORMANCE.md`).

## What changed in tuning, and why

### M9 (P39): the world's bosses and engines (`docs/BALANCE_LOG.md`, iterations 1-3)

| What | Before -> after | Why (the runs before) |
| --- | --- | --- |
| Harrok's overhead chop (power) | 120 -> 95 -> 75 | the killing blow in 28 of the novice's 39 deaths to Harrok; 63-77 % of the damage he dealt the novice |
| Harrok's health | 5,000 -> 4,300 -> 3,400 | the novice's tries ended at about 40 % of his health, where he yields at 25 % |
| The Troll Matriarch's regeneration (phase 1 / phase 2) | 25 / 40 -> 15 / 25 -> 12 / 15 hp/s | it matched what the giant deals (the M8 gate's F37); the slay held at 33-49 % in her phase 2 |
| The Matriarch's phase-2 call | 3 -> 2 whelps | 11 of 12 conqueror-novice tries died in her phase 2 |
| The ballista bolt (power; its poise stays) | 90 -> 60 | five deaths in a row on the Ballista Ridge; the ballistae 68-77 % of the Iron Regiment's damage |
| The catapult stone (power) | 110 -> 85 | the siege of Skarn at stage 5 |
| The bot (measurement only) | `docs/systems/P38.md`, "P39 (W23)" | the expert's answers from stage 4, the ability rotation, siege disruption, the Matriarch's brazier lure, shots only along a clear line |

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

- **The Iron Regiment at stage 4** (the crown's oath first): the Wall's fall leaves the battle's bar at 62 % of the
  desktop aggregate (about 67 % of the web's), above the Charge's 60 %, and from the bailey nothing the giant throws
  harms the fort's ballistae or the wall's crews, so the Charge never comes and the ballistae kill the giant. The
  threshold is a layout number (`tools/data/world/aldmere.json`, the arena's phase `below`): about 0.70, set with
  the merge's world rebuild and checked by the crown order's run (the confirmation phase).
- **Lone humans do not flee a stage-4 giant** (3 % of their engaged time; §5.14: "single humans flee on sight"): a
  lone soldier's awe (35 of 70 morale) leaves it above its flee threshold. The lever is the awe's morale loss for
  the world's soldiers (46 or more), measured on the merged code.
- **The conqueror's slays are hard**: one novice of two slays the Matriarch (the den without its last brazier),
  no expert slays Harrok after his yield. By design the harder path; measured as it is.
- **The peaceful experts die at the Raiders' Hollow** (six deaths each, iterations 1-3; the novice crosses it):
  the expert's world rules, a bot question for the confirmation phase.
- **Pace**: the main path played straight is about 33 minutes against 75-140 (above): a person's time is the
  measure.
- **The music among lesser enemies** is in combat 42 % of the time (target under 25 %): P28's mix data.
- **Abilities**: three of the stage-4-6 abilities sit unused in about half the runs; one ability takes over 40 % of
  the ability damage in most runs (the bot's policy).
- **The worst streaming work frame** is a large props part's text parse (17.7 ms headless; exports ship binary
  scenes, about a tenth of the time: `docs/systems/P39f.md`).
- **The Valley's stage-3 flee share** read 38 % in iteration 0's matrix (target 50 %, the M6 gate's 52 %): measured
  again on the merged code.
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
3. **A formation** (2-3 min): the King's Road south-east to Brannock and the toll fort beyond: a pike wall braces at
   the giant's legs, and locking it takes the whole formation as one target; break its banner and it routs. The fort's
   tower archers shoot from above - a Crag Hurl or a boulder reaches them.
4. **Stage 6 and an engine** (2 min): F6 twice, then east to the Ballista Ridge (about 900 m: a minute at a sprint);
   strike a ballista until it staggers, seize it and throw it at its own line.
5. **Fast travel** (1 min): the map, a waystone you touched (the Kingsgate shelf's), Travel.

**The full campaign** (New Game from the title; about 15 minutes for the Valley and 30-40 for the world's main path
by the bot's estimate, much more for a person who explores): the Valley's crown, the Kings' Door, the Kingsgate
shelf, two of the three oaths (the march's toll and raiders, the Greywood's Matriarch, Aldmere's Iron Regiment or
its war camp), stage 5 and the Drowned Steps, stage 6 at the Standing Stones, the Giant's Stair or the Ironway to the
Moot, Harrok's duel, the Stone Throne.

Things to watch, from where the bots struggled: Harrok's overhead chop (unblockable, a long line: dodge sideways,
not back) and the Moot's falling stones in his second phase; the Matriarch's regeneration (fight her beside a
brazier: its fire stops it); the Iron Regiment's ballistae when the crown comes first; the Raiders' Hollow's
archers and mages; the den's whelps.

**The 5-minute combat tour** (New Game, the Valley's Hollow): the dummies and the sparring post teach the light
chain, the heavy, Heavy Footfall, the block, the parry and the dodge; the forest's first wolves and hunters follow;
F6 shows stage 2's formations and stage 3's awe on what is left of them.

## What a human playtest should look for

- **The world's first minutes**: does the shelf's view say where to go; do players find the beacon, the shrine, the
  map and the compass without the bot's index?
- **Formations at stage 4**: do players lock the group, see the brace, find the banner?
- **Harrok**: does the chop read (a long line, unblockable); is the duel fair at a median of two deaths for the bot?
- **The Matriarch**: do players find the braziers' fire without being told?
- **The Iron Regiment** (after the threshold is set): is the bailey a fair fight at stage 4?
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

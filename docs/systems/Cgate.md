# Cgate - Milestone C's gate: what was broken, what was fixed, what is left

The gate reviewed milestone C (C1, C1b, C2, C3, C3b, C4 merged on the released `0.15.0-m15`, `bb73c37`; the diff
`git diff bb73c37..cdf6d0e`) on `pkg/cgate` from the C4 merge (`cdf6d0e`), as the last check before the owner's
checkpoint. The version is **0.16.0-m16**, finished here; the save stays **schema 3**. Every suspicion was run before it
was called a finding - the real open world in the gate tier (deterministic streaming), the real game under Xvfb with the
compatibility renderer, the desktop build's world walk on the Web check's own fixture and route - and every fix has a test
that fails before it. The decisions are in `docs/DECISIONS.md` §3.11; what is left is in `docs/plans/FOLLOWUPS.md`, "From
the milestone C gate". Evidence outside the repository (stills, logs) is in the hand-back's folder.

## Findings

| # | Severity | Finding | How confirmed | Fix | Test |
| --- | --- | --- | --- | --- | --- |
| G1 | major (progression) | **Three raids lost or given up closed tier 3 for good.** The raid ran at most three times (`max_runs`); the beacon's deed read the event's *last* outcome (`event_done` "defended"), so three raids that fell - or a defended raid followed by one that fell - left the beacon, the Colossus Anvil and the Frostbound lead unreachable. | `can_start_with` on three lost runs: `max_runs`; the beacon's status with "defended" then "fell": not met. | The raid comes again until it is beaten back once (no `max_runs`; a condition: not yet defended, or fewer than three runs); the deed reads the sticky `world.last_hearth.raid_defended` (an outcome's `set_flags`, first write wins). | `tests/unit/test_cgate_progress.gd` |
| G2 | major | **The raid never came.** Its raiders' patrol points are the protect targets' places, and the targets (the Hearth's folk) are a fixed encounter's people the world index does not hold: no points, so the raiders stood where they were made, 90 m east, beyond their 40 m sight - and beyond the AI LOD's 90 m, frozen - while the folk ran into their shelter (hidden, out of reach). The protect objective could not be lost; the giant had to walk out to them. | The gate's raid harness (below): idle giant at tier 1, 300 s, the raiders on their spawn points, 0 folk lost; a trace of every raider's brain. | A fixed encounter's spawn gives the point (`WanderDirector.fixed_spawn_position`); a running event's raiders keep AI tier 1 wherever the giant stands; the raid's commander no longer holds the men in a formation at the spawn; the Hearth's folk huddle at their safe place in the open while it runs (`"folk_hide": false`, `Civilian.stays_in_open`) and go in when it ends. | `tests/gate/test_cgate_raid.gd` (idle at tier 1: the Hearth falls) |
| G3 | major (balance) | **The garrison's arrows decided the raid; the giant had little to do.** Measured after G2's fix with C4's garrison: the archers alone defended tiers 2 and 3 (8 of 8 kills, the rimkin included); with the giant fighting they made 6-8 of the 8 kills. At tier 1 a stage-6 giant died in every run (novice and expert): the raid's rimkin was a full rimkin, "a stage-6 giant's even fight", with seven men round him. | The raid harness, three seeds, tiers 1-3, the giant fighting and idle. | Arrows can miss (range, a man on the move; a hash of the tick, the post and the target - no random stream); bows never loose at a giant-kin (the great bow prefers him); bows power 20 every 3 s to 60 m, the great bow 160; the raid's rimkin is a warleader (`enemy.rimkin_warleader`: 2,400 health, `weapon.rimkin_raid_axe` at 0.6). Numbers below. | `tests/gate/test_cgate_raid.gd` |
| G4 | minor (look) | **Black blots at the fires.** The smoke's puffs (Last Hearth's fires, every smithy's chimney) drew as one black, opaque blot at the fire in the compatibility renderer - the Web's and the desktop's `opengl3`, not only the capture: a probe scene drawing every frame shows it after 3 s and after 12 s. Billboarded CPU particles without `billboard_keep_scale` drew their youngest puffs black. | The probe scene (five variants: preprocess, the scale curve, the ramp, local coordinates, the amount: all black; with keep_scale: none). | `billboard_keep_scale` on the smoke's material (the column thin at its fire, spreading as it rises), a softer, rounder puff. | `tests/unit/test_cgate_look.gd`; `test_c1b_look` changed (the quad's width) |
| G5 | minor | **E with a load in both arms grabbed a staggered man in reach** (PlayerGrab took E before the interact candidates): the haul's own E - set the load down - was lost. | `tests/integration/test_cgate_haul.gd` fails before. | While he carries, the grab leaves E to the load. | same |
| G6 | minor (test health) | **The Web visit to Last Hearth: two stuck teleports.** Reproduced on the desktop build (the same fixture and route: three): a scenery rock on the straight leg along the Hearth path, a garrison archer on his firing step across the leg through the ring's curtain, and the raid's warleader (the fixture had one of the raid's runs spent, so a raid came during the visit). Not a game defect: the walk's straight legs. | `WORLD_WALK_STUCK` lines (new: where, the waypoint, what the giant ran against). | The route round the rock and in and out by the gate; the fixture's raid runs spent. Desktop: 726 m, 0 stuck. | `tools/web/world_check_c4.json` (the Web check) |
| G7 | minor (tooling) | The capture tour's Last Hearth work stopped at its travel once the raid came for real (G2): "Not while enemies are close". | The tour. | The tour holds the raid's cooldown; it starts the raid itself where it films it. | the tour |

### The draw calls at Last Hearth's tier 3 (C4's open item)

The Web visit's peak, 121 draw calls, is the people, not the settlement. The capture tour now records each shot's draw
calls and, with `--tour-draws`, what each kind of thing costs (drawn again with it hidden). At `low`, desktop `opengl3`,
Last Hearth's far view: tier 1 **88** (people 54, flagged settlement meshes 3, particles 4, lights 0), tier 2 **86**
(people 49, flagged 6, particles 5), tier 3 **97** (people 53); the static world's own 28 at tier 3 (`test_world_build`).
Twelve skinned people at `low` (P64's cap) cost about four draws each; the Web visit's 121 also had a raid in it (the
fixture's spent run, G6). No merge or batch reaches that cheaply: the settlement's meshes, fires and lights are 8-12 of
it. Fewer skinned folk at the camp (a camera-distance rule at `low`) would; it changes the people's tiers everywhere and
is left (FOLLOWUPS).

### Suspicions run and rejected

| Suspicion | What was run | Result |
| --- | --- | --- |
| Hauling soft-locks: a load lost or kept across a death, a travel, a checkpoint, a growth | Read with the code paths: `PlayerHaul.post_movement` (dead, grabbed, staggered), `on_exit` (every travel reloads the scene), a load never saved; the gate walk and the haul walk below | Put back each time; nothing kept or lost |
| The raid interrupted by a death or a quit | Read: `WorldEvent` resets the attempt on a death; F19 resumes a saved run | No soft-lock; with G1 a lost or abandoned raid comes again |
| A 0.14 or 0.15 save cannot continue, or loses its settlements | `test_c4_settlement` (the 0.14, 0.15 and C4 fixtures), `test_save_schema3_play`, the gate walk's document | Load and continue; schema 3 |
| An older save with the raid defended loses the beacon's deed after G1 | The outcome "defended" has always set `world.last_hearth.raid_defended` | Kept |
| Stage 4-8 unreachable | The gate and slow route walks (`test_bot_route`, `test_stage_reach_bands`, `test_growth_route_456`), C1's colossi suites, the haul walk to tier 3 | Every step reached |
| The settlement panel and tab at 1280 x 720 | C4's tour stills of the panel, its tabs and the Character menu's tab, again here | They fit; keyboard and pad hints as the other screens |

## The raid (decided by the giant)

`tests/gate/test_cgate_raid.gd` (`RaidFight`: the bots' own fighting, BotCombat's novice, going for the raider nearest the
folk, else the nearest to him; `-- --raid-matrix=3` for the seeds). Stage 6, the giant not invulnerable; "idle": he stands
60 m west of the bonfire behind the hall, invulnerable, near enough that the folk and the raiders stay in play.

| Tier | Before (C4's raid with G2 fixed, C4's garrison) | After: the giant fighting (seeds 1-3) | After: idle |
| --- | --- | --- | --- |
| 1 | the giant dead in all three (novice 47.5-69.8 s, expert 86-106 s), the rimkin 1,300-1,600 of his 1,525 health | **defended 3 of 3** in 57.7 / 64.4 / 58.7 s, lowest health 29 / 49 / 33 %, 0 folk lost; expert 3 of 3 (24-64 %) at the 0.75 axe | **fell 3 of 3** (102.8 s) |
| 2 | defended by the archers alone (8 of 8 kills, 86 s); fighting, the archers 6 of the 8 | **defended 3 of 3** in 57.1 / 61.9 / 63.1 s, lowest 19 / 5 / 42 %; kills the giant 6 / 6 / 6, the garrison 1 / 1 / 1 | no outcome in 300 s twice (the archers drop the men; the warleader, beyond their bows, holds the giant), fell once |
| 3 | defended by the garrison alone (8 of 8, 37 s); fighting, the garrison 7-8 | **defended 3 of 3** in 53.1 / 53.4 / 52.9 s, lowest 43 / 12 / 42 %; kills 4 / 2 / 3 against 3 / 5 / 4; the suite's run: the giant 62 % of the raiders' wounds | no outcome in 300 s (the great bow does not finish the warleader) |

The men break and run from a stage-6 giant who comes at them (P30's rout: a routed raider counts as beaten), so the giant's
kills are fewer than the men he ends. Bot measures only: no person has fought it.

## The hauling (tier 1 -> 3 walked)

`tests/gate/test_cgate_haul_walk.gd`: from the Last Hearth waystone at stage 6 a scripted player walks every leg (the world
bot's route planner, the stick through the input router, sprint held, the carry's 0.7 pace), takes each load up at its pile,
sets it down at its site, walks to the rockfall, the crags and the pilgrims' track (their fights ended at once) and raises
each work. 0 stuck legs.

| Loaded leg | Stage 6 sprint | Stage 6 walk | Stage 7 sprint |
| --- | --- | --- | --- |
| a great timber, the Windfall -> the hall (twice) | 12.4 / 14.3 s (98 m) | 17.3 / 17.3 s | 12.1 / 13.5 s |
| a king-stone, the pier -> the ring's gate (three) | 27.1-27.6 s (186-190 m) | 33.7-33.8 s | 26.0-26.6 s |
| a king-stone -> the forge | 33.4 s (231 m) | 41.7 s | 32.0 s |
| a king-stone -> the beacon; a timber -> the beacon | 30.7 s; 16.9 s | 38.4 s; 20.3 s | 29.1 s; 15.3 s |
| a king-stone -> the anvil | 24.0 s | 29.5 s | 23.3 s |
| **all nine loads carried** | **214 s** | 266 s | 204 s |
| **tier 1 / 2 / 3, every walk and raising** | 76 / 248 / 138 s | 109 / 307 / 170 s | 74 / 243 / 130 s |

No loaded leg is over a minute at the stage that does it (the worst 33 s sprinting, 42 s walking): nothing was trimmed.
C4's "about six minutes of carrying" was an estimate; the measured carrying is 3.6 minutes sprinting, 4.4 walking, and
the whole loop's walking about 7.7 minutes plus its fights.

## The look pass

Stills from a giant's eye and close, before (C4's final tour) and after, in the hand-back's folder
(`after_hearth_tiers`, `after_hearth_work`).

- **Works rise as they are raised**: a project's work rises out of the ground and settles under a burst of dust (1.3 s)
  as the giant raises it; a load he sets down settles into its stack (`FlagVisibility.rise_m`; at a load it is simply
  there). **A crumbling tower comes down**: it leans away from the blow and sinks into its own dust while its heap rises
  (1.6 s) instead of a swap; its courses weathered greys with a broken crown and quoins.
- **The carried load weighs**: it rides lower, the hands on it (the pose brain reads the haul's socket), dipping and
  rolling with each stride.
- **Last Hearth**: dry-stone courses of flat-bedded stones of varied length with staggered joints, the hall's turf roof
  in bands of turves, huts under low turf domes, banners hanging in folds, snow drifts against the hall's back wall,
  the huts and the ring; the smoke soft and pale. The world's data 4.98 MB of 5.0.

## What still falls short of the owner's bar (bluntly)

- **It is still a low-poly world.** Up close the hall's courses are grey boxes (the worked-block shape tripled the world's
  data), the turf roof a patchwork of flat turves, the domes smooth, the drifts white mounds; the Bastion's keep walls
  are still the Old Kingdom's pale stone boxes (only the towers changed). From a giant's eye it reads as a place; close
  it does not read as real.
- **Nothing is built by hand.** The rise is a work coming up out of the ground under dust, not a giant setting a
  roof-tree into crucks; the folk do not build; the giant has no lift, set-down or levering motion - only the load's
  dip and roll and his hands on it.
- **The ring is not solid.** A giant walks through the curtain he raised (as do the raiders; their navmesh is the
  camp's), and a stage-6 giant is stopped by a garrison archer standing on his step. A man on a wall stopping a 62-foot
  giant is clunky.
- **The raid is a bot's fight, tuned on three seeds of one bot.** At tier 2 the novice's worst run ended at 5 % health;
  the idle runs at tiers 2 and 3 end with no outcome (the warleader alive, holding nobody) rather than a loss. The raid
  starts as soon as the roof is raised (its first run has no cooldown), in the middle of the giant's work there.
- **The draw calls at the camp** stay near 100 at `low` (the skinned folk); the Web's peak with a raid was 121.
- **The smoke, the drifts and the domes were judged on software-rendered stills only.** No GPU, no person.
- **Human playtest not run.** The raid's feel, the haul's pace (now measured, not felt), the rise and the collapse.

## Tests

| Suite | Tier | What |
| --- | --- | --- |
| `tests/unit/test_cgate_progress.gd` | default | G1 |
| `tests/unit/test_cgate_look.gd` | default | G4 |
| `tests/integration/test_cgate_haul.gd` | default | G5; a raised work rises in play and is simply there at a load |
| `tests/gate/test_cgate_raid.gd` (`tests/support/raid_fight.gd`) | gate | G2, G3: tier 1 idle falls, fighting holds with no folk lost and the giant alive; tier 3 idle the garrison alone does not end it; fighting holds, the giant most of the wounds, the garrison's arrows miss |
| `tests/gate/test_cgate_haul_walk.gd` | gate | the tier 1 -> 3 loop walked, no leg stuck, no loaded leg over 60 s at stage 6 |
| changed | - | `test_c1b_look` (the smoke's quad and its kept scale) |

## Verification

Filled in by the final check (below).

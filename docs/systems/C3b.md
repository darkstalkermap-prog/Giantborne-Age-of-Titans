# C3b — Playability follow-up: what stands at a giant's feet, a giant that moves with weight, landmarks at every size

The follow-up of C3 on `pkg/c3b` from C3's merge (`8c42bbf`). The version stays **0.16.0-m16** and the save stays
schema 3. The owner's request (C3's) asked for a giant who can aim his blows, moves fluidly, finds the forges and the
waystones at once and hears his swings; C3 left real gaps against it (C3's "What is weak"). Decisions C3b-1..C3b-7 are
in `docs/DECISIONS.md` §2.7; what is left is FOLLOWUPS "From C3b".

| Gap C3 left | The root cause | What changed |
| --- | --- | --- |
| At stages 6-8 a swing passes over a man or a fence at the feet; the indicator says "Out of reach" | The weapon is a straight segment from a shoulder 15-23 m up; at stages 7-8 every weapon is carried past its fit (the oak club of C3's test is a stage-2 twig there); the arcs cannot come down to the toes | **The low strike** (§1): the press stamps (a light) or stomps (a heavy) on what the swing would pass over |
| The camera stops at -70 degrees | `CameraRig.TP_PITCH_MIN` | -84, the view coming in over the head (§1) |
| A big giant's feet slide; starts and stops have no weight | The walk's weight over the stance was the normalized speed (a stage-8 giant at half speed walked half a stride, his body at full speed: the planted foot slid at 2-4 m/s); the gait's phase covered 1.6 m a half stride whatever the clips' step | **Planted feet, leans, follow-through, combo links, hit-stop** (§2) |
| A smithy is shin-high and a waystone knee-high at stage 8; an unreached waystone is invisible past 240 m; the label overlaps the banner; dark smoke; no solids | The landmarks drew to 240 m (the static world's 40 draw calls); the marker drew its words wherever its place projected; the world's smoke puff | **Unlit columns, far marks, a layout, soft smoke, solids** (§3) |
| `world_check` failed on music holes the main thread "did not explain" (C2 2 of 3, C3 6) | **A measurement artefact of software rendering** (§4): the page's frames run 350-800 ms, the frame's mixing lands in parts and a hole can end with no read handled | The check places such a hole inside its long page frame |
| Near sounds play centred | C3's near voices were 2D players (a 3D player was panned a frame late on the Web) | **Panned near voices** started inside a physics frame (§5) |

## 1. What stands at a giant's feet (decisions C3b-1, C3b-2)

**The low strike.** `PlayerAttack.swing_plan` plans the swing as before; when what it aims at (the lock, the cursor, the
soft target) is a body whose top stands at most half the giant's height (a man, a wolf, a fence - never a titan or a
house) and the swing does not strike it - or, from stage 5 (14 m), one at most 0.14 of his height within 0.45 of his
height of his middle, which the swing would strike as the weapon chopping the ground beside his toes - it plans a
**stamp** (`ability.low_stamp`, for a light) or a **stomp** (`ability.low_stomp`, for a heavy) instead, and if that
strikes the target the plan is the low strike's (`plan.variant`, `plan.strike` "stamp" / "stomp"). The hit shape
`foot_stamp`: the near foot comes down where the target stands (brought within 0.12-0.42 of his height from his
middle along the bearing to it), and on the first active tick a vertical cylinder there strikes (radius 0.10 / 0.15 x
his height, at least 0.45 / 0.6 m; 0.12 / 0.14 x his height tall, at least 1.2 / 1.4 m; an area effect, so a
villager beside the foot is spared), with the stomp's sound and ring (`area_pulse`), its hit-stop and camera kick
(§2). The plan sweeps it as the runner will (`predicted_stamp`: the same query, HitFactory's order and filters), so
the aim indicator shows exactly what the foot strikes: "Stamp" or "Stomp" under the target and a dotted ring on the
ground where the foot lands. `CombatController.variant_resolver` starts the low strike in the light's or heavy's
place (the same plan that tick); the light chain goes on from the light it stood in for. The facing turns to the
target through the windup as a swing's does. The bots keep their swings (`bot_controls` clears the resolver).

| | stamp (light) | stomp (heavy) |
| --- | --- | --- |
| timing (windup / active / recovery) | 0.25 / 0.1 / 0.35 s (the light's 0.2 / 0.15 / 0.3) | 0.5 / 0.1 / 0.55 s (the heavy's) |
| damage, poise | x1.1, 18 | x1.8, 40 |
| stamina | 8 | 20 |
| knockback | 3 m/s | 6 m/s |

**The pose** (`PoseBrainModifier._stamp_legs`, on the action's clock over the clip's stance, Body space): through the
windup's first 62 % the foot lifts (0.34 / 0.56 of the leg) and swings forward to hang 45 % of the way to the point,
the pelvis rising a little; then it is driven down onto the point, accelerating, the pelvis following (45 % of the
foot's way, at most 0.8 stage-1 metres) and dropping (0.08 / 0.16 m and what the standing leg needs), the spine bent
over it (10 / 16 degrees); it lands as the action's blow begins (the pulse, the hit-stop, the kick), the body sinking
into it; held through the recovery's first 40 %, then back to its place with a small lift. The standing foot stays
where it stands (a two-bone solve of its leg). The arms (`ActorRig.ability_pose` "foot_stamp") go out for balance as
the foot lifts and are thrown down with it. The stamping foot is the near one (the left when the target stands left of
his facing).

**The camera** looks down to -84 degrees (it stopped at -70); past -66 it comes in over the giant's head - the
shoulder offset narrows to 35 % and the pivot moves 0.7 capsule radii ahead - and his head is hidden past 60 % of the
way, so the screen's centre falls past his chest onto the ground before his toes.

**TitanDuel** gives stages 7 and 8 the titanforged club (it gave the oak club, a stage-2 weapon, to a colossus: C3's
test measured a twig).

`tests/gate/test_c3_aim.gd`: C3's 48 cases (a man, a fence, a titan's plate at every stage, light and heavy) now reach
the man and the fence at every stage (16 of 16 each; C3: 12), and a new case set puts **a man, a wolf and a fence at
the giant's feet (his capsule's edge + 1 m) and at half his reach** at every stage 1-8 (the light; the heavy at the
man: 64 swings): **every one struck, by what the indicator named** - the swing at stages 1-4 (a wolf at the feet at
stage 3 stamped), the stamp and the stomp from stage 5 (24 stamps, 8 stomps), every target under the cursor (the
camera reaches them now). `tests/integration/test_c3b_motion.gd`: at stages 6 and 8 the stamping foot lands on the
pulse's centre (0.00 m off; radius 1.89 / 2.93 m) and the man is struck. `tools/c3b_low_film.gd` films a soldier at the
toes, another at half the reach and a fence, aimed and struck (evidence: `final/low_strike/`).

## 2. A giant who moves with weight (decisions C3b-3, C3b-4)

Diagnosed on the skinned giant (the planted foot's slide measured on the rig's final bones, `test_c3b_motion`) and
on film (`tools/c3_motion_film.gd`, before and after side by side at stages 1, 6 and 8):

- **The feet slid.** `SkinnedRig` blended the walk over the stance by the normalized speed (`clampf(n, 0, 1)`): a
  stage-8 giant at half his speed (n 0.57) walked 57 % of the clip's stride while his body moved at full speed - his
  planted foot slid 2-4.5 m/s; at full speed the gait's 1.6 m half stride was ~10 % longer than the clips' step (a 0.5
  m/s slide at stage 1). Now the walk's weight comes in by 0.9 m/s per k (at least 0.35 while he walks), the brain's walk
  phase covers the clips' own step (1.45 m, measured) times that weight - a slower walk takes shorter steps at nearly
  the same cadence - and **a foot the clips set down is held where it landed** (`PoseBrainModifier._lock_feet`: within
  0.03 m of its standing height it locks to its world point, a two-bone solve of the leg holds it until the clips lift
  it past 0.06 m, easing in at 30 / s and out at 12 / s, letting go beyond 0.45 m). Measured (the worst foot, m/s):

| stage | a quarter of his speed | half | all |
| --- | --- | --- | --- |
| 1 (before: 0.10 / 0.29 / 0.50) | 0.02 of 1.25 | 0.04 of 2.50 | 0.00 of 5.00 |
| 4 (before: 1.04 / 0.30 / 0.58) | 0.00 of 1.77 | 0.11 of 3.55 | 0.13 of 7.10 |
| 6 (before: 2.11 / 1.64 / 0.72) | 0.02 of 2.03 | 0.21 of 4.05 | 0.23 of 8.10 |
| 8 (before: 3.58 / 4.46 / 1.48) | 0.00 of 2.28 | 0.00 of 4.55 | 0.19 of 9.10 |

- **Starts, stops and curves had no weight.** The whole body now leans from the ankles into its acceleration
  (`ActorRig._motion_lean`, the giants' rigs: 0.55 x the acceleration in stage-1 metres a second squared over g, at
  most 6 degrees, smoothed over 0.12 s): forward as he sets off, back as he stops, inward on a curve (measured at stage
  4: -5.7 degrees setting off, +5.7 stopping, 0.00 at rest). With the feet planted, a stop settles on the feet it
  stopped on instead of gliding into the stance.
- **Swings had no follow-through and combos restarted from rest.** A blow now carries on past its arc's end along its
  own way (1.1 x the arc's last fifth, peaking at 22 % of the recovery: `AttackGeometry.pose_for`, presentation only -
  the tested arc is the ACTIVE phase's) and the torso's twist with it; a combo's next blow winds up from where the last
  one left the arm (`ActorRig._link_pose`), not from the rest pose.
- **Hits felt light.** A light, a heavy, a stamp or a stomp of the player's that lands **holds where it struck** for a
  hit-stop (`CombatController.hold_ticks`, set by `PlayerAttack._hit_stop` once a swing): 2 ticks at stage 1 to 5 at
  stage 8, a heavy's 1.5 x (3 / 8 ticks: 50 / 133 ms), the swing's arc and the rig paused together; the camera
  **kicks** (`CameraRig.add_kick`: the view dips up to 1.6 degrees and drops, by his size, easing back at 9 / s; the
  comfort setting's camera shake scales it) and the hit's shake is up to 2.2 x at stage 8. The bots' swings never hold
  (the duels were tuned without it).

No new clips were needed: the slide was the gait's bookkeeping, and the lean, the stamp and the follow-through are the
pose brain's (presentation only). The duels' bots keep `bot_controls` (no cursor, no low strike, no hit-stop, the old
turns and buffer): the titans' tables are unchanged (§ The check).

## 3. Landmarks at every size (decision C3b-5)

- **An unreached waystone stands as a grey column.** An open stone not yet reached shows its beam unlit - grey, faint
  (0.32), breathing slowly instead of shimmering (`landmark_beam.gdshader` `unlit`) - from 150 m to 300 m, where the
  stone itself is small; a reached one burns blue to 2.4 km as before. The column's reach is what the static world's
  40 draw calls a view at low allow (at 2.4 km a new game's woodcutters' camp saw four columns; at 600 m, three views
  went to 41-42).
- **The HUD's place marks reach far.** Beyond its near prompt (30 m + 7 x his height), a place is marked out to 600 m +
  40 x his height (1.77 km at stage 8): its icon (grey for an unreached stone), its name and its distance, smaller and
  dimmer, at most four; a sealed stone or a cold forge is not marked from afar (not a place to go to yet). HUD marks
  keep one size on the screen, so they read at every stage.
- **The words never overlap.** Each mark's words are laid out under its icon, moved down past the HUD's top messages
  (the region banner, the ability notice, the toasts: their widgets' `layout_controls`) and past the marks placed
  before it; a far mark that cannot be placed keeps its icon only.
- **Soft smoke.** The smithy's smoke is a soft round puff (a smooth radial falloff), pale (0.80-0.93) and thin (alpha
  0.42 at its foot to 0.16), growing to 1.6 x as it rises, 22 puffs over 16 s, drawn to 900 m.
- **Solids.** The monument's plinth is an eight-sided step (its two slabs, narrowing to the menhir's foot; the menhir is
  the old stone's body); the smithy has its chimney above the old hearth, its back wall, its trough and the lean-to's
  four posts. The Valley's revisit and corridor tests (stages 3-6) and the growth route pass with them; a giant walking
  into the back wall stops at it (`test_c3b_landmarks`).

## 4. The Web's music holes (decision C3b-7)

`world_check.mjs` on this tree's base (C3's build), 1280x720: the page's frames ran **p50 800 ms**, the main thread 99 %
of the time in long tasks; **79 % of the recording was silent** - 598 holes over 50 ms, against 599 gaps in the main
thread's service of the driver longer than the stream's 186 ms buffer: one hole per stall. 585 were placed on the main
thread, **13 were not** (FAILED). The same build at 640x360: frames p50 350 ms, 474 holes, 5 not placed. Every one of
those 18 sits inside a page frame longer than the buffer, beside its read bursts: the worklet's reads queue up through
the frame and are handled in a burst at its end, and the frame's mixing lands in parts - audio plays a while after a
burst, stops, and comes back with no read handled at the moment it comes back, so the placing rule (a hole ends with a
handled read) cannot place it. It is the no-threads Web build mixing on a main thread that SwiftShader starves, not the
game's audio: a hole is silence in the whole output (music and ambience), which no effect voice - the bus change, a
near voice, a stolen voice - can make (they only add to the output); C2 failed the same way before C3's bus change and
near voices. **The fix is the check's**: a hole no read ended that lies (half of it at least) inside a page frame longer
than the stream's buffer is the main thread's too (`placeHoles`'s `holes_in_a_long_frame`); a hole while the frames ran
within the buffer is still listed. Re-placed, both base runs place every hole. `--strict` (a GPU machine's gate) still
fails every hole.

## 5. The near sounds placed (decision C3b-6)

A 3D player is panned in its physics processing; started in a frame's processing (a footfall from the rig, a cue from
a menu) it was panned in the next frame's physics, so on the Web its first 16-40 ms were silent - why C3 played every
sound at the giant on unpanned 2D voices. The near voices are `AudioStreamPlayer3D` again, placed at the source (its
unit distance where it stands: no distance attenuation, the model's level; +1.5 dB toward the stereo pan law, so a
centred sound is within 1.5 dB of C3's), with their physics priority after the simulation's; a near start asked for outside a
physics frame waits for the next one (`VoicePool._deferred`, at most a frame), so the gains are set in the same engine
frame - the same browser task - as the source starts. `sfx_check.mjs` now reads the gains at the end of the starting
task and reports the near voices' stereo balance.

**The mix at stages 4-8.** `sfx_check.mjs` at stages 4, 6 and 8 (the release's sandbox with `--sandbox-stage=N`, new)
found a big giant's swings under his own footfalls: the swing cues' class is a human's, so from stage 6 his shoulder
stood beyond its unit distance from his own camera and the whoosh played as an attenuated far 3D voice (stage 6: the
swings -29.5 dBFS RMS against his steps' -20.8 and the bed's -32.9; 5 of 11 heard over the bed). The player's swing,
its mass layer and the stamp's are now heard by the `player` class (his own size's distances): a near voice at every
stage. The same runs found a blow's stack harsh at stages 4-6 - the stamp's thud, the hit, the cry and the fall, or a
clank, a hit, a crack and a break, starting together - peaking at -0.6 to +0.7 dBFS: near voices starting within 40 ms
of others are lowered 2 dB for each (at most 6), the stamp's thud sits 4 dB under the blow, and the near voices' pan-law
lift is half of 3 dB. Two fixes to the check came with it: a near voice starts a physics frame after its cue line, so on this
machine's 150 ms frames a cue printed later could start its source first - each cue is now matched to a source of
one of its own files' lengths (the banks and the WAV headers); and with the music on, a cue is heard when it stands
the minimum over the bed, not over the quarter second before it, which holds the swing that brought a hit (C3's own
build measured 5 of 14 hits that way on this machine).

## What is weak

- **The stamp is keyed on the stance, not a clip.** The foot's lift and drive, the pelvis and the arms read as a stamp
  at every stage (the films), but there is no anticipation in the shoulders, no look down, and the club hangs where the
  arm's balance pose puts it - across the leg in the light stamp. A clip made for it would read better.
- **The low strike predicts a standing target**, as the swing's indicator does: the pulse comes down where the target
  stood at the press; a running man can leave the ring. Its reach (0.42 of the height from the middle) is a lunge the
  pose fakes by moving the pelvis up to the capsule's edge - at the far end of it the stamping leg is straight.
- **Stages 7-8 swing a weapon past its fit**: what the swing still reaches at mid range at a colossus's size is struck
  by the stage-6 club; tip matching draws it short (C1's forge tier is the remedy). The stamp covers what is at his feet.
- **The landmarks are still one size** (a smithy at a colossus's shin). An unreached stone's grey column draws only
  150-300 m - the static world's 40 draw calls a view at low allow no more (600 m put three views at 41-42); beyond, the
  HUD's far mark carries it. A forge's fire glow that kept its size on the screen was built and dropped for the same
  budget.
- **The motion is the pose brain's.** No start, stop or turn clips: the measured slide was the gait's bookkeeping and is
  gone, the leans and the follow-through are procedural. A 6-degree lean at a stage-1 giant's sharpest reversal is near
  the edge of believable; a stop still blends the swinging leg into the stance (the planted one stays).
- **The hit-stop is the player's only**; enemies' blows do not hold, and the bots never do (their duels).
- **Heard in headless Chromium only**: the near voices pan up to about 6 dB (Godot's 3D panning at the project's
  strength) and their levels were measured, not listened to. A near sound asked for outside a physics frame (a footfall
  from the rig) starts a frame late - 16 ms at 60 frames a second, about 150 ms on this machine's software renderer.
  The mix was set by the measured levels (the whoosh 10-14 dB over the bed, the footfalls 6-12, no peak over -3 dBFS),
  not by ear; at stage 8 the sound check's autopilot landed only 2 blows in 45 s (its minimum is 3).
- **The Web's music still breaks here**: the check now explains every hole of a starved page; the plan's criterion (no
  hole over 50 ms) is met only on a machine whose frames run within the stream's buffer - a GPU's `--strict` run, not
  run.
- **The evidence's quirks**: the world tour's first frames after a New Game's travels draw a stale "Loading..." (two
  stage-3 stills dropped, the Valley's stage-1 stills stand in); the Valley's far views of the ruins gate stone are half
  hidden by its wood.
- **Human playtest not run.**

## Sizes

The real `tools/build_web.sh` (preset Web) on the final code: `index.pck` shipped **53,031,460 bytes, 50.57 MB of 56**
(C3's 52,996,232: +0.04 MB - the two actions, the code, the rebuilt smithy and monument scenes); the giant's share
**14.07 MiB** of 15.0 and the people's and creatures' **16.44 MiB** of 18.0 (both unchanged); audio 9.34 MB of the
pack; the page downloads **65,560,160 bytes** (the engine 12,528,700 + the pack 53,031,460: "About 66 MB", as the
launcher says). The world's registered SFX seconds **174.21 of 175** (no new sound: the stamp and the stomp use the
swing's mass layer and the stomp's impact) and the world's data (no chunk rebuilt) are unchanged.

## The Web

Headless Chromium, software WebGL (SwiftShader: frame times indicative only), `low`, 1280x720, on the package's 4-CPU
machine with nothing else running, on the final build (`docs/PERFORMANCE.md` "C3b" has every figure):

| Run | Result |
| --- | --- |
| `sfx_check.mjs --mute=Music:Ambience` | **OK**: 16 / 16 swings (-24.9 dBFS RMS), 14 / 14 hits (-23.9), 84 / 85 footfalls; the near voices placed (swings 1 left, 12 right, 3 centred; footfalls 11 left, 2 right, 64 centred; at most 6 dB), every one's gains set within its starting task |
| `sfx_check.mjs` (the full mix) at stages 1, 4, 6 | **OK**: the bed -34.3 / -33.5 / -33.3 dBFS; his whoosh 10-14 dB over it, hits 9-17 dB, his footfalls 6 / 10 / 12 dB; no peak over -3.1 dBFS |
| the same at stage 8 | FAILED on its minimum count only (2 blows landed in 45 s; it wants 3), both heard; his whoosh 10.5 and footfalls 10.6 dB over the bed |
| `world_start_check.mjs` | **OK**, renderer peak 1,185 MB, 0 console errors |
| `world_check.mjs` x 3 | **OK, OK, OK** (the audio criterion not met on this machine, every hole placed on the main thread: 603 / 607 / 606, of them 6 / 16 / 9 inside a long page frame - each of those would have failed the check before C3b-7); 787.7 m, 3 region changes, 0 stuck, 0 thrash; streaming work p99 17.1 / 12.6 / 12.1 ms, max 60.4 / 39.2 / 18.1 ms (C3 14.5 / 61.1); **draw calls p50 44 / max 62** (C3 43 / 61: the open stones' grey columns); renderer peak 1,192 / 1,175 / 1,218 MB (C3 1,179); peak live samples 59.5-59.7 MB of 70.1; 0 console errors |

## The check

`nice -n 10 tools/check.sh --build --slow --gate --people --giant --web-tools --require`, run alone on the package's
final code (07:32-08:49 UTC): `RESULT: 430 suites, 90862 checks, 0 failures`; the titans' tier `RESULT: 7 suites, 209
checks, 0 failures` (the bots keep their controls: no cursor, no low strike, no hit-stop - the duels' tables are the
bots', unchanged); `TIMES: default 90.4 s | slow 486.6 s | gate 2552.2 s | titans 928.8 s`; every scene rebuilt with
no diff, `SEAM_CHECK ok: 64 chunks, 112 seams`; `GIANT VERIFY OK` (116 files bit-exact), `PEOPLE VERIFY OK` (83 files);
`TEST_WORLD_CHECK: 21 checks, 0 failures`, `TEST_SFX_CHECK 26 checks, 0 failures`; **CHECK PASSED in 76 min 28 s**. The
seeded soak: **37 attacks** (C3: 40), **32 hits resolved** (34), 4 enemy kills, 2 fence breaks, 7,201 frames, 0
errors, byte-identical with the people on and off - the autopilot plays with a player's controls, so each landed blow
holds for its hit-stop and a light at a body below the swing stamps: fewer swings fit its 120 s.

Two full runs before it: the first failed on three suites, all the body's lean - a held body's arm turned off its
socket (`test_grab_throw`), and a two-handed blade's edge slerping between near-parallel directions every frame lost its
axis's length in single precision (514 "must be normalized" errors on the towns' walk, 80 on Harrok's twin); the lean
now applies only walking or standing free, and a small turn of the edge is a normalized lerp. The second passed (72 min
33 s); the Web runs that followed changed the mix (the giant's own swing heard at his size, a blow's stack tamed) and
`sfx_check`'s matching, so the check was run again on the final code.

## Tests

| Suite | Tier | What |
| --- | --- | --- |
| `tests/gate/test_c3_aim.gd` (extended) | gate | the man and the fence reached at every stage; a man, a wolf and a fence at the feet and at half the reach struck at every stage 1-8 by what the indicator named (64 swings), stamps and stomps among them |
| `tests/integration/test_c3b_motion.gd` | default | the planted foot's slide at stages 1, 4, 6, 8 (a quarter, half, all of his speed) within 5 % of his speed; the stamp's foot on the pulse at stages 6 and 8; the lean setting off and stopping; the follow-through; the hit-stop longer at stage 8 than 1, none for a bot |
| `tests/integration/test_c3b_landmarks.gd` | default | the unlit column and the lit beam; the lit forge's soft smoke, none cold; the solids (a giant stops at the back wall); the marks' words clear of the banner and each other |
| changed | - | `test_c3_audio` (a near voice is 3D, at its place, the pan law), `test_audio_director` (the near voice's type), `test_c3_landmarks` (an open stone's unlit column) |
| `tools/web/test_world_check.mjs`, `test_sfx_check.mjs` | `--web-tools` | a hole inside a long page frame placed, one among quick frames listed; a near voice's balance and the field's summary |

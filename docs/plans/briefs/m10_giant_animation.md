# Brief: animating the realistic giant (M10)

Planning brief for M10 ("the realistic giant in the game, with a character creator"), written
while M9 runs. Scope: how a skinned skeleton replaces the player's stylized rig without changing
gameplay - the current rig and everything that reads it, the chosen design and its in-engine proof,
growth stages, first person, the other giants, determinism, test impact and the CPU cost on the Web
build.

Tags: **VERIFIED (ran)** = I ran it (command, lab or computation on the repository's data);
**VERIFIED (code)** = read in the repository at commit 1c33b8e and
confirmed by grep; **ASSUMED** = reasoning or engine knowledge I did not run;
**RECOMMENDATION** = a design choice for the planner.

Lab material (all scratch, outside the repository; the scratch worktree /tmp/m10-anim was removed):

| What | Path |
|---|---|
| Blender export of the skinned test giant (game rig + computed clips) | `<scratchpad>/m10_plan/anim_lab/export_test_giant.py` |
| The exported test giant (glTF binary, 1.30 MB) | `<scratchpad>/m10_plan/anim_lab/out/test_giant.glb` |
| Godot lab: real player scene + skinned giant + pose-brain modifier, IK probe | `<scratchpad>/m10_plan/anim_lab/godot_lab/` (skin_lab.gd/.tscn, skin_modifier.gd, ik_probe.gd; they lived in `assets/m10_lab/` of the scratch worktree) |
| Frames rendered under Xvfb (Compatibility renderer) | `<scratchpad>/m10_plan/anim_lab/frames/lab_01_idle.png` ... `lab_08_stage4.png`, sheet `<scratchpad>/m10_plan/anim_lab/lab_contact_sheet.png` |
| Raw numbers (lab, benches, IK probe) | `<scratchpad>/m10_plan/anim_lab/results.txt` |
| Skinning / AnimationTree bench (native + Web export) | `<scratchpad>/m10_plan/anim_lab/webbench/` (bench.gd), runner `<scratchpad>/m10_plan/anim_lab/web_bench_run.mjs`, Web frame `<scratchpad>/m10_plan/anim_lab/webbench/web_bench_last_frame.png` |

---

## 0. The answer in one page

* **Recommendation: a hybrid.** Keep `ActorRig` as the *pose brain* (it already turns every combat
  state into arm yaw/pitch, torso twist, leg swing, body lean/fall and footfalls, on the frame clock,
  apart from the simulation) and add a skinned body that *follows* it:
  1. an `AnimationTree` for what the brain does poorly on a human body - locomotion (idle, walk,
     jog, run), finger grips, later stomp/roar/death clips - all authored by **computed keyframes in
     a committed Blender builder** (provenance rule) and driven by the brain's own phases, so their
     timing is the gameplay timing;
  2. one `SkeletonModifier3D` (GDScript) after the tree: spine twist from the brain, the weapon arm by
     an analytic two-bone solve, the off arm / grab hand, later the engine's `TwoBoneIK3D` for feet.
  The simulation is untouched: nothing in the sim reads the rig today and nothing will.
* **The one real problem is geometry, not animation.** The gameplay arm is the stylized giant's:
  shoulder pivot (0.82, 2.9, 0)·k and a 1.5·k arm. A real human body of the same height has its
  shoulder joint at (0.414, 3.015, -0.033)·k and reaches 1.385·k. The gameplay grip lies beyond the
  realistic reach in 98 % of the swing samples (§2). An IK that puts the fist on the gameplay grip
  cannot work, and changing the pivots is a gameplay change.
* **Chosen mapping: "tip matching".** The visible weapon is aimed from a grip the real arm can reach
  at the tested segment's tip. VERIFIED (ran) over every player weapon arc, stage and ACTIVE sample
  (12,450): the outer half of the visible weapon stays inside the hit capsule 100 % of the time (worst
  0.60 hit radii from the tested segment); the visible direction differs from the tested one by 7.0°
  median, 13.8° worst. The old "exact" rule ("the arm points along the swept segment within 1°")
  becomes a measured one ("the visible head lies inside the swept capsule").
* **Proof, in the real game code:** the real `scenes/player/giant.tscn` with its stylized meshes
  hidden and the skinned MakeHuman giant (CC0, MPFB2 `game_engine` skeleton, 53 bones, 26,756
  triangles) under `Visual/Body`, driven by the real ActorRig: it walks with an authored clip synced
  to the rig's stride and swings the club's real heavy (`ability.heavy_1`); club in the fist (0.000 m
  error), visible club head 0.29-0.33 hit radii off the tested segment, tip 0.14-0.25 m off (stage 1),
  stage 4 scales it uniformly (k = 3). Rendered under Xvfb. VERIFIED (ran).
* **Cost:** on the Web build one skinned giant measured alone costs 0.26 ms CPU per frame
  (AnimationTree 205 µs + modifier 52 µs, WASM: 1.5 % of a 60 Hz frame); with 4-8 instances the share
  per giant is 75 + 28 to 53 + 20.5 µs. Native: ~35-70 µs. Skinning itself is GPU work (transform
  feedback) in the Compatibility renderer, and skinned meshes render in WebGL2. VERIFIED (ran).
* **Must-do side work:** split the body mesh so head/neck/torso/garments go on render layer 2 (first
  person is blind without it - VERIFIED (ran), frame 07); give the skinned meshes `material_override`s so
  RigPaint's flash/tint reaches them; rewrite 6 integration suites' rig-node assertions (§8).
* **Other giants (rival giants, Harrok): keep the stylized rig in M10** (§7); the same skeleton and
  brain can carry them later with other phenotypes.

---

## 1. How the giant is drawn and moved today

### 1.1 The scene and the rig - VERIFIED (code)

`tools/builders/player.gd` builds `scenes/player/giant.tscn`:

* `Giant` (CharacterBody3D, `giant_player.gd`), `BodyShape` capsule (r 0.85, h 3.66), `CombatEntity`,
  `Anchors/Torso` (0, 2.3, 0), `Hurtboxes` Legs/Torso/Head (static boxes), `CameraRig/Camera3D`.
* `Visual` = `ActorRig` (`scripts/presentation/actor_rig.gd`, 494 lines) with `Visual/Body`:
  `HipL/HipR` (y 1.6) with merged leg+foot meshes, `Torso` (y 1.6) with Chest, Belt and Head
  (neck, head, hair, brow, eyes merged) **on render layer 2** (`SceneKit.FP_HIDDEN`), `ShoulderL/R`
  at (∓0.82, 2.9, 0) with a merged arm mesh, the generated `Club` under `ShoulderR`, and a `Hand`
  marker at (0, 0, -1.5) under each shoulder. 8 meshes, one vertex-coloured material copied per actor
  (P22, `RigPaint`).
* The arm is a straight rod: `_aim()` sets `Basis.looking_at(local_direction(yaw, pitch))`, the hand
  is 1.5 m down the arm, the weapon continues from there. `GiantPlayer.rig` is typed `ActorRig`.

### 1.2 What drives the poses - VERIFIED (code)

`ActorRig._process()` reads `actor.get_rig_state()` (`GiantPlayer` + each component's `rig_state()`):

| State / action | Pose today (ActorRig) |
|---|---|
| locomotion | idle arm (12°, -78°) / off (-10°, -80°); legs `rotation.x` = sin(walk phase)·0.55 rad; arms swing ±16°; walk phase += delta·speed/(stride 1.6·k)·π; `footfall` signal every π |
| weapon_arc (lights, heavies of club/sword/hammer/axe/fists/tree/pine, stage movesets) | weapon arm = `AttackGeometry.pose_for()` - exact (`_arm` = pose) during ACTIVE, smoothed otherwise; + the stage's `arc_pitch_offset_deg` (and P17b's per-swing aimed tilt) eased by `arc_offset_weight`; off arm = off idle + 30° pitch; torso twist = -0.3·yaw |
| cylinder_pulse (Heavy Footfall, Titan Stomp, Thunderhead) | both arms raise (20°, 70°) over WINDUP, slam (10°, -70°) at ACTIVE, settle - a stomp is drawn with the arms, the legs do nothing |
| cylinder_pulse with morale damage (Thunder Roar, Titan Roar) | `ability_pose`: arms pulled in, then flung wide (85°, 20°) |
| line_pulse (Earthquake), body_sweep (Shoulder Charge) | no case in `_process`: idle arms, no leg swing while the action runs (VERIFIED (code + data/abilities)) |
| sector_pulse (sweeps) | wound (110°, 5°) → swept (-110°, 0°), twist ±25° |
| projectile | boulder / thrown body: two-hand overhead (15°, 85°) → (10°, 5°); else one-hand cast with the off arm |
| none (self buffs) | two-arm flex (45°, 35°) |
| blocking | block (-45°, 12°) / off block (30°, 8°) |
| dodging | arms (25°, -50°) roll or (35°, -62°) sidestep; Body leans into `dodge_local` (roll 0.25 rad, sidestep 0.08/0.14) |
| staggered | Body wobble (0.14 + sin·0.06 rad pitch, sin·0.05 roll) |
| dead | Body falls forward over ~0.6 s (-0.48π about X at the feet) |
| grab reach / hold / crush / throw (`PlayerGrab.rig_state` → `pose_override`) | `ActorRig.grab_pose()`: off hand (both for `two_hand` in third person) aimed at the grab socket; crush shakes; throw winds back to `THROW_BACK_*` and follows through |
| growth | `set_body_scale(k)`: `Visual/Body` scaled uniformly, k = height / 3.6576; shoulders re-placed at pivot / k |
| weapon change | `set_weapon_visual()`: the `WeaponVisuals` mesh under `ShoulderR` at (0, 0, -1.5), node scale effective_weapon_scale / k; tree/pine carried at `TREE_IDLE_POSE` (24°, 30°) |
| hit flash / status tint | `RigPaint.paint()` on the rig's material copies (emission flash, albedo multiplier tint) |

There is no jump pose, no head look, no foot placement, no facial animation (VERIFIED (code): no
`jump` case in actor_rig.gd).

### 1.3 Who reads the rig - VERIFIED (code, grep over scripts/ tools/ tests/)

Gameplay geometry never comes from the rig:

* **Weapon sweep**: `PlayerAttack.weapon_segment_global()` = profile pivot + `AttackGeometry`
  direction × [arm_length, arm_length + weapon_length] (data); the P17b vertical aim picks a tilt per
  swing from the target (`_start_aim`), so the visual must follow a per-swing value - authored swing
  clips could not know it.
* **Hurtboxes, lock anchor** (`Anchors/Torso`): static nodes under the CharacterBody, resized ×k by
  `PlayerGrowth._resize_body()`. The hurtbox `region` field (legs/torso/head) is read by nothing in
  scripts/ (only `wander_director.gd` reads an unrelated `.region`), so the realistic body's other
  proportions (hip joint at 2.07 m instead of the boxes' 1.6 m split) change no damage.
* **Camera**: third-person pivot = `camera_pivot_height_m` (3.35·k); first-person eye =
  0.92·height + 0.18 m forward (the 0.18 m is not scaled by k); layer 2 culled in first person and
  when the arm is pressed short (`hides_head`). No rig node is read.
* **Grab sockets**: `PlayerGrab.SOCKETS` × k (data); the held body is placed there every tick; the rig
  only points the arm at it.
* **Rig → elsewhere, all presentation**: `footfall` → `PlayerGrowth._on_footfall` (camera shake),
  `CueRouter.on_node_added` (`node is ActorRig` → step sounds, `ambience.on_giant_impact`);
  `HitFeedback` → `flash` / `set_status_tint`; `PlayerEquipment` → `set_weapon_visual`, `idle_arm_pose`,
  `body_scale`; `PlayerGrab` → `idle_arm_pose`/`off_idle_pose` for `grab_pose`.

### 1.4 Determinism - VERIFIED (code)

`Sim` steps actors in `_physics_process` at 60 Hz (hooks, stable entity order); `ActorRig` runs in
`_process`; the walk phase uses the frame delta, so footfall timing is frame-rate dependent but feeds
only audio and camera shake. Pre-existing camera→gameplay couplings unrelated to the rig (keep them
unchanged): `PlayerGrab.socket_local()` switches sockets in first person; `camera_aim_point()` aims an
unlocked projectile through the camera. **RECOMMENDATION:** the skinned rig must stay write-only to
its own Skeleton3D and its weapon node; it may *read* physics (foot rays) in `_process` like the
camera rig's sweeps already do (VERIFIED (code): `CameraRig._sweep` uses `cast_motion` from
`_update_transform` in `_process`).

---

## 2. The geometry problem (why the arm cannot simply be IK'd onto the gameplay grip)

Skeleton landmarks of the kit's giant (MakeHuman phenotype `GIANT_MACRO`/`GIANT_MODIFIERS`, MPFB2
`game_engine` rig) built at stage-1 height 3.6576 m, in the game's actor axes (+X right, -Z front) -
VERIFIED (ran, `export_test_giant.py`):

| Landmark | Realistic body | Stylized rig / gameplay |
|---|---|---|
| right shoulder joint | (0.414, 3.015, -0.033) | pivot (0.82, 2.9, 0) |
| upper arm / forearm / wrist→palm centre | 0.601 / 0.545 / 0.239 m → reach 1.385 m | arm_length 1.5 m (straight rod) |
| hip joint | y 2.071 | hip pivots y 1.6 |
| eyes (mid) | (0, 3.447, -0.244) | first-person eye (0, 3.365, -0.18) |
| head bone / top of head | y 3.376 / 3.658 | Head box centre 3.34 |

Every profile is a uniform k-scale of stage 1: pivot/k = (0.82, 2.9, 0), arm/k = 1.5, attack
origin/k = (0, 2.6, 0), camera pivot/k ≈ 3.35 at all six stages - VERIFIED (ran, data/growth/*.json).
So the realistic body can be scaled uniformly too and the mismatch is the same at every stage
(×k).

Reach, over all player weapon arcs (lights, heavies, stage movesets) × stages 1-6 (with each stage's
arc pitch offset) × WINDUP/ACTIVE/RECOVERY - VERIFIED (ran, 14,742 samples): the gameplay grip
(pivot + dir·1.5) is beyond 0.98 × the realistic reach in **90 %** of samples, **98 %** of ACTIVE
samples (4,799 / 4,914); median 1.13 × reach, worst 1.39 ×; even the idle grip is 1.21 ×.
Grab sockets are 1.06-1.24 × reach from the shoulders (torso_fist 1.72 m, two_hand 1.47 m, first
person 1.71 m from the left shoulder at stage 1) - VERIFIED (ran).

Three ways to map a swing were compared on the 12,450 ACTIVE samples of every player weapon/arc/stage -
VERIFIED (ran):

| Mapping | Visible head inside the hit capsule | Head deviation (hit radii) p50 / max | Tip offset (stage-1 m, ×k) p50 / max | Direction change p50 / max |
|---|---|---|---|---|
| parallel arc (same yaw/pitch around the real shoulder) | 77 % | 0.91 / 1.41 | 0.48 / 0.63 | 0° / 0° |
| **tip matching** (grip within reach, weapon aimed at the tested tip) | **100 %** | **0.30 / 0.60** | 0.19 / 0.58 | 7.0° / 13.8° |
| two hands from the chest centre | 4 % | 1.75 / 2.77 | 0.87 / 1.27 | 0° / 0° |

Two-handed grips on the haft (0.30 m beyond the weapon hand) are reachable only 4 % (club) to 21 %
(oak) of ACTIVE samples under tip matching - VERIFIED (ran). The off hand therefore follows the brain's
off pose; in overhead chops it lands near the haft by itself (frame 05).

Changing the gameplay pivots/arm lengths to the realistic skeleton would remove the mismatch but is a
gameplay change (reach bands, P17b vertical aim, `test_stage_reach_bands`, balance matrices): not for
M10 (**RECOMMENDATION**; keep as a later option if playtests see the 7° offset).

---

## 3. Design: SkinnedRig = ActorRig brain + skinned body (RECOMMENDATION)

### 3.1 The asset (Blender builder, committed)

* Body: the kit's MakeHuman body with the **MPFB2 `game_engine` rig** (53 bones, mannequin-style
  names: pelvis, spine_01-03, neck_01, head, clavicle/upperarm/lowerarm/hand, thigh/calf/foot/ball,
  15 finger bones per hand) and its CC0 weights (`weights.game_engine.json`: every one of 19,158 hm08
  vertices weighted, up to 7 influences, 981 vertices with more than 4) - VERIFIED (ran). The kit's
  renders use the 163-bone `default` rig with twist bones; for the game the 53-bone rig is enough.
  No face bones (no jaw/eyes): expressions would need MakeHuman expression targets as blend shapes
  (later).
* Export: glTF binary, 4 influences per vertex, +Y up, armature-relative, base mesh without
  subdivision (detail from normal maps - see the asset brief). The lab export: body 14,517 vertices /
  26,756 triangles, braies 551/964, belt 192/192, eyes 80/140 each, 1.30 MB file, 1.3-2.2 s in
  Blender, imported by Godot in ~11 s, **0.73 MB in a pck** (the bench's pck with the giant: 741 KB) -
  VERIFIED (ran). The model faces +Z after import; the game turns it 180° about Y under `Visual/Body`.
* **Split for first person**: separate meshes (same skeleton) for head+neck+hair+beard+eyes, torso
  (spine/clavicle/pelvis-weighted faces) and garments → render layer 2; arms and legs on layer 1.
  Keep the split normals of the joined mesh when separating so no seam shows (ASSUMED technique).
* **Clips by computed keyframes** (provenance: no hand animation, like the audio generators): the lab
  wrote idle (2 s breathing), walk (32 frames, one two-step cycle) and grip (finger curl) in Python and
  they imported as Godot animations - VERIFIED (ran). The walk's stride is 3.12 m per cycle at k = 1
  against ActorRig's 3.2 m (2.5 % apart, no visible sliding) - VERIFIED (ran). M10 list (ASSUMED
  effort): idle, walk/jog/run cycles (same two-step structure), right and left grip poses, a relaxed
  open hand; M11 or later: stomp (leg), roar, flex, flinch (additive), death fall, roll, jump.

### 3.2 Runtime layers (order inside one frame)

1. `ActorRig._process` (unchanged brain): `_arm`, `_off`, torso twist, leg swing, Body lean/fall,
   `_walk_phase`, footfalls. It keeps its invisible pivots (`Body/ShoulderR` etc.) - cheap Node3Ds.
2. `AnimationTree` (BlendTree, VERIFIED (ran) in the lab and the bench):
   `idle | TimeSeek(walk)` blended by speed → `Blend2(grip)` with a filter on the right-hand finger
   bones. The walk's time is **set from the brain's walk phase** each frame
   (`t = fposmod(_walk_phase + π/2, 2π) / 2π × clip length`), so the heel strikes happen when the brain
   emits `footfall` (audio and camera shake stay in sync - the +π/2 aligns the clip's heel strike with
   the brain's π steps; ASSUMED aligned by construction, not measured frame by frame). For walk vs run,
   blend by normalized speed = speed / k: 5.0 at stage 1 down to 1.57 at stage 6, so one clip set reads
   as a jog at stage 1 and a slow heavy walk at stage 6 (cycle 0.64 s → 2.04 s) - VERIFIED (ran,
   numbers from data/growth).
3. `PoseBrainModifier` (SkeletonModifier3D child of Skeleton3D, runs after the tree; VERIFIED (ran):
   the lab's `skin_modifier.gd`):
   * spine twist: the brain's torso twist spread over spine_01-03;
   * weapon arm, **tip matching**: tip = pivot/k + dir·(arm + weapon)/k in Body space; grip = the
     natural grip (shoulder + dir·0.93·reach) moved onto the sphere of radius weapon_length around the
     tip and projected into reach (12 alternating projections), or the farthest reachable point toward
     the tip; analytic two-bone solve (law of cosines, elbow pole down-back-out), hand turned so a
     diagonal grip axis (wrist→knuckle line rotated toward the index side, ~40°) lies on the weapon;
     the weapon node (child of Body, scale effective_weapon_scale / k as today) placed in the fist;
   * off arm: the brain's off pose mapped onto the real arm (palm at shoulder + dir·0.9·reach) when an
     action/block/dodge/override runs, the clip's arm in plain locomotion; for grabs, the palm on the
     socket when in reach;
   * later: legs with the engine's `TwoBoneIK3D` on ground rays (feet on slopes): the engine IK put the
     giant's foot exactly on a raised target (error 0.0000 m, knee toward the pole) - VERIFIED (ran,
     `ik_probe.gd`).
4. Body-level leans (stagger, dodge, death fall) are inherited for free because the model is a child
   of `Visual/Body` (the lab put it there; uniform scale inherited - VERIFIED (ran)).

**Engine facts for the implementer** - VERIFIED (ran) on Godot 4.6.3:
* available: `SkeletonModifier3D`, `TwoBoneIK3D`, `FABRIK3D`, `CCDIK3D`, `JacobianIK3D`, `SplineIK3D`,
  `LookAtModifier3D`, `AimModifier3D`, `CopyTransformModifier3D`, `BoneTwistDisperser3D`,
  `LimitAngularVelocityModifier3D`, `SpringBoneSimulator3D` (hair/beard sway), `RetargetModifier3D`,
  `BoneAttachment3D`, `AnimationTree` with BlendTree/BlendSpace/StateMachine/TimeSeek/OneShot;
* **modifier results are not kept**: outside the skeleton's update, `get_bone_global_pose()` returns
  the animated (pre-modifier) pose; read final poses in `Skeleton3D.skeleton_updated` or from nodes the
  modifier places (the weapon). Tests must do the same.
* glTF clips import with loop off; set `loop_mode` (or name them `*_loop`) for idle cycles.

### 3.3 Class shape

`SkinnedRig extends ActorRig` (scripts/presentation/skinned_rig.gd): inherits the brain so every
`is ActorRig` check (CueRouter footfalls, `HitFeedback.tint_target`, `GiantPlayer.rig` type, tests)
keeps working; overrides `set_weapon_visual()` (weapon under a `Body/WeaponSocket` the modifier drives
instead of `ShoulderR`), `set_body_scale()` (also the growth tween below) and the material capture
(RigPaint copies `material_override`s only - VERIFIED (code) `RigPaint.make_unique` - so the builder
must set `material_override` on the skinned meshes, and RigPaint needs a ShaderMaterial path if the
skin is a custom shader: tint uniform × albedo, flash uniform → emission).

### 3.4 Per-action treatment

| Brain output | Skinned treatment |
|---|---|
| weapon arcs (all weapons, fists included: the Stoneknuckles stay a 1.9 m weapon mesh in the fist) | tip matching IK, exact phase timing from the brain |
| block / dodge arms / casts / flex / sweeps / overhead throws | the brain's arm (yaw, pitch) → palm at shoulder + dir·0.9·reach (generic mapping, no new code per action) |
| grabs | off palm on the socket when in reach; otherwise its farthest point, and (RECOMMENDATION) offset the *held actor's Visual node* by the remaining gap (≤ 0.33·k m) so the body sits in the fist - collision and hurtboxes stay at the simulated socket |
| stomp, roar (cylinder_pulse) | M10: brain arm poses; later a leg stomp / roar clip whose time is seeked from the action's phase fraction (impact key at ACTIVE start) |
| stagger, dodge lean, death | inherited Body rotations (M10); later additive flinch, roll, death clips |
| growth | uniform scale (§5) |

---

## 4. The proof (lab) - VERIFIED (ran)

Scratch worktree of HEAD 1c33b8e (removed afterwards); the real `giant.tscn` spawned on a flat box;
its stylized meshes hidden (nodes kept for the brain); `test_giant.glb` under `Visual/Body` turned 180°;
AnimationTree + `skin_modifier.gd`; input injected through the real `InputRouter`; the real
`controller.request(&"heavy")`; rendered with `--rendering-driver opengl3` under Xvfb. Frames:
`lab_01_idle`, `lab_02_walk_side`, `lab_03_walk_game_camera` (the game's own third-person camera),
`lab_04_heavy_windup`, `lab_05_heavy_active`, `lab_06_heavy_recovery`, `lab_07_first_person_down`,
`lab_08_stage4`.

| Check | Result |
|---|---|
| walk | 5.00 m/s (stage 1), the clip's stride follows the brain's walk phase, footfalls counted (28 over the walk) |
| heavy_1, ACTIVE (2 frames sampled; the box rendered at a few frames per second under load, slow motion 0.12) | visible club head 0.290-0.329 hit radii from the tested segment; tip 0.135-0.247 m from the tested tip; grip 0.27-0.35 m from the tested grip; direction 7.1-7.2° (the tip-matching angle); fist on its target 0.000 m; wrist bend 38-45°; modifier 73-74 µs per frame (GDScript, 4-CPU box at load ~10) |
| first, parallel-arc run (superseded) | measured against the previous tick by mistake: 10.6° = one tick of the heavy (127° in 12 ticks); lesson for the tests: compare with `phase_fraction()` at `frame_pre_draw`, not `active_fraction_prev()` |
| stage 4 | `debug_set_stage(4)` ok; Body scale (3, 3, 3); head bone at 10.13 m = 3 × 3.376 |
| first person (frame 07) | with one body mesh the view is filled by the giant's own neck/chest from inside - the layer-2 split (§3.1) is required |
| first-person eye vs the model's eyes | stage 1: model eyes 0.082 m above and 0.064 m ahead of the game's eye; stage 4: 0.246 m above, 0.552 m ahead (the 0.18 m forward offset is not ×k) |

---

## 5. Growth stages 1-6

* **Uniform scale** (RECOMMENDATION): the gameplay geometry is uniform (§2), the model under
  `Visual/Body` scales with k (VERIFIED (ran), stage 4). Per-stage proportions (heavier, older at
  stage 6) would need per-stage skeletons or bind poses; blend shapes on a fixed skeleton are possible
  later but the character creator owns body shape (other brief).
* **Growth moment**: today it is instant (one tick). A presentation-only grow tween can live on an
  intermediate node (`Body/Model` scale from k_old/k_new to 1 over ~0.8 s) so `Visual/Body.scale == k`
  stays true at once for the tests (`test_growth` checks it right after growing) - ASSUMED.
* Weapon node scale stays effective_weapon_scale / k (the tree's 1/k) - VERIFIED (ran) in the lab.
* Cadence per stage (two-step cycle): 0.64 / 0.83 / 1.07 / 1.35 / 1.68 / 2.04 s for stages 1-6 -
  VERIFIED (ran) from walk_speed_mps and the 1.6·k stride.

## 6. First person

* Split meshes to layer 2 as listed in §3.1, hair and beard meshes included; arms and legs stay
  visible (as the stylized arms do). Today the stylized hair is merged into the layer-2 head, and the
  tree/pine canopies are on layer 2 (`WeaponVisuals.FP_HIDDEN_LAYER` - VERIFIED (code)).
* Keep `eye_height_ratio` 0.92 and the 0.18 m offset: the eye feeds `camera_aim_point()` (projectile aim
  without a lock) and `test_growth_456` checks 0.92 - changing it is a gameplay-adjacent change
  (RECOMMENDATION: leave it; the 8 cm × k difference is inside the hidden head).
* The camera reads no rig node, so no camera change is needed - VERIFIED (code).

## 7. Other giants (rival giants, clan giants, Harrok)

* Today: stylized ActorRig bodies (`tools/builders/big.gd`), shoulders at (0.135, 0.73)·H, arm 0.26·H
  (rival giant H 10 m, Harrok 15 m, pivots (1.35, 7.3) and (2.0, 10.95)), `render_lod_m` 0 - VERIFIED
  (code + data). Clan giants come in groups (`encounter_tpl_stonehold_clan_giants`, the Moot) -
  VERIFIED (grep).
* **RECOMMENDATION: keep them stylized in M10** (the owner was told the realistic giant will stand
  out; the time goes to the player and the creator). Later they can share the skeleton, the brain and
  tip matching (their shoulders are closer to human: 0.135·H vs 0.113·H) with their own phenotypes and
  outfits, at the per-instance cost of §9 (~0.1 ms Web CPU each) plus their draw cost.

## 8. Determinism and test impact

* Determinism: unchanged if the rules of §1.4 hold - the brain stays the only reader of combat state,
  the skinned layers are write-only to their skeleton/weapon, feet read physics only. Headless test
  runs process AnimationTrees and modifiers (the bench ran them headless - VERIFIED (ran)); their cost
  in the default suite is microseconds per frame.
* Suites that read the player's stylized rig nodes - VERIFIED (grep):

| Suite | What it reads | With the hybrid |
|---|---|---|
| `tests/integration/test_rig_merge.gd` | giant row: 8 meshes under Visual/Body, `ShoulderR/Club`, Torso/Chest-Belt-Head on layer 2, `ShoulderL/R/Mesh`, `HipL/Mesh`, `Hand` markers, material count, `set_weapon_visual` | rewrite the giant row (skinned meshes, layer-2 parts, materials) |
| `tests/integration/test_growth.gd` | `rig.body_scale`, `Visual/Body.scale`, `ShoulderR.position == pivot/k`, footfalls, head hidden when the arm is short (`Torso/Head`, `ShoulderR/Mesh`), tilted arc: ShoulderR on the pivot and -Z within 1° of the swept segment | body-scale/pivot/footfall checks pass on the kept brain; mesh paths change; replace the 1° check with "visible weapon head inside the swept capsule at stage 3" |
| `tests/integration/test_growth_456.gd` | `rig.body_scale`; FP eye inside `Visual/Body/Torso/Head`'s box, head on layer 2 | point at the new head mesh |
| `tests/integration/test_camera_review_fixes.gd` | FP hides Torso/Chest, Belt, Head; `ShoulderR/Mesh` visible | new mesh paths |
| `tests/integration/test_grab_throw.gd` | `ShoulderL` -Z within 3° of the socket, `ShoulderL/Hand` within 0.25 m | passes on the brain's pivots but proves less; add "visible palm within the measured gap (≤ 0.33·k) of the socket", read in `skeleton_updated` |
| `tests/integration/test_weapons.gd` | `Weapon` under `Visual/Body/ShoulderR`, Club hidden, canopy layer 2, `idle_arm_pose` | weapon socket path |

  Unaffected while `ActorRig` stays the base class: `test_growth_rules` (static ActorRig functions),
  `test_world_threat_cues` and the sfx suites (`rig.footfall`), `test_abilities_m2` (status tint),
  enemy rig suites (`test_render_lod`, `test_troll`, `test_telegraphs`...).

## 9. CPU and size on the Web build - VERIFIED (ran)

Bench: N skinned test giants, each with the lab's AnimationTree (idle | seek(walk) → filtered grip) and
a GDScript modifier (spine twist + both arms, two-bone solve), timed per frame (trees advanced
manually, modifiers timed from inside). Machine: 4 CPUs at load ~10 (M9 runs) - absolute numbers are
pessimistic.

| Build | 1 giant | 4 giants | 8 giants |
|---|---|---|---|
| native Linux headless: AnimationTree / modifier µs per giant per frame | 51 / 18 | 26 / 9.8 | 23 / 10.4 |
| **Web** (Godot 4.6.3 single-threaded export, headless Chromium, WebGL2 on ANGLE/SwiftShader): AnimationTree / modifier µs per giant | **205 / 52** | **75 / 28** | **53 / 20.5** |
| Web frame interval (software rasterizer: GPU-bound, indicative only) | 148 ms (empty 120 ms) | 284 ms | 358 ms |

* The player's one giant: 0.26 ms of a 16.7 ms frame on WASM measured alone (1.5 %); the per-instance
  share falls to ~0.07-0.1 ms with more instances, so shared per-frame overhead is part of the lone figure.
* Skinning is GPU work in the Compatibility renderer: the engine binary carries the GLES3 skeleton
  shader (`uniform highp sampler2D skeleton_texture`, `texelFetch` bone fetch) and
  `glBeginTransformFeedback` - VERIFIED (ran, strings of the 4.6.3 binary); the CPU only uploads 53
  bone transforms. The skinned giants render in WebGL2 (`webbench/web_bench_last_frame.png`).
* GPU cost of 26.7k skinned triangles on a real GPU: not measured (ASSUMED small; SwiftShader's
  +28 ms per first giant is CPU rasterization).
* pck: +0.73 MB for the mesh + 3 clips (VERIFIED); textures (skin, normal maps, tattoo/war-paint
  layers) are the asset brief's budget against the 23 MB pck (17.5 MB used).

## 10. Risks, open points, rough work split

* Visible-vs-tested offset (7° median, head always inside the capsule) is a deliberate change of a
  documented contract - the M10 plan should state it and the tests should measure it (ASSUMED
  acceptable; playtest it).
* Arm-body intersection on cross-body arcs (yaw down to -100°) is not handled (no collision
  avoidance); the brain's -0.3·yaw torso twist helps; tune elbow poles per arc side (ASSUMED risk).
* Wrist bend 38-45° measured with tip matching (38-57° in the parallel-arc run) with a ~40° diagonal
  grip axis; tune the grip axis per weapon family (ASSUMED).
* Grabs: hand 0.08-0.33·k m short of the socket; the held-visual offset needs the enemy's Visual to
  accept a presentation offset while held (small hook in EnemyActor's carry path) (ASSUMED).
* Rough effort inside M10's 2-3 days (ASSUMED): game-export builder with split meshes and the
  locomotion/grip clips 0.5 d; SkinnedRig + PoseBrainModifier (tip matching, grabs, spine) + material
  path 0.75 d; builder/scene + 6 suite rewrites + new contract tests 0.5 d; Web size/frame check
  0.25 d. Foot IK, ability clips (stomp/roar/death/roll/jump), two-handed grips and the other giants
  belong to a later milestone.

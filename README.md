# Giantborn: Age of Titans

Giantborn: Age of Titans is a single-player open-world fantasy action RPG. You begin as a
juvenile giant twice human height and grow over 20 levels and 10 physical stages into a
140-ft titan. The full design is in [docs/GIANTBORN_SPEC_V2.md](docs/GIANTBORN_SPEC_V2.md).

**This repository currently holds milestones M0 + M1:** a low-poly, playable 3D combat sandbox.
It has a 120 × 120 m arena, the 12-ft (3.66 m) stage-1 giant, a melee soldier, a practice dummy,
a breakable fence, both camera modes, light/heavy attacks, block, parry, dodge, lock-on, Heavy
Footfall, a HUD, settings, key rebinding and a debug reset. Graphics are deliberately simple
(flat-coloured boxes); audio is silent.

The test results and the full acceptance-check list are in
[docs/M1_HANDOFF.md](docs/M1_HANDOFF.md).

---

## 1. Requirements

| Item | Version |
| --- | --- |
| Engine | **Godot 4.6.3-stable**, standard build (GDScript, not .NET). Download: <https://godotengine.org/download/archive/4.6.3-stable/>. Pick the Windows 64-bit standard ZIP. |
| Renderer | Compatibility (OpenGL 3.3); this is set in the project and runs on modest GPUs. |
| OS | Windows 10/11 is the target; Linux was used for development and testing. |
| Plugins / paid assets / online services | None. |

Use exactly 4.6.3. A newer 4.x editor will offer to convert the project; please don't accept
that until the engine version is deliberately upgraded.

## 2. Run it

### From the Godot editor (recommended)
1. Start Godot 4.6.3 → **Import** → choose this folder's `project.godot` → **Import & Edit**.
2. Wait for the first import to finish (a few seconds).
3. Press **F5** (Run Project). The main scene is `scenes/main.tscn`.

### From a command line
```bash
godot --path /path/to/Giantborne-Age-of-Titans
```
On Windows, run `Godot_v4.6.3-stable_win64.exe --path C:\path\to\Giantborne-Age-of-Titans` from
PowerShell, using wherever you unzipped Godot.

If a data file has an error, the game shows the complete list of validation errors instead of
starting the sandbox. Fix the listed JSON file and run again.

## 3. Controls

All bindings can be changed in **Esc → Controls**. Click a binding, then press the new key or
button; changes are saved to `user://settings.json`.

| Action | Keyboard / mouse | Controller |
| --- | --- | --- |
| Move / look | WASD / mouse | Left / right stick |
| Light attack (3-hit chain) | Left mouse | RB / R1 |
| Heavy attack | **Shift + left mouse** | RT / R2 |
| Block (tap = parry window) | Right mouse | LB / L1 |
| Dodge / jump | Space / F | B / Circle; A / Cross |
| Interact / grab | E (nothing to grab until M3) | X / Square |
| Sprint | Hold Shift while moving | Left-stick press |
| Lock target | Tab | Right-stick press |
| Switch target | Mouse wheel while locked | Right-stick flick while locked |
| Camera zoom (third person) | Mouse wheel while not locked | — |
| Camera mode (third / first person) | V | D-pad Up |
| Ability slots 1–8 (slot 1 = Heavy Footfall) | 1–8 | LT + A/B/X/Y, LT + D-pad Up/Right/Down/Left |
| Ultimate (none equipped in M1) | R | LT + RT |
| Pause, settings, rebinding | Esc | Start |
| Controls overlay | F1 | — |
| Restart after defeat | Enter | — |
| **Debug panel** (debug builds only) | F3 | — |
| **Debug reset** (debug builds only) | F5 | — |

Modifier inputs are consumed: Shift + left mouse issues one heavy attack and never also a light
attack. With LT held, B uses slot 2 instead of dodging, D-pad Up uses slot 5 instead of switching
camera, and RT is the ultimate instead of a heavy attack. The controller combo buttons are
remappable too; the Controls page shows them as "LT + button". Holding block keeps you blocking
(it resumes after attacks or staggers), but only a fresh press opens the parry window. While
blocking, the guard faces where you aim. **Settings** (Esc → Settings) covers
mouse sensitivity, stick speed, invert Y, FOV (75° default), hold/toggle sprint, hold/toggle
lock-on, camera shake, head bob, hit flash, vibration, first-person aim assist and damage
numbers. Motion blur is off and is not part of the prototype.

## 4. What's in the sandbox

You spawn at the south end, facing north.

| Feature | Where | What to try |
| --- | --- | --- |
| Practice dummy (armor 25) | 8 m ahead | Damage matches the spec's worked example: light **37**, heavy **66**, Heavy Footfall **44**. It never dies and refills 3 s after the last hit. |
| Breakable fence | 12 m to your right | Breaks into stumps and debris, awards "+1 Wood Scrap" once, and stops blocking movement. |
| Wall test lane | 14 m to your left | A dummy stands behind a solid wall; swings at the wall must not hit it (you get a spark instead). |
| Doorway 2.6 × 5 m | north-west | Narrow-door and camera test. |
| Low arch, 4.2 m ceiling | north-east | Ceiling-clearance and camera test. |
| Ramp (20°) and platform | far north-east | Slope test. |
| Soldier patrol | north (about 55 m away) | It notices you within 25 m, approaches your legs, telegraphs its strikes (0.55 s slash, 0.85 s overhead chop) and pauses between them. Between strikes it **guards its front** (sword raised): frontal hits are mostly blocked. Flank it (it turns slowly while guarding) or break the guard with heavy attacks, which staggers it. Parrying its strikes staggers it too. |

**Combat basics:**
- Attacks cost stamina (light 8, heavy 22, dodge 18, block 5 on entry, sprint 8/s). Stamina
  regenerates 15/s after 1 s without spending.
- Block covers your front 120°. Pressing block just before a hit (within 0.20 s) is a
  **parry**: no damage, 5 more stamina, and the attacker takes 40 poise (enough to stagger a
  soldier).
- Dodge makes you invulnerable from 0.10 s to 0.30 s.
- Fury fills from basic attacks (4), parries (6) and kills (8). The ultimate that spends it is
  roadmap.

## 5. Tests and soak runs

```bash
tools/run_tests.sh
```
That runs `godot --headless --path . --fixed-fps 60 res://tests/run_tests.tscn -- --no-user-settings`
under the hood. On Windows, run that underlying `godot` command directly. It prints one line per
suite and `RESULT: … checks, 0 failures`, and exits with 1 if anything fails. Add
`--filter=unit` or `--filter=integration` after `--no-user-settings` to run a subset.

The 10-minute automated play session (the seeded bot fights, blocks, dodges, breaks the fence,
switches cameras and resets on death; it prints a JSON summary):
```bash
godot --headless --path . --fixed-fps 60 -- --no-user-settings --autoplay=600
```

**Frame-time measurement on your PC:** run the exported game without `--fixed-fps`, so frame
times are real, and read `frame_ms_p95` / `frame_ms_p99` in the printed summary. On Windows, use
the `Giantborn.console.exe` that the export creates, so the summary prints to the console.
```bash
Giantborn.console.exe -- --no-user-settings --autoplay=300
```

The screenshot tour (needs a display):
```bash
godot --path . -- --no-user-settings --scenario=capture --capture-dir=user://captures
```

## 6. Export

1. Install the export templates once: **Editor → Manage Export Templates → Download and Install**
   (4.6.3).
2. **Project → Export…** → choose **Windows Desktop** (or Linux) → **Export Project**.

Presets already exist in `export_presets.cfg`. They write to `builds/`, include `data/**/*.json`,
and exclude `tests/` and `tools/`. The command-line equivalent is:
```bash
godot --headless --path . --export-release "Windows Desktop" builds/windows/Giantborn.exe
```
Release exports disable the F3 debug panel and the F5 debug reset.

## 7. Project layout

```
data/        JSON content: abilities, actions, growth profiles, player, enemies, props, weapons, items, input
scripts/     core (autoloads, data, saves) · combat (rules + controller) · adapters · actors · ai · world · presentation · debug
scenes/      main, player/giant, enemies/soldier, world/{sandbox_arena, practice_dummy, fence_wood}
ui/          HUD, debug panel, pause/settings/rebind menu
tests/       unit/ and integration/ suites, test runner
tools/       run_tests.sh, build_scenes.tscn (scene generator)
docs/        spec, architecture, decisions, M1 handoff
```
Gameplay numbers live in `data/` and are validated at startup (duplicate ids, missing
references, negative costs, non-positive heights, invalid timing, unknown values and unknown
keys). The architecture is described in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), and every
interpretation of the spec is recorded in [docs/DECISIONS.md](docs/DECISIONS.md).

`tools/build_scenes.tscn` regenerates the scenes from code. **Once you edit scenes in the
editor, don't re-run it**, because it overwrites them.

## 8. Known limitations

- **Visuals and audio are placeholders.** The models are boxes with procedural (code-driven)
  animation, there is no sound, and there is no motion blur.
- **Not tested on real hardware yet.** Everything was tested in a Linux container with a
  software renderer. Windows play, real GPU performance, and gamepad feel (including
  vibration) need your PC. See the handoff for the checklist.
- **Physics interpolation is off.** On monitors faster than 60 Hz, character movement updates
  at 60 Hz (mouse look stays smooth).
- **Only stage 1 is playable.** Growth stages 2–3 exist as data only; growth, grabs, abilities
  2–8, the ultimate, and character/world save files are later milestones.
- **First-person framing.** The club is mostly below the view when you look straight ahead;
  look down to see your swings (this is also how you hit humans in first person). Your chest
  is hidden in first person, so you can see enemies at your feet.
- **Sandbox-only shortcuts.** The navmesh re-bakes when the fence breaks, and the fence's
  partial damage is not persisted.
- **Balance.** All numbers are first-pass tuning from the spec. One soldier is no real match for
  the giant yet, even with its guard.

## 9. Manual test checklist (about 10 minutes)

1. Launch with F5: the sandbox loads without an error screen, and the HUD shows 500 / 100 / 100 / 0.
2. Walk, sprint (watch stamina drain), jump (F), dodge (Space). Rotate the camera.
3. Hit the dummy: light → **37**, heavy (Shift + click) → **66**, three lights in a row chain
   (37 / 40 / 46).
4. Press 1 near the dummy: you see a ground ring and **44**, and slot 1 shows an 8 s cooldown.
   Press 1 again: "recovering" message, nothing spent.
5. Press V to switch to first person, swing while looking down at the dummy, then press V again.
   Nothing about your attack or position should change.
6. Swing at the wall in the wall-test lane: a spark and **no** number on the dummy behind it.
7. Break the fence: debris, "+1 Wood Scrap", and you can now walk through.
8. Walk north to the soldier and lock on with Tab: you see the frame and diamond marker. Block
   (right mouse) and watch for **BLOCK 9**. Tap block just before its sword lands for
   **PARRY**, and the soldier staggers. Dodge through a strike for **EVADE**. Hit its raised
   guard from the front (**BLOCK** numbers), then circle to its side, or use heavies until the
   guard breaks.
9. Kill the soldier: the lock releases at once and does not jump to another target.
10. Walk through the doorway, under the low arch and up the ramp in both camera modes. The camera
    should never sit inside a wall.
11. Esc: try the settings sliders, rebind a key, close the menu and confirm it works.
12. F5 (debug reset) restores everything. Let the soldier win (or set a low-health test) and
    press Enter on the defeat screen.
13. F3: the debug panel shows state, stage, stamina, attack id, target, frame time and AI state.

## 10. Next milestone (M2: combat depth)

Next comes targeting polish, four abilities (Heavy Footfall, Sweeping Blow, Stone Skin, Runic
Bolt), two enemy roles (soldier and wolf), Titan Surge, and the first playtests with new players.
See the M2 row of the spec's milestone table.

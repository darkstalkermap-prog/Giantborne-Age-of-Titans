# Giantborn: Age of Titans

Giantborn: Age of Titans is a single-player fantasy action RPG about growth. You begin as a
juvenile giant twice human height; the full design grows you over 20 levels and 10 physical stages
into a 140-ft titan ([docs/GIANTBORN_SPEC_V2.md](docs/GIANTBORN_SPEC_V2.md)).

**This repository holds the playable prototype through milestone M5: the Valley of Broken Kings**,
a 20-30 minute slice in a 400 x 400 m valley. You wake 12 feet tall in Giant's Hollow, learn to
fight on dummies and a sparring post, cross the Old Wood (wolves, soldiers, an ogre), grow to 18 ft
at the Grove Shrine, settle things with the village of Thornwick (help it, cow it or force your
way), break into the ruins of the Broken Kings, defeat the Ogre King at Kingsfall, grow to 26 ft,
uproot a tree and use it to smash the Deadfall that blocked the Barrow, and claim the Crown of the
First King. The M1 combat sandbox is still there for practice. Graphics are flat-coloured boxes on
purpose; there is no audio.

- **Play it in a browser:** <https://claude.ai/artifact/2UYupKVL1xE6pttiZ6NLqe> (private until it is
  shared from the page's Share menu; needs a keyboard and mouse; see [Browser build](#browser-build-the-play-link)).
- **How it plays**, measured by a bot that plays the whole slice: [docs/HOW_IT_PLAYS.md](docs/HOW_IT_PLAYS.md).
- **The handoff** (what was built, the milestone gates with their evidence, known bugs, what to
  run on your PC): [docs/M2_M5_HANDOFF.md](docs/M2_M5_HANDOFF.md).

| | |
| --- | --- |
| ![Giant's Hollow at New Game](docs/screenshots/01_hollow_start.jpg) | ![A wolf's lunge telegraph in the Old Wood](docs/screenshots/02_wolf_lunge.jpg) |
| New Game: Giant's Hollow, the quest tracker, the first tutorial prompt and the objective marker | The Old Wood: a wolf's lunge telegraph (the red strip fills as it winds up), one wolf down, the forest ogre coming |
| ![The forest ogre's smash](docs/screenshots/03_forest_ogre_smash.jpg) | ![Stage 2 at the Grove](docs/screenshots/04_grove_stage_2.jpg) |
| The forest ogre's smash: a circle to leave before it fills; its long recovery is the punish window | Grown to stage 2 (18 ft) at the Grove: Boulder Hurl locked on the watch cairn on its ledge; the Deadfall on the left, Thornwick ahead |
| ![The quarry raiders](docs/screenshots/05_quarry_archer.jpg) | ![The practice gate cracked](docs/screenshots/06_practice_gate.jpg) |
| The quarry raiders (the help path): an archer's aim line, committed before the shot | The ruins' practice gate, cracked: structural damage that saves with the game |
| ![The Ogre King](docs/screenshots/07_ogre_king.jpg) | ![Stage 3 with the uprooted oak](docs/screenshots/08_stage_3_tree.jpg) |
| The Ogre King at Kingsfall: boss bar, phase pips, the slam's telegraph | Stage 3 (26 ft) with an uprooted oak on the way back to the Deadfall |
| ![The end screen](docs/screenshots/09_end_screen.jpg) | ![The title screen in a browser](docs/screenshots/10_title_web.jpg) |
| The end screen: time, deaths, level and stage, and what Thornwick remembers | The play link's title screen (the browser build, in Chromium) |

*(The first nine were rendered by the game itself while the Valley bot played the help_cache path
(`tools/valley_tour.gd`, software OpenGL under a virtual display, the desktop's `medium` preset); the
last is the browser build in Chromium, which always uses the `low` preset. The M1 sandbox's shots are
in [docs/screenshots/sandbox_m1/](docs/screenshots/sandbox_m1/).)*

---

## 1. Requirements

| Item | Version |
| --- | --- |
| Engine | **Godot 4.6.3-stable**, standard build (GDScript, not .NET). Download: <https://godotengine.org/download/archive/4.6.3-stable/> (Windows: the 64-bit standard ZIP). |
| Renderer | Compatibility (OpenGL 3.3), set in the project. |
| OS | Windows 10/11 is the target; development and testing were done on Linux. |
| Plugins, paid assets, online services | None. |

Use exactly 4.6.3. A newer 4.x editor offers to convert the project; don't accept that until the
engine is deliberately upgraded.

## 2. Run it

**From the editor:** Godot 4.6.3 → **Import** → this folder's `project.godot` → **Import & Edit**,
wait for the first import, then **F5**. **From a command line:** `godot --path .` (Windows:
`Godot_v4.6.3-stable_win64.exe --path C:\path\to\Giantborne-Age-of-Titans`).

The game opens at the **title screen**: **New Game** (the Valley; asks before replacing a saved
game), **Continue** (the last checkpoint), **Sandbox** (the M1 arena), **Settings**, **Controls**,
**Quit**. Shortcuts after `--`: `--mode=valley --new-game`, `--mode=valley --continue`,
`--mode=sandbox`, `--graphics=low|medium` (one run only).

If a data file has an error, the game lists every validation error instead of starting. Fix the
named JSON file and run again.

**Saves.** One slot, written at every checkpoint: the first visit to a shrine, resting, opening a
shrine, reaching a waystone, every growth, the Ogre King's defeat and every main quest stage.
Death reloads the last checkpoint with at least 60 % health; nothing is lost. The file is
`user://saves/valley_1.json` (Windows: `%APPDATA%\Godot\app_userdata\Giantborn- Age of Titans\saves\`;
Linux: `~/.local/share/godot/app_userdata/Giantborn- Age of Titans/saves/`; the browser keeps it in
its own storage). A damaged save falls back to its backup with a message.

## 3. Controls

All bindings can be changed in **Esc → Controls** (or the title's Controls page): click a binding,
then press the new key or button. **F1** or **H** shows the controls for your current loadout in
the game. Button prompts follow the last device you used (Settings → Button prompts).

| Action | Keyboard / mouse | Controller |
| --- | --- | --- |
| Move / look | W A S D / mouse | Left / right stick |
| Light attack (3-hit chain) | Left mouse | RB |
| Heavy attack | **Shift + left mouse** | RT |
| Block (tap just before a hit = parry) | Right mouse | LB |
| Dodge / jump | Space / F | B / A |
| Sprint | Hold Shift while moving | Left-stick press |
| Interact: talk, use a shrine or forge, pick up, **grab** a staggered enemy, put it down | E | X |
| Throw what you hold | Light or heavy attack | RB or RT |
| Lock target / switch target | Tab / mouse wheel while locked | Right-stick press / right-stick flick |
| Camera zoom (third person, not locked) | Mouse wheel | — |
| Third / first person | V | D-pad up |
| Ability slots 1-8 | 1-8 | LT + A / B / X / Y, LT + D-pad up / right / down / left |
| Titan Surge (ultimate, 100 fury) | R | LT + RT |
| Inventory, attributes | I | Back |
| Pause, settings, rebinding | Esc | Start |
| Controls overlay | F1 or H | — |
| Confirm on the death screen (load the last checkpoint; the sandbox restarts) | Enter | A |
| **Debug builds only:** debug panel, sandbox reset, grow / shrink a stage, +100 XP, reload the checkpoint | F3, F5, F6 / F7, F8, F9 | — |

With LT held the face buttons and the D-pad fire ability slots instead of their usual actions, and
RT fires the ultimate. Holding block keeps you blocking, but only a fresh press opens the parry
window. Menus work with the arrows, Tab and Enter, or with the D-pad, A and B (LB / RB switch
tabs). Release exports have no debug keys.

## 4. The Valley

| Segment | Where | What happens |
| --- | --- | --- |
| 1. Giant's Hollow | The start | Both cameras (V), the dummies (light chain, heavy, Heavy Footfall), lock-on, the sparring post (block, parry, dodge), the first shrine. The tutorial is optional. |
| 2. The Old Wood | North | A wolf pack (dodge the lunge, then punish), level 2 (Stone Skin, Crushing Grip), two soldiers that guard their front (break the guard, grab a staggered one with E and throw it), the forest ogre (punish its recovery). |
| 3. The Grove | East of the wood | Level 3, **growth to stage 2 (18 ft)** at the shrine, Boulder Hurl at the watch cairn on the ledge, Runic Bolt. The Deadfall blocks the way north. |
| 4. Thornwick | The village | Outmatched soldiers hold a line and brace. Elder Maren asks for help: **bring back the supply cache** from the quarry raiders, or **drive the ogre out of the fields** (both: XP, two iron ingots for the forge, Ancestral Mend), or **intimidate** her (stage 2: Thunder Roar, no iron), or **smash the barricade** (the village turns on you, and an ambush waits on the way back). |
| 5. The ruins | Across the King's Bridge | The practice gate cracks, then breaks; the courtyard garrison (a formation, an archer on the wall, a mage); the armory's sword and the Giantforge (reforge a weapon for 2 iron so it fits stage 3). Level 4: Mend, Roar, Titan Surge. |
| 6. Kingsfall | South of the ruins | The Ogre King: phase 1 alternates a blockable combo and an unblockable slam; at half health he roars and starts charging - make him hit a pillar or the wall, then punish. |
| 7. The return | Back west | **Growth to stage 3 (26 ft)**, uproot an ancient oak, scatter the patrol on the bridge (soldiers flee from a giant four times their height), smash the Deadfall with the tree, defeat the Barrow's wardens and claim the crown. The end screen names your choice at the village. |

Quest XP is accelerated on purpose ("prototype pacing"). Shrines heal, save, change your loadout
and spend attribute points; growth happens only at shrines (stage 3 only after the Ogre King). A
weapon fits up to a stage: above it the HUD says it is too small until a forge reforges it.

## 5. Combat basics

- Attacks cost stamina (light 8, heavy 22, dodge 18, block 5 on entry, sprint 8/s); stamina comes
  back at 15/s after 1 s without spending. Abilities cost stamina or essence and have cooldowns;
  the hotbar shows why one is unavailable.
- Block covers your front 120°. Pressing block within 0.20 s of a hit is a **parry**: no damage,
  and the attacker takes 40 poise (a soldier staggers). Dodge makes you invulnerable from 0.10 to
  0.30 s. Unblockable blows (the Ogre King's slam and charge) must be dodged.
- Every enemy blow with a long windup shows a **telegraph** on the ground that fills as it winds up;
  archers and mages show an aim line; an arrow at the screen's edge warns of a threat you cannot see.
- Growth adds health, reach and new tactics on both sides: at stage 2 soldiers hold formation and
  brace; at stage 3 they break and flee. Village guards are neutral until you strike them twice.
- Fury fills from basic attacks, parries and kills; at 100, Titan Surge adds 25 % damage and poise
  for 6 s.

## 6. Tests, bots and measurements

Every Godot command for tests goes through `tools/gd.sh`, which gives the worktree its own
`user://` folder (`.userdata/`).

```bash
tools/check.sh                 # import, import, the default suite, the 120 s soak (about 2 min)
tools/check.sh --build --slow  # also rebuild every scene and run the slow suites (about 3 min)
tools/run_tests.sh             # the default suite only; add --slow, or --filter=<part of a path>
```

The suites print one line each and `RESULT: N suites, N checks, 0 failures`; any engine or script
error during a test fails it. There are three folders: `tests/unit` (pure rules), `tests/integration`
(real scenes, physics and input events) and `tests/slow` (the Valley, routes, walkthroughs of all
four village outcomes, stress and bot smoke tests).

**The Valley bot** plays the whole quest line headless (novice or expert, optionally assisted):

```bash
tools/run_bots.sh help_cache:novice:1:assist     # one run; policy:skill:seed[:assist]
tools/run_bots.sh --preset=assisted              # the four village outcomes, assisted (M4 gate)
tools/run_bots.sh --preset=stability             # the 30-minute run (M5 stability gate)
tools/run_bots.sh --preset=balance               # the 22-run balance matrix (25-35 min)
python3 tools/bot_report.py ".userdata/godot/app_userdata/Giantborn- Age of Titans/bot_runs/<tag>"
```

**Performance** (`docs/PERFORMANCE.md` has every command, the budgets and the results):

```bash
tools/gd.sh --headless --path . --fixed-fps 60 -- --no-user-settings \
  --level=res://scenes/test/stress_arena.tscn --scenario=stress --autoplay=300 --graphics=low
tools/gd.sh --headless --path . --fixed-fps 60 -- --no-user-settings \
  --mode=valley --new-game --scenario=valley_walk --autoplay=900 --graphics=low
```

On your PC, run the exported build **without** `--fixed-fps` (real frame times):
`Giantborn.console.exe --resolution 1920x1080 -- --no-user-settings --level=res://scenes/test/stress_arena.tscn --scenario=stress --autoplay=300 --graphics=low`
prints `frame_ms`, `gpu_render_ms` and `draw_calls` percentiles in its `PERF_RESULT` line.

**Screenshots** (need a display; on Linux `xvfb-run` provides one): `tools/capture_tour.sh` (the M1
sandbox), and the Valley tour beside the bot:

```bash
xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --resolution 1280x720 \
  --audio-driver Dummy -s res://tools/valley_tour.gd -- --no-user-settings \
  --save-dir=user://tour_saves --mode=valley --new-game --scenario=valley --bot-assist \
  --bot-village=help_cache --autoplay=2400 --tour-dir=/absolute/folder
```

## 7. Export

1. Install the export templates once: **Editor → Manage Export Templates → Download and Install**
   (4.6.3).
2. **Project → Export…** → **Windows Desktop** (or **Linux**, **Web**) → **Export Project**.

The presets in `export_presets.cfg` write to `builds/`, include `data/**/*.json` and exclude
`tests/` and `tools/` (the Web preset also `docs/`). From a command line:

```bash
godot --headless --path . --export-release "Windows Desktop" builds/windows/Giantborn.exe
godot --headless --path . --export-release "Linux" builds/linux/Giantborn.x86_64
```

Windows also gets `Giantborn.console.exe`, which prints to the console (use it for the
measurement runs). Release exports have no debug panel or debug keys.

### Browser build (the play link)

The play link is the **Web** preset (single-threaded, so it needs no special server headers),
hosted as a claude.ai Artifact page. `web/launcher.html` is that page: a poster, a Play button, the
controls and a loader. The host serves files of up to 16 MB and no archives, so the 36 MB engine
(`index.wasm`) and the game data (`index.pck`) ship gzipped and base64-encoded as `.txt` files,
and the launcher unpacks them in the browser.

```bash
tools/build_web.sh
```

This exports into `builds/web/`, packs the two files, copies the poster
(`docs/screenshots/01_hollow_start.jpg`) and writes the byte counts into `web/launcher.html`. To try
it locally, serve that folder with any static web server (for example
`python3 -m http.server -d builds/web 8000`) and open `http://localhost:8000/play.html`. To update
the play link, republish `web/launcher.html` to the same artifact URL with these files from
`builds/web/`: `index.js`, `index.wasm.gz.b64.txt`, `index.pck.gz.b64.txt`,
`index.audio.worklet.js`, `index.audio.position.worklet.js` and `poster.jpg`.

In the browser: click the game (or a title button) to take the mouse; the first **Esc** gives it
back and pauses, because the browser keeps that key for itself. **H** shows the controls (F1 may
open the browser's help). The browser build always uses the low graphics preset, keeps its save and
settings in that browser, and has no Quit button.

## 8. Project layout

```
data/        JSON content (152 records): abilities, statuses, player, growth, enemies, NPCs, props,
             weapons, items, loot, shrines, progression, quests, dialogue, tutorial prompts, levels,
             encounters, input bindings
scripts/     core (autoloads, data, saves, session) · combat · adapters · actors (+ player components)
             · ai · world (levels, director, props, interactables) · progression · quests ·
             presentation · debug (autopilot, Valley bot, perf probe)
scenes/      generated: main, the giant, enemies, NPCs, world props, the sandbox, the Valley and its
             districts, test levels
ui/          HUD and its widgets, the screen stack and every screen, pad navigation
assets/      materials, shaders, the Valley's navmeshes
tests/       unit/, integration/, slow/, support/, and the runner
tools/       gd.sh, check.sh, run_tests.sh, run_bots.sh, bot_report.py, build_web.sh, the scene
             builders and SceneKit, the Valley layout table, the screenshot tours, probes
web/         launcher.html: the page behind the play link
docs/        spec, plan, architecture, decisions, handoffs, how it plays, performance, usability
```

Gameplay numbers live in `data/` and are validated at startup. Scenes are generated by
`tools/build_scenes.tscn` from the builders in `tools/builders/` (the Valley from
`tools/data/valley_layout.json`); **once you edit scenes in the editor, don't re-run it**, because
it overwrites them. How the code fits together: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Every
interpretation of the spec: [docs/DECISIONS.md](docs/DECISIONS.md).

## 9. Known limitations

- **Placeholder visuals, no audio.** Boxes with procedural animation; no sound; no motion blur.
- **No human has played this build yet**, and it has not run on real hardware: the usability
  sessions, a real gamepad, Windows, real-GPU frame times and real desktop browsers are the owner's
  to run (`docs/USABILITY_SCRIPT.md`, `docs/PERFORMANCE.md`). Everything here was measured in a
  Linux container with a software renderer.
- **Draw calls with many enemies in view.** The static world stays within the 250-per-view budget
  (at most 93 at `low`), but each enemy in full detail costs about 33, so views with five or more
  enemies (the courtyard, the quarry, the return patrol) pass it. Distant enemies beyond the AI's
  far tier already show a one-box proxy.
- **Pacing and balance.** The bot finishes the slice in about 15 minutes of estimated human time
  (target 20-30; it does not explore or learn) and rarely needs a second try at the Ogre King. The
  forest and the ruins' courtyard are where it takes the most damage. `docs/HOW_IT_PLAYS.md` has the
  numbers and what to watch in a playtest.
- **Browser build.** Single-threaded and slower than the desktop build on the same machine; tested
  only in Chromium with software rendering; a gamepad may not be detected inside the hosting page.
- **Physics interpolation is off.** On monitors faster than 60 Hz, bodies move at 60 Hz (mouse look
  stays smooth).
- **Smaller gaps.** Button prompts are text (Xbox names); soldiers fleeing together through an
  opened gate can jam on its narrow path; a yard north of Thornwick's square is outside the giant's
  navigation (the bot backs out; a player can walk out). Stages 4-10, talent trees, more ancestries
  and everything else the plan defers (`docs/plans/M2_M5_PLAN.md` §0.4) are not built.

## 10. More documents

| Document | What it holds |
| --- | --- |
| [docs/M2_M5_HANDOFF.md](docs/M2_M5_HANDOFF.md) | The M2-M5 handoff: changed files, versions, implemented versus deferred, the gate table with evidence, test results, known bugs, the next milestone |
| [docs/HOW_IT_PLAYS.md](docs/HOW_IT_PLAYS.md) | The bot's measured play: times, deaths, damage, growth evidence, what to try first |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | Budgets, tools, commands, container results, the reference-PC and web checklists |
| [docs/USABILITY_SCRIPT.md](docs/USABILITY_SCRIPT.md) | The three-player usability session and the real-controller checklist |
| [docs/BALANCE_LOG.md](docs/BALANCE_LOG.md) | Every tuning change, why, and the matrices before and after |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/DECISIONS.md](docs/DECISIONS.md) | How it is built; every interpretation and deviation |
| [docs/systems/](docs/systems/) | One document per package (P01-P18): APIs, data, decisions, tests |
| [docs/plans/M2_M5_PLAN.md](docs/plans/M2_M5_PLAN.md), [docs/plans/FOLLOWUPS.md](docs/plans/FOLLOWUPS.md) | The M2-M5 plan and the review follow-ups |
| [docs/M1_HANDOFF.md](docs/M1_HANDOFF.md) | The M0/M1 combat sandbox handoff |

## 11. Next milestone

The smallest next step is the owner's **M5 sign-off**: three new players through
`docs/USABILITY_SCRIPT.md`, the real-controller checklist, the reference-PC frame and GPU times of
the Windows export (`docs/PERFORMANCE.md`), and the play link in a real desktop browser. Their
findings become data and tuning changes first (spec §16: fix recurring failures before adding
content), together with a distance level of detail for enemy rigs (draw calls). See the handoff's
last section.

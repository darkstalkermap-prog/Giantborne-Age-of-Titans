# Brief: the character creator (M10)

Planning brief for M10 ("the realistic giant in the game, with a character creator"), written while
M9 runs. Scope: where the creator lives in the game's flows, the options and their data, the 3D
preview and its cost on the Web, the appearance record in the save, the tests, and the look mismatch
between the realistic giant and the stylized world. The asset pipeline (meshes, textures, shaders,
pck budget) is the asset brief's (`briefs/giant_asset.md`); the skinned rig and its driver are the
animation brief's (`briefs/giant_animation.md`). This brief builds on both and does not repeat them.

Tags: **VERIFIED (ran)** = I ran it (a lab, a test in a scratch worktree, a probe, a Web run);
**VERIFIED (code)** = read in the repository at commit 1c33b8e (the integration branch)
and confirmed by grep; **ASSUMED** = reasoning or engine knowledge I did not run;
**RECOMMENDATION** = a design choice for the planner.

Nothing in the repository or in the worktrees was changed. Godot ran in the scratch worktree
`/tmp/m10-creator` (HEAD 1c33b8e, reverted and removed at the end) and in a standalone lab project.
Lab material (all scratch; `CL` = `<scratchpad>/m10_plan/creator_lab`):

| What | Path |
|---|---|
| Creator lab project (prototype creator screen, SubViewport preview, applier, benches, option check, texture-array test) | `<scratchpad>/m10_plan/creator_lab/proj/` (`creator_lab.gd`, `shaders/giant_skin_arr.gdshader`, `tools/probe_*.gd`; the giant glTFs, textures and shaders are a snapshot of the asset research's outputs) |
| Mock-up of the creator at 1280x720 (native and Web) | `<scratchpad>/m10_plan/creator_lab/frames2/ui_stormborn.png`, `<scratchpad>/m10_plan/creator_lab/web_creator_last_frame.png` |
| Looks and options sheet | `<scratchpad>/m10_plan/creator_lab/creator_lab_sheet.png` (every option shot in `<scratchpad>/m10_plan/creator_lab/frames2/`) |
| Per-region designs from one texture array | `<scratchpad>/m10_plan/creator_lab/array_test_sheet.png` |
| Morph artefact | `<scratchpad>/m10_plan/creator_lab/morph_crops.png`, `<scratchpad>/m10_plan/creator_lab/morph_probe.png` |
| Raw numbers | `CL/native_run1.log` (benches), `CL/native_run2.log` (options), `CL/native_run4.log` (texture array), `CL/native_run5.log` (morph probe), `CL/web_run1.log` (Web benches + options), `CL/web_run2.log` (Web options + texture array) |
| Web export of the lab + headless Chromium runner | `CL/web_out/`, `CL/runner/web_creator_run.mjs` |
| Game-code lab files (ran in the scratch worktree, then removed from it) | `<scratchpad>/m10_plan/creator_lab/game_lab/` (`test_m10lab_appearance_save.gd`, `test_m10lab_shrine_tab.gd`, `appearance_tab.gd`, `shrine_screen_tabs.diff`) |

---

## 0. The answer in one page

* **One creator screen, two doors.** A new `CreatorScreen` (ScreenStack `SCREENS["creator"]`) opens
  (a) at New Game, after the existing "replace the saved game?" confirm and the prologue / skip
  choice, before any scene reload, and (b) from a seventh shrine tab, **Appearance**, through a
  "Change your look..." button: the same pattern as the Ancestry tab opening the ancestry screen.
  Back at New Game returns to the title with the save untouched; Back at a shrine reverts the
  preview. Command-line, bot and test New Games never see it (default look). RECOMMENDATION.
* **A seventh shrine tab fits.** VERIFIED (ran) with the real ShrineScreen at 1280x720, level 20, every
  tab offered: the tab row needs 542 px of the 760 px panel, every tab's panel and Leave stay above
  the footer hint, RB visits all seven tabs, `test_ui_focus` passes (127 checks). Three suites
  assert the exact tab list and must be updated (`test_shrine`, `test_shrine_panel_fit`,
  `test_talent_tab`).
* **The save needs no schema bump.** VERIFIED (ran) on the M9 code: a `character.appearance` block
  (887 bytes) survives `SaveSlots.read()` (migrate, validate, sanitize), Continue,
  apply -> capture -> normalize, the next checkpoint write and a death reload; only its numbers come
  back as floats (JSON). A schema 3 file is refused by the M9 build (Continue disabled, kept as
  `valley_1.schema3.rejected.json`). RECOMMENDATION: keep schema 2, store the look as an optional
  key of the character, **absent = the default look** (old saves load unchanged; existing exact
  comparisons of character dictionaries keep passing), sanitize never fails a load over cosmetics.
* **The preview is a SubViewport with its own world.** VERIFIED (ran) natively (Compatibility,
  llvmpipe) and on the Web export (WebGL2 in headless Chromium): the giant renders, all 57 lab
  options render with the same pixel changes on both, applying a whole look costs 0.03 ms native
  and 0.06 ms (p95 0.15 ms) in WebAssembly, the preview draws 26-34 draw calls and 21-25k primitives
  (the game's budget is 250 draw calls a view). At a shrine the world keeps rendering behind the
  screen: `Viewport.disable_3d` on the root while the creator is open cut the root's draw calls from
  677 to 0 and back (VERIFIED (ran)). The first frame with the giant's shaders costs 0.5-3.3 s on
  the software renderers (shader compile): warm the giant up behind the title (RECOMMENDATION).
* **Options for M10** (sized to the asset brief's budget, about 21 MB of 23 MB): 6 hair styles
  (shaved included), 6 beard choices (none and stubble from the skin mask, 4 card meshes), 10 hair colours with a grey slider for hair and
  beard, 10 skin tones, 8 eye colours, 16 tattoo designs over 4 regions (arms, chest, back, face)
  with 6 inks, 4 war-paint designs with 6 colours, 4-6 scar sets, 4-5 outfits from ~12 garments with
  8 dyes, 8 presets, Randomize, and one mark per ancestry unlocked by the choice. **No build or face
  sliders in M10**: a dense shape key costs ~0.34 MB shipped each (asset brief), and every one of
  the four exported morphs puts a dark patch between the brows and under the nose (VERIFIED (ran),
  body-side, cause not found). Height is never a choice (it is the growth stage).
* **One sampler for any number of designs.** VERIFIED (ran) natively and on WebGL2: a
  `sampler2DArray` plus the per-vertex region id (`COLOR.r`, read as a `flat int`) selects one design
  per body region; one RGBA channel can carry designs of two regions; scars come from another layer
  of the same array. So 16+ tattoo designs need one texture sampler, not four.
* **Determinism**: the look never enters the simulation - lives in the character, applied by a
  presentation component, Randomize uses its own `RandomNumberGenerator`, bots and CLI use the
  default; guarded by a code-rule test and a two-process determinism gate test (RECOMMENDATION).
* **Look mismatch**: recommend **both, staged** - in M10 a light "world look" preset of the giant's
  shaders (flatter diffuse, softer normals, palette matched to the world), and a later milestone
  that brings the people near the camera (soldiers, villagers, named NPCs) onto the same body
  pipeline with their stylized rigs kept as the far LOD (§8).
* **Pipeline findings for the asset work** (§9): Pillow's RGBA resize wiped the RGB channels of the
  512 mask textures (the "web lean" set's tattoo/scars/masks were broken); two of the four scar
  channels are empty in the 1024 bake; the morph artefact above.
* **Effort**: the creator alone is about 2 days (data and saves 0.5, screen and preview 1, shrine
  tab, portraits and gates 0.5) on top of the asset and animation work; inside a 2-3 day milestone
  that only fits as the MVP of §10 (ASSUMED).

---

## 1. What exists today

### 1.1 Flows and screens - VERIFIED (code)

* `main.gd`: `GameSession.mode == TITLE` builds a ScreenStack with the title screen only (no level,
  no HUD, nothing 3D). Every mode change is a reload of `main.tscn`.
* `TitleScreen` (`ui/screens/title_screen.gd`): New Game asks once more when a save exists ("New
  Game: replace the saved game?"); when the saved game finished the prologue and the world exists it
  shows "Play the prologue" / "Skip to the Old Kingdom" instead. Each path ends in
  `_start(mode, {"new_game": true})`, which on the Web sets `Input.mouse_mode = CAPTURED` inside the
  click ("browsers grant pointer lock only inside a click") and emits `Events.mode_change_requested`.
  `pauses_game()` is false; the title never closes on Esc / pad B.
* `GameSession._begin_new_valley()` / `_begin_new_world()` build `character` from
  `CharacterState.new_game()` / `world_start()`; `on_level_ready` applies it to the player and takes
  the first checkpoint. Command-line starts (`--mode=valley --new-game`, `--mode=world`, the bots,
  `start_world_for_tests`) go straight there.
* `ScreenStack`: `SCREENS` is a pre-declared name -> path table (a missing file opens nothing);
  while any screen is open the input context is MENU and the mouse is visible; a screen that
  `pauses_game()` pauses the tree; the footer hint ("D-pad / left stick: move  A: select  B: back")
  sits in the bottom 30 px (y 690-712 at 720 p).
* `ShrineScreen`: a 760x580 panel lifted 16 px, a row of tab buttons from the pre-declared `TABS`
  list (Rest, Grow, Loadout, Attributes, Talents, Ancestry; a tab's `available()` can hide it), then
  the tab, then Leave; LB / RB switch tabs. The Ancestry tab's "Choose X..." opens the ancestry
  screen on top and reacts to its `closed(result)` - the pattern the Appearance tab copies.
* `GameSession` re-takes a shrine's checkpoint at once when `talent_learned`, `ancestry_chosen`,
  `attributes_changed` or `loadout_changed` fire while a shrine's screen is open (M8 gate F15).
* Where the giant's look could show: the end screen (680x460 frame, "Prologue complete" / "The Giant
  King" lines), the title's save line (`describe_save`: "Saved game: level 3, stage 2, at the Grove
  Shrine, ..."), the pause menu (Resume / Load / Quit; the world is visible behind its shade). No
  screen or HUD widget draws the giant today.

### 1.2 Focus rules (P16) - VERIFIED (code)

A screen lists `focus_rows()` (rows top to bottom, each left to right); `UiNav.link_rows` wires
neighbours with wrap-around and skips hidden / disabled controls; `first_focus()` is where the focus
lands; `UiNav.keep_focus` puts a lost focus back every frame; pad A / B are added to `ui_accept` /
`ui_cancel`; LB / RB come from `UiNav.page_step`. The ancestry screen moves "focus = preview"
(`focus_entered` selects the ancestry shown) and never starts on its permanent Choose button.

### 1.3 Saves - VERIFIED (code + ran)

`SaveSlots` (schema 2): `read()` = `SaveIO.read_json` (main, else the one `.bak`, newer versions
refused and kept aside) -> `migrate()` (one pure step per version) -> `validate()` (structural; a
failing main falls back to the backup) -> `sanitize()` (unknown ids dropped with "Dropped ids this
build does not know: ..."). `CharacterState.sanitize` keeps keys it does not know ("Unknown keys are
kept as they are"), and `GiantPlayer.apply_character_state` keeps the whole applied dictionary as
`_state_passthrough`, which `capture_character_state()` starts from - so a later build's key survives
an older build. The lab (`game_lab/test_m10lab_appearance_save.gd`, 12 checks, 0 failures) ran this
on the real flow test level - VERIFIED (ran):

| Path | `character.appearance` (887-byte block in a 2,537-byte save) |
|---|---|
| `SaveSlots.write` -> `validate(migrate())` | no problems |
| `SaveSlots.read()` | kept, no message |
| title -> Continue -> `on_level_ready` (apply, capture, normalize) | kept |
| next checkpoint written to disk | kept |
| death -> reload | kept |
| numbers | come back as floats (`"v": 1` -> `1.0`): normalize must cast |
| the same file at `schema_version` 3 | `read()` ok=false, "valley_1.json was written by a newer version (schema 3; this build supports 2). It was kept as valley_1.schema3.rejected.json."; title Continue disabled |

---

## 2. Where the creator lives (RECOMMENDATION unless marked)

### 2.1 New Game

```
Title ── New Game ──┬─ (save exists) "replace the saved game?" ── New Game again ─┐
                    ├─ (prologue finished) Play the prologue | Skip to the Old Kingdom ┤
                    └─ (no save) ─────────────────────────────────────────────────────┤
                                                                                       v
                        CreatorScreen {context: "new_game", start: {mode, options}}
                         Back / Esc / pad B  -> closes, title as it was, save untouched
                         "Begin your journey" (prologue) / "Begin in the Old Kingdom" (skip)
                               -> TitleScreen.start_game(mode, options + {"appearance": record})
                               -> GameSession: character = new_game()/world_start() + appearance
                               -> reload, first checkpoint writes the save (as today)
```

* The creator sits on the title's stack (`pauses_game()` false: nothing runs), so the title's own
  state (the prologue / skip buttons, the confirm) is still there after Back.
* **Web pointer lock**: Begin must start the game in its own pressed handler through the title's
  `_start` path (make it public as `start_game(mode, options)`), as the title's buttons do today; a
  start deferred to a later frame would lose the click (VERIFIED (code) comment; the lock itself on
  the creator path is ASSUMED to behave like the title's).
* `GameSession.change_mode` passes `options.appearance` to `_begin_new_valley(start, appearance)` /
  `_begin_new_world(start, appearance)`; `--appearance=<preset id>` on the command line (optional)
  lets tools and capture tours start with other looks.
* Bots, `--mode=valley --new-game`, `--mode=world`, tests and the sandbox: no creator, the default
  look (absent key). The sandbox's shrine has the Appearance tab for manual checks.

### 2.2 Shrines

* `ShrineScreen.TABS` gets `["Appearance", "res://ui/screens/shrine/appearance_tab.gd"]` last
  (a hotspot edit; the lab put it there - VERIFIED (ran) to fit, §6.2). The tab shows a short text,
  a summary of the look (Hair: long, chestnut, a little grey / Beard: full / Marks: woad knotwork on
  the arms; a scar over the left brow / Clothing: wanderer's braies, undyed) and **Change your
  look...**, which opens `SCREENS["creator"]` with `{context: "shrine", player, shrine, appearance}`.
* The creator pauses (it opens over the paused shrine screen), sets the root viewport's
  `disable_3d` while it is on top and restores it on close (§4.3).
* **Keep this look** closes with `{"appearance": record}`; the tab calls
  `player.set_appearance(record)`, which emits a new `Events.appearance_changed(tick, entity_id)`;
  `GameSession` adds it to the F15 list, so the shrine's checkpoint is re-taken and written at once.
  **Cancel** / Esc / B reverts the preview and closes with `{"cancelled": true}`. Free, any number of
  times, any shrine, any stage.

### 2.3 Old saves

A save without the key gets the default look (§5). A one-time HUD line or tutorial prompt at the
first shrine after loading such a save ("Your giant's look can now be changed at any shrine:
Appearance tab") tells the player; a flag stops it repeating (ASSUMED wording).

### 2.4 Elsewhere

| Place | Recommendation | Cost |
|---|---|---|
| End screen ("The Giant King", "Prologue complete") | a portrait of the giant (current look and stage, `GiantPreview` drawn once) beside the lines; the frame widens to ~900 px | one render; the giant is already loaded in the level (ASSUMED) |
| Title, saved-game line | optional: the saved giant as a live figure beside the menu (right of the 760 px panel there are 260 px at 1280x720), loaded one frame after the title shows; it also warms the giant's shaders for the creator | measured in the lab: loading the giant's scenes and materials took 37-54 ms native and 247-671 ms in WebAssembly, the first frame 0.46-3.3 s native and 1.3-2.0 s on the Web's software renderer (VERIFIED (ran)); real GPUs are faster (ASSUMED) |
| Pause menu | nothing: the giant is in view behind the shade; the menu stays light | 0 |
| HUD, map | nothing | 0 |

---

## 3. The options and their data

### 3.1 Catalogue for M10 - RECOMMENDATION, sized to the asset brief's budget

The asset brief measured the shipped cost (gzip + base64, as `build_web.sh` counts) and proposes
"6 hair styles + 5 beards, 16 tattoo designs, 4 scar sets, ~12 garments" for about 21 MB of 23 MB.
The creator should present exactly that, plus what costs nothing (shader parameters):

| Category | Options | How (asset brief's shaders) | Shipped cost |
|---|---|---|---|
| Presets | 8 (§3.4) | records | 0 |
| Skin | 10 tones (pale to deep, plus weathered and a grey "ashen") | `skin_tone` ratio to the bake | 0 |
| Eyes | 8 iris colours | `giant_eye` `iris_color` | 0 |
| Hair | 6 styles: shaved, crop, long combed back, long braided, warrior tail, wild mane | one card mesh each, `visible` | ~0.06-0.19 MB each (asset brief) |
| Beard | none, stubble (mask only), short, full, braided, forked | card meshes; stubble via the mask | ~0.05-0.11 MB each |
| Hair colour | 10 (black ... white), one palette for hair, beard and brows; beard can differ; **grey** slider 0-1 for hair and beard each | `hair_color`, `tip_color`, `grey` | 0 |
| Tattoos | 16 designs, 4 regions (arms, chest, back, face), at most one per region; 6 inks (woad, soot, ochre red, chalk, moss, iron) | design array layer + channel per region (§3.5) | ~10-20 KB per layer |
| War paint | 4 designs (face stripes, brow band, hand prints, full face) and 6 colours; on top of tattoos | same array, "paint on top" flag | idem |
| Scars | 4-6 sets, any combination (at most 4) | scar layer, `scar_on` | ~2-6 KB |
| Clothing | 4-5 outfits from ~12 garments (wanderer: braies + belt; hunter: + furs + bracers; warrior: tunic + jerkin + boots + bracers; chieftain: furs + jerkin + boots), primary and secondary dye from 8 | `visible`, `dye`, `hidden_regions` | garments ~0.05-0.16 MB each (asset brief's rates) |
| Ancestry mark | 1 per ancestry (§3.3) | design layer | ~0 |

Left out of M10, with reasons:
* **Build / face sliders**: a shape key is stored dense, ~0.34 MB shipped each on the 14.5k-vertex
  body (asset brief); and the lab's four exported morphs (`jaw_wide`, `brow_heavy`, `nose_broken`,
  `lean`) each put a dark patch between the brows (and under the nose) at weight 1, with and without
  hair and beard - VERIFIED (ran), `morph_crops.png`, `morph_probe.png`. The shape data looks sane
  (largest offset 1.0-2.5 cm, 118-1,497 vertices moved per shape, normals present and not flipped,
  no vertex moved by every shape - VERIFIED (ran) probe); the cause is not found. Hair cards would
  also not follow a head morph. Later: a separate head mesh with small shape keys (asset brief's
  idea, ASSUMED ~0.07 MB per key) once the artefact is understood.
* **Height**: the giant's height is the growth stage (hurtboxes, camera, reach); never a slider.
* **Age wrinkles**: needs normal-map variants; greying covers "age" in M10.
* **A name**: no dialogue or screen uses one.

### 3.2 Records - RECOMMENDATION

Two new record types, each with a schema module (`appearance_set_schema.gd`,
`appearance_preset_schema.gd`) and a pre-declared entry in `DataValidator.SCHEMA_PATHS` (a hotspot
edit, like P20's for M7-M9):

* `appearance_set` - one file per category under `data/appearance/` (~12 files: skin, eyes, hair,
  beard, haircolor, tattoo, ink, paint, paintcolor, scar, outfit, dye, mark). A set lists options
  `{key, name, ...category fields, "requires": {"ancestry": id}?, "default": true?}`; an option's id
  in saves is `<category>.<key>` (`hair.long_back`). Category fields: hair/beard `mesh` (node name in
  the giant scene), `scalp_tint` / `beard_tint` / `stubble`; palettes `color` (+ `tip` for hair);
  tattoo/paint/scar/mark `layer`, `channel`, `region`, `paint`; outfit `parts`, `hide_regions`,
  `dye_slots`. Options are data; the asset builder's manifest (mesh names, layers) is checked against
  them by a unit test.
* `appearance_preset` - one file per preset: `display_name`, `description`, a full `appearance`
  record, optional `ancestry` (a suggestion only).

Palettes instead of free colour pickers: every combination stays readable in the world's light,
pads can step through swatches, saves hold ids (validated, retunable), not raw RGB.

### 3.3 Ancestries - RECOMMENDATION

Each ancestry unlocks one mark when chosen (the P33 ancestry schema gets an `appearance_mark` field
at an M10 anchor):

| Ancestry | Mark | Also unlocked |
|---|---|---|
| Stoneblood | "granite veins": grey-blue vein pattern over shoulders and forearms | the "ashen" skin tone |
| Stormborn | "lightning tree": a branching scar over back and arm | "storm-lit" eyes (pale iris, slight emission) |
| Wildheart | "claw stripes": three dark bands across chest and cheek | "amber" eyes |

The record's `mark` is `"auto"` by default: the mark shows as soon as the ancestry is chosen (the
look is re-resolved on `ancestry_chosen`, no save write needed) and a HUD line names it; the player
can set `"none"` at any shrine. Before the choice (the prologue, the Valley) the creator shows the
marks locked: "Choose your line at a shrine of the Old Kingdom".

### 3.4 Presets and Randomize - RECOMMENDATION

* Presets (8): **The Wanderer** (default: the owner-approved render - long brown hair, full beard,
  braies), Stone Elder, Storm Herald, Wild Hunter, Iron Veteran, Young Giant, Ash Raider, Northern
  Chieftain. A preset fills every field; editing afterwards makes the look "custom" (the record keeps
  `preset` for the summary only).
* **Randomize** (pad Y): a private `RandomNumberGenerator` seeded from the clock (never `Sim.rng` or
  `Sim.rng_for`, which seeded runs replay); weighted towards natural combinations (natural hair
  colours 90 %, at most two tattoo regions, paint 30 %); it keeps the outfit unless the Clothing tab
  is open (ASSUMED rule).
* **Reset**: back to the look the screen opened with (shrine) or the default preset (New Game).

### 3.5 Designs per region from one texture array - VERIFIED (ran)

The asset brief's skin shader holds 4 designs per RGBA texture with `tattoo_on` per channel; 16
designs that way are four textures and four samplers. The lab's `giant_skin_arr.gdshader` instead
uses one `sampler2DArray` and the region id the export already writes into the body's vertex colour:

```
varying flat int v_region;                        // vertex(): v_region = int(COLOR.r * 16.0)
uniform sampler2DArray design_tex;                // RGBA layers of designs (tattoos, paint, scars)
uniform int region_design[12];                    // per region: layer * 4 + channel, -1 none
uniform vec4 region_ink[12];                      // rgb ink or paint colour (linear), a = paint on top
```

Results, chest view, native and Web (`web_run2.log`) agree within 1 %:

| Check | Changed pixels [left half, right half] |
|---|---|
| per-region path vs the four-channel path, same three designs | visually the same; 6,246 px differ (line darkness: mipmaps and colour handling) |
| three designs vs none | [2,241 spiral, 5,508 arm bands + chevrons] |
| chest region set to -1 | [2,241, 0]: only the chest design went |
| one channel holding the arm bands **and** the chest spiral, only the arm region using it | [0, 3,024]: the spiral did not appear |
| ... then the chest region too | [2,241, 0] |
| scars from layer 1 of the same array | 522 px |

Also VERIFIED (ran): the imported vertex colours store region `id + 0.41...0.52` (x16), so
`int(COLOR.r * 16.0)` is right for all 12 regions (rounding would turn region 4 into 5); uniform
arrays cannot have default values in Godot 4.6.3 shaders ("Setting default values to uniform arrays
is not supported") - the applier must fill `region_design` with -1. RECOMMENDATION: tattoos, paint,
marks and scars all live in one design array; 4 regions x 4 channels = 16 designs per RGBA layer.

---

## 4. The preview

### 4.1 Design - RECOMMENDATION

`GiantPreview` (`ui/screens/creator/giant_preview.gd`, a `SubViewportContainer` with `stretch`):
* a `SubViewport` with `own_world_3d`, MSAA 2x on desktop / off on the Web preset, its own
  `WorldEnvironment` (dark backdrop, ambient), a key light with shadows, a cool rim light, a stone
  disc to stand on;
* the giant built from the same scene and the same `AppearanceApplier` as the in-game giant, so the
  preview can never disagree with the game; the idle clip from the animation package (breathing),
  the current weapon in the hand at shrines;
* an orbit camera (yaw free, pitch -20...+20 degrees, distance from full body to face) with
  **framing per category**: Hair, Beard, Eyes, War paint -> face; Tattoos -> the region of the
  focused design (arm, chest, back, face); Skin, Clothing, Presets -> full body. The lab shows why:
  an eye colour changes 126-135 pixels in a 720x544 face view and an arm tattoo 216-342 pixels in a
  full-body view (VERIFIED (ran)) - invisible unless the camera goes there;
* controls: mouse drag / wheel; pad right stick / LT-RT; keys Q/E and +/- (ASSUMED bindings);
  view buttons Full / Face / Back;
* `render_once()` (`UPDATE_ONCE`) for portraits (end screen, title).

### 4.2 Cost - VERIFIED (ran)

Lab: the asset research's giant (body, eyes, long hair, full beard, braies, belt: 38,548 triangles
loaded; the preview's frame counted 21-25k primitives, LODs and the shadow pass included), its shaders, a 720x544 preview in a
1280x720 window. Natively Mesa llvmpipe (software GL) on a 4-CPU box at load ~8; on the Web headless
Chromium with SwiftShader (software WebGL2). **Both rasterize on the CPU**, so frame intervals show
relative cost only; real-GPU frame times were not measured.

| Measure | Native (llvmpipe) | Web (WASM + SwiftShader) |
|---|---|---|
| load the giant's scenes and build its materials | 37-54 ms | 247-671 ms |
| first frame with the giant (shader compile) | 3,305 ms first run, 460-660 ms later (shader cache) | 1,291-1,987 ms |
| apply a whole look (200 random records) | mean 0.03 ms, p95 0.05 ms | mean 0.06 ms, p95 0.15 ms |
| preview draw calls / objects | 26 (base look), 34 (random looks), 28 full screen | same |
| preview render submission (RenderingServer measured CPU) | (rasterizes in-call) | 0.38-0.49 ms typical |
| frame interval: no preview / drawn once / 720x544 every frame / full screen | 29 / 30 / 221-229 / 329 ms | 149 / 287 / 432-694 / 1,030 ms |
| options rendered without errors, pixels changed as expected | 57 of 57 (§7.3) | 57 of 57, same counts within 1 % |

Reading: the preview is a small scene (26-34 draw calls against the game's 250 per view, a giant
already budgeted by the asset brief at 3-11 calls); its per-frame CPU cost on the Web is about half
a millisecond of submission; its fill cost doubles from 720x544 to full screen (SwiftShader 432 ->
1,030 ms). RECOMMENDATION: keep the preview to its 720x544 area (not a full-screen backdrop), redraw
it every frame only while the creator is on top (`UPDATE_WHEN_VISIBLE`), and let portraits draw once.

### 4.3 The world behind a shrine's creator - VERIFIED (ran)

A stand-in world in the root viewport (220 boxes, a sun with shadows: 677 draw calls in the lab)
behind the creator:

| Root viewport | Root draw calls | Web frame interval (mean) |
|---|---|---|
| 3D on | 677 | 524 ms |
| `disable_3d = true` | 0 | 428 ms (-18 %) |
| 3D back on | 677 | 503 ms |

The creator's opaque full-window background hides the world anyway, so it should switch the root's
3D off while it is on top and back on when it closes (and when another screen comes on top). With
that, the creator at a shrine costs what it costs at the title. The simulation is paused there, so
nothing moves meanwhile (VERIFIED (code): the shrine screen pauses).

### 4.4 Shader warm-up - RECOMMENDATION

The first frame with the giant's materials stalls (above). On Continue the level's loading screen
hides it; at New Game the creator would open with a stall. Warm up behind the title: one frame after
the title shows, instantiate the giant in a hidden 64x64 SubViewport (or the optional title figure,
§2.4) and keep it cached, as the M8 work warmed world scripts behind the loading screen.

---

## 5. Saves

### 5.1 The record - RECOMMENDATION

```json
"appearance": {
  "v": 1,
  "preset": "appearance_preset.wanderer",
  "skin": "skin.ruddy",
  "eyes": "eyes.grey_green",
  "hair": {"style": "hair.long_back", "color": "haircolor.chestnut", "grey": 0.12},
  "beard": {"style": "beard.full", "color": "", "grey": 0.2},
  "tattoos": {"arms": "tattoo.arms_knotwork", "chest": "", "back": "", "face": "", "ink": "ink.woad"},
  "paint": {"design": "", "color": "paintcolor.chalk"},
  "scars": ["scar.brow_left"],
  "mark": "auto",
  "outfit": {"set": "outfit.wanderer", "primary": "dye.undyed", "secondary": "dye.dark_leather"}
}
```

* It lives in the character (`CharacterState`), beside talents and the ancestry; not in
  `PROGRESSION_KEYS` (the bots compare those across reloads).
* **Absent means the default look.** `Appearance.resolve(character)` returns the explicit record or
  the default preset, then applies `mark: "auto"` for the chosen ancestry. The creator writes the full
  record; nothing else writes it. Consequences: old saves and fixtures load unchanged; the exact
  comparisons of whole characters in today's suites keep passing (VERIFIED (code):
  `test_save_migration` lines 78 and 233, `test_session_flow` line 225, `test_world_start` line 164);
  CLI and bot runs carry no record at all.
* `beard.color` "" = the hair's colour; one ink for every tattoo (the shader allows one per region
  later at no cost).

### 5.2 Schema, migration, validation - RECOMMENDATION (on VERIFIED behaviour)

* **Keep `SaveSlots.SCHEMA_VERSION` = 2.** The key is additive and optional; the 0.9 build keeps it
  through every path (§1.3), while a schema 3 file would lock 0.9 players out of Continue (§1.3).
  Document the key in the SaveSlots header ("schema 2; M10 adds the optional character.appearance").
  The record has its own `"v"` for its own migrations, like the world block's `schema_version`.
* **Migration** of existing saves: none needed - absent = default (plus the ancestry mark if the save
  has chosen one, by `resolve`).
* **Sanitize** (`Appearance.sanitize`, called by `CharacterState.sanitize` for the key):
  `"v"` cast to int; each id checked against its set - unknown -> the category default, reported in
  the existing "Dropped ids this build does not know: ..." message; an option whose `requires` does
  not hold (a mark without its ancestry) -> default, reported; a tattoo in the wrong region -> "";
  scars unique, known, at most 4; numbers clamped 0-1; unknown keys inside the record kept (a later
  build's additions survive, as for the character).
* **Validate** never rejects a save for the look: a malformed block (not a dictionary, wrong types)
  is repaired by sanitize to the default with a message ("Your giant's look could not be read; the
  default look is used.") - a cosmetic must never send the player to the backup or refuse the save.
* **Backups**: nothing new. SaveIO's one `.bak` is the previous valid save; a shrine change writes a
  checkpoint (F15 rule) so the previous file becomes the backup. Cancel in the creator restores the
  look in memory without a write.

### 5.3 Determinism - RECOMMENDATION

* The look is applied by a presentation component (`PlayerAppearance`, a `PlayerComponent` whose
  `apply_state` / `capture_state` move the record, and an `AppearanceApplier` node under `Visual`)
  outside `Sim` ticks; changes happen only in menus (title: no level; shrine: paused).
* No simulation code reads it: a code-rule test (`tests/unit/test_appearance_rules.gd`) greps
  `scripts/combat`, `scripts/ai`, `scripts/world`, `scripts/core/sim.gd` and the actor components
  other than `PlayerAppearance` for `appearance` and fails on a hit (the project's anchor tests do
  similar greps).
* Randomize uses its own RNG (§3.4); the default look for every automated run.
* A gate test runs two child processes of the same seeded autopilot run (the pattern of
  `tests/gate/test_world_determinism.gd`) with `--appearance=` two very different presets and
  requires byte-identical `AUTOPILOT_RESULT` lines without the wall-time fields.

---

## 6. The screen: layout and controls

### 6.1 Layout at 1280x720 - VERIFIED (ran) as a mock-up, RECOMMENDATION as design

`frames2/ui_stormborn.png` (native) and `web_creator_last_frame.png` (Web) - every region inside the
window and above the stack's footer hint:

```
y 10   Shape your giant      New Game - you can change all of this later at any shrine
y 52   [Presets][Skin][Eyes][Hair][Beard][Tattoos][War paint][Scars][Clothing]   (the mock's ten tabs, Build included, end at x ~585)
y 96   +------------------- preview 720x544 -------------------+ +---- options 512x544 ----+
       |                                                       | | Hair                     |
       |                 the giant (orbit, zoom)               | | Style   < Long, combed > |
       |                                                       | | Colour  [■][■][■]...[■]  |
       | [Full][Face][Back]                                    | | Grey    [---|------]     |
y 640  +-------------------------------------------------------+ +--------------------------+
y 648  [Randomize] [Reset] [Presets...]                      [Back]  [Begin your journey]
y 690  footer hint (ScreenStack)  D-pad: move  A: select  LB/RB: category  R-stick: turn  ...
```

* Larger sizes keep the 720x544 preview centred-left and grow the panels (anchors), as the HUD does.
* The stack's footer is generic; the creator's extra controls (LB / RB, right stick, triggers, Y
  randomize, X view) need either a `UiScreen.footer_hint()` the stack appends (one small hotspot edit
  in ScreenStack / UiNav) or a hint line of the creator's own above y 690 (RECOMMENDATION: the former).

### 6.2 The shrine with seven tabs - VERIFIED (ran)

`game_lab/test_m10lab_shrine_tab.gd` on the real ShrineScreen (scratch worktree; level 20, stage-5
shrine, ancestry not chosen, a minimal `appearance_tab.gd` added to `TABS`):

* tabs: Rest, Grow, Loadout, Attributes, Talents, Ancestry, Appearance; tab row minimum width
  **542 px** in the 760 px panel; panel at (260, 54) 760x580, inside the room above the hint
  (1280x690); every tab's panel and Leave inside; RB visits all seven tabs;
* `test_ui_focus`: 127 checks, 0 failures; `test_ancestry_choice`: 57 / 0; `test_shrine_choices_saved`:
  41 / 0;
* to update in M10: `test_shrine.test_shrine_screen_rest_and_grow_tabs` and
  `test_shrine_panel_fit.test_every_tab_and_the_ancestry_screen_fit_at_level_20` (exact tab lists),
  `test_talent_tab.test_the_talents_and_ancestry_tabs_with_a_pad` (exact list, and "LB twice from
  Rest" now lands on Ancestry, not Talents).

### 6.3 Pad, keyboard and mouse (P16) - RECOMMENDATION

* `focus_rows()`: [category tabs] + the category's rows + [Randomize, Reset, Presets, Back, Begin];
  wrap-around everywhere; LB / RB = previous / next category (`UiNav.page_step`); `first_focus()` =
  the category's first row, never Begin.
* Row kinds: **swatch rows** (a row of colour buttons; moving the focus previews the colour, like the
  ancestry screen's row; A keeps it), **cycler** (one focusable control showing "< Long, combed back
  >" that consumes left / right while focused - a one-control row's own neighbours are itself, so
  nothing is lost), **sliders** (`HSlider` takes left / right natively), **toggles** (scars).
* Every swatch has a name (label under the row: "Chestnut"); locked options show why (ancestry).
* Mouse: everything clickable; drag and wheel on the preview. Keyboard: arrows / Tab / Enter / Esc
  as everywhere, Q/E turn, +/- zoom.

---

## 7. Tests - RECOMMENDATION (the lab is the prototype of the rendered check)

### 7.1 Unit (default tier, < 0.3 s together)
* `test_appearance_record.gd`: the default record from data; `resolve()` (absent -> default; mark
  "auto" with and without an ancestry; "none"); `sanitize()` (unknown ids -> defaults and the dropped
  list; requires; wrong region; scars unique and <= 4; numbers clamped; `"v"` cast from 1.0; unknown
  keys kept; non-dictionary -> default + message); `random_record()` for 1,000 seeds always valid and
  `Sim.rng`'s state unchanged; presets all valid.
* `test_appearance_schemas.gd`: the two schema modules reject bad sets (unknown category, duplicate
  keys, a missing default, a design layer/channel used twice in one region, a palette without
  colour); every option's `mesh` / `layer` exists in the giant builder's manifest.
* `test_save_migration.gd` / `test_save_slots.gd` additions: v1 and v2 fixtures load with no record
  and resolve to the default; a record with unknown ids loads with the message; a record round-trips
  exactly through write / read.
* `test_appearance_rules.gd`: the grep rule of §5.3.

### 7.2 Integration (default tier, ~1 s together)
* `test_creator_screen.gd`: from the title - New Game (no save) -> creator -> Begin: one reload,
  `GameSession.character.appearance` = the chosen record, the right mode (Valley; with a finished
  prologue, the skip choice -> world); Back returns to the title with the save file unchanged
  (byte-compare); with a save, the confirm comes first. Pad: LB / RB through all categories, D-pad
  through every row (`UiNav.link_rows` keeps every control), A on a swatch, B backs out, the focus is
  never lost after a category switch or Randomize.
* `test_appearance_apply.gd`: every option of every set applied to the real giant scene without an
  engine error (the runner turns errors into failures) and changing what it should (mesh
  visibility, the shader parameter, `region_design`); growth to stage 4 keeps the look; first person
  hides head, hair and beard (layer 2 / the body's hidden regions, animation brief §6).
* `test_shrine_appearance.gd`: the tab is offered; Change your look opens the creator over the
  shrine; Keep applies to the player, emits `appearance_changed`, re-takes and writes the shrine's
  checkpoint; Cancel restores; Continue after quitting restores the same look on the live materials;
  a death reload keeps it; the root viewport's 3D is off while the creator is open and on after.
* Layout: `test_creator_layout.gd` at 1280x720, 1366x768, 1600x900, 1920x1080, 2560x1440 (the HUD
  test's sizes): every panel, button and the preview inside the window and above the footer hint,
  none overlapping; plus the three shrine suites of §6.2 updated to seven tabs.

### 7.3 Slow (rendered, Xvfb child process)
`tests/slow/test_appearance_render.gd`, in the pattern of `test_rig_draw_calls` / `test_world_build`
(a child Godot under `xvfb-run` with `--rendering-driver opengl3`, skipped with a note without
xvfb-run): render every option once in its framed view against the base look and require (a) no
engine or shader error, (b) changed pixels above a floor per category in the framed view, (c) a
non-blank frame. The lab did exactly this: 57 options and 8 looks in 49-78 s at 720x544 with 2
llvmpipe threads on a busy box (VERIFIED (ran)); at 360x272 it should fit the slow tier's 8-minute budget
easily (ASSUMED). It already caught two broken options: the "forearm slash" and "knuckle nick" scars
changed 0 pixels (empty channels, §9).

### 7.4 Gate and Web
* Gate: the determinism pair of §5.3.
* Web: extend the existing Web check (`tools/web/world_check.mjs` family): boot, New Game ->
  creator -> preview renders (screenshot, no console errors) -> Begin -> the Valley loads; the lab's
  runner (`CL/runner/web_creator_run.mjs`) shows the harness shape.

---

## 8. The look mismatch

What the owner will see: the asset research's world frame (`giant_asset/frames/world_front_medium.png`)
puts the realistic giant among box soldiers, crates and cone trees; the gap is obvious up close, as
the owner was told. Options:

| Option | What | Cost | Effect |
|---|---|---|---|
| A. Humans next | Soldiers, villagers, archers, riders, named NPCs on the same body pipeline (lighter MakeHuman bodies, outfits per faction, hair cards only near), stylized rigs kept as the far LOD and in crowds | a milestone: assets per archetype, a CPU cost per skinned actor on the Web (animation brief: ~0.07-0.1 ms each with several on screen), pck growth | closes the gap where it is seen most (fights within ~30 m); today's rig is ~6 draw calls each (VERIFIED (code), PERFORMANCE.md after P22), a skinned human with 2-3 garments is about as many (ASSUMED) |
| B. Stylize the giant a little | A "world look" preset of the giant's shaders: wrap diffuse without transmission, normal strength ~0.5, palette pulled toward the world's vertex colours, softer specular | ~0.25 day (the shaders already have `light_model` and the parameters, VERIFIED (ran) in the lab) | narrows the gap, keeps the owner's realistic giant |
| C. Both, staged | B in M10 (as a setting "Giant style: Realistic / World", default Realistic, so the owner can compare in game), A as the next milestone | B now, A later | best result per day |
| D. World materials | textured terrain, props, buildings | the largest | the long-term fix; after A |

**RECOMMENDATION: C.** It honours the owner's choice now (realistic giant, the default), gives them a
one-click comparison in game, and puts the human upgrade where the mismatch is most visible next.

---

## 9. Findings for the asset pipeline - VERIFIED (ran)

1. **The 512 "web lean" masks were broken by the resize.** Pillow 13.0.0 resizing an RGBA image with
   LANCZOS works on premultiplied alpha: the 1024 tattoo mask became [0, 0, 0, 477] lit texels per
   channel at 512 instead of [460, 946, 899, 477] (per-channel resize). The same hit `masks.png`
   (scalp channel 0 instead of 34,511) and `scars.png`. Resize mask channels one by one ("L" mode) or
   keep them at full size; the asset brief's B-set sizes for masks/scars/tattoo at 512 are for the
   broken files (the corrected 512 PNGs are 33.6 / 1.9 / 10.6 KB - still small).
2. **Two of four scar channels are empty** in the 1024 bake: G "forearm slash" has one texel above 0
   (64/255), A "knuckle nick" 32 texels (4 above 5/255); in the render they change 0 pixels.
3. **Any of the four exported morphs** at weight 1 darkens a patch between the brows and under the
   nose, body-side (§3.1).
4. Region ids in `COLOR.r` decode correctly with `int()`, not `round()` (§3.5).

---

## 10. Work split, MVP and open points

### 10.1 Packages - RECOMMENDATION (effort ASSUMED)

| Package | Content | Effort |
|---|---|---|
| C1 data and saves | `Appearance` (pure: default, resolve, sanitize, random, summary), 2 schema modules + `SCHEMA_PATHS`, `data/appearance/` sets and presets, `CharacterState` hook, `Events.appearance_changed`, unit tests | 0.5 d |
| C2 creator and preview | `GiantPreview`, `AppearanceApplier` (shared with the rig package), option row controls, `CreatorScreen`, title and `GameSession` New Game path, `SCREENS["creator"]`, root `disable_3d`, warm-up, integration tests, layout test | 1 d |
| C3 shrine and gates | Appearance tab + F15 checkpoint, old-save hint, end-screen portrait, slow rendered check, determinism gate, Web check, docs | 0.5 d |

Dependencies: C2 needs the giant scene, its shaders (with the design array) and its manifest from
the asset / rig packages; it can start on the lab's snapshot. Hotspots touched: `screen_stack.gd`
(SCREENS), `shrine_screen.gd` (TABS), `title_screen.gd`, `game_session.gd`, `events.gd`,
`character_state.gd`, `data_validator.gd`, `ui_screen.gd` / `ui_nav.gd` (footer hint).

### 10.2 MVP if the milestone's 2-3 days are tight - RECOMMENDATION
Must: New Game creator, shrine tab, presets, Randomize, hair / beard / colours / grey / skin / eyes /
tattoos / paint / scars / outfits / dyes, saves (§5), unit + integration tests, the slow rendered
check. Can wait: ancestry marks, end-screen portrait, title figure, the world-look setting, the
determinism gate (the grep rule covers the risk meanwhile).

### 10.3 Risks
* Real-GPU and real-browser frame times of the preview are unmeasured (both labs rasterized in
  software); the first-frame shader stall on the Web is real (1.3-2.0 s on SwiftShader).
* Option content is bounded by the pck budget: the asset brief asks the owner whether the Web budget
  may rise to 26 MB; with 23 MB the hairstyle list is capped as in §3.1.
* Hair cards are "good game cards" (asset brief); a closer creator camera shows their limits more
  than gameplay does - frame the face shots at a distance that flatters them.
* The visible weapon in the preview depends on the rig package's hand placement.

### 10.4 Questions for the owner
1. Raise the Web budget to 26 MB for more hairstyles and garments (asset brief), or keep 23 MB?
2. Ancestry marks automatic on the choice (removable at shrines), or offered only?
3. The "World" style setting for the giant (option C) - worth having as a comparison switch?

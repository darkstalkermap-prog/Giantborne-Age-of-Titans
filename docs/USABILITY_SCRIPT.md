# Giantborn usability script (spec §16, plan §5.5)

This script is for the human usability gate and the real-controller check of milestone M5. A
facilitator runs it with three new players and records the results on the sheets below. It takes
about 30 minutes per player.

| Item | Status |
| --- | --- |
| Usability sessions with 3 new players (spec §16) | **NOT RUN** (the owner runs them) |
| Real-controller checklist (§6 below) | **NOT RUN** (the owner runs it) |
| Synthetic controller pass (every menu by pad events) | Automated: `tests/integration/test_ui_focus.gd` |
| HUD layout at 1280 x 720 and 1920 x 1080 | Automated: `tests/integration/test_hud_layout.gd` |

The recommended owner checkpoints after waves 1 and 8 (plan §1.3) use the same sheets (§4 and §5).

## 1. What the gate asks

Spec §16: "Ask at least three new players to complete the Sandbox. At least two should complete
the tutorial encounter without developer intervention and correctly identify heavy attacks,
blocking, and dodge timing. Record confusion, camera discomfort, accidental ability use, and time
to defeat."

The tutorial encounter is **Giant's Hollow plus the first wolf pack** (decision 28). Giant's Hollow
holds the practice dummies, the sparring post and the `quest.tutorial` stages `awaken` (camera),
`train` (light x3, heavy, Heavy Footfall on the dummies) and `spar` (block or parry the post's
swing, then dodge it). The first wolf pack is `encounter.forest_wolves_a` on the trail north of the
Hollow (`quest.main` stage `wolves`). The Sandbox has its own sparring post for free play.

**Pass:** at least 2 of 3 players
1. finish the Hollow stages `train` and `spar` and survive or defeat the first wolf pack, with no
   developer help (a hint from the facilitator counts as help; the game's own prompts do not), and
2. answer the three identification questions of §3.3 correctly.

## 2. Setup (before each session)

- **Build.** A Windows export (`Giantborn.exe`) or the editor's run of `main.tscn`. Note the build
  version shown on the title screen (bottom line) on the sheet.
- **Fresh state.** Delete the save and settings so every player starts the same way:
  `%APPDATA%\Godot\app_userdata\Giantborn\saves\` and `settings.json` (Windows), or start with
  `-- --save-dir=user://usability_<name>` for a separate slot per player.
- **Devices.** A mouse and keyboard, and an Xbox-layout controller (XInput) plugged in before the
  game starts. Ask each player which they prefer; aim for at least one controller player among the
  three. The game switches its button prompts to whichever device was used last (Settings >
  Button prompts: Auto).
- **Screen.** 1920 x 1080 if possible (the HUD is also checked at 1280 x 720). Sound is not part of
  the prototype.
- **Recording.** Optional screen and face recording, only with consent. Keep a clock running from
  the moment the player first sees the title screen.
- **Facilitator.** One person, seated behind the player, with this script printed. Do not explain
  the controls beyond the opening sentence in §3.1.

## 3. Session protocol (about 30 minutes)

### 3.1 Opening (2 minutes)

Read aloud: "You play a giant that grows during the game. Please think aloud: say what you are
trying to do and what you expect to happen. I cannot help you while you play; if you are completely
stuck, say so. There are no wrong answers - we are testing the game, not you."

Let the player choose keyboard and mouse or the controller.

### 3.2 Part A: Sandbox free play (5 minutes)

1. From the title, choose **Sandbox** (keyboard, mouse or pad: the menu starts with the focus on a
   button).
2. Let the player explore for 5 minutes. The arena holds soldiers, a wolf pack, practice dummies,
   a breakable fence, a growth shrine (E to open) and the sparring post (it swings at the giant and
   never fights back).
3. Note anything from the observation sheet (§4): especially camera discomfort, attacks or
   abilities used by accident, and how the player finds the controls (F1 / H opens the controls
   table; on a pad the pause menu's Controls page lists them).
4. At 5 minutes: Esc or Start, **Quit to title**.

### 3.3 Part B: the first 10 Valley minutes (10 minutes)

1. From the title, choose **New Game**. Start the clock for the tutorial encounter.
2. The player starts in Giant's Hollow. Watch the TIP panel (left of centre) and the objective
   tracker (top right). Do not read them out.
3. Record the time each of these happens (or "not reached"):
   - `awaken`: the camera switched to first person and back;
   - `train`: three light attacks, a heavy attack and Heavy Footfall on the dummies;
   - `spar`: a block or parry and a dodge against the sparring post;
   - leaving the Hollow north (`leave_hollow`);
   - the first wolf pack defeated or escaped (`wolves`), and every death on the way.
4. Stop at 10 minutes, or earlier when the first wolf pack is done.
5. Ask the three identification questions and write the answers verbatim:
   - **Heavy attacks:** "How do you make a heavy attack, and what is it good for?" (Correct: names
     the heavy input - Shift + left mouse or RT - and that it is slower but harder, breaks guards or
     staggers.)
   - **Blocking:** "How do you block, and when does a block become a parry?" (Correct: names the
     block input - right mouse or LB - and that pressing it just as the blow lands parries.)
   - **Dodge timing:** "When should you dodge?" (Correct: as the strike lands, not as soon as the
     enemy starts its windup; the red telegraph fills up, then dodge.)

### 3.4 Post-session questionnaire (5 minutes)

Hand over §5. The player fills it in alone.

## 4. Observation sheet (one per player)

| Field | Player 1 | Player 2 | Player 3 |
| --- | --- | --- | --- |
| Name / initials, date | | | |
| Device chosen (KBM / pad), switched mid-session? | | | |
| Prior experience (action games, souls-likes) | | | |
| Build version (title screen) | | | |
| **Part A** confusion points (time, place, what) | | | |
| Part A camera discomfort (clipping, nausea, lost framing, first person vs third) | | | |
| Part A accidental ability use (which slot, how: number key, LT combo) | | | |
| Part A menus: found the controls? pause menu, shrine screen with the chosen device | | | |
| **Part B** time to `awaken` / `train` / `spar` | | | |
| Part B time to leave the Hollow / finish the first wolf pack | | | |
| Part B deaths (time, killer) and time to the first defeat | | | |
| Part B confusion points (time, place, what) | | | |
| Part B camera discomfort | | | |
| Part B accidental ability use | | | |
| Telegraphs: did the player react to the red decals and the edge arrows? | | | |
| Hotbar: did the player read the cost, cooldown or "Out of range" / "Stage 2" reasons? | | | |
| Developer interventions (time, what was said) | | | |
| Identification: heavy attack (verbatim, correct?) | | | |
| Identification: block and parry (verbatim, correct?) | | | |
| Identification: dodge timing (verbatim, correct?) | | | |
| **Tutorial encounter completed unaided?** (§1 rule 1) | | | |

## 5. Post-session questionnaire

Rate 1 (strongly disagree) to 5 (strongly agree):

1. I always knew what my giant was doing (attacking, blocking, dodging, recovering).
2. I could see enemy attacks coming in time to react.
3. The camera showed me what I needed in fights.
4. The camera never made me feel uncomfortable or sick.
5. Attacks felt heavy and powerful.
6. I understood when I could block, parry and dodge.
7. I never triggered an ability I did not mean to.
8. The menus were easy to use with my device (keyboard and mouse, or controller).
9. The on-screen prompts showed the right buttons for my device.
10. I knew where to go next.

Open questions:

- What was the most confusing moment?
- What would you change first?
- Did growing (or the promise of growing) feel different from an ordinary character?
- Would you keep playing? Why or why not?

## 6. Real-controller checklist (owner)

Run once on a real Xbox-layout pad (and, if available, a PlayStation pad through Steam Input or
the OS driver). Tick each line; note the pad model and the OS.

| # | Check | Pass? |
| --- | --- | --- |
| 1 | Title: the first button has the focus at start; D-pad and left stick move it; it wraps from the last entry to the first and back; disabled entries (Continue without a save) are skipped; A presses; B leaves Settings / Controls. | |
| 2 | The menu footer (bottom centre) reads "D-pad / left stick: move  A: select  B: back" after any pad input, and "Arrows / Tab: move  Enter: select  Esc: back" after a key or the mouse. | |
| 3 | Start opens the pause menu; up from Resume reaches the page tabs; LB / RB switch Main / Settings / Controls; B or Start resumes. | |
| 4 | Settings: up / down walk every row; left / right move sliders; A opens an option list, D-pad picks, A confirms, B closes only the list. Button prompts: Controller pins pad glyphs. | |
| 5 | Controls: A on a controller binding starts a capture; the next pad button becomes the binding; without input the capture gives up after 6 s; Esc on the keyboard cancels it. Reset all bindings restores LT + A..D-pad combos. | |
| 6 | In game: the interact prompt shows the pad button ("[X] Rest at the ..."), the hotbar shows the LT combos large, TIP texts name pad buttons. A key press switches them all back to the keyboard. | |
| 7 | Shrine (X near a shrine): Rest, Grow, Loadout, Attributes tabs by LB / RB and by the tab row; a loadout list opens with A and closes with B; + / - and Confirm on Attributes; B leaves. | |
| 8 | Dialogue (X near the elder): choices by D-pad, A chooses, B leaves; numbered keys still work. | |
| 9 | Inventory (Back): Close focused; Equip and Attributes reachable; B closes. | |
| 10 | Forge: Reforge then the focus moves to Leave; B leaves. | |
| 11 | Death screen: A loads the last checkpoint (Valley) or restarts the sandbox. | |
| 12 | End screen (after the crown): Continue exploring focused; Quit to title reachable. | |
| 13 | Combos: LT + A / B / X / Y and LT + D-pad fire slots 1-8 and never jump, dodge, interact or switch the camera; LT + RT is the ultimate, not a heavy. | |
| 14 | Lock-on: right-stick press locks; a right-stick flick switches targets; vibration follows the Controller vibration slider (0 = none). | |
| 15 | Web build (play link): the title takes pad input after the browser has seen one button press (browsers hide pads until then); the camera works with the right stick without clicking; the "Click the game" hint does not show for a pad player. | |

## 7. Reporting

- Copy the filled sheets (§4, §5 and §6) into `docs/USABILITY_RESULTS.md` (one section per
  session date), with the build version and the device of each player.
- Write the verdict: **PASS** when §1's rule holds (2 of 3), else **FAIL** with the recurring
  problems.
- Turn every problem seen with two or more players into a follow-up in
  `docs/plans/FOLLOWUPS.md` (owner: the package that owns the data or the screen). Spec §16: fix
  recurring failures before adding content.
- Until the sessions run, the M5 usability and real-controller gates stay **NOT RUN** in the
  handoff (P18).

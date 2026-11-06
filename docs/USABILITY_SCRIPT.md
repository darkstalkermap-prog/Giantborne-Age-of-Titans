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
| Audio sheet (§8: the owner's listening pass, M6) | **NOT RUN** (the owner runs it) |
| Music and ambience behaviour (layers, variants, rests, crossfades, ducks, beds, spots) | Automated: `tests/integration/test_music_valley.gd`, `test_ambience_valley.gd`, `test_audio_zones.gd`; the web build: `tools/web/audio_check.mjs` |

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
  `%APPDATA%\Godot\app_userdata\Giantborn- Age of Titans\saves\` and `settings.json` (Windows), or start with
  `-- --save-dir=user://usability_<name>` for a separate slot per player.
- **Devices.** A mouse and keyboard, and an Xbox-layout controller (XInput) plugged in before the
  game starts. Ask each player which they prefer; aim for at least one controller player among the
  three. The game switches its button prompts to whichever device was used last (Settings >
  Button prompts: Auto).
- **Screen.** 1920 x 1080 if possible (the HUD is also checked at 1280 x 720).
- **Sound.** On since M6 (headphones or speakers at a comfortable level; Settings > Audio at its
  defaults). The usability sessions do not judge the sound; the owner's listening pass is §8.
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

## 8. Audio sheet (owner, M6)

The owner's listening pass of the Valley's sound (plan M6-M9 §6.6, P23): once on headphones and
once on laptop or desk speakers, at one fixed system volume, with Settings > Audio at its defaults
(Master volume 100 %, Music 80 %, Ambience 80 %, Effects 100 %, Interface 80 %). Allow 30-40 minutes. Tick or note
each line; the pieces are described in `docs/systems/P23.md` (music, stingers, ambience) and
`docs/systems/P21.md` (effects). Every file also plays on its own from `assets/audio/`.

**Where to listen.** Title (leave it for 4 minutes: the theme rests after 3); New Game; Giant's
Hollow (stand still 2 minutes, then train at the dummies); north into the Old Wood (wolves); the
Grove Shrine; Thornwick and the fields; the King's Bridge over the river; the Raider Quarry; the
Barrow and the ruins; Kingsfall and the Ogre King (both phases); the end screen. The sandbox
(Title > Sandbox) plays the Hollow's music over a meadow.

### 8.1 Loudness balance

| # | Check | Headphones | Speakers |
| --- | --- | --- | --- |
| 1 | The music sits under the effects: a hit, a footfall and a threat sting are always clearer than the melody. | | |
| 2 | The ambience is felt more than heard: you notice it when it changes (the Hollow's wind to the Wood's leaves, Thornwick's murmur, the stone districts' cold wind), not while it plays. | | |
| 3 | No district is clearly louder than the others (the beds are balanced at the same loudness; the stone bed has the deepest rumble). | | |
| 4 | Combat lifts the level without a jump: the drums and brass come in over two beats, the combat intro plays once on the next beat, then the music sits about 5 dB higher than exploring (danger, the pulse, is no louder than exploring). | | |
| 5 | The Ogre King's music is as loud as a district fight and grows about 1.5 dB in phase 2: the string tremolo should add tension, not just volume. | | |
| 6 | Stingers (level up, quest, growth, victory) duck the music by 8 dB and the music comes back within half a second after them; nothing stacks into a wall. | | |
| 7 | The interface blips are quieter than the world and never startle. | | |

### 8.2 Harshness

| # | Check | Headphones | Speakers |
| --- | --- | --- | --- |
| 8 | No piece is shrill or fizzy at your listening level: the flute's breath (the Old Wood), the cricket spot, the danger pulse's shaker, the boss frenzy's strings. Note the worst one. | | |
| 9 | No click or thump where a loop wraps (the drones and beds loop every 30 s and 20 s) or where a melody switches variant (at 10 s, 20 s, 30 s). | | |
| 10 | The low end is full on headphones and not boomy on speakers (taiko, the King's drums, the stone bed's rumble, the forge fire). | | |
| 11 | Spots (lark, crow, owl, dog, hammer, cart, pebbles, howl) sound like part of the place at 10-35 m, not like effects next to you. | | |

### 8.3 Threat readability

| # | Check | Headphones | Speakers |
| --- | --- | --- | --- |
| 12 | With the music playing, a wolf lunge, an archer's draw and an ogre's windup from behind are heard and turned to in time (the off-camera sting cuts through the combat layer). | | |
| 13 | The danger pulse (a frame-drum heartbeat) starts when something hostile has noticed you and you know why it started. | | |
| 14 | The music does not tell you "combat" when nothing is attacking (after a fight it holds 6 s, then eases back to danger, then exploring). | | |

### 8.4 Music fatigue

| # | Check | Notes |
| --- | --- | --- |
| 15 | In the Hollow for 5 minutes: the lute melody rotates between its three variants, rests for one to three loops (30-90 s) between phrases, and never plays the same variant three times running. Does it stay pleasant or start to nag? | |
| 16 | After 3 minutes of quiet exploring (no fight, no discovery) the music fades out for 1-2 minutes and comes back. Is the silence welcome, too early, too long? | |
| 17 | The three districts sound like three places of one valley (the same chords and tempo; lute, low flute and horn melodies), not three unrelated pieces. Which set would you change first? | |
| 18 | Crossing between districts the music changes at a bar line over two bars: smooth, or noticeable? | |
| 19 | The title theme (four minutes on the title screen) and the end screen: fitting, or does the title loop wear? | |

### 8.5 The world (M7)

The world's sound (P28; the pieces are described in `docs/systems/P28.md`). **Where to listen:**
down from the Kingsgate shelf into the Crownmarch's fields; Brannock at stage 4 (enter, leave,
enter again), Brannock Bridge over the Wend, Millford's mill race, the Wend Falls; the Greywood
(Hollowmere's pond, the Troll Den); the Drowned Steps (the Mere's shore, wading, the Titan's
Bones); Aldmere (the war camp's forge, a pike formation marching and bracing); the Stonehold
(Skarn's hearths, the Moot). Use F6/F7 (debug growth) for stages 4-6.

| # | Check | Notes |
| --- | --- | --- |
| 20 | Each region sounds like its own place in one kingdom: the Crownmarch's fiddle over open fifths, the Greywood's reed over a dark choir, the Drowned Steps' bells over a glassy pad, Aldmere's trumpet calls (and a field drum in combat), the Stonehold's enormous horn over a wide choir - on the Valley's chords and tempo. Which set would you change first? | |
| 21 | Crossing a region line the music changes at a bar line over two bars and the beds over three seconds; Brannock, Hollowmere and Skarn keep their region's music with the melody quieter and resting longer; the Moot plays only its drone until Harrok. Smooth, or noticeable? | |
| 22 | Entering Brannock (or Millford, Hollowmere) at stage 4 or more: one gasp of the crowd and the town bell, once a visit, not again when you step out and back in. Welcome, or too much? | |
| 23 | The place beds fit their places and none is louder than the region around it: the town's market, carts and smithy; the camp's drums, canvas and hammers; the giants' hearth and deep voices; the den's drips and slow breath; the wind through the Titan's ribs; the Moot's humming stones. | |
| 24 | The emitters sit where they are and fade with distance, without a seam: the Wend under Brannock Bridge, the Millrace, the Wend Falls, Hollowmere's pond (frogs), the Mere's shore, the war camp's forge, Skarn's hearths, the Titan Forge in the Bones. | |
| 25 | A pike formation advancing is one march (stomps in step, a field drum) that moves with it, not thirty scattered footsteps; when it braces you hear one low wall rumble per brace, not one per pike. | |
| 26 | Wading the Wend or the Mere: heavy wet steps and one splash on entering deep water, no splash spam at the bank. | |
| 27 | At stage 6 among fleeing soldiers the music stays at exploring (no pulse, no sting); a formation or a troll still raises it. | |
| 28 | The giant's stage 4-6 footfalls grow heavier and lower with each stage and soften on long walks; a size gate answers with water, stone or timber where you touched it. | |
| 29 | The world's stingers: a discovery's bells, the world's reveal from the Kingsgate shelf and the Stair's head, a rout's brass flourish (fleeing armies sound triumphant). Note any that feels too big or too small. | |
| 30 | Later content (M8-M9, as it arrives): the troll's grunts and roar, the dire wolf, the cavalry's gallop swell and the horse, the rival giants' bellow (not the player's roar), the Matriarch, a catapult's release at the engine and its rising whistle ending where the stone lands, the bosses' music, the crowning. | |

### 8.6 Focus and the web

| # | Check | Notes |
| --- | --- | --- |
| 31 | Alt-tab away (desktop) or switch to another browser tab (web): the sound fades out within a fifth of a second and comes back when you return (Settings > Mute when unfocused). | |
| 32 | Web: the first click on the page starts the sound (the launcher resumes the browser's audio); no sound before it, no crackle after it on a mid-range laptop. | |
| 33 | Web: music keeps playing without gaps while the frame rate drops (heavy fights in the forest, a formation fight in the world). Note any gap. | |

Write the results under the session in `docs/USABILITY_RESULTS.md` and turn every "change this"
into a follow-up for the sound packages (P21 effects, P23 music and ambience, P28 the world's).

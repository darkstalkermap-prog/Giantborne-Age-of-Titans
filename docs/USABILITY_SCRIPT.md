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
| World sheet (§9: finding the way - the map, pins, the compass, fast travel, sealed places; M7) | **NOT RUN** (the owner runs it); the rules automated: `tests/integration/test_map_screen.gd`, `test_compass.gd`, `test_discovery.gd`, `test_fast_travel.gd`, `test_tracked_quest.gd`, `test_journal.gd` |
| Usability sessions with the world (M9: §3.5 Part C and §10 - twenty minutes of the world from the Kings' Door, after the Valley's first ten minutes) | **NOT RUN** (the owner runs them with three players) |
| The world's music and ambience on speakers and headphones (§8.7, M9) | **NOT RUN** (the owner's listening pass) |
| Real browsers (§11, M9: load time with the multi-part pack, streaming hitches, a Continue and a fast travel, audio in a hidden tab) | **NOT RUN** (the owner's); the container's headless Chromium runs automated: `tools/web/world_check.mjs` (a Continue of a world save, a fast travel, a 60 s walk across region borders), `stream_check.mjs --world --audio`, `audio_check.mjs`, `world_start_check.mjs` - software WebGL, indicative only |
| Real gamepad: the map, journal, track and pin bindings (§6 rows 16-21, M9) | **NOT RUN** (the owner runs it); the bindings automated: `tests/integration/test_map_screen.gd`, `test_journal.gd`, `test_tracked_quest.gd`, `test_ui_focus.gd` |

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
- **The world (M9, Part C).** Part C starts from a save made just after the crown, so every player
  meets the world at the same place: the Kings' Door behind the crown's altar, standing open. Make it
  once per player before the session with the Valley bot (about 8 minutes, unattended), which plays the
  Valley to the crown and writes its checkpoints into the player's own save slot (a few minutes
  headless):
  `Giantborn.console.exe --headless --fixed-fps 60 -- --no-user-settings --save-dir=user://saves
  --mode=valley --new-game --scenario=valley --bot-village=help_cache --bot-skill=novice --bot-assist
  --bot-seed=1 --autoplay=1800` (the run ends at the crown, `"finish_reason": "completed"` in its
  `AUTOPILOT_RESULT` line; without `--headless --fixed-fps 60` it plays in real time). Keep a copy of
  `saves\valley_1.json` and put it back before each player's Part C (Part B's New Game replaces it).
  The title's Continue then wakes the giant at the Kingsfall shrine with the Kings' Door open.

## 3. Session protocol (about 30 minutes; about 55 with M9's Part C)

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

### 3.5 Part C (M9): twenty minutes of the world from the Kings' Door (20 minutes)

After Part B and a short break (the questionnaires of §5 and §10.2 are filled in at the very end):

1. Quit to the title, put the crowned save back (§2), and choose **Continue**. Start the clock when
   the giant stands at the Kingsfall shrine. Say only: "The Valley is behind you now. Go on as you
   like for twenty minutes."
2. Do not point at the Kings' Door, the map or the compass. The tracker reads "Step through the Kings'
   Door" and the objective marker leads there; note how long it takes to find it.
3. Watch for the moments of §10.1 and write their times: the door, the first view from the Kingsgate
   shelf (the world's reveal), the first map, the first pin, the beacon and the growth to stage 4 at
   the Kingsgate shrine, the first formation met at stage 4, the first sealed place seen, the first fast
   travel. A player who never travels: after 15 minutes ask once, "Is there a quicker way back to the
   shelf?" and note the answer (a prompt counts as help on the sheet).
4. Stop at 20 minutes. Ask, and write verbatim:
   - **The view:** "What did you see from the shelf, and where did you decide to go?"
   - **The way:** "Where would you go next, and how would you get there?" (Answered from the map and the
     compass alone?)
   - **Formations:** "How did the soldiers in a block fight differently from the ones on their own?" (Correct:
     names one of the group lock or its banner, the braced wall that takes no blows from the front, the
     rout when the banner falls.)
   - **Sealed places:** "What was the place with the lock on the map, and what does it need?" (Correct: a
     larger growth stage.)

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
| 16 | **M9, the world's bindings on a real pad.** In the Old Kingdom: D-pad Down opens the map and pauses the game; D-pad / left stick move between places, the right stick pans, LB / RB zoom, A chooses a place (a visited waystone or shrine: the focus moves to Travel, A again travels), B closes. The panel's control line names the pad's buttons. | |
| 17 | Y on the map pins the place in focus (or the map's centre); the compass shows the red pin after the map closes; Clear pin (focus it, A) removes it; the pin is still there after loading the game again. | |
| 18 | D-pad Right opens the journal (one page: quests, waiting quests, completed quests, oaths, sealed places, regions) and pauses the game: D-pad up / down walk its Track buttons and Close, the page scrolls with the focus, A on Track follows that quest ("Tracked"), B closes. | |
| 19 | D-pad Left (no screen open) cycles the tracked quest: "Tracking: <quest>" shows, and the tracker, the compass's gold diamonds and the objective marker follow it. | |
| 20 | With LT held, the D-pad fires slots 5-8 and never opens the map or the journal or changes the tracked quest; released, D-pad Down / Right / Left work again at once. | |
| 21 | The web build with the pad: the map, journal, track and pin buttons above work in the browser too (after one button press), and the map's travel loads the world again with the pad still in charge. | |

## 7. Reporting

- Copy the filled sheets (§4, §5 and §6; since M9 also §10 for Part C, and the owner's §8.7 and §11)
  into `docs/USABILITY_RESULTS.md` (one section per session date), with the build version and the
  device of each player.
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

### 8.7 The world's music and ambience on speakers and headphones (M9)

The listening pass of plan §6.7 for the whole Old Kingdom as M9 ships it (P28's sets with M8's peoples,
bosses and engines): once on headphones and once on laptop or desk speakers, at one fixed system
volume, Settings > Audio at its defaults; about 45 minutes a device. Start in the world with a save
from the world bot or your own (`Giantborn.exe -- --mode=world --new-game` and F6 / F7 for the stages
work too). **Where to listen** (fast travel between the stones once reached): the Kingsgate shelf (the
reveal, then stand 4 minutes); down the King's Road to Brannock and the King's Road waystone; south
into the Drowned Steps (the Mere's shore, a bell); west into the Greywood (Hollowmere, the troll den's
mouth); east into the Aldmere March (the war camp, Fort Aldmere's walls); up the Ironway into the
Stonehold (Skarn, the Moot). Fight at least once in each region, once a formation, once with an
engine shooting, once a mounted charge. Tick each line for each device and note the place.

| # | Check | Headphones | Speakers |
| --- | --- | --- | --- |
| 34 | **Balance across the regions.** No region's music or bed is clearly louder than the others; crossing a border nothing jumps (the music over two bars at a bar line, the beds over three seconds). Note the loudest and the quietest place. | | |
| 35 | **Effects over the world's music.** A footfall at stage 4-6, a pike wall's brace, a catapult's release and whistle, a ballista bolt, a rider's charge and a troll's roar stay clearer than the melody and the beds, in the music's combat layer too. | | |
| 36 | **Harshness.** No world set is shrill or fizzy at your level: the Crownmarch's fiddle, the Greywood's reed, the Drowned Steps' bells, Aldmere's trumpet and field drum, the Stonehold's horn and choir, the bosses' sets (the Matriarch, Harrok, the Iron Regiment's battle). Note the worst one. | | |
| 37 | **The low end.** The stage 5-6 footfalls, the Stonehold's horn, the war camp's drums and the engines' impacts are full on headphones and not boomy on speakers. | | |
| 38 | **Threat readability.** From behind and off camera: a formation's march, an engine winding, a cavalry charge's swell and an archer's draw are heard and turned to in time; you can tell the danger pulse (noticed) from combat. | | |
| 39 | **The melody rotation.** Stay 5 minutes in each of two regions without fighting: the region's melody rotates between its variants, rests one to three loops between phrases and never plays one variant three times running. Pleasant, or nagging? | | |
| 40 | **The silence windows.** After about 3 minutes of quiet exploring the music fades out for 1-2 minutes and comes back (in the world as in the Valley); the place beds carry the silence. Welcome, too early, too long? | | |
| 41 | **Fatigue over a session.** After 45 minutes, which set would you mute first, and which would you keep? Does the world's music still feel like the Valley's kingdom (the same chords and tempo)? | | |
| 42 | **Settlements and places.** Brannock, Millford, Hollowmere, Skarn: the region's music quieter with the place's bed under it; the Moot: its drone until Harrok; the troll den, the Titan's Bones, the war camp: their beds without a seam at their edges. | | |
| 43 | **The bosses.** The Matriarch, Harrok and the Iron Regiment's battle: their music enters on a bar, its phases lift without a jump, and the end (a death, a yield, a rout, a flight) closes it with its stinger and back to the region's music. | | |
| 44 | **The web build** (the play link, same route, same device): no crackle, no music gap at a fast travel's loading screen or while chunks stream in (note any gap and where); the sound fades out in a hidden tab and comes back. | | |

Write the results under the session in `docs/USABILITY_RESULTS.md` and turn every "change this"
into a follow-up for the sound packages (P21 effects, P23 music and ambience, P28 the world's).

## 9. World sheet: finding the way (owner, M7)

The open world's wayfinding (plan M6-M9 §3.10, P27; `docs/systems/P27.md`): the map, pins, the
compass, discovery, fast travel, the tracked quest, the journal and sealed places. Run it twice -
once with a pad, once with the mouse and keyboard - about 20 minutes each, with a new player if one
is at hand (the facilitator rules of §3 apply: no help beyond the game's own prompts). Start in the
Old Kingdom: `Giantborn.exe -- --mode=world --new-game`, or on the title New Game > "Skip to the Old
Kingdom" with a save that finished the prologue. Tick each line for each device; note what confused.

| # | Check | Pad | Mouse and keyboard |
| --- | --- | --- | --- |
| 1 | Soon after arriving a TIP names the map's button; the map opens (M / D-pad Down), pauses the game, and the TIP goes away. | | |
| 2 | The map reads at a glance: where you stand and face (the white arrow), places found (bright squares) and seen from a vista (dim), waystones and shrines (blue; bright once reached), exits, sealed places (a lock and "Stage N"), the pin (red), the quest's gold diamonds; land not yet seen lies under a dark fog. | | |
| 3 | Moving around the map: D-pad / left stick between places, right stick pans, LB / RB zoom, A chooses, Y pins, B closes - or arrows between places, W A S D or dragging pans, the wheel or - / = zooms, Enter chooses, P or a right click pins, Esc or M closes. The panel lists the controls of the device in use. | | |
| 4 | A place chosen: its name, its region with the recommended stages (orange when you are below them), and what it is (reached or not, found, seen from afar, sealed with its stage). | | |
| 5 | Pin a spot and close the map: the compass shows the red pin; it is still there after loading the game again; Clear pin removes it. | | |
| 6 | The compass (top centre) turns with the camera: N E S W, gold diamonds for the quest you track (several when a step has several places), marks for the nearest known places, "?" for something unexplored nearby (a landmark on the skyline from farther away). Ask what each mark means. | | |
| 7 | Walking into a new place: "Discovered: <name> +XP" shows top left once; from a vista the places around appear on the map and the line says how many. | | |
| 8 | Crossing into a region: its name shows top centre with "Recommended stage N-M", in orange when you are below it. | | |
| 9 | Fast travel: on the map, a waystone you reached > Travel: the game loads and you stand there. Try one you have not reached ("You have not been there yet.") and with an enemy hunting you close by ("Not while enemies are close."): is the reason clear, and where did the player look for it? | | |
| 10 | T / D-pad Left: "Tracking: <quest>" shows; the tracker's first line, the compass's diamonds and the objective marker follow it. | | |
| 11 | The journal (J / D-pad Right): quests with their step, objective and region; waiting quests say what they wait for; completed quests; oaths; sealed places with the stage they need; each region's note. Track from the journal (D-pad and A, or a click) changes the followed quest. | | |
| 12 | A sealed place seen for the first time: a TIP explains it, "Sealed: <name> (grow to stage N)" shows, the map marks it with a lock and the journal lists it. | | |
| 13 | With LT held, the D-pad still fires slots 5-8 and never opens the map or the journal or changes the tracked quest. | | |
| 14 | Ask: "Where would you go next, and how would you get there?" The player answers from the map and the compass alone. | | |

Write the results under the session in `docs/USABILITY_RESULTS.md`; every line two or more players
miss becomes a follow-up for P27's screens and widgets in `docs/plans/FOLLOWUPS.md`.

### 9.1 Region notes: the Greywood and the Drowned Steps (owner, M8)

Start at stage 4 in the Old Kingdom (`--mode=world --new-game`, then grow at a shrine or with the
debug panel) and fast travel to the Hollowmere waystone, then the Mere south waystone. Tick each line;
note what confused.

| # | Check | Pad | Mouse and keyboard |
| --- | --- | --- | --- |
| 1 | Walking into the woodcutters' camp a TIP explains fire; smashing the bonfire or the brazier beside a troll sets it burning (no green pulse while it burns). Does the player connect the fire to the trolls' healing? | | |
| 2 | Sedge stands among Hollowmere's huts near the green (on the green at stage 5-6); her oath offers slay or drive, and the den's marker leads to the troll den. | | |
| 3 | In the den: three nests with a brazier beside each; smashing a brazier burns its nest; 20 s after the last nest the woodfolk pull the back wall down (a HUD line says so); below 60 % the Matriarch runs out through it. At stage 5 "Heave the wall aside" opens it at once. Is the drive-out understood without the journal? | | |
| 4 | Back at Sedge the oath is sworn; Hollowmere's lanterns are lit on the next visit. | | |
| 5 | The Needle: at stage 4 the giant fits the slot; at stage 5 the sign says it has outgrown it, and the map's sealed rockfall on the grove's north ridge is the other way in. | | |
| 6 | Wenna at her landing names the five bells; the compass's diamonds lead to the nearest unrung bell; the fourth bell (the Wend's deep reach) needs stage 4, the island's stage 5; the Stoneknuckles' rack opens once all five ring. | | |
| 7 | The Titan Forge stays cold while the scavengers are there ("Light the Titan Forge" says why); once lit it titanforges a reinforced weapon. | | |
| 8 | The causeway's rockfall will not move below stage 5; behind it the vault, its cache and cairn. | | |

## 10. World session sheet (owner, M9): twenty minutes from the Kings' Door

Part C of the session (§3.5), one column per player, the same three players as Parts A and B. The
moments are what plan §6.7 asks the sessions to look at: the view, finding the way, the map, the compass,
pins, fast travel, formations at stage 4 and a sealed place. Write a time (from the Continue) or "not
reached", and what the player said or did.

### 10.1 Observation

| Field | Player 1 | Player 2 | Player 3 |
| --- | --- | --- | --- |
| Device in Part C (KBM / pad), switched? | | | |
| **The Kings' Door**: found it (time); how (the tracker, the marker, the compass, by chance) | | | |
| **The view** from the Kingsgate shelf: stopped to look? turned the camera? what they named (the beacon, the King's Road, a far landmark) | | | |
| **Finding the way**: the beacon reached (time); the route taken (the ramp and the road, cross-country); lost or turned back (where) | | | |
| **The compass**: used it (looked up at it, said "the diamond")? the gold diamonds and a "?" understood? | | | |
| **The map**: first opened (time, by the TIP or alone); found where they stood; moved between places, zoomed | | | |
| **Pins**: set one (time)? followed it on the compass? cleared it? | | | |
| **Stage 4**: grew at the Kingsgate shrine (time); noticed the size (the camera, the road, the folk fleeing) | | | |
| **Formations at stage 4**: first block met (where: the toll fort, a pike column on the road, the war camp); locked the group or a member; hit a braced wall from the front and stopped; went for the banner; a rout seen | | | |
| **A sealed place**: first seen (which; the TIP, the map's lock and "Stage N"); tried to open it; understood it needs growth | | | |
| **Fast travel**: first use (time, from where to where); a refusal seen ("You have not been there yet.", "Not while enemies are close.") and understood; asked at 15 minutes (§3.5 step 3)? | | | |
| Deaths (time, what) and confusion points (time, place, what) | | | |
| Camera at stages 4-5 (trees, the ground, framing a formation) | | | |
| Developer interventions (time, what was said) | | | |
| The four questions of §3.5 step 4 (verbatim; the formation and sealed-place answers correct?) | | | |

### 10.2 Questions after Part C

Rate 1 (strongly disagree) to 5 (strongly agree):

1. Leaving the Valley felt like a reward: the view made me want to explore.
2. I always knew where to go next in the world.
3. The map was easy to read and to use with my device.
4. The compass told me where things were without opening the map.
5. Fast travel was there when I wanted it, and I understood when it was not.
6. Fighting a block of soldiers felt different from fighting soldiers one by one, and I knew how to break it.
7. I understood why some places were sealed and when I could come back.
8. Growing to stage 4 changed how the world felt.

Open questions: What did you most want to do when you first saw the world? What made you stop or turn
back? What would you change first?

Write the results under the session in `docs/USABILITY_RESULTS.md`. A moment two or more players miss, or
a question most rate 2 or less, becomes a follow-up in `docs/plans/FOLLOWUPS.md` (owners: P27's map,
compass, journal and fast travel; P30's formations; P25's and the regions' places and sealed places).

## 11. Real browsers (owner, M9)

The play link in real browsers on real machines (plan §6.7): Chrome or Edge, Firefox and Safari (macOS or
iPadOS with a keyboard), on a mid-range laptop with its own GPU and on a low-end one. The container's
checks run headless Chromium with software WebGL, so their frame times and music holes are the CPU's
rasterising (indicative only; `docs/systems/P39f.md`, "Part web"); these runs are the real ones. Clear the
site's data before each browser (a fresh profile) and keep the browser's task manager open.

| # | Check | Chrome / Edge | Firefox | Safari |
| --- | --- | --- | --- | --- |
| 1 | **Load time with the multi-part pack**: from Play to the title's music (the meter counts the engine and the pck's two parts in one bar); then New Game to the Hollow. Write both times and the connection. | | | |
| 2 | **Continue a world save**: play into the Old Kingdom, reach a waystone, quit to the title, reload the page, Continue: the giant stands where the save was. Time from Continue to control. | | | |
| 3 | **Fast travel**: from the map to a waystone 500 m or more away; the loading screen's time; the music goes on (no gap, or note it). | | | |
| 4 | **Streaming hitches**: walk 60 s across a region border (the King's Road waystone south into the Drowned Steps, then east into the Aldmere March, as `tools/web/world_check.mjs` walks): stutters where the ground ahead loads? Note each and where. | | | |
| 5 | **Frame rate**: steady in the open, in Brannock, in a formation fight and at a battle (the Iron Regiment's bailey). Note the worst place (and the browser's FPS meter if it has one). | | | |
| 6 | **Audio in a hidden tab**: switch to another tab for 30 s and back: the sound fades out within a fifth of a second and comes back; no burst, no crackle; the music did not race ahead. | | | |
| 7 | **Music without holes**: 60 s of a region's music while walking - any gap or crackle (the container hears holes on every slow frame of its software WebGL: is it clean here?). | | | |
| 8 | **Memory over a session**: the tab's memory after the title, after 10 minutes and after 30 minutes of the world (no steady climb); the page never reloads or crashes. | | | |
| 9 | **Saves stay**: close the browser, open the link again: Continue is offered and wakes the giant where it was. | | | |
| 10 | **A pad in the browser** (§6 rows 15 and 21). | | | |

On a machine with a GPU, also run the container's checks with their strict forms and keep the reports
(Node and Playwright installed; the release built with `tools/build_web.sh`): `node tools/web/audio_check.mjs
--strict`, `node tools/web/stream_check.mjs --world --audio --build=builds/web --strict` and `node tools/web/world_check.mjs
--strict` (the plan's music criterion - no silent run over 50 ms - is NOT RUN until then;
`docs/plans/FOLLOWUPS.md`). These strict runs are the ones that count: the container's default verdicts are
indicative only (they pass holes placed on the main thread's stalls - since W23 also a hole the recording's end
cut short - and under load they can fail on holes the placement misses). Write the results under the session in `docs/USABILITY_RESULTS.md` and the frame
and load times beside the reference-PC table in `docs/PERFORMANCE.md`.

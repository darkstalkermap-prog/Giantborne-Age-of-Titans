# Fix: the rim council at the Stone Throne (act two's first stage would not engage)

A fix lane on `pkg/fix-council` from `39dd72a` (the Web build with E1, "Harrok's return"). The version stays
**0.17.0-m17**; the save stays schema 3 and gains nothing. The decision is in `docs/DECISIONS.md` §3.13.

## The report

> Check into the last quest where you have to listen to the kings after you take the throne, there is a glitch where it
> wouldnt engage the quest and let me continue.

That is `quest.act_two_main`'s first stage, "Hear the oath-holders at the Stone Throne", done by
`act_two.council_heard`, which `dialogue.rim_council` sets when it is heard out.

## What the owner hit (reproduced)

Played as a player plays it in the real world (`scenes/world/world.tscn`, a screen stack, cutscenes on as in the Web
build): a stage-6 giant at the Stone Throne's marker takes the throne by E, the act-one finale plays (through, or
skipped), the "Act One" end screen's Continue, and act two's stage leads with its marker,
`world.marker.stone_throne` at (0, -786) - 14 m before the throne, where the giant already stands. There:

| Where the giant stands | Prompt before the fix | E before the fix |
| --- | --- | --- |
| at the marker, facing the throne (or the oath-stone, or anywhere within 78 degrees of the throne) | **"Take the Stone Throne"** (the throne, priority 30) | **"The Stone Throne is yours. The Old Kingdom has its Giant King."** - nothing else |
| at the marker facing west, toward the council's stone | none | nothing |
| 20 m south of the marker, in the ring | none | nothing |

The rim council is a separate speaking stone, `world.stonehold.rim_council` at (-30, -790): 30.3 m from the marker,
beyond its reach (16 m + the giant's capsule, 3.7 m at stage 6, 6.9 m at stage 9), set against the ring's wall west of
the throne with nothing to mark it. The taken throne kept offering its own prompt - "Take the Stone Throne", still
first by priority (30 against a talker's 40) - and answered E with its claimed line. So at the place the objective
names and marks, the only thing on offer was a dead prompt; the stage could never be heard unless the player happened
to walk 25 m west to a stone the tracker never pointed at. The same holds after a Continue from the save act two's
start writes (the `act_two` checkpoint), for every ending of Harrok's (slain, spared, the talk ending) and for a
colossus (stages 7-9) arriving at the marker from the ring's middle or its east side. The bots never saw it: the world
bot walks to the talker's own position and starts its dialogue directly (`_act_say`), and C1's tests check the talker
exists, not that the marker reaches it.

This is C1's, not E1's: the throne's priority and claimed line are P36's and the marker is act one's throne stage's,
reused by C1 for the council. E1 added a second misleading prompt beside the throne (below).

## Every contributing cause

1. **The marker leads to the throne, the talk was 30 m away.** The council stage reused act one's throne marker; the
   council's stone is out of reach from it at every stage.
2. **The taken throne swallowed E.** A claimed StoneThrone stayed a candidate with "Take the Stone Throne" and the
   highest priority at the throne; E gave only its claimed line.
3. **E1's oath-stone misled from act one's end.** `world.stonehold.throne_stone`, "Speak at the oath-stone" (22, -792),
   stands from the start; before the rumour of Harrok's banner it told a slain-Harrok giant that his sister's son "has
   come to take the throne back" (Orrik is not there yet) and a spared-Harrok giant to "go to his stone at the ring's
   gate" - to a player looking for the oath-holders, the wrong stone saying the wrong thing.
4. **(Robustness, not seen in play)** a begun act two with a pledge without its answer would leave the council's line
   for it with no choice but Leave - the stage could never be heard out.

Checked and not causes: the fetter-winches (they `appears_when` the rumour, `lead.harrok.hearth`: none stand at the
Moot in act two's start; winch 2 at (-32.5, -777.5) would sit 13 m from the council's stone only after the rumour);
ThroneChallenge (`challenge_open()` needs the rumour; before it the ring is act one's and engages nothing) and the
blocked checkpoints; `act.two.begun` (set before the end screen opens, by the finale's end or skip, and on the first
Continue of a save that quit during the finale - `test_act_one_finale`); leaving the dialogue early (Esc at any line
ends it unheard and it starts again from its first line; heard out it sets the flag and then offers "Hear them
again"); the talker's reach at the giant's sizes (talker radius plus the giant's capsule; nothing at the Moot scales
or hides it). In the real ring a spared Harrok stands south of the marker: a colossus walking straight up the ring's
middle meets him and walks round (not a blocker).

## What changed

- **The taken throne is where the council is heard** (`scripts/world/stone_throne.gd`). Once claimed and act two has
  begun, the throne's prompt is "Hear the oath-holders at the throne" and E opens `dialogue.rim_council` for
  `world.stonehold.rim_council` - the same talk as the council's stone, which stays where it was. It answers from any
  side within its reach without the giant facing it (`facing_free`), ahead of the oath-stone and the council's stone
  (its priority). Between the claim and act two's start (the finale) it offers nothing (`offered`). Before the claim it
  is "Take the Stone Throne" as before. No world data changed: the marker before the throne is now right.
- **Two Interactable hooks** (`scripts/world/interactable.gd`, `scripts/actors/player/player_interact.gd`):
  `offered(player)` (false: no candidate at all, read live, so a save loaded under it or a flag set quietly is seen at
  once) and `facing_free(player)` (true: PlayerInteract's front rule is skipped; the reach still holds). Both default
  to the old behaviour; only the throne overrides them.
- **The oath-stone is quiet before the rumour** (`data/dialogue/dialogue_moot_oath.json`): before `lead.harrok.hearth`
  and Orrik's fall it says no one speaks from it, and while the council waits it sends the giant to the throne. From the
  rumour on it is E1's as before.
- **A begun act two answers a pledge left unanswered** on entering the world (`ActTwo.answer_missing`, from
  `GameSession._on_level_entered_act_two`); a given answer never changes.
- **A save already stuck recovers on Continue** with nothing to migrate: the throne before its marker opens the council
  as soon as the world loads.

## Tests

| Suite | Tier | What | Before the fix |
| --- | --- | --- | --- |
| `tests/integration/test_council_at_throne.gd` | default (about 3 s) | the Moot's two chunks where the world has them: at the marker the taken throne opens the council for stages 6-9 facing six ways, beside the oath-stone too; nothing between the claim and act two; "Take the Stone Throne" before the claim; Esc mid-way strands nothing and heard out completes it; the oath-stone quiet before the rumour, pointing at the throne while the council waits; a missing pledge answered on entering the world | 66 of 104 checks fail |
| `tests/slow/test_council_after_the_throne.gd` | slow (about 25 s) | the report as played, in the real world with cutscenes on: slain (the finale played through), spared (skipped) - the throne taken by E at the marker, the end screen's Continue, the council's prompt there, E opens the dialogue screen, Esc leaves it unheard and the prompt comes back, heard out through the screen's buttons the Breach is next; the talk ending, then Continue from the save act two wrote; a colossus (7, 8, 9) walking to the marker from the ring's middle, its east side and the council's stone | every prompt and E check fails: "Take the Stone Throne", "The Stone Throne is yours" |

## Verification

- The new suites green; `test_council_at_throne` fails 66 checks and `test_council_after_the_throne` every prompt
  check on `39dd72a`'s code.
- Targeted: `test_act_two`, `test_act_one_finale`, `test_e1_story`, `test_e1_fetters`, `test_npc_talker`,
  `test_interact_seam`, `test_player_components`, `test_e1_heir` (slow), `test_c1_world`, `test_stonehold_walkthrough`
  and `test_c1_act_two` (gate: the world bot hears the council and climbs the Breach): 12 suites, 763 checks, 0
  failures (with `test_council_after_the_throne`).
- The default tier: 256 suites, one failure that is `39dd72a`'s own (`test_web_presets`: "the first press resumes the
  sound", the game page's sound commit; it fails the same with this lane's changes stashed); 70.4 s under a shared,
  niced machine (budget 75 s).

## What is weak

- The council's stone west of the throne is still where C1 put it, against the ring's wall with nothing marking it; it
  is now a second way in, not the way the tracker leads.
- The throne answers every later visit with the council's "heard" line ("The oath-holders have spoken") - true, but
  the throne has nothing of its own to say after act two's start.
- No human playtest and no rendered still of the prompt: judged by the headless flow, the prompts it read and the
  dialogue screen it drove.

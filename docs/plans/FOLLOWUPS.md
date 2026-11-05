# Follow-ups from milestone reviews

Minor findings that a milestone review confirmed but did not fix. Each one names the package
that owns the files involved. That package fixes its items (with a regression test) as part of
its own work and reports it.

## From the M2 gate review (wave 1)

| Item | Owner | Notes |
| --- | --- | --- |
| Runic Bolt locked onto a target beyond 25 m fizzles, while the hotbar shows it as ready and names the target. The hotbar should show "Out of range" (or the cast should not be accepted). | P16 (UX pass) | `scripts/actors/player/player_attack.gd`, the hotbar's `preview_reason` path |
| Titan Surge's +25% poise damage does not apply to the poise damage that the player's parry deals. | P11a (owns `combat_entity.gd` in W6) | `scripts/combat/combat_entity.gd` |
| Wolves never show status tints (for example Thunder Roar's slow), because `QuadrupedRig` is not an `ActorRig` and HitFeedback only tints `ActorRig`s. | P09 (telegraph visuals) | `scripts/presentation/hit_feedback.gd`, `scripts/presentation/quadruped_rig.gd` |

## From the M3 gate review (wave 3)

| Item | Owner | Notes |
| --- | --- | --- |
| Crushing Grip spends 20 stamina and starts its 10 s cooldown when the grab fails the recheck at attachment. Spec §15 says invalid grabs spend nothing: refund (or never charge) a grab that fails the attachment recheck. | P16 | `scripts/actors/player/player_grab.gd` |
| The growth clearance check ignores the actors layer, so the new capsule can grow into a static dummy or a nearby enemy. Include actors (or push them clear) and keep "blocked growth changes nothing". | P16 | `scripts/actors/player/player_growth.gd` |
| The growth "combat" gate counts only hits from the last 10 s, so an aware enemy closing in does not block growth although the refusal text says "Enemies are near". Gate on aware enemies within the shrine radius as well. | P16 | `scripts/actors/player/player_growth.gd` |
| A schema-valid but otherwise invalid main save is copied over the only valid backup on the next checkpoint. Only back up a main file that fully loads. | P16 | `scripts/core/save_io.gd`, `scripts/core/save_slots.gd` |
| `--mode=valley --new-game` overwrites a newer build's save without keeping the rejected copy (the title screen path keeps it). | P16 | `scripts/core/game_session.gd` |
| Loading a checkpoint from the pause menu (or F9) while dead skips the death floor (60% health, full stamina). | P16 | `scripts/core/game_session.gd` |
| Quit to title keeps `level_override` from a Continue, so Sandbox and New Game then load the saved test level. | P16 | `scripts/core/game_session.gd` |

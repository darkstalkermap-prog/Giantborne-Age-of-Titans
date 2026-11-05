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

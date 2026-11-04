class_name SoldierBrain
extends EnemyBrain
## Finite-state AI for the melee Soldier archetype (spec section 10).
##
## Soldier tactics: guard the front (SoldierEnemy raises its guard while aware and not
## striking), approach the giant's legs, pause between strikes. At most `max_attackers`
## enemies hold attack tokens on one target; the rest reposition. Outmatched (a giant at least
## tactics.outmatched_ratio times taller) they hold formation: HOLD at a formation marker or in
## an ad-hoc line, guard up, striking only what steps into reach. All of it is the shared
## EnemyBrain behaviour; this class keeps the soldier's name, fields and
## SoldierBrain.AIState.* (inherited) for the scenes, tests and debug tools that use them.

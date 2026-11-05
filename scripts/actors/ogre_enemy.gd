class_name OgreEnemy
extends EnemyActor
## Ogre (enemy.ogre, the fifth role; spec 10, plan §3.12 design 1, §4.4): a 3.4 m brute with the
## shared EnemyActor glue and an OgreBrain. Its two strikes are pulses that match their telegraphs
## exactly - the smash a circle round the ogre (r 3.5 m), the sweep a 120 degree sector in front -
## behind windups of 1.0 / 0.9 s, with super armour (light blows and even a broken poise do not
## stop the strike) and a long recovery (1.2 / 1.1 s) that is the punish window: super armour does
## not cover it and poise taken there counts x3.5 (poise 120: one stage-1 heavy staggers it). It
## turns slowly (90 degrees/s), walks on the large nav layer (2), ignores morale and fear, and a
## stage-3 giant can grab it with both hands (mass medium, grab_attach two_hand, Anchors/Grab at
## the chest). Anchors/{Torso,KneeL,KneeR} are its lock anchors (CombatEntity.lock_anchors).


func _make_brain() -> EnemyBrain:
	return OgreBrain.new(entity.entity_id, record, Sim.DEFAULT_SEED ^ hash(entity.entity_id))


## The ActorRig keys; while a strike runs with super armour "armored" is true (presentation).
func get_rig_state() -> Dictionary:
	var s := super()
	var a := controller.action
	s["armored"] = a != null and a.interrupt_policy == "super_armor" \
		and controller.phase() != ActionDef.Phase.RECOVERY
	return s

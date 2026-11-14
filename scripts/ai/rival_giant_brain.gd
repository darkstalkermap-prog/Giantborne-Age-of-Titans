class_name RivalGiantBrain
extends OgreBossBrain
## A rival giant (plan M6-M9 §2.10; P34): the boss framework's sequences (EnemyBrain P11a) through
## OgreBossBrain - each entry struck inside its ai band when its facing rule allows (a circle all
## round, a line within 45 degrees, a cone in front), else closed on or backed off for up to 2 s and
## skipped. Its combo chains (queue_chain_next), its boulder is a lob that needs no facing beyond the
## line's, and the shoulder charge turns in its windup. A plain rival giant has one phase ("fight");
## Harrok's brain (HarrokBrain) adds the second phase's arena hazards. Ignores morale; immune to Grab
## and Fear (its record).


func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	super(p_actor_id, record, seed_value)
